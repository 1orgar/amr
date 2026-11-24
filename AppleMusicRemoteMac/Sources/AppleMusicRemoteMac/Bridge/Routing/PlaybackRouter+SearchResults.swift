//
//  PlaybackRouter+SearchResults.swift
//  AppleMusicRemoteMac
//
//  Custom queue playback, search result queue launching, infinite wave paging, and search-and-play.
//

import AppKit
import Foundation

extension PlaybackRouter {
    // MARK: - Custom Tracks & Search Results

    func applyShuffleOrdering(_ tracks: inout [TrackInfo], pinnedStartIndex: Int) {
        guard tracks.count > 1 else { return }
        if pinnedStartIndex >= 0 && pinnedStartIndex < tracks.count {
            let selected = tracks.remove(at: pinnedStartIndex)
            tracks.shuffle()
            tracks.insert(selected, at: 0)
            return
        }
        let currentFav = PlayerStatusEngine.shared.currentFavoritedState()
        let currentTitle = currentFav.name.trimmingCharacters(in: .whitespacesAndNewlines)
        tracks.shuffle()
        if !currentTitle.isEmpty && tracks.count > 1 &&
            tracks[0].name.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(currentTitle) == .orderedSame {
            let swapIdx = Int.random(in: 1..<tracks.count)
            tracks.swapAt(0, swapIdx)
        }
    }

