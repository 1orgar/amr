import Foundation
import Network

/// Supported ASCII / Text-over-TCP amplifier protocols.
public enum ExternalAmpProfile: String, CaseIterable, Codable, Sendable {
    case rotel = "rotel"
    case denonMarantz = "denon_marantz"
    case hegel = "hegel"
    case nad = "nad"
    case lyngdorf = "lyngdorf"

    public var displayName: String {
        switch self {
        case .rotel:
            return "Rotel"
        case .denonMarantz:
            return "Denon / Marantz"
        case .hegel:
            return "Hegel"
        case .nad:
            return "NAD"
        case .lyngdorf:
            return "Lyngdorf"
        }
    }

    public var menuTitle: String {
        switch self {
        case .rotel:
            return "Rotel (ASCII TCP :9590)"
        case .denonMarantz:
            return "Denon / Marantz (ASCII TCP :23)"
        case .hegel:
            return "Hegel (ASCII TCP :50001)"
        case .nad:
            return "NAD (ASCII TCP :30000)"
        case .lyngdorf:
            return "Lyngdorf (ASCII TCP :84)"
        }
    }

    public var defaultPort: UInt16 {
        switch self {
        case .rotel:
            return 9590
        case .denonMarantz:
            return 23
        case .hegel:
            return 50001
        case .nad:
            return 30000
        case .lyngdorf:
            return 84
        }
    }

    public var nativeMaxVolume: Int {
        switch self {
        case .rotel:
            return 96
        case .denonMarantz:
            return 98
        case .hegel, .nad, .lyngdorf:
            return 100
        }
    }

    /// Builds the ASCII command to set the hardware volume to `volume`.
    public func buildSetVolumeCommand(_ volume: Int) -> String {
        let clamped = max(0, min(nativeMaxVolume, volume))
        switch self {
        case .rotel:
            return String(format: "vol_%02d!", clamped)
        case .denonMarantz:
            return String(format: "MV%02d\r", clamped)
        case .hegel:
            return "-v.\(clamped)\r"
        case .nad:
            return "Main.Volume=\(clamped)\r\n"
        case .lyngdorf:
            let dbTenths = (clamped - 100) * 8 // 0..100 -> -800..0 (-80.0dB .. 0.0dB)
            return "!VOL(\(dbTenths))\r"
        }
    }

    /// Builds the ASCII command to step volume up or down.
    public func buildStepVolumeCommand(up: Bool) -> String {
        switch self {
        case .rotel:
            return up ? "vol_up!" : "vol_dwn!"
        case .denonMarantz:
            return up ? "MVUP\r" : "MVDOWN\r"
        case .hegel:
            return up ? "-v.u\r" : "-v.d\r"
        case .nad:
            return up ? "Main.Volume+\r\n" : "Main.Volume-\r\n"
        case .lyngdorf:
            return up ? "!VOLUP\r" : "!VOLDN\r"
        }
    }

    /// Builds the ASCII command to set or toggle mute state.
    public func buildMuteCommand(muted: Bool? = nil) -> String {
        switch self {
        case .rotel:
            if let muted {
                return muted ? "mute_on!" : "mute_off!"
            }
            return "mute!"
        case .denonMarantz:
            let target = muted ?? true
            return target ? "MUON\r" : "MUOFF\r"
        case .hegel:
            if let muted {
                return muted ? "-m.1\r" : "-m.0\r"
            }
            return "-m.t\r"
        case .nad:
            let target = muted ?? true
            return target ? "Main.Mute=On\r\n" : "Main.Mute=Off\r\n"
        case .lyngdorf:
            let target = muted ?? true
            return target ? "!MUTEON\r" : "!MUTEOFF\r"
        }
    }

    /// Builds the periodic status query command to poll current volume and mute state.
    public func buildQueryStatusCommand() -> String {
        switch self {
        case .rotel:
            return "get_volume!get_mute_status!"
        case .denonMarantz:
            return "MV?\rMU?\r"
        case .hegel:
            return "-v.?\r-m.?\r"
        case .nad:
            return "Main.Volume?\r\nMain.Mute?\r\n"
        case .lyngdorf:
            return "!VOL?\r!MUTE?\r"
        }
    }

    /// Parses a single ASCII response token (already trimmed of frame delimiters `$`, `!`, `\r`, `\n`).
    public func parseToken(_ rawToken: String) -> (volume: Int?, muted: Bool?) {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return (nil, nil) }
        let lower = token.lowercased()

