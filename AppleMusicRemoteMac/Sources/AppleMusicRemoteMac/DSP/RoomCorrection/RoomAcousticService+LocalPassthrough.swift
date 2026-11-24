//
//  RoomAcousticService+LocalPassthrough.swift
//  AppleMusicRemoteMac
//
//  Real-Time Audio Hooks & Local Passthrough 64-bit Pre-DSP AudioUnit Lifecycle
//

import AudioToolbox
import CoreAudio
import Darwin
import Foundation
import os

extension RoomAcousticService {

    // MARK: - Real-Time Audio Hooks (DSP Engine, BluOS/DLNA Stream & Local Passthrough)

    public func processPlanarDoubleIfEnabled(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frameCount: Int,
        sampleRate: Int
    ) {
        guard !isTestSignalPlaying else { return }
        dspEngineProcessor.processPlanarDouble(left: left, right: right, frameCount: frameCount, sampleRate: sampleRate)
    }

    public func processStreamPlanarFloat32IfEnabled(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        frameCount: Int,
        sampleRate: Int
    ) {
        guard !isTestSignalPlaying else { return }
        streamProcessor.processPlanarFloat32(left: left, right: right, frameCount: frameCount, sampleRate: sampleRate)
    }

    public func processStreamFloatPairIfEnabled(
        left: inout Float,
        right: inout Float,
        sampleRate: Int
    ) {
        guard !isTestSignalPlaying else { return }
        streamProcessor.processStereoFloatPair(left: &left, right: &right, sampleRate: sampleRate)
    }

    internal func syncRealtimeProcessors() {
        let (enabled, prof) = lock.withLock { () -> (Bool, RoomAcousticProfile?) in
            let p = activeProfileIDInternal.flatMap { aid in profiles.first(where: { $0.id == aid }) } ?? profiles.first
            return (correctionEnabledInternal && p != nil, p)
        }
        let bands = prof?.eqBands ?? []
        let preamp = prof?.preampGainDB ?? 0.0
        dspEngineProcessor.configure(enabled: enabled, bands: bands, preampGainDB: preamp)
        streamProcessor.configure(enabled: enabled, bands: bands, preampGainDB: preamp)
        localPassthroughProcessor.configure(enabled: enabled, bands: bands, preampGainDB: preamp)
    }

    public func suspendLocalPassthroughDueToZeroedTap() {
        guard !isIsolatedInstance else { return }
        let newlySuspended: Bool = lock.withLock {
            if tapZeroSignalSuspended { return false }
            tapZeroSignalSuspended = true
            syncFastFlagsFromStateLocked()
            return true
        }
        guard newlySuspended else { return }
        NSLog("[RoomAcousticService] ⚠️ Muted Process Tap delivered 100%% digital zeros while Music.app is playing (check macOS System Settings -> Privacy & Security -> Screen & System Audio Recording). Automatically restoring unmuted Bit-Perfect audio!")
        stopLocalPassthroughEQ()
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
    }

    public func notifyNonZeroTapSignalDetected() {
        guard !isIsolatedInstance else { return }
        let wasSuspended: Bool = lock.withLock {
            guard tapZeroSignalSuspended else { return false }
            tapZeroSignalSuspended = false
            syncFastFlagsFromStateLocked()
            return true
        }
        guard wasSuspended else { return }
        NSLog("[RoomAcousticService] ✅ Non-zero CoreAudio tap signal detected — re-enabling Local Passthrough Pre-DSP.")
        localEQControlQueue.async { [weak self] in
            self?.refreshLocalPassthroughEQPipeline()
            WebSocketServer.shared.broadcastStatus(includeQueue: false)
        }
    }

    /// Manages the lightweight CoreAudio DefaultOutput unit when user enables Room EQ, Mastering Restoration, or Late-Night DRC in Bit-Perfect Passthrough mode on local speakers/DAC.
    public func refreshLocalPassthroughEQPipeline(clearZeroSignalSuspension: Bool = false) {
        guard !isIsolatedInstance else { return }
        if clearZeroSignalSuspension {
            lock.withLock {
                tapZeroSignalSuspended = false
                syncFastFlagsFromStateLocked()
            }
        }
        if shouldRunLocalPassthroughPreDSP() {
            startLocalPassthroughEQIfNeeded()
        } else {
            stopLocalPassthroughEQ()
        }
    }

