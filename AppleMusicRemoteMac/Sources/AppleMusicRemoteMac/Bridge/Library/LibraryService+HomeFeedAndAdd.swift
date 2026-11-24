//
//  LibraryService+HomeFeedAndAdd.swift
//  AppleMusicRemoteMac
//
//  Smart personal home feed aggregation and library track addition.
//

import Foundation

extension LibraryService {

    // MARK: - Personal Home Feed

    public func getPersonalHomeFeed() -> [String: Any] {
        lock.lock()
        if let feed = cachedHomeFeed, let ts = homeFeedTimestamp, Date().timeIntervalSince(ts) < 60.0 {
            lock.unlock()
            return feed
        }
        lock.unlock()

        let songs = getLibrarySongs()
        let playlists = getPlaylists()

        let allTracks: [[String: Any]] = songs.suffix(120).map { t in
            let dbId = t.numericId ?? Int(t.id) ?? 0
            return [
                "id": t.id,
                "numeric_id": dbId,
                "name": t.name,
                "artist": t.artist,
                "album": t.album,
                "duration": t.duration,
                "played_count": t.favorited ? 5 : 1,
                "played_date": t.playedDate ?? 0.0,
                "date_added": t.dateAdded ?? 0.0,
                "artwork": t.artworkUrl.isEmpty ? "/api/artwork/track?id=\(dbId)" : t.artworkUrl,
                "is_local": true
            ]
        }

        let playlistsList: [[String: Any]] = playlists.compactMap { p in
            guard p.trackCount > 0 else { return nil }
            let enc = p.name.amrQueryValueEncoded
            return [
                "name": p.name,
                "track_count": p.trackCount,
                "artwork": p.artworkUrl ?? "/api/artwork/playlist?name=\(enc)",
                "is_playlist": true
            ]
        }

        let top15 = Array(allTracks.prefix(15))
        let recent15 = Array(allTracks.suffix(30).reversed())
        let added15 = Array(allTracks.suffix(15).reversed())

        let feed: [String: Any] = [
            "top_picks": top15,
            "recently_played": recent15,
            "playlists_for_you": playlistsList,
            "new_releases": added15
        ]

        lock.lock()
        cachedHomeFeed = feed
        homeFeedTimestamp = Date()
        lock.unlock()

        return feed
    }

    // MARK: - Add To Library

    public func addToLibrary(trackId: Int?, name: String?, artist: String?, url: String?) -> Bool {
        return addToLibrary(
            id: trackId.map { "\($0)" },
            trackId: trackId,
            name: name,
            artist: artist,
            url: url
        )
    }

