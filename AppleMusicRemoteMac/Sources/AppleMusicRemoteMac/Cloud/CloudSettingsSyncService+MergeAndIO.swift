//
//  CloudSettingsSyncService+MergeAndIO.swift
//  AppleMusicRemoteMac
//
//  Atomic single-coordinator two-way merge engine, manual snapshot export/import,
//  16 MB file-size validation, and 0600 POSIX permission enforcement.
//

import Darwin
import Foundation

extension CloudSettingsSyncService {

    // MARK: - Core Two-Way Coordinated Merge Engine (Unit-Testable)

    @discardableResult
    public static func performTwoWaySync(
        fileURL: URL,
        dspManager: DSPPresetManager,
        soundCheckService: AppleSoundCheckService,
        spectralAnalyzer: SpectralIntegrityAnalyzer,
        normPolicyProvider: () -> ExternalAmpTCPController.NormalizationPolicySyncState?,
        normPolicyMerger: (ExternalAmpTCPController.NormalizationPolicySyncState) -> Bool,
        roomService: RoomAcousticService? = nil,
        lateNightService: LateNightDRCService? = nil,
        masteringService: MasteringRestorationService? = nil,
        onLocalWrite: (() -> Void)? = nil
    ) throws -> CloudSyncSummary {
        let fm = FileManager.default
        let dirURL = fileURL.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        } catch {
            throw CloudSyncError.invalidSyncDirectory(error.localizedDescription)
        }

        // Проверяем выгруженный облачный плейсхолдер `.<name>.icloud` до захвата координации
        try ensureUbiquitousFileDownloaded(at: fileURL)

        var coordError: NSError?
        var innerError: Error?
        var resultSummary = CloudSyncSummary()
        let coordinator = NSFileCoordinator(filePresenter: nil)

