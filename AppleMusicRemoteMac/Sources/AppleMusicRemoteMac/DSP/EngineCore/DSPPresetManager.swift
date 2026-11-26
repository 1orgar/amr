//
//  DSPPresetManager.swift
//  AppleMusicRemoteMac
//
//  Управление заводскими и пользовательскими пресетами гибридного DSP-движка.
//  Создание/редактирование выполняется в системных настройках macOS,
//  а быстрый выбор — в Web PWA и верхнем меню macOS.
//

import Foundation

/// Пресет конфигурации гибридного DSP-движка (`DSD DoP` / `HQ NOS PCM` / `Bit-Perfect`).
public struct DSPPreset: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var subtitle: String
    public var isBuiltIn: Bool
    public var configuration: EngineConfiguration
    public var updatedAt: TimeInterval

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case subtitle
        case isBuiltIn
        case configuration
        case updatedAt
    }

    public init(
        id: String,
        name: String,
        subtitle: String,
        isBuiltIn: Bool,
        configuration: EngineConfiguration,
        updatedAt: TimeInterval = 0
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.isBuiltIn = isBuiltIn
        self.configuration = configuration
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.subtitle = try container.decode(String.self, forKey: .subtitle)
        self.isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        self.configuration = try container.decode(EngineConfiguration.self, forKey: .configuration)
        self.updatedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .updatedAt) ?? 0
    }

    public func toDictionary() -> [String: Any] {
        [
            "id": id,
            "name": name,
            "subtitle": subtitle,
            "is_builtin": isBuiltIn,
            "mode": configuration.mode.rawValue,
            "dsd_rate": configuration.dsdRate.rawValue,
            "profile": configuration.profile.displayName,
            "updated_at": updatedAt
        ]
    }
}

/// Потокобезопасный менеджер заводских и пользовательских пресетов DSP.
public final class DSPPresetManager: @unchecked Sendable {
    public static let shared = DSPPresetManager()

    public static let unsavedCustomPresetID = "unsaved_custom"
    private static let customPresetsStorageKey = "amr.dsp.custom_presets.v1"
    private static let selectedPresetIDStorageKey = "amr.dsp.active_preset_id.v1"
    private static let deletedPresetsStorageKey = "amr.dsp.deleted_presets.v1"

    private static let isTestingEnvironment: Bool = {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil {
            return true
        }
        return NSClassFromString("XCTestCase") != nil
    }()

