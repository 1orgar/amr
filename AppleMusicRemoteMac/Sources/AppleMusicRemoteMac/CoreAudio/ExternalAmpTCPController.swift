//
//  ExternalAmpTCPController.swift
//  AppleMusicRemoteMac
//
//  Persistent Text-over-TCP Amplifier Controller: Core State, Configuration & Mutual Exclusion
//

import Foundation
import Network
import os

/// Manages a persistent Text-over-TCP socket connection to an external amplifier/receiver
/// (Rotel, Denon/Marantz, Hegel, NAD, Lyngdorf) with continuous push listening and periodic status polling.
///
/// Mutual exclusion rule:
/// External amplifier volume control can ONLY be enabled when `PlaybackStateStore.shared.isVolumeLockedTo100` is `true`.
public final class ExternalAmpTCPController: @unchecked Sendable {
    public static let shared = ExternalAmpTCPController()

    internal let kEnabledKey = "amr_ext_amp_enabled"
    internal let kProfileKey = "amr_ext_amp_profile"
    internal let kHostKey = "amr_ext_amp_host"
    internal let kPortKey = "amr_ext_amp_port"
    internal let kMaxCapKey = "amr_ext_amp_max_cap"
    internal let kSoundCheckKey = "amr_ext_amp_soundcheck_enabled"
    internal let kLowVolumeSmartNormKey = "amr_ext_amp_low_vol_smart_norm"
    internal let kCompressionCompKey = "amr_ext_amp_compression_comp"
    internal let kBaseVolumeKey = "amr_ext_amp_base_volume"
    internal let kLastSentAmpVolumeKey = "amr_ext_amp_last_sent_volume"
    internal let kNormalizationPolicyUpdatedAtKey = "amr.cloud.norm_policy_updated_at.v1"

    // Strict lock ordering: NEVER acquire `PlaybackStateStore` or `AudioDuckingController` locks while `lock` is held.
    internal let lock = NSLock()
    private let callbackLock = NSLock()
    internal let queue = DispatchQueue(label: "com.amr.ext-amp-tcp", qos: .userInitiated)

    internal var connection: NWConnection?
    internal var pollTimer: DispatchSourceTimer?
    internal var reconnectTimer: DispatchSourceTimer?
    internal var receiveBuffer: String = ""
    internal var lastUserCommandTime: Date = .distantPast
    internal var lastAutoNormCommandTime: Date = .distantPast
    internal var lastAutoNormTargetVolume: Int?
    internal var lastAutoNormPreviousVolume: Int?
    internal var hasSyncedVolumeWithAmp: Bool = false
    internal var appliedVolumeOffset: Int = 0
    internal var lastPersistedAmpVolume: Int = 0

    // Separate pending queues so mute/unmute commands issued while disconnected are NEVER lost when volume updates arrive (and vice versa).
    internal var pendingVolumeCommand: Double?
    internal var pendingMuteCommand: Bool?

    private var _onStateChanged: (() -> Void)?

    /// Callback invoked on a background queue whenever connection state, volume, or mute state changes (thread-safe).
    public var onStateChanged: (() -> Void)? {
        get { callbackLock.withLock { _onStateChanged } }
        set { callbackLock.withLock { _onStateChanged = newValue } }
    }

    /// Lock-free / spinlock-safe cached flag for CoreAudio real-time IOProc thread inspection.
    private var rtFlagSpinLock = os_unfair_lock_s()
    private var _rtIsSoundCheckEnabledFlag: Bool = false

    public var rtIsSoundCheckEnabledFlag: Bool {
        get {
            os_unfair_lock_lock(&rtFlagSpinLock)
            let v = _rtIsSoundCheckEnabledFlag
            os_unfair_lock_unlock(&rtFlagSpinLock)
            return v
        }
        set {
            os_unfair_lock_lock(&rtFlagSpinLock)
            _rtIsSoundCheckEnabledFlag = newValue
            os_unfair_lock_unlock(&rtFlagSpinLock)
        }
    }

