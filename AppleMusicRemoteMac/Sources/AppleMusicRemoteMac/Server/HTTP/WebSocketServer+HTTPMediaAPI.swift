//
//  WebSocketServer+HTTPMediaAPI.swift
//  AppleMusicRemoteMac
//
//  REST POST /api/media endpoint handler for authorized clients and automation scripts.
//

import Foundation
import Network

extension WebSocketServer {
    internal func handleMediaAPI(headerString: String = "", fullPath: String = "", bodyData: Data, connection: NWConnection) async {
        guard let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any],
              let endpoint = (json["endpoint"] as? String)?.lowercased() else {
            let errResp: [String: Any] = ["status": "error", "message": "Missing endpoint in JSON payload"]
            let data = (try? JSONSerialization.data(withJSONObject: errResp)) ?? Data()
            sendHTTPResponse(status: "400 Bad Request", contentType: "application/json; charset=utf-8", body: data, connection: connection)
            return
        }

        let params = (json["params"] as? [String: Any]) ?? [:]
        let bridge = MusicBridge.shared
        var resultData: [String: Any] = ["status": "ok", "endpoint": endpoint]

        switch endpoint {
        case "play":
            let ok = bridge.play()
            var status = PlayerStatusEngine.shared.getPlayerStatus()
            status.playerState = "playing"
            if DLNADiscoveryManager.shared.hasActiveRenderer {
                DLNADiscoveryManager.shared.play()
            }
            broadcastStatus(status: status, includeQueue: false)
            resultData["success"] = ok

        case "pause":
            let ok = bridge.pause()
            var status = PlayerStatusEngine.shared.getPlayerStatus()
            status.playerState = "paused"
            if DLNADiscoveryManager.shared.hasActiveRenderer {
                DLNADiscoveryManager.shared.pause()
            }
            broadcastStatus(status: status, includeQueue: false)
            resultData["success"] = ok

        case "play_pause":
            let ok = bridge.playPause()
            resultData["success"] = ok
            if DLNADiscoveryManager.shared.hasActiveRenderer {
                let st = PlayerStatusEngine.shared.getPlayerStatus()
                if st.isPlaying {
                    DLNADiscoveryManager.shared.play()
                } else {
                    DLNADiscoveryManager.shared.pause()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.broadcastStatus(includeQueue: false)
            }

        case "next":
            let ok = bridge.nextTrack()
            resultData["success"] = ok
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.broadcastStatus(includeQueue: true)
            }

        case "previous":
            let ok = bridge.previousTrack()
            resultData["success"] = ok
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.broadcastStatus(includeQueue: true)
            }

        case "stop":
            let ok = bridge.stop()
            resultData["success"] = ok
            if DLNADiscoveryManager.shared.hasActiveRenderer {
                DLNADiscoveryManager.shared.stopPlayback()
            }
            broadcastStatus(includeQueue: false)

        case "set_volume":
            var parsedVol: Int?
            if let num = params["volume"] as? NSNumber {
                parsedVol = num.intValue
            } else if let num = params["vol"] as? NSNumber {
                parsedVol = num.intValue
            } else if let num = params["volume"] as? Int {
                parsedVol = num
            } else if let d = params["volume"] as? Double, d.isFinite {
                parsedVol = Int(d)
            } else if let s = params["volume"] as? String, let parsed = Int(s) {
                parsedVol = parsed
            }
            guard var vol = parsedVol else {
                resultData["success"] = false
                resultData["error"] = "Invalid volume value"
                break
            }
            let maxAllowed = ExternalAmpTCPController.shared.isActive ? ExternalAmpTCPController.shared.maxVolumeCap : 100
            vol = max(0, min(maxAllowed, vol))
            let ok = bridge.setVolume(vol)
            resultData["success"] = ok
            resultData["volume"] = vol

        case "set_lock_volume_100", "lock_volume_100":
            let queryDeviceId = extractQueryParameter(named: "device_id", from: fullPath)
                ?? extractQueryParameter(named: "deviceid", from: fullPath)
            let bodyTopDeviceId = (json["device_id"] as? String) ?? (json["deviceId"] as? String)
            let bodyParamDeviceId = (params["device_id"] as? String) ?? (params["deviceId"] as? String)
            let resolvedDeviceId = nonEmpty(extractHeader(named: "x-amr-device-id", from: headerString))
                ?? nonEmpty(extractCookie(named: "amr_device_uid", from: headerString))
                ?? nonEmpty(queryDeviceId)
                ?? nonEmpty(bodyTopDeviceId)
                ?? nonEmpty(bodyParamDeviceId)

