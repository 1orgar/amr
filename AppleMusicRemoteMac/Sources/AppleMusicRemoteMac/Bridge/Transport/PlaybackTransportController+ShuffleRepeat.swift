//
//  PlaybackTransportController+ShuffleRepeat.swift
//  AppleMusicRemoteMac
//
//  Shuffle (including deterministic local-playlist promotion), Repeat (including non-destructive
//  Radio Repeat-One pinning), Favorites, and manual Add-to-Library transport actions.
//

import Foundation
import ScriptingBridge

extension PlaybackTransportController {

    public func setShuffle(_ enabled: Bool) -> Bool {
        let isRadio = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isRadioPlayback || (PlaybackStateStore.shared.lastPlayerStatusCache?.status.isRadio == true)
        }
        if isRadio && enabled {
            NSLog("[PlaybackTransportController] 📻 Shuffle is disabled during radio playback")
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.isShuffleQueueActive = false
            }
            PlayerStatusEngine.shared.updateCachedShuffle(false)
            WebSocketServer.shared.broadcastStatus(includeQueue: false)
            return false
        }

        PlaybackStateStore.shared.invalidateQueueCache()

        // If a native local/library playlist is currently playing without a custom queue (`isCustomQueuePlayback == false`)
        // and the user enables Shuffle, promote the playlist into `activeCustomQueue` once so the queue NEVER regenerates
        // after every track and `setShuffle(false)` can cleanly restore the unshuffled playlist order!
        let needsPlaylistPromotion: Bool = PlaybackStateStore.shared.withLock {
            enabled && !PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackRouter.shared.isTestingEnvironment
        }
        if needsPlaylistPromotion {
            let origPl = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.currentOriginalPlaylistName }
            let status = PlayerStatusEngine.shared.getPlayerStatus()
            let candidatePl = (origPl?.isEmpty == false ? origPl! : (PlayerStatusEngine.shared.cachedCurrentPlaylistName ?? status.playlist))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let lowerPl = candidatePl.lowercased()
            let isGenericMaster = candidatePl.isEmpty
                || LibraryService.masterLibraryPlaylistNames.contains(lowerPl)
                || lowerPl == "apple music"
                || lowerPl == "apple music radio"
            var rawPlTracks: [TrackInfo] = []
            if !isGenericMaster {
                rawPlTracks = LibraryService.shared.getPlaylistTracks(name: candidatePl)
            }
            if rawPlTracks.isEmpty && !isGenericMaster {
                rawPlTracks = LibraryService.shared.getCurrentPlaylistTracks()
            }
            if rawPlTracks.count > 1 {
                let resolvedTracks = LibraryService.shared.resolveLocalLibraryMatches(
                    rawPlTracks,
                    updateNames: false,
                    includeStagedTemporary: false
                )
                let curDbId = status.track?.numericId ?? 0
                let curName = status.track?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let curArtist = status.track?.artist.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                var curIdx = 0
                if let matchIdx = resolvedTracks.firstIndex(where: {
                    (curDbId > 0 && $0.numericId == curDbId) ||
                    (!curName.isEmpty && $0.name.localizedCaseInsensitiveCompare(curName) == .orderedSame &&
                     (curArtist.isEmpty || $0.artist.isEmpty || $0.artist.localizedCaseInsensitiveCompare(curArtist) == .orderedSame))
                }) {
                    curIdx = matchIdx
                }
                var unshuffled = resolvedTracks
                for i in 0..<unshuffled.count { unshuffled[i].index = i + 1 }

                let curTrack = resolvedTracks[curIdx]
                var others = resolvedTracks
                others.remove(at: curIdx)
                others.shuffle()
                var combined = [curTrack] + others
                for i in 0..<combined.count { combined[i].index = i + 1 }

                let gen = PlaybackStateStore.shared.withLock { () -> UInt64 in
                    PlaybackStateStore.shared.originalCustomQueue = unshuffled
                    PlaybackStateStore.shared.activeCustomQueue = combined
                    PlaybackStateStore.shared.activeCustomQueueIndex = 0
                    PlaybackStateStore.shared.activeCustomQueueName = candidatePl
                    PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                    PlaybackStateStore.shared.isCustomQueuePlayback = true
                    PlaybackStateStore.shared.isShuffleQueueActive = true
                    PlaybackStateStore.shared.activeShuffledQueue.removeAll()
                    PlaybackStateStore.shared.activeShuffledIndex = 0
                    PlaybackStateStore.shared.activeShuffledPlaylistName = nil
                    PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                    PlaybackStateStore.shared.lastWasPlayingCloud = true
                    PlaybackStateStore.shared.lastCloudPlayTime = Date()
                    PlaybackStateStore.shared.latestUpcomingTracks = combined.count > 1 ? Array(combined[1...]) : []
                    PlaybackStateStore.shared.latestHistoryTracks = []
                    PlaybackStateStore.shared.lastShuffleSetTime = Date()
                    return PlaybackStateStore.shared.playbackGeneration
                }
                if let app = MusicAppProvider.shared.getMusicApp() {
                    app.shuffleEnabled = false
                }
                QueueManager.shared.startQueueMonitoring()
                if combined.count > 1 {
                    PlaybackRouter.shared.prestageUpcomingCloudTracks(
                        fromIndex: 1,
                        count: 6,
                        expectedGeneration: gen,
                        immediate: true
                    )
                }
                PlaybackStateStore.shared.invalidateQueueCache()
                PlayerStatusEngine.shared.updateCachedShuffle(true)
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
                return true
            }
        }

        var prestageInfo: (nextIdx: Int, gen: UInt64)? = nil
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isShuffleQueueActive = enabled
            if !enabled {
                PlaybackStateStore.shared.activeShuffledQueue.removeAll()
                PlaybackStateStore.shared.activeShuffledIndex = 0
                PlaybackStateStore.shared.activeShuffledPlaylistName = nil
            }
            if PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty {
                PlaybackStateStore.shared.nativeQueuedUpcomingCatalogIds.removeAll()
                let currentQueue = PlaybackStateStore.shared.activeCustomQueue
                let curIdx = PlaybackStateStore.shared.activeCustomQueueIndex
                let gen = PlaybackStateStore.shared.playbackGeneration
                if enabled {
                    if PlaybackStateStore.shared.originalCustomQueue.isEmpty {
                        PlaybackStateStore.shared.originalCustomQueue = currentQueue
                    }
                    if curIdx >= 0 && curIdx < currentQueue.count && currentQueue.count > 1 {
                        if curIdx + 1 < currentQueue.count {
                            let head = Array(currentQueue[0...curIdx])
                            var tail = Array(currentQueue[(curIdx + 1)...])
                            tail.shuffle()
                            var combined = head + tail
                            for i in 0..<combined.count { combined[i].index = i + 1 }
                            PlaybackStateStore.shared.activeCustomQueue = combined
                            PlaybackStateStore.shared.latestUpcomingTracks = Array(combined[(curIdx + 1)...])
                            prestageInfo = (nextIdx: curIdx + 1, gen: gen)
                        } else {
                            // At the last track: keep current track at index 0 and shuffle all previous tracks as upcoming
                            let curTrack = currentQueue[curIdx]
                            var others = Array(currentQueue[0..<curIdx])
                            others.shuffle()
                            var combined = [curTrack] + others
                            for i in 0..<combined.count { combined[i].index = i + 1 }
                            PlaybackStateStore.shared.activeCustomQueue = combined
                            PlaybackStateStore.shared.activeCustomQueueIndex = 0
                            PlaybackStateStore.shared.latestUpcomingTracks = Array(combined[1...])
                            PlaybackStateStore.shared.latestHistoryTracks = []
                            prestageInfo = (nextIdx: 1, gen: gen)
                        }
                    }
                } else if !PlaybackStateStore.shared.originalCustomQueue.isEmpty {
                    let orig = PlaybackStateStore.shared.originalCustomQueue
                    let curTrack = (curIdx >= 0 && curIdx < currentQueue.count) ? currentQueue[curIdx] : nil
                    var restoredIdx = 0
                    if let ct = curTrack {
                        if let matchIdx = orig.firstIndex(where: { $0.id == ct.id && !ct.id.isEmpty }) ??
                                          orig.firstIndex(where: { $0.name == ct.name && $0.artist == ct.artist }) {
                            restoredIdx = matchIdx
                        }
                    }
                    var restored = orig
                    for i in 0..<restored.count { restored[i].index = i + 1 }
                    PlaybackStateStore.shared.activeCustomQueue = restored
                    PlaybackStateStore.shared.activeCustomQueueIndex = restoredIdx
                    if restoredIdx + 1 < restored.count {
                        PlaybackStateStore.shared.latestUpcomingTracks = Array(restored[(restoredIdx + 1)...])
                        prestageInfo = (nextIdx: restoredIdx + 1, gen: gen)
                    } else {
                        PlaybackStateStore.shared.latestUpcomingTracks = []
                    }
                    if restoredIdx > 0 {
                        PlaybackStateStore.shared.latestHistoryTracks = Array(restored[0..<restoredIdx].reversed())
                    } else {
                        PlaybackStateStore.shared.latestHistoryTracks = []
                    }
                }
            }
        }
        if let info = prestageInfo {
            PlaybackRouter.shared.prestageUpcomingCloudTracks(
                fromIndex: info.nextIdx,
                count: 6,
                expectedGeneration: info.gen,
                immediate: true
            )
        }
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastShuffleSetTime = Date()
        }
        PlayerStatusEngine.shared.updateCachedShuffle(enabled)
        if PlaybackRouter.shared.isTestingEnvironment {
            return true
        }
        let isCustomQueue = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty
        }
        if !isCustomQueue {
            if let app = MusicAppProvider.shared.getMusicApp() {
                app.shuffleEnabled = enabled
            } else {
                let script = enabled ? "tell application \"Music\"\nset shuffle mode to songs\nset shuffle enabled to true\nend tell" : "tell application \"Music\" to set shuffle enabled to false"
                _ = AppleScriptExecutor.shared.execute(script)
            }
        }
        PlaybackStateStore.shared.invalidateQueueCache()
        PlayerStatusEngine.shared.updateCachedShuffle(enabled)
        WebSocketServer.shared.broadcastStatus(includeQueue: true)
        return true
    }

    public func setRepeat(mode: String) -> Bool {
        let cleanMode = mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isRadio = PlaybackStateStore.shared.withLock {
            let detected = PlaybackStateStore.shared.isRadioPlayback || (PlaybackStateStore.shared.lastPlayerStatusCache?.status.isRadio == true)
            if detected && !PlaybackStateStore.shared.isCustomQueuePlayback {
                PlaybackStateStore.shared.isRadioPlayback = true
            }
            return detected
        }
        let rejectedRadioAll = (isRadio && cleanMode == "all")
        let validMode: String
        if cleanMode == "one" || cleanMode == "track" || cleanMode == "1" {
            validMode = "one"
        } else if cleanMode == "all" && !isRadio {
            validMode = "all"
        } else {
            validMode = "off"
        }

        let (isCustomQueue, cachedTrack) = PlaybackStateStore.shared.withLock { () -> (Bool, TrackInfo?) in
            PlaybackStateStore.shared.repeatMode = validMode
            PlaybackStateStore.shared.lastRepeatSetTime = Date()
            if validMode != "one" {
                PlaybackStateStore.shared.repeatOnePinnedTrack = nil
            }
            let isCustom = PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty
            let curTrack = PlaybackStateStore.shared.lastPlayerStatusCache?.status.track
            return (isCustom, curTrack)
        }
        if validMode == "one" {
            BitPerfectLogMonitor.shared.clearPendingNextTrackFormat()
        }
        if validMode == "one" && !isCustomQueue {
            let candidate = cachedTrack ?? (PlaybackRouter.shared.isTestingEnvironment ? nil : PlayerStatusEngine.shared.getPlayerStatus().track)
            if let t = candidate {
                let cleanTitle = t.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let lowerTitle = cleanTitle.lowercased()
                let isPlaceholder = cleanTitle.isEmpty || ((lowerTitle.hasPrefix("станция:") || lowerTitle.hasPrefix("station:")) && t.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !isPlaceholder {
                    PlaybackStateStore.shared.withLock {
                        PlaybackStateStore.shared.repeatOnePinnedTrack = t
                    }
                    if isRadio && t.duration <= 0 && !PlaybackRouter.shared.isTestingEnvironment {
                        QueueManager.shared.resolveRadioPinnedTrackDurationIfNeeded(name: t.name, artist: t.artist)
                    }
                }
            }
            QueueManager.shared.startQueueMonitoring()
        }
        PlayerStatusEngine.shared.updateCachedRepeatMode(validMode)
        if PlaybackRouter.shared.isTestingEnvironment {
            return !rejectedRadioAll
        }

        // During radio playback, never mutate Music.app's native repeat mode to `one` (which is ignored or can halt station streaming);
        // Radio Repeat-One is handled cleanly by seeking the active radio track to `0:00` before track end.
        let musicAppMode = (isRadio || (isCustomQueue && validMode == "all")) ? "off" : validMode
        if !isRadio {
            _ = SystemMusicPlayerBridge.shared.setRepeatMode(musicAppMode)
        }
        var appliedViaSB = false
        if let app = MusicAppProvider.shared.getMusicApp() {
            var rMode: MusicERpt = .off
            if musicAppMode == "all" { rMode = .all }
            else if musicAppMode == "one" { rMode = .one }
            app.songRepeat = rMode
            appliedViaSB = (app.songRepeat == rMode)
        }
        if !appliedViaSB && MusicAppProvider.shared.isMusicAppRunning {
            _ = AppleScriptExecutor.shared.execute(
                "tell application \"Music\" to try\nset song repeat to \(musicAppMode)\nend try",
                maxWait: 1.5,
                reportTimeout: false
            )
        }
        NSLog("[PlaybackTransportController] 🔁 Repeat mode set to '%@' (Music.app='%@', sb=%d, customQueue=%d, radio=%d)",
              validMode, musicAppMode, appliedViaSB ? 1 : 0, isCustomQueue ? 1 : 0, isRadio ? 1 : 0)

        PlayerStatusEngine.shared.updateCachedRepeatMode(validMode)
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
        return !rejectedRadioAll
    }

    public func toggleFavorite() -> Bool {
        let state = PlayerStatusEngine.shared.currentFavoritedState()
        return setFavorite(!state.isFavorited)
    }

    public func setFavorite(_ fav: Bool) -> Bool {
        let state = PlayerStatusEngine.shared.currentFavoritedState()
        PlayerStatusEngine.shared.updateFavoritedState(fav, name: state.name, artist: state.artist)

        if let app = MusicAppProvider.shared.getMusicApp(), let track = app.currentTrack {
            let tName = track.sbName
            let tArtist = track.sbArtist
            if !tName.isEmpty {
                PlayerStatusEngine.shared.updateFavoritedState(fav, name: tName, artist: tArtist)
            }
            track.sbFavorited = fav
            if track.sbFavorited != fav {
                let escN = tName.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                let escA = tArtist.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                let script = """
                tell application "Music"
                  try
                    set favorited of current track to \(fav)
                  end try
                  try
                    set foundTracks to (every track of library playlist 1 whose name is "\(escN)" and artist is "\(escA)")
                    repeat with lt in foundTracks
                      set favorited of lt to \(fav)
                    end repeat
                  end try
                end tell
                """
                _ = AppleScriptExecutor.shared.execute(script)
            }
            return true
        } else {
            let (ok, _) = AppleScriptExecutor.shared.execute("tell application \"Music\"\ntry\nset favorited of current track to \(fav)\nend try\nend tell")
            return ok
        }
    }

    public func addCurrentTrackToLibrary() -> Bool {
        var (name, artist, activeDbId, activeCatId, activeUrl) = PlaybackStateStore.shared.withLock { () -> (String, String, Int, String?, String?) in
            if PlaybackStateStore.shared.isCustomQueuePlayback,
               PlaybackStateStore.shared.activeCustomQueueIndex >= 0,
               PlaybackStateStore.shared.activeCustomQueueIndex < PlaybackStateStore.shared.activeCustomQueue.count {
                let cur = PlaybackStateStore.shared.activeCustomQueue[PlaybackStateStore.shared.activeCustomQueueIndex]
                if !cur.name.isEmpty && !cur.artist.isEmpty {
                    return (cur.name, cur.artist, cur.numericId ?? 0, cur.catalogId ?? cur.id, cur.url)
                }
            }
            if let cached = PlaybackStateStore.shared.lastPlayerStatusCache?.status.track,
               !cached.name.isEmpty && !cached.artist.isEmpty {
                return (cached.name, cached.artist, cached.numericId ?? 0, cached.catalogId ?? cached.id, cached.url)
            }
            return ("", "", 0, nil, nil)
        }
        if (name.isEmpty || artist.isEmpty), let cur = MusicAppProvider.shared.getMusicApp()?.currentTrack {
            name = cur.sbName
            artist = cur.sbArtist
        }
        if LibraryService.shared.addToLibrary(id: activeCatId, trackId: activeDbId > 0 ? activeDbId : nil, name: name, artist: artist, url: activeUrl) {
            return true
        }

        if !name.isEmpty && !artist.isEmpty {
            let escN = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let escA = artist.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
            tell application "Music"
              try
                set foundTracks to (every track of library playlist 1 whose name is "\(escN)" and artist is "\(escA)")
                if (count of foundTracks) > 0 then
                  return "ok"
                end if
              end try
              try
                duplicate (first track whose name is "\(escN)" and artist is "\(escA)") to library playlist 1
                return "ok"
              on error
                try
                  set libPl to first library playlist
                  duplicate (first track whose name is "\(escN)" and artist is "\(escA)") to libPl
                  return "ok"
                end try
              end try
            end tell
            """
            let (ok, res) = AppleScriptExecutor.shared.execute(script)
            if ok, res == "ok" { return true }
        }

        let currentTrackScript = """
        tell application "Music"
          try
            duplicate current track to first source
            return "ok"
          on error
            try
              duplicate current track to library playlist 1
              return "ok"
            on error
              try
                set libPl to first library playlist
                duplicate current track to libPl
                return "ok"
              on error
                return "error"
              end try
            end try
          end try
        end tell
        """
        let (ok, res) = AppleScriptExecutor.shared.execute(currentTrackScript)
        return ok && res == "ok"
    }
}
