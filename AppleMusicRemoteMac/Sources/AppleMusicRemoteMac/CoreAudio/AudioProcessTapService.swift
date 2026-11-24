//
//  AudioProcessTapService.swift
//  AppleMusicRemoteMac
//
//  High-Resolution CoreAudio Process Tap Service for Apple Music
//  Captures real-time uncompressed PCM audio from Music.app (up to 24-bit / 192 kHz)
//  and feeds it to network streamers (BluOS / DLNA / UPnP) and local DSP pipelines.
//

import Foundation
import Accelerate
import CoreAudio
import AppKit
import os

public final class AudioProcessTapService: @unchecked Sendable {
    public static let shared = AudioProcessTapService()

    internal static let queueSpecificKey = DispatchSpecificKey<Void>()
    internal static let streamScratchTileFrames: Int = 4096
    internal static let streamFloatRingCapacityFrames: Int = 131_072
    internal static let tapControlSignalNonZeroDetected: UInt = 1 << 0
    internal static let tapControlSignalSuspendZeroedPassthrough: UInt = 1 << 1
    internal static let passiveIdleSuspendTimeoutSec: Double = 45.0
    internal let queue = DispatchQueue(label: "org.ksholokhov.amr.audiotap", qos: .userInteractive)

    // CoreAudio objects
    internal var tapObjectID: AudioObjectID = 0
    internal var aggregateDeviceID: AudioObjectID = 0
    internal var ioProcID: AudioDeviceIOProcID?

    // Stream parameters (RT-safe spinlocks — never call Objective-C NSLock from CoreAudio IOProc)
    internal var formatSpinLock = os_unfair_lock_s()
    internal var _sampleRate: Int = 44100
    internal var _bitDepth: Int = 16

    public internal(set) var sampleRate: Int {
        get {
            os_unfair_lock_lock(&formatSpinLock)
            let v = _sampleRate
            os_unfair_lock_unlock(&formatSpinLock)
            return v
        }
        set {
            os_unfair_lock_lock(&formatSpinLock)
            _sampleRate = newValue
            os_unfair_lock_unlock(&formatSpinLock)
        }
    }
    public let channels: Int = 2
    public internal(set) var bitDepth: Int {
        get {
            os_unfair_lock_lock(&formatSpinLock)
            let v = _bitDepth
            os_unfair_lock_unlock(&formatSpinLock)
            return v
        }
        set {
            os_unfair_lock_lock(&formatSpinLock)
            _bitDepth = newValue
            os_unfair_lock_unlock(&formatSpinLock)
        }
    }
    public var bitsPerSample: Int { bitDepth }
    public var bytesPerFrame: Int { channels * (bitDepth / 8) }

    internal var _isCapturing: Bool = false
    internal var _isTapMuted: Bool = false
    internal var _isRealTapActiveFlag: Bool = false

    public internal(set) var isCapturing: Bool {
        get {
            os_unfair_lock_lock(&mutingGuardSpinLock)
            let v = _isCapturing
            os_unfair_lock_unlock(&mutingGuardSpinLock)
            return v
        }
        set {
            os_unfair_lock_lock(&mutingGuardSpinLock)
            _isCapturing = newValue
            os_unfair_lock_unlock(&mutingGuardSpinLock)
        }
    }

    public var isRealTapActive: Bool {
        os_unfair_lock_lock(&mutingGuardSpinLock)
        let v = _isRealTapActiveFlag
        os_unfair_lock_unlock(&mutingGuardSpinLock)
        return v
    }

    internal var isTapMuted: Bool {
        get {
            os_unfair_lock_lock(&mutingGuardSpinLock)
            let v = _isTapMuted
            os_unfair_lock_unlock(&mutingGuardSpinLock)
            return v
        }
        set {
            os_unfair_lock_lock(&mutingGuardSpinLock)
            _isTapMuted = newValue
            os_unfair_lock_unlock(&mutingGuardSpinLock)
        }
    }

