//
//  PlaybackRouter+SearchResults.swift
//  AppleMusicRemoteMac
//

import Foundation
import AppKit

extension PlaybackRouter {
    // MARK: - Custom Tracks & Search Results

    public func playCustomTracks(_ tracks: [TrackInfo], startIndex: Int, shuffle: Bool, queueName: String?) -> Bool {
        guard !tracks.isEmpty else { return false }
        let targetIndex: Int = PlaybackStateStore.shared.withLock {
            let displayName = queueName?.isEmpty == false ? queueName! : "Очередь"
            PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
            PlaybackStateStore.shared.activeCustomQueueName = displayName
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.isRadioPlayback = false
            PlaybackStateStore.shared.isShuffleQueueActive = shuffle

            var finalTracks = LibraryService.shared.resolveLocalLibraryMatches(tracks, updateNames: false)
            var unshuffledFormatted = [TrackInfo]()
            for (idx, var t) in finalTracks.enumerated() {
                t.index = idx + 1
                unshuffledFormatted.append(t)
            }
            PlaybackStateStore.shared.originalCustomQueue = unshuffledFormatted

            var resolvedIdx = 0
            if shuffle {
                if startIndex >= 0 && startIndex < finalTracks.count {
                    let sel = finalTracks.remove(at: startIndex)
                    finalTracks.shuffle()
                    finalTracks.insert(sel, at: 0)
                } else {
                    finalTracks.shuffle()
                }
                resolvedIdx = 0
            } else {
                resolvedIdx = (startIndex >= 0 && startIndex < finalTracks.count) ? startIndex : 0
            }

            var formattedCustom = [TrackInfo]()
            for (idx, var t) in finalTracks.enumerated() {
                t.index = idx + 1
                formattedCustom.append(t)
            }

            PlaybackStateStore.shared.activeCustomQueue = formattedCustom
            PlaybackStateStore.shared.activeCustomQueueIndex = resolvedIdx
            return resolvedIdx
        }
        QueueManager.shared.startQueueMonitoring()
        return QueueManager.shared.playQueueIndexUnlocked(targetIndex)
    }

    public func playCustomTracksUnlocked(_ tracks: [TrackInfo], startIndex: Int, shuffle: Bool, queueName: String?) -> Bool {
        return playCustomTracks(tracks, startIndex: startIndex, shuffle: shuffle, queueName: queueName)
    }