    /// Заводские эталонные пресеты для основных сценариев и типов ЦАП/DDC.
    public static var builtInPresets: [DSPPreset] {
        let isEn = AMRLocalization.isEnglish
        return [
            DSPPreset(
                id: "builtin_passthrough",
                name: isEn ? "Bit-Perfect Passthrough (Off)" : "Bit-Perfect Passthrough (Выкл)",
                subtitle: isEn
                    ? "Direct bit-exact PCM transfer without oversampling or modulation"
                    : "Прямая побитовая передача PCM без оверсэмплинга и модуляции",
                isBuiltIn: true,
                configuration: EngineConfiguration(mode: .bitPerfectPassthrough)
            ),
            DSPPreset(
                id: "builtin_dsd256_sacd",
                name: isEn ? "SACD Reference (DSD256 • 7EC-Balanced)" : "SACD Эталон (DSD256 • 7EC-Balanced)",
                subtitle: isEn
                    ? "DoP 705.6 kHz • Trellis M=8 • AMX Min-Phase • ISI • Reference balance"
                    : "DoP 705.6 кГц • Trellis M=8 • AMX Min-Phase • ISI • Референсный баланс",
                isBuiltIn: true,
                configuration: EngineConfiguration(
                    mode: .sdmDoP,
                    profile: .balanced,
                    dsdRate: .dsd256,
                    maxNOSPCMRateHz: 768_000,
                    clockPolicy: .strictSACD44k1,
                    oversamplerBackend: .accelerateAMX,
                    phaseMode: .minimumPhase,
                    trellisOrder: .m8,
                    isiRegularizerEnabled: true,
                    headroomDB: -3.5,
                    ispProtectionEnabled: true,
                    nosDitherMode: .lns15,
                    chunkDurationMs: 40,
                    hogModeEnabled: true
                )
            ),
            DSPPreset(
                id: "builtin_dsd256_super_metal",
                name: isEn ? "Max Stage & Air (DSD256 • 7EC-Super • Metal)" : "Макс. сцена и воздух (DSD256 • 7EC-Super • Metal)",
                subtitle: isEn
                    ? "DoP 705.6 kHz • Trellis M=16 • Metal GPU Sinc-M (262k) • Deep soundstage"
                    : "DoP 705.6 кГц • Trellis M=16 • Metal GPU Sinc-M (262k) • Глубокая сцена",
                isBuiltIn: true,
                configuration: EngineConfiguration(
                    mode: .sdmDoP,
                    profile: .superWide,
                    dsdRate: .dsd256,
                    maxNOSPCMRateHz: 768_000,
                    clockPolicy: .strictSACD44k1,
                    oversamplerBackend: .metalOverlapSave,
                    phaseMode: .linearPhase,
                    trellisOrder: .m16,
                    isiRegularizerEnabled: true,
                    headroomDB: -3.5,
                    ispProtectionEnabled: true,
                    nosDitherMode: .lns15,
                    chunkDurationMs: 40,
                    hogModeEnabled: true
                )
            ),
            DSPPreset(
                id: "builtin_dsd128_transient",
                name: isEn ? "Attack & Drive (DSD128 • 7EC-Transient)" : "Атака и драйв (DSD128 • 7EC-Transient)",
                subtitle: isEn
                    ? "DoP 352.8 kHz • OBG 1.38 • Pre-ring-free Min-Phase • Rock & metal punch"
                    : "DoP 352.8 кГц • OBG 1.38 • Min-Phase без предзвона • Панч для рока и метала",
                isBuiltIn: true,
                configuration: EngineConfiguration(
                    mode: .sdmDoP,
                    profile: .transient,
                    dsdRate: .dsd128,
                    maxNOSPCMRateHz: 768_000,
                    clockPolicy: .strictSACD44k1,
                    oversamplerBackend: .accelerateAMX,
                    phaseMode: .minimumPhase,
                    trellisOrder: .m8,
                    isiRegularizerEnabled: true,
                    headroomDB: -3.0,
                    ispProtectionEnabled: true,
                    nosDitherMode: .lns15,
                    chunkDurationMs: 40,
                    hogModeEnabled: true
                )
            ),
            DSPPreset(
                id: "builtin_dsd64_spdif",
                name: isEn ? "Optical / Coaxial S/PDIF (DSD64 DoP)" : "Оптика / Коаксиал S/PDIF (DSD64 DoP)",
                subtitle: isEn
                    ? "DoP 176.4 kHz / 24-bit • Compatible with S/PDIF & classic DACs"
                    : "DoP 176.4 кГц / 24-bit • Совместимость с S/PDIF и классическими ЦАП",
                isBuiltIn: true,
                configuration: EngineConfiguration(
                    mode: .sdmDoP,
                    profile: .balanced,
                    dsdRate: .dsd64,
                    maxNOSPCMRateHz: 768_000,
                    clockPolicy: .strictSACD44k1,
                    oversamplerBackend: .accelerateAMX,
                    phaseMode: .minimumPhase,
                    trellisOrder: .m8,
                    isiRegularizerEnabled: true,
                    headroomDB: -3.5,
                    ispProtectionEnabled: true,
                    nosDitherMode: .lns15,
                    chunkDurationMs: 40,
                    hogModeEnabled: true
                )
            ),
            DSPPreset(
                id: "builtin_hq_nos_r2r",
                name: isEn ? "Multibit / R2R (HQ PCM NOS • LNS15)" : "Мультибит / R2R (HQ PCM NOS • LNS15)",
                subtitle: isEn
                    ? "PCM 705.6/768 kHz bypassing DAC digital filter • Metal Linear-Phase • 15th-order shaper"
                    : "PCM 705.6/768 кГц в обход ЦФ ЦАП • Metal Linear-Phase • Шейпер 15-го порядка",
                isBuiltIn: true,
                configuration: EngineConfiguration(
                    mode: .hqNOSPCM,
                    profile: .balanced,
                    dsdRate: .dsd256,
                    maxNOSPCMRateHz: 768_000,
                    clockPolicy: .adaptiveDualGrid,
                    oversamplerBackend: .metalOverlapSave,
                    phaseMode: .linearPhase,
                    trellisOrder: .m8,
                    isiRegularizerEnabled: true,
                    headroomDB: -3.0,
                    ispProtectionEnabled: true,
                    nosDitherMode: .lns15,
                    chunkDurationMs: 40,
                    hogModeEnabled: true
                )
            )
        ]
    }

