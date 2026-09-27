//
//  PlayerStatusEngine.swift
//  AppleMusicRemoteMac
//
//  Aggregates player status from Music.app ScriptingBridge, active custom queues,
//  radio playback, optimistic seek compensation, and real-time audio quality.
//

import Foundation
import ScriptingBridge

public final class PlayerStatusEngine: @unchecked Sendable {
    public static let shared = PlayerStatusEngine()

    private let statusLock = NSLock()

    private init() {}

    public func computeOptimisticPosition(rawPosition: Double, isPlaying: Bool, duration: Double) -> Double {
        let (targetPos, targetDate) = PlaybackStateStore.shared.withLock {
            (PlaybackStateStore.shared.seekTargetPosition, PlaybackStateStore.shared.seekTargetDate)
        }

        guard let target = targetPos, Date().timeIntervalSince(targetDate) < 4.0 else {
            return rawPosition
        }

        let elapsed = isPlaying ? Date().timeIntervalSince(targetDate) : 0.0
        let expected = target + elapsed

        // If Music.app's internal position has caught up within 1.2 seconds of target
        if abs(rawPosition - expected) < 1.2 {
            PlaybackStateStore.shared.clearSeekTarget()
            return rawPosition
        }

        return min(expected, duration > 0 ? duration : expected)
    }

    public func getPlayerStatus() -> PlayerStatus {
        let cached = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastPlayerStatusCache
        }
        if let cached = cached, Date().timeIntervalSince(cached.timestamp) < 0.25 {
            return cached.status
        }

