//
//  CloudSettingsSyncServiceTests.swift
//  AppleMusicRemoteMacTests
//
//  Unit tests for CloudSettingsSyncService (Two-Way Coordinated Cloud Sync of
//  Custom DSP Presets, SoundCheck Loudness Cache, Mastering Dynamics & Normalization Policy).
//

import XCTest
@testable import AppleMusicRemoteMac

final class CloudSettingsSyncServiceTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("amr-cloud-sync-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testTwoMacDSPPresetsLoudnessDynamicsAndNormalizationPolicySync() throws {
        let cloudFileURL = tempDir
            .appendingPathComponent("SharedCloudFolder", isDirectory: true)
            .appendingPathComponent(CloudSettingsSyncService.cloudFileName, isDirectory: false)

        // Mac A isolated stores
        let dspA = DSPPresetManager(loadFromDefaults: false)
        let soundCheckA = AppleSoundCheckService(customCacheFileURL: tempDir.appendingPathComponent("sc_a.json"))
        let spectralA = SpectralIntegrityAnalyzer(customCacheFileURL: tempDir.appendingPathComponent("spec_a.json"))
        var policyA = ExternalAmpTCPController.NormalizationPolicySyncState(
            soundCheckEnabled: true,
            lowVolumeSmartNormEnabled: true,
            compressionCompensationEnabled: true,
            updatedAt: 1_760_000_100
        )

        // Mac B isolated stores
        let dspB = DSPPresetManager(loadFromDefaults: false)
        let soundCheckB = AppleSoundCheckService(customCacheFileURL: tempDir.appendingPathComponent("sc_b.json"))
        let spectralB = SpectralIntegrityAnalyzer(customCacheFileURL: tempDir.appendingPathComponent("spec_b.json"))
        var policyB = ExternalAmpTCPController.NormalizationPolicySyncState(
            soundCheckEnabled: false,
            lowVolumeSmartNormEnabled: true,
            compressionCompensationEnabled: false,
            updatedAt: 0
        )

        // 1. Populate Mac A with a custom DSP preset (including hardware-local targetDeviceUID),
        //    portable + local SoundCheck keys, and a mastering dynamics entry.
        var cfgA = EngineConfiguration(mode: .sdmDoP)
        cfgA.dsdRate = .dsd256
        cfgA.profile = .superWide
        cfgA.clockPolicy = .strictSACD44k1
        cfgA.oversamplerBackend = .metalOverlapSave
        cfgA.phaseMode = .linearPhase
        cfgA.isiRegularizerEnabled = true
        cfgA.headroomDB = -3.5
        cfgA.ispProtectionEnabled = true
        cfgA.hogModeEnabled = true
        cfgA.targetDeviceUID = "SMSL-USB-LOCAL-MAC-A"
        let savedPresetA = dspA.saveCustomPreset(name: "Мои наушники планары", configuration: cfgA)

        // Stores canonicalKey + local trackId ("id:4135") + Apple Music catalogId ("id:1440857781"):
        // Cloud export must sync canonicalKey + catalogId, while filtering out machine-local "id:4135"!
        soundCheckA.storeGainInCache(
            -4.25,
            canonicalKey: "daft punk:giorgio by moroder",
            trackId: "4135",
            catalogId: "1440857781"
        )

        let validationA = CachedSpectralValidation(
            trackId: "1440857781",
            trackKey: "daft punk|giorgio by moroder",
            isLocal: false,
            verdict: "verified_hires",
            verdictTitle: "True Hi-Res",
            verdictDescription: "Verified",
            isAuthentic: true,
            sampleRate: 96000,
            claimedBitDepth: 24,
            effectiveBitDepth: 24,
            isZeroPadded: false,
            cutoffFrequencyHz: 42000,
            nyquistFrequencyHz: 48000,
            ultrasonicEnergyDb: -48.0,
            highBandEnergyDb: -24.0,
            dynamicRangeCrestDb: 14.8,
            analyzedFramesCount: 120,
            validatedAt: Date(timeIntervalSince1970: 1_760_000_050),
            ttDrScore: 13,
            integratedLufs: -12.4,
            loudnessRangeLu: 8.6,
            truePeakDbtp: -0.45
        )
        spectralA.storeValidationForTesting(validationA, isLossless: true)

        // Also store a strictly machine-local validation on Mac A -> local_id key must NOT leak to Mac B,
        // while portable track_key should still sync!
        let localTrackValidation = CachedSpectralValidation(
            trackId: "4135",
            trackKey: "kenshi yonezu|kick back",
            isLocal: true,
            verdict: "verified_lossless",
            verdictTitle: "True 24-Bit",
            verdictDescription: "Verified",
            isAuthentic: true,
            sampleRate: 48000,
            claimedBitDepth: 24,
            effectiveBitDepth: 24,
            isZeroPadded: false,
            cutoffFrequencyHz: 22100,
            nyquistFrequencyHz: 24000,
            ultrasonicEnergyDb: -70.0,
            highBandEnergyDb: -18.0,
            dynamicRangeCrestDb: 7.4,
            analyzedFramesCount: 95,
            validatedAt: Date(timeIntervalSince1970: 1_760_000_060),
            ttDrScore: 7,
            integratedLufs: -6.8,
            loudnessRangeLu: 4.1,
            truePeakDbtp: 0.32
        )
        spectralA.storeValidationForTesting(localTrackValidation, isLossless: true)

        // 2. Sync Mac A -> Cloud
        let summaryA1 = try CloudSettingsSyncService.performTwoWaySync(
            fileURL: cloudFileURL,
            dspManager: dspA,
            soundCheckService: soundCheckA,
            spectralAnalyzer: spectralA,
            normPolicyProvider: { policyA },
            normPolicyMerger: { incoming in
                guard incoming.updatedAt > policyA.updatedAt else { return false }
                policyA = incoming
                return true
            }
        )
        XCTAssertTrue(summaryA1.wroteRemoteUpdate)
        XCTAssertEqual(summaryA1.totalSyncedPresets, 1)
        XCTAssertEqual(summaryA1.totalSyncedLoudnessTracks, 2) // id:4135 filtered out!

        // 3. Sync Cloud -> Mac B
        let summaryB1 = try CloudSettingsSyncService.performTwoWaySync(
            fileURL: cloudFileURL,
            dspManager: dspB,
            soundCheckService: soundCheckB,
            spectralAnalyzer: spectralB,
            normPolicyProvider: { policyB },
            normPolicyMerger: { incoming in
                guard incoming.updatedAt > policyB.updatedAt else { return false }
                policyB = incoming
                return true
            }
        )
        XCTAssertTrue(summaryB1.dspPresetsChanged)
        XCTAssertEqual(summaryB1.mergedLoudnessCount, 2)
        XCTAssertTrue(summaryB1.normalizationPolicyChanged)
        // Because Mac B is now 100% semantically identical to Cloud, Mac B must NOT re-write the file!
        XCTAssertFalse(summaryB1.wroteRemoteUpdate)

        // Verify Mac B received preset WITHOUT Mac A's hardware-specific targetDeviceUID
        let syncedPresetOnB = try XCTUnwrap(dspB.preset(withID: savedPresetA.id))
        XCTAssertEqual(syncedPresetOnB.name, "Мои наушники планары")
        XCTAssertNil(syncedPresetOnB.configuration.targetDeviceUID)
        XCTAssertEqual(syncedPresetOnB.configuration.headroomDB, -3.5, accuracy: 0.01)

        // Verify Mac B received portable loudness entries, and did NOT receive local id:4135
        let exportedLoudnessB = soundCheckB.exportCloudSyncLoudnessEntries()
        XCTAssertEqual(exportedLoudnessB["daft punk:giorgio by moroder"] ?? 0, -4.25, accuracy: 0.001)
        XCTAssertEqual(exportedLoudnessB["id:1440857781"] ?? 0, -4.25, accuracy: 0.001)
        XCTAssertNil(exportedLoudnessB["id:4135"])

        // Verify Mac B received mastering dynamics (DR7 & DR13) without local_id:4135
        let exportedDynB = spectralB.exportCloudSyncValidations()
        XCTAssertNil(exportedDynB.keys.first(where: { $0.hasPrefix("local_id:") }))
        let daftPunkDyn = try XCTUnwrap(exportedDynB["cloud_id:1440857781:96000:24:1"])
        XCTAssertEqual(daftPunkDyn.ttDrScore, 13)
        let kickBackDyn = try XCTUnwrap(exportedDynB["track_key:kenshi yonezu|kick back:48000:24:1"])
        XCTAssertEqual(kickBackDyn.ttDrScore, 7)
        XCTAssertEqual(kickBackDyn.integratedLufs ?? 0, -6.8, accuracy: 0.01)
        XCTAssertEqual(kickBackDyn.truePeakDbtp ?? 0, 0.32, accuracy: 0.01)

        // Verify Mac B adopted Mac A's newer normalization policy
        XCTAssertEqual(policyB, policyA)

        // 4. Modify preset on Mac B & add a second preset, then delete original preset on Mac B -> verify tombstone syncs to Mac A
        cfgA.mode = .hqNOSPCM
        cfgA.nosDitherMode = .lns15
        let r2rPresetB = dspB.saveCustomPreset(name: "R2R Гостиная", configuration: cfgA)
        XCTAssertTrue(dspB.deleteCustomPreset(id: savedPresetA.id))

        let summaryB2 = try CloudSettingsSyncService.performTwoWaySync(
            fileURL: cloudFileURL,
            dspManager: dspB,
            soundCheckService: soundCheckB,
            spectralAnalyzer: spectralB,
            normPolicyProvider: { policyB },
            normPolicyMerger: { _ in false }
        )
        XCTAssertTrue(summaryB2.wroteRemoteUpdate)

        let summaryA2 = try CloudSettingsSyncService.performTwoWaySync(
            fileURL: cloudFileURL,
            dspManager: dspA,
            soundCheckService: soundCheckA,
            spectralAnalyzer: spectralA,
            normPolicyProvider: { policyA },
            normPolicyMerger: { _ in false }
        )
        XCTAssertTrue(summaryA2.dspPresetsChanged)
        XCTAssertNil(dspA.preset(withID: savedPresetA.id))
        XCTAssertNotNil(dspA.preset(withID: r2rPresetB.id))
        XCTAssertFalse(summaryA2.wroteRemoteUpdate)
    }

    func testEvictedICloudPlaceholderPreventsPrematureOverwrite() throws {
        let syncFolder = tempDir.appendingPathComponent("ICloudMock", isDirectory: true)
        try FileManager.default.createDirectory(at: syncFolder, withIntermediateDirectories: true)

        let cloudFileURL = syncFolder.appendingPathComponent(CloudSettingsSyncService.cloudFileName)
        let placeholderURL = syncFolder.appendingPathComponent(".\(CloudSettingsSyncService.cloudFileName).icloud")
        try Data("placeholder".utf8).write(to: placeholderURL)

        let dsp = DSPPresetManager(loadFromDefaults: false)
        let sc = AppleSoundCheckService(customCacheFileURL: tempDir.appendingPathComponent("sc_p.json"))
        let spec = SpectralIntegrityAnalyzer(customCacheFileURL: tempDir.appendingPathComponent("spec_p.json"))

        XCTAssertThrowsError(
            try CloudSettingsSyncService.performTwoWaySync(
                fileURL: cloudFileURL,
                dspManager: dsp,
                soundCheckService: sc,
                spectralAnalyzer: spec,
                normPolicyProvider: { nil },
                normPolicyMerger: { _ in false }
            )
        ) { error in
            guard case CloudSyncError.waitingForICloudDownload = error else {
                XCTFail("Expected waitingForICloudDownload, got \(error)")
                return
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloudFileURL.path))
    }
}
