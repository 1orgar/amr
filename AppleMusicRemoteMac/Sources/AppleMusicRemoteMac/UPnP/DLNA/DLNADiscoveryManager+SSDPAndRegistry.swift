//
//  DLNADiscoveryManager+SSDPAndRegistry.swift
//  AppleMusicRemoteMac
//
//  SSDP UDP M-SEARCH socket, BluOS probing, LAN SSRF URL validation, 512 KB
//  no-redirect description fetching, anti-self-discovery filter, and <=64 registry.
//

import Darwin
import Foundation

extension DLNADiscoveryManager {
    internal func setupUDPSocket() {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            NSLog("[DLNADiscovery] ❌ Failed to create UDP socket: %d", errno)
            return
        }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var bindAddr = sockaddr_in()
        bindAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_port = 0
        bindAddr.sin_addr.s_addr = in_addr_t(INADDR_ANY)

        let bindRes = withUnsafePointer(to: &bindAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindRes < 0 {
            NSLog("[DLNADiscovery] ❌ Failed to bind UDP socket: %d", errno)
            close(fd)
            return
        }

        var loop: u_char = 1
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_LOOP, &loop, socklen_t(MemoryLayout<u_char>.size))

        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }

        self.udpSocketFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readIncomingDatagram()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.readSource = source
    }

    public func sendMSearch() {
        guard udpSocketFD >= 0 else { return }

        let targets = [
            "urn:schemas-upnp-org:device:MediaRenderer:1",
            "urn:schemas-upnp-org:service:AVTransport:1"
        ]

        var destAddr = sockaddr_in()
        destAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destAddr.sin_family = sa_family_t(AF_INET)
        destAddr.sin_port = in_port_t(1900).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &destAddr.sin_addr)

        for target in targets {
            let msearch = [
                "M-SEARCH * HTTP/1.1",
                "HOST: 239.255.255.250:1900",
                "MAN: \"ssdp:discover\"",
                "MX: 3",
                "ST: \(target)",
                "",
                ""
            ].joined(separator: "\r\n")

            let data = Array(msearch.utf8)
            _ = withUnsafePointer(to: &destAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(udpSocketFD, data, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    public func probeKnownBluOSHosts() {
        let hosts = AppStorageProvider.shared.stringArray(forKey: "BluOSKnownHosts") ?? []
        for host in hosts {
            probeBluOS(host: host)
        }
    }

    public func probeBluOS(host: String, port: Int = 11000) {
        guard (1...65535).contains(port),
              let syncURL = URL(string: "http://\(host):\(port)/SyncStatus"),
              let baseURL = URL(string: "http://\(host):\(port)"),
              Self.isAllowedLANRendererURL(syncURL),
              Self.isAllowedLANRendererURL(baseURL) else {
            return
        }
        var request = URLRequest(url: syncURL)
        request.timeoutInterval = 3.0
        BoundedNoRedirectHTTPClient.shared.fetch(request: request, maxBytes: 256 * 1024) { [weak self] data, response, error in
            guard let self = self,
                  error == nil,
                  response?.statusCode == 200,
                  let data = data,
                  let xml = String(data: data, encoding: .utf8),
                  (xml.contains("<SyncStatus") || xml.contains("<status")) else {
                return
            }

            let name = self.extractXMLAttribute(attr: "name", from: xml) ?? "Bluesound Player"
            let brand = self.extractXMLAttribute(attr: "brand", from: xml) ?? "Bluesound"
            let modelName = self.extractXMLAttribute(attr: "modelName", from: xml) ?? "NODE NANO"
            let mac = self.extractXMLAttribute(attr: "mac", from: xml) ?? host
            let cleanMac = mac.replacingOccurrences(of: ":", with: "").uppercased()

            let uid = "bluos:\(cleanMac)"
            let friendlyTitle = "\(name) (\(brand) \(modelName))"

            let renderer = DiscoveredDLNARenderer(
                id: uid,
                friendlyName: friendlyTitle,
                manufacturer: brand,
                modelName: modelName,
                locationURL: syncURL,
                avTransportControlURL: nil,
                renderingControlURL: nil,
                isBluOS: true,
                bluOSBaseURL: baseURL,
                lastSeen: Date()
            )

            var hosts = AppStorageProvider.shared.stringArray(forKey: "BluOSKnownHosts") ?? []
            if !hosts.contains(host) {
                hosts.append(host)
                AppStorageProvider.shared.set(hosts, forKey: "BluOSKnownHosts")
            }

            self.registerDevice(renderer)
        }
    }

    // MARK: - SSDP Parsing, SSRF Validation & Registry

    private static func extractSocketSenderIP(_ storage: inout sockaddr_storage) -> String? {
        return withUnsafePointer(to: &storage) { ptr in
            let family = Int32(ptr.pointee.ss_family)
            if family == AF_INET {
                return ptr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sinPtr in
                    var addr = sinPtr.pointee.sin_addr
                    var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    guard inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
                    return String(cString: buf)
                }
            } else if family == AF_INET6 {
                return ptr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6Ptr in
                    var addr6 = sin6Ptr.pointee.sin6_addr
                    var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                    guard inet_ntop(AF_INET6, &addr6, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil else { return nil }
                    let raw = String(cString: buf)
                    if let pct = raw.firstIndex(of: "%") {
                        return String(raw[..<pct])
                    }
                    return raw
                }
            }
            return nil
        }
    }

    internal static func normalizeLiteralIP(_ rawHost: String) -> String? {
        var clean = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[] \t\r\n")).lowercased()
        if let pct = clean.firstIndex(of: "%") {
            clean = String(clean[..<pct])
        }
        guard !clean.isEmpty else { return nil }
        if clean.hasPrefix("::ffff:") {
            clean = String(clean.dropFirst("::ffff:".count))
        }
        var addr4 = in_addr()
        if inet_pton(AF_INET, clean, &addr4) == 1 {
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            if inet_ntop(AF_INET, &addr4, &buf, socklen_t(INET_ADDRSTRLEN)) != nil {
                return String(cString: buf)
            }
            return clean
        }
        var addr6 = in6_addr()
        if inet_pton(AF_INET6, clean, &addr6) == 1 {
            var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            if inet_ntop(AF_INET6, &addr6, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil {
                return String(cString: buf).lowercased()
            }
            return clean
        }
        return nil
    }

    public static func isAllowedLANRendererURL(_ url: URL, expectedSenderIP: String? = nil) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard url.user == nil && url.password == nil else {
            return false
        }
        guard let rawHost = url.host, let ip = normalizeLiteralIP(rawHost) else {
            return false
        }

        if let senderRaw = expectedSenderIP, !senderRaw.isEmpty {
            guard let senderIP = normalizeLiteralIP(senderRaw), senderIP == ip else {
                return false
            }
        }

        var addr4 = in_addr()
        if inet_pton(AF_INET, ip, &addr4) == 1 {
            let hostOrder = UInt32(bigEndian: addr4.s_addr)
            let b0 = Int((hostOrder >> 24) & 0xFF)
            let b1 = Int((hostOrder >> 16) & 0xFF)
            let b2 = Int((hostOrder >> 8) & 0xFF)
            let b3 = Int(hostOrder & 0xFF)

            if b0 == 127 || b0 == 0 || b0 >= 224 || b3 == 255 {
                return false
            }
            if b0 == 169 && b1 == 254 && b2 == 169 && b3 == 254 {
                return false
            }
            if b0 == 10 { return true }
            if b0 == 172 && (16...31).contains(b1) { return true }
            if b0 == 192 && b1 == 168 { return true }
            if b0 == 169 && b1 == 254 { return true }
            return false
        }

        var addr6 = in6_addr()
        if inet_pton(AF_INET6, ip, &addr6) == 1 {
            let bytes = withUnsafeBytes(of: &addr6) { Array($0) }
            guard bytes.count == 16 else { return false }
            let isAllZero = bytes.allSatisfy { $0 == 0 }
            let isLoopback = bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes[15] == 1
            if isAllZero || isLoopback || bytes[0] == 0xFF {
                return false
            }
            if (bytes[0] & 0xFE) == 0xFC { return true }
            if bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80 { return true }
            return false
        }

        return false
    }

    private func readIncomingDatagram() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while udpSocketFD >= 0 {
            var srcAddr = sockaddr_storage()
            var addrLen = socklen_t(MemoryLayout<sockaddr_storage>.size)

            let bytesRead = withUnsafeMutablePointer(to: &srcAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(udpSocketFD, &buffer, buffer.count, 0, $0, &addrLen)
                }
            }

            guard bytesRead > 0 else { break }
            let senderIP = Self.extractSocketSenderIP(&srcAddr)
            if let text = String(bytes: buffer[0..<bytesRead], encoding: .utf8) {
                processSSDPMessage(text, senderIP: senderIP)
            }
        }
    }

    public func processSSDPMessage(_ text: String, senderIP: String? = nil) {
        guard text.contains("200 OK") || text.contains("NOTIFY") else { return }

        guard let locationStr = extractHeader("LOCATION", from: text),
              let locationURL = URL(string: locationStr) else {
            return
        }

        let usn = extractHeader("USN", from: text) ?? ""
        if isSelfDevice(udn: usn, location: locationURL, friendlyName: "") {
            return
        }

        guard Self.isAllowedLANRendererURL(locationURL, expectedSenderIP: senderIP) else {
            NSLog("[DLNADiscovery] 🛡️ Blocked disallowed or spoofed SSDP LOCATION URL: %@ (sender: %@)", locationURL.absoluteString, senderIP ?? "unknown")
            return
        }

        fetchDeviceDescription(from: locationURL)
    }

    public func fetchDeviceDescription(from url: URL) {
        guard Self.isAllowedLANRendererURL(url) else {
            NSLog("[DLNADiscovery] 🛡️ Blocked fetchDeviceDescription for disallowed URL: %@", url.absoluteString)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        BoundedNoRedirectHTTPClient.shared.fetch(request: request, maxBytes: 512 * 1024) { [weak self] data, response, error in
            guard let self = self,
                  error == nil,
                  let statusCode = response?.statusCode,
                  (200...299).contains(statusCode),
                  let data = data,
                  let xml = String(data: data, encoding: .utf8) else {
                return
            }
            self.parseAndRegisterDevice(xml: xml, locationURL: url)
        }
    }

    public func parseAndRegisterDevice(xml: String, locationURL: URL) {
        guard xml.contains("urn:schemas-upnp-org:device:MediaRenderer:1") || xml.contains("MediaRenderer") else {
            return
        }

        let friendlyName = extractXMLTagValue(tag: "friendlyName", from: xml) ?? "Unknown DLNA Renderer"
        let manufacturer = extractXMLTagValue(tag: "manufacturer", from: xml) ?? "Unknown"
        let modelName = extractXMLTagValue(tag: "modelName", from: xml) ?? "MediaRenderer"
        let udn = extractXMLTagValue(tag: "UDN", from: xml) ?? locationURL.absoluteString

        if isSelfDevice(udn: udn, location: locationURL, friendlyName: friendlyName, manufacturer: manufacturer, modelName: modelName) {
            NSLog("[DLNADiscovery] 🛡️ Ignored self AMR UPnP instance: '%@' (%@)", friendlyName, udn)
            return
        }

        let avTransportControlURL = extractServiceControlURL(serviceType: "AVTransport", from: xml, baseURL: locationURL)
        let renderingControlURL = extractServiceControlURL(serviceType: "RenderingControl", from: xml, baseURL: locationURL)

        let renderer = DiscoveredDLNARenderer(
            id: udn,
            friendlyName: friendlyName,
            manufacturer: manufacturer,
            modelName: modelName,
            locationURL: locationURL,
            avTransportControlURL: avTransportControlURL,
            renderingControlURL: renderingControlURL,
            lastSeen: Date()
        )
        registerDevice(renderer)
    }

    public func registerDevice(_ renderer: DiscoveredDLNARenderer) {
        if isSelfDevice(udn: renderer.id, location: renderer.locationURL, friendlyName: renderer.friendlyName, manufacturer: renderer.manufacturer, modelName: renderer.modelName) {
            return
        }

        lock.lock()
        let isNew = discoveredRenderers[renderer.id] == nil
        if isNew && discoveredRenderers.count >= Self.maxDiscoveredRenderers {
            let activeRaw = AppStorageProvider.shared.string(forKey: Self.activeRendererDefaultsKey) ?? ""
            let candidates = discoveredRenderers.values
                .filter { $0.id != activeRaw && "dlna:\($0.id)" != activeRaw }
                .sorted { $0.lastSeen < $1.lastSeen }
            if let oldest = candidates.first {
                discoveredRenderers.removeValue(forKey: oldest.id)
            }
        }
        discoveredRenderers[renderer.id] = renderer
        let currentList = Array(discoveredRenderers.values)
        lock.unlock()

        resolveAndCacheHostIfNeeded(renderer.locationURL.host)
        resolveAndCacheHostIfNeeded(renderer.bluOSBaseURL?.host)

        if isNew {
            NSLog("[DLNADiscovery] 🎵 Discovered DLNA MediaRenderer: '%@' (%@ - %@) at %@",
                  renderer.friendlyName, renderer.manufacturer, renderer.modelName, renderer.locationURL.absoluteString)
            onDevicesChanged?(currentList)
            scheduleDebouncedBroadcastAudioDevices()
        }

        if renderer.isBluOS,
           (activeRendererUID == renderer.id || activeRendererUID == "dlna:\(renderer.id)"),
           bluOSPollingTask == nil {
            startBluOSStatusMonitoring(renderer: renderer)
        }
    }

    internal func scheduleDebouncedBroadcastAudioDevices() {
        lock.lock()
        broadcastDebounceWorkItem?.cancel()
        let work = DispatchWorkItem {
            WebSocketServer.shared.broadcastAudioDevices()
        }
        broadcastDebounceWorkItem = work
        lock.unlock()
        queue.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    public func isSelfDevice(udn: String, location: URL?, friendlyName: String, manufacturer: String = "", modelName: String = "") -> Bool {
        let selfUdn = SSDPService.shared.deviceUDN.lowercased()
        let selfUuid = SSDPService.shared.deviceUUID.lowercased()
        let lowerUdn = udn.lowercased()

        if !selfUdn.isEmpty && (lowerUdn == selfUdn || lowerUdn.contains(selfUdn) || lowerUdn.contains(selfUuid)) {
            return true
        }

        if let loc = location, let host = loc.host?.lowercased() {
            let port = loc.port ?? 80
            if port == SSDPService.shared.httpPort || port == 8090 {
                let localIPs = Set(WebSocketServer.shared.getLANIPAddresses().map { $0.lowercased() })
                if host == "127.0.0.1" || host == "localhost" || host == "::1" || localIPs.contains(host) {
                    return true
                }
            }
        }

        let lowerMan = manufacturer.lowercased()
        let lowerModel = modelName.lowercased()
        if lowerMan.contains("apple music remote") || lowerModel == "amr-mediarenderer" {
            return true
        }

        let selfName = SSDPService.shared.friendlyName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedFriendly = friendlyName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !selfName.isEmpty && (trimmedFriendly == selfName || trimmedFriendly == "amr" || trimmedFriendly == "apple music remote (mac)") {
            return true
        }
        return false
    }

    public func getDiscoveredRenderers() -> [DiscoveredDLNARenderer] {
        lock.lock()
        defer { lock.unlock() }
        return Array(discoveredRenderers.values).sorted(by: { $0.friendlyName < $1.friendlyName })
    }

    public func getDiscoveredDevices() -> [[String: Any]] {
        return getDiscoveredRenderers().map { $0.dictionary }
    }

    public func getDiscoveredCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return discoveredRenderers.count
    }

    internal func cleanupStaleDevices() {
        let cutoff = Date().addingTimeInterval(-300)
        let activeRaw = AppStorageProvider.shared.string(forKey: Self.activeRendererDefaultsKey) ?? ""
        lock.lock()
        let beforeCount = discoveredRenderers.count
        discoveredRenderers = discoveredRenderers.filter {
            $0.value.lastSeen >= cutoff || $0.key == activeRaw || "dlna:\($0.key)" == activeRaw
        }
        let afterCount = discoveredRenderers.count
        let changed = beforeCount != afterCount
        let currentList = Array(discoveredRenderers.values)
        lock.unlock()

        if changed {
            NSLog("[DLNADiscovery] 🧹 Cleaned up stale DLNA devices (Remaining: %d)", afterCount)
            onDevicesChanged?(currentList)
            scheduleDebouncedBroadcastAudioDevices()
        }
    }
}
