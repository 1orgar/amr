//
//  ModelsAndSerializationTests.swift
//  AppleMusicRemoteMacTests
//

import XCTest
@testable import AppleMusicRemoteMac

final class ModelsAndSerializationTests: XCTestCase {

    // MARK: - TrackInfo Tests

    func testTrackInfoFormattingAndDefaults() {
        var track = TrackInfo()
        XCTAssertEqual(track.formattedDuration, "0:00")
        XCTAssertTrue(track.artworkUrl.isEmpty)
        XCTAssertFalse(track.hasArtwork)
        XCTAssertFalse(track.favorited)
        XCTAssertEqual(track.isLocal, true)

        track.duration = 45
        XCTAssertEqual(track.formattedDuration, "0:45")

        track.duration = 60
        XCTAssertEqual(track.formattedDuration, "1:00")

        track.duration = 135
        XCTAssertEqual(track.formattedDuration, "2:15")

        track.duration = 3661
        XCTAssertEqual(track.formattedDuration, "61:01")
    }

    func testTrackInfoCodableRoundTrip() throws {
        let original = TrackInfo(
            id: "track-101",
            numericId: 101,
            name: "Heroes",
            artist: "David Bowie",
            album: "Heroes",
            duration: 360.0,
            hasArtwork: true,
            artworkUrl: "https://example.com/art.jpg",
            artworkDataBase64: "base64data",
            favorited: true,
            isLocal: false,
            playedCount: 42,
            playedDate: 1700000000.0,
            dateAdded: 1690000000.0,
            url: "https://music.apple.com/track/101",
            previewUrl: "https://audio-ssl.itunes.apple.com/preview.m4a",
            index: 3,
            isCurrent: true
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TrackInfo.self, from: data)

        XCTAssertEqual(decoded.id, "track-101")
        XCTAssertEqual(decoded.numericId, 101)
        XCTAssertEqual(decoded.name, "Heroes")
        XCTAssertEqual(decoded.artist, "David Bowie")
        XCTAssertEqual(decoded.album, "Heroes")
        XCTAssertEqual(decoded.duration, 360.0)
        XCTAssertEqual(decoded.hasArtwork, true)
        XCTAssertEqual(decoded.artworkUrl, "https://example.com/art.jpg")
        XCTAssertEqual(decoded.artworkDataBase64, "base64data")
        XCTAssertEqual(decoded.favorited, true)
        XCTAssertEqual(decoded.isLocal, false)
        XCTAssertEqual(decoded.playedCount, 42)
        XCTAssertEqual(decoded.playedDate, 1700000000.0)
        XCTAssertEqual(decoded.dateAdded, 1690000000.0)
        XCTAssertEqual(decoded.url, "https://music.apple.com/track/101")
        XCTAssertEqual(decoded.previewUrl, "https://audio-ssl.itunes.apple.com/preview.m4a")
        XCTAssertEqual(decoded.index, 3)
        XCTAssertEqual(decoded.isCurrent, true)
    }

    // MARK: - PlaylistInfo Tests

    func testPlaylistInfoCodableRoundTrip() throws {
        let original = PlaylistInfo(
            name: "Rock Classics",
            trackCount: 150,
            artworkUrl: "https://example.com/rock.jpg",
            isPlaylist: true
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PlaylistInfo.self, from: data)

        XCTAssertEqual(decoded.name, "Rock Classics")
        XCTAssertEqual(decoded.trackCount, 150)
        XCTAssertEqual(decoded.artworkUrl, "https://example.com/rock.jpg")
        XCTAssertTrue(decoded.isPlaylist)
    }

    // MARK: - ArtistInfo Tests

    func testArtistInfoCodableRoundTrip() throws {
        let original = ArtistInfo(
            name: "Pink Floyd",
            id: "1234",
            genre: "Progressive Rock",
            url: "https://music.apple.com/artist/pink-floyd/1234"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ArtistInfo.self, from: data)

        XCTAssertEqual(decoded.name, "Pink Floyd")
        XCTAssertEqual(decoded.id, "1234")
        XCTAssertEqual(decoded.genre, "Progressive Rock")
        XCTAssertEqual(decoded.url, "https://music.apple.com/artist/pink-floyd/1234")
    }

    // MARK: - AlbumInfo Tests

