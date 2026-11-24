//
//  SpectralIntegrityAnalyzer.swift
//  AppleMusicRemoteMac
//
//  Real-Time Audiophile Spectral Integrity & Upsampling Detector (Accelerate / vDSP FFT).
//  Analyzes uncompressed Float32 PCM buffers from AudioProcessTapService (< 0.1% CPU on Apple Silicon):
//  - 2048-point Hann-windowed Forward Real FFT (vDSP_fft_zrip)
//  - Effective upper frequency cutoff detection (Brickwall detector at 16–18.5 kHz for Lossy Transcodes,
//    22.05 kHz for Fake Hi-Res / Upsampled CD masters, and > 23 kHz for Verified True Hi-Res)
//  - True 24-bit LSB vs 16-bit Zero-Padding verification
//  - 32-band Real-Time Analyzer (RTA) spectrum output for the Signal Path Inspector UI
//

import Foundation
import Accelerate
import os

public struct CachedSpectralValidation: Codable, Sendable, Equatable {
    public var trackId: String
    public var trackKey: String
    public var isLocal: Bool
    public var verdict: String
    public var verdictTitle: String
    public var verdictDescription: String
    public var isAuthentic: Bool
    public var sampleRate: Int
    public var claimedBitDepth: Int
    public var effectiveBitDepth: Int
    public var isZeroPadded: Bool
    public var cutoffFrequencyHz: Double
    public var nyquistFrequencyHz: Double
    public var ultrasonicEnergyDb: Double
    public var highBandEnergyDb: Double
    public var dynamicRangeCrestDb: Double
    public var analyzedFramesCount: Int
    public var validatedAt: Date
    public var ttDrScore: Int?
    public var integratedLufs: Double?
    public var loudnessRangeLu: Double?
    public var truePeakDbtp: Double?

    public init(
        trackId: String,
        trackKey: String,
        isLocal: Bool,
        verdict: String,
        verdictTitle: String,
        verdictDescription: String,
        isAuthentic: Bool,
        sampleRate: Int,
        claimedBitDepth: Int,
        effectiveBitDepth: Int,
        isZeroPadded: Bool,
        cutoffFrequencyHz: Double,
        nyquistFrequencyHz: Double,
        ultrasonicEnergyDb: Double,
        highBandEnergyDb: Double,
        dynamicRangeCrestDb: Double,
        analyzedFramesCount: Int,
        validatedAt: Date = Date(),
        ttDrScore: Int? = nil,
        integratedLufs: Double? = nil,
        loudnessRangeLu: Double? = nil,
        truePeakDbtp: Double? = nil
    ) {
        self.trackId = trackId
        self.trackKey = trackKey
        self.isLocal = isLocal
        self.verdict = verdict
        self.verdictTitle = verdictTitle
        self.verdictDescription = verdictDescription
        self.isAuthentic = isAuthentic
        self.sampleRate = sampleRate
        self.claimedBitDepth = claimedBitDepth
        self.effectiveBitDepth = effectiveBitDepth
        self.isZeroPadded = isZeroPadded
        self.cutoffFrequencyHz = cutoffFrequencyHz
        self.nyquistFrequencyHz = nyquistFrequencyHz
        self.ultrasonicEnergyDb = ultrasonicEnergyDb
        self.highBandEnergyDb = highBandEnergyDb
        self.dynamicRangeCrestDb = dynamicRangeCrestDb
        self.analyzedFramesCount = analyzedFramesCount
        self.validatedAt = validatedAt
        self.ttDrScore = ttDrScore
        self.integratedLufs = integratedLufs
        self.loudnessRangeLu = loudnessRangeLu
        self.truePeakDbtp = truePeakDbtp
    }
}

@usableFromInline
internal struct KWeightBiquadCoeffs: Sendable {
    @usableFromInline var b0: Double = 1.0
    @usableFromInline var b1: Double = 0.0
    @usableFromInline var b2: Double = 0.0
    @usableFromInline var a1: Double = 0.0
    @usableFromInline var a2: Double = 0.0

    @usableFromInline
    init(b0: Double = 1.0, b1: Double = 0.0, b2: Double = 0.0, a1: Double = 0.0, a2: Double = 0.0) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
    }

    @usableFromInline
    @inline(__always)
    func process(_ x: Double, z1: inout Double, z2: inout Double) -> Double {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}

public final class SpectralIntegrityAnalyzer: @unchecked Sendable {
    public static let shared = SpectralIntegrityAnalyzer()

