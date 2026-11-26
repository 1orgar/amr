//
//  WebSocketServer+DSPAndRoomActions.swift
//  AppleMusicRemoteMac
//
//  DSP presets & configuration, Room Acoustic EQ calibration, Late-Night DRC,
//  Mastering Restoration, and Cloud Settings Sync WebSocket actions.
//

import Foundation
import Network

extension WebSocketServer {
    internal func handleDSPOrRoomAction(
        action: String,
        actionLower: String,
        id: String?,
        params: [String: Any],
        clientId: UUID,
        connection: NWConnection
    ) async -> Bool {
        switch actionLower {
        case "get_dsp_settings", "dsp_settings":
            let payload = Self.buildDSPSettingsDictionary()
            sendEvent(name: "dsp_settings", data: payload, to: connection)
            sendSuccess(action: action, data: payload, id: id, to: connection)
            return true

        case "select_dsp_preset":
            guard ClientDeviceManager.shared.canConnectionSelectDSPPreset(connectionId: clientId) else {
                if let record = ClientDeviceManager.shared.getDeviceForConnection(connectionId: clientId) {
                    sendEvent(name: "device_auth_status", data: record.dictionary, to: connection)
                }
                sendEvent(name: "dsp_settings", data: Self.buildDSPSettingsDictionary(), to: connection)
                sendError(
                    action: action,
                    error: AMRLocalization.tr(
                        "DSP preset selection is disabled for this device in Mac settings",
                        "Выбор пресета DSP отключён для этого устройства в настройках Mac"
                    ),
                    id: id,
                    to: connection
                )
                return true
            }
            guard !DLNADiscoveryManager.shared.hasActiveRenderer else {
                sendEvent(name: "dsp_settings", data: Self.buildDSPSettingsDictionary(), to: connection)
                sendError(
                    action: action,
                    error: AMRLocalization.tr(
                        "DSP preset selection is disabled when streaming to an external BluOS / DLNA network player",
                        "Выбор пресета DSP отключён при выводе на внешний сетевой плеер BluOS / DLNA"
                    ),
                    id: id,
                    to: connection
                )
                return true
            }
            let presetID = ((params["preset_id"] as? String) ?? (params["id"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !presetID.isEmpty,
                  let targetPreset = DSPPresetManager.shared.preset(withID: presetID) else {
                sendError(action: action, error: "DSP preset not found: \(presetID)", id: id, to: connection)
                return true
            }
            if targetPreset.configuration.mode != .bitPerfectPassthrough {
                let curCfg = AudioEngineController.shared.currentConfigurationSnapshot()
                let usbAvail = AudioEngineController.shared.currentUSBDACAvailability(targetDeviceUID: curCfg.targetDeviceUID)
                guard usbAvail.isModeSupported(targetPreset.configuration.mode, dsdRate: targetPreset.configuration.dsdRate) else {
                    sendEvent(name: "dsp_settings", data: Self.buildDSPSettingsDictionary(), to: connection)
                    sendError(
                        action: action,
                        error: AMRLocalization.tr(
                            "DSD and HQ NOS modes require an external USB DAC (≥ 24-bit / 176.4 kHz)",
                            "Режимы DSD и HQ NOS доступны только при подключении внешнего USB ЦАП (≥ 24-бит / 176.4 кГц)"
                        ),
                        id: id,
                        to: connection
                    )
                    return true
                }
            }
            guard await DSPPresetManager.shared.applyPreset(id: presetID) != nil else {
                sendError(action: action, error: "DSP preset not found: \(presetID)", id: id, to: connection)
                return true
            }
            RoomAcousticService.shared.refreshLocalPassthroughEQPipeline()
            let updatedPayload = Self.buildDSPSettingsDictionary()
            broadcastEvent(name: "dsp_settings", data: updatedPayload)
            broadcastAudioDevices()
            broadcastStatus(includeQueue: false)
            DispatchQueue.main.async {
                MenuManager.shared.updateMenuState()
                SettingsWindow.refreshIfVisible()
            }
            sendSuccess(action: action, data: updatedPayload, id: id, to: connection)
            return true

        case "set_dsp_settings", "update_dsp_settings":
            await handleSetDSPSettingsAction(action: action, id: id, params: params, clientId: clientId, connection: connection)
            return true

        case "get_room_acoustic_settings", "room_acoustic_settings":
            let payload = RoomAcousticService.shared.statusDictionary()
            sendEvent(name: "room_acoustic_settings", data: payload, to: connection)
            sendSuccess(action: action, data: payload, id: id, to: connection)
            return true

        case "start_room_test_signal":
            guard ClientDeviceManager.shared.canConnectionMeasureRoom(connectionId: clientId) else {
                if let record = ClientDeviceManager.shared.getDeviceForConnection(connectionId: clientId) {
                    sendEvent(name: "device_auth_status", data: record.dictionary, to: connection)
                }
                sendError(
                    action: action,
                    error: AMRLocalization.tr(
                        "Room acoustic measurement is disabled for this device in Mac settings",
                        "Измерение АЧХ комнаты отключено для этого устройства в настройках Mac"
                    ),
                    id: id,
                    to: connection
                )
                return true
            }
            let duration = (params["duration"] as? Double) ?? (params["duration"] as? NSNumber)?.doubleValue ?? 35.0
            RoomAcousticService.shared.startTestSignal(durationSeconds: duration, initiatingClientID: clientId)
            let payload = RoomAcousticService.shared.statusDictionary()
            broadcastEvent(name: "room_acoustic_settings", data: payload)
            sendSuccess(action: action, data: payload, id: id, to: connection)
            return true

        case "stop_room_test_signal":
            guard ClientDeviceManager.shared.canConnectionMeasureRoom(connectionId: clientId) else {
                if let record = ClientDeviceManager.shared.getDeviceForConnection(connectionId: clientId) {
                    sendEvent(name: "device_auth_status", data: record.dictionary, to: connection)
                }
                sendError(
                    action: action,
                    error: AMRLocalization.tr(
                        "Room acoustic measurement is disabled for this device in Mac settings",
                        "Измерение АЧХ комнаты отключено для этого устройства в настройках Mac"
                    ),
                    id: id,
                    to: connection
                )
                return true
            }
            RoomAcousticService.shared.stopTestSignal()
            let payload = RoomAcousticService.shared.statusDictionary()
            broadcastEvent(name: "room_acoustic_settings", data: payload)
            sendSuccess(action: action, data: payload, id: id, to: connection)
            return true

        case "submit_room_measurement":
            guard ClientDeviceManager.shared.canConnectionMeasureRoom(connectionId: clientId) else {
                if let record = ClientDeviceManager.shared.getDeviceForConnection(connectionId: clientId) {
                    sendEvent(name: "device_auth_status", data: record.dictionary, to: connection)
                }
                sendError(
                    action: action,
                    error: AMRLocalization.tr(
                        "Room acoustic measurement is disabled for this device in Mac settings",
                        "Измерение АЧХ комнаты отключено для этого устройства в настройках Mac"
                    ),
                    id: id,
                    to: connection
                )
                return true
            }
            RoomAcousticService.shared.stopTestSignal()

            var parsedBands: [Double] = []
            if let dblArr = params["bands_db"] as? [Double] {
                parsedBands = dblArr
            } else if let numArr = params["bands_db"] as? [NSNumber] {
                parsedBands = numArr.map { $0.doubleValue }
            } else if let anyArr = params["bands_db"] as? [Any] {
                parsedBands = anyArr.compactMap { ($0 as? Double) ?? ($0 as? NSNumber)?.doubleValue }
            }

            let profileName = (params["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let clientDevName = ClientDeviceManager.shared.getDeviceForConnection(connectionId: clientId)?.deviceName
                ?? ((params["device_name"] as? String) ?? "iPhone / iPad")
            let memsComp = (params["mems_compensation"] as? Bool) ?? true

            guard let profile = RoomAcousticService.shared.createProfileFromThirdOctaveBands(
                rawBandsDB: parsedBands,
                profileName: profileName,
                deviceName: clientDevName,
                applyMEMSMicCompensation: memsComp,
                autoSaveAndEnable: true
            ) else {
                sendError(
                    action: action,
                    error: AMRLocalization.tr(
                        "Invalid spectrum data (expected 31 1/3-octave bands)",
                        "Некорректные данные спектра (ожидается 31 полоса 1/3 октавы)"
                    ),
                    id: id,
                    to: connection
                )
                return true
            }

            var resp = RoomAcousticService.shared.statusDictionary()
            resp["created_profile"] = profile.dictionary
            broadcastEvent(name: "room_acoustic_settings", data: resp)
            broadcastEvent(name: "dsp_settings", data: Self.buildDSPSettingsDictionary())
            broadcastStatus(includeQueue: false)
            sendSuccess(action: action, data: resp, id: id, to: connection)
            DispatchQueue.main.async {
                MenuManager.shared.updateMenuState()
                SettingsWindow.refreshIfVisible()
            }
            return true

        case "set_room_correction_enabled":
            guard ClientDeviceManager.shared.canConnectionMeasureRoom(connectionId: clientId)
                    || ClientDeviceManager.shared.canConnectionSelectDSPPreset(connectionId: clientId) else {
                sendError(
                    action: action,
                    error: AMRLocalization.tr(
                        "Room EQ control is disabled for this device in Mac settings",
                        "Управление коррекцией АЧХ отключено для этого устройства в настройках Mac"
                    ),
                    id: id,
                    to: connection
                )
                return true
            }
            let enabled = (params["enabled"] as? Bool) ?? ((params["enabled"] as? NSNumber)?.boolValue ?? false)
            RoomAcousticService.shared.setCorrectionEnabled(enabled)
            broadcastRoomAndDSPStatus(action: action, id: id, connection: connection)
            return true

        case "select_room_profile":
            guard ClientDeviceManager.shared.canConnectionMeasureRoom(connectionId: clientId)
                    || ClientDeviceManager.shared.canConnectionSelectDSPPreset(connectionId: clientId) else {
                sendError(
                    action: action,
                    error: AMRLocalization.tr(
                        "Room profile selection is disabled for this device in Mac settings",
                        "Выбор профиля АЧХ отключён для этого устройства в настройках Mac"
                    ),
                    id: id,
                    to: connection
                )
                return true
            }
            let profID = ((params["profile_id"] as? String) ?? (params["id"] as? String))?.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = RoomAcousticService.shared.selectProfile(id: profID)
            broadcastRoomAndDSPStatus(action: action, id: id, connection: connection)
            return true

        case "rename_room_profile":
            guard ClientDeviceManager.shared.canConnectionMeasureRoom(connectionId: clientId) else {
                sendError(
                    action: action,
                    error: AMRLocalization.tr(
                        "Editing room profiles is disabled for this device",
                        "Редактирование профилей АЧХ отключено для этого устройства"
                    ),
                    id: id,
                    to: connection
                )
                return true
            }
            let profID = ((params["profile_id"] as? String) ?? (params["id"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let newName = ((params["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard RoomAcousticService.shared.renameProfile(id: profID, newName: newName) != nil else {
                sendError(
                    action: action,
                    error: AMRLocalization.tr("Failed to rename room profile", "Не удалось переименовать профиль АЧХ"),
                    id: id,
                    to: connection
                )
                return true
            }
            broadcastRoomAndDSPStatus(action: action, id: id, connection: connection)
            return true

        case "delete_room_profile":
            guard ClientDeviceManager.shared.canConnectionMeasureRoom(connectionId: clientId) else {
                sendError(
                    action: action,
                    error: AMRLocalization.tr(
                        "Deleting room profiles is disabled for this device",
                        "Удаление профилей АЧХ отключено для этого устройства"
                    ),
                    id: id,
                    to: connection
                )
                return true
            }
            let profID = ((params["profile_id"] as? String) ?? (params["id"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard RoomAcousticService.shared.deleteProfile(id: profID) else {
                sendError(
                    action: action,
                    error: AMRLocalization.tr("Room profile not found", "Профиль АЧХ не найден"),
                    id: id,
                    to: connection
                )
                return true
            }
            broadcastRoomAndDSPStatus(action: action, id: id, connection: connection)
            return true

        case "get_late_night_drc_settings", "late_night_drc_settings":
            sendSuccess(action: action, data: LateNightDRCService.shared.statusDictionary(), id: id, to: connection)
            return true

        case "set_late_night_drc", "set_late_night_drc_mode", "set_late_night_drc_enabled", "set_late_night_drc_profile":
            guard ClientDeviceManager.shared.canConnectionControlLateNight(connectionId: clientId) else {
                sendError(
                    action: action,
                    error: AMRLocalization.tr(
                        "Late-Night DRC access is disabled for this device in Mac settings",
                        "Доступ к ночному режиму (Late-Night DRC) отключён для этого устройства в настройках Mac"
                    ),
                    id: id,
                    to: connection
                )
                return true
            }

            let explicitEnabled = params["enabled"] as? Bool
            let rawProfile = (params["profile"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawMode = (params["mode"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let rawMode, !rawMode.isEmpty {
                guard let targetMode = LateNightDRCMode(rawValue: rawMode) else {
                    sendError(
                        action: action,
                        error: AMRLocalization.tr(
                            "Unknown Late-Night DRC mode: \(rawMode)",
                            "Неизвестный режим Late-Night DRC: \(rawMode)"
                        ),
                        id: id,
                        to: connection
                    )
                    return true
                }
                LateNightDRCService.shared.setMode(targetMode)
            } else if explicitEnabled != nil || rawProfile != nil {
                if let rawProfile, !rawProfile.isEmpty {
                    if rawProfile == LateNightDRCMode.off.rawValue && explicitEnabled == nil {
                        LateNightDRCService.shared.setMode(.off)
                    } else {
                        guard let p = LateNightDRCMode(rawValue: rawProfile), p != .off else {
                            sendError(
                                action: action,
                                error: AMRLocalization.tr(
                                    "Unknown Late-Night DRC profile: \(rawProfile)",
                                    "Неизвестный профиль Late-Night DRC: \(rawProfile)"
                                ),
                                id: id,
                                to: connection
                            )
                            return true
                        }
                        LateNightDRCService.shared.updateState(enabled: explicitEnabled, profile: p)
                    }
                } else {
                    LateNightDRCService.shared.updateState(enabled: explicitEnabled, profile: nil)
                }
            } else {
                LateNightDRCService.shared.setMode(.off)
            }

            let resp = LateNightDRCService.shared.statusDictionary()
            broadcastEvent(name: "late_night_drc_settings", data: resp)
            broadcastEvent(name: "dsp_settings", data: Self.buildDSPSettingsDictionary())
            broadcastStatus(includeQueue: false)
            sendSuccess(action: action, data: resp, id: id, to: connection)
            DispatchQueue.main.async {
                MenuManager.shared.updateMenuState()
                SettingsWindow.refreshIfVisible()
            }
            return true

        case "get_mastering_restoration_settings", "mastering_restoration_settings":
            sendSuccess(action: action, data: MasteringRestorationService.shared.statusDictionary(), id: id, to: connection)
            return true

        case "set_mastering_restoration", "set_mastering_declip_mode", "set_mastering_deesser_mode":
            guard ClientDeviceManager.shared.canConnectionSelectDSPPreset(connectionId: clientId) else {
                sendError(
                    action: action,
                    error: AMRLocalization.tr(
                        "DSP parameter control is disabled for this device in Mac settings",
                        "Управление параметрами DSP отключено для этого устройства в настройках Mac"
                    ),
                    id: id,
                    to: connection
                )
                return true
            }

            let rawDeClip = (params["declip_mode"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawDeEsser = (params["deesser_mode"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            var parsedDeClip: MasteringDeClipMode? = nil
            var parsedDeEsser: MasteringDeEsserMode? = nil

            if let rawDeClip, !rawDeClip.isEmpty {
                guard let m = MasteringDeClipMode(rawValue: rawDeClip) else {
                    sendError(
                        action: action,
                        error: AMRLocalization.tr(
                            "Unknown De-Clipper mode: \(rawDeClip)",
                            "Неизвестный режим De-Clipper: \(rawDeClip)"
                        ),
                        id: id,
                        to: connection
                    )
                    return true
                }
                parsedDeClip = m
            }
            if let rawDeEsser, !rawDeEsser.isEmpty {
                guard let m = MasteringDeEsserMode(rawValue: rawDeEsser) else {
                    sendError(
                        action: action,
                        error: AMRLocalization.tr(
                            "Unknown Weiss De-Esser mode: \(rawDeEsser)",
                            "Неизвестный режим Weiss De-Esser: \(rawDeEsser)"
                        ),
                        id: id,
                        to: connection
                    )
                    return true
                }
                parsedDeEsser = m
            }
            if actionLower == "set_mastering_declip_mode", parsedDeClip == nil,
               let rawMode = (params["mode"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let m = MasteringDeClipMode(rawValue: rawMode) {
                parsedDeClip = m
            }
            if actionLower == "set_mastering_deesser_mode", parsedDeEsser == nil,
               let rawMode = (params["mode"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let m = MasteringDeEsserMode(rawValue: rawMode) {
                parsedDeEsser = m
            }

            MasteringRestorationService.shared.updateModes(deClipMode: parsedDeClip, deEsserMode: parsedDeEsser)
            let resp = MasteringRestorationService.shared.statusDictionary()
            broadcastEvent(name: "mastering_restoration_settings", data: resp)
            broadcastEvent(name: "dsp_settings", data: Self.buildDSPSettingsDictionary())
            broadcastStatus(includeQueue: false)
            sendSuccess(action: action, data: resp, id: id, to: connection)
            DispatchQueue.main.async {
                MenuManager.shared.updateMenuState()
                SettingsWindow.refreshIfVisible()
            }
            return true

        case "get_cloud_sync_status", "cloud_sync_status":
            var summary = CloudSettingsSyncService.shared.statusSummaryDictionary()
            summary.removeValue(forKey: "sync_directory")
            summary.removeValue(forKey: "sync_file")
            summary.removeValue(forKey: "custom_folder_path")
            sendSuccess(action: action, data: summary, id: id, to: connection)
            return true

        case "trigger_cloud_sync":
            guard ClientDeviceManager.shared.canConnectionSelectDSPPreset(connectionId: clientId) else {
                sendError(
                    action: action,
                    error: AMRLocalization.tr(
                        "DSP parameter control is disabled for this device",
                        "Управление параметрами DSP отключено для этого устройства"
                    ),
                    id: id,
                    to: connection
                )
                return true
            }
            guard CloudSettingsSyncService.shared.isEnabled else {
                sendError(
                    action: action,
                    error: AMRLocalization.tr(
                        "Cloud sync is disabled in Mac settings",
                        "Облачная синхронизация выключена в настройках Mac"
                    ),
                    id: id,
                    to: connection
                )
                return true
            }
            CloudSettingsSyncService.shared.syncNow(reason: "ws_client_trigger") { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    var summary = CloudSettingsSyncService.shared.statusSummaryDictionary()
                    summary.removeValue(forKey: "sync_directory")
                    summary.removeValue(forKey: "sync_file")
                    summary.removeValue(forKey: "custom_folder_path")
                    self.sendSuccess(action: action, data: summary, id: id, to: connection)
                case .failure(let err):
                    self.sendError(action: action, error: err.localizedDescription, id: id, to: connection)
                }
            }
            return true

        default:
            return false
        }
    }

    private func broadcastRoomAndDSPStatus(action: String, id: String?, connection: NWConnection) {
        let resp = RoomAcousticService.shared.statusDictionary()
        broadcastEvent(name: "room_acoustic_settings", data: resp)
        broadcastEvent(name: "dsp_settings", data: Self.buildDSPSettingsDictionary())
        broadcastStatus(includeQueue: false)
        sendSuccess(action: action, data: resp, id: id, to: connection)
        DispatchQueue.main.async {
            MenuManager.shared.updateMenuState()
            SettingsWindow.refreshIfVisible()
        }
    }

    private func handleSetDSPSettingsAction(
        action: String,
        id: String?,
        params: [String: Any],
        clientId: UUID,
        connection: NWConnection
    ) async {
        guard ClientDeviceManager.shared.canConnectionSelectDSPPreset(connectionId: clientId) else {
            if let record = ClientDeviceManager.shared.getDeviceForConnection(connectionId: clientId) {
                sendEvent(name: "device_auth_status", data: record.dictionary, to: connection)
            }
            sendEvent(name: "dsp_settings", data: Self.buildDSPSettingsDictionary(), to: connection)
            sendError(
                action: action,
                error: AMRLocalization.tr(
                    "DSP preset selection is disabled for this device in Mac settings",
                    "Выбор пресета DSP отключён для этого устройства в настройках Mac"
                ),
                id: id,
                to: connection
            )
            return
        }
        guard !DLNADiscoveryManager.shared.hasActiveRenderer else {
            sendEvent(name: "dsp_settings", data: Self.buildDSPSettingsDictionary(), to: connection)
            sendError(
                action: action,
                error: AMRLocalization.tr(
                    "DSP preset settings are unavailable when streaming to an external BluOS / DLNA network player",
                    "Настройки пресетов DSP недоступны при выводе на внешний сетевой плеер BluOS / DLNA"
                ),
                id: id,
                to: connection
            )
            return
        }
        if let presetID = ((params["preset_id"] as? String) ?? (params["presetId"] as? String))?.trimmingCharacters(in: .whitespacesAndNewlines),
           !presetID.isEmpty,
           presetID != DSPPresetManager.unsavedCustomPresetID {
            guard let targetPreset = DSPPresetManager.shared.preset(withID: presetID) else {
                sendError(action: action, error: "DSP preset not found: \(presetID)", id: id, to: connection)
                return
            }
            if targetPreset.configuration.mode != .bitPerfectPassthrough {
                let curCfg = AudioEngineController.shared.currentConfigurationSnapshot()
                let usbAvail = AudioEngineController.shared.currentUSBDACAvailability(targetDeviceUID: curCfg.targetDeviceUID)
                guard usbAvail.isModeSupported(targetPreset.configuration.mode, dsdRate: targetPreset.configuration.dsdRate) else {
                    sendEvent(name: "dsp_settings", data: Self.buildDSPSettingsDictionary(), to: connection)
                    sendError(
                        action: action,
                        error: AMRLocalization.tr(
                            "DSD and HQ NOS modes require an external USB DAC (≥ 24-bit / 176.4 kHz)",
                            "Режимы DSD и HQ NOS доступны только при подключении внешнего USB ЦАП (≥ 24-бит / 176.4 кГц)"
                        ),
                        id: id,
                        to: connection
                    )
                    return
                }
            }
            guard await DSPPresetManager.shared.applyPreset(id: presetID) != nil else {
                sendError(action: action, error: "DSP preset not found: \(presetID)", id: id, to: connection)
                return
            }
            let updatedPayload = Self.buildDSPSettingsDictionary()
            broadcastEvent(name: "dsp_settings", data: updatedPayload)
            broadcastAudioDevices()
            broadcastStatus(includeQueue: false)
            DispatchQueue.main.async {
                MenuManager.shared.updateMenuState()
                SettingsWindow.refreshIfVisible()
            }
            sendSuccess(action: action, data: updatedPayload, id: id, to: connection)
            return
        }

        var cfg = AudioEngineController.shared.currentConfigurationSnapshot()
        if let modeStr = (params["mode"] as? String) ?? (params["dsp_mode"] as? String),
           let parsedMode = DSPEngineMode(rawValue: modeStr) {
            cfg.mode = parsedMode
        }
        if let dsdInt = (params["dsd_rate"] as? Int) ?? (params["dsdRate"] as? Int) ?? (params["dsd_rate"] as? NSNumber)?.intValue,
           let parsedRate = DSDRateMultiplier(rawValue: dsdInt) {
            cfg.dsdRate = parsedRate
        }
        if let profStr = (params["profile"] as? String) ?? (params["sdm_profile"] as? String) {
            switch profStr.lowercased() {
            case "transient", "7ec-transient", "0": cfg.profile = .transient
            case "balanced", "7ec-balanced", "1": cfg.profile = .balanced
            case "superwide", "super", "7ec-super", "2": cfg.profile = .superWide
            default: break
            }
        } else if let profInt = (params["profile"] as? Int) ?? (params["profile"] as? NSNumber)?.intValue,
                  let parsedProf = SDM7Profile(rawValue: profInt) {
            cfg.profile = parsedProf
        }
        if let clockStr = (params["clock_policy"] as? String) ?? (params["clockPolicy"] as? String) {
            if let parsedClock = ClockGridPolicy(rawValue: clockStr) {
                cfg.clockPolicy = parsedClock
            } else {
                switch clockStr.lowercased() {
                case "strict_sacd_44k1", "strictsacd44k1": cfg.clockPolicy = .strictSACD44k1
                case "adaptive_dual_grid", "adaptivedualgrid": cfg.clockPolicy = .adaptiveDualGrid
                case "hybrid_48k_pcm", "hybrid48kpcm": cfg.clockPolicy = .hybrid48kPCM
                default: break
                }
            }
        }
        if let backendStr = (params["oversampler_backend"] as? String) ?? (params["oversamplerBackend"] as? String) {
            if let parsedBackend = OversamplerBackendKind(rawValue: backendStr) {
                cfg.oversamplerBackend = parsedBackend
            } else {
                switch backendStr.lowercased() {
                case "metal:lin", "metal":
                    cfg.oversamplerBackend = .metalOverlapSave
                    cfg.phaseMode = .linearPhase
                case "amx:lin":
                    cfg.oversamplerBackend = .accelerateAMX
                    cfg.phaseMode = .linearPhase
                case "amx:min":
                    cfg.oversamplerBackend = .accelerateAMX
                    cfg.phaseMode = .minimumPhase
                default:
                    break
                }
            }
        }
        if let phaseStr = (params["phase_mode"] as? String) ?? (params["phaseMode"] as? String),
           let parsedPhase = OversamplerPhaseMode(rawValue: phaseStr) {
            cfg.phaseMode = parsedPhase
        }
        if let trellisInt = (params["trellis_order"] as? Int) ?? (params["trellisOrder"] as? Int) ?? (params["trellis_order"] as? NSNumber)?.intValue,
           let parsedTrellis = TrellisOrder(rawValue: trellisInt) {
            cfg.trellisOrder = parsedTrellis
        }
        if let isi = (params["isi_regularizer"] as? Bool) ?? (params["isiRegularizer"] as? Bool) {
            cfg.isiRegularizerEnabled = isi
        }
        if let hr = (params["headroom_db"] as? Double) ?? (params["headroomDb"] as? Double) ?? (params["headroom_db"] as? NSNumber)?.doubleValue {
            cfg.headroomDB = min(max(hr, -12.0), 0.0)
        }
        if let isp = (params["isp_protection"] as? Bool) ?? (params["ispProtection"] as? Bool) {
            cfg.ispProtectionEnabled = isp
        }
        if let ditherStr = (params["nos_dither_mode"] as? String) ?? (params["nosDitherMode"] as? String),
           let parsedDither = NOSPCMDitherMode(rawValue: ditherStr) {
            cfg.nosDitherMode = parsedDither
        }
        if let hog = (params["hog_mode"] as? Bool) ?? (params["hogMode"] as? Bool) {
            cfg.hogModeEnabled = hog
        }
        if let chunkMs = (params["chunk_duration_ms"] as? Int) ?? (params["chunkDurationMs"] as? Int) ?? (params["chunk_duration_ms"] as? NSNumber)?.intValue {
            cfg.chunkDurationMs = (chunkMs <= 20) ? 20 : 40
        }
        if let maxNos = (params["max_nos_pcm_rate"] as? Int) ?? (params["maxNosPcmRate"] as? Int) ?? (params["max_nos_pcm_rate"] as? NSNumber)?.intValue {
            cfg.maxNOSPCMRateHz = max(176_400, min(768_000, maxNos))
        }
        if let devUID = (params["target_device_uid"] as? String) ?? (params["targetDeviceUID"] as? String) {
            let trimmed = devUID.trimmingCharacters(in: .whitespacesAndNewlines)
            cfg.targetDeviceUID = trimmed.isEmpty ? nil : trimmed
        }
        if cfg.mode != .bitPerfectPassthrough {
            let usbAvail = AudioEngineController.shared.currentUSBDACAvailability(targetDeviceUID: cfg.targetDeviceUID)
            guard usbAvail.isModeSupported(cfg.mode, dsdRate: cfg.dsdRate) else {
                sendEvent(name: "dsp_settings", data: Self.buildDSPSettingsDictionary(), to: connection)
                sendError(
                    action: action,
                    error: AMRLocalization.tr(
                        "DSD and HQ NOS modes require an external USB DAC (≥ 24-bit / 176.4 kHz)",
                        "Режимы DSD и HQ NOS доступны только при подключении внешнего USB ЦАП (≥ 24-бит / 176.4 кГц)"
                    ),
                    id: id,
                    to: connection
                )
                return
            }
        }
        await AudioEngineController.shared.updateConfiguration(cfg)
        RoomAcousticService.shared.refreshLocalPassthroughEQPipeline()
        let updatedPayload = Self.buildDSPSettingsDictionary()
        broadcastEvent(name: "dsp_settings", data: updatedPayload)
        broadcastAudioDevices()
        broadcastStatus(includeQueue: false)
        DispatchQueue.main.async {
            MenuManager.shared.updateMenuState()
            SettingsWindow.refreshIfVisible()
        }
        sendSuccess(action: action, data: updatedPayload, id: id, to: connection)
    }
}
