//
//  LibraryService+PlaylistTracks.swift
//  AppleMusicRemoteMac
//
//  Playlist tracks retrieval, active playlist inspection, and playlist cache management.
//

import Foundation

extension LibraryService {

    // MARK: - Playlist Tracks

    internal func peekCachedPlaylistTracks(name: String) -> [TrackInfo] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        if let entry = playlistTracksCache[trimmed] {
            return entry.tracks
        }
        if let ciMatch = playlistTracksCache.first(where: { $0.key.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            return ciMatch.value.tracks
        }
        return []
    }

    public func getPlaylistTracks(name: String, limit: Int? = nil) -> [TrackInfo] {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return [] }
        // Never query Music.app playlist tracks for Apple Music Radio station names (e.g. "Моя станция", "Станция открытий")
        if PlayerStatusEngine.isLikelyRadioPlaylistName(trimmedName, activeStationName: nil, isCurrentlyRadio: false),
           !hasCachedUserPlaylist(named: trimmedName) {
            return []
        }
        // Short-circuit favorite-playlist candidate probes when playlists cache is populated and no matching playlist exists
        if Self.favoritePlaylistCandidateNames.contains(trimmedName.lowercased()),
           hasPopulatedPlaylistsCache(),
           !hasCachedUserPlaylist(named: trimmedName) {
            return []
        }