    private let lock = NSLock()
    private var _customPresets: [DSPPreset]
    private var _preferredPresetID: String?
    private var _deletedPresetTimestamps: [String: TimeInterval]

    public init(loadFromDefaults: Bool = true) {
        if loadFromDefaults && !Self.isTestingEnvironment {
            if let data = AppStorageProvider.shared.data(forKey: Self.customPresetsStorageKey),
               let decoded = try? JSONDecoder().decode([DSPPreset].self, from: data) {
                self._customPresets = decoded.map { p in
                    var copy = p
                    copy.isBuiltIn = false
                    return copy
                }
            } else {
                self._customPresets = []
            }
            if let delData = AppStorageProvider.shared.data(forKey: Self.deletedPresetsStorageKey),
               let delDecoded = try? JSONDecoder().decode([String: TimeInterval].self, from: delData) {
                self._deletedPresetTimestamps = delDecoded
            } else {
                self._deletedPresetTimestamps = [:]
            }
            self._preferredPresetID = AppStorageProvider.shared.string(forKey: Self.selectedPresetIDStorageKey)
        } else {
            self._customPresets = []
            self._preferredPresetID = nil
            self._deletedPresetTimestamps = [:]
        }
    }

    // MARK: - Queries

    public func allPresets() -> [DSPPreset] {
        lock.withLock {
            Self.builtInPresets + _customPresets
        }
    }

    public func customPresets() -> [DSPPreset] {
        lock.withLock { _customPresets }
    }

    public func preset(withID id: String) -> DSPPreset? {
        lock.withLock {
            if let builtIn = Self.builtInPresets.first(where: { $0.id == id }) {
                return builtIn
            }
            return _customPresets.first(where: { $0.id == id })
        }
    }

    /// Проверяет эквивалентность звуковых параметров `EngineConfiguration` и пресета
    /// (аппаратная привязка `targetDeviceUID` не сбрасывает совпадение пресета).
    public static func configurationsMatch(_ lhs: EngineConfiguration, _ rhs: EngineConfiguration) -> Bool {
        if lhs.mode == .bitPerfectPassthrough && rhs.mode == .bitPerfectPassthrough {
            return true
        }
        guard lhs.mode == rhs.mode else { return false }

        // Общие параметры активного DSP
        guard lhs.oversamplerBackend == rhs.oversamplerBackend,
              lhs.phaseMode == rhs.phaseMode,
              lhs.clockPolicy == rhs.clockPolicy,
              abs(lhs.headroomDB - rhs.headroomDB) < 0.05,
              lhs.ispProtectionEnabled == rhs.ispProtectionEnabled,
              lhs.hogModeEnabled == rhs.hogModeEnabled else {
            return false
        }

        switch lhs.mode {
        case .bitPerfectPassthrough:
            return true
        case .sdmDoP:
            let ditherMatches = (lhs.clockPolicy != .hybrid48kPCM) || (lhs.nosDitherMode == rhs.nosDitherMode)
            return lhs.dsdRate == rhs.dsdRate
                && lhs.profile == rhs.profile
                && lhs.trellisOrder == rhs.trellisOrder
                && lhs.isiRegularizerEnabled == rhs.isiRegularizerEnabled
                && ditherMatches
        case .hqNOSPCM:
            return lhs.maxNOSPCMRateHz == rhs.maxNOSPCMRateHz
                && lhs.nosDitherMode == rhs.nosDitherMode
        }
    }

