//
//  WebSocketServer+HTTPAuth.swift
//  AppleMusicRemoteMac
//
//  HTTP request authentication, Host/Origin/CSRF guards, DLNA stream_token verification,
//  and Apple ID / DSID masking helpers.
//

import Foundation
import Network

extension WebSocketServer {
    public func isAllowedOrigin(_ origin: String, hostHeader: String? = nil) -> Bool {
        return isAllowedWebSocketOrigin(origin, requestHost: hostHeader)
    }

    internal static func maskAppleId(_ email: String?) -> String? {
        guard let raw = email?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.contains("***") { return raw }
        let parts = raw.split(separator: "@", maxSplits: 1)
        if parts.count == 2 {
            let local = String(parts[0])
            let domain = String(parts[1])
            let prefix = String(local.prefix(1))
            return "\(prefix)***@\(domain)"
        }
        return "\(raw.prefix(1))***"
    }

    internal static func maskDsid(_ dsid: String?) -> String? {
        guard let raw = dsid?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.contains("***") { return raw }
        if raw.count > 4 {
            return "***\(raw.suffix(4))"
        }
        return "***"
    }

    internal static func maskedAccountHealth(_ status: AccountHealthStatus) -> AccountHealthStatus {
        var copy = status
        let maskedEmail = maskAppleId(status.macAppleId)
        let maskedId = maskDsid(status.macDsid)
        if let origEmail = status.macAppleId, !origEmail.isEmpty, let mEmail = maskedEmail {
            copy.message = copy.message.replacingOccurrences(of: origEmail, with: mEmail)
        }
        if let origDsid = status.macDsid, !origDsid.isEmpty, let mDsid = maskedId {
            copy.message = copy.message.replacingOccurrences(of: origDsid, with: mDsid)
        }
        copy.macAppleId = maskedEmail
        copy.macDsid = maskedId
        return copy
    }

    internal func extractQueryParameter(named paramName: String, from fullPath: String) -> String? {
        guard let qIdx = fullPath.firstIndex(of: "?") else { return nil }
        let rawQS = String(fullPath[fullPath.index(after: qIdx)...])
        let target = paramName.lowercased()
        let candidates: [String] = rawQS.contains("%")
            ? [rawQS, rawQS.removingPercentEncoding].compactMap { $0 }
            : [rawQS]
        for qs in candidates {
            for pair in qs.components(separatedBy: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                if kv.count == 2 && kv[0].lowercased() == target {
                    let raw = String(kv[1]).replacingOccurrences(of: "+", with: "%20")
                    return (raw.removingPercentEncoding ?? raw).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return nil
    }

    /// S-02 / S-03: Requires BOTH selected DLNA renderer IP match AND valid per-session `stream_token`.
    internal func isAllowedDLNAStreamRequest(connection: NWConnection, fullPath: String) -> Bool {
        let remoteIP = extractRemoteIP(from: connection)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !remoteIP.isEmpty else { return false }
        guard let token = extractQueryParameter(named: "stream_token", from: fullPath),
              !token.isEmpty,
              DLNADiscoveryManager.shared.validateStreamSessionToken(token) else {
            return false
        }
        return DLNADiscoveryManager.shared.matchesSelectedRendererIP(remoteIP)
    }

    /// Authorizes read-only album artwork requests from private LAN / multi-VLAN peers (e.g. Home Assistant
    /// fetching BluOS/DLNA `stream_token` cover URLs or UPnP DMR `<upnp:albumArtURI>` endpoints) while
    /// keeping unpaired browser sessions and WAN peers blocked.
    internal func isAllowedLANArtworkRequest(headerString: String, fullPath: String, connection: NWConnection) -> Bool {
        let remoteIP = extractRemoteIP(from: connection)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !remoteIP.isEmpty, LANSubnetGuard.isPrivateLANOrLoopbackPeer(remoteIP) else {
            return false
        }
        if let token = extractQueryParameter(named: "stream_token", from: fullPath),
           !token.isEmpty,
           DLNADiscoveryManager.shared.validateStreamSessionToken(token) {
            return true
        }
        guard UPnPMediaRendererServer.shared.isEnabled else {
            return false
        }
        let hasOrigin = (nonEmpty(extractHeader(named: "origin", from: headerString)) != nil)
        let secFetchMode = extractHeader(named: "sec-fetch-mode", from: headerString)?.lowercased() ?? ""
        let secFetchSite = extractHeader(named: "sec-fetch-site", from: headerString)?.lowercased() ?? ""
        let ua = extractHeader(named: "user-agent", from: headerString) ?? ""
        if hasOrigin || !secFetchMode.isEmpty || !secFetchSite.isEmpty || ua.contains("Mozilla/") {
            return false
        }
        return true
    }

    /// Serves cached or fetched remote cover bytes directly (200 OK) for UPnP/DLNA/Home Assistant clients
    /// so isolated VLANs and non-redirecting media players never fail on 302 redirects to CDN URLs.
    internal func serveArtworkURLOrRedirect(
        _ remoteUrlStr: String,
        preferDirectBytes: Bool,
        connection: NWConnection,
        cacheSeconds: Int = 86400
    ) {
        if !preferDirectBytes {
            sendRedirect(location: remoteUrlStr, connection: connection, cacheSeconds: cacheSeconds)
            return
        }
        if let disk = ArtworkDiskCache.shared.get(key: remoteUrlStr) {
            sendHTTPResponse(status: "200 OK", contentType: "image/jpeg", body: disk, connection: connection, cacheSeconds: cacheSeconds)
            return
        }
        guard let url = URL(string: remoteUrlStr), ArtworkService.isAllowedRemoteArtworkURL(url) else {
            sendDefaultArtwork(connection: connection)
            return
        }
        let req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 4.0)
        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            guard let self = self else { return }
            if let d = data, !d.isEmpty, let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                ArtworkDiskCache.shared.set(key: remoteUrlStr, data: d)
                let mime = http.mimeType ?? "image/jpeg"
                self.sendHTTPResponse(status: "200 OK", contentType: mime, body: d, connection: connection, cacheSeconds: cacheSeconds)
            } else {
                self.sendDefaultArtwork(connection: connection)
            }
        }.resume()
    }

