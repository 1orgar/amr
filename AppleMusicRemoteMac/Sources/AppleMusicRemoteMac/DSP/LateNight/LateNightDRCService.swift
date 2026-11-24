//
//  LateNightDRCService.swift
//  AppleMusicRemoteMac
//
//  Global State Coordinator, Lock-Free Fast Mode Flags, Persistence & iCloud Drive LWW Sync
//  for Audiophile Late-Night Dynamic Range Control (`Night Concert Mode`).
//

import Foundation
import os.lock

public final class LateNightDRCService: @unchecked Sendable {
    public static let shared = LateNightDRCService()

    /// Selectable DRC profiles when Late-Night mode is enabled.
    public static let selectableProfiles: [LateNightDRCMode] = [.gentle, .concert]

    private let lock = NSLock()
    private var fastStateLock = os_unfair_lock_s()
    private let userDefaults: UserDefaults
    private let modeStorageKey: String
    private let enabledStorageKey: String
    private let profileStorageKey: String
    private let updatedAtStorageKey: String
    private let isIsolatedInstance: Bool

    private var _isEnabled: Bool
    private var _selectedProfile: LateNightDRCMode
    private var _updatedAt: TimeInterval

    private var _fastIsEnabled: Bool
    private var _fastSelectedProfile: LateNightDRCMode
    private var _fastUpdatedAt: TimeInterval

    /// Real-time processors isolated per audio pipeline (HQ NOS / DSD DoP, BluOS/DLNA stream, Local Passthrough AU)
    public let dspEngineProcessor = LateNightDRCProcessor()
    public let streamProcessor = LateNightDRCProcessor()
    public let localPassthroughProcessor = LateNightDRCProcessor()

    public init(
        userDefaults: UserDefaults = AppStorageProvider.shared,
        suiteKeyPrefix: String = "amr.late_night_drc",
        isIsolated: Bool = false
    ) {
        let mKey = "\(suiteKeyPrefix).mode.v1"
        let eKey = "\(suiteKeyPrefix).enabled.v1"
        let pKey = "\(suiteKeyPrefix).profile.v1"
        let uKey = "\(suiteKeyPrefix).updated_at.v1"

        self.userDefaults = userDefaults
        self.modeStorageKey = mKey
        self.enabledStorageKey = eKey
        self.profileStorageKey = pKey
        self.updatedAtStorageKey = uKey
        self.isIsolatedInstance = isIsolated

        let legacyMode = LateNightDRCMode(rawValue: userDefaults.string(forKey: mKey) ?? "") ?? .off
        let storedProfileRaw = userDefaults.string(forKey: pKey)
        let resolvedProfile: LateNightDRCMode
        if let raw = storedProfileRaw,
           let parsed = LateNightDRCMode(rawValue: raw),
           parsed != .off {
            resolvedProfile = parsed
        } else if legacyMode != .off {
            resolvedProfile = legacyMode
        } else {
            resolvedProfile = .gentle
        }

        let resolvedEnabled: Bool
        if userDefaults.object(forKey: eKey) != nil {
            resolvedEnabled = userDefaults.bool(forKey: eKey)
        } else {
            resolvedEnabled = legacyMode.isEnabled
        }

        let loadedUpdatedAt = userDefaults.double(forKey: uKey)
        self._isEnabled = resolvedEnabled
        self._selectedProfile = resolvedProfile
        self._updatedAt = loadedUpdatedAt
        self._fastIsEnabled = resolvedEnabled
        self._fastSelectedProfile = resolvedProfile
        self._fastUpdatedAt = loadedUpdatedAt

        let effective = resolvedEnabled ? resolvedProfile : .off
        dspEngineProcessor.setMode(effective)
        streamProcessor.setMode(effective)
        localPassthroughProcessor.setMode(effective)
    }

    public var mode: LateNightDRCMode {
        os_unfair_lock_lock(&fastStateLock)
        let effective: LateNightDRCMode = _fastIsEnabled ? _fastSelectedProfile : .off
        os_unfair_lock_unlock(&fastStateLock)
        return effective
    }

    public var isEnabled: Bool {
        os_unfair_lock_lock(&fastStateLock)
        let flag = _fastIsEnabled
        os_unfair_lock_unlock(&fastStateLock)
        return flag
    }

    public var selectedProfile: LateNightDRCMode {
        os_unfair_lock_lock(&fastStateLock)
        let prof = _fastSelectedProfile
        os_unfair_lock_unlock(&fastStateLock)
        return prof
    }

    public var updatedAt: TimeInterval {
        os_unfair_lock_lock(&fastStateLock)
        let ts = _fastUpdatedAt
        os_unfair_lock_unlock(&fastStateLock)
        return ts
    }

    public func setEnabled(_ enabled: Bool, notifyCloudSync: Bool = true) {
        updateState(enabled: enabled, profile: nil, notifyCloudSync: notifyCloudSync)
    }

    public func setSelectedProfile(_ profile: LateNightDRCMode, notifyCloudSync: Bool = true) {
        guard profile != .off else {
            setEnabled(false, notifyCloudSync: notifyCloudSync)
            return
        }
        updateState(enabled: nil, profile: profile, notifyCloudSync: notifyCloudSync)
    }

