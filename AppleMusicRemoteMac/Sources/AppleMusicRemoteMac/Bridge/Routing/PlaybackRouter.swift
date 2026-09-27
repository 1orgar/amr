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

    @discardableResult
    public func openMusicUrl(_ urlString: String) -> Bool {
        var target = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if target.hasPrefix("https://") {
            target = "music://" + target.dropFirst(8)
        }
        guard let url = URL(string: target) else { return false }
        DispatchQueue.main.async {
            NSWorkspace.shared.open(url)
        }
        return true
    }

    // MARK: - Playlist Playback

    public func playPlaylist(name: String, trackId: Int?, trackIndex: Int?, shuffle: Bool) -> Bool {
        BitPerfectLogMonitor.shared.resetTrackState()
        let pl = name.isEmpty ? "Музыка" : name

        PlaybackStateStore.shared.resetPlaybackState(originalPlaylist: pl)
        let escapedPl = pl.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")

        let plTracks = LibraryService.shared.getPlaylistTracks(name: pl)
        var startIdx = 0
        if let targetIdx = trackIndex, targetIdx > 0 {
            startIdx = targetIdx - 1
        } else if let targetId = trackId, targetId > 0 {
            if let found = plTracks.firstIndex(where: { $0.numericId == targetId }) {
                startIdx = found
            }
        }

        if !shuffle {
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.isShuffleQueueActive = false
                PlaybackStateStore.shared.activeShuffledQueue.removeAll()
                PlaybackStateStore.shared.activeShuffledPlaylistName = nil
                PlaybackStateStore.shared.isCustomQueuePlayback = true
                PlaybackStateStore.shared.activeCustomQueue = plTracks
                PlaybackStateStore.shared.activeCustomQueueIndex = startIdx
                PlaybackStateStore.shared.activeCustomQueueName = pl
            }

            let script = """
            tell application "Music"
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
                if plTarget is missing value and ("\(escapedPl)" contains "Любим" or "\(escapedPl)" contains "Favorit") then
                    try
                        set plTarget to (first playlist whose name contains "Любим" or name contains "Favorit")
                    end try
                end if
                if plTarget is not missing value then
                    set shuffle enabled to false
                    try
                        if \(startIdx) = 0 then
                            play plTarget
                        else
                            play track \(startIdx + 1) of plTarget
                        end if
                        return "ok"
                    on error
                        play plTarget
                        return "ok"
                    end try
                end if
                return "error"
            end tell
            """
            let (ok, _) = AppleScriptExecutor.shared.execute(script)
            if ok {
                if let app = MusicAppProvider.shared.getMusicApp() {
                    app.shuffleEnabled = false
                }
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
            }
            return ok
        } else {
            // Shuffle Mode
            var plTracks = LibraryService.shared.getPlaylistTracks(name: pl)
            var total = plTracks.count
            if total == 0 {
                let (cntOk, cntOut) = AppleScriptExecutor.shared.execute("""
                tell application "Music"
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
                        set plTarget to library playlist 1
                    end if
                    return count of tracks of plTarget
                end tell
                """)
                if cntOk, let s = cntOut, let c = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    total = c
                }
            }

            guard total > 0 else {
                NSLog("[PlaybackRouter] playPlaylist shuffle: no tracks found for %@", pl)
                return false
            }

            var orderIndices: [Int]
            if total <= 120 {
                orderIndices = Array(1...total).shuffled()
            } else {
                var picked = Set<Int>()
                while picked.count < 120 {
                    picked.insert(Int.random(in: 1...total))
                }
                orderIndices = Array(picked).shuffled()
            }

            if startIdx >= 0 && startIdx < total {
                let target1Based = startIdx + 1
                if let pos = orderIndices.firstIndex(of: target1Based), pos != 0 {
                    orderIndices.remove(at: pos)
                    orderIndices.insert(target1Based, at: 0)
                }
            }

            let indicesStr = orderIndices.map(String.init).joined(separator: ", ")

            let script = """
            tell application "Music"
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
                if plTarget is missing value and ("\(escapedPl)" contains "Любим" or "\(escapedPl)" contains "Favorit") then
                    try
                        set plTarget to (first playlist whose name contains "Любим" or name contains "Favorit")
                    end try
                end if
                if plTarget is missing value then
                    set plTarget to library playlist 1
                end if

                set qPl to missing value
                try
                    set qPl to user playlist "Очередь AMR"
                end try
                if qPl is missing value then
                    try
                        set qPl to (make new user playlist with properties {name:"Очередь AMR"})
                    end try
                end if

                if qPl is not missing value and plTarget is not missing value then
                    delete every track of qPl
                    set idxList to {\(indicesStr)}
                    repeat with trIdx in idxList
                        try
                            duplicate (track trIdx of plTarget) to qPl
                        end try
                    end repeat
                    set shuffle enabled to false
                    try
                        play qPl
                        return "ok"
                    end try
                end if
                return "error"
            end tell
            """
            let (ok, _) = AppleScriptExecutor.shared.execute(script)
            if ok {
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.isShuffleQueueActive = true
                    PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                    PlaybackStateStore.shared.activeShuffledPlaylistName = "Очередь AMR"
                }
                LibraryService.shared.invalidatePlaylistCache(name: "Очередь AMR")
                if let app = MusicAppProvider.shared.getMusicApp() {
                    app.shuffleEnabled = false
                }
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
            }
            return ok
        }
    }

    // MARK: - Station Playback

    public func playStation(url: String, name: String) -> Bool {
        guard !url.isEmpty || !name.isEmpty else { return false }
        var targetUrl = url
        if targetUrl.contains("ra.u-personal") || name.contains("Моя станция") {
            targetUrl = "https://music.apple.com/station/my-station/ra.u-96b95a031a2fb0aa1abb70ff757aa95f"
        } else if targetUrl.contains("ra.u-discovery") || name.contains("открытий") || name.contains("В моем вкусе") {
            targetUrl = "https://music.apple.com/station/item/ra.q-GAI6IDk2Yjk1YTAzMWEyZmIwYWExYWJiNzBmZjc1N2FhOTVm"
        }
        var playUrl = targetUrl
        if playUrl.hasPrefix("https://") {
            playUrl = "music://" + playUrl.dropFirst(8)
        }

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isRadioPlayback = true
            PlaybackStateStore.shared.activeStationName = !name.isEmpty ? name : "Apple Music Radio"
            PlaybackStateStore.shared.isCustomQueuePlayback = false
            PlaybackStateStore.shared.activeCustomQueue.removeAll()
            PlaybackStateStore.shared.activeCustomQueueName = nil
            PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
            PlaybackStateStore.shared.latestUpcomingTracks.removeAll()
            PlaybackStateStore.shared.latestHistoryTracks.removeAll()
            PlaybackStateStore.shared.isShuffleQueueActive = false
            PlaybackStateStore.shared.activeShuffledQueue.removeAll()
            PlaybackStateStore.shared.activeShuffledPlaylistName = nil
            PlaybackStateStore.shared.playbackQueueCache = nil
        }

        let ok = openMusicUrl(playUrl)
        if ok {
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to play")
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    self.syncCurrentTrackToAMRQueue(clearQueue: true)
                    PlaybackStateStore.shared.invalidateQueueCache()
                    PlaybackStateStore.shared.invalidateStatusCache()
                    WebSocketServer.shared.broadcastStatus(includeQueue: true)
                }
            }
        }
        return ok
    }

    // MARK: - Album Playback

    public func playAlbum(id: String, name: String, artist: String, startIndex: Int = 0, shuffle: Bool = false) async -> Bool {
        var album = await CloudCatalogService.shared.getAlbumDetails(albumId: id, country: "ru")
        if album == nil || (album?.tracks?.isEmpty ?? true) {
            album = await CloudCatalogService.shared.getAlbumDetails(albumId: id, country: "us")
        }

        var albumTracks = album?.tracks ?? []
        if albumTracks.isEmpty && (!name.isEmpty || !artist.isEmpty) {
            albumTracks = await MusicKitManager.shared.getAlbumTracks(album: name, artist: artist, storefront: "ru")
            if albumTracks.isEmpty {
                albumTracks = await MusicKitManager.shared.getAlbumTracks(album: name, artist: artist, storefront: "us")
            }
        }

        if !albumTracks.isEmpty {
            let qName = !name.isEmpty ? name : (album?.name ?? "Альбом")
            let ok = playCustomTracks(albumTracks, startIndex: startIndex, shuffle: shuffle, queueName: qName)
            if ok {
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
                return true
            }
        }

        // Direct Apple Music URL fallback
        let targetUrl = !id.isEmpty ? "music://music.apple.com/album/\(id)" : ""
        if !targetUrl.isEmpty, openMusicUrl(targetUrl) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to play")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to play")
            return true
        }
        return false
    }

    // MARK: - Hero Card Playback

    public func playHeroCard(index: Int, name: String, artist: String? = nil, cardId: String?, url: String?, type: String? = nil) async -> Bool {
        BitPerfectLogMonitor.shared.resetTrackState()

        let isStation = (type == "station") || (cardId?.hasPrefix("ra.") == true) || name.lowercased().contains("станция")
        var targetUrl = url ?? ""
        var actualCardId = cardId ?? ""
        let art = artist ?? ""

        if targetUrl.contains("ra.u-personal") || actualCardId == "station_personal" || name.contains("Моя станция") {
            actualCardId = "ra.u-96b95a031a2fb0aa1abb70ff757aa95f"
            targetUrl = "https://music.apple.com/station/my-station/ra.u-96b95a031a2fb0aa1abb70ff757aa95f"
        } else if targetUrl.contains("ra.u-discovery") || actualCardId == "station_discovery" || name.contains("открытий") || name.contains("В моем вкусе") {
            actualCardId = "ra.q-GAI6IDk2Yjk1YTAzMWEyZmIwYWExYWJiNzBmZjc1N2FhOTVm"
            targetUrl = "https://music.apple.com/station/item/ra.q-GAI6IDk2Yjk1YTAzMWEyZmIwYWExYWJiNzBmZjc1N2FhOTVm"
        }

        if isStation {
            return playStation(url: targetUrl, name: name)
        }

        if type == "playlist" || actualCardId.hasPrefix("pl.") {
            let plName = !name.isEmpty ? name : actualCardId
            let ok = playPlaylist(name: plName, trackId: nil, trackIndex: nil, shuffle: false)
            if ok {
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
                return true
            }
        }

        if type == "album" || (!actualCardId.isEmpty && !actualCardId.hasPrefix("ra.") && !actualCardId.hasPrefix("pl.")) {
            if await playAlbum(id: actualCardId, name: name, artist: art, shuffle: false) {
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
                return true
            }
        }

        let cleanQuery = name
            .replacingOccurrences(of: " - Single", with: "")
            .replacingOccurrences(of: " - EP", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if await searchAndPlay(query: cleanQuery) {
            try? await Task.sleep(nanoseconds: 800_000_000)
            _ = syncCurrentTrackToAMRQueue(clearQueue: true)
            PlaybackStateStore.shared.invalidateQueueCache()
            PlaybackStateStore.shared.invalidateStatusCache()
            WebSocketServer.shared.broadcastStatus(includeQueue: true)
            return true
        }
        if cleanQuery.hasSuffix("s") || cleanQuery.hasSuffix("S") {
            let singular = String(cleanQuery.dropLast())
            if await searchAndPlay(query: singular) {
                try? await Task.sleep(nanoseconds: 800_000_000)
                _ = syncCurrentTrackToAMRQueue(clearQueue: true)
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
                return true
            }
        }

        if targetUrl.isEmpty && !actualCardId.isEmpty {
            if actualCardId.hasPrefix("ra.") {
                targetUrl = "https://music.apple.com/station/item/\(actualCardId)"
            } else if actualCardId.hasPrefix("pl.") {
                targetUrl = "https://music.apple.com/playlist/\(actualCardId)"
            } else {
                targetUrl = "https://music.apple.com/album/\(actualCardId)"
            }
        }

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isRadioPlayback = false
            PlaybackStateStore.shared.activeStationName = nil
            PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
            PlaybackStateStore.shared.activeCustomQueueName = "Очередь AMR"
        }

        var launched = false
        if !targetUrl.isEmpty {
            if openMusicUrl(targetUrl) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to play")
                launched = true
            }
        }

        guard launched else { return false }

        try? await Task.sleep(nanoseconds: 1_200_000_000)
        _ = syncCurrentTrackToAMRQueue(clearQueue: true)
        PlaybackStateStore.shared.invalidateQueueCache()
        PlaybackStateStore.shared.invalidateStatusCache()
        WebSocketServer.shared.broadcastStatus(includeQueue: true)
        return true
    }

    // MARK: - Cloud Track Playback

    public func playCloud(url: String?, id: String?, name: String?, artist: String?, numericId: Int? = nil) async -> Bool {
        BitPerfectLogMonitor.shared.resetTrackState()
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isRadioPlayback = false
            PlaybackStateStore.shared.activeStationName = nil
        }

        let escN = (name ?? "").replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let escA = (artist ?? "").replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let numId = numericId ?? (Int(id ?? "") ?? 0)

        // 1. Temporary Playlist "Очередь AMR" playback
        let script = """
        tell application "Music"
            set qPl to missing value
            try
                set qPl to playlist "Очередь AMR"
            end try
            if qPl is missing value then
                try
                    set qPl to (make new user playlist with properties {name:"Очередь AMR"})
                end try
            end if
            if qPl is not missing value then
                delete every track of qPl
            end if

            set foundTrack to missing value

            -- A: By numeric database ID
            if \(numId) > 0 then
                try
                    set foundTrack to (first track of library playlist 1 whose database ID is \(numId))
                end try
                if foundTrack is missing value then
                    try
                        set foundTrack to (first track whose database ID is \(numId))
                    end try
                end if
            end if

            -- B: By exact name & artist
            if foundTrack is missing value and "\(escN)" is not "" and "\(escA)" is not "" then
                try
                    set matches to (every track of library playlist 1 whose name is "\(escN)" and artist is "\(escA)")
                    if (count of matches) > 0 then
                        set foundTrack to item 1 of matches
                    end if
                end try
            end if

            -- C: By search across all playlists
            if foundTrack is missing value and "\(escN)" is not "" then
                repeat with p in playlists
                    try
                        if name of p is not "Очередь AMR" then
                            set sMatches to (search p for "\(escN)")
                            if (count of sMatches) > 0 then
                                set foundTrack to item 1 of sMatches
                                exit repeat
                            end if
                        end if
                    end try
                end repeat
            end if

            if foundTrack is not missing value and qPl is not missing value then
                duplicate foundTrack to qPl
                set t to track 1 of qPl
                play t
                set actualDbId to (database ID of t as integer)
                set actualName to (name of t as string)
                set actualArtist to (artist of t as string)
                set actualAlbum to (album of t as string)
                set actualDur to (duration of t as real)
                return "ok||" & actualDbId & "||" & actualName & "||" & actualArtist & "||" & actualAlbum & "||" & actualDur
            end if
            return "not_found"
        end tell
        """

        let (ok, res) = AppleScriptExecutor.shared.execute(script)
        if ok, let out = res, out.hasPrefix("ok||") {
            let parts = out.components(separatedBy: "||")
            let actualId = parts.count > 1 ? (Int(parts[1]) ?? numId) : numId
            let actualName = parts.count > 2 ? parts[2] : (name ?? "")
            let actualArtist = parts.count > 3 ? parts[3] : (artist ?? "")
            let actualAlbum = parts.count > 4 ? parts[4] : ""
            let actualDur = parts.count > 5 ? (Double(parts[5]) ?? 0) : 0

            var artUrl = ""
            if let cached = MusicKitManager.shared.getCachedTrackArtwork(name: actualName, artist: actualArtist) {
                artUrl = cached
            } else if let local = ArtworkService.shared.findLocalTrackArtwork(name: actualName, artist: actualArtist) {
                artUrl = local
            }

            let tInfo = TrackInfo(
                id: "\(actualId)",
                numericId: actualId,
                name: actualName,
                artist: actualArtist,
                album: actualAlbum,
                duration: actualDur,
                hasArtwork: !artUrl.isEmpty,
                artworkUrl: artUrl,
                favorited: false,
                isLocal: true,
                index: 1
            )

            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                PlaybackStateStore.shared.activeCustomQueueName = "Очередь AMR"
                PlaybackStateStore.shared.isCustomQueuePlayback = true
                PlaybackStateStore.shared.activeCustomQueue = [tInfo]
                PlaybackStateStore.shared.activeCustomQueueIndex = 0
                PlaybackStateStore.shared.isShuffleQueueActive = false
                PlaybackStateStore.shared.activeShuffledQueue.removeAll()
                PlaybackStateStore.shared.activeShuffledPlaylistName = nil
            }
            LibraryService.shared.invalidatePlaylistCache(name: "Очередь AMR")

            PlaybackStateStore.shared.invalidateQueueCache()
            PlaybackStateStore.shared.invalidateStatusCache()
            WebSocketServer.shared.broadcastStatus(includeQueue: true)
            return true
        }

        // 2. Fallback to Cloud URL
        var targetUrl = url ?? ""
        if targetUrl.isEmpty, let songId = id, !songId.isEmpty {
            targetUrl = "https://music.apple.com/album/song/\(songId)"
        }
        if !targetUrl.isEmpty {
            openMusicUrl(targetUrl)
            try? await Task.sleep(nanoseconds: 800_000_000)
            let playScript = """
            tell application "Music"
                try
                    play
                    return "ok||" & (name of current track as string)
                on error
                    return "err"
                end try
            end tell
            """
            let (cloudOk, cloudRes) = AppleScriptExecutor.shared.execute(playScript)
            if cloudOk, let res = cloudRes, res.hasPrefix("ok||") {
                let fallbackTrack = TrackInfo(
                    id: id ?? "0",
                    numericId: numId > 0 ? numId : nil,
                    name: name ?? "Apple Music",
                    artist: artist ?? "",
                    album: "",
                    duration: 0,
                    hasArtwork: false,
                    artworkUrl: "",
                    favorited: false,
                    isLocal: false,
                    index: 1
                )
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.currentOriginalPlaylistName = "Apple Music"
                    PlaybackStateStore.shared.activeCustomQueueName = "Apple Music"
                    PlaybackStateStore.shared.isCustomQueuePlayback = true
                    PlaybackStateStore.shared.activeCustomQueue = [fallbackTrack]
                    PlaybackStateStore.shared.activeCustomQueueIndex = 0
                }

                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
                return true
            }
        }

        return false
    }

    public func playCloudSync(url: String?, id: String?, name: String?, artist: String?) -> Bool {
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isRadioPlayback = false
            PlaybackStateStore.shared.activeStationName = nil
        }

        if let n = name, let a = artist, !n.isEmpty, !a.isEmpty {
            let escN = n.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let escA = a.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let searchScript = """
            tell application "Music"
              try
                set foundTracks to (every track of library playlist 1 whose name is "\(escN)" and artist is "\(escA)")
                if (count of foundTracks) > 0 then
                  play item 1 of foundTracks
                  return "ok"
                end if
              end try
              try
                set foundTracks to (every track of library playlist 1 whose name is "\(escN)")
                if (count of foundTracks) > 0 then
                  play item 1 of foundTracks
                  return "ok"
                end if
              end try
              return "not_found"
            end tell
            """
            let (ok, res) = AppleScriptExecutor.shared.execute(searchScript)
            if ok, res?.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" {
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                return true
            }
        }

        // Try catalog song ID via radio station scheme (starts playing this exact song immediately)
        var songId: String? = nil
        if let rawId = id, let n = Int(rawId), n > 0 {
            songId = rawId
        } else if let u = url, let comp = URLComponents(string: u), let qi = comp.queryItems?.first(where: { $0.name == "i" })?.value, let n = Int(qi), n > 0 {
            songId = qi
        }

        if let sId = songId {
            let stationUrl = "music://music.apple.com/station/item/ra.\(sId)"
            let ok = openMusicUrl(stationUrl)
            if ok {
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                return true
            }
        }

        // Fallback to direct URL if valid station or album URL
        var targetUrl = url ?? ""
        if !targetUrl.isEmpty {
            if targetUrl.contains("ra.") || targetUrl.contains("/station/") {
                return openMusicUrl(targetUrl)
            }
        }

        return false
    }

    // MARK: - Custom Tracks & Search Results

    public func playCustomTracks(_ tracks: [TrackInfo], startIndex: Int, shuffle: Bool, queueName: String?) -> Bool {
        return PlaybackStateStore.shared.withLock {
            playCustomTracksUnlocked(tracks, startIndex: startIndex, shuffle: shuffle, queueName: queueName)
        }
    }

    public func playCustomTracksUnlocked(_ tracks: [TrackInfo], startIndex: Int, shuffle: Bool, queueName: String?) -> Bool {
        guard !tracks.isEmpty else { return false }
        let displayName = queueName?.isEmpty == false ? queueName! : "Очередь"
        PlaybackStateStore.shared.currentOriginalPlaylistName = displayName
        PlaybackStateStore.shared.activeCustomQueueName = displayName
        PlaybackStateStore.shared.isCustomQueuePlayback = true
        PlaybackStateStore.shared.isRadioPlayback = false

        var finalTracks = tracks
        var targetIndex = 0

        if shuffle {
            finalTracks.shuffle()
            if startIndex >= 0 && startIndex < tracks.count {
                let sel = tracks[startIndex]
                if let found = finalTracks.firstIndex(where: { $0.id == sel.id }), found != 0 {
                    let item = finalTracks.remove(at: found)
                    finalTracks.insert(item, at: 0)
                }
            }
            targetIndex = 0
        } else if startIndex >= 0 && startIndex < finalTracks.count {
            targetIndex = startIndex
        }

        PlaybackStateStore.shared.activeCustomQueue = finalTracks
        PlaybackStateStore.shared.activeCustomQueueIndex = targetIndex
        return QueueManager.shared.playQueueIndexUnlocked(targetIndex)
    }

    public func playSearchResults(tracks: [TrackInfo], shuffle: Bool) async -> Bool {
        guard !tracks.isEmpty else { return false }
        var playList = tracks
        if shuffle {
            playList.shuffle()
        }

        let first = playList[0]
        let remaining = Array(playList.dropFirst())

        let played = await playCloud(
            url: first.url,
            id: first.id,
            name: first.name,
            artist: first.artist,
            numericId: first.numericId
        )

        guard played else { return false }

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isRadioPlayback = false
            PlaybackStateStore.shared.activeStationName = nil
            PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
            PlaybackStateStore.shared.activeCustomQueueName = "Результаты поиска"
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            var formattedQueue = [first]
            for (idx, var t) in remaining.enumerated() {
                t.index = idx + 2
                formattedQueue.append(t)
            }
            PlaybackStateStore.shared.activeCustomQueue = formattedQueue
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.latestUpcomingTracks = remaining
            PlaybackStateStore.shared.isShuffleQueueActive = false
            PlaybackStateStore.shared.activeShuffledQueue.removeAll()
            PlaybackStateStore.shared.playbackQueueCache = nil
        }

        PlaybackStateStore.shared.invalidateQueueCache()
        PlaybackStateStore.shared.invalidateStatusCache()
        WebSocketServer.shared.broadcastStatus(includeQueue: true)
        return true
    }

    public func searchAndPlay(query: String) async -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return false }

        // 1. Check local library first
        let localTracks = LibraryService.shared.getLibrarySongs()
        let lowerQ = q.lowercased()
        if let match = localTracks.first(where: {
            $0.name.lowercased().contains(lowerQ) ||
            $0.artist.lowercased().contains(lowerQ) ||
            $0.album.lowercased().contains(lowerQ) ||
            lowerQ.contains($0.name.lowercased())
        }) {
            if let nid = match.numericId, nid > 0 {
                let script = """
                tell application "Music"
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
                let (ok, res) = AppleScriptExecutor.shared.execute(script)
                if ok, res?.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" {
                    return true
                }
            }
            return playCustomTracks([match], startIndex: 0, shuffle: false, queueName: "Search: \(q)")
        }

        // 2. Fallback to Cloud Catalog / Apple Music Search
        let searchResults = await CloudCatalogService.shared.search(query: q, country: "ru", source: "cloud")
        if let anySongs = searchResults["songs"]?.value as? [[String: Any]], !anySongs.isEmpty {
            let first = anySongs[0]
            let id = "\(first["id"] ?? "")"
            let name = first["name"] as? String ?? ""
            let artist = first["artist"] as? String ?? ""
            let url = first["url"] as? String ?? ""
            return playCloudSync(url: url, id: id, name: name, artist: artist)
        }

        // 3. AppleScript search in Apple Music app
        let escQ = q.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Music"
            try
                set foundTracks to (every track of library playlist 1 whose name contains "\(escQ)" or artist contains "\(escQ)")
                if (count of foundTracks) > 0 then
                    play item 1 of foundTracks
                    return "ok"
                end if
            end try
            return "not_found"
        end tell
        """
        let (ok, res) = AppleScriptExecutor.shared.execute(script)
        return ok && res == "ok"
    }

    @discardableResult
    public func syncCurrentTrackToAMRQueue(clearQueue: Bool = false) -> Bool {
        let script = """
        tell application "Music"
            set ct to current track
            if ct is not missing value then
                set curName to name of ct
                set curArtist to artist of ct
                try
                    duplicate ct to source 1
                end try
                set qPl to missing value
                try
                    set qPl to user playlist "Очередь AMR"
                end try
                if qPl is missing value then
                    try
                        set qPl to (make new user playlist with properties {name:"Очередь AMR"})
                    end try
                end if
                if qPl is not missing value then
                    if \(clearQueue ? "true" : "false") then
                        delete every track of qPl
                    end if
                    set alreadyPresent to false
                    try
                        set matches to (every track of qPl whose name is curName)
                        if (count of matches) > 0 then
                            set alreadyPresent to true
                        end if
                    end try
                    if not alreadyPresent then
                        try
                            set foundTracks to (search (library playlist 1) for curName)
                            if (count of foundTracks) > 0 then
                                duplicate (item 1 of foundTracks) to qPl
                                return "ok||" & (name of item 1 of foundTracks)
                            end if
                        end try
                    else
                        return "already_present"
                    end if
                end if
            end if
            return "not_found"
        end tell
        """
        let (ok, out) = AppleScriptExecutor.shared.execute(script)
        if ok {
            LibraryService.shared.invalidatePlaylistCache(name: "Очередь AMR")
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
            }
            PlaybackStateStore.shared.invalidateQueueCache()
        }
        return ok && (out?.hasPrefix("ok||") == true || out == "already_present")
    }
}
