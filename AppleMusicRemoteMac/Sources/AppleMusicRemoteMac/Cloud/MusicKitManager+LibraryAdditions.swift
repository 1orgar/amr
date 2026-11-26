//
//  MusicKitManager+LibraryAdditions.swift
//  AppleMusicRemoteMac
//
//  Adding playlists and albums to the user's Apple Music Cloud / local library.
//

import Foundation

extension MusicKitManager {

    internal func extractCatalogIdsFromTracks(_ tracks: [TrackInfo]) -> [String] {
        var ids: [String] = []
        var seen = Set<String>()
        for t in tracks {
            var candidate = (t.catalogId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.isEmpty {
                let rawId = t.id.trimmingCharacters(in: .whitespacesAndNewlines)
                if let num = Int(rawId), num > 10_000_000 {
                    candidate = rawId
                }
            }
            if candidate.isEmpty, let u = t.url, !u.isEmpty {
                if let comps = URLComponents(string: u),
                   let iVal = comps.queryItems?.first(where: { $0.name == "i" })?.value,
                   let num = Int(iVal), num > 10_000_000 {
                    candidate = iVal
                } else {
                    let cleanPath = u.components(separatedBy: "?").first ?? u
                    if let lastSeg = cleanPath.split(separator: "/").last,
                       let num = Int(lastSeg), num > 10_000_000 {
                        candidate = String(lastSeg)
                    }
                }
            }
            if Self.isValidResourceIdentifier(candidate) && !seen.contains(candidate) {
                seen.insert(candidate)
                ids.append(candidate)
            }
        }
        return ids
    }

    public func addPlaylistToLibrary(playlistId: String, name: String = "", tracks: [TrackInfo] = []) async -> Bool {
        var targetId = playlistId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let devToken = getDeveloperToken()
        let uToken = getUserToken()

        let isExplicitCustomPlaylist = targetId == "replay_playlist" || targetId == "custom_queue" || targetId == "ai_queue" || (targetId.isEmpty && !tracks.isEmpty)

        // 1. If targetId is empty or not a standard pl./p. ID, try resolving via catalog search by name
        if (targetId.isEmpty || (!targetId.hasPrefix("pl.") && !targetId.hasPrefix("p."))) && !cleanName.isEmpty && !isExplicitCustomPlaylist,
           let token = devToken {
            let sf = Self.sanitizedStorefront(getUserStorefront())
            let lang = getPreferredLanguageTag()
            if let searchUrl = Self.makeAppleMusicAPIURL(
                path: "/v1/catalog/\(sf)/search",
                queryItems: [
                    URLQueryItem(name: "term", value: cleanName),
                    URLQueryItem(name: "types", value: "playlists"),
                    URLQueryItem(name: "limit", value: "5"),
                    URLQueryItem(name: "l", value: lang)
                ]
            ) {
                var sReq = URLRequest(url: searchUrl)
                sReq.timeoutInterval = 4.0
                sReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                sReq.setValue("application/json", forHTTPHeaderField: "Accept")
                if let (sData, sResp) = try? await session.data(for: sReq),
                   let sHttp = sResp as? HTTPURLResponse, sHttp.statusCode == 200,
                   let sJson = try? JSONSerialization.jsonObject(with: sData) as? [String: Any],
                   let results = sJson["results"] as? [String: Any],
                   let plsObj = results["playlists"] as? [String: Any],
                   let plsData = plsObj["data"] as? [[String: Any]] {
                    for item in plsData {
                        if let pid = item["id"] as? String,
                           Self.isValidResourceIdentifier(pid),
                           let attrs = item["attributes"] as? [String: Any],
                           let pName = attrs["name"] as? String,
                           pName.localizedCaseInsensitiveCompare(cleanName) == .orderedSame || pName.localizedCaseInsensitiveContains(cleanName) {
                            targetId = pid
                            break
                        }
                    }
                    if targetId.isEmpty,
                       let firstId = plsData.first?["id"] as? String,
                       Self.isValidResourceIdentifier(firstId) {
                        targetId = firstId
                    }
                }
            }
        }

        // 2. Try standard Apple Music API POST /v1/me/library?ids[playlists]=...
        if let token = devToken, let u = uToken, !u.isEmpty,
           (targetId.hasPrefix("pl.") || targetId.hasPrefix("p.")),
           Self.isValidResourceIdentifier(targetId),
           let url = Self.makeAppleMusicAPIURL(
               path: "/v1/me/library",
               queryItems: [URLQueryItem(name: "ids[playlists]", value: targetId)]
           ) {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue(u, forHTTPHeaderField: "Music-User-Token")
            if let (_, resp) = try? await session.data(for: req),
               let http = resp as? HTTPURLResponse,
               (http.statusCode == 200 || http.statusCode == 201 || http.statusCode == 202 || http.statusCode == 204) {
                NSLog("[MusicKitManager] ✅ Successfully added catalog playlist '%@' to user library", targetId)
                invalidateCloudLibraryPlaylistsCache()
                triggerCloudLibrarySyncInMusicApp()
                LibraryService.shared.invalidatePlaylistsCache()
                return true
            } else {
                NSLog("[MusicKitManager] ⚠️ ids[playlists] did not succeed for '%@', falling back to creating library playlist", targetId)
            }
        }

        // 3. Fallback: Create a new user library playlist with tracks via POST /v1/me/library/playlists
        var effectiveTracks = tracks
        if effectiveTracks.isEmpty && !targetId.isEmpty && Self.isValidResourceIdentifier(targetId) {
            effectiveTracks = await getPlaylistTracksById(playlistId: targetId)
        }
        if let token = devToken, let u = uToken, !u.isEmpty {
            let songIds = extractCatalogIdsFromTracks(effectiveTracks)
            if !songIds.isEmpty, let createUrl = Self.makeAppleMusicAPIURL(path: "/v1/me/library/playlists") {
                var req = URLRequest(url: createUrl)
                req.httpMethod = "POST"
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                req.setValue(u, forHTTPHeaderField: "Music-User-Token")
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let plTitle = cleanName.isEmpty
                    ? AMRLocalization.tr("Apple Music Playlist", "Плейлист Apple Music")
                    : cleanName
                let trackData = songIds.map { ["id": $0, "type": "songs"] }
                let payload: [String: Any] = [
                    "attributes": [
                        "name": plTitle,
                        "description": AMRLocalization.tr("Added via Apple Music Remote", "Добавлено через Apple Music Remote")
                    ],
                    "relationships": [
                        "tracks": [
                            "data": trackData
                        ]
                    ]
                ]
                if let body = try? JSONSerialization.data(withJSONObject: payload) {
                    req.httpBody = body
                    if let (_, resp) = try? await session.data(for: req),
                       let http = resp as? HTTPURLResponse,
                       (http.statusCode == 200 || http.statusCode == 201 || http.statusCode == 202) {
                        NSLog("[MusicKitManager] ✅ Created user library playlist '%@' with %d tracks", plTitle, songIds.count)
                        invalidateCloudLibraryPlaylistsCache()
                        triggerCloudLibrarySyncInMusicApp()
                        LibraryService.shared.invalidatePlaylistsCache()
                        return true
                    }
                }
            }
        }

        // 4. Local Music.app AppleScript fallback for local playlists
        if !cleanName.isEmpty && !PlaybackRouter.shared.isTestingEnvironment {
            let escName = cleanName.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let (ok, _) = AppleScriptExecutor.shared.execute("""
            tell application "Music"
                with timeout of 2 seconds
                    try
                        if not (exists user playlist "\(escName)") then
                            make new user playlist with properties {name:"\(escName)"}
                        end if
                        return "ok"
                    on error
                        return "error"
                    end try
                end timeout
            end tell
            """, maxWait: 2.5)
            if ok {
                LibraryService.shared.invalidatePlaylistsCache()
                return true
            }
        }

        return false
    }

    public func addAlbumToLibrary(albumId: String, name: String, artist: String, tracks: [TrackInfo] = []) async -> Bool {
        let cleanId = albumId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        var targetAlbumId = ""
        if let num = Int(cleanId), num > 10_000_000 {
            targetAlbumId = cleanId
        }

        // Extract album ID from track URL if needed
        if targetAlbumId.isEmpty {
            for t in tracks {
                if let u = t.url, u.contains("/album/") {
                    let cleanPath = u.components(separatedBy: "?").first ?? u
                    if let lastSeg = cleanPath.split(separator: "/").last,
                       let num = Int(lastSeg), num > 10_000_000 {
                        targetAlbumId = String(lastSeg)
                        break
                    }
                }
            }
        }

        let devToken = getDeveloperToken()
        let uToken = getUserToken()

        // Search catalog by name + artist if targetAlbumId is still empty
        if targetAlbumId.isEmpty, let token = devToken, (!cleanName.isEmpty || !cleanArtist.isEmpty) {
            let sf = Self.sanitizedStorefront(getUserStorefront())
            let lang = getPreferredLanguageTag()
            let query = "\(cleanName) \(cleanArtist)".trimmingCharacters(in: .whitespacesAndNewlines)
            if let searchUrl = Self.makeAppleMusicAPIURL(
                path: "/v1/catalog/\(sf)/search",
                queryItems: [
                    URLQueryItem(name: "term", value: query),
                    URLQueryItem(name: "types", value: "albums"),
                    URLQueryItem(name: "limit", value: "10"),
                    URLQueryItem(name: "l", value: lang)
                ]
            ) {
                var sReq = URLRequest(url: searchUrl)
                sReq.timeoutInterval = 4.0
                sReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                sReq.setValue("application/json", forHTTPHeaderField: "Accept")
                sReq.setValue(lang, forHTTPHeaderField: "Accept-Language")
                if let (sData, sResp) = try? await session.data(for: sReq),
                   let sHttp = sResp as? HTTPURLResponse, sHttp.statusCode == 200,
                   let sJson = try? JSONSerialization.jsonObject(with: sData) as? [String: Any],
                   let results = sJson["results"] as? [String: Any],
                   let albumsObj = results["albums"] as? [String: Any],
                   let albumsData = albumsObj["data"] as? [[String: Any]] {
                    for item in albumsData {
                        guard let candId = item["id"] as? String,
                              Self.isValidResourceIdentifier(candId),
                              let attrs = item["attributes"] as? [String: Any] else { continue }
                        let candName = (attrs["name"] as? String) ?? ""
                        let candArtist = (attrs["artistName"] as? String) ?? ""
                        if Self.albumMatches(candName, candArtist, cleanName, cleanArtist) {
                            targetAlbumId = candId
                            break
                        }
                    }
                }
            }
        }

        let bestArt = tracks.first(where: { !$0.artworkUrl.isEmpty })?.artworkUrl ?? ""
        let resolvedTrackCount: Int? = tracks.isEmpty ? nil : tracks.count
        let finalizeAdded: (String, Bool) -> Void = { [weak self] resolvedAlbumId, triggerCloudSync in
            self?.recordAddedAlbumToLibrary(
                albumId: resolvedAlbumId,
                name: cleanName,
                artist: cleanArtist,
                artwork: bestArt,
                trackCount: resolvedTrackCount
            )
            PlaybackStateStore.shared.promoteStagedTracksForSavedAlbum(
                name: cleanName,
                artist: cleanArtist,
                tracks: tracks
            )
            LibraryService.shared.invalidateLibrarySongsCache()
            if triggerCloudSync {
                self?.triggerCloudLibrarySyncInMusicApp()
            }
        }

        if let token = devToken, let u = uToken, !u.isEmpty {
            // 1. Add album by catalog ID: POST /v1/me/library?ids[albums]=...
            if Self.isValidResourceIdentifier(targetAlbumId),
               let url = Self.makeAppleMusicAPIURL(
                   path: "/v1/me/library",
                   queryItems: [URLQueryItem(name: "ids[albums]", value: targetAlbumId)]
               ) {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                req.setValue(u, forHTTPHeaderField: "Music-User-Token")
                if let (_, resp) = try? await session.data(for: req),
                   let http = resp as? HTTPURLResponse,
                   (http.statusCode == 200 || http.statusCode == 201 || http.statusCode == 202 || http.statusCode == 204) {
                    NSLog("[MusicKitManager] ✅ Successfully added album '%@' (%@) to user library", cleanName, targetAlbumId)
                    finalizeAdded(targetAlbumId, true)
                    return true
                }
            }

            // 2. Fallback: Add album tracks via POST /v1/me/library?ids[songs]=... in chunks of 50
            let songIds = extractCatalogIdsFromTracks(tracks)
            if !songIds.isEmpty {
                var addedCount = 0
                var startIdx = 0
                while startIdx < songIds.count {
                    let endIdx = min(startIdx + 50, songIds.count)
                    let chunk = songIds[startIdx..<endIdx]
                    let joinedIds = chunk.joined(separator: ",")
                    if let url = Self.makeAppleMusicAPIURL(
                        path: "/v1/me/library",
                        queryItems: [URLQueryItem(name: "ids[songs]", value: joinedIds)]
                    ) {
                        var req = URLRequest(url: url)
                        req.httpMethod = "POST"
                        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                        req.setValue(u, forHTTPHeaderField: "Music-User-Token")
                        if let (_, resp) = try? await session.data(for: req),
                           let http = resp as? HTTPURLResponse,
                           (http.statusCode == 200 || http.statusCode == 201 || http.statusCode == 202 || http.statusCode == 204) {
                            addedCount += chunk.count
                        }
                    }
                    startIdx = endIdx
                }
                if addedCount > 0 {
                    NSLog("[MusicKitManager] ✅ Successfully added %d album tracks for '%@' to user library", addedCount, cleanName)
                    finalizeAdded(targetAlbumId, true)
                    return true
                }
            }
        }

        // 3. Fallback: Local Music.app addToLibrary
        var anyAdded = false
        for t in tracks {
            if await LibraryService.shared.addToLibraryAsync(id: t.catalogId ?? t.id, trackId: t.numericId, name: t.name, artist: t.artist, url: t.url) {
                anyAdded = true
            }
        }
        if anyAdded {
            finalizeAdded(targetAlbumId, false)
        }
        return anyAdded
    }
}
