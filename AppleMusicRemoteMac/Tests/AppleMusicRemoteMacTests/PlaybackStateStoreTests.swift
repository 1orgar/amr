import XCTest
@testable import AppleMusicRemoteMac

final class PlaybackStateStoreTests: XCTestCase {

    func testThreadSafeLock() {
        let store = PlaybackStateStore.shared
        let iterations = 1000
        let exp = expectation(description: "Concurrent access to PlaybackStateStore")
        exp.expectedFulfillmentCount = 2

        DispatchQueue.global(qos: .userInitiated).async {
            for i in 0..<iterations {
                store.withLock {
                    store.activeCustomQueueIndex = i
                }
            }
            exp.fulfill()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            for i in 0..<iterations {
                store.withLock {
                    _ = store.activeCustomQueueIndex
                }
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 5.0)
    }

    func testCustomQueueReset() {
        let store = PlaybackStateStore.shared

        store.withLock {
            store.isCustomQueuePlayback = true
            store.activeCustomQueue = [
                TrackInfo(id: "1", numericId: 1, name: "Track 1", artist: "Artist", album: "Album", duration: 180, hasArtwork: false, artworkUrl: "", favorited: false, isLocal: false, url: nil, previewUrl: nil, index: 1)
            ]
            store.activeCustomQueueIndex = 0
            store.activeCustomQueueName = "Test Album"
        }

        XCTAssertTrue(store.isCustomQueuePlayback)
        XCTAssertEqual(store.activeCustomQueue.count, 1)

        store.resetPlaybackState()

        XCTAssertFalse(store.isCustomQueuePlayback)
        XCTAssertTrue(store.activeCustomQueue.isEmpty)
        XCTAssertNil(store.activeCustomQueueName)
    }
}
