//
//  SpectralIntegrityAnalyzerTests.swift
//  AppleMusicRemoteMacTests
//
//  Unit tests for SpectralIntegrityAnalyzer (vDSP FFT Spectral Verification & Upsampling Detector).
//

import XCTest
@testable import AppleMusicRemoteMac

final class SpectralIntegrityAnalyzerTests: XCTestCase {

    private func generateTestSignal(
        sampleRate: Int,
        frameCount: Int = 8192,
        frequencies: [(hz: Double, amplitude: Double)],
        quantizeTo16Bit: Bool = false
    ) -> [Float] {
        var samples = [Float](repeating: 0, count: frameCount)
        let sr = Double(sampleRate)
        for n in 0..<frameCount {
            let t = Double(n) / sr
            var val: Double = 0
            for f in frequencies {
                val += f.amplitude * sin(2.0 * .pi * f.hz * t)
            }
            // Add deterministic subtle 24-bit dither unless quantizing to 16-bit
            if !quantizeTo16Bit {
                let lsbDither = Double((n * 73 + 19) % 127 - 63) / 8388608.0
                val += lsbDither
                samples[n] = Float(max(-0.98, min(0.98, val)))
            } else {
                let q16 = (val * 32768.0).rounded() / 32768.0
                samples[n] = Float(max(-0.98, min(0.98, q16)))
            }
        }
        return samples
    }

    func testVerifiedTrueHiRes96kHz() {
        let signal = generateTestSignal(
            sampleRate: 96000,
            frequencies: [
                (hz: 1000.0, amplitude: 0.25),
                (hz: 5000.0, amplitude: 0.18),
                (hz: 14000.0, amplitude: 0.12),
                (hz: 20500.0, amplitude: 0.08),
                (hz: 31000.0, amplitude: 0.05),
                (hz: 39000.0, amplitude: 0.03)
            ],
            quantizeTo16Bit: false
        )

        let result = SpectralIntegrityAnalyzer.shared.processFloatSamplesForTesting(
            samples: signal,
            sampleRate: 96000,
            claimedBitDepth: 24,
            isLossless: true
        )

        XCTAssertEqual(result.verdict, "verified_hires")
        XCTAssertTrue(result.isAuthentic)
        XCTAssertEqual(result.effectiveBitDepth, 24)
        XCTAssertFalse(result.isZeroPadded)
        XCTAssertGreaterThan(result.cutoffFrequencyHz, 35000.0)
        XCTAssertEqual(result.rtaBands.count, 32)
    }

    func testDetectsUpsampledFakeHiResAt96kHz() {
        // 96 kHz container, but brickwalled below 22.05 kHz (no ultrasonic content)
        let signal = generateTestSignal(
            sampleRate: 96000,
            frequencies: [
                (hz: 1200.0, amplitude: 0.25),
                (hz: 6000.0, amplitude: 0.18),
                (hz: 13000.0, amplitude: 0.14),
                (hz: 20200.0, amplitude: 0.09)
            ],
            quantizeTo16Bit: false
        )

        let result = SpectralIntegrityAnalyzer.shared.processFloatSamplesForTesting(
            samples: signal,
            sampleRate: 96000,
            claimedBitDepth: 24,
            isLossless: true
        )

        XCTAssertEqual(result.verdict, "upsampled")
        XCTAssertFalse(result.isAuthentic)
        XCTAssertLessThanOrEqual(result.cutoffFrequencyHz, 22800.0)
    }

    func testDetectsLossyTranscodeBrickwallAt15kHz() {
        // 44.1 kHz ALAC container, but brickwalled at ~14.5 kHz (MP3 128k transcode)
        let signal = generateTestSignal(
            sampleRate: 44100,
            frequencies: [
                (hz: 1000.0, amplitude: 0.25),
                (hz: 4500.0, amplitude: 0.20),
                (hz: 11500.0, amplitude: 0.15),
                (hz: 14200.0, amplitude: 0.12)
            ],
            quantizeTo16Bit: true
        )

        let result = SpectralIntegrityAnalyzer.shared.processFloatSamplesForTesting(
            samples: signal,
            sampleRate: 44100,
            claimedBitDepth: 16,
            isLossless: true
        )

        XCTAssertEqual(result.verdict, "lossy_transcode")
        XCTAssertFalse(result.isAuthentic)
        XCTAssertLessThan(result.cutoffFrequencyHz, 19000.0)
    }

