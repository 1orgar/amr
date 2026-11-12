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
        validatedAt: Date = Date()
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
    }
}

public final class SpectralIntegrityAnalyzer: @unchecked Sendable {
    public static let shared = SpectralIntegrityAnalyzer()

    public static let fftSize: Int = 2048
    public static let halfFFTSize: Int = 1024
    public static let log2N: vDSP_Length = 11
    public static let rtaBandCount: Int = 32
    private static let maxCachedValidations: Int = 10000

    private let lock = NSLock()
    private let dspQueue = DispatchQueue(label: "org.ksholokhov.amr.spectral.dsp", qos: .utility)
    private let persistenceQueue = DispatchQueue(label: "org.ksholokhov.amr.spectral.cache", qos: .utility)
    private let cacheFileURL: URL

    private static let keyEnabled = "SpectralAnalyzerEnabled"

    public var isEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return isEnabledInternal
        }
        set {
            lock.lock()
            let changed = (isEnabledInternal != newValue)
            isEnabledInternal = newValue
            UserDefaults.standard.set(newValue, forKey: Self.keyEnabled)
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

    private var isEnabledInternal: Bool

    private let fftSetup: FFTSetup?
    private let hannWindow: [Float]

    // Ring buffer for incoming mono Float samples
    private var sampleRingBuffer: [Float] = []

    // Current track metadata state
    private var currentTrackId: String = ""
    private var currentTrackKey: String = ""
    private var currentIsLocal: Bool = false
    private var currentSampleRate: Int = 44100
    private var claimedBitDepth: Int = 16
    private var isClaimedLossless: Bool = true
    private var isPlayingState: Bool = false

    // Persistent + in-memory cache of passed spectral validations (local & cloud tracks)
    private var validationCache: [String: CachedSpectralValidation] = [:]
    private var activeCachedValidation: CachedSpectralValidation? = nil

    // Bit-depth / Zero-padding telemetry
    private var totalNonSilentSamples: Int = 0
    private var nonZeroLSB24Samples: Int = 0

    // Spectral accumulators
    private var analyzedFFTFrames: Int = 0
    private var activeMusicalFrames: Int = 0
    private var trebleActiveFrames: Int = 0
    private var loudnessMusicalFrames: Int = 0
    private var loudnessPowerSum: Double = 0.0
    private var loudnessFinalizedForTrack: Bool = false
    private var isSingleBufferTestMode: Bool = false
    private var peakBinDb: [Float]
    private var liveBinDb: [Float]
    private var smoothedRtaBands: [Double]
    private var dynamicRangeCrestDb: Double = 14.0
    private var latestResult: SpectralAnalysisInfo

    private init() {
        let baseCache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let cacheDir = baseCache.appendingPathComponent("com.kirill.AppleMusicRemoteMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        self.cacheFileURL = cacheDir.appendingPathComponent("spectral_validation_cache.json")

        if UserDefaults.standard.object(forKey: Self.keyEnabled) == nil {
            self.isEnabledInternal = true
        } else {
            self.isEnabledInternal = UserDefaults.standard.bool(forKey: Self.keyEnabled)
        }
        self.fftSetup = vDSP_create_fftsetup(Self.log2N, FFTRadix(kFFTRadix2))
        var window = [Float](repeating: 0, count: Self.fftSize)
        vDSP_hann_window(&window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
        self.hannWindow = window
        self.peakBinDb = [Float](repeating: -96.0, count: Self.halfFFTSize)
        self.liveBinDb = [Float](repeating: -96.0, count: Self.halfFFTSize)
        self.smoothedRtaBands = [Double](repeating: 0.0, count: Self.rtaBandCount)
        self.latestResult = SpectralAnalysisInfo(isEnabled: self.isEnabledInternal)
        self.sampleRingBuffer.reserveCapacity(Self.fftSize * 2)

        if let data = try? Data(contentsOf: self.cacheFileURL),
           let decoded = try? JSONDecoder().decode([String: CachedSpectralValidation].self, from: data) {
            self.validationCache = decoded
        }
    }

    deinit {
        if let setup = fftSetup {
            vDSP_destroy_fftsetup(setup)
        }
    }

    // MARK: - Spectral Validation Cache (Local & Cloud Tracks)

    private static func makeFormatSuffix(sampleRate: Int, claimedBitDepth: Int, isLossless: Bool) -> String {
        let rate = max(44100, sampleRate)
        let depth = isLossless ? (claimedBitDepth >= 24 ? 24 : 16) : 16
        return "\(rate):\(depth):\(isLossless ? 1 : 0)"
    }

    private static func makeIdCacheKey(
        trackId: String,
        isLocal: Bool,
        sampleRate: Int,
        claimedBitDepth: Int,
        isLossless: Bool
    ) -> String? {
        let cleanId = trackId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanId.isEmpty, cleanId != "0" else { return nil }
        let prefix = isLocal ? "local_id" : "cloud_id"
        let fmt = makeFormatSuffix(sampleRate: sampleRate, claimedBitDepth: claimedBitDepth, isLossless: isLossless)
        return "\(prefix):\(cleanId):\(fmt)"
    }

    private static func makeMetadataCacheKey(
        trackKey: String,
        sampleRate: Int,
        claimedBitDepth: Int,
        isLossless: Bool
    ) -> String? {
        let cleanKey = trackKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanKey.isEmpty, cleanKey != ":" else { return nil }
        let fmt = makeFormatSuffix(sampleRate: sampleRate, claimedBitDepth: claimedBitDepth, isLossless: isLossless)
        return "track_key:\(cleanKey):\(fmt)"
    }

    private func lookupCachedValidationLocked(
        trackId: String,
        trackKey: String,
        isLocal: Bool,
        sampleRate: Int,
        claimedBitDepth: Int,
        isLossless: Bool
    ) -> CachedSpectralValidation? {
        let idKey = Self.makeIdCacheKey(
            trackId: trackId,
            isLocal: isLocal,
            sampleRate: sampleRate,
            claimedBitDepth: claimedBitDepth,
            isLossless: isLossless
        )
        let metaKey = Self.makeMetadataCacheKey(
            trackKey: trackKey,
            sampleRate: sampleRate,
            claimedBitDepth: claimedBitDepth,
            isLossless: isLossless
        )

        if let idKey = idKey, let entry = validationCache[idKey], entry.isAuthentic {
            if let metaKey = metaKey, validationCache[metaKey] == nil {
                validationCache[metaKey] = entry
            }
            return entry
        }

        if let metaKey = metaKey, let entry = validationCache[metaKey], entry.isAuthentic {
            if let idKey = idKey, validationCache[idKey] == nil {
                var updated = entry
                if updated.trackId.isEmpty {
                    updated.trackId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                validationCache[idKey] = updated
            }
            return entry
        }

        return nil
    }

    private func storePassedValidationLocked(_ entry: CachedSpectralValidation, isLossless: Bool) {
        guard entry.isAuthentic else { return }

        var wroteNewKey = false
        if let idKey = Self.makeIdCacheKey(
            trackId: entry.trackId,
            isLocal: entry.isLocal,
            sampleRate: entry.sampleRate,
            claimedBitDepth: entry.claimedBitDepth,
            isLossless: isLossless
        ) {
            if validationCache[idKey] != entry {
                validationCache[idKey] = entry
                wroteNewKey = true
            }
        }

        if let metaKey = Self.makeMetadataCacheKey(
            trackKey: entry.trackKey,
            sampleRate: entry.sampleRate,
            claimedBitDepth: entry.claimedBitDepth,
            isLossless: isLossless
        ) {
            if validationCache[metaKey] != entry {
                validationCache[metaKey] = entry
                wroteNewKey = true
            }
        }

        if validationCache.count > Self.maxCachedValidations {
            let sortedKeys = validationCache.sorted { $0.value.validatedAt < $1.value.validatedAt }.prefix(1000).map { $0.key }
            for k in sortedKeys {
                validationCache.removeValue(forKey: k)
            }
        }

        if wroteNewKey {
            let snapshot = validationCache
            let url = cacheFileURL
            persistenceQueue.async {
                if let encoded = try? JSONEncoder().encode(snapshot) {
                    try? encoded.write(to: url, options: .atomic)
                }
            }
        }
    }

    public func getCachedValidation(
        trackId: String = "",
        trackKey: String = "",
        isLocal: Bool = false,
        sampleRate: Int,
        claimedBitDepth: Int,
        isLossless: Bool
    ) -> CachedSpectralValidation? {
        let validRate = max(44100, sampleRate)
        let validDepth = isLossless ? (claimedBitDepth >= 24 ? 24 : 16) : 16
        lock.lock()
        defer { lock.unlock() }
        return lookupCachedValidationLocked(
            trackId: trackId,
            trackKey: trackKey,
            isLocal: isLocal,
            sampleRate: validRate,
            claimedBitDepth: validDepth,
            isLossless: isLossless
        )
    }

    public var isCurrentTrackValidationCached: Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeCachedValidation != nil
    }

    public var cachedValidationEntriesCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return validationCache.count
    }

    public func clearValidationCache() {
        lock.lock()
        validationCache.removeAll()
        activeCachedValidation = nil
        recomputeResultLocked()
        let url = cacheFileURL
        lock.unlock()
        persistenceQueue.async {
            try? FileManager.default.removeItem(at: url)
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

        if (enabled || ExternalAmpTCPController.shared.isSoundCheckEnabled) && isPlaying && !PlaybackRouter.shared.isTestingEnvironment {
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

    private func resetAccumulatorsLocked() {
        sampleRingBuffer.removeAll(keepingCapacity: true)
        totalNonSilentSamples = 0
        nonZeroLSB24Samples = 0
        analyzedFFTFrames = 0
        activeMusicalFrames = 0
        trebleActiveFrames = 0
        loudnessMusicalFrames = 0
        loudnessPowerSum = 0.0
        loudnessFinalizedForTrack = false
        for i in 0..<Self.halfFFTSize {
            peakBinDb[i] = -96.0
            liveBinDb[i] = -96.0
        }
        for i in 0..<Self.rtaBandCount {
            smoothedRtaBands[i] = 0.0
        }
        dynamicRangeCrestDb = 14.0
    }

    public var isPlaying: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isPlayingState
    }

    public func getCurrentAnalysis() -> SpectralAnalysisInfo {
        lock.lock()
        defer { lock.unlock() }
        if !isPlayingState && activeMusicalFrames == 0 {
            recomputeResultLocked()
        }
        return latestResult
    }

    // MARK: - Real-Time Float32 PCM Ingestion from AudioProcessTapService

    public func processNonInterleavedFloatFrames(
        left: UnsafePointer<Float>,
        right: UnsafePointer<Float>,
        frameCount: Int
    ) {
        guard !PlaybackRouter.shared.isTestingEnvironment,
              (isEnabled || ExternalAmpTCPController.shared.isSoundCheckEnabled),
              frameCount > 0 else { return }
        var mono = [Float](repeating: 0, count: frameCount)
        var nonSilent = 0
        var lsb24 = 0

        if isCurrentTrackValidationCached {
            // Fast visualization-only path: skip 24-bit LSB bit-depth scanning and use SIMD stereo-to-mono mixdown
            var half: Float = 0.5
            vDSP_vasm(left, 1, right, 1, &half, &mono, 1, vDSP_Length(frameCount))
        } else {
            let step = max(1, frameCount / 512)
            var i = 0
            while i < frameCount {
                let l = left[i]
                let r = right[i]
                if i % step == 0 {
                    let s24L = Int32((Double(l) * 8388608.0).rounded())
                    let absL = abs(s24L)
                    if absL > 256 {
                        nonSilent += 1
                        if (absL & 0xFE) != 0 {
                            lsb24 += 1
                        }
                    }
                }
                mono[i] = 0.5 * (l + r)
                i += 1
            }
        }

        dspQueue.async { [weak self] in
            self?.ingestMonoFrames(mono, nonSilentCount: nonSilent, lsb24Count: lsb24)
        }
    }

    public func processInterleavedFloatFrames(
        interleaved: UnsafePointer<Float>,
        floatCount: Int,
        channels: Int
    ) {
        guard !PlaybackRouter.shared.isTestingEnvironment,
              (isEnabled || ExternalAmpTCPController.shared.isSoundCheckEnabled) else { return }
        let ch = max(1, channels)
        let frameCount = floatCount / ch
        guard frameCount > 0 else { return }

        var mono = [Float](repeating: 0, count: frameCount)
        var nonSilent = 0
        var lsb24 = 0

        if isCurrentTrackValidationCached {
            // Fast visualization-only path: extract mono for RTA visualization without 24-bit LSB scanning
            for f in 0..<frameCount {
                let idx = f * ch
                let l = interleaved[idx]
                let r = (ch > 1) ? interleaved[idx + 1] : l
                mono[f] = 0.5 * (l + r)
            }
        } else {
            let step = max(1, frameCount / 512)
            for f in 0..<frameCount {
                let idx = f * ch
                let l = interleaved[idx]
                let r = (ch > 1) ? interleaved[idx + 1] : l
                if f % step == 0 {
                    let s24L = Int32((Double(l) * 8388608.0).rounded())
                    let absL = abs(s24L)
                    if absL > 256 {
                        nonSilent += 1
                        if (absL & 0xFE) != 0 {
                            lsb24 += 1
                        }
                    }
                }
                mono[f] = 0.5 * (l + r)
            }
        }

        dspQueue.async { [weak self] in
            self?.ingestMonoFrames(mono, nonSilentCount: nonSilent, lsb24Count: lsb24)
        }
    }

    /// Synchronous helper for deterministic unit testing of synthetic audio signals.
    public func processFloatSamplesForTesting(
        samples: [Float],
        sampleRate: Int,
        claimedBitDepth: Int,
        isLossless: Bool,
        trackKey: String = "",
        trackId: String = "",
        isLocal: Bool = false
    ) -> SpectralAnalysisInfo {
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
            for s in samples {
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

        ingestMonoFramesLocked(samples, nonSilentCount: nonSilent, lsb24Count: lsb24)
        return latestResult
    }

    // MARK: - Core FFT & Spectral Evaluation

    private func ingestMonoFrames(_ mono: [Float], nonSilentCount: Int, lsb24Count: Int) {
        lock.lock()
        defer { lock.unlock() }
        ingestMonoFramesLocked(mono, nonSilentCount: nonSilentCount, lsb24Count: lsb24Count)
    }

    private func ingestMonoFramesLocked(_ mono: [Float], nonSilentCount: Int, lsb24Count: Int) {
        let visualizationOnly = (activeCachedValidation != nil)
        if !visualizationOnly {
            totalNonSilentSamples += nonSilentCount
            nonZeroLSB24Samples += lsb24Count
        }
        sampleRingBuffer.append(contentsOf: mono)

        if visualizationOnly {
            // Fast visualization-only path: only run FFT on the latest frame for RTA bars
            if sampleRingBuffer.count >= Self.fftSize {
                let latestFrame = Array(sampleRingBuffer.suffix(Self.fftSize))
                sampleRingBuffer.removeAll(keepingCapacity: true)
                performFFTFrameLocked(latestFrame, visualizationOnly: true)
            }
        } else {
            // Cap ring buffer so we don't fall behind real-time
            if sampleRingBuffer.count > Self.fftSize * 4 {
                sampleRingBuffer.removeFirst(sampleRingBuffer.count - Self.fftSize * 2)
            }

            while sampleRingBuffer.count >= Self.fftSize {
                let frame = Array(sampleRingBuffer.prefix(Self.fftSize))
                sampleRingBuffer.removeFirst(Self.fftSize)
                performFFTFrameLocked(frame, visualizationOnly: false)
            }
        }

        recomputeResultLocked()
    }

    private func performFFTFrameLocked(_ frame: [Float], visualizationOnly: Bool = false) {
        guard let setup = fftSetup else { return }

        // 1. Compute RMS & Peak for Crest Factor and silence gating
        var rms: Float = 0
        vDSP_rmsqv(frame, 1, &rms, vDSP_Length(Self.fftSize))
        var peak: Float = 0
        vDSP_maxmgv(frame, 1, &peak, vDSP_Length(Self.fftSize))

        let rmsDb = 20.0 * log10(Double(max(rms, 1e-6)))
        let peakDb = 20.0 * log10(Double(max(peak, 1e-6)))

        analyzedFFTFrames += 1

        if rmsDb > -54.0 {
            let crest = max(3.0, min(24.0, peakDb - rmsDb))
            dynamicRangeCrestDb = dynamicRangeCrestDb * 0.88 + crest * 0.12
        }

        // 2. Apply Hann Window
        var windowed = [Float](repeating: 0, count: Self.fftSize)
        vDSP_vmul(frame, 1, hannWindow, 1, &windowed, 1, vDSP_Length(Self.fftSize))

        // 3. Pack into Split Complex and run Forward Real FFT
        var realp = [Float](repeating: 0, count: Self.halfFFTSize)
        var imagp = [Float](repeating: 0, count: Self.halfFFTSize)
        var magnitudes = [Float](repeating: 0, count: Self.halfFFTSize)

        realp.withUnsafeMutableBufferPointer { realBuf in
            imagp.withUnsafeMutableBufferPointer { imagBuf in
                guard let rBase = realBuf.baseAddress, let iBase = imagBuf.baseAddress else { return }
                var splitComplex = DSPSplitComplex(realp: rBase, imagp: iBase)
                windowed.withUnsafeBytes { rawBytes in
                    guard let complexPtr = rawBytes.baseAddress?.assumingMemoryBound(to: DSPComplex.self) else { return }
                    vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(Self.halfFFTSize))
                }
                vDSP_fft_zrip(setup, &splitComplex, 1, Self.log2N, FFTDirection(kFFTDirection_Forward))
                splitComplex.imagp[0] = 0 // Nyquist component packed in imagp[0]
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(Self.halfFFTSize))
            }
        }

        // Normalize squared magnitudes by (N/2)^2
        let normFactor = Float(Self.halfFFTSize * Self.halfFFTSize)
        let hasSignalForRta = (rmsDb > -72.0)
        let isMusicalFrame = (rmsDb > -62.0)
        if isMusicalFrame {
            activeMusicalFrames += 1
        }

        // Accumulate K-weighted ITU-R BS.1770 / SoundCheck loudness matrix for tracks lacking iTunNORM metadata
        accumulateLoudnessMatrixFrameLocked(rms: rms, rmsDb: rmsDb, magnitudes: magnitudes, normFactor: normFactor)

        if visualizationOnly {
            for k in 1..<Self.halfFFTSize {
                let normMagSq = max(magnitudes[k] / normFactor, 1e-10)
                let db = max(-96.0, min(0.0, 10.0 * log10(normMagSq)))
                if db > liveBinDb[k] {
                    liveBinDb[k] = liveBinDb[k] * 0.35 + db * 0.65
                } else {
                    liveBinDb[k] = liveBinDb[k] * 0.78 + db * 0.22
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
            let normMagSq = max(magnitudes[k] / normFactor, 1e-10)
            let db = max(-96.0, min(0.0, 10.0 * log10(normMagSq)))
            // Smooth live spectrum for RTA display (fast attack, smooth musical release)
            if db > liveBinDb[k] {
                liveBinDb[k] = liveBinDb[k] * 0.35 + db * 0.65
            } else {
                liveBinDb[k] = liveBinDb[k] * 0.78 + db * 0.22
            }

            if isMusicalFrame {
                if k >= trebleStartBin && k <= trebleEndBin && db > frameMaxTrebleDb {
                    frameMaxTrebleDb = db
                }
                // Cumulative non-decaying peak hold per track:
                // Captures even brief high-frequency bursts and prevents flickering during quiet passages.
                if db > peakBinDb[k] {
                    peakBinDb[k] = db
                }
            }
        }

        if isMusicalFrame && frameMaxTrebleDb > -66.0 {
            trebleActiveFrames += 1
        }

        updateRtaBandsLocked(isMusicalFrame: hasSignalForRta)
    }

    /// Accumulates perceptual ITU-R BS.1770 K-weighted loudness for tracks without `iTunNORM` metadata.
    /// Once 45 active musical frames (~2s) are analyzed, emits an initial normalization gain to `AppleSoundCheckService`
    /// and refines/locks it in persistent cache at 180 frames (~8s).
    private func accumulateLoudnessMatrixFrameLocked(
        rms: Float,
        rmsDb: Double,
        magnitudes: [Float],
        normFactor: Float
    ) {
        guard !loudnessFinalizedForTrack,
              rmsDb > -44.0,
              !currentTrackKey.isEmpty,
              currentTrackKey != ":",
              ExternalAmpTCPController.shared.isSoundCheckEnabled else {
            return
        }

        if loudnessMusicalFrames == 0 {
            if AppleSoundCheckService.shared.hasFinalizedCachedGain(trackId: currentTrackId, trackKey: currentTrackKey) {
                loudnessFinalizedForTrack = true
                return
            }
        }

        // Compute K-weighted spectral balance modifier from FFT bins (sub-bass shelf -4 dB, presence 1.5-6 kHz +3.4 dB)
        let nyquist = Double(currentSampleRate) / 2.0
        let binHz = max(1.0, nyquist / Double(Self.halfFFTSize))
        let lowBinEnd = max(1, min(Self.halfFFTSize - 1, Int(120.0 / binHz)))
        let presBinStart = max(lowBinEnd + 1, min(Self.halfFFTSize - 1, Int(1500.0 / binHz)))
        let presBinEnd = max(presBinStart, min(Self.halfFFTSize - 1, Int(6000.0 / binHz)))

        var totalBinEnergy: Double = 0.0
        var weightedBinEnergy: Double = 0.0
        let step = 2
        var k = 1
        while k < Self.halfFFTSize {
            let e = Double(magnitudes[k] / normFactor)
            totalBinEnergy += e
            if k <= lowBinEnd {
                weightedBinEnergy += e * 0.42
            } else if k >= presBinStart && k <= presBinEnd {
                weightedBinEnergy += e * 2.15
            } else {
                weightedBinEnergy += e
            }
            k += step
        }

        let kWeightRatio = totalBinEnergy > 1e-12 ? max(0.5, min(2.2, weightedBinEnergy / totalBinEnergy)) : 1.0
        let framePower = Double(rms * rms) * kWeightRatio

        loudnessPowerSum += framePower
        loudnessMusicalFrames += 1

        if loudnessMusicalFrames == 45 || loudnessMusicalFrames == 180 {
            if AppleSoundCheckService.shared.hasFinalizedCachedGain(trackId: currentTrackId, trackKey: currentTrackKey) {
                loudnessFinalizedForTrack = true
                return
            }
            let isRefined = (loudnessMusicalFrames >= 180)
            if isRefined {
                loudnessFinalizedForTrack = true
            }
            let meanPower = loudnessPowerSum / Double(loudnessMusicalFrames)
            let measuredLufsDb = 10.0 * log10(max(meanPower, 1e-10))
            // Never boost above 0.0 dB on live stream fallback (only attenuate loud masters in -12.0...0.0 dB range)
            let computedGainDb = max(-12.0, min(0.0, -16.5 - measuredLufsDb))
            let tId = currentTrackId
            let tKey = currentTrackKey

            persistenceQueue.async {
                AppleSoundCheckService.shared.recordLiveDSPLoudness(
                    trackId: tId,
                    trackKey: tKey,
                    gainDb: computedGainDb,
                    isRefined: isRefined
                )
            }
        }
    }

    private func updateRtaBandsLocked(isMusicalFrame: Bool) {
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
                : smoothedRtaBands[bandIdx] * 0.85

            let prev = smoothedRtaBands[bandIdx]
            if normalized > prev {
                smoothedRtaBands[bandIdx] = prev * 0.32 + normalized * 0.68
            } else {
                smoothedRtaBands[bandIdx] = prev * 0.72 + normalized * 0.28
            }
        }
    }

    private func averagePeakDbInBand(lowHz: Double, highHz: Double) -> Double {
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

    private func estimateCutoffFrequencyLocked(midEnergyDb: Double) -> Double {
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

    private func recomputeResultLocked() {
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
        // keeping only the live RTA spectrum bands for UI visualizations.
        if let cached = activeCachedValidation, cached.isAuthentic {
            let liveBands = (isPlayingState && smoothedRtaBands.contains(where: { $0 > 0.05 }))
                ? smoothedRtaBands
                : makePreviewBandsForIdleState(nyquist: nyquist)
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
                rtaBands: liveBands
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
            let fallbackBands = makePreviewBandsForIdleState(nyquist: nyquist)
            let khzStr = formatKhz(Double(currentSampleRate))
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
                    rtaBands: fallbackBands
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
                    rtaBands: fallbackBands
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
                    rtaBands: fallbackBands
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
                analyzedFramesCount: activeMusicalFrames
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
            rtaBands: smoothedRtaBands
        )
    }

    private func makePreviewBandsForIdleState(nyquist: Double) -> [Double] {
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

    private func formatKhz(_ hz: Double) -> String {
        let khz = hz / 1000.0
        return (khz.truncatingRemainder(dividingBy: 1) == 0)
            ? String(format: "%.0f", khz)
            : String(format: "%.1f", khz)
    }
}
