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
}
