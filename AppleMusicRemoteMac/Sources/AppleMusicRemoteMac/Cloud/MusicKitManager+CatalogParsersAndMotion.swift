//
//  MusicKitManager+CatalogParsersAndMotion.swift
//  AppleMusicRemoteMac
//
//  Apple Music Catalog JSON parsers and editorial animated motion artwork resolution.
//

import Foundation

extension MusicKitManager {

    // MARK: - Catalog JSON Parsers

    internal func parseSearchResults(_ results: [String: Any]) -> [String: Any] {
        var songs = [[String: Any]]()
        var albums = [[String: Any]]()
        var artists = [[String: Any]]()
        var playlists = [[String: Any]]()

        if let songsObj = results["songs"] as? [String: Any],
           let songsData = songsObj["data"] as? [[String: Any]] {
            for item in songsData {
                if let s = parseCatalogSong(item) { songs.append(s) }
            }
        }

        if let albumsObj = results["albums"] as? [String: Any],
           let albumsData = albumsObj["data"] as? [[String: Any]] {
            for item in albumsData {
                if let a = parseCatalogAlbum(item) { albums.append(a) }
            }
        }

        if let artistsObj = results["artists"] as? [String: Any],
           let artistsData = artistsObj["data"] as? [[String: Any]] {
            for item in artistsData {
                if let art = parseCatalogArtist(item) { artists.append(art) }
            }
        }

        if let playlistsObj = results["playlists"] as? [String: Any],
           let playlistsData = playlistsObj["data"] as? [[String: Any]] {
            for item in playlistsData {
                if let pl = parseCatalogPlaylist(item) { playlists.append(pl) }
            }
        }

        return [
            "songs": songs,
            "albums": albums,
            "artists": artists,
            "playlists": playlists
        ]
    }

    internal func parseCatalogSong(_ item: [String: Any]) -> [String: Any]? {
        let id = item["id"] as? String ?? ""
        guard Self.isValidResourceIdentifier(id), let attrs = item["attributes"] as? [String: Any] else { return nil }

        let name = attrs["name"] as? String ?? ""
        let artist = attrs["artistName"] as? String ?? ""
        let album = attrs["albumName"] as? String ?? ""
        let durMs = attrs["durationInMillis"] as? Double ?? 0.0
        let isrc = attrs["isrc"] as? String ?? ""
        let url = attrs["url"] as? String ?? ""
        cacheTrackCatalogId(id, name: name, artist: artist, album: album)

        var artworkUrl = ""
        if let artObj = attrs["artwork"] as? [String: Any],
           let artTemplate = artObj["url"] as? String {
            artworkUrl = Self.formatArtworkUrl(artTemplate, width: 600, height: 600) ?? ""
        }
        if !artworkUrl.isEmpty {
            cacheTrackArtworkUrl(artworkUrl, name: name, artist: artist, album: album)
        }

        var previewUrl = ""
        if let previews = attrs["previews"] as? [[String: Any]],
           let firstPrev = previews.first?["url"] as? String {
            previewUrl = firstPrev
        }

        let audioVariants = (attrs["audioVariants"] as? [String]) ?? []
        let isHiRes = audioVariants.contains("hi-res-lossless")
        let isLossless = isHiRes || audioVariants.contains("lossless")
        let isADM = (attrs["isMasteredForItunes"] as? Bool == true) || (attrs["isAppleDigitalMaster"] as? Bool == true)

        return [
            "type": "song",
            "id": id,
            "numeric_id": Int(id) ?? 0,
            "name": name,
            "artist": artist,
            "album": album,
            "duration": durMs / 1000.0,
            "artwork": artworkUrl,
            "artwork_url": artworkUrl,
            "url": url,
            "preview_url": previewUrl,
            "isrc": isrc,
            "is_local": false,
            "audio_variants": audioVariants,
            "is_hi_res": isHiRes,
            "is_lossless": isLossless,
            "is_apple_digital_master": isADM
        ]
    }

