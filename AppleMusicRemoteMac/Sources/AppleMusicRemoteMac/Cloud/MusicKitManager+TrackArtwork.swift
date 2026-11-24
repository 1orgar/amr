//
//  MusicKitManager+TrackArtwork.swift
//  AppleMusicRemoteMac
//
//  Coalesced track & album artwork search via Apple Music Catalog and iTunes Store fallback.
//

import Foundation

extension MusicKitManager {

    // MARK: - Coalesced Track & Album Artwork Search

    public func searchTrackArtwork(name: String, artist: String, album: String = "", storefront: String = "") async -> String? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty || !cleanAlbum.isEmpty else { return nil }

        if let cached = getCachedTrackArtwork(name: cleanName, artist: cleanArtist, album: cleanAlbum), !cached.isEmpty {
            return cached
        }

        var mainArtist = cleanArtist
        if let ampIdx = mainArtist.range(of: " & ") {
            mainArtist = String(mainArtist[..<ampIdx.lowerBound]).trimmingCharacters(in: .whitespaces)
        } else if let featIdx = mainArtist.range(of: " feat", options: .caseInsensitive) {
            mainArtist = String(mainArtist[..<featIdx.lowerBound]).trimmingCharacters(in: .whitespaces)
        }

        let normAlbum = Self.normalizedAlbumTitle(cleanAlbum)
        let coalescingKey: String = !normAlbum.isEmpty
            ? "alb|\(normAlbum)|\(mainArtist.lowercased())"
            : "trk|\(cleanName.lowercased())|\(cleanArtist.lowercased())"
        let trackNegativeKey = "\(cleanName.lowercased())|\(cleanArtist.lowercased())|\(cleanAlbum.lowercased())"

        let isRecentlyNegative: Bool = withLock {
            let now = Date()
            if let negTs = trackArtworkNegativeCache[trackNegativeKey], now.timeIntervalSince(negTs) < 600.0 {
                return true
            }
            if !normAlbum.isEmpty, let albNegTs = trackArtworkNegativeCache[coalescingKey], now.timeIntervalSince(albNegTs) < 300.0 {
                return true
            }
            return false
        }
        if isRecentlyNegative {
            return nil
        }

        if let existingTask = withLock({ inFlightTrackArtworkTasks[coalescingKey] }) {
            if let sharedArt = await existingTask.value, !sharedArt.isEmpty {
                cacheTrackArtworkUrl(sharedArt, name: cleanName, artist: cleanArtist, album: cleanAlbum)
                return sharedArt
            }
            if !normAlbum.isEmpty, let afterCache = getCachedTrackArtwork(name: cleanName, artist: cleanArtist, album: cleanAlbum), !afterCache.isEmpty {
                return afterCache
            }
            return nil
        }

        let primarySf = Self.sanitizedStorefront(storefront, fallback: getUserStorefront())

        let searchTask = Task<String?, Never> {
            await self.performSearchTrackArtwork(
                cleanName: cleanName,
                cleanArtist: cleanArtist,
                mainArtist: mainArtist,
                cleanAlbum: cleanAlbum,
                primaryStorefront: primarySf
            )
        }

        let taskToAwait: Task<String?, Never> = withLock {
            if let raced = inFlightTrackArtworkTasks[coalescingKey] {
                searchTask.cancel()
                return raced
            }
            inFlightTrackArtworkTasks[coalescingKey] = searchTask
            return searchTask
        }

        let resolvedUrl = await taskToAwait.value
        withLock {
            if inFlightTrackArtworkTasks[coalescingKey] == taskToAwait {
                inFlightTrackArtworkTasks.removeValue(forKey: coalescingKey)
            }
        }

        if let artUrl = resolvedUrl, !artUrl.isEmpty {
            cacheTrackArtworkUrl(artUrl, name: cleanName, artist: cleanArtist, album: cleanAlbum)
            return artUrl
        }

