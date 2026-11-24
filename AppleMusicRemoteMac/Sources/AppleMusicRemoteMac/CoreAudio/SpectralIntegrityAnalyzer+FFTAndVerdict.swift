//
//  SpectralIntegrityAnalyzer+FFTAndVerdict.swift
//  AppleMusicRemoteMac
//
//  2048-pt Hann Forward Real FFT (vDSP), 32-Band RTA Spectrum,
//  Brickwall Cutoff Estimator & Audiophile Lossless/Hi-Res Verdict Engine
//

import Foundation
import Accelerate

extension SpectralIntegrityAnalyzer {

    internal func ingestMonoFrames(_ mono: [Float], nonSilentCount: Int, lsb24Count: Int) {
        lock.lock()
        defer { lock.unlock() }
        ingestMonoFramesLocked(mono, nonSilentCount: nonSilentCount, lsb24Count: lsb24Count)
    }

    internal func ingestMonoFramesLocked(_ mono: [Float], nonSilentCount: Int, lsb24Count: Int) {
        let visualizationOnly = (activeCachedValidation != nil)
        if !visualizationOnly {
            totalNonSilentSamples += nonSilentCount
            nonZeroLSB24Samples += lsb24Count
        }
        sampleRingBuffer.append(contentsOf: mono)

        if visualizationOnly {
            // Fast 50%-overlapped visualization path: cap backlog to latest 2 hops for crisp RTA bars
            let maxKeep = Self.fftSize + Self.fftHopSize
            if sampleRingBuffer.count > maxKeep {
                sampleRingBuffer.removeFirst(sampleRingBuffer.count - maxKeep)
            }
            var offset = 0
            while sampleRingBuffer.count - offset >= Self.fftSize {
                for i in 0..<Self.fftSize {
                    fftFrameScratch[i] = sampleRingBuffer[offset + i]
                }
                performFFTFrameLocked(fftFrameScratch, visualizationOnly: true, countTowardVerdict: false)
                offset += Self.fftHopSize
            }
            if offset > 0 {
                sampleRingBuffer.removeFirst(offset)
            }
        } else {
            // Cap ring buffer so we don't fall behind real-time
            if sampleRingBuffer.count > Self.fftSize * 4 {
                sampleRingBuffer.removeFirst(sampleRingBuffer.count - Self.fftSize * 2)
            }

            let stepSize = isSingleBufferTestMode ? Self.fftSize : Self.fftHopSize
            var offset = 0
            while sampleRingBuffer.count - offset >= Self.fftSize {
                for i in 0..<Self.fftSize {
                    fftFrameScratch[i] = sampleRingBuffer[offset + i]
                }
                let countVerdict: Bool
                if isSingleBufferTestMode {
                    countVerdict = true
                } else {
                    countVerdict = !fftHopParity
                    fftHopParity.toggle()
                }
                performFFTFrameLocked(fftFrameScratch, visualizationOnly: false, countTowardVerdict: countVerdict)
                offset += stepSize
            }
            if offset > 0 {
                sampleRingBuffer.removeFirst(offset)
            }
        }

        recomputeResultLocked()
    }

