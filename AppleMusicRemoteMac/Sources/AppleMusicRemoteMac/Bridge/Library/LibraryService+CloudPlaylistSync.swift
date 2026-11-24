//
//  LibraryService+CloudPlaylistSync.swift
//  AppleMusicRemoteMac
//
//  Cross-locale playlist identity matching (`catalogId` `pl.xxx` / `pl.pm-xxx`, library `p.xxx`,
//  localized catalog titles like `"2010s Metal Essentials"` <-> `"Метал 2010-х: главное"`,
//  and Apple Music Personal Mix aliases like `"Get Up! Mix"` <-> `"На старт!"`).
//

import Foundation

extension LibraryService {

    internal static let personalMixAliasGroups: [[String]] = [
        ["get up! mix", "get up!", "get up mix", "на старт!", "на старт", "на старт!: микс", "энергетический микс", "драйв-микс"],
        ["chill mix", "чилл-микс", "чилл микс", "для отдыха", "для отдыха: микс"],
        ["new music mix", "микс новинок", "новинки для вас", "новая музыка", "новая музыка: микс"],
        ["favorites mix", "favourites mix", "фавориты", "фавориты: микс", "в моём вкусе", "в моем вкусе", "в моём вкусе: микс", "в моем вкусе: микс", "избранное: микс"],
        ["friends mix", "микс друзей", "микс для друзей"],
        ["heavy rotation mix", "на повторе", "сейчас на повторе"],
        ["your essentials", "мои любимые треки"]
    ]