    /// Lock-free / spinlock-safe check whether a real CoreAudio Process Tap is currently active and configured as `.muted`.
    public var isTapCurrentlyMuted: Bool {
        os_unfair_lock_lock(&mutingGuardSpinLock)
        let v = _isRealTapActiveFlag && _isTapMuted
        os_unfair_lock_unlock(&mutingGuardSpinLock)
        return v
    }

    @usableFromInline
    @inline(__always)
    internal func syncRealTapActiveFlag() {
        let active = (aggregateDeviceID != 0 && tapObjectID != 0)
        os_unfair_lock_lock(&mutingGuardSpinLock)
        _isRealTapActiveFlag = active
        os_unfair_lock_unlock(&mutingGuardSpinLock)
    }

    internal var isPassiveAnalysisActive: Bool = false
    internal var isWLEDTapConsumerActive: Bool = false
    internal var isPassiveTapIdleSuspended: Bool = false
    internal var passivePausedSinceMono: Double? = nil
    internal var isMutingGuardZeroFill: Bool = false
    internal var mutingGuardSpinLock = os_unfair_lock_s()
    internal var streamScratchSpinLock = os_unfair_lock_s()
    internal let streamScratchL: UnsafeMutablePointer<Float>
    internal let streamScratchR: UnsafeMutablePointer<Float>
    internal let streamScratchPCMBytes: UnsafeMutablePointer<UInt8>

    internal let streamFloatRingBuffer: SPSCStereoFloatRingBuffer
    internal var streamDrainSignalSource: DispatchSourceUserDataAdd!
    internal var tapControlSignalSource: DispatchSourceUserDataOr!
    internal var ditherSeedL: UInt64 = 0x853C_49E6_748F_EA9B
    internal var ditherSeedR: UInt64 = 0xDA3E_39CB_94B9_5BDB

    // Subscriber callbacks: (UUID, (Data) -> Void)
    internal var subscribers: [UUID: (Data) -> Void] = [:]
    internal var hasActiveSubscribersFlag: Bool = false

    // Audio buffering & silence generation
    internal var chunkAccumulator = Data()
    internal var targetChunkFrameCount: Int {
        // Target ~50ms of audio at current sample rate
        return max(512, sampleRate / 20)
    }
    internal var lastAudioReceivedTimeMono: Double = -1.0e9
    internal var lastNonZeroAudioTimeMono: Double = -1.0e9
    internal var mutedZeroSignalAccumulatedSec: Double = 0.0
    internal var silenceTimer: DispatchSourceTimer?
    internal var silenceTickCount: Int = 0
    internal var autoHealCount: Int = 0
    internal var rateConvergenceGeneration: UInt64 = 0
    internal var tappedProcessObjectIDs: Set<AudioObjectID> = []
    internal var silenceSpinLock = os_unfair_lock_s()
    internal let isTestingEnv: Bool = PlaybackRouter.shared.isTestingEnvironment

    private init() {
        queue.setSpecific(key: Self.queueSpecificKey, value: ())
        streamScratchL = UnsafeMutablePointer<Float>.allocate(capacity: Self.streamScratchTileFrames)
        streamScratchR = UnsafeMutablePointer<Float>.allocate(capacity: Self.streamScratchTileFrames)
        streamScratchL.initialize(repeating: 0, count: Self.streamScratchTileFrames)
        streamScratchR.initialize(repeating: 0, count: Self.streamScratchTileFrames)

        let maxTilePCMBytes = Self.streamScratchTileFrames * 6
        streamScratchPCMBytes = UnsafeMutablePointer<UInt8>.allocate(capacity: maxTilePCMBytes)
        streamScratchPCMBytes.initialize(repeating: 0, count: maxTilePCMBytes)

        streamFloatRingBuffer = SPSCStereoFloatRingBuffer(minimumFrameCapacity: Self.streamFloatRingCapacityFrames)

        let drainSource = DispatchSource.makeUserDataAddSource(queue: queue)
        self.streamDrainSignalSource = drainSource
        drainSource.setEventHandler { [weak self] in
            self?.drainStreamPCMRingBufferOnQueue()
        }
        drainSource.resume()

        let controlSource = DispatchSource.makeUserDataOrSource(queue: queue)
        self.tapControlSignalSource = controlSource
        controlSource.setEventHandler { [weak self] in
            guard let self = self else { return }
            let flags = self.tapControlSignalSource.data
            if (flags & Self.tapControlSignalNonZeroDetected) != 0 {
                RoomAcousticService.shared.notifyNonZeroTapSignalDetected()
            }
            if (flags & Self.tapControlSignalSuspendZeroedPassthrough) != 0 {
                RoomAcousticService.shared.suspendLocalPassthroughDueToZeroedTap()
            }
        }
        controlSource.resume()
    }

