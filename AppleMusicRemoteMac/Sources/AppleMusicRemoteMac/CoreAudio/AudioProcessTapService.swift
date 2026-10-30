//
//  AudioProcessTapService.swift
//  AppleMusicRemoteMac
//
//  High-Resolution CoreAudio Process Tap Service for Apple Music
//  Captures real-time uncompressed PCM audio from Music.app (up to 24-bit / 192 kHz)
//  and feeds it to network streamers (BluOS / DLNA / UPnP).
//

import Foundation
import CoreAudio
import AppKit

public final class AudioProcessTapService: @unchecked Sendable {
    public static let shared = AudioProcessTapService()

    private let queue = DispatchQueue(label: "org.ksholokhov.amr.audiotap", qos: .userInteractive)
    
    // CoreAudio objects
    private var tapObjectID: AudioObjectID = 0
    private var aggregateDeviceID: AudioObjectID = 0
    private var ioProcID: AudioDeviceIOProcID?
    
    // Stream parameters
    public private(set) var sampleRate: Int = 44100
    public let channels: Int = 2
    public private(set) var bitDepth: Int = 16
    public var bitsPerSample: Int { bitDepth }
    public var bytesPerFrame: Int { channels * (bitDepth / 8) }

    public private(set) var isCapturing: Bool = false
    
    // Subscriber callbacks: (UUID, (Data) -> Void)
    private var subscribers: [UUID: (Data) -> Void] = [:]
    
    // Audio buffering & silence generation
    private var chunkAccumulator = Data()
    private var targetChunkFrameCount: Int {
        // Target ~50ms of audio at current sample rate
        return max(512, sampleRate / 20)
    }
    private var lastAudioReceivedTime: Date = Date.distantPast
    private var silenceTimer: DispatchSourceTimer?
    private let silenceLock = NSLock()

    private init() {}

    deinit {
        stopCapture()
    }

    // MARK: - Subscriber Management

