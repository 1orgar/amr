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
    var queueTimer: DispatchSourceTimer?
    let queueTimerQueue = DispatchQueue(label: "org.ksholokhov.amr.queue.timer", qos: .utility)

    private init() {}

    // MARK: - Recently Played

    public func getRecentlyPlayed(limit: Int = 30) -> [TrackInfo] {
        let hist = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.latestHistoryTracks }
        if !hist.isEmpty {
            return Array(hist.prefix(limit))
        }
        var tracks = LibraryService.shared.getPlaylistTracks(name: "Недавно добавленные")
        if tracks.isEmpty {
            tracks = LibraryService.shared.getPlaylistTracks(name: "Recently Added")
        }
        if tracks.isEmpty {
            tracks = LibraryService.shared.getPlaylistTracks(name: "Любимые песни")
        }
        if tracks.isEmpty {
            tracks = LibraryService.shared.getPlaylistTracks(name: "Favorites")
        }
        if tracks.isEmpty {
            tracks = Array(LibraryService.shared.getLibrarySongs().prefix(limit))
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

        let (hasCustomQueue, customQueue, customQueueName, activeCustomIdx, isBusyOrAMRQueue) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty,
                PlaybackStateStore.shared.activeCustomQueue,
                PlaybackStateStore.shared.activeCustomQueueName,
                PlaybackStateStore.shared.activeCustomQueueIndex,
                PlaybackStateStore.shared.isTransitioningTrack ||
                    PlaybackStateStore.shared.isStagingCloudTrack ||
                    !PlaybackStateStore.shared.currentTrackPlaybackConfirmed ||
                    PlaybackStateStore.shared.currentOriginalPlaylistName == "Очередь AMR"
            )
        }

        let curTrack = (!hasCustomQueue || !isBusyOrAMRQueue) ? app.currentTrack : nil
        var curName = curTrack?.sbName ?? ""
        var curArtist = curTrack?.sbArtist ?? ""
        var curAlbum = curTrack?.sbAlbum ?? ""
        var curDbId = (curTrack?.value(forKey: "databaseID") as? Int) ?? 0

        if hasCustomQueue && isBusyOrAMRQueue && activeCustomIdx >= 0 && activeCustomIdx < customQueue.count {
            let expectedTrack = customQueue[activeCustomIdx]
            curName = expectedTrack.name
            curArtist = expectedTrack.artist
            curAlbum = expectedTrack.album
            curDbId = expectedTrack.numericId ?? curDbId
        } else if curName.isEmpty {
            let status = PlayerStatusEngine.shared.getPlayerStatus()
            if let tr = status.track, !tr.name.isEmpty {
                curName = tr.name
                curArtist = tr.artist
                curAlbum = tr.album
                curDbId = tr.numericId ?? curDbId
            }
        }

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
                if activeIdx < customQueue.count && isTrackMatching(expected: customQueue[activeIdx], candidateName: curName, candidateArtist: curArtist) {
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
                recentHistory = Array(formattedTracks[0..<matchedIdx].reversed().prefix(25))
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

        let isStreamTrack = (curTrack != nil && curTrack?.value(forKey: "location") == nil)
        var curPlNameRaw = (app.currentPlaylist?.value(forKey: "name") as? String) ?? ""
        if curPlNameRaw.isEmpty || curPlNameRaw == "Музыка" || curPlNameRaw == "Music" || curPlNameRaw == "Медиатека" {
            let status = PlayerStatusEngine.shared.getPlayerStatus()
            if !status.playlist.isEmpty && status.playlist != "Apple Music Radio" && status.playlist != "Музыка" && status.playlist != "Music" && status.playlist != "Медиатека" {
                curPlNameRaw = status.playlist
            }
        }
        var isRadioDetected = isRadio
        if !curPlNameRaw.isEmpty && curPlNameRaw != "Музыка" && curPlNameRaw != "Music" && curPlNameRaw != "Медиатека" {
            isRadioDetected = false
        } else if let orig = origPl, !orig.isEmpty {
            isRadioDetected = false
        } else if isStreamTrack && curPlNameRaw.isEmpty {
            let curKind = ((curTrack?.value(forKey: "kind") as? String) ?? "").lowercased()
            let curDur = (curTrack?.value(forKey: "duration") as? Double) ?? 0
            let lowerName = curName.lowercased()
            if curKind.contains("stream") || curKind.contains("поток") || lowerName.hasPrefix("станция:") || lowerName.hasPrefix("station:") || curDur <= 0 {
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
        if tracksList.isEmpty && !curPlName.isEmpty && curPlName != "Музыка" && curPlName != "Music" && curPlName != "Медиатека" {
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
}
