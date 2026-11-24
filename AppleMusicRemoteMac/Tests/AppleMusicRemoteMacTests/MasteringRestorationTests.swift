//
//  MasteringRestorationTests.swift
//  AppleMusicRemoteMacTests
//
//  Unit tests for 64-Bit Studio Mastering Pre-DSP Suite:
//  - MasteringDeClipper (C1 Cubic Hermite peak reconstruction + Adaptive Ceiling + Smart Guard)
//  - Weiss-Style Dynamic De-Esser (Level-independent relative sibilance detector + RBJ bell cut)
//  - iCloud Drive Two-Way LWW Synchronization
//

import XCTest
@testable import AppleMusicRemoteMac

final class MasteringRestorationTests: XCTestCase {

    private var tempDir: URL!
    private var suiteA: String!
    private var suiteB: String!
    private var defaultsA: UserDefaults!
    private var defaultsB: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("amr-mastering-restoration-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        suiteA = "com.amr.tests.mrA.\(UUID().uuidString)"
        suiteB = "com.amr.tests.mrB.\(UUID().uuidString)"
        defaultsA = UserDefaults(suiteName: suiteA)
        defaultsB = UserDefaults(suiteName: suiteB)
    }

    override func tearDownWithError() throws {
        if let suiteA { defaultsA?.removePersistentDomain(forName: suiteA) }
        if let suiteB { defaultsB?.removePersistentDomain(forName: suiteB) }
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        try super.tearDownWithError()
    }

    // MARK: - 1. 100% Bit-Exact Identity When Off

    func testBitExactIdentityWhenBothModesOff() {
        let proc = MasteringRestorationProcessor()
        proc.configure(deClipMode: .off, deEsserMode: .off)

        let n = 1024
        var origL = [Double](repeating: 0.0, count: n)
        var origR = [Double](repeating: 0.0, count: n)
        for i in 0..<n {
            origL[i] = sin(Double(i) * 0.173) * 0.92
            origR[i] = cos(Double(i) * 0.119) * 0.78
        }

        var bufL = origL
        var bufR = origR
        bufL.withUnsafeMutableBufferPointer { lPtr in
            bufR.withUnsafeMutableBufferPointer { rPtr in
                proc.processPlanarDouble(
                    left: lPtr.baseAddress!,
                    right: rPtr.baseAddress!,
                    frameCount: n,
                    sampleRate: 48_000.0
                )
            }
        }

        for i in 0..<n {
            XCTAssertEqual(bufL[i], origL[i], accuracy: 0.0, "Sample \(i) L must be bit-exact when off")
            XCTAssertEqual(bufR[i], origR[i], accuracy: 0.0, "Sample \(i) R must be bit-exact when off")
        }
    }

    // MARK: - 2. Brickwall Clipped Sine Crest Reconstruction & MSE Improvement

