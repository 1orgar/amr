//
//  ExternalAmpTCPController+SoundCheckPolicy.swift
//  AppleMusicRemoteMac
//
//  Hardware SoundCheck Policy Properties, Cloud Sync Reconciliation,
//  and Psychoacoustic Crest / Resistor-Ladder Volume Offset Math
//

import Foundation

extension ExternalAmpTCPController {

    // MARK: - Hardware SoundCheck & Normalization Policy

    /// Whether Bit-Perfect Hardware SoundCheck (`iTunNORM` volume normalization via the external amplifier) is enabled.
    /// Can ONLY be enabled when External Amplifier TCP Volume Control (`isEnabled`) is ON.
    public var isSoundCheckEnabled: Bool {
        get {
            let lockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100
            return lock.withLock {
                _cachedVolumeLockedTo100 = lockedTo100
                syncRTSoundCheckFlagLocked()
                return _isSoundCheckEnabled && _isEnabled && lockedTo100
            }
        }
        set {
            let lockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100
            var restoreVol: Int?
            let (changed, effectiveVal): (Bool, Bool) = lock.withLock {
                _cachedVolumeLockedTo100 = lockedTo100
                let canEnable = newValue && _isEnabled && lockedTo100
                let prev = _isSoundCheckEnabled
                _isSoundCheckEnabled = canEnable
                _persistedSoundCheckPreference = canEnable
                syncRTSoundCheckFlagLocked()
                UserDefaults.standard.set(canEnable, forKey: kSoundCheckKey)
                if prev != canEnable {
                    let now = Date().timeIntervalSince1970
                    _normalizationPolicyUpdatedAt = now
                    UserDefaults.standard.set(now, forKey: kNormalizationPolicyUpdatedAtKey)
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
                if !PlaybackRouter.shared.isTestingEnvironment {
                    CloudSettingsSyncService.shared.schedulePush(reason: "norm_policy_soundcheck")
                }
                notifyStateChanged()
            }
        }
    }

    /// Whether non-linear low-volume compensation (`< 40%`) is enabled for Hardware SoundCheck.
    public var isLowVolumeSmartNormEnabled: Bool {
        get {
            lock.withLock { _isLowVolumeSmartNormEnabled }
        }
        set {
            let lockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100
            let isDucked = AudioDuckingController.shared.isDucked
            let postAdj = MasteringRestorationService.shared.postFilterNormalizationAdjustment()
            var volumeToSend: (vol: Int, profile: ExternalAmpProfile)?
            let changed: Bool = lock.withLock {
                _cachedVolumeLockedTo100 = lockedTo100
                let prev = _isLowVolumeSmartNormEnabled
                _isLowVolumeSmartNormEnabled = newValue
                UserDefaults.standard.set(newValue, forKey: kLowVolumeSmartNormKey)
                guard prev != newValue else { return false }
                let now = Date().timeIntervalSince1970
                _normalizationPolicyUpdatedAt = now
                UserDefaults.standard.set(now, forKey: kNormalizationPolicyUpdatedAtKey)

                let active = _isEnabled && lockedTo100 && !_host.isEmpty
                if _isSoundCheckEnabled {
                    let effectiveMax = max(1, min(100, min(_maxVolumeCap, _profile.nativeMaxVolume)))
                    let newOffset = Self.computeVolumeOffset(
                        forGainDb: _currentTrackGainDb,
                        baseVolume: _baseListeningVolume,
                        smartLowVolume: _isLowVolumeSmartNormEnabled,
                        compressionCompensation: _isCompressionCompensationEnabled,
                        crestFactorDb: _currentTrackCrestDb,
                        digitalSoundCheckAlreadyActive: _isDigitalSoundCheckAlreadyActive,
                        postFilterRestoredPeakDb: postAdj.restoredPeakDb,
                        postFilterDigitalPadDb: postAdj.digitalPadDb
                    )
                    _currentTrackVolumeOffset = newOffset
                    if active && hasSyncedVolumeWithAmp && !_isMuted && !isDucked && (_baseListeningVolume > 0 || _currentVolume > 0) {
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
                            volumeToSend = (targetVol, _profile)
                        }
                    }
                }
                return true
            }
            if let v = volumeToSend {
                sendVolumeCommand(v.vol, profile: v.profile)
            }
            if changed {
                if !PlaybackRouter.shared.isTestingEnvironment {
                    CloudSettingsSyncService.shared.schedulePush(reason: "norm_policy_smart_low_vol")
                }
                notifyStateChanged()
            }
        }
    }

