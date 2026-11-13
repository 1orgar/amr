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
    var clientHostAddresses: [UUID: String] = [:]
    var liveStreamConnections: [UUID: NWConnection] = [:]
    var headRequestConnections: Set<ObjectIdentifier> = []
    var fragmentBuffers: [ObjectIdentifier: (opcode: UInt8, data: Data)] = [:]
    let liveStreamLock = NSLock()
    let clientLock = NSRecursiveLock()
    let sendLock = NSRecursiveLock()
    let curateTaskLock = NSLock()
    var activeCurateTask: Task<Void, Never>?
    var activeCurateTasks: [UUID: Task<Void, Never>] = [:]
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

        CoreAudioDeviceManager.shared.addDevicesChangedObserver(id: "WebSocketServer") { [weak self] devices in
            guard let self = self else { return }
            let devList = devices.map { $0.dictionary }
            self.broadcastEvent(name: "audio_devices_changed", data: ["devices": devList])
            self.broadcastStatus(includeQueue: false)
        }

        CoreAudioDeviceManager.shared.addSampleRateChangedObserver(id: "WebSocketServer") { [weak self] _, _ in
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
                if case .failed = state {
                    self.isRunning = false
                }
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
        clientHostAddresses.removeAll()
        headRequestConnections.removeAll()
        fragmentBuffers.removeAll()
        cancelAllCurateTasks()
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
                self.removeClient(clientId: clientId, connection: conn)
            case .cancelled:
                self.removeClient(clientId: clientId, connection: conn)
            default:
                break
            }
        }

        let queue = DispatchQueue(label: "com.amr.server.client.\(clientId.uuidString)", qos: .userInteractive)
        connection.start(queue: queue)
    }

    private func removeClient(clientId: UUID, connection: NWConnection? = nil) {
        clientLock.lock()
        let conn = clients.removeValue(forKey: clientId)
        clientHostAddresses.removeValue(forKey: clientId)
        if let c = conn ?? connection {
            let objId = ObjectIdentifier(c)
            headRequestConnections.remove(objId)
            fragmentBuffers.removeValue(forKey: objId)
        }
        let count = clients.count
        clientLock.unlock()

        cancelCurateTask(for: clientId)

        guard let conn = conn else { return }

        ClientDeviceManager.shared.unregisterConnection(connectionId: clientId)
        conn.cancel()
        NSLog("[WebSocket] Client disconnected. Total clients: %d", count)
        delegate?.webSocketServer(self, didUpdateClientCount: count)
    }

    public func hasAuthorizedWebSocketClient(fromIP remoteIP: String) -> Bool {
        let cleanIP = remoteIP.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanIP.isEmpty else { return false }
        let unauthIds = ClientDeviceManager.shared.getUnauthorizedConnectionIds()
        clientLock.lock()
        defer { clientLock.unlock() }
        for (clientId, hostIP) in clientHostAddresses {
            if !unauthIds.contains(clientId) && hostIP.lowercased() == cleanIP && clients[clientId] != nil {
                return true
            }
        }
        return false
    }

    internal func extractRemoteIP(from connection: NWConnection) -> String {
        switch connection.endpoint {
        case .hostPort(let host, _):
            let raw = "\(host)"
            if let pct = raw.firstIndex(of: "%") {
                return String(raw[..<pct])
            }
            return raw
        default:
            return ""
        }
    }

    internal func extractCookie(named name: String, from headerString: String) -> String? {
        guard let cookieLine = extractHeader(named: "cookie", from: headerString) else { return nil }
        let target = name.lowercased() + "="
        for part in cookieLine.components(separatedBy: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix(target) {
                return String(trimmed.dropFirst(target.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func readInitialConnection(clientId: UUID, connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] content, _, isComplete, error in
            guard let self = self, let conn = connection else { return }
            if let error = error {
                NSLog("[Server] Initial receive error: %@", error.localizedDescription)
                conn.cancel()
                self.removeClient(clientId: clientId, connection: conn)
                return
            }

            var current = buffer
            if let data = content {
                current.append(data)
            }
            if current.count > 16 * 1024 * 1024 {
                conn.cancel()
                return
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
                    let remoteIP = self.extractRemoteIP(from: c)
                    self.clientLock.lock()
                    self.clients[clientId] = c
                    self.clientHostAddresses[clientId] = remoteIP
                    let count = self.clients.count
                    self.clientLock.unlock()

                    NSLog("[WebSocket] Handshake complete. Total WebSocket clients: %d", count)
                    self.delegate?.webSocketServer(self, didUpdateClientCount: count)

                    let firstLine = headerString.components(separatedBy: .newlines).first ?? ""
                    let reqParts = firstLine.split(separator: " ")
                    let reqFullPath = reqParts.count >= 2 ? String(reqParts[1]) : ""
                    let wsInviteToken: String? = {
                        guard let qIdx = reqFullPath.firstIndex(of: "?") else { return nil }
                        let query = String(reqFullPath[reqFullPath.index(after: qIdx)...])
                        for pair in query.components(separatedBy: "&") {
                            let kv = pair.components(separatedBy: "=")
                            if kv.count == 2 && kv[0].lowercased() == "invite" {
                                return kv[1].removingPercentEncoding ?? kv[1]
                            }
                        }
                        return nil
                    }()

                    let hasValidInvite = ClientDeviceManager.shared.validateInviteToken(wsInviteToken)
                    let lowerIP = remoteIP.lowercased()
                    let isLoopback = (lowerIP == "127.0.0.1" || lowerIP == "::1" || lowerIP == "localhost" || lowerIP == "::ffff:127.0.0.1")
                    let ua = self.extractHeader(named: "user-agent", from: headerString) ?? ""

                    if let cookieUid = self.extractCookie(named: "amr_device_uid", from: headerString),
                       !cookieUid.isEmpty {
                        if let existing = ClientDeviceManager.shared.getDevice(deviceId: cookieUid) {
                            let record = ClientDeviceManager.shared.registerConnection(
                                connectionId: clientId,
                                deviceId: cookieUid,
                                deviceName: existing.deviceName,
                                deviceType: existing.deviceType,
                                preferredLockScreen: existing.lockScreenControls,
                                remoteIP: remoteIP,
                                inviteToken: wsInviteToken
                            )
                            self.sendEvent(name: "device_auth_status", data: record.dictionary, to: c)
                            if record.isAuthorized {
                                let status = MusicBridge.shared.getPlayerStatus()
                                self.sendEvent("player_state_changed", data: status, to: c)
                                Task {
                                    let queue = await MusicBridge.shared.getPlaybackQueue()
                                    self.sendEvent("queue", data: queue, to: c)
                                }
                            }
                        } else if hasValidInvite {
                            let record = ClientDeviceManager.shared.registerConnection(
                                connectionId: clientId,
                                deviceId: cookieUid,
                                deviceName: "Invited Client",
                                deviceType: "mobile",
                                preferredLockScreen: nil,
                                remoteIP: remoteIP,
                                inviteToken: wsInviteToken
                            )
                            self.sendEvent(name: "device_auth_status", data: record.dictionary, to: c)
                            if record.isAuthorized {
                                let status = MusicBridge.shared.getPlayerStatus()
                                self.sendEvent("player_state_changed", data: status, to: c)
                                Task {
                                    let queue = await MusicBridge.shared.getPlaybackQueue()
                                    self.sendEvent("queue", data: queue, to: c)
                                }
                            }
                        } else {
                            // Brand-new UID that hasn't sent register_device yet:
                            // do NOT pre-create a fake "mobile" record before register_device arrives with real device_type & lock_screen_controls.
                            ClientDeviceManager.shared.markBrowserConnectionPending(connectionId: clientId)
                        }
                    } else if hasValidInvite {
                        let generatedUid = UUID().uuidString.lowercased()
                        let record = ClientDeviceManager.shared.registerConnection(
                            connectionId: clientId,
                            deviceId: generatedUid,
                            deviceName: "Invited Client",
                            deviceType: "mobile",
                            preferredLockScreen: nil,
                            remoteIP: remoteIP,
                            inviteToken: wsInviteToken
                        )
                        self.sendEvent(name: "device_auth_status", data: record.dictionary, to: c)
                        if record.isAuthorized {
                            let status = MusicBridge.shared.getPlayerStatus()
                            self.sendEvent("player_state_changed", data: status, to: c)
                            Task {
                                let queue = await MusicBridge.shared.getPlaybackQueue()
                                self.sendEvent("queue", data: queue, to: c)
                            }
                        }
                    } else if !isLoopback || ua.contains("Mozilla/") {
                        // Non-loopback client or browser tab without valid cookie or invite token:
                        // mark pending registration so it cannot bypass PWA device authorization by omitting register_device.
                        ClientDeviceManager.shared.markBrowserConnectionPending(connectionId: clientId)
                    } else {
                        // Localhost headless / Node.js / API WebSocket client without PWA cookie:
                        // send initial status & queue immediately for API compatibility.
                        let status = MusicBridge.shared.getPlayerStatus()
                        self.sendEvent("player_state_changed", data: status, to: c)
                        Task {
                            let queue = await MusicBridge.shared.getPlaybackQueue()
                            self.sendEvent("queue", data: queue, to: c)
                        }
                    }

                    self.readWebSocketFrames(clientId: clientId, connection: c, buffer: restData)
                }))
                return
            }

            // Normal HTTP request
            var expectedBodyLen = 0
            if let clStr = self.extractHeader(named: "content-length", from: headerString) {
                guard let rawLen = Int(clStr.trimmingCharacters(in: .whitespacesAndNewlines)),
                      rawLen >= 0,
                      rawLen <= 16 * 1024 * 1024 else {
                    conn.cancel()
                    return
                }
                expectedBodyLen = max(0, min(rawLen, 16 * 1024 * 1024))
            }

            if restData.count < expectedBodyLen {
                self.readRemainingHTTPBody(clientId: clientId, connection: conn, headerString: headerString, buffer: restData, expectedLen: expectedBodyLen)
            } else {
                let bodySlice = expectedBodyLen > 0 ? Data(restData.prefix(expectedBodyLen)) : Data()
                self.handleHTTPRequest(headerString: headerString, bodyData: bodySlice, connection: conn)
            }
        }
    }

    private func readRemainingHTTPBody(clientId: UUID, connection: NWConnection, headerString: String, buffer: Data, expectedLen: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 524288) { [weak self, weak connection] content, _, isComplete, error in
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
            if current.count > 16 * 1024 * 1024 {
                conn.cancel()
                return
            }
            if current.count >= expectedLen || isComplete {
                let bodySlice = expectedLen > 0 ? Data(current.prefix(expectedLen)) : Data()
                self.handleHTTPRequest(headerString: headerString, bodyData: bodySlice, connection: conn)
            } else {
                self.readRemainingHTTPBody(clientId: clientId, connection: conn, headerString: headerString, buffer: current, expectedLen: expectedLen)
            }
        }
    }

    private func readWebSocketFrames(clientId: UUID, connection: NWConnection, buffer: Data) {
        var current = buffer
        var oversizedFrame = false
        let frames = decodeWebSocketFrames(buffer: &current, oversizedFrame: &oversizedFrame)
        if oversizedFrame {
            NSLog("[WebSocket] ❌ Closing connection due to oversized or malformed frame")
            removeClient(clientId: clientId, connection: connection)
            connection.cancel()
            return
        }

        let connKey = ObjectIdentifier(connection)
        for (opcode, payload, fin) in frames {
            switch opcode {
            case 0x01, 0x02:
                var protocolError = false
                clientLock.lock()
                if fragmentBuffers[connKey] != nil || clients[clientId] == nil {
                    fragmentBuffers.removeValue(forKey: connKey)
                    protocolError = true
                } else if !fin {
                    if payload.count > 16 * 1024 * 1024 {
                        protocolError = true
                    } else {
                        fragmentBuffers[connKey] = (opcode: opcode, data: payload)
                    }
                }
                clientLock.unlock()

                if protocolError {
                    removeClient(clientId: clientId, connection: connection)
                    connection.cancel()
                    return
                }

                if fin {
                    if opcode == 0x01 {
                        if let text = String(data: payload, encoding: .utf8) {
                            Task {
                                await self.processClientTextMessage(text, clientId: clientId, connection: connection)
                            }
                        }
                    } else {
                        Task {
                            await self.processClientBinaryMessage(payload, clientId: clientId, connection: connection)
                        }
                    }
                }
            case 0x00:
                var completedMessage: (opcode: UInt8, data: Data)? = nil
                var protocolOrSizeError = false
                clientLock.lock()
                if clients[clientId] != nil, var existing = fragmentBuffers[connKey] {
                    if existing.data.count + payload.count > 16 * 1024 * 1024 {
                        fragmentBuffers.removeValue(forKey: connKey)
                        protocolOrSizeError = true
                    } else {
                        existing.data.append(payload)
                        if fin {
                            fragmentBuffers.removeValue(forKey: connKey)
                            completedMessage = existing
                        } else {
                            fragmentBuffers[connKey] = existing
                        }
                    }
                } else {
                    fragmentBuffers.removeValue(forKey: connKey)
                    protocolOrSizeError = true
                }
                clientLock.unlock()
                if protocolOrSizeError {
                    removeClient(clientId: clientId, connection: connection)
                    connection.cancel()
                    return
                }
                if let msg = completedMessage {
                    if msg.opcode == 0x01 {
                        if let text = String(data: msg.data, encoding: .utf8) {
                            Task {
                                await self.processClientTextMessage(text, clientId: clientId, connection: connection)
                            }
                        }
                    } else if msg.opcode == 0x02 {
                        Task {
                            await self.processClientBinaryMessage(msg.data, clientId: clientId, connection: connection)
                        }
                    }
                }
            case 0x08:
                removeClient(clientId: clientId, connection: connection)
                return
            case 0x09:
                let pong = makeWebSocketFrame(payload: payload, opcode: 0x0A)
                sendLock.lock()
                defer { sendLock.unlock() }
                connection.send(content: pong, completion: .contentProcessed({ _ in }))
            case 0x0A:
                break
            default:
                break
            }
        }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] content, _, isComplete, error in
            guard let self = self, let conn = connection else { return }
            if error != nil {
                self.removeClient(clientId: clientId, connection: conn)
                return
            }
            if isComplete {
                self.removeClient(clientId: clientId, connection: conn)
                return
            }
            var next = current
            if let data = content {
                next.append(data)
            }
            self.readWebSocketFrames(clientId: clientId, connection: conn, buffer: next)
        }
    }

    internal func decodeWebSocketFrames(buffer: inout Data) -> [(opcode: UInt8, payload: Data, fin: Bool)] {
        var oversized = false
        return decodeWebSocketFrames(buffer: &buffer, oversizedFrame: &oversized)
    }

    internal func decodeWebSocketFrames(buffer: inout Data, oversizedFrame: inout Bool) -> [(opcode: UInt8, payload: Data, fin: Bool)] {
        var results: [(opcode: UInt8, payload: Data, fin: Bool)] = []
        while buffer.count >= 2 {
            let b0 = buffer[buffer.startIndex]
            let fin = (b0 & 0x80) != 0
            let opcode = b0 & 0x0F
            let b1 = buffer[buffer.startIndex + 1]
            let isMasked = (b1 & 0x80) != 0
            var payloadLen = UInt64(b1 & 0x7F)
            var offset = 2

            // RFC 6455 §5.5: Control frames (opcode >= 0x08) MUST NOT be fragmented (!fin)
            // and MUST have a payload length of 125 bytes or less.
            if opcode >= 0x08 && (!fin || payloadLen > 125) {
                oversizedFrame = true
                buffer.removeAll()
                return []
            }

            if payloadLen == 126 {
                guard buffer.count >= offset + 2 else { break }
                let high = UInt64(buffer[buffer.startIndex + offset])
                let low = UInt64(buffer[buffer.startIndex + offset + 1])
                payloadLen = (high << 8) | low
                offset += 2
            } else if payloadLen == 127 {
                guard buffer.count >= offset + 8 else { break }
                var len: UInt64 = 0
                for i in 0..<8 {
                    len = (len << 8) | UInt64(buffer[buffer.startIndex + offset + i])
                }
                guard len <= UInt64(16 * 1024 * 1024) else {
                    oversizedFrame = true
                    buffer.removeAll()
                    break
                }
                payloadLen = len
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

            results.append((opcode: opcode, payload: unmasked, fin: fin))
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
        let lines = headerString.components(separatedBy: .newlines)
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
            let trackName = status.track?.name ?? ""
            let trackArtist = status.track?.artist ?? ""
            let trackCompositeKey = (!trackId.isEmpty || !trackName.isEmpty) ? "\(trackId)|\(trackName)|\(trackArtist)" : ""

            let stateChanged = (state != self.lastKnownState)
            let trackChanged = (!trackCompositeKey.isEmpty && trackCompositeKey != self.lastKnownTrackId)
            let posJumped = abs(pos - self.lastKnownPosition) > 2.5
            let isPlaying = (state == "playing")

            if stateChanged || trackChanged || posJumped || (isPlaying && Date().timeIntervalSince(self.lastBroadcastTime) >= 3.0) {
                self.lastKnownState = state
                self.lastKnownPosition = pos
                if !trackCompositeKey.isEmpty {
                    self.lastKnownTrackId = trackCompositeKey
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

    private func isPrivateOrLocalHost(_ rawHost: String) -> Bool {
        var host = rawHost
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
        if let pct = host.firstIndex(of: "%") {
            host = String(host[..<pct])
        }
        guard !host.isEmpty else { return false }
        if host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "::ffff:127.0.0.1"
            || host.hasSuffix(".local") || host.hasSuffix(".lan") || host.hasSuffix(".home") {
            return true
        }
        if host.hasPrefix("fe80:") || ((host.hasPrefix("fc") || host.hasPrefix("fd")) && host.contains(":")) {
            return true
        }
        let ipv4Candidate = host.hasPrefix("::ffff:") ? String(host.dropFirst("::ffff:".count)) : host
        let parts = ipv4Candidate.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 4 {
            var octets: [Int] = []
            for p in parts {
                guard let val = Int(p), (0...255).contains(val), String(val) == p else {
                    return false
                }
                octets.append(val)
            }
            if octets[0] == 10 || octets[0] == 127 { return true }
            if octets[0] == 192 && octets[1] == 168 { return true }
            if octets[0] == 172 && (16...31).contains(octets[1]) { return true }
            if octets[0] == 100 && (64...127).contains(octets[1]) { return true }
            if octets[0] == 169 && octets[1] == 254 { return true }
        }
        return false
    }

    public func isAllowedWebSocketOrigin(_ origin: String, requestHost: String? = nil) -> Bool {
        let trimmed = origin.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == "null" {
            return false
        }
        if trimmed.isEmpty || trimmed.hasPrefix("file://") || trimmed.hasPrefix("capacitor://") || trimmed.hasPrefix("ionic://") {
            return true
        }
        guard let url = URL(string: trimmed), let rawHost = url.host?.lowercased(), !rawHost.isEmpty else {
            return false
        }
        var host = rawHost.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        if let pct = host.firstIndex(of: "%") {
            host = String(host[..<pct])
        }
        guard isPrivateOrLocalHost(host) else {
            return false
        }
        if let rawReqHost = requestHost?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !rawReqHost.isEmpty {
            var reqHostOnly: String
            var reqPort: Int? = nil
            if rawReqHost.hasPrefix("["), let closeBracket = rawReqHost.firstIndex(of: "]") {
                reqHostOnly = String(rawReqHost[rawReqHost.index(after: rawReqHost.startIndex)..<closeBracket])
                let afterBracket = rawReqHost[rawReqHost.index(after: closeBracket)...]
                if afterBracket.hasPrefix(":") {
                    reqPort = Int(afterBracket.dropFirst())
                }
            } else {
                let colonParts = rawReqHost.split(separator: ":", omittingEmptySubsequences: false)
                if colonParts.count == 2, let p = Int(colonParts[1]) {
                    reqHostOnly = String(colonParts[0])
                    reqPort = p
                } else {
                    reqHostOnly = rawReqHost
                }
            }
            if let pct = reqHostOnly.firstIndex(of: "%") {
                reqHostOnly = String(reqHostOnly[..<pct])
            }
            guard isPrivateOrLocalHost(reqHostOnly) else {
                return false
            }
            let defaultPort = (url.scheme == "https" || url.scheme == "wss") ? 443 : 80
            if (url.port != nil || reqPort != nil) && (url.port ?? defaultPort) != (reqPort ?? defaultPort) {
                return false
            }
            if host == reqHostOnly {
                return true
            }
            let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "::ffff:127.0.0.1"]
            if loopbackHosts.contains(host) && loopbackHosts.contains(reqHostOnly) {
                return true
            }
            return false
        }
        return true
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