    func testAlbumInfoCodableRoundTrip() throws {
        let tracks = [
            TrackInfo(id: "1", name: "Speak to Me", artist: "Pink Floyd", album: "The Dark Side of the Moon", duration: 65),
            TrackInfo(id: "2", name: "Breathe", artist: "Pink Floyd", album: "The Dark Side of the Moon", duration: 169)
        ]
        let original = AlbumInfo(
            id: "album-99",
            name: "The Dark Side of the Moon",
            artist: "Pink Floyd",
            artwork: "https://example.com/dsotm.jpg",
            releaseDate: "1973-03-01",
            trackCount: 10,
            genre: "Rock",
            url: "https://music.apple.com/album/99",
            tracks: tracks
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AlbumInfo.self, from: data)

        XCTAssertEqual(decoded.id, "album-99")
        XCTAssertEqual(decoded.name, "The Dark Side of the Moon")
        XCTAssertEqual(decoded.tracks?.count, 2)
        XCTAssertEqual(decoded.tracks?[0].name, "Speak to Me")
    }

    // MARK: - StationInfo Tests

    func testStationInfoCodableRoundTrip() throws {
        let original = StationInfo(
            id: "station-1",
            name: "Discovery Station",
            subtitle: "Personalized music",
            artwork: "/assets/stations/discovery.png",
            url: "music://music.apple.com/station/discovery",
            isLive: false,
            color: "#1e88e5"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StationInfo.self, from: data)

        XCTAssertEqual(decoded.id, "station-1")
        XCTAssertEqual(decoded.name, "Discovery Station")
        XCTAssertEqual(decoded.subtitle, "Personalized music")
        XCTAssertFalse(decoded.isLive)
        XCTAssertEqual(decoded.color, "#1e88e5")
    }

    // MARK: - PlaybackQueueInfo Tests

    func testPlaybackQueueInfoCodableRoundTrip() throws {
        let track1 = TrackInfo(id: "t1", name: "Song A", artist: "Artist A")
        let track2 = TrackInfo(id: "t2", name: "Song B", artist: "Artist B")
        let hist = TrackInfo(id: "th", name: "Old Song", artist: "Past Artist")

        let original = PlaybackQueueInfo(
            playlist: "Favorites Queue",
            currentIndex: 1,
            totalTracks: 2,
            shuffle: true,
            upcomingTracks: [track2],
            tracks: [track1, track2],
            historyTracks: [hist]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PlaybackQueueInfo.self, from: data)

        XCTAssertEqual(decoded.playlist, "Favorites Queue")
        XCTAssertEqual(decoded.currentIndex, 1)
        XCTAssertEqual(decoded.totalTracks, 2)
        XCTAssertTrue(decoded.shuffle)
        XCTAssertEqual(decoded.upcomingTracks.count, 1)
        XCTAssertEqual(decoded.tracks.count, 2)
        XCTAssertEqual(decoded.historyTracks.count, 1)
    }

    // MARK: - AnyCodable Tests

    func testAnyCodableAllTypesAndValueProperty() throws {
        // String
        let strVal = AnyCodable("test string")
        XCTAssertEqual(strVal.value as? String, "test string")

        // Int
        let intVal = AnyCodable(12345)
        XCTAssertEqual(intVal.value as? Int, 12345)

        // Double
        let doubleVal = AnyCodable(96000.5)
        XCTAssertEqual(doubleVal.value as? Double, 96000.5)

        // Bool
        let boolVal = AnyCodable(true)
        XCTAssertEqual(boolVal.value as? Bool, true)

        // Null
        let nullVal = AnyCodable(nil)
        XCTAssertNil(nullVal.value)

        // Array
        let arrVal = AnyCodable(["a", 1, false])
        if let arr = arrVal.value as? [Any] {
            XCTAssertEqual(arr.count, 3)
            XCTAssertEqual(arr[0] as? String, "a")
            XCTAssertEqual(arr[1] as? Int, 1)
            XCTAssertEqual(arr[2] as? Bool, false)
        } else {
            XCTFail("Array conversion failed")
        }

        // Dictionary
        let dictVal = AnyCodable(["key1": "val1", "key2": 42])
        if let dict = dictVal.value as? [String: Any] {
            XCTAssertEqual(dict["key1"] as? String, "val1")
            XCTAssertEqual(dict["key2"] as? Int, 42)
        } else {
            XCTFail("Dict conversion failed")
        }

        // Round-trip encoding & decoding of complex dictionary
        let complexDict: [String: AnyCodable] = [
            "title": strVal,
            "count": intVal,
            "rate": doubleVal,
            "active": boolVal,
            "empty": nullVal,
            "list": arrVal,
            "nested": dictVal
        ]
        let data = try JSONEncoder().encode(complexDict)
        let decodedDict = try JSONDecoder().decode([String: AnyCodable].self, from: data)

        XCTAssertEqual(decodedDict["title"]?.value as? String, "test string")
        XCTAssertEqual(decodedDict["count"]?.value as? Int, 12345)
        XCTAssertEqual(decodedDict["active"]?.value as? Bool, true)
        XCTAssertNil(decodedDict["empty"]?.value)
    }

