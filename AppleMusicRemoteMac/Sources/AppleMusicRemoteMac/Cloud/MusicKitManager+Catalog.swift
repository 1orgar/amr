//
//  MusicKitManager+Catalog.swift
//  AppleMusicRemoteMac
//
//  Apple Music Catalog search, top charts, playlist artwork lookup,
//  and bounded in-memory artwork/catalog-ID/station caches.
//

import Foundation

extension MusicKitManager {
    // MARK: - Apple Music API Requests

    public func searchAppleMusic(query: String, storefront: String = "", limit: Int = 25, offset: Int = 0, timeout: TimeInterval = 5.0) async -> [String: Any]? {
        guard !Task.isCancelled else { return nil }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty, let token = getDeveloperToken() else { return nil }

        let sf = Self.sanitizedStorefront(storefront, fallback: getUserStorefront())
        let effectiveLimit = max(1, min(limit, 25))
        let lang = getPreferredLanguageTag()
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "term", value: trimmedQuery),
            URLQueryItem(name: "types", value: "songs,albums,artists,playlists"),
            URLQueryItem(name: "limit", value: "\(effectiveLimit)")
        ]
        if offset > 0 {
            queryItems.append(URLQueryItem(name: "offset", value: "\(offset)"))
        }
        queryItems.append(URLQueryItem(name: "l", value: lang))

        guard let url = Self.makeAppleMusicAPIURL(path: "/v1/catalog/\(sf)/search", queryItems: queryItems) else {
            return nil
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let uToken = getUserToken(), !uToken.isEmpty {
            request.setValue(uToken, forHTTPHeaderField: "Music-User-Token")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(lang, forHTTPHeaderField: "Accept-Language")

        guard let (data, response) = try? await session.data(for: request),
              !Task.isCancelled,
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any] else {
            return nil
        }

        return parseSearchResults(results)
    }

    public func getTopCharts(storefront: String = "", limit: Int = 20) async -> [[String: Any]] {
        let (songs, _) = await getTopChartsFull(storefront: storefront, limit: limit)
        return songs
    }

    public func getTopChartsFull(storefront: String = "", limit: Int = 25) async -> (songs: [[String: Any]], albums: [[String: Any]]) {
        guard let token = getDeveloperToken() else { return ([], []) }

        let sf = Self.sanitizedStorefront(storefront, fallback: getUserStorefront())
        let clampedLimit = max(1, min(limit, 50))
        let lang = getPreferredLanguageTag()
        guard let url = Self.makeAppleMusicAPIURL(
            path: "/v1/catalog/\(sf)/charts",
            queryItems: [
                URLQueryItem(name: "types", value: "songs,albums"),
                URLQueryItem(name: "limit", value: "\(clampedLimit)"),
                URLQueryItem(name: "l", value: lang)
            ]
        ) else { return ([], []) }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(lang, forHTTPHeaderField: "Accept-Language")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any] else {
            return ([], [])
        }

        var songsList = [[String: Any]]()
        if let songsCharts = results["songs"] as? [[String: Any]],
           let songData = songsCharts.first?["data"] as? [[String: Any]] {
            for item in songData {
                if let parsed = parseCatalogSong(item) {
                    songsList.append(parsed)
                }
            }
        }

        var albumsList = [[String: Any]]()
        if let albumsCharts = results["albums"] as? [[String: Any]],
           let albumData = albumsCharts.first?["data"] as? [[String: Any]] {
            for item in albumData {
                if let parsed = parseCatalogAlbum(item) {
                    albumsList.append(parsed)
                }
            }
        }

        return (songsList, albumsList)
    }

    public func searchPlaylistArtwork(name: String, storefront: String = "") async -> String? {
        guard let token = getDeveloperToken() else { return nil }
        var query = name
        if let barIdx = query.firstIndex(of: "|") {
            query = String(query[..<barIdx]).trimmingCharacters(in: .whitespaces)
        }
        let cleanSearch = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSearch.isEmpty else { return nil }

        let sf = Self.sanitizedStorefront(storefront, fallback: getUserStorefront())
        let lang = getPreferredLanguageTag()
        guard let url = Self.makeAppleMusicAPIURL(
            path: "/v1/catalog/\(sf)/search",
            queryItems: [
                URLQueryItem(name: "term", value: cleanSearch),
                URLQueryItem(name: "types", value: "playlists"),
                URLQueryItem(name: "limit", value: "3"),
                URLQueryItem(name: "l", value: lang)
            ]
        ) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(lang, forHTTPHeaderField: "Accept-Language")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let playlists = results["playlists"] as? [String: Any],
              let dataArr = playlists["data"] as? [[String: Any]] else {
            return nil
        }

        let cleanTarget = cleanSearch.lowercased()
        for item in dataArr {
            guard let attrs = item["attributes"] as? [String: Any],
                  let artObj = attrs["artwork"] as? [String: Any],
                  let artTemplate = artObj["url"] as? String else { continue }
            let itemPlName = (attrs["name"] as? String ?? "").lowercased().trimmingCharacters(in: .whitespaces)
            if itemPlName == cleanTarget || itemPlName.contains(cleanTarget) || cleanTarget.contains(itemPlName) {
                return artTemplate
                    .replacingOccurrences(of: "{w}x{h}", with: "600x600")
                    .replacingOccurrences(of: "{f}", with: "jpg")
            }
        }

        if let first = dataArr.first,
           let attrs = first["attributes"] as? [String: Any],
           let artObj = attrs["artwork"] as? [String: Any],
           let artTemplate = artObj["url"] as? String {
            return artTemplate
                .replacingOccurrences(of: "{w}x{h}", with: "600x600")
                .replacingOccurrences(of: "{f}", with: "jpg")
        }

        return nil
    }

    // MARK: - Bounded Artwork, Catalog-ID & Station Caches

    internal func trimDictionaryIfNeeded<V>(_ dict: inout [String: V], maxEntries: Int) {
        guard dict.count >= maxEntries else { return }
        let targetKeep = maxEntries / 2
        var pruned: [String: V] = [:]
        pruned.reserveCapacity(targetKeep + 16)
        for (k, v) in dict where pruned.count < targetKeep {
            pruned[k] = v
        }
        dict = pruned
    }

    public func registerAlbumArtwork(album: String, artist: String, url: String, persist: Bool = true) {
        let cleanAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAlbum.isEmpty,
              cleanUrl.hasPrefix("http://") || cleanUrl.hasPrefix("https://") else { return }
        let normTitle = Self.normalizedAlbumTitle(cleanAlbum)
        guard !normTitle.isEmpty else { return }

        withLock {
            if albumArtworkCacheByNormTitle[normTitle] == nil {
                trimDictionaryIfNeeded(&albumArtworkCacheByNormTitle, maxEntries: Self.maxArtworkCacheEntries)
            }
            var bucket = albumArtworkCacheByNormTitle[normTitle] ?? []
            if let idx = bucket.firstIndex(where: { Self.albumMatches($0.album, $0.artist, cleanAlbum, cleanArtist) }) {
                bucket[idx] = (album: cleanAlbum, artist: cleanArtist, url: cleanUrl)
            } else {
                bucket.append((album: cleanAlbum, artist: cleanArtist, url: cleanUrl))
                if bucket.count > 8 {
                    bucket.removeFirst(bucket.count - 8)
                }
            }
            albumArtworkCacheByNormTitle[normTitle] = bucket
        }

        if persist && !isTestingProcess && !PlaybackRouter.shared.isTestingEnvironment {
            ArtworkUrlDiskCache.shared.storeAlbumArtworks([
                (normTitle: normTitle, album: cleanAlbum, artist: cleanArtist, url: cleanUrl)
            ])
        }
    }

    public func registerAlbumArtworksBatch(_ items: [(album: String, artist: String, url: String)]) {
        guard !items.isEmpty else { return }
        var diskBatch: [(normTitle: String, album: String, artist: String, url: String)] = []
        diskBatch.reserveCapacity(items.count)

        withLock {
            for item in items {
                let cleanAlbum = item.album.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanArtist = item.artist.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanUrl = item.url.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanAlbum.isEmpty,
                      cleanUrl.hasPrefix("http://") || cleanUrl.hasPrefix("https://") else { continue }
                let normTitle = Self.normalizedAlbumTitle(cleanAlbum)
                guard !normTitle.isEmpty else { continue }

                if albumArtworkCacheByNormTitle[normTitle] == nil {
                    trimDictionaryIfNeeded(&albumArtworkCacheByNormTitle, maxEntries: Self.maxArtworkCacheEntries)
                }
                var bucket = albumArtworkCacheByNormTitle[normTitle] ?? []
                if let idx = bucket.firstIndex(where: { Self.albumMatches($0.album, $0.artist, cleanAlbum, cleanArtist) }) {
                    bucket[idx] = (album: cleanAlbum, artist: cleanArtist, url: cleanUrl)
                } else {
                    bucket.append((album: cleanAlbum, artist: cleanArtist, url: cleanUrl))
                    if bucket.count > 8 {
                        bucket.removeFirst(bucket.count - 8)
                    }
                }
                albumArtworkCacheByNormTitle[normTitle] = bucket
                diskBatch.append((normTitle: normTitle, album: cleanAlbum, artist: cleanArtist, url: cleanUrl))
            }
        }

        if !diskBatch.isEmpty && !isTestingProcess && !PlaybackRouter.shared.isTestingEnvironment {
            ArtworkUrlDiskCache.shared.storeAlbumArtworks(diskBatch)
        }
    }

    public func cacheTrackArtworkUrl(_ url: String, name: String, artist: String, album: String = "", persist: Bool = true) {
        let cleanUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanUrl.hasPrefix("http://") || cleanUrl.hasPrefix("https://") else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)

        var storedKeys: [String] = []
        if !cleanName.isEmpty {
            let lowerName = cleanName.lowercased()
            let lowerArtist = cleanArtist.lowercased()
            let lowerAlbum = cleanAlbum.lowercased()
            let k1 = "\(lowerName)|\(lowerArtist)"
            storedKeys.append(k1)
            if !lowerAlbum.isEmpty {
                storedKeys.append("\(lowerName)|\(lowerArtist)|\(lowerAlbum)")
            }
            withLock {
                for k in storedKeys {
                    if trackArtworkCache[k] == nil {
                        trimDictionaryIfNeeded(&trackArtworkCache, maxEntries: Self.maxArtworkCacheEntries)
                    }
                    trackArtworkCache[k] = cleanUrl
                    trackArtworkNegativeCache.removeValue(forKey: k)
                }
            }
            if persist && !isTestingProcess && !PlaybackRouter.shared.isTestingEnvironment {
                ArtworkUrlDiskCache.shared.storeTrackUrl(cleanUrl, forKeys: storedKeys)
            }
        }
        if !cleanAlbum.isEmpty {
            registerAlbumArtwork(album: cleanAlbum, artist: cleanArtist, url: cleanUrl, persist: persist)
        }
    }

    public func getCachedAlbumArtwork(album: String, artist: String = "") -> String? {
        let cleanAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAlbum.isEmpty else { return nil }
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let normTitle = Self.normalizedAlbumTitle(cleanAlbum)
        guard !normTitle.isEmpty else { return nil }

        return withLock {
            if let bucket = albumArtworkCacheByNormTitle[normTitle] {
                if let match = bucket.first(where: { Self.albumMatches($0.album, $0.artist, cleanAlbum, cleanArtist) }),
                   !match.url.isEmpty {
                    return match.url
                }
            }
            for item in recentlyAddedLibraryAlbums {
                if Self.albumMatches(item.album.name, item.album.artist, cleanAlbum, cleanArtist),
                   item.album.artwork.hasPrefix("http") {
                    return item.album.artwork
                }
            }
            if let cloudAlbums = userLibraryAlbumsCache?.albums {
                if let match = cloudAlbums.first(where: {
                    $0.artwork.hasPrefix("http") && Self.albumMatches($0.name, $0.artist, cleanAlbum, cleanArtist)
                }) {
                    return match.artwork
                }
            }
            return nil
        }
    }

    public func getCachedTrackArtwork(name: String, artist: String, album: String = "") -> String? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)

        if !cleanName.isEmpty {
            let exactHit: String? = withLock {
                if !cleanAlbum.isEmpty {
                    if let cached = trackArtworkCache["\(cleanName)|\(cleanArtist)|\(cleanAlbum.lowercased())"], !cached.isEmpty {
                        return cached
                    }
                }
                if let cached = trackArtworkCache["\(cleanName)|\(cleanArtist)"], !cached.isEmpty {
                    return cached
                }
                return nil
            }
            if let hit = exactHit {
                return hit
            }
        }

        if !cleanAlbum.isEmpty {
            return getCachedAlbumArtwork(album: cleanAlbum, artist: artist)
        }
        return nil
    }

    public func cacheTrackCatalogId(_ id: String, name: String, artist: String, album: String = "") {
        let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.isValidResourceIdentifier(cleanId), cleanId != "0", !cleanName.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        if !cleanAlbum.isEmpty {
            let k = "\(cleanName)|\(cleanArtist)|\(cleanAlbum)"
            if trackCatalogIdCache[k] == nil {
                trimDictionaryIfNeeded(&trackCatalogIdCache, maxEntries: Self.maxArtworkCacheEntries)
            }
            trackCatalogIdCache[k] = cleanId
        }
        let kMain = "\(cleanName)|\(cleanArtist)"
        if trackCatalogIdCache[kMain] == nil {
            trimDictionaryIfNeeded(&trackCatalogIdCache, maxEntries: Self.maxArtworkCacheEntries)
        }
        trackCatalogIdCache[kMain] = cleanId
    }

    public func getCachedTrackCatalogId(name: String, artist: String, album: String = "") -> String? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanName.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if !cleanAlbum.isEmpty {
            if let cached = trackCatalogIdCache["\(cleanName)|\(cleanArtist)|\(cleanAlbum)"], !cached.isEmpty {
                return cached
            }
        }
        if let cached = trackCatalogIdCache["\(cleanName)|\(cleanArtist)"], !cached.isEmpty {
            return cached
        }
        return nil
    }

    public func getCachedArtistStation(for key: String) -> ArtistStationInfo? {
        lock.lock()
        defer { lock.unlock() }
        return artistStationCache[key.lowercased()]
    }

    public func setCachedArtistStation(_ info: ArtistStationInfo, for key: String) {
        let lowerKey = key.lowercased()
        lock.lock()
        defer { lock.unlock() }
        if artistStationCache[lowerKey] == nil {
            trimDictionaryIfNeeded(&artistStationCache, maxEntries: Self.maxStationCacheEntries)
        }
        artistStationCache[lowerKey] = info
    }

    public func getCachedTrackStation(for key: String) -> TrackStationInfo? {
        lock.lock()
        defer { lock.unlock() }
        return trackStationCache[key.lowercased()]
    }

    public func setCachedTrackStation(_ info: TrackStationInfo, for key: String) {
        let lowerKey = key.lowercased()
        lock.lock()
        defer { lock.unlock() }
        if trackStationCache[lowerKey] == nil {
            trimDictionaryIfNeeded(&trackStationCache, maxEntries: Self.maxStationCacheEntries)
        }
        trackStationCache[lowerKey] = info
    }
}
