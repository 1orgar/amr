//
//  MusicKitManager+Playlists.swift
//  AppleMusicRemoteMac
//

import Foundation

extension MusicKitManager {
    public func createTemporaryCloudPlaylist(name: String = "Очередь AMR", trackCatalogIds: [String]) async -> String? {
        return await syncCloudQueuePlaylist(trackCatalogIds: trackCatalogIds, name: name)
    }

    public func syncCloudQueuePlaylist(trackCatalogIds: [String], name: String = "Очередь AMR", minTracks: Int = 1) async -> String? {
        guard let devToken = getDeveloperToken(), let uToken = getUserToken(), !uToken.isEmpty else {
            NSLog("[MusicKitManager] Cannot sync iCloud playlist: missing developer or user token")
            return nil
        }
        guard !trackCatalogIds.isEmpty else { return nil }

        // Step 1: Clean up previous temporary cloud playlist from iCloud
        let oldCloudId = withLock { lastTemporaryCloudPlaylistId }
        if let oldId = oldCloudId {
            Task.detached(priority: .background) { [weak self] in
                _ = await self?.deleteTemporaryCloudPlaylist(playlistId: oldId)
            }
        }

        // Remove any old temporary queue playlists in Music.app so they do not accumulate
        // and so that their deletion syncs to iCloud, ensuring only ONE queue playlist exists.
        if !PlaybackRouter.shared.isTestingEnvironment {
            _ = AppleScriptExecutor.shared.execute("""
            tell application "Music"
                try
                    repeat with p in (get every user playlist whose name is "\(name)")
                        try
                            delete p
                        end try
                    end repeat
                end try
            end tell
            """)
        }

        // Step 2: Create new playlist with all track catalog IDs via Cloud API
        guard let url = URL(string: "https://api.music.apple.com/v1/me/library/playlists") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let trackData = trackCatalogIds.map { ["id": $0, "type": "songs"] }
        let payload: [String: Any] = [
            "attributes": [
                "name": name,
                "description": "Очередь воспроизведения Apple Music Remote"
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
               let plId = first["id"] as? String {
                createdPlaylistId = plId
                withLock {
                    lastTemporaryCloudPlaylistId = plId
                }
                NSLog("[MusicKitManager] ✅ Created cloud queue playlist: '%@' with %d tracks", plId, trackCatalogIds.count)
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
        let targetMin = min(trackCatalogIds.count, max(minTracks, 1))
        for _ in 1...60 {
            let (ok, out) = AppleScriptExecutor.shared.execute("""
            tell application "Music"
                set maxTracks to 0
                repeat with p in (get every user playlist whose name is "\(name)")
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
        guard let playlistId = plId, !trackCatalogIds.isEmpty else { return false }

        guard let addUrl = URL(string: "https://api.music.apple.com/v1/me/library/playlists/\(playlistId)/tracks") else {
            return false
        }
        var addReq = URLRequest(url: addUrl)
        addReq.httpMethod = "POST"
        addReq.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        addReq.setValue(uToken, forHTTPHeaderField: "Music-User-Token")
        addReq.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let trackData = trackCatalogIds.map { ["id": $0, "type": "songs"] }
        let addPayload: [String: Any] = ["data": trackData]
        guard let addBody = try? JSONSerialization.data(withJSONObject: addPayload) else { return false }
        addReq.httpBody = addBody

        do {
            let (addData, addResp) = try await session.data(for: addReq)
            if let addHttp = addResp as? HTTPURLResponse, (addHttp.statusCode == 200 || addHttp.statusCode == 201 || addHttp.statusCode == 204) {
                NSLog("[MusicKitManager] ✅ Successfully appended %d tracks into temporary iCloud playlist '%@'", trackCatalogIds.count, playlistId)
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
        guard let devToken = getDeveloperToken(), let uToken = getUserToken(), !uToken.isEmpty else { return false }
        guard let url = URL(string: "https://api.music.apple.com/v1/me/library/playlists/\(playlistId)") else { return false }

        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")

        do {
            let (data, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 204) {
                NSLog("[MusicKitManager] 🗑 Deleted temporary iCloud playlist: '%@'", playlistId)
                return true
            } else if let http = resp as? HTTPURLResponse {
                let errStr = String(data: data, encoding: .utf8) ?? ""
                NSLog("[MusicKitManager] ⚠️ Delete iCloud playlist status %d for '%@': %@", http.statusCode, playlistId, errStr)
            }
        } catch {
            NSLog("[MusicKitManager] Error deleting iCloud playlist: %@", error.localizedDescription)
        }
        return false
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
                return LibraryService.shared.resolveLocalLibraryMatches(cached, updateNames: false)
            }
            return cached
        }

        if cleanId == "replay_playlist" || cleanId.lowercased().contains("replay") {
            return await getPersonalizedReplayTracks()
        }

        guard let token = getDeveloperToken() else { return [] }
        let uToken = getUserToken()
        let sf = (storefront?.lowercased() ?? getUserStorefront()).trimmingCharacters(in: .whitespacesAndNewlines)
        let primarySf = sf.isEmpty ? "us" : sf
        let lang = getPreferredLanguageTag()

        var fetchedTracks: [TrackInfo] = []

        // 1. Catalog tracks endpoint: GET /v1/catalog/{sf}/playlists/{id}/tracks
        func tryCatalogTracks(storefrontToTry: String) async -> [TrackInfo] {
            let langQuery = "?l=\(lang)&limit=100"
            guard let url = URL(string: "https://api.music.apple.com/v1/catalog/\(storefrontToTry)/playlists/\(cleanId)/tracks\(langQuery)") else { return [] }
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
                let langQuery = "?l=\(lang)"
                guard let url = URL(string: "https://api.music.apple.com/v1/catalog/\(storefrontToTry)/playlists/\(cleanId)\(langQuery)") else { return [] }
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
            if let url = URL(string: "https://api.music.apple.com/v1/me/library/playlists/\(cleanId)/tracks?limit=100&l=\(lang)") {
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
                fetchedTracks = LibraryService.shared.resolveLocalLibraryMatches(fetchedTracks, updateNames: false)
            }
            withLock {
                playlistTracksCache[cleanId] = (timestamp: Date(), tracks: fetchedTracks)
            }
            NSLog("[MusicKitManager] 📋 Fetched & cached %d tracks for playlist '%@'", fetchedTracks.count, cleanId)
        }

        return fetchedTracks
    }

    // MARK: - Fast Cloud Song Library Staging (On-Demand & Pre-Staging)

    private static let stageDedupLock = NSLock()
    private static var recentlyStagedCatalogIds: [String: Date] = [:]

    @discardableResult
    public func stageCloudSongsInLibrarySync(catalogIds: [String]) -> Bool {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return true }
        guard let devToken = getDeveloperToken(), let uToken = getUserToken(), !uToken.isEmpty else {
            return false
        }
        let allValidIds = Array(Set(catalogIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { Int($0) != nil && !$0.isEmpty })).prefix(10)
        guard !allValidIds.isEmpty else { return false }

        let now = Date()
        let idsToSend: [String] = Self.stageDedupLock.withLock {
            Self.recentlyStagedCatalogIds = Self.recentlyStagedCatalogIds.filter { now.timeIntervalSince($0.value) < 15.0 }
            let fresh = allValidIds.filter { Self.recentlyStagedCatalogIds[$0] == nil }
            for cid in fresh {
                Self.recentlyStagedCatalogIds[cid] = now
            }
            return fresh
        }
        if idsToSend.isEmpty {
            return true
        }

        let idsParam = idsToSend.joined(separator: ",")
        guard let url = URL(string: "https://api.music.apple.com/v1/me/library?ids%5Bsongs%5D=\(idsParam)") else { return false }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")

        let sema = DispatchSemaphore(value: 0)
        var ok = false
        session.dataTask(with: req) { _, resp, _ in
            if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                ok = true
            }
            sema.signal()
        }.resume()
        _ = sema.wait(timeout: .now() + 4.0)
        return ok
    }

    public func resolveCatalogSongIdInUserStorefrontSync(name: String, artist: String) -> String? {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return nil }
        guard let devToken = getDeveloperToken() else { return nil }
        let sf = getUserStorefront()
        let lang = getPreferredLanguageTag()
        let query = "\(name) \(artist)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        guard let url = URL(string: "https://api.music.apple.com/v1/catalog/\(sf)/search?term=\(encoded)&types=songs&limit=5&l=\(lang)") else { return nil }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(lang, forHTTPHeaderField: "Accept-Language")
        if let uToken = getUserToken(), !uToken.isEmpty {
            req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")
        }

        let sema = DispatchSemaphore(value: 0)
        var resolvedId: String?
        let targetNameNorm = LibraryService.normalizeMatchingTitle(name)
        let targetBaseNorm = LibraryService.normalizeMatchingTitle(Self.extractBaseTrackTitle(name))
        let targetArtistNorm = artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        session.dataTask(with: req) { data, resp, _ in
            defer { sema.signal() }
            guard let d = data, let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let results = json["results"] as? [String: Any],
                  let songs = results["songs"] as? [String: Any],
                  let arr = songs["data"] as? [[String: Any]], !arr.isEmpty else { return }

            for item in arr {
                guard let sid = item["id"] as? String, !sid.isEmpty,
                      let attr = item["attributes"] as? [String: Any] else { continue }
                let rawSName = (attr["name"] as? String) ?? ""
                let sName = LibraryService.normalizeMatchingTitle(rawSName)
                let sBase = LibraryService.normalizeMatchingTitle(Self.extractBaseTrackTitle(rawSName))
                let sArtist = ((attr["artistName"] as? String) ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let artistOk = targetArtistNorm.isEmpty || (!sArtist.isEmpty && (sArtist.contains(targetArtistNorm) || targetArtistNorm.contains(sArtist)))
                if artistOk && (sName == targetNameNorm || (!targetBaseNorm.isEmpty && sBase == targetBaseNorm)) {
                    resolvedId = sid
                    return
                }
            }
            if targetArtistNorm.isEmpty {
                resolvedId = arr.first?["id"] as? String
            }
        }.resume()
        _ = sema.wait(timeout: .now() + 3.5)
        return resolvedId
    }

    private static func extractBaseTrackTitle(_ title: String) -> String {
        var s = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parenIdx = s.firstIndex(of: "(") {
            let prefix = s[..<parenIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            if prefix.count >= 2 {
                s = prefix
            }
        }
        if let bracketIdx = s.firstIndex(of: "[") {
            let prefix = s[..<bracketIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            if prefix.count >= 2 {
                s = prefix
            }
        }
        if let dashRange = s.range(of: " - ") {
            let prefix = s[..<dashRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if prefix.count >= 2 {
                s = prefix
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractPrimaryArtist(_ artist: String) -> String {
        var s = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        for sep in [",", " & ", " feat.", " ft."] {
            if let r = s.range(of: sep, options: .caseInsensitive) {
                let prefix = s[..<r.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if prefix.count >= 2 {
                    s = prefix
                    break
                }
            }
        }
        return s
    }

    public func resolveLocalizedCatalogSongTitleSync(catalogId: String) -> (name: String, artist: String)? {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return nil }
        let cleanId = catalogId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty, Int(cleanId) != nil, let devToken = getDeveloperToken() else { return nil }
        let sf = getUserStorefront()
        let lang = getPreferredLanguageTag()
        guard let url = URL(string: "https://api.music.apple.com/v1/catalog/\(sf)/songs/\(cleanId)?l=\(lang)") else { return nil }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(lang, forHTTPHeaderField: "Accept-Language")
        if let uToken = getUserToken(), !uToken.isEmpty {
            req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")
        }

        let sema = DispatchSemaphore(value: 0)
        var resolved: (name: String, artist: String)?
        session.dataTask(with: req) { data, resp, _ in
            defer { sema.signal() }
            guard let d = data, let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let arr = json["data"] as? [[String: Any]],
                  let first = arr.first,
                  let attr = first["attributes"] as? [String: Any],
                  let locName = attr["name"] as? String, !locName.isEmpty else { return }
            let locArtist = (attr["artistName"] as? String) ?? ""
            resolved = (locName, locArtist)
        }.resume()
        _ = sema.wait(timeout: .now() + 2.5)
        return resolved
    }

    public func findTrackDatabaseIdInMusicApp(name: String, artist: String, preferredDbId: Int? = nil, checkSubscriptionPlaylists: Bool = true) -> Int? {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return nil }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let validPrefId = (preferredDbId != nil && preferredDbId! > 0 && preferredDbId! < 10_000_000) ? preferredDbId! : 0
        guard !cleanName.isEmpty || validPrefId > 0 else { return nil }

        let escN = cleanName.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let baseName = Self.extractBaseTrackTitle(cleanName)
        let escBase = (baseName.isEmpty ? cleanName : baseName).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let primaryArtist = Self.extractPrimaryArtist(artist)
        let escA = primaryArtist.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let artistClause = escA.isEmpty ? "" : " and artist contains \"\(escA)\""

        // Fast indexed search path for library playlist 1 (takes ~3ms even on large libraries when track is not present yet)
        if !checkSubscriptionPlaylists && validPrefId == 0 && !escBase.isEmpty {
            let fastScript = """
            tell application "Music"
                try
                    set foundList to (search (library playlist 1) for "\(escBase)")
                    repeat with tr in foundList
                        set trName to (name of tr as string)
                        set trArtist to (artist of tr as string)
                        if (trName is "\(escN)" or trName contains "\(escBase)") and ("\(escA)" is "" or trArtist contains "\(escA)") then
                            return database ID of tr
                        end if
                    end repeat
                end try
                return 0
            end tell
            """
            let (fOk, fOut) = AppleScriptExecutor.shared.execute(fastScript)
            if fOk, let str = fOut?.trimmingCharacters(in: .whitespacesAndNewlines), let dbId = Int(str), dbId > 0 {
                return dbId
            }
            return nil
        }

        let prefSubCheck = checkSubscriptionPlaylists ? """
            repeat with sp in (get every subscription playlist)
                try
                    return database ID of (first track of sp whose database ID is \(validPrefId))
                end try
            end repeat
        """ : ""

        let prefCheck = validPrefId > 0 ? """
            try
                return database ID of (first track of library playlist 1 whose database ID is \(validPrefId))
            end try
            \(prefSubCheck)
        """ : ""

        let indexedSearchCheck = !escBase.isEmpty ? """
            try
                set foundList to (search (library playlist 1) for "\(escBase)")
                repeat with tr in foundList
                    set trName to (name of tr as string)
                    set trArtist to (artist of tr as string)
                    if (trName is "\(escN)" or trName contains "\(escBase)") and ("\(escA)" is "" or trArtist contains "\(escA)") then
                        return database ID of tr
                    end if
                end repeat
            end try
        """ : ""

        let subNameCheck = checkSubscriptionPlaylists ? """
            repeat with sp in (get every subscription playlist)
                try
                    return database ID of (first track of sp whose name is "\(escN)"\(artistClause))
                end try
                try
                    return database ID of (first track of sp whose name contains "\(escBase)"\(artistClause))
                end try
            end repeat
        """ : ""

        let script = """
        tell application "Music"
            \(prefCheck)
            \(indexedSearchCheck)
            \(subNameCheck)
            try
                return database ID of (first track of library playlist 1 whose name is "\(escN)")
            end try
            return 0
        end tell
        """
        let (ok, out) = AppleScriptExecutor.shared.execute(script)
        if ok, let str = out?.trimmingCharacters(in: .whitespacesAndNewlines), let dbId = Int(str), dbId > 0 {
            return dbId
        }
        return nil
    }

    private static let stagePollLock = NSLock()

    public func stageAndResolveCloudTrackInLibrarySync(id: String?, url: String?, name: String, artist: String, timeout: TimeInterval = 11.0, expectedGeneration: UInt64? = nil) -> Int? {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return nil }
        guard hasUserToken else { return nil }

        let prefId = id.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }.flatMap { ($0 > 0 && $0 < 10_000_000) ? $0 : nil }

        // 1. Check if already in library playlist 1 or subscription playlists
        if let existingId = findTrackDatabaseIdInMusicApp(name: name, artist: artist, preferredDbId: prefId, checkSubscriptionPlaylists: true) {
            return existingId
        }

        // 2. Determine Apple Music catalog song ID (must be >= 10_000_000, not a local database ID)
        var catalogId: String? = nil
        if let u = url, let comp = URLComponents(string: u),
           let qi = comp.queryItems?.first(where: { $0.name == "i" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
           let num = Int(qi), num >= 10_000_000 {
            catalogId = qi
        }
        if catalogId == nil, let rawId = id?.trimmingCharacters(in: .whitespacesAndNewlines),
           let num = Int(rawId), num >= 10_000_000 {
            catalogId = rawId
        }
        if catalogId == nil && !name.isEmpty {
            catalogId = resolveCatalogSongIdInUserStorefrontSync(name: name, artist: artist)
        }
        if catalogId == nil, let rawId = id?.trimmingCharacters(in: .whitespacesAndNewlines), Int(rawId) != nil {
            catalogId = rawId
        }

        guard let initialId = catalogId, !initialId.isEmpty else { return nil }

        // 2b. Check localized (l=ru) song title from Apple Music catalog (e.g. "Mallow Blue" -> "マロウブルー")
        var localizedTitle: String? = nil
        var localizedArtist: String? = nil
        if let loc = resolveLocalizedCatalogSongTitleSync(catalogId: initialId), loc.name != name {
            localizedTitle = loc.name
            localizedArtist = loc.artist.isEmpty ? artist : loc.artist
            if let existingLocId = findTrackDatabaseIdInMusicApp(name: loc.name, artist: localizedArtist ?? artist, checkSubscriptionPlaylists: true) {
                return existingLocId
            }
        }

        _ = stageCloudSongsInLibrarySync(catalogIds: [initialId])

        let start = Date()
        var effectiveTimeout = timeout
        var didTryStorefrontResolve = false
        while Date().timeIntervalSince(start) < effectiveTimeout {
            if let expGen = expectedGeneration {
                let curGen = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.playbackGeneration }
                if curGen != expGen {
                    return nil
                }
            }
            Thread.sleep(forTimeInterval: 0.3)
            if let expGen = expectedGeneration {
                let curGen = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.playbackGeneration }
                if curGen != expGen {
                    return nil
                }
            }
            // Serialize AppleScript polling so background pre-staging and foreground play never double-poll Music.app
            let resolvedDbId: Int? = Self.stagePollLock.withLock {
                if let found = findTrackDatabaseIdInMusicApp(name: name, artist: artist, checkSubscriptionPlaylists: false) {
                    return found
                }
                if let locN = localizedTitle, let foundLoc = findTrackDatabaseIdInMusicApp(name: locN, artist: localizedArtist ?? artist, checkSubscriptionPlaylists: false) {
                    return foundLoc
                }
                return nil
            }
            if let dbId = resolvedDbId {
                PlaybackStateStore.shared.registerStagedTemporaryTrack(dbId: dbId)
                LibraryService.shared.registerStagedTrackInCache(dbId: dbId, name: localizedTitle ?? name, artist: localizedArtist ?? artist)
                NSLog("[MusicKitManager] ⚡️ Staged cloud track '%@' — '%@' into Music.app (dbId=%d in %.2fs)",
                      name, artist, dbId, Date().timeIntervalSince(start))
                return dbId
            }
            // Only if after 3.8s the track hasn't appeared (normal iCloud sync takes 2.0-3.5s),
            // resolve canonical ID in user's storefront with strict artist check and re-stage.
            if !didTryStorefrontResolve && Date().timeIntervalSince(start) >= 3.8 && !name.isEmpty {
                didTryStorefrontResolve = true
                if let sfId = resolveCatalogSongIdInUserStorefrontSync(name: name, artist: artist), sfId != initialId {
                    NSLog("[MusicKitManager] 🔄 Re-staging '%@' with storefront ID %@ (was %@)", name, sfId, initialId)
                    if let loc = resolveLocalizedCatalogSongTitleSync(catalogId: sfId), loc.name != name {
                        localizedTitle = loc.name
                        localizedArtist = loc.artist.isEmpty ? artist : loc.artist
                    }
                    _ = stageCloudSongsInLibrarySync(catalogIds: [sfId])
                    effectiveTimeout = max(effectiveTimeout, Date().timeIntervalSince(start) + 4.5)
                }
            }
        }
        return nil
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
            if let libUrl = URL(string: "https://api.music.apple.com/v1/me/library/playlists?limit=100&l=\(lang)") {
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
                    }), let realId = found["id"] as? String, !realId.isEmpty {
                        let cloudReplayTracks = await getPlaylistTracksById(playlistId: realId)
                        if !cloudReplayTracks.isEmpty {
                            withLock {
                                playlistTracksCache["replay_playlist"] = (timestamp: Date(), tracks: cloudReplayTracks)
                            }
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
                if plId.hasPrefix("pl.") || plId.hasPrefix("p.") {
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

        withLock {
            playlistTracksCache["replay_playlist"] = (timestamp: Date(), tracks: result)
        }
        NSLog("[MusicKitManager] 🎵 Formed hybrid Replay tracks: %d tracks (cloud + local)", result.count)
        return result
    }

    // MARK: - Add Playlist to User Library

    public func addPlaylistToLibrary(playlistId: String) async -> Bool {
        let cleanId = playlistId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else { return false }
        guard let devToken = getDeveloperToken(), let uToken = getUserToken(), !uToken.isEmpty else {
            NSLog("[MusicKitManager] ❌ addPlaylistToLibrary failed: unauthenticated")
            return false
        }

        guard let url = URL(string: "https://api.music.apple.com/v1/me/library?ids[playlists]=\(cleanId)") else {
            return false
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")

        do {
            let (_, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 201 || http.statusCode == 202) else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                NSLog("[MusicKitManager] ❌ Failed to add playlist '%@' to library (status %d)", cleanId, code)
                return false
            }
            NSLog("[MusicKitManager] ✅ Successfully added playlist '%@' to user library", cleanId)

            // Trigger cloud library sync so Music.app picks up the newly added playlist
            if !PlaybackRouter.shared.isTestingEnvironment {
                let pUpd = Process()
                pUpd.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                pUpd.arguments = ["-e", """
                tell application "System Events" to tell process "Music"
                    try
                        set libMenu to menu 1 of (first menu item of menu 1 of menu bar item 3 of menu bar 1 whose name contains "Медиатека" or name contains "Library")
                        click (first menu item of libMenu whose name contains "облачн" or name contains "Cloud")
                    end try
                end tell
                """]
                try? pUpd.run()
                pUpd.waitUntilExit()
            }

            LibraryService.shared.invalidatePlaylistsCache()
            return true
        } catch {
            NSLog("[MusicKitManager] ❌ Error adding playlist to library: %@", error.localizedDescription)
            return false
        }
    }
}
