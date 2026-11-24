//
//  LibraryService+Removals.swift
//  AppleMusicRemoteMac
//
//  Removal of tracks, albums, artists, and playlists from the library.
//

import Foundation

extension LibraryService {

    // MARK: - Remove From Library (Track / Album / Artist / Playlist)

    internal func deleteLibraryTrackDbIds(_ dbIds: [Int]) -> Int {
        var seen = Set<Int>()
        var uniqueIds: [Int] = []
        for rawId in dbIds where rawId > 0 && rawId < 10_000_000 {
            if seen.insert(rawId).inserted {
                uniqueIds.append(rawId)
            }
        }
        guard !uniqueIds.isEmpty else { return 0 }

        let targetSet = seen

        // Detach matching tracks from active custom / shuffle queues and staged temporary set
        var updatedStagedSnapshot: [Int]? = nil
        var shouldResumeNextQueueTrack = false
        var nextQueueIdxToPlay = 0
        PlaybackStateStore.shared.withLock {
            let store = PlaybackStateStore.shared
            if !store.activeCustomQueue.isEmpty {
                var removedBeforeCurrent = 0
                var removedCurrent = false
                var filteredQueue: [TrackInfo] = []
                filteredQueue.reserveCapacity(store.activeCustomQueue.count)
                for (idx, trk) in store.activeCustomQueue.enumerated() {
                    let tid = trk.numericId ?? Int(trk.id) ?? 0
                    if tid > 0 && targetSet.contains(tid) {
                        if idx < store.activeCustomQueueIndex {
                            removedBeforeCurrent += 1
                        } else if idx == store.activeCustomQueueIndex {
                            removedCurrent = true
                        }
                    } else {
                        filteredQueue.append(trk)
                    }
                }
                if filteredQueue.count != store.activeCustomQueue.count {
                    store.activeCustomQueue = filteredQueue
                    if filteredQueue.isEmpty {
                        store.activeCustomQueueIndex = 0
                        store.isCustomQueuePlayback = false
                        store.isUserPaused = true
                        store.lastKnownPosition = 0.0
                        store.currentTrackPlaybackConfirmed = false
                        store.hasTriggeredAdvanceForCurrentTrack = false
                        store.lastWasPlayingCloud = false
                        store.lastCloudPlayTime = nil
                    } else {
                        let shifted = max(0, store.activeCustomQueueIndex - removedBeforeCurrent)
                        store.activeCustomQueueIndex = min(shifted, filteredQueue.count - 1)
                        if removedCurrent {
                            store.lastKnownPosition = 0.0
                            store.currentTrackPlaybackConfirmed = false
                            store.hasTriggeredAdvanceForCurrentTrack = false
                            store.lastWasPlayingCloud = false
                            store.lastSkipTime = Date()
                            if !store.isUserPaused {
                                shouldResumeNextQueueTrack = true
                                nextQueueIdxToPlay = store.activeCustomQueueIndex
                            }
                        }
                    }
                    let curIdx = store.activeCustomQueueIndex
                    store.latestUpcomingTracks = (curIdx + 1 < filteredQueue.count)
                        ? Array(filteredQueue[(curIdx + 1)...])
                        : []
                    store.playbackQueueCache = nil
                    store.lastPlayerStatusCache = nil
                }
            }
            if !store.originalCustomQueue.isEmpty {
                store.originalCustomQueue.removeAll {
                    let tid = $0.numericId ?? Int($0.id) ?? 0
                    return tid > 0 && targetSet.contains(tid)
                }
            }
            if !store.activeShuffledQueue.isEmpty {
                store.activeShuffledQueue.removeAll {
                    let tid = $0.numericId ?? Int($0.id) ?? 0
                    return tid > 0 && targetSet.contains(tid)
                }
            }
            if !store.stagedTemporaryTrackDbIds.isDisjoint(with: targetSet) {
                store.stagedTemporaryTrackDbIds.subtract(targetSet)
                updatedStagedSnapshot = Array(store.stagedTemporaryTrackDbIds)
            }
            for id in targetSet {
                store.trackMetadataCache.removeValue(forKey: id)
            }
        }

        if let snap = updatedStagedSnapshot, !PlaybackRouter.shared.isTestingEnvironment {
            UserDefaults.standard.set(snap, forKey: "AMRStagedTemporaryTrackDbIds")
        }

        if PlaybackRouter.shared.isTestingEnvironment {
            lock.lock()
            if var cached = rawLibrarySongsCache {
                cached.tracks.removeAll {
                    let tid = $0.numericId ?? Int($0.id) ?? 0
                    return tid > 0 && targetSet.contains(tid)
                }
                rawLibrarySongsCache = (cached.timestamp, cached.tracks)
            }
            for (norm, list) in librarySongsByNormalizedTitle {
                let filtered = list.filter {
                    let tid = $0.numericId ?? Int($0.id) ?? 0
                    return !(tid > 0 && targetSet.contains(tid))
                }
                if filtered.isEmpty {
                    librarySongsByNormalizedTitle.removeValue(forKey: norm)
                } else {
                    librarySongsByNormalizedTitle[norm] = filtered
                }
            }
            cachedHomeFeed = nil
            homeFeedTimestamp = nil
            playlistsCache = nil
            playlistTracksCache.removeAll()
            removeUnlockedPlaylistFetchLocksLocked { _ in true }
            lock.unlock()
            return uniqueIds.count
        }

        MusicAppProvider.shared.ensureMusicAppRunning()

        var totalConfirmedDeleted = 0
        let batchSize = 100
        var startIdx = 0

        while startIdx < uniqueIds.count {
            let endIdx = min(startIdx + batchSize, uniqueIds.count)
            let batch = uniqueIds[startIdx..<endIdx]
            var realDbIds: [Int] = []
            var persistentHexIds: [String] = []
            for id in batch {
                if let hex = ITLibraryReader.shared.persistentIDHex(forTrackId: id) {
                    persistentHexIds.append(hex)
                } else {
                    realDbIds.append(id)
                }
            }
            let idList = realDbIds.map { "\($0)" }.joined(separator: ", ")
            let hexList = persistentHexIds.map { "\"\($0)\"" }.joined(separator: ", ")

            let script = """
            tell application "Music"
                with timeout of 6 seconds
                    if not (exists library playlist 1) then return -1
                    try
                        if player state is not stopped then
                            set curId to database ID of current track
                            set curHex to persistent ID of current track
                            if curId is in {\(idList)} or curHex is in {\(hexList)} then
                                stop
                                repeat with qp in (get every user playlist whose name is "Очередь AMR")
                                    try
                                        delete qp
                                    end try
                                end repeat
                            end if
                        end if
                    end try
                    set deletedCount to 0
                    repeat with tid in {\(idList)}
                        set tVal to (contents of tid)
                        set existedBefore to false
                        try
                            if (count of (every track of library playlist 1 whose database ID is tVal)) > 0 then
                                set existedBefore to true
                            end if
                        end try
                        if existedBefore then
                            try
                                delete (every track of library playlist 1 whose database ID is tVal)
                            end try
                            try
                                if (count of (every track of library playlist 1 whose database ID is tVal)) = 0 then
                                    set deletedCount to deletedCount + 1
                                end if
                            end try
                        end if
                    end repeat
                    repeat with pid in {\(hexList)}
                        set pVal to (contents of pid)
                        set existedBefore to false
                        try
                            if (count of (every track of library playlist 1 whose persistent ID is pVal)) > 0 then
                                set existedBefore to true
                            end if
                        end try
                        if existedBefore then
                            try
                                delete (every track of library playlist 1 whose persistent ID is pVal)
                            end try
                            try
                                if (count of (every track of library playlist 1 whose persistent ID is pVal)) = 0 then
                                    set deletedCount to deletedCount + 1
                                end if
                            end try
                        end if
                    end repeat
                    return deletedCount
                end timeout
            end tell
            """

            if let desc = AppleScriptExecutor.shared.executeDescriptor(script, maxWait: 6.5, reportTimeout: false) {
                let batchDeleted = Int(desc.int32Value)
                if batchDeleted > 0 {
                    totalConfirmedDeleted += batchDeleted
                } else if let strVal = desc.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                          let parsed = Int(strVal), parsed > 0 {
                    totalConfirmedDeleted += parsed
                }
            }
            startIdx = endIdx
        }

        lock.lock()
        rawLibrarySongsCache = nil
        subscriptionSongsCache = nil
        librarySongsByNormalizedTitle.removeAll()
        for (normKey, list) in stagedBufferTracksByNormalizedTitle {
            let filtered = list.filter { item in
                let nid = item.numericId ?? Int(item.id) ?? 0
                return nid <= 0 || !targetSet.contains(nid)
            }
            if filtered.isEmpty {
                stagedBufferTracksByNormalizedTitle.removeValue(forKey: normKey)
            } else if filtered.count != list.count {
                stagedBufferTracksByNormalizedTitle[normKey] = filtered
            }
        }
        cachedHomeFeed = nil
        homeFeedTimestamp = nil
        playlistsCache = nil
        playlistTracksCache.removeAll()
        removeUnlockedPlaylistFetchLocksLocked { _ in true }
        lock.unlock()

        PlaybackStateStore.shared.invalidateStatusCache()
        if shouldResumeNextQueueTrack && !PlaybackRouter.shared.isTestingEnvironment {
            _ = QueueManager.shared.playQueueIndexUnlocked(nextQueueIdxToPlay)
        }
        return totalConfirmedDeleted
    }