    internal func parseCatalogAlbum(_ item: [String: Any]) -> [String: Any]? {
        let id = item["id"] as? String ?? ""
        guard Self.isValidResourceIdentifier(id), let attrs = item["attributes"] as? [String: Any] else { return nil }

        let name = attrs["name"] as? String ?? ""
        let artist = attrs["artistName"] as? String ?? ""
        let relDate = attrs["releaseDate"] as? String ?? ""
        let trackCount = attrs["trackCount"] as? Int ?? 0
        let url = attrs["url"] as? String ?? ""
        let audioVariants = (attrs["audioVariants"] as? [String]) ?? []
        let isHiRes = audioVariants.contains("hi-res-lossless")
        let isLossless = isHiRes || audioVariants.contains("lossless")
        let isADM = (attrs["isMasteredForItunes"] as? Bool == true) || (attrs["isAppleDigitalMaster"] as? Bool == true)

        var artworkUrl = ""
        if let artObj = attrs["artwork"] as? [String: Any],
           let artTemplate = artObj["url"] as? String {
            artworkUrl = Self.formatArtworkUrl(artTemplate, width: 600, height: 600) ?? ""
        }
        if !artworkUrl.isEmpty {
            registerAlbumArtwork(album: name, artist: artist, url: artworkUrl)
        }

        return [
            "type": "album",
            "id": id,
            "name": name,
            "artist": artist,
            "artwork": artworkUrl,
            "release_date": relDate,
            "track_count": trackCount,
            "url": url,
            "audio_variants": audioVariants,
            "is_hi_res": isHiRes,
            "is_lossless": isLossless,
            "is_apple_digital_master": isADM
        ]
    }

    internal func parseCatalogArtist(_ item: [String: Any]) -> [String: Any]? {
        let id = item["id"] as? String ?? ""
        guard Self.isValidResourceIdentifier(id), let attrs = item["attributes"] as? [String: Any] else { return nil }

        let name = attrs["name"] as? String ?? ""
        let url = attrs["url"] as? String ?? ""
        let genres = (attrs["genreNames"] as? [String])?.joined(separator: ", ") ?? ""

        return [
            "type": "artist",
            "id": id,
            "name": name,
            "genre": genres,
            "url": url
        ]
    }

    internal func parseCatalogPlaylist(_ item: [String: Any]) -> [String: Any]? {
        let id = item["id"] as? String ?? ""
        guard Self.isValidResourceIdentifier(id), let attrs = item["attributes"] as? [String: Any] else { return nil }

        let name = attrs["name"] as? String ?? ""
        let curator = attrs["curatorName"] as? String ?? "Apple Music"
        let desc = (attrs["description"] as? [String: Any])?["short"] as? String
            ?? (attrs["description"] as? [String: Any])?["standard"] as? String
            ?? curator
        let url = attrs["url"] as? String ?? "https://music.apple.com/playlist/\(id)"

        var artworkUrl = ""
        if let artObj = attrs["artwork"] as? [String: Any],
           let artTemplate = artObj["url"] as? String {
            artworkUrl = artTemplate
                .replacingOccurrences(of: "{w}x{h}", with: "600x600")
                .replacingOccurrences(of: "{w}", with: "600")
                .replacingOccurrences(of: "{h}", with: "600")
                .replacingOccurrences(of: "{f}", with: "jpg")
                .replacingOccurrences(of: "{c}", with: "bb")
        }

        return [
            "type": "playlist",
            "id": id,
            "name": name,
            "curator": curator,
            "curator_name": curator,
            "subtitle": curator,
            "description": desc,
            "artwork": artworkUrl,
            "artwork_url": artworkUrl,
            "url": url,
            "is_playlist": true,
            "is_local": false
        ]
    }

    // MARK: - Apple Music Motion Artwork (Animated Cover Video)

    internal static let mvodRegex = try? NSRegularExpression(
        pattern: "https://mvod\\.itunes\\.apple\\.com/itunes-assets/[^\"'\\s<>\\\\]+_default\\.m3u8",
        options: []
    )
    internal static let avcVariantRegex = try? NSRegularExpression(
        pattern: "([^\\s\"'<>]*_Anull_video_[^\\s\"'<>]*sdr_(?:1080x1080|768x768)[^\\s\"'<>]*\\.m3u8)",
        options: []
    )

