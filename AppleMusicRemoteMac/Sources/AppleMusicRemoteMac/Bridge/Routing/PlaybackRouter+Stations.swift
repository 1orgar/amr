//
//  PlaybackRouter+Stations.swift
//  AppleMusicRemoteMac
//

import Foundation
import AppKit

extension PlaybackRouter {
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
            if !targetUrl.isEmpty && (targetUrl.contains("playlist") || targetUrl.contains("pl.")) {
                if openMusicUrl(targetUrl) {
                    _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to play")
                    return true
                }
            }
            return playPlaylist(name: "Сейчас на повторе", trackId: nil, trackIndex: nil, shuffle: true)
        }
        if (targetUrl.isEmpty || targetUrl == "ra.u-personal") && (name.contains("Моя станция") || lowName.contains("моя станция")) {
            if let personal = await MusicKitManager.shared.fetchPersonalStation(), !personal.url.isEmpty {
                targetUrl = personal.url
            } else {
                targetUrl = "https://music.apple.com/station/my-station/ra.u-96b95a031a2fb0aa1abb70ff757aa95f"
            }
        } else if (targetUrl.isEmpty || targetUrl == "ra.u-discovery") && (name.contains("открытий") || name.contains("В моем вкусе") || lowName.contains("станция открытий")) {
            let (_, discovery) = await MusicKitManager.shared.fetchPersonalStations()
            if let disc = discovery, !disc.url.isEmpty {
                targetUrl = disc.url
            } else {
                targetUrl = "https://music.apple.com/station/item/ra.q-GAI6IDk2Yjk1YTAzMWEyZmIwYWExYWJiNzBmZjc1N2FhOTVm"
            }
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
                QueueManager.shared.stopQueueMonitoring()
                PlaybackStateStore.shared.resetPlaybackState(isRadio: true, stationName: "Станция «\(t)»")
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.isUserPaused = false
                    PlaybackStateStore.shared.lastPlayerStatusCache = nil
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
        QueueManager.shared.stopQueueMonitoring()
        let resolvedStationName = !stationDisplayName.isEmpty ? stationDisplayName : (!name.isEmpty ? name : "Apple Music Radio")
        PlaybackStateStore.shared.resetPlaybackState(isRadio: true, stationName: resolvedStationName)
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isUserPaused = false
            PlaybackStateStore.shared.lastPlayerStatusCache = nil
            PlaybackStateStore.shared.latestUpcomingTracks.removeAll()
            PlaybackStateStore.shared.latestHistoryTracks.removeAll()
            PlaybackStateStore.shared.isShuffleQueueActive = false
            PlaybackStateStore.shared.activeShuffledQueue.removeAll()
            PlaybackStateStore.shared.activeShuffledPlaylistName = nil
            PlaybackStateStore.shared.playbackQueueCache = nil
        }
        PlaybackStateStore.shared.invalidateStatusCache()

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
            QueueManager.shared.stopQueueMonitoring()
            // Fast polling loop to broadcast status the instant radio playback begins (eliminates lag)
            Task.detached(priority: .userInitiated) {
                for i in 0..<40 {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    PlaybackStateStore.shared.invalidateStatusCache()
                    let status = PlayerStatusEngine.shared.getPlayerStatus()
                    if status.playerState == "playing" {
                        PlaybackStateStore.shared.invalidateQueueCache()
                        PlaybackStateStore.shared.invalidateStatusCache()
                        WebSocketServer.shared.broadcastStatus(includeQueue: false)
                        break
                    }
                    if i == 15 && status.playerState != "playing" {
                        _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to play")
                    }
                }
            }
        }
        return ok
    }
}
