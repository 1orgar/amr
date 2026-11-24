//
//  QueueManager+TrackMatching.swift
//  AppleMusicRemoteMac
//
//  Track identity normalization, cross-script localization confirmation, and foreign track guards.
//

import Foundation
import ScriptingBridge

extension QueueManager {

    private static let bracketRegex = try? NSRegularExpression(pattern: "\\s*[\\[\\(].*?[\\]\\)]", options: [])

    func normalizeTrackTitle(_ title: String) -> String {
        var t = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["станция: ", "станция:", "station: ", "station:"] {
            if t.hasPrefix(prefix) {
                t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if t.hasSuffix(" station") {
            t = String(t.dropLast(" station".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let regex = Self.bracketRegex {
            t = regex.stringByReplacingMatches(in: t, options: [], range: NSRange(location: 0, length: t.utf16.count), withTemplate: "")
        }
        if let dashIdx = t.range(of: " - ") {
            t = String(t[..<dashIdx.lowerBound])
        }
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        t = t.components(separatedBy: allowed.inverted).joined()
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum TitleScript {
        case latin
        case cyrillic
        case cjk
        case other
    }

    func classifyTitleScript(_ text: String) -> TitleScript {
        var hasLatin = false
        var hasCyrillic = false
        var hasCJK = false
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x0400...0x04FF).contains(v) || (0x0500...0x052F).contains(v) {
                hasCyrillic = true
            } else if (0x3040...0x30FF).contains(v) || (0x4E00...0x9FFF).contains(v) || (0xAC00...0xD7AF).contains(v) {
                hasCJK = true
            } else if CharacterSet.letters.contains(scalar) {
                hasLatin = true
            }
        }
        if hasCJK && !hasCyrillic { return .cjk }
        if hasCyrillic && !hasCJK { return .cyrillic }
        if hasLatin && !hasCyrillic && !hasCJK { return .latin }
        return .other
    }

    func isTrackMatching(
        expected: TrackInfo,
        candidateName: String,
        candidateArtist: String? = nil,
        candidateDbId: Int? = nil
    ) -> Bool {
        if let expId = expected.numericId, expId > 0, expId < 10_000_000,
           let candId = candidateDbId, candId > 0, expId == candId {
            return true
        }
        let cn = candidateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cn.isEmpty else { return false }
        let en = expected.name.trimmingCharacters(in: .whitespacesAndNewlines)

        if en.localizedCaseInsensitiveCompare(cn) == .orderedSame {
            return true
        }
        if LibraryService.hasConflictingVersionQualifier(en, cn) {
            return false
        }

        let normEn = normalizeTrackTitle(en)
        let normCn = normalizeTrackTitle(cn)
        if !normEn.isEmpty && normEn == normCn {
            return true
        }

        let libNormEn = LibraryService.normalizeMatchingTitle(en)
        let libNormCn = LibraryService.normalizeMatchingTitle(cn)
        if !libNormEn.isEmpty && libNormEn == libNormCn {
            return true
        }

        if let ca = candidateArtist?.trimmingCharacters(in: .whitespacesAndNewlines), !ca.isEmpty {
            let ea = expected.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let artistsMatch = MusicKitManager.artistsOverlap(ea, ca)
            if artistsMatch {
                if !normEn.isEmpty && !normCn.isEmpty {
                    if normEn.hasPrefix(normCn) || normCn.hasPrefix(normEn) {
                        let minLen = min(normEn.count, normCn.count)
                        let maxLen = max(normEn.count, normCn.count)
                        if minLen >= 3 && Double(minLen) / Double(maxLen) >= 0.6 {
                            return true
                        }
                    }
                }
                let enScript = classifyTitleScript(en)
                let cnScript = classifyTitleScript(cn)
                if (enScript == .latin && (cnScript == .cyrillic || cnScript == .cjk)) ||
                   (cnScript == .latin && (enScript == .cyrillic || enScript == .cjk)) {
                    return true
                }
            }
        }
        return false
    }

    internal func matchesExpectedQueueTrack(
        _ expected: TrackInfo,
        candidateName: String,
        candidateArtist: String? = nil,
        candidateDbId: Int? = nil
    ) -> Bool {
        if isTrackMatching(
            expected: expected,
            candidateName: candidateName,
            candidateArtist: candidateArtist,
            candidateDbId: candidateDbId
        ) {
            return true
        }
        guard !LibraryService.hasConflictingVersionQualifier(expected.name, candidateName) else {
            return false
        }
        var variants = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.activeTrackTitleVariants }
        let expectedCid = MusicKitManager.extractNumericCatalogId(from: expected)
        for v in MusicKitManager.shared.cachedTitleVariants(catalogId: expectedCid)
            where !variants.contains(where: { $0.name == v.name && $0.artist == v.artist }) {
            variants.append(v)
        }
        for variant in variants where !variant.name.isEmpty {
            let probe = TrackInfo(
                id: expected.id,
                numericId: nil,
                name: variant.name,
                artist: variant.artist.isEmpty ? expected.artist : variant.artist,
                album: expected.album,
                duration: expected.duration
            )
            if isTrackMatching(expected: probe, candidateName: candidateName, candidateArtist: candidateArtist) {
                return true
            }
        }
        return false
    }

    internal func isDrainingPreviousTrack(
        candidateName: String,
        candidateArtist: String?,
        confirmed: Bool,
        timeSincePlay: TimeInterval
    ) -> Bool {
        guard !confirmed, timeSincePlay < 6.0 else { return false }
        let prevKey = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.transitionPreviousTrackKey }
        guard let pk = prevKey, !pk.isEmpty, pk != ":" else { return false }
        return canonicalForeignTrackKey(name: candidateName, artist: candidateArtist) == pk
    }

    func persistConfirmedAlternateSeedIfNeeded(
        expected: TrackInfo,
        confirmedName: String,
        confirmedArtist: String?
    ) {
        let origId = expected.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let origNum = Int(origId), origNum >= 1_000_000,
              let usedRaw = expected.catalogId?.trimmingCharacters(in: .whitespacesAndNewlines),
              let usedNum = Int(usedRaw), usedNum >= 1_000_000,
              usedRaw != origId else {
            return
        }
        let recName = confirmedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? expected.name : confirmedName
        let recArtist = (confirmedArtist ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? expected.artist : (confirmedArtist ?? "")
        MusicKitManager.shared.recordPreferredAlternateCatalogSong(
            for: origId,
            alternate: (id: usedRaw, name: recName, artist: recArtist)
        )
    }

    func tryRecoverMismatchedCloudSeedIfNeeded(
        expected: TrackInfo,
        activeIdx: Int,
        candidateName: String,
        candidateArtist: String?
    ) -> Bool {
        guard !PlaybackRouter.shared.isTestingEnvironment, PlaybackRouter.shared.urlOpener == nil else {
            return false
        }
        let candKey = canonicalForeignTrackKey(name: candidateName, artist: candidateArtist)

        // Pre-flight localized variant check: first check 0 ms RAM cache; if cold, verify asynchronously inside the recovery Task BEFORE stopping Music.app!
        let seedToVerifyVariants: (gen: UInt64, seedId: String)? = PlaybackStateStore.shared.withLock {
            guard !PlaybackStateStore.shared.currentTrackPlaybackConfirmed,
                  !PlaybackStateStore.shared.isUserPaused,
                  PlaybackStateStore.shared.activeTrackTitleVariants.isEmpty,
                  PlaybackStateStore.shared.activeCustomQueueIndex == activeIdx else {
                return nil
            }
            let curTrack = (activeIdx >= 0 && activeIdx < PlaybackStateStore.shared.activeCustomQueue.count)
                ? PlaybackStateStore.shared.activeCustomQueue[activeIdx]
                : expected
            let rawCid = (curTrack.catalogId ?? curTrack.id).trimmingCharacters(in: .whitespacesAndNewlines)
            guard Int(rawCid) != nil else { return nil }
            return (PlaybackStateStore.shared.playbackGeneration, rawCid)
        }
        if let (vGen, vSeedId) = seedToVerifyVariants {
            let cachedVariants = MusicKitManager.shared.cachedTitleVariants(catalogId: vSeedId)
            if !cachedVariants.isEmpty {
                PlaybackStateStore.shared.withLock {
                    if PlaybackStateStore.shared.playbackGeneration == vGen {
                        PlaybackStateStore.shared.activeTrackTitleVariants = cachedVariants
                    }
                }
                if matchesExpectedQueueTrack(expected, candidateName: candidateName, candidateArtist: candidateArtist) {
                    PlaybackStateStore.shared.withLock {
                        if PlaybackStateStore.shared.playbackGeneration == vGen {
                            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                            PlaybackStateStore.shared.lastConfirmedTrackTime = Date()
                            PlaybackStateStore.shared.activeLoadingStage = nil
                            PlaybackStateStore.shared.activeLoadingStartedAt = nil
                            PlaybackStateStore.shared.transitionPreviousTrackKey = nil
                            PlaybackStateStore.shared.lastWasPlayingCloud = true
                            PlaybackStateStore.shared.lastSkipTime = .distantPast
                        }
                    }
                    persistConfirmedAlternateSeedIfNeeded(expected: expected, confirmedName: candidateName, confirmedArtist: candidateArtist)
                    PlaybackStateStore.shared.invalidateQueueCache()
                    PlaybackStateStore.shared.invalidateStatusCache()
                    WebSocketServer.shared.broadcastStatus(includeQueue: true)
                    return true
                }
            }
        }

        let maxSeedRecoveryAttempts = 4
        let recoveryContext: (gen: UInt64, originalId: String, badSeedId: String, attempt: Int, triedIds: Set<String>, needsColdVariantCheck: Bool)? = PlaybackStateStore.shared.withLock {
            guard !PlaybackStateStore.shared.currentTrackPlaybackConfirmed,
                  !PlaybackStateStore.shared.isUserPaused,
                  !PlaybackStateStore.shared.triedAlternateCloudSeedForCurrentTrack,
                  PlaybackStateStore.shared.alternateCloudSeedAttemptCount < maxSeedRecoveryAttempts,
                  PlaybackStateStore.shared.activeCustomQueueIndex == activeIdx else {
                return nil
            }
            let curTrack = (activeIdx >= 0 && activeIdx < PlaybackStateStore.shared.activeCustomQueue.count)
                ? PlaybackStateStore.shared.activeCustomQueue[activeIdx]
                : expected
            let origId = curTrack.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawCid = (curTrack.catalogId ?? curTrack.id).trimmingCharacters(in: .whitespacesAndNewlines)
            let coldVariants = PlaybackStateStore.shared.activeTrackTitleVariants.isEmpty && Int(rawCid) != nil
            PlaybackStateStore.shared.playbackGeneration &+= 1
            PlaybackStateStore.shared.isStagingCloudTrack = true
            let nextAttempt = PlaybackStateStore.shared.alternateCloudSeedAttemptCount + 1
            PlaybackStateStore.shared.alternateCloudSeedAttemptCount = nextAttempt
            PlaybackStateStore.shared.triedAlternateCloudSeedForCurrentTrack = (nextAttempt >= maxSeedRecoveryAttempts)
            if Int(origId) != nil {
                PlaybackStateStore.shared.triedCloudSeedIdsForCurrentTrack.insert(origId)
            }
            if Int(rawCid) != nil {
                PlaybackStateStore.shared.triedCloudSeedIdsForCurrentTrack.insert(rawCid)
            }
            PlaybackStateStore.shared.transitionPreviousTrackKey = (candKey.isEmpty || candKey == ":") ? nil : candKey
            let now = Date()
            PlaybackStateStore.shared.lastCloudPlayTime = now
            PlaybackStateStore.shared.lastSkipTime = now
            return (
                PlaybackStateStore.shared.playbackGeneration,
                origId,
                rawCid,
                nextAttempt,
                PlaybackStateStore.shared.triedCloudSeedIdsForCurrentTrack,
                coldVariants
            )
        }
        guard let (capturedGen, originalId, badSeedId, attemptNum, triedIds, needsColdVariantCheck) = recoveryContext else { return false }

        Task.detached(priority: .userInitiated) { [weak self] in
            defer {
                PlaybackStateStore.shared.withLock {
                    if PlaybackStateStore.shared.playbackGeneration == capturedGen {
                        PlaybackStateStore.shared.isStagingCloudTrack = false
                    }
                }
            }
            guard let self = self else { return }

            // 1. Async localized CJK/Cyrillic variant check (~150 ms parallel `async let`) BEFORE stopping Music.app!
            if needsColdVariantCheck {
                let fetchedVariants = await MusicKitManager.shared.resolveCatalogSongTitleVariants(catalogId: badSeedId)
                if !fetchedVariants.isEmpty {
                    PlaybackStateStore.shared.withLock {
                        if PlaybackStateStore.shared.playbackGeneration == capturedGen {
                            PlaybackStateStore.shared.activeTrackTitleVariants = fetchedVariants
                        }
                    }
                    if self.matchesExpectedQueueTrack(expected, candidateName: candidateName, candidateArtist: candidateArtist) {
                        PlaybackStateStore.shared.withLock {
                            guard PlaybackStateStore.shared.playbackGeneration == capturedGen else { return }
                            PlaybackStateStore.shared.alternateCloudSeedAttemptCount = max(0, attemptNum - 1)
                            PlaybackStateStore.shared.triedAlternateCloudSeedForCurrentTrack = false
                            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                            PlaybackStateStore.shared.lastConfirmedTrackTime = Date()
                            PlaybackStateStore.shared.activeLoadingStage = nil
                            PlaybackStateStore.shared.activeLoadingStartedAt = nil
                            PlaybackStateStore.shared.transitionPreviousTrackKey = nil
                            PlaybackStateStore.shared.lastWasPlayingCloud = true
                            PlaybackStateStore.shared.lastSkipTime = .distantPast
                        }
                        self.persistConfirmedAlternateSeedIfNeeded(expected: expected, confirmedName: candidateName, confirmedArtist: candidateArtist)
                        PlaybackStateStore.shared.invalidateQueueCache()
                        PlaybackStateStore.shared.invalidateStatusCache()
                        WebSocketServer.shared.broadcastStatus(includeQueue: true)
                        return
                    }
                }
            }

            let stillActiveBeforeStop = PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.playbackGeneration == capturedGen && !PlaybackStateStore.shared.isUserPaused
            }
            guard stillActiveBeforeStop else { return }

            if Int(badSeedId) != nil {
                PlaybackRouter.markDirectSeedMismatch(catalogId: badSeedId)
            }
            NSLog("[QueueManager] ⚠️ Cloud seed ra.%@ started '%@ — %@' instead of '%@ — %@' — switching to alternate release (attempt #%d/%d)",
                  badSeedId, candidateArtist ?? "", candidateName, expected.artist, expected.name, attemptNum, maxSeedRecoveryAttempts)
            _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop", maxWait: 0.7, reportTimeout: false)
            BitPerfectLogMonitor.shared.resetTrackState()

            let lookupCatalogId: String? = {
                if let n = Int(originalId), n >= 1_000_000 { return originalId }
                if let n = Int(badSeedId), n >= 1_000_000 { return badSeedId }
                return nil
            }()
            var altCandidates = await MusicKitManager.shared.resolveAlternateCatalogSongs(
                catalogId: lookupCatalogId,
                name: expected.name,
                artist: expected.artist,
                excludingIds: triedIds
            )
            if altCandidates.isEmpty, lookupCatalogId != nil {
                altCandidates = await MusicKitManager.shared.resolveAlternateCatalogSongs(
                    catalogId: nil,
                    name: expected.name,
                    artist: expected.artist,
                    excludingIds: triedIds
                )
            }

            let eligiblePrefix = Array(
                altCandidates
                    .filter { !triedIds.contains($0.id) && !PlaybackRouter.hasDirectSeedMismatch(catalogId: $0.id) }
                    .prefix(6)
            )
            var chosenAlt: (id: String, name: String, artist: String)? = nil
            if !eligiblePrefix.isEmpty {
                let winnerIdx: Int? = await withTaskGroup(of: (Int, Bool).self) { group in
                    for (idx, alt) in eligiblePrefix.enumerated() {
                        group.addTask {
                            let info = await MusicKitManager.shared.inspectCatalogSongDirectCloudEligibility(catalogId: alt.id)
                            return (idx, info?.hasStationSeed != false)
                        }
                    }
                    var best: Int? = nil
                    for await (idx, ok) in group where ok {
                        if best == nil || idx < best! {
                            best = idx
                        }
                    }
                    return best
                }
                if let w = winnerIdx {
                    chosenAlt = eligiblePrefix[w]
                }
            }

            let stillCurrentGen = PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.playbackGeneration == capturedGen && !PlaybackStateStore.shared.isUserPaused
            }
            guard stillCurrentGen else { return }

            if let alt = chosenAlt {
                let variants = await MusicKitManager.shared.resolveCatalogSongTitleVariants(catalogId: alt.id)
                let stillValidBeforeOpen = PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.playbackGeneration == capturedGen && !PlaybackStateStore.shared.isUserPaused
                }
                guard stillValidBeforeOpen else { return }
                if PlaybackRouter.shared.openMusicUrl("music://music.apple.com/station/item/ra.\(alt.id)") {
                    let now = Date()
                    PlaybackStateStore.shared.withLock {
                        guard PlaybackStateStore.shared.playbackGeneration == capturedGen else { return }
                        PlaybackStateStore.shared.lastCloudPlayTime = now
                        PlaybackStateStore.shared.lastSkipTime = now
                        PlaybackStateStore.shared.activeLoadingStage = "cloud"
                        PlaybackStateStore.shared.triedCloudSeedIdsForCurrentTrack.insert(alt.id)
                        if !variants.isEmpty {
                            PlaybackStateStore.shared.activeTrackTitleVariants = variants
                        }
                        if activeIdx >= 0 && activeIdx < PlaybackStateStore.shared.activeCustomQueue.count {
                            PlaybackStateStore.shared.activeCustomQueue[activeIdx].catalogId = alt.id
                        }
                    }
                    PlaybackRouter.shared.resumePlaybackIfNeeded(generation: capturedGen)
                    PlaybackStateStore.shared.invalidateStatusCache()
                    WebSocketServer.shared.broadcastStatus(includeQueue: false)
                    NSLog("[QueueManager] 🔄 Dispatched alternate cloud seed ra.%@ (attempt #%d) for '%@ — %@'", alt.id, attemptNum, expected.artist, expected.name)
                    return
                }
            }
            self.advanceOrEndCustomQueueUnlocked(reason: "seed-mismatch-no-alt")
        }
        return true
    }

