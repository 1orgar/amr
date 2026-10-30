//
//  UPnPMediaRendererServerTests.swift
//  AppleMusicRemoteMacTests
//

import XCTest
@testable import AppleMusicRemoteMac

final class UPnPMediaRendererServerTests: XCTestCase {

    func testDeviceDescriptionContainsAllRequiredServices() {
        let server = UPnPMediaRendererServer.shared
        let xml = server.buildDeviceDescriptionXML()

        // 1. Root and device headers
        XCTAssertTrue(xml.contains("<deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>"))
        XCTAssertTrue(xml.contains("<friendlyName>"))
        XCTAssertTrue(xml.contains("<modelName>AMR-MediaRenderer</modelName>"))
        XCTAssertTrue(xml.contains("<UDN>"))

        // 2. AVTransport Service
        XCTAssertTrue(xml.contains("<serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>"))
        XCTAssertTrue(xml.contains("<controlURL>/upnp/control/avtransport</controlURL>"))
        XCTAssertTrue(xml.contains("<eventSubURL>/upnp/event/avtransport</eventSubURL>"))
        XCTAssertTrue(xml.contains("<SCPDURL>/upnp/scpd/avtransport.xml</SCPDURL>"))

        // 3. RenderingControl Service (essential for Home Assistant volume and mute)
        XCTAssertTrue(xml.contains("<serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>"))
        XCTAssertTrue(xml.contains("<controlURL>/upnp/control/renderingcontrol</controlURL>"))
        XCTAssertTrue(xml.contains("<eventSubURL>/upnp/event/renderingcontrol</eventSubURL>"))
        XCTAssertTrue(xml.contains("<SCPDURL>/upnp/scpd/renderingcontrol.xml</SCPDURL>"))

        // 4. ConnectionManager Service
        XCTAssertTrue(xml.contains("<serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>"))
        XCTAssertTrue(xml.contains("<controlURL>/upnp/control/connectionmanager</controlURL>"))
        XCTAssertTrue(xml.contains("<eventSubURL>/upnp/event/connectionmanager</eventSubURL>"))
        XCTAssertTrue(xml.contains("<SCPDURL>/upnp/scpd/connectionmanager.xml</SCPDURL>"))
    }

    func testFormatSecondsToTime() {
        let server = UPnPMediaRendererServer.shared
        XCTAssertEqual(server.formatSecondsToTime(0), "00:00:00")
        XCTAssertEqual(server.formatSecondsToTime(-10), "00:00:00")
        XCTAssertEqual(server.formatSecondsToTime(5), "00:00:05")
        XCTAssertEqual(server.formatSecondsToTime(65), "00:01:05")
        XCTAssertEqual(server.formatSecondsToTime(3600), "01:00:00")
        XCTAssertEqual(server.formatSecondsToTime(3665), "01:01:05")
    }

    func testParseTimeToSeconds() {
        let server = UPnPMediaRendererServer.shared
        XCTAssertEqual(server.parseTimeToSeconds("00:00:00"), 0.0)
        XCTAssertEqual(server.parseTimeToSeconds("00:01:05"), 65.0)
        XCTAssertEqual(server.parseTimeToSeconds("01:01:05"), 3665.0)
        XCTAssertEqual(server.parseTimeToSeconds("02:30"), 150.0)
        XCTAssertEqual(server.parseTimeToSeconds("45"), 45.0)
    }

    func testEscapeXMLText() {
        let server = UPnPMediaRendererServer.shared
        let raw = "Rock & Roll <Live> \"AC/DC\" 'Back in Black'"
        let escaped = server.escapeXMLText(raw)
        XCTAssertEqual(escaped, "Rock &amp; Roll &lt;Live&gt; &quot;AC/DC&quot; &apos;Back in Black&apos;")
    }

    func testGenerateDIDLLiteXML() {
        let server = UPnPMediaRendererServer.shared
        let didl = server.generateDIDLLiteXML(
            title: "Comfortably Numb",
            artist: "Pink Floyd & Friends",
            album: "The Wall",
            artUri: "http://127.0.0.1:8090/artwork/current.jpg",
            durTimeStr: "00:06:22"
        )

        XCTAssertTrue(didl.contains("<dc:title>Comfortably Numb</dc:title>"))
        XCTAssertTrue(didl.contains("<dc:creator>Pink Floyd &amp; Friends</dc:creator>"))
        XCTAssertTrue(didl.contains("The Wall"))
        XCTAssertTrue(didl.contains("http://127.0.0.1:8090/artwork/current.jpg"))
        XCTAssertTrue(didl.contains("duration=\"00:06:22\""))
        XCTAssertTrue(didl.contains("xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\""))
    }

    func testArtworkURIWithAmpersandsEscapedInDIDL() {
        let server = UPnPMediaRendererServer.shared
        let artUriWithParams = "http://10.10.20.180:8080/api/artwork/track?id=3456&name=Self%20Esteem&artist=The%20Offspring"
        let didl = server.generateDIDLLiteXML(
            title: "Self Esteem",
            artist: "The Offspring",
            album: "Smash",
            artUri: artUriWithParams,
            durTimeStr: "00:04:17"
        )

        // In DIDL-Lite, & must be escaped as &amp;
        XCTAssertTrue(didl.contains("http://10.10.20.180:8080/api/artwork/track?id=3456&amp;name=Self%20Esteem&amp;artist=The%20Offspring"))
        XCTAssertFalse(didl.contains("&name="))
    }

    func testArtworkURIEscapingForLastChange() {
        let server = UPnPMediaRendererServer.shared
        let artUriWithParams = "http://10.10.20.180:8080/api/artwork/track?id=3456&name=Self%20Esteem&artist=The%20Offspring"
        let escaped = server.escapeForLastChangeVal(artUriWithParams)

        // Inside LastChange element, & in attributes must be &amp;amp; so outer XML parser doesn't break
        XCTAssertTrue(escaped.contains("&amp;amp;name="))
        XCTAssertFalse(escaped.contains("&name="))
    }

    func testLocalDMRToggleAndPersistence() {
        let server = UPnPMediaRendererServer.shared
        UserDefaults.standard.removeObject(forKey: UPnPMediaRendererServer.defaultsKey)

        // Default should be true
        XCTAssertTrue(server.isEnabled)

        // Toggle to false
        server.setEnabled(false)
        XCTAssertFalse(server.isEnabled)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: UPnPMediaRendererServer.defaultsKey))

        // startIfEnabled should return false when disabled
        XCTAssertFalse(server.startIfEnabled(port: 8090))

        // Toggle back to true
        server.setEnabled(true)
        XCTAssertTrue(server.isEnabled)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: UPnPMediaRendererServer.defaultsKey))
    }
}