    /// Возвращает активный пресет, соответствующий текущей конфигурации `config`, либо `nil` (если параметры изменены вручную).
    public func matchingPreset(for config: EngineConfiguration) -> DSPPreset? {
        lock.withLock {
            let all = Self.builtInPresets + _customPresets
            if let prefID = _preferredPresetID,
               let preferred = all.first(where: { $0.id == prefID }),
               Self.configurationsMatch(config, preferred.configuration) {
                return preferred
            }
            if let customMatch = _customPresets.first(where: { Self.configurationsMatch(config, $0.configuration) }) {
                return customMatch
            }
            return Self.builtInPresets.first(where: { Self.configurationsMatch(config, $0.configuration) })
        }
    }

    public func preferredCustomPresetID() -> String? {
        lock.withLock {
            guard let pref = _preferredPresetID,
                  _customPresets.contains(where: { $0.id == pref }) else {
                return nil
            }
            return pref
        }
    }

    /// Формирует краткое описание параметров для автоподзаголовка пользовательского пресета.
    public static func summarizeConfiguration(_ cfg: EngineConfiguration) -> String {
        let isEn = AMRLocalization.isEnglish
        switch cfg.mode {
        case .bitPerfectPassthrough:
            return "Bit-Perfect PCM Passthrough"
        case .sdmDoP:
            let osStr = (cfg.oversamplerBackend == .metalOverlapSave)
                ? "Metal Sinc-M"
                : (cfg.phaseMode == .minimumPhase ? "AMX Min-Phase" : "AMX Lin-Phase")
            return String(
                format: isEn ? "DSD%d • %@ • M=%d • %@ • %.1f dB" : "DSD%d • %@ • M=%d • %@ • %.1f дБ",
                cfg.dsdRate.rawValue,
                cfg.profile.displayName,
                cfg.trellisOrder.rawValue,
                osStr,
                cfg.headroomDB
            )
        case .hqNOSPCM:
            let khz = cfg.maxNOSPCMRateHz / 1000
            let osStr = (cfg.oversamplerBackend == .metalOverlapSave) ? "Metal Sinc-M" : "AMX FP64"
            return isEn
                ? "HQ NOS PCM \(khz) kHz • \(cfg.nosDitherMode.displayName) • \(osStr)"
                : "HQ NOS PCM \(khz) кГц • \(cfg.nosDitherMode.displayName) • \(osStr)"
        }
    }

    // MARK: - Preset Selection & CRUD

    /// Применяет пресет по его `id` к `AudioEngineController`, сохраняя привязку `targetDeviceUID`.
    @discardableResult
    public func applyPreset(id: String, controller: AudioEngineController = .shared) async -> DSPPreset? {
        guard let target = preset(withID: id) else { return nil }
        lock.withLock {
            _preferredPresetID = target.id
            persistLocked()
        }
        var nextCfg = target.configuration
        let currentCfg = controller.currentConfigurationSnapshot()
        nextCfg.targetDeviceUID = currentCfg.targetDeviceUID
        await controller.updateConfiguration(nextCfg)
        return target
    }

