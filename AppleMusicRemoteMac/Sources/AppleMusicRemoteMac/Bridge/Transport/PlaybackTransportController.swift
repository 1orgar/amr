//
//  PlaybackTransportController.swift
//  AppleMusicRemoteMac
//
//  Transport control operations: play, pause, playPause, stop, next, previous,
//  seek, volume, shuffle, repeat, favorite, and library track addition.
//

import Foundation
import ScriptingBridge

public final class PlaybackTransportController: @unchecked Sendable {
    public static let shared = PlaybackTransportController()

    private init() {}

    // MARK: - Core Playback Controls

    public func play() -> Bool {
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isUserPaused = false
            let knownPos = max(0.0, PlaybackStateStore.shared.lastKnownPosition)
            PlaybackStateStore.shared.lastCloudPlayTime = Date().addingTimeInterval(-knownPos)
        }
        PlaybackStateStore.shared.invalidateStatusCache(optimisticState: "playing")
        if PlaybackRouter.shared.isTestingEnvironment {
            return true
        }
        MusicAppProvider.shared.ensureMusicAppRunning()
        if let app = MusicAppProvider.shared.getMusicApp() {
            let state = app.playerState
            if state == .paused {
                app.playpause()
            } else if state == .stopped {
                let curTrackName = (app.currentTrack?.value(forKey: "name") as? String) ?? ""
                if curTrackName.isEmpty {
                    let (isCustom, hasQueue, activeIdx) = PlaybackStateStore.shared.withLock {
                        (
                            PlaybackStateStore.shared.isCustomQueuePlayback,
                            !PlaybackStateStore.shared.activeCustomQueue.isEmpty,
                            PlaybackStateStore.shared.activeCustomQueueIndex
                        )
                    }
                    if isCustom && hasQueue {
                        return QueueManager.shared.playQueueIndexUnlocked(activeIdx)
                    }
                }
                app.playOnce(false)
            } else {
                app.playOnce(false)
            }
            return true
        }
        _ = AppleScriptExecutor.shared.run("tell application \"Music\" to play")
        return true
    }

    public func pause() -> Bool {
        PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isUserPaused = true }
        PlaybackStateStore.shared.invalidateStatusCache(optimisticState: "paused")
        if PlaybackRouter.shared.isTestingEnvironment {
            return true
        }
        if let app = MusicAppProvider.shared.getMusicApp() {
            app.pause()
            return true
        }
        _ = AppleScriptExecutor.shared.run("tell application \"Music\" to pause")
        return true
    }

    public func stop() -> Bool {
        PlaybackStateStore.shared.clearSeekTarget()
        PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isUserPaused = true }
        PlaybackStateStore.shared.invalidateStatusCache(optimisticState: "stopped")
        if PlaybackRouter.shared.isTestingEnvironment {
            return true
        }
        if let app = MusicAppProvider.shared.getMusicApp() {
            if let stopFn = app.stop {
                stopFn()
            } else {
                app.pause()
                app.playerPosition = 0
            }
            return true
        }
        let (ok, _) = AppleScriptExecutor.shared.run("tell application \"Music\" to stop")
        return ok
    }

    public func playPause() -> Bool {
        let cachedPlaying: Bool? = PlaybackStateStore.shared.withLock {
            if let cache = PlaybackStateStore.shared.lastPlayerStatusCache,
               Date().timeIntervalSince(cache.timestamp) < 1.5 {
                return cache.status.playerState == "playing"
            }
            return nil
        }
        let isPlaying: Bool
        if let cachedPlaying {
            isPlaying = cachedPlaying
        } else if let app = MusicAppProvider.shared.getMusicApp() {
            isPlaying = app.playerState == .playing
        } else {
            isPlaying = PlaybackStateStore.shared.withLock { !PlaybackStateStore.shared.isUserPaused }
        }
        if isPlaying {
            return pause()
        } else {
            return play()
        }
    }

    private let transportLock = NSLock()
    private var lastNextTrackTime: Date = Date.distantPast
    private var lastPrevTrackTime: Date = Date.distantPast

    public func nextTrack() -> Bool {
        transportLock.lock()
        let now = Date()
        if now.timeIntervalSince(lastNextTrackTime) < 0.25 {
            transportLock.unlock()
            return true
        }
        lastNextTrackTime = now
        transportLock.unlock()

        BitPerfectLogMonitor.shared.resetTrackState()
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isUserPaused = false
            PlaybackStateStore.shared.lastSkipTime = now
            PlaybackStateStore.shared.clearSeekTarget()
            PlaybackStateStore.shared.invalidateStatusCache()
            PlaybackStateStore.shared.invalidateQueueCache()
        }

        let (isCustom, count, curIdx, repMode) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty,
                PlaybackStateStore.shared.activeCustomQueue.count,
                PlaybackStateStore.shared.activeCustomQueueIndex,
                PlaybackStateStore.shared.repeatMode
            )
        }

        if isCustom {
            let nextIdx = curIdx + 1
            if nextIdx < count {
                _ = QueueManager.shared.playQueueIndexUnlocked(nextIdx)
            } else if repMode == "all" && count > 0 {
                QueueManager.shared.advanceOrEndCustomQueueUnlocked(reason: "manual-next")
            }
            return true
        }

        if PlaybackRouter.shared.isTestingEnvironment {
            return true
        }

        if let app = MusicAppProvider.shared.getMusicApp() {
            app.nextTrack()
            return true
        }
        let (ok, _) = AppleScriptExecutor.shared.run("tell application \"Music\" to next track")
        return ok
    }

    public func previousTrack(forceTrackChange: Bool = false) -> Bool {
        transportLock.lock()
        let now = Date()
        let timeSinceLastClick = now.timeIntervalSince(lastPrevTrackTime)
        if timeSinceLastClick < 0.15 {
            transportLock.unlock()
            return true
        }
        let isRapidRepeat = timeSinceLastClick < 3.0
        lastPrevTrackTime = now
        transportLock.unlock()

        BitPerfectLogMonitor.shared.resetTrackState()
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isUserPaused = false
            PlaybackStateStore.shared.lastSkipTime = now
            PlaybackStateStore.shared.clearSeekTarget()
            PlaybackStateStore.shared.invalidateStatusCache()
            PlaybackStateStore.shared.invalidateQueueCache()
        }

        let (isCustom, activeIdx) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty,
                PlaybackStateStore.shared.activeCustomQueueIndex
            )
        }

        if isCustom {
            let rawPos = MusicAppProvider.shared.getMusicApp()?.playerPosition ?? 0.0
            let appPos = PlayerStatusEngine.shared.computeOptimisticPosition(rawPosition: rawPos, isPlaying: true, duration: 0)
            // Standard media player behavior: if track played > 3.0 seconds AND this is not a rapid double click (or explicit DMR track change), restart to 0:00
            if !forceTrackChange && appPos > 3.0 && !isRapidRepeat {
                return seek(to: 0.0)
            }
            if activeIdx > 0 {
                return QueueManager.shared.playQueueIndexUnlocked(activeIdx - 1)
            } else {
                let (repMode, count) = PlaybackStateStore.shared.withLock {
                    (PlaybackStateStore.shared.repeatMode, PlaybackStateStore.shared.activeCustomQueue.count)
                }
                if repMode == "all" && count > 1 {
                    return QueueManager.shared.playQueueIndexUnlocked(count - 1)
                }
                // At the start of custom queue: rewind to 0:00 of track 0, NEVER fall through to app.previousTrack()!
                return seek(to: 0.0)
            }
        }

        // Radio Playback: Apple Music Radio cannot go back to past songs. Rewind to 0:00 without exiting radio!
        let isRadio = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isRadioPlayback }
        if isRadio {
            return seek(to: 0.0)
        }

        // Standard Library Playlists
        if PlaybackRouter.shared.isTestingEnvironment {
            return true
        }
        guard let app = MusicAppProvider.shared.getMusicApp() else { return false }
        let rawPos = app.playerPosition
        let effectivePos = PlayerStatusEngine.shared.computeOptimisticPosition(rawPosition: rawPos, isPlaying: true, duration: 0)
        if !forceTrackChange && effectivePos > 3.0 && !isRapidRepeat {
            return seek(to: 0.0)
        }
        app.playerPosition = 0.0
        app.previousTrack()
        return true
    }

    public func seek(to position: Double) -> Bool {
        PlaybackStateStore.shared.setSeekTarget(position: position)
        PlaybackStateStore.shared.invalidateStatusCache()
        if PlaybackRouter.shared.isTestingEnvironment {
            return true
        }
        guard let app = MusicAppProvider.shared.getMusicApp() else { return false }
        app.playerPosition = position
        return true
    }

    public func setVolume(_ volume: Int, isFromDuckingController: Bool = false) -> Bool {
        if PlaybackStateStore.shared.isVolumeLockedTo100 {
            if ExternalAmpTCPController.shared.isActive {
                if !isFromDuckingController {
                    AudioDuckingController.shared.notifyManualVolumeChange(max(0, min(100, volume)))
                }
                ExternalAmpTCPController.shared.setVolume(volume, preserveBaseVolume: isFromDuckingController)
                return true
            }
            if !isFromDuckingController && volume != 100 {
                NSLog("[PlaybackTransportController] 🔒 Volume is locked to 100%% (Bit-Perfect). Rejecting volume change to %d%%", volume)
                return false
            }
        }
        let clamped = max(0, min(100, volume))
        if !isFromDuckingController {
            AudioDuckingController.shared.notifyManualVolumeChange(clamped)
        }
        let isDLNAMuted = PlaybackStateStore.shared.withLock { () -> Bool in
            PlaybackStateStore.shared.simulatedVolume = clamped
            if PlaybackStateStore.shared.isDLNAMuted && !isFromDuckingController && clamped > 0 {
                PlaybackStateStore.shared.preDLNAVolume = clamped
            }
            return PlaybackStateStore.shared.isDLNAMuted
        }
        CoreAudioDeviceManager.shared.updateSavedGuardVolumeIfNeeded(clamped, isDucked: AudioDuckingController.shared.isDucked)
        PlaybackStateStore.shared.invalidateStatusCache()
        if !CoreAudioDeviceManager.shared.isMutingGuardActive && !isDLNAMuted {
            if let app = MusicAppProvider.shared.getMusicApp() {
                app.soundVolume = clamped
            } else if MusicAppProvider.shared.isMusicAppRunning {
                let script = "tell application \"Music\" to set sound volume to \(clamped)"
                _ = AppleScriptExecutor.shared.execute(script)
            }
        }
        PlaybackStateStore.shared.invalidateStatusCache()
        return true
    }

    @discardableResult
    public func checkAndEnforceVolumeLock() -> Bool {
        let isDLNAMuted = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isDLNAMuted }
        guard PlaybackStateStore.shared.isVolumeLockedTo100
              && !isDLNAMuted
              && !AudioDuckingController.shared.isDucked
              && !CoreAudioDeviceManager.shared.isMutingGuardActive else { return false }
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.simulatedVolume = 100
        }
        if PlaybackRouter.shared.isTestingEnvironment {
            return true
        }
        guard MusicAppProvider.shared.isMusicAppRunning else {
            return true
        }
        if let app = MusicAppProvider.shared.getMusicApp() {
            if app.soundVolume != 100 {
                NSLog("[PlaybackTransportController] 🔊 Enforcing 100%% volume lock in Music.app (was %d%%)", app.soundVolume)
                app.soundVolume = 100
            }
        } else {
            let script = """
            tell application "Music"
                try
                    if sound volume is not 100 then
                        set sound volume to 100
                    end if
                    return "ok"
                on error
                    return "error"
                end try
            end tell
            """
            _ = AppleScriptExecutor.shared.execute(script)
        }
        PlaybackStateStore.shared.invalidateStatusCache()
        return true
    }

    public func setShuffle(_ enabled: Bool) -> Bool {
        PlaybackStateStore.shared.invalidateQueueCache()
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isShuffleQueueActive = enabled
            if PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty {
                let currentQueue = PlaybackStateStore.shared.activeCustomQueue
                let curIdx = PlaybackStateStore.shared.activeCustomQueueIndex
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
        PlaybackStateStore.shared.invalidateStatusCache()
        WebSocketServer.shared.broadcastStatus(includeQueue: true)
        return true
    }

    public func setRepeat(mode: String) -> Bool {
        let cleanMode = mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let validMode = ["off", "one", "all"].contains(cleanMode) ? cleanMode : "off"
        let isCustomQueue = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.repeatMode = validMode
            return PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty
        }
        PlaybackStateStore.shared.invalidateStatusCache()
        if PlaybackRouter.shared.isTestingEnvironment {
            return true
        }
        let musicAppMode = (isCustomQueue && validMode == "all") ? "off" : validMode
        if let app = MusicAppProvider.shared.getMusicApp() {
            var rMode: MusicERpt = .off
            if musicAppMode == "all" { rMode = .all }
            else if musicAppMode == "one" { rMode = .one }
            app.songRepeat = rMode
        } else {
            let script = "tell application \"Music\" to set song repeat to \(musicAppMode)"
            _ = AppleScriptExecutor.shared.execute(script)
        }
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
        return true
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
        var (name, artist, _) = PlaybackStateStore.shared.withLock { () -> (String, String, Int) in
            if PlaybackStateStore.shared.isCustomQueuePlayback,
               PlaybackStateStore.shared.activeCustomQueueIndex >= 0,
               PlaybackStateStore.shared.activeCustomQueueIndex < PlaybackStateStore.shared.activeCustomQueue.count {
                let cur = PlaybackStateStore.shared.activeCustomQueue[PlaybackStateStore.shared.activeCustomQueueIndex]
                if !cur.name.isEmpty && !cur.artist.isEmpty {
                    return (cur.name, cur.artist, cur.numericId ?? 0)
                }
            }
            if let cached = PlaybackStateStore.shared.lastPlayerStatusCache?.status.track,
               !cached.name.isEmpty && !cached.artist.isEmpty {
                return (cached.name, cached.artist, cached.numericId ?? 0)
            }
            return ("", "", 0)
        }
        if (name.isEmpty || artist.isEmpty), let cur = MusicAppProvider.shared.getMusicApp()?.currentTrack {
            name = cur.sbName
            artist = cur.sbArtist
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
