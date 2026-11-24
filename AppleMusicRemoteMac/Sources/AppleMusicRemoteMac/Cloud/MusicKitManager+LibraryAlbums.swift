//
//  MusicKitManager+LibraryAlbums.swift
//  AppleMusicRemoteMac
//
//  User library albums fetching, optimistic session-added album tracking,
//  pagination host verification, and library album tracks lookup.
//

import Foundation

extension MusicKitManager {

    // MARK: - Album Normalization & User Library Albums

    public static func normalizedAlbumTitle(_ raw: String) -> String {
        raw
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalizedBaseAlbumTitle(_ raw: String) -> String {
        var norm = normalizedAlbumTitle(raw)
        for suffix in [" - single", " - ep", " – single", " – ep", " — single", " — ep"] {
            if norm.hasSuffix(suffix), norm.count > suffix.count {
                norm = String(norm.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return norm
    }

    public static func normalizedAlbumKey(name: String, artist: String) -> String {
        let n = normalizedAlbumTitle(name)
        let a = normalizedAlbumTitle(artist)
        return "\(n)|\(a)"
    }

    public static func albumMatches(_ lhsName: String, _ lhsArtist: String, _ rhsName: String, _ rhsArtist: String) -> Bool {
        let ln = normalizedAlbumTitle(lhsName)
        let rn = normalizedAlbumTitle(rhsName)
        let titleMatches: Bool = {
            guard !ln.isEmpty, !rn.isEmpty else { return false }
            if ln == rn { return true }
            let lBase = normalizedBaseAlbumTitle(lhsName)
            let rBase = normalizedBaseAlbumTitle(rhsName)
            return !lBase.isEmpty && lBase == rBase && (ln != lBase || rn != rBase)
        }()
        guard titleMatches else { return false }
        let la = normalizedAlbumTitle(lhsArtist)
        let ra = normalizedAlbumTitle(rhsArtist)
        if la.isEmpty || ra.isEmpty { return true }
        return la == ra || la.contains(ra) || ra.contains(la) || artistsOverlap(lhsArtist, rhsArtist)
    }

    public func invalidateUserLibraryAlbumsCache() {
        withLock {
            userLibraryAlbumsCache = nil
        }
    }

    public func clearRecentlyAddedAlbumsForTesting() {
        withLock {
            recentlyAddedLibraryAlbums.removeAll()
            userLibraryAlbumsCache = nil
        }
    }

    public func recordAddedAlbumToLibrary(
        albumId: String,
        name: String,
        artist: String,
        artwork: String = "",
        trackCount: Int? = nil
    ) {
        let cleanId = albumId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty || !cleanName.isEmpty else { return }

        let now = Date()
        let catalogId = (Int(cleanId) ?? 0) >= 10_000_000 ? cleanId : nil
        let entryAlbum = AlbumInfo(
            id: cleanId,
            name: cleanName,
            artist: cleanArtist,
            artwork: artwork,
            trackCount: trackCount,
            inLibrary: true,
            libraryTrackCount: trackCount,
            catalogTrackCount: trackCount,
            catalogAlbumId: catalogId,
            isCompleteInLibrary: true,
            dateAdded: now.timeIntervalSince1970
        )
        withLock {
            recentlyAddedLibraryAlbums.removeAll { item in
                if !cleanId.isEmpty && !item.album.id.isEmpty && item.album.id.caseInsensitiveCompare(cleanId) == .orderedSame {
                    return true
                }
                return Self.albumMatches(item.album.name, item.album.artist, cleanName, cleanArtist)
            }
            recentlyAddedLibraryAlbums.insert((addedAt: now, album: entryAlbum), at: 0)
            if recentlyAddedLibraryAlbums.count > 100 {
                recentlyAddedLibraryAlbums = Array(recentlyAddedLibraryAlbums.prefix(100))
            }
            userLibraryAlbumsCache = nil
        }
        if artwork.hasPrefix("http://") || artwork.hasPrefix("https://") {
            registerAlbumArtwork(album: cleanName, artist: cleanArtist, url: artwork)
        }
    }

    public func getCachedUserLibraryAlbumsSnapshot() -> [AlbumInfo] {
        withLock {
            userLibraryAlbumsCache?.albums ?? []
        }
    }

    public func getRecentlyAddedAlbums() -> [AlbumInfo] {
        withLock {
            recentlyAddedLibraryAlbums.map(\.album)
        }
    }

    public func getRecentlyAddedLibraryAlbumsSnapshot() -> [AlbumInfo] {
        getRecentlyAddedAlbums()
    }

    @discardableResult
    public func removeRecordedAlbumFromLibrary(albumId: String?, name: String, artist: String) -> Bool {
        let cleanId = albumId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)

        return withLock {
            let beforeCount = recentlyAddedLibraryAlbums.count
            recentlyAddedLibraryAlbums.removeAll { item in
                if !cleanId.isEmpty {
                    if !item.album.id.isEmpty && item.album.id.caseInsensitiveCompare(cleanId) == .orderedSame {
                        return true
                    }
                    if let catId = item.album.catalogAlbumId, !catId.isEmpty,
                       catId.caseInsensitiveCompare(cleanId) == .orderedSame {
                        return true
                    }
                }
                if !cleanName.isEmpty && Self.albumMatches(item.album.name, item.album.artist, cleanName, cleanArtist) {
                    return true
                }
                return false
            }
            let removed = recentlyAddedLibraryAlbums.count < beforeCount
            userLibraryAlbumsCache = nil
            return removed
        }
    }

    @discardableResult
    public func removeRecordedAlbumsForArtistFromLibrary(artist: String) -> Int {
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanArtist.isEmpty else { return 0 }

        return withLock {
            let beforeCount = recentlyAddedLibraryAlbums.count
            recentlyAddedLibraryAlbums.removeAll { item in
                LibraryService.artistMatchesLibraryTarget(trackArtist: item.album.artist, targetArtist: cleanArtist)
            }
            let removedCount = beforeCount - recentlyAddedLibraryAlbums.count
            userLibraryAlbumsCache = nil
            return removedCount
        }
    }

    public func isExplicitlyAddedAlbumInSession(albumId: String, name: String, artist: String) -> Bool {
        let cleanId = albumId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        return withLock {
            for item in recentlyAddedLibraryAlbums {
                if !cleanId.isEmpty && !item.album.id.isEmpty && item.album.id.caseInsensitiveCompare(cleanId) == .orderedSame {
                    return true
                }
                if !cleanName.isEmpty && Self.albumMatches(item.album.name, item.album.artist, cleanName, cleanArtist) {
                    return true
                }
            }
            return false
        }
    }

    public func getCachedUserLibraryAlbumMatch(albumId: String, name: String, artist: String) -> AlbumInfo? {
        let cleanId = albumId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        return withLock {
            guard let cached = userLibraryAlbumsCache?.albums else { return nil }
            for alb in cached {
                if !cleanId.isEmpty && !alb.id.isEmpty && alb.id.caseInsensitiveCompare(cleanId) == .orderedSame {
                    return alb
                }
                if !cleanName.isEmpty && Self.albumMatches(alb.name, alb.artist, cleanName, cleanArtist) {
                    return alb
                }
            }
            return nil
        }
    }

    public func isAlbumInLibraryOrRecentlyAdded(albumId: String, name: String, artist: String) -> Bool {
        let cleanId = albumId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)

        return withLock {
            for item in recentlyAddedLibraryAlbums {
                if !cleanId.isEmpty && !item.album.id.isEmpty && item.album.id.caseInsensitiveCompare(cleanId) == .orderedSame {
                    return true
                }
                if Self.albumMatches(item.album.name, item.album.artist, cleanName, cleanArtist) {
                    return true
                }
            }
            if let cached = userLibraryAlbumsCache?.albums {
                for alb in cached {
                    if !cleanId.isEmpty && !alb.id.isEmpty && alb.id.caseInsensitiveCompare(cleanId) == .orderedSame {
                        return true
                    }
                    if Self.albumMatches(alb.name, alb.artist, cleanName, cleanArtist) {
                        return true
                    }
                }
            }
            return false
        }
    }

    public func fetchUserLibraryAlbums(forceRefresh: Bool = false) async -> [AlbumInfo] {
        if !forceRefresh, let cached = withLock({ () -> [AlbumInfo]? in
            if let entry = userLibraryAlbumsCache, Date().timeIntervalSince(entry.timestamp) < 120.0 {
                return entry.albums
            }
            return nil
        }) {
            return mergeRecentlyAddedIntoAlbums(cached)
        }

        guard !PlaybackRouter.shared.isTestingEnvironment,
              let devToken = getDeveloperToken(),
              let uToken = getUserToken(),
              !uToken.isEmpty else {
            return getRecentlyAddedAlbums()
        }

        if !forceRefresh, let existingTask = withLock({ inFlightUserLibraryAlbumsTask }) {
            let shared = await existingTask.value
            return mergeRecentlyAddedIntoAlbums(shared)
        }

        let fetchTask = Task<[AlbumInfo], Never> {
            await self.performFetchUserLibraryAlbums(devToken: devToken, uToken: uToken)
        }

        let taskToAwait: Task<[AlbumInfo], Never> = withLock {
            if !forceRefresh, let raced = inFlightUserLibraryAlbumsTask {
                fetchTask.cancel()
                return raced
            }
            inFlightUserLibraryAlbumsTask = fetchTask
            return fetchTask
        }

        let fetchedAlbums = await taskToAwait.value
        withLock {
            if inFlightUserLibraryAlbumsTask == taskToAwait {
                inFlightUserLibraryAlbumsTask = nil
            }
        }
        if !fetchedAlbums.isEmpty {
            return mergeRecentlyAddedIntoAlbums(fetchedAlbums)
        }
        return getRecentlyAddedAlbums()
    }

    internal func performFetchUserLibraryAlbums(devToken: String, uToken: String) async -> [AlbumInfo] {
        let lang = getPreferredLanguageTag()
        var parsedEntries: [(dateAdded: String, album: AlbumInfo)] = []
        var artworkBatch: [(album: String, artist: String, url: String)] = []
        var nextPath: String? = "/v1/me/library/albums?limit=100&include=catalog"
        var pagesFetched = 0
        var retriedWithoutInclude = false

        while let path = nextPath, pagesFetched < 10 {
            pagesFetched += 1
            var extraItems: [URLQueryItem] = [URLQueryItem(name: "l", value: lang)]
            if !retriedWithoutInclude {
                extraItems.append(URLQueryItem(name: "include", value: "catalog"))
            }
            guard let url = Self.resolveSafeAppleMusicPaginationURL(path, extraQueryItems: extraItems) else {
                break
            }
            var req = URLRequest(url: url, timeoutInterval: 4.5)
            req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
            req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue(lang, forHTTPHeaderField: "Accept-Language")

            guard let (data, resp) = try? await session.data(for: req),
                  let http = resp as? HTTPURLResponse else {
                break
            }

            if http.statusCode != 200 {
                if pagesFetched == 1 && !retriedWithoutInclude {
                    retriedWithoutInclude = true
                    pagesFetched = 0
                    nextPath = "/v1/me/library/albums?limit=100"
                    continue
                }
                NSLog("[MusicKitManager] ⚠️ /v1/me/library/albums returned HTTP %d", http.statusCode)
                break
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArr = json["data"] as? [[String: Any]] else {
                break
            }

            for item in dataArr {
                let rawLibId = (item["id"] as? String) ?? ""
                let attrs = (item["attributes"] as? [String: Any]) ?? [:]
                let aName = (attrs["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !aName.isEmpty else { continue }
                let aArtist = (attrs["artistName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let relDate = attrs["releaseDate"] as? String
                let tCount = attrs["trackCount"] as? Int
                let genre = (attrs["genreNames"] as? [String])?.first
                let dateAdded = (attrs["dateAdded"] as? String) ?? ""

                var resolvedId = rawLibId
                var catalogAlbumId: String? = nil
                var catalogAttrs: [String: Any]? = nil

                if let rels = item["relationships"] as? [String: Any],
                   let catObj = rels["catalog"] as? [String: Any],
                   let catArr = catObj["data"] as? [[String: Any]],
                   let firstCat = catArr.first {
                    if let catId = firstCat["id"] as? String, Self.isValidResourceIdentifier(catId) {
                        resolvedId = catId
                        catalogAlbumId = catId
                    }
                    catalogAttrs = firstCat["attributes"] as? [String: Any]
                }

                if catalogAlbumId == nil,
                   let playParams = attrs["playParams"] as? [String: Any],
                   let catId = playParams["catalogId"] as? String, Self.isValidResourceIdentifier(catId) {
                    resolvedId = catId
                    catalogAlbumId = catId
                } else if catalogAlbumId == nil, (Int(rawLibId) ?? 0) >= 10_000_000 {
                    catalogAlbumId = rawLibId
                }

                var artUrl = ""
                if let catArtObj = catalogAttrs?["artwork"] as? [String: Any],
                   let catTmpl = catArtObj["url"] as? String, !catTmpl.isEmpty,
                   let formatted = Self.formatArtworkUrl(catTmpl, width: 600, height: 600),
                   formatted.hasPrefix("http") {
                    artUrl = formatted
                }
                if artUrl.isEmpty,
                   let artObj = attrs["artwork"] as? [String: Any],
                   let tmpl = artObj["url"] as? String, !tmpl.isEmpty,
                   let formatted = Self.formatArtworkUrl(tmpl, width: 600, height: 600),
                   formatted.hasPrefix("http") {
                    artUrl = formatted
                }
                if !artUrl.isEmpty {
                    artworkBatch.append((album: aName, artist: aArtist, url: artUrl))
                }

                let catTrackCount = catalogAttrs?["trackCount"] as? Int
                let isComplete: Bool? = {
                    if let cc = catTrackCount, cc > 0, let lc = tCount, lc > 0 {
                        return lc >= cc
                    }
                    return nil
                }()

                let parsedTs = Self.parseISO8601Timestamp(dateAdded)
                let alb = AlbumInfo(
                    id: resolvedId,
                    name: aName,
                    artist: aArtist,
                    artwork: artUrl,
                    releaseDate: relDate,
                    trackCount: tCount,
                    genre: genre,
                    inLibrary: true,
                    libraryTrackCount: tCount,
                    catalogTrackCount: catTrackCount,
                    catalogAlbumId: catalogAlbumId,
                    isCompleteInLibrary: isComplete,
                    dateAdded: parsedTs
                )
                parsedEntries.append((dateAdded: dateAdded, album: alb))
            }

            nextPath = json["next"] as? String
        }

        if !artworkBatch.isEmpty {
            registerAlbumArtworksBatch(artworkBatch)
        }

        if !parsedEntries.isEmpty {
            parsedEntries.sort { lhs, rhs in
                if lhs.dateAdded != rhs.dateAdded {
                    return lhs.dateAdded > rhs.dateAdded
                }
                return lhs.album.name.localizedCaseInsensitiveCompare(rhs.album.name) == .orderedAscending
            }
            let sortedAlbums = parsedEntries.map(\.album)
            withLock {
                userLibraryAlbumsCache = (timestamp: Date(), albums: sortedAlbums)
            }
            return sortedAlbums
        }

        return []
    }

    internal static func parseISO8601Timestamp(_ raw: String) -> TimeInterval? {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = frac.date(from: clean) {
            return d.timeIntervalSince1970
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: clean)?.timeIntervalSince1970
    }

    internal func mergeRecentlyAddedIntoAlbums(_ base: [AlbumInfo]) -> [AlbumInfo] {
        let recent = getRecentlyAddedAlbums()
        guard !recent.isEmpty else { return base }
        var result = base
        for r in recent.reversed() {
            if let existingIdx = result.firstIndex(where: { item in
                (!r.id.isEmpty && !item.id.isEmpty && r.id.caseInsensitiveCompare(item.id) == .orderedSame) ||
                Self.albumMatches(r.name, r.artist, item.name, item.artist)
            }) {
                var merged = result.remove(at: existingIdx)
                if merged.artwork.isEmpty && !r.artwork.isEmpty {
                    merged.artwork = r.artwork
                }
                if (merged.trackCount ?? 0) == 0, let rc = r.trackCount, rc > 0 {
                    merged.trackCount = rc
                }
                merged.inLibrary = true
                result.insert(merged, at: 0)
            } else {
                result.insert(r, at: 0)
            }
        }
        return result
    }

    public func getLibraryAlbumTracksById(libraryAlbumId: String) async -> [TrackInfo] {
        let cleanId = libraryAlbumId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanId.hasPrefix("l."),
              Self.isValidResourceIdentifier(cleanId),
              let devToken = getDeveloperToken(),
              let uToken = getUserToken(),
              !uToken.isEmpty else {
            return []
        }
        let lang = getPreferredLanguageTag()
        guard let url = Self.makeAppleMusicAPIURL(
            path: "/v1/me/library/albums/\(cleanId)/tracks",
            queryItems: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "l", value: lang)
            ]
        ) else {
            return []
        }
        var req = URLRequest(url: url, timeoutInterval: 4.5)
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(lang, forHTTPHeaderField: "Accept-Language")

        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tracksData = json["data"] as? [[String: Any]], !tracksData.isEmpty else {
            return []
        }
        var parsed = parseCatalogTrackItems(tracksData)
        if !PlaybackRouter.shared.isTestingEnvironment {
            parsed = LibraryService.shared.resolveLocalLibraryMatches(parsed, updateNames: false)
        }
        return parsed
    }
}