    /// Создаёт новый или обновляет существующий пользовательский пресет.
    @discardableResult
    public func saveCustomPreset(
        name: String,
        subtitle: String? = nil,
        configuration: EngineConfiguration,
        updatingPresetID: String? = nil
    ) -> DSPPreset {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultPresetName = AMRLocalization.tr("My DSP Preset", "Мой пресет DSP")
        let safeName = trimmedName.isEmpty ? defaultPresetName : String(trimmedName.prefix(64))
        var cleanCfg = configuration
        cleanCfg.targetDeviceUID = nil
        let resolvedSubtitle = {
            let trimmedSub = (subtitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedSub.isEmpty ? Self.summarizeConfiguration(cleanCfg) : String(trimmedSub.prefix(120))
        }()

        let now = Date().timeIntervalSince1970
        let saved: DSPPreset = lock.withLock {
            if let existingID = updatingPresetID,
               let idx = _customPresets.firstIndex(where: { $0.id == existingID }) {
                _customPresets[idx].name = safeName
                _customPresets[idx].subtitle = resolvedSubtitle
                _customPresets[idx].configuration = cleanCfg
                _customPresets[idx].updatedAt = now
                _deletedPresetTimestamps.removeValue(forKey: existingID)
                _preferredPresetID = existingID
                persistLocked()
                return _customPresets[idx]
            }

            let newID = "custom_\(UUID().uuidString.lowercased().prefix(8))"
            let created = DSPPreset(
                id: newID,
                name: safeName,
                subtitle: resolvedSubtitle,
                isBuiltIn: false,
                configuration: cleanCfg,
                updatedAt: now
            )
            _customPresets.append(created)
            _deletedPresetTimestamps.removeValue(forKey: newID)
            _preferredPresetID = newID
            persistLocked()
            return created
        }
        if self === Self.shared && !Self.isTestingEnvironment {
            CloudSettingsSyncService.shared.schedulePush(reason: "dsp_preset_saved")
        }
        return saved
    }

    /// Переименовывает существующий пользовательский пресет.
    @discardableResult
    public func renameCustomPreset(id: String, newName: String) -> DSPPreset? {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let safeName = String(trimmed.prefix(64))
        let now = Date().timeIntervalSince1970
        let renamed: DSPPreset? = lock.withLock {
            guard let idx = _customPresets.firstIndex(where: { $0.id == id }) else { return nil }
            _customPresets[idx].name = safeName
            _customPresets[idx].updatedAt = now
            persistLocked()
            return _customPresets[idx]
        }
        if renamed != nil && self === Self.shared && !Self.isTestingEnvironment {
            CloudSettingsSyncService.shared.schedulePush(reason: "dsp_preset_renamed")
        }
        return renamed
    }

    /// Удаляет пользовательский пресет (встроенные заводские пресеты защищены от удаления).
    @discardableResult
    public func deleteCustomPreset(id: String) -> Bool {
        let now = Date().timeIntervalSince1970
        let deleted: Bool = lock.withLock {
            guard let idx = _customPresets.firstIndex(where: { $0.id == id }) else { return false }
            _customPresets.remove(at: idx)
            _deletedPresetTimestamps[id] = now
            pruneDeletedTombstonesLocked(now: now)
            if _preferredPresetID == id {
                _preferredPresetID = nil
            }
            persistLocked()
            return true
        }
        if deleted && self === Self.shared && !Self.isTestingEnvironment {
            CloudSettingsSyncService.shared.schedulePush(reason: "dsp_preset_deleted")
        }
        return deleted
    }

    // MARK: - Cloud Sync Export & Merge (LWW + Tombstones)

    public func exportCloudSyncState() -> (customPresets: [DSPPreset], deletedTimestamps: [String: TimeInterval]) {
        lock.withLock {
            let cleanList = _customPresets.map { preset -> DSPPreset in
                var copy = preset
                copy.isBuiltIn = false
                copy.configuration.targetDeviceUID = nil
                return copy
            }
            return (cleanList, _deletedPresetTimestamps)
        }
    }

    @discardableResult
    public func mergeCloudSyncState(
        remotePresets: [DSPPreset],
        remoteDeletedTimestamps: [String: TimeInterval]
    ) -> Bool {
        let builtInIDs = Set(Self.builtInPresets.map { $0.id })
        let now = Date().timeIntervalSince1970

        return lock.withLock {
            let prevPresets = _customPresets
            let prevDeleted = _deletedPresetTimestamps

            var mergedDeleted = _deletedPresetTimestamps
            for (delId, ts) in remoteDeletedTimestamps where !builtInIDs.contains(delId) && ts.isFinite && ts > 0 {
                if let curTs = mergedDeleted[delId] {
                    if ts > curTs { mergedDeleted[delId] = ts }
                } else {
                    mergedDeleted[delId] = ts
                }
            }

            var localById: [String: DSPPreset] = [:]
            var orderedIDs: [String] = []
            for p in _customPresets where !builtInIDs.contains(p.id) {
                localById[p.id] = p
                orderedIDs.append(p.id)
            }

            var remoteById: [String: DSPPreset] = [:]
            for raw in remotePresets where !builtInIDs.contains(raw.id) && !raw.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                var clean = raw
                clean.isBuiltIn = false
                clean.configuration.targetDeviceUID = nil
                remoteById[clean.id] = clean
                if localById[clean.id] == nil && !orderedIDs.contains(clean.id) {
                    orderedIDs.append(clean.id)
                }
            }

            var nextPresets: [DSPPreset] = []
            for id in orderedIDs {
                let loc = localById[id]
                let rem = remoteById[id]
                let winner: DSPPreset
                switch (loc, rem) {
                case let (.some(l), .some(r)):
                    winner = (r.updatedAt > l.updatedAt) ? r : l
                case let (.some(l), .none):
                    winner = l
                case let (.none, .some(r)):
                    winner = r
                case (.none, .none):
                    continue
                }

                let delTs = mergedDeleted[id] ?? 0
                if delTs > winner.updatedAt && delTs > 0 {
                    // Tombstone is newer than preset's last edit — keep deleted
                    continue
                }
                mergedDeleted.removeValue(forKey: id)
                nextPresets.append(winner)
            }

            _customPresets = nextPresets
            _deletedPresetTimestamps = mergedDeleted
            pruneDeletedTombstonesLocked(now: now)

            if let pref = _preferredPresetID,
               !builtInIDs.contains(pref),
               !_customPresets.contains(where: { $0.id == pref }) {
                _preferredPresetID = nil
            }

            let changed = (_customPresets != prevPresets) || (_deletedPresetTimestamps != prevDeleted)
            if changed {
                persistLocked()
            }
            return changed
        }
    }

