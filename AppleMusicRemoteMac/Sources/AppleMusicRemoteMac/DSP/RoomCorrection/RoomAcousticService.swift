//
//  RoomAcousticService.swift
//  AppleMusicRemoteMac
//
//  Quick Room Frequency Response (АЧХ комнаты) Measurement via iPhone / iPad Microphone (PWA),
//  Profile Management, Cloud Sync Tombstone Reconciliation, and Persistence.
//

import AudioToolbox
import CoreAudio
import Foundation
import os

// MARK: - RoomAcousticService

public final class RoomAcousticService: @unchecked Sendable {
    public static let shared = RoomAcousticService()

    public static let isoThirdOctaveBandsHz: [Double] = [
        20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160,
        200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600,
        2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000,
        20000
    ]

    internal let defaults: UserDefaults
    internal let isIsolatedInstance: Bool
    internal let lock = NSLock()

    // Leaf nanosecond spin-lock caching trivial Bool scalars for Real-Time CoreAudio IOProcs.
    // NEVER hold fastFlagsLock across JSON encoding, UserDefaults, CoreAudio HAL, or other locks.
    internal var fastFlagsLock = os_unfair_lock_s()
    internal var _fastIsCorrectionEnabled: Bool = false
    internal var _fastIsLocalPassthroughEQActive: Bool = false
    internal var _fastIsSuspendedDueToZeroedTap: Bool = false

    internal static let tombstoneTTLSeconds: TimeInterval = 180.0 * 86_400.0

    private let profilesKey = "amr.room.acousticProfiles.v1"
    private let deletedTombstonesKey = "amr.room.deletedProfileTimestamps.v1"
    private let activeProfileIDKey = "amr.room.activeProfileID.v1"
    private let correctionEnabledKey = "amr.room.correctionEnabled.v1"
    private let stateUpdatedAtKey = "amr.room.stateUpdatedAt.v1"

    internal var profiles: [RoomAcousticProfile] = []
    internal var deletedProfileTimestamps: [String: TimeInterval] = [:]
    internal var activeProfileIDInternal: String?
    internal var correctionEnabledInternal: Bool = false
    internal var roomStateUpdatedAtInternal: TimeInterval = 0

    // Real-time processors (separate states for DSP engine vs Tap/Local output so filters never cross-corrupt)
    public let dspEngineProcessor = RoomEQProcessor()
    public let streamProcessor = RoomEQProcessor()
    public let localPassthroughProcessor = RoomEQProcessor()

    // Reference Pink Noise state & local CoreAudio DefaultOutput unit
    internal var pinkSpinLock = os_unfair_lock_s()
    internal var _isTestSignalPlaying: Bool = false
    internal var pinkStateL = PinkNoiseGeneratorState(rngState: 0x9E37_79B9_7F4A_7C15)
    internal var pinkStateR = PinkNoiseGeneratorState(rngState: 0xBF58_476D_1CE4_E5B9)
    internal var testSignalAutoStopTimer: DispatchSourceTimer?
    internal var testSignalTimerGeneration: UInt64 = 0
    internal var activeTestSignalClientID: UUID?
    internal var localNoiseAudioUnit: AudioComponentInstance?

    // Local Passthrough Pre-DSP AudioUnit (active ONLY when mode == .bitPerfectPassthrough && (hasRoomEQ || hasLateNightDRC || hasMastering) && !DLNA)
    internal static let localEQRingCapacity: Int = 65_536 // Power of two (~682 ms @ 96 kHz, ~341 ms @ 192 kHz, zero RT heap allocs)
    internal static let localEQRingMask: Int = 65_535
    internal let localEQUnitLifecycleLock = NSLock()
    internal let localEQControlQueue = DispatchQueue(label: "org.ksholokhov.amr.roomeq.control", qos: .userInteractive)
    internal var localEQAudioUnit: AudioComponentInstance?
    internal var simulatedLocalEQActiveForTesting: Bool = false
    internal var tapZeroSignalSuspended: Bool = false
    internal var localEQConfiguredSampleRate: Double = 0.0
    internal var localEQConfiguredDeviceID: AudioDeviceID = 0
    internal var localEQReconfigGeneration: UInt64 = 0
    internal var localEQSubscriberID = UUID()
    internal var localEQRingLock = os_unfair_lock_s()
    internal var localEQRingL: [Float]
    internal var localEQRingR: [Float]
    internal var localEQRingReadIdx: Int = 0
    internal var localEQRingWriteIdx: Int = 0
    internal var localEQRingCount: Int = 0
    internal var localEQRingPrimed: Bool = false
    internal var localEQFadeInCurrent: Float = 1.0
    internal var localEQFadeInStep: Float = 0.0
    internal var localEQAsyncReconfigPending: Bool = false
    internal var localEQRingUnitActiveFlag: Bool = false
    internal var localEQRingConfiguredUnitRate: Double = 0.0
    internal var localEQSampleRate: Double = 48_000.0

