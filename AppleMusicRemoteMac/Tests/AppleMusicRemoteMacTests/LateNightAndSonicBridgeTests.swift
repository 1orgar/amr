//
//  LateNightAndSonicBridgeTests.swift
//  AppleMusicRemoteMacTests
//
//  Unit tests for Audiophile Late-Night Dynamic Range Control (64-bit ITU-R BS.1770 K-weighted
//  dual-envelope DRC + -63 dBFS noise-floor gate + -1.0 dBTP look-ahead guard + Cloud Sync)
//  and Sonic Bridge (512-D Geodesic SLERP trajectory solver).
//

import XCTest
@testable import AppleMusicRemoteMac

final class LateNightAndSonicBridgeTests: XCTestCase {

    private var tempDir: URL!
    private var suiteA: String!
    private var suiteB: String!
    private var defaultsA: UserDefaults!
    private var defaultsB: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("amr-latenight-bridge-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        suiteA = "com.amr.tests.drcA.\(UUID().uuidString)"
        suiteB = "com.amr.tests.drcB.\(UUID().uuidString)"
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

    // MARK: - 1. 100% Bit-Perfect Identity Bypass When Off

    func testLateNightDRCBitExactIdentityWhenOff() {
        let processor = LateNightDRCProcessor()
        processor.setMode(.off)

        let frameCount = 512
        var leftOrig = [Double](repeating: 0.0, count: frameCount)
        var rightOrig = [Double](repeating: 0.0, count: frameCount)
        for i in 0..<frameCount {
            leftOrig[i] = sin(Double(i) * 0.137) * 0.85
            rightOrig[i] = cos(Double(i) * 0.093) * 0.65
        }

        var leftBuf = leftOrig
        var rightBuf = rightOrig
        leftBuf.withUnsafeMutableBufferPointer { lPtr in
            rightBuf.withUnsafeMutableBufferPointer { rPtr in
                processor.processPlanarDouble(
                    left: lPtr.baseAddress!,
                    right: rPtr.baseAddress!,
                    frameCount: frameCount,
                    sampleRate: 96_000.0
                )
            }
        }

        for i in 0..<frameCount {
            XCTAssertEqual(leftBuf[i].bitPattern, leftOrig[i].bitPattern, "Planar 64-bit L sample must be bit-identical in .off mode")
            XCTAssertEqual(rightBuf[i].bitPattern, rightOrig[i].bitPattern, "Planar 64-bit R sample must be bit-identical in .off mode")
        }

        var fL: Float = -0.43210987
        var fR: Float = 0.7654321
        let origFL = fL.bitPattern
        let origFR = fR.bitPattern
        processor.processStereoFloatPair(left: &fL, right: &fR, sampleRate: 44_100.0)
        XCTAssertEqual(fL.bitPattern, origFL, "Float32 stream L sample must be bit-identical in .off mode")
        XCTAssertEqual(fR.bitPattern, origFR, "Float32 stream R sample must be bit-identical in .off mode")
    }

    // MARK: - 2. -63 dBFS Noise-Floor Gate (No Tape Hiss Pumping)

    func testLateNightDRCNoiseFloorGatePreventsTapeHissPumping() {
        let processor = LateNightDRCProcessor()
        processor.setMode(.concert)

        let sr = 48_000.0
        let totalFrames = Int(sr * 2.0) // 2 seconds of -70 dBFS low-level tape hiss
        let hissAmp = pow(10.0, -70.0 / 20.0) // ~0.0003162

        var left = [Double](repeating: 0.0, count: totalFrames)
        var right = [Double](repeating: 0.0, count: totalFrames)
        for i in 0..<totalFrames {
            let phase = 2.0 * Double.pi * 1000.0 * Double(i) / sr
            left[i] = sin(phase) * hissAmp
            right[i] = cos(phase) * hissAmp
        }

        left.withUnsafeMutableBufferPointer { lPtr in
            right.withUnsafeMutableBufferPointer { rPtr in
                processor.processPlanarDouble(
                    left: lPtr.baseAddress!,
                    right: rPtr.baseAddress!,
                    frameCount: totalFrames,
                    sampleRate: sr
                )
            }
        }

        let snap = processor.telemetrySnapshot()
        XCTAssertLessThanOrEqual(
            abs(snap.gainDB),
            0.05,
            "Signals below -63 dBFS noise-floor gate must NOT receive upward boost (got \(snap.gainDB) dB)"
        )
    }

    // MARK: - 3. Whisper & Pianissimo Upward Lift (Gentle vs Night Concert)

    func testLateNightDRCWhisperLiftGentleVsConcert() {
        let sr = 48_000.0
        let totalFrames = Int(sr * 3.5) // 3.5s so slow envelope & upward gain settle
        let quietAmp = pow(10.0, -40.0 / 20.0) // -40 dBFS pianissimo passage (above -63 dBFS gate)

        func runWhisperPass(mode: LateNightDRCMode) -> (gainDB: Double, rmsOut: Double) {
            let proc = LateNightDRCProcessor()
            proc.setMode(mode)
            var left = [Double](repeating: 0.0, count: totalFrames)
            var right = [Double](repeating: 0.0, count: totalFrames)
            for i in 0..<totalFrames {
                let s = sin(2.0 * Double.pi * 1000.0 * Double(i) / sr) * quietAmp
                left[i] = s
                right[i] = s
            }
            left.withUnsafeMutableBufferPointer { lPtr in
                right.withUnsafeMutableBufferPointer { rPtr in
                    proc.processPlanarDouble(
                        left: lPtr.baseAddress!,
                        right: rPtr.baseAddress!,
                        frameCount: totalFrames,
                        sampleRate: sr
                    )
                }
            }
            let tailCount = 4800
            var sumSq = 0.0
            for i in (totalFrames - tailCount)..<totalFrames {
                sumSq += left[i] * left[i]
            }
            let rms = sqrt(sumSq / Double(tailCount))
            return (proc.telemetrySnapshot().gainDB, rms)
        }

        let gentleRes = runWhisperPass(mode: .gentle)
        let concertRes = runWhisperPass(mode: .concert)

        XCTAssertGreaterThan(gentleRes.gainDB, 3.5, "Gentle mode should lift -40 dBFS pianissimo by > +3.5 dB")
        XCTAssertLessThanOrEqual(gentleRes.gainDB, 6.1, "Gentle mode lift must respect +6.0 dB cap")

        XCTAssertGreaterThan(
            concertRes.gainDB,
            gentleRes.gainDB + 2.0,
            "Night Concert mode should apply stronger pianissimo lift than Gentle mode"
        )
        XCTAssertLessThanOrEqual(concertRes.gainDB, 9.6, "Night Concert mode lift must respect +9.5 dB cap")
        XCTAssertGreaterThan(concertRes.rmsOut, gentleRes.rmsOut, "Night Concert output RMS on quiet passage must exceed Gentle")
    }

    // MARK: - 4. Crescendo Compression & -1.0 dBTP True Peak Look-Ahead Guard

    func testLateNightDRCCrescendoAndMinus1dBTPCeilingGuard() {
        let processor = LateNightDRCProcessor()
        processor.setMode(.concert)

        let sr = 48_000.0
        let quietFrames = Int(sr * 2.0)
        let burstFrames = Int(sr * 0.5)
        let totalFrames = quietFrames + burstFrames

        var left = [Double](repeating: 0.0, count: totalFrames)
        var right = [Double](repeating: 0.0, count: totalFrames)

        // First 2.0s: quiet -38 dBFS passage (causes upward gain ~ +7..+8 dB)
        let quietAmp = pow(10.0, -38.0 / 20.0)
        for i in 0..<quietFrames {
            let s = sin(2.0 * Double.pi * 880.0 * Double(i) / sr) * quietAmp
            left[i] = s
            right[i] = s
        }
        // Sudden 0.0 dBFS (1.0 amplitude) orchestral tutti hit right when upward gain is boosted!
        for i in quietFrames..<totalFrames {
            let s = sin(2.0 * Double.pi * 880.0 * Double(i) / sr) * 1.0
            left[i] = s
            right[i] = s
        }

        left.withUnsafeMutableBufferPointer { lPtr in
            right.withUnsafeMutableBufferPointer { rPtr in
                processor.processPlanarDouble(
                    left: lPtr.baseAddress!,
                    right: rPtr.baseAddress!,
                    frameCount: totalFrames,
                    sampleRate: sr
                )
            }
        }

        let ceilingLinear = 0.89126 // -1.0 dBFS + tiny float tolerance
        var peakObserved = 0.0
        for i in 0..<totalFrames {
            peakObserved = max(peakObserved, abs(left[i]), abs(right[i]))
        }

        XCTAssertLessThanOrEqual(
            peakObserved,
            ceilingLinear,
            "64-sample look-ahead True Peak guard must prevent any sample from exceeding -1.0 dBFS (got \(peakObserved))"
        )
        XCTAssertLessThan(
            processor.telemetrySnapshot().gainDB,
            0.0,
            "Sustained 0 dBFS crescendo must engage downward compression (< 0 dB net gain)"
        )
    }

    // MARK: - 5. Cloud Sync Two-Way Last-Write-Wins Merge for Late-Night DRC

    func testLateNightDRCCloudSyncTwoWayLWWMerge() throws {
        let cloudFileURL = tempDir
            .appendingPathComponent("iCloudSync", isDirectory: true)
            .appendingPathComponent(CloudSettingsSyncService.cloudFileName, isDirectory: false)

        let dspA = DSPPresetManager(loadFromDefaults: false)
        let scA = AppleSoundCheckService(customCacheFileURL: tempDir.appendingPathComponent("sc_a.json"))
        let specA = SpectralIntegrityAnalyzer(customCacheFileURL: tempDir.appendingPathComponent("spec_a.json"))
        let drcA = LateNightDRCService(userDefaults: defaultsA, suiteKeyPrefix: "test.macA.drc", isIsolated: true)

        let dspB = DSPPresetManager(loadFromDefaults: false)
        let scB = AppleSoundCheckService(customCacheFileURL: tempDir.appendingPathComponent("sc_b.json"))
        let specB = SpectralIntegrityAnalyzer(customCacheFileURL: tempDir.appendingPathComponent("spec_b.json"))
        let drcB = LateNightDRCService(userDefaults: defaultsB, suiteKeyPrefix: "test.macB.drc", isIsolated: true)

        XCTAssertEqual(drcA.mode, .off)
        XCTAssertEqual(drcB.mode, .off)

        // Step 1: Mac A enables Night Concert mode and syncs to Cloud
        drcA.setMode(.concert, notifyCloudSync: false)
        _ = try CloudSettingsSyncService.performTwoWaySync(
            fileURL: cloudFileURL,
            dspManager: dspA,
            soundCheckService: scA,
            spectralAnalyzer: specA,
            normPolicyProvider: { nil },
            normPolicyMerger: { _ in false },
            lateNightService: drcA
        )

        // Step 2: Mac B pulls Night Concert mode from Cloud
        let pullSummaryB = try CloudSettingsSyncService.performTwoWaySync(
            fileURL: cloudFileURL,
            dspManager: dspB,
            soundCheckService: scB,
            spectralAnalyzer: specB,
            normPolicyProvider: { nil },
            normPolicyMerger: { _ in false },
            lateNightService: drcB
        )
        XCTAssertTrue(pullSummaryB.lateNightDRCChanged)
        XCTAssertEqual(drcB.mode, .concert)

        // Step 3: Mac B switches to Gentle mode slightly later and syncs back to Mac A
        Thread.sleep(forTimeInterval: 0.015)
        drcB.setMode(.gentle, notifyCloudSync: false)
        _ = try CloudSettingsSyncService.performTwoWaySync(
            fileURL: cloudFileURL,
            dspManager: dspB,
            soundCheckService: scB,
            spectralAnalyzer: specB,
            normPolicyProvider: { nil },
            normPolicyMerger: { _ in false },
            lateNightService: drcB
        )

        let pullSummaryA = try CloudSettingsSyncService.performTwoWaySync(
            fileURL: cloudFileURL,
            dspManager: dspA,
            soundCheckService: scA,
            spectralAnalyzer: specA,
            normPolicyProvider: { nil },
            normPolicyMerger: { _ in false },
            lateNightService: drcA
        )
        XCTAssertTrue(pullSummaryA.lateNightDRCChanged)
        XCTAssertEqual(drcA.mode, .gentle)
    }

    // MARK: - 6. Sonic Bridge 512-D Geodesic SLERP & Trajectory Solver

    func testSonicBridgeSLERPAndGeodesicSequenceMonotonicity() {
        let dim = 16
        var vecA = [Double](repeating: 0.0, count: dim)
        var vecB = [Double](repeating: 0.0, count: dim)
        vecA[0] = 1.0 // Pure axis 0 (e.g. Acoustic Jazz)
        vecB[1] = 1.0 // Pure axis 1 (e.g. Ambient Techno)

        let mid = NativeMusicCuratorService.sphericalInterpolate(vecA, vecB, t: 0.5)
        let normMid = sqrt(mid.reduce(0.0) { $0 + $1 * $1 })
        XCTAssertEqual(normMid, 1.0, accuracy: 1e-6, "SLERP midpoint must lie on unit hypersphere")
        XCTAssertEqual(mid[0], mid[1], accuracy: 1e-6, "SLERP t=0.5 between orthogonal basis vectors must be equidistant")

        // Construct synthetic pool of candidate tracks spanning angles 0 -> pi/2, plus duplicates & repeated artists
        var candidates: [[String: Any]] = []
        let artists = [
            "Miles Davis", "Bill Evans", "Chet Baker", "Esbjörn Svensson Trio",
            "Portico Quartet", "Floating Points", "Nils Frahm", "Kiasmos",
            "Jon Hopkins", "Rival Consoles", "Moderat", "Daft Punk"
        ]

        for idx in 0..<artists.count {
            let frac = Double(idx) / Double(artists.count - 1)
            let angle = frac * (Double.pi * 0.5)
            var v = [Double](repeating: 0.0, count: dim)
            v[0] = cos(angle)
            v[1] = sin(angle)
            candidates.append([
                "id": "cat-\(idx)",
                "name": "Bridge Piece \(idx)",
                "artist": artists[idx],
                "_test_vec": v
            ])
        }

        // Inject duplicate track & consecutive-artist trap near midpoint
        var midTrapVec = [Double](repeating: 0.0, count: dim)
        midTrapVec[0] = cos(Double.pi * 0.25)
        midTrapVec[1] = sin(Double.pi * 0.25)
        candidates.append([
            "id": "cat-dup",
            "name": "Bridge Piece 5 (Remastered 2024)",
            "artist": "Floating Points",
            "_test_vec": midTrapVec
        ])
        candidates.append([
            "id": "cat-same-artist",
            "name": "Another Floating Track",
            "artist": "Floating Points",
            "_test_vec": midTrapVec
        ])

        let endpointA = candidates.first!
        let endpointB = candidates[11]

        let route = NativeMusicCuratorService.shared.solveGeodesicBridgeSequence(
            candidates: candidates,
            endpointA: endpointA,
            endpointB: endpointB,
            vecA: vecA,
            vecB: vecB,
            stepCount: 8,
            preferEnglish: true
        )

        XCTAssertEqual(route.count, 8, "Route must contain exact requested stepCount")
        XCTAssertEqual(route.first?["id"] as? String, "cat-0", "Step 1 must pin Point A")
        XCTAssertEqual(route.last?["id"] as? String, "cat-11", "Final step must pin Point B")
        XCTAssertEqual(route.first?["bridge_progress"] as? Int, 0)
        XCTAssertEqual(route.last?["bridge_progress"] as? Int, 100)

        // Verify zero duplicate IDs, zero back-to-back same artist, and monotonic progression toward vecB
        var seenIds = Set<String>()
        var prevArtist = ""
        var prevDotB = -1.0

        for step in route {
            let id = step["id"] as? String ?? ""
            let artist = step["artist"] as? String ?? ""
            XCTAssertFalse(seenIds.contains(id), "Sonic Bridge must never repeat a song (\(id))")
            seenIds.insert(id)

            if !prevArtist.isEmpty {
                XCTAssertNotEqual(artist, prevArtist, "Sonic Bridge should avoid back-to-back tracks by same artist")
            }
            prevArtist = artist

            if let vec = step["_test_vec"] as? [Double] {
                let dotB = vec[1] // cosine similarity with vecB = [0, 1, 0, ...]
                XCTAssertGreaterThanOrEqual(
                    dotB + 0.05,
                    prevDotB,
                    "Sonic Bridge trajectory must progress monotonically from Point A toward Point B"
                )
                prevDotB = dotB
            }
        }
    }

    // MARK: - 7. Separated Master Enable + Profile Sync & Per-Device Permission

    func testLateNightSeparatedToggleProfilePersistenceCloudSyncAndDevicePermission() throws {
        let cloudFileURL = tempDir
            .appendingPathComponent("iCloudSyncToggleProfile", isDirectory: true)
            .appendingPathComponent(CloudSettingsSyncService.cloudFileName, isDirectory: false)

        let dspA = DSPPresetManager(loadFromDefaults: false)
        let scA = AppleSoundCheckService(customCacheFileURL: tempDir.appendingPathComponent("sc_tp_a.json"))
        let specA = SpectralIntegrityAnalyzer(customCacheFileURL: tempDir.appendingPathComponent("spec_tp_a.json"))
        let drcA = LateNightDRCService(userDefaults: defaultsA, suiteKeyPrefix: "test.tp.macA", isIsolated: true)

        let dspB = DSPPresetManager(loadFromDefaults: false)
        let scB = AppleSoundCheckService(customCacheFileURL: tempDir.appendingPathComponent("sc_tp_b.json"))
        let specB = SpectralIntegrityAnalyzer(customCacheFileURL: tempDir.appendingPathComponent("spec_tp_b.json"))
        let drcB = LateNightDRCService(userDefaults: defaultsB, suiteKeyPrefix: "test.tp.macB", isIsolated: true)

        // Default state: disabled (Bit-Perfect), default profile is .gentle
        XCTAssertFalse(drcA.isEnabled)
        XCTAssertEqual(drcA.selectedProfile, .gentle)
        XCTAssertEqual(drcA.mode, .off)

        // Choose .concert profile while keeping master switch OFF -> stays .off (Bit-Perfect) but remembers .concert
        drcA.updateState(enabled: false, profile: .concert, notifyCloudSync: false)
        XCTAssertFalse(drcA.isEnabled)
        XCTAssertEqual(drcA.selectedProfile, .concert)
        XCTAssertEqual(drcA.mode, .off)

        // Sync disabled-but-selected .concert state to Mac B via Cloud Sync
        _ = try CloudSettingsSyncService.performTwoWaySync(
            fileURL: cloudFileURL,
            dspManager: dspA,
            soundCheckService: scA,
            spectralAnalyzer: specA,
            normPolicyProvider: { nil },
            normPolicyMerger: { _ in false },
            lateNightService: drcA
        )
        let summaryB = try CloudSettingsSyncService.performTwoWaySync(
            fileURL: cloudFileURL,
            dspManager: dspB,
            soundCheckService: scB,
            spectralAnalyzer: specB,
            normPolicyProvider: { nil },
            normPolicyMerger: { _ in false },
            lateNightService: drcB
        )
        XCTAssertTrue(summaryB.lateNightDRCChanged)
        XCTAssertFalse(drcB.isEnabled)
        XCTAssertEqual(drcB.selectedProfile, .concert)
        XCTAssertEqual(drcB.mode, .off)

        // Turning master switch ON immediately activates remembered .concert profile
        drcB.setEnabled(true, notifyCloudSync: false)
        XCTAssertTrue(drcB.isEnabled)
        XCTAssertEqual(drcB.mode, .concert)

        // Turning master switch OFF returns to .off while preserving .concert
        drcB.setEnabled(false, notifyCloudSync: false)
        XCTAssertFalse(drcB.isEnabled)
        XCTAssertEqual(drcB.selectedProfile, .concert)
        XCTAssertEqual(drcB.mode, .off)

        // Verify ClientDeviceRecord per-device allowLateNightMode serialization & backward-compatible decode
        let record = ClientDeviceRecord(
            deviceId: "dev-late-night-1",
            deviceName: "iPad Pro",
            deviceType: "tablet",
            isAuthorized: true,
            lockScreenControls: false,
            allowLateNightMode: false,
            firstSeenAt: 1_700_000_000,
            lastSeenAt: 1_700_000_100,
            lastIPAddress: "192.168.1.42"
        )
        XCTAssertEqual(record.dictionary["allow_late_night_mode"] as? Bool, false)
        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ClientDeviceRecord.self, from: encoded)
        XCTAssertFalse(decoded.allowLateNightMode)

        // Verify 3-option dropdown ordering: .off ("Выкл (100% Bit-Perfect)") MUST be at index 0
        XCTAssertEqual(LateNightDRCMode.allCases, [.off, .gentle, .concert])
    }