    public func playSearchResults(tracks: [TrackInfo], startIndex: Int = 0, shuffle: Bool, queueName: String? = nil, query: String? = nil, curatorPrompt: String? = nil) async -> Bool {
        guard !tracks.isEmpty else { return false }
        let resolvedQueueName = (queueName?.isEmpty == false) ? queueName! : "Результаты поиска"
        var playList = tracks
        let targetIndex = (startIndex >= 0 && startIndex < playList.count) ? startIndex : 0

        // Resolve any tracks that match in the local library using indexed O(1) normalized matching
        playList = LibraryService.shared.resolveLocalLibraryMatches(tracks, updateNames: true)
        var unshuffledFormatted = [TrackInfo]()
        for (idx, var t) in playList.enumerated() {
            t.index = idx + 1
            unshuffledFormatted.append(t)
        }

        var orderedTracks = playList
        var curTargetIdx = targetIndex
        if shuffle {
            if startIndex >= 0 && startIndex < orderedTracks.count {
                let selected = orderedTracks.remove(at: startIndex)
                orderedTracks.shuffle()
                orderedTracks.insert(selected, at: 0)
            } else {
                orderedTracks.shuffle()
            }
            curTargetIdx = 0
        }

        var formattedQueue = [TrackInfo]()
        for (idx, var t) in orderedTracks.enumerated() {
            t.index = idx + 1
            formattedQueue.append(t)
        }

        // If the starting track is a cloud track (not already in local library cache), stop current playback before transitioning
        if isTestingEnvironment || formattedQueue[curTargetIdx].isLocal != true {
            stopAndClearAMRQueue()
        }
        let curTrack = formattedQueue[curTargetIdx]
        let hasToken = MusicKitManager.shared.hasUserToken

        BitPerfectLogMonitor.shared.resetTrackState()
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isUserPaused = false
            PlaybackStateStore.shared.isRadioPlayback = false
            PlaybackStateStore.shared.activeStationName = nil
            PlaybackStateStore.shared.currentOriginalPlaylistName = (curTrack.isLocal == true || hasToken) ? "Очередь AMR" : nil
            PlaybackStateStore.shared.activeCustomQueueName = resolvedQueueName
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.originalCustomQueue = unshuffledFormatted
            PlaybackStateStore.shared.activeCustomQueue = formattedQueue
            PlaybackStateStore.shared.activeCustomQueueIndex = curTargetIdx
            let cleanCuratorPrompt = curatorPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
            PlaybackStateStore.shared.activeCuratorPrompt = (cleanCuratorPrompt?.isEmpty == false) ? cleanCuratorPrompt : nil
            PlaybackStateStore.shared.isFetchingNextCuratorPage = false
            PlaybackStateStore.shared.activeSearchQuery = (PlaybackStateStore.shared.activeCuratorPrompt != nil) ? nil : query
            PlaybackStateStore.shared.activeSearchCountry = MusicKitManager.shared.getUserStorefront()
            PlaybackStateStore.shared.activeSearchOffset = formattedQueue.count
            PlaybackStateStore.shared.isFetchingNextSearchPage = false
            if curTargetIdx + 1 < formattedQueue.count {
                PlaybackStateStore.shared.latestUpcomingTracks = Array(formattedQueue[(curTargetIdx + 1)...])
            } else {
                PlaybackStateStore.shared.latestUpcomingTracks = []
            }
            if curTargetIdx > 0 {
                PlaybackStateStore.shared.latestHistoryTracks = Array(formattedQueue[0..<curTargetIdx].reversed())
            } else {
                PlaybackStateStore.shared.latestHistoryTracks = []
            }
            PlaybackStateStore.shared.lastCloudPlayTime = Date()
            PlaybackStateStore.shared.lastSkipTime = Date()
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
            PlaybackStateStore.shared.lastKnownPosition = 0.0
            PlaybackStateStore.shared.lastWasPlayingCloud = (curTrack.isLocal != true)
            PlaybackStateStore.shared.isShuffleQueueActive = shuffle
            PlaybackStateStore.shared.activeShuffledQueue.removeAll()
            PlaybackStateStore.shared.playbackQueueCache = nil
        }
        QueueManager.shared.startQueueMonitoring()