        // Single coordinated read-for-writing block closes TOCTOU window between read and conditional write
        coordinator.coordinate(
            readingItemAt: fileURL,
            options: [],
            writingItemAt: fileURL,
            options: .forReplacing,
            error: &coordError
        ) { readURL, writeURL in
            do {
                try ensureUbiquitousFileDownloaded(at: readURL)

                var remoteDigest: String?
                var dspChanged = false
                var mergedLoudness = 0
                var mergedDynamics = 0
                var normPolicyChanged = false
                var roomChanged = false
                var lateNightChanged = false
                var masteringChanged = false
                var preservedRoomProfiles: [RoomAcousticProfile] = []
                var preservedDeletedRoomTs: [String: TimeInterval] = [:]
                var preservedRoomEnabled: Bool? = nil
                var preservedActiveRoomID: String? = nil
                var preservedRoomStateUpdatedAt: TimeInterval? = nil
                var preservedLateNightMode: String? = nil
                var preservedLateNightEnabled: Bool? = nil
                var preservedLateNightProfile: String? = nil
                var preservedLateNightUpdatedAt: TimeInterval? = nil
                var preservedMasteringDeClip: String? = nil
                var preservedMasteringDeEsser: String? = nil
                var preservedMasteringUpdatedAt: TimeInterval? = nil

                if fm.fileExists(atPath: readURL.path) {
                    try validateSnapshotFileSize(at: readURL)
                    let remoteData = try Data(contentsOf: readURL)
                    if remoteData.count > maxSnapshotFileSizeBytes {
                        throw CloudSyncError.snapshotTooLarge(remoteData.count)
                    }
                    if !remoteData.isEmpty {
                        let remotePayload = try JSONDecoder().decode(CloudSyncPayload.self, from: remoteData)
                        remoteDigest = remotePayload.contentDigest()

                        dspChanged = dspManager.mergeCloudSyncState(
                            remotePresets: remotePayload.customDSPPresets,
                            remoteDeletedTimestamps: remotePayload.deletedDSPPresetTimestamps
                        )
                        mergedLoudness = soundCheckService.mergeCloudSyncLoudnessEntries(remotePayload.trackLoudnessEntries)
                        mergedDynamics = spectralAnalyzer.mergeCloudSyncValidations(remotePayload.trackDynamicsEntries)
                        if let remotePolicy = remotePayload.normalizationPolicy {
                            normPolicyChanged = normPolicyMerger(remotePolicy)
                        }
                        if let roomService {
                            let importedRoom = roomService.mergeCloudProfiles(
                                remoteProfiles: remotePayload.roomAcousticProfiles,
                                remoteDeletedTimestamps: remotePayload.deletedRoomProfileTimestamps,
                                remoteCorrectionEnabled: remotePayload.roomCorrectionEnabled,
                                remoteActiveProfileID: remotePayload.activeRoomProfileID,
                                remoteStateUpdatedAt: remotePayload.roomStateUpdatedAt
                            )
                            roomChanged = (importedRoom > 0)
                        } else {
                            preservedRoomProfiles = remotePayload.roomAcousticProfiles
                            preservedDeletedRoomTs = remotePayload.deletedRoomProfileTimestamps
                            preservedRoomEnabled = remotePayload.roomCorrectionEnabled
                            preservedActiveRoomID = remotePayload.activeRoomProfileID
                            preservedRoomStateUpdatedAt = remotePayload.roomStateUpdatedAt
                        }
                        if let lateNightService {
                            lateNightChanged = lateNightService.mergeCloudState(
                                remoteModeRaw: remotePayload.lateNightDRCMode,
                                remoteEnabled: remotePayload.lateNightDRCEnabled,
                                remoteProfileRaw: remotePayload.lateNightDRCProfile,
                                remoteUpdatedAt: remotePayload.lateNightDRCUpdatedAt
                            )
                        } else {
                            preservedLateNightMode = remotePayload.lateNightDRCMode
                            preservedLateNightEnabled = remotePayload.lateNightDRCEnabled
                            preservedLateNightProfile = remotePayload.lateNightDRCProfile
                            preservedLateNightUpdatedAt = remotePayload.lateNightDRCUpdatedAt
                        }
                        if let masteringService {
                            masteringChanged = masteringService.mergeCloudState(
                                remoteDeClipRaw: remotePayload.masteringDeClipMode,
                                remoteDeEsserRaw: remotePayload.masteringDeEsserMode,
                                remoteUpdatedAt: remotePayload.masteringRestorationUpdatedAt
                            )
                        } else {
                            preservedMasteringDeClip = remotePayload.masteringDeClipMode
                            preservedMasteringDeEsser = remotePayload.masteringDeEsserMode
                            preservedMasteringUpdatedAt = remotePayload.masteringRestorationUpdatedAt
                        }
                    }
                }

                let exportedDSP = dspManager.exportCloudSyncState()
                let exportedLoudness = soundCheckService.exportCloudSyncLoudnessEntries()
                let exportedDynamics = spectralAnalyzer.exportCloudSyncValidations()
                let exportedPolicy = normPolicyProvider()
                let exportedRoomProfiles = roomService?.allProfiles() ?? preservedRoomProfiles
                let exportedDeletedRoomTs = roomService?.deletedProfileTombstonesSnapshot() ?? preservedDeletedRoomTs
                let exportedRoomEnabled = roomService.map { $0.isCorrectionEnabled } ?? preservedRoomEnabled
                let exportedActiveRoomID = roomService != nil ? roomService?.activeProfileID : preservedActiveRoomID
                let exportedRoomStateUpdatedAt = roomService.map { $0.roomStateUpdatedAt } ?? preservedRoomStateUpdatedAt
                let exportedLateNightMode = lateNightService.map { $0.mode.rawValue } ?? preservedLateNightMode
                let exportedLateNightEnabled = lateNightService.map { $0.isEnabled } ?? preservedLateNightEnabled
                let exportedLateNightProfile = lateNightService.map { $0.selectedProfile.rawValue } ?? preservedLateNightProfile
                let exportedLateNightUpdatedAt = lateNightService.map { $0.updatedAt } ?? preservedLateNightUpdatedAt
                let exportedMasteringDeClip = masteringService.map { $0.deClipMode.rawValue } ?? preservedMasteringDeClip
                let exportedMasteringDeEsser = masteringService.map { $0.deEsserMode.rawValue } ?? preservedMasteringDeEsser
                let exportedMasteringUpdatedAt = masteringService.map { $0.updatedAt } ?? preservedMasteringUpdatedAt

                let unifiedPayload = CloudSyncPayload(
                    schemaVersion: CloudSyncPayload.currentSchemaVersion,
                    exportedAt: Date().timeIntervalSince1970,
                    originHostName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
                    customDSPPresets: exportedDSP.customPresets,
                    deletedDSPPresetTimestamps: exportedDSP.deletedTimestamps,
                    normalizationPolicy: exportedPolicy,
                    trackLoudnessEntries: exportedLoudness,
                    trackDynamicsEntries: exportedDynamics,
                    roomAcousticProfiles: exportedRoomProfiles,
                    deletedRoomProfileTimestamps: exportedDeletedRoomTs,
                    roomCorrectionEnabled: exportedRoomEnabled,
                    activeRoomProfileID: exportedActiveRoomID,
                    lateNightDRCMode: exportedLateNightMode,
                    lateNightDRCEnabled: exportedLateNightEnabled,
                    lateNightDRCProfile: exportedLateNightProfile,
                    lateNightDRCUpdatedAt: exportedLateNightUpdatedAt,
                    masteringDeClipMode: exportedMasteringDeClip,
                    masteringDeEsserMode: exportedMasteringDeEsser,
                    masteringRestorationUpdatedAt: exportedMasteringUpdatedAt,
                    roomStateUpdatedAt: exportedRoomStateUpdatedAt
                )

                let localDigest = unifiedPayload.contentDigest()
                var wroteRemote = false
                if remoteDigest != localDigest {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let encoded = try encoder.encode(unifiedPayload)
                    onLocalWrite?()
                    try writeSnapshotAtomicallyWith0600(encoded, to: writeURL)
                    wroteRemote = true
                }

                resultSummary = CloudSyncSummary(
                    dspPresetsChanged: dspChanged,
                    mergedLoudnessCount: mergedLoudness,
                    mergedDynamicsCount: mergedDynamics,
                    normalizationPolicyChanged: normPolicyChanged,
                    roomProfilesChanged: roomChanged,
                    lateNightDRCChanged: lateNightChanged,
                    masteringRestorationChanged: masteringChanged,
                    wroteRemoteUpdate: wroteRemote,
                    totalSyncedPresets: exportedDSP.customPresets.count,
                    totalSyncedLoudnessTracks: exportedLoudness.count,
                    totalSyncedDynamicsTracks: exportedDynamics.count,
                    totalSyncedRoomProfiles: exportedRoomProfiles.count
                )
            } catch {
                innerError = error
            }
        }

