//
//  RoomAcousticService+LocalPassthroughRing.swift
//  AppleMusicRemoteMac
//
//  Real-Time Lock-Free Ring Buffer Ingestion, Pre-DSP Block Renderer & Deterministic Test Hooks
//

import AudioToolbox
import CoreAudio
import Darwin
import Foundation
import os

extension RoomAcousticService {

    internal func resetLocalPassthroughRingLocked(sampleRate: Double, armFadeIn: Bool) {
        localEQSampleRate = max(44_100.0, sampleRate)
        localEQRingReadIdx = 0
        localEQRingWriteIdx = 0
        localEQRingCount = 0
        localEQRingPrimed = false
        if armFadeIn {
            localEQFadeInCurrent = 0.0
            localEQFadeInStep = Float(1.0 / max(64.0, localEQSampleRate * 0.012))
        } else {
            localEQFadeInCurrent = 1.0
            localEQFadeInStep = 0.0
        }
    }

    /// Flushes stale pre-switch samples from the Local Passthrough Pre-DSP ring buffer once the Process Tap settles on a new rate.
    public func resetLocalPassthroughBufferForRateTransition(sampleRateHz: Double) {
        guard sampleRateHz >= 44_100.0 else { return }
        os_unfair_lock_lock(&localEQRingLock)
        let active = localEQRingUnitActiveFlag
        if active {
            resetLocalPassthroughRingLocked(sampleRate: sampleRateHz, armFadeIn: true)
        }
        os_unfair_lock_unlock(&localEQRingLock)
        if active {
            MasteringRestorationService.shared.resetLocalPassthroughState()
            localPassthroughProcessor.resetState()
            LateNightDRCService.shared.resetLocalPassthroughState()
        }
    }

    public func feedLocalPassthroughPlanarFloat32(
        left: UnsafePointer<Float>,
        right: UnsafePointer<Float>,
        frames: Int,
        sampleRate: Int
    ) {
        guard frames > 0 else { return }
        let lockedStreamRate: Double = BitPerfectLogMonitor.shared.isEnabled
            ? (BitPerfectLogMonitor.shared.currentDetectedSampleRate ?? 0.0)
            : 0.0
        var triggerAsyncRateSync = false
        os_unfair_lock_lock(&localEQRingLock)
        guard localEQRingUnitActiveFlag else {
            os_unfair_lock_unlock(&localEQRingLock)
            return
        }
        if sampleRate >= 44_100 {
            let incomingRate = Double(sampleRate)
            if localEQRingConfiguredUnitRate > 0 && abs(localEQRingConfiguredUnitRate - incomingRate) > 1.0 {
                if lockedStreamRate >= 44_100.0 && abs(localEQRingConfiguredUnitRate - lockedStreamRate) <= 1.0 {
                    // AudioUnit is already locked to the target stream rate; ignore stale draining tap frames
                    os_unfair_lock_unlock(&localEQRingLock)
                    return
                }
                localEQSampleRate = incomingRate
                if !localEQAsyncReconfigPending {
                    localEQAsyncReconfigPending = true
                    resetLocalPassthroughRingLocked(sampleRate: incomingRate, armFadeIn: true)
                    triggerAsyncRateSync = true
                }
            } else if abs(localEQSampleRate - incomingRate) > 1.0 {
                localEQSampleRate = incomingRate
            }
        }

        let effectiveSR = max(44_100, sampleRate)
        let maxBuffered = min(Self.localEQRingCapacity - 1024, max(8192, effectiveSR / 5))
        let countToWrite = min(frames, maxBuffered)
        let srcOffset = frames - countToWrite

        if localEQRingCount + countToWrite > maxBuffered {
            // Trim oldest samples back to a ~40 ms cushion so clock drift never causes chop-dropping
            let targetKeep = min(localEQRingCount, max(2048, effectiveSR / 25))
            let dropCount = max(0, localEQRingCount - targetKeep)
            localEQRingReadIdx = (localEQRingReadIdx + dropCount) & Self.localEQRingMask
            localEQRingCount -= dropCount
            localEQFadeInCurrent = min(localEQFadeInCurrent, 0.35)
            localEQFadeInStep = Float(0.65 / max(32.0, Double(effectiveSR) * 0.006))
        }

        var w = localEQRingWriteIdx
        for i in 0..<countToWrite {
            localEQRingL[w] = left[srcOffset + i]
            localEQRingR[w] = right[srcOffset + i]
            w = (w + 1) & Self.localEQRingMask
        }
        localEQRingWriteIdx = w
        localEQRingCount += countToWrite
        os_unfair_lock_unlock(&localEQRingLock)

        if triggerAsyncRateSync {
            let newRateHz = Double(sampleRate)
            localEQControlQueue.async { [weak self] in
                self?.notifyLocalOutputFormatChanged(sampleRateHz: newRateHz)
            }
        }
    }

