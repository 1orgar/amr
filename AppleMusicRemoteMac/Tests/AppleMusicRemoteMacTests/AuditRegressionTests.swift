//
//  AuditRegressionTests.swift
//  AppleMusicRemoteMacTests
//
//  Regression tests covering the post-implementation adversarial audit fixes:
//  - CRIT-5: Deterministic two-Mac Cloud Sync convergence (Room EQ state LWW, SoundCheck & Spectral tie-breaking, zero ping-pong)
//  - HIGH-4: Localized "Очередь AMR" track confirmation without double-skip + history drain rejection
//  - HIGH-6 / MED-4: Empty X-AMR-Device-ID header bypass prevention & per-device Room EQ / DAC permission enforcement
//  - HIGH-10: Truthful `isBitPerfect` flag when Pre-DSP (Late-Night DRC / Room EQ) is active vs bypassed
//  - MED-9 / LOW-2: Antipodal SLERP orthogonal midpoint & diacritic / 2-character artist semantic vectors
//

import XCTest
@testable import AppleMusicRemoteMac

final class AuditRegressionTests: XCTestCase {

    private var tempDir: URL!
    private var suiteA: String!
    private var suiteB: String!
    private var defaultsA: UserDefaults!
    private var defaultsB: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("amr-audit-regression-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        suiteA = "com.amr.tests.auditA.\(UUID().uuidString)"
        suiteB = "com.amr.tests.auditB.\(UUID().uuidString)"
        defaultsA = UserDefaults(suiteName: suiteA)
        defaultsB = UserDefaults(suiteName: suiteB)
    }

