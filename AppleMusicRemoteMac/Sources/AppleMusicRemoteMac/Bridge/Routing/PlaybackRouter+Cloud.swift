//
//  PlaybackRouter+Cloud.swift
//  AppleMusicRemoteMac
//
//  Async cloud track playback, direct seed mismatch tracking, and track script matching.
//

import AppKit
import Foundation

extension PlaybackRouter {
    // MARK: - Cloud Track Playback

    public func playCloud(url: String?, id: String?, name: String?, artist: String?, numericId: Int? = nil, isLocal: Bool? = nil, incrementGeneration: Bool = true) async -> Bool {
        _ = AppleScriptExecutor.shared.execute("tell application \"Music\" to stop")
        BitPerfectLogMonitor.shared.resetTrackState()
        PlaybackStateStore.shared.withLock {
            if incrementGeneration {
                PlaybackStateStore.shared.playbackGeneration &+= 1
            }
            PlaybackStateStore.shared.isStagingCloudTrack = false
            PlaybackStateStore.shared.isActivelyStagingInBuffer = false
            PlaybackStateStore.shared.activeLoadingStage = nil
            PlaybackStateStore.shared.activeLoadingStartedAt = nil
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

        let sep = "||AMR||"

        // 1. If explicitly marked local library track, play directly via once=true
        if numId > 0 && isLocal == true {
            let storeRepeat = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.repeatMode }
            let isRepeatOne = (storeRepeat == "one")
            let appleSongRepeat = isRepeatOne ? "one" : "off"
            let playStatement = isRepeatOne ? "play foundTrack" : "play foundTrack once true"
            let script = """
            tell application "Music"
                try
                    with timeout of 5 seconds
                        set sep to "\(sep)"
                        set foundTrack to missing value
                        try
                            set foundTrack to (first track of user playlist "Очередь AMR" whose database ID is \(numId))
                        end try
                        if foundTrack is missing value then
                            try
                                set foundTrack to (first track of library playlist 1 whose database ID is \(numId))
                            end try
                        end if
                        if foundTrack is missing value then
                            repeat with pl in (get every playlist)
                                try
                                    set foundTrack to (first track of pl whose database ID is \(numId))
                                    if foundTrack is not missing value then exit repeat
                                end try
                            end repeat
                        end if

                        if foundTrack is not missing value then
                            try
                                stop
                            end try
                            set shuffle enabled to false
                            set song repeat to \(appleSongRepeat)
                            set actualDbId to (database ID of foundTrack as integer)
                            set actualName to (name of foundTrack as string)
                            set actualArtist to (artist of foundTrack as string)
                            set actualAlbum to (album of foundTrack as string)
                            set actualDur to (duration of foundTrack as real)
                            try
                                \(playStatement)
                            on error playErr number playErrNum
                                if playErrNum is not -1712 then
                                    play foundTrack
                                end if
                            end try
                            return "ok" & sep & actualDbId & sep & actualName & sep & actualArtist & sep & actualAlbum & sep & actualDur
                        end if
                        return "not_found"
                    end timeout
                on error
                    return "timeout"
                end try
            end tell
            """

            let (ok, res) = AppleScriptExecutor.shared.execute(script, maxWait: 5.5, reportTimeout: false)
            if ok, let out = res, out.hasPrefix("ok" + sep) {
                let parts = out.components(separatedBy: sep)
                let actualId = parts.count > 1 ? (Int(parts[1]) ?? numId) : numId
                let actualName = parts.count > 2 ? parts[2] : (name ?? "")
                let actualArtist = parts.count > 3 ? parts[3] : (artist ?? "")
                let actualAlbum = parts.count > 4 ? parts[4] : ""
                let actualDur = parts.count > 5 ? (Double(parts[5].replacingOccurrences(of: ",", with: ".")) ?? 0) : 0

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

    // MARK: - Direct Cloud Seed Mismatch & Script Matching Helpers

    private static let directSeedMismatchLock = NSLock()
    private static var directSeedMismatchTimestamps: [String: Date] = [:]

    internal static func markDirectSeedMismatch(catalogId: String) {
        let clean = catalogId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        directSeedMismatchLock.withLock {
            if directSeedMismatchTimestamps.count > 400 {
                let cutoff = Date().addingTimeInterval(-300.0)
                directSeedMismatchTimestamps = directSeedMismatchTimestamps.filter { $0.value > cutoff }
            }
            directSeedMismatchTimestamps[clean] = Date()
        }
    }

    internal static func hasDirectSeedMismatch(catalogId: String) -> Bool {
        let clean = catalogId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        return directSeedMismatchLock.withLock {
            guard let ts = directSeedMismatchTimestamps[clean] else { return false }
            if Date().timeIntervalSince(ts) > 300.0 {
                directSeedMismatchTimestamps.removeValue(forKey: clean)
                return false
            }
            return true
        }
    }

    internal static func clearDirectSeedMismatchesForTesting() {
        directSeedMismatchLock.withLock {
            directSeedMismatchTimestamps.removeAll()
        }
    }

    internal func isExpectedCloudTrackAlreadyPlayingInMusicApp(name: String, artist: String) -> Bool {
        guard !isTestingEnvironment, urlOpener == nil else { return false }
        let trimmedExpName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedExpName.isEmpty else { return false }
        let trimmedExpArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let probe = TrackInfo(id: "probe", numericId: nil, name: trimmedExpName, artist: trimmedExpArtist, album: "", duration: 0)
        let sep = "||AMR||"
        let (ok, raw) = AppleScriptExecutor.shared.execute("""
        tell application "Music"
            try
                with timeout of 0.7 seconds
                    if player state is not playing then return "not_playing"
                    set ct to current track
                    if ct is missing value then return "not_playing"
                    return "playing\(sep)" & (name of ct as string) & "\(sep)" & (artist of ct as string)
                end timeout
            on error
                return "err"
            end try
        end tell
        """, maxWait: 1.1, reportTimeout: false)
        guard ok, let out = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        let parts = out.components(separatedBy: sep)
        guard parts.first == "playing", parts.count >= 3 else { return false }
        let liveName = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let liveArtist = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !liveName.isEmpty else { return false }
        return QueueManager.shared.isTrackMatching(expected: probe, candidateName: liveName, candidateArtist: liveArtist)
    }

    internal static func sameScriptTrackMatches(expectedName: String, expectedArtist: String, candidateName: String, candidateArtist: String) -> Bool {
        let en = expectedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cn = candidateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cn.isEmpty else { return false }
        if en.isEmpty { return true }
        if en.localizedCaseInsensitiveCompare(cn) == .orderedSame {
            return true
        }
        if LibraryService.hasConflictingVersionQualifier(en, cn) {
            return false
        }
        let normEn = QueueManager.shared.normalizeTrackTitle(en)
        let normCn = QueueManager.shared.normalizeTrackTitle(cn)
        if !normEn.isEmpty && normEn == normCn {
            return true
        }
        let libEn = LibraryService.normalizeMatchingTitle(en)
        let libCn = LibraryService.normalizeMatchingTitle(cn)
        if !libEn.isEmpty && libEn == libCn {
            return true
        }
        let ea = expectedArtist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ca = candidateArtist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let artistsMatch = !ea.isEmpty && !ca.isEmpty && (ea == ca || ea.contains(ca) || ca.contains(ea))
        if artistsMatch && !normEn.isEmpty && !normCn.isEmpty && (normEn.hasPrefix(normCn) || normCn.hasPrefix(normEn)) {
            let minLen = min(normEn.count, normCn.count)
            let maxLen = max(normEn.count, normCn.count)
            if minLen >= 3 && Double(minLen) / Double(maxLen) >= 0.65 {
                return true
            }
        }
        return false
    }
}