    func canonicalForeignTrackKey(name: String, artist: String?) -> String {
        let cleanArtist = (artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(cleanArtist):\(cleanName)"
    }

    func canInterceptForeignTrack(
        candidateName: String,
        candidateArtist: String?,
        expectedTrack: TrackInfo,
        timeSincePlay: TimeInterval
    ) -> Bool {
        let now = Date()
        let fKey = canonicalForeignTrackKey(name: candidateName, artist: candidateArtist)
        return PlaybackStateStore.shared.withLock {
            if now.timeIntervalSince(PlaybackStateStore.shared.lastSkipTime) < 3.0 {
                return false
            }
            let foreignCooldown: TimeInterval = (expectedTrack.duration > 0 && expectedTrack.duration < 8.0)
                ? max(1.5, expectedTrack.duration * 0.5)
                : 4.0
            let timeSinceLastForeign = now.timeIntervalSince(PlaybackStateStore.shared.lastForeignInterceptTime)
            if timeSinceLastForeign < foreignCooldown {
                return false
            }
            if !fKey.isEmpty, fKey != ":",
               PlaybackStateStore.shared.lastForeignInterceptKey == fKey,
               timeSinceLastForeign < 12.0 {
                return false
            }
            if PlaybackStateStore.shared.currentTrackPlaybackConfirmed,
               expectedTrack.duration <= 0 || expectedTrack.duration >= 8.0 {
                let timeSinceConfirm = now.timeIntervalSince(PlaybackStateStore.shared.lastConfirmedTrackTime)
                if timeSinceConfirm < 3.5 && timeSincePlay < 5.0 && PlaybackStateStore.shared.lastKnownPosition < 4.0 {
                    return false
                }
            }
            return true
        }
    }

    func recordForeignTrackIntercept(name: String, artist: String?) {
        let now = Date()
        let fKey = canonicalForeignTrackKey(name: name, artist: artist)
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastSkipTime = now
            PlaybackStateStore.shared.lastForeignInterceptTime = now
            PlaybackStateStore.shared.lastForeignInterceptKey = (fKey.isEmpty || fKey == ":") ? nil : fKey
        }
    }

