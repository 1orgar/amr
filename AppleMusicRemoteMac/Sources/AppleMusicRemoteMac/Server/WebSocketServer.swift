//
//  WebSocketServer.swift
//  AppleMusicRemoteMac
//
//  Pure Swift WebSocket Server using Network.framework (NWListener + NWProtocolWebSocket)
//

import AppKit
import CoreAudio
import CryptoKit
import Foundation
import Network

public protocol WebSocketServerDelegate: AnyObject, Sendable {
    func webSocketServer(_ server: WebSocketServer, didUpdateClientCount count: Int)
    func webSocketServer(_ server: WebSocketServer, didChangeState state: NWListener.State)
}

public final class WebSocketServer: @unchecked Sendable {
    public static let shared = WebSocketServer()

    public weak var delegate: WebSocketServerDelegate?

    private var listener: NWListener?
    private var clients: [UUID: NWConnection] = [:]
    private var liveStreamConnections: [UUID: NWConnection] = [:]
    private let liveStreamLock = NSLock()
    private let clientLock = NSRecursiveLock()
    private let sendLock = NSRecursiveLock()
    private var isRunning = false
    public private(set) var port: Int = 8080

    public func closeLiveStreamConnections() {
        liveStreamLock.lock()
        let conns = Array(liveStreamConnections.values)
        liveStreamConnections.removeAll()
        liveStreamLock.unlock()
        for conn in conns {
            conn.cancel()
        }
        NSLog("[WebSocketServer] 🔌 Closed %d active live audio stream connection(s).", conns.count)
    }

    private var pollerTimer: DispatchSourceTimer?
    private var lastKnownState: String = ""
    private var lastKnownPosition: Double = 0
    private var lastKnownTrackId: String = ""
    private var lastBroadcastTime: Date = Date.distantPast
    private var observersSetup = false

    private init() {
        setupDistributedNotifications()
    }

    private let notifQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.amr.notifications"
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private var notifDebounceItem: DispatchWorkItem?