        guard statusLock.lock(before: Date().addingTimeInterval(1.0)) else {
            if let cached = PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.lastPlayerStatusCache }) {
                return cached.status
            }
            return PlayerStatus()
        }
        defer { statusLock.unlock() }

        let (isRadio, stationName, isCustom, customQueue, customIndex, customName, isShufActive, origPl) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isRadioPlayback,
                PlaybackStateStore.shared.activeStationName,
                PlaybackStateStore.shared.isCustomQueuePlayback,
                PlaybackStateStore.shared.activeCustomQueue,
                PlaybackStateStore.shared.activeCustomQueueIndex,
                PlaybackStateStore.shared.activeCustomQueueName,
                PlaybackStateStore.shared.isShuffleQueueActive,
                PlaybackStateStore.shared.currentOriginalPlaylistName
            )
        }

        guard let app = MusicAppProvider.shared.getMusicApp() else {
            return PlayerStatus()
        }

        // 1. Radio / Station Playback Mode
        if isRadio {
            let pState = app.playerState
            let stateStr = (pState == .playing) ? "playing" : ((pState == .paused) ? "paused" : "stopped")
            let curTrack = app.currentTrack
            let tName = (curTrack?.value(forKey: "name") as? String) ?? (stationName ?? "Apple Music Radio")
            let tArtist = (curTrack?.value(forKey: "artist") as? String) ?? "Apple Music"
            let tAlbum = (curTrack?.value(forKey: "album") as? String) ?? ""
            let dur = (curTrack?.value(forKey: "duration") as? Double) ?? 0
            let pos = computeOptimisticPosition(rawPosition: app.playerPosition, isPlaying: (pState == .playing), duration: dur)

            var hasArt = false
            if let arts = curTrack?.value(forKey: "artworks") as? SBElementArray, arts.count > 0 {
                hasArt = true
            }

            let dbId = (curTrack?.value(forKey: "databaseID") as? Int) ?? 0
            var artUrl = hasArt ? (dbId > 0 ? "/api/artwork/track?id=\(dbId)" : "/api/artwork") : ""
            if artUrl.isEmpty {
                if let local = ArtworkService.shared.findLocalTrackArtwork(name: tName, artist: tArtist) {
                    artUrl = local
                    hasArt = true
                } else if let cached = MusicKitManager.shared.getCachedTrackArtwork(name: tName, artist: tArtist, album: tAlbum), !cached.isEmpty {
                    artUrl = cached
                    hasArt = true
                } else {
                    Task.detached(priority: .utility) {
                        if let fetched = await MusicKitManager.shared.searchTrackArtwork(name: tName, artist: tArtist, album: tAlbum), !fetched.isEmpty {
                            WebSocketServer.shared.broadcastStatus(includeQueue: false)
                        }
                    }
                }
            }

            let track = TrackInfo(
                id: "\(dbId)",
                numericId: dbId,
                name: tName,
                artist: tArtist,
                album: tAlbum,
                duration: dur > 0 ? dur : 0,
                hasArtwork: hasArt,
                artworkUrl: artUrl,
                favorited: false,
                isLocal: false
            )

            let status = PlayerStatus(
                playerState: stateStr,
                position: pos,
                duration: dur > 0 ? dur : 0,
                volume: app.soundVolume,
                shuffle: false,
                repeatMode: "off",
                playlist: stationName ?? "Apple Music Radio",
                isRadio: true,
                audioQuality: "AAC (256 kbps)",
                track: track
            )

            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.lastPlayerStatusCache = (Date(), status)
            }
            return status
        }

        // 2. Standard or Custom Queue Playback
        let pState = app.playerState
        var stateStr = "stopped"
        switch pState {
        case .playing: stateStr = "playing"
        case .paused: stateStr = "paused"
        case .fastForwarding: stateStr = "fast forwarding"
        case .rewinding: stateStr = "rewinding"
        default: stateStr = "stopped"
        }

        if pState == .stopped {
            if isCustom && customIndex < customQueue.count {
                let qTrack = customQueue[customIndex]
                let artUrl = qTrack.artworkUrl
                let status = PlayerStatus(
                    playerState: "stopped",
                    position: 0,
                    duration: qTrack.duration,
                    volume: app.soundVolume,
                    shuffle: app.shuffleEnabled,
                    repeatMode: "off",
                    playlist: customName ?? "Очередь",
                    isRadio: false,
                    audioQuality: "Lossless (ALAC 24-bit/48kHz)",
                    track: TrackInfo(
                        id: qTrack.id,
                        numericId: qTrack.numericId,
                        name: qTrack.name,
                        artist: qTrack.artist,
                        album: qTrack.album,
                        duration: qTrack.duration,
                        hasArtwork: !artUrl.isEmpty,
                        artworkUrl: artUrl,
                        favorited: false,
                        isLocal: qTrack.isLocal
                    )
                )
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.lastPlayerStatusCache = (Date(), status)
                }
                return status
            }
            let status = PlayerStatus(
                playerState: stateStr,
                position: 0,
                duration: 0,
                volume: app.soundVolume,
                shuffle: app.shuffleEnabled,
                repeatMode: "off",
                playlist: "Музыка",
                isRadio: false,
                audioQuality: "Lossless (ALAC 24-bit/48kHz)",
                track: nil
            )
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.lastPlayerStatusCache = (Date(), status)
            }
            return status
        }

        let curTrack = app.currentTrack
        var tName = (curTrack?.value(forKey: "name") as? String) ?? ""
        var tArtist = (curTrack?.value(forKey: "artist") as? String) ?? ""
        var tAlbum = (curTrack?.value(forKey: "album") as? String) ?? ""
        var dur = (curTrack?.value(forKey: "duration") as? Double) ?? 0
        let pos = computeOptimisticPosition(rawPosition: app.playerPosition, isPlaying: (pState == .playing), duration: dur)
        let vol = app.soundVolume
        let shuf = isShufActive || app.shuffleEnabled

        // Enrich with active custom queue if track is numeric stream or empty
        if isCustom && customIndex < customQueue.count {
            let curQueueTrack = customQueue[customIndex]
            let isNumeric = !tName.isEmpty && tName.allSatisfy { $0.isNumber }
            if tName.isEmpty || isNumeric {
                tName = !curQueueTrack.name.isEmpty ? curQueueTrack.name : tName
                tArtist = !curQueueTrack.artist.isEmpty ? curQueueTrack.artist : tArtist
                tAlbum = !curQueueTrack.album.isEmpty ? curQueueTrack.album : tAlbum
                if dur <= 0 { dur = curQueueTrack.duration }
            }
        }

        var repMode = "off"
        let r = app.songRepeat
        switch r {
        case .one: repMode = "one"
        case .all: repMode = "all"
        default: repMode = "off"
        }

        var hasArt = false
        var isFavorited = false
        if let arts = curTrack?.value(forKey: "artworks") as? SBElementArray, arts.count > 0 {
            hasArt = true
        }
        if let fav = curTrack?.value(forKey: "favorited") as? Bool, fav {
            isFavorited = true
        }

        var currentPlName = "Музыка"
        if isCustom, let qn = customName, !qn.isEmpty {
            currentPlName = qn
        } else if let pName = app.currentPlaylist?.value(forKey: "name") as? String, !pName.isEmpty {
            if pName == "Очередь AMR" {
                currentPlName = origPl ?? "Очередь"
            } else {
                currentPlName = pName
            }
        }

        var trackObj: TrackInfo? = nil
        let dbId = (curTrack?.value(forKey: "databaseID") as? Int) ?? 0
        if !tName.isEmpty {
            var artUrl = hasArt ? (dbId > 0 ? "/api/artwork/track?id=\(dbId)" : "/api/artwork") : ""
            if artUrl.isEmpty && isCustom && customIndex < customQueue.count {
                let customArt = customQueue[customIndex].artworkUrl
                if !customArt.isEmpty {
                    artUrl = customArt
                    hasArt = true
                }
            }
            if artUrl.isEmpty {
                if let local = ArtworkService.shared.findLocalTrackArtwork(name: tName, artist: tArtist) {
                    artUrl = local
                    hasArt = true
                } else if let cached = MusicKitManager.shared.getCachedTrackArtwork(name: tName, artist: tArtist, album: tAlbum), !cached.isEmpty {
                    artUrl = cached
                    hasArt = true
                } else {
                    Task.detached(priority: .utility) {
                        if let fetched = await MusicKitManager.shared.searchTrackArtwork(name: tName, artist: tArtist), !fetched.isEmpty {
                            WebSocketServer.shared.broadcastStatus(includeQueue: false)
                        }
                    }
                }
            }
            trackObj = TrackInfo(
                id: "\(dbId)",
                numericId: dbId,
                name: tName,
                artist: tArtist,
                album: tAlbum,
                duration: dur,
                hasArtwork: hasArt,
                artworkUrl: artUrl,
                favorited: isFavorited,
                isLocal: !isCustom
            )
        }

        var curQuality = "AAC (256 kbps)"
        if let ct = curTrack {
            let bRate = ct.sbBitRate
            let sRate = ct.sbSampleRate
            let knd = ct.sbKind
            curQuality = AudioQualityDetector.determineAudioQuality(kind: knd, bitRate: bRate, sampleRate: sRate)
        }

        if BitPerfectLogMonitor.shared.isEnabled, let rate = BitPerfectLogMonitor.shared.currentDetectedSampleRate {
            let depth = BitPerfectLogMonitor.shared.currentDetectedBitDepth ?? (rate > 48000.0 ? 24 : 16)
            let khz = rate / 1000.0
            let khzStr = (khz.truncatingRemainder(dividingBy: 1) == 0) ? String(format: "%.0f", khz) : String(format: "%.1f", khz)
            if rate > 48000.0 {
                curQuality = "Hi-Res Lossless (ALAC \(depth)-bit/\(khzStr)kHz)"
            } else {
                curQuality = "Lossless (ALAC \(depth)-bit/\(khzStr)kHz)"
            }
        }

        let status = PlayerStatus(
            playerState: stateStr,
            position: pos,
            duration: dur,
            volume: vol,
            shuffle: shuf,
            repeatMode: repMode,
            playlist: currentPlName,
            isRadio: false,
            audioQuality: curQuality,
            track: trackObj
        )

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastPlayerStatusCache = (Date(), status)
        }
        return status
    }
}
