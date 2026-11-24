//
//  SpectralIntegrityAnalyzer+TapIngestion.swift
//  AppleMusicRemoteMac
//
//  Real-Time Lock-Free Float32 PCM Ingestion from AudioProcessTapService,
//  DSP Queue Ring Drainer & Deterministic Unit-Test Helpers
//

import Foundation
import os

extension SpectralIntegrityAnalyzer {

    // MARK: - Real-Time Float32 PCM Ingestion from AudioProcessTapService

    public func processNonInterleavedFloatFrames(
        left: UnsafePointer<Float>,
        right: UnsafePointer<Float>,
        frameCount: Int
    ) {
        guard !isTestingEnv, frameCount > 0 else { return }
        let ampSoundCheckActive = ExternalAmpTCPController.shared.rtIsSoundCheckEnabledFlag
        guard os_unfair_lock_trylock(&rtSpinLock) else { return }

        guard rtIsEnabledFlag || ampSoundCheckActive else {
            os_unfair_lock_unlock(&rtSpinLock)
            return
        }

        let scanLSB = !rtIsValidationCachedFlag
        let startOffset = frameCount > Self.rtRingCapacity ? (frameCount - Self.rtRingCapacity) : 0
        let countToWrite = frameCount - startOffset
        let step = max(1, countToWrite / 512)

        var wIdx = rtRingWriteIdx
        var rIdx = rtRingReadIdx
        var count = rtRingCount
        var nonSilent = 0
        var lsb24 = 0

        for j in 0..<countToWrite {
            let srcIdx = startOffset + j
            let l = left[srcIdx]
            let r = right[srcIdx]
            if scanLSB && (j % step == 0) {
                let s24L = Int32((Double(l) * 8388608.0).rounded())
                let absL = abs(s24L)
                if absL > 256 {
                    nonSilent += 1
                    if (absL & 0xFE) != 0 {
                        lsb24 += 1
                    }
                }
            }
            rtRingL[wIdx] = l
            rtRingR[wIdx] = r
            rtRingMono[wIdx] = 0.5 * (l + r)
            wIdx = (wIdx + 1) & Self.rtRingMask
            if count < Self.rtRingCapacity {
                count += 1
            } else {
                rIdx = (rIdx + 1) & Self.rtRingMask
            }
        }

        rtRingWriteIdx = wIdx
        rtRingReadIdx = rIdx
        rtRingCount = count
        rtPendingNonSilent &+= nonSilent
        rtPendingLSB24 &+= lsb24

        let hasData = count > 0
        os_unfair_lock_unlock(&rtSpinLock)

        if hasData {
            rtDrainSignalSource.add(data: 1)
        }
    }

    public func processInterleavedFloatFrames(
        interleaved: UnsafePointer<Float>,
        floatCount: Int,
        channels: Int
    ) {
        guard !isTestingEnv else { return }
        let ch = max(1, channels)
        let frameCount = floatCount / ch
        guard frameCount > 0 else { return }

        let ampSoundCheckActive = ExternalAmpTCPController.shared.rtIsSoundCheckEnabledFlag
        guard os_unfair_lock_trylock(&rtSpinLock) else { return }

        guard rtIsEnabledFlag || ampSoundCheckActive else {
            os_unfair_lock_unlock(&rtSpinLock)
            return
        }

        let scanLSB = !rtIsValidationCachedFlag
        let startOffset = frameCount > Self.rtRingCapacity ? (frameCount - Self.rtRingCapacity) : 0
        let countToWrite = frameCount - startOffset
        let step = max(1, countToWrite / 512)

        var wIdx = rtRingWriteIdx
        var rIdx = rtRingReadIdx
        var count = rtRingCount
        var nonSilent = 0
        var lsb24 = 0

        for j in 0..<countToWrite {
            let f = startOffset + j
            let idx = f * ch
            let l = interleaved[idx]
            let r = (ch > 1) ? interleaved[idx + 1] : l
            if scanLSB && (j % step == 0) {
                let s24L = Int32((Double(l) * 8388608.0).rounded())
                let absL = abs(s24L)
                if absL > 256 {
                    nonSilent += 1
                    if (absL & 0xFE) != 0 {
                        lsb24 += 1
                    }
                }
            }
            rtRingL[wIdx] = l
            rtRingR[wIdx] = r
            rtRingMono[wIdx] = 0.5 * (l + r)
            wIdx = (wIdx + 1) & Self.rtRingMask
            if count < Self.rtRingCapacity {
                count += 1
            } else {
                rIdx = (rIdx + 1) & Self.rtRingMask
            }
        }

        rtRingWriteIdx = wIdx
        rtRingReadIdx = rIdx
        rtRingCount = count
        rtPendingNonSilent &+= nonSilent
        rtPendingLSB24 &+= lsb24

        let hasData = count > 0
        os_unfair_lock_unlock(&rtSpinLock)

        if hasData {
            rtDrainSignalSource.add(data: 1)
        }
    }

