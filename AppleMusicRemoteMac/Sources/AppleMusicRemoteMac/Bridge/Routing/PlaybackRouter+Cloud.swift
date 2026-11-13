//
//  PlaybackRouter+Cloud.swift
//  AppleMusicRemoteMac
//

import Foundation
import AppKit

extension PlaybackRouter {
    // MARK: - Album Playback

    public func playAlbumWithTracks(tracks: [TrackInfo], name: String, artist: String, startIndex: Int = 0, shuffle: Bool = false) async -> Bool {
        guard !tracks.isEmpty else { return false }
        let qName = !name.isEmpty ? name : "Альбом"
        let validIdx = (startIndex >= 0 && startIndex < tracks.count) ? startIndex : 0
        return await playSearchResults(tracks: tracks, startIndex: validIdx, shuffle: shuffle, queueName: qName)
    }

    public func playAlbum(id: String, name: String, artist: String, startIndex: Int = 0, shuffle: Bool = false) async -> Bool {
        _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop")
        BitPerfectLogMonitor.shared.resetTrackState()
        let expectedGen: UInt64 = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.playbackGeneration &+= 1
            PlaybackStateStore.shared.isStagingCloudTrack = false
            PlaybackStateStore.shared.isRadioPlayback = false
            PlaybackStateStore.shared.activeStationName = nil
            PlaybackStateStore.shared.isCustomQueuePlayback = false
            return PlaybackStateStore.shared.playbackGeneration
        }
        PlaybackStateStore.shared.invalidateQueueCache()
        PlaybackStateStore.shared.invalidateStatusCache()

        let primaryStorefront = MusicKitManager.shared.getUserStorefront()
        let fallbackStorefront = (primaryStorefront == "us") ? "ru" : "us"
        var album = await CloudCatalogService.shared.getAlbumDetails(albumId: id, country: primaryStorefront)
        if album == nil || (album?.tracks?.isEmpty ?? true) {
            album = await CloudCatalogService.shared.getAlbumDetails(albumId: id, country: fallbackStorefront)
        }

        var albumTracks = album?.tracks ?? []
        if albumTracks.isEmpty && (!name.isEmpty || !artist.isEmpty) {
            albumTracks = await MusicKitManager.shared.getAlbumTracks(album: name, artist: artist, storefront: primaryStorefront)
            if albumTracks.isEmpty {
                albumTracks = await MusicKitManager.shared.getAlbumTracks(album: name, artist: artist, storefront: fallbackStorefront)
            }
        }

