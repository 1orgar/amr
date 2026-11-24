//
//  WebSocketServer+TransportActions.swift
//  AppleMusicRemoteMac
//
//  Transport controls, volume/ducking/amp-mute, DAC guard, digital booklet,
//  search_and_play, player status, and Up Next queue actions.
//

import Foundation
import Network

extension WebSocketServer {
    internal func handleTransportOrQueueAction(
        action: String,
        actionLower: String,
        id: String?,
        params: [String: Any],
        clientId: UUID,
        connection: NWConnection
    ) async -> Bool {
        let bridge = MusicBridge.shared

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
            return true

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
            return true

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
            return true

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
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.broadcastStatus(includeQueue: false)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.broadcastStatus(includeQueue: false)
            }
            return true

        case "next", "next_track":
            let ok = bridge.nextTrack()
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.8) { [weak self] in
                let isRadio = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isRadioPlayback }
                self?.broadcastStatus(includeQueue: !isRadio)
            }
            return true

        case "previous", "prev", "previous_track":
            let ok = bridge.previousTrack()
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.8) { [weak self] in
                let isRadio = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isRadioPlayback }
                self?.broadcastStatus(includeQueue: !isRadio)
            }
            return true

        case "seek":
            let pos = (params["position"] as? Double) ?? (params["pos"] as? Double) ?? 0
            let ok = bridge.seek(to: pos)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "position": pos], id: id, to: connection)
            broadcastStatus(includeQueue: false)
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.broadcastStatus(includeQueue: false)
            }
            return true

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
                return true
            }
            let maxAllowed = ExternalAmpTCPController.shared.isActive ? ExternalAmpTCPController.shared.maxVolumeCap : 100
            volInt = max(0, min(maxAllowed, volInt))
            let ok = bridge.setVolume(volInt)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "volume": volInt], id: id, to: connection)
            broadcastStatus(includeQueue: false)
            return true

        case "toggle_amp_mute", "set_amp_mute":
            guard ClientDeviceManager.shared.canConnectionModifyLibrary(connectionId: clientId) else {
                if let record = ClientDeviceManager.shared.getDeviceForConnection(connectionId: clientId) {
                    sendEvent(name: "device_auth_status", data: record.dictionary, to: connection)
                }
                sendError(action: action, error: "Управление усилителем отключено для этого устройства в настройках Mac", id: id, to: connection)
                return true
            }
            let explicitMute = (params["muted"] as? Bool) ?? (params["mute"] as? Bool)
            ExternalAmpTCPController.shared.setMuted(explicitMute)
            sendSuccess(action: action, data: [
                "status": "ok",
                "amp_muted": ExternalAmpTCPController.shared.isMuted,
                "amp_volume": ExternalAmpTCPController.shared.currentVolume
            ], id: id, to: connection)
            broadcastStatus(includeQueue: false)
            return true

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
            return true

        case "unduck", "deactivate_ducking":
            let res = bridge.deactivateDucking()
            sendSuccess(action: action, data: [
                "status": "ok",
                "is_ducked": false,
                "restored_volume": res.restoredVolume,
                "volume": res.restoredVolume
            ], id: id, to: connection)
            broadcastStatus(includeQueue: false)
            return true

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
            return true

        case "set_shuffle", "shuffle":
            let enabled = (params["enabled"] as? Bool) ?? (params["shuffle"] as? Bool) ?? false
            let ok = bridge.setShuffle(enabled)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "shuffle": enabled], id: id, to: connection)
            return true

        case "set_repeat", "repeat":
            let mode = (params["mode"] as? String) ?? (params["repeat"] as? String) ?? "off"
            let ok = bridge.setRepeat(mode: mode)
            let appliedMode = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.repeatMode }
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "repeat": appliedMode], id: id, to: connection)
            return true

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
            return true

        case "set_lock_volume_100", "lock_volume_100":
            guard ClientDeviceManager.shared.canConnectionSelectDAC(connectionId: clientId) else {
                if let record = ClientDeviceManager.shared.getDeviceForConnection(connectionId: clientId) {
                    sendEvent(name: "device_auth_status", data: record.dictionary, to: connection)
                }
                sendError(action: action, error: "Выбор ЦАП и параметров аудиовыхода отключён для этого устройства в настройках Mac", id: id, to: connection)
                return true
            }
            let enabled = (params["enabled"] as? Bool) ?? (params["lock"] as? Bool) ?? (params["lock_volume_100"] as? Bool) ?? true
            PlaybackStateStore.shared.isVolumeLockedTo100 = enabled
            if enabled {
                PlaybackTransportController.shared.checkAndEnforceVolumeLock()
            }
            broadcastStatus(includeQueue: false)
            sendSuccess(action: action, data: ["status": "ok", "lock_volume_100": enabled], id: id, to: connection)
            return true

        case "set_dac_muting_guard", "dac_muting_guard":
            guard ClientDeviceManager.shared.canConnectionSelectDAC(connectionId: clientId) else {
                if let record = ClientDeviceManager.shared.getDeviceForConnection(connectionId: clientId) {
                    sendEvent(name: "device_auth_status", data: record.dictionary, to: connection)
                }
                sendError(action: action, error: "Выбор ЦАП и параметров аудиовыхода отключён для этого устройства в настройках Mac", id: id, to: connection)
                return true
            }
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
            return true

        case "get_dac_muting_guard":
            sendSuccess(action: action, data: [
                "status": "ok",
                "dac_muting_guard_enabled": CoreAudioDeviceManager.shared.isMutingGuardEnabled,
                "dac_muting_guard_ms": CoreAudioDeviceManager.shared.mutingGuardDurationMs
            ], id: id, to: connection)
            return true

        case "get_digital_booklet", "get_booklet":
            let reqAlbum = params["album"] as? String
            let reqArtist = params["artist"] as? String
            let reqAlbumId = (params["album_id"] as? String) ?? (params["id"] as? String)
            let reqTrack = (params["track"] as? String) ?? (params["name"] as? String)
            let reqRefresh = (params["refresh"] as? Bool) ?? false
            let info = await DigitalBookletService.shared.resolveBooklet(
                album: reqAlbum,
                artist: reqArtist,
                albumId: reqAlbumId,
                trackName: reqTrack,
                forceRefresh: reqRefresh
            )
            sendSuccess(action: action, data: info, id: id, to: connection)
            return true

        case "search_and_play":
            let query = (params["query"] as? String) ?? (params["q"] as? String) ?? ""
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
            sendSuccess(action: action, data: respData, id: id, to: connection)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.broadcastStatus(includeQueue: true)
            }
            return true

        case "get_status", "status", "player_status":
            let status = bridge.getPlayerStatus()
            sendSuccess(action: action, data: status, id: id, to: connection)
            return true

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
            return true

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
            return true

        case "queue_remove":
            let idx = (params["index"] as? Int) ?? 0
            let ok = await bridge.removeQueueTrack(at: idx)
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            return true

        case "queue_clear":
            let ok = await bridge.clearUpcomingQueue()
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            return true

        case "queue_play_index", "play_queue_index":
            let idx = (params["index"] as? Int) ?? 0
            let ok = await bridge.playQueueIndex(idx)
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            return true

        case "get_queue", "queue":
            let q = await bridge.getPlaybackQueue()
            sendSuccess(action: action, data: q, id: id, to: connection)
            return true

        default:
            return false
        }
    }
}
