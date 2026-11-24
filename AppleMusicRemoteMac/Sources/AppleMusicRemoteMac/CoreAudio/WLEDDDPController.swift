//
//  WLEDDDPController.swift
//  AppleMusicRemoteMac
//
//  Real-time 16-Zone WLED Ambilight & Audio-Reactive DSP Controller over UDP DDP (port 4048).
//  Includes strict RFC1918 / Loopback Unicast IPv4 SSRF & Broadcast Guard, RT-safe Float32 tap state,
//  and automatic server-side Vision Neural Saliency cover palette synchronization.
//

import Foundation
import Darwin
import os

public final class WLEDDDPController: @unchecked Sendable {
    public static let shared = WLEDDDPController()

    internal static let zoneCount = 16
    public static let supportedModes: [String] = [
        "off",
        "vu_center",
        "shockwave",
        "harmonic",
        "supernova",
        "prism_center",
        "duet_wings",
        "spectrum",
        "breathing",
        "ambilight",
        "static"
    ]

    internal static func normalizeModeName(_ raw: String) -> String {
        switch raw {
        case "aurora": return "spectrum"
        case "sunset": return "vu_center"
        case "prism":  return "prism_center"
        default:
            return supportedModes.contains(raw) ? raw : "vu_center"
        }
    }

    // MARK: - Strict Unicast Private LAN / Loopback IPv4 Guard (SSRF & Broadcast Prevention)

    /// Validates that `raw` is a canonical dotted-decimal IPv4 literal with NO port, path, query, fragment,
    /// userinfo, or whitespace, AND resolves via `inet_pton(AF_INET, ...)` to a unicast RFC1918 private LAN IP
    /// (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) or `127.0.0.1`, strictly rejecting broadcast
    /// (`255.255.255.255` or `.255`), network `.0` addresses, link-local metadata (`169.254.0.0/16`),
    /// multicast, and public internet addresses.
    public static func validatedUnicastPrivateOrLoopbackIPv4(_ raw: String) -> (ipString: String, addr: in_addr)? {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 15 else { return nil }
        guard clean.allSatisfy({ ($0 >= "0" && $0 <= "9") || $0 == "." }) else { return nil }

        let parts = clean.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        for part in parts {
            guard !part.isEmpty, part.count <= 3,
                  let val = UInt8(part),
                  String(val) == part else {
                return nil
            }
        }

        var sinAddr = in_addr()
        guard inet_pton(AF_INET, clean, &sinAddr) == 1 else { return nil }

        let hostOrder = UInt32(bigEndian: sinAddr.s_addr)
        let b0 = UInt8((hostOrder >> 24) & 0xFF)
        let b1 = UInt8((hostOrder >> 16) & 0xFF)
        let b2 = UInt8((hostOrder >> 8) & 0xFF)
        let b3 = UInt8(hostOrder & 0xFF)

        if hostOrder == 0xFFFF_FFFF || b3 == 255 {
            return nil
        }
        if b0 == 169 && b1 == 254 {
            return nil
        }
        if hostOrder == 0x7F00_0001 {
            return (clean, sinAddr)
        }
        if b0 == 10 {
            guard !(b1 == 0 && b2 == 0 && b3 == 0) else { return nil }
            return (clean, sinAddr)
        }
        if b0 == 172 && (16...31).contains(b1) {
            guard !(b2 == 0 && b3 == 0) else { return nil }
            return (clean, sinAddr)
        }
        if b0 == 192 && b1 == 168 {
            guard b3 != 0 else { return nil }
            return (clean, sinAddr)
        }

        return nil
    }

    public static func isValidWLEDUnicastIP(_ raw: String) -> Bool {
        validatedUnicastPrivateOrLoopbackIPv4(raw) != nil
    }

    internal let lock = NSLock()
    internal let audioFilterLock = NSLock()
    internal var rtSpinLock = os_unfair_lock_s()
    internal var rtFilterSpinLock = os_unfair_lock_s()

    internal let ddpQueue = DispatchQueue(label: "org.ksholokhov.amr.wled.ddp", qos: .userInteractive)
    internal var timer: DispatchSourceTimer?
    internal var timerIntervalMs: Int = 0
    internal var udpSocket: Int32 = -1
    internal var cachedSockAddr: sockaddr_in?
    internal var cachedIPString: String = ""
    internal var lastProbedIP: String = ""
    internal var isProbingDeviceInfo: Bool = false
    internal var lastSyncedPaletteTrackKey: String = ""
    internal var sequenceNumber: UInt8 = 1
    internal var offHeartbeatTickCount: Int = 0

