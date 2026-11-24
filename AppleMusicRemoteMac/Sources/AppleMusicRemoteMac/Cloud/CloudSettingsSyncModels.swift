//
//  CloudSettingsSyncModels.swift
//  AppleMusicRemoteMac
//
//  Error types, sync summary DTO, and canonical SHA-256 CloudSyncPayload for two-way iCloud/folder sync.
//

import CryptoKit
import Foundation

public enum CloudSyncError: LocalizedError {
    case iCloudDriveUnavailable
    case waitingForICloudDownload
    case invalidSyncDirectory(String)
    case coordinatorFailed(String)
    case snapshotTooLarge(Int)

    public var errorDescription: String? {
        switch self {
        case .iCloudDriveUnavailable:
            return "Папка iCloud Drive недоступна на этом Mac. Войдите в iCloud или выберите собственную папку синхронизации."
        case .waitingForICloudDownload:
            return "Облачный файл найден в iCloud Drive и загружается. Синхронизация завершится автоматически после скачивания."
        case .invalidSyncDirectory(let details):
            return "Не удалось подготовить папку синхронизации: \(details)"
        case .coordinatorFailed(let details):
            return "Ошибка координации доступа к облачному файлу: \(details)"
        case .snapshotTooLarge(let bytes):
            return "Файл синхронизации превышает допустимый лимит 16 МБ (\(bytes) байт)."
        }
    }
}

public struct CloudSyncSummary: Equatable, Sendable {
    public var dspPresetsChanged: Bool
    public var mergedLoudnessCount: Int
    public var mergedDynamicsCount: Int
    public var normalizationPolicyChanged: Bool
    public var roomProfilesChanged: Bool
    public var lateNightDRCChanged: Bool
    public var masteringRestorationChanged: Bool
    public var wroteRemoteUpdate: Bool
    public var totalSyncedPresets: Int
    public var totalSyncedLoudnessTracks: Int
    public var totalSyncedDynamicsTracks: Int
    public var totalSyncedRoomProfiles: Int

    public init(
        dspPresetsChanged: Bool = false,
        mergedLoudnessCount: Int = 0,
        mergedDynamicsCount: Int = 0,
        normalizationPolicyChanged: Bool = false,
        roomProfilesChanged: Bool = false,
        lateNightDRCChanged: Bool = false,
        masteringRestorationChanged: Bool = false,
        wroteRemoteUpdate: Bool = false,
        totalSyncedPresets: Int = 0,
        totalSyncedLoudnessTracks: Int = 0,
        totalSyncedDynamicsTracks: Int = 0,
        totalSyncedRoomProfiles: Int = 0
    ) {
        self.dspPresetsChanged = dspPresetsChanged
        self.mergedLoudnessCount = mergedLoudnessCount
        self.mergedDynamicsCount = mergedDynamicsCount
        self.normalizationPolicyChanged = normalizationPolicyChanged
        self.roomProfilesChanged = roomProfilesChanged
        self.lateNightDRCChanged = lateNightDRCChanged
        self.masteringRestorationChanged = masteringRestorationChanged
        self.wroteRemoteUpdate = wroteRemoteUpdate
        self.totalSyncedPresets = totalSyncedPresets
        self.totalSyncedLoudnessTracks = totalSyncedLoudnessTracks
        self.totalSyncedDynamicsTracks = totalSyncedDynamicsTracks
        self.totalSyncedRoomProfiles = totalSyncedRoomProfiles
    }

    public var hasLocalChanges: Bool {
        dspPresetsChanged || mergedLoudnessCount > 0 || mergedDynamicsCount > 0 || normalizationPolicyChanged || roomProfilesChanged || lateNightDRCChanged || masteringRestorationChanged
    }
}

public struct CloudSyncPayload: Codable, Sendable {
    public static let currentSchemaVersion: Int = 1

    public var schemaVersion: Int
    public var exportedAt: TimeInterval
    public var originHostName: String
    public var customDSPPresets: [DSPPreset]
    public var deletedDSPPresetTimestamps: [String: TimeInterval]
    public var normalizationPolicy: ExternalAmpTCPController.NormalizationPolicySyncState?
    public var trackLoudnessEntries: [String: Double]
    public var trackDynamicsEntries: [String: CachedSpectralValidation]
    public var roomAcousticProfiles: [RoomAcousticProfile]
    public var deletedRoomProfileTimestamps: [String: TimeInterval]
    public var roomCorrectionEnabled: Bool?
    public var activeRoomProfileID: String?
    public var roomStateUpdatedAt: TimeInterval?
    public var lateNightDRCMode: String?
    public var lateNightDRCEnabled: Bool?
    public var lateNightDRCProfile: String?
    public var lateNightDRCUpdatedAt: TimeInterval?
    public var masteringDeClipMode: String?
    public var masteringDeEsserMode: String?
    public var masteringRestorationUpdatedAt: TimeInterval?

