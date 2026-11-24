import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

/// Режим захвата входного аудиопотока (Раздел 2.2 ТЗ).
public enum DSPInputCaptureMode: String, CaseIterable, Sendable, Codable {
    case processTap = "process_tap"       // Mode A: CoreAudio Process Tap (CATapDescription, com.apple.Music)
    case loopbackDevice = "loopback"      // Mode B: Virtual Loopback HAL Input (BlackHole 2ch / Loopback)
    case localFile = "local_file"         // Mode C: Прямой декодер локальных файлов (WAV/AIFF/FLAC/ALAC/DSF/DFF)
}

/// Захват входного потока с виртуального Loopback-устройства (`BlackHole 2ch`, `Loopback Audio`)
/// через низкоуровневый `AudioDeviceCreateIOProcID` без аллокаций в RT-коллбэке.
public final class LoopbackAudioCaptureSession: @unchecked Sendable {
    private var deviceID: AudioDeviceID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    public let captureRingBuffer: SPSCStereoFloatRingBuffer
    public private(set) var inputSampleRateHz: Int = 44_100
    public private(set) var isRunning: Bool = false

    public init(captureRingBuffer: SPSCStereoFloatRingBuffer) {
        self.captureRingBuffer = captureRingBuffer
    }

    deinit {
        stop()
    }

    public func start(preferredDeviceUID: String? = nil) -> Bool {
        stop()

        let resolvedID: AudioDeviceID
        if let uid = preferredDeviceUID, !uid.isEmpty, let id = HALDeviceManager.findDeviceID(byUID: uid) {
            resolvedID = id
        } else if let autoLoopback = Self.findLoopbackInputDevice() {
            resolvedID = autoLoopback
        } else {
            return false
        }

        self.deviceID = resolvedID
        let nomRate = Int(HALDeviceManager.nominalSampleRate(deviceID: resolvedID).rounded())
        if nomRate > 0 {
            self.inputSampleRateHz = nomRate
        }

        let unmanagedSelf = Unmanaged.passUnretained(self).toOpaque()
        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcID(
            resolvedID,
            { _, _, inInputData, _, _, _, inClientData -> OSStatus in
                guard let inClientData else { return noErr }
                let session = Unmanaged<LoopbackAudioCaptureSession>.fromOpaque(inClientData).takeUnretainedValue()
                let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
                guard abl.count > 0 else { return noErr }

                if abl.count >= 2,
                   let ptrL = abl[0].mData?.assumingMemoryBound(to: Float.self),
                   let ptrR = abl[1].mData?.assumingMemoryBound(to: Float.self) {
                    let frames = Int(abl[0].mDataByteSize) / MemoryLayout<Float>.stride
                    _ = session.captureRingBuffer.writePlanar(left: ptrL, right: ptrR, frames: frames)
                } else if let ptr = abl[0].mData?.assumingMemoryBound(to: Float.self) {
                    let channels = max(1, Int(abl[0].mNumberChannels))
                    let frames = Int(abl[0].mDataByteSize) / (MemoryLayout<Float>.stride * channels)
                    _ = session.captureRingBuffer.writeInterleaved(ptr, frames: frames, channels: channels)
                }
                return noErr
            },
            unmanagedSelf,
            &procID
        )

        guard status == noErr, let procID else {
            self.deviceID = kAudioObjectUnknown
            return false
        }

        self.ioProcID = procID
        let startStatus = AudioDeviceStart(resolvedID, procID)
        if startStatus == noErr {
            isRunning = true
            return true
        } else {
            AudioDeviceDestroyIOProcID(resolvedID, procID)
            self.ioProcID = nil
            self.deviceID = kAudioObjectUnknown
            return false
        }
    }

    public func stop() {
        if let procID = ioProcID, deviceID != kAudioObjectUnknown {
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
        }
        ioProcID = nil
        deviceID = kAudioObjectUnknown
        isRunning = false
    }

    public static func findLoopbackInputDevice() -> AudioDeviceID? {
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propAddr,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize > 0 else {
            return nil
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.stride
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propAddr,
            0,
            nil,
            &dataSize,
            &ids
        ) == noErr else {
            return nil
        }

        for id in ids {
            let name = HALDeviceManager.deviceName(deviceID: id).lowercased()
            if name.contains("blackhole") || name.contains("loopback") || name.contains("soundflower") {
                return id
            }
        }
        return nil
    }
}