    func isLiveMusicAppAlreadyPlayingExpectedTrack(_ expectedTrack: TrackInfo) -> Bool {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return false }
        guard let app = MusicAppProvider.shared.getMusicApp() else { return false }
        if app.playerState != .playing {
            return true
        }
        guard let ct = app.currentTrack else { return false }
        if let expDbId = expectedTrack.numericId, expDbId > 0, expDbId < 10_000_000, ct.sbDatabaseID == expDbId {
            return true
        }
        let liveName = ct.sbName
        let liveArtist = ct.sbArtist
        if !liveName.isEmpty && isTrackMatching(expected: expectedTrack, candidateName: liveName, candidateArtist: liveArtist) {
            return true
        }
        return false
    }

    func shouldConfirmLocalizedAMRTrackStart(
        expected: TrackInfo,
        candidateName: String,
        candidateArtist: String?,
        liveTrackDbId: Int? = nil
    ) -> Bool {
        // 1. Never confirm if candidate matches a recently played history track (draining notification from previous track)
        let matchesRecentHistory = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.latestHistoryTracks.prefix(2).contains {
                isTrackMatching(expected: $0, candidateName: candidateName, candidateArtist: candidateArtist)
            }
        }
        if matchesRecentHistory {
            return false
        }
        if LibraryService.hasConflictingVersionQualifier(expected.name, candidateName) {
            return false
        }

        // 2. Resolve live Music.app database ID first: if Music.app is demonstrably on a different local/staged dbId, reject immediately!
        let expDbId: Int? = {
            if let nid = expected.numericId, nid > 0, nid < 10_000_000 { return nid }
            return nil
        }()
        let resolvedLiveId: Int? = liveTrackDbId ?? {
            guard !PlaybackRouter.shared.isTestingEnvironment,
                  let app = MusicAppProvider.shared.getMusicApp(),
                  let ct = app.currentTrack else { return nil }
            let id = ct.sbDatabaseID
            return id > 0 ? id : nil
        }()
        if let expId = expDbId, let liveId = resolvedLiveId, liveId != expId {
            return false
        }

        let expArtist = expected.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let candArtist = (candidateArtist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let artistMatches = !expArtist.isEmpty && !candArtist.isEmpty && MusicKitManager.artistsOverlap(expArtist, candArtist)

        let normExpTitle = normalizeTrackTitle(expected.name)
        let normCandTitle = normalizeTrackTitle(candidateName)
        let minTitleLen = min(normExpTitle.count, normCandTitle.count)
        let maxTitleLen = max(normExpTitle.count, normCandTitle.count)
        let titleMatches = !normExpTitle.isEmpty && !normCandTitle.isEmpty && (
            normExpTitle == normCandTitle
            || (minTitleLen >= 4 && Double(minTitleLen) / Double(max(1, maxTitleLen)) >= 0.65 && (normCandTitle.hasPrefix(normExpTitle) || normExpTitle.hasPrefix(normCandTitle)))
        )

        // Check cached catalog ID / official localized title variants
        let expectedCatalogId = MusicKitManager.extractNumericCatalogId(from: expected)
        let candidateCatalogId = MusicKitManager.shared.getCachedTrackCatalogId(name: candidateName, artist: candArtist, album: expected.album)
        let catalogMatches: Bool = {
            if let expCid = expectedCatalogId, !expCid.isEmpty {
                if let candCid = candidateCatalogId, candCid == expCid {
                    return true
                }
                let cachedVars = MusicKitManager.shared.cachedTitleVariants(catalogId: expCid)
                for v in cachedVars where !v.name.isEmpty {
                    let probe = TrackInfo(id: expCid, name: v.name, artist: v.artist.isEmpty ? expArtist : v.artist)
                    if isTrackMatching(expected: probe, candidateName: candidateName, candidateArtist: candArtist) {
                        return true
                    }
                }
            }
            return false
        }()

        if catalogMatches {
            return true
        }

        let titleScriptDiffers = classifyTitleScript(expected.name) != classifyTitleScript(candidateName)
        let artistScriptDiffers = !expArtist.isEmpty && !candArtist.isEmpty && classifyTitleScript(expArtist) != classifyTitleScript(candArtist)

        if artistMatches && (titleMatches || titleScriptDiffers) {
            return true
        }
        if titleMatches && (artistMatches || artistScriptDiffers || expArtist.isEmpty || candArtist.isEmpty) {
            return true
        }

        // Exact database ID confirmation when Music.app is playing the staged track ID (e.g. CJK title + CJK artist vs Romaji metadata)
        if let expId = expDbId {
            // Same artist + same script with non-matching title is a DIFFERENT song by that artist — never confirm!
            if artistMatches && !titleMatches && !titleScriptDiffers {
                return false
            }
            if let liveId = resolvedLiveId, liveId == expId {
                return true
            }
            if PlaybackRouter.shared.isTestingEnvironment && liveTrackDbId == nil {
                return true
            }
        }

        return false
    }
}