    public static let fftSize: Int = 2048
    public static let fftHopSize: Int = 1024
    public static let halfFFTSize: Int = 1024
    public static let log2N: vDSP_Length = 11
    public static let rtaBandCount: Int = 32
    internal static let maxCachedValidations: Int = 5000
    internal static let rtRingCapacity: Int = 65_536
    internal static let rtRingMask: Int = 65_535
    internal static let dspDrainChunkCapacity: Int = 8_192

    internal let lock = NSLock()
    internal let dspQueue = DispatchQueue(label: "org.ksholokhov.amr.spectral.dsp", qos: .utility)
    internal let persistenceQueue = DispatchQueue(label: "org.ksholokhov.amr.spectral.cache", qos: .utility)
    internal let cacheFileURL: URL

    internal static let keyEnabled = "SpectralAnalyzerEnabled"

    // Dedicated leaf spin-lock caching trivial Bool scalars for Real-Time CoreAudio IOProcs (~2ns).
    // NEVER hold fastFlagsLock across FFT, sorting, UserDefaults, JSON, or NSLock.
    internal var fastFlagsLock = os_unfair_lock_s()
    internal var _fastIsEnabled: Bool = true
    internal var _fastIsPlaying: Bool = false

    public var isEnabled: Bool {
        get {
            os_unfair_lock_lock(&fastFlagsLock)
            let enabled = _fastIsEnabled
            os_unfair_lock_unlock(&fastFlagsLock)
            return enabled
        }
        set {
            lock.lock()
            let changed = (isEnabledInternal != newValue)
            isEnabledInternal = newValue
            AppStorageProvider.shared.set(newValue, forKey: Self.keyEnabled)
            if !newValue {
                resetAccumulatorsLocked()
            }
            recomputeResultLocked()
            lock.unlock()
            if changed {
                NSLog("[SpectralIntegrityAnalyzer] Spectral analyzer is now: \(newValue ? "ON" : "OFF")")
                AudioProcessTapService.shared.setPassiveAnalysisEnabled(newValue)
            }
        }
    }

    internal var isEnabledInternal: Bool {
        didSet {
            os_unfair_lock_lock(&fastFlagsLock)
            _fastIsEnabled = isEnabledInternal
            os_unfair_lock_unlock(&fastFlagsLock)
            os_unfair_lock_lock(&rtSpinLock)
            rtIsEnabledFlag = isEnabledInternal
            os_unfair_lock_unlock(&rtSpinLock)
        }
    }

    internal var rtSpinLock = os_unfair_lock_s()
    internal var rtIsEnabledFlag: Bool = true
    internal var rtIsValidationCachedFlag: Bool = false
    internal var rtRingL: [Float]
    internal var rtRingR: [Float]
    internal var rtRingMono: [Float]
    internal var rtRingReadIdx: Int = 0
    internal var rtRingWriteIdx: Int = 0
    internal var rtRingCount: Int = 0
    internal var rtPendingNonSilent: Int = 0
    internal var rtPendingLSB24: Int = 0
    internal var rtConsumerScheduled: Bool = false
    internal var rtDrainSignalSource: DispatchSourceUserDataAdd!
    internal var dspDrainL: [Float] = []
    internal var dspDrainR: [Float] = []
    internal var dspDrainMono: [Float] = []

    internal let fftSetup: FFTSetup?
    internal let hannWindow: [Float]
    internal var fftFrameScratch: [Float]
    internal var fftWindowedScratch: [Float]
    internal var fftRealScratch: [Float]
    internal var fftImagScratch: [Float]
    internal var fftMagScratch: [Float]
    internal var fftHopParity: Bool = false

    // Ring buffer for incoming mono Float samples
    internal var sampleRingBuffer: [Float] = []

    // Current track metadata state
    internal var currentTrackId: String = ""
    internal var currentTrackKey: String = ""
    internal var currentIsLocal: Bool = false
    internal var currentSampleRate: Int = 44100
    internal var claimedBitDepth: Int = 16
    internal var isClaimedLossless: Bool = true
    internal var isPlayingState: Bool = false {
        didSet {
            os_unfair_lock_lock(&fastFlagsLock)
            _fastIsPlaying = isPlayingState
            os_unfair_lock_unlock(&fastFlagsLock)
        }
    }

