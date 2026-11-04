//
//  WebSocketServer+HTTP.swift
//  AppleMusicRemoteMac
//

import Foundation
import Network

extension WebSocketServer {
    // MARK: - HTTP Request Handling & Media API

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

        if method == "OPTIONS" {
            sendCORSPreflight(connection: connection)
            return
        }

        if method == "GET" || method == "HEAD" {
            switch path {
            case "/", "/index.html":
                let content = loadWebAsset(filename: "index.html") ?? WebUIContent.indexHTML
                sendHTTPResponse(status: "200 OK", contentType: "text/html; charset=utf-8", body: Data(content.utf8), connection: connection, cacheSeconds: 0)
            case "/style.css":
                let content = loadWebAsset(filename: "style.css") ?? WebUIContent.styleCSS
                sendHTTPResponse(status: "200 OK", contentType: "text/css; charset=utf-8", body: Data(content.utf8), connection: connection, cacheSeconds: 0)
            case "/app.js":
                let content = loadWebAsset(filename: "app.js") ?? WebUIContent.appJS
                sendHTTPResponse(status: "200 OK", contentType: "application/javascript; charset=utf-8", body: Data(content.utf8), connection: connection, cacheSeconds: 0)
            case "/manifest.json":
                let content = loadWebAsset(filename: "manifest.json") ?? WebUIContent.manifestJSON
                sendHTTPResponse(status: "200 OK", contentType: "application/json; charset=utf-8", body: Data(content.utf8), connection: connection)
            case "/sw.js":
                let content = loadWebAsset(filename: "sw.js") ?? WebUIContent.swJS
                sendHTTPResponse(status: "200 OK", contentType: "application/javascript; charset=utf-8", body: Data(content.utf8), connection: connection, cacheSeconds: 0)
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
                let sub = String(p.dropFirst("/assets/".count))
                if let data = loadWebBinaryAsset(subpath: "assets/\(sub)") {
                    let cType: String
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
                    if let rangeHeader = extractHeader(named: "Range", from: headerString),
                       rangeHeader.hasPrefix("bytes=") {
                        let spec = String(rangeHeader.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        let parts = spec.components(separatedBy: "-")
                        if parts.count >= 2 {
                            let startStr = parts[0]
                            let endStr = parts[1]
                            let total = data.count
                            var start = Int(startStr) ?? 0
                            var end = endStr.isEmpty ? (total - 1) : (Int(endStr) ?? (total - 1))
                            if start < 0 { start = 0 }
                            if end >= total { end = total - 1 }
                            if start <= end && start < total {
                                let chunk = data.subdata(in: start..<(end + 1))
                                sendPartialHTTPResponse(contentType: cType, rangeStart: start, rangeEnd: end, totalLength: total, body: chunk, connection: connection, cacheSeconds: 86400 * 30)
                                return
                            }
                        }
                    }
                    sendHTTPResponse(status: "200 OK", contentType: cType, body: data, connection: connection, cacheSeconds: 86400 * 30)
                    return
                }
            case "/stream/live.wav", "/stream/live":
                if method == "HEAD" {
                    let headResp = "HTTP/1.1 200 OK\r\nContent-Type: audio/wav\r\nAccept-Ranges: none\r\nCache-Control: no-cache, no-store\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
                    connection.send(content: Data(headResp.utf8), completion: .contentProcessed({ [weak connection] _ in
                        connection?.cancel()
                    }))
                    return
                }
                handleLiveAudioStream(connection: connection, headerString: headerString, fullPath: fullPath)
                return
            case let p where p == "/api/artwork" || p == "/api/artwork.jpg" || p == "/artwork.jpg" || p.hasPrefix("/api/artwork.jpg?") || p.hasPrefix("/api/artwork?"):
                // 1. Try local track artwork from Music.app
                let artData = MusicBridge.shared.getCurrentTrackArtwork()
                if let art = artData, !art.isEmpty {
                    sendHTTPResponse(status: "200 OK", contentType: "image/jpeg", body: art, connection: connection, cacheSeconds: 0)
                    return
                }

                // 2. Try current player status track artworkUrl
                let curStatus = MusicBridge.shared.getPlayerStatus()
                let trackArt = curStatus.track?.artworkUrl ?? ""

                if !trackArt.isEmpty && (trackArt.hasPrefix("http://") || trackArt.hasPrefix("https://")) {
                    if let disk = ArtworkDiskCache.shared.get(key: trackArt) {
                        sendHTTPResponse(status: "200 OK", contentType: "image/jpeg", body: disk, connection: connection, cacheSeconds: 86400)
                        return
                    }
                    if let url = URL(string: trackArt) {
                        let req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 4.0)
                        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
                            guard let self = self else { return }
                            if let d = data, let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                                ArtworkDiskCache.shared.set(key: trackArt, data: d)
                                let mime = http.mimeType ?? "image/jpeg"
                                self.sendHTTPResponse(status: "200 OK", contentType: mime, body: d, connection: connection, cacheSeconds: 86400)
                            } else {
                                self.sendDefaultArtwork(connection: connection)
                            }
                        }.resume()
                        return
                    }
                }

