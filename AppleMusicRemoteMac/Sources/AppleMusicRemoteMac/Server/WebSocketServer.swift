//
//  WebSocketServer.swift
//  AppleMusicRemoteMac
//
//  Pure Swift HTTP & WebSocket Server using Network.framework (NWListener)
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

    public static let maxConcurrentTCPConnections = 128
    public static let maxPendingOutboundFrames = 64
    public static let maxQueuedClientMessages = 64

    public weak var delegate: WebSocketServerDelegate?

    var listener: NWListener?
    var activeTCPConnections: [UUID: NWConnection] = [:]
    var clients: [UUID: NWConnection] = [:]
    var clientHostAddresses: [UUID: String] = [:]
    var liveStreamConnections: [UUID: NWConnection] = [:]
    var headRequestConnections: Set<ObjectIdentifier> = []
    var connectionQueues: [ObjectIdentifier: DispatchQueue] = [:]
    var connectionClientIds: [ObjectIdentifier: UUID] = [:]
    var keepAliveIdleTimers: [ObjectIdentifier: DispatchWorkItem] = [:]
    var keepAliveStateByConnection: [ObjectIdentifier: (keepAlive: Bool, trailingBuffer: Data)] = [:]
    var fragmentBuffers: [ObjectIdentifier: (opcode: UInt8, data: Data)] = [:]
    var pendingOutboundFrames: [ObjectIdentifier: Int] = [:]
    var clientMessageQueues: [UUID: [String]] = [:]
    var activeClientWorkers: [UUID: Task<Void, Never>] = [:]

    let httpConnectionTargetQueue = DispatchQueue(
        label: "com.amr.server.connections",
        qos: .userInitiated,
        attributes: .concurrent
    )

    let liveStreamLock = NSLock()
    let clientLock = NSRecursiveLock()
    let sendLock = NSRecursiveLock()
    let clientQueueLock = NSLock()
    let curateTaskLock = NSLock()
    var activeCurateTasks: [UUID: Task<Void, Never>] = [:]

    private var _isRunning = false
    var isRunning: Bool {
        get {
            clientLock.lock()
            defer { clientLock.unlock() }
            return _isRunning
        }
        set {
            clientLock.lock()
            _isRunning = newValue
            clientLock.unlock()
        }
    }

    public private(set) var port: Int = 8080

    public var hasActiveLiveStreamConnections: Bool {
        liveStreamLock.lock()
        defer { liveStreamLock.unlock() }
        return !liveStreamConnections.isEmpty
    }

    public func closeLiveStreamConnections() {
        liveStreamLock.lock()
        let conns = Array(liveStreamConnections.values)
        liveStreamConnections.removeAll()
        liveStreamLock.unlock()
        for conn in conns {
            conn.cancel()
        }
        if !conns.isEmpty {
            NSLog("[WebSocketServer] 🔌 Closed %d active live audio stream connection(s).", conns.count)
        }
    }

    @discardableResult
    internal func removeLiveStreamConnection(id: UUID) -> NWConnection? {
        liveStreamLock.lock()
        let removed = liveStreamConnections.removeValue(forKey: id)
        liveStreamLock.unlock()
        return removed
    }

    internal func liveStreamConnection(id: UUID) -> NWConnection? {
        liveStreamLock.lock()
        let conn = liveStreamConnections[id]
        liveStreamLock.unlock()
        return conn
    }

    internal func clientConnection(for clientId: UUID) -> NWConnection? {
        clientLock.lock()
        let conn = clients[clientId]
        clientLock.unlock()
        return conn
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
                if UPnPMediaRendererServer.shared.hasActiveSubscribers {
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.3) { [weak self] in
                        PlaybackStateStore.shared.invalidateStatusCache()
                        self?.broadcastStatus(includeQueue: false)
                    }
                }
            }
            self.notifDebounceItem = work
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2, execute: work)
        }

        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.Music.playerInfo"), object: nil, queue: notifQueue, using: handler)
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.iTunes.playerInfo"), object: nil, queue: notifQueue, using: handler)

        NotificationCenter.default.addObserver(forName: .bitPerfectFormatDidChange, object: nil, queue: notifQueue) { [weak self] _ in
            guard let self = self else { return }
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
                    self.clientLock.lock()
                    self._isRunning = false
                    self.clientLock.unlock()
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
            self._isRunning = true

            startPollerTimer()

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
        closeLiveStreamConnections()

        if let l = listener {
            l.cancel()
            self.listener = nil
        }

        for (_, conn) in activeTCPConnections {
            conn.cancel()
        }
        for (_, conn) in clients {
            conn.cancel()
        }
        activeTCPConnections.removeAll()
        clients.removeAll()
        clientHostAddresses.removeAll()
        headRequestConnections.removeAll()
        fragmentBuffers.removeAll()

        sendLock.lock()
        pendingOutboundFrames.removeAll()
        sendLock.unlock()

        cancelAllClientWorkers()
        cancelAllCurateTasks()
        _isRunning = false
        delegate?.webSocketServer(self, didUpdateClientCount: 0)
    }

    public var clientCount: Int {
        clientLock.lock()
        defer { clientLock.unlock() }
        return clients.count
    }

    // MARK: - Connection & Handshake Handling

    private func handleNewConnection(_ connection: NWConnection) {
        let clientId = UUID()

        clientLock.lock()
        if activeTCPConnections.count >= Self.maxConcurrentTCPConnections {
            clientLock.unlock()
            NSLog("[Server] ⚠️ Rejecting connection: max concurrent TCP connections (%d) reached", Self.maxConcurrentTCPConnections)
            connection.cancel()
            return
        }
        activeTCPConnections[clientId] = connection
        clientLock.unlock()

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

        let queue = DispatchQueue(
            label: "com.amr.server.client.\(clientId.uuidString)",
            qos: .userInitiated,
            target: httpConnectionTargetQueue
        )
        let objId = ObjectIdentifier(connection)
        clientLock.lock()
        connectionQueues[objId] = queue
        connectionClientIds[objId] = clientId
        clientLock.unlock()

        connection.start(queue: queue)

        // Guard against idle / slowloris TCP connections that never complete handshake or HTTP request
        scheduleConnectionIdleTimeout(clientId: clientId, connection: connection, seconds: 30.0)
    }

    internal static func shouldKeepHTTPConnectionAlive(headerString: String) -> Bool {
        let firstLine = (headerString.components(separatedBy: "\r\n").first
            ?? headerString.components(separatedBy: "\n").first
            ?? "").uppercased()
        var connHeaderValue: String? = nil
        for line in headerString.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix("connection:") {
                connHeaderValue = String(trimmed.dropFirst("connection:".count)).trimmingCharacters(in: .whitespaces).lowercased()
                break
            }
        }
        if let connVal = connHeaderValue {
            if connVal.contains("close") { return false }
            if connVal.contains("keep-alive") { return true }
        }
        return firstLine.contains("HTTP/1.1")
    }

    internal func scheduleConnectionIdleTimeout(clientId: UUID, connection: NWConnection, seconds: TimeInterval) {
        let objId = ObjectIdentifier(connection)
        let work = DispatchWorkItem { [weak self, weak connection] in
            guard let self = self, let conn = connection else { return }
            let isUpgradedWS: Bool = {
                self.clientLock.lock()
                defer { self.clientLock.unlock() }
                return self.clients[clientId] != nil
            }()
            let isLiveStream: Bool = {
                self.liveStreamLock.lock()
                defer { self.liveStreamLock.unlock() }
                return self.liveStreamConnections.values.contains(where: { $0 === conn })
            }()
            if !isUpgradedWS && !isLiveStream {
                self.untrackTCPConnection(conn)
                conn.cancel()
                self.removeClient(clientId: clientId, connection: conn)
            }
        }
        clientLock.lock()
        keepAliveIdleTimers[objId]?.cancel()
        keepAliveIdleTimers[objId] = work
        let targetQ = connectionQueues[objId] ?? httpConnectionTargetQueue
        clientLock.unlock()
        targetQ.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    internal func cancelConnectionIdleTimeout(for connection: NWConnection) {
        let objId = ObjectIdentifier(connection)
        clientLock.lock()
        keepAliveIdleTimers.removeValue(forKey: objId)?.cancel()
        clientLock.unlock()
    }

    internal func isKeepAliveEnabled(for connection: NWConnection) -> Bool {
        let objId = ObjectIdentifier(connection)
        clientLock.lock()
        defer { clientLock.unlock() }
        return keepAliveStateByConnection[objId]?.keepAlive ?? false
    }

    internal func finishHTTPResponseCycle(connection: NWConnection, forceClose: Bool = false) {
        let objId = ObjectIdentifier(connection)
        clientLock.lock()
        let state = keepAliveStateByConnection.removeValue(forKey: objId)
        let clientId = connectionClientIds[objId]
        let connQueue = connectionQueues[objId]
        clientLock.unlock()

        if !forceClose, let state, state.keepAlive, let clientId {
            scheduleConnectionIdleTimeout(clientId: clientId, connection: connection, seconds: 15.0)
            let nextBuf = state.trailingBuffer
            if let q = connQueue {
                q.async { [weak self, weak connection] in
                    guard let self = self, let c = connection else { return }
                    self.readInitialConnection(clientId: clientId, connection: c, buffer: nextBuf)
                }
            } else {
                readInitialConnection(clientId: clientId, connection: connection, buffer: nextBuf)
            }
        } else {
            untrackTCPConnection(connection)
            connection.cancel()
        }
    }

    internal func untrackTCPConnection(_ connection: NWConnection) {
        let objId = ObjectIdentifier(connection)
        clientLock.lock()
        if let match = activeTCPConnections.first(where: { $0.value === connection })?.key {
            activeTCPConnections.removeValue(forKey: match)
        }
        headRequestConnections.remove(objId)
        keepAliveIdleTimers.removeValue(forKey: objId)?.cancel()
        keepAliveStateByConnection.removeValue(forKey: objId)
        connectionQueues.removeValue(forKey: objId)
        connectionClientIds.removeValue(forKey: objId)
        clientLock.unlock()
        sendLock.lock()
        pendingOutboundFrames.removeValue(forKey: objId)
        sendLock.unlock()
    }

    internal func removeClient(clientId: UUID, connection: NWConnection? = nil) {
        clientLock.lock()
        activeTCPConnections.removeValue(forKey: clientId)
        let conn = clients.removeValue(forKey: clientId)
        clientHostAddresses.removeValue(forKey: clientId)
        if let c = conn ?? connection {
            let objId = ObjectIdentifier(c)
            headRequestConnections.remove(objId)
            keepAliveIdleTimers.removeValue(forKey: objId)?.cancel()
            keepAliveStateByConnection.removeValue(forKey: objId)
            connectionQueues.removeValue(forKey: objId)
            connectionClientIds.removeValue(forKey: objId)
            fragmentBuffers.removeValue(forKey: objId)
            sendLock.lock()
            pendingOutboundFrames.removeValue(forKey: objId)
            sendLock.unlock()
        }
        let count = clients.count
        clientLock.unlock()

        cancelClientWorker(for: clientId)
        cancelCurateTask(for: clientId)
        RoomAcousticService.shared.stopTestSignalIfInitiatedBy(clientID: clientId)

        guard let conn = conn else { return }

        ClientDeviceManager.shared.unregisterConnection(connectionId: clientId)
        conn.cancel()
        NSLog("[WebSocket] Client disconnected. Total clients: %d", count)
        delegate?.webSocketServer(self, didUpdateClientCount: count)
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
                self.removeClient(clientId: clientId, connection: conn)
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
                    self.untrackTCPConnection(conn)
                    conn.cancel()
                    self.removeClient(clientId: clientId, connection: conn)
                    return
                }
                if current.count > 65536 {
                    self.untrackTCPConnection(conn)
                    conn.cancel()
                    self.removeClient(clientId: clientId, connection: conn)
                    return
                }
                self.readInitialConnection(clientId: clientId, connection: conn, buffer: current)
                return
            }

            self.cancelConnectionIdleTimeout(for: conn)
            let headerData = current.subdata(in: current.startIndex..<delim.lowerBound)
            let restData = current.subdata(in: delim.upperBound..<current.endIndex)
            guard let headerString = String(data: headerData, encoding: .utf8) else {
                conn.cancel()
                self.removeClient(clientId: clientId, connection: conn)
                return
            }

            let hostHeader = self.extractHeader(named: "host", from: headerString)
            guard self.isValidHostHeader(hostHeader) else {
                NSLog("[Server] ❌ Rejected connection with disallowed Host header: %@", hostHeader ?? "<missing>")
                let forbidden = "HTTP/1.1 403 Forbidden\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                conn.send(content: Data(forbidden.utf8), completion: .contentProcessed({ [weak self, weak conn] _ in
                    if let c = conn {
                        self?.untrackTCPConnection(c)
                        c.cancel()
                    }
                }))
                return
            }

            let isWSUpgrade = (self.extractHeader(named: "upgrade", from: headerString)?.lowercased().contains("websocket") == true)
            if isWSUpgrade, let key = self.extractHeader(named: "sec-websocket-key", from: headerString) {
                if let origin = self.extractHeader(named: "origin", from: headerString),
                   !self.isAllowedWebSocketOrigin(origin, requestHost: hostHeader) {
                    NSLog("[WebSocket] ❌ Rejected connection from untrusted Origin: %@", origin)
                    let forbidden = "HTTP/1.1 403 Forbidden\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                    conn.send(content: Data(forbidden.utf8), completion: .contentProcessed({ [weak self, weak conn] _ in
                        if let c = conn {
                            self?.untrackTCPConnection(c)
                            c.cancel()
                        }
                    }))
                    return
                }
                let accept = self.webSocketAccept(for: key)
                let response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
                conn.send(content: Data(response.utf8), completion: .contentProcessed({ [weak self, weak conn] _ in
                    guard let self = self, let c = conn else { return }
                    self.completeWebSocketHandshake(clientId: clientId, connection: c, headerString: headerString, restData: restData)
                }))
                return
            }

            // Normal HTTP request
            var expectedBodyLen = 0
            if let clStr = self.extractHeader(named: "content-length", from: headerString) {
                guard let rawLen = Int(clStr.trimmingCharacters(in: .whitespacesAndNewlines)),
                      rawLen >= 0,
                      rawLen <= 16 * 1024 * 1024 else {
                    self.untrackTCPConnection(conn)
                    conn.cancel()
                    return
                }
                expectedBodyLen = max(0, min(rawLen, 16 * 1024 * 1024))
            }

            let wantsKeepAlive = Self.shouldKeepHTTPConnectionAlive(headerString: headerString)
            if restData.count < expectedBodyLen {
                self.readRemainingHTTPBody(
                    clientId: clientId,
                    connection: conn,
                    headerString: headerString,
                    buffer: restData,
                    expectedLen: expectedBodyLen,
                    wantsKeepAlive: wantsKeepAlive
                )
            } else {
                let bodySlice = expectedBodyLen > 0 ? Data(restData.prefix(expectedBodyLen)) : Data()
                let trailing = restData.count > expectedBodyLen ? Data(restData.dropFirst(expectedBodyLen)) : Data()
                let objId = ObjectIdentifier(conn)
                self.clientLock.lock()
                self.keepAliveStateByConnection[objId] = (keepAlive: wantsKeepAlive && !isComplete, trailingBuffer: trailing)
                self.clientLock.unlock()
                self.handleHTTPRequest(headerString: headerString, bodyData: bodySlice, connection: conn)
            }
        }
    }

    private func completeWebSocketHandshake(clientId: UUID, connection c: NWConnection, headerString: String, restData: Data) {
        let remoteIP = extractRemoteIP(from: c)
        clientLock.lock()
        clients[clientId] = c
        clientHostAddresses[clientId] = remoteIP
        let count = clients.count
        clientLock.unlock()

        NSLog("[WebSocket] Handshake complete. Total WebSocket clients: %d", count)
        delegate?.webSocketServer(self, didUpdateClientCount: count)

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

        let cookieUid = nonEmpty(extractCookie(named: "amr_device_uid", from: headerString))
        let wsDeviceSecret = nonEmpty(extractHeader(named: "x-amr-device-secret", from: headerString))
            ?? nonEmpty(extractCookie(named: "amr_device_secret", from: headerString))
        let apiTokenHeader = nonEmpty(extractHeader(named: "authorization", from: headerString))
            ?? nonEmpty(extractHeader(named: "x-amr-api-token", from: headerString))
        let hasOrigin = (nonEmpty(extractHeader(named: "origin", from: headerString)) != nil)
        let hasValidInvite = ClientDeviceManager.shared.validateInviteToken(wsInviteToken)

        if let cookieUid {
            if let existing = ClientDeviceManager.shared.getDevice(deviceId: cookieUid) {
                let record = ClientDeviceManager.shared.registerConnection(
                    connectionId: clientId,
                    deviceId: cookieUid,
                    deviceName: existing.deviceName,
                    deviceType: existing.deviceType,
                    preferredLockScreen: existing.lockScreenControls,
                    remoteIP: remoteIP,
                    inviteToken: wsInviteToken,
                    deviceSecret: wsDeviceSecret
                )
                sendEvent(name: "device_auth_status", data: record.dictionaryWithSecret, to: c)
                if record.isAuthorized {
                    pushInitialAuthorizedSnapshot(clientId: clientId)
                }
            } else if hasValidInvite {
                let record = ClientDeviceManager.shared.registerConnection(
                    connectionId: clientId,
                    deviceId: cookieUid,
                    deviceName: "Invited Client",
                    deviceType: "mobile",
                    preferredLockScreen: nil,
                    remoteIP: remoteIP,
                    inviteToken: wsInviteToken,
                    deviceSecret: wsDeviceSecret
                )
                sendEvent(name: "device_auth_status", data: record.dictionaryWithSecret, to: c)
                if record.isAuthorized {
                    pushInitialAuthorizedSnapshot(clientId: clientId)
                }
            } else {
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
            sendEvent(name: "device_auth_status", data: record.dictionaryWithSecret, to: c)
            if record.isAuthorized {
                pushInitialAuthorizedSnapshot(clientId: clientId)
            }
        } else if !hasOrigin && ClientDeviceManager.shared.validateLocalAPIToken(apiTokenHeader) {
            pushInitialAuthorizedSnapshot(clientId: clientId)
        } else {
            // S-04: Mark ALL unauthenticated TCP WebSocket connections (including loopback) pending authorization
            ClientDeviceManager.shared.markBrowserConnectionPending(connectionId: clientId)
        }

        readWebSocketFrames(clientId: clientId, connection: c, buffer: restData)
    }

    internal func pushInitialAuthorizedSnapshot(clientId: UUID) {
        Task(priority: .utility) { [weak self] in
            guard let self = self, let conn = self.clientConnection(for: clientId) else { return }
            let status = MusicBridge.shared.getPlayerStatus()
            self.sendEvent("player_state_changed", data: status, to: conn)
            self.sendEvent(name: "ai_curator_settings", data: NativeMusicCuratorService.shared.getSettingsDictionary(), to: conn)
            self.sendEvent(name: "dsp_settings", data: Self.buildDSPSettingsDictionary(), to: conn)
            self.sendEvent(name: "tv_library_config", data: TVLibraryConfigurationStore.shared.toDictionary(), to: conn)
            let queue = await MusicBridge.shared.getPlaybackQueue()
            guard let activeConn = self.clientConnection(for: clientId) else { return }
            self.sendEvent("queue", data: queue, to: activeConn)
        }
    }

    private func readRemainingHTTPBody(
        clientId: UUID,
        connection: NWConnection,
        headerString: String,
        buffer: Data,
        expectedLen: Int,
        wantsKeepAlive: Bool
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 524288) { [weak self, weak connection] content, _, isComplete, error in
            guard let self = self, let conn = connection else { return }
            if let error = error {
                NSLog("[Server] HTTP body receive error: %@", error.localizedDescription)
                self.untrackTCPConnection(conn)
                conn.cancel()
                return
            }
            var current = buffer
            if let data = content {
                current.append(data)
            }
            if current.count > 16 * 1024 * 1024 {
                self.untrackTCPConnection(conn)
                conn.cancel()
                return
            }
            if current.count >= expectedLen || isComplete {
                let bodySlice = expectedLen > 0 ? Data(current.prefix(expectedLen)) : Data()
                let trailing = current.count > expectedLen ? Data(current.dropFirst(expectedLen)) : Data()
                let objId = ObjectIdentifier(conn)
                self.clientLock.lock()
                self.keepAliveStateByConnection[objId] = (keepAlive: wantsKeepAlive && !isComplete, trailingBuffer: trailing)
                self.clientLock.unlock()
                self.handleHTTPRequest(headerString: headerString, bodyData: bodySlice, connection: conn)
            } else {
                self.readRemainingHTTPBody(
                    clientId: clientId,
                    connection: conn,
                    headerString: headerString,
                    buffer: current,
                    expectedLen: expectedLen,
                    wantsKeepAlive: wantsKeepAlive
                )
            }
        }
    }

    // MARK: - Periodic Monitoring Timer

    private func startPollerTimer() {
        stopPollerTimer()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 3.0, repeating: 3.0)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            guard self.clientCount > 0
                || WLEDDDPController.shared.isActivelyStreaming
                || UPnPMediaRendererServer.shared.hasActiveSubscribers
                || DLNADiscoveryManager.shared.hasActiveRenderer else { return }
            guard MusicAppLifecycleManager.shared.isHealthy else { return }
            if PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.isTransitioningTrack }) {
                return
            }

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
}
