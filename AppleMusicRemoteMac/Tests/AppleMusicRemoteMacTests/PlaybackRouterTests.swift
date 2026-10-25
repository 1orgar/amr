//
//  PlaybackRouterTests.swift
//  AppleMusicRemoteMacTests
//

import XCTest
@testable import AppleMusicRemoteMac

final class PlaybackRouterTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PlaybackStateStore.shared.resetCustomQueue()
    }

    override func tearDown() {
        PlaybackStateStore.shared.resetCustomQueue()
        super.tearDown()
    }

    func testPlaybackRouterSharedExists() {
        XCTAssertNotNil(PlaybackRouter.shared)
    }

    func testPlayCustomTracksEmptyReturnsFalse() {
        let router = PlaybackRouter.shared
        let result = router.playCustomTracks([], startIndex: 0, shuffle: false, queueName: "Empty")
        XCTAssertFalse(result)
    }

    func testPlayCustomTracksPopulatesPlaybackStateStore() {
        let router = PlaybackRouter.shared
        let tracks = [
            TrackInfo(id: "10", name: "Song Ten", artist: "Artist Ten"),
            TrackInfo(id: "20", name: "Song Twenty", artist: "Artist Twenty")
        ]

        let result = router.playCustomTracks(tracks, startIndex: 1, shuffle: false, queueName: "My Queue")
        XCTAssertTrue(result)

        XCTAssertTrue(PlaybackStateStore.shared.isCustomQueuePlayback)
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueue.count, 2)
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 1)
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueName, "My Queue")
    }

    func testPlayCustomTracksShuffleKeepsFirstTrack() {
        let router = PlaybackRouter.shared
        let tracks = (1...10).map { TrackInfo(id: "\($0)", name: "Track \($0)", artist: "Artist") }

        let result = router.playCustomTracks(tracks, startIndex: 0, shuffle: true, queueName: "Shuffled")
        XCTAssertTrue(result)

        let q = PlaybackStateStore.shared.activeCustomQueue
        XCTAssertEqual(q.count, 10)
        // With startIndex = 0, first track is kept as index 0
        XCTAssertEqual(q[0].id, "1")
    }

    func testPlaySearchResultsEmptyReturnsFalse() async {
        let router = PlaybackRouter.shared
        let result = await router.playSearchResults(tracks: [], shuffle: false)
        XCTAssertFalse(result)
    }

    func testPlayStationEmptyUrlReturnsFalse() async {
        let router = PlaybackRouter.shared
        let result = await router.playStation(url: "", name: "")
        XCTAssertFalse(result)
    }

    func testPlayAlbumWithTracksEmptyReturnsFalse() async {
        let router = PlaybackRouter.shared
        let result = await router.playAlbumWithTracks(tracks: [], name: "Album", artist: "Artist")
        XCTAssertFalse(result)
    }

    func testOpenMusicUrlEmptyReturnsFalse() {
        let router = PlaybackRouter.shared
        XCTAssertFalse(router.openMusicUrl(""))
        XCTAssertFalse(router.openMusicUrl("    "))
    }

    func testPlaySearchResultsSetsUpCustomQueueState() async {
        let router = PlaybackRouter.shared
        let tracks = [
            TrackInfo(id: "c1", name: "Cloud Song 1", artist: "Artist 1", isLocal: false, url: "https://music.apple.com/station/item/ra.123"),
            TrackInfo(id: "c2", name: "Cloud Song 2", artist: "Artist 2", isLocal: false, url: "https://music.apple.com/station/item/ra.456")
        ]

        _ = await router.playSearchResults(tracks: tracks, shuffle: false)

        let store = PlaybackStateStore.shared
        XCTAssertTrue(store.isCustomQueuePlayback)
        XCTAssertFalse(store.isRadioPlayback)
        XCTAssertNil(store.activeStationName)
        XCTAssertEqual(store.activeCustomQueueName, "Результаты поиска")
        XCTAssertEqual(store.activeCustomQueue.count, 2)
        XCTAssertEqual(store.activeCustomQueue[0].name, "Cloud Song 1")
        XCTAssertEqual(store.activeCustomQueue[1].name, "Cloud Song 2")
        XCTAssertEqual(store.latestUpcomingTracks.count, 1)
        XCTAssertEqual(store.latestUpcomingTracks[0].name, "Cloud Song 2")
        XCTAssertFalse(store.hasTriggeredAdvanceForCurrentTrack)
    }

    func testPlaySearchResultsWithStartIndexSetsCorrectActiveIndexAndUpcoming() async {
        let router = PlaybackRouter.shared
        let tracks = [
            TrackInfo(id: "c1", name: "Sonne", artist: "Rammstein", isLocal: false, url: "https://music.apple.com/station/item/ra.1"),
            TrackInfo(id: "c2", name: "Du Hast", artist: "Rammstein", isLocal: false, url: "https://music.apple.com/station/item/ra.2"),
            TrackInfo(id: "c3", name: "Deutschland", artist: "Rammstein", isLocal: false, url: "https://music.apple.com/station/item/ra.3")
        ]

        // Start directly on track 1 (Du Hast)
        _ = await router.playSearchResults(tracks: tracks, startIndex: 1, shuffle: false)

        let store = PlaybackStateStore.shared
        XCTAssertTrue(store.isCustomQueuePlayback)
        XCTAssertEqual(store.activeCustomQueueIndex, 1)
        XCTAssertEqual(store.activeCustomQueue.count, 3)
        // History should contain track 0 (Sonne)
        XCTAssertEqual(store.latestHistoryTracks.count, 1)
        XCTAssertEqual(store.latestHistoryTracks[0].name, "Sonne")
        // Upcoming should contain track 2 (Deutschland)
        XCTAssertEqual(store.latestUpcomingTracks.count, 1)
        XCTAssertEqual(store.latestUpcomingTracks[0].name, "Deutschland")
    }

    func testSearchAndPlayDetailedEmptyQueryPicksStation() async {
        let router = PlaybackRouter.shared
        let res = await router.searchAndPlayDetailed(query: "")
        XCTAssertNotNil(res.station)
        let validStations = ["сейчас на повторе", "станция открытий", "моя станция"]
        XCTAssertTrue(validStations.contains(res.station ?? ""))
        XCTAssertNil(res.query)
    }

    func testPlayStationByTrackAndArtistSetsRadioState() async {
        let router = PlaybackRouter.shared
        _ = await router.playStation(
            url: "https://music.apple.com/station/item/ra.1440771222",
            name: "Станция «Mein Herz brennt»",
            type: "track",
            trackTitle: "Mein Herz brennt",
            artistName: "Rammstein"
        )
        let store = PlaybackStateStore.shared
        XCTAssertTrue(store.isRadioPlayback)
        XCTAssertEqual(store.activeStationName, "Станция «Mein Herz brennt»")
        XCTAssertFalse(store.isCustomQueuePlayback)
        XCTAssertTrue(store.activeCustomQueue.isEmpty)
    }

    func testResolveTrackStationEmptyTitleReturnsNil() async {
        let result = await MusicKitManager.shared.resolveTrackStation(title: "", artist: "")
        XCTAssertNil(result)
    }

    func testNormalizeQueryTextRemovesPunctuationAndTags() {
        let raw1 = "The Hero!! \"One Punch Man\" (Full Version)"
        let norm1 = MusicKitManager.normalizeQueryText(raw1)
        XCTAssertEqual(norm1, "the hero one punch man")

        let raw2 = "KICK BACK [Chainsaw Man OP]"
        let norm2 = MusicKitManager.normalizeQueryText(raw2)
        XCTAssertEqual(norm2, "kick back")

        let raw3 = "Uncrowned Greatest Hero (GET OVER 2021 Live Edition)"
        let norm3 = MusicKitManager.normalizeQueryText(raw3)
        XCTAssertEqual(norm3, "uncrowned greatest hero")
    }

    func testComputeSongSimilarityRejectsMismatchedGenresAndArtists() {
        // Perfect match
        let (score1, isMatch1) = MusicKitManager.computeSongSimilarity(
            queryTitle: "Unravel",
            queryArtist: "TK from Ling tosite sigure",
            candidateTitle: "unravel",
            candidateArtist: "TK from Ling tosite sigure"
        )
        XCTAssertTrue(isMatch1)
        XCTAssertGreaterThanOrEqual(score1, 0.95)

        // Title containment
        let (score2, isMatch2) = MusicKitManager.computeSongSimilarity(
            queryTitle: "The Hero!! \"One Punch Man\"",
            queryArtist: "HelloROMIX",
            candidateTitle: "The Hero!! \"One Punch Man\"",
            candidateArtist: "HelloROMIX"
        )
        XCTAssertTrue(isMatch2)
        XCTAssertGreaterThanOrEqual(score2, 0.95)

        // Strict rejection: Void_Chords (Anime) vs Serenity (Metal)
        let (_, isMatch3) = MusicKitManager.computeSongSimilarity(
            queryTitle: "twilight little star",
            queryArtist: "Void_Chords",
            candidateTitle: "Symphony for the Quiet",
            candidateArtist: "Serenity"
        )
        XCTAssertFalse(isMatch3, "Anime track must NEVER match unrelated metal band Serenity")

        // Strict rejection: Re:vale (Anime) vs John Travolta (Musical)
        let (_, isMatch4) = MusicKitManager.computeSongSimilarity(
            queryTitle: "Journey",
            queryArtist: "Re:vale",
            candidateTitle: "You're the One That I Want",
            candidateArtist: "John Travolta & Olivia Newton-John"
        )
        XCTAssertFalse(isMatch4, "Anime track must NEVER match John Travolta")
    }

    func testPlaySearchResultsDoesNotTreatCatalogNumericIdAsLocal() async {
        let router = PlaybackRouter.shared
        let savedToken = MusicKitManager.shared.getUserToken()
        MusicKitManager.shared.clearUserToken()
        defer {
            if let t = savedToken { MusicKitManager.shared.setUserToken(t) }
        }

        let tracks = [
            TrackInfo(id: "270570607", numericId: 270570607, name: "Open Your Eyes", artist: "Guano Apes", isLocal: false, url: "https://music.apple.com/station/item/ra.270570607"),
            TrackInfo(id: "402659693", numericId: 402659693, name: "Lords of the Boards", artist: "Guano Apes", isLocal: false, url: "https://music.apple.com/station/item/ra.402659693")
        ]

        _ = await router.playSearchResults(tracks: tracks, startIndex: 0, shuffle: false)

        let store = PlaybackStateStore.shared
        XCTAssertTrue(store.isCustomQueuePlayback)
        XCTAssertEqual(store.activeCustomQueueIndex, 0)
        XCTAssertEqual(store.activeCustomQueue.count, 2)
        // Cloud tracks without user token must never set currentOriginalPlaylistName to "Очередь AMR"
        XCTAssertNil(store.currentOriginalPlaylistName)
    }

    func testQueueManagerSteeringUnconfirmedForeignTrack() {
        let store = PlaybackStateStore.shared
        let tracks = [
            TrackInfo(id: "1", name: "Open Your Eyes", artist: "Guano Apes", isLocal: false),
            TrackInfo(id: "2", name: "Lords of the Boards", artist: "Guano Apes", isLocal: false)
        ]
        store.withLock {
            store.isCustomQueuePlayback = true
            store.activeCustomQueue = tracks
            store.activeCustomQueueIndex = 0
            store.currentTrackPlaybackConfirmed = false
            store.hasTriggeredAdvanceForCurrentTrack = false
            // Simulate that track 0 was started 5 seconds ago
            store.lastCloudPlayTime = Date().addingTimeInterval(-5.0)
        }

        // Send distributed notification of a foreign track (e.g. Apple Music radio playing The Offspring)
        let userInfo: [AnyHashable: Any] = [
            "Player State": "Playing",
            "Name": "Self Esteem",
            "Artist": "The Offspring"
        ]
        QueueManager.shared.handleTrackNotification(userInfo: userInfo)

        // Chopin requirement: QueueManager blocks foreign radio tracks and steers to next custom queue track (index 1)
        let activeIdx = store.withLock { store.activeCustomQueueIndex }
        XCTAssertEqual(activeIdx, 1, "Foreign radio track must be intercepted and advanced to next track in custom queue")
    }

    func testPlayCloudPreservesMultiTrackCustomQueueForLocalTracks() async {
        let store = PlaybackStateStore.shared
        let tracks = [
            TrackInfo(id: "3648", numericId: 3648, name: "Mein Herz brennt", artist: "Rammstein", isLocal: true),
            TrackInfo(id: "4016", numericId: 4016, name: "Sonne", artist: "Rammstein", isLocal: true),
            TrackInfo(id: "3496", numericId: 3496, name: "Ich will", artist: "Rammstein", isLocal: true)
        ]
        store.withLock {
            store.isCustomQueuePlayback = true
            store.activeCustomQueue = tracks
            store.activeCustomQueueIndex = 0
        }

        let router = PlaybackRouter.shared
        _ = await router.playCloud(url: nil, id: "3648", name: "Mein Herz brennt", artist: "Rammstein", numericId: 3648, isLocal: true)

        let count = store.withLock { store.activeCustomQueue.count }
        XCTAssertEqual(count, 3, "Multi-track custom queue must be preserved when playCloud is called for a local track")
    }

    func testQueueManagerIgnoresDrainingTrackMismatchDuringGracePeriod() {
        let store = PlaybackStateStore.shared
        let tracks = [
            TrackInfo(id: "1", name: "Track A", artist: "Artist", isLocal: false),
            TrackInfo(id: "2", name: "Track B", artist: "Artist", isLocal: false)
        ]
        store.withLock {
            store.isCustomQueuePlayback = true
            store.activeCustomQueue = tracks
            store.activeCustomQueueIndex = 0
            store.currentTrackPlaybackConfirmed = false
            store.hasTriggeredAdvanceForCurrentTrack = false
            // Simulate track 0 was started only 1 second ago (within 3.5s grace period)
            store.lastCloudPlayTime = Date().addingTimeInterval(-1.0)
            store.lastSkipTime = Date().addingTimeInterval(-1.0)
        }

        // Notification arrives for Track B (which was draining/residual from previous queue)
        let userInfo: [AnyHashable: Any] = [
            "Player State": "Playing",
            "Name": "Track B",
            "Artist": "Artist"
        ]
        QueueManager.shared.handleTrackNotification(userInfo: userInfo)

        let activeIdx = store.withLock { store.activeCustomQueueIndex }
        XCTAssertEqual(activeIdx, 0, "During transition grace period, mismatch matching future queue track must be ignored")
    }

    func testArtistMatchedTrackConfirmsPlaybackWithoutSteering() {
        let store = PlaybackStateStore.shared
        let tracks = [
            TrackInfo(id: "270570607", name: "Open Your Eyes", artist: "Guano Apes", isLocal: false),
            TrackInfo(id: "402659693", name: "Lords of the Boards", artist: "Guano Apes", isLocal: false)
        ]
        store.withLock {
            store.isCustomQueuePlayback = true
            store.activeCustomQueue = tracks
            store.activeCustomQueueIndex = 0
            store.currentTrackPlaybackConfirmed = false
            store.hasTriggeredAdvanceForCurrentTrack = false
            // Simulate that track 0 was started 5 seconds ago
            store.lastCloudPlayTime = Date().addingTimeInterval(-5.0)
        }

        // Notification arrives for another song by the same artist ("All I Wanna Do" by Guano Apes) that is not in the queue
        let userInfo: [AnyHashable: Any] = [
            "Player State": "Playing",
            "Name": "All I Wanna Do",
            "Artist": "Guano Apes"
        ]
        QueueManager.shared.handleTrackNotification(userInfo: userInfo)

        let activeIdx = store.withLock {
            store.activeCustomQueueIndex
        }
        XCTAssertEqual(activeIdx, 1, "Unqueued track must trigger steering/advance forward to next queue track (Lords of the Boards)")
    }

    func testPlaySearchResultsDoesNotTruncateWhenMixedLocalAndCloud() async {
        let router = PlaybackRouter.shared
        let tracks = [
            TrackInfo(id: "local_1", numericId: 101, name: "Open Your Eyes", artist: "Guano Apes", isLocal: true),
            TrackInfo(id: "local_2", numericId: 102, name: "Big in Japan", artist: "Guano Apes", isLocal: true),
            TrackInfo(id: "270570607", numericId: nil, name: "Lords of the Boards", artist: "Guano Apes", isLocal: false, url: "https://music.apple.com/station/item/ra.270570607"),
            TrackInfo(id: "270570608", numericId: nil, name: "Rain", artist: "Guano Apes", isLocal: false, url: "https://music.apple.com/station/item/ra.270570608")
        ]

        let ok = await router.playSearchResults(tracks: tracks, startIndex: 0, shuffle: false)
        XCTAssertTrue(ok)

        let store = PlaybackStateStore.shared
        XCTAssertTrue(store.isCustomQueuePlayback)
        XCTAssertEqual(store.activeCustomQueue.count, 4, "Queue must NOT be truncated to the 2 local tracks")
        XCTAssertEqual(store.activeCustomQueueIndex, 0)
        XCTAssertEqual(store.latestUpcomingTracks.count, 3)
    }

    func testNotificationIgnoresWhenUserPaused() {
        let store = PlaybackStateStore.shared
        let tracks = [
            TrackInfo(id: "270570607", name: "Open Your Eyes", artist: "Guano Apes", isLocal: false),
            TrackInfo(id: "402659693", name: "Lords of the Boards", artist: "Guano Apes", isLocal: false)
        ]
        store.withLock {
            store.isCustomQueuePlayback = true
            store.activeCustomQueue = tracks
            store.activeCustomQueueIndex = 0
            store.isUserPaused = true
            store.lastCloudPlayTime = Date().addingTimeInterval(-10.0)
        }

        let userInfo: [AnyHashable: Any] = [
            "Player State": "Paused",
            "Name": "Open Your Eyes",
            "Artist": "Guano Apes"
        ]
        QueueManager.shared.handleTrackNotification(userInfo: userInfo)

        let activeIdx = store.withLock { store.activeCustomQueueIndex }
        XCTAssertEqual(activeIdx, 0, "When paused, track notifications must not advance or change index")
    }
}