    // Persistent + in-memory cache of passed spectral validations (local & cloud tracks)
    internal var validationCache: [String: CachedSpectralValidation] = [:]
    internal var activeCachedValidation: CachedSpectralValidation? = nil {
        didSet {
            let cached = (activeCachedValidation != nil)
            os_unfair_lock_lock(&rtSpinLock)
            rtIsValidationCachedFlag = cached
            os_unfair_lock_unlock(&rtSpinLock)
        }
    }

    // Bit-depth / Zero-padding telemetry
    internal var totalNonSilentSamples: Int = 0
    internal var nonZeroLSB24Samples: Int = 0

    // Spectral accumulators
    internal var analyzedFFTFrames: Int = 0
    internal var activeMusicalFrames: Int = 0
    internal var trebleActiveFrames: Int = 0
    internal var loudnessMaxPeakDb: Double = -96.0
    internal var loudnessFinalizedForTrack: Bool = false
    internal var isSingleBufferTestMode: Bool = false
    internal var peakBinDb: [Float]
    internal var liveBinDb: [Float]
    internal var smoothedRtaBands: [Double]
    internal var dynamicRangeCrestDb: Double = 14.0

    // ITU-R BS.1770-4 / EBU R128 K-Weighting & Loudness state
    internal var kWeightSampleRate: Int = 0
    internal var kwStage1: KWeightBiquadCoeffs = KWeightBiquadCoeffs()
    internal var kwStage2: KWeightBiquadCoeffs = KWeightBiquadCoeffs()
    internal var kwL1z1: Double = 0.0, kwL1z2: Double = 0.0
    internal var kwL2z1: Double = 0.0, kwL2z2: Double = 0.0
    internal var kwR1z1: Double = 0.0, kwR1z2: Double = 0.0
    internal var kwR2z1: Double = 0.0, kwR2z2: Double = 0.0
    internal var ebuSubBlockAccumSamples: Int = 0
    internal var ebuSubBlockSumSqL: Double = 0.0
    internal var ebuSubBlockSumSqR: Double = 0.0
    internal var ebuRecent100msEnergies: [Double] = []
    internal var ebuGated400msBlocks: [Double] = []
    internal var ebuShortTermBlocks: [Double] = []
    internal var liveMomentaryLufs: Double? = nil
    internal var liveShortTermLufs: Double? = nil
    internal var liveIntegratedLufs: Double? = nil
    internal var liveLoudnessRangeLu: Double? = nil
    internal var emittedDynamicsAt20: Bool = false
    internal var emittedDynamicsAt80: Bool = false

    // 4x Polyphase FIR True Peak (dBTP) & Inter-Sample Peak (ISP) state
    internal static let truePeakPolyphasePhases: [[Float]] = {
        let alphas: [Double] = [0.25, 0.50, 0.75]
        return alphas.map { alpha in
            var weights = [Double](repeating: 0.0, count: 12)
            var sum = 0.0
            for m in 0..<12 {
                let u = Double(m) - (5.0 + alpha)
                let sinc = sin(Double.pi * u) / (Double.pi * u)
                let hann = 0.5 * (1.0 + cos(Double.pi * u / 6.0))
                let w = sinc * hann
                weights[m] = w
                sum += w
            }
            let invSum = sum != 0.0 ? (1.0 / sum) : 1.0
            return weights.map { Float($0 * invSum) }
        }
    }()
    internal var tpRingL: [Float] = [Float](repeating: 0.0, count: 24)
    internal var tpRingR: [Float] = [Float](repeating: 0.0, count: 24)
    internal var tpRingPos: Int = 0
    internal var tpWarmupSamples: Int = 0
    internal var maxTruePeakLinear: Double = 0.0
    internal var liveTruePeakDbtp: Double? = nil
    internal var liveIspClipCount: Int = 0
    internal var tpInClipL: Bool = false
    internal var tpInClipR: Bool = false

    // Pleasurize Music Foundation TT Dynamic Range (DR) state
    internal var ttDrAccumSamples: Int = 0
    internal var ttDrSumSqL: Double = 0.0
    internal var ttDrSumSqR: Double = 0.0
    internal var ttDrBlockPeakL: Double = 0.0
    internal var ttDrBlockPeakR: Double = 0.0
    internal var ttDrBlockRmsL: [Double] = []
    internal var ttDrBlockRmsR: [Double] = []
    internal var ttDrBlockPeaksL: [Double] = []
    internal var ttDrBlockPeaksR: [Double] = []
    internal var liveTtDrScore: Int? = nil

