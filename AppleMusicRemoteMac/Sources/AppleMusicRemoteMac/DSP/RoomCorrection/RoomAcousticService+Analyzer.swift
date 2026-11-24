//
//  RoomAcousticService+Analyzer.swift
//  AppleMusicRemoteMac
//
//  1/3-Octave vDSP Spectral Analyzer & Automatic Minimum-Phase RBJ Room EQ Synthesizer
//

import Accelerate
import AudioToolbox
import CoreAudio
import Foundation

extension RoomAcousticService {

    // MARK: - Room Acoustic Analysis & Auto-PEQ Synthesis

    /// Saves a newly analyzed profile, makes it active, enables Room EQ if requested, and schedules Cloud Sync.
    @discardableResult
    public func saveMeasuredProfile(_ profile: RoomAcousticProfile, autoEnable: Bool = true) -> RoomAcousticProfile {
        lock.lock()
        let prevActive = activeProfileIDInternal
        let prevEnabled = correctionEnabledInternal
        deletedProfileTimestamps.removeValue(forKey: profile.id)
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.insert(profile, at: 0)
        }
        activeProfileIDInternal = profile.id
        if autoEnable {
            correctionEnabledInternal = true
        }
        if activeProfileIDInternal != prevActive || correctionEnabledInternal != prevEnabled {
            roomStateUpdatedAtInternal = Date().timeIntervalSince1970
        }
        syncFastFlagsFromStateLocked()
        saveToDefaultsLocked()
        lock.unlock()

        syncRealtimeProcessors()
        refreshLocalPassthroughEQPipeline()