    func testDeClipperReconstructsBrickwallClippedSineCrests() {
        let proc = MasteringRestorationProcessor()
        proc.configure(deClipMode: .studio, deEsserMode: .off)

        let sr = 48_000.0
        let freq = 1000.0
        let trueAmp = 1.38 // ~ +2.8 dB above 0 dBFS brickwall
        let frames = 4096

        var trueWave = [Double](repeating: 0.0, count: frames)
        var clippedL = [Double](repeating: 0.0, count: frames)
        var clippedR = [Double](repeating: 0.0, count: frames)

        for i in 0..<frames {
            let s = trueAmp * sin(2.0 * Double.pi * freq * Double(i) / sr)
            trueWave[i] = s
            let hardClipped = min(1.0, max(-1.0, s))
            clippedL[i] = hardClipped
            clippedR[i] = -hardClipped
        }

        var outL = clippedL
        var outR = clippedR
        outL.withUnsafeMutableBufferPointer { lPtr in
            outR.withUnsafeMutableBufferPointer { rPtr in
                proc.processPlanarDouble(
                    left: lPtr.baseAddress!,
                    right: rPtr.baseAddress!,
                    frameCount: frames,
                    sampleRate: sr,
                    applyOutputHeadroom: false
                )
            }
        }

        let snap = proc.telemetrySnapshot()
        XCTAssertGreaterThan(snap.reconstructedClipsCount, 40, "Should detect and reconstruct clipped half-cycles")
        XCTAssertGreaterThan(snap.restoredPeakDB, 2.0, "Should restore > +2.0 dB peak crest above 0 dBFS plateau")

        // Compare MSE vs true unclipped sine after 256-sample look-ahead delay
        let delay = 256
        var mseClipped = 0.0
        var mseRestored = 0.0
        var maxRestoredPeak = 0.0
        var count = 0
        for t in 512..<(frames - delay) {
            let truth = trueWave[t]
            let clipVal = clippedL[t]
            let restVal = outL[t + delay]
            mseClipped += (clipVal - truth) * (clipVal - truth)
            mseRestored += (restVal - truth) * (restVal - truth)
            maxRestoredPeak = max(maxRestoredPeak, abs(restVal))
            count += 1
        }
        mseClipped /= Double(count)
        mseRestored /= Double(count)

        XCTAssertGreaterThan(maxRestoredPeak, 1.28, "Restored crest should rise cleanly above 1.28 (vs 1.0 clipped)")
        XCTAssertLessThan(mseRestored, mseClipped * 0.15, "Cubic Hermite de-clipping must cut waveform MSE by > 85%")
    }

    // MARK: - 3. Clean Sine & Intentional Square-Wave Synth Immunity

    func testDeClipperLeavesCleanSineAndSquareSynthUntouched() {
        let proc = MasteringRestorationProcessor()
        proc.configure(deClipMode: .studio, deEsserMode: .off)

        let sr = 48_000.0
        let frames = 2048
        var cleanL = [Double](repeating: 0.0, count: frames)
        var synthSquareR = [Double](repeating: 0.0, count: frames)

        for i in 0..<frames {
            // -3 dBFS clean sine
            cleanL[i] = 0.707 * sin(2.0 * Double.pi * 440.0 * Double(i) / sr)
            // 60 Hz square-wave synth: 400 samples per half-cycle (well above ~50-sample maxClipRunSamples)
            synthSquareR[i] = ((i / 400) % 2 == 0) ? 0.995 : -0.995
        }

        var outL = cleanL
        var outR = synthSquareR
        outL.withUnsafeMutableBufferPointer { lPtr in
            outR.withUnsafeMutableBufferPointer { rPtr in
                proc.processPlanarDouble(
                    left: lPtr.baseAddress!,
                    right: rPtr.baseAddress!,
                    frameCount: frames,
                    sampleRate: sr,
                    applyOutputHeadroom: false
                )
            }
        }

        let snap = proc.telemetrySnapshot()
        XCTAssertEqual(snap.reconstructedClipsCount, 0, "Clean sine and long square-wave synths must NOT trigger false clip repairs")

        let delay = 256
        for t in 0..<(frames - delay) {
            XCTAssertEqual(outL[t + delay], cleanL[t], accuracy: 0.0, "Unclipped audio must remain bit-exact after look-ahead delay")
            XCTAssertEqual(outR[t + delay], synthSquareR[t], accuracy: 0.0, "Intentional square-wave synth plateaus must remain untouched")
        }
    }

    // MARK: - 4. Smart Guard Auto-Bypass on Verified High-DR Audiophile Masters

