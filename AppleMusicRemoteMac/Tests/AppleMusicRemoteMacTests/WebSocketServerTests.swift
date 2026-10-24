//
//  WebSocketServerTests.swift
//  AppleMusicRemoteMacTests
//

import XCTest
@testable import AppleMusicRemoteMac

final class WebSocketServerTests: XCTestCase {

    func testWebSocketAcceptRFC6455Compliance() {
        let server = WebSocketServer.shared
        // RFC 6455 official test vector:
        // Key: "dGhlIHNhbXBsZSBub25jZQ==" -> Accept: "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
        let key = "dGhlIHNhbXBsZSBub25jZQ=="
        let accept = server.webSocketAccept(for: key)
        XCTAssertEqual(accept, "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", "webSocketAccept must strictly match RFC 6455 standard")
    }

    func testExtractHeaderCaseInsensitive() {
        let server = WebSocketServer.shared
        let rawHeader = """
        GET / HTTP/1.1\r
        Host: localhost:8080\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r
        Sec-WebSocket-Version: 13\r
        \r
        """

        XCTAssertEqual(server.extractHeader(named: "Upgrade", from: rawHeader), "websocket")
        XCTAssertEqual(server.extractHeader(named: "upgrade", from: rawHeader), "websocket")
        XCTAssertEqual(server.extractHeader(named: "CONNECTION", from: rawHeader), "Upgrade")
        XCTAssertEqual(server.extractHeader(named: "Sec-WebSocket-Key", from: rawHeader), "dGhlIHNhbXBsZSBub25jZQ==")
        XCTAssertNil(server.extractHeader(named: "Non-Existent", from: rawHeader))
    }

    func testMakeWebSocketFrameSmallMediumLarge() {
        let server = WebSocketServer.shared

        // 1. Small payload (<= 125 bytes)
        let smallPayload = Data("Hello, Apple Music Remote!".utf8)
        let smallFrame = server.makeWebSocketFrame(payload: smallPayload, opcode: 0x01)
        XCTAssertEqual(smallFrame[0], 0x81) // FIN + text opcode
        XCTAssertEqual(smallFrame[1], UInt8(smallPayload.count)) // No mask bit, length
        XCTAssertEqual(smallFrame.subdata(in: 2..<smallFrame.count), smallPayload)

        // 2. Medium payload (126 .. 65535 bytes)
        let mediumCount = 300
        let mediumPayload = Data(repeating: 0x41, count: mediumCount)
        let mediumFrame = server.makeWebSocketFrame(payload: mediumPayload, opcode: 0x02)
        XCTAssertEqual(mediumFrame[0], 0x82) // FIN + binary opcode
        XCTAssertEqual(mediumFrame[1], 126) // Extended 16-bit length indicator
        let high = UInt16(mediumFrame[2])
        let low = UInt16(mediumFrame[3])
        let len16 = (high << 8) | low
        XCTAssertEqual(Int(len16), mediumCount)
        XCTAssertEqual(mediumFrame.count, 4 + mediumCount)

        // 3. Large payload (> 65535 bytes)
        let largeCount = 70000
        let largePayload = Data(repeating: 0x42, count: largeCount)
        let largeFrame = server.makeWebSocketFrame(payload: largePayload, opcode: 0x01)
        XCTAssertEqual(largeFrame[0], 0x81)
        XCTAssertEqual(largeFrame[1], 127) // Extended 64-bit length indicator
        XCTAssertEqual(largeFrame.count, 10 + largeCount)
    }

    func testDecodeWebSocketFramesUnmaskedAndMasked() {
        let server = WebSocketServer.shared

        // 1. Unmasked frame
        let helloData = Data("PING".utf8)
        var buffer = server.makeWebSocketFrame(payload: helloData, opcode: 0x09)
        let frames1 = server.decodeWebSocketFrames(buffer: &buffer)
        XCTAssertEqual(frames1.count, 1)
        XCTAssertEqual(frames1[0].opcode, 0x09)
        XCTAssertEqual(frames1[0].payload, helloData)
        XCTAssertTrue(buffer.isEmpty)

        // 2. Client-to-server Masked frame
        // Text "Hello" (0x48, 0x65, 0x6c, 0x6c, 0x6f) with mask key [0x12, 0x34, 0x56, 0x78]
        let maskKey: [UInt8] = [0x12, 0x34, 0x56, 0x78]
        let plain = [UInt8]("Hello".utf8)
        var masked = [UInt8]()
        for (i, b) in plain.enumerated() {
            masked.append(b ^ maskKey[i % 4])
        }

        var maskedBuffer = Data()
        maskedBuffer.append(0x81) // FIN + text
        maskedBuffer.append(0x80 | UInt8(plain.count)) // Masked bit + len 5
        maskedBuffer.append(contentsOf: maskKey)
        maskedBuffer.append(contentsOf: masked)

        let frames2 = server.decodeWebSocketFrames(buffer: &maskedBuffer)
        XCTAssertEqual(frames2.count, 1)
        XCTAssertEqual(frames2[0].opcode, 0x01)
        XCTAssertEqual(String(data: frames2[0].payload, encoding: .utf8), "Hello")
        XCTAssertTrue(maskedBuffer.isEmpty)
    }

    func testDecodeWebSocketFramesIncompleteBuffer() {
        let server = WebSocketServer.shared
        // Incomplete buffer (only 1 byte)
        var buf1 = Data([0x81])
        let res1 = server.decodeWebSocketFrames(buffer: &buf1)
        XCTAssertTrue(res1.isEmpty)
        XCTAssertEqual(buf1.count, 1) // Buffer retained for next read

        // Incomplete payload
        var buf2 = Data([0x81, 0x05, 0x41, 0x42]) // Length is 5, but only 2 bytes present
        let res2 = server.decodeWebSocketFrames(buffer: &buf2)
        XCTAssertTrue(res2.isEmpty)
        XCTAssertEqual(buf2.count, 4)
    }

    func testLoadWebAssetExistingAndMissing() {
        let server = WebSocketServer.shared
        // Existing files
        let html = server.loadWebAsset(filename: "index.html")
        XCTAssertNotNil(html)
        XCTAssertTrue(html?.contains("Apple Music Remote") ?? false)

        let css = server.loadWebAsset(filename: "style.css")
        XCTAssertNotNil(css)

        let js = server.loadWebAsset(filename: "app.js")
        XCTAssertNotNil(js)

        // Non-existent file
        let missing = server.loadWebAsset(filename: "non_existent_file_xyz.html")
        XCTAssertNil(missing)
    }

    func testLoadWebBinaryAssetExistingAndMissing() {
        let server = WebSocketServer.shared
        let icon = server.loadWebBinaryAsset(subpath: "apple-touch-icon-180.png")
        XCTAssertNotNil(icon)
        XCTAssertGreaterThan(icon?.count ?? 0, 0)

        let missing = server.loadWebBinaryAsset(subpath: "does_not_exist.bin")
        XCTAssertNil(missing)
    }

    func testGetLANIPAddressesReturnsValidList() {
        let server = WebSocketServer.shared
        let ips = server.getLANIPAddresses()
        XCTAssertFalse(ips.isEmpty, "LAN IP addresses should never be empty")
        for ip in ips {
            XCTAssertFalse(ip.isEmpty)
            // Should be valid IPv4 representation (e.g. 192.168.x.x, 10.x.x.x, or 127.0.0.1)
            let parts = ip.split(separator: ".")
            XCTAssertEqual(parts.count, 4, "IP address \(ip) should have 4 octets")
        }
    }
}