    func testDetectsZeroPadded16BitIn24BitContainer() {
        // Full 48 kHz bandwidth up to 22 kHz, but quantized to 16-bit inside a 24-bit container
        let signal = generateTestSignal(
            sampleRate: 48000,
            frequencies: [
                (hz: 1000.0, amplitude: 0.25),
                (hz: 7000.0, amplitude: 0.18),
                (hz: 14000.0, amplitude: 0.12),
                (hz: 20800.0, amplitude: 0.08)
            ],
            quantizeTo16Bit: true
        )

        let result = SpectralIntegrityAnalyzer.shared.processFloatSamplesForTesting(
            samples: signal,
            sampleRate: 48000,
            claimedBitDepth: 24,
            isLossless: true
        )

        XCTAssertEqual(result.verdict, "zero_padded")
        XCTAssertTrue(result.isZeroPadded)
        XCTAssertEqual(result.effectiveBitDepth, 16)
        XCTAssertFalse(result.isAuthentic)
    }

    func testVerifiedTrueLossless44100Hz() {
        let signal = generateTestSignal(
            sampleRate: 44100,
            frequencies: [
                (hz: 1000.0, amplitude: 0.25),
                (hz: 6000.0, amplitude: 0.18),
                (hz: 13500.0, amplitude: 0.12),
                (hz: 20400.0, amplitude: 0.08)
            ],
            quantizeTo16Bit: true
        )

        let result = SpectralIntegrityAnalyzer.shared.processFloatSamplesForTesting(
            samples: signal,
            sampleRate: 44100,
            claimedBitDepth: 16,
            isLossless: true
        )

        XCTAssertEqual(result.verdict, "verified_lossless")
        XCTAssertTrue(result.isAuthentic)
        XCTAssertEqual(result.effectiveBitDepth, 16)
    }

    func testDetectsLossyUpscale128To256kbps() {
        // Claimed AAC 256 kbps (isLossless: false), but spectrum is brickwalled at ~14.5 kHz (128 -> 256 kbps upscale)
        let signal = generateTestSignal(
            sampleRate: 44100,
            frequencies: [
                (hz: 1000.0, amplitude: 0.25),
                (hz: 5000.0, amplitude: 0.20),
                (hz: 11200.0, amplitude: 0.15),
                (hz: 14500.0, amplitude: 0.11)
            ],
            quantizeTo16Bit: true
        )

        let result = SpectralIntegrityAnalyzer.shared.processFloatSamplesForTesting(
            samples: signal,
            sampleRate: 44100,
            claimedBitDepth: 16,
            isLossless: false
        )

        XCTAssertEqual(result.verdict, "lossy_upscaled")
        XCTAssertFalse(result.isAuthentic)
        XCTAssertLessThan(result.cutoffFrequencyHz, 16800.0)
    }

    func testGenuineAAC256kbps() {
        // Genuine AAC 256 kbps reaches ~18.5-19.5 kHz
        let signal = generateTestSignal(
            sampleRate: 44100,
            frequencies: [
                (hz: 1000.0, amplitude: 0.25),
                (hz: 5000.0, amplitude: 0.18),
                (hz: 12000.0, amplitude: 0.14),
                (hz: 18600.0, amplitude: 0.09)
            ],
            quantizeTo16Bit: true
        )

        let result = SpectralIntegrityAnalyzer.shared.processFloatSamplesForTesting(
            samples: signal,
            sampleRate: 44100,
            claimedBitDepth: 16,
            isLossless: false
        )

        XCTAssertEqual(result.verdict, "aac_lossy")
        XCTAssertTrue(result.isAuthentic)
        XCTAssertGreaterThanOrEqual(result.cutoffFrequencyHz, 16800.0)
    }

