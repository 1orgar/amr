//
//  DiscoveredDLNARenderer.swift
//  AppleMusicRemoteMac
//
//  Model for discovered UPnP/DLNA MediaRenderers and BluOS streamers, plus
//  Bonjour (_musc._tcp) resolution with LAN SSRF & no-redirect protections.
//

import Darwin
import Foundation

public struct DiscoveredDLNARenderer: Identifiable, Sendable {
    public let id: String // UDN or "bluos:MAC"
    public let friendlyName: String
    public let manufacturer: String
    public let modelName: String
    public let locationURL: URL
    public let avTransportControlURL: URL?
    public let renderingControlURL: URL?
    public let isBluOS: Bool
    public let bluOSBaseURL: URL?
    public let lastSeen: Date

    public init(
        id: String,
        friendlyName: String,
        manufacturer: String,
        modelName: String,
        locationURL: URL,
        avTransportControlURL: URL? = nil,
        renderingControlURL: URL? = nil,
        isBluOS: Bool = false,
        bluOSBaseURL: URL? = nil,
        lastSeen: Date = Date()
    ) {
        self.id = id
        self.friendlyName = friendlyName
        self.manufacturer = manufacturer
        self.modelName = modelName
        self.locationURL = locationURL
        self.avTransportControlURL = avTransportControlURL
        self.renderingControlURL = renderingControlURL
        self.isBluOS = isBluOS
        self.bluOSBaseURL = bluOSBaseURL
        self.lastSeen = lastSeen
    }

    public var numericId: Int {
        Int(truncatingIfNeeded: id.hashValue.magnitude & 0x3FFF_FFFF) % 1_000_000 + 900_000
    }

    public var isSelected: Bool {
        guard let active = DLNADiscoveryManager.shared.activeRendererUID else { return false }
        return active == "dlna:\(id)" || active == id
    }

    public var dictionary: [String: Any] {
        return [
            "id": numericId,
            "uid": id.hasPrefix("dlna:") ? id : "dlna:\(id)",
            "name": friendlyName,
            "icon": "network",
            "type": "dlna",
            "protocol": isBluOS ? "bluos" : "upnp",
            "manufacturer": manufacturer,
            "model": modelName,
            "location": locationURL.absoluteString,
            "controlUrl": avTransportControlURL?.absoluteString ?? (bluOSBaseURL?.absoluteString ?? ""),
            "currentSampleRate": 192000.0,
            "availableSampleRates": [44100.0, 48000.0, 88200.0, 96000.0, 176400.0, 192000.0],
            "isDefault": isSelected
        ]
    }
}

internal final class BluOSNetServiceDelegate: NSObject, NetServiceBrowserDelegate, NetServiceDelegate, @unchecked Sendable {
    weak var manager: DLNADiscoveryManager?
    private var pendingServices: [NetService] = []
    private let lock = NSLock()

    init(manager: DLNADiscoveryManager) {
        self.manager = manager
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        lock.lock()
        if pendingServices.count >= 64 {
            pendingServices.removeFirst()
        }
        pendingServices.append(service)
        lock.unlock()
        service.delegate = self
        service.schedule(in: .main, forMode: .common)
        service.resolve(withTimeout: 4.0)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        lock.lock()
        pendingServices.removeAll(where: { $0.name == service.name })
        lock.unlock()
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        lock.lock()
        pendingServices.removeAll(where: { $0 === sender || $0.name == sender.name })
        lock.unlock()
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        lock.lock()
        pendingServices.removeAll(where: { $0 === sender || $0.name == sender.name })
        lock.unlock()
        guard let manager = manager else { return }

        var resolvedIP: String?
        var resolvedIPv6: String?
        for data in sender.addresses ?? [] {
            data.withUnsafeBytes { raw in
                guard let addr = raw.bindMemory(to: sockaddr.self).baseAddress else { return }
                let family = addr.pointee.sa_family
                if family == sa_family_t(AF_INET) {
                    let addr4 = raw.bindMemory(to: sockaddr_in.self).baseAddress!
                    var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    var sinAddr = addr4.pointee.sin_addr
                    if inet_ntop(AF_INET, &sinAddr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil {
                        resolvedIP = String(cString: buf)
                    }
                } else if family == sa_family_t(AF_INET6) {
                    let addr6 = raw.bindMemory(to: sockaddr_in6.self).baseAddress!
                    var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                    var sin6Addr = addr6.pointee.sin6_addr
                    if inet_ntop(AF_INET6, &sin6Addr, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil {
                        let ip6 = String(cString: buf)
                        if resolvedIPv6 == nil || !ip6.lowercased().hasPrefix("fe80:") {
                            resolvedIPv6 = ip6
                        }
                    }
                }
            }
            if resolvedIP != nil { break }
        }

        // Only connect to resolved literal LAN IP addresses (never untrusted mDNS hostName strings)
        guard let rawHost = resolvedIP ?? resolvedIPv6 else {
            return
        }
        let ip = (rawHost.contains(":") && !rawHost.hasPrefix("[")) ? "[\(rawHost)]" : rawHost
        let port = (1...65535).contains(sender.port) ? sender.port : 11000

        guard let syncURL = URL(string: "http://\(ip):\(port)/SyncStatus"),
              let baseURL = URL(string: "http://\(ip):\(port)"),
              DLNADiscoveryManager.isAllowedLANRendererURL(syncURL),
              DLNADiscoveryManager.isAllowedLANRendererURL(baseURL) else {
            NSLog("[DLNADiscovery] 🛡️ Blocked disallowed Bonjour BluOS address: %@:%d", ip, port)
            return
        }

        var request = URLRequest(url: syncURL)
        request.timeoutInterval = 3.0
        let serviceName = sender.name
        BoundedNoRedirectHTTPClient.shared.fetch(request: request, maxBytes: 256 * 1024) { [weak manager] data, response, error in
            guard let manager = manager,
                  error == nil,
                  response?.statusCode == 200,
                  let data = data,
                  let xml = String(data: data, encoding: .utf8),
                  (xml.contains("<SyncStatus") || xml.contains("<status")) else {
                return
            }

            let name = manager.extractXMLAttribute(attr: "name", from: xml) ?? serviceName
            let brand = manager.extractXMLAttribute(attr: "brand", from: xml) ?? "Bluesound"
            let modelName = manager.extractXMLAttribute(attr: "modelName", from: xml) ?? "NODE NANO"
            let mac = manager.extractXMLAttribute(attr: "mac", from: xml) ?? serviceName
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

            manager.registerDevice(renderer)
        }
    }
}
