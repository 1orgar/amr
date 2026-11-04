import XCTest
@testable import AppleMusicRemoteMac

final class CloudCatalogServiceTests: XCTestCase {

    func testCuratedStationsValidity() {
        let service = CloudCatalogService.shared
        let stations = service.getCuratedStations(country: "ru")

        XCTAssertFalse(stations.isEmpty, "Stations list should not be empty")
        XCTAssertGreaterThanOrEqual(stations.count, 6, "Expected at least 6 curated stations")

        for station in stations {
            let name = station.name
            let url = station.url
            let id = station.id

            XCTAssertFalse(name.isEmpty, "Station name should not be empty")
            XCTAssertFalse(id.isEmpty, "Station id should not be empty")
            XCTAssertFalse(url.isEmpty, "Station url should not be empty")

            // Ensure station URL contains valid station scheme or ra identifier
            let hasValidUrl = url.contains("ra.") || url.contains("/station/") || url.contains("music.apple.com")
            XCTAssertTrue(hasValidUrl, "Station \(name) URL \(url) should be a valid Apple Music station URL")

            // Ensure no legacy dead station IDs (ra.146115865x)
            XCTAssertFalse(url.contains("ra.146115865"), "Station \(name) must not use dead legacy ID: \(url)")
        }
    }

    func testArtworkUrlUpgrading() {
        let service = CloudCatalogService.shared

        // 1. Template replacement
        let template = "https://is1-ssl.mzstatic.com/image/thumb/Music/{w}x{h}bb.{f}"
        let upgraded = service.upgradeArtworkUrl(template)
        XCTAssertEqual(upgraded, "https://is1-ssl.mzstatic.com/image/thumb/Music/600x600bb.jpg")

        // 2. Fixed size regex replacement
        let fixed = "https://is1-ssl.mzstatic.com/image/thumb/Music/100x100bb.jpg"
        let upgradedFixed = service.upgradeArtworkUrl(fixed)
        XCTAssertEqual(upgradedFixed, "https://is1-ssl.mzstatic.com/image/thumb/Music/600x600bb.jpg")

        // 3. Empty URL
        XCTAssertEqual(service.upgradeArtworkUrl(""), "")
    }

    func testExploreFeedReturnsNonEmptyStructure() async {
        let service = CloudCatalogService.shared
        let feed = await service.getExploreFeed(country: "ru")

        XCTAssertNotNil(feed["stations"], "Explore feed must have stations")
        if let stations = feed["stations"] as? [[String: Any]] {
            XCTAssertGreaterThanOrEqual(stations.count, 6, "Explore feed should have at least 6 stations")
        }

        XCTAssertNotNil(feed["hero_cards"], "Explore feed must have hero_cards")
        XCTAssertNotNil(feed["top_albums"], "Explore feed must have top_albums")
    }

