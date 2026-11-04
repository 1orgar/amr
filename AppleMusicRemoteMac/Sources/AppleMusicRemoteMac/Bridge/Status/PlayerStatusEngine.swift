//
//  PlayerStatusEngine.swift
//  AppleMusicRemoteMac
//
//  Aggregates player status from Music.app via atomic AppleScript queries, active custom queues,
//  radio playback, optimistic seek compensation, and real-time audio quality.
//

import Foundation

public struct StaticTrackMetadata: Sendable {
    public var dbId: Int
    public var name: String
    public var artist: String
    public var album: String
    public var duration: Double
    public var hasLoc: Bool
    public var kind: String
    public var bitRate: Int
    public var sampleRate: Int
    public var isFavorited: Bool
    public var currentPlaylistName: String
    public var shuffle: Bool
    public var repeatMode: String
    public var volume: Int
    public var fetchedAt: Date

    public init(
        dbId: Int,
        name: String,
        artist: String,
        album: String,
        duration: Double,
        hasLoc: Bool,
        kind: String,
        bitRate: Int,
        sampleRate: Int,
        isFavorited: Bool,
        currentPlaylistName: String,
        shuffle: Bool,
        repeatMode: String,
        volume: Int,
        fetchedAt: Date = Date()
    ) {
        self.dbId = dbId
        self.name = name
        self.artist = artist
        self.album = album
        self.duration = duration
        self.hasLoc = hasLoc
        self.kind = kind
        self.bitRate = bitRate
        self.sampleRate = sampleRate
        self.isFavorited = isFavorited
        self.currentPlaylistName = currentPlaylistName
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        self.volume = volume
        self.fetchedAt = fetchedAt
    }
}

public final class PlayerStatusEngine: @unchecked Sendable {
    public static let shared = PlayerStatusEngine()

    private let statusLock = NSLock()
    private var lastCanonicalTrackKey: String?
    private var cachedStaticMetadata: StaticTrackMetadata?
    private var lastPulsePosition: Double = 0.0
    public private(set) var lastPollUsedLightweightPulse: Bool = false

    public var cachedCurrentPlaylistName: String? {
        PlaybackStateStore.shared.withLock {
            cachedStaticMetadata?.currentPlaylistName
        }
    }

    private init() {}

    public func seedStaticMetadataForTesting(_ meta: StaticTrackMetadata) {
        PlaybackStateStore.shared.withLock {
            cachedStaticMetadata = meta
            lastPulsePosition = 0.0
            PlaybackStateStore.shared.needsStaticMetadataRefresh = false
        }
    }

    public func shouldUseLightweightPulse(rawState: String, rawPosition: Double) -> Bool {
        return PlaybackStateStore.shared.withLock {
            guard !PlaybackStateStore.shared.needsStaticMetadataRefresh,
                  let meta = cachedStaticMetadata else {
                return false
            }
            if Date().timeIntervalSince(meta.fetchedAt) >= 30.0 {
                return false
            }
            let isStopped = (rawState.lowercased() == "stopped")
            if isStopped != meta.name.isEmpty {
                return false
            }
            let hasSeekTarget = (PlaybackStateStore.shared.seekTargetPosition != nil && Date().timeIntervalSince(PlaybackStateStore.shared.seekTargetDate) < 4.0)
            if !hasSeekTarget && rawPosition < lastPulsePosition - 4.0 && lastPulsePosition > 8.0 {
                return false
            }
            return true
        }
    }

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