    func testAnalyzerDisabledState() {
        let prev = SpectralIntegrityAnalyzer.shared.isEnabled
        defer { SpectralIntegrityAnalyzer.shared.isEnabled = prev }

        SpectralIntegrityAnalyzer.shared.isEnabled = false
        let snap = SpectralIntegrityAnalyzer.shared.getCurrentAnalysis()
        XCTAssertFalse(snap.isEnabled)
        XCTAssertEqual(snap.verdict, "disabled")
    }

    // MARK: - DAC Muting Guard & Click-Free Switcher Tests

    func testDACMutingGuardConfigurationAndClamping() {
        let mgr = CoreAudioDeviceManager.shared
        let prevEnabled = mgr.isMutingGuardEnabled
        let prevDuration = mgr.mutingGuardDurationMs
        defer {
            mgr.isMutingGuardEnabled = prevEnabled
            mgr.mutingGuardDurationMs = prevDuration
        }

        mgr.isMutingGuardEnabled = true
        XCTAssertTrue(mgr.isMutingGuardEnabled)

        mgr.mutingGuardDurationMs = 150
        XCTAssertEqual(mgr.mutingGuardDurationMs, 150)

        // Clamp lower bound (min 30ms)
        mgr.mutingGuardDurationMs = 5
        XCTAssertEqual(mgr.mutingGuardDurationMs, 30)

        // Clamp upper bound (max 500ms)
        mgr.mutingGuardDurationMs = 1200
        XCTAssertEqual(mgr.mutingGuardDurationMs, 500)
    }

    func testDACMutingGuardClickFreeCycleEngagesZeroFillAndReleases() {
        let mgr = CoreAudioDeviceManager.shared
        let prevEnabled = mgr.isMutingGuardEnabled
        let prevDuration = mgr.mutingGuardDurationMs
        defer {
            mgr.isMutingGuardEnabled = prevEnabled
            mgr.mutingGuardDurationMs = prevDuration
            AudioProcessTapService.shared.setMutingGuardZeroFill(false)
        }

        mgr.isMutingGuardEnabled = true
        mgr.mutingGuardDurationMs = 100
        let initialCount = mgr.mutingGuardActivationCount

        var wasActiveDuringSwitch = false
        var wasZeroFillingDuringSwitch = false
        let exp = expectation(description: "DAC Muting Guard post-switch release")

        mgr.performClickFreeSwitchCycle(
            fromRate: 44100.0,
            toRate: 96000.0,
            switchOperation: {
                wasActiveDuringSwitch = mgr.isMutingGuardActive
                wasZeroFillingDuringSwitch = AudioProcessTapService.shared.isZeroFillingForMutingGuard
            },
            completion: {
                exp.fulfill()
            }
        )

        XCTAssertTrue(wasActiveDuringSwitch, "Muting guard must be active while CoreAudio sample rate switches")
        XCTAssertTrue(wasZeroFillingDuringSwitch, "Process Tap zero-fill must be active during sample rate switch")
        XCTAssertEqual(mgr.mutingGuardActivationCount, initialCount + 1)

        waitForExpectations(timeout: 1.0)
        XCTAssertFalse(mgr.isMutingGuardActive, "Muting guard must release after PLL/relay settling window")
        XCTAssertFalse(AudioProcessTapService.shared.isZeroFillingForMutingGuard)
    }

