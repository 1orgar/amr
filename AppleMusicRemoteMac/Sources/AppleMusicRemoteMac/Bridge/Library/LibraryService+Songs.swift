//
//  LibraryService+Songs.swift
//  AppleMusicRemoteMac
//
//  Library songs caching, subscription playlist songs, staged buffer cache,
//  local library matching, and top-played tracks.
//

import Foundation

extension LibraryService {

    // MARK: - Library Songs

    internal static func filterOutStagedTracks(_ songs: [TrackInfo], stagedIds: Set<Int>) -> [TrackInfo] {
        guard !stagedIds.isEmpty, !songs.isEmpty else { return songs }
        return songs.filter { song in
            let dbId = song.numericId ?? Int(song.id) ?? 0
            return !(dbId > 0 && stagedIds.contains(dbId))
        }
    }

    internal func fetchRawLibrarySongs(forceRefresh: Bool = false) -> [TrackInfo] {
        if forceRefresh {
            invalidateLibrarySongsCache()
        }

        lock.lock()
        if !forceRefresh, let entry = rawLibrarySongsCache, Date().timeIntervalSince(entry.timestamp) < 300.0 {
            let cached = entry.tracks
            lock.unlock()
            return cached
        }
        lock.unlock()

        librarySongsFetchLock.lock()
        defer { librarySongsFetchLock.unlock() }

        lock.lock()
        if !forceRefresh, let entry = rawLibrarySongsCache, Date().timeIntervalSince(entry.timestamp) < 300.0 {
            let cached = entry.tracks
            lock.unlock()
            return cached
        }
        let staleFallback = rawLibrarySongsCache?.tracks
        lock.unlock()

        let scriptSrc = """
        tell application "Music"
            try
                with timeout of 4 seconds
                    set p to library playlist 1
                    if not (exists p) then
                        set p to playlist 1
                    end if
                    if (count of tracks of p) is 0 then
                        return {"EMPTY"}
                    end if
                    set idList to database ID of tracks of p
                    set nList to name of tracks of p
                    set aList to artist of tracks of p
                    set alList to album of tracks of p
                    set dList to duration of tracks of p
                    set fList to favorited of tracks of p
                    set cList to class of tracks of p
                    try
                        set daList to date added of tracks of p
                        return {idList, nList, aList, alList, dList, fList, cList, daList}
                    on error
                        return {idList, nList, aList, alList, dList, fList, cList}
                    end try
                end timeout
            on error
                return {}
            end try
        end tell
        """

        var result = [TrackInfo]()
        let rawDesc = AppleScriptExecutor.shared.executeDescriptor(scriptSrc, maxWait: 4.5, reportTimeout: false)
        if let desc = rawDesc, desc.numberOfItems == 1, desc.atIndex(1)?.stringValue == "EMPTY" {
            lock.lock()
            rawLibrarySongsCache = (Date(), [])
            librarySongsByNormalizedTitle.removeAll()
            lock.unlock()
            return []
        }
        if let desc = rawDesc, desc.numberOfItems >= 6 {
            let idsDesc = desc.atIndex(1)
            let namesDesc = desc.atIndex(2)
            let artistsDesc = desc.atIndex(3)
            let albumsDesc = desc.atIndex(4)
            let dursDesc = desc.atIndex(5)
            let favsDesc = desc.atIndex(6)
            let classesDesc = desc.numberOfItems >= 7 ? desc.atIndex(7) : nil
            let datesDesc = desc.numberOfItems >= 8 ? desc.atIndex(8) : nil

            let count = namesDesc?.numberOfItems ?? 0
            if count > 0 {
                result.reserveCapacity(count)
                for i in 1...count {
                    let dbId = Int(idsDesc?.atIndex(i)?.int32Value ?? 0)
                    let tName = namesDesc?.atIndex(i)?.stringValue ?? ""
                    let tArtist = artistsDesc?.atIndex(i)?.stringValue ?? ""
                    let tAlbum = albumsDesc?.atIndex(i)?.stringValue ?? ""
                    let dur = dursDesc?.atIndex(i)?.doubleValue ?? 0
                    let fav = favsDesc?.atIndex(i)?.booleanValue ?? false
                    let trackClassCode = classesDesc?.atIndex(i)?.typeCodeValue ?? 0x63466C54 // 'cFlT' = file track
                    let isFileTrack = (trackClassCode == 0x63466C54)
                    let dateAddedVal = datesDesc?.atIndex(i)?.dateValue?.timeIntervalSince1970

                    if isValidTrack(name: tName, artist: tArtist, duration: dur) {
                        if dbId > 0 {
                            PlaybackStateStore.shared.setTrackMetadata(id: dbId, name: tName, artist: tArtist, album: tAlbum)
                        }
                        let encN = tName.amrQueryValueEncoded
                        let encA = tArtist.amrQueryValueEncoded
                        let encAl = tAlbum.amrQueryValueEncoded
                        let artUrl: String
                        if let cached = MusicKitManager.shared.getCachedTrackArtwork(name: tName, artist: tArtist, album: tAlbum), !cached.isEmpty {
                            artUrl = cached
                        } else if isFileTrack && dbId > 0 {
                            artUrl = "/api/artwork/track?id=\(dbId)&name=\(encN)&artist=\(encA)&album=\(encAl)"
                        } else if !tName.isEmpty {
                            artUrl = "/api/artwork/search?name=\(encN)&artist=\(encA)&album=\(encAl)"
                        } else {
                            artUrl = ""
                        }
                        result.append(TrackInfo(
                            id: "\(dbId)",
                            numericId: dbId,
                            name: tName,
                            artist: tArtist,
                            album: tAlbum,
                            duration: dur,
                            hasArtwork: !artUrl.isEmpty,
                            artworkUrl: artUrl,
                            favorited: fav,
                            isLocal: true,
                            dateAdded: dateAddedVal,
                            index: i
                        ))
                    }
                }
            }

            var normMap = [String: [TrackInfo]](minimumCapacity: result.count + 64)
            for song in result {
                let norm = Self.normalizeMatchingTitle(song.name)
                if !norm.isEmpty {
                    normMap[norm, default: []].append(song)
                }
            }

            lock.lock()
            rawLibrarySongsCache = (Date(), result)
            librarySongsByNormalizedTitle = normMap
            lock.unlock()

            return result
        }

        if let fallback = staleFallback, !fallback.isEmpty {
            return fallback
        }
        return []
    }