    internal func shouldRunLocalPassthroughPreDSP() -> Bool {
        if isSuspendedDueToZeroedTap { return false }
        let hasRoomEQ = isCorrectionEnabled && activeProfile != nil
        let hasLateNightDRC = LateNightDRCService.shared.isEnabled
        let hasMasteringRestoration = MasteringRestorationService.shared.isAnyEnabled
        return (hasRoomEQ || hasLateNightDRC || hasMasteringRestoration)
            && !DLNADiscoveryManager.shared.hasActiveRenderer
            && !AudioEngineController.shared.isActivePipelineHook
    }

    internal func resolveActiveLocalOutputFormat(preferredSampleRateHz: Double? = nil) -> (deviceID: AudioDeviceID, sampleRate: Double) {
        let devID = isIsolatedInstance ? 0 : (CoreAudioDeviceManager.shared.getDefaultOutputDeviceID() ?? 0)
        if let preferred = preferredSampleRateHz, preferred >= 44_100.0, preferred <= 768_000.0 {
            if devID != 0, !isIsolatedInstance {
                let supported = CoreAudioDeviceManager.shared.availableSampleRates(deviceID: devID)
                if !supported.isEmpty, !supported.contains(where: { abs($0 - preferred) < 1.0 }) {
                    // Hardware cannot run at `preferred` (e.g. 192 kHz track on 96 kHz max speakers) — read actual device rate
                    let hwRate = HALDeviceManager.nominalSampleRate(deviceID: devID)
                    if hwRate >= 44_100.0 {
                        return (devID, hwRate)
                    }
                }
            }
            return (devID, preferred)
        }
        if devID != 0, !isIsolatedInstance {
            let hwRate = HALDeviceManager.nominalSampleRate(deviceID: devID)
            if hwRate >= 44_100.0 {
                return (devID, hwRate)
            }
        }
        if let detected = BitPerfectLogMonitor.shared.currentDetectedSampleRate, detected >= 44_100.0 {
            return (devID, detected)
        }
        let tapRate = Double(AudioProcessTapService.shared.sampleRate)
        return (devID, max(44_100.0, tapRate))
    }

