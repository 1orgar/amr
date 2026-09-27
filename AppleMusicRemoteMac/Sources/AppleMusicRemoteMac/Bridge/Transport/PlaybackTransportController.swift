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
        PlaybackStateStore.shared.invalidateStatusCache()
        if let app = MusicAppProvider.shared.getMusicApp() {
            if app.playerState == .stopped {
                app.playOnce(false)
            } else {
                app.playpause()
            }
            return true
        }
        let (ok, _) = AppleScriptExecutor.shared.run("tell application \"Music\" to play")
        return ok
    }

    public func pause() -> Bool {
        PlaybackStateStore.shared.invalidateStatusCache()
        if let app = MusicAppProvider.shared.getMusicApp() {
            app.pause()
            return true
        }
        let (ok, _) = AppleScriptExecutor.shared.run("tell application \"Music\" to pause")
        return ok
    }

    public func stop() -> Bool {
        PlaybackStateStore.shared.clearSeekTarget()
        PlaybackStateStore.shared.invalidateStatusCache()
        if let app = MusicAppProvider.shared.getMusicApp() {
            app.pause()
            app.playerPosition = 0
            return true
        }
        let (ok, _) = AppleScriptExecutor.shared.run("""
        tell application "Music" to pause
        tell application "Music" to set player position to 0
        """)
        return ok
    }

    public func playPause() -> Bool {
        PlaybackStateStore.shared.invalidateStatusCache()
        if let app = MusicAppProvider.shared.getMusicApp() {
            app.playpause()
            return true
        }
        let (ok, _) = AppleScriptExecutor.shared.run("tell application \"Music\" to playpause")
        return ok
    }

    public func nextTrack() -> Bool {
        BitPerfectLogMonitor.shared.resetTrackState()
        PlaybackStateStore.shared.clearSeekTarget()
        PlaybackStateStore.shared.invalidateQueueCache()

        let isCustom = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty
        }

        if isCustom {
            let handled = PlaybackStateStore.shared.withLock { () -> Bool in
                let nextIdx = PlaybackStateStore.shared.activeCustomQueueIndex + 1
                if nextIdx < PlaybackStateStore.shared.activeCustomQueue.count {
                    return QueueManager.shared.playQueueIndexUnlocked(nextIdx)
                }
                return false
            }
            if handled { return true }
        }

        guard let app = MusicAppProvider.shared.getMusicApp() else { return false }
        app.nextTrack()
        return true
    }

    public func previousTrack() -> Bool {
        BitPerfectLogMonitor.shared.resetTrackState()
        PlaybackStateStore.shared.clearSeekTarget()
        PlaybackStateStore.shared.invalidateQueueCache()

        let isCustom = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty
        }

        if isCustom {
            let handled = PlaybackStateStore.shared.withLock { () -> Bool in
                let prevIdx = PlaybackStateStore.shared.activeCustomQueueIndex - 1
                if prevIdx >= 0 {
                    return QueueManager.shared.playQueueIndexUnlocked(prevIdx)
                }
                return false
            }
            if handled { return true }
        }

        guard let app = MusicAppProvider.shared.getMusicApp() else { return false }
        if app.playerPosition > 3.0 {
            app.playerPosition = 0
            return true
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
        PlaybackStateStore.shared.invalidateStatusCache()
        guard let app = MusicAppProvider.shared.getMusicApp() else { return false }
        let clamped = max(0, min(100, volume))
        app.soundVolume = clamped
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
        guard let app = MusicAppProvider.shared.getMusicApp(), let track = app.currentTrack else { return false }
        let currentFav = track.sbFavorited
        track.sbFavorited = !currentFav
        return true
    }

    public func setFavorite(_ fav: Bool) -> Bool {
        guard let app = MusicAppProvider.shared.getMusicApp(), let track = app.currentTrack else { return false }
        track.sbFavorited = fav
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
        end tell
        """
        let (ok, res) = AppleScriptExecutor.shared.execute(currentTrackScript)
        return ok && res == "ok"
    }
}
