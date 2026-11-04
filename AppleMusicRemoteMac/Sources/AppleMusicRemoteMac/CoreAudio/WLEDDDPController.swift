//
//  WLEDDDPController.swift
//  AppleMusicRemoteMac
//
//  Real-time 16-Zone WLED Ambilight & Audio-Reactive DSP Controller over UDP DDP (port 4048).
//  Features:
//  - Full-rate 3-Band CoreAudio DSP (Sub-Bass/Kick <115Hz, Mid/Vocal 115..2200Hz, Treble >2200Hz)
//    with Automatic Gain Control (AGC) & smooth onset pulse detection
//  - 5 distinct Music-Reactive lighting modes (Standing Sine Wave, 3-Band Equalizer,
//    Center VU-Pulse, Live Ambilight 16-Zone, Harmonic Resonance) + 1 Static Cover Palette mode
//  - Zero frantic chasing/running dots: all effects use smooth standing sine/bell envelopes
//  - Automatic minimal idle glow on Pause / Stop (no movement when paused)
//  - Off-State Heartbeat (UDP DDP blackout + HTTP /json/state {"on":false}) so controllers with
//    auto-power-on stay turned off whenever WLED is disabled in AMR
//

import Foundation
import Darwin

public final class WLEDDDPController: @unchecked Sendable {
    public static let shared = WLEDDDPController()

    private static let zoneCount = 16
    public static let supportedModes: [String] = [
        "off",
        "breathing",
        "spectrum",
        "vu_center",
        "ambilight",
        "harmonic",
        "static"
    ]

    private static func normalizeModeName(_ raw: String) -> String {
        switch raw {
        case "aurora": return "spectrum"
        case "sunset": return "vu_center"
        case "prism":  return "harmonic"
        default:
            return supportedModes.contains(raw) ? raw : "breathing"
        }
    }

