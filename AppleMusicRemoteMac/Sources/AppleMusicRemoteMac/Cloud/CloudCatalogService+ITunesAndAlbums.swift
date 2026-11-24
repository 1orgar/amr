//
//  CloudCatalogService+ITunesAndAlbums.swift
//  AppleMusicRemoteMac
//
//  iTunes Store search/lookup/RSS fallbacks and album details with URLComponents validation.
//

import Foundation

extension CloudCatalogService {

    internal static func makeITunesSearchURL(
        term: String,
        entity: String,
        country: String,
        limit: Int,
        lang: String
    ) -> URL? {
        let safeCountry = MusicKitManager.sanitizedStorefront(country)
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "itunes.apple.com"
        comps.path = "/search"
        comps.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "country", value: safeCountry),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "lang", value: lang)
        ]
        return comps.url
    }

    internal func fetchArtists(query: String, country: String, limit: Int = 8, offset: Int = 0) async -> [[String: Any]] {
        let totalToFetch = max(1, min(200, offset + limit))
        let langInfo = Self.itunesLangInfo(country: country)
        guard let url = Self.makeITunesSearchURL(
            term: query,
            entity: "musicArtist",
            country: country,
            limit: totalToFetch,
            lang: langInfo.itunesLang
        ) else { return [] }

        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        req.setValue(langInfo.acceptLang, forHTTPHeaderField: "Accept-Language")

        guard let (data, _) = try? await session.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }

        var list = [[String: Any]]()
        for it in results {
            let name = it["artistName"] as? String ?? ""
            let genre = it["primaryGenreName"] as? String ?? ""
            let url = it["artistLinkUrl"] as? String ?? ""
            let aid = "\(it["artistId"] ?? "")"
            list.append([
                "type": "artist",
                "id": aid,
                "name": name,
                "genre": genre,
                "url": url
            ])
        }
        if offset < list.count {
            let end = min(offset + limit, list.count)
            return Array(list[offset..<end])
        }
        return []
    }

    internal func fetchSongs(query: String, country: String, limit: Int = 50, offset: Int = 0) async -> [[String: Any]] {
        let totalToFetch = max(1, min(200, offset + limit))
        let langInfo = Self.itunesLangInfo(country: country)
        guard let url = Self.makeITunesSearchURL(
            term: query,
            entity: "song",
            country: country,
            limit: totalToFetch,
            lang: langInfo.itunesLang
        ) else { return [] }

        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        req.setValue(langInfo.acceptLang, forHTTPHeaderField: "Accept-Language")

        guard let (data, _) = try? await session.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }

        var list = [[String: Any]]()
        for it in results {
            let name = it["trackName"] as? String ?? ""
            let artist = it["artistName"] as? String ?? ""
            let album = it["collectionName"] as? String ?? ""
            let url = it["trackViewUrl"] as? String ?? ""
            let rawArt = it["artworkUrl100"] as? String ?? ""
            let art = upgradeArtworkUrl(rawArt)
            let durMs = (it["trackTimeMillis"] as? Double) ?? 0
            let tid = "\(it["trackId"] ?? "")"
            let preview = it["previewUrl"] as? String ?? ""

            list.append([
                "type": "song",
                "id": tid,
                "name": name,
                "artist": artist,
                "album": album,
                "duration": durMs / 1000.0,
                "artwork": art,
                "artwork_url": art,
                "url": url,
                "preview_url": preview
            ])
        }
        if offset < list.count {
            let end = min(offset + limit, list.count)
            return Array(list[offset..<end])
        }
        return []
    }

    internal func fetchAlbums(query: String, country: String, limit: Int = 12, offset: Int = 0) async -> [[String: Any]] {
        let totalToFetch = max(1, min(200, offset + limit))
        let langInfo = Self.itunesLangInfo(country: country)
        guard let url = Self.makeITunesSearchURL(
            term: query,
            entity: "album",
            country: country,
            limit: totalToFetch,
            lang: langInfo.itunesLang
        ) else { return [] }

        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        req.setValue(langInfo.acceptLang, forHTTPHeaderField: "Accept-Language")

        guard let (data, _) = try? await session.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }

        var list = [[String: Any]]()
        for it in results {
            let name = it["collectionName"] as? String ?? ""
            let artist = it["artistName"] as? String ?? ""
            let url = it["collectionViewUrl"] as? String ?? ""
            let rawArt = it["artworkUrl100"] as? String ?? ""
            let art = upgradeArtworkUrl(rawArt)
            let relDate = it["releaseDate"] as? String ?? ""
            let tCount = (it["trackCount"] as? Int) ?? 0
            let aid = "\(it["collectionId"] ?? "")"

            list.append([
                "type": "album",
                "id": aid,
                "name": name,
                "artist": artist,
                "artwork": art,
                "artwork_url": art,
                "release_date": relDate,
                "track_count": tCount,
                "url": url
            ])
        }
        if offset < list.count {
            let end = min(offset + limit, list.count)
            return Array(list[offset..<end])
        }
        return []
    }

    internal func fetchTopSongsRSS(country: String) async -> [[String: Any]] {
        let safeCountry = MusicKitManager.sanitizedStorefront(country)
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "itunes.apple.com"
        comps.path = "/\(safeCountry)/rss/topsongs/limit=50/json"
        guard let url = comps.url else { return [] }

        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await session.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feed = json["feed"] as? [String: Any],
              let entries = feed["entry"] as? [[String: Any]] else {
            return []
        }

        var parsed = [[String: Any]]()
        var rank = 1

        for e in entries {
            let name = (e["im:name"] as? [String: Any])?["label"] as? String ?? ""
            let artist = (e["im:artist"] as? [String: Any])?["label"] as? String ?? ""

            var artUrl = ""
            if let images = e["im:image"] as? [[String: Any]], let lastImg = images.last {
                artUrl = upgradeArtworkUrl(lastImg["label"] as? String ?? "")
            }

            var urlStr = ""
            var previewUrl = ""
            if let links = e["link"] as? [[String: Any]] {
                if let first = links.first, let attrs = first["attributes"] as? [String: Any] {
                    urlStr = attrs["href"] as? String ?? ""
                }
                for l in links {
                    if let attrs = l["attributes"] as? [String: Any] {
                        let rel = attrs["rel"] as? String ?? ""
                        let type = attrs["type"] as? String ?? ""
                        if rel == "enclosure" || type.contains("audio") {
                            previewUrl = attrs["href"] as? String ?? ""
                            break
                        }
                    }
                }
            } else if let link = e["link"] as? [String: Any], let attrs = link["attributes"] as? [String: Any] {
                urlStr = attrs["href"] as? String ?? ""
            }

            let idStr = (e["id"] as? [String: Any])?["attributes"] as? [String: Any]
            let trackId = idStr?["im:id"] as? String ?? ""

            parsed.append([
                "rank": rank,
                "id": trackId,
                "name": name,
                "artist": artist,
                "artwork": artUrl,
                "url": urlStr,
                "preview_url": previewUrl
            ])
            rank += 1
        }

        return parsed
    }

    internal func fetchTopAlbumsRSS(country: String) async -> [[String: Any]] {
        let safeCountry = MusicKitManager.sanitizedStorefront(country)
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "itunes.apple.com"
        comps.path = "/\(safeCountry)/rss/topalbums/limit=50/json"
        guard let url = comps.url else { return [] }

        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await session.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feed = json["feed"] as? [String: Any],
              let entries = feed["entry"] as? [[String: Any]] else {
            return []
        }

        var parsed = [[String: Any]]()
        var rank = 1

        for e in entries {
            let name = (e["im:name"] as? [String: Any])?["label"] as? String ?? ""
            let artist = (e["im:artist"] as? [String: Any])?["label"] as? String ?? ""

            var artUrl = ""
            if let images = e["im:image"] as? [[String: Any]], let lastImg = images.last {
                artUrl = upgradeArtworkUrl(lastImg["label"] as? String ?? "")
            }

            var urlStr = ""
            if let links = e["link"] as? [[String: Any]], let first = links.first, let attrs = first["attributes"] as? [String: Any] {
                urlStr = attrs["href"] as? String ?? ""
            } else if let link = e["link"] as? [String: Any], let attrs = link["attributes"] as? [String: Any] {
                urlStr = attrs["href"] as? String ?? ""
            }

            let idStr = (e["id"] as? [String: Any])?["attributes"] as? [String: Any]
            let albumId = idStr?["im:id"] as? String ?? ""

            parsed.append([
                "rank": rank,
                "id": albumId,
                "name": name,
                "artist": artist,
                "artwork": artUrl,
                "url": urlStr
            ])
            rank += 1
        }

        return parsed
    }

    // MARK: - Album Details

    public func getAlbumDetails(albumId: String, country: String = "") async -> AlbumInfo? {
        let cleanAlbumId = albumId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard MusicKitManager.isValidResourceIdentifier(cleanAlbumId) else { return nil }
        let c = MusicKitManager.sanitizedStorefront(MusicKitManager.shared.resolveEffectiveStorefront(country))

        // 1. Primary: Official Apple Music Catalog API via Developer Token
        if let mkAlbum = await MusicKitManager.shared.getAlbumDetailsById(albumId: cleanAlbumId, storefront: c),
           let tracks = mkAlbum.tracks, !tracks.isEmpty {
            return mkAlbum
        }
        if c != "us", let usAlbum = await MusicKitManager.shared.getAlbumDetailsById(albumId: cleanAlbumId, storefront: "us"),
           let tracks = usAlbum.tracks, !tracks.isEmpty {
            return usAlbum
        }

        // 2. Secondary fallback: iTunes Lookup API via URLComponents
        var lComps = URLComponents()
        lComps.scheme = "https"
        lComps.host = "itunes.apple.com"
        lComps.path = "/lookup"
        lComps.queryItems = [
            URLQueryItem(name: "id", value: cleanAlbumId),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "country", value: c)
        ]
        guard let url = lComps.url else { return nil }

        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await session.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]], !results.isEmpty else {
            return nil
        }

        let albumMeta = results[0]
        let aName = albumMeta["collectionName"] as? String ?? ""
        let aArtist = albumMeta["artistName"] as? String ?? ""
        let aArt = upgradeArtworkUrl(albumMeta["artworkUrl100"] as? String ?? "")
        let relDate = albumMeta["releaseDate"] as? String ?? ""
        let genre = albumMeta["primaryGenreName"] as? String ?? ""
        let aUrl = albumMeta["collectionViewUrl"] as? String ?? ""
        let tCount = albumMeta["trackCount"] as? Int ?? 0

        var tracks = [TrackInfo]()
        for i in 1..<results.count {
            let it = results[i]
            if (it["wrapperType"] as? String) == "track" {
                let tName = it["trackName"] as? String ?? ""
                let tArtist = it["artistName"] as? String ?? aArtist
                let tUrl = it["trackViewUrl"] as? String ?? ""
                let tArt = upgradeArtworkUrl(it["artworkUrl100"] as? String ?? aArt)
                let durMs = (it["trackTimeMillis"] as? Double) ?? 0
                let tNum = tracks.count + 1
                let tid = "\(it["trackId"] ?? "")"
                let preview = it["previewUrl"] as? String ?? ""

                tracks.append(TrackInfo(
                    id: tid,
                    numericId: Int(tid),
                    name: tName,
                    artist: tArtist,
                    album: aName,
                    duration: durMs / 1000.0,
                    hasArtwork: !tArt.isEmpty,
                    artworkUrl: tArt,
                    favorited: false,
                    isLocal: false,
                    url: tUrl,
                    previewUrl: preview,
                    index: tNum
                ))
            }
        }

        return AlbumInfo(
            id: cleanAlbumId,
            name: aName,
            artist: aArtist,
            artwork: aArt,
            releaseDate: relDate,
            trackCount: tCount > 0 ? tCount : tracks.count,
            genre: genre,
            url: aUrl,
            tracks: tracks
        )
    }
}