    public func resolveMotionArtworkUrl(albumId: String? = nil, trackName: String, artist: String, albumName: String) async -> String? {
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAlbum = albumName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTrack = trackName.trimmingCharacters(in: .whitespacesAndNewlines)
        var targetAlbumId = albumId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !Self.isValidResourceIdentifier(targetAlbumId) {
            targetAlbumId = ""
        } else if let num = Int(targetAlbumId), num < 10_000_000 {
            targetAlbumId = ""
        }

        let idKey = !targetAlbumId.isEmpty ? "id|\(targetAlbumId)" : ""
        let albumKey = !cleanAlbum.isEmpty ? "album|\(cleanArtist.lowercased())|\(cleanAlbum.lowercased())" : ""
        let artistTrackKey = (!cleanArtist.isEmpty && !cleanTrack.isEmpty) ? "at|\(cleanArtist.lowercased())|\(cleanTrack.lowercased())" : ""
        let trackKey = "track|\(targetAlbumId)|\(cleanArtist.lowercased())|\(cleanAlbum.lowercased())|\(cleanTrack.lowercased())"

        if let cachedRemoteUrl = MotionArtworkDiskCache.shared.lookupUrl(keys: [idKey, albumKey, artistTrackKey, trackKey]) {
            if cachedRemoteUrl.isEmpty {
                return nil
            }
            if let localPath = MotionArtworkDiskCache.shared.localEndpointIfCached(for: cachedRemoteUrl) {
                return localPath
            }
            MotionArtworkDiskCache.shared.cacheVideoInBackground(remoteUrl: cachedRemoteUrl)
            return cachedRemoteUrl
        }

        let singleFlightKey = !albumKey.isEmpty ? albumKey : (!idKey.isEmpty ? idKey : (!artistTrackKey.isEmpty ? artistTrackKey : trackKey))
        if let existingTask = withLock({ inFlightMotionArtworkTasks[singleFlightKey] }) {
            return await existingTask.value
        }

        let task = Task<String?, Never> {
            await self.performResolveMotionArtworkUrl(
                initialAlbumId: targetAlbumId,
                cleanTrack: cleanTrack,
                cleanArtist: cleanArtist,
                cleanAlbum: cleanAlbum,
                idKey: idKey,
                albumKey: albumKey,
                artistTrackKey: artistTrackKey,
                trackKey: trackKey
            )
        }
        let taskToAwait: Task<String?, Never> = withLock {
            if let raced = inFlightMotionArtworkTasks[singleFlightKey] {
                task.cancel()
                return raced
            }
            inFlightMotionArtworkTasks[singleFlightKey] = task
            return task
        }
        let resolved = await taskToAwait.value
        withLock {
            if inFlightMotionArtworkTasks[singleFlightKey] == taskToAwait {
                inFlightMotionArtworkTasks.removeValue(forKey: singleFlightKey)
            }
        }
        return resolved
    }