    public init(userDefaults: UserDefaults = AppStorageProvider.shared, isIsolatedInstance: Bool = false) {
        self.defaults = userDefaults
        self.isIsolatedInstance = isIsolatedInstance || PlaybackRouter.shared.isTestingEnvironment
        self.localEQRingL = [Float](repeating: 0.0, count: Self.localEQRingCapacity)
        self.localEQRingR = [Float](repeating: 0.0, count: Self.localEQRingCapacity)
        loadFromDefaults()
        syncFastFlagsFromStateLocked()
        syncRealtimeProcessors()
    }

    @usableFromInline
    @inline(__always)
    internal func syncFastFlagsFromStateLocked() {
        let corr = correctionEnabledInternal
        let eqActive = (localEQAudioUnit != nil) || simulatedLocalEQActiveForTesting
        let zeroSusp = tapZeroSignalSuspended
        os_unfair_lock_lock(&fastFlagsLock)
        _fastIsCorrectionEnabled = corr
        _fastIsLocalPassthroughEQActive = eqActive
        _fastIsSuspendedDueToZeroedTap = zeroSusp
        os_unfair_lock_unlock(&fastFlagsLock)
    }

    // MARK: - Public State & Profiles

    public var isTestSignalPlaying: Bool {
        os_unfair_lock_lock(&pinkSpinLock)
        let v = _isTestSignalPlaying
        os_unfair_lock_unlock(&pinkSpinLock)
        return v
    }

    public var isCorrectionEnabled: Bool {
        get {
            os_unfair_lock_lock(&fastFlagsLock)
            let v = _fastIsCorrectionEnabled
            os_unfair_lock_unlock(&fastFlagsLock)
            return v
        }
        set {
            setCorrectionEnabled(newValue)
        }
    }

    public var activeProfileID: String? {
        lock.lock()
        defer { lock.unlock() }
        return activeProfileIDInternal
    }

    public var activeProfile: RoomAcousticProfile? {
        lock.lock()
        defer { lock.unlock() }
        guard let id = activeProfileIDInternal else { return profiles.first }
        return profiles.first(where: { $0.id == id }) ?? profiles.first
    }

    /// True when local Passthrough Room EQ / Late-Night DRC AudioUnit is actively routing `Music.app` audio through Pre-DSP (RT-safe).
    public var isLocalPassthroughEQActive: Bool {
        os_unfair_lock_lock(&fastFlagsLock)
        let active = _fastIsLocalPassthroughEQActive
        os_unfair_lock_unlock(&fastFlagsLock)
        return active
    }

    /// True when Process Tap delivered 100% zeros while Music.app is playing (RT-safe).
    public var isSuspendedDueToZeroedTap: Bool {
        os_unfair_lock_lock(&fastFlagsLock)
        let suspended = _fastIsSuspendedDueToZeroedTap
        os_unfair_lock_unlock(&fastFlagsLock)
        return suspended
    }

    /// Configured input stream sample rate of the active Local Passthrough Pre-DSP pipeline (`Hz`).
    public var currentLocalPassthroughSampleRate: Double {
        lock.lock()
        let configured = localEQConfiguredSampleRate
        lock.unlock()
        if configured > 0 {
            return configured
        }
        os_unfair_lock_lock(&localEQRingLock)
        let ringSR = localEQSampleRate
        os_unfair_lock_unlock(&localEQRingLock)
        return ringSR
    }

