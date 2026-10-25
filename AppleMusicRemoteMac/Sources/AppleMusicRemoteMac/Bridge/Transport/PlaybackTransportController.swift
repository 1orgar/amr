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
        PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isUserPaused = false }
        PlaybackStateStore.shared.invalidateStatusCache(optimisticState: "playing")
        MusicAppProvider.shared.ensureMusicAppRunning()
        if let app = MusicAppProvider.shared.getMusicApp() {
            if app.playerState == .stopped {
                app.playOnce(false)
            } else {
                app.playpause()
            }
            return true
        }
        if PlaybackRouter.shared.isTestingEnvironment {
            return true
        }
        let (ok, _) = AppleScriptExecutor.shared.run("tell application \"Music\" to play")
        return ok
    }

    public func pause() -> Bool {
        PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isUserPaused = true }
        PlaybackStateStore.shared.invalidateStatusCache(optimisticState: "paused")
        if let app = MusicAppProvider.shared.getMusicApp() {
            app.pause()
        }
        if PlaybackRouter.shared.isTestingEnvironment {
            return true
        }
        _ = AppleScriptExecutor.shared.run("tell application \"Music\" to pause")
        return true
    }

    public func stop() -> Bool {
        PlaybackStateStore.shared.clearSeekTarget()
        PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isUserPaused = true }
        PlaybackStateStore.shared.invalidateStatusCache(optimisticState: "stopped")
        if let app = MusicAppProvider.shared.getMusicApp() {
            app.pause()
            app.playerPosition = 0
            return true
        }
        if PlaybackRouter.shared.isTestingEnvironment {
            return true
        }
        let (ok, _) = AppleScriptExecutor.shared.run("""
        tell application "Music" to pause
        tell application "Music" to set player position to 0
        """)
        return ok
    }

    public func playPause() -> Bool {
        let isPlaying = PlaybackStateStore.shared.withLock {
            if let cache = PlaybackStateStore.shared.lastPlayerStatusCache,
               Date().timeIntervalSince(cache.timestamp) < 1.5 {
                return cache.status.playerState == "playing"
            }
            if let app = MusicAppProvider.shared.getMusicApp() {
                return app.playerState == .playing
            }
            return !PlaybackStateStore.shared.isUserPaused
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
        if now.timeIntervalSince(lastNextTrackTime) < 0.8 {
            transportLock.unlock()
            return true
        }
        lastNextTrackTime = now
        transportLock.unlock()

        BitPerfectLogMonitor.shared.resetTrackState()
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastSkipTime = now
            PlaybackStateStore.shared.clearSeekTarget()
            PlaybackStateStore.shared.invalidateStatusCache()
            PlaybackStateStore.shared.invalidateQueueCache()
        }

        let isCustom = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty
        }

        if isCustom {
            PlaybackStateStore.shared.withLock {
                let nextIdx = PlaybackStateStore.shared.activeCustomQueueIndex + 1
                if nextIdx < PlaybackStateStore.shared.activeCustomQueue.count {
                    _ = QueueManager.shared.playQueueIndexUnlocked(nextIdx)
                }
            }
            return true
        }

        if let app = MusicAppProvider.shared.getMusicApp() {
            // Auto-detect radio stream
            if (app.currentPlaylist?.value(forKey: "name") as? String) == nil && (app.currentTrack?.value(forKey: "location") == nil) {
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.isRadioPlayback = true
                }
            }
            app.nextTrack()
            return true
        }
        let (ok, _) = AppleScriptExecutor.shared.run("tell application \"Music\" to next track")
        return ok
    }

    public func previousTrack() -> Bool {
        transportLock.lock()
        let now = Date()
        let timeSinceLastClick = now.timeIntervalSince(lastPrevTrackTime)
        if timeSinceLastClick < 0.15 {
            transportLock.unlock()
            return true
        }
        let isRapidRepeat = timeSinceLastClick < 1.5
        lastPrevTrackTime = now
        transportLock.unlock()

        BitPerfectLogMonitor.shared.resetTrackState()
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastSkipTime = now
            PlaybackStateStore.shared.clearSeekTarget()
            PlaybackStateStore.shared.invalidateStatusCache()
            PlaybackStateStore.shared.invalidateQueueCache()
        }

        // Radio Playback: Apple Music Radio cannot go back to past songs. Rewind to 0:00 without exiting radio!
        let isRadio = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isRadioPlayback }
        if isRadio {
            return seek(to: 0.0)
        }

        let (isCustom, activeIdx) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty,
                PlaybackStateStore.shared.activeCustomQueueIndex
            )
        }

        if isCustom {
            let appPos = MusicAppProvider.shared.getMusicApp()?.playerPosition ?? 0.0
            // Standard media player behavior: if track played > 3.0 seconds AND this is not a rapid double click, restart to 0:00
            if appPos > 3.0 && !isRapidRepeat {
                return seek(to: 0.0)
            }
            if activeIdx > 0 {
                return PlaybackStateStore.shared.withLock {
                    QueueManager.shared.playQueueIndexUnlocked(activeIdx - 1)
                }
            } else {
                // At the start of custom queue: rewind to 0:00 of track 0, NEVER fall through to app.previousTrack()!
                return seek(to: 0.0)
            }
        }

        // Standard Library Playlists
        guard let app = MusicAppProvider.shared.getMusicApp() else { return false }
        if app.playerPosition > 3.0 && !isRapidRepeat {
            app.playerPosition = 0.0
            return true
        }
        if (app.currentPlaylist?.value(forKey: "name") as? String) == nil && (app.currentTrack?.value(forKey: "location") == nil) {
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.isRadioPlayback = true
            }
            return seek(to: 0.0)
        }
        app.previousTrack()
        return true
    }

    public func seek(to position: Double) -> Bool {
        PlaybackStateStore.shared.setSeekTarget(position: position)
        PlaybackStateStore.shared.invalidateStatusCache()
        guard let app = MusicAppProvider.shared.getMusicApp() else { return false }
        app.playerPosition = position
        return true
    }

    public func setVolume(_ volume: Int) -> Bool {
        if PlaybackStateStore.shared.isVolumeLockedTo100 && volume != 100 && !AudioDuckingController.shared.isDucked {
            NSLog("[PlaybackTransportController] 🔒 Volume is locked to 100%% (Bit-Perfect). Rejecting volume change to %d%%", volume)
            return false
        }
        let clamped = max(0, min(100, volume))
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.simulatedVolume = clamped
        }
        PlaybackStateStore.shared.invalidateStatusCache()
        if let app = MusicAppProvider.shared.getMusicApp() {
            app.soundVolume = clamped
        }
        if MusicAppProvider.shared.isMusicAppRunning {
            let script = "tell application \"Music\" to set sound volume to \(clamped)"
            _ = AppleScriptExecutor.shared.execute(script)
        }
        PlaybackStateStore.shared.invalidateStatusCache()
        return true
    }

    @discardableResult
    public func checkAndEnforceVolumeLock() -> Bool {
        guard PlaybackStateStore.shared.isVolumeLockedTo100 else { return false }
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.simulatedVolume = 100
        }
        guard MusicAppProvider.shared.isMusicAppRunning else {
            return true
        }
        if let app = MusicAppProvider.shared.getMusicApp(), app.soundVolume != 100 {
            NSLog("[PlaybackTransportController] 🔊 Enforcing 100%% volume lock in Music.app (was %d%%)", app.soundVolume)
            app.soundVolume = 100
        }
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
        PlaybackStateStore.shared.invalidateStatusCache()
        return true
    }

    public func setShuffle(_ enabled: Bool) -> Bool {
        PlaybackStateStore.shared.invalidateQueueCache()
        guard let app = MusicAppProvider.shared.getMusicApp() else { return false }

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isShuffleQueueActive = enabled
        }

        app.shuffleEnabled = enabled
        let script = "tell application \"Music\" to set shuffle enabled to \(enabled ? "true" : "false")"
        _ = AppleScriptExecutor.shared.execute(script)
        PlaybackStateStore.shared.invalidateStatusCache()
        WebSocketServer.shared.broadcastStatus(includeQueue: true)
        return true
    }

    public func setRepeat(mode: String) -> Bool {
        PlaybackStateStore.shared.invalidateStatusCache()
        guard let app = MusicAppProvider.shared.getMusicApp() else { return false }
        var rMode: MusicERpt = .off
        if mode == "all" { rMode = .all }
        else if mode == "one" { rMode = .one }
        app.songRepeat = rMode
        return true
    }

    public func toggleFavorite() -> Bool {
        guard let app = MusicAppProvider.shared.getMusicApp(), let track = app.currentTrack else {
            let (ok, _) = AppleScriptExecutor.shared.execute("tell application \"Music\" to set favorited of current track to not (favorited of current track)")
            return ok
        }
        let currentFav = track.sbFavorited
        track.sbFavorited = !currentFav
        if track.sbFavorited == currentFav {
            _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to set favorited of current track to \(!currentFav)")
        }
        return true
    }

    public func setFavorite(_ fav: Bool) -> Bool {
        guard let app = MusicAppProvider.shared.getMusicApp(), let track = app.currentTrack else {
            let (ok, _) = AppleScriptExecutor.shared.execute("tell application \"Music\" to set favorited of current track to \(fav)")
            return ok
        }
        track.sbFavorited = fav
        if track.sbFavorited != fav {
            _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to set favorited of current track to \(fav)")
        }
        return true
    }

    public func addCurrentTrackToLibrary() -> Bool {
        let (name, artist, _) = PlaybackStateStore.shared.withLock { () -> (String, String, Int) in
            guard let cur = MusicAppProvider.shared.getMusicApp()?.currentTrack else { return ("", "", 0) }
            return (cur.sbName, cur.sbArtist, cur.sbDatabaseID)
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
