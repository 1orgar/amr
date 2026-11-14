//
//  DLNADiscoveryManager.swift
//  AppleMusicRemoteMac
//
//  Discovers DLNA / UPnP MediaRenderer devices (Bluesound Nano, WiiM, Eversolo, etc.)
//  Includes strict anti-self-discovery filtering to never expose AMR's own UPnP server.
//

import Foundation
import Network
import Darwin

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
        abs(id.hashValue) % 1_000_000 + 900_000
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

private final class BluOSNetServiceDelegate: NSObject, NetServiceBrowserDelegate, NetServiceDelegate, @unchecked Sendable {
    weak var manager: DLNADiscoveryManager?
    private var pendingServices: [NetService] = []
    private let lock = NSLock()

    init(manager: DLNADiscoveryManager) {
        self.manager = manager
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        lock.lock()
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

        guard let rawHost = resolvedIP ?? resolvedIPv6 ?? sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")) else {
            return
        }
        let ip = (rawHost.contains(":") && !rawHost.hasPrefix("[")) ? "[\(rawHost)]" : rawHost

        let port = sender.port > 0 ? sender.port : 11000
        guard let syncURL = URL(string: "http://\(ip):\(port)/SyncStatus") else { return }

        var request = URLRequest(url: syncURL)
        request.timeoutInterval = 3.0
        URLSession.shared.dataTask(with: request) { [weak manager] data, response, error in
            guard let manager = manager,
                  error == nil,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let data = data,
                  let xml = String(data: data, encoding: .utf8),
                  (xml.contains("<SyncStatus") || xml.contains("<status")) else {
                return
            }

            let name = manager.extractXMLAttribute(attr: "name", from: xml) ?? sender.name
            let brand = manager.extractXMLAttribute(attr: "brand", from: xml) ?? "Bluesound"
            let modelName = manager.extractXMLAttribute(attr: "modelName", from: xml) ?? "NODE NANO"
            let mac = manager.extractXMLAttribute(attr: "mac", from: xml) ?? sender.name
            let cleanMac = mac.replacingOccurrences(of: ":", with: "").uppercased()

            let uid = "bluos:\(cleanMac)"
            let friendlyTitle = "\(name) (\(brand) \(modelName))"
            guard let baseURL = URL(string: "http://\(ip):\(port)") else { return }

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
        }.resume()
    }
}

public final class DLNADiscoveryManager: @unchecked Sendable {
    public static let shared = DLNADiscoveryManager()