    public static func upgradeTrackArtworksFromCache(_ songs: [TrackInfo]) -> [TrackInfo] {
        guard !songs.isEmpty else { return songs }
        var out = songs
        for i in out.indices {
            let cur = out[i].artworkUrl
            if !cur.hasPrefix("http") && !cur.hasPrefix("data:") {
                if let cached = MusicKitManager.shared.getCachedTrackArtwork(
                    name: out[i].name,
                    artist: out[i].artist,
                    album: out[i].album
                ), !cached.isEmpty {
                    out[i].artworkUrl = cached
                    out[i].hasArtwork = true
                }
            }
        }
        return out
    }

    public static func upgradeAlbumArtworksFromCache(_ albums: [AlbumInfo]) -> [AlbumInfo] {
        guard !albums.isEmpty else { return albums }
        var out = albums
        for i in out.indices {
            let cur = out[i].artwork
            if !cur.hasPrefix("http") && !cur.hasPrefix("data:") {
                if let cached = MusicKitManager.shared.getCachedAlbumArtwork(
                    album: out[i].name,
                    artist: out[i].artist
                ), !cached.isEmpty {
                    out[i].artwork = cached
                }
            }
        }
        return out
    }

    public func getLibrarySongs(forceRefresh: Bool = false) -> [TrackInfo] {
        let raw = fetchRawLibrarySongs(forceRefresh: forceRefresh)
        let stagedIds = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.stagedTemporaryTrackDbIds }
        let filtered = Self.filterOutStagedTracks(raw, stagedIds: stagedIds)
        return Self.upgradeTrackArtworksFromCache(filtered)
    }

    internal func getSubscriptionPlaylistSongs() -> [TrackInfo] {
        lock.lock()
        if let entry = subscriptionSongsCache, Date().timeIntervalSince(entry.timestamp) < 300.0 {
            let cached = entry.tracks
            lock.unlock()
            return cached
        }
        lock.unlock()

        let scriptSrc = """
        tell application "Music"
            try
                with timeout of 4 seconds
                    set allIds to {}
                    set allNames to {}
                    set allArtists to {}
                    set allAlbums to {}
                    set allDurs to {}
                    repeat with sp in (get every subscription playlist)
                        try
                            set allIds to allIds & (database ID of tracks of sp)
                            set allNames to allNames & (name of tracks of sp)
                            set allArtists to allArtists & (artist of tracks of sp)
                            set allAlbums to allAlbums & (album of tracks of sp)
                            set allDurs to allDurs & (duration of tracks of sp)
                        end try
                    end repeat
                    return {allIds, allNames, allArtists, allAlbums, allDurs}
                end timeout
            on error
                return {}
            end try
        end tell
        """

        var subResult = [TrackInfo]()
        if let desc = AppleScriptExecutor.shared.executeDescriptor(scriptSrc, maxWait: 4.5, reportTimeout: false), desc.numberOfItems >= 5 {
            let idsDesc = desc.atIndex(1)
            let namesDesc = desc.atIndex(2)
            let artistsDesc = desc.atIndex(3)
            let albumsDesc = desc.atIndex(4)
            let dursDesc = desc.atIndex(5)
            let count = namesDesc?.numberOfItems ?? 0
            if count > 0 {
                subResult.reserveCapacity(count)
                for i in 1...count {
                    let dbId = Int(idsDesc?.atIndex(i)?.int32Value ?? 0)
                    let tName = namesDesc?.atIndex(i)?.stringValue ?? ""
                    let tArtist = artistsDesc?.atIndex(i)?.stringValue ?? ""
                    let tAlbum = albumsDesc?.atIndex(i)?.stringValue ?? ""
                    let dur = dursDesc?.atIndex(i)?.doubleValue ?? 0
                    if dbId > 0 && !tName.isEmpty {
                        subResult.append(TrackInfo(
                            id: "\(dbId)",
                            numericId: dbId,
                            name: tName,
                            artist: tArtist,
                            album: tAlbum,
                            duration: dur,
                            hasArtwork: true,
                            artworkUrl: "",
                            favorited: false,
                            isLocal: false,
                            index: i
                        ))
                    }
                }
            }
        }
        lock.lock()
        subscriptionSongsCache = (Date(), subResult)
        lock.unlock()
        return subResult
    }

    public func invalidateLibrarySongsCache() {
        lock.lock()
        rawLibrarySongsCache = nil
        subscriptionSongsCache = nil
        librarySongsByNormalizedTitle.removeAll()
        cachedHomeFeed = nil
        homeFeedTimestamp = nil
        lock.unlock()
    }

    public func purgeDeletedTrackDbIdsFromAllCaches(_ dbIds: Set<Int>) {
        guard !dbIds.isEmpty else { return }
        lock.lock()
        if var cached = rawLibrarySongsCache {
            cached.tracks.removeAll {
                let nid = $0.numericId ?? Int($0.id) ?? 0
                return nid > 0 && dbIds.contains(nid)
            }
            rawLibrarySongsCache = (cached.timestamp, cached.tracks)
        }
        for (normKey, list) in librarySongsByNormalizedTitle {
            let filtered = list.filter { item in
                let nid = item.numericId ?? Int(item.id) ?? 0
                return nid <= 0 || !dbIds.contains(nid)
            }
            if filtered.isEmpty {
                librarySongsByNormalizedTitle.removeValue(forKey: normKey)
            } else if filtered.count != list.count {
                librarySongsByNormalizedTitle[normKey] = filtered
            }
        }
        for (normKey, list) in stagedBufferTracksByNormalizedTitle {
            let filtered = list.filter { item in
                let nid = item.numericId ?? Int(item.id) ?? 0
                return nid <= 0 || !dbIds.contains(nid)
            }
            if filtered.isEmpty {
                stagedBufferTracksByNormalizedTitle.removeValue(forKey: normKey)
            } else if filtered.count != list.count {
                stagedBufferTracksByNormalizedTitle[normKey] = filtered
            }
        }
        lock.unlock()
    }

    public func registerStagedTrackInCache(dbId: Int, name: String, artist: String, album: String = "", duration: Double = 0) {
        guard dbId > 0, !name.isEmpty else { return }
        if !PlaybackStateStore.shared.isTrackPermanentlySaved(id: nil, name: name, artist: artist) {
            PlaybackStateStore.shared.registerStagedTemporaryTrack(dbId: dbId)
        }
        PlaybackStateStore.shared.clearPendingStagedCatalogTrack(catalogId: nil, name: name, artist: artist)
        var resolvedAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        PlaybackStateStore.shared.withLock {
            if resolvedAlbum.isEmpty {
                if let existing = PlaybackStateStore.shared.trackMetadataCache[dbId]?.album, !existing.isEmpty {
                    resolvedAlbum = existing
                } else if let qMatch = PlaybackStateStore.shared.activeCustomQueue.first(where: {
                    $0.numericId == dbId || ($0.name.localizedCaseInsensitiveCompare(name) == .orderedSame && ($0.artist.isEmpty || artist.isEmpty || $0.artist.localizedCaseInsensitiveContains(artist) || artist.localizedCaseInsensitiveContains($0.artist)))
                }), !qMatch.album.isEmpty {
                    resolvedAlbum = qMatch.album
                }
            }
            PlaybackStateStore.shared.setTrackMetadata(id: dbId, name: name, artist: artist, album: resolvedAlbum)
        }
        let encN = name.amrQueryValueEncoded
        let encA = artist.amrQueryValueEncoded
        let encAl = resolvedAlbum.amrQueryValueEncoded
        let artUrl = "/api/artwork/track?id=\(dbId)&name=\(encN)&artist=\(encA)&album=\(encAl)"
        let info = TrackInfo(
            id: "\(dbId)",
            numericId: dbId,
            name: name,
            artist: artist,
            album: resolvedAlbum,
            duration: duration,
            hasArtwork: true,
            artworkUrl: artUrl,
            favorited: false,
            isLocal: false,
            index: 1
        )
        let norm = Self.normalizeMatchingTitle(name)
        guard !norm.isEmpty else { return }
        lock.lock()
        var list = stagedBufferTracksByNormalizedTitle[norm] ?? []
        if !list.contains(where: { $0.numericId == dbId }) {
            list.append(info)
            stagedBufferTracksByNormalizedTitle[norm] = list
        }
        lock.unlock()
    }

    public func clearStagedBufferCache() {
        lock.lock()
        stagedBufferTracksByNormalizedTitle.removeAll()
        lock.unlock()
    }

    public func removeStagedTracksFromCache(dbIds: Set<Int>) {
        guard !dbIds.isEmpty else { return }
        lock.lock()
        for (normKey, list) in stagedBufferTracksByNormalizedTitle {
            let filtered = list.filter { item in
                let nid = item.numericId ?? Int(item.id) ?? 0
                return nid <= 0 || !dbIds.contains(nid)
            }
            if filtered.isEmpty {
                stagedBufferTracksByNormalizedTitle.removeValue(forKey: normKey)
            } else if filtered.count != list.count {
                stagedBufferTracksByNormalizedTitle[normKey] = filtered
            }
        }
        lock.unlock()
    }

    public func resolveLocalLibraryMatches(
        _ tracks: [TrackInfo],
        updateNames: Bool = false,
        includeStagedTemporary: Bool = true
    ) -> [TrackInfo] {
        guard !tracks.isEmpty else { return tracks }
        lock.lock()
        let needsRefresh = rawLibrarySongsCache == nil || Date().timeIntervalSince(rawLibrarySongsCache!.timestamp) >= 300.0
        let normMap = librarySongsByNormalizedTitle
        let bufferMap = includeStagedTemporary ? stagedBufferTracksByNormalizedTitle : [:]
        lock.unlock()
        if needsRefresh && !PlaybackRouter.shared.isTestingEnvironment {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.5) {
                _ = self.fetchRawLibrarySongs()
            }
        }

        let stagedIds: Set<Int> = includeStagedTemporary
            ? []
            : PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.stagedTemporaryTrackDbIds }

        guard !normMap.isEmpty || !bufferMap.isEmpty else {
            if !includeStagedTemporary && !stagedIds.isEmpty {
                return tracks.map { item in
                    var copy = item
                    if let nid = copy.numericId, nid > 0, nid < 10_000_000, stagedIds.contains(nid) {
                        copy.isLocal = false
                    }
                    return copy
                }
            }
            return tracks
        }

        var resolved = tracks
        for i in 0..<resolved.count {
            if !includeStagedTemporary, let existingNid = resolved[i].numericId,
               existingNid > 0, existingNid < 10_000_000, stagedIds.contains(existingNid) {
                resolved[i].isLocal = false
                continue
            }

            let hasCatalogUrl = (resolved[i].url?.isEmpty == false)
            let isCatalogNumericId = (resolved[i].numericId ?? 0) >= 10_000_000 || (Int(resolved[i].id) ?? 0) >= 10_000_000
            if resolved[i].numericId == nil || resolved[i].isLocal != true || hasCatalogUrl || isCatalogNumericId {
                let n = Self.normalizeMatchingTitle(resolved[i].name)
                guard !n.isEmpty else { continue }
                let a = resolved[i].artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

                var matchedTrack: TrackInfo? = nil
                if let candidates = normMap[n] {
                    matchedTrack = candidates.first(where: { cand in
                        if Self.hasConflictingVersionQualifier(resolved[i].name, cand.name) {
                            return false
                        }
                        if !includeStagedTemporary {
                            let cid = cand.numericId ?? Int(cand.id) ?? 0
                            if cid > 0 && stagedIds.contains(cid) {
                                return false
                            }
                        }
                        let la = cand.artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                        if updateNames {
                            return !a.isEmpty && !la.isEmpty && (la == a || la.contains(a) || a.contains(la))
                        } else {
                            return a.isEmpty || la.isEmpty || la.contains(a) || a.contains(la)
                        }
                    })
                }
                if matchedTrack == nil && updateNames && n.count >= 4 {
                    for (sn, candidates) in normMap where sn.count >= 4 && (sn.hasPrefix(n) || n.hasPrefix(sn)) {
                        if let m = candidates.first(where: { cand in
                            if Self.hasConflictingVersionQualifier(resolved[i].name, cand.name) {
                                return false
                            }
                            if !includeStagedTemporary {
                                let cid = cand.numericId ?? Int(cand.id) ?? 0
                                if cid > 0 && stagedIds.contains(cid) {
                                    return false
                                }
                            }
                            let sa = cand.artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                            return !a.isEmpty && !sa.isEmpty && (sa == a || sa.contains(a) || a.contains(sa))
                        }) {
                            matchedTrack = m
                            break
                        }
                    }
                }
                if let match = matchedTrack {
                    if resolved[i].catalogId == nil, AppleSoundCheckService.isValidCatalogId(resolved[i].id) {
                        resolved[i].catalogId = resolved[i].id
                    }
                    resolved[i].numericId = match.numericId
                    resolved[i].isLocal = true
                    if resolved[i].duration <= 0 && match.duration > 0 {
                        resolved[i].duration = match.duration
                    }
                    if updateNames {
                        resolved[i].name = match.name
                        resolved[i].artist = match.artist
                    }
                } else if includeStagedTemporary, let bufCandidates = bufferMap[n],
                          let bufMatch = bufCandidates.first(where: { cand in
                              if Self.hasConflictingVersionQualifier(resolved[i].name, cand.name) {
                                  return false
                              }
                              let ba = cand.artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                              return a.isEmpty || ba.isEmpty || ba.contains(a) || a.contains(ba)
                          }) {
                    if resolved[i].catalogId == nil, AppleSoundCheckService.isValidCatalogId(resolved[i].id) {
                        resolved[i].catalogId = resolved[i].id
                    }
                    resolved[i].numericId = bufMatch.numericId
                    resolved[i].isLocal = false
                    if resolved[i].duration <= 0 && bufMatch.duration > 0 {
                        resolved[i].duration = bufMatch.duration
                    }
                } else if hasCatalogUrl || isCatalogNumericId {
                    resolved[i].isLocal = false
                }
            }
        }
        return resolved
    }

    public func getCachedLibrarySongs() -> [TrackInfo] {
        lock.lock()
        let raw = rawLibrarySongsCache?.tracks ?? []
        lock.unlock()
        let stagedIds = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.stagedTemporaryTrackDbIds }
        return Self.filterOutStagedTracks(raw, stagedIds: stagedIds)
    }

    public func hasConfirmedEmptyLibraryCache() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = rawLibrarySongsCache, Date().timeIntervalSince(entry.timestamp) < 300.0 else {
            return false
        }
        return entry.tracks.isEmpty
    }

    // MARK: - Top Played Tracks (Most Played in Library)

    public func getTopPlayedTracks(limit: Int = 25) -> [TrackInfo] {
        let scriptSrc = """
        tell application "Music"
            try
                with timeout of 4 seconds
                    set p to library playlist 1
                    if not (exists p) then
                        set p to playlist 1
                    end if
                    return {database ID of tracks of p, name of tracks of p, artist of tracks of p, album of tracks of p, duration of tracks of p, played count of tracks of p}
                end timeout
            on error
                return {}
            end try
        end tell
        """

        guard let desc = AppleScriptExecutor.shared.executeDescriptor(scriptSrc, maxWait: 4.5, reportTimeout: false), desc.numberOfItems >= 6 else {
            return Array(getLibrarySongs().prefix(limit))
        }

        let idsDesc = desc.atIndex(1)
        let namesDesc = desc.atIndex(2)
        let artistsDesc = desc.atIndex(3)
        let albumsDesc = desc.atIndex(4)
        let dursDesc = desc.atIndex(5)
        let countsDesc = desc.atIndex(6)

        let total = namesDesc?.numberOfItems ?? 0
        guard total > 0 else { return [] }

        struct Candidate {
            let dbId: Int
            let name: String
            let artist: String
            let album: String
            let duration: Double
            let playedCount: Int
        }

        var candidates = [Candidate]()
        candidates.reserveCapacity(total)

        let stagedIds = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.stagedTemporaryTrackDbIds }

        for i in 1...total {
            let dbId = Int(idsDesc?.atIndex(i)?.int32Value ?? 0)
            if dbId > 0 && stagedIds.contains(dbId) {
                continue
            }
            let tName = namesDesc?.atIndex(i)?.stringValue ?? ""
            let tArtist = artistsDesc?.atIndex(i)?.stringValue ?? ""
            let tAlbum = albumsDesc?.atIndex(i)?.stringValue ?? ""
            let dur = dursDesc?.atIndex(i)?.doubleValue ?? 0
            let pCount = Int(countsDesc?.atIndex(i)?.int32Value ?? 0)

            if isValidTrack(name: tName, artist: tArtist, duration: dur) {
                candidates.append(Candidate(
                    dbId: dbId,
                    name: tName,
                    artist: tArtist,
                    album: tAlbum,
                    duration: dur,
                    playedCount: pCount
                ))
            }
        }

        candidates.sort { $0.playedCount > $1.playedCount }

        var result = [TrackInfo]()
        var seen = Set<String>()

        for c in candidates {
            if result.count >= limit { break }
            let key = "\(c.name.lowercased())|\(c.artist.lowercased())"
            if seen.contains(key) { continue }
            seen.insert(key)

            if c.dbId > 0 {
                PlaybackStateStore.shared.setTrackMetadata(id: c.dbId, name: c.name, artist: c.artist, album: c.album)
            }
            let encN = c.name.amrQueryValueEncoded
            let encA = c.artist.amrQueryValueEncoded
            let encAl = c.album.amrQueryValueEncoded
            let artUrl = (c.dbId > 0) ? "/api/artwork/track?id=\(c.dbId)&name=\(encN)&artist=\(encA)&album=\(encAl)" : ""

            result.append(TrackInfo(
                id: "\(c.dbId)",
                numericId: c.dbId,
                name: c.name,
                artist: c.artist,
                album: c.album,
                duration: c.duration,
                hasArtwork: !artUrl.isEmpty,
                artworkUrl: artUrl,
                favorited: false,
                isLocal: true,
                index: result.count + 1
            ))
        }

        return result
    }
}