            let dacDisabledErr = AMRLocalization.tr(
                "DAC and audio output selection is disabled for this device in Mac settings",
                "Выбор ЦАП и аудиовыхода отключён для этого устройства в настройках Mac"
            )
            if let devId = resolvedDeviceId {
                guard canDeviceSelectDAC(deviceId: devId) else {
                    sendHTTPResponse(
                        status: "403 Forbidden",
                        contentType: "application/json; charset=utf-8",
                        body: Data("{\"status\":\"error\",\"error\":\"\(dacDisabledErr)\"}".utf8),
                        connection: connection
                    )
                    return
                }
            } else if isLocalhostConnection(connection) {
                guard canLocalhostSelectDAC() else {
                    sendHTTPResponse(
                        status: "403 Forbidden",
                        contentType: "application/json; charset=utf-8",
                        body: Data("{\"status\":\"error\",\"error\":\"\(dacDisabledErr)\"}".utf8),
                        connection: connection
                    )
                    return
                }
            } else {
                sendHTTPResponse(
                    status: "403 Forbidden",
                    contentType: "application/json; charset=utf-8",
                    body: Data("{\"status\":\"error\",\"error\":\"Missing device_id for DAC volume lock\"}".utf8),
                    connection: connection
                )
                return
            }

            let enabled = (params["enabled"] as? Bool) ?? (params["lock"] as? Bool) ?? (params["lock_volume_100"] as? Bool) ?? true
            PlaybackStateStore.shared.isVolumeLockedTo100 = enabled
            if enabled {
                PlaybackTransportController.shared.checkAndEnforceVolumeLock()
            }
            resultData["success"] = true
            resultData["lock_volume_100"] = enabled
            broadcastStatus(includeQueue: false)

        case "duck", "activate_ducking":
            let reduction = (params["reduction"] as? Double) ?? ((params["reduction"] as? NSNumber)?.doubleValue) ?? (params["percent"] as? Double) ?? ((params["percent"] as? NSNumber)?.doubleValue) ?? 80.0
            let timeout = (params["timeout"] as? Double) ?? ((params["timeout"] as? NSNumber)?.doubleValue) ?? (params["duration"] as? Double) ?? ((params["duration"] as? NSNumber)?.doubleValue)
            let res = bridge.activateDucking(reductionPercent: reduction, timeout: timeout)
            resultData["success"] = true
            resultData["is_ducked"] = true
            resultData["original_volume"] = res.originalVolume
            resultData["ducked_volume"] = res.duckedVolume
            resultData["volume"] = res.duckedVolume
            broadcastStatus(includeQueue: false)

        case "unduck", "deactivate_ducking":
            let res = bridge.deactivateDucking()
            resultData["success"] = true
            resultData["is_ducked"] = false
            resultData["restored_volume"] = res.restoredVolume
            resultData["volume"] = res.restoredVolume
            broadcastStatus(includeQueue: false)

        case "set_ducking", "ducking":
            let enabled = (params["enabled"] as? Bool) ?? (params["active"] as? Bool) ?? true
            if enabled {
                let reduction = (params["reduction"] as? Double) ?? ((params["reduction"] as? NSNumber)?.doubleValue) ?? (params["percent"] as? Double) ?? ((params["percent"] as? NSNumber)?.doubleValue) ?? 80.0
                let timeout = (params["timeout"] as? Double) ?? ((params["timeout"] as? NSNumber)?.doubleValue) ?? (params["duration"] as? Double) ?? ((params["duration"] as? NSNumber)?.doubleValue)
                let res = bridge.activateDucking(reductionPercent: reduction, timeout: timeout)
                resultData["success"] = true
                resultData["is_ducked"] = true
                resultData["original_volume"] = res.originalVolume
                resultData["ducked_volume"] = res.duckedVolume
                resultData["volume"] = res.duckedVolume
            } else {
                let res = bridge.deactivateDucking()
                resultData["success"] = true
                resultData["is_ducked"] = false
                resultData["restored_volume"] = res.restoredVolume
                resultData["volume"] = res.restoredVolume
            }
            broadcastStatus(includeQueue: false)

        case "search_and_play":
            let query = (params["query"] as? String) ?? (params["q"] as? String) ?? ""
            let res = await bridge.searchAndPlayDetailed(query: query)
            resultData["success"] = res.success
            if let st = res.station {
                resultData["station"] = st
                resultData["mode"] = "random_station"
            }
            if let q = res.query {
                resultData["query"] = q
                resultData["mode"] = "search"
                if let cnt = res.count {
                    resultData["count"] = cnt
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.broadcastStatus(includeQueue: true)
            }

        case "status":
            let status = bridge.getPlayerStatus()
            if let enc = try? JSONEncoder().encode(status),
               let dict = try? JSONSerialization.jsonObject(with: enc) as? [String: Any] {
                resultData["data"] = dict
            }

        case "play_playlist":
            let plName = (params["playlist"] as? String) ?? (params["name"] as? String) ?? "Музыка"
            let trackId = (params["track_id"] as? Int) ?? Int((params["track_id"] as? String) ?? "")
            let trackIndex = (params["track_index"] as? Int) ?? (params["trackIndex"] as? Int) ?? Int((params["track_index"] as? String) ?? "")
            let shuffle = (params["shuffle"] as? Bool) ?? false
            let ok = bridge.playPlaylist(name: plName, trackId: trackId, trackIndex: trackIndex, shuffle: shuffle)
            resultData["success"] = ok
            resultData["playlist"] = plName
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.broadcastStatus(includeQueue: true)
            }

