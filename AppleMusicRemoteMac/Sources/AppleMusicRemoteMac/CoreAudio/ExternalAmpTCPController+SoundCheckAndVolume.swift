//
//  ExternalAmpTCPController+SoundCheckAndVolume.swift
//  AppleMusicRemoteMac
//
//  Hardware Volume, Track SoundCheck Application, Live Crest/De-Clipper Reapplication & Mute Control
//

import Foundation

extension ExternalAmpTCPController {

    // MARK: - Volume & Mute Commands

    /// Sets the amplifier hardware volume (clamped to `0...maxVolumeCap`).
    public func setVolume(_ newVolume: Int, preserveBaseVolume: Bool = false) {
        let lockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100
        let (active, prof, cap) = lock.withLock { () -> (Bool, ExternalAmpProfile, Int) in
            _cachedVolumeLockedTo100 = lockedTo100
            return (_isEnabled && lockedTo100 && !_host.isEmpty, _profile, _maxVolumeCap)
        }
        guard active else { return }

        let effectiveMax = max(1, min(100, min(cap, prof.nativeMaxVolume)))
        var clamped = max(0, min(effectiveMax, newVolume))
        if prof == .lyngdorf {
            clamped = prof.parseToken(prof.buildSetVolumeCommand(clamped)).volume ?? clamped
        }

        let postAdj = MasteringRestorationService.shared.postFilterNormalizationAdjustment()
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
                let resolved = resolveBaseAndOffsetForManualVolume(
                    clamped,
                    effectiveMax: effectiveMax,
                    postFilterRestoredPeakDb: postAdj.restoredPeakDb,
                    postFilterDigitalPadDb: postAdj.digitalPadDb
                )
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

        if !preserveBaseVolume {
            AudioDuckingController.shared.notifyManualVolumeChange(clamped)
        }

        sendVolumeCommand(clamped, profile: prof)

        if stateChanged {
            notifyStateChanged()
        }
    }

    /// Applies Apple's `iTunNORM` SoundCheck gain (in dB) for the currently playing track by offsetting
    /// the amplifier hardware volume relative to `baseListeningVolume` without altering CoreAudio's 100% Bit-Perfect stream.
    public func applyTrackSoundCheck(trackKey: String, gainDb: Double?, crestFactorDb: Double? = nil) {
        let lockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100
        let isDucked = AudioDuckingController.shared.isDucked
        let postAdj = MasteringRestorationService.shared.postFilterNormalizationAdjustment()
        var volumeToSend: (vol: Int, profile: ExternalAmpProfile)?
        let shouldNotify: Bool = lock.withLock {
            _cachedVolumeLockedTo100 = lockedTo100
            let active = _isEnabled && lockedTo100 && !_host.isEmpty
            let effectiveMax = max(1, min(100, min(_maxVolumeCap, _profile.nativeMaxVolume)))
            let prevKey = _currentTrackKey
            let prevGain = _currentTrackGainDb
            let prevOffset = _currentTrackVolumeOffset

            if prevKey != trackKey {
                _currentTrackCrestDb = crestFactorDb
                _isDigitalSoundCheckAlreadyActive = false
            } else if let crestFactorDb {
                _currentTrackCrestDb = crestFactorDb
            }

            let restoredForTrack = (prevKey == trackKey) ? postAdj.restoredPeakDb : 0.0
            let newOffset = _isSoundCheckEnabled
                ? Self.computeVolumeOffset(
                    forGainDb: gainDb,
                    baseVolume: _baseListeningVolume,
                    smartLowVolume: _isLowVolumeSmartNormEnabled,
                    compressionCompensation: _isCompressionCompensationEnabled,
                    crestFactorDb: _currentTrackCrestDb,
                    digitalSoundCheckAlreadyActive: _isDigitalSoundCheckAlreadyActive,
                    postFilterRestoredPeakDb: restoredForTrack,
                    postFilterDigitalPadDb: postAdj.digitalPadDb
                )
                : 0

            _currentTrackKey = trackKey
            _currentTrackGainDb = gainDb
            _currentTrackVolumeOffset = newOffset

            var volChanged = false
            if active && _isSoundCheckEnabled && hasSyncedVolumeWithAmp && !_isMuted && !isDucked && (_baseListeningVolume > 0 || _currentVolume > 0) {
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
                    volChanged = true
                    NSLog("[ExternalAmpTCP] SoundCheck '%@': gain=%+.2f dB, crest=%.1f dB, offset=%+d, base=%d -> ampVol=%d",
                          trackKey, gainDb ?? 0.0, _currentTrackCrestDb ?? -1.0, newOffset, _baseListeningVolume, targetVol)
                } else if prevKey != trackKey && !trackKey.isEmpty {
                    NSLog("[ExternalAmpTCP] SoundCheck '%@': gain=%+.2f dB, crest=%.1f dB, offset=%+d, base=%d -> ampVol=%d (unchanged)",
                          trackKey, gainDb ?? 0.0, _currentTrackCrestDb ?? -1.0, newOffset, _baseListeningVolume, targetVol)
                }
            }

            return volChanged || prevKey != trackKey || prevGain != gainDb || prevOffset != newOffset
        }

