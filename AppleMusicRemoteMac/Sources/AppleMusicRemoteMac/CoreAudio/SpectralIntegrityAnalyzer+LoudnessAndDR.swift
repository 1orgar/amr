//
//  SpectralIntegrityAnalyzer+LoudnessAndDR.swift
//  AppleMusicRemoteMac
//
//  4x Polyphase True Peak (dBTP), ITU-R BS.1770-4 / EBU R128 K-Weighting (LUFS / LRA),
//  TT DR Meter & Stereo Phase Correlation Evaluation
//

import Foundation
import Accelerate

extension SpectralIntegrityAnalyzer {

    // MARK: - Core EBU R128, TT DR & Stereo Telemetry Evaluation

    internal func ensureKWeightingInitializedLocked() {
        let sr = max(44100, currentSampleRate)
        guard kWeightSampleRate != sr else { return }
        kWeightSampleRate = sr
        let fs = Double(sr)

        // Stage 1: ITU-R BS.1770-4 Acoustic Head High-Shelf (+4.0 dB @ 1681.97 Hz)
        let f0Shelf = 1681.974450955533
        let gShelf = 3.99984385397
        let qShelf = 0.7071752369554196
        let k1 = tan(Double.pi * f0Shelf / fs)
        let vh = pow(10.0, gShelf / 20.0)
        let vb = pow(vh, 0.499666774155)
        let a0_1 = 1.0 + k1 / qShelf + k1 * k1
        kwStage1 = KWeightBiquadCoeffs(
            b0: (vh + vb * k1 / qShelf + k1 * k1) / a0_1,
            b1: 2.0 * (k1 * k1 - vh) / a0_1,
            b2: (vh - vb * k1 / qShelf + k1 * k1) / a0_1,
            a1: 2.0 * (k1 * k1 - 1.0) / a0_1,
            a2: (1.0 - k1 / qShelf + k1 * k1) / a0_1
        )

        // Stage 2: ITU-R BS.1770-4 RLB High-Pass (@ 38.135 Hz)
        let f0Hp = 38.13547087602444
        let qHp = 0.5003270373238773
        let k2 = tan(Double.pi * f0Hp / fs)
        let a0_2 = 1.0 + k2 / qHp + k2 * k2
        kwStage2 = KWeightBiquadCoeffs(
            b0: 1.0 / a0_2,
            b1: -2.0 / a0_2,
            b2: 1.0 / a0_2,
            a1: 2.0 * (k2 * k2 - 1.0) / a0_2,
            a2: (1.0 - k2 / qHp + k2 * k2) / a0_2
        )
    }

    @inline(__always)
    internal func pushTruePeakPairLocked(_ l: Float, _ r: Float) {
        tpRingPos = (tpRingPos == 0) ? 11 : (tpRingPos - 1)
        tpRingL[tpRingPos] = l
        tpRingL[tpRingPos + 12] = l
        tpRingR[tpRingPos] = r
        tpRingR[tpRingPos + 12] = r
        tpWarmupSamples += 1

        let absL = Double(abs(l))
        let absR = Double(abs(r))
        if absL > maxTruePeakLinear { maxTruePeakLinear = absL }
        if absR > maxTruePeakLinear { maxTruePeakLinear = absR }

        if absL < 0.92 { tpInClipL = false }
        if absR < 0.92 { tpInClipR = false }

        guard tpWarmupSamples >= 12 else { return }

        let baseIdx = tpRingPos
        let centerMaxL = max(abs(tpRingL[baseIdx + 5]), abs(tpRingL[baseIdx + 6]))
        let centerMaxR = max(abs(tpRingR[baseIdx + 5]), abs(tpRingR[baseIdx + 6]))
        let gateThresh = Float(min(0.60, maxTruePeakLinear * 0.58))

        if centerMaxL > gateThresh || centerMaxL > 0.65 {
            var localMaxL = Double(centerMaxL)
            for phase in Self.truePeakPolyphasePhases {
                var sum: Float = 0.0
                for m in 0..<12 {
                    sum += tpRingL[baseIdx + m] * phase[m]
                }
                let mag = Double(abs(sum))
                if mag > localMaxL { localMaxL = mag }
            }
            if localMaxL > maxTruePeakLinear { maxTruePeakLinear = localMaxL }
            if localMaxL > 1.000115 && !tpInClipL {
                liveIspClipCount += 1
                tpInClipL = true
            }
        } else if absL > 1.000115 && !tpInClipL {
            liveIspClipCount += 1
            tpInClipL = true
        }

        if centerMaxR > gateThresh || centerMaxR > 0.65 {
            var localMaxR = Double(centerMaxR)
            for phase in Self.truePeakPolyphasePhases {
                var sum: Float = 0.0
                for m in 0..<12 {
                    sum += tpRingR[baseIdx + m] * phase[m]
                }
                let mag = Double(abs(sum))
                if mag > localMaxR { localMaxR = mag }
            }
            if localMaxR > maxTruePeakLinear { maxTruePeakLinear = localMaxR }
            if localMaxR > 1.000115 && !tpInClipR {
                liveIspClipCount += 1
                tpInClipR = true
            }
        } else if absR > 1.000115 && !tpInClipR {
            liveIspClipCount += 1
            tpInClipR = true
        }
    }

