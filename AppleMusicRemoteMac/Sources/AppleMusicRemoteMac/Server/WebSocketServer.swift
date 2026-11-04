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

    var listener: NWListener?
    var clients: [UUID: NWConnection] = [:]
    var liveStreamConnections: [UUID: NWConnection] = [:]
    let liveStreamLock = NSLock()
    let clientLock = NSRecursiveLock()
    let sendLock = NSRecursiveLock()
    var isRunning = false
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

    var pollerTimer: DispatchSourceTimer?
    var lastKnownState: String = ""
    var lastKnownPosition: Double = 0
    var lastKnownTrackId: String = ""
    var lastNotificationTrackKey: String = ""
    var lastBroadcastTime: Date = Date.distantPast
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
            PlaybackStateStore.shared.markStaticMetadataNeedsRefresh()
            if let info = notif.userInfo {
                let rawName = (info["Name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let rawArtist = (info["Artist"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let canonicalKey = !rawName.isEmpty
                    ? "\(rawArtist.lowercased()):\(rawName.lowercased())"
                    : String(describing: info["PersistentID"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !canonicalKey.isEmpty && canonicalKey != self.lastNotificationTrackKey {
                    self.lastNotificationTrackKey = canonicalKey
                    let cachedFmt = BitPerfectLogMonitor.shared.getCachedFormat(artist: rawArtist, title: rawName)
                    BitPerfectLogMonitor.shared.resetTrackState(
                        trackKey: canonicalKey,
                        expectedSampleRate: cachedFmt?.sampleRate,
                        expectedBitDepth: cachedFmt?.bitDepth
                    )
                }
            }
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

        NotificationCenter.default.addObserver(forName: .bitPerfectFormatDidChange, object: nil, queue: notifQueue) { [weak self] _ in
            guard let self = self else { return }
            PlaybackStateStore.shared.invalidateStatusCache()
            self.broadcastStatus(includeQueue: false)
        }

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
                if let origin = self.extractHeader(named: "origin", from: headerString),
                   !self.isAllowedWebSocketOrigin(origin, requestHost: self.extractHeader(named: "host", from: headerString)) {
                    NSLog("[WebSocket] ❌ Rejected connection from untrusted Origin: %@", origin)
                    let forbidden = "HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                    conn.send(content: Data(forbidden.utf8), completion: .contentProcessed({ [weak conn] _ in
                        conn?.cancel()
                    }))
                    return
                }
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

    public func isAllowedWebSocketOrigin(_ origin: String, requestHost: String? = nil) -> Bool {
        let trimmed = origin.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty || trimmed == "null" || trimmed.hasPrefix("file://") || trimmed.hasPrefix("capacitor://") || trimmed.hasPrefix("ionic://") {
            return true
        }
        guard let url = URL(string: trimmed), let host = url.host?.lowercased(), !host.isEmpty else {
            return false
        }
        if let reqHost = requestHost?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            let reqHostOnly = reqHost.components(separatedBy: ":").first ?? reqHost
            if host == reqHostOnly {
                return true
            }
        }
        if host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]" || host.hasSuffix(".local") || host.hasSuffix(".lan") || host.hasSuffix(".home") {
            return true
        }
        // Check RFC1918 private LAN IPv4 addresses (10.x.x.x, 192.168.x.x, 172.16-31.x.x) and Tailscale/Carrier NAT (100.64-127.x.x)
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4 {
            if parts[0] == 10 || parts[0] == 127 { return true }
            if parts[0] == 192 && parts[1] == 168 { return true }
            if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
            if parts[0] == 100 && (64...127).contains(parts[1]) { return true }
        }
        return false
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