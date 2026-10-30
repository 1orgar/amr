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
}