    internal var _cachedVolumeLockedTo100: Bool = true
    internal var _isEnabled: Bool {
        didSet { syncRTSoundCheckFlagLocked() }
    }
    internal var _profile: ExternalAmpProfile
    internal var _host: String
    internal var _port: UInt16
    internal var _maxVolumeCap: Int
    internal var _persistedSoundCheckPreference: Bool
    internal var _isSoundCheckEnabled: Bool {
        didSet { syncRTSoundCheckFlagLocked() }
    }
    internal var _isLowVolumeSmartNormEnabled: Bool
    internal var _isCompressionCompensationEnabled: Bool
    internal var _normalizationPolicyUpdatedAt: TimeInterval
    internal var _currentVolume: Int = 20
    internal var _baseListeningVolume: Int = 20
    internal var _currentTrackKey: String = ""
    internal var _currentTrackGainDb: Double?
    internal var _currentTrackCrestDb: Double?
    internal var _isDigitalSoundCheckAlreadyActive: Bool = false
    internal var _currentTrackVolumeOffset: Int = 0
    internal var _isMuted: Bool = false
    internal var _isConnected: Bool = false
    internal var _lastError: String?

    @inline(__always)
    internal func syncRTSoundCheckFlagLocked() {
        let enabledFlag = _isSoundCheckEnabled && _isEnabled && _cachedVolumeLockedTo100
        os_unfair_lock_lock(&rtFlagSpinLock)
        _rtIsSoundCheckEnabledFlag = enabledFlag
        os_unfair_lock_unlock(&rtFlagSpinLock)
    }

    private init() {
        let defaults = AppStorageProvider.shared
        let lockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100
        self._cachedVolumeLockedTo100 = lockedTo100
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
        let savedSoundCheckPref = defaults.bool(forKey: kSoundCheckKey)
        _persistedSoundCheckPreference = savedSoundCheckPref
        _isSoundCheckEnabled = _isEnabled ? savedSoundCheckPref : false
        _rtIsSoundCheckEnabledFlag = _isSoundCheckEnabled && _isEnabled && lockedTo100
        _isLowVolumeSmartNormEnabled = defaults.object(forKey: kLowVolumeSmartNormKey) == nil
            ? true
            : defaults.bool(forKey: kLowVolumeSmartNormKey)
        _isCompressionCompensationEnabled = defaults.object(forKey: kCompressionCompKey) == nil
            ? true
            : defaults.bool(forKey: kCompressionCompKey)
        _normalizationPolicyUpdatedAt = defaults.double(forKey: kNormalizationPolicyUpdatedAtKey)
    }

    // MARK: - Public Configuration & State

