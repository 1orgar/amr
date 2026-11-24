//
//  UPnPMediaRendererServer.swift
//  AppleMusicRemoteMac
//
//  UPnP / DLNA MediaRenderer HTTP Server on Port 8090.
//  Enforces same-subnet unicast peer guard, <=64 concurrent connection cap,
//  zombie-free listener restart, and safe non-trapping hash magnitudes.
//

import Foundation
import Network

public final class UPnPMediaRendererServer: @unchecked Sendable {
    public static let shared = UPnPMediaRendererServer()

    private static let maxActiveConnections = 64

    internal struct EventSubscription {
        let sid: String
        let callbackURL: URL
        let path: String
        var seq: UInt32
        var expiryDate: Date
        var failureCount: Int
    }

    public private(set) var port: UInt16 = 8090
    internal var listener: NWListener?
    internal let listenerLock = NSLock()
    internal let queue = DispatchQueue(label: "org.ksholokhov.amr.upnp.http", qos: .utility)
    internal var activeConnections: [NWConnection] = []
    internal let connectionsLock = NSLock()

    // Optimistic tracking for instantaneous Home Assistant response & seek stabilization
    internal var optimisticState: String?
    internal var optimisticStateDate: Date = .distantPast

    internal var optimisticPosition: Double?
    internal var optimisticPositionDate: Date = .distantPast
    internal var optimisticPositionIsPlaying: Bool = false
    internal let stateLock = NSLock()

    internal var lastNotifiedState: String?
    internal var lastNotifiedTrackId: String?
    internal var lastNotifiedArtworkUrl: String?
    internal var lastNotifiedTrackTitle: String?
    internal var lastNotifiedDurationSec: Int = -1
    internal var lastNotifiedPositionSec: Double = 0
    internal var lastNotifiedPlayMode: String?
    internal var lastNotifiedVolume: Int?
    internal var lastNotifiedMute: Bool?
    internal var lastNotifiedTime: Date = .distantPast
    internal var preMuteVolume: Int = 50
    internal var cachedActiveSubscriberCount: Int = 0

    public var hasActiveSubscribers: Bool {
        stateLock.withLock { cachedActiveSubscriberCount > 0 }
    }

    internal var subscriptions: [EventSubscription] = []
    internal let subQueue = DispatchQueue(label: "org.ksholokhov.amr.upnp.gena")

    private var cachedArtworkData: (key: String, data: Data, contentType: String)?
    private let artworkLock = NSLock()
    private var isRestarting = false
    private var restartWorkItem: DispatchWorkItem?

    public static let defaultsKey = "LocalUPnPRendererEnabled"

    public var isEnabled: Bool {
        get {
            if AppStorageProvider.shared.object(forKey: Self.defaultsKey) == nil {
                return true
            }
            return AppStorageProvider.shared.bool(forKey: Self.defaultsKey)
        }
        set {
            AppStorageProvider.shared.set(newValue, forKey: Self.defaultsKey)
        }
    }

    private init() {}

    @discardableResult
    public func startIfEnabled(port: UInt16 = 8090) -> Bool {
        guard isEnabled else {
            NSLog("[UPnPMediaRendererServer] ⏸️ Local UPnP/DLNA MediaRenderer is disabled in settings.")
            return false
        }
        let ok = start(port: port)
        if ok {
            SSDPService.shared.start(httpPort: port)
        }
        return ok
    }

    public func setEnabled(_ enabled: Bool, port: UInt16 = 8090) {
        isEnabled = enabled
        if enabled {
            _ = startIfEnabled(port: port)
        } else {
            stop()
            SSDPService.shared.stop()
            NSLog("[UPnPMediaRendererServer] ⏹ Local UPnP/DLNA MediaRenderer & SSDP stopped.")
        }
    }

