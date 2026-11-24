//
//  AudioProcessTapService+HALCapture.swift
//  AppleMusicRemoteMac
//
//  CoreAudio CATapDescription & Private Aggregate Device Creation,
//  Process Object Discovery, and Sample Rate Convergence
//

import Foundation
import CoreAudio
import AppKit
import Darwin
import os

extension AudioProcessTapService {

    internal func readAggregateNominalRate() -> Double {
        guard !isTestingEnv, aggregateDeviceID != 0 else { return Double(sampleRate) }
        var rateAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var actualRate: Float64 = 0
        var actualSize = UInt32(MemoryLayout<Float64>.size)
        if AudioObjectGetPropertyData(aggregateDeviceID, &rateAddr, 0, nil, &actualSize, &actualRate) == noErr && actualRate > 0 {
            return actualRate
        }
        return 0
    }

    @discardableResult
    internal func applyAggregateNominalRateImmediate(_ targetRate: Int) -> OSStatus {
        guard !isTestingEnv, aggregateDeviceID != 0 else { return noErr }
        if let procID = ioProcID {
            AudioDeviceStop(aggregateDeviceID, procID)
        }
        var rateAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var newRate: Float64 = Float64(targetRate)
        let rateSize = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectSetPropertyData(aggregateDeviceID, &rateAddr, 0, nil, rateSize, &newRate)
        if let procID = ioProcID {
            AudioDeviceStart(aggregateDeviceID, procID)
        }
        return status
    }

    /// Resolves the actual sample rate at which `CATapDescription` / `AMR Tap Aggregate` can capture `Music.app`
    /// when the external DSP DAC is held in Hog Mode (so `Music.app` outputs to the system fallback device, e.g. MacBook Speakers capped at 96 kHz).
    public func resolveEffectiveTapSampleRate(forRequestedRate requestedRate: Int) -> Int {
        guard requestedRate > 0, !isTestingEnv else { return requestedRate }
        if AudioEngineController.shared.isActivePipelineHook {
            let dspDevID = AudioEngineController.shared.activeHardwareOutputDeviceID
            if let defID = CoreAudioDeviceManager.shared.getDefaultOutputDeviceID(), defID != 0, defID != dspDevID {
                let avail = CoreAudioDeviceManager.shared.availableSampleRates(deviceID: defID)
                if !avail.isEmpty {
                    let candidates = [Double(requestedRate), Double(requestedRate) / 2.0, Double(requestedRate) / 4.0, (requestedRate % 48_000 == 0) ? 48_000.0 : 44_100.0]
                    if let bestHostRate = candidates.first(where: { cand in avail.contains(where: { abs($0 - cand) < 1.0 }) }) {
                        return Int(bestHostRate.rounded())
                    }
                }
            }
        }
        return requestedRate
    }

    internal func resolveEffectiveConvergenceTargetRate(requestedRate: Int) -> Int {
        guard !isTestingEnv else { return requestedRate }
        if AudioEngineController.shared.isActivePipelineHook {
            return resolveEffectiveTapSampleRate(forRequestedRate: requestedRate)
        }
        // In local Passthrough / Pre-DSP mode, Music.app's AUHAL and the Process Tap always run at the Default Output Device's clock.
        if !DLNADiscoveryManager.shared.hasActiveRenderer,
           let defID = CoreAudioDeviceManager.shared.getDefaultOutputDeviceID(), defID != 0 {
            let hwRate = HALDeviceManager.nominalSampleRate(deviceID: defID)
            if hwRate >= 44_100.0 {
                return Int(hwRate.rounded())
            }
        }
        return requestedRate
    }