    // MARK: - Response DTOs

    func testResponseDTOsRoundTrip() throws {
        // PlaylistTracksResponse
        let ptr = PlaylistTracksResponse(playlist: "Chill", tracks: [TrackInfo(id: "1", name: "Song 1")])
        let ptrData = try JSONEncoder().encode(ptr)
        let decodedPtr = try JSONDecoder().decode(PlaylistTracksResponse.self, from: ptrData)
        XCTAssertEqual(decodedPtr.playlist, "Chill")
        XCTAssertEqual(decodedPtr.tracks.count, 1)

        // PlaylistsResponse
        let plr = PlaylistsResponse(playlists: [PlaylistInfo(name: "P1", trackCount: 5)])
        let plrData = try JSONEncoder().encode(plr)
        let decodedPlr = try JSONDecoder().decode(PlaylistsResponse.self, from: plrData)
        XCTAssertEqual(decodedPlr.playlists.count, 1)

        // ArtistsResponse
        let ar = ArtistsResponse(artists: [ArtistInfo(name: "A1")])
        let arData = try JSONEncoder().encode(ar)
        let decodedAr = try JSONDecoder().decode(ArtistsResponse.self, from: arData)
        XCTAssertEqual(decodedAr.artists.count, 1)

        // AlbumsResponse
        let albr = AlbumsResponse(albums: [AlbumInfo(id: "1", name: "Alb1", artist: "Art1", artwork: "art")])
        let albrData = try JSONEncoder().encode(albr)
        let decodedAlbr = try JSONDecoder().decode(AlbumsResponse.self, from: albrData)
        XCTAssertEqual(decodedAlbr.albums.count, 1)

        // SongsResponse
        let sr = SongsResponse(songs: [TrackInfo(id: "s1", name: "Song")])
        let srData = try JSONEncoder().encode(sr)
        let decodedSr = try JSONDecoder().decode(SongsResponse.self, from: srData)
        XCTAssertEqual(decodedSr.songs.count, 1)

        // StationsResponse
        let str = StationsResponse(stations: [StationInfo(id: "s1", name: "S1", subtitle: "Sub", artwork: "art", url: "url", isLive: false, color: "#000")])
        let strData = try JSONEncoder().encode(str)
        let decodedStr = try JSONDecoder().decode(StationsResponse.self, from: strData)
        XCTAssertEqual(decodedStr.stations.count, 1)

        // SearchResponse
        let search = SearchResponse(
            songs: [TrackInfo(id: "s1", name: "Found Song")],
            albums: [AlbumInfo(id: "a1", name: "Found Album", artist: "Art", artwork: "art")],
            artists: [ArtistInfo(name: "Found Artist")]
        )
        let sData = try JSONEncoder().encode(search)
        let decodedSearch = try JSONDecoder().decode(SearchResponse.self, from: sData)
        XCTAssertEqual(decodedSearch.songs.count, 1)
        XCTAssertEqual(decodedSearch.albums.count, 1)
        XCTAssertEqual(decodedSearch.artists.count, 1)
    }

    // MARK: - PlayerStatus & Volume Lock Tests