    public init(
        schemaVersion: Int = CloudSyncPayload.currentSchemaVersion,
        exportedAt: TimeInterval = Date().timeIntervalSince1970,
        originHostName: String = Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
        customDSPPresets: [DSPPreset] = [],
        deletedDSPPresetTimestamps: [String: TimeInterval] = [:],
        normalizationPolicy: ExternalAmpTCPController.NormalizationPolicySyncState? = nil,
        trackLoudnessEntries: [String: Double] = [:],
        trackDynamicsEntries: [String: CachedSpectralValidation] = [:],
        roomAcousticProfiles: [RoomAcousticProfile] = [],
        deletedRoomProfileTimestamps: [String: TimeInterval] = [:],
        roomCorrectionEnabled: Bool? = nil,
        activeRoomProfileID: String? = nil,
        lateNightDRCMode: String? = nil,
        lateNightDRCEnabled: Bool? = nil,
        lateNightDRCProfile: String? = nil,
        lateNightDRCUpdatedAt: TimeInterval? = nil,
        masteringDeClipMode: String? = nil,
        masteringDeEsserMode: String? = nil,
        masteringRestorationUpdatedAt: TimeInterval? = nil,
        roomStateUpdatedAt: TimeInterval? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.originHostName = originHostName
        self.customDSPPresets = customDSPPresets
        self.deletedDSPPresetTimestamps = deletedDSPPresetTimestamps
        self.normalizationPolicy = normalizationPolicy
        self.trackLoudnessEntries = trackLoudnessEntries
        self.trackDynamicsEntries = trackDynamicsEntries
        self.roomAcousticProfiles = roomAcousticProfiles
        self.deletedRoomProfileTimestamps = deletedRoomProfileTimestamps
        self.roomCorrectionEnabled = roomCorrectionEnabled
        self.activeRoomProfileID = activeRoomProfileID
        self.roomStateUpdatedAt = roomStateUpdatedAt
        self.lateNightDRCMode = lateNightDRCMode
        self.lateNightDRCEnabled = lateNightDRCEnabled
        self.lateNightDRCProfile = lateNightDRCProfile
        self.lateNightDRCUpdatedAt = lateNightDRCUpdatedAt
        self.masteringDeClipMode = masteringDeClipMode
        self.masteringDeEsserMode = masteringDeEsserMode
        self.masteringRestorationUpdatedAt = masteringRestorationUpdatedAt
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case exportedAt
        case originHostName
        case customDSPPresets
        case deletedDSPPresetTimestamps
        case normalizationPolicy
        case trackLoudnessEntries
        case trackDynamicsEntries
        case roomAcousticProfiles
        case deletedRoomProfileTimestamps
        case roomCorrectionEnabled
        case activeRoomProfileID
        case roomStateUpdatedAt
        case lateNightDRCMode
        case lateNightDRCEnabled
        case lateNightDRCProfile
        case lateNightDRCUpdatedAt
        case masteringDeClipMode
        case masteringDeEsserMode
        case masteringRestorationUpdatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        self.exportedAt = try c.decodeIfPresent(TimeInterval.self, forKey: .exportedAt) ?? 0
        self.originHostName = try c.decodeIfPresent(String.self, forKey: .originHostName) ?? ""
        self.customDSPPresets = try c.decodeIfPresent([DSPPreset].self, forKey: .customDSPPresets) ?? []
        self.deletedDSPPresetTimestamps = try c.decodeIfPresent([String: TimeInterval].self, forKey: .deletedDSPPresetTimestamps) ?? [:]
        self.normalizationPolicy = try c.decodeIfPresent(ExternalAmpTCPController.NormalizationPolicySyncState.self, forKey: .normalizationPolicy)
        self.trackLoudnessEntries = try c.decodeIfPresent([String: Double].self, forKey: .trackLoudnessEntries) ?? [:]
        self.trackDynamicsEntries = try c.decodeIfPresent([String: CachedSpectralValidation].self, forKey: .trackDynamicsEntries) ?? [:]
        self.roomAcousticProfiles = try c.decodeIfPresent([RoomAcousticProfile].self, forKey: .roomAcousticProfiles) ?? []
        self.deletedRoomProfileTimestamps = try c.decodeIfPresent([String: TimeInterval].self, forKey: .deletedRoomProfileTimestamps) ?? [:]
        self.roomCorrectionEnabled = try c.decodeIfPresent(Bool.self, forKey: .roomCorrectionEnabled)
        self.activeRoomProfileID = try c.decodeIfPresent(String.self, forKey: .activeRoomProfileID)
        self.roomStateUpdatedAt = try c.decodeIfPresent(TimeInterval.self, forKey: .roomStateUpdatedAt)
        self.lateNightDRCMode = try c.decodeIfPresent(String.self, forKey: .lateNightDRCMode)
        self.lateNightDRCEnabled = try c.decodeIfPresent(Bool.self, forKey: .lateNightDRCEnabled)
        self.lateNightDRCProfile = try c.decodeIfPresent(String.self, forKey: .lateNightDRCProfile)
        self.lateNightDRCUpdatedAt = try c.decodeIfPresent(TimeInterval.self, forKey: .lateNightDRCUpdatedAt)
        self.masteringDeClipMode = try c.decodeIfPresent(String.self, forKey: .masteringDeClipMode)
        self.masteringDeEsserMode = try c.decodeIfPresent(String.self, forKey: .masteringDeEsserMode)
        self.masteringRestorationUpdatedAt = try c.decodeIfPresent(TimeInterval.self, forKey: .masteringRestorationUpdatedAt)
    }