/// Прямой декодер локальных файлов (`WAV`, `AIFF`, `FLAC`, `ALAC`, `DSF`, `DFF`) для верификации
/// и эталонного воспроизведения (Mode C ТЗ).
public final class LocalAudioFileSource: @unchecked Sendable {
    public enum FileKind: Sendable {
        case pcm(AVAudioFile)
        case dsf(url: URL, sampleRateHz: Int, dataOffset: UInt64, dataSize: UInt64, blockSizePerChannel: Int)
    }

    public private(set) var sampleRateHz: Int = 44_100
    public private(set) var isNativeDSD: Bool = false

    private var fileKind: FileKind?
    private var pcmScratchBuffer: AVAudioPCMBuffer?
    private var dsfFileHandle: FileHandle?
    private var dsfBytesRead: UInt64 = 0
    private var dsfLeftMSB: [UInt8] = []
    private var dsfRightMSB: [UInt8] = []
    private var dsfPackedWords: [Int32] = []

    /// Таблица разворота битов байта (`LSB-first` в формате Sony `.dsf` -> `MSB-first` для упаковки DoP).
    @usableFromInline
    internal static let bitReverseTable: [UInt8] = (0..<256).map { byte in
        var v = UInt8(byte)
        var r: UInt8 = 0
        for _ in 0..<8 {
            r = (r << 1) | (v & 1)
            v >>= 1
        }
        return r
    }

    public init() {}

    deinit {
        close()
    }

