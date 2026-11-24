//
//  WebSocketServer+HTTPRouter.swift
//  AppleMusicRemoteMac
//
//  HTTP static asset serving, gzip compression, security headers (CSP / nosniff),
//  and API route dispatch.
//

import Foundation
import Network
import zlib

extension WebSocketServer {
    private static let staticAssetCacheLock = NSLock()
    private static var staticTextAssetCache: [String: (mtime: Date?, raw: Data, gzip: Data?)] = [:]

    private static let htmlContentSecurityPolicy =
        "default-src 'self' https://*.apple.com https://*.mzstatic.com data: blob:; " +
        "script-src 'self' https://js-cdn.music.apple.com; " +
        "style-src 'self' 'unsafe-inline'; " +
        "img-src 'self' https://*.mzstatic.com https://*.apple.com data: blob:; " +
        "media-src 'self' https://*.mzstatic.com https://*.apple.com blob: data:; " +
        "connect-src 'self' ws: wss: https://*.apple.com https://*.mzstatic.com; " +
        "object-src 'none'; base-uri 'self'; frame-ancestors 'none'"

    internal static func gzipCompress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        var stream = z_stream()
        let status = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            15 + 16,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard status == Z_OK else { return nil }
        defer { deflateEnd(&stream) }

        let maxOut = Int(deflateBound(&stream, uLong(data.count)))
        var compressed = Data(count: maxOut)
        let rc: Int32 = data.withUnsafeBytes { srcRaw in
            compressed.withUnsafeMutableBytes { dstRaw in
                guard let srcBase = srcRaw.bindMemory(to: Bytef.self).baseAddress,
                      let dstBase = dstRaw.bindMemory(to: Bytef.self).baseAddress else {
                    return Z_MEM_ERROR
                }
                stream.next_in = UnsafeMutablePointer(mutating: srcBase)
                stream.avail_in = uInt(data.count)
                stream.next_out = dstBase
                stream.avail_out = uInt(maxOut)
                return deflate(&stream, Z_FINISH)
            }
        }
        guard rc == Z_STREAM_END else { return nil }
        compressed.count = Int(stream.total_out)
        return compressed
    }

    private func candidateWebDirectories() -> [URL] {
        let currentDir = FileManager.default.currentDirectoryPath
        var baseWebDirs: [URL] = []
        if let resourcePath = Bundle.main.resourcePath {
            baseWebDirs.append(URL(fileURLWithPath: resourcePath).appendingPathComponent("Web"))
        }
        baseWebDirs.append(URL(fileURLWithPath: currentDir).appendingPathComponent("AppleMusicRemoteMac/Web"))
        baseWebDirs.append(URL(fileURLWithPath: currentDir).appendingPathComponent("Web"))
        baseWebDirs.append(URL(fileURLWithPath: currentDir).deletingLastPathComponent().appendingPathComponent("AppleMusicRemoteMac/Web"))
        baseWebDirs.append(URL(fileURLWithPath: currentDir).deletingLastPathComponent().appendingPathComponent("Web"))
        return baseWebDirs
    }

    private func loadCachedWebTextAsset(filename: String, fallback: String) -> (raw: Data, gzip: Data?) {
        var diskURL: URL? = nil
        var diskMtime: Date? = nil
        for baseWebURL in candidateWebDirectories() {
            let basePath = baseWebURL.standardizedFileURL.path
            let fileURL = baseWebURL.appendingPathComponent(filename).standardizedFileURL
            guard fileURL.path.hasPrefix(basePath + "/") else { continue }
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let mtime = attrs[.modificationDate] as? Date {
                diskURL = fileURL
                diskMtime = mtime
                break
            }
        }

        Self.staticAssetCacheLock.lock()
        if let cached = Self.staticTextAssetCache[filename], cached.mtime == diskMtime {
            Self.staticAssetCacheLock.unlock()
            return (cached.raw, cached.gzip)
        }
        Self.staticAssetCacheLock.unlock()

        let rawData: Data
        if let url = diskURL, let d = try? Data(contentsOf: url) {
            rawData = d
        } else {
            rawData = Data(fallback.utf8)
        }
        let gz = rawData.count >= 512 ? Self.gzipCompress(rawData) : nil

        Self.staticAssetCacheLock.lock()
        Self.staticTextAssetCache[filename] = (mtime: diskMtime, raw: rawData, gzip: gz)
        Self.staticAssetCacheLock.unlock()
        return (rawData, gz)
    }

    private func clientAcceptsGzip(_ headerString: String) -> Bool {
        guard let enc = extractHeader(named: "accept-encoding", from: headerString)?.lowercased() else {
            return false
        }
        return enc.contains("gzip")
    }

    // MARK: - HTTP Request Router

    func handleHTTPRequest(headerString: String, bodyData: Data, connection: NWConnection) {
        let firstLine = headerString.components(separatedBy: "\r\n").first ?? headerString.components(separatedBy: "\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendHTTPResponse(status: "400 Bad Request", contentType: "text/plain", body: Data("Bad Request".utf8), connection: connection)
            return
        }
        let method = String(parts[0]).uppercased()
        let fullPath = String(parts[1])
        let path = fullPath.components(separatedBy: "?").first ?? fullPath

        if method == "HEAD" {
            clientLock.lock()
            headRequestConnections.insert(ObjectIdentifier(connection))
            clientLock.unlock()
        }

        let hostHeader = extractHeader(named: "host", from: headerString)
        guard isValidHostHeader(hostHeader) else {
            NSLog("[HTTP] ❌ Rejected HTTP request with disallowed Host header: %@", hostHeader ?? "<missing>")
            sendForbiddenWithoutCORS(connection: connection)
            return
        }

        if let origin = extractHeader(named: "origin", from: headerString), !origin.isEmpty {
            if !isAllowedOrigin(origin, hostHeader: hostHeader) {
                NSLog("[HTTP] ❌ Rejected HTTP request from untrusted Origin: %@", origin)
                sendForbiddenWithoutCORS(connection: connection)
                return
            }
        }

        if method == "OPTIONS" {
            sendCORSPreflight(connection: connection)
            return
        }

        if method == "GET" || method == "HEAD" {
            handleGETOrHEADRequest(method: method, path: path, fullPath: fullPath, headerString: headerString, bodyData: bodyData, connection: connection)
        } else if method == "POST" && (path == "/api/duck" || path == "/api/unduck") {
            handlePOSTDuckingRequest(path: path, fullPath: fullPath, headerString: headerString, bodyData: bodyData, connection: connection)
        } else if method == "POST" && path == "/api/room-measurement/analyze" {
            handleRoomMeasurementAnalyzeHTTP(fullPath: fullPath, headerString: headerString, bodyData: bodyData, connection: connection)
        } else if method == "POST" && path == "/api/media" {
            guard isHTTPRequestAuthorized(headerString: headerString, fullPath: fullPath, bodyData: bodyData, connection: connection) else {
                sendHTTPResponse(status: "403 Forbidden", contentType: "application/json; charset=utf-8", body: Data("{\"status\":\"error\",\"error\":\"Device not authorized\"}".utf8), connection: connection)
                return
            }
            Task {
                await handleMediaAPI(headerString: headerString, fullPath: fullPath, bodyData: bodyData, connection: connection)
            }
        } else {
            sendHTTPResponse(status: "404 Not Found", contentType: "text/plain", body: Data("Not Found".utf8), connection: connection)
        }
    }

    private func handleGETOrHEADRequest(
        method: String,
        path: String,
        fullPath: String,
        headerString: String,
        bodyData: Data,
        connection: NWConnection
    ) {
        let acceptsGzip = clientAcceptsGzip(headerString)
        switch path {
        case "/", "/index.html":
            let asset = loadCachedWebTextAsset(filename: "index.html", fallback: WebUIContent.indexHTML)
            let body = (acceptsGzip ? asset.gzip : nil) ?? asset.raw
            let enc = (acceptsGzip && asset.gzip != nil) ? "gzip" : nil
            sendHTTPResponse(status: "200 OK", contentType: "text/html; charset=utf-8", body: body, connection: connection, cacheSeconds: 0, contentEncoding: enc)

        case "/style.css":
            let asset = loadCachedWebTextAsset(filename: "style.css", fallback: WebUIContent.styleCSS)
            let body = (acceptsGzip ? asset.gzip : nil) ?? asset.raw
            let enc = (acceptsGzip && asset.gzip != nil) ? "gzip" : nil
            sendHTTPResponse(status: "200 OK", contentType: "text/css; charset=utf-8", body: body, connection: connection, cacheSeconds: 0, contentEncoding: enc)

        case "/app.js":
            let asset = loadCachedWebTextAsset(filename: "app.js", fallback: WebUIContent.appJS)
            let body = (acceptsGzip ? asset.gzip : nil) ?? asset.raw
            let enc = (acceptsGzip && asset.gzip != nil) ? "gzip" : nil
            sendHTTPResponse(status: "200 OK", contentType: "application/javascript; charset=utf-8", body: body, connection: connection, cacheSeconds: 0, contentEncoding: enc)

        case "/manifest.json":
            let asset = loadCachedWebTextAsset(filename: "manifest.json", fallback: WebUIContent.manifestJSON)
            sendHTTPResponse(status: "200 OK", contentType: "application/json; charset=utf-8", body: asset.raw, connection: connection, cacheSeconds: 0)

        case "/sw.js":
            let asset = loadCachedWebTextAsset(filename: "sw.js", fallback: WebUIContent.swJS)
            let body = (acceptsGzip ? asset.gzip : nil) ?? asset.raw
            let enc = (acceptsGzip && asset.gzip != nil) ? "gzip" : nil
            sendHTTPResponse(status: "200 OK", contentType: "application/javascript; charset=utf-8", body: body, connection: connection, cacheSeconds: 0, contentEncoding: enc)

        case "/apple-touch-icon.svg":
            let content = loadWebAsset(filename: "apple-touch-icon.svg") ?? WebUIContent.appleTouchIconSVG
            sendHTTPResponse(status: "200 OK", contentType: "image/svg+xml; charset=utf-8", body: Data(content.utf8), connection: connection)

        case "/apple-touch-icon.png", "/apple-touch-icon-180.png", "/apple-touch-icon-192.png", "/apple-touch-icon-512.png", "/apple-touch-icon-precomposed.png":
            let filename = String(path.dropFirst())
            let lookupName = filename == "apple-touch-icon-precomposed.png" ? "apple-touch-icon.png" : filename
            if let data = loadWebBinaryAsset(subpath: lookupName) {
                sendHTTPResponse(status: "200 OK", contentType: "image/png", body: data, connection: connection, cacheSeconds: 86400 * 7)
            } else {
                let svg = loadWebAsset(filename: "apple-touch-icon.svg") ?? WebUIContent.appleTouchIconSVG
                sendHTTPResponse(status: "200 OK", contentType: "image/svg+xml; charset=utf-8", body: Data(svg.utf8), connection: connection)
            }

        case "/favicon.ico":
            if let data = loadWebBinaryAsset(subpath: "apple-touch-icon-180.png") ?? loadWebBinaryAsset(subpath: "apple-touch-icon.png") {
                sendHTTPResponse(status: "200 OK", contentType: "image/png", body: data, connection: connection, cacheSeconds: 86400 * 7)
            } else {
                sendHTTPResponse(status: "404 Not Found", contentType: "text/plain", body: Data("Not Found".utf8), connection: connection)
            }

        case let p where p.hasPrefix("/assets/"):
            handleStaticBinaryAssetHTTP(path: p, headerString: headerString, connection: connection)

        case "/stream/live.wav", "/stream/live":
            guard isHTTPRequestAuthorized(headerString: headerString, fullPath: fullPath, bodyData: bodyData, connection: connection)
                    || isAllowedDLNAStreamRequest(connection: connection, fullPath: fullPath) else {
                sendHTTPResponse(status: "403 Forbidden", contentType: "application/json; charset=utf-8", body: Data("{\"status\":\"error\",\"error\":\"Device not authorized\"}".utf8), connection: connection)
                return
            }
            if method == "HEAD" {
                _ = consumeHeadRequestFlag(for: connection)
                let headResp = "HTTP/1.1 200 OK\r\nContent-Type: audio/wav\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nAccept-Ranges: none\r\nCache-Control: no-cache, no-store\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(headResp.utf8), completion: .contentProcessed({ [weak self, weak connection] _ in
                    if let c = connection {
                        self?.untrackTCPConnection(c)
                        c.cancel()
                    }
                }))
                return
            }
            handleLiveAudioStream(connection: connection, headerString: headerString, fullPath: fullPath)

        case let p where p == "/api/artwork" || p == "/api/artwork.jpg" || p == "/artwork.jpg" || p.hasPrefix("/api/artwork.jpg?") || p.hasPrefix("/api/artwork?"):
            handleCurrentArtworkHTTP(headerString: headerString, fullPath: fullPath, bodyData: bodyData, connection: connection)

        case let p where p.hasPrefix("/api/artwork/search"):
            handleSearchArtworkHTTP(headerString: headerString, fullPath: fullPath, bodyData: bodyData, connection: connection)

        case let p where p.hasPrefix("/api/artwork/track"):
            handleTrackArtworkHTTP(headerString: headerString, fullPath: fullPath, bodyData: bodyData, connection: connection)

        case let p where p.hasPrefix("/api/artwork/playlist"):
            handlePlaylistArtworkHTTP(headerString: headerString, fullPath: fullPath, bodyData: bodyData, connection: connection)

        case let p where p.hasPrefix("/api/artwork/motion.mp4"):
            handleMotionArtworkHTTP(method: method, headerString: headerString, fullPath: fullPath, bodyData: bodyData, connection: connection)

        case "/api/status":
            guard isHTTPRequestAuthorized(headerString: headerString, fullPath: fullPath, bodyData: bodyData, connection: connection) else {
                sendHTTPResponse(status: "403 Forbidden", contentType: "application/json; charset=utf-8", body: Data("{\"status\":\"error\",\"error\":\"Device not authorized\"}".utf8), connection: connection)
                return
            }
            let status = MusicBridge.shared.getPlayerStatus()
            if let data = try? JSONEncoder().encode(status) {
                sendHTTPResponse(status: "200 OK", contentType: "application/json; charset=utf-8", body: data, connection: connection)
            } else {
                sendHTTPResponse(status: "500 Internal Server Error", contentType: "text/plain", body: Data("{}".utf8), connection: connection)
            }

        case let p where p == "/api/duck" || p == "/api/unduck" || p.hasPrefix("/api/duck?"):
            guard method == "GET" else {
                sendMethodNotAllowed(allowed: "POST", connection: connection)
                return
            }
            guard isDuckingGETRequestAuthorized(headerString: headerString, fullPath: fullPath, connection: connection) else {
                sendHTTPResponse(status: "403 Forbidden", contentType: "application/json; charset=utf-8", body: Data("{\"status\":\"error\",\"error\":\"POST or explicit API/device header required\"}".utf8), connection: connection)
                return
            }
            if p == "/api/unduck" {
                let res = MusicBridge.shared.deactivateDucking()
                broadcastStatus(includeQueue: false)
                let respObj: [String: Any] = [
                    "status": "ok",
                    "is_ducked": false,
                    "restored_volume": res.restoredVolume,
                    "volume": res.restoredVolume
                ]
                let data = (try? JSONSerialization.data(withJSONObject: respObj)) ?? Data("{}".utf8)
                sendHTTPResponse(status: "200 OK", contentType: "application/json; charset=utf-8", body: data, connection: connection)
            } else {
                var reduction = 80.0
                var timeout: Double? = nil
                if let components = URLComponents(string: fullPath) {
                    if let redStr = components.queryItems?.first(where: { $0.name == "reduction" || $0.name == "percent" })?.value, let val = Double(redStr) {
                        reduction = val
                    }
                    if let toStr = components.queryItems?.first(where: { $0.name == "timeout" || $0.name == "duration" })?.value, let val = Double(toStr) {
                        timeout = val
                    }
                }
                let res = MusicBridge.shared.activateDucking(reductionPercent: reduction, timeout: timeout)
                broadcastStatus(includeQueue: false)
                let respObj: [String: Any] = [
                    "status": "ok",
                    "is_ducked": true,
                    "original_volume": res.originalVolume,
                    "ducked_volume": res.duckedVolume,
                    "volume": res.duckedVolume
                ]
                let data = (try? JSONSerialization.data(withJSONObject: respObj)) ?? Data("{}".utf8)
                sendHTTPResponse(status: "200 OK", contentType: "application/json; charset=utf-8", body: data, connection: connection)
            }

        case "/api/booklet/info", "/api/booklet/page", "/api/booklet/pdf":
            handleBookletHTTP(path: path, fullPath: fullPath, headerString: headerString, bodyData: bodyData, connection: connection)

        default:
            sendHTTPResponse(status: "404 Not Found", contentType: "text/plain", body: Data("Not Found".utf8), connection: connection)
        }
    }

    private func handleStaticBinaryAssetHTTP(path p: String, headerString: String, connection: NWConnection) {
        let sub = String(p.dropFirst("/assets/".count))
        var assetData = loadWebBinaryAsset(subpath: "assets/\(sub)")
        var cType: String
        if sub.hasSuffix(".m4a") || sub.hasSuffix(".mp4") {
            cType = "audio/mp4"
        } else if sub.hasSuffix(".wav") {
            cType = "audio/wav"
        } else if sub.hasSuffix(".mp3") {
            cType = "audio/mpeg"
        } else if sub.hasSuffix(".png") {
            cType = "image/png"
        } else if sub.hasSuffix(".jpg") || sub.hasSuffix(".jpeg") {
            cType = "image/jpeg"
        } else if sub.hasSuffix(".svg") {
            cType = "image/svg+xml"
        } else {
            cType = "application/octet-stream"
        }
        if (assetData == nil || assetData?.isEmpty == true) && (p == "/assets/silence.wav" || p == "/assets/silence.m4a") {
            let pcmBytes = 44100 * 2 * 3
            var wav = makeWAVHeader(sampleRate: 44100, bitDepth: 16, channels: 1, dataSize: pcmBytes)
            wav.append(Data(count: pcmBytes))
            assetData = wav
            cType = "audio/wav"
        }
        guard let data = assetData else {
            sendHTTPResponse(status: "404 Not Found", contentType: "text/plain", body: Data("Not Found".utf8), connection: connection)
            return
        }
        serveByteRangeOrFullHTTP(data: data, contentType: cType, headerString: headerString, connection: connection, cacheSeconds: 86400 * 7)
    }

    internal func serveByteRangeOrFullHTTP(
        data: Data,
        contentType: String,
        headerString: String,
        connection: NWConnection,
        cacheSeconds: Int
    ) {
        if let rangeHeader = extractHeader(named: "Range", from: headerString),
           rangeHeader.hasPrefix("bytes=") {
            let spec = String(rangeHeader.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            let parts = spec.components(separatedBy: "-")
            if parts.count >= 2 {
                let startStr = parts[0].trimmingCharacters(in: .whitespaces)
                let endStr = parts[1].trimmingCharacters(in: .whitespaces)
                let total = data.count
                let start: Int
                let end: Int
                if startStr.isEmpty {
                    let suffix = Int(endStr) ?? 0
                    guard suffix > 0, total > 0 else {
                        sendRangeNotSatisfiable(totalLength: total, connection: connection)
                        return
                    }
                    start = max(0, total - suffix)
                    end = total - 1
                } else {
                    guard let parsedStart = Int(startStr), parsedStart >= 0 else {
                        sendRangeNotSatisfiable(totalLength: total, connection: connection)
                        return
                    }
                    start = parsedStart
                    let parsedEnd = endStr.isEmpty ? (total - 1) : (Int(endStr) ?? (total - 1))
                    end = min(parsedEnd, total - 1)
                }
                guard start < total && start <= end else {
                    sendRangeNotSatisfiable(totalLength: total, connection: connection)
                    return
                }
                let chunk = data.subdata(in: start..<(end + 1))
                sendPartialHTTPResponse(contentType: contentType, rangeStart: start, rangeEnd: end, totalLength: total, body: chunk, connection: connection, cacheSeconds: cacheSeconds)
                return
            }
        }
        sendHTTPResponse(status: "200 OK", contentType: contentType, body: data, connection: connection, cacheSeconds: cacheSeconds)
    }

    // MARK: - HTTP Response Writers

    internal func consumeHeadRequestFlag(for connection: NWConnection) -> Bool {
        clientLock.lock()
        defer { clientLock.unlock() }
        return headRequestConnections.remove(ObjectIdentifier(connection)) != nil
    }

    internal func sendForbiddenWithoutCORS(connection: NWConnection) {
        let isHead = consumeHeadRequestFlag(for: connection)
        let body = Data("{\"status\":\"error\",\"error\":\"Forbidden\"}".utf8)
        let header = "HTTP/1.1 403 Forbidden\r\nContent-Type: application/json; charset=utf-8\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var respData = Data(header.utf8)
        if !isHead {
            respData.append(body)
        }
        connection.send(content: respData, completion: .contentProcessed({ [weak self, weak connection] _ in
            if let c = connection {
                self?.untrackTCPConnection(c)
                c.cancel()
            }
        }))
    }

    internal func sendMethodNotAllowed(allowed: String, connection: NWConnection) {
        _ = consumeHeadRequestFlag(for: connection)
        let header = "HTTP/1.1 405 Method Not Allowed\r\nAllow: \(allowed)\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed({ [weak self, weak connection] _ in
            if let c = connection {
                self?.untrackTCPConnection(c)
                c.cancel()
            }
        }))
    }

    internal func sendRangeNotSatisfiable(totalLength: Int, connection: NWConnection) {
        _ = consumeHeadRequestFlag(for: connection)
        let header = "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */\(totalLength)\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed({ [weak self, weak connection] _ in
            if let c = connection {
                self?.untrackTCPConnection(c)
                c.cancel()
            }
        }))
    }

    internal func sendHTTPResponse(
        status: String,
        contentType: String,
        body: Data,
        connection: NWConnection,
        cacheSeconds: Int = 0,
        setCookie: String? = nil,
        headOnly: Bool = false,
        contentEncoding: String? = nil
    ) {
        let isHead = headOnly || consumeHeadRequestFlag(for: connection)
        var header = "HTTP/1.1 \(status)\r\n" +
            "Content-Type: \(contentType)\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "X-Content-Type-Options: nosniff\r\n" +
            "Referrer-Policy: no-referrer\r\n" +
            "Accept-Ranges: bytes\r\n" +
            "Access-Control-Allow-Methods: GET, POST, OPTIONS, HEAD\r\n" +
            "Access-Control-Allow-Headers: Range, Content-Type, X-AMR-Device-ID, X-AMR-Device-Secret, X-AMR-API-Token, Authorization\r\n" +
            "Connection: close\r\n"
        if contentType.lowercased().contains("text/html") {
            header += "Content-Security-Policy: \(Self.htmlContentSecurityPolicy)\r\n"
        }
        if let enc = contentEncoding, !enc.isEmpty {
            header += "Content-Encoding: \(enc)\r\nVary: Accept-Encoding\r\n"
        }
        if let cookie = setCookie, !cookie.isEmpty {
            header += "Set-Cookie: \(cookie)\r\n"
        }
        if cacheSeconds > 0 {
            header += "Cache-Control: public, max-age=\(cacheSeconds)\r\n"
        } else {
            header += "Cache-Control: no-cache\r\n"
        }
        header += "\r\n"
        var respData = Data(header.utf8)
        if !isHead {
            respData.append(body)
        }
        connection.send(content: respData, completion: .contentProcessed({ [weak self, weak connection] _ in
            if let c = connection {
                self?.untrackTCPConnection(c)
                c.cancel()
            }
        }))
    }

    internal func sendPartialHTTPResponse(
        contentType: String,
        rangeStart: Int,
        rangeEnd: Int,
        totalLength: Int,
        body: Data,
        connection: NWConnection,
        cacheSeconds: Int = 2592000
    ) {
        let isHead = consumeHeadRequestFlag(for: connection)
        var header = "HTTP/1.1 206 Partial Content\r\n" +
            "Content-Type: \(contentType)\r\n" +
            "Content-Range: bytes \(rangeStart)-\(rangeEnd)/\(totalLength)\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "X-Content-Type-Options: nosniff\r\n" +
            "Referrer-Policy: no-referrer\r\n" +
            "Accept-Ranges: bytes\r\n" +
            "Access-Control-Allow-Methods: GET, HEAD, OPTIONS\r\n" +
            "Access-Control-Allow-Headers: Range, Content-Type, X-AMR-Device-ID, X-AMR-Device-Secret, X-AMR-API-Token, Authorization\r\n"
        if cacheSeconds > 0 {
            header += "Cache-Control: public, max-age=\(cacheSeconds)\r\n"
        } else {
            header += "Cache-Control: no-cache\r\n"
        }
        header += "Connection: close\r\n\r\n"
        var respData = Data(header.utf8)
        if !isHead {
            respData.append(body)
        }
        connection.send(content: respData, completion: .contentProcessed({ [weak self, weak connection] _ in
            if let c = connection {
                self?.untrackTCPConnection(c)
                c.cancel()
            }
        }))
    }

    internal func sendDefaultArtwork(connection: NWConnection) {
        if let pngData = loadWebBinaryAsset(subpath: "apple-touch-icon-512.png") ?? loadWebBinaryAsset(subpath: "apple-touch-icon.png") {
            sendHTTPResponse(status: "200 OK", contentType: "image/png", body: pngData, connection: connection, cacheSeconds: 0)
        } else {
            let fallback = loadWebAsset(filename: "apple-touch-icon.svg") ?? WebUIContent.appleTouchIconSVG
            sendHTTPResponse(status: "200 OK", contentType: "image/svg+xml; charset=utf-8", body: Data(fallback.utf8), connection: connection, cacheSeconds: 0)
        }
    }

    internal func sendCORSPreflight(connection: NWConnection) {
        _ = consumeHeadRequestFlag(for: connection)
        let header = "HTTP/1.1 204 No Content\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS, HEAD\r\nAccess-Control-Allow-Headers: Range, Content-Type, X-AMR-Device-ID, X-AMR-Device-Secret, X-AMR-API-Token, Authorization\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed({ [weak self, weak connection] _ in
            if let c = connection {
                self?.untrackTCPConnection(c)
                c.cancel()
            }
        }))
    }

    internal func sendRedirect(location: String, connection: NWConnection, cacheSeconds: Int = 0) {
        _ = consumeHeadRequestFlag(for: connection)
        let safeLocation = location.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        var header = "HTTP/1.1 302 Found\r\nLocation: \(safeLocation)\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Length: 0\r\nConnection: close\r\n"
        if cacheSeconds > 0 {
            header += "Cache-Control: public, max-age=\(cacheSeconds)\r\n"
        } else {
            header += "Cache-Control: no-cache, no-store, must-revalidate\r\n"
        }
        header += "\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed({ [weak self, weak connection] _ in
            if let c = connection {
                self?.untrackTCPConnection(c)
                c.cancel()
            }
        }))
    }

    internal func loadWebAsset(filename: String) -> String? {
        guard !filename.isEmpty,
              !filename.contains(".."),
              !filename.hasPrefix("/"),
              !filename.hasPrefix("\\") else {
            return nil
        }

        for baseWebURL in candidateWebDirectories() {
            let basePath = baseWebURL.standardizedFileURL.path
            let resolvedURL = baseWebURL.appendingPathComponent(filename).standardizedFileURL
            guard resolvedURL.path.hasPrefix(basePath + "/") else { continue }
            if FileManager.default.fileExists(atPath: resolvedURL.path),
               let content = try? String(contentsOfFile: resolvedURL.path, encoding: .utf8) {
                return content
            }
        }

        switch filename {
        case "index.html": return WebUIContent.indexHTML
        case "style.css": return WebUIContent.styleCSS
        case "app.js": return WebUIContent.appJS
        case "manifest.json": return WebUIContent.manifestJSON
        case "sw.js": return WebUIContent.swJS
        case "apple-touch-icon.svg": return WebUIContent.appleTouchIconSVG
        default: return nil
        }
    }

    internal func loadWebBinaryAsset(subpath: String) -> Data? {
        guard !subpath.isEmpty,
              !subpath.contains(".."),
              !subpath.hasPrefix("/"),
              !subpath.hasPrefix("\\") else {
            return nil
        }

        for baseWebURL in candidateWebDirectories() {
            let basePath = baseWebURL.standardizedFileURL.path
            let resolvedURL = baseWebURL.appendingPathComponent(subpath).standardizedFileURL
            guard resolvedURL.path.hasPrefix(basePath + "/") else { continue }
            if FileManager.default.fileExists(atPath: resolvedURL.path),
               let data = try? Data(contentsOf: resolvedURL) {
                return data
            }
        }
        return nil
    }
}