    internal func ingestStereoTelemetryLocked(left: [Float], right: [Float]) {
        let n = min(left.count, right.count)
        guard n > 0 else { return }
        ensureKWeightingInitializedLocked()
        let sr = max(44100, currentSampleRate)

        // 1. Stereo Phase Correlation (-1 ... 0 ... +1), Mid/Side Width (%), L/R Balance (dB)
        var sumLL: Float = 0.0
        var sumRR: Float = 0.0
        var sumLR: Float = 0.0
        vDSP_dotpr(left, 1, left, 1, &sumLL, vDSP_Length(n))
        vDSP_dotpr(right, 1, right, 1, &sumRR, vDSP_Length(n))
        vDSP_dotpr(left, 1, right, 1, &sumLR, vDSP_Length(n))

        let meanPower = (Double(sumLL) + Double(sumRR)) / Double(2 * n)
        if meanPower > 1e-9 {
            let dLL = Double(sumLL)
            let dRR = Double(sumRR)
            let dLR = Double(sumLR)
            let corr: Double
            if dLL > 1e-12 && dRR > 1e-12 {
                corr = max(-1.0, min(1.0, dLR / sqrt(dLL * dRR)))
            } else {
                corr = 0.0
            }
            let eMid = max(0.0, 0.25 * (dLL + dRR + 2.0 * dLR))
            let eSide = max(0.0, 0.25 * (dLL + dRR - 2.0 * dLR))
            let widthPct = max(0.0, min(100.0, 100.0 * sqrt(eSide / max(1e-12, eMid + eSide))))
            let balDb = max(-12.0, min(12.0, 10.0 * log10(max(dRR, 1e-12) / max(dLL, 1e-12))))

            let dt = Double(n) / Double(sr)
            let alpha = (!hasStereoMeasurement || isSingleBufferTestMode)
                ? 1.0
                : min(1.0, 1.0 - exp(-dt / 0.18))
            hasStereoMeasurement = true
            livePhaseCorrelation = max(-1.0, min(1.0, livePhaseCorrelation + alpha * (corr - livePhaseCorrelation)))
            liveStereoWidthPercent = liveStereoWidthPercent + alpha * (widthPct - liveStereoWidthPercent)
            liveChannelBalanceDb = liveChannelBalanceDb + alpha * (balDb - liveChannelBalanceDb)
        }

        // 2. Per-sample 4x True Peak + BS.1770-4 K-Weighting + 3.0s TT DR Block Accumulation
        let subBlockTarget = max(1, sr / 10) // 100 ms sub-blocks for EBU R128
        let ttBlockTarget = isSingleBufferTestMode
            ? min(sr * 3, max(4096, n / 4))
            : (sr * 3)

        let s1 = kwStage1
        let s2 = kwStage2
        var l1z1 = kwL1z1, l1z2 = kwL1z2, l2z1 = kwL2z1, l2z2 = kwL2z2
        var r1z1 = kwR1z1, r1z2 = kwR1z2, r2z1 = kwR2z1, r2z2 = kwR2z2

        var didCompleteTtBlock = false

        for i in 0..<n {
            let l = left[i]
            let r = right[i]
            pushTruePeakPairLocked(l, r)

            let dl = Double(l)
            let dr = Double(r)

            // K-weighting biquad cascade
            let klMid = s1.process(dl, z1: &l1z1, z2: &l1z2)
            let kl = s2.process(klMid, z1: &l2z1, z2: &l2z2)
            let krMid = s1.process(dr, z1: &r1z1, z2: &r1z2)
            let kr = s2.process(krMid, z1: &r2z1, z2: &r2z2)

            ebuSubBlockSumSqL += kl * kl
            ebuSubBlockSumSqR += kr * kr
            ebuSubBlockAccumSamples += 1
            if ebuSubBlockAccumSamples >= subBlockTarget {
                let zSub = (ebuSubBlockSumSqL + ebuSubBlockSumSqR) / Double(ebuSubBlockAccumSamples)
                ebuSubBlockSumSqL = 0.0
                ebuSubBlockSumSqR = 0.0
                ebuSubBlockAccumSamples = 0
                processEbu100msSubBlockLocked(zSub)
            }

            // TT DR 3.0-second window accumulation
            let al = abs(dl)
            let ar = abs(dr)
            ttDrSumSqL += dl * dl
            ttDrSumSqR += dr * dr
            if al > ttDrBlockPeakL { ttDrBlockPeakL = al }
            if ar > ttDrBlockPeakR { ttDrBlockPeakR = ar }
            ttDrAccumSamples += 1
            if ttDrAccumSamples >= ttBlockTarget {
                let invN = 1.0 / Double(ttDrAccumSamples)
                let rmsL = sqrt(2.0 * ttDrSumSqL * invN)
                let rmsR = sqrt(2.0 * ttDrSumSqR * invN)
                if max(rmsL, rmsR) >= 1e-4 {
                    ttDrBlockRmsL.append(rmsL)
                    ttDrBlockRmsR.append(rmsR)
                    ttDrBlockPeaksL.append(ttDrBlockPeakL)
                    ttDrBlockPeaksR.append(ttDrBlockPeakR)
                    didCompleteTtBlock = true
                }
                ttDrSumSqL = 0.0
                ttDrSumSqR = 0.0
                ttDrBlockPeakL = 0.0
                ttDrBlockPeakR = 0.0
                ttDrAccumSamples = 0
            }
        }

        kwL1z1 = l1z1; kwL1z2 = l1z2; kwL2z1 = l2z1; kwL2z2 = l2z2
        kwR1z1 = r1z1; kwR1z2 = r1z2; kwR2z1 = r2z1; kwR2z2 = r2z2

        if isSingleBufferTestMode {
            // Flush 6 trailing zeros so any peak near the end of a synthetic test buffer passes the 12-tap FIR center
            for _ in 0..<6 {
                pushTruePeakPairLocked(0.0, 0.0)
            }
        }

        if maxTruePeakLinear > 1e-6 {
            liveTruePeakDbtp = 20.0 * log10(maxTruePeakLinear)
        }

        if didCompleteTtBlock {
            recomputeTtDrScoreLocked()
            maybeUpdateCachedTelemetryMilestoneLocked()
        }
    }