    private func pruneDeletedTombstonesLocked(now: TimeInterval) {
        let retentionSeconds: TimeInterval = 180.0 * 86_400.0
        _deletedPresetTimestamps = _deletedPresetTimestamps.filter { (_, ts) in
            ts.isFinite && ts > 0 && (now - ts) < retentionSeconds
        }
    }

    public func buildTelemetryPresetInfo(for config: EngineConfiguration) -> (
        activeID: String,
        activeName: String,
        activeSubtitle: String,
        presetsPayload: [[String: Any]]
    ) {
        let matched = matchingPreset(for: config)
        let list = allPresets().map { $0.toDictionary() }
        if let matched {
            return (matched.id, matched.name, matched.subtitle, list)
        } else {
            return (
                Self.unsavedCustomPresetID,
                AMRLocalization.tr("Custom Mode", "Пользовательский режим"),
                Self.summarizeConfiguration(config),
                list
            )
        }
    }

    private func persistLocked() {
        guard !Self.isTestingEnvironment else { return }
        if let encoded = try? JSONEncoder().encode(_customPresets) {
            AppStorageProvider.shared.set(encoded, forKey: Self.customPresetsStorageKey)
        }
        if let delEncoded = try? JSONEncoder().encode(_deletedPresetTimestamps) {
            AppStorageProvider.shared.set(delEncoded, forKey: Self.deletedPresetsStorageKey)
        }
        if let pref = _preferredPresetID {
            AppStorageProvider.shared.set(pref, forKey: Self.selectedPresetIDStorageKey)
        } else {
            AppStorageProvider.shared.removeObject(forKey: Self.selectedPresetIDStorageKey)
        }
    }
}
