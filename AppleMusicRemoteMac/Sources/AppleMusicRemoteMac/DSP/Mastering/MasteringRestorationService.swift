//
//  MasteringRestorationService.swift
//  AppleMusicRemoteMac
//
//  Service Coordinator, Lock-Free Fast Mode Flags, Persistence & iCloud Drive LWW Sync
//  for 64-Bit Studio Mastering Pre-DSP Suite (De-Clipper + Weiss De-Esser).
//

import Foundation
import os.lock

public final class MasteringRestorationService: @unchecked Sendable {
    public static let shared = MasteringRestorationService()

    private let lock = NSLock()
    private var fastStateLock = os_unfair_lock_s()
    private let userDefaults: UserDefaults
    private let deClipStorageKey: String
    private let deEsserStorageKey: String
    private let updatedAtStorageKey: String
    private let isIsolatedInstance: Bool

    private var _deClipMode: MasteringDeClipMode
    private var _deEsserMode: MasteringDeEsserMode
    private var _updatedAt: TimeInterval
    private var _cleanMasterAutoBypass: Bool = false

    private var _fastDeClipMode: MasteringDeClipMode
    private var _fastDeEsserMode: MasteringDeEsserMode
    private var _fastUpdatedAt: TimeInterval

    public let dspEngineProcessor = MasteringRestorationProcessor()
    public let streamProcessor = MasteringRestorationProcessor()
    public let localPassthroughProcessor = MasteringRestorationProcessor()

    public init(
        userDefaults: UserDefaults = .standard,
        suiteKeyPrefix: String = "amr.mastering_restoration",
        isIsolated: Bool = false
    ) {
        let dcKey = "\(suiteKeyPrefix).declip_mode.v1"
        let deKey = "\(suiteKeyPrefix).deesser_mode.v1"
        let upKey = "\(suiteKeyPrefix).updated_at.v1"

        self.userDefaults = userDefaults
        self.deClipStorageKey = dcKey
        self.deEsserStorageKey = deKey
        self.updatedAtStorageKey = upKey
        self.isIsolatedInstance = isIsolated

        let loadedDeClip = MasteringDeClipMode(rawValue: userDefaults.string(forKey: dcKey) ?? "") ?? .off
        let loadedDeEsser = MasteringDeEsserMode(rawValue: userDefaults.string(forKey: deKey) ?? "") ?? .off
        let loadedUpdatedAt = userDefaults.double(forKey: upKey)
        self._deClipMode = loadedDeClip
        self._deEsserMode = loadedDeEsser
        self._updatedAt = loadedUpdatedAt
        self._fastDeClipMode = loadedDeClip
        self._fastDeEsserMode = loadedDeEsser
        self._fastUpdatedAt = loadedUpdatedAt

        dspEngineProcessor.configure(deClipMode: loadedDeClip, deEsserMode: loadedDeEsser)
        streamProcessor.configure(deClipMode: loadedDeClip, deEsserMode: loadedDeEsser)
        localPassthroughProcessor.configure(deClipMode: loadedDeClip, deEsserMode: loadedDeEsser)
    }

    public var deClipMode: MasteringDeClipMode {
        os_unfair_lock_lock(&fastStateLock)
        let m = _fastDeClipMode
        os_unfair_lock_unlock(&fastStateLock)
        return m
    }

    public var deEsserMode: MasteringDeEsserMode {
        os_unfair_lock_lock(&fastStateLock)
        let m = _fastDeEsserMode
        os_unfair_lock_unlock(&fastStateLock)
        return m
    }

    public var isAnyEnabled: Bool {
        os_unfair_lock_lock(&fastStateLock)
        let active = (_fastDeClipMode != .off) || (_fastDeEsserMode != .off)
        os_unfair_lock_unlock(&fastStateLock)
        return active
    }

    public var updatedAt: TimeInterval {
        os_unfair_lock_lock(&fastStateLock)
        let ts = _fastUpdatedAt
        os_unfair_lock_unlock(&fastStateLock)
        return ts
    }

