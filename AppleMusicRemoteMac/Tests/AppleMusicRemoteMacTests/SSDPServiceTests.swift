//
//  SSDPServiceTests.swift
//  AppleMusicRemoteMacTests
//

import XCTest
@testable import AppleMusicRemoteMac

final class SSDPServiceTests: XCTestCase {

    func testDeviceUUIDAndUDNValidity() {
        let service = SSDPService.shared
        XCTAssertFalse(service.deviceUUID.isEmpty)
        XCTAssertTrue(service.deviceUDN.hasPrefix("uuid:"))
        XCTAssertEqual(service.deviceUDN, "uuid:\(service.deviceUUID)")
    }

    func testMatchingTargetsForSSDPAll() {
        let service = SSDPService.shared
        let targets = service.matchingTargets(for: "ssdp:all")

        XCTAssertTrue(targets.contains("upnp:rootdevice"))
        XCTAssertTrue(targets.contains(service.deviceUDN))
        XCTAssertTrue(targets.contains("urn:schemas-upnp-org:device:MediaRenderer:1"))
        XCTAssertTrue(targets.contains("urn:schemas-upnp-org:service:AVTransport:1"))
        XCTAssertTrue(targets.contains("urn:schemas-upnp-org:service:RenderingControl:1"))
        XCTAssertTrue(targets.contains("urn:schemas-upnp-org:service:ConnectionManager:1"))
    }

    func testMatchingTargetsForSpecificService() {
        let service = SSDPService.shared

        let rootTargets = service.matchingTargets(for: "upnp:rootdevice")
        XCTAssertEqual(rootTargets, ["upnp:rootdevice"])

        let avTargets = service.matchingTargets(for: "urn:schemas-upnp-org:service:AVTransport:1")
        XCTAssertEqual(avTargets, ["urn:schemas-upnp-org:service:AVTransport:1"])

        let rcTargets = service.matchingTargets(for: "urn:schemas-upnp-org:service:RenderingControl:1")
        XCTAssertEqual(rcTargets, ["urn:schemas-upnp-org:service:RenderingControl:1"])

        let cmTargets = service.matchingTargets(for: "urn:schemas-upnp-org:service:ConnectionManager:1")
        XCTAssertEqual(cmTargets, ["urn:schemas-upnp-org:service:ConnectionManager:1"])

        let udnTargets = service.matchingTargets(for: service.deviceUDN)
        XCTAssertEqual(udnTargets, [service.deviceUDN])

        let unknownTargets = service.matchingTargets(for: "urn:schemas-upnp-org:service:Unknown:1")
        XCTAssertTrue(unknownTargets.isEmpty)
    }

    func testBuildMSearchResponseFormatting() {
        let service = SSDPService.shared
        let response = service.buildMSearchResponse(target: "upnp:rootdevice", lanIP: "192.168.1.50")

        XCTAssertTrue(response.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(response.contains("CACHE-CONTROL: max-age=1800\r\n"))
        XCTAssertTrue(response.contains("EXT:\r\n"))
        XCTAssertTrue(response.contains("LOCATION: http://192.168.1.50:8090/description.xml\r\n"))
        XCTAssertTrue(response.contains("ST: upnp:rootdevice\r\n"))
        XCTAssertTrue(response.contains("USN: \(service.deviceUDN)::upnp:rootdevice\r\n"))
    }

    func testFriendlyNameDefaultAndCustomization() {
        let service = SSDPService.shared
        let original = service.friendlyName

        service.friendlyName = "Living Room Hi-Fi"
        XCTAssertEqual(service.friendlyName, "Living Room Hi-Fi")

        // Reset
        service.friendlyName = original
    }
}