    /// Dynamically reconfigures the Local Passthrough Pre-DSP AudioUnit (`kAudioUnitProperty_StreamFormat`)
    /// whenever the source track or physical DAC switches sample rate (e.g. `48 kHz -> 96 kHz -> 44.1 kHz`)
    /// or when the default macOS output device changes, preventing ring-buffer rate mismatch (`дребезг`).
    public func notifyLocalOutputFormatChanged(sampleRateHz: Double? = nil, forceRecreateUnit: Bool = false) {
        var needReconcileTapAfterStop = false
        var tapFormatSyncRateHz: Int? = nil

        localEQUnitLifecycleLock.lock()
        lockedSection: do {
            defer { localEQUnitLifecycleLock.unlock() }

            os_unfair_lock_lock(&localEQRingLock)
            localEQAsyncReconfigPending = false
            os_unfair_lock_unlock(&localEQRingLock)

            let (existingAU, isSimTesting) = lock.withLock { (localEQAudioUnit, simulatedLocalEQActiveForTesting) }

            if isSimTesting && existingAU == nil {
                let targetRate = max(44_100.0, sampleRateHz ?? 48_000.0)
                let prevRate = lock.withLock { localEQConfiguredSampleRate }
                guard forceRecreateUnit || abs(prevRate - targetRate) >= 0.5 else { return }
                os_unfair_lock_lock(&localEQRingLock)
                localEQRingConfiguredUnitRate = targetRate
                resetLocalPassthroughRingLocked(sampleRate: targetRate, armFadeIn: true)
                os_unfair_lock_unlock(&localEQRingLock)
                localPassthroughProcessor.resetState()
                LateNightDRCService.shared.resetLocalPassthroughState()
                lock.withLock {
                    localEQConfiguredSampleRate = targetRate
                    localEQReconfigGeneration &+= 1
                }
                return
            }

            guard !isIsolatedInstance, let currentAU = existingAU else { return }

            guard shouldRunLocalPassthroughPreDSP() else {
                needReconcileTapAfterStop = stopLocalPassthroughEQLocked()
                break lockedSection
            }

            let (targetDevID, targetRate) = resolveActiveLocalOutputFormat(preferredSampleRateHz: sampleRateHz)
            let (prevRate, prevDevID) = lock.withLock { (localEQConfiguredSampleRate, localEQConfiguredDeviceID) }
            let deviceChanged = (targetDevID != 0 && prevDevID != 0 && targetDevID != prevDevID)
            let rateChanged = abs(prevRate - targetRate) >= 0.5

            guard forceRecreateUnit || deviceChanged || rateChanged else {
                os_unfair_lock_lock(&localEQRingLock)
                if abs(localEQSampleRate - targetRate) >= 0.5 {
                    localEQSampleRate = targetRate
                }
                os_unfair_lock_unlock(&localEQRingLock)
                return
            }

            // Reset ring buffer & filter delay states before re-arming the AudioUnit at `targetRate`
            os_unfair_lock_lock(&localEQRingLock)
            localEQRingConfiguredUnitRate = targetRate
            resetLocalPassthroughRingLocked(sampleRate: targetRate, armFadeIn: true)
            os_unfair_lock_unlock(&localEQRingLock)

            MasteringRestorationService.shared.resetLocalPassthroughState()
            localPassthroughProcessor.resetState()
            LateNightDRCService.shared.resetLocalPassthroughState()

            var reconfiguredInPlace = false
            if !forceRecreateUnit && !deviceChanged {
                _ = AudioOutputUnitStop(currentAU)
                if AudioUnitUninitialize(currentAU) == noErr {
                    var streamDesc = Self.makeNonInterleavedFloat32ASBD(sampleRate: targetRate)
                    let setStatus = AudioUnitSetProperty(
                        currentAU,
                        kAudioUnitProperty_StreamFormat,
                        kAudioUnitScope_Input,
                        0,
                        &streamDesc,
                        UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                    )
                    if setStatus == noErr,
                       AudioUnitInitialize(currentAU) == noErr,
                       AudioOutputUnitStart(currentAU) == noErr {
                        reconfiguredInPlace = true
                    }
                }
            }

            if reconfiguredInPlace {
                lock.withLock {
                    localEQConfiguredSampleRate = targetRate
                    if targetDevID != 0 {
                        localEQConfiguredDeviceID = targetDevID
                    }
                    localEQReconfigGeneration &+= 1
                }
                NSLog(
                    "[RoomAcousticService] 🔄 Reconfigured Local Passthrough Pre-DSP AudioUnit: %.1f kHz (was %.1f kHz)",
                    targetRate / 1000.0,
                    prevRate / 1000.0
                )
                return
            }

            // Device changed or AudioUnit required fresh instantiation: create `newAU` BEFORE swapping so `localEQAudioUnit` is never nil!
            if let newAU = instantiateAndStartLocalPassthroughUnit(targetRate: targetRate) {
                lock.withLock {
                    localEQAudioUnit = newAU
                    localEQConfiguredSampleRate = targetRate
                    localEQConfiguredDeviceID = targetDevID
                    localEQReconfigGeneration &+= 1
                    syncFastFlagsFromStateLocked()
                }
                AudioOutputUnitStop(currentAU)
                AudioUnitUninitialize(currentAU)
                AudioComponentInstanceDispose(currentAU)
                if deviceChanged {
                    tapFormatSyncRateHz = Int(targetRate.rounded())
                }
                NSLog(
                    "[RoomAcousticService] 🔄 Recreated Local Passthrough Pre-DSP AudioUnit on device %u at %.1f kHz (was %.1f kHz)",
                    targetDevID,
                    targetRate / 1000.0,
                    prevRate / 1000.0
                )
            } else {
                // Best-effort restart of previous unit if creation failed transiently
                _ = AudioUnitInitialize(currentAU)
                _ = AudioOutputUnitStart(currentAU)
            }
        }

        // Perform external AudioProcessTapService calls strictly outside localEQUnitLifecycleLock to prevent AB-BA deadlocks
        if needReconcileTapAfterStop {
            AudioProcessTapService.shared.reconcileCaptureAfterRouteChange()
        } else if let rateToSync = tapFormatSyncRateHz {
            AudioProcessTapService.shared.setFormat(sampleRate: rateToSync)
        }
    }