        if let coordError {
            throw CloudSyncError.coordinatorFailed(coordError.localizedDescription)
        }
        if let innerError {
            throw innerError
        }
        return resultSummary
    }

    // MARK: - Manual Export / Import

    @discardableResult
    public func exportSnapshot(to destinationURL: URL) throws -> CloudSyncPayload {
        try runSyncOnSyncQueue {
            let exportedDSP = DSPPresetManager.shared.exportCloudSyncState()
            let exportedLoudness = AppleSoundCheckService.shared.exportCloudSyncLoudnessEntries()
            let exportedDynamics = SpectralIntegrityAnalyzer.shared.exportCloudSyncValidations()
            let exportedPolicy = ExternalAmpTCPController.shared.exportNormalizationPolicy()
            let exportedRoomProfiles = RoomAcousticService.shared.allProfiles()
            let exportedDeletedRoomTs = RoomAcousticService.shared.deletedProfileTombstonesSnapshot()

            let payload = CloudSyncPayload(
                schemaVersion: CloudSyncPayload.currentSchemaVersion,
                exportedAt: Date().timeIntervalSince1970,
                originHostName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
                customDSPPresets: exportedDSP.customPresets,
                deletedDSPPresetTimestamps: exportedDSP.deletedTimestamps,
                normalizationPolicy: exportedPolicy,
                trackLoudnessEntries: exportedLoudness,
                trackDynamicsEntries: exportedDynamics,
                roomAcousticProfiles: exportedRoomProfiles,
                deletedRoomProfileTimestamps: exportedDeletedRoomTs,
                roomCorrectionEnabled: RoomAcousticService.shared.isCorrectionEnabled,
                activeRoomProfileID: RoomAcousticService.shared.activeProfileID,
                lateNightDRCMode: LateNightDRCService.shared.mode.rawValue,
                lateNightDRCEnabled: LateNightDRCService.shared.isEnabled,
                lateNightDRCProfile: LateNightDRCService.shared.selectedProfile.rawValue,
                lateNightDRCUpdatedAt: LateNightDRCService.shared.updatedAt,
                masteringDeClipMode: MasteringRestorationService.shared.deClipMode.rawValue,
                masteringDeEsserMode: MasteringRestorationService.shared.deEsserMode.rawValue,
                masteringRestorationUpdatedAt: MasteringRestorationService.shared.updatedAt,
                roomStateUpdatedAt: RoomAcousticService.shared.roomStateUpdatedAt
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try writeDataCoordinated(data, to: destinationURL)
            return payload
        }
    }

    @discardableResult
    public func importSnapshot(from sourceURL: URL) throws -> CloudSyncSummary {
        let (summary, dspChanged, lateNightOrMasteringChanged, roomChanged, normChanged): (CloudSyncSummary, Bool, Bool, Bool, Bool) = try runSyncOnSyncQueue {
            stateLock.withLock { _isPerformingMerge = true }
            defer { stateLock.withLock { _isPerformingMerge = false } }

            try Self.ensureUbiquitousFileDownloaded(at: sourceURL)
            try Self.validateSnapshotFileSize(at: sourceURL)
            let data = try Self.readDataCoordinated(from: sourceURL)
            let payload = try JSONDecoder().decode(CloudSyncPayload.self, from: data)

            let dspChanged = DSPPresetManager.shared.mergeCloudSyncState(
                remotePresets: payload.customDSPPresets,
                remoteDeletedTimestamps: payload.deletedDSPPresetTimestamps
            )
            let mergedLoudness = AppleSoundCheckService.shared.mergeCloudSyncLoudnessEntries(payload.trackLoudnessEntries)
            let mergedDynamics = SpectralIntegrityAnalyzer.shared.mergeCloudSyncValidations(payload.trackDynamicsEntries)
            let normChanged = payload.normalizationPolicy.map { ExternalAmpTCPController.shared.mergeNormalizationPolicy($0) } ?? false
            let importedRoom = RoomAcousticService.shared.mergeCloudProfiles(
                remoteProfiles: payload.roomAcousticProfiles,
                remoteDeletedTimestamps: payload.deletedRoomProfileTimestamps,
                remoteCorrectionEnabled: payload.roomCorrectionEnabled,
                remoteActiveProfileID: payload.activeRoomProfileID,
                remoteStateUpdatedAt: payload.roomStateUpdatedAt
            )
            let roomChanged = (importedRoom > 0)
            let lateNightChanged = LateNightDRCService.shared.mergeCloudState(
                remoteModeRaw: payload.lateNightDRCMode,
                remoteEnabled: payload.lateNightDRCEnabled,
                remoteProfileRaw: payload.lateNightDRCProfile,
                remoteUpdatedAt: payload.lateNightDRCUpdatedAt
            )
            let masteringChanged = MasteringRestorationService.shared.mergeCloudState(
                remoteDeClipRaw: payload.masteringDeClipMode,
                remoteDeEsserRaw: payload.masteringDeEsserMode,
                remoteUpdatedAt: payload.masteringRestorationUpdatedAt
            )

            let exportedDSP = DSPPresetManager.shared.exportCloudSyncState()
            let exportedLoudness = AppleSoundCheckService.shared.exportCloudSyncLoudnessEntries()
            let exportedDynamics = SpectralIntegrityAnalyzer.shared.exportCloudSyncValidations()
            let exportedRoom = RoomAcousticService.shared.allProfiles()

            let summary = CloudSyncSummary(
                dspPresetsChanged: dspChanged,
                mergedLoudnessCount: mergedLoudness,
                mergedDynamicsCount: mergedDynamics,
                normalizationPolicyChanged: normChanged,
                roomProfilesChanged: roomChanged,
                lateNightDRCChanged: lateNightChanged,
                masteringRestorationChanged: masteringChanged,
                wroteRemoteUpdate: false,
                totalSyncedPresets: exportedDSP.customPresets.count,
                totalSyncedLoudnessTracks: exportedLoudness.count,
                totalSyncedDynamicsTracks: exportedDynamics.count,
                totalSyncedRoomProfiles: exportedRoom.count
            )

            stateLock.withLock {
                _lastSummary = summary
                _lastErrorMessage = nil
            }
            return (summary, dspChanged, lateNightChanged || masteringChanged, roomChanged, normChanged)
        }

        if summary.hasLocalChanges && !Self.isTestingEnvironment {
            broadcastLocalStateRefresh(
                dspChanged: dspChanged || lateNightOrMasteringChanged,
                roomChanged: roomChanged,
                normalizationPolicyChanged: normChanged
            )
        }
        if isEnabled && !Self.isTestingEnvironment {
            syncNow(reason: "post_manual_import")
        } else {
            notifyStatusChanged()
        }
        return summary
    }

    // MARK: - Coordinated File IO & Safety Guards

    internal static func ensureUbiquitousFileDownloaded(at fileURL: URL) throws {
        let fm = FileManager.default
        let dirURL = fileURL.deletingLastPathComponent()
        let placeholderURL = dirURL.appendingPathComponent(".\(fileURL.lastPathComponent).icloud", isDirectory: false)
        if fm.fileExists(atPath: placeholderURL.path) && !fm.fileExists(atPath: fileURL.path) {
            try? fm.startDownloadingUbiquitousItem(at: placeholderURL)
            try? fm.startDownloadingUbiquitousItem(at: fileURL)
            throw CloudSyncError.waitingForICloudDownload
        }
        var checkURL = fileURL
        checkURL.removeCachedResourceValue(forKey: .ubiquitousItemDownloadingStatusKey)
        if let resourceValues = try? checkURL.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
           resourceValues.isUbiquitousItem == true,
           resourceValues.ubiquitousItemDownloadingStatus == .notDownloaded {
            try? fm.startDownloadingUbiquitousItem(at: fileURL)
            throw CloudSyncError.waitingForICloudDownload
        }
    }

    internal static func validateSnapshotFileSize(at url: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        if let attrs = try? fm.attributesOfItem(atPath: url.path),
           let sizeNum = attrs[.size] as? NSNumber {
            let bytes = sizeNum.int64Value
            if bytes > Int64(maxSnapshotFileSizeBytes) {
                throw CloudSyncError.snapshotTooLarge(Int(min(bytes, Int64(Int.max))))
            }
        }
    }

    internal static func writeSnapshotAtomicallyWith0600(_ data: Data, to destinationURL: URL) throws {
        try data.write(to: destinationURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: destinationURL.path
        )
        _ = Darwin.chmod(destinationURL.path, mode_t(0o600))
    }

    internal static func readDataCoordinated(from url: URL) throws -> Data {
        var coordError: NSError?
        var ioError: Error?
        var resultData = Data()
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordError) { coordinatedURL in
            do {
                try validateSnapshotFileSize(at: coordinatedURL)
                let loaded = try Data(contentsOf: coordinatedURL)
                if loaded.count > maxSnapshotFileSizeBytes {
                    throw CloudSyncError.snapshotTooLarge(loaded.count)
                }
                resultData = loaded
            } catch {
                ioError = error
            }
        }
        if let coordError {
            throw CloudSyncError.coordinatorFailed(coordError.localizedDescription)
        }
        if let ioError {
            throw ioError
        }
        return resultData
    }

    internal static func writeDataCoordinated(_ data: Data, to url: URL) throws {
        var coordError: NSError?
        var ioError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { coordinatedURL in
            do {
                try writeSnapshotAtomicallyWith0600(data, to: coordinatedURL)
            } catch {
                ioError = error
            }
        }
        if let coordError {
            throw CloudSyncError.coordinatorFailed(coordError.localizedDescription)
        }
        if let ioError {
            throw ioError
        }
    }

    internal func writeDataCoordinated(_ data: Data, to url: URL) throws {
        try Self.writeDataCoordinated(data, to: url)
    }
}