    internal var isTapSubscribed: Bool = false

    // Persisted settings (synchronized via `lock`)
    internal var _isEnabled: Bool
    internal var _ipAddress: String
    internal var _mode: String
    internal var _ledCount: Int
    internal var _brightness: Double
    internal var _defaultTVMode: Bool
    private var _onSettingsChanged: (@Sendable () -> Void)?

    public var isEnabled: Bool {
        lock.withLock { _isEnabled }
    }
    public var ipAddress: String {
        lock.withLock { _ipAddress }
    }
    public var mode: String {
        lock.withLock { _mode }
    }
    public var ledCount: Int {
        lock.withLock { _ledCount }
    }
    public var brightness: Double {
        lock.withLock { _brightness }
    }
    public var defaultTVMode: Bool {
        lock.withLock { _defaultTVMode }
    }
    public var isActivelyStreaming: Bool {
        lock.withLock { _isEnabled && !_ipAddress.isEmpty && _mode != "off" }
    }
    public var isRealTimeAudioTapNeeded: Bool {
        os_unfair_lock_lock(&rtSpinLock)
        let active = rtAudioHookActive
        os_unfair_lock_unlock(&rtSpinLock)
        return active
    }
    public var onSettingsChanged: (@Sendable () -> Void)? {
        get { lock.withLock { _onSettingsChanged } }
        set { lock.withLock { _onSettingsChanged = newValue } }
    }

    // 16 spatial RGB zones + 4 distinct harmonic cover anchors in 0...255 space (before Gamma 2.0):
    // `targetZones` / `targetAnchors` guarded by `lock`; `currentZones`, `currentAnchors` & temporal buffers mutated on `ddpQueue`.
    internal var currentZones: [(r: Double, g: Double, b: Double)]
    internal var targetZones: [(r: Double, g: Double, b: Double)]
    internal var currentAnchors: [(r: Double, g: Double, b: Double)]
    internal var targetAnchors: [(r: Double, g: Double, b: Double)]
    internal var renderedLinearRGB: [(r: Double, g: Double, b: Double)] = []
    internal var lastQuantizedRGB: [UInt8] = []

    // Real-Time CoreAudio Float32 Filter Registers (guarded by `rtFilterSpinLock`, zero RT heap allocs)
    internal var rtFilterSampleRate: Int = 0
    internal var lp110Stage1: Double = 0.0
    internal var lp110Stage2: Double = 0.0
    internal var lp1800Stage1: Double = 0.0
    internal var lp1800Stage2: Double = 0.0

    // Real-Time Envelope, Adaptive Baseline & Beat Onset State (guarded by `rtSpinLock`)
    internal var rtAudioHookActive: Bool = false
    internal var rtFastBass: Double = 0.0
    internal var rtSlowBass: Double = 0.0
    internal var rtFastMid: Double = 0.0
    internal var rtSlowMid: Double = 0.0
    internal var rtFastHigh: Double = 0.0
    internal var rtAgcPeakBass: Double = 0.06
    internal var rtAgcPeakMid: Double = 0.06
    internal var rtAgcPeakHigh: Double = 0.03
    internal var rtPrevNormBass: Double = 0.0
    internal var rtPrevNormMid: Double = 0.0
    internal var rtBassLevel: Double = 0.0
    internal var rtMidLevel: Double = 0.0
    internal var rtHighLevel: Double = 0.0
    internal var rtBeatPulse: Double = 0.0
    internal var rtLastTapCallbackMono: Double = -1.0e9
    internal var rtLastNonSilentMono: Double = -1.0e9

    // 40 FPS Render State (accessed exclusively on `ddpQueue`)
    internal struct ShockwaveRing {
        var pos: Double
        var energy: Double
        var colorIdx: Int
    }
    internal var phase: Double = 0.0
    internal var beatPhase: Double = 0.0
    internal var playbackDimFactor: Double = 0.14
    internal var smoothedBass: Double = 0.0
    internal var smoothedMid: Double = 0.0
    internal var smoothedHigh: Double = 0.0
    internal var smoothedBeat: Double = 0.0
    internal var shockwaveRings: [ShockwaveRing] = []
    internal var prevBeatForRingTrigger: Double = 0.0
    internal var lastRingSpawnMono: Double = -1.0e9
    internal var nextRingColorIdx: Int = 0
    internal var playingHoldUntilMono: Double = -1.0e9
    internal var lastHalRunCheckMono: Double = -1.0e9
    internal var cachedHalOutputRunning: Bool = false
    internal var lastAutoProbeAttemptMono: Double = -1.0e9

