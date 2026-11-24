//
//  MusicKitManager+CatalogAlbums.swift
//  AppleMusicRemoteMac
//
//  Catalog album track listing, detailed album inspection by ID, and album summary search
//  with strict identifier & pagination-host validation.
//

import Foundation

extension MusicKitManager {

    // MARK: - Album Tracks & Details (MusicKit Catalog)

    public func getAlbumTracks(album: String, artist: String, storefront: String = "") async -> [TrackInfo] {
        guard let token = getDeveloperToken() else { return [] }
        let cleanAlbum = album
            .replacingOccurrences(of: "(30th Anniversary Super Deluxe Edition)", with: "")
            .replacingOccurrences(of: "(30th Anniversary Edition)", with: "")
            .replacingOccurrences(of: "(Deluxe Edition)", with: "")
            .replacingOccurrences(of: "(Deluxe)", with: "")
            .replacingOccurrences(of: "[Deluxe Edition]", with: "")
            .trimmingCharacters(in: .whitespaces)
        let query = "\(cleanAlbum) \(artist)".trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }

        let sf = Self.sanitizedStorefront(storefront, fallback: getUserStorefront())
        let lang = getPreferredLanguageTag()
        guard let searchUrl = Self.makeAppleMusicAPIURL(
            path: "/v1/catalog/\(sf)/search",
            queryItems: [
                URLQueryItem(name: "term", value: query),
                URLQueryItem(name: "types", value: "albums"),
                URLQueryItem(name: "limit", value: "1"),
                URLQueryItem(name: "l", value: lang)
            ]
        ) else { return [] }

        var sReq = URLRequest(url: searchUrl)
        sReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        sReq.setValue("application/json", forHTTPHeaderField: "Accept")
        sReq.setValue(lang, forHTTPHeaderField: "Accept-Language")

        guard let (sData, sResp) = try? await session.data(for: sReq),
              let sHttp = sResp as? HTTPURLResponse, sHttp.statusCode == 200,
              let sJson = try? JSONSerialization.jsonObject(with: sData) as? [String: Any],
              let results = sJson["results"] as? [String: Any],
              let albums = results["albums"] as? [String: Any],
              let dataArr = albums["data"] as? [[String: Any]],
              let firstAlbum = dataArr.first,
              let albumId = firstAlbum["id"] as? String,
              Self.isValidResourceIdentifier(albumId) else {
            return []
        }

        var res = [TrackInfo]()
        var seenTrackIds = Set<String>()
        var nextPath: String? = "/v1/catalog/\(sf)/albums/\(albumId)/tracks"
        var pagesFetched = 0

        while let path = nextPath, pagesFetched < 5 {
            pagesFetched += 1
            guard let tracksUrl = Self.resolveSafeAppleMusicPaginationURL(
                path,
                extraQueryItems: [
                    URLQueryItem(name: "limit", value: "100"),
                    URLQueryItem(name: "l", value: lang)
                ]
            ) else { break }

            var tReq = URLRequest(url: tracksUrl)
            tReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            tReq.setValue("application/json", forHTTPHeaderField: "Accept")
            tReq.setValue(lang, forHTTPHeaderField: "Accept-Language")

            guard let (tData, tResp) = try? await session.data(for: tReq),
                  let tHttp = tResp as? HTTPURLResponse, tHttp.statusCode == 200,
                  let tJson = try? JSONSerialization.jsonObject(with: tData) as? [String: Any],
                  let tracksData = tJson["data"] as? [[String: Any]], !tracksData.isEmpty else {
                break
            }

            for (i, item) in tracksData.enumerated() {
                guard let attrs = item["attributes"] as? [String: Any] else { continue }
                let rawId = item["id"] as? String ?? ""
                if !rawId.isEmpty && seenTrackIds.contains(rawId) {
                    continue
                }
                if !rawId.isEmpty {
                    seenTrackIds.insert(rawId)
                }
                let name = attrs["name"] as? String ?? ""
                let trackArtist = attrs["artistName"] as? String ?? artist
                let durMs = attrs["durationInMillis"] as? Double ?? 0
                let trackNumber = res.count + 1
                let idStr = !rawId.isEmpty ? rawId : "\(res.count + i + 1)"
                let numericId = Int(idStr) ?? trackNumber
                let playUrl = attrs["url"] as? String

                var artUrl = ""
                if let artObj = attrs["artwork"] as? [String: Any],
                   let tmpl = artObj["url"] as? String {
                    artUrl = tmpl.replacingOccurrences(of: "{w}x{h}", with: "600x600").replacingOccurrences(of: "{f}", with: "jpg")
                }

                if Self.isValidResourceIdentifier(rawId) {
                    cacheTrackCatalogId(rawId, name: name, artist: trackArtist, album: album)
                }
                res.append(TrackInfo(
                    id: idStr,
                    numericId: numericId,
                    name: name,
                    artist: trackArtist,
                    album: album,
                    duration: durMs / 1000.0,
                    hasArtwork: !artUrl.isEmpty,
                    artworkUrl: artUrl,
                    favorited: false,
                    isLocal: false,
                    url: playUrl,
                    index: trackNumber,
                    catalogId: idStr
                ))
            }

            nextPath = tJson["next"] as? String
        }

