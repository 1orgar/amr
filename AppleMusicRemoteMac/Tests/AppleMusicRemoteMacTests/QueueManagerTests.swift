//
//  QueueManagerTests.swift
//  AppleMusicRemoteMacTests
//

import XCTest
@testable import AppleMusicRemoteMac

final class QueueManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset playback state before each test
        PlaybackStateStore.shared.resetCustomQueue()
    }

    override func tearDown() {
        PlaybackStateStore.shared.resetCustomQueue()
        QueueManager.shared.stopQueueMonitoring()
        super.tearDown()
    }

    func testQueueManagerSharedInstanceExists() {
        XCTAssertNotNil(QueueManager.shared)
    }

    func testQueueMonitoringStartAndStop() {
        let qm = QueueManager.shared
        qm.startQueueMonitoring()
        // Calling start again should safely restart/replace timer
        qm.startQueueMonitoring()
        qm.stopQueueMonitoring()
        // Calling stop again should safely do nothing
        qm.stopQueueMonitoring()
    }

    func testCheckAndAutoAdvanceWhenNoCustomQueue() {
        // When there is no active custom queue, calling checkAndAutoAdvanceCloudQueue should safely return
        PlaybackStateStore.shared.resetCustomQueue()
        QueueManager.shared.checkAndAutoAdvanceCloudQueue()
        XCTAssertFalse(PlaybackStateStore.shared.isCustomQueuePlayback)
    }

    func testHandleTrackNotificationWhenCustomQueueInactive() {
        // When no custom queue is active, notification does not trigger custom queue redirection
        PlaybackStateStore.shared.resetCustomQueue()
        let userInfo: [AnyHashable: Any] = [
            "Name": "Random Radio Track",
            "Artist": "Random Artist"
        ]
        QueueManager.shared.handleTrackNotification(userInfo: userInfo)
        XCTAssertFalse(PlaybackStateStore.shared.isCustomQueuePlayback)
    }

    func testHandleTrackNotificationWhenMatchingActiveTrack() {
        let track1 = TrackInfo(id: "1", name: "Song One", artist: "Artist One")
        let track2 = TrackInfo(id: "2", name: "Song Two", artist: "Artist Two")

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.activeCustomQueueName = "Test Queue"
        }

        // Notification for the matching active track
        let userInfo: [AnyHashable: Any] = [
            "Name": "Song One",
            "Artist": "Artist One"
        ]
        QueueManager.shared.handleTrackNotification(userInfo: userInfo)

        // Queue index should still be 0
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 0)
    }

    func testHandleTrackNotificationWhenMatchingNextTrack() {
        let track1 = TrackInfo(id: "1", name: "Song One", artist: "Artist One")
        let track2 = TrackInfo(id: "2", name: "Song Two", artist: "Artist Two")

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.activeCustomQueueName = "Test Queue"
        }

        // Notification arrived for track 2 (natural advance)
        let userInfo: [AnyHashable: Any] = [
            "Name": "Song Two",
            "Artist": "Artist Two"
        ]
        QueueManager.shared.handleTrackNotification(userInfo: userInfo)

        // Index advances to 1
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 1)
    }

    func testRemoveQueueTrackBounds() async {
        let track1 = TrackInfo(id: "1", name: "Song One", artist: "Artist One")
        let track2 = TrackInfo(id: "2", name: "Song Two", artist: "Artist Two")

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
        }

        // Out of bounds negative upcoming index (targetIdx < 0)
        let negResult = await QueueManager.shared.removeQueueTrack(at: -2)
        XCTAssertFalse(negResult)

        // Out of bounds high upcoming index (targetIdx >= count)
        let highResult = await QueueManager.shared.removeQueueTrack(at: 10)
        XCTAssertFalse(highResult)

        // Removing valid upcoming index 0 (which maps to activeCustomQueueIndex + 1 + 0 = 1, i.e. track2)
        let okResult = await QueueManager.shared.removeQueueTrack(at: 0)
        XCTAssertTrue(okResult)
        let remaining = PlaybackStateStore.shared.activeCustomQueue
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining[0].id, "1")
    }

    func testClearUpcomingQueue() async {
        let track1 = TrackInfo(id: "1", name: "Song One", artist: "Artist One")
        let track2 = TrackInfo(id: "2", name: "Song Two", artist: "Artist Two")
        let track3 = TrackInfo(id: "3", name: "Song Three", artist: "Artist Three")

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2, track3]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
        }

        let cleared = await QueueManager.shared.clearUpcomingQueue()
        XCTAssertTrue(cleared)

        let remaining = PlaybackStateStore.shared.activeCustomQueue
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining[0].id, "1")
    }

    func testEnqueueTrackPlayNextAndAppend() async {
        let track1 = TrackInfo(id: "1", name: "Song One", artist: "Artist One")
        let track2 = TrackInfo(id: "2", name: "Song Two", artist: "Artist Two")
        let newTrack = TrackInfo(id: "new", name: "Inserted Song", artist: "New Artist")

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
        }

        // Enqueue playNext = true (should insert at index 1)
        let enqNext = await QueueManager.shared.enqueueTrack(newTrack, playNext: true)
        XCTAssertTrue(enqNext)

        var queue = PlaybackStateStore.shared.activeCustomQueue
        XCTAssertEqual(queue.count, 3)
        XCTAssertEqual(queue[1].id, "new")

        // Enqueue playNext = false (should append at the end)
        let appendTrack = TrackInfo(id: "end", name: "End Song", artist: "End Artist")
        let enqAppend = await QueueManager.shared.enqueueTrack(appendTrack, playNext: false)
        XCTAssertTrue(enqAppend)

        queue = PlaybackStateStore.shared.activeCustomQueue
        XCTAssertEqual(queue.count, 4)
        XCTAssertEqual(queue[3].id, "end")
    }

    func testPlayQueueIndexUnlockedOutOfBounds() {
        let track1 = TrackInfo(id: "1", name: "Song One", artist: "Artist One")

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
        }

        // Out of bounds index
        let resultNeg = QueueManager.shared.playQueueIndexUnlocked(-1)
        XCTAssertFalse(resultNeg)

        let resultOver = QueueManager.shared.playQueueIndexUnlocked(5)
        XCTAssertFalse(resultOver)
    }

    func testGetRecentlyPlayedDoesNotCrash() {
        let recent = QueueManager.shared.getRecentlyPlayed(limit: 5)
        XCTAssertLessThanOrEqual(recent.count, 5)
    }

    func testBufferingGracePeriodDoesNotSkipOnStoppedOrForeignWhenUnconfirmed() {
        let track1 = TrackInfo(id: "1", name: "Otherside", artist: "Red Hot Chili Peppers")
        let track2 = TrackInfo(id: "2", name: "Dani California", artist: "Red Hot Chili Peppers")

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.lastCloudPlayTime = Date().addingTimeInterval(-3.0) // 3 seconds ago
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
        }

        // Notification: player state is "stopped" while buffering (unconfirmed)
        QueueManager.shared.handleTrackNotification(userInfo: ["Player State": "stopped"])
        // Must NOT skip to next track while unconfirmed!
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 0)

        // Notification: previous or foreign track playing while buffering (unconfirmed)
        QueueManager.shared.handleTrackNotification(userInfo: [
            "Player State": "playing",
            "Name": "Unrelated Old Song",
            "Artist": "Unrelated Artist"
        ])
        // Must NOT steer to next track while unconfirmed!
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 0)
        XCTAssertFalse(PlaybackStateStore.shared.currentTrackPlaybackConfirmed)
    }

    func testQueueWideMatchingSyncsIndexWithoutSkipping() {
        let track1 = TrackInfo(id: "1", name: "Otherside", artist: "Red Hot Chili Peppers")
        let track2 = TrackInfo(id: "2", name: "Dani California", artist: "Red Hot Chili Peppers")
        let track3 = TrackInfo(id: "3", name: "Snow (Hey Oh)", artist: "Red Hot Chili Peppers")

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2, track3]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
        }

        // Station started playing track 3 directly
        QueueManager.shared.handleTrackNotification(userInfo: [
            "Player State": "playing",
            "Name": "Snow (Hey Oh)",
            "Artist": "Red Hot Chili Peppers"
        ])

        // Should cleanly sync to index 2 and confirm playback!
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 2)
        XCTAssertTrue(PlaybackStateStore.shared.currentTrackPlaybackConfirmed)
    }

    func testPastTrackNotificationDoesNotRollbackActiveIndex() {
        let track1 = TrackInfo(id: "1", name: "Song One", artist: "Artist One")
        let track2 = TrackInfo(id: "2", name: "Song Two", artist: "Artist Two")
        let track3 = TrackInfo(id: "3", name: "Song Three", artist: "Artist Three")

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2, track3]
            PlaybackStateStore.shared.activeCustomQueueIndex = 1 // Currently on track 2
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
        }

        // Delayed notification arrives from Music.app for track 1 (index 0) during audio switch buffer
        QueueManager.shared.handleTrackNotification(userInfo: [
            "Player State": "playing",
            "Name": "Song One",
            "Artist": "Artist One"
        ])

        // Must NOT roll back to index 0! Index must remain 1.
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 1)
        XCTAssertFalse(PlaybackStateStore.shared.currentTrackPlaybackConfirmed)
    }

    func testOneShotAdvanceGuardPreventsDuplicateSkips() {
        let track1 = TrackInfo(id: "1", name: "Song One", artist: "Artist One", duration: 180)
        let track2 = TrackInfo(id: "2", name: "Song Two", artist: "Artist Two", duration: 200)

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = true // Already fired!
        }

        // Notification: player stopped or end-of-track, but guard already triggered
        QueueManager.shared.handleTrackNotification(userInfo: ["Player State": "stopped"])

        // Must NOT trigger another advance while guard is true
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 0)
    }

    func testTitleNormalizationMatchesEditionsWithoutCrossMatchingSharedWords() {
        let track1 = TrackInfo(id: "1", name: "Under the Bridge", artist: "Red Hot Chili Peppers")
        let track2 = TrackInfo(id: "2", name: "Around the World", artist: "Red Hot Chili Peppers")

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
        }

        // 1. Remaster edition of track 1 matches track 1 cleanly
        QueueManager.shared.handleTrackNotification(userInfo: [
            "Player State": "playing",
            "Name": "Under the Bridge (2014 Remaster)",
            "Artist": "Red Hot Chili Peppers"
        ])
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 0)
        XCTAssertTrue(PlaybackStateStore.shared.currentTrackPlaybackConfirmed)

        // 2. Notification for "Around the World" (sharing word "the") advances forward to index 1,
        // without erroneously matching index 0
        QueueManager.shared.handleTrackNotification(userInfo: [
            "Player State": "playing",
            "Name": "Around the World",
            "Artist": "Red Hot Chili Peppers"
        ])
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 1)
    }

    func testQueueMonitoringIgnoresDrainingTrackDuringTransition() {
        let track1 = TrackInfo(id: "1", name: "Sonne", artist: "Rammstein")
        let track2 = TrackInfo(id: "2", name: "Du Hast", artist: "Rammstein")
        let track3 = TrackInfo(id: "3", name: "Deutschland", artist: "Rammstein")

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2, track3]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0 // User switched back to track 0 (Sonne)
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
            PlaybackStateStore.shared.lastSkipTime = Date() // Transitioning right now!
        }

        // Delayed notification arrives from Music.app for draining track 1 (Du Hast)
        QueueManager.shared.handleTrackNotification(userInfo: [
            "Player State": "playing",
            "Name": "Du Hast",
            "Artist": "Rammstein"
        ])

        // Must IGNORE Du Hast because it is transitioning to Sonne!
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 0)
        XCTAssertFalse(PlaybackStateStore.shared.currentTrackPlaybackConfirmed)

        // Now target track Sonne begins playing
        QueueManager.shared.handleTrackNotification(userInfo: [
            "Player State": "playing",
            "Name": "Sonne",
            "Artist": "Rammstein"
        ])

        // Correctly matches target track and confirms!
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 0)
        XCTAssertTrue(PlaybackStateStore.shared.currentTrackPlaybackConfirmed)
        XCTAssertFalse(PlaybackStateStore.shared.isTransitioningTrack)
    }

    func testPreviousTrackInRadioPlaybackRewindsWithoutExitingRadio() {
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.resetPlaybackState(originalPlaylist: nil, isRadio: true, stationName: "Rock Radio")
        }

        let res = PlaybackTransportController.shared.previousTrack()
        XCTAssertTrue(res)
        XCTAssertTrue(PlaybackStateStore.shared.isRadioPlayback)
        XCTAssertEqual(PlaybackStateStore.shared.activeStationName, "Rock Radio")
    }

    func testPreviousTrackAtBeginningOfCustomQueueRewindsWithoutFallingOutOfQueue() {
        let track1 = TrackInfo(id: "1", name: "Sonne", artist: "Rammstein")
        let track2 = TrackInfo(id: "2", name: "Du Hast", artist: "Rammstein")

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.lastSkipTime = .distantPast
        }

        let res = PlaybackTransportController.shared.previousTrack()
        XCTAssertTrue(res)
        // Must stay on index 0 and keep custom queue active
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 0)
        XCTAssertTrue(PlaybackStateStore.shared.isCustomQueuePlayback)
    }

    func testNextTrackAtEndOfCustomQueueDoesNotFallThroughToAppNextTrack() {
        let track1 = TrackInfo(id: "1", name: "Sonne", artist: "Rammstein")
        let track2 = TrackInfo(id: "2", name: "Du Hast", artist: "Rammstein")

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2]
            PlaybackStateStore.shared.activeCustomQueueIndex = 1 // Already at end of queue
            PlaybackStateStore.shared.lastSkipTime = .distantPast
        }

        let res = PlaybackTransportController.shared.nextTrack()
        XCTAssertTrue(res)
        // Must remain on index 1 and keep custom queue active
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 1)
        XCTAssertTrue(PlaybackStateStore.shared.isCustomQueuePlayback)
    }

    func testPlayQueueIndexUnlockedInAMRQueueUpdatesUpcomingAndHistory() {
        let track1 = TrackInfo(id: "1", numericId: 101, name: "Sonne", artist: "Rammstein", isLocal: true, index: 1)
        let track2 = TrackInfo(id: "2", numericId: 102, name: "Du Hast", artist: "Rammstein", isLocal: true, index: 2)
        let track3 = TrackInfo(id: "3", numericId: 103, name: "Ich will", artist: "Rammstein", isLocal: true, index: 3)

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2, track3]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
        }

        // Navigate to index 1 (Du Hast)
        _ = QueueManager.shared.playQueueIndexUnlocked(1)

        PlaybackStateStore.shared.withLock {
            XCTAssertEqual(PlaybackStateStore.shared.latestUpcomingTracks.count, 1)
            XCTAssertEqual(PlaybackStateStore.shared.latestUpcomingTracks[0].name, "Ich will")
            XCTAssertEqual(PlaybackStateStore.shared.latestHistoryTracks.count, 1)
            XCTAssertEqual(PlaybackStateStore.shared.latestHistoryTracks[0].name, "Sonne")
            XCTAssertTrue(PlaybackStateStore.shared.isTransitioningTrack)
        }

        // Navigate back to index 0 (Sonne)
        _ = QueueManager.shared.playQueueIndexUnlocked(0)

        PlaybackStateStore.shared.withLock {
            XCTAssertEqual(PlaybackStateStore.shared.latestUpcomingTracks.count, 2)
            XCTAssertEqual(PlaybackStateStore.shared.latestUpcomingTracks[0].name, "Du Hast")
            XCTAssertEqual(PlaybackStateStore.shared.latestUpcomingTracks[1].name, "Ich will")
            XCTAssertEqual(PlaybackStateStore.shared.latestHistoryTracks.count, 0)
        }
    }

    func testTransitioningDebounceWindowIs2Point5Seconds() {
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastSkipTime = Date().addingTimeInterval(-2.0)
            XCTAssertTrue(PlaybackStateStore.shared.isTransitioningTrack, "At 2.0s, track must still be transitioning")

            PlaybackStateStore.shared.lastSkipTime = Date().addingTimeInterval(-2.6)
            XCTAssertFalse(PlaybackStateStore.shared.isTransitioningTrack, "At 2.6s, track transition debounce must be expired")
        }
    }

    func testTrackMatchingWithLocalizedTitlesAndSameArtist() {
        let expected = TrackInfo(id: "1838420151", numericId: 1838420151, name: "Hitoshibai", artist: "Mai Fuchigami")
        // Japanese Kanji localization in Music.app vs English/Romaji from catalog
        let matches = QueueManager.shared.isTrackMatching(expected: expected, candidateName: "人芝居", candidateArtist: "Mai Fuchigami")
        XCTAssertTrue(matches, "Track matching must recognize localized title when artist is identical")

        // Cyrillic localization vs Latin title with matching artist
        let expectedCyr = TrackInfo(id: "2", numericId: 2, name: "Swan Lake", artist: "Tchaikovsky")
        let matchesCyr = QueueManager.shared.isTrackMatching(expected: expectedCyr, candidateName: "Лебединое озеро", candidateArtist: "Tchaikovsky")
        XCTAssertTrue(matchesCyr, "Track matching must recognize Cyrillic localization when artist matches")

        // Two different Cyrillic songs by the same artist must NOT match
        let cyrSong1 = TrackInfo(id: "3", numericId: 3, name: "Группа крови", artist: "Кино")
        XCTAssertFalse(
            QueueManager.shared.isTrackMatching(expected: cyrSong1, candidateName: "Звезда по имени Солнце", candidateArtist: "Кино"),
            "Two different Cyrillic titles by the same artist must not false-positive match"
        )

        // Two different CJK songs by the same artist must NOT match
        let cjkSong1 = TrackInfo(id: "4", numericId: 4, name: "青のすみか", artist: "Tatsuya Kitani")
        XCTAssertFalse(
            QueueManager.shared.isTrackMatching(expected: cjkSong1, candidateName: "呪術廻戦", candidateArtist: "Tatsuya Kitani"),
            "Two different CJK titles by the same artist must not false-positive match"
        )

        // Two different Latin songs with curly apostrophes or umlauts by the same artist must NOT match
        let queenSong = TrackInfo(id: "5", numericId: 5, name: "Don’t Stop Me Now", artist: "Queen")
        XCTAssertFalse(
            QueueManager.shared.isTrackMatching(expected: queenSong, candidateName: "Bohemian Rhapsody", candidateArtist: "Queen"),
            "Curly apostrophe in Latin title must not cause false-positive match with another song by the same artist"
        )

        let rammsteinSong = TrackInfo(id: "6", numericId: 6, name: "Bück Dich", artist: "Rammstein")
        XCTAssertFalse(
            QueueManager.shared.isTrackMatching(expected: rammsteinSong, candidateName: "Sonne", candidateArtist: "Rammstein"),
            "Umlaut in Latin title must not cause false-positive match with another song by the same artist"
        )
    }

    func testPollerNeverStopsAMRPlaylistPlayback() {
        let track1 = TrackInfo(id: "1", numericId: 101, name: "Hitoshibai", artist: "Mai Fuchigami", isLocal: false, index: 1)
        let track2 = TrackInfo(id: "2", numericId: 102, name: "Minor Piece", artist: "ZAQ", isLocal: false, index: 2)

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
            PlaybackStateStore.shared.lastCloudPlayTime = Date().addingTimeInterval(-10.0)
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
        }

        QueueManager.shared.handleTrackNotification(userInfo: [
            "Player State": "playing",
            "Name": "Unmatched Japanese Song",
            "Artist": "Some Artist"
        ])

        PlaybackStateStore.shared.withLock {
            // Must be confirmed without stopping or skipping to track 1
            XCTAssertTrue(PlaybackStateStore.shared.currentTrackPlaybackConfirmed)
            XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 0)
        }
    }

    func testAMRQueueAdvancesToNextTrackWhenConfirmedTrackTransitionsToForeignSameArtistTrack() {
        let track1 = TrackInfo(id: "1", numericId: 101, name: "That Home", artist: "The Cinematic Orchestra", isLocal: true, index: 1)
        let track2 = TrackInfo(id: "2", numericId: 102, name: "Almost Blue", artist: "Chet Baker", isLocal: true, index: 2)
        let track3 = TrackInfo(id: "3", numericId: 103, name: "Peace Piece", artist: "Bill Evans", isLocal: true, index: 3)

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2, track3]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
            PlaybackStateStore.shared.lastCloudPlayTime = Date().addingTimeInterval(-15.0)
            PlaybackStateStore.shared.lastSkipTime = .distantPast
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
            PlaybackStateStore.shared.isUserPaused = false
        }

        // Simulate Music.app auto-advancing in library playlist 1 to the next song of the same artist ("Familiar Ground")
        QueueManager.shared.handleTrackNotification(userInfo: [
            "Player State": "playing",
            "Name": "Familiar Ground",
            "Artist": "The Cinematic Orchestra"
        ])

        PlaybackStateStore.shared.withLock {
            // Must intercept the foreign same-artist track and advance activeCustomQueueIndex to 1 ("Chet Baker - Almost Blue")
            XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 1)
            XCTAssertEqual(PlaybackStateStore.shared.latestUpcomingTracks.first?.name, "Peace Piece")
            XCTAssertEqual(PlaybackStateStore.shared.latestHistoryTracks.first?.name, "That Home")
        }
    }

    func testPollerNeverStopsNativeNamedPlaylistPlayback() {
        let track1 = TrackInfo(id: "1", numericId: 101, name: "Sonne", artist: "Rammstein", isLocal: true, index: 1)
        let track2 = TrackInfo(id: "2", numericId: 102, name: "Ich will", artist: "Rammstein", isLocal: true, index: 2)

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.currentOriginalPlaylistName = "Любимые песни"
            PlaybackStateStore.shared.lastCloudPlayTime = Date().addingTimeInterval(-10.0)
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
        }

        QueueManager.shared.handleTrackNotification(userInfo: [
            "Player State": "playing",
            "Name": "Unmatched Song",
            "Artist": "Foreign Artist"
        ])

        PlaybackStateStore.shared.withLock {
            XCTAssertTrue(PlaybackStateStore.shared.currentTrackPlaybackConfirmed)
            XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 0)
        }
    }

    func testAdvanceCustomQueueRepeatOne() {
        let track1 = TrackInfo(id: "1", numericId: 101, name: "Track 1", artist: "Artist 1", isLocal: true, index: 1)
        let track2 = TrackInfo(id: "2", numericId: 102, name: "Track 2", artist: "Artist 2", isLocal: true, index: 2)

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.repeatMode = "one"
            QueueManager.shared.advanceOrEndCustomQueueUnlocked(reason: "test-repeat-one")
            XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 0)
            XCTAssertFalse(PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack)
        }
    }

    func testAdvanceCustomQueueSequential() {
        let track1 = TrackInfo(id: "1", numericId: 101, name: "Track 1", artist: "Artist 1", isLocal: true, index: 1)
        let track2 = TrackInfo(id: "2", numericId: 102, name: "Track 2", artist: "Artist 2", isLocal: true, index: 2)
        let track3 = TrackInfo(id: "3", numericId: 103, name: "Track 3", artist: "Artist 3", isLocal: true, index: 3)

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2, track3]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.repeatMode = "off"
            QueueManager.shared.advanceOrEndCustomQueueUnlocked(reason: "test-seq-1")
            XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 1)

            QueueManager.shared.advanceOrEndCustomQueueUnlocked(reason: "test-seq-2")
            XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 2)
        }
    }

    func testAdvanceCustomQueueRepeatAllNoShuffle() {
        let track1 = TrackInfo(id: "1", numericId: 101, name: "Track 1", artist: "Artist 1", isLocal: true, index: 1)
        let track2 = TrackInfo(id: "2", numericId: 102, name: "Track 2", artist: "Artist 2", isLocal: true, index: 2)

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2]
            PlaybackStateStore.shared.activeCustomQueueIndex = 1
            PlaybackStateStore.shared.repeatMode = "all"
            PlaybackStateStore.shared.isShuffleQueueActive = false
            QueueManager.shared.advanceOrEndCustomQueueUnlocked(reason: "test-repeat-all")
            XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 0)
        }
    }

    func testAdvanceCustomQueueRepeatAllWithShuffle() {
        let track1 = TrackInfo(id: "1", numericId: 101, name: "Track 1", artist: "Artist 1", isLocal: true, index: 1)
        let track2 = TrackInfo(id: "2", numericId: 102, name: "Track 2", artist: "Artist 2", isLocal: true, index: 2)
        let track3 = TrackInfo(id: "3", numericId: 103, name: "Track 3", artist: "Artist 3", isLocal: true, index: 3)

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2, track3]
            PlaybackStateStore.shared.activeCustomQueueIndex = 2 // last track is track3 (id "3")
            PlaybackStateStore.shared.repeatMode = "all"
            PlaybackStateStore.shared.isShuffleQueueActive = true

            QueueManager.shared.advanceOrEndCustomQueueUnlocked(reason: "test-infinite-shuffle")
            XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 0)
            XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueue.count, 3)
            // The first track of the new cycle must not be track3 (immediate duplicate avoidance)
            XCTAssertNotEqual(PlaybackStateStore.shared.activeCustomQueue.first?.id, "3")
        }
    }

    func testAdvanceCustomQueueRepeatOffSingleTrackStopsCleanly() {
        let track1 = TrackInfo(id: "1", numericId: 101, name: "Single Track", artist: "Single Artist", isLocal: true, index: 1)

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.repeatMode = "off"

            QueueManager.shared.advanceOrEndCustomQueueUnlocked(reason: "test-single-stop")
            XCTAssertFalse(PlaybackStateStore.shared.isCustomQueuePlayback)
            XCTAssertTrue(PlaybackStateStore.shared.activeCustomQueue.isEmpty)
            XCTAssertTrue(PlaybackStateStore.shared.isUserPaused)
        }
    }

    func testAdvanceCustomQueueRepeatOffMultiTrackClearsAndTransitions() {
        let track1 = TrackInfo(id: "1", numericId: 101, name: "Track 1", artist: "Artist 1", isLocal: true, index: 1)
        let track2 = TrackInfo(id: "2", numericId: 102, name: "Track 2", artist: "Artist 2", isLocal: true, index: 2)

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2]
            PlaybackStateStore.shared.activeCustomQueueIndex = 1 // at the end
            PlaybackStateStore.shared.repeatMode = "off"

            QueueManager.shared.advanceOrEndCustomQueueUnlocked(reason: "test-multi-end")
            XCTAssertFalse(PlaybackStateStore.shared.isCustomQueuePlayback)
            XCTAssertTrue(PlaybackStateStore.shared.activeCustomQueue.isEmpty)
        }
    }

    func testManualNextTrackInShuffledCustomQueueAdvancesWithoutDuplicates() {
        let tracks = [
            TrackInfo(id: "1", numericId: 101, name: "Track 1", artist: "Artist 1", isLocal: true, index: 1),
            TrackInfo(id: "2", numericId: 102, name: "Track 2", artist: "Artist 2", isLocal: true, index: 2),
            TrackInfo(id: "3", numericId: 103, name: "Track 3", artist: "Artist 3", isLocal: true, index: 3)
        ]

        _ = PlaybackRouter.shared.playCustomTracks(tracks, startIndex: 0, shuffle: true, queueName: "Shuffled Queue")
        var visitedIds: [String] = []
        visitedIds.append(PlaybackStateStore.shared.activeCustomQueue[PlaybackStateStore.shared.activeCustomQueueIndex].id)

        // Wait > 0.25s debounce between manual nextTrack calls
        Thread.sleep(forTimeInterval: 0.26)
        _ = PlaybackTransportController.shared.nextTrack()
        visitedIds.append(PlaybackStateStore.shared.activeCustomQueue[PlaybackStateStore.shared.activeCustomQueueIndex].id)

        Thread.sleep(forTimeInterval: 0.26)
        _ = PlaybackTransportController.shared.nextTrack()
        visitedIds.append(PlaybackStateStore.shared.activeCustomQueue[PlaybackStateStore.shared.activeCustomQueueIndex].id)

        // All 3 tracks must be visited exactly once without duplicates!
        XCTAssertEqual(Set(visitedIds).count, 3)
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 2)

        // With repeat = "all", pressing nextTrack at the end loops back to index 0 with a fresh permutation
        _ = PlaybackTransportController.shared.setRepeat(mode: "all")
        Thread.sleep(forTimeInterval: 0.26)
        _ = PlaybackTransportController.shared.nextTrack()
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 0)
    }

    func testSetShuffleMidQueueShufflesAndRestoresOriginalOrder() {
        let tracks = [
            TrackInfo(id: "10", numericId: 10, name: "Alpha", artist: "Band", isLocal: true, index: 1),
            TrackInfo(id: "20", numericId: 20, name: "Beta", artist: "Band", isLocal: true, index: 2),
            TrackInfo(id: "30", numericId: 30, name: "Gamma", artist: "Band", isLocal: true, index: 3),
            TrackInfo(id: "40", numericId: 40, name: "Delta", artist: "Band", isLocal: true, index: 4)
        ]

        _ = PlaybackRouter.shared.playCustomTracks(tracks, startIndex: 1, shuffle: false, queueName: "Order Test")
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 1)
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueue[1].id, "20")

        // Enable shuffle mid-queue: current track at index 1 ("20") stays at index 1, tail is permuted
        _ = PlaybackTransportController.shared.setShuffle(true)
        XCTAssertTrue(PlaybackStateStore.shared.isShuffleQueueActive)
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueue[1].id, "20")
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueue.count, 4)

        // Disable shuffle: original order [10, 20, 30, 40] is restored and index stays on "20" (index 1)
        _ = PlaybackTransportController.shared.setShuffle(false)
        XCTAssertFalse(PlaybackStateStore.shared.isShuffleQueueActive)
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueue.map(\.id), ["10", "20", "30", "40"])
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 1)
    }

    func testSetRepeatSanitizesInvalidMode() {
        _ = PlaybackTransportController.shared.setRepeat(mode: "all\"; do shell script \"whoami")
        XCTAssertEqual(PlaybackStateStore.shared.repeatMode, "off")

        _ = PlaybackTransportController.shared.setRepeat(mode: "ONE")
        XCTAssertEqual(PlaybackStateStore.shared.repeatMode, "one")
    }

    func testWebSocketOriginValidation() {
        XCTAssertTrue(WebSocketServer.shared.isAllowedWebSocketOrigin("http://localhost:8080"))
        XCTAssertTrue(WebSocketServer.shared.isAllowedWebSocketOrigin("http://127.0.0.1:8080"))
        XCTAssertTrue(WebSocketServer.shared.isAllowedWebSocketOrigin("http://192.168.1.50:8080"))
        XCTAssertTrue(WebSocketServer.shared.isAllowedWebSocketOrigin("http://mac-mini.local:8080"))
        XCTAssertFalse(WebSocketServer.shared.isAllowedWebSocketOrigin("https://evil.example.com"))
    }

    func testStationHeaderNotificationDoesNotKillCloudStream() {
        let track1 = TrackInfo(id: "1381263374", numericId: 3967, name: "Open Your Eyes", artist: "Guano Apes", isLocal: true)
        let track2 = TrackInfo(id: "286006732", numericId: nil, name: "Lords of the Boards", artist: "Guano Apes", isLocal: false)
        let track3 = TrackInfo(id: "280436240", numericId: nil, name: "Big In Japan", artist: "Guano Apes", isLocal: false)

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2, track3]
            PlaybackStateStore.shared.activeCustomQueueIndex = 1
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
            PlaybackStateStore.shared.lastCloudPlayTime = Date().addingTimeInterval(-5.0)
            PlaybackStateStore.shared.lastSkipTime = .distantPast
        }

        // Transient station header emitted by Music.app must NOT be treated as a foreign track
        QueueManager.shared.handleTrackNotification(userInfo: [
            "Player State": "playing",
            "Name": "Станция: Lords of the Boards",
            "Artist": ""
        ])

        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 1)
        XCTAssertFalse(PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack)
    }

    func testStoppedNotificationAdvancesWhenLastKnownPositionNearEnd() {
        let track1 = TrackInfo(id: "1", numericId: 3413, name: "青のすみか", artist: "Tatsuya Kitani", duration: 196.0, isLocal: true)
        let track2 = TrackInfo(id: "2", numericId: 3909, name: "マロウブルー", artist: "IDOLiSH7", duration: 245.0, isLocal: true)

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track1, track2]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
            PlaybackStateStore.shared.lastCloudPlayTime = Date().addingTimeInterval(-8.0) // User seeked 8s ago
            PlaybackStateStore.shared.lastKnownPosition = 194.5 // Near end of 196s track
        }

        QueueManager.shared.handleTrackNotification(userInfo: [
            "Player State": "stopped"
        ])

        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 1)
    }

    func testPastTrackNotificationInAMRPlaylistDoesNotCascadeOrClearQueue() {
        let track0 = TrackInfo(id: "100", numericId: 32587, name: "Temptation", artist: "Diana Krall", duration: 210.0, isLocal: true)
        let track1 = TrackInfo(id: "101", numericId: 32602, name: "Birds", artist: "Dominique Fils-Aimé", duration: 195.0, isLocal: true)
        let track2 = TrackInfo(id: "102", numericId: 32605, name: "Baby I'm A Fool", artist: "Melody Gardot", duration: 212.0, isLocal: true)
        let track3 = TrackInfo(id: "103", numericId: 32608, name: "Fields of Gold", artist: "Eva Cassidy", duration: 280.0, isLocal: true)

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track0, track1, track2, track3]
            PlaybackStateStore.shared.activeCustomQueueIndex = 1 // User pressed Next Track -> playing track1 (Birds)
            PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
            PlaybackStateStore.shared.lastCloudPlayTime = Date().addingTimeInterval(-195.0)
            PlaybackStateStore.shared.lastKnownPosition = 193.5
            PlaybackStateStore.shared.lastSkipTime = .distantPast
        }

        // Track 1 (Birds) finishes -> advances to Track 2 (Baby I'm A Fool)
        QueueManager.shared.advanceOrEndCustomQueueUnlocked(reason: "smooth-advance")
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 2)
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueue.count, 4)

        // Simulate late draining notification from Music.app for previous track "Birds" (pastIdx = 1)
        // Even if skip window expired and confirmed is true in "Очередь AMR", it must NEVER treat "Birds" as foreign!
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastSkipTime = Date().addingTimeInterval(-5.0)
            PlaybackStateStore.shared.lastCloudPlayTime = Date().addingTimeInterval(-5.0)
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
        }

        QueueManager.shared.handleTrackNotification(userInfo: [
            "Player State": "playing",
            "Name": "Birds",
            "Artist": "Dominique Fils-Aimé"
        ])

        // Must stay on index 2 ("Baby I'm A Fool") and NEVER cascade or clear activeCustomQueue!
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 2)
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueue.count, 4)
        XCTAssertTrue(PlaybackStateStore.shared.isCustomQueuePlayback)

        // Lightweight pulse must invalidate when track database ID or track name changes
        let seededMeta = StaticTrackMetadata(
            dbId: 32602,
            name: "Birds",
            artist: "Dominique Fils-Aimé",
            album: "Nameless",
            duration: 195.0,
            hasLoc: true,
            kind: "Apple Music AAC audio file",
            bitRate: 256,
            sampleRate: 44100,
            isFavorited: false,
            currentPlaylistName: "Очередь AMR",
            shuffle: false,
            repeatMode: "off",
            volume: 100
        )
        PlayerStatusEngine.shared.seedStaticMetadataForTesting(seededMeta)
        XCTAssertTrue(PlayerStatusEngine.shared.shouldUseLightweightPulse(rawState: "playing", rawPosition: 2.0, rawDbId: 32602, rawTrackName: "Birds"))
        XCTAssertFalse(PlayerStatusEngine.shared.shouldUseLightweightPulse(rawState: "playing", rawPosition: 2.0, rawDbId: 32605, rawTrackName: "Baby I'm A Fool"))
    }

    func testSameArtistTrackLaterInAMRQueueDoesNotSkipIntermediateQueueTracks() {
        // Queue has Diana Krall at index 0 AND another Diana Krall song at index 3.
        // When index 0 finishes in Music.app, library playlist 1 (sorted by artist) auto-advances to index 3's song.
        // QueueManager MUST NOT teleport to index 3! It must intercept it and play index 1 (Dominique Fils-Aimé).
        let track0 = TrackInfo(id: "100", numericId: 32587, name: "Temptation", artist: "Diana Krall", duration: 210.0, isLocal: true)
        let track1 = TrackInfo(id: "101", numericId: 32602, name: "Birds", artist: "Dominique Fils-Aimé", duration: 195.0, isLocal: true)
        let track2 = TrackInfo(id: "102", numericId: 32605, name: "Baby I'm A Fool", artist: "Melody Gardot", duration: 212.0, isLocal: true)
        let track3 = TrackInfo(id: "103", numericId: 32590, name: "The Look of Love", artist: "Diana Krall", duration: 240.0, isLocal: true)

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track0, track1, track2, track3]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
            PlaybackStateStore.shared.lastCloudPlayTime = Date().addingTimeInterval(-210.0)
            PlaybackStateStore.shared.lastSkipTime = .distantPast
        }

        // Music.app auto-advances in library playlist 1 to "The Look of Love" by Diana Krall (which is also track3!)
        QueueManager.shared.handleTrackNotification(userInfo: [
            "Player State": "playing",
            "Name": "The Look of Love",
            "Artist": "Diana Krall"
        ])

        // Must advance strictly to index 1 ("Birds"), NOT jump to index 3!
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 1)
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueue[PlaybackStateStore.shared.activeCustomQueueIndex].name, "Birds")
        XCTAssertEqual(PlaybackStateStore.shared.latestUpcomingTracks.map(\.name), ["Baby I'm A Fool", "The Look of Love"])
        XCTAssertEqual(PlaybackStateStore.shared.latestHistoryTracks.map(\.name), ["Temptation"])
    }

    func testAllQueueTransitionsAndHistoryNavigationAreExact() async {
        let tracks = [
            TrackInfo(id: "t0", numericId: 1000, name: "Track Zero", artist: "Artist A", duration: 180, isLocal: true, index: 1),
            TrackInfo(id: "t1", numericId: 1001, name: "Track One", artist: "Artist B", duration: 180, isLocal: true, index: 2),
            TrackInfo(id: "t2", numericId: 1002, name: "Track Two", artist: "Artist C", duration: 180, isLocal: true, index: 3),
            TrackInfo(id: "t3", numericId: 1003, name: "Track Three", artist: "Artist D", duration: 180, isLocal: true, index: 4),
            TrackInfo(id: "t4", numericId: 1004, name: "Track Four", artist: "Artist E", duration: 180, isLocal: true, index: 5)
        ]

        _ = PlaybackRouter.shared.playCustomTracks(tracks, startIndex: 0, shuffle: false, queueName: "AI Mix")
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 0)

        // 1. Jump forward via playQueueIndex(1) -> upcoming[1] is "Track Two" (index 2)
        let jumpedUpcoming = await QueueManager.shared.playQueueIndex(1)
        XCTAssertTrue(jumpedUpcoming)
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 2)
        XCTAssertEqual(PlaybackStateStore.shared.latestUpcomingTracks.map(\.id), ["t3", "t4"])
        XCTAssertEqual(PlaybackStateStore.shared.latestHistoryTracks.map(\.id), ["t1", "t0"])

        // 2. Jump backward via playHistoryIndex(0) -> history[0] is most recent past track "Track One" (index 1)
        let jumpedHistory0 = await QueueManager.shared.playHistoryIndex(0)
        XCTAssertTrue(jumpedHistory0)
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 1)
        XCTAssertEqual(PlaybackStateStore.shared.latestUpcomingTracks.map(\.id), ["t2", "t3", "t4"])
        XCTAssertEqual(PlaybackStateStore.shared.latestHistoryTracks.map(\.id), ["t0"])

        // 3. Enqueue Play Next while at index 1 -> inserts at index 2
        let bonusTrack = TrackInfo(id: "bonus", numericId: 1999, name: "Bonus Track", artist: "Artist X", duration: 150, isLocal: true)
        let enqOk = await QueueManager.shared.enqueueTrack(bonusTrack, playNext: true)
        XCTAssertTrue(enqOk)
        let qAfterEnq = await QueueManager.shared.getPlaybackQueue()
        XCTAssertEqual(qAfterEnq.currentIndex, 1)
        XCTAssertEqual(qAfterEnq.upcomingTracks.first?.id, "bonus")
        XCTAssertEqual(qAfterEnq.totalTracks, 6)

        // 4. Remove the newly inserted Play Next track (upcoming index 0 -> queue index 2)
        let remOk = await QueueManager.shared.removeQueueTrack(at: 0)
        XCTAssertTrue(remOk)
        let qAfterRem = await QueueManager.shared.getPlaybackQueue()
        XCTAssertEqual(qAfterRem.totalTracks, 5)
        XCTAssertEqual(qAfterRem.upcomingTracks.map(\.id), ["t2", "t3", "t4"])

        // 5. Clear upcoming queue while at index 1 -> keeps t0 and t1, removes t2..t4
        let clearOk = await QueueManager.shared.clearUpcomingQueue()
        XCTAssertTrue(clearOk)
        let qAfterClear = await QueueManager.shared.getPlaybackQueue()
        XCTAssertEqual(qAfterClear.totalTracks, 2)
        XCTAssertEqual(qAfterClear.currentIndex, 1)
        XCTAssertTrue(qAfterClear.upcomingTracks.isEmpty)
        XCTAssertEqual(qAfterClear.historyTracks.map(\.id), ["t0"])
    }

    func testRepeatOneTrackPersistsInStatusAndLoopsCustomQueue() {
        defer {
            _ = PlaybackTransportController.shared.setRepeat(mode: "off")
            PlaybackStateStore.shared.resetCustomQueue()
        }

        // 1. Verify setRepeat("one") and aliases ("track", "1") persist in PlaybackStateStore & PlayerStatusEngine
        XCTAssertTrue(PlaybackTransportController.shared.setRepeat(mode: "track"))
        XCTAssertEqual(PlaybackStateStore.shared.repeatMode, "one")
        XCTAssertEqual(PlayerStatusEngine.shared.getPlayerStatus().repeatMode, "one")

        XCTAssertTrue(PlaybackTransportController.shared.setRepeat(mode: "1"))
        XCTAssertEqual(PlaybackStateStore.shared.repeatMode, "one")

        // 2. Single-track custom queue with Repeat One: EOF and Next must loop index 0 without ending queue
        let soloTrack = TrackInfo(id: "solo-1", numericId: 501, name: "Solo Loop", artist: "Test Artist", duration: 210, isLocal: true, index: 1)
        _ = PlaybackRouter.shared.playCustomTracks([soloTrack], startIndex: 0, shuffle: false, queueName: "Solo Queue")
        XCTAssertEqual(PlaybackStateStore.shared.repeatMode, "one", "Starting a track must preserve user-selected Repeat One mode")

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastSkipTime = .distantPast
            QueueManager.shared.advanceOrEndCustomQueueUnlocked(reason: "test-eof-solo")
        }
        XCTAssertTrue(PlaybackStateStore.shared.isCustomQueuePlayback, "1-track custom queue must stay active on EOF when Repeat One is enabled")
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 0)

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastSkipTime = .distantPast
        }
        PlaybackTransportController.shared.resetDebounceForTesting()
        XCTAssertTrue(PlaybackTransportController.shared.nextTrack())
        XCTAssertTrue(PlaybackStateStore.shared.isCustomQueuePlayback)
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 0)

        // 3. Multi-track custom queue at index 1 with Repeat One:
        //    - Natural EOF replays current track (index 1) infinitely
        //    - Manual Next skips to index 2 (Apple Music UX), and at end of queue (index 2) replays index 2
        let tracks = [
            TrackInfo(id: "m0", numericId: 601, name: "First", artist: "Artist", duration: 180, isLocal: true, index: 1),
            TrackInfo(id: "m1", numericId: 602, name: "Second", artist: "Artist", duration: 180, isLocal: true, index: 2),
            TrackInfo(id: "m2", numericId: 603, name: "Third", artist: "Artist", duration: 180, isLocal: true, index: 3)
        ]
        _ = PlaybackRouter.shared.playCustomTracks(tracks, startIndex: 1, shuffle: false, queueName: "Multi Queue")
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 1)

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastSkipTime = .distantPast
            QueueManager.shared.advanceOrEndCustomQueueUnlocked(reason: "test-eof-multi")
        }
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 1, "EOF with Repeat One must replay current track index 1")

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastSkipTime = .distantPast
        }
        PlaybackTransportController.shared.resetDebounceForTesting()
        XCTAssertTrue(PlaybackTransportController.shared.nextTrack())
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 2, "Manual Next advances to next track (index 2) which then loops on Repeat One")

        // At end of queue (index 2) with Repeat One, both EOF and manual Next stay on index 2 without ending queue
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastSkipTime = .distantPast
        }
        PlaybackTransportController.shared.resetDebounceForTesting()
        XCTAssertTrue(PlaybackTransportController.shared.nextTrack())
        XCTAssertTrue(PlaybackStateStore.shared.isCustomQueuePlayback)
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 2)

        // Turn Repeat Off confirms status resets cleanly
        XCTAssertTrue(PlaybackTransportController.shared.setRepeat(mode: "off"))
        XCTAssertEqual(PlayerStatusEngine.shared.getPlayerStatus().repeatMode, "off")
    }

    func testRepeatModeCyclingOffAllOneOffPersistsAcrossStatusQueries() {
        defer {
            _ = PlaybackTransportController.shared.setRepeat(mode: "off")
            PlaybackStateStore.shared.resetCustomQueue()
        }
        PlaybackStateStore.shared.resetCustomQueue()
        PlaybackStateStore.shared.invalidateStatusCache(optimisticState: "stopped")

        // Rapid consecutive cycle off -> all -> one -> off while stopped (no active custom queue or playlist)
        let sequence = ["off", "all", "one", "off", "all", "one", "off"]
        for expected in sequence {
            XCTAssertTrue(PlaybackTransportController.shared.setRepeat(mode: expected))
            XCTAssertEqual(PlaybackStateStore.shared.repeatMode, expected, "Store repeatMode must equal \(expected)")
            let statusImmediate = PlayerStatusEngine.shared.getPlayerStatus()
            XCTAssertEqual(statusImmediate.repeatMode, expected, "Immediate getPlayerStatus() must preserve \(expected)")

            // Even if status cache expires / is invalidated while stopped, repeatMode must NOT revert to 'off'
            PlaybackStateStore.shared.invalidateStatusCache()
            let statusUncached = PlayerStatusEngine.shared.getPlayerStatus()
            XCTAssertEqual(statusUncached.repeatMode, expected, "Uncached getPlayerStatus() while stopped must preserve \(expected)")
        }
    }

    func testStaleDuplicateForeignNotificationDoesNotDoubleAdvanceQueue() {
        let track0 = TrackInfo(id: "ut-q0", numericId: nil, name: "UnitTest Open Eyes", artist: "UnitTest Apes", duration: 188.6, isLocal: false, index: 1)
        let track1 = TrackInfo(id: "ut-q1", numericId: nil, name: "UnitTest Sweet Apocalypse", artist: "UnitTest Lambert", duration: 163.0, isLocal: false, index: 2)
        let track2 = TrackInfo(id: "ut-q2", numericId: nil, name: "UnitTest Remember", artist: "UnitTest Olafur", duration: 295.0, isLocal: false, index: 3)

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [track0, track1, track2]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
            PlaybackStateStore.shared.lastConfirmedTrackTime = Date().addingTimeInterval(-187.0)
            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
            PlaybackStateStore.shared.lastCloudPlayTime = Date().addingTimeInterval(-188.0)
            PlaybackStateStore.shared.lastSkipTime = .distantPast
            PlaybackStateStore.shared.isUserPaused = false
        }

        // 1. Track 0 reaches end and Music.app briefly emits foreign track #1 -> advances 0 -> 1
        QueueManager.shared.handleTrackNotification(userInfo: [
            "Player State": "playing",
            "Name": "UnitTest Kids Arent Alright",
            "Artist": "UnitTest Offspring"
        ])
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 1, "First foreign track notification must advance 0 -> 1")

        // 2. Track 1 ("UnitTest Sweet Apocalypse") starts playing and confirms (+0.8s), clearing lastSkipTime
        QueueManager.shared.handleTrackNotification(userInfo: [
            "Player State": "playing",
            "Name": "UnitTest Sweet Apocalypse",
            "Artist": "UnitTest Lambert"
        ])
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 1)
        XCTAssertTrue(PlaybackStateStore.shared.currentTrackPlaybackConfirmed)
        XCTAssertFalse(PlaybackStateStore.shared.isTransitioningTrack)

        // 3. Delayed duplicate DistributedNotification for the same foreign track arrives +0.35s later:
        //    MUST be ignored and MUST NOT skip Track 1 to Track 2!
        QueueManager.shared.handleTrackNotification(userInfo: [
            "Player State": "playing",
            "Name": "UnitTest Kids Arent Alright",
            "Artist": "UnitTest Offspring"
        ])
        XCTAssertEqual(
            PlaybackStateStore.shared.activeCustomQueueIndex,
            1,
            "Stale duplicate foreign notification after Track 1 confirmation must NEVER skip Track 1 -> Track 2"
        )

        // 4. Even if foreign cooldown is simulated as expired at +5s, same foreign key within 12s + newly confirmed guard blocks skip
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastForeignInterceptTime = Date().addingTimeInterval(-5.0)
        }
        QueueManager.shared.handleTrackNotification(userInfo: [
            "Player State": "playing",
            "Name": "UnitTest Kids Arent Alright",
            "Artist": "UnitTest Offspring"
        ])
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 1)

        // 5. After Track 1 genuinely plays to completion (163s later), a new foreign track advances 1 -> 2 cleanly
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastCloudPlayTime = Date().addingTimeInterval(-163.0)
            PlaybackStateStore.shared.lastConfirmedTrackTime = Date().addingTimeInterval(-162.0)
            PlaybackStateStore.shared.lastForeignInterceptTime = Date().addingTimeInterval(-163.0)
            PlaybackStateStore.shared.lastKnownPosition = 162.5
        }
        QueueManager.shared.handleTrackNotification(userInfo: [
            "Player State": "playing",
            "Name": "UnitTest Next Library Song",
            "Artist": "UnitTest Library Artist"
        ])
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 2, "Legitimate EOF foreign track after full playback must advance 1 -> 2")
    }

    func testCloudQueuePlaysFullTrackEndingWithoutEarlySmartTransitionCutoff() {
        let vengeance = TrackInfo(
            id: "1583000000",
            numericId: nil,
            name: "Vengeance",
            artist: "coldrain",
            album: "Vengeance - Single",
            duration: 238.534,
            isLocal: false,
            index: 1,
            catalogId: "1583000000"
        )
        let likeFlames = TrackInfo(
            id: "1583000001",
            numericId: nil,
            name: "Like Flames",
            artist: "MindaRyn",
            album: "Like Flames",
            duration: 247.39,
            isLocal: false,
            index: 2,
            catalogId: "1583000001"
        )
        let thirdTrack = TrackInfo(
            id: "1600000099",
            numericId: nil,
            name: "Final Frontier",
            artist: "Synthsoldier",
            album: "Single",
            duration: 210.0,
            isLocal: false,
            index: 3,
            catalogId: "1600000099"
        )

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [vengeance, likeFlames, thirdTrack]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
            PlaybackStateStore.shared.isUserPaused = false
            PlaybackStateStore.shared.repeatMode = "off"
            PlaybackStateStore.shared.lastCloudPlayTime = Date().addingTimeInterval(-235.0)
            // MediaPlaybackCore scheduled Smart Transition / AutoMix 2.5s - 22s before EOF:
            // QueueManager must NEVER chop off the last 3-22 seconds of the song!
            PlaybackStateStore.shared.scheduledSmartTransitionStart = 232.5
            PlaybackStateStore.shared.nativeQueuedUpcomingCatalogIds = ["1583000001", "1600000099"]
            PlaybackStateStore.shared.lastKnownPosition = 234.0
            PlaybackStateStore.shared.lastPlayerStatusCache = (
                timestamp: Date(),
                status: PlayerStatus(
                    playerState: "playing",
                    position: 234.0,
                    duration: 238.534,
                    track: vengeance
                )
            )
        }

        // 1. 4.5s before EOF (past scheduledSmartTransitionStart=232.5s): must NOT cut off the song early!
        QueueManager.shared.checkAndAutoAdvanceCloudQueue()
        XCTAssertEqual(
            PlaybackStateStore.shared.activeCustomQueueIndex,
            0,
            "QueueManager must not cut off cloud queue tracks at MediaPlaybackCore's early fade-out timestamp"
        )

        // 2. Even at 238.45s (< 0.10s before EOF), while next cloud track is natively queued in SystemMusicPlayerBridge,
        //    must NOT call stop() — let Music.app transition natively into Like Flames!
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastKnownPosition = 238.45
            PlaybackStateStore.shared.lastPlayerStatusCache = (
                timestamp: Date(),
                status: PlayerStatus(
                    playerState: "playing",
                    position: 238.45,
                    duration: 238.534,
                    track: vengeance
                )
            )
        }
        QueueManager.shared.checkAndAutoAdvanceCloudQueue()
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 0)

        // 3. Music.app naturally advances to Like Flames -> index updates to 1, queued list pops slot 0, position resets
        QueueManager.shared.handleTrackNotification(userInfo: [
            "Player State": "playing",
            "Name": "Like Flames",
            "Artist": "MindaRyn"
        ])
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 1)
        XCTAssertEqual(
            PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.nativeQueuedUpcomingCatalogIds },
            ["1600000099"]
        )
        XCTAssertEqual(PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.lastKnownPosition }, 0.0)
        XCTAssertNil(PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.scheduledSmartTransitionStart })

        // 4. On a boundary track where nativeQueuedUpcomingCatalogIds is empty, still plays full tail (no cut at 225s / 244s)
        //    and only advances inside the final 0.18s EOF window!
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.nativeQueuedUpcomingCatalogIds.removeAll()
            PlaybackStateStore.shared.scheduledSmartTransitionStart = 225.45
            PlaybackStateStore.shared.lastKnownPosition = 244.0
            PlaybackStateStore.shared.lastPlayerStatusCache = (
                timestamp: Date(),
                status: PlayerStatus(
                    playerState: "playing",
                    position: 244.0,
                    duration: 247.39,
                    track: likeFlames
                )
            )
        }
        QueueManager.shared.checkAndAutoAdvanceCloudQueue()
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 1, "Must not cut off 3.4s before EOF")

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastKnownPosition = 247.25
            PlaybackStateStore.shared.lastPlayerStatusCache = (
                timestamp: Date(),
                status: PlayerStatus(
                    playerState: "playing",
                    position: 247.25,
                    duration: 247.39,
                    track: likeFlames
                )
            )
        }
        QueueManager.shared.checkAndAutoAdvanceCloudQueue()
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 2, "Boundary track advances cleanly within final 0.18s EOF window")
    }

    func testSmartTransitionImmediateZeroLagUIAdvanceAndOverlapStatusHold() {
        // 1. Verify MediaPlaybackCore smartTransitionWillBegin log extraction
        let logLine = "[MediaPlaybackCore] smartTransitionWillBegin - <ITMPAVItem: 0xb4fa1dc00> (8599::8604) Big In Japan [166.51s] -> <ITMPAVItem: 0xb52ca9500> (8599::8605) Lords of the Boards [1.09s]"
        let range = NSRange(logLine.startIndex..<logLine.endIndex, in: logLine)
        let match = BitPerfectLogMonitor.smartTransitionItemsPattern.firstMatch(in: logLine, options: [], range: range)
        XCTAssertNotNil(match)
        let parsedOutgoing = match.flatMap { Range($0.range(at: 1), in: logLine) }.map { String(logLine[$0]) }
        let parsedIncoming = match.flatMap { Range($0.range(at: 3), in: logLine) }.map { String(logLine[$0]) }
        let parsedStartPos = match.flatMap { Range($0.range(at: 4), in: logLine) }.flatMap { Double(logLine[$0]) }
        XCTAssertEqual(parsedOutgoing, "Big In Japan")
        XCTAssertEqual(parsedIncoming, "Lords of the Boards")
        XCTAssertEqual(parsedStartPos ?? -1, 1.09, accuracy: 0.001)

        // 2. Seed a 3-track cloud queue on track 0 ("Big In Japan") with native upcoming tracks queued
        let bigInJapan = TrackInfo(
            id: "1440857780",
            numericId: nil,
            name: "Big In Japan",
            artist: "Guano Apes",
            album: "Don't Give Me Names",
            duration: 169.2,
            artworkUrl: "https://example.com/big-in-japan.jpg",
            isLocal: false,
            index: 1,
            catalogId: "1440857780"
        )
        let lordsOfTheBoards = TrackInfo(
            id: "1440857781",
            numericId: nil,
            name: "Lords of the Boards",
            artist: "Guano Apes",
            album: "Proud Like a God",
            duration: 218.5,
            artworkUrl: "https://example.com/lords-of-the-boards.jpg",
            isLocal: false,
            index: 2,
            catalogId: "1440857781"
        )
        let youCantStopMe = TrackInfo(
            id: "1440857782",
            numericId: nil,
            name: "You Can't Stop Me",
            artist: "Guano Apes",
            album: "Walking on a Thin Line",
            duration: 193.0,
            artworkUrl: "https://example.com/you-cant-stop-me.jpg",
            isLocal: false,
            index: 3,
            catalogId: "1440857782"
        )

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [bigInJapan, lordsOfTheBoards, youCantStopMe]
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.activeCustomQueueName = "90s Alt Rock"
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
            PlaybackStateStore.shared.isUserPaused = false
            PlaybackStateStore.shared.repeatMode = "off"
            PlaybackStateStore.shared.nativeQueuedUpcomingCatalogIds = ["1440857781", "1440857782"]
            PlaybackStateStore.shared.lastKnownPosition = 166.51
        }

        // 3. Fire immediate Smart Transition start -> queue index jumps 0 -> 1 immediately with initialPosition = 1.09s
        QueueManager.shared.handleImmediateSmartTransitionBegan(
            outgoingTitle: parsedOutgoing,
            incomingTitle: parsedIncoming,
            incomingStartPos: parsedStartPos
        )
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 1)
        XCTAssertEqual(
            PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.nativeQueuedUpcomingCatalogIds },
            ["1440857782"]
        )
        let overlap = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.activeOverlapTransition }
        XCTAssertNotNil(overlap)
        XCTAssertEqual(overlap?.outgoingName, "Big In Japan")
        XCTAssertEqual(overlap?.incomingTrack.name, "Lords of the Boards")
        XCTAssertEqual(overlap?.initialPosition ?? -1, 1.09, accuracy: 0.001)

        // 4. Duplicate `overlappedPlaybackWillBegin` log line for the same transition MUST be idempotent (must NOT advance 1 -> 2!)
        QueueManager.shared.handleImmediateSmartTransitionBegan(
            outgoingTitle: "Big In Japan",
            incomingTitle: "Lords of the Boards",
            incomingStartPos: 1.09
        )
        XCTAssertEqual(PlaybackStateStore.shared.activeCustomQueueIndex, 1)

        // 5. While Music.app is in OverlappedTransitionState before pivotPoint (AppleScript still reports "Big In Japan" at 167.8s),
        //    PlayerStatusEngine must keep returning "Lords of the Boards" with interpolated position >= 1.09s and incoming cover art!
        var outgoingDrainSample = RawMusicAppStatusSample()
        outgoingDrainSample.rawState = "playing"
        outgoingDrainSample.rawPos = 167.8
        outgoingDrainSample.dur = 169.2
        outgoingDrainSample.tName = "Big In Japan"
        outgoingDrainSample.tArtist = "Guano Apes"
        outgoingDrainSample.tAlbum = "Don't Give Me Names"

        let statusDuringOverlap = PlayerStatusEngine.shared.assemblePlayerStatusLocked(
            sample: outgoingDrainSample,
            isRadio: false,
            stationName: nil,
            isCustom: true,
            customQueue: [bigInJapan, lordsOfTheBoards, youCantStopMe],
            customIndex: 1,
            customName: "90s Alt Rock",
            storeRepMode: "off",
            origPl: nil
        )
        XCTAssertEqual(statusDuringOverlap.track?.name, "Lords of the Boards")
        XCTAssertEqual(statusDuringOverlap.track?.album, "Proud Like a God")
        XCTAssertEqual(statusDuringOverlap.track?.artworkUrl, "https://example.com/lords-of-the-boards.jpg")
        XCTAssertGreaterThanOrEqual(statusDuringOverlap.position, 1.09)
        XCTAssertLessThan(statusDuringOverlap.position, 5.0)

        // 6. Once Music.app reaches pivotPoint and reports "Lords of the Boards" at 6.65s, activeOverlapTransition clears cleanly
        var pivotSample = RawMusicAppStatusSample()
        pivotSample.rawState = "playing"
        pivotSample.rawPos = 6.65
        pivotSample.dur = 218.5
        pivotSample.tName = "Lords of the Boards"
        pivotSample.tArtist = "Guano Apes"
        pivotSample.tAlbum = "Proud Like a God"

        let statusAtPivot = PlayerStatusEngine.shared.assemblePlayerStatusLocked(
            sample: pivotSample,
            isRadio: false,
            stationName: nil,
            isCustom: true,
            customQueue: [bigInJapan, lordsOfTheBoards, youCantStopMe],
            customIndex: 1,
            customName: "90s Alt Rock",
            storeRepMode: "off",
            origPl: nil
        )
        XCTAssertEqual(statusAtPivot.track?.name, "Lords of the Boards")
        XCTAssertEqual(statusAtPivot.position, 6.65, accuracy: 0.05)
        XCTAssertNil(PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.activeOverlapTransition })
    }

    func testSettingsTabHasDedicatedTVSection() {
        let tabs = SettingsTab.allCases
        XCTAssertEqual(tabs, [.general, .tv, .playback, .dsp, .amplifier, .wled, .advanced])
        XCTAssertEqual(SettingsTab.tv.symbolName, "tv")
    }

    @MainActor
    func testSettingsWindowAllSevenTabsLayoutCleanly() {
        let settings = SettingsWindow.shared
        XCTAssertNotNil(settings.window)
        for tab in SettingsTab.allCases {
            settings.selectTabForTesting(tab)
            XCTAssertEqual(settings.window?.title, tab.windowTitle)
            let frameWidth = settings.window?.contentView?.frame.width ?? 0
            XCTAssertEqual(frameWidth, 700, accuracy: 2.0, "Tab \(tab) must maintain uniform 700pt Music.app width")
        }
    }
}
