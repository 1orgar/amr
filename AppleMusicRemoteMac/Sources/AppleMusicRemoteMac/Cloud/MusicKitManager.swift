//
//  MusicKitManager.swift
//  AppleMusicRemoteMac
//
//  Pure Swift MusicKit / Apple Music API Developer Token Manager
//  Generates and auto-refreshes ES256 JWT tokens using native CryptoKit
//

import Foundation
import CryptoKit

public final class MusicKitManager: @unchecked Sendable {
    public static let shared = MusicKitManager()

    public let keyId: String = "MJHWRCSZHH"
    public let teamId: String = "886CSW93R8"
    public let bundleId: String = "org.ksholokhov.amr"

    private let lock = NSLock()
    private var cachedToken: String?
    private var tokenExpiry: Date?
    private var privateKey: P256.Signing.PrivateKey?
    private var trackArtworkCache: [String: String] = [:]

    public struct ArtistStationInfo: Sendable {
        public let artistId: Int
        public let canonicalName: String
        public let stationUrl: String
        public let artworkUrl: String?

        public init(artistId: Int, canonicalName: String, stationUrl: String, artworkUrl: String?) {
            self.artistId = artistId
            self.canonicalName = canonicalName
            self.stationUrl = stationUrl
            self.artworkUrl = artworkUrl
        }
    }

    private var artistStationCache: [String: ArtistStationInfo] = [:]

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 15.0
        self.session = URLSession(configuration: config)

