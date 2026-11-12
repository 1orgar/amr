//
//  LibraryService.swift
//  AppleMusicRemoteMac
//
//  Local library inspection: songs, playlists, artists, albums,
//  smart personal home feed aggregation, and library addition.
//

import AppKit
import Foundation
import ScriptingBridge

public final class LibraryService: @unchecked Sendable {
    public static let shared = LibraryService()

    private let lock = NSLock()
    private let playlistsFetchLock = NSLock()
    private let librarySongsFetchLock = NSLock()
    private var playlistFetchLocks: [String: NSLock] = [:]
    private var playlistsCache: (timestamp: Date, playlists: [PlaylistInfo])?
    private var playlistTracksCache: [String: (timestamp: Date, tracks: [TrackInfo])] = [:]
    private var librarySongsCache: (timestamp: Date, tracks: [TrackInfo])?
    private var subscriptionSongsCache: (timestamp: Date, tracks: [TrackInfo])?
    private var librarySongsByNormalizedTitle: [String: [TrackInfo]] = [:]
    private var cachedHomeFeed: [String: Any]?
    private var homeFeedTimestamp: Date?

    private static let removableTitleTags = [
        " (remastered)", " [remastered]", " (remaster)", " [remaster]",
        " (2011 remaster)", " (2013 remaster)", " (deluxe edition)",
        " (deluxe)", " [deluxe]", " (single version)", " (album version)",
        " - single", " - ep"
    ]