    internal func drainRTRingBufferOnDSPQueue() {
        while true {
            var nonSilent = 0
            var lsb24 = 0

            os_unfair_lock_lock(&rtSpinLock)
            let available = rtRingCount
            if available == 0 {
                rtConsumerScheduled = false
                os_unfair_lock_unlock(&rtSpinLock)
                return
            }

            let toRead = min(available, Self.dspDrainChunkCapacity)
            dspDrainL.removeAll(keepingCapacity: true)
            dspDrainR.removeAll(keepingCapacity: true)
            dspDrainMono.removeAll(keepingCapacity: true)

            var rIdx = rtRingReadIdx
            for _ in 0..<toRead {
                dspDrainL.append(rtRingL[rIdx])
                dspDrainR.append(rtRingR[rIdx])
                dspDrainMono.append(rtRingMono[rIdx])
                rIdx = (rIdx + 1) & Self.rtRingMask
            }
            rtRingReadIdx = rIdx
            rtRingCount = available - toRead
            nonSilent = rtPendingNonSilent
            lsb24 = rtPendingLSB24
            rtPendingNonSilent = 0
            rtPendingLSB24 = 0
            os_unfair_lock_unlock(&rtSpinLock)

            ingestStereoAndMonoFrames(
                left: dspDrainL,
                right: dspDrainR,
                mono: dspDrainMono,
                nonSilentCount: nonSilent,
                lsb24Count: lsb24
            )
        }
    }

    /// Synchronous helper for deterministic unit testing of synthetic mono audio signals.
    public func processFloatSamplesForTesting(
        samples: [Float],
        sampleRate: Int,
        claimedBitDepth: Int,
        isLossless: Bool,
        trackKey: String = "",
        trackId: String = "",
        isLocal: Bool = false
    ) -> SpectralAnalysisInfo {
        return processStereoSamplesForTesting(
            left: samples,
            right: samples,
            sampleRate: sampleRate,
            claimedBitDepth: claimedBitDepth,
            isLossless: isLossless,
            trackKey: trackKey,
            trackId: trackId,
            isLocal: isLocal
        )
    }

    /// Synchronous helper for deterministic unit testing of synthetic stereo audio signals
    /// (TT DR Meter, EBU R128 LUFS / LRA, 4x Polyphase True Peak dBTP, and Phase Correlation).
    public func processStereoSamplesForTesting(
        left: [Float],
        right: [Float],
        sampleRate: Int,
        claimedBitDepth: Int,
        isLossless: Bool,
        trackKey: String = "",
        trackId: String = "",
        isLocal: Bool = false
    ) -> SpectralAnalysisInfo {
        let frameCount = min(left.count, right.count)
        let leftSlice = left.count == frameCount ? left : Array(left.prefix(frameCount))
        let rightSlice = right.count == frameCount ? right : Array(right.prefix(frameCount))
        var mono = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            mono[i] = 0.5 * (leftSlice[i] + rightSlice[i])
        }

        let cleanKey = trackKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)
        let validRate = max(44100, sampleRate)
        let validDepth = isLossless ? (claimedBitDepth >= 24 ? 24 : 16) : 16

        lock.lock()
        defer { lock.unlock() }
        self.isEnabledInternal = true
        self.currentTrackKey = cleanKey
        self.currentTrackId = cleanId
        self.currentIsLocal = isLocal
        self.currentSampleRate = validRate
        self.claimedBitDepth = validDepth
        self.isClaimedLossless = isLossless
        self.isPlayingState = true
        resetAccumulatorsLocked()
        self.isSingleBufferTestMode = true
        self.activeCachedValidation = (!cleanKey.isEmpty || !cleanId.isEmpty)
            ? lookupCachedValidationLocked(
                trackId: cleanId,
                trackKey: cleanKey,
                isLocal: isLocal,
                sampleRate: validRate,
                claimedBitDepth: validDepth,
                isLossless: isLossless
            )
            : nil
        let isAlreadyCached = (self.activeCachedValidation != nil)

        var nonSilent = 0
        var lsb24 = 0
        if !isAlreadyCached {
            for s in leftSlice {
                let s24 = Int32((Double(s) * 8388608.0).rounded())
                let absS = abs(s24)
                if absS > 256 {
                    nonSilent += 1
                    if (absS & 0xFE) != 0 {
                        lsb24 += 1
                    }
                }
            }
        }

        ingestStereoTelemetryLocked(left: leftSlice, right: rightSlice)
        ingestMonoFramesLocked(mono, nonSilentCount: nonSilent, lsb24Count: lsb24)
        return latestResult
    }

    internal func ingestStereoAndMonoFrames(
        left: [Float],
        right: [Float],
        mono: [Float],
        nonSilentCount: Int,
        lsb24Count: Int
    ) {
        lock.lock()
        defer { lock.unlock() }
        ingestStereoTelemetryLocked(left: left, right: right)
        ingestMonoFramesLocked(mono, nonSilentCount: nonSilentCount, lsb24Count: lsb24Count)
    }
}