        if let v = volumeToSend {
            sendVolumeCommand(v.vol, profile: v.profile)
        }
        if shouldNotify {
            notifyStateChanged()
        }
    }

    /// Обновляет измеренный в реальном времени пик-фактор (Crest Factor) и статус цифровой «Коррекции громкости» Music.app.
    public func updateLiveTrackDynamics(
        trackKey: String,
        crestFactorDb: Double,
        digitalSoundCheckAlreadyActive: Bool
    ) {
        let cleanKey = trackKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanKey.isEmpty else { return }

        let lockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100
        let isDucked = AudioDuckingController.shared.isDucked
        let postAdj = MasteringRestorationService.shared.postFilterNormalizationAdjustment()
        var volumeToSend: (vol: Int, profile: ExternalAmpProfile)?
        let shouldNotify: Bool = lock.withLock {
            _cachedVolumeLockedTo100 = lockedTo100
            guard _currentTrackKey.lowercased() == cleanKey else { return false }
            let prevOffset = _currentTrackVolumeOffset
            let prevDigital = _isDigitalSoundCheckAlreadyActive
            _currentTrackCrestDb = crestFactorDb
            _isDigitalSoundCheckAlreadyActive = digitalSoundCheckAlreadyActive

            if digitalSoundCheckAlreadyActive && !prevDigital {
                NSLog("[ExternalAmpTCP] ⚠️ Обнаружена активная цифровая «Коррекция громкости» в Music.app для '%@' — аппаратное дублирование ослабления отключено!", cleanKey)
            }

            guard _isSoundCheckEnabled else { return prevDigital != digitalSoundCheckAlreadyActive }
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

            let active = _isEnabled && lockedTo100 && !_host.isEmpty
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
                    NSLog("[ExternalAmpTCP] Refined Post-Filter Crest Normalization '%@': gain=%+.2f dB, rawCrest=%.1f dB, restored=%+.1f dB, pad=%+.1f dB, digitalSC=%d -> offset=%+d (ampVol=%d)",
                          cleanKey, _currentTrackGainDb ?? 0.0, crestFactorDb, postAdj.restoredPeakDb, postAdj.digitalPadDb, digitalSoundCheckAlreadyActive ? 1 : 0, newOffset, targetVol)
                }
            }
            return prevOffset != newOffset || prevDigital != digitalSoundCheckAlreadyActive
        }

        if let v = volumeToSend {
            sendVolumeCommand(v.vol, profile: v.profile)
        }
        if shouldNotify {
            notifyStateChanged()
        }
    }

    /// Пересчитывает аппаратное смещение громкости усилителя при включении/выключении `MasteringDeClipper`
    /// или срабатывании `Smart Guard`, чтобы нормализация громкости и компенсация компрессии (`Crest`)
    /// всегда соответствовали сигналу ПОСЛЕ фильтра реставрации.
    public func reapplyPostFilterNormalization() {
        let lockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100
        let isDucked = AudioDuckingController.shared.isDucked
        let postAdj = MasteringRestorationService.shared.postFilterNormalizationAdjustment()
        var volumeToSend: (vol: Int, profile: ExternalAmpProfile)?
        let shouldNotify: Bool = lock.withLock {
            _cachedVolumeLockedTo100 = lockedTo100
            guard _isSoundCheckEnabled, !_currentTrackKey.isEmpty else { return false }
            let prevOffset = _currentTrackVolumeOffset
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
            guard newOffset != prevOffset else { return false }
            _currentTrackVolumeOffset = newOffset

            let active = _isEnabled && lockedTo100 && !_host.isEmpty
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
            return true
        }

        if let v = volumeToSend {
            sendVolumeCommand(v.vol, profile: v.profile)
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
        let lockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100
        var extraVolTarget: Int?
        let (active, prof, targetMute): (Bool, ExternalAmpProfile, Bool) = lock.withLock {
            _cachedVolumeLockedTo100 = lockedTo100
            let isAct = _isEnabled && lockedTo100 && !_host.isEmpty
            let nextMute = muted ?? !_isMuted
            if isAct {
                _isMuted = nextMute
                lastUserCommandTime = Date()
                if !nextMute && _isSoundCheckEnabled && hasSyncedVolumeWithAmp && (_baseListeningVolume > 0 || _currentVolume > 0) && appliedVolumeOffset != _currentTrackVolumeOffset {
                    let effectiveMax = max(1, min(100, min(_maxVolumeCap, _profile.nativeMaxVolume)))
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
                        extraVolTarget = targetVol
                    }
                }
            }
            return (isAct, _profile, nextMute)
        }
        guard active else { return }

        sendMuteCommand(targetMute, profile: prof)
        if let extraVolTarget {
            sendVolumeCommand(extraVolTarget, profile: prof)
        }
        notifyStateChanged()
    }

    /// Requests an immediate status update from the amplifier.
    public func requestStatusPoll() {
        let lockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100
        let (active, prof) = lock.withLock { () -> (Bool, ExternalAmpProfile) in
            _cachedVolumeLockedTo100 = lockedTo100
            return (_isEnabled && lockedTo100 && !_host.isEmpty, _profile)
        }
        guard active else { return }
        sendQueryStatusIfConnected(profile: prof)
    }
}