        case "play_queue_index", "queue_play_index":
            let idx = (params["index"] as? Int) ?? 0
            let ok = await bridge.playQueueIndex(idx)
            resultData["success"] = ok
            resultData["index"] = idx
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.broadcastStatus(includeQueue: true)
            }

        case "play_history_index", "history_play_index":
            let idx = (params["index"] as? Int) ?? 0
            let ok = await bridge.playHistoryIndex(idx)
            resultData["success"] = ok
            resultData["index"] = idx
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.broadcastStatus(includeQueue: true)
            }

        case "queue":
            let queue = await bridge.getPlaybackQueue()
            if let enc = try? JSONEncoder().encode(queue),
               let dict = try? JSONSerialization.jsonObject(with: enc) as? [String: Any] {
                resultData["data"] = dict
            }

        case "search":
            let query = (params["query"] as? String) ?? (params["q"] as? String) ?? ""
            let country = MusicKitManager.shared.resolveEffectiveStorefront((params["country"] as? String) ?? (params["storefront"] as? String))
            let source = (params["scope"] as? String) ?? (params["source"] as? String) ?? "all"
            let results = await CloudCatalogService.shared.search(query: query, country: country, source: source)
            if let enc = try? JSONEncoder().encode(results),
               let obj = try? JSONSerialization.jsonObject(with: enc) as? [String: Any] {
                resultData["data"] = obj
            }
            resultData["success"] = true

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
            let ok: Bool
            if isAlbum && !albumId.isEmpty {
                let explicitStartIdx = (params["start_index"] as? Int)
                    ?? (params["startIndex"] as? Int)
                    ?? (params["start_index"] as? NSNumber)?.intValue
                    ?? (params["startIndex"] as? NSNumber)?.intValue
                let explicitTrackIdx = (params["track_index"] as? Int)
                    ?? (params["trackIndex"] as? Int)
                    ?? (params["index"] as? Int)
                    ?? (params["track_index"] as? NSNumber)?.intValue
                    ?? (params["trackIndex"] as? NSNumber)?.intValue
                let resolvedStartIndex: Int
                if let sIdx = explicitStartIdx {
                    resolvedStartIndex = sIdx
                } else if let tIdx = explicitTrackIdx {
                    resolvedStartIndex = max(0, tIdx - 1)
                } else {
                    resolvedStartIndex = shuffle ? -1 : 0
                }
                ok = await bridge.playAlbum(id: albumId, name: name, artist: artist, startIndex: resolvedStartIndex, shuffle: shuffle)
            } else {
                ok = await bridge.playCloud(url: url, id: storeId, name: name, artist: artist, numericId: numericId, isLocal: isLocal)
            }
            resultData["success"] = ok
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.broadcastStatus(includeQueue: true)
            }

        case "play_station":
            let name = (params["name"] as? String) ?? "Radio"
            let url = (params["url"] as? String) ?? ""
            let type = (params["type"] as? String) ?? ""
            let trackTitle = (params["title"] as? String) ?? (params["track"] as? String) ?? ""
            let artistName = (params["artist"] as? String) ?? ""
            let ok = await bridge.playStation(url: url, name: name, type: type, trackTitle: trackTitle, artistName: artistName)
            resultData["success"] = ok
            resultData["name"] = name
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.broadcastStatus(includeQueue: true)
            }

        case "get_account_status", "account_health":
            let force = (params["refresh"] as? Bool) ?? false
            let rawHealth = await AccountHealthService.shared.checkAccountHealth(forceRefresh: force)
            let health = Self.maskedAccountHealth(rawHealth)
            if let enc = try? JSONEncoder().encode(health),
               let dict = try? JSONSerialization.jsonObject(with: enc) as? [String: Any] {
                resultData["data"] = dict
            }
            resultData["success"] = true

        default:
            resultData = ["status": "error", "message": "Unknown endpoint: \(endpoint)"]
        }

        var respData = Data("{\"status\":\"ok\"}".utf8)
        if JSONSerialization.isValidJSONObject(resultData), let data = try? JSONSerialization.data(withJSONObject: resultData) {
            respData = data
        } else {
            let safeMap: [String: Any] = [
                "status": resultData["status"] as? String ?? "ok",
                "endpoint": resultData["endpoint"] as? String ?? endpoint,
                "success": (resultData["success"] as? Bool) ?? true
            ]
            if let data = try? JSONSerialization.data(withJSONObject: safeMap) {
                respData = data
            }
        }
        sendHTTPResponse(status: "200 OK", contentType: "application/json; charset=utf-8", body: respData, connection: connection)
    }
}
