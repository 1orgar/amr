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

    func testOptimisticPauseTracking() {
        let store = PlaybackStateStore.shared

        store.invalidateStatusCache(optimisticState: "paused")
        XCTAssertTrue(store.isUserPaused)

        store.invalidateStatusCache(optimisticState: "playing")
        XCTAssertFalse(store.isUserPaused)
    }

    func testAggregateLibraryAlbumsExcludesStagedTracksAndMergesFeaturedArtists() {
        let songs: [TrackInfo] = [
            TrackInfo(id: "9001", numericId: 9001, name: "UnitTest Staged Single", artist: "UnitTest Temp Artist", album: "UnitTest Temp Single", duration: 200, isLocal: false, index: 100),
            TrackInfo(id: "101", numericId: 101, name: "UnitTest Intro", artist: "UnitTest Chamber Artist", album: "UnitTest Remember", duration: 185, isLocal: false, index: 10),
            TrackInfo(id: "102", numericId: 102, name: "UnitTest Duet", artist: "UnitTest Chamber Artist & Guest", album: "UnitTest Remember", duration: 240, isLocal: false, index: 11),
            TrackInfo(id: "103", numericId: 103, name: "UnitTest Finale", artist: "UnitTest Chamber Artist", album: "UnitTest Remember", duration: 210, isLocal: false, index: 12),
            TrackInfo(id: "201", numericId: 201, name: "UnitTest Hit A", artist: "UnitTest Band Alpha", album: "UnitTest Anthology", duration: 195, isLocal: false, index: 20),
            TrackInfo(id: "202", numericId: 202, name: "UnitTest Hit B", artist: "UnitTest Band Beta", album: "UnitTest Anthology", duration: 205, isLocal: false, index: 30)
        ]

        let albums = LibraryService.aggregateLibraryAlbums(from: songs, excludingStagedDbIds: [9001])

        XCTAssertEqual(albums.count, 3)
        XCTAssertFalse(albums.contains { $0.name == "UnitTest Temp Single" })

        // Ordered by maxOrderIndex descending: Band Beta (30), Band Alpha (20), Chamber Artist (12)
        XCTAssertEqual(albums[0].artist, "UnitTest Band Beta")
        XCTAssertEqual(albums[1].artist, "UnitTest Band Alpha")

        let mergedAlbum = albums[2]
        XCTAssertEqual(mergedAlbum.name, "UnitTest Remember")
        XCTAssertEqual(mergedAlbum.artist, "UnitTest Chamber Artist")
        XCTAssertEqual(mergedAlbum.trackCount, 3)
        XCTAssertEqual(mergedAlbum.inLibrary, true)
    }

    func testPromoteStagedTracksForSavedAlbumRemovesOnlySavedAlbumIds() {
        let store = PlaybackStateStore.shared
        let originalStaged = store.withLock { store.stagedTemporaryTrackDbIds }
        defer {
            store.withLock { store.stagedTemporaryTrackDbIds = originalStaged }
            AppStorageProvider.shared.set(Array(originalStaged), forKey: "AMRStagedTemporaryTrackDbIds")
        }

        store.setTrackMetadata(id: 77001, name: "UnitTest Track 1", artist: "UnitTest Ólafur", album: "UnitTest re:member")
        store.setTrackMetadata(id: 77002, name: "UnitTest Other", artist: "UnitTest Other Artist", album: "UnitTest Other Album")
        store.registerStagedTemporaryTrack(dbId: 77001)
        store.registerStagedTemporaryTrack(dbId: 77002)

        store.promoteStagedTracksForSavedAlbum(name: "UnitTest re:member", artist: "UnitTest Olafur", tracks: [])

        let remaining = store.withLock { store.stagedTemporaryTrackDbIds }
        XCTAssertFalse(remaining.contains(77001))
        XCTAssertTrue(remaining.contains(77002))
    }

    func testRecentlyAddedAlbumsAndMergeLibraryAlbums() throws {
        let mk = MusicKitManager.shared
        mk.clearRecentlyAddedAlbumsForTesting()
        defer { mk.clearRecentlyAddedAlbumsForTesting() }

        mk.recordAddedAlbumToLibrary(
            albumId: "1390704147",
            name: "UnitTest re:member",
            artist: "UnitTest Ólafur Arnalds",
            artwork: "https://example.com/art600.jpg",
            trackCount: 12
        )

        XCTAssertTrue(mk.isAlbumInLibraryOrRecentlyAdded(albumId: "1390704147", name: "", artist: ""))
        XCTAssertTrue(mk.isAlbumInLibraryOrRecentlyAdded(albumId: "", name: "unittest re:member", artist: "UnitTest Olafur Arnalds"))

        let local = [
            AlbumInfo(id: "4421", name: "UnitTest re:member", artist: "UnitTest Ólafur Arnalds", artwork: "/api/artwork/search?name=x", trackCount: 12, inLibrary: true),
            AlbumInfo(id: "4400", name: "UnitTest Local FLAC", artist: "UnitTest Trio", artwork: "/api/artwork/track?id=4400", trackCount: 8, inLibrary: true)
        ]

        let merged = MusicBridge.mergeLibraryAlbums(
            cloud: [],
            local: local,
            recentlyAdded: mk.getRecentlyAddedAlbums()
        )

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].id, "1390704147")
        XCTAssertEqual(merged[0].artwork, "https://example.com/art600.jpg")
        XCTAssertEqual(merged[0].trackCount, 12)
        XCTAssertEqual(merged[0].inLibrary, true)
        XCTAssertEqual(merged[1].name, "UnitTest Local FLAC")

        let jsonData = try JSONEncoder().encode(merged[0])
        let jsonObj = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        XCTAssertEqual(jsonObj?["in_library"] as? Bool, true)
    }
}