    private func performResolveMotionArtworkUrl(
        initialAlbumId: String,
        cleanTrack: String,
        cleanArtist: String,
        cleanAlbum: String,
        idKey: String,
        albumKey: String,
        artistTrackKey: String,
        trackKey: String
    ) async -> String? {
        var targetAlbumId = Self.isValidResourceIdentifier(initialAlbumId) ? initialAlbumId : ""
        let sf = Self.sanitizedStorefront(getUserStorefront())

        // 1. Resolve catalog album ID if not provided
        if targetAlbumId.isEmpty, let devToken = getDeveloperToken() {
            let lang = getPreferredLanguageTag()
            let searchTerm = (!cleanAlbum.isEmpty ? "\(cleanAlbum) \(cleanArtist)" : "\(cleanTrack) \(cleanArtist)")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !searchTerm.isEmpty,
               let searchUrl = Self.makeAppleMusicAPIURL(
                   path: "/v1/catalog/\(sf)/search",
                   queryItems: [
                       URLQueryItem(name: "term", value: searchTerm),
                       URLQueryItem(name: "types", value: "albums,songs"),
                       URLQueryItem(name: "limit", value: "3"),
                       URLQueryItem(name: "l", value: lang)
                   ]
               ) {
                var req = URLRequest(url: searchUrl)
                req.timeoutInterval = 3.5
                req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                req.setValue(lang, forHTTPHeaderField: "Accept-Language")
                if let (data, resp) = try? await session.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let results = json["results"] as? [String: Any] {
                    if let albumsObj = results["albums"] as? [String: Any],
                       let albumsData = albumsObj["data"] as? [[String: Any]],
                       let firstAlbumId = albumsData.first?["id"] as? String,
                       Self.isValidResourceIdentifier(firstAlbumId) {
                        targetAlbumId = firstAlbumId
                    } else if let songsObj = results["songs"] as? [String: Any],
                              let songsData = songsObj["data"] as? [[String: Any]],
                              let firstSong = songsData.first,
                              let sUrl = (firstSong["attributes"] as? [String: Any])?["url"] as? String {
                        let cleanPath = sUrl.components(separatedBy: "?").first ?? sUrl
                        if let lastSeg = cleanPath.split(separator: "/").last, Int(lastSeg) != nil {
                            targetAlbumId = String(lastSeg)
                        }
                    }
                }
            }
        }

        guard Self.isValidResourceIdentifier(targetAlbumId) else {
            MotionArtworkDiskCache.shared.storeUrl("", forKeys: [idKey, albumKey, artistTrackKey, trackKey])
            return nil
        }

        let resolvedIdKey = "id|\(targetAlbumId)"
        if let cachedById = MotionArtworkDiskCache.shared.lookupUrl(keys: [resolvedIdKey]) {
            MotionArtworkDiskCache.shared.storeUrl(cachedById, forKeys: [idKey, albumKey, artistTrackKey, trackKey])
            if cachedById.isEmpty {
                return nil
            }
            if let localPath = MotionArtworkDiskCache.shared.localEndpointIfCached(for: cachedById) {
                return localPath
            }
            MotionArtworkDiskCache.shared.cacheVideoInBackground(remoteUrl: cachedById)
            return cachedById
        }

        // 2. Fetch Apple Music album page to extract editorial motion cover master .m3u8
        let storefrontsToTry = sf == "us" ? ["us"] : [sf, "us"]
        var masterM3u8Url: String? = nil

        for trySf in storefrontsToTry where Self.isValidStorefrontCode(trySf) {
            var pComps = URLComponents()
            pComps.scheme = "https"
            pComps.host = "music.apple.com"
            pComps.path = "/\(trySf)/album/_/\(targetAlbumId)"
            guard let pageUrl = pComps.url else { continue }
            var req = URLRequest(url: pageUrl)
            req.timeoutInterval = 4.0
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            if let (data, resp) = try? await session.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let html = String(data: data, encoding: .utf8),
               let regex = Self.mvodRegex {
                let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
                if let match = regex.firstMatch(in: html, options: [], range: nsRange),
                   let matchRange = Range(match.range, in: html) {
                    masterM3u8Url = String(html[matchRange])
                    break
                }
            }
        }

        guard let masterUrlStr = masterM3u8Url,
              let masterUrl = URL(string: masterUrlStr),
              masterUrl.scheme?.lowercased() == "https",
              masterUrl.host?.lowercased() == "mvod.itunes.apple.com" else {
            MotionArtworkDiskCache.shared.storeUrl("", forKeys: [idKey, resolvedIdKey, albumKey, artistTrackKey, trackKey])
            return nil
        }

        // 3. Resolve direct 1080x1080 / 768x768 H.264 (avc1) .mp4 from master .m3u8 so all browsers play it natively
        var finalVideoUrl = masterUrlStr
        var mReq = URLRequest(url: masterUrl)
        mReq.timeoutInterval = 3.0
        if let (mData, mResp) = try? await session.data(for: mReq),
           let mHttp = mResp as? HTTPURLResponse, mHttp.statusCode == 200,
           let mText = String(data: mData, encoding: .utf8),
           let vRegex = Self.avcVariantRegex {
            let nsRange = NSRange(mText.startIndex..<mText.endIndex, in: mText)
            let matches = vRegex.matches(in: mText, options: [], range: nsRange)
            var chosenVariant: String? = nil
            for m in matches {
                if let r = Range(m.range, in: mText) {
                    let s = String(mText[r])
                    if s.contains("768x768") {
                        chosenVariant = s
                        break
                    } else if chosenVariant == nil {
                        chosenVariant = s
                    }
                }
            }
            if let variant = chosenVariant {
                let mp4Variant = variant.replacingOccurrences(of: ".m3u8", with: "-.mp4")
                if mp4Variant.hasPrefix("https://") {
                    if let candidateUrl = URL(string: mp4Variant), ArtworkService.isAllowedRemoteArtworkURL(candidateUrl) {
                        finalVideoUrl = mp4Variant
                    }
                } else if !mp4Variant.contains("://") && !mp4Variant.contains("..") {
                    let baseDir = masterUrl.deletingLastPathComponent().absoluteString
                    finalVideoUrl = baseDir.hasSuffix("/") ? "\(baseDir)\(mp4Variant)" : "\(baseDir)/\(mp4Variant)"
                }
            }
        }

        MotionArtworkDiskCache.shared.storeUrl(finalVideoUrl, forKeys: [idKey, resolvedIdKey, albumKey, artistTrackKey, trackKey])
        if let localPath = MotionArtworkDiskCache.shared.localEndpointIfCached(for: finalVideoUrl) {
            return localPath
        }
        MotionArtworkDiskCache.shared.cacheVideoInBackground(remoteUrl: finalVideoUrl)
        return finalVideoUrl
    }