    internal static let keyEnabled = "WLEDDDP_Enabled"
    internal static let keyIP = "WLEDDDP_IP"
    internal static let keyMode = "WLEDDDP_Mode"
    internal static let keyLedCount = "WLEDDDP_LedCount"
    internal static let keyBrightness = "WLEDDDP_Brightness"
    internal static let keyDefaultTVMode = "AMR_DefaultTVModeOnStart"

    // Warm cohesive Apple Music crimson-amber-plum default anchors & zones (until current cover resolves)
    internal static let defaultAnchors: [(r: Double, g: Double, b: Double)] = [
        (246, 36, 68),   // Core Hero: Crimson
        (255, 138, 24),  // Secondary Harmonic: Molten Amber
        (158, 28, 196),  // Deep Wing Contrast: Velvet Violet
        (255, 206, 96)   // Luminous Crest: Warm Gold Spark
    ]

    internal static let defaultZones: [(r: Double, g: Double, b: Double)] = [
        (158, 28, 196),  (182, 30, 162),  (208, 34, 122),  (232, 42, 86),
        (246, 56, 64),   (252, 92, 42),   (255, 128, 28),  (248, 44, 68),
        (248, 44, 68),   (255, 128, 28),  (252, 92, 42),   (246, 56, 64),
        (232, 42, 86),   (208, 34, 122),  (182, 30, 162),  (158, 28, 196)
    ]

    private init() {
        let defaults = AppStorageProvider.shared
        self._isEnabled = defaults.bool(forKey: Self.keyEnabled)
        let rawSavedIP = (defaults.string(forKey: Self.keyIP) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let valid = Self.validatedUnicastPrivateOrLoopbackIPv4(rawSavedIP) {
            self._ipAddress = valid.ipString
        } else {
            self._ipAddress = ""
        }
        let savedMode = defaults.string(forKey: Self.keyMode) ?? "vu_center"
        self._mode = Self.normalizeModeName(savedMode)
        let savedLeds = defaults.integer(forKey: Self.keyLedCount)
        self._ledCount = (savedLeds > 0) ? min(max(savedLeds, 1), 480) : 120
        let savedBri = defaults.object(forKey: Self.keyBrightness) as? Double ?? 0.92
        self._brightness = min(max(savedBri, 0.05), 1.0)
        self._defaultTVMode = defaults.bool(forKey: Self.keyDefaultTVMode)
        self.currentZones = Self.defaultZones
        self.targetZones = Self.defaultZones
        self.currentAnchors = Self.defaultAnchors
        self.targetAnchors = Self.defaultAnchors

        if !_ipAddress.isEmpty {
            if _isEnabled {
                probeWledDeviceInfoIfNeeded(ip: _ipAddress)
            }
            reconfigureEngine(sendOffSignalIfInactive: false)
        }
    }

    deinit {
        stopEngine()
    }

    // MARK: - Public API

    public func getSettingsDictionary() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return [
            "enabled": _isEnabled,
            "ip": _ipAddress,
            "mode": _mode,
            "led_count": _ledCount,
            "brightness": _brightness,
            "default_tv_mode": _defaultTVMode
        ]
    }