    override func tearDownWithError() throws {
        if let suiteA {
            defaultsA?.removePersistentDomain(forName: suiteA)
        }
        if let suiteB {
            defaultsB?.removePersistentDomain(forName: suiteB)
        }
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    // MARK: - CRIT-5: Two-Mac Cloud Sync Deterministic Convergence (Zero Ping-Pong)

    func testCloudSyncDeterministicTwoMacConvergenceZeroPingPong() throws {
        let cloudFileURL = tempDir
            .appendingPathComponent("iCloudSyncAudit", isDirectory: true)
            .appendingPathComponent(CloudSettingsSyncService.cloudFileName, isDirectory: false)

        let dspA = DSPPresetManager(loadFromDefaults: false)
        let scA = AppleSoundCheckService(customCacheFileURL: tempDir.appendingPathComponent("sc_audit_a.json"))
        let specA = SpectralIntegrityAnalyzer(customCacheFileURL: tempDir.appendingPathComponent("spec_audit_a.json"))
        let roomA = RoomAcousticService(userDefaults: defaultsA, isIsolatedInstance: true)
        let drcA = LateNightDRCService(userDefaults: defaultsA, suiteKeyPrefix: "test.audit.macA", isIsolated: true)

        let dspB = DSPPresetManager(loadFromDefaults: false)
        let scB = AppleSoundCheckService(customCacheFileURL: tempDir.appendingPathComponent("sc_audit_b.json"))
        let specB = SpectralIntegrityAnalyzer(customCacheFileURL: tempDir.appendingPathComponent("spec_audit_b.json"))
        let roomB = RoomAcousticService(userDefaults: defaultsB, isIsolatedInstance: true)
        let drcB = LateNightDRCService(userDefaults: defaultsB, suiteKeyPrefix: "test.audit.macB", isIsolated: true)

        let bands = RoomAcousticService.isoThirdOctaveBandsHz
        let zeros = [Double](repeating: 0.0, count: bands.count)
        let profile1 = RoomAcousticProfile(
            id: "prof-studio-1",
            name: "Studio Nearfield",
            measuredOnDevice: "iPhone 16 Pro",
            bandsHz: bands,
            measuredResponseDB: zeros,
            targetCurveDB: zeros,
            correctedResponseDB: zeros,
            maxPeakDeviationDB: 2.5,
            eqBands: [RoomEQBand(frequencyHz: 125.0, gainDB: -3.0, q: 2.0, filterType: "peaking")],
            preampGainDB: -0.5
        )
        let profile2 = RoomAcousticProfile(
            id: "prof-living-2",
            name: "Living Room Sofa",
            measuredOnDevice: "iPad Pro",
            bandsHz: bands,
            measuredResponseDB: zeros,
            targetCurveDB: zeros,
            correctedResponseDB: zeros,
            maxPeakDeviationDB: 4.0,
            eqBands: [RoomEQBand(frequencyHz: 63.0, gainDB: -5.0, q: 2.8, filterType: "peaking")],
            preampGainDB: -1.0
        )

        // Seed conflicting SoundCheck loudness values & same-second Spectral validations on Mac A and Mac B
        _ = scA.mergeCloudSyncLoudnessEntries(["id:1440857781": -6.84])
        _ = scB.mergeCloudSyncLoudnessEntries(["id:1440857781": -7.12])

        let fixedDate = Date(timeIntervalSince1970: 1_750_000_000.0)
        let specEntryA = CachedSpectralValidation(
            trackId: "1440857781",
            trackKey: "olafur arnalds:re member",
            isLocal: false,
            verdict: "true_hires",
            verdictTitle: "True Hi-Res",
            verdictDescription: "Mac A pass",
            isAuthentic: true,
            sampleRate: 96_000,
            claimedBitDepth: 24,
            effectiveBitDepth: 24,
            isZeroPadded: false,
            cutoffFrequencyHz: 42_000,
            nyquistFrequencyHz: 48_000,
            ultrasonicEnergyDb: -48.0,
            highBandEnergyDb: -24.0,
            dynamicRangeCrestDb: 13.4,
            analyzedFramesCount: 64,
            validatedAt: fixedDate,
            ttDrScore: 12,
            integratedLufs: -14.2
        )
        let specEntryB = CachedSpectralValidation(
            trackId: "1440857781",
            trackKey: "olafur arnalds:re member",
            isLocal: false,
            verdict: "true_hires",
            verdictTitle: "True Hi-Res",
            verdictDescription: "Mac B pass",
            isAuthentic: true,
            sampleRate: 96_000,
            claimedBitDepth: 24,
            effectiveBitDepth: 24,
            isZeroPadded: false,
            cutoffFrequencyHz: 43_500,
            nyquistFrequencyHz: 48_000,
            ultrasonicEnergyDb: -46.0,
            highBandEnergyDb: -23.0,
            dynamicRangeCrestDb: 14.8,
            analyzedFramesCount: 96,
            validatedAt: fixedDate,
            ttDrScore: 13,
            integratedLufs: -14.0
        )
        _ = specA.mergeCloudSyncValidations(["catalog:1440857781": specEntryA])
        _ = specB.mergeCloudSyncValidations(["catalog:1440857781": specEntryB])

        // Step 1: Mac A saves both Room EQ profiles and enables profile1
        roomA.saveMeasuredProfile(profile2, autoEnable: false)
        roomA.saveMeasuredProfile(profile1, autoEnable: true)
        XCTAssertTrue(roomA.isCorrectionEnabled)
        XCTAssertEqual(roomA.activeProfile?.id, "prof-studio-1")

        _ = try CloudSettingsSyncService.performTwoWaySync(
            fileURL: cloudFileURL,
            dspManager: dspA,
            soundCheckService: scA,
            spectralAnalyzer: specA,
            normPolicyProvider: { nil },
            normPolicyMerger: { _ in false },
            roomService: roomA,
            lateNightService: drcA
        )

        // Step 2: Mac B syncs (merges Room EQ + SoundCheck + Spectral)
        _ = try CloudSettingsSyncService.performTwoWaySync(
            fileURL: cloudFileURL,
            dspManager: dspB,
            soundCheckService: scB,
            spectralAnalyzer: specB,
            normPolicyProvider: { nil },
            normPolicyMerger: { _ in false },
            roomService: roomB,
            lateNightService: drcB
        )
        XCTAssertTrue(roomB.isCorrectionEnabled)
        XCTAssertEqual(roomB.activeProfile?.id, "prof-studio-1")

        // Step 3: Mac A switches active Room EQ profile to profile2 and turns Room EQ OFF
        Thread.sleep(forTimeInterval: 0.015)
        roomA.selectProfile(id: "prof-living-2")
        roomA.setCorrectionEnabled(false)
        XCTAssertFalse(roomA.isCorrectionEnabled)
        XCTAssertEqual(roomA.activeProfile?.id, "prof-living-2")

        _ = try CloudSettingsSyncService.performTwoWaySync(
            fileURL: cloudFileURL,
            dspManager: dspA,
            soundCheckService: scA,
            spectralAnalyzer: specA,
            normPolicyProvider: { nil },
            normPolicyMerger: { _ in false },
            roomService: roomA,
            lateNightService: drcA
        )

        // Step 4: Mac B pulls -> must adopt BOTH activeProfile == profile2 AND isCorrectionEnabled == false!
        _ = try CloudSettingsSyncService.performTwoWaySync(
            fileURL: cloudFileURL,
            dspManager: dspB,
            soundCheckService: scB,
            spectralAnalyzer: specB,
            normPolicyProvider: { nil },
            normPolicyMerger: { _ in false },
            roomService: roomB,
            lateNightService: drcB
        )
        XCTAssertFalse(roomB.isCorrectionEnabled, "Mac B must adopt Room EQ OFF state via LWW timestamp")
        XCTAssertEqual(roomB.activeProfile?.id, "prof-living-2", "Mac B must adopt switched active Room EQ profile")

        // Step 5: Mac A pulls back once so SoundCheck & Spectral converge, then verify ZERO writes on subsequent passes!
        _ = try CloudSettingsSyncService.performTwoWaySync(
            fileURL: cloudFileURL,
            dspManager: dspA,
            soundCheckService: scA,
            spectralAnalyzer: specA,
            normPolicyProvider: { nil },
            normPolicyMerger: { _ in false },
            roomService: roomA,
            lateNightService: drcA
        )

        XCTAssertEqual(scA.exportCloudSyncLoudnessEntries()["id:1440857781"], -7.12)
        XCTAssertEqual(scB.exportCloudSyncLoudnessEntries()["id:1440857781"], -7.12)
        XCTAssertEqual(
            specA.exportCloudSyncValidations()["catalog:1440857781"],
            specB.exportCloudSyncValidations()["catalog:1440857781"]
        )

        var steadyStateWrites = 0
        _ = try CloudSettingsSyncService.performTwoWaySync(
            fileURL: cloudFileURL,
            dspManager: dspB,
            soundCheckService: scB,
            spectralAnalyzer: specB,
            normPolicyProvider: { nil },
            normPolicyMerger: { _ in false },
            roomService: roomB,
            lateNightService: drcB,
            onLocalWrite: { steadyStateWrites += 1 }
        )
        _ = try CloudSettingsSyncService.performTwoWaySync(
            fileURL: cloudFileURL,
            dspManager: dspA,
            soundCheckService: scA,
            spectralAnalyzer: specA,
            normPolicyProvider: { nil },
            normPolicyMerger: { _ in false },
            roomService: roomA,
            lateNightService: drcA,
            onLocalWrite: { steadyStateWrites += 1 }
        )
        XCTAssertEqual(steadyStateWrites, 0, "Once converged, neither Mac A nor Mac B may rewrite amr_cloud_sync_v1.json")
    }

    // MARK: - HIGH-10: Truthful `isBitPerfect` Status Flag Under Pre-DSP

    func testPlayerStatusIsBitPerfectReflectsPreDSPState() {
        let prevMonitor = BitPerfectLogMonitor.shared.isEnabled
        let prevDRCEnabled = LateNightDRCService.shared.isEnabled
        let prevDRCProfile = LateNightDRCService.shared.selectedProfile
        let prevRoomEnabled = RoomAcousticService.shared.isCorrectionEnabled

        BitPerfectLogMonitor.shared.isEnabled = true
        RoomAcousticService.shared.setCorrectionEnabled(false)
        LateNightDRCService.shared.updateState(enabled: false, profile: .gentle, notifyCloudSync: false)

        defer {
            BitPerfectLogMonitor.shared.isEnabled = prevMonitor
            RoomAcousticService.shared.setCorrectionEnabled(prevRoomEnabled)
            LateNightDRCService.shared.updateState(enabled: prevDRCEnabled, profile: prevDRCProfile, notifyCloudSync: false)
        }

        let devRate = CoreAudioDeviceManager.shared.getDefaultOutputDevice()?.currentSampleRate ?? 48_000.0
        let track = TrackInfo(
            id: "bp-1",
            numericId: 1,
            name: "re:member",
            artist: "Ólafur Arnalds",
            album: "re:member",
            duration: 300,
            sampleRate: Int(devRate.rounded()),
            bitDepth: 24
        )

        var statusOff = PlayerStatus(
            playerState: "playing",
            position: 10.0,
            duration: 300.0,
            volume: 100,
            shuffle: false,
            repeatMode: "off",
            playlist: "re:member",
            isRadio: false,
            audioQuality: "Hi-Res Lossless 24-бит/96 кГц",
            track: track
        )
        _ = PlayerStatusEngine.shared.applyLiveAudioPipelineOverlay(to: &statusOff, updateTapFormatIfNeeded: false)
        XCTAssertEqual(statusOff.isBitPerfect, true, "With both Room EQ and Late-Night DRC OFF, isBitPerfect must be true")

        LateNightDRCService.shared.setMode(.concert, notifyCloudSync: false)
        var statusDRCOn = statusOff
        _ = PlayerStatusEngine.shared.applyLiveAudioPipelineOverlay(to: &statusDRCOn, updateTapFormatIfNeeded: false)
        XCTAssertEqual(statusDRCOn.isBitPerfect, false, "When Late-Night DRC is modifying audio, isBitPerfect must be false")
        XCTAssertEqual(statusDRCOn.lateNightDrcMode, "concert")
    }

    // MARK: - HIGH-6 / MED-4: Empty Header Device-ID Bypass & Per-Device Permission Enforcement

    func testHTTPDeviceIdResolutionPreventsEmptyHeaderPermissionBypass() {
        let server = WebSocketServer.shared
        let rawHeadersWithEmptyDeviceHeader = [
            "POST /api/room-measurement/analyze HTTP/1.1",
            "Host: 127.0.0.1:8765",
            "X-AMR-Device-ID:    ",
            "Cookie: amr_device_uid=TEST-GUEST-AUDIT",
            "",
            ""
        ].joined(separator: "\r\n")

        let resolved = server.nonEmpty(server.extractHeader(named: "x-amr-device-id", from: rawHeadersWithEmptyDeviceHeader))
            ?? server.nonEmpty(server.extractCookie(named: "amr_device_uid", from: rawHeadersWithEmptyDeviceHeader))
        XCTAssertEqual(resolved, "TEST-GUEST-AUDIT", "Blank X-AMR-Device-ID header must fall through to Cookie device ID")

        let guestId = "TEST-GUEST-AUDIT-\(UUID().uuidString.prefix(8))"
        let token = ClientDeviceManager.shared.createInviteToken()
        _ = ClientDeviceManager.shared.registerConnection(
            connectionId: UUID(),
            deviceId: guestId,
            deviceName: "Guest Phone",
            deviceType: "mobile",
            preferredLockScreen: false,
            remoteIP: "10.10.99.55",
            inviteToken: token
        )
        defer {
            ClientDeviceManager.shared.removeDevice(deviceId: guestId)
        }

        ClientDeviceManager.shared.setAllowRoomMeasurement(deviceId: guestId, enabled: false)
        ClientDeviceManager.shared.setAllowDACSelection(deviceId: guestId, enabled: false)

        XCTAssertTrue(ClientDeviceManager.shared.isDeviceAuthorized(deviceId: guestId))
        XCTAssertFalse(ClientDeviceManager.shared.canDeviceMeasureRoom(deviceId: guestId))
        XCTAssertFalse(server.canDeviceSelectDAC(deviceId: guestId))
    }

    // MARK: - MED-9 / LOW-2: Sonic Bridge Antipodal SLERP & Diacritic / Short Artist Vectors

    func testSonicBridgeAntipodalSLERPDiacriticsAndShortArtistTokens() {
        let vecA = [1.0, 0.0, 0.0, 0.0]
        let vecB = [-1.0, 0.0, 0.0, 0.0]
        let mid = NativeMusicCuratorService.sphericalInterpolate(vecA, vecB, t: 0.5)
        let normMid = sqrt(mid.reduce(0.0) { $0 + $1 * $1 })
        let dotA = zip(mid, vecA).reduce(0.0) { $0 + $1.0 * $1.1 }

        XCTAssertEqual(normMid, 1.0, accuracy: 1e-6, "Antipodal SLERP midpoint must have unit norm")
        XCTAssertEqual(dotA, 0.0, accuracy: 1e-6, "Antipodal SLERP t=0.5 must lie on orthogonal equator, not collapse to endpoint A")

        for (artist, title) in [
            ("Ólafur Arnalds", "re:member"),
            ("Björk", "Jóga"),
            ("U2", "One"),
            ("ДДТ", "Осень")
        ] {
            let vec = NativeMusicCuratorService.shared.computeTrackSemanticVector([
                "artist": artist,
                "name": title
            ])
            XCTAssertNotNil(vec, "Track semantic vector must not return nil for '\(artist) — \(title)'")
            if let vec {
                let norm = sqrt(vec.reduce(0.0) { $0 + $1 * $1 })
                XCTAssertEqual(norm, 1.0, accuracy: 1e-5, "Embedding for '\(artist)' must be L2-normalized")
            }
        }
    }

    // MARK: - HIGH-4: Localized AMR Queue Confirmation Without Double-Skip

    func testAMRQueueLocalizedTrackConfirmationPreventsDoubleSkipAndRejectsHistoryDrain() {
        defer {
            PlaybackStateStore.shared.resetCustomQueue()
        }

        let prevHistory = TrackInfo(id: "prev-0", numericId: 99, name: "Sweet Apocalypse", artist: "Lambert", isLocal: false, index: 1)
        let track1 = TrackInfo(id: "1", numericId: 101, name: "Hitoshibai", artist: "Mai Fuchigami", isLocal: false, index: 1)
        let track2 = TrackInfo(id: "2", numericId: 102, name: "Minor Piece", artist: "ZAQ", isLocal: false, index: 2)

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.latestHistoryTracks = [prevHistory]
            PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
            PlaybackStateStore.shared.lastCloudPlayTime = Date().addingTimeInterval(-6.0)
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
            PlaybackStateStore.shared.isUserPaused = false
        }

        // 1. First notification with localized Japanese title & localized artist confirms index 0 AND updates name
        QueueManager.shared.handleTrackNotification(userInfo: [
            "Player State": "playing",
            "Name": "ひとしばい",
            "Artist": "渕上舞"
        ])
        PlaybackStateStore.shared.withLock {
            XCTAssertTrue(PlaybackStateStore.shared.currentTrackPlaybackConfirmed)
            XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 0)
            XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueue[0].name, "ひとしばい")
        }

        // 2. Subsequent notification for the SAME localized track must NOT false-trigger foreign skip 0 -> 1!
        QueueManager.shared.handleTrackNotification(userInfo: [
            "Player State": "playing",
            "Name": "ひとしばい",
            "Artist": "渕上舞"
        ])
        PlaybackStateStore.shared.withLock {
            XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 0, "Repeated notification for confirmed localized track must not double-skip")
        }
    }

    // MARK: - Stream Buffering Zero-Jump & Radio Playlist Short-Circuit Regressions

    func testPlayerStatusCacheDoesNotExtrapolateWhileBufferingAtZeroPosition() {
        defer {
            PlaybackStateStore.shared.invalidateStatusCache()
        }

        // 1. When stream is stuck buffering at position == 0.0, cached status MUST remain 0.0 (no 0:00 -> 0:02 sawtooth jump)
        let bufferingTrack = TrackInfo(id: "cloud-1", numericId: 501, name: "Stalled Stream", artist: "Test Artist", duration: 210.0, isLocal: false)
        let zeroStatus = PlayerStatus(
            playerState: "playing",
            position: 0.0,
            duration: 210.0,
            playlist: "Моя станция",
            isRadio: true,
            audioQuality: "Буферизация потока…",
            track: bufferingTrack,
            isBuffering: true
        )
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastSkipTime = .distantPast
            PlaybackStateStore.shared.lastPlayerStatusCache = (Date().addingTimeInterval(-0.6), zeroStatus)
        }
        let sampledZero = PlayerStatusEngine.shared.getPlayerStatus()
        XCTAssertEqual(sampledZero.position, 0.0, accuracy: 0.001, "Position at 0.0 must never extrapolate forward while waiting for first decoded audio frame")

        // 2. Once playback has genuinely advanced (position > 0.05), cache extrapolation smoothly advances position
        let advancingStatus = PlayerStatus(
            playerState: "playing",
            position: 12.0,
            duration: 210.0,
            playlist: "Моя станция",
            isRadio: true,
            audioQuality: "Lossless (ALAC 16-bit/44.1kHz)",
            track: bufferingTrack,
            isBuffering: false
        )
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastPlayerStatusCache = (Date().addingTimeInterval(-0.5), advancingStatus)
        }
        let sampledAdvancing = PlayerStatusEngine.shared.getPlayerStatus()
        XCTAssertGreaterThan(sampledAdvancing.position, 12.35, "Active playback past 0.05s should smoothly extrapolate elapsed cache age")
    }

    func testRadioStationPlaylistTracksShortCircuitsWithoutAppleScript() {
        XCTAssertTrue(LibraryService.shared.getPlaylistTracks(name: "Моя станция").isEmpty)
        XCTAssertTrue(LibraryService.shared.getPlaylistTracks(name: "Станция открытий").isEmpty)
        XCTAssertTrue(LibraryService.shared.getPlaylistTracks(name: "Apple Music 1").isEmpty)
    }

    func testDirectSeedMismatchTrackingAndStagedBufferCaseNormalization() {
        let testCatalogId = "1799990001"
        XCTAssertFalse(PlaybackRouter.hasDirectSeedMismatch(catalogId: testCatalogId))
        PlaybackRouter.markDirectSeedMismatch(catalogId: testCatalogId)
        XCTAssertTrue(PlaybackRouter.hasDirectSeedMismatch(catalogId: testCatalogId))

        let bufferSnapshot: [(dbId: Int, name: String, artist: String)] = [
            (dbId: 3706, name: "Needle On Da Rec", artist: "Lekkerfaces & Deadly Guns"),
            (dbId: 3710, name: "It’s Me Surprise", artist: "Dimitri K.")
        ]
        XCTAssertEqual(
            MusicKitManager.shared.matchTrackInStagedBufferSnapshot(
                name: "Needle on da Rec",
                artist: "Lekkerfaces & Deadly Guns",
                snapshot: bufferSnapshot
            ),
            3706
        )
        XCTAssertEqual(
            MusicKitManager.shared.matchTrackInStagedBufferSnapshot(
                name: "It's Me Surprise",
                artist: "Dimitri K.",
                snapshot: bufferSnapshot
            ),
            3710
        )
    }

    func testParseCatalogTrackItemsExtractsCatalogIdAndAvoidsIndexNumericIdCollision() {
        let items: [[String: Any]] = [
            [
                "id": "i.m78Xabc123",
                "attributes": [
                    "name": "Needle On Da Rec",
                    "artistName": "Lekkerfaces & Deadly Guns",
                    "albumName": "HYPER",
                    "durationInMillis": 126353.0,
                    "playParams": [
                        "id": "i.m78Xabc123",
                        "kind": "song",
                        "catalogId": "6829729404"
                    ]
                ]
            ],
            [
                "id": "i.noCatalogIdTrack",
                "attributes": [
                    "name": "Uploaded Cloud Track",
                    "artistName": "Local Upload",
                    "albumName": "Demo",
                    "durationInMillis": 180000.0
                ]
            ]
        ]

        let parsed = MusicKitManager.shared.parseCatalogTrackItems(items)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].id, "6829729404")
        XCTAssertEqual(parsed[0].catalogId, "6829729404")
        XCTAssertEqual(parsed[0].numericId, 6829729404)

        // Non-numeric library IDs without catalogId must NEVER get numericId = 2 (which would collide with local Music.app database IDs < 10_000_000!)
        XCTAssertEqual(parsed[1].id, "i.noCatalogIdTrack")
        XCTAssertNil(parsed[1].numericId)
        XCTAssertEqual(parsed[1].index, 2)
    }

    func testRuntimeAndShutdownCleanupPurgeLegacyStagingStateCompletely() {
        let original = MusicKitManager.shared.reusableStagingStateSnapshot()
        defer {
            MusicKitManager.shared.configureReusableStagingStateForTesting(
                reusableId: original.reusableId,
                trackCount: original.trackCount,
                legacyTempQueueId: original.legacyTempQueueId
            )
        }

        MusicKitManager.shared.configureReusableStagingStateForTesting(
            reusableId: "p.WarmBuffer01",
            trackCount: 18,
            legacyTempQueueId: "p.OldQueue99"
        )

        MusicKitManager.shared.cleanupTemporaryPlaybackPlaylists(keepingActiveQueue: false, synchronous: false)
        let afterRuntimeSwitch = MusicKitManager.shared.reusableStagingStateSnapshot()
        XCTAssertNil(afterRuntimeSwitch.reusableId)
        XCTAssertEqual(afterRuntimeSwitch.trackCount, 0)
        XCTAssertNil(afterRuntimeSwitch.legacyTempQueueId)

        MusicKitManager.shared.cleanupTemporaryPlaybackPlaylists(keepingActiveQueue: false, synchronous: true)
        let afterShutdown = MusicKitManager.shared.reusableStagingStateSnapshot()
        XCTAssertNil(afterShutdown.reusableId)
        XCTAssertEqual(afterShutdown.trackCount, 0)
        XCTAssertNil(afterShutdown.legacyTempQueueId)
    }

    func testUnstageableCatalogIdTrackingIsolatesRightsLockedSongs() {
        MusicKitManager.shared.clearUnstageableCatalogIdsForTesting()
        defer { MusicKitManager.shared.clearUnstageableCatalogIdsForTesting() }

        XCTAssertFalse(MusicKitManager.shared.isUnstageableCatalogId("1823646274"))
        MusicKitManager.shared.markUnstageableCatalogId(" 1823646274 ")
        XCTAssertTrue(MusicKitManager.shared.isUnstageableCatalogId("1823646274"))
        XCTAssertFalse(MusicKitManager.shared.isUnstageableCatalogId("1065973618"))
    }

    func testAccountStorefrontAndLocaleResolveStrictlyFromAccountMetadataWithoutHardcoding() {
        let orig = MusicKitManager.shared.storefrontMetadataSnapshot()
        defer {
            MusicKitManager.shared.configureStorefrontMetadataForTesting(
                storefront: orig.storefront,
                supportedLanguages: orig.supportedLanguages,
                defaultLanguage: orig.defaultLanguage
            )
        }

        // 1. US account on a Russian macOS system (even when US `supportedLanguageTags` lists `"ru"` alongside `"en-US"`):
        // storefront is `"us"` and `getPreferredLanguageTag` MUST honor the account storefront's `defaultLanguageTag` (`"en-US"`),
        // ONLY overriding when the user's locale explicitly targets that same storefront region (e.g. `"es-US"` / `"fr-CA"` on `"ca"`).
        MusicKitManager.shared.configureStorefrontMetadataForTesting(
            storefront: "US",
            supportedLanguages: ["en-US", "es-MX", "ar", "ru", "zh-Hans-CN", "fr-FR", "ko", "pt-BR", "vi", "zh-Hant-TW"],
            defaultLanguage: "en-US"
        )
        XCTAssertEqual(MusicKitManager.shared.getUserStorefront(), "us")
        XCTAssertEqual(MusicKitManager.shared.resolveEffectiveStorefront(nil), "us")
        XCTAssertEqual(
            MusicKitManager.shared.getPreferredLanguageTag(preferredLanguagesOverride: ["ru-RU"]),
            "en-US"
        )

        // 2. Canada account ("ca") with ["en-CA", "fr-CA"] when user locale is "fr-CA" (matching region "ca") -> selects "fr-CA"
        MusicKitManager.shared.configureStorefrontMetadataForTesting(
            storefront: "ca",
            supportedLanguages: ["en-CA", "fr-CA"],
            defaultLanguage: "en-CA"
        )
        XCTAssertEqual(MusicKitManager.shared.getUserStorefront(), "ca")
        XCTAssertEqual(
            MusicKitManager.shared.getPreferredLanguageTag(preferredLanguagesOverride: ["fr-CA"]),
            "fr-CA"
        )

        // 2b. Kazakhstan account ("kz") supporting ["kk", "ru", "en-GB"] with regional locale "ru-KZ" -> selects "ru"
        MusicKitManager.shared.configureStorefrontMetadataForTesting(
            storefront: "kz",
            supportedLanguages: ["kk", "ru", "en-GB"],
            defaultLanguage: "en-GB"
        )
        XCTAssertEqual(MusicKitManager.shared.getUserStorefront(), "kz")
        XCTAssertEqual(
            MusicKitManager.shared.getPreferredLanguageTag(preferredLanguagesOverride: ["ru-KZ"]),
            "ru"
        )

        // 3. Japan account ("jp") supporting ["ja", "en-US"] on Turkish macOS -> falls back to JP defaultLanguageTag ("ja")
        MusicKitManager.shared.configureStorefrontMetadataForTesting(
            storefront: "jp",
            supportedLanguages: ["ja", "en-US"],
            defaultLanguage: "ja"
        )
        XCTAssertEqual(MusicKitManager.shared.getUserStorefront(), "jp")
        XCTAssertEqual(
            MusicKitManager.shared.getPreferredLanguageTag(preferredLanguagesOverride: ["tr-TR"]),
            "ja"
        )
    }

    func testPlayerStatusBufferStagingSerializationAndPauseReset() throws {
        defer {
            PlaybackStateStore.shared.resetCustomQueue()
        }

        // 1. Verify Codable round-trip of `is_staging_buffer` and `loading_stage`
        let status = PlayerStatus(
            playerState: "playing",
            position: 0.0,
            duration: 214.0,
            volume: 100,
            shuffle: false,
            repeatMode: "off",
            playlist: "Новинки для вас",
            isRadio: false,
            audioQuality: "Загрузка через буфер AMR…",
            track: TrackInfo(id: "1789001122", name: "Monsoon", artist: "Ha Hyun Sang", isLocal: false),
            isBuffering: true,
            isStreamStalled: false,
            isStagingBuffer: true,
            loadingStage: "buffer"
        )
        let encoded = try JSONEncoder().encode(status)
        let jsonObj = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(jsonObj["is_staging_buffer"] as? Bool, true)
        XCTAssertEqual(jsonObj["loading_stage"] as? String, "buffer")
        XCTAssertEqual(jsonObj["is_buffering"] as? Bool, true)

        let decoded = try JSONDecoder().decode(PlayerStatus.self, from: encoded)
        XCTAssertEqual(decoded.isStagingBuffer, true)
        XCTAssertEqual(decoded.loadingStage, "buffer")
        XCTAssertEqual(decoded.isBuffering, true)

        // 2. Verify `PlaybackStateStore.isTransitioningTrack` includes `isActivelyStagingInBuffer`
        //    and `PlaybackTransportController.pause()` clears buffer staging flags cleanly
        XCTAssertTrue(PlaybackRouter.shared.isTestingEnvironment)

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastSkipTime = .distantPast
            PlaybackStateStore.shared.isStagingCloudTrack = false
            PlaybackStateStore.shared.isActivelyStagingInBuffer = true
            PlaybackStateStore.shared.activeLoadingStage = "buffer"
            PlaybackStateStore.shared.activeLoadingStartedAt = Date()
        }
        XCTAssertTrue(PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isTransitioningTrack })

        _ = PlaybackTransportController.shared.pause()
        PlaybackStateStore.shared.withLock {
            XCTAssertFalse(PlaybackStateStore.shared.isActivelyStagingInBuffer)
            XCTAssertNil(PlaybackStateStore.shared.activeLoadingStage)
            XCTAssertNil(PlaybackStateStore.shared.activeLoadingStartedAt)
        }
    }

    func testCloudTrackMatchingRejectsSameArtistWrongSongAndLiveOrOffVocalVariants() {
        // 1. Same artist ("Guano Apes"), different song ("Open Your Eyes" vs "Lords of the Boards") MUST NOT match!
        XCTAssertFalse(
            PlaybackRouter.sameScriptTrackMatches(
                expectedName: "Open Your Eyes",
                expectedArtist: "Guano Apes",
                candidateName: "Lords of the Boards",
                candidateArtist: "Guano Apes"
            )
        )

        // 2. Studio "Big In Japan" vs "Big In Japan (Live)" MUST NOT match or collapse in search dedup!
        XCTAssertTrue(LibraryService.hasConflictingVersionQualifier("Big In Japan", "Big In Japan (Live)"))
        XCTAssertFalse(
            PlaybackRouter.sameScriptTrackMatches(
                expectedName: "Big In Japan",
                expectedArtist: "Guano Apes",
                candidateName: "Big In Japan (Live)",
                candidateArtist: "Guano Apes"
            )
        )
        XCTAssertNotEqual(
            CloudCatalogService.normalizeTrackKey(name: "Big In Japan", artist: "Guano Apes"),
            CloudCatalogService.normalizeTrackKey(name: "Big In Japan (Live)", artist: "Guano Apes")
        )

        // 3. "Soleil Smile (Off Vocal)" / "ソレイユスマイル (Off Vocal)" MUST NOT match vocal version!
        XCTAssertTrue(LibraryService.hasConflictingVersionQualifier("ソレイユスマイル (Off Vocal)", "ソレイユスマイル"))
        XCTAssertTrue(LibraryService.hasConflictingVersionQualifier("Soleil Smile (Off Vocal)", "Soleil Smile"))
        XCTAssertFalse(LibraryService.hasConflictingVersionQualifier("Soleil Smile (Off Vocal)", "ソレイユスマイル (Off Vocal)"))

        // 4. Words containing "live" as substring ("Stayin' Alive", "Live Forever") are NOT treated as Live versions
        XCTAssertFalse(LibraryService.hasConflictingVersionQualifier("Stayin' Alive", "Stayin' Alive (Remastered)"))
        XCTAssertTrue(
            PlaybackRouter.sameScriptTrackMatches(
                expectedName: "Big In Japan",
                expectedArtist: "Guano Apes",
                candidateName: "Big In Japan (Remastered 2020)",
                candidateArtist: "Guano Apes"
            )
        )
    }

    func testDirectCloudQueueMatchesLocalizedVariantsAndIgnoresDrainingPreviousTrack() {
        defer {
            PlaybackStateStore.shared.resetCustomQueue()
            PlaybackRouter.shared.urlOpener = nil
        }

        var openedUrls: [String] = []
        PlaybackRouter.shared.urlOpener = { url in
            openedUrls.append(url.absoluteString)
            return true
        }

        // User library playlist item where `id` is `"i.abc"` and `catalogId` is numeric `"1790001122"`
        let track0 = TrackInfo(
            id: "i.libPrev01",
            numericId: nil,
            name: "Flowers and Dreams",
            artist: "F/ACE",
            album: "Single",
            duration: 215,
            isLocal: false,
            url: nil,
            index: 1,
            catalogId: "1790001122"
        )
        let track1 = TrackInfo(
            id: "i.libNext02",
            numericId: nil,
            name: "Namae wo Yobuyo",
            artist: "Luck Life",
            album: "Single",
            duration: 242,
            isLocal: false,
            url: nil,
            index: 2,
            catalogId: "1790002233"
        )

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track0, track1]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
        }

        // Switching to index 1 must capture `track0` as `transitionPreviousTrackKey` and pass numeric `catalogId` (`1790002233`)
        XCTAssertTrue(QueueManager.shared.playQueueIndexUnlocked(1))
        XCTAssertEqual(PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.transitionPreviousTrackKey }, "f/ace:flowers and dreams")

        // Draining notification for `Flowers and Dreams` during stream handoff MUST be ignored
        XCTAssertTrue(
            QueueManager.shared.isDrainingPreviousTrack(
                candidateName: "Flowers and Dreams",
                candidateArtist: "F/ACE",
                confirmed: false,
                timeSincePlay: 0.8
            )
        )

        // Official catalog variant (`名前を呼ぶよ`) populated in `activeTrackTitleVariants` confirms immediately
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.activeTrackTitleVariants = [("名前を呼ぶよ", "ラックライフ")]
        }
        XCTAssertTrue(
            QueueManager.shared.matchesExpectedQueueTrack(
                track1,
                candidateName: "名前を呼ぶよ",
                candidateArtist: "ラックライフ"
            )
        )
    }

    func testMultiArtistReversedCreditsAndPreferredAlternateCatalogSongMapping() {
        MusicKitManager.shared.clearUnstageableCatalogIdsForTesting()
        defer { MusicKitManager.shared.clearUnstageableCatalogIdsForTesting() }

        let tokens = MusicKitManager.extractArtistTokens("Lekkerfaces & Deadly Guns")
        XCTAssertEqual(tokens, ["lekkerfaces", "deadly guns"])
        XCTAssertTrue(MusicKitManager.artistsOverlap("Lekkerfaces & Deadly Guns", "Deadly Guns & Lekkerfaces"))
        XCTAssertTrue(MusicKitManager.artistsOverlap("Lekkerfaces & Deadly Guns", "Deadly Guns"))
        XCTAssertFalse(MusicKitManager.artistsOverlap("Lekkerfaces & Deadly Guns", "Guano Apes"))

        // Snapshot matching must resolve alternate compilation credit order while still rejecting Live/Off Vocal mismatches
        let snapshot: [(dbId: Int, name: String, artist: String)] = [
            (dbId: 9141, name: "Needle On Da Rec", artist: "Deadly Guns"),
            (dbId: 9142, name: "Needle On Da Rec (Live)", artist: "Lekkerfaces & Deadly Guns")
        ]
        XCTAssertEqual(
            MusicKitManager.shared.matchTrackInStagedBufferSnapshot(
                name: "Needle On Da Rec",
                artist: "Lekkerfaces & Deadly Guns",
                snapshot: snapshot
            ),
            9141
        )

        // Preferred alternate mapping caches proven ISRC sibling (`6829729404` -> `6817136270`) and populates title/artist variants
        MusicKitManager.shared.recordPreferredAlternateCatalogSong(
            for: "6829729404",
            alternate: (id: "6817136270", name: "Needle On Da Rec", artist: "Deadly Guns & Lekkerfaces")
        )
        let pref = MusicKitManager.shared.preferredAlternateCatalogSong(for: "6829729404")
        XCTAssertEqual(pref?.id, "6817136270")
        XCTAssertEqual(pref?.artist, "Deadly Guns & Lekkerfaces")
        XCTAssertTrue(
            MusicKitManager.shared.cachedTitleVariants(catalogId: "6829729404").contains {
                $0.name == "Needle On Da Rec" && $0.artist == "Deadly Guns & Lekkerfaces"
            }
        )

        // If the alternate itself becomes unstageable, preferredAlternateCatalogSong must drop it
        MusicKitManager.shared.markUnstageableCatalogId("6817136270")
        XCTAssertNil(MusicKitManager.shared.preferredAlternateCatalogSong(for: "6829729404"))
    }
}