    internal func parseCatalogTrackItems(_ items: [[String: Any]]) -> [TrackInfo] {
        var res = [TrackInfo]()
        for (i, item) in items.enumerated() {
            guard let attrs = item["attributes"] as? [String: Any] else { continue }
            let name = attrs["name"] as? String ?? ""
            let trackArtist = attrs["artistName"] as? String ?? ""
            let albumName = attrs["albumName"] as? String ?? ""
            let durMs = attrs["durationInMillis"] as? Double ?? 0
            let trackNumber = res.count + 1
            let rawItemId = (item["id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let playParams = attrs["playParams"] as? [String: Any]
            let catalogIdFromParams = (playParams?["catalogId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? (playParams?["id"] as? String).flatMap { s in
                    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    return Int(trimmed) != nil ? trimmed : nil
                }
            let playUrl = attrs["url"] as? String
            let catalogIdFromUrl: String? = playUrl.flatMap { u in
                guard let comp = URLComponents(string: u),
                      let qi = comp.queryItems?.first(where: { $0.name == "i" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                      Int(qi) != nil else { return nil }
                return qi
            }
            let resolvedCatalogId: String? = {
                if let c = catalogIdFromParams, !c.isEmpty, Int(c) != nil { return c }
                if let c = catalogIdFromUrl, !c.isEmpty, Int(c) != nil { return c }
                if !rawItemId.isEmpty, Int(rawItemId) != nil { return rawItemId }
                return nil
            }()
            let idStr = resolvedCatalogId ?? (!rawItemId.isEmpty ? rawItemId : "\(i + 1)")
            let numericId = resolvedCatalogId.flatMap { Int($0) }

            var artUrl = ""
            if let artObj = attrs["artwork"] as? [String: Any],
               let tmpl = artObj["url"] as? String {
                artUrl = Self.formatArtworkUrl(tmpl, width: 600, height: 600) ?? ""
            }
            if !artUrl.isEmpty {
                cacheTrackArtworkUrl(artUrl, name: name, artist: trackArtist, album: albumName)
            }
            if let validCid = resolvedCatalogId {
                cacheTrackCatalogId(validCid, name: name, artist: trackArtist, album: albumName)
            }

            res.append(TrackInfo(
                id: idStr,
                numericId: numericId,
                name: name,
                artist: trackArtist,
                album: albumName,
                duration: durMs / 1000.0,
                hasArtwork: !artUrl.isEmpty,
                artworkUrl: artUrl,
                favorited: false,
                isLocal: false,
                url: playUrl,
                index: trackNumber,
                catalogId: resolvedCatalogId
            ))
        }
        return res
    }
}
