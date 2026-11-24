//
//  PlaybackTransportControllerTests.swift
//  AppleMusicRemoteMacTests
//

import XCTest
@testable import AppleMusicRemoteMac

final class PlaybackTransportControllerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PlaybackStateStore.shared.resetPlaybackState()
    }

    override func tearDown() {
        PlaybackStateStore.shared.resetPlaybackState()
        super.tearDown()
    }

    func testPauseSetsUserPausedAndInvalidatesCache() {
        let store = PlaybackStateStore.shared
        let transport = PlaybackTransportController.shared

        // Set initial playing state
        store.invalidateStatusCache(optimisticState: "playing")
        XCTAssertFalse(store.isUserPaused)

        // Call pause
        let result = transport.pause()
        XCTAssertTrue(result, "pause() should return true")

        // Verify isUserPaused is true
        let isPaused = store.withLock { store.isUserPaused }
        XCTAssertTrue(isPaused, "isUserPaused must be set to true after pause()")

        // Verify cached state is paused
        let cached = store.withLock { store.lastPlayerStatusCache }
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.status.playerState, "paused", "lastPlayerStatusCache must report paused")
    }

    func testPlayClearsUserPausedAndSetsPlaying() {
        let store = PlaybackStateStore.shared
        let transport = PlaybackTransportController.shared

        // Set paused
        store.invalidateStatusCache(optimisticState: "paused")
        XCTAssertTrue(store.isUserPaused)

        // Call play
        _ = transport.play()

        // Verify isUserPaused is cleared
        let isPaused = store.withLock { store.isUserPaused }
        XCTAssertFalse(isPaused, "isUserPaused must be false after play()")

        // Verify cached state is playing
        let cached = store.withLock { store.lastPlayerStatusCache }
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.status.playerState, "playing", "lastPlayerStatusCache must report playing")
    }

    func testStopSetsStoppedAndClearsSeekTarget() {
        let store = PlaybackStateStore.shared
        let transport = PlaybackTransportController.shared

        store.setSeekTarget(position: 42.0)
        XCTAssertNotNil(store.seekTargetPosition)

        _ = transport.stop()

        XCTAssertTrue(store.isUserPaused)
        XCTAssertNil(store.seekTargetPosition, "stop() must clear seekTargetPosition")
        let cached = store.withLock { store.lastPlayerStatusCache }
        XCTAssertEqual(cached?.status.playerState, "stopped", "lastPlayerStatusCache must report stopped")
    }

    func testPlayPauseTogglesState() {
        let store = PlaybackStateStore.shared
        let transport = PlaybackTransportController.shared

        // 1. Force state to playing in cache
        store.invalidateStatusCache(optimisticState: "playing")
        XCTAssertFalse(store.isUserPaused)

        // 2. Toggling while playing should call pause()
        _ = transport.playPause()
        XCTAssertTrue(store.isUserPaused, "playPause() while playing must pause")

        // 3. Toggling while paused should call play()
        _ = transport.playPause()
        XCTAssertFalse(store.isUserPaused, "playPause() while paused must resume play")
    }

    func testRadioRepeatOneSeeksToZeroWithoutResettingRadioSession() {
        let store = PlaybackStateStore.shared
        let radioTrack = TrackInfo(
            id: "radio_1",
            numericId: nil,
            name: "Midnight City",
            artist: "M83",
            album: "Hurry Up, We're Dreaming",
            duration: 240.0,
            isLocal: false
        )

        store.withLock {
            store.isRadioPlayback = true
            store.activeStationName = "Моя станция"
            store.isCustomQueuePlayback = false
            store.repeatMode = "one"
            store.repeatOnePinnedTrack = radioTrack
            store.lastRepeatOneRewindTime = .distantPast
            store.seekTargetPosition = nil
            store.lastPlayerStatusCache = (
                Date(),
                PlayerStatus(
                    playerState: "playing",
                    position: 238.5,
                    duration: 240.0,
                    volume: 100,
                    shuffle: false,
                    repeatMode: "one",
                    playlist: "Моя станция",
                    isRadio: true,
                    track: radioTrack
                )
            )
        }

        QueueManager.shared.enforceRadioRepeatOneLocked()
        XCTAssertEqual(store.seekTargetPosition, 0.0, "Radio Repeat-One must seek current radio track to 0:00 before track end")
        XCTAssertTrue(store.isRadioPlayback, "Radio session must stay active after Repeat-One rewind")
        XCTAssertFalse(store.isCustomQueuePlayback, "Radio Repeat-One must never replace radio with a custom queue")
        XCTAssertEqual(store.activeStationName, "Моя станция")

        // Verify Smart Transition cutoff also seeks to 0:00 early without resetting radio
        store.withLock {
            store.lastRepeatOneRewindTime = .distantPast
            store.seekTargetPosition = nil
            store.scheduledSmartTransitionStart = 228.0
            store.lastPlayerStatusCache = (
                Date(),
                PlayerStatus(
                    playerState: "playing",
                    position: 227.7,
                    duration: 240.0,
                    volume: 100,
                    shuffle: false,
                    repeatMode: "one",
                    playlist: "Моя станция",
                    isRadio: true,
                    track: radioTrack
                )
            )
        }
        QueueManager.shared.enforceRadioRepeatOneLocked()
        XCTAssertEqual(store.seekTargetPosition, 0.0, "Smart Transition schedule during Radio Repeat-One must seek to 0:00 before crossfade")
        XCTAssertTrue(store.isRadioPlayback)
        XCTAssertFalse(store.isCustomQueuePlayback)

        // Verify track change on radio updates pinned track in-place without destroying radio session
        let nextRadioTrack = TrackInfo(id: "radio_2", numericId: nil, name: "Starlight", artist: "Muse", duration: 240.0, isLocal: false)
        store.withLock {
            store.lastPlayerStatusCache = (
                Date(),
                PlayerStatus(
                    playerState: "playing",
                    position: 12.0,
                    duration: 240.0,
                    volume: 100,
                    shuffle: false,
                    repeatMode: "one",
                    playlist: "Моя станция",
                    isRadio: true,
                    track: nextRadioTrack
                )
            )
        }
        QueueManager.shared.enforceRadioRepeatOneLocked(triggerTrackName: "Starlight", triggerArtistName: "Muse")
        XCTAssertTrue(store.isRadioPlayback, "Radio session must never be reset when station advances")
        XCTAssertFalse(store.isCustomQueuePlayback)
        XCTAssertEqual(store.repeatOnePinnedTrack?.name, "Starlight")
    }

    func testLocalPlaylistShuffleNeverRegeneratesQueueAcrossTracks() async {
        let localTracks = (1...8).map { i in
            TrackInfo(
                id: "loc_\(i)",
                numericId: 500 + i,
                name: "Local Song \(i)",
                artist: "Local Artist",
                album: "Local Album",
                duration: 200,
                isLocal: true,
                index: i
            )
        }

        XCTAssertTrue(PlaybackRouter.shared.playCustomTracks(localTracks, startIndex: -1, shuffle: true, queueName: "Локальный рок"))
        let initialShuffledIds = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.activeCustomQueue.map(\.id) }
        XCTAssertEqual(initialShuffledIds.count, 8)

        for step in 1...4 {
            PlaybackTransportController.shared.resetDebounceForTesting()
            XCTAssertTrue(PlaybackTransportController.shared.nextTrack())
            let currentOrder = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.activeCustomQueue.map(\.id) }
            XCTAssertEqual(currentOrder, initialShuffledIds, "Shuffled local playlist queue must never regenerate after track \(step)")

            let q = await QueueManager.shared.getPlaybackQueue()
            XCTAssertEqual(q.currentIndex, step)
            XCTAssertEqual(q.upcomingTracks.map(\.id), Array(initialShuffledIds[(step + 1)...]))
            XCTAssertEqual(q.historyTracks.map(\.id), Array(initialShuffledIds[0..<step].reversed()))
        }

        // Disabling shuffle restores unshuffled local playlist order anchored at the active song
        let activeSongId = initialShuffledIds[4]
        XCTAssertTrue(PlaybackTransportController.shared.setShuffle(false))
        let restoredIds = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.activeCustomQueue.map(\.id) }
        XCTAssertEqual(restoredIds, localTracks.map(\.id))
        let restoredIdx = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.activeCustomQueueIndex }
        XCTAssertEqual(restoredIds[restoredIdx], activeSongId)
    }

    func testPreviousTracksRenderedInQueuePayloadAndWebUI() {
        let store = PlaybackStateStore.shared
        store.withLock {
            store.radioHistoryTracks.removeAll()
            store.lastRadioTrackSnapshot = nil
            let t1 = TrackInfo(id: "r1", name: "Radio Song One", artist: "Artist 1", duration: 180, isLocal: false)
            let t2 = TrackInfo(id: "r2", name: "Radio Song Two", artist: "Artist 2", duration: 195, isLocal: false)
            store.recordRadioTrackTransitionLocked(current: t1, stationName: "Моя станция")
            store.recordRadioTrackTransitionLocked(current: t2, stationName: "Моя станция")
            XCTAssertEqual(store.radioHistoryTracks.map(\.name), ["Radio Song One"])
        }

        XCTAssertTrue(WebUIContent.indexHTML.contains("id=\"queue-history-group\""))
        XCTAssertTrue(WebUIContent.indexHTML.contains("id=\"queue-history-list\""))
        XCTAssertTrue(WebUIContent.appJS.contains("renderQueueHistorySection"))
        XCTAssertTrue(WebUIContent.appJS.contains("play_history_index"))
    }
}