        guard PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.playbackGeneration == expectedGen }) else {
            return false
        }

        let qName = !name.isEmpty ? name : (album?.name ?? "Альбом")
        let validIdx = (startIndex >= 0 && startIndex < albumTracks.count) ? startIndex : 0

        if !albumTracks.isEmpty && MusicKitManager.shared.hasUserToken {
            return await playSearchResults(tracks: albumTracks, startIndex: validIdx, shuffle: shuffle, queueName: qName, incrementGeneration: false)
        }

        var targetUrl = !id.isEmpty ? "music://music.apple.com/album/\(id)" : ""
        if !targetUrl.isEmpty && validIdx > 0 && validIdx < albumTracks.count {
            let startTrack = albumTracks[validIdx]
            let cleanId = startTrack.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanId.isEmpty && Int(cleanId) != nil {
                targetUrl += "?i=\(cleanId)"
            }
        }

        if !targetUrl.isEmpty, openMusicUrl(targetUrl) {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.playbackGeneration == expectedGen }) else {
                return false
            }
            _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to play")
            if !albumTracks.isEmpty {
                PlaybackStateStore.shared.withLock {
                    if PlaybackStateStore.shared.playbackGeneration == expectedGen {
                        var formattedTracks = [TrackInfo]()
                        for (idx, var t) in albumTracks.enumerated() {
                            t.index = idx + 1
                            formattedTracks.append(t)
                        }
                        PlaybackStateStore.shared.originalCustomQueue = formattedTracks
                        PlaybackStateStore.shared.activeCustomQueue = formattedTracks
                        PlaybackStateStore.shared.activeCustomQueueIndex = validIdx
                        PlaybackStateStore.shared.activeCustomQueueName = qName
                        PlaybackStateStore.shared.isCustomQueuePlayback = true
                        PlaybackStateStore.shared.currentOriginalPlaylistName = qName
                        PlaybackStateStore.shared.activeSearchQuery = nil
                        PlaybackStateStore.shared.activeSearchOffset = 0
                        PlaybackStateStore.shared.isFetchingNextSearchPage = false
                        PlaybackStateStore.shared.activeCuratorPrompt = nil
                        PlaybackStateStore.shared.isFetchingNextCuratorPage = false
                        PlaybackStateStore.shared.isShuffleQueueActive = false
                        PlaybackStateStore.shared.activeShuffledQueue.removeAll()
                        PlaybackStateStore.shared.lastCloudPlayTime = Date()
                        PlaybackStateStore.shared.lastSkipTime = Date()
                        PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
                        PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
                        PlaybackStateStore.shared.lastKnownPosition = 0.0
                        if validIdx + 1 < formattedTracks.count {
                            PlaybackStateStore.shared.latestUpcomingTracks = Array(formattedTracks[(validIdx + 1)...])
                        } else {
                            PlaybackStateStore.shared.latestUpcomingTracks = []
                        }
                        if validIdx > 0 {
                            PlaybackStateStore.shared.latestHistoryTracks = Array(formattedTracks[0..<validIdx].reversed())
                        } else {
                            PlaybackStateStore.shared.latestHistoryTracks = []
                        }
                    }
                }
                QueueManager.shared.startQueueMonitoring()
            }
            PlaybackStateStore.shared.invalidateQueueCache()
            PlaybackStateStore.shared.invalidateStatusCache()
            WebSocketServer.shared.broadcastStatus(includeQueue: true)
            return true
        }

        if !albumTracks.isEmpty {
            let startTrack = albumTracks[validIdx]
            let cloudOk = await playCloud(url: startTrack.url, id: startTrack.id, name: startTrack.name, artist: startTrack.artist, numericId: startTrack.numericId, incrementGeneration: false)
            if cloudOk {
                PlaybackStateStore.shared.withLock {
                    if PlaybackStateStore.shared.playbackGeneration == expectedGen {
                        var formattedTracks = [TrackInfo]()
                        for (idx, var t) in albumTracks.enumerated() {
                            t.index = idx + 1
                            formattedTracks.append(t)
                        }
                        PlaybackStateStore.shared.originalCustomQueue = formattedTracks
                        PlaybackStateStore.shared.activeCustomQueue = formattedTracks
                        PlaybackStateStore.shared.activeCustomQueueIndex = validIdx
                        PlaybackStateStore.shared.activeCustomQueueName = qName
                        PlaybackStateStore.shared.isCustomQueuePlayback = true
                        PlaybackStateStore.shared.currentOriginalPlaylistName = qName
                        PlaybackStateStore.shared.activeSearchQuery = nil
                        PlaybackStateStore.shared.activeSearchOffset = 0
                        PlaybackStateStore.shared.isFetchingNextSearchPage = false
                        PlaybackStateStore.shared.activeCuratorPrompt = nil
                        PlaybackStateStore.shared.isFetchingNextCuratorPage = false
                        PlaybackStateStore.shared.isShuffleQueueActive = false
                        PlaybackStateStore.shared.activeShuffledQueue.removeAll()
                        PlaybackStateStore.shared.lastCloudPlayTime = Date()
                        PlaybackStateStore.shared.lastSkipTime = Date()
                        PlaybackStateStore.shared.currentTrackPlaybackConfirmed = false
                        PlaybackStateStore.shared.hasTriggeredAdvanceForCurrentTrack = false
                        PlaybackStateStore.shared.lastKnownPosition = 0.0
                        if validIdx + 1 < formattedTracks.count {
                            PlaybackStateStore.shared.latestUpcomingTracks = Array(formattedTracks[(validIdx + 1)...])
                        } else {
                            PlaybackStateStore.shared.latestUpcomingTracks = []
                        }
                        if validIdx > 0 {
                            PlaybackStateStore.shared.latestHistoryTracks = Array(formattedTracks[0..<validIdx].reversed())
                        } else {
                            PlaybackStateStore.shared.latestHistoryTracks = []
                        }
                    }
                }
                QueueManager.shared.startQueueMonitoring()
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
                return true
            }
        }

        return false
    }

    // MARK: - Hero Card Playback

    public func playHeroCard(index: Int, name: String, artist: String? = nil, cardId: String?, url: String?, type: String? = nil) async -> Bool {
        BitPerfectLogMonitor.shared.resetTrackState()
        var expectedGen: UInt64 = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.playbackGeneration
        }

        let isStation = (type == "station") || (cardId?.hasPrefix("ra.") == true) || name.lowercased().contains("станция")
        var targetUrl = url ?? ""
        var actualCardId = cardId ?? ""
        let art = artist ?? ""

        let lowName = name.lowercased()
        let isPersonalCard = targetUrl.contains("ra.u-personal")
            || actualCardId == "station_personal"
            || lowName.contains("моя станция")
            || lowName.contains("my station")
            || lowName.contains("персональная")
            || lowName.contains("personal station")
        let isDiscoveryCard = targetUrl.contains("ra.u-discovery")
            || actualCardId == "station_discovery"
            || lowName.contains("открытий")
            || lowName.contains("discovery station")
            || lowName.contains("в моем вкусе")
            || lowName.contains("в моём вкусе")
        let isGenericOrMissingUrl = targetUrl.isEmpty
            || !targetUrl.contains("ra.")
            || targetUrl.contains("ra.u-personal")
            || targetUrl.contains("ra.u-discovery")
            || targetUrl.contains("ra.985480047")
            || targetUrl.contains("ra.985484943")

        if isPersonalCard && isGenericOrMissingUrl {
            if let personal = await MusicKitManager.shared.fetchPersonalStation(), !personal.url.isEmpty {
                actualCardId = personal.id
                targetUrl = personal.url
            } else {
                targetUrl = ""
            }
        } else if isDiscoveryCard && isGenericOrMissingUrl {
            let (_, discovery) = await MusicKitManager.shared.fetchPersonalStations()
            if let disc = discovery, !disc.url.isEmpty {
                actualCardId = disc.id
                targetUrl = disc.url
            } else {
                targetUrl = ""
            }
        } else if targetUrl.isEmpty && actualCardId.hasPrefix("ra.") {
            targetUrl = "music://music.apple.com/station/\(actualCardId)"
        }

        guard PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.playbackGeneration == expectedGen }) else {
            return false
        }

        if isStation || isPersonalCard || isDiscoveryCard {
            let isGenericName = name.isEmpty || lowName == "apple music"
            let lowArt = art.lowercased()
            let isSubtitleGeneric = lowArt.contains("персональная радиостанция") || lowArt.contains("personal station")
            let stationName = (!isGenericName || isSubtitleGeneric || art.isEmpty) ? (!name.isEmpty ? name : art) : art
            return await playStation(url: targetUrl, name: stationName)
        }

        let isPlaylistCard = type == "playlist" || actualCardId.hasPrefix("pl.") || actualCardId.hasPrefix("p.") || actualCardId == "replay_playlist" || actualCardId == "favorites_mix" || name.lowercased().contains("replay") || name.lowercased().contains("итоги") || name.lowercased().contains("в моём вкусе") || name.lowercased().contains("в моем вкусе") || name.lowercased().contains("essentials") || name.lowercased().contains("повторе") || name.lowercased().contains("heavy rotation") || name.lowercased().contains("микс") || name.lowercased().contains("mix")

        if isPlaylistCard {
            let plName = !name.isEmpty ? name : actualCardId
            let lowerPl = plName.lowercased()
            let localPlaylists = LibraryService.shared.getPlaylists()

            // 1. Try local playlist in Music.app (matches exact name or localized alias like "Мои любимые треки" for Essentials)
            let isEssentials = lowerPl.contains("essentials") || lowerPl.contains("любимые") || lowerPl.contains("favorites") || actualCardId == "favorites_mix"
            if let matched = localPlaylists.first(where: {
                let n = $0.name.lowercased()
                if n == lowerPl { return true }
                if isEssentials && (n == "мои любимые треки" || n.contains("любимые треки")) { return true }
                return false
            }) {
                let localOk = playPlaylist(name: matched.name, trackId: nil, trackIndex: nil, shuffle: false)
                if localOk {
                    PlaybackStateStore.shared.invalidateQueueCache()
                    PlaybackStateStore.shared.invalidateStatusCache()
                    WebSocketServer.shared.broadcastStatus(includeQueue: true)
                    return true
                }
                expectedGen = PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.playbackGeneration
                }
            }

            // Direct Apple Music cloud playlist resolution
            var targetPlId = actualCardId
            if !targetPlId.hasPrefix("pl.") && !targetPlId.hasPrefix("p.") {
                if let mixes = MusicKitManager.shared.getCachedPersonalData()?.mixes,
                   let found = mixes.first(where: {
                       let n = $0.name.lowercased()
                       if n == lowerPl { return true }
                       if (lowerPl.contains("повторе") || lowerPl.contains("heavy rotation")) && (n.contains("повторе") || n.contains("heavy rotation")) { return true }
                       if (lowerPl.contains("в моём вкусе") || lowerPl.contains("в моем вкусе") || lowerPl.contains("essentials") || lowerPl.contains("favorites")) && (n.contains("в моём вкусе") || n.contains("в моем вкусе") || n.contains("favorites") || n.contains("избранн")) { return true }
                       if (lowerPl.contains("chill") || lowerPl.contains("чилл")) && (n.contains("chill") || n.contains("чилл")) { return true }
                       if (lowerPl.contains("new music") || lowerPl.contains("новинк")) && (n.contains("new music") || n.contains("новинк")) { return true }
                       if (lowerPl.contains("get up") || lowerPl.contains("энерги")) && (n.contains("get up") || n.contains("энерги")) { return true }
                       return false
                   })?.id {
                    targetPlId = found
                }
            }

            var plTracks = [TrackInfo]()
            if actualCardId == "replay_playlist" || lowerPl.contains("replay") || lowerPl.contains("итоги") {
                plTracks = await MusicKitManager.shared.getPersonalizedReplayTracks()
            } else if !targetPlId.isEmpty && (targetPlId.hasPrefix("pl.") || targetPlId.hasPrefix("p.")) {
                plTracks = await MusicKitManager.shared.getPlaylistTracksById(playlistId: targetPlId)
            }
            if plTracks.isEmpty {
                let mixes = await MusicKitManager.shared.fetchPersonalMixes()
                if let m = mixes.first(where: {
                    let n = $0.name.lowercased()
                    if n == lowerPl { return true }
                    if (lowerPl.contains("повторе") || lowerPl.contains("heavy rotation")) && (n.contains("повторе") || n.contains("heavy rotation")) { return true }
                    if (lowerPl.contains("в моём вкусе") || lowerPl.contains("в моем вкусе") || lowerPl.contains("essentials") || lowerPl.contains("favorites")) && (n.contains("в моём вкусе") || n.contains("в моем вкусе") || n.contains("favorites") || n.contains("избранн")) { return true }
                    if (lowerPl.contains("chill") || lowerPl.contains("чилл")) && (n.contains("chill") || n.contains("чилл")) { return true }
                    if (lowerPl.contains("new music") || lowerPl.contains("новинк")) && (n.contains("new music") || n.contains("новинк")) { return true }
                    if (lowerPl.contains("get up") || lowerPl.contains("энерги")) && (n.contains("get up") || n.contains("энерги")) { return true }
                    return false
                }), let mid = m.id, !mid.isEmpty {
                    plTracks = await MusicKitManager.shared.getPlaylistTracksById(playlistId: mid)
                }
            }
            guard PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.playbackGeneration == expectedGen }) else {
                return false
            }
            // Fallback for Heavy Rotation / В моем вкусе if API unauthenticated or offline
            if plTracks.isEmpty && (lowerPl.contains("повторе") || lowerPl.contains("heavy rotation")) {
                plTracks = MusicBridge.shared.getRecentlyPlayed(limit: 50)
                if plTracks.isEmpty {
                    plTracks = Array(LibraryService.shared.getLibrarySongs().prefix(50))
                }
            }
            if plTracks.isEmpty && (lowerPl.contains("в моём вкусе") || lowerPl.contains("в моем вкусе") || lowerPl.contains("essentials")) {
                plTracks = LibraryService.shared.getPlaylistTracks(name: "Любимые песни")
                if plTracks.isEmpty {
                    plTracks = LibraryService.shared.getPlaylistTracks(name: "Favorites")
                }
                if plTracks.isEmpty {
                    plTracks = Array(LibraryService.shared.getLibrarySongs().prefix(50))
                }
            }
            if plTracks.isEmpty && self.isTestingEnvironment {
                plTracks = [TrackInfo(id: actualCardId.isEmpty ? "test_pl_1" : actualCardId, name: plName, artist: art.isEmpty ? "Apple Music" : art, isLocal: false, url: targetUrl)]
            }

            if !plTracks.isEmpty {
                if MusicKitManager.shared.hasUserToken {
                    return await playSearchResults(tracks: plTracks, startIndex: 0, shuffle: false, queueName: plName)
                } else {
                    return playCustomTracks(plTracks, startIndex: 0, shuffle: false, queueName: plName)
                }
            }

            // Fallback to local playlist if local playlist exists with this name
            if localPlaylists.contains(where: { $0.name.lowercased() == plName.lowercased() }) {
                let localOk = playPlaylist(name: plName, trackId: nil, trackIndex: nil, shuffle: false)
                if localOk {
                    PlaybackStateStore.shared.invalidateQueueCache()
                    PlaybackStateStore.shared.invalidateStatusCache()
                    WebSocketServer.shared.broadcastStatus(includeQueue: true)
                    return true
                }
            }
            return false
        }

        if type == "album" || (!actualCardId.isEmpty && !actualCardId.hasPrefix("ra.") && !actualCardId.hasPrefix("pl.")) {
            let genBeforeAlbum = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.playbackGeneration }
            if await playAlbum(id: actualCardId, name: name, artist: art, shuffle: false) {
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
                return true
            }
            guard PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.playbackGeneration == genBeforeAlbum &+ 1 }) else {
                return false
            }
            expectedGen = genBeforeAlbum &+ 1
        }

        let cleanQuery = name
            .replacingOccurrences(of: " - Single", with: "")
            .replacingOccurrences(of: " - EP", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.playbackGeneration == expectedGen }) else {
            return false
        }

        let primarySearch = await searchAndPlayDetailed(query: cleanQuery)
        expectedGen = primarySearch.expectedGeneration
        if primarySearch.success {
            let genAfterSearch = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.playbackGeneration }
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.playbackGeneration == genAfterSearch }) else {
                return false
            }
            _ = syncCurrentTrackToAMRQueue(clearQueue: true)
            PlaybackStateStore.shared.invalidateQueueCache()
            PlaybackStateStore.shared.invalidateStatusCache()
            WebSocketServer.shared.broadcastStatus(includeQueue: true)
            return true
        }
        guard PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.playbackGeneration == expectedGen }) else {
            return false
        }
        if cleanQuery.hasSuffix("s") || cleanQuery.hasSuffix("S") {
            let singular = String(cleanQuery.dropLast())
            let singularSearch = await searchAndPlayDetailed(query: singular)
            expectedGen = singularSearch.expectedGeneration
            if singularSearch.success {
                let genAfterSearch = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.playbackGeneration }
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.playbackGeneration == genAfterSearch }) else {
                    return false
                }
                _ = syncCurrentTrackToAMRQueue(clearQueue: true)
                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
                return true
            }
            guard PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.playbackGeneration == expectedGen }) else {
                return false
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

        let launchGen: UInt64 = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isRadioPlayback = false
            PlaybackStateStore.shared.activeStationName = nil
            PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
            PlaybackStateStore.shared.activeCustomQueueName = "Очередь AMR"
            return PlaybackStateStore.shared.playbackGeneration
        }

        var launched = false
        if !targetUrl.isEmpty {
            if openMusicUrl(targetUrl) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.playbackGeneration == launchGen }) else {
                    return false
                }
                _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to play")
                launched = true
            }
        }

        guard launched else { return false }

        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.playbackGeneration == launchGen }) else {
            return false
        }
        _ = syncCurrentTrackToAMRQueue(clearQueue: true)
        PlaybackStateStore.shared.invalidateQueueCache()
        PlaybackStateStore.shared.invalidateStatusCache()
        WebSocketServer.shared.broadcastStatus(includeQueue: true)
        return true
    }

    // MARK: - Cloud Track Playback

    public func playCloud(url: String?, id: String?, name: String?, artist: String?, numericId: Int? = nil, isLocal: Bool? = nil, incrementGeneration: Bool = true) async -> Bool {
        _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop")
        BitPerfectLogMonitor.shared.resetTrackState()
        PlaybackStateStore.shared.withLock {
            if incrementGeneration {
                PlaybackStateStore.shared.playbackGeneration &+= 1
            }
            PlaybackStateStore.shared.isStagingCloudTrack = false
            PlaybackStateStore.shared.isRadioPlayback = false
            PlaybackStateStore.shared.activeStationName = nil
        }

        let numId = (isLocal == true) ? (numericId ?? (Int(id ?? "") ?? 0)) : 0

        if isTestingEnvironment {
            let inMultiTrackQueue = PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.isCustomQueuePlayback && PlaybackStateStore.shared.activeCustomQueue.count > 1
            }
            if !inMultiTrackQueue {
                let actualId = numId > 0 ? numId : 1
                let tInfo = TrackInfo(
                    id: "\(actualId)",
                    numericId: actualId,
                    name: name ?? "Test",
                    artist: artist ?? "Test",
                    album: "",
                    duration: 180,
                    hasArtwork: false,
                    artworkUrl: "",
                    favorited: false,
                    isLocal: isLocal ?? false,
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
            }
            PlaybackStateStore.shared.invalidateQueueCache()
            PlaybackStateStore.shared.invalidateStatusCache()
            return true
        }

        // 1. If explicitly marked local library track, play directly via "play foundTrack once true"
        if numId > 0 && isLocal == true {
            let script = """
            tell application "Music"
                stop
                set foundTrack to missing value
                try
                    set foundTrack to (first track of library playlist 1 whose database ID is \(numId))
                end try
                if foundTrack is missing value then
                    try
                        set foundTrack to (first track whose database ID is \(numId))
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
                    set actualDbId to (database ID of foundTrack as integer)
                    set actualName to (name of foundTrack as string)
                    set actualArtist to (artist of foundTrack as string)
                    set actualAlbum to (album of foundTrack as string)
                    set actualDur to (duration of foundTrack as real)
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
                    let inMultiTrackQueue = PlaybackStateStore.shared.isCustomQueuePlayback && PlaybackStateStore.shared.activeCustomQueue.count > 1
                    if !inMultiTrackQueue {
                        PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                        PlaybackStateStore.shared.activeCustomQueueName = "Очередь AMR"
                        PlaybackStateStore.shared.isCustomQueuePlayback = true
                        PlaybackStateStore.shared.activeCustomQueue = [tInfo]
                        PlaybackStateStore.shared.activeCustomQueueIndex = 0
                        PlaybackStateStore.shared.isShuffleQueueActive = false
                        PlaybackStateStore.shared.activeShuffledQueue.removeAll()
                        PlaybackStateStore.shared.activeShuffledPlaylistName = nil
                    }
                }

                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
                return true
            }
        }

        // 2. Cloud Track Playback (Apple Music catalog track NOT in local library)
        var targetUrl = ""
        var catalogSongId: String? = nil
        if let u = url, let comp = URLComponents(string: u), let qi = comp.queryItems?.first(where: { $0.name == "i" })?.value, let n = Int(qi), n > 0 {
            catalogSongId = qi
        } else if let rawId = id, let n = Int(rawId), n >= 10_000_000 {
            catalogSongId = rawId
        } else if let rawId = id, let n = Int(rawId), n > 0, (url == nil || url?.isEmpty == true) {
            catalogSongId = rawId
        }


        // 2b. Prefer native Cloud Queue playback if user token is present, otherwise station/direct URL
        if let sId = catalogSongId {
            if !isTestingEnvironment && MusicKitManager.shared.hasUserToken {
                let singleTrack = TrackInfo(
                    id: sId,
                    numericId: nil,
                    name: name ?? "",
                    artist: artist ?? "",
                    album: "",
                    duration: 0,
                    hasArtwork: false,
                    artworkUrl: "",
                    favorited: false,
                    isLocal: false,
                    url: url,
                    index: 1
                )
                return await playSearchResults(tracks: [singleTrack], startIndex: 0, shuffle: false, queueName: name ?? "Очередь AMR", incrementGeneration: false)
            }
            targetUrl = "music://music.apple.com/station/item/ra.\(sId)"
        } else if !isTestingEnvironment && MusicKitManager.shared.hasUserToken, let n = name, !n.isEmpty {
            let singleTrack = TrackInfo(
                id: id ?? "cloud",
                numericId: nil,
                name: n,
                artist: artist ?? "",
                album: "",
                duration: 0,
                hasArtwork: false,
                artworkUrl: "",
                favorited: false,
                isLocal: false,
                url: url,
                index: 1
            )
            return await playSearchResults(tracks: [singleTrack], startIndex: 0, shuffle: false, queueName: n, incrementGeneration: false)
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
                        PlaybackStateStore.shared.isRadioPlayback = false
                        PlaybackStateStore.shared.activeStationName = nil
                    }
                }
                QueueManager.shared.startQueueMonitoring()

                PlaybackStateStore.shared.invalidateQueueCache()
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
                return true
            }
        }

        return false
    }

    public func playCloudSync(url: String?, id: String?, name: String?, artist: String?) -> Bool {
        stopAndClearAMRQueue()
        let (inMultiQueue, gen) = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isStagingCloudTrack = true
            return (
                PlaybackStateStore.shared.isCustomQueuePlayback && PlaybackStateStore.shared.activeCustomQueue.count > 1,
                PlaybackStateStore.shared.playbackGeneration
            )
        }
        defer {
            PlaybackStateStore.shared.withLock {
                if PlaybackStateStore.shared.playbackGeneration == gen {
                    PlaybackStateStore.shared.isStagingCloudTrack = false
                }
            }
        }
        if !inMultiQueue {
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.isRadioPlayback = false
                PlaybackStateStore.shared.activeStationName = nil
            }
        }

        // 0. If user token is available, stage the exact catalog track into Music.app and play via "Очередь AMR"
        if !isTestingEnvironment && urlOpener == nil && MusicKitManager.shared.hasUserToken {
            if let dbId = MusicKitManager.shared.stageAndResolveCloudTrackInLibrarySync(
                id: id,
                url: url,
                name: name ?? "",
                artist: artist ?? "",
                timeout: 9.0,
                expectedGeneration: gen
            ), dbId > 0 {
                let stillValid = PlaybackStateStore.shared.withLock { () -> Bool in
                    if PlaybackStateStore.shared.playbackGeneration != gen {
                        return false
                    }
                    let idx = PlaybackStateStore.shared.activeCustomQueueIndex
                    if idx >= 0 && idx < PlaybackStateStore.shared.activeCustomQueue.count {
                        PlaybackStateStore.shared.activeCustomQueue[idx].numericId = dbId
                        PlaybackStateStore.shared.activeCustomQueue[idx].isLocal = true
                    }
                    return true
                }
                guard stillValid else { return false }
                if playTrackByDatabaseIdViaAMRQueue(dbId, generation: gen) {
                    let now = Date()
                    PlaybackStateStore.shared.withLock {
                        if PlaybackStateStore.shared.playbackGeneration == gen {
                            PlaybackStateStore.shared.lastCloudPlayTime = now
                            PlaybackStateStore.shared.lastSkipTime = now
                            PlaybackStateStore.shared.lastWasPlayingCloud = true
                            PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                        }
                    }
                    PlaybackStateStore.shared.invalidateQueueCache()
                    PlaybackStateStore.shared.invalidateStatusCache()
                    return true
                }
            }
        }

        let isGenValid = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.playbackGeneration == gen }
        guard isGenValid else { return false }

        // 0b. Before falling back to URL opening, check if track is now findable in Music.app by name/artist and play via "Очередь AMR"
        if !isTestingEnvironment && urlOpener == nil, let n = name, !n.isEmpty {
            if let fallbackDbId = MusicKitManager.shared.findTrackDatabaseIdInMusicApp(name: n, artist: artist ?? ""), fallbackDbId > 0 {
                if playTrackByDatabaseIdViaAMRQueue(fallbackDbId, generation: gen) {
                    let now = Date()
                    PlaybackStateStore.shared.withLock {
                        let idx = PlaybackStateStore.shared.activeCustomQueueIndex
                        if idx >= 0 && idx < PlaybackStateStore.shared.activeCustomQueue.count {
                            PlaybackStateStore.shared.activeCustomQueue[idx].numericId = fallbackDbId
                            PlaybackStateStore.shared.activeCustomQueue[idx].isLocal = true
                        }
                        PlaybackStateStore.shared.lastCloudPlayTime = now
                        PlaybackStateStore.shared.lastSkipTime = now
                        PlaybackStateStore.shared.lastWasPlayingCloud = true
                        PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                    }
                    PlaybackStateStore.shared.invalidateQueueCache()
                    PlaybackStateStore.shared.invalidateStatusCache()
                    return true
                }
            }
        }

        // 1. In mock/testing environment, open direct URL if provided
        if isTestingEnvironment || urlOpener != nil {
            if let u = url, !u.isEmpty {
                var directUrl = u
                if directUrl.hasPrefix("https://music.apple.com") {
                    directUrl = "music://" + directUrl.dropFirst("https://".count)
                }
                if openMusicUrl(directUrl) {
                    resumePlaybackIfNeeded(generation: gen)
                    PlaybackStateStore.shared.invalidateQueueCache()
                    PlaybackStateStore.shared.invalidateStatusCache()
                    return true
                }
            }
            if (url == nil || url?.isEmpty == true), let sId = id, Int(sId) != nil {
                let sf = MusicKitManager.shared.getUserStorefront()
                let synthUrl = "music://music.apple.com/\(sf)/album/_?i=\(sId)"
                if openMusicUrl(synthUrl) {
                    resumePlaybackIfNeeded(generation: gen)
                    PlaybackStateStore.shared.invalidateQueueCache()
                    PlaybackStateStore.shared.invalidateStatusCache()
                    return true
                }
            }
        }

        // 2. Search local library by name & artist and play directly via once=true
        if let n = name, !n.isEmpty {
            let a = artist ?? ""
            let escN = n.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let escA = a.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let searchScript = """
            tell application "Music"
              try
                set foundTrack to missing value
                try
                  set foundTrack to (first track of library playlist 1 whose name is "\(escN)" and artist is "\(escA)")
                end try
                if foundTrack is missing value then
                  try
                    set foundTrack to (first track of library playlist 1 whose name is "\(escN)")
                  end try
                end if
                if foundTrack is not missing value then
                  set dbId to (database ID of foundTrack as integer)
                  return (dbId as string)
                end if
              end try
              return "not_found"
            end tell
            """
            let (ok, res) = AppleScriptExecutor.shared.execute(searchScript)
            if ok, let out = res?.trimmingCharacters(in: .whitespacesAndNewlines), let foundDbId = Int(out), foundDbId > 0 {
                if playTrackByDatabaseIdViaAMRQueue(foundDbId, generation: gen) {
                    PlaybackStateStore.shared.withLock {
                        PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                    }
                    PlaybackStateStore.shared.invalidateQueueCache()
                    PlaybackStateStore.shared.invalidateStatusCache()
                    return true
                }
            }
        }

        // 3. Fallback in production: NEVER open music://.../album/... (which opens the Album UI without playing).
        // Instead, use track station seed ra.<songId> or cached track station to start immediate audio playback.
        if !isTestingEnvironment && urlOpener == nil {
            var songId: String? = nil
            if let u = url, let comp = URLComponents(string: u),
               let qi = comp.queryItems?.first(where: { $0.name == "i" })?.value,
               let num = Int(qi), num > 0 {
                songId = qi
            } else if let rawId = id, let num = Int(rawId), num > 0 {
                songId = rawId
            }
            if let sId = songId {
                let stationUrl = "music://music.apple.com/station/item/ra.\(sId)"
                if openMusicUrl(stationUrl) {
                    PlaybackStateStore.shared.withLock {
                        if PlaybackStateStore.shared.currentOriginalPlaylistName == "Очередь AMR" {
                            PlaybackStateStore.shared.currentOriginalPlaylistName = nil
                        }
                    }
                    resumePlaybackIfNeeded(generation: gen)
                    PlaybackStateStore.shared.invalidateQueueCache()
                    PlaybackStateStore.shared.invalidateStatusCache()
                    return true
                }
            }
            if let n = name, let a = artist, !n.isEmpty, !a.isEmpty {
                let cacheKey = "\(n.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(a.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
                if let cached = MusicKitManager.shared.getCachedTrackStation(for: cacheKey), !cached.stationUrl.isEmpty {
                    if openMusicUrl(cached.stationUrl) {
                        PlaybackStateStore.shared.withLock {
                            if PlaybackStateStore.shared.currentOriginalPlaylistName == "Очередь AMR" {
                                PlaybackStateStore.shared.currentOriginalPlaylistName = nil
                            }
                        }
                        resumePlaybackIfNeeded(generation: gen)
                        PlaybackStateStore.shared.invalidateQueueCache()
                        PlaybackStateStore.shared.invalidateStatusCache()
                        return true
                    }
                }
            }
        }

        return false
    }
}
