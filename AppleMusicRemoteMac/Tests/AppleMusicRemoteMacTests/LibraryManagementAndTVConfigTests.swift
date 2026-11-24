//
//  LibraryManagementAndTVConfigTests.swift
//  AppleMusicRemoteMacTests
//
//  Unit tests covering:
//  1. StandBy TV Mode Library Tile Configuration (TVLibraryConfigurationStore persistence, validation, dict sync)
//  2. Crash-Proof Pending Staged Catalog Track Pre-Journal & Permanent Track Removal
//  3. Token-Boundary Artist Matching for Safe Library Artist Deletion
//  4. Album Completeness & Library Section DTOs (LibraryRecentResponse, ArtistLibraryDetailResponse)
//

import CoreAudio
import XCTest
@testable import AppleMusicRemoteMac

final class LibraryManagementAndTVConfigTests: XCTestCase {

    private var suiteName: String!
    private var isolatedDefaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "com.amr.tests.tvlib.\(UUID().uuidString)"
        isolatedDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        if let suiteName {
            isolatedDefaults?.removePersistentDomain(forName: suiteName)
        }
        try super.tearDownWithError()
    }

    // MARK: - 1. StandBy TV Library Configuration Store

    func testTVLibraryConfigurationStorePersistenceValidationAndDictionarySync() {
        let key = "AMRTVConfigTestKey"
        let store1 = TVLibraryConfigurationStore(userDefaults: isolatedDefaults, storageKey: key)

        // Default configuration: all 4 core tiles ON, playlists = "all", albums = "recent"
        let initial = store1.current
        XCTAssertTrue(initial.showMyStation)
        XCTAssertTrue(initial.showDiscoveryStation)
        XCTAssertTrue(initial.showFavoritesMix)
        XCTAssertTrue(initial.showHeavyRotation)
        XCTAssertEqual(initial.playlistsMode, "all")
        XCTAssertEqual(initial.albumsMode, "recent")

        let albKey1 = TVLibraryConfigurationStore.makeAlbumSelectionKey(name: "re:member", artist: "Ólafur Arnalds")
        let albKey2 = TVLibraryConfigurationStore.makeAlbumSelectionKey(name: "RE:MEMBER", artist: "Olafur Arnalds")
        XCTAssertEqual(albKey1, albKey2, "Album selection keys must fold diacritics and case deterministically")

        // Mutate & deduplicate
        let updated = store1.update { cfg in
            cfg.showDiscoveryStation = false
            cfg.showHeavyRotation = false
            cfg.playlistsMode = "selected"
            cfg.selectedPlaylistNames = ["Jazz Late Night", "Jazz Late Night", "  Audiophile Reference  "]
            cfg.albumsMode = "selected"
            cfg.selectedAlbums = [
                TVLibraryAlbumSelection(key: albKey1, id: "1401234567", name: "re:member", artist: "Ólafur Arnalds"),
                TVLibraryAlbumSelection(key: albKey2, id: "1401234567", name: "re:member", artist: "Ólafur Arnalds")
            ]
        }

        XCTAssertFalse(updated.showDiscoveryStation)
        XCTAssertFalse(updated.showHeavyRotation)
        XCTAssertEqual(updated.playlistsMode, "selected")
        XCTAssertEqual(updated.selectedPlaylistNames.count, 2, "Duplicate playlist names must be deduplicated")
        XCTAssertEqual(updated.albumsMode, "selected")
        XCTAssertEqual(updated.selectedAlbums.count, 1, "Duplicate album keys must be deduplicated")

        // Reload from persisted UserDefaults in a fresh store instance
        let store2 = TVLibraryConfigurationStore(userDefaults: isolatedDefaults, storageKey: key)
        XCTAssertEqual(store2.current, updated)

        // Dictionary round-trip & invalid mode fallback
        let dict = store2.toDictionary()
        XCTAssertEqual(dict["show_my_station"] as? Bool, true)
        XCTAssertEqual(dict["show_discovery_station"] as? Bool, false)
        XCTAssertEqual(dict["playlists_mode"] as? String, "selected")
        XCTAssertEqual(dict["albums_mode"] as? String, "selected")
        XCTAssertEqual((dict["selected_album_keys"] as? [String])?.first, albKey1)

        let store3 = TVLibraryConfigurationStore(userDefaults: isolatedDefaults, storageKey: "AMRTVConfigTestKey2")
        let applied = store3.applyDictionary([
            "show_my_station": false,
            "playlists_mode": "invalid_mode",
            "albums_mode": "none"
        ])
        XCTAssertFalse(applied.showMyStation)
        XCTAssertEqual(applied.playlistsMode, "all", "Invalid playlists_mode must fall back safely to 'all'")
        XCTAssertEqual(applied.albumsMode, "none")
    }

    // MARK: - 2. Crash-Proof Pending Staged Catalog Track Pre-Journal

    func testPendingStagedCatalogTrackPreJournalAndPermanentRemoval() {
        let testCatId = "9988776655"
        PlaybackStateStore.shared.clearPendingStagedCatalogTrack(catalogId: testCatId, name: "Crash Test Song", artist: "Test Artist")

        PlaybackStateStore.shared.recordPendingStagedCatalogTrack(
            catalogId: testCatId,
            name: "Crash Test Song",
            artist: "Test Artist",
            album: "Crash Test Album"
        )

        let snapAfterRecord = PlaybackStateStore.shared.pendingStagedCatalogTracksSnapshot()
        XCTAssertTrue(
            snapAfterRecord.contains { $0.catalogId == testCatId && $0.name == "Crash Test Song" },
            "Pre-journal must record pending catalog track before HTTP stage request"
        )

        PlaybackStateStore.shared.clearPendingStagedCatalogTrack(
            catalogId: testCatId,
            name: "Crash Test Song",
            artist: "Test Artist"
        )
        let snapAfterClear = PlaybackStateStore.shared.pendingStagedCatalogTracksSnapshot()
        XCTAssertFalse(
            snapAfterClear.contains { $0.catalogId == testCatId },
            "Clearing pending staged track must remove it cleanly"
        )

        // Verify promote -> explicit user removal clears permanentlySavedTrackKeys
        PlaybackStateStore.shared.promoteStagedTrackForSavedSong(
            dbId: nil,
            catalogId: testCatId,
            name: "Saved Song",
            artist: "Saved Artist"
        )
        XCTAssertTrue(
            PlaybackStateStore.shared.isTrackPermanentlySaved(id: testCatId, name: "Saved Song", artist: "Saved Artist")
        )

        PlaybackStateStore.shared.removePermanentlySavedTrack(
            id: testCatId,
            name: "Saved Song",
            artist: "Saved Artist"
        )
        XCTAssertFalse(
            PlaybackStateStore.shared.isTrackPermanentlySaved(id: testCatId, name: "Saved Song", artist: "Saved Artist"),
            "Explicit library removal must clear permanentlySavedTrackKeys"
        )
    }

    // MARK: - 3. Safe Token-Boundary Artist Matching for Library Deletion

    func testArtistMatchesLibraryTargetRespectsTokenBoundariesAndDiacritics() {
        XCTAssertTrue(LibraryService.artistMatchesLibraryTarget(trackArtist: "Queen", targetArtist: "Queen"))
        XCTAssertTrue(LibraryService.artistMatchesLibraryTarget(trackArtist: "Queen & David Bowie", targetArtist: "Queen"))
        XCTAssertTrue(LibraryService.artistMatchesLibraryTarget(trackArtist: "Queen feat. Paul Rodgers", targetArtist: "Queen"))
        XCTAssertTrue(LibraryService.artistMatchesLibraryTarget(trackArtist: "Ólafur Arnalds", targetArtist: "Olafur Arnalds"))

        // Must NEVER false-match artists sharing a prefix!
        XCTAssertFalse(
            LibraryService.artistMatchesLibraryTarget(trackArtist: "Queens of the Stone Age", targetArtist: "Queen"),
            "Deleting 'Queen' must NEVER match 'Queens of the Stone Age'"
        )
        XCTAssertFalse(
            LibraryService.artistMatchesLibraryTarget(trackArtist: "Queen Latifah", targetArtist: "Queen"),
            "Deleting 'Queen' must NEVER match 'Queen Latifah'"
        )
    }

    // MARK: - 4. Album Completeness & Recorded Album Removal

    func testAlbumCompletenessDTOSerializationAndRecordedAlbumRemoval() throws {
        let partialAlbum = AlbumInfo(
            id: "42",
            name: "re:member",
            artist: "Ólafur Arnalds",
            artwork: "/api/artwork/track?id=42",
            releaseDate: "2018-08-24",
            trackCount: 3,
            tracks: [],
            inLibrary: true,
            libraryTrackCount: 3,
            catalogTrackCount: 12,
            catalogAlbumId: "1396528379",
            isCompleteInLibrary: false,
            isLibraryView: true,
            dateAdded: 1_760_000_000.0
        )

        let data = try JSONEncoder().encode(partialAlbum)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["in_library"] as? Bool, true)
        XCTAssertEqual(json["is_complete_in_library"] as? Bool, false)
        XCTAssertEqual(json["is_library_view"] as? Bool, true)
        XCTAssertEqual(json["library_track_count"] as? Int, 3)
        XCTAssertEqual(json["catalog_track_count"] as? Int, 12)
        XCTAssertEqual(json["catalog_album_id"] as? String, "1396528379")

        let decoded = try JSONDecoder().decode(AlbumInfo.self, from: data)
        XCTAssertEqual(decoded.isCompleteInLibrary, false)
        XCTAssertEqual(decoded.libraryTrackCount, 3)
        XCTAssertEqual(decoded.catalogTrackCount, 12)
        XCTAssertEqual(decoded.catalogAlbumId, "1396528379")

        // Verify MusicKitManager session-added album removal
        MusicKitManager.shared.recordAddedAlbumToLibrary(
            albumId: "1396528379",
            name: "UnitTestTempAlbum",
            artist: "UnitTestTempArtist",
            artwork: "",
            trackCount: 12
        )
        XCTAssertTrue(
            MusicKitManager.shared.isAlbumInLibraryOrRecentlyAdded(
                albumId: "1396528379",
                name: "UnitTestTempAlbum",
                artist: "UnitTestTempArtist"
            )
        )
        let removed = MusicKitManager.shared.removeRecordedAlbumFromLibrary(
            albumId: "1396528379",
            name: "UnitTestTempAlbum",
            artist: "UnitTestTempArtist"
        )
        XCTAssertTrue(removed)
        XCTAssertFalse(
            MusicKitManager.shared.isExplicitlyAddedAlbumInSession(
                albumId: "1396528379",
                name: "UnitTestTempAlbum",
                artist: "UnitTestTempArtist"
            )
        )

        // Verify mergeLibraryAlbums excludes cloud albums whose only presence is a temporary staged song
        PlaybackStateStore.shared.registerStagedTemporaryTrack(dbId: 777001)
        PlaybackStateStore.shared.setTrackMetadata(id: 777001, name: "Staged Single", artist: "Staged Artist", album: "Staged Cloud Album")
        defer {
            PlaybackStateStore.shared.unregisterStagedTemporaryTrack(dbId: 777001)
        }

        let cloudList = [
            AlbumInfo(id: "1555000111", name: "Staged Cloud Album", artist: "Staged Artist", artwork: "", trackCount: 1, inLibrary: true),
            AlbumInfo(id: "1555000222", name: "Real Saved Cloud Album", artist: "Real Artist", artwork: "", trackCount: 10, inLibrary: true)
        ]
        let merged = MusicBridge.mergeLibraryAlbums(cloud: cloudList, local: [], recentlyAdded: [])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.name, "Real Saved Cloud Album")
    }

    // MARK: - 5. Playlist Removal Guardrails & Library Isolation

    func testProtectedSystemPlaylistsAndPlaylistRemovalPreservesLibraryTracks() async {
        XCTAssertTrue(PlaybackRouter.shared.isTestingEnvironment)

        XCTAssertTrue(LibraryService.isProtectedSystemPlaylist("Музыка"))
        XCTAssertTrue(LibraryService.isProtectedSystemPlaylist("Music"))
        XCTAssertTrue(LibraryService.isProtectedSystemPlaylist("Любимые песни"))
        XCTAssertTrue(LibraryService.isProtectedSystemPlaylist("Favorites"))
        XCTAssertTrue(LibraryService.isProtectedSystemPlaylist("Очередь AMR"))
        XCTAssertFalse(LibraryService.isProtectedSystemPlaylist("Jazz Late Night"))
        XCTAssertFalse(LibraryService.isProtectedSystemPlaylist("✨ Очередь AMR (16.11)"))

        // Protected system playlist must never be deleted
        let protectedDeleted = await LibraryService.shared.removePlaylistFromLibrary(
            playlistId: nil,
            name: "Любимые песни"
        )
        XCTAssertFalse(protectedDeleted)

        // Playlist deletion removes only the playlist and preserves saved library tracks
        let catId = "1777888999"
        PlaybackStateStore.shared.promoteStagedTrackForSavedSong(
            dbId: nil,
            catalogId: catId,
            name: "Night Train",
            artist: "Oscar Peterson"
        )

        _ = await LibraryService.shared.removePlaylistFromLibrary(
            playlistId: "p.test1",
            name: "Jazz Late Night"
        )
        XCTAssertTrue(
            PlaybackStateStore.shared.isTrackPermanentlySaved(id: catId, name: "Night Train", artist: "Oscar Peterson"),
            "Deleting a playlist must never remove saved tracks from the user's library"
        )
    }

    // MARK: - 6. CoreAudio 3-Stage USB DAC Validator for DSD (DoP) & HQ NOS PCM

    func testCoreAudioUSBDACCapabilityEvaluationBlocksBuiltInAndNonHiResUSB() {
        // 1. Built-in MacBook Speakers (96 kHz / 32-bit float) MUST be blocked from NOS & DSD
        let builtIn = CoreAudioDeviceManager.evaluateDSPCapabilities(
            rawTransport: kAudioDeviceTransportTypeBuiltIn,
            name: "Динамики MacBook Air",
            uid: "BuiltInSpeakerDevice",
            availableRates: [44_100, 48_000, 88_200, 96_000],
            maxBitDepth: 32,
            hasStereoOutput: true
        )
        XCTAssertEqual(builtIn.transportType, "builtin")
        XCTAssertFalse(builtIn.isUSB)
        XCTAssertFalse(builtIn.supportsNOS)
        XCTAssertFalse(builtIn.supportsDSDDoP)
        XCTAssertEqual(builtIn.maxDSDRate, 0)

        // 2. Bluetooth / HDMI / Virtual Aggregate MUST be blocked even if reporting high sample rates
        for rawTransport in [kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeVirtual] {
            let nonUSB = CoreAudioDeviceManager.evaluateDSPCapabilities(
                rawTransport: rawTransport,
                name: "External Non-USB Output",
                uid: "Ext-Non-USB",
                availableRates: [44_100, 176_400, 352_800, 705_600],
                maxBitDepth: 32,
                hasStereoOutput: true
            )
            XCTAssertFalse(nonUSB.isUSB)
            XCTAssertFalse(nonUSB.supportsNOS)
            XCTAssertFalse(nonUSB.supportsDSDDoP)
        }

        // 3. Cheap 16-bit / 48 kHz USB Headset MUST be blocked (prevents DoP white noise & broken stream)
        let usbHeadset = CoreAudioDeviceManager.evaluateDSPCapabilities(
            rawTransport: kAudioDeviceTransportTypeUSB,
            name: "USB Conference Headset",
            uid: "USB-Headset-16bit",
            availableRates: [44_100, 48_000],
            maxBitDepth: 16,
            hasStereoOutput: true
        )
        XCTAssertTrue(usbHeadset.isUSB)
        XCTAssertFalse(usbHeadset.supportsNOS)
        XCTAssertFalse(usbHeadset.supportsDSDDoP)
        XCTAssertEqual(usbHeadset.maxDSDRate, 0)

        // 4. USB-to-S/PDIF Bridge (24-bit, up to 192 kHz including 176.4 kHz) -> NOS + DSD64 DoP
        let usbSpdif = CoreAudioDeviceManager.evaluateDSPCapabilities(
            rawTransport: kAudioDeviceTransportTypeUSB,
            name: "USB S/PDIF Converter",
            uid: "USB-SPDIF-24-192",
            availableRates: [44_100, 48_000, 88_200, 96_000, 176_400, 192_000],
            maxBitDepth: 24,
            hasStereoOutput: true
        )
        XCTAssertTrue(usbSpdif.isUSB)
        XCTAssertTrue(usbSpdif.supportsNOS)
        XCTAssertTrue(usbSpdif.supportsDSDDoP)
        XCTAssertEqual(usbSpdif.maxDSDRate, 64)

        // 5. External USB UAC2 Hi-Res DAC (32-bit, up to 768 kHz) -> NOS + DSD256 DoP
        let usbHiRes = CoreAudioDeviceManager.evaluateDSPCapabilities(
            rawTransport: kAudioDeviceTransportTypeUSB,
            name: "SMSL PO100 PRO",
            uid: "SMSL-UAC2-768",
            availableRates: [44_100, 48_000, 88_200, 96_000, 176_400, 192_000, 352_800, 384_000, 705_600, 768_000],
            maxBitDepth: 32,
            hasStereoOutput: true
        )
        XCTAssertTrue(usbHiRes.isUSB)
        XCTAssertTrue(usbHiRes.supportsNOS)
        XCTAssertTrue(usbHiRes.supportsDSDDoP)
        XCTAssertEqual(usbHiRes.maxDSDRate, 256)
    }

    // MARK: - 7. Radio Shuffle & Repeat-Queue Blocking (Repeat-One Allowed)

    func testRadioDisablesShuffleAndRepeatAllWhileKeepingRepeatOne() {
        defer {
            PlaybackStateStore.shared.resetCustomQueue()
        }

        // Pre-set Repeat All before entering Radio -> resetPlaybackState(isRadio: true) must downgrade "all" -> "off"
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.repeatMode = "all"
            PlaybackStateStore.shared.isShuffleQueueActive = true
        }
        PlaybackStateStore.shared.resetPlaybackState(isRadio: true, stationName: "Моя станция")

        let (initialRadio, initialShuf, initialRep) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isRadioPlayback,
                PlaybackStateStore.shared.isShuffleQueueActive,
                PlaybackStateStore.shared.repeatMode
            )
        }
        XCTAssertTrue(initialRadio)
        XCTAssertFalse(initialShuf)
        XCTAssertEqual(initialRep, "off")

        // Enabling shuffle during Radio must be rejected
        XCTAssertFalse(PlaybackTransportController.shared.setShuffle(true))
        XCTAssertFalse(PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isShuffleQueueActive })

        // Repeat One ("one") MUST be allowed during Radio
        XCTAssertTrue(PlaybackTransportController.shared.setRepeat(mode: "one"))
        XCTAssertEqual(PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.repeatMode }, "one")

        // Repeat Queue ("all") MUST be rejected and fall back to "off" during Radio
        XCTAssertFalse(PlaybackTransportController.shared.setRepeat(mode: "all"))
        XCTAssertEqual(PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.repeatMode }, "off")
    }

    // MARK: - 8. Playlist-Isolated Staging Buffer ("Буфер AMR") Never Pollutes Library

    func testStagingBufferCacheNeverPollutesMainLibraryCache() {
        LibraryService.shared.invalidateLibrarySongsCache()
        LibraryService.shared.clearStagedBufferCache()
        defer {
            LibraryService.shared.clearStagedBufferCache()
            PlaybackStateStore.shared.unregisterStagedTemporaryTrack(dbId: 912_345)
        }

        XCTAssertTrue(LibraryService.isProtectedSystemPlaylist("Буфер AMR"))
        XCTAssertFalse(
            PlayerStatusEngine.isLikelyRadioPlaylistName(
                "Буфер AMR",
                activeStationName: nil,
                isCurrentlyRadio: true
            )
        )

        PlaybackStateStore.shared.registerStagedTemporaryTrack(dbId: 912_345)
        LibraryService.shared.registerStagedTrackInCache(
            dbId: 912_345,
            name: "Flowers and Dreams",
            artist: "F/ACE",
            album: "Anime Single",
            duration: 215
        )

        // Main library cache MUST stay completely untouched
        XCTAssertTrue(LibraryService.shared.getCachedLibrarySongs().isEmpty)

        // Queue resolver with includeStagedTemporary=true resolves numericId for playback while keeping isLocal=false
        let probe = TrackInfo(
            id: "1790001122",
            numericId: nil,
            name: "Flowers and Dreams",
            artist: "F/ACE",
            album: "Anime Single",
            duration: 215,
            isLocal: false,
            url: "https://music.apple.com/us/album/x/1?i=1790001122"
        )
        let forPlayback = LibraryService.shared.resolveLocalLibraryMatches([probe], includeStagedTemporary: true)
        XCTAssertEqual(forPlayback.first?.numericId, 912_345)
        XCTAssertEqual(forPlayback.first?.isLocal, false)

        // UI / catalog resolver with includeStagedTemporary=false does NOT match the buffer track
        let forUI = LibraryService.shared.resolveLocalLibraryMatches([probe], includeStagedTemporary: false)
        XCTAssertNil(forUI.first?.numericId)
        XCTAssertEqual(forUI.first?.isLocal, false)

        // Clearing buffer wipes staging lookup immediately (e.g. when switching to Radio or another playlist)
        LibraryService.shared.clearStagedBufferCache()
        let afterClear = LibraryService.shared.resolveLocalLibraryMatches([probe], includeStagedTemporary: true)
        XCTAssertNil(afterClear.first?.numericId)
    }

    // MARK: - 9. Instant Optimistic Playlist Addition & Reusable "Буфер AMR" Container Retention

    func testRecentlyAddedPlaylistAppearsImmediatelyInGetPlaylistsAndRemovesCleanly() async {
        let plId = "pl.2a95256367dd4edd8f3f450e1e04bed2"
        let plName = "Электронная музыка 90-х: главное [UnitTest]"
        let plArt = "https://is1-ssl.mzstatic.com/image/thumb/Features/90s.jpg/600x600bb.jpg"
        defer {
            LibraryService.shared.removeRecentlyAddedPlaylist(id: plId, name: plName)
            LibraryService.shared.invalidatePlaylistsCache()
        }

        LibraryService.shared.recordRecentlyAddedPlaylist(
            id: plId,
            name: plName,
            trackCount: 100,
            artworkUrl: plArt
        )

        let immediate = LibraryService.shared.getPlaylists(forceRefresh: false)
        let matched = immediate.first { $0.name == plName }
        XCTAssertNotNil(matched)
        XCTAssertEqual(matched?.id, plId)
        XCTAssertEqual(matched?.trackCount, 100)
        XCTAssertEqual(matched?.artworkUrl, plArt)
        XCTAssertTrue(LibraryService.shared.hasCachedUserPlaylist(named: plName))

        let removed = await LibraryService.shared.removePlaylistFromLibrary(playlistId: plId, name: plName)
        XCTAssertTrue(removed)

        let afterRemove = LibraryService.shared.getPlaylists(forceRefresh: true)
        XCTAssertFalse(afterRemove.contains { $0.name == plName })
        XCTAssertFalse(LibraryService.shared.hasCachedUserPlaylist(named: plName))
    }

    func testCleanupTemporaryPlaybackPlaylistsPurgesAllLegacyStagingState() {
        let original = MusicKitManager.shared.reusableStagingStateSnapshot()
        defer {
            MusicKitManager.shared.configureReusableStagingStateForTesting(
                reusableId: original.reusableId,
                trackCount: original.trackCount,
                legacyTempQueueId: original.legacyTempQueueId
            )
        }

        MusicKitManager.shared.configureReusableStagingStateForTesting(
            reusableId: "p.LegacyBufferAMR01",
            trackCount: 14,
            legacyTempQueueId: "p.LegacyTempQueue99"
        )

        MusicKitManager.shared.cleanupTemporaryPlaybackPlaylists(keepingActiveQueue: false, synchronous: true)

        let afterCleanup = MusicKitManager.shared.reusableStagingStateSnapshot()
        XCTAssertNil(afterCleanup.reusableId)
        XCTAssertEqual(afterCleanup.trackCount, 0)
        XCTAssertNil(afterCleanup.legacyTempQueueId)
        XCTAssertFalse(MusicKitManager.shared.stageCloudSongsInLibrarySync(catalogIds: ["1790001122"]))
    }

    // MARK: - 10. Shuffle Queue Pre-Staging & HTTP Gzip Compression

    func testSetShuffleTriggersUpcomingCloudPrestageOnShuffledAndRestoredQueue() async {
        defer {
            PlaybackStateStore.shared.resetCustomQueue()
        }

        let cloudTracks = (1...8).map { idx in
            TrackInfo(
                id: "\(1700000000 + idx)",
                numericId: nil,
                name: "Cloud Song \(idx)",
                artist: "Artist \(idx)",
                album: "Album \(idx)",
                duration: 210,
                isLocal: false,
                url: "https://music.apple.com/us/album/x/\(1700000000 + idx)?i=\(1700000000 + idx)"
            )
        }

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isRadioPlayback = false
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = cloudTracks
            PlaybackStateStore.shared.originalCustomQueue = cloudTracks
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
        }

        let seqBefore = PlaybackRouter.currentPrestageRequestSeqForTesting()
        XCTAssertTrue(PlaybackTransportController.shared.setShuffle(true))
        let seqAfterShuffleOn = PlaybackRouter.currentPrestageRequestSeqForTesting()
        XCTAssertEqual(seqAfterShuffleOn, seqBefore + 1, "Enabling shuffle must immediately trigger pre-staging of new shuffled upcoming tracks")

        // Current track at index 0 stays pinned
        let pinnedFirst = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.activeCustomQueue.first?.id }
        XCTAssertEqual(pinnedFirst, "1700000001")

        XCTAssertTrue(PlaybackTransportController.shared.setShuffle(false))
        let seqAfterShuffleOff = PlaybackRouter.currentPrestageRequestSeqForTesting()
        XCTAssertEqual(seqAfterShuffleOff, seqAfterShuffleOn + 1, "Disabling shuffle must trigger pre-staging of restored sequential upcoming tracks")

        // Enqueueing a cloud track with playNext=true also triggers pre-staging
        let extra = TrackInfo(
            id: "1799999999",
            numericId: nil,
            name: "Extra Cloud Song",
            artist: "Extra Artist",
            album: "Extra Album",
            duration: 195,
            isLocal: false
        )
        let enqOk = await QueueManager.shared.enqueueTrack(extra, playNext: true)
        XCTAssertTrue(enqOk)
        XCTAssertEqual(PlaybackRouter.currentPrestageRequestSeqForTesting(), seqAfterShuffleOff + 1)
    }

    func testGzipCompressProducesValidRFC1952GzipPayloadAndShrinksWebAssets() {
        let sampleJS = String(repeating: "function renderPlaylistCard(item) { return item.name + ' - ' + item.artist; }\n", count: 200)
        let rawData = Data(sampleJS.utf8)
        guard let gz = WebSocketServer.gzipCompress(rawData) else {
            XCTFail("Expected gzipCompress to return non-nil Data")
            return
        }
        // RFC 1952 magic bytes: 0x1f 0x8b, compression method 0x08 (deflate)
        XCTAssertGreaterThanOrEqual(gz.count, 18)
        XCTAssertEqual(gz[0], 0x1f)
        XCTAssertEqual(gz[1], 0x8b)
        XCTAssertEqual(gz[2], 0x08)
        XCTAssertLessThan(gz.count, rawData.count / 5)
    }

    func testSingleBufferSnapshotMatchingWithoutSecondaryQueuePlaylist() {
        let snapshot: [(dbId: Int, name: String, artist: String)] = [
            (dbId: 7001, name: "Silent Crisis", artist: "Osiris"),
            (dbId: 7002, name: "雨天決行ガムシャララ", artist: "Fairy April"),
            (dbId: 7003, name: "ぐるぐるマジック (Remastered 2025)", artist: "Cure2tron & Friends")
        ]

        XCTAssertEqual(
            MusicKitManager.shared.matchTrackInStagedBufferSnapshot(
                name: "Silent Crisis",
                artist: "Osiris",
                snapshot: snapshot
            ),
            7001
        )
        XCTAssertEqual(
            MusicKitManager.shared.matchTrackInStagedBufferSnapshot(
                name: "雨天決行ガムシャララ",
                artist: "Fairy April",
                snapshot: snapshot
            ),
            7002
        )
        XCTAssertEqual(
            MusicKitManager.shared.matchTrackInStagedBufferSnapshot(
                name: "ぐるぐるマジック",
                artist: "Cure2tron",
                snapshot: snapshot
            ),
            7003
        )
        XCTAssertNil(
            MusicKitManager.shared.matchTrackInStagedBufferSnapshot(
                name: "Silent Crisis",
                artist: "Completely Different Artist",
                snapshot: snapshot
            )
        )
    }

    func testCleanupStagedTemporaryTracksPurgesStagedBufferCacheSoDeletedDbIdIsNeverReused() {
        let store = PlaybackStateStore.shared
        let originalStaged = store.withLock { store.stagedTemporaryTrackDbIds }
        defer {
            LibraryService.shared.clearStagedBufferCache()
            store.withLock { store.stagedTemporaryTrackDbIds = originalStaged }
            UserDefaults.standard.set(Array(originalStaged), forKey: "AMRStagedTemporaryTrackDbIds")
        }

        LibraryService.shared.clearStagedBufferCache()
        store.registerStagedTemporaryTrack(dbId: 7044)
        LibraryService.shared.registerStagedTrackInCache(
            dbId: 7044,
            name: "Smash the Speakers",
            artist: "Kronos",
            album: "Get Up!",
            duration: 185
        )

        let cloudInput = [
            TrackInfo(
                id: "1805405936",
                numericId: nil,
                name: "Smash the Speakers",
                artist: "Kronos",
                album: "Get Up!",
                duration: 185,
                isLocal: false,
                url: "https://music.apple.com/us/album/smash-the-speakers/1805405935?i=1805405936"
            )
        ]

        let beforeCleanup = LibraryService.shared.resolveLocalLibraryMatches(
            cloudInput,
            updateNames: false,
            includeStagedTemporary: true
        )
        XCTAssertEqual(beforeCleanup.first?.numericId, 7044)

        store.cleanupStagedTemporaryTracks(keepingActiveQueue: false)

        let afterCleanup = LibraryService.shared.resolveLocalLibraryMatches(
            cloudInput,
            updateNames: false,
            includeStagedTemporary: true
        )
        XCTAssertNil(afterCleanup.first?.numericId, "Deleted staged dbId must never remain in stagedBufferTracksByNormalizedTitle")
    }
}
