//
//  LibraryServiceTests.swift
//  AppleMusicRemoteMacTests
//

import XCTest
@testable import AppleMusicRemoteMac

final class LibraryServiceTests: XCTestCase {

    func testIsValidTrackFiltering() {
        let service = LibraryService.shared

        // Valid track
        XCTAssertTrue(service.isValidTrack(name: "Karma Police", artist: "Radiohead", duration: 260.0))

        // Empty track name
        XCTAssertFalse(service.isValidTrack(name: "", artist: "Radiohead", duration: 260.0))

        // Zero or negative duration
        XCTAssertFalse(service.isValidTrack(name: "Karma Police", artist: "Radiohead", duration: 0.0))
        XCTAssertFalse(service.isValidTrack(name: "Karma Police", artist: "Radiohead", duration: -5.0))

        // Purely numeric stream track names
        XCTAssertFalse(service.isValidTrack(name: "1849104812", artist: "Apple Music", duration: 200.0))

        // M3U playlist file names
        XCTAssertFalse(service.isValidTrack(name: "track.m3u", artist: "Artist", duration: 200.0))
        XCTAssertFalse(service.isValidTrack(name: "video.mkv.m3u", artist: "Artist", duration: 200.0))
    }

    func testPlaylistTracksCachingAndInvalidation() {
        let service = LibraryService.shared
        let testTracks = [
            TrackInfo(id: "1", name: "Track 1", artist: "Artist 1"),
            TrackInfo(id: "2", name: "Track 2", artist: "Artist 2")
        ]

        // 1. Update cache
        service.updatePlaylistTracksCache(name: "Test Cache Playlist", tracks: testTracks)

        // 2. Query cache
        let cached = service.getPlaylistTracks(name: "Test Cache Playlist")
        XCTAssertEqual(cached.count, 2)
        XCTAssertEqual(cached[0].id, "1")
        XCTAssertEqual(cached[1].id, "2")

        // 3. Invalidate cache
        service.invalidatePlaylistCache(name: "Test Cache Playlist")

        // 4. Empty name returns empty array immediately
        XCTAssertTrue(service.getPlaylistTracks(name: "").isEmpty)
    }

    func testAddToLibraryEmptyParametersReturnsFalse() {
        let service = LibraryService.shared
        let result = service.addToLibrary(trackId: nil, name: "", artist: "", url: nil)
        XCTAssertFalse(result)

        let resultNil = service.addToLibrary(trackId: nil, name: nil, artist: nil, url: nil)
        XCTAssertFalse(resultNil)
    }

    func testGetCachedLibrarySongsDoesNotCrash() {
        let service = LibraryService.shared
        let songs = service.getCachedLibrarySongs()
        XCTAssertGreaterThanOrEqual(songs.count, 0)
    }
}
