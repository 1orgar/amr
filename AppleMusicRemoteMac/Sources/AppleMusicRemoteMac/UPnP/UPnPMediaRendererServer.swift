//
//  UPnPMediaRendererServer.swift
//  AppleMusicRemoteMac
//
//  UPnP / DLNA MediaRenderer HTTP Server on Port 8090
//  Implements standard AVTransport:1, RenderingControl:1, ConnectionManager:1
//  Enables Home Assistant 'dlna_dmr' integration with track metadata, artwork, volume and seek.
//

import Foundation
import Network

public final class UPnPMediaRendererServer: @unchecked Sendable {
    public static let shared = UPnPMediaRendererServer()

    public private(set) var port: UInt16 = 8090
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "org.ksholokhov.amr.upnp.http", qos: .utility)
    private var activeConnections: [NWConnection] = []

    // Optimistic tracking for instantaneous Home Assistant response & seek stabilization
    private var optimisticState: String?
    private var optimisticStateDate: Date = .distantPast

    private var optimisticPosition: Double?
    private var optimisticPositionDate: Date = .distantPast
    private var optimisticPositionIsPlaying: Bool = false

    private var lastNotifiedState: String?
    private var lastNotifiedTrackId: String?
    private var lastNotifiedTime: Date = .distantPast

    private init() {}

    public func start(port: UInt16 = 8090) -> Bool {
        self.port = port
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            self.listener = listener

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    NSLog("[UPnPMediaRendererServer] ✅ HTTP UPnP Server listening on port %u", port)
                case .failed(let err):
                    NSLog("[UPnPMediaRendererServer] ❌ Listener failed: %@", err.localizedDescription)
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
            NSLog("[UPnPMediaRendererServer] ❌ Failed to create NWListener: %@", error.localizedDescription)
            return false
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.listener?.cancel()
            self.listener = nil
            for conn in self.activeConnections {
                conn.cancel()
            }
            self.activeConnections.removeAll()
            NSLog("[UPnPMediaRendererServer] UPnP HTTP server stopped.")
        }
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        queue.async { [weak self] in
            self?.activeConnections.append(connection)
        }

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            switch state {
            case .failed, .cancelled:
                if let conn = connection {
                    self?.queue.async {
                        self?.activeConnections.removeAll { $0 === conn }
                    }
                }
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

            // Check if full HTTP header received
            if let headerEndRange = current.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = current.subdata(in: 0..<headerEndRange.lowerBound)
                let bodyData = current.subdata(in: headerEndRange.upperBound..<current.count)

                guard let headerString = String(data: headerData, encoding: .utf8) else {
                    self.send400(connection)
                    return
                }

                // Check Content-Length for POST body
                var contentLength = 0
                for line in headerString.components(separatedBy: "\r\n") {
                    if line.lowercased().hasPrefix("content-length:") {
                        let valStr = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                        contentLength = Int(valStr) ?? 0
                        break
                    }
                }

                if bodyData.count >= contentLength {
                    self.processHTTPRequest(headerString: headerString, bodyData: bodyData, connection: connection)
                } else {
                    // Need more body data
                    self.receiveRequest(connection, accumulatedData: current)
                }
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receiveRequest(connection, accumulatedData: current)
            }
        }
    }

    // MARK: - HTTP Request Routing

    private func processHTTPRequest(headerString: String, bodyData: Data, connection: NWConnection) {
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

        // Handle Event Subscriptions (GENA)
        if method == "SUBSCRIBE" || method == "UNSUBSCRIBE" {
            handleSubscription(method: method, path: path, headers: headers, connection: connection)
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
            sendCurrentArtwork(connection)

        case "/artwork/icon.png":
            sendDefaultIcon(connection)

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

    // MARK: - GENA Subscriptions (Home Assistant EventSub)

    private struct EventSubscription {
        let sid: String
        let callbackURL: URL
        let path: String
        var seq: UInt32
    }

    private var subscriptions: [EventSubscription] = []
    private let subQueue = DispatchQueue(label: "org.ksholokhov.amr.upnp.gena")

    private func handleSubscription(method: String, path: String, headers: [String: String], connection: NWConnection) {
        let cleanPath = path.components(separatedBy: "?").first ?? path

        if method == "SUBSCRIBE" {
            let requestedSid = headers["SID"]
            let sid = requestedSid ?? "uuid:\(UUID().uuidString.lowercased())"

            let response = """
            HTTP/1.1 200 OK\r
            SERVER: macOS/14.0 UPnP/1.0 AppleMusicRemote/2.0\r
            SID: \(sid)\r
            TIMEOUT: Second-1800\r
            Content-Length: 0\r
            Connection: close\r
            \r\n
            """
            sendRaw(connection, string: response)

            // Parse CALLBACK header: e.g. <http://10.10.20.15:8123/api/dlna/callback>
            if let rawCallback = headers["CALLBACK"] {
                let clean = rawCallback.trimmingCharacters(in: CharacterSet(charactersIn: "<> \t\r\n"))
                let firstUrlStr = clean.components(separatedBy: CharacterSet(charactersIn: "<> ")).first { !$0.isEmpty } ?? clean
                if let url = URL(string: firstUrlStr) {
                    let sub = EventSubscription(sid: sid, callbackURL: url, path: cleanPath, seq: 0)
                    subQueue.async { [weak self] in
                        guard let self = self else { return }
                        // Remove previous subscription only for this specific service path or matching SID
                        self.subscriptions.removeAll { $0.sid == sid || ($0.callbackURL == url && $0.path == cleanPath) }
                        self.subscriptions.append(sub)
                        NSLog("[UPnPMediaRendererServer] 📝 Subscribed to %@ (SID: %@, Total subs: %d)", cleanPath, sid, self.subscriptions.count)
                        if cleanPath.contains("avtransport") {
                            self.sendNotification(for: sub)
                        } else if cleanPath.contains("connectionmanager") {
                            self.sendConnectionManagerNotification(for: sub)
                        }
                    }
                }
            } else if let renewSid = requestedSid {
                // Subscription renewal
                subQueue.async { [weak self] in
                    guard let self = self else { return }
                    if let idx = self.subscriptions.firstIndex(where: { $0.sid == renewSid }) {
                        NSLog("[UPnPMediaRendererServer] 🔄 Renewed subscription for %@ (SID: %@)", self.subscriptions[idx].path, renewSid)
                    }
                }
            }
        } else {
            // UNSUBSCRIBE
            if let sid = headers["SID"] {
                subQueue.async { [weak self] in
                    self?.subscriptions.removeAll { $0.sid == sid }
                }
            }
            let response = """
            HTTP/1.1 200 OK\r
            SERVER: macOS/14.0 UPnP/1.0 AppleMusicRemote/2.0\r
            Content-Length: 0\r
            Connection: close\r
            \r\n
            """
            sendRaw(connection, string: response)
        }
    }

    public func notifySubscribers(status: PlayerStatus? = nil, force: Bool = false, completion: (() -> Void)? = nil) {
        let currentStatus = status ?? MusicBridge.shared.getPlayerStatus()
        let stateStr: String
        if Date().timeIntervalSince(optimisticStateDate) < 5.0, let optState = optimisticState {
            stateStr = optState
        } else {
            switch currentStatus.playerState.lowercased() {
            case "playing": stateStr = "PLAYING"
            case "paused": stateStr = "PAUSED_PLAYBACK"
            default: stateStr = "STOPPED"
            }
        }
        let trackId = currentStatus.track?.id ?? "0"

        subQueue.async { [weak self] in
            guard let self = self else {
                completion?()
                return
            }
            guard !self.subscriptions.isEmpty else {
                completion?()
                return
            }

            // Deduplicate: Don't spam notifications if state & track haven't changed and not forced
            if !force,
               stateStr == self.lastNotifiedState,
               trackId == self.lastNotifiedTrackId,
               Date().timeIntervalSince(self.lastNotifiedTime) < 30.0 {
                completion?()
                return
            }

            self.lastNotifiedState = stateStr
            self.lastNotifiedTrackId = trackId
            self.lastNotifiedTime = Date()

            let group = DispatchGroup()
            for i in 0..<self.subscriptions.count {
                if self.subscriptions[i].path.contains("avtransport") {
                    self.subscriptions[i].seq &+= 1
                    group.enter()
                    self.sendNotification(for: self.subscriptions[i], status: currentStatus, overrideState: stateStr) {
                        group.leave()
                    }
                }
            }

            if let comp = completion {
                // Wait up to 250ms for subscriber delivery so state is ingested before SOAP response
                _ = group.wait(timeout: .now() + 0.25)
                comp()
            }
        }
    }

    private func sendConnectionManagerNotification(for subscription: EventSubscription) {
        let body = """
        <e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0">
          <e:property>
            <SourceProtocolInfo>http-get:*:audio/mpeg:*,http-get:*:audio/mp4:*,http-get:*:audio/x-m4a:*,http-get:*:audio/flac:*</SourceProtocolInfo>
          </e:property>
          <e:property>
            <SinkProtocolInfo>http-get:*:audio/mpeg:*,http-get:*:audio/mp4:*,http-get:*:audio/x-m4a:*,http-get:*:audio/flac:*</SinkProtocolInfo>
          </e:property>
          <e:property>
            <CurrentConnectionIDs>0</CurrentConnectionIDs>
          </e:property>
        </e:propertyset>
        """
        sendRawNotify(to: subscription.callbackURL, sid: subscription.sid, seq: subscription.seq, body: body)
    }

    private func sendNotification(for subscription: EventSubscription, status: PlayerStatus? = nil, overrideState: String? = nil, completion: (() -> Void)? = nil) {
        let currentStatus = status ?? MusicBridge.shared.getPlayerStatus()
        let lanIP = getLANIP()

        let curSec: Double
        if Date().timeIntervalSince(optimisticPositionDate) < 5.0, let optPos = optimisticPosition {
            let elapsed = optimisticPositionIsPlaying ? Date().timeIntervalSince(optimisticPositionDate) : 0.0
            curSec = min(optPos + elapsed, currentStatus.track?.duration ?? (optPos + elapsed))
        } else {
            curSec = currentStatus.position
        }

        let durSec = currentStatus.track?.duration ?? 0.0
        let curTimeStr = formatSecondsToTime(curSec)
        let durTimeStr = formatSecondsToTime(durSec)

        let stateStr = overrideState ?? {
            if Date().timeIntervalSince(optimisticStateDate) < 5.0, let optState = optimisticState {
                return optState
            }
            switch currentStatus.playerState.lowercased() {
            case "playing": return "PLAYING"
            case "paused": return "PAUSED_PLAYBACK"
            default: return "STOPPED"
            }
        }()

        let title = currentStatus.track?.name ?? "Без названия"
        let artist = currentStatus.track?.artist ?? "Apple Music"
        let album = currentStatus.track?.album ?? ""
        let trackId = currentStatus.track?.id ?? "0"
        let trackHash = abs((currentStatus.track?.name ?? "").hashValue ^ (currentStatus.track?.artist ?? "").hashValue)
        let artUri = "http://\(lanIP):\(port)/artwork/current.jpg?v=\(trackId)_\(trackHash)"

        let didlRaw = generateDIDLLiteXML(title: title, artist: artist, album: album, artUri: artUri, durTimeStr: durTimeStr)
        let didlForLastChange = escapeForLastChangeVal(didlRaw)

        let lastChange = """
        &lt;Event xmlns="urn:schemas-upnp-org:metadata-1-0/AVT/"&gt;&lt;InstanceID val="0"&gt;&lt;TransportState val="\(stateStr)"/&gt;&lt;TransportStatus val="OK"/&gt;&lt;CurrentTrack val="1"/&gt;&lt;CurrentTrackDuration val="\(durTimeStr)"/&gt;&lt;CurrentTrackMetaData val="\(didlForLastChange)"/&gt;&lt;AVTransportURI val="\(artUri)"/&gt;&lt;AVTransportURIMetaData val="\(didlForLastChange)"/&gt;&lt;CurrentTrackURI val="\(artUri)"/&gt;&lt;RelativeTimePosition val="\(curTimeStr)"/&gt;&lt;AbsoluteTimePosition val="\(curTimeStr)"/&gt;&lt;/InstanceID&gt;&lt;/Event&gt;
        """
        let body = """
        <e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0">
          <e:property>
            <LastChange>\(lastChange)</LastChange>
          </e:property>
        </e:propertyset>
        """

        sendRawNotify(to: subscription.callbackURL, sid: subscription.sid, seq: subscription.seq, body: body, completion: completion)
    }

    private func sendRawNotify(to url: URL, sid: String, seq: UInt32, body: String, completion: (() -> Void)? = nil) {
        guard let bodyData = body.data(using: .utf8) else {
            completion?()
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "NOTIFY"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "CONTENT-TYPE")
        request.setValue("upnp:event", forHTTPHeaderField: "NT")
        request.setValue("upnp:propchange", forHTTPHeaderField: "NTS")
        request.setValue(sid, forHTTPHeaderField: "SID")
        request.setValue("\(seq)", forHTTPHeaderField: "SEQ")
        request.httpBody = bodyData
        request.timeoutInterval = 2.5

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let err = error {
                NSLog("[UPnPMediaRendererServer] ❌ NOTIFY error to %@: %@", url.absoluteString, err.localizedDescription)
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                NSLog("[UPnPMediaRendererServer] ✅ NOTIFY delivered to %@ (HTTP %d, seq: %u, SID: %@)", url.absoluteString, code, seq, sid)
            }
            completion?()
        }
        task.resume()
    }

    // MARK: - Device Description

    private func sendDeviceDescription(_ connection: NWConnection) {
        let udn = SSDPService.shared.deviceUDN
        let friendlyName = escapeXMLText(SSDPService.shared.friendlyName)

        let xml = """
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

        sendXML(connection, content: xml)
    }

    // MARK: - Artwork Endpoint

    private func sendCurrentArtwork(_ connection: NWConnection) {
        // Check if track artwork data is available locally
        if let artData = MusicBridge.shared.getCurrentTrackArtwork() {
            sendBinary(connection, data: artData, contentType: "image/jpeg")
            return
        }

        // If local is not available, check if we have a remote artwork URL
        let status = MusicBridge.shared.getPlayerStatus()
        if let artUrl = status.track?.artworkUrl, artUrl.hasPrefix("http"), let url = URL(string: artUrl) {
            // Redirect to remote CDN artwork (supported by HA)
            let redirect = """
            HTTP/1.1 302 Found\r
            Location: \(url.absoluteString)\r
            Cache-Control: no-cache, no-store, must-revalidate\r
            Pragma: no-cache\r
            Expires: 0\r
            Content-Length: 0\r
            Connection: close\r
            \r\n
            """
            sendRaw(connection, string: redirect)
            return
        }

        sendDefaultIcon(connection)
    }

    private func sendDefaultIcon(_ connection: NWConnection) {
        if let iconUrl = Bundle.main.url(forResource: "icon", withExtension: "png"),
           let data = try? Data(contentsOf: iconUrl) {
            sendBinary(connection, data: data, contentType: "image/png")
            return
        }
        // Return 1x1 transparent PNG fallback
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
        sendBinary(connection, data: Data(transparentPNG), contentType: "image/png")
    }

    // MARK: - AVTransport SOAP Actions

    private func handleAVTransportControl(bodyData: Data, headers: [String: String], connection: NWConnection) {
        guard let bodyString = String(data: bodyData, encoding: .utf8) else {
            send400(connection)
            return
        }

        let action = extractSOAPAction(from: headers, body: bodyString)
        NSLog("[UPnPMediaRendererServer] 📩 AVTransport SOAP action: %@", action)
        let status = MusicBridge.shared.getPlayerStatus()
        let lanIP = getLANIP()

        switch action {
        case "GetPositionInfo":
            let curSec: Double
            if Date().timeIntervalSince(optimisticPositionDate) < 5.0, let optPos = optimisticPosition {
                let elapsed = optimisticPositionIsPlaying ? Date().timeIntervalSince(optimisticPositionDate) : 0.0
                curSec = min(optPos + elapsed, status.track?.duration ?? (optPos + elapsed))
            } else {
                curSec = status.position
            }
            let durSec = status.track?.duration ?? 0.0
            let curTimeStr = formatSecondsToTime(curSec)
            let durTimeStr = formatSecondsToTime(durSec)

            let title = status.track?.name ?? "Без названия"
            let artist = status.track?.artist ?? "Apple Music"
            let album = status.track?.album ?? ""
            let trackId = status.track?.id ?? "0"
            let trackHash = abs((status.track?.name ?? "").hashValue ^ (status.track?.artist ?? "").hashValue)
            let artUri = "http://\(lanIP):\(port)/artwork/current.jpg?v=\(trackId)_\(trackHash)"

            let didlRaw = generateDIDLLiteXML(title: title, artist: artist, album: album, artUri: artUri, durTimeStr: durTimeStr)
            let didl = escapeForSOAP(didlRaw)

            let response = """
            <u:GetPositionInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <Track>1</Track>
              <TrackDuration>\(durTimeStr)</TrackDuration>
              <TrackMetaData>\(didl)</TrackMetaData>
              <TrackURI>\(artUri)</TrackURI>
              <RelTime>\(curTimeStr)</RelTime>
              <AbsTime>\(curTimeStr)</AbsTime>
              <RelCount>2147483647</RelCount>
              <AbsCount>2147483647</AbsCount>
            </u:GetPositionInfoResponse>
            """
            sendSOAPResponse(connection, response: response)

        case "GetTransportInfo":
            let stateStr: String
            if Date().timeIntervalSince(optimisticStateDate) < 5.0, let optState = optimisticState {
                stateStr = optState
            } else {
                switch status.playerState.lowercased() {
                case "playing": stateStr = "PLAYING"
                case "paused": stateStr = "PAUSED_PLAYBACK"
                default: stateStr = "STOPPED"
                }
            }

            let response = """
            <u:GetTransportInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <CurrentTransportState>\(stateStr)</CurrentTransportState>
              <CurrentTransportStatus>OK</CurrentTransportStatus>
              <CurrentSpeed>1</CurrentSpeed>
            </u:GetTransportInfoResponse>
            """
            sendSOAPResponse(connection, response: response)

        case "GetMediaInfo":
            let durSec = status.track?.duration ?? 0.0
            let durTimeStr = formatSecondsToTime(durSec)
            let title = status.track?.name ?? "Без названия"
            let artist = status.track?.artist ?? "Apple Music"
            let album = status.track?.album ?? ""
            let trackId = status.track?.id ?? "0"
            let trackHash = abs((status.track?.name ?? "").hashValue ^ (status.track?.artist ?? "").hashValue)
            let artUri = "http://\(lanIP):\(port)/artwork/current.jpg?v=\(trackId)_\(trackHash)"

            let didlRaw = generateDIDLLiteXML(title: title, artist: artist, album: album, artUri: artUri, durTimeStr: durTimeStr)
            let didl = escapeForSOAP(didlRaw)

            let response = """
            <u:GetMediaInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <NrTracks>1</NrTracks>
              <MediaDuration>\(durTimeStr)</MediaDuration>
              <CurrentURI>\(artUri)</CurrentURI>
              <CurrentURIMetaData>\(didl)</CurrentURIMetaData>
              <NextURI></NextURI>
              <NextURIMetaData></NextURIMetaData>
              <PlayMedium>NETWORK</PlayMedium>
              <RecordMedium>NOT_IMPLEMENTED</RecordMedium>
              <WriteStatus>NOT_IMPLEMENTED</WriteStatus>
            </u:GetMediaInfoResponse>
            """
            sendSOAPResponse(connection, response: response)

        case "GetDeviceCapabilities":
            let response = """
            <u:GetDeviceCapabilitiesResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <PlayMedia>NONE</PlayMedia>
              <RecMedia>NONE</RecMedia>
              <RecQualityModes>NONE</RecQualityModes>
            </u:GetDeviceCapabilitiesResponse>
            """
            sendSOAPResponse(connection, response: response)

        case "GetTransportSettings":
            let response = """
            <u:GetTransportSettingsResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <PlayMode>NORMAL</PlayMode>
              <RecQualityMode>NOT_IMPLEMENTED</RecQualityMode>
            </u:GetTransportSettingsResponse>
            """
            sendSOAPResponse(connection, response: response)

        case "Play":
            optimisticState = "PLAYING"
            optimisticStateDate = Date()
            optimisticPosition = status.position
            optimisticPositionDate = Date()
            optimisticPositionIsPlaying = true
            _ = MusicBridge.shared.play()
            notifySubscribers(force: true) { [weak self] in
                self?.sendSOAPResponse(connection, response: "<u:PlayResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"/>")
            }
            DispatchQueue.main.async {
                WebSocketServer.shared.broadcastStatus()
            }

        case "Pause":
            optimisticState = "PAUSED_PLAYBACK"
            optimisticStateDate = Date()
            optimisticPosition = status.position
            optimisticPositionDate = Date()
            optimisticPositionIsPlaying = false
            _ = MusicBridge.shared.pause()
            notifySubscribers(force: true) { [weak self] in
                self?.sendSOAPResponse(connection, response: "<u:PauseResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"/>")
            }
            DispatchQueue.main.async {
                WebSocketServer.shared.broadcastStatus()
            }

        case "Stop":
            optimisticState = "STOPPED"
            optimisticStateDate = Date()
            optimisticPosition = 0
            optimisticPositionDate = Date()
            optimisticPositionIsPlaying = false
            _ = MusicBridge.shared.stop()
            notifySubscribers(force: true) { [weak self] in
                self?.sendSOAPResponse(connection, response: "<u:StopResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"/>")
            }
            DispatchQueue.main.async {
                WebSocketServer.shared.broadcastStatus()
            }

        case "Next":
            optimisticPosition = 0
            optimisticPositionDate = Date()
            _ = MusicBridge.shared.nextTrack()
            sendSOAPResponse(connection, response: "<u:NextResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"/>")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.notifySubscribers(force: true)
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
            }

        case "Previous":
            optimisticPosition = 0
            optimisticPositionDate = Date()
            _ = MusicBridge.shared.previousTrack()
            sendSOAPResponse(connection, response: "<u:PreviousResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"/>")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.notifySubscribers(force: true)
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
            }

        case "Seek":
            // Example: <Unit>REL_TIME</Unit><Target>00:01:23</Target>
            if let targetVal = extractTagValue(tag: "Target", from: bodyString) {
                let seconds = parseTimeToSeconds(targetVal)
                let isPlaying = (status.playerState.lowercased() == "playing" || optimisticState == "PLAYING")
                optimisticPosition = seconds
                optimisticPositionDate = Date()
                optimisticPositionIsPlaying = isPlaying
                _ = MusicBridge.shared.seek(to: seconds)
            }
            notifySubscribers(force: true) { [weak self] in
                self?.sendSOAPResponse(connection, response: "<u:SeekResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"/>")
            }
            DispatchQueue.main.async {
                WebSocketServer.shared.broadcastStatus()
            }

        case "SetAVTransportURI":
            sendSOAPResponse(connection, response: "<u:SetAVTransportURIResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"/>")

        case "GetCurrentTransportActions":
            let response = """
            <u:GetCurrentTransportActionsResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <Actions>Play,Pause,Stop,Seek,Next,Previous</Actions>
            </u:GetCurrentTransportActionsResponse>
            """
            sendSOAPResponse(connection, response: response)

        default:
            sendSOAPError(connection, code: 401, message: "Invalid Action")
        }
    }

    // MARK: - RenderingControl SOAP Actions

    private func handleRenderingControl(bodyData: Data, headers: [String: String], connection: NWConnection) {
        guard let bodyString = String(data: bodyData, encoding: .utf8) else {
            send400(connection)
            return
        }

        let action = extractSOAPAction(from: headers, body: bodyString)
        let status = MusicBridge.shared.getPlayerStatus()

        switch action {
        case "GetVolume":
            let response = """
            <u:GetVolumeResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              <CurrentVolume>\(status.volume)</CurrentVolume>
            </u:GetVolumeResponse>
            """
            sendSOAPResponse(connection, response: response)

        case "SetVolume":
            if let volStr = extractTagValue(tag: "DesiredVolume", from: bodyString), let vol = Int(volStr) {
                let clamped = min(max(vol, 0), 100)
                DispatchQueue.main.async {
                    _ = MusicBridge.shared.setVolume(clamped)
                }
            }
            sendSOAPResponse(connection, response: "<u:SetVolumeResponse xmlns:u=\"urn:schemas-upnp-org:service:RenderingControl:1\"/>")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.notifySubscribers()
                WebSocketServer.shared.broadcastStatus()
            }

        case "GetMute":
            let isMuted = (status.volume == 0) ? "1" : "0"
            let response = """
            <u:GetMuteResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              <CurrentMute>\(isMuted)</CurrentMute>
            </u:GetMuteResponse>
            """
            sendSOAPResponse(connection, response: response)

        case "SetMute":
            if let muteStr = extractTagValue(tag: "DesiredMute", from: bodyString) {
                let mute = (muteStr == "1" || muteStr.lowercased() == "true")
                DispatchQueue.main.async {
                    _ = MusicBridge.shared.setVolume(mute ? 0 : 50)
                }
            }
            sendSOAPResponse(connection, response: "<u:SetMuteResponse xmlns:u=\"urn:schemas-upnp-org:service:RenderingControl:1\"/>")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.notifySubscribers()
                WebSocketServer.shared.broadcastStatus()
            }

        default:
            sendSOAPError(connection, code: 401, message: "Invalid Action")
        }
    }

    // MARK: - ConnectionManager SOAP Actions

    private func handleConnectionManagerControl(bodyData: Data, headers: [String: String], connection: NWConnection) {
        guard let bodyString = String(data: bodyData, encoding: .utf8) else {
            send400(connection)
            return
        }

        let action = extractSOAPAction(from: headers, body: bodyString)

        switch action {
        case "GetProtocolInfo":
            let response = """
            <u:GetProtocolInfoResponse xmlns:u="urn:schemas-upnp-org:service:ConnectionManager:1">
              <Source>http-get:*:audio/mpeg:*,http-get:*:audio/mp4:*,http-get:*:audio/aac:*,http-get:*:audio/x-m4a:*,http-get:*:audio/flac:*,http-get:*:audio/wav:*</Source>
              <Sink></Sink>
            </u:GetProtocolInfoResponse>
            """
            sendSOAPResponse(connection, response: response)

        case "GetCurrentConnectionIDs":
            let response = """
            <u:GetCurrentConnectionIDsResponse xmlns:u="urn:schemas-upnp-org:service:ConnectionManager:1">
              <ConnectionIDs>0</ConnectionIDs>
            </u:GetCurrentConnectionIDsResponse>
            """
            sendSOAPResponse(connection, response: response)

        case "GetCurrentConnectionInfo":
            let response = """
            <u:GetCurrentConnectionInfoResponse xmlns:u="urn:schemas-upnp-org:service:ConnectionManager:1">
              <RcsID>0</RcsID>
              <AVTransportID>0</AVTransportID>
              <ProtocolInfo></ProtocolInfo>
              <PeerConnectionManager></PeerConnectionManager>
              <PeerConnectionID>-1</PeerConnectionID>
              <Direction>Input</Direction>
              <Status>OK</Status>
            </u:GetCurrentConnectionInfoResponse>
            """
            sendSOAPResponse(connection, response: response)

        default:
            sendSOAPError(connection, code: 401, message: "Invalid Action")
        }
    }

    // MARK: - SOAP Helpers

    private func extractSOAPAction(from headers: [String: String], body: String) -> String {
        if let actionHeader = headers["SOAPACTION"] {
            let clean = actionHeader.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
            if let hashIdx = clean.firstIndex(of: "#") {
                return String(clean[clean.index(after: hashIdx)...])
            }
            return clean
        }

        // Fallback: parse XML body for <u:ActionName
        let pattern = try! NSRegularExpression(pattern: #"<u:([A-Za-z0-9]+)"#, options: [])
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        if let match = pattern.firstMatch(in: body, options: [], range: range),
           let r = Range(match.range(at: 1), in: body) {
            return String(body[r])
        }

        return ""
    }

    private func extractTagValue(tag: String, from xml: String) -> String? {
        let pattern = try! NSRegularExpression(pattern: "<\(tag)>([^<]+)</\(tag)>", options: .caseInsensitive)
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        if let match = pattern.firstMatch(in: xml, options: [], range: range),
           let r = Range(match.range(at: 1), in: xml) {
            return String(xml[r])
        }
        return nil
    }

    private func sendSOAPResponse(_ connection: NWConnection, response: String) {
        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            \(response)
          </s:Body>
        </s:Envelope>
        """

        sendXML(connection, content: envelope)
    }

    private func sendSOAPError(_ connection: NWConnection, code: Int, message: String) {
        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <s:Fault>
              <faultcode>s:Client</faultcode>
              <faultstring>UPnPError</faultstring>
              <detail>
                <UPnPError xmlns="urn:schemas-upnp-org:control-1-0">
                  <errorCode>\(code)</errorCode>
                  <errorDescription>\(message)</errorDescription>
                </UPnPError>
              </detail>
            </s:Fault>
          </s:Body>
        </s:Envelope>
        """
        guard let data = envelope.data(using: .utf8) else { return }

        let headers = """
        HTTP/1.1 500 Internal Server Error\r
        Content-Type: text/xml; charset="utf-8"\r
        Content-Length: \(data.count)\r
        Connection: close\r
        \r\n
        """
        sendRawWithBody(connection, headers: headers, body: data)
    }

    // MARK: - HTTP Responses

    private func sendXML(_ connection: NWConnection, content: String) {
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

    private func sendBinary(_ connection: NWConnection, data: Data, contentType: String) {
        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: \(contentType)\r
        Content-Length: \(data.count)\r
        Cache-Control: no-cache\r
        Connection: close\r
        \r\n
        """
        sendRawWithBody(connection, headers: header, body: data)
    }

    private func send400(_ connection: NWConnection) {
        let body = "400 Bad Request"
        let resp = "HTTP/1.1 400 Bad Request\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n\(body)"
        sendRaw(connection, string: resp)
    }

    private func send404(_ connection: NWConnection) {
        let body = "404 Not Found"
        let resp = "HTTP/1.1 404 Not Found\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n\(body)"
        sendRaw(connection, string: resp)
    }

    private func sendRaw(_ connection: NWConnection, string: String) {
        guard let data = string.data(using: .utf8) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendRawWithBody(_ connection: NWConnection, headers: String, body: Data) {
        guard let headerData = headers.data(using: .utf8) else { return }
        var full = headerData
        full.append(body)
        connection.send(content: full, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Time and XML Utilities

    private func formatSecondsToTime(_ totalSec: Double) -> String {
        guard totalSec > 0 && !totalSec.isNaN else { return "00:00:00" }
        let sec = Int(totalSec)
        let hours = sec / 3600
        let minutes = (sec % 3600) / 60
        let seconds = sec % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func parseTimeToSeconds(_ timeStr: String) -> Double {
        let parts = timeStr.components(separatedBy: ":")
        if parts.count == 3,
           let h = Double(parts[0]),
           let m = Double(parts[1]),
           let s = Double(parts[2]) {
            return h * 3600 + m * 60 + s
        } else if parts.count == 2,
                  let m = Double(parts[0]),
                  let s = Double(parts[1]) {
            return m * 60 + s
        } else if let s = Double(timeStr) {
            return s
        }
        return 0.0
    }

    private func escapeXMLText(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func generateDIDLLiteXML(title: String, artist: String, album: String, artUri: String, durTimeStr: String) -> String {
        let t = escapeXMLText(title)
        let a = escapeXMLText(artist)

        let rate = BitPerfectLogMonitor.shared.currentDetectedSampleRate ?? 44100.0
        let bitDepth = BitPerfectLogMonitor.shared.currentDetectedBitDepth ?? (rate > 48000.0 ? 24 : 16)
        let khz = rate / 1000.0
        let khzStr = (khz.truncatingRemainder(dividingBy: 1) == 0) ? String(format: "%.0f", khz) : String(format: "%.1f", khz)
        let qualityBadge = "\(khzStr) кГц / \(bitDepth)-бит"

        let displayAlbum: String
        if album.isEmpty {
            displayAlbum = qualityBadge
        } else {
            displayAlbum = "\(album) • \(qualityBadge)"
        }
        let alb = escapeXMLText(displayAlbum)
        let qDesc = escapeXMLText(qualityBadge)
        let bytesPerSec = Int(rate * Double(bitDepth) * 2 / 8)
        let sampleFreqInt = Int(rate)

        return "<DIDL-Lite xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\"><item id=\"1\" parentID=\"0\" restricted=\"1\"><dc:title>\(t)</dc:title><dc:creator>\(a)</dc:creator><dc:description>\(qDesc)</dc:description><upnp:artist>\(a)</upnp:artist><upnp:album>\(alb)</upnp:album><upnp:albumArtURI dlna:profileID=\"JPEG_MED\" xmlns:dlna=\"urn:schemas-dlna-org:metadata-1-0/\">\(artUri)</upnp:albumArtURI><res duration=\"\(durTimeStr)\" sampleFrequency=\"\(sampleFreqInt)\" bitsPerSample=\"\(bitDepth)\" nrAudioChannels=\"2\" bitrate=\"\(bytesPerSec)\" protocolInfo=\"http-get:*:audio/flac:*\">\(artUri)</res><upnp:class>object.item.audioItem.musicTrack</upnp:class></item></DIDL-Lite>"
    }

    private func escapeForSOAP(_ xmlStr: String) -> String {
        return xmlStr
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func escapeForLastChangeVal(_ xmlStr: String) -> String {
        return xmlStr
            .replacingOccurrences(of: "&", with: "&amp;amp;")
            .replacingOccurrences(of: "<", with: "&amp;lt;")
            .replacingOccurrences(of: ">", with: "&amp;gt;")
            .replacingOccurrences(of: "\"", with: "&amp;quot;")
            .replacingOccurrences(of: "'", with: "&amp;apos;")
    }

    private func getLANIP() -> String {
        let ips = WebSocketServer.shared.getLANIPAddresses()
        return ips.first ?? "127.0.0.1"
    }

    // MARK: - UPnP SCPD Definitions

    private static let avTransportSCPD = """
    <?xml version="1.0" encoding="utf-8"?>
    <scpd xmlns="urn:schemas-upnp-org:service-1-0">
      <specVersion><major>1</major><minor>0</minor></specVersion>
      <actionList>
        <action>
          <name>GetPositionInfo</name>
          <argumentList>
            <argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
            <argument><name>Track</name><direction>out</direction><relatedStateVariable>CurrentTrack</relatedStateVariable></argument>
            <argument><name>TrackDuration</name><direction>out</direction><relatedStateVariable>CurrentTrackDuration</relatedStateVariable></argument>
            <argument><name>TrackMetaData</name><direction>out</direction><relatedStateVariable>CurrentTrackMetaData</relatedStateVariable></argument>
            <argument><name>TrackURI</name><direction>out</direction><relatedStateVariable>CurrentTrackURI</relatedStateVariable></argument>
            <argument><name>RelTime</name><direction>out</direction><relatedStateVariable>RelativeTimePosition</relatedStateVariable></argument>
            <argument><name>AbsTime</name><direction>out</direction><relatedStateVariable>AbsoluteTimePosition</relatedStateVariable></argument>
            <argument><name>RelCount</name><direction>out</direction><relatedStateVariable>RelativeCounterPosition</relatedStateVariable></argument>
            <argument><name>AbsCount</name><direction>out</direction><relatedStateVariable>AbsoluteCounterPosition</relatedStateVariable></argument>
          </argumentList>
        </action>
        <action>
          <name>GetTransportInfo</name>
          <argumentList>
            <argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
            <argument><name>CurrentTransportState</name><direction>out</direction><relatedStateVariable>TransportState</relatedStateVariable></argument>
            <argument><name>CurrentTransportStatus</name><direction>out</direction><relatedStateVariable>TransportStatus</relatedStateVariable></argument>
            <argument><name>CurrentSpeed</name><direction>out</direction><relatedStateVariable>TransportPlaySpeed</relatedStateVariable></argument>
          </argumentList>
        </action>
        <action>
          <name>GetMediaInfo</name>
          <argumentList>
            <argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
            <argument><name>NrTracks</name><direction>out</direction><relatedStateVariable>NumberOfTracks</relatedStateVariable></argument>
            <argument><name>MediaDuration</name><direction>out</direction><relatedStateVariable>CurrentMediaDuration</relatedStateVariable></argument>
            <argument><name>CurrentURI</name><direction>out</direction><relatedStateVariable>AVTransportURI</relatedStateVariable></argument>
            <argument><name>CurrentURIMetaData</name><direction>out</direction><relatedStateVariable>AVTransportURIMetaData</relatedStateVariable></argument>
            <argument><name>NextURI</name><direction>out</direction><relatedStateVariable>NextAVTransportURI</relatedStateVariable></argument>
            <argument><name>NextURIMetaData</name><direction>out</direction><relatedStateVariable>NextAVTransportURIMetaData</relatedStateVariable></argument>
            <argument><name>PlayMedium</name><direction>out</direction><relatedStateVariable>PlaybackStorageMedium</relatedStateVariable></argument>
            <argument><name>RecordMedium</name><direction>out</direction><relatedStateVariable>RecordStorageMedium</relatedStateVariable></argument>
            <argument><name>WriteStatus</name><direction>out</direction><relatedStateVariable>RecordMediumWriteStatus</relatedStateVariable></argument>
          </argumentList>
        </action>
        <action>
          <name>Play</name>
          <argumentList>
            <argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
            <argument><name>Speed</name><direction>in</direction><relatedStateVariable>TransportPlaySpeed</relatedStateVariable></argument>
          </argumentList>
        </action>
        <action>
          <name>Pause</name>
          <argumentList>
            <argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
          </argumentList>
        </action>
        <action>
          <name>Stop</name>
          <argumentList>
            <argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
          </argumentList>
        </action>
        <action>
          <name>Seek</name>
          <argumentList>
            <argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
            <argument><name>Unit</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_SeekMode</relatedStateVariable></argument>
            <argument><name>Target</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_SeekTarget</relatedStateVariable></argument>
          </argumentList>
        </action>
        <action>
          <name>Next</name>
          <argumentList>
            <argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
          </argumentList>
        </action>
        <action>
          <name>Previous</name>
          <argumentList>
            <argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
          </argumentList>
        </action>
        <action>
          <name>SetAVTransportURI</name>
          <argumentList>
            <argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
            <argument><name>CurrentURI</name><direction>in</direction><relatedStateVariable>AVTransportURI</relatedStateVariable></argument>
            <argument><name>CurrentURIMetaData</name><direction>in</direction><relatedStateVariable>AVTransportURIMetaData</relatedStateVariable></argument>
          </argumentList>
        </action>
        <action>
          <name>GetDeviceCapabilities</name>
          <argumentList>
            <argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
            <argument><name>PlayMedia</name><direction>out</direction><relatedStateVariable>PossiblePlaybackStorageMedia</relatedStateVariable></argument>
            <argument><name>RecMedia</name><direction>out</direction><relatedStateVariable>PossibleRecordStorageMedia</relatedStateVariable></argument>
            <argument><name>RecQualityModes</name><direction>out</direction><relatedStateVariable>PossibleRecordQualityModes</relatedStateVariable></argument>
          </argumentList>
        </action>
        <action>
          <name>GetTransportSettings</name>
          <argumentList>
            <argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
            <argument><name>PlayMode</name><direction>out</direction><relatedStateVariable>CurrentPlayMode</relatedStateVariable></argument>
            <argument><name>RecQualityMode</name><direction>out</direction><relatedStateVariable>CurrentRecordQualityMode</relatedStateVariable></argument>
          </argumentList>
        </action>
        <action>
          <name>GetCurrentTransportActions</name>
          <argumentList>
            <argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
            <argument><name>Actions</name><direction>out</direction><relatedStateVariable>CurrentTransportActions</relatedStateVariable></argument>
          </argumentList>
        </action>
      </actionList>
      <serviceStateTable>
        <stateVariable sendEvents="no"><name>TransportState</name><dataType>string</dataType><allowedValueList><allowedValue>STOPPED</allowedValue><allowedValue>PLAYING</allowedValue><allowedValue>PAUSED_PLAYBACK</allowedValue><allowedValue>TRANSITIONING</allowedValue><allowedValue>NO_MEDIA_PRESENT</allowedValue></allowedValueList></stateVariable>
        <stateVariable sendEvents="no"><name>TransportStatus</name><dataType>string</dataType><allowedValueList><allowedValue>OK</allowedValue><allowedValue>ERROR_OCCURRED</allowedValue></allowedValueList></stateVariable>
        <stateVariable sendEvents="no"><name>PlaybackStorageMedium</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>PossiblePlaybackStorageMedia</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>PossibleRecordStorageMedia</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>RecordStorageMedium</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>CurrentPlayMode</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>TransportPlaySpeed</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>RecordMediumWriteStatus</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>CurrentRecordQualityMode</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>PossibleRecordQualityModes</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>NumberOfTracks</name><dataType>ui4</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>CurrentTrack</name><dataType>ui4</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>CurrentTrackDuration</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>CurrentMediaDuration</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>CurrentTrackMetaData</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>CurrentTrackURI</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>AVTransportURI</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>AVTransportURIMetaData</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>NextAVTransportURI</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>NextAVTransportURIMetaData</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>RelativeTimePosition</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>AbsoluteTimePosition</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>RelativeCounterPosition</name><dataType>i4</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>AbsoluteCounterPosition</name><dataType>i4</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>CurrentTransportActions</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="yes"><name>LastChange</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>A_ARG_TYPE_InstanceID</name><dataType>ui4</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>A_ARG_TYPE_SeekMode</name><dataType>string</dataType><allowedValueList><allowedValue>TRACK_NR</allowedValue><allowedValue>REL_TIME</allowedValue></allowedValueList></stateVariable>
        <stateVariable sendEvents="no"><name>A_ARG_TYPE_SeekTarget</name><dataType>string</dataType></stateVariable>
      </serviceStateTable>
    </scpd>
    """

    private static let renderingControlSCPD = """
    <?xml version="1.0" encoding="utf-8"?>
    <scpd xmlns="urn:schemas-upnp-org:service-1-0">
      <specVersion><major>1</major><minor>0</minor></specVersion>
      <actionList>
        <action>
          <name>GetVolume</name>
          <argumentList>
            <argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
            <argument><name>Channel</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_Channel</relatedStateVariable></argument>
            <argument><name>CurrentVolume</name><direction>out</direction><relatedStateVariable>Volume</relatedStateVariable></argument>
          </argumentList>
        </action>
        <action>
          <name>SetVolume</name>
          <argumentList>
            <argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
            <argument><name>Channel</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_Channel</relatedStateVariable></argument>
            <argument><name>DesiredVolume</name><direction>in</direction><relatedStateVariable>Volume</relatedStateVariable></argument>
          </argumentList>
        </action>
        <action>
          <name>GetMute</name>
          <argumentList>
            <argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
            <argument><name>Channel</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_Channel</relatedStateVariable></argument>
            <argument><name>CurrentMute</name><direction>out</direction><relatedStateVariable>Mute</relatedStateVariable></argument>
          </argumentList>
        </action>
        <action>
          <name>SetMute</name>
          <argumentList>
            <argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
            <argument><name>Channel</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_Channel</relatedStateVariable></argument>
            <argument><name>DesiredMute</name><direction>in</direction><relatedStateVariable>Mute</relatedStateVariable></argument>
          </argumentList>
        </action>
      </actionList>
      <serviceStateTable>
        <stateVariable sendEvents="no"><name>Volume</name><dataType>ui2</dataType><allowedValueRange><minimum>0</minimum><maximum>100</maximum><step>1</step></allowedValueRange></stateVariable>
        <stateVariable sendEvents="no"><name>Mute</name><dataType>boolean</dataType></stateVariable>
        <stateVariable sendEvents="yes"><name>LastChange</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>A_ARG_TYPE_InstanceID</name><dataType>ui4</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>A_ARG_TYPE_Channel</name><dataType>string</dataType><allowedValueList><allowedValue>Master</allowedValue><allowedValue>LF</allowedValue><allowedValue>RF</allowedValue></allowedValueList></stateVariable>
      </serviceStateTable>
    </scpd>
    """

    private static let connectionManagerSCPD = """
    <?xml version="1.0" encoding="utf-8"?>
    <scpd xmlns="urn:schemas-upnp-org:service-1-0">
      <specVersion><major>1</major><minor>0</minor></specVersion>
      <actionList>
        <action>
          <name>GetProtocolInfo</name>
          <argumentList>
            <argument><name>Source</name><direction>out</direction><relatedStateVariable>SourceProtocolInfo</relatedStateVariable></argument>
            <argument><name>Sink</name><direction>out</direction><relatedStateVariable>SinkProtocolInfo</relatedStateVariable></argument>
          </argumentList>
        </action>
        <action>
          <name>GetCurrentConnectionIDs</name>
          <argumentList>
            <argument><name>ConnectionIDs</name><direction>out</direction><relatedStateVariable>CurrentConnectionIDs</relatedStateVariable></argument>
          </argumentList>
        </action>
        <action>
          <name>GetCurrentConnectionInfo</name>
          <argumentList>
            <argument><name>RcsID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_RcsID</relatedStateVariable></argument>
            <argument><name>AVTransportID</name><direction>out</direction><relatedStateVariable>A_ARG_TYPE_AVTransportID</relatedStateVariable></argument>
            <argument><name>ProtocolInfo</name><direction>out</direction><relatedStateVariable>ProtocolInfo</relatedStateVariable></argument>
            <argument><name>PeerConnectionManager</name><direction>out</direction><relatedStateVariable>PeerConnectionManager</relatedStateVariable></argument>
            <argument><name>PeerConnectionID</name><direction>out</direction><relatedStateVariable>A_ARG_TYPE_ConnectionID</relatedStateVariable></argument>
            <argument><name>Direction</name><direction>out</direction><relatedStateVariable>Direction</relatedStateVariable></argument>
            <argument><name>Status</name><direction>out</direction><relatedStateVariable>ConnectionStatus</relatedStateVariable></argument>
          </argumentList>
        </action>
      </actionList>
      <serviceStateTable>
        <stateVariable sendEvents="yes"><name>SourceProtocolInfo</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="yes"><name>SinkProtocolInfo</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="yes"><name>CurrentConnectionIDs</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>A_ARG_TYPE_RcsID</name><dataType>i4</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>A_ARG_TYPE_AVTransportID</name><dataType>i4</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>A_ARG_TYPE_ConnectionID</name><dataType>i4</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>ProtocolInfo</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>PeerConnectionManager</name><dataType>string</dataType></stateVariable>
        <stateVariable sendEvents="no"><name>Direction</name><dataType>string</dataType><allowedValueList><allowedValue>Output</allowedValue><allowedValue>Input</allowedValue></allowedValueList></stateVariable>
        <stateVariable sendEvents="no"><name>ConnectionStatus</name><dataType>string</dataType><allowedValueList><allowedValue>OK</allowedValue><allowedValue>ContentFormatMismatch</allowedValue><allowedValue>InsufficientBandwidth</allowedValue><allowedValue>UnreliableChannel</allowedValue><allowedValue>Unknown</allowedValue></allowedValueList></stateVariable>
      </serviceStateTable>
    </scpd>
    """
}