    internal func processEbu100msSubBlockLocked(_ zSub: Double) {
        ebuRecent100msEnergies.append(zSub)
        if ebuRecent100msEnergies.count > 30 {
            ebuRecent100msEnergies.removeFirst(ebuRecent100msEnergies.count - 30)
        }

        let recentCount = ebuRecent100msEnergies.count
        if recentCount >= 4 {
            let z400 = ebuRecent100msEnergies.suffix(4).reduce(0.0, +) * 0.25
            let mLufs = z400 > 1e-12 ? (-0.691 + 10.0 * log10(z400)) : -96.0
            liveMomentaryLufs = max(-70.0, min(6.0, mLufs))

            // Absolute gate Gamma_a = -70.0 LUFS
            if mLufs > -70.0 {
                if ebuGated400msBlocks.count >= 36000 {
                    ebuGated400msBlocks.removeFirst(1000)
                }
                ebuGated400msBlocks.append(z400)
                recomputeIntegratedLufsLocked()
                emitLiveDynamicsUpdateIfNeededLocked()
            }
        }

        if recentCount >= 4 {
            let zSt = ebuRecent100msEnergies.reduce(0.0, +) / Double(recentCount)
            let stLufs = zSt > 1e-12 ? (-0.691 + 10.0 * log10(zSt)) : -96.0
            liveShortTermLufs = max(-70.0, min(6.0, stLufs))

            let minStSubBlocks = isSingleBufferTestMode ? 10 : 30
            if recentCount >= minStSubBlocks && stLufs > -70.0 {
                if ebuShortTermBlocks.count >= 12000 {
                    ebuShortTermBlocks.removeFirst(500)
                }
                ebuShortTermBlocks.append(zSt)
                recomputeLoudnessRangeLocked()
            }
        }
    }