    public func playCustomTracks(_ tracks: [TrackInfo], startIndex: Int, shuffle: Bool, queueName: String?) -> Bool {
        guard !tracks.isEmpty else { return false }
        var finalTracks = LibraryService.shared.resolveLocalLibraryMatches(tracks, updateNames: false, includeStagedTemporary: false)
        let currentPlayingTitle: String = {
            let fav = PlayerStatusEngine.shared.currentFavoritedState()
            return fav.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }()
        let prevLiveTrack: TrackInfo? = PlaybackStateStore.shared.withLock {
            if let cached = PlaybackStateStore.shared.lastPlayerStatusCache?.status.track, !cached.name.isEmpty {
                return cached
            }
            let oldQ = PlaybackStateStore.shared.activeCustomQueue
            let oldIdx = PlaybackStateStore.shared.activeCustomQueueIndex
            if oldIdx >= 0 && oldIdx < oldQ.count {
                return oldQ[oldIdx]
            }
            return nil
        }
        let targetIndex: Int = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.playbackGeneration &+= 1
            PlaybackStateStore.shared.isStagingCloudTrack = false
            PlaybackStateStore.shared.isActivelyStagingInBuffer = false
            PlaybackStateStore.shared.isUserPaused = false
            let displayName = queueName?.isEmpty == false ? queueName! : "Очередь"
            PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
            PlaybackStateStore.shared.activeCustomQueueName = displayName
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.isRadioPlayback = false
            PlaybackStateStore.shared.activeStationName = (queueName == "Сейчас на повторе") ? "Сейчас на повторе" : nil
            PlaybackStateStore.shared.activeSearchQuery = nil
            PlaybackStateStore.shared.activeSearchOffset = 0
            PlaybackStateStore.shared.isFetchingNextSearchPage = false
            PlaybackStateStore.shared.activeCuratorPrompt = nil
            PlaybackStateStore.shared.isFetchingNextCuratorPage = false
            PlaybackStateStore.shared.isShuffleQueueActive = shuffle
            PlaybackStateStore.shared.repeatOnePinnedTrack = nil
            PlaybackStateStore.shared.lastForeignInterceptTime = .distantPast
            PlaybackStateStore.shared.lastForeignInterceptKey = nil
            PlaybackStateStore.shared.lastConfirmedTrackTime = .distantPast

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
                    if !currentPlayingTitle.isEmpty && finalTracks.count > 1 &&
                        finalTracks[0].name.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(currentPlayingTitle) == .orderedSame {
                        let swapIdx = Int.random(in: 1..<finalTracks.count)
                        finalTracks.swapAt(0, swapIdx)
                    }
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

            let targetTrack = formattedCustom[resolvedIdx]
            PlaybackStateStore.shared.currentOriginalPlaylistName = (targetTrack.isLocal == true || MusicKitManager.shared.hasUserToken) ? "Очередь AMR" : nil
            if let prev = prevLiveTrack,
               !QueueManager.shared.isTrackMatching(expected: targetTrack, candidateName: prev.name, candidateArtist: prev.artist, candidateDbId: prev.numericId) {
                PlaybackStateStore.shared.transitionPreviousTrackKey = QueueManager.shared.canonicalForeignTrackKey(name: prev.name, artist: prev.artist)
            } else {
                PlaybackStateStore.shared.transitionPreviousTrackKey = nil
            }
            PlaybackStateStore.shared.activeTrackTitleVariants = []
            PlaybackStateStore.shared.triedAlternateCloudSeedForCurrentTrack = false
            PlaybackStateStore.shared.alternateCloudSeedAttemptCount = 0
            PlaybackStateStore.shared.triedCloudSeedIdsForCurrentTrack.removeAll()
            PlaybackStateStore.shared.activeCustomQueue = formattedCustom
            PlaybackStateStore.shared.activeCustomQueueIndex = resolvedIdx
            return resolvedIdx
        }
        QueueManager.shared.startQueueMonitoring()
        return QueueManager.shared.playQueueIndexUnlocked(targetIndex, incrementGeneration: false)
    }

    public func playCustomTracksUnlocked(_ tracks: [TrackInfo], startIndex: Int, shuffle: Bool, queueName: String?) -> Bool {
        return playCustomTracks(tracks, startIndex: startIndex, shuffle: shuffle, queueName: queueName)
    }

    public static let genericQueuePlaceholderLabels: Set<String> = [
        "результаты поиска",
        "search results",
        "очередь",
        "очередь amr",
        "amr queue"
    ]

    public static func isGenericQueueLabel(_ raw: String?) -> Bool {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty || genericQueuePlaceholderLabels.contains(trimmed)
    }

    public static func formatSearchQueuePlaylistName(
        query: String?,
        explicitQueueName: String? = nil,
        curatorPrompt: String? = nil,
        preferEnglish: Bool = !MusicKitManager.shared.isSystemLocaleRussian
    ) -> String {
        let cleanExplicit = (explicitQueueName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanExplicit.isEmpty && !isGenericQueueLabel(cleanExplicit) {
            return cleanExplicit
        }
        let cleanQuery = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanQuery.isEmpty {
            return preferEnglish ? "Search: \(cleanQuery)" : "Поиск: \(cleanQuery)"
        }
        let cleanPrompt = (curatorPrompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanPrompt.isEmpty {
            return cleanPrompt.hasPrefix("✨") ? cleanPrompt : "✨ \(cleanPrompt)"
        }
        if !cleanExplicit.isEmpty {
            return cleanExplicit
        }
        return preferEnglish ? "Search Results" : "Результаты поиска"
    }

    public static func resolveSavedQueuePlaylistName(
        explicitName: String?,
        activeQueueName: String?,
        activeSearchQuery: String?,
        activeCuratorPrompt: String?,
        preferEnglish: Bool = !MusicKitManager.shared.isSystemLocaleRussian,
        now: Date = Date()
    ) -> String {
        let cleanExplicit = (explicitName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanExplicit.isEmpty && !isGenericQueueLabel(cleanExplicit) {
            return cleanExplicit
        }
        let cleanActiveQueue = (activeQueueName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanActiveQueue.isEmpty && !isGenericQueueLabel(cleanActiveQueue) {
            return cleanActiveQueue
        }
        let cleanQuery = (activeSearchQuery ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanQuery.isEmpty {
            return preferEnglish ? "Search: \(cleanQuery)" : "Поиск: \(cleanQuery)"
        }
        let cleanPrompt = (activeCuratorPrompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanPrompt.isEmpty {
            return cleanPrompt.hasPrefix("✨") ? cleanPrompt : "✨ \(cleanPrompt)"
        }
        let df = DateFormatter()
        df.dateFormat = "dd.MM"
        let stamp = df.string(from: now)
        return preferEnglish ? "✨ AMR Queue (\(stamp))" : "✨ Очередь AMR (\(stamp))"
    }

    public func playSearchResults(tracks: [TrackInfo], startIndex: Int = 0, shuffle: Bool, queueName: String? = nil, query: String? = nil, curatorPrompt: String? = nil, incrementGeneration: Bool = true) async -> Bool {
        guard !tracks.isEmpty else { return false }
        let resolvedQueueName = Self.formatSearchQueuePlaylistName(
            query: query,
            explicitQueueName: queueName,
            curatorPrompt: curatorPrompt,
            preferEnglish: isTestingEnvironment ? false : !MusicKitManager.shared.isSystemLocaleRussian
        )
        var playList = tracks
        let targetIndex = (startIndex >= 0 && startIndex < playList.count) ? startIndex : 0

        playList = LibraryService.shared.resolveLocalLibraryMatches(tracks, updateNames: true, includeStagedTemporary: false)
        var unshuffledFormatted = [TrackInfo]()
        for (idx, var t) in playList.enumerated() {
            t.index = idx + 1
            unshuffledFormatted.append(t)
        }

        var orderedTracks = playList
        var curTargetIdx = targetIndex
        if shuffle {
            applyShuffleOrdering(&orderedTracks, pinnedStartIndex: startIndex)
            curTargetIdx = 0
        }

        var formattedQueue = [TrackInfo]()
        for (idx, var t) in orderedTracks.enumerated() {
            t.index = idx + 1
            formattedQueue.append(t)
        }

        let (capturedGen, prevLiveTrack): (UInt64, TrackInfo?) = PlaybackStateStore.shared.withLock {
            let prev: TrackInfo? = {
                if let cached = PlaybackStateStore.shared.lastPlayerStatusCache?.status.track, !cached.name.isEmpty {
                    return cached
                }
                let oldQ = PlaybackStateStore.shared.activeCustomQueue
                let oldIdx = PlaybackStateStore.shared.activeCustomQueueIndex
                if oldIdx >= 0 && oldIdx < oldQ.count {
                    return oldQ[oldIdx]
                }
                return nil
            }()
            if incrementGeneration {
                PlaybackStateStore.shared.playbackGeneration &+= 1
            }
            PlaybackStateStore.shared.isStagingCloudTrack = false
            PlaybackStateStore.shared.isActivelyStagingInBuffer = false
            return (PlaybackStateStore.shared.playbackGeneration, prev)
        }

        if isTestingEnvironment || formattedQueue[curTargetIdx].isLocal != true {
            stopAndClearAMRQueue()
        }
        let curTrack = formattedQueue[curTargetIdx]

        BitPerfectLogMonitor.shared.resetTrackState()
        let didApplyState: Bool = PlaybackStateStore.shared.withLock {
            guard PlaybackStateStore.shared.playbackGeneration == capturedGen else {
                return false
            }
            PlaybackStateStore.shared.isStagingCloudTrack = false
            PlaybackStateStore.shared.isActivelyStagingInBuffer = false
            PlaybackStateStore.shared.isUserPaused = false
            PlaybackStateStore.shared.isRadioPlayback = false
            PlaybackStateStore.shared.activeStationName = nil
            PlaybackStateStore.shared.repeatOnePinnedTrack = nil
            if let prev = prevLiveTrack,
               !QueueManager.shared.isTrackMatching(expected: curTrack, candidateName: prev.name, candidateArtist: prev.artist, candidateDbId: prev.numericId) {
                PlaybackStateStore.shared.transitionPreviousTrackKey = QueueManager.shared.canonicalForeignTrackKey(name: prev.name, artist: prev.artist)
            } else {
                PlaybackStateStore.shared.transitionPreviousTrackKey = nil
            }
            PlaybackStateStore.shared.activeTrackTitleVariants = []
            PlaybackStateStore.shared.triedAlternateCloudSeedForCurrentTrack = false
            PlaybackStateStore.shared.alternateCloudSeedAttemptCount = 0
            PlaybackStateStore.shared.triedCloudSeedIdsForCurrentTrack.removeAll()
            PlaybackStateStore.shared.currentOriginalPlaylistName = (curTrack.isLocal == true || MusicKitManager.shared.hasUserToken) ? "Очередь AMR" : nil
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
            PlaybackStateStore.shared.lastConfirmedTrackTime = .distantPast
            PlaybackStateStore.shared.lastForeignInterceptTime = .distantPast
            PlaybackStateStore.shared.lastForeignInterceptKey = nil
            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
            PlaybackStateStore.shared.lastKnownPosition = 0.0
            PlaybackStateStore.shared.lastWasPlayingCloud = (curTrack.isLocal != true)
            PlaybackStateStore.shared.isShuffleQueueActive = shuffle
            PlaybackStateStore.shared.activeShuffledQueue.removeAll()
            PlaybackStateStore.shared.playbackQueueCache = nil
            return true
        }
        guard didApplyState else { return false }
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

        PlaybackStateStore.shared.invalidateQueueCache()
        PlaybackStateStore.shared.invalidateStatusCache()
        WebSocketServer.shared.broadcastStatus(includeQueue: true)

        let started: Bool = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let isCurrentGen = PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.playbackGeneration == capturedGen
                }
                guard isCurrentGen else {
                    continuation.resume(returning: false)
                    return
                }
                let ok = QueueManager.shared.playQueueIndexUnlocked(curTargetIdx, incrementGeneration: false)
                continuation.resume(returning: ok)
            }
        }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.35) {
            let stillCurrentGen = PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.playbackGeneration == capturedGen
            }
            if stillCurrentGen {
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
            }
        }
        return started
    }

    // MARK: - Infinite Wave & Auto-Paging Queue Append

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
            PlaybackStateStore.shared.isCustomQueuePlayback &&
            PlaybackStateStore.shared.playbackGeneration == targetGen &&
            PlaybackStateStore.shared.activeCuratorPrompt == prompt
        }
        guard stillSameSession, !rawWave.isEmpty else {
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.isFetchingNextCuratorPage = false
            }
            return
        }
        let resolvedWave = LibraryService.shared.resolveLocalLibraryMatches(rawWave, updateNames: true, includeStagedTemporary: false)
        _ = await appendTracksToAMRQueue(newTracks: resolvedWave)
        let fromIdx = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.activeCustomQueueIndex + 1
        }
        prestageUpcomingCloudTracks(fromIndex: fromIdx, count: 4, expectedGeneration: targetGen)
    }

    public func fetchAndAppendNextSearchResults(query: String) async {
        let (currentCount, rawCountry, expectedGen) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.activeCustomQueue.count,
                PlaybackStateStore.shared.activeSearchCountry,
                PlaybackStateStore.shared.playbackGeneration
            )
        }
        let country = MusicKitManager.shared.resolveEffectiveStorefront(rawCountry)
        NSLog("[PlaybackRouter] 🔍 Auto-fetching next search page for '%@' at offset %d", query, currentCount)
        let res = await CloudCatalogService.shared.search(query: query, country: country, source: "all", limit: 25, offset: currentCount)
        let stillSameSearch = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback &&
            PlaybackStateStore.shared.playbackGeneration == expectedGen &&
            PlaybackStateStore.shared.activeSearchQuery == query
        }
        guard stillSameSearch, let songsArray = res["songs"]?.value as? [[String: Any]], !songsArray.isEmpty else {
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

    // MARK: - Search and Play

    public struct SearchAndPlayResult {
        public let success: Bool
        public let station: String?
        public let query: String?
        public let count: Int?
        public let expectedGeneration: UInt64

        public init(success: Bool, station: String? = nil, query: String? = nil, count: Int? = nil, expectedGeneration: UInt64 = 0) {
            self.success = success
            self.station = station
            self.query = query
            self.count = count
            self.expectedGeneration = expectedGeneration
        }
    }

    public func searchAndPlayDetailed(query: String) async -> SearchAndPlayResult {
        let expectedGen = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.playbackGeneration }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if q.isEmpty {
            let stations = ["сейчас на повторе", "станция открытий", "моя станция"]
            let chosen = stations.randomElement() ?? "станция открытий"
            let ok: Bool
            switch chosen {
            case "сейчас на повторе":
                ok = playPlaylist(name: "Сейчас на повторе", trackId: nil, trackIndex: nil, shuffle: true)
            case "станция открытий":
                let personal = await MusicKitManager.shared.fetchPersonalStations()
                guard PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.playbackGeneration == expectedGen }) else {
                    return SearchAndPlayResult(success: false, station: chosen, query: nil, count: nil, expectedGeneration: expectedGen)
                }
                let discUrl = personal.discovery?.url ?? ""
                ok = await playStation(url: discUrl, name: "Станция открытий")
            case "моя станция":
                let personal = await MusicKitManager.shared.fetchPersonalStations()
                guard PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.playbackGeneration == expectedGen }) else {
                    return SearchAndPlayResult(success: false, station: chosen, query: nil, count: nil, expectedGeneration: expectedGen)
                }
                let myUrl = personal.personal?.url ?? ""
                ok = await playStation(url: myUrl, name: "Моя станция")
            default:
                ok = false
            }
            return SearchAndPlayResult(success: ok, station: chosen, query: nil, count: nil, expectedGeneration: expectedGen &+ 1)
        }

        let userSf = MusicKitManager.shared.getUserStorefront()
        var searchResults = await CloudCatalogService.shared.search(query: q, country: userSf, source: "all")
        guard PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.playbackGeneration == expectedGen }) else {
            return SearchAndPlayResult(success: false, station: nil, query: q, count: 0, expectedGeneration: expectedGen)
        }
        var anySongs = (searchResults["songs"]?.value as? [[String: Any]]) ?? []

        if anySongs.isEmpty && userSf != "us" {
            searchResults = await CloudCatalogService.shared.search(query: q, country: "us", source: "all")
            guard PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.playbackGeneration == expectedGen }) else {
                return SearchAndPlayResult(success: false, station: nil, query: q, count: 0, expectedGeneration: expectedGen)
            }
            anySongs = (searchResults["songs"]?.value as? [[String: Any]]) ?? []
        }

        if anySongs.isEmpty {
            let escQ = q.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let sep = "||AMR||"
            let script = """
            tell application "Music"
                try
                    with timeout of 2.5 seconds
                        set sep to "\(sep)"
                        set foundTracks to (every track of library playlist 1 whose name contains "\(escQ)" or artist contains "\(escQ)")
                        set totalCount to count of foundTracks
                        if totalCount > 0 then
                            set idList to ""
                            repeat with i from 1 to totalCount
                                if i > 50 then exit repeat
                                set tr to item i of foundTracks
                                set idList to idList & (database ID of tr as integer) & sep & (name of tr as string) & sep & (artist of tr as string) & sep & (album of tr as string) & "\\n"
                            end repeat
                            return idList
                        end if
                    end timeout
                end try
                return "not_found"
            end tell
            """
            let (ok, res) = AppleScriptExecutor.shared.execute(script, maxWait: 3.0)
            if ok, let out = res, out != "not_found" {
                let lines = out.components(separatedBy: "\n")
                for line in lines {
                    let parts = line.components(separatedBy: sep)
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
            return SearchAndPlayResult(success: false, station: nil, query: q, count: 0, expectedGeneration: expectedGen)
        }

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

        guard !trackInfos.isEmpty,
              PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.playbackGeneration == expectedGen }) else {
            return SearchAndPlayResult(success: false, station: nil, query: q, count: 0, expectedGeneration: expectedGen)
        }

        let ok = await playSearchResults(tracks: trackInfos, shuffle: false, query: q)
        return SearchAndPlayResult(success: ok, station: nil, query: q, count: trackInfos.count, expectedGeneration: expectedGen &+ 1)
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
        let sep = "||AMR||"
        let script = """
        tell application "Music"
            with timeout of 1.5 seconds
                set ct to current track
                if ct is not missing value then
                    return "ok\(sep)" & (name of ct as string)
                end if
                return "not_found"
            end timeout
        end tell
        """
        let (ok, out) = AppleScriptExecutor.shared.execute(script, maxWait: 2.0)
        if ok {
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
            }
            PlaybackStateStore.shared.invalidateQueueCache()
        }
        return ok && (out?.hasPrefix("ok" + sep) == true)
    }
}
