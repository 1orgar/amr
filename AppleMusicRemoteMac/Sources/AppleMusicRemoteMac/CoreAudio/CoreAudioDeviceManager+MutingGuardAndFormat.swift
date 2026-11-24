//
//  CoreAudioDeviceManager+MutingGuardAndFormat.swift
//  AppleMusicRemoteMac
//
//  Generation-Safe DAC Muting Guard (Click-Free Relay Switching),
//  Stream Physical Bit-Depth Configuration & Hardware Output Volume
//

import Foundation
import CoreAudio
import Darwin

extension CoreAudioDeviceManager {

    // MARK: - DAC Muting Guard Implementation (Click-Free Relay Switching)

    /// Executes a deterministic DAC Muting Guard cycle around a custom format-switch closure (used in live switching & unit tests).
    public func performClickFreeSwitchCycle(
        deviceID: AudioDeviceID = 0,
        fromRate: Double,
        toRate: Double,
        switchOperation: () -> Void,
        completion: (() -> Void)? = nil
    ) {
        let needsSwitch = abs(fromRate - toRate) >= 0.5
        guard isMutingGuardEnabled && needsSwitch else {
            switchOperation()
            completion?()
            return
        }
        let guardMs = mutingGuardDurationMs
        let generation = engageMutingGuardPreSwitch(deviceID: deviceID, durationMs: guardMs, fromRate: fromRate, toRate: toRate)
        switchOperation()
        scheduleMutingGuardPostSwitchRelease(
            deviceID: deviceID,
            durationMs: guardMs,
            targetRate: toRate,
            generation: generation,
            completion: completion
        )
    }

    public func updateSavedGuardVolumeIfNeeded(_ newVol: Int, isDucked: Bool) {
        mutingGuardLock.lock()
        if isMutingGuardActiveInternal {
            preGuardAppVolume = newVol
            pendingAsyncVolumeRestoreTarget = nil
            preGuardWasDucked = isDucked
            if !isDucked {
                preGuardUnduckedVolume = newVol
            } else if preGuardUnduckedVolume == nil {
                preGuardUnduckedVolume = AudioDuckingController.shared.originalVolume
            }
        }
        mutingGuardLock.unlock()
    }

