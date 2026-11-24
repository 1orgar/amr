//
//  HALDeviceManager.swift
//  AppleMusicRemoteMac
//
//  Direct CoreAudio HAL Output Controller:
//  - Exclusive Hog Mode acquisition (kAudioDevicePropertyHogMode)
//  - Hardware Integer Mode negotiation (kAudioStreamPropertyAvailablePhysicalFormats / PhysicalFormat)
//  - Automatic DoP256 -> DoP128 -> DoP64 ceiling negotiation
//  - Zero-Click DSD Silence (0x69) pre-fill and Zero-ARC @convention(c) IOProc lifecycle
//

import Foundation
import CoreAudio
import AudioToolbox
import Darwin

/// Описание согласованного аппаратного формата выходного потока CoreAudio HAL.
public struct NegotiatedHALOutputFormat: Sendable, Equatable {
    public let deviceID: AudioDeviceID
    public let streamID: AudioStreamID
    public let sampleRateHz: Int
    public let bitDepth: Int
    public let physicalFormat: HALPhysicalStreamFormat
    public let isIntegerMode: Bool
    public let isHogModeLocked: Bool
    public let dsdMultiplier: DSDRateMultiplier?
    public var bitsPerChannel: Int { bitDepth }

    public init(
        deviceID: AudioDeviceID,
        streamID: AudioStreamID,
        sampleRateHz: Int,
        bitDepth: Int,
        physicalFormat: HALPhysicalStreamFormat,
        isIntegerMode: Bool,
        isHogModeLocked: Bool,
        dsdMultiplier: DSDRateMultiplier?
    ) {
        self.deviceID = deviceID
        self.streamID = streamID
        self.sampleRateHz = sampleRateHz
        self.bitDepth = bitDepth
        self.physicalFormat = physicalFormat
        self.isIntegerMode = isIntegerMode
        self.isHogModeLocked = isHogModeLocked
        self.dsdMultiplier = dsdMultiplier
    }
}