    /// Whether external amplifier TCP control is enabled in settings.
    /// Automatically forced to `false` if 100% Bit-Perfect volume lock is OFF.
    public var isEnabled: Bool {
        get {
            let lockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100
            return lock.withLock {
                _cachedVolumeLockedTo100 = lockedTo100
                syncRTSoundCheckFlagLocked()
                return _isEnabled && lockedTo100
            }
        }
        set {
            let lockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100
            let canEnable = newValue && lockedTo100
            let changed: Bool = lock.withLock {
                _cachedVolumeLockedTo100 = lockedTo100
                let prev = _isEnabled
                _isEnabled = canEnable
                AppStorageProvider.shared.set(canEnable, forKey: kEnabledKey)
                if !canEnable && _isSoundCheckEnabled {
                    _isSoundCheckEnabled = false
                    _persistedSoundCheckPreference = false
                    _currentTrackVolumeOffset = 0
                    AppStorageProvider.shared.set(false, forKey: kSoundCheckKey)
                }
                if !canEnable {
                    pendingVolumeCommand = nil
                    pendingMuteCommand = nil
                }
                syncRTSoundCheckFlagLocked()
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
        let lockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100
        return lock.withLock {
            _cachedVolumeLockedTo100 = lockedTo100
            return _isEnabled &&
                lockedTo100 &&
                !_host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public var profile: ExternalAmpProfile {
        get { lock.withLock { _profile } }
        set {
            let changed: Bool = lock.withLock {
                let prev = _profile
                _profile = newValue
                AppStorageProvider.shared.set(newValue.rawValue, forKey: kProfileKey)
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
                AppStorageProvider.shared.set(trimmed, forKey: kHostKey)
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
            let fallbackPort = lock.withLock { _profile.defaultPort }
            let validPort = newValue > 0 ? newValue : fallbackPort
            let changed: Bool = lock.withLock {
                let prev = _port
                _port = validPort
                AppStorageProvider.shared.set(Int(validPort), forKey: kPortKey)
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
                AppStorageProvider.shared.set(clamped, forKey: kMaxCapKey)
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

    public var currentTrackCrestDb: Double? {
        lock.withLock { _currentTrackCrestDb }
    }

    public var isDigitalSoundCheckDetected: Bool {
        lock.withLock { _isDigitalSoundCheckAlreadyActive }
    }

    public var currentTrackVolumeOffset: Int {
        lock.withLock { _isSoundCheckEnabled ? _currentTrackVolumeOffset : 0 }
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
        let lockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100

        lock.withLock {
            _cachedVolumeLockedTo100 = lockedTo100
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
            pendingMuteCommand = nil
            if endpointChanged {
                hasSyncedVolumeWithAmp = false
                appliedVolumeOffset = 0
            }
            if let isEnabled {
                _isEnabled = isEnabled && lockedTo100
                AppStorageProvider.shared.set(_isEnabled, forKey: kEnabledKey)
                if !_isEnabled && _isSoundCheckEnabled {
                    _isSoundCheckEnabled = false
                    _persistedSoundCheckPreference = false
                    _currentTrackVolumeOffset = 0
                    appliedVolumeOffset = 0
                    AppStorageProvider.shared.set(false, forKey: kSoundCheckKey)
                }
            }
            syncRTSoundCheckFlagLocked()
            AppStorageProvider.shared.set(profile.rawValue, forKey: kProfileKey)
            AppStorageProvider.shared.set(trimmedHost, forKey: kHostKey)
            AppStorageProvider.shared.set(Int(validPort), forKey: kPortKey)
            AppStorageProvider.shared.set(clampedCap, forKey: kMaxCapKey)
        }
        reconfigureConnection()
        notifyStateChanged()
    }

    /// Enforces mutual exclusion: when 100% Volume Lock is turned OFF, External Amp TCP control is forced OFF.
    public func enforceVolumeLockConstraint(isVolumeLockedTo100: Bool) {
        if !isVolumeLockedTo100 {
            let wasEnabled: Bool = lock.withLock {
                let prev = _isEnabled
                _cachedVolumeLockedTo100 = false
                _isEnabled = false
                _isSoundCheckEnabled = false
                _persistedSoundCheckPreference = false
                syncRTSoundCheckFlagLocked()
                _currentTrackVolumeOffset = 0
                appliedVolumeOffset = 0
                pendingVolumeCommand = nil
                pendingMuteCommand = nil
                lastAutoNormTargetVolume = nil
                lastAutoNormPreviousVolume = nil
                AppStorageProvider.shared.set(false, forKey: kEnabledKey)
                AppStorageProvider.shared.set(false, forKey: kSoundCheckKey)
                return prev
            }
            if wasEnabled {
                NSLog("[ExternalAmpTCP] Volume Lock 100%% disabled -> automatically disabling External Amp TCP control.")
                reconfigureConnection()
                notifyStateChanged()
            }
        } else {
            lock.withLock {
                _cachedVolumeLockedTo100 = true
                syncRTSoundCheckFlagLocked()
            }
        }
    }

    /// Starts the TCP connection if `isActive` is true.
    public func startIfActive() {
        reconfigureConnection()
    }

    internal func resetSyncStateForTesting(baseVolume: Int = 20, lastPersistedAmpVolume: Int = 0) {
        lock.withLock {
            let effectiveMax = max(1, min(100, min(_maxVolumeCap, _profile.nativeMaxVolume)))
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
            pendingMuteCommand = nil
            lastAutoNormTargetVolume = nil
            lastAutoNormPreviousVolume = nil
            lastUserCommandTime = .distantPast
            lastAutoNormCommandTime = .distantPast
        }
    }

    internal func notifyStateChanged() {
        // PlayerStatusEngine.getPlayerStatus() reads ExternalAmpTCPController properties dynamically;
        // never wipe Music.app static track metadata cache on amplifier volume/SoundCheck updates.
        let callback = self.onStateChanged
        callback?()
    }
}