    private func setupDistributedNotifications() {
        guard !observersSetup else { return }
        observersSetup = true

        let handler: (Notification) -> Void = { [weak self] notif in
            guard let self = self else { return }
            BitPerfectLogMonitor.shared.resetTrackState()
            QueueManager.shared.handleTrackNotification(userInfo: notif.userInfo)
            self.notifDebounceItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.lastPlayerStatusCache = nil
                }
                self.broadcastStatus(includeQueue: true)
            }
            self.notifDebounceItem = work
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2, execute: work)
        }

        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.Music.playerInfo"), object: nil, queue: notifQueue, using: handler)
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.iTunes.playerInfo"), object: nil, queue: notifQueue, using: handler)

        CoreAudioDeviceManager.shared.onDevicesChanged = { [weak self] devices in
            guard let self = self else { return }
            let devList = devices.map { $0.dictionary }
            self.broadcastEvent(name: "audio_devices_changed", data: ["devices": devList])
            self.broadcastStatus(includeQueue: false)
        }

        CoreAudioDeviceManager.shared.onSampleRateChanged = { [weak self] _, _ in
            guard let self = self else { return }
            self.broadcastStatus(includeQueue: false)
        }

        MusicAppLifecycleManager.shared.onStateChanged = { [weak self] event in
            guard let self = self else { return }
            self.broadcastEvent(name: "music_app_lifecycle", data: [
                "state": event.state.rawValue,
                "reason": event.reason,
                "is_healthy": event.isHealthy,
                "restart_count": event.restartCount,
                "cooldown_remaining": event.cooldownRemaining
            ])
            if event.state == .running {
                self.broadcastStatus(includeQueue: true)
            }
        }
    }

    // MARK: - Server Lifecycle

    public func start(port: Int = 8080) -> Bool {
        setupDistributedNotifications()
        clientLock.lock()
        defer { clientLock.unlock() }

        stopUnlocked()

        self.port = port

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 10

        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.allowLocalEndpointReuse = true

        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            NSLog("[Server] Invalid port: %d", port)
            return false
        }

        do {
            let nwListener = try NWListener(using: params, on: endpointPort)
            self.listener = nwListener

            nwListener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                NSLog("[Server] Listener state: \(state)")
                self.delegate?.webSocketServer(self, didChangeState: state)
            }

            nwListener.newConnectionHandler = { [weak self] connection in
                guard let self = self else { return }
                self.handleNewConnection(connection)
            }

            let queue = DispatchQueue(label: "com.amr.server", qos: .userInteractive)
            nwListener.start(queue: queue)
            self.isRunning = true

            startPollerTimer()

            // Start Bonjour Advertising
            BonjourAdvertiser.shared.startAdvertising(port: port)

            NSLog("[Server] Pure Swift HTTP & WebSocket Server listening on port %d", port)
            return true
        } catch {
            NSLog("[Server] Failed to start listener on port %d: %@", port, error.localizedDescription)
            return false
        }
    }

    public func stop() {
        clientLock.lock()
        defer { clientLock.unlock() }
        stopUnlocked()
    }

    private func stopUnlocked() {
        stopPollerTimer()
        BonjourAdvertiser.shared.stopAdvertising()

        if let l = listener {
            l.cancel()
            self.listener = nil
        }

        for (_, conn) in clients {
            conn.cancel()
        }
        clients.removeAll()
        isRunning = false
        delegate?.webSocketServer(self, didUpdateClientCount: 0)
    }

    public var clientCount: Int {
        clientLock.lock()
        defer { clientLock.unlock() }
        return clients.count
    }

    // MARK: - Connection & Protocol Handling

    private func handleNewConnection(_ connection: NWConnection) {
        let clientId = UUID()

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let conn = connection else { return }
            switch state {
            case .ready:
                self.readInitialConnection(clientId: clientId, connection: conn, buffer: Data())
            case .failed(let err):
                NSLog("[Server] Client connection failed: %@", err.localizedDescription)
                self.removeClient(clientId: clientId)
            case .cancelled:
                self.removeClient(clientId: clientId)
            default:
                break
            }
        }

        let queue = DispatchQueue(label: "com.amr.server.client.\(clientId.uuidString)", qos: .userInteractive)
        connection.start(queue: queue)
    }

    private func removeClient(clientId: UUID) {
        clientLock.lock()
        guard let conn = clients.removeValue(forKey: clientId) else {
            clientLock.unlock()
            return
        }
        let count = clients.count
        clientLock.unlock()

        conn.cancel()
        NSLog("[WebSocket] Client disconnected. Total clients: %d", count)
        delegate?.webSocketServer(self, didUpdateClientCount: count)
    }

    private func readInitialConnection(clientId: UUID, connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] content, _, isComplete, error in
            guard let self = self, let conn = connection else { return }
            if let error = error {
                NSLog("[Server] Initial receive error: %@", error.localizedDescription)
                self.removeClient(clientId: clientId)
                return
            }

            var current = buffer
            if let data = content {
                current.append(data)
            }

            var delimiterRange: Range<Data.Index>?
            if let r = current.range(of: Data("\r\n\r\n".utf8)) {
                delimiterRange = r
            } else if let r = current.range(of: Data("\n\n".utf8)) {
                delimiterRange = r
            }

            guard let delim = delimiterRange else {
                if isComplete {
                    conn.cancel()
                    return
                }
                self.readInitialConnection(clientId: clientId, connection: conn, buffer: current)
                return
            }

            let headerData = current.subdata(in: current.startIndex..<delim.lowerBound)
            let restData = current.subdata(in: delim.upperBound..<current.endIndex)
            guard let headerString = String(data: headerData, encoding: .utf8) else {
                conn.cancel()
                return
            }

            let isWSUpgrade = (self.extractHeader(named: "upgrade", from: headerString)?.lowercased().contains("websocket") == true)
            if isWSUpgrade, let key = self.extractHeader(named: "sec-websocket-key", from: headerString) {
                let accept = self.webSocketAccept(for: key)
                let response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
                conn.send(content: Data(response.utf8), completion: .contentProcessed({ [weak self, weak conn] _ in
                    guard let self = self, let c = conn else { return }
                    self.clientLock.lock()
                    self.clients[clientId] = c
                    let count = self.clients.count
                    self.clientLock.unlock()

                    NSLog("[WebSocket] Handshake complete. Total WebSocket clients: %d", count)
                    self.delegate?.webSocketServer(self, didUpdateClientCount: count)

                    let status = MusicBridge.shared.getPlayerStatus()
                    self.sendEvent("player_state_changed", data: status, to: c)
                    Task {
                        let queue = await MusicBridge.shared.getPlaybackQueue()
                        self.sendEvent("queue", data: queue, to: c)
                    }

                    self.readWebSocketFrames(clientId: clientId, connection: c, buffer: restData)
                }))
                return
            }

            // Normal HTTP request
            var expectedBodyLen = 0
            if let clStr = self.extractHeader(named: "content-length", from: headerString), let cl = Int(clStr) {
                expectedBodyLen = cl
            }

            if restData.count < expectedBodyLen {
                self.readRemainingHTTPBody(clientId: clientId, connection: conn, headerString: headerString, buffer: restData, expectedLen: expectedBodyLen)
            } else {
                self.handleHTTPRequest(headerString: headerString, bodyData: restData.prefix(expectedBodyLen), connection: conn)
            }
        }
    }

    private func readRemainingHTTPBody(clientId: UUID, connection: NWConnection, headerString: String, buffer: Data, expectedLen: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] content, _, isComplete, error in
            guard let self = self, let conn = connection else { return }
            if let error = error {
                NSLog("[Server] HTTP body receive error: %@", error.localizedDescription)
                conn.cancel()
                return
            }
            var current = buffer
            if let data = content {
                current.append(data)
            }
            if current.count >= expectedLen || isComplete {
                self.handleHTTPRequest(headerString: headerString, bodyData: current.prefix(expectedLen), connection: conn)
            } else {
                self.readRemainingHTTPBody(clientId: clientId, connection: conn, headerString: headerString, buffer: current, expectedLen: expectedLen)
            }
        }
    }

    private func readWebSocketFrames(clientId: UUID, connection: NWConnection, buffer: Data) {
        var current = buffer
        let frames = decodeWebSocketFrames(buffer: &current)
        for (opcode, payload) in frames {
            switch opcode {
            case 0x01:
                if let text = String(data: payload, encoding: .utf8) {
                    Task {
                        await self.processClientTextMessage(text, connection: connection)
                    }
                }
            case 0x02:
                Task {
                    await self.processClientBinaryMessage(payload, connection: connection)
                }
            case 0x08:
                removeClient(clientId: clientId)
                return
            case 0x09:
                let pong = makeWebSocketFrame(payload: payload, opcode: 0x0A)
                connection.send(content: pong, completion: .contentProcessed({ _ in }))
            default:
                break
            }
        }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] content, _, isComplete, error in
            guard let self = self, let conn = connection else { return }
            if error != nil {
                self.removeClient(clientId: clientId)
                return
            }
            if isComplete {
                self.removeClient(clientId: clientId)
                return
            }
            var next = current
            if let data = content {
                next.append(data)
            }
            self.readWebSocketFrames(clientId: clientId, connection: conn, buffer: next)
        }
    }

    internal func decodeWebSocketFrames(buffer: inout Data) -> [(opcode: UInt8, payload: Data)] {
        var results: [(opcode: UInt8, payload: Data)] = []
        while buffer.count >= 2 {
            let b0 = buffer[buffer.startIndex]
            let opcode = b0 & 0x0F
            let b1 = buffer[buffer.startIndex + 1]
            let isMasked = (b1 & 0x80) != 0
            var payloadLen = UInt64(b1 & 0x7F)
            var offset = 2

            if payloadLen == 126 {
                guard buffer.count >= offset + 2 else { break }
                let high = UInt64(buffer[buffer.startIndex + offset])
                let low = UInt64(buffer[buffer.startIndex + offset + 1])
                payloadLen = (high << 8) | low
                offset += 2
            } else if payloadLen == 127 {
                guard buffer.count >= offset + 8 else { break }
                payloadLen = 0
                for i in 0..<8 {
                    payloadLen = (payloadLen << 8) | UInt64(buffer[buffer.startIndex + offset + i])
                }
                offset += 8
            }

            var maskKey: [UInt8] = [0, 0, 0, 0]
            if isMasked {
                guard buffer.count >= offset + 4 else { break }
                maskKey = [
                    buffer[buffer.startIndex + offset],
                    buffer[buffer.startIndex + offset + 1],
                    buffer[buffer.startIndex + offset + 2],
                    buffer[buffer.startIndex + offset + 3]
                ]
                offset += 4
            }

            let totalFrameLen = offset + Int(payloadLen)
            guard buffer.count >= totalFrameLen else { break }

            let rawPayload = buffer.subdata(in: (buffer.startIndex + offset)..<(buffer.startIndex + totalFrameLen))
            buffer.removeSubrange(buffer.startIndex..<(buffer.startIndex + totalFrameLen))

            var unmasked = Data(count: rawPayload.count)
            if isMasked {
                let count = rawPayload.count
                rawPayload.withUnsafeBytes { rawPtr in
                    unmasked.withUnsafeMutableBytes { outPtr in
                        let inBytes = rawPtr.bindMemory(to: UInt8.self).baseAddress!
                        let outBytes = outPtr.bindMemory(to: UInt8.self).baseAddress!
                        for i in 0..<count {
                            outBytes[i] = inBytes[i] ^ maskKey[i % 4]
                        }
                    }
                }
            } else {
                unmasked = rawPayload
            }

            results.append((opcode: opcode, payload: unmasked))
        }
        return results
    }

    internal func makeWebSocketFrame(payload: Data, opcode: UInt8) -> Data {
        var frame = Data()
        frame.append(0x80 | (opcode & 0x0F))
        let count = payload.count
        if count <= 125 {
            frame.append(UInt8(count))
        } else if count <= 65535 {
            frame.append(126)
            var len16 = UInt16(count).bigEndian
            withUnsafeBytes(of: &len16) { frame.append(contentsOf: $0) }
        } else {
            frame.append(127)
            var len64 = UInt64(count).bigEndian
            withUnsafeBytes(of: &len64) { frame.append(contentsOf: $0) }
        }
        frame.append(payload)
        return frame
    }

    internal func webSocketAccept(for key: String) -> String {
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let combined = key.trimmingCharacters(in: .whitespacesAndNewlines) + magic
        let digest = Insecure.SHA1.hash(data: Data(combined.utf8))
        return Data(digest).base64EncodedString()
    }

    internal func extractHeader(named name: String, from headerString: String) -> String? {
        let lines = headerString.components(separatedBy: "\r\n")
        let target = name.lowercased() + ":"
        for line in lines {
            if line.lowercased().hasPrefix(target) {
                let value = line.dropFirst(target.count)
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    // MARK: - HTTP Request Handling & Media API

    private func handleHTTPRequest(headerString: String, bodyData: Data, connection: NWConnection) {
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
        var header = "HTTP/1.1 302 Found\r\nLocation: \(location)\r\nContent-Length: 0\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n"
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

    // MARK: - Message Routing & Dispatcher

    private func processClientTextMessage(_ text: String, connection: NWConnection) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            sendError(action: "unknown", error: "Invalid JSON format", id: nil, to: connection)
            return
        }

        let id = json["id"] as? String
        let action = (json["action"] as? String) ?? (json["command"] as? String) ?? (json["type"] as? String) ?? ""
        let params = (json["params"] as? [String: Any]) ?? (json["payload"] as? [String: Any]) ?? (json["data"] as? [String: Any]) ?? json

        let bridge = MusicBridge.shared
        let cloud = CloudCatalogService.shared

        NSLog("[WebSocket] Processing action: %@, id: %@", action, id ?? "nil")
        switch action.lowercased() {
        case "play", "start":
            let ok = bridge.play()
            var status = PlayerStatusEngine.shared.getPlayerStatus()
            status.playerState = "playing"
            if DLNADiscoveryManager.shared.hasActiveRenderer {
                DLNADiscoveryManager.shared.play()
            }
            broadcastStatus(status: status, includeQueue: false)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.broadcastStatus(includeQueue: false)
            }

        case "pause":
            let ok = bridge.pause()
            var status = PlayerStatusEngine.shared.getPlayerStatus()
            status.playerState = "paused"
            if DLNADiscoveryManager.shared.hasActiveRenderer {
                DLNADiscoveryManager.shared.pause()
            }
            broadcastStatus(status: status, includeQueue: false)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.broadcastStatus(includeQueue: false)
            }

        case "stop":
            let ok = bridge.stop()
            var status = PlayerStatusEngine.shared.getPlayerStatus()
            status.playerState = "stopped"
            if DLNADiscoveryManager.shared.hasActiveRenderer {
                DLNADiscoveryManager.shared.stopPlayback()
            }
            broadcastStatus(status: status, includeQueue: false)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.broadcastStatus(includeQueue: false)
            }

        case "play_pause", "toggle_play_pause":
            let ok = bridge.playPause()
            let status = PlayerStatusEngine.shared.getPlayerStatus()
            if DLNADiscoveryManager.shared.hasActiveRenderer {
                if status.isPlaying {
                    DLNADiscoveryManager.shared.play()
                } else {
                    DLNADiscoveryManager.shared.pause()
                }
            }
            broadcastStatus(status: status, includeQueue: false)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            // ScriptingBridge needs ~150-250ms to reflect state changes in Music.app.
            // Avoid immediate broadcast of stale state; broadcast after 250ms and 600ms.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.broadcastStatus(includeQueue: false)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.broadcastStatus(includeQueue: false)
            }

        case "next", "next_track":
            let ok = bridge.nextTrack()
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            try? await Task.sleep(nanoseconds: 800_000_000)
            let isRadio = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isRadioPlayback }
            broadcastStatus(includeQueue: !isRadio)

        case "previous", "prev", "previous_track":
            let ok = bridge.previousTrack()
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            try? await Task.sleep(nanoseconds: 800_000_000)
            let isRadio = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isRadioPlayback }
            broadcastStatus(includeQueue: !isRadio)

        case "seek":
            let pos = (params["position"] as? Double) ?? (params["pos"] as? Double) ?? 0
            let ok = bridge.seek(to: pos)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "position": pos], id: id, to: connection)
            broadcastStatus(includeQueue: false)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.broadcastStatus(includeQueue: false)
            }

        case "set_volume", "volume":
            var volInt = 50
            if let num = params["volume"] as? NSNumber {
                volInt = num.intValue
            } else if let num = params["vol"] as? NSNumber {
                volInt = num.intValue
            } else if let d = params["volume"] as? Double {
                volInt = Int(d)
            } else if let d = params["vol"] as? Double {
                volInt = Int(d)
            } else if let s = params["volume"] as? String, let parsed = Int(s) {
                volInt = parsed
            }
            volInt = max(0, min(100, volInt))
            let ok = bridge.setVolume(volInt)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "volume": volInt], id: id, to: connection)
            broadcastStatus(includeQueue: false)

        case "duck", "activate_ducking":
            let reduction = (params["reduction"] as? Double) ?? ((params["reduction"] as? NSNumber)?.doubleValue) ?? (params["percent"] as? Double) ?? ((params["percent"] as? NSNumber)?.doubleValue) ?? 80.0
            let timeout = (params["timeout"] as? Double) ?? ((params["timeout"] as? NSNumber)?.doubleValue) ?? (params["duration"] as? Double) ?? ((params["duration"] as? NSNumber)?.doubleValue)
            let res = bridge.activateDucking(reductionPercent: reduction, timeout: timeout)
            sendSuccess(action: action, data: [
                "status": "ok",
                "is_ducked": true,
                "original_volume": res.originalVolume,
                "ducked_volume": res.duckedVolume,
                "volume": res.duckedVolume
            ], id: id, to: connection)
            broadcastStatus(includeQueue: false)

        case "unduck", "deactivate_ducking":
            let res = bridge.deactivateDucking()
            sendSuccess(action: action, data: [
                "status": "ok",
                "is_ducked": false,
                "restored_volume": res.restoredVolume,
                "volume": res.restoredVolume
            ], id: id, to: connection)
            broadcastStatus(includeQueue: false)

        case "set_ducking", "ducking":
            let enabled = (params["enabled"] as? Bool) ?? (params["active"] as? Bool) ?? true
            if enabled {
                let reduction = (params["reduction"] as? Double) ?? ((params["reduction"] as? NSNumber)?.doubleValue) ?? (params["percent"] as? Double) ?? ((params["percent"] as? NSNumber)?.doubleValue) ?? 80.0
                let timeout = (params["timeout"] as? Double) ?? ((params["timeout"] as? NSNumber)?.doubleValue) ?? (params["duration"] as? Double) ?? ((params["duration"] as? NSNumber)?.doubleValue)
                let res = bridge.activateDucking(reductionPercent: reduction, timeout: timeout)
                sendSuccess(action: action, data: [
                    "status": "ok",
                    "is_ducked": true,
                    "original_volume": res.originalVolume,
                    "ducked_volume": res.duckedVolume,
                    "volume": res.duckedVolume
                ], id: id, to: connection)
            } else {
                let res = bridge.deactivateDucking()
                sendSuccess(action: action, data: [
                    "status": "ok",
                    "is_ducked": false,
                    "restored_volume": res.restoredVolume,
                    "volume": res.restoredVolume
                ], id: id, to: connection)
            }
            broadcastStatus(includeQueue: false)

        case "set_shuffle", "shuffle":
            let enabled = (params["enabled"] as? Bool) ?? (params["shuffle"] as? Bool) ?? false
            let ok = bridge.setShuffle(enabled)
            broadcastStatus(includeQueue: false)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "shuffle": enabled], id: id, to: connection)

        case "set_repeat", "repeat":
            let mode = (params["mode"] as? String) ?? (params["repeat"] as? String) ?? "off"
            let ok = bridge.setRepeat(mode: mode)
            broadcastStatus(includeQueue: false)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "repeat": mode], id: id, to: connection)

        case "favorite", "toggle_favorite":
            let ok = bridge.toggleFavorite()
            broadcastStatus(includeQueue: false)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)

        case "set_lock_volume_100", "lock_volume_100":
            let enabled = (params["enabled"] as? Bool) ?? (params["lock"] as? Bool) ?? (params["lock_volume_100"] as? Bool) ?? true
            PlaybackStateStore.shared.isVolumeLockedTo100 = enabled
            if enabled {
                _ = bridge.setVolume(100)
            }
            broadcastStatus(includeQueue: false)
            sendSuccess(action: action, data: ["status": "ok", "lock_volume_100": enabled], id: id, to: connection)

        case "search_and_play":
            let query = (params["query"] as? String) ?? (params["q"] as? String) ?? ""
            Task { [weak self] in
                guard let self = self else { return }
                let res = await bridge.searchAndPlayDetailed(query: query)
                var respData: [String: Any] = [
                    "status": res.success ? "ok" : "error",
                    "success": res.success
                ]
                if let st = res.station {
                    respData["station"] = st
                    respData["mode"] = "random_station"
                }
                if let q = res.query {
                    respData["query"] = q
                    respData["mode"] = "search"
                    if let cnt = res.count {
                        respData["count"] = cnt
                    }
                }
                self.sendSuccess(action: action, data: respData, id: id, to: connection)
                try? await Task.sleep(nanoseconds: 300_000_000)
                self.broadcastStatus(includeQueue: true)
            }

        case "get_status", "status", "player_status":
            let status = bridge.getPlayerStatus()
            sendSuccess(action: action, data: status, id: id, to: connection)

        case "get_playlists", "playlists":
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                let fastList = bridge.getPlaylists()
                self.sendSuccess(action: action, data: PlaylistsResponse(playlists: fastList), id: id, to: connection)

                let hasMissing = fastList.contains { ($0.artworkUrl?.isEmpty ?? true) }
                if hasMissing {
                    let enriched = await bridge.getPlaylistsWithArtworks()
                    self.sendEvent("playlists_result", data: PlaylistsResponse(playlists: enriched), to: connection)
                }
            }

        case "get_playlist_tracks", "playlist_tracks":
            let name = (params["name"] as? String) ?? (params["playlist"] as? String) ?? ""
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                let tracks = name == "Сейчас на повторе" ? bridge.getRecentlyPlayed(limit: 50) : bridge.getPlaylistTracks(name: name)
                self.sendSuccess(action: action, data: PlaylistTracksResponse(playlist: name, tracks: tracks), id: id, to: connection)

                let hasMissing = tracks.contains { !$0.hasArtwork || $0.artworkUrl.isEmpty }
                if hasMissing {
                    let enriched = await bridge.enrichTracksArtwork(tracks)
                    bridge.updatePlaylistTracksCache(name: name, tracks: enriched)
                    self.sendEvent("playlist_tracks", data: PlaylistTracksResponse(playlist: name, tracks: enriched), to: connection)
                }
            }

        case "get_artists", "get_library_artists":
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                let artists = bridge.getLibraryArtists()
                self.sendSuccess(action: action, data: ArtistsResponse(artists: artists), id: id, to: connection)
            }

        case "get_albums", "get_library_albums":
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                let albums = bridge.getLibraryAlbums()
                self.sendSuccess(action: action, data: AlbumsResponse(albums: albums), id: id, to: connection)
            }

        case "get_songs", "get_library_songs":
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                let songs = bridge.getLibrarySongs()
                self.sendSuccess(action: action, data: SongsResponse(songs: songs), id: id, to: connection)
            }

        case "get_stations", "stations":
            let country = (params["country"] as? String) ?? "ru"
            let stations = cloud.getCuratedStations(country: country)
            sendSuccess(action: action, data: StationsResponse(stations: stations), id: id, to: connection)

        case "play_station":
            let url = (params["url"] as? String) ?? ""
            let name = (params["name"] as? String) ?? "Apple Music Radio"
            let type = (params["type"] as? String) ?? ""
            let trackTitle = (params["title"] as? String) ?? (params["track"] as? String) ?? ""
            let artistName = (params["artist"] as? String) ?? ""
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                let ok = await bridge.playStation(url: url, name: name, type: type, trackTitle: trackTitle, artistName: artistName)
                self.broadcastStatus(includeQueue: true)
                self.sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "station": name], id: id, to: connection)
            }

        case "play_hero_card":
            let index = (params["index"] as? Int) ?? 0
            let name = (params["name"] as? String) ?? ""
            let artist = (params["artist"] as? String) ?? (params["subtitle"] as? String) ?? (params["sub"] as? String) ?? ""
            let cardId = params["id"] as? String
            let url = params["url"] as? String
            let type = params["type"] as? String
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                let ok = await bridge.playHeroCard(index: index, name: name, artist: artist, cardId: cardId, url: url, type: type)
                self.sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "name": name], id: id, to: connection)
                self.broadcastStatus(includeQueue: true)
            }

        case "play_playlist":
            let plName = (params["playlist"] as? String) ?? (params["name"] as? String) ?? "Музыка"
            let trackId = (params["track_id"] as? Int) ?? Int((params["track_id"] as? String) ?? "")
            let trackIndex = (params["track_index"] as? Int) ?? Int((params["track_index"] as? String) ?? "")
            let shuffle = (params["shuffle"] as? Bool) ?? false
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                let ok = bridge.playPlaylist(name: plName, trackId: trackId, trackIndex: trackIndex, shuffle: shuffle)
                self.sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "playlist": plName], id: id, to: connection)
                try? await Task.sleep(nanoseconds: 200_000_000)
                self.broadcastStatus(includeQueue: true)
                try? await Task.sleep(nanoseconds: 600_000_000)
                self.broadcastStatus(includeQueue: true)
            }

        case "play_history_index", "history_play_index":
            let idx = (params["index"] as? Int) ?? 0
            let ok = await bridge.playHistoryIndex(idx)
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)

        case "play_history_track", "history_play_track":
            let name = (params["name"] as? String) ?? ""
            let artist = (params["artist"] as? String) ?? ""
            let ok = await bridge.playHistoryTrack(name: name, artist: artist)
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)

        case "play_album", "play_album_tracks":
            let albumId = (params["id"] as? String) ?? (params["album_id"] as? String) ?? ""
            let name = (params["name"] as? String) ?? (params["title"] as? String) ?? ""
            let artist = (params["artist"] as? String) ?? ""
            let shuffle = (params["shuffle"] as? Bool) ?? false
            let trackIndex = (params["track_index"] as? Int) ?? (params["index"] as? Int) ?? 1
            let startIndex = max(0, trackIndex - 1)

            var customTracks = [TrackInfo]()
            if let rawTracks = params["tracks"] as? [[String: Any]] {
                for (idx, item) in rawTracks.enumerated() {
                    let tid = (item["id"] as? String) ?? "\(idx + 1)"
                    let numId = (item["numeric_id"] as? Int) ?? (item["numericId"] as? Int)
                    let tName = (item["name"] as? String) ?? ""
                    let tArtist = (item["artist"] as? String) ?? artist
                    let tAlbum = (item["album"] as? String) ?? name
                    let tUrl = item["url"] as? String
                    let tArt = (item["artwork_url"] as? String) ?? (item["artwork"] as? String) ?? ""
                    let isLoc = (item["is_local"] as? Bool) ?? (item["isLocal"] as? Bool) ?? false
                    let dur = (item["duration"] as? Double) ?? 0.0
                    customTracks.append(TrackInfo(
                        id: tid,
                        numericId: numId,
                        name: tName,
                        artist: tArtist,
                        album: tAlbum,
                        duration: dur,
                        hasArtwork: !tArt.isEmpty,
                        artworkUrl: tArt,
                        favorited: false,
                        isLocal: isLoc,
                        url: tUrl,
                        index: idx + 1
                    ))
                }
            }

            let ok: Bool
            if !customTracks.isEmpty {
                ok = await bridge.playAlbumWithTracks(tracks: customTracks, name: name, artist: artist, startIndex: startIndex, shuffle: shuffle)
            } else {
                ok = await bridge.playAlbum(id: albumId, name: name, artist: artist, startIndex: startIndex, shuffle: shuffle)
            }
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "album": name], id: id, to: connection)

        case "play_recent", "play_recently_played":
            let shuffle = (params["shuffle"] as? Bool) ?? false
            let ok = await bridge.playRecentTracks(shuffle: shuffle)
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)

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
            let targetIsAlbum = isAlbum
            let targetAlbumId = albumId

            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                let ok: Bool
                if targetIsAlbum && !targetAlbumId.isEmpty {
                    ok = await bridge.playAlbum(id: targetAlbumId, name: name, artist: artist, shuffle: shuffle)
                } else {
                    ok = await bridge.playCloud(url: url, id: storeId, name: name, artist: artist, numericId: numericId, isLocal: isLocal)
                }
                self.broadcastStatus(includeQueue: true)
                self.sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            }

        case "play_search_results":
            let shuffle = (params["shuffle"] as? Bool) ?? false
            var trackInfos = [TrackInfo]()
            if let rawTracks = params["tracks"] as? [[String: Any]] {
                for (idx, item) in rawTracks.enumerated() {
                    let tid = (item["id"] as? String) ?? "\(idx + 1)"
                    let numId = (item["numeric_id"] as? Int) ?? (item["numericId"] as? Int)
                    let tName = (item["name"] as? String) ?? ""
                    let tArtist = (item["artist"] as? String) ?? ""
                    let tAlbum = (item["album"] as? String) ?? ""
                    let tUrl = item["url"] as? String
                    let tArt = (item["artwork_url"] as? String) ?? (item["artwork"] as? String) ?? ""
                    let isLoc = (item["is_local"] as? Bool) ?? (item["isLocal"] as? Bool) ?? false
                    trackInfos.append(TrackInfo(
                        id: tid,
                        numericId: numId,
                        name: tName,
                        artist: tArtist,
                        album: tAlbum,
                        duration: 0,
                        hasArtwork: !tArt.isEmpty,
                        artworkUrl: tArt,
                        favorited: false,
                        isLocal: isLoc,
                        url: tUrl,
                        index: idx + 1
                    ))
                }
            }
            let startIndex = (params["startIndex"] as? Int) ?? (params["track_index"] as? Int).map { max(0, $0 - 1) } ?? 0
            let targetTracks = trackInfos
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                let ok = await bridge.playSearchResults(tracks: targetTracks, startIndex: startIndex, shuffle: shuffle)
                self.sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "count": targetTracks.count], id: id, to: connection)
                self.broadcastStatus(includeQueue: true)
            }

        case "search":
            let query = (params["query"] as? String) ?? (params["q"] as? String) ?? ""
            var country = (params["country"] as? String) ?? "ru"
            if MusicKitManager.shared.hasUserToken {
                country = MusicKitManager.shared.getUserStorefront()
            }
            let source = (params["scope"] as? String) ?? (params["source"] as? String) ?? "all"
            let limit = (params["limit"] as? Int) ?? 50
            let offset = (params["offset"] as? Int) ?? 0
            let results = await cloud.search(query: query, country: country, source: source, limit: limit, offset: offset)
            sendSuccess(action: action, data: results, id: id, to: connection)

        case "get_developer_token":
            if let token = MusicKitManager.shared.getDeveloperToken() {
                sendSuccess(action: action, data: ["token": token], id: id, to: connection)
            } else {
                sendError(action: action, error: "Developer token unavailable", id: id, to: connection)
            }

        case "set_user_token", "user_token":
            if let token = (params["token"] as? String) ?? (params["user_token"] as? String), !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MusicKitManager.shared.setUserToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
                sendSuccess(action: action, data: ["status": "ok", "has_user_token": true, "storefront": MusicKitManager.shared.getUserStorefront()], id: id, to: connection)
            } else {
                MusicKitManager.shared.clearUserToken()
                sendSuccess(action: action, data: ["status": "ok", "has_user_token": false], id: id, to: connection)
            }

        case "get_user_token_status", "user_token_status":
            let hasToken = MusicKitManager.shared.hasUserToken
            sendSuccess(action: action, data: ["has_user_token": hasToken, "storefront": MusicKitManager.shared.getUserStorefront()], id: id, to: connection)

        case "get_audio_devices", "audio_devices":
            let isDLNAActive = DLNADiscoveryManager.shared.hasActiveRenderer
            var devices = CoreAudioDeviceManager.shared.getOutputDevices().map { dev -> [String: Any] in
                var dict = dev.dictionary
                if isDLNAActive {
                    dict["isDefault"] = false
                }
                return dict
            }
            if DLNADiscoveryManager.shared.isEnabled {
                devices.append(contentsOf: DLNADiscoveryManager.shared.getDiscoveredDevices())
            }
            let currentDev: [String: Any]?
            if let activeDLNA = DLNADiscoveryManager.shared.getActiveRenderer() {
                currentDev = activeDLNA.dictionary
            } else {
                currentDev = CoreAudioDeviceManager.shared.getDefaultOutputDevice()?.dictionary
            }
            sendSuccess(action: action, data: ["devices": devices, "current_device": currentDev as Any], id: id, to: connection)

        case "get_dlna_discovery_status":
            let isEnabled = DLNADiscoveryManager.shared.isEnabled
            let count = DLNADiscoveryManager.shared.getDiscoveredCount()
            sendSuccess(action: action, data: ["enabled": isEnabled, "discovered_count": count], id: id, to: connection)

        case "set_dlna_discovery":
            let enabled = (params["enabled"] as? Bool) ?? false
            DLNADiscoveryManager.shared.setEnabled(enabled)
            broadcastAudioDevices()
            sendSuccess(action: action, data: ["enabled": enabled, "status": "ok"], id: id, to: connection)

        case "get_local_dmr_status":
            let isEnabled = UPnPMediaRendererServer.shared.isEnabled
            sendSuccess(action: action, data: ["enabled": isEnabled], id: id, to: connection)

        case "set_local_dmr":
            let enabled = (params["enabled"] as? Bool) ?? false
            UPnPMediaRendererServer.shared.setEnabled(enabled)
            sendSuccess(action: action, data: ["enabled": enabled, "status": "ok"], id: id, to: connection)

        case "set_audio_device", "select_audio_device":
            let uidParam = (params["uid"] as? String) ?? ""
            let idNum = (params["id"] as? NSNumber)?.intValue ?? (params["id"] as? Int)

            // 1. Check if target is a DLNA MediaRenderer
            let isDLNATarget = uidParam.hasPrefix("dlna:") ||
                               (idNum != nil && DLNADiscoveryManager.shared.getDiscoveredRenderers().contains(where: { $0.numericId == idNum }))

            if isDLNATarget {
                let targetUID: String
                if uidParam.hasPrefix("dlna:") {
                    targetUID = uidParam
                } else if let id = idNum, let found = DLNADiscoveryManager.shared.getDiscoveredRenderers().first(where: { $0.numericId == id }) {
                    targetUID = "dlna:\(found.id)"
                } else {
                    targetUID = uidParam
                }

                if let dlnaDev = DLNADiscoveryManager.shared.selectRenderer(uid: targetUID) {
                    AudioProcessTapService.shared.startCapture()

                    // Send UPnP AVTransport SetAVTransportURI & Play
                    let (streamURL, imageURL, fullTitle, metadata) = DLNADiscoveryManager.shared.resolveStreamAndImageURLs()
                    let status = MusicBridge.shared.getPlayerStatus()

                    DLNADiscoveryManager.shared.setAVTransportURI(uri: streamURL, metadata: metadata, imageURL: imageURL, title: fullTitle) { success, _ in
                        if success, status.isPlaying, !dlnaDev.isBluOS {
                            DLNADiscoveryManager.shared.play()
                        }
                    }

                    broadcastAudioDevices()
                    broadcastStatus(includeQueue: false)
                    sendSuccess(action: action, data: ["status": "ok", "device_uid": targetUID, "name": dlnaDev.friendlyName], id: id, to: connection)
                    return
                } else {
                    sendError(action: action, error: "DLNA renderer not found or offline", id: id, to: connection)
                    return
                }
            }

            // 2. Otherwise target is a local CoreAudio device
            var targetId: AudioDeviceID?
            if let num = idNum {
                targetId = AudioDeviceID(num)
            } else if let idStr = params["id"] as? String, let parsed = UInt32(idStr) {
                targetId = AudioDeviceID(parsed)
            } else if !uidParam.isEmpty {
                targetId = CoreAudioDeviceManager.shared.getOutputDevices().first { $0.uid == uidParam }?.id
            }

            if let devId = targetId, CoreAudioDeviceManager.shared.setDefaultOutputDevice(id: devId) {
                // If DLNA was active, stop DLNA playback and deselect renderer
                if DLNADiscoveryManager.shared.hasActiveRenderer {
                    DLNADiscoveryManager.shared.stopPlayback()
                    DLNADiscoveryManager.shared.deselectRenderer()
                    AudioProcessTapService.shared.stopCapture()
                }

                broadcastAudioDevices()
                broadcastStatus(includeQueue: false)
                let updated = CoreAudioDeviceManager.shared.getOutputDevices().map { $0.dictionary }
                sendSuccess(action: action, data: ["status": "ok", "device_id": Int(devId), "devices": updated], id: id, to: connection)
            } else {
                sendError(action: action, error: "Failed to switch audio output device", id: id, to: connection)
            }

        case "get_catalog_charts", "catalog_charts", "charts":
            let country = (params["country"] as? String) ?? "us"
            let songs = await MusicKitManager.shared.getTopCharts(storefront: country)
            sendSuccess(action: action, data: ["songs": songs], id: id, to: connection)

        case "get_explore", "explore":
            let country = (params["country"] as? String) ?? "ru"
            let feed = await cloud.getExploreFeed(country: country)
            sendSuccess(action: action, data: feed, id: id, to: connection)

        case "get_album", "album":
            let albumId = (params["id"] as? String) ?? (params["album_id"] as? String) ?? ""
            let name = (params["name"] as? String) ?? (params["title"] as? String) ?? ""
            let artist = (params["artist"] as? String) ?? ""
            let country = (params["country"] as? String) ?? "ru"
            var albumInfo = await cloud.getAlbumDetails(albumId: albumId, country: country)
            if albumInfo == nil && country != "us" {
                albumInfo = await cloud.getAlbumDetails(albumId: albumId, country: "us")
            }
            if albumInfo == nil && (!name.isEmpty || !artist.isEmpty) {
                var trks = await MusicKitManager.shared.getAlbumTracks(album: name, artist: artist, storefront: country)
                if trks.isEmpty && country != "us" {
                    trks = await MusicKitManager.shared.getAlbumTracks(album: name, artist: artist, storefront: "us")
                }
                if !trks.isEmpty {
                    albumInfo = AlbumInfo(
                        id: albumId,
                        name: name,
                        artist: artist,
                        artwork: trks.first?.artworkUrl ?? "",
                        releaseDate: nil,
                        trackCount: trks.count,
                        genre: nil,
                        url: nil,
                        tracks: trks
                    )
                }
            }
            if let album = albumInfo {
                sendSuccess(action: action, data: ["album": album], id: id, to: connection)
            } else {
                sendError(action: action, error: "Album not found", id: id, to: connection)
            }

        case "add_to_library":
            let trackId = params["track_id"] as? Int
            let name = params["name"] as? String
            let artist = params["artist"] as? String
            let url = params["url"] as? String
            let ok = bridge.addToLibrary(trackId: trackId, name: name, artist: artist, url: url)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)

        case "queue_add", "add_to_queue":
            var ok = false
            if let rawTracks = params["tracks"] as? [[String: Any]] {
                let trackInfos = rawTracks.map { parseTrackInfo($0) }
                ok = await bridge.enqueueTracks(trackInfos, playNext: false)
            } else if let rawTrack = params["track"] as? [String: Any] {
                let trackInfo = parseTrackInfo(rawTrack)
                ok = await bridge.enqueueTrack(trackInfo, playNext: false)
            }
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)

        case "queue_play_next":
            var ok = false
            if let rawTracks = params["tracks"] as? [[String: Any]] {
                let trackInfos = rawTracks.map { parseTrackInfo($0) }
                ok = await bridge.enqueueTracks(trackInfos, playNext: true)
            } else if let rawTrack = params["track"] as? [String: Any] {
                let trackInfo = parseTrackInfo(rawTrack)
                ok = await bridge.enqueueTrack(trackInfo, playNext: true)
            }
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)

        case "queue_remove":
            let idx = (params["index"] as? Int) ?? 0
            let ok = await bridge.removeQueueTrack(at: idx)
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)

        case "queue_clear":
            let ok = await bridge.clearUpcomingQueue()
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)

        case "queue_play_index", "play_queue_index":
            let idx = (params["index"] as? Int) ?? 0
            let ok = await bridge.playQueueIndex(idx)
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)

        case "get_queue", "queue":
            let q = await bridge.getPlaybackQueue()
            sendSuccess(action: action, data: q, id: id, to: connection)

        case "get_artwork", "artwork":
            if let isCur = params["current"] as? Bool, isCur {
                if let data = bridge.getCurrentTrackArtwork() {
                    let b64 = data.base64EncodedString()
                    sendSuccess(action: action, data: ["artwork_base64": b64, "mime": "image/jpeg"], id: id, to: connection)
                } else {
                    sendError(action: action, error: "No artwork found", id: id, to: connection)
                }
            } else if let tid = params["track_id"] as? Int {
                if let data = bridge.getTrackArtwork(id: tid) {
                    let b64 = data.base64EncodedString()
                    sendSuccess(action: action, data: ["artwork_base64": b64, "mime": "image/jpeg"], id: id, to: connection)
                } else {
                    sendError(action: action, error: "No artwork found", id: id, to: connection)
                }
            } else if let plName = params["playlist"] as? String {
                if let data = bridge.getPlaylistArtwork(name: plName) {
                    let b64 = data.base64EncodedString()
                    sendSuccess(action: action, data: ["artwork_base64": b64, "mime": "image/jpeg"], id: id, to: connection)
                } else {
                    sendError(action: action, error: "No artwork found", id: id, to: connection)
                }
            } else {
                sendError(action: action, error: "Missing parameters for artwork", id: id, to: connection)
            }

        case "get_account_status", "account_health":
            let force = (params["refresh"] as? Bool) ?? false
            let health = await AccountHealthService.shared.checkAccountHealth(forceRefresh: force)
            sendSuccess(action: action, data: health, id: id, to: connection)

        case "get_info", "info":
            let ips = getLANIPAddresses()
            let primaryUrl = ips.first.map { "http://\($0):\(self.port)" } ?? "http://localhost:\(self.port)"
            sendSuccess(action: action, data: [
                "port": self.port,
                "primary_url": primaryUrl,
                "ips": ips,
                "version": "2.3.0",
                "platform": "macOS"
            ], id: id, to: connection)

        default:
            sendError(action: action, error: "Unsupported action: \(action)", id: id, to: connection)
        }
    }

    private func processClientBinaryMessage(_ data: Data, connection: NWConnection) async {
        sendSuccess(action: "binary", data: ["received_bytes": data.count], id: nil, to: connection)
    }

    private func parseTrackInfo(_ dict: [String: Any]) -> TrackInfo {
        let tid = (dict["id"] as? String) ?? "\(dict["numeric_id"] ?? UUID().uuidString)"
        let numericId = (dict["numeric_id"] as? Int) ?? Int(tid)
        let name = (dict["name"] as? String) ?? ""
        let artist = (dict["artist"] as? String) ?? ""
        let album = (dict["album"] as? String) ?? ""
        let dur = (dict["duration"] as? Double) ?? 0
        let art = (dict["artwork"] as? String) ?? (dict["artwork_url"] as? String) ?? ""
        let url = dict["url"] as? String
        let preview = dict["preview_url"] as? String
        let isLocal = (dict["is_local"] as? Bool) ?? false

        return TrackInfo(
            id: tid,
            numericId: numericId,
            name: name,
            artist: artist,
            album: album,
            duration: dur,
            hasArtwork: !art.isEmpty,
            artworkUrl: art,
            favorited: false,
            isLocal: isLocal,
            url: url,
            previewUrl: preview
        )
    }

    // MARK: - Outgoing WebSocket Messages

    public func sendSuccess<T: Encodable>(action: String, data: T, id: String?, to connection: NWConnection) {
        var baseObj: [String: Any] = [
            "action": action,
            "event": action,
            "type": action,
            "status": "ok"
        ]
        if let reqId = id {
            baseObj["id"] = reqId
        }

        if let encodedData = try? JSONEncoder().encode(data),
           let dataObj = try? JSONSerialization.jsonObject(with: encodedData) {
            baseObj["data"] = dataObj
        } else {
            baseObj["data"] = "\(data)"
        }

        if let jsonBytes = try? JSONSerialization.data(withJSONObject: baseObj),
           let text = String(data: jsonBytes, encoding: .utf8) {
            sendText(text, to: connection)
        }
    }

    public func sendSuccess(action: String, data: [String: Any], id: String?, to connection: NWConnection) {
        var payload: [String: Any] = [
            "action": action,
            "event": action,
            "type": action,
            "status": "ok"
        ]
        if let reqId = id {
            payload["id"] = reqId
        }

        // Sanitize data dictionary so AnyCodable or custom Swift structs/enums become native JSON types
        let sanitizedData = sanitizeForJSON(data)
        payload["data"] = sanitizedData

        if let jsonBytes = try? JSONSerialization.data(withJSONObject: payload),
           let text = String(data: jsonBytes, encoding: .utf8) {
            sendText(text, to: connection)
        }
    }

    private func sanitizeForJSON(_ value: Any) -> Any {
        if let ac = value as? AnyCodable {
            return sanitizeForJSON(ac.value ?? NSNull())
        } else if let dict = value as? [String: Any] {
            var res = [String: Any]()
            for (k, v) in dict {
                res[k] = sanitizeForJSON(v)
            }
            return res
        } else if let arr = value as? [Any] {
            return arr.map { sanitizeForJSON($0) }
        } else if let str = value as? String {
            return str
        } else if let num = value as? NSNumber {
            return num
        } else if let b = value as? Bool {
            return b
        } else if let i = value as? Int {
            return i
        } else if let d = value as? Double {
            return d
        } else if let s = value as? StationInfo {
            if let data = try? JSONEncoder().encode(s),
               let obj = try? JSONSerialization.jsonObject(with: data) {
                return obj
            }
            return s.name
        } else if let t = value as? TrackInfo {
            if let data = try? JSONEncoder().encode(t),
               let obj = try? JSONSerialization.jsonObject(with: data) {
                return obj
            }
            return t.name
        } else if value is NSNull {
            return NSNull()
        } else {
            return String(describing: value)
        }
    }

    public func sendError(action: String, error: String, id: String?, to connection: NWConnection) {
        var payload: [String: Any] = [
            "action": action,
            "status": "error",
            "error": error
        ]
        if let reqId = id {
            payload["id"] = reqId
        }

        if let jsonBytes = try? JSONSerialization.data(withJSONObject: payload),
           let text = String(data: jsonBytes, encoding: .utf8) {
            sendText(text, to: connection)
        }
    }

    public struct EventEnvelope<T: Encodable>: Encodable {
        public let event: String
        public let type: String
        public let data: T
    }

    public func sendEvent<T: Encodable>(_ eventName: String, data: T, to connection: NWConnection) {
        let env = EventEnvelope(event: eventName, type: eventName, data: data)
        if let encoded = try? JSONEncoder().encode(env),
           let text = String(data: encoded, encoding: .utf8) {
            sendText(text, to: connection)
        }
    }

    public func broadcastEvent<T: Encodable>(_ eventName: String, data: T) {
        let env = EventEnvelope(event: eventName, type: eventName, data: data)
        if let encoded = try? JSONEncoder().encode(env),
           let text = String(data: encoded, encoding: .utf8) {
            broadcastText(text)
        }
    }

    public func broadcastEvent(name: String, data: [String: Any]) {
        let envelope: [String: Any] = [
            "event": name,
            "type": name,
            "data": sanitizeForJSON(data)
        ]
        if let json = try? JSONSerialization.data(withJSONObject: envelope),
           let text = String(data: json, encoding: .utf8) {
            broadcastText(text)
        }
    }

    public func sendText(_ text: String, to connection: NWConnection) {
        guard let data = text.data(using: .utf8) else { return }
        let frame = makeWebSocketFrame(payload: data, opcode: 0x01)
        sendLock.lock()
        defer { sendLock.unlock() }
        connection.send(content: frame, completion: .contentProcessed({ error in
            if let err = error {
                NSLog("[WebSocket] sendText error: %@", err.localizedDescription)
            }
        }))
    }

    public func sendBinary(_ data: Data, to connection: NWConnection) {
        let frame = makeWebSocketFrame(payload: data, opcode: 0x02)
        sendLock.lock()
        defer { sendLock.unlock() }
        connection.send(content: frame, completion: .contentProcessed({ _ in }))
    }

    public func broadcastText(_ text: String) {
        clientLock.lock()
        let active = Array(clients.values)
        clientLock.unlock()

        for conn in active {
            sendText(text, to: conn)
        }
    }

    public func broadcastStatus(status customStatus: PlayerStatus? = nil, includeQueue: Bool = false) {
        let status = customStatus ?? MusicBridge.shared.getPlayerStatus()
        clientLock.lock()
        let active = Array(clients.values)
        clientLock.unlock()

        for conn in active {
            sendEvent("player_state_changed", data: status, to: conn)
        }

        if includeQueue {
            Task {
                let queue = await MusicBridge.shared.getPlaybackQueue()
                for conn in active {
                    sendEvent("queue_changed", data: queue, to: conn)
                }
                await MainActor.run {
                    MenuManager.shared.updateMenuState(with: status)
                }
            }
        }

        Task { @MainActor in
            MenuManager.shared.updateMenuState(with: status)
        }

        UPnPMediaRendererServer.shared.notifySubscribers(status: status)
        DLNADiscoveryManager.shared.handleTrackChanged(status: status)
    }

    public func broadcastAudioDevices() {
        let isDLNAActive = DLNADiscoveryManager.shared.hasActiveRenderer
        var devices = CoreAudioDeviceManager.shared.getOutputDevices().map { dev -> [String: Any] in
            var dict = dev.dictionary
            if isDLNAActive {
                dict["isDefault"] = false
            }
            return dict
        }
        if DLNADiscoveryManager.shared.isEnabled {
            devices.append(contentsOf: DLNADiscoveryManager.shared.getDiscoveredDevices())
        }
        var data: [String: Any] = ["devices": devices]
        if let activeDLNA = DLNADiscoveryManager.shared.getActiveRenderer() {
            data["current_device"] = activeDLNA.dictionary
        } else if let defaultDev = CoreAudioDeviceManager.shared.getDefaultOutputDevice()?.dictionary {
            data["current_device"] = defaultDev
        }
        broadcastEvent(name: "audio_devices", data: data)
    }

    // MARK: - Periodic Monitoring Timer

    private func startPollerTimer() {
        stopPollerTimer()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 3.0, repeating: 3.0)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }

            // If NO clients connected, do NOT poll Music.app at all!
            let hasClients = self.clientCount > 0
            guard hasClients else { return }

            // Guard against polling when Music.app is hung, recovering, or in cooldown
            guard MusicAppLifecycleManager.shared.isHealthy else { return }

            // Guard against bombarding Music.app while a track skip is actively buffering
            if PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.isTransitioningTrack }) {
                return
            }

            // Auto-advance check for cloud queue
            MusicBridge.shared.checkAndAutoAdvanceCloudQueue()

            let status = MusicBridge.shared.getPlayerStatus()
            let state = status.playerState
            let pos = status.position
            let trackId = status.track?.id ?? ""

            let stateChanged = (state != self.lastKnownState)
            let trackChanged = (!trackId.isEmpty && trackId != self.lastKnownTrackId)
            let posJumped = abs(pos - self.lastKnownPosition) > 2.5
            let isPlaying = (state == "playing")

            if stateChanged || trackChanged || posJumped || (isPlaying && Date().timeIntervalSince(self.lastBroadcastTime) >= 3.0) {
                self.lastKnownState = state
                self.lastKnownPosition = pos
                if !trackId.isEmpty {
                    self.lastKnownTrackId = trackId
                }
                self.lastBroadcastTime = Date()
                self.broadcastStatus(includeQueue: trackChanged)
            }
        }
        timer.resume()
        self.pollerTimer = timer
    }

    private func stopPollerTimer() {
        pollerTimer?.cancel()
        pollerTimer = nil
    }

    // MARK: - IP Address Detection

    public func getLANIPAddresses() -> [String] {
        var addresses = [String]()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                let flags = Int32(ptr!.pointee.ifa_flags)
                var addr = ptr!.pointee.ifa_addr.pointee
                if (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING) {
                    if addr.sa_family == UInt8(AF_INET) {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(&addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                            let ip = String(cString: hostname)
                            if ip != "127.0.0.1" && !ip.hasPrefix("169.254") {
                                addresses.append(ip)
                            }
                        }
                    }
                }
                ptr = ptr!.pointee.ifa_next
            }
            freeifaddrs(ifaddr)
        }
        return addresses.isEmpty ? ["127.0.0.1"] : addresses
    }
}