    public func removeTrackFromLibrary(
        id: String? = nil,
        trackId: Int? = nil,
        name: String? = nil,
        artist: String? = nil,
        album: String? = nil
    ) -> Int {
        let cleanId = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanArtist = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanAlbum = album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var targetDbIds = Set<Int>()
        if let tid = trackId, tid > 0, tid < 10_000_000 {
            targetDbIds.insert(tid)
        }
        if let pid = Int(cleanId), pid > 0, pid < 10_000_000 {
            targetDbIds.insert(pid)
        }

        if !cleanName.isEmpty {
            let exactFoldedName = cleanName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            let normTargetName = Self.normalizeMatchingTitle(cleanName)
            let normTargetArtist = Self.normalizedArtistName(cleanArtist)
            let hasAlbumFilter = !cleanAlbum.isEmpty

            func collectMatchingDbIds(from songs: [TrackInfo], requireAlbumMatch: Bool) -> [Int] {
                var ids: [Int] = []
                for s in songs {
                    let sDbId = s.numericId ?? Int(s.id) ?? 0
                    guard sDbId > 0, sDbId < 10_000_000 else { continue }
                    let sFoldedName = s.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let nameOk = (sFoldedName == exactFoldedName)
                        || (!normTargetName.isEmpty && Self.normalizeMatchingTitle(s.name) == normTargetName)
                    guard nameOk else { continue }

                    let sNormArtist = Self.normalizedArtistName(s.artist)
                    let artistOk = normTargetArtist.isEmpty
                        || sNormArtist.isEmpty
                        || Self.artistMatchesLibraryTarget(trackArtist: s.artist, targetArtist: cleanArtist)
                        || sNormArtist.contains(normTargetArtist)
                        || normTargetArtist.contains(sNormArtist)
                    guard artistOk else { continue }

                    if requireAlbumMatch && hasAlbumFilter {
                        guard MusicKitManager.albumMatches(s.album, s.artist, cleanAlbum, cleanArtist) else { continue }
                    }
                    ids.append(sDbId)
                }
                return ids
            }

            let rawSongs = fetchRawLibrarySongs()
            var matchedByMeta = collectMatchingDbIds(from: rawSongs, requireAlbumMatch: hasAlbumFilter)
            if matchedByMeta.isEmpty && hasAlbumFilter {
                matchedByMeta = collectMatchingDbIds(from: rawSongs, requireAlbumMatch: false)
            }
            for mid in matchedByMeta {
                targetDbIds.insert(mid)
            }

            if targetDbIds.isEmpty && !PlaybackRouter.shared.isTestingEnvironment {
                if let directDbId = MusicKitManager.shared.findTrackDatabaseIdInMusicApp(
                    name: cleanName,
                    artist: cleanArtist,
                    checkSubscriptionPlaylists: false
                ), directDbId > 0 {
                    targetDbIds.insert(directDbId)
                }
            }
        }

        PlaybackStateStore.shared.removePermanentlySavedTrack(
            id: cleanId.isEmpty ? nil : cleanId,
            name: cleanName.isEmpty ? nil : cleanName,
            artist: cleanArtist.isEmpty ? nil : cleanArtist
        )
        PlaybackStateStore.shared.clearPendingStagedCatalogTrack(
            catalogId: cleanId.isEmpty ? nil : cleanId,
            name: cleanName,
            artist: cleanArtist
        )
        MusicKitManager.shared.invalidateUserLibraryAlbumsCache()

        return deleteLibraryTrackDbIds(Array(targetDbIds))
    }