    func testExploreFeedHeroCardsOrderWithPersonalData() async {
        let service = CloudCatalogService.shared
        service.invalidateExploreFeedCache()

        let origToken = MusicKitManager.shared.getUserToken()
        MusicKitManager.shared.setUserToken("test_user_token")

        let personalStation = StationInfo(id: "ra.u-test", name: "Кирилл's Station", subtitle: "Персональная радиостанция", artwork: "https://art/personal.jpg", url: "https://music.apple.com/station/my-station/ra.u-test", isLive: false, color: "#fa233b", isPersonal: true)
        let discoveryStation = StationInfo(id: "ra.q-test", name: "Станция открытий", subtitle: "Новые треки", artwork: "https://art/discovery.jpg", url: "https://music.apple.com/station/item/ra.q-test", isLive: false, color: "#7928ca", isPersonal: true)
        let favMix = PlaylistInfo(name: "В моём вкусе", trackCount: 25, artworkUrl: "https://art/fav.jpg", isPlaylist: true, id: "pl.pm-fav", url: "https://music.apple.com/playlist/fav/pl.pm-fav")
        let hrMix = PlaylistInfo(name: "Сейчас на повторе", trackCount: 25, artworkUrl: "https://art/hr.jpg", isPlaylist: true, id: "pl.pm-hr", url: "https://music.apple.com/playlist/hr/pl.pm-hr")
        let replayMix = PlaylistInfo(name: "Replay 2026", trackCount: 50, artworkUrl: "https://art/replay.jpg", isPlaylist: true, id: "pl.pm-replay", url: "https://music.apple.com/playlist/replay/pl.pm-replay")

        let artistStation = RecommendationResource(id: "ra.12345", type: "stations", name: "Queen", subtitle: "Queen Radio", artworkUrl: "https://art/queen.jpg", url: "https://music.apple.com/station/ra.12345")
        let stationsGroup = PersonalRecommendationGroup(id: "rec_stations", title: "Stations for You", contents: [artistStation])

        let newAlbum = RecommendationResource(id: "alb_123", type: "albums", name: "New Rock Album", subtitle: "Artist X", artworkUrl: "https://art/alb.jpg", url: "https://music.apple.com/album/alb_123")
        let newReleasesGroup = PersonalRecommendationGroup(id: "rec_new", title: "New Releases for You", contents: [newAlbum])

        let cache = MusicKitManager.PersonalDataCache(
            timestamp: Date(),
            personalStation: personalStation,
            discoveryStation: discoveryStation,
            mixes: [favMix, hrMix, replayMix],
            recommendations: [stationsGroup, newReleasesGroup]
        )
        MusicKitManager.shared.setCachedPersonalData(cache)

        let feed = await service.getExploreFeed(country: "ru")
        guard let heroCards = feed["hero_cards"] as? [[String: Any]] else {
            XCTFail("hero_cards should not be nil")
            return
        }

        XCTAssertGreaterThanOrEqual(heroCards.count, 7, "Expected at least 7 hero cards (Personal, Discovery, Fav, HR, Replay, Event, Artist)")

        // 1. Моя станция
        XCTAssertEqual(heroCards[0]["index"] as? Int, 1)
        XCTAssertEqual(heroCards[0]["title"] as? String, "Моя станция")
        XCTAssertEqual(heroCards[0]["tag"] as? String, "Радиостанция")
        XCTAssertEqual(heroCards[0]["type"] as? String, "station")
        XCTAssertTrue((heroCards[0]["sub"] as? String)?.contains("Apple Music for Кирилл") == true)

        // 2. Станция открытий
        XCTAssertEqual(heroCards[1]["index"] as? Int, 2)
        XCTAssertEqual(heroCards[1]["title"] as? String, "Станция открытий")
        XCTAssertEqual(heroCards[1]["tag"] as? String, "Радиостанция")
        XCTAssertEqual(heroCards[1]["type"] as? String, "station")

        // 3. В моём вкусе
        XCTAssertEqual(heroCards[2]["index"] as? Int, 3)
        XCTAssertEqual(heroCards[2]["name"] as? String, "В моём вкусе")
        XCTAssertEqual(heroCards[2]["type"] as? String, "playlist")

        // 4. Сейчас на повторе
        XCTAssertEqual(heroCards[3]["index"] as? Int, 4)
        XCTAssertEqual(heroCards[3]["name"] as? String, "Сейчас на повторе")
        XCTAssertEqual(heroCards[3]["type"] as? String, "playlist")

        // 5. Сезонная подборка
        XCTAssertEqual(heroCards[4]["index"] as? Int, 5)
        XCTAssertEqual(heroCards[4]["name"] as? String, "Replay 2026")
        XCTAssertEqual(heroCards[4]["type"] as? String, "playlist")

        // 6. Подборка к событиям: Ближайшее событие (Новый год / Halloween в зависимости от месяца)
        XCTAssertEqual(heroCards[5]["index"] as? Int, 6)
        XCTAssertEqual(heroCards[5]["type"] as? String, "playlist")
        XCTAssertEqual(heroCards[5]["tag"] as? String, "Событие")

        // 7. Артист-станция
        XCTAssertEqual(heroCards[6]["index"] as? Int, 7)
        XCTAssertEqual(heroCards[6]["name"] as? String, "Queen")
        XCTAssertEqual(heroCards[6]["type"] as? String, "station")

        // New releases group
        let newReleases = feed["new_releases"] as? [[String: Any]]
        XCTAssertNotNil(newReleases, "Feed should contain new_releases")
        XCTAssertEqual(newReleases?.first?["name"] as? String, "New Rock Album")

        // Cleanup
        service.invalidateExploreFeedCache()
        if let orig = origToken {
            MusicKitManager.shared.setUserToken(orig)
        } else {
            MusicKitManager.shared.setUserToken("")
        }
    }
}