    internal func scheduleAggregateRateConvergence(requestedRate: Int, generation: UInt64) {
        let retryDelaysSec: [Double] = [0.12, 0.26, 0.46]
        for (attemptIdx, delaySec) in retryDelaysSec.enumerated() {
            let isFinalAttempt = (attemptIdx == retryDelaysSec.count - 1)
            queue.asyncAfter(deadline: .now() + delaySec) { [weak self] in
                guard let self = self,
                      self.rateConvergenceGeneration == generation,
                      self.isRealTapActive,
                      self.aggregateDeviceID != 0 else {
                    return
                }
                let effectiveTarget = self.resolveEffectiveConvergenceTargetRate(requestedRate: requestedRate)
                let currentAgg = self.readAggregateNominalRate()
                if currentAgg > 0 && abs(currentAgg - Double(effectiveTarget)) < 1.0 {
                    // Aggregate device converged! Ensure sampleRate, Local Passthrough Pre-DSP, and SDM/NOS match 1:1.
                    if self.sampleRate != effectiveTarget {
                        self.sampleRate = effectiveTarget
                    }
                    if RoomAcousticService.shared.isLocalPassthroughEQActive {
                        RoomAcousticService.shared.notifyLocalOutputFormatChanged(sampleRateHz: currentAgg)
                    }
                    if AudioEngineController.shared.isActivePipelineHook {
                        Task {
                            await AudioEngineController.shared.notifySourceSampleRateChanged(currentAgg)
                        }
                    }
                    self.rateConvergenceGeneration &+= 1 // Cancel remaining retry steps
                    return
                }

                if !isFinalAttempt {
                    _ = self.applyAggregateNominalRateImmediate(effectiveTarget)
                    let afterRetry = self.readAggregateNominalRate()
                    if afterRetry > 0 && abs(afterRetry - Double(effectiveTarget)) < 1.0 {
                        self.sampleRate = effectiveTarget
                        if RoomAcousticService.shared.isLocalPassthroughEQActive {
                            RoomAcousticService.shared.notifyLocalOutputFormatChanged(sampleRateHz: afterRetry)
                            RoomAcousticService.shared.resetLocalPassthroughBufferForRateTransition(sampleRateHz: afterRetry)
                        }
                        if AudioEngineController.shared.isActivePipelineHook {
                            Task {
                                await AudioEngineController.shared.notifySourceSampleRateChanged(afterRetry)
                            }
                        }
                        NSLog("[AudioProcessTapService] ✅ Aggregate nominal sample rate converged to \(effectiveTarget) Hz (attempt \(attemptIdx + 1))")
                        self.rateConvergenceGeneration &+= 1
                    }
                } else {
                    // CATapDescription kept its previous mix format across async retries — recreate Process Tap + Aggregate (~13 ms)
                    // so it binds cleanly to Music.app's active output stream rate!
                    NSLog("[AudioProcessTapService] 🔄 Recreating Process Tap to lock nominal sample rate \(effectiveTarget) Hz (was \(Int(currentAgg.rounded())) Hz)")
                    self.stopCaptureInternal()
                    self.sampleRate = effectiveTarget
                    self.startCaptureInternal()
                }
            }
        }
    }

    internal func applyFormatOnQueue(sampleRate: Int?, bitDepth: Int?) {
        var formatChanged = false
        if let b = bitDepth, (b == 16 || b == 20 || b == 24 || b == 32) {
            let effectiveDepth = (b == 16) ? 16 : 24
            if effectiveDepth != self.bitDepth {
                NSLog("[AudioProcessTapService] 🎛️ Switching tap bit depth to \(effectiveDepth)-bit (requested \(b)-bit, was \(self.bitDepth)-bit)")
                self.bitDepth = effectiveDepth
                formatChanged = true
            }
        }
        if let rawRate = sampleRate, rawRate > 0 {
            let r = self.resolveEffectiveTapSampleRate(forRequestedRate: rawRate)
            let aggCurrent = self.readAggregateNominalRate()
            let aggMismatch = (!self.isTestingEnv && self.aggregateDeviceID != 0 && aggCurrent > 0 && abs(aggCurrent - Double(r)) >= 1.0)
            if r != self.sampleRate || aggMismatch {
                if r != self.sampleRate {
                    NSLog("[AudioProcessTapService] 🎛️ Switching tap sample rate to \(r) Hz (requested \(rawRate) Hz, was \(self.sampleRate) Hz)")
                    self.sampleRate = r
                    formatChanged = true
                }

                // Если наш DSP-движок держит Hog Mode на внешнем ЦАП, Music.app выводит звук в системный fallback-выход (приглушённый через .muted tap).
                // Подстраиваем частоту этого fallback-устройства под сетку трека (44.1/48/88.2/96 кГц), чтобы CATapDescription отдавал бит-точные отсчёты!
                if !self.isTestingEnv && AudioEngineController.shared.isActivePipelineHook {
                    let dspDevID = AudioEngineController.shared.activeHardwareOutputDeviceID
                    if let defID = CoreAudioDeviceManager.shared.getDefaultOutputDeviceID(), defID != 0, defID != dspDevID {
                        let bestHostRate = Double(r)
                        var hostRateAddr = AudioObjectPropertyAddress(
                            mSelector: kAudioDevicePropertyNominalSampleRate,
                            mScope: kAudioObjectPropertyScopeGlobal,
                            mElement: kAudioObjectPropertyElementMain
                        )
                        var curHostRate: Float64 = 0
                        var sz = UInt32(MemoryLayout<Float64>.size)
                        _ = AudioObjectGetPropertyData(defID, &hostRateAddr, 0, nil, &sz, &curHostRate)
                        if abs(curHostRate - bestHostRate) > 0.5 {
                            var desiredHostRate = Float64(bestHostRate)
                            _ = AudioObjectSetPropertyData(defID, &hostRateAddr, 0, nil, sz, &desiredHostRate)
                        }
                    }
                    if r != rawRate {
                        let effectiveTapRateDouble = Double(r)
                        Task {
                            await AudioEngineController.shared.notifySourceSampleRateChanged(effectiveTapRateDouble)
                        }
                    }
                }

                if !self.isTestingEnv && RoomAcousticService.shared.isLocalPassthroughEQActive {
                    RoomAcousticService.shared.notifyLocalOutputFormatChanged(sampleRateHz: Double(r))
                }

                if self.aggregateDeviceID != 0 {
                    let status = self.applyAggregateNominalRateImmediate(r)
                    if status == noErr {
                        NSLog("[AudioProcessTapService] ✅ Aggregate device nominal sample rate requested: \(r) Hz")
                    } else {
                        NSLog("[AudioProcessTapService] ⚠️ Failed to set nominal sample rate on aggregate device: \(status)")
                    }
                    let immediateActual = self.readAggregateNominalRate()
                    self.rateConvergenceGeneration &+= 1
                    let convGen = self.rateConvergenceGeneration
                    if immediateActual > 0 && abs(immediateActual - Double(r)) < 1.0 {
                        if RoomAcousticService.shared.isLocalPassthroughEQActive {
                            RoomAcousticService.shared.resetLocalPassthroughBufferForRateTransition(sampleRateHz: immediateActual)
                        }
                        if AudioEngineController.shared.isActivePipelineHook {
                            Task {
                                await AudioEngineController.shared.notifySourceSampleRateChanged(immediateActual)
                            }
                        }
                    } else {
                        // CoreAudio aggregate / Music.app AUHAL rate adaptation is asynchronous (~100-300 ms);
                        // NEVER overwrite `self.sampleRate` with the stale pre-commit readback — schedule convergence instead!
                        self.scheduleAggregateRateConvergence(requestedRate: r, generation: convGen)
                    }
                }
            }
        }
        if formatChanged {
            self.streamFloatRingBuffer.reset()
            self.chunkAccumulator.removeAll()
        }
    }

