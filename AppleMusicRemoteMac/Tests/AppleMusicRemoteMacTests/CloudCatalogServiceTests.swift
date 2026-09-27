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
}