/// Низкоуровневый менеджер вывода CoreAudio HAL (без AVAudioEngine и AudioQueue).
public final class HALDeviceManager: @unchecked Sendable {
    /// Отвязывает внутренний обработчик IPC-сообщений CoreAudio HAL (`HALC_IOContext_PauseIO` / `ResumeIO`)
    /// от `CFRunLoopGetMain()`, предотвращая 7.3-секундный дедлок `AudioDeviceStart -> OSStatus 35 (EAGAIN)`
    /// при переключении частот 352.8 / 705.6 кГц на USB UAC2 ЦАП/DDC (XMOS XU316 / SMSL PO100 PRO).
    private static let detachedHALRunLoopOnce: Void = {
        var runLoopAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyRunLoop,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var nullRunLoop: CFRunLoop? = nil
        let status = withUnsafePointer(to: &nullRunLoop) { ptr in
            AudioObjectSetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &runLoopAddr,
                0,
                nil,
                UInt32(MemoryLayout<CFRunLoop?>.size),
                ptr
            )
        }
        NSLog("[HALDeviceManager] 🧵 Detached CoreAudio HAL runloop from main thread (OSStatus: %d)", status)
    }()

    public static func ensureDetachedHALRunLoop() {
        _ = detachedHALRunLoopOnce
    }

    internal let lock = NSLock()
    internal var activeDeviceID: AudioDeviceID = 0
    internal var activeStreamID: AudioStreamID = 0
    internal var ioProcID: AudioDeviceIOProcID?
    internal var isHoggedByUsStorage: Bool = false
    internal var savedOutputVolumes: [(element: UInt32, scalar: Float32)] = []
    internal var savedOriginalSampleRate: Float64?
    internal var savedOriginalPhysicalFormat: AudioStreamBasicDescription?
    internal var savedOriginalVirtualFormat: AudioStreamBasicDescription?
    internal var retainedRingBuffer: SPSCAtomicRingBuffer?
    internal var ioContextPtr: UnsafeMutablePointer<RealtimeIOContext>
    internal var negotiatedFormatStorage: NegotiatedHALOutputFormat?

    public var currentNegotiatedFormat: NegotiatedHALOutputFormat? {
        lock.lock()
        defer { lock.unlock() }
        return negotiatedFormatStorage
    }

    public var negotiatedPhysicalFormat: NegotiatedHALOutputFormat? {
        currentNegotiatedFormat
    }

    public var isHogModeLocked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isHoggedByUsStorage
    }

    public var currentActiveDeviceID: AudioDeviceID {
        lock.lock()
        defer { lock.unlock() }
        return activeDeviceID
    }

    public init() {
        Self.ensureDetachedHALRunLoop()
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<RealtimeIOContext>.stride,
            alignment: 64
        )
        self.ioContextPtr = raw.initializeMemory(as: RealtimeIOContext.self, repeating: RealtimeIOContext(), count: 1)
        _ = mlock(raw, MemoryLayout<RealtimeIOContext>.stride)
    }

    deinit {
        stopAndReleaseDevice()
        ioContextPtr.pointee.deallocateScratch()
        munlock(ioContextPtr, MemoryLayout<RealtimeIOContext>.stride)
        UnsafeMutableRawPointer(ioContextPtr).deallocate()
    }

    // MARK: - Hog Mode Lifecycle (Thread-Safe)

    /// Захватывает `kAudioDevicePropertyHogMode` для текущего процесса (`getpid()`).
    @discardableResult
    public func acquireHogMode(for deviceID: AudioDeviceID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return acquireHogModeLocked(for: deviceID)
    }

    /// Освобождает `kAudioDevicePropertyHogMode` (`pid_t = -1`).
    public func releaseHogMode(for deviceID: AudioDeviceID) {
        lock.lock()
        defer { lock.unlock() }
        releaseHogModeLocked(for: deviceID)
    }

    @discardableResult
    internal func acquireHogModeLocked(for deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyHogMode,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var currentHogPID: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        let myPID = getpid()
        if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &currentHogPID) == noErr {
            if currentHogPID == myPID {
                isHoggedByUsStorage = true
                return true
            }
        }

        var isSettable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr, isSettable.boolValue else {
            return false
        }

        var targetPID: pid_t = myPID
        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &targetPID)
        if status == noErr {
            isHoggedByUsStorage = true
            NSLog("[HALDeviceManager] 🔒 Acquired Exclusive Hog Mode on device %u (PID: %d)", deviceID, myPID)
            return true
        }
        NSLog("[HALDeviceManager] ⚠️ Could not acquire Hog Mode on device %u (OSStatus: %d)", deviceID, status)
        return false
    }

    internal func releaseHogModeLocked(for deviceID: AudioDeviceID) {
        guard deviceID != 0, isHoggedByUsStorage else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyHogMode,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var releasePID: pid_t = -1
        let size = UInt32(MemoryLayout<pid_t>.size)
        _ = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &releasePID)
        isHoggedByUsStorage = false
        NSLog("[HALDeviceManager] 🔓 Released Hog Mode on device %u", deviceID)
    }

    // MARK: - Start / Stop Real-Time IOProc

    /// Запускает вывод из `ringBuffer` в `deviceID` с защитой от щелчков (`Zero-Click Mute`)
    /// и полным откатом микшируемого формата и `Hog Mode` при ошибке старта CoreAudio.
    @discardableResult
    public func startOutput(
        deviceID: AudioDeviceID,
        sampleRateHz: Int,
        isDoPMode: Bool,
        dsdMultiplier: DSDRateMultiplier?,
        enableHogMode: Bool,
        ringBuffer: SPSCAtomicRingBuffer
    ) -> NegotiatedHALOutputFormat? {
        lock.lock()
        defer { lock.unlock() }

        guard deviceID != 0 else {
            stopAndReleaseDeviceLocked()
            return nil
        }

        // Если меняем частоту/режим на ТОМ ЖЕ устройстве, останавливаем только IOProc без сброса Hog Mode и микшера,
        // чтобы macOS не дёргала системный аудиовыход (Динамики <-> SMSL) между переключениями частот!
        if activeDeviceID != 0 && activeDeviceID != deviceID {
            stopAndReleaseDeviceLocked()
        } else {
            stopIOProcOnlyLocked()
            if !enableHogMode && isHoggedByUsStorage {
                restoreMixableFormatAndControlsBeforeReleaseLocked(deviceID: deviceID, streamID: activeStreamID)
                releaseHogModeLocked(for: deviceID)
            }
        }

        // Сохраняем исходный микшируемый формат и частоту устройства ДО захвата Hog Mode / Non-Mixable переключения,
        // чтобы при сбое AudioDeviceCreateIOProcID / AudioDeviceStart гарантированно вернуть управление Music.app и macOS.
        if savedOriginalSampleRate == nil || activeDeviceID != deviceID {
            savedOriginalSampleRate = Self.nominalSampleRate(deviceID: deviceID)
            let preStream = getOutputStreams(for: deviceID).first ?? 0
            if preStream != 0 {
                savedOriginalPhysicalFormat = currentStreamFormat(for: preStream, selector: kAudioStreamPropertyPhysicalFormat)
                savedOriginalVirtualFormat = currentStreamFormat(for: preStream, selector: kAudioStreamPropertyVirtualFormat)
            } else {
                savedOriginalPhysicalFormat = nil
                savedOriginalVirtualFormat = nil
            }
        }

        let hogLocked = enableHogMode ? acquireHogModeLocked(for: deviceID) : false
        let (streamID, physFormat, bitDepth, isInteger) = configurePhysicalFormat(
            deviceID: deviceID,
            targetSampleRateHz: sampleRateHz,
            preferNonMixable: hogLocked || isDoPMode
        )
        if isDoPMode {
            ensureBitTransparentHardwareControlsForDoPLocked(deviceID: deviceID)
        }

        // Если вызывающий код (AudioEngineController) ещё не предзаполнил кольцевой буфер,
        // предзаполняем его нейтральной DSD-тишиной (0x69) на ~40 мс перед стартом IOProc.
        if ringBuffer.availableToRead == 0 {
            var prefillState = DoPPackerState()
            let prefillFrames = min(ringBuffer.capacity / 8, max(4096, sampleRateHz / 25))
            if prefillFrames > 0 {
                let tempCount = prefillFrames * 2
                let tempBuf = UnsafeMutablePointer<Int32>.allocate(capacity: tempCount)
                defer { tempBuf.deallocate() }
                if isDoPMode {
                    prefillState.fillSilenceS32(into: tempBuf, stereoFrameCount: prefillFrames)
                } else {
                    memset(tempBuf, 0, tempCount * MemoryLayout<Int32>.stride)
                }
                _ = ringBuffer.write(from: tempBuf, count: tempCount)
            }
        }

        // Удерживаем strong reference на ringBuffer в HALDeviceManager, а в RT-контекст передаём чистую C-структуру без ARC!
        self.retainedRingBuffer = ringBuffer
        ioContextPtr.pointee.ringView = ringBuffer.rawView
        ioContextPtr.pointee.ringBufferPtr = Unmanaged.passUnretained(ringBuffer).toOpaque()
        ioContextPtr.pointee.isDoPModeFlag = isDoPMode ? 1 : 0
        ioContextPtr.pointee.physicalFormatRaw = physFormat.rawValue
        ioContextPtr.pointee.fallbackDoPState = DoPPackerState(altMarker: false)
        ioContextPtr.pointee.callbackTickCount = 0

        var newProcID: AudioDeviceIOProcID?
        let createStatus = AudioDeviceCreateIOProcID(
            deviceID,
            realtimeHALAudioIOProc,
            ioContextPtr,
            &newProcID
        )
        guard createStatus == noErr, let procID = newProcID else {
            NSLog("[HALDeviceManager] ❌ AudioDeviceCreateIOProcID failed with status %d", createStatus)
            rollbackFailedStartLocked(deviceID: deviceID, streamID: streamID)
            return nil
        }

        // Отключаем лишние системные потоки для нашего IOProc (kAudioDevicePropertyIOProcStreamUsage)
        let outputStreams = getOutputStreams(for: deviceID)
        if !outputStreams.isEmpty {
            let usageSize = MemoryLayout<AudioHardwareIOProcStreamUsage>.size + (max(0, outputStreams.count - 1) * MemoryLayout<UInt32>.size)
            let usageRaw = UnsafeMutableRawPointer.allocate(byteCount: usageSize, alignment: 8)
            defer { usageRaw.deallocate() }
            memset(usageRaw, 0, usageSize)
            let usagePtr = usageRaw.assumingMemoryBound(to: AudioHardwareIOProcStreamUsage.self)
            usagePtr.pointee.mIOProc = unsafeBitCast(procID, to: UnsafeMutableRawPointer.self)
            usagePtr.pointee.mNumberStreams = UInt32(outputStreams.count)
            withUnsafeMutablePointer(to: &usagePtr.pointee.mStreamIsOn) { firstStreamPtr in
                firstStreamPtr[0] = 1
            }
            var usageAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyIOProcStreamUsage,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            _ = AudioObjectSetPropertyData(deviceID, &usageAddr, 0, nil, UInt32(usageSize), usageRaw)
        }

        var startStatus = AudioDeviceStart(deviceID, procID)
        if startStatus == 35 {
            // Если USB UAC2 контроллер завершал перестройку изохронного пайпа (EAGAIN), даём 80 мс и повторяем старт один раз
            usleep(80_000)
            startStatus = AudioDeviceStart(deviceID, procID)
        }
        guard startStatus == noErr else {
            NSLog("[HALDeviceManager] ❌ AudioDeviceStart failed with status %d on device %u (%d Hz)", startStatus, deviceID, sampleRateHz)
            AudioDeviceDestroyIOProcID(deviceID, procID)
            rollbackFailedStartLocked(deviceID: deviceID, streamID: streamID)
            return nil
        }

        self.activeDeviceID = deviceID
        self.activeStreamID = streamID
        self.ioProcID = procID

        let negotiated = NegotiatedHALOutputFormat(
            deviceID: deviceID,
            streamID: streamID,
            sampleRateHz: sampleRateHz,
            bitDepth: bitDepth,
            physicalFormat: physFormat,
            isIntegerMode: isInteger,
            isHogModeLocked: hogLocked,
            dsdMultiplier: dsdMultiplier
        )
        self.negotiatedFormatStorage = negotiated
        NSLog("[HALDeviceManager] 🚀 Started HAL output on device %u at %d Hz (%d-bit, integer=%d, hog=%d, DoP=%d)",
              deviceID, sampleRateHz, bitDepth, isInteger ? 1 : 0, hogLocked ? 1 : 0, isDoPMode ? 1 : 0)
        return negotiated
    }

    @discardableResult
    public func startOutput(
        deviceID: AudioDeviceID,
        targetSampleRate: Double,
        isDoPMode: Bool,
        ringBuffer: SPSCAtomicRingBuffer
    ) -> Bool {
        let ok = startOutput(
            deviceID: deviceID,
            sampleRateHz: max(44_100, Int(targetSampleRate.rounded())),
            isDoPMode: isDoPMode,
            dsdMultiplier: nil,
            enableHogMode: true,
            ringBuffer: ringBuffer
        ) != nil
        if !ok {
            stopAndReleaseDevice()
        }
        return ok
    }

    /// Останавливает только активный `IOProc`, сохраняя захваченный `Hog Mode` и устройство для бесшовного переключения частоты DoP.
    public func stopIOProcPreservingHogMode() {
        lock.lock()
        defer { lock.unlock() }
        stopIOProcOnlyLocked()
    }

    internal func stopIOProcOnlyLocked() {
        if let procID = ioProcID, activeDeviceID != 0 {
            AudioDeviceStop(activeDeviceID, procID)
            AudioDeviceDestroyIOProcID(activeDeviceID, procID)
            ioProcID = nil
        }
        ioContextPtr.pointee.ringView = nil
        ioContextPtr.pointee.ringBufferPtr = nil
        retainedRingBuffer = nil
        negotiatedFormatStorage = nil
    }

    internal func rollbackFailedStartLocked(deviceID: AudioDeviceID, streamID: AudioStreamID) {
        ioContextPtr.pointee.ringView = nil
        ioContextPtr.pointee.ringBufferPtr = nil
        retainedRingBuffer = nil
        negotiatedFormatStorage = nil
        restoreMixableFormatAndControlsBeforeReleaseLocked(
            deviceID: deviceID,
            streamID: streamID,
            restoreOriginalSampleRate: true
        )
        releaseHogModeLocked(for: deviceID)
        activeDeviceID = 0
        activeStreamID = 0
        savedOriginalSampleRate = nil
        savedOriginalPhysicalFormat = nil
        savedOriginalVirtualFormat = nil
    }

    /// Бесщелчковая остановка вывода и освобождение `Hog Mode`.
    public func stopAndReleaseDevice() {
        lock.lock()
        defer { lock.unlock() }
        stopAndReleaseDeviceLocked()
    }

    internal func stopAndReleaseDeviceLocked() {
        stopIOProcOnlyLocked()
        if activeDeviceID != 0 {
            restoreMixableFormatAndControlsBeforeReleaseLocked(
                deviceID: activeDeviceID,
                streamID: activeStreamID,
                restoreOriginalSampleRate: false
            )
            releaseHogModeLocked(for: activeDeviceID)
            activeDeviceID = 0
            activeStreamID = 0
        }
        savedOriginalSampleRate = nil
        savedOriginalPhysicalFormat = nil
        savedOriginalVirtualFormat = nil
    }
}
