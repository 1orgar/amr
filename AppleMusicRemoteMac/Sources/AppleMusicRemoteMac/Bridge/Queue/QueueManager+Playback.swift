//
//  QueueManager+Playback.swift
//  AppleMusicRemoteMac
//

import Foundation
import ScriptingBridge

extension QueueManager {
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
            return self.playQueueIndexUnlocked(targetIdx)
        }

        let q = await getPlaybackQueue()
        guard index >= 0 && index < q.upcomingTracks.count else { return false }

        if !q.tracks.isEmpty {
            let targetIdx = q.currentIndex + 1 + index
            if targetIdx >= 0 && targetIdx < q.tracks.count {
                NSLog("[QueueManager] 🎵 Jumping to track index %d in playlist '%@' via custom queue", targetIdx + 1, q.playlist)
                return PlaybackRouter.shared.playCustomTracks(q.tracks, startIndex: targetIdx, shuffle: false, queueName: q.playlist)
            }
        }

        let targetTrack = q.upcomingTracks[index]

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
        let stateInfo: (track: TrackInfo, gen: UInt64)? = PlaybackStateStore.shared.withLock {
            guard index >= 0 && index < PlaybackStateStore.shared.activeCustomQueue.count else { return nil }
            let now = Date()
            PlaybackStateStore.shared.playbackGeneration &+= 1
            let gen = PlaybackStateStore.shared.playbackGeneration
            PlaybackStateStore.shared.isStagingCloudTrack = false
            PlaybackStateStore.shared.activeCustomQueueIndex = index
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.isRadioPlayback = false
            PlaybackStateStore.shared.isUserPaused = false
            PlaybackStateStore.shared.lastSkipTime = now
            PlaybackStateStore.shared.clearSeekTarget()

            let t = PlaybackStateStore.shared.activeCustomQueue[index]
            PlaybackStateStore.shared.lastWasPlayingCloud = false
            PlaybackStateStore.shared.lastCloudPlayTime = now
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
            PlaybackStateStore.shared.lastKnownPosition = 0.0
            if t.isLocal == true || MusicKitManager.shared.hasUserToken {
                PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
            } else {
                PlaybackStateStore.shared.currentOriginalPlaylistName = nil
            }

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
            return (t, gen)
        }
        guard let (track, gen) = stateInfo else { return false }
        let canonicalKey = !track.name.isEmpty
            ? "\(track.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()):\(track.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
            : nil
        let cachedFmt = BitPerfectLogMonitor.shared.getCachedFormat(artist: track.artist, title: track.name)
        BitPerfectLogMonitor.shared.resetTrackState(trackKey: canonicalKey, expectedSampleRate: cachedFmt?.sampleRate, expectedBitDepth: cachedFmt?.bitDepth)

        if ExternalAmpTCPController.shared.isActive,
           ExternalAmpTCPController.shared.isSoundCheckEnabled,
           !PlaybackRouter.shared.isTestingEnvironment,
           !track.name.isEmpty {
            let resolvedCatId = track.catalogId ?? (AppleSoundCheckService.isValidCatalogId(track.id) ? track.id : nil)
            let isStagedTemp = track.numericId.map { nid in
                PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.stagedTemporaryTrackDbIds.contains(nid) }
            } ?? false
            let isTrulyLocal = track.isLocal == true
                && (track.url == nil || track.url?.isEmpty == true)
                && !AppleSoundCheckService.isValidCatalogId(track.id)
                && !isStagedTemp
            AppleSoundCheckService.shared.syncCurrentTrack(
                trackKey: canonicalKey ?? "\(track.artist):\(track.name)",
                trackId: resolvedCatId ?? track.persistentId ?? track.id,
                catalogId: resolvedCatId,
                name: track.name,
                artist: track.artist,
                album: track.album,
                isLocal: isTrulyLocal
            )
            let upcomingToPrefetch: [TrackInfo] = PlaybackStateStore.shared.withLock {
                let q = PlaybackStateStore.shared.activeCustomQueue
                var list = [TrackInfo]()
                for offsetIdx in 1...2 {
                    let nextIdx = index + offsetIdx
                    if nextIdx >= 0 && nextIdx < q.count {
                        list.append(q[nextIdx])
                    }
                }
                return list
            }
            for nextTr in upcomingToPrefetch {
                let nextCatId = nextTr.catalogId ?? (AppleSoundCheckService.isValidCatalogId(nextTr.id) ? nextTr.id : nil)
                AppleSoundCheckService.shared.prefetchTrack(
                    trackId: nextCatId ?? nextTr.persistentId ?? nextTr.id,
                    catalogId: nextCatId,
                    name: nextTr.name,
                    artist: nextTr.artist,
                    album: nextTr.album
                )
            }
        }

        if PlaybackRouter.shared.isTestingEnvironment {
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
            }
            PlaybackStateStore.shared.invalidateQueueCache()
            PlaybackStateStore.shared.invalidateStatusCache()
            return true
        }

        if queueTimer == nil {
            startQueueMonitoring()
        }

        // Proactively trigger search or Infinite AI Wave auto-paging if user jumps/skips into the last 3 tracks
        let (searchQuery, isFetchingSearch, curatorPrompt, isFetchingCurator, qCount) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.activeSearchQuery,
                PlaybackStateStore.shared.isFetchingNextSearchPage,
                PlaybackStateStore.shared.activeCuratorPrompt,
                PlaybackStateStore.shared.isFetchingNextCuratorPage,
                PlaybackStateStore.shared.activeCustomQueue.count
            )
        }
        if index >= max(0, qCount - 3) {
            if let q = searchQuery, !q.isEmpty, !isFetchingSearch {
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.isFetchingNextSearchPage = true
                }
                Task.detached(priority: .userInitiated) {
                    await PlaybackRouter.shared.fetchAndAppendNextSearchResults(query: q)
                }
            } else if let cp = curatorPrompt, !cp.isEmpty, !isFetchingCurator {
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.isFetchingNextCuratorPage = true
                }
                Task.detached(priority: .userInitiated) {
                    await PlaybackRouter.shared.fetchAndAppendNextCuratorResults(prompt: cp)
                }
            }
        }

        // 1a. Try by numeric database ID if available and valid local ID (< 10_000_000) via "Очередь AMR" for deterministic 1-track isolation
        if let nid = track.numericId, nid > 0, nid < 10_000_000 {
            if PlaybackRouter.shared.playTrackByDatabaseIdViaAMRQueue(nid, generation: gen) {
                let now = Date()
                PlaybackStateStore.shared.withLock {
                    if PlaybackStateStore.shared.playbackGeneration == gen {
                        PlaybackStateStore.shared.lastCloudPlayTime = now
                        PlaybackStateStore.shared.lastSkipTime = now
                        PlaybackStateStore.shared.lastWasPlayingCloud = true
                        PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                    }
                }
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
                PlaybackRouter.shared.prestageUpcomingCloudTracks(fromIndex: index + 1, count: 4, expectedGeneration: gen)
                return true
            }
        }

        // 1b. Try finding in Music.app by name and artist (including pre-staged cloud tracks or tracks with edition suffixes) and play via "Очередь AMR"
        if !track.name.isEmpty, PlaybackRouter.shared.urlOpener == nil {
            let prefDbId = (track.numericId != nil && track.numericId! > 0 && track.numericId! < 10_000_000) ? track.numericId : nil
            if let foundDbId = MusicKitManager.shared.findTrackDatabaseIdInMusicApp(
                name: track.name,
                artist: track.artist,
                preferredDbId: prefDbId,
                checkSubscriptionPlaylists: false
            ), foundDbId > 0 {
                let isCurrentGen = PlaybackStateStore.shared.withLock { () -> Bool in
                    guard PlaybackStateStore.shared.playbackGeneration == gen else { return false }
                    if index >= 0 && index < PlaybackStateStore.shared.activeCustomQueue.count {
                        PlaybackStateStore.shared.activeCustomQueue[index].numericId = foundDbId
                        PlaybackStateStore.shared.activeCustomQueue[index].isLocal = true
                    }
                    return true
                }
                if isCurrentGen && PlaybackRouter.shared.playTrackByDatabaseIdViaAMRQueue(foundDbId, generation: gen) {
                    let now = Date()
                    PlaybackStateStore.shared.withLock {
                        if PlaybackStateStore.shared.playbackGeneration == gen {
                            PlaybackStateStore.shared.lastCloudPlayTime = now
                            PlaybackStateStore.shared.lastSkipTime = now
                            PlaybackStateStore.shared.lastWasPlayingCloud = true
                            PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                        }
                    }
                    PlaybackStateStore.shared.invalidateQueueCache()
                    PlaybackStateStore.shared.invalidateStatusCache()
                    WebSocketServer.shared.broadcastStatus(includeQueue: true)
                    PlaybackRouter.shared.prestageUpcomingCloudTracks(fromIndex: index + 1, count: 4, expectedGeneration: gen)
                    return true
                }
            }
        }

        // 2. Fallback to Cloud / URL (stages track into Music.app if user token is present, and plays via "Очередь AMR")
        let started = PlaybackRouter.shared.playCloudSync(url: track.url, id: track.id, name: track.name, artist: track.artist)
        if started {
            let isCurrentGen = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.playbackGeneration == gen }
            guard isCurrentGen else { return false }
            PlaybackStateStore.shared.invalidateQueueCache()
            PlaybackStateStore.shared.invalidateStatusCache()
            WebSocketServer.shared.broadcastStatus(includeQueue: true)
            PlaybackRouter.shared.prestageUpcomingCloudTracks(fromIndex: index + 1, count: 4, expectedGeneration: gen)
            let nextIdx = index + 1
            let queueSnapshot = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.activeCustomQueue }
            if nextIdx < queueSnapshot.count {
                let nextTrack = queueSnapshot[nextIdx]
                Task.detached(priority: .utility) {
                    _ = await MusicKitManager.shared.resolveTrackStation(title: nextTrack.name, artist: nextTrack.artist)
                }
            }
        }
        return started
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
        let (hasCustom, curCustomIndex, customCount) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty,
                PlaybackStateStore.shared.activeCustomQueueIndex,
                PlaybackStateStore.shared.activeCustomQueue.count
            )
        }
        if hasCustom {
            let targetIdx = curCustomIndex - 1 - index
            guard targetIdx >= 0 && targetIdx < customCount else { return false }
            return self.playQueueIndexUnlocked(targetIdx)
        }
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