    internal static func discoverAppleMusicAudioObjectIDs() -> [AudioObjectID] {
        guard #available(macOS 14.2, *) else { return [] }
        let musicPid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first?.processIdentifier ?? -1
        let selfPid = ProcessInfo.processInfo.processIdentifier

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var processIDs = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &processIDs) == noErr else {
            return []
        }

        var matched: [AudioObjectID] = []
        for objID in processIDs {
            var pidAddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var objPID: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            let gotPid = (AudioObjectGetPropertyData(objID, &pidAddr, 0, nil, &pidSize, &objPID) == noErr)

            if gotPid && objPID == musicPid && musicPid > 0 {
                matched.append(objID)
                continue
            }
            if gotPid && objPID == selfPid {
                continue
            }

            var bundleAddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyBundleID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var bundleRef: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            if AudioObjectGetPropertyData(objID, &bundleAddr, 0, nil, &bundleSize, &bundleRef) == noErr,
               let bStr = bundleRef?.takeRetainedValue() as String? {
                if bStr == "com.apple.Music" {
                    matched.append(objID)
                    continue
                }
            }

            if gotPid && objPID > 0 {
                var pathBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
                let len = proc_pidpath(objPID, &pathBuf, UInt32(pathBuf.count))
                if len > 0 {
                    let path = String(cString: pathBuf)
                    if path.hasSuffix("/Music.app/Contents/MacOS/Music") {
                        matched.append(objID)
                    }
                }
            }
        }
        return matched
    }

    /// Queries macOS CoreAudio HAL (`kAudioProcessPropertyIsRunningOutput`) in `< 0.1 ms`
    /// without AppleScript IPC to check whether `Music.app` is actively rendering audio frames.
    public static func isMusicAppRunningAudioOutput() -> Bool {
        guard #available(macOS 14.2, *) else { return false }
        let targetObjIDs = discoverAppleMusicAudioObjectIDs()
        guard !targetObjIDs.isEmpty else { return false }
        for objID in targetObjIDs {
            var runAddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningOutput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var isRunning: UInt32 = 0
            var runSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(objID, &runAddr, 0, nil, &runSize, &isRunning) == noErr, isRunning != 0 {
                return true
            }
        }
        return false
    }

    internal func startCaptureInternal() {
        guard !isTestingEnv else { return }
        guard !isRealTapActive else { return }
        self.passivePausedSinceMono = nil

        guard #available(macOS 14.2, *) else {
            NSLog("[AudioProcessTapService] ⚠️ CoreAudio Process Tap requires macOS 14.2+. Running silence generator fallback.")
            startSilenceGenerator()
            isCapturing = true
            return
        }

        let targetObjectIDs = Self.discoverAppleMusicAudioObjectIDs()
        guard !targetObjectIDs.isEmpty else {
            NSLog("[AudioProcessTapService] ⚠️ Apple Music audio object not found in HAL list yet. Running silence generator fallback.")
            startSilenceGenerator()
            isCapturing = true
            return
        }

        self.tappedProcessObjectIDs = Set(targetObjectIDs)
        NSLog("[AudioProcessTapService] 🎯 Found CoreAudio process object IDs: \(targetObjectIDs)")
        let tapDesc = CATapDescription(stereoMixdownOfProcesses: targetObjectIDs)
        tapDesc.name = "AMR Live Tap"
        let shouldMute = DLNADiscoveryManager.shared.hasActiveRenderer || AudioEngineController.shared.isActivePipelineHook || RoomAcousticService.shared.isLocalPassthroughEQActive
        tapDesc.muteBehavior = shouldMute ? .muted : .unmuted
        self.isTapMuted = shouldMute

        var newTapID: AudioObjectID = 0
        let tapStatus = AudioHardwareCreateProcessTap(tapDesc, &newTapID)
        guard tapStatus == noErr else {
            NSLog("[AudioProcessTapService] ❌ AudioHardwareCreateProcessTap failed with OSStatus \(tapStatus)")
            self.isTapMuted = false
            syncRealTapActiveFlag()
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
            self.isTapMuted = false
            syncRealTapActiveFlag()
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
            self.isTapMuted = false
            syncRealTapActiveFlag()
            return
        }
        self.aggregateDeviceID = newAggID
        syncRealTapActiveFlag()
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
            let confirmedInt = Int(round(actualRate))
            self.sampleRate = confirmedInt
            if RoomAcousticService.shared.isLocalPassthroughEQActive {
                RoomAcousticService.shared.notifyLocalOutputFormatChanged(sampleRateHz: actualRate)
                RoomAcousticService.shared.resetLocalPassthroughBufferForRateTransition(sampleRateHz: actualRate)
            }
            if AudioEngineController.shared.isActivePipelineHook {
                let confirmedRate = actualRate
                Task {
                    await AudioEngineController.shared.notifySourceSampleRateChanged(confirmedRate)
                }
            }
        }
        NSLog("[AudioProcessTapService] 🎛️ Tap active rate: \(self.sampleRate) Hz, channels: \(self.channels), bits: \(self.bitsPerSample)")

        // Setup IOProc Callback
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let ioCallback: AudioDeviceIOProc = { (_, _, inInputData, _, _, _, inClientData) -> OSStatus in
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
            self.isTapMuted = false
            syncRealTapActiveFlag()
            return
        }
        self.ioProcID = procID

        let startStatus = AudioDeviceStart(newAggID, procID)
        if startStatus == noErr {
            self.isCapturing = true
            let nowMono = Double(DispatchTime.now().uptimeNanoseconds) * 1.0e-9
            os_unfair_lock_lock(&self.silenceSpinLock)
            self.lastAudioReceivedTimeMono = nowMono
            self.lastNonZeroAudioTimeMono = nowMono
            self.mutedZeroSignalAccumulatedSec = 0.0
            os_unfair_lock_unlock(&self.silenceSpinLock)
            NSLog("[AudioProcessTapService] 🚀 Audio capture started successfully at \(self.sampleRate) Hz \(self.bitsPerSample)-bit")
        } else {
            NSLog("[AudioProcessTapService] ❌ AudioDeviceStart failed: \(startStatus)")
            AudioDeviceDestroyIOProcID(newAggID, procID)
            AudioHardwareDestroyAggregateDevice(newAggID)
            AudioHardwareDestroyProcessTap(newTapID)
            self.ioProcID = nil
            self.aggregateDeviceID = 0
            self.tapObjectID = 0
            self.isTapMuted = false
            syncRealTapActiveFlag()
            return
        }

        startSilenceGenerator()
    }

    internal func stopCaptureInternal() {
        rateConvergenceGeneration &+= 1
        passivePausedSinceMono = nil
        guard isCapturing || isRealTapActive else { return }
        stopSilenceGenerator()
        silenceTickCount = 0

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

        self.isTapMuted = false
        self.tappedProcessObjectIDs.removeAll()
        syncRealTapActiveFlag()
        self.isCapturing = false
        self.streamFloatRingBuffer.reset()
        self.chunkAccumulator.removeAll()
        NSLog("[AudioProcessTapService] 🛑 Audio capture stopped and resources released.")
    }
}
