//
//  WebSocketServer+HTTPArtworkAndStream.swift
//  AppleMusicRemoteMac
//
//  HTTP artwork endpoints, digital booklet endpoints, room measurement upload,
//  and live WAV PCM streaming with backpressure & leak-free subscriber cleanup.
//

import Foundation
import Network

private final class LiveStreamBackpressureState: @unchecked Sendable {
    private let lock = NSLock()
    private var _isClosed = false
    private var _pendingChunks = 0
    private let maxPendingChunks: Int

    init(maxPendingChunks: Int = 64) {
        self.maxPendingChunks = maxPendingChunks
    }

    var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isClosed
    }

    /// Returns `true` if the state transitioned from open -> closed (ensures one-shot cleanup).
    func markClosed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if _isClosed { return false }
        _isClosed = true
        return true
    }

    /// Returns `true` if chunk is accepted, or `false` if closed / exceeded backpressure limit.
    func tryAcquireSendSlot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !_isClosed, _pendingChunks < maxPendingChunks else {
            return false
        }
        _pendingChunks += 1
        return true
    }

    func releaseSendSlot() {
        lock.lock()
        if _pendingChunks > 0 {
            _pendingChunks -= 1
        }
        lock.unlock()
    }
}

extension WebSocketServer {
    internal func handleCurrentArtworkHTTP(headerString: String, fullPath: String, bodyData: Data, connection: NWConnection) {
        guard isHTTPRequestAuthorized(headerString: headerString, fullPath: fullPath, bodyData: bodyData, connection: connection)
                || isAllowedDLNAStreamRequest(connection: connection, fullPath: fullPath)
                || isAllowedLANArtworkRequest(headerString: headerString, fullPath: fullPath, connection: connection) else {
            sendHTTPResponse(status: "403 Forbidden", contentType: "application/json; charset=utf-8", body: Data("{\"status\":\"error\",\"error\":\"Device not authorized\"}".utf8), connection: connection)
            return
        }
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            let curStatus = MusicBridge.shared.getPlayerStatus()
            let trackArt = (curStatus.track?.artworkUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            if trackArt.hasPrefix("/assets/") {
                self.serveStationCoverAssetOrRedirect(assetPath: trackArt, preferDirectBytes: true, connection: connection)
                return
            }

            if !trackArt.isEmpty && (trackArt.hasPrefix("http://") || trackArt.hasPrefix("https://")) {
                self.serveArtworkURLOrRedirect(trackArt, preferDirectBytes: true, connection: connection)
                return
            }

            let tName = curStatus.track?.name ?? ""
            let tArtist = curStatus.track?.artist ?? ""
            let tAlbum = curStatus.track?.album ?? ""
            if !tName.isEmpty, let cloudUrlStr = MusicKitManager.shared.getCachedTrackArtwork(name: tName, artist: tArtist, album: tAlbum), !cloudUrlStr.isEmpty {
                self.serveArtworkURLOrRedirect(cloudUrlStr, preferDirectBytes: true, connection: connection)
                return
            }

            if curStatus.track?.isLocal != false, let art = MusicBridge.shared.getCurrentTrackArtwork(), !art.isEmpty {
                self.sendHTTPResponse(status: "200 OK", contentType: "image/jpeg", body: art, connection: connection, cacheSeconds: 0)
                return
            }

            if !tName.isEmpty,
               let searchedUrlStr = await MusicKitManager.shared.searchTrackArtwork(name: tName, artist: tArtist, album: tAlbum),
               !searchedUrlStr.isEmpty {
                self.serveArtworkURLOrRedirect(searchedUrlStr, preferDirectBytes: true, connection: connection)
                return
            }

            if let fallbackArt = MusicBridge.shared.getCurrentTrackArtwork(), !fallbackArt.isEmpty {
                self.sendHTTPResponse(status: "200 OK", contentType: "image/jpeg", body: fallbackArt, connection: connection, cacheSeconds: 0)
                return
            }

            self.sendDefaultArtwork(connection: connection)
        }
    }