    /// Monotonic counter incremented every time Local Passthrough Pre-DSP reconfigures for a new sample rate or output device.
    public var localPassthroughReconfigCount: UInt64 {
        lock.lock()
        let gen = localEQReconfigGeneration
        lock.unlock()
        return gen
    }

    public var roomStateUpdatedAt: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return roomStateUpdatedAtInternal
    }

    public func allProfiles() -> [RoomAcousticProfile] {
        lock.lock()
        defer { lock.unlock() }
        return profiles.sorted {
            if abs($0.updatedAt - $1.updatedAt) > 0.0001 {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.id < $1.id
        }
    }

    public func deletedProfileTombstonesSnapshot() -> [String: TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return deletedProfileTimestamps
    }

    public func setCorrectionEnabled(_ enabled: Bool, notifyCloudSync: Bool = true) {
        lock.lock()
        let prevEnabled = correctionEnabledInternal
        let prevActive = activeProfileIDInternal
        correctionEnabledInternal = enabled
        if enabled && activeProfileIDInternal == nil {
            activeProfileIDInternal = profiles.first?.id
        }
        let changed = (correctionEnabledInternal != prevEnabled) || (activeProfileIDInternal != prevActive)
        if changed {
            roomStateUpdatedAtInternal = Date().timeIntervalSince1970
        }
        syncFastFlagsFromStateLocked()
        saveToDefaultsLocked()
        lock.unlock()

        syncRealtimeProcessors()
        refreshLocalPassthroughEQPipeline()

        if changed && notifyCloudSync && !isIsolatedInstance {
            CloudSettingsSyncService.shared.scheduleDebouncedSync(reason: "room_correction_toggled")
        }
    }

    @discardableResult
    public func selectProfile(id: String?, notifyCloudSync: Bool = true) -> RoomAcousticProfile? {
        let trimmed = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        let prevActive = activeProfileIDInternal
        if let tid = trimmed, !tid.isEmpty {
            guard profiles.contains(where: { $0.id == tid }) else {
                lock.unlock()
                return nil
            }
            activeProfileIDInternal = tid
        } else {
            activeProfileIDInternal = nil
        }
        let stateChanged = (activeProfileIDInternal != prevActive)
        if stateChanged {
            roomStateUpdatedAtInternal = Date().timeIntervalSince1970
        }
        syncFastFlagsFromStateLocked()
        saveToDefaultsLocked()
        let chosen = activeProfileIDInternal.flatMap { aid in profiles.first(where: { $0.id == aid }) }
        lock.unlock()

        syncRealtimeProcessors()
        refreshLocalPassthroughEQPipeline()

        if stateChanged && notifyCloudSync && !isIsolatedInstance {
            CloudSettingsSyncService.shared.scheduleDebouncedSync(reason: "room_profile_selected")
        }
        return chosen
    }

    @discardableResult
    public func renameProfile(id: String, newName: String) -> RoomAcousticProfile? {
        let cleanName = String(newName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        guard !cleanName.isEmpty else { return nil }
        lock.lock()
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            return nil
        }
        profiles[idx].name = cleanName
        profiles[idx].updatedAt = Date().timeIntervalSince1970
        let updated = profiles[idx]
        saveToDefaultsLocked()
        lock.unlock()

        if !isIsolatedInstance {
            CloudSettingsSyncService.shared.scheduleDebouncedSync(reason: "room_profile_renamed")
        }
        return updated
    }

    @discardableResult
    public func deleteProfile(id: String) -> Bool {
        lock.lock()
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            return false
        }
        let now = Date().timeIntervalSince1970
        let prevActive = activeProfileIDInternal
        let prevEnabled = correctionEnabledInternal
        profiles.remove(at: idx)
        deletedProfileTimestamps[id] = now
        pruneExpiredTombstonesLocked(now: now)
        if activeProfileIDInternal == id {
            activeProfileIDInternal = profiles.first?.id
            if activeProfileIDInternal == nil {
                correctionEnabledInternal = false
            }
        }
        if activeProfileIDInternal != prevActive || correctionEnabledInternal != prevEnabled {
            roomStateUpdatedAtInternal = now
        }
        syncFastFlagsFromStateLocked()
        saveToDefaultsLocked()
        lock.unlock()

        syncRealtimeProcessors()
        refreshLocalPassthroughEQPipeline()

        if !isIsolatedInstance {
            CloudSettingsSyncService.shared.scheduleDebouncedSync(reason: "room_profile_deleted")
        }
        return true
    }

    @discardableResult
    public func mergeCloudProfiles(
        remoteProfiles: [RoomAcousticProfile],
        remoteDeletedTimestamps: [String: TimeInterval],
        remoteCorrectionEnabled: Bool?,
        remoteActiveProfileID: String?,
        remoteStateUpdatedAt: TimeInterval? = nil
    ) -> Int {
        var importedCount = 0
        let now = Date().timeIntervalSince1970
        lock.lock()
        let hadAnyLocalProfiles = !profiles.isEmpty
        pruneExpiredTombstonesLocked(now: now)

        for (delID, delTs) in remoteDeletedTimestamps {
            guard delTs > 0, (now - delTs) <= Self.tombstoneTTLSeconds else { continue }
            let curTs = deletedProfileTimestamps[delID] ?? 0
            if delTs > curTs {
                deletedProfileTimestamps[delID] = delTs
            }
        }
        // Remove any local profile whose tombstone is newer than its updatedAt
        let countBeforeRemoval = profiles.count
        profiles.removeAll { prof in
            if let delTs = deletedProfileTimestamps[prof.id], delTs >= prof.updatedAt {
                return true
            }
            return false
        }
        importedCount += max(0, countBeforeRemoval - profiles.count)

        for remote in remoteProfiles {
            if let delTs = deletedProfileTimestamps[remote.id], delTs >= remote.updatedAt {
                continue
            }
            if let existingIdx = profiles.firstIndex(where: { $0.id == remote.id }) {
                let local = profiles[existingIdx]
                let shouldReplace: Bool
                if remote.updatedAt > local.updatedAt + 0.0001 {
                    shouldReplace = true
                } else if abs(remote.updatedAt - local.updatedAt) <= 0.0001 && remote != local {
                    shouldReplace = (remote.name, remote.preampGainDB, remote.eqBands.count) > (local.name, local.preampGainDB, local.eqBands.count)
                } else {
                    shouldReplace = false
                }
                if shouldReplace {
                    profiles[existingIdx] = remote
                    importedCount += 1
                }
            } else {
                profiles.append(remote)
                importedCount += 1
            }
        }
        profiles.sort {
            if abs($0.updatedAt - $1.updatedAt) > 0.0001 {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.id < $1.id
        }

        let prevEnabled = correctionEnabledInternal
        let prevActive = activeProfileIDInternal

        var sanitizedLocalActive = activeProfileIDInternal
        if let curActive = sanitizedLocalActive, !profiles.contains(where: { $0.id == curActive }) {
            sanitizedLocalActive = profiles.first?.id
        } else if sanitizedLocalActive == nil {
            sanitizedLocalActive = profiles.first?.id
        }
        let sanitizedLocalEnabled = (profiles.isEmpty || sanitizedLocalActive == nil) ? false : correctionEnabledInternal

        if remoteCorrectionEnabled != nil || remoteActiveProfileID != nil || remoteStateUpdatedAt != nil {
            let candActive: String? = {
                if let remActive = remoteActiveProfileID,
                   !remActive.isEmpty,
                   profiles.contains(where: { $0.id == remActive }) {
                    return remActive
                }
                return profiles.first?.id
            }()
            let rawRemEnabled = remoteCorrectionEnabled ?? sanitizedLocalEnabled
            let candEnabled = (profiles.isEmpty || candActive == nil) ? false : rawRemEnabled

            let localTs = roomStateUpdatedAtInternal
            let remTs = remoteStateUpdatedAt ?? 0.0

            let adoptRemoteState: Bool
            if !hadAnyLocalProfiles && localTs == 0 {
                adoptRemoteState = true
            } else if remTs > localTs + 0.0001 {
                adoptRemoteState = true
            } else if abs(remTs - localTs) <= 0.0001 {
                adoptRemoteState = (candEnabled ? 1 : 0, candActive ?? "") > (sanitizedLocalEnabled ? 1 : 0, sanitizedLocalActive ?? "")
            } else {
                adoptRemoteState = false
            }

            if adoptRemoteState {
                activeProfileIDInternal = candActive
                correctionEnabledInternal = candEnabled
                roomStateUpdatedAtInternal = max(localTs, remTs)
            } else {
                activeProfileIDInternal = sanitizedLocalActive
                correctionEnabledInternal = sanitizedLocalEnabled
                if abs(remTs - localTs) <= 0.0001 && candEnabled == sanitizedLocalEnabled && candActive == sanitizedLocalActive {
                    roomStateUpdatedAtInternal = max(localTs, remTs)
                }
            }
        } else {
            activeProfileIDInternal = sanitizedLocalActive
            correctionEnabledInternal = sanitizedLocalEnabled
        }

        if prevEnabled != correctionEnabledInternal || prevActive != activeProfileIDInternal {
            importedCount += 1
        }

        syncFastFlagsFromStateLocked()
        saveToDefaultsLocked()
        lock.unlock()

        syncRealtimeProcessors()
        refreshLocalPassthroughEQPipeline()
        return importedCount
    }

    public func statusDictionary() -> [String: Any] {
        let all = allProfiles()
        let active = activeProfile
        return [
            "enabled": isCorrectionEnabled,
            "is_test_signal_playing": isTestSignalPlaying,
            "active_profile_id": active?.id ?? "",
            "active_profile": active?.dictionary ?? NSNull(),
            "profiles": all.map { $0.dictionary },
            "bands_hz": Self.isoThirdOctaveBandsHz
        ]
    }

    // MARK: - Persistence

    internal func pruneExpiredTombstonesLocked(now: TimeInterval = Date().timeIntervalSince1970) {
        deletedProfileTimestamps = deletedProfileTimestamps.filter { _, ts in
            ts > 0 && (now - ts) <= Self.tombstoneTTLSeconds
        }
    }

    internal func loadFromDefaults() {
        if let data = defaults.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([RoomAcousticProfile].self, from: data) {
            self.profiles = decoded
        }
        if let tombData = defaults.data(forKey: deletedTombstonesKey),
           let decodedTomb = try? JSONDecoder().decode([String: TimeInterval].self, from: tombData) {
            self.deletedProfileTimestamps = decodedTomb
            pruneExpiredTombstonesLocked()
        }
        self.activeProfileIDInternal = defaults.string(forKey: activeProfileIDKey)
        self.correctionEnabledInternal = defaults.bool(forKey: correctionEnabledKey)
        self.roomStateUpdatedAtInternal = defaults.double(forKey: stateUpdatedAtKey)
        if activeProfileIDInternal == nil {
            activeProfileIDInternal = profiles.first?.id
        }
        if profiles.isEmpty {
            correctionEnabledInternal = false
        }
    }

    internal func saveToDefaultsLocked() {
        pruneExpiredTombstonesLocked()
        if let encoded = try? JSONEncoder().encode(profiles) {
            defaults.set(encoded, forKey: profilesKey)
        }
        if let encodedTomb = try? JSONEncoder().encode(deletedProfileTimestamps) {
            defaults.set(encodedTomb, forKey: deletedTombstonesKey)
        }
        if let activeID = activeProfileIDInternal {
            defaults.set(activeID, forKey: activeProfileIDKey)
        } else {
            defaults.removeObject(forKey: activeProfileIDKey)
        }
        defaults.set(correctionEnabledInternal, forKey: correctionEnabledKey)
        defaults.set(roomStateUpdatedAtInternal, forKey: stateUpdatedAtKey)
    }
}
