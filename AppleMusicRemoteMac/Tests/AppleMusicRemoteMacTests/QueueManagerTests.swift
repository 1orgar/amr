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
}