    public func setMode(_ newMode: LateNightDRCMode, notifyCloudSync: Bool = true) {
        if newMode == .off {
            updateState(enabled: false, profile: nil, notifyCloudSync: notifyCloudSync)
        } else {
            updateState(enabled: true, profile: newMode, notifyCloudSync: notifyCloudSync)
        }
    }

    public func updateState(
        enabled: Bool?,
        profile: LateNightDRCMode?,
        notifyCloudSync: Bool = true
    ) {
        let now = Date().timeIntervalSince1970
        var changed = false
        let effectiveMode: LateNightDRCMode

        lock.lock()
        if let profile, profile != .off, _selectedProfile != profile {
            _selectedProfile = profile
            changed = true
        }
        if let enabled, _isEnabled != enabled {
            _isEnabled = enabled
            changed = true
        }
        effectiveMode = _isEnabled ? _selectedProfile : .off
        if changed {
            _updatedAt = now
            os_unfair_lock_lock(&fastStateLock)
            _fastIsEnabled = _isEnabled
            _fastSelectedProfile = _selectedProfile
            _fastUpdatedAt = now
            os_unfair_lock_unlock(&fastStateLock)
            userDefaults.set(_isEnabled, forKey: enabledStorageKey)
            userDefaults.set(_selectedProfile.rawValue, forKey: profileStorageKey)
            userDefaults.set(effectiveMode.rawValue, forKey: modeStorageKey)
            userDefaults.set(now, forKey: updatedAtStorageKey)
        }
        lock.unlock()

        dspEngineProcessor.setMode(effectiveMode)
        streamProcessor.setMode(effectiveMode)
        localPassthroughProcessor.setMode(effectiveMode)

        guard !isIsolatedInstance else { return }
        RoomAcousticService.shared.refreshLocalPassthroughEQPipeline(clearZeroSignalSuspension: true)

        if changed && notifyCloudSync {
            CloudSettingsSyncService.shared.scheduleDebouncedSync(reason: "late_night_drc_changed")
        }
    }

    /// Merges remote iCloud Drive state using Last-Write-Wins timestamp resolution.
    @discardableResult
    public func mergeCloudState(
        remoteModeRaw: String?,
        remoteEnabled: Bool? = nil,
        remoteProfileRaw: String? = nil,
        remoteUpdatedAt: TimeInterval?
    ) -> Bool {
        let parsedMode = remoteModeRaw.flatMap { LateNightDRCMode(rawValue: $0) }
        let parsedProfile = remoteProfileRaw.flatMap { LateNightDRCMode(rawValue: $0) }.flatMap { $0 == .off ? nil : $0 }

        guard parsedMode != nil || remoteEnabled != nil || parsedProfile != nil else {
            return false
        }

        let remoteTS = remoteUpdatedAt ?? 0.0
        var applied = false
        let effectiveMode: LateNightDRCMode

        lock.lock()
        let nextProfile: LateNightDRCMode = {
            if let parsedProfile { return parsedProfile }
            if let parsedMode, parsedMode != .off { return parsedMode }
            return _selectedProfile
        }()
        let nextEnabled: Bool = {
            if let remoteEnabled { return remoteEnabled }
            if let parsedMode { return parsedMode.isEnabled }
            return _isEnabled
        }()

        let shouldAdoptRemote: Bool
        if remoteTS > _updatedAt + 0.0001 {
            shouldAdoptRemote = true
        } else if abs(remoteTS - _updatedAt) <= 0.0001 {
            shouldAdoptRemote = (nextEnabled ? 1 : 0, nextProfile.rawValue) > (_isEnabled ? 1 : 0, _selectedProfile.rawValue)
        } else {
            shouldAdoptRemote = false
        }

        if shouldAdoptRemote {
            if _isEnabled != nextEnabled || _selectedProfile != nextProfile {
                applied = true
            }
            _isEnabled = nextEnabled
            _selectedProfile = nextProfile
            _updatedAt = max(_updatedAt, remoteTS)
            let nextEffective: LateNightDRCMode = _isEnabled ? _selectedProfile : .off
            os_unfair_lock_lock(&fastStateLock)
            _fastIsEnabled = _isEnabled
            _fastSelectedProfile = _selectedProfile
            _fastUpdatedAt = _updatedAt
            os_unfair_lock_unlock(&fastStateLock)
            userDefaults.set(_isEnabled, forKey: enabledStorageKey)
            userDefaults.set(_selectedProfile.rawValue, forKey: profileStorageKey)
            userDefaults.set(nextEffective.rawValue, forKey: modeStorageKey)
            userDefaults.set(_updatedAt, forKey: updatedAtStorageKey)
        } else if abs(remoteTS - _updatedAt) <= 0.0001 && _isEnabled == nextEnabled && _selectedProfile == nextProfile && remoteTS > _updatedAt {
            _updatedAt = remoteTS
            os_unfair_lock_lock(&fastStateLock)
            _fastUpdatedAt = remoteTS
            os_unfair_lock_unlock(&fastStateLock)
            userDefaults.set(_updatedAt, forKey: updatedAtStorageKey)
        }
        effectiveMode = _isEnabled ? _selectedProfile : .off
        lock.unlock()

        if applied {
            dspEngineProcessor.setMode(effectiveMode)
            streamProcessor.setMode(effectiveMode)
            localPassthroughProcessor.setMode(effectiveMode)
            if !isIsolatedInstance {
                RoomAcousticService.shared.refreshLocalPassthroughEQPipeline(clearZeroSignalSuspension: true)
            }
        }
        return applied
    }

