//
//  WebSocketServer+PlaybackActions.swift
//  AppleMusicRemoteMac
//
//  Playback initiation actions (stations, hero cards, playlists, history, albums,
//  cloud items, search results, and queue appending), awaited in FIFO order per client.
//

import Foundation
import Network

extension WebSocketServer {
    internal func handlePlaybackInitiationAction(
        action: String,
        actionLower: String,
        id: String?,
        params: [String: Any],
        clientId: UUID,
        connection: NWConnection
    ) async -> Bool {
        let bridge = MusicBridge.shared

        switch actionLower {
        case "play_station":
            let url = (params["url"] as? String) ?? ""
            let name = (params["name"] as? String) ?? "Apple Music Radio"
            let type = (params["type"] as? String) ?? ""
            let trackTitle = (params["title"] as? String) ?? (params["track"] as? String) ?? ""
            let artistName = (params["artist"] as? String) ?? ""
            let ok = await bridge.playStation(url: url, name: name, type: type, trackTitle: trackTitle, artistName: artistName)
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "station": name], id: id, to: connection)
            return true

        case "play_hero_card":
            let index = (params["index"] as? Int) ?? 0
            let name = (params["name"] as? String) ?? ""
            let artist = (params["artist"] as? String) ?? (params["subtitle"] as? String) ?? (params["sub"] as? String) ?? ""
            let cardId = params["id"] as? String
            let url = params["url"] as? String
            let type = params["type"] as? String
            let ok = await bridge.playHeroCard(index: index, name: name, artist: artist, cardId: cardId, url: url, type: type)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "name": name], id: id, to: connection)
            broadcastStatus(includeQueue: true)
            if ok {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.broadcastStatus(includeQueue: true)
                }
            }
            return true

        case "play_playlist":
            await handlePlayPlaylistAction(action: action, id: id, params: params, connection: connection)
            return true

        case "play_history_index", "history_play_index":
            let idx = (params["index"] as? Int) ?? 0
            let ok = await bridge.playHistoryIndex(idx)
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            return true

        case "play_history_track", "history_play_track":
            let name = (params["name"] as? String) ?? ""
            let artist = (params["artist"] as? String) ?? ""
            let ok = await bridge.playHistoryTrack(name: name, artist: artist)
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            return true

        case "play_album", "play_album_tracks":
            let albumId = (params["id"] as? String) ?? (params["album_id"] as? String) ?? ""
            let name = (params["name"] as? String) ?? (params["title"] as? String) ?? ""
            let artist = (params["artist"] as? String) ?? ""
            let shuffle = (params["shuffle"] as? Bool) ?? false
            let explicitTrackIndex = (params["track_index"] as? Int) ?? (params["index"] as? Int)
            let startIndex: Int = (shuffle && explicitTrackIndex == nil) ? -1 : max(0, (explicitTrackIndex ?? 1) - 1)

            let customTracks = parseExplicitTracksList(from: params, fallbackArtist: artist, fallbackAlbum: name)
            let ok: Bool
            if !customTracks.isEmpty {
                ok = await bridge.playAlbumWithTracks(tracks: customTracks, name: name, artist: artist, startIndex: startIndex, shuffle: shuffle)
            } else {
                ok = await bridge.playAlbum(id: albumId, name: name, artist: artist, startIndex: startIndex, shuffle: shuffle)
            }
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "album": name], id: id, to: connection)
            return true

        case "play_recent", "play_recently_played":
            let shuffle = (params["shuffle"] as? Bool) ?? false
            let ok = await bridge.playRecentTracks(shuffle: shuffle)
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            return true

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

            let ok: Bool
            if isAlbum && !albumId.isEmpty {
                ok = await bridge.playAlbum(id: albumId, name: name, artist: artist, startIndex: resolvedStartIndex, shuffle: shuffle)
            } else {
                ok = await bridge.playCloud(url: url, id: storeId, name: name, artist: artist, numericId: numericId, isLocal: isLocal)
            }
            broadcastStatus(includeQueue: true)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            return true

        case "play_search_results":
            let shuffle = (params["shuffle"] as? Bool) ?? false
            let targetTracks = parseExplicitTracksList(from: params, fallbackArtist: "", fallbackAlbum: "")
            let pinStart = (params["pin_start_track"] as? Bool) ?? false
            let rawStartIdx = (params["startIndex"] as? Int) ?? (params["start_index"] as? Int) ?? (params["track_index"] as? Int).map { max(0, $0 - 1) }
            let startIndex: Int
            if shuffle {
                if let idx = rawStartIdx, idx >= 0, (pinStart || idx > 0) {
                    startIndex = idx
                } else {
                    startIndex = -1
                }
            } else {
                startIndex = max(0, rawStartIdx ?? 0)
            }
            let queueName = (params["queue_name"] as? String) ?? (params["queueName"] as? String)
            let searchQuery = (params["query"] as? String) ?? (params["q"] as? String)
            let curatorPrompt = (params["curator_prompt"] as? String) ?? (params["curatorPrompt"] as? String) ?? (params["ai_prompt"] as? String)

            let t0 = Date()
            NSLog("[AICurator] play_search_results started (tracks=%d, startIndex=%d, queueName='%@', hasCuratorPrompt=%d)", targetTracks.count, startIndex, queueName ?? "", curatorPrompt != nil ? 1 : 0)
            let ok = await bridge.playSearchResults(tracks: targetTracks, startIndex: startIndex, shuffle: shuffle, queueName: queueName, query: searchQuery, curatorPrompt: curatorPrompt)
            let elapsedMs = Int(Date().timeIntervalSince(t0) * 1000)
            NSLog("[AICurator] play_search_results finished in %dms (ok=%d, tracks=%d)", elapsedMs, ok ? 1 : 0, targetTracks.count)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "count": targetTracks.count], id: id, to: connection)
            broadcastStatus(includeQueue: true)
            return true

        case "append_search_results", "append_queue":
            let targetTracks = parseExplicitTracksList(from: params, fallbackArtist: "", fallbackAlbum: "")
            let ok = await bridge.appendTracksToAMRQueue(tracks: targetTracks)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "appended": targetTracks.count], id: id, to: connection)
            broadcastStatus(includeQueue: true)
            return true

        default:
            return false
        }
    }

    // MARK: - Playlist Playback Helper

    private func parseExplicitTracksList(from params: [String: Any], fallbackArtist: String, fallbackAlbum: String) -> [TrackInfo] {
        guard let rawTracks = params["tracks"] as? [[String: Any]], !rawTracks.isEmpty else {
            return []
        }
        var list = [TrackInfo]()
        list.reserveCapacity(rawTracks.count)
        for (idx, item) in rawTracks.enumerated() {
            let tid = (item["id"] as? String) ?? "\(idx + 1)"
            let numId = (item["numeric_id"] as? Int) ?? (item["numericId"] as? Int)
            let tName = (item["name"] as? String) ?? ""
            let tArtist = (item["artist"] as? String) ?? fallbackArtist
            let tAlbum = (item["album"] as? String) ?? fallbackAlbum
            let tUrl = item["url"] as? String
            let tArt = (item["artwork_url"] as? String) ?? (item["artwork"] as? String) ?? ""
            let isLoc = (item["is_local"] as? Bool) ?? (item["isLocal"] as? Bool) ?? false
            let dur = (item["duration"] as? Double) ?? 0.0
            let catId = (item["catalog_id"] as? String) ?? (item["catalogId"] as? String) ?? (AppleSoundCheckService.isValidCatalogId(tid) ? tid : nil)
            list.append(TrackInfo(
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
        return list
    }

    private func resolvePlaylistStartIndex(
        tracks: [TrackInfo],
        trackIdStr: String,
        trackId: Int?,
        trackIndex: Int?,
        shuffle: Bool
    ) -> Int {
        if !trackIdStr.isEmpty, let found = tracks.firstIndex(where: { $0.id == trackIdStr || "\($0.numericId ?? -1)" == trackIdStr }) {
            return found
        }
        if let tid = trackId, let found = tracks.firstIndex(where: { ($0.numericId ?? Int($0.id)) == tid }) {
            return found
        }
        if let tIdx = trackIndex, tIdx > 0 {
            return min(tracks.count - 1, tIdx - 1)
        }
        if shuffle && !tracks.isEmpty {
            return -1
        }
        return 0
    }

    private func scheduleDelayedQueueBroadcast(after seconds: TimeInterval = 0.25) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.broadcastStatus(includeQueue: true)
        }
    }

    private func handlePlayPlaylistAction(
        action: String,
        id: String?,
        params: [String: Any],
        connection: NWConnection
    ) async {
        let bridge = MusicBridge.shared
        let plName = (params["playlist"] as? String) ?? (params["name"] as? String) ?? "Музыка"
        let plId = (params["id"] as? String) ?? (params["playlist_id"] as? String) ?? ""
        let urlStr = (params["url"] as? String) ?? ""
        let trackId = (params["track_id"] as? Int) ?? Int((params["track_id"] as? String) ?? "")
        let trackIdStr = (params["track_id"] as? String) ?? (params["track_id"] as? Int).map(String.init) ?? ""
        let trackIndex = (params["track_index"] as? Int) ?? Int((params["track_index"] as? String) ?? "")
        let shuffle = (params["shuffle"] as? Bool) ?? false
        let isExplicitLocal = (params["is_local"] as? Bool) ?? (params["isLocal"] as? Bool) ?? false

        var targetTracks = parseExplicitTracksList(from: params, fallbackArtist: "", fallbackAlbum: "")

        if !targetTracks.isEmpty && !isExplicitLocal {
            let trimmedPl = plName.trimmingCharacters(in: .whitespacesAndNewlines)
            let localPlaylistsForVerify = LibraryService.shared.getPlaylists()
            if let exactLocal = localPlaylistsForVerify.first(where: { $0.name.localizedCaseInsensitiveCompare(trimmedPl) == .orderedSame }),
               exactLocal.trackCount == targetTracks.count {
                let localSample = LibraryService.shared.getPlaylistTracks(name: exactLocal.name)
                let firstLocalTitle = localSample.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let firstTargetTitle = targetTracks.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if localSample.count == targetTracks.count,
                   !firstLocalTitle.isEmpty,
                   firstLocalTitle.localizedCaseInsensitiveCompare(firstTargetTitle) == .orderedSame {
                    let resolvedTrackIdx: Int?
                    if let tIdx = trackIndex, tIdx > 0 {
                        resolvedTrackIdx = tIdx
                    } else if !trackIdStr.isEmpty, let found = targetTracks.firstIndex(where: { $0.id == trackIdStr || "\($0.numericId ?? -1)" == trackIdStr }) {
                        resolvedTrackIdx = found + 1
                    } else {
                        resolvedTrackIdx = shuffle ? nil : 1
                    }
                    let localOk = bridge.playPlaylist(name: exactLocal.name, trackId: nil, trackIndex: resolvedTrackIdx, shuffle: shuffle)
                    if localOk {
                        sendSuccess(action: action, data: ["status": "ok", "playlist": exactLocal.name], id: id, to: connection)
                        scheduleDelayedQueueBroadcast()
                        return
                    }
                }
            }

            let startIdx = resolvePlaylistStartIndex(tracks: targetTracks, trackIdStr: trackIdStr, trackId: trackId, trackIndex: trackIndex, shuffle: shuffle)
            let ok: Bool
            if MusicKitManager.shared.hasUserToken {
                ok = await bridge.playSearchResults(tracks: targetTracks, startIndex: startIdx, shuffle: shuffle, queueName: plName)
            } else {
                ok = bridge.playCustomTracks(targetTracks, startIndex: startIdx, shuffle: shuffle, queueName: plName)
            }
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "playlist": plName], id: id, to: connection)
            scheduleDelayedQueueBroadcast()
            return
        }

        let localPlaylists = LibraryService.shared.getPlaylists()
        let lowerPl = plName.lowercased()
        let isEssentials = lowerPl.contains("essentials")
        let isChill = lowerPl.contains("chill") || lowerPl.contains("чилл") || lowerPl.contains("для отдыха")
        let isNewMusic = lowerPl.contains("new music") || lowerPl.contains("новинк")
        let isFavorites = lowerPl.contains("favorites") || lowerPl.contains("фаворит") || lowerPl.contains("избранн") || lowerPl.contains("в моём вкусе") || lowerPl.contains("в моем вкусе")
        let isGetUp = lowerPl.contains("get up") || lowerPl.contains("на старт") || lowerPl.contains("энерги")

        func isPlaylistMatch(_ candidate: String) -> Bool {
            let n = candidate.lowercased()
            if n == lowerPl || LibraryService.playlistsSharePersonalMixAlias(n, lowerPl) { return true }
            if isEssentials && (n == "мои любимые треки" || n.contains("любимые треки")) { return true }
            if isChill && (n.contains("chill") || n.contains("чилл") || n.contains("для отдыха")) { return true }
            if isNewMusic && (n.contains("new music") || n.contains("новинк")) { return true }
            if isFavorites {
                if lowerPl == "любимые песни" && n == "любимые песни" { return true }
                if n == "мои любимые треки" || n.contains("favorites") || n.contains("фаворит") { return true }
            }
            if isGetUp && (n.contains("get up") || n.contains("на старт") || n.contains("энерги")) { return true }
            return false
        }

        let crossLocaleLocalMatch = LibraryService.shared.findMatchingLocalPlaylist(id: plId, name: plName)
        let hasExactLocalMatch = crossLocaleLocalMatch != nil || localPlaylists.contains(where: { $0.name.lowercased() == lowerPl })
        let isCloudMixId = plId.hasPrefix("pl.") || plId.hasPrefix("p.") || plName.hasPrefix("pl.") || plName.hasPrefix("p.")
        if isExplicitLocal || (targetTracks.isEmpty && !isCloudMixId && (hasExactLocalMatch || localPlaylists.contains(where: { isPlaylistMatch($0.name) }))) {
            let matchName = localPlaylists.first(where: { $0.name.lowercased() == lowerPl })?.name
                ?? crossLocaleLocalMatch?.name
                ?? localPlaylists.first(where: { isPlaylistMatch($0.name) })?.name
                ?? plName
            let localOk = bridge.playPlaylist(name: matchName, trackId: trackId, trackIndex: trackIndex, shuffle: shuffle)
            if localOk {
                sendSuccess(action: action, data: ["status": "ok", "playlist": matchName], id: id, to: connection)
                scheduleDelayedQueueBroadcast()
                return
            }
            if targetTracks.isEmpty {
                targetTracks = bridge.getPlaylistTracks(name: matchName)
            }
            if !targetTracks.isEmpty {
                let startIdx = resolvePlaylistStartIndex(tracks: targetTracks, trackIdStr: trackIdStr, trackId: trackId, trackIndex: trackIndex, shuffle: shuffle)
                let fallbackOk: Bool
                if MusicKitManager.shared.hasUserToken {
                    fallbackOk = await bridge.playSearchResults(tracks: targetTracks, startIndex: startIdx, shuffle: shuffle, queueName: matchName)
                } else {
                    fallbackOk = bridge.playCustomTracks(targetTracks, startIndex: startIdx, shuffle: shuffle, queueName: matchName)
                }
                sendSuccess(action: action, data: ["status": fallbackOk ? "ok" : "error", "playlist": matchName], id: id, to: connection)
                scheduleDelayedQueueBroadcast()
                return
            }
            if isExplicitLocal {
                sendSuccess(action: action, data: ["status": "error", "playlist": matchName], id: id, to: connection)
                return
            }
        }

        if !targetTracks.isEmpty {
            let startIdx = resolvePlaylistStartIndex(tracks: targetTracks, trackIdStr: trackIdStr, trackId: trackId, trackIndex: trackIndex, shuffle: shuffle)
            let ok: Bool
            if MusicKitManager.shared.hasUserToken {
                ok = await bridge.playSearchResults(tracks: targetTracks, startIndex: startIdx, shuffle: shuffle, queueName: plName)
            } else {
                ok = bridge.playCustomTracks(targetTracks, startIndex: startIdx, shuffle: shuffle, queueName: plName)
            }
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "playlist": plName], id: id, to: connection)
            scheduleDelayedQueueBroadcast()
            return
        }

        if !isCloudMixId, let matched = localPlaylists.first(where: { $0.name.lowercased() == lowerPl }) {
            let localOk = bridge.playPlaylist(name: matched.name, trackId: trackId, trackIndex: trackIndex, shuffle: shuffle)
            if localOk {
                sendSuccess(action: action, data: ["status": "ok", "playlist": matched.name], id: id, to: connection)
                scheduleDelayedQueueBroadcast(after: 0.2)
                return
            }
        }

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
            var mixes = MusicKitManager.shared.getCachedPersonalData()?.mixes ?? []
            if mixes.isEmpty {
                mixes = await MusicKitManager.shared.fetchPersonalMixes()
            }
            if let m = mixes.first(where: { Self.matchesPersonalMix(queryLower: lowerPl, candidateLower: $0.name.lowercased()) }),
               let mid = m.id, !mid.isEmpty {
                resolvedId = mid
            }
        }

        let isReplay = (resolvedId == "replay_playlist" || resolvedId.contains("replay") || lowerPl.contains("replay") || lowerPl.contains("итоги"))
        if isReplay {
            targetTracks = await MusicKitManager.shared.getPersonalizedReplayTracks()
        } else if !resolvedId.isEmpty && (resolvedId.hasPrefix("pl.") || resolvedId.hasPrefix("p.")) {
            targetTracks = await MusicKitManager.shared.getPlaylistTracksById(playlistId: resolvedId)
        }

        if targetTracks.isEmpty {
            let mixes = await MusicKitManager.shared.fetchPersonalMixes()
            if let m = mixes.first(where: { Self.matchesPersonalMix(queryLower: lowerPl, candidateLower: $0.name.lowercased()) }),
               let mid = m.id, !mid.isEmpty {
                targetTracks = await MusicKitManager.shared.getPlaylistTracksById(playlistId: mid)
            }
        }

        if targetTracks.isEmpty && (lowerPl.contains("повторе") || lowerPl.contains("heavy rotation")) {
            targetTracks = bridge.getRecentlyPlayed(limit: 50)
            if targetTracks.isEmpty {
                targetTracks = Array(bridge.getLibrarySongs().prefix(50))
            }
        }
        if targetTracks.isEmpty && (lowerPl.contains("в моём вкусе") || lowerPl.contains("в моем вкусе") || lowerPl.contains("essentials")) {
            targetTracks = bridge.getPlaylistTracks(name: "Любимые песни")
            if targetTracks.isEmpty {
                targetTracks = bridge.getPlaylistTracks(name: "Favorites")
            }
            if targetTracks.isEmpty {
                targetTracks = Array(bridge.getLibrarySongs().prefix(50))
            }
        }

        let ok: Bool
        if !targetTracks.isEmpty {
            let startIdx = resolvePlaylistStartIndex(tracks: targetTracks, trackIdStr: trackIdStr, trackId: trackId, trackIndex: trackIndex, shuffle: shuffle)
            if MusicKitManager.shared.hasUserToken {
                ok = await bridge.playSearchResults(tracks: targetTracks, startIndex: startIdx, shuffle: shuffle, queueName: plName)
            } else {
                ok = bridge.playCustomTracks(targetTracks, startIndex: startIdx, shuffle: shuffle, queueName: plName)
            }
        } else {
            ok = bridge.playPlaylist(name: plName, trackId: trackId, trackIndex: trackIndex, shuffle: shuffle)
        }

        sendSuccess(action: action, data: ["status": ok ? "ok" : "error", "playlist": plName], id: id, to: connection)
        scheduleDelayedQueueBroadcast(after: 0.3)
    }

    internal static func matchesPersonalMix(queryLower: String, candidateLower: String) -> Bool {
        if candidateLower == queryLower || LibraryService.playlistsSharePersonalMixAlias(queryLower, candidateLower) { return true }
        if (queryLower.contains("повторе") || queryLower.contains("heavy rotation")) && (candidateLower.contains("повторе") || candidateLower.contains("heavy rotation")) { return true }
        if (queryLower.contains("в моём вкусе") || queryLower.contains("в моем вкусе") || queryLower.contains("essentials") || queryLower.contains("favorites") || queryLower.contains("фаворит")) && (candidateLower.contains("в моём вкусе") || candidateLower.contains("в моем вкусе") || candidateLower.contains("favorites") || candidateLower.contains("фаворит") || candidateLower.contains("избранн")) { return true }
        if (queryLower.contains("chill") || queryLower.contains("чилл") || queryLower.contains("для отдыха")) && (candidateLower.contains("chill") || candidateLower.contains("чилл") || candidateLower.contains("для отдыха")) { return true }
        if (queryLower.contains("new music") || queryLower.contains("новинк")) && (candidateLower.contains("new music") || candidateLower.contains("новинк")) { return true }
        if (queryLower.contains("get up") || queryLower.contains("на старт") || queryLower.contains("энерги")) && (candidateLower.contains("get up") || candidateLower.contains("на старт") || candidateLower.contains("энерги")) { return true }
        if (queryLower.contains("friends mix") || queryLower.contains("микс друзей")) && (candidateLower.contains("friends mix") || candidateLower.contains("микс друзей")) { return true }
        return false
    }
}
