//
//  LibraryService.swift
//  AppleMusicRemoteMac
//
//  Local library inspection: core state, title/version normalization,
//  and playlist listing with optimistic additions.
//

import AppKit
import Foundation
import ScriptingBridge

public final class LibraryService: @unchecked Sendable {
    public static let shared = LibraryService()

    internal let lock = NSLock()
    internal let playlistsFetchLock = NSLock()
    internal let librarySongsFetchLock = NSLock()
    internal var playlistFetchLocks: [String: NSLock] = [:]
    internal static let maxPlaylistFetchLocks = 128

    internal var playlistsCache: (timestamp: Date, playlists: [PlaylistInfo])?
    internal var recentlyAddedPlaylists: [(addedAt: Date, playlist: PlaylistInfo)] = []
    internal var cloudPlaylistMetadataItems: [CloudLibraryPlaylistMetadata] = []
    internal var cloudPlaylistMetaTimestamp: Date?
    internal static let playlistsCacheTTL: TimeInterval = 20.0
    internal static let recentlyAddedPlaylistTTL: TimeInterval = 120.0
    internal var playlistTracksCache: [String: (timestamp: Date, tracks: [TrackInfo])] = [:]
    internal var rawLibrarySongsCache: (timestamp: Date, tracks: [TrackInfo])?
    internal var subscriptionSongsCache: (timestamp: Date, tracks: [TrackInfo])?
    internal var librarySongsByNormalizedTitle: [String: [TrackInfo]] = [:]
    internal var stagedBufferTracksByNormalizedTitle: [String: [TrackInfo]] = [:]
    internal var cachedHomeFeed: [String: Any]?
    internal var homeFeedTimestamp: Date?

    internal static let removableTitleTags = [
        " (remastered)", " [remastered]", " (remaster)", " [remaster]",
        " (2011 remaster)", " (2013 remaster)", " (deluxe edition)",
        " (deluxe)", " [deluxe]", " (single version)", " (album version)",
        " - single", " - ep"
    ]

    internal static let masterLibraryPlaylistNames: Set<String> = [
        "музыка", "music", "медиатека", "библиотека", "musik", "musique", "música", "musica", "ミュージック", "音乐", "очередь amr", "буфер amr"
    ]

    public static let favoritePlaylistCandidateNames: Set<String> = [
        "любимые песни", "favorite songs", "favorites", "избранное", "favourite songs"
    ]

    public static let protectedSystemPlaylistNames: Set<String> = masterLibraryPlaylistNames.union([
        "любимые песни", "favorites", "favourite songs", "favorite songs",
        "покупки", "purchased", "загружено", "downloaded"
    ])