    public func open(url: URL) throws {
        close()
        let ext = url.pathExtension.lowercased()
        if ext == "dsf" {
            try openDSF(url: url)
        } else {
            let audioFile = try AVAudioFile(
                forReading: url,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            self.sampleRateHz = Int(audioFile.processingFormat.sampleRate.rounded())
            self.isNativeDSD = false
            self.pcmScratchBuffer = AVAudioPCMBuffer(
                pcmFormat: audioFile.processingFormat,
                frameCapacity: 4096
            )
            self.fileKind = .pcm(audioFile)
        }
    }

    public func close() {
        try? dsfFileHandle?.close()
        dsfFileHandle = nil
        pcmScratchBuffer = nil
        fileKind = nil
        dsfBytesRead = 0
    }

    private func openDSF(url: URL) throws {
        let fh = try FileHandle(forReadingFrom: url)
        guard let header = try fh.read(upToCount: 92), header.count >= 92 else {
            try? fh.close()
            throw NSError(domain: "LocalAudioFileSource", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid DSF header"])
        }

        // Проверяем сигнатуру 'DSD ' и 'fmt '
        let magicDSD = String(decoding: header[0..<4], as: UTF8.self)
        let magicFmt = String(decoding: header[28..<32], as: UTF8.self)
        guard magicDSD == "DSD " && magicFmt == "fmt " else {
            try? fh.close()
            throw NSError(domain: "LocalAudioFileSource", code: -2, userInfo: [NSLocalizedDescriptionKey: "Corrupt DSF magic"])
        }

        let sampleRate = header.withUnsafeBytes { raw -> Int in
            Int(raw.loadUnaligned(fromByteOffset: 56, as: UInt32.self).littleEndian)
        }
        let blockSize = header.withUnsafeBytes { raw -> Int in
            Int(raw.loadUnaligned(fromByteOffset: 68, as: UInt32.self).littleEndian)
        }
        let dataSize = header.withUnsafeBytes { raw -> UInt64 in
            let chunkTotal = raw.loadUnaligned(fromByteOffset: 84, as: UInt64.self).littleEndian
            return chunkTotal > 12 ? (chunkTotal - 12) : 0
        }

        let validBlockSize = (blockSize >= 2 && (blockSize & 1) == 0) ? blockSize : 4096
        let blockFrames = validBlockSize / 2
        self.dsfLeftMSB = [UInt8](repeating: 0, count: validBlockSize)
        self.dsfRightMSB = [UInt8](repeating: 0, count: validBlockSize)
        self.dsfPackedWords = [Int32](repeating: 0, count: blockFrames * 2)

        self.dsfFileHandle = fh
        self.dsfBytesRead = 0
        self.sampleRateHz = max(2_822_400, sampleRate)
        self.isNativeDSD = true
        self.fileKind = .dsf(
            url: url,
            sampleRateHz: self.sampleRateHz,
            dataOffset: 92,
            dataSize: dataSize,
            blockSizePerChannel: validBlockSize
        )
    }

    /// Читает следующую порцию PCM-кадров в кольцевой буфер захвата.
    public func readNextPCMChunk(into ringBuffer: SPSCStereoFloatRingBuffer, maxFrames: Int = 1024) -> Int {
        guard case .pcm(let audioFile) = fileKind else { return 0 }
        let pcmBuf: AVAudioPCMBuffer
        if let scratch = pcmScratchBuffer, Int(scratch.frameCapacity) >= maxFrames {
            scratch.frameLength = 0
            pcmBuf = scratch
        } else if let allocated = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: AVAudioFrameCount(max(maxFrames, 4096))
        ) {
            self.pcmScratchBuffer = allocated
            pcmBuf = allocated
        } else {
            return 0
        }

        do {
            try audioFile.read(into: pcmBuf, frameCount: AVAudioFrameCount(maxFrames))
        } catch {
            return 0
        }

        let frames = Int(pcmBuf.frameLength)
        guard frames > 0, let channelData = pcmBuf.floatChannelData else { return 0 }
        let chCount = Int(audioFile.processingFormat.channelCount)
        let leftPtr = channelData[0]
        let rightPtr = chCount > 1 ? channelData[1] : channelData[0]
        return ringBuffer.writePlanar(left: leftPtr, right: rightPtr, frames: frames)
    }

    /// Читает следующую порцию нативного 1-битного потока Sony `.dsf` (планарные блоки L + R, `LSB-first`),
    /// разворачивает порядок битов в `MSB-first` по предвычисленной таблице и упаковывает напрямую в `S32_LE` DoP-слова
    /// в `ringBuffer` без промежуточной децимации в PCM (Mode C ТЗ).
    ///
    /// - Returns: Количество упакованных и записанных стерео-фреймов DoP.
    public func readNextDSFDoPWords(
        into ringBuffer: SPSCAtomicRingBuffer,
        dopPackerState: inout DoPPackerState,
        maxDoPFrames: Int = 4096
    ) -> Int {
        guard case .dsf(_, _, _, let dataSize, let blockSizePerChannel) = fileKind,
              let fh = dsfFileHandle else {
            return 0
        }

        let blockFrames = max(1, blockSizePerChannel / 2) // 2 байта DSD (16 бит) на канал = 1 DoP фрейм
        var totalWrittenFrames = 0

        while totalWrittenFrames + blockFrames <= maxDoPFrames && ringBuffer.availableToWrite >= blockFrames * 2 {
            let remainingDataBytes = dataSize > dsfBytesRead ? Int(min(UInt64(Int.max), dataSize - dsfBytesRead)) : 0
            let pairBytes = blockSizePerChannel * 2
            guard remainingDataBytes >= pairBytes else { break }

            guard let rawPair = try? fh.read(upToCount: pairBytes), rawPair.count == pairBytes else {
                break
            }
            dsfBytesRead &+= UInt64(pairBytes)

            rawPair.withUnsafeBytes { rawBuf in
                guard let base = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                for i in 0..<blockSizePerChannel {
                    dsfLeftMSB[i] = Self.bitReverseTable[Int(base[i])]
                    dsfRightMSB[i] = Self.bitReverseTable[Int(base[blockSizePerChannel + i])]
                }
            }

            dsfLeftMSB.withUnsafeBufferPointer { lPtr in
                dsfRightMSB.withUnsafeBufferPointer { rPtr in
                    dsfPackedWords.withUnsafeMutableBufferPointer { outPtr in
                        DoPPackerState.packStereoDSDBytesToDoP32(
                            state: &dopPackerState,
                            dsdLeftBytes: lPtr.baseAddress!,
                            dsdRightBytes: rPtr.baseAddress!,
                            dopFrameCount: blockFrames,
                            interleavedOutput: outPtr.baseAddress!
                        )
                    }
                }
            }

            let writtenWords = dsfPackedWords.withUnsafeBufferPointer { buf in
                ringBuffer.write(from: buf.baseAddress!, count: blockFrames * 2)
            }
            totalWrittenFrames += writtenWords / 2
            if writtenWords < blockFrames * 2 {
                break
            }
        }

        return totalWrittenFrames
    }
}
