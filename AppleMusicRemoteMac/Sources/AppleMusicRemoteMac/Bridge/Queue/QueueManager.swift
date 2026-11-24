//
//  QueueManager.swift
//  AppleMusicRemoteMac
//
//  Queue generation, history tracking, AMR playlist queue management,
//  custom queue operations, and cloud queue auto-advance.
//

import Foundation
import ScriptingBridge

public final class QueueManager: @unchecked Sendable {
    public static let shared = QueueManager()

    private let lock = NSLock()
    let monitorLock = NSRecursiveLock()
    let timerLock = NSLock()
    private var albumTracksCache: [String: (timestamp: Date, tracks: [TrackInfo])] = [:]
    private var recentlyPlayedCache: (timestamp: Date, tracks: [TrackInfo])?
    private var inFlightQueueTask: Task<PlaybackQueueInfo, Never>?
    var queueTimer: DispatchSourceTimer?
    var pendingCutoffWakeupWorkItem: DispatchWorkItem?
    var pendingCutoffWakeupDeadline: Date?
    let queueTimerQueue = DispatchQueue(label: "org.ksholokhov.amr.queue.timer", qos: .utility)

    private init() {}

    // MARK: - Recently Played

    public func getRecentlyPlayed(limit: Int = 30) -> [TrackInfo] {
        let hist = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.latestHistoryTracks }
        if !hist.isEmpty {
            return Array(hist.prefix(limit))
        }
        if let cached = lock.withLock({ recentlyPlayedCache }) {
            let ttl: TimeInterval = cached.tracks.isEmpty ? 60.0 : 300.0
            if Date().timeIntervalSince(cached.timestamp) < ttl {
                return Array(cached.tracks.prefix(limit))
            }
        }
        let fetchLimit = max(limit, 30)
        var tracks: [TrackInfo] = []
        let playlistsWarm = LibraryService.shared.hasPopulatedPlaylistsCache()
        for favName in ["Любимые песни", "Favorite Songs", "Favorites"] {
            if !tracks.isEmpty { break }
            if playlistsWarm && !LibraryService.shared.hasCachedUserPlaylist(named: favName) {
                continue
            }
            tracks = LibraryService.shared.getPlaylistTracks(name: favName, limit: fetchLimit)
        }
        if tracks.isEmpty {
            tracks = Array(LibraryService.shared.getCachedLibrarySongs().prefix(fetchLimit))
        }
        lock.withLock {
            recentlyPlayedCache = (Date(), tracks)
        }
        if !tracks.isEmpty {
            return Array(tracks.prefix(limit))
        }
        return []
    }

    // MARK: - Playback Queue Generation

    public func getPlaybackQueue() async -> PlaybackQueueInfo {
        if PlaybackRouter.shared.isTestingEnvironment {
            return await computePlaybackQueue()
        }
        let (existingTask, createdTask): (Task<PlaybackQueueInfo, Never>?, Task<PlaybackQueueInfo, Never>?) = lock.withLock {
            if let active = inFlightQueueTask {
                return (active, nil)
            }
            let task = Task<PlaybackQueueInfo, Never> { [weak self] in
                guard let self = self else { return PlaybackQueueInfo() }
                let result = await self.computePlaybackQueue()
                self.lock.withLock {
                    self.inFlightQueueTask = nil
                }
                return result
            }
            inFlightQueueTask = task
            return (nil, task)
        }
        if let existingTask {
            return await existingTask.value
        }
        return await createdTask!.value
    }

    private func computePlaybackQueue() async -> PlaybackQueueInfo {
        if PlaybackRouter.shared.isTestingEnvironment {
            let (hasCustomQueue, customQueue, customQueueName, activeIdx) = PlaybackStateStore.shared.withLock {
                (
                    PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty,
                    PlaybackStateStore.shared.activeCustomQueue,
                    PlaybackStateStore.shared.activeCustomQueueName,
                    PlaybackStateStore.shared.activeCustomQueueIndex
                )
            }
            if hasCustomQueue {
                let upcoming = activeIdx + 1 < customQueue.count ? Array(customQueue[(activeIdx + 1)...]) : []
                let history = activeIdx > 0 ? Array(customQueue[0..<activeIdx].reversed()) : []
                return PlaybackQueueInfo(
                    playlist: customQueueName ?? "Queue",
                    currentIndex: activeIdx,
                    totalTracks: customQueue.count,
                    shuffle: false,
                    upcomingTracks: upcoming,
                    tracks: customQueue,
                    historyTracks: history
                )
            }
            return PlaybackQueueInfo()
        }

        if !MusicAppProvider.shared.isMusicAppRunning || !MusicAppLifecycleManager.shared.isHealthy {
            return PlaybackQueueInfo()
        }

        let (hasCustomQueue, customQueue, customQueueName, activeCustomIdx, isBusyOrAMRQueue, cached) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty,
                PlaybackStateStore.shared.activeCustomQueue,
                PlaybackStateStore.shared.activeCustomQueueName,
                PlaybackStateStore.shared.activeCustomQueueIndex,
                PlaybackStateStore.shared.isTransitioningTrack ||
                    PlaybackStateStore.shared.isStagingCloudTrack ||
                    !PlaybackStateStore.shared.currentTrackPlaybackConfirmed ||
                    PlaybackStateStore.shared.currentOriginalPlaylistName == "Очередь AMR",
                PlaybackStateStore.shared.playbackQueueCache
            )
        }

        let status = PlayerStatusEngine.shared.getPlayerStatus()
        var curName = ""
        var curArtist = ""
        var curAlbum = ""
        var curDbId = 0
        var curDuration = 0.0
        var curIsLocal = false

        if hasCustomQueue && isBusyOrAMRQueue && activeCustomIdx >= 0 && activeCustomIdx < customQueue.count {
            let expectedTrack = customQueue[activeCustomIdx]
            curName = expectedTrack.name
            curArtist = expectedTrack.artist
            curAlbum = expectedTrack.album
            curDbId = expectedTrack.numericId ?? 0
            curDuration = expectedTrack.duration
            curIsLocal = expectedTrack.isLocal ?? false
        } else if let tr = status.track, !tr.name.isEmpty {
            curName = tr.name
            curArtist = tr.artist
            curAlbum = tr.album
            curDbId = tr.numericId ?? 0
            curDuration = tr.duration
            curIsLocal = tr.isLocal ?? false
        }

        if let entry = cached, Date().timeIntervalSince(entry.timestamp) < 2.5 {
            let cachedInfo = entry.info
            if cachedInfo.currentIndex < cachedInfo.tracks.count {
                let ct = cachedInfo.tracks[cachedInfo.currentIndex]
                if (curDbId > 0 && ct.numericId == curDbId) || (!curName.isEmpty && ct.name.localizedCaseInsensitiveCompare(curName) == .orderedSame) {
                    return cachedInfo
                }
            }
        }

        // Fast path: nothing is playing and no custom queue is active
        if !hasCustomQueue && curName.isEmpty {
            if let entry = cached, Date().timeIntervalSince(entry.timestamp) < 5.0, entry.info.totalTracks == 0 {
                return entry.info
            }
            let history = getRecentlyPlayed(limit: 25)
            let queueInfo = PlaybackQueueInfo(
                playlist: "Apple Music",
                currentIndex: 0,
                totalTracks: 0,
                shuffle: false,
                upcomingTracks: [],
                tracks: [],
                historyTracks: history
            )
            PlaybackStateStore.shared.withLock {
                if PlaybackStateStore.shared.latestHistoryTracks.isEmpty && !history.isEmpty {
                    PlaybackStateStore.shared.latestHistoryTracks = history
                }
                PlaybackStateStore.shared.playbackQueueCache = (Date(), queueInfo)
            }
            return queueInfo
        }

        // 0. Custom Queue Playback
        if hasCustomQueue {
            let (activeIdx, isTransitioning, origPl, isShufActive) = PlaybackStateStore.shared.withLock {
                (
                    PlaybackStateStore.shared.activeCustomQueueIndex,
                    PlaybackStateStore.shared.isTransitioningTrack || PlaybackStateStore.shared.isStagingCloudTrack || !PlaybackStateStore.shared.currentTrackPlaybackConfirmed,
                    PlaybackStateStore.shared.currentOriginalPlaylistName,
                    PlaybackStateStore.shared.isShuffleQueueActive
                )
            }
            var matchedIdx = activeIdx
            if !curName.isEmpty && !isTransitioning && origPl != "Очередь AMR" {
                if activeIdx < customQueue.count && matchesExpectedQueueTrack(customQueue[activeIdx], candidateName: curName, candidateArtist: curArtist) {
                    matchedIdx = activeIdx
                } else if let foundIdx = customQueue.firstIndex(where: { isTrackMatching(expected: $0, candidateName: curName, candidateArtist: curArtist) }) {
                    matchedIdx = foundIdx
                }
            }

            if matchedIdx != activeIdx {
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.activeCustomQueueIndex = matchedIdx
                }
            }

            var formattedTracks = [TrackInfo]()
            for (idx, var t) in customQueue.enumerated() {
                t.isCurrent = (idx == matchedIdx)
                t.index = idx + 1
                if !t.hasArtwork || t.artworkUrl.isEmpty {
                    if idx == matchedIdx, let local = ArtworkService.shared.findLocalTrackArtwork(name: t.name, artist: t.artist) {
                        t.artworkUrl = local
                        t.hasArtwork = true
                    } else if let cached = MusicKitManager.shared.getCachedTrackArtwork(name: t.name, artist: t.artist), !cached.isEmpty {
                        t.artworkUrl = cached
                        t.hasArtwork = true
                    }
                }
                formattedTracks.append(t)
            }

            var upcoming = [TrackInfo]()
            if matchedIdx + 1 < formattedTracks.count {
                upcoming = Array(formattedTracks[(matchedIdx + 1)...])
            }

            let missingTracks = Array(upcoming.prefix(5).filter { !$0.hasArtwork })
            if !missingTracks.isEmpty {
                Task.detached(priority: .utility) {
                    for t in missingTracks {
                        _ = await MusicKitManager.shared.searchTrackArtwork(name: t.name, artist: t.artist)
                    }
                }
            }

            var recentHistory = [TrackInfo]()
            if matchedIdx > 0 {
                recentHistory = Array(formattedTracks[0..<matchedIdx].reversed().prefix(100))
            }
            enrichQueueTrackArtworks(&upcoming)
            enrichQueueTrackArtworks(&recentHistory)

            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.latestUpcomingTracks = upcoming
                PlaybackStateStore.shared.latestHistoryTracks = recentHistory
            }

            let qInfo = PlaybackQueueInfo(
                playlist: customQueueName ?? "Очередь",
                currentIndex: matchedIdx,
                totalTracks: formattedTracks.count,
                shuffle: isShufActive,
                upcomingTracks: upcoming,
                tracks: formattedTracks,
                historyTracks: recentHistory
            )

            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.playbackQueueCache = (Date(), qInfo)
            }
            return qInfo
        }

        // 1. Radio / Station Playback Mode
        let (isRadio, stationName, origPl) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isRadioPlayback,
                PlaybackStateStore.shared.activeStationName,
                PlaybackStateStore.shared.currentOriginalPlaylistName
            )
        }

        let isStreamTrack = !curIsLocal
        var curPlNameRaw = ""
        if !status.playlist.isEmpty && status.playlist != "Apple Music Radio" && status.playlist != "Музыка" && status.playlist != "Music" && status.playlist != "Медиатека" {
            curPlNameRaw = status.playlist
        }
        var isRadioDetected = isRadio || status.isRadio
        if !curPlNameRaw.isEmpty && curPlNameRaw != "Музыка" && curPlNameRaw != "Music" && curPlNameRaw != "Медиатека" {
            isRadioDetected = false
        } else if let orig = origPl, !orig.isEmpty {
            isRadioDetected = false
        } else if isStreamTrack && curPlNameRaw.isEmpty {
            let lowerName = curName.lowercased()
            if lowerName.hasPrefix("станция:") || lowerName.hasPrefix("station:") || curDuration <= 0 {
                isRadioDetected = true
            }
        }

        if isRadioDetected {
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.isRadioPlayback = true
            }
            var currentTrackInfo = TrackInfo(
                id: "\(curDbId)",
                numericId: curDbId,
                name: !curName.isEmpty ? curName : (stationName ?? "Apple Music Radio"),
                artist: !curArtist.isEmpty ? curArtist : "Apple Music",
                album: curAlbum,
                duration: curDuration,
                hasArtwork: false,
                artworkUrl: "",
                favorited: status.track?.favorited ?? false,
                isLocal: false,
                isCurrent: true
            )
            if let artUrl = MusicKitManager.shared.getCachedTrackArtwork(name: currentTrackInfo.name, artist: currentTrackInfo.artist, album: currentTrackInfo.album) ?? status.track?.artworkUrl, !artUrl.isEmpty {
                currentTrackInfo.artworkUrl = artUrl
                currentTrackInfo.hasArtwork = true
            }

            var history = PlaybackStateStore.shared.withLock { () -> [TrackInfo] in
                PlaybackStateStore.shared.recordRadioTrackTransitionLocked(current: currentTrackInfo, stationName: stationName)
                return PlaybackStateStore.shared.radioHistoryTracks
            }
            enrichQueueTrackArtworks(&history)
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.latestUpcomingTracks = []
                PlaybackStateStore.shared.latestHistoryTracks = history
            }

            let queueInfo = PlaybackQueueInfo(
                playlist: stationName ?? "Apple Music Radio",
                currentIndex: 0,
                totalTracks: 1,
                shuffle: false,
                upcomingTracks: [],
                tracks: [currentTrackInfo],
                historyTracks: history
            )

            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.playbackQueueCache = (Date(), queueInfo)
            }
            return queueInfo
        }

        // 2. Detect Current Playlist from Music.app
        var curPlName = curPlNameRaw
        if curPlName.isEmpty || curPlName == "Музыка" || curPlName == "Music" || curPlName == "Медиатека" {
            let orig = PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.currentOriginalPlaylistName ?? ""
            }
            if !orig.isEmpty {
                curPlName = orig
            }
        }

        var tracksList: [TrackInfo] = []
        var effectivePlName = curPlName

        let (isShufActive, shufQueue, _) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isShuffleQueueActive,
                PlaybackStateStore.shared.activeShuffledQueue,
                PlaybackStateStore.shared.currentOriginalPlaylistName
            )
        }

        if isShufActive && !shufQueue.isEmpty {
            effectivePlName = origPl ?? "Очередь"
            tracksList = shufQueue
        } else if curPlName == "Очередь AMR"
                    || curPlName.localizedCaseInsensitiveCompare("Очередь AMR") == .orderedSame {
            effectivePlName = origPl ?? "Очередь AMR"
            // Single-track isolated playback without custom queue: leave tracksList empty so the active track block below builds a clean 1-track queue
            tracksList = []
        } else if !curPlName.isEmpty && curPlName != "Музыка" && curPlName != "Music" && curPlName != "Медиатека" {
            tracksList = LibraryService.shared.getPlaylistTracks(name: curPlName)
        }
        if tracksList.isEmpty
            && !curPlName.isEmpty
            && curPlName != "Музыка"
            && curPlName != "Music"
            && curPlName != "Медиатека"
            && curPlName != "Очередь AMR" {
            tracksList = LibraryService.shared.getCurrentPlaylistTracks()
        }

        // 3. Album track resolution (from cache, never dump full library)
        if tracksList.isEmpty && !curAlbum.isEmpty && (curPlName.localizedCaseInsensitiveCompare(curAlbum) == .orderedSame) {
            let cacheKey = "\(curAlbum.lowercased())|\(curArtist.lowercased())"
            let cached = lock.withLock { albumTracksCache[cacheKey] }

            if let c = cached, Date().timeIntervalSince(c.timestamp) < 1800 {
                tracksList = c.tracks
                effectivePlName = curAlbum
            } else {
                let catalogTracks = await MusicKitManager.shared.getAlbumTracks(album: curAlbum, artist: curArtist)
                if !catalogTracks.isEmpty {
                    lock.withLock {
                        if albumTracksCache.count >= 256 {
                            let oldest = albumTracksCache.sorted { $0.value.timestamp < $1.value.timestamp }.prefix(128).map(\.key)
                            for k in oldest { albumTracksCache.removeValue(forKey: k) }
                        }
                        albumTracksCache[cacheKey] = (Date(), catalogTracks)
                    }
                    tracksList = catalogTracks
                    effectivePlName = curAlbum
                }
            }
            }

        if tracksList.isEmpty {
            var currentTrackInfo = TrackInfo(
                id: "\(curDbId)",
                numericId: curDbId,
                name: !curName.isEmpty ? curName : (!curPlName.isEmpty ? curPlName : (stationName ?? "Apple Music")),
                artist: curArtist,
                album: curAlbum,
                duration: curDuration,
                hasArtwork: false,
                artworkUrl: "",
                favorited: status.track?.favorited ?? false,
                isLocal: curIsLocal,
                isCurrent: true
            )
            if let artUrl = MusicKitManager.shared.getCachedTrackArtwork(name: currentTrackInfo.name, artist: currentTrackInfo.artist, album: currentTrackInfo.album)
                ?? (curIsLocal ? ArtworkService.shared.findLocalTrackArtwork(name: currentTrackInfo.name, artist: currentTrackInfo.artist) : nil)
                ?? status.track?.artworkUrl,
               !artUrl.isEmpty {
                currentTrackInfo.artworkUrl = artUrl
                currentTrackInfo.hasArtwork = true
            }

            let history: [TrackInfo] = []
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.latestUpcomingTracks = []
                PlaybackStateStore.shared.latestHistoryTracks = history
            }

            let queueInfo = PlaybackQueueInfo(
                playlist: !curPlName.isEmpty ? curPlName : (stationName ?? "Apple Music"),
                currentIndex: 0,
                totalTracks: 1,
                shuffle: false,
                upcomingTracks: [],
                tracks: [currentTrackInfo],
                historyTracks: history
            )
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.playbackQueueCache = (Date(), queueInfo)
            }
            return queueInfo
        }

        // Find current track index in tracksList
        var curIdx = -1
        for (i, t) in tracksList.enumerated() {
            if curDbId > 0 && t.numericId == curDbId {
                curIdx = i
                break
            }
            if !curName.isEmpty && t.name.localizedCaseInsensitiveCompare(curName) == .orderedSame {
                if curArtist.isEmpty || t.artist.isEmpty || t.artist.localizedCaseInsensitiveCompare(curArtist) == .orderedSame {
                    curIdx = i
                    break
                }
            }
        }
        if curIdx == -1 && !curName.isEmpty {
            let cleanCur = curName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            for (i, t) in tracksList.enumerated() {
                let cleanT = t.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if cleanT.hasPrefix(cleanCur) || cleanCur.hasPrefix(cleanT) {
                    curIdx = i
                    break
                }
            }
        }
        if curIdx == -1 && !tracksList.isEmpty {
            curIdx = 0
        }

        var formattedTracks = [TrackInfo]()
        for (idx, var t) in tracksList.enumerated() {
            t.isCurrent = (idx == curIdx)
            t.index = idx + 1
            if idx == curIdx {
                if let art = MusicKitManager.shared.getCachedTrackArtwork(name: t.name, artist: t.artist, album: t.album)
                    ?? (t.isLocal == true ? ArtworkService.shared.findLocalTrackArtwork(name: t.name, artist: t.artist) : nil)
                    ?? status.track?.artworkUrl,
                   !art.isEmpty {
                    t.artworkUrl = art
                    t.hasArtwork = true
                }
            }
            formattedTracks.append(t)
        }

        var upcoming = [TrackInfo]()
        var history = [TrackInfo]()
        let isShuffle = (status.shuffle || isShufActive) && curPlName != "Очередь AMR"

        if !isShuffle {
            if curIdx >= 0 && curIdx + 1 < formattedTracks.count {
                upcoming = Array(formattedTracks[(curIdx + 1)...])
            }
            if curIdx > 0 {
                history = Array(formattedTracks[0..<curIdx].reversed().prefix(100))
            }
        } else {
            // Stable shuffle tracking even if Shuffle was enabled externally inside Music.app:
            // maintains `[played_0..played_k, currentTrack, unplayed_0..unplayed_m]` without ever regenerating unplayed tracks!
            PlaybackStateStore.shared.withLock {
                let matchesCur: (TrackInfo) -> Bool = { item in
                    (curDbId > 0 && item.numericId == curDbId) ||
                    (!curName.isEmpty && item.name.localizedCaseInsensitiveCompare(curName) == .orderedSame &&
                     (curArtist.isEmpty || item.artist.isEmpty || item.artist.localizedCaseInsensitiveCompare(curArtist) == .orderedSame))
                }
                if PlaybackStateStore.shared.activeShuffledPlaylistName == effectivePlName && !PlaybackStateStore.shared.activeShuffledQueue.isEmpty {
                    var sq = PlaybackStateStore.shared.activeShuffledQueue
                    var sIdx = min(max(0, PlaybackStateStore.shared.activeShuffledIndex), sq.count - 1)
                    if !matchesCur(sq[sIdx]) {
                        if let tailPos = sq[(sIdx + 1)...].firstIndex(where: matchesCur) {
                            let picked = sq.remove(at: tailPos)
                            let newIdx = min(sIdx + 1, sq.count)
                            sq.insert(picked, at: newIdx)
                            sIdx = newIdx
                        } else if let pastPos = sq[..<sIdx].firstIndex(where: matchesCur) {
                            sIdx = pastPos
                        }
                        for i in 0..<sq.count {
                            sq[i].index = i + 1
                            sq[i].isCurrent = (i == sIdx)
                        }
                        PlaybackStateStore.shared.activeShuffledQueue = sq
                        PlaybackStateStore.shared.activeShuffledIndex = sIdx
                    }
                    formattedTracks = sq
                    curIdx = sIdx
                    if sIdx + 1 < sq.count {
                        upcoming = Array(sq[(sIdx + 1)...])
                    }
                    if sIdx > 0 {
                        history = Array(sq[0..<sIdx].reversed().prefix(100))
                    }
                } else if !formattedTracks.isEmpty {
                    let safeCurIdx = min(max(0, curIdx), formattedTracks.count - 1)
                    let curItem = formattedTracks[safeCurIdx]
                    var others = formattedTracks
                    others.remove(at: safeCurIdx)
                    others.shuffle()
                    var sq = [curItem] + others
                    for i in 0..<sq.count {
                        sq[i].index = i + 1
                        sq[i].isCurrent = (i == 0)
                    }
                    PlaybackStateStore.shared.activeShuffledQueue = sq
                    PlaybackStateStore.shared.activeShuffledIndex = 0
                    PlaybackStateStore.shared.activeShuffledPlaylistName = effectivePlName
                    formattedTracks = sq
                    curIdx = 0
                    upcoming = sq.count > 1 ? Array(sq[1...]) : []
                    history = []
                }
            }
        }

        if upcoming.isEmpty {
            upcoming = PlaybackStateStore.shared.withLock {
                if !PlaybackStateStore.shared.isRadioPlayback && !PlaybackStateStore.shared.latestUpcomingTracks.isEmpty {
                    return PlaybackStateStore.shared.latestUpcomingTracks
                }
                return []
            }
        }

        enrichQueueTrackArtworks(&upcoming)
        enrichQueueTrackArtworks(&history)

        // Only prefetch embedded artwork for genuinely local file tracks
        let topLocalIds = Array((upcoming.prefix(6) + history.prefix(4)).filter { $0.isLocal == true }.compactMap { $0.numericId })
        if !topLocalIds.isEmpty {
            ArtworkService.shared.queueNativeArtworkFetch(ids: topLocalIds)
        }

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.latestUpcomingTracks = upcoming
            PlaybackStateStore.shared.latestHistoryTracks = history
        }

        let queueInfo = PlaybackQueueInfo(
            playlist: effectivePlName.isEmpty ? "Музыка" : effectivePlName,
            currentIndex: max(0, curIdx),
            totalTracks: formattedTracks.count,
            shuffle: isShufActive || status.shuffle,
            upcomingTracks: upcoming,
            tracks: formattedTracks,
            historyTracks: history
        )
        if !upcoming.isEmpty || !formattedTracks.isEmpty {
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.playbackQueueCache = (Date(), queueInfo)
            }
        }
        return queueInfo
    }

    /// Non-blocking artwork URL enrichment for both upcoming and previous queue items.
    private func enrichQueueTrackArtworks(_ tracks: inout [TrackInfo]) {
        for i in 0..<tracks.count {
            let t = tracks[i]
            if let cachedCloud = MusicKitManager.shared.getCachedTrackArtwork(name: t.name, artist: t.artist, album: t.album), !cachedCloud.isEmpty {
                tracks[i].artworkUrl = cachedCloud
                tracks[i].hasArtwork = true
                continue
            }
            if t.artworkUrl.hasPrefix("http://") || t.artworkUrl.hasPrefix("https://") || t.artworkUrl.hasPrefix("data:") {
                tracks[i].hasArtwork = true
                continue
            }
            let encN = t.name.amrQueryValueEncoded
            let encA = t.artist.amrQueryValueEncoded
            let encAl = t.album.amrQueryValueEncoded
            if t.isLocal == true, let nid = t.numericId, nid > 0 {
                if let cached = ArtworkService.shared.getCachedTrackArtwork(id: nid) {
                    tracks[i].artworkUrl = "data:image/jpeg;base64,\(cached.base64EncodedString())"
                    tracks[i].hasArtwork = true
                    continue
                }
                tracks[i].artworkUrl = "/api/artwork/track?id=\(nid)&name=\(encN)&artist=\(encA)&album=\(encAl)"
                tracks[i].hasArtwork = true
                continue
            }
            if !t.name.isEmpty {
                tracks[i].artworkUrl = "/api/artwork/search?name=\(encN)&artist=\(encA)&album=\(encAl)"
                tracks[i].hasArtwork = true
            }
        }
    }
}
