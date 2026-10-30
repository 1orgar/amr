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
    private var albumTracksCache: [String: (timestamp: Date, tracks: [TrackInfo])] = [:]
    private var queueTimer: DispatchSourceTimer?
    private let queueTimerQueue = DispatchQueue(label: "org.ksholokhov.amr.queue.timer", qos: .utility)

    private init() {}

    // MARK: - Recently Played

    public func getRecentlyPlayed(limit: Int = 30) -> [TrackInfo] {
        let hist = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.latestHistoryTracks }
        if !hist.isEmpty {
            return Array(hist.prefix(limit))
        }
        var tracks = LibraryService.shared.getPlaylistTracks(name: "Любимые песни")
        if tracks.isEmpty {
            tracks = LibraryService.shared.getPlaylistTracks(name: "Недавно добавленные")
        }
        if tracks.isEmpty {
            tracks = LibraryService.shared.getPlaylistTracks(name: "Классика рока")
        }
        if !tracks.isEmpty {
            return Array(tracks.prefix(limit))
        }
        return []
    }

    // MARK: - Playback Queue Generation

    public func getPlaybackQueue() async -> PlaybackQueueInfo {
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

        guard let app = MusicAppProvider.shared.getMusicApp() else {
            return PlaybackQueueInfo()
        }

        let curTrack = app.currentTrack
        let curName = curTrack?.sbName ?? ""
        let curArtist = curTrack?.sbArtist ?? ""
        let curAlbum = curTrack?.sbAlbum ?? ""
        let curDbId = (curTrack?.value(forKey: "databaseID") as? Int) ?? 0

        let cached = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.playbackQueueCache }
        if let entry = cached, Date().timeIntervalSince(entry.timestamp) < 2.0 {
            let cachedInfo = entry.info
            if cachedInfo.currentIndex < cachedInfo.tracks.count {
                let ct = cachedInfo.tracks[cachedInfo.currentIndex]
                if (curDbId > 0 && ct.numericId == curDbId) || (!curName.isEmpty && ct.name.localizedCaseInsensitiveCompare(curName) == .orderedSame) {
                    return cachedInfo
                }
            }
        }

        let (hasCustomQueue, customQueue, customQueueName) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty,
                PlaybackStateStore.shared.activeCustomQueue,
                PlaybackStateStore.shared.activeCustomQueueName
            )
        }

        // Fast path: nothing is playing and no custom queue is active
        if !hasCustomQueue && (curTrack == nil || curName.isEmpty) {
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
            return queueInfo
        }

        // 0. Custom Queue Playback
        if hasCustomQueue {
            let (activeIdx, isTransitioning, confirmed, lastPlayTime) = PlaybackStateStore.shared.withLock {
                (
                    PlaybackStateStore.shared.activeCustomQueueIndex,
                    PlaybackStateStore.shared.isTransitioningTrack,
                    PlaybackStateStore.shared.currentTrackPlaybackConfirmed,
                    PlaybackStateStore.shared.lastCloudPlayTime
                )
            }
            let timeSincePlay = Date().timeIntervalSince(lastPlayTime ?? Date.distantPast)
            var matchedIdx = activeIdx
            if !curName.isEmpty && !isTransitioning && activeIdx < customQueue.count {
                if isTrackMatching(expected: customQueue[activeIdx], candidateName: curName, candidateArtist: curArtist) {
                    matchedIdx = activeIdx
                } else if (confirmed || timeSincePlay >= 3.5) {
                    let forwardWindowEnd = min(activeIdx + 3, customQueue.count)
                    if let foundIdx = customQueue[activeIdx..<forwardWindowEnd].firstIndex(where: { isTrackMatching(expected: $0, candidateName: curName, candidateArtist: curArtist) }) {
                        matchedIdx = foundIdx
                    }
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
                recentHistory = Array(formattedTracks[0..<matchedIdx].reversed().prefix(25))
            }

            let qInfo = PlaybackQueueInfo(
                playlist: customQueueName ?? "Очередь",
                currentIndex: matchedIdx,
                totalTracks: formattedTracks.count,
                shuffle: app.shuffleEnabled,
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

        let isStreamTrack = (curTrack != nil && curTrack?.value(forKey: "location") == nil)
        let curPlNameRaw = (app.currentPlaylist?.value(forKey: "name") as? String) ?? ""
        var isRadioDetected = isRadio
        if !curPlNameRaw.isEmpty && curPlNameRaw != "Музыка" && curPlNameRaw != "Music" && curPlNameRaw != "Медиатека" {
            isRadioDetected = false
        } else if let orig = origPl, !orig.isEmpty {
            isRadioDetected = false
        } else if isStreamTrack && curPlNameRaw.isEmpty {
            isRadioDetected = true
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
                duration: (curTrack?.value(forKey: "duration") as? Double) ?? 0,
                hasArtwork: false,
                artworkUrl: "",
                favorited: false,
                isLocal: false,
                isCurrent: true
            )
            if let artUrl = ArtworkService.shared.findLocalTrackArtwork(name: currentTrackInfo.name, artist: currentTrackInfo.artist) ?? MusicKitManager.shared.getCachedTrackArtwork(name: currentTrackInfo.name, artist: currentTrackInfo.artist, album: currentTrackInfo.album) {
                currentTrackInfo.artworkUrl = artUrl
                currentTrackInfo.hasArtwork = true
            } else {
                let artData = ArtworkService.shared.getCurrentTrackArtworkDataUri()
                if !artData.isEmpty {
                    currentTrackInfo.artworkUrl = artData
                    currentTrackInfo.hasArtwork = true
                }
            }

            let history = getRecentlyPlayed(limit: 25)
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
        } else if curPlName == "Очередь AMR" || curPlName.localizedCaseInsensitiveCompare("Очередь AMR") == .orderedSame {
            effectivePlName = origPl ?? "Очередь AMR"
            tracksList = LibraryService.shared.getPlaylistTracks(name: "Очередь AMR")
        } else if !curPlName.isEmpty && curPlName != "Музыка" && curPlName != "Music" && curPlName != "Медиатека" {
            tracksList = LibraryService.shared.getPlaylistTracks(name: curPlName)
        }
        if tracksList.isEmpty && !curPlName.isEmpty {
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
                duration: (curTrack?.value(forKey: "duration") as? Double) ?? 0,
                hasArtwork: false,
                artworkUrl: "",
                favorited: false,
                isLocal: false,
                isCurrent: true
            )
            if let artUrl = ArtworkService.shared.findLocalTrackArtwork(name: currentTrackInfo.name, artist: currentTrackInfo.artist) ?? MusicKitManager.shared.getCachedTrackArtwork(name: currentTrackInfo.name, artist: currentTrackInfo.artist, album: currentTrackInfo.album) {
                currentTrackInfo.artworkUrl = artUrl
                currentTrackInfo.hasArtwork = true
            } else {
                let artData = ArtworkService.shared.getCurrentTrackArtworkDataUri()
                if !artData.isEmpty {
                    currentTrackInfo.artworkUrl = artData
                    currentTrackInfo.hasArtwork = true
                }
            }

            let history = getRecentlyPlayed(limit: 25)
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
        if curPlName == "Очередь AMR", let currentTrackIndex = (app.currentTrack?.value(forKey: "index") as? Int), currentTrackIndex > 0, currentTrackIndex <= tracksList.count {
            curIdx = currentTrackIndex - 1
        } else {
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
        }
        if curIdx == -1 && !tracksList.isEmpty {
            curIdx = 0
        }

        var formattedTracks = [TrackInfo]()
        for (idx, var t) in tracksList.enumerated() {
            t.isCurrent = (idx == curIdx)
            t.index = idx + 1
            if idx == curIdx {
                if let art = ArtworkService.shared.findLocalTrackArtwork(name: t.name, artist: t.artist) ?? MusicKitManager.shared.getCachedTrackArtwork(name: t.name, artist: t.artist) {
                    t.artworkUrl = art
                    t.hasArtwork = true
                }
            }
            formattedTracks.append(t)
        }

        var upcoming = [TrackInfo]()
        var history = [TrackInfo]()
        let isShuffle = app.shuffleEnabled && !isShufActive && curPlName != "Очередь AMR"

        if !isShuffle {
            if curIdx >= 0 && curIdx + 1 < formattedTracks.count {
                upcoming = Array(formattedTracks[(curIdx + 1)...])
            }
            if curIdx > 0 {
                history = Array(formattedTracks[0..<curIdx].reversed().prefix(25))
            }
        } else {
            PlaybackStateStore.shared.withLock {
                if PlaybackStateStore.shared.activeShuffledPlaylistName == effectivePlName && !PlaybackStateStore.shared.activeShuffledQueue.isEmpty {
                    if let foundIdx = PlaybackStateStore.shared.activeShuffledQueue.firstIndex(where: {
                        ($0.numericId != nil && $0.numericId == curDbId) ||
                        (!curName.isEmpty && $0.name.localizedCaseInsensitiveCompare(curName) == .orderedSame)
                    }) {
                        upcoming = Array(PlaybackStateStore.shared.activeShuffledQueue[(foundIdx + 1)...])
                        if foundIdx > 0 {
                            history = Array(PlaybackStateStore.shared.activeShuffledQueue[0..<foundIdx].reversed().prefix(25))
                        }
                    } else {
                        upcoming = PlaybackStateStore.shared.activeShuffledQueue.filter {
                            ($0.numericId != nil && $0.numericId != curDbId) || (!curName.isEmpty && $0.name.localizedCaseInsensitiveCompare(curName) != .orderedSame)
                        }
                    }
                } else if !formattedTracks.isEmpty {
                    var remaining = formattedTracks.filter {
                        ($0.numericId != nil && $0.numericId != curDbId) || (!curName.isEmpty && $0.name.localizedCaseInsensitiveCompare(curName) != .orderedSame)
                    }
                    remaining.shuffle()
                    PlaybackStateStore.shared.activeShuffledQueue = remaining
                    PlaybackStateStore.shared.activeShuffledPlaylistName = effectivePlName
                    upcoming = remaining
                }
            }
        }

        if history.isEmpty {
            history = getRecentlyPlayed(limit: 25)
        }

        if upcoming.isEmpty {
            upcoming = PlaybackStateStore.shared.withLock {
                if !PlaybackStateStore.shared.isRadioPlayback && !PlaybackStateStore.shared.latestUpcomingTracks.isEmpty {
                    return PlaybackStateStore.shared.latestUpcomingTracks
                }
                return []
            }
        }

        // Fast pass for artwork
        for i in 0..<upcoming.count {
            let t = upcoming[i]
            if let nid = t.numericId, nid > 0 {
                if let cached = ArtworkService.shared.getCachedTrackArtwork(id: nid) {
                    upcoming[i].artworkUrl = "data:image/jpeg;base64,\(cached.base64EncodedString())"
                    upcoming[i].hasArtwork = true
                    continue
                }
                upcoming[i].artworkUrl = "/api/artwork/track?id=\(nid)"
                upcoming[i].hasArtwork = true
                continue
            }
            if let local = ArtworkService.shared.findLocalTrackArtwork(name: t.name, artist: t.artist) {
                upcoming[i].artworkUrl = local
                upcoming[i].hasArtwork = true
            } else if let cachedCloud = MusicKitManager.shared.getCachedTrackArtwork(name: t.name, artist: t.artist, album: t.album), !cachedCloud.isEmpty {
                upcoming[i].artworkUrl = cachedCloud
                upcoming[i].hasArtwork = true
            }
        }

        // Native artwork queue for top upcoming
        let topIds = Array(upcoming.prefix(10).compactMap { $0.numericId })
        ArtworkService.shared.queueNativeArtworkFetch(ids: topIds)

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.latestUpcomingTracks = upcoming
            PlaybackStateStore.shared.latestHistoryTracks = history
        }

        let queueInfo = PlaybackQueueInfo(
            playlist: effectivePlName.isEmpty ? "Музыка" : effectivePlName,
            currentIndex: max(0, curIdx),
            totalTracks: formattedTracks.count,
            shuffle: isShufActive || app.shuffleEnabled,
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

    // MARK: - Enqueue Operations

    public func enqueueTrack(_ track: TrackInfo, playNext: Bool) async -> Bool {
        let hasCustom = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty
        }

        if !hasCustom {
            let q = await getPlaybackQueue()
            let curTrack = PlayerStatusEngine.shared.getPlayerStatus().track

            return PlaybackStateStore.shared.withLock {
                var queue = [TrackInfo]()
                if let cur = curTrack {
                    queue.append(cur)
                } else if q.currentIndex < q.tracks.count {
                    queue.append(q.tracks[q.currentIndex])
                }
                if !q.upcomingTracks.isEmpty {
                    queue.append(contentsOf: q.upcomingTracks)
                }

                if queue.isEmpty {
                    PlaybackStateStore.shared.activeCustomQueue = [track]
                    PlaybackStateStore.shared.activeCustomQueueIndex = 0
                    PlaybackStateStore.shared.isCustomQueuePlayback = true
                    PlaybackStateStore.shared.activeCustomQueueName = "Очередь"
                    return playQueueIndexUnlocked(0)
                }

                PlaybackStateStore.shared.activeCustomQueue = queue
                PlaybackStateStore.shared.activeCustomQueueIndex = 0
                PlaybackStateStore.shared.isCustomQueuePlayback = true
                PlaybackStateStore.shared.activeCustomQueueName = q.playlist.isEmpty ? "Очередь" : q.playlist

                if playNext {
                    PlaybackStateStore.shared.activeCustomQueue.insert(track, at: 1)
                } else {
                    PlaybackStateStore.shared.activeCustomQueue.append(track)
                }
                return true
            }
        }

        return PlaybackStateStore.shared.withLock {
            if playNext {
                let insertIdx = min(PlaybackStateStore.shared.activeCustomQueue.count, PlaybackStateStore.shared.activeCustomQueueIndex + 1)
                PlaybackStateStore.shared.activeCustomQueue.insert(track, at: insertIdx)
            } else {
                PlaybackStateStore.shared.activeCustomQueue.append(track)
            }
            return true
        }
    }

    public func enqueueTracks(_ tracks: [TrackInfo], playNext: Bool) async -> Bool {
        guard !tracks.isEmpty else { return false }
        let hasCustom = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty
        }

        if !hasCustom {
            let q = await getPlaybackQueue()
            let curTrack = PlayerStatusEngine.shared.getPlayerStatus().track

            return PlaybackStateStore.shared.withLock {
                var queue = [TrackInfo]()
                if let cur = curTrack {
                    queue.append(cur)
                } else if q.currentIndex < q.tracks.count {
                    queue.append(q.tracks[q.currentIndex])
                }
                if !q.upcomingTracks.isEmpty {
                    queue.append(contentsOf: q.upcomingTracks)
                }

                if queue.isEmpty {
                    return PlaybackRouter.shared.playCustomTracksUnlocked(tracks, startIndex: 0, shuffle: false, queueName: "Очередь")
                }

                PlaybackStateStore.shared.activeCustomQueue = queue
                PlaybackStateStore.shared.activeCustomQueueIndex = 0
                PlaybackStateStore.shared.isCustomQueuePlayback = true
                PlaybackStateStore.shared.activeCustomQueueName = q.playlist.isEmpty ? "Очередь" : q.playlist

                if playNext {
                    PlaybackStateStore.shared.activeCustomQueue.insert(contentsOf: tracks, at: 1)
                } else {
                    PlaybackStateStore.shared.activeCustomQueue.append(contentsOf: tracks)
                }
                return true
            }
        }

        return PlaybackStateStore.shared.withLock {
            if playNext {
                let insertIdx = min(PlaybackStateStore.shared.activeCustomQueue.count, PlaybackStateStore.shared.activeCustomQueueIndex + 1)
                PlaybackStateStore.shared.activeCustomQueue.insert(contentsOf: tracks, at: insertIdx)
            } else {
                PlaybackStateStore.shared.activeCustomQueue.append(contentsOf: tracks)
            }
            return true
        }
    }

    public func removeQueueTrack(at index: Int) async -> Bool {
        let hasCustom = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty
        }

        if hasCustom {
            return PlaybackStateStore.shared.withLock {
                let targetIdx = PlaybackStateStore.shared.activeCustomQueueIndex + 1 + index
                guard targetIdx >= 0 && targetIdx < PlaybackStateStore.shared.activeCustomQueue.count else { return false }
                PlaybackStateStore.shared.activeCustomQueue.remove(at: targetIdx)
                return true
            }
        }

        if let app = MusicAppProvider.shared.getMusicApp(), let pName = app.currentPlaylist?.value(forKey: "name") as? String, pName == "Очередь AMR" {
            let curIdx = (app.currentTrack?.value(forKey: "index") as? Int) ?? 1
            let targetIdx = curIdx + 1 + index
            let script = """
            tell application "Music"
                try
                    set qPl to missing value
                    repeat with p in (get every user playlist whose name is "Очередь AMR")
                        if (count of tracks of p) > 0 then
                            set qPl to p
                            exit repeat
                        end if
                    end repeat
                    if qPl is not missing value then
                        delete (track \(targetIdx) of qPl)
                    end if
                end try
            end tell
            """
            _ = AppleScriptExecutor.shared.execute(script)
            LibraryService.shared.invalidatePlaylistCache(name: "Очередь AMR")
            PlaybackStateStore.shared.invalidateQueueCache()
            return true
        }

        let q = await getPlaybackQueue()
        guard index >= 0 && index < q.upcomingTracks.count else { return false }

        return PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.activeCustomQueue = q.tracks
            PlaybackStateStore.shared.activeCustomQueueIndex = q.currentIndex
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueueName = q.playlist
            let targetIdx = PlaybackStateStore.shared.activeCustomQueueIndex + 1 + index
            if targetIdx >= 0 && targetIdx < PlaybackStateStore.shared.activeCustomQueue.count {
                PlaybackStateStore.shared.activeCustomQueue.remove(at: targetIdx)
                return true
            }
            return false
        }
    }

    public func clearUpcomingQueue() async -> Bool {
        PlaybackStateStore.shared.invalidateQueueCache()
        let hasCustom = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty
        }

        if hasCustom {
            return PlaybackStateStore.shared.withLock {
                if PlaybackStateStore.shared.activeCustomQueueIndex + 1 < PlaybackStateStore.shared.activeCustomQueue.count {
                    PlaybackStateStore.shared.activeCustomQueue.removeSubrange((PlaybackStateStore.shared.activeCustomQueueIndex + 1)...)
                }
                return true
            }
        }

        if let app = MusicAppProvider.shared.getMusicApp(), let pName = app.currentPlaylist?.value(forKey: "name") as? String, pName == "Очередь AMR" {
            let curIdx = (app.currentTrack?.value(forKey: "index") as? Int) ?? 1
            let script = """
            tell application "Music"
                try
                    set qPl to missing value
                    repeat with p in (get every user playlist whose name is "Очередь AMR")
                        if (count of tracks of p) > 0 then
                            set qPl to p
                            exit repeat
                        end if
                    end repeat
                    if qPl is not missing value then
                        set c to count of tracks of qPl
                        if c > \(curIdx) then
                            delete (tracks \(curIdx + 1) thru c of qPl)
                        end if
                    end if
                end try
            end tell
            """
            _ = AppleScriptExecutor.shared.execute(script)
            LibraryService.shared.invalidatePlaylistCache(name: "Очередь AMR")
            return true
        }

        let q = await getPlaybackQueue()
        let curTrack = PlayerStatusEngine.shared.getPlayerStatus().track
        return PlaybackStateStore.shared.withLock {
            if let cur = curTrack {
                PlaybackStateStore.shared.activeCustomQueue = [cur]
            } else if q.currentIndex < q.tracks.count {
                PlaybackStateStore.shared.activeCustomQueue = [q.tracks[q.currentIndex]]
            } else {
                PlaybackStateStore.shared.activeCustomQueue = []
            }
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueueName = "Очередь"
            return true
        }
    }

    // MARK: - Queue Track Execution

    public func playQueueIndex(_ index: Int) async -> Bool {
        PlaybackStateStore.shared.invalidateQueueCache()
        let (hasCustom, curCustomIndex, customCount) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty,
                PlaybackStateStore.shared.activeCustomQueueIndex,
                PlaybackStateStore.shared.activeCustomQueue.count
            )
        }

        if hasCustom {
            let targetIdx = curCustomIndex + 1 + index
            guard targetIdx >= 0 && targetIdx < customCount else { return false }
            return PlaybackStateStore.shared.withLock {
                self.playQueueIndexUnlocked(targetIdx)
            }
        }

        let q = await getPlaybackQueue()
        guard index >= 0 && index < q.upcomingTracks.count else { return false }
        let targetTrack = q.upcomingTracks[index]

        let (isShuf, shufQueue) = PlaybackStateStore.shared.withLock {
            (PlaybackStateStore.shared.isShuffleQueueActive, PlaybackStateStore.shared.activeShuffledQueue)
        }

        if isShuf && !shufQueue.isEmpty {
            let targetIdx = q.currentIndex + 1 + index
            guard targetIdx >= 0 && targetIdx < shufQueue.count else { return false }
            let target1Based = targetIdx + 1

            let script = """
            tell application "Music"
                try
                    set qPl to user playlist "Очередь AMR"
                    set trList to tracks of qPl
                    if (count of trList) >= \(target1Based) then
                        play (item \(target1Based) of trList)
                        return "ok"
                    end if
                end try
                return "error"
            end tell
            """
            let (ok, out) = AppleScriptExecutor.shared.execute(script)
            if ok && out?.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" {
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                return true
            }
        }

        // 1. Try by numeric database ID (ONLY if local track)
        if targetTrack.isLocal == true, let nid = targetTrack.numericId, nid > 0 {
            let script = """
            tell application "Music"
                try
                    if current playlist is not missing value then
                        set t to (first track of current playlist whose database ID is \(nid))
                        play t
                        return "ok"
                    end if
                end try
                try
                    set t to (first track of library playlist 1 whose database ID is \(nid))
                    play t
                    return "ok"
                end try
                try
                    set t to (first track whose database ID is \(nid))
                    play t
                    return "ok"
                end try
                return "error"
            end tell
            """
            let (ok, out) = AppleScriptExecutor.shared.execute(script)
            if ok && out?.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" {
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                return true
            }
        }

        // 2. Try by name & artist (ONLY if local track)
        let escN = targetTrack.name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escA = targetTrack.artist.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        if targetTrack.isLocal == true, !escN.isEmpty {
            let script = """
            tell application "Music"
                try
                    if current playlist is not missing value then
                        set matches to (every track of current playlist whose name is "\(escN)")
                        if (count of matches) > 0 then
                            play item 1 of matches
                            return "ok"
                        end if
                    end if
                end try
                try
                    set matches to (every track of library playlist 1 whose name is "\(escN)" and artist is "\(escA)")
                    if (count of matches) > 0 then
                        play item 1 of matches
                        return "ok"
                    end if
                end try
                try
                    set matches to (every track whose name contains "\(escN)")
                    if (count of matches) > 0 then
                        play item 1 of matches
                        return "ok"
                    end if
                end try
                return "error"
            end tell
            """
            let (ok, out) = AppleScriptExecutor.shared.execute(script)
            if ok && out?.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" {
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                return true
            }
        }

        // 3. Fallback to Cloud playback
        var playUrl = targetTrack.url ?? ""
        if playUrl.isEmpty, let nid = targetTrack.numericId, nid > 0 {
            playUrl = "https://music.apple.com/album/song/\(nid)"
        }
        let cloudOk = PlaybackRouter.shared.playCloudSync(url: playUrl, id: targetTrack.id, name: targetTrack.name, artist: targetTrack.artist)
        if cloudOk {
            PlaybackStateStore.shared.invalidateQueueCache()
            PlaybackStateStore.shared.invalidateStatusCache()
            return true
        }

        if index == 0 {
            return PlaybackTransportController.shared.nextTrack()
        }

        return false
    }

    public func playQueueIndexUnlocked(_ index: Int) -> Bool {
        guard index >= 0 && index < PlaybackStateStore.shared.activeCustomQueue.count else { return false }
        BitPerfectLogMonitor.shared.resetTrackState()
        let now = Date()
        PlaybackStateStore.shared.activeCustomQueueIndex = index
        PlaybackStateStore.shared.isCustomQueuePlayback = true
        PlaybackStateStore.shared.isRadioPlayback = false
        PlaybackStateStore.shared.isUserPaused = false
        PlaybackStateStore.shared.lastSkipTime = now
        PlaybackStateStore.shared.clearSeekTarget()

        let track = PlaybackStateStore.shared.activeCustomQueue[index]
        PlaybackStateStore.shared.lastWasPlayingCloud = false
        PlaybackStateStore.shared.lastCloudPlayTime = now
        PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
        PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false

        // Update upcoming & history tracks
        if index + 1 < PlaybackStateStore.shared.activeCustomQueue.count {
            PlaybackStateStore.shared.latestUpcomingTracks = Array(PlaybackStateStore.shared.activeCustomQueue[(index + 1)...])
        } else {
            PlaybackStateStore.shared.latestUpcomingTracks = []
        }
        if index > 0 {
            PlaybackStateStore.shared.latestHistoryTracks = Array(PlaybackStateStore.shared.activeCustomQueue[0..<index].reversed())
        } else {
            PlaybackStateStore.shared.latestHistoryTracks = []
        }

        if PlaybackRouter.shared.isTestingEnvironment {
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
            PlaybackStateStore.shared.invalidateQueueCache()
            PlaybackStateStore.shared.invalidateStatusCache()
            return true
        }

        // 1a. Fast local / cloud playback within "Очередь AMR" (SearchResults / Custom Queue)
        if let plName = PlaybackStateStore.shared.currentOriginalPlaylistName, plName == "Очередь AMR" {
            let targetTrackIndex = (track.index != nil && track.index! > 0) ? track.index! : (index + 1)
            let script = """
            tell application "Music"
              try
                set qPl to missing value
                repeat with p in (get every user playlist whose name is "Очередь AMR")
                    if (count of tracks of p) >= \(targetTrackIndex) then
                        set qPl to p
                        exit repeat
                    end if
                end repeat
                if qPl is not missing value then
                  set shuffle enabled to false
                  play track \(targetTrackIndex) of qPl
                  return "ok"
                end if
              on error
              end try
              return "error"
            end tell
            """
            let (ok, out) = AppleScriptExecutor.shared.execute(script)
            if ok && out?.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" {
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                return true
            }
        }

        // 1. Fast local library playback using track index (ONLY if track is local library track and original playlist is specified)
        if track.isLocal == true, let originalIndex = track.index, let plName = PlaybackStateStore.shared.currentOriginalPlaylistName, !plName.isEmpty, plName != "Очередь AMR" {
            let escapedPl = plName.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
            tell application "Music"
              stop
              try
                set p to (first playlist whose name is "\(escapedPl)")
              on error
                try
                  set p to playlist "\(escapedPl)"
                on error
                  try
                    set p to (first playlist whose name contains "\(escapedPl)")
                  on error
                    set p to missing value
                  end try
                end try
              end try
              if p is not missing value then
                try
                  play track \(originalIndex) of p
                  return "ok"
                on error
                  try
                    set t to track \(originalIndex) of p
                    play t
                    return "ok"
                  end try
                end try
              end if
              return "error"
            end tell
            """
            let (ok, out) = AppleScriptExecutor.shared.execute(script)
            if ok && out?.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" {
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                return true
            }
        }

        // 1b. Try by numeric database ID if available (ONLY for local library tracks)
        if track.isLocal == true, let nid = track.numericId, nid > 0 {
            let inMultiQueue = PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.isCustomQueuePlayback && PlaybackStateStore.shared.activeCustomQueue.count > 1
            }
            let deleteClause = inMultiQueue ? "" : """
              if qPl is not missing value then
                delete every track of qPl
              end if
            """
            let script = """
            tell application "Music"
              stop
              set qPl to missing value
              try
                set qPl to playlist "Очередь AMR"
              end try
              if qPl is missing value then
                try
                  set qPl to (make new user playlist with properties {name:"Очередь AMR"})
                end try
              end if
              \(deleteClause)

              set foundTrack to missing value
              try
                set foundTrack to (first track of library playlist 1 whose database ID is \(nid))
              end try
              if foundTrack is missing value then
                try
                  set foundTrack to (first track whose database ID is \(nid))
                end try
              end if

              if foundTrack is not missing value and qPl is not missing value then
                duplicate foundTrack to qPl
                set shuffle enabled to false
                play qPl
                return "ok"
              end if
              return "error"
            end tell
            """
            let (ok, out) = AppleScriptExecutor.shared.execute(script)
            if ok && out?.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" {
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                return true
            }
        }

        // 1c. Try by name and artist in local library if marked local
        if track.isLocal == true && !track.name.isEmpty {
            let escN = track.name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let escA = track.artist.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let artistClause = escA.isEmpty ? "" : " and artist is \"\(escA)\""
            let script = """
            tell application "Music"
              stop
              try
                set t to (first track of library playlist 1 whose name is "\(escN)"\(artistClause))
                play t
                return "ok"
              end try
              return "error"
            end tell
            """
            let (ok, out) = AppleScriptExecutor.shared.execute(script)
            if ok && out?.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" {
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                return true
            }
        }

        // 2. Fallback to Cloud / URL
        let nextIdx = index + 1
        let queueSnapshot = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.activeCustomQueue }
        if nextIdx < queueSnapshot.count {
            let nextTrack = queueSnapshot[nextIdx]
            Task.detached(priority: .utility) {
                _ = await MusicKitManager.shared.resolveTrackStation(title: nextTrack.name, artist: nextTrack.artist)
            }
        }
        return PlaybackRouter.shared.playCloudSync(url: track.url, id: track.id, name: track.name, artist: track.artist)
    }

    public func startQueueMonitoring() {
        if PlaybackRouter.shared.isTestingEnvironment {
            return
        }
        stopQueueMonitoring()
        let timer = DispatchSource.makeTimerSource(queue: queueTimerQueue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            self?.checkAndAutoAdvanceCloudQueue()
        }
        timer.resume()
        self.queueTimer = timer
    }

    public func stopQueueMonitoring() {
        queueTimer?.cancel()
        queueTimer = nil
    }

    private func normalizeTrackTitle(_ title: String) -> String {
        var t = title.lowercased()
        if let regex = try? NSRegularExpression(pattern: "\\s*[\\[\\(].*?[\\]\\)]", options: []) {
            t = regex.stringByReplacingMatches(in: t, options: [], range: NSRange(location: 0, length: t.utf16.count), withTemplate: "")
        }
        if let dashIdx = t.range(of: " - ") {
            t = String(t[..<dashIdx.lowerBound])
        }
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        t = t.components(separatedBy: allowed.inverted).joined()
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isTrackMatching(expected: TrackInfo, candidateName: String, candidateArtist: String? = nil) -> Bool {
        let cn = candidateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cn.isEmpty else { return false }
        let en = expected.name.trimmingCharacters(in: .whitespacesAndNewlines)

        if en.localizedCaseInsensitiveCompare(cn) == .orderedSame {
            return true
        }

        let normEn = normalizeTrackTitle(en)
        let normCn = normalizeTrackTitle(cn)
        if !normEn.isEmpty && normEn == normCn {
            return true
        }

        if let ca = candidateArtist?.trimmingCharacters(in: .whitespacesAndNewlines), !ca.isEmpty {
            let ea = expected.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let normEa = ea.lowercased()
            let normCa = ca.lowercased()
            let artistsMatch = !normEa.isEmpty && !normCa.isEmpty && (normEa == normCa || normEa.contains(normCa) || normCa.contains(normEa))
            if artistsMatch {
                if !normEn.isEmpty && !normCn.isEmpty {
                    if normEn.hasPrefix(normCn) || normCn.hasPrefix(normEn) {
                        let minLen = min(normEn.count, normCn.count)
                        let maxLen = max(normEn.count, normCn.count)
                        if minLen >= 3 && Double(minLen) / Double(maxLen) >= 0.6 {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    public func handleTrackNotification(userInfo: [AnyHashable: Any]?) {
        guard let info = userInfo else { return }
        let (isCustom, hasQueue, activeIdx, queueTracks, lastPlayTime, confirmed, isTransitioning, isUserPaused) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isCustomQueuePlayback,
                !PlaybackStateStore.shared.activeCustomQueue.isEmpty,
                PlaybackStateStore.shared.activeCustomQueueIndex,
                PlaybackStateStore.shared.activeCustomQueue,
                PlaybackStateStore.shared.lastCloudPlayTime,
                PlaybackStateStore.shared.currentTrackPlaybackConfirmed,
                PlaybackStateStore.shared.isTransitioningTrack,
                PlaybackStateStore.shared.isUserPaused
            )
        }
        guard isCustom && hasQueue && activeIdx < queueTracks.count else { return }

        let state = (info["Player State"] as? String)?.lowercased() ?? ""
        if isUserPaused || state == "paused" {
            return
        }
        let trackName = (info["Name"] as? String) ?? ""
        let artistName = info["Artist"] as? String
        let timeSincePlay = Date().timeIntervalSince(lastPlayTime ?? Date.distantPast)

        // 1. If Music.app is stopped, ONLY advance if playback was confirmed AND track played to the end!
        // If unconfirmed or stopped early (< 15s), Music.app is buffering, paused, or switching streams, so do NOT skip!
        if state == "stopped" {
            if timeSincePlay < 15.0 {
                return
            }
            let alreadyTriggered = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack }
            let status = PlayerStatusEngine.shared.getPlayerStatus()
            let dur = status.duration > 0 ? status.duration : (queueTracks[activeIdx].duration > 0 ? queueTracks[activeIdx].duration : 180.0)
            let pos = status.position
            let isNearEnd = (dur > 15.0 && pos >= dur - 3.0) || (dur > 15.0 && timeSincePlay >= dur - 3.0) || (pos >= 30.0 && pos >= dur * 0.9)
            if confirmed && !alreadyTriggered && isNearEnd && activeIdx + 1 < queueTracks.count {
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = true
                    PlaybackStateStore.shared.lastWasPlayingCloud = false
                    PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
                    _ = self.playQueueIndexUnlocked(activeIdx + 1)
                }
            }
            return
        }

        guard !trackName.isEmpty else { return }
        let expected = queueTracks[activeIdx]

        // 2. If track matches expected track, confirm playback and mark playing
        if isTrackMatching(expected: expected, candidateName: trackName, candidateArtist: artistName) {
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                PlaybackStateStore.shared.lastWasPlayingCloud = true
                PlaybackStateStore.shared.lastSkipTime = .distantPast
            }
            return
        }

        // 3. During transition to target track, ignore mismatch from draining track
        if isTransitioning || (!confirmed && timeSincePlay < 3.5) {
            return
        }

        // 4. If track is a past track in our custom queue, do not roll back and do not steer
        if queueTracks[..<activeIdx].contains(where: { isTrackMatching(expected: $0, candidateName: trackName, candidateArtist: artistName) }) {
            return
        }

        // 5. If track matches forward in our custom queue (within next 2 tracks), sync index to it
        let forwardWindowEnd = min(activeIdx + 3, queueTracks.count)
        if activeIdx < forwardWindowEnd,
           let relativeIdx = queueTracks[activeIdx..<forwardWindowEnd].firstIndex(where: { isTrackMatching(expected: $0, candidateName: trackName, candidateArtist: artistName) }) {
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.activeCustomQueueIndex = relativeIdx
                PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                PlaybackStateStore.shared.lastWasPlayingCloud = true
                PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
            }
            return
        }

        // 6. Track is foreign (not matching anything in customQueue):
        // If Apple Music started an Autoplay radio track while we still have tracks left in customQueue,
        // immediately stop foreign audio and advance to the next custom queue track!
        if activeIdx + 1 < queueTracks.count && !isTransitioning {
            let lastSkip = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.lastSkipTime }
            if Date().timeIntervalSince(lastSkip) < 2.5 {
                return
            }
            NSLog("[QueueManager] 🛡 Notification: Foreign track '%@' by '%@' while in custom queue! Stopping audio and advancing to %d: '%@'",
                  trackName, artistName ?? "", activeIdx + 1, queueTracks[activeIdx + 1].name)
            _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop")
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.lastSkipTime = Date()
                PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = true
                PlaybackStateStore.shared.lastWasPlayingCloud = false
                PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
                _ = self.playQueueIndexUnlocked(activeIdx + 1)
            }
            return
        }

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
            PlaybackStateStore.shared.lastWasPlayingCloud = true
            PlaybackStateStore.shared.lastSkipTime = .distantPast
        }
    }

    public func checkAndAutoAdvanceCloudQueue() {
        let (isCustom, hasQueue, activeIdx, queueTracks, lastPlayTime, lastWasPlaying, confirmed, isTransitioning, isUserPaused) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isCustomQueuePlayback,
                !PlaybackStateStore.shared.activeCustomQueue.isEmpty,
                PlaybackStateStore.shared.activeCustomQueueIndex,
                PlaybackStateStore.shared.activeCustomQueue,
                PlaybackStateStore.shared.lastCloudPlayTime,
                PlaybackStateStore.shared.lastWasPlayingCloud,
                PlaybackStateStore.shared.currentTrackPlaybackConfirmed,
                PlaybackStateStore.shared.isTransitioningTrack,
                PlaybackStateStore.shared.isUserPaused
            )
        }
        guard isCustom && hasQueue else {
            stopQueueMonitoring()
            return
        }

        if isUserPaused {
            return
        }

        let status = PlayerStatusEngine.shared.getPlayerStatus()
        let pState = status.playerState
        if pState == "paused" {
            return
        }

        let pos = status.position
        var dur = status.duration

        if dur <= 0 && activeIdx < queueTracks.count {
            dur = queueTracks[activeIdx].duration
        }

        let timeSincePlay = Date().timeIntervalSince(lastPlayTime ?? Date.distantPast)
        let curTrackName = status.track?.name ?? ""
        let curArtist = status.track?.artist ?? ""

        if pState == "playing" {
            if !curTrackName.isEmpty && activeIdx < queueTracks.count {
                let expectedTrack = queueTracks[activeIdx]
                let matchesExpected = isTrackMatching(expected: expectedTrack, candidateName: curTrackName, candidateArtist: curArtist)

                if matchesExpected {
                    PlaybackStateStore.shared.withLock {
                        PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                        PlaybackStateStore.shared.lastWasPlayingCloud = true
                        PlaybackStateStore.shared.lastSkipTime = .distantPast
                        if pos >= 1.0 && pos < (dur > 3.0 ? dur - 3.0 : 1000.0) {
                            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
                        }
                    }
                } else if isTransitioning || (!confirmed && timeSincePlay < 3.5) {
                    // Still transitioning to activeIdx, ignore mismatch from draining track
                    return
                } else if queueTracks[..<activeIdx].contains(where: { isTrackMatching(expected: $0, candidateName: curTrackName, candidateArtist: curArtist) }) {
                    // Past track in custom queue, do NOT roll forward or steer as foreign track
                    return
                } else if activeIdx < min(activeIdx + 3, queueTracks.count),
                          let relativeIdx = queueTracks[activeIdx..<min(activeIdx + 3, queueTracks.count)].firstIndex(where: { isTrackMatching(expected: $0, candidateName: curTrackName, candidateArtist: curArtist) }) {
                    // Synced forward to an immediate next track in the queue
                    PlaybackStateStore.shared.withLock {
                        PlaybackStateStore.shared.activeCustomQueueIndex = relativeIdx
                        PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                        PlaybackStateStore.shared.lastWasPlayingCloud = true
                        PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
                    }
                    return
                } else {
                    // Foreign track playing while in custom queue
                    if activeIdx + 1 < queueTracks.count && !isTransitioning {
                        let lastSkip = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.lastSkipTime }
                        if Date().timeIntervalSince(lastSkip) < 2.5 {
                            return
                        }
                        // Apple Music Autoplay started a foreign radio track while queue still has songs!
                        NSLog("[QueueManager] 🛡 Poller: Foreign radio track '%@' by '%@' while in custom queue! Stopping audio and advancing to %d: '%@'",
                              curTrackName, curArtist, activeIdx + 1, queueTracks[activeIdx + 1].name)
                        _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop")
                        PlaybackStateStore.shared.withLock {
                            PlaybackStateStore.shared.lastSkipTime = Date()
                            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = true
                            PlaybackStateStore.shared.lastWasPlayingCloud = false
                            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
                            _ = self.playQueueIndexUnlocked(activeIdx + 1)
                        }
                        return
                    } else {
                        PlaybackStateStore.shared.withLock {
                            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                            PlaybackStateStore.shared.lastWasPlayingCloud = true
                            PlaybackStateStore.shared.lastSkipTime = .distantPast
                        }
                    }
                }
            }

            // Smooth advance before song finishes completely (3.0s before end)
            let alreadyTriggered = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack }
            if confirmed && !alreadyTriggered && dur > 5.0 && pos > 1.0 && timeSincePlay >= 2.0 && (pos >= (dur - 3.0) || timeSincePlay >= (dur - 3.0)) {
                if activeIdx + 1 < queueTracks.count {
                    _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop")
                    PlaybackStateStore.shared.withLock {
                        PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = true
                        PlaybackStateStore.shared.lastWasPlayingCloud = false
                        PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
                        NSLog("[QueueManager] ⏭ Preemptively auto-advancing (smooth) to index %d: '%@'", activeIdx + 1, queueTracks[activeIdx + 1].name)
                        _ = self.playQueueIndexUnlocked(activeIdx + 1)
                    }
                } else {
                    // Queue finished! Transition to artist radio!
                    let lastTrack = queueTracks[activeIdx]
                    NSLog("[QueueManager] 📻 Custom queue reached end at index %d! Auto-transitioning to artist radio for '%@'", activeIdx, lastTrack.artist)
                    PlaybackStateStore.shared.withLock {
                        PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = true
                        PlaybackStateStore.shared.isCustomQueuePlayback = false
                        PlaybackStateStore.shared.activeCustomQueue.removeAll()
                        PlaybackStateStore.shared.activeCustomQueueIndex = 0
                    }
                    self.stopQueueMonitoring()
                    Task.detached(priority: .userInitiated) {
                        _ = await PlaybackRouter.shared.playStation(
                            url: "",
                            name: "Станция «\(lastTrack.artist)»",
                            type: "artist",
                            trackTitle: lastTrack.name,
                            artistName: lastTrack.artist
                        )
                    }
                }
            }
        } else if pState == "stopped" && lastWasPlaying && confirmed {
            // Natural track finish: only advance if the track was confirmed playing AND actually reached near the end
            let alreadyTriggered = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack }
            let isNearEnd = (dur > 15.0 && pos >= dur - 3.0) || (dur > 15.0 && timeSincePlay >= dur - 3.0) || (pos >= 30.0 && pos >= dur * 0.9)
            if isNearEnd && !alreadyTriggered {
                if activeIdx + 1 < queueTracks.count {
                    PlaybackStateStore.shared.withLock {
                        PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = true
                        PlaybackStateStore.shared.lastWasPlayingCloud = false
                        PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
                        NSLog("[QueueManager] ⏭ Auto-advancing (stopped) to index %d: '%@'", activeIdx + 1, queueTracks[activeIdx + 1].name)
                        _ = self.playQueueIndexUnlocked(activeIdx + 1)
                    }
                } else {
                    let lastTrack = queueTracks[activeIdx]
                    NSLog("[QueueManager] 📻 Custom queue finished (stopped)! Transitioning to artist radio for '%@'", lastTrack.artist)
                    PlaybackStateStore.shared.withLock {
                        PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = true
                        PlaybackStateStore.shared.isCustomQueuePlayback = false
                        PlaybackStateStore.shared.activeCustomQueue.removeAll()
                        PlaybackStateStore.shared.activeCustomQueueIndex = 0
                    }
                    self.stopQueueMonitoring()
                    Task.detached(priority: .userInitiated) {
                        _ = await PlaybackRouter.shared.playStation(
                            url: "",
                            name: "Станция «\(lastTrack.artist)»",
                            type: "artist",
                            trackTitle: lastTrack.name,
                            artistName: lastTrack.artist
                        )
                    }
                }
            }
        }
    }

    // MARK: - History Playback

    public func playHistoryTrack(name: String, artist: String) async -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return false }

        let escN = cleanName.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escA = cleanArtist.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Music"
            try
                set foundTracks to (every track of library playlist 1 whose name is "\(escN)" and artist is "\(escA)")
                if (count of foundTracks) > 0 then
                    play item 1 of foundTracks
                    return "ok"
                end if
            end try
            try
                set foundTracks to (every track of library playlist 1 whose name is "\(escN)")
                if (count of foundTracks) > 0 then
                    play item 1 of foundTracks
                    return "ok"
                end if
            end try
            return "not_found"
        end tell
        """
        let (ok, res) = AppleScriptExecutor.shared.execute(script)
        if ok, res?.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" {
            return true
        }

        return await PlaybackRouter.shared.playCloud(url: nil, id: nil, name: cleanName, artist: cleanArtist)
    }

    public func playHistoryIndex(_ index: Int) async -> Bool {
        PlaybackStateStore.shared.invalidateQueueCache()
        let history = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.latestHistoryTracks }
        guard index >= 0 && index < history.count else { return false }
        let track = history[index]
        return await playHistoryTrack(name: track.name, artist: track.artist)
    }

    public func playRecentTracks(shuffle: Bool) async -> Bool {
        let recentTracks = getRecentlyPlayed(limit: 30)
        guard !recentTracks.isEmpty else { return false }
        return PlaybackRouter.shared.playCustomTracks(recentTracks, startIndex: 0, shuffle: shuffle, queueName: "Вы недавно слушали")
    }
}
