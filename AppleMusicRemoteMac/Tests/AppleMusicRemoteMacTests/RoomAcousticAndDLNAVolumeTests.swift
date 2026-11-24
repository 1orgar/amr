//
//  RoomAcousticAndDLNAVolumeTests.swift
//  AppleMusicRemoteMacTests
//
//  Unit tests for Quick Room Acoustic Measurement (vDSP Welch FFT + 64-bit Auto-PEQ),
//  Cloud Sync of Room Acoustic Profiles, and Per-Device Room Measurement Permissions.
//

import XCTest
@testable import AppleMusicRemoteMac

final class RoomAcousticAndDLNAVolumeTests: XCTestCase {

    private var tempDir: URL!
    private var suiteNameA: String!
    private var suiteNameB: String!
    private var defaultsA: UserDefaults!
    private var defaultsB: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("amr-room-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        suiteNameA = "com.amr.tests.roomA.\(UUID().uuidString)"
        suiteNameB = "com.amr.tests.roomB.\(UUID().uuidString)"
        defaultsA = UserDefaults(suiteName: suiteNameA)
        defaultsB = UserDefaults(suiteName: suiteNameB)
    }

    override func tearDownWithError() throws {
        if let suiteNameA {
            defaultsA?.removePersistentDomain(forName: suiteNameA)
        }
        if let suiteNameB {
            defaultsB?.removePersistentDomain(forName: suiteNameB)
        }
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testRoomAcousticThirdOctaveAutoPEQAnd64BitProcessorAttenuatesRoomPeak() throws {
        let roomService = RoomAcousticService(userDefaults: defaultsA, isIsolatedInstance: true)

        // Simulate flat in-room curve except a +10.5 dB standing-wave room mode around 80 Hz (index 6)
        var measuredBands = [Double](repeating: 0.0, count: RoomAcousticService.isoThirdOctaveBandsHz.count)
        measuredBands[5] = 4.5  // 63 Hz
        measuredBands[6] = 10.5 // 80 Hz room resonance
        measuredBands[7] = 4.5  // 100 Hz

        let profile = try XCTUnwrap(
            roomService.createProfileFromThirdOctaveBands(
                rawBandsDB: measuredBands,
                profileName: "Гостиная iPad Pro",
                deviceName: "iPad Pro",
                applyMEMSMicCompensation: false,
                autoSaveAndEnable: true
            )
        )

        XCTAssertTrue(roomService.isCorrectionEnabled)
        XCTAssertEqual(roomService.activeProfile?.id, profile.id)
        XCTAssertFalse(profile.eqBands.isEmpty)

        // Expect a cutting filter near 63..100 Hz with negative gain
        let bassCutBand = profile.eqBands.first {
            $0.frequencyHz >= 55.0 && $0.frequencyHz <= 110.0 && $0.gainDB < -2.0
        }
        XCTAssertNotNil(bassCutBand, "Expected Auto-PEQ to synthesize a bass room-mode cut around 80 Hz")

        // Verify real-time 64-bit RoomEQProcessor attenuates an 80 Hz sine wave more than a 1 kHz sine wave
        let processor = roomService.dspEngineProcessor
        let sampleRate = 48_000
        let frameCount = 4_096

        var left80 = [Double](repeating: 0.0, count: frameCount)
        var right80 = [Double](repeating: 0.0, count: frameCount)
        for n in 0..<frameCount {
            let s = 0.5 * sin(2.0 * Double.pi * 80.0 * Double(n) / Double(sampleRate))
            left80[n] = s
            right80[n] = s
        }
        left80.withUnsafeMutableBufferPointer { lBuf in
            right80.withUnsafeMutableBufferPointer { rBuf in
                processor.processPlanarDouble(
                    left: lBuf.baseAddress!,
                    right: rBuf.baseAddress!,
                    frameCount: frameCount,
                    sampleRate: sampleRate
                )
            }
        }
        let tailStart = frameCount / 2
        let rms80Out = sqrt(left80[tailStart...].reduce(0.0) { $0 + $1 * $1 } / Double(frameCount - tailStart))

        var left1k = [Double](repeating: 0.0, count: frameCount)
        var right1k = [Double](repeating: 0.0, count: frameCount)
        for n in 0..<frameCount {
            let s = 0.5 * sin(2.0 * Double.pi * 1_000.0 * Double(n) / Double(sampleRate))
            left1k[n] = s
            right1k[n] = s
        }
        left1k.withUnsafeMutableBufferPointer { lBuf in
            right1k.withUnsafeMutableBufferPointer { rBuf in
                processor.processPlanarDouble(
                    left: lBuf.baseAddress!,
                    right: rBuf.baseAddress!,
                    frameCount: frameCount,
                    sampleRate: sampleRate
                )
            }
        }
        let rms1kOut = sqrt(left1k[tailStart...].reduce(0.0) { $0 + $1 * $1 } / Double(frameCount - tailStart))

        XCTAssertLessThan(rms80Out, rms1kOut * 0.82, "80 Hz room mode should be significantly attenuated compared to 1 kHz reference")
    }

    func testWelchFFTAnalyzePCMMonoSamplesDetectsResonance() throws {
        let roomService = RoomAcousticService(userDefaults: defaultsA, isIsolatedInstance: true)
        let sampleRate = 48_000.0
        let totalSamples = 96_000 // 2 seconds at 48 kHz

        // Generate deterministic pink-weighted noise + strong 125 Hz room mode peak
        var samples = [Float](repeating: 0.0, count: totalSamples)
        var rng: UInt64 = 0x1234_5678_9ABC_DEF0
        var b0 = 0.0, b1 = 0.0, b2 = 0.0
        for i in 0..<totalSamples {
            rng ^= rng >> 12
            rng ^= rng << 25
            rng ^= rng >> 27
            let u = Double((rng &* 0x2545_F491_4F6C_DD1D) >> 11) * (1.0 / 9_007_199_254_740_992.0)
            let white = u * 2.0 - 1.0
            b0 = 0.99765 * b0 + white * 0.0990460
            b1 = 0.96300 * b1 + white * 0.2965164
            b2 = 0.57000 * b2 + white * 1.0526913
            let pink = (b0 + b1 + b2 + white * 0.1848) * 0.04
            let mode125 = 0.18 * sin(2.0 * Double.pi * 125.0 * Double(i) / sampleRate)
            samples[i] = Float(pink + mode125)
        }

        let profile = try roomService.analyzePCMMonoSamples(
            samples,
            sampleRate: sampleRate,
            profileName: "Замер iPhone 16 Pro",
            deviceName: "iPhone 16 Pro",
            applyMEMSMicCompensation: true,
            autoSaveAndEnable: true
        )

        XCTAssertEqual(profile.measuredResponseDB.count, 31)
        let cutNear125 = profile.eqBands.contains {
            $0.frequencyHz >= 95.0 && $0.frequencyHz <= 165.0 && $0.gainDB < -2.0
        }
        XCTAssertTrue(cutNear125, "Welch vDSP FFT analyzer should detect and cut the 125 Hz resonant peak")
    }

    func testCloudTwoWaySyncForRoomAcousticProfilesAndTombstones() throws {
        let cloudFileURL = tempDir
            .appendingPathComponent("CloudRoomSync", isDirectory: true)
            .appendingPathComponent(CloudSettingsSyncService.cloudFileName, isDirectory: false)

        let dspA = DSPPresetManager(loadFromDefaults: false)
        let scA = AppleSoundCheckService(customCacheFileURL: tempDir.appendingPathComponent("sc_ra.json"))
        let specA = SpectralIntegrityAnalyzer(customCacheFileURL: tempDir.appendingPathComponent("spec_ra.json"))
        let roomA = RoomAcousticService(userDefaults: defaultsA, isIsolatedInstance: true)

        let dspB = DSPPresetManager(loadFromDefaults: false)
        let scB = AppleSoundCheckService(customCacheFileURL: tempDir.appendingPathComponent("sc_rb.json"))
        let specB = SpectralIntegrityAnalyzer(customCacheFileURL: tempDir.appendingPathComponent("spec_rb.json"))
        let roomB = RoomAcousticService(userDefaults: defaultsB, isIsolatedInstance: true)

        var bands = [Double](repeating: 0.0, count: 31)
        bands[6] = 8.5
        let createdOnA = try XCTUnwrap(
            roomA.createProfileFromThirdOctaveBands(
                rawBandsDB: bands,
                profileName: "Кабинет KEF",
                deviceName: "iPhone",
                autoSaveAndEnable: true
            )
        )

        // 1. Sync Mac A -> Cloud
        let sumA1 = try CloudSettingsSyncService.performTwoWaySync(
            fileURL: cloudFileURL,
            dspManager: dspA,
            soundCheckService: scA,
            spectralAnalyzer: specA,
            normPolicyProvider: { nil },
            normPolicyMerger: { _ in false },
            roomService: roomA
        )
        XCTAssertTrue(sumA1.wroteRemoteUpdate)
        XCTAssertEqual(sumA1.totalSyncedRoomProfiles, 1)

        // 2. Sync Cloud -> Mac B
        let sumB1 = try CloudSettingsSyncService.performTwoWaySync(
            fileURL: cloudFileURL,
            dspManager: dspB,
            soundCheckService: scB,
            spectralAnalyzer: specB,
            normPolicyProvider: { nil },
            normPolicyMerger: { _ in false },
            roomService: roomB
        )
        XCTAssertTrue(sumB1.roomProfilesChanged)
        XCTAssertFalse(sumB1.wroteRemoteUpdate)
        XCTAssertEqual(roomB.allProfiles().count, 1)
        XCTAssertEqual(roomB.activeProfile?.id, createdOnA.id)
        XCTAssertEqual(roomB.activeProfile?.name, "Кабинет KEF")
        XCTAssertTrue(roomB.isCorrectionEnabled)

        // 3. Delete profile on Mac B and sync tombstone back to Mac A
        XCTAssertTrue(roomB.deleteProfile(id: createdOnA.id))
        let sumB2 = try CloudSettingsSyncService.performTwoWaySync(
            fileURL: cloudFileURL,
            dspManager: dspB,
            soundCheckService: scB,
            spectralAnalyzer: specB,
            normPolicyProvider: { nil },
            normPolicyMerger: { _ in false },
            roomService: roomB
        )
        XCTAssertTrue(sumB2.wroteRemoteUpdate)
        XCTAssertEqual(sumB2.totalSyncedRoomProfiles, 0)

        let sumA2 = try CloudSettingsSyncService.performTwoWaySync(
            fileURL: cloudFileURL,
            dspManager: dspA,
            soundCheckService: scA,
            spectralAnalyzer: specA,
            normPolicyProvider: { nil },
            normPolicyMerger: { _ in false },
            roomService: roomA
        )
        XCTAssertTrue(sumA2.roomProfilesChanged)
        XCTAssertTrue(roomA.allProfiles().isEmpty)
        XCTAssertFalse(sumA2.wroteRemoteUpdate)
    }

    func testPerDeviceRoomMeasurementPermission() {
        let manager = ClientDeviceManager.shared
        let connId = UUID()
        let headlessConnId = UUID()
        let testDeviceId = "test-room-perm-\(UUID().uuidString.lowercased())"

        defer {
            manager.unregisterConnection(connectionId: connId)
            manager.removeDevice(deviceId: testDeviceId)
        }

        // Unbound headless connections remain allowed
        XCTAssertTrue(manager.canConnectionMeasureRoom(connectionId: headlessConnId))

        let record = manager.registerConnection(
            connectionId: connId,
            deviceId: testDeviceId,
            deviceName: "iPad Air Гостевой",
            deviceType: "tablet",
            preferredLockScreen: false,
            remoteIP: "192.168.1.120"
        )
        XCTAssertFalse(record.isAuthorized)
        XCTAssertTrue(record.allowRoomMeasurement)
        XCTAssertEqual(record.dictionary["allow_room_measurement"] as? Bool, true)
        // While pending authorization on Mac, room measurement must be blocked
        XCTAssertFalse(manager.canConnectionMeasureRoom(connectionId: connId))
        XCTAssertFalse(manager.canDeviceMeasureRoom(deviceId: testDeviceId))

        // Authorize device on Mac -> room measurement becomes allowed by default
        manager.setAuthorized(deviceId: testDeviceId, authorized: true)
        XCTAssertTrue(manager.canConnectionMeasureRoom(connectionId: connId))
        XCTAssertTrue(manager.canDeviceMeasureRoom(deviceId: testDeviceId))

        manager.setAllowRoomMeasurement(deviceId: testDeviceId, enabled: false)
        XCTAssertFalse(manager.canConnectionMeasureRoom(connectionId: connId))
        XCTAssertFalse(manager.canDeviceMeasureRoom(deviceId: testDeviceId))
        XCTAssertEqual(manager.getDevice(deviceId: testDeviceId)?.allowRoomMeasurement, false)

        manager.setAllowRoomMeasurement(deviceId: testDeviceId, enabled: true)
        XCTAssertTrue(manager.canConnectionMeasureRoom(connectionId: connId))
        XCTAssertTrue(manager.canDeviceMeasureRoom(deviceId: testDeviceId))
    }
}
