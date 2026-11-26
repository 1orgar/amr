//
//  MusicKitManager+Playlists.swift
//  AppleMusicRemoteMac
//
//  Cloud queue playlists, library playlist deletion, playlist track fetching by ID,
//  and hybrid Replay playlist assembly.
//

import Foundation

extension MusicKitManager {

    internal func storePlaylistTracksCached(id: String, tracks: [TrackInfo]) {
        withLock {
            if playlistTracksCache[id] == nil && playlistTracksCache.count >= Self.maxPlaylistTracksCacheEntries {
                let now = Date()
                playlistTracksCache = playlistTracksCache.filter { now.timeIntervalSince($0.value.timestamp) < 3600.0 }
                if playlistTracksCache.count >= Self.maxPlaylistTracksCacheEntries,
                   let oldestKey = playlistTracksCache.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
                    playlistTracksCache.removeValue(forKey: oldestKey)
                }
            }
            playlistTracksCache[id] = (timestamp: Date(), tracks: tracks)
        }
    }

    public func createTemporaryCloudPlaylist(name: String = "Очередь AMR", trackCatalogIds: [String]) async -> String? {
        return await syncCloudQueuePlaylist(trackCatalogIds: trackCatalogIds, name: name)
    }

    public func syncCloudQueuePlaylist(trackCatalogIds: [String], name: String = "Очередь AMR", minTracks: Int = 1) async -> String? {
        guard let devToken = getDeveloperToken(), let uToken = getUserToken(), !uToken.isEmpty else {
            NSLog("[MusicKitManager] Cannot sync iCloud playlist: missing developer or user token")
            return nil
        }
        let validCatalogIds = trackCatalogIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { Self.isValidResourceIdentifier($0) }
        guard !validCatalogIds.isEmpty else { return nil }

        // Step 1: Clean up previous temporary cloud playlist from iCloud
        let oldCloudId = withLock { lastTemporaryCloudPlaylistId }
        if let oldId = oldCloudId {
            Task.detached(priority: .background) { [weak self] in
                _ = await self?.deleteTemporaryCloudPlaylist(playlistId: oldId)
            }
        }

        let safeName = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // Remove any old temporary queue playlists in Music.app so they do not accumulate
        if !PlaybackRouter.shared.isTestingEnvironment {
            _ = AppleScriptExecutor.shared.execute("""
            tell application "Music"
                try
                    repeat with p in (get every user playlist whose name is "\(safeName)")
                        try
                            delete p
                        end try
                    end repeat
                end try
            end tell
            """)
        }

        // Step 2: Create new playlist with all track catalog IDs via Cloud API
        guard let url = Self.makeAppleMusicAPIURL(path: "/v1/me/library/playlists") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let trackData = validCatalogIds.map { ["id": $0, "type": "songs"] }
        let payload: [String: Any] = [
            "attributes": [
                "name": name,
                "description": AMRLocalization.tr("Apple Music Remote Playback Queue", "Очередь воспроизведения Apple Music Remote")
            ],
            "relationships": [
                "tracks": [
                    "data": trackData
                ]
            ]
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        req.httpBody = body

        var createdPlaylistId: String?
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 201) else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let errStr = String(data: data, encoding: .utf8) ?? ""
                NSLog("[MusicKitManager] ❌ Failed to create cloud playlist '%@' (status %d): %@", name, code, errStr)
                return nil
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let arr = json["data"] as? [[String: Any]],
               let first = arr.first,
               let plId = first["id"] as? String,
               Self.isValidResourceIdentifier(plId) {
                createdPlaylistId = plId
                withLock {
                    lastTemporaryCloudPlaylistId = plId
                }
                NSLog("[MusicKitManager] ✅ Created cloud queue playlist: '%@' with %d tracks", plId, validCatalogIds.count)
            }
        } catch {
            NSLog("[MusicKitManager] ❌ Error creating cloud queue playlist: %@", error.localizedDescription)
            return nil
        }

        guard let plId = createdPlaylistId else { return nil }

        if PlaybackRouter.shared.isTestingEnvironment {
            return plId
        }

        // Step 3: Wait for Music.app to sync the playlist and its tracks into its local library cache
        let targetMin = min(validCatalogIds.count, max(minTracks, 1))
        for _ in 1...60 {
            let (ok, out) = AppleScriptExecutor.shared.execute("""
            tell application "Music"
                set maxTracks to 0
                repeat with p in (get every user playlist whose name is "\(safeName)")
                    try
                        set c to count of tracks of p
                        if c > maxTracks then
                            set maxTracks to c
                        end if
                    end try
                end repeat
                return maxTracks
            end tell
            """)
            if ok, let countStr = out?.trimmingCharacters(in: .whitespacesAndNewlines), let count = Int(countStr), count >= targetMin {
                NSLog("[MusicKitManager] ⚡️ Playlist '%@' is now available in Music.app with %d tracks", name, count)
                return plId
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        NSLog("[MusicKitManager] ⚡️ Playlist '%@' created in cloud (%@), continuing with immediate playback", name, plId)
        return plId
    }

    public func addTracksToTemporaryCloudPlaylist(trackCatalogIds: [String]) async -> Bool {
        guard let devToken = getDeveloperToken(), let uToken = getUserToken(), !uToken.isEmpty else { return false }
        let plId = withLock { lastTemporaryCloudPlaylistId }
        let validIds = trackCatalogIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { Self.isValidResourceIdentifier($0) }
        guard let playlistId = plId, Self.isValidResourceIdentifier(playlistId), !validIds.isEmpty else { return false }

        guard let addUrl = Self.makeAppleMusicAPIURL(path: "/v1/me/library/playlists/\(playlistId)/tracks") else {
            return false
        }
        var addReq = URLRequest(url: addUrl)
        addReq.httpMethod = "POST"
        addReq.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        addReq.setValue(uToken, forHTTPHeaderField: "Music-User-Token")
        addReq.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let trackData = validIds.map { ["id": $0, "type": "songs"] }
        let addPayload: [String: Any] = ["data": trackData]
        guard let addBody = try? JSONSerialization.data(withJSONObject: addPayload) else { return false }
        addReq.httpBody = addBody

        do {
            let (addData, addResp) = try await session.data(for: addReq)
            if let addHttp = addResp as? HTTPURLResponse, (addHttp.statusCode == 200 || addHttp.statusCode == 201 || addHttp.statusCode == 204) {
                NSLog("[MusicKitManager] ✅ Successfully appended %d tracks into temporary iCloud playlist '%@'", validIds.count, playlistId)
                return true
            } else {
                let addErr = String(data: addData, encoding: .utf8) ?? ""
                NSLog("[MusicKitManager] ⚠️ Warning appending tracks to playlist (status %d): %@", (addResp as? HTTPURLResponse)?.statusCode ?? 0, addErr)
                return false
            }
        } catch {
            NSLog("[MusicKitManager] ⚠️ Error appending tracks to playlist: %@", error.localizedDescription)
            return false
        }
    }

    public func deleteTemporaryCloudPlaylist(playlistId: String) async -> Bool {
        let cleanId = playlistId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidResourceIdentifier(cleanId),
              let devToken = getDeveloperToken(),
              let uToken = getUserToken(), !uToken.isEmpty else { return false }
        guard let url = Self.makeAppleMusicAPIURL(path: "/v1/me/library/playlists/\(cleanId)") else { return false }

        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")

        do {
            let (data, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 204) {
                NSLog("[MusicKitManager] 🗑 Deleted temporary iCloud playlist: '%@'", cleanId)
                return true
            } else if let http = resp as? HTTPURLResponse {
                let errStr = String(data: data, encoding: .utf8) ?? ""
                NSLog("[MusicKitManager] ⚠️ Delete iCloud playlist status %d for '%@': %@", http.statusCode, cleanId, errStr)
            }
        } catch {
            NSLog("[MusicKitManager] Error deleting iCloud playlist: %@", error.localizedDescription)
        }
        return false
    }

    public func deleteUserLibraryPlaylist(playlistId: String? = nil, name: String) async -> Bool {
        let cleanId = playlistId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        invalidatePlaylistTracksCache()
        invalidateCloudLibraryPlaylistsCache()

        guard !PlaybackRouter.shared.isTestingEnvironment,
              let devToken = getDeveloperToken(),
              let uToken = getUserToken(),
              !uToken.isEmpty else {
            return false
        }

        var candidateIds: [String] = []
        if cleanId.hasPrefix("p."), Self.isValidResourceIdentifier(cleanId) {
            candidateIds.append(cleanId)
        }

        if candidateIds.isEmpty && (!cleanName.isEmpty || !cleanId.isEmpty) {
            let lang = getPreferredLanguageTag()
            if let listUrl = Self.makeAppleMusicAPIURL(
                path: "/v1/me/library/playlists",
                queryItems: [
                    URLQueryItem(name: "limit", value: "100"),
                    URLQueryItem(name: "include", value: "catalog"),
                    URLQueryItem(name: "l", value: lang)
                ]
            ) {
                var req = URLRequest(url: listUrl, timeoutInterval: 4.0)
                req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
                req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                req.setValue(lang, forHTTPHeaderField: "Accept-Language")

                if let (data, resp) = try? await session.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let arr = json["data"] as? [[String: Any]] {
                    for item in arr {
                        guard let libPlId = item["id"] as? String, Self.isValidResourceIdentifier(libPlId) else { continue }
                        let attrs = (item["attributes"] as? [String: Any]) ?? [:]
                        let pName = (attrs["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        var matched = false
                        if !cleanName.isEmpty && (pName.caseInsensitiveCompare(cleanName) == .orderedSame || LibraryService.playlistsSharePersonalMixAlias(pName, cleanName)) {
                            matched = true
                        }
                        if !matched, !cleanId.isEmpty,
                           let playParams = attrs["playParams"] as? [String: Any],
                           let globalId = playParams["globalId"] as? String,
                           globalId.caseInsensitiveCompare(cleanId) == .orderedSame {
                            matched = true
                        }
                        if !matched, !cleanId.isEmpty,
                           let rels = item["relationships"] as? [String: Any],
                           let catObj = rels["catalog"] as? [String: Any],
                           let catData = catObj["data"] as? [[String: Any]],
                           catData.contains(where: { ($0["id"] as? String)?.caseInsensitiveCompare(cleanId) == .orderedSame }) {
                            matched = true
                        }
                        if matched && !candidateIds.contains(libPlId) {
                            candidateIds.append(libPlId)
                        }
                    }
                }
            }
        }

        var deletedAny = false
        for libId in candidateIds {
            if await deleteTemporaryCloudPlaylist(playlistId: libId) {
                deletedAny = true
            }
        }
        return deletedAny
    }

    // MARK: - Playlist Tracks by ID (MusicKit Catalog & Library)

    public func invalidatePlaylistTracksCache() {
        withLock {
            playlistTracksCache.removeAll()
        }
    }

    public func getPlaylistTracksById(playlistId: String, storefront: String? = nil) async -> [TrackInfo] {
        let cleanId = playlistId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else { return [] }

        if let cached = withLock({ () -> [TrackInfo]? in
            if let entry = playlistTracksCache[cleanId], Date().timeIntervalSince(entry.timestamp) < 3600.0 {
                return entry.tracks
            }
            return nil
        }) {
            if !PlaybackRouter.shared.isTestingEnvironment {
                return LibraryService.shared.resolveLocalLibraryMatches(cached, updateNames: false, includeStagedTemporary: false)
            }
            return cached
        }

        if cleanId == "replay_playlist" || cleanId.lowercased().contains("replay") {
            return await getPersonalizedReplayTracks()
        }

        guard Self.isValidResourceIdentifier(cleanId),
              let token = getDeveloperToken() else { return [] }
        let uToken = getUserToken()
        let primarySf = Self.sanitizedStorefront(storefront, fallback: getUserStorefront())
        let lang = getPreferredLanguageTag()

        var fetchedTracks: [TrackInfo] = []

        // 1. Catalog tracks endpoint: GET /v1/catalog/{sf}/playlists/{id}/tracks
        func tryCatalogTracks(storefrontToTry: String) async -> [TrackInfo] {
            guard Self.isValidStorefrontCode(storefrontToTry),
                  let url = Self.makeAppleMusicAPIURL(
                      path: "/v1/catalog/\(storefrontToTry)/playlists/\(cleanId)/tracks",
                      queryItems: [
                          URLQueryItem(name: "l", value: lang),
                          URLQueryItem(name: "limit", value: "100")
                      ]
                  ) else { return [] }
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let u = uToken, !u.isEmpty {
                req.setValue(u, forHTTPHeaderField: "Music-User-Token")
            }
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue(lang, forHTTPHeaderField: "Accept-Language")

            guard let (data, resp) = try? await session.data(for: req),
                  let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tracksData = json["data"] as? [[String: Any]], !tracksData.isEmpty else {
                return []
            }
            return parseCatalogTrackItems(tracksData)
        }

        fetchedTracks = await tryCatalogTracks(storefrontToTry: primarySf)
        if fetchedTracks.isEmpty && primarySf != "us" {
            fetchedTracks = await tryCatalogTracks(storefrontToTry: "us")
        }

        // 2. Catalog full playlist endpoint with relationships: GET /v1/catalog/{sf}/playlists/{id}
        if fetchedTracks.isEmpty {
            func tryCatalogPlaylist(storefrontToTry: String) async -> [TrackInfo] {
                guard Self.isValidStorefrontCode(storefrontToTry),
                      let url = Self.makeAppleMusicAPIURL(
                          path: "/v1/catalog/\(storefrontToTry)/playlists/\(cleanId)",
                          queryItems: [URLQueryItem(name: "l", value: lang)]
                      ) else { return [] }
                var req = URLRequest(url: url)
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                if let u = uToken, !u.isEmpty {
                    req.setValue(u, forHTTPHeaderField: "Music-User-Token")
                }
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                req.setValue(lang, forHTTPHeaderField: "Accept-Language")

                guard let (data, resp) = try? await session.data(for: req),
                      let http = resp as? HTTPURLResponse, http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let dataArr = json["data"] as? [[String: Any]],
                      let plObj = dataArr.first,
                      let rels = plObj["relationships"] as? [String: Any],
                      let trksObj = rels["tracks"] as? [String: Any],
                      let trksData = trksObj["data"] as? [[String: Any]], !trksData.isEmpty else {
                    return []
                }
                return parseCatalogTrackItems(trksData)
            }

            fetchedTracks = await tryCatalogPlaylist(storefrontToTry: primarySf)
            if fetchedTracks.isEmpty && primarySf != "us" {
                fetchedTracks = await tryCatalogPlaylist(storefrontToTry: "us")
            }
        }

        // 3. User iCloud Library playlist endpoint: GET /v1/me/library/playlists/{id}/tracks
        if fetchedTracks.isEmpty, let u = uToken, !u.isEmpty, (cleanId.hasPrefix("p.") || cleanId.hasPrefix("pl.")) {
            if let url = Self.makeAppleMusicAPIURL(
                path: "/v1/me/library/playlists/\(cleanId)/tracks",
                queryItems: [
                    URLQueryItem(name: "limit", value: "100"),
                    URLQueryItem(name: "l", value: lang)
                ]
            ) {
                var req = URLRequest(url: url)
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                req.setValue(u, forHTTPHeaderField: "Music-User-Token")
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                req.setValue(lang, forHTTPHeaderField: "Accept-Language")

                if let (data, resp) = try? await session.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tracksData = json["data"] as? [[String: Any]], !tracksData.isEmpty {
                    fetchedTracks = parseCatalogTrackItems(tracksData)
                }
            }
        }

        if !fetchedTracks.isEmpty {
            if !PlaybackRouter.shared.isTestingEnvironment {
                fetchedTracks = LibraryService.shared.resolveLocalLibraryMatches(fetchedTracks, updateNames: false, includeStagedTemporary: false)
            }
            storePlaylistTracksCached(id: cleanId, tracks: fetchedTracks)
            NSLog("[MusicKitManager] 📋 Fetched & cached %d tracks for playlist '%@'", fetchedTracks.count, cleanId)
        }

        return fetchedTracks
    }

    // MARK: - Personalized Replay Tracks (Cloud + Local Hybrid)

    public func getPersonalizedReplayTracks() async -> [TrackInfo] {
        if let cached = withLock({ () -> [TrackInfo]? in
            if let entry = playlistTracksCache["replay_playlist"], Date().timeIntervalSince(entry.timestamp) < 300.0, !entry.tracks.isEmpty {
                return entry.tracks
            }
            return nil
        }) {
            return cached
        }

        var result = [TrackInfo]()
        var seenKeys = Set<String>()

        // 1. Check if user has an explicit Replay playlist in cloud library
        let devToken = getDeveloperToken()
        let uToken = getUserToken()
        let lang = getPreferredLanguageTag()
        if let dToken = devToken, let userT = uToken, !userT.isEmpty {
            if let libUrl = Self.makeAppleMusicAPIURL(
                path: "/v1/me/library/playlists",
                queryItems: [
                    URLQueryItem(name: "limit", value: "100"),
                    URLQueryItem(name: "l", value: lang)
                ]
            ) {
                var req = URLRequest(url: libUrl)
                req.setValue("Bearer \(dToken)", forHTTPHeaderField: "Authorization")
                req.setValue(userT, forHTTPHeaderField: "Music-User-Token")
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                req.setValue(lang, forHTTPHeaderField: "Accept-Language")

                if let (data, resp) = try? await session.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let arr = json["data"] as? [[String: Any]] {
                    if let found = arr.first(where: { item in
                        let attrs = item["attributes"] as? [String: Any] ?? [:]
                        let name = (attrs["name"] as? String ?? "").lowercased()
                        return name.contains("replay") || name.contains("итоги")
                    }), let realId = found["id"] as? String, Self.isValidResourceIdentifier(realId) {
                        let cloudReplayTracks = await getPlaylistTracksById(playlistId: realId)
                        if !cloudReplayTracks.isEmpty {
                            storePlaylistTracksCached(id: "replay_playlist", tracks: cloudReplayTracks)
                            return cloudReplayTracks
                        }
                    }
                }
            }
        }

        // 2. Check personal recommendations for Replay / Yearly Review
        let recs = await fetchPersonalRecommendations()
        for r in recs {
            let n = r.title.lowercased()
            if n.contains("replay") || n.contains("итоги") || n.contains("favorite") || n.contains("любим") {
                let plId = r.id
                if (plId.hasPrefix("pl.") || plId.hasPrefix("p.")) && Self.isValidResourceIdentifier(plId) {
                    let cloudTracks = await getPlaylistTracksById(playlistId: plId)
                    for t in cloudTracks {
                        let k = "\(t.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(t.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
                        if !k.isEmpty && !seenKeys.contains(k) {
                            seenKeys.insert(k)
                            var trk = t
                            trk.index = result.count + 1
                            result.append(trk)
                        }
                    }
                    if !result.isEmpty { break }
                }
            }
        }

        // 3. Supplement with local library top played tracks (highest played count in user library)
        let localTop = LibraryService.shared.getTopPlayedTracks(limit: 50)
        for t in localTop {
            if result.count >= 50 { break }
            let k = "\(t.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(t.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
            if !k.isEmpty && !seenKeys.contains(k) {
                seenKeys.insert(k)
                var trk = t
                trk.index = result.count + 1
                result.append(trk)
            }
        }

        // 4. Fallback if still empty: cached library songs
        if result.isEmpty {
            let fallbackSongs = LibraryService.shared.getLibrarySongs()
            for (idx, var t) in fallbackSongs.prefix(50).enumerated() {
                t.index = idx + 1
                result.append(t)
            }
        }

        storePlaylistTracksCached(id: "replay_playlist", tracks: result)
        NSLog("[MusicKitManager] 🎵 Formed hybrid Replay tracks: %d tracks (cloud + local)", result.count)
        return result
    }
}