    // MARK: - Real-Time Pipeline Entry Points

    @inline(__always)
    public func processPlanarDoubleIfEnabled(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frameCount: Int,
        sampleRate: Double
    ) {
        guard dspEngineProcessor.mode != .off else { return }
        dspEngineProcessor.processPlanarDouble(
            left: left,
            right: right,
            frameCount: frameCount,
            sampleRate: sampleRate
        )
    }

    @inline(__always)
    public func processStreamPlanarFloat32IfEnabled(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        frameCount: Int,
        sampleRate: Double
    ) {
        guard streamProcessor.mode != .off else { return }
        streamProcessor.processPlanarFloat32(
            left: left,
            right: right,
            frameCount: frameCount,
            sampleRate: sampleRate
        )
    }

    @inline(__always)
    public func processLocalPassthroughPlanarFloat32IfEnabled(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        frameCount: Int,
        sampleRate: Double
    ) {
        guard localPassthroughProcessor.mode != .off else { return }
        localPassthroughProcessor.processPlanarFloat32(
            left: left,
            right: right,
            frameCount: frameCount,
            sampleRate: sampleRate
        )
    }

    @inline(__always)
    public func processStreamFloatPairIfEnabled(
        left: inout Float,
        right: inout Float,
        sampleRate: Double
    ) {
        guard streamProcessor.mode != .off else { return }
        streamProcessor.processStereoFloatPair(left: &left, right: &right, sampleRate: sampleRate)
    }

    @inline(__always)
    public func processLocalPassthroughFloatPairIfEnabled(
        left: inout Float,
        right: inout Float,
        sampleRate: Double
    ) {
        guard localPassthroughProcessor.mode != .off else { return }
        localPassthroughProcessor.processStereoFloatPair(left: &left, right: &right, sampleRate: sampleRate)
    }

    public func resetLocalPassthroughState() {
        localPassthroughProcessor.resetState()
    }

    private func resolveActiveProcessor() -> LateNightDRCProcessor {
        if isIsolatedInstance {
            return dspEngineProcessor
        }
        if AudioEngineController.shared.isActivePipelineHook {
            return dspEngineProcessor
        }
        if DLNADiscoveryManager.shared.hasActiveRenderer {
            return streamProcessor
        }
        return localPassthroughProcessor
    }

    /// Returns the live active gain in dB from whichever output pipeline is currently running.
    public func activeGainDB() -> Double {
        let current = mode
        guard current != .off else { return 0.0 }
        let snap = resolveActiveProcessor().telemetrySnapshot()
        return (snap.gainDB * 10.0).rounded() / 10.0
    }

    public func statusDictionary(isEnglish: Bool = false) -> [String: Any] {
        let current = mode
        let prof = selectedProfile
        let enabledFlag = isEnabled
        let activeTelemetry = resolveActiveProcessor().telemetrySnapshot()
        let gainDB = current != .off
            ? ((activeTelemetry.gainDB * 10.0).rounded() / 10.0)
            : 0.0
        let lufs = activeTelemetry.shortTermLUFS

        let profilesList: [[String: Any]] = Self.selectableProfiles.map { m in
            [
                "id": m.rawValue,
                "title": m.title(isEnglish: isEnglish),
                "short_label": m.shortLabel(isEnglish: isEnglish),
                "subtitle": m.subtitle(isEnglish: isEnglish)
            ]
        }

        let modesList: [[String: Any]] = LateNightDRCMode.allCases.map { m in
            [
                "id": m.rawValue,
                "title": m.title(isEnglish: isEnglish),
                "short_label": m.shortLabel(isEnglish: isEnglish),
                "subtitle": m.subtitle(isEnglish: isEnglish)
            ]
        }

        return [
            "mode": current.rawValue,
            "enabled": enabledFlag,
            "profile": prof.rawValue,
            "profile_title": prof.title(isEnglish: isEnglish),
            "profile_short_label": prof.shortLabel(isEnglish: isEnglish),
            "profile_subtitle": prof.subtitle(isEnglish: isEnglish),
            "title": current.title(isEnglish: isEnglish),
            "short_label": current.shortLabel(isEnglish: isEnglish),
            "subtitle": current.subtitle(isEnglish: isEnglish),
            "current_gain_db": gainDB,
            "short_term_lufs": (lufs * 10.0).rounded() / 10.0,
            "updated_at": updatedAt,
            "profiles": profilesList,
            "modes": modesList
        ]
    }
}