    func testSmartGuardAutoBypassOnVerifiedHighDRMaster() {
        let svc = MasteringRestorationService(userDefaults: defaultsA, suiteKeyPrefix: "test.smartguard", isIsolated: true)
        svc.setDeClipMode(.auto, notifyCloudSync: false)

        // 1. Hint a clean DR14 audiophile recording
        svc.updateTrackDynamicsHint(ttDrScore: 14, truePeakDbtp: -1.5)
        XCTAssertTrue(svc.activeTelemetrySnapshot().autoBypassedCleanMaster)

        let sr = 48_000.0
        let frames = 2048
        var waveL = (0..<frames).map { min(1.0, max(-1.0, 1.35 * sin(2.0 * Double.pi * 1000.0 * Double($0) / sr))) }
        var waveR = waveL

        waveL.withUnsafeMutableBufferPointer { lPtr in
            waveR.withUnsafeMutableBufferPointer { rPtr in
                svc.processDSPPlanarDoubleIfEnabled(
                    left: lPtr.baseAddress!,
                    right: rPtr.baseAddress!,
                    frameCount: frames,
                    sampleRate: sr
                )
            }
        }
        XCTAssertEqual(svc.activeTelemetrySnapshot().reconstructedClipsCount, 0, "DR14 verified clean master must be bypassed in Auto mode")

        // 2. Now hint a brickwall DR5 Loudness War remaster -> Auto Smart Guard immediately engages!
        svc.updateTrackDynamicsHint(ttDrScore: 5, truePeakDbtp: 0.35)
        XCTAssertFalse(svc.activeTelemetrySnapshot().autoBypassedCleanMaster)

        var clippedL = (0..<frames).map { min(1.0, max(-1.0, 1.35 * sin(2.0 * Double.pi * 1000.0 * Double($0) / sr))) }
        var clippedR = clippedL
        clippedL.withUnsafeMutableBufferPointer { lPtr in
            clippedR.withUnsafeMutableBufferPointer { rPtr in
                svc.processDSPPlanarDoubleIfEnabled(
                    left: lPtr.baseAddress!,
                    right: rPtr.baseAddress!,
                    frameCount: frames,
                    sampleRate: sr
                )
            }
        }
        XCTAssertGreaterThan(svc.activeTelemetrySnapshot().reconstructedClipsCount, 15, "DR5 brickwall master must be actively restored in Auto mode")
    }

    // MARK: - 5. Passthrough Float32 Output Headroom Prevents Re-Clipping & Restores Crest Factor

    func testPassthroughFloat32HeadroomPreventsReClipping() {
        let proc = MasteringRestorationProcessor()
        proc.configure(deClipMode: .studio, deEsserMode: .off)

        let sr = 48_000.0
        let frames = 4096
        var inL = [Float](repeating: 0.0, count: frames)
        var inR = [Float](repeating: 0.0, count: frames)
        for i in 0..<frames {
            let raw = 1.45 * sin(2.0 * Double.pi * 800.0 * Double(i) / sr)
            let clipped = Float(min(1.0, max(-1.0, raw)))
            inL[i] = clipped
            inR[i] = clipped
        }

        let inCrestDB: Double = {
            let sumSq = inL.reduce(0.0) { $0 + Double($1 * $1) }
            let rms = sqrt(sumSq / Double(frames))
            return 20.0 * log10(1.0 / rms)
        }()

        var outL = inL
        var outR = inR
        outL.withUnsafeMutableBufferPointer { lPtr in
            outR.withUnsafeMutableBufferPointer { rPtr in
                proc.processPlanarFloat32(
                    left: lPtr.baseAddress!,
                    right: rPtr.baseAddress!,
                    frameCount: frames,
                    sampleRate: sr,
                    applyOutputHeadroom: true
                )
            }
        }

        var maxOut: Float = 0.0
        var sumSqOut: Double = 0.0
        let validSlice = 512..<frames
        for i in validSlice {
            maxOut = max(maxOut, abs(outL[i]))
            sumSqOut += Double(outL[i]) * Double(outL[i])
        }
        let rmsOut = sqrt(sumSqOut / Double(validSlice.count))
        let outCrestDB = 20.0 * log10(Double(maxOut) / rmsOut)

        XCTAssertLessThanOrEqual(maxOut, 0.995, "Passthrough Float32 output must never re-clip above 0 dBFS")
        // Note: A 1.45x continuous sine clipped at 1.0 has RMS ~0.840 (crest ~1.51 dB) vs pure sine crest 3.01 dB (theoretical max delta = +1.50 dB).
        XCTAssertGreaterThan(outCrestDB - inCrestDB, 1.30, "Restored continuous sine must recover > 86% of theoretical +1.50 dB crest delta")
    }

