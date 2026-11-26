//
//  WebSocketServer+AudioAndAIActions.swift
//  AppleMusicRemoteMac
//
//  CoreAudio/DLNA/UPnP output routing, WLED Ambilight, spectral analysis,
//  Apple Intelligence AI Curator / Sonic Bridge, TV mode config, and server info.
//

import CoreAudio
import Foundation
import Network

extension WebSocketServer {
    internal func handleAudioOrAIAction(
        action: String,
        actionLower: String,
        id: String?,
        json: [String: Any],
        params: [String: Any],
        clientId: UUID,
        connection: NWConnection
    ) async -> Bool {
        switch actionLower {
        case "get_audio_devices", "audio_devices":
            let isDLNAActive = DLNADiscoveryManager.shared.hasActiveRenderer
            let dspActiveDev = isDLNAActive ? nil : AudioEngineController.shared.activeHardwareOutputDeviceInfo
            let coreDevices = CoreAudioDeviceManager.shared.getOutputDevices()

            var devices = coreDevices.map { dev -> [String: Any] in
                var dict = dev.dictionary
                if isDLNAActive {
                    dict["isDefault"] = false
                } else if let dspDev = dspActiveDev {
                    dict["isDefault"] = (dev.id == dspDev.id)
                    if dev.id == dspDev.id {
                        let tel = AudioEngineController.shared.latestTelemetrySnapshot()
                        if tel.dopCarrierRateHz > 0 {
                            dict["sampleRate"] = Double(tel.dopCarrierRateHz)
                        }
                    }
                }
                return dict
            }
            if DLNADiscoveryManager.shared.isEnabled {
                devices.append(contentsOf: DLNADiscoveryManager.shared.getDiscoveredDevices())
            }
            let currentDev: [String: Any]?
            if let activeDLNA = DLNADiscoveryManager.shared.getActiveRenderer() {
                currentDev = activeDLNA.dictionary
            } else if let dspDev = dspActiveDev,
                      var matched = coreDevices.first(where: { $0.id == dspDev.id })?.dictionary {
                matched["isDefault"] = true
                let tel = AudioEngineController.shared.latestTelemetrySnapshot()
                if tel.dopCarrierRateHz > 0 {
                    matched["sampleRate"] = Double(tel.dopCarrierRateHz)
                }
                currentDev = matched
            } else {
                currentDev = CoreAudioDeviceManager.shared.getDefaultOutputDevice()?.dictionary
            }
            sendSuccess(action: action, data: ["devices": devices, "current_device": currentDev as Any], id: id, to: connection)
            return true

        case "get_dlna_discovery_status":
            let isEnabled = DLNADiscoveryManager.shared.isEnabled
            let count = DLNADiscoveryManager.shared.getDiscoveredCount()
            sendSuccess(action: action, data: ["enabled": isEnabled, "discovered_count": count], id: id, to: connection)
            return true

        case "set_dlna_discovery":
            guard ClientDeviceManager.shared.canConnectionSelectDAC(connectionId: clientId) else {
                if let record = ClientDeviceManager.shared.getDeviceForConnection(connectionId: clientId) {
                    sendEvent(name: "device_auth_status", data: record.dictionary, to: connection)
                }
                sendError(
                    action: action,
                    error: AMRLocalization.tr(
                        "DAC and audio output selection is disabled for this device in Mac settings",
                        "Выбор ЦАП и аудиовыхода отключён для этого устройства в настройках Mac"
                    ),
                    id: id,
                    to: connection
                )
                return true
            }
            let enabled = (params["enabled"] as? Bool) ?? false
            var shouldResumeLocalDSP = false
            var hadDLNA = false
            if !enabled {
                hadDLNA = DLNADiscoveryManager.shared.hasActiveRenderer
                if hadDLNA {
                    shouldResumeLocalDSP = true
                    DLNADiscoveryManager.shared.stopPlayback()
                    DLNADiscoveryManager.shared.deselectRenderer()
                } else if AudioEngineController.shared.currentConfigurationSnapshot().mode != .bitPerfectPassthrough {
                    shouldResumeLocalDSP = true
                }
                restoreVolumeAfterDLNADisconnect(hadDLNA: hadDLNA)
            }
            DLNADiscoveryManager.shared.setEnabled(enabled)
            if shouldResumeLocalDSP {
                _ = await AudioEngineController.shared.startOrReconfigurePipeline()
            }
            RoomAcousticService.shared.refreshLocalPassthroughEQPipeline()
            if hadDLNA {
                AudioProcessTapService.shared.reconcileCaptureAfterRouteChange()
            }
            broadcastAudioDevices()
            broadcastStatus(includeQueue: false)
            broadcastEvent(name: "dsp_settings", data: Self.buildDSPSettingsDictionary())
            broadcastEvent(name: "room_acoustic_settings", data: RoomAcousticService.shared.statusDictionary())
            sendSuccess(action: action, data: ["enabled": enabled, "status": "ok"], id: id, to: connection)
            return true

        case "deselect_dlna_renderer":
            guard ClientDeviceManager.shared.canConnectionSelectDAC(connectionId: clientId) else {
                if let record = ClientDeviceManager.shared.getDeviceForConnection(connectionId: clientId) {
                    sendEvent(name: "device_auth_status", data: record.dictionary, to: connection)
                }
                sendError(
                    action: action,
                    error: AMRLocalization.tr(
                        "DAC and audio output selection is disabled for this device in Mac settings",
                        "Выбор ЦАП и аудиовыхода отключён для этого устройства в настройках Mac"
                    ),
                    id: id,
                    to: connection
                )
                return true
            }
            let hadActiveDLNA = DLNADiscoveryManager.shared.hasActiveRenderer
            if hadActiveDLNA {
                DLNADiscoveryManager.shared.stopPlayback()
                DLNADiscoveryManager.shared.deselectRenderer()
            }
            restoreVolumeAfterDLNADisconnect(hadDLNA: hadActiveDLNA)
            if AudioEngineController.shared.currentConfigurationSnapshot().mode != .bitPerfectPassthrough {
                _ = await AudioEngineController.shared.startOrReconfigurePipeline()
            }
            RoomAcousticService.shared.refreshLocalPassthroughEQPipeline()
            if hadActiveDLNA {
                AudioProcessTapService.shared.reconcileCaptureAfterRouteChange()
            }
            broadcastAudioDevices()
            broadcastStatus(includeQueue: false)
            broadcastEvent(name: "dsp_settings", data: Self.buildDSPSettingsDictionary())
            broadcastEvent(name: "room_acoustic_settings", data: RoomAcousticService.shared.statusDictionary())
            DispatchQueue.main.async {
                MenuManager.shared.updateMenuState()
                SettingsWindow.refreshIfVisible()
            }
            sendSuccess(action: action, data: ["status": "ok"], id: id, to: connection)
            return true

        case "get_local_dmr_status":
            let isEnabled = UPnPMediaRendererServer.shared.isEnabled
            sendSuccess(action: action, data: ["enabled": isEnabled], id: id, to: connection)
            return true

        case "set_local_dmr":
            guard ClientDeviceManager.shared.canConnectionSelectDAC(connectionId: clientId) else {
                if let record = ClientDeviceManager.shared.getDeviceForConnection(connectionId: clientId) {
                    sendEvent(name: "device_auth_status", data: record.dictionary, to: connection)
                }
                sendError(
                    action: action,
                    error: AMRLocalization.tr(
                        "DAC and audio output selection is disabled for this device in Mac settings",
                        "Выбор ЦАП и аудиовыхода отключён для этого устройства в настройках Mac"
                    ),
                    id: id,
                    to: connection
                )
                return true
            }
            let enabled = (params["enabled"] as? Bool) ?? false
            UPnPMediaRendererServer.shared.setEnabled(enabled)
            sendSuccess(action: action, data: ["enabled": enabled, "status": "ok"], id: id, to: connection)
            return true

        case "set_audio_device", "select_audio_device":
            await handleSelectAudioDeviceAction(action: action, id: id, params: params, clientId: clientId, connection: connection)
            return true

        case "get_wled_settings", "wled_settings":
            let settings = WLEDDDPController.shared.getSettingsDictionary()
            sendSuccess(action: action, data: settings, id: id, to: connection)
            return true

        case "set_wled_settings":
            guard ClientDeviceManager.shared.canConnectionModifyLibrary(connectionId: clientId) else {
                if let record = ClientDeviceManager.shared.getDeviceForConnection(connectionId: clientId) {
                    sendEvent(name: "device_auth_status", data: record.dictionary, to: connection)
                }
                sendError(
                    action: action,
                    error: AMRLocalization.tr(
                        "Modifying WLED lighting settings is disabled for this device in Mac settings",
                        "Изменение настроек подсветки WLED отключено для этого устройства в настройках Mac"
                    ),
                    id: id,
                    to: connection
                )
                return true
            }
            let enabled = params["enabled"] as? Bool
            let ip = params["ip"] as? String
            let mode = params["mode"] as? String
            let ledCount = (params["led_count"] as? Int) ?? (params["ledCount"] as? Int)
            let brightness = (params["brightness"] as? Double)
            let defaultTVMode = (params["default_tv_mode"] as? Bool) ?? (params["defaultTvMode"] as? Bool)
            let updated = WLEDDDPController.shared.updateSettings(
                enabled: enabled,
                ip: ip,
                mode: mode,
                ledCount: ledCount,
                brightness: brightness,
                defaultTVMode: defaultTVMode
            )
            sendSuccess(action: action, data: updated, id: id, to: connection)
            broadcastEvent(name: "wled_settings", data: updated)
            DispatchQueue.main.async {
                SettingsWindow.refreshIfVisible()
            }
            return true

        case "update_wled_palette", "wled_palette":
            var colorList: [[Int]] = []
            if let rawColors = params["colors"] as? [[Any]] {
                for arr in rawColors {
                    let ints = arr.compactMap { ($0 as? NSNumber)?.intValue ?? ($0 as? Int) }
                    if ints.count >= 3 {
                        colorList.append(Array(ints.prefix(3)))
                    }
                }
            }
            WLEDDDPController.shared.updatePalette(colorList)
            sendSuccess(action: action, data: ["status": "ok"], id: id, to: connection)
            return true

        case "get_spectral_rta", "spectral_rta":
            ensureSpectralTapAwakeNonBlocking()
            let compact = SpectralIntegrityAnalyzer.shared.getCompactRTAPayload()
            sendSuccess(action: action, data: compact, id: id, to: connection)
            return true

        case "get_spectral_analysis", "spectral_analysis":
            ensureSpectralTapAwakeNonBlocking()
            let analysis = SpectralIntegrityAnalyzer.shared.getCurrentAnalysis()
            sendSuccess(action: action, data: analysis, id: id, to: connection)
            return true

        case "ai_curate", "curate_music":
            let prompt = (params["prompt"] as? String) ?? (params["query"] as? String) ?? ""
            let storefront = MusicKitManager.shared.resolveEffectiveStorefront((params["country"] as? String) ?? (params["storefront"] as? String))
            let autoPlay = (params["auto_play"] as? Bool) ?? (params["autoPlay"] as? Bool) ?? false
            let requestId = Self.extractRequestId(json: json, params: params)
            let task = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                if Task.isCancelled {
                    self.sendCancelledCurateResponse(action: action, id: id, requestId: requestId, to: connection)
                    return
                }
                var curated = await NativeMusicCuratorService.shared.curateMusicSession(prompt: prompt, storefront: storefront)
                if Task.isCancelled || (curated["status"] as? String) == "cancelled" {
                    self.sendCancelledCurateResponse(action: action, id: id, requestId: requestId, to: connection)
                    return
                }
                if autoPlay { curated["auto_play"] = true }
                if let reqId = requestId { curated["request_id"] = reqId }
                self.sendSuccess(action: action, data: curated, id: id, to: connection)
            }
            curateTaskLock.withLock {
                activeCurateTasks[clientId]?.cancel()
                activeCurateTasks[clientId] = task
            }
            return true

        case "ai_curate_from_track", "play_ai_track_vibe":
            let trackName = (params["name"] as? String) ?? (params["title"] as? String) ?? ""
            let artist = (params["artist"] as? String) ?? ""
            let album = (params["album"] as? String) ?? ""
            let storefront = MusicKitManager.shared.resolveEffectiveStorefront((params["country"] as? String) ?? (params["storefront"] as? String))
            let autoPlay = (params["auto_play"] as? Bool) ?? (params["autoPlay"] as? Bool) ?? true
            let requestId = Self.extractRequestId(json: json, params: params)
            let task = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                if Task.isCancelled {
                    self.sendCancelledCurateResponse(action: action, id: id, requestId: requestId, to: connection)
                    return
                }
                var curated = await NativeMusicCuratorService.shared.curateSessionFromTrack(
                    name: trackName,
                    artist: artist,
                    album: album,
                    storefront: storefront
                )
                if Task.isCancelled || (curated["status"] as? String) == "cancelled" {
                    self.sendCancelledCurateResponse(action: action, id: id, requestId: requestId, to: connection)
                    return
                }
                if autoPlay { curated["auto_play"] = true }
                if let reqId = requestId { curated["request_id"] = reqId }
                self.sendSuccess(action: action, data: curated, id: id, to: connection)
            }
            curateTaskLock.withLock {
                activeCurateTasks[clientId]?.cancel()
                activeCurateTasks[clientId] = task
            }
            return true

