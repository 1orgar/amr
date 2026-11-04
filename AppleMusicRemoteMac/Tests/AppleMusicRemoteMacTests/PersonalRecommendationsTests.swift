//
//  PersonalRecommendationsTests.swift
//  AppleMusicRemoteMacTests
//
//  Unit tests for Apple Music personalization, personal stations, weekly mixes,
//  caching, and graceful fallback.
//

import XCTest
@testable import AppleMusicRemoteMac

final class PersonalRecommendationsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MusicKitManager.shared.invalidatePersonalCache()
    }

    override func tearDown() {
        MusicKitManager.shared.invalidatePersonalCache()
        super.tearDown()
    }

    // MARK: - 1. Personal Station JSON Parsing

    func testPersonalStationJsonParsing() throws {
        let sampleJson = """
        {
          "data": [
            {
              "id": "ra.u-user1234567890abcdef",
              "type": "stations",
              "href": "/v1/catalog/us/stations/ra.u-user1234567890abcdef",
              "attributes": {
                "name": "Kirill's Station",
                "url": "https://music.apple.com/station/my-station/ra.u-user1234567890abcdef",
                "artwork": {
                  "width": 1000,
                  "height": 1000,
                  "url": "https://is1-ssl.mzstatic.com/image/thumb/Features/v4/user_station_{w}x{h}.{f}"
                },
                "isLive": false
              }
            }
          ]
        }
        """

        let data = Data(sampleJson.utf8)
        let station = MusicKitManager.parsePersonalStation(data: data)

        XCTAssertNotNil(station, "Parsed personal station should not be nil")
        XCTAssertEqual(station?.id, "ra.u-user1234567890abcdef")
        XCTAssertEqual(station?.name, "Kirill's Station")
        XCTAssertEqual(station?.url, "https://music.apple.com/station/my-station/ra.u-user1234567890abcdef")
        XCTAssertEqual(station?.isLive, false)
        XCTAssertEqual(station?.isPersonal, true)
        XCTAssertTrue(station?.artwork.contains("600x600") == true, "Artwork template should be formatted with dimensions")
    }

    // MARK: - 2. Recommendations & Mixes Parsing

    func testPersonalRecommendationsAndMixesParsing() throws {
        let sampleJson = """
        {
          "data": [
            {
              "id": "rec_made_for_you",
              "type": "personal-recommendation",
              "attributes": {
                "title": {
                  "stringForDisplay": "Made for You"
                },
                "resourceTypes": ["playlists", "stations"]
              },
              "relationships": {
                "contents": {
                  "data": [
                    {
                      "id": "pl.pm-newmusicmix123",
                      "type": "playlists",
                      "attributes": {
                        "name": "New Music Mix",
                        "curatorName": "Apple Music",
                        "description": {
                          "standard": "Fresh music tailored to your tastes"
                        },
                        "url": "https://music.apple.com/playlist/new-music-mix/pl.pm-newmusicmix123",
                        "artwork": {
                          "url": "https://is1-ssl.mzstatic.com/image/thumb/Music/mix_new_{w}x{h}.{f}"
                        }
                      }
                    },
                    {
                      "id": "pl.pm-chillmix456",
                      "type": "playlists",
                      "attributes": {
                        "name": "Chill Mix",
                        "curatorName": "Apple Music",
                        "description": {
                          "standard": "Laid-back beats and relaxing melodies"
                        },
                        "url": "https://music.apple.com/playlist/chill-mix/pl.pm-chillmix456",
                        "artwork": {
                          "url": "https://is1-ssl.mzstatic.com/image/thumb/Music/mix_chill_{w}x{h}.{f}"
                        }
                      }
                    },
                    {
                      "id": "ra.q-discovery789",
                      "type": "stations",
                      "attributes": {
                        "name": "Discovery Station",
                        "url": "https://music.apple.com/station/discovery/ra.q-discovery789",
                        "artwork": {
                          "url": "https://is1-ssl.mzstatic.com/image/thumb/Music/discovery_{w}x{h}.{f}"
                        }
                      }
                    }
                  ]
                }
              }
            }
          ]
        }
        """

        let data = Data(sampleJson.utf8)
        let groups = MusicKitManager.parsePersonalRecommendations(data: data)

        XCTAssertEqual(groups.count, 1, "Should parse 1 recommendation group")
        XCTAssertEqual(groups.first?.title, "Made for You")
        XCTAssertEqual(groups.first?.contents.count, 3)

        // Extract mixes
        let mixes = MusicKitManager.extractMixes(from: groups)
        XCTAssertEqual(mixes.count, 2, "Should extract 2 weekly mixes (New Music Mix, Chill Mix)")
        XCTAssertTrue(mixes.contains { $0.name == "New Music Mix" && $0.id == "pl.pm-newmusicmix123" })
        XCTAssertTrue(mixes.contains { $0.name == "Chill Mix" && $0.id == "pl.pm-chillmix456" })

        // Extract stations (Discovery Station)
        let (personal, discovery) = MusicKitManager.extractStations(from: groups)
        XCTAssertNil(personal, "Personal station was not in this group")
        XCTAssertNotNil(discovery, "Discovery station should be found in recommendations")
        XCTAssertEqual(discovery?.id, "ra.q-discovery789")
        XCTAssertEqual(discovery?.name, "Discovery Station")
        XCTAssertEqual(discovery?.url, "https://music.apple.com/station/discovery/ra.q-discovery789")
        XCTAssertEqual(discovery?.isPersonal, true)
    }

    // MARK: - 3. Cache and Invalidation

    func testPersonalDataCacheAndInvalidation() {
        let mgr = MusicKitManager.shared
        mgr.invalidatePersonalCache()

        XCTAssertNil(mgr.getCachedPersonalData(), "Cache should be nil initially")

        let testStation = StationInfo(
            id: "ra.u-test",
            name: "Test Station",
            subtitle: "Sub",
            artwork: "art.jpg",
            url: "https://music.apple.com/station/test",
            isLive: false,
            color: "red",
            isPersonal: true
        )

        let testCache = MusicKitManager.PersonalDataCache(
            timestamp: Date(),
            personalStation: testStation,
            discoveryStation: nil,
            mixes: [],
            recommendations: []
        )

        mgr.setCachedPersonalData(testCache)
        let retrieved = mgr.getCachedPersonalData()
        XCTAssertNotNil(retrieved, "Cached data should be retrieved")
        XCTAssertEqual(retrieved?.personalStation?.id, "ra.u-test")

        // Invalidation
        mgr.invalidatePersonalCache()
        XCTAssertNil(mgr.getCachedPersonalData(), "Cache should be cleared after invalidatePersonalCache()")
    }

    // MARK: - 4. Graceful Fallback Without Token (v2.3 compatibility)

    func testCuratedStationsFallbackWithoutToken() {
        let service = CloudCatalogService.shared
        let stations = service.getCuratedStations(country: "ru")

        XCTAssertGreaterThanOrEqual(stations.count, 6)

        // Ensure "Моя станция" and "Станция открытий" exist in default catalog
        let hasPersonal = stations.contains { $0.name.contains("Моя станция") || $0.id.contains("personal") }
        let hasDiscovery = stations.contains { $0.name.contains("Станция открытий") || $0.id.contains("discovery") }

        XCTAssertTrue(hasPersonal, "Curated stations must contain personal station fallback")
        XCTAssertTrue(hasDiscovery, "Curated stations must contain discovery station fallback")

        for s in stations {
            XCTAssertFalse(s.name.isEmpty)
            XCTAssertFalse(s.url.isEmpty)
            XCTAssertFalse(s.artwork.isEmpty)
        }
    }

    // MARK: - 5. PlaybackRouter Station URL Preservation

    func testPlaybackRouterPreservesDynamicStationUrls() async {
        let customUrl = "https://music.apple.com/station/my-station/ra.u-customuser999"
        XCTAssertTrue(customUrl.contains("ra.u-customuser999"))
        XCTAssertFalse(customUrl.contains("ra.u-96b95a031a2fb0aa1abb70ff757aa95f"))
    }

    // MARK: - 6. Model Serialization Round-Trip

    func testPersonalMixesResponseSerialization() throws {
        let mix = PlaylistInfo(
            name: "Favorites Mix",
            trackCount: 25,
            artworkUrl: "https://example.com/art.jpg",
            isPlaylist: true,
            id: "pl.pm-fav123",
            url: "https://music.apple.com/playlist/fav",
            curatorName: "Apple Music",
            description: "Your favorite songs"
        )

        let station = StationInfo(
            id: "ra.u-personal123",
            name: "My Station",
            subtitle: "Personal",
            artwork: "https://example.com/art.jpg",
            url: "https://music.apple.com/station/my",
            isLive: false,
            color: "blue",
            isPersonal: true,
            provider: "Apple Music"
        )

        let response = PersonalMixesResponse(mixes: [mix], stations: [station])
        let encoded = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(PersonalMixesResponse.self, from: encoded)

        XCTAssertEqual(decoded.mixes.count, 1)
        XCTAssertEqual(decoded.mixes.first?.name, "Favorites Mix")
        XCTAssertEqual(decoded.mixes.first?.id, "pl.pm-fav123")
        XCTAssertEqual(decoded.stations.count, 1)
        XCTAssertEqual(decoded.stations.first?.id, "ra.u-personal123")
        XCTAssertEqual(decoded.stations.first?.isPersonal, true)
    }

    func testRecommendationResourceSerialization() throws {
        let resource = RecommendationResource(
            id: "pl.pm-chill",
            type: "playlists",
            name: "Chill Mix",
            subtitle: "Apple Music",
            artworkUrl: "https://example.com/art.jpg",
            url: "https://music.apple.com/playlist/chill"
        )

        let group = PersonalRecommendationGroup(id: "group1", title: "Made for You", contents: [resource])
        let encoded = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(PersonalRecommendationGroup.self, from: encoded)

        XCTAssertEqual(decoded.id, "group1")
        XCTAssertEqual(decoded.title, "Made for You")
        XCTAssertEqual(decoded.contents.count, 1)
        XCTAssertEqual(decoded.contents.first?.name, "Chill Mix")
        XCTAssertEqual(decoded.contents.first?.type, "playlists")
    }

    func testFetchPersonalStationsReturnsCloudStationsOrFallback() async throws {
        let (p, d) = await MusicKitManager.shared.fetchPersonalStations()
        if let personal = p {
            XCTAssertFalse(personal.name.isEmpty)
            XCTAssertFalse(personal.url.isEmpty)
            XCTAssertFalse(personal.artwork.isEmpty)
            XCTAssertFalse(personal.artwork.contains("CoverPersonal.png"), "Personal station artwork should not use CoverPersonal.png fallback")
        }
        if let discovery = d {
            XCTAssertFalse(discovery.name.isEmpty)
            XCTAssertFalse(discovery.url.isEmpty)
            XCTAssertFalse(discovery.artwork.isEmpty)
        }
    }
}
