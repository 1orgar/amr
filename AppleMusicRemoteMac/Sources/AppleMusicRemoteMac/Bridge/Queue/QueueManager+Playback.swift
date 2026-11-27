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
            PlaybackStateStore.shared.lastSkipTime = Date()
            PlaybackStateStore.shared.repeatOnePinnedTrack = nil
            return (
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

    public func playQueueIndexUnlocked(_ index: Int, incrementGeneration: Bool = true, unavailableSkipDepth: Int = 0) -> Bool {
        let stateInfo: (track: TrackInfo, gen: UInt64)? = PlaybackStateStore.shared.withLock {
            guard index >= 0 && index < PlaybackStateStore.shared.activeCustomQueue.count else { return nil }
            let now = Date()
            let t = PlaybackStateStore.shared.activeCustomQueue[index]
            if incrementGeneration {
                let prevCandidate: TrackInfo? = {
                    if let cached = PlaybackStateStore.shared.lastPlayerStatusCache?.status.track, !cached.name.isEmpty {
                        return cached
                    }
                    let prevIdx = PlaybackStateStore.shared.activeCustomQueueIndex
                    if prevIdx >= 0 && prevIdx < PlaybackStateStore.shared.activeCustomQueue.count {
                        return PlaybackStateStore.shared.activeCustomQueue[prevIdx]
                    }
                    return nil
                }()
                if let prev = prevCandidate,
                   !self.isTrackMatching(expected: t, candidateName: prev.name, candidateArtist: prev.artist, candidateDbId: prev.numericId) {
                    PlaybackStateStore.shared.transitionPreviousTrackKey = self.canonicalForeignTrackKey(name: prev.name, artist: prev.artist)
                } else {
                    PlaybackStateStore.shared.transitionPreviousTrackKey = nil
                }
                PlaybackStateStore.shared.activeTrackTitleVariants = []
                PlaybackStateStore.shared.triedAlternateCloudSeedForCurrentTrack = false
                PlaybackStateStore.shared.alternateCloudSeedAttemptCount = 0
                PlaybackStateStore.shared.triedCloudSeedIdsForCurrentTrack.removeAll()
                PlaybackStateStore.shared.playbackGeneration &+= 1
            }
            let gen = PlaybackStateStore.shared.playbackGeneration
            PlaybackStateStore.shared.isStagingCloudTrack = false
            PlaybackStateStore.shared.isActivelyStagingInBuffer = false
            let hasReadyDbId = (t.isLocal == true && t.numericId != nil && t.numericId! > 0 && t.numericId! < 10_000_000)
            PlaybackStateStore.shared.activeLoadingStage = hasReadyDbId ? nil : "cloud"
            PlaybackStateStore.shared.activeLoadingStartedAt = hasReadyDbId ? nil : now
            PlaybackStateStore.shared.activeCustomQueueIndex = index
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.isRadioPlayback = false
            PlaybackStateStore.shared.isUserPaused = false
            PlaybackStateStore.shared.lastSkipTime = now
            PlaybackStateStore.shared.clearSeekTarget()

            PlaybackStateStore.shared.lastWasPlayingCloud = false
            PlaybackStateStore.shared.lastCloudPlayTime = now
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
            PlaybackStateStore.shared.lastConfirmedTrackTime = .distantPast
            PlaybackStateStore.shared.lastForeignInterceptTime = .distantPast
            PlaybackStateStore.shared.lastForeignInterceptKey = nil
            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
            PlaybackStateStore.shared.lastKnownPosition = 0.0
            PlaybackStateStore.shared.scheduledSmartTransitionStart = nil
            PlaybackStateStore.shared.nativeQueuedUpcomingCatalogIds.removeAll()
            PlaybackStateStore.shared.activeOverlapTransition = nil
            PlaybackStateStore.shared.currentOriginalPlaylistName = (t.isLocal == true || MusicKitManager.shared.hasUserToken) ? "Очередь AMR" : nil

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
        let initialCatalogId = MusicKitManager.extractNumericCatalogId(from: track)
        let cachedFmt = BitPerfectLogMonitor.shared.getCachedFormat(artist: track.artist, title: track.name, catalogId: initialCatalogId)
        if PlaybackRouter.shared.isTestingEnvironment || PlaybackRouter.shared.urlOpener != nil {
            BitPerfectLogMonitor.shared.resetTrackState(
                trackKey: canonicalKey,
                catalogId: initialCatalogId,
                expectedSampleRate: cachedFmt?.sampleRate,
                expectedBitDepth: cachedFmt?.bitDepth,
                clearPrebuffer: true
            )
        } else {
            BitPerfectLogMonitor.shared.beginExplicitTrackSwitch()
        }

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
                isLocal: isTrulyLocal,
                isExplicitTransition: true
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
                PlaybackStateStore.shared.lastConfirmedTrackTime = Date()
            }
            PlaybackStateStore.shared.invalidateQueueCache()
            PlaybackStateStore.shared.invalidateStatusCache()
            return true
        }

        if timerLock.withLock({ queueTimer == nil }) {
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

        if incrementGeneration && PlaybackRouter.shared.urlOpener == nil {
            PlaybackStateStore.shared.invalidateQueueCache()
            PlaybackStateStore.shared.invalidateStatusCache()
            WebSocketServer.shared.broadcastStatus(includeQueue: true)
        }

        let trackCatalogId = MusicKitManager.extractNumericCatalogId(from: track)
        let cachedVariants = MusicKitManager.shared.cachedTitleVariants(catalogId: trackCatalogId)

        // 1a. Immediate Music.app Lossless/Hi-Res fast path (~15 ms): downloaded local files (`isLocal == true` & not cloud-only `shared track`) ONLY!
        var hadStaleNumericId = false
        var fallbackCloudLibraryDbId: Int? = nil
        let itDownloadedStatus: Bool? = (track.numericId != nil)
            ? ITLibraryReader.shared.downloadedFileTrackStatus(forTrackId: track.numericId!)
            : nil
        if itDownloadedStatus == false, let cloudLibNid = track.numericId, cloudLibNid > 0, cloudLibNid < 10_000_000 {
            // Track is saved in Apple Music Library (`ITLibrary`) as a cloud-only item without a downloaded local file;
            // play via native `SystemMusicPlayerBridge` first to avoid `Music.app` `AutoPlay` XPC queue deadlocks,
            // keeping `cloudLibNid` as fallback for private iCloud-uploaded audio.
            fallbackCloudLibraryDbId = cloudLibNid
        } else if track.isLocal == true, let nid = track.numericId, nid > 0, nid < 10_000_000, PlaybackRouter.shared.urlOpener == nil {
            if PlaybackRouter.shared.playTrackByDatabaseIdViaAMRQueue(nid, generation: gen) {
                BitPerfectLogMonitor.shared.endExplicitTrackSwitch(
                    trackKey: canonicalKey,
                    catalogId: trackCatalogId,
                    expectedSampleRate: cachedFmt?.sampleRate,
                    expectedBitDepth: cachedFmt?.bitDepth
                )
                let now = Date()
                PlaybackStateStore.shared.withLock {
                    if PlaybackStateStore.shared.playbackGeneration == gen {
                        if !cachedVariants.isEmpty {
                            PlaybackStateStore.shared.activeTrackTitleVariants = cachedVariants
                        }
                        PlaybackStateStore.shared.lastCloudPlayTime = now
                        PlaybackStateStore.shared.lastSkipTime = now
                        PlaybackStateStore.shared.lastWasPlayingCloud = true
                        PlaybackStateStore.shared.activeLoadingStage = nil
                        PlaybackStateStore.shared.activeLoadingStartedAt = nil
                        PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                    }
                }
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
                PlaybackRouter.shared.prestageUpcomingCloudTracks(fromIndex: index + 1, count: 5, expectedGeneration: gen)
                return true
            } else {
                // Stale or non-playable dbId — purge if non-synthetic or fall through to native cloud engine
                hadStaleNumericId = true
                if !ITLibraryReader.isSyntheticTrackId(nid) {
                    LibraryService.shared.purgeDeletedTrackDbIdsFromAllCaches([nid])
                    PlaybackStateStore.shared.unregisterStagedTemporaryTrack(dbId: nid)
                }
                PlaybackStateStore.shared.withLock {
                    if PlaybackStateStore.shared.playbackGeneration == gen {
                        if !ITLibraryReader.isSyntheticTrackId(nid),
                           index >= 0 && index < PlaybackStateStore.shared.activeCustomQueue.count {
                            PlaybackStateStore.shared.activeCustomQueue[index].numericId = nil
                            PlaybackStateStore.shared.activeCustomQueue[index].isLocal = false
                        }
                        PlaybackStateStore.shared.activeLoadingStage = "cloud"
                        PlaybackStateStore.shared.activeLoadingStartedAt = Date()
                    }
                }
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: false)
            }
        }

        // 1b. Fast ~2 ms lookup in `library playlist 1` ONLY for downloaded `file track`s (skipped in `0 ms` when library cache is confirmed empty or already known cloud-only!)
        if fallbackCloudLibraryDbId == nil,
           !track.name.isEmpty,
           PlaybackRouter.shared.urlOpener == nil,
           !LibraryService.shared.hasConfirmedEmptyLibraryCache() {
            let prefDbId = (!hadStaleNumericId && track.isLocal == true && track.numericId != nil && track.numericId! > 0 && track.numericId! < 10_000_000 && !ITLibraryReader.isSyntheticTrackId(track.numericId!)) ? track.numericId : nil
            let altTitles = cachedVariants.map(\.name).filter { !$0.isEmpty }
            let altArtists = cachedVariants.map(\.artist).filter { !$0.isEmpty }
            if let found = MusicKitManager.shared.findTrackDatabaseIdDetailedInMusicApp(
                name: track.name,
                artist: track.artist,
                preferredDbId: prefDbId,
                checkSubscriptionPlaylists: false,
                alternateTitles: altTitles,
                alternateArtists: altArtists
            ), found.dbId > 0, found.isPermanentLibrary {
                let foundDbId = found.dbId
                let isStagedTemp = PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.stagedTemporaryTrackDbIds.contains(foundDbId)
                }
                if !isStagedTemp {
                    if found.isDownloadedFile {
                        let isCurrentGen = PlaybackStateStore.shared.withLock { () -> Bool in
                            guard PlaybackStateStore.shared.playbackGeneration == gen else { return false }
                            if !cachedVariants.isEmpty {
                                PlaybackStateStore.shared.activeTrackTitleVariants = cachedVariants
                            }
                            if index >= 0 && index < PlaybackStateStore.shared.activeCustomQueue.count {
                                PlaybackStateStore.shared.activeCustomQueue[index].numericId = foundDbId
                                PlaybackStateStore.shared.activeCustomQueue[index].isLocal = true
                            }
                            return true
                        }
                        if isCurrentGen && PlaybackRouter.shared.playTrackByDatabaseIdViaAMRQueue(foundDbId, generation: gen) {
                            BitPerfectLogMonitor.shared.endExplicitTrackSwitch(
                                trackKey: canonicalKey,
                                catalogId: trackCatalogId,
                                expectedSampleRate: cachedFmt?.sampleRate,
                                expectedBitDepth: cachedFmt?.bitDepth
                            )
                            let now = Date()
                            PlaybackStateStore.shared.withLock {
                                if PlaybackStateStore.shared.playbackGeneration == gen {
                                    PlaybackStateStore.shared.lastCloudPlayTime = now
                                    PlaybackStateStore.shared.lastSkipTime = now
                                    PlaybackStateStore.shared.lastWasPlayingCloud = true
                                    PlaybackStateStore.shared.activeLoadingStage = nil
                                    PlaybackStateStore.shared.activeLoadingStartedAt = nil
                                    PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                                }
                            }
                            PlaybackStateStore.shared.invalidateQueueCache()
                            PlaybackStateStore.shared.invalidateStatusCache()
                            WebSocketServer.shared.broadcastStatus(includeQueue: true)
                            PlaybackRouter.shared.prestageUpcomingCloudTracks(fromIndex: index + 1, count: 5, expectedGeneration: gen)
                            return true
                        }
                    } else {
                        fallbackCloudLibraryDbId = foundDbId
                    }
                }
            }
        }

        // 2. Primary Music.app Lossless/Hi-Res Cloud Engine (prefer numeric `catalogId` when `track.id` is a library `i.xxx` or `<10M` ID!)
        let effectiveSongId: String? = {
            if let cat = track.catalogId?.trimmingCharacters(in: .whitespacesAndNewlines),
               let num = Int(cat), num >= 1_000_000, !ITLibraryReader.isSyntheticTrackId(num) {
                return cat
            }
            let raw = track.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if let num = Int(raw), num > 0, num < 10_000_000, PlaybackRouter.shared.urlOpener == nil && !PlaybackRouter.shared.isTestingEnvironment {
                return nil
            }
            return track.id
        }()
        let started = PlaybackRouter.shared.playCloudSync(
            url: track.url,
            id: effectiveSongId,
            name: track.name,
            artist: track.artist,
            skipInitialMusicAppLookup: true,
            expectedGeneration: gen
        )
        if started {
            let isCurrentGen = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.playbackGeneration == gen }
            guard isCurrentGen else { return false }
            PlaybackStateStore.shared.invalidateQueueCache()
            PlaybackStateStore.shared.invalidateStatusCache()
            WebSocketServer.shared.broadcastStatus(includeQueue: true)
            PlaybackRouter.shared.prestageUpcomingCloudTracks(fromIndex: index + 1, count: 5, expectedGeneration: gen)
            let nextIdx = index + 1
            let queueSnapshot = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.activeCustomQueue }
            if nextIdx < queueSnapshot.count {
                let nextTrack = queueSnapshot[nextIdx]
                Task.detached(priority: .utility) {
                    _ = await MusicKitManager.shared.resolveTrackStation(title: nextTrack.name, artist: nextTrack.artist)
                }
            }
            return true
        }

        // 2b. Fallback for private iCloud-uploaded library tracks not present in Apple Music's public catalog
        if let uploadDbId = fallbackCloudLibraryDbId,
           PlaybackRouter.shared.urlOpener == nil,
           !PlaybackRouter.shared.isTestingEnvironment,
           PlaybackRouter.shared.playTrackByDatabaseIdViaAMRQueue(uploadDbId, generation: gen) {
            BitPerfectLogMonitor.shared.endExplicitTrackSwitch(
                trackKey: canonicalKey,
                catalogId: trackCatalogId,
                expectedSampleRate: cachedFmt?.sampleRate,
                expectedBitDepth: cachedFmt?.bitDepth
            )
            let now = Date()
            PlaybackStateStore.shared.withLock {
                if PlaybackStateStore.shared.playbackGeneration == gen {
                    PlaybackStateStore.shared.lastCloudPlayTime = now
                    PlaybackStateStore.shared.lastSkipTime = now
                    PlaybackStateStore.shared.lastWasPlayingCloud = true
                    PlaybackStateStore.shared.activeLoadingStage = nil
                    PlaybackStateStore.shared.activeLoadingStartedAt = nil
                    PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                }
            }
            PlaybackStateStore.shared.invalidateQueueCache()
            PlaybackStateStore.shared.invalidateStatusCache()
            WebSocketServer.shared.broadcastStatus(includeQueue: true)
            return true
        }

        // 3. If a track in a multi-track queue is unavailable / rights-restricted on Apple Music (`started == false`),
        // automatically skip to the next track (just like native Music.app) instead of stalling the queue!
        if !PlaybackRouter.shared.isTestingEnvironment && PlaybackRouter.shared.urlOpener == nil && unavailableSkipDepth < 4 {
            let fallbackNextIndex: Int? = PlaybackStateStore.shared.withLock {
                guard PlaybackStateStore.shared.playbackGeneration == gen,
                      !PlaybackStateStore.shared.isUserPaused,
                      PlaybackStateStore.shared.isCustomQueuePlayback else {
                    return nil
                }
                let total = PlaybackStateStore.shared.activeCustomQueue.count
                guard total > 1 else { return nil }
                if index + 1 < total {
                    return index + 1
                }
                if PlaybackStateStore.shared.repeatMode == "all" {
                    return 0
                }
                return nil
            }
            if let nextIdx = fallbackNextIndex, nextIdx != index {
                NSLog("[QueueManager] ⏭ Track '%@ — %@' (index %d/%d) is unavailable in Apple Music — auto-skipping to index %d",
                      track.artist, track.name, index + 1, qCount, nextIdx + 1)
                let labelRu = track.name.isEmpty ? "Трек" : track.name
                let labelEn = track.name.isEmpty ? "Track" : track.name
                WebSocketServer.shared.broadcastEvent(
                    name: "toast",
                    data: [
                        "message_ru": "⏭ «\(labelRu)» недоступен в Apple Music — пропуск",
                        "message_en": "⏭ '\(labelEn)' is unavailable on Apple Music — skipping"
                    ]
                )
                return playQueueIndexUnlocked(nextIdx, incrementGeneration: true, unavailableSkipDepth: unavailableSkipDepth + 1)
            }
        }
        return false
    }


    // MARK: - History Playback

    public func playHistoryTrack(name: String, artist: String) async -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return false }
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastSkipTime = Date()
            PlaybackStateStore.shared.repeatOnePinnedTrack = nil
        }

        let escN = cleanName.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escA = cleanArtist.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "Music"
            try
                set foundTracks to (every file track of library playlist 1 whose name is "\(escN)" and artist is "\(escA)")
                if (count of foundTracks) > 0 then
                    if location of (item 1 of foundTracks) is not missing value then
                        play item 1 of foundTracks
                        return "ok"
                    end if
                end if
            end try
            try
                set foundTracks to (every file track of library playlist 1 whose name is "\(escN)")
                if (count of foundTracks) > 0 then
                    if location of (item 1 of foundTracks) is not missing value then
                        play item 1 of foundTracks
                        return "ok"
                    end if
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
            PlaybackStateStore.shared.lastSkipTime = Date()
            PlaybackStateStore.shared.repeatOnePinnedTrack = nil
            return (
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

        let q = await getPlaybackQueue()
        if !q.tracks.isEmpty && !q.playlist.isEmpty && q.playlist != "Apple Music" && q.playlist != "Apple Music Radio" {
            let targetIdx = q.currentIndex - 1 - index
            if targetIdx >= 0 && targetIdx < q.tracks.count {
                if q.shuffle {
                    return PlaybackRouter.shared.playCustomTracks(q.tracks, startIndex: targetIdx, shuffle: false, queueName: q.playlist)
                }
                if PlaybackRouter.shared.playPlaylist(name: q.playlist, trackId: nil, trackIndex: targetIdx + 1, shuffle: false) {
                    return true
                }
            }
        }

        let history = q.historyTracks.isEmpty
            ? PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.latestHistoryTracks })
            : q.historyTracks
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
