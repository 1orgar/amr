//
//  CloudSearchPaginationTests.swift
//  AppleMusicRemoteMacTests
//

import XCTest
@testable import AppleMusicRemoteMac

final class CloudSearchPaginationTests: XCTestCase {

    func testSearchPaginationStructureAndParameters() async {
        let service = CloudCatalogService.shared

        // Query with offset = 0
        let resultPage1 = await service.search(query: "Radiohead", country: "us", limit: 5, offset: 0)

        XCTAssertNotNil(resultPage1["offset"])
        XCTAssertNotNil(resultPage1["limit"])
        XCTAssertNotNil(resultPage1["has_more"])
        XCTAssertNotNil(resultPage1["songs"])
        XCTAssertNotNil(resultPage1["albums"])
        XCTAssertNotNil(resultPage1["artists"])

        if let offsetCodable = resultPage1["offset"] as? AnyCodable, let offset = offsetCodable.value as? Int {
            XCTAssertEqual(offset, 0)
        } else {
            XCTFail("Missing offset in search response")
        }

        if let limitCodable = resultPage1["limit"] as? AnyCodable, let limit = limitCodable.value as? Int {
            XCTAssertEqual(limit, 5)
        } else {
            XCTFail("Missing limit in search response")
        }

        // Query with offset = 5 (page 2)
        let resultPage2 = await service.search(query: "Radiohead", country: "us", limit: 5, offset: 5)

        if let offsetCodable = resultPage2["offset"] as? AnyCodable, let offset = offsetCodable.value as? Int {
            XCTAssertEqual(offset, 5)
        } else {
            XCTFail("Missing offset in second search response")
        }

        if let limitCodable = resultPage2["limit"] as? AnyCodable, let limit = limitCodable.value as? Int {
            XCTAssertEqual(limit, 5)
        } else {
            XCTFail("Missing limit in second search response")
        }

        if let songsCodable = resultPage2["songs"] as? AnyCodable, let songs = songsCodable.value as? [[String: Any]] {
            XCTAssertGreaterThanOrEqual(songs.count, 0)
        }
    }

    func testSearchEmptyQueryReturnsEmptyStructures() async {
        let service = CloudCatalogService.shared
        let emptyResult = await service.search(query: "", country: "ru", limit: 20, offset: 0)

        if let songsCodable = emptyResult["songs"] as? AnyCodable, let songs = songsCodable.value as? [[String: Any]] {
            XCTAssertEqual(songs.count, 0)
        }
        if let albumsCodable = emptyResult["albums"] as? AnyCodable, let albums = albumsCodable.value as? [[String: Any]] {
            XCTAssertEqual(albums.count, 0)
        }
        if let artistsCodable = emptyResult["artists"] as? AnyCodable, let artists = artistsCodable.value as? [[String: Any]] {
            XCTAssertEqual(artists.count, 0)
        }
    }

    func testCuratedStationsBothCountries() {
        MusicKitManager.shared.invalidatePersonalCache()
        let service = CloudCatalogService.shared

        let ruStations = service.getCuratedStations(country: "ru")
        XCTAssertGreaterThanOrEqual(ruStations.count, 6)
        XCTAssertTrue(ruStations.contains(where: { $0.name.contains("Моя станция") || $0.name.contains("Станция открытий") || $0.isPersonal == true }))

        let usStations = service.getCuratedStations(country: "us")
        XCTAssertGreaterThanOrEqual(usStations.count, 6)
        XCTAssertTrue(usStations.contains(where: { $0.name.contains("My Station") || $0.name.contains("Discovery Station") || $0.isPersonal == true }))
    }

    func testParseCatalogSongAndAlbumAudioVariantsMetadata() {
        let manager = MusicKitManager.shared
        let rawSong: [String: Any] = [
            "id": "579149036",
            "attributes": [
                "name": "For Whom the Bell Tolls (Remastered)",
                "artistName": "Metallica",
                "albumName": "Ride the Lightning (Remastered)",
                "durationInMillis": 309000.0,
                "audioVariants": ["hi-res-lossless", "lossless", "lossy-stereo"],
                "isMasteredForItunes": true
            ] as [String: Any]
        ]

        let parsedSong = manager.parseCatalogSong(rawSong)
        XCTAssertNotNil(parsedSong)
        XCTAssertEqual(parsedSong?["is_hi_res"] as? Bool, true)
        XCTAssertEqual(parsedSong?["is_lossless"] as? Bool, true)
        XCTAssertEqual(parsedSong?["is_apple_digital_master"] as? Bool, true)
        XCTAssertEqual(CloudCatalogService.audioQualityTier(for: parsedSong ?? [:]), 3)

        let rawAlbum: [String: Any] = [
            "id": "579148345",
            "attributes": [
                "name": "Ride the Lightning (Remastered)",
                "artistName": "Metallica",
                "releaseDate": "1984-07-27",
                "trackCount": 8,
                "audioVariants": ["hi-res-lossless", "lossless", "lossy-stereo"],
                "isMasteredForItunes": true
            ] as [String: Any]
        ]
        let parsedAlbum = manager.parseCatalogAlbum(rawAlbum)
        XCTAssertNotNil(parsedAlbum)
        XCTAssertEqual(parsedAlbum?["is_hi_res"] as? Bool, true)
        XCTAssertEqual(parsedAlbum?["is_lossless"] as? Bool, true)
        XCTAssertEqual(parsedAlbum?["is_apple_digital_master"] as? Bool, true)
    }