    func testDACMutingGuardSkipsWhenSampleRateUnchangedOrDisabled() {
        let mgr = CoreAudioDeviceManager.shared
        let prevEnabled = mgr.isMutingGuardEnabled
        defer { mgr.isMutingGuardEnabled = prevEnabled }

        mgr.isMutingGuardEnabled = true
        let initialCount = mgr.mutingGuardActivationCount
        var switched = false

        // Same rate (48kHz -> 48kHz): should NOT engage muting guard
        mgr.performClickFreeSwitchCycle(
            fromRate: 48000.0,
            toRate: 48000.0,
            switchOperation: {
                switched = true
                XCTAssertFalse(mgr.isMutingGuardActive)
            }
        )
        XCTAssertTrue(switched)
        XCTAssertEqual(mgr.mutingGuardActivationCount, initialCount)

        // Disabled guard (44.1kHz -> 192kHz): should NOT engage muting guard
        mgr.isMutingGuardEnabled = false
        mgr.performClickFreeSwitchCycle(
            fromRate: 44100.0,
            toRate: 192000.0,
            switchOperation: {
                XCTAssertFalse(mgr.isMutingGuardActive)
            }
        )
        XCTAssertEqual(mgr.mutingGuardActivationCount, initialCount)
    }

    // MARK: - Spectral Validation Cache Tests (Local & Cloud Tracks)

    func testCachesPassedValidationForLocalAndCloudTracksAndPreservesVisualization() {
        let analyzer = SpectralIntegrityAnalyzer.shared
        analyzer.clearValidationCache()
        defer { analyzer.clearValidationCache() }

        // 1. Validate a Local Hi-Res Track (persistent ID: 8F3A1B2C4D5E6F70)
        let hiResSignal = generateTestSignal(
            sampleRate: 96000,
            frequencies: [
                (hz: 1000.0, amplitude: 0.25),
                (hz: 5000.0, amplitude: 0.18),
                (hz: 14000.0, amplitude: 0.12),
                (hz: 20500.0, amplitude: 0.08),
                (hz: 31000.0, amplitude: 0.05),
                (hz: 39000.0, amplitude: 0.03)
            ],
            quantizeTo16Bit: false
        )

        let firstPass = analyzer.processFloatSamplesForTesting(
            samples: hiResSignal,
            sampleRate: 96000,
            claimedBitDepth: 24,
            isLossless: true,
            trackKey: "daft punk:give life back to music",
            trackId: "8F3A1B2C4D5E6F70",
            isLocal: true
        )

        XCTAssertEqual(firstPass.verdict, "verified_hires")
        XCTAssertTrue(firstPass.isAuthentic)
        XCTAssertTrue(firstPass.isCached)
        XCTAssertTrue(analyzer.isCurrentTrackValidationCached)
        XCTAssertNotNil(analyzer.getCachedValidation(
            trackId: "8F3A1B2C4D5E6F70",
            trackKey: "daft punk:give life back to music",
            isLocal: true,
            sampleRate: 96000,
            claimedBitDepth: 24,
            isLossless: true
        ))

        // 2. Switch to another track, then re-select the cached local track:
        //    Verdict must be immediately "verified_hires" from cache BEFORE any audio frames arrive!
        analyzer.resetForNewTrack(trackKey: "other artist:other track", trackId: "1111222233334444", isLocal: true)
        XCTAssertFalse(analyzer.isCurrentTrackValidationCached)

        analyzer.syncTrackContext(
            trackKey: "daft punk:give life back to music",
            trackId: "8F3A1B2C4D5E6F70",
            isLocal: true,
            sampleRate: 96000,
            claimedBitDepth: 24,
            isLossless: true,
            isPlaying: true
        )
        let instantCachedSnap = analyzer.getCurrentAnalysis()
        XCTAssertTrue(analyzer.isCurrentTrackValidationCached)
        XCTAssertTrue(instantCachedSnap.isCached)
        XCTAssertEqual(instantCachedSnap.verdict, "verified_hires")
        XCTAssertEqual(instantCachedSnap.effectiveBitDepth, 24)
        XCTAssertGreaterThan(instantCachedSnap.cutoffFrequencyHz, 35000.0)

        // 3. Feed a bass-only signal in visualization-only mode:
        //    RTA bands must update for visualizations while the cached "verified_hires" validation stays locked!
        let bassVisSignal = generateTestSignal(
            sampleRate: 96000,
            frequencies: [(hz: 120.0, amplitude: 0.45), (hz: 440.0, amplitude: 0.30)],
            quantizeTo16Bit: true
        )
        let visSnap = analyzer.processFloatSamplesForTesting(
            samples: bassVisSignal,
            sampleRate: 96000,
            claimedBitDepth: 24,
            isLossless: true,
            trackKey: "daft punk:give life back to music",
            trackId: "8F3A1B2C4D5E6F70",
            isLocal: true
        )
        XCTAssertTrue(visSnap.isCached)
        XCTAssertEqual(visSnap.verdict, "verified_hires")
        XCTAssertEqual(visSnap.effectiveBitDepth, 24)
        XCTAssertEqual(visSnap.rtaBands.count, 32)
        XCTAssertTrue(visSnap.rtaBands.contains(where: { $0 > 0.15 }), "RTA spectrum visualization bands must still update from live audio")

        // 4. Validate a Cloud Track by Apple Music catalogId ("617154353")
        let losslessSignal = generateTestSignal(
            sampleRate: 44100,
            frequencies: [
                (hz: 1000.0, amplitude: 0.25),
                (hz: 6000.0, amplitude: 0.18),
                (hz: 13500.0, amplitude: 0.12),
                (hz: 20400.0, amplitude: 0.08)
            ],
            quantizeTo16Bit: true
        )
        let cloudPass = analyzer.processFloatSamplesForTesting(
            samples: losslessSignal,
            sampleRate: 44100,
            claimedBitDepth: 16,
            isLossless: true,
            trackKey: "daft punk:giorgio by moroder",
            trackId: "617154353",
            isLocal: false
        )
        XCTAssertEqual(cloudPass.verdict, "verified_lossless")
        XCTAssertTrue(cloudPass.isCached)

        // Lookup by cloud catalogId alone (e.g., different localized track title) must hit cache
        analyzer.syncTrackContext(
            trackKey: "daft punk:giorgio by moroder (album version)",
            trackId: "617154353",
            isLocal: false,
            sampleRate: 44100,
            claimedBitDepth: 16,
            isLossless: true,
            isPlaying: true
        )
        let cloudInstant = analyzer.getCurrentAnalysis()
        XCTAssertTrue(cloudInstant.isCached)
        XCTAssertEqual(cloudInstant.verdict, "verified_lossless")
    }