    public func addToLibrary(id: String?, trackId: Int? = nil, name: String?, artist: String?, url: String?) -> Bool {
        let cleanName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanArtist = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanUrl = url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanIdStr = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // 1. Extract Apple Music catalog song ID (>= 10_000_000) from id, trackId, or url (?i=<songId> or /song/.../<songId>)
        var resolvedCatalogId: String? = nil
        if let num = Int(cleanIdStr), num >= 10_000_000 {
            resolvedCatalogId = cleanIdStr
        } else if let tid = trackId, tid >= 10_000_000 {
            resolvedCatalogId = "\(tid)"
        }
        if resolvedCatalogId == nil && !cleanUrl.isEmpty {
            if let comps = URLComponents(string: cleanUrl),
               let iVal = comps.queryItems?.first(where: { $0.name == "i" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
               let num = Int(iVal), num >= 10_000_000 {
                resolvedCatalogId = iVal
            } else if cleanUrl.contains("/song/") {
                let cleanPath = cleanUrl.components(separatedBy: "?").first ?? cleanUrl
                if let lastSeg = cleanPath.split(separator: "/").last,
                   let num = Int(lastSeg), num >= 10_000_000 {
                    resolvedCatalogId = String(lastSeg)
                }
            }
        }

        var localDbId: Int? = nil
        if let tid = trackId, tid > 0, tid < 10_000_000 {
            localDbId = tid
        } else if let num = Int(cleanIdStr), num > 0, num < 10_000_000 {
            localDbId = num
        }

        let isStagedTemp = localDbId.map { lid in
            PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.stagedTemporaryTrackDbIds.contains(lid) }
        } ?? false

        func duplicateLocalTrackById(_ tid: Int) -> Bool {
            let script = """
            tell application "Music"
              with timeout of 2 seconds
                try
                  duplicate (first track of current playlist whose database ID is \(tid)) to first source
                  return "ok"
                on error
                  try
                    duplicate (first track of current playlist whose database ID is \(tid)) to library playlist 1
                    return "ok"
                  on error
                    try
                      duplicate (first track of library playlist 1 whose database ID is \(tid)) to first source
                      return "ok"
                    on error
                      try
                        duplicate (first track of library playlist 1 whose database ID is \(tid)) to library playlist 1
                        return "ok"
                      on error
                        return "error"
                      end try
                    end try
                  end try
                end try
              end timeout
            end tell
            """
            let (ok, res) = AppleScriptExecutor.shared.execute(script, maxWait: 2.5)
            return ok && res?.trimmingCharacters(in: .whitespacesAndNewlines) == "ok"
        }

        var triedLocalById = false
        if let tid = localDbId, !isStagedTemp, resolvedCatalogId == nil {
            triedLocalById = true
            if duplicateLocalTrackById(tid) {
                PlaybackStateStore.shared.promoteStagedTrackForSavedSong(
                    dbId: tid,
                    catalogId: nil,
                    name: cleanName,
                    artist: cleanArtist
                )
                invalidateLibrarySongsCache()
                return true
            }
        }

        // 2. Authenticated MusicKit catalog song addition (POST /v1/me/library?ids%5Bsongs%5D=...)
        if MusicKitManager.shared.hasUserToken {
            if resolvedCatalogId == nil && !cleanName.isEmpty {
                if let cachedCid = MusicKitManager.shared.getCachedTrackCatalogId(name: cleanName, artist: cleanArtist),
                   let num = Int(cachedCid), num >= 10_000_000 {
                    resolvedCatalogId = cachedCid
                } else if let searchedCid = MusicKitManager.shared.resolveCatalogSongIdInUserStorefrontSync(name: cleanName, artist: cleanArtist),
                          let num = Int(searchedCid), num >= 10_000_000 {
                    resolvedCatalogId = searchedCid
                }
            }
            if let cid = resolvedCatalogId, !cid.isEmpty {
                if MusicKitManager.shared.addSongsToUserLibrarySync(catalogIds: [cid]) {
                    PlaybackStateStore.shared.promoteStagedTrackForSavedSong(
                        dbId: localDbId,
                        catalogId: cid,
                        name: cleanName,
                        artist: cleanArtist
                    )
                    invalidateLibrarySongsCache()
                    return true
                }
            }
        }

        // 3. Fallback: AppleScript duplicate for unauthenticated or local < 10_000_000 tracks
        if let tid = localDbId, !triedLocalById {
            if duplicateLocalTrackById(tid) {
                PlaybackStateStore.shared.promoteStagedTrackForSavedSong(
                    dbId: tid,
                    catalogId: resolvedCatalogId,
                    name: cleanName,
                    artist: cleanArtist
                )
                invalidateLibrarySongsCache()
                return true
            }
        }

        if !cleanName.isEmpty && !cleanArtist.isEmpty {
            let escN = cleanName.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let escA = cleanArtist.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
            tell application "Music"
              with timeout of 2 seconds
                try
                  duplicate (first track whose name is "\(escN)" and artist is "\(escA)") to first source
                  return "ok"
                on error
                  try
                    duplicate (first track whose name is "\(escN)" and artist is "\(escA)") to library playlist 1
                    return "ok"
                  on error
                    return "error"
                  end try
                end try
              end timeout
            end tell
            """
            let (ok, res) = AppleScriptExecutor.shared.execute(script, maxWait: 2.5)
            if ok, res?.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" {
                PlaybackStateStore.shared.promoteStagedTrackForSavedSong(
                    dbId: localDbId,
                    catalogId: resolvedCatalogId,
                    name: cleanName,
                    artist: cleanArtist
                )
                invalidateLibrarySongsCache()
                return true
            }
        }

        if isStagedTemp, let tid = localDbId {
            // Already staged into library playlist 1; promoting out of temporary set keeps it permanently
            PlaybackStateStore.shared.promoteStagedTrackForSavedSong(
                dbId: tid,
                catalogId: resolvedCatalogId,
                name: cleanName,
                artist: cleanArtist
            )
            invalidateLibrarySongsCache()
            return true
        }

        return false
    }
}
