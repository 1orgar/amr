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
    private var playlistTracksCache: [String: (timestamp: Date, tracks: [TrackInfo])] = [:]
    private var librarySongsCache: (timestamp: Date, tracks: [TrackInfo])?
    private var cachedHomeFeed: [String: Any]?
    private var homeFeedTimestamp: Date?

    private init() {}

    // MARK: - Playlists

    public func getPlaylists() -> [PlaylistInfo] {
        var result = [PlaylistInfo]()
        var seenNames = Set<String>()

        MusicAppProvider.shared.ensureMusicAppRunning()

        // 1. Ultra-fast batch query via AppleScript (queries all playlists in ~0.05s)
        let scriptSrc = """
        tell application "Music"
            set res to {}
            try
                set pList to (every playlist)
                repeat with p in pList
                    try
                        set pName to (name of p as string)
                        set pCount to 0
                        try
                            set pCount to (count of tracks of p)
                        end try
                        set end of res to (pName & "|||" & pCount)
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
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func getPlaylistsWithArtworks() async -> [PlaylistInfo] {
        var baseList = getPlaylists()
        guard !baseList.isEmpty else { return [] }

        await withTaskGroup(of: (String, String).self) { group in
            for pl in baseList {
                if let cached = ArtworkService.shared.getCachedPlaylistArtworkUrl(name: pl.name), !cached.isEmpty {
                    continue
                }

                group.addTask {
                    if let catArt = await MusicKitManager.shared.searchPlaylistArtwork(name: pl.name) {
                        return (pl.name, catArt)
                    }
                    return (pl.name, "")
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
        if let entry = playlistTracksCache[name], Date().timeIntervalSince(entry.timestamp) < 20.0 {
            let cached = entry.tracks
            lock.unlock()
            return cached
        }
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
        if let desc = AppleScriptExecutor.shared.executeDescriptor(scriptSrc), desc.numberOfItems >= 6 {
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
                        if dbId > 0 {
                            if let cached = ArtworkService.shared.getCachedTrackArtwork(id: dbId) {
                                artUrl = "data:image/jpeg;base64,\(cached.base64EncodedString())"
                            } else {
                                artUrl = "/api/artwork/track?id=\(dbId)"
                            }
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

        NSLog("[LibraryService] getPlaylistTracks('%@') returning %d tracks", name, result.count)
        lock.lock()
        playlistTracksCache[name] = (timestamp: Date(), tracks: result)
        lock.unlock()

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
        if let desc = AppleScriptExecutor.shared.executeDescriptor(scriptSrc), desc.numberOfItems >= 6 {
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
        if let entry = librarySongsCache, Date().timeIntervalSince(entry.timestamp) < 30.0 {
            let cached = entry.tracks
            lock.unlock()
            return cached
        }
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
        if let desc = AppleScriptExecutor.shared.executeDescriptor(scriptSrc), desc.numberOfItems >= 6 {
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
                        result.append(TrackInfo(
                            id: "\(dbId)",
                            numericId: dbId,
                            name: tName,
                            artist: tArtist,
                            album: tAlbum,
                            duration: dur,
                            hasArtwork: false,
                            artworkUrl: "",
                            favorited: fav,
                            isLocal: true,
                            index: i
                        ))
                    }
                }
            }

            lock.lock()
            librarySongsCache = (Date(), result)
            lock.unlock()

            return result
        }

        return []
    }

    public func getCachedLibrarySongs() -> [TrackInfo] {
        lock.lock()
        defer { lock.unlock() }
        return librarySongsCache?.tracks ?? []
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
        if let feed = cachedHomeFeed, let ts = homeFeedTimestamp, Date().timeIntervalSince(ts) < 20.0 {
            lock.unlock()
            return feed
        }
        lock.unlock()

        guard let app = MusicAppProvider.shared.getMusicApp() else { return [:] }
        let playlists = app.playlists()
        var allTracks = [[String: Any]]()
        var playlistsList = [[String: Any]]()

        for pObj in playlists {
            guard let p = pObj as? SBObject else { continue }
            let pName = p.sbName
            if pName == "Музыка" || pName == "Music" || pName == "Медиатека" || pName == "Библиотека" {
                if let tracks = p.sbTracks {
                    let total = tracks.count
                    let maxScan = min(total, 120)
                    let startIdx = max(0, total - maxScan)
                    for i in startIdx..<total {
                        guard let t = tracks[i] as? SBObject else { continue }
                        let name = t.sbName
                        let artist = t.sbArtist
                        let album = t.sbAlbum
                        let dur = t.sbDuration
                        let dbId = t.sbDatabaseID

                        if isValidTrack(name: name, artist: artist, duration: dur) {
                            let playedCount = t.sbPlayedCount
                            let playedDate = t.sbPlayedDate?.timeIntervalSince1970 ?? 0
                            let dateAdded = t.sbDateAdded?.timeIntervalSince1970 ?? 0

                            PlaybackStateStore.shared.setTrackMetadata(id: dbId, name: name, artist: artist, album: album)

                            allTracks.append([
                                "id": "\(dbId)",
                                "numeric_id": dbId,
                                "name": name,
                                "artist": artist,
                                "album": album,
                                "duration": dur,
                                "played_count": playedCount,
                                "played_date": playedDate,
                                "date_added": dateAdded,
                                "artwork": "/api/artwork/track?id=\(dbId)",
                                "is_local": true
                            ])
                        }
                    }
                }
            } else if pName != "Медиатека" && pName != "Музыка" && pName != "Music" && pName != "Очередь AMR" {
                let count = p.sbTracks?.count ?? 0
                if count > 0 {
                    let enc = pName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    playlistsList.append([
                        "name": pName,
                        "track_count": count,
                        "artwork": "/api/artwork/playlist?name=\(enc)",
                        "is_playlist": true
                    ])
                }
            }
        }

        // 1. Top Picks (played_count > 0)
        let topCandidates = allTracks.filter { ($0["played_count"] as? Int ?? 0) > 0 }
        let topPicks = topCandidates.sorted { ($0["played_count"] as? Int ?? 0) > ($1["played_count"] as? Int ?? 0) }
        var seenTop = Set<String>()
        var dedupTop = [[String: Any]]()
        for track in topPicks {
            let name = (track["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let artist = (track["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let key = "\(name)|\(artist)"
            if !name.isEmpty && !seenTop.contains(key) {
                seenTop.insert(key)
                dedupTop.append(track)
            }
        }
        let top15 = Array(dedupTop.prefix(15))

        // 2. Recently Played
        let recentCandidates = allTracks.filter { ($0["played_date"] as? Double ?? 0) > 0 }
        let recentlyPlayed = recentCandidates.sorted { ($0["played_date"] as? Double ?? 0) > ($1["played_date"] as? Double ?? 0) }
        var seenRecent = Set<String>()
        var deduplicatedRecent = [[String: Any]]()
        for track in recentlyPlayed {
            let name = (track["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let artist = (track["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let key = "\(name)|\(artist)"
            if !name.isEmpty && !seenRecent.contains(key) {
                seenRecent.insert(key)
                deduplicatedRecent.append(track)
            }
        }
        if deduplicatedRecent.isEmpty {
            for track in allTracks.prefix(30) {
                let name = (track["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let artist = (track["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let key = "\(name)|\(artist)"
                if !name.isEmpty && !seenRecent.contains(key) {
                    seenRecent.insert(key)
                    deduplicatedRecent.append(track)
                }
            }
        }
        let recent15 = Array(deduplicatedRecent.prefix(30))

        // 3. Recently Added
        let recentlyAdded = allTracks.sorted { ($0["date_added"] as? Double ?? 0) > ($1["date_added"] as? Double ?? 0) }
        var seenAdded = Set<String>()
        var dedupAdded = [[String: Any]]()
        for track in recentlyAdded {
            let name = (track["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let artist = (track["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let key = "\(name)|\(artist)"
            if !name.isEmpty && !seenAdded.contains(key) {
                seenAdded.insert(key)
                dedupAdded.append(track)
            }
        }
        let added15 = Array(dedupAdded.prefix(15))

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
                duplicate (first track of current playlist whose database ID is \(tid)) to library playlist 1
                return "ok"
              on error
                try
                  duplicate (first track of library playlist 1 whose database ID is \(tid)) to library playlist 1
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

        if let n = name, let a = artist, !n.isEmpty, !a.isEmpty {
            let escN = n.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let escA = a.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
            tell application "Music"
              try
                duplicate (first track whose name is "\(escN)" and artist is "\(escA)") to library playlist 1
                return "ok"
              on error
                return "error"
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
