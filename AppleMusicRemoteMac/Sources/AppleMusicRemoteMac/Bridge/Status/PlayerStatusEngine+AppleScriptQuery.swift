//
//  PlayerStatusEngine+AppleScriptQuery.swift
//  AppleMusicRemoteMac
//
//  Tier 1 lightweight IPC pulse & Tier 2 full metadata query using collision-safe ||AMR|| separator.
//

import Foundation

struct RawMusicAppStatusSample {
    var rawState: String = "stopped"
    var rawPos: Double = 0.0
    var vol: Int = 100
    var dur: Double = 0.0
    var tName: String = ""
    var tArtist: String = ""
    var tAlbum: String = ""
    var dbId: Int = 0
    var persistentId: String = ""
    var shuf: Bool = false
    var repMode: String = "off"
    var hasLoc: Bool = false
    var curPlNameRaw: String = ""
    var knd: String = ""
    var bRate: Int = 0
    var sRate: Int = 0
    var isFavorited: Bool = false
    var usedLightweightPulse: Bool = false
}

extension PlayerStatusEngine {

    func computePlayerStatus() -> PlayerStatus {
        let (cached, isTransitioning) = PlaybackStateStore.shared.withLock {
            (PlaybackStateStore.shared.lastPlayerStatusCache, PlaybackStateStore.shared.isTransitioningTrack)
        }
        let cacheMaxAge = isTransitioning ? 0.8 : 1.2
        if let cached = cached {
            let age = Date().timeIntervalSince(cached.timestamp)
            if age < cacheMaxAge {
                var status = cached.status
                if status.playerState == "playing" && status.position > 0.05 {
                    let optimisticPos = status.position + age
                    let nearEndMargin = (status.isRadio && status.repeatMode == "one") ? 5.0 : 2.6
                    if status.duration > 0 && optimisticPos >= status.duration - nearEndMargin && !isTransitioning {
                        // Fall through to query fresh status near track end
                    } else {
                        status.position = status.duration > 0 ? min(optimisticPos, status.duration) : optimisticPos
                        return status
                    }
                } else {
                    return status
                }
            }
        }

        guard statusLock.lock(before: Date().addingTimeInterval(0.4)) else {
            if let cached = PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.lastPlayerStatusCache }) {
                let age = Date().timeIntervalSince(cached.timestamp)
                var status = cached.status
                if status.playerState == "playing" && status.position > 0.05 {
                    let optimisticPos = status.position + age
                    status.position = status.duration > 0 ? min(optimisticPos, status.duration) : optimisticPos
                }
                return status
            }
            var fallbackStatus = PlayerStatus()
            applyLiveAudioPipelineOverlay(to: &fallbackStatus, updateTapFormatIfNeeded: false)
            return fallbackStatus
        }
        defer { statusLock.unlock() }

        if let cached = PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.lastPlayerStatusCache }) {
            let age = Date().timeIntervalSince(cached.timestamp)
            if age < 0.06 {
                var status = cached.status
                if status.playerState == "playing" && status.position > 0.05 {
                    let optimisticPos = status.position + age
                    status.position = status.duration > 0 ? min(optimisticPos, status.duration) : optimisticPos
                }
                return status
            }
        }

        if PlaybackRouter.shared.isTestingEnvironment || !MusicAppProvider.shared.isMusicAppRunning || !MusicAppLifecycleManager.shared.isHealthy {
            let (currentVol, isUserPaused, currentRepMode, currentShuf) = PlaybackStateStore.shared.withLock {
                (
                    PlaybackStateStore.shared.simulatedVolume,
                    PlaybackStateStore.shared.isUserPaused,
                    PlaybackStateStore.shared.repeatMode,
                    PlaybackStateStore.shared.isShuffleQueueActive
                )
            }
            let cachedState = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.lastPlayerStatusCache?.status.playerState } ?? (isUserPaused ? "paused" : "stopped")
            var stoppedStatus = PlayerStatus(
                playerState: cachedState,
                position: 0,
                duration: 0,
                volume: currentVol,
                shuffle: currentShuf,
                repeatMode: currentRepMode,
                playlist: "Музыка",
                isRadio: false,
                audioQuality: "Lossless (Остановлен)",
                isMusicAppRunning: MusicAppLifecycleManager.shared.isHealthy,
                track: nil
            )
            applyLiveAudioPipelineOverlay(to: &stoppedStatus, updateTapFormatIfNeeded: false)
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.lastPlayerStatusCache = (Date(), stoppedStatus)
            }
            return stoppedStatus
        }

        let (isRadio, stationName, isCustom, customQueue, customIndex, customName, isShufActive, storeRepMode, lastRepeatSetTime, lastShuffleSetTime, origPl, needsFullRefresh, isActivelyStartingCloud, simVol) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isRadioPlayback,
                PlaybackStateStore.shared.activeStationName,
                PlaybackStateStore.shared.isCustomQueuePlayback,
                PlaybackStateStore.shared.activeCustomQueue,
                PlaybackStateStore.shared.activeCustomQueueIndex,
                PlaybackStateStore.shared.activeCustomQueueName,
                PlaybackStateStore.shared.isShuffleQueueActive,
                PlaybackStateStore.shared.repeatMode,
                PlaybackStateStore.shared.lastRepeatSetTime,
                PlaybackStateStore.shared.lastShuffleSetTime,
                PlaybackStateStore.shared.currentOriginalPlaylistName,
                PlaybackStateStore.shared.needsStaticMetadataRefresh,
                PlaybackStateStore.shared.isStagingCloudTrack && !PlaybackStateStore.shared.currentTrackPlaybackConfirmed && !PlaybackStateStore.shared.isUserPaused,
                PlaybackStateStore.shared.simulatedVolume
            )
        }

        // Zero-AppleEvent fast path while `SystemMusicPlayerBridge` is initializing a cloud stream in `Music.app`:
        // avoids stalling `Music.app`'s main thread with AppleScript queries before `com.apple.Music.playerInfo` fires.
        if isActivelyStartingCloud && isCustom && customIndex >= 0 && customIndex < customQueue.count {
            return buildStoppedPlayerStatusLocked(
                stateStr: "stopped",
                vol: simVol,
                shuf: isShufActive,
                storeRepMode: storeRepMode,
                isCustom: true,
                customQueue: customQueue,
                customIndex: customIndex,
                customName: customName
            )
        }

        guard let sample = sampleMusicAppStatusLocked(
            isRadio: isRadio,
            stationName: stationName,
            isCustom: isCustom,
            customQueue: customQueue,
            customIndex: customIndex,
            isShufActive: isShufActive,
            storeRepMode: storeRepMode,
            lastRepeatSetTime: lastRepeatSetTime,
            lastShuffleSetTime: lastShuffleSetTime,
            needsFullRefresh: needsFullRefresh
        ) else {
            if let cached = PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.lastPlayerStatusCache }) {
                return cached.status
            }
            let simVol = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.simulatedVolume }
            return PlayerStatus(volume: simVol)
        }

        return assemblePlayerStatusLocked(
            sample: sample,
            isRadio: isRadio,
            stationName: stationName,
            isCustom: isCustom,
            customQueue: customQueue,
            customIndex: customIndex,
            customName: customName,
            storeRepMode: storeRepMode,
            origPl: origPl
        )
    }

    func sampleMusicAppStatusLocked(
        isRadio: Bool,
        stationName: String?,
        isCustom: Bool,
        customQueue: [TrackInfo],
        customIndex: Int,
        isShufActive: Bool,
        storeRepMode: String,
        lastRepeatSetTime: Date,
        lastShuffleSetTime: Date,
        needsFullRefresh: Bool
    ) -> RawMusicAppStatusSample? {
        var s = RawMusicAppStatusSample()
        let sep = Self.appleScriptFieldSeparator

        // Tier 1: Zero-Stall Lightweight IPC Pulse (~15ms)
        if !needsFullRefresh, let staticMeta = cachedStaticMetadata, Date().timeIntervalSince(staticMeta.fetchedAt) < 30.0 {
            let pulseScript = """
            tell application "Music"
                try
                    with timeout of 1.5 seconds
                        set sep to "\(sep)"
                        set pState to (player state as string)
                        if pState is "stopped" then
                            return "stopped" & sep & "0" & sep & "0" & sep & ""
                        end if
                        set pPos to 0
                        try
                            set pPos to player position
                        end try
                        set curDbId to 0
                        set curName to ""
                        try
                            set ct to current track
                            if ct is not missing value then
                                try
                                    set curDbId to (database ID of ct as integer)
                                end try
                                try
                                    set curName to (name of ct as string)
                                end try
                            end if
                        end try
                        return pState & sep & pPos & sep & curDbId & sep & curName
                    end timeout
                on error
                    return "error"
                end try
            end tell
            """
            let (pulseOk, pulseOut) = AppleScriptExecutor.shared.execute(pulseScript)
            if pulseOk, let pOut = pulseOut, !pOut.isEmpty, pOut != "error" {
                let pParts = pOut.components(separatedBy: sep)
                if pParts.count >= 2 {
                    let candidateState = pParts[0].lowercased()
                    let candidatePos = Double(pParts[1].replacingOccurrences(of: ",", with: ".")) ?? 0.0
                    let candidateDbId: Int? = pParts.count >= 3 ? Int(pParts[2]) : nil
                    let candidateName: String? = pParts.count >= 4 ? pParts[3] : nil
                    if shouldUseLightweightPulse(rawState: candidateState, rawPosition: candidatePos, rawDbId: candidateDbId, rawTrackName: candidateName) {
                        s.rawState = candidateState
                        s.rawPos = candidatePos
                        s.vol = staticMeta.volume
                        s.dur = staticMeta.duration
                        s.tName = staticMeta.name
                        s.tArtist = staticMeta.artist
                        s.tAlbum = staticMeta.album
                        s.dbId = staticMeta.dbId
                        s.persistentId = staticMeta.persistentId
                        s.curPlNameRaw = staticMeta.currentPlaylistName
                        let isRadioPl = Self.isLikelyRadioPlaylistName(
                            s.curPlNameRaw,
                            activeStationName: stationName,
                            isCurrentlyRadio: isRadio,
                            hasLocalFile: staticMeta.hasLoc
                        )
                        let hasNamedNativePlaylist = !isRadioPl
                            && !s.curPlNameRaw.isEmpty
                            && s.curPlNameRaw != "Музыка"
                            && s.curPlNameRaw != "Music"
                            && s.curPlNameRaw != "Медиатека"
                            && s.curPlNameRaw != "Очередь AMR"
                        let preferStoreShuffle = isCustom || isRadio || isRadioPl || candidateState == "stopped" || Date().timeIntervalSince(lastShuffleSetTime) < 5.0 || !hasNamedNativePlaylist
                        let preferStoreRepeat = isCustom || isRadio || isRadioPl || candidateState == "stopped" || Date().timeIntervalSince(lastRepeatSetTime) < 5.0 || !hasNamedNativePlaylist
                        s.shuf = preferStoreShuffle ? isShufActive : (staticMeta.shuffle || isShufActive)
                        s.repMode = preferStoreRepeat ? storeRepMode : staticMeta.repeatMode
                        s.hasLoc = staticMeta.hasLoc
                        s.knd = staticMeta.kind
                        s.bRate = staticMeta.bitRate
                        s.sRate = staticMeta.sampleRate
                        s.isFavorited = staticMeta.isFavorited
                        lastPulsePosition = candidatePos
                        _lastPollUsedLightweightPulse = true
                        s.usedLightweightPulse = true
                        return s
                    }
                }
            }
        }

        // Tier 2: Full Static Metadata Query
        let script = """
        tell application "Music"
            try
                with timeout of 2.5 seconds
                    set sep to "\(sep)"
                    set pState to (player state as string)
                    set pVol to 100
                    try
                        set pVol to sound volume
                    end try
                    set sRep to "off"
                    try
                        set sRep to (song repeat as string)
                    end try
                    if pState is "stopped" then
                        return "stopped" & sep & "0" & sep & pVol & sep & "0" & sep & "" & sep & "" & sep & "" & sep & "0" & sep & "false" & sep & sRep & sep & "false" & sep & "" & sep & "" & sep & "0" & sep & "0" & sep & "false" & sep & ""
                    end if
                    set pPos to 0
                    try
                        set pPos to player position
                    end try
                    set shuf to false
                    try
                        set shuf to (shuffle enabled as boolean)
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
                        set pid to ""
                        try
                            set pid to (persistent ID of ct as string)
                        end try
                        return pState & sep & pPos & sep & pVol & sep & dur & sep & nm & sep & art & sep & alb & sep & dbid & sep & shuf & sep & sRep & sep & hasLoc & sep & plName & sep & knd & sep & br & sep & sr & sep & isFav & sep & pid
                    end if
                    return pState & sep & pPos & sep & pVol & sep & "0" & sep & "" & sep & "" & sep & "" & sep & "0" & sep & shuf & sep & sRep & sep & "false" & sep & plName & sep & "" & sep & "0" & sep & "0" & sep & "false" & sep & ""
                end timeout
            on error
                return "error"
            end try
        end tell
        """

        let (ok, rawOut) = AppleScriptExecutor.shared.execute(script)
        guard ok, let out = rawOut, !out.isEmpty, out != "error" else {
            return nil
        }

        let parts = out.components(separatedBy: sep)
        guard parts.count >= 12 else {
            return nil
        }

        s.rawState = parts[0].lowercased()
        s.rawPos = Double(parts[1].replacingOccurrences(of: ",", with: ".")) ?? 0.0
        s.vol = Int(parts[2]) ?? 100
        s.dur = Double(parts[3].replacingOccurrences(of: ",", with: ".")) ?? 0.0
        s.tName = parts[4]
        s.tArtist = parts[5]
        s.tAlbum = parts[6]
        s.dbId = Int(parts[7]) ?? 0
        let rawShuf = (parts[8].lowercased() == "true")
        let rawRepLower = parts[9].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rawRep = ["off", "one", "all"].contains(rawRepLower) ? rawRepLower : "off"
        s.hasLoc = (parts[10].lowercased() == "true")
        s.curPlNameRaw = parts[11]
        let isRadioPl = Self.isLikelyRadioPlaylistName(
            s.curPlNameRaw,
            activeStationName: stationName,
            isCurrentlyRadio: isRadio,
            hasLocalFile: s.hasLoc
        )
        let hasNamedNativePlaylist = !isRadioPl
            && !s.curPlNameRaw.isEmpty
            && s.curPlNameRaw != "Музыка"
            && s.curPlNameRaw != "Music"
            && s.curPlNameRaw != "Медиатека"
            && s.curPlNameRaw != "Очередь AMR"
        let preferStoreShuffle = isCustom || isRadio || isRadioPl || s.rawState == "stopped" || Date().timeIntervalSince(lastShuffleSetTime) < 5.0 || !hasNamedNativePlaylist
        let preferStoreRepeat = isCustom || isRadio || isRadioPl || s.rawState == "stopped" || Date().timeIntervalSince(lastRepeatSetTime) < 5.0 || !hasNamedNativePlaylist
        s.shuf = preferStoreShuffle ? isShufActive : (rawShuf || isShufActive)
        s.repMode = preferStoreRepeat ? storeRepMode : rawRep
        s.knd = parts.count > 12 ? parts[12] : ""
        s.bRate = parts.count > 13 ? (Int(parts[13]) ?? 0) : 0
        s.sRate = parts.count > 14 ? (Int(parts[14]) ?? 0) : 0
        s.isFavorited = parts.count > 15 ? (parts[15].lowercased() == "true") : false
        s.persistentId = parts.count > 16 ? parts[16].trimmingCharacters(in: .whitespacesAndNewlines) : ""

        let isDLNAMuted = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isDLNAMuted }
        if CoreAudioDeviceManager.shared.isMutingGuardActive {
            if isDLNAMuted {
                s.vol = 0
            } else if AudioDuckingController.shared.isDucked {
                s.vol = AudioDuckingController.shared.currentDuckedVolume
            } else if PlaybackStateStore.shared.isVolumeLockedTo100 {
                s.vol = 100
            } else {
                s.vol = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.simulatedVolume }
            }
        } else if PlaybackStateStore.shared.isVolumeLockedTo100 && !isDLNAMuted && s.vol != 100 && !AudioDuckingController.shared.isDucked {
            PlaybackTransportController.shared.checkAndEnforceVolumeLock()
            s.vol = 100
        }

        if isCustom && customIndex < customQueue.count {
            let curQueueTrack = customQueue[customIndex]
            if s.dur <= 0 && curQueueTrack.duration > 0 {
                let isNumeric = !s.tName.isEmpty && s.tName.allSatisfy { $0.isNumber }
                if s.tName.isEmpty || isNumeric || QueueManager.shared.isTrackMatching(expected: curQueueTrack, candidateName: s.tName, candidateArtist: s.tArtist) {
                    s.dur = curQueueTrack.duration
                    if s.tAlbum.isEmpty && !curQueueTrack.album.isEmpty {
                        s.tAlbum = curQueueTrack.album
                    }
                }
            }
        }

        let meta = StaticTrackMetadata(
            dbId: s.dbId,
            persistentId: s.persistentId,
            name: s.tName,
            artist: s.tArtist,
            album: s.tAlbum,
            duration: s.dur,
            hasLoc: s.hasLoc,
            kind: s.knd,
            bitRate: s.bRate,
            sampleRate: s.sRate,
            isFavorited: s.isFavorited,
            currentPlaylistName: s.curPlNameRaw,
            shuffle: s.shuf,
            repeatMode: s.repMode,
            volume: s.vol,
            fetchedAt: Date()
        )
        PlaybackStateStore.shared.withLock {
            self.cachedStaticMetadata = meta
            PlaybackStateStore.shared.simulatedVolume = s.vol
            PlaybackStateStore.shared.needsStaticMetadataRefresh = false
            if !preferStoreRepeat {
                PlaybackStateStore.shared.repeatMode = rawRep
            }
        }
        lastPulsePosition = s.rawPos
        _lastPollUsedLightweightPulse = false
        return s
    }
}