    public func setDeClipMode(_ mode: MasteringDeClipMode, notifyCloudSync: Bool = true) {
        updateModes(deClipMode: mode, deEsserMode: nil, notifyCloudSync: notifyCloudSync)
    }

    public func setDeEsserMode(_ mode: MasteringDeEsserMode, notifyCloudSync: Bool = true) {
        updateModes(deClipMode: nil, deEsserMode: mode, notifyCloudSync: notifyCloudSync)
    }

    public func updateModes(
        deClipMode: MasteringDeClipMode?,
        deEsserMode: MasteringDeEsserMode?,
        notifyCloudSync: Bool = true
    ) {
        let now = Date().timeIntervalSince1970
        var changed = false
        let nextDC: MasteringDeClipMode
        let nextDE: MasteringDeEsserMode
        let cleanHint: Bool

        lock.lock()
        if let deClipMode, _deClipMode != deClipMode {
            _deClipMode = deClipMode
            changed = true
        }
        if let deEsserMode, _deEsserMode != deEsserMode {
            _deEsserMode = deEsserMode
            changed = true
        }
        nextDC = _deClipMode
        nextDE = _deEsserMode
        cleanHint = _cleanMasterAutoBypass
        if changed {
            _updatedAt = now
            os_unfair_lock_lock(&fastStateLock)
            _fastDeClipMode = nextDC
            _fastDeEsserMode = nextDE
            _fastUpdatedAt = now
            os_unfair_lock_unlock(&fastStateLock)
            userDefaults.set(nextDC.rawValue, forKey: deClipStorageKey)
            userDefaults.set(nextDE.rawValue, forKey: deEsserStorageKey)
            userDefaults.set(now, forKey: updatedAtStorageKey)
        }
        lock.unlock()

        dspEngineProcessor.configure(deClipMode: nextDC, deEsserMode: nextDE, cleanMasterAutoBypass: cleanHint)
        streamProcessor.configure(deClipMode: nextDC, deEsserMode: nextDE, cleanMasterAutoBypass: cleanHint)
        localPassthroughProcessor.configure(deClipMode: nextDC, deEsserMode: nextDE, cleanMasterAutoBypass: cleanHint)

        guard !isIsolatedInstance else { return }
        RoomAcousticService.shared.refreshLocalPassthroughEQPipeline(clearZeroSignalSuspension: true)
        ExternalAmpTCPController.shared.reapplyPostFilterNormalization()

        if changed && notifyCloudSync {
            CloudSettingsSyncService.shared.scheduleDebouncedSync(reason: "mastering_restoration_changed")
        }
    }

    /// Updates Smart Guard hint from `SpectralIntegrityAnalyzer` (`DR >= 11` and `True Peak <= -0.35 dBTP` -> clean audiophile master).
    public func updateTrackDynamicsHint(ttDrScore: Int?, truePeakDbtp: Double?) {
        let isVerifiedClean: Bool
        if let dr = ttDrScore, dr >= 11 {
            if let tp = truePeakDbtp {
                isVerifiedClean = (tp <= -0.35)
            } else {
                isVerifiedClean = true
            }
        } else {
            isVerifiedClean = false
        }

        lock.lock()
        let prev = _cleanMasterAutoBypass
        _cleanMasterAutoBypass = isVerifiedClean
        lock.unlock()

        if prev != isVerifiedClean {
            dspEngineProcessor.setCleanMasterAutoBypass(isVerifiedClean)
            streamProcessor.setCleanMasterAutoBypass(isVerifiedClean)
            localPassthroughProcessor.setCleanMasterAutoBypass(isVerifiedClean)
            if !isIsolatedInstance {
                ExternalAmpTCPController.shared.reapplyPostFilterNormalization()
            }
        }
    }

    public func resetTrackTelemetry() {
        lock.lock()
        _cleanMasterAutoBypass = false
        lock.unlock()
        dspEngineProcessor.setCleanMasterAutoBypass(false)
        streamProcessor.setCleanMasterAutoBypass(false)
        localPassthroughProcessor.setCleanMasterAutoBypass(false)
    }