    internal func serveStationCoverAssetOrRedirect(
        assetPath: String,
        preferDirectBytes: Bool,
        connection: NWConnection,
        cacheSeconds: Int = 86400
    ) {
        if !preferDirectBytes {
            sendRedirect(location: assetPath, connection: connection, cacheSeconds: cacheSeconds)
            return
        }
        let subpath = assetPath.hasPrefix("/") ? String(assetPath.dropFirst()) : assetPath
        if !subpath.lowercased().hasSuffix(".svg"), let data = loadWebBinaryAsset(subpath: subpath) {
            let ct = subpath.lowercased().hasSuffix(".jpg") ? "image/jpeg" : "image/png"
            sendHTTPResponse(status: "200 OK", contentType: ct, body: data, connection: connection, cacheSeconds: cacheSeconds)
        } else {
            sendDefaultArtwork(connection: connection)
        }
    }

    internal static func isLoopbackAddress(_ rawIP: String) -> Bool {
        let clean = rawIP.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return clean == "127.0.0.1" || clean == "::1" || clean == "localhost" || clean == "::ffff:127.0.0.1"
    }

    internal func isLocalhostConnection(_ connection: NWConnection) -> Bool {
        Self.isLoopbackAddress(extractRemoteIP(from: connection))
    }

    internal func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else {
            return nil
        }
        return t
    }

    internal func canLocalhostMeasureRoom() -> Bool {
        let localhostRecords = ClientDeviceManager.shared.getAllDevices().filter {
            Self.isLoopbackAddress($0.lastIPAddress)
        }
        if localhostRecords.contains(where: { !$0.isAuthorized || !$0.allowRoomMeasurement }) {
            return false
        }
        return true
    }

    internal func canDeviceSelectDAC(deviceId: String) -> Bool {
        guard ClientDeviceManager.shared.isDeviceAuthorized(deviceId: deviceId),
              let record = ClientDeviceManager.shared.getDevice(deviceId: deviceId) else {
            return false
        }
        return record.allowDACSelection
    }

    internal func canLocalhostSelectDAC() -> Bool {
        let localhostRecords = ClientDeviceManager.shared.getAllDevices().filter {
            Self.isLoopbackAddress($0.lastIPAddress)
        }
        if localhostRecords.contains(where: { !$0.isAuthorized || !$0.allowDACSelection }) {
            return false
        }
        return true
    }

    /// S-02: GET /api/duck and /api/unduck require explicit `X-AMR-Device-ID` or `Authorization: Bearer`
    /// (rejecting bare cookie / bare loopback IP GET so `<img src>` CSRF is impossible).
    internal func isDuckingGETRequestAuthorized(headerString: String, fullPath: String, connection: NWConnection) -> Bool {
        let secFetchSite = extractHeader(named: "sec-fetch-site", from: headerString)?.lowercased() ?? ""
        let secFetchMode = extractHeader(named: "sec-fetch-mode", from: headerString)?.lowercased() ?? ""
        if secFetchSite == "cross-site" || secFetchMode == "no-cors" || secFetchMode == "navigate" {
            return false
        }
        let hasExplicitDeviceHeader = (nonEmpty(extractHeader(named: "x-amr-device-id", from: headerString)) != nil)
        let apiToken = nonEmpty(extractHeader(named: "authorization", from: headerString))
            ?? nonEmpty(extractHeader(named: "x-amr-api-token", from: headerString))
        let hasExplicitAPIToken = ClientDeviceManager.shared.validateLocalAPIToken(apiToken)
        guard hasExplicitDeviceHeader || hasExplicitAPIToken else {
            return false
        }
        return isHTTPRequestAuthorized(headerString: headerString, fullPath: fullPath, bodyData: Data(), connection: connection)
    }

    internal func isHTTPRequestAuthorized(headerString: String, fullPath: String, bodyData: Data, connection: NWConnection) -> Bool {
        let hostHeader = extractHeader(named: "host", from: headerString)
        guard isValidHostHeader(hostHeader) else {
            return false
        }

        let originHeader = extractHeader(named: "origin", from: headerString)
        let hasOrigin = (nonEmpty(originHeader) != nil)
        let secFetchMode = extractHeader(named: "sec-fetch-mode", from: headerString)?.lowercased() ?? ""
        let secFetchSite = extractHeader(named: "sec-fetch-site", from: headerString)?.lowercased() ?? ""
        let ua = extractHeader(named: "user-agent", from: headerString) ?? ""

        if secFetchSite == "cross-site" {
            return false
        }

        if let origin = originHeader, !origin.isEmpty {
            guard isAllowedOrigin(origin, hostHeader: hostHeader) else {
                return false
            }
        }

        let apiToken = nonEmpty(extractHeader(named: "authorization", from: headerString))
            ?? nonEmpty(extractHeader(named: "x-amr-api-token", from: headerString))
        if ClientDeviceManager.shared.validateLocalAPIToken(apiToken) {
            return true
        }

        var candidateIds: [String] = []
        if let hdrId = nonEmpty(extractHeader(named: "x-amr-device-id", from: headerString)) {
            candidateIds.append(hdrId)
        }
        if let cookieId = nonEmpty(extractCookie(named: "amr_device_uid", from: headerString)) {
            candidateIds.append(cookieId)
        }
        if let qIdx = fullPath.firstIndex(of: "?") {
            let qs = String(fullPath[fullPath.index(after: qIdx)...])
            for pair in qs.components(separatedBy: "&") {
                let kv = pair.components(separatedBy: "=")
                if kv.count == 2 && (kv[0] == "device_id" || kv[0] == "deviceId") {
                    let val = kv[1].replacingOccurrences(of: "+", with: "%20").removingPercentEncoding ?? kv[1]
                    if let clean = nonEmpty(val) {
                        candidateIds.append(clean)
                    }
                }
            }
        }
        if !bodyData.isEmpty,
           let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] {
            if let topId = nonEmpty((json["device_id"] as? String) ?? (json["deviceId"] as? String)) {
                candidateIds.append(topId)
            }
            if let params = json["params"] as? [String: Any],
               let pId = nonEmpty((params["device_id"] as? String) ?? (params["deviceId"] as? String)) {
                candidateIds.append(pId)
            }
        }

        let remoteIP = extractRemoteIP(from: connection).lowercased()
        let providedSecret = nonEmpty(extractHeader(named: "x-amr-device-secret", from: headerString))
            ?? nonEmpty(extractCookie(named: "amr_device_secret", from: headerString))

        if !candidateIds.isEmpty {
            return candidateIds.contains(where: {
                ClientDeviceManager.shared.isHTTPDeviceAuthorized(
                    deviceId: $0,
                    providedSecret: providedSecret,
                    remoteIP: remoteIP
                )
            })
        }

        // Reject any unauthenticated browser request (even on loopback)
        if hasOrigin || !secFetchMode.isEmpty || !secFetchSite.isEmpty || ua.contains("Mozilla/") {
            return false
        }

        if Self.isLoopbackAddress(remoteIP) {
            return true
        }

        return false
    }
}