        loadPrivateKey()
    }

    // MARK: - Key Loading

    private func loadPrivateKey() {
        let possiblePaths = [
            Bundle.main.resourcePath.map { "\($0)/AuthKey_\(keyId).p8" },
            Bundle.main.bundlePath + "/Contents/Resources/AuthKey_\(keyId).p8",
            FileManager.default.currentDirectoryPath + "/AuthKey_\(keyId).p8",
            "/Users/kirill/Documents/projects/amr/AuthKey_\(keyId).p8"
        ].compactMap { $0 }

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path),
               let keyString = try? String(contentsOfFile: path, encoding: .utf8) {
                if configureKey(pemString: keyString) {
                    NSLog("[MusicKitManager] Loaded private key from: %@", path)
                    return
                }
            }
        }

        NSLog("[MusicKitManager] Warning: AuthKey_%@.p8 not found in search paths", keyId)
    }

    public func configureKey(pemString: String) -> Bool {
        let cleaned = pemString
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let derData = Data(base64Encoded: cleaned),
              let pKey = try? P256.Signing.PrivateKey(derRepresentation: derData) else {
            NSLog("[MusicKitManager] Failed to parse DER private key")
            return false
        }

        lock.lock()
        self.privateKey = pKey
        self.cachedToken = nil
        self.tokenExpiry = nil
        lock.unlock()
        return true
    }

    // MARK: - Developer Token (JWT)

    public func getDeveloperToken() -> String? {
        lock.lock()
        defer { lock.unlock() }

        if let token = cachedToken, let expiry = tokenExpiry, expiry.timeIntervalSinceNow > 3600 {
            return token
        }

        guard let pKey = privateKey else {
            NSLog("[MusicKitManager] Private key not initialized")
            return nil
        }

        let now = Int(Date().timeIntervalSince1970)
        let expirySeconds = 86400 * 30 // 30 days valid
        let exp = now + expirySeconds

        let header: [String: Any] = [
            "alg": "ES256",
            "kid": keyId
        ]
        let payload: [String: Any] = [
            "iss": teamId,
            "iat": now,
            "exp": exp
        ]

        guard let headerData = try? JSONSerialization.data(withJSONObject: header),
              let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
        }

        let signingInput = "\(base64UrlEncode(headerData)).\(base64UrlEncode(payloadData))"
        guard let signingData = signingInput.data(using: .utf8),
              let signature = try? pKey.signature(for: signingData) else {
            NSLog("[MusicKitManager] Failed to generate ES256 signature")
            return nil
        }

        let token = "\(signingInput).\(base64UrlEncode(signature.rawRepresentation))"
        self.cachedToken = token
        self.tokenExpiry = Date(timeIntervalSince1970: TimeInterval(exp))

        NSLog("[MusicKitManager] Generated new MusicKit Developer Token (valid for 30 days)")
        return token
    }

    private func base64UrlEncode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Apple Music API Requests

    public func searchAppleMusic(query: String, storefront: String = "us", limit: Int = 25, offset: Int = 0) async -> [String: Any]? {
        guard let token = getDeveloperToken() else { return nil }
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }

        let sf = storefront.lowercased()
        let offsetParam = offset > 0 ? "&offset=\(offset)" : ""
        let urlStr = "https://api.music.apple.com/v1/catalog/\(sf)/search?term=\(encodedQuery)&types=songs,albums,artists,playlists&limit=\(limit)\(offsetParam)"
        guard let url = URL(string: urlStr) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any] else {
            return nil
        }

        return parseSearchResults(results)
    }

    public func getTopCharts(storefront: String = "us", limit: Int = 20) async -> [[String: Any]] {
        let (songs, _) = await getTopChartsFull(storefront: storefront, limit: limit)
        return songs
    }

    public func getTopChartsFull(storefront: String = "ru", limit: Int = 25) async -> (songs: [[String: Any]], albums: [[String: Any]]) {
        guard let token = getDeveloperToken() else { return ([], []) }

        let sf = storefront.lowercased()
        let urlStr = "https://api.music.apple.com/v1/catalog/\(sf)/charts?types=songs,albums&limit=\(limit)"
        guard let url = URL(string: urlStr) else { return ([], []) }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

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

    public func searchPlaylistArtwork(name: String, storefront: String = "ru") async -> String? {
        guard let token = getDeveloperToken() else { return nil }
        var query = name
        if let barIdx = query.firstIndex(of: "|") {
            query = String(query[..<barIdx]).trimmingCharacters(in: .whitespaces)
        }
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }

        let sf = storefront.lowercased()
        let urlStr = "https://api.music.apple.com/v1/catalog/\(sf)/search?term=\(encodedQuery)&types=playlists&limit=3"
        guard let url = URL(string: urlStr) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let playlists = results["playlists"] as? [String: Any],
              let dataArr = playlists["data"] as? [[String: Any]] else {
            return nil
        }

        let cleanTarget = query.lowercased().trimmingCharacters(in: .whitespaces)
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

    public func getCachedTrackArtwork(name: String, artist: String, album: String = "") -> String? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanName.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if !cleanAlbum.isEmpty {
            if let cached = trackArtworkCache["\(cleanName)|\(cleanArtist)|\(cleanAlbum)"] {
                return cached.isEmpty ? nil : cached
            }
        }
        if let cached = trackArtworkCache["\(cleanName)|\(cleanArtist)"] {
            return cached.isEmpty ? nil : cached
        }
        return nil
    }


    private func getCachedArtistStation(for key: String) -> ArtistStationInfo? {
        lock.lock()
        defer { lock.unlock() }
        return artistStationCache[key.lowercased()]
    }

    private func setCachedArtistStation(_ info: ArtistStationInfo, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        artistStationCache[key.lowercased()] = info
    }

    public func extractArtistCandidates(from raw: String) -> [String] {
        var result: [String] = []
        func add(_ s: String) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count > 1 && !result.contains(t) {
                result.append(t)
            }
        }

        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = cleaned.range(of: " и другие", options: .caseInsensitive) {
            cleaned = String(cleaned[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if cleaned.lowercased().hasPrefix("при участии:") {
            cleaned = String(cleaned.dropFirst("при участии:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        add(raw)
        add(cleaned)

        if let lastAmp = cleaned.range(of: " & ", options: .backwards) {
            let beforeLast = String(cleaned[..<lastAmp.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            add(beforeLast)
        }

        var subParts = [cleaned]
        let sepList = [" & ", ", ", " feat. ", " feat ", " ft. ", " ft ", " / ", " with ", " x ", " X "]
        for sep in sepList {
            var nextParts: [String] = []
            for part in subParts {
                let chunks = part.components(separatedBy: sep)
                nextParts.append(contentsOf: chunks)
            }
            subParts = nextParts
        }

        for p in subParts {
            add(p)
        }

        if let firstAmp = cleaned.components(separatedBy: " & ").first {
            add(firstAmp)
        }

        return result
    }

    public func resolveArtistStation(artist: String) async -> ArtistStationInfo? {
        let clean = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }

        if let cached = getCachedArtistStation(for: clean) {
            return cached
        }

        let candidates = extractArtistCandidates(from: clean)

        for candidate in candidates {
            guard let enc = candidate.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { continue }
            for country in ["ru", "us", ""] {
                let countryParam = country.isEmpty ? "" : "&country=\(country)"
                let searchUrlStr = "https://itunes.apple.com/search?term=\(enc)&entity=musicArtist&limit=1\(countryParam)"
                guard let url = URL(string: searchUrlStr) else { continue }
                var req = URLRequest(url: url)
                req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

                guard let (data, _) = try? await URLSession.shared.data(for: req),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [[String: Any]],
                      let first = results.first,
                      let artistId = first["artistId"] as? Int else {
                    continue
                }

                let canonicalName = first["artistName"] as? String ?? candidate
                let stationUrl = "music://music.apple.com/station/ra.\(artistId)"

                var artworkUrl: String? = nil
                let lookupCountryParam = country.isEmpty ? "" : "&country=\(country)"
                let lookupStr = "https://itunes.apple.com/lookup?id=\(artistId)&entity=album&limit=1\(lookupCountryParam)"
                if let lookupUrl = URL(string: lookupStr) {
                    var lreq = URLRequest(url: lookupUrl)
                    lreq.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                    if let (ldata, _) = try? await URLSession.shared.data(for: lreq),
                       let ljson = try? JSONSerialization.jsonObject(with: ldata) as? [String: Any],
                       let lresults = ljson["results"] as? [[String: Any]],
                       lresults.count > 1,
                       let rawArt = lresults[1]["artworkUrl100"] as? String {
                        artworkUrl = rawArt.replacingOccurrences(of: "100x100bb", with: "600x600bb")
                    }
                }

                let info = ArtistStationInfo(
                    artistId: artistId,
                    canonicalName: canonicalName,
                    stationUrl: stationUrl,
                    artworkUrl: artworkUrl
                )

                setCachedArtistStation(info, for: clean)
                if clean.lowercased() != candidate.lowercased() {
                    setCachedArtistStation(info, for: candidate)
                }
                return info
            }
        }

        return nil
    }

    public func searchArtistStationUrl(artist: String, storefront: String = "ru") async -> String? {
        if let info = await resolveArtistStation(artist: artist) {
            return info.stationUrl
        }
        return nil
    }

    public func resolveTrackStation(title: String, artist: String = "") async -> String? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = cleanArtist.isEmpty ? cleanTitle : "\(cleanTitle) \(cleanArtist)"
        guard let enc = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }

        for country in ["ru", "us", ""] {
            let countryParam = country.isEmpty ? "" : "&country=\(country)"
            let searchUrlStr = "https://itunes.apple.com/search?term=\(enc)&entity=song&limit=1\(countryParam)"
            guard let url = URL(string: searchUrlStr) else { continue }
            var req = URLRequest(url: url)
            req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first,
                  let trackId = first["trackId"] as? Int else {
                continue
            }
            return "music://music.apple.com/station/ra.\(trackId)"
        }
        return nil
    }

    public func searchTrackArtwork(name: String, artist: String, album: String = "", storefront: String = "ru") async -> String? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }

        let cacheKey = "\(cleanName.lowercased())|\(cleanArtist.lowercased())|\(cleanAlbum.lowercased())"
        lock.lock()
        if let cached = trackArtworkCache[cacheKey] {
            lock.unlock()
            return cached.isEmpty ? nil : cached
        }
        lock.unlock()

        let simplifiedName = cleanName
            .replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\[.*?\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        
        var mainArtist = cleanArtist
        if let ampIdx = mainArtist.range(of: " & ") {
            mainArtist = String(mainArtist[..<ampIdx.lowerBound]).trimmingCharacters(in: .whitespaces)
        } else if let featIdx = mainArtist.range(of: " feat", options: .caseInsensitive) {
            mainArtist = String(mainArtist[..<featIdx.lowerBound]).trimmingCharacters(in: .whitespaces)
        }

        var queries: [String] = []
        let primaryQuery = [simplifiedName, mainArtist].filter { !$0.isEmpty }.joined(separator: " ")
        if !primaryQuery.isEmpty { queries.append(primaryQuery) }
        if !cleanAlbum.isEmpty {
            let simplifiedAlbum = cleanAlbum
                .replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s*\[.*?\]"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            let fullQuery = [simplifiedName, mainArtist, simplifiedAlbum].filter { !$0.isEmpty }.joined(separator: " ")
            if fullQuery != primaryQuery { queries.append(fullQuery) }
        }
        if !cleanName.isEmpty && cleanName != simplifiedName {
            queries.append([cleanName, mainArtist].filter { !$0.isEmpty }.joined(separator: " "))
        }

        var foundArtUrl: String? = nil

        if let token = getDeveloperToken() {
            let storefronts = [storefront.lowercased(), "us"]
            for sf in storefronts {
                if foundArtUrl != nil { break }
                for q in queries {
                    if foundArtUrl != nil { break }
                    guard let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { continue }
                    let urlStr = "https://api.music.apple.com/v1/catalog/\(sf)/search?term=\(encoded)&types=songs&limit=1"
                    guard let url = URL(string: urlStr) else { continue }
                    var request = URLRequest(url: url)
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 2.5

                    if let (data, response) = try? await session.data(for: request),
                       let http = response as? HTTPURLResponse, http.statusCode == 200,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let results = json["results"] as? [String: Any],
                       let songs = results["songs"] as? [String: Any],
                       let dataArr = songs["data"] as? [[String: Any]],
                       let first = dataArr.first,
                       let attrs = first["attributes"] as? [String: Any],
                       let artObj = attrs["artwork"] as? [String: Any],
                       let artTmpl = artObj["url"] as? String {
                        let artUrl = artTmpl
                            .replacingOccurrences(of: "{w}x{h}", with: "600x600")
                            .replacingOccurrences(of: "{w}", with: "600")
                            .replacingOccurrences(of: "{h}", with: "600")
                            .replacingOccurrences(of: "{f}", with: "jpg")
                        foundArtUrl = artUrl
                    }
                }
            }
        }

        // Fallback to iTunes Store Search API (works universally without token)
        if foundArtUrl == nil {
            for q in queries {
                if foundArtUrl != nil { break }
                guard let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { continue }
                let itunesUrlStr = "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=1"
                guard let itunesUrl = URL(string: itunesUrlStr) else { continue }
                var req = URLRequest(url: itunesUrl)
                req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
                req.timeoutInterval = 2.5

                if let (data, response) = try? await session.data(for: req),
                   let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let results = json["results"] as? [[String: Any]],
                   let first = results.first,
                   let rawArt = first["artworkUrl100"] as? String, !rawArt.isEmpty {
                    let artUrl = rawArt.replacingOccurrences(of: "100x100bb", with: "600x600bb")
                    foundArtUrl = artUrl
                }
            }
        }

        if let artUrl = foundArtUrl, !artUrl.isEmpty {
            lock.lock()
            trackArtworkCache[cacheKey] = artUrl
            trackArtworkCache["\(cleanName.lowercased())|\(cleanArtist.lowercased())"] = artUrl
            lock.unlock()
            return artUrl
        }

        lock.lock()
        trackArtworkCache[cacheKey] = ""
        lock.unlock()
        return nil
    }

    public func getAlbumTracks(album: String, artist: String, storefront: String = "ru") async -> [TrackInfo] {
        guard let token = getDeveloperToken() else { return [] }
        let cleanAlbum = album
            .replacingOccurrences(of: "(30th Anniversary Super Deluxe Edition)", with: "")
            .replacingOccurrences(of: "(30th Anniversary Edition)", with: "")
            .replacingOccurrences(of: "(Deluxe Edition)", with: "")
            .replacingOccurrences(of: "(Deluxe)", with: "")
            .replacingOccurrences(of: "[Deluxe Edition]", with: "")
            .trimmingCharacters(in: .whitespaces)
        let query = "\(cleanAlbum) \(artist)".trimmingCharacters(in: .whitespaces)
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }

        let sf = storefront.lowercased()
        let searchUrlStr = "https://api.music.apple.com/v1/catalog/\(sf)/search?term=\(encodedQuery)&types=albums&limit=1"
        guard let searchUrl = URL(string: searchUrlStr) else { return [] }

        var sReq = URLRequest(url: searchUrl)
        sReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        sReq.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (sData, sResp) = try? await session.data(for: sReq),
              let sHttp = sResp as? HTTPURLResponse, sHttp.statusCode == 200,
              let sJson = try? JSONSerialization.jsonObject(with: sData) as? [String: Any],
              let results = sJson["results"] as? [String: Any],
              let albums = results["albums"] as? [String: Any],
              let dataArr = albums["data"] as? [[String: Any]],
              let firstAlbum = dataArr.first,
              let albumId = firstAlbum["id"] as? String else {
            return []
        }

        let tracksUrlStr = "https://api.music.apple.com/v1/catalog/\(sf)/albums/\(albumId)/tracks"
        guard let tracksUrl = URL(string: tracksUrlStr) else { return [] }

        var tReq = URLRequest(url: tracksUrl)
        tReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        tReq.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (tData, tResp) = try? await session.data(for: tReq),
              let tHttp = tResp as? HTTPURLResponse, tHttp.statusCode == 200,
              let tJson = try? JSONSerialization.jsonObject(with: tData) as? [String: Any],
              let tracksData = tJson["data"] as? [[String: Any]] else {
            return []
        }

        var res = [TrackInfo]()
        for (i, item) in tracksData.enumerated() {
            guard let attrs = item["attributes"] as? [String: Any] else { continue }
            let name = attrs["name"] as? String ?? ""
            let trackArtist = attrs["artistName"] as? String ?? artist
            let durMs = attrs["durationInMillis"] as? Double ?? 0
            let trackNumber = attrs["trackNumber"] as? Int ?? (i + 1)
            let idStr = item["id"] as? String ?? "\(i + 1)"
            let numericId = Int(idStr) ?? (i + 1)
            let playUrl = attrs["url"] as? String

            var artUrl = ""
            if let artObj = attrs["artwork"] as? [String: Any],
               let tmpl = artObj["url"] as? String {
                artUrl = tmpl.replacingOccurrences(of: "{w}x{h}", with: "600x600").replacingOccurrences(of: "{f}", with: "jpg")
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
                index: trackNumber
            ))
        }

        return res
    }

    // MARK: - Album Details by ID (MusicKit Catalog)

    public func getAlbumDetailsById(albumId: String, storefront: String = "us") async -> AlbumInfo? {
        guard let token = getDeveloperToken(), !albumId.isEmpty else { return nil }
        let sf = storefront.lowercased()
        let urlStr = "https://api.music.apple.com/v1/catalog/\(sf)/albums/\(albumId)"
        guard let url = URL(string: urlStr) else { return nil }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

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
        let aUrl = attrs["url"] as? String ?? "https://music.apple.com/album/\(albumId)"
        let relDate = attrs["releaseDate"] as? String ?? ""
        let tCount = attrs["trackCount"] as? Int ?? 0
        let genres = (attrs["genreNames"] as? [String])?.first ?? ""

        var aArt = ""
        if let artObj = attrs["artwork"] as? [String: Any],
           let tmpl = artObj["url"] as? String {
            aArt = tmpl.replacingOccurrences(of: "{w}x{h}", with: "600x600").replacingOccurrences(of: "{f}", with: "jpg")
        }

        var tracks = [TrackInfo]()
        if let rels = albumObj["relationships"] as? [String: Any],
           let trksObj = rels["tracks"] as? [String: Any],
           let trksData = trksObj["data"] as? [[String: Any]] {
            for (i, item) in trksData.enumerated() {
                guard let tAttrs = item["attributes"] as? [String: Any] else { continue }
                let tName = tAttrs["name"] as? String ?? ""
                let tArtist = tAttrs["artistName"] as? String ?? aArtist
                let durMs = tAttrs["durationInMillis"] as? Double ?? 0
                let trackNumber = tAttrs["trackNumber"] as? Int ?? (i + 1)
                let idStr = item["id"] as? String ?? "\(i + 1)"
                let numericId = Int(idStr) ?? (i + 1)
                let playUrl = tAttrs["url"] as? String

                var tArt = aArt
                if let artObj = tAttrs["artwork"] as? [String: Any],
                   let tmpl = artObj["url"] as? String {
                    tArt = tmpl.replacingOccurrences(of: "{w}x{h}", with: "600x600").replacingOccurrences(of: "{f}", with: "jpg")
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
                    index: trackNumber
                ))
            }
        }

        // If tracks relationship was not returned inline, fetch /tracks subresource
        if tracks.isEmpty {
            let trksUrlStr = "https://api.music.apple.com/v1/catalog/\(sf)/albums/\(albumId)/tracks"
            if let trksUrl = URL(string: trksUrlStr) {
                var tReq = URLRequest(url: trksUrl)
                tReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                tReq.setValue("application/json", forHTTPHeaderField: "Accept")
                if let (tData, tResp) = try? await session.data(for: tReq),
                   let tHttp = tResp as? HTTPURLResponse, tHttp.statusCode == 200,
                   let tJson = try? JSONSerialization.jsonObject(with: tData) as? [String: Any],
                   let tracksData = tJson["data"] as? [[String: Any]] {
                    for (i, item) in tracksData.enumerated() {
                        guard let tAttrs = item["attributes"] as? [String: Any] else { continue }
                        let tName = tAttrs["name"] as? String ?? ""
                        let tArtist = tAttrs["artistName"] as? String ?? aArtist
                        let durMs = tAttrs["durationInMillis"] as? Double ?? 0
                        let trackNumber = tAttrs["trackNumber"] as? Int ?? (i + 1)
                        let idStr = item["id"] as? String ?? "\(i + 1)"
                        let numericId = Int(idStr) ?? (i + 1)
                        let playUrl = tAttrs["url"] as? String

                        var tArt = aArt
                        if let artObj = tAttrs["artwork"] as? [String: Any],
                           let tmpl = artObj["url"] as? String {
                            tArt = tmpl.replacingOccurrences(of: "{w}x{h}", with: "600x600").replacingOccurrences(of: "{f}", with: "jpg")
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
                            index: trackNumber
                        ))
                    }
                }
            }
        }

        return AlbumInfo(
            id: albumId,
            name: aName,
            artist: aArtist,
            artwork: aArt,
            releaseDate: relDate,
            trackCount: tCount > 0 ? tCount : tracks.count,
            genre: genres,
            url: aUrl,
            tracks: tracks
        )
    }

    // MARK: - Parsers

    private func parseSearchResults(_ results: [String: Any]) -> [String: Any] {
        var songs = [[String: Any]]()
        var albums = [[String: Any]]()
        var artists = [[String: Any]]()

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

        return [
            "songs": songs,
            "albums": albums,
            "artists": artists
        ]
    }

    private func parseCatalogSong(_ item: [String: Any]) -> [String: Any]? {
        let id = item["id"] as? String ?? ""
        guard !id.isEmpty, let attrs = item["attributes"] as? [String: Any] else { return nil }

        let name = attrs["name"] as? String ?? ""
        let artist = attrs["artistName"] as? String ?? ""
        let album = attrs["albumName"] as? String ?? ""
        let durMs = attrs["durationInMillis"] as? Double ?? 0.0
        let isrc = attrs["isrc"] as? String ?? ""
        let url = attrs["url"] as? String ?? ""

        var artworkUrl = ""
        if let artObj = attrs["artwork"] as? [String: Any],
           let artTemplate = artObj["url"] as? String {
            artworkUrl = artTemplate
                .replacingOccurrences(of: "{w}", with: "600")
                .replacingOccurrences(of: "{h}", with: "600")
                .replacingOccurrences(of: "{f}", with: "jpg")
        }

        var previewUrl = ""
        if let previews = attrs["previews"] as? [[String: Any]],
           let firstPrev = previews.first?["url"] as? String {
            previewUrl = firstPrev
        }

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
            "is_local": false
        ]
    }

    private func parseCatalogAlbum(_ item: [String: Any]) -> [String: Any]? {
        let id = item["id"] as? String ?? ""
        guard !id.isEmpty, let attrs = item["attributes"] as? [String: Any] else { return nil }

        let name = attrs["name"] as? String ?? ""
        let artist = attrs["artistName"] as? String ?? ""
        let relDate = attrs["releaseDate"] as? String ?? ""
        let trackCount = attrs["trackCount"] as? Int ?? 0
        let url = attrs["url"] as? String ?? ""

        var artworkUrl = ""
        if let artObj = attrs["artwork"] as? [String: Any],
           let artTemplate = artObj["url"] as? String {
            artworkUrl = artTemplate
                .replacingOccurrences(of: "{w}", with: "600")
                .replacingOccurrences(of: "{h}", with: "600")
                .replacingOccurrences(of: "{f}", with: "jpg")
        }

        return [
            "type": "album",
            "id": id,
            "name": name,
            "artist": artist,
            "artwork": artworkUrl,
            "release_date": relDate,
            "track_count": trackCount,
            "url": url
        ]
    }

    private func parseCatalogArtist(_ item: [String: Any]) -> [String: Any]? {
        let id = item["id"] as? String ?? ""
        guard !id.isEmpty, let attrs = item["attributes"] as? [String: Any] else { return nil }

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
}
