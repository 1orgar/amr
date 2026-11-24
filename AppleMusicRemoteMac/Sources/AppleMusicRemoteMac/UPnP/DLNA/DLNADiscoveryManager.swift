//
//  DLNADiscoveryManager.swift
//  AppleMusicRemoteMac
//
//  Discovers DLNA / UPnP MediaRenderer devices and BluOS streamers.
//  Manages active renderer selection, streamSessionToken rotation, host IP caching,
//  and discovery lifecycle.
//

import Darwin
import Foundation
import Network

public final class DLNADiscoveryManager: @unchecked Sendable {
    public static let shared = DLNADiscoveryManager()

    public static let defaultsKey = "DiscoverDLNARenderers"
    public static let activeRendererDefaultsKey = "ActiveDLNARendererUID"
    internal static let rendererVolumesDefaultsKey = "amr.dlna.rendererVolumes.v1"
    internal static let streamSessionTokenDefaultsKey = "amr.dlna.streamSessionToken.v1"
    internal static let maxDiscoveredRenderers = 64

    internal let lock = NSLock()
    internal let queue = DispatchQueue(label: "org.ksholokhov.amr.dlna.discovery", qos: .utility)
    internal var scanTimer: DispatchSourceTimer?
    internal var cleanupTimer: DispatchSourceTimer?
    internal var udpSocketFD: Int32 = -1
    internal var readSource: DispatchSourceRead?
    internal var netServiceBrowser: NetServiceBrowser?
    internal var netServiceDelegate: BluOSNetServiceDelegate?

    internal var discoveredRenderers: [String: DiscoveredDLNARenderer] = [:]
    internal var resolvedHostIPs: [String: Set<String>] = [:]
    internal var _streamSessionToken: String = {
        if let saved = AppStorageProvider.shared.string(forKey: "amr.dlna.streamSessionToken.v1")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           saved.count >= 32 {
            return saved
        }
        let generated = ClientDeviceRecord.generateRandomHexSecret(byteCount: 16)
        AppStorageProvider.shared.set(generated, forKey: "amr.dlna.streamSessionToken.v1")
        return generated
    }()
    internal var _previousStreamSessionToken: String? = nil
    internal var broadcastDebounceWorkItem: DispatchWorkItem?

    private let handlersLock = NSLock()
    private var _onDevicesChanged: (([DiscoveredDLNARenderer]) -> Void)?
    private var devicesChangedObservers: [String: ([DiscoveredDLNARenderer]) -> Void] = [:]

    internal var bluOSPollingTask: Task<Void, Never>?
    internal var lastKnownBluOSState: String = ""
    internal var isExplicitlyPaused: Bool = false
    internal var lastLocalActionDate: Date = Date.distantPast
    internal var lastBluOSStreamRecoveryDate: Date = Date.distantPast
    internal var lastLocalVolumeCommandDate: Date = Date.distantPast
    internal var pendingVolumeWorkItem: DispatchWorkItem?
    internal var pendingVolumeCompletion: ((Bool, String) -> Void)?
    internal var rendererVolumesByUID: [String: Int] = (AppStorageProvider.shared.dictionary(forKey: "amr.dlna.rendererVolumes.v1") as? [String: Int]) ?? [:]
    internal var rendererMutedState: Bool = false
    internal var lastTrackId: String = ""
    internal var lastTrackTitle: String = ""
    internal var lastTrackArtist: String = ""
    internal var lastSentStreamRate: Int = 0
    internal var lastSentStreamDepth: Int = 0
    internal var lastSentStreamTitle: String = ""
    internal var lastSentStreamDate: Date = Date.distantPast
    internal var seekRefreshWorkItem: DispatchWorkItem?
    internal var activeStreamInstanceID: String = ""
    internal var activeStreamFirstConnectedAt: Date? = nil
    internal var activeStreamLastClientDisconnectedAt: Date? = nil
    internal var lastBluOSPrevTriggerDate: Date = Date.distantPast

    public var currentStreamSessionToken: String {
        lock.lock()
        defer { lock.unlock() }
        return _streamSessionToken
    }