    public func feedLocalPassthroughInterleavedFloat32(
        interleaved: UnsafePointer<Float>,
        frames: Int,
        channels: Int,
        sampleRate: Int
    ) {
        guard frames > 0, channels >= 1 else { return }
        let lockedStreamRate: Double = BitPerfectLogMonitor.shared.isEnabled
            ? (BitPerfectLogMonitor.shared.currentDetectedSampleRate ?? 0.0)
            : 0.0
        var triggerAsyncRateSync = false
        os_unfair_lock_lock(&localEQRingLock)
        guard localEQRingUnitActiveFlag else {
            os_unfair_lock_unlock(&localEQRingLock)
            return
        }
        if sampleRate >= 44_100 {
            let incomingRate = Double(sampleRate)
            if localEQRingConfiguredUnitRate > 0 && abs(localEQRingConfiguredUnitRate - incomingRate) > 1.0 {
                if lockedStreamRate >= 44_100.0 && abs(localEQRingConfiguredUnitRate - lockedStreamRate) <= 1.0 {
                    os_unfair_lock_unlock(&localEQRingLock)
                    return
                }
                localEQSampleRate = incomingRate
                if !localEQAsyncReconfigPending {
                    localEQAsyncReconfigPending = true
                    resetLocalPassthroughRingLocked(sampleRate: incomingRate, armFadeIn: true)
                    triggerAsyncRateSync = true
                }
            } else if abs(localEQSampleRate - incomingRate) > 1.0 {
                localEQSampleRate = incomingRate
            }
        }

        let effectiveSR = max(44_100, sampleRate)
        let maxBuffered = min(Self.localEQRingCapacity - 1024, max(8192, effectiveSR / 5))
        let countToWrite = min(frames, maxBuffered)
        let srcOffset = frames - countToWrite

        if localEQRingCount + countToWrite > maxBuffered {
            let targetKeep = min(localEQRingCount, max(2048, effectiveSR / 25))
            let dropCount = max(0, localEQRingCount - targetKeep)
            localEQRingReadIdx = (localEQRingReadIdx + dropCount) & Self.localEQRingMask
            localEQRingCount -= dropCount
            localEQFadeInCurrent = min(localEQFadeInCurrent, 0.35)
            localEQFadeInStep = Float(0.65 / max(32.0, Double(effectiveSR) * 0.006))
        }

        var w = localEQRingWriteIdx
        for i in 0..<countToWrite {
            let base = (srcOffset + i) * channels
            let l = interleaved[base]
            let r = channels >= 2 ? interleaved[base + 1] : l
            localEQRingL[w] = l
            localEQRingR[w] = r
            w = (w + 1) & Self.localEQRingMask
        }
        localEQRingWriteIdx = w
        localEQRingCount += countToWrite
        os_unfair_lock_unlock(&localEQRingLock)

        if triggerAsyncRateSync {
            let newRateHz = Double(sampleRate)
            localEQControlQueue.async { [weak self] in
                self?.notifyLocalOutputFormatChanged(sampleRateHz: newRateHz)
            }
        }
    }

