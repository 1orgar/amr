//
//  QueueManager+Monitoring.swift
//  AppleMusicRemoteMac
//
//  Distributed notification track interception and cloud queue auto-advance poller.
//

import Foundation
import ScriptingBridge

extension QueueManager {

    internal func resolveForwardMatchIndex(
        queueTracks: [TrackInfo],
        activeIdx: Int,
        isAMRPlaylist: Bool,
        candidateName: String,
        candidateArtist: String?
    ) -> Int? {
        guard activeIdx + 1 < queueTracks.count else { return nil }
        if !isAMRPlaylist {
            return queueTracks[(activeIdx + 1)...].firstIndex {
                matchesExpectedQueueTrack($0, candidateName: candidateName, candidateArtist: candidateArtist)
            }
        }
        if matchesExpectedQueueTrack(queueTracks[activeIdx + 1], candidateName: candidateName, candidateArtist: candidateArtist) {
            return activeIdx + 1
        }
        // If SystemMusicPlayerBridge queued multiple upcoming catalog IDs and Music.app natively skipped
        // an unavailable track at activeIdx + 1, allow matching activeIdx + 2 when its catalog ID matches slot [1].
        let secondNativeCid: String? = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.nativeQueuedUpcomingCatalogIds.count >= 2
                ? PlaybackStateStore.shared.nativeQueuedUpcomingCatalogIds[1]
                : nil
        }
        if let secondCid = secondNativeCid,
           activeIdx + 2 < queueTracks.count {
            let candidateTrack = queueTracks[activeIdx + 2]
            if let rawCid = MusicKitManager.extractNumericCatalogId(from: candidateTrack) {
                let effCid = MusicKitManager.shared.preferredAlternateCatalogSong(for: rawCid)?.id ?? rawCid
                if (secondCid == effCid || secondCid == rawCid),
                   matchesExpectedQueueTrack(candidateTrack, candidateName: candidateName, candidateArtist: candidateArtist) {
                    return activeIdx + 2
                }
            }
        }
        return nil
    }

    internal func completeNaturalForwardQueueAdvance(
        from oldIdx: Int,
        to relativeIdx: Int,
        initialPosition: Double = 0.0,
        outgoingTitleOverride: String? = nil
    ) {
        let transitionSnapshot: (track: TrackInfo, immediateStatus: PlayerStatus, gen: UInt64)? = PlaybackStateStore.shared.withLock {
            let q = PlaybackStateStore.shared.activeCustomQueue
            guard relativeIdx >= 0 && relativeIdx < q.count else { return nil }
            let prevTrack: TrackInfo? = (oldIdx >= 0 && oldIdx < q.count) ? q[oldIdx] : nil
            let outgoingName = (outgoingTitleOverride?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? prevTrack?.name.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""
            let steps = max(1, relativeIdx - oldIdx)
            if steps <= PlaybackStateStore.shared.nativeQueuedUpcomingCatalogIds.count {
                PlaybackStateStore.shared.nativeQueuedUpcomingCatalogIds.removeFirst(steps)
            } else {
                PlaybackStateStore.shared.nativeQueuedUpcomingCatalogIds.removeAll()
            }
            let now = Date()
            let nextTrack = q[relativeIdx]
            let nextCid = MusicKitManager.extractNumericCatalogId(from: nextTrack)
            if !outgoingName.isEmpty,
               outgoingName.localizedCaseInsensitiveCompare(nextTrack.name) != .orderedSame {
                PlaybackStateStore.shared.transitionPreviousTrackKey = self.canonicalForeignTrackKey(
                    name: outgoingName,
                    artist: prevTrack?.artist
                )
                PlaybackStateStore.shared.activeOverlapTransition = OverlapTransitionSnapshot(
                    outgoingName: outgoingName,
                    incomingTrack: nextTrack,
                    startedAt: now,
                    initialPosition: max(0.0, initialPosition)
                )
            } else {
                PlaybackStateStore.shared.activeOverlapTransition = nil
            }
            PlaybackStateStore.shared.activeCustomQueueIndex = relativeIdx
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
            PlaybackStateStore.shared.lastConfirmedTrackTime = now
            PlaybackStateStore.shared.lastCloudPlayTime = now
            PlaybackStateStore.shared.lastKnownPosition = max(0.0, initialPosition)
            PlaybackStateStore.shared.scheduledSmartTransitionStart = nil
            PlaybackStateStore.shared.lastWasPlayingCloud = true
            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
            PlaybackStateStore.shared.activeTrackTitleVariants = MusicKitManager.shared.cachedTitleVariants(catalogId: nextCid)
            if relativeIdx + 1 < q.count {
                PlaybackStateStore.shared.latestUpcomingTracks = Array(q[(relativeIdx + 1)...])
            } else {
                PlaybackStateStore.shared.latestUpcomingTracks = []
            }
            if relativeIdx > 0 {
                PlaybackStateStore.shared.latestHistoryTracks = Array(q[0..<relativeIdx].reversed())
            } else {
                PlaybackStateStore.shared.latestHistoryTracks = []
            }

            var resolvedArt = nextTrack.artworkUrl
            if resolvedArt.isEmpty {
                if let cached = MusicKitManager.shared.getCachedTrackArtwork(
                    name: nextTrack.name,
                    artist: nextTrack.artist,
                    album: nextTrack.album
                ), !cached.isEmpty {
                    resolvedArt = cached
                } else if !nextTrack.name.isEmpty {
                    let encN = nextTrack.name.amrQueryValueEncoded
                    let encA = nextTrack.artist.amrQueryValueEncoded
                    let encAl = nextTrack.album.amrQueryValueEncoded
                    resolvedArt = "/api/artwork/search?name=\(encN)&artist=\(encA)&album=\(encAl)"
                }
            }
            var enrichedNext = nextTrack
            if !resolvedArt.isEmpty {
                enrichedNext.artworkUrl = resolvedArt
                enrichedNext.hasArtwork = true
            }
            let plLabel = PlaybackStateStore.shared.activeCustomQueueName ?? "Очередь"
            let immediate = PlayerStatus(
                playerState: "playing",
                position: max(0.0, initialPosition),
                duration: enrichedNext.duration,
                volume: PlaybackStateStore.shared.simulatedVolume,
                shuffle: PlaybackStateStore.shared.isShuffleQueueActive,
                repeatMode: PlaybackStateStore.shared.repeatMode,
                playlist: plLabel,
                isRadio: false,
                audioQuality: PlaybackStateStore.shared.lastPlayerStatusCache?.status.audioQuality ?? "Lossless (ALAC 16-bit/44.1kHz)",
                track: enrichedNext
            )
            return (enrichedNext, immediate, PlaybackStateStore.shared.playbackGeneration)
        }
        PlaybackStateStore.shared.invalidateQueueCache()
        PlaybackStateStore.shared.invalidateStatusCache()
        if !PlaybackRouter.shared.isTestingEnvironment, let snapshot = transitionSnapshot {
            let newTrack = snapshot.track
            var immediateStatus = snapshot.immediateStatus
            let gen = snapshot.gen
            PlayerStatusEngine.shared.applyLiveAudioPipelineOverlay(to: &immediateStatus, updateTapFormatIfNeeded: false)
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.lastPlayerStatusCache = (Date(), immediateStatus)
            }
            // Push zero-latency optimistic UI & queue update (< 2 ms) before background format/SoundCheck warmup
            WebSocketServer.shared.broadcastStatus(status: immediateStatus, includeQueue: true)

            let canonicalKey = !newTrack.name.isEmpty
                ? "\(newTrack.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()):\(newTrack.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
                : nil
            let nextCatalogId = MusicKitManager.extractNumericCatalogId(from: newTrack)
            let cachedFmt = BitPerfectLogMonitor.shared.getCachedFormat(artist: newTrack.artist, title: newTrack.name, catalogId: nextCatalogId)
            BitPerfectLogMonitor.shared.resetTrackState(
                trackKey: canonicalKey,
                catalogId: nextCatalogId,
                expectedSampleRate: cachedFmt?.sampleRate,
                expectedBitDepth: cachedFmt?.bitDepth
            )
            if ExternalAmpTCPController.shared.isActive,
               ExternalAmpTCPController.shared.isSoundCheckEnabled,
               !newTrack.name.isEmpty {
                let resolvedCatId = newTrack.catalogId ?? (AppleSoundCheckService.isValidCatalogId(newTrack.id) ? newTrack.id : nil)
                AppleSoundCheckService.shared.syncCurrentTrack(
                    trackKey: canonicalKey ?? "\(newTrack.artist):\(newTrack.name)",
                    trackId: resolvedCatId ?? newTrack.persistentId ?? newTrack.id,
                    catalogId: resolvedCatId,
                    name: newTrack.name,
                    artist: newTrack.artist,
                    album: newTrack.album,
                    isLocal: false,
                    isExplicitTransition: true
                )
            }
            PlaybackRouter.shared.prestageUpcomingCloudTracks(fromIndex: relativeIdx + 1, count: 4, expectedGeneration: gen)
            _ = newTrack
        }
    }

    public func handleTrackNotification(userInfo: [AnyHashable: Any]?) {
        monitorLock.lock()
        defer { monitorLock.unlock() }

        guard let info = userInfo else { return }
        let (isCustom, hasQueue, activeIdx, queueTracks, lastPlayTime, confirmed, isTransitioning, isUserPaused) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isCustomQueuePlayback,
                !PlaybackStateStore.shared.activeCustomQueue.isEmpty,
                PlaybackStateStore.shared.activeCustomQueueIndex,
                PlaybackStateStore.shared.activeCustomQueue,
                PlaybackStateStore.shared.lastCloudPlayTime,
                PlaybackStateStore.shared.currentTrackPlaybackConfirmed,
                PlaybackStateStore.shared.isTransitioningTrack || PlaybackStateStore.shared.isStagingCloudTrack,
                PlaybackStateStore.shared.isUserPaused
            )
        }
        guard isCustom && hasQueue && activeIdx < queueTracks.count else {
            let repMode = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.repeatMode }
            if repMode == "one" {
                let state = (info["Player State"] as? String)?.lowercased() ?? ""
                if !isUserPaused && state != "paused" && state != "stopped" {
                    let notifName = (info["Name"] as? String) ?? ""
                    let notifArtist = info["Artist"] as? String
                    enforceRadioRepeatOneLocked(triggerTrackName: notifName, triggerArtistName: notifArtist)
                }
            }
            return
        }

        let state = (info["Player State"] as? String)?.lowercased() ?? ""
        if isUserPaused || state == "paused" {
            return
        }
        let trackName = (info["Name"] as? String) ?? ""
        let artistName = info["Artist"] as? String
        let timeSincePlay = Date().timeIntervalSince(lastPlayTime ?? Date.distantPast)

        // 1. If Music.app is stopped, ONLY advance if playback was confirmed AND track played to the end!
        if state == "stopped" {
            let (alreadyTriggered, lastKnownPos, curRepeatMode) = PlaybackStateStore.shared.withLock {
                (
                    PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack,
                    PlaybackStateStore.shared.lastKnownPosition,
                    PlaybackStateStore.shared.repeatMode
                )
            }
            let status = PlayerStatusEngine.shared.getPlayerStatus()
            let dur = status.duration > 0 ? status.duration : (queueTracks[activeIdx].duration > 0 ? queueTracks[activeIdx].duration : 180.0)
            let minPlayGuard = curRepeatMode == "one" ? min(15.0, max(1.5, dur * 0.5)) : 15.0
            let minPosGuard = curRepeatMode == "one" ? min(10.0, max(1.0, dur * 0.5)) : 10.0
            if timeSincePlay < minPlayGuard && lastKnownPos < minPosGuard {
                return
            }
            let effectivePos = max(status.position, lastKnownPos)
            let endTolerance = min(3.5, max(0.5, dur * 0.35))
            let timeBasedNearEnd = (lastKnownPos <= 1.0 || lastKnownPos >= max(0.0, dur - 10.0)) && (dur > 2.0 && timeSincePlay >= max(1.0, dur - endTolerance))
            let isNearEnd = (dur > 2.0 && effectivePos >= max(1.0, dur - endTolerance))
                || timeBasedNearEnd
                || (effectivePos >= min(30.0, max(3.0, dur * 0.85)) && effectivePos >= dur * 0.88)
            if confirmed && !alreadyTriggered && isNearEnd {
                self.advanceOrEndCustomQueueUnlocked(reason: "notification-stopped")
            }
            return
        }

        guard !trackName.isEmpty else { return }
        let lowerTrackName = trackName.lowercased()
        if (lowerTrackName.hasPrefix("станция:") || lowerTrackName.hasPrefix("station:")) && (artistName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        let expected = queueTracks[activeIdx]

        // 2. If track matches expected track (including official catalog localized title variants), confirm playback immediately
        if matchesExpectedQueueTrack(expected, candidateName: trackName, candidateArtist: artistName) {
            let newlyConfirmed = PlaybackStateStore.shared.withLock { () -> Bool in
                let wasConfirmed = PlaybackStateStore.shared.currentTrackPlaybackConfirmed
                PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                if !wasConfirmed {
                    PlaybackStateStore.shared.lastConfirmedTrackTime = Date()
                }
                PlaybackStateStore.shared.activeLoadingStage = nil
                PlaybackStateStore.shared.activeLoadingStartedAt = nil
                PlaybackStateStore.shared.transitionPreviousTrackKey = nil
                PlaybackStateStore.shared.activeOverlapTransition = nil
                PlaybackStateStore.shared.lastWasPlayingCloud = true
                PlaybackStateStore.shared.lastSkipTime = .distantPast
                return !wasConfirmed
            }
            if newlyConfirmed && !PlaybackRouter.shared.isTestingEnvironment {
                persistConfirmedAlternateSeedIfNeeded(expected: expected, confirmedName: trackName, confirmedArtist: artistName)
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
            }
            return
        }

        if isDrainingPreviousTrack(candidateName: trackName, candidateArtist: artistName, confirmed: confirmed, timeSincePlay: timeSincePlay) {
            return
        }

        let origPlName = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.currentOriginalPlaylistName }
        let isAMRPlaylist = (origPlName == "Очередь AMR")

        if !confirmed && origPlName == nil && timeSincePlay >= 1.8 {
            if tryRecoverMismatchedCloudSeedIfNeeded(
                expected: expected,
                activeIdx: activeIdx,
                candidateName: trackName,
                candidateArtist: artistName
            ) {
                return
            }
        }

        // 3. During transition to target track, ignore mismatch from draining track
        if isTransitioning || (!confirmed && timeSincePlay < 3.5) {
            return
        }

        // 4. Past tracks in custom queue
        if let pastIdx = queueTracks[..<activeIdx].firstIndex(where: { isTrackMatching(expected: $0, candidateName: trackName, candidateArtist: artistName) }) {
            if let orig = origPlName, !orig.isEmpty, orig != "Очередь AMR", confirmed {
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.activeCustomQueueIndex = pastIdx
                    PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                    PlaybackStateStore.shared.lastWasPlayingCloud = true
                    PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
                }
            }
            return
        }

        // 5. Forward tracks in custom queue
        if let relativeIdx = resolveForwardMatchIndex(
            queueTracks: queueTracks,
            activeIdx: activeIdx,
            isAMRPlaylist: isAMRPlaylist,
            candidateName: trackName,
            candidateArtist: artistName
        ) {
            let curRep = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.repeatMode }
            if curRep == "one" {
                NSLog("[QueueManager] 🔂 Notification: Intercepted forward advance to '%@' while Repeat ONE is active — replaying index %d ('%@')",
                      trackName, activeIdx, expected.name)
                stopMusicAppImmediatelyForQueueCutoff()
                advanceOrEndCustomQueueUnlocked(reason: "repeat-one-intercept")
                return
            }
            completeNaturalForwardQueueAdvance(from: activeIdx, to: relativeIdx)
            return
        }

        // 6. Localized AMR queue start confirmation vs foreign track interception
        if isAMRPlaylist && !confirmed && timeSincePlay < 15.0 {
            if shouldConfirmLocalizedAMRTrackStart(expected: expected, candidateName: trackName, candidateArtist: artistName) {
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                    PlaybackStateStore.shared.lastConfirmedTrackTime = Date()
                    PlaybackStateStore.shared.lastWasPlayingCloud = true
                    PlaybackStateStore.shared.lastSkipTime = .distantPast
                    if activeIdx < PlaybackStateStore.shared.activeCustomQueue.count && !trackName.isEmpty {
                        PlaybackStateStore.shared.activeCustomQueue[activeIdx].name = trackName
                    }
                }
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                if !PlaybackRouter.shared.isTestingEnvironment {
                    WebSocketServer.shared.broadcastStatus(includeQueue: true)
                }
                return
            }
        }

        if let orig = origPlName, !orig.isEmpty, orig != "Очередь AMR" {
            let cachedPl = PlayerStatusEngine.shared.cachedCurrentPlaylistName
            let isCurrentPlMatch = PlaybackRouter.shared.isTestingEnvironment || (cachedPl == orig)
            if isCurrentPlMatch {
                PlaybackStateStore.shared.withLock {
                    if !PlaybackStateStore.shared.currentTrackPlaybackConfirmed {
                        PlaybackStateStore.shared.lastConfirmedTrackTime = Date()
                    }
                    PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                    PlaybackStateStore.shared.lastWasPlayingCloud = true
                    PlaybackStateStore.shared.lastSkipTime = .distantPast
                }
                return
            }
        }

        if !isTransitioning && (confirmed || timeSincePlay >= 3.0) {
            guard canInterceptForeignTrack(
                candidateName: trackName,
                candidateArtist: artistName,
                expectedTrack: expected,
                timeSincePlay: timeSincePlay
            ) else {
                return
            }
            if isLiveMusicAppAlreadyPlayingExpectedTrack(expected) {
                NSLog("[QueueManager] 🛡 Notification: Ignoring stale foreign payload '%@' by '%@' — Music.app is already on expected track '%@'",
                      trackName, artistName ?? "", expected.name)
                return
            }
            NSLog("[QueueManager] 🛡 Notification: Foreign track '%@' by '%@' while in custom queue! Stopping audio and advancing/ending queue.",
                  trackName, artistName ?? "")
            recordForeignTrackIntercept(name: trackName, artist: artistName)
            _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop")
            self.advanceOrEndCustomQueueUnlocked(reason: "notification-foreign")
            return
        }
    }

    public func checkAndAutoAdvanceCloudQueue() {
        monitorLock.lock()
        defer { monitorLock.unlock() }

        let (isCustom, hasQueue, prePollGen, prePollPaused) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isCustomQueuePlayback,
                !PlaybackStateStore.shared.activeCustomQueue.isEmpty,
                PlaybackStateStore.shared.playbackGeneration,
                PlaybackStateStore.shared.isUserPaused
            )
        }
        guard isCustom && hasQueue else {
            let repMode = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.repeatMode }
            if repMode == "one" {
                enforceRadioRepeatOneLocked()
            } else {
                stopQueueMonitoring()
            }
            return
        }

        if prePollPaused {
            return
        }

        let status = PlayerStatusEngine.shared.getPlayerStatus()
        let (stillSameGen, activeIdx, queueTracks, lastPlayTime, lastWasPlaying, confirmed, isTransitioning, isUserPaused) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.playbackGeneration == prePollGen && PlaybackStateStore.shared.isCustomQueuePlayback,
                PlaybackStateStore.shared.activeCustomQueueIndex,
                PlaybackStateStore.shared.activeCustomQueue,
                PlaybackStateStore.shared.lastCloudPlayTime,
                PlaybackStateStore.shared.lastWasPlayingCloud,
                PlaybackStateStore.shared.currentTrackPlaybackConfirmed,
                PlaybackStateStore.shared.isTransitioningTrack || PlaybackStateStore.shared.isStagingCloudTrack,
                PlaybackStateStore.shared.isUserPaused
            )
        }
        guard stillSameGen, !queueTracks.isEmpty, !isUserPaused else {
            return
        }
        let pState = (status.isBuffering == true) ? "stopped" : status.playerState
        if pState == "paused" {
            return
        }

        let pos = status.position
        var dur = status.duration

        if dur <= 0 && activeIdx < queueTracks.count {
            dur = queueTracks[activeIdx].duration
        }

        let timeSincePlay = Date().timeIntervalSince(lastPlayTime ?? Date.distantPast)
        let liveRawMeta = PlaybackRouter.shared.isTestingEnvironment ? nil : PlayerStatusEngine.shared.cachedLiveTrackTitleAndArtist
        let hasResolvedLiveTrack: Bool = {
            guard let raw = liveRawMeta else { return true }
            let trimmed = raw.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && !trimmed.allSatisfy(\.isNumber)
        }()
        let curTrackName = hasResolvedLiveTrack ? (liveRawMeta?.name ?? status.track?.name ?? "") : ""
        let curArtist = hasResolvedLiveTrack ? (liveRawMeta?.artist ?? status.track?.artist ?? "") : ""

        if pState == "playing" {
            let (searchQuery, isFetching, curatorPrompt, isFetchingCurator, qCount) = PlaybackStateStore.shared.withLock {
                (
                    PlaybackStateStore.shared.activeSearchQuery,
                    PlaybackStateStore.shared.isFetchingNextSearchPage,
                    PlaybackStateStore.shared.activeCuratorPrompt,
                    PlaybackStateStore.shared.isFetchingNextCuratorPage,
                    PlaybackStateStore.shared.activeCustomQueue.count
                )
            }
            if let q = searchQuery, !q.isEmpty, !isFetching, activeIdx >= max(0, qCount - 3) {
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.isFetchingNextSearchPage = true
                }
                Task.detached(priority: .userInitiated) {
                    await PlaybackRouter.shared.fetchAndAppendNextSearchResults(query: q)
                }
            } else if let cp = curatorPrompt, !cp.isEmpty, !isFetchingCurator, activeIdx >= max(0, qCount - 3) {
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.isFetchingNextCuratorPage = true
                }
                Task.detached(priority: .userInitiated) {
                    await PlaybackRouter.shared.fetchAndAppendNextCuratorResults(prompt: cp)
                }
            }

            let origPlName = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.currentOriginalPlaylistName }
            let isAMR = (origPlName == "Очередь AMR")

            if !curTrackName.isEmpty && activeIdx < queueTracks.count {
                let expectedTrack = queueTracks[activeIdx]
                let matchesExpected = PlaybackRouter.shared.isTestingEnvironment
                    || matchesExpectedQueueTrack(
                        expectedTrack,
                        candidateName: curTrackName,
                        candidateArtist: curArtist,
                        candidateDbId: status.track?.numericId
                    )

                if matchesExpected {
                    let newlyConfirmed = PlaybackStateStore.shared.withLock { () -> Bool in
                        let wasConfirmed = PlaybackStateStore.shared.currentTrackPlaybackConfirmed
                        PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                        if !wasConfirmed {
                            PlaybackStateStore.shared.lastConfirmedTrackTime = Date()
                        }
                        PlaybackStateStore.shared.activeLoadingStage = nil
                        PlaybackStateStore.shared.activeLoadingStartedAt = nil
                        PlaybackStateStore.shared.transitionPreviousTrackKey = nil
                        PlaybackStateStore.shared.lastWasPlayingCloud = true
                        PlaybackStateStore.shared.lastSkipTime = .distantPast
                        if pos >= 0 {
                            PlaybackStateStore.shared.lastKnownPosition = pos
                        }
                        if dur > 0 && activeIdx < PlaybackStateStore.shared.activeCustomQueue.count && PlaybackStateStore.shared.activeCustomQueue[activeIdx].duration <= 0 {
                            PlaybackStateStore.shared.activeCustomQueue[activeIdx].duration = dur
                        }
                        if pos >= 0.25 && pos < (dur > 3.0 ? dur - 3.0 : 1000.0) {
                            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
                        }
                        return !wasConfirmed
                    }
                    if newlyConfirmed && !PlaybackRouter.shared.isTestingEnvironment {
                        persistConfirmedAlternateSeedIfNeeded(expected: expectedTrack, confirmedName: curTrackName, confirmedArtist: curArtist)
                        PlaybackStateStore.shared.invalidateQueueCache()
                        PlaybackStateStore.shared.invalidateStatusCache()
                        WebSocketServer.shared.broadcastStatus(includeQueue: true)
                    }
                } else if (curTrackName.lowercased().hasPrefix("станция:") || curTrackName.lowercased().hasPrefix("station:")) && curArtist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return
                } else if isDrainingPreviousTrack(candidateName: curTrackName, candidateArtist: curArtist, confirmed: confirmed, timeSincePlay: timeSincePlay) {
                    return
                } else if !confirmed && origPlName == nil && timeSincePlay >= 1.8 && tryRecoverMismatchedCloudSeedIfNeeded(
                    expected: expectedTrack,
                    activeIdx: activeIdx,
                    candidateName: curTrackName,
                    candidateArtist: curArtist
                ) {
                    return
                } else if isTransitioning || (!confirmed && timeSincePlay < 3.5) {
                    return
                } else if let pastIdx = queueTracks[..<activeIdx].firstIndex(where: { isTrackMatching(expected: $0, candidateName: curTrackName, candidateArtist: curArtist) }) {
                    let knownPos = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.lastKnownPosition }
                    if let orig = origPlName, !orig.isEmpty, orig != "Очередь AMR", confirmed {
                        PlaybackStateStore.shared.withLock {
                            PlaybackStateStore.shared.activeCustomQueueIndex = pastIdx
                            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                            PlaybackStateStore.shared.lastWasPlayingCloud = true
                            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
                        }
                        return
                    } else if !confirmed || (timeSincePlay < 12.0 && knownPos < 10.0) {
                        return
                    } else if !isTransitioning {
                        guard canInterceptForeignTrack(
                            candidateName: curTrackName,
                            candidateArtist: curArtist,
                            expectedTrack: expectedTrack,
                            timeSincePlay: timeSincePlay
                        ) else {
                            return
                        }
                        if isLiveMusicAppAlreadyPlayingExpectedTrack(expectedTrack) {
                            return
                        }
                        NSLog("[QueueManager] 🛡 Poller: Music.app auto-advanced to past staged track '%@' (idx=%d while activeIdx=%d)! Stopping and advancing custom queue.",
                              curTrackName, pastIdx, activeIdx)
                        recordForeignTrackIntercept(name: curTrackName, artist: curArtist)
                        self.stopMusicAppImmediatelyForQueueCutoff()
                        self.advanceOrEndCustomQueueUnlocked(reason: "poller-past-track-advance")
                        return
                    }
                    return
                } else if let relativeIdx = resolveForwardMatchIndex(
                    queueTracks: queueTracks,
                    activeIdx: activeIdx,
                    isAMRPlaylist: isAMR,
                    candidateName: curTrackName,
                    candidateArtist: curArtist
                ) {
                    let curRep = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.repeatMode }
                    if curRep == "one" {
                        NSLog("[QueueManager] 🔂 Poller: Intercepted forward advance to '%@' while Repeat ONE is active — replaying index %d ('%@')",
                              curTrackName, activeIdx, expectedTrack.name)
                        stopMusicAppImmediatelyForQueueCutoff()
                        advanceOrEndCustomQueueUnlocked(reason: "repeat-one-intercept")
                        return
                    }
                    completeNaturalForwardQueueAdvance(from: activeIdx, to: relativeIdx)
                    return
                } else if isAMR && !confirmed && timeSincePlay < 15.0,
                          shouldConfirmLocalizedAMRTrackStart(
                              expected: expectedTrack,
                              candidateName: curTrackName,
                              candidateArtist: curArtist,
                              liveTrackDbId: status.track?.numericId
                          ) {
                    PlaybackStateStore.shared.withLock {
                        PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                        PlaybackStateStore.shared.lastConfirmedTrackTime = Date()
                        PlaybackStateStore.shared.lastWasPlayingCloud = true
                        PlaybackStateStore.shared.lastSkipTime = .distantPast
                        if activeIdx < PlaybackStateStore.shared.activeCustomQueue.count && !curTrackName.isEmpty {
                            PlaybackStateStore.shared.activeCustomQueue[activeIdx].name = curTrackName
                        }
                        if pos > 0 {
                            PlaybackStateStore.shared.lastKnownPosition = pos
                        }
                    }
                    PlaybackStateStore.shared.invalidateQueueCache()
                    PlaybackStateStore.shared.invalidateStatusCache()
                    if !PlaybackRouter.shared.isTestingEnvironment {
                        WebSocketServer.shared.broadcastStatus(includeQueue: true)
                    }
                    return
                } else if let orig = origPlName, !orig.isEmpty, orig != "Очередь AMR" {
                    let cachedPl = PlayerStatusEngine.shared.cachedCurrentPlaylistName
                    let isCurrentPlMatch = PlaybackRouter.shared.isTestingEnvironment || (cachedPl == orig)
                    if isCurrentPlMatch {
                        PlaybackStateStore.shared.withLock {
                            if !PlaybackStateStore.shared.currentTrackPlaybackConfirmed {
                                PlaybackStateStore.shared.lastConfirmedTrackTime = Date()
                            }
                            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                            PlaybackStateStore.shared.lastWasPlayingCloud = true
                            PlaybackStateStore.shared.lastSkipTime = .distantPast
                        }
                        return
                    }
                } else {
                    if !isTransitioning && (confirmed || timeSincePlay >= 4.5) {
                        guard canInterceptForeignTrack(
                            candidateName: curTrackName,
                            candidateArtist: curArtist,
                            expectedTrack: expectedTrack,
                            timeSincePlay: timeSincePlay
                        ) else {
                            return
                        }
                        if isLiveMusicAppAlreadyPlayingExpectedTrack(expectedTrack) {
                            return
                        }
                        NSLog("[QueueManager] 🛡 Poller: Foreign track '%@' by '%@' while in custom queue! Stopping audio and advancing or ending queue.",
                              curTrackName, curArtist)
                        recordForeignTrackIntercept(name: curTrackName, artist: curArtist)
                        self.stopMusicAppImmediatelyForQueueCutoff()
                        self.advanceOrEndCustomQueueUnlocked(reason: "poller-foreign")
                        return
                    }
                }
            }

            // Near-EOF advance (never pre-cut at MediaPlaybackCore's 3-38s fade-out `scheduledSmartTransitionStart`!)
            let (alreadyTriggered, lastKnownPos, currentRepeatMode, firstNativeQueuedCid) = PlaybackStateStore.shared.withLock {
                (
                    PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack,
                    PlaybackStateStore.shared.lastKnownPosition,
                    PlaybackStateStore.shared.repeatMode,
                    PlaybackStateStore.shared.nativeQueuedUpcomingCatalogIds.first
                )
            }
            let cachedPlName = PlayerStatusEngine.shared.cachedCurrentPlaylistName
            let isIsolatedAMRPlaylist = (cachedPlName == "Очередь AMR")
            let isNativePlayingPlaylist: Bool = {
                guard let curPl = cachedPlName,
                      !curPl.isEmpty,
                      curPl != "Очередь AMR",
                      let origPl = origPlName,
                      !origPl.isEmpty,
                      origPl != "Очередь AMR",
                      curPl == origPl else {
                    return false
                }
                return true
            }()
            let hasMatchingNativeNextTrack: Bool = {
                guard currentRepeatMode != "one",
                      let queuedCid = firstNativeQueuedCid,
                      !queuedCid.isEmpty,
                      activeIdx + 1 < queueTracks.count else {
                    return false
                }
                let nextTrack = queueTracks[activeIdx + 1]
                let isDownloadedLocalNext = nextTrack.isLocal == true && (
                    nextTrack.numericId == nil || ITLibraryReader.shared.downloadedFileTrackStatus(forTrackId: nextTrack.numericId!) != false
                )
                guard !isDownloadedLocalNext,
                      let rawNextCid = MusicKitManager.extractNumericCatalogId(from: nextTrack) else {
                    return false
                }
                let effNextCid = MusicKitManager.shared.preferredAlternateCatalogSong(for: rawNextCid)?.id ?? rawNextCid
                return queuedCid == effNextCid || queuedCid == rawNextCid
            }()
            var effectivePos = pos
            if confirmed && !alreadyTriggered && dur > 5.0 && pos > 0.0 && (dur - pos) <= 5.0,
               !PlaybackRouter.shared.isTestingEnvironment,
               let app = MusicAppProvider.shared.getMusicApp() {
                let directPos = app.playerPosition
                if directPos > 0 {
                    effectivePos = directPos
                    PlaybackStateStore.shared.withLock {
                        PlaybackStateStore.shared.lastKnownPosition = directPos
                    }
                }
            }

            let repeatOneCutoffPos: Double = max(1.0, dur - 0.30)
            let eofLeadWindow: Double = 0.18

            if isIsolatedAMRPlaylist {
                if currentRepeatMode == "one" && confirmed && !PlaybackRouter.shared.isTestingEnvironment && dur > 5.0 && effectivePos > 1.0 {
                    let remainingToRepeat = repeatOneCutoffPos - effectivePos
                    if remainingToRepeat <= 0.0 {
                        let lastRewind = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.lastRepeatOneRewindTime }
                        if Date().timeIntervalSince(lastRewind) >= 2.0 {
                            PlaybackStateStore.shared.withLock {
                                PlaybackStateStore.shared.lastRepeatOneRewindTime = Date()
                            }
                            _ = PlaybackTransportController.shared.seek(to: 0.0)
                            WebSocketServer.shared.broadcastStatus(includeQueue: false)
                        }
                    } else if remainingToRepeat <= 0.45 {
                        let wakeDelay = max(0.015, min(remainingToRepeat + 0.008, remainingToRepeat * 0.65))
                        self.schedulePrecisionCutoffWakeup(delay: wakeDelay)
                    }
                } else if currentRepeatMode != "one" && !hasMatchingNativeNextTrack && confirmed && !alreadyTriggered && dur > 5.0 && effectivePos > 1.0 {
                    let cutoffPos = dur - eofLeadWindow
                    let remainingToCutoff = cutoffPos - effectivePos
                    if remainingToCutoff <= 0.0 {
                        self.stopMusicAppImmediatelyForQueueCutoff()
                        self.advanceOrEndCustomQueueUnlocked(reason: "smooth-advance-amr")
                    } else if !PlaybackRouter.shared.isTestingEnvironment && remainingToCutoff <= 0.45 {
                        let wakeDelay = max(0.015, min(remainingToCutoff + 0.008, remainingToCutoff * 0.65))
                        self.schedulePrecisionCutoffWakeup(delay: wakeDelay)
                    }
                }
            } else {
                let isSingleTrackOff = (queueTracks.count <= 1 && currentRepeatMode == "off")
                let cutoffPos: Double = dur - eofLeadWindow
                let timeBasedSmoothEnd = (lastKnownPos <= 1.0 || lastKnownPos >= dur - 10.0) && (effectivePos <= 0.0 && timeSincePlay >= cutoffPos)
                let needsPrequeuedRepeatRewind = (firstNativeQueuedCid != nil)
                if currentRepeatMode == "one" && confirmed && !PlaybackRouter.shared.isTestingEnvironment && dur > 5.0 && effectivePos > 1.0 && needsPrequeuedRepeatRewind {
                    let remainingToRepeat = repeatOneCutoffPos - effectivePos
                    if remainingToRepeat <= 0.0 {
                        let lastRewind = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.lastRepeatOneRewindTime }
                        if Date().timeIntervalSince(lastRewind) >= 2.0 {
                            PlaybackStateStore.shared.withLock {
                                PlaybackStateStore.shared.lastRepeatOneRewindTime = Date()
                            }
                            _ = PlaybackTransportController.shared.seek(to: 0.0)
                            WebSocketServer.shared.broadcastStatus(includeQueue: false)
                        }
                    } else if remainingToRepeat <= 0.45 {
                        let wakeDelay = max(0.015, min(remainingToRepeat + 0.008, remainingToRepeat * 0.65))
                        self.schedulePrecisionCutoffWakeup(delay: wakeDelay)
                    }
                } else if !hasMatchingNativeNextTrack && confirmed && !alreadyTriggered && dur > 5.0 && ((effectivePos > 1.0 && effectivePos >= cutoffPos) || timeBasedSmoothEnd) {
                    if isNativePlayingPlaylist {
                        // Native named playlist gapless playback
                    } else if currentRepeatMode == "one" {
                        // Handled above or at EOF
                    } else if isSingleTrackOff {
                        if !PlaybackRouter.shared.isTestingEnvironment && effectivePos > 1.0 && effectivePos >= cutoffPos {
                            self.stopMusicAppImmediatelyForQueueCutoff()
                            self.advanceOrEndCustomQueueUnlocked(reason: "smooth-advance-amr")
                        }
                    } else {
                        self.stopMusicAppImmediatelyForQueueCutoff()
                        self.advanceOrEndCustomQueueUnlocked(reason: "smooth-advance")
                    }
                } else if !PlaybackRouter.shared.isTestingEnvironment && !isNativePlayingPlaylist && !hasMatchingNativeNextTrack && confirmed && !alreadyTriggered && dur > 5.0 && effectivePos > 1.0 {
                    let remainingToCutoff = cutoffPos - effectivePos
                    if remainingToCutoff > 0.0 && remainingToCutoff <= 0.45 {
                        let wakeDelay = max(0.015, min(remainingToCutoff + 0.008, remainingToCutoff * 0.65))
                        self.schedulePrecisionCutoffWakeup(delay: wakeDelay)
                    }
                }
            }
        } else if pState == "stopped" && lastWasPlaying && confirmed {
            let (alreadyTriggered, lastKnownPos, curRepeatMode) = PlaybackStateStore.shared.withLock {
                (
                    PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack,
                    PlaybackStateStore.shared.lastKnownPosition,
                    PlaybackStateStore.shared.repeatMode
                )
            }
            let effectivePos = max(pos, lastKnownPos)
            let minDur = curRepeatMode == "one" ? 2.0 : 15.0
            let endTol = min(3.5, max(0.5, dur * 0.35))
            let timeBasedNearEnd = (lastKnownPos <= 1.0 || lastKnownPos >= max(0.0, dur - 10.0)) && (dur > minDur && timeSincePlay >= max(1.0, dur - endTol))
            let isNearEnd = (dur > minDur && effectivePos >= max(1.0, dur - endTol))
                || timeBasedNearEnd
                || (effectivePos >= min(30.0, max(3.0, dur * 0.85)) && effectivePos >= dur * 0.88)
            if isNearEnd && !alreadyTriggered {
                self.advanceOrEndCustomQueueUnlocked(reason: "poller-stopped")
            }
        } else if pState == "stopped" && !confirmed && !isUserPaused && !isTransitioning && timeSincePlay >= 8.5 && !PlaybackRouter.shared.isTestingEnvironment {
            let alreadyTriggered = PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack
            }
            if !alreadyTriggered {
                NSLog("[QueueManager] ⏭ Cloud stream load timed out after %.1fs in stopped state — advancing queue", timeSincePlay)
                self.advanceOrEndCustomQueueUnlocked(reason: "cloud-load-timeout")
            }
        }
    }
}
