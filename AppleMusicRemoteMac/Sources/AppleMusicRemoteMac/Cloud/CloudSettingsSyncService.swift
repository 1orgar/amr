//
//  CloudSettingsSyncService.swift
//  AppleMusicRemoteMac
//
//  Двусторонняя облачная синхронизация пользовательских пресетов DSP
//  и параметров нормализации треков через iCloud Drive (NSFileCoordinator)
//  либо выбранную пользователем облачную папку (Dropbox / Syncthing / NAS).
//

import Darwin
import Foundation

public final class CloudSettingsSyncService: @unchecked Sendable {
    public static let shared = CloudSettingsSyncService()

    public static let cloudFileName = "amr_cloud_sync_v1.json"
    public static let defaultSubfolderName = "AppleMusicRemote"
    public static let maxSnapshotFileSizeBytes: Int = 16 * 1024 * 1024

    internal let kEnabledKey = "amr.cloud_sync.enabled.v1"
    internal let kCustomFolderPathKey = "amr.cloud_sync.custom_folder_path.v1"
    internal let kLastSyncTimestampKey = "amr.cloud_sync.last_sync_ts.v1"

    internal static let syncQueueSpecificKey = DispatchSpecificKey<UInt8>()
    internal let stateLock = NSLock()
    internal let syncQueue = DispatchQueue(label: "com.amr.cloud-settings-sync", qos: .utility)

    internal var _isEnabled: Bool
    internal var _customFolderPath: String?
    internal var _lastSyncTimestamp: TimeInterval
    internal var _lastSummary: CloudSyncSummary?
    internal var _lastErrorMessage: String?
    internal var _isSyncing: Bool = false
    internal var _isPerformingMerge: Bool = false
    internal var _lastLocalWriteTime: TimeInterval = 0
    internal var _onStatusChanged: (() -> Void)?

    internal var debounceWorkItem: DispatchWorkItem?
    internal var folderMonitorFD: Int32 = -1
    internal var folderMonitorSource: DispatchSourceFileSystemObject?
    internal var periodicSyncTimer: DispatchSourceTimer?

    /// Вызывается на `@MainActor` при изменении состояния облачной синхронизации (потокобезопасно).
    public var onStatusChanged: (() -> Void)? {
        get { stateLock.withLock { _onStatusChanged } }
        set { stateLock.withLock { _onStatusChanged = newValue } }
    }

