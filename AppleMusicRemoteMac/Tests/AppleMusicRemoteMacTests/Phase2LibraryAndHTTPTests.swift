import XCTest
@testable import AppleMusicRemoteMac

final class Phase2LibraryAndHTTPTests: XCTestCase {

    func testDiskWebAssetsResolveViaCompileTimeSourceDirectoryWithoutEmbeddedSwiftLiterals() {
        let serverDir = WebSocketServer.compileTimeSourceWebDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AppleMusicRemoteMac/Server")
        for removedFile in ["WebUIContent+JS.swift", "WebUIContent+CSS.swift", "WebUIContent+HTML.swift"] {
            let path = serverDir.appendingPathComponent(removedFile).path
            XCTAssertFalse(FileManager.default.fileExists(atPath: path), "\(removedFile) must remain deleted")
        }

        XCTAssertGreaterThan(WebUIContent.appJS.utf8.count, 50_000, "app.js must load directly from Web/ directory")
        XCTAssertGreaterThan(WebUIContent.styleCSS.utf8.count, 10_000, "style.css must load directly from Web/ directory")
        XCTAssertTrue(WebUIContent.indexHTML.contains("<!DOCTYPE html>"))
    }

    func testETagComputationAndIfNoneMatchRFC7232Matching() {
        let payload = Data("Apple Music Remote Static Bundle".utf8)
        let rawETag = WebSocketServer.computeETag(for: payload)
        let gzipETag = WebSocketServer.computeETag(for: payload, variant: "gzip")
        XCTAssertNotEqual(rawETag, gzipETag, "Compressed and uncompressed representations must have distinct strong ETags")

        XCTAssertTrue(WebSocketServer.matchesIfNoneMatch(rawETag, etag: rawETag))
        XCTAssertTrue(WebSocketServer.matchesIfNoneMatch("W/\(rawETag)", etag: rawETag))
        XCTAssertTrue(WebSocketServer.matchesIfNoneMatch("\"other\", \(gzipETag)", etag: gzipETag))
        XCTAssertTrue(WebSocketServer.matchesIfNoneMatch("*", etag: rawETag))
        XCTAssertFalse(WebSocketServer.matchesIfNoneMatch(rawETag, etag: gzipETag))
        XCTAssertFalse(WebSocketServer.matchesIfNoneMatch(nil, etag: rawETag))
    }