    public static func isProtectedSystemPlaylist(_ name: String) -> Bool {
        let lower = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }
        return protectedSystemPlaylistNames.contains(lower)
    }

    public static func normalizeMatchingTitle(_ t: String) -> String {
        var s = t.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "ʼ", with: "'")
            .replacingOccurrences(of: "`", with: "'")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "ё", with: "е")
        for tag in removableTitleTags {
            if s.contains(tag) {
                s = s.replacingOccurrences(of: tag, with: "")
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    internal static let liveVersionRegex = try? NSRegularExpression(
        pattern: "(?:[\\(\\[\\-–—]\\s*live\\b|\\blive\\s+(?:at|in|from|on|version|session|recording)\\b|\\blive\\s*[\\)\\]])",
        options: [.caseInsensitive]
    )

    public static func extractVersionQualifiers(_ rawTitle: String) -> Set<String> {
        let low = rawTitle.lowercased()
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "［", with: "[")
            .replacingOccurrences(of: "］", with: "]")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
        var flags = Set<String>()
        if let rx = liveVersionRegex,
           rx.firstMatch(in: low, options: [], range: NSRange(location: 0, length: low.utf16.count)) != nil {
            flags.insert("live")
        }
        if low.contains("off vocal") || low.contains("off-vocal") || low.contains("instrumental") ||
           low.contains("karaoke") || low.contains("backing track") || low.contains("オフボーカル") || low.contains("カラオケ") {
            flags.insert("instrumental")
        }
        if low.contains("remix") || low.contains("vip mix") || low.contains("club mix") || low.contains("dub mix") {
            flags.insert("remix")
        }
        if low.contains("acoustic") || low.contains("unplugged") {
            flags.insert("acoustic")
        }
        if low.contains("(demo") || low.contains("[demo") || low.contains("- demo") {
            flags.insert("demo")
        }
        if low.contains("sped up") || low.contains("nightcore") {
            flags.insert("sped_up")
        }
        if low.contains("slowed") {
            flags.insert("slowed")
        }
        if low.contains("a cappella") || low.contains("acapella") {
            flags.insert("acappella")
        }
        if low.contains("tv size") || low.contains("tv-size") || low.contains("tv ver") || low.contains("anime size") || low.contains("short ver") {
            flags.insert("tv_size")
        }
        return flags
    }

    /// Returns `true` when one title carries a distinct version qualifier (`Live`, `Off Vocal` / `Instrumental`,
    /// `Remix`, `Acoustic`, `Demo`, `Sped Up`, `Slowed`, `A Cappella`) that the other title lacks.
    public static func hasConflictingVersionQualifier(_ lhs: String, _ rhs: String) -> Bool {
        return extractVersionQualifiers(lhs) != extractVersionQualifiers(rhs)
    }

    private init() {}

    // MARK: - Playlist Fetch Lock Management

    internal func acquirePlaylistFetchLockLocked(for name: String) -> NSLock {
        if let existing = playlistFetchLocks[name] {
            return existing
        }
        if playlistFetchLocks.count >= Self.maxPlaylistFetchLocks {
            for key in Array(playlistFetchLocks.keys) {
                guard let candidate = playlistFetchLocks[key] else { continue }
                if candidate.try() {
                    candidate.unlock()
                    playlistFetchLocks.removeValue(forKey: key)
                    if playlistFetchLocks.count < Self.maxPlaylistFetchLocks / 2 {
                        break
                    }
                }
            }
        }
        let newLock = NSLock()
        playlistFetchLocks[name] = newLock
        return newLock
    }

    internal func removeUnlockedPlaylistFetchLocksLocked(where predicate: (String) -> Bool) {
        for key in Array(playlistFetchLocks.keys) where predicate(key) {
            if let existing = playlistFetchLocks[key], existing.try() {
                existing.unlock()
                playlistFetchLocks.removeValue(forKey: key)
            }
        }
    }

    // MARK: - Playlists

    /// Non-blocking check against the in-memory playlists cache (`trackCount > 0`).
    /// Used by `PlayerStatusEngine` to distinguish real user playlists from 0-track Apple Music radio station containers.
    public func hasPopulatedPlaylistsCache() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return playlistsCache != nil
    }

    public func hasCachedUserPlaylist(named name: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty, !Self.masterLibraryPlaylistNames.contains(clean) else { return false }
        lock.lock()
        let playlists = playlistsCache?.playlists ?? []
        let recent = recentlyAddedPlaylists
        lock.unlock()
        if playlists.contains(where: {
            $0.trackCount > 0 && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == clean
        }) {
            return true
        }
        return recent.contains {
            Date().timeIntervalSince($0.addedAt) < Self.recentlyAddedPlaylistTTL &&
            $0.playlist.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == clean
        }
    }

    public func recordRecentlyAddedPlaylist(
        id: String?,
        name: String,
        trackCount: Int = 0,
        artworkUrl: String? = nil
    ) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanId = (id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerName = cleanName.lowercased()
        guard !cleanName.isEmpty, !Self.masterLibraryPlaylistNames.contains(lowerName) else { return }

        let cleanArt = (artworkUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let enc = cleanName.amrQueryValueEncoded
        let effectiveArt: String
        if !cleanArt.isEmpty {
            effectiveArt = cleanArt
            if cleanArt.hasPrefix("http") {
                ArtworkService.shared.setPlaylistArtworkUrl(name: cleanName, url: cleanArt)
            }
        } else {
            effectiveArt = ArtworkService.shared.getCachedPlaylistArtworkUrl(name: cleanName)
                ?? "/api/artwork/playlist?name=\(enc)&v=2"
        }

        let isCatalogPlId = cleanId.lowercased().hasPrefix("pl.")
        var altNames: [String] = [cleanName]
        for alias in Self.canonicalPersonalMixAliases(for: cleanName) {
            if !altNames.contains(where: { Self.normalizePlaylistMatchKey($0) == Self.normalizePlaylistMatchKey(alias) }) {
                altNames.append(alias)
            }
        }
        let optimistic = PlaylistInfo(
            name: cleanName,
            trackCount: max(0, trackCount),
            artworkUrl: effectiveArt,
            isPlaylist: true,
            id: cleanId.isEmpty ? nil : cleanId,
            catalogId: isCatalogPlId ? cleanId : nil,
            alternateNames: altNames.count > 1 ? altNames : nil
        )

        let now = Date()
        lock.lock()
        recentlyAddedPlaylists.removeAll { entry in
            if now.timeIntervalSince(entry.addedAt) >= Self.recentlyAddedPlaylistTTL {
                return true
            }
            if entry.playlist.name.caseInsensitiveCompare(cleanName) == .orderedSame {
                return true
            }
            if !cleanId.isEmpty, let eId = entry.playlist.id, eId.caseInsensitiveCompare(cleanId) == .orderedSame {
                return true
            }
            return false
        }
        recentlyAddedPlaylists.append((addedAt: now, playlist: optimistic))
        playlistsCache = nil
        cachedHomeFeed = nil
        homeFeedTimestamp = nil
        lock.unlock()
    }

    public func removeRecentlyAddedPlaylist(id: String?, name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanId = (id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty || !cleanId.isEmpty else { return }
        lock.lock()
        recentlyAddedPlaylists.removeAll { entry in
            if !cleanName.isEmpty && entry.playlist.name.caseInsensitiveCompare(cleanName) == .orderedSame {
                return true
            }
            if !cleanId.isEmpty, let eId = entry.playlist.id, eId.caseInsensitiveCompare(cleanId) == .orderedSame {
                return true
            }
            return false
        }
        lock.unlock()
    }

    internal func mergeRecentlyAddedPlaylists(into base: [PlaylistInfo]) -> [PlaylistInfo] {
        let now = Date()
        let activeOptimistic: [PlaylistInfo] = lock.withLock {
            recentlyAddedPlaylists.removeAll { now.timeIntervalSince($0.addedAt) >= Self.recentlyAddedPlaylistTTL }
            return recentlyAddedPlaylists.map { $0.playlist }
        }
        guard !activeOptimistic.isEmpty else { return base }

        var merged = base
        var didMutate = false
        for opt in activeOptimistic {
            let optNorm = Self.normalizePlaylistMatchKey(opt.name)
            let optCat = (opt.catalogId ?? (opt.id?.lowercased().hasPrefix("pl.") == true ? opt.id : nil))?.lowercased()
            if let idx = merged.firstIndex(where: { existing in
                let exNorm = Self.normalizePlaylistMatchKey(existing.name)
                if exNorm == optNorm || Self.playlistsSharePersonalMixAlias(exNorm, optNorm) {
                    return true
                }
                if let oc = optCat, !oc.isEmpty {
                    if existing.catalogId?.lowercased() == oc || existing.id?.lowercased() == oc {
                        return true
                    }
                }
                if let oid = opt.id?.lowercased(), !oid.isEmpty, existing.id?.lowercased() == oid {
                    return true
                }
                if let alts = existing.alternateNames, alts.contains(where: { Self.normalizePlaylistMatchKey($0) == optNorm }) {
                    return true
                }
                return false
            }) {
                let existing = merged[idx]
                let betterCount = (existing.trackCount == 0 && opt.trackCount > 0) ? opt.trackCount : existing.trackCount
                let existingArt = existing.artworkUrl ?? ""
                let optArt = opt.artworkUrl ?? ""
                let betterArt: String?
                if (existingArt.isEmpty || existingArt.hasPrefix("/api/artwork/playlist")), optArt.hasPrefix("http") {
                    betterArt = optArt
                } else {
                    betterArt = existing.artworkUrl ?? opt.artworkUrl
                }
                var combinedAlts = existing.alternateNames ?? [existing.name]
                if !combinedAlts.contains(where: { Self.normalizePlaylistMatchKey($0) == optNorm }) {
                    combinedAlts.append(opt.name)
                }
                if let optAlts = opt.alternateNames {
                    for a in optAlts where !combinedAlts.contains(where: { Self.normalizePlaylistMatchKey($0) == Self.normalizePlaylistMatchKey(a) }) {
                        combinedAlts.append(a)
                    }
                }
                merged[idx] = PlaylistInfo(
                    name: existing.name,
                    trackCount: betterCount,
                    artworkUrl: betterArt,
                    isPlaylist: true,
                    id: existing.id ?? opt.id,
                    catalogId: existing.catalogId ?? opt.catalogId ?? (opt.id?.lowercased().hasPrefix("pl.") == true ? opt.id : nil),
                    alternateNames: combinedAlts.count > 1 ? combinedAlts : existing.alternateNames,
                    url: existing.url ?? opt.url,
                    curatorName: existing.curatorName ?? opt.curatorName,
                    description: existing.description ?? opt.description
                )
            } else {
                merged.append(opt)
                didMutate = true
            }
        }
        if didMutate {
            merged.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return merged
    }

    public func getPlaylists(forceRefresh: Bool = false) -> [PlaylistInfo] {
        lock.lock()
        if !forceRefresh, let cached = playlistsCache, Date().timeIntervalSince(cached.timestamp) < Self.playlistsCacheTTL {
            let list = cached.playlists
            lock.unlock()
            return mergeRecentlyAddedPlaylists(into: applyCachedCloudPlaylistMetadata(into: list))
        }
        lock.unlock()

        playlistsFetchLock.lock()
        defer { playlistsFetchLock.unlock() }

        lock.lock()
        if !forceRefresh, let cached = playlistsCache, Date().timeIntervalSince(cached.timestamp) < Self.playlistsCacheTTL {
            let list = cached.playlists
            lock.unlock()
            return mergeRecentlyAddedPlaylists(into: applyCachedCloudPlaylistMetadata(into: list))
        }
        let staleFallback = playlistsCache?.playlists
        lock.unlock()

        if PlaybackRouter.shared.isTestingEnvironment {
            return mergeRecentlyAddedPlaylists(into: applyCachedCloudPlaylistMetadata(into: staleFallback ?? []))
        }

        var result = [PlaylistInfo]()
        var seenNames = Set<String>()

        MusicAppProvider.shared.ensureMusicAppRunning()

        // Ultra-fast batch query via AppleScript (non-fatal if contended; never triggers watchdog termination)
        let scriptSrc = """
        tell application "Music"
            set res to {}
            try
                with timeout of 2.5 seconds
                    set pList to (every playlist)
                    repeat with p in pList
                        try
                            set pName to (name of p as string)
                            if pName is not in {"Музыка", "Music", "Медиатека", "Библиотека", "Musik", "Musique", "Música", "Musica", "ミュージック", "音乐", "Очередь AMR", "Буфер AMR"} then
                                set pCount to 0
                                try
                                    set pCount to (count of tracks of p)
                                end try
                                set end of res to (pName & "|||" & pCount)
                            end if
                        end try
                    end repeat
                end timeout
            end try
            return res
        end tell
        """

        let rawDesc = AppleScriptExecutor.shared.executeDescriptor(scriptSrc, maxWait: 2.9, reportTimeout: false)
        if let desc = rawDesc {
            let count = desc.numberOfItems
            if count > 0 {
                result.reserveCapacity(count)
                for i in 1...count {
                    if let str = desc.atIndex(i)?.stringValue {
                        let parts = str.components(separatedBy: "|||")
                        if parts.count >= 2 {
                            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                            let trackCount = Int(parts[1]) ?? 0
                            let lower = name.lowercased()
                            if !name.isEmpty, !seenNames.contains(lower),
                               !Self.masterLibraryPlaylistNames.contains(lower) {
                                seenNames.insert(lower)
                                let enc = name.amrQueryValueEncoded
                                let art = ArtworkService.shared.getCachedPlaylistArtworkUrl(name: name) ?? "/api/artwork/playlist?name=\(enc)&v=2"
                                result.append(PlaylistInfo(name: name, trackCount: trackCount, artworkUrl: art, isPlaylist: true))
                            }
                        }
                    }
                }
            }
        } else if let stale = staleFallback, !stale.isEmpty {
            return mergeRecentlyAddedPlaylists(into: applyCachedCloudPlaylistMetadata(into: stale))
        }

        NSLog("[LibraryService] getPlaylists returning %d playlists", result.count)
        let sorted = applyCachedCloudPlaylistMetadata(
            into: result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        )
        if !sorted.isEmpty || rawDesc != nil {
            lock.lock()
            playlistsCache = (timestamp: Date(), playlists: sorted)
            lock.unlock()
        }
        return mergeRecentlyAddedPlaylists(into: sorted)
    }

    public func getPlaylistsWithArtworks() async -> [PlaylistInfo] {
        var baseList = getPlaylists()
        guard !baseList.isEmpty else { return [] }

        await withTaskGroup(of: (String, String).self) { group in
            for pl in baseList {
                if let cached = ArtworkService.shared.getCachedPlaylistArtworkUrl(name: pl.name), !cached.isEmpty {
                    continue
                }

                let playlistName = pl.name
                group.addTask {
                    if let catArt = await MusicKitManager.shared.searchPlaylistArtwork(name: playlistName) {
                        return (playlistName, catArt)
                    }
                    return (playlistName, "")
                }
            }

            for await (plName, artUrl) in group {
                if !artUrl.isEmpty {
                    ArtworkService.shared.setPlaylistArtworkUrl(name: plName, url: artUrl)
                }
            }
        }

        for i in 0..<baseList.count {
            let name = baseList[i].name
            if let art = ArtworkService.shared.getCachedPlaylistArtworkUrl(name: name), !art.isEmpty {
                baseList[i].artworkUrl = art
            } else if baseList[i].artworkUrl?.isEmpty ?? true {
                let enc = name.amrQueryValueEncoded
                baseList[i].artworkUrl = "/api/artwork/playlist?name=\(enc)"
            }
        }

        return baseList
    }

    public func isValidTrack(name: String, artist: String, duration: Double) -> Bool {
        if name.isEmpty || duration <= 0 { return false }
        if name.allSatisfy({ $0.isNumber }) { return false }
        if name.hasSuffix(".mkv.m3u") || name.hasSuffix(".m3u") { return false }
        return true
    }
}