        return res
    }

    public func getAlbumDetailsById(albumId: String, storefront: String = "") async -> AlbumInfo? {
        let cleanAlbumId = albumId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidResourceIdentifier(cleanAlbumId),
              let token = getDeveloperToken() else { return nil }
        let sf = Self.sanitizedStorefront(storefront, fallback: getUserStorefront())
        let lang = getPreferredLanguageTag()
        guard let url = Self.makeAppleMusicAPIURL(
            path: "/v1/catalog/\(sf)/albums/\(cleanAlbumId)",
            queryItems: [URLQueryItem(name: "l", value: lang)]
        ) else { return nil }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(lang, forHTTPHeaderField: "Accept-Language")

        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArr = json["data"] as? [[String: Any]],
              let albumObj = dataArr.first else {
            return nil
        }

        let attrs = albumObj["attributes"] as? [String: Any] ?? [:]
        let aName = attrs["name"] as? String ?? ""
        let aArtist = attrs["artistName"] as? String ?? ""
        let aUrl = attrs["url"] as? String ?? "https://music.apple.com/album/\(cleanAlbumId)"
        let relDate = attrs["releaseDate"] as? String ?? ""
        let tCount = attrs["trackCount"] as? Int ?? 0
        let genres = (attrs["genreNames"] as? [String])?.first ?? ""

        var aArt = ""
        if let artObj = attrs["artwork"] as? [String: Any],
           let tmpl = artObj["url"] as? String {
            aArt = tmpl.replacingOccurrences(of: "{w}x{h}", with: "600x600").replacingOccurrences(of: "{f}", with: "jpg")
        }

        var tracks = [TrackInfo]()
        var seenTrackIds = Set<String>()
        var nextTracksPath: String? = nil

        func appendAlbumTrackItems(_ items: [[String: Any]]) {
            for (i, item) in items.enumerated() {
                guard let tAttrs = item["attributes"] as? [String: Any] else { continue }
                let rawId = item["id"] as? String ?? ""
                if !rawId.isEmpty && seenTrackIds.contains(rawId) {
                    continue
                }
                if !rawId.isEmpty {
                    seenTrackIds.insert(rawId)
                }
                let tName = tAttrs["name"] as? String ?? ""
                let tArtist = tAttrs["artistName"] as? String ?? aArtist
                let durMs = tAttrs["durationInMillis"] as? Double ?? 0
                let trackNumber = tracks.count + 1
                let idStr = !rawId.isEmpty ? rawId : "\(tracks.count + i + 1)"
                let numericId = Int(idStr) ?? trackNumber
                let playUrl = tAttrs["url"] as? String

                var tArt = aArt
                if let artObj = tAttrs["artwork"] as? [String: Any],
                   let tmpl = artObj["url"] as? String {
                    tArt = tmpl.replacingOccurrences(of: "{w}x{h}", with: "600x600").replacingOccurrences(of: "{f}", with: "jpg")
                }

                if Self.isValidResourceIdentifier(rawId) {
                    cacheTrackCatalogId(rawId, name: tName, artist: tArtist, album: aName)
                }

                tracks.append(TrackInfo(
                    id: idStr,
                    numericId: numericId,
                    name: tName,
                    artist: tArtist,
                    album: aName,
                    duration: durMs / 1000.0,
                    hasArtwork: !tArt.isEmpty,
                    artworkUrl: tArt,
                    favorited: false,
                    isLocal: false,
                    url: playUrl,
                    index: trackNumber,
                    catalogId: !rawId.isEmpty ? rawId : nil
                ))
            }
        }

        if let rels = albumObj["relationships"] as? [String: Any],
           let trksObj = rels["tracks"] as? [String: Any] {
            if let trksData = trksObj["data"] as? [[String: Any]] {
                appendAlbumTrackItems(trksData)
            }
            nextTracksPath = trksObj["next"] as? String
        }

        if tracks.isEmpty {
            nextTracksPath = "/v1/catalog/\(sf)/albums/\(cleanAlbumId)/tracks?limit=100"
        } else if nextTracksPath == nil && tCount > tracks.count {
            nextTracksPath = "/v1/catalog/\(sf)/albums/\(cleanAlbumId)/tracks?offset=\(tracks.count)&limit=100"
        }

        // Follow pagination cursors (up to 5 pages / ~500 tracks) with strict host & HTTPS verification
        var pagesFetched = 0
        while let path = nextTracksPath, pagesFetched < 5 {
            pagesFetched += 1
            guard let trksUrl = Self.resolveSafeAppleMusicPaginationURL(
                path,
                extraQueryItems: [
                    URLQueryItem(name: "limit", value: "100"),
                    URLQueryItem(name: "l", value: lang)
                ]
            ) else { break }
            var tReq = URLRequest(url: trksUrl)
            tReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            tReq.setValue("application/json", forHTTPHeaderField: "Accept")
            tReq.setValue(lang, forHTTPHeaderField: "Accept-Language")
            guard let (tData, tResp) = try? await session.data(for: tReq),
                  let tHttp = tResp as? HTTPURLResponse, tHttp.statusCode == 200,
                  let tJson = try? JSONSerialization.jsonObject(with: tData) as? [String: Any],
                  let tracksData = tJson["data"] as? [[String: Any]], !tracksData.isEmpty else {
                break
            }
            appendAlbumTrackItems(tracksData)
            nextTracksPath = tJson["next"] as? String
        }

        let catTrackCount = tCount > 0 ? tCount : tracks.count
        var inLibraryVal: Bool? = nil
        var libTrackCountVal: Int? = nil
        var isCompleteVal: Bool? = nil

        if !PlaybackRouter.shared.isTestingEnvironment {
            let localLibTracks = LibraryService.shared.getLibraryAlbumTracks(album: aName, artist: aArtist)
            let explicitlyAddedFull = isExplicitlyAddedAlbumInSession(albumId: cleanAlbumId, name: aName, artist: aArtist)
            let cloudLibMatch = getCachedUserLibraryAlbumMatch(albumId: cleanAlbumId, name: aName, artist: aArtist)
            let cloudLibCount = cloudLibMatch?.libraryTrackCount ?? cloudLibMatch?.trackCount ?? 0
            let effectiveLibCount = explicitlyAddedFull ? max(catTrackCount, localLibTracks.count) : max(localLibTracks.count, cloudLibCount)
            let inLib = effectiveLibCount > 0 || explicitlyAddedFull
            let isComplete = explicitlyAddedFull || (catTrackCount > 0 && effectiveLibCount >= catTrackCount)
            inLibraryVal = inLib
            libTrackCountVal = effectiveLibCount
            isCompleteVal = isComplete
        }

        return AlbumInfo(
            id: cleanAlbumId,
            name: aName,
            artist: aArtist,
            artwork: aArt,
            releaseDate: relDate,
            trackCount: catTrackCount,
            genre: genres,
            url: aUrl,
            tracks: tracks,
            inLibrary: inLibraryVal,
            libraryTrackCount: libTrackCountVal,
            catalogTrackCount: catTrackCount,
            catalogAlbumId: cleanAlbumId,
            isCompleteInLibrary: isCompleteVal,
            isLibraryView: false
        )
    }

    public func searchCatalogAlbumSummary(
        name: String,
        artist: String,
        storefront: String? = nil
    ) async -> (catalogAlbumId: String, catalogTrackCount: Int, artwork: String, releaseDate: String?, genre: String?, url: String?)? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, let token = getDeveloperToken() else { return nil }

        let primarySf = Self.sanitizedStorefront(storefront, fallback: getUserStorefront())
        let lang = getPreferredLanguageTag()
        let query = "\(cleanName) \(cleanArtist)".trimmingCharacters(in: .whitespacesAndNewlines)

        let storefrontsToTry = primarySf == "us" ? ["us"] : [primarySf, "us"]
        for trySf in storefrontsToTry where Self.isValidStorefrontCode(trySf) {
            guard let searchUrl = Self.makeAppleMusicAPIURL(
                path: "/v1/catalog/\(trySf)/search",
                queryItems: [
                    URLQueryItem(name: "term", value: query),
                    URLQueryItem(name: "types", value: "albums"),
                    URLQueryItem(name: "limit", value: "10"),
                    URLQueryItem(name: "l", value: lang)
                ]
            ) else {
                continue
            }
            var req = URLRequest(url: searchUrl, timeoutInterval: 3.5)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue(lang, forHTTPHeaderField: "Accept-Language")

            guard let (data, resp) = try? await session.data(for: req),
                  let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [String: Any],
                  let albumsObj = results["albums"] as? [String: Any],
                  let dataArr = albumsObj["data"] as? [[String: Any]] else {
                continue
            }

            for item in dataArr {
                guard let candId = item["id"] as? String,
                      Self.isValidResourceIdentifier(candId),
                      let attrs = item["attributes"] as? [String: Any] else { continue }
                let candName = (attrs["name"] as? String) ?? ""
                let candArtist = (attrs["artistName"] as? String) ?? ""
                if Self.albumMatches(candName, candArtist, cleanName, cleanArtist) {
                    let tCount = (attrs["trackCount"] as? Int) ?? 0
                    let relDate = attrs["releaseDate"] as? String
                    let genre = (attrs["genreNames"] as? [String])?.first
                    let aUrl = attrs["url"] as? String
                    var artUrl = ""
                    if let artObj = attrs["artwork"] as? [String: Any],
                       let tmpl = artObj["url"] as? String {
                        artUrl = tmpl
                            .replacingOccurrences(of: "{w}x{h}", with: "600x600")
                            .replacingOccurrences(of: "{w}", with: "600")
                            .replacingOccurrences(of: "{h}", with: "600")
                            .replacingOccurrences(of: "{f}", with: "jpg")
                    }
                    return (candId, tCount, artUrl, relDate, genre, aUrl)
                }
            }
        }
        return nil
    }
}
