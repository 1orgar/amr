//
//  WebSocketServer+Actions.swift
//  AppleMusicRemoteMac
//

import Foundation
import Network
import CoreAudio

extension WebSocketServer {
    // MARK: - Message Routing & Dispatcher

    private static let curateTasksLock = NSLock()
    private static var activeCurateTasks: [UUID: Task<Void, Never>] = [:]
    private static let clientLogRateLock = NSLock()
    private static var clientLogTimestamps: [UUID: [TimeInterval]] = [:]

    internal func cancelCurateTask(for clientId: UUID) {
        Self.curateTasksLock.withLock {
            Self.activeCurateTasks.removeValue(forKey: clientId)?.cancel()
        }
        curateTaskLock.withLock {
            activeCurateTasks.removeValue(forKey: clientId)?.cancel()
        }
        Self.clientLogRateLock.withLock {
            _ = Self.clientLogTimestamps.removeValue(forKey: clientId)
        }
    }

    internal func cancelAllCurateTasks() {
        Self.curateTasksLock.withLock {
            for (_, task) in Self.activeCurateTasks {
                task.cancel()
            }
            Self.activeCurateTasks.removeAll()
        }
        curateTaskLock.withLock {
            for (_, task) in activeCurateTasks {
                task.cancel()
            }
            activeCurateTasks.removeAll()
            activeCurateTask?.cancel()
            activeCurateTask = nil
        }
        Self.clientLogRateLock.withLock {
            Self.clientLogTimestamps.removeAll()
        }
    }

    private func sendCancelledCurateResponse(action: String, id: String?, requestId: Int? = nil, to connection: NWConnection) {
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

    func processClientTextMessage(_ text: String, clientId: UUID, connection: NWConnection) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            sendError(action: "unknown", error: "Invalid JSON format", id: nil, to: connection)
            return
        }

        let id = json["id"] as? String
        let action = (json["action"] as? String) ?? (json["command"] as? String) ?? (json["type"] as? String) ?? ""
        let params = (json["params"] as? [String: Any]) ?? (json["payload"] as? [String: Any]) ?? (json["data"] as? [String: Any]) ?? json

        let bridge = MusicBridge.shared
        let cloud = CloudCatalogService.shared

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

        // Handle Device Registration & Settings before authorization guard
        if actionLower == "register_device" {
            let rawDeviceId = (params["device_id"] as? String) ?? (params["deviceId"] as? String) ?? ""
            let rawDeviceName = (params["device_name"] as? String) ?? (params["deviceName"] as? String) ?? ""
            let rawDeviceType = (params["device_type"] as? String) ?? (params["deviceType"] as? String) ?? "mobile"
            let prefLockScreen = (params["lock_screen_controls"] as? Bool) ?? (params["lockScreenControls"] as? Bool)
            let inviteToken = (params["invite_token"] as? String) ?? (params["inviteToken"] as? String)
            let remoteIP = extractRemoteIP(from: connection)

            let record = ClientDeviceManager.shared.registerConnection(
                connectionId: clientId,
                deviceId: rawDeviceId,
                deviceName: rawDeviceName,
                deviceType: rawDeviceType,
                preferredLockScreen: prefLockScreen,
                remoteIP: remoteIP,
                inviteToken: inviteToken
            )
            sendEvent(name: "device_auth_status", data: record.dictionary, to: connection)
            sendSuccess(action: action, data: record.dictionary, id: id, to: connection)

            if record.isAuthorized {
                let status = bridge.getPlayerStatus()
                sendEvent("player_state_changed", data: status, to: connection)
                sendEvent(name: "ai_curator_settings", data: NativeMusicCuratorService.shared.getSettingsDictionary(), to: connection)
                let queue = await bridge.getPlaybackQueue()
                sendEvent("queue", data: queue, to: connection)
            }
            return
        }

        if actionLower == "update_device_settings" {
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
            guard isCallerOwnDevice || (isLoopback && boundDeviceId == nil) else {
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
            return
        }

        if actionLower == "get_device_status" {
            if let record = ClientDeviceManager.shared.getDeviceForConnection(connectionId: clientId) {
                sendEvent(name: "device_auth_status", data: record.dictionary, to: connection)
                sendSuccess(action: action, data: record.dictionary, id: id, to: connection)
            } else {
                sendError(action: action, error: "Device not registered", id: id, to: connection)
            }
            return
        }

        if actionLower != "ping" && !ClientDeviceManager.shared.isConnectionAuthorized(connectionId: clientId) {
            if let record = ClientDeviceManager.shared.getDeviceForConnection(connectionId: clientId) {
                sendEvent(name: "device_auth_status", data: record.dictionary, to: connection)
            }
            sendError(action: action, error: "Device pending authorization on Mac", id: id, to: connection)
            return
        }

        if actionLower == "get_share_access_qr" || actionLower == "generate_share_access_qr" {
            let payload = ClientDeviceManager.shared.generateShareAccessPayload()
            sendEvent(name: "share_access_qr", data: payload, to: connection)
            sendSuccess(action: action, data: payload, id: id, to: connection)
            return
        }

        switch actionLower {
        case "play", "start":
            let ok = bridge.play()
            var status = PlayerStatusEngine.shared.getPlayerStatus()
            status.playerState = "playing"
            if DLNADiscoveryManager.shared.hasActiveRenderer {
                DLNADiscoveryManager.shared.play()
            }
            broadcastStatus(status: status, includeQueue: false)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.broadcastStatus(includeQueue: false)
            }

        case "pause":
            let ok = bridge.pause()
            var status = PlayerStatusEngine.shared.getPlayerStatus()
            status.playerState = "paused"
            if DLNADiscoveryManager.shared.hasActiveRenderer {
                DLNADiscoveryManager.shared.pause()
            }
            broadcastStatus(status: status, includeQueue: false)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.broadcastStatus(includeQueue: false)
            }