    // MARK: - 6. Weiss-Style Dynamic De-Esser: Bit-Exact Midrange & Level-Independent Sibilance Control

    func testWeissDeEsserBitExactMidrangeAndLevelIndependentSibilanceControl() {
        let sr = 48_000.0
        let frames = 4096

        // A. Pure 900 Hz vocal vowel / midrange tone -> must remain 100% bit-exact (0.0 dB GR)!
        let procVowel = MasteringRestorationProcessor()
        procVowel.configure(deClipMode: .off, deEsserMode: .vocal)
        var vowelOrig = (0..<frames).map { 0.45 * sin(2.0 * Double.pi * 900.0 * Double($0) / sr) }
        var vowelR = vowelOrig
        let expectedVowel = vowelOrig
        vowelOrig.withUnsafeMutableBufferPointer { lPtr in
            vowelR.withUnsafeMutableBufferPointer { rPtr in
                procVowel.processPlanarDouble(left: lPtr.baseAddress!, right: rPtr.baseAddress!, frameCount: frames, sampleRate: sr)
            }
        }
        for i in 0..<frames {
            XCTAssertEqual(vowelOrig[i], expectedVowel[i], accuracy: 0.0, "900 Hz vocal fundamental must pass bit-exact with 0.0 dB cut")
        }

        // B. Harsh 6.5 kHz sibilant burst at LOUD level (-3 dBFS) vs QUIET whisper level (-26 dBFS)
        func measureSibilantAttenuationDB(amplitude: Double) -> Double {
            let proc = MasteringRestorationProcessor()
            proc.configure(deClipMode: .off, deEsserMode: .vocal)
            var bufL = (0..<frames).map { amplitude * sin(2.0 * Double.pi * 6500.0 * Double($0) / sr) }
            var bufR = bufL
            bufL.withUnsafeMutableBufferPointer { lPtr in
                bufR.withUnsafeMutableBufferPointer { rPtr in
                    proc.processPlanarDouble(left: lPtr.baseAddress!, right: rPtr.baseAddress!, frameCount: frames, sampleRate: sr)
                }
            }
            let tail = (frames - 1024)..<frames
            let rmsOut = sqrt(tail.reduce(0.0) { $0 + bufL[$1] * bufL[$1] } / Double(tail.count))
            let rmsIn = amplitude / sqrt(2.0)
            return 20.0 * log10(rmsOut / rmsIn)
        }

        let loudAttenDB = measureSibilantAttenuationDB(amplitude: 0.707)   // -3 dBFS
        let quietAttenDB = measureSibilantAttenuationDB(amplitude: 0.050)  // -26 dBFS

        XCTAssertLessThan(loudAttenDB, -3.5, "Harsh 6.5 kHz sibilance at -3 dBFS should be attenuated by > 3.5 dB")
        XCTAssertLessThan(quietAttenDB, -3.5, "Harsh 6.5 kHz sibilance at -26 dBFS whisper should ALSO be attenuated by > 3.5 dB")
        XCTAssertEqual(loudAttenDB, quietAttenDB, accuracy: 0.6, "Weiss relative threshold must behave identically across 23 dB level difference")
    }

    // MARK: - 7. Two-Way iCloud Drive LWW Sync