    public func start(port: UInt16 = 8090) -> Bool {
        listenerLock.lock()
        self.port = port
        self.restartWorkItem?.cancel()
        self.restartWorkItem = nil
        self.isRestarting = false
        if let existing = self.listener {
            existing.stateUpdateHandler = nil
            existing.cancel()
            self.listener = nil
        }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            listenerLock.unlock()
            return false
        }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: nwPort)
            self.listener = listener
            listenerLock.unlock()

            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    NSLog("[UPnPMediaRendererServer] ✅ HTTP UPnP Server listening on port %u", port)
                case .failed(let err):
                    NSLog("[UPnPMediaRendererServer] ❌ Listener failed: %@", err.localizedDescription)
                    self?.scheduleRestart()
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            listener.start(queue: queue)
            return true
        } catch {
            listenerLock.unlock()
            NSLog("[UPnPMediaRendererServer] ❌ Failed to create NWListener: %@", error.localizedDescription)
            return false
        }
    }

    private func scheduleRestart() {
        queue.async { [weak self] in
            guard let self = self, self.isEnabled, !self.isRestarting else { return }
            self.isRestarting = true
            self.listenerLock.lock()
            self.listener?.stateUpdateHandler = nil
            self.listener?.cancel()
            self.listener = nil
            let currentPort = self.port
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.listenerLock.lock()
                self.restartWorkItem = nil
                self.isRestarting = false
                self.listenerLock.unlock()
                guard self.isEnabled else { return }
                _ = self.start(port: currentPort)
            }
            self.restartWorkItem?.cancel()
            self.restartWorkItem = work
            self.listenerLock.unlock()
            self.queue.asyncAfter(deadline: .now() + 1.0, execute: work)
        }
    }

    public func stop() {
        listenerLock.lock()
        self.restartWorkItem?.cancel()
        self.restartWorkItem = nil
        self.isRestarting = false
        self.listener?.stateUpdateHandler = nil
        self.listener?.cancel()
        self.listener = nil
        listenerLock.unlock()

        queue.async { [weak self] in
            guard let self = self else { return }
            self.listenerLock.lock()
            self.restartWorkItem?.cancel()
            self.restartWorkItem = nil
            self.isRestarting = false
            self.listener?.cancel()
            self.listener = nil
            self.listenerLock.unlock()

            self.connectionsLock.lock()
            let conns = self.activeConnections
            self.activeConnections.removeAll()
            self.connectionsLock.unlock()
            for conn in conns {
                conn.cancel()
            }
            NSLog("[UPnPMediaRendererServer] UPnP HTTP server stopped.")
        }
    }

    // MARK: - Connection Handling & Same-Subnet Guard

    private func handleNewConnection(_ connection: NWConnection) {
        let remoteIP = WebSocketServer.shared.extractRemoteIP(from: connection)
        if !remoteIP.isEmpty && !LANSubnetGuard.isPrivateLANOrLoopbackPeer(remoteIP) {
            NSLog("[UPnPMediaRendererServer] 🛡️ Rejected non-LAN/WAN UPnP TCP connection from %@", remoteIP)
            connection.cancel()
            return
        }

        connectionsLock.lock()
        if activeConnections.count >= Self.maxActiveConnections {
            connectionsLock.unlock()
            connection.cancel()
            return
        }
        activeConnections.append(connection)
        connectionsLock.unlock()

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            switch state {
            case .failed, .cancelled:
                if let conn = connection {
                    self?.connectionsLock.lock()
                    self?.activeConnections.removeAll { $0 === conn }
                    self?.connectionsLock.unlock()
                }
            default:
                break
            }
        }

        queue.asyncAfter(deadline: .now() + 15.0) { [weak connection] in
            guard let conn = connection else { return }
            switch conn.state {
            case .setup, .preparing, .waiting, .ready:
                conn.cancel()
            default:
                break
            }
        }

        connection.start(queue: queue)
        receiveRequest(connection)
    }

    private func receiveRequest(_ connection: NWConnection, accumulatedData: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] data, _, isComplete, error in
            guard let self = self, let connection = connection else { return }

            var current = accumulatedData
            if let d = data {
                current.append(d)
            }

            if let headerEndRange = current.range(of: Data("\r\n\r\n".utf8)) {
                guard headerEndRange.lowerBound <= 32 * 1024 else {
                    self.send400(connection)
                    return
                }
                let headerData = current.subdata(in: 0..<headerEndRange.lowerBound)
                let bodyData = current.subdata(in: headerEndRange.upperBound..<current.count)

                guard let headerString = String(data: headerData, encoding: .utf8) else {
                    self.send400(connection)
                    return
                }

                var contentLength = 0
                for line in headerString.components(separatedBy: "\r\n") {
                    if line.lowercased().hasPrefix("content-length:") {
                        let valStr = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                        guard let parsed = Int(valStr), parsed >= 0, parsed <= 1024 * 1024 else {
                            self.send400(connection)
                            return
                        }
                        contentLength = parsed
                        break
                    }
                }

                if bodyData.count >= contentLength {
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        self?.processHTTPRequest(headerString: headerString, bodyData: bodyData, connection: connection)
                    }
                } else if isComplete || error != nil {
                    connection.cancel()
                } else {
                    self.receiveRequest(connection, accumulatedData: current)
                }
            } else if current.count > 32 * 1024 {
                self.send400(connection)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receiveRequest(connection, accumulatedData: current)
            }
        }
    }

    // MARK: - HTTP Request Routing

    private func processHTTPRequest(headerString: String, bodyData: Data, connection: NWConnection) {
        let remoteIP = WebSocketServer.shared.extractRemoteIP(from: connection)
        guard LANSubnetGuard.isPrivateLANOrLoopbackPeer(remoteIP) else {
            send403(connection)
            return
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            send400(connection)
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            send400(connection)
            return
        }

        let method = parts[0].uppercased()
        let path = parts[1]

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
                let val = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                headers[key] = val
            }
        }

        if method == "SUBSCRIBE" || method == "UNSUBSCRIBE" {
            handleSubscription(method: method, path: path, headers: headers, remoteIP: remoteIP, connection: connection)
            return
        }

        var reqPath = path
        if let url = URL(string: path), !url.path.isEmpty {
            reqPath = url.path
        }
        let cleanPath = reqPath.components(separatedBy: "?").first ?? reqPath

        switch cleanPath {
        case "/description.xml":
            sendDeviceDescription(connection)
        case "/upnp/scpd/avtransport.xml":
            sendXML(connection, content: Self.avTransportSCPD)
        case "/upnp/scpd/renderingcontrol.xml":
            sendXML(connection, content: Self.renderingControlSCPD)
        case "/upnp/scpd/connectionmanager.xml":
            sendXML(connection, content: Self.connectionManagerSCPD)
        case "/artwork/current.jpg":
            sendCurrentArtwork(connection, headOnly: method == "HEAD")
        case "/artwork/icon.png":
            sendDefaultIcon(connection, headOnly: method == "HEAD")
        case "/upnp/control/avtransport":
            handleAVTransportControl(bodyData: bodyData, headers: headers, connection: connection)
        case "/upnp/control/renderingcontrol":
            handleRenderingControl(bodyData: bodyData, headers: headers, connection: connection)
        case "/upnp/control/connectionmanager":
            handleConnectionManagerControl(bodyData: bodyData, headers: headers, connection: connection)
        default:
            send404(connection)
        }
    }

    // MARK: - Device Description & Artwork Endpoints

    public func buildDeviceDescriptionXML() -> String {
        let udn = SSDPService.shared.deviceUDN
        let friendlyName = escapeXMLText(SSDPService.shared.friendlyName)

        return """
        <?xml version="1.0" encoding="utf-8"?>
        <root xmlns="urn:schemas-upnp-org:device-1-0">
          <specVersion>
            <major>1</major>
            <minor>0</minor>
          </specVersion>
          <device>
            <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
            <friendlyName>\(friendlyName)</friendlyName>
            <manufacturer>Apple Music Remote</manufacturer>
            <manufacturerURL>https://github.com/ksholokhov/amr</manufacturerURL>
            <modelDescription>Apple Music Remote UPnP/DLNA Media Renderer</modelDescription>
            <modelName>AMR-MediaRenderer</modelName>
            <modelNumber>2.0</modelNumber>
            <modelURL>https://github.com/ksholokhov/amr</modelURL>
            <serialNumber>AMR-MAC-\(SSDPService.shared.deviceUUID.prefix(8))</serialNumber>
            <UDN>\(udn)</UDN>
            <iconList>
              <icon>
                <mimetype>image/png</mimetype>
                <width>128</width>
                <height>128</height>
                <depth>24</depth>
                <url>/artwork/icon.png</url>
              </icon>
            </iconList>
            <serviceList>
              <service>
                <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
                <serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>
                <controlURL>/upnp/control/avtransport</controlURL>
                <eventSubURL>/upnp/event/avtransport</eventSubURL>
                <SCPDURL>/upnp/scpd/avtransport.xml</SCPDURL>
              </service>
              <service>
                <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
                <serviceId>urn:upnp-org:serviceId:RenderingControl</serviceId>
                <controlURL>/upnp/control/renderingcontrol</controlURL>
                <eventSubURL>/upnp/event/renderingcontrol</eventSubURL>
                <SCPDURL>/upnp/scpd/renderingcontrol.xml</SCPDURL>
              </service>
              <service>
                <serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>
                <serviceId>urn:upnp-org:serviceId:ConnectionManager</serviceId>
                <controlURL>/upnp/control/connectionmanager</controlURL>
                <eventSubURL>/upnp/event/connectionmanager</eventSubURL>
                <SCPDURL>/upnp/scpd/connectionmanager.xml</SCPDURL>
              </service>
            </serviceList>
          </device>
        </root>
        """
    }

    private func sendDeviceDescription(_ connection: NWConnection) {
        sendXML(connection, content: buildDeviceDescriptionXML())
    }

    internal func resolveArtworkURI(for track: TrackInfo?, lanIP: String) -> String {
        guard let track = track else {
            return "http://\(lanIP):\(port)/artwork/icon.png"
        }
        let rawArtUrl = track.artworkUrl.trimmingCharacters(in: .whitespacesAndNewlines)

        if rawArtUrl.hasPrefix("http://") || rawArtUrl.hasPrefix("https://") {
            return rawArtUrl
        }
        if rawArtUrl.hasPrefix("/") {
            return "http://\(lanIP):\(WebSocketServer.shared.port)\(rawArtUrl)"
        }

        let trackId = track.id
        let combinedTrack = track.name.hashValue ^ track.artist.hashValue
        let trackHash = Int(truncatingIfNeeded: combinedTrack.magnitude & 0x3FFF_FFFF)
        let artHash = Int(truncatingIfNeeded: rawArtUrl.hashValue.magnitude & 0x3FFF_FFFF)
        return "http://\(lanIP):\(port)/artwork/current.jpg?v=\(trackId)_\(trackHash)_\(artHash)"
    }

    private static func isSafeRemoteArtworkURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased(), !host.isEmpty else {
            return false
        }
        if LANSubnetGuard.isLoopbackIP(host) || host == "169.254.169.254" || host.hasSuffix(".local") {
            return false
        }
        if DLNADiscoveryManager.normalizeLiteralIP(host) != nil {
            return false
        }
        return true
    }

    private func fetchAndSendRemoteArtwork(_ urlStr: String, url: URL, connection: NWConnection, headOnly: Bool) {
        if let cached = artworkLock.withLock({ cachedArtworkData }), cached.key == urlStr {
            sendBinary(connection, data: cached.data, contentType: cached.contentType, headOnly: headOnly)
            return
        }
        if let disk = ArtworkDiskCache.shared.get(key: urlStr) {
            artworkLock.withLock { cachedArtworkData = (key: urlStr, data: disk, contentType: "image/jpeg") }
            sendBinary(connection, data: disk, contentType: "image/jpeg", headOnly: headOnly)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        BoundedNoRedirectHTTPClient.shared.fetch(request: request, maxBytes: 8 * 1024 * 1024) { [weak self] data, http, _ in
            guard let self = self else { return }
            if let d = data, let http = http, (200...299).contains(http.statusCode), !d.isEmpty {
                let mime = http.mimeType ?? "image/jpeg"
                ArtworkDiskCache.shared.set(key: urlStr, data: d)
                self.artworkLock.withLock {
                    self.cachedArtworkData = (key: urlStr, data: d, contentType: mime)
                }
                self.sendBinary(connection, data: d, contentType: mime, headOnly: headOnly)
            } else {
                self.sendDefaultIcon(connection, headOnly: headOnly)
            }
        }
    }

    private func sendCurrentArtwork(_ connection: NWConnection, headOnly: Bool = false) {
        if let artData = MusicBridge.shared.getCurrentTrackArtwork(), !artData.isEmpty {
            sendBinary(connection, data: artData, contentType: "image/jpeg", headOnly: headOnly)
            return
        }

        let status = MusicBridge.shared.getPlayerStatus()
        guard let track = status.track else {
            sendDefaultIcon(connection, headOnly: headOnly)
            return
        }

        let artUrl = track.artworkUrl.trimmingCharacters(in: .whitespacesAndNewlines)

        if artUrl.hasPrefix("/assets/") && !artUrl.lowercased().hasSuffix(".svg") {
            let assetSubpath = String(artUrl.dropFirst(1))
            if let data = WebSocketServer.shared.loadWebBinaryAsset(subpath: assetSubpath) {
                let ct = assetSubpath.hasSuffix(".jpg") ? "image/jpeg" : "image/png"
                sendBinary(connection, data: data, contentType: ct, headOnly: headOnly)
                return
            }
        }

        if artUrl.hasPrefix("/api/artwork/track"), let numId = track.numericId, numId > 0,
           let data = ArtworkService.shared.getTrackArtwork(id: numId) {
            sendBinary(connection, data: data, contentType: "image/jpeg", headOnly: headOnly)
            return
        }

        if (artUrl.hasPrefix("http://") || artUrl.hasPrefix("https://")),
           let url = URL(string: artUrl),
           Self.isSafeRemoteArtworkURL(url) {
            fetchAndSendRemoteArtwork(artUrl, url: url, connection: connection, headOnly: headOnly)
            return
        }

        if let cachedUrlStr = MusicKitManager.shared.getCachedTrackArtwork(name: track.name, artist: track.artist, album: track.album),
           !cachedUrlStr.isEmpty,
           let url = URL(string: cachedUrlStr),
           Self.isSafeRemoteArtworkURL(url) {
            fetchAndSendRemoteArtwork(cachedUrlStr, url: url, connection: connection, headOnly: headOnly)
            return
        }

        if !track.name.isEmpty {
            let (tName, tArtist, tAlbum) = (track.name, track.artist, track.album)
            Task.detached(priority: .utility) { [weak self] in
                guard let self = self else { return }
                if let searchedStr = await MusicKitManager.shared.searchTrackArtwork(name: tName, artist: tArtist, album: tAlbum),
                   let url = URL(string: searchedStr),
                   Self.isSafeRemoteArtworkURL(url) {
                    self.fetchAndSendRemoteArtwork(searchedStr, url: url, connection: connection, headOnly: headOnly)
                } else {
                    self.sendDefaultIcon(connection, headOnly: headOnly)
                }
            }
            return
        }

        sendDefaultIcon(connection, headOnly: headOnly)
    }

    private func sendDefaultIcon(_ connection: NWConnection, headOnly: Bool = false) {
        if let iconUrl = Bundle.main.url(forResource: "icon", withExtension: "png"),
           let data = try? Data(contentsOf: iconUrl) {
            sendBinary(connection, data: data, contentType: "image/png", headOnly: headOnly)
            return
        }
        if let webPng = WebSocketServer.shared.loadWebBinaryAsset(subpath: "apple-touch-icon-512.png") {
            sendBinary(connection, data: webPng, contentType: "image/png", headOnly: headOnly)
            return
        }
        let transparentPNG: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
            0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
            0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
            0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
            0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
            0x42, 0x60, 0x82
        ]
        sendBinary(connection, data: Data(transparentPNG), contentType: "image/png", headOnly: headOnly)
    }

    // MARK: - Shared Helpers & HTTP Responses

    internal func getFastDMRStatus() -> PlayerStatus {
        if !PlaybackRouter.shared.isTestingEnvironment {
            let cached: (status: PlayerStatus, age: TimeInterval)? = PlaybackStateStore.shared.withLock {
                guard let entry = PlaybackStateStore.shared.lastPlayerStatusCache else { return nil }
                return (entry.status, Date().timeIntervalSince(entry.timestamp))
            }
            if let cached = cached, (cached.age < 4.5 || AppleScriptExecutor.shared.isBusy) {
                if cached.status.playerState.lowercased() == "playing" {
                    let dur = cached.status.track?.duration ?? 0
                    let rawPos = cached.status.position + max(0, cached.age)
                    let interpolatedPos = dur > 0 ? min(rawPos, dur) : rawPos
                    var updated = cached.status
                    updated.position = interpolatedPos
                    return updated
                }
                return cached.status
            }
        }
        return MusicBridge.shared.getPlayerStatus()
    }

    internal func getLANIP() -> String {
        let ips = WebSocketServer.shared.getLANIPAddresses()
        return ips.first ?? "127.0.0.1"
    }

    internal func sendXML(_ connection: NWConnection, content: String) {
        guard let data = content.data(using: .utf8) else { return }
        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: text/xml; charset="utf-8"\r
        Content-Length: \(data.count)\r
        Connection: close\r
        \r\n
        """
        sendRawWithBody(connection, headers: header, body: data)
    }

    internal func sendBinary(_ connection: NWConnection, data: Data, contentType: String, headOnly: Bool = false) {
        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: \(contentType)\r
        Content-Length: \(data.count)\r
        Cache-Control: no-cache\r
        Connection: close\r
        \r\n
        """
        if headOnly {
            sendRaw(connection, string: header)
        } else {
            sendRawWithBody(connection, headers: header, body: data)
        }
    }

    internal func send400(_ connection: NWConnection) {
        let body = "400 Bad Request"
        sendRaw(connection, string: "HTTP/1.1 400 Bad Request\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n\(body)")
    }

    internal func send403(_ connection: NWConnection) {
        let body = "403 Forbidden"
        sendRaw(connection, string: "HTTP/1.1 403 Forbidden\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n\(body)")
    }

    internal func send404(_ connection: NWConnection) {
        let body = "404 Not Found"
        sendRaw(connection, string: "HTTP/1.1 404 Not Found\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n\(body)")
    }

    internal func sendRaw(_ connection: NWConnection, string: String) {
        guard let data = string.data(using: .utf8) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    internal func sendRawWithBody(_ connection: NWConnection, headers: String, body: Data) {
        guard let headerData = headers.data(using: .utf8) else { return }
        var full = headerData
        full.append(body)
        connection.send(content: full, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