        if isTestingEnvironment {
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
            }
            PlaybackStateStore.shared.invalidateQueueCache()
            PlaybackStateStore.shared.invalidateStatusCache()
            WebSocketServer.shared.broadcastStatus(includeQueue: true)
            return true
        }

        // Broadcast updated queue immediately so the UI shows the target album/playlist right away
        PlaybackStateStore.shared.invalidateQueueCache()
        WebSocketServer.shared.broadcastStatus(includeQueue: true)

        // Offload synchronous AppleScript / cloud track staging off Swift's 8-thread cooperative pool
        let started: Bool = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let ok = QueueManager.shared.playQueueIndexUnlocked(curTargetIdx)
                continuation.resume(returning: ok)
            }
        }

        try? await Task.sleep(nanoseconds: 200_000_000)
        PlaybackStateStore.shared.invalidateQueueCache()
        PlaybackStateStore.shared.invalidateStatusCache()
        WebSocketServer.shared.broadcastStatus(includeQueue: true)
        return started
    }

    public func prestageUpcomingCloudTracks(fromIndex: Int, count: Int = 4, expectedGeneration: UInt64? = nil) {
        guard !isTestingEnvironment, MusicKitManager.shared.hasUserToken else { return }
        let (slice, targetGen): ([TrackInfo], UInt64) = PlaybackStateStore.shared.withLock {
            let gen = expectedGeneration ?? PlaybackStateStore.shared.playbackGeneration
            let q = PlaybackStateStore.shared.activeCustomQueue
            guard fromIndex >= 0 && fromIndex < q.count else { return ([], gen) }
            let end = min(q.count, fromIndex + count)
            return (Array(q[fromIndex..<end]).filter { $0.isLocal != true || ($0.numericId ?? 0) >= 10_000_000 }, gen)
        }
        guard !slice.isEmpty else { return }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3.2) {
            let stillSameGen = PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.playbackGeneration == targetGen && !PlaybackStateStore.shared.isStagingCloudTrack
            }
            guard stillSameGen else { return }

            var catalogIds = [String]()
            var seenCatalogIds = Set<String>()
            for t in slice {
                let genCheck = PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.playbackGeneration == targetGen && !PlaybackStateStore.shared.isStagingCloudTrack
                }
                guard genCheck else { return }

                var cid: String? = nil
                if let u = t.url, let comp = URLComponents(string: u),
                   let qi = comp.queryItems?.first(where: { $0.name == "i" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let num = Int(qi), num >= 10_000_000 {
                    cid = qi
                } else {
                    let rawId = t.id.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let num = Int(rawId), num >= 10_000_000 {
                        cid = rawId
                    } else if !t.name.isEmpty, let sfId = MusicKitManager.shared.resolveCatalogSongIdInUserStorefrontSync(name: t.name, artist: t.artist) {
                        cid = sfId
                    }
                }
                if let validCid = cid, !seenCatalogIds.contains(validCid) {
                    seenCatalogIds.insert(validCid)
                    catalogIds.append(validCid)
                }
            }
            guard !catalogIds.isEmpty else { return }
            _ = MusicKitManager.shared.stageCloudSongsInLibrarySync(catalogIds: catalogIds)

            let start = Date()
            var pending = slice
            while !pending.isEmpty && Date().timeIntervalSince(start) < 4.5 {
                Thread.sleep(forTimeInterval: 0.45)
                let genOk = PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.playbackGeneration == targetGen && !PlaybackStateStore.shared.isStagingCloudTrack
                }
                guard genOk else { return }

                var stillPending = [TrackInfo]()
                var resolvedAny = false
                for t in pending {
                    let itemGenOk = PlaybackStateStore.shared.withLock {
                        PlaybackStateStore.shared.playbackGeneration == targetGen && !PlaybackStateStore.shared.isStagingCloudTrack
                    }
                    guard itemGenOk else { return }

                    if let dbId = MusicKitManager.shared.findTrackDatabaseIdInMusicApp(
                        name: t.name,
                        artist: t.artist,
                        checkSubscriptionPlaylists: false
                    ), dbId > 0 {
                        PlaybackStateStore.shared.registerStagedTemporaryTrack(dbId: dbId)
                        LibraryService.shared.registerStagedTrackInCache(
                            dbId: dbId,
                            name: t.name,
                            artist: t.artist,
                            album: t.album,
                            duration: t.duration
                        )
                        PlaybackStateStore.shared.withLock {
                            for i in 0..<PlaybackStateStore.shared.activeCustomQueue.count {
                                let qt = PlaybackStateStore.shared.activeCustomQueue[i]
                                if qt.id == t.id || (qt.name == t.name && qt.artist == t.artist) {
                                    if PlaybackStateStore.shared.activeCustomQueue[i].catalogId == nil,
                                       AppleSoundCheckService.isValidCatalogId(qt.id) {
                                        PlaybackStateStore.shared.activeCustomQueue[i].catalogId = qt.id
                                    }
                                    PlaybackStateStore.shared.activeCustomQueue[i].numericId = dbId
                                    PlaybackStateStore.shared.activeCustomQueue[i].isLocal = true
                                }
                            }
                            let curIdx = PlaybackStateStore.shared.activeCustomQueueIndex
                            let q = PlaybackStateStore.shared.activeCustomQueue
                            if curIdx + 1 < q.count {
                                PlaybackStateStore.shared.latestUpcomingTracks = Array(q[(curIdx + 1)...])
                            }
                        }
                        resolvedAny = true
                    } else {
                        stillPending.append(t)
                    }
                }
                if resolvedAny {
                    PlaybackStateStore.shared.invalidateQueueCache()
                }
                pending = stillPending
            }
        }
    }

    public func appendTracksToAMRQueue(newTracks: [TrackInfo]) async -> Bool {
        guard !newTracks.isEmpty else { return false }
        var updatedQueue = [TrackInfo]()
        var curIdx = 0
        PlaybackStateStore.shared.withLock {
            let existing = PlaybackStateStore.shared.activeCustomQueue
            let existingOrig = PlaybackStateStore.shared.originalCustomQueue
            curIdx = PlaybackStateStore.shared.activeCustomQueueIndex
            let startIdx = existing.count
            var formatted = [TrackInfo]()
            for (offset, var t) in newTracks.enumerated() {
                t.index = startIdx + offset + 1
                formatted.append(t)
            }
            var origFormatted = [TrackInfo]()
            let origStart = existingOrig.count
            for (offset, var t) in newTracks.enumerated() {
                t.index = origStart + offset + 1
                origFormatted.append(t)
            }
            PlaybackStateStore.shared.originalCustomQueue = existingOrig + origFormatted
            if PlaybackStateStore.shared.isShuffleQueueActive {
                formatted.shuffle()
                for i in 0..<formatted.count {
                    formatted[i].index = startIdx + i + 1
                }
            }
            updatedQueue = existing + formatted
            PlaybackStateStore.shared.activeCustomQueue = updatedQueue
            if curIdx + 1 < updatedQueue.count {
                PlaybackStateStore.shared.latestUpcomingTracks = Array(updatedQueue[(curIdx + 1)...])
            }
            PlaybackStateStore.shared.playbackQueueCache = nil
            PlaybackStateStore.shared.activeSearchOffset = updatedQueue.count
            PlaybackStateStore.shared.isFetchingNextSearchPage = false
            PlaybackStateStore.shared.isFetchingNextCuratorPage = false
        }

        PlaybackStateStore.shared.invalidateQueueCache()
        WebSocketServer.shared.broadcastStatus(includeQueue: true)
        NSLog("[PlaybackRouter] ➕ Appended %d tracks to active AMR queue (total: %d)", newTracks.count, updatedQueue.count)
        return true
    }

    public func fetchAndAppendNextCuratorResults(prompt: String) async {
        let (existingTracks, country, targetGen) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.activeCustomQueue,
                PlaybackStateStore.shared.activeSearchCountry ?? MusicKitManager.shared.getUserStorefront(),
                PlaybackStateStore.shared.playbackGeneration
            )
        }
        NSLog("[PlaybackRouter] ♾️ Auto-curating next AI Wave for prompt '%@' (excluding %d existing tracks)", prompt, existingTracks.count)
        let rawWave = await NativeMusicCuratorService.shared.curateNextWaveTracks(
            prompt: prompt,
            storefront: country,
            excluding: existingTracks
        )
        let stillSameSession = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback && PlaybackStateStore.shared.activeCuratorPrompt == prompt
        }
        guard stillSameSession, !rawWave.isEmpty else {
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.isFetchingNextCuratorPage = false
            }
            return
        }
        let resolvedWave = LibraryService.shared.resolveLocalLibraryMatches(rawWave, updateNames: true)
        _ = await appendTracksToAMRQueue(newTracks: resolvedWave)
        let fromIdx = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.activeCustomQueueIndex + 1
        }
        prestageUpcomingCloudTracks(fromIndex: fromIdx, count: 4, expectedGeneration: targetGen)
    }

    public func fetchAndAppendNextSearchResults(query: String) async {
        let (currentCount, country) = PlaybackStateStore.shared.withLock {
            (PlaybackStateStore.shared.activeCustomQueue.count, PlaybackStateStore.shared.activeSearchCountry ?? "ru")
        }
        NSLog("[PlaybackRouter] 🔍 Auto-fetching next search page for '%@' at offset %d", query, currentCount)
        let res = await CloudCatalogService.shared.search(query: query, country: country, source: "all", limit: 25, offset: currentCount)
        guard let songsArray = res["songs"]?.value as? [[String: Any]], !songsArray.isEmpty else {
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.isFetchingNextSearchPage = false
            }
            return
        }

        var newTracks = [TrackInfo]()
        for (idx, item) in songsArray.enumerated() {
            let tid = (item["id"] as? String) ?? "\(currentCount + idx + 1)"
            let numId = (item["numeric_id"] as? Int) ?? (item["numericId"] as? Int)
            let tName = (item["name"] as? String) ?? ""
            let tArtist = (item["artist"] as? String) ?? ""
            let tAlbum = (item["album"] as? String) ?? ""
            let tUrl = item["url"] as? String
            let tArt = (item["artwork_url"] as? String) ?? (item["artwork"] as? String) ?? ""
            let isLoc = (item["is_local"] as? Bool) ?? (item["isLocal"] as? Bool) ?? false
            newTracks.append(TrackInfo(
                id: tid,
                numericId: numId,
                name: tName,
                artist: tArtist,
                album: tAlbum,
                duration: (item["duration"] as? Double) ?? 0,
                hasArtwork: !tArt.isEmpty,
                artworkUrl: tArt,
                favorited: false,
                isLocal: isLoc,
                url: tUrl,
                index: currentCount + idx + 1
            ))
        }
        _ = await appendTracksToAMRQueue(newTracks: newTracks)
    }

    public struct SearchAndPlayResult {
        public let success: Bool
        public let station: String?
        public let query: String?
        public let count: Int?

        public init(success: Bool, station: String? = nil, query: String? = nil, count: Int? = nil) {
            self.success = success
            self.station = station
            self.query = query
            self.count = count
        }
    }

    public func searchAndPlayDetailed(query: String) async -> SearchAndPlayResult {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. If query is empty -> randomly pick one of three stations:
        // "сейчас на повторе", "станция открытий" or "моя станция"
        if q.isEmpty {
            let stations = ["сейчас на повторе", "станция открытий", "моя станция"]
            let chosen = stations.randomElement() ?? "станция открытий"
            let ok: Bool
            switch chosen {
            case "сейчас на повторе":
                ok = playPlaylist(name: "Сейчас на повторе", trackId: nil, trackIndex: nil, shuffle: true)
            case "станция открытий":
                let personal = await MusicKitManager.shared.fetchPersonalStations()
                let discUrl = personal.discovery?.url
                    ?? "https://music.apple.com/station/item/ra.q-GAI6IDk2Yjk1YTAzMWEyZmIwYWExYWJiNzBmZjc1N2FhOTVm"
                ok = await playStation(url: discUrl, name: "Станция открытий")
            case "моя станция":
                let personal = await MusicKitManager.shared.fetchPersonalStations()
                let myUrl = personal.personal?.url
                    ?? "https://music.apple.com/station/my-station/ra.u-96b95a031a2fb0aa1abb70ff757aa95f"
                ok = await playStation(url: myUrl, name: "Моя станция")
            default:
                ok = false
            }
            return SearchAndPlayResult(success: ok, station: chosen, query: nil, count: nil)
        }

        // 2. Query provided -> perform search and play found results sequentially
        // 2a. Unified search across local library and Apple Music cloud catalog (using user's storefront)
        let userSf = MusicKitManager.shared.getUserStorefront()
        let fallbackSf = (userSf == "us") ? "ru" : "us"
        var searchResults = await CloudCatalogService.shared.search(query: q, country: userSf, source: "all")
        var anySongs = (searchResults["songs"]?.value as? [[String: Any]]) ?? []

        // 2b. Storefront fallback if primary storefront returned no songs
        if anySongs.isEmpty {
            searchResults = await CloudCatalogService.shared.search(query: q, country: fallbackSf, source: "all")
            anySongs = (searchResults["songs"]?.value as? [[String: Any]]) ?? []
        }

        // 2c. Offline / AppleScript fallback if online search is unavailable
        if anySongs.isEmpty {
            let escQ = q.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
            tell application "Music"
                try
                    set foundTracks to (every track of library playlist 1 whose name contains "\(escQ)" or artist contains "\(escQ)")
                    set totalCount to count of foundTracks
                    if totalCount > 0 then
                        set idList to ""
                        repeat with i from 1 to totalCount
                            if i > 50 then exit repeat
                            set tr to item i of foundTracks
                            set idList to idList & (database ID of tr as integer) & "||" & (name of tr as string) & "||" & (artist of tr as string) & "||" & (album of tr as string) & "\\n"
                        end repeat
                        return idList
                    end if
                end try
                return "not_found"
            end tell
            """
            let (ok, res) = AppleScriptExecutor.shared.execute(script)
            if ok, let out = res, out != "not_found" {
                let lines = out.components(separatedBy: "\n")
                for line in lines {
                    let parts = line.components(separatedBy: "||")
                    if parts.count >= 4 {
                        let dbId = Int(parts[0]) ?? 0
                        let name = parts[1]
                        let artist = parts[2]
                        let album = parts[3]
                        anySongs.append([
                            "id": "\(dbId)",
                            "numeric_id": dbId,
                            "name": name,
                            "artist": artist,
                            "album": album,
                            "is_local": true
                        ])
                    }
                }
            }
        }

        guard !anySongs.isEmpty else {
            return SearchAndPlayResult(success: false, station: nil, query: q, count: 0)
        }

        // 2d. Build TrackInfo list
        var trackInfos: [TrackInfo] = []
        for (idx, item) in anySongs.prefix(50).enumerated() {
            let tid = (item["id"] as? String) ?? "\(idx + 1)"
            let numId = (item["numeric_id"] as? Int) ?? (item["numericId"] as? Int)
            let tName = (item["name"] as? String) ?? ""
            let tArtist = (item["artist"] as? String) ?? ""
            let tAlbum = (item["album"] as? String) ?? ""
            let tUrl = item["url"] as? String
            let tArt = (item["artwork_url"] as? String) ?? (item["artwork"] as? String) ?? ""
            let isLoc = (item["is_local"] as? Bool) ?? (item["isLocal"] as? Bool) ?? false
            let dur = (item["duration"] as? Double) ?? 0

            guard !tName.isEmpty else { continue }

            trackInfos.append(TrackInfo(
                id: tid,
                numericId: numId,
                name: tName,
                artist: tArtist,
                album: tAlbum,
                duration: dur,
                hasArtwork: !tArt.isEmpty,
                artworkUrl: tArt,
                favorited: false,
                isLocal: isLoc,
                url: tUrl,
                index: idx + 1
            ))
        }

        guard !trackInfos.isEmpty else {
            return SearchAndPlayResult(success: false, station: nil, query: q, count: 0)
        }

        // 2e. Play found results sequentially (shuffle: false)
        let ok = await playSearchResults(tracks: trackInfos, shuffle: false)
        return SearchAndPlayResult(success: ok, station: nil, query: q, count: trackInfos.count)
    }

    public func searchAndPlay(query: String) async -> Bool {
        let res = await searchAndPlayDetailed(query: query)
        return res.success
    }

    @discardableResult
    public func syncCurrentTrackToAMRQueue(clearQueue: Bool = false) -> Bool {
        if isTestingEnvironment {
            return true
        }
        let script = """
        tell application "Music"
            set ct to current track
            if ct is not missing value then
                return "ok||" & (name of ct as string)
            end if
            return "not_found"
        end tell
        """
        let (ok, out) = AppleScriptExecutor.shared.execute(script)
        if ok {
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
            }
            PlaybackStateStore.shared.invalidateQueueCache()
        }
        return ok && (out?.hasPrefix("ok||") == true)
    }
}