        let cacheKey = limit.map { "\($0 > 0 ? "\(name)#limit:\($0)" : name)" } ?? name
        lock.lock()
        if let fullEntry = playlistTracksCache[name], Date().timeIntervalSince(fullEntry.timestamp) < 600.0 {
            let cached = fullEntry.tracks
            lock.unlock()
            if let maxCount = limit, maxCount > 0 {
                return Array(cached.prefix(maxCount))
            }
            return cached
        }
        if cacheKey != name, let limEntry = playlistTracksCache[cacheKey], Date().timeIntervalSince(limEntry.timestamp) < 600.0 {
            let cached = limEntry.tracks
            lock.unlock()
            return cached
        }
        let plLock = acquirePlaylistFetchLockLocked(for: name)
        lock.unlock()

        plLock.lock()
        defer { plLock.unlock() }

        lock.lock()
        if let fullEntry = playlistTracksCache[name], Date().timeIntervalSince(fullEntry.timestamp) < 600.0 {
            let cached = fullEntry.tracks
            lock.unlock()
            if let maxCount = limit, maxCount > 0 {
                return Array(cached.prefix(maxCount))
            }
            return cached
        }
        if cacheKey != name, let limEntry = playlistTracksCache[cacheKey], Date().timeIntervalSince(limEntry.timestamp) < 600.0 {
            let cached = limEntry.tracks
            lock.unlock()
            return cached
        }
        let staleFallback = playlistTracksCache[name]?.tracks ?? playlistTracksCache[cacheKey]?.tracks
        lock.unlock()

        MusicAppProvider.shared.ensureMusicAppRunning()
        let escapedName = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let rangeExpr: String
        if let maxCount = limit, maxCount > 0 {
            rangeExpr = """
            set endIdx to totalCount
            if endIdx > \(maxCount) then set endIdx to \(maxCount)
            set idList to database ID of tracks 1 thru endIdx of p
            set nList to name of tracks 1 thru endIdx of p
            set aList to artist of tracks 1 thru endIdx of p
            set alList to album of tracks 1 thru endIdx of p
            set dList to duration of tracks 1 thru endIdx of p
            set fList to favorited of tracks 1 thru endIdx of p
            set cList to class of tracks 1 thru endIdx of p
            """
        } else {
            rangeExpr = """
            set idList to database ID of every track of p
            set nList to name of every track of p
            set aList to artist of every track of p
            set alList to album of every track of p
            set dList to duration of every track of p
            set fList to favorited of every track of p
            set cList to class of every track of p
            """
        }

        let scriptSrc = """
        tell application "Music"
            try
                with timeout of 2.5 seconds
                    set p to missing value
                    try
                        set p to playlist "\(escapedName)"
                    end try
                    if p is missing value then
                        repeat with cand in (every playlist)
                            try
                                if (name of cand as string) is "\(escapedName)" then
                                    set p to cand
                                    exit repeat
                                end if
                            end try
                        end repeat
                    end if
                    if p is missing value then return {}
                    set totalCount to count of tracks of p
                    if totalCount = 0 then return {}
                    \(rangeExpr)
                    return {idList, nList, aList, alList, dList, fList, cList}
                end timeout
            on error
                return {}
            end try
        end tell
        """

        var result = [TrackInfo]()
        let rawDesc = AppleScriptExecutor.shared.executeDescriptor(scriptSrc, maxWait: 2.9, reportTimeout: false)
        if let desc = rawDesc, desc.numberOfItems >= 6 {
            let idsDesc = desc.atIndex(1)
            let namesDesc = desc.atIndex(2)
            let artistsDesc = desc.atIndex(3)
            let albumsDesc = desc.atIndex(4)
            let dursDesc = desc.atIndex(5)
            let favsDesc = desc.atIndex(6)
            let classesDesc = desc.numberOfItems >= 7 ? desc.atIndex(7) : nil

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

                    if self.isValidTrack(name: tName, artist: tArtist, duration: dur) {
                        if dbId > 0 {
                            PlaybackStateStore.shared.setTrackMetadata(id: dbId, name: tName, artist: tArtist, album: tAlbum)
                        }

                        var artUrl = ""
                        let encN = tName.amrQueryValueEncoded
                        let encA = tArtist.amrQueryValueEncoded
                        let encAl = tAlbum.amrQueryValueEncoded
                        if let cached = MusicKitManager.shared.getCachedTrackArtwork(name: tName, artist: tArtist, album: tAlbum), !cached.isEmpty {
                            artUrl = cached
                        } else if isFileTrack && dbId > 0 {
                            artUrl = "/api/artwork/track?id=\(dbId)&name=\(encN)&artist=\(encA)&album=\(encAl)"
                        } else if !tName.isEmpty {
                            artUrl = "/api/artwork/search?name=\(encN)&artist=\(encA)&album=\(encAl)"
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
                            isLocal: isFileTrack,
                            index: i
                        ))
                    }
                }
            }
        }

        if rawDesc == nil, let fallback = staleFallback, !fallback.isEmpty {
            NSLog("[LibraryService] getPlaylistTracks('%@') returning %d stale cached tracks after AppleScript contention", name, fallback.count)
            if let maxCount = limit, maxCount > 0 {
                return Array(fallback.prefix(maxCount))
            }
            return fallback
        }

        NSLog("[LibraryService] getPlaylistTracks('%@') returning %d tracks", name, result.count)
        if rawDesc != nil || !result.isEmpty {
            lock.lock()
            playlistTracksCache[cacheKey] = (timestamp: Date(), tracks: result)
            lock.unlock()
        }

        return result
    }

    public func getCurrentPlaylistTracks() -> [TrackInfo] {
        let isStopped = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.lastPlayerStatusCache?.status.playerState == "stopped" }
        if isStopped {
            return []
        }
        MusicAppProvider.shared.ensureMusicAppRunning()
        let scriptSrc = """
        tell application "Music"
            try
                with timeout of 2 seconds
                    if player state is stopped then return {}
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
        let rawDesc = AppleScriptExecutor.shared.executeDescriptor(scriptSrc, maxWait: 2.4, reportTimeout: false)
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

    public func invalidatePlaylistCache(name: String) {
        lock.lock()
        let prefix = "\(name)#limit:"
        for key in Array(playlistTracksCache.keys) where key == name || key.hasPrefix(prefix) {
            playlistTracksCache.removeValue(forKey: key)
        }
        removeUnlockedPlaylistFetchLocksLocked { $0 == name }
        lock.unlock()
    }

    public func updatePlaylistTracksCache(name: String, tracks: [TrackInfo]) {
        lock.lock()
        let prefix = "\(name)#limit:"
        for key in Array(playlistTracksCache.keys) where key.hasPrefix(prefix) {
            playlistTracksCache.removeValue(forKey: key)
        }
        playlistTracksCache[name] = (timestamp: Date(), tracks: tracks)
        lock.unlock()
    }
}
