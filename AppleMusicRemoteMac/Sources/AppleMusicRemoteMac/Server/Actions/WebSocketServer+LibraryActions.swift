//
//  WebSocketServer+LibraryActions.swift
//  AppleMusicRemoteMac
//
//  Local & merged library browsing, adding playlists/albums/tracks, and
//  capability-gated library deletion actions.
//

import Foundation
import Network

extension WebSocketServer {
    internal func handleLibraryOrCatalogAction(
        action: String,
        actionLower: String,
        id: String?,
        json: [String: Any],
        params: [String: Any],
        clientId: UUID,
        connection: NWConnection
    ) async -> Bool {
        if await handleLibraryAction(action: action, actionLower: actionLower, id: id, params: params, clientId: clientId, connection: connection) {
            return true
        }
        return await handleCatalogAndMediaAction(action: action, actionLower: actionLower, id: id, json: json, params: params, clientId: clientId, connection: connection)
    }

    private func handleLibraryAction(
        action: String,
        actionLower: String,
        id: String?,
        params: [String: Any],
        clientId: UUID,
        connection: NWConnection
    ) async -> Bool {
        let bridge = MusicBridge.shared

        switch actionLower {
        case "get_playlists", "playlists":
            let forceRefresh = (params["refresh"] as? Bool) ?? false
            let fastList = bridge.getPlaylists(forceRefresh: forceRefresh)
            sendSuccess(action: action, data: PlaylistsResponse(playlists: fastList), id: id, to: connection)

            let hasMissing = fastList.contains { ($0.artworkUrl?.isEmpty ?? true) }
            let needsCloudMeta = !PlaybackRouter.shared.isTestingEnvironment
                && MusicKitManager.shared.hasUserToken
                && (forceRefresh || !LibraryService.shared.hasFreshCloudPlaylistMetadata())
            if hasMissing || needsCloudMeta {
                await LibraryService.shared.ensureCloudPlaylistMetadataLoaded(forceRefresh: forceRefresh)
                let enriched = hasMissing ? await bridge.getPlaylistsWithArtworks() : bridge.getPlaylists(forceRefresh: false)
                sendEvent("playlists_result", data: PlaylistsResponse(playlists: enriched), to: connection)
            }
            return true

        case "get_playlist_tracks", "playlist_tracks":
            let name = (params["name"] as? String) ?? (params["playlist"] as? String) ?? ""
            let plId = (params["id"] as? String) ?? (params["playlist_id"] as? String) ?? ""
            let urlStr = (params["url"] as? String) ?? ""
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
                tracks = bridge.getPlaylistTracks(name: name)
            }

            if tracks.isEmpty {
                var mixes = MusicKitManager.shared.getCachedPersonalData()?.mixes ?? []
                if mixes.isEmpty {
                    mixes = await MusicKitManager.shared.fetchPersonalMixes()
                }
                if let m = mixes.first(where: { Self.matchesPersonalMix(queryLower: lowerName, candidateLower: $0.name.lowercased()) }),
                   let mid = m.id, !mid.isEmpty {
                    tracks = await MusicKitManager.shared.getPlaylistTracksById(playlistId: mid)
                }
            }

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

            sendSuccess(action: action, data: PlaylistTracksResponse(playlist: name, tracks: tracks), id: id, to: connection)
            PlaybackRouter.shared.prestagePreviewHeadTracks(tracks, count: 4)

            let hasMissing = tracks.contains { !$0.hasArtwork || $0.artworkUrl.isEmpty }
            if hasMissing {
                let enriched = await bridge.enrichTracksArtwork(tracks)
                bridge.updatePlaylistTracksCache(name: name, tracks: enriched)
                sendEvent("playlist_tracks", data: PlaylistTracksResponse(playlist: name, tracks: enriched), to: connection)
            }
            return true

        case "get_artists", "get_library_artists":
            let forceRefresh = (params["refresh"] as? Bool) ?? false
            let artists = await bridge.getLibraryArtistsMerged(forceRefresh: forceRefresh)
            sendSuccess(action: action, data: ArtistsResponse(artists: artists), id: id, to: connection)
            return true

        case "get_albums", "get_library_albums":
            let forceRefresh = (params["refresh"] as? Bool) ?? false
            let albums = await bridge.getLibraryAlbumsMerged(forceRefresh: forceRefresh)
            sendSuccess(action: action, data: AlbumsResponse(albums: albums), id: id, to: connection)
            return true

        case "get_songs", "get_library_songs":
            let forceRefresh = (params["refresh"] as? Bool) ?? false
            let songs = await bridge.getLibrarySongsMerged(forceRefresh: forceRefresh)
            sendSuccess(action: action, data: SongsResponse(songs: songs), id: id, to: connection)
            return true

        case "get_library_recent", "library_recent":
            let forceRefresh = (params["refresh"] as? Bool) ?? false
            let recent = await bridge.getLibraryRecentMerged(forceRefresh: forceRefresh)
            sendSuccess(action: action, data: recent, id: id, to: connection)
            return true

        case "get_library_artist_detail", "library_artist_detail":
            let artist = (params["artist"] as? String) ?? (params["name"] as? String) ?? ""
            let detail = await bridge.getLibraryArtistDetailMerged(artist: artist)
            sendSuccess(action: action, data: detail, id: id, to: connection)
            return true

        case "add_to_library":
            let rawIdStr = (params["id"] as? String)
                ?? (params["track_id"] as? String)
                ?? (params["catalog_id"] as? String)
            let trackId = (params["track_id"] as? Int)
                ?? (params["id"] as? Int)
                ?? rawIdStr.flatMap { Int($0) }
            let name = params["name"] as? String
            let artist = params["artist"] as? String
            let url = params["url"] as? String
            let ok = await bridge.addToLibraryAsync(id: rawIdStr, trackId: trackId, name: name, artist: artist, url: url)
            sendSuccess(action: action, data: ["status": ok ? "ok" : "error"], id: id, to: connection)
            return true

        case "remove_from_library", "delete_from_library", "remove_track_from_library", "remove_album_from_library", "remove_artist_from_library", "remove_playlist_from_library", "delete_playlist_from_library":
            guard ClientDeviceManager.shared.canConnectionModifyLibrary(connectionId: clientId) else {
                if let record = ClientDeviceManager.shared.getDeviceForConnection(connectionId: clientId) {
                    sendEvent(name: "device_auth_status", data: record.dictionary, to: connection)
                }
                sendError(action: action, error: "Изменение и удаление медиатеки отключено для этого устройства в настройках Mac", id: id, to: connection)
                return true
            }
            let targetType: String
            if actionLower == "remove_album_from_library" {
                targetType = "album"
            } else if actionLower == "remove_artist_from_library" {
                targetType = "artist"
            } else if actionLower == "remove_playlist_from_library" || actionLower == "delete_playlist_from_library" {
                targetType = "playlist"
            } else if actionLower == "remove_track_from_library" {
                targetType = "track"
            } else {
                targetType = ((params["type"] as? String) ?? "track")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }
            let pIdStr = params["id"] as? String
            let pTrackIdStr = params["track_id"] as? String
            let pAlbumIdStr = params["album_id"] as? String
            let pPlaylistIdStr = params["playlist_id"] as? String
            let rawIdStr: String? = pIdStr ?? pTrackIdStr ?? pAlbumIdStr ?? pPlaylistIdStr
            let pIdInt = params["id"] as? Int
            let pTrackIdInt = params["track_id"] as? Int
            let pAlbumIdInt = params["album_id"] as? Int
            let rawIdInt: Int? = pIdInt ?? pTrackIdInt ?? pAlbumIdInt
            let rawId: String? = rawIdStr ?? rawIdInt.map { String($0) }
            let trackId: Int? = pTrackIdInt ?? pIdInt ?? (rawId.flatMap { Int($0) })
            let name: String = (params["name"] as? String) ?? (params["title"] as? String) ?? (params["playlist"] as? String) ?? ""
            let artist = (params["artist"] as? String) ?? ""
            let album = (params["album"] as? String) ?? ""

            if targetType == "playlist" {
                if LibraryService.isProtectedSystemPlaylist(name) {
                    sendSuccess(
                        action: action,
                        data: [
                            "status": "error",
                            "type": "playlist",
                            "message": "Системный плейлист нельзя удалить"
                        ],
                        id: id,
                        to: connection
                    )
                    return true
                }
                let matchedLocal = LibraryService.shared.findMatchingLocalPlaylist(id: rawId, name: name)
                let ok = await bridge.removePlaylistFromLibrary(playlistId: rawId, name: name)
                let resolvedCatalogId = matchedLocal?.catalogId ?? ((rawId?.lowercased().hasPrefix("pl.") == true) ? rawId! : "")
                let payload: [String: Any] = [
                    "status": ok ? "ok" : "error",
                    "type": "playlist",
                    "playlist_deleted": ok,
                    "deleted_count": ok ? 1 : 0,
                    "id": rawId ?? (matchedLocal?.id ?? ""),
                    "catalog_id": resolvedCatalogId,
                    "name": name,
                    "local_name": matchedLocal?.name ?? ""
                ]
                sendSuccess(action: action, data: payload, id: id, to: connection)
                if ok {
                    broadcastEvent(name: "library_changed", data: payload)
                    broadcastEvent(name: "tv_library_config", data: TVLibraryConfigurationStore.shared.toDictionary())
                    let freshPlaylists = bridge.getPlaylists(forceRefresh: true)
                    broadcastEvent("playlists_result", data: PlaylistsResponse(playlists: freshPlaylists))
                    broadcastStatus(includeQueue: true)
                    DispatchQueue.main.async {
                        SettingsWindow.refreshIfVisible()
                    }
                }
                return true
            }

            let deletedCount: Int
            switch targetType {
            case "album":
                deletedCount = bridge.removeAlbumFromLibrary(albumId: rawId, name: name, artist: artist)
            case "artist":
                deletedCount = bridge.removeArtistFromLibrary(artist: !artist.isEmpty ? artist : name)
            default:
                deletedCount = bridge.removeTrackFromLibrary(
                    id: rawId,
                    trackId: trackId,
                    name: name,
                    artist: artist,
                    album: album
                )
            }
            let payload: [String: Any] = [
                "status": deletedCount > 0 ? "ok" : "error",
                "type": targetType,
                "deleted_count": deletedCount,
                "id": rawId ?? "",
                "name": name,
                "artist": artist,
                "album": album
            ]
            sendSuccess(action: action, data: payload, id: id, to: connection)
            if deletedCount > 0 {
                broadcastEvent(name: "library_changed", data: payload)
                broadcastStatus(includeQueue: true)
            }
            return true

        case "add_playlist_to_library", "add_album_to_library", "save_queue_to_playlist":
            let isSaveQueue = (actionLower == "save_queue_to_playlist")
            let isSingleTrack = (params["is_single_track"] as? Bool) ?? false
            let itemId = isSaveQueue
                ? "custom_queue"
                : ((params["id"] as? String) ?? (params["playlist_id"] as? String) ?? (params["album_id"] as? String) ?? "")
            let rawName = (params["name"] as? String) ?? (params["title"] as? String) ?? ""
            let itemArtist = (params["artist"] as? String) ?? ""
            let itemArtwork = ((params["artwork"] as? String) ?? (params["artwork_url"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let explicitTrackCount = (params["track_count"] as? Int) ?? 0
            let isAlbum = !isSaveQueue && !isSingleTrack && ((actionLower == "add_album_to_library") || ((params["is_album"] as? Bool) ?? false))
            let rawTracks = (params["tracks"] as? [[String: Any]]) ?? []
            let passedTrackInfos = rawTracks.map { parseTrackInfo($0) }

            if isSingleTrack, let single = passedTrackInfos.first {
                let ok = await bridge.addToLibraryAsync(
                    id: single.catalogId ?? single.id,
                    trackId: single.numericId,
                    name: !single.name.isEmpty ? single.name : rawName,
                    artist: !single.artist.isEmpty ? single.artist : itemArtist,
                    url: single.url
                )
                sendSuccess(action: "add_to_library", data: ["status": ok ? "ok" : "error"], id: id, to: connection)
                return true
            }

            var trackInfos = passedTrackInfos
            var itemName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)

            if isSaveQueue || itemId == "custom_queue" || itemId == "ai_queue" {
                let (customQueue, customName, searchQuery, curatorPrompt) = PlaybackStateStore.shared.withLock {
                    (
                        PlaybackStateStore.shared.activeCustomQueue,
                        PlaybackStateStore.shared.activeCustomQueueName,
                        PlaybackStateStore.shared.activeSearchQuery,
                        PlaybackStateStore.shared.activeCuratorPrompt
                    )
                }
                if !customQueue.isEmpty && trackInfos.count < customQueue.count {
                    trackInfos = customQueue
                } else if trackInfos.isEmpty {
                    let qInfo = await MusicBridge.shared.getPlaybackQueue()
                    trackInfos = qInfo.upcomingTracks
                }
                itemName = PlaybackRouter.resolveSavedQueuePlaylistName(
                    explicitName: itemName,
                    activeQueueName: customName,
                    activeSearchQuery: searchQuery,
                    activeCuratorPrompt: curatorPrompt
                )
            }

            let ok: Bool
            if isAlbum {
                ok = await MusicBridge.shared.addAlbumToLibrary(albumId: itemId, name: itemName, artist: itemArtist, tracks: trackInfos)
            } else {
                ok = await MusicBridge.shared.addPlaylistToLibrary(playlistId: itemId, name: itemName, tracks: trackInfos)
            }
            let effectiveCount = max(explicitTrackCount, trackInfos.count)
            if ok && !isAlbum && !itemName.isEmpty {
                LibraryService.shared.recordRecentlyAddedPlaylist(
                    id: itemId,
                    name: itemName,
                    trackCount: effectiveCount,
                    artworkUrl: itemArtwork
                )
            }
            sendSuccess(
                action: action,
                data: [
                    "status": ok ? "ok" : "error",
                    "playlist": itemName,
                    "name": itemName,
                    "id": itemId,
                    "is_album": isAlbum,
                    "track_count": effectiveCount,
                    "artwork_url": itemArtwork
                ],
                id: id,
                to: connection
            )
            if ok {
                Task.detached(priority: .utility) { [weak self] in
                    guard let self = self else { return }
                    if isAlbum {
                        let immediateAlbums = await MusicBridge.shared.getLibraryAlbumsMerged(forceRefresh: false)
                        self.broadcastEvent("albums_result", data: AlbumsResponse(albums: immediateAlbums))
                        try? await Task.sleep(nanoseconds: 3_200_000_000)
                        let syncedAlbums = await MusicBridge.shared.getLibraryAlbumsMerged(forceRefresh: true)
                        self.broadcastEvent("albums_result", data: AlbumsResponse(albums: syncedAlbums))
                    } else {
                        let immediatePlaylists = MusicBridge.shared.getPlaylists(forceRefresh: false)
                        self.broadcastEvent("playlists_result", data: PlaylistsResponse(playlists: immediatePlaylists))
                        for delayNs: UInt64 in [2_000_000_000, 4_000_000_000, 7_000_000_000] {
                            try? await Task.sleep(nanoseconds: delayNs)
                            let syncedPlaylists = await LibraryService.shared.refreshPlaylistsWithCloudMetadata(forceRefresh: true)
                            self.broadcastEvent("playlists_result", data: PlaylistsResponse(playlists: syncedPlaylists))
                        }
                    }
                }
            }
            return true

        default:
            return false
        }
    }
}