    public static func normalizeMatchingTitle(_ t: String) -> String {
        var s = t.lowercased()
        for tag in removableTitleTags {
            if s.contains(tag) {
                s = s.replacingOccurrences(of: tag, with: "")
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private init() {}

    // MARK: - Playlists

    public func getPlaylists(forceRefresh: Bool = false) -> [PlaylistInfo] {
        lock.lock()
        if !forceRefresh, let cached = playlistsCache, Date().timeIntervalSince(cached.timestamp) < 120.0 {
            let list = cached.playlists
            lock.unlock()
            return list
        }
        lock.unlock()

        playlistsFetchLock.lock()
        defer { playlistsFetchLock.unlock() }

        lock.lock()
        if !forceRefresh, let cached = playlistsCache, Date().timeIntervalSince(cached.timestamp) < 120.0 {
            let list = cached.playlists
            lock.unlock()
            return list
        }
        lock.unlock()

        var result = [PlaylistInfo]()
        var seenNames = Set<String>()

        MusicAppProvider.shared.ensureMusicAppRunning()

        // 1. Ultra-fast batch query via AppleScript (queries all playlists in ~0.05s, skipping full-library track counts)
        let scriptSrc = """
        tell application "Music"
            set res to {}
            try
                set pList to (every playlist)
                repeat with p in pList
                    try
                        set pName to (name of p as string)
                        if pName is not in {"Музыка", "Music", "Медиатека", "Библиотека", "Очередь AMR"} then
                            set pCount to 0
                            try
                                set pCount to (count of tracks of p)
                            end try
                            set end of res to (pName & "|||" & pCount)
                        end if
                    end try
                end repeat
            end try
            return res
        end tell
        """

        if let desc = AppleScriptExecutor.shared.executeDescriptor(scriptSrc) {
            let count = desc.numberOfItems
            if count > 0 {
                result.reserveCapacity(count)
                for i in 1...count {
                    if let str = desc.atIndex(i)?.stringValue {
                        let parts = str.components(separatedBy: "|||")
                        if parts.count >= 2 {
                            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                            let trackCount = Int(parts[1]) ?? 0
                            let lower = name.lowercased()
                            if !name.isEmpty, !seenNames.contains(lower),
                               name != "Музыка", name != "Music", name != "Медиатека", name != "Библиотека", name != "Очередь AMR" {
                                seenNames.insert(lower)
                                let enc = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
                                let art = ArtworkService.shared.getCachedPlaylistArtworkUrl(name: name) ?? "/api/artwork/playlist?name=\(enc)&v=2"
                                result.append(PlaylistInfo(name: name, trackCount: trackCount, artworkUrl: art, isPlaylist: true))
                            }
                        }
                    }
                }
            }
        }

        // 2. Fallback to ScriptingBridge if AppleScript returned empty
        if result.isEmpty, let app = MusicAppProvider.shared.getMusicApp() {
            let playlists = app.playlists()
            for p in playlists {
                guard let obj = p as? SBObject else { continue }
                let name = (obj.value(forKey: "name") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let lower = name.lowercased()
                if name.isEmpty || seenNames.contains(lower) ||
                   name == "Музыка" || name == "Music" || name == "Медиатека" || name == "Библиотека" || name == "Очередь AMR" {
                    continue
                }
                let trks = obj.value(forKey: "tracks") as? SBElementArray
                let count = trks?.count ?? 0
                seenNames.insert(lower)
                let enc = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
                let art = ArtworkService.shared.getCachedPlaylistArtworkUrl(name: name) ?? "/api/artwork/playlist?name=\(enc)&v=2"
                result.append(PlaylistInfo(name: name, trackCount: count, artworkUrl: art, isPlaylist: true))
            }
        }

        NSLog("[LibraryService] getPlaylists returning %d playlists", result.count)
        let sorted = result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if !sorted.isEmpty {
            lock.lock()
            playlistsCache = (timestamp: Date(), playlists: sorted)
            lock.unlock()
        }
        return sorted
    }

    public func getPlaylistsWithArtworks() async -> [PlaylistInfo] {
        var baseList = getPlaylists()
        guard !baseList.isEmpty else { return [] }

        await withTaskGroup(of: (String, String).self) { group in
            for pl in baseList {
                if let cached = ArtworkService.shared.getCachedPlaylistArtworkUrl(name: pl.name), !cached.isEmpty {
                    continue
                }

                let playlistName = pl.name
                group.addTask {
                    if let catArt = await MusicKitManager.shared.searchPlaylistArtwork(name: playlistName) {
                        return (playlistName, catArt)
                    }
                    return (playlistName, "")
                }
            }

            for await (plName, artUrl) in group {
                if !artUrl.isEmpty {
                    ArtworkService.shared.setPlaylistArtworkUrl(name: plName, url: artUrl)
                }
            }
        }

        for i in 0..<baseList.count {
            let name = baseList[i].name
            if let art = ArtworkService.shared.getCachedPlaylistArtworkUrl(name: name), !art.isEmpty {
                baseList[i].artworkUrl = art
            } else if baseList[i].artworkUrl?.isEmpty ?? true {
                let enc = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
                baseList[i].artworkUrl = "/api/artwork/playlist?name=\(enc)"
            }
        }

        return baseList
    }

    // MARK: - Playlist Tracks

    public func getPlaylistTracks(name: String) -> [TrackInfo] {
        guard !name.isEmpty else { return [] }
        lock.lock()
        if let entry = playlistTracksCache[name], Date().timeIntervalSince(entry.timestamp) < 120.0 {
            let cached = entry.tracks
            lock.unlock()
            return cached
        }
        let plLock: NSLock
        if let existing = playlistFetchLocks[name] {
            plLock = existing
        } else {
            let newLock = NSLock()
            playlistFetchLocks[name] = newLock
            plLock = newLock
        }
        lock.unlock()

        plLock.lock()
        defer { plLock.unlock() }

        lock.lock()
        if let entry = playlistTracksCache[name], Date().timeIntervalSince(entry.timestamp) < 120.0 {
            let cached = entry.tracks
            lock.unlock()
            return cached
        }
        let staleFallback = playlistTracksCache[name]?.tracks
        lock.unlock()

        MusicAppProvider.shared.ensureMusicAppRunning()
        let escapedName = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let scriptSrc = """
        tell application "Music"
            try
                with timeout of 3 seconds
                    set p to missing value
                    try
                        set p to (first user playlist whose name is "\(escapedName)")
                    on error
                        try
                            set p to playlist "\(escapedName)"
                        on error
                            try
                                set p to (first subscription playlist whose name is "\(escapedName)")
                            on error
                                set p to (first playlist whose name is "\(escapedName)")
                            end try
                        end try
                    end try
                    if p is missing value then return {}
                    set idList to database ID of every track of p
                    set nList to name of every track of p
                    set aList to artist of every track of p
                    set alList to album of every track of p
                    set dList to duration of every track of p
                    set fList to favorited of every track of p
                    return {idList, nList, aList, alList, dList, fList}
                end timeout
            on error
                return {}
            end try
        end tell
        """

        var result = [TrackInfo]()
        let rawDesc = AppleScriptExecutor.shared.executeDescriptor(scriptSrc)
        if let desc = rawDesc, desc.numberOfItems >= 6 {
            let idsDesc = desc.atIndex(1)
            let namesDesc = desc.atIndex(2)
            let artistsDesc = desc.atIndex(3)
            let albumsDesc = desc.atIndex(4)
            let dursDesc = desc.atIndex(5)
            let favsDesc = desc.atIndex(6)

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

                    if self.isValidTrack(name: tName, artist: tArtist, duration: dur) {
                        if dbId > 0 {
                            PlaybackStateStore.shared.setTrackMetadata(id: dbId, name: tName, artist: tArtist, album: tAlbum)
                        }

                        var artUrl = ""
                        if dbId > 0 {
                            let encN = tName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            let encA = tArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            let encAl = tAlbum.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            artUrl = "/api/artwork/track?id=\(dbId)&name=\(encN)&artist=\(encA)&album=\(encAl)"
                        } else if let cached = MusicKitManager.shared.getCachedTrackArtwork(name: tName, artist: tArtist, album: tAlbum), !cached.isEmpty {
                            artUrl = cached
                        } else if let local = ArtworkService.shared.findLocalTrackArtwork(name: tName, artist: tArtist), !local.isEmpty {
                            artUrl = local
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
                            index: i
                        ))
                    }
                }
            }
        }

        if rawDesc == nil, let fallback = staleFallback, !fallback.isEmpty {
            NSLog("[LibraryService] getPlaylistTracks('%@') returning %d stale cached tracks after AppleScript contention", name, fallback.count)
            return fallback
        }

        NSLog("[LibraryService] getPlaylistTracks('%@') returning %d tracks", name, result.count)
        if rawDesc != nil || !result.isEmpty {
            lock.lock()
            playlistTracksCache[name] = (timestamp: Date(), tracks: result)
            lock.unlock()
        }

        return result
    }

    public func getCurrentPlaylistTracks() -> [TrackInfo] {
        guard let app = MusicAppProvider.shared.getMusicApp(), app.playerState != .stopped, app.currentTrack != nil else {
            return []
        }
        MusicAppProvider.shared.ensureMusicAppRunning()
        let scriptSrc = """
        tell application "Music"
            try
                with timeout of 2 seconds
                    if not (exists current playlist) then return {}
                    set p to current playlist
                    set totalCount to count of tracks of p
                    if totalCount = 0 or totalCount > 300 then return {}
                    set idList to database ID of every track of p
                    set nList to name of every track of p
                    set aList to artist of every track of p
                    set alList to album of every track of p
                    set dList to duration of every track of p
                    set fList to favorited of every track of p
                    return {idList, nList, aList, alList, dList, fList}
                end timeout
            on error
                return {}
            end try
        end tell
        """

        var result = [TrackInfo]()
        let rawDesc = AppleScriptExecutor.shared.executeDescriptor(scriptSrc)
        if let desc = rawDesc, desc.numberOfItems >= 6 {
            let idsDesc = desc.atIndex(1)
            let namesDesc = desc.atIndex(2)
            let artistsDesc = desc.atIndex(3)
            let albumsDesc = desc.atIndex(4)
            let dursDesc = desc.atIndex(5)
            let favsDesc = desc.atIndex(6)

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

                    if self.isValidTrack(name: tName, artist: tArtist, duration: dur) {
                        var artUrl = ""
                        if let cached = MusicKitManager.shared.getCachedTrackArtwork(name: tName, artist: tArtist), !cached.isEmpty {
                            artUrl = cached
                        } else if let local = ArtworkService.shared.findLocalTrackArtwork(name: tName, artist: tArtist), !local.isEmpty {
                            artUrl = local
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
                            index: i
                        ))
                    }
                }
            }
        }
        return result
    }

    public func invalidatePlaylistsCache() {
        lock.lock()
        playlistsCache = nil
        lock.unlock()
    }

    public func invalidatePlaylistCache(name: String) {
        lock.lock()
        playlistTracksCache.removeValue(forKey: name)
        lock.unlock()
    }

    public func updatePlaylistTracksCache(name: String, tracks: [TrackInfo]) {
        lock.lock()
        playlistTracksCache[name] = (timestamp: Date(), tracks: tracks)
        lock.unlock()
    }

    // MARK: - Library Songs

    public func getLibrarySongs() -> [TrackInfo] {
        lock.lock()
        if let entry = librarySongsCache, Date().timeIntervalSince(entry.timestamp) < 300.0 {
            let cached = entry.tracks
            lock.unlock()
            return cached
        }
        lock.unlock()

        librarySongsFetchLock.lock()
        defer { librarySongsFetchLock.unlock() }

        lock.lock()
        if let entry = librarySongsCache, Date().timeIntervalSince(entry.timestamp) < 300.0 {
            let cached = entry.tracks
            lock.unlock()
            return cached
        }
        let staleFallback = librarySongsCache?.tracks
        lock.unlock()

        let scriptSrc = """
        tell application "Music"
            try
                with timeout of 4 seconds
                    set p to playlist "Музыка"
                    if not (exists p) then
                        set p to playlist 1
                    end if
                    return {database ID of tracks of p, name of tracks of p, artist of tracks of p, album of tracks of p, duration of tracks of p, favorited of tracks of p}
                end timeout
            on error
                return {}
            end try
        end tell
        """

        var result = [TrackInfo]()
        let rawDesc = AppleScriptExecutor.shared.executeDescriptor(scriptSrc)
        if let desc = rawDesc, desc.numberOfItems >= 6 {
            let idsDesc = desc.atIndex(1)
            let namesDesc = desc.atIndex(2)
            let artistsDesc = desc.atIndex(3)
            let albumsDesc = desc.atIndex(4)
            let dursDesc = desc.atIndex(5)
            let favsDesc = desc.atIndex(6)

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

                    if isValidTrack(name: tName, artist: tArtist, duration: dur) {
                        if dbId > 0 {
                            PlaybackStateStore.shared.setTrackMetadata(id: dbId, name: tName, artist: tArtist, album: tAlbum)
                        }
                        let encN = tName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        let encA = tArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        let encAl = tAlbum.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        let artUrl = (dbId > 0) ? "/api/artwork/track?id=\(dbId)&name=\(encN)&artist=\(encA)&album=\(encAl)" : ""
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
                            index: i
                        ))
                    }
                }
            }

            var normMap = [String: [TrackInfo]](minimumCapacity: result.count + 256)
            for song in result {
                let norm = Self.normalizeMatchingTitle(song.name)
                if !norm.isEmpty {
                    normMap[norm, default: []].append(song)
                }
            }

            let cachedSubSongs: [TrackInfo] = {
                lock.lock()
                defer { lock.unlock() }
                return subscriptionSongsCache?.tracks ?? []
            }()
            for song in cachedSubSongs {
                let norm = Self.normalizeMatchingTitle(song.name)
                if !norm.isEmpty {
                    normMap[norm, default: []].append(song)
                }
            }

            lock.lock()
            librarySongsCache = (Date(), result)
            librarySongsByNormalizedTitle = normMap
            lock.unlock()

            return result
        }

        if let fallback = staleFallback, !fallback.isEmpty {
            return fallback
        }
        return []
    }

    private func getSubscriptionPlaylistSongs() -> [TrackInfo] {
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
        if let desc = AppleScriptExecutor.shared.executeDescriptor(scriptSrc), desc.numberOfItems >= 5 {
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
                            isLocal: true,
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
        librarySongsCache = nil
        subscriptionSongsCache = nil
        lock.unlock()
    }

    public func registerStagedTrackInCache(dbId: Int, name: String, artist: String, album: String = "", duration: Double = 0) {
        guard dbId > 0, !name.isEmpty else { return }
        let encN = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encA = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encAl = album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let artUrl = "/api/artwork/track?id=\(dbId)&name=\(encN)&artist=\(encA)&album=\(encAl)"
        let info = TrackInfo(
            id: "\(dbId)",
            numericId: dbId,
            name: name,
            artist: artist,
            album: album,
            duration: duration,
            hasArtwork: true,
            artworkUrl: artUrl,
            favorited: false,
            isLocal: true,
            index: 1
        )
        let norm = Self.normalizeMatchingTitle(name)
        lock.lock()
        if var cached = librarySongsCache {
            if !cached.tracks.contains(where: { $0.numericId == dbId }) {
                cached.tracks.append(info)
                librarySongsCache = (cached.timestamp, cached.tracks)
            }
        }
        if !norm.isEmpty {
            var list = librarySongsByNormalizedTitle[norm] ?? []
            if !list.contains(where: { $0.numericId == dbId }) {
                list.append(info)
                librarySongsByNormalizedTitle[norm] = list
            }
        }
        lock.unlock()
    }

    public func resolveLocalLibraryMatches(_ tracks: [TrackInfo], updateNames: Bool = false) -> [TrackInfo] {
        guard !tracks.isEmpty else { return tracks }
        lock.lock()
        let needsRefresh = librarySongsCache == nil || Date().timeIntervalSince(librarySongsCache!.timestamp) >= 300.0
        let normMap = librarySongsByNormalizedTitle
        lock.unlock()
        if needsRefresh && !PlaybackRouter.shared.isTestingEnvironment {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.5) {
                _ = self.getLibrarySongs()
            }
        }
        guard !normMap.isEmpty else { return tracks }

        var resolved = tracks
        for i in 0..<resolved.count {
            let hasCatalogUrl = (resolved[i].url?.isEmpty == false)
            let isCatalogNumericId = (resolved[i].numericId ?? 0) >= 10_000_000 || (Int(resolved[i].id) ?? 0) >= 10_000_000
            if resolved[i].numericId == nil || resolved[i].isLocal != true || hasCatalogUrl || isCatalogNumericId {
                let n = Self.normalizeMatchingTitle(resolved[i].name)
                guard !n.isEmpty else { continue }
                let a = resolved[i].artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

                var matchedTrack: TrackInfo? = nil
                if let candidates = normMap[n] {
                    matchedTrack = candidates.first(where: {
                        let la = $0.artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                        if updateNames {
                            return !a.isEmpty && !la.isEmpty && (la == a || la.contains(a) || a.contains(la))
                        } else {
                            return a.isEmpty || la.isEmpty || la.contains(a) || a.contains(la)
                        }
                    })
                }
                if matchedTrack == nil && updateNames && n.count >= 4 {
                    for (sn, candidates) in normMap where sn.count >= 4 && (sn.hasPrefix(n) || n.hasPrefix(sn)) {
                        if let m = candidates.first(where: {
                            let sa = $0.artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
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
                } else if hasCatalogUrl || isCatalogNumericId {
                    resolved[i].isLocal = false
                }
            }
        }
        return resolved
    }

    public func getCachedLibrarySongs() -> [TrackInfo] {
        lock.lock()
        defer { lock.unlock() }
        return librarySongsCache?.tracks ?? []
    }

    // MARK: - Top Played Tracks (Most Played in Library)

    public func getTopPlayedTracks(limit: Int = 25) -> [TrackInfo] {
        let scriptSrc = """
        tell application "Music"
            try
                with timeout of 4 seconds
                    set p to playlist "Музыка"
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

        guard let desc = AppleScriptExecutor.shared.executeDescriptor(scriptSrc), desc.numberOfItems >= 6 else {
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

        for i in 1...total {
            let dbId = Int(idsDesc?.atIndex(i)?.int32Value ?? 0)
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
            let encN = c.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let encA = c.artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let encAl = c.album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
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

    // MARK: - Artists & Albums

    public func getLibraryArtists() -> [ArtistInfo] {
        guard let app = MusicAppProvider.shared.getMusicApp() else { return [] }
        let playlists = app.playlists()
        var artistSet = Set<String>()
        var result = [ArtistInfo]()

        for p in playlists {
            guard let obj = p as? SBObject, let pName = obj.value(forKey: "name") as? String else { continue }
            if pName == "Музыка" || pName == "Music" || pName == "Медиатека" || pName == "Библиотека" {
                if let tracks = obj.value(forKey: "tracks") as? SBElementArray {
                    for tObj in tracks {
                        guard let t = tObj as? SBObject else { continue }
                        let artist = t.value(forKey: "artist") as? String ?? ""
                        let name = t.value(forKey: "name") as? String ?? ""
                        let dur = t.value(forKey: "duration") as? Double ?? 0
                        if !artist.isEmpty && isValidTrack(name: name, artist: artist, duration: dur) && !artistSet.contains(artist) {
                            artistSet.insert(artist)
                            result.append(ArtistInfo(name: artist))
                        }
                    }
                }
                break
            }
        }

        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func getLibraryAlbums() -> [AlbumInfo] {
        guard let app = MusicAppProvider.shared.getMusicApp() else { return [] }
        let playlists = app.playlists()
        var albumDict = [String: AlbumInfo]()

        for p in playlists {
            guard let obj = p as? SBObject, let pName = obj.value(forKey: "name") as? String else { continue }
            if pName == "Музыка" || pName == "Music" || pName == "Медиатека" || pName == "Библиотека" {
                if let tracks = obj.value(forKey: "tracks") as? SBElementArray {
                    for tObj in tracks {
                        guard let t = tObj as? SBObject else { continue }
                        let album = t.value(forKey: "album") as? String ?? ""
                        let artist = t.value(forKey: "artist") as? String ?? ""
                        let dur = t.value(forKey: "duration") as? Double ?? 0
                        let dbId = t.value(forKey: "databaseID") as? Int ?? 0
                        let name = t.value(forKey: "name") as? String ?? ""

                        if !album.isEmpty && isValidTrack(name: name, artist: artist, duration: dur) {
                            let key = "\(album.lowercased())___\(artist.lowercased())"
                            if var existing = albumDict[key] {
                                existing.trackCount = (existing.trackCount ?? 0) + 1
                                albumDict[key] = existing
                            } else {
                                albumDict[key] = AlbumInfo(
                                    id: "\(dbId)",
                                    name: album,
                                    artist: artist,
                                    artwork: "",
                                    trackCount: 1
                                )
                            }
                        }
                    }
                }
                break
            }
        }

        return Array(albumDict.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

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
                "played_date": 0.0,
                "date_added": 0.0,
                "artwork": t.artworkUrl.isEmpty ? "/api/artwork/track?id=\(dbId)" : t.artworkUrl,
                "is_local": true
            ]
        }

        let playlistsList: [[String: Any]] = playlists.compactMap { p in
            guard p.trackCount > 0 else { return nil }
            let enc = p.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
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
        if let tid = trackId, tid > 0 {
            let script = """
            tell application "Music"
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
            end tell
            """
            let (ok, res) = AppleScriptExecutor.shared.execute(script)
            if ok, res == "ok" { return true }
        }

        if let n = name, let a = artist, !n.isEmpty, !a.isEmpty {
            let escN = n.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let escA = a.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
            tell application "Music"
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
            end tell
            """
            let (ok, res) = AppleScriptExecutor.shared.execute(script)
            if ok, res == "ok" { return true }
        }

        return false
    }

    public func isValidTrack(name: String, artist: String, duration: Double) -> Bool {
        if name.isEmpty || duration <= 0 { return false }
        if name.allSatisfy({ $0.isNumber }) { return false }
        if name.hasSuffix(".mkv.m3u") || name.hasSuffix(".m3u") { return false }
        return true
    }
}
