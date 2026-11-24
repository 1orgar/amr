//
//  CloudCatalogService.swift
//  AppleMusicRemoteMac
//
//  Pure Swift cloud catalog search, curated radio stations, and track normalization/deduplication.
//

import Foundation

public final class CloudCatalogService: @unchecked Sendable {
    public static let shared = CloudCatalogService()

    internal struct UncheckedFeedBox: @unchecked Sendable {
        let feed: [String: Any]
    }

    internal static let maxCachedFeedEntries = 32
    private static let artworkDimensionsRegex = try? NSRegularExpression(pattern: "/\\d+x\\d+bb\\.(jpg|png|webp)", options: [])
    private static let bracketQualifierRegex = try? NSRegularExpression(pattern: "\\s*[\\[\\(].*?[\\]\\)]", options: [])

    internal let session: URLSession
    internal var cachedFeed: [String: (timestamp: Date, feed: [String: Any])] = [:]
    internal var inFlightFeedTasks: [String: Task<UncheckedFeedBox, Never>] = [:]
    internal let feedLock = NSLock()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8.0
        config.timeoutIntervalForResource = 12.0
        self.session = URLSession(configuration: config)
    }

    // MARK: - Artwork URL Helper

    public func upgradeArtworkUrl(_ url: String) -> String {
        guard !url.isEmpty else { return "" }
        var result = url
        if result.contains("{w}") || result.contains("{h}") {
            result = result
                .replacingOccurrences(of: "{w}", with: "600")
                .replacingOccurrences(of: "{h}", with: "600")
                .replacingOccurrences(of: "{f}", with: "jpg")
                .replacingOccurrences(of: "{c}", with: "bb")
        }
        if let regex = Self.artworkDimensionsRegex {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "/600x600bb.$1")
        }
        return result
    }

    // MARK: - Curated Stations Catalog

    public func getCuratedStationsAsync(country: String = "") async -> [StationInfo] {
        if MusicKitManager.shared.hasUserToken {
            _ = await MusicKitManager.shared.fetchPersonalStations()
        }
        return getCuratedStations(country: country)
    }

    public func getCuratedStations(country: String = "") -> [StationInfo] {
        let c = MusicKitManager.sanitizedStorefront(MusicKitManager.shared.resolveEffectiveStorefront(country))
        let isRu = ["ru", "kz", "by", "ua"].contains(c) || MusicKitManager.shared.isSystemLocaleRussian || MusicKitManager.shared.getPreferredLanguageTag().lowercased().hasPrefix("ru")

        let cached = MusicKitManager.shared.getCachedPersonalData()
        let personalStation = cached?.personalStation
        let discoveryStation = cached?.discoveryStation

        let personalName = personalStation?.name ?? (isRu ? "Моя станция" : "My Station")
        let personalUrl = (personalStation?.url.isEmpty == false) ? personalStation!.url : "https://music.apple.com/\(c)/station/todays-hits/ra.985480047"
        let personalArt = (personalStation?.artwork.isEmpty == false) ? personalStation!.artwork : MusicKitManager.defaultPersonalStationArtwork
        let personalId = personalStation?.id ?? "station_personal"

        let discoveryName = discoveryStation?.name ?? (isRu ? "Станция открытий" : "Discovery Station")
        let discoveryUrl = (discoveryStation?.url.isEmpty == false) ? discoveryStation!.url : "https://music.apple.com/\(c)/station/pure-chill/ra.985484943"
        let discoveryArt = (discoveryStation?.artwork.isEmpty == false) ? discoveryStation!.artwork : "/assets/stations/CoverDiscovery.png"
        let discoveryId = discoveryStation?.id ?? "station_discovery"

        return [
            StationInfo(
                id: personalId,
                name: personalName,
                subtitle: isRu ? "Любимые треки и персональные рекомендации" : "Favorite tracks & personal recommendations",
                artwork: personalArt,
                url: personalUrl,
                isLive: false,
                color: "linear-gradient(135deg, #fa233b, #fb5c74)",
                isPersonal: true
            ),
            StationInfo(
                id: discoveryId,
                name: discoveryName,
                subtitle: isRu ? "Новая музыка на основе ваших вкусов" : "New music based on what you love",
                artwork: discoveryArt,
                url: discoveryUrl,
                isLive: false,
                color: "linear-gradient(135deg, #7928ca, #ff0080)",
                isPersonal: true
            ),
            StationInfo(
                id: "station_am1",
                name: "Apple Music 1 Live",
                subtitle: isRu ? "Главные мировые релизы в прямом эфире" : "The new music that matters, live 24/7",
                artwork: "/assets/stations/CoverAppleMusic1.png",
                url: "https://music.apple.com/us/station/apple-music-1/ra.978194965",
                isLive: true,
                color: "linear-gradient(135deg, #1c1c1e, #3a3a3c)"
            ),
            StationInfo(
                id: "station_hits",
                name: "Apple Music Hits",
                subtitle: isRu ? "Культовые хиты 80-х, 90-х и 2000-х" : "The songs you know and love",
                artwork: "https://is1-ssl.mzstatic.com/image/thumb/Features221/v4/27/b7/ec/27b7eca8-5bb2-3c46-ca1e-be2877a3cc91/feb0dc99-412b-4688-b8d6-c0fa07059558.png/600x600sr.jpg",
                url: "https://music.apple.com/us/station/apple-music-hits/ra.1498155548",
                isLive: true,
                color: "linear-gradient(135deg, #ff0844, #ffb199)"
            ),
            StationInfo(
                id: "station_country",
                name: "Apple Music Country",
                subtitle: isRu ? "Современное и классическое кантри" : "Where country music lives",
                artwork: "https://is1-ssl.mzstatic.com/image/thumb/Features/v4/89/37/3f/89373f8b-0fe9-ab3d-713d-1ed8b9cb3336/0799e8e4-e4be-44ab-8c3a-aefd9cf8d174.png/600x600sr.jpg",
                url: "https://music.apple.com/us/station/apple-music-country/ra.1498157166",
                isLive: true,
                color: "linear-gradient(135deg, #f7971e, #ffd200)"
            ),
            StationInfo(
                id: "station_chill",
                name: isRu ? "Chill & Lo-Fi" : "Chill Station",
                subtitle: isRu ? "Спокойный ритм и фоновые биты" : "Laid-back sounds and mellow beats",
                artwork: "https://is1-ssl.mzstatic.com/image/thumb/Features/v4/f5/54/f5/f554f538-499a-3dec-1054-d7a90f633e1a/5211c0ce-9a10-4857-b0d0-ea2311fb1fed.png/600x600sr.jpg",
                url: "https://music.apple.com/us/station/chill-station/ra.985484943",
                isLive: false,
                color: "linear-gradient(135deg, #00b4db, #0083b0)"
            ),
            StationInfo(
                id: "station_pop",
                name: isRu ? "Pop Hits" : "Today's Hits Radio",
                subtitle: isRu ? "Самые популярные поп-треки мира" : "The biggest pop anthems right now",
                artwork: "https://is1-ssl.mzstatic.com/image/thumb/Features221/v4/c1/94/de/c194deaa-eae8-75e6-0402-85a45bf76408/ec85d0a7-7073-441d-95be-fd1c4cfdc348.png/600x600sr.jpg",
                url: "https://music.apple.com/us/station/hits-station/ra.985480047",
                isLive: false,
                color: "linear-gradient(135deg, #fa2d48, #ff6b8b)"
            ),
            StationInfo(
                id: "station_rock",
                name: isRu ? "Rock Classics" : "Rock Classics Radio",
                subtitle: isRu ? "Культовые рок-гимны и гитарные соло" : "Greatest guitar anthems & classic rock",
                artwork: "https://is1-ssl.mzstatic.com/image/thumb/Features/v4/db/ba/e4/dbbae45c-8d9a-5c45-3c6b-d8662f0a5873/c07ee270-72ba-4c0d-b01d-bac5d595bbab.png/600x600sr.jpg",
                url: "https://music.apple.com/us/station/classic-rock-station/ra.985500514",
                isLive: false,
                color: "linear-gradient(135deg, #e65100, #ff9800)"
            ),
            StationInfo(
                id: "station_hiphop",
                name: isRu ? "Hip-Hop" : "Hip-Hop & R&B",
                subtitle: isRu ? "Плотные биты и свежие релизы" : "Heavy beats and groundbreaking rap",
                artwork: "https://is1-ssl.mzstatic.com/image/thumb/Features/v4/88/89/43/888943a0-6ce9-c778-5120-8f7ad49bbb73/76991844-0242-404d-949d-ba28b7432f51.png/600x600sr.jpg",
                url: "https://music.apple.com/us/station/hip-hop-station/ra.985488923",
                isLive: false,
                color: "linear-gradient(135deg, #4a148c, #7b1fa2)"
            ),
            StationInfo(
                id: "station_electronic",
                name: isRu ? "Dance & Electronic" : "Dance & Electronic",
                subtitle: isRu ? "Клубный драйв и танцевальная энергия" : "Non-stop club bangers & festival anthems",
                artwork: "https://is1-ssl.mzstatic.com/image/thumb/Features211/v4/0b/36/19/0b36194e-bca3-ca9b-0e0d-f25afacff780/81fc6d0f-6f9d-4d14-ab92-036f5024d6e2.png/600x600sr.jpg",
                url: "https://music.apple.com/us/station/dance-station/ra.985487895",
                isLive: false,
                color: "linear-gradient(135deg, #00695c, #00bfa5)"
            ),
            StationInfo(
                id: "station_deephouse",
                name: "Deep House",
                subtitle: isRu ? "Глубокое электронное звучание" : "Deep melodic house & hypnotic rhythms",
                artwork: "https://is1-ssl.mzstatic.com/image/thumb/Features122/v4/76/66/fd/7666fdf7-1ff0-799e-f1b9-25eb41de9d93/5e4b0619-cc57-4ae6-a3a9-f2620ca68bcc.png/600x600sr.jpg",
                url: "https://music.apple.com/us/station/house-station/ra.991194049",
                isLive: false,
                color: "linear-gradient(135deg, #880e4f, #d81b60)"
            ),
            StationInfo(
                id: "station_jazz",
                name: isRu ? "Jazz" : "Jazz & Blues",
                subtitle: isRu ? "Безупречная классика джаза" : "Timeless jazz standards & soothing brass",
                artwork: "https://is1-ssl.mzstatic.com/image/thumb/Features/v4/06/2e/6c/062e6ce2-1492-456e-091d-880f84d6837e/107f3a79-1ff9-4f6c-9749-f9e53dbc76bf.png/600x600sr.jpg",
                url: "https://music.apple.com/us/station/jazz-station/ra.985496180",
                isLive: false,
                color: "linear-gradient(135deg, #37474f, #78909c)"
            )
        ]
    }

    // MARK: - Search Apple Music / iTunes

    public func search(query: String, country: String = "", source: String? = "cloud", limit: Int = 50, offset: Int = 0) async -> [String: AnyCodable] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return [
                "artists": AnyCodable([]),
                "songs": AnyCodable([]),
                "albums": AnyCodable([]),
                "all": AnyCodable([]),
                "offset": AnyCodable(offset),
                "limit": AnyCodable(limit),
                "has_more": AnyCodable(false)
            ]
        }

        let c = MusicKitManager.sanitizedStorefront(MusicKitManager.shared.resolveEffectiveStorefront(country))
        let effectiveLimit = max(1, min(limit, 100))
        let effectiveOffset = max(0, offset)

        if effectiveOffset == 0 && source != "library" {
            await LibraryService.shared.ensureCloudPlaylistMetadataLoaded()
        }

        // Precompute normalized local library lookup maps ONCE outside the cloud-results loop (O(N + M) instead of O(N * M))
        let librarySongs = MusicBridge.shared.getLibrarySongs()
        var exactLocalByTitleAndArtist: [String: Int] = [:]
        var localByNormalizedTitle: [String: [(artistLower: String, dbId: Int)]] = [:]
        if !librarySongs.isEmpty {
            exactLocalByTitleAndArtist.reserveCapacity(librarySongs.count)
            localByNormalizedTitle.reserveCapacity(librarySongs.count)
            for local in librarySongs {
                guard let dbId = local.numericId, dbId > 0 else { continue }
                let ln = local.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !ln.isEmpty else { continue }
                let la = local.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let exactKey = "\(ln)|\(la)"
                if exactLocalByTitleAndArtist[exactKey] == nil {
                    exactLocalByTitleAndArtist[exactKey] = dbId
                }
                localByNormalizedTitle[ln, default: []].append((artistLower: la, dbId: dbId))
            }
        }

        // Only query local library matches on first page (offset == 0)
        var localSongDicts = [[String: Any]]()
        if effectiveOffset == 0 {
            let lowerQ = trimmedQuery.lowercased()
            let qTokens = lowerQ.split(separator: " ").map { String($0) }.filter { !$0.isEmpty }

            let filtered = librarySongs.filter { t in
                let n = t.name.lowercased()
                let a = t.artist.lowercased()
                let alb = t.album.lowercased()
                if n.contains(lowerQ) || a.contains(lowerQ) || alb.contains(lowerQ) {
                    return true
                }
                if !qTokens.isEmpty {
                    let combined = "\(n) \(a) \(alb)"
                    if qTokens.allSatisfy({ combined.contains($0) }) {
                        return true
                    }
                }
                return false
            }

            for t in filtered {
                localSongDicts.append([
                    "id": t.id,
                    "numeric_id": t.numericId ?? 0,
                    "name": t.name,
                    "artist": t.artist,
                    "album": t.album,
                    "duration": t.duration,
                    "artwork_url": t.artworkUrl,
                    "favorited": t.favorited,
                    "is_local": true
                ])
            }
        }

        var localPlaylistDicts = [[String: Any]]()
        var altOnlyLocalCatalogIds = Set<String>()
        if effectiveOffset == 0 {
            let lowerQ = LibraryService.normalizePlaylistMatchKey(trimmedQuery)
            let qTokens = lowerQ.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            let localPlaylists = LibraryService.shared.getPlaylists()
            for pl in localPlaylists {
                let pName = LibraryService.normalizePlaylistMatchKey(pl.name)
                let matchesPrimaryDirect = pName.contains(lowerQ)
                let matchesPrimaryTokens = !qTokens.isEmpty && qTokens.allSatisfy({ pName.contains($0) })
                let isPrimaryMatch = matchesPrimaryDirect || matchesPrimaryTokens

                var isAltMatch = false
                if !isPrimaryMatch, let alts = pl.alternateNames {
                    for alt in alts {
                        let aNorm = LibraryService.normalizePlaylistMatchKey(alt)
                        guard !aNorm.isEmpty else { continue }
                        if aNorm.contains(lowerQ) || (!qTokens.isEmpty && qTokens.allSatisfy({ aNorm.contains($0) })) {
                            isAltMatch = true
                            break
                        }
                    }
                }

                if isPrimaryMatch || isAltMatch {
                    let enc = pl.name.amrQueryValueEncoded
                    let art = pl.artworkUrl ?? "/api/artwork/playlist?name=\(enc)"
                    let catId = pl.catalogId ?? ""
                    if !isPrimaryMatch && !catId.isEmpty {
                        altOnlyLocalCatalogIds.insert(catId.lowercased())
                    }
                    localPlaylistDicts.append([
                        "type": "playlist",
                        "id": pl.id ?? pl.name,
                        "library_id": pl.id ?? "",
                        "catalog_id": catId,
                        "alternate_names": pl.alternateNames ?? [],
                        "name": pl.name,
                        "local_name": pl.name,
                        "curator": "Медиатека",
                        "curator_name": "Медиатека",
                        "subtitle": "\(pl.trackCount) треков",
                        "track_count": pl.trackCount,
                        "artwork": art,
                        "artwork_url": art,
                        "url": pl.url ?? "",
                        "is_playlist": true,
                        "is_local": true,
                        "in_library": true
                    ])
                }
            }
        }

        if source == "library" {
            let dedupedLocal = Self.deduplicateSongs(localSongDicts)
            return [
                "artists": AnyCodable([]),
                "songs": AnyCodable(dedupedLocal),
                "albums": AnyCodable([]),
                "playlists": AnyCodable(localPlaylistDicts),
                "offset": AnyCodable(effectiveOffset),
                "limit": AnyCodable(effectiveLimit),
                "has_more": AnyCodable(false)
            ]
        }

        // O(1) lookup against precomputed local library maps
        let enrichWithLocal: ([[String: Any]]) -> [[String: Any]] = { songs in
            guard !localByNormalizedTitle.isEmpty else { return songs }
            return songs.map { orig in
                var item = orig
                let sName = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                guard !sName.isEmpty else { return item }
                let sArtist = (item["artist"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

                if let exactDbId = exactLocalByTitleAndArtist["\(sName)|\(sArtist)"] {
                    item["numeric_id"] = exactDbId
                    item["is_local"] = true
                    return item
                }
                if let candidates = localByNormalizedTitle[sName],
                   let matched = candidates.first(where: { cand in
                       sArtist.isEmpty || cand.artistLower == sArtist || cand.artistLower.contains(sArtist) || sArtist.contains(cand.artistLower)
                   }) {
                    item["numeric_id"] = matched.dbId
                    item["is_local"] = true
                }
                return item
            }
        }

        // 1. Try official Apple Music API with MusicKit developer token
        let catalogLimit = min(effectiveLimit, 25)
        if let appleMusicResults = await MusicKitManager.shared.searchAppleMusic(query: trimmedQuery, storefront: c, limit: catalogLimit, offset: effectiveOffset) {
            var res = [String: AnyCodable]()
            let rawCloudSongs = (appleMusicResults["songs"] as? [[String: Any]]) ?? []
            let dedupedCloudSongs = Self.deduplicateSongs(rawCloudSongs)
            let enrichedCloudSongs = enrichWithLocal(dedupedCloudSongs)
            let cloudSongKeys = Set(enrichedCloudSongs.compactMap { song -> String? in
                let n = (song["name"] as? String) ?? ""
                let a = (song["artist"] as? String) ?? ""
                let k = Self.normalizeTrackKey(name: n, artist: a)
                return (!k.isEmpty && k != "|") ? k : nil
            })
            let uniqueLocalSongs = localSongDicts.filter { local in
                let n = (local["name"] as? String) ?? ""
                let a = (local["artist"] as? String) ?? ""
                let k = Self.normalizeTrackKey(name: n, artist: a)
                return !cloudSongKeys.contains(k)
            }
            let mergedSongs = Self.deduplicateSongs(enrichedCloudSongs + uniqueLocalSongs)
            res["songs"] = AnyCodable(mergedSongs)
            if let albums = appleMusicResults["albums"] as? [[String: Any]] {
                res["albums"] = AnyCodable(albums)
            } else {
                res["albums"] = AnyCodable([])
            }
            if let artists = appleMusicResults["artists"] as? [[String: Any]] {
                res["artists"] = AnyCodable(artists)
            } else {
                res["artists"] = AnyCodable([])
            }
            let cloudPlaylists = (appleMusicResults["playlists"] as? [[String: Any]]) ?? []
            var returnedCloudCatalogIds = Set<String>()
            let enrichedCloudPlaylists: [[String: Any]] = cloudPlaylists.map { rawItem in
                var item = rawItem
                let cid = (item["id"] as? String) ?? ""
                let cname = (item["name"] as? String) ?? ""
                if !cid.isEmpty {
                    returnedCloudCatalogIds.insert(cid.lowercased())
                }
                if let matchedLocal = LibraryService.shared.findMatchingLocalPlaylist(id: cid, name: cname) {
                    item["is_local"] = true
                    item["in_library"] = true
                    item["local_name"] = matchedLocal.name
                    item["catalog_id"] = cid
                    if let lid = matchedLocal.id, !lid.isEmpty {
                        item["library_id"] = lid
                    }
                    if let alts = matchedLocal.alternateNames, !alts.isEmpty {
                        item["alternate_names"] = alts
                    }
                    if matchedLocal.trackCount > 0 {
                        item["track_count"] = matchedLocal.trackCount
                    }
                }
                return item
            }

            // If the user searched the English catalog name (e.g. "2010s Metal Essentials"), drop the alt-only
            // Russian local duplicate when the catalog card itself is returned (now marked `in_library: true`).
            let filteredLocalPlaylistDicts = localPlaylistDicts.filter { localItem in
                let lCat = ((localItem["catalog_id"] as? String) ?? "").lowercased()
                if !lCat.isEmpty && altOnlyLocalCatalogIds.contains(lCat) && returnedCloudCatalogIds.contains(lCat) {
                    return false
                }
                return true
            }

            let primaryLocalNames = Set(filteredLocalPlaylistDicts.compactMap { ($0["name"] as? String).map(LibraryService.normalizePlaylistMatchKey) })
            let primaryLocalCatalogIds = Set(filteredLocalPlaylistDicts.compactMap {
                let cId = (($0["catalog_id"] as? String) ?? "").lowercased()
                return cId.isEmpty ? nil : cId
            })
            let uniqueCloudPlaylists = enrichedCloudPlaylists.filter { item in
                let cid = ((item["id"] as? String) ?? "").lowercased()
                if !cid.isEmpty && primaryLocalCatalogIds.contains(cid) {
                    return false
                }
                guard let cn = (item["name"] as? String).map(LibraryService.normalizePlaylistMatchKey) else { return true }
                return !primaryLocalNames.contains(cn)
            }
            res["playlists"] = AnyCodable(filteredLocalPlaylistDicts + uniqueCloudPlaylists)
            res["offset"] = AnyCodable(effectiveOffset)
            res["limit"] = AnyCodable(effectiveLimit)
            res["has_more"] = AnyCodable(rawCloudSongs.count >= catalogLimit)
            return res
        }

        // 2. Fallback to iTunes Store Search API (using URLComponents with raw query)
        async let artistsTask = fetchArtists(query: trimmedQuery, country: c, limit: min(effectiveLimit, 15), offset: effectiveOffset)
        async let songsTask = fetchSongs(query: trimmedQuery, country: c, limit: effectiveLimit, offset: effectiveOffset)
        async let albumsTask = fetchAlbums(query: trimmedQuery, country: c, limit: min(effectiveLimit, 20), offset: effectiveOffset)

        let (artists, rawSongs, albums) = await (artistsTask, songsTask, albumsTask)
        let dedupedRawSongs = Self.deduplicateSongs(rawSongs)
        let enrichedSongs = enrichWithLocal(dedupedRawSongs)
        let fallbackCloudKeys = Set(enrichedSongs.compactMap { song -> String? in
            let n = (song["name"] as? String) ?? ""
            let a = (song["artist"] as? String) ?? ""
            let k = Self.normalizeTrackKey(name: n, artist: a)
            return (!k.isEmpty && k != "|") ? k : nil
        })
        let fallbackUniqueLocal = localSongDicts.filter { local in
            let n = (local["name"] as? String) ?? ""
            let a = (local["artist"] as? String) ?? ""
            let k = Self.normalizeTrackKey(name: n, artist: a)
            return !fallbackCloudKeys.contains(k)
        }
        let mergedFallbackSongs = Self.deduplicateSongs(enrichedSongs + fallbackUniqueLocal)

        return [
            "artists": AnyCodable(artists),
            "songs": AnyCodable(mergedFallbackSongs),
            "albums": AnyCodable(albums),
            "playlists": AnyCodable(localPlaylistDicts),
            "offset": AnyCodable(effectiveOffset),
            "limit": AnyCodable(effectiveLimit),
            "has_more": AnyCodable(rawSongs.count >= effectiveLimit)
        ]
    }

    // MARK: - Track Normalization & Deduplication Helpers

    public static func normalizeTrackKey(name: String, artist: String) -> String {
        let qualifiers = LibraryService.extractVersionQualifiers(name).sorted().joined(separator: "+")
        var n = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let regex = bracketQualifierRegex {
            n = regex.stringByReplacingMatches(in: n, options: [], range: NSRange(location: 0, length: n.utf16.count), withTemplate: "")
        }
        if let dashIdx = n.range(of: " - ") {
            n = String(n[..<dashIdx.lowerBound])
        }
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let cleanN = n.unicodeScalars.filter { allowed.contains($0) }.map { String($0) }.joined()
        let cleanA = artist.lowercased().unicodeScalars.filter { allowed.contains($0) }.map { String($0) }.joined()
        let normN = cleanN.split(separator: " ").joined(separator: " ")
        let normA = cleanA.split(separator: " ").joined(separator: " ")
        if qualifiers.isEmpty {
            return "\(normN)|\(normA)"
        }
        return "\(normN)#\(qualifiers)|\(normA)"
    }

    internal static func itunesLangInfo(country: String) -> (itunesLang: String, acceptLang: String) {
        let pref = MusicKitManager.shared.getPreferredLanguageTag()
        let normalized = pref.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "-", with: "_").lowercased()
        let parts = normalized.split(separator: "_").map(String.init)
        let itunesLang: String
        if parts.count >= 2 {
            itunesLang = "\(parts[0])_\(parts.last!)"
        } else if let primary = parts.first, !primary.isEmpty {
            let reg = MusicKitManager.sanitizedStorefront(country)
            itunesLang = "\(primary)_\(reg)"
        } else {
            itunesLang = "en_us"
        }
        return (itunesLang, pref)
    }

    public static func deduplicateSongs(_ songs: [[String: Any]]) -> [[String: Any]] {
        var seen = Set<String>()
        var result = [[String: Any]]()
        for s in songs {
            let n = (s["name"] as? String) ?? (s["trackName"] as? String) ?? ""
            let a = (s["artist"] as? String) ?? (s["artistName"] as? String) ?? ""
            let key = normalizeTrackKey(name: n, artist: a)
            if !key.isEmpty && key != "|" {
                if !seen.contains(key) {
                    seen.insert(key)
                    result.append(s)
                }
            } else {
                result.append(s)
            }
        }
        return result
    }
}
