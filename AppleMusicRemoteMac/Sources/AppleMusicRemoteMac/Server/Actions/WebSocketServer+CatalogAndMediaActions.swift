//
//  WebSocketServer+CatalogAndMediaActions.swift
//  AppleMusicRemoteMac
//
//  Apple Music catalog search, stations, charts, explore feed, album details,
//  MusicKit tokens, artwork, motion artwork, and account health actions.
//

import Foundation
import Network

extension WebSocketServer {
    internal func handleCatalogAndMediaAction(
        action: String,
        actionLower: String,
        id: String?,
        json: [String: Any],
        params: [String: Any],
        clientId: UUID,
        connection: NWConnection
    ) async -> Bool {
        let bridge = MusicBridge.shared
        let cloud = CloudCatalogService.shared

        switch actionLower {
        case "get_stations", "stations":
            let country = MusicKitManager.shared.resolveEffectiveStorefront((params["country"] as? String) ?? (params["storefront"] as? String))
            let stations = cloud.getCuratedStations(country: country)
            sendSuccess(action: action, data: StationsResponse(stations: stations), id: id, to: connection)
            return true

        case "search":
            let query = (params["query"] as? String) ?? (params["q"] as? String) ?? ""
            let country = MusicKitManager.shared.resolveEffectiveStorefront((params["country"] as? String) ?? (params["storefront"] as? String))
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
            if offset == 0, let rawSongs = results["songs"]?.value as? [[String: Any]], !rawSongs.isEmpty {
                let topCatalogIds: [String] = rawSongs.prefix(4).compactMap { dict in
                    let sid = ((dict["id"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let isLoc = (dict["is_local"] as? Bool) ?? false
                    guard !isLoc, let num = Int(sid), num >= 1_000_000 else { return nil }
                    return sid
                }
                if !topCatalogIds.isEmpty {
                    DispatchQueue.global(qos: .utility).async {
                        for cid in topCatalogIds {
                            _ = MusicKitManager.shared.resolveCatalogSongTitleVariantsSync(catalogId: cid)
                        }
                    }
                }
            }
            return true

        case "get_developer_token":
            if let token = MusicKitManager.shared.getDeveloperToken() {
                sendSuccess(action: action, data: ["token": token], id: id, to: connection)
            } else {
                sendError(action: action, error: "Developer token unavailable", id: id, to: connection)
            }
            return true

        case "set_user_token", "user_token":
            guard ClientDeviceManager.shared.canConnectionModifyLibrary(connectionId: clientId) else {
                if let record = ClientDeviceManager.shared.getDeviceForConnection(connectionId: clientId) {
                    sendEvent(name: "device_auth_status", data: record.dictionary, to: connection)
                }
                sendError(action: action, error: "Изменение токена Apple Music отключено для этого устройства в настройках Mac", id: id, to: connection)
                return true
            }
            if let token = (params["token"] as? String) ?? (params["user_token"] as? String),
               !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MusicKitManager.shared.setUserToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
                sendSuccess(action: action, data: [
                    "status": "ok",
                    "has_user_token": true,
                    "storefront": MusicKitManager.shared.getUserStorefront(),
                    "locale": MusicKitManager.shared.getPreferredLanguageTag()
                ], id: id, to: connection)
            } else {
                MusicKitManager.shared.clearUserToken()
                sendSuccess(action: action, data: ["status": "ok", "has_user_token": false], id: id, to: connection)
            }
            return true

        case "get_user_token_status", "user_token_status":
            let hasToken = MusicKitManager.shared.hasUserToken
            sendSuccess(action: action, data: [
                "has_user_token": hasToken,
                "storefront": MusicKitManager.shared.getUserStorefront(),
                "locale": MusicKitManager.shared.getPreferredLanguageTag()
            ], id: id, to: connection)
            return true

        case "get_catalog_charts", "catalog_charts", "charts":
            let country = MusicKitManager.shared.resolveEffectiveStorefront((params["country"] as? String) ?? (params["storefront"] as? String))
            let songs = await MusicKitManager.shared.getTopCharts(storefront: country)
            sendSuccess(action: action, data: ["songs": songs], id: id, to: connection)
            return true

        case "get_explore", "explore":
            let country = MusicKitManager.shared.resolveEffectiveStorefront((params["country"] as? String) ?? (params["storefront"] as? String))
            let feed = await cloud.getExploreFeed(country: country)
            sendSuccess(action: action, data: feed, id: id, to: connection)
            PlaybackRouter.shared.prewarmPersonalMixesHeadTracks()
            return true

        case "get_personal_mixes", "personal_mixes":
            let mixes = await MusicKitManager.shared.fetchPersonalMixes()
            let (personal, discovery) = await MusicKitManager.shared.fetchPersonalStations()
            var stationsList = [StationInfo]()
            if let p = personal { stationsList.append(p) }
            if let d = discovery { stationsList.append(d) }
            sendSuccess(action: action, data: PersonalMixesResponse(mixes: mixes, stations: stationsList), id: id, to: connection)
            return true

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
            return true

        case "get_album", "album":
            await handleGetAlbumAction(action: action, id: id, params: params, connection: connection)
            return true

        case "get_artwork", "artwork":
            let isCur = (params["current"] as? Bool) ?? false
            let tid = params["track_id"] as? Int
            let plName = params["playlist"] as? String
            if isCur {
                if let data = bridge.getCurrentTrackArtwork() {
                    sendSuccess(action: action, data: ["artwork_base64": data.base64EncodedString(), "mime": "image/jpeg"], id: id, to: connection)
                } else {
                    sendError(action: action, error: "No artwork found", id: id, to: connection)
                }
            } else if let tid = tid {
                if let data = bridge.getTrackArtwork(id: tid) {
                    sendSuccess(action: action, data: ["artwork_base64": data.base64EncodedString(), "mime": "image/jpeg"], id: id, to: connection)
                } else {
                    sendError(action: action, error: "No artwork found", id: id, to: connection)
                }
            } else if let plName = plName {
                if let data = bridge.getPlaylistArtwork(name: plName) {
                    sendSuccess(action: action, data: ["artwork_base64": data.base64EncodedString(), "mime": "image/jpeg"], id: id, to: connection)
                } else {
                    sendError(action: action, error: "No artwork found", id: id, to: connection)
                }
            } else {
                sendError(action: action, error: "Missing parameters for artwork", id: id, to: connection)
            }
            return true

        case "get_account_status", "account_health":
            let force = (params["refresh"] as? Bool) ?? false
            let rawHealth = await AccountHealthService.shared.checkAccountHealth(forceRefresh: force)
            let health = Self.maskedAccountHealth(rawHealth)
            sendSuccess(action: action, data: health, id: id, to: connection)
            return true

        case "get_motion_artwork", "motion_artwork":
            let albumId = (params["album_id"] as? String) ?? (params["id"] as? String)
            let trackName = (params["track"] as? String) ?? (params["name"] as? String) ?? ""
            let artist = (params["artist"] as? String) ?? ""
            let albumName = (params["album"] as? String) ?? ""
            let motionUrl = await MusicKitManager.shared.resolveMotionArtworkUrl(
                albumId: albumId,
                trackName: trackName,
                artist: artist,
                albumName: albumName
            )
            sendSuccess(action: action, data: [
                "motion_url": motionUrl ?? "",
                "track": trackName,
                "artist": artist,
                "album": albumName
            ], id: id, to: connection)
            return true

        default:
            return false
        }
    }

    private func handleGetAlbumAction(
        action: String,
        id: String?,
        params: [String: Any],
        connection: NWConnection
    ) async {
        let bridge = MusicBridge.shared
        let cloud = CloudCatalogService.shared
        let albumId = (
            (params["id"] as? String)
            ?? (params["album_id"] as? String)
            ?? (params["id"] as? Int).map(String.init)
            ?? (params["album_id"] as? Int).map(String.init)
            ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (params["name"] as? String) ?? (params["title"] as? String) ?? ""
        let artist = (params["artist"] as? String) ?? ""
        let requestedSource = ((params["source"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let country = MusicKitManager.shared.resolveEffectiveStorefront((params["country"] as? String) ?? (params["storefront"] as? String))

        let isCatalogAlbumId = (Int(albumId) ?? 0) >= 10_000_000
        var catalogAlbum: AlbumInfo? = nil
        var resolvedCatalogAlbumId: String? = isCatalogAlbumId ? albumId : nil

        if isCatalogAlbumId {
            catalogAlbum = await cloud.getAlbumDetails(albumId: albumId, country: country)
            if catalogAlbum == nil && country != "us" {
                catalogAlbum = await cloud.getAlbumDetails(albumId: albumId, country: "us")
            }
            if catalogAlbum == nil && country != "ru" {
                catalogAlbum = await cloud.getAlbumDetails(albumId: albumId, country: "ru")
            }
            if let cid = catalogAlbum?.id, (Int(cid) ?? 0) >= 10_000_000 {
                resolvedCatalogAlbumId = cid
            }
        }

        var targetName = (!name.isEmpty ? name : (catalogAlbum?.name ?? "")).trimmingCharacters(in: .whitespacesAndNewlines)
        var targetArtist = (!artist.isEmpty ? artist : (catalogAlbum?.artist ?? "")).trimmingCharacters(in: .whitespacesAndNewlines)

        var localLibraryTracks: [TrackInfo] = []
        if !PlaybackRouter.shared.isTestingEnvironment && !targetName.isEmpty {
            localLibraryTracks = bridge.getLibraryAlbumTracks(album: targetName, artist: targetArtist)
        }
        if albumId.hasPrefix("l.") && localLibraryTracks.isEmpty {
            localLibraryTracks = await MusicKitManager.shared.getLibraryAlbumTracksById(libraryAlbumId: albumId)
            if targetName.isEmpty {
                targetName = (localLibraryTracks.first?.album ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if targetArtist.isEmpty {
                targetArtist = (localLibraryTracks.first?.artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if catalogAlbum == nil && (!targetName.isEmpty || !targetArtist.isEmpty) {
            var catTracks = await MusicKitManager.shared.getAlbumTracks(album: targetName, artist: targetArtist, storefront: country)
            if catTracks.isEmpty && country != "us" {
                catTracks = await MusicKitManager.shared.getAlbumTracks(album: targetName, artist: targetArtist, storefront: "us")
            }
            if catTracks.isEmpty && country != "ru" {
                catTracks = await MusicKitManager.shared.getAlbumTracks(album: targetName, artist: targetArtist, storefront: "ru")
            }
            if !catTracks.isEmpty {
                if resolvedCatalogAlbumId == nil {
                    for trk in catTracks {
                        if let firstUrl = trk.url {
                            let cleanPath = firstUrl.components(separatedBy: "?").first ?? firstUrl
                            if let lastSeg = cleanPath.split(separator: "/").last,
                               let parsedCatId = Int(lastSeg), parsedCatId >= 10_000_000 {
                                resolvedCatalogAlbumId = String(lastSeg)
                                break
                            }
                        }
                    }
                }
                let resolvedCatTitle = !targetName.isEmpty
                    ? targetName
                    : (catTracks.first?.album.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                let resolvedCatArtist = !targetArtist.isEmpty
                    ? targetArtist
                    : (catTracks.first?.artist.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                catalogAlbum = AlbumInfo(
                    id: resolvedCatalogAlbumId ?? albumId,
                    name: resolvedCatTitle,
                    artist: resolvedCatArtist,
                    artwork: catTracks.first?.artworkUrl ?? "",
                    releaseDate: nil,
                    trackCount: catTracks.count,
                    genre: nil,
                    url: nil,
                    tracks: catTracks
                )
            }
        }

        if !PlaybackRouter.shared.isTestingEnvironment && localLibraryTracks.isEmpty,
           let catAlb = catalogAlbum, !catAlb.name.isEmpty {
            localLibraryTracks = bridge.getLibraryAlbumTracks(album: catAlb.name, artist: catAlb.artist)
        }

        let rawCatTracks = catalogAlbum?.tracks ?? []
        let resolvedCatTracks: [TrackInfo]
        if !rawCatTracks.isEmpty && !PlaybackRouter.shared.isTestingEnvironment {
            resolvedCatTracks = LibraryService.shared.resolveLocalLibraryMatches(
                rawCatTracks,
                updateNames: false,
                includeStagedTemporary: false
            )
        } else {
            resolvedCatTracks = rawCatTracks
        }

        let finalName = !(catalogAlbum?.name ?? "").isEmpty
            ? (catalogAlbum?.name ?? targetName)
            : (!targetName.isEmpty ? targetName : (localLibraryTracks.first?.album ?? ""))
        let finalArtist = !(catalogAlbum?.artist ?? "").isEmpty
            ? (catalogAlbum?.artist ?? targetArtist)
            : (!targetArtist.isEmpty ? targetArtist : (localLibraryTracks.first?.artist ?? ""))

        var baseAlbum: AlbumInfo? = catalogAlbum
        if baseAlbum == nil && !localLibraryTracks.isEmpty {
            baseAlbum = AlbumInfo(
                id: !albumId.isEmpty ? albumId : "local:\(finalArtist):\(finalName)",
                name: finalName,
                artist: finalArtist,
                artwork: localLibraryTracks.first(where: { !$0.artworkUrl.isEmpty })?.artworkUrl ?? "",
                trackCount: localLibraryTracks.count,
                tracks: localLibraryTracks,
                inLibrary: true
            )
        }

        guard var album = baseAlbum else {
            sendError(action: action, error: "Album not found", id: id, to: connection)
            return
        }

        let matchedCatalogCount = resolvedCatTracks.filter { $0.isLocal == true }.count
        let libCount = max(localLibraryTracks.count, matchedCatalogCount)
        let catCount = resolvedCatTracks.count
        let recentlySavedWholeAlbum = MusicKitManager.shared.isExplicitlyAddedAlbumInSession(
            albumId: resolvedCatalogAlbumId ?? albumId,
            name: finalName,
            artist: finalArtist
        )

        let isCompleteInLibrary: Bool
        if catCount > 0 {
            isCompleteInLibrary = (libCount >= catCount)
                || (matchedCatalogCount == catCount)
                || (recentlySavedWholeAlbum && localLibraryTracks.isEmpty)
        } else {
            isCompleteInLibrary = libCount > 0
        }

        let fallbackArtwork = !album.artwork.isEmpty
            ? album.artwork
            : (resolvedCatTracks.first(where: { !$0.artworkUrl.isEmpty })?.artworkUrl
                ?? localLibraryTracks.first(where: { !$0.artworkUrl.isEmpty })?.artworkUrl
                ?? "")
        if album.artwork.isEmpty && !fallbackArtwork.isEmpty {
            album.artwork = fallbackArtwork
        }

        if requestedSource == "library" && !localLibraryTracks.isEmpty && !isCompleteInLibrary {
            var enrichedLocal = localLibraryTracks
            if !resolvedCatTracks.isEmpty || !fallbackArtwork.isEmpty {
                for idx in enrichedLocal.indices where enrichedLocal[idx].artworkUrl.isEmpty {
                    let lowerTitle = enrichedLocal[idx].name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let matchedArt = resolvedCatTracks.first(where: {
                        !$0.artworkUrl.isEmpty && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lowerTitle
                    })?.artworkUrl ?? fallbackArtwork
                    if !matchedArt.isEmpty {
                        enrichedLocal[idx].artworkUrl = matchedArt
                        enrichedLocal[idx].hasArtwork = true
                    }
                }
            }
            album.tracks = enrichedLocal
            album.trackCount = enrichedLocal.count
            album.isLibraryView = true
            album.inLibrary = true
            album.isCompleteInLibrary = false
            album.libraryTrackCount = enrichedLocal.count
            album.catalogTrackCount = catCount
            album.catalogAlbumId = resolvedCatalogAlbumId
        } else {
            let fullTracks = !resolvedCatTracks.isEmpty ? resolvedCatTracks : localLibraryTracks
            album.tracks = fullTracks
            if !fullTracks.isEmpty {
                album.trackCount = fullTracks.count
            }
            album.isLibraryView = false
            album.inLibrary = (libCount > 0 || recentlySavedWholeAlbum)
            album.isCompleteInLibrary = isCompleteInLibrary
            album.libraryTrackCount = isCompleteInLibrary ? max(libCount, catCount) : libCount
            album.catalogTrackCount = max(catCount, libCount)
            album.catalogAlbumId = resolvedCatalogAlbumId
        }

        sendSuccess(action: action, data: ["album": album], id: id, to: connection)
        if !isCompleteInLibrary, let albTracks = album.tracks, !albTracks.isEmpty {
            PlaybackRouter.shared.prestagePreviewHeadTracks(albTracks, count: 2)
        }
    }
}