    internal func performFFTFrameLocked(_ frame: [Float], visualizationOnly: Bool = false, countTowardVerdict: Bool = true) {
        guard let setup = fftSetup else { return }

        // 1. Compute RMS & Peak for Crest Factor and silence gating
        var rms: Float = 0
        vDSP_rmsqv(frame, 1, &rms, vDSP_Length(Self.fftSize))
        var peak: Float = 0
        vDSP_maxmgv(frame, 1, &peak, vDSP_Length(Self.fftSize))

        let rmsDb = 20.0 * log10(Double(max(rms, 1e-6)))
        let peakDb = 20.0 * log10(Double(max(peak, 1e-6)))

        if countTowardVerdict {
            analyzedFFTFrames += 1
        }

        if rmsDb > -54.0 && countTowardVerdict {
            let crest = max(3.0, min(24.0, peakDb - rmsDb))
            dynamicRangeCrestDb = dynamicRangeCrestDb * 0.88 + crest * 0.12
        }

        // 2. Apply Hann Window into pre-allocated scratch buffer (zero heap allocations)
        vDSP_vmul(frame, 1, hannWindow, 1, &fftWindowedScratch, 1, vDSP_Length(Self.fftSize))

        // 3. Pack into Split Complex and run Forward Real FFT
        fftRealScratch.withUnsafeMutableBufferPointer { realBuf in
            fftImagScratch.withUnsafeMutableBufferPointer { imagBuf in
                guard let rBase = realBuf.baseAddress, let iBase = imagBuf.baseAddress else { return }
                var splitComplex = DSPSplitComplex(realp: rBase, imagp: iBase)
                fftWindowedScratch.withUnsafeBytes { rawBytes in
                    guard let complexPtr = rawBytes.baseAddress?.assumingMemoryBound(to: DSPComplex.self) else { return }
                    vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(Self.halfFFTSize))
                }
                vDSP_fft_zrip(setup, &splitComplex, 1, Self.log2N, FFTDirection(kFFTDirection_Forward))
                splitComplex.imagp[0] = 0 // Nyquist component packed in imagp[0]
                vDSP_zvmags(&splitComplex, 1, &fftMagScratch, 1, vDSP_Length(Self.halfFFTSize))
            }
        }

        // Normalize squared magnitudes by (N/2)^2
        let normFactor = Float(Self.halfFFTSize * Self.halfFFTSize)
        let hasSignalForRta = (rmsDb > -72.0)
        let isMusicalFrame = (rmsDb > -62.0)
        if isMusicalFrame && countTowardVerdict {
            activeMusicalFrames += 1
        }
        if peakDb > loudnessMaxPeakDb {
            loudnessMaxPeakDb = peakDb
        }

        if visualizationOnly {
            for k in 1..<Self.halfFFTSize {
                let normMagSq = max(fftMagScratch[k] / normFactor, 1e-10)
                let db = max(-96.0, min(0.0, 10.0 * log10(normMagSq)))
                if db > liveBinDb[k] {
                    liveBinDb[k] = liveBinDb[k] * 0.20 + db * 0.80
                } else {
                    liveBinDb[k] = liveBinDb[k] * 0.62 + db * 0.38
                }
            }
            updateRtaBandsLocked(isMusicalFrame: hasSignalForRta)
            return
        }

        let nyquist = Double(currentSampleRate) / 2.0
        let binHz = nyquist / Double(Self.halfFFTSize)
        let trebleStartBin = max(1, min(Self.halfFFTSize - 1, Int(floor(8500.0 / binHz))))
        let trebleEndBin = max(trebleStartBin, min(Self.halfFFTSize - 1, Int(ceil(15500.0 / binHz))))
        var frameMaxTrebleDb: Float = -96.0

        for k in 1..<Self.halfFFTSize {
            let normMagSq = max(fftMagScratch[k] / normFactor, 1e-10)
            let db = max(-96.0, min(0.0, 10.0 * log10(normMagSq)))
            // Smooth live spectrum for RTA display (crisp transient attack, responsive musical release)
            if db > liveBinDb[k] {
                liveBinDb[k] = liveBinDb[k] * 0.20 + db * 0.80
            } else {
                liveBinDb[k] = liveBinDb[k] * 0.62 + db * 0.38
            }

            if isMusicalFrame {
                if countTowardVerdict && k >= trebleStartBin && k <= trebleEndBin && db > frameMaxTrebleDb {
                    frameMaxTrebleDb = db
                }
                // Cumulative non-decaying peak hold per track:
                // Captures even brief high-frequency bursts and prevents flickering during quiet passages.
                if db > peakBinDb[k] {
                    peakBinDb[k] = db
                }
            }
        }

        if isMusicalFrame && countTowardVerdict && frameMaxTrebleDb > -66.0 {
            trebleActiveFrames += 1
        }