    internal func recomputeIntegratedLufsLocked() {
        guard !ebuGated400msBlocks.isEmpty else { return }
        let meanAbs = ebuGated400msBlocks.reduce(0.0, +) / Double(ebuGated400msBlocks.count)
        guard meanAbs > 1e-12 else { return }
        let lAbs = -0.691 + 10.0 * log10(meanAbs)
        let relGateThresholdZ = pow(10.0, (lAbs - 10.0 + 0.691) / 10.0)

        var sumRel = 0.0
        var countRel = 0
        for z in ebuGated400msBlocks where z >= relGateThresholdZ {
            sumRel += z
            countRel += 1
        }
        if countRel > 0 {
            let lInt = -0.691 + 10.0 * log10(sumRel / Double(countRel))
            liveIntegratedLufs = max(-70.0, min(6.0, lInt))
        }
    }

    internal func recomputeLoudnessRangeLocked() {
        guard ebuShortTermBlocks.count >= 2 else { return }
        let meanAbs = ebuShortTermBlocks.reduce(0.0, +) / Double(ebuShortTermBlocks.count)
        guard meanAbs > 1e-12 else { return }
        let lAbs = -0.691 + 10.0 * log10(meanAbs)
        let relGateZ = pow(10.0, (lAbs - 20.0 + 0.691) / 10.0)

        var gatedDb: [Double] = []
        gatedDb.reserveCapacity(ebuShortTermBlocks.count)
        for z in ebuShortTermBlocks where z >= relGateZ {
            gatedDb.append(-0.691 + 10.0 * log10(max(z, 1e-12)))
        }
        guard gatedDb.count >= 2 else { return }
        gatedDb.sort()
        let p10Idx = min(gatedDb.count - 1, max(0, Int(Double(gatedDb.count - 1) * 0.10)))
        let p95Idx = min(gatedDb.count - 1, max(0, Int(Double(gatedDb.count - 1) * 0.95)))
        liveLoudnessRangeLu = max(0.0, gatedDb[p95Idx] - gatedDb[p10Idx])
    }

    internal func recomputeTtDrScoreLocked() {
        let bCount = min(ttDrBlockRmsL.count, ttDrBlockRmsR.count)
        guard bCount >= 1 else { return }

        func computeChannelDr(rmsValues: [Double], peakValues: [Double]) -> Double {
            let sortedRms = rmsValues.sorted(by: >)
            let topK = max(1, Int(floor(0.20 * Double(sortedRms.count))))
            var sumSq = 0.0
            for i in 0..<topK {
                sumSq += sortedRms[i] * sortedRms[i]
            }
            let rmsTop20 = sqrt(sumSq / Double(topK))
            let sortedPeaks = peakValues.sorted(by: >)
            let refPeak = sortedPeaks[min(1, sortedPeaks.count - 1)]
            guard rmsTop20 > 1e-6, refPeak > 1e-6 else { return 14.0 }
            return max(0.0, min(24.0, 20.0 * log10(refPeak / rmsTop20)))
        }

        let drL = computeChannelDr(rmsValues: ttDrBlockRmsL, peakValues: ttDrBlockPeaksL)
        let drR = computeChannelDr(rmsValues: ttDrBlockRmsR, peakValues: ttDrBlockPeaksR)
        let officialDr = Int(((drL + drR) * 0.5).rounded())
        liveTtDrScore = max(0, min(24, officialDr))
    }