    func testDeduplicateSongsUpgradesCompilationToHiResAndStudioRemaster() {
        let rawSongs: [[String: Any]] = [
            [
                "id": "1066502146",
                "name": "Comfortably Numb",
                "artist": "Pink Floyd",
                "album": "Echoes: The Best of Pink Floyd",
                "audio_variants": ["lossless", "lossy-stereo"],
                "is_hi_res": false,
                "is_lossless": true
            ],
            [
                "id": "1065976170",
                "name": "Comfortably Numb",
                "artist": "Pink Floyd",
                "album": "The Wall",
                "audio_variants": ["hi-res-lossless", "lossless", "lossy-stereo"],
                "is_hi_res": true,
                "is_lossless": true,
                "is_apple_digital_master": true
            ],
            [
                "id": "1632910001",
                "name": "Master of Puppets",
                "artist": "Metallica",
                "album": "Stranger Things: Soundtrack from the Netflix Series (Season 4)",
                "audio_variants": ["lossless", "lossy-stereo"],
                "is_hi_res": false,
                "is_lossless": true
            ],
            [
                "id": "1275600311",
                "name": "Master of Puppets (Remastered)",
                "artist": "Metallica",
                "album": "Master of Puppets (Remastered)",
                "audio_variants": ["lossless", "lossy-stereo"],
                "is_hi_res": false,
                "is_lossless": true,
                "is_apple_digital_master": true
            ]
        ]

        let deduped = CloudCatalogService.deduplicateSongs(rawSongs)
        XCTAssertEqual(deduped.count, 2)
        // Compilation 44.1 kHz Lossless must be upgraded to The Wall Hi-Res Lossless
        XCTAssertEqual(deduped[0]["id"] as? String, "1065976170")
        XCTAssertEqual(deduped[0]["album"] as? String, "The Wall")
        XCTAssertEqual(deduped[0]["is_hi_res"] as? Bool, true)

        // Soundtrack compilation must be upgraded to Master of Puppets (Remastered) Apple Digital Master
        XCTAssertEqual(deduped[1]["id"] as? String, "1275600311")
        XCTAssertEqual(deduped[1]["album"] as? String, "Master of Puppets (Remastered)")
    }

    func testPrioritizeSearchSongsRanksHiResFirstWhilePreservingExactSongQueryAtTop() {
        let metallicaCatalogSongs: [[String: Any]] = [
            [
                "id": "579372950",
                "name": "Enter Sandman",
                "artist": "Metallica",
                "album": "Metallica",
                "audio_variants": ["lossless", "lossy-stereo"],
                "is_hi_res": false,
                "is_lossless": true
            ],
            [
                "id": "579373079",
                "name": "Nothing Else Matters",
                "artist": "Metallica",
                "album": "Metallica",
                "audio_variants": ["lossless", "lossy-stereo"],
                "is_hi_res": false,
                "is_lossless": true
            ],
            [
                "id": "579149036",
                "name": "For Whom the Bell Tolls (Remastered)",
                "artist": "Metallica",
                "album": "Ride the Lightning (Remastered)",
                "audio_variants": ["hi-res-lossless", "lossless", "lossy-stereo"],
                "is_hi_res": true,
                "is_lossless": true
            ],
            [
                "id": "579149037",
                "name": "Fade to Black (Remastered)",
                "artist": "Metallica",
                "album": "Ride the Lightning (Remastered)",
                "audio_variants": ["hi-res-lossless", "lossless", "lossy-stereo"],
                "is_hi_res": true,
                "is_lossless": true
            ],
            [
                "id": "999999999",
                "name": "For Whom the Bell Tolls (1983 Rough Mix Demo)",
                "artist": "Metallica",
                "album": "Ride the Lightning (Deluxe Box)",
                "audio_variants": ["hi-res-lossless", "lossless"],
                "is_hi_res": true,
                "is_lossless": true
            ]
        ]

        // 1. Artist search "metallica": Hi-Res studio tracks come first in Apple Music relevance order,
        //    followed by standard Lossless hits, with Rough Mix Demo demoted to the bottom.
        let artistRanked = CloudCatalogService.prioritizeSearchSongs(metallicaCatalogSongs, query: "metallica")
        XCTAssertEqual(artistRanked.map { $0["id"] as? String }, [
            "579149036", // For Whom the Bell Tolls (Hi-Res 96 kHz)
            "579149037", // Fade to Black (Hi-Res 96 kHz)
            "579372950", // Enter Sandman (Lossless 44.1 kHz)
            "579373079", // Nothing Else Matters (Lossless 44.1 kHz)
            "999999999"  // Rough Mix Demo
        ])

        // 2. Explicit song search "metallica enter sandman": exact song match stays #1, followed by Hi-Res tracks!
        let songRanked = CloudCatalogService.prioritizeSearchSongs(metallicaCatalogSongs, query: "metallica enter sandman")
        XCTAssertEqual(songRanked.first?["id"] as? String, "579372950")
        XCTAssertEqual(songRanked[1]["id"] as? String, "579149036")
        XCTAssertEqual(songRanked[2]["id"] as? String, "579149037")
    }
}
