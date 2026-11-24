//
//  ArtworkDiskCacheTests.swift
//  AppleMusicRemoteMacTests
//

import XCTest
@testable import AppleMusicRemoteMac

final class ArtworkDiskCacheTests: XCTestCase {

    private var cache: ArtworkDiskCache!

    override func setUp() {
        super.setUp()
        cache = ArtworkDiskCache(maxSizeMB: 5)
        cache.clear()
    }

    override func tearDown() {
        cache.clear()
        super.tearDown()
    }

    func testSetAndGetArtworkData() {
        let sampleData = Data("sample_artwork_data_bytes_12345".utf8)
        let key = "test_album_queen_night_at_the_opera"

        cache.set(key: key, data: sampleData)

        // Wait a small moment for async disk write
        let exp = expectation(description: "Wait for disk write")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            let retrieved = self.cache.get(key: key)
            XCTAssertEqual(retrieved, sampleData)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    func testRemoveArtwork() {
        let sampleData = Data("sample_bytes".utf8)
        let key = "test_track_to_remove"
        cache.set(key: key, data: sampleData)

        let exp = expectation(description: "Wait for write then delete")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            self.cache.remove(key: key)
            let retrieved = self.cache.get(key: key)
            XCTAssertNil(retrieved)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    func testTotalCacheSizeAndClear() {
        let sampleData = Data(repeating: 0x42, count: 1024) // 1 KB
        cache.set(key: "item1", data: sampleData)
        cache.set(key: "item2", data: sampleData)

        let exp = expectation(description: "Wait for write")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
            let size = self.cache.totalCacheSize()
            XCTAssertGreaterThanOrEqual(size, 2048)

            self.cache.clear()
            let clearedSize = self.cache.totalCacheSize()
            XCTAssertEqual(clearedSize, 0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    func testArtworkUrlDiskCachePersistsAndReloads() {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("amr_url_cache_test_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let urlCache = ArtworkUrlDiskCache(directory: tempDir)
        let cdnUrl = "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/aa/bb/cc/600x600bb.jpg"
        urlCache.storeTrackUrl(cdnUrl, forKeys: ["saman|ólafur arnalds|re:member"])
        urlCache.storeAlbumArtworks([
            (normTitle: MusicKitManager.normalizedAlbumTitle("re:member"), album: "re:member", artist: "Ólafur Arnalds", url: cdnUrl)
        ])

        let exp = expectation(description: "Wait for debounced URL index write")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.75) {
            let reloaded = ArtworkUrlDiskCache(directory: tempDir)
            let snap = reloaded.snapshot()
            XCTAssertEqual(snap.tracks["saman|ólafur arnalds|re:member"], cdnUrl)
            let normTitle = MusicKitManager.normalizedAlbumTitle("re:member")
            XCTAssertEqual(snap.albums[normTitle]?.first?.url, cdnUrl)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.5)
    }

    func testAlbumLevelArtworkCacheUpgradesSiblingTracksWithoutArtistCollision() {
        let mk = MusicKitManager.shared
        let queenCover = "https://is1-ssl.mzstatic.com/image/thumb/Music115/queen_gh/600x600bb.jpg"
        let offspringCover = "https://is1-ssl.mzstatic.com/image/thumb/Music115/offspring_gh/600x600bb.jpg"
        let olafurCover = "https://is1-ssl.mzstatic.com/image/thumb/Music126/olafur_remember/600x600bb.jpg"

        mk.registerAlbumArtwork(album: "Greatest Hits", artist: "Queen", url: queenCover, persist: false)
        mk.registerAlbumArtwork(album: "Greatest Hits", artist: "The Offspring", url: offspringCover, persist: false)
        mk.registerAlbumArtwork(album: "re:member", artist: "Ólafur Arnalds", url: olafurCover, persist: false)

        // Distinct artists with identical album title must never collide
        XCTAssertEqual(mk.getCachedAlbumArtwork(album: "Greatest Hits", artist: "Queen"), queenCover)
        XCTAssertEqual(mk.getCachedAlbumArtwork(album: "Greatest Hits", artist: "The Offspring"), offspringCover)

        // Track with featured guest artist on the same album resolves parent album CDN cover
        XCTAssertEqual(
            mk.getCachedTrackArtwork(name: "unfold", artist: "Ólafur Arnalds & SOHN", album: "re:member"),
            olafurCover
        )

        // LibraryService upgrades proxy /api/artwork/... URLs to direct Apple CDN URLs
        let proxySongs = [
            TrackInfo(
                id: "101",
                numericId: 101,
                name: "re:member",
                artist: "Ólafur Arnalds",
                album: "re:member",
                duration: 290,
                hasArtwork: true,
                artworkUrl: "/api/artwork/track?id=101&name=re%3Amember",
                isLocal: true
            ),
            TrackInfo(
                id: "102",
                numericId: 102,
                name: "Self Esteem",
                artist: "The Offspring",
                album: "Greatest Hits",
                duration: 257,
                hasArtwork: true,
                artworkUrl: "/api/artwork/search?name=Self%20Esteem",
                isLocal: true
            )
        ]
        let upgraded = LibraryService.upgradeTrackArtworksFromCache(proxySongs)
        XCTAssertEqual(upgraded[0].artworkUrl, olafurCover)
        XCTAssertEqual(upgraded[1].artworkUrl, offspringCover)
    }
}
