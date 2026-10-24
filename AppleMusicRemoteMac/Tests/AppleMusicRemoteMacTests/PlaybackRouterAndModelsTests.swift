//
//  PlaybackRouterAndModelsTests.swift
//  AppleMusicRemoteMacTests
//

import XCTest
@testable import AppleMusicRemoteMac

final class PlaybackRouterAndModelsTests: XCTestCase {

    func testPlayerStatusDefaultInitialization() {
        let status = PlayerStatus()
        XCTAssertEqual(status.playerState, "stopped")
        XCTAssertEqual(status.position, 0)
        XCTAssertEqual(status.duration, 0)
        XCTAssertEqual(status.volume, 50)
        XCTAssertFalse(status.shuffle)
        XCTAssertEqual(status.repeatMode, "off")
        XCTAssertEqual(status.playlist, "Музыка")
        XCTAssertFalse(status.isRadio)
        XCTAssertTrue(status.isMusicAppRunning)
        XCTAssertNil(status.track)
    }

    func testPlayerStatusEncodingAndDecodingWithMusicAppRunning() throws {
        let track = TrackInfo(
            id: "12345",
            numericId: 12345,
            name: "Starman",
            artist: "David Bowie",
            album: "The Rise and Fall of Ziggy Stardust",
            duration: 250,
            hasArtwork: true,
            artworkUrl: "https://example.com/starman.jpg",
            favorited: true,
            isLocal: false
        )

        let original = PlayerStatus(
            playerState: "playing",
            position: 45.5,
            duration: 250.0,
            volume: 80,
            shuffle: true,
            repeatMode: "all",
            playlist: "Favorites",
            isRadio: false,
            audioQuality: "Lossless (ALAC 24-bit/48kHz)",
            isMusicAppRunning: true,
            track: track
        )

        let data = try JSONEncoder().encode(original)
        let jsonString = String(data: data, encoding: .utf8)!

        XCTAssertTrue(jsonString.contains("\"player_state\":\"playing\""))
        XCTAssertTrue(jsonString.contains("\"is_music_app_running\":true"))
        XCTAssertTrue(jsonString.contains("\"name\":\"Starman\""))

        let decoded = try JSONDecoder().decode(PlayerStatus.self, from: data)
        XCTAssertEqual(decoded.playerState, "playing")
        XCTAssertEqual(decoded.position, 45.5)
        XCTAssertEqual(decoded.duration, 250.0)
        XCTAssertEqual(decoded.volume, 80)
        XCTAssertTrue(decoded.shuffle)
        XCTAssertEqual(decoded.repeatMode, "all")
        XCTAssertEqual(decoded.playlist, "Favorites")
        XCTAssertTrue(decoded.isMusicAppRunning)
        XCTAssertEqual(decoded.track?.name, "Starman")
        XCTAssertEqual(decoded.track?.artist, "David Bowie")
    }

    func testPlayerStatusDecodingLegacyJSONMissingMusicAppRunning() throws {
        // Simulating older payloads from client or previous server version without is_music_app_running
        let legacyJSON = """
        {
            "player_state": "playing",
            "position": 12.0,
            "duration": 180.0,
            "volume": 70,
            "shuffle": false,
            "repeat": "off",
            "playlist": "My Playlist",
            "is_radio": false,
            "audio_quality": "Lossless"
        }
        """

        let data = legacyJSON.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PlayerStatus.self, from: data)

        XCTAssertEqual(decoded.playerState, "playing")
        XCTAssertEqual(decoded.position, 12.0)
        // Must default to true when omitted
        XCTAssertTrue(decoded.isMusicAppRunning)
    }

    func testTrackInfoFormatting() {
        let track = TrackInfo(
            id: "100",
            numericId: 100,
            name: "Echoes",
            artist: "Pink Floyd",
            album: "Meddle",
            duration: 1414.0,
            hasArtwork: false,
            artworkUrl: "",
            favorited: false,
            isLocal: true
        )

        XCTAssertEqual(track.formattedDuration, "23:34")
    }
}
