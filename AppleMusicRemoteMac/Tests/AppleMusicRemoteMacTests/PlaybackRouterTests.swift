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
}