    internal func instantiateAndStartLocalPassthroughUnit(targetRate: Double) -> AudioComponentInstance? {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_DefaultOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let comp = AudioComponentFindNext(nil, &desc) else { return nil }
        var unit: AudioComponentInstance?
        guard AudioComponentInstanceNew(comp, &unit) == noErr, let au = unit else { return nil }

        var streamDesc = Self.makeNonInterleavedFloat32ASBD(sampleRate: targetRate)
        let fmtStatus = AudioUnitSetProperty(
            au,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,
            &streamDesc,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard fmtStatus == noErr else {
            AudioComponentInstanceDispose(au)
            return nil
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var cb = AURenderCallbackStruct(
            inputProc: { inRefCon, _, _, _, inNumberFrames, ioData -> OSStatus in
                guard let ioData else { return noErr }
                let abl = UnsafeMutableAudioBufferListPointer(ioData)
                let frames = Int(inNumberFrames)
                let neededBytes = frames * MemoryLayout<Float>.size
                guard frames > 0,
                      abl.count >= 2,
                      Int(abl[0].mDataByteSize) >= neededBytes,
                      Int(abl[1].mDataByteSize) >= neededBytes,
                      let lRaw = abl[0].mData,
                      let rRaw = abl[1].mData else {
                    for idx in 0..<abl.count {
                        if let ptr = abl[idx].mData, abl[idx].mDataByteSize > 0 {
                            memset(ptr, 0, Int(abl[idx].mDataByteSize))
                        }
                    }
                    return noErr
                }
                let service = Unmanaged<RoomAcousticService>.fromOpaque(inRefCon).takeUnretainedValue()
                let lOut = lRaw.assumingMemoryBound(to: Float.self)
                let rOut = rRaw.assumingMemoryBound(to: Float.self)
                service.renderLocalPassthroughBlock(
                    leftOut: lOut,
                    rightOut: rOut,
                    frames: frames,
                    useStartupCushion: true
                )
                if Int(abl[0].mDataByteSize) > neededBytes {
                    memset(lRaw.advanced(by: neededBytes), 0, Int(abl[0].mDataByteSize) - neededBytes)
                }
                if Int(abl[1].mDataByteSize) > neededBytes {
                    memset(rRaw.advanced(by: neededBytes), 0, Int(abl[1].mDataByteSize) - neededBytes)
                }
                if abl.count > 2 {
                    for idx in 2..<abl.count {
                        if let ptr = abl[idx].mData, abl[idx].mDataByteSize > 0 {
                            memset(ptr, 0, Int(abl[idx].mDataByteSize))
                        }
                    }
                }
                return noErr
            },
            inputProcRefCon: selfPtr
        )
        let cbStatus = AudioUnitSetProperty(
            au,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input,
            0,
            &cb,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        guard cbStatus == noErr else {
            AudioComponentInstanceDispose(au)
            return nil
        }

        if AudioUnitInitialize(au) == noErr, AudioOutputUnitStart(au) == noErr {
            return au
        } else {
            AudioComponentInstanceDispose(au)
            return nil
        }
    }

    internal func startLocalPassthroughEQIfNeeded() {
        var shouldStartTapCapture = false
        var tapFormatSyncRateHz: Int? = nil

        localEQUnitLifecycleLock.lock()
        do {
            defer { localEQUnitLifecycleLock.unlock() }

            let alreadyRunning = lock.withLock { localEQAudioUnit != nil }
            if alreadyRunning {
                if !AudioProcessTapService.shared.isCapturing || !AudioProcessTapService.shared.isTapCurrentlyMuted {
                    shouldStartTapCapture = true
                }
                // Ensure existing unit is synchronized with the current output device & sample rate
                let (devID, curRate) = resolveActiveLocalOutputFormat()
                let (cfgRate, cfgDev) = lock.withLock { (localEQConfiguredSampleRate, localEQConfiguredDeviceID) }
                if abs(cfgRate - curRate) >= 0.5 || (devID != 0 && cfgDev != 0 && devID != cfgDev) {
                    localEQControlQueue.async { [weak self] in
                        self?.notifyLocalOutputFormatChanged(sampleRateHz: curRate)
                    }
                }
            } else {
                let (targetDevID, targetRate) = resolveActiveLocalOutputFormat()
                os_unfair_lock_lock(&localEQRingLock)
                localEQRingUnitActiveFlag = true
                localEQRingConfiguredUnitRate = targetRate
                localEQAsyncReconfigPending = false
                resetLocalPassthroughRingLocked(sampleRate: targetRate, armFadeIn: true)
                os_unfair_lock_unlock(&localEQRingLock)

                MasteringRestorationService.shared.resetLocalPassthroughState()
                localPassthroughProcessor.resetState()
                LateNightDRCService.shared.resetLocalPassthroughState()

                if let au = instantiateAndStartLocalPassthroughUnit(targetRate: targetRate) {
                    lock.withLock {
                        localEQAudioUnit = au
                        localEQConfiguredSampleRate = targetRate
                        localEQConfiguredDeviceID = targetDevID
                        localEQReconfigGeneration &+= 1
                        syncFastFlagsFromStateLocked()
                    }
                    tapFormatSyncRateHz = Int(targetRate.rounded())
                    shouldStartTapCapture = true
                    NSLog("[RoomAcousticService] 🎛️ Local Passthrough 64-bit Pre-DSP output active at %.0f Hz", targetRate)
                } else {
                    os_unfair_lock_lock(&localEQRingLock)
                    localEQRingUnitActiveFlag = false
                    localEQRingConfiguredUnitRate = 0.0
                    os_unfair_lock_unlock(&localEQRingLock)
                }
            }
        }

        // Perform external AudioProcessTapService calls strictly outside localEQUnitLifecycleLock to prevent AB-BA deadlocks
        if let syncRate = tapFormatSyncRateHz {
            AudioProcessTapService.shared.setFormat(sampleRate: syncRate)
        }
        if shouldStartTapCapture {
            AudioProcessTapService.shared.startCapture()
        }
    }

    internal func stopLocalPassthroughEQ() {
        localEQUnitLifecycleLock.lock()
        let didStopAU = stopLocalPassthroughEQLocked()
        localEQUnitLifecycleLock.unlock()

        if didStopAU {
            AudioProcessTapService.shared.reconcileCaptureAfterRouteChange()
        }
    }

    @discardableResult
    internal func stopLocalPassthroughEQLocked() -> Bool {
        let au: AudioComponentInstance? = lock.withLock {
            let existing = localEQAudioUnit
            localEQAudioUnit = nil
            localEQConfiguredSampleRate = 0.0
            localEQConfiguredDeviceID = 0
            syncFastFlagsFromStateLocked()
            return existing
        }

        os_unfair_lock_lock(&localEQRingLock)
        localEQRingUnitActiveFlag = false
        localEQRingConfiguredUnitRate = 0.0
        localEQAsyncReconfigPending = false
        resetLocalPassthroughRingLocked(sampleRate: localEQSampleRate, armFadeIn: false)
        os_unfair_lock_unlock(&localEQRingLock)

        if let au {
            AudioOutputUnitStop(au)
            AudioUnitUninitialize(au)
            AudioComponentInstanceDispose(au)
            NSLog("[RoomAcousticService] ⏹️ Local Passthrough Pre-DSP stopped (pure Bit-Perfect restored)")
            return true
        }
        return false
    }
}