    public func updateSettings(
        enabled: Bool? = nil,
        ip: String? = nil,
        mode: String? = nil,
        ledCount: Int? = nil,
        brightness: Double? = nil,
        defaultTVMode: Bool? = nil
    ) -> [String: Any] {
        var shouldTurnOffStrip = false
        var shouldTurnOnStrip = false
        var ipToProbe: String? = nil
        var ipDidChange = false
        var previousValidIpSnapshot: String = ""
        var currentIpSnapshot: String = ""
        var notifyCallback: (@Sendable () -> Void)? = nil

        lock.lock()
        let wasActive = self._isEnabled && !self._ipAddress.isEmpty && self._mode != "off"
        previousValidIpSnapshot = self._ipAddress
        let prevLedCount = self._ledCount
        if let en = enabled {
            self._isEnabled = en
            AppStorageProvider.shared.set(en, forKey: Self.keyEnabled)
        }
        if let rawIp = ip {
            let trimmed = rawIp.trimmingCharacters(in: .whitespacesAndNewlines)
            let sanitizedIp: String
            if trimmed.isEmpty {
                sanitizedIp = ""
            } else if let valid = Self.validatedUnicastPrivateOrLoopbackIPv4(trimmed) {
                sanitizedIp = valid.ipString
            } else {
                NSLog("[WLEDDDPController] ⚠️ Rejected invalid or non-LAN WLED IP address: '%@'", trimmed)
                sanitizedIp = ""
            }
            if sanitizedIp != self._ipAddress {
                self._ipAddress = sanitizedIp
                self.lastProbedIP = ""
                ipDidChange = true
                AppStorageProvider.shared.set(sanitizedIp, forKey: Self.keyIP)
            }
        }
        if let m = mode {
            let normalized = Self.normalizeModeName(m)
            self._mode = normalized
            AppStorageProvider.shared.set(normalized, forKey: Self.keyMode)
        }
        let userExplicitlyChangedLedCount: Bool
        if let cnt = ledCount, cnt > 0 {
            let clamped = min(max(cnt, 1), 480)
            userExplicitlyChangedLedCount = (clamped != prevLedCount)
            self._ledCount = clamped
            AppStorageProvider.shared.set(clamped, forKey: Self.keyLedCount)
        } else {
            userExplicitlyChangedLedCount = false
        }
        if let bri = brightness {
            let clamped = min(max(bri, 0.05), 1.0)
            self._brightness = clamped
            AppStorageProvider.shared.set(clamped, forKey: Self.keyBrightness)
        }
        if let defTv = defaultTVMode {
            self._defaultTVMode = defTv
            AppStorageProvider.shared.set(defTv, forKey: Self.keyDefaultTVMode)
        }
        let isNowActive = self._isEnabled && !self._ipAddress.isEmpty && self._mode != "off"
        currentIpSnapshot = self._ipAddress
        let offTargetIp = !currentIpSnapshot.isEmpty ? currentIpSnapshot : previousValidIpSnapshot
        if wasActive && !isNowActive && !offTargetIp.isEmpty {
            shouldTurnOffStrip = true
            currentIpSnapshot = offTargetIp
        } else if !wasActive && isNowActive {
            shouldTurnOnStrip = true
        }
        if self._isEnabled && !self._ipAddress.isEmpty && !userExplicitlyChangedLedCount && (ipDidChange || self.lastProbedIP != self._ipAddress) {
            ipToProbe = self._ipAddress
        }
        notifyCallback = self._onSettingsChanged
        lock.unlock()

        if let probeIp = ipToProbe {
            probeWledDeviceInfoIfNeeded(ip: probeIp)
        }
        if shouldTurnOffStrip {
            sendBlackoutFrame(targetIP: currentIpSnapshot)
            sendWledHttpPowerState(ip: currentIpSnapshot, on: false)
        } else if shouldTurnOnStrip {
            sendWledHttpPowerState(ip: currentIpSnapshot, on: true)
            bootstrapCurrentTrackPaletteAsync()
        }
        reconfigureEngine(sendOffSignalIfInactive: shouldTurnOffStrip)
        notifyCallback?()
        return getSettingsDictionary()
    }

    /// Updates both the 4 distinct harmonic cover anchors and the 16 spatial zones from Vision Saliency / cover colors.
    public func updateCoverPalette(ambientRGB: [[Int]]?, spatialZones: [[Int]]) {
        func sanitizeRGB(_ list: [[Int]]) -> [(r: Double, g: Double, b: Double)] {
            var out: [(r: Double, g: Double, b: Double)] = []
            out.reserveCapacity(list.count)
            for c in list where c.count >= 3 {
                let r = Double(min(max(c[0], 0), 255))
                let g = Double(min(max(c[1], 0), 255))
                let b = Double(min(max(c[2], 0), 255))
                out.append(Self.saturateForLED(r: r, g: g, b: b))
            }
            return out
        }

        let satAmbient = sanitizeRGB(ambientRGB ?? [])
        let satZones = sanitizeRGB(spatialZones)
        let primarySource = !satAmbient.isEmpty ? satAmbient : satZones
        guard !primarySource.isEmpty else { return }

        let anchors = Self.buildDistinctCoverAnchors(from: primarySource + satZones)
        let expandedZones = Self.buildRich16Zones(from: !satZones.isEmpty ? satZones : primarySource, anchors: anchors)

        lock.lock()
        self.targetAnchors = anchors
        self.targetZones = expandedZones
        lock.unlock()
    }

    /// Updates the 16-zone spatial palette from Vision Neural Saliency zones or 4-stop cover palette.
    public func updatePalette(_ colors: [[Int]]) {
        updateCoverPalette(ambientRGB: nil, spatialZones: colors)
    }