    /// Психоакустическая компенсация динамического сжатия (Crest / PLR Compensation).
    public var isCompressionCompensationEnabled: Bool {
        get {
            lock.withLock { _isCompressionCompensationEnabled }
        }
        set {
            let lockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100
            let isDucked = AudioDuckingController.shared.isDucked
            let postAdj = MasteringRestorationService.shared.postFilterNormalizationAdjustment()
            var volumeToSend: (vol: Int, profile: ExternalAmpProfile)?
            let changed: Bool = lock.withLock {
                _cachedVolumeLockedTo100 = lockedTo100
                let prev = _isCompressionCompensationEnabled
                _isCompressionCompensationEnabled = newValue
                UserDefaults.standard.set(newValue, forKey: kCompressionCompKey)
                guard prev != newValue else { return false }
                let now = Date().timeIntervalSince1970
                _normalizationPolicyUpdatedAt = now
                UserDefaults.standard.set(now, forKey: kNormalizationPolicyUpdatedAtKey)

                let active = _isEnabled && lockedTo100 && !_host.isEmpty
                if _isSoundCheckEnabled {
                    let effectiveMax = max(1, min(100, min(_maxVolumeCap, _profile.nativeMaxVolume)))
                    let newOffset = Self.computeVolumeOffset(
                        forGainDb: _currentTrackGainDb,
                        baseVolume: _baseListeningVolume,
                        smartLowVolume: _isLowVolumeSmartNormEnabled,
                        compressionCompensation: _isCompressionCompensationEnabled,
                        crestFactorDb: _currentTrackCrestDb,
                        digitalSoundCheckAlreadyActive: _isDigitalSoundCheckAlreadyActive,
                        postFilterRestoredPeakDb: postAdj.restoredPeakDb,
                        postFilterDigitalPadDb: postAdj.digitalPadDb
                    )
                    _currentTrackVolumeOffset = newOffset
                    if active && hasSyncedVolumeWithAmp && !_isMuted && !isDucked && (_baseListeningVolume > 0 || _currentVolume > 0) {
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
                            volumeToSend = (targetVol, _profile)
                        }
                    }
                }
                return true
            }
            if let v = volumeToSend {
                sendVolumeCommand(v.vol, profile: v.profile)
            }
            if changed {
                if !PlaybackRouter.shared.isTestingEnvironment {
                    CloudSettingsSyncService.shared.schedulePush(reason: "norm_policy_compression_comp")
                }
                notifyStateChanged()
            }
        }
    }

    // MARK: - Cloud Sync (Normalization Policy)

    public struct NormalizationPolicySyncState: Codable, Equatable, Sendable {
        public var soundCheckEnabled: Bool
        public var lowVolumeSmartNormEnabled: Bool
        public var compressionCompensationEnabled: Bool
        public var updatedAt: TimeInterval

        public init(
            soundCheckEnabled: Bool,
            lowVolumeSmartNormEnabled: Bool,
            compressionCompensationEnabled: Bool,
            updatedAt: TimeInterval
        ) {
            self.soundCheckEnabled = soundCheckEnabled
            self.lowVolumeSmartNormEnabled = lowVolumeSmartNormEnabled
            self.compressionCompensationEnabled = compressionCompensationEnabled
            self.updatedAt = updatedAt
        }
    }

    public func exportNormalizationPolicy() -> NormalizationPolicySyncState {
        let lockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100
        return lock.withLock {
            _cachedVolumeLockedTo100 = lockedTo100
            let canRunActive = _isEnabled && lockedTo100
            let exportedSoundCheck = canRunActive ? _isSoundCheckEnabled : _persistedSoundCheckPreference
            return NormalizationPolicySyncState(
                soundCheckEnabled: exportedSoundCheck,
                lowVolumeSmartNormEnabled: _isLowVolumeSmartNormEnabled,
                compressionCompensationEnabled: _isCompressionCompensationEnabled,
                updatedAt: _normalizationPolicyUpdatedAt
            )
        }
    }

    @discardableResult
    public func mergeNormalizationPolicy(_ incoming: NormalizationPolicySyncState) -> Bool {
        let lockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100
        var shouldReapply = false
        var restoreVol: Int?
        let changed: Bool = lock.withLock {
            _cachedVolumeLockedTo100 = lockedTo100
            let canRunActive = _isEnabled && lockedTo100
            let currentExportedSC = canRunActive ? _isSoundCheckEnabled : _persistedSoundCheckPreference

            let shouldAdopt: Bool
            if incoming.updatedAt > _normalizationPolicyUpdatedAt + 0.0001 {
                shouldAdopt = true
            } else if abs(incoming.updatedAt - _normalizationPolicyUpdatedAt) <= 0.0001 {
                let incomingTuple = (
                    incoming.soundCheckEnabled ? 1 : 0,
                    incoming.lowVolumeSmartNormEnabled ? 1 : 0,
                    incoming.compressionCompensationEnabled ? 1 : 0
                )
                let currentTuple = (
                    currentExportedSC ? 1 : 0,
                    _isLowVolumeSmartNormEnabled ? 1 : 0,
                    _isCompressionCompensationEnabled ? 1 : 0
                )
                shouldAdopt = incomingTuple > currentTuple
            } else {
                shouldAdopt = false
            }
            guard shouldAdopt else { return false }

            _normalizationPolicyUpdatedAt = max(_normalizationPolicyUpdatedAt, incoming.updatedAt)
            let valueChanged = (
                _isLowVolumeSmartNormEnabled != incoming.lowVolumeSmartNormEnabled ||
                _isCompressionCompensationEnabled != incoming.compressionCompensationEnabled ||
                currentExportedSC != incoming.soundCheckEnabled
            )
            _persistedSoundCheckPreference = incoming.soundCheckEnabled
            _isLowVolumeSmartNormEnabled = incoming.lowVolumeSmartNormEnabled
            _isCompressionCompensationEnabled = incoming.compressionCompensationEnabled
            if !PlaybackRouter.shared.isTestingEnvironment {
                let defaults = UserDefaults.standard
                defaults.set(_normalizationPolicyUpdatedAt, forKey: kNormalizationPolicyUpdatedAtKey)
                defaults.set(incoming.lowVolumeSmartNormEnabled, forKey: kLowVolumeSmartNormKey)
                defaults.set(incoming.compressionCompensationEnabled, forKey: kCompressionCompKey)
                defaults.set(incoming.soundCheckEnabled, forKey: kSoundCheckKey)
            }
            if canRunActive {
                if _isSoundCheckEnabled != incoming.soundCheckEnabled {
                    _isSoundCheckEnabled = incoming.soundCheckEnabled
                    if incoming.soundCheckEnabled {
                        _baseListeningVolume = _currentVolume
                        appliedVolumeOffset = 0
                        shouldReapply = true
                    } else {
                        if appliedVolumeOffset != 0 || _currentTrackVolumeOffset != 0 {
                            restoreVol = _baseListeningVolume
                        }
                        _currentTrackVolumeOffset = 0
                        appliedVolumeOffset = 0
                        lastAutoNormTargetVolume = nil
                        lastAutoNormPreviousVolume = nil
                    }
                } else if _isSoundCheckEnabled && valueChanged {
                    shouldReapply = true
                }
            } else {
                _isSoundCheckEnabled = false
            }
            syncRTSoundCheckFlagLocked()
            return valueChanged
        }
        if changed {
            if !PlaybackRouter.shared.isTestingEnvironment {
                if shouldReapply {
                    AppleSoundCheckService.shared.reapplyCurrentTrack()
                } else if let restoreVol {
                    setVolume(restoreVol)
                }
            }
            notifyStateChanged()
        }
        return changed
    }

    // MARK: - SoundCheck Gain & Resistor-Ladder Volume Offset Math

    public static func computeEffectiveSoundCheckGainDb(
        rawGainDb: Double?,
        compressionCompensation: Bool = true,
        crestFactorDb: Double? = nil,
        digitalSoundCheckAlreadyActive: Bool = false,
        postFilterRestoredPeakDb: Double = 0.0,
        postFilterDigitalPadDb: Double = 0.0
    ) -> Double? {
        guard let rawGainDb, rawGainDb.isFinite else { return nil }
        let padCompensationDb = min(4.5, max(0.0, -postFilterDigitalPadDb))
        if digitalSoundCheckAlreadyActive && rawGainDb < -1.0 {
            return padCompensationDb
        }
        guard compressionCompensation, rawGainDb < -3.0, let rawCrest = crestFactorDb else {
            return rawGainDb + padCompensationDb
        }

        let postFilterCrest = rawCrest + max(0.0, postFilterRestoredPeakDb)
        let effectiveCrest = min(max(postFilterCrest, 3.5), 24.0)
        let crestComp: Double
        if effectiveCrest < 10.5 {
            let crestDeficit = min(6.5, 10.5 - effectiveCrest)
            let excessAttenuation = abs(rawGainDb) - 3.0
            let rawCompensation = min(3.5, crestDeficit * 0.45)
            crestComp = min(rawCompensation, excessAttenuation * 0.45)
        } else {
            crestComp = 0.0
        }
        let baseEffective = min(-1.0, rawGainDb + crestComp)
        return baseEffective + padCompensationDb
    }

    public static func computeVolumeOffset(
        forGainDb gainDb: Double?,
        baseVolume: Int = 50,
        smartLowVolume: Bool = false,
        compressionCompensation: Bool = false,
        crestFactorDb: Double? = nil,
        digitalSoundCheckAlreadyActive: Bool = false,
        postFilterRestoredPeakDb: Double = 0.0,
        postFilterDigitalPadDb: Double = 0.0
    ) -> Int {
        guard let effectiveGain = computeEffectiveSoundCheckGainDb(
            rawGainDb: gainDb,
            compressionCompensation: compressionCompensation,
            crestFactorDb: crestFactorDb,
            digitalSoundCheckAlreadyActive: digitalSoundCheckAlreadyActive,
            postFilterRestoredPeakDb: postFilterRestoredPeakDb,
            postFilterDigitalPadDb: postFilterDigitalPadDb
        ) else { return 0 }
        if !smartLowVolume || baseVolume >= 40 {
            let rounded = Int(effectiveGain.rounded())
            return max(-12, min(5, rounded))
        }
        guard baseVolume > 0 else { return 0 }

        let t = Double(max(1, min(40, baseVolume))) / 40.0
        if effectiveGain < 0 {
            let scale = 0.15 + 0.85 * pow(t, 1.2)
            let scaled = Int((effectiveGain * scale).rounded())
            let maxDrop = max(1, Int((Double(baseVolume) * 0.35).rounded()))
            return max(-min(12, maxDrop), min(0, scaled))
        } else {
            let scale = 0.45 + 0.55 * t
            let scaled = Int((effectiveGain * scale).rounded())
            return max(0, min(5, scaled))
        }
    }

    internal func resolveBaseAndOffsetForManualVolume(
        _ manualVol: Int,
        effectiveMax: Int,
        postFilterRestoredPeakDb: Double = 0.0,
        postFilterDigitalPadDb: Double = 0.0
    ) -> (base: Int, offset: Int) {
        guard manualVol > 0 else { return (0, _isSoundCheckEnabled ? _currentTrackVolumeOffset : 0) }
        guard _isSoundCheckEnabled else { return (max(1, min(effectiveMax, manualVol)), 0) }
        let b0 = max(1, min(effectiveMax, manualVol - appliedVolumeOffset))
        let off1 = Self.computeVolumeOffset(
            forGainDb: _currentTrackGainDb,
            baseVolume: b0,
            smartLowVolume: _isLowVolumeSmartNormEnabled,
            compressionCompensation: _isCompressionCompensationEnabled,
            crestFactorDb: _currentTrackCrestDb,
            digitalSoundCheckAlreadyActive: _isDigitalSoundCheckAlreadyActive,
            postFilterRestoredPeakDb: postFilterRestoredPeakDb,
            postFilterDigitalPadDb: postFilterDigitalPadDb
        )
        let b1 = max(1, min(effectiveMax, manualVol - off1))
        let off2 = Self.computeVolumeOffset(
            forGainDb: _currentTrackGainDb,
            baseVolume: b1,
            smartLowVolume: _isLowVolumeSmartNormEnabled,
            compressionCompensation: _isCompressionCompensationEnabled,
            crestFactorDb: _currentTrackCrestDb,
            digitalSoundCheckAlreadyActive: _isDigitalSoundCheckAlreadyActive,
            postFilterRestoredPeakDb: postFilterRestoredPeakDb,
            postFilterDigitalPadDb: postFilterDigitalPadDb
        )
        let finalBase = max(1, min(effectiveMax, manualVol - off2))
        return (finalBase, off2)
    }
}
