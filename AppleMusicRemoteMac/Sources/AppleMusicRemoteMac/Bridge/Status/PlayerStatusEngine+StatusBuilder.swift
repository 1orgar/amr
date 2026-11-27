//
//  PlayerStatusEngine+StatusBuilder.swift
//  AppleMusicRemoteMac
//
//  Assembles Radio, Stopped, and Active-Track PlayerStatus snapshots from raw Music.app samples.
//

import Foundation

extension PlayerStatusEngine {

    func assemblePlayerStatusLocked(
        sample: RawMusicAppStatusSample,
        isRadio: Bool,
        stationName: String?,
        isCustom: Bool,
        customQueue: [TrackInfo],
        customIndex: Int,
        customName: String?,
        storeRepMode: String,
        origPl: String?
    ) -> PlayerStatus {
        let rawState = sample.rawState
        var rawPos = sample.rawPos
        let vol = sample.vol
        var dur = sample.dur
        var tName = sample.tName
        var tArtist = sample.tArtist
        var tAlbum = sample.tAlbum
        var dbId = sample.dbId
        var persistentId = sample.persistentId
        let shuf = sample.shuf
        let repMode = sample.repMode
        var hasLoc = sample.hasLoc
        let curPlNameRaw = sample.curPlNameRaw
        var knd = sample.knd
        var bRate = sample.bRate
        var sRate = sample.sRate
        var isFavorited = sample.isFavorited

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

        // Honor active AutoMix / Smart Cross-Fade overlap (`OverlappedTransitionState` before `pivotPoint`):
        // while `Music.app` already plays the incoming track in speakers (`smartTransitionWillBegin`)
        // yet AppleScript `current track` still reports the fading-out outgoing track, keep AMR's UI
        // locked onto the incoming track with live interpolated position (`initialPosition + elapsed`).
        var activeOverlapIncomingTrack: TrackInfo? = nil
        if let ov = PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.activeOverlapTransition }) {
            let elapsed = Date().timeIntervalSince(ov.startedAt)
            if stateStr != "playing" || elapsed >= 15.0 {
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.activeOverlapTransition = nil
                }
            } else if !tName.isEmpty {
                let normSample = QueueManager.shared.normalizeTrackTitle(tName)
                let normOutgoing = QueueManager.shared.normalizeTrackTitle(ov.outgoingName)
                let matchesIncoming = QueueManager.shared.isTrackMatching(
                    expected: ov.incomingTrack,
                    candidateName: tName,
                    candidateArtist: tArtist,
                    candidateDbId: dbId > 0 ? dbId : nil
                )
                let isStillOutgoing = !normOutgoing.isEmpty && (
                    tName.localizedCaseInsensitiveCompare(ov.outgoingName) == .orderedSame
                    || normSample == normOutgoing
                )
                if matchesIncoming && (!isStillOutgoing || ov.incomingTrack.name.localizedCaseInsensitiveCompare(ov.outgoingName) == .orderedSame) {
                    PlaybackStateStore.shared.withLock {
                        PlaybackStateStore.shared.activeOverlapTransition = nil
                    }
                } else if isStillOutgoing {
                    let inc = ov.incomingTrack
                    activeOverlapIncomingTrack = inc
                    tName = inc.name
                    if !inc.artist.isEmpty { tArtist = inc.artist }
                    if !inc.album.isEmpty { tAlbum = inc.album }
                    if inc.duration > 0 { dur = inc.duration }
                    dbId = max(0, inc.numericId ?? 0)
                    persistentId = inc.persistentId ?? ""
                    hasLoc = inc.isLocal ?? false
                    knd = ""
                    bRate = 0
                    sRate = inc.sampleRate ?? 0
                    isFavorited = inc.favorited
                    rawPos = ov.initialPosition + max(0.0, elapsed)
                    if dur > 0 {
                        rawPos = min(rawPos, dur)
                    }
                }
            }
        }

        let matchedQueueTrackForKey: TrackInfo? = {
            guard isCustom, customIndex >= 0, customIndex < customQueue.count, !tName.isEmpty else { return nil }
            let expected = customQueue[customIndex]
            if QueueManager.shared.matchesExpectedQueueTrack(
                expected,
                candidateName: tName,
                candidateArtist: tArtist,
                candidateDbId: dbId > 0 ? dbId : nil
            ) {
                return expected
            }
            return nil
        }()
        let canonicalArtistForKey = (matchedQueueTrackForKey?.artist.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? tArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonicalTitleForKey = (matchedQueueTrackForKey?.name.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? tName.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonicalKey = (!tName.isEmpty)
            ? "\(canonicalArtistForKey.lowercased()):\(canonicalTitleForKey.lowercased())"
            : ""
        if !canonicalKey.isEmpty {
            if let favOverride = PlaybackStateStore.shared.withLock({ self.lookupFavoritedOverrideLocked(for: canonicalKey) }) {
                isFavorited = favOverride
            }
        }
        let lowerKind = knd.lowercased()
        let isAppleMusicCatalogDownload = hasLoc && (lowerKind.contains("hls") || lowerKind.contains("apple music"))
        let matchedCatalogId: String? = matchedQueueTrackForKey.flatMap { MusicKitManager.extractNumericCatalogId(from: $0) }
            ?? activeOverlapIncomingTrack.flatMap { MusicKitManager.extractNumericCatalogId(from: $0) }
        if !canonicalKey.isEmpty && stateStr == "playing" {
            if lastCanonicalTrackKey != canonicalKey {
                var preRate: Double? = nil
                var preDepth: Int? = nil
                if let cached = BitPerfectLogMonitor.shared.getCachedFormat(artist: canonicalArtistForKey, title: canonicalTitleForKey, catalogId: matchedCatalogId)
                    ?? (matchedCatalogId == nil ? BitPerfectLogMonitor.shared.getCachedFormat(artist: tArtist, title: tName) : nil) {
                    preRate = cached.sampleRate
                    preDepth = cached.bitDepth
                } else if hasLoc && !isAppleMusicCatalogDownload && sRate > 0 {
                    let locQuality = AudioQualityDetector.determineAudioQuality(kind: knd, bitRate: bRate, sampleRate: sRate)
                    let locIsLossless = !locQuality.contains("AAC") && !locQuality.contains("MP3")
                    preRate = Double(sRate)
                    preDepth = !locIsLossless ? 16 : ((sRate >= 48000) ? 24 : (bRate > 1000 ? 24 : 16))
                }
                NSLog("[PlayerStatusEngine] 🎵 Track changed to '%@' (pre-inspected format: %@)", canonicalKey, preRate != nil ? "\(preRate! / 1000.0) kHz" : "awaiting ALAC decoder")
                BitPerfectLogMonitor.shared.resetTrackState(trackKey: canonicalKey, catalogId: matchedCatalogId, expectedSampleRate: preRate, expectedBitDepth: preDepth)
                lastCanonicalTrackKey = canonicalKey
            }
        } else if stateStr == "stopped" && lastCanonicalTrackKey != nil {
            lastCanonicalTrackKey = nil
            BitPerfectLogMonitor.shared.resetTrackState()
        }

        let isStreamTrack = (!hasLoc && !tName.isEmpty)
        let isRadioPlaylistContainer = Self.isLikelyRadioPlaylistName(
            curPlNameRaw,
            activeStationName: stationName,
            isCurrentlyRadio: isRadio,
            hasLocalFile: hasLoc
        )
        var isRadioDetected = isRadio
        var effectiveStationName = stationName
        if isCustom {
            isRadioDetected = false
        } else if isRadioPlaylistContainer {
            isRadioDetected = true
            let resolvedStation = (stationName?.isEmpty == false) ? stationName! : curPlNameRaw
            effectiveStationName = resolvedStation
            if !isRadio || stationName == nil {
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.isRadioPlayback = true
                    PlaybackStateStore.shared.isShuffleQueueActive = false
                    if PlaybackStateStore.shared.repeatMode == "all" {
                        PlaybackStateStore.shared.repeatMode = "off"
                    }
                    if PlaybackStateStore.shared.activeStationName == nil && !resolvedStation.isEmpty {
                        PlaybackStateStore.shared.activeStationName = resolvedStation
                    }
                }
            }
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
        } else if isStreamTrack && curPlNameRaw.isEmpty && (knd.lowercased().contains("stream") || knd.lowercased().contains("поток") || tName.lowercased().hasPrefix("станция:") || tName.lowercased().hasPrefix("station:") || dur <= 0) {
            isRadioDetected = true
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.isRadioPlayback = true
                PlaybackStateStore.shared.isShuffleQueueActive = false
                if PlaybackStateStore.shared.repeatMode == "all" {
                    PlaybackStateStore.shared.repeatMode = "off"
                }
            }
        }

        let pos = computeOptimisticPosition(rawPosition: rawPos, isPlaying: (stateStr == "playing"), duration: dur)

        // 1. Radio / Station Playback Mode
        if isRadioDetected {
            return buildRadioPlayerStatusLocked(
                stateStr: stateStr,
                pos: pos,
                dur: dur,
                vol: vol,
                repMode: repMode,
                tName: tName,
                tArtist: tArtist,
                tAlbum: tAlbum,
                dbId: dbId,
                persistentId: persistentId,
                isFavorited: isFavorited,
                effectiveStationName: effectiveStationName,
                stationName: stationName
            )
        }

        // 2. Stopped state handling
        if stateStr == "stopped" {
            return buildStoppedPlayerStatusLocked(
                stateStr: stateStr,
                vol: vol,
                shuf: shuf,
                storeRepMode: storeRepMode,
                isCustom: isCustom,
                customQueue: customQueue,
                customIndex: customIndex,
                customName: customName
            )
        }

        // 3. Active Track / Queue Mode
        if isCustom && customIndex < customQueue.count {
            let curQueueTrack = customQueue[customIndex]
            let isNumeric = !tName.isEmpty && tName.allSatisfy { $0.isNumber }
            if tName.isEmpty || isNumeric {
                tName = !curQueueTrack.name.isEmpty ? curQueueTrack.name : tName
                tArtist = !curQueueTrack.artist.isEmpty ? curQueueTrack.artist : tArtist
                tAlbum = !curQueueTrack.album.isEmpty ? curQueueTrack.album : tAlbum
                if dur <= 0 { dur = curQueueTrack.duration }
            } else if dur <= 0 && curQueueTrack.duration > 0 && QueueManager.shared.isTrackMatching(expected: curQueueTrack, candidateName: tName, candidateArtist: tArtist) {
                dur = curQueueTrack.duration
                if tAlbum.isEmpty && !curQueueTrack.album.isEmpty {
                    tAlbum = curQueueTrack.album
                }
            }
        }

        var currentPlName = "Музыка"
        if isCustom, let qn = customName, !qn.isEmpty {
            currentPlName = qn
        } else if !curPlNameRaw.isEmpty && curPlNameRaw != "Музыка" && curPlNameRaw != "Music" && curPlNameRaw != "Медиатека" {
            if curPlNameRaw == "Очередь AMR" {
                if let orig = origPl, !orig.isEmpty, orig != "Очередь AMR" {
                    currentPlName = orig
                } else {
                    currentPlName = "Очередь"
                }
            } else {
                currentPlName = curPlNameRaw
            }
        } else if let orig = origPl, !orig.isEmpty, orig != "Очередь AMR" {
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
            let encName = tName.amrQueryValueEncoded
            let encArtist = tArtist.amrQueryValueEncoded
            let encAlbum = tAlbum.amrQueryValueEncoded
            var artUrl = ""

            if hasLoc && dbId > 0 {
                artUrl = "/api/artwork/track?id=\(dbId)&name=\(encName)&artist=\(encArtist)&album=\(encAlbum)"
            }

            if artUrl.isEmpty, let ovArt = activeOverlapIncomingTrack?.artworkUrl, !ovArt.isEmpty {
                artUrl = ovArt
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
            var resolvedCatalogId: String? = nil
            if let mCid = matchedCatalogId, AppleSoundCheckService.isValidCatalogId(mCid) {
                resolvedCatalogId = mCid
                MusicKitManager.shared.cacheTrackCatalogId(mCid, name: tName, artist: tArtist, album: tAlbum)
            }
            if resolvedCatalogId == nil, isCustom && customIndex < customQueue.count {
                let curQueueTrack = customQueue[customIndex]
                if curQueueTrack.name.caseInsensitiveCompare(tName) == .orderedSame {
                    let cid = curQueueTrack.catalogId ?? curQueueTrack.id
                    if AppleSoundCheckService.isValidCatalogId(cid) {
                        resolvedCatalogId = cid
                        MusicKitManager.shared.cacheTrackCatalogId(cid, name: tName, artist: tArtist, album: tAlbum)
                    }
                }
            }
            if resolvedCatalogId == nil, let matchTrack = customQueue.first(where: {
                $0.name.caseInsensitiveCompare(tName) == .orderedSame &&
                $0.artist.caseInsensitiveCompare(tArtist) == .orderedSame
            }) {
                let cid = matchTrack.catalogId ?? matchTrack.id
                if AppleSoundCheckService.isValidCatalogId(cid) {
                    resolvedCatalogId = cid
                    MusicKitManager.shared.cacheTrackCatalogId(cid, name: tName, artist: tArtist, album: tAlbum)
                }
            }
            if resolvedCatalogId == nil, let ovTrack = activeOverlapIncomingTrack {
                let cid = ovTrack.catalogId ?? ovTrack.id
                if AppleSoundCheckService.isValidCatalogId(cid) {
                    resolvedCatalogId = cid
                    MusicKitManager.shared.cacheTrackCatalogId(cid, name: tName, artist: tArtist, album: tAlbum)
                }
            }
            if resolvedCatalogId == nil,
               let cachedCid = MusicKitManager.shared.getCachedTrackCatalogId(name: tName, artist: tArtist, album: tAlbum),
               AppleSoundCheckService.isValidCatalogId(cachedCid) {
                resolvedCatalogId = cachedCid
            }

            let cachedFmt = BitPerfectLogMonitor.shared.getCachedFormat(artist: tArtist, title: tName, catalogId: resolvedCatalogId)
            let isLiveFormatLocked = BitPerfectLogMonitor.shared.isFormatLockedForCurrentTrack && BitPerfectLogMonitor.shared.currentIsLossless
            let isAuthoritativeLiveLossless = isLiveFormatLocked && BitPerfectLogMonitor.shared.isAuthoritativelyLocked
            let detectedRate = BitPerfectLogMonitor.shared.currentDetectedSampleRate.map { Int($0) }
            let detectedDepth = BitPerfectLogMonitor.shared.currentDetectedBitDepth
            let isStreamLossless = (cachedFmt != nil) || (BitPerfectLogMonitor.shared.currentIsLossless && detectedRate != nil)
            let effectiveTrackRate: Int?
            let effectiveTrackDepth: Int?
            if isAuthoritativeLiveLossless, let liveRate = detectedRate {
                effectiveTrackRate = liveRate
                effectiveTrackDepth = detectedDepth ?? (liveRate >= 48000 ? 24 : 16)
            } else if hasLoc && !isAppleMusicCatalogDownload && sRate > 0 {
                effectiveTrackRate = sRate
                effectiveTrackDepth = !isLocalLossless ? 16 : ((sRate >= 48000) ? 24 : (bRate > 1000 ? 24 : (detectedDepth ?? 16)))
            } else if isStreamLossless {
                effectiveTrackRate = isLiveFormatLocked ? (detectedRate ?? cachedFmt.map { Int($0.sampleRate) }) : (cachedFmt.map { Int($0.sampleRate) } ?? detectedRate)
                if let d = isLiveFormatLocked ? (detectedDepth ?? cachedFmt?.bitDepth) : (cachedFmt?.bitDepth ?? detectedDepth) {
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
                bitDepth: effectiveTrackDepth,
                catalogId: resolvedCatalogId,
                persistentId: persistentId.isEmpty ? nil : persistentId
            )
        }

        if stateStr == "playing" && hasLoc && !isAppleMusicCatalogDownload && sRate > 0 && BitPerfectLogMonitor.shared.isEnabled {
            let depth = !isLocalLossless ? 16 : (sRate >= 48000 ? 24 : (bRate > 1000 ? 24 : 16))
            BitPerfectLogMonitor.shared.reportLocalTrackFormat(sampleRate: Double(sRate), bitDepth: depth, isLossless: isLocalLossless)
        }

        let isLosslessTrack: Bool = {
            if hasLoc && !isAppleMusicCatalogDownload {
                return isLocalLossless || (BitPerfectLogMonitor.shared.isFormatLockedForCurrentTrack && BitPerfectLogMonitor.shared.isAuthoritativelyLocked && BitPerfectLogMonitor.shared.currentIsLossless && BitPerfectLogMonitor.shared.currentDetectedSampleRate != nil)
            }
            return (BitPerfectLogMonitor.shared.getCachedFormat(artist: tArtist, title: tName, catalogId: trackObj?.catalogId) != nil)
                || (BitPerfectLogMonitor.shared.currentIsLossless && BitPerfectLogMonitor.shared.currentDetectedSampleRate != nil)
        }()
        let activeSourceRate = trackObj?.sampleRate.map { Double($0) } ?? (isLosslessTrack ? BitPerfectLogMonitor.shared.currentDetectedSampleRate : 44100.0)
        let activeSourceDepth = !isLosslessTrack ? 16 : (trackObj?.bitDepth ?? BitPerfectLogMonitor.shared.currentDetectedBitDepth)
        if BitPerfectLogMonitor.shared.isEnabled || isAppleMusicCatalogDownload {
            if isLosslessTrack, let rate = activeSourceRate {
                let depth = activeSourceDepth ?? (rate >= 48000.0 ? 24 : 16)
                let khz = rate / 1000.0
                let khzStr = (khz.truncatingRemainder(dividingBy: 1) == 0) ? String(format: "%.0f", khz) : String(format: "%.1f", khz)
                if rate > 48000.0 {
                    curQuality = "Hi-Res Lossless (ALAC \(depth)-bit/\(khzStr)kHz)"
                } else {
                    curQuality = "Lossless (ALAC \(depth)-bit/\(khzStr)kHz)"
                }
            } else if !hasLoc || isAppleMusicCatalogDownload {
                curQuality = "AAC (256 kbps)"
            }
        }

        var status = PlayerStatus(
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
            audioDeviceName: AMRLocalization.tr("Audio Device", "Аудиоустройство"),
            audioDeviceSampleRate: 44100.0,
            audioDeviceBitDepth: activeSourceDepth ?? 16,
            isBitPerfect: false
        )
        applyLiveAudioPipelineOverlay(to: &status, updateTapFormatIfNeeded: stateStr != "stopped")

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastPlayerStatusCache = (Date(), status)
        }
        return status
    }

    func buildRadioPlayerStatusLocked(
        stateStr: String,
        pos: Double,
        dur: Double,
        vol: Int,
        repMode: String,
        tName: String,
        tArtist: String,
        tAlbum: String,
        dbId: Int,
        persistentId: String,
        isFavorited: Bool,
        effectiveStationName: String?,
        stationName: String?
    ) -> PlayerStatus {
        let radName = tName.isEmpty ? (effectiveStationName ?? "Apple Music Radio") : tName
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
                let encName = radName.amrQueryValueEncoded
                let encArtist = radArtist.amrQueryValueEncoded
                let encAlbum = tAlbum.amrQueryValueEncoded
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

        let radCatalogId = MusicKitManager.shared.getCachedTrackCatalogId(name: radName, artist: radArtist, album: tAlbum)
        var effectiveRadDur = dur > 0 ? dur : 0
        if effectiveRadDur <= 0 {
            effectiveRadDur = PlaybackStateStore.shared.withLock {
                guard let pinned = PlaybackStateStore.shared.repeatOnePinnedTrack,
                      pinned.name.localizedCaseInsensitiveCompare(radName) == .orderedSame,
                      pinned.duration > 0 else {
                    return 0.0
                }
                return pinned.duration
            }
        }
        let track = TrackInfo(
            id: "\(dbId)",
            numericId: dbId,
            name: radName,
            artist: radArtist,
            album: tAlbum,
            duration: effectiveRadDur,
            hasArtwork: hasArt,
            artworkUrl: artUrl,
            favorited: isFavorited,
            isLocal: false,
            sampleRate: radRate,
            bitDepth: radDepth,
            catalogId: radCatalogId,
            persistentId: persistentId.isEmpty ? nil : persistentId
        )
        if stateStr == "playing" {
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.recordRadioTrackTransitionLocked(current: track, stationName: effectiveStationName ?? stationName)
            }
        }

        let radioRepeatMode = (repMode == "one") ? "one" : "off"
        var status = PlayerStatus(
            playerState: stateStr,
            position: pos,
            duration: effectiveRadDur,
            volume: vol,
            shuffle: false,
            repeatMode: radioRepeatMode,
            playlist: effectiveStationName ?? stationName ?? "Apple Music Radio",
            isRadio: true,
            audioQuality: radQuality,
            track: track,
            audioDeviceName: AMRLocalization.tr("Audio Device", "Аудиоустройство"),
            audioDeviceSampleRate: 44100.0,
            audioDeviceBitDepth: isRadLossless ? radDepth : 16,
            isBitPerfect: false
        )
        applyLiveAudioPipelineOverlay(to: &status, updateTapFormatIfNeeded: stateStr != "stopped")

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastPlayerStatusCache = (Date(), status)
        }
        return status
    }

    func buildStoppedPlayerStatusLocked(
        stateStr: String,
        vol: Int,
        shuf: Bool,
        storeRepMode: String,
        isCustom: Bool,
        customQueue: [TrackInfo],
        customIndex: Int,
        customName: String?
    ) -> PlayerStatus {
        if isCustom && customIndex < customQueue.count {
            let (isActivelyLoadingCloud, loadStage) = PlaybackStateStore.shared.withLock { () -> (Bool, String?) in
                guard !PlaybackStateStore.shared.isUserPaused else { return (false, nil) }
                let waitingCloudStart = !PlaybackStateStore.shared.currentTrackPlaybackConfirmed
                    && !PlaybackRouter.shared.isTestingEnvironment
                    && Date().timeIntervalSince(PlaybackStateStore.shared.lastCloudPlayTime ?? .distantPast) < 8.5
                let loading = PlaybackStateStore.shared.isStagingCloudTrack
                    || PlaybackStateStore.shared.isTransitioningTrack
                    || waitingCloudStart
                let stage = loading ? (PlaybackStateStore.shared.activeLoadingStage ?? "cloud") : nil
                return (loading, stage)
            }
            let isRu = MusicKitManager.shared.isSystemLocaleRussian
            let loadingQuality: String = isActivelyLoadingCloud
                ? (isRu ? "Запуск из облака…" : "Starting Cloud Stream…")
                : "Lossless (ALAC 24-bit/48kHz)"
            let qTrack = customQueue[customIndex]
            let artUrl = qTrack.artworkUrl
            var status = PlayerStatus(
                playerState: isActivelyLoadingCloud ? "playing" : "stopped",
                position: 0,
                duration: qTrack.duration,
                volume: vol,
                shuffle: shuf,
                repeatMode: storeRepMode,
                playlist: customName ?? (isRu ? "Очередь" : "Queue"),
                isRadio: false,
                audioQuality: loadingQuality,
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
            status.isBuffering = isActivelyLoadingCloud
            status.isStagingBuffer = false
            status.loadingStage = loadStage
            applyLiveAudioPipelineOverlay(to: &status, updateTapFormatIfNeeded: false)
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.lastPlayerStatusCache = (Date(), status)
            }
            return status
        }
        var status = PlayerStatus(
            playerState: stateStr,
            position: 0,
            duration: 0,
            volume: vol,
            shuffle: shuf,
            repeatMode: storeRepMode,
            playlist: "Музыка",
            isRadio: false,
            audioQuality: "Lossless (ALAC 24-bit/48kHz)",
            track: nil
        )
        applyLiveAudioPipelineOverlay(to: &status, updateTapFormatIfNeeded: false)
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastPlayerStatusCache = (Date(), status)
        }
        return status
    }
}