    @discardableResult
    internal func engageMutingGuardPreSwitch(deviceID: AudioDeviceID, durationMs: Int, fromRate: Double, toRate: Double) -> UInt64 {
        AudioProcessTapService.shared.setMutingGuardZeroFill(true)

        let isDuckedNow = !PlaybackRouter.shared.isTestingEnvironment ? AudioDuckingController.shared.isDucked : false
        let duckOriginalVol = isDuckedNow ? AudioDuckingController.shared.originalVolume : nil
        let canTrySoftwareMute = !PlaybackRouter.shared.isTestingEnvironment
            && !ExternalAmpTCPController.shared.isActive
            && !AppleScriptExecutor.shared.isBusy

        var needSoftwareMute = false
        var staleHardwareMutedDev: AudioDeviceID?
        var shouldAttemptHardwareMute = false

        mutingGuardLock.lock()
        mutingGuardGeneration &+= 1
        let generation = mutingGuardGeneration
        unmuteWorkItem?.cancel()
        unmuteWorkItem = nil
        let wasAlreadyActive = isMutingGuardActiveInternal
        isMutingGuardActiveInternal = true
        mutingGuardActivationCountInternal += 1

        if !PlaybackRouter.shared.isTestingEnvironment {
            if !wasAlreadyActive {
                preGuardWasDucked = isDuckedNow
                preGuardUnduckedVolume = duckOriginalVol
                // If an async volume restore from a just-finished guard cycle has not reached Music.app yet,
                // preserve that target volume so we NEVER capture 0 on back-to-back sample-rate switches!
                if let pendingVol = pendingAsyncVolumeRestoreTarget, preGuardAppVolume == nil {
                    preGuardAppVolume = pendingVol
                }
                shouldAttemptHardwareMute = (deviceID != 0)
            } else if deviceID != 0, hardwareMutedDeviceID != deviceID {
                staleHardwareMutedDev = hardwareMutedDeviceID
                hardwareMutedDeviceID = nil
                shouldAttemptHardwareMute = true
            }
        }
        mutingGuardLock.unlock()

        if let oldDev = staleHardwareMutedDev, oldDev != 0 {
            _ = setHardwareMute(false, for: oldDev)
        }

        if !PlaybackRouter.shared.isTestingEnvironment {
            var hwMuted = false
            if shouldAttemptHardwareMute {
                hwMuted = setHardwareMute(true, for: deviceID)
            }
            mutingGuardLock.lock()
            if mutingGuardGeneration == generation && isMutingGuardActiveInternal {
                if hwMuted {
                    hardwareMutedDeviceID = deviceID
                } else if !wasAlreadyActive && hardwareMutedDeviceID == nil && canTrySoftwareMute {
                    needSoftwareMute = true
                }
            }
            mutingGuardLock.unlock()
        }

        // Only fall back to ScriptingBridge soundVolume when the DAC lacks hardware kAudioDevicePropertyMute
        // and Music.app IPC is idle — never stall the DAC clock switch on contended AppleEvents,
        // and NEVER overwrite preGuardAppVolume if already saved!
        if needSoftwareMute, let app = MusicAppProvider.shared.getMusicApp() {
            let currentVol = app.soundVolume
            if currentVol >= 0 {
                let lockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100
                let isDLNAMuted = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isDLNAMuted }
                mutingGuardLock.lock()
                if mutingGuardGeneration == generation && isMutingGuardActiveInternal && preGuardAppVolume == nil {
                    if currentVol > 0 {
                        preGuardAppVolume = currentVol
                    } else if lockedTo100 && !isDLNAMuted {
                        preGuardAppVolume = 100
                    } else {
                        preGuardAppVolume = currentVol
                    }
                }
                mutingGuardLock.unlock()
            }
            app.soundVolume = 0
        }

        // Drain CoreAudio output FIFO with digital silence before flipping the hardware oscillator/relay,
        // NEVER blocking @MainActor / Thread.isMainThread with usleep!
        if !Thread.isMainThread {
            let preDelaySec: Double
            if PlaybackRouter.shared.isTestingEnvironment {
                preDelaySec = min(0.015, Double(durationMs) * 0.30 / 1000.0)
            } else {
                preDelaySec = min(0.045, Double(durationMs) * 0.30 / 1000.0)
            }
            if preDelaySec > 0.001 {
                usleep(UInt32(preDelaySec * 1_000_000))
            }
        }