    func testPlayerStatusVolumeLockCodableRoundTrip() throws {
        var status = PlayerStatus()
        status.playerState = "playing"
        status.position = 45.0
        status.duration = 180.0
        status.volume = 85
        status.isVolumeLockedTo100 = false

        let data = try JSONEncoder().encode(status)
        let jsonStr = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(jsonStr.contains("\"lock_volume_100\":false"))
        XCTAssertTrue(jsonStr.contains("\"volume\":85"))

        let decoded = try JSONDecoder().decode(PlayerStatus.self, from: data)
        XCTAssertEqual(decoded.playerState, "playing")
        XCTAssertEqual(decoded.volume, 85)
        XCTAssertFalse(decoded.isVolumeLockedTo100)
    }

    func testPlayerStatusDefaultLockVolume100WhenMissingInJSON() throws {
        // When decoding legacy JSON payload without lock_volume_100 key, default must be true
        let legacyJSON = """
        {
            "player_state": "playing",
            "position": 10.0,
            "duration": 200.0,
            "volume": 100,
            "shuffle": false,
            "repeat": "off",
            "is_ducked": false,
            "is_music_app_running": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PlayerStatus.self, from: legacyJSON)
        XCTAssertTrue(decoded.isVolumeLockedTo100, "isVolumeLockedTo100 should default to true for bit-perfect output")
    }

    func testPlaybackStateStoreVolumeLockPersistence() {
        let store = PlaybackStateStore.shared
        let original = store.isVolumeLockedTo100

        defer {
            store.isVolumeLockedTo100 = original
        }

        store.isVolumeLockedTo100 = false
        XCTAssertFalse(store.isVolumeLockedTo100)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "LockVolume100"))

        store.isVolumeLockedTo100 = true
        XCTAssertTrue(store.isVolumeLockedTo100)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "LockVolume100"))
    }

    func testVolumeClampingLimits() {
        let testCases: [(input: Int, expected: Int)] = [
            (-50, 0),
            (-1, 0),
            (0, 0),
            (50, 50),
            (100, 100),
            (101, 100),
            (999, 100)
        ]

        for tc in testCases {
            let clamped = max(0, min(100, tc.input))
            XCTAssertEqual(clamped, tc.expected, "Volume \(tc.input) should clamp to \(tc.expected)")
        }
    }

    func testCheckAndEnforceVolumeLockWhenLockedSetsSimulatedVolumeTo100() {
        let store = PlaybackStateStore.shared
        let origLocked = store.isVolumeLockedTo100
        let origVol = store.simulatedVolume
        defer {
            store.isVolumeLockedTo100 = origLocked
            store.simulatedVolume = origVol
        }

        store.isVolumeLockedTo100 = true
        store.simulatedVolume = 30

        let enforced = PlaybackTransportController.shared.checkAndEnforceVolumeLock()
        XCTAssertTrue(enforced)
        XCTAssertEqual(store.simulatedVolume, 100)
    }

    func testCheckAndEnforceVolumeLockWhenUnlockedDoesNotEnforce() {
        let store = PlaybackStateStore.shared
        let origLocked = store.isVolumeLockedTo100
        let origVol = store.simulatedVolume
        defer {
            store.isVolumeLockedTo100 = origLocked
            store.simulatedVolume = origVol
        }

        store.isVolumeLockedTo100 = false
        store.simulatedVolume = 45

        let enforced = PlaybackTransportController.shared.checkAndEnforceVolumeLock()
        XCTAssertFalse(enforced)
        XCTAssertEqual(store.simulatedVolume, 45)
    }

    func testSetVolumeRespectsVolumeLockState() {
        let store = PlaybackStateStore.shared
        let origLocked = store.isVolumeLockedTo100
        let origVol = store.simulatedVolume
        defer {
            store.isVolumeLockedTo100 = origLocked
            store.simulatedVolume = origVol
        }

        // When locked, attempting to set volume to 50 should be rejected
        store.isVolumeLockedTo100 = true
        let rejected = PlaybackTransportController.shared.setVolume(50)
        XCTAssertFalse(rejected)

        // Setting volume to 100 should be accepted
        let accepted100 = PlaybackTransportController.shared.setVolume(100)
        XCTAssertTrue(accepted100)

        // When unlocked, setting volume to 50 should be accepted
        store.isVolumeLockedTo100 = false
        let accepted50 = PlaybackTransportController.shared.setVolume(50)
        XCTAssertTrue(accepted50)
    }
}

