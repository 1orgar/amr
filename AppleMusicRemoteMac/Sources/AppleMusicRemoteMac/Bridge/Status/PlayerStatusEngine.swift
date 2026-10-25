//
//  PlayerStatusEngine.swift
//  AppleMusicRemoteMac
//
//  Aggregates player status from Music.app via atomic AppleScript queries, active custom queues,
//  radio playback, optimistic seek compensation, and real-time audio quality.
//

import Foundation

public final class PlayerStatusEngine: @unchecked Sendable {
    public static let shared = PlayerStatusEngine()

    private let statusLock = NSLock()
    private var lastTrackSignature: String?

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
        var status = computePlayerStatus()
        status.isDucked = AudioDuckingController.shared.isDucked
        status.isVolumeLockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100
        return status
    }

    private func computePlayerStatus() -> PlayerStatus {
        let (cached, isTransitioning) = PlaybackStateStore.shared.withLock {
            (PlaybackStateStore.shared.lastPlayerStatusCache, PlaybackStateStore.shared.isTransitioningTrack)
        }
        let cacheMaxAge = isTransitioning ? 0.8 : 1.2
        if let cached = cached {
            let age = Date().timeIntervalSince(cached.timestamp)
            if age < cacheMaxAge {
                var status = cached.status
                if status.playerState == "playing" {
                    let optimisticPos = status.position + age
                    status.position = status.duration > 0 ? min(optimisticPos, status.duration) : optimisticPos
                }
                return status
            }
        }

        guard statusLock.lock(before: Date().addingTimeInterval(0.4)) else {
            if let cached = PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.lastPlayerStatusCache }) {
                let age = Date().timeIntervalSince(cached.timestamp)
                var status = cached.status
                if status.playerState == "playing" {
                    let optimisticPos = status.position + age
                    status.position = status.duration > 0 ? min(optimisticPos, status.duration) : optimisticPos
                }
                return status
            }
            return PlayerStatus()
        }
        defer { statusLock.unlock() }

        // Double check cache after lock
        if let cached = PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.lastPlayerStatusCache }) {
            let age = Date().timeIntervalSince(cached.timestamp)
            if age < 0.3 {
                var status = cached.status
                if status.playerState == "playing" {
                    let optimisticPos = status.position + age
                    status.position = status.duration > 0 ? min(optimisticPos, status.duration) : optimisticPos
                }
                return status
            }
        }

        // Fast path: if Music.app is closed, avoid running AppleScript or triggering app launch
        if !MusicAppProvider.shared.isMusicAppRunning {
            let currentVol = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.simulatedVolume }
            let stoppedStatus = PlayerStatus(
                playerState: "stopped",
                position: 0,
                duration: 0,
                volume: currentVol,
                shuffle: false,
                repeatMode: "off",
                playlist: "Музыка",
                isRadio: false,
                audioQuality: "Lossless (Остановлен)",
                isMusicAppRunning: false,
                track: nil
            )
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.lastPlayerStatusCache = (Date(), stoppedStatus)
            }
            return stoppedStatus
        }

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

        let script = """
        tell application "Music"
            try
                with timeout of 2.5 seconds
                    set pState to (player state as string)
                    set pVol to 100
                    try
                        set pVol to sound volume
                    end try
                    if pState is "stopped" then
                        return "stopped||0||" & pVol & "||0||||||||0||false||off||false||||||0||0||false"
                    end if
                    set pPos to 0
                    try
                        set pPos to player position
                    end try
                    set shuf to false
                    try
                        set shuf to (shuffle enabled as boolean)
                    end try
                    set sRep to "off"
                    try
                        set sRep to (song repeat as string)
                    end try
                    set plName to ""
                    try
                        set curPl to current playlist
                        if curPl is not missing value then
                            set plName to (name of curPl as string)
                        end if
                    end try
                    set ct to missing value
                    try
                        set ct to current track
                    end try
                    if ct is not missing value then
                        set dur to 0
                        try
                            set dur to (duration of ct as real)
                        end try
                        set nm to ""
                        try
                            set nm to (name of ct as string)
                        end try
                        set art to ""
                        try
                            set art to (artist of ct as string)
                        end try
                        set alb to ""
                        try
                            set alb to (album of ct as string)
                        end try
                        set dbid to 0
                        try
                            set dbid to (database ID of ct as integer)
                        end try
                        set hasLoc to false
                        try
                            if (class of ct as string) is "file track" then
                                set hasLoc to true
                            end if
                        end try
                        set knd to ""
                        set br to 0
                        set sr to 0
                        try
                            set knd to (kind of ct as string)
                            set br to (bit rate of ct as integer)
                            set sr to (sample rate of ct as integer)
                        end try
                        set isFav to false
                        try
                            set isFav to (favorited of ct as boolean)
                        end try
                        return pState & "||" & pPos & "||" & pVol & "||" & dur & "||" & nm & "||" & art & "||" & alb & "||" & dbid & "||" & shuf & "||" & sRep & "||" & hasLoc & "||" & plName & "||" & knd & "||" & br & "||" & sr & "||" & isFav
                    end if
                    return pState & "||" & pPos & "||" & pVol & "||0||||||||0||" & shuf & "||" & sRep & "||false||" & plName & "||||0||0||false"
                end timeout
            on error
                return "error"
            end try
        end tell
        """

        var (ok, rawOut) = AppleScriptExecutor.shared.execute(script)
        if !ok || rawOut == nil || rawOut?.isEmpty == true || rawOut == "error" {
            Thread.sleep(forTimeInterval: 0.05)
            (ok, rawOut) = AppleScriptExecutor.shared.execute(script)
        }
        guard ok, let out = rawOut, !out.isEmpty, out != "error" else {
            if let cached = PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.lastPlayerStatusCache }) {
                return cached.status
            }
            return PlayerStatus()
        }

        let parts = out.components(separatedBy: "||")
        guard parts.count >= 12 else {
            if let cached = PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.lastPlayerStatusCache }) {
                return cached.status
            }
            return PlayerStatus()
        }

        let rawState = parts[0].lowercased()
        let isUserPaused = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isUserPaused }
        var stateStr = (rawState == "playing") ? "playing" : ((rawState == "paused") ? "paused" : "stopped")
        if isUserPaused && stateStr == "playing" {
            stateStr = "paused"
        }
        let rawPosStr = parts[1].replacingOccurrences(of: ",", with: ".")
        let rawPos = Double(rawPosStr) ?? 0.0
        var vol = Int(parts[2]) ?? 100
        if PlaybackStateStore.shared.isVolumeLockedTo100 && vol != 100 && !AudioDuckingController.shared.isDucked {
            PlaybackTransportController.shared.checkAndEnforceVolumeLock()
            vol = 100
        }
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.simulatedVolume = vol
        }
        let rawDurStr = parts[3].replacingOccurrences(of: ",", with: ".")
        var dur = Double(rawDurStr) ?? 0.0
        var tName = parts[4]
        var tArtist = parts[5]
        var tAlbum = parts[6]
        let dbId = Int(parts[7]) ?? 0
        let shuf = (parts[8].lowercased() == "true") || isShufActive
        let repMode = parts[9]
        let hasLoc = (parts[10].lowercased() == "true")
        let curPlNameRaw = parts[11]

        let knd = parts.count > 12 ? parts[12] : ""
        let bRate = parts.count > 13 ? (Int(parts[13]) ?? 0) : 0
        let sRate = parts.count > 14 ? (Int(parts[14]) ?? 0) : 0
        let isFavorited = parts.count > 15 ? (parts[15].lowercased() == "true") : false

        let currentTrackSig = "\(stateStr):\(dbId):\(tName):\(tArtist)"
        if let lastSig = lastTrackSignature, lastSig != currentTrackSig {
            if !tName.isEmpty && stateStr == "playing" {
                NSLog("[PlayerStatusEngine] 🎵 Track changed to '%@' (Natural progression) - resetting Bit-Perfect lock", currentTrackSig)
                BitPerfectLogMonitor.shared.resetTrackState()
            } else if stateStr == "stopped" && !lastSig.starts(with: "stopped") {
                BitPerfectLogMonitor.shared.resetTrackState()
            }
        }
        lastTrackSignature = currentTrackSig

        let isStreamTrack = (!hasLoc && !tName.isEmpty)
        var isRadioDetected = isRadio
        if isCustom {
            isRadioDetected = false
        } else if !curPlNameRaw.isEmpty && curPlNameRaw != "Музыка" && curPlNameRaw != "Music" && curPlNameRaw != "Медиатека" {
            isRadioDetected = false
            if isRadio {
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.isRadioPlayback = false
                    PlaybackStateStore.shared.activeStationName = nil
                }
            }
        } else if let orig = origPl, !orig.isEmpty {
            isRadioDetected = false
            if isRadio {
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.isRadioPlayback = false
                    PlaybackStateStore.shared.activeStationName = nil
                }
            }
        } else if isStreamTrack && curPlNameRaw.isEmpty {
            isRadioDetected = true
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.isRadioPlayback = true
            }
        }

        let pos = computeOptimisticPosition(rawPosition: rawPos, isPlaying: (stateStr == "playing"), duration: dur)

        // 1. Radio / Station Playback Mode
        if isRadioDetected {
            let radName = tName.isEmpty ? (stationName ?? "Apple Music Radio") : tName
            let radArtist = tArtist.isEmpty ? "Apple Music" : tArtist

            if dbId > 0 && !tName.isEmpty {
                PlaybackStateStore.shared.setTrackMetadata(id: dbId, name: tName, artist: tArtist, album: tAlbum)
            }

            var hasArt = false
            var artUrl = ""

            let checkName = radName.lowercased()
            if checkName.contains("моя станция") {
                artUrl = "/assets/stations/CoverPersonal.png"
                hasArt = true
            } else if checkName.contains("станция открытий") {
                artUrl = "/assets/stations/CoverDiscovery.png"
                hasArt = true
            } else if checkName.contains("сейчас на повторе") {
                artUrl = "/assets/stations/CoverHeavyRotation.svg"
                hasArt = true
            } else if checkName.contains("apple music 1") {
                artUrl = "/assets/stations/CoverAppleMusic1.png"
                hasArt = true
            }

            if artUrl.isEmpty && !radName.isEmpty {
                if let cached = MusicKitManager.shared.getCachedTrackArtwork(name: radName, artist: radArtist, album: tAlbum), !cached.isEmpty {
                    artUrl = cached
                    hasArt = true
                } else if let local = ArtworkService.shared.findLocalTrackArtwork(name: radName, artist: radArtist) {
                    artUrl = local
                    hasArt = true
                } else {
                    let encName = radName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    let encArtist = radArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    let encAlbum = tAlbum.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    artUrl = "/api/artwork/search?name=\(encName)&artist=\(encArtist)&album=\(encAlbum)"
                    hasArt = true
                    let searchAlbum = tAlbum
                    Task.detached(priority: .userInitiated) {
                        if let fetched = await MusicKitManager.shared.searchTrackArtwork(name: radName, artist: radArtist, album: searchAlbum), !fetched.isEmpty {
                            if !PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.isTransitioningTrack }) {
                                WebSocketServer.shared.broadcastStatus(includeQueue: false)
                            }
                        }
                    }
                }
            }

            let track = TrackInfo(
                id: "\(dbId)",
                numericId: dbId,
                name: radName,
                artist: radArtist,
                album: tAlbum,
                duration: dur > 0 ? dur : 0,
                hasArtwork: hasArt,
                artworkUrl: artUrl,
                favorited: isFavorited,
                isLocal: false
            )

            let status = PlayerStatus(
                playerState: stateStr,
                position: pos,
                duration: dur > 0 ? dur : 0,
                volume: vol,
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

        // 2. Stopped state handling
        if stateStr == "stopped" {
            if isCustom && customIndex < customQueue.count {
                let qTrack = customQueue[customIndex]
                let artUrl = qTrack.artworkUrl
                let status = PlayerStatus(
                    playerState: "stopped",
                    position: 0,
                    duration: qTrack.duration,
                    volume: vol,
                    shuffle: shuf,
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
                volume: vol,
                shuffle: shuf,
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

        // 3. Enrich with active custom queue if track is numeric stream or empty
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

        var currentPlName = "Музыка"
        if isCustom, let qn = customName, !qn.isEmpty {
            currentPlName = qn
        } else if !curPlNameRaw.isEmpty && curPlNameRaw != "Музыка" && curPlNameRaw != "Music" && curPlNameRaw != "Медиатека" {
            if curPlNameRaw == "Очередь AMR" {
                currentPlName = origPl ?? "Очередь"
            } else {
                currentPlName = curPlNameRaw
            }
        } else if let orig = origPl, !orig.isEmpty {
            currentPlName = orig
        }

        var trackObj: TrackInfo? = nil
        if dbId > 0 && !tName.isEmpty {
            PlaybackStateStore.shared.setTrackMetadata(id: dbId, name: tName, artist: tArtist, album: tAlbum)
        }

        if !tName.isEmpty {
            let encName = tName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let encArtist = tArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let encAlbum = tAlbum.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            var artUrl = ""

            if hasLoc && dbId > 0 {
                artUrl = "/api/artwork/track?id=\(dbId)&name=\(encName)&artist=\(encArtist)&album=\(encAlbum)"
            }

            if artUrl.isEmpty && isCustom && customIndex < customQueue.count {
                let customArt = customQueue[customIndex].artworkUrl
                if !customArt.isEmpty {
                    artUrl = customArt
                }
            }
            if artUrl.isEmpty {
                if let cached = MusicKitManager.shared.getCachedTrackArtwork(name: tName, artist: tArtist, album: tAlbum), !cached.isEmpty {
                    artUrl = cached
                } else if let local = ArtworkService.shared.findLocalTrackArtwork(name: tName, artist: tArtist) {
                    artUrl = local
                } else {
                    artUrl = "/api/artwork/search?name=\(encName)&artist=\(encArtist)&album=\(encAlbum)"
                    let searchName = tName
                    let searchArtist = tArtist
                    let searchAlbum = tAlbum
                    Task.detached(priority: .userInitiated) {
                        if let fetched = await MusicKitManager.shared.searchTrackArtwork(name: searchName, artist: searchArtist, album: searchAlbum), !fetched.isEmpty {
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
                hasArtwork: !artUrl.isEmpty,
                artworkUrl: artUrl,
                favorited: isFavorited,
                isLocal: hasLoc
            )
        }

        var curQuality = "AAC (256 kbps)"
        if hasLoc {
            curQuality = AudioQualityDetector.determineAudioQuality(kind: knd, bitRate: bRate, sampleRate: sRate)
            if stateStr == "playing" && sRate > 0 && BitPerfectLogMonitor.shared.isEnabled {
                BitPerfectLogMonitor.shared.reportLocalTrackFormat(sampleRate: Double(sRate), bitDepth: sRate > 48000 ? 24 : 16)
            }
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

        let defDevice = CoreAudioDeviceManager.shared.getDefaultOutputDevice()
        let devName = defDevice?.name ?? "Аудиоустройство"
        let devRate = defDevice?.currentSampleRate ?? 44100.0
        let isBp = BitPerfectLogMonitor.shared.isEnabled

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
            track: trackObj,
            audioDeviceName: devName,
            audioDeviceSampleRate: devRate,
            isBitPerfect: isBp
        )

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastPlayerStatusCache = (Date(), status)
        }
        return status
    }
}