        if status.playerState != "stopped" {
            let tArtist = status.track?.artist ?? ""
            let tName = status.track?.name ?? ""
            let cachedFmt = BitPerfectLogMonitor.shared.getCachedFormat(artist: tArtist, title: tName)
            let detectedRate = BitPerfectLogMonitor.shared.currentDetectedSampleRate
            let detectedDepth = BitPerfectLogMonitor.shared.currentDetectedBitDepth
            let isStreamLossless = (cachedFmt != nil) || (BitPerfectLogMonitor.shared.currentIsLossless && detectedRate != nil)

            if status.track?.isLocal != true {
                if isStreamLossless, let r = cachedFmt?.sampleRate ?? detectedRate {
                    let depth = cachedFmt?.bitDepth ?? detectedDepth ?? (r >= 48000.0 ? 24 : 16)
                    status.track?.sampleRate = Int(r)
                    status.track?.bitDepth = depth
                    if BitPerfectLogMonitor.shared.isEnabled {
                        let khz = r / 1000.0
                        let khzStr = (khz.truncatingRemainder(dividingBy: 1) == 0) ? String(format: "%.0f", khz) : String(format: "%.1f", khz)
                        status.audioQuality = (r > 48000.0)
                            ? "Hi-Res Lossless (ALAC \(depth)-bit/\(khzStr)kHz)"
                            : "Lossless (ALAC \(depth)-bit/\(khzStr)kHz)"
                    }
                } else {
                    status.track?.sampleRate = 44100
                    status.track?.bitDepth = 16
                    status.audioQuality = "AAC (256 kbps)"
                }
            } else {
                let isLocalLossless = !status.audioQuality.contains("AAC") && !status.audioQuality.contains("MP3")
                if !isLocalLossless {
                    status.track?.bitDepth = 16
                } else if BitPerfectLogMonitor.shared.isEnabled, let r = status.track?.sampleRate.map({ Double($0) }) ?? detectedRate {
                    let depth = status.track?.bitDepth ?? detectedDepth ?? (r >= 48000.0 ? 24 : 16)
                    let khz = r / 1000.0
                    let khzStr = (khz.truncatingRemainder(dividingBy: 1) == 0) ? String(format: "%.0f", khz) : String(format: "%.1f", khz)
                    status.audioQuality = (r > 48000.0)
                        ? "Hi-Res Lossless (ALAC \(depth)-bit/\(khzStr)kHz)"
                        : "Lossless (ALAC \(depth)-bit/\(khzStr)kHz)"
                }
            }
        }

        let isLosslessQuality = !status.audioQuality.contains("AAC") && !status.audioQuality.contains("MP3")
        let activeSourceRate = status.track?.sampleRate.map { Double($0) } ?? (isLosslessQuality ? BitPerfectLogMonitor.shared.currentDetectedSampleRate : 44100.0)
        let activeSourceDepth = !isLosslessQuality ? 16 : (status.track?.bitDepth ?? BitPerfectLogMonitor.shared.currentDetectedBitDepth)

        if let dlna = DLNADiscoveryManager.shared.getActiveRenderer() {
            if let trRate = status.track?.sampleRate, trRate > 0, BitPerfectLogMonitor.shared.isEnabled {
                let trDepth = !isLosslessQuality ? 16 : (status.track?.bitDepth ?? (trRate >= 48000 ? 24 : 16))
                if AudioProcessTapService.shared.sampleRate != trRate || AudioProcessTapService.shared.bitDepth != trDepth {
                    AudioProcessTapService.shared.setFormat(sampleRate: trRate, bitDepth: trDepth)
                }
            }
            status.audioDeviceName = dlna.friendlyName
            status.audioDeviceSampleRate = Double(AudioProcessTapService.shared.sampleRate)
            status.audioDeviceBitDepth = AudioProcessTapService.shared.bitDepth
        } else if let defDevice = CoreAudioDeviceManager.shared.getDefaultOutputDevice() {
            status.audioDeviceName = defDevice.name
            status.audioDeviceSampleRate = defDevice.currentSampleRate
            status.audioDeviceBitDepth = activeSourceDepth ?? (defDevice.currentSampleRate >= 48000.0 ? 24 : 16)
        }
        let devRate = status.audioDeviceSampleRate ?? 44100.0
        let ratesMatch = (activeSourceRate == nil) || (abs((activeSourceRate ?? devRate) - devRate) <= 500.0)
        status.isBitPerfect = BitPerfectLogMonitor.shared.isEnabled && isLosslessQuality && ratesMatch

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