    func testHTTPKeepAlivePolicyAndByteRangeParsingAndFileSliceStreaming() throws {
        let http11Default = "GET /app.js HTTP/1.1\r\nHost: localhost:8080\r\n\r\n"
        let http11Close = "GET /app.js HTTP/1.1\r\nHost: localhost:8080\r\nConnection: close\r\n\r\n"
        let http10Default = "GET /app.js HTTP/1.0\r\nHost: localhost:8080\r\n\r\n"
        let http10KeepAlive = "GET /app.js HTTP/1.0\r\nHost: localhost:8080\r\nConnection: Keep-Alive\r\n\r\n"

        XCTAssertTrue(WebSocketServer.shouldKeepHTTPConnectionAlive(headerString: http11Default))
        XCTAssertFalse(WebSocketServer.shouldKeepHTTPConnectionAlive(headerString: http11Close))
        XCTAssertFalse(WebSocketServer.shouldKeepHTTPConnectionAlive(headerString: http10Default))
        XCTAssertTrue(WebSocketServer.shouldKeepHTTPConnectionAlive(headerString: http10KeepAlive))

        XCTAssertEqual(
            WebSocketServer.parseHTTPByteRange(rangeHeader: "bytes=0-1", totalLength: 10_000),
            .satisfiable(start: 0, end: 1)
        )
        XCTAssertEqual(
            WebSocketServer.parseHTTPByteRange(rangeHeader: "bytes=500-", totalLength: 10_000),
            .satisfiable(start: 500, end: 9_999)
        )
        XCTAssertEqual(
            WebSocketServer.parseHTTPByteRange(rangeHeader: "bytes=-256", totalLength: 1_000),
            .satisfiable(start: 744, end: 999)
        )
        XCTAssertEqual(
            WebSocketServer.parseHTTPByteRange(rangeHeader: "bytes=10000-10050", totalLength: 10_000),
            .notSatisfiable
        )

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("amr-phase2-range-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var pattern = Data(capacity: 65_536)
        for i in 0..<65_536 {
            pattern.append(UInt8(i & 0xFF))
        }
        try pattern.write(to: tempURL)

        let slice = try XCTUnwrap(WebSocketServer.readFileByteSlice(url: tempURL, offset: 4099, length: 513))
        XCTAssertEqual(slice.count, 513)
        XCTAssertEqual(slice, pattern.subdata(in: 4099..<(4099 + 513)))
    }

    func testLiveWAVHeaderUnbounded0xFFFFFFFFAndRawDLNALPCMNetworkByteOrder() {
        let header = AudioProcessTapService.shared.makeWAVHeader(
            sampleRate: 96_000,
            bitDepth: 24,
            dataLength: AudioProcessTapService.unboundedWAVDataLength
        )
        XCTAssertEqual(header.count, 44)
        let riffSize = header.subdata(in: 4..<8).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let dataSize = header.subdata(in: 40..<44).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        XCTAssertEqual(UInt32(littleEndian: riffSize), 0xFFFF_FFFF)
        XCTAssertEqual(UInt32(littleEndian: dataSize), 0xFFFF_FFFF)

        // 16-bit LE [0x34, 0x12, 0x78, 0x56] -> BE [0x12, 0x34, 0x56, 0x78]
        let pcm16LE = Data([0x34, 0x12, 0x78, 0x56])
        let pcm16BE = WebSocketServer.convertLittleEndianPCMToNetworkByteOrder(pcm16LE, bitDepth: 16)
        XCTAssertEqual([UInt8](pcm16BE), [0x12, 0x34, 0x56, 0x78])

        // 24-bit LE [0x56, 0x34, 0x12, 0xBC, 0x9A, 0x78] -> BE [0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC]
        let pcm24LE = Data([0x56, 0x34, 0x12, 0xBC, 0x9A, 0x78])
        let pcm24BE = WebSocketServer.convertLittleEndianPCMToNetworkByteOrder(pcm24LE, bitDepth: 24)
        XCTAssertEqual([UInt8](pcm24BE), [0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC])
    }

    func testITLibraryReaderSyntheticIDMappingPinnedAppleScriptCacheAndBoundedServiceCaches() {
        // 1. ITLibraryReader synthetic ID <-> persistent hex & embedded artwork round-trip
        let fakeArt = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0xFF, 0xD9])
        let sid = ITLibraryReader.shared.registerSyntheticMappingForTesting(
            persistentIDHex: "8a3f12b4c5d6e7f8",
            artworkData: fakeArt
        )
        XCTAssertTrue(ITLibraryReader.isSyntheticTrackId(sid))
        XCTAssertLessThan(sid, 10_000_000)
        XCTAssertEqual(ITLibraryReader.shared.persistentIDHex(forTrackId: sid), "8A3F12B4C5D6E7F8")

        ArtworkService.shared.clearTrackArtworkCache(id: sid)
        let resolvedArt = ArtworkService.shared.getTrackArtwork(id: sid)
        XCTAssertEqual(resolvedArt, fakeArt)
        ArtworkService.shared.clearTrackArtworkCache(id: sid)

        // 2. AppleScriptExecutor pinned script survives dynamic script flood
        let pulse = "tell application \"Music\" to get {player state, player position}"
        AppleScriptExecutor.shared.pinScript(pulse)
        for idx in 0..<(AppleScriptExecutor.maxDynamicScripts + 20) {
            AppleScriptExecutor.shared.simulateDynamicScriptInsertionForTesting(
                "tell application \"Music\" to play track \(idx) of library playlist 1"
            )
        }
        let pulseStatus = AppleScriptExecutor.shared.isScriptCachedForTesting(pulse)
        XCTAssertTrue(pulseStatus.pinned, "Pinned pulse script must never be evicted by one-off dynamic scripts")
        let evictedFirst = AppleScriptExecutor.shared.isScriptCachedForTesting(
            "tell application \"Music\" to play track 0 of library playlist 1"
        )
        XCTAssertFalse(evictedFirst.dynamic, "Oldest dynamic script must be FIFO-evicted once capacity is exceeded")

        // 3. BitPerfectLogMonitor trackFormatCache cap (<= 2000)
        let monitor = BitPerfectLogMonitor.shared
        for i in 0..<(BitPerfectLogMonitor.maxTrackFormatCacheEntries + 150) {
            monitor.cacheTrackFormat(artist: "CapTestArtist", title: "Track-\(i)", sampleRate: 96_000, bitDepth: 24)
        }
        XCTAssertLessThanOrEqual(monitor.trackFormatCacheCountForTesting, BitPerfectLogMonitor.maxTrackFormatCacheEntries)
    }
}