        withLock {
            let now = Date()
            if trackArtworkNegativeCache.count >= Self.maxArtworkCacheEntries {
                trackArtworkNegativeCache = trackArtworkNegativeCache.filter { now.timeIntervalSince($0.value) < 600.0 }
                trimDictionaryIfNeeded(&trackArtworkNegativeCache, maxEntries: Self.maxArtworkCacheEntries)
            }
            trackArtworkNegativeCache[trackNegativeKey] = now
            if cleanName.isEmpty {
                trackArtworkNegativeCache[coalescingKey] = now
            }
        }
        return nil
    }

    internal func performSearchTrackArtwork(
        cleanName: String,
        cleanArtist: String,
        mainArtist: String,
        cleanAlbum: String,
        primaryStorefront: String
    ) async -> String? {
        let simplifiedName = cleanName
            .replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\[.*?\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let simplifiedAlbum = cleanAlbum
            .replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\[.*?\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        var storefronts: [String] = []
        for sf in [primaryStorefront, "us", "ru"] where Self.isValidStorefrontCode(sf) && !storefronts.contains(sf) {
            storefronts.append(sf)
        }

        if let token = getDeveloperToken() {
            let lang = getPreferredLanguageTag()

            for sf in storefronts {
                // 1. Album-first lookup when album name is known
                if !simplifiedAlbum.isEmpty {
                    let albumQuery = [simplifiedAlbum, mainArtist].filter { !$0.isEmpty }.joined(separator: " ")
                    if !albumQuery.isEmpty,
                       let url = Self.makeAppleMusicAPIURL(
                           path: "/v1/catalog/\(sf)/search",
                           queryItems: [
                               URLQueryItem(name: "term", value: albumQuery),
                               URLQueryItem(name: "types", value: "albums,songs"),
                               URLQueryItem(name: "limit", value: "5"),
                               URLQueryItem(name: "l", value: lang)
                           ]
                       ) {
                        var req = URLRequest(url: url, timeoutInterval: 2.2)
                        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                        req.setValue("application/json", forHTTPHeaderField: "Accept")
                        req.setValue(lang, forHTTPHeaderField: "Accept-Language")

                        if let (data, response) = try? await session.data(for: req),
                           let http = response as? HTTPURLResponse, http.statusCode == 200,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let results = json["results"] as? [String: Any] {
                            if let albumsObj = results["albums"] as? [String: Any],
                               let albumsData = albumsObj["data"] as? [[String: Any]] {
                                for cand in albumsData {
                                    guard let attrs = cand["attributes"] as? [String: Any] else { continue }
                                    let candAlbum = (attrs["name"] as? String) ?? ""
                                    let candArtist = (attrs["artistName"] as? String) ?? ""
                                    if (Self.albumMatches(candAlbum, candArtist, cleanAlbum, cleanArtist) ||
                                        Self.albumMatches(candAlbum, candArtist, simplifiedAlbum, mainArtist)),
                                       let artObj = attrs["artwork"] as? [String: Any],
                                       let artTmpl = artObj["url"] as? String,
                                       let formatted = Self.formatArtworkUrl(artTmpl, width: 600, height: 600),
                                       !formatted.isEmpty {
                                        registerAlbumArtwork(album: cleanAlbum, artist: cleanArtist, url: formatted)
                                        return formatted
                                    }
                                }
                            }
                            if !cleanName.isEmpty,
                               let songsObj = results["songs"] as? [String: Any],
                               let songsData = songsObj["data"] as? [[String: Any]] {
                                for song in songsData {
                                    guard let attrs = song["attributes"] as? [String: Any] else { continue }
                                    let sName = (attrs["name"] as? String) ?? ""
                                    let sArtist = (attrs["artistName"] as? String) ?? ""
                                    let sAlbum = (attrs["albumName"] as? String) ?? ""
                                    let (_, isMatch) = Self.computeSongSimilarity(
                                        queryTitle: cleanName,
                                        queryArtist: cleanArtist,
                                        candidateTitle: sName,
                                        candidateArtist: sArtist
                                    )
                                    if isMatch || (!cleanAlbum.isEmpty && Self.albumMatches(sAlbum, sArtist, cleanAlbum, cleanArtist)),
                                       let artObj = attrs["artwork"] as? [String: Any],
                                       let artTmpl = artObj["url"] as? String,
                                       let formatted = Self.formatArtworkUrl(artTmpl, width: 600, height: 600),
                                       !formatted.isEmpty {
                                        if let catId = song["id"] as? String, Self.isValidResourceIdentifier(catId) {
                                            cacheTrackCatalogId(catId, name: cleanName, artist: cleanArtist, album: cleanAlbum)
                                        }
                                        return formatted
                                    }
                                }
                            }
                        }
                    }
                }

                // 2. Song lookup when album was empty or didn't match directly
                if !simplifiedName.isEmpty {
                    let songQuery = [simplifiedName, mainArtist].filter { !$0.isEmpty }.joined(separator: " ")
                    if !songQuery.isEmpty,
                       let url = Self.makeAppleMusicAPIURL(
                           path: "/v1/catalog/\(sf)/search",
                           queryItems: [
                               URLQueryItem(name: "term", value: songQuery),
                               URLQueryItem(name: "types", value: "songs"),
                               URLQueryItem(name: "limit", value: "3"),
                               URLQueryItem(name: "l", value: lang)
                           ]
                       ) {
                        var req = URLRequest(url: url, timeoutInterval: 2.2)
                        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                        req.setValue("application/json", forHTTPHeaderField: "Accept")
                        req.setValue(lang, forHTTPHeaderField: "Accept-Language")

                        if let (data, response) = try? await session.data(for: req),
                           let http = response as? HTTPURLResponse, http.statusCode == 200,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let results = json["results"] as? [String: Any],
                           let songs = results["songs"] as? [String: Any],
                           let dataArr = songs["data"] as? [[String: Any]] {
                            for item in dataArr {
                                guard let attrs = item["attributes"] as? [String: Any] else { continue }
                                let sName = (attrs["name"] as? String) ?? ""
                                let sArtist = (attrs["artistName"] as? String) ?? ""
                                let (_, isMatch) = Self.computeSongSimilarity(
                                    queryTitle: cleanName,
                                    queryArtist: cleanArtist,
                                    candidateTitle: sName,
                                    candidateArtist: sArtist
                                )
                                if isMatch,
                                   let artObj = attrs["artwork"] as? [String: Any],
                                   let artTmpl = artObj["url"] as? String,
                                   let formatted = Self.formatArtworkUrl(artTmpl, width: 600, height: 600),
                                   !formatted.isEmpty {
                                    if let catId = item["id"] as? String, Self.isValidResourceIdentifier(catId) {
                                        cacheTrackCatalogId(catId, name: cleanName, artist: cleanArtist, album: cleanAlbum)
                                    }
                                    return formatted
                                }
                            }
                        }
                    }
                }
            }
        }

        // 3. Single concise fallback to iTunes Store Search API (works without token)
        let fallbackTerm = !simplifiedAlbum.isEmpty
            ? [simplifiedAlbum, mainArtist].filter { !$0.isEmpty }.joined(separator: " ")
            : [simplifiedName, mainArtist].filter { !$0.isEmpty }.joined(separator: " ")
        if !fallbackTerm.isEmpty {
            let entity = (!simplifiedAlbum.isEmpty && simplifiedName.isEmpty) ? "album" : "song"
            let countryCode = Self.sanitizedStorefront(primaryStorefront, fallback: "us")
            var iComps = URLComponents()
            iComps.scheme = "https"
            iComps.host = "itunes.apple.com"
            iComps.path = "/search"
            iComps.queryItems = [
                URLQueryItem(name: "term", value: fallbackTerm),
                URLQueryItem(name: "entity", value: entity),
                URLQueryItem(name: "limit", value: "3"),
                URLQueryItem(name: "country", value: countryCode)
            ]
            if let itunesUrl = iComps.url {
                var req = URLRequest(url: itunesUrl, timeoutInterval: 2.0)
                req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
                if let (data, response) = try? await session.data(for: req),
                   let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let results = json["results"] as? [[String: Any]],
                   let first = results.first,
                   let rawArt = first["artworkUrl100"] as? String, !rawArt.isEmpty {
                    let artUrl = rawArt.replacingOccurrences(of: "100x100bb", with: "600x600bb")
                    if let itunesTrackId = first["trackId"] as? Int, itunesTrackId > 0, !cleanName.isEmpty {
                        cacheTrackCatalogId("\(itunesTrackId)", name: cleanName, artist: cleanArtist, album: cleanAlbum)
                    }
                    return artUrl
                }
            }
        }

        return nil
    }
}
