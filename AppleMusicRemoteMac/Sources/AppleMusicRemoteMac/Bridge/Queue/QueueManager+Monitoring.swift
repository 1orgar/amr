//
//  QueueManager+Monitoring.swift
//  AppleMusicRemoteMac
//

import Foundation
import ScriptingBridge

extension QueueManager {
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

    private static let bracketRegex = try? NSRegularExpression(pattern: "\\s*[\\[\\(].*?[\\]\\)]", options: [])

    func normalizeTrackTitle(_ title: String) -> String {
        var t = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["станция: ", "станция:", "station: ", "station:"] {
            if t.hasPrefix(prefix) {
                t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if t.hasSuffix(" station") {
            t = String(t.dropLast(" station".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let regex = Self.bracketRegex {
            t = regex.stringByReplacingMatches(in: t, options: [], range: NSRange(location: 0, length: t.utf16.count), withTemplate: "")
        }
        if let dashIdx = t.range(of: " - ") {
            t = String(t[..<dashIdx.lowerBound])
        }
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        t = t.components(separatedBy: allowed.inverted).joined()
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isTrackMatching(expected: TrackInfo, candidateName: String, candidateArtist: String? = nil) -> Bool {
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
                // Localization support: If artist matches and either title has non-ASCII characters
                // (e.g. Japanese Kanji '人芝居' vs English 'Hitoshibai'), treat as match
                let hasNonAscii = !en.allSatisfy({ $0.isASCII }) || !cn.allSatisfy({ $0.isASCII })
                if hasNonAscii && (normEa == normCa) {
                    return true
                }
            }
        }
        return false
    }

    /// Advances, repeats, stops, or transitions to radio when a track in customQueue finishes or needs auto-advance.
    /// Caller MUST hold PlaybackStateStore.shared.withLock (or be in a thread-safe context).
    func advanceOrEndCustomQueueUnlocked(reason: String) {
        let activeIdx = PlaybackStateStore.shared.activeCustomQueueIndex
        let queueTracks = PlaybackStateStore.shared.activeCustomQueue
        guard !queueTracks.isEmpty else { return }

        let repeatMode = PlaybackStateStore.shared.repeatMode
        let isShuf = PlaybackStateStore.shared.isShuffleQueueActive

        // Case 1: Repeat ONE track
        if repeatMode == "one" && activeIdx >= 0 && activeIdx < queueTracks.count {
            NSLog("[QueueManager] 🔂 Repeat ONE (%@): Replaying index %d: '%@'", reason, activeIdx, queueTracks[activeIdx].name)
            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = true
            PlaybackStateStore.shared.lastWasPlayingCloud = false
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
            _ = self.playQueueIndexUnlocked(activeIdx)
            return
        }

        // Case 2: Next track in queue
        if activeIdx + 1 < queueTracks.count {
            let nextIdx = activeIdx + 1
            NSLog("[QueueManager] ⏭ Auto-advancing (%@) to index %d/%d: '%@'", reason, nextIdx, queueTracks.count, queueTracks[nextIdx].name)
            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = true
            PlaybackStateStore.shared.lastWasPlayingCloud = false
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
            _ = self.playQueueIndexUnlocked(nextIdx)
            return
        }

        // Check if auto-fetching more search results is in progress
        let (searchQ, isFetching) = (PlaybackStateStore.shared.activeSearchQuery, PlaybackStateStore.shared.isFetchingNextSearchPage)
        if searchQ != nil && isFetching {
            return
        }

        // Case 3: End of queue reached (activeIdx + 1 >= queueTracks.count)
        if repeatMode == "all" {
            // Repeat ALL
            if isShuf && queueTracks.count > 1 {
                // "зацикленность + рандом – бесконечный рандом: рандом должен быть рандом, но не более 1 раза на трек"
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
                _ = self.playQueueIndexUnlocked(0)
            } else {
                // Normal repeat loop
                NSLog("[QueueManager] 🔁 Repeat ALL loop (%@): Looping back to index 0: '%@'", reason, queueTracks[0].name)
                PlaybackStateStore.shared.activeCustomQueueIndex = 0
                PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = true
                PlaybackStateStore.shared.lastWasPlayingCloud = false
                PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
                _ = self.playQueueIndexUnlocked(0)
            }
            return
        }

        // Case 4: No repeat (repeatMode == "off")
        if queueTracks.count <= 1 {
            // "заставить music app играть ровно 1 трек без фоллбека на радио после - запустил, отыграл, остановил"
            NSLog("[QueueManager] ⏹ Single track completed with repeat=off (%@). Stopping playback cleanly without radio fallback.", reason)
            _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop")
            stopQueueMonitoring()
            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = true
            PlaybackStateStore.shared.isUserPaused = true
            PlaybackStateStore.shared.isCustomQueuePlayback = false
            PlaybackStateStore.shared.activeCustomQueue.removeAll()
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
            PlaybackStateStore.shared.lastWasPlayingCloud = false
            PlaybackStateStore.shared.invalidateQueueCache()
            PlaybackStateStore.shared.invalidateStatusCache()
            WebSocketServer.shared.broadcastStatus(includeQueue: true)
            return
        } else {
            // Multi-track queue finished!
            // "если зацикленности нет - то по сле прослушивания всех треков - переходи к радио по этому плейлисту, НО ТОЛЬКО после завершения всех треков"
            let lastTrack = (activeIdx < queueTracks.count) ? queueTracks[activeIdx] : queueTracks.last!
            NSLog("[QueueManager] 📻 Custom queue finished all %d tracks (%@)! Transitioning to artist radio for '%@'", queueTracks.count, reason, lastTrack.artist)
            _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop")
            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = true
            PlaybackStateStore.shared.isCustomQueuePlayback = false
            PlaybackStateStore.shared.activeCustomQueue.removeAll()
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
            PlaybackStateStore.shared.lastWasPlayingCloud = false
            stopQueueMonitoring()
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
            return
        }
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
        // If unconfirmed or stopped early, Music.app is buffering, paused, or switching streams, so do NOT skip!
        if state == "stopped" {
            let (alreadyTriggered, lastKnownPos) = PlaybackStateStore.shared.withLock {
                (PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack, PlaybackStateStore.shared.lastKnownPosition)
            }
            if timeSincePlay < 15.0 && lastKnownPos < 10.0 {
                return
            }
            let status = PlayerStatusEngine.shared.getPlayerStatus()
            let dur = status.duration > 0 ? status.duration : (queueTracks[activeIdx].duration > 0 ? queueTracks[activeIdx].duration : 180.0)
            let effectivePos = max(status.position, lastKnownPos)
            let isNearEnd = (dur > 15.0 && effectivePos >= dur - 3.5) || (dur > 15.0 && timeSincePlay >= dur - 3.5) || (effectivePos >= 30.0 && effectivePos >= dur * 0.9)
            if confirmed && !alreadyTriggered && isNearEnd {
                PlaybackStateStore.shared.withLock {
                    self.advanceOrEndCustomQueueUnlocked(reason: "notification-stopped")
                }
            }
            return
        }

        guard !trackName.isEmpty else { return }
        let lowerTrackName = trackName.lowercased()
        if (lowerTrackName.hasPrefix("станция:") || lowerTrackName.hasPrefix("station:")) && (artistName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
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
        if isTransitioning || timeSincePlay < 3.5 {
            return
        }

        let origPlName = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.currentOriginalPlaylistName }

        // 4. Past tracks in custom queue:
        if let pastIdx = queueTracks[..<activeIdx].firstIndex(where: { isTrackMatching(expected: $0, candidateName: trackName, candidateArtist: artistName) }) {
            if let orig = origPlName, !orig.isEmpty, confirmed {
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.activeCustomQueueIndex = pastIdx
                    PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                    PlaybackStateStore.shared.lastWasPlayingCloud = true
                    PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
                }
            }
            return
        }

        // 5. Forward tracks in custom queue (natural advance or jump):
        if let relativeIdx = queueTracks[activeIdx...].firstIndex(where: { isTrackMatching(expected: $0, candidateName: trackName, candidateArtist: artistName) }) {
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.activeCustomQueueIndex = relativeIdx
                PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                PlaybackStateStore.shared.lastWasPlayingCloud = true
                PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
            }
            return
        }

        // 6. Track is foreign (not matching expected track in customQueue):
        let isAMRPlaylist = (origPlName == "Очередь AMR")
        if isAMRPlaylist {
            let isStaging = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isStagingCloudTrack }
            if isStaging {
                return
            }
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                PlaybackStateStore.shared.lastWasPlayingCloud = true
                PlaybackStateStore.shared.lastSkipTime = .distantPast
            }
            return
        }

        if let orig = origPlName, !orig.isEmpty, orig != "Очередь AMR" {
            let cachedPl = PlayerStatusEngine.shared.cachedCurrentPlaylistName
            let isCurrentPlMatch = PlaybackRouter.shared.isTestingEnvironment || (cachedPl == orig)
            if isCurrentPlMatch {
                // Actually playing inside a named playlist, never stop audio!
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                    PlaybackStateStore.shared.lastWasPlayingCloud = true
                    PlaybackStateStore.shared.lastSkipTime = .distantPast
                }
                return
            }
        }

