//
//  PlaybackRouter.swift
//  AppleMusicRemoteMac
//
//  High-level playback orchestration: playlists, stations, albums,
//  cloud songs, hero cards, search results, and custom queue playback.
//

import AppKit
import Foundation
import ScriptingBridge

public final class PlaybackRouter: @unchecked Sendable {
    public static let shared = PlaybackRouter()

    private init() {}

    public var urlOpener: ((URL) -> Bool)? = nil

    public var isTestingEnvironment: Bool {
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
               ProcessInfo.processInfo.environment["XCInjectBundleInto"] != nil ||
               NSClassFromString("XCTestCase") != nil
    }

    @discardableResult
    public func openMusicUrl(_ urlString: String) -> Bool {
        var target = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return false }

        if target.hasPrefix("https://music.apple.com") {
            target = "music://" + target.dropFirst("https://".count)
        } else if !target.hasPrefix("music://") && (target.contains("ra.") || target.contains("/station/") || target.contains("/album/") || target.contains("/playlist/")) {
            target = "music://" + target
        }

        if let opener = urlOpener {
            if let url = URL(string: target) {
                return opener(url)
            }
            if let encoded = target.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: encoded) {
                return opener(url)
            }
            return false
        }

        if isTestingEnvironment {
            return true
        }

        let parsedUrl = URL(string: target) ?? target.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap { URL(string: $0) }
        guard let url = parsedUrl else { return false }

        let conf = NSWorkspace.OpenConfiguration()
        conf.activates = false
        conf.addsToRecentItems = false
        let sema = DispatchSemaphore(value: 0)
        var success = false
        NSWorkspace.shared.open(url, configuration: conf) { _, error in
            success = (error == nil)
            sema.signal()
        }
        _ = sema.wait(timeout: .now() + 1.5)
        return success
    }

    // MARK: - Playlist Playback

    public func playPlaylist(name: String, trackId: Int?, trackIndex: Int?, shuffle: Bool) -> Bool {
        BitPerfectLogMonitor.shared.resetTrackState()
        let pl = name.isEmpty ? "Музыка" : name

        // SPECIAL CASE: "Сейчас на повторе" (Heavy Rotation) is a dynamic mix from recent history / library.
        if pl == "Сейчас на повторе" || pl.lowercased().contains("повторе") || pl.lowercased().contains("heavy rotation") {
            var hrTracks = MusicBridge.shared.getRecentlyPlayed(limit: 50)
            if hrTracks.isEmpty {
                hrTracks = Array(LibraryService.shared.getLibrarySongs().prefix(50))
            }
            var startIdx = 0
            if let targetIdx = trackIndex, targetIdx > 0 {
                startIdx = targetIdx - 1
            } else if let targetId = trackId, targetId > 0 {
                if let found = hrTracks.firstIndex(where: { $0.numericId == targetId }) {
                    startIdx = found
                }
            }
            PlaybackStateStore.shared.activeStationName = "Сейчас на повторе"
            return playCustomTracks(hrTracks, startIndex: startIdx, shuffle: shuffle, queueName: "Сейчас на повторе")
        }

        PlaybackStateStore.shared.resetPlaybackState(originalPlaylist: pl)
        let escapedPl = pl.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")

        var startIdx = 0
        var hasSpecificTrack = false
        if let targetIdx = trackIndex, targetIdx > 0 {
            startIdx = targetIdx - 1
            hasSpecificTrack = true
        } else if let targetId = trackId, targetId > 0 {
            let plTracks = LibraryService.shared.getPlaylistTracks(name: pl)
            if let found = plTracks.firstIndex(where: { $0.numericId == targetId }) {
                startIdx = found
                hasSpecificTrack = true
            }
        }

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = false
            PlaybackStateStore.shared.activeCustomQueue.removeAll()
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.activeCustomQueueName = nil
            PlaybackStateStore.shared.currentOriginalPlaylistName = pl
            PlaybackStateStore.shared.isShuffleQueueActive = shuffle
            PlaybackStateStore.shared.activeShuffledPlaylistName = nil
            PlaybackStateStore.shared.activeShuffledQueue.removeAll()
        }
        QueueManager.shared.stopQueueMonitoring()

        let playCmd: String
        if hasSpecificTrack && !shuffle {
            playCmd = "play track \(startIdx + 1) of plTarget"
        } else {
            playCmd = "play plTarget"
        }

        let script = """
        tell application "Music"
            try
                stop
            end try
            set plTarget to missing value
            try
                set plTarget to playlist "\(escapedPl)"
            end try
            if plTarget is missing value then
                try
                    set plTarget to (first user playlist whose name is "\(escapedPl)")
                end try
            end if
            if plTarget is missing value then
                try
                    set plTarget to (first subscription playlist whose name is "\(escapedPl)")
                end try
            end if
            if plTarget is missing value then
                try
                    set plTarget to (first playlist whose name is "\(escapedPl)")
                end try
            end if
            if plTarget is missing value then
                try
                    set plTarget to (first playlist whose name contains "\(escapedPl)")
                end try
            end if
            if plTarget is missing value and ("\(escapedPl)" contains "Любим" or "\(escapedPl)" contains "Favorit" or "\(escapedPl)" contains "Essentials" or "\(escapedPl)" contains "essentials") then
                try
                    set plTarget to (first playlist whose name contains "Любим" or name contains "Favorit" or name contains "Essentials")
                end try
            end if
            if plTarget is not missing value then
                \(shuffle ? "set shuffle mode to songs\n                set shuffle enabled to true" : "set shuffle enabled to false")
                try
                    \(playCmd)
                    \(shuffle ? "set shuffle mode to songs\n                    set shuffle enabled to true" : "set shuffle enabled to false")
                    return "ok"
                on error err
                    try
                        play plTarget
                        \(shuffle ? "set shuffle mode to songs\n                        set shuffle enabled to true" : "set shuffle enabled to false")
                        return "ok"
                    on error err2
                        return "err: " & err & " / " & err2
                    end try
                end try
            end if
            return "error: plTarget missing"
        end tell
        """

        let (ok, res) = AppleScriptExecutor.shared.execute(script)
        NSLog("[PlaybackRouter] 🎵 playPlaylist pl='%@' ok=%d res='%@'", pl, ok ? 1 : 0, res ?? "nil")
        if ok, res?.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" {
            if let app = MusicAppProvider.shared.getMusicApp() {
                app.shuffleEnabled = shuffle
            }
            PlaybackStateStore.shared.invalidateQueueCache()
            PlaybackStateStore.shared.invalidateStatusCache()
            WebSocketServer.shared.broadcastStatus(includeQueue: true)

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.15) {
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
            }
            return true
        }
        return false
    }

    public func stopAndClearAMRQueue() {
        _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop")
    }

    public func playTrackByDatabaseIdViaAMRQueue(_ dbId: Int, generation: UInt64? = nil) -> Bool {
        guard dbId > 0 else { return false }
        if isTestingEnvironment {
            return true
        }
        if let expGen = generation {
            let curGen = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.playbackGeneration }
            if curGen != expGen {
                return false
            }
        }
        let script = """
        tell application "Music"
            try
                stop
            end try
            set foundTrack to missing value
            try
                set foundTrack to (first track of library playlist 1 whose database ID is \(dbId))
            end try
            if foundTrack is missing value then
                try
                    set foundTrack to (first track whose database ID is \(dbId))
                end try
            end if
            if foundTrack is not missing value then
                set shuffle enabled to false
                set song repeat to off
                try
                    play foundTrack once true
                on error
                    play foundTrack
                end try
                return "ok"
            end if
            return "error"
        end tell
        """
        let (ok, out) = AppleScriptExecutor.shared.execute(script)
        if ok && out?.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" {
            let activeGen = generation ?? PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.playbackGeneration }
            resumePlaybackIfNeeded(generation: activeGen, dbId: dbId)
            return true
        }
        return false
    }

    func resumePlaybackIfNeeded(generation: UInt64? = nil, dbId: Int? = nil) {
        if !isTestingEnvironment {
            let targetGen = generation ?? PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.playbackGeneration }
            for delay in [0.4, 1.0, 1.8] {
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    let shouldAbort = PlaybackStateStore.shared.withLock {
                        PlaybackStateStore.shared.isUserPaused ||
                        PlaybackStateStore.shared.isStagingCloudTrack ||
                        PlaybackStateStore.shared.playbackGeneration != targetGen
                    }
                    if shouldAbort { return }
                    let (stOk, stOut) = AppleScriptExecutor.shared.execute("tell application \"Music\" to get player state as string")
                    if stOk, stOut?.trimmingCharacters(in: .whitespacesAndNewlines) == "playing" {
                        return
                    }
                    let recheckAbort = PlaybackStateStore.shared.withLock {
                        PlaybackStateStore.shared.isUserPaused ||
                        PlaybackStateStore.shared.isStagingCloudTrack ||
                        PlaybackStateStore.shared.playbackGeneration != targetGen
                    }
                    if recheckAbort { return }
                    if let targetDbId = dbId, targetDbId > 0 {
                        _ = AppleScriptExecutor.shared.execute("""
                        tell application "Music"
                            try
                                set foundTrack to (first track of library playlist 1 whose database ID is \(targetDbId))
                                play foundTrack once true
                            on error
                                try
                                    play
                                end try
                            end try
                        end tell
                        """)
                    } else {
                        _ = AppleScriptExecutor.shared.execute("""
                        tell application "Music"
                            try
                                play
                            end try
                        end tell
                        """)
                    }
                }
            }
        }
    }
}
