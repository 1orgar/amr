//
//  WebSocketServer+ActionDispatcher.swift
//  AppleMusicRemoteMac
//
//  WebSocket client message router, synchronous register_device handling,
//  per-client FIFO enqueueing, capability-gated QR minting, and shared helpers.
//

import Foundation
import Network

extension WebSocketServer {
    // MARK: - Curate Task Lifecycle & Client Log Rate Limiting

    private static let clientLogRateLock = NSLock()
    private static var clientLogTimestamps: [UUID: [TimeInterval]] = [:]
    private static let spectralWakeLock = NSLock()
    private static var lastSpectralColdWakeAt: TimeInterval = 0

    internal func ensureSpectralTapAwakeNonBlocking() {
        guard SpectralIntegrityAnalyzer.shared.isEnabled,
              !AudioProcessTapService.shared.isRealTapActive,
              !PlaybackRouter.shared.isTestingEnvironment else {
            return
        }
        if SpectralIntegrityAnalyzer.shared.isPlaying {
            let fmt = SpectralIntegrityAnalyzer.shared.sampleRateAndBitDepthSnapshot
            AudioProcessTapService.shared.ensurePassiveAnalysisTapActive(
                sampleRate: fmt.sampleRate,
                bitDepth: fmt.bitDepth
            )
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let shouldProbeColdStart: Bool = Self.spectralWakeLock.withLock {
            guard now - Self.lastSpectralColdWakeAt >= 3.0 else { return false }
            Self.lastSpectralColdWakeAt = now
            return true
        }
        if shouldProbeColdStart {
            DispatchQueue.global(qos: .utility).async {
                _ = PlayerStatusEngine.shared.getPlayerStatus()
            }
        }
    }

    internal func cancelCurateTask(for clientId: UUID) {
        curateTaskLock.withLock {
            activeCurateTasks.removeValue(forKey: clientId)?.cancel()
        }
        Self.clientLogRateLock.withLock {
            _ = Self.clientLogTimestamps.removeValue(forKey: clientId)
        }
    }

    internal func cancelAllCurateTasks() {
        curateTaskLock.withLock {
            for (_, task) in activeCurateTasks {
                task.cancel()
            }
            activeCurateTasks.removeAll()
        }
        Self.clientLogRateLock.withLock {
            Self.clientLogTimestamps.removeAll()
        }
    }

    internal func sendCancelledCurateResponse(action: String, id: String?, requestId: Int? = nil, to connection: NWConnection) {
        var dataDict: [String: Any] = ["status": "cancelled"]
        if let reqNum = requestId {
            dataDict["request_id"] = reqNum
        }
        var payload: [String: Any] = [
            "action": action,
            "event": action,
            "type": action,
            "status": "cancelled",
            "data": dataDict
        ]
        if let reqId = id {
            payload["id"] = reqId
        }
        if let reqNum = requestId {
            payload["request_id"] = reqNum
        }
        if JSONSerialization.isValidJSONObject(payload),
           let jsonBytes = try? JSONSerialization.data(withJSONObject: payload),
           let text = String(data: jsonBytes, encoding: .utf8) {
            sendText(text, to: connection)
        }
    }

    // MARK: - Device Registration Shared Handler

    private func handleRegisterDeviceAction(
        action: String,
        id: String?,
        params: [String: Any],
        clientId: UUID,
        connection: NWConnection,
        pushInitialState: Bool
    ) -> ClientDeviceRecord {
        let rawDeviceId = (params["device_id"] as? String) ?? (params["deviceId"] as? String) ?? ""
        let rawDeviceName = (params["device_name"] as? String) ?? (params["deviceName"] as? String) ?? ""
        let rawDeviceType = (params["device_type"] as? String) ?? (params["deviceType"] as? String) ?? "mobile"
        let prefLockScreen = (params["lock_screen_controls"] as? Bool) ?? (params["lockScreenControls"] as? Bool)
        let inviteToken = (params["invite_token"] as? String) ?? (params["inviteToken"] as? String)
        let deviceSecret = (params["device_secret"] as? String) ?? (params["deviceSecret"] as? String)
        let remoteIP = extractRemoteIP(from: connection)

        let record = ClientDeviceManager.shared.registerConnection(
            connectionId: clientId,
            deviceId: rawDeviceId,
            deviceName: rawDeviceName,
            deviceType: rawDeviceType,
            preferredLockScreen: prefLockScreen,
            remoteIP: remoteIP,
            inviteToken: inviteToken,
            deviceSecret: deviceSecret
        )
        let authPayload = record.dictionaryWithSecret
        sendEvent(name: "device_auth_status", data: authPayload, to: connection)
        sendSuccess(action: action, data: authPayload, id: id, to: connection)

        if pushInitialState && record.isAuthorized {
            pushInitialAuthorizedSnapshot(clientId: clientId)
        }
        return record
    }

    // MARK: - Synchronous Entry Point & Per-Client FIFO Enqueue

    /// Synchronously handles `register_device` on the connection's serial queue so any pipelined
    /// frames in the same TCP read buffer immediately observe the updated authorization state.
    /// All other client messages are enqueued into the per-client bounded FIFO worker (`<= 64`).
    internal func dispatchClientTextMessage(_ text: String, clientId: UUID, connection: NWConnection) {
        if text.contains("register_device"),
           let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let action = (json["action"] as? String) ?? (json["command"] as? String) ?? (json["type"] as? String) ?? ""
            if action.lowercased() == "register_device" {
                let id = json["id"] as? String
                let params = (json["params"] as? [String: Any]) ?? (json["payload"] as? [String: Any]) ?? (json["data"] as? [String: Any]) ?? json
                NSLog("[WebSocket] Processing action: %@, id: %@", action, id ?? "nil")
                _ = handleRegisterDeviceAction(
                    action: action,
                    id: id,
                    params: params,
                    clientId: clientId,
                    connection: connection,
                    pushInitialState: true
                )
                return
            }
        }

        if (text.contains("spectral_analysis") || text.contains("spectral_rta")),
           ClientDeviceManager.shared.isConnectionAuthorized(connectionId: clientId),
           let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let action = (json["action"] as? String) ?? (json["command"] as? String) ?? (json["type"] as? String) ?? ""
            let actionLower = action.lowercased()
            let id = json["id"] as? String
            if actionLower == "get_spectral_rta" || actionLower == "spectral_rta" {
                ensureSpectralTapAwakeNonBlocking()
                sendSuccess(action: action, data: SpectralIntegrityAnalyzer.shared.getCompactRTAPayload(), id: id, to: connection)
                return
            }
            if actionLower == "get_spectral_analysis" || actionLower == "spectral_analysis" {
                ensureSpectralTapAwakeNonBlocking()
                sendSuccess(action: action, data: SpectralIntegrityAnalyzer.shared.getCurrentAnalysis(), id: id, to: connection)
                return
            }
        }

