//
//  UPnPMediaRendererFullTests.swift
//  AppleMusicRemoteMacTests
//

import XCTest
@testable import AppleMusicRemoteMac

final class UPnPMediaRendererFullTests: XCTestCase {

    func testSOAPActionExtraction() {
        let server = UPnPMediaRendererServer.shared

        // 1. With quotes and namespace hash
        let headers1 = ["SOAPACTION": "\"urn:schemas-upnp-org:service:AVTransport:1#Play\""]
        XCTAssertEqual(server.extractSOAPAction(from: headers1, body: ""), "Play")

        // 2. Without quotes
        let headers2 = ["SOAPACTION": "urn:schemas-upnp-org:service:AVTransport:1#Pause"]
        XCTAssertEqual(server.extractSOAPAction(from: headers2, body: ""), "Pause")

        // 3. Simple action name
        let headers3 = ["SOAPACTION": "Stop"]
        XCTAssertEqual(server.extractSOAPAction(from: headers3, body: ""), "Stop")

        // 4. Fallback to XML body when header is absent
        let body = "<s:Envelope><s:Body><u:Next xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"></u:Next></s:Body></s:Envelope>"
        XCTAssertEqual(server.extractSOAPAction(from: [:], body: body), "Next")

        // 5. Empty when neither exists
        XCTAssertEqual(server.extractSOAPAction(from: [:], body: "<invalid></invalid>"), "")
    }

    func testTagValueExtraction() {
        let server = UPnPMediaRendererServer.shared

        let xml = "<InstanceID>0</InstanceID><CurrentURI>http://stream.example.com/live</CurrentURI><Speed>1</Speed>"
        XCTAssertEqual(server.extractTagValue(tag: "InstanceID", from: xml), "0")
        XCTAssertEqual(server.extractTagValue(tag: "CurrentURI", from: xml), "http://stream.example.com/live")
        XCTAssertEqual(server.extractTagValue(tag: "Speed", from: xml), "1")
        XCTAssertNil(server.extractTagValue(tag: "NonExistentTag", from: xml))
    }

    func testEscapes() {
        let server = UPnPMediaRendererServer.shared
        let raw = "Rock & Roll <Live> \"The Best\" '80s"

        let escapedSOAP = server.escapeForSOAP(raw)
        XCTAssertEqual(escapedSOAP, "Rock &amp; Roll &lt;Live&gt; &quot;The Best&quot; &apos;80s")

        let escapedLastChange = server.escapeForLastChangeVal(raw)
        XCTAssertEqual(escapedLastChange, "Rock &amp;amp; Roll &amp;lt;Live&amp;gt; &amp;quot;The Best&amp;quot; &amp;apos;80s")
    }

    func testResolveArtworkURI() {
        let server = UPnPMediaRendererServer.shared
        let ip = "192.168.1.50"

        // 1. Nil track
        let nilArt = server.resolveArtworkURI(for: nil, lanIP: ip)
        XCTAssertEqual(nilArt, "http://192.168.1.50:8090/artwork/icon.png")

        // 2. Remote CDN URL
        let cdnTrack = TrackInfo(name: "Song", artworkUrl: "https://is1-ssl.mzstatic.com/image/thumb/Music/test.jpg")
        let cdnArt = server.resolveArtworkURI(for: cdnTrack, lanIP: ip)
        XCTAssertEqual(cdnArt, "https://is1-ssl.mzstatic.com/image/thumb/Music/test.jpg")

        // 3. Relative AMR server URL
        let relTrack = TrackInfo(name: "Local Song", artworkUrl: "/api/artwork/track?id=42")
        let relArt = server.resolveArtworkURI(for: relTrack, lanIP: ip)
        XCTAssertEqual(relArt, "http://192.168.1.50:8080/api/artwork/track?id=42")

        // 4. Empty artwork fallback to UPnP endpoint
        let emptyTrack = TrackInfo(id: "123", name: "No Art", artist: "Artist", artworkUrl: "")
        let fallbackArt = server.resolveArtworkURI(for: emptyTrack, lanIP: ip)
        XCTAssertTrue(fallbackArt.hasPrefix("http://192.168.1.50:8090/artwork/current.jpg?v=123_"))
    }

    func testTimeConversion() {
        let server = UPnPMediaRendererServer.shared

        // Formatting
        XCTAssertEqual(server.formatSecondsToTime(0), "00:00:00")
        XCTAssertEqual(server.formatSecondsToTime(5), "00:00:05")
        XCTAssertEqual(server.formatSecondsToTime(65), "00:01:05")
        XCTAssertEqual(server.formatSecondsToTime(3665), "01:01:05")

        // Parsing
        XCTAssertEqual(server.parseTimeToSeconds("00:00:00"), 0.0)
        XCTAssertEqual(server.parseTimeToSeconds("00:01:05"), 65.0)
        XCTAssertEqual(server.parseTimeToSeconds("01:01:05"), 3665.0)
        XCTAssertEqual(server.parseTimeToSeconds("invalid"), 0.0)
    }

    func testDIDLLiteGenerationWithSpecialChars() {
        let server = UPnPMediaRendererServer.shared
        let xml = server.generateDIDLLiteXML(
            title: "Rock & Roll",
            artist: "AC/DC <Band>",
            album: "Back in Black \"Remastered\"",
            artUri: "http://example.com/art.jpg",
            durTimeStr: "00:04:15"
        )

        XCTAssertTrue(xml.contains("<dc:title>Rock &amp; Roll</dc:title>"))
        XCTAssertTrue(xml.contains("<dc:creator>AC/DC &lt;Band&gt;</dc:creator>"))
        XCTAssertTrue(xml.contains("Back in Black &quot;Remastered&quot;"))
        XCTAssertTrue(xml.contains("<res duration=\"00:04:15\""))
    }
}