        return generation
    }

    internal func scheduleMutingGuardPostSwitchRelease(
        deviceID: AudioDeviceID,
        durationMs: Int,
        targetRate: Double,
        generation: UInt64,
        completion: (() -> Void)? = nil
    ) {
        let postDelaySec: Double
        if PlaybackRouter.shared.isTestingEnvironment {
            postDelaySec = min(0.035, Double(durationMs) * 0.70 / 1000.0)
        } else {
            postDelaySec = max(0.025, Double(durationMs) * 0.70 / 1000.0)
        }

        mutingGuardLock.lock()
        guard mutingGuardGeneration == generation else {
            mutingGuardLock.unlock()
            completion?()
            return
        }
        unmuteWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else {
                completion?()
                return
            }
            self.releaseMutingGuard(targetRate: targetRate, expectedGeneration: generation)
            completion?()
        }
        unmuteWorkItem = item
        mutingGuardLock.unlock()

        mutingGuardQueue.asyncAfter(deadline: .now() + postDelaySec, execute: item)
    }

    internal func releaseMutingGuard(targetRate: Double, expectedGeneration: UInt64) {
        mutingGuardLock.lock()
        guard mutingGuardGeneration == expectedGeneration, isMutingGuardActiveInternal else {
            mutingGuardLock.unlock()
            return
        }
        let mutedDev = hardwareMutedDeviceID
        hardwareMutedDeviceID = nil
        let savedVol = preGuardAppVolume
        preGuardAppVolume = nil
        let wasDuckedAtEngage = preGuardWasDucked
        preGuardWasDucked = false
        let savedUnduckedVol = preGuardUnduckedVolume
        preGuardUnduckedVolume = nil
        isMutingGuardActiveInternal = false
        unmuteWorkItem = nil
        mutingGuardLock.unlock()

        if !PlaybackRouter.shared.isTestingEnvironment {
            if let devID = mutedDev, devID != 0 {
                _ = setHardwareMute(false, for: devID)
            }
            let isDLNAMuted = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isDLNAMuted }
            if !isDLNAMuted && savedVol != nil {
                let targetAppVol: Int
                if AudioDuckingController.shared.isDucked {
                    targetAppVol = wasDuckedAtEngage
                        ? (savedVol ?? AudioDuckingController.shared.currentDuckedVolume)
                        : AudioDuckingController.shared.currentDuckedVolume
                } else if PlaybackStateStore.shared.isVolumeLockedTo100 {
                    targetAppVol = 100
                } else if wasDuckedAtEngage {
                    let simVol = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.simulatedVolume }
                    targetAppVol = savedUnduckedVol ?? simVol
                } else {
                    let simVol = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.simulatedVolume }
                    targetAppVol = savedVol ?? simVol
                }
                mutingGuardLock.lock()
                if mutingGuardGeneration == expectedGeneration {
                    pendingAsyncVolumeRestoreTarget = targetAppVol
                }
                mutingGuardLock.unlock()

                DispatchQueue.global(qos: .utility).async { [weak self] in
                    guard let self else { return }
                    let shouldRestoreNow = self.mutingGuardLock.withLock {
                        self.mutingGuardGeneration == expectedGeneration && !self.isMutingGuardActiveInternal
                    }
                    if shouldRestoreNow, let app = MusicAppProvider.shared.getMusicApp() {
                        app.soundVolume = targetAppVol
                    }
                    self.mutingGuardLock.withLock {
                        if self.mutingGuardGeneration == expectedGeneration {
                            self.pendingAsyncVolumeRestoreTarget = nil
                        }
                    }
                }
            }
        }

        let stillInactive = mutingGuardLock.withLock {
            mutingGuardGeneration == expectedGeneration && !isMutingGuardActiveInternal
        }
        if stillInactive {
            AudioProcessTapService.shared.setMutingGuardZeroFill(false)
        }
    }

    @discardableResult
    internal func setHardwareMute(_ mute: Bool, for deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var isSettable: DarwinBoolean = false
        guard AudioObjectHasProperty(deviceID, &address),
              AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr,
              isSettable.boolValue else {
            return false
        }
        var val: UInt32 = mute ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &val) == noErr
    }

    // MARK: - Stream Physical Format Bit-Depth

    internal func isCurrentBitDepth(_ targetBits: UInt32, deviceID: AudioDeviceID, sampleRate: Double) -> Bool {
        var streamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamsSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &streamsAddress, 0, nil, &streamsSize) == noErr, streamsSize > 0 else { return true }

        let streamCount = Int(streamsSize) / MemoryLayout<AudioStreamID>.size
        var streamIDs = [AudioStreamID](repeating: 0, count: streamCount)
        guard AudioObjectGetPropertyData(deviceID, &streamsAddress, 0, nil, &streamsSize, &streamIDs) == noErr else { return true }

        for sID in streamIDs {
            var physAddress = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyPhysicalFormat,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var currentASBD = AudioStreamBasicDescription()
            var currentASBDSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            if AudioObjectGetPropertyData(sID, &physAddress, 0, nil, &currentASBDSize, &currentASBD) == noErr {
                if currentASBD.mBitsPerChannel != targetBits {
                    return false
                }
            }
        }
        return true
    }

    @discardableResult
    internal func setStreamBitDepth(_ targetBits: UInt32, sampleRate: Double, deviceID: AudioDeviceID) -> Bool {
        var streamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamsSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &streamsAddress, 0, nil, &streamsSize) == noErr, streamsSize > 0 else { return false }

        let streamCount = Int(streamsSize) / MemoryLayout<AudioStreamID>.size
        var streamIDs = [AudioStreamID](repeating: 0, count: streamCount)
        guard AudioObjectGetPropertyData(deviceID, &streamsAddress, 0, nil, &streamsSize, &streamIDs) == noErr else { return false }

        var anyChanged = false
        for sID in streamIDs {
            var physAddress = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyPhysicalFormat,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var isSettable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(sID, &physAddress, &isSettable) == noErr, isSettable.boolValue else { continue }

            var currentASBD = AudioStreamBasicDescription()
            var currentASBDSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            if AudioObjectGetPropertyData(sID, &physAddress, 0, nil, &currentASBDSize, &currentASBD) == noErr {
                if currentASBD.mBitsPerChannel == targetBits && abs(currentASBD.mSampleRate - sampleRate) < 0.5 {
                    anyChanged = true
                    continue // Already configured
                }
            }

            var availAddress = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyAvailablePhysicalFormats,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var availSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(sID, &availAddress, 0, nil, &availSize) == noErr, availSize > 0 else { continue }

            let count = Int(availSize) / MemoryLayout<AudioStreamRangedDescription>.size
            var ranged = [AudioStreamRangedDescription](repeating: AudioStreamRangedDescription(), count: count)
            guard AudioObjectGetPropertyData(sID, &availAddress, 0, nil, &availSize, &ranged) == noErr else { continue }

            let rateMatches = ranged.filter {
                sampleRate >= ($0.mSampleRateRange.mMinimum - 0.5) &&
                sampleRate <= ($0.mSampleRateRange.mMaximum + 0.5)
            }

            if let match = rateMatches.first(where: { $0.mFormat.mBitsPerChannel == targetBits }) {
                var newASBD = match.mFormat
                newASBD.mSampleRate = sampleRate
                let asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                if AudioObjectSetPropertyData(sID, &physAddress, 0, nil, asbdSize, &newASBD) == noErr {
                    anyChanged = true
                }
            }
        }
        return anyChanged
    }

    // MARK: - Hardware Volume

    public func outputVolume() -> Float? {
        guard let deviceID = getDefaultOutputDeviceID(),
              let (selector, elements) = volumeAddress(deviceID: deviceID) else {
            return nil
        }

        var values: [Float] = []
        for element in elements {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr {
                values.append(value)
            }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Float(values.count)
    }

    @discardableResult
    public func setOutputVolume(_ volume: Float) -> Bool {
        guard let deviceID = getDefaultOutputDeviceID(),
              let (selector, elements) = volumeAddress(deviceID: deviceID) else {
            return false
        }

        let clamped = min(max(volume, 0.0), 1.0)
        var success = false
        for element in elements {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            var isSettable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr, isSettable.boolValue else {
                continue
            }
            var val = Float32(clamped)
            let size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &val) == noErr {
                success = true
            }
        }
        return success
    }

    internal func volumeAddress(deviceID: AudioDeviceID) -> (selector: AudioObjectPropertySelector, elements: [AudioObjectPropertyElement])? {
        let virtualMainVolume = AudioObjectPropertySelector(0x766D_7663) // 'vmvc'
        let candidates: [AudioObjectPropertyElement] = [kAudioObjectPropertyElementMain, 1, 2]

        for selector in [kAudioDevicePropertyVolumeScalar, virtualMainVolume] {
            let present = candidates.filter { element in
                var address = AudioObjectPropertyAddress(
                    mSelector: selector,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: element
                )
                return AudioObjectHasProperty(deviceID, &address)
            }
            if present.contains(kAudioObjectPropertyElementMain) {
                return (selector, [kAudioObjectPropertyElementMain])
            }
            if !present.isEmpty {
                return (selector, present)
            }
        }
        return nil
    }
}
