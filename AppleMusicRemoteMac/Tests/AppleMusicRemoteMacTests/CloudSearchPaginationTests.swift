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
        let service = CloudCatalogService.shared

        let ruStations = service.getCuratedStations(country: "ru")
        XCTAssertGreaterThanOrEqual(ruStations.count, 6)
        XCTAssertTrue(ruStations.contains(where: { $0.name.contains("Моя станция") || $0.name.contains("Станция открытий") }))

        let usStations = service.getCuratedStations(country: "us")
        XCTAssertGreaterThanOrEqual(usStations.count, 6)
        XCTAssertTrue(usStations.contains(where: { $0.name.contains("My Station") || $0.name.contains("Discovery Station") }))
    }
}