                // 3. Check cached track artwork via MusicKit / Search
                let tName = curStatus.track?.name ?? ""
                let tArtist = curStatus.track?.artist ?? ""
                let tAlbum = curStatus.track?.album ?? ""
                if !tName.isEmpty, let cloudUrlStr = MusicKitManager.shared.getCachedTrackArtwork(name: tName, artist: tArtist, album: tAlbum),
                   !cloudUrlStr.isEmpty, let url = URL(string: cloudUrlStr) {
                    if let disk = ArtworkDiskCache.shared.get(key: cloudUrlStr) {
                        sendHTTPResponse(status: "200 OK", contentType: "image/jpeg", body: disk, connection: connection, cacheSeconds: 86400)
                        return
                    }
                    let req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 4.0)
                    URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
                        guard let self = self else { return }
                        if let d = data, let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                            ArtworkDiskCache.shared.set(key: cloudUrlStr, data: d)
                            let mime = http.mimeType ?? "image/jpeg"
                            self.sendHTTPResponse(status: "200 OK", contentType: mime, body: d, connection: connection, cacheSeconds: 86400)
                        } else {
                            self.sendDefaultArtwork(connection: connection)
                        }
                    }.resume()
                    return
                }

                sendDefaultArtwork(connection: connection)
            case let p where p.hasPrefix("/api/artwork/search"):
                var trackName = ""
                var trackArtist = ""
                var trackAlbum = ""
                if let qIdx = fullPath.firstIndex(of: "?") {
                    let qs = String(fullPath[fullPath.index(after: qIdx)...])
                    for pair in qs.components(separatedBy: "&") {
                        let parts = pair.components(separatedBy: "=")
                        if parts.count == 2 {
                            let val = parts[1].removingPercentEncoding ?? ""
                            if parts[0] == "name" { trackName = val }
                            else if parts[0] == "artist" { trackArtist = val }
                            else if parts[0] == "album" { trackAlbum = val }
                        }
                    }
                }
                let tName = trackName
                let tArtist = trackArtist
                let tAlbum = trackAlbum
                let lowName = tName.lowercased()
                if lowName.contains("моя станция") {
                    sendRedirect(location: "/assets/stations/CoverPersonal.png", connection: connection, cacheSeconds: 86400)
                    return
                } else if lowName.contains("станция открытий") {
                    sendRedirect(location: "/assets/stations/CoverDiscovery.png", connection: connection, cacheSeconds: 86400)
                    return
                } else if lowName.contains("сейчас на повторе") {
                    sendRedirect(location: "/assets/stations/CoverHeavyRotation.svg", connection: connection, cacheSeconds: 86400)
                    return
                } else if lowName.contains("apple music 1") {
                    sendRedirect(location: "/assets/stations/CoverAppleMusic1.png", connection: connection, cacheSeconds: 86400)
                    return
                }

                if let cached = MusicKitManager.shared.getCachedTrackArtwork(name: tName, artist: tArtist, album: tAlbum), !cached.isEmpty {
                    sendRedirect(location: cached, connection: connection, cacheSeconds: 86400)
                } else {
                    Task { [weak self] in
                        guard let self = self else { return }
                        if let cloudArt = await MusicKitManager.shared.searchTrackArtwork(name: tName, artist: tArtist, album: tAlbum) {
                            self.sendRedirect(location: cloudArt, connection: connection, cacheSeconds: 86400)
                        } else {
                            self.sendDefaultArtwork(connection: connection)
                        }
                    }
                }
            case let p where p.hasPrefix("/api/artwork/track"):
                var trackId = 0
                var paramName = ""
                var paramArtist = ""
                var paramAlbum = ""
                if let qIdx = fullPath.firstIndex(of: "?") {
                    let qs = String(fullPath[fullPath.index(after: qIdx)...])
                    for pair in qs.components(separatedBy: "&") {
                        let parts = pair.components(separatedBy: "=")
                        if parts.count == 2 {
                            let val = parts[1].removingPercentEncoding ?? ""
                            if parts[0] == "id" { trackId = Int(val) ?? 0 }
                            else if parts[0] == "name" { paramName = val }
                            else if parts[0] == "artist" { paramArtist = val }
                            else if parts[0] == "album" { paramAlbum = val }
                        }
                    }
                }
                if trackId > 0, let art = MusicBridge.shared.getTrackArtwork(id: trackId), !art.isEmpty {
                    sendHTTPResponse(status: "200 OK", contentType: "image/jpeg", body: art, connection: connection, cacheSeconds: 86400)
                } else {
                    let meta = (trackId > 0) ? MusicBridge.shared.getTrackMetadata(id: trackId) : nil
                    let effName = !paramName.isEmpty ? paramName : (meta?.name ?? "")
                    let effArtist = !paramArtist.isEmpty ? paramArtist : (meta?.artist ?? "")
                    let effAlbum = !paramAlbum.isEmpty ? paramAlbum : (meta?.album ?? "")

                    if !effName.isEmpty {
                        if let cached = MusicKitManager.shared.getCachedTrackArtwork(name: effName, artist: effArtist, album: effAlbum), !cached.isEmpty {
                            sendRedirect(location: cached, connection: connection, cacheSeconds: 86400)
                        } else {
                            Task { [weak self] in
                                guard let self = self else { return }
                                if let cloudArt = await MusicKitManager.shared.searchTrackArtwork(name: effName, artist: effArtist, album: effAlbum) {
                                    self.sendRedirect(location: cloudArt, connection: connection, cacheSeconds: 86400)
                                } else {
                                    self.sendDefaultArtwork(connection: connection)
                                }
                            }
                        }
                    } else {
                        sendDefaultArtwork(connection: connection)
                    }
                }
            case let p where p.hasPrefix("/api/artwork/playlist"):
                var plName = ""
                if let components = URLComponents(string: fullPath),
                   let nameItem = components.queryItems?.first(where: { $0.name == "name" })?.value {
                    plName = nameItem
                } else if let qIdx = fullPath.firstIndex(of: "?") {
                    let qs = String(fullPath[fullPath.index(after: qIdx)...])
                    for pair in qs.components(separatedBy: "&") {
                        let parts = pair.components(separatedBy: "=")
                        if parts.count == 2 && parts[0] == "name" {
                            plName = parts[1].removingPercentEncoding ?? parts[1]
                        }
                    }
                }
                let targetPlName = plName
                if !targetPlName.isEmpty, let art = MusicBridge.shared.getPlaylistArtwork(name: targetPlName), !art.isEmpty {
                    sendHTTPResponse(status: "200 OK", contentType: "image/jpeg", body: art, connection: connection, cacheSeconds: 86400)
                } else if !targetPlName.isEmpty {
                    Task { [weak self] in
                        guard let self = self else { return }
                        var cloudArtUrl = await MusicKitManager.shared.searchPlaylistArtwork(name: targetPlName, storefront: "ru")
                        if cloudArtUrl == nil || cloudArtUrl?.isEmpty == true {
                            cloudArtUrl = await MusicKitManager.shared.searchPlaylistArtwork(name: targetPlName, storefront: "us")
                        }
                        if let artUrl = cloudArtUrl, !artUrl.isEmpty {
                            self.sendRedirect(location: artUrl, connection: connection, cacheSeconds: 86400)
                            return
                        }
                        self.sendDefaultArtwork(connection: connection)
                    }
                } else {
                    sendDefaultArtwork(connection: connection)
                }
            case let p where p.hasPrefix("/api/artwork/motion.mp4"):
                var hashParam = ""
                if let components = URLComponents(string: fullPath),
                   let hVal = components.queryItems?.first(where: { $0.name == "hash" })?.value {
                    hashParam = hVal
                } else if let qIdx = fullPath.firstIndex(of: "?") {
                    let qs = String(fullPath[fullPath.index(after: qIdx)...])
                    for pair in qs.components(separatedBy: "&") {
                        let parts = pair.components(separatedBy: "=")
                        if parts.count == 2 && parts[0] == "hash" {
                            hashParam = parts[1].removingPercentEncoding ?? parts[1]
                        }
                    }
                }
                guard let data = MotionArtworkDiskCache.shared.getVideoData(forHash: hashParam), !data.isEmpty else {
                    sendHTTPResponse(status: "404 Not Found", contentType: "text/plain", body: Data("Not Found".utf8), connection: connection)
                    return
                }
                if method == "HEAD" {
                    let headResp = "HTTP/1.1 200 OK\r\nContent-Type: video/mp4\r\nContent-Length: \(data.count)\r\nAccept-Ranges: bytes\r\nCache-Control: public, max-age=604800\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
                    connection.send(content: Data(headResp.utf8), completion: .contentProcessed({ [weak connection] _ in
                        connection?.cancel()
                    }))
                    return
                }
                if let rangeHeader = extractHeader(named: "Range", from: headerString),
                   rangeHeader.hasPrefix("bytes=") {
                    let spec = String(rangeHeader.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                    let parts = spec.components(separatedBy: "-")
                    if parts.count >= 2 {
                        let startStr = parts[0]
                        let endStr = parts[1]
                        let total = data.count
                        var start = Int(startStr) ?? 0
                        var end = endStr.isEmpty ? (total - 1) : (Int(endStr) ?? (total - 1))
                        if start < 0 { start = 0 }
                        if end >= total { end = total - 1 }
                        if start <= end && start < total {
                            let chunk = data.subdata(in: start..<(end + 1))
                            sendPartialHTTPResponse(contentType: "video/mp4", rangeStart: start, rangeEnd: end, totalLength: total, body: chunk, connection: connection, cacheSeconds: 86400 * 7)
                            return
                        }
                    }
                }
                sendHTTPResponse(status: "200 OK", contentType: "video/mp4", body: data, connection: connection, cacheSeconds: 86400 * 7)
                return
            case "/api/status":
                let status = MusicBridge.shared.getPlayerStatus()
                if let data = try? JSONEncoder().encode(status) {
                    sendHTTPResponse(status: "200 OK", contentType: "application/json; charset=utf-8", body: data, connection: connection)
                } else {
                    sendHTTPResponse(status: "500 Internal Server Error", contentType: "text/plain", body: Data("{}".utf8), connection: connection)
                }
            case let p where p.hasPrefix("/api/duck"):
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

            case "/api/unduck":
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

            default:
                sendHTTPResponse(status: "404 Not Found", contentType: "text/plain", body: Data("Not Found".utf8), connection: connection)
            }
        } else if method == "POST" && (path == "/api/duck" || path == "/api/unduck") {
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
        } else if method == "POST" && path == "/api/media" {
            Task {
                await handleMediaAPI(bodyData: bodyData, connection: connection)
            }
        } else {
            sendHTTPResponse(status: "404 Not Found", contentType: "text/plain", body: Data("Not Found".utf8), connection: connection)
        }
    }

    private func handleMediaAPI(bodyData: Data, connection: NWConnection) async {
        guard let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any],
              let endpoint = (json["endpoint"] as? String)?.lowercased() else {
            let errResp: [String: Any] = ["status": "error", "message": "Missing endpoint in JSON payload"]
            let data = (try? JSONSerialization.data(withJSONObject: errResp)) ?? Data()
            sendHTTPResponse(status: "400 Bad Request", contentType: "application/json; charset=utf-8", body: data, connection: connection)
            return
        }

        let params = (json["params"] as? [String: Any]) ?? [:]
        let bridge = MusicBridge.shared
        var resultData: [String: Any] = ["status": "ok", "endpoint": endpoint]

        switch endpoint {
        case "play":
            let ok = bridge.play()
            var status = PlayerStatusEngine.shared.getPlayerStatus()
            status.playerState = "playing"
            if DLNADiscoveryManager.shared.hasActiveRenderer {
                DLNADiscoveryManager.shared.play()
            }
            broadcastStatus(status: status, includeQueue: false)
            resultData["success"] = ok

        case "pause":
            let ok = bridge.pause()
            var status = PlayerStatusEngine.shared.getPlayerStatus()
            status.playerState = "paused"
            if DLNADiscoveryManager.shared.hasActiveRenderer {
                DLNADiscoveryManager.shared.pause()
            }
            broadcastStatus(status: status, includeQueue: false)
            resultData["success"] = ok

        case "play_pause":
            let ok = bridge.playPause()
            resultData["success"] = ok
            if DLNADiscoveryManager.shared.hasActiveRenderer {
                let st = PlayerStatusEngine.shared.getPlayerStatus()
                if st.isPlaying {
                    DLNADiscoveryManager.shared.play()
                } else {
                    DLNADiscoveryManager.shared.pause()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.broadcastStatus(includeQueue: false)
            }

        case "next":
            let ok = bridge.nextTrack()
            resultData["success"] = ok
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.broadcastStatus(includeQueue: true)
            }

        case "previous":
            let ok = bridge.previousTrack()
            resultData["success"] = ok
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.broadcastStatus(includeQueue: true)
            }

        case "stop":
            let ok = bridge.stop()
            resultData["success"] = ok
            if DLNADiscoveryManager.shared.hasActiveRenderer {
                DLNADiscoveryManager.shared.stop()
            }
            broadcastStatus(includeQueue: false)

        case "set_volume":
            var vol = 100
            if let num = params["volume"] as? NSNumber {
                vol = num.intValue
            } else if let num = params["volume"] as? Int {
                vol = num
            }
            vol = max(0, min(100, vol))
            let ok = bridge.setVolume(vol)
            resultData["success"] = ok
            resultData["volume"] = vol
        case "set_lock_volume_100", "lock_volume_100":
            let enabled = (params["enabled"] as? Bool) ?? (params["lock"] as? Bool) ?? (params["lock_volume_100"] as? Bool) ?? true
            PlaybackStateStore.shared.isVolumeLockedTo100 = enabled
            if enabled {
                _ = bridge.setVolume(100)
            }
            resultData["success"] = true
            resultData["lock_volume_100"] = enabled
            broadcastStatus(includeQueue: false)

        case "duck", "activate_ducking":
            let reduction = (params["reduction"] as? Double) ?? ((params["reduction"] as? NSNumber)?.doubleValue) ?? (params["percent"] as? Double) ?? ((params["percent"] as? NSNumber)?.doubleValue) ?? 80.0
            let timeout = (params["timeout"] as? Double) ?? ((params["timeout"] as? NSNumber)?.doubleValue) ?? (params["duration"] as? Double) ?? ((params["duration"] as? NSNumber)?.doubleValue)
            let res = bridge.activateDucking(reductionPercent: reduction, timeout: timeout)
            resultData["success"] = true
            resultData["is_ducked"] = true
            resultData["original_volume"] = res.originalVolume
            resultData["ducked_volume"] = res.duckedVolume
            resultData["volume"] = res.duckedVolume
            broadcastStatus(includeQueue: false)

        case "unduck", "deactivate_ducking":
            let res = bridge.deactivateDucking()
            resultData["success"] = true
            resultData["is_ducked"] = false
            resultData["restored_volume"] = res.restoredVolume
            resultData["volume"] = res.restoredVolume
            broadcastStatus(includeQueue: false)

        case "set_ducking", "ducking":
            let enabled = (params["enabled"] as? Bool) ?? (params["active"] as? Bool) ?? true
            if enabled {
                let reduction = (params["reduction"] as? Double) ?? ((params["reduction"] as? NSNumber)?.doubleValue) ?? (params["percent"] as? Double) ?? ((params["percent"] as? NSNumber)?.doubleValue) ?? 80.0
                let timeout = (params["timeout"] as? Double) ?? ((params["timeout"] as? NSNumber)?.doubleValue) ?? (params["duration"] as? Double) ?? ((params["duration"] as? NSNumber)?.doubleValue)
                let res = bridge.activateDucking(reductionPercent: reduction, timeout: timeout)
                resultData["success"] = true
                resultData["is_ducked"] = true
                resultData["original_volume"] = res.originalVolume
                resultData["ducked_volume"] = res.duckedVolume
                resultData["volume"] = res.duckedVolume
            } else {
                let res = bridge.deactivateDucking()
                resultData["success"] = true
                resultData["is_ducked"] = false
                resultData["restored_volume"] = res.restoredVolume
                resultData["volume"] = res.restoredVolume
            }
            broadcastStatus(includeQueue: false)

        case "search_and_play":
            let query = (params["query"] as? String) ?? (params["q"] as? String) ?? ""
            let res = await bridge.searchAndPlayDetailed(query: query)
            resultData["success"] = res.success
            if let st = res.station {
                resultData["station"] = st
                resultData["mode"] = "random_station"
            }
            if let q = res.query {
                resultData["query"] = q
                resultData["mode"] = "search"
                if let cnt = res.count {
                    resultData["count"] = cnt
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.broadcastStatus(includeQueue: true)
            }

        case "status":
            let status = bridge.getPlayerStatus()
            if let enc = try? JSONEncoder().encode(status),
               let dict = try? JSONSerialization.jsonObject(with: enc) as? [String: Any] {
                resultData["data"] = dict
            }

        case "play_playlist":
            let plName = (params["playlist"] as? String) ?? (params["name"] as? String) ?? "Музыка"
            let trackId = (params["track_id"] as? Int) ?? Int((params["track_id"] as? String) ?? "")
            let trackIndex = (params["track_index"] as? Int) ?? (params["trackIndex"] as? Int) ?? Int((params["track_index"] as? String) ?? "")
            let shuffle = (params["shuffle"] as? Bool) ?? false
            let ok = bridge.playPlaylist(name: plName, trackId: trackId, trackIndex: trackIndex, shuffle: shuffle)
            resultData["success"] = ok
            resultData["playlist"] = plName
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.broadcastStatus(includeQueue: true)
            }

        case "play_queue_index", "queue_play_index":
            let idx = (params["index"] as? Int) ?? 0
            let ok = await bridge.playQueueIndex(idx)
            resultData["success"] = ok
            resultData["index"] = idx
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.broadcastStatus(includeQueue: true)
            }

        case "queue":
            let queue = await bridge.getPlaybackQueue()
            if let enc = try? JSONEncoder().encode(queue),
               let dict = try? JSONSerialization.jsonObject(with: enc) as? [String: Any] {
                resultData["data"] = dict
            }

        case "search":
            let query = (params["query"] as? String) ?? (params["q"] as? String) ?? ""
            let country = (params["country"] as? String) ?? "ru"
            let source = (params["scope"] as? String) ?? (params["source"] as? String) ?? "all"
            let results = await CloudCatalogService.shared.search(query: query, country: country, source: source)
            if let enc = try? JSONEncoder().encode(results),
               let obj = try? JSONSerialization.jsonObject(with: enc) as? [String: Any] {
                resultData["data"] = obj
            }
            resultData["success"] = true

        case "play_cloud":
            let url = params["url"] as? String
            let storeId = params["id"] as? String
            let name = (params["name"] as? String) ?? (params["title"] as? String) ?? ""
            let artist = (params["artist"] as? String) ?? ""
            let numericId = (params["numeric_id"] as? Int) ?? (params["numericId"] as? Int)
            let isLocal = (params["is_local"] as? Bool) ?? (params["isLocal"] as? Bool)
            let type = (params["type"] as? String)?.lowercased()
            let shuffle = (params["shuffle"] as? Bool) ?? false
            var isAlbum = (type == "album")
            var albumId = storeId ?? ""
            if !isAlbum, let u = url, u.contains("/album/"), !u.contains("?i="), !u.contains("/song/") {
                isAlbum = true
                if albumId.isEmpty {
                    let clean = u.components(separatedBy: "?").first ?? u
                    if let lastSegment = clean.split(separator: "/").last, !lastSegment.isEmpty {
                        albumId = String(lastSegment)
                    }
                }
            }
            let ok: Bool
            if isAlbum && !albumId.isEmpty {
                ok = await bridge.playAlbum(id: albumId, name: name, artist: artist, shuffle: shuffle)
            } else {
                ok = await bridge.playCloud(url: url, id: storeId, name: name, artist: artist, numericId: numericId, isLocal: isLocal)
            }
            resultData["success"] = ok
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.broadcastStatus(includeQueue: true)
            }

        case "play_station":
            let name = (params["name"] as? String) ?? "Radio"
            let url = (params["url"] as? String) ?? ""
            let type = (params["type"] as? String) ?? ""
            let trackTitle = (params["title"] as? String) ?? (params["track"] as? String) ?? ""
            let artistName = (params["artist"] as? String) ?? ""
            let ok = await bridge.playStation(url: url, name: name, type: type, trackTitle: trackTitle, artistName: artistName)
            resultData["success"] = ok
            resultData["name"] = name
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.broadcastStatus(includeQueue: true)
            }

        case "get_account_status", "account_health":
            let force = (params["refresh"] as? Bool) ?? false
            let health = await AccountHealthService.shared.checkAccountHealth(forceRefresh: force)
            if let enc = try? JSONEncoder().encode(health),
               let dict = try? JSONSerialization.jsonObject(with: enc) as? [String: Any] {
                resultData["data"] = dict
            }
            resultData["success"] = true

        default:
            resultData = ["status": "error", "message": "Unknown endpoint: \(endpoint)"]
        }

        var respData = Data("{\"status\":\"ok\"}".utf8)
        if JSONSerialization.isValidJSONObject(resultData), let data = try? JSONSerialization.data(withJSONObject: resultData) {
            respData = data
        } else {
            let safeMap: [String: Any] = [
                "status": resultData["status"] as? String ?? "ok",
                "endpoint": resultData["endpoint"] as? String ?? endpoint,
                "success": (resultData["success"] as? Bool) ?? true
            ]
            if let data = try? JSONSerialization.data(withJSONObject: safeMap) {
                respData = data
            }
        }
        sendHTTPResponse(status: "200 OK", contentType: "application/json; charset=utf-8", body: respData, connection: connection)
    }

    private func handleLiveAudioStream(connection: NWConnection, headerString: String, fullPath: String) {
        let subscriberID = UUID()
        liveStreamLock.lock()
        liveStreamConnections[subscriberID] = connection
        liveStreamLock.unlock()

        var requestedRate: Int? = nil
        var requestedBits: Int? = nil
        if let qIdx = fullPath.firstIndex(of: "?") {
            let qs = String(fullPath[fullPath.index(after: qIdx)...])
            for pair in qs.components(separatedBy: "&") {
                let parts = pair.components(separatedBy: "=")
                if parts.count == 2 {
                    if parts[0] == "rate", let r = Int(parts[1]), r > 0 {
                        requestedRate = r
                    } else if (parts[0] == "bits" || parts[0] == "depth"), let b = Int(parts[1]), (b == 16 || b == 24) {
                        requestedBits = b
                    }
                }
            }
        }

        let detectedDepth = BitPerfectLogMonitor.shared.currentDetectedBitDepth
        let effectiveRate = requestedRate ?? AudioProcessTapService.shared.sampleRate
        let effectiveBits = requestedBits ?? detectedDepth ?? (effectiveRate >= 48000 ? 24 : 16)

        AudioProcessTapService.shared.setFormat(sampleRate: effectiveRate, bitDepth: effectiveBits)

        let httpHeader = "HTTP/1.1 200 OK\r\nContent-Type: audio/wav\r\nAccept-Ranges: none\r\nCache-Control: no-cache, no-store\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"

        let wavHeader = AudioProcessTapService.shared.makeWAVHeader(sampleRate: effectiveRate, bitDepth: effectiveBits)
        var initData = Data(httpHeader.utf8)
        initData.append(wavHeader)

        NSLog("[WebSocketServer] 📻 Client connected to /stream/live.wav at \(effectiveRate) Hz, \(effectiveBits)-bit (subscriber: \(subscriberID))")

        connection.send(content: initData, isComplete: false, completion: .contentProcessed({ error in
            if let error = error {
                NSLog("[WebSocketServer] ❌ Failed to send live stream header: \(error)")
                connection.cancel()
                return
            }
        }))

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                NSLog("[WebSocketServer] 🔌 Live stream client disconnected (subscriber: \(subscriberID))")
                AudioProcessTapService.shared.removeSubscriber(id: subscriberID)
                self?.liveStreamLock.lock()
                self?.liveStreamConnections.removeValue(forKey: subscriberID)
                self?.liveStreamLock.unlock()
            default:
                break
            }
        }

        AudioProcessTapService.shared.addSubscriber(id: subscriberID) { [weak connection] chunk in
            guard let conn = connection else { return }
            conn.send(content: chunk, isComplete: false, completion: .contentProcessed({ [weak conn] error in
                if let error = error {
                    NSLog("[WebSocketServer] ⚠️ Failed to send audio chunk: \(error). Closing stream.")
                    AudioProcessTapService.shared.removeSubscriber(id: subscriberID)
                    conn?.cancel()
                }
            }))
        }
    }

    private func makeWAVHeader(sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        var chunkSize: UInt32 = 0x7FFFFFFF
        header.append(Data(bytes: &chunkSize, count: 4))
        header.append(contentsOf: "WAVEfmt ".utf8)
        var subchunk1Size: UInt32 = 16
        header.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat: UInt16 = 1
        header.append(Data(bytes: &audioFormat, count: 2))
        var numChannels = UInt16(channels)
        header.append(Data(bytes: &numChannels, count: 2))
        var sRate = UInt32(sampleRate)
        header.append(Data(bytes: &sRate, count: 4))
        var byteRate = UInt32(sampleRate * channels * bitsPerSample / 8)
        header.append(Data(bytes: &byteRate, count: 4))
        var blockAlign = UInt16(channels * bitsPerSample / 8)
        header.append(Data(bytes: &blockAlign, count: 2))
        var bits = UInt16(bitsPerSample)
        header.append(Data(bytes: &bits, count: 2))
        header.append(contentsOf: "data".utf8)
        var dataSize: UInt32 = 0x7FFFFFFF - 36
        header.append(Data(bytes: &dataSize, count: 4))
        return header
    }

    private func sendHTTPResponse(status: String, contentType: String, body: Data, connection: NWConnection, cacheSeconds: Int = 0) {
        var header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nAccept-Ranges: bytes\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS, HEAD\r\nAccess-Control-Allow-Headers: Range, Content-Type\r\nConnection: close\r\n"
        if cacheSeconds > 0 {
            header += "Cache-Control: public, max-age=\(cacheSeconds)\r\n"
        } else {
            header += "Cache-Control: no-cache\r\n"
        }
        header += "\r\n"
        var respData = Data(header.utf8)
        respData.append(body)
        connection.send(content: respData, completion: .contentProcessed({ [weak connection] _ in
            connection?.cancel()
        }))
    }

    private func sendPartialHTTPResponse(contentType: String, rangeStart: Int, rangeEnd: Int, totalLength: Int, body: Data, connection: NWConnection, cacheSeconds: Int = 2592000) {
        var header = "HTTP/1.1 206 Partial Content\r\nContent-Type: \(contentType)\r\nContent-Range: bytes \(rangeStart)-\(rangeEnd)/\(totalLength)\r\nContent-Length: \(body.count)\r\nAccept-Ranges: bytes\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, HEAD, OPTIONS\r\nAccess-Control-Allow-Headers: Range, Content-Type\r\n"
        if cacheSeconds > 0 {
            header += "Cache-Control: public, max-age=\(cacheSeconds)\r\n"
        } else {
            header += "Cache-Control: no-cache\r\n"
        }
        header += "Connection: close\r\n\r\n"
        var respData = Data(header.utf8)
        respData.append(body)
        connection.send(content: respData, completion: .contentProcessed({ [weak connection] _ in
            connection?.cancel()
        }))
    }

    private func sendDefaultArtwork(connection: NWConnection) {
        if let pngData = loadWebBinaryAsset(subpath: "apple-touch-icon-512.png") ?? loadWebBinaryAsset(subpath: "apple-touch-icon.png") {
            sendHTTPResponse(status: "200 OK", contentType: "image/png", body: pngData, connection: connection, cacheSeconds: 0)
        } else {
            let fallback = loadWebAsset(filename: "apple-touch-icon.svg") ?? WebUIContent.appleTouchIconSVG
            sendHTTPResponse(status: "200 OK", contentType: "image/svg+xml; charset=utf-8", body: Data(fallback.utf8), connection: connection, cacheSeconds: 0)
        }
    }

    private func sendCORSPreflight(connection: NWConnection) {
        let header = "HTTP/1.1 204 No Content\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed({ [weak connection] _ in
            connection?.cancel()
        }))
    }

    private func sendRedirect(location: String, connection: NWConnection, cacheSeconds: Int = 0) {
        let safeLocation = location.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        var header = "HTTP/1.1 302 Found\r\nLocation: \(safeLocation)\r\nContent-Length: 0\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n"
        if cacheSeconds > 0 {
            header += "Cache-Control: public, max-age=\(cacheSeconds)\r\n"
        } else {
            header += "Cache-Control: no-cache, no-store, must-revalidate\r\n"
        }
        header += "\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed({ [weak connection] _ in
            connection?.cancel()
        }))
    }

    internal func loadWebAsset(filename: String) -> String? {
        let currentDir = FileManager.default.currentDirectoryPath
        let thisFile = URL(fileURLWithPath: #filePath)
        let rootMac = thisFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

        var candidates: [String] = []
        if let resourcePath = Bundle.main.resourcePath {
            candidates.append((resourcePath as NSString).appendingPathComponent("Web/\(filename)"))
        }
        candidates.append((currentDir as NSString).appendingPathComponent("AppleMusicRemoteMac/Web/\(filename)"))
        candidates.append((currentDir as NSString).appendingPathComponent("Web/\(filename)"))
        candidates.append(((currentDir as NSString).appendingPathComponent("..") as NSString).appendingPathComponent("AppleMusicRemoteMac/Web/\(filename)"))
        candidates.append(rootMac.appendingPathComponent("Web/\(filename)").path)
        candidates.append(rootMac.appendingPathComponent("AppleMusicRemoteMac/Web/\(filename)").path)
        candidates.append("/Users/kirill/Documents/projects/amr/AppleMusicRemoteMac/Web/\(filename)")

        for path in candidates {
            if FileManager.default.fileExists(atPath: path),
               let content = try? String(contentsOfFile: path, encoding: .utf8) {
                return content
            }
        }

        // Fallback to embedded WebUIContent for known core assets
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
        let currentDir = FileManager.default.currentDirectoryPath
        let thisFile = URL(fileURLWithPath: #filePath)
        let rootMac = thisFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

        var candidates: [String] = []
        if let resourcePath = Bundle.main.resourcePath {
            candidates.append((resourcePath as NSString).appendingPathComponent("Web/\(subpath)"))
        }
        candidates.append((currentDir as NSString).appendingPathComponent("AppleMusicRemoteMac/Web/\(subpath)"))
        candidates.append((currentDir as NSString).appendingPathComponent("Web/\(subpath)"))
        candidates.append(((currentDir as NSString).appendingPathComponent("..") as NSString).appendingPathComponent("AppleMusicRemoteMac/Web/\(subpath)"))
        candidates.append(rootMac.appendingPathComponent("Web/\(subpath)").path)
        candidates.append(rootMac.appendingPathComponent("AppleMusicRemoteMac/Web/\(subpath)").path)
        candidates.append("/Users/kirill/Documents/projects/amr/AppleMusicRemoteMac/Web/\(subpath)")

        for path in candidates {
            if FileManager.default.fileExists(atPath: path),
               let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                return data
            }
        }
        return nil
    }
}