    public var isRendererPausedOrStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isExplicitlyPaused || lastKnownBluOSState == "pause" || lastKnownBluOSState == "stop"
    }

    public func validateStreamSessionToken(_ candidate: String?) -> Bool {
        guard let raw = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.count >= 32 else {
            return false
        }
        let (expected, previous): (String, String?) = lock.withLock {
            (_streamSessionToken, _previousStreamSessionToken)
        }
        if ClientDeviceRecord.constantTimeEqual(raw, expected) {
            return true
        }
        if let prev = previous, prev.count >= 32, ClientDeviceRecord.constantTimeEqual(raw, prev) {
            return true
        }
        return false
    }

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

    public var currentVolume: Int {
        lock.lock()
        defer { lock.unlock() }
        guard let uid = AppStorageProvider.shared.string(forKey: Self.activeRendererDefaultsKey) else {
            return 50
        }
        let cleanId = uid.hasPrefix("dlna:") ? String(uid.dropFirst(5)) : uid
        if rendererMutedState {
            return 0
        }
        return max(0, min(100, rendererVolumesByUID[cleanId] ?? 35))
    }

    public var isRendererMuted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return rendererMutedState
    }

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
            return AppStorageProvider.shared.string(forKey: Self.activeRendererDefaultsKey)
        }
        set {
            lock.lock()
            if let val = newValue {
                AppStorageProvider.shared.set(val, forKey: Self.activeRendererDefaultsKey)
            } else {
                AppStorageProvider.shared.removeObject(forKey: Self.activeRendererDefaultsKey)
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
        let targetStoredUID = "dlna:\(renderer.id)"
        let previousUID = AppStorageProvider.shared.string(forKey: Self.activeRendererDefaultsKey)
        if previousUID != targetStoredUID {
            _previousStreamSessionToken = _streamSessionToken
            let rotated = ClientDeviceRecord.generateRandomHexSecret(byteCount: 16)
            _streamSessionToken = rotated
            if !PlaybackRouter.shared.isTestingEnvironment {
                AppStorageProvider.shared.set(rotated, forKey: Self.streamSessionTokenDefaultsKey)
            }
        }
        AppStorageProvider.shared.set(targetStoredUID, forKey: Self.activeRendererDefaultsKey)
        lock.unlock()

        resolveAndCacheHostIfNeeded(renderer.locationURL.host)
        resolveAndCacheHostIfNeeded(renderer.bluOSBaseURL?.host)

        if !PlaybackRouter.shared.isTestingEnvironment,
           let app = MusicAppProvider.shared.getMusicApp(),
           app.soundVolume != 100 {
            app.soundVolume = 100
        }
        RoomAcousticService.shared.refreshLocalPassthroughEQPipeline()

        if renderer.isBluOS {
            startBluOSStatusMonitoring(renderer: renderer)
        } else {
            fetchUPnPRendererVolume(renderer: renderer)
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

    internal func resolveAndCacheHostIfNeeded(_ rawHost: String?) {
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
        guard let selected = getActiveRenderer() else {
            if let activeUID = AppStorageProvider.shared.string(forKey: Self.activeRendererDefaultsKey),
               activeUID.lowercased().contains("bluos:"),
               let knownHosts = AppStorageProvider.shared.stringArray(forKey: "BluOSKnownHosts") {
                return knownHosts.map(Self.normalizeHost).contains(cleanRemote)
            }
            return false
        }

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
        let supersededCompletion = pendingVolumeCompletion
        pendingVolumeCompletion = nil
        pendingVolumeWorkItem?.cancel()
        pendingVolumeWorkItem = nil
        isExplicitlyPaused = false
        _previousStreamSessionToken = nil
        let rotated = ClientDeviceRecord.generateRandomHexSecret(byteCount: 16)
        _streamSessionToken = rotated
        if !PlaybackRouter.shared.isTestingEnvironment {
            AppStorageProvider.shared.set(rotated, forKey: Self.streamSessionTokenDefaultsKey)
        }
        AppStorageProvider.shared.removeObject(forKey: Self.activeRendererDefaultsKey)
        lock.unlock()
        supersededCompletion?(false, "Renderer deselected")
        stopBluOSStatusMonitoring()
        RoomAcousticService.shared.refreshLocalPassthroughEQPipeline()
    }

    public var selectedDevice: DiscoveredDLNARenderer? {
        return getActiveRenderer()
    }

    public func getActiveRenderer() -> DiscoveredDLNARenderer? {
        lock.lock()
        defer { lock.unlock() }
        guard let uid = AppStorageProvider.shared.string(forKey: Self.activeRendererDefaultsKey) else { return nil }
        let cleanId = uid.hasPrefix("dlna:") ? String(uid.dropFirst(5)) : uid
        return discoveredRenderers[cleanId] ?? discoveredRenderers.values.first(where: { $0.id == cleanId || "dlna:\($0.id)" == uid })
    }

    public var isEnabled: Bool {
        get {
            if AppStorageProvider.shared.object(forKey: Self.defaultsKey) == nil {
                return true
            }
            return AppStorageProvider.shared.bool(forKey: Self.defaultsKey)
        }
        set {
            AppStorageProvider.shared.set(newValue, forKey: Self.defaultsKey)
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
        broadcastDebounceWorkItem?.cancel()
        broadcastDebounceWorkItem = nil
        lock.unlock()
        queue.async { [weak self] in
            self?.stopInternal(clearDevices: true)
        }
    }

    public func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
    }

    internal func startInternal() {
        stopInternal(clearDevices: false)

        if let active = getActiveRenderer(), active.isBluOS {
            startBluOSStatusMonitoring(renderer: active)
        }

        NSLog("[DLNADiscovery] 🔍 Starting DLNA & BluOS MediaRenderer discovery...")
        setupUDPSocket()
        sendMSearch()

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

        probeKnownBluOSHosts()

        if !PlaybackRouter.shared.isTestingEnvironment {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 30.0, repeating: 30.0)
            timer.setEventHandler { [weak self] in
                self?.sendMSearch()
                self?.probeKnownBluOSHosts()
            }
            timer.resume()
            self.scanTimer = timer

            let cTimer = DispatchSource.makeTimerSource(queue: queue)
            cTimer.schedule(deadline: .now() + 60.0, repeating: 60.0)
            cTimer.setEventHandler { [weak self] in
                self?.cleanupStaleDevices()
            }
            cTimer.resume()
            self.cleanupTimer = cTimer
        }
    }

    internal func stopInternal(clearDevices: Bool = true) {
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
}
