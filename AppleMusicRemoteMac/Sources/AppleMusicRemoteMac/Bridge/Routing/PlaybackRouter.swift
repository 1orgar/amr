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

    private static let allowedAppleMusicHosts: Set<String> = [
        "music.apple.com",
        "itunes.apple.com",
        "geo.music.apple.com",
        "beta.music.apple.com"
    ]

    /// Strictly validates that a URL uses `music://` or `itmss://` and targets an Apple Music / iTunes resource.
    /// Rejects `file://`, `smb://`, `ssh://`, `vnc://`, `javascript:`, `x-apple.systempreferences:`, arbitrary `http(s)://`, etc.
    public static func isAllowedMusicAppURL(_ url: URL) -> Bool {
        guard url.user == nil, url.password == nil, url.port == nil else { return false }
        guard let scheme = url.scheme?.lowercased(),
              scheme == "music" || scheme == "itmss" else {
            return false
        }
        let rawHost = url.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let host = rawHost.map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }

        if let h = host, !h.isEmpty {
            if allowedAppleMusicHosts.contains(h) {
                return true
            }
            if h.hasPrefix("ra.") {
                let suffix = h.dropFirst(3)
                return !suffix.isEmpty && suffix.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
            }
            if h == "station" || h == "album" || h == "playlist" {
                return true
            }
            if h.allSatisfy(\.isNumber) {
                return true
            }
            return false
        }

        // Empty / nil host (e.g. music:///station/...)
        let path = url.path.lowercased()
        return path.hasPrefix("/station/") || path.hasPrefix("/album/") || path.hasPrefix("/playlist/")
    }

    @discardableResult
    public func openMusicUrl(_ urlString: String) -> Bool {
        var target = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return false }
        guard !target.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return false
        }

        let lower = target.lowercased()
        if lower.hasPrefix("https://") || lower.hasPrefix("http://") {
            let prefixLen = lower.hasPrefix("https://") ? "https://".count : "http://".count
            let remainder = String(target.dropFirst(prefixLen))
            let hostPart = remainder.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)?.lowercased() ?? ""
            guard Self.allowedAppleMusicHosts.contains(hostPart) else {
                return false
            }
            target = "music://" + remainder
        } else if !lower.hasPrefix("music://") && !lower.hasPrefix("itmss://") {
            // Reject any explicit non-music URL scheme (e.g. file:, smb:, ssh:, vnc:, javascript:, x-apple.systempreferences:, terminal:)
            if target.contains(":") {
                return false
            }
            let lowerRel = lower
            if lowerRel.hasPrefix("music.apple.com/") || lowerRel.hasPrefix("itunes.apple.com/") || lowerRel.hasPrefix("geo.music.apple.com/") || lowerRel.hasPrefix("beta.music.apple.com/") {
                target = "music://" + target
            } else if lowerRel.hasPrefix("ra.") {
                target = "music://music.apple.com/station/item/" + target
            } else if lowerRel.hasPrefix("/station/") || lowerRel.hasPrefix("/album/") || lowerRel.hasPrefix("/playlist/") {
                target = "music://music.apple.com" + target
            } else if lowerRel.hasPrefix("station/") || lowerRel.hasPrefix("album/") || lowerRel.hasPrefix("playlist/") {
                target = "music://music.apple.com/" + target
            } else {
                return false
            }
        }

        let parsedUrl = URL(string: target)
            ?? target.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap { URL(string: $0) }
        guard let url = parsedUrl, Self.isAllowedMusicAppURL(url) else {
            return false
        }

        if let opener = urlOpener {
            return opener(url)
        }

        if isTestingEnvironment {
            return true
        }

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
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.playbackGeneration &+= 1
            PlaybackStateStore.shared.isStagingCloudTrack = false
        }
        let pl = name.isEmpty ? "Музыка" : name

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
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.activeStationName = "Сейчас на повторе"
            }
            return playCustomTracks(hrTracks, startIndex: startIdx, shuffle: shuffle, queueName: "Сейчас на повторе")
        }

        // Deterministic Shuffle for local/library playlists: build ONE fixed shuffled queue in `activeCustomQueue`
        // (preserving `originalCustomQueue` for unshuffling) so the queue NEVER regenerates after each track!
        if shuffle && !isTestingEnvironment {
            let rawPlTracks = LibraryService.shared.getPlaylistTracks(name: pl)
            if !rawPlTracks.isEmpty {
                let resolvedTracks = LibraryService.shared.resolveLocalLibraryMatches(
                    rawPlTracks,
                    updateNames: false,
                    includeStagedTemporary: false
                )
                if resolvedTracks.contains(where: { $0.isLocal == true }) || MusicKitManager.shared.hasUserToken {
                    var pinnedStartIdx = -1
                    if let targetIdx = trackIndex, targetIdx > 0, targetIdx - 1 < resolvedTracks.count {
                        pinnedStartIdx = targetIdx - 1
                    } else if let targetId = trackId, targetId > 0,
                              let found = resolvedTracks.firstIndex(where: { $0.numericId == targetId }) {
                        pinnedStartIdx = found
                    }
                    if let app = MusicAppProvider.shared.getMusicApp() {
                        app.shuffleEnabled = false
                    }
                    return playCustomTracks(resolvedTracks, startIndex: pinnedStartIdx, shuffle: true, queueName: pl)
                }
            }
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
        if !shuffle && startIdx == 0 {
            playCmd = """
            if plClass is "subscription playlist" then
                                    set shuffle enabled to false
                                    play plTarget
                                    set shuffle enabled to false
                                else
                                    play track 1 of plTarget
                                end if
            """
        } else if startIdx > 0 {
            playCmd = """
            if plClass is "subscription playlist" then
                                    return "err: subscription_specific_index"
                                else
                                    play track \(startIdx + 1) of plTarget
                                end if
            """
        } else if shuffle && hasSpecificTrack {
            playCmd = """
            if plClass is "subscription playlist" then
                                    return "err: subscription_specific_index"
                                else
                                    play track \(max(1, startIdx + 1)) of plTarget
                                end if
            """
        } else {
            playCmd = """
            if plClass is "subscription playlist" then
                                    set shuffle mode to songs
                                    set shuffle enabled to true
                                    play plTarget
                                else
                                    set plCnt to (count of tracks of plTarget)
                                    if plCnt > 1 then
                                        set rndIdx to (random number from 1 to plCnt)
                                        play track rndIdx of plTarget
                                    else
                                        play plTarget
                                    end if
                                end if
            """
        }

        if let app = MusicAppProvider.shared.getMusicApp() {
            app.shuffleEnabled = shuffle
        }

        let currentRepMode = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.repeatMode }
        let applePlaylistRepeat = ["off", "one", "all"].contains(currentRepMode) ? currentRepMode : "off"

        let allowWholePlaylistFallback = (startIdx == 0 && !hasSpecificTrack)
        let fallbackOnPlayError: String
        if allowWholePlaylistFallback {
            fallbackOnPlayError = """
                                try
                                    play plTarget
                                    \(shuffle ? "set shuffle mode to songs\n                                    set shuffle enabled to true" : "set shuffle enabled to false")
                                    set song repeat to \(applePlaylistRepeat)
                                    return "ok"
                                on error err2
                                    return "err: " & err & " / " & err2
                                end try
            """
        } else {
            fallbackOnPlayError = """
                                return "err: specific_index_failed: " & err
            """
        }

        let script = """
        tell application "Music"
            try
                with timeout of 1.8 seconds
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
                        set plClass to ""
                        try
                            set plClass to (class of plTarget as string)
                        end try
                        if plClass is "subscription playlist" and \((startIdx > 0 || hasSpecificTrack) ? "true" : "false") then
                            return "err: subscription_specific_index"
                        end if
                        if plClass is not "subscription playlist" then
                            try
                                if (count of tracks of plTarget) is 0 then
                                    return "err: empty_playlist"
                                end if
                            end try
                        end if
                        try
                            stop
                        end try
                        \(shuffle ? "set shuffle mode to songs\n                        set shuffle enabled to true" : "set shuffle enabled to false")
                        set song repeat to \(applePlaylistRepeat)
                        try
                            \(playCmd)
                            \(shuffle ? "set shuffle mode to songs\n                            set shuffle enabled to true" : "set shuffle enabled to false")
                            set song repeat to \(applePlaylistRepeat)
                            return "ok"
                        on error err
                            \(fallbackOnPlayError)
                        end try
                    end if
                    return "error: plTarget missing"
                end timeout
            on error
                return "error: timeout"
            end try
        end tell
        """

        let (ok, res) = AppleScriptExecutor.shared.execute(script, maxWait: 2.3, reportTimeout: false)
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
        if !isTestingEnvironment && urlOpener == nil && SystemMusicPlayerBridge.shared.stop() {
            return
        }
        _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop", maxWait: 1.2, reportTimeout: false)
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
        let storeRepeat = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.repeatMode }
        let isRepeatOne = (storeRepeat == "one")
        let appleSongRepeat = isRepeatOne ? "one" : "off"
        let localPlayStatement = isRepeatOne ? "play foundTrack" : "play foundTrack once true"
        let script = """
        tell application "Music"
            try
                with timeout of 3 seconds
                    set foundTrack to missing value
                    try
                        set foundTrack to (first track of library playlist 1 whose database ID is \(dbId))
                    end try
                    if foundTrack is missing value then
                        return "not_found"
                    end if
                    try
                        stop
                    end try
                    set shuffle enabled to false
                    set song repeat to \(appleSongRepeat)
                    try
                        \(localPlayStatement)
                        return "ok"
                    on error playErr number playErrNum
                        if playErrNum is -1712 then
                            return "ok_buffering"
                        end if
                        try
                            play foundTrack
                            return "ok"
                        on error playErr2 number playErrNum2
                            if playErrNum2 is -1712 then
                                return "ok_buffering"
                            end if
                            return "err:" & playErrNum2 & ":" & playErr2
                        end try
                    end try
                end timeout
            on error outerErr number outerErrNum
                if outerErrNum is -1712 then
                    return "ok_buffering"
                end if
                return "err:" & outerErrNum & ":" & outerErr
            end try
        end tell
        """
        let (ok, out) = AppleScriptExecutor.shared.execute(script, maxWait: 5.6, reportTimeout: false)
        let trimmed = out?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "nil"
        if ok && (trimmed == "ok" || trimmed == "ok_buffering") {
            NSLog("[PlaybackRouter] ▶️ playTrackByDatabaseIdViaAMRQueue(dbId=%d) -> %@", dbId, trimmed)
            let activeGen = generation ?? PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.playbackGeneration }
            resumePlaybackIfNeeded(generation: activeGen, dbId: dbId)
            return true
        }
        NSLog("[PlaybackRouter] ⚠️ playTrackByDatabaseIdViaAMRQueue(dbId=%d) failed: ok=%d out=%@", dbId, ok ? 1 : 0, trimmed)
        return false
    }

    func resumePlaybackIfNeeded(generation: UInt64? = nil, dbId: Int? = nil) {
        if !isTestingEnvironment {
            let targetGen = generation ?? PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.playbackGeneration }
            let checkDelays: [TimeInterval] = (dbId != nil) ? [0.85, 2.2] : [0.45, 1.05, 1.85]
            for delay in checkDelays {
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    let shouldAbort = PlaybackStateStore.shared.withLock {
                        PlaybackStateStore.shared.isUserPaused ||
                        PlaybackStateStore.shared.isStagingCloudTrack ||
                        PlaybackStateStore.shared.playbackGeneration != targetGen
                    }
                    if shouldAbort { return }
                    let (stOk, stOut) = AppleScriptExecutor.shared.execute("tell application \"Music\" to get player state as string", maxWait: 1.0, reportTimeout: false)
                    let curState = stOut?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if stOk && curState == "playing" {
                        return
                    }
                    let recheckAbort = PlaybackStateStore.shared.withLock {
                        PlaybackStateStore.shared.isUserPaused ||
                        PlaybackStateStore.shared.isStagingCloudTrack ||
                        PlaybackStateStore.shared.playbackGeneration != targetGen
                    }
                    if recheckAbort { return }
                    if stOk && curState == "paused" {
                        _ = AppleScriptExecutor.shared.execute("""
                        tell application "Music"
                            try
                                with timeout of 1 seconds
                                    if player state is paused then play
                                end timeout
                            end try
                        end tell
                        """, maxWait: 1.4, reportTimeout: false)
                    }
                }
            }
        }
    }
}