        if !isIsolatedInstance {
            CloudSettingsSyncService.shared.scheduleDebouncedSync(reason: "room_measurement_saved")
        }
        return profile
    }

    /// Creates a `RoomAcousticProfile` from 31 client-measured 1/3-octave dB values (WebAudio live mic capture).
    public func createProfileFromThirdOctaveBands(
        rawBandsDB: [Double],
        profileName: String?,
        deviceName: String,
        applyMEMSMicCompensation: Bool = true,
        autoSaveAndEnable: Bool = true
    ) -> RoomAcousticProfile? {
        guard rawBandsDB.count == Self.isoThirdOctaveBandsHz.count else { return nil }
        let sanitized = rawBandsDB.map { $0.isFinite ? $0 : -60.0 }
        let profile = synthesizeRoomProfile(
            rawBandLevelsDB: sanitized,
            profileName: profileName,
            deviceName: deviceName,
            applyMEMSMicCompensation: applyMEMSMicCompensation
        )
        if autoSaveAndEnable {
            saveMeasuredProfile(profile, autoEnable: true)
        }
        return profile
    }

    /// Decodes an uploaded audio file (M4A / WAV / CAF / AAC / AIFF from iPhone/iPad `<input type="file" accept="audio/*" capture>`)
    /// via `ExtAudioFile` and runs Welch overlapped 4096-pt Hann-windowed `vDSP` FFT to synthesize a `RoomAcousticProfile`.
    public func analyzeUploadedAudioData(
        _ audioData: Data,
        fileExtensionHint: String = "m4a",
        profileName: String?,
        deviceName: String,
        autoSaveAndEnable: Bool = true
    ) throws -> RoomAcousticProfile {
        guard audioData.count >= 1024 else {
            throw NSError(domain: "RoomAcousticService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Аудиозапись слишком короткая"])
        }
        let safeExt = fileExtensionHint
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        let ext = safeExt.isEmpty ? "m4a" : safeExt
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("amr_room_meas_\(UUID().uuidString).\(ext)")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        try audioData.write(to: tempURL, options: .atomic)

        var extFile: ExtAudioFileRef?
        let openStatus = ExtAudioFileOpenURL(tempURL as CFURL, &extFile)
        guard openStatus == noErr, let fileRef = extFile else {
            throw NSError(
                domain: "RoomAcousticService",
                code: Int(openStatus),
                userInfo: [NSLocalizedDescriptionKey: "Не удалось декодировать аудиофайл микрофона (код \(openStatus)). Используйте запись Voice Memos / Микрофон iOS (M4A/WAV)."]
            )
        }
        defer {
            ExtAudioFileDispose(fileRef)
        }

        let targetSampleRate = 48_000.0
        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: targetSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        let fmtStatus = ExtAudioFileSetProperty(
            fileRef,
            kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            &clientFormat
        )
        guard fmtStatus == noErr else {
            throw NSError(domain: "RoomAcousticService", code: Int(fmtStatus), userInfo: [NSLocalizedDescriptionKey: "Неподдерживаемый аудиоформат записи"])
        }

        // Read up to 15 seconds at 48 kHz (720,000 samples max)
        let maxSamples = 720_000
        var samples: [Float] = []
        samples.reserveCapacity(240_000)
        let chunkFrames: UInt32 = 16_384
        var chunkBuf = [Float](repeating: 0.0, count: Int(chunkFrames))

        while samples.count < maxSamples {
            var numFrames = chunkFrames
            let readStatus: OSStatus = chunkBuf.withUnsafeMutableBytes { rawPtr in
                let audioBuffer = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(rawPtr.count),
                    mData: rawPtr.baseAddress
                )
                var abl = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
                return ExtAudioFileRead(fileRef, &numFrames, &abl)
            }
            if readStatus != noErr || numFrames == 0 {
                break
            }
            samples.append(contentsOf: chunkBuf.prefix(Int(numFrames)))
        }

        guard samples.count >= 24_000 else {
            throw NSError(domain: "RoomAcousticService", code: 422, userInfo: [NSLocalizedDescriptionKey: "Запись должна длиться не менее 1–2 секунд во время звучания розового шума"])
        }

        return try analyzePCMMonoSamples(
            samples,
            sampleRate: targetSampleRate,
            profileName: profileName,
            deviceName: deviceName,
            applyMEMSMicCompensation: true,
            autoSaveAndEnable: autoSaveAndEnable
        )
    }

    /// Core Welch 4096-point Hann-windowed `vDSP` FFT analyzer over mono PCM samples.
    public func analyzePCMMonoSamples(
        _ samples: [Float],
        sampleRate: Double,
        profileName: String?,
        deviceName: String,
        applyMEMSMicCompensation: Bool = false,
        autoSaveAndEnable: Bool = false
    ) throws -> RoomAcousticProfile {
        let fftN = 4096
        let halfN = fftN / 2
        let log2N: vDSP_Length = 12
        guard samples.count >= fftN else {
            throw NSError(domain: "RoomAcousticService", code: 422, userInfo: [NSLocalizedDescriptionKey: "Недостаточно аудиосэмплов для спектрального анализа"])
        }

        // Trim leading/trailing quiet sections (keep windows within 18 dB of RMS peak)
        let hop = fftN / 2
        var windowRMS: [(offset: Int, rms: Float)] = []
        var offset = 0
        while offset + fftN <= samples.count {
            var rms: Float = 0.0
            samples.withUnsafeBufferPointer { ptr in
                vDSP_rmsqv(ptr.baseAddress! + offset, 1, &rms, vDSP_Length(fftN))
            }
            windowRMS.append((offset, rms))
            offset += hop
        }
        let maxRMS = windowRMS.map(\.rms).max() ?? 0.0
        guard maxRMS > 1.0e-5 else {
            throw NSError(domain: "RoomAcousticService", code: 422, userInfo: [NSLocalizedDescriptionKey: "Записана тишина — убедитесь, что доступ к микрофону разрешён и громкость системы достаточна"])
        }
        let activeThreshold = maxRMS * 0.125 // -18 dB relative to peak window
        let activeOffsets = windowRMS.filter { $0.rms >= activeThreshold }.map(\.offset)
        let chosenOffsets = activeOffsets.isEmpty ? windowRMS.map(\.offset) : activeOffsets

        guard let fftSetup = vDSP_create_fftsetup(log2N, FFTRadix(kFFTRadix2)) else {
            throw NSError(domain: "RoomAcousticService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Не удалось инициализировать vDSP FFT"])
        }
        defer {
            vDSP_destroy_fftsetup(fftSetup)
        }

        var hann = [Float](repeating: 0.0, count: fftN)
        vDSP_hann_window(&hann, vDSP_Length(fftN), Int32(vDSP_HANN_NORM))

        var windowed = [Float](repeating: 0.0, count: fftN)
        var realPart = [Float](repeating: 0.0, count: halfN)
        var imagPart = [Float](repeating: 0.0, count: halfN)
        var magSq = [Float](repeating: 0.0, count: halfN)
        var accumPower = [Double](repeating: 0.0, count: halfN)

        for winStart in chosenOffsets {
            samples.withUnsafeBufferPointer { sPtr in
                vDSP_vmul(sPtr.baseAddress! + winStart, 1, hann, 1, &windowed, 1, vDSP_Length(fftN))
            }
            realPart.withUnsafeMutableBufferPointer { rBuf in
                imagPart.withUnsafeMutableBufferPointer { iBuf in
                    var split = DSPSplitComplex(realp: rBuf.baseAddress!, imagp: iBuf.baseAddress!)
                    windowed.withUnsafeBytes { rawBytes in
                        let cPtr = rawBytes.bindMemory(to: DSPComplex.self)
                        vDSP_ctoz(cPtr.baseAddress!, 2, &split, 1, vDSP_Length(halfN))
                    }
                    vDSP_fft_zrip(fftSetup, &split, 1, log2N, FFTDirection(FFT_FORWARD))
                    vDSP_zvmags(&split, 1, &magSq, 1, vDSP_Length(halfN))
                }
            }
            magSq[0] = 0.0
            for k in 1..<halfN {
                accumPower[k] += Double(magSq[k])
            }
        }

        let invWinCount = 1.0 / Double(max(1, chosenOffsets.count))
        for k in 1..<halfN {
            accumPower[k] *= invWinCount
        }

        // Integrate linear FFT power across each ISO 1/3-octave band [fc / 2^(1/6), fc * 2^(1/6)].
        // Because calibrated Pink Noise has -3 dB/octave power spectral density (1/f), its integrated power per
        // constant-percentage (1/3-octave) band is flat (0 dB slope)!
        let binHz = sampleRate / Double(fftN)
        let sixthOct = pow(2.0, 1.0 / 6.0)
        var bandLevelsDB = [Double](repeating: -60.0, count: Self.isoThirdOctaveBandsHz.count)

        for (bIdx, fc) in Self.isoThirdOctaveBandsHz.enumerated() {
            let fLow = fc / sixthOct
            let fHigh = fc * sixthOct
            let kLow = max(1, Int(floor(fLow / binHz)))
            let kHigh = min(halfN - 1, Int(ceil(fHigh / binHz)))
            if kLow <= kHigh {
                var sumPower = 0.0
                var weightSum = 0.0
                for k in kLow...kHigh {
                    let fk = Double(k) * binHz
                    // Fractional bin overlap weighting for narrow low-frequency 1/3-octave bands (20..63 Hz)
                    let binLo = fk - 0.5 * binHz
                    let binHi = fk + 0.5 * binHz
                    let overlap = max(0.0, min(fHigh, binHi) - max(fLow, binLo)) / binHz
                    let w = max(0.15, overlap)
                    sumPower += accumPower[k] * w
                    weightSum += w
                }
                // Multiply average bin power by bandwidth in bins so pink noise integrates to flat 0 dB across octaves
                let expectedBins = max(0.5, (fHigh - fLow) / binHz)
                let bandPower = (sumPower / max(1.0e-9, weightSum)) * expectedBins
                bandLevelsDB[bIdx] = 10.0 * log10(max(1.0e-18, bandPower))
            }
        }

        let profile = synthesizeRoomProfile(
            rawBandLevelsDB: bandLevelsDB,
            profileName: profileName,
            deviceName: deviceName,
            applyMEMSMicCompensation: applyMEMSMicCompensation
        )
        if autoSaveAndEnable {
            saveMeasuredProfile(profile, autoEnable: true)
        }
        return profile
    }

    // MARK: - Internal Curve Normalization & Auto-PEQ Fitting

    internal func synthesizeRoomProfile(
        rawBandLevelsDB: [Double],
        profileName: String?,
        deviceName: String,
        applyMEMSMicCompensation: Bool
    ) -> RoomAcousticProfile {
        let bands = Self.isoThirdOctaveBandsHz
        var compensated = rawBandLevelsDB

        // Typical iPhone / iPad bottom omnidirectional MEMS microphone calibration curve:
        // flat +/-1 dB from 60 Hz to 8 kHz, gentle 1st-order high-pass below 45 Hz, slight acoustic helmholtz rise at 10-14 kHz.
        if applyMEMSMicCompensation {
            for (i, f) in bands.enumerated() {
                if f < 45.0 {
                    // Compensate iOS voice/MEMS sub-45 Hz roll-off gently
                    let octavesBelow = log2(45.0 / max(18.0, f))
                    compensated[i] += min(4.2, octavesBelow * 2.8)
                } else if f >= 9_000.0 && f <= 16_000.0 {
                    compensated[i] -= 1.0
                }
            }
        }

        // Light 3-point psychoacoustic smoothing [0.2, 0.6, 0.2] to avoid chasing narrow 1-bin comb notches
        var smoothed = compensated
        if compensated.count >= 3 {
            for i in 1..<(compensated.count - 1) {
                smoothed[i] = 0.20 * compensated[i - 1] + 0.60 * compensated[i] + 0.20 * compensated[i + 1]
            }
        }

        // Normalize midrange reference (250 Hz .. 2000 Hz, indices 11..20) to 0.0 dB median
        let midIndices = bands.indices.filter { bands[$0] >= 250.0 && bands[$0] <= 2_000.0 }
        let midValues = midIndices.map { smoothed[$0] }.sorted()
        let refLevel: Double = midValues.isEmpty ? 0.0 : midValues[midValues.count / 2]
        let measuredNormalized = smoothed.map { max(-24.0, min(24.0, $0 - refLevel)) }

        // Smooth Harman-inspired in-room target curve:
        // gentle +2.2 dB warmth shelf below 90 Hz, neutral 0 dB midrange, natural -0.5 dB/oct HF in-room tilt above 2.5 kHz
        let targetCurve: [Double] = bands.map { f in
            if f <= 63.0 {
                return 2.2
            } else if f < 160.0 {
                let t = log2(f / 63.0) / log2(160.0 / 63.0)
                return 2.2 * (1.0 - t)
            } else if f <= 2_000.0 {
                return 0.0
            } else {
                let octAbove = log2(f / 2_000.0)
                return max(-3.0, -0.85 * octAbove)
            }
        }

        // Iterative greedy minimum-phase RBJ Peaking EQ fitter (up to 8 bands across 28 Hz .. 12.5 kHz)
        let designSampleRate = 48_000.0
        var residual = zip(measuredNormalized, targetCurve).map { $0 - $1 } // >0 means room peak (needs cut), <0 means dip (needs gentle boost)
        var fittedBands: [RoomEQBand] = []
        var usedIndices = Set<Int>()

        for _ in 0..<RoomEQProcessor.maxStages {
            // Search candidate band in [28 Hz .. 12500 Hz] with largest weighted error
            var bestIdx: Int?
            var bestScore: Double = 0.0
            for idx in bands.indices {
                let f = bands[idx]
                guard f >= 25.0 && f <= 12_500.0 else { continue }
                if usedIndices.contains(idx) { continue }
                let err = residual[idx]
                // Prioritize cutting room-mode peaks (weight 1.35x in bass < 300 Hz) over boosting acoustic cancellations!
                let absErr = abs(err)
                guard absErr >= 1.4 else { continue }
                var weight = (err > 0) ? 1.25 : 0.72
                if f <= 300.0 && err > 0 {
                    weight *= 1.25
                }
                let score = absErr * weight
                if score > bestScore {
                    bestScore = score
                    bestIdx = idx
                }
            }

            guard let peakIdx = bestIdx else { break }
            usedIndices.insert(peakIdx)

            let err = residual[peakIdx]
            let fc = bands[peakIdx]

            // Asymmetric safety clamping: cut room resonances up to -9.0 dB; cap boosts at +3.5 dB to protect amp/woofer headroom in acoustic nulls!
            let targetGain: Double
            if err > 0 {
                targetGain = -min(9.0, err * 0.85)
            } else {
                targetGain = min(3.5, (-err) * 0.58)
            }
            guard abs(targetGain) >= 0.8 else { continue }

            // Estimate Q from 1/3-octave neighbor width
            let leftErr = peakIdx > 0 ? residual[peakIdx - 1] : err * 0.5
            let rightErr = (peakIdx + 1 < residual.count) ? residual[peakIdx + 1] : err * 0.5
            let sameSignNeighbors = ((leftErr * err > 0 && abs(leftErr) > abs(err) * 0.55) ? 1 : 0)
                + ((rightErr * err > 0 && abs(rightErr) > abs(err) * 0.55) ? 1 : 0)

            let estimatedQ: Double
            if err > 0 {
                // Room mode cut: sharper Q for narrow standing waves, broader Q for wide humps
                switch sameSignNeighbors {
                case 0: estimatedQ = (fc < 250.0) ? 3.6 : 2.8
                case 1: estimatedQ = 2.0
                default: estimatedQ = 1.25
                }
            } else {
                // Dip fill: always gentle wide Q so it sounds natural and phase-coherent
                estimatedQ = (sameSignNeighbors >= 1) ? 1.1 : 1.6
            }

            let newBand = RoomEQBand(frequencyHz: fc, gainDB: targetGain, q: estimatedQ, filterType: "peaking")
            let biquad = RoomBiquadCoefficients.makeRBJ(band: newBand, sampleRate: designSampleRate)
            fittedBands.append(newBand)

            // Update residual across all 31 bands with exact RBJ magnitude response
            for j in bands.indices {
                residual[j] += biquad.magnitudeDB(atFrequencyHz: bands[j], sampleRate: designSampleRate)
            }
        }

        fittedBands.sort { $0.frequencyHz < $1.frequencyHz }

        // Compute exact corrected response and required negative preamp headroom so total EQ curve never exceeds 0 dBFS
        var eqResponse = [Double](repeating: 0.0, count: bands.count)
        for band in fittedBands {
            let bq = RoomBiquadCoefficients.makeRBJ(band: band, sampleRate: designSampleRate)
            for j in bands.indices {
                eqResponse[j] += bq.magnitudeDB(atFrequencyHz: bands[j], sampleRate: designSampleRate)
            }
        }
        let corrected = zip(measuredNormalized, eqResponse).map { $0 + $1 }
        let maxBoost = max(0.0, eqResponse.max() ?? 0.0)
        let preampDB = maxBoost > 0.05 ? -(maxBoost + 0.5) : 0.0
        let maxDev = zip(measuredNormalized, targetCurve).map { abs($0 - $1) }.max() ?? 0.0

        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM HH:mm"
        let fallbackName = "АЧХ комнаты (\(formatter.string(from: Date())))"
        let trimmedName = profileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let finalName = trimmedName.isEmpty ? fallbackName : String(trimmedName.prefix(64))
        let now = Date().timeIntervalSince1970

        return RoomAcousticProfile(
            name: finalName,
            measuredOnDevice: deviceName.isEmpty ? "iOS / PWA Mic" : deviceName,
            createdAt: now,
            updatedAt: now,
            bandsHz: bands,
            measuredResponseDB: measuredNormalized,
            targetCurveDB: targetCurve,
            correctedResponseDB: corrected,
            maxPeakDeviationDB: maxDev,
            eqBands: fittedBands,
            preampGainDB: preampDB
        )
    }
}