    deinit {
        tapControlSignalSource?.cancel()
        streamDrainSignalSource?.cancel()
        runSyncOnQueue {
            stopCaptureInternal()
        }
        streamScratchL.deinitialize(count: Self.streamScratchTileFrames)
        streamScratchL.deallocate()
        streamScratchR.deinitialize(count: Self.streamScratchTileFrames)
        streamScratchR.deallocate()
        let maxTilePCMBytes = Self.streamScratchTileFrames * 6
        streamScratchPCMBytes.deinitialize(count: maxTilePCMBytes)
        streamScratchPCMBytes.deallocate()
    }

    @inline(__always)
    internal func runSyncOnQueue<T>(_ block: () -> T) -> T {
        if DispatchQueue.getSpecific(key: Self.queueSpecificKey) != nil {
            return block()
        }
        return queue.sync(execute: block)
    }

    // MARK: - Subscriber Management

    public func addSubscriber(id: UUID, onAudioChunk: @escaping (Data) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.subscribers[id] = onAudioChunk
            self.isPassiveTapIdleSuspended = false
            self.passivePausedSinceMono = nil
            os_unfair_lock_lock(&self.mutingGuardSpinLock)
            self.hasActiveSubscribersFlag = !self.subscribers.isEmpty
            os_unfair_lock_unlock(&self.mutingGuardSpinLock)
            NSLog("[AudioProcessTapService] 🎧 Added stream subscriber \(id). Total active: \(self.subscribers.count)")
            if !self.isRealTapActive {
                self.startCaptureInternal()
            }
        }
    }

    public func removeSubscriber(id: UUID) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.subscribers.removeValue(forKey: id)
            os_unfair_lock_lock(&self.mutingGuardSpinLock)
            self.hasActiveSubscribersFlag = !self.subscribers.isEmpty
            os_unfair_lock_unlock(&self.mutingGuardSpinLock)
            NSLog("[AudioProcessTapService] 🔌 Removed stream subscriber \(id). Remaining: \(self.subscribers.count)")
            if self.subscribers.isEmpty && !self.isWLEDTapConsumerActive && !self.isPassiveAnalysisActive && !AudioEngineController.shared.isActivePipelineHook && !RoomAcousticService.shared.isLocalPassthroughEQActive {
                // Keep capture running for a 3-second grace period in case streamer re-requests
                self.queue.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    guard let self = self else { return }
                    if self.subscribers.isEmpty && !self.isWLEDTapConsumerActive && !self.isPassiveAnalysisActive && !AudioEngineController.shared.isActivePipelineHook && !RoomAcousticService.shared.isLocalPassthroughEQActive && self.isCapturing {
                        NSLog("[AudioProcessTapService] No subscribers remaining. Stopping tap capture.")
                        self.stopCaptureInternal()
                    }
                }
            }
        }
    }

    public func setWLEDRealTimeTapConsumerActive(_ active: Bool) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.isWLEDTapConsumerActive = active
            if active {
                self.isPassiveTapIdleSuspended = false
                self.passivePausedSinceMono = nil
                if !self.isRealTapActive && !self.isTestingEnv {
                    self.startCaptureInternal()
                }
            } else if self.subscribers.isEmpty && !self.isPassiveAnalysisActive && !AudioEngineController.shared.isActivePipelineHook && !RoomAcousticService.shared.isLocalPassthroughEQActive && self.isCapturing {
                self.stopCaptureInternal()
            }
        }
    }

    public var hasSubscribers: Bool {
        return runSyncOnQueue { !subscribers.isEmpty }
    }

    public var subscriberCount: Int {
        return runSyncOnQueue { subscribers.count }
    }

    // MARK: - Capture Control

    public func setMutingGuardZeroFill(_ active: Bool) {
        os_unfair_lock_lock(&mutingGuardSpinLock)
        isMutingGuardZeroFill = active
        os_unfair_lock_unlock(&mutingGuardSpinLock)
    }

    public var isZeroFillingForMutingGuard: Bool {
        os_unfair_lock_lock(&mutingGuardSpinLock)
        let v = isMutingGuardZeroFill
        os_unfair_lock_unlock(&mutingGuardSpinLock)
        return v
    }

    public func setPassiveAnalysisEnabled(_ enabled: Bool) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.isPassiveAnalysisActive = enabled
            if !enabled {
                self.isPassiveTapIdleSuspended = false
                self.passivePausedSinceMono = nil
            }
            if !enabled && self.subscribers.isEmpty && !self.isWLEDTapConsumerActive && !AudioEngineController.shared.isActivePipelineHook && !RoomAcousticService.shared.isLocalPassthroughEQActive && self.isCapturing {
                NSLog("[AudioProcessTapService] 🛑 Spectral analyzer disabled and no subscribers remaining. Stopping passive tap.")
                self.stopCaptureInternal()
            }
        }
    }

    public func ensurePassiveAnalysisTapActive(sampleRate: Int, bitDepth: Int) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.isPassiveAnalysisActive = true
            self.isPassiveTapIdleSuspended = false
            self.passivePausedSinceMono = nil

            var resolvedRate = sampleRate
            if !self.isTestingEnv && !DLNADiscoveryManager.shared.hasActiveRenderer && !AudioEngineController.shared.isActivePipelineHook,
               let defID = CoreAudioDeviceManager.shared.getDefaultOutputDeviceID(), defID != 0 {
                let hwRate = HALDeviceManager.nominalSampleRate(deviceID: defID)
                if hwRate >= 44_100.0 {
                    resolvedRate = Int(hwRate.rounded())
                }
            }

            var formatChanged = false
            // Only seed initial sample rate when tap is not yet running (or in headless tests);
            // live sample-rate transitions are driven authoritatively via `setFormat(...)`.
            if resolvedRate > 0 && resolvedRate != self.sampleRate && (self.isTestingEnv || !self.isRealTapActive) {
                self.sampleRate = resolvedRate
                formatChanged = true
            }
            if (bitDepth == 16 || bitDepth == 20 || bitDepth == 24 || bitDepth == 32) && (self.isTestingEnv || !self.isRealTapActive) {
                let effectiveDepth = (bitDepth == 16) ? 16 : 24
                if effectiveDepth != self.bitDepth {
                    self.bitDepth = effectiveDepth
                    formatChanged = true
                }
            }
            if formatChanged {
                self.chunkAccumulator.removeAll()
            }
            guard !self.isTestingEnv else { return }
            let shouldMute = DLNADiscoveryManager.shared.hasActiveRenderer || AudioEngineController.shared.isActivePipelineHook || RoomAcousticService.shared.isLocalPassthroughEQActive
            if self.isRealTapActive && self.isTapMuted != shouldMute {
                NSLog("[AudioProcessTapService] 🔄 Recreating Process Tap to update muteBehavior (muted: \(shouldMute))")
                self.stopCaptureInternal()
            }
            if !self.isRealTapActive {
                self.startCaptureInternal()
            }
        }
    }

    public func startCapture() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.isPassiveTapIdleSuspended = false
            self.passivePausedSinceMono = nil
            let shouldMute = DLNADiscoveryManager.shared.hasActiveRenderer || AudioEngineController.shared.isActivePipelineHook || RoomAcousticService.shared.isLocalPassthroughEQActive
            if self.isRealTapActive && self.isTapMuted != shouldMute {
                self.stopCaptureInternal()
            }
            self.startCaptureInternal()
        }
    }

    public func stopCapture() {
        queue.async { [weak self] in
            self?.isPassiveTapIdleSuspended = false
            self?.passivePausedSinceMono = nil
            self?.stopCaptureInternal()
        }
    }

    /// Reconciles Process Tap state on `queue` after a route transition (e.g. DLNA disconnect or DSP teardown):
    /// - Stops capture if no active consumers remain (`subscribers`, `isPassiveAnalysisActive`, `DLNADiscoveryManager`, `AudioEngineController`, `RoomAcousticService`).
    /// - Otherwise ensures capture is running and recreates the tap if `muteBehavior` changed (e.g. `.muted` -> `.unmuted`).
    public func reconcileCaptureAfterRouteChange() {
        queue.async { [weak self] in
            guard let self = self else { return }
            let hasActiveNonPassiveConsumer = !self.subscribers.isEmpty
                || self.isWLEDTapConsumerActive
                || DLNADiscoveryManager.shared.hasActiveRenderer
                || AudioEngineController.shared.isActivePipelineHook
                || RoomAcousticService.shared.isLocalPassthroughEQActive
            let needsTap = hasActiveNonPassiveConsumer || self.isPassiveAnalysisActive
            if !needsTap {
                if self.isCapturing || self.isRealTapActive {
                    self.stopCaptureInternal()
                }
                return
            }
            if !hasActiveNonPassiveConsumer && self.isPassiveTapIdleSuspended && !SpectralIntegrityAnalyzer.shared.isPlaying {
                if self.isCapturing || self.isRealTapActive {
                    self.stopCaptureInternal()
                }
                return
            }
            self.isPassiveTapIdleSuspended = false
            self.passivePausedSinceMono = nil
            let shouldMute = DLNADiscoveryManager.shared.hasActiveRenderer
                || AudioEngineController.shared.isActivePipelineHook
                || RoomAcousticService.shared.isLocalPassthroughEQActive
            if self.isRealTapActive && self.isTapMuted != shouldMute {
                NSLog("[AudioProcessTapService] 🔄 Recreating Process Tap on route change to update muteBehavior (muted: \(shouldMute))")
                self.stopCaptureInternal()
            }
            if !self.isRealTapActive {
                self.startCaptureInternal()
            }
        }
    }

    public func setFormat(sampleRate: Int? = nil, bitDepth: Int? = nil) {
        queue.async { [weak self] in
            self?.applyFormatOnQueue(sampleRate: sampleRate, bitDepth: bitDepth)
        }
    }

    @discardableResult
    public func setFormatSync(sampleRate: Int? = nil, bitDepth: Int? = nil) -> (sampleRate: Int, bitDepth: Int) {
        return runSyncOnQueue {
            self.applyFormatOnQueue(sampleRate: sampleRate, bitDepth: bitDepth)
            return (self.sampleRate, self.bitDepth)
        }
    }

    public func currentFormatSync() -> (sampleRate: Int, bitDepth: Int) {
        return runSyncOnQueue {
            (self.sampleRate, self.bitDepth)
        }
    }

    public func setSampleRate(_ rate: Int) {
        setFormat(sampleRate: rate)
    }

    public func setBitDepth(_ depth: Int) {
        setFormat(bitDepth: depth)
    }

    // MARK: - WAV Header Helper

    public func makeWAVHeader(sampleRate: Int? = nil, bitDepth: Int? = nil, dataLength: UInt32 = 0x7FFFFFFF - 36) -> Data {
        let rawRate = sampleRate ?? self.sampleRate
        let effectiveRate = max(8_000, min(768_000, rawRate))
        let rawBd = bitDepth ?? self.bitDepth
        let bd: UInt16 = (rawBd == 24 || rawBd == 20 || rawBd == 32) ? 24 : 16
        let effectiveBits = Int(bd)
        let effectiveBytesPerFrame = channels * (effectiveBits / 8)
        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        var chunkSize: UInt32 = dataLength > (UInt32.max - 36) ? UInt32.max : (dataLength + 36)
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
        var bits = bd
        header.append(Data(bytes: &bits, count: 2))
        header.append(contentsOf: "data".utf8)
        var dSize = dataLength
        header.append(Data(bytes: &dSize, count: 4))
        return header
    }
}
