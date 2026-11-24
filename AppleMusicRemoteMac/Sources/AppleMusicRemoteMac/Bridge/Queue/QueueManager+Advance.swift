//
//  QueueManager+Advance.swift
//  AppleMusicRemoteMac
//
//  Queue timer lifecycle, deduplicated cutoff wakeups, Smart Transition intercepts,
//  custom queue advancement, and Radio Repeat-One enforcement.
//

import Foundation
import ScriptingBridge

extension QueueManager {

    public func startQueueMonitoring() {
        if PlaybackRouter.shared.isTestingEnvironment {
            return
        }
        timerLock.lock()
        defer { timerLock.unlock() }
        queueTimer?.cancel()
        queueTimer = nil
        pendingCutoffWakeupWorkItem?.cancel()
        pendingCutoffWakeupWorkItem = nil
        pendingCutoffWakeupDeadline = nil
        let timer = DispatchSource.makeTimerSource(queue: queueTimerQueue)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in
            self?.checkAndAutoAdvanceCloudQueue()
        }
        timer.resume()
        self.queueTimer = timer
    }

    public func stopQueueMonitoring() {
        timerLock.lock()
        defer { timerLock.unlock() }
        queueTimer?.cancel()
        queueTimer = nil
        pendingCutoffWakeupWorkItem?.cancel()
        pendingCutoffWakeupWorkItem = nil
        pendingCutoffWakeupDeadline = nil
    }

    /// Deduplicates sub-second smooth-cutoff `asyncAfter` wakeups so overlapping poller ticks cannot cascade exponentially.
    func schedulePrecisionCutoffWakeup(delay: TimeInterval) {
        let clampedDelay = max(0.015, delay)
        let targetDeadline = Date().addingTimeInterval(clampedDelay)
        timerLock.lock()
        if let existingDeadline = pendingCutoffWakeupDeadline,
           existingDeadline <= targetDeadline.addingTimeInterval(0.012) {
            timerLock.unlock()
            return
        }
        pendingCutoffWakeupWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.timerLock.withLock {
                self.pendingCutoffWakeupWorkItem = nil
                self.pendingCutoffWakeupDeadline = nil
            }
            self.checkAndAutoAdvanceCloudQueue()
        }
        pendingCutoffWakeupWorkItem = item
        pendingCutoffWakeupDeadline = targetDeadline
        timerLock.unlock()
        queueTimerQueue.asyncAfter(deadline: .now() + clampedDelay, execute: item)
    }

    internal func stopMusicAppImmediatelyForQueueCutoff() {
        if !PlaybackRouter.shared.isTestingEnvironment && PlaybackRouter.shared.urlOpener == nil {
            if SystemMusicPlayerBridge.shared.stop() {
                return
            }
            MusicAppProvider.shared.getMusicApp()?.pause()
        }
        _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop", maxWait: 1.2, reportTimeout: false)
    }

    /// Coordinates clean end-of-queue handling when the user presses Next on the final track with `repeatMode == "off"`.
    /// Stops live playback cleanly without falling through to `app.nextTrack()` while keeping the custom queue intact for Previous/Play.
    public func handleEndOfQueueManualNext() {
        PlaybackStateStore.shared.clearSeekTarget()
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isUserPaused = true
            PlaybackStateStore.shared.isStagingCloudTrack = false
            PlaybackStateStore.shared.isActivelyStagingInBuffer = false
            PlaybackStateStore.shared.activeLoadingStage = nil
            PlaybackStateStore.shared.activeLoadingStartedAt = nil
            PlaybackStateStore.shared.lastKnownPosition = 0.0
            PlaybackStateStore.shared.scheduledSmartTransitionStart = nil
            PlaybackStateStore.shared.lastSkipTime = .distantPast
        }
        PlaybackStateStore.shared.invalidateStatusCache(optimisticState: "stopped")
        PlaybackStateStore.shared.invalidateQueueCache()
        if !PlaybackRouter.shared.isTestingEnvironment {
            stopMusicAppImmediatelyForQueueCutoff()
            WebSocketServer.shared.broadcastStatus(includeQueue: true)
        }
    }

    public func handleSmartTransitionScheduleDetected(startSeconds: Double) {
        guard startSeconds > 4.0 else { return }
        queueTimerQueue.async { [weak self] in
            self?.checkAndAutoAdvanceCloudQueue()
        }
    }

    public func handleImmediateSmartTransitionBegan() {
        queueTimerQueue.async { [weak self] in
            guard let self = self else { return }

            // Radio Repeat-One: immediately seek to 0:00 when Music.app begins an early station crossfade / Smart Transition,
            // preserving the active Apple Music Radio session without ever resetting or leaving radio!
            let shouldRewindRadio: Bool = PlaybackStateStore.shared.withLock {
                let store = PlaybackStateStore.shared
                guard !store.isCustomQueuePlayback,
                      store.isRadioPlayback,
                      store.repeatMode == "one",
                      !store.isUserPaused,
                      Date().timeIntervalSince(store.lastRepeatOneRewindTime) >= 2.0 else {
                    return false
                }
                let cachedPos = store.lastPlayerStatusCache?.status.position ?? 0.0
                let livePos = PlaybackRouter.shared.isTestingEnvironment ? cachedPos : (MusicAppProvider.shared.getMusicApp()?.playerPosition ?? cachedPos)
                guard livePos > 2.5 else { return false }
                store.lastRepeatOneRewindTime = Date()
                return true
            }
            if shouldRewindRadio {
                NSLog("[QueueManager] 🔂 Radio Repeat ONE: Immediate Smart Transition intercept — seeking radio track to 0:00!")
                _ = PlaybackTransportController.shared.seek(to: 0.0)
                if !PlaybackRouter.shared.isTestingEnvironment {
                    WebSocketServer.shared.broadcastStatus(includeQueue: false)
                }
                return
            }

            let snapshot: (
                shouldIntercept: Bool,
                repeatMode: String,
                origPlName: String?
            ) = PlaybackStateStore.shared.withLock {
                let store = PlaybackStateStore.shared
                guard store.isCustomQueuePlayback,
                      !store.activeCustomQueue.isEmpty,
                      !store.isUserPaused,
                      !store.isTransitioningTrack,
                      store.currentTrackPlaybackConfirmed,
                      !store.hasTriggeredAdvanceForCurrentTrack else {
                    return (false, "off", nil)
                }
                let activeIdx = store.activeCustomQueueIndex
                let dur = (activeIdx >= 0 && activeIdx < store.activeCustomQueue.count)
                    ? store.activeCustomQueue[activeIdx].duration
                    : (store.lastPlayerStatusCache?.status.duration ?? 0.0)
                let timeSincePlay = store.lastCloudPlayTime.map { Date().timeIntervalSince($0) } ?? 0.0
                let nearEnd: Bool
                if dur > 8.0 {
                    nearEnd = (store.lastKnownPosition >= max(3.0, dur - 40.0)) || (timeSincePlay >= max(3.0, dur - 40.0))
                } else {
                    nearEnd = store.lastKnownPosition > 2.0 || timeSincePlay > 2.0
                }
                guard nearEnd else {
                    return (false, "off", nil)
                }
                return (true, store.repeatMode, store.currentOriginalPlaylistName)
            }
            guard snapshot.shouldIntercept else { return }

            let cachedPlName = PlayerStatusEngine.shared.cachedCurrentPlaylistName
            if let curPl = cachedPlName, !curPl.isEmpty, curPl != "Очередь AMR",
               let origPl = snapshot.origPlName, !origPl.isEmpty, origPl != "Очередь AMR",
               curPl == origPl {
                return
            }

            if snapshot.repeatMode == "one" {
                let lastRewind = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.lastRepeatOneRewindTime }
                if Date().timeIntervalSince(lastRewind) >= 2.0 {
                    PlaybackStateStore.shared.withLock {
                        PlaybackStateStore.shared.lastRepeatOneRewindTime = Date()
                    }
                    _ = PlaybackTransportController.shared.seek(to: 0.0)
                    if !PlaybackRouter.shared.isTestingEnvironment {
                        WebSocketServer.shared.broadcastStatus(includeQueue: false)
                    }
                }
                return
            }

            NSLog("[QueueManager] ⚡️ Immediate Smart Transition intercept fired — stopping Music.app before AutoPlay overlap!")
            self.stopMusicAppImmediatelyForQueueCutoff()
            self.advanceOrEndCustomQueueUnlocked(reason: "smart-transition-intercept")
        }
    }

    private enum QueueAdvanceAction {
        case none
        case playIndex(Int)
        case stopSingleTrack
        case transitionToArtistRadio(TrackInfo)
    }

    /// Advances, repeats, stops, or transitions to radio when a track in customQueue finishes or needs auto-advance.
    func advanceOrEndCustomQueueUnlocked(reason: String) {
        monitorLock.lock()
        defer { monitorLock.unlock() }

        let action: QueueAdvanceAction = PlaybackStateStore.shared.withLock {
            if PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack && reason != "manual-next" {
                NSLog("[QueueManager] ⏭ Ignoring duplicate advance trigger (%@) — already triggered for index %d", reason, PlaybackStateStore.shared.activeCustomQueueIndex)
                return .none
            }
            let activeIdx = PlaybackStateStore.shared.activeCustomQueueIndex
            let queueTracks = PlaybackStateStore.shared.activeCustomQueue
            guard !queueTracks.isEmpty else { return .none }

            let repeatMode = PlaybackStateStore.shared.repeatMode
            let isShuf = PlaybackStateStore.shared.isShuffleQueueActive

            // Case 1: Repeat ONE track
            if repeatMode == "one" && activeIdx >= 0 && activeIdx < queueTracks.count {
                NSLog("[QueueManager] 🔂 Repeat ONE (%@): Replaying index %d: '%@'", reason, activeIdx, queueTracks[activeIdx].name)
                PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = true
                PlaybackStateStore.shared.lastWasPlayingCloud = false
                PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
                return .playIndex(activeIdx)
            }

            // Case 2: Next track in queue
            if activeIdx + 1 < queueTracks.count {
                let nextIdx = activeIdx + 1
                NSLog("[QueueManager] ⏭ Auto-advancing (%@) to index %d/%d: '%@' — '%@'", reason, nextIdx + 1, queueTracks.count, queueTracks[nextIdx].artist, queueTracks[nextIdx].name)
                PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = true
                PlaybackStateStore.shared.lastWasPlayingCloud = false
                PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
                return .playIndex(nextIdx)
            }

            let (searchQ, isFetching, curatorP, isFetchingCurator) = (
                PlaybackStateStore.shared.activeSearchQuery,
                PlaybackStateStore.shared.isFetchingNextSearchPage,
                PlaybackStateStore.shared.activeCuratorPrompt,
                PlaybackStateStore.shared.isFetchingNextCuratorPage
            )
            if (searchQ != nil && isFetching) || (curatorP != nil && isFetchingCurator) {
                return .none
            }

            // Case 3: End of queue reached (activeIdx + 1 >= queueTracks.count)
            if repeatMode == "all" {
                if isShuf && queueTracks.count > 1 {
                    let lastTrackId = (activeIdx < queueTracks.count) ? queueTracks[activeIdx].id : ""
                    var newQueue = queueTracks
                    newQueue.shuffle()
                    if newQueue.first?.id == lastTrackId && newQueue.count > 1 {
                        let swapIdx = Int.random(in: 1..<newQueue.count)
                        newQueue.swapAt(0, swapIdx)
                    }
                    for i in 0..<newQueue.count {
                        newQueue[i].index = i + 1
                    }
                    NSLog("[QueueManager] 🔁 Infinite shuffle loop (%@): Reshuffled %d tracks for next cycle. First track: '%@'", reason, newQueue.count, newQueue[0].name)
                    PlaybackStateStore.shared.activeCustomQueue = newQueue
                    PlaybackStateStore.shared.activeCustomQueueIndex = 0
                    PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = true
                    PlaybackStateStore.shared.lastWasPlayingCloud = false
                    PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
                    return .playIndex(0)
                } else {
                    NSLog("[QueueManager] 🔁 Repeat ALL loop (%@): Looping back to index 0: '%@'", reason, queueTracks[0].name)
                    PlaybackStateStore.shared.activeCustomQueueIndex = 0
                    PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = true
                    PlaybackStateStore.shared.lastWasPlayingCloud = false
                    PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
                    return .playIndex(0)
                }
            }

            // Case 4: No repeat (repeatMode == "off")
            if queueTracks.count <= 1 {
                NSLog("[QueueManager] ⏹ Single track completed with repeat=off (%@). Stopping playback cleanly without radio fallback.", reason)
                PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = true
                PlaybackStateStore.shared.isUserPaused = true
                PlaybackStateStore.shared.isCustomQueuePlayback = false
                PlaybackStateStore.shared.activeCustomQueue.removeAll()
                PlaybackStateStore.shared.activeCustomQueueIndex = 0
                PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
                PlaybackStateStore.shared.lastWasPlayingCloud = false
                return .stopSingleTrack
            } else {
                let lastTrack = (activeIdx < queueTracks.count) ? queueTracks[activeIdx] : queueTracks.last!
                NSLog("[QueueManager] 📻 Custom queue finished all %d tracks (%@)! Transitioning to artist radio for '%@'", queueTracks.count, reason, lastTrack.artist)
                PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = true
                PlaybackStateStore.shared.isCustomQueuePlayback = false
                PlaybackStateStore.shared.activeCustomQueue.removeAll()
                PlaybackStateStore.shared.activeCustomQueueIndex = 0
                PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
                PlaybackStateStore.shared.lastWasPlayingCloud = false
                return .transitionToArtistRadio(lastTrack)
            }
        }

        switch action {
        case .none:
            return
        case .playIndex(let idx):
            let runPlayBlock = { [weak self] in
                guard let self = self else { return }
                _ = self.playQueueIndexUnlocked(idx)
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
                if !PlaybackRouter.shared.isTestingEnvironment {
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.6) {
                        PlaybackStateStore.shared.invalidateQueueCache()
                        PlaybackStateStore.shared.invalidateStatusCache()
                        WebSocketServer.shared.broadcastStatus(includeQueue: true)
                    }
                }
            }
            if PlaybackRouter.shared.isTestingEnvironment {
                runPlayBlock()
            } else {
                DispatchQueue.global(qos: .userInitiated).async(execute: runPlayBlock)
            }
        case .stopSingleTrack:
            _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop")
            stopQueueMonitoring()
            PlaybackStateStore.shared.scheduleIdleStagedCleanup(after: 300.0)
            MusicKitManager.shared.cleanupTemporaryPlaybackPlaylists(keepingActiveQueue: false)
            PlaybackStateStore.shared.invalidateQueueCache()
            PlaybackStateStore.shared.invalidateStatusCache()
            WebSocketServer.shared.broadcastStatus(includeQueue: true)
        case .transitionToArtistRadio(let lastTrack):
            _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop")
            stopQueueMonitoring()
            PlaybackStateStore.shared.scheduleIdleStagedCleanup(after: 300.0)
            MusicKitManager.shared.cleanupTemporaryPlaybackPlaylists(keepingActiveQueue: false)
            PlaybackStateStore.shared.invalidateQueueCache()
            PlaybackStateStore.shared.invalidateStatusCache()
            WebSocketServer.shared.broadcastStatus(includeQueue: true)
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

    /// Asynchronously resolves catalog duration when `Music.app` reports `duration == 0` for an Apple Music Radio stream,
    /// enabling exact pre-EOF `seek(to: 0.0)` looping without exiting the radio station.
    public func resolveRadioPinnedTrackDurationIfNeeded(name: String, artist: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !PlaybackRouter.shared.isTestingEnvironment else { return }
        let key = "\(cleanArtist.lowercased()):\(cleanName.lowercased())"
        let shouldStart: Bool = PlaybackStateStore.shared.withLock {
            if PlaybackStateStore.shared.resolvingRadioDurationTrackKey == key {
                return false
            }
            if let pinned = PlaybackStateStore.shared.repeatOnePinnedTrack,
               pinned.name.localizedCaseInsensitiveCompare(cleanName) == .orderedSame,
               pinned.duration > 5.0 {
                return false
            }
            PlaybackStateStore.shared.resolvingRadioDurationTrackKey = key
            return true
        }
        guard shouldStart else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            var resolvedDur: Double = 0
            if let sbDur = MusicAppProvider.shared.getMusicApp()?.currentTrack?.sbDuration, sbDur > 5.0 {
                resolvedDur = sbDur
            }
            if resolvedDur <= 5.0,
               let cid = MusicKitManager.shared.getCachedTrackCatalogId(name: cleanName, artist: cleanArtist, album: "")
                   ?? MusicKitManager.shared.resolveCatalogSongIdInUserStorefrontSync(name: cleanName, artist: cleanArtist),
               let info = MusicKitManager.shared.inspectCatalogSongDirectCloudEligibilitySync(catalogId: cid),
               let catDur = info.durationSeconds, catDur > 5.0 {
                resolvedDur = catDur
            }
            PlaybackStateStore.shared.withLock {
                if PlaybackStateStore.shared.resolvingRadioDurationTrackKey == key {
                    PlaybackStateStore.shared.resolvingRadioDurationTrackKey = nil
                }
                guard resolvedDur > 5.0 else { return }
                if var pinned = PlaybackStateStore.shared.repeatOnePinnedTrack,
                   pinned.name.localizedCaseInsensitiveCompare(cleanName) == .orderedSame {
                    pinned.duration = resolvedDur
                    PlaybackStateStore.shared.repeatOnePinnedTrack = pinned
                }
                if var cached = PlaybackStateStore.shared.lastPlayerStatusCache,
                   cached.status.isRadio,
                   cached.status.track?.name.localizedCaseInsensitiveCompare(cleanName) == .orderedSame,
                   cached.status.duration <= 0 {
                    cached.status.duration = resolvedDur
                    cached.status.track?.duration = resolvedDur
                    PlaybackStateStore.shared.lastPlayerStatusCache = cached
                }
            }
        }
    }

    /// Enforces `repeatMode == "one"` during Apple Music Radio / station playback strictly via `seek(to: 0.0)`
    /// BEFORE track end or station crossfade — NEVER replacing the radio stream with a custom queue (`playSearchResults`).
    func enforceRadioRepeatOneLocked(triggerTrackName: String? = nil, triggerArtistName: String? = nil) {
        let (repMode, isRadio, stationName, pinnedTrack, lastRewind, isUserPaused, isStaging, scheduledSmartStart) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.repeatMode,
                PlaybackStateStore.shared.isRadioPlayback,
                PlaybackStateStore.shared.activeStationName,
                PlaybackStateStore.shared.repeatOnePinnedTrack,
                PlaybackStateStore.shared.lastRepeatOneRewindTime,
                PlaybackStateStore.shared.isUserPaused,
                PlaybackStateStore.shared.isStagingCloudTrack,
                PlaybackStateStore.shared.scheduledSmartTransitionStart
            )
        }
        guard repMode == "one", !isUserPaused, !isStaging else { return }

        let status = PlayerStatusEngine.shared.getPlayerStatus()
        let activeRadio = isRadio || status.isRadio
        guard activeRadio else { return }
        guard status.playerState == "playing" else { return }

        let rawName = (triggerTrackName?.isEmpty == false) ? triggerTrackName! : (status.track?.name ?? "")
        let curName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let curArtist = ((triggerArtistName != nil) ? triggerArtistName! : (status.track?.artist ?? "")).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !curName.isEmpty else { return }

        let lowerName = curName.lowercased()
        if (lowerName.hasPrefix("станция:") || lowerName.hasPrefix("station:") || curName == (stationName ?? "")) &&
            (curArtist.isEmpty || curArtist == "Apple Music") {
            return
        }

        var currentPinned = pinnedTrack
        if currentPinned == nil || !isTrackMatching(expected: currentPinned!, candidateName: curName, candidateArtist: curArtist) {
            // Update pinned track in-place (e.g. after manual Next or station start) — NEVER call `playSearchResults`,
            // which would exit and destroy the active Apple Music Radio session!
            let candidate = status.track ?? TrackInfo(
                id: "radio_pinned",
                numericId: nil,
                name: curName,
                artist: curArtist,
                album: "",
                duration: status.duration,
                hasArtwork: false,
                artworkUrl: "",
                favorited: false,
                isLocal: false,
                url: nil,
                index: 1
            )
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.repeatOnePinnedTrack = candidate
                PlaybackStateStore.shared.scheduledSmartTransitionStart = nil
            }
            currentPinned = candidate
        }

        var dur = status.duration
        if dur <= 5.0, let pinnedDur = currentPinned?.duration, pinnedDur > 5.0 {
            dur = pinnedDur
        }
        if dur <= 5.0, !PlaybackRouter.shared.isTestingEnvironment,
           let sbDur = MusicAppProvider.shared.getMusicApp()?.currentTrack?.sbDuration, sbDur > 5.0 {
            dur = sbDur
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.repeatOnePinnedTrack?.duration = sbDur
            }
        }
        if dur <= 5.0 {
            resolveRadioPinnedTrackDurationIfNeeded(name: curName, artist: curArtist)
            return
        }

        var livePos = status.position
        if dur - livePos <= 8.0, !PlaybackRouter.shared.isTestingEnvironment, let app = MusicAppProvider.shared.getMusicApp() {
            let directPos = app.playerPosition
            if directPos > 0 {
                livePos = directPos
            }
        }

        let validSmartStart: Double? = {
            guard let s = scheduledSmartStart,
                  dur > 8.0,
                  s >= max(4.0, max(dur * 0.55, dur - 38.0)),
                  s <= dur + 0.5 else {
                return nil
            }
            return s
        }()
        let baseRewindPos = max(1.0, dur - 1.85)
        let rewindThreshold = validSmartStart.map { max(1.0, min(baseRewindPos, $0 - 0.45)) } ?? baseRewindPos
        let remaining = rewindThreshold - livePos

        if remaining <= 0.0 && Date().timeIntervalSince(lastRewind) >= 2.0 {
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.lastRepeatOneRewindTime = Date()
            }
            NSLog("[QueueManager] 🔂 Radio Repeat ONE: Seeking '%@' at %.2f/%.2fs to 0:00 (keeping radio station active)", curName, livePos, dur)
            _ = PlaybackTransportController.shared.seek(to: 0.0)
            WebSocketServer.shared.broadcastStatus(includeQueue: false)
        } else if !PlaybackRouter.shared.isTestingEnvironment && remaining > 0.0 && remaining <= 0.85 {
            let wakeDelay = max(0.02, min(remaining + 0.01, remaining * 0.6))
            self.schedulePrecisionCutoffWakeup(delay: wakeDelay)
        }
    }
}
