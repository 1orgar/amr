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
        let expectedGen: UInt64 = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.playbackGeneration &+= 1
            PlaybackStateStore.shared.isStagingCloudTrack = false
            return PlaybackStateStore.shared.playbackGeneration
        }
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
        let isPersonalStationRequest = targetUrl == "ra.u-personal"
            || lowName.contains("моя станция")
            || lowName.contains("my station")
            || lowName.contains("персональная")
            || lowName.contains("personal station")
        let isDiscoveryStationRequest = targetUrl == "ra.u-discovery"
            || lowName.contains("открытий")
            || lowName.contains("discovery station")
            || lowName.contains("в моем вкусе")
            || lowName.contains("в моём вкусе")
        let isGenericOrMissingStationUrl = targetUrl.isEmpty
            || !targetUrl.contains("ra.")
            || targetUrl == "ra.u-personal"
            || targetUrl == "ra.u-discovery"
            || targetUrl.contains("ra.985480047")
            || targetUrl.contains("ra.985484943")

        if isPersonalStationRequest && isGenericOrMissingStationUrl {
            if let personal = await MusicKitManager.shared.fetchPersonalStation(), !personal.url.isEmpty {
                targetUrl = personal.url
            } else {
                return false
            }
        } else if isDiscoveryStationRequest && isGenericOrMissingStationUrl {
            let (_, discovery) = await MusicKitManager.shared.fetchPersonalStations()
            if let disc = discovery, !disc.url.isEmpty {
                targetUrl = disc.url
            } else {
                return false
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
        guard PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.playbackGeneration == expectedGen }) else {
            return false
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
        let stationGen: UInt64 = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isUserPaused = false
            PlaybackStateStore.shared.lastPlayerStatusCache = nil
            PlaybackStateStore.shared.latestUpcomingTracks.removeAll()
            PlaybackStateStore.shared.latestHistoryTracks.removeAll()
            PlaybackStateStore.shared.isShuffleQueueActive = false
            PlaybackStateStore.shared.activeShuffledQueue.removeAll()
            PlaybackStateStore.shared.activeShuffledPlaylistName = nil
            PlaybackStateStore.shared.playbackQueueCache = nil
            return PlaybackStateStore.shared.playbackGeneration
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
                    let shouldContinue = PlaybackStateStore.shared.withLock {
                        PlaybackStateStore.shared.playbackGeneration == stationGen &&
                        PlaybackStateStore.shared.isRadioPlayback &&
                        !PlaybackStateStore.shared.isUserPaused
                    }
                    if !shouldContinue {
                        break
                    }
                    PlaybackStateStore.shared.invalidateStatusCache()
                    let status = PlayerStatusEngine.shared.getPlayerStatus()
                    if status.playerState == "playing" {
                        PlaybackStateStore.shared.invalidateQueueCache()
                        PlaybackStateStore.shared.invalidateStatusCache()
                        WebSocketServer.shared.broadcastStatus(includeQueue: false)
                        break
                    }
                    if i == 15 && status.playerState != "playing" {
                        let stillValid = PlaybackStateStore.shared.withLock {
                            PlaybackStateStore.shared.playbackGeneration == stationGen &&
                            PlaybackStateStore.shared.isRadioPlayback &&
                            !PlaybackStateStore.shared.isUserPaused
                        }
                        if stillValid {
                            _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to play")
                        } else {
                            break
                        }
                    }
                }
            }
        }
        return ok
    }
}