    public func addSubscriber(id: UUID, onAudioChunk: @escaping (Data) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.subscribers[id] = onAudioChunk
            NSLog("[AudioProcessTapService] 🎧 Added stream subscriber \(id). Total active: \(self.subscribers.count)")
            if !self.isCapturing {
                self.startCaptureInternal()
            }
        }
    }

    public func removeSubscriber(id: UUID) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.subscribers.removeValue(forKey: id)
            NSLog("[AudioProcessTapService] 🔌 Removed stream subscriber \(id). Remaining: \(self.subscribers.count)")
            if self.subscribers.isEmpty {
                // Keep capture running for a 3-second grace period in case streamer re-requests
                self.queue.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    guard let self = self else { return }
                    if self.subscribers.isEmpty && self.isCapturing {
                        NSLog("[AudioProcessTapService] No subscribers remaining. Stopping tap capture.")
                        self.stopCaptureInternal()
                    }
                }
            }
        }
    }

    public var hasSubscribers: Bool {
        return queue.sync { !subscribers.isEmpty }
    }

    // MARK: - Capture Control

    public func startCapture() {
        queue.async { [weak self] in
            self?.startCaptureInternal()
        }
    }

    public func stopCapture() {
        queue.async { [weak self] in
            self?.stopCaptureInternal()
        }
    }

    public func setFormat(sampleRate: Int? = nil, bitDepth: Int? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            var formatChanged = false
            if let r = sampleRate, r > 0, r != self.sampleRate {
                NSLog("[AudioProcessTapService] 🎛️ Switching tap sample rate to \(r) Hz (was \(self.sampleRate) Hz)")
                self.sampleRate = r
                formatChanged = true

                if self.aggregateDeviceID != 0 {
                    var rateAddr = AudioObjectPropertyAddress(
                        mSelector: kAudioDevicePropertyNominalSampleRate,
                        mScope: kAudioObjectPropertyScopeGlobal,
                        mElement: kAudioObjectPropertyElementMain
                    )
                    var newRate: Float64 = Float64(r)
                    let rateSize = UInt32(MemoryLayout<Float64>.size)
                    let status = AudioObjectSetPropertyData(self.aggregateDeviceID, &rateAddr, 0, nil, rateSize, &newRate)
                    if status == noErr {
                        NSLog("[AudioProcessTapService] ✅ Aggregate device nominal sample rate switched to \(r) Hz")
                    } else {
                        NSLog("[AudioProcessTapService] ⚠️ Failed to set nominal sample rate on aggregate device: \(status)")
                    }
                }
            }
            if let b = bitDepth, (b == 16 || b == 24), b != self.bitDepth {
                NSLog("[AudioProcessTapService] 🎛️ Switching tap bit depth to \(b)-bit (was \(self.bitDepth)-bit)")
                self.bitDepth = b
                formatChanged = true
            }
            if formatChanged {
                self.chunkAccumulator.removeAll()
            }
        }
    }

    public func setSampleRate(_ rate: Int) {
        setFormat(sampleRate: rate)
    }

    public func setBitDepth(_ depth: Int) {
        setFormat(bitDepth: depth)
    }

    private func startCaptureInternal() {
        guard !isCapturing else { return }

        guard #available(macOS 14.2, *) else {
            NSLog("[AudioProcessTapService] ⚠️ CoreAudio Process Tap requires macOS 14.2+. Running silence generator fallback.")
            startSilenceGenerator()
            isCapturing = true
            return
        }

        // Find Music.app PID
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
        guard let musicApp = apps.first else {
            NSLog("[AudioProcessTapService] ⚠️ Music.app is not running. Cannot create process tap.")
            startSilenceGenerator()
            isCapturing = true
            return
        }

        let pid = musicApp.processIdentifier
        NSLog("[AudioProcessTapService] 🔍 Found Music.app (PID: \(pid)). Querying CoreAudio process objects...")

        var musicAudioObjectID: AudioObjectID? = nil
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize)
        if status == noErr && dataSize > 0 {
            let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
            var processIDs = [AudioObjectID](repeating: 0, count: count)
            status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &processIDs)
            if status == noErr {
                for objID in processIDs {
                    var pidAddr = AudioObjectPropertyAddress(
                        mSelector: kAudioProcessPropertyPID,
                        mScope: kAudioObjectPropertyScopeGlobal,
                        mElement: kAudioObjectPropertyElementMain
                    )
                    var objPID: pid_t = 0
                    var pidSize = UInt32(MemoryLayout<pid_t>.size)
                    if AudioObjectGetPropertyData(objID, &pidAddr, 0, nil, &pidSize, &objPID) == noErr {
                        if objPID == pid {
                            musicAudioObjectID = objID
                            break
                        }
                    }
                }
            }
        }

        guard let objID = musicAudioObjectID else {
            NSLog("[AudioProcessTapService] ⚠️ Music.app audio object not found in HAL list yet. Running silence generator fallback.")
            startSilenceGenerator()
            isCapturing = true
            return
        }

        NSLog("[AudioProcessTapService] 🎯 Found CoreAudio process object ID: \(objID) for Music.app")
        let tapDesc = CATapDescription(stereoMixdownOfProcesses: [objID])
        tapDesc.name = "AMR Live Tap"
        tapDesc.muteBehavior = .muted

        var newTapID: AudioObjectID = 0
        let tapStatus = AudioHardwareCreateProcessTap(tapDesc, &newTapID)
        guard tapStatus == noErr else {
            NSLog("[AudioProcessTapService] ❌ AudioHardwareCreateProcessTap failed with OSStatus \(tapStatus)")
            startSilenceGenerator()
            isCapturing = true
            return
        }
        self.tapObjectID = newTapID
        NSLog("[AudioProcessTapService] ✅ Process Tap created successfully (AudioObjectID: \(newTapID))")

        // Retrieve Tap UID
        var uidAddr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var tapUIDRef: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let uidStatus = AudioObjectGetPropertyData(newTapID, &uidAddr, 0, nil, &uidSize, &tapUIDRef)
        guard uidStatus == noErr, let tapUID = tapUIDRef?.takeRetainedValue() as String? else {
            NSLog("[AudioProcessTapService] ❌ Failed to get tap UID: \(uidStatus)")
            AudioHardwareDestroyProcessTap(newTapID)
            self.tapObjectID = 0
            return
        }

        // Create Private Aggregate Device
        let aggDict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AMR Tap Aggregate",
            kAudioAggregateDeviceUIDKey: "AMR-Tap-Aggregate-\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID
                ]
            ]
        ]

        var newAggID: AudioObjectID = 0
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDict as CFDictionary, &newAggID)
        guard aggStatus == noErr else {
            NSLog("[AudioProcessTapService] ❌ AudioHardwareCreateAggregateDevice failed: \(aggStatus)")
            AudioHardwareDestroyProcessTap(newTapID)
            self.tapObjectID = 0
            return
        }
        self.aggregateDeviceID = newAggID
        NSLog("[AudioProcessTapService] ✅ Aggregate Device created (AudioObjectID: \(newAggID))")

        // Configure Aggregate Nominal Sample Rate
        var rateAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var targetRate = Float64(self.sampleRate)
        let rateSize = UInt32(MemoryLayout<Float64>.size)
        let rateStatus = AudioObjectSetPropertyData(newAggID, &rateAddr, 0, nil, rateSize, &targetRate)
        if rateStatus == noErr {
            NSLog("[AudioProcessTapService] ✅ Aggregate device nominal sample rate set to \(self.sampleRate) Hz")
        } else {
            NSLog("[AudioProcessTapService] ⚠️ Failed to set aggregate nominal sample rate to \(self.sampleRate) Hz: \(rateStatus)")
        }

        var actualRate: Float64 = 0
        var actualSize = UInt32(MemoryLayout<Float64>.size)
        if AudioObjectGetPropertyData(newAggID, &rateAddr, 0, nil, &actualSize, &actualRate) == noErr && actualRate > 0 {
            self.sampleRate = Int(round(actualRate))
        }
        NSLog("[AudioProcessTapService] 🎛️ Tap active rate: \(self.sampleRate) Hz, channels: \(self.channels), bits: \(self.bitsPerSample)")

        // Setup IOProc Callback
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let ioCallback: AudioDeviceIOProc = { (deviceID, inNow, inInputData, inInputTime, outOutputData, inOutputTime, inClientData) -> OSStatus in
            guard let clientData = inClientData else { return noErr }
            let service = Unmanaged<AudioProcessTapService>.fromOpaque(clientData).takeUnretainedValue()
            service.processCoreAudioInput(inInputData: inInputData)
            return noErr
        }

        var newProcID: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcID(newAggID, ioCallback, selfPtr, &newProcID)
        guard procStatus == noErr, let procID = newProcID else {
            NSLog("[AudioProcessTapService] ❌ AudioDeviceCreateIOProcID failed: \(procStatus)")
            AudioHardwareDestroyAggregateDevice(newAggID)
            AudioHardwareDestroyProcessTap(newTapID)
            self.aggregateDeviceID = 0
            self.tapObjectID = 0
            return
        }
        self.ioProcID = procID

        let startStatus = AudioDeviceStart(newAggID, procID)
        if startStatus == noErr {
            self.isCapturing = true
            NSLog("[AudioProcessTapService] 🚀 Audio capture started successfully at \(self.sampleRate) Hz 24-bit")
        } else {
            NSLog("[AudioProcessTapService] ❌ AudioDeviceStart failed: \(startStatus)")
        }

        startSilenceGenerator()
    }

    private func stopCaptureInternal() {
        guard isCapturing else { return }
        stopSilenceGenerator()

        if let procID = ioProcID, aggregateDeviceID != 0 {
            AudioDeviceStop(aggregateDeviceID, procID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            self.ioProcID = nil
        }

        if aggregateDeviceID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            self.aggregateDeviceID = 0
        }

        if #available(macOS 14.2, *) {
            if tapObjectID != 0 {
                AudioHardwareDestroyProcessTap(tapObjectID)
                self.tapObjectID = 0
            }
        }

        self.isCapturing = false
        self.chunkAccumulator.removeAll()
        NSLog("[AudioProcessTapService] 🛑 Audio capture stopped and resources released.")
    }

    // MARK: - CoreAudio Audio Processing

    private func processCoreAudioInput(inInputData: UnsafePointer<AudioBufferList>) {
        let bufferList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
        guard !bufferList.isEmpty else { return }

        let currentDepth = self.bitDepth
        let currentBytesPerFrame = self.channels * (currentDepth / 8)

        var convertedData: Data

        if bufferList.count >= 2, let leftData = bufferList[0].mData, let rightData = bufferList[1].mData {
            // Non-interleaved stereo (Buffer 0: Left, Buffer 1: Right)
            let frameCount = Int(bufferList[0].mDataByteSize) / MemoryLayout<Float>.size
            guard frameCount > 0 else { return }

            let leftPtr = leftData.assumingMemoryBound(to: Float.self)
            let rightPtr = rightData.assumingMemoryBound(to: Float.self)

            convertedData = Data(count: frameCount * currentBytesPerFrame)
            convertedData.withUnsafeMutableBytes { (rawBuf: UnsafeMutableRawBufferPointer) in
                guard let dstPtr = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                var dstIdx = 0
                if currentDepth == 16 {
                    for i in 0..<frameCount {
                        // Left channel
                        let leftFloat = max(-1.0, min(1.0, leftPtr[i]))
                        let leftInt16 = Int16(round(leftFloat * 32767.0))
                        dstPtr[dstIdx] = UInt8(leftInt16 & 0xFF)
                        dstPtr[dstIdx + 1] = UInt8((leftInt16 >> 8) & 0xFF)
                        dstIdx += 2

                        // Right channel
                        let rightFloat = max(-1.0, min(1.0, rightPtr[i]))
                        let rightInt16 = Int16(round(rightFloat * 32767.0))
                        dstPtr[dstIdx] = UInt8(rightInt16 & 0xFF)
                        dstPtr[dstIdx + 1] = UInt8((rightInt16 >> 8) & 0xFF)
                        dstIdx += 2
                    }
                } else {
                    for i in 0..<frameCount {
                        // Left channel
                        let leftFloat = max(-1.0, min(1.0, leftPtr[i]))
                        let leftInt32 = Int32(round(leftFloat * 8388607.0))
                        dstPtr[dstIdx] = UInt8(leftInt32 & 0xFF)
                        dstPtr[dstIdx + 1] = UInt8((leftInt32 >> 8) & 0xFF)
                        dstPtr[dstIdx + 2] = UInt8((leftInt32 >> 16) & 0xFF)
                        dstIdx += 3

                        // Right channel
                        let rightFloat = max(-1.0, min(1.0, rightPtr[i]))
                        let rightInt32 = Int32(round(rightFloat * 8388607.0))
                        dstPtr[dstIdx] = UInt8(rightInt32 & 0xFF)
                        dstPtr[dstIdx + 1] = UInt8((rightInt32 >> 8) & 0xFF)
                        dstPtr[dstIdx + 2] = UInt8((rightInt32 >> 16) & 0xFF)
                        dstIdx += 3
                    }
                }
            }
        } else if let firstBuffer = bufferList.first, let rawData = firstBuffer.mData {
            // Interleaved stereo (Buffer 0: L, R, L, R...)
            let floatCount = Int(firstBuffer.mDataByteSize) / MemoryLayout<Float>.size
            guard floatCount > 0 else { return }

            let floatPtr = rawData.assumingMemoryBound(to: Float.self)
            let frameCount = floatCount / channels

            convertedData = Data(count: frameCount * currentBytesPerFrame)
            convertedData.withUnsafeMutableBytes { (rawBuf: UnsafeMutableRawBufferPointer) in
                guard let dstPtr = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                var dstIdx = 0
                if currentDepth == 16 {
                    for i in 0..<floatCount {
                        let sampleFloat = max(-1.0, min(1.0, floatPtr[i]))
                        let sampleInt16 = Int16(round(sampleFloat * 32767.0))
                        dstPtr[dstIdx] = UInt8(sampleInt16 & 0xFF)
                        dstPtr[dstIdx + 1] = UInt8((sampleInt16 >> 8) & 0xFF)
                        dstIdx += 2
                    }
                } else {
                    for i in 0..<floatCount {
                        let sampleFloat = max(-1.0, min(1.0, floatPtr[i]))
                        let sampleInt32 = Int32(round(sampleFloat * 8388607.0))
                        dstPtr[dstIdx] = UInt8(sampleInt32 & 0xFF)
                        dstPtr[dstIdx + 1] = UInt8((sampleInt32 >> 8) & 0xFF)
                        dstPtr[dstIdx + 2] = UInt8((sampleInt32 >> 16) & 0xFF)
                        dstIdx += 3
                    }
                }
            }
        } else {
            return
        }

        silenceLock.lock()
        lastAudioReceivedTime = Date()
        silenceLock.unlock()

        dispatchAudioChunk(convertedData)
    }

    private func dispatchAudioChunk(_ data: Data) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.chunkAccumulator.append(data)

            // When accumulated ~50ms of audio, dispatch to subscribers
            let targetBytes = self.targetChunkFrameCount * self.bytesPerFrame
            while self.chunkAccumulator.count >= targetBytes {
                let chunk = self.chunkAccumulator.prefix(targetBytes)
                self.chunkAccumulator.removeFirst(targetBytes)
                for callback in self.subscribers.values {
                    callback(Data(chunk))
                }
            }
        }
    }

    // MARK: - Silence Fallback Generator

    private func startSilenceGenerator() {
        stopSilenceGenerator()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // Fire every 50ms
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let now = Date()
            self.silenceLock.lock()
            let timeSinceLastAudio = now.timeIntervalSince(self.lastAudioReceivedTime)
            self.silenceLock.unlock()

            // If no real CoreAudio frames received for > 200ms (paused or stopped),
            // inject 50ms of silence frames so connected streamers don't buffer-underrun.
            if timeSinceLastAudio > 0.20 {
                let silenceFrameCount = self.sampleRate / 20 // 50ms
                let silenceBytes = silenceFrameCount * self.bytesPerFrame
                let silenceData = Data(repeating: 0, count: silenceBytes)
                for callback in self.subscribers.values {
                    callback(silenceData)
                }
            }
        }
        timer.resume()
        self.silenceTimer = timer
    }

    private func stopSilenceGenerator() {
        silenceTimer?.cancel()
        silenceTimer = nil
    }

    // MARK: - WAV Header Helper

    public func makeWAVHeader(sampleRate: Int? = nil, bitDepth: Int? = nil, dataLength: UInt32 = 0x7FFFFFFF - 36) -> Data {
        let effectiveRate = sampleRate ?? self.sampleRate
        let effectiveBits = bitDepth ?? self.bitDepth
        let effectiveBytesPerFrame = channels * (effectiveBits / 8)
        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        var chunkSize: UInt32 = dataLength + 36
        header.append(Data(bytes: &chunkSize, count: 4))
        header.append(contentsOf: "WAVEfmt ".utf8)
        var subchunk1Size: UInt32 = 16
        header.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat: UInt16 = 1 // Linear PCM
        header.append(Data(bytes: &audioFormat, count: 2))
        var numChannels = UInt16(channels)
        header.append(Data(bytes: &numChannels, count: 2))
        var sRate = UInt32(effectiveRate)
        header.append(Data(bytes: &sRate, count: 4))
        var byteRate = UInt32(effectiveRate * effectiveBytesPerFrame)
        header.append(Data(bytes: &byteRate, count: 4))
        var blockAlign = UInt16(effectiveBytesPerFrame)
        header.append(Data(bytes: &blockAlign, count: 2))
        var bits = UInt16(effectiveBits)
        header.append(Data(bytes: &bits, count: 2))
        header.append(contentsOf: "data".utf8)
        var dSize = dataLength
        header.append(Data(bytes: &dSize, count: 4))
        return header
    }
}