        if !isTransitioning && (confirmed || timeSincePlay >= 3.0) {
            let lastSkip = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.lastSkipTime }
            if Date().timeIntervalSince(lastSkip) < 3.0 {
                return
            }
            NSLog("[QueueManager] 🛡 Notification: Foreign track '%@' by '%@' while in custom queue! Stopping audio and advancing/ending queue.",
                  trackName, artistName ?? "")
            _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop")
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.lastSkipTime = Date()
                self.advanceOrEndCustomQueueUnlocked(reason: "notification-foreign")
            }
            return
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
            // Auto-fetch next search page when approaching end of search queue (3 tracks before end)
            let (searchQuery, isFetching, qCount) = PlaybackStateStore.shared.withLock {
                (
                    PlaybackStateStore.shared.activeSearchQuery,
                    PlaybackStateStore.shared.isFetchingNextSearchPage,
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
            }

            let origPlName = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.currentOriginalPlaylistName }
            let isAMR = (origPlName == "Очередь AMR")
            if isAMR {
                if activeIdx < queueTracks.count {
                    let expectedTrack = queueTracks[activeIdx]
                    if PlaybackRouter.shared.isTestingEnvironment || isTrackMatching(expected: expectedTrack, candidateName: curTrackName, candidateArtist: curArtist) {
                        PlaybackStateStore.shared.withLock {
                            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                            PlaybackStateStore.shared.lastWasPlayingCloud = true
                            PlaybackStateStore.shared.lastSkipTime = .distantPast
                            if pos > 0 {
                                PlaybackStateStore.shared.lastKnownPosition = pos
                            }
                            if dur > 0 && activeIdx < PlaybackStateStore.shared.activeCustomQueue.count && PlaybackStateStore.shared.activeCustomQueue[activeIdx].duration <= 0 {
                                PlaybackStateStore.shared.activeCustomQueue[activeIdx].duration = dur
                            }
                            if pos >= 1.0 && pos < (dur > 3.0 ? dur - 3.0 : 1000.0) {
                                PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
                            }
                        }
                    }
                }
                return
            }

            if !curTrackName.isEmpty && activeIdx < queueTracks.count {
                let expectedTrack = queueTracks[activeIdx]
                let matchesExpected = isTrackMatching(expected: expectedTrack, candidateName: curTrackName, candidateArtist: curArtist)

                if matchesExpected {
                    PlaybackStateStore.shared.withLock {
                        PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                        PlaybackStateStore.shared.lastWasPlayingCloud = true
                        PlaybackStateStore.shared.lastSkipTime = .distantPast
                        if pos > 0 {
                            PlaybackStateStore.shared.lastKnownPosition = pos
                        }
                        if dur > 0 && activeIdx < PlaybackStateStore.shared.activeCustomQueue.count && PlaybackStateStore.shared.activeCustomQueue[activeIdx].duration <= 0 {
                            PlaybackStateStore.shared.activeCustomQueue[activeIdx].duration = dur
                        }
                        if pos >= 1.0 && pos < (dur > 3.0 ? dur - 3.0 : 1000.0) {
                            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
                        }
                    }
                } else if (curTrackName.lowercased().hasPrefix("станция:") || curTrackName.lowercased().hasPrefix("station:")) && curArtist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return
                } else if isTransitioning || timeSincePlay < 3.5 {
                    // Still transitioning to activeIdx, ignore mismatch from draining track
                    return
                } else if let pastIdx = queueTracks[..<activeIdx].firstIndex(where: { isTrackMatching(expected: $0, candidateName: curTrackName, candidateArtist: curArtist) }) {
                    // Past track in custom queue: only sync backward if playing a native multi-track playlist; otherwise ignore draining track
                    if let orig = origPlName, !orig.isEmpty, confirmed {
                        PlaybackStateStore.shared.withLock {
                            PlaybackStateStore.shared.activeCustomQueueIndex = pastIdx
                            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                            PlaybackStateStore.shared.lastWasPlayingCloud = true
                            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
                        }
                    }
                    return
                } else if let relativeIdx = queueTracks[activeIdx...].firstIndex(where: { isTrackMatching(expected: $0, candidateName: curTrackName, candidateArtist: curArtist) }) {
                    // Synced forward to an upcoming track in the queue
                    PlaybackStateStore.shared.withLock {
                        PlaybackStateStore.shared.activeCustomQueueIndex = relativeIdx
                        PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                        PlaybackStateStore.shared.lastWasPlayingCloud = true
                        PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
                    }
                    return
                } else if let orig = origPlName, !orig.isEmpty {
                    let cachedPl = PlayerStatusEngine.shared.cachedCurrentPlaylistName
                    let isCurrentPlMatch = PlaybackRouter.shared.isTestingEnvironment || (cachedPl == orig)
                    if isCurrentPlMatch {
                        // Actually playing in a named playlist (e.g. "Любимые песни"), never stop audio!
                        PlaybackStateStore.shared.withLock {
                            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                            PlaybackStateStore.shared.lastWasPlayingCloud = true
                            PlaybackStateStore.shared.lastSkipTime = .distantPast
                        }
                        return
                    }
                } else {
                    // Foreign track playing while in custom queue
                    if confirmed && !isTransitioning && timeSincePlay >= 3.0 {
                        let lastSkip = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.lastSkipTime }
                        if Date().timeIntervalSince(lastSkip) < 3.0 {
                            return
                        }
                        NSLog("[QueueManager] 🛡 Poller: Foreign radio track '%@' by '%@' while in custom queue! Stopping audio and advancing or ending queue.",
                              curTrackName, curArtist)
                        _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop")
                        PlaybackStateStore.shared.withLock {
                            PlaybackStateStore.shared.lastSkipTime = Date()
                            self.advanceOrEndCustomQueueUnlocked(reason: "poller-foreign")
                        }
                        return
                    }
                }
            }

            // Smooth advance before song finishes completely (3.0s before end)
            let alreadyTriggered = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack }
            let isNativePlayingPlaylist: Bool = {
                if isAMR { return true }
                guard let curPl = PlayerStatusEngine.shared.cachedCurrentPlaylistName,
                      !curPl.isEmpty,
                      let origPl = origPlName,
                      !origPl.isEmpty,
                      curPl == origPl else {
                    return false
                }
                return true
            }()
            let currentRepeatMode = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.repeatMode }
            if confirmed && !alreadyTriggered && dur > 5.0 && pos > 1.0 && timeSincePlay >= 2.0 && (pos >= (dur - 3.0) || timeSincePlay >= (dur - 3.0)) {
                if isNativePlayingPlaylist {
                    // When playing a native Music.app playlist or AMR queue, Music.app naturally and gaplessly
                    // advances to the next track. Do NOT issue a disruptive "stop" command!
                    // The track notification / poller will detect the new track and sync activeCustomQueueIndex.
                } else if queueTracks.count <= 1 && currentRepeatMode == "off" {
                    // For a single track with repeat=off, let it play naturally to the very end!
                    // Do NOT preemptively stop it 3s early. The "stopped" state or foreign track handler will catch the end cleanly.
                } else {
                    _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop")
                    PlaybackStateStore.shared.withLock {
                        self.advanceOrEndCustomQueueUnlocked(reason: "smooth-advance")
                    }
                }
            }
        } else if pState == "stopped" && lastWasPlaying && confirmed {
            // Natural track finish: only advance if the track was confirmed playing AND actually reached near the end
            let (alreadyTriggered, lastKnownPos) = PlaybackStateStore.shared.withLock {
                (PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack, PlaybackStateStore.shared.lastKnownPosition)
            }
            let effectivePos = max(pos, lastKnownPos)
            let isNearEnd = (dur > 15.0 && effectivePos >= dur - 3.5) || (dur > 15.0 && timeSincePlay >= dur - 3.5) || (effectivePos >= 30.0 && effectivePos >= dur * 0.9)
            if isNearEnd && !alreadyTriggered {
                PlaybackStateStore.shared.withLock {
                    self.advanceOrEndCustomQueueUnlocked(reason: "poller-stopped")
                }
            }
        }
    }
}