        enqueueClientTextMessage(text, clientId: clientId, connection: connection)
    }

    // MARK: - Async Message Processor

    func processClientTextMessage(_ text: String, clientId: UUID, connection: NWConnection) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            sendError(action: "unknown", error: "Invalid JSON format", id: nil, to: connection)
            return
        }

        let id = json["id"] as? String
        let action = (json["action"] as? String) ?? (json["command"] as? String) ?? (json["type"] as? String) ?? ""
        let params = (json["params"] as? [String: Any]) ?? (json["payload"] as? [String: Any]) ?? (json["data"] as? [String: Any]) ?? json
        let actionLower = action.lowercased()

        if actionLower == "client_log" {
            if !ClientDeviceManager.shared.isConnectionAuthorized(connectionId: clientId) {
                let now = Date().timeIntervalSince1970
                let allowed: Bool = Self.clientLogRateLock.withLock {
                    var recent = (Self.clientLogTimestamps[clientId] ?? []).filter { now - $0 < 10.0 }
                    guard recent.count < 10 else {
                        Self.clientLogTimestamps[clientId] = recent
                        return false
                    }
                    recent.append(now)
                    Self.clientLogTimestamps[clientId] = recent
                    return true
                }
                guard allowed else { return }
            }
            let rawMsg = (params["message"] as? String) ?? ""
            let sanitizedMsg = String(
                rawMsg
                    .replacingOccurrences(of: "\r", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
                    .prefix(500)
            )
            let rawLevel = (params["level"] as? String) ?? "info"
            let level = String(
                rawLevel
                    .replacingOccurrences(of: "\r", with: "")
                    .replacingOccurrences(of: "\n", with: "")
                    .prefix(32)
            )
            let devRecord = ClientDeviceManager.shared.getDeviceForConnection(connectionId: clientId)
            let rawDevName = devRecord?.deviceName ?? (params["device_name"] as? String) ?? "PWA"
            let devName = String(
                rawDevName
                    .replacingOccurrences(of: "\r", with: "")
                    .replacingOccurrences(of: "\n", with: "")
                    .prefix(64)
            )
            if !sanitizedMsg.isEmpty {
                DiagnosticLogger.shared.logClientEvent(device: devName, level: level, message: sanitizedMsg)
            }
            return
        }

        if actionLower != "get_spectral_analysis" && actionLower != "spectral_analysis" && actionLower != "ping" {
            NSLog("[WebSocket] Processing action: %@, id: %@", action, id ?? "nil")
        }

        if actionLower == "register_device" {
            let record = handleRegisterDeviceAction(
                action: action,
                id: id,
                params: params,
                clientId: clientId,
                connection: connection,
                pushInitialState: false
            )
            if record.isAuthorized {
                let status = MusicBridge.shared.getPlayerStatus()
                sendEvent("player_state_changed", data: status, to: connection)
                sendEvent(name: "ai_curator_settings", data: NativeMusicCuratorService.shared.getSettingsDictionary(), to: connection)
                sendEvent(name: "dsp_settings", data: Self.buildDSPSettingsDictionary(), to: connection)
                sendEvent(name: "tv_library_config", data: TVLibraryConfigurationStore.shared.toDictionary(), to: connection)
                let queue = await MusicBridge.shared.getPlaybackQueue()
                sendEvent("queue", data: queue, to: connection)
            }
            return
        }

        if actionLower == "update_device_settings" {
            handleUpdateDeviceSettingsAction(action: action, id: id, params: params, clientId: clientId, connection: connection)
            return
        }

        if actionLower == "get_device_status" {
            if let record = ClientDeviceManager.shared.getDeviceForConnection(connectionId: clientId) {
                let payload = record.dictionaryWithSecret
                sendEvent(name: "device_auth_status", data: payload, to: connection)
                sendSuccess(action: action, data: payload, id: id, to: connection)
            } else {
                sendError(action: action, error: "Device not registered", id: id, to: connection)
            }
            return
        }

        if actionLower == "ping" {
            sendSuccess(action: action, data: ["status": "pong"], id: id, to: connection)
            return
        }

        if !ClientDeviceManager.shared.isConnectionAuthorized(connectionId: clientId) {
            if let record = ClientDeviceManager.shared.getDeviceForConnection(connectionId: clientId) {
                sendEvent(name: "device_auth_status", data: record.dictionary, to: connection)
            }
            sendError(action: action, error: "Device pending authorization on Mac", id: id, to: connection)
            return
        }

        if actionLower == "get_share_access_qr" || actionLower == "generate_share_access_qr" {
            guard ClientDeviceManager.shared.canConnectionSelectDAC(connectionId: clientId) else {
                if let record = ClientDeviceManager.shared.getDeviceForConnection(connectionId: clientId) {
                    sendEvent(name: "device_auth_status", data: record.dictionary, to: connection)
                }
                sendError(action: action, error: "Генерация QR-приглашений доступна только устройствам с правами администратора ЦАП/аудиовыхода", id: id, to: connection)
                return
            }
            let payload = ClientDeviceManager.shared.generateShareAccessPayload()
            sendEvent(name: "share_access_qr", data: payload, to: connection)
            sendSuccess(action: action, data: payload, id: id, to: connection)
            return
        }

        if await handleTransportOrQueueAction(action: action, actionLower: actionLower, id: id, params: params, clientId: clientId, connection: connection) {
            return
        }
        if await handlePlaybackInitiationAction(action: action, actionLower: actionLower, id: id, params: params, clientId: clientId, connection: connection) {
            return
        }
        if await handleLibraryOrCatalogAction(action: action, actionLower: actionLower, id: id, json: json, params: params, clientId: clientId, connection: connection) {
            return
        }
        if await handleAudioOrAIAction(action: action, actionLower: actionLower, id: id, json: json, params: params, clientId: clientId, connection: connection) {
            return
        }
        if await handleDSPOrRoomAction(action: action, actionLower: actionLower, id: id, params: params, clientId: clientId, connection: connection) {
            return
        }

        sendError(action: action, error: "Unsupported action: \(action)", id: id, to: connection)
    }

    private func handleUpdateDeviceSettingsAction(
        action: String,
        id: String?,
        params: [String: Any],
        clientId: UUID,
        connection: NWConnection
    ) {
        let currentRecord = ClientDeviceManager.shared.getDeviceForConnection(connectionId: clientId)
        let boundDeviceId = ClientDeviceManager.shared.getDeviceId(forConnection: clientId)
        let rawTargetId = (params["device_id"] as? String) ?? (params["deviceId"] as? String) ?? currentRecord?.deviceId ?? ""
        let targetDeviceId = rawTargetId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !targetDeviceId.isEmpty else {
            sendError(action: action, error: "Device ID not registered", id: id, to: connection)
            return
        }
        let isCallerOwnDevice = (boundDeviceId != nil && boundDeviceId == targetDeviceId)
        let remoteIP = extractRemoteIP(from: connection).lowercased()
        let isLoopback = (remoteIP == "127.0.0.1" || remoteIP == "::1" || remoteIP == "localhost" || remoteIP == "::ffff:127.0.0.1")
        let isAuthorized = ClientDeviceManager.shared.isConnectionAuthorized(connectionId: clientId)
        guard isCallerOwnDevice || (isLoopback && isAuthorized && boundDeviceId == nil) else {
            sendError(action: action, error: "Unauthorized to modify another device's settings", id: id, to: connection)
            return
        }
        if !isAuthorized {
            guard isCallerOwnDevice else {
                sendError(action: action, error: "Device not authorized to modify settings", id: id, to: connection)
                return
            }
            if let newName = (params["device_name"] as? String) ?? (params["deviceName"] as? String),
               !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ClientDeviceManager.shared.updateDeviceName(deviceId: targetDeviceId, name: newName)
            }
            if let updated = ClientDeviceManager.shared.getDevice(deviceId: targetDeviceId) {
                sendSuccess(action: action, data: updated.dictionary, id: id, to: connection)
            } else {
                sendError(action: action, error: "Device not found", id: id, to: connection)
            }
            return
        }
        if let lockEnabled = (params["lock_screen_controls"] as? Bool) ?? (params["lockScreenControls"] as? Bool) {
            ClientDeviceManager.shared.setLockScreenControls(deviceId: targetDeviceId, enabled: lockEnabled)
        }
        if let newName = (params["device_name"] as? String) ?? (params["deviceName"] as? String),
           !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ClientDeviceManager.shared.updateDeviceName(deviceId: targetDeviceId, name: newName)
        }
        if let updated = ClientDeviceManager.shared.getDevice(deviceId: targetDeviceId) {
            sendSuccess(action: action, data: updated.dictionary, id: id, to: connection)
        } else {
            sendError(action: action, error: "Device not found", id: id, to: connection)
        }
    }

    // MARK: - Binary Messages & Shared Model Builders

    func processClientBinaryMessage(_ data: Data, clientId: UUID? = nil, connection: NWConnection) async {
        if let cid = clientId, !ClientDeviceManager.shared.isConnectionAuthorized(connectionId: cid) {
            sendError(action: "binary", error: "Device pending authorization on Mac", id: nil, to: connection)
            return
        }
        sendSuccess(action: "binary", data: ["received_bytes": data.count], id: nil, to: connection)
    }

    internal func parseTrackInfo(_ dict: [String: Any]) -> TrackInfo {
        let tid = (dict["id"] as? String) ?? "\(dict["numeric_id"] ?? UUID().uuidString)"
        let numericId = (dict["numeric_id"] as? Int) ?? Int(tid)
        let name = (dict["name"] as? String) ?? ""
        let artist = (dict["artist"] as? String) ?? ""
        let album = (dict["album"] as? String) ?? ""
        let dur = (dict["duration"] as? Double) ?? 0
        let art = (dict["artwork"] as? String) ?? (dict["artwork_url"] as? String) ?? ""
        let url = dict["url"] as? String
        let preview = dict["preview_url"] as? String
        let isLocal = (dict["is_local"] as? Bool) ?? (dict["isLocal"] as? Bool) ?? false
        let catId = (dict["catalog_id"] as? String) ?? (dict["catalogId"] as? String) ?? (AppleSoundCheckService.isValidCatalogId(tid) ? tid : nil)

        return TrackInfo(
            id: tid,
            numericId: numericId,
            name: name,
            artist: artist,
            album: album,
            duration: dur,
            hasArtwork: !art.isEmpty,
            artworkUrl: art,
            favorited: false,
            isLocal: isLocal,
            url: url,
            previewUrl: preview,
            catalogId: catId
        )
    }

    internal static func buildDSPSettingsDictionary() -> [String: Any] {
        let cfg = AudioEngineController.shared.currentConfigurationSnapshot()
        let tel = AudioEngineController.shared.latestTelemetrySnapshot()
        let usbAvail = AudioEngineController.shared.currentUSBDACAvailability(targetDeviceUID: cfg.targetDeviceUID)
        let isDLNA = DLNADiscoveryManager.shared.hasActiveRenderer
        let isModeAllowedOnHardware = !isDLNA && usbAvail.isModeSupported(cfg.mode)
        let effectiveMode: DSPEngineMode = isModeAllowedOnHardware ? cfg.mode : .bitPerfectPassthrough
        let presetInfo = DSPPresetManager.shared.buildTelemetryPresetInfo(for: cfg)
        let effectivePresetID = isModeAllowedOnHardware ? presetInfo.activeID : "builtin_passthrough"
        let effectivePresetName = isModeAllowedOnHardware ? presetInfo.activeName : "Чистый оригинал (Bit-Perfect Passthrough)"
        let effectivePresetSubtitle = isModeAllowedOnHardware
            ? presetInfo.activeSubtitle
            : (usbAvail.hasEligibleUSBDAC
                ? presetInfo.activeSubtitle
                : "Внешний USB / Thunderbolt ЦАП не подключён: DSD и HQ NOS доступны только для внешних USB / Thunderbolt ЦАП (≥ 24-бит / 176.4 кГц)")
        let profileKey: String = {
            switch cfg.profile {
            case .transient: return "transient"
            case .balanced: return "balanced"
            case .superWide: return "superWide"
            }
        }()
        return [
            "active_preset_id": effectivePresetID,
            "active_preset_name": effectivePresetName,
            "active_preset_subtitle": effectivePresetSubtitle,
            "configured_preset_id": presetInfo.activeID,
            "presets": presetInfo.presetsPayload,
            "mode": effectiveMode.rawValue,
            "configured_mode": cfg.mode.rawValue,
            "dsd_rate": cfg.dsdRate.rawValue,
            "profile": profileKey,
            "clock_policy": cfg.clockPolicy.rawValue,
            "oversampler_backend": cfg.oversamplerBackend.rawValue,
            "phase_mode": cfg.phaseMode.rawValue,
            "trellis_order": cfg.trellisOrder.rawValue,
            "isi_regularizer": cfg.isiRegularizerEnabled,
            "headroom_db": cfg.headroomDB,
            "isp_protection": cfg.ispProtectionEnabled,
            "nos_dither_mode": cfg.nosDitherMode.rawValue,
            "hog_mode": cfg.hogModeEnabled,
            "chunk_duration_ms": cfg.chunkDurationMs,
            "max_nos_pcm_rate": cfg.maxNOSPCMRateHz,
            "target_device_uid": cfg.targetDeviceUID ?? "",
            "is_running": tel.isRunning,
            "input_sample_rate": tel.inputSampleRateHz,
            "output_sample_rate": tel.outputSampleRateHz,
            "dop_carrier_rate": tel.dopCarrierRateHz,
            "active_clock_grid": tel.activeClockGrid.rawValue,
            "is_hog_mode": tel.isHogModeActive,
            "is_integer_mode": tel.isIntegerModeActive,
            "max_integrator_state": tel.maxIntegratorState,
            "isp_clip_count": tel.ispClipCount,
            "underrun_count": tel.underrunCount,
            "ring_buffer_fill_percent": tel.ringBufferFillPercent,
            "cpu_load_percent": tel.processingLoadPercent,
            "output_device_name": tel.outputDeviceName,
            "is_dlna_active": isDLNA,
            "usb_dac_available": usbAvail.hasEligibleUSBDAC,
            "supports_nos_pcm": usbAvail.supportsNOS,
            "supports_dsd_dop": usbAvail.supportsDSDDoP,
            "max_dsd_rate": usbAvail.maxDSDRate,
            "active_output_transport": usbAvail.activeTransportType,
            "usb_dac_name": usbAvail.eligibleDeviceName ?? "",
            "room_acoustic": RoomAcousticService.shared.statusDictionary(),
            "late_night_drc": LateNightDRCService.shared.statusDictionary(),
            "mastering_restoration": MasteringRestorationService.shared.statusDictionary()
        ]
    }
}