    public static var isTestingEnvironment: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        NSClassFromString("XCTestCase") != nil
    }

    private init() {
        syncQueue.setSpecific(key: Self.syncQueueSpecificKey, value: 1)
        let defaults = UserDefaults.standard
        _isEnabled = defaults.bool(forKey: kEnabledKey)
        let rawCustom = defaults.string(forKey: kCustomFolderPathKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        _customFolderPath = (rawCustom?.isEmpty == false) ? rawCustom : nil
        _lastSyncTimestamp = defaults.double(forKey: kLastSyncTimestampKey)
    }

    internal func runSyncOnSyncQueue<T>(_ block: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: Self.syncQueueSpecificKey) != nil {
            return try block()
        }
        return try syncQueue.sync(execute: block)
    }

    // MARK: - Preferences & Paths

    public static var defaultICloudDriveRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Mobile Documents", isDirectory: true)
            .appendingPathComponent("com~apple~CloudDocs", isDirectory: true)
    }

    public static var defaultICloudSyncFolderURL: URL {
        defaultICloudDriveRootURL.appendingPathComponent(defaultSubfolderName, isDirectory: true)
    }

    public var isEnabled: Bool {
        get { stateLock.withLock { _isEnabled } }
        set {
            let changed: Bool = stateLock.withLock {
                guard _isEnabled != newValue else { return false }
                _isEnabled = newValue
                if !newValue {
                    _lastErrorMessage = nil
                }
                return true
            }
            guard changed else { return }
            if !Self.isTestingEnvironment {
                UserDefaults.standard.set(newValue, forKey: kEnabledKey)
            }
            if newValue {
                startIfEnabled()
                syncNow(reason: "enabled_toggle")
            } else {
                stopMonitoring()
                notifyStatusChanged()
            }
        }
    }

    public var customFolderPath: String? {
        get { stateLock.withLock { _customFolderPath } }
        set {
            let normalized: String? = {
                guard let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !trimmed.isEmpty else { return nil }
                return (trimmed as NSString).expandingTildeInPath
            }()
            let (changed, currentlyEnabled): (Bool, Bool) = stateLock.withLock {
                guard _customFolderPath != normalized else { return (false, _isEnabled) }
                _customFolderPath = normalized
                _lastErrorMessage = nil
                return (true, _isEnabled)
            }
            guard changed else { return }
            if !Self.isTestingEnvironment {
                if let normalized {
                    UserDefaults.standard.set(normalized, forKey: kCustomFolderPathKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: kCustomFolderPathKey)
                }
            }
            if currentlyEnabled {
                restartDirectoryMonitoring()
                syncNow(reason: "folder_changed")
            } else {
                notifyStatusChanged()
            }
        }
    }

    public var isSyncing: Bool {
        stateLock.withLock { _isSyncing }
    }

    public var lastSyncTimestamp: TimeInterval {
        stateLock.withLock { _lastSyncTimestamp }
    }

    public var lastErrorMessage: String? {
        stateLock.withLock { _lastErrorMessage }
    }

    public var lastSummary: CloudSyncSummary? {
        stateLock.withLock { _lastSummary }
    }

    public func resolvedSyncDirectoryURL() -> URL {
        if let custom = customFolderPath, !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return Self.defaultICloudSyncFolderURL
    }

    public func resolvedSyncFileURL() -> URL {
        resolvedSyncDirectoryURL().appendingPathComponent(Self.cloudFileName, isDirectory: false)
    }

    public var usesDefaultICloudDrive: Bool {
        customFolderPath == nil
    }

    public var isICloudDriveSignedIn: Bool {
        guard FileManager.default.ubiquityIdentityToken != nil else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: Self.defaultICloudDriveRootURL.path, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: - Lifecycle & File Monitoring

    public func startIfEnabled() {
        guard !Self.isTestingEnvironment else { return }
        guard isEnabled else { return }
        restartDirectoryMonitoring()
        syncIfEnabled(reason: "startup")
    }

    public func stopMonitoring() {
        syncQueue.async { [weak self] in
            self?.debounceWorkItem?.cancel()
            self?.debounceWorkItem = nil
            self?.teardownWatcherOnQueue()
        }
    }

    private func restartDirectoryMonitoring() {
        guard !Self.isTestingEnvironment else { return }
        syncQueue.async { [weak self] in
            guard let self else { return }
            self.teardownWatcherOnQueue()
            guard self.isEnabled else { return }

            let dirURL = self.resolvedSyncDirectoryURL()
            if self.usesDefaultICloudDrive {
                guard self.isICloudDriveSignedIn else {
                    return
                }
            }
            try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

            let fd = open(dirURL.path, O_EVTONLY)
            if fd >= 0 {
                self.folderMonitorFD = fd
                let source = DispatchSource.makeFileSystemObjectSource(
                    fileDescriptor: fd,
                    eventMask: [.write, .rename, .attrib, .extend],
                    queue: self.syncQueue
                )
                source.setEventHandler { [weak self] in
                    guard let self else { return }
                    let sinceWrite = Date().timeIntervalSince1970 - self.stateLock.withLock { self._lastLocalWriteTime }
                    guard sinceWrite > 1.8 else { return }
                    self.scheduleDebouncedSyncOnQueue(delay: 1.5, reason: "fs_watcher")
                }
                source.setCancelHandler {
                    close(fd)
                }
                self.folderMonitorSource = source
                source.resume()
            }

            let timer = DispatchSource.makeTimerSource(queue: self.syncQueue)
            timer.schedule(deadline: .now() + 60.0, repeating: 60.0, leeway: .seconds(10))
            timer.setEventHandler { [weak self] in
                guard let self, self.isEnabled else { return }
                self.executeSyncOnQueue(reason: "periodic", completion: nil)
            }
            self.periodicSyncTimer = timer
            timer.resume()
        }
    }

    private func teardownWatcherOnQueue() {
        periodicSyncTimer?.cancel()
        periodicSyncTimer = nil
        if let source = folderMonitorSource {
            source.cancel()
            folderMonitorSource = nil
            folderMonitorFD = -1
        } else if folderMonitorFD >= 0 {
            close(folderMonitorFD)
            folderMonitorFD = -1
        }
    }

    // MARK: - Triggers

    public func schedulePush(reason: String) {
        guard !Self.isTestingEnvironment else { return }
        let shouldSchedule: Bool = stateLock.withLock {
            _isEnabled && !_isPerformingMerge
        }
        guard shouldSchedule else { return }
        syncQueue.async { [weak self] in
            self?.scheduleDebouncedSyncOnQueue(delay: 2.5, reason: reason)
        }
    }

    public func scheduleDebouncedSync(reason: String) {
        schedulePush(reason: reason)
    }

    public func syncIfEnabled(reason: String) {
        guard !Self.isTestingEnvironment else { return }
        guard isEnabled else { return }
        syncNow(reason: reason, completion: nil)
    }

    public func syncNow(
        reason: String = "manual",
        completion: (@Sendable (Result<CloudSyncSummary, Error>) -> Void)? = nil
    ) {
        syncQueue.async { [weak self] in
            guard let self else { return }
            self.debounceWorkItem?.cancel()
            self.debounceWorkItem = nil
            self.executeSyncOnQueue(reason: reason, completion: completion)
        }
    }

    private func scheduleDebouncedSyncOnQueue(delay: TimeInterval, reason: String) {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.executeSyncOnQueue(reason: reason, completion: nil)
        }
        debounceWorkItem = item
        syncQueue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    internal func executeSyncOnQueue(
        reason: String,
        completion: (@Sendable (Result<CloudSyncSummary, Error>) -> Void)?
    ) {
        stateLock.withLock {
            _isSyncing = true
            _isPerformingMerge = true
        }
        notifyStatusChanged()

        let fileURL = resolvedSyncFileURL()
        let usesICloudDefault = usesDefaultICloudDrive

        do {
            if usesICloudDefault {
                guard isICloudDriveSignedIn else {
                    throw CloudSyncError.iCloudDriveUnavailable
                }
            }

            let summary = try Self.performTwoWaySync(
                fileURL: fileURL,
                dspManager: DSPPresetManager.shared,
                soundCheckService: AppleSoundCheckService.shared,
                spectralAnalyzer: SpectralIntegrityAnalyzer.shared,
                normPolicyProvider: { ExternalAmpTCPController.shared.exportNormalizationPolicy() },
                normPolicyMerger: { ExternalAmpTCPController.shared.mergeNormalizationPolicy($0) },
                roomService: RoomAcousticService.shared,
                lateNightService: LateNightDRCService.shared,
                masteringService: MasteringRestorationService.shared,
                onLocalWrite: { [weak self] in
                    self?.stateLock.withLock {
                        self?._lastLocalWriteTime = Date().timeIntervalSince1970
                    }
                }
            )

            let now = Date().timeIntervalSince1970
            stateLock.withLock {
                _isSyncing = false
                _isPerformingMerge = false
                _lastSyncTimestamp = now
                _lastSummary = summary
                _lastErrorMessage = nil
            }
            if !Self.isTestingEnvironment {
                UserDefaults.standard.set(now, forKey: kLastSyncTimestampKey)
            }

            if summary.hasLocalChanges && !Self.isTestingEnvironment {
                broadcastLocalStateRefresh(
                    dspChanged: summary.dspPresetsChanged || summary.lateNightDRCChanged || summary.masteringRestorationChanged,
                    roomChanged: summary.roomProfilesChanged,
                    normalizationPolicyChanged: summary.normalizationPolicyChanged
                )
            }
            notifyStatusChanged()
            completion?(.success(summary))
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            NSLog("[CloudSync] Sync (%@) notice/error: %@", reason, msg)
            stateLock.withLock {
                _isSyncing = false
                _isPerformingMerge = false
                _lastErrorMessage = msg
            }
            notifyStatusChanged()
            completion?(.failure(error))
        }
    }

    // MARK: - Status & UI Helpers

    public func statusSummaryDictionary() -> [String: Any] {
        let snap = stateLock.withLock {
            (
                enabled: _isEnabled,
                customPath: _customFolderPath,
                syncing: _isSyncing,
                lastTs: _lastSyncTimestamp,
                lastErr: _lastErrorMessage,
                summary: _lastSummary
            )
        }
        let customPresetsCount = DSPPresetManager.shared.allPresets().filter { !$0.isBuiltIn }.count
        let loudnessCount = AppleSoundCheckService.shared.exportCloudSyncLoudnessEntries().count
        let dynamicsCount = SpectralIntegrityAnalyzer.shared.exportCloudSyncValidations().count
        let roomProfilesCount = RoomAcousticService.shared.allProfiles().count

        let iCloudSignedIn = isICloudDriveSignedIn
        let provider: String
        if snap.customPath != nil {
            provider = "custom_folder"
        } else if iCloudSignedIn {
            provider = "icloud_drive"
        } else {
            provider = "local_fallback"
        }

        var dict: [String: Any] = [
            "enabled": snap.enabled,
            "provider": provider,
            "icloud_signed_in": iCloudSignedIn,
            "sync_directory": resolvedSyncDirectoryURL().path,
            "sync_file": resolvedSyncFileURL().path,
            "is_syncing": snap.syncing,
            "last_sync_timestamp": snap.lastTs,
            "custom_presets_count": snap.summary?.totalSyncedPresets ?? customPresetsCount,
            "loudness_tracks_count": snap.summary?.totalSyncedLoudnessTracks ?? loudnessCount,
            "dynamics_tracks_count": snap.summary?.totalSyncedDynamicsTracks ?? dynamicsCount,
            "room_profiles_count": snap.summary?.totalSyncedRoomProfiles ?? roomProfilesCount
        ]
        if let customPath = snap.customPath {
            dict["custom_folder_path"] = customPath
        }
        if let err = snap.lastErr {
            dict["last_error"] = err
        }
        return dict
    }

    public func statusDescription(isEn: Bool) -> (text: String, isActive: Bool, hasWarning: Bool) {
        let snap = stateLock.withLock {
            (
                enabled: _isEnabled,
                customPath: _customFolderPath,
                syncing: _isSyncing,
                lastTs: _lastSyncTimestamp,
                lastErr: _lastErrorMessage,
                summary: _lastSummary
            )
        }
        let customPresetsCount = snap.summary?.totalSyncedPresets ?? DSPPresetManager.shared.allPresets().filter { !$0.isBuiltIn }.count
        let loudnessCount = snap.summary?.totalSyncedLoudnessTracks ?? AppleSoundCheckService.shared.exportCloudSyncLoudnessEntries().count
        let dynamicsCount = snap.summary?.totalSyncedDynamicsTracks ?? SpectralIntegrityAnalyzer.shared.exportCloudSyncValidations().count
        let roomCount = snap.summary?.totalSyncedRoomProfiles ?? RoomAcousticService.shared.allProfiles().count

        if snap.syncing {
            let txt = isEn
                ? "Syncing DSP presets, Room EQ & track normalization with cloud…"
                : "Синхронизация пресетов DSP, АЧХ комнаты и нормализации…"
            return (txt, true, false)
        }

        let iCloudSignedIn = isICloudDriveSignedIn
        if snap.customPath == nil && !iCloudSignedIn {
            if !snap.enabled {
                let txt = isEn
                    ? "Auto-sync off (iCloud signed out — local cache only: \(customPresetsCount) presets • \(roomCount) Room EQ • \(loudnessCount) loudness • \(dynamicsCount) DR/LUFS)."
                    : "Автосинхронизация выкл (вход в iCloud не выполнен — локально: пресетов — \(customPresetsCount) • АЧХ — \(roomCount) • громкость — \(loudnessCount) • DR/LUFS — \(dynamicsCount))."
                return (txt, false, false)
            }
            let txt = isEn
                ? "iCloud Drive unavailable (not signed in — local fallback only: \(customPresetsCount) presets • \(roomCount) Room EQ • \(loudnessCount) loudness • \(dynamicsCount) DR/LUFS). Sign in to iCloud or select a custom sync folder."
                : "iCloud Drive недоступен (вход в iCloud не выполнен — локальный режим: пресетов — \(customPresetsCount) • АЧХ — \(roomCount) • громкость — \(loudnessCount) • DR/LUFS — \(dynamicsCount)). Войдите в iCloud или выберите собственную папку."
            return (txt, false, true)
        }

        if let err = snap.lastErr, !err.isEmpty {
            return (err, snap.enabled, true)
        }

        let targetLabel: String = {
            if let custom = snap.customPath, !custom.isEmpty {
                return (custom as NSString).abbreviatingWithTildeInPath
            }
            return "iCloud Drive"
        }()

        if !snap.enabled {
            let txt = isEn
                ? "Auto-sync off (\(targetLabel)). Local cache: \(customPresetsCount) presets • \(roomCount) Room EQ • \(loudnessCount) loudness • \(dynamicsCount) DR/LUFS."
                : "Автосинхронизация выкл (\(targetLabel)). Локально: пресетов — \(customPresetsCount) • АЧХ — \(roomCount) • громкость — \(loudnessCount) • DR/LUFS — \(dynamicsCount)."
            return (txt, false, false)
        }

        let timeLabel: String = {
            guard snap.lastTs > 0 else {
                return isEn ? "pending initial sync" : "ожидание первой синхронизации"
            }
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            return formatter.string(from: Date(timeIntervalSince1970: snap.lastTs))
        }()

        let txt = isEn
            ? "Active (\(targetLabel)) • Presets: \(customPresetsCount) • Room EQ: \(roomCount) • Loudness: \(loudnessCount) • DR/LUFS: \(dynamicsCount) • Last sync: \(timeLabel)"
            : "Активна (\(targetLabel)) • Пресеты: \(customPresetsCount) • АЧХ: \(roomCount) • Громкость: \(loudnessCount) • DR/LUFS: \(dynamicsCount) • Обновлено: \(timeLabel)"
        return (txt, true, false)
    }

    internal func broadcastLocalStateRefresh(
        dspChanged: Bool,
        roomChanged: Bool = false,
        normalizationPolicyChanged: Bool = false
    ) {
        if dspChanged || roomChanged || normalizationPolicyChanged {
            let payload = WebSocketServer.buildDSPSettingsDictionary()
            WebSocketServer.shared.broadcastEvent(name: "dsp_settings", data: payload)
            WebSocketServer.shared.broadcastEvent(
                name: "late_night_drc_settings",
                data: LateNightDRCService.shared.statusDictionary()
            )
            WebSocketServer.shared.broadcastEvent(
                name: "mastering_restoration_settings",
                data: MasteringRestorationService.shared.statusDictionary()
            )
        }
        if roomChanged {
            WebSocketServer.shared.broadcastEvent(
                name: "room_acoustic_settings",
                data: RoomAcousticService.shared.statusDictionary()
            )
        }
        if normalizationPolicyChanged {
            let policy = ExternalAmpTCPController.shared.exportNormalizationPolicy()
            WebSocketServer.shared.broadcastEvent(
                name: "normalization_policy",
                data: [
                    "sound_check_enabled": policy.soundCheckEnabled,
                    "low_volume_smart_norm_enabled": policy.lowVolumeSmartNormEnabled,
                    "compression_compensation_enabled": policy.compressionCompensationEnabled,
                    "updated_at": policy.updatedAt
                ]
            )
        }
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
        DispatchQueue.main.async {
            MenuManager.shared.updateMenuState()
            SettingsWindow.shared.refreshState()
        }
    }

    internal func notifyStatusChanged() {
        guard !Self.isTestingEnvironment else { return }
        let handler = stateLock.withLock { _onStatusChanged }
        guard let handler else { return }
        DispatchQueue.main.async {
            handler()
        }
    }
}