    internal func maybeUpdateCachedTelemetryMilestoneLocked() {
        guard var cached = activeCachedValidation, cached.isAuthentic else { return }
        let blockCount = ttDrBlockRmsL.count
        let isMilestone = isSingleBufferTestMode || blockCount == 1 || blockCount == 5 || blockCount == 15 || blockCount == 30
        guard isMilestone else { return }

        var changed = false
        if let dr = liveTtDrScore, cached.ttDrScore != dr {
            cached.ttDrScore = dr
            changed = true
        }
        if let lufs = liveIntegratedLufs {
            let rounded = (lufs * 10.0).rounded() / 10.0
            if cached.integratedLufs != rounded {
                cached.integratedLufs = rounded
                changed = true
            }
        }
        if let lra = liveLoudnessRangeLu {
            let rounded = (lra * 10.0).rounded() / 10.0
            if cached.loudnessRangeLu != rounded {
                cached.loudnessRangeLu = rounded
                changed = true
            }
        }
        if let tp = liveTruePeakDbtp {
            let rounded = (tp * 10.0).rounded() / 10.0
            if cached.truePeakDbtp != rounded {
                cached.truePeakDbtp = rounded
                changed = true
            }
        }
        if changed {
            activeCachedValidation = cached
            storePassedValidationLocked(cached, isLossless: isClaimedLossless)
        }
    }

    internal func emitLiveDynamicsUpdateIfNeededLocked() {
        let count = ebuGated400msBlocks.count
        let trigger20 = (!emittedDynamicsAt20 && count >= 20)
        let trigger80 = (!emittedDynamicsAt80 && count >= 80)
        guard trigger20 || trigger80 else { return }
        if trigger20 { emittedDynamicsAt20 = true }
        if trigger80 {
            emittedDynamicsAt80 = true
            loudnessFinalizedForTrack = true
        }

        guard !isTestingEnv,
              let measuredLufsDb = liveIntegratedLufs,
              measuredLufsDb > -48.0,
              !currentTrackKey.isEmpty,
              currentTrackKey != ":",
              ExternalAmpTCPController.shared.isSoundCheckEnabled else {
            return
        }

        let isRefined = trigger80
        let peakSnap = liveTruePeakDbtp ?? loudnessMaxPeakDb
        let measuredPLRDb = max(3.5, min(24.0, peakSnap - measuredLufsDb))
        let computedGainDb = max(-12.0, min(0.0, -16.5 - measuredLufsDb))
        let tId = currentTrackId
        let tKey = currentTrackKey

        persistenceQueue.async {
            let hasFinalizedMeta = AppleSoundCheckService.shared.hasFinalizedCachedGain(trackId: tId, trackKey: tKey)
            let cachedMetaGain = ExternalAmpTCPController.shared.currentTrackGainDb
            let isDigitalSoundCheckActive: Bool
            if hasFinalizedMeta,
               let metaGain = cachedMetaGain,
               metaGain <= -5.5,
               PlaybackStateStore.shared.isVolumeLockedTo100,
               !AudioDuckingController.shared.isDucked,
               measuredLufsDb <= -14.8,
               peakSnap <= metaGain + 2.5 {
                isDigitalSoundCheckActive = true
            } else {
                isDigitalSoundCheckActive = false
            }

            let effectivePLRDb: Double
            if hasFinalizedMeta, !isDigitalSoundCheckActive, let metaGain = cachedMetaGain, metaGain < -3.0 {
                effectivePLRDb = min(measuredPLRDb, max(4.5, 16.5 + metaGain))
            } else {
                effectivePLRDb = measuredPLRDb
            }

            ExternalAmpTCPController.shared.updateLiveTrackDynamics(
                trackKey: tKey,
                crestFactorDb: effectivePLRDb,
                digitalSoundCheckAlreadyActive: isDigitalSoundCheckActive
            )

            if !hasFinalizedMeta {
                AppleSoundCheckService.shared.recordLiveDSPLoudness(
                    trackId: tId,
                    trackKey: tKey,
                    gainDb: computedGainDb,
                    isRefined: isRefined
                )
            }
        }
    }

    internal static func statusForTtDr(_ score: Int?) -> String {
        guard let score else { return "analyzing" }
        if score >= 12 { return "dynamic" }
        if score >= 8 { return "balanced" }
        return "compressed"
    }
}