    func testDoesNotCacheFailedValidationVerdicts() {
        let analyzer = SpectralIntegrityAnalyzer.shared
        analyzer.clearValidationCache()
        defer { analyzer.clearValidationCache() }

        // Upsampled Fake Hi-Res (96 kHz brickwalled at 20.2 kHz) must NOT be cached
        let fakeHiResSignal = generateTestSignal(
            sampleRate: 96000,
            frequencies: [
                (hz: 1200.0, amplitude: 0.25),
                (hz: 6000.0, amplitude: 0.18),
                (hz: 13000.0, amplitude: 0.14),
                (hz: 20200.0, amplitude: 0.09)
            ],
            quantizeTo16Bit: false
        )

        let failedResult = analyzer.processFloatSamplesForTesting(
            samples: fakeHiResSignal,
            sampleRate: 96000,
            claimedBitDepth: 24,
            isLossless: true,
            trackKey: "artist:fake hires track",
            trackId: "999888777",
            isLocal: false
        )

        XCTAssertEqual(failedResult.verdict, "upsampled")
        XCTAssertFalse(failedResult.isAuthentic)
        XCTAssertFalse(failedResult.isCached)
        XCTAssertFalse(analyzer.isCurrentTrackValidationCached)
        XCTAssertNil(analyzer.getCachedValidation(
            trackId: "999888777",
            trackKey: "artist:fake hires track",
            isLocal: false,
            sampleRate: 96000,
            claimedBitDepth: 24,
            isLossless: true
        ))
    }
}
