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

        if let url = URL(string: target) {
            return NSWorkspace.shared.open(url)
        }
        if let encoded = target.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded) {
            return NSWorkspace.shared.open(url)
        }
        return false
    }

    // MARK: - Playlist Playback

    public func playPlaylist(name: String, trackId: Int?, trackIndex: Int?, shuffle: Bool) -> Bool {
        BitPerfectLogMonitor.shared.resetTrackState()
        let pl = name.isEmpty ? "Музыка" : name

        // SPECIAL CASE: "Сейчас на повторе" is not a real Apple Music playlist, it's a dynamic mix from recent history.
        if pl == "Сейчас на повторе" || pl.lowercased().contains("повторе") {
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

        let plTracks = LibraryService.shared.getPlaylistTracks(name: pl)
        var startIdx = 0
        var hasSpecificTrack = false
        if let targetIdx = trackIndex, targetIdx > 0 {
            startIdx = targetIdx - 1
            hasSpecificTrack = true
        } else if let targetId = trackId, targetId > 0 {
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
            PlaybackStateStore.shared.isShuffleQueueActive = false
            PlaybackStateStore.shared.activeShuffledPlaylistName = nil
            PlaybackStateStore.shared.activeShuffledQueue.removeAll()
        }
        QueueManager.shared.stopQueueMonitoring()

        let playCmd: String
        if hasSpecificTrack {
            playCmd = "play track \(startIdx + 1) of plTarget"
        } else {
            playCmd = "play plTarget"
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
                set shuffle enabled to \(shuffle ? "true" : "false")
                try
                    \(playCmd)
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
        }
        return ok
    }

    // MARK: - Station Playback

    public func playStation(url: String, name: String) async -> Bool {
        await playStation(url: url, name: name, type: "", trackTitle: "", artistName: "")
    }

    public func playStation(url: String, name: String, type: String, trackTitle: String, artistName: String) async -> Bool {
        guard !url.isEmpty || !name.isEmpty || !trackTitle.isEmpty || !artistName.isEmpty else { return false }
        var targetUrl = url
        var stationDisplayName = name
        let lowName = name.lowercased()
        if targetUrl.contains("повторе") || lowName.contains("повторе") {
            return playPlaylist(name: "Сейчас на повторе", trackId: nil, trackIndex: nil, shuffle: true)
        }
        if targetUrl.contains("ra.u-personal") || name.contains("Моя станция") || lowName.contains("моя станция") {
            targetUrl = "https://music.apple.com/station/my-station/ra.u-96b95a031a2fb0aa1abb70ff757aa95f"
        } else if targetUrl.contains("ra.u-discovery") || name.contains("открытий") || name.contains("В моем вкусе") || lowName.contains("станция открытий") {
            targetUrl = "https://music.apple.com/station/item/ra.q-GAI6IDk2Yjk1YTAzMWEyZmIwYWExYWJiNzBmZjc1N2FhOTVm"
        } else if !targetUrl.contains("ra.") {
            if type == "track" || (!trackTitle.isEmpty && targetUrl.isEmpty) {
                let titleToResolve = trackTitle.isEmpty ? name : trackTitle
                if let resolved = await MusicKitManager.shared.resolveTrackStation(title: titleToResolve, artist: artistName) {
                    targetUrl = resolved
                    if stationDisplayName.isEmpty || stationDisplayName == "Apple Music Radio" {
                        stationDisplayName = "Станция «\(titleToResolve)»"
                    }
                } else if !artistName.isEmpty, let artistInfo = await MusicKitManager.shared.resolveArtistStation(artist: artistName) {
                    // Fallback Tier 2: Artist station when track-specific station is unavailable
                    targetUrl = artistInfo.stationUrl
                    if stationDisplayName.isEmpty || stationDisplayName == "Apple Music Radio" {
                        stationDisplayName = "Станция «\(artistInfo.canonicalName)»"
                    }
                }
            } else {
                let query = !artistName.isEmpty ? artistName : (!name.isEmpty ? name : url)
                if let info = await MusicKitManager.shared.resolveArtistStation(artist: query) {
                    targetUrl = info.stationUrl
                    if stationDisplayName.isEmpty || stationDisplayName == "Apple Music Radio" {
                        stationDisplayName = "Станция «\(info.canonicalName)»"
                    }
                }
            }
        }
        var playUrl = targetUrl
        if playUrl.hasPrefix("https://") {
            playUrl = "music://" + playUrl.dropFirst(8)
        }

        // Fallback Tier 3: If track-based station still has no URL, try playing catalog track directly
        // This natively triggers Apple Music Autoplay (∞) for the track's genre/style.
        if playUrl.isEmpty && (type == "track" || !trackTitle.isEmpty) {
            let t = trackTitle.isEmpty ? name : trackTitle
            let query = artistName.isEmpty ? t : "\(t) \(artistName)"
            if await searchAndPlay(query: query) {
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.isRadioPlayback = true
                    PlaybackStateStore.shared.activeStationName = "Станция «\(t)»"
                }
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: false)
                return true
            }
            return false
        }

        guard !playUrl.isEmpty || (!name.isEmpty && !name.hasPrefix("Станция «") && !name.hasPrefix("Радио ")) else {
            return false
        }

        _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop")
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isRadioPlayback = true
            PlaybackStateStore.shared.activeStationName = !stationDisplayName.isEmpty ? stationDisplayName : (!name.isEmpty ? name : "Apple Music Radio")
            PlaybackStateStore.shared.isCustomQueuePlayback = false
            PlaybackStateStore.shared.activeCustomQueue.removeAll()
            PlaybackStateStore.shared.activeCustomQueueName = nil
            PlaybackStateStore.shared.currentOriginalPlaylistName = nil
            PlaybackStateStore.shared.latestUpcomingTracks.removeAll()
            PlaybackStateStore.shared.latestHistoryTracks.removeAll()
            PlaybackStateStore.shared.isShuffleQueueActive = false
            PlaybackStateStore.shared.activeShuffledQueue.removeAll()
            PlaybackStateStore.shared.activeShuffledPlaylistName = nil
            PlaybackStateStore.shared.playbackQueueCache = nil
        }

        var ok = false
        if !playUrl.isEmpty {
            ok = openMusicUrl(playUrl)
        } else if !name.isEmpty && !name.hasPrefix("Станция «") && !name.hasPrefix("Радио ") {
            // Search local station via applescript fallback ONLY if name is a real local playlist
            let escName = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let (resOk, _) = AppleScriptExecutor.shared.execute("tell application \"Music\" to play playlist \"\(escName)\"")
            ok = resOk
        }

        if ok {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard self != nil else { return }
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: false)
            }
        }
        return ok
    }

    // MARK: - Album Playback

    public func playAlbumWithTracks(tracks: [TrackInfo], name: String, artist: String, startIndex: Int = 0, shuffle: Bool = false) async -> Bool {
        _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop")
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isRadioPlayback = false
            PlaybackStateStore.shared.activeStationName = nil
        }
        PlaybackStateStore.shared.invalidateQueueCache()
        PlaybackStateStore.shared.invalidateStatusCache()

        if !tracks.isEmpty {
            let qName = !name.isEmpty ? name : "Альбом"
            let ok = playCustomTracks(tracks, startIndex: startIndex, shuffle: shuffle, queueName: qName)
            if ok {
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
                return true
            }
            let validIdx = (startIndex >= 0 && startIndex < tracks.count) ? startIndex : 0
            let startTrack = tracks[validIdx]
            let cloudOk = await playCloud(url: startTrack.url, id: startTrack.id, name: startTrack.name, artist: startTrack.artist, numericId: startTrack.numericId)
            if cloudOk {
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.activeCustomQueue = tracks
                    PlaybackStateStore.shared.activeCustomQueueIndex = validIdx
                    PlaybackStateStore.shared.activeCustomQueueName = qName
                    PlaybackStateStore.shared.isCustomQueuePlayback = true
                }
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
                return true
            }
        }
        return false
    }

    public func playAlbum(id: String, name: String, artist: String, startIndex: Int = 0, shuffle: Bool = false) async -> Bool {
        _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop")
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isRadioPlayback = false
            PlaybackStateStore.shared.activeStationName = nil
        }
        PlaybackStateStore.shared.invalidateQueueCache()
        PlaybackStateStore.shared.invalidateStatusCache()

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
            // Direct fallback: play starting track via catalog song ID
            let validIdx = (startIndex >= 0 && startIndex < albumTracks.count) ? startIndex : 0
            let startTrack = albumTracks[validIdx]
            let cloudOk = await playCloud(url: startTrack.url, id: startTrack.id, name: startTrack.name, artist: startTrack.artist, numericId: startTrack.numericId)
            if cloudOk {
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.activeCustomQueue = albumTracks
                    PlaybackStateStore.shared.activeCustomQueueIndex = validIdx
                    PlaybackStateStore.shared.activeCustomQueueName = qName
                    PlaybackStateStore.shared.isCustomQueuePlayback = true
                }
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
                return true
            }
        }

        // Direct Apple Music URL fallback
        let targetUrl = !id.isEmpty ? "music://music.apple.com/album/\(id)" : ""
        if !targetUrl.isEmpty, openMusicUrl(targetUrl) {
            try? await Task.sleep(nanoseconds: 800_000_000)
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
        } else if targetUrl.isEmpty && actualCardId.hasPrefix("ra.") {
            targetUrl = "music://music.apple.com/station/\(actualCardId)"
        }

        if isStation {
            let stationName = !art.isEmpty ? art : name
            return await playStation(url: targetUrl, name: stationName)
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
        _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop")
        BitPerfectLogMonitor.shared.resetTrackState()
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isRadioPlayback = false
            PlaybackStateStore.shared.activeStationName = nil
        }

        let numId = numericId ?? (Int(id ?? "") ?? 0)

        // 1. If numeric database ID exists (> 0), try local library playlist first
        if numId > 0 {
            let script = """
            tell application "Music"
                stop
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
                try
                    set foundTrack to (first track of library playlist 1 whose database ID is \(numId))
                end try
                if foundTrack is missing value then
                    try
                        set foundTrack to (first track whose database ID is \(numId))
                    end try
                end if

                if foundTrack is not missing value and qPl is not missing value then
                    duplicate foundTrack to qPl
                    set shuffle enabled to false
                    play qPl
                    set t to track 1 of qPl
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
        }

        // 2. Cloud Track Playback (Apple Music catalog track NOT in local library)
        var catalogSongId: String? = nil
        if let rawId = id, let n = Int(rawId), n > 0 {
            catalogSongId = rawId
        } else if let u = url, let comp = URLComponents(string: u), let qi = comp.queryItems?.first(where: { $0.name == "i" })?.value, let n = Int(qi), n > 0 {
            catalogSongId = qi
        }

        var targetUrl = ""
        if let sId = catalogSongId {
            targetUrl = "music://music.apple.com/station/item/ra.\(sId)"
        } else if let u = url, !u.isEmpty {
            targetUrl = u
            if targetUrl.hasPrefix("https://music.apple.com") {
                targetUrl = "music://" + targetUrl.dropFirst("https://".count)
            }
        }

        if !targetUrl.isEmpty {
            let opened = openMusicUrl(targetUrl)
            if opened {
                if !isTestingEnvironment {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
                        _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to play")
                    }
                }
                var artUrl = ""
                if let a = artist, let n = name {
                    artUrl = MusicKitManager.shared.getCachedTrackArtwork(name: n, artist: a) ?? ""
                }

                let fallbackTrack = TrackInfo(
                    id: catalogSongId ?? id ?? "cloud",
                    numericId: nil,
                    name: name ?? "Apple Music",
                    artist: artist ?? "",
                    album: "",
                    duration: 0,
                    hasArtwork: !artUrl.isEmpty,
                    artworkUrl: artUrl,
                    favorited: false,
                    isLocal: false,
                    index: 1
                )
                PlaybackStateStore.shared.withLock {
                    let inMultiTrackQueue = PlaybackStateStore.shared.isCustomQueuePlayback && PlaybackStateStore.shared.activeCustomQueue.count > 1
                    if !inMultiTrackQueue {
                        PlaybackStateStore.shared.currentOriginalPlaylistName = "Apple Music"
                        PlaybackStateStore.shared.activeCustomQueueName = "Apple Music"
                        PlaybackStateStore.shared.isCustomQueuePlayback = true
                        PlaybackStateStore.shared.activeCustomQueue = [fallbackTrack]
                        PlaybackStateStore.shared.activeCustomQueueIndex = 0
                        PlaybackStateStore.shared.isRadioPlayback = true
                        PlaybackStateStore.shared.activeStationName = name ?? "Apple Music"
                    }
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
        _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop")
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isRadioPlayback = false
            PlaybackStateStore.shared.activeStationName = nil
        }

        // 1. Try catalog song ID via radio station scheme (starts playing this exact song immediately without freezing)
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
                if !isTestingEnvironment {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
                        _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to play")
                    }
                }
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                return true
            }
        }

        // 2. Direct station, album, or playlist URL fallback
        let targetUrl = url ?? ""
        if !targetUrl.isEmpty {
            let ok = openMusicUrl(targetUrl)
            if ok {
                if !isTestingEnvironment {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to play")
                    }
                }
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                return true
            }
        }

        // 3. Fallback: Search local library by name & artist ONLY if songId / URL failed or missing
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
        QueueManager.shared.startQueueMonitoring()
        return QueueManager.shared.playQueueIndexUnlocked(targetIndex)
    }

    public func playSearchResults(tracks: [TrackInfo], startIndex: Int = 0, shuffle: Bool) async -> Bool {
        guard !tracks.isEmpty else { return false }
        var playList = tracks
        var targetIndex = 0

        if shuffle {
            playList.shuffle()
            if startIndex >= 0 && startIndex < tracks.count {
                let sel = tracks[startIndex]
                if let found = playList.firstIndex(where: { $0.id == sel.id }), found != 0 {
                    let item = playList.remove(at: found)
                    playList.insert(item, at: 0)
                }
            }
            targetIndex = 0
        } else if startIndex >= 0 && startIndex < playList.count {
            targetIndex = startIndex
        }

        // Cleanly halt any previous audio/stream in Music.app first
        _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop")

        // Fast path for local tracks: batch-populate "Очередь AMR" in Music.app
        let localTracks = playList.filter { ($0.numericId ?? 0) > 0 || $0.isLocal == true }
        if localTracks.count == playList.count && !localTracks.isEmpty {
            let dbIds = localTracks.compactMap { $0.numericId }
            let idListStr = dbIds.map { "\($0)" }.joined(separator: ", ")
            let playTargetLine = (targetIndex > 0) ? "play track \(targetIndex + 1) of qPl" : "play qPl"
            let script = """
            tell application "Music"
                stop
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
                    set idList to {\(idListStr)}
                    repeat with tid in idList
                        try
                            set trk to (first track of library playlist 1 whose database ID is (contents of tid))
                            duplicate trk to qPl
                        end try
                    end repeat
                    if (count of tracks of qPl) > 0 then
                        set shuffle enabled to false
                        \(playTargetLine)
                        return "ok"
                    end if
                end if
                return "error"
            end tell
            """
            let (ok, res) = AppleScriptExecutor.shared.execute(script)
            if ok, res?.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" {
                BitPerfectLogMonitor.shared.resetTrackState()
                var formattedQueue = [TrackInfo]()
                for (idx, var t) in playList.enumerated() {
                    t.index = idx + 1
                    formattedQueue.append(t)
                }
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.isRadioPlayback = false
                    PlaybackStateStore.shared.activeStationName = nil
                    PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                    PlaybackStateStore.shared.activeCustomQueueName = "Результаты поиска"
                    PlaybackStateStore.shared.isCustomQueuePlayback = true
                    PlaybackStateStore.shared.activeCustomQueue = formattedQueue
                    PlaybackStateStore.shared.activeCustomQueueIndex = targetIndex
                    if targetIndex + 1 < formattedQueue.count {
                        PlaybackStateStore.shared.latestUpcomingTracks = Array(formattedQueue[(targetIndex + 1)...])
                    } else {
                        PlaybackStateStore.shared.latestUpcomingTracks = []
                    }
                    if targetIndex > 0 {
                        PlaybackStateStore.shared.latestHistoryTracks = Array(formattedQueue[0..<targetIndex].reversed())
                    } else {
                        PlaybackStateStore.shared.latestHistoryTracks = []
                    }
                    PlaybackStateStore.shared.lastCloudPlayTime = Date()
                    PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
                    PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
                    PlaybackStateStore.shared.lastWasPlayingCloud = false
                    PlaybackStateStore.shared.isShuffleQueueActive = false
                    PlaybackStateStore.shared.activeShuffledQueue.removeAll()
                    PlaybackStateStore.shared.playbackQueueCache = nil
                }
                QueueManager.shared.startQueueMonitoring()
                LibraryService.shared.invalidatePlaylistCache(name: "Очередь AMR")
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
                return true
            }
        }

        // Mixed or Cloud tracks:
        var played = false
        var actualPlayIndex = targetIndex
        for i in targetIndex..<playList.count {
            let tr = playList[i]
            let ok = await playCloud(
                url: tr.url,
                id: tr.id,
                name: tr.name,
                artist: tr.artist,
                numericId: tr.numericId
            )
            if ok {
                played = true
                actualPlayIndex = i
                break
            }
        }

        guard played else { return false }

        var formattedQueue = [TrackInfo]()
        for (idx, var t) in playList.enumerated() {
            t.index = idx + 1
            formattedQueue.append(t)
        }
        let curTrack = formattedQueue[actualPlayIndex]

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isRadioPlayback = false
            PlaybackStateStore.shared.activeStationName = nil
            PlaybackStateStore.shared.currentOriginalPlaylistName = (curTrack.numericId != nil && curTrack.numericId! > 0) ? "Очередь AMR" : nil
            PlaybackStateStore.shared.activeCustomQueueName = "Результаты поиска"
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = formattedQueue
            PlaybackStateStore.shared.activeCustomQueueIndex = actualPlayIndex
            if actualPlayIndex + 1 < formattedQueue.count {
                PlaybackStateStore.shared.latestUpcomingTracks = Array(formattedQueue[(actualPlayIndex + 1)...])
            } else {
                PlaybackStateStore.shared.latestUpcomingTracks = []
            }
            if actualPlayIndex > 0 {
                PlaybackStateStore.shared.latestHistoryTracks = Array(formattedQueue[0..<actualPlayIndex].reversed())
            } else {
                PlaybackStateStore.shared.latestHistoryTracks = []
            }
            PlaybackStateStore.shared.lastCloudPlayTime = Date()
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
            PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
            PlaybackStateStore.shared.lastWasPlayingCloud = false
            PlaybackStateStore.shared.isShuffleQueueActive = false
            PlaybackStateStore.shared.activeShuffledQueue.removeAll()
            PlaybackStateStore.shared.playbackQueueCache = nil
        }

        QueueManager.shared.startQueueMonitoring()
        PlaybackStateStore.shared.invalidateQueueCache()
        PlaybackStateStore.shared.invalidateStatusCache()
        WebSocketServer.shared.broadcastStatus(includeQueue: true)
        return true
    }

    public struct SearchAndPlayResult {
        public let success: Bool
        public let station: String?
        public let query: String?
        public let count: Int?

        public init(success: Bool, station: String? = nil, query: String? = nil, count: Int? = nil) {
            self.success = success
            self.station = station
            self.query = query
            self.count = count
        }
    }

    public func searchAndPlayDetailed(query: String) async -> SearchAndPlayResult {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. If query is empty -> randomly pick one of three stations:
        // "сейчас на повторе", "станция открытий" or "моя станция"
        if q.isEmpty {
            let stations = ["сейчас на повторе", "станция открытий", "моя станция"]
            let chosen = stations.randomElement() ?? "станция открытий"
            let ok: Bool
            switch chosen {
            case "сейчас на повторе":
                ok = playPlaylist(name: "Сейчас на повторе", trackId: nil, trackIndex: nil, shuffle: true)
            case "станция открытий":
                ok = await playStation(
                    url: "https://music.apple.com/station/item/ra.q-GAI6IDk2Yjk1YTAzMWEyZmIwYWExYWJiNzBmZjc1N2FhOTVm",
                    name: "Станция открытий"
                )
            case "моя станция":
                ok = await playStation(
                    url: "https://music.apple.com/station/my-station/ra.u-96b95a031a2fb0aa1abb70ff757aa95f",
                    name: "Моя станция"
                )
            default:
                ok = false
            }
            return SearchAndPlayResult(success: ok, station: chosen, query: nil, count: nil)
        }

        // 2. Query provided -> perform search and play found results sequentially
        // 2a. Unified search across local library and Apple Music cloud catalog (storefront: "ru")
        var searchResults = await CloudCatalogService.shared.search(query: q, country: "ru", source: "all")
        var anySongs = (searchResults["songs"]?.value as? [[String: Any]]) ?? []

        // 2b. Storefront fallback to "us" if "ru" returned no songs
        if anySongs.isEmpty {
            searchResults = await CloudCatalogService.shared.search(query: q, country: "us", source: "all")
            anySongs = (searchResults["songs"]?.value as? [[String: Any]]) ?? []
        }

        // 2c. Offline / AppleScript fallback if online search is unavailable
        if anySongs.isEmpty {
            let escQ = q.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
            tell application "Music"
                try
                    set foundTracks to (every track of library playlist 1 whose name contains "\(escQ)" or artist contains "\(escQ)")
                    set totalCount to count of foundTracks
                    if totalCount > 0 then
                        set idList to ""
                        repeat with i from 1 to totalCount
                            if i > 50 then exit repeat
                            set tr to item i of foundTracks
                            set idList to idList & (database ID of tr as integer) & "||" & (name of tr as string) & "||" & (artist of tr as string) & "||" & (album of tr as string) & "\\n"
                        end repeat
                        return idList
                    end if
                end try
                return "not_found"
            end tell
            """
            let (ok, res) = AppleScriptExecutor.shared.execute(script)
            if ok, let out = res, out != "not_found" {
                let lines = out.components(separatedBy: "\n")
                for line in lines {
                    let parts = line.components(separatedBy: "||")
                    if parts.count >= 4 {
                        let dbId = Int(parts[0]) ?? 0
                        let name = parts[1]
                        let artist = parts[2]
                        let album = parts[3]
                        anySongs.append([
                            "id": "\(dbId)",
                            "numeric_id": dbId,
                            "name": name,
                            "artist": artist,
                            "album": album,
                            "is_local": true
                        ])
                    }
                }
            }
        }

        guard !anySongs.isEmpty else {
            return SearchAndPlayResult(success: false, station: nil, query: q, count: 0)
        }

        // 2d. Build TrackInfo list
        var trackInfos: [TrackInfo] = []
        for (idx, item) in anySongs.prefix(50).enumerated() {
            let tid = (item["id"] as? String) ?? "\(idx + 1)"
            let numId = (item["numeric_id"] as? Int) ?? (item["numericId"] as? Int)
            let tName = (item["name"] as? String) ?? ""
            let tArtist = (item["artist"] as? String) ?? ""
            let tAlbum = (item["album"] as? String) ?? ""
            let tUrl = item["url"] as? String
            let tArt = (item["artwork_url"] as? String) ?? (item["artwork"] as? String) ?? ""
            let isLoc = (item["is_local"] as? Bool) ?? (item["isLocal"] as? Bool) ?? false
            let dur = (item["duration"] as? Double) ?? 0

            guard !tName.isEmpty else { continue }

            trackInfos.append(TrackInfo(
                id: tid,
                numericId: numId,
                name: tName,
                artist: tArtist,
                album: tAlbum,
                duration: dur,
                hasArtwork: !tArt.isEmpty,
                artworkUrl: tArt,
                favorited: false,
                isLocal: isLoc,
                url: tUrl,
                index: idx + 1
            ))
        }

        guard !trackInfos.isEmpty else {
            return SearchAndPlayResult(success: false, station: nil, query: q, count: 0)
        }

        // 2e. Play found results sequentially (shuffle: false)
        let ok = await playSearchResults(tracks: trackInfos, shuffle: false)
        return SearchAndPlayResult(success: ok, station: nil, query: q, count: trackInfos.count)
    }

    public func searchAndPlay(query: String) async -> Bool {
        let res = await searchAndPlayDetailed(query: query)
        return res.success
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