    public func resetLocalPassthroughState() {
        localPassthroughProcessor.resetState()
    }

    @discardableResult
    public func mergeCloudState(
        remoteDeClipRaw: String?,
        remoteDeEsserRaw: String?,
        remoteUpdatedAt: TimeInterval?
    ) -> Bool {
        let parsedDC = remoteDeClipRaw.flatMap { MasteringDeClipMode(rawValue: $0) }
        let parsedDE = remoteDeEsserRaw.flatMap { MasteringDeEsserMode(rawValue: $0) }
        guard parsedDC != nil || parsedDE != nil else { return false }

        let remoteTS = remoteUpdatedAt ?? 0.0
        var applied = false
        let effectiveDC: MasteringDeClipMode
        let effectiveDE: MasteringDeEsserMode
        let cleanHint: Bool

        lock.lock()
        let candidateDC = parsedDC ?? _deClipMode
        let candidateDE = parsedDE ?? _deEsserMode

        let shouldAdopt: Bool
        if remoteTS > _updatedAt + 0.0001 {
            shouldAdopt = true
        } else if abs(remoteTS - _updatedAt) <= 0.0001 {
            shouldAdopt = (candidateDC.rawValue, candidateDE.rawValue) > (_deClipMode.rawValue, _deEsserMode.rawValue)
        } else {
            shouldAdopt = false
        }

        if shouldAdopt {
            if _deClipMode != candidateDC || _deEsserMode != candidateDE {
                applied = true
            }
            _deClipMode = candidateDC
            _deEsserMode = candidateDE
            _updatedAt = max(_updatedAt, remoteTS)
            os_unfair_lock_lock(&fastStateLock)
            _fastDeClipMode = _deClipMode
            _fastDeEsserMode = _deEsserMode
            _fastUpdatedAt = _updatedAt
            os_unfair_lock_unlock(&fastStateLock)
            userDefaults.set(_deClipMode.rawValue, forKey: deClipStorageKey)
            userDefaults.set(_deEsserMode.rawValue, forKey: deEsserStorageKey)
            userDefaults.set(_updatedAt, forKey: updatedAtStorageKey)
        }
        effectiveDC = _deClipMode
        effectiveDE = _deEsserMode
        cleanHint = _cleanMasterAutoBypass
        lock.unlock()

        if applied {
            dspEngineProcessor.configure(deClipMode: effectiveDC, deEsserMode: effectiveDE, cleanMasterAutoBypass: cleanHint)
            streamProcessor.configure(deClipMode: effectiveDC, deEsserMode: effectiveDE, cleanMasterAutoBypass: cleanHint)
            localPassthroughProcessor.configure(deClipMode: effectiveDC, deEsserMode: effectiveDE, cleanMasterAutoBypass: cleanHint)
            if !isIsolatedInstance {
                RoomAcousticService.shared.refreshLocalPassthroughEQPipeline(clearZeroSignalSuspension: true)
                ExternalAmpTCPController.shared.reapplyPostFilterNormalization()
            }
        }
        return applied
    }

    // MARK: - Real-Time Pipeline Entry Points

    @discardableResult
    @inline(__always)
    public func processDSPPlanarDoubleIfEnabled(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frameCount: Int,
        sampleRate: Double
    ) -> MasteringDeClipMode {
        guard dspEngineProcessor.isAnyEnabled else { return .off }
        return dspEngineProcessor.processPlanarDouble(
            left: left,
            right: right,
            frameCount: frameCount,
            sampleRate: sampleRate,
            applyOutputHeadroom: false
        )
    }

    @inline(__always)
    public func processStreamPlanarFloat32IfEnabled(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        frameCount: Int,
        sampleRate: Double
    ) {
        guard streamProcessor.isAnyEnabled else { return }
        streamProcessor.processPlanarFloat32(
            left: left,
            right: right,
            frameCount: frameCount,
            sampleRate: sampleRate,
            applyOutputHeadroom: true
        )
    }