    /// Automatically synchronizes the WLED 16-zone palette with the active track's cover artwork on the Mac server
    /// (works even when zero browser tabs are open!).
    public func syncCurrentTrackPaletteIfNeeded(track: TrackInfo?) {
        guard !PlaybackRouter.shared.isTestingEnvironment,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        guard let tr = track, !tr.name.isEmpty else { return }
        let artUrl = tr.artworkUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let numId = tr.numericId ?? 0
        guard !artUrl.isEmpty || numId > 0 else { return }

        let compositeKey = "\(tr.artist.lowercased())|\(tr.name.lowercased())|\(artUrl)|\(numId)"
        let shouldFetch: Bool = lock.withLock {
            guard _isEnabled && !_ipAddress.isEmpty && _mode != "off" else { return false }
            if compositeKey == lastSyncedPaletteTrackKey {
                return false
            }
            lastSyncedPaletteTrackKey = compositeKey
            return true
        }
        guard shouldFetch else { return }

        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            guard let palette = await ArtworkService.shared.resolveArtworkPalette(
                url: artUrl.isEmpty ? nil : artUrl,
                trackId: numId > 0 ? numId : nil
            ) else {
                self.lock.withLock {
                    if self.lastSyncedPaletteTrackKey == compositeKey {
                        self.lastSyncedPaletteTrackKey = ""
                    }
                }
                return
            }
            let stillCurrent = self.lock.withLock { self.lastSyncedPaletteTrackKey == compositeKey }
            guard stillCurrent else { return }
            let ambientRgb = palette["ambient_rgb"] as? [[Int]]
            let wledZones = (palette["wled_zones"] as? [[Int]]) ?? []
            if !wledZones.isEmpty || (ambientRgb?.isEmpty == false) {
                self.updateCoverPalette(ambientRGB: ambientRgb, spatialZones: wledZones)
            }
        }
    }

    internal func bootstrapCurrentTrackPaletteAsync() {
        guard !PlaybackRouter.shared.isTestingEnvironment,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        lock.withLock {
            lastSyncedPaletteTrackKey = ""
        }
        if let cachedTrack = PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.lastPlayerStatusCache?.status.track }),
           !cachedTrack.name.isEmpty {
            syncCurrentTrackPaletteIfNeeded(track: cachedTrack)
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let st = PlayerStatusEngine.shared.getPlayerStatus()
            self?.syncCurrentTrackPaletteIfNeeded(track: st.track)
        }
    }

    // MARK: - WLED HTTP Info Auto-Discovery & Power Control (/json/info & /json/state)

    internal func probeWledDeviceInfoIfNeeded(ip: String) {
        guard !PlaybackRouter.shared.isTestingEnvironment,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let valid = Self.validatedUnicastPrivateOrLoopbackIPv4(ip) else {
            return
        }
        let cleanIp = valid.ipString
        let canStartProbe: Bool = lock.withLock {
            if isProbingDeviceInfo || lastProbedIP == cleanIp {
                return false
            }
            isProbingDeviceInfo = true
            return true
        }
        guard canStartProbe, let url = URL(string: "http://\(cleanIp)/json/info") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2.0

        URLSession.shared.dataTask(with: req) { [weak self] data, resp, _ in
            guard let self = self else { return }
            defer {
                self.lock.withLock { self.isProbingDeviceInfo = false }
            }
            guard let data = data,
                  let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let leds = json["leds"] as? [String: Any],
                  let count = leds["count"] as? Int,
                  count > 0 else {
                return
            }
            let clamped = min(max(count, 1), 480)
            var changed = false
            var callback: (@Sendable () -> Void)? = nil
            self.lock.withLock {
                self.lastProbedIP = cleanIp
                if self._ledCount != clamped {
                    self._ledCount = clamped
                    AppStorageProvider.shared.set(clamped, forKey: Self.keyLedCount)
                    changed = true
                    callback = self._onSettingsChanged
                }
            }
            if changed {
                NSLog("[WLEDDDPController] 🔍 Auto-detected WLED strip length: %d LEDs at %@", clamped, cleanIp)
                callback?()
                WebSocketServer.shared.broadcastEvent(name: "wled_settings", data: self.getSettingsDictionary())
            }
        }.resume()
    }

    internal func sendWledHttpPowerState(ip: String, on: Bool) {
        guard !PlaybackRouter.shared.isTestingEnvironment,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let valid = Self.validatedUnicastPrivateOrLoopbackIPv4(ip),
              let url = URL(string: "http://\(valid.ipString)/json/state") else {
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 1.5
        // Disable WLED crossfade transition & built-in mic AudioReactive / segment fx so DDP frames render cleanly
        let body: [String: Any] = on
            ? [
                "on": true,
                "bri": 255,
                "transition": 0,
                "lor": 0,
                "AudioReactive": ["on": false],
                "seg": [["id": 0, "fx": 0]]
            ]
            : ["on": false, "transition": 0]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
    }
}