        case "stop":
            let ok = bridge.stop()
            var status = PlayerStatusEngine.shared.getPlayerStatus()
            status.playerState = "stopped"
            if DLNADiscoveryManager.shared.hasActiveRenderer {
                DLNADiscoveryManager.shared.stopPlayback()
            }
            broadcastStatus(status: status, includeQueue: false)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.broadcastStatus(includeQueue: false)
            }

        case "play_pause", "toggle_play_pause":
            let ok = bridge.playPause()
            let status = PlayerStatusEngine.shared.getPlayerStatus()
            if DLNADiscoveryManager.shared.hasActiveRenderer {
                if status.isPlaying {
                    DLNADiscoveryManager.shared.play()
                } else {
                    DLNADiscoveryManager.shared.pause()
                }
            }
            broadcastStatus(status: status, includeQueue: false)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            // ScriptingBridge needs ~150-250ms to reflect state changes in Music.app.
            // Avoid immediate broadcast of stale state; broadcast after 250ms and 600ms.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.broadcastStatus(includeQueue: false)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.broadcastStatus(includeQueue: false)
            }

        case "next", "next_track":
            let ok = bridge.nextTrack()
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            try? await Task.sleep(nanoseconds: 800_000_000)
            let isRadio = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isRadioPlayback }
            broadcastStatus(includeQueue: !isRadio)

        case "previous", "prev", "previous_track":
            let ok = bridge.previousTrack()
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            try? await Task.sleep(nanoseconds: 800_000_000)
            let isRadio = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isRadioPlayback }
            broadcastStatus(includeQueue: !isRadio)

        case "seek":
            let pos = (params["position"] as? Double) ?? (params["pos"] as? Double) ?? 0
            let ok = bridge.seek(to: pos)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "position": pos], id: id, to: connection)
            broadcastStatus(includeQueue: false)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.broadcastStatus(includeQueue: false)
            }

        case "set_volume", "volume":
            var parsedVol: Int?
            if let num = params["volume"] as? NSNumber {
                parsedVol = num.intValue
            } else if let num = params["vol"] as? NSNumber {
                parsedVol = num.intValue
            } else if let d = params["volume"] as? Double, d.isFinite {
                parsedVol = Int(d)
            } else if let d = params["vol"] as? Double, d.isFinite {
                parsedVol = Int(d)
            } else if let s = params["volume"] as? String, let parsed = Int(s) {
                parsedVol = parsed
            }
            guard var volInt = parsedVol else {
                sendError(action: action, error: "Invalid volume value", id: id, to: connection)
                return
            }
            let maxAllowed = ExternalAmpTCPController.shared.isActive ? ExternalAmpTCPController.shared.maxVolumeCap : 100
            volInt = max(0, min(maxAllowed, volInt))
            let ok = bridge.setVolume(volInt)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "volume": volInt], id: id, to: connection)
            broadcastStatus(includeQueue: false)

        case "toggle_amp_mute", "set_amp_mute":
            let explicitMute = (params["muted"] as? Bool) ?? (params["mute"] as? Bool)
            ExternalAmpTCPController.shared.setMuted(explicitMute)
            sendSuccess(action: action, data: [
                "status": "ok",
                "amp_muted": ExternalAmpTCPController.shared.isMuted,
                "amp_volume": ExternalAmpTCPController.shared.currentVolume
            ], id: id, to: connection)
            broadcastStatus(includeQueue: false)

        case "duck", "activate_ducking":
            let reduction = (params["reduction"] as? Double) ?? ((params["reduction"] as? NSNumber)?.doubleValue) ?? (params["percent"] as? Double) ?? ((params["percent"] as? NSNumber)?.doubleValue) ?? 80.0
            let timeout = (params["timeout"] as? Double) ?? ((params["timeout"] as? NSNumber)?.doubleValue) ?? (params["duration"] as? Double) ?? ((params["duration"] as? NSNumber)?.doubleValue)
            let res = bridge.activateDucking(reductionPercent: reduction, timeout: timeout)
            sendSuccess(action: action, data: [
                "status": "ok",
                "is_ducked": true,
                "original_volume": res.originalVolume,
                "ducked_volume": res.duckedVolume,
                "volume": res.duckedVolume
            ], id: id, to: connection)
            broadcastStatus(includeQueue: false)

        case "unduck", "deactivate_ducking":
            let res = bridge.deactivateDucking()
            sendSuccess(action: action, data: [
                "status": "ok",
                "is_ducked": false,
                "restored_volume": res.restoredVolume,
                "volume": res.restoredVolume
            ], id: id, to: connection)
            broadcastStatus(includeQueue: false)

        case "set_ducking", "ducking":
            let enabled = (params["enabled"] as? Bool) ?? (params["active"] as? Bool) ?? true
            if enabled {
                let reduction = (params["reduction"] as? Double) ?? ((params["reduction"] as? NSNumber)?.doubleValue) ?? (params["percent"] as? Double) ?? ((params["percent"] as? NSNumber)?.doubleValue) ?? 80.0
                let timeout = (params["timeout"] as? Double) ?? ((params["timeout"] as? NSNumber)?.doubleValue) ?? (params["duration"] as? Double) ?? ((params["duration"] as? NSNumber)?.doubleValue)
                let res = bridge.activateDucking(reductionPercent: reduction, timeout: timeout)
                sendSuccess(action: action, data: [
                    "status": "ok",
                    "is_ducked": true,
                    "original_volume": res.originalVolume,
                    "ducked_volume": res.duckedVolume,
                    "volume": res.duckedVolume
                ], id: id, to: connection)
            } else {
                let res = bridge.deactivateDucking()
                sendSuccess(action: action, data: [
                    "status": "ok",
                    "is_ducked": false,
                    "restored_volume": res.restoredVolume,
                    "volume": res.restoredVolume
                ], id: id, to: connection)
            }
            broadcastStatus(includeQueue: false)

        case "set_shuffle", "shuffle":
            let enabled = (params["enabled"] as? Bool) ?? (params["shuffle"] as? Bool) ?? false
            let ok = bridge.setShuffle(enabled)
            broadcastStatus(includeQueue: false)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "shuffle": enabled], id: id, to: connection)

        case "set_repeat", "repeat":
            let mode = (params["mode"] as? String) ?? (params["repeat"] as? String) ?? "off"
            let ok = bridge.setRepeat(mode: mode)
            broadcastStatus(includeQueue: false)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "repeat": mode], id: id, to: connection)

        case "favorite", "toggle_favorite":
            let ok: Bool
            if let explicitFav = (params["favorited"] as? Bool) ?? (params["enabled"] as? Bool) {
                ok = bridge.setFavorite(explicitFav)
            } else {
                ok = bridge.toggleFavorite()
            }
            let newFav = PlayerStatusEngine.shared.currentFavoritedState().isFavorited
            broadcastStatus(includeQueue: false)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "favorited": newFav], id: id, to: connection)

        case "set_lock_volume_100", "lock_volume_100":
            let enabled = (params["enabled"] as? Bool) ?? (params["lock"] as? Bool) ?? (params["lock_volume_100"] as? Bool) ?? true
            PlaybackStateStore.shared.isVolumeLockedTo100 = enabled
            if enabled {
                PlaybackTransportController.shared.checkAndEnforceVolumeLock()
            }
            broadcastStatus(includeQueue: false)
            sendSuccess(action: action, data: ["status": "ok", "lock_volume_100": enabled], id: id, to: connection)

        case "set_dac_muting_guard", "dac_muting_guard":
            if let enabled = (params["enabled"] as? Bool) ?? (params["dac_muting_guard_enabled"] as? Bool) {
                CoreAudioDeviceManager.shared.isMutingGuardEnabled = enabled
            }
            if let duration = (params["duration_ms"] as? Int) ?? (params["dac_muting_guard_ms"] as? Int) {
                CoreAudioDeviceManager.shared.mutingGuardDurationMs = duration
            }
            broadcastStatus(includeQueue: false)
            sendSuccess(action: action, data: [
                "status": "ok",
                "dac_muting_guard_enabled": CoreAudioDeviceManager.shared.isMutingGuardEnabled,
                "dac_muting_guard_ms": CoreAudioDeviceManager.shared.mutingGuardDurationMs
            ], id: id, to: connection)

        case "get_dac_muting_guard":
            sendSuccess(action: action, data: [
                "status": "ok",
                "dac_muting_guard_enabled": CoreAudioDeviceManager.shared.isMutingGuardEnabled,
                "dac_muting_guard_ms": CoreAudioDeviceManager.shared.mutingGuardDurationMs
            ], id: id, to: connection)

        case "get_digital_booklet", "get_booklet":
            let reqAlbum = params["album"] as? String
            let reqArtist = params["artist"] as? String
            let reqAlbumId = (params["album_id"] as? String) ?? (params["id"] as? String)
            let reqTrack = (params["track"] as? String) ?? (params["name"] as? String)
            let reqRefresh = (params["refresh"] as? Bool) ?? false
            Task { [weak self] in
                guard let self = self else { return }
                let info = await DigitalBookletService.shared.resolveBooklet(
                    album: reqAlbum,
                    artist: reqArtist,
                    albumId: reqAlbumId,
                    trackName: reqTrack,
                    forceRefresh: reqRefresh
                )
                self.sendSuccess(action: action, data: info, id: id, to: connection)
            }

        case "search_and_play":
            let query = (params["query"] as? String) ?? (params["q"] as? String) ?? ""
            Task { [weak self] in
                guard let self = self else { return }
                let res = await bridge.searchAndPlayDetailed(query: query)
                var respData: [String: Any] = [
                    "status": res.success ? "ok" : "error",
                    "success": res.success
                ]
                if let st = res.station {
                    respData["station"] = st
                    respData["mode"] = "random_station"
                }
                if let q = res.query {
                    respData["query"] = q
                    respData["mode"] = "search"
                    if let cnt = res.count {
                        respData["count"] = cnt
                    }
                }
                self.sendSuccess(action: action, data: respData, id: id, to: connection)
                try? await Task.sleep(nanoseconds: 300_000_000)
                self.broadcastStatus(includeQueue: true)
            }

        case "get_status", "status", "player_status":
            let status = bridge.getPlayerStatus()
            sendSuccess(action: action, data: status, id: id, to: connection)

        case "get_playlists", "playlists":
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                let fastList = bridge.getPlaylists()
                self.sendSuccess(action: action, data: PlaylistsResponse(playlists: fastList), id: id, to: connection)

                let hasMissing = fastList.contains { ($0.artworkUrl?.isEmpty ?? true) }
                if hasMissing {
                    let enriched = await bridge.getPlaylistsWithArtworks()
                    self.sendEvent("playlists_result", data: PlaylistsResponse(playlists: enriched), to: connection)
                }
            }

        case "get_playlist_tracks", "playlist_tracks":
            let name = (params["name"] as? String) ?? (params["playlist"] as? String) ?? ""
            let plId = (params["id"] as? String) ?? (params["playlist_id"] as? String) ?? ""
            let urlStr = (params["url"] as? String) ?? ""
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                var resolvedId = plId
                if resolvedId.isEmpty && urlStr.contains("/playlist/") {
                    let clean = urlStr.components(separatedBy: "?").first ?? urlStr
                    if let last = clean.split(separator: "/").last, !last.isEmpty {
                        resolvedId = String(last)
                    }
                }
                if resolvedId.isEmpty && (name.hasPrefix("pl.") || name.hasPrefix("p.") || name.hasPrefix("favorite_") || name.hasPrefix("replay_")) {
                    resolvedId = name
                }
                var tracks = [TrackInfo]()
                let lowerName = name.lowercased()
                let isCloudPlaylistId = resolvedId.hasPrefix("pl.") || resolvedId.hasPrefix("p.")
                let isReplay = (resolvedId == "replay_playlist" || resolvedId.contains("replay") || lowerName.contains("replay") || lowerName.contains("итоги"))

                if isReplay {
                    tracks = await MusicKitManager.shared.getPersonalizedReplayTracks()
                } else if isCloudPlaylistId {
                    tracks = await MusicKitManager.shared.getPlaylistTracksById(playlistId: resolvedId)
                } else if !name.isEmpty {
                    // Check local library playlist first if no cloud playlist ID was passed
                    tracks = bridge.getPlaylistTracks(name: name)
                }

                if tracks.isEmpty {
                    var mixes = MusicKitManager.shared.getCachedPersonalData()?.mixes ?? []
                    if mixes.isEmpty {
                        mixes = await MusicKitManager.shared.fetchPersonalMixes()
                    }
                    if let m = mixes.first(where: {
                        let n = $0.name.lowercased()
                        if n == lowerName { return true }
                        if (lowerName.contains("повторе") || lowerName.contains("heavy rotation")) && (n.contains("повторе") || n.contains("heavy rotation")) { return true }
                        if (lowerName.contains("в моём вкусе") || lowerName.contains("в моем вкусе") || lowerName.contains("essentials") || lowerName.contains("favorites")) && (n.contains("в моём вкусе") || n.contains("в моем вкусе") || n.contains("favorites") || n.contains("избранн")) { return true }
                        if (lowerName.contains("chill") || lowerName.contains("чилл")) && (n.contains("chill") || n.contains("чилл")) { return true }
                        if (lowerName.contains("new music") || lowerName.contains("новинк")) && (n.contains("new music") || n.contains("новинк")) { return true }
                        if (lowerName.contains("get up") || lowerName.contains("энерги")) && (n.contains("get up") || n.contains("энерги")) { return true }
                        return false
                    }), let mid = m.id, !mid.isEmpty {
                        tracks = await MusicKitManager.shared.getPlaylistTracksById(playlistId: mid)
                    }
                }

                // Fallbacks if personal mix has no cloud tracks (unauthenticated or offline)
                if tracks.isEmpty && (lowerName.contains("повторе") || lowerName.contains("heavy rotation")) {
                    tracks = bridge.getRecentlyPlayed(limit: 50)
                    if tracks.isEmpty {
                        tracks = Array(bridge.getLibrarySongs().prefix(50))
                    }
                }
                if tracks.isEmpty && (lowerName.contains("в моём вкусе") || lowerName.contains("в моем вкусе") || lowerName.contains("essentials")) {
                    tracks = bridge.getPlaylistTracks(name: "Любимые песни")
                    if tracks.isEmpty {
                        tracks = bridge.getPlaylistTracks(name: "Favorites")
                    }
                    if tracks.isEmpty {
                        tracks = Array(bridge.getLibrarySongs().prefix(50))
                    }
                }

                if tracks.isEmpty && !name.isEmpty {
                    tracks = bridge.getPlaylistTracks(name: name)
                }

                self.sendSuccess(action: action, data: PlaylistTracksResponse(playlist: name, tracks: tracks), id: id, to: connection)

                // Pre-stage the first track of the cloud playlist/mix in the background so clicking "Слушать" starts immediately
                if !PlaybackRouter.shared.isTestingEnvironment,
                   MusicKitManager.shared.hasUserToken,
                   let firstTrack = tracks.first,
                   firstTrack.isLocal != true {
                    DispatchQueue.global(qos: .utility).async {
                        _ = MusicKitManager.shared.stageAndResolveCloudTrackInLibrarySync(
                            id: firstTrack.id,
                            url: firstTrack.url,
                            name: firstTrack.name,
                            artist: firstTrack.artist,
                            timeout: 6.0
                        )
                    }
                }

                let hasMissing = tracks.contains { !$0.hasArtwork || $0.artworkUrl.isEmpty }
                if hasMissing {
                    let enriched = await bridge.enrichTracksArtwork(tracks)
                    bridge.updatePlaylistTracksCache(name: name, tracks: enriched)
                    self.sendEvent("playlist_tracks", data: PlaylistTracksResponse(playlist: name, tracks: enriched), to: connection)
                }
            }

        case "get_artists", "get_library_artists":
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                let artists = bridge.getLibraryArtists()
                self.sendSuccess(action: action, data: ArtistsResponse(artists: artists), id: id, to: connection)
            }

        case "get_albums", "get_library_albums":
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                let albums = bridge.getLibraryAlbums()
                self.sendSuccess(action: action, data: AlbumsResponse(albums: albums), id: id, to: connection)
            }

        case "get_songs", "get_library_songs":
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                let songs = bridge.getLibrarySongs()
                self.sendSuccess(action: action, data: SongsResponse(songs: songs), id: id, to: connection)
            }

        case "get_stations", "stations":
            let country = (params["country"] as? String) ?? "ru"
            let stations = cloud.getCuratedStations(country: country)
            sendSuccess(action: action, data: StationsResponse(stations: stations), id: id, to: connection)

        case "play_station":
            let url = (params["url"] as? String) ?? ""
            let name = (params["name"] as? String) ?? "Apple Music Radio"
            let type = (params["type"] as? String) ?? ""
            let trackTitle = (params["title"] as? String) ?? (params["track"] as? String) ?? ""
            let artistName = (params["artist"] as? String) ?? ""
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                let ok = await bridge.playStation(url: url, name: name, type: type, trackTitle: trackTitle, artistName: artistName)
                self.broadcastStatus(includeQueue: true)
                self.sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "station": name], id: id, to: connection)
            }

        case "play_hero_card":
            let index = (params["index"] as? Int) ?? 0
            let name = (params["name"] as? String) ?? ""
            let artist = (params["artist"] as? String) ?? (params["subtitle"] as? String) ?? (params["sub"] as? String) ?? ""
            let cardId = params["id"] as? String
            let url = params["url"] as? String
            let type = params["type"] as? String
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                let ok = await bridge.playHeroCard(index: index, name: name, artist: artist, cardId: cardId, url: url, type: type)
                if ok {
                    for _ in 1...10 {
                        let (stOk, stOut) = AppleScriptExecutor.shared.execute("tell application \"Music\" to get player state as string")
                        if stOk, stOut?.trimmingCharacters(in: .whitespacesAndNewlines) == "playing" {
                            break
                        }
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }
                }
                self.sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "name": name], id: id, to: connection)
                self.broadcastStatus(includeQueue: true)
            }

        case "play_playlist":
            let plName = (params["playlist"] as? String) ?? (params["name"] as? String) ?? "Музыка"
            let plId = (params["id"] as? String) ?? (params["playlist_id"] as? String) ?? ""
            let urlStr = (params["url"] as? String) ?? ""
            let trackId = (params["track_id"] as? Int) ?? Int((params["track_id"] as? String) ?? "")
            let trackIdStr = (params["track_id"] as? String) ?? (params["track_id"] as? Int).map(String.init) ?? ""
            let trackIndex = (params["track_index"] as? Int) ?? Int((params["track_index"] as? String) ?? "")
            let shuffle = (params["shuffle"] as? Bool) ?? false
            let isExplicitLocal = (params["is_local"] as? Bool) ?? (params["isLocal"] as? Bool) ?? false

            var targetTracks = [TrackInfo]()
            if let rawTracks = params["tracks"] as? [[String: Any]], !rawTracks.isEmpty {
                for (idx, item) in rawTracks.enumerated() {
                    let tid = (item["id"] as? String) ?? "\(idx + 1)"
                    let numId = (item["numeric_id"] as? Int) ?? (item["numericId"] as? Int)
                    let tName = (item["name"] as? String) ?? ""
                    let tArtist = (item["artist"] as? String) ?? ""
                    let tAlbum = (item["album"] as? String) ?? ""
                    let tUrl = item["url"] as? String
                    let tArt = (item["artwork_url"] as? String) ?? (item["artwork"] as? String) ?? ""
                    let isLoc = (item["is_local"] as? Bool) ?? (item["isLocal"] as? Bool) ?? false
                    let dur = (item["duration"] as? Double) ?? 0.0
                    let catId = (item["catalog_id"] as? String) ?? (item["catalogId"] as? String) ?? (AppleSoundCheckService.isValidCatalogId(tid) ? tid : nil)
                    targetTracks.append(TrackInfo(
                        id: tid,
                        numericId: numId,
                        name: tName,
                        artist: tArtist,
                        album: tAlbum,
                        duration: dur,
                        hasArtwork: !tArt.isEmpty,
                        artworkUrl: tArt,
                        favorited: false,
                        isLocal: isLoc,
                        url: tUrl,
                        index: idx + 1,
                        catalogId: catId
                    ))
                }
            }

            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }

                // 0. If tracks were provided in payload (e.g. from Web UI modal for Heavy Rotation, Chill, New Music, Replay, Essentials):
                // Play directly without blocking on LibraryService.getPlaylists() first!
                if !targetTracks.isEmpty && !isExplicitLocal {
                    var startIdx = 0
                    if !trackIdStr.isEmpty, let found = targetTracks.firstIndex(where: { $0.id == trackIdStr || "\($0.numericId ?? -1)" == trackIdStr }) {
                        startIdx = found
                    } else if let tid = trackId, let found = targetTracks.firstIndex(where: { ($0.numericId ?? Int($0.id)) == tid }) {
                        startIdx = found
                    } else if let tIdx = trackIndex, tIdx > 0 {
                        startIdx = min(targetTracks.count - 1, tIdx - 1)
                    } else if shuffle && !targetTracks.isEmpty {
                        startIdx = Int.random(in: 0..<targetTracks.count)
                    }
                    var ok = false
                    if MusicKitManager.shared.hasUserToken {
                        ok = await bridge.playSearchResults(tracks: targetTracks, startIndex: startIdx, shuffle: shuffle, queueName: plName)
                    } else {
                        ok = bridge.playCustomTracks(targetTracks, startIndex: startIdx, shuffle: shuffle, queueName: plName)
                    }
                    self.sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "playlist": plName], id: id, to: connection)
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    self.broadcastStatus(includeQueue: true)
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    self.broadcastStatus(includeQueue: true)
                    return
                }

                // 1. Fast path for local library playlists (including added cloud playlists like "Мои любимые треки"):
                let localPlaylists = LibraryService.shared.getPlaylists()
                let lowerPl = plName.lowercased()
                let isEssentials = lowerPl.contains("essentials")
                let isChill = lowerPl.contains("chill") || lowerPl.contains("чилл")
                let isNewMusic = lowerPl.contains("new music") || lowerPl.contains("новинк")
                let isFavorites = lowerPl.contains("favorites") || lowerPl.contains("избранн") || lowerPl.contains("в моём вкусе") || lowerPl.contains("в моем вкусе")
                let isGetUp = lowerPl.contains("get up") || lowerPl.contains("энерги")

                func isPlaylistMatch(_ candidate: String) -> Bool {
                    let n = candidate.lowercased()
                    if n == lowerPl { return true }
                    if isEssentials && (n == "мои любимые треки" || n.contains("любимые треки")) { return true }
                    if isChill && (n.contains("chill") || n.contains("чилл")) { return true }
                    if isNewMusic && (n.contains("new music") || n.contains("новинк")) { return true }
                    if isFavorites {
                        if lowerPl == "любимые песни" && n == "любимые песни" { return true }
                        if n == "мои любимые треки" || n.contains("favorites") { return true }
                    }
                    if isGetUp && (n.contains("get up") || n.contains("энерги")) { return true }
                    return false
                }

                let hasExactLocalMatch = localPlaylists.contains(where: { $0.name.lowercased() == lowerPl })
                let isCloudMixId = plId.hasPrefix("pl.") || plId.hasPrefix("p.") || plName.hasPrefix("pl.") || plName.hasPrefix("p.")
                if isExplicitLocal || (targetTracks.isEmpty && !isCloudMixId && (hasExactLocalMatch || localPlaylists.contains(where: { isPlaylistMatch($0.name) }))) {
                    let matchName = localPlaylists.first(where: { $0.name.lowercased() == lowerPl })?.name
                        ?? localPlaylists.first(where: { isPlaylistMatch($0.name) })?.name
                        ?? plName
                    let localOk = bridge.playPlaylist(name: matchName, trackId: trackId, trackIndex: trackIndex, shuffle: shuffle)
                    for _ in 1...10 {
                        let (stOk, stOut) = AppleScriptExecutor.shared.execute("tell application \"Music\" to get player state as string")
                        if stOk, stOut?.trimmingCharacters(in: .whitespacesAndNewlines) == "playing" {
                            break
                        }
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }
                    self.sendSuccess(action: action, data: ["status": localOk ? "ok" : "error", "playlist": matchName], id: id, to: connection)
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    self.broadcastStatus(includeQueue: true)
                    return
                }

                // 2. If tracks were provided in payload (e.g. from Web UI modal for Chill, New Music, Replay, Essentials, or any playlist):
                // NEVER override explicit tracks with a random local playlist!
                if !targetTracks.isEmpty {
                    var startIdx = 0
                    if !trackIdStr.isEmpty, let found = targetTracks.firstIndex(where: { $0.id == trackIdStr || "\($0.numericId ?? -1)" == trackIdStr }) {
                        startIdx = found
                    } else if let tid = trackId, let found = targetTracks.firstIndex(where: { ($0.numericId ?? Int($0.id)) == tid }) {
                        startIdx = found
                    } else if let tIdx = trackIndex, tIdx > 0 {
                        startIdx = min(targetTracks.count - 1, tIdx - 1)
                    } else if shuffle && !targetTracks.isEmpty {
                        startIdx = Int.random(in: 0..<targetTracks.count)
                    }
                    var ok = false
                    if MusicKitManager.shared.hasUserToken {
                        ok = await bridge.playSearchResults(tracks: targetTracks, startIndex: startIdx, shuffle: shuffle, queueName: plName)
                    } else {
                        ok = bridge.playCustomTracks(targetTracks, startIndex: startIdx, shuffle: shuffle, queueName: plName)
                    }
                    self.sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "playlist": plName], id: id, to: connection)
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    self.broadcastStatus(includeQueue: true)
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    self.broadcastStatus(includeQueue: true)
                    return
                }

                // 3. If targetTracks was empty, check if this playlist exists in the local library by EXACT name
                if let matched = localPlaylists.first(where: {
                    let n = $0.name.lowercased()
                    return n == lowerPl
                }) {
                    let localOk = bridge.playPlaylist(name: matched.name, trackId: trackId, trackIndex: trackIndex, shuffle: shuffle)
                    if localOk {
                        self.sendSuccess(action: action, data: ["status": "ok", "playlist": matched.name], id: id, to: connection)
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        self.broadcastStatus(includeQueue: true)
                        return
                    }
                }

                // 4. Resolve cloud playlist ID or personal mixes
                var resolvedId = plId
                if resolvedId.isEmpty && urlStr.contains("/playlist/") {
                    let clean = urlStr.components(separatedBy: "?").first ?? urlStr
                    if let last = clean.split(separator: "/").last, !last.isEmpty {
                        resolvedId = String(last)
                    }
                }
                if resolvedId.isEmpty && (plName.hasPrefix("pl.") || plName.hasPrefix("p.") || plName.hasPrefix("favorite_") || plName.hasPrefix("replay_")) {
                    resolvedId = plName
                }
                if resolvedId.isEmpty {
                    let lower = plName.lowercased()
                    var mixes = MusicKitManager.shared.getCachedPersonalData()?.mixes ?? []
                    if mixes.isEmpty {
                        mixes = await MusicKitManager.shared.fetchPersonalMixes()
                    }
                    if let m = mixes.first(where: {
                        let n = $0.name.lowercased()
                        if n == lower { return true }
                        if (lower.contains("повторе") || lower.contains("heavy rotation")) && (n.contains("повторе") || n.contains("heavy rotation")) { return true }
                        if (lower.contains("в моём вкусе") || lower.contains("в моем вкусе") || lower.contains("essentials") || lower.contains("favorites")) && (n.contains("в моём вкусе") || n.contains("в моем вкусе") || n.contains("favorites") || n.contains("избранн")) { return true }
                        if (lower.contains("chill") || lower.contains("чилл")) && (n.contains("chill") || n.contains("чилл")) { return true }
                        if (lower.contains("new music") || lower.contains("новинк")) && (n.contains("new music") || n.contains("новинк")) { return true }
                        if (lower.contains("get up") || lower.contains("энерги")) && (n.contains("get up") || n.contains("энерги")) { return true }
                        return false
                    }), let mid = m.id, !mid.isEmpty {
                        resolvedId = mid
                    }
                }

                // 5. Fetch tracks for resolved cloud playlist
                let isReplay = (resolvedId == "replay_playlist" || resolvedId.contains("replay") || plName.lowercased().contains("replay") || plName.lowercased().contains("итоги"))
                if isReplay {
                    targetTracks = await MusicKitManager.shared.getPersonalizedReplayTracks()
                } else if !resolvedId.isEmpty && (resolvedId.hasPrefix("pl.") || resolvedId.hasPrefix("p.")) {
                    targetTracks = await MusicKitManager.shared.getPlaylistTracksById(playlistId: resolvedId)
                }

                if targetTracks.isEmpty {
                    let mixes = await MusicKitManager.shared.fetchPersonalMixes()
                    if let m = mixes.first(where: {
                        let n = $0.name.lowercased()
                        if n == lowerPl { return true }
                        if (lowerPl.contains("повторе") || lowerPl.contains("heavy rotation")) && (n.contains("повторе") || n.contains("heavy rotation")) { return true }
                        if (lowerPl.contains("в моём вкусе") || lowerPl.contains("в моем вкусе") || lowerPl.contains("essentials") || lowerPl.contains("favorites")) && (n.contains("в моём вкусе") || n.contains("в моем вкусе") || n.contains("favorites") || n.contains("избранн")) { return true }
                        if (lowerPl.contains("chill") || lowerPl.contains("чилл")) && (n.contains("chill") || n.contains("чилл")) { return true }
                        if (lowerPl.contains("new music") || lowerPl.contains("новинк")) && (n.contains("new music") || n.contains("новинк")) { return true }
                        if (lowerPl.contains("get up") || lowerPl.contains("энерги")) && (n.contains("get up") || n.contains("энерги")) { return true }
                        return false
                    }), let mid = m.id, !mid.isEmpty {
                        targetTracks = await MusicKitManager.shared.getPlaylistTracksById(playlistId: mid)
                    }
                }

                // Fallbacks for personal mixes if API unauthenticated or offline
                let lowerPlFinal = plName.lowercased()
                if targetTracks.isEmpty && (lowerPlFinal.contains("повторе") || lowerPlFinal.contains("heavy rotation")) {
                    targetTracks = bridge.getRecentlyPlayed(limit: 50)
                    if targetTracks.isEmpty {
                        targetTracks = Array(bridge.getLibrarySongs().prefix(50))
                    }
                }
                if targetTracks.isEmpty && (lowerPlFinal.contains("в моём вкусе") || lowerPlFinal.contains("в моем вкусе") || lowerPlFinal.contains("essentials")) {
                    targetTracks = bridge.getPlaylistTracks(name: "Любимые песни")
                    if targetTracks.isEmpty {
                        targetTracks = bridge.getPlaylistTracks(name: "Favorites")
                    }
                    if targetTracks.isEmpty {
                        targetTracks = Array(bridge.getLibrarySongs().prefix(50))
                    }
                }

                var ok = false
                if !targetTracks.isEmpty {
                    var startIdx = 0
                    if !trackIdStr.isEmpty, let found = targetTracks.firstIndex(where: { $0.id == trackIdStr || "\($0.numericId ?? -1)" == trackIdStr }) {
                        startIdx = found
                    } else if let tid = trackId, let found = targetTracks.firstIndex(where: { ($0.numericId ?? Int($0.id)) == tid }) {
                        startIdx = found
                    } else if let tIdx = trackIndex, tIdx > 0 {
                        startIdx = min(targetTracks.count - 1, tIdx - 1)
                    } else if shuffle && !targetTracks.isEmpty {
                        startIdx = Int.random(in: 0..<targetTracks.count)
                    }
                    if MusicKitManager.shared.hasUserToken {
                        ok = await bridge.playSearchResults(tracks: targetTracks, startIndex: startIdx, shuffle: shuffle, queueName: plName)
                    } else {
                        ok = bridge.playCustomTracks(targetTracks, startIndex: startIdx, shuffle: shuffle, queueName: plName)
                    }
                } else {
                    ok = bridge.playPlaylist(name: plName, trackId: trackId, trackIndex: trackIndex, shuffle: shuffle)
                }

                self.sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "playlist": plName], id: id, to: connection)
                try? await Task.sleep(nanoseconds: 200_000_000)
                self.broadcastStatus(includeQueue: true)
                try? await Task.sleep(nanoseconds: 600_000_000)
                self.broadcastStatus(includeQueue: true)
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                self.broadcastStatus(includeQueue: true)
            }

        case "play_history_index", "history_play_index":
            let idx = (params["index"] as? Int) ?? 0
            let ok = await bridge.playHistoryIndex(idx)
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)

        case "play_history_track", "history_play_track":
            let name = (params["name"] as? String) ?? ""
            let artist = (params["artist"] as? String) ?? ""
            let ok = await bridge.playHistoryTrack(name: name, artist: artist)
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)

        case "play_album", "play_album_tracks":
            let albumId = (params["id"] as? String) ?? (params["album_id"] as? String) ?? ""
            let name = (params["name"] as? String) ?? (params["title"] as? String) ?? ""
            let artist = (params["artist"] as? String) ?? ""
            let shuffle = (params["shuffle"] as? Bool) ?? false
            let trackIndex = (params["track_index"] as? Int) ?? (params["index"] as? Int) ?? 1
            let startIndex = max(0, trackIndex - 1)

            var customTracks = [TrackInfo]()
            if let rawTracks = params["tracks"] as? [[String: Any]] {
                for (idx, item) in rawTracks.enumerated() {
                    let tid = (item["id"] as? String) ?? "\(idx + 1)"
                    let numId = (item["numeric_id"] as? Int) ?? (item["numericId"] as? Int)
                    let tName = (item["name"] as? String) ?? ""
                    let tArtist = (item["artist"] as? String) ?? artist
                    let tAlbum = (item["album"] as? String) ?? name
                    let tUrl = item["url"] as? String
                    let tArt = (item["artwork_url"] as? String) ?? (item["artwork"] as? String) ?? ""
                    let isLoc = (item["is_local"] as? Bool) ?? (item["isLocal"] as? Bool) ?? false
                    let dur = (item["duration"] as? Double) ?? 0.0
                    customTracks.append(TrackInfo(
                        id: tid,
                        numericId: numId,
                        name: tName,
                        artist: tArtist,
                        album: tAlbum,
                        duration: dur,
                        hasArtwork: !tArt.isEmpty,
                        artworkUrl: tArt,
                        favorited: false,
                        isLocal: isLoc,
                        url: tUrl,
                        index: idx + 1
                    ))
                }
            }
            let targetCustomTracks = customTracks
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                let ok: Bool
                if !targetCustomTracks.isEmpty {
                    ok = await bridge.playAlbumWithTracks(tracks: targetCustomTracks, name: name, artist: artist, startIndex: startIndex, shuffle: shuffle)
                } else {
                    ok = await bridge.playAlbum(id: albumId, name: name, artist: artist, startIndex: startIndex, shuffle: shuffle)
                }
                self.broadcastStatus(includeQueue: true)
                self.sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "album": name], id: id, to: connection)
            }

        case "play_recent", "play_recently_played":
            let shuffle = (params["shuffle"] as? Bool) ?? false
            let ok = await bridge.playRecentTracks(shuffle: shuffle)
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)

        case "play_cloud":
            let url = params["url"] as? String
            let storeId = params["id"] as? String
            let name = (params["name"] as? String) ?? (params["title"] as? String) ?? ""
            let artist = (params["artist"] as? String) ?? ""
            let numericId = (params["numeric_id"] as? Int) ?? (params["numericId"] as? Int)
            let isLocal = (params["is_local"] as? Bool) ?? (params["isLocal"] as? Bool)
            let type = (params["type"] as? String)?.lowercased()
            let shuffle = (params["shuffle"] as? Bool) ?? false

            var isAlbum = (type == "album")
            var albumId = storeId ?? ""
            if !isAlbum, let u = url, u.contains("/album/"), !u.contains("?i="), !u.contains("/song/") {
                isAlbum = true
                if albumId.isEmpty {
                    let clean = u.components(separatedBy: "?").first ?? u
                    if let lastSegment = clean.split(separator: "/").last, !lastSegment.isEmpty {
                        albumId = String(lastSegment)
                    }
                }
            }
            let targetIsAlbum = isAlbum
            let targetAlbumId = albumId

            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                let ok: Bool
                if targetIsAlbum && !targetAlbumId.isEmpty {
                    ok = await bridge.playAlbum(id: targetAlbumId, name: name, artist: artist, shuffle: shuffle)
                } else {
                    ok = await bridge.playCloud(url: url, id: storeId, name: name, artist: artist, numericId: numericId, isLocal: isLocal)
                }
                self.broadcastStatus(includeQueue: true)
                self.sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            }

        case "play_search_results":
            let shuffle = (params["shuffle"] as? Bool) ?? false
            var trackInfos = [TrackInfo]()
            if let rawTracks = params["tracks"] as? [[String: Any]] {
                for (idx, item) in rawTracks.enumerated() {
                    let tid = (item["id"] as? String) ?? "\(idx + 1)"
                    let numId = (item["numeric_id"] as? Int) ?? (item["numericId"] as? Int)
                    let tName = (item["name"] as? String) ?? ""
                    let tArtist = (item["artist"] as? String) ?? ""
                    let tAlbum = (item["album"] as? String) ?? ""
                    let tUrl = item["url"] as? String
                    let tArt = (item["artwork_url"] as? String) ?? (item["artwork"] as? String) ?? ""
                    let isLoc = (item["is_local"] as? Bool) ?? (item["isLocal"] as? Bool) ?? false
                    let dur = (item["duration"] as? Double) ?? 0
                    let catId = (item["catalog_id"] as? String) ?? (item["catalogId"] as? String) ?? (AppleSoundCheckService.isValidCatalogId(tid) ? tid : nil)
                    trackInfos.append(TrackInfo(
                        id: tid,
                        numericId: numId,
                        name: tName,
                        artist: tArtist,
                        album: tAlbum,
                        duration: dur,
                        hasArtwork: !tArt.isEmpty,
                        artworkUrl: tArt,
                        favorited: false,
                        isLocal: isLoc,
                        url: tUrl,
                        index: idx + 1,
                        catalogId: catId
                    ))
                }
            }
            let startIndex = (params["startIndex"] as? Int) ?? (params["start_index"] as? Int) ?? (params["track_index"] as? Int).map { max(0, $0 - 1) } ?? 0
            let targetTracks = trackInfos
            let queueName = (params["queue_name"] as? String) ?? (params["queueName"] as? String)
            let searchQuery = (params["query"] as? String) ?? (params["q"] as? String)
            let curatorPrompt = (params["curator_prompt"] as? String) ?? (params["curatorPrompt"] as? String) ?? (params["ai_prompt"] as? String)
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                let t0 = Date()
                NSLog("[AICurator] play_search_results started (tracks=%d, startIndex=%d, queueName='%@', hasCuratorPrompt=%d)", targetTracks.count, startIndex, queueName ?? "", curatorPrompt != nil ? 1 : 0)
                let ok = await bridge.playSearchResults(tracks: targetTracks, startIndex: startIndex, shuffle: shuffle, queueName: queueName, query: searchQuery, curatorPrompt: curatorPrompt)
                let elapsedMs = Int(Date().timeIntervalSince(t0) * 1000)
                NSLog("[AICurator] play_search_results finished in %dms (ok=%d, tracks=%d)", elapsedMs, ok ? 1 : 0, targetTracks.count)
                self.sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "count": targetTracks.count], id: id, to: connection)
                self.broadcastStatus(includeQueue: true)
            }

        case "append_search_results", "append_queue":
            var trackInfos = [TrackInfo]()
            if let rawTracks = params["tracks"] as? [[String: Any]] {
                for (idx, item) in rawTracks.enumerated() {
                    let tid = (item["id"] as? String) ?? "\(idx + 1)"
                    let numId = (item["numeric_id"] as? Int) ?? (item["numericId"] as? Int)
                    let tName = (item["name"] as? String) ?? ""
                    let tArtist = (item["artist"] as? String) ?? ""
                    let tAlbum = (item["album"] as? String) ?? ""
                    let tUrl = item["url"] as? String
                    let tArt = (item["artwork_url"] as? String) ?? (item["artwork"] as? String) ?? ""
                    let isLoc = (item["is_local"] as? Bool) ?? (item["isLocal"] as? Bool) ?? false
                    let catId = (item["catalog_id"] as? String) ?? (item["catalogId"] as? String) ?? (AppleSoundCheckService.isValidCatalogId(tid) ? tid : nil)
                    trackInfos.append(TrackInfo(
                        id: tid,
                        numericId: numId,
                        name: tName,
                        artist: tArtist,
                        album: tAlbum,
                        duration: (item["duration"] as? Double) ?? 0,
                        hasArtwork: !tArt.isEmpty,
                        artworkUrl: tArt,
                        favorited: false,
                        isLocal: isLoc,
                        url: tUrl,
                        index: idx + 1,
                        catalogId: catId
                    ))
                }
            }
            let targetTracks = trackInfos
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                let ok = await bridge.appendTracksToAMRQueue(tracks: targetTracks)
                self.sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "appended": targetTracks.count], id: id, to: connection)
                self.broadcastStatus(includeQueue: true)
            }

        case "search":
            let query = (params["query"] as? String) ?? (params["q"] as? String) ?? ""
            var country = (params["country"] as? String) ?? "ru"
            if MusicKitManager.shared.hasUserToken {
                country = MusicKitManager.shared.getUserStorefront()
            }
            let source = (params["scope"] as? String) ?? (params["source"] as? String) ?? "all"
            let limit = (params["limit"] as? Int) ?? 50
            let offset = (params["offset"] as? Int) ?? 0
            let requestId = (json["request_id"] as? Int)
                ?? (params["request_id"] as? Int)
                ?? (json["requestId"] as? Int)
                ?? (params["requestId"] as? Int)
                ?? (json["request_id"] as? NSNumber)?.intValue
                ?? (params["request_id"] as? NSNumber)?.intValue
            var results = await cloud.search(query: query, country: country, source: source, limit: limit, offset: offset)
            if let reqId = requestId {
                results["request_id"] = AnyCodable(reqId)
            }
            sendSuccess(action: action, data: results, id: id, to: connection)

        case "get_developer_token":
            if let token = MusicKitManager.shared.getDeveloperToken() {
                sendSuccess(action: action, data: ["token": token], id: id, to: connection)
            } else {
                sendError(action: action, error: "Developer token unavailable", id: id, to: connection)
            }

        case "set_user_token", "user_token":
            if let token = (params["token"] as? String) ?? (params["user_token"] as? String), !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MusicKitManager.shared.setUserToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
                sendSuccess(action: action, data: ["status": "ok", "has_user_token": true, "storefront": MusicKitManager.shared.getUserStorefront()], id: id, to: connection)
            } else {
                MusicKitManager.shared.clearUserToken()
                sendSuccess(action: action, data: ["status": "ok", "has_user_token": false], id: id, to: connection)
            }

        case "get_user_token_status", "user_token_status":
            let hasToken = MusicKitManager.shared.hasUserToken
            sendSuccess(action: action, data: ["has_user_token": hasToken, "storefront": MusicKitManager.shared.getUserStorefront()], id: id, to: connection)

        case "get_audio_devices", "audio_devices":
            let isDLNAActive = DLNADiscoveryManager.shared.hasActiveRenderer
            var devices = CoreAudioDeviceManager.shared.getOutputDevices().map { dev -> [String: Any] in
                var dict = dev.dictionary
                if isDLNAActive {
                    dict["isDefault"] = false
                }
                return dict
            }
            if DLNADiscoveryManager.shared.isEnabled {
                devices.append(contentsOf: DLNADiscoveryManager.shared.getDiscoveredDevices())
            }
            let currentDev: [String: Any]?
            if let activeDLNA = DLNADiscoveryManager.shared.getActiveRenderer() {
                currentDev = activeDLNA.dictionary
            } else {
                currentDev = CoreAudioDeviceManager.shared.getDefaultOutputDevice()?.dictionary
            }
            sendSuccess(action: action, data: ["devices": devices, "current_device": currentDev as Any], id: id, to: connection)

        case "get_dlna_discovery_status":
            let isEnabled = DLNADiscoveryManager.shared.isEnabled
            let count = DLNADiscoveryManager.shared.getDiscoveredCount()
            sendSuccess(action: action, data: ["enabled": isEnabled, "discovered_count": count], id: id, to: connection)

        case "set_dlna_discovery":
            let enabled = (params["enabled"] as? Bool) ?? false
            if !enabled {
                let hadDLNA = DLNADiscoveryManager.shared.hasActiveRenderer
                if hadDLNA {
                    DLNADiscoveryManager.shared.stopPlayback()
                    DLNADiscoveryManager.shared.deselectRenderer()
                    AudioProcessTapService.shared.stopCapture()
                    if AudioProcessTapService.shared.hasSubscribers {
                        AudioProcessTapService.shared.startCapture()
                    }
                }
                let (wasMuted, restoreVol) = PlaybackStateStore.shared.withLock { () -> (Bool, Int) in
                    let m = PlaybackStateStore.shared.isDLNAMuted
                    let v = PlaybackStateStore.shared.preDLNAVolume > 0
                        ? PlaybackStateStore.shared.preDLNAVolume
                        : PlaybackStateStore.shared.simulatedVolume
                    PlaybackStateStore.shared.isDLNAMuted = false
                    return (m, v > 0 ? v : 100)
                }
                if wasMuted || hadDLNA {
                    AudioProcessTapService.shared.setMutingGuardZeroFill(false)
                    if wasMuted {
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
                }
            }
            DLNADiscoveryManager.shared.setEnabled(enabled)
            broadcastAudioDevices()
            broadcastStatus(includeQueue: false)
            sendSuccess(action: action, data: ["enabled": enabled, "status": "ok"], id: id, to: connection)

        case "get_local_dmr_status":
            let isEnabled = UPnPMediaRendererServer.shared.isEnabled
            sendSuccess(action: action, data: ["enabled": isEnabled], id: id, to: connection)

        case "set_local_dmr":
            let enabled = (params["enabled"] as? Bool) ?? false
            UPnPMediaRendererServer.shared.setEnabled(enabled)
            sendSuccess(action: action, data: ["enabled": enabled, "status": "ok"], id: id, to: connection)

        case "set_audio_device", "select_audio_device":
            let uidParam = (params["uid"] as? String) ?? ""
            let idNum = (params["id"] as? NSNumber)?.intValue ?? (params["id"] as? Int)

            // 1. Check if target is a DLNA MediaRenderer
            let isDLNATarget = uidParam.hasPrefix("dlna:") ||
                               (idNum != nil && DLNADiscoveryManager.shared.getDiscoveredRenderers().contains(where: { $0.numericId == idNum }))

            if isDLNATarget {
                let targetUID: String
                if uidParam.hasPrefix("dlna:") {
                    targetUID = uidParam
                } else if let id = idNum, let found = DLNADiscoveryManager.shared.getDiscoveredRenderers().first(where: { $0.numericId == id }) {
                    targetUID = "dlna:\(found.id)"
                } else {
                    targetUID = uidParam
                }

                if let dlnaDev = DLNADiscoveryManager.shared.selectRenderer(uid: targetUID) {
                    let status = MusicBridge.shared.getPlayerStatus()
                    if status.isPlaying {
                        AudioProcessTapService.shared.startCapture()

                        // Send UPnP AVTransport SetAVTransportURI & Play only when actively playing
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

                    broadcastAudioDevices()
                    broadcastStatus(includeQueue: false)
                    sendSuccess(action: action, data: ["status": "ok", "device_uid": targetUID, "name": dlnaDev.friendlyName], id: id, to: connection)
                    return
                } else {
                    sendError(action: action, error: "DLNA renderer not found or offline", id: id, to: connection)
                    return
                }
            }

            // 2. Otherwise target is a local CoreAudio device
            var targetId: AudioDeviceID?
            if let num = idNum {
                targetId = AudioDeviceID(num)
            } else if let idStr = params["id"] as? String, let parsed = UInt32(idStr) {
                targetId = AudioDeviceID(parsed)
            } else if !uidParam.isEmpty {
                targetId = CoreAudioDeviceManager.shared.getOutputDevices().first { $0.uid == uidParam }?.id
            }

            if let devId = targetId, CoreAudioDeviceManager.shared.setDefaultOutputDevice(id: devId) {
                let hadDLNA = DLNADiscoveryManager.shared.hasActiveRenderer
                // If DLNA was active, stop DLNA playback and deselect renderer
                if hadDLNA {
                    DLNADiscoveryManager.shared.stopPlayback()
                    DLNADiscoveryManager.shared.deselectRenderer()
                    AudioProcessTapService.shared.stopCapture()
                    if AudioProcessTapService.shared.hasSubscribers {
                        AudioProcessTapService.shared.startCapture()
                    }
                }

                let (wasMuted, restoreVol) = PlaybackStateStore.shared.withLock { () -> (Bool, Int) in
                    let m = PlaybackStateStore.shared.isDLNAMuted
                    let v = PlaybackStateStore.shared.preDLNAVolume > 0
                        ? PlaybackStateStore.shared.preDLNAVolume
                        : PlaybackStateStore.shared.simulatedVolume
                    PlaybackStateStore.shared.isDLNAMuted = false
                    return (m, v > 0 ? v : 100)
                }
                if wasMuted || hadDLNA {
                    AudioProcessTapService.shared.setMutingGuardZeroFill(false)
                    if wasMuted {
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
                }

                broadcastAudioDevices()
                broadcastStatus(includeQueue: false)
                let updated = CoreAudioDeviceManager.shared.getOutputDevices().map { $0.dictionary }
                sendSuccess(action: action, data: ["status": "ok", "device_id": Int(devId), "devices": updated], id: id, to: connection)
            } else {
                sendError(action: action, error: "Failed to switch audio output device", id: id, to: connection)
            }

        case "get_catalog_charts", "catalog_charts", "charts":
            let country = (params["country"] as? String) ?? "us"
            let songs = await MusicKitManager.shared.getTopCharts(storefront: country)
            sendSuccess(action: action, data: ["songs": songs], id: id, to: connection)

        case "get_explore", "explore":
            let country = (params["country"] as? String) ?? "ru"
            let feed = await cloud.getExploreFeed(country: country)
            sendSuccess(action: action, data: feed, id: id, to: connection)

        case "get_personal_mixes", "personal_mixes":
            let mixes = await MusicKitManager.shared.fetchPersonalMixes()
            let (personal, discovery) = await MusicKitManager.shared.fetchPersonalStations()
            var stationsList = [StationInfo]()
            if let p = personal { stationsList.append(p) }
            if let d = discovery { stationsList.append(d) }
            sendSuccess(action: action, data: PersonalMixesResponse(mixes: mixes, stations: stationsList), id: id, to: connection)

        case "get_personal_recommendations", "personal_recommendations":
            let limit = (params["limit"] as? Int) ?? 10
            let groups = await MusicKitManager.shared.fetchPersonalRecommendations(limit: limit)
            let dicts = groups.map { grp in
                [
                    "id": grp.id,
                    "title": grp.title,
                    "contents": grp.contents.map { res in
                        [
                            "id": res.id,
                            "type": res.type,
                            "name": res.name,
                            "subtitle": res.subtitle ?? "",
                            "artwork": res.artworkUrl ?? "",
                            "url": res.url ?? ""
                        ]
                    }
                ]
            }
            sendSuccess(action: action, data: ["recommendations": dicts], id: id, to: connection)

        case "get_album", "album":
            let albumId = (params["id"] as? String) ?? (params["album_id"] as? String) ?? ""
            let name = (params["name"] as? String) ?? (params["title"] as? String) ?? ""
            let artist = (params["artist"] as? String) ?? ""
            let defaultCountry = MusicKitManager.shared.hasUserToken
                ? MusicKitManager.shared.getUserStorefront()
                : MusicKitManager.shared.getPreferredLanguageTag()
            let country = (params["country"] as? String) ?? defaultCountry
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                var albumInfo = await cloud.getAlbumDetails(albumId: albumId, country: country)
                if albumInfo == nil && country != "us" {
                    albumInfo = await cloud.getAlbumDetails(albumId: albumId, country: "us")
                }
                if albumInfo == nil && country != "ru" {
                    albumInfo = await cloud.getAlbumDetails(albumId: albumId, country: "ru")
                }
                if albumInfo == nil && (!name.isEmpty || !artist.isEmpty) {
                    var trks = await MusicKitManager.shared.getAlbumTracks(album: name, artist: artist, storefront: country)
                    if trks.isEmpty && country != "us" {
                        trks = await MusicKitManager.shared.getAlbumTracks(album: name, artist: artist, storefront: "us")
                    }
                    if trks.isEmpty && country != "ru" {
                        trks = await MusicKitManager.shared.getAlbumTracks(album: name, artist: artist, storefront: "ru")
                    }
                    if trks.isEmpty && !name.isEmpty {
                        let targetAlbum = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let targetArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
                        let localMatches = bridge.getLibrarySongs().filter { song in
                            let sAlb = song.album.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard sAlb.localizedCaseInsensitiveCompare(targetAlbum) == .orderedSame else { return false }
                            if !targetArtist.isEmpty {
                                let sArt = song.artist.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !sArt.isEmpty && !sArt.localizedCaseInsensitiveContains(targetArtist) && !targetArtist.localizedCaseInsensitiveContains(sArt) {
                                    return false
                                }
                            }
                            return true
                        }
                        if !localMatches.isEmpty {
                            trks = localMatches
                        }
                    }
                    if !trks.isEmpty {
                        var resolvedAlbumId = albumId
                        if resolvedAlbumId.isEmpty, let firstUrl = trks.first?.url {
                            let cleanPath = firstUrl.components(separatedBy: "?").first ?? firstUrl
                            if let lastSeg = cleanPath.split(separator: "/").last, Int(lastSeg) != nil {
                                resolvedAlbumId = String(lastSeg)
                            }
                        }
                        albumInfo = AlbumInfo(
                            id: resolvedAlbumId,
                            name: name,
                            artist: artist,
                            artwork: trks.first?.artworkUrl ?? "",
                            releaseDate: nil,
                            trackCount: trks.count,
                            genre: nil,
                            url: nil,
                            tracks: trks
                        )
                    }
                }
                if let album = albumInfo {
                    self.sendSuccess(action: action, data: ["album": album], id: id, to: connection)
                    // Pre-stage the first track of the album in the background so clicking "Слушать" starts immediately
                    if !PlaybackRouter.shared.isTestingEnvironment,
                       MusicKitManager.shared.hasUserToken,
                       let firstTrack = album.tracks?.first,
                       firstTrack.isLocal != true {
                        DispatchQueue.global(qos: .utility).async {
                            _ = MusicKitManager.shared.stageAndResolveCloudTrackInLibrarySync(
                                id: firstTrack.id,
                                url: firstTrack.url,
                                name: firstTrack.name,
                                artist: firstTrack.artist,
                                timeout: 5.0
                            )
                        }
                    }
                } else {
                    self.sendError(action: action, error: "Album not found", id: id, to: connection)
                }
            }

        case "add_to_library":
            let trackId = params["track_id"] as? Int
            let name = params["name"] as? String
            let artist = params["artist"] as? String
            let url = params["url"] as? String
            let ok = bridge.addToLibrary(trackId: trackId, name: name, artist: artist, url: url)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)

        case "add_playlist_to_library", "add_album_to_library", "save_queue_to_playlist":
            let isSaveQueue = (action == "save_queue_to_playlist")
            let itemId = isSaveQueue ? "custom_queue" : ((params["id"] as? String) ?? (params["playlist_id"] as? String) ?? (params["album_id"] as? String) ?? "")
            let rawName = (params["name"] as? String) ?? (params["title"] as? String) ?? ""
            let itemArtist = (params["artist"] as? String) ?? ""
            let isAlbum = !isSaveQueue && ((action == "add_album_to_library") || ((params["is_album"] as? Bool) ?? false))
            let rawTracks = (params["tracks"] as? [[String: Any]]) ?? []
            let passedTrackInfos = rawTracks.map { parseTrackInfo($0) }
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                var trackInfos = passedTrackInfos
                var itemName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)

                if isSaveQueue || itemId == "custom_queue" || itemId == "ai_queue" {
                    let (customQueue, customName, curatorPrompt) = PlaybackStateStore.shared.withLock {
                        (
                            PlaybackStateStore.shared.activeCustomQueue,
                            PlaybackStateStore.shared.activeCustomQueueName,
                            PlaybackStateStore.shared.activeCuratorPrompt
                        )
                    }
                    if !customQueue.isEmpty && trackInfos.count < customQueue.count {
                        trackInfos = customQueue
                    } else if trackInfos.isEmpty {
                        let qInfo = await MusicBridge.shared.getPlaybackQueue()
                        trackInfos = qInfo.upcomingTracks
                    }
                    if itemName.isEmpty {
                        if let cn = customName?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !cn.isEmpty, cn != "Очередь AMR" {
                            itemName = cn
                        } else if let cp = curatorPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !cp.isEmpty {
                            itemName = cp.hasPrefix("✨") ? cp : "✨ \(cp)"
                        } else {
                            let df = DateFormatter()
                            df.dateFormat = "dd.MM"
                            itemName = "✨ Очередь AMR (\(df.string(from: Date())))"
                        }
                    }
                }

                let ok: Bool
                if isAlbum {
                    ok = await MusicBridge.shared.addAlbumToLibrary(albumId: itemId, name: itemName, artist: itemArtist, tracks: trackInfos)
                } else {
                    ok = await MusicBridge.shared.addPlaylistToLibrary(playlistId: itemId, name: itemName, tracks: trackInfos)
                }
                self.sendSuccess(
                    action: action,
                    data: [
                        "status": ok ? "ok" : "error",
                        "playlist": itemName,
                        "name": itemName,
                        "id": itemId,
                        "is_album": isAlbum,
                        "track_count": trackInfos.count
                    ],
                    id: id,
                    to: connection
                )
                if ok {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    let freshPlaylists = MusicBridge.shared.getPlaylists()
                    self.broadcastEvent("playlists_result", data: PlaylistsResponse(playlists: freshPlaylists))
                }
            }

        case "queue_add", "add_to_queue":
            var ok = false
            if let rawTracks = params["tracks"] as? [[String: Any]] {
                let trackInfos = rawTracks.map { parseTrackInfo($0) }
                ok = await bridge.enqueueTracks(trackInfos, playNext: false)
            } else if let rawTrack = params["track"] as? [String: Any] {
                let trackInfo = parseTrackInfo(rawTrack)
                ok = await bridge.enqueueTrack(trackInfo, playNext: false)
            }
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)

        case "queue_play_next":
            var ok = false
            if let rawTracks = params["tracks"] as? [[String: Any]] {
                let trackInfos = rawTracks.map { parseTrackInfo($0) }
                ok = await bridge.enqueueTracks(trackInfos, playNext: true)
            } else if let rawTrack = params["track"] as? [String: Any] {
                let trackInfo = parseTrackInfo(rawTrack)
                ok = await bridge.enqueueTrack(trackInfo, playNext: true)
            }
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)

        case "queue_remove":
            let idx = (params["index"] as? Int) ?? 0
            let ok = await bridge.removeQueueTrack(at: idx)
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)

        case "queue_clear":
            let ok = await bridge.clearUpcomingQueue()
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)

        case "queue_play_index", "play_queue_index":
            let idx = (params["index"] as? Int) ?? 0
            let ok = await bridge.playQueueIndex(idx)
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)

        case "get_queue", "queue":
            let q = await bridge.getPlaybackQueue()
            sendSuccess(action: action, data: q, id: id, to: connection)

        case "get_artwork", "artwork":
            if let isCur = params["current"] as? Bool, isCur {
                if let data = bridge.getCurrentTrackArtwork() {
                    let b64 = data.base64EncodedString()
                    sendSuccess(action: action, data: ["artwork_base64": b64, "mime": "image/jpeg"], id: id, to: connection)
                } else {
                    sendError(action: action, error: "No artwork found", id: id, to: connection)
                }
            } else if let tid = params["track_id"] as? Int {
                if let data = bridge.getTrackArtwork(id: tid) {
                    let b64 = data.base64EncodedString()
                    sendSuccess(action: action, data: ["artwork_base64": b64, "mime": "image/jpeg"], id: id, to: connection)
                } else {
                    sendError(action: action, error: "No artwork found", id: id, to: connection)
                }
            } else if let plName = params["playlist"] as? String {
                if let data = bridge.getPlaylistArtwork(name: plName) {
                    let b64 = data.base64EncodedString()
                    sendSuccess(action: action, data: ["artwork_base64": b64, "mime": "image/jpeg"], id: id, to: connection)
                } else {
                    sendError(action: action, error: "No artwork found", id: id, to: connection)
                }
            } else {
                sendError(action: action, error: "Missing parameters for artwork", id: id, to: connection)
            }

        case "get_account_status", "account_health":
            let force = (params["refresh"] as? Bool) ?? false
            let rawHealth = await AccountHealthService.shared.checkAccountHealth(forceRefresh: force)
            let health = Self.maskedAccountHealth(rawHealth)
            sendSuccess(action: action, data: health, id: id, to: connection)

        case "get_wled_settings", "wled_settings":
            let settings = WLEDDDPController.shared.getSettingsDictionary()
            sendSuccess(action: action, data: settings, id: id, to: connection)

        case "set_wled_settings":
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

        case "get_motion_artwork", "motion_artwork":
            let albumId = (params["album_id"] as? String) ?? (params["id"] as? String)
            let trackName = (params["track"] as? String) ?? (params["name"] as? String) ?? ""
            let artist = (params["artist"] as? String) ?? ""
            let albumName = (params["album"] as? String) ?? ""
            Task.detached(priority: .utility) { [weak self] in
                guard let self = self else { return }
                let motionUrl = await MusicKitManager.shared.resolveMotionArtworkUrl(
                    albumId: albumId,
                    trackName: trackName,
                    artist: artist,
                    albumName: albumName
                )
                self.sendSuccess(action: action, data: [
                    "motion_url": motionUrl ?? "",
                    "track": trackName,
                    "artist": artist,
                    "album": albumName
                ], id: id, to: connection)
            }

        case "get_spectral_analysis", "spectral_analysis":
            if SpectralIntegrityAnalyzer.shared.isEnabled && !AudioProcessTapService.shared.isRealTapActive && !PlaybackRouter.shared.isTestingEnvironment {
                _ = PlayerStatusEngine.shared.getPlayerStatus()
            }
            let analysis = SpectralIntegrityAnalyzer.shared.getCurrentAnalysis()
            sendSuccess(action: action, data: analysis, id: id, to: connection)

        case "ai_curate", "curate_music":
            let prompt = (params["prompt"] as? String) ?? (params["query"] as? String) ?? ""
            let storefront = (params["country"] as? String) ?? (params["storefront"] as? String) ?? MusicKitManager.shared.getUserStorefront()
            let autoPlay = (params["auto_play"] as? Bool) ?? (params["autoPlay"] as? Bool) ?? false
            let requestId = (json["request_id"] as? Int)
                ?? (params["request_id"] as? Int)
                ?? (json["requestId"] as? Int)
                ?? (params["requestId"] as? Int)
                ?? (json["request_id"] as? NSNumber)?.intValue
                ?? (params["request_id"] as? NSNumber)?.intValue
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
                if autoPlay {
                    curated["auto_play"] = true
                }
                if let reqId = requestId {
                    curated["request_id"] = reqId
                }
                self.sendSuccess(action: action, data: curated, id: id, to: connection)
            }
            Self.curateTasksLock.withLock {
                Self.activeCurateTasks[clientId]?.cancel()
                Self.activeCurateTasks[clientId] = task
            }
            curateTaskLock.withLock {
                activeCurateTasks[clientId]?.cancel()
                activeCurateTasks[clientId] = task
            }

        case "ai_curate_from_track", "play_ai_track_vibe":
            let trackName = (params["name"] as? String) ?? (params["title"] as? String) ?? ""
            let artist = (params["artist"] as? String) ?? ""
            let album = (params["album"] as? String) ?? ""
            let storefront = (params["country"] as? String) ?? (params["storefront"] as? String) ?? MusicKitManager.shared.getUserStorefront()
            let autoPlay = (params["auto_play"] as? Bool) ?? (params["autoPlay"] as? Bool) ?? true
            let requestId = (json["request_id"] as? Int)
                ?? (params["request_id"] as? Int)
                ?? (json["requestId"] as? Int)
                ?? (params["requestId"] as? Int)
                ?? (json["request_id"] as? NSNumber)?.intValue
                ?? (params["request_id"] as? NSNumber)?.intValue
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
                if autoPlay {
                    curated["auto_play"] = true
                }
                if let reqId = requestId {
                    curated["request_id"] = reqId
                }
                self.sendSuccess(action: action, data: curated, id: id, to: connection)
            }
            Self.curateTasksLock.withLock {
                Self.activeCurateTasks[clientId]?.cancel()
                Self.activeCurateTasks[clientId] = task
            }
            curateTaskLock.withLock {
                activeCurateTasks[clientId]?.cancel()
                activeCurateTasks[clientId] = task
            }

        case "toggle_ai_pin_prompt", "pin_ai_prompt":
            let prompt = (params["prompt"] as? String) ?? ""
            let label = (params["label"] as? String)
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

        case "get_artwork_palette", "artwork_palette":
            let url = (params["url"] as? String) ?? (params["artwork_url"] as? String)
            let trackId = (params["track_id"] as? Int) ?? (params["numeric_id"] as? Int) ?? (params["id"] as? Int)
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { return }
                guard let palette = await ArtworkService.shared.resolveArtworkPalette(url: url, trackId: trackId) else {
                    self.sendSuccess(action: action, data: ["status": "empty"], id: id, to: connection)
                    return
                }
                if NativeMusicCuratorService.shared.isEnabled,
                   let wledZones = palette["wled_zones"] as? [[Int]],
                   !wledZones.isEmpty {
                    WLEDDDPController.shared.updatePalette(wledZones)
                }
                self.sendSuccess(action: action, data: palette, id: id, to: connection)
            }

        case "get_ai_curator_settings", "ai_curator_settings", "refresh_ai_prompts":
            let exclude = (params["exclude_prompts"] as? [String]) ?? (params["excludePrompts"] as? [String]) ?? []
            let settings = NativeMusicCuratorService.shared.getSettingsDictionary(excludePrompts: exclude)
            sendEvent(name: "ai_curator_settings", data: settings, to: connection)
            sendSuccess(action: action, data: settings, id: id, to: connection)

        case "get_info", "info":
            let ips = getLANIPAddresses()
            let primaryUrl = ips.first.map { "http://\($0):\(self.port)" } ?? "http://localhost:\(self.port)"
            sendSuccess(action: action, data: [
                "port": self.port,
                "primary_url": primaryUrl,
                "ips": ips,
                "version": "2.5.0",
                "git_commit": ClientDeviceManager.shared.gitCommitShort,
                "git_commit_date": ClientDeviceManager.shared.gitCommitDate,
                "ai_curator_enabled": NativeMusicCuratorService.shared.isEnabled,
                "is_apple_silicon": NativeMusicCuratorService.shared.isAppleSilicon,
                "platform": "macOS"
            ], id: id, to: connection)

        default:
            sendError(action: action, error: "Unsupported action: \(action)", id: id, to: connection)
        }
    }

    func processClientBinaryMessage(_ data: Data, clientId: UUID? = nil, connection: NWConnection) async {
        if let cid = clientId, !ClientDeviceManager.shared.isConnectionAuthorized(connectionId: cid) {
            sendError(action: "binary", error: "Device pending authorization on Mac", id: nil, to: connection)
            return
        }
        sendSuccess(action: "binary", data: ["received_bytes": data.count], id: nil, to: connection)
    }

    private func parseTrackInfo(_ dict: [String: Any]) -> TrackInfo {
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
}