    func testUnpinnedSearchResultsShuffleDoesNotAlwaysStartWithFirstTrack() async {
        defer {
            PlaybackStateStore.shared.resetCustomQueue()
        }

        let sampleTracks: [TrackInfo] = (0..<20).map { idx in
            TrackInfo(
                id: "track_\(idx)",
                numericId: nil,
                name: "UnitTest Shuffle Track \(idx)",
                artist: "UnitTest Shuffle Artist",
                album: "UnitTest Album",
                duration: 210,
                hasArtwork: false,
                artworkUrl: "",
                favorited: false,
                isLocal: false,
                url: nil,
                index: idx + 1
            )
        }

        // 1. Unpinned shuffle (startIndex = -1) across 15 runs must NOT pin index 0 ("Open Your Eyes") every time
        var distinctCustomFirstTracks = Set<String>()
        var distinctSearchFirstTracks = Set<String>()
        for _ in 0..<15 {
            _ = PlaybackRouter.shared.playCustomTracks(sampleTracks, startIndex: -1, shuffle: true, queueName: "Результаты поиска")
            if let first = PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.activeCustomQueue.first?.id }) {
                distinctCustomFirstTracks.insert(first)
            }

            _ = await PlaybackRouter.shared.playSearchResults(tracks: sampleTracks, startIndex: -1, shuffle: true, queueName: "Результаты поиска")
            if let first = PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.activeCustomQueue.first?.id }) {
                distinctSearchFirstTracks.insert(first)
            }
        }
        XCTAssertGreaterThan(distinctCustomFirstTracks.count, 1, "Unpinned playCustomTracks shuffle must randomize starting track instead of pinning index 0")
        XCTAssertGreaterThan(distinctSearchFirstTracks.count, 1, "Unpinned playSearchResults shuffle must randomize starting track instead of pinning index 0")

        // 2. Explicit pinned startIndex (e.g. startIndex = 5) with shuffle = true still starts with track_5
        _ = PlaybackRouter.shared.playCustomTracks(sampleTracks, startIndex: 5, shuffle: true, queueName: "Результаты поиска")
        let pinnedFirst = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.activeCustomQueue.first?.id }
        XCTAssertEqual(pinnedFirst, "track_5")
    }

    func testRadioStationDetectionAndRepeatOnePreservation() {
        defer {
            PlaybackStateStore.shared.resetCustomQueue()
        }

        // Apple Music Radio station playlist containers ("Моя станция", "Discovery Station", "Apple Music 1") MUST be recognized as radio
        XCTAssertTrue(PlayerStatusEngine.isLikelyRadioPlaylistName("Моя станция", activeStationName: "Моя станция", isCurrentlyRadio: true))
        XCTAssertTrue(PlayerStatusEngine.isLikelyRadioPlaylistName("Моя станция", activeStationName: nil, isCurrentlyRadio: false))
        XCTAssertTrue(PlayerStatusEngine.isLikelyRadioPlaylistName("Discovery Station", activeStationName: nil, isCurrentlyRadio: false))
        XCTAssertTrue(PlayerStatusEngine.isLikelyRadioPlaylistName("Apple Music 1", activeStationName: nil, isCurrentlyRadio: false))
        // Master library containers are NOT radio
        XCTAssertFalse(PlayerStatusEngine.isLikelyRadioPlaylistName("Музыка", activeStationName: nil, isCurrentlyRadio: false))
        XCTAssertFalse(PlayerStatusEngine.isLikelyRadioPlaylistName("Music", activeStationName: nil, isCurrentlyRadio: false))
        XCTAssertFalse(PlayerStatusEngine.isLikelyRadioPlaylistName("Очередь AMR", activeStationName: nil, isCurrentlyRadio: false))

        // Verify repeatMode = "one" pins the active radio track and preserves repeatMode in PlaybackStateStore
        let radioTrack = TrackInfo(
            id: "1440857781",
            numericId: nil,
            name: "Lebanese Blonde",
            artist: "Thievery Corporation",
            album: "The Mirror Conspiracy",
            duration: 288.0,
            hasArtwork: false,
            artworkUrl: "",
            favorited: false,
            isLocal: false,
            url: nil,
            index: 1
        )
        PlaybackStateStore.shared.resetPlaybackState(isRadio: true, stationName: "Моя станция")
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastPlayerStatusCache = (
                Date(),
                PlayerStatus(
                    playerState: "playing",
                    position: 42.0,
                    duration: 288.0,
                    volume: 100,
                    shuffle: false,
                    repeatMode: "off",
                    playlist: "Моя станция",
                    isRadio: true,
                    audioQuality: "Lossless 24-бит/44.1 кГц",
                    track: radioTrack
                )
            )
        }

        XCTAssertTrue(PlaybackTransportController.shared.setRepeat(mode: "one"))
        let (repMode, pinned) = PlaybackStateStore.shared.withLock {
            (PlaybackStateStore.shared.repeatMode, PlaybackStateStore.shared.repeatOnePinnedTrack)
        }
        XCTAssertEqual(repMode, "one")
        XCTAssertEqual(pinned?.name, "Lebanese Blonde")

        // Manual nextTrack clears repeatOnePinnedTrack so the newly skipped radio song becomes the next pinned track
        _ = PlaybackTransportController.shared.nextTrack()
        let pinnedAfterSkip = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.repeatOnePinnedTrack }
        XCTAssertNil(pinnedAfterSkip)
    }

    // MARK: - 10. Pre-DSP Sample Rate Reconfiguration (48 kHz -> 96 kHz -> 192 kHz -> 44.1 kHz)

    func testPreDSPLocalPassthroughSampleRateTransitionsAndSelfHealing() {
        let roomSvc = RoomAcousticService(userDefaults: defaultsA, isIsolatedInstance: true)
        let drcProc = LateNightDRCProcessor()
        drcProc.setMode(.concert)

        let bands = RoomAcousticService.isoThirdOctaveBandsHz
        let eqBand = RoomEQBand(frequencyHz: 125.0, gainDB: -4.5, q: 2.2, filterType: "peaking")
        let profile = RoomAcousticProfile(
            name: "Living Room Test",
            measuredOnDevice: "iPhone Test",
            bandsHz: bands,
            measuredResponseDB: [Double](repeating: 0.0, count: bands.count),
            targetCurveDB: [Double](repeating: 0.0, count: bands.count),
            correctedResponseDB: [Double](repeating: 0.0, count: bands.count),
            maxPeakDeviationDB: 4.5,
            eqBands: [eqBand],
            preampGainDB: -1.0
        )
        roomSvc.saveMeasuredProfile(profile, autoEnable: true)
        roomSvc.setSimulatedLocalPassthroughActiveForTesting(true, initialSampleRateHz: 48_000.0)
        defer {
            roomSvc.setSimulatedLocalPassthroughActiveForTesting(false)
        }

        XCTAssertTrue(roomSvc.isLocalPassthroughEQActive)
        XCTAssertEqual(roomSvc.currentLocalPassthroughSampleRate, 48_000.0, accuracy: 0.5)

        func feedAndRenderSine(rate: Int, blockFrames: Int = 1024, blocks: Int = 4) -> (firstSampleAbs: Float, tailRMS: Double, maxPeak: Float) {
            var inL = [Float](repeating: 0.0, count: blockFrames)
            var inR = [Float](repeating: 0.0, count: blockFrames)
            var outL = [Float](repeating: 0.0, count: blockFrames)
            var outR = [Float](repeating: 0.0, count: blockFrames)

            var firstSampleAbs: Float = -1.0
            var maxPeak: Float = 0.0
            var tailSumSq: Double = 0.0
            let srD = Double(rate)
            var sampleCursor = 0

            for b in 0..<blocks {
                for i in 0..<blockFrames {
                    let s = Float(sin(2.0 * Double.pi * 440.0 * Double(sampleCursor) / srD) * 0.25)
                    inL[i] = s
                    inR[i] = s
                    sampleCursor += 1
                }
                roomSvc.feedLocalPassthroughPlanarFloat32(left: inL, right: inR, frames: blockFrames, sampleRate: rate)
                roomSvc.renderLocalPassthroughFramesForTesting(
                    leftOut: &outL,
                    rightOut: &outR,
                    frames: blockFrames,
                    useStartupCushion: false,
                    customDRCProcessor: drcProc
                )
                if b == 0 {
                    firstSampleAbs = abs(outL[0])
                }
                for i in 0..<blockFrames {
                    XCTAssertTrue(outL[i].isFinite && outR[i].isFinite, "Rendered Pre-DSP sample must be finite at \(rate) Hz")
                    maxPeak = max(maxPeak, abs(outL[i]), abs(outR[i]))
                    if b == blocks - 1 {
                        tailSumSq += Double(outL[i] * outL[i])
                    }
                }
            }
            let tailRMS = sqrt(tailSumSq / Double(blockFrames))
            return (firstSampleAbs, tailRMS, maxPeak)
        }

        // 1. Track 1 at 48 kHz / 24-bit
        let res48 = feedAndRenderSine(rate: 48_000)
        XCTAssertEqual(roomSvc.localPassthroughProcessor.activeSampleRateHz, 48_000)
        XCTAssertEqual(drcProc.activeSampleRateHz, 48_000.0, accuracy: 0.5)
        XCTAssertEqual(res48.firstSampleAbs, 0.0, accuracy: 1e-5, "Initial block must start with smooth 0.0 fade-in")
        XCTAssertGreaterThan(res48.tailRMS, 0.05, "Steady-state 48 kHz Pre-DSP output must have healthy signal energy")
        XCTAssertLessThanOrEqual(res48.maxPeak, 0.90)

        // Seed leftover 48 kHz samples in ring buffer to verify transition flushes stale frames cleanly
        let stale48 = [Float](repeating: 0.77, count: 512)
        roomSvc.feedLocalPassthroughPlanarFloat32(left: stale48, right: stale48, frames: 512, sampleRate: 48_000)

        // 2. Track 2 switches source & DAC to 96 kHz / 24-bit
        let reconfigBefore96 = roomSvc.localPassthroughReconfigCount
        roomSvc.notifyLocalOutputFormatChanged(sampleRateHz: 96_000.0)
        XCTAssertEqual(roomSvc.localPassthroughReconfigCount, reconfigBefore96 + 1)
        XCTAssertEqual(roomSvc.currentLocalPassthroughSampleRate, 96_000.0, accuracy: 0.5)

        // Verify ring buffer was flushed (rendering before new 96 kHz frames arrive produces clean silence, not stale 0.77!)
        var checkEmptyL = [Float](repeating: 1.0, count: 128)
        var checkEmptyR = [Float](repeating: 1.0, count: 128)
        roomSvc.renderLocalPassthroughFramesForTesting(
            leftOut: &checkEmptyL,
            rightOut: &checkEmptyR,
            frames: 128,
            useStartupCushion: false,
            customDRCProcessor: drcProc
        )
        XCTAssertTrue(checkEmptyL.allSatisfy { $0 == 0.0 }, "Ring buffer must flush stale 48 kHz frames on 96 kHz transition")

        let res96 = feedAndRenderSine(rate: 96_000)
        XCTAssertEqual(roomSvc.localPassthroughProcessor.activeSampleRateHz, 96_000)
        XCTAssertEqual(drcProc.activeSampleRateHz, 96_000.0, accuracy: 0.5)
        XCTAssertGreaterThan(res96.tailRMS, 0.05, "Steady-state 96 kHz Pre-DSP output must play cleanly without packet loss")
        XCTAssertLessThanOrEqual(res96.maxPeak, 0.90)

        // 3. Reactive self-healing: feed 192 kHz frames directly before explicit notification arrives
        let reconfigBefore192 = roomSvc.localPassthroughReconfigCount
        let burst192 = [Float](repeating: 0.12, count: 512)
        roomSvc.feedLocalPassthroughPlanarFloat32(left: burst192, right: burst192, frames: 512, sampleRate: 192_000)

        let exp192 = expectation(description: "Async self-healing reconfigures Pre-DSP to 192 kHz")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.08) {
            exp192.fulfill()
        }
        wait(for: [exp192], timeout: 1.0)
        XCTAssertEqual(roomSvc.currentLocalPassthroughSampleRate, 192_000.0, accuracy: 0.5)
        XCTAssertGreaterThan(roomSvc.localPassthroughReconfigCount, reconfigBefore192)

        // 4. Downward transition 192 kHz -> 44.1 kHz
        roomSvc.notifyLocalOutputFormatChanged(sampleRateHz: 44_100.0)
        let res44 = feedAndRenderSine(rate: 44_100)
        XCTAssertEqual(roomSvc.currentLocalPassthroughSampleRate, 44_100.0, accuracy: 0.5)
        XCTAssertEqual(roomSvc.localPassthroughProcessor.activeSampleRateHz, 44_100)
        XCTAssertEqual(drcProc.activeSampleRateHz, 44_100.0, accuracy: 0.5)
        XCTAssertGreaterThan(res44.tailRMS, 0.05)
    }

    func testBitPerfectMonitorPropagatesSampleRateSwitchToLocalPreDSPAndTap() {
        let prevEnabled = BitPerfectLogMonitor.shared.isEnabled
        BitPerfectLogMonitor.shared.isEnabled = true
        RoomAcousticService.shared.setSimulatedLocalPassthroughActiveForTesting(true, initialSampleRateHz: 48_000.0)
        defer {
            RoomAcousticService.shared.setSimulatedLocalPassthroughActiveForTesting(false)
            BitPerfectLogMonitor.shared.isEnabled = prevEnabled
            BitPerfectLogMonitor.shared.resetTrackStateSyncForTesting()
        }

        // Track 1: 48 kHz / 24-bit ALAC
        BitPerfectLogMonitor.shared.resetTrackStateSyncForTesting(trackKey: "olafur arnalds:nyepi")
        BitPerfectLogMonitor.shared.processLogMessageForTesting(
            "ACAppleLosslessDecoder.cpp:680 Input format: 2 ch, 48000 Hz, alac (0x00000003) from 24-bit source, 4096 frames/packet"
        )
        let exp1 = expectation(description: "Tap queue processes 48 kHz")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { exp1.fulfill() }
        wait(for: [exp1], timeout: 1.0)
        XCTAssertEqual(RoomAcousticService.shared.currentLocalPassthroughSampleRate, 48_000.0, accuracy: 0.5)
        XCTAssertEqual(AudioProcessTapService.shared.sampleRate, 48_000)

        // Track 2: 96 kHz / 24-bit ALAC (exact user repro: 48/24 -> 96/24 with Late-Night ON)
        BitPerfectLogMonitor.shared.resetTrackStateSyncForTesting(trackKey: "olafur arnalds:saman")
        BitPerfectLogMonitor.shared.processLogMessageForTesting(
            "ACAppleLosslessDecoder.cpp:680 Input format: 2 ch, 96000 Hz, alac (0x00000003) from 24-bit source, 4096 frames/packet"
        )
        let exp2 = expectation(description: "Tap queue processes 96 kHz")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { exp2.fulfill() }
        wait(for: [exp2], timeout: 1.0)
        XCTAssertEqual(RoomAcousticService.shared.currentLocalPassthroughSampleRate, 96_000.0, accuracy: 0.5)
        XCTAssertEqual(AudioProcessTapService.shared.sampleRate, 96_000)

        // Track 3: 44.1 kHz / 16-bit ALAC downward switch
        BitPerfectLogMonitor.shared.resetTrackStateSyncForTesting(trackKey: "test artist:redbook track")
        BitPerfectLogMonitor.shared.processLogMessageForTesting(
            "ACAppleLosslessDecoder.cpp:680 Input format: 2 ch, 44100 Hz, alac (0x00000001) from 16-bit source, 4096 frames/packet"
        )
        let exp3 = expectation(description: "Tap queue processes 44.1 kHz")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { exp3.fulfill() }
        wait(for: [exp3], timeout: 1.0)
        XCTAssertEqual(RoomAcousticService.shared.currentLocalPassthroughSampleRate, 44_100.0, accuracy: 0.5)
        XCTAssertEqual(AudioProcessTapService.shared.sampleRate, 44_100)
    }

    func testSDMAndNOSUpscalerPreDSPIsolatedAndAdaptsSampleRates() {
        let roomSvc = RoomAcousticService(userDefaults: defaultsA, isIsolatedInstance: true)
        let bands = RoomAcousticService.isoThirdOctaveBandsHz
        let profile = RoomAcousticProfile(
            name: "SDM Room EQ",
            measuredOnDevice: "iPhone 16 Pro",
            bandsHz: bands,
            measuredResponseDB: [Double](repeating: 0.0, count: bands.count),
            targetCurveDB: [Double](repeating: 0.0, count: bands.count),
            correctedResponseDB: [Double](repeating: 0.0, count: bands.count),
            maxPeakDeviationDB: 3.5,
            eqBands: [
                RoomEQBand(frequencyHz: 75.0, gainDB: -3.5, q: 3.5, filterType: "peaking"),
                RoomEQBand(frequencyHz: 3200.0, gainDB: 1.5, q: 1.4, filterType: "peaking")
            ],
            preampGainDB: -1.5
        )
        roomSvc.saveMeasuredProfile(profile, autoEnable: true)

        let drcSvc = LateNightDRCService(userDefaults: defaultsA, suiteKeyPrefix: "test.sdm.drc", isIsolated: true)
        drcSvc.setMode(.concert)

        // Verify Local Passthrough AudioUnit remains completely inactive while 64-bit DSP Engine processors adapt across 48 -> 96 -> 192 -> 44.1 kHz
        XCTAssertFalse(roomSvc.isLocalPassthroughEQActive)

        for rate in [48_000, 96_000, 192_000, 44_100] {
            let frames = 512
            var left = [Double](repeating: 0.0, count: frames)
            var right = [Double](repeating: 0.0, count: frames)
            for i in 0..<frames {
                let phase = 2.0 * Double.pi * 440.0 * Double(i) / Double(rate)
                let s = 0.25 * sin(phase)
                left[i] = s
                right[i] = s
            }
            left.withUnsafeMutableBufferPointer { lBuf in
                right.withUnsafeMutableBufferPointer { rBuf in
                    roomSvc.processPlanarDoubleIfEnabled(
                        left: lBuf.baseAddress!,
                        right: rBuf.baseAddress!,
                        frameCount: frames,
                        sampleRate: rate
                    )
                    drcSvc.processPlanarDoubleIfEnabled(
                        left: lBuf.baseAddress!,
                        right: rBuf.baseAddress!,
                        frameCount: frames,
                        sampleRate: Double(rate)
                    )
                }
            }
            XCTAssertEqual(roomSvc.dspEngineProcessor.activeSampleRateHz, rate)
            XCTAssertEqual(drcSvc.dspEngineProcessor.activeSampleRateHz, Double(rate), accuracy: 0.5)
            // Isolated from Local Passthrough Float32 processor
            XCTAssertEqual(roomSvc.localPassthroughProcessor.activeSampleRateHz, 0)
            let rms = sqrt(left.reduce(0.0) { $0 + $1 * $1 } / Double(frames))
            XCTAssertTrue(rms.isFinite && rms > 0.05 && rms < 1.0, "64-bit SDM/NOS Pre-DSP output invalid at \(rate) Hz (rms=\(rms))")
        }
    }
}