    internal func handleSearchArtworkHTTP(headerString: String, fullPath: String, bodyData: Data, connection: NWConnection) {
        let isAuthorizedApp = isHTTPRequestAuthorized(headerString: headerString, fullPath: fullPath, bodyData: bodyData, connection: connection)
        guard isAuthorizedApp || isAllowedLANArtworkRequest(headerString: headerString, fullPath: fullPath, connection: connection) else {
            sendHTTPResponse(status: "403 Forbidden", contentType: "application/json; charset=utf-8", body: Data("{\"status\":\"error\",\"error\":\"Device not authorized\"}".utf8), connection: connection)
            return
        }
        let preferDirect = !isAuthorizedApp
        let tName = extractQueryParameter(named: "name", from: fullPath) ?? ""
        let tArtist = extractQueryParameter(named: "artist", from: fullPath) ?? ""
        let tAlbum = extractQueryParameter(named: "album", from: fullPath) ?? ""
        let lowName = tName.lowercased()
        if lowName.contains("моя станция") || lowName.contains("my station") {
            serveStationCoverAssetOrRedirect(assetPath: "/assets/stations/CoverPersonal.png", preferDirectBytes: preferDirect, connection: connection)
            return
        } else if lowName.contains("станция открытий") || lowName.contains("discovery station") {
            serveStationCoverAssetOrRedirect(assetPath: "/assets/stations/CoverDiscovery.png", preferDirectBytes: preferDirect, connection: connection)
            return
        } else if lowName.contains("сейчас на повторе") || lowName.contains("heavy rotation") {
            serveStationCoverAssetOrRedirect(assetPath: "/assets/stations/CoverHeavyRotation.svg", preferDirectBytes: preferDirect, connection: connection)
            return
        } else if lowName.contains("apple music 1") {
            serveStationCoverAssetOrRedirect(assetPath: "/assets/stations/CoverAppleMusic1.png", preferDirectBytes: preferDirect, connection: connection)
            return
        }

        if let cached = MusicKitManager.shared.getCachedTrackArtwork(name: tName, artist: tArtist, album: tAlbum), !cached.isEmpty {
            serveArtworkURLOrRedirect(cached, preferDirectBytes: preferDirect, connection: connection)
        } else if !tAlbum.isEmpty,
                  let localAlbArt = ArtworkService.shared.getCachedLocalAlbumArtwork(album: tAlbum, artist: tArtist),
                  !localAlbArt.isEmpty {
            sendHTTPResponse(status: "200 OK", contentType: "image/jpeg", body: localAlbArt, connection: connection, cacheSeconds: 86400)
        } else {
            Task { [weak self] in
                guard let self = self else { return }
                if let cloudArt = await MusicKitManager.shared.searchTrackArtwork(name: tName, artist: tArtist, album: tAlbum) {
                    self.serveArtworkURLOrRedirect(cloudArt, preferDirectBytes: preferDirect, connection: connection)
                } else {
                    self.sendDefaultArtwork(connection: connection)
                }
            }
        }
    }