        // Fast path: if in test environment, or Music.app is closed/unhealthy, avoid running AppleScript or triggering app launch
        if PlaybackRouter.shared.isTestingEnvironment || !MusicAppProvider.shared.isMusicAppRunning || !MusicAppLifecycleManager.shared.isHealthy {
            let currentVol = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.simulatedVolume }
            let isUserPaused = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isUserPaused }
            let cachedState = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.lastPlayerStatusCache?.status.playerState } ?? (isUserPaused ? "paused" : "stopped")
            let stoppedStatus = PlayerStatus(
                playerState: cachedState,
                position: 0,
                duration: 0,
                volume: currentVol,
                shuffle: false,
                repeatMode: "off",
                playlist: "Музыка",
                isRadio: false,
                audioQuality: "Lossless (Остановлен)",
                isMusicAppRunning: MusicAppLifecycleManager.shared.isHealthy,
                track: nil
            )
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.lastPlayerStatusCache = (Date(), stoppedStatus)
            }
            return stoppedStatus
        }

        let (isRadio, stationName, isCustom, customQueue, customIndex, customName, isShufActive, storeRepMode, origPl, needsFullRefresh) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isRadioPlayback,
                PlaybackStateStore.shared.activeStationName,
                PlaybackStateStore.shared.isCustomQueuePlayback,
                PlaybackStateStore.shared.activeCustomQueue,
                PlaybackStateStore.shared.activeCustomQueueIndex,
                PlaybackStateStore.shared.activeCustomQueueName,
                PlaybackStateStore.shared.isShuffleQueueActive,
                PlaybackStateStore.shared.repeatMode,
                PlaybackStateStore.shared.currentOriginalPlaylistName,
                PlaybackStateStore.shared.needsStaticMetadataRefresh
            )
        }

        var rawState = "stopped"
        var rawPos = 0.0
        var vol = 100
        var dur = 0.0
        var tName = ""
        var tArtist = ""
        var tAlbum = ""
        var dbId = 0
        var shuf = false
        var repMode = "off"
        var hasLoc = false
        var curPlNameRaw = ""
        var knd = ""
        var bRate = 0
        var sRate = 0
        var isFavorited = false
        var usedLightweightPulse = false

        // Tier 1: Zero-Stall Lightweight IPC Pulse (queries ONLY player state + player position in ~15ms)
        if !needsFullRefresh, let staticMeta = cachedStaticMetadata, Date().timeIntervalSince(staticMeta.fetchedAt) < 30.0 {
            let pulseScript = """
            tell application "Music"
                try
                    with timeout of 1.5 seconds
                        set pState to (player state as string)
                        if pState is "stopped" then
                            return "stopped||0"
                        end if
                        set pPos to 0
                        try
                            set pPos to player position
                        end try
                        return pState & "||" & pPos
                    end timeout
                on error
                    return "error"
                end try
            end tell
            """
            let (pulseOk, pulseOut) = AppleScriptExecutor.shared.execute(pulseScript)
            if pulseOk, let pOut = pulseOut, !pOut.isEmpty, pOut != "error" {
                let pParts = pOut.components(separatedBy: "||")
                if pParts.count >= 2 {
                    let candidateState = pParts[0].lowercased()
                    let candidatePos = Double(pParts[1].replacingOccurrences(of: ",", with: ".")) ?? 0.0
                    if shouldUseLightweightPulse(rawState: candidateState, rawPosition: candidatePos) {
                        rawState = candidateState
                        rawPos = candidatePos
                        vol = staticMeta.volume
                        dur = staticMeta.duration
                        tName = staticMeta.name
                        tArtist = staticMeta.artist
                        tAlbum = staticMeta.album
                        dbId = staticMeta.dbId
                        shuf = isCustom ? isShufActive : (staticMeta.shuffle || isShufActive)
                        repMode = isCustom ? storeRepMode : staticMeta.repeatMode
                        hasLoc = staticMeta.hasLoc
                        curPlNameRaw = staticMeta.currentPlaylistName
                        knd = staticMeta.kind
                        bRate = staticMeta.bitRate
                        sRate = staticMeta.sampleRate
                        isFavorited = staticMeta.isFavorited
                        lastPulsePosition = candidatePos
                        lastPollUsedLightweightPulse = true
                        usedLightweightPulse = true
                    }
                }
            }
        }

        // Tier 2: Full Static Metadata Query (strictly once on track change or cache invalidation)
        if !usedLightweightPulse {
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
                            try
                                set knd to (kind of ct as string)
                            end try
                            set br to 0
                            try
                                set br to (bit rate of ct as integer)
                            end try
                            set sr to 0
                            try
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
                (ok, rawOut) = AppleScriptExecutor.shared.execute(script)
            }
            guard ok, let out = rawOut, !out.isEmpty, out != "error" else {
                if let cached = PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.lastPlayerStatusCache }) {
                    return cached.status
                }
                let simVol = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.simulatedVolume }
                return PlayerStatus(volume: simVol)
            }

            let parts = out.components(separatedBy: "||")
            guard parts.count >= 12 else {
                if let cached = PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.lastPlayerStatusCache }) {
                    return cached.status
                }
                return PlayerStatus()
            }

            rawState = parts[0].lowercased()
            let rawPosStr = parts[1].replacingOccurrences(of: ",", with: ".")
            rawPos = Double(rawPosStr) ?? 0.0
            vol = Int(parts[2]) ?? 100
            let rawDurStr = parts[3].replacingOccurrences(of: ",", with: ".")
            dur = Double(rawDurStr) ?? 0.0
            tName = parts[4]
            tArtist = parts[5]
            tAlbum = parts[6]
            dbId = Int(parts[7]) ?? 0
            let rawShuf = (parts[8].lowercased() == "true")
            shuf = isCustom ? isShufActive : (rawShuf || isShufActive)
            let rawRep = parts[9]
            repMode = isCustom ? storeRepMode : rawRep
            hasLoc = (parts[10].lowercased() == "true")
            curPlNameRaw = parts[11]
            knd = parts.count > 12 ? parts[12] : ""
            bRate = parts.count > 13 ? (Int(parts[13]) ?? 0) : 0
            sRate = parts.count > 14 ? (Int(parts[14]) ?? 0) : 0
            isFavorited = parts.count > 15 ? (parts[15].lowercased() == "true") : false

            if PlaybackStateStore.shared.isVolumeLockedTo100 && vol != 100 && !AudioDuckingController.shared.isDucked {
                PlaybackTransportController.shared.checkAndEnforceVolumeLock()
                vol = 100
            }

            let meta = StaticTrackMetadata(
                dbId: dbId,
                name: tName,
                artist: tArtist,
                album: tAlbum,
                duration: dur,
                hasLoc: hasLoc,
                kind: knd,
                bitRate: bRate,
                sampleRate: sRate,
                isFavorited: isFavorited,
                currentPlaylistName: curPlNameRaw,
                shuffle: rawShuf,
                repeatMode: rawRep,
                volume: vol,
                fetchedAt: Date()
            )
            PlaybackStateStore.shared.withLock {
                self.cachedStaticMetadata = meta
                PlaybackStateStore.shared.simulatedVolume = vol
                PlaybackStateStore.shared.needsStaticMetadataRefresh = false
            }
            lastPulsePosition = rawPos
            lastPollUsedLightweightPulse = false
        }

        let isUserPaused = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isUserPaused }
        var stateStr = (rawState == "playing") ? "playing" : ((rawState == "paused") ? "paused" : "stopped")
        if isUserPaused && stateStr == "playing" {
            let isRadioActive = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isRadioPlayback }
            if isRadioActive {
                PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isUserPaused = false }
            } else {
                stateStr = "paused"
            }
        }

        let canonicalKey = (!tName.isEmpty)
            ? "\(tArtist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()):\(tName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
            : ""
        if !canonicalKey.isEmpty && stateStr == "playing" {
            if lastCanonicalTrackKey != canonicalKey {
                var preRate: Double? = nil
                var preDepth: Int? = nil
                if let cached = BitPerfectLogMonitor.shared.getCachedFormat(artist: tArtist, title: tName) {
                    preRate = cached.sampleRate
                    preDepth = cached.bitDepth
                } else if hasLoc && sRate > 0 {
                    // Only trust AppleScript's sample rate for local files; streaming tracks report placeholder 44100 Hz before ALAC decoder starts
                    let locQuality = AudioQualityDetector.determineAudioQuality(kind: knd, bitRate: bRate, sampleRate: sRate)
                    let locIsLossless = !locQuality.contains("AAC") && !locQuality.contains("MP3")
                    preRate = Double(sRate)
                    preDepth = !locIsLossless ? 16 : ((sRate >= 48000) ? 24 : (bRate > 1000 ? 24 : 16))
                }
                NSLog("[PlayerStatusEngine] 🎵 Track changed to '%@' (pre-inspected format: %@)", canonicalKey, preRate != nil ? "\(preRate! / 1000.0) kHz" : "awaiting ALAC decoder")
                BitPerfectLogMonitor.shared.resetTrackState(trackKey: canonicalKey, expectedSampleRate: preRate, expectedBitDepth: preDepth)
                lastCanonicalTrackKey = canonicalKey
            }
        } else if stateStr == "stopped" && lastCanonicalTrackKey != nil {
            lastCanonicalTrackKey = nil
            BitPerfectLogMonitor.shared.resetTrackState()
        }

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

            let cachedFmt = BitPerfectLogMonitor.shared.getCachedFormat(artist: radArtist, title: radName)
            let detectedRate = BitPerfectLogMonitor.shared.currentDetectedSampleRate
            let detectedDepth = BitPerfectLogMonitor.shared.currentDetectedBitDepth
            let isRadLossless = (cachedFmt != nil) || (BitPerfectLogMonitor.shared.currentIsLossless && detectedRate != nil)
            let radRate: Int
            let radDepth: Int
            let radQuality: String
            if isRadLossless, let r = cachedFmt?.sampleRate ?? detectedRate {
                radRate = Int(r)
                radDepth = cachedFmt?.bitDepth ?? detectedDepth ?? (r >= 48000.0 ? 24 : 16)
                let khz = r / 1000.0
                let khzStr = (khz.truncatingRemainder(dividingBy: 1) == 0) ? String(format: "%.0f", khz) : String(format: "%.1f", khz)
                radQuality = (r > 48000.0)
                    ? "Hi-Res Lossless (ALAC \(radDepth)-bit/\(khzStr)kHz)"
                    : "Lossless (ALAC \(radDepth)-bit/\(khzStr)kHz)"
            } else {
                radRate = 44100
                radDepth = 16
                radQuality = "AAC (256 kbps)"
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
                isLocal: false,
                sampleRate: radRate,
                bitDepth: radDepth
            )

            let activeDLNA = DLNADiscoveryManager.shared.getActiveRenderer()
            let defDevice = CoreAudioDeviceManager.shared.getDefaultOutputDevice()
            let devName: String
            let devRate: Double
            let devDepth: Int
            if let dlna = activeDLNA {
                devName = dlna.friendlyName
                if BitPerfectLogMonitor.shared.isEnabled && (AudioProcessTapService.shared.sampleRate != radRate || AudioProcessTapService.shared.bitDepth != radDepth) {
                    AudioProcessTapService.shared.setFormat(sampleRate: radRate, bitDepth: radDepth)
                }
                devRate = Double(AudioProcessTapService.shared.sampleRate)
                devDepth = AudioProcessTapService.shared.bitDepth
            } else {
                devName = defDevice?.name ?? "Аудиоустройство"
                devRate = defDevice?.currentSampleRate ?? 44100.0
                devDepth = isRadLossless ? radDepth : 16
            }
            let ratesMatch = abs(Double(radRate) - devRate) <= 500.0
            let isBp = BitPerfectLogMonitor.shared.isEnabled && isRadLossless && ratesMatch

            let status = PlayerStatus(
                playerState: stateStr,
                position: pos,
                duration: dur > 0 ? dur : 0,
                volume: vol,
                shuffle: false,
                repeatMode: "off",
                playlist: stationName ?? "Apple Music Radio",
                isRadio: true,
                audioQuality: radQuality,
                track: track,
                audioDeviceName: devName,
                audioDeviceSampleRate: devRate,
                audioDeviceBitDepth: devDepth,
                isBitPerfect: isBp
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

        var curQuality = "AAC (256 kbps)"
        var isLocalLossless = false
        if hasLoc {
            curQuality = AudioQualityDetector.determineAudioQuality(kind: knd, bitRate: bRate, sampleRate: sRate)
            isLocalLossless = !curQuality.contains("AAC") && !curQuality.contains("MP3")
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
            let cachedFmt = BitPerfectLogMonitor.shared.getCachedFormat(artist: tArtist, title: tName)
            let detectedRate = BitPerfectLogMonitor.shared.currentDetectedSampleRate.map { Int($0) }
            let detectedDepth = BitPerfectLogMonitor.shared.currentDetectedBitDepth
            let isStreamLossless = (cachedFmt != nil) || (BitPerfectLogMonitor.shared.currentIsLossless && detectedRate != nil)
            let effectiveTrackRate: Int?
            let effectiveTrackDepth: Int?
            if hasLoc && sRate > 0 {
                effectiveTrackRate = sRate
                effectiveTrackDepth = !isLocalLossless ? 16 : ((sRate >= 48000) ? 24 : (bRate > 1000 ? 24 : (detectedDepth ?? 16)))
            } else if isStreamLossless {
                effectiveTrackRate = cachedFmt.map { Int($0.sampleRate) } ?? detectedRate
                if let d = cachedFmt?.bitDepth ?? detectedDepth {
                    effectiveTrackDepth = d
                } else if let r = effectiveTrackRate {
                    effectiveTrackDepth = r >= 48000 ? 24 : 16
                } else {
                    effectiveTrackDepth = nil
                }
            } else {
                effectiveTrackRate = 44100
                effectiveTrackDepth = 16
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
                isLocal: hasLoc,
                sampleRate: effectiveTrackRate,
                bitDepth: effectiveTrackDepth
            )
        }

        if stateStr == "playing" && hasLoc && sRate > 0 && BitPerfectLogMonitor.shared.isEnabled {
            let depth = !isLocalLossless ? 16 : (sRate >= 48000 ? 24 : (bRate > 1000 ? 24 : 16))
            BitPerfectLogMonitor.shared.reportLocalTrackFormat(sampleRate: Double(sRate), bitDepth: depth, isLossless: isLocalLossless)
        }

        let isLosslessTrack = hasLoc ? isLocalLossless : ((BitPerfectLogMonitor.shared.getCachedFormat(artist: tArtist, title: tName) != nil) || (BitPerfectLogMonitor.shared.currentIsLossless && BitPerfectLogMonitor.shared.currentDetectedSampleRate != nil))
        let activeSourceRate = trackObj?.sampleRate.map { Double($0) } ?? (isLosslessTrack ? BitPerfectLogMonitor.shared.currentDetectedSampleRate : 44100.0)
        let activeSourceDepth = !isLosslessTrack ? 16 : (trackObj?.bitDepth ?? BitPerfectLogMonitor.shared.currentDetectedBitDepth)
        if BitPerfectLogMonitor.shared.isEnabled {
            if isLosslessTrack, let rate = activeSourceRate {
                let depth = activeSourceDepth ?? (rate >= 48000.0 ? 24 : 16)
                let khz = rate / 1000.0
                let khzStr = (khz.truncatingRemainder(dividingBy: 1) == 0) ? String(format: "%.0f", khz) : String(format: "%.1f", khz)
                if rate > 48000.0 {
                    curQuality = "Hi-Res Lossless (ALAC \(depth)-bit/\(khzStr)kHz)"
                } else {
                    curQuality = "Lossless (ALAC \(depth)-bit/\(khzStr)kHz)"
                }
            } else if !hasLoc {
                curQuality = "AAC (256 kbps)"
            }
        }

        let activeDLNA = DLNADiscoveryManager.shared.getActiveRenderer()
        let defDevice = CoreAudioDeviceManager.shared.getDefaultOutputDevice()
        let devName: String
        let devRate: Double
        let devDepth: Int
        if let dlna = activeDLNA {
            devName = dlna.friendlyName
            if let trRate = trackObj?.sampleRate, trRate > 0, BitPerfectLogMonitor.shared.isEnabled {
                let trDepth = !isLosslessTrack ? 16 : (trackObj?.bitDepth ?? (trRate >= 48000 ? 24 : 16))
                if AudioProcessTapService.shared.sampleRate != trRate || AudioProcessTapService.shared.bitDepth != trDepth {
                    AudioProcessTapService.shared.setFormat(sampleRate: trRate, bitDepth: trDepth)
                }
            }
            devRate = Double(AudioProcessTapService.shared.sampleRate)
            devDepth = AudioProcessTapService.shared.bitDepth
        } else {
            devName = defDevice?.name ?? "Аудиоустройство"
            devRate = defDevice?.currentSampleRate ?? 44100.0
            devDepth = activeSourceDepth ?? (devRate >= 48000.0 ? 24 : 16)
        }
        let ratesMatch = (activeSourceRate == nil) || (abs((activeSourceRate ?? devRate) - devRate) <= 500.0)
        let isBp = BitPerfectLogMonitor.shared.isEnabled && isLosslessTrack && ratesMatch

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
            audioDeviceBitDepth: devDepth,
            isBitPerfect: isBp
        )

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastPlayerStatusCache = (Date(), status)
        }
        return status
    }
}