    func testCloudSyncTwoWayLWWMergeForMasteringRestoration() throws {
        let syncFile = tempDir.appendingPathComponent("amr_cloud_sync_v1.json")
        let dspA = DSPPresetManager()
        let dspB = DSPPresetManager()
        let mrA = MasteringRestorationService(userDefaults: defaultsA, suiteKeyPrefix: "test.syncA.mr", isIsolated: true)
        let mrB = MasteringRestorationService(userDefaults: defaultsB, suiteKeyPrefix: "test.syncB.mr", isIsolated: true)

        mrA.updateModes(deClipMode: .studio, deEsserMode: .gentle, notifyCloudSync: false)

        let sum1 = try CloudSettingsSyncService.performTwoWaySync(
            fileURL: syncFile,
            dspManager: dspA,
            soundCheckService: AppleSoundCheckService.shared,
            spectralAnalyzer: SpectralIntegrityAnalyzer.shared,
            normPolicyProvider: { nil },
            normPolicyMerger: { _ in false },
            masteringService: mrA
        )
        XCTAssertTrue(sum1.wroteRemoteUpdate)

        let sum2 = try CloudSettingsSyncService.performTwoWaySync(
            fileURL: syncFile,
            dspManager: dspB,
            soundCheckService: AppleSoundCheckService.shared,
            spectralAnalyzer: SpectralIntegrityAnalyzer.shared,
            normPolicyProvider: { nil },
            normPolicyMerger: { _ in false },
            masteringService: mrB
        )
        XCTAssertTrue(sum2.masteringRestorationChanged)
        XCTAssertEqual(mrB.deClipMode, .studio)
        XCTAssertEqual(mrB.deEsserMode, .gentle)
    }

    // MARK: - 8. Post-Filter Loudness & Crest Compression Normalization Sync

    func testPostFilterLoudnessAndCrestNormalizationPreventsDoubleBoostAndRestoresDigitalPad() {
        // Brickwall DR5 Loudness War track: raw SoundCheck = -10.0 dB, raw Crest = 5.0 dB
        // 1. De-Clipper OFF: Crest deficit = 10.5 - 5.0 = 5.5 dB -> +2.475 dB Crest lift -> -7.525 dB
        let gainOff = ExternalAmpTCPController.computeEffectiveSoundCheckGainDb(
            rawGainDb: -10.0,
            compressionCompensation: true,
            crestFactorDb: 5.0,
            digitalSoundCheckAlreadyActive: false,
            postFilterRestoredPeakDb: 0.0,
            postFilterDigitalPadDb: 0.0
        )!
        XCTAssertEqual(gainOff, -7.525, accuracy: 0.01)

        // 2. De-Clipper ON (Auto: -3.6 dB digital pad, +3.0 dB restored peaks -> post-filter Crest = 8.0 dB):
        //    - Post-filter Crest deficit drops from 5.5 dB to 2.5 dB (+1.125 dB instead of +2.475 dB -> NO double boost!)
        //    - Digital -3.6 dB pad is compensated (+3.6 dB) in analog amp domain so perceived LUFS stays 1:1 matched!
        let gainPostDeClip = ExternalAmpTCPController.computeEffectiveSoundCheckGainDb(
            rawGainDb: -10.0,
            compressionCompensation: true,
            crestFactorDb: 5.0,
            digitalSoundCheckAlreadyActive: false,
            postFilterRestoredPeakDb: 3.0,
            postFilterDigitalPadDb: -3.6
        )!
        // Expected: (-10.0 + 1.125) + 3.6 = -5.275 dB in analog; combined with -3.6 dB digital pad = -8.875 dB RMS + +3.0 dB real peaks!
        XCTAssertEqual(gainPostDeClip, -5.275, accuracy: 0.01)
        let netRoomRmsWithDeClip = gainPostDeClip + (-3.6)
        XCTAssertLessThan(netRoomRmsWithDeClip, gainOff, "Post-filter RMS must not double-boost loudness once real peaks are restored")

        // 3. Clean DR14 master in Auto mode (autoBypass -> 0.0 dB pad, 0.0 dB restored peaks) -> 0.0 dB shift!
        let cleanGain = ExternalAmpTCPController.computeEffectiveSoundCheckGainDb(
            rawGainDb: -1.8,
            compressionCompensation: true,
            crestFactorDb: 14.0,
            digitalSoundCheckAlreadyActive: false,
            postFilterRestoredPeakDb: 0.0,
            postFilterDigitalPadDb: 0.0
        )!
        XCTAssertEqual(cleanGain, -1.8, accuracy: 0.001)
    }
}