        switch self {
        case .rotel:
            // Examples: "volume=45", "vol=45", "volume=min", "volume=max", "mute=on", "mute=off"
            if lower.hasPrefix("volume=") || lower.hasPrefix("vol=") {
                let parts = lower.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let valStr = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if valStr == "min" {
                        return (0, nil)
                    } else if valStr == "max" {
                        return (nativeMaxVolume, nil)
                    }
                    let digits = valStr.filter { $0.isNumber }
                    if let v = Int(digits) {
                        return (max(0, min(nativeMaxVolume, v)), nil)
                    }
                }
            }
            if lower.hasPrefix("mute=") {
                let parts = lower.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let valStr = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if valStr == "on" || valStr == "1" {
                        return (nil, true)
                    } else if valStr == "off" || valStr == "0" {
                        return (nil, false)
                    }
                }
            }
            return (nil, nil)

        case .denonMarantz:
            // Examples: "MV45", "MV455" (45.5), "MUON", "MUOFF"
            let upper = token.uppercased()
            if upper == "MUON" {
                return (nil, true)
            }
            if upper == "MUOFF" {
                return (nil, false)
            }
            if upper.hasPrefix("MV"), !upper.hasPrefix("MVMAX") {
                let digits = String(upper.dropFirst(2)).prefix(while: { $0.isNumber })
                if let rawVal = Int(digits) {
                    let normalized = digits.count >= 3 ? (rawVal / 10) : rawVal
                    return (max(0, min(nativeMaxVolume, normalized)), nil)
                }
            }
            return (nil, nil)

        case .hegel:
            // Examples: "-v.45", "-m.1", "-m.0"
            if lower.hasPrefix("-v.") {
                let digits = String(lower.dropFirst(3)).filter { $0.isNumber }
                if let v = Int(digits) {
                    return (max(0, min(nativeMaxVolume, v)), nil)
                }
            }
            if lower.hasPrefix("-m.") {
                let flag = String(lower.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                if flag == "1" || flag == "on" {
                    return (nil, true)
                } else if flag == "0" || flag == "off" {
                    return (nil, false)
                }
            }
            return (nil, nil)

        case .nad:
            // Examples: "Main.Volume=45", "Main.Mute=On", "Main.Mute=Off"
            if lower.hasPrefix("main.volume=") {
                let valStr = String(lower.dropFirst("main.volume=".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let v = Int(valStr) {
                    return (max(0, min(nativeMaxVolume, v)), nil)
                }
            }
            if lower.hasPrefix("main.mute=") {
                let valStr = String(lower.dropFirst("main.mute=".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if valStr == "on" || valStr == "1" {
                    return (nil, true)
                } else if valStr == "off" || valStr == "0" {
                    return (nil, false)
                }
            }
            return (nil, nil)

        case .lyngdorf:
            // Examples: "!VOL(-350)", "!MUTEON", "!MUTEOFF"
            let upper = token.uppercased()
            if upper == "!MUTEON" || upper == "!MUTE(ON)" {
                return (nil, true)
            }
            if upper == "!MUTEOFF" || upper == "!MUTE(OFF)" {
                return (nil, false)
            }
            if upper.hasPrefix("!VOL("), upper.hasSuffix(")") {
                let inner = String(upper.dropFirst(5).dropLast(1))
                if let dbTenths = Int(inner) {
                    let mapped = 100 + (dbTenths / 8)
                    return (max(0, min(nativeMaxVolume, mapped)), nil)
                }
            }
            return (nil, nil)
        }
    }
}

/// Manages a persistent Text-over-TCP socket connection to an external amplifier/receiver
/// (Rotel, Denon/Marantz, Hegel, NAD, Lyngdorf) with continuous push listening and periodic status polling.
///
/// Mutual exclusion rule:
/// External amplifier volume control can ONLY be enabled when `PlaybackStateStore.shared.isVolumeLockedTo100` is `true`.
public final class ExternalAmpTCPController: @unchecked Sendable {
    public static let shared = ExternalAmpTCPController()

    private let kEnabledKey = "amr_ext_amp_enabled"
    private let kProfileKey = "amr_ext_amp_profile"
    private let kHostKey = "amr_ext_amp_host"
    private let kPortKey = "amr_ext_amp_port"
    private let kMaxCapKey = "amr_ext_amp_max_cap"
    private let kSoundCheckKey = "amr_ext_amp_soundcheck_enabled"
    private let kLowVolumeSmartNormKey = "amr_ext_amp_low_vol_smart_norm"
    private let kBaseVolumeKey = "amr_ext_amp_base_volume"
    private let kLastSentAmpVolumeKey = "amr_ext_amp_last_sent_volume"

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.amr.ext-amp-tcp", qos: .userInitiated)

    private var connection: NWConnection?
    private var pollTimer: DispatchSourceTimer?
    private var reconnectTimer: DispatchSourceTimer?
    private var receiveBuffer: String = ""
    private var lastUserCommandTime: Date = .distantPast
    private var lastAutoNormCommandTime: Date = .distantPast
    private var lastAutoNormTargetVolume: Int?
    private var lastAutoNormPreviousVolume: Int?
    private var hasSyncedVolumeWithAmp: Bool = false
    private var appliedVolumeOffset: Int = 0
    private var lastPersistedAmpVolume: Int = 0
    private var pendingVolumeCommand: String?

    /// Callback invoked on a background queue whenever connection state, volume, or mute state changes.
    public var onStateChanged: (() -> Void)?

    private var _isEnabled: Bool
    private var _profile: ExternalAmpProfile
    private var _host: String
    private var _port: UInt16
    private var _maxVolumeCap: Int
    private var _isSoundCheckEnabled: Bool
    private var _isLowVolumeSmartNormEnabled: Bool
    private var _currentVolume: Int = 20
    private var _baseListeningVolume: Int = 20
    private var _currentTrackKey: String = ""
    private var _currentTrackGainDb: Double?
    private var _currentTrackVolumeOffset: Int = 0
    private var _isMuted: Bool = false
    private var _isConnected: Bool = false
    private var _lastError: String?

    private init() {
        let defaults = UserDefaults.standard
        let savedProfile = ExternalAmpProfile(rawValue: defaults.string(forKey: kProfileKey) ?? "") ?? .rotel
        _profile = savedProfile
        _isEnabled = defaults.bool(forKey: kEnabledKey)
        _host = defaults.string(forKey: kHostKey) ?? ""
        let savedPort = defaults.integer(forKey: kPortKey)
        _port = savedPort > 0 && savedPort <= 65535 ? UInt16(savedPort) : savedProfile.defaultPort
        let savedCap = defaults.integer(forKey: kMaxCapKey)
        let capVal = savedCap > 0 ? max(1, min(100, savedCap)) : 80
        _maxVolumeCap = capVal
        let savedBase = defaults.integer(forKey: kBaseVolumeKey)
        let initialBase = savedBase > 0 ? max(1, min(capVal, savedBase)) : 20
        _baseListeningVolume = initialBase
        let savedSent = defaults.integer(forKey: kLastSentAmpVolumeKey)
        lastPersistedAmpVolume = savedSent > 0 ? max(0, min(capVal, savedSent)) : 0
        _currentVolume = initialBase
        _isSoundCheckEnabled = _isEnabled ? defaults.bool(forKey: kSoundCheckKey) : false
        _isLowVolumeSmartNormEnabled = defaults.object(forKey: kLowVolumeSmartNormKey) == nil
            ? true
            : defaults.bool(forKey: kLowVolumeSmartNormKey)
    }

    // MARK: - Public Configuration & State

    /// Whether external amplifier TCP control is enabled in settings.
    /// Automatically forced to `false` if 100% Bit-Perfect volume lock is OFF.
    public var isEnabled: Bool {
        get {
            lock.withLock { _isEnabled && PlaybackStateStore.shared.isVolumeLockedTo100 }
        }
        set {
            let canEnable = newValue && PlaybackStateStore.shared.isVolumeLockedTo100
            let changed: Bool = lock.withLock {
                let prev = _isEnabled
                _isEnabled = canEnable
                UserDefaults.standard.set(canEnable, forKey: kEnabledKey)
                if !canEnable && _isSoundCheckEnabled {
                    _isSoundCheckEnabled = false
                    _currentTrackVolumeOffset = 0
                    UserDefaults.standard.set(false, forKey: kSoundCheckKey)
                }
                return prev != canEnable
            }
            if changed {
                reconfigureConnection()
                notifyStateChanged()
            }
        }
    }

    /// True when 100% Volume Lock is ON, External Amp TCP control is ON, and a valid host is configured.
    public var isActive: Bool {
        lock.withLock {
            _isEnabled &&
            PlaybackStateStore.shared.isVolumeLockedTo100 &&
            !_host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public var profile: ExternalAmpProfile {
        get { lock.withLock { _profile } }
        set {
            let changed: Bool = lock.withLock {
                let prev = _profile
                _profile = newValue
                UserDefaults.standard.set(newValue.rawValue, forKey: kProfileKey)
                return prev != newValue
            }
            if changed {
                reconfigureConnection()
                notifyStateChanged()
            }
        }
    }

    public var host: String {
        get { lock.withLock { _host } }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let changed: Bool = lock.withLock {
                let prev = _host
                _host = trimmed
                UserDefaults.standard.set(trimmed, forKey: kHostKey)
                return prev != trimmed
            }
            if changed {
                reconfigureConnection()
                notifyStateChanged()
            }
        }
    }

    public var port: UInt16 {
        get { lock.withLock { _port } }
        set {
            let validPort = newValue > 0 ? newValue : profile.defaultPort
            let changed: Bool = lock.withLock {
                let prev = _port
                _port = validPort
                UserDefaults.standard.set(Int(validPort), forKey: kPortKey)
                return prev != validPort
            }
            if changed {
                reconfigureConnection()
                notifyStateChanged()
            }
        }
    }

    /// Maximum volume percentage (`1...100%`) configured in settings.
    /// The AMR volume slider operates within `0...maxVolumeCap`.
    public var maxVolumeCap: Int {
        get {
            lock.withLock {
                max(1, min(100, _maxVolumeCap))
            }
        }
        set {
            let changed: Bool = lock.withLock {
                let clamped = max(1, min(100, newValue))
                let prev = _maxVolumeCap
                _maxVolumeCap = clamped
                UserDefaults.standard.set(clamped, forKey: kMaxCapKey)
                return prev != clamped
            }
            if changed {
                notifyStateChanged()
            }
        }
    }

    public var currentVolume: Int {
        lock.withLock { _currentVolume }
    }

    public var baseListeningVolume: Int {
        lock.withLock { _baseListeningVolume }
    }

    public var currentTrackKey: String {
        lock.withLock { _currentTrackKey }
    }

    public var currentTrackGainDb: Double? {
        lock.withLock { _currentTrackGainDb }
    }

    public var currentTrackVolumeOffset: Int {
        lock.withLock { _isSoundCheckEnabled ? _currentTrackVolumeOffset : 0 }
    }

    /// Whether Bit-Perfect Hardware SoundCheck (`iTunNORM` volume normalization via the external amplifier) is enabled.
    /// Can ONLY be enabled when External Amplifier TCP Volume Control (`isEnabled`) is ON.
    public var isSoundCheckEnabled: Bool {
        get {
            lock.withLock {
                _isSoundCheckEnabled && _isEnabled && PlaybackStateStore.shared.isVolumeLockedTo100
            }
        }
        set {
            var restoreVol: Int?
            let (changed, effectiveVal): (Bool, Bool) = lock.withLock {
                let canEnable = newValue && _isEnabled && PlaybackStateStore.shared.isVolumeLockedTo100
                let prev = _isSoundCheckEnabled
                _isSoundCheckEnabled = canEnable
                UserDefaults.standard.set(canEnable, forKey: kSoundCheckKey)
                if prev != canEnable {
                    if canEnable {
                        _baseListeningVolume = _currentVolume
                        appliedVolumeOffset = 0
                        UserDefaults.standard.set(_baseListeningVolume, forKey: kBaseVolumeKey)
                    } else {
                        if appliedVolumeOffset != 0 || _currentTrackVolumeOffset != 0 {
                            restoreVol = _baseListeningVolume
                        }
                        _currentTrackVolumeOffset = 0
                        appliedVolumeOffset = 0
                        lastAutoNormTargetVolume = nil
                        lastAutoNormPreviousVolume = nil
                    }
                    return (true, canEnable)
                }
                return (false, canEnable)
            }
            if changed {
                if effectiveVal {
                    AppleSoundCheckService.shared.reapplyCurrentTrack()
                } else if let restoreVol {
                    setVolume(restoreVol)
                }
                notifyStateChanged()
            }
        }
    }

    /// Whether non-linear low-volume compensation (`< 40%`) is enabled for Hardware SoundCheck.
    /// Scales dB-to-step offsets at low listening volumes to match the steeper resistor-ladder
    /// attenuation curve of Rotel/Hi-Fi amplifiers and Fletcher-Munson equal-loudness contours.
    public var isLowVolumeSmartNormEnabled: Bool {
        get {
            lock.withLock { _isLowVolumeSmartNormEnabled }
        }
        set {
            var commandToSend: String?
            let changed: Bool = lock.withLock {
                let prev = _isLowVolumeSmartNormEnabled
                _isLowVolumeSmartNormEnabled = newValue
                UserDefaults.standard.set(newValue, forKey: kLowVolumeSmartNormKey)
                guard prev != newValue else { return false }

                let active = _isEnabled && PlaybackStateStore.shared.isVolumeLockedTo100 && !_host.isEmpty
                if _isSoundCheckEnabled {
                    let effectiveMax = max(1, min(100, _maxVolumeCap))
                    let newOffset = Self.computeVolumeOffset(
                        forGainDb: _currentTrackGainDb,
                        baseVolume: _baseListeningVolume,
                        smartLowVolume: _isLowVolumeSmartNormEnabled
                    )
                    _currentTrackVolumeOffset = newOffset
                    if active && hasSyncedVolumeWithAmp && !_isMuted && !AudioDuckingController.shared.isDucked && (_baseListeningVolume > 0 || _currentVolume > 0) {
                        let minAutoVol = _baseListeningVolume > 0 ? 1 : 0
                        let targetVol = max(minAutoVol, min(effectiveMax, _baseListeningVolume + newOffset))
                        appliedVolumeOffset = newOffset
                        if targetVol != _currentVolume {
                            lastAutoNormPreviousVolume = _currentVolume
                            lastAutoNormTargetVolume = targetVol
                            _currentVolume = targetVol
                            lastAutoNormCommandTime = Date()
                            lastPersistedAmpVolume = targetVol
                            UserDefaults.standard.set(targetVol, forKey: kLastSentAmpVolumeKey)
                            commandToSend = _profile.buildSetVolumeCommand(targetVol)
                        }
                    }
                }
                return true
            }
            if let cmd = commandToSend {
                sendRawCommand(cmd)
            }
            if changed {
                notifyStateChanged()
            }
        }
    }

    /// Converts an Apple SoundCheck `iTunNORM` gain in dB into an integer hardware volume step offset (`-12 ... +5`).
    /// When `smartLowVolume` is `true` and `baseVolume < 40`, scales the step offset along a non-linear curve to
    /// compensate for the steeper dB-per-step resistor ladder attenuation on Rotel/Hi-Fi amplifiers and human ear
    /// equal-loudness sensitivity at quiet listening levels.
    public static func computeVolumeOffset(
        forGainDb gainDb: Double?,
        baseVolume: Int = 50,
        smartLowVolume: Bool = false
    ) -> Int {
        guard let gainDb, gainDb.isFinite else { return 0 }
        if !smartLowVolume || baseVolume >= 40 {
            let rounded = Int(gainDb.rounded())
            return max(-12, min(5, rounded))
        }
        guard baseVolume > 0 else { return 0 }

        let t = Double(max(1, min(40, baseVolume))) / 40.0
        if gainDb < 0 {
            let scale = 0.15 + 0.85 * pow(t, 1.2)
            let scaled = Int((gainDb * scale).rounded())
            let maxDrop = max(1, Int((Double(baseVolume) * 0.35).rounded()))
            return max(-min(12, maxDrop), min(0, scaled))
        } else {
            let scale = 0.45 + 0.55 * t
            let scaled = Int((gainDb * scale).rounded())
            return max(0, min(5, scaled))
        }
    }

    private func resolveBaseAndOffsetForManualVolume(_ manualVol: Int, effectiveMax: Int) -> (base: Int, offset: Int) {
        guard manualVol > 0 else { return (0, _isSoundCheckEnabled ? _currentTrackVolumeOffset : 0) }
        guard _isSoundCheckEnabled else { return (max(1, min(effectiveMax, manualVol)), 0) }
        let b0 = max(1, min(effectiveMax, manualVol - appliedVolumeOffset))
        let off1 = Self.computeVolumeOffset(
            forGainDb: _currentTrackGainDb,
            baseVolume: b0,
            smartLowVolume: _isLowVolumeSmartNormEnabled
        )
        let b1 = max(1, min(effectiveMax, manualVol - off1))
        let off2 = Self.computeVolumeOffset(
            forGainDb: _currentTrackGainDb,
            baseVolume: b1,
            smartLowVolume: _isLowVolumeSmartNormEnabled
        )
        let finalBase = max(1, min(effectiveMax, manualVol - off2))
        return (finalBase, off2)
    }

    public var isMuted: Bool {
        lock.withLock { _isMuted }
    }

    public var isConnected: Bool {
        lock.withLock { _isConnected }
    }

    public var lastError: String? {
        lock.withLock { _lastError }
    }

    /// Updates all connection parameters atomically and reconnects if active.
    public func updateConfiguration(
        profile: ExternalAmpProfile,
        host: String,
        port: UInt16,
        maxVolumeCap: Int,
        isEnabled: Bool? = nil
    ) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let validPort = port > 0 ? port : profile.defaultPort
        let clampedCap = max(1, min(100, maxVolumeCap))

        lock.withLock {
            let endpointChanged = (_profile != profile || _host != trimmedHost || _port != validPort)
            _profile = profile
            _host = trimmedHost
            _port = validPort
            _maxVolumeCap = clampedCap
            lastUserCommandTime = .distantPast
            lastAutoNormCommandTime = .distantPast
            lastAutoNormTargetVolume = nil
            lastAutoNormPreviousVolume = nil
            pendingVolumeCommand = nil
            if endpointChanged {
                hasSyncedVolumeWithAmp = false
                appliedVolumeOffset = 0
            }
            if let isEnabled {
                _isEnabled = isEnabled && PlaybackStateStore.shared.isVolumeLockedTo100
                UserDefaults.standard.set(_isEnabled, forKey: kEnabledKey)
                if !_isEnabled && _isSoundCheckEnabled {
                    _isSoundCheckEnabled = false
                    _currentTrackVolumeOffset = 0
                    appliedVolumeOffset = 0
                    UserDefaults.standard.set(false, forKey: kSoundCheckKey)
                }
            }
            UserDefaults.standard.set(profile.rawValue, forKey: kProfileKey)
            UserDefaults.standard.set(trimmedHost, forKey: kHostKey)
            UserDefaults.standard.set(Int(validPort), forKey: kPortKey)
            UserDefaults.standard.set(clampedCap, forKey: kMaxCapKey)
        }
        reconfigureConnection()
        notifyStateChanged()
    }

    /// Enforces mutual exclusion: when 100% Volume Lock is turned OFF, External Amp TCP control is forced OFF.
    public func enforceVolumeLockConstraint(isVolumeLockedTo100: Bool) {
        if !isVolumeLockedTo100 {
            let wasEnabled: Bool = lock.withLock {
                let prev = _isEnabled
                _isEnabled = false
                _isSoundCheckEnabled = false
                _currentTrackVolumeOffset = 0
                appliedVolumeOffset = 0
                pendingVolumeCommand = nil
                lastAutoNormTargetVolume = nil
                lastAutoNormPreviousVolume = nil
                UserDefaults.standard.set(false, forKey: kEnabledKey)
                UserDefaults.standard.set(false, forKey: kSoundCheckKey)
                return prev
            }
            if wasEnabled {
                NSLog("[ExternalAmpTCP] Volume Lock 100%% disabled -> automatically disabling External Amp TCP control.")
                reconfigureConnection()
                notifyStateChanged()
            }
        }
    }

    /// Starts the TCP connection if `isActive` is true.
    public func startIfActive() {
        reconfigureConnection()
    }

    // MARK: - Volume & Mute Commands

    /// Sets the amplifier hardware volume (clamped to `0...maxVolumeCap`).
    /// Also updates `baseListeningVolume` relative to the current track's SoundCheck offset so manual volume changes
    /// never conflict with per-track normalization (unless `preserveBaseVolume` is `true`, e.g. during temporary audio ducking).
    public func setVolume(_ newVolume: Int, preserveBaseVolume: Bool = false) {
        let (active, prof, cap) = lock.withLock {
            (_isEnabled && PlaybackStateStore.shared.isVolumeLockedTo100 && !_host.isEmpty, _profile, _maxVolumeCap)
        }
        guard active else { return }

        let effectiveMax = max(1, min(100, cap))
        let clamped = max(0, min(effectiveMax, newVolume))

        let stateChanged: Bool = lock.withLock {
            let prevVol = _currentVolume
            let prevMute = _isMuted
            _currentVolume = clamped
            hasSyncedVolumeWithAmp = true
            if preserveBaseVolume {
                lastAutoNormPreviousVolume = prevVol
                lastAutoNormTargetVolume = clamped
                lastAutoNormCommandTime = Date()
            } else {
                lastAutoNormTargetVolume = nil
                lastAutoNormPreviousVolume = nil
                let resolved = resolveBaseAndOffsetForManualVolume(clamped, effectiveMax: effectiveMax)
                _baseListeningVolume = resolved.base
                if _isSoundCheckEnabled {
                    _currentTrackVolumeOffset = resolved.offset
                    appliedVolumeOffset = resolved.offset
                } else {
                    appliedVolumeOffset = 0
                }
                lastPersistedAmpVolume = clamped
                UserDefaults.standard.set(_baseListeningVolume, forKey: kBaseVolumeKey)
                UserDefaults.standard.set(clamped, forKey: kLastSentAmpVolumeKey)
                lastUserCommandTime = Date()
            }
            if clamped > 0 {
                _isMuted = false
            }
            return prevVol != clamped || (clamped > 0 && prevMute)
        }

        let cmd = prof.buildSetVolumeCommand(clamped)
        sendRawCommand(cmd)

        if stateChanged {
            notifyStateChanged()
        }
    }

    /// Applies Apple's `iTunNORM` SoundCheck gain (in dB) for the currently playing track by offsetting
    /// the amplifier hardware volume relative to `baseListeningVolume` without altering CoreAudio's 100% Bit-Perfect stream.
    public func applyTrackSoundCheck(trackKey: String, gainDb: Double?) {
        var commandToSend: String?
        let shouldNotify: Bool = lock.withLock {
            let active = _isEnabled && PlaybackStateStore.shared.isVolumeLockedTo100 && !_host.isEmpty
            let effectiveMax = max(1, min(100, _maxVolumeCap))
            let newOffset = _isSoundCheckEnabled
                ? Self.computeVolumeOffset(
                    forGainDb: gainDb,
                    baseVolume: _baseListeningVolume,
                    smartLowVolume: _isLowVolumeSmartNormEnabled
                )
                : 0
            let prevKey = _currentTrackKey
            let prevGain = _currentTrackGainDb
            let prevOffset = _currentTrackVolumeOffset

            _currentTrackKey = trackKey
            _currentTrackGainDb = gainDb
            _currentTrackVolumeOffset = newOffset

            var volChanged = false
            if active && _isSoundCheckEnabled && hasSyncedVolumeWithAmp && !_isMuted && !AudioDuckingController.shared.isDucked && (_baseListeningVolume > 0 || _currentVolume > 0) {
                let minAutoVol = _baseListeningVolume > 0 ? 1 : 0
                let targetVol = max(minAutoVol, min(effectiveMax, _baseListeningVolume + newOffset))
                appliedVolumeOffset = newOffset
                if targetVol != _currentVolume {
                    lastAutoNormPreviousVolume = _currentVolume
                    lastAutoNormTargetVolume = targetVol
                    _currentVolume = targetVol
                    lastAutoNormCommandTime = Date()
                    lastPersistedAmpVolume = targetVol
                    UserDefaults.standard.set(targetVol, forKey: kLastSentAmpVolumeKey)
                    commandToSend = _profile.buildSetVolumeCommand(targetVol)
                    volChanged = true
                    NSLog("[ExternalAmpTCP] SoundCheck '%@': gain=%+.2f dB, offset=%+d, base=%d -> ampVol=%d",
                          trackKey, gainDb ?? 0.0, newOffset, _baseListeningVolume, targetVol)
                } else if prevKey != trackKey && !trackKey.isEmpty {
                    NSLog("[ExternalAmpTCP] SoundCheck '%@': gain=%+.2f dB, offset=%+d, base=%d -> ampVol=%d (unchanged)",
                          trackKey, gainDb ?? 0.0, newOffset, _baseListeningVolume, targetVol)
                }
            }

            return volChanged || prevKey != trackKey || prevGain != gainDb || prevOffset != newOffset
        }

        if let cmd = commandToSend {
            sendRawCommand(cmd)
        }
        if shouldNotify {
            notifyStateChanged()
        }
    }

    /// Steps the amplifier volume up or down by `delta`.
    public func stepVolume(by delta: Int) {
        let current = currentVolume
        setVolume(current + delta)
    }

    /// Toggles or sets hardware mute on the amplifier.
    public func setMuted(_ muted: Bool? = nil) {
        var extraVolCommand: String?
        let (active, prof, targetMute): (Bool, ExternalAmpProfile, Bool) = lock.withLock {
            let isAct = _isEnabled && PlaybackStateStore.shared.isVolumeLockedTo100 && !_host.isEmpty
            let nextMute = muted ?? !_isMuted
            if isAct {
                _isMuted = nextMute
                lastUserCommandTime = Date()
                if !nextMute && _isSoundCheckEnabled && hasSyncedVolumeWithAmp && (_baseListeningVolume > 0 || _currentVolume > 0) && appliedVolumeOffset != _currentTrackVolumeOffset {
                    let effectiveMax = max(1, min(100, _maxVolumeCap))
                    let minAutoVol = _baseListeningVolume > 0 ? 1 : 0
                    let targetVol = max(minAutoVol, min(effectiveMax, _baseListeningVolume + _currentTrackVolumeOffset))
                    appliedVolumeOffset = _currentTrackVolumeOffset
                    if targetVol != _currentVolume {
                        lastAutoNormPreviousVolume = _currentVolume
                        lastAutoNormTargetVolume = targetVol
                        _currentVolume = targetVol
                        lastAutoNormCommandTime = Date()
                        lastPersistedAmpVolume = targetVol
                        UserDefaults.standard.set(targetVol, forKey: kLastSentAmpVolumeKey)
                        extraVolCommand = _profile.buildSetVolumeCommand(targetVol)
                    }
                }
            }
            return (isAct, _profile, nextMute)
        }
        guard active else { return }

        let cmd = prof.buildMuteCommand(muted: targetMute)
        sendRawCommand(cmd)
        if let extraVolCommand {
            sendRawCommand(extraVolCommand)
        }
        notifyStateChanged()
    }

    /// Requests an immediate status update from the amplifier.
    public func requestStatusPoll() {
        let (active, prof) = lock.withLock {
            (_isEnabled && PlaybackStateStore.shared.isVolumeLockedTo100 && !_host.isEmpty, _profile)
        }
        guard active else { return }
        sendRawCommand(prof.buildQueryStatusCommand())
    }

    /// Probes the TCP connection to the amplifier, sends a status query command, and reports the result on the main thread.
    public func testConnection(
        profile: ExternalAmpProfile,
        host: String,
        port: UInt16,
        completion: @escaping @Sendable (_ success: Bool, _ message: String) -> Void
    ) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            DispatchQueue.main.async {
                completion(false, "🟠 Укажите IP-адрес усилителя для проверки соединения")
            }
            return
        }
        let validPort = port > 0 ? port : profile.defaultPort
        guard let nwPort = NWEndpoint.Port(rawValue: validPort) else {
            DispatchQueue.main.async {
                completion(false, "❌ Некорректный TCP-порт: \(validPort)")
            }
            return
        }

        let probeQueue = DispatchQueue(label: "com.amr.ext-amp-probe", qos: .userInitiated)
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = 3
        tcpOptions.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        let probeConn = NWConnection(host: NWEndpoint.Host(trimmedHost), port: nwPort, using: params)

        final class ProbeState: @unchecked Sendable {
            var completed = false
            var tcpConnected = false
            var responseBuffer = ""
            var detectedVolume: Int?
            var detectedMute: Bool?
        }
        let state = ProbeState()

        let finish: @Sendable (Bool, String) -> Void = { [weak self] ok, msg in
            guard !state.completed else { return }
            state.completed = true
            probeConn.stateUpdateHandler = nil
            probeConn.cancel()
            if ok, let self {
                self.lock.withLock {
                    if let v = state.detectedVolume {
                        if v == 0 && self._baseListeningVolume > 0 {
                            NSLog("[ExternalAmpTCP] testConnection zero-jump guard: ignoring detectedVolume=0 while base=%d", self._baseListeningVolume)
                        } else {
                            self.hasSyncedVolumeWithAmp = true
                            self._currentVolume = v
                            let effectiveMax = max(1, min(100, self._maxVolumeCap))
                            if self._isSoundCheckEnabled && self.lastPersistedAmpVolume > 0 && v == self.lastPersistedAmpVolume {
                                self.appliedVolumeOffset = v - self._baseListeningVolume
                            } else {
                                let resolved = self.resolveBaseAndOffsetForManualVolume(v, effectiveMax: effectiveMax)
                                self._baseListeningVolume = resolved.base
                                if self._isSoundCheckEnabled {
                                    self._currentTrackVolumeOffset = resolved.offset
                                    self.appliedVolumeOffset = resolved.offset
                                }
                            }
                        }
                    }
                    if let m = state.detectedMute {
                        self._isMuted = m
                    }
                    self._lastError = nil
                }
                self.reconfigureConnection()
                self.notifyStateChanged()
            }
            DispatchQueue.main.async {
                completion(ok, msg)
            }
        }

        probeQueue.asyncAfter(deadline: .now() + 3.2) {
            guard !state.completed else { return }
            if state.tcpConnected {
                finish(true, "✅ TCP-сокет доступен: \(profile.displayName) (\(trimmedHost):\(validPort)) подключен")
            } else {
                finish(false, "❌ Таймаут подключения к \(profile.displayName) (\(trimmedHost):\(validPort)) — проверьте IP, порт и сеть")
            }
        }

        probeConn.stateUpdateHandler = { connState in
            switch connState {
            case .ready:
                state.tcpConnected = true
                let query = profile.buildQueryStatusCommand()
                if let data = query.data(using: .utf8) {
                    probeConn.send(content: data, completion: .contentProcessed { _ in })
                }
                probeConn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
                    guard !state.completed else { return }
                    if let data, !data.isEmpty,
                       let str = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
                        state.responseBuffer.append(str)
                        let delimiters: Set<Character> = profile == .rotel
                            ? ["$", "!", "\r", "\n"]
                            : ["\r", "\n", "$"]
                        let tokens = state.responseBuffer.split(whereSeparator: { delimiters.contains($0) }).map(String.init)
                        for tok in tokens {
                            let parsed = profile.parseToken(tok)
                            if let v = parsed.volume { state.detectedVolume = v }
                            if let m = parsed.muted { state.detectedMute = m }
                        }
                    }
                    if let vol = state.detectedVolume {
                        let muteStr = (state.detectedMute == true) ? " • MUTE" : ""
                        finish(true, "✅ Соединение установлено: \(profile.displayName) (\(trimmedHost):\(validPort)) ответил • Громкость: \(vol)%\(muteStr)")
                    } else {
                        finish(true, "✅ Соединение установлено: \(profile.displayName) (\(trimmedHost):\(validPort)) доступен по TCP")
                    }
                }
                probeQueue.asyncAfter(deadline: .now() + 1.1) {
                    guard !state.completed else { return }
                    if let vol = state.detectedVolume {
                        let muteStr = (state.detectedMute == true) ? " • MUTE" : ""
                        finish(true, "✅ Соединение установлено: \(profile.displayName) (\(trimmedHost):\(validPort)) ответил • Громкость: \(vol)%\(muteStr)")
                    } else {
                        finish(true, "✅ TCP-сокет доступен: \(profile.displayName) (\(trimmedHost):\(validPort)) подключен")
                    }
                }

            case .failed(let error):
                finish(false, "❌ Ошибка подключения к \(trimmedHost):\(validPort): \(error.localizedDescription)")

            default:
                break
            }
        }

        probeConn.start(queue: probeQueue)
    }

    // MARK: - Internal Connection Lifecycle

    private func reconfigureConnection() {
        queue.async { [weak self] in
            self?.teardownConnectionOnQueue()
            guard let self else { return }
            let (shouldConnect, host, port) = self.lock.withLock {
                let active = self._isEnabled &&
                    PlaybackStateStore.shared.isVolumeLockedTo100 &&
                    !self._host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                return (active, self._host, self._port)
            }
            if shouldConnect {
                self.connectOnQueue(host: host, port: port)
            }
        }
    }

    private func teardownConnectionOnQueue() {
        pollTimer?.cancel()
        pollTimer = nil
        reconnectTimer?.cancel()
        reconnectTimer = nil
        receiveBuffer.removeAll(keepingCapacity: false)

        if let conn = connection {
            conn.stateUpdateHandler = nil
            conn.cancel()
            connection = nil
        }

        let wasConnected = lock.withLock {
            let prev = _isConnected
            _isConnected = false
            return prev
        }
        if wasConnected {
            notifyStateChanged()
        }
    }

    private func connectOnQueue(host: String, port: UInt16) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            lock.withLock { _lastError = "Некорректный порт \(port)" }
            notifyStateChanged()
            return
        }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 15
        tcpOptions.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                let (prof, pendingCmd) = self.lock.withLock { () -> (ExternalAmpProfile, String?) in
                    self._isConnected = true
                    self._lastError = nil
                    let cmd = self.pendingVolumeCommand
                    self.pendingVolumeCommand = nil
                    return (self._profile, cmd)
                }
                NSLog("[ExternalAmpTCP] Connected to %@ at %@:%u", prof.displayName, host, port)
                self.receiveBuffer.removeAll(keepingCapacity: false)
                self.startReceiveLoopOnQueue(for: conn)
                self.startPollTimerOnQueue()
                if let pendingCmd, !pendingCmd.isEmpty {
                    self.sendRawCommandOnQueue(pendingCmd, on: conn)
                }
                // Query initial volume & mute immediately upon connection
                self.sendRawCommandOnQueue(prof.buildQueryStatusCommand(), on: conn)
                self.notifyStateChanged()

            case .failed(let error):
                NSLog("[ExternalAmpTCP] Connection failed (%@:%u): %@", host, port, error.localizedDescription)
                self.lock.withLock {
                    self._isConnected = false
                    self._lastError = error.localizedDescription
                }
                self.notifyStateChanged()
                self.scheduleReconnectOnQueue()

            case .waiting(let error):
                self.lock.withLock {
                    self._isConnected = false
                    self._lastError = error.localizedDescription
                }
                self.notifyStateChanged()

            case .cancelled:
                self.lock.withLock {
                    self._isConnected = false
                }
                self.notifyStateChanged()

            default:
                break
            }
        }

        conn.start(queue: queue)
    }

    private func startReceiveLoopOnQueue(for conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            guard self.connection === conn else { return }

            if let data, !data.isEmpty, let chunk = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
                self.handleIncomingChunkOnQueue(chunk)
            }

            if let error {
                NSLog("[ExternalAmpTCP] Receive error: %@", error.localizedDescription)
                self.lock.withLock {
                    self._isConnected = false
                    self._lastError = error.localizedDescription
                }
                self.notifyStateChanged()
                self.scheduleReconnectOnQueue()
                return
            }

            if isComplete {
                NSLog("[ExternalAmpTCP] Remote peer closed TCP connection.")
                self.lock.withLock {
                    self._isConnected = false
                }
                self.notifyStateChanged()
                self.scheduleReconnectOnQueue()
                return
            }

            self.startReceiveLoopOnQueue(for: conn)
        }
    }

    /// Processes incoming stream chunks, splitting on `$`, `!` (for Rotel), `\r`, or `\n`.
    /// Exposed internally for unit testing.
    internal func processIncomingChunkForTesting(_ chunk: String) {
        queue.sync {
            handleIncomingChunkOnQueue(chunk)
        }
    }

    private func handleIncomingChunkOnQueue(_ chunk: String) {
        receiveBuffer.append(chunk)

        let prof = lock.withLock { _profile }
        var stateUpdated = false

        // Delimiters: `$` (Rotel V1/V2 responses), `\r`, `\n`, and `;`
        // Note: Lyngdorf commands/responses start with `!` (e.g. `!VOL(-350)\r`), whereas Rotel sometimes uses `!` as terminator (`volume=45!`).
        let delimiters: Set<Character> = prof == .rotel
            ? ["$", "!", "\r", "\n"]
            : ["\r", "\n", "$"]

        while let idx = receiveBuffer.firstIndex(where: { delimiters.contains($0) }) {
            let token = String(receiveBuffer[..<idx])
            let afterIdx = receiveBuffer.index(after: idx)
            receiveBuffer.removeSubrange(..<afterIdx)

            let parsed = prof.parseToken(token)
            if parsed.volume != nil || parsed.muted != nil {
                var deferredAutoNormCmd: String?
                let changed = lock.withLock { () -> Bool in
                    let sinceUserCmd = Date().timeIntervalSince(self.lastUserCommandTime)
                    let sinceAutoCmd = Date().timeIntervalSince(self.lastAutoNormCommandTime)
                    var modified = false
                    if let newVol = parsed.volume {
                        let effectiveMax = max(1, min(100, self._maxVolumeCap))
                        if !self.hasSyncedVolumeWithAmp {
                            if newVol == 0 && self._baseListeningVolume > 0 {
                                // Zero-jump guard on initial connect: amplifier in Standby / relay mute reports volume=00; preserve saved _baseListeningVolume
                                NSLog("[ExternalAmpTCP] Zero-jump guard: ignoring initial volume=0 report while saved base=%d", self._baseListeningVolume)
                            } else {
                                self.hasSyncedVolumeWithAmp = true
                                self._currentVolume = newVol
                                if self._isSoundCheckEnabled && self.lastPersistedAmpVolume > 0 && newVol == self.lastPersistedAmpVolume {
                                    // Amplifier is still at the SoundCheck-adjusted volume from before AMR restarted; keep saved _baseListeningVolume intact
                                    self.appliedVolumeOffset = newVol - self._baseListeningVolume
                                } else {
                                    let offsetToSubtract = self._isSoundCheckEnabled ? self.appliedVolumeOffset : 0
                                    self._baseListeningVolume = max(0, min(effectiveMax, newVol - offsetToSubtract))
                                    UserDefaults.standard.set(self._baseListeningVolume, forKey: self.kBaseVolumeKey)
                                }
                                if self._isSoundCheckEnabled {
                                    self._currentTrackVolumeOffset = Self.computeVolumeOffset(
                                        forGainDb: self._currentTrackGainDb,
                                        baseVolume: self._baseListeningVolume,
                                        smartLowVolume: self._isLowVolumeSmartNormEnabled
                                    )
                                }
                                if self._isSoundCheckEnabled && !self._currentTrackKey.isEmpty && !self._isMuted && (self._baseListeningVolume > 0 || self._currentVolume > 0) && self.appliedVolumeOffset != self._currentTrackVolumeOffset {
                                    let minAutoVol = self._baseListeningVolume > 0 ? 1 : 0
                                    let targetVol = max(minAutoVol, min(effectiveMax, self._baseListeningVolume + self._currentTrackVolumeOffset))
                                    self.appliedVolumeOffset = self._currentTrackVolumeOffset
                                    if targetVol != self._currentVolume {
                                        self.lastAutoNormPreviousVolume = self._currentVolume
                                        self.lastAutoNormTargetVolume = targetVol
                                        self._currentVolume = targetVol
                                        self.lastAutoNormCommandTime = Date()
                                        self.lastPersistedAmpVolume = targetVol
                                        UserDefaults.standard.set(targetVol, forKey: self.kLastSentAmpVolumeKey)
                                        deferredAutoNormCmd = self._profile.buildSetVolumeCommand(targetVol)
                                        NSLog("[ExternalAmpTCP] Initial sync SoundCheck '%@': gain=%+.2f dB, offset=%+d, base=%d -> ampVol=%d",
                                              self._currentTrackKey, self._currentTrackGainDb ?? 0.0, self._currentTrackVolumeOffset, self._baseListeningVolume, targetVol)
                                    }
                                }
                                modified = true
                            }
                        } else if let target = self.lastAutoNormTargetVolume, sinceAutoCmd < 2.5, newVol == target {
                            // Confirmation of our automatic SoundCheck volume command: never alter _baseListeningVolume
                            self.lastAutoNormTargetVolume = nil
                            self.lastAutoNormPreviousVolume = nil
                            self.lastUserCommandTime = .distantPast
                            if self._currentVolume != newVol {
                                self._currentVolume = newVol
                                modified = true
                            }
                        } else if self.lastAutoNormTargetVolume != nil, let prev = self.lastAutoNormPreviousVolume, sinceAutoCmd < 0.85, newVol == prev {
                            // Ignore stale in-flight poll echo of the previous track's volume arriving right before the amp processes our auto-norm step
                        } else if newVol == 0 && self._currentVolume >= 6 {
                            // Zero-jump guard: physical rotary encoder / IR remote steps through low values (5,4,3,2,1,0).
                            // An instantaneous jump from >= 6 straight to 0 is a standby / input-relay transient; preserve _currentVolume and _baseListeningVolume.
                            NSLog("[ExternalAmpTCP] Zero-jump guard: ignoring sudden uncommanded drop from %d to 0", self._currentVolume)
                        } else if sinceUserCmd > 0.45 && self._currentVolume != newVol {
                            // Genuine physical knob / IR remote adjustment on the amplifier itself
                            self._currentVolume = newVol
                            self.lastAutoNormTargetVolume = nil
                            self.lastAutoNormPreviousVolume = nil
                            let resolved = self.resolveBaseAndOffsetForManualVolume(newVol, effectiveMax: effectiveMax)
                            self._baseListeningVolume = resolved.base
                            if self._isSoundCheckEnabled {
                                self._currentTrackVolumeOffset = resolved.offset
                                self.appliedVolumeOffset = resolved.offset
                            } else {
                                self.appliedVolumeOffset = 0
                            }
                            self.lastPersistedAmpVolume = newVol
                            UserDefaults.standard.set(self._baseListeningVolume, forKey: self.kBaseVolumeKey)
                            UserDefaults.standard.set(newVol, forKey: self.kLastSentAmpVolumeKey)
                            NSLog("[ExternalAmpTCP] Physical knob/remote volume=%d (offset=%+d) -> new base=%d",
                                  newVol, resolved.offset, self._baseListeningVolume)
                            modified = true
                        }
                    }
                    if let newMute = parsed.muted {
                        if sinceUserCmd > 0.35 || newMute == self._isMuted {
                            if self._isMuted != newMute {
                                self._isMuted = newMute
                                modified = true
                            }
                        }
                    }
                    return modified
                }
                if let cmd = deferredAutoNormCmd {
                    sendRawCommand(cmd)
                }
                if changed {
                    stateUpdated = true
                }
            }
        }

        // Prevent unbounded buffer growth if an unrecognized stream lacks delimiters
        if receiveBuffer.count > 4096 {
            receiveBuffer.removeAll(keepingCapacity: false)
        }

        if stateUpdated {
            notifyStateChanged()
        }
    }

    private func startPollTimerOnQueue() {
        pollTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 4.0, repeating: 4.0, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            guard let self, let conn = self.connection else { return }
            let (connected, prof) = self.lock.withLock { (self._isConnected, self._profile) }
            guard connected else { return }
            self.sendRawCommandOnQueue(prof.buildQueryStatusCommand(), on: conn)
        }
        pollTimer = timer
        timer.resume()
    }

    private func scheduleReconnectOnQueue() {
        pollTimer?.cancel()
        pollTimer = nil
        if let conn = connection {
            conn.stateUpdateHandler = nil
            conn.cancel()
            connection = nil
        }

        reconnectTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 3.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.reconnectTimer = nil
            let (shouldConnect, host, port) = self.lock.withLock {
                let active = self._isEnabled &&
                    PlaybackStateStore.shared.isVolumeLockedTo100 &&
                    !self._host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                return (active, self._host, self._port)
            }
            if shouldConnect {
                self.connectOnQueue(host: host, port: port)
            }
        }
        reconnectTimer = timer
        timer.resume()
    }

    internal func resetSyncStateForTesting(baseVolume: Int = 20, lastPersistedAmpVolume: Int = 0) {
        lock.withLock {
            let effectiveMax = max(1, min(100, _maxVolumeCap))
            let clampedBase = max(1, min(effectiveMax, baseVolume))
            _baseListeningVolume = clampedBase
            _currentVolume = clampedBase
            _currentTrackKey = ""
            _currentTrackGainDb = nil
            _currentTrackVolumeOffset = 0
            appliedVolumeOffset = 0
            hasSyncedVolumeWithAmp = false
            self.lastPersistedAmpVolume = lastPersistedAmpVolume
            pendingVolumeCommand = nil
            lastAutoNormTargetVolume = nil
            lastAutoNormPreviousVolume = nil
            lastUserCommandTime = .distantPast
            lastAutoNormCommandTime = .distantPast
        }
    }

    private func sendRawCommand(_ command: String) {
        queue.async { [weak self] in
            guard let self else { return }
            if let conn = self.connection, self.lock.withLock({ self._isConnected }) {
                self.sendRawCommandOnQueue(command, on: conn)
            } else {
                // Queue latest volume/mute command and attempt immediate connection if not connected yet
                let (shouldConnect, host, port) = self.lock.withLock {
                    self.pendingVolumeCommand = command
                    let active = self._isEnabled &&
                        PlaybackStateStore.shared.isVolumeLockedTo100 &&
                        !self._host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    return (active, self._host, self._port)
                }
                if shouldConnect && self.connection == nil {
                    self.connectOnQueue(host: host, port: port)
                }
            }
        }
    }

    private func sendRawCommandOnQueue(_ command: String, on conn: NWConnection) {
        guard let data = command.data(using: .utf8) else { return }
        conn.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                NSLog("[ExternalAmpTCP] Send error: %@", error.localizedDescription)
                self?.queue.async {
                    self?.lock.withLock {
                        self?._isConnected = false
                        self?._lastError = error.localizedDescription
                    }
                    self?.notifyStateChanged()
                    self?.scheduleReconnectOnQueue()
                }
            }
        })
    }

    private func notifyStateChanged() {
        PlaybackStateStore.shared.invalidateStatusCache()
        onStateChanged?()
    }
}