    internal static func makeNonInterleavedFloat32ASBD(sampleRate: Double) -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
    }

    @usableFromInline
    @inline(__always)
    internal func renderLocalPassthroughBlock(
        leftOut: UnsafeMutablePointer<Float>,
        rightOut: UnsafeMutablePointer<Float>,
        frames: Int,
        useStartupCushion: Bool,
        customDRCProcessor: LateNightDRCProcessor? = nil
    ) {
        guard frames > 0 else { return }

        os_unfair_lock_lock(&localEQRingLock)
        let sr = max(44_100, Int(localEQSampleRate.rounded()))
        if useStartupCushion && !localEQRingPrimed {
            let primeThreshold = max(frames, sr / 60)
            if localEQRingCount < primeThreshold {
                os_unfair_lock_unlock(&localEQRingLock)
                memset(leftOut, 0, frames * MemoryLayout<Float>.size)
                memset(rightOut, 0, frames * MemoryLayout<Float>.size)
                return
            }
            localEQRingPrimed = true
        }

        let toCopy = min(frames, localEQRingCount)
        var rIdx = localEQRingReadIdx
        for i in 0..<toCopy {
            leftOut[i] = localEQRingL[rIdx]
            rightOut[i] = localEQRingR[rIdx]
            rIdx = (rIdx + 1) & Self.localEQRingMask
        }
        localEQRingReadIdx = rIdx
        localEQRingCount -= toCopy

        let fadeStart = localEQFadeInCurrent
        let fadeStep = localEQFadeInStep
        if fadeStart < 1.0 && toCopy > 0 {
            localEQFadeInCurrent = min(1.0, fadeStart + fadeStep * Float(toCopy))
        }
        if toCopy < frames {
            localEQRingPrimed = false
            localEQFadeInCurrent = 0.0
            localEQFadeInStep = Float(1.0 / max(64.0, Double(sr) * 0.012))
        }
        os_unfair_lock_unlock(&localEQRingLock)

        if toCopy < frames {
            memset(leftOut.advanced(by: toCopy), 0, (frames - toCopy) * MemoryLayout<Float>.size)
            memset(rightOut.advanced(by: toCopy), 0, (frames - toCopy) * MemoryLayout<Float>.size)
        }

        let srDouble = Double(sr)
        let isTestNoise = isTestSignalPlaying
        let applyFade = fadeStart < 0.99999 && fadeStep > 0.0
        if toCopy > 0 && !isTestNoise {
            if customDRCProcessor == nil {
                MasteringRestorationService.shared.processLocalPassthroughPlanarFloat32IfEnabled(
                    left: leftOut,
                    right: rightOut,
                    frameCount: toCopy,
                    sampleRate: srDouble
                )
            }
            localPassthroughProcessor.processPlanarFloat32(
                left: leftOut,
                right: rightOut,
                frameCount: toCopy,
                sampleRate: sr
            )
            if let customDRC = customDRCProcessor {
                customDRC.processPlanarFloat32(
                    left: leftOut,
                    right: rightOut,
                    frameCount: toCopy,
                    sampleRate: srDouble
                )
            } else {
                LateNightDRCService.shared.processLocalPassthroughPlanarFloat32IfEnabled(
                    left: leftOut,
                    right: rightOut,
                    frameCount: toCopy,
                    sampleRate: srDouble
                )
            }
        }
        if applyFade {
            for i in 0..<toCopy {
                let g = min(1.0, fadeStart + fadeStep * Float(i))
                leftOut[i] *= g
                rightOut[i] *= g
            }
        }
    }

    // MARK: - Deterministic Test Hooks for Local Passthrough Pre-DSP

    internal func setSimulatedLocalPassthroughActiveForTesting(_ active: Bool, initialSampleRateHz: Double = 48_000.0) {
        localEQUnitLifecycleLock.lock()
        defer { localEQUnitLifecycleLock.unlock() }
        let rate = max(44_100.0, initialSampleRateHz)
        os_unfair_lock_lock(&localEQRingLock)
        localEQRingUnitActiveFlag = active
        localEQRingConfiguredUnitRate = active ? rate : 0.0
        localEQAsyncReconfigPending = false
        resetLocalPassthroughRingLocked(sampleRate: rate, armFadeIn: active)
        os_unfair_lock_unlock(&localEQRingLock)
        localPassthroughProcessor.resetState()
        lock.withLock {
            simulatedLocalEQActiveForTesting = active
            localEQConfiguredSampleRate = active ? rate : 0.0
            localEQConfiguredDeviceID = 0
            if !active {
                localEQReconfigGeneration = 0
            }
            syncFastFlagsFromStateLocked()
        }
    }

    internal func renderLocalPassthroughFramesForTesting(
        leftOut: UnsafeMutablePointer<Float>,
        rightOut: UnsafeMutablePointer<Float>,
        frames: Int,
        useStartupCushion: Bool = false,
        customDRCProcessor: LateNightDRCProcessor? = nil
    ) {
        renderLocalPassthroughBlock(
            leftOut: leftOut,
            rightOut: rightOut,
            frames: frames,
            useStartupCushion: useStartupCushion,
            customDRCProcessor: customDRCProcessor
        )
    }
}