    @inline(__always)
    public func processLocalPassthroughPlanarFloat32IfEnabled(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        frameCount: Int,
        sampleRate: Double
    ) {
        guard localPassthroughProcessor.isAnyEnabled else { return }
        localPassthroughProcessor.processPlanarFloat32(
            left: left,
            right: right,
            frameCount: frameCount,
            sampleRate: sampleRate,
            applyOutputHeadroom: true
        )
    }

    private func resolveActiveProcessor() -> MasteringRestorationProcessor {
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

    public func activeTelemetrySnapshot() -> MasteringRestorationTelemetrySnapshot {
        guard isAnyEnabled else { return MasteringRestorationTelemetrySnapshot() }
        return resolveActiveProcessor().telemetrySnapshot()
    }

    /// Returns the post-filter crest restoration (`restoredPeakDb >= 0`) and net digital headroom pad (`digitalPadDb <= 0`)
    /// applied downstream of `SpectralIntegrityAnalyzer`.
    public func postFilterNormalizationAdjustment() -> (restoredPeakDb: Double, digitalPadDb: Double) {
        let dc = deClipMode
        guard dc != .off else { return (0.0, 0.0) }
        let snap = activeTelemetrySnapshot()
        let autoBypass = (dc == .auto) && snap.autoBypassedCleanMaster
        if autoBypass {
            return (0.0, 0.0)
        }
        let restored = max(0.0, snap.restoredPeakDB)
        if !isIsolatedInstance && AudioEngineController.shared.isActivePipelineHook {
            let baseHeadroom = AudioEngineController.shared.currentConfigurationSnapshot().headroomDB
            let capDB: Double = (dc == .studio) ? -4.5 : -3.6
            let extraPadDB = min(0.0, capDB - baseHeadroom)
            return (restored, extraPadDB)
        }
        let padDB = MasteringRestorationProcessor.outputHeadroomDB(for: dc, autoBypass: autoBypass)
        return (restored, padDB)
    }

    public func statusDictionary(isEnglish: Bool = false) -> [String: Any] {
        let dc = deClipMode
        let de = deEsserMode
        let snap = activeTelemetrySnapshot()
        let restoredDB = dc != .off ? ((snap.restoredPeakDB * 10.0).rounded() / 10.0) : 0.0
        let deEssDB = de != .off ? ((snap.deEsserGainReductionDB * 10.0).rounded() / 10.0) : 0.0

        let deClipModes: [[String: Any]] = MasteringDeClipMode.allCases.map { m in
            [
                "id": m.rawValue,
                "title": m.title(isEnglish: isEnglish),
                "short_label": m.shortLabel(isEnglish: isEnglish),
                "subtitle": m.subtitle(isEnglish: isEnglish)
            ]
        }

        let deEsserModes: [[String: Any]] = MasteringDeEsserMode.allCases.map { m in
            [
                "id": m.rawValue,
                "title": m.title(isEnglish: isEnglish),
                "short_label": m.shortLabel(isEnglish: isEnglish),
                "subtitle": m.subtitle(isEnglish: isEnglish)
            ]
        }

        return [
            "enabled": dc != .off || de != .off,
            "declip_mode": dc.rawValue,
            "declip_enabled": dc != .off,
            "declip_title": dc.title(isEnglish: isEnglish),
            "declip_short_label": dc.shortLabel(isEnglish: isEnglish),
            "declip_subtitle": dc.subtitle(isEnglish: isEnglish),
            "restored_peak_db": restoredDB,
            "reconstructed_clips_count": snap.reconstructedClipsCount,
            "auto_bypassed_clean_master": snap.autoBypassedCleanMaster,
            "deesser_mode": de.rawValue,
            "deesser_enabled": de != .off,
            "deesser_title": de.title(isEnglish: isEnglish),
            "deesser_short_label": de.shortLabel(isEnglish: isEnglish),
            "deesser_subtitle": de.subtitle(isEnglish: isEnglish),
            "deesser_gain_db": deEssDB,
            "updated_at": updatedAt,
            "declip_modes": deClipModes,
            "deesser_modes": deEsserModes
        ]
    }
}
