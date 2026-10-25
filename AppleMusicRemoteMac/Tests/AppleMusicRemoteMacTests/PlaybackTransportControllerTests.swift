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
}