    /// Детерминированный SHA-256 отпечаток семантических данных (без `exportedAt` и `originHostName`),
    /// предотвращающий бесконечную перезапись облачного файла между несколькими Mac.
    public func contentDigest() -> String {
        struct CanonicalPayload: Encodable {
            let schemaVersion: Int
            let customDSPPresets: [DSPPreset]
            let deletedDSPPresetTimestamps: [String: TimeInterval]
            let normalizationPolicy: ExternalAmpTCPController.NormalizationPolicySyncState?
            let trackLoudnessEntries: [String: Double]
            let trackDynamicsEntries: [String: CachedSpectralValidation]
            let roomAcousticProfiles: [RoomAcousticProfile]
            let deletedRoomProfileTimestamps: [String: TimeInterval]
            let roomCorrectionEnabled: Bool?
            let activeRoomProfileID: String?
            let roomStateUpdatedAt: TimeInterval?
            let lateNightDRCMode: String?
            let lateNightDRCEnabled: Bool?
            let lateNightDRCProfile: String?
            let lateNightDRCUpdatedAt: TimeInterval?
            let masteringDeClipMode: String?
            let masteringDeEsserMode: String?
            let masteringRestorationUpdatedAt: TimeInterval?
        }
        let sortedPresets = customDSPPresets.sorted { $0.id < $1.id }
        let sortedRoomProfiles = roomAcousticProfiles.sorted { $0.id < $1.id }
        let roundedDSPDeleted = deletedDSPPresetTimestamps.mapValues { ($0 * 1000.0).rounded() / 1000.0 }
        let roundedRoomDeleted = deletedRoomProfileTimestamps.mapValues { ($0 * 1000.0).rounded() / 1000.0 }
        let roundedPolicy: ExternalAmpTCPController.NormalizationPolicySyncState? = normalizationPolicy.map {
            var copy = $0
            copy.updatedAt = ($0.updatedAt * 1000.0).rounded() / 1000.0
            return copy
        }
        let roundedLoudness = trackLoudnessEntries.mapValues { ($0 * 10_000.0).rounded() / 10_000.0 }
        let roundedRoomUpdatedAt = roomStateUpdatedAt.map { ($0 * 1000.0).rounded() / 1000.0 }
        let roundedDRCUpdatedAt = lateNightDRCUpdatedAt.map { ($0 * 1000.0).rounded() / 1000.0 }
        let roundedMasteringUpdatedAt = masteringRestorationUpdatedAt.map { ($0 * 1000.0).rounded() / 1000.0 }
        let canonical = CanonicalPayload(
            schemaVersion: schemaVersion,
            customDSPPresets: sortedPresets,
            deletedDSPPresetTimestamps: roundedDSPDeleted,
            normalizationPolicy: roundedPolicy,
            trackLoudnessEntries: roundedLoudness,
            trackDynamicsEntries: trackDynamicsEntries,
            roomAcousticProfiles: sortedRoomProfiles,
            deletedRoomProfileTimestamps: roundedRoomDeleted,
            roomCorrectionEnabled: roomCorrectionEnabled,
            activeRoomProfileID: activeRoomProfileID,
            roomStateUpdatedAt: roundedRoomUpdatedAt,
            lateNightDRCMode: lateNightDRCMode,
            lateNightDRCEnabled: lateNightDRCEnabled,
            lateNightDRCProfile: lateNightDRCProfile,
            lateNightDRCUpdatedAt: roundedDRCUpdatedAt,
            masteringDeClipMode: masteringDeClipMode,
            masteringDeEsserMode: masteringDeEsserMode,
            masteringRestorationUpdatedAt: roundedMasteringUpdatedAt
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(canonical) else {
            return UUID().uuidString
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