    public static func normalizePlaylistMatchKey(_ raw: String) -> String {
        return raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "ʼ", with: "'")
            .replacingOccurrences(of: "`", with: "'")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
    }

    public static func playlistsSharePersonalMixAlias(_ lhs: String, _ rhs: String) -> Bool {
        let a = normalizePlaylistMatchKey(lhs)
        let b = normalizePlaylistMatchKey(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        for group in personalMixAliasGroups {
            if group.contains(a) && group.contains(b) {
                return true
            }
        }
        return false
    }

    public static func canonicalPersonalMixAliases(for name: String) -> [String] {
        let norm = normalizePlaylistMatchKey(name)
        guard !norm.isEmpty else { return [] }
        for group in personalMixAliasGroups where group.contains(norm) {
            return group
        }
        return []
    }

    public func hasFreshCloudPlaylistMetadata() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let ts = cloudPlaylistMetaTimestamp else { return false }
        return Date().timeIntervalSince(ts) < 45.0
    }

    public func invalidatePlaylistsCache() {
        lock.lock()
        playlistsCache = nil
        cloudPlaylistMetaTimestamp = nil
        cachedHomeFeed = nil
        homeFeedTimestamp = nil
        lock.unlock()
        MusicKitManager.shared.invalidateCloudLibraryPlaylistsCache()
    }

    internal func applyCachedCloudPlaylistMetadata(into base: [PlaylistInfo]) -> [PlaylistInfo] {
        guard !base.isEmpty else { return base }
        let metaItems: [CloudLibraryPlaylistMetadata] = lock.withLock { cloudPlaylistMetadataItems }

        var enriched = base
        for i in 0..<enriched.count {
            let pNorm = Self.normalizePlaylistMatchKey(enriched[i].name)
            var altSet: [String] = enriched[i].alternateNames ?? []
            func addAlt(_ s: String) {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return }
                if !altSet.contains(where: { Self.normalizePlaylistMatchKey($0) == Self.normalizePlaylistMatchKey(t) }) {
                    altSet.append(t)
                }
            }
            addAlt(enriched[i].name)
            for alias in Self.canonicalPersonalMixAliases(for: enriched[i].name) {
                addAlt(alias)
            }

            if let matchedMeta = metaItems.first(where: { meta in
                if let existingId = enriched[i].id, !existingId.isEmpty,
                   (meta.libraryId.caseInsensitiveCompare(existingId) == .orderedSame ||
                    meta.catalogId?.caseInsensitiveCompare(existingId) == .orderedSame) {
                    return true
                }
                if let existingCat = enriched[i].catalogId, !existingCat.isEmpty,
                   meta.catalogId?.caseInsensitiveCompare(existingCat) == .orderedSame {
                    return true
                }
                return meta.names.contains { cand in
                    let cNorm = Self.normalizePlaylistMatchKey(cand)
                    return cNorm == pNorm || Self.playlistsSharePersonalMixAlias(cNorm, pNorm)
                }
            }) {
                if enriched[i].id == nil || enriched[i].id?.isEmpty == true {
                    enriched[i].id = matchedMeta.libraryId
                }
                if enriched[i].catalogId == nil, let cid = matchedMeta.catalogId, !cid.isEmpty {
                    enriched[i].catalogId = cid
                }
                for n in matchedMeta.names {
                    addAlt(n)
                }
                let curArt = enriched[i].artworkUrl ?? ""
                if (curArt.isEmpty || curArt.hasPrefix("/api/artwork/playlist")),
                   let cdnArt = matchedMeta.artworkUrl, cdnArt.hasPrefix("http") {
                    enriched[i].artworkUrl = cdnArt
                    ArtworkService.shared.setPlaylistArtworkUrl(name: enriched[i].name, url: cdnArt)
                }
            }

            if altSet.count > 1 || enriched[i].alternateNames != nil {
                enriched[i].alternateNames = altSet
            }
        }
        return enriched
    }

    public func ensureCloudPlaylistMetadataLoaded(forceRefresh: Bool = false) async {
        guard !PlaybackRouter.shared.isTestingEnvironment, MusicKitManager.shared.hasUserToken else { return }
        if !forceRefresh && hasFreshCloudPlaylistMetadata() {
            return
        }
        let fetched = await MusicKitManager.shared.fetchCloudLibraryPlaylistsMetadata(forceRefresh: forceRefresh)
        lock.withLock {
            cloudPlaylistMetadataItems = fetched
            cloudPlaylistMetaTimestamp = Date()
            if let cached = playlistsCache {
                playlistsCache = (cached.timestamp, cached.playlists)
            }
        }
    }

    public func refreshPlaylistsWithCloudMetadata(forceRefresh: Bool = false) async -> [PlaylistInfo] {
        await ensureCloudPlaylistMetadataLoaded(forceRefresh: forceRefresh)
        return getPlaylists(forceRefresh: forceRefresh)
    }

    /// Finds an added user/subscription playlist in the user's library matching ANY of:
    /// `id` (`p.xxx`), `catalogId` (`pl.xxx` / `pl.pm-xxx`), localized `Music.app` title, or catalog `alternateNames`.
    public func findMatchingLocalPlaylist(id: String?, name: String?) -> PlaylistInfo? {
        let cleanId = (id ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let normTarget = Self.normalizePlaylistMatchKey(cleanName)
        guard !cleanId.isEmpty || !normTarget.isEmpty else { return nil }

        let playlists = getPlaylists()
        // 1. Exact ID or Catalog ID match (`pl.xxx`, `pl.pm-xxx`, `p.xxx`)
        if !cleanId.isEmpty {
            if let byId = playlists.first(where: { pl in
                if let pid = pl.id?.lowercased(), pid == cleanId { return true }
                if let cid = pl.catalogId?.lowercased(), cid == cleanId { return true }
                return false
            }) {
                return byId
            }
            // Also check cloudPlaylistMetadataItems in case Music.app renamed it before next getPlaylists merge
            let metaMatch: CloudLibraryPlaylistMetadata? = lock.withLock {
                cloudPlaylistMetadataItems.first {
                    $0.libraryId.lowercased() == cleanId || $0.catalogId?.lowercased() == cleanId
                }
            }
            if let meta = metaMatch {
                if let byMetaName = playlists.first(where: { pl in
                    let pNorm = Self.normalizePlaylistMatchKey(pl.name)
                    return meta.names.contains { Self.normalizePlaylistMatchKey($0) == pNorm || Self.playlistsSharePersonalMixAlias($0, pNorm) }
                }) {
                    return byMetaName
                }
            }
        }

        // 2. Name, Alternate Localized Names, or Personal Mix Alias match
        guard !normTarget.isEmpty else { return nil }
        return playlists.first { pl in
            let pNorm = Self.normalizePlaylistMatchKey(pl.name)
            if pNorm == normTarget || Self.playlistsSharePersonalMixAlias(pNorm, normTarget) {
                return true
            }
            if let alts = pl.alternateNames {
                return alts.contains {
                    let aNorm = Self.normalizePlaylistMatchKey($0)
                    return aNorm == normTarget || Self.playlistsSharePersonalMixAlias(aNorm, normTarget)
                }
            }
            return false
        }
    }
}