    private let lock = NSLock()
    private let ddpQueue = DispatchQueue(label: "org.ksholokhov.amr.wled.ddp", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var timerIntervalMs: Int = 0
    private var udpSocket: Int32 = -1
    private var cachedSockAddr: sockaddr_in?
    private var cachedIPString: String = ""
    private var lastProbedIP: String = ""
    private var sequenceNumber: UInt8 = 1
    private var offHeartbeatTickCount: Int = 0

    private let tapSubscriberId = UUID()
    private var isTapSubscribed: Bool = false

    // Precomputed Gamma 2.4 lookup table (0...255 -> 0...255) for deep LED saturation
    private let gammaLUT: [UInt8] = (0...255).map { i in
        let norm = Double(i) / 255.0
        let corrected = pow(norm, 2.4) * 255.0
        return UInt8(min(max(Int(corrected.rounded()), 0), 255))
    }

    // Persisted settings
    public private(set) var isEnabled: Bool
    public private(set) var ipAddress: String
    public private(set) var mode: String
    public private(set) var ledCount: Int
    public private(set) var brightness: Double
    public private(set) var defaultTVMode: Bool
    public var onSettingsChanged: (@Sendable () -> Void)?

    // 16 spatial RGB zones in 0...255 linear space (before Gamma 2.4)
    private var currentZones: [(r: Double, g: Double, b: Double)]
    private var targetZones: [(r: Double, g: Double, b: Double)]

    // Full-Rate 2-Pole Cascaded IIR Filter State & AGC Envelopes
    private var lp115Stage1: Double = 0.0
    private var lp115Stage2: Double = 0.0
    private var lp2200Stage1: Double = 0.0
    private var lp2200Stage2: Double = 0.0

    private var agcPeakBass: Double = 0.04
    private var agcPeakMid: Double = 0.04
    private var agcPeakHigh: Double = 0.02

    private var bassEnvelope: Double = 0.0
    private var midEnvelope: Double = 0.0
    private var highEnvelope: Double = 0.0
    private var kickPulseEnvelope: Double = 0.0
    private var prevNormBass: Double = 0.0
    private var lastAudioChunkTime: Date = .distantPast

    // 50 FPS Render Smoothing State
    private var phase: Double = 0.0
    private var playbackDimFactor: Double = 0.08 // 0.08 minimal brightness on pause/stop, 1.0 when playing
    private var smoothedBass: Double = 0.0
    private var smoothedMid: Double = 0.0
    private var smoothedHigh: Double = 0.0
    private var smoothedKick: Double = 0.0

    private static let keyEnabled = "WLEDDDP_Enabled"
    private static let keyIP = "WLEDDDP_IP"
    private static let keyMode = "WLEDDDP_Mode"
    private static let keyLedCount = "WLEDDDP_LedCount"
    private static let keyBrightness = "WLEDDDP_Brightness"
    private static let keyDefaultTVMode = "AMR_DefaultTVModeOnStart"

    private static let defaultZones: [(r: Double, g: Double, b: Double)] = [
        (255, 20, 60),   (255, 70, 20),   (255, 160, 0),   (180, 30, 255),
        (90, 20, 255),   (0, 120, 255),   (0, 220, 255),   (0, 240, 150),
        (40, 20, 180),   (160, 0, 255),   (255, 0, 140),   (255, 45, 70),
        (255, 110, 0),   (0, 180, 255),   (110, 0, 255),   (255, 20, 90)
    ]

    private init() {
        let defaults = UserDefaults.standard
        self.isEnabled = defaults.bool(forKey: Self.keyEnabled)
        self.ipAddress = (defaults.string(forKey: Self.keyIP) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let savedMode = defaults.string(forKey: Self.keyMode) ?? "breathing"
        self.mode = Self.normalizeModeName(savedMode)
        let savedLeds = defaults.integer(forKey: Self.keyLedCount)
        self.ledCount = (savedLeds > 0) ? min(max(savedLeds, 1), 480) : 120
        let savedBri = defaults.object(forKey: Self.keyBrightness) as? Double ?? 0.92
        self.brightness = min(max(savedBri, 0.05), 1.0)
        self.defaultTVMode = defaults.bool(forKey: Self.keyDefaultTVMode)
        self.currentZones = Self.defaultZones
        self.targetZones = Self.defaultZones

        if !ipAddress.isEmpty {
            if isEnabled {
                probeWledDeviceInfoIfNeeded(ip: ipAddress)
            }
            reconfigureEngine()
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
            "enabled": isEnabled,
            "ip": ipAddress,
            "mode": mode,
            "led_count": ledCount,
            "brightness": brightness,
            "default_tv_mode": defaultTVMode
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
        var currentIpSnapshot: String = ""
        var notifyCallback: (@Sendable () -> Void)? = nil

        lock.lock()
        let wasActive = self.isEnabled && !self.ipAddress.isEmpty && self.mode != "off"
        if let en = enabled {
            self.isEnabled = en
            UserDefaults.standard.set(en, forKey: Self.keyEnabled)
        }
        if let rawIp = ip {
            let cleanIp = rawIp.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanIp != self.ipAddress {
                self.ipAddress = cleanIp
                self.lastProbedIP = ""
                UserDefaults.standard.set(cleanIp, forKey: Self.keyIP)
            }
        }
        if let m = mode {
            let normalized = Self.normalizeModeName(m)
            self.mode = normalized
            UserDefaults.standard.set(normalized, forKey: Self.keyMode)
        }
        if let cnt = ledCount, cnt > 0 {
            let clamped = min(max(cnt, 1), 480)
            self.ledCount = clamped
            UserDefaults.standard.set(clamped, forKey: Self.keyLedCount)
        }
        if let bri = brightness {
            let clamped = min(max(bri, 0.05), 1.0)
            self.brightness = clamped
            UserDefaults.standard.set(clamped, forKey: Self.keyBrightness)
        }
        if let defTv = defaultTVMode {
            self.defaultTVMode = defTv
            UserDefaults.standard.set(defTv, forKey: Self.keyDefaultTVMode)
        }
        let isNowActive = self.isEnabled && !self.ipAddress.isEmpty && self.mode != "off"
        currentIpSnapshot = self.ipAddress
        if !isNowActive && !currentIpSnapshot.isEmpty {
            shouldTurnOffStrip = true
        } else if !wasActive && isNowActive {
            shouldTurnOnStrip = true
        }
        if self.isEnabled && !self.ipAddress.isEmpty && ledCount == nil && self.lastProbedIP != self.ipAddress {
            ipToProbe = self.ipAddress
        }
        notifyCallback = self.onSettingsChanged
        lock.unlock()

        if let probeIp = ipToProbe {
            probeWledDeviceInfoIfNeeded(ip: probeIp)
        }
        if shouldTurnOffStrip {
            sendBlackoutFrame()
            sendWledHttpPowerState(ip: currentIpSnapshot, on: false)
        } else if shouldTurnOnStrip {
            sendWledHttpPowerState(ip: currentIpSnapshot, on: true)
        }
        reconfigureEngine()
        notifyCallback?()
        return getSettingsDictionary()
    }

    /// Updates the 16-zone spatial palette from client-extracted perimeter zones or 4-stop cover palette.
    public func updatePalette(_ colors: [[Int]]) {
        guard !colors.isEmpty else { return }
        var rawInput: [(r: Double, g: Double, b: Double)] = []
        for c in colors where c.count >= 3 {
            let r = Double(min(max(c[0], 0), 255))
            let g = Double(min(max(c[1], 0), 255))
            let b = Double(min(max(c[2], 0), 255))
            rawInput.append(Self.saturateForLED(r: r, g: g, b: b))
        }
        guard !rawInput.isEmpty else { return }

        let expanded = Self.buildRich16Zones(from: rawInput)

        lock.lock()
        self.targetZones = expanded
        lock.unlock()
    }

    // MARK: - WLED HTTP Info Auto-Discovery & Power Control (/json/info & /json/state)

    private func probeWledDeviceInfoIfNeeded(ip: String) {
        let cleanIp = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanIp.isEmpty else { return }
        lock.withLock {
            self.lastProbedIP = cleanIp
        }
        guard let url = URL(string: "http://\(cleanIp)/json/info") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2.0

        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data,
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
                if self.ledCount != clamped {
                    self.ledCount = clamped
                    UserDefaults.standard.set(clamped, forKey: Self.keyLedCount)
                    changed = true
                    callback = self.onSettingsChanged
                }
            }
            if changed {
                NSLog("[WLEDDDPController] 🔍 Auto-detected WLED strip length: %d LEDs at %@", clamped, cleanIp)
                callback?()
            }
        }.resume()
    }

    private func sendWledHttpPowerState(ip: String, on: Bool) {
        let cleanIp = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanIp.isEmpty,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let url = URL(string: "http://\(cleanIp)/json/state") else {
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 1.5
        let body: [String: Any] = on ? ["on": true, "bri": 255] : ["on": false]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
    }

    // MARK: - Color Science & Multi-Zone Synthesis for Addressable LEDs

    private static func rgbToHsv(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
        let rf = r / 255.0
        let gf = g / 255.0
        let bf = b / 255.0
        let maxC = max(rf, gf, bf)
        let minC = min(rf, gf, bf)
        let delta = maxC - minC

        var h: Double = 0.0
        if delta > 0.0001 {
            if maxC == rf {
                h = 60.0 * (((gf - bf) / delta).truncatingRemainder(dividingBy: 6.0))
            } else if maxC == gf {
                h = 60.0 * (((bf - rf) / delta) + 2.0)
            } else {
                h = 60.0 * (((rf - gf) / delta) + 4.0)
            }
            if h < 0 { h += 360.0 }
        }
        let s = maxC <= 0.0001 ? 0.0 : (delta / maxC)
        return (h, s, maxC)
    }

    private static func hsvToRgb(h: Double, s: Double, v: Double) -> (r: Double, g: Double, b: Double) {
        let cleanH = ((h.truncatingRemainder(dividingBy: 360.0)) + 360.0).truncatingRemainder(dividingBy: 360.0)
        let c = v * s
        let x = c * (1.0 - abs(((cleanH / 60.0).truncatingRemainder(dividingBy: 2.0)) - 1.0))
        let m = v - c
        let (r1, g1, b1): (Double, Double, Double)
        switch cleanH {
        case 0..<60:    (r1, g1, b1) = (c, x, 0)
        case 60..<120:  (r1, g1, b1) = (x, c, 0)
        case 120..<180: (r1, g1, b1) = (0, c, x)
        case 180..<240: (r1, g1, b1) = (0, x, c)
        case 240..<300: (r1, g1, b1) = (x, 0, c)
        default:        (r1, g1, b1) = (c, 0, x)
        }
        return ((r1 + m) * 255.0, (g1 + m) * 255.0, (b1 + m) * 255.0)
    }

    private static func saturateForLED(r: Double, g: Double, b: Double) -> (r: Double, g: Double, b: Double) {
        var (h, s, v) = rgbToHsv(r: r, g: g, b: b)
        if s > 0.08 {
            s = min(1.0, pow(s, 0.42) * 1.18)
        }
        v = min(1.0, max(0.28, pow(v, 0.85) * 1.12))
        return hsvToRgb(h: h, s: s, v: v)
    }

    private static func hueDistance(_ h1: Double, _ h2: Double) -> Double {
        let diff = abs(h1 - h2).truncatingRemainder(dividingBy: 360.0)
        return diff > 180.0 ? 360.0 - diff : diff
    }

    private static func buildRich16Zones(from input: [(r: Double, g: Double, b: Double)]) -> [(r: Double, g: Double, b: Double)] {
        let hsvList = input.map { rgbToHsv(r: $0.r, g: $0.g, b: $0.b) }
        let baseHsv = hsvList[0]

        var maxHueSpread: Double = 0.0
        for i in 0..<hsvList.count {
            for j in (i + 1)..<hsvList.count {
                if hsvList[i].s > 0.15 && hsvList[j].s > 0.15 {
                    maxHueSpread = max(maxHueSpread, hueDistance(hsvList[i].h, hsvList[j].h))
                }
            }
        }

        var anchors: [(h: Double, s: Double, v: Double)] = []
        if maxHueSpread < 38.0 {
            let domH = baseHsv.s > 0.1 ? baseHsv.h : 345.0
            let domS = max(baseHsv.s, 0.92)
            anchors = [
                (domH, domS, 1.0),
                (domH + 38.0, min(1.0, domS * 0.95), 0.88),
                (domH, domS, 0.25),
                (domH - 42.0, min(1.0, domS), 0.95),
                (domH + 155.0, min(1.0, domS * 0.9), 0.82),
                (domH - 25.0, domS, 0.30),
                (domH + 22.0, domS, 0.96),
                (domH - 145.0, min(1.0, domS * 0.88), 0.78)
            ]
        } else if input.count >= zoneCount {
            var zones: [(r: Double, g: Double, b: Double)] = []
            for i in 0..<zoneCount {
                var (h, s, v) = hsvList[i]
                if i % 4 == 2 {
                    v = max(0.24, v * 0.62)
                    s = min(1.0, s * 1.1)
                } else if i % 4 == 0 {
                    v = min(1.0, v * 1.12)
                }
                if i > 0 && hueDistance(h, rgbToHsv(r: zones[i - 1].r, g: zones[i - 1].g, b: zones[i - 1].b).h) < 12.0 {
                    h += (i % 2 == 0) ? 24.0 : -24.0
                }
                zones.append(hsvToRgb(h: h, s: max(s, 0.82), v: v))
            }
            return zones
        } else {
            for (idx, item) in hsvList.enumerated() {
                let s = max(item.s, 0.85)
                anchors.append((item.h, s, min(1.0, max(item.v, 0.82))))
                let next = hsvList[(idx + 1) % hsvList.count]
                let midH = hueDistance(item.h, next.h) < 25.0 ? (item.h + 40.0) : (item.h + next.h) * 0.5
                anchors.append((midH, min(1.0, s * 1.05), 0.34))
            }
        }

        var result: [(r: Double, g: Double, b: Double)] = []
        for i in 0..<zoneCount {
            let t = Double(i) / Double(zoneCount) * Double(anchors.count)
            let idxA = Int(t) % anchors.count
            let idxB = (idxA + 1) % anchors.count
            let frac = t - floor(t)
            let a = anchors[idxA]
            let b = anchors[idxB]

            var deltaH = b.h - a.h
            if deltaH > 180.0 { deltaH -= 360.0 }
            if deltaH < -180.0 { deltaH += 360.0 }
            let h = a.h + deltaH * frac
            let s = a.s + (b.s - a.s) * frac
            let v = a.v + (b.v - a.v) * frac
            result.append(hsvToRgb(h: h, s: s, v: v))
        }
        return result
    }

    // MARK: - Engine Lifecycle & Off-State Heartbeat

    private func reconfigureEngine() {
        ddpQueue.async { [weak self] in
            guard let self = self else { return }
            let (enabled, ip, currentMode) = self.lock.withLock {
                (self.isEnabled, self.ipAddress, self.mode)
            }
            let active = enabled && !ip.isEmpty && currentMode != "off"

            // Subscribe to CoreAudio Process Tap for ALL active modes except "static"
            let needsAudioTap = active && currentMode != "static"
            if needsAudioTap && !self.isTapSubscribed {
                self.isTapSubscribed = true
                AudioProcessTapService.shared.addSubscriber(id: self.tapSubscriberId) { [weak self] pcmData in
                    self?.processAudioChunk(pcmData)
                }
            } else if !needsAudioTap && self.isTapSubscribed {
                self.isTapSubscribed = false
                AudioProcessTapService.shared.removeSubscriber(id: self.tapSubscriberId)
            }

            if ip.isEmpty {
                self.stopTimerAndSocket()
                return
            }

            self.ensureSocket(for: ip)

            if active {
                if self.timer == nil || self.timerIntervalMs != 20 {
                    self.timer?.cancel()
                    self.timer = nil
                    let t = DispatchSource.makeTimerSource(queue: self.ddpQueue)
                    t.schedule(deadline: .now(), repeating: .milliseconds(20), leeway: .milliseconds(2))
                    t.setEventHandler { [weak self] in
                        self?.tickFrame()
                    }
                    t.resume()
                    self.timer = t
                    self.timerIntervalMs = 20
                    self.sendWledHttpPowerState(ip: ip, on: true)
                    NSLog("[WLEDDDPController] 💡 Started 16-Zone DDP Ambilight stream -> %@:4048 (mode=%@)", ip, currentMode)
                }
            } else {
                // WLED is disabled in AMR or mode == "off":
                // Keep a 1500ms Off-State Heartbeat running so WLED controllers with auto-power-on or
                // UDP realtime timeout stay turned OFF.
                self.offHeartbeatTickCount = 0
                self.dispatchBlackoutPacketSync(ip: ip)
                self.sendWledHttpPowerState(ip: ip, on: false)

                if self.timer == nil || self.timerIntervalMs != 1500 {
                    self.timer?.cancel()
                    self.timer = nil
                    let t = DispatchSource.makeTimerSource(queue: self.ddpQueue)
                    t.schedule(deadline: .now() + .milliseconds(1500), repeating: .milliseconds(1500), leeway: .milliseconds(100))
                    t.setEventHandler { [weak self] in
                        self?.tickOffStateHeartbeat()
                    }
                    t.resume()
                    self.timer = t
                    self.timerIntervalMs = 1500
                    NSLog("[WLEDDDPController] 🌙 WLED Off-State Heartbeat active for %@ (keeping strip off)", ip)
                }
            }
        }
    }

    private func tickOffStateHeartbeat() {
        let (enabled, ip, currentMode) = lock.withLock {
            (self.isEnabled, self.ipAddress, self.mode)
        }
        guard !ip.isEmpty, !(enabled && currentMode != "off") else { return }
        dispatchBlackoutPacketSync(ip: ip)
        offHeartbeatTickCount += 1
        if offHeartbeatTickCount % 8 == 0 {
            sendWledHttpPowerState(ip: ip, on: false)
        }
    }

    private func stopEngine() {
        if isTapSubscribed {
            isTapSubscribed = false
            AudioProcessTapService.shared.removeSubscriber(id: tapSubscriberId)
        }
        ddpQueue.sync {
            stopTimerAndSocket()
        }
    }

    private func stopTimerAndSocket() {
        timer?.cancel()
        timer = nil
        timerIntervalMs = 0
        if udpSocket >= 0 {
            Darwin.close(udpSocket)
            udpSocket = -1
        }
        cachedSockAddr = nil
        cachedIPString = ""
    }

    private func ensureSocket(for ip: String) {
        if udpSocket < 0 {
            let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            if fd >= 0 {
                var nonBlocking: Int32 = 1
                _ = Darwin.ioctl(fd, 0x8004667e /* FIONBIO */, &nonBlocking)
                udpSocket = fd
            }
        }
        if ip != cachedIPString || cachedSockAddr == nil {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = UInt16(4048).bigEndian
            if inet_pton(AF_INET, ip, &addr.sin_addr) == 1 {
                cachedSockAddr = addr
                cachedIPString = ip
            } else {
                cachedSockAddr = nil
            }
        }
    }

    // MARK: - Full-Rate 3-Band CoreAudio DSP with Automatic Gain Control (AGC)

    private func processAudioChunk(_ data: Data) {
        let count = data.count
        guard count >= 4 else { return }
        let bitDepth = AudioProcessTapService.shared.bitDepth
        let sampleRate = Double(max(AudioProcessTapService.shared.sampleRate, 44100))

        // True per-frame dt (we process every stereo frame so IIR filter cutoff frequencies are exact!)
        let dt = 1.0 / sampleRate
        let rc115 = 1.0 / (2.0 * Double.pi * 115.0)
        let alpha115 = dt / (rc115 + dt)

        let rc2200 = 1.0 / (2.0 * Double.pi * 2200.0)
        let alpha2200 = dt / (rc2200 + dt)

        var sumBassSq: Double = 0.0
        var sumMidSq: Double = 0.0
        var sumHighSq: Double = 0.0
        var framesProcessed = 0

        var b1 = lp115Stage1
        var b2 = lp115Stage2
        var m1 = lp2200Stage1
        var m2 = lp2200Stage2

        data.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            if bitDepth == 24 {
                let bytesPerFrame = 6 // 2 channels * 3 bytes
                let frameCount = count / bytesPerFrame
                let ptr = base.assumingMemoryBound(to: UInt8.self)
                for f in 0..<frameCount {
                    let offset = f * bytesPerFrame
                    let l0 = Int32(ptr[offset]) | (Int32(ptr[offset + 1]) << 8) | (Int32(Int8(bitPattern: ptr[offset + 2])) << 16)
                    let r0 = Int32(ptr[offset + 3]) | (Int32(ptr[offset + 4]) << 8) | (Int32(Int8(bitPattern: ptr[offset + 5])) << 16)
                    let mono = Double(l0 + r0) / (2.0 * 8_388_608.0)

                    // 2-pole cascaded low-pass at 115 Hz (Sub-bass & kick drum)
                    b1 += alpha115 * (mono - b1)
                    b2 += alpha115 * (b1 - b2)

                    // 2-pole cascaded low-pass at 2200 Hz
                    m1 += alpha2200 * (mono - m1)
                    m2 += alpha2200 * (m1 - m2)

                    let bass = b2
                    let mid = m2 - b2
                    let high = mono - m2

                    sumBassSq += bass * bass
                    sumMidSq += mid * mid
                    sumHighSq += high * high
                }
                framesProcessed = frameCount
            } else {
                let sampleCount = count / 2
                let frameCount = sampleCount / 2
                let ptr = base.assumingMemoryBound(to: Int16.self)
                for f in 0..<frameCount {
                    let idx = f * 2
                    let mono = (Double(ptr[idx]) + Double(ptr[idx + 1])) / (2.0 * 32768.0)

                    b1 += alpha115 * (mono - b1)
                    b2 += alpha115 * (b1 - b2)

                    m1 += alpha2200 * (mono - m1)
                    m2 += alpha2200 * (m1 - m2)

                    let bass = b2
                    let mid = m2 - b2
                    let high = mono - m2

                    sumBassSq += bass * bass
                    sumMidSq += mid * mid
                    sumHighSq += high * high
                }
                framesProcessed = frameCount
            }
        }

        lp115Stage1 = b1
        lp115Stage2 = b2
        lp2200Stage1 = m1
        lp2200Stage2 = m2
        guard framesProcessed > 0 else { return }

        let rmsBass = sqrt(sumBassSq / Double(framesProcessed))
        let rmsMid  = sqrt(sumMidSq / Double(framesProcessed))
        let rmsHigh = sqrt(sumHighSq / Double(framesProcessed))

        // Ignore pure digital silence frames injected by SilenceGenerator when paused
        let totalRms = rmsBass + rmsMid + rmsHigh
        guard totalRms > 0.0002 else { return }

        let now = Date()
        lock.lock()
        // Automatic Gain Control (AGC): track running peak per band with fast attack and slow release
        if rmsBass > agcPeakBass {
            agcPeakBass += (rmsBass - agcPeakBass) * 0.25
        } else {
            agcPeakBass = max(0.015, agcPeakBass * 0.992)
        }
        if rmsMid > agcPeakMid {
            agcPeakMid += (rmsMid - agcPeakMid) * 0.22
        } else {
            agcPeakMid = max(0.015, agcPeakMid * 0.992)
        }
        if rmsHigh > agcPeakHigh {
            agcPeakHigh += (rmsHigh - agcPeakHigh) * 0.25
        } else {
            agcPeakHigh = max(0.008, agcPeakHigh * 0.992)
        }

        // Normalize 0.0 ... 1.0 using AGC peak reference and expand dynamic contrast
        let rawNormBass = min(1.0, rmsBass / max(0.015, agcPeakBass * 0.92))
        let rawNormMid  = min(1.0, rmsMid  / max(0.015, agcPeakMid * 0.92))
        let rawNormHigh = min(1.0, rmsHigh / max(0.008, agcPeakHigh * 0.92))

        // Shape curves so quiet passages drop low (~0.05) and beats swell up to 1.0
        let shapedBass = pow(rawNormBass, 1.35)
        let shapedMid  = pow(rawNormMid, 1.25)
        let shapedHigh = pow(rawNormHigh, 1.30)

        // Detect bass/kick onset delta for rhythmic pulse
        let bassDelta = max(0.0, shapedBass - prevNormBass)
        prevNormBass = shapedBass
        if bassDelta > 0.10 {
            kickPulseEnvelope = min(1.0, kickPulseEnvelope + bassDelta * 1.65)
        } else {
            kickPulseEnvelope *= 0.82
        }

        bassEnvelope += (shapedBass - bassEnvelope) * (shapedBass > bassEnvelope ? 0.42 : 0.16)
        midEnvelope  += (shapedMid - midEnvelope)   * (shapedMid > midEnvelope ? 0.38 : 0.15)
        highEnvelope += (shapedHigh - highEnvelope) * (shapedHigh > highEnvelope ? 0.45 : 0.18)
        lastAudioChunkTime = now
        lock.unlock()
    }

    // MARK: - 50 FPS Multi-Zone Frame Generator & DDP Packet Dispatch

    private func sampleZone(at continuousIndex: Double, zones: [(r: Double, g: Double, b: Double)]) -> (r: Double, g: Double, b: Double) {
        let count = zones.count
        guard count > 0 else { return (250, 35, 59) }
        let wrapped = ((continuousIndex.truncatingRemainder(dividingBy: Double(count))) + Double(count)).truncatingRemainder(dividingBy: Double(count))
        let idxA = Int(floor(wrapped)) % count
        let idxB = (idxA + 1) % count
        let frac = wrapped - floor(wrapped)
        let smooth = frac * frac * (3.0 - 2.0 * frac)
        let a = zones[idxA]
        let b = zones[idxB]
        return (
            a.r + (b.r - a.r) * smooth,
            a.g + (b.g - a.g) * smooth,
            a.b + (b.b - a.b) * smooth
        )
    }

    private func tickFrame() {
        let (active, ip, currentMode, count, baseBri, targetZ, rawBass, rawMid, rawHigh, rawKick, lastChunk) = lock.withLock {
            (
                self.isEnabled && !self.ipAddress.isEmpty && self.mode != "off",
                self.ipAddress,
                self.mode,
                self.ledCount,
                self.brightness,
                self.targetZones,
                self.bassEnvelope,
                self.midEnvelope,
                self.highEnvelope,
                self.kickPulseEnvelope,
                self.lastAudioChunkTime
            )
        }
        guard active, count > 0 else { return }
        ensureSocket(for: ip)
        guard udpSocket >= 0, var addr = cachedSockAddr else { return }

        // Smoothly crossfade currentZones -> targetZones
        let lerpFactor = 0.07
        for i in 0..<min(currentZones.count, targetZ.count) {
            currentZones[i].r += (targetZ[i].r - currentZones[i].r) * lerpFactor
            currentZones[i].g += (targetZ[i].g - currentZones[i].g) * lerpFactor
            currentZones[i].b += (targetZ[i].b - currentZones[i].b) * lerpFactor
        }

        let isPlaying = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastPlayerStatusCache?.status.isPlaying ?? false
        }

        // On Pause / Stop: freeze phase movement and smoothly dim to minimal idle brightness (8%)
        let targetDim = isPlaying ? 1.0 : 0.08
        playbackDimFactor += (targetDim - playbackDimFactor) * (isPlaying ? 0.07 : 0.04)

        if isPlaying {
            phase += 0.025 + smoothedBass * 0.015
            if phase > Double.pi * 400.0 {
                phase -= Double.pi * 400.0
            }
        }

        // Update 50 FPS smoothed audio envelopes
        let age = Date().timeIntervalSince(lastChunk)
        if !isPlaying {
            smoothedBass += (0.0 - smoothedBass) * 0.14
            smoothedMid  += (0.0 - smoothedMid)  * 0.14
            smoothedHigh += (0.0 - smoothedHigh) * 0.14
            smoothedKick += (0.0 - smoothedKick) * 0.16
        } else if age < 0.35 {
            smoothedBass += (rawBass - smoothedBass) * 0.28
            smoothedMid  += (rawMid  - smoothedMid)  * 0.25
            smoothedHigh += (rawHigh - smoothedHigh) * 0.30
            smoothedKick += (rawKick - smoothedKick) * 0.32
        } else {
            // Musical rhythmic fallback if playing via external network streamer without local CoreAudio tap
            let synthBass = pow(0.5 + 0.5 * sin(phase * 1.8), 2.0)
            let synthMid  = 0.5 + 0.5 * sin(phase * 1.1 + 1.3)
            let synthHigh = pow(0.5 + 0.5 * cos(phase * 2.4), 2.0)
            smoothedBass += (synthBass * 0.80 - smoothedBass) * 0.15
            smoothedMid  += (synthMid  * 0.70 - smoothedMid)  * 0.15
            smoothedHigh += (synthHigh * 0.60 - smoothedHigh) * 0.15
            smoothedKick += (synthBass * 0.75 - smoothedKick) * 0.18
        }

        let payloadByteCount = count * 3
        var packet = [UInt8](repeating: 0, count: 10 + payloadByteCount)

        // DDP 10-byte Header
        packet[0] = 0x41 // Version 1 + PUSH flag
        packet[1] = sequenceNumber
        sequenceNumber = (sequenceNumber % 15) + 1
        packet[2] = 0x01 // RGB 8-bit
        packet[3] = 0x01 // Default destination ID
        let lenBE = UInt16(payloadByteCount).bigEndian
        packet[8] = UInt8(lenBE & 0xFF)
        packet[9] = UInt8((lenBE >> 8) & 0xFF)

        let zCount = Double(Self.zoneCount)
        let zonesSnapshot = currentZones
        let effectiveBri = baseBri * playbackDimFactor
        let motionWeight = max(0.0, min(1.0, (playbackDimFactor - 0.08) / 0.92))

        // Combined musical energy variables (0.0 ... 1.0)
        let bassEnergy = min(1.0, smoothedBass * 0.75 + smoothedKick * 0.45)
        let midEnergy  = min(1.0, smoothedMid)
        let highEnergy = min(1.0, smoothedHigh)

        for i in 0..<count {
            let normPos = count > 1 ? Double(i) / Double(count - 1) : 0.0
            let distFromCenter = abs(normPos - 0.5) * 2.0 // 0.0 at center, 1.0 at left/right edges
            let baseZoneIdx = normPos * (zCount - 1.0)
            var r: Double = 0
            var g: Double = 0
            var b: Double = 0

            if currentMode == "static" || motionWeight < 0.02 {
                // "Статичная палитра обложки" (также используется на паузе/стопе при минимальной яркости)
                let col = sampleZone(at: baseZoneIdx, zones: zonesSnapshot)
                let contour = 0.84 + 0.16 * sin(normPos * Double.pi * 3.0)
                r = col.r * effectiveBri * contour
                g = col.g * effectiveBri * contour
                b = col.b * effectiveBri * contour

            } else if currentMode == "breathing" {
                // 1. "Синусоида ритма (Стоячая волна под музыку)":
                // Неподвижные синусоидальные полуволны вдоль ленты (узлы стоят на месте, никакого бега огней!).
                // На басах/бочке мощно вырастают 3 основные полуволны (от 10% до 100%),
                // а на вокале/средних частотах плавно поднимаются полуволны во впадинах.
                let baseCol = sampleZone(at: baseZoneIdx, zones: zonesSnapshot)
                let accentCol = sampleZone(at: baseZoneIdx + zCount * 0.35, zones: zonesSnapshot)

                let bassLobes = pow(sin(normPos * Double.pi * 3.0), 2.0) // 3 стоячих купола баса
                let midLobes  = pow(cos(normPos * Double.pi * 3.0), 2.0) // Впадины между ними откликаются на вокал/середину

                // Амплитуда стоячих полуволн напрямую следует за басом и серединой музыки
                let bassAmp = 0.06 + 0.94 * pow(bassEnergy, 0.85)
                let midAmp  = 0.06 + 0.72 * pow(midEnergy, 0.90)

                let standingWave = min(1.0, 0.08 + bassLobes * bassAmp * 0.88 + midLobes * midAmp * 0.52)

                // На пиках баса верхушки синусоиды переливаются контрастным тоном обложки
                let colorShift = min(0.65, bassLobes * bassEnergy * 0.65) * motionWeight
                let mixR = baseCol.r * (1.0 - colorShift) + accentCol.r * colorShift
                let mixG = baseCol.g * (1.0 - colorShift) + accentCol.g * colorShift
                let mixB = baseCol.b * (1.0 - colorShift) + accentCol.b * colorShift

                let env = (1.0 - motionWeight) * 0.85 + motionWeight * standingWave
                r = mixR * effectiveBri * env
                g = mixG * effectiveBri * env
                b = mixB * effectiveBri * env

            } else if currentMode == "spectrum" {
                // 2. "Спектральный эквалайзер (Бас · Вокал · Верх)":
                // Лента разделена на симметричные частотные области:
                // - Центр ленты (0.0..0.38 от центра): мощно качает Суб-бас и Бочка (<115 Гц)
                // - Средние крылья (0.30..0.75 от центра): поют в такт Вокалу и Инструментам (115..2200 Гц)
                // - Края ленты (0.65..1.0 от центра): откликаются на Хай-хэты и Верх (>2200 Гц)
                let baseCol = sampleZone(at: baseZoneIdx, zones: zonesSnapshot)
                let highCol = sampleZone(at: baseZoneIdx + zCount * 0.5, zones: zonesSnapshot)

                // Плавные гауссоподобные купола для 3 полос частот (без резких границ)
                let bassZoneWeight = exp(-pow(distFromCenter / 0.38, 2.0))
                let midZoneWeight  = exp(-pow((distFromCenter - 0.52) / 0.26, 2.0))
                let highZoneWeight = exp(-pow((distFromCenter - 0.88) / 0.24, 2.0)) * (0.65 + 0.35 * pow(sin(normPos * Double.pi * 8.0), 2.0))

                let bandResponse =
                    bassZoneWeight * (0.10 + 0.90 * pow(bassEnergy, 0.80)) +
                    midZoneWeight  * (0.10 + 0.85 * pow(midEnergy, 0.85)) +
                    highZoneWeight * (0.08 + 0.92 * pow(highEnergy, 0.80))

                let eqLevel = min(1.0, max(0.08, bandResponse))
                let highTint = min(0.70, highZoneWeight * highEnergy * 0.75) * motionWeight

                let mixR = baseCol.r * (1.0 - highTint) + highCol.r * highTint
                let mixG = baseCol.g * (1.0 - highTint) + highCol.g * highTint
                let mixB = baseCol.b * (1.0 - highTint) + highCol.b * highTint

                let env = (1.0 - motionWeight) * 0.85 + motionWeight * eqLevel
                r = mixR * effectiveBri * env
                g = mixG * effectiveBri * env
                b = mixB * effectiveBri * env

            } else if currentMode == "vu_center" {
                // 3. "Симметричный пульс (Раскрытие от центра)":
                // Музыкальный купол раскрывается из центра ленты к краям пропорционально энергии трека и басу.
                // В тихих фрагментах тлеет компактное ядро в центре, на ударах баса и припевах волна
                // плавно раскрывается на всю ширину ленты.
                let baseCol = sampleZone(at: baseZoneIdx, zones: zonesSnapshot)
                let centerCol = sampleZone(at: (1.0 - distFromCenter) * (zCount * 0.5), zones: zonesSnapshot)

                // Радиус раскрытия от центра: от 0.18 в тишине до 1.05 на пике баса и вокала
                let activeSpan = 0.18 + 0.87 * min(1.0, bassEnergy * 0.68 + midEnergy * 0.42)
                let normalizedDist = distFromCenter / max(0.15, activeSpan)

                // Плавная косинусная огибающая купола от центра к краям
                let vuBell: Double
                if normalizedDist < 1.0 {
                    let c = cos(normalizedDist * Double.pi * 0.5)
                    vuBell = 0.08 + 0.92 * (c * c) * (0.35 + 0.65 * max(bassEnergy, midEnergy))
                } else {
                    vuBell = 0.08
                }

                let blend = (1.0 - distFromCenter * 0.6) * motionWeight
                let mixR = baseCol.r * (1.0 - blend * 0.5) + centerCol.r * (blend * 0.5)
                let mixG = baseCol.g * (1.0 - blend * 0.5) + centerCol.g * (blend * 0.5)
                let mixB = baseCol.b * (1.0 - blend * 0.5) + centerCol.b * (blend * 0.5)

                let env = (1.0 - motionWeight) * 0.85 + motionWeight * vuBell
                r = mixR * effectiveBri * env
                g = mixG * effectiveBri * env
                b = mixB * effectiveBri * env

            } else if currentMode == "harmonic" {
                // 4. "Гармонический резонанс (Цвет и ритм мелодии)":
                // 4 стоячих синусоидальных купола по длине ленты, где бас управляет глубиной рельефа,
                // а соотношение Вокал/Бас плавно переливает палитру между тёплыми и контрастными зонами обложки.
                let primaryCol = sampleZone(at: baseZoneIdx, zones: zonesSnapshot)
                let oppositeCol = sampleZone(at: (baseZoneIdx + zCount * 0.5), zones: zonesSnapshot)

                let standingDome = pow(sin(normPos * Double.pi * 4.0), 2.0) // 4 стоячих купола
                let complementDome = pow(cos(normPos * Double.pi * 4.0), 2.0)

                // Цветовой баланс напрямую зависит от музыки (мелодия + верх раскрывают контрастный цвет)
                let harmonicShift = min(0.85, (midEnergy * 0.55 + highEnergy * 0.45) * standingDome) * motionWeight
                let mixR = primaryCol.r * (1.0 - harmonicShift) + oppositeCol.r * harmonicShift
                let mixG = primaryCol.g * (1.0 - harmonicShift) + oppositeCol.g * harmonicShift
                let mixB = primaryCol.b * (1.0 - harmonicShift) + oppositeCol.b * harmonicShift

                // Высота куполов дышит под бас, а впадины подсвечиваются серединой
                let domeBri = 0.10 + standingDome * (0.20 + 0.80 * bassEnergy) + complementDome * (0.35 * midEnergy)
                let clampedBri = min(1.0, max(0.10, domeBri))

                let env = (1.0 - motionWeight) * 0.85 + motionWeight * clampedBri
                r = mixR * effectiveBri * env
                g = mixG * effectiveBri * env
                b = mixB * effectiveBri * env

            } else {
                // 5. "ambilight": "Живой Ambilight (16 зон + пульс музыки)"
                // Полноценная 16-зонная пространственная палитра обложки, где каждая зона мягко дышит
                // по стоячей синусоиде в такт басу и мелодии трека.
                let standingSway = sin(normPos * Double.pi * 2.0) * sin(phase * 0.5) * (0.4 + 0.8 * midEnergy) * motionWeight
                let colPrimary = sampleZone(at: baseZoneIdx + standingSway, zones: zonesSnapshot)
                let colSecondary = sampleZone(at: baseZoneIdx + 2.0, zones: zonesSnapshot)

                let trebleGlow = pow(sin(normPos * Double.pi * 3.0), 2.0) * highEnergy * 0.45 * motionWeight
                let mixR = colPrimary.r * (1.0 - trebleGlow) + colSecondary.r * trebleGlow
                let mixG = colPrimary.g * (1.0 - trebleGlow) + colSecondary.g * trebleGlow
                let mixB = colPrimary.b * (1.0 - trebleGlow) + colSecondary.b * trebleGlow

                let standingWave = 0.5 + 0.5 * sin(normPos * Double.pi * 3.0) * cos(phase * 0.45)
                let musicPulse = 0.28 + 0.72 * (0.35 * standingWave + 0.65 * (bassEnergy * 0.7 + midEnergy * 0.3))
                let env = (1.0 - motionWeight) * 0.85 + motionWeight * min(1.0, musicPulse)

                r = mixR * effectiveBri * env
                g = mixG * effectiveBri * env
                b = mixB * effectiveBri * env
            }

            let rIdx = min(max(Int(r.rounded()), 0), 255)
            let gIdx = min(max(Int(g.rounded()), 0), 255)
            let bIdx = min(max(Int(b.rounded()), 0), 255)

            let baseIdx = 10 + i * 3
            packet[baseIdx]     = gammaLUT[rIdx]
            packet[baseIdx + 1] = gammaLUT[gIdx]
            packet[baseIdx + 2] = gammaLUT[bIdx]
        }

        packet.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                    _ = Darwin.sendto(udpSocket, base, packet.count, 0, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private func dispatchBlackoutPacketSync(ip: String) {
        let count = lock.withLock { self.ledCount }
        guard !ip.isEmpty, count > 0 else { return }
        ensureSocket(for: ip)
        guard udpSocket >= 0, var addr = self.cachedSockAddr else { return }

        let payloadByteCount = count * 3
        var packet = [UInt8](repeating: 0, count: 10 + payloadByteCount)
        packet[0] = 0x41
        packet[1] = sequenceNumber
        sequenceNumber = (sequenceNumber % 15) + 1
        packet[2] = 0x01
        packet[3] = 0x01
        let lenBE = UInt16(payloadByteCount).bigEndian
        packet[8] = UInt8(lenBE & 0xFF)
        packet[9] = UInt8((lenBE >> 8) & 0xFF)

        packet.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                    _ = Darwin.sendto(udpSocket, base, packet.count, 0, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private func sendBlackoutFrame() {
        ddpQueue.async { [weak self] in
            guard let self = self else { return }
            let ip = self.lock.withLock { self.ipAddress }
            self.dispatchBlackoutPacketSync(ip: ip)
        }
    }
}