    internal func handleTrackArtworkHTTP(headerString: String, fullPath: String, bodyData: Data, connection: NWConnection) {
        let isAuthorizedApp = isHTTPRequestAuthorized(headerString: headerString, fullPath: fullPath, bodyData: bodyData, connection: connection)
        guard isAuthorizedApp || isAllowedLANArtworkRequest(headerString: headerString, fullPath: fullPath, connection: connection) else {
            sendHTTPResponse(status: "403 Forbidden", contentType: "application/json; charset=utf-8", body: Data("{\"status\":\"error\",\"error\":\"Device not authorized\"}".utf8), connection: connection)
            return
        }
        let preferDirect = !isAuthorizedApp
        let trackId = extractQueryParameter(named: "id", from: fullPath).flatMap(Int.init) ?? 0
        let paramName = extractQueryParameter(named: "name", from: fullPath) ?? ""
        let paramArtist = extractQueryParameter(named: "artist", from: fullPath) ?? ""
        let paramAlbum = extractQueryParameter(named: "album", from: fullPath) ?? ""

        let lowTrackName = paramName.lowercased()
        if lowTrackName.contains("моя станция") || lowTrackName.contains("my station") {
            serveStationCoverAssetOrRedirect(assetPath: "/assets/stations/CoverPersonal.png", preferDirectBytes: preferDirect, connection: connection)
            return
        } else if lowTrackName.contains("станция открытий") || lowTrackName.contains("discovery station") {
            serveStationCoverAssetOrRedirect(assetPath: "/assets/stations/CoverDiscovery.png", preferDirectBytes: preferDirect, connection: connection)
            return
        } else if lowTrackName.contains("сейчас на повторе") || lowTrackName.contains("heavy rotation") {
            serveStationCoverAssetOrRedirect(assetPath: "/assets/stations/CoverHeavyRotation.svg", preferDirectBytes: preferDirect, connection: connection)
            return
        }

        if trackId > 0, let fastArt = ArtworkService.shared.getCachedTrackArtwork(id: trackId) ?? ArtworkDiskCache.shared.get(key: "track_\(trackId)"), !fastArt.isEmpty {
            sendHTTPResponse(status: "200 OK", contentType: "image/jpeg", body: fastArt, connection: connection, cacheSeconds: 86400)
            return
        }

        let meta = (trackId > 0) ? MusicBridge.shared.getTrackMetadata(id: trackId) : nil
        let effName = !paramName.isEmpty ? paramName : (meta?.name ?? "")
        let effArtist = !paramArtist.isEmpty ? paramArtist : (meta?.artist ?? "")
        let effAlbum = !paramAlbum.isEmpty ? paramAlbum : (meta?.album ?? "")

        if !effAlbum.isEmpty,
           let fastAlbArt = ArtworkService.shared.getCachedLocalAlbumArtwork(album: effAlbum, artist: effArtist),
           !fastAlbArt.isEmpty {
            sendHTTPResponse(status: "200 OK", contentType: "image/jpeg", body: fastAlbArt, connection: connection, cacheSeconds: 86400)
            return
        }

        if (!effName.isEmpty || !effAlbum.isEmpty),
           let cached = MusicKitManager.shared.getCachedTrackArtwork(name: effName, artist: effArtist, album: effAlbum),
           !cached.isEmpty {
            serveArtworkURLOrRedirect(cached, preferDirectBytes: preferDirect, connection: connection)
            return
        }

        let resolvedTrackId = trackId
        let hasCloudQuery = !effName.isEmpty || !effAlbum.isEmpty
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            let wasBusy = hasCloudQuery && AppleScriptExecutor.shared.isBusy
            if resolvedTrackId > 0 && !wasBusy && !ArtworkService.shared.isKnownMissingTrackArtwork(id: resolvedTrackId),
               let art = MusicBridge.shared.getTrackArtwork(
                   id: resolvedTrackId,
                   album: effAlbum,
                   artist: effArtist,
                   skipIfContended: hasCloudQuery
               ), !art.isEmpty {
                self.sendHTTPResponse(status: "200 OK", contentType: "image/jpeg", body: art, connection: connection, cacheSeconds: 86400)
                return
            }
            if hasCloudQuery,
               let cloudArt = await MusicKitManager.shared.searchTrackArtwork(name: effName, artist: effArtist, album: effAlbum) {
                self.serveArtworkURLOrRedirect(cloudArt, preferDirectBytes: preferDirect, connection: connection)
                return
            }
            if resolvedTrackId > 0 && !ArtworkService.shared.isKnownMissingTrackArtwork(id: resolvedTrackId),
               let fallbackLocalArt = MusicBridge.shared.getTrackArtwork(
                   id: resolvedTrackId,
                   album: effAlbum,
                   artist: effArtist,
                   skipIfContended: false
               ), !fallbackLocalArt.isEmpty {
                self.sendHTTPResponse(status: "200 OK", contentType: "image/jpeg", body: fallbackLocalArt, connection: connection, cacheSeconds: 86400)
                return
            }
            self.sendDefaultArtwork(connection: connection)
        }
    }

    internal func handlePlaylistArtworkHTTP(headerString: String, fullPath: String, bodyData: Data, connection: NWConnection) {
        let isAuthorizedApp = isHTTPRequestAuthorized(headerString: headerString, fullPath: fullPath, bodyData: bodyData, connection: connection)
        guard isAuthorizedApp || isAllowedLANArtworkRequest(headerString: headerString, fullPath: fullPath, connection: connection) else {
            sendHTTPResponse(status: "403 Forbidden", contentType: "application/json; charset=utf-8", body: Data("{\"status\":\"error\",\"error\":\"Device not authorized\"}".utf8), connection: connection)
            return
        }
        let preferDirect = !isAuthorizedApp
        let targetPlName = extractQueryParameter(named: "name", from: fullPath) ?? ""
        if targetPlName.isEmpty {
            sendDefaultArtwork(connection: connection)
        } else if let cachedCloudUrl = ArtworkService.shared.getCachedPlaylistArtworkUrl(name: targetPlName),
                  cachedCloudUrl.hasPrefix("http") {
            serveArtworkURLOrRedirect(cachedCloudUrl, preferDirectBytes: preferDirect, connection: connection)
        } else {
            Task.detached(priority: .utility) { [weak self] in
                guard let self = self else { return }
                if let art = MusicBridge.shared.getPlaylistArtwork(name: targetPlName), !art.isEmpty {
                    self.sendHTTPResponse(status: "200 OK", contentType: "image/jpeg", body: art, connection: connection, cacheSeconds: 86400)
                    return
                }
                let activeSf = MusicKitManager.shared.getUserStorefront()
                var cloudArtUrl = await MusicKitManager.shared.searchPlaylistArtwork(name: targetPlName, storefront: activeSf)
                if (cloudArtUrl == nil || cloudArtUrl?.isEmpty == true) && activeSf != "us" {
                    cloudArtUrl = await MusicKitManager.shared.searchPlaylistArtwork(name: targetPlName, storefront: "us")
                }
                if let artUrl = cloudArtUrl, !artUrl.isEmpty {
                    ArtworkService.shared.setPlaylistArtworkUrl(name: targetPlName, url: artUrl)
                    self.serveArtworkURLOrRedirect(artUrl, preferDirectBytes: preferDirect, connection: connection)
                    return
                }
                self.sendDefaultArtwork(connection: connection)
            }
        }
    }

    internal static let motionStreamChunkSize: Int = 524_288 // 512 KB bounded RAM per active .mp4 stream

    internal static func readFileByteSlice(url: URL, offset: Int, length: Int) -> Data? {
        guard offset >= 0, length >= 0 else { return nil }
        if length == 0 { return Data() }
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        do {
            try fh.seek(toOffset: UInt64(offset))
            return try fh.read(upToCount: length)
        } catch {
            return nil
        }
    }

    internal func handleMotionArtworkHTTP(method: String, headerString: String, fullPath: String, bodyData: Data, connection: NWConnection) {
        guard isHTTPRequestAuthorized(headerString: headerString, fullPath: fullPath, bodyData: bodyData, connection: connection) else {
            sendHTTPResponse(status: "403 Forbidden", contentType: "application/json; charset=utf-8", body: Data("{\"status\":\"error\",\"error\":\"Device not authorized\"}".utf8), connection: connection)
            return
        }
        let hashParam = extractQueryParameter(named: "hash", from: fullPath) ?? ""
        let cleanHash = hashParam.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let fileMeta = MotionArtworkDiskCache.shared.videoFileLocationAndSize(forHash: cleanHash) else {
            sendHTTPResponse(status: "404 Not Found", contentType: "text/plain", body: Data("Not Found".utf8), connection: connection)
            return
        }

        let etag = "\"\(cleanHash.prefix(24))\""
        let totalSize = fileMeta.fileSize

        if method == "HEAD" {
            _ = consumeHeadRequestFlag(for: connection)
            let keepAlive = isKeepAliveEnabled(for: connection)
            let connHdr = keepAlive ? "Connection: keep-alive\r\nKeep-Alive: timeout=15, max=200\r\n" : "Connection: close\r\n"
            let headResp = "HTTP/1.1 200 OK\r\nContent-Type: video/mp4\r\nETag: \(etag)\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Length: \(totalSize)\r\nAccept-Ranges: bytes\r\nCache-Control: public, max-age=604800\r\n\(connHdr)\r\n"
            connection.send(content: Data(headResp.utf8), completion: .contentProcessed({ [weak self, weak connection] error in
                if let c = connection {
                    self?.finishHTTPResponseCycle(connection: c, forceClose: error != nil || !keepAlive)
                }
            }))
            return
        }

        let rangeHeader = extractHeader(named: "Range", from: headerString)
        if rangeHeader == nil,
           Self.matchesIfNoneMatch(extractHeader(named: "If-None-Match", from: headerString), etag: etag) {
            sendNotModified(etag: etag, cacheSeconds: 604800, varyGzip: false, connection: connection)
            return
        }

        let rangeStart: Int
        let rangeEnd: Int
        let isPartial: Bool
        switch Self.parseHTTPByteRange(rangeHeader: rangeHeader, totalLength: totalSize) {
        case .satisfiable(let s, let e):
            rangeStart = s
            rangeEnd = e
            isPartial = true
        case .notSatisfiable:
            sendRangeNotSatisfiable(totalLength: totalSize, connection: connection)
            return
        case .none:
            rangeStart = 0
            rangeEnd = totalSize - 1
            isPartial = false
        }

        guard let fh = try? FileHandle(forReadingFrom: fileMeta.url) else {
            sendHTTPResponse(status: "404 Not Found", contentType: "text/plain", body: Data("Not Found".utf8), connection: connection)
            return
        }
        do {
            try fh.seek(toOffset: UInt64(rangeStart))
        } catch {
            try? fh.close()
            sendRangeNotSatisfiable(totalLength: totalSize, connection: connection)
            return
        }

        _ = consumeHeadRequestFlag(for: connection)
        let keepAlive = isKeepAliveEnabled(for: connection)
        let sliceLength = rangeEnd - rangeStart + 1
        let connHdr = keepAlive ? "Connection: keep-alive\r\nKeep-Alive: timeout=15, max=200\r\n" : "Connection: close\r\n"
        var respHeader: String
        if isPartial {
            respHeader = "HTTP/1.1 206 Partial Content\r\n" +
                "Content-Type: video/mp4\r\n" +
                "Content-Range: bytes \(rangeStart)-\(rangeEnd)/\(totalSize)\r\n"
        } else {
            respHeader = "HTTP/1.1 200 OK\r\n" +
                "Content-Type: video/mp4\r\n"
        }
        respHeader += "Content-Length: \(sliceLength)\r\n" +
            "ETag: \(etag)\r\n" +
            "X-Content-Type-Options: nosniff\r\n" +
            "Referrer-Policy: no-referrer\r\n" +
            "Accept-Ranges: bytes\r\n" +
            "Access-Control-Allow-Methods: GET, HEAD, OPTIONS\r\n" +
            "Access-Control-Allow-Headers: Range, Content-Type, X-AMR-Device-ID, X-AMR-Device-Secret, X-AMR-API-Token, Authorization\r\n" +
            "Cache-Control: public, max-age=604800\r\n" +
            "\(connHdr)\r\n"

        connection.send(content: Data(respHeader.utf8), isComplete: false, completion: .contentProcessed({ [weak self, weak connection] error in
            guard let self = self, let c = connection else {
                try? fh.close()
                return
            }
            if error != nil {
                try? fh.close()
                self.finishHTTPResponseCycle(connection: c, forceClose: true)
                return
            }
            self.streamNextFileChunk(fileHandle: fh, remainingBytes: sliceLength, keepAlive: keepAlive, connection: c)
        }))
    }

    private func streamNextFileChunk(
        fileHandle: FileHandle,
        remainingBytes: Int,
        keepAlive: Bool,
        connection: NWConnection
    ) {
        if remainingBytes <= 0 {
            try? fileHandle.close()
            finishHTTPResponseCycle(connection: connection, forceClose: !keepAlive)
            return
        }
        let readSize = min(Self.motionStreamChunkSize, remainingBytes)
        let chunk: Data
        do {
            chunk = (try fileHandle.read(upToCount: readSize)) ?? Data()
        } catch {
            try? fileHandle.close()
            finishHTTPResponseCycle(connection: connection, forceClose: true)
            return
        }
        if chunk.isEmpty {
            try? fileHandle.close()
            finishHTTPResponseCycle(connection: connection, forceClose: true)
            return
        }
        let nextRemaining = remainingBytes - chunk.count
        connection.send(content: chunk, isComplete: false, completion: .contentProcessed({ [weak self, weak connection] error in
            guard let self = self, let c = connection else {
                try? fileHandle.close()
                return
            }
            if error != nil {
                try? fileHandle.close()
                self.finishHTTPResponseCycle(connection: c, forceClose: true)
                return
            }
            self.streamNextFileChunk(fileHandle: fileHandle, remainingBytes: nextRemaining, keepAlive: keepAlive, connection: c)
        }))
    }

    internal func handleBookletHTTP(path: String, fullPath: String, headerString: String, bodyData: Data, connection: NWConnection) {
        guard isHTTPRequestAuthorized(headerString: headerString, fullPath: fullPath, bodyData: bodyData, connection: connection) else {
            sendHTTPResponse(status: "403 Forbidden", contentType: "application/json; charset=utf-8", body: Data("{\"status\":\"error\",\"error\":\"Device not authorized\"}".utf8), connection: connection)
            return
        }
        switch path {
        case "/api/booklet/info":
            var qAlbum: String? = nil
            var qArtist: String? = nil
            var qAlbumId: String? = nil
            var qTrack: String? = nil
            var qRefresh = false
            if let components = URLComponents(string: fullPath.replacingOccurrences(of: "+", with: "%20")) {
                qAlbum = components.queryItems?.first(where: { $0.name == "album" })?.value
                qArtist = components.queryItems?.first(where: { $0.name == "artist" })?.value
                qAlbumId = components.queryItems?.first(where: { $0.name == "album_id" || $0.name == "id" })?.value
                qTrack = components.queryItems?.first(where: { $0.name == "track" || $0.name == "name" })?.value
                if let refVal = components.queryItems?.first(where: { $0.name == "refresh" })?.value {
                    qRefresh = (refVal == "1" || refVal.lowercased() == "true")
                }
            }
            let (reqAlbum, reqArtist, reqAlbumId, reqTrack, reqRefresh) = (qAlbum, qArtist, qAlbumId, qTrack, qRefresh)
            Task { [weak self] in
                guard let self = self else { return }
                let info = await DigitalBookletService.shared.resolveBooklet(
                    album: reqAlbum,
                    artist: reqArtist,
                    albumId: reqAlbumId,
                    trackName: reqTrack,
                    forceRefresh: reqRefresh
                )
                let data = (try? JSONEncoder().encode(info)) ?? Data("{}".utf8)
                self.sendHTTPResponse(status: "200 OK", contentType: "application/json; charset=utf-8", body: data, connection: connection, cacheSeconds: 0)
            }

        case "/api/booklet/page":
            var bookletId = ""
            var pageIndex = 0
            var scale: Double = 1600
            if let components = URLComponents(string: fullPath) {
                bookletId = components.queryItems?.first(where: { $0.name == "id" })?.value ?? ""
                if let pStr = components.queryItems?.first(where: { $0.name == "page" })?.value, let pVal = Int(pStr) {
                    pageIndex = pVal
                }
                if let sStr = components.queryItems?.first(where: { $0.name == "scale" || $0.name == "width" })?.value, let sVal = Double(sStr) {
                    scale = sVal
                }
            }
            let (bid, pIdx, maxDim) = (bookletId, pageIndex, CGFloat(scale))
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                if let jpegData = DigitalBookletService.shared.renderPageImage(bookletId: bid, pageIndex: pIdx, maxDimension: maxDim) {
                    self.sendHTTPResponse(status: "200 OK", contentType: "image/jpeg", body: jpegData, connection: connection, cacheSeconds: 3600)
                } else {
                    self.sendHTTPResponse(status: "404 Not Found", contentType: "text/plain", body: Data("Booklet page not found".utf8), connection: connection)
                }
            }

        default:
            var bookletId = ""
            if let components = URLComponents(string: fullPath) {
                bookletId = components.queryItems?.first(where: { $0.name == "id" })?.value ?? ""
            }
            if let pdfResult = DigitalBookletService.shared.getPdfData(bookletId: bookletId) {
                sendHTTPResponse(status: "200 OK", contentType: "application/pdf", body: pdfResult.data, connection: connection, cacheSeconds: 300)
            } else {
                sendHTTPResponse(status: "404 Not Found", contentType: "text/plain", body: Data("Booklet PDF not found".utf8), connection: connection)
            }
        }
    }

    internal func handlePOSTDuckingRequest(path: String, fullPath: String, headerString: String, bodyData: Data, connection: NWConnection) {
        guard isHTTPRequestAuthorized(headerString: headerString, fullPath: fullPath, bodyData: bodyData, connection: connection) else {
            sendHTTPResponse(status: "403 Forbidden", contentType: "application/json; charset=utf-8", body: Data("{\"status\":\"error\",\"error\":\"Device not authorized\"}".utf8), connection: connection)
            return
        }
        if path == "/api/duck" {
            var reduction = 80.0
            var timeout: Double? = nil
            if let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] {
                if let num = (json["reduction"] as? NSNumber) ?? (json["percent"] as? NSNumber) {
                    reduction = num.doubleValue
                }
                if let num = (json["timeout"] as? NSNumber) ?? (json["duration"] as? NSNumber) {
                    timeout = num.doubleValue
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
        } else {
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
        }
    }

    internal func handleRoomMeasurementAnalyzeHTTP(fullPath: String, headerString: String, bodyData: Data, connection: NWConnection) {
        guard isHTTPRequestAuthorized(headerString: headerString, fullPath: fullPath, bodyData: Data(), connection: connection) else {
            let errText = AMRLocalization.tr("Device not authorized", "Устройство не авторизовано")
            sendHTTPResponse(
                status: "403 Forbidden",
                contentType: "application/json; charset=utf-8",
                body: Data("{\"status\":\"error\",\"error\":\"\(errText)\"}".utf8),
                connection: connection
            )
            return
        }

        let queryDeviceId = extractQueryParameter(named: "device_id", from: fullPath)
            ?? extractQueryParameter(named: "deviceId", from: fullPath)
        let queryExt = extractQueryParameter(named: "ext", from: fullPath)
        let queryName = extractQueryParameter(named: "name", from: fullPath)
        let queryDeviceName = extractQueryParameter(named: "device_name", from: fullPath)

        let resolvedDeviceId = nonEmpty(extractHeader(named: "x-amr-device-id", from: headerString))
            ?? nonEmpty(extractCookie(named: "amr_device_uid", from: headerString))
            ?? nonEmpty(queryDeviceId)

        let roomDisabledErr = AMRLocalization.tr(
            "Room acoustic measurement is disabled for this device in Mac settings",
            "Измерение АЧХ комнаты отключено для этого устройства в настройках Mac"
        )
        if let devId = resolvedDeviceId {
            guard ClientDeviceManager.shared.canDeviceMeasureRoom(deviceId: devId) else {
                sendHTTPResponse(
                    status: "403 Forbidden",
                    contentType: "application/json; charset=utf-8",
                    body: Data("{\"status\":\"error\",\"error\":\"\(roomDisabledErr)\"}".utf8),
                    connection: connection
                )
                return
            }
        } else if isLocalhostConnection(connection) {
            guard canLocalhostMeasureRoom() else {
                sendHTTPResponse(
                    status: "403 Forbidden",
                    contentType: "application/json; charset=utf-8",
                    body: Data("{\"status\":\"error\",\"error\":\"\(roomDisabledErr)\"}".utf8),
                    connection: connection
                )
                return
            }
        } else {
            sendHTTPResponse(
                status: "403 Forbidden",
                contentType: "application/json; charset=utf-8",
                body: Data("{\"status\":\"error\",\"error\":\"Missing device_id for room measurement\"}".utf8),
                connection: connection
            )
            return
        }

        RoomAcousticService.shared.stopTestSignal()

        let contentType = (extractHeader(named: "content-type", from: headerString) ?? "").lowercased()
        let inferredExt: String = {
            if let qExt = queryExt, !qExt.isEmpty { return qExt }
            if contentType.contains("wav") { return "wav" }
            if contentType.contains("caf") { return "caf" }
            if contentType.contains("aiff") { return "aiff" }
            if contentType.contains("aac") { return "aac" }
            if contentType.contains("mp3") || contentType.contains("mpeg") { return "mp3" }
            return "m4a"
        }()

        let clientRecordName = resolvedDeviceId.flatMap { ClientDeviceManager.shared.getDevice(deviceId: $0)?.deviceName }
        let deviceLabel = clientRecordName ?? queryDeviceName ?? "iPhone / iPad"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let profile = try RoomAcousticService.shared.analyzeUploadedAudioData(
                    bodyData,
                    fileExtensionHint: inferredExt,
                    profileName: queryName,
                    deviceName: deviceLabel,
                    autoSaveAndEnable: true
                )
                var statusPayload = RoomAcousticService.shared.statusDictionary()
                statusPayload["status"] = "ok"
                statusPayload["created_profile"] = profile.dictionary
                self.broadcastEvent(name: "room_acoustic_settings", data: statusPayload)
                self.broadcastEvent(name: "dsp_settings", data: Self.buildDSPSettingsDictionary())
                self.broadcastStatus(includeQueue: false)
                DispatchQueue.main.async {
                    MenuManager.shared.updateMenuState()
                    SettingsWindow.refreshIfVisible()
                }
                let respData = (try? JSONSerialization.data(withJSONObject: statusPayload)) ?? Data("{\"status\":\"ok\"}".utf8)
                self.sendHTTPResponse(status: "200 OK", contentType: "application/json; charset=utf-8", body: respData, connection: connection)
            } catch {
                let errPayload: [String: Any] = ["status": "error", "error": error.localizedDescription]
                let errData = (try? JSONSerialization.data(withJSONObject: errPayload)) ?? Data("{\"status\":\"error\"}".utf8)
                self.sendHTTPResponse(status: "400 Bad Request", contentType: "application/json; charset=utf-8", body: errData, connection: connection)
            }
        }
    }

    // MARK: - Live Audio Stream (/stream/live.wav) with Leak-Free Backpressure

    private func cleanupLiveAudioStream(subscriberID: UUID, streamState: LiveStreamBackpressureState, streamInstanceID: String? = nil, wasBackpressureClose: Bool = false) {
        guard streamState.markClosed() else { return }
        AudioProcessTapService.shared.removeSubscriber(id: subscriberID)
        if let conn = removeLiveStreamConnection(id: subscriberID) {
            if !wasBackpressureClose {
                DLNADiscoveryManager.shared.noteDLNALiveStreamClientDisconnected(sid: streamInstanceID)
            }
            untrackTCPConnection(conn)
            conn.cancel()
        }
    }

    internal static func convertLittleEndianPCMToNetworkByteOrder(_ chunk: Data, bitDepth: Int) -> Data {
        guard !chunk.isEmpty else { return chunk }
        var out = Data(count: chunk.count)
        chunk.withUnsafeBytes { srcRaw in
            out.withUnsafeMutableBytes { dstRaw in
                guard let src = srcRaw.bindMemory(to: UInt8.self).baseAddress,
                      let dst = dstRaw.bindMemory(to: UInt8.self).baseAddress else { return }
                if bitDepth == 24 {
                    let samples = chunk.count / 3
                    var idx = 0
                    for _ in 0..<samples {
                        dst[idx] = src[idx + 2]
                        dst[idx + 1] = src[idx + 1]
                        dst[idx + 2] = src[idx]
                        idx += 3
                    }
                    while idx < chunk.count {
                        dst[idx] = src[idx]
                        idx += 1
                    }
                } else {
                    let samples = chunk.count / 2
                    var idx = 0
                    for _ in 0..<samples {
                        dst[idx] = src[idx + 1]
                        dst[idx + 1] = src[idx]
                        idx += 2
                    }
                    if idx < chunk.count {
                        dst[idx] = src[idx]
                    }
                }
            }
        }
        return out
    }

    internal func handleLiveAudioStream(
        connection: NWConnection,
        headerString: String,
        fullPath: String,
        rawLPCM: Bool = false
    ) {
        let subscriberID = UUID()
        let streamState = LiveStreamBackpressureState(maxPendingChunks: 64)
        let streamInstanceID = extractQueryParameter(named: "sid", from: fullPath)

        let isAuthorizedCaller = isHTTPRequestAuthorized(headerString: headerString, fullPath: fullPath, bodyData: Data(), connection: connection)
        let isAuthorizedDLNA = isAllowedDLNAStreamRequest(connection: connection, fullPath: fullPath)
        guard isAuthorizedCaller || isAuthorizedDLNA else {
            sendHTTPResponse(status: "403 Forbidden", contentType: "application/json; charset=utf-8", body: Data("{\"status\":\"error\",\"error\":\"Device not authorized\"}".utf8), connection: connection)
            return
        }

        cancelConnectionIdleTimeout(for: connection)
        liveStreamLock.lock()
        liveStreamConnections[subscriberID] = connection
        liveStreamLock.unlock()

        // Install stateUpdateHandler BEFORE adding tap subscriber so early cancellation cannot leak!
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                NSLog("[WebSocketServer] 🔌 Live stream client disconnected (subscriber: \(subscriberID))")
                self?.cleanupLiveAudioStream(subscriberID: subscriberID, streamState: streamState, streamInstanceID: isAuthorizedDLNA ? streamInstanceID : nil)
            default:
                break
            }
        }

        switch connection.state {
        case .cancelled, .failed:
            cleanupLiveAudioStream(subscriberID: subscriberID, streamState: streamState, streamInstanceID: isAuthorizedDLNA ? streamInstanceID : nil)
            return
        default:
            break
        }

        var requestedRate: Int? = nil
        var requestedBits: Int? = nil
        if isAuthorizedCaller || isAuthorizedDLNA {
            if let rateStr = extractQueryParameter(named: "rate", from: fullPath),
               let r = Int(rateStr),
               [44_100, 48_000, 88_200, 96_000, 176_400, 192_000, 352_800, 384_000].contains(r) {
                requestedRate = r
            }
            if let bitsStr = extractQueryParameter(named: "bits", from: fullPath) ?? extractQueryParameter(named: "depth", from: fullPath),
               let b = Int(bitsStr),
               (b == 16 || b == 24) {
                requestedBits = b
            }
        }

        let detectedDepth = BitPerfectLogMonitor.shared.currentDetectedBitDepth
        let canConfigureCapture = (!AudioProcessTapService.shared.isCapturing || AudioProcessTapService.shared.subscriberCount == 0)
            && (isAuthorizedCaller || isAuthorizedDLNA)
        let effectiveRate: Int
        let effectiveBits: Int
        if canConfigureCapture {
            let curFmt = AudioProcessTapService.shared.currentFormatSync()
            let rate = requestedRate ?? curFmt.sampleRate
            let bits = requestedBits ?? detectedDepth ?? (rate >= 48000 ? 24 : 16)
            let fmt = AudioProcessTapService.shared.setFormatSync(sampleRate: rate, bitDepth: bits)
            effectiveRate = fmt.sampleRate
            effectiveBits = fmt.bitDepth
        } else {
            let fmt = AudioProcessTapService.shared.currentFormatSync()
            effectiveRate = fmt.sampleRate
            effectiveBits = fmt.bitDepth
        }

        let streamBits = (effectiveBits == 24) ? 24 : 16
        let contentType = rawLPCM
            ? "audio/L\(streamBits);rate=\(effectiveRate);channels=2"
            : "audio/wav"
        let httpHeader = "HTTP/1.1 200 OK\r\nContent-Type: \(contentType)\r\ntransferMode.dlna.org: Streaming\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nAccept-Ranges: none\r\nCache-Control: no-cache, no-store\r\nConnection: close\r\n\r\n"
        var initData = Data(httpHeader.utf8)
        if !rawLPCM {
            let wavHeader = AudioProcessTapService.shared.makeWAVHeader(
                sampleRate: effectiveRate,
                bitDepth: streamBits,
                dataLength: AudioProcessTapService.unboundedWAVDataLength
            )
            initData.append(wavHeader)
        }

        NSLog("[WebSocketServer] 📻 Client connected to \(rawLPCM ? "/stream/live.pcm" : "/stream/live.wav") at \(effectiveRate) Hz, \(streamBits)-bit (subscriber: \(subscriberID))")
        if isAuthorizedDLNA {
            DLNADiscoveryManager.shared.noteDLNALiveStreamConnected(sid: streamInstanceID)
        }

        connection.send(content: initData, isComplete: false, completion: .contentProcessed({ [weak self] error in
            if let error = error {
                NSLog("[WebSocketServer] ❌ Failed to send live stream header: \(error)")
                self?.cleanupLiveAudioStream(subscriberID: subscriberID, streamState: streamState, streamInstanceID: isAuthorizedDLNA ? streamInstanceID : nil)
            }
        }))

        guard !streamState.isClosed else { return }

        AudioProcessTapService.shared.addSubscriber(id: subscriberID) { [weak self] chunk in
            guard let self = self, let conn = self.liveStreamConnection(id: subscriberID) else {
                AudioProcessTapService.shared.removeSubscriber(id: subscriberID)
                self?.removeLiveStreamConnection(id: subscriberID)
                return
            }
            guard streamState.tryAcquireSendSlot() else {
                if streamState.isClosed { return }
                let isPaused = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isUserPaused }
                    || DLNADiscoveryManager.shared.isRendererPausedOrStopped
                if isPaused {
                    // Streamer stopped reading TCP window while paused — drop zero-chunk without killing the connection!
                    return
                }
                NSLog("[WebSocketServer] ⚠️ Live stream backpressure exceeded (> 64 chunks); closing subscriber \(subscriberID)")
                self.cleanupLiveAudioStream(subscriberID: subscriberID, streamState: streamState, streamInstanceID: nil, wasBackpressureClose: true)
                return
            }
            let outboundChunk = rawLPCM
                ? Self.convertLittleEndianPCMToNetworkByteOrder(chunk, bitDepth: streamBits)
                : chunk
            conn.send(content: outboundChunk, isComplete: false, completion: .contentProcessed({ [weak self] error in
                streamState.releaseSendSlot()
                if let error = error {
                    if !streamState.isClosed {
                        NSLog("[WebSocketServer] ⚠️ Failed to send audio chunk: \(error). Closing stream.")
                    }
                    self?.cleanupLiveAudioStream(subscriberID: subscriberID, streamState: streamState, streamInstanceID: isAuthorizedDLNA ? streamInstanceID : nil)
                }
            }))
        }

        if streamState.isClosed {
            AudioProcessTapService.shared.removeSubscriber(id: subscriberID)
            removeLiveStreamConnection(id: subscriberID)
        }
    }

    internal func makeWAVHeader(sampleRate: Int = 44100, bitDepth: Int = 16, channels: Int = 1, dataSize: Int = 0x7FFFFFFF - 36) -> Data {
        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        let clampedDataSize = max(0, min(dataSize, 0x7FFFFFFF - 36))
        var chunkSize = UInt32(clampedDataSize + 36).littleEndian
        header.append(Data(bytes: &chunkSize, count: 4))
        header.append(contentsOf: "WAVEfmt ".utf8)
        var subchunk1Size = UInt32(16).littleEndian
        header.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat = UInt16(1).littleEndian
        header.append(Data(bytes: &audioFormat, count: 2))
        var numChannels = UInt16(channels).littleEndian
        header.append(Data(bytes: &numChannels, count: 2))
        var sRate = UInt32(sampleRate).littleEndian
        header.append(Data(bytes: &sRate, count: 4))
        var byteRate = UInt32(sampleRate * channels * bitDepth / 8).littleEndian
        header.append(Data(bytes: &byteRate, count: 4))
        var blockAlign = UInt16(channels * bitDepth / 8).littleEndian
        header.append(Data(bytes: &blockAlign, count: 2))
        var bits = UInt16(bitDepth).littleEndian
        header.append(Data(bytes: &bits, count: 2))
        header.append(contentsOf: "data".utf8)
        var subchunk2Size = UInt32(clampedDataSize).littleEndian
        header.append(Data(bytes: &subchunk2Size, count: 4))
        return header
    }
}