    // Stereo Phase Correlation, Mid/Side Width & Channel Balance state
    internal var hasStereoMeasurement: Bool = false
    internal var livePhaseCorrelation: Double = 1.0
    internal var liveStereoWidthPercent: Double = 0.0
    internal var liveChannelBalanceDb: Double = 0.0

    internal var latestResult: SpectralAnalysisInfo
    internal let isTestingEnv: Bool

    internal init(customCacheFileURL: URL? = nil) {
        self.isTestingEnv = PlaybackRouter.shared.isTestingEnvironment
        if let customURL = customCacheFileURL {
            try? FileManager.default.createDirectory(at: customURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            self.cacheFileURL = customURL
        } else {
            let baseCache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let cacheDir = baseCache.appendingPathComponent("com.kirill.AppleMusicRemoteMac", isDirectory: true)
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            self.cacheFileURL = cacheDir.appendingPathComponent("spectral_validation_cache.json")
        }

        let initialEnabled: Bool
        if AppStorageProvider.shared.object(forKey: Self.keyEnabled) == nil {
            initialEnabled = true
        } else {
            initialEnabled = AppStorageProvider.shared.bool(forKey: Self.keyEnabled)
        }
        self.isEnabledInternal = initialEnabled
        self._fastIsEnabled = initialEnabled
        self._fastIsPlaying = false
        self.rtIsEnabledFlag = initialEnabled
        self.rtRingL = [Float](repeating: 0.0, count: Self.rtRingCapacity)
        self.rtRingR = [Float](repeating: 0.0, count: Self.rtRingCapacity)
        self.rtRingMono = [Float](repeating: 0.0, count: Self.rtRingCapacity)
        self.dspDrainL.reserveCapacity(Self.dspDrainChunkCapacity)
        self.dspDrainR.reserveCapacity(Self.dspDrainChunkCapacity)
        self.dspDrainMono.reserveCapacity(Self.dspDrainChunkCapacity)
        self.fftSetup = vDSP_create_fftsetup(Self.log2N, FFTRadix(kFFTRadix2))
        var window = [Float](repeating: 0, count: Self.fftSize)
        vDSP_hann_window(&window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
        self.hannWindow = window
        self.fftFrameScratch = [Float](repeating: 0.0, count: Self.fftSize)
        self.fftWindowedScratch = [Float](repeating: 0.0, count: Self.fftSize)
        self.fftRealScratch = [Float](repeating: 0.0, count: Self.halfFFTSize)
        self.fftImagScratch = [Float](repeating: 0.0, count: Self.halfFFTSize)
        self.fftMagScratch = [Float](repeating: 0.0, count: Self.halfFFTSize)
        self.peakBinDb = [Float](repeating: -96.0, count: Self.halfFFTSize)
        self.liveBinDb = [Float](repeating: -96.0, count: Self.halfFFTSize)
        self.smoothedRtaBands = [Double](repeating: 0.0, count: Self.rtaBandCount)
        self.latestResult = SpectralAnalysisInfo(isEnabled: initialEnabled)
        self.sampleRingBuffer.reserveCapacity(Self.fftSize * 2)

        let drainSource = DispatchSource.makeUserDataAddSource(queue: self.dspQueue)
        self.rtDrainSignalSource = drainSource
        drainSource.setEventHandler { [weak self] in
            self?.drainRTRingBufferOnDSPQueue()
        }
        drainSource.resume()

        if let data = try? Data(contentsOf: self.cacheFileURL),
           let decoded = try? JSONDecoder().decode([String: CachedSpectralValidation].self, from: data) {
            self.validationCache = decoded
        }
    }

    deinit {
        rtDrainSignalSource?.cancel()
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }

    // MARK: - Track Metadata & Lifecycle Sync

    public func syncTrackContext(
        trackKey: String,
        trackId: String = "",
        isLocal: Bool = false,
        sampleRate: Int,
        claimedBitDepth: Int,
        isLossless: Bool,
        isPlaying: Bool
    ) {
        let validRate = max(44100, sampleRate)
        let validDepth = isLossless ? (claimedBitDepth >= 24 ? 24 : 16) : 16
        let cleanKey = trackKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)

        lock.lock()
        let enabled = self.isEnabledInternal
        let keyChanged = (!cleanKey.isEmpty && !self.currentTrackKey.isEmpty && cleanKey != self.currentTrackKey)
        let idChanged = (!cleanId.isEmpty && cleanId != "0" && !self.currentTrackId.isEmpty && self.currentTrackId != "0" && cleanId.lowercased() != self.currentTrackId.lowercased())
        let rateChanged = (validRate != self.currentSampleRate || validDepth != self.claimedBitDepth || isLossless != self.isClaimedLossless)
        if !cleanKey.isEmpty {
            self.currentTrackKey = cleanKey
        }
        if !cleanId.isEmpty && cleanId != "0" {
            self.currentTrackId = cleanId
        } else if keyChanged {
            self.currentTrackId = ""
        }
        self.currentIsLocal = isLocal
        self.currentSampleRate = validRate
        self.claimedBitDepth = validDepth
        self.isClaimedLossless = isLossless
        self.isPlayingState = isPlaying
        self.isSingleBufferTestMode = false

        if keyChanged || idChanged || rateChanged {
            resetAccumulatorsLocked()
        }
        self.activeCachedValidation = lookupCachedValidationLocked(
            trackId: self.currentTrackId,
            trackKey: self.currentTrackKey,
            isLocal: self.currentIsLocal,
            sampleRate: validRate,
            claimedBitDepth: validDepth,
            isLossless: isLossless
        )
        recomputeResultLocked()
        lock.unlock()

        if (enabled || ExternalAmpTCPController.shared.isSoundCheckEnabled) && isPlaying && !isTestingEnv {
            AudioProcessTapService.shared.ensurePassiveAnalysisTapActive(sampleRate: validRate, bitDepth: validDepth)
        }
    }

    public func resetForNewTrack(trackKey: String = "", trackId: String = "", isLocal: Bool? = nil) {
        let clean = trackKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        let keyChanged = (!clean.isEmpty && clean != self.currentTrackKey) || (clean.isEmpty && cleanId.isEmpty)
        if !clean.isEmpty {
            self.currentTrackKey = clean
        } else if cleanId.isEmpty {
            self.currentTrackKey = ""
        }
        if !cleanId.isEmpty && cleanId != "0" {
            self.currentTrackId = cleanId
        } else if keyChanged {
            self.currentTrackId = ""
        }
        if let loc = isLocal {
            self.currentIsLocal = loc
        }
        self.isSingleBufferTestMode = false
        resetAccumulatorsLocked()
        self.activeCachedValidation = lookupCachedValidationLocked(
            trackId: self.currentTrackId,
            trackKey: self.currentTrackKey,
            isLocal: self.currentIsLocal,
            sampleRate: self.currentSampleRate,
            claimedBitDepth: self.claimedBitDepth,
            isLossless: self.isClaimedLossless
        )
        recomputeResultLocked()
        lock.unlock()
    }

    internal func resetAccumulatorsLocked() {
        os_unfair_lock_lock(&rtSpinLock)
        rtRingReadIdx = 0
        rtRingWriteIdx = 0
        rtRingCount = 0
        rtPendingNonSilent = 0
        rtPendingLSB24 = 0
        os_unfair_lock_unlock(&rtSpinLock)

        sampleRingBuffer.removeAll(keepingCapacity: true)
        fftHopParity = false
        totalNonSilentSamples = 0
        nonZeroLSB24Samples = 0
        analyzedFFTFrames = 0
        activeMusicalFrames = 0
        trebleActiveFrames = 0
        loudnessMaxPeakDb = -96.0
        loudnessFinalizedForTrack = false
        for i in 0..<Self.halfFFTSize {
            peakBinDb[i] = -96.0
            liveBinDb[i] = -96.0
        }
        for i in 0..<Self.rtaBandCount {
            smoothedRtaBands[i] = 0.0
        }
        dynamicRangeCrestDb = 14.0

        // Reset ITU-R BS.1770-4 / EBU R128 K-weighting & loudness accumulators
        kWeightSampleRate = 0
        kwL1z1 = 0.0; kwL1z2 = 0.0; kwL2z1 = 0.0; kwL2z2 = 0.0
        kwR1z1 = 0.0; kwR1z2 = 0.0; kwR2z1 = 0.0; kwR2z2 = 0.0
        ebuSubBlockAccumSamples = 0
        ebuSubBlockSumSqL = 0.0
        ebuSubBlockSumSqR = 0.0
        ebuRecent100msEnergies.removeAll(keepingCapacity: true)
        ebuGated400msBlocks.removeAll(keepingCapacity: true)
        ebuShortTermBlocks.removeAll(keepingCapacity: true)
        liveMomentaryLufs = nil
        liveShortTermLufs = nil
        liveIntegratedLufs = nil
        liveLoudnessRangeLu = nil
        emittedDynamicsAt20 = false
        emittedDynamicsAt80 = false

        // Reset 4x Polyphase True Peak & ISP counter
        for i in 0..<24 {
            tpRingL[i] = 0.0
            tpRingR[i] = 0.0
        }
        tpRingPos = 0
        tpWarmupSamples = 0
        maxTruePeakLinear = 0.0
        liveTruePeakDbtp = nil
        liveIspClipCount = 0
        tpInClipL = false
        tpInClipR = false

        // Reset TT DR Meter accumulators
        ttDrAccumSamples = 0
        ttDrSumSqL = 0.0
        ttDrSumSqR = 0.0
        ttDrBlockPeakL = 0.0
        ttDrBlockPeakR = 0.0
        ttDrBlockRmsL.removeAll(keepingCapacity: true)
        ttDrBlockRmsR.removeAll(keepingCapacity: true)
        ttDrBlockPeaksL.removeAll(keepingCapacity: true)
        ttDrBlockPeaksR.removeAll(keepingCapacity: true)
        liveTtDrScore = nil

        // Reset Stereo Phase Correlation meter
        hasStereoMeasurement = false
        livePhaseCorrelation = 1.0
        liveStereoWidthPercent = 0.0
        liveChannelBalanceDb = 0.0
    }

    /// True when playback is active (RT-safe scalar read, zero NSLock contention).
    public var isPlaying: Bool {
        os_unfair_lock_lock(&fastFlagsLock)
        let playing = _fastIsPlaying
        os_unfair_lock_unlock(&fastFlagsLock)
        return playing
    }

    public var sampleRateAndBitDepthSnapshot: (sampleRate: Int, bitDepth: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (max(44100, currentSampleRate), claimedBitDepth >= 24 ? 24 : 16)
    }

    public func getCurrentAnalysis() -> SpectralAnalysisInfo {
        lock.lock()
        defer { lock.unlock() }
        if !isPlayingState && activeMusicalFrames == 0 {
            recomputeResultLocked()
        }
        return latestResult
    }

    /// Lightweight compact RTA + live dynamics snapshot for high-rate (~11 Hz) WebSocket telemetry.
    public func getCompactRTAPayload() -> [String: Any] {
        let info = getCurrentAnalysis()
        var dict: [String: Any] = [
            "is_enabled": info.isEnabled,
            "is_cached": info.isCached,
            "verdict": info.verdict,
            "is_authentic": info.isAuthentic,
            "sample_rate": info.sampleRate,
            "claimed_bit_depth": info.claimedBitDepth,
            "effective_bit_depth": info.effectiveBitDepth,
            "is_zero_padded": info.isZeroPadded,
            "cutoff_frequency_hz": info.cutoffFrequencyHz,
            "nyquist_frequency_hz": info.nyquistFrequencyHz,
            "ultrasonic_energy_db": info.ultrasonicEnergyDb,
            "analyzed_frames_count": info.analyzedFramesCount,
            "rta_bands": info.rtaBands,
            "isp_clip_count": info.ispClipCount,
            "phase_correlation": ((info.phaseCorrelation * 100.0).rounded() / 100.0),
            "stereo_width_percent": ((info.stereoWidthPercent * 10.0).rounded() / 10.0),
            "channel_balance_db": ((info.channelBalanceDb * 10.0).rounded() / 10.0)
        ]
        if let dr = info.ttDrScore { dict["tt_dr_score"] = dr }
        dict["tt_dr_status"] = info.ttDrStatus
        if let intLufs = info.integratedLufs { dict["integrated_lufs"] = (intLufs * 10.0).rounded() / 10.0 }
        if let stLufs = info.shortTermLufs { dict["short_term_lufs"] = (stLufs * 10.0).rounded() / 10.0 }
        if let momLufs = info.momentaryLufs { dict["momentary_lufs"] = (momLufs * 10.0).rounded() / 10.0 }
        if let lra = info.loudnessRangeLu { dict["loudness_range_lu"] = (lra * 10.0).rounded() / 10.0 }
        if let tp = info.truePeakDbtp { dict["true_peak_dbtp"] = (tp * 100.0).rounded() / 100.0 }
        return dict
    }
}