    public static let defaultsKey = "DiscoverDLNARenderers"

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "org.ksholokhov.amr.dlna.discovery", qos: .utility)
    private var scanTimer: DispatchSourceTimer?
    private var cleanupTimer: DispatchSourceTimer?
    private var udpSocketFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var netServiceBrowser: NetServiceBrowser?
    private var netServiceDelegate: BluOSNetServiceDelegate?

    private var discoveredRenderers: [String: DiscoveredDLNARenderer] = [:]
    private var resolvedHostIPs: [String: Set<String>] = [:]

    private let handlersLock = NSLock()
    private var _onDevicesChanged: (([DiscoveredDLNARenderer]) -> Void)?
    private var devicesChangedObservers: [String: ([DiscoveredDLNARenderer]) -> Void] = [:]

    public func addDevicesChangedObserver(id: String, handler: @escaping ([DiscoveredDLNARenderer]) -> Void) {
        handlersLock.lock()
        devicesChangedObservers[id] = handler
        handlersLock.unlock()
    }

    public var onDevicesChanged: (([DiscoveredDLNARenderer]) -> Void)? {
        get {
            handlersLock.lock()
            let primary = _onDevicesChanged
            let observers = Array(devicesChangedObservers.values)
            handlersLock.unlock()
            guard primary != nil || !observers.isEmpty else { return nil }
            return { devices in
                primary?(devices)
                for observer in observers {
                    observer(devices)
                }
            }
        }
        set {
            handlersLock.lock()
            _onDevicesChanged = newValue
            handlersLock.unlock()
        }
    }

    public static let activeRendererDefaultsKey = "ActiveDLNARendererUID"

    private var bluOSPollingTask: Task<Void, Never>?
    private var lastKnownBluOSState: String = ""
    private var lastLocalActionDate: Date = Date.distantPast
    private var lastTrackId: String = ""
    private var lastTrackTitle: String = ""
    private var lastTrackArtist: String = ""
    private var lastSentStreamRate: Int = 0
    private var lastSentStreamDepth: Int = 0
    private var lastSentStreamTitle: String = ""
    private var lastSentStreamDate: Date = Date.distantPast

    public func markLocalAction() {
        lock.lock()
        lastLocalActionDate = Date()
        lock.unlock()
    }

    public func timeSinceLastLocalAction() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Date().timeIntervalSince(lastLocalActionDate)
    }

    public var activeRendererUID: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return UserDefaults.standard.string(forKey: Self.activeRendererDefaultsKey)
        }
        set {
            lock.lock()
            if let val = newValue {
                UserDefaults.standard.set(val, forKey: Self.activeRendererDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.activeRendererDefaultsKey)
            }
            lock.unlock()
        }
    }

    public var hasActiveRenderer: Bool {
        return activeRendererUID != nil
    }

    @discardableResult
    public func selectRenderer(uid: String) -> DiscoveredDLNARenderer? {
        lock.lock()
        let cleanId = uid.hasPrefix("dlna:") ? String(uid.dropFirst(5)) : uid
        guard let renderer = discoveredRenderers[cleanId] ?? discoveredRenderers.values.first(where: { $0.id == cleanId || "dlna:\($0.id)" == uid }) else {
            lock.unlock()
            return nil
        }
        UserDefaults.standard.set("dlna:\(renderer.id)", forKey: Self.activeRendererDefaultsKey)
        lock.unlock()

        resolveAndCacheHostIfNeeded(renderer.locationURL.host)
        resolveAndCacheHostIfNeeded(renderer.bluOSBaseURL?.host)

        if renderer.isBluOS {
            startBluOSStatusMonitoring(renderer: renderer)
        }
        return renderer
    }

    internal static func normalizeHost(_ raw: String) -> String {
        var h = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
        if let pct = h.firstIndex(of: "%") {
            h = String(h[..<pct])
        }
        if h.hasPrefix("::ffff:") {
            h = String(h.dropFirst("::ffff:".count))
        }
        return h
    }

    private static func isNumericIP(_ host: String) -> Bool {
        var addr4 = in_addr()
        if inet_pton(AF_INET, host, &addr4) == 1 { return true }
        var addr6 = in6_addr()
        if inet_pton(AF_INET6, host, &addr6) == 1 { return true }
        return false
    }

    private func resolveAndCacheHostIfNeeded(_ rawHost: String?) {
        guard let rawHost = rawHost else { return }
        let host = Self.normalizeHost(rawHost)
        guard !host.isEmpty, !Self.isNumericIP(host) else { return }
        queue.async { [weak self] in
            guard let self = self else { return }
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC
            hints.ai_socktype = SOCK_STREAM
            var res: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else { return }
            defer { freeaddrinfo(first) }
            var resolved = Set<String>()
            var ptr: UnsafeMutablePointer<addrinfo>? = first
            while let info = ptr {
                if info.pointee.ai_family == AF_INET, let sa = info.pointee.ai_addr {
                    sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        var addr = sin.pointee.sin_addr
                        if inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil {
                            resolved.insert(Self.normalizeHost(String(cString: buf)))
                        }
                    }
                } else if info.pointee.ai_family == AF_INET6, let sa = info.pointee.ai_addr {
                    sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
                        var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                        var addr = sin6.pointee.sin6_addr
                        if inet_ntop(AF_INET6, &addr, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil {
                            resolved.insert(Self.normalizeHost(String(cString: buf)))
                        }
                    }
                }
                ptr = info.pointee.ai_next
            }
            if !resolved.isEmpty {
                self.lock.lock()
                self.resolvedHostIPs[host] = resolved
                self.lock.unlock()
            }
        }
    }

    public func matchesSelectedRendererIP(_ remoteIP: String) -> Bool {
        let cleanRemote = Self.normalizeHost(remoteIP)
        guard !cleanRemote.isEmpty else { return false }
        guard let selected = getActiveRenderer() else { return false }

        var candidateHosts: [String] = []
        if let locHost = selected.locationURL.host {
            let norm = Self.normalizeHost(locHost)
            if !norm.isEmpty {
                candidateHosts.append(norm)
            }
        }
        if let bluHost = selected.bluOSBaseURL?.host {
            let norm = Self.normalizeHost(bluHost)
            if !norm.isEmpty && !candidateHosts.contains(norm) {
                candidateHosts.append(norm)
            }
        }
        guard !candidateHosts.isEmpty else { return false }

        for host in candidateHosts {
            if cleanRemote == host {
                return true
            }
            let cached: Set<String>? = lock.withLock { resolvedHostIPs[host] }
            if let ips = cached, ips.contains(cleanRemote) {
                return true
            }
            if cached == nil && !Self.isNumericIP(host) {
                resolveAndCacheHostIfNeeded(host)
            }
        }
        return false
    }

    public func deselectRenderer() {
        lock.lock()
        UserDefaults.standard.removeObject(forKey: Self.activeRendererDefaultsKey)
        lock.unlock()
        stopBluOSStatusMonitoring()
    }

    public var selectedDevice: DiscoveredDLNARenderer? {
        return getActiveRenderer()
    }

    public func getActiveRenderer() -> DiscoveredDLNARenderer? {
        lock.lock()
        defer { lock.unlock() }
        guard let uid = UserDefaults.standard.string(forKey: Self.activeRendererDefaultsKey) else { return nil }
        let cleanId = uid.hasPrefix("dlna:") ? String(uid.dropFirst(5)) : uid
        return discoveredRenderers[cleanId] ?? discoveredRenderers.values.first(where: { $0.id == cleanId || "dlna:\($0.id)" == uid })
    }

    public var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.defaultsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.defaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.defaultsKey)
            if newValue {
                start()
            } else {
                deselectRenderer()
                stop()
            }
        }
    }

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFormatChangedNotification(_:)),
            name: .bitPerfectFormatDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stop()
    }

    // MARK: - Lifecycle

    public func startIfEnabled() {
        if isEnabled {
            start()
        }
    }

    public func start() {
        queue.async { [weak self] in
            self?.startInternal()
        }
    }

    public func stop() {
        lock.lock()
        discoveredRenderers.removeAll()
        lock.unlock()
        queue.async { [weak self] in
            self?.stopInternal(clearDevices: true)
        }
    }

    public func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
    }

    private func startInternal() {
        stopInternal(clearDevices: false)

        NSLog("[DLNADiscovery] 🔍 Starting DLNA & BluOS MediaRenderer discovery...")

        // 1. UPnP SSDP Discovery for standard DLNA MediaRenderers (WiiM, Sony, Denon, etc.)
        setupUDPSocket()
        sendMSearch()

        // 2. Bonjour Discovery for BluOS streamers (Bluesound NODE NANO, NODE, POWERNODE, NAD, etc.)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let browser = NetServiceBrowser()
            let delegate = BluOSNetServiceDelegate(manager: self)
            browser.delegate = delegate
            browser.schedule(in: .main, forMode: .common)
            browser.searchForServices(ofType: "_musc._tcp.", inDomain: "local.")
            self.netServiceBrowser = browser
            self.netServiceDelegate = delegate
            NSLog("[DLNADiscovery] 🔍 Started Bonjour discovery for BluOS streamers (_musc._tcp)")
        }

        // 3. Known / cached BluOS hosts probing (supports cross-VLAN setups)
        probeKnownBluOSHosts()

        if !PlaybackRouter.shared.isTestingEnvironment {
            // Periodic M-SEARCH and BluOS host check every 30 seconds
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 30.0, repeating: 30.0)
            timer.setEventHandler { [weak self] in
                self?.sendMSearch()
                self?.probeKnownBluOSHosts()
            }
            timer.resume()
            self.scanTimer = timer

            // Cleanup stale devices (> 300s old) every 60s
            let cTimer = DispatchSource.makeTimerSource(queue: queue)
            cTimer.schedule(deadline: .now() + 60.0, repeating: 60.0)
            cTimer.setEventHandler { [weak self] in
                self?.cleanupStaleDevices()
            }
            cTimer.resume()
            self.cleanupTimer = cTimer
        }
    }

    private func stopInternal(clearDevices: Bool = true) {
        scanTimer?.cancel()
        scanTimer = nil

        cleanupTimer?.cancel()
        cleanupTimer = nil

        if let source = readSource {
            udpSocketFD = -1
            readSource = nil
            source.cancel()
        } else if udpSocketFD >= 0 {
            close(udpSocketFD)
            udpSocketFD = -1
        }

        DispatchQueue.main.async { [weak self] in
            self?.netServiceBrowser?.stop()
            self?.netServiceBrowser = nil
            self?.netServiceDelegate = nil
        }

        if clearDevices && !isEnabled {
            lock.lock()
            discoveredRenderers.removeAll()
            lock.unlock()
        }

        stopBluOSStatusMonitoring()

        NSLog("[DLNADiscovery] ⏹ DLNA discovery stopped and cleared.")
    }

    // MARK: - UDP Socket & M-SEARCH

    private func setupUDPSocket() {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            NSLog("[DLNADiscovery] ❌ Failed to create UDP socket: %d", errno)
            return
        }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // Bind to ephemeral port
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

        // Enable multicast loopback so MockDLNARenderer on localhost can be received
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
        let hosts = UserDefaults.standard.stringArray(forKey: "BluOSKnownHosts") ?? []
        for host in hosts {
            probeBluOS(host: host)
        }
    }

    public func probeBluOS(host: String, port: Int = 11000) {
        guard let syncURL = URL(string: "http://\(host):\(port)/SyncStatus") else { return }
        var request = URLRequest(url: syncURL)
        request.timeoutInterval = 3.0
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self,
                  error == nil,
                  (response as? HTTPURLResponse)?.statusCode == 200,
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
            guard let baseURL = URL(string: "http://\(host):\(port)") else { return }

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

            // Save host in known hosts
            var hosts = UserDefaults.standard.stringArray(forKey: "BluOSKnownHosts") ?? []
            if !hosts.contains(host) {
                hosts.append(host)
                UserDefaults.standard.set(hosts, forKey: "BluOSKnownHosts")
            }

            self.registerDevice(renderer)
        }.resume()
    }

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

    /// Validates that an SSDP `LOCATION` URL is an HTTP(S) private/LAN literal IP address (preventing SSRF
    /// to loopback, cloud metadata `169.254.169.254`, DNS rebinding, or WAN endpoints) and matches the UDP sender IP when known.
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

            // Reject loopback (127.0.0.0/8), unspecified (0.0.0.0/8), multicast/broadcast (>=224.0.0.0)
            if b0 == 127 || b0 == 0 || b0 >= 224 || b3 == 255 {
                return false
            }
            // Reject cloud metadata endpoint 169.254.169.254
            if b0 == 169 && b1 == 254 && b2 == 169 && b3 == 254 {
                return false
            }
            // Allow RFC1918 private LAN (10/8, 172.16/12, 192.168/16) and AutoIP link-local DLNA (169.254/16)
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
            // Reject unspecified (::), loopback (::1), multicast (ff00::/8)
            let isAllZero = bytes.allSatisfy { $0 == 0 }
            let isLoopback = bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes[15] == 1
            if isAllZero || isLoopback || bytes[0] == 0xFF {
                return false
            }
            // Allow ULA (fc00::/7) and link-local (fe80::/10)
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

        // Quick self-check against USN before HTTP GET
        if isSelfDevice(udn: usn, location: locationURL, friendlyName: "") {
            return
        }

        // Enforce strict LAN SSRF & sender-origin check before making any outbound HTTP request
        guard Self.isAllowedLANRendererURL(locationURL, expectedSenderIP: senderIP) else {
            NSLog("[DLNADiscovery] 🛡️ Blocked disallowed or spoofed SSDP LOCATION URL: %@ (sender: %@)", locationURL.absoluteString, senderIP ?? "unknown")
            return
        }

        // Fetch description XML asynchronously
        fetchDeviceDescription(from: locationURL)
    }

    // MARK: - Device XML Description Fetch & Parse

    public func fetchDeviceDescription(from url: URL) {
        guard Self.isAllowedLANRendererURL(url) else {
            NSLog("[DLNADiscovery] 🛡️ Blocked fetchDeviceDescription for disallowed URL: %@", url.absoluteString)
            return
        }
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, let data = data, let xml = String(data: data, encoding: .utf8) else {
                return
            }
            self.parseAndRegisterDevice(xml: xml, locationURL: url)
        }
        task.resume()
    }

    public func parseAndRegisterDevice(xml: String, locationURL: URL) {
        // Ensure deviceType is MediaRenderer
        guard xml.contains("urn:schemas-upnp-org:device:MediaRenderer:1") || xml.contains("MediaRenderer") else {
            return
        }

        let friendlyName = extractXMLTagValue(tag: "friendlyName", from: xml) ?? "Unknown DLNA Renderer"
        let manufacturer = extractXMLTagValue(tag: "manufacturer", from: xml) ?? "Unknown"
        let modelName = extractXMLTagValue(tag: "modelName", from: xml) ?? "MediaRenderer"
        let udn = extractXMLTagValue(tag: "UDN", from: xml) ?? locationURL.absoluteString

        // STRICT ANTI SELF-DISCOVERY FILTER
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
        // Double check anti-self-discovery filter
        if isSelfDevice(udn: renderer.id, location: renderer.locationURL, friendlyName: renderer.friendlyName, manufacturer: renderer.manufacturer, modelName: renderer.modelName) {
            return
        }

        lock.lock()
        let isNew = discoveredRenderers[renderer.id] == nil
        discoveredRenderers[renderer.id] = renderer
        let currentList = Array(discoveredRenderers.values)
        lock.unlock()

        resolveAndCacheHostIfNeeded(renderer.locationURL.host)
        resolveAndCacheHostIfNeeded(renderer.bluOSBaseURL?.host)

        if isNew {
            NSLog("[DLNADiscovery] 🎵 Discovered DLNA MediaRenderer: '%@' (%@ - %@) at %@",
                  renderer.friendlyName, renderer.manufacturer, renderer.modelName, renderer.locationURL.absoluteString)
            onDevicesChanged?(currentList)
            WebSocketServer.shared.broadcastAudioDevices()

            if renderer.isBluOS, (activeRendererUID == renderer.id || activeRendererUID == "dlna:\(renderer.id)"), bluOSPollingTask == nil {
                startBluOSStatusMonitoring(renderer: renderer)
            }
        }
    }

    // MARK: - Anti-Self-Discovery Filter

    public func isSelfDevice(udn: String, location: URL?, friendlyName: String, manufacturer: String = "", modelName: String = "") -> Bool {
        let selfUdn = SSDPService.shared.deviceUDN.lowercased()
        let selfUuid = SSDPService.shared.deviceUUID.lowercased()
        let lowerUdn = udn.lowercased()

        // 1. Check UDN and UUID
        if !selfUdn.isEmpty && (lowerUdn == selfUdn || lowerUdn.contains(selfUdn) || lowerUdn.contains(selfUuid)) {
            return true
        }

        // 2. Check location URL port 8090 (AMR's UPnP server port) on local host/LAN IP
        if let loc = location, let host = loc.host?.lowercased() {
            let port = loc.port ?? 80
            if port == SSDPService.shared.httpPort || port == 8090 {
                let localIPs = Set(WebSocketServer.shared.getLANIPAddresses().map { $0.lowercased() })
                if host == "127.0.0.1" || host == "localhost" || host == "::1" || localIPs.contains(host) {
                    return true
                }
            }
        }

        // 3. Check AMR manufacturer & modelName
        let lowerMan = manufacturer.lowercased()
        let lowerModel = modelName.lowercased()
        if lowerMan.contains("apple music remote") || lowerModel == "amr-mediarenderer" {
            return true
        }

        // 4. Check friendlyName
        let selfName = SSDPService.shared.friendlyName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedFriendly = friendlyName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !selfName.isEmpty && (trimmedFriendly == selfName || trimmedFriendly == "amr" || trimmedFriendly == "apple music remote (mac)") {
            return true
        }

        return false
    }

    // MARK: - Device Registry Queries

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

    private func cleanupStaleDevices() {
        let cutoff = Date().addingTimeInterval(-300) // 5 minutes
        lock.lock()
        let beforeCount = discoveredRenderers.count
        discoveredRenderers = discoveredRenderers.filter { $0.value.lastSeen >= cutoff }
        let afterCount = discoveredRenderers.count
        let changed = beforeCount != afterCount
        let currentList = Array(discoveredRenderers.values)
        lock.unlock()

        if changed {
            NSLog("[DLNADiscovery] 🧹 Cleaned up stale DLNA devices (Remaining: %d)", afterCount)
            onDevicesChanged?(currentList)
            WebSocketServer.shared.broadcastAudioDevices()
        }
    }

    // MARK: - XML & Header Helpers

    public func extractHeader(_ name: String, from text: String) -> String? {
        let lines = text.components(separatedBy: "\r\n")
        let prefix = "\(name):".lowercased()
        for line in lines {
            if line.lowercased().hasPrefix(prefix) {
                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
                if parts.count == 2 {
                    return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return nil
    }

    public func extractXMLTagValue(tag: String, from text: String) -> String? {
        let pattern = "<\(tag)[^>]*>([^<]*)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) else { return nil }
        return nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func extractXMLAttribute(attr: String, from text: String) -> String? {
        let pattern = "\(attr)=\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) else { return nil }
        return nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func extractServiceControlURL(serviceType: String, from xml: String, baseURL: URL) -> URL? {
        // Matches <service> ... <serviceType>...serviceType... </serviceType> ... <controlURL>...</controlURL> ... </service>
        let pattern = "<service>[\\s\\S]*?<serviceType>[^<]*\(serviceType)[^<]*</serviceType>[\\s\\S]*?<controlURL>([^<]+)</controlURL>[\\s\\S]*?</service>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsText = xml as NSString
        guard let match = regex.firstMatch(in: xml, options: [], range: NSRange(location: 0, length: nsText.length)) else { return nil }
        let relOrAbs = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)

        let resolved: URL?
        if relOrAbs.hasPrefix("http://") || relOrAbs.hasPrefix("https://") {
            resolved = URL(string: relOrAbs)
        } else {
            resolved = URL(string: relOrAbs, relativeTo: baseURL)?.absoluteURL
        }
        guard let candidate = resolved,
              let candScheme = candidate.scheme?.lowercased(),
              let baseScheme = baseURL.scheme?.lowercased(),
              (candScheme == "http" || candScheme == "https"),
              candScheme == baseScheme,
              candidate.user == nil,
              candidate.password == nil else {
            return nil
        }

        let candHost = Self.normalizeLiteralIP(candidate.host ?? "") ?? candidate.host?.lowercased()
        let baseHost = Self.normalizeLiteralIP(baseURL.host ?? "") ?? baseURL.host?.lowercased()
        guard let ch = candHost, let bh = baseHost, ch == bh else {
            NSLog("[DLNADiscovery] 🛡️ Blocked cross-host controlURL '%@' for baseURL '%@'", candidate.absoluteString, baseURL.absoluteString)
            return nil
        }

        let defaultPort = (baseScheme == "https") ? 443 : 80
        let candPort = candidate.port ?? defaultPort
        let basePort = baseURL.port ?? defaultPort
        guard candPort == basePort else {
            NSLog("[DLNADiscovery] 🛡️ Blocked cross-port controlURL '%@' for baseURL '%@'", candidate.absoluteString, baseURL.absoluteString)
            return nil
        }

        return candidate
    }

    // MARK: - AVTransport SOAP Remote Control

    public func sendAVTransportAction(action: String, bodyContent: String, completion: ((Bool, String) -> Void)? = nil) {
        guard let renderer = getActiveRenderer(), let controlURL = renderer.avTransportControlURL else {
            completion?(false, "No active DLNA renderer or controlURL")
            return
        }

        var request = URLRequest(url: controlURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 4.0
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"urn:schemas-upnp-org:service:AVTransport:1#\(action)\"", forHTTPHeaderField: "SOAPACTION")

        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:\(action) xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              \(bodyContent)
            </u:\(action)>
          </s:Body>
        </s:Envelope>
        """
        request.httpBody = Data(envelope.utf8)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                NSLog("[DLNADiscovery] ❌ SOAP %@ failed on %@: %@", action, renderer.friendlyName, error.localizedDescription)
                completion?(false, error.localizedDescription)
                return
            }
            let respStr = data != nil ? (String(data: data!, encoding: .utf8) ?? "") : ""
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
            let hasSoapFault = respStr.contains(":Fault>") || respStr.contains("<Fault>")
            guard (200..<300).contains(statusCode) && !hasSoapFault else {
                NSLog("[DLNADiscovery] ❌ SOAP %@ rejected on %@ (HTTP %d): %@", action, renderer.friendlyName, statusCode, respStr)
                completion?(false, respStr.isEmpty ? "HTTP \(statusCode)" : respStr)
                return
            }
            NSLog("[DLNADiscovery] ✅ SOAP %@ succeeded on %@", action, renderer.friendlyName)
            completion?(true, respStr)
        }.resume()
    }

    public func play(completion: ((Bool, String) -> Void)? = nil) {
        markLocalAction()
        guard let renderer = getActiveRenderer() else {
            completion?(false, "No active renderer")
            return
        }
        if !PlaybackRouter.shared.isTestingEnvironment {
            AudioProcessTapService.shared.startCapture()
        }
        if renderer.isBluOS {
            let (streamURL, imageURL, fullTitle, metadata) = resolveStreamAndImageURLs()
            setAVTransportURI(uri: streamURL, metadata: metadata, imageURL: imageURL, title: fullTitle, completion: completion)
        } else {
            lock.lock()
            let hasSentStream = lastSentStreamDate != Date.distantPast
            lock.unlock()
            if !hasSentStream {
                let (streamURL, imageURL, fullTitle, metadata) = resolveStreamAndImageURLs()
                setAVTransportURI(uri: streamURL, metadata: metadata, imageURL: imageURL, title: fullTitle) { [weak self] success, msg in
                    if success {
                        self?.sendAVTransportAction(action: "Play", bodyContent: "<Speed>1</Speed>", completion: completion)
                    } else {
                        completion?(false, msg)
                    }
                }
            } else {
                sendAVTransportAction(action: "Play", bodyContent: "<Speed>1</Speed>", completion: completion)
            }
        }
    }

    public func pause(completion: ((Bool, String) -> Void)? = nil) {
        markLocalAction()
        guard let renderer = getActiveRenderer() else {
            completion?(false, "No active renderer")
            return
        }
        if renderer.isBluOS, let base = renderer.bluOSBaseURL {
            sendBluOSCommand(endpoint: "Pause", base: base, completion: completion)
        } else {
            sendAVTransportAction(action: "Pause", bodyContent: "", completion: completion)
        }
    }

    public func stop(completion: ((Bool, String) -> Void)? = nil) {
        markLocalAction()
        guard let renderer = getActiveRenderer() else {
            completion?(false, "No active renderer")
            return
        }
        if renderer.isBluOS, let base = renderer.bluOSBaseURL {
            sendBluOSCommand(endpoint: "Pause", base: base, completion: completion)
        } else {
            sendAVTransportAction(action: "Stop", bodyContent: "", completion: completion)
        }
    }

    public func stopPlayback(completion: ((Bool, String) -> Void)? = nil) {
        stop(completion: completion)
    }

    public func pausePlayback(completion: ((Bool, String) -> Void)? = nil) {
        pause(completion: completion)
    }

    public func startPlayback(completion: ((Bool, String) -> Void)? = nil) {
        play(completion: completion)
    }

    public func setMute(_ mute: Bool, completion: ((Bool, String) -> Void)? = nil) {
        markLocalAction()
        guard let renderer = getActiveRenderer() else {
            completion?(false, "No active renderer")
            return
        }
        if renderer.isBluOS, let base = renderer.bluOSBaseURL {
            sendBluOSCommand(endpoint: "Volume?mute=\(mute ? 1 : 0)", base: base, completion: completion)
        } else if let controlURL = renderer.renderingControlURL {
            var request = URLRequest(url: controlURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 4.0
            request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
            request.setValue("\"urn:schemas-upnp-org:service:RenderingControl:1#SetMute\"", forHTTPHeaderField: "SOAPACTION")
            let desiredMute = mute ? "1" : "0"
            let envelope = """
            <?xml version="1.0" encoding="utf-8"?>
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
              <s:Body>
                <u:SetMute xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
                  <InstanceID>0</InstanceID>
                  <Channel>Master</Channel>
                  <DesiredMute>\(desiredMute)</DesiredMute>
                </u:SetMute>
              </s:Body>
            </s:Envelope>
            """
            request.httpBody = Data(envelope.utf8)
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion?(false, error.localizedDescription)
                    return
                }
                let respStr = data != nil ? (String(data: data!, encoding: .utf8) ?? "") : ""
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
                let hasSoapFault = respStr.contains(":Fault>") || respStr.contains("<Fault>")
                guard (200..<300).contains(statusCode) && !hasSoapFault else {
                    completion?(false, respStr.isEmpty ? "HTTP \(statusCode)" : respStr)
                    return
                }
                completion?(true, respStr)
            }.resume()
        } else {
            completion?(false, "No RenderingControl URL")
        }
    }

    public func setAVTransportURI(
        uri: String,
        metadata: String = "",
        imageURL: String? = nil,
        title: String? = nil,
        completion: ((Bool, String) -> Void)? = nil
    ) {
        markLocalAction()
        guard let renderer = getActiveRenderer() else {
            completion?(false, "No active renderer")
            return
        }
        if let uriComps = URLComponents(string: uri), let qItems = uriComps.queryItems {
            let parsedRate = qItems.first(where: { $0.name == "rate" })?.value.flatMap { Int($0) }
            let parsedBits = qItems.first(where: { $0.name == "bits" || $0.name == "depth" })?.value.flatMap { Int($0) }
            lock.lock()
            if let r = parsedRate { lastSentStreamRate = r }
            if let b = parsedBits { lastSentStreamDepth = b }
            if let t = title, !t.isEmpty { lastSentStreamTitle = t }
            lastSentStreamDate = Date()
            lock.unlock()
        }
        if renderer.isBluOS, let base = renderer.bluOSBaseURL {
            var comps = URLComponents(string: "\(base.absoluteString)/Play")
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "url", value: uri)
            ]
            if let t = title, !t.isEmpty {
                queryItems.append(URLQueryItem(name: "title1", value: t))
            }
            if let img = imageURL, !img.isEmpty {
                queryItems.append(URLQueryItem(name: "image", value: img))
            }
            comps?.queryItems = queryItems
            guard let url = comps?.url else {
                completion?(false, "Invalid BluOS URL")
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 4.0
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    NSLog("[DLNADiscovery] ❌ BluOS Play failed: %@", error.localizedDescription)
                    completion?(false, error.localizedDescription)
                    return
                }
                let respStr = data != nil ? (String(data: data!, encoding: .utf8) ?? "") : ""
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200...299).contains(statusCode) else {
                    NSLog("[DLNADiscovery] ❌ BluOS Play rejected (HTTP %d): %@", statusCode, respStr)
                    completion?(false, respStr.isEmpty ? "HTTP \(statusCode)" : respStr)
                    return
                }
                NSLog("[DLNADiscovery] ✅ BluOS Play succeeded: %@", url.absoluteString)
                completion?(true, respStr)
            }.resume()
        } else {
            let escapedURI = Self.escapeXMLText(uri)
            let escapedMeta = Self.escapeXMLText(metadata)
            let body = "<CurrentURI>\(escapedURI)</CurrentURI><CurrentURIMetaData>\(escapedMeta)</CurrentURIMetaData>"
            sendAVTransportAction(action: "SetAVTransportURI", bodyContent: body, completion: completion)
        }
    }

    private static func escapeXMLText(_ raw: String) -> String {
        return raw
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    public func sendBluOSCommand(endpoint: String, base: URL, completion: ((Bool, String) -> Void)? = nil) {
        guard let url = URL(string: "\(base.absoluteString)/\(endpoint)") else {
            completion?(false, "Invalid BluOS URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4.0
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                NSLog("[DLNADiscovery] ❌ BluOS %@ failed: %@", endpoint, error.localizedDescription)
                completion?(false, error.localizedDescription)
                return
            }
            let respStr = data != nil ? (String(data: data!, encoding: .utf8) ?? "") : ""
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(statusCode) else {
                NSLog("[DLNADiscovery] ❌ BluOS %@ rejected (HTTP %d): %@", endpoint, statusCode, respStr)
                completion?(false, respStr.isEmpty ? "HTTP \(statusCode)" : respStr)
                return
            }
            NSLog("[DLNADiscovery] ✅ BluOS %@ succeeded", endpoint)
            completion?(true, respStr)
        }.resume()
    }

    // MARK: - BluOS Status Monitoring & Two-Way Sync

    public func startBluOSStatusMonitoring(renderer: DiscoveredDLNARenderer) {
        stopBluOSStatusMonitoring()
        lock.withLock {
            lastKnownBluOSState = ""
        }
        guard renderer.isBluOS, let baseURL = renderer.bluOSBaseURL else { return }

        bluOSPollingTask = Task { [weak self] in
            var lastEtag: String? = nil
            var isFirst = true
            while !Task.isCancelled {
                guard let self = self, self.hasActiveRenderer else { break }
                var urlString = "\(baseURL.absoluteString)/Status"
                if let etag = lastEtag, !isFirst {
                    urlString += "?timeout=15&etag=\(etag)"
                }
                isFirst = false

                guard let url = URL(string: urlString) else { break }
                var req = URLRequest(url: url)
                req.timeoutInterval = 20.0

                do {
                    let (data, _) = try await URLSession.shared.data(for: req)
                    if Task.isCancelled { break }
                    if let xml = String(data: data, encoding: .utf8) {
                        if let etag = self.extractXMLAttribute(attr: "etag", from: xml) {
                            lastEtag = etag
                        }
                        if let state = self.extractXMLTagValue(tag: "state", from: xml) {
                            self.handleBluOSStateUpdate(state: state)
                        }
                    }
                } catch {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
    }

    public func stopBluOSStatusMonitoring() {
        bluOSPollingTask?.cancel()
        bluOSPollingTask = nil
        lock.withLock {
            lastKnownBluOSState = ""
        }
    }

    private func handleBluOSStateUpdate(state: String) {
        let prevState: String = lock.withLock {
            let prev = lastKnownBluOSState
            lastKnownBluOSState = state
            return prev
        }

        let elapsed = timeSinceLastLocalAction()
        if elapsed < 4.0 {
            NSLog("[DLNADiscovery] ⏳ Ignoring BluOS state '%@' (recent local action %.1fs ago)", state, elapsed)
            return
        }

        let musicStatus = MusicBridge.shared.getPlayerStatus()
        if state == "pause" || state == "stop" {
            if musicStatus.isPlaying {
                NSLog("[DLNADiscovery] ⏸️ BluOS reported %@ state. Pausing Apple Music.", state)
                markLocalAction()
                _ = MusicBridge.shared.pause()
                UPnPMediaRendererServer.shared.notifySubscribers(force: true)
                WebSocketServer.shared.broadcastStatus()
            }
        } else if state == "stream" || state == "play" {
            // Resume Apple Music if BluOS transitioned from paused/stopped/connecting -> 'stream'/'play'
            // (never auto-start playback on initial poll when prevState is empty).
            if !musicStatus.isPlaying && !prevState.isEmpty && prevState != "stream" && prevState != "play" {
                NSLog("[DLNADiscovery] ▶️ BluOS transitioned from '%@' to '%@'. Resuming Apple Music.", prevState, state)
                markLocalAction()
                _ = MusicBridge.shared.play()
                UPnPMediaRendererServer.shared.notifySubscribers(force: true)
                WebSocketServer.shared.broadcastStatus()
            }
        }
    }

    // MARK: - Sample Rate Change & Stream Recreation

    @objc private func handleFormatChangedNotification(_ notification: Notification) {
        guard BitPerfectLogMonitor.shared.isEnabled else { return }
        guard let userInfo = notification.userInfo,
              let rate = userInfo["sampleRate"] as? Double else { return }
        let bitDepth = (userInfo["bitDepth"] as? Int) ?? (rate >= 48000.0 ? 24 : 16)
        handleTrackFormatChanged(sampleRate: Int(rate), bitDepth: bitDepth)
    }

    public func resolveStreamAndImageURLs(sampleRate: Int? = nil, bitDepth: Int? = nil, isBluOS: Bool? = nil) -> (streamURL: String, imageURL: String, title: String, metadata: String) {
        let lanIP = WebSocketServer.shared.getLANIPAddresses().first ?? "127.0.0.1"
        let port = WebSocketServer.shared.port
        let status = MusicBridge.shared.getPlayerStatus()
        let isLossy = status.audioQuality.contains("AAC") || status.audioQuality.contains("MP3") || (!BitPerfectLogMonitor.shared.currentIsLossless && sampleRate == nil)
        let rate = sampleRate ?? (isLossy ? 44100 : (status.track?.sampleRate ?? BitPerfectLogMonitor.shared.currentDetectedSampleRate.map { Int($0) } ?? AudioProcessTapService.shared.sampleRate))
        let depth: Int
        if let explicitDepth = bitDepth {
            depth = explicitDepth
        } else if sampleRate != nil {
            depth = rate >= 48000 ? 24 : (isLossy ? 16 : (status.track?.bitDepth ?? BitPerfectLogMonitor.shared.currentDetectedBitDepth ?? 16))
        } else if isLossy {
            depth = 16
        } else {
            depth = status.track?.bitDepth ?? BitPerfectLogMonitor.shared.currentDetectedBitDepth ?? (rate >= 48000 ? 24 : 16)
        }

        AudioProcessTapService.shared.setFormat(sampleRate: rate, bitDepth: depth)

        let timestamp = Int(Date().timeIntervalSince1970)
        let streamURL = "http://\(lanIP):\(port)/stream/live.wav?rate=\(rate)&bits=\(depth)&t=\(timestamp)"

        let trackName = status.track?.name ?? "Apple Music"
        let trackArtist = status.track?.artist ?? ""
        let fullTitle = trackArtist.isEmpty ? trackName : "\(trackArtist) - \(trackName)"

        let activeRenderer = getActiveRenderer()
        let bluOS = isBluOS ?? activeRenderer?.isBluOS ?? false

        // Artwork resolution:
        // For BluOS streamers, ALWAYS use local AMR artwork endpoint http://<lanIP>:<port>/api/artwork.jpg?t=<timestamp>
        // because BluOS embedded devices reliably fetch local HTTP JPEGs without TLS, CDN or SNI certificate issues.
        // For standard UPnP, remote CDN URL is used if available, otherwise local endpoint.
        let imageURL: String
        if !bluOS, let art = status.track?.artworkUrl, art.hasPrefix("http://") || art.hasPrefix("https://") {
            imageURL = art
        } else {
            imageURL = "http://\(lanIP):\(port)/api/artwork.jpg?t=\(timestamp)"
        }

        let escapedTitle = Self.escapeXMLText(trackName)
        let escapedArtist = Self.escapeXMLText(trackArtist)
        let escapedArt = Self.escapeXMLText(imageURL)

        let metadata = """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"><item id="0" parentID="-1" restricted="1"><dc:title>\(escapedTitle)</dc:title><dc:creator>\(escapedArtist)</dc:creator><upnp:albumArtURI>\(escapedArt)</upnp:albumArtURI><upnp:class>object.item.audioItem.musicTrack</upnp:class></item></DIDL-Lite>
        """

        return (streamURL, imageURL, fullTitle, metadata)
    }

    public func handleTrackChanged(status: PlayerStatus) {
        guard hasActiveRenderer else { return }
        guard status.isPlaying else { return }
        guard let renderer = getActiveRenderer() else { return }
        guard let track = status.track else { return }

        let curId = track.id
        let curTitle = track.name
        let curArtist = track.artist
        let expectedFullTitle = curArtist.isEmpty ? curTitle : "\(curArtist) - \(curTitle)"

        let cachedFmt = BitPerfectLogMonitor.shared.getCachedFormat(artist: curArtist, title: curTitle)
        let isLossy = status.audioQuality.contains("AAC") || status.audioQuality.contains("MP3") || (!BitPerfectLogMonitor.shared.currentIsLossless && cachedFmt == nil)
        let detectedRate = BitPerfectLogMonitor.shared.currentDetectedSampleRate.map { Int($0) }
        let detectedDepth = BitPerfectLogMonitor.shared.currentDetectedBitDepth
        let targetRate = isLossy ? 44100 : (cachedFmt.map { Int($0.sampleRate) } ?? detectedRate ?? status.track?.sampleRate ?? AudioProcessTapService.shared.sampleRate)
        let targetDepth = isLossy ? 16 : (cachedFmt?.bitDepth ?? detectedDepth ?? status.track?.bitDepth ?? (targetRate >= 48000 ? 24 : 16))

        lock.lock()
        let isSameTrack = (curId == lastTrackId && curTitle == lastTrackTitle && curArtist == lastTrackArtist)
        let alreadySentSameStream = (lastSentStreamTitle == expectedFullTitle && lastSentStreamRate == targetRate && lastSentStreamDepth == targetDepth && Date().timeIntervalSince(lastSentStreamDate) < 3.5)
        if !isSameTrack {
            lastTrackId = curId
            lastTrackTitle = curTitle
            lastTrackArtist = curArtist
        }
        lock.unlock()

        guard !isSameTrack && !alreadySentSameStream else { return }

        NSLog("[DLNADiscovery] 🎵 Track changed while streaming to \(renderer.friendlyName): '\(curArtist) - \(curTitle)' (\(targetRate) Hz / \(targetDepth)-bit)")

        let (streamURL, imageURL, fullTitle, metadata) = resolveStreamAndImageURLs(sampleRate: targetRate, bitDepth: targetDepth)
        setAVTransportURI(uri: streamURL, metadata: metadata, imageURL: imageURL, title: fullTitle) { success, _ in
            if success, status.isPlaying, !renderer.isBluOS {
                self.play()
            }
        }
    }

    public func handleTrackFormatChanged(sampleRate: Int, bitDepth: Int = 16) {
        guard hasActiveRenderer else { return }
        guard let renderer = getActiveRenderer() else { return }
        let currentRate = AudioProcessTapService.shared.sampleRate
        let currentDepth = AudioProcessTapService.shared.bitDepth
        lock.lock()
        let sentRate = lastSentStreamRate
        let sentDepth = lastSentStreamDepth
        lock.unlock()

        guard sampleRate > 0, (bitDepth == 16 || bitDepth == 24),
              (sampleRate != currentRate || bitDepth != currentDepth || sampleRate != sentRate || bitDepth != sentDepth) else { return }

        AudioProcessTapService.shared.setFormat(sampleRate: sampleRate, bitDepth: bitDepth)
        PlaybackStateStore.shared.invalidateStatusCache()

        let status = MusicBridge.shared.getPlayerStatus()
        guard status.isPlaying else {
            WebSocketServer.shared.broadcastStatus(includeQueue: false)
            return
        }

        markLocalAction()
        NSLog("[DLNADiscovery] 🎛️ Track format changed to \(sampleRate) Hz / \(bitDepth)-bit while streaming to \(renderer.friendlyName). Recreating stream...")

        WebSocketServer.shared.closeLiveStreamConnections()

        let (streamURL, imageURL, fullTitle, metadata) = resolveStreamAndImageURLs(sampleRate: sampleRate, bitDepth: bitDepth)

        if let curTrack = status.track {
            lock.lock()
            lastTrackId = curTrack.id
            lastTrackTitle = curTrack.name
            lastTrackArtist = curTrack.artist
            lock.unlock()
        }

        setAVTransportURI(uri: streamURL, metadata: metadata, imageURL: imageURL, title: fullTitle) { success, _ in
            if success, !renderer.isBluOS {
                let latestStatus = MusicBridge.shared.getPlayerStatus()
                if latestStatus.isPlaying {
                    self.play()
                }
            }
            WebSocketServer.shared.broadcastStatus(includeQueue: false)
        }
    }
}