    public func removeAlbumFromLibrary(albumId: String? = nil, name: String, artist: String = "") -> Int {
        let cleanId = albumId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)

        var targetDbIds = Set<Int>()
        if let aid = Int(cleanId), aid > 0, aid < 10_000_000 {
            targetDbIds.insert(aid)
        }

        func collectAlbumTrackIds(from songs: [TrackInfo]) {
            guard !cleanName.isEmpty else { return }
            for s in songs {
                let sDbId = s.numericId ?? Int(s.id) ?? 0
                guard sDbId > 0, sDbId < 10_000_000 else { continue }
                if MusicKitManager.albumMatches(s.album, s.artist, cleanName, cleanArtist) {
                    targetDbIds.insert(sDbId)
                    PlaybackStateStore.shared.removePermanentlySavedTrack(
                        id: s.catalogId ?? s.id,
                        name: s.name,
                        artist: s.artist
                    )
                }
            }
        }

        collectAlbumTrackIds(from: fetchRawLibrarySongs())
        if targetDbIds.isEmpty && !cleanName.isEmpty && !PlaybackRouter.shared.isTestingEnvironment {
            collectAlbumTrackIds(from: fetchRawLibrarySongs(forceRefresh: true))
        }

        let removedFromRecentCloud = MusicKitManager.shared.removeRecordedAlbumFromLibrary(
            albumId: cleanId.isEmpty ? nil : cleanId,
            name: cleanName,
            artist: cleanArtist
        )
        let deletedCount = deleteLibraryTrackDbIds(Array(targetDbIds))
        return max(deletedCount, removedFromRecentCloud ? 1 : 0)
    }

    public func removeArtistFromLibrary(artist: String) -> Int {
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanArtist.isEmpty else { return 0 }

        var targetDbIds = Set<Int>()
        func collectArtistTrackIds(from songs: [TrackInfo]) {
            for s in songs {
                let sDbId = s.numericId ?? Int(s.id) ?? 0
                guard sDbId > 0, sDbId < 10_000_000 else { continue }
                if Self.artistMatchesLibraryTarget(trackArtist: s.artist, targetArtist: cleanArtist) {
                    targetDbIds.insert(sDbId)
                    PlaybackStateStore.shared.removePermanentlySavedTrack(
                        id: s.catalogId ?? s.id,
                        name: s.name,
                        artist: s.artist
                    )
                }
            }
        }

        collectArtistTrackIds(from: fetchRawLibrarySongs())
        if targetDbIds.isEmpty && !PlaybackRouter.shared.isTestingEnvironment {
            collectArtistTrackIds(from: fetchRawLibrarySongs(forceRefresh: true))
        }

        let removedRecentAlbums = MusicKitManager.shared.removeRecordedAlbumsForArtistFromLibrary(artist: cleanArtist)
        let deletedCount = deleteLibraryTrackDbIds(Array(targetDbIds))
        return max(deletedCount, removedRecentAlbums)
    }

    public func removePlaylistFromLibrary(
        playlistId: String? = nil,
        name: String
    ) async -> Bool {
        let cleanId = playlistId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard (!cleanName.isEmpty || !cleanId.isEmpty),
              !Self.isProtectedSystemPlaylist(cleanName) else {
            return false
        }

        let matchedLocal = findMatchingLocalPlaylist(
            id: cleanId.isEmpty ? nil : cleanId,
            name: cleanName.isEmpty ? nil : cleanName
        )
        var targetNames: [String] = []
        if !cleanName.isEmpty && !Self.isProtectedSystemPlaylist(cleanName) {
            targetNames.append(cleanName)
        }
        if let localName = matchedLocal?.name.trimmingCharacters(in: .whitespacesAndNewlines),
           !localName.isEmpty,
           !Self.isProtectedSystemPlaylist(localName),
           !targetNames.contains(where: { $0.caseInsensitiveCompare(localName) == .orderedSame }) {
            targetNames.append(localName)
        }

        // 1. Delete the playlist itself from Music.app (both user playlists and subscribed Apple Music playlists)
        var localPlaylistDeleted = false
        if !targetNames.isEmpty && !PlaybackRouter.shared.isTestingEnvironment {
            let appleScriptNamesList = targetNames.map { raw in
                let esc = raw
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                return "\"\(esc)\""
            }.joined(separator: ", ")

            let deletePlaylistScript = """
            tell application "Music"
                try
                    with timeout of 5 seconds
                        set deletedPl to 0
                        set targetNames to {\(appleScriptNamesList)}
                        ignoring case
                            repeat with p in (get every user playlist)
                                try
                                    if (special kind of p is none) and (targetNames contains (name of p as string)) then
                                        delete p
                                        set deletedPl to deletedPl + 1
                                    end if
                                end try
                            end repeat
                            repeat with sp in (get every subscription playlist)
                                try
                                    if targetNames contains (name of sp as string) then
                                        delete sp
                                        set deletedPl to deletedPl + 1
                                    end if
                                end try
                            end repeat
                        end ignoring
                        return deletedPl
                    end timeout
                on error
                    return 0
                end try
            end tell
            """
            if let desc = AppleScriptExecutor.shared.executeDescriptor(deletePlaylistScript, maxWait: 5.5, reportTimeout: false) {
                let count = Int(desc.int32Value)
                if count > 0 {
                    localPlaylistDeleted = true
                } else if let s = desc.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                          let parsed = Int(s), parsed > 0 {
                    localPlaylistDeleted = true
                }
            }
        }

        let effectiveDeleteId: String? = {
            if let lid = matchedLocal?.id, lid.lowercased().hasPrefix("p.") {
                return lid
            }
            if !cleanId.isEmpty {
                return cleanId
            }
            return matchedLocal?.catalogId
        }()
        let cloudPlaylistDeleted = await MusicKitManager.shared.deleteUserLibraryPlaylist(
            playlistId: effectiveDeleteId,
            name: matchedLocal?.name ?? cleanName
        )

        var playlistDeleted = localPlaylistDeleted || cloudPlaylistDeleted

        // Clear active custom queue playlist label if it pointed to this playlist
        if !targetNames.isEmpty {
            PlaybackStateStore.shared.withLock {
                if let activeName = PlaybackStateStore.shared.activeCustomQueueName,
                   targetNames.contains(where: { $0.caseInsensitiveCompare(activeName) == .orderedSame }) {
                    PlaybackStateStore.shared.activeCustomQueueName = nil
                }
            }
        }

        // 2. Invalidate playlist caches & prune TV Mode selected playlists if present
        let cachedRemoved: Bool = lock.withLock {
            var hadMatch = false
            let beforeRecent = recentlyAddedPlaylists.count
            recentlyAddedPlaylists.removeAll { entry in
                if targetNames.contains(where: { entry.playlist.name.caseInsensitiveCompare($0) == .orderedSame || Self.playlistsSharePersonalMixAlias(entry.playlist.name, $0) }) {
                    return true
                }
                if !cleanId.isEmpty {
                    if let eId = entry.playlist.id, eId.caseInsensitiveCompare(cleanId) == .orderedSame {
                        return true
                    }
                    if let eCat = entry.playlist.catalogId, eCat.caseInsensitiveCompare(cleanId) == .orderedSame {
                        return true
                    }
                }
                return false
            }
            if recentlyAddedPlaylists.count < beforeRecent {
                hadMatch = true
            }
            if let cachedPls = playlistsCache?.playlists {
                let filtered = cachedPls.filter { pl in
                    if targetNames.contains(where: { pl.name.caseInsensitiveCompare($0) == .orderedSame }) {
                        return false
                    }
                    if !cleanId.isEmpty && (pl.id?.caseInsensitiveCompare(cleanId) == .orderedSame || pl.catalogId?.caseInsensitiveCompare(cleanId) == .orderedSame) {
                        return false
                    }
                    return true
                }
                if filtered.count < cachedPls.count {
                    hadMatch = true
                }
            }
            cloudPlaylistMetadataItems.removeAll { meta in
                if !cleanId.isEmpty && (meta.libraryId.caseInsensitiveCompare(cleanId) == .orderedSame || meta.catalogId?.caseInsensitiveCompare(cleanId) == .orderedSame) {
                    return true
                }
                return meta.names.contains { mName in
                    targetNames.contains { $0.caseInsensitiveCompare(mName) == .orderedSame }
                }
            }
            cloudPlaylistMetaTimestamp = nil
            playlistsCache = nil
            for tName in targetNames {
                let prefix = "\(tName)#limit:"
                for k in Array(playlistTracksCache.keys) where k.caseInsensitiveCompare(tName) == .orderedSame || k.lowercased().hasPrefix(prefix.lowercased()) {
                    playlistTracksCache.removeValue(forKey: k)
                }
                removeUnlockedPlaylistFetchLocksLocked { $0.caseInsensitiveCompare(tName) == .orderedSame }
            }
            cachedHomeFeed = nil
            homeFeedTimestamp = nil
            return hadMatch
        }
        MusicKitManager.shared.invalidateCloudLibraryPlaylistsCache()
        if cachedRemoved {
            playlistDeleted = true
        }

        for tName in targetNames {
            ArtworkService.shared.clearPlaylistArtworkCache(name: tName)
        }
        if !targetNames.isEmpty && !PlaybackRouter.shared.isTestingEnvironment {
            _ = TVLibraryConfigurationStore.shared.update { cfg in
                cfg.selectedPlaylistNames.removeAll { sel in
                    targetNames.contains { $0.caseInsensitiveCompare(sel) == .orderedSame }
                }
            }
        }
        PlaybackStateStore.shared.invalidateStatusCache()

        return playlistDeleted
    }
}
