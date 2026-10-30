//
//  DLNADiscoveryTests.swift
//  AppleMusicRemoteMacTests
//
//  Tests for DLNA MediaRenderer discovery, anti-self-discovery filtering,
//  and Mock DLNA Renderer Server functionality.
//

import XCTest
@testable import AppleMusicRemoteMac

final class DLNADiscoveryTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Save current user default
        UserDefaults.standard.removeObject(forKey: DLNADiscoveryManager.defaultsKey)
    }

    override func tearDown() {
        DLNADiscoveryManager.shared.stop()
        super.tearDown()
    }

    // MARK: - Anti-Self-Discovery Filter Tests

    func testAntiSelfDiscoveryFilterByUDN() {
        let manager = DLNADiscoveryManager.shared
        let selfUDN = SSDPService.shared.deviceUDN
        let selfUUID = SSDPService.shared.deviceUUID

        XCTAssertTrue(manager.isSelfDevice(udn: selfUDN, location: nil, friendlyName: "Some Name"),
                      "Must filter device matching exact self UDN")
        XCTAssertTrue(manager.isSelfDevice(udn: "uuid:\(selfUUID)::urn:schemas-upnp-org:device:MediaRenderer:1", location: nil, friendlyName: ""),
                      "Must filter device containing self UUID in USN/UDN")
    }

    func testAntiSelfDiscoveryFilterByLocationPort8090() {
        let manager = DLNADiscoveryManager.shared
        let localURL1 = URL(string: "http://127.0.0.1:8090/description.xml")!
        let localURL2 = URL(string: "http://localhost:8090/description.xml")!

        XCTAssertTrue(manager.isSelfDevice(udn: "uuid:random-other-device", location: localURL1, friendlyName: "Random"),
                      "Must filter device located at localhost:8090 (AMR's own UPnP server)")
        XCTAssertTrue(manager.isSelfDevice(udn: "uuid:random-other-device", location: localURL2, friendlyName: "Random"),
                      "Must filter device located at localhost:8090")
    }

    func testAntiSelfDiscoveryFilterByFriendlyName() {
        let manager = DLNADiscoveryManager.shared
        let selfName = SSDPService.shared.friendlyName

        XCTAssertTrue(manager.isSelfDevice(udn: "uuid:random", location: nil, friendlyName: selfName),
                      "Must filter device with identical friendly name")
    }

    func testAntiSelfDiscoveryAllowsExternalDevice() {
        let manager = DLNADiscoveryManager.shared
        let extURL = URL(string: "http://192.168.1.155:11000/description.xml")!

        XCTAssertFalse(manager.isSelfDevice(udn: "uuid:bluesound-node-nano-12345", location: extURL, friendlyName: "Bluesound NODE NANO"),
                       "External Bluesound streamer must NOT be filtered")
    }

    // MARK: - XML Parsing & Registration Tests

    func testParseAndRegisterBluesoundNanoXML() {
        let manager = DLNADiscoveryManager.shared
        let location = URL(string: "http://192.168.1.55:8095/mock/description.xml")!

        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <root xmlns="urn:schemas-upnp-org:device-1-0">
          <device>
            <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
            <friendlyName>Living Room NODE NANO</friendlyName>
            <manufacturer>Bluesound</manufacturer>
            <modelName>NODE NANO</modelName>
            <UDN>uuid:node-nano-real-001</UDN>
            <serviceList>
              <service>
                <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
                <controlURL>/AVTransport/control</controlURL>
              </service>
              <service>
                <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
                <controlURL>/RenderingControl/control</controlURL>
              </service>
            </serviceList>
          </device>
        </root>
        """

        manager.parseAndRegisterDevice(xml: xml, locationURL: location)

        let renderers = manager.getDiscoveredRenderers()
        guard let device = renderers.first(where: { $0.id == "uuid:node-nano-real-001" }) else {
            XCTFail("Failed to register Bluesound device from XML")
            return
        }

        XCTAssertEqual(device.friendlyName, "Living Room NODE NANO")
        XCTAssertEqual(device.manufacturer, "Bluesound")
        XCTAssertEqual(device.modelName, "NODE NANO")
        XCTAssertEqual(device.avTransportControlURL?.absoluteString, "http://192.168.1.55:8095/AVTransport/control")

        let dict = device.dictionary
        XCTAssertEqual(dict["type"] as? String, "dlna")
        XCTAssertEqual(dict["icon"] as? String, "network")
        XCTAssertEqual(dict["manufacturer"] as? String, "Bluesound")
        XCTAssertEqual(dict["model"] as? String, "NODE NANO")
        XCTAssertEqual(dict["currentSampleRate"] as? Double, 192000.0)
    }

    func testSelfAMRInstanceIgnoredDuringParse() {
        let manager = DLNADiscoveryManager.shared
        let selfLocation = URL(string: "http://127.0.0.1:8090/description.xml")!
        let selfXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <root xmlns="urn:schemas-upnp-org:device-1-0">
          <device>
            <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
            <friendlyName>\(SSDPService.shared.friendlyName)</friendlyName>
            <manufacturer>Apple Music Remote</manufacturer>
            <modelName>AMR-UPnP</modelName>
            <UDN>\(SSDPService.shared.deviceUDN)</UDN>
          </device>
        </root>
        """

        let countBefore = manager.getDiscoveredCount()
        manager.parseAndRegisterDevice(xml: selfXML, locationURL: selfLocation)
        let countAfter = manager.getDiscoveredCount()

        XCTAssertEqual(countBefore, countAfter, "AMR's own instance must be rejected during parse")
    }

    // MARK: - Integration with Audio Devices List

    func testDLNADevicesIncludedInAudioDevicesListWhenEnabled() {
        let manager = DLNADiscoveryManager.shared

        // When disabled
        manager.setEnabled(false)
        XCTAssertFalse(manager.isEnabled)

        // When enabled
        manager.setEnabled(true)
        XCTAssertTrue(manager.isEnabled)

        // Register a mock device
        let testDev = DiscoveredDLNARenderer(
            id: "uuid:test-wiim-pro-001",
            friendlyName: "Office WiiM Pro",
            manufacturer: "Linkplay",
            modelName: "WiiM Pro",
            locationURL: URL(string: "http://192.168.1.120:49152/description.xml")!
        )
        manager.registerDevice(testDev)

        let devices = manager.getDiscoveredDevices()
        XCTAssertTrue(devices.contains(where: { ($0["uid"] as? String) == "dlna:uuid:test-wiim-pro-001" }))
        XCTAssertEqual(devices.first?["name"] as? String, "Office WiiM Pro")
        XCTAssertEqual(devices.first?["type"] as? String, "dlna")
    }

    // MARK: - Local Action Debounce Tracking

    func testLocalActionDebounceTiming() {
        let manager = DLNADiscoveryManager.shared

        manager.markLocalAction()
        let elapsedImmediately = manager.timeSinceLastLocalAction()
        XCTAssertLessThan(elapsedImmediately, 0.5, "Elapsed time right after markLocalAction should be < 0.5s")

        // Wait a tiny bit
        Thread.sleep(forTimeInterval: 0.05)
        let elapsedAfter = manager.timeSinceLastLocalAction()
        XCTAssertGreaterThanOrEqual(elapsedAfter, 0.04, "Elapsed time should track real elapsed duration")
    }

    func testResolveStreamAndImageURLs() {
        let manager = DLNADiscoveryManager.shared
        let (streamURL, imageURL, title, metadata) = manager.resolveStreamAndImageURLs(sampleRate: 96000)

        XCTAssertTrue(streamURL.contains("/stream/live.wav?rate=96000&bits=24&t="))
        XCTAssertFalse(imageURL.isEmpty)
        XCTAssertFalse(title.isEmpty)
        XCTAssertTrue(metadata.contains("<DIDL-Lite"))
        XCTAssertTrue(metadata.contains("<upnp:albumArtURI>"))
    }
}