        updateRtaBandsLocked(isMusicalFrame: hasSignalForRta)
    }

    internal func updateRtaBandsLocked(isMusicalFrame: Bool) {
        let nyquist = Double(currentSampleRate) / 2.0
        let binHz = nyquist / Double(Self.halfFFTSize)
        let isHiResRate = currentSampleRate >= 88200

        for bandIdx in 0..<Self.rtaBandCount {
            let fLow: Double
            let fHigh: Double

            if isHiResRate {
                // Bars 0..19 map 20 Hz -> 22,050 Hz (Audible CD band, logarithmic)
                // Bars 20..31 map 22,050 Hz -> Nyquist (Ultrasonic Hi-Res band, linear/log)
                if bandIdx < 20 {
                    let t0 = Double(bandIdx) / 20.0
                    let t1 = Double(bandIdx + 1) / 20.0
                    fLow = 20.0 * pow(22050.0 / 20.0, t0)
                    fHigh = 20.0 * pow(22050.0 / 20.0, t1)
                } else {
                    let u0 = Double(bandIdx - 20) / 12.0
                    let u1 = Double(bandIdx - 19) / 12.0
                    fLow = 22050.0 + (nyquist - 22050.0) * u0
                    fHigh = 22050.0 + (nyquist - 22050.0) * u1
                }
            } else {
                // Standard rate (44.1 / 48 kHz): Bars 0..23 map 20 Hz -> 18,000 Hz, Bars 24..31 map 18,000 Hz -> Nyquist
                if bandIdx < 24 {
                    let t0 = Double(bandIdx) / 24.0
                    let t1 = Double(bandIdx + 1) / 24.0
                    fLow = 20.0 * pow(18000.0 / 20.0, t0)
                    fHigh = 20.0 * pow(18000.0 / 20.0, t1)
                } else {
                    let u0 = Double(bandIdx - 24) / 8.0
                    let u1 = Double(bandIdx - 23) / 8.0
                    fLow = 18000.0 + (nyquist - 18000.0) * u0
                    fHigh = 18000.0 + (nyquist - 18000.0) * u1
                }
            }

            let startBin = max(1, min(Self.halfFFTSize - 1, Int(floor(fLow / binHz))))
            let endBin = max(startBin, min(Self.halfFFTSize - 1, Int(ceil(fHigh / binHz))))

            var maxDb: Float = -96.0
            for b in startBin...endBin {
                let liveVal = liveBinDb[b]
                if liveVal > maxDb {
                    maxDb = liveVal
                }
            }

            // Normalize -88 dBFS ... -6 dBFS into 0.0 ... 1.0
            let normalized = isMusicalFrame
                ? min(1.0, max(0.02, Double(maxDb + 88.0) / 82.0))
                : max(0.03, smoothedRtaBands[bandIdx] * 0.78)

            let prev = smoothedRtaBands[bandIdx]
            if normalized > prev {
                smoothedRtaBands[bandIdx] = prev * 0.22 + normalized * 0.78
            } else {
                smoothedRtaBands[bandIdx] = prev * 0.58 + normalized * 0.42
            }
        }
    }

    @inline(__always)
    internal func quantizedRtaBandsLocked() -> [Double] {
        return smoothedRtaBands.map { (($0 * 1000.0).rounded()) / 1000.0 }
    }

    internal func averagePeakDbInBand(lowHz: Double, highHz: Double) -> Double {
        let nyquist = Double(currentSampleRate) / 2.0
        guard lowHz < nyquist else { return -96.0 }
        let clampedHigh = min(highHz, nyquist - 100.0)
        guard clampedHigh > lowHz else { return -96.0 }

        let binHz = nyquist / Double(Self.halfFFTSize)
        let b0 = max(1, min(Self.halfFFTSize - 1, Int(floor(lowHz / binHz))))
        let b1 = max(b0, min(Self.halfFFTSize - 1, Int(ceil(clampedHigh / binHz))))

        var vals: [Float] = []
        vals.reserveCapacity(b1 - b0 + 1)
        for b in b0...b1 {
            vals.append(peakBinDb[b])
        }
        vals.sort(by: >)
        // Take mean of top 2 bins in the band so harmonic peaks represent the band energy accurately
        let topCount = max(1, min(vals.count, 2))
        var sum: Double = 0
        for i in 0..<topCount {
            sum += Double(vals[i])
        }
        return sum / Double(topCount)
    }

    internal func estimateCutoffFrequencyLocked(midEnergyDb: Double) -> Double {
        let nyquist = Double(currentSampleRate) / 2.0
        let thresholdDb = max(-84.0, min(-70.0, midEnergyDb - 46.0))
        let stepHz = 400.0
        var freq = nyquist - 200.0

        while freq >= 12000.0 {
            let subBandDb = averagePeakDbInBand(lowHz: freq - stepHz, highHz: freq + stepHz)
            if subBandDb >= thresholdDb {
                return min(nyquist, freq + stepHz * 0.5)
            }
            freq -= stepHz
        }
        return max(12000.0, freq)
    }

    internal func recomputeResultLocked() {
        let nyquist = Double(currentSampleRate) / 2.0

        if !isEnabledInternal {
            latestResult = SpectralAnalysisInfo(
                isEnabled: false,
                isCached: false,
                verdict: "disabled",
                verdictTitle: "Спектральный анализ отключен",
                verdictDescription: "Аудиофильский верификатор спектра отключен в настройках приложения.",
                isAuthentic: true,
                sampleRate: currentSampleRate,
                claimedBitDepth: claimedBitDepth,
                effectiveBitDepth: claimedBitDepth,
                isZeroPadded: false,
                cutoffFrequencyHz: nyquist,
                nyquistFrequencyHz: nyquist,
                ultrasonicEnergyDb: -96.0,
                highBandEnergyDb: -45.0,
                dynamicRangeCrestDb: dynamicRangeCrestDb,
                analyzedFramesCount: 0,
                rtaBands: Array(repeating: 0.0, count: Self.rtaBandCount)
            )
            return
        }

        // Fast path: if the current track (local or cloud) already passed spectral validation in cache,
        // skip all heavy sub-band sorting, brickwall cutoff scanning, and bit-depth checks,
        // keeping live RTA spectrum bands and live EBU R128 / TT DR / Stereo Phase Correlation telemetry.
        if let cached = activeCachedValidation, cached.isAuthentic {
            let liveBands = isPlayingState
                ? quantizedRtaBandsLocked()
                : makePreviewBandsForIdleState(nyquist: nyquist)
            let effDr = liveTtDrScore ?? cached.ttDrScore
            let effIntLufs = liveIntegratedLufs ?? cached.integratedLufs
            let effLra = liveLoudnessRangeLu ?? cached.loudnessRangeLu
            let effTp: Double?
            if let liveTp = liveTruePeakDbtp, let cachedTp = cached.truePeakDbtp {
                effTp = max(liveTp, cachedTp)
            } else {
                effTp = liveTruePeakDbtp ?? cached.truePeakDbtp
            }
            latestResult = SpectralAnalysisInfo(
                isEnabled: true,
                isCached: true,
                verdict: cached.verdict,
                verdictTitle: cached.verdictTitle,
                verdictDescription: cached.verdictDescription,
                isAuthentic: true,
                sampleRate: currentSampleRate,
                claimedBitDepth: claimedBitDepth,
                effectiveBitDepth: cached.effectiveBitDepth,
                isZeroPadded: false,
                cutoffFrequencyHz: cached.cutoffFrequencyHz,
                nyquistFrequencyHz: nyquist,
                ultrasonicEnergyDb: cached.ultrasonicEnergyDb,
                highBandEnergyDb: cached.highBandEnergyDb,
                dynamicRangeCrestDb: activeMusicalFrames > 0 ? dynamicRangeCrestDb : cached.dynamicRangeCrestDb,
                analyzedFramesCount: max(cached.analyzedFramesCount, activeMusicalFrames),
                rtaBands: liveBands,
                ttDrScore: effDr,
                ttDrStatus: Self.statusForTtDr(effDr),
                integratedLufs: effIntLufs,
                shortTermLufs: liveShortTermLufs ?? effIntLufs,
                momentaryLufs: liveMomentaryLufs,
                loudnessRangeLu: effLra,
                truePeakDbtp: effTp,
                ispClipCount: liveIspClipCount,
                phaseCorrelation: livePhaseCorrelation,
                stereoWidthPercent: liveStereoWidthPercent,
                channelBalanceDb: liveChannelBalanceDb
            )
            return
        }

        // Effective bit depth from LSB 17..24 activity
        let hasLSB24Activity: Bool
        if totalNonSilentSamples >= 64 {
            let ratio = Double(nonZeroLSB24Samples) / Double(totalNonSilentSamples)
            hasLSB24Activity = (ratio >= 0.015)
        } else {
            hasLSB24Activity = (claimedBitDepth >= 24)
        }

        let effectiveDepth: Int
        if !isClaimedLossless {
            effectiveDepth = 16
        } else if claimedBitDepth >= 24 {
            effectiveDepth = hasLSB24Activity ? 24 : 16
        } else {
            effectiveDepth = 16
        }

        let isZeroPadded = isClaimedLossless && (claimedBitDepth >= 24) && (totalNonSilentSamples >= 128) && (effectiveDepth == 16)

        let midEnergyDb = averagePeakDbInBand(lowHz: 1500.0, highHz: 9500.0)
        let lowPresenceEnergyDb = averagePeakDbInBand(lowHz: 8000.0, highHz: 14500.0)
        let presenceEnergyDb = averagePeakDbInBand(lowHz: 10000.0, highHz: 15500.0)
        let aacHighBandDb = averagePeakDbInBand(lowHz: 16800.0, highHz: 19800.0)
        let cdTopEnergyDb = averagePeakDbInBand(lowHz: 19000.0, highHz: 21800.0)
        let ultrasonicEnergyDb = (currentSampleRate >= 88200)
            ? averagePeakDbInBand(lowHz: 23500.0, highHz: min(nyquist - 500.0, 44000.0))
            : -96.0

        // Require sufficient musical/treble frames in live streaming before locking a verdict
        let minMusicalFrames = isSingleBufferTestMode ? 2 : 6
        let hasEarlyTopExtension = isClaimedLossless
            ? (currentSampleRate >= 88200 ? ultrasonicEnergyDb > -80.0 : cdTopEnergyDb > -78.0)
            : (aacHighBandDb > -78.0)
        let hasTreblePresence = (presenceEnergyDb > -60.0 || lowPresenceEnergyDb > -58.0 || trebleActiveFrames >= 4)
        let needsMoreTrebleEvidence = !isSingleBufferTestMode && isPlayingState && !hasEarlyTopExtension && !hasTreblePresence && (activeMusicalFrames < 16)

        if activeMusicalFrames < minMusicalFrames || needsMoreTrebleEvidence {
            let liveOrIdleBands = isPlayingState
                ? quantizedRtaBandsLocked()
                : makePreviewBandsForIdleState(nyquist: nyquist)
            let khzStr = formatKhz(Double(currentSampleRate))
            let curDrStatus = Self.statusForTtDr(liveTtDrScore)
            if isPlayingState {
                latestResult = SpectralAnalysisInfo(
                    isEnabled: true,
                    isCached: false,
                    verdict: "analyzing",
                    verdictTitle: "Спектральный анализ потока...",
                    verdictDescription: activeMusicalFrames < minMusicalFrames
                        ? "Сбор PCM-фреймов из CoreAudio Process Tap (\(claimedBitDepth)-бит / \(khzStr) кГц) для верификации спектра vDSP FFT."
                        : "Накопление пиковой ВЧ-огибающей трека (ожидание высокочастотных транзиентов выше 16 кГц)...",
                    isAuthentic: true,
                    sampleRate: currentSampleRate,
                    claimedBitDepth: claimedBitDepth,
                    effectiveBitDepth: effectiveDepth,
                    isZeroPadded: false,
                    cutoffFrequencyHz: nyquist,
                    nyquistFrequencyHz: nyquist,
                    ultrasonicEnergyDb: ultrasonicEnergyDb,
                    highBandEnergyDb: cdTopEnergyDb,
                    dynamicRangeCrestDb: dynamicRangeCrestDb,
                    analyzedFramesCount: activeMusicalFrames,
                    rtaBands: liveOrIdleBands,
                    ttDrScore: liveTtDrScore,
                    ttDrStatus: curDrStatus,
                    integratedLufs: liveIntegratedLufs,
                    shortTermLufs: liveShortTermLufs,
                    momentaryLufs: liveMomentaryLufs,
                    loudnessRangeLu: liveLoudnessRangeLu,
                    truePeakDbtp: liveTruePeakDbtp,
                    ispClipCount: liveIspClipCount,
                    phaseCorrelation: livePhaseCorrelation,
                    stereoWidthPercent: liveStereoWidthPercent,
                    channelBalanceDb: liveChannelBalanceDb
                )
            } else if !isClaimedLossless {
                latestResult = SpectralAnalysisInfo(
                    isEnabled: true,
                    isCached: false,
                    verdict: "aac_lossy",
                    verdictTitle: "Сжатый поток AAC 256 kbps",
                    verdictDescription: "Воспроизводится сжатый поток AAC (16-бит / 44.1 кГц). Включите воспроизведение для проверки спектра.",
                    isAuthentic: true,
                    sampleRate: currentSampleRate,
                    claimedBitDepth: 16,
                    effectiveBitDepth: 16,
                    isZeroPadded: false,
                    cutoffFrequencyHz: 18500,
                    nyquistFrequencyHz: nyquist,
                    ultrasonicEnergyDb: -92.0,
                    highBandEnergyDb: -48.0,
                    dynamicRangeCrestDb: dynamicRangeCrestDb,
                    analyzedFramesCount: activeMusicalFrames,
                    rtaBands: liveOrIdleBands,
                    ttDrScore: liveTtDrScore,
                    ttDrStatus: curDrStatus,
                    integratedLufs: liveIntegratedLufs,
                    shortTermLufs: liveShortTermLufs,
                    momentaryLufs: liveMomentaryLufs,
                    loudnessRangeLu: liveLoudnessRangeLu,
                    truePeakDbtp: liveTruePeakDbtp,
                    ispClipCount: liveIspClipCount,
                    phaseCorrelation: livePhaseCorrelation,
                    stereoWidthPercent: liveStereoWidthPercent,
                    channelBalanceDb: liveChannelBalanceDb
                )
            } else {
                latestResult = SpectralAnalysisInfo(
                    isEnabled: true,
                    isCached: false,
                    verdict: "analyzing",
                    verdictTitle: "Ожидание воспроизведения...",
                    verdictDescription: "Формат контейнера ALAC \(claimedBitDepth)-бит / \(khzStr) кГц. Включите воспроизведение для живого БПФ-анализа спектра.",
                    isAuthentic: true,
                    sampleRate: currentSampleRate,
                    claimedBitDepth: claimedBitDepth,
                    effectiveBitDepth: claimedBitDepth,
                    isZeroPadded: false,
                    cutoffFrequencyHz: nyquist,
                    nyquistFrequencyHz: nyquist,
                    ultrasonicEnergyDb: currentSampleRate >= 88200 ? -54.0 : -92.0,
                    highBandEnergyDb: -36.0,
                    dynamicRangeCrestDb: dynamicRangeCrestDb,
                    analyzedFramesCount: activeMusicalFrames,
                    rtaBands: liveOrIdleBands,
                    ttDrScore: liveTtDrScore,
                    ttDrStatus: curDrStatus,
                    integratedLufs: liveIntegratedLufs,
                    shortTermLufs: liveShortTermLufs,
                    momentaryLufs: liveMomentaryLufs,
                    loudnessRangeLu: liveLoudnessRangeLu,
                    truePeakDbtp: liveTruePeakDbtp,
                    ispClipCount: liveIspClipCount,
                    phaseCorrelation: livePhaseCorrelation,
                    stereoWidthPercent: liveStereoWidthPercent,
                    channelBalanceDb: liveChannelBalanceDb
                )
            }
            return
        }

        let rawCutoffHz = estimateCutoffFrequencyLocked(midEnergyDb: midEnergyDb)
        let cutoffKhzStr = String(format: "%.1f", rawCutoffHz / 1000.0)

        let verdict: String
        let title: String
        let desc: String
        let authentic: Bool

        if !isClaimedLossless {
            // Check for lossy-to-lossy upscale (e.g. 96/128 kbps MP3/AAC upscaled into 256 kbps AAC stream)
            if lowPresenceEnergyDb > -56.0 && aacHighBandDb < -78.0 && (lowPresenceEnergyDb - aacHighBandDb) > 25.0 && rawCutoffHz < 16800.0 {
                verdict = "lossy_upscaled"
                title = "Lossy-апскейл (~128 → 256 kbps)"
                desc = "Несмотря на битрейт потока 256 kbps, спектр резко обрывается на \(cutoffKhzStr) кГц (вместо 18.5–20 кГц у честного AAC 256). Запись пережата из низкого битрейта (96–128 kbps)."
                authentic = false
            } else {
                verdict = "aac_lossy"
                title = "Честный AAC 256 kbps"
                desc = "Поток AAC 256 kbps соответствует эталонному профилю: верхняя граница спектра простирается до \(cutoffKhzStr) кГц без признаков апскейла из 128 kbps."
                authentic = true
            }
        } else if presenceEnergyDb > -56.0 && cdTopEnergyDb < -78.0 && (presenceEnergyDb - cdTopEnergyDb) > 28.0 && rawCutoffHz < 19000.0 {
            verdict = "lossy_transcode"
            let approxBitrate = rawCutoffHz < 16500.0 ? "~128 kbps" : "~256 kbps"
            title = "Lossy-транскод (\(approxBitrate) • срез \(cutoffKhzStr) кГц)"
            desc = "Обнаружен резкий кирпичный срез ВЧ на \(cutoffKhzStr) кГц при контейнере ALAC. Вероятно, исходник был сжат в MP3/AAC (\(approxBitrate))."
            authentic = false
        } else if currentSampleRate >= 88200 && cdTopEnergyDb > -66.0 && ultrasonicEnergyDb < -81.0 && (cdTopEnergyDb - ultrasonicEnergyDb) > 22.0 && rawCutoffHz <= 22800.0 {
            verdict = "upsampled"
            title = "Апсемплинг CD (срез 22.05 кГц)"
            desc = "В потоке \(formatKhz(Double(currentSampleRate))) кГц отсутствует ультразвуковая энергия выше 22.05 кГц (\(String(format: "%.0f", ultrasonicEnergyDb)) dBFS). Трек получен апсемплингом из 44.1 кГц."
            authentic = false
        } else if isZeroPadded {
            verdict = "zero_padded"
            title = "Zero-Padding (16-бит → 24-бит)"
            desc = "Спектр чистый (до \(cutoffKhzStr) кГц), но младшие 8 бит (17–24) всех сэмплов равны нулю. Реальная разрядность мастера — 16 бит."
            authentic = false
        } else if currentSampleRate >= 88200 {
            verdict = "verified_hires"
            title = "Verified True Hi-Res"
            desc = "Подлинный студийный Hi-Res мастер: зафиксирована живая ультразвуковая составляющая до \(cutoffKhzStr) кГц (\(String(format: "%.0f", ultrasonicEnergyDb)) dBFS) и честные \(effectiveDepth) бит."
            authentic = true
        } else if currentSampleRate == 48000 && effectiveDepth == 24 {
            verdict = "verified_hires"
            title = "Verified Studio Master 24-бит"
            desc = "Подлинный 24-битный студийный мастер 48 кГц: полный спектр до \(cutoffKhzStr) кГц и активные младшие разряды (LSB 24-bit)."
            authentic = true
        } else {
            verdict = "verified_lossless"
            title = "Verified True Lossless"
            desc = "Честный Lossless-спектр до \(cutoffKhzStr) кГц без признаков психоакустической фильтрации MP3/AAC (\(effectiveDepth)-бит / \(formatKhz(Double(currentSampleRate))) кГц)."
            authentic = true
        }

        // Cache passed spectral validation so we don't re-run spectral verification for this track
        let hasConfirmedPass: Bool
        if !authentic {
            hasConfirmedPass = false
        } else if !isClaimedLossless {
            hasConfirmedPass = (aacHighBandDb > -78.0 && rawCutoffHz >= 16800.0)
        } else if currentSampleRate >= 88200 {
            let bitDepthConfirmed = (claimedBitDepth < 24) || (hasLSB24Activity && totalNonSilentSamples >= 64)
            hasConfirmedPass = (ultrasonicEnergyDb > -81.0 && rawCutoffHz > 22800.0 && !isZeroPadded && bitDepthConfirmed)
        } else {
            let bitDepthConfirmed = (claimedBitDepth < 24) || (hasLSB24Activity && totalNonSilentSamples >= 64)
            hasConfirmedPass = (cdTopEnergyDb > -78.0 && rawCutoffHz >= 19000.0 && !isZeroPadded && bitDepthConfirmed)
        }

        var didCachePass = false
        if hasConfirmedPass && (!currentTrackId.isEmpty || (!currentTrackKey.isEmpty && currentTrackKey != ":")) {
            let cachedEntry = CachedSpectralValidation(
                trackId: currentTrackId,
                trackKey: currentTrackKey,
                isLocal: currentIsLocal,
                verdict: verdict,
                verdictTitle: title,
                verdictDescription: desc,
                isAuthentic: true,
                sampleRate: currentSampleRate,
                claimedBitDepth: claimedBitDepth,
                effectiveBitDepth: effectiveDepth,
                isZeroPadded: false,
                cutoffFrequencyHz: rawCutoffHz,
                nyquistFrequencyHz: nyquist,
                ultrasonicEnergyDb: ultrasonicEnergyDb,
                highBandEnergyDb: cdTopEnergyDb,
                dynamicRangeCrestDb: dynamicRangeCrestDb,
                analyzedFramesCount: activeMusicalFrames,
                ttDrScore: liveTtDrScore,
                integratedLufs: liveIntegratedLufs.map { ($0 * 10.0).rounded() / 10.0 },
                loudnessRangeLu: liveLoudnessRangeLu.map { ($0 * 10.0).rounded() / 10.0 },
                truePeakDbtp: liveTruePeakDbtp.map { ($0 * 10.0).rounded() / 10.0 }
            )
            storePassedValidationLocked(cachedEntry, isLossless: isClaimedLossless)
            activeCachedValidation = cachedEntry
            didCachePass = true
        }

        latestResult = SpectralAnalysisInfo(
            isEnabled: true,
            isCached: didCachePass,
            verdict: verdict,
            verdictTitle: title,
            verdictDescription: desc,
            isAuthentic: authentic,
            sampleRate: currentSampleRate,
            claimedBitDepth: claimedBitDepth,
            effectiveBitDepth: effectiveDepth,
            isZeroPadded: isZeroPadded,
            cutoffFrequencyHz: rawCutoffHz,
            nyquistFrequencyHz: nyquist,
            ultrasonicEnergyDb: ultrasonicEnergyDb,
            highBandEnergyDb: cdTopEnergyDb,
            dynamicRangeCrestDb: dynamicRangeCrestDb,
            analyzedFramesCount: activeMusicalFrames,
            rtaBands: quantizedRtaBandsLocked(),
            ttDrScore: liveTtDrScore,
            ttDrStatus: Self.statusForTtDr(liveTtDrScore),
            integratedLufs: liveIntegratedLufs,
            shortTermLufs: liveShortTermLufs,
            momentaryLufs: liveMomentaryLufs,
            loudnessRangeLu: liveLoudnessRangeLu,
            truePeakDbtp: liveTruePeakDbtp,
            ispClipCount: liveIspClipCount,
            phaseCorrelation: livePhaseCorrelation,
            stereoWidthPercent: liveStereoWidthPercent,
            channelBalanceDb: liveChannelBalanceDb
        )
    }

    internal func makePreviewBandsForIdleState(nyquist: Double) -> [Double] {
        var anyAboveFloor = false
        for i in 0..<smoothedRtaBands.count {
            let decayed = max(0.03, smoothedRtaBands[i] * 0.72)
            smoothedRtaBands[i] = decayed
            if decayed > 0.045 {
                anyAboveFloor = true
            }
        }
        if anyAboveFloor {
            return smoothedRtaBands
        }
        return Array(repeating: 0.03, count: Self.rtaBandCount)
    }

    internal func formatKhz(_ hz: Double) -> String {
        let khz = hz / 1000.0
        return (khz.truncatingRemainder(dividingBy: 1) == 0)
            ? String(format: "%.0f", khz)
            : String(format: "%.1f", khz)
    }
}