        case "build_sonic_bridge", "sonic_bridge":
            let fromQuery = (params["from_query"] as? String) ?? (params["from"] as? String) ?? (params["point_a"] as? String) ?? ""
            let toQuery = (params["to_query"] as? String) ?? (params["to"] as? String) ?? (params["point_b"] as? String) ?? ""
            let stepCount = (params["step_count"] as? Int) ?? (params["steps"] as? Int) ?? (params["step_count"] as? NSNumber)?.intValue ?? 12
            let storefront = MusicKitManager.shared.resolveEffectiveStorefront((params["country"] as? String) ?? (params["storefront"] as? String))
            let autoPlay = (params["auto_play"] as? Bool) ?? (params["autoPlay"] as? Bool) ?? false
            let requestId = Self.extractRequestId(json: json, params: params)
            let task = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                if Task.isCancelled {
                    self.sendCancelledCurateResponse(action: action, id: id, requestId: requestId, to: connection)
                    return
                }
                var bridge = await NativeMusicCuratorService.shared.buildSonicBridge(
                    fromQuery: fromQuery,
                    toQuery: toQuery,
                    stepCount: stepCount,
                    storefront: storefront
                )
                if Task.isCancelled || (bridge["status"] as? String) == "cancelled" {
                    self.sendCancelledCurateResponse(action: action, id: id, requestId: requestId, to: connection)
                    return
                }
                if autoPlay { bridge["auto_play"] = true }
                if let reqId = requestId { bridge["request_id"] = reqId }
                self.sendSuccess(action: action, data: bridge, id: id, to: connection)
            }
            curateTaskLock.withLock {
                activeCurateTasks[clientId]?.cancel()
                activeCurateTasks[clientId] = task
            }
            return true

        case "toggle_ai_pin_prompt", "pin_ai_prompt":
            let prompt = (params["prompt"] as? String) ?? ""
            let label = params["label"] as? String
            let labelRu = (params["label_ru"] as? String) ?? (params["labelRu"] as? String)
            let promptRu = (params["prompt_ru"] as? String) ?? (params["promptRu"] as? String)
            let labelEn = (params["label_en"] as? String) ?? (params["labelEn"] as? String)
            let promptEn = (params["prompt_en"] as? String) ?? (params["promptEn"] as? String)
            let isPinned = NativeMusicCuratorService.shared.togglePinPrompt(
                prompt: prompt,
                label: label,
                labelRu: labelRu,
                promptRu: promptRu,
                labelEn: labelEn,
                promptEn: promptEn
            )
            var settings = NativeMusicCuratorService.shared.getSettingsDictionary()
            settings["toggled_prompt"] = prompt
            settings["is_pinned"] = isPinned
            broadcastEvent(name: "ai_curator_settings", data: settings)
            sendSuccess(action: action, data: settings, id: id, to: connection)
            return true

        case "get_artwork_palette", "artwork_palette":
            let url = (params["url"] as? String) ?? (params["artwork_url"] as? String)
            let trackId = (params["track_id"] as? Int) ?? (params["numeric_id"] as? Int) ?? (params["id"] as? Int)
            guard let palette = await ArtworkService.shared.resolveArtworkPalette(url: url, trackId: trackId) else {
                sendSuccess(action: action, data: ["status": "empty"], id: id, to: connection)
                return true
            }
            if NativeMusicCuratorService.shared.isEnabled {
                let ambientRgb = palette["ambient_rgb"] as? [[Int]]
                let wledZones = (palette["wled_zones"] as? [[Int]]) ?? []
                if !wledZones.isEmpty || (ambientRgb?.isEmpty == false) {
                    WLEDDDPController.shared.updateCoverPalette(ambientRGB: ambientRgb, spatialZones: wledZones)
                }
            }
            sendSuccess(action: action, data: palette, id: id, to: connection)
            return true

        case "get_ai_curator_settings", "ai_curator_settings", "refresh_ai_prompts":
            let exclude = (params["exclude_prompts"] as? [String]) ?? (params["excludePrompts"] as? [String]) ?? []
            let settings = NativeMusicCuratorService.shared.getSettingsDictionary(excludePrompts: exclude)
            sendEvent(name: "ai_curator_settings", data: settings, to: connection)
            sendSuccess(action: action, data: settings, id: id, to: connection)
            return true

        case "get_tv_library_config", "tv_library_config":
            sendSuccess(action: action, data: TVLibraryConfigurationStore.shared.toDictionary(), id: id, to: connection)
            return true

        case "set_tv_library_config":
            guard ClientDeviceManager.shared.isConnectionAuthorized(connectionId: clientId) else {
                sendError(action: action, error: "Device pending authorization on Mac", id: id, to: connection)
                return true
            }
            _ = TVLibraryConfigurationStore.shared.applyDictionary(params)
            let payload = TVLibraryConfigurationStore.shared.toDictionary()
            broadcastEvent(name: "tv_library_config", data: payload)
            DispatchQueue.main.async {
                SettingsWindow.refreshIfVisible()
            }
            sendSuccess(action: action, data: payload, id: id, to: connection)
            return true

        case "get_info", "info":
            let ips = getLANIPAddresses()
            let primaryUrl = ips.first.map { "http://\($0):\(self.port)" } ?? "http://localhost:\(self.port)"
            sendSuccess(action: action, data: [
                "port": self.port,
                "primary_url": primaryUrl,
                "ips": ips,
                "version": "3.0.0",
                "git_commit": ClientDeviceManager.shared.gitCommitShort,
                "git_commit_date": ClientDeviceManager.shared.gitCommitDate,
                "ai_curator_enabled": NativeMusicCuratorService.shared.isEnabled,
                "is_apple_silicon": NativeMusicCuratorService.shared.isAppleSilicon,
                "platform": "macOS"
            ], id: id, to: connection)
            return true

        default:
            return false
        }
    }

    private static func extractRequestId(json: [String: Any], params: [String: Any]) -> Int? {
        return (json["request_id"] as? Int)
            ?? (params["request_id"] as? Int)
            ?? (json["requestId"] as? Int)
            ?? (params["requestId"] as? Int)
            ?? (json["request_id"] as? NSNumber)?.intValue
            ?? (params["request_id"] as? NSNumber)?.intValue
    }

    private func restoreVolumeAfterDLNADisconnect(hadDLNA: Bool) {
        let (wasMuted, restoreVol) = PlaybackStateStore.shared.withLock { () -> (Bool, Int) in
            let m = PlaybackStateStore.shared.isDLNAMuted
            let v = PlaybackStateStore.shared.preDLNAVolume > 0
                ? PlaybackStateStore.shared.preDLNAVolume
                : PlaybackStateStore.shared.simulatedVolume
            PlaybackStateStore.shared.isDLNAMuted = false
            return (m, v > 0 ? v : 100)
        }
        guard wasMuted || hadDLNA else { return }
        AudioProcessTapService.shared.setMutingGuardZeroFill(false)
        guard wasMuted else { return }
        if AudioDuckingController.shared.isDucked {
            let duckVol = AudioDuckingController.shared.currentDuckedVolume
            _ = PlaybackTransportController.shared.setVolume(duckVol, isFromDuckingController: true)
        } else if PlaybackStateStore.shared.isVolumeLockedTo100 {
            if let app = MusicAppProvider.shared.getMusicApp() {
                app.soundVolume = 100
            }
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.simulatedVolume = 100
            }
            PlaybackStateStore.shared.invalidateStatusCache()
        } else {
            _ = MusicBridge.shared.setVolume(restoreVol)
        }
    }

    private func handleSelectAudioDeviceAction(
        action: String,
        id: String?,
        params: [String: Any],
        clientId: UUID,
        connection: NWConnection
    ) async {
        guard ClientDeviceManager.shared.canConnectionSelectDAC(connectionId: clientId) else {
            if let record = ClientDeviceManager.shared.getDeviceForConnection(connectionId: clientId) {
                sendEvent(name: "device_auth_status", data: record.dictionary, to: connection)
            }
            sendError(
                action: action,
                error: AMRLocalization.tr(
                    "DAC and audio output selection is disabled for this device in Mac settings",
                    "Выбор ЦАП и аудиовыхода отключён для этого устройства в настройках Mac"
                ),
                id: id,
                to: connection
            )
            return
        }
        let uidParam = (params["uid"] as? String) ?? ""
        let idNum = (params["id"] as? NSNumber)?.intValue ?? (params["id"] as? Int)

        let isDLNATarget = uidParam.hasPrefix("dlna:") ||
            (idNum != nil && DLNADiscoveryManager.shared.getDiscoveredRenderers().contains(where: { $0.numericId == idNum }))

        if isDLNATarget {
            let targetUID: String
            if uidParam.hasPrefix("dlna:") {
                targetUID = uidParam
            } else if let devNum = idNum, let found = DLNADiscoveryManager.shared.getDiscoveredRenderers().first(where: { $0.numericId == devNum }) {
                targetUID = "dlna:\(found.id)"
            } else {
                targetUID = uidParam
            }

            if let dlnaDev = DLNADiscoveryManager.shared.selectRenderer(uid: targetUID) {
                await AudioEngineController.shared.suspendForDLNARouting()
                let status = MusicBridge.shared.getPlayerStatus()
                if status.isPlaying {
                    AudioProcessTapService.shared.startCapture()
                    let (streamURL, imageURL, fullTitle, metadata) = DLNADiscoveryManager.shared.resolveStreamAndImageURLs()
                    DLNADiscoveryManager.shared.setAVTransportURI(uri: streamURL, metadata: metadata, imageURL: imageURL, title: fullTitle) { success, _ in
                        if success, !dlnaDev.isBluOS {
                            DLNADiscoveryManager.shared.play()
                        }
                    }
                } else {
                    let isLossy = status.audioQuality.contains("AAC") || status.audioQuality.contains("MP3")
                    let targetRate = isLossy ? 44100 : (status.track?.sampleRate ?? 44100)
                    let targetDepth = isLossy ? 16 : (status.track?.bitDepth ?? (targetRate >= 48000 ? 24 : 16))
                    AudioProcessTapService.shared.setFormat(sampleRate: targetRate, bitDepth: targetDepth)
                }

                RoomAcousticService.shared.refreshLocalPassthroughEQPipeline()
                broadcastAudioDevices()
                broadcastStatus(includeQueue: false)
                broadcastEvent(name: "dsp_settings", data: Self.buildDSPSettingsDictionary())
                broadcastEvent(name: "room_acoustic_settings", data: RoomAcousticService.shared.statusDictionary())
                DispatchQueue.main.async {
                    MenuManager.shared.updateMenuState()
                    SettingsWindow.refreshIfVisible()
                }
                sendSuccess(action: action, data: ["status": "ok", "device_uid": targetUID, "name": dlnaDev.friendlyName], id: id, to: connection)
            } else {
                sendError(action: action, error: "DLNA renderer not found or offline", id: id, to: connection)
            }
            return
        }

        var targetId: AudioDeviceID?
        if let num = idNum {
            targetId = AudioDeviceID(num)
        } else if let idStr = params["id"] as? String, let parsed = UInt32(idStr) {
            targetId = AudioDeviceID(parsed)
        } else if !uidParam.isEmpty {
            targetId = CoreAudioDeviceManager.shared.getOutputDevices().first { $0.uid == uidParam }?.id
        }

        let isKnownLocalDevice = targetId.map { tid in
            CoreAudioDeviceManager.shared.getOutputDevices().contains(where: { $0.id == tid })
        } ?? false
        let isDSPConfigured = (AudioEngineController.shared.currentConfigurationSnapshot().mode != .bitPerfectPassthrough)

        if let devId = targetId,
           isKnownLocalDevice,
           (CoreAudioDeviceManager.shared.setDefaultOutputDevice(id: devId) || isDSPConfigured) {
            let hadDLNA = DLNADiscoveryManager.shared.hasActiveRenderer
            if hadDLNA {
                DLNADiscoveryManager.shared.stopPlayback()
                DLNADiscoveryManager.shared.deselectRenderer()
            }
            restoreVolumeAfterDLNADisconnect(hadDLNA: hadDLNA)

            if isDSPConfigured {
                await AudioEngineController.shared.handleUserSelectedLocalDevice(id: devId)
            }
            RoomAcousticService.shared.refreshLocalPassthroughEQPipeline()
            if hadDLNA {
                AudioProcessTapService.shared.reconcileCaptureAfterRouteChange()
            }

            broadcastAudioDevices()
            broadcastStatus(includeQueue: false)
            broadcastEvent(name: "dsp_settings", data: Self.buildDSPSettingsDictionary())
            broadcastEvent(name: "room_acoustic_settings", data: RoomAcousticService.shared.statusDictionary())
            DispatchQueue.main.async {
                MenuManager.shared.updateMenuState()
                SettingsWindow.refreshIfVisible()
            }
            let updated = CoreAudioDeviceManager.shared.getOutputDevices().map { $0.dictionary }
            sendSuccess(action: action, data: ["status": "ok", "device_id": Int(devId), "devices": updated], id: id, to: connection)
        } else {
            sendError(action: action, error: "Failed to switch audio output device", id: id, to: connection)
        }
    }
}
