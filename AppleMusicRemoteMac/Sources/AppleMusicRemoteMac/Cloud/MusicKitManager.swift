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
    private var userToken: String?

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

    public struct TrackStationInfo: Sendable {
        public let trackId: String
        public let title: String
        public let artist: String
        public let stationUrl: String
        public let artworkUrl: String?

        public init(trackId: String, title: String, artist: String, stationUrl: String, artworkUrl: String? = nil) {
            self.trackId = trackId
            self.title = title
            self.artist = artist
            self.stationUrl = stationUrl
            self.artworkUrl = artworkUrl
        }
    }

    private var artistStationCache: [String: ArtistStationInfo] = [:]
    private var trackStationCache: [String: TrackStationInfo] = [:]

    private let session: URLSession

    private static var storageDefaults: UserDefaults {
        UserDefaults(suiteName: "org.ksholokhov.AppleMusicRemoteMac") ?? UserDefaults.standard
    }

    public private(set) var userStorefront: String = (UserDefaults(suiteName: "org.ksholokhov.AppleMusicRemoteMac") ?? UserDefaults.standard).string(forKey: "AppleMusicUserStorefront") ?? UserDefaults.standard.string(forKey: "AppleMusicUserStorefront") ?? "us"

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 15.0
        self.session = URLSession(configuration: config)

        let defs = Self.storageDefaults
        self.userToken = defs.string(forKey: "AppleMusicUserToken") ?? UserDefaults.standard.string(forKey: "AppleMusicUserToken")
        self.userStorefront = defs.string(forKey: "AppleMusicUserStorefront") ?? UserDefaults.standard.string(forKey: "AppleMusicUserStorefront") ?? "us"
        loadPrivateKey()
        if self.userToken != nil && !self.userToken!.isEmpty {
            Task.detached(priority: .utility) { [weak self] in
                _ = await self?.fetchUserStorefront()
            }
        }
    }

    // MARK: - User Token & Cloud Library Playlists

    public var hasUserToken: Bool {
        lock.lock()
        defer { lock.unlock() }
        return userToken != nil && !userToken!.isEmpty
    }

    public func getUserToken() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return userToken
    }

    public func getUserStorefront() -> String {
        lock.lock()
        defer { lock.unlock() }
        return userStorefront
    }

    public func fetchUserStorefront() async -> String {
        guard let devToken = getDeveloperToken(), let uToken = getUserToken(), !uToken.isEmpty else {
            return self.getUserStorefront()
        }
        guard let url = URL(string: "https://api.music.apple.com/v1/me/storefront") else { return self.getUserStorefront() }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")
        do {
            let (data, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let arr = json["data"] as? [[String: Any]],
               let first = arr.first,
               let sfId = first["id"] as? String, !sfId.isEmpty {
                let lower = sfId.lowercased()
                lock.lock()
                self.userStorefront = lower
                Self.storageDefaults.set(lower, forKey: "AppleMusicUserStorefront")
                UserDefaults.standard.set(lower, forKey: "AppleMusicUserStorefront")
                lock.unlock()
                NSLog("[MusicKitManager] 🌍 Detected active Apple ID storefront: '%@'", lower)
                return lower
            }
        } catch {
            NSLog("[MusicKitManager] Error fetching user storefront: %@", error.localizedDescription)
        }
        return self.getUserStorefront()
    }

    public func setUserToken(_ token: String) {
        lock.lock()
        self.userToken = token
        Self.storageDefaults.set(token, forKey: "AppleMusicUserToken")
        UserDefaults.standard.set(token, forKey: "AppleMusicUserToken")
        lock.unlock()
        NSLog("[MusicKitManager] ✅ Saved Apple Music User Token (len: %d)", token.count)
        Task.detached(priority: .userInitiated) { [weak self] in
            _ = await self?.fetchUserStorefront()
        }
    }

    public func clearUserToken() {
        lock.lock()
        self.userToken = nil
        Self.storageDefaults.removeObject(forKey: "AppleMusicUserToken")
        UserDefaults.standard.removeObject(forKey: "AppleMusicUserToken")
        lock.unlock()
        NSLog("[MusicKitManager] Cleared Apple Music User Token")
    }

    public func createTemporaryCloudPlaylist(name: String = "Очередь AMR", trackCatalogIds: [String]) async -> String? {
        guard let devToken = getDeveloperToken(), let uToken = getUserToken(), !uToken.isEmpty else {
            NSLog("[MusicKitManager] Cannot create iCloud playlist: missing developer or user token")
            return nil
        }
        guard let url = URL(string: "https://api.music.apple.com/v1/me/library/playlists") else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "attributes": [
                "name": name,
                "description": "Временный плейлист AMR для результатов поиска"
            ]
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        req.httpBody = body

        var createdPlaylistId: String?
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return nil }
            if http.statusCode == 200 || http.statusCode == 201 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let arr = json["data"] as? [[String: Any]],
                   let first = arr.first,
                   let plId = first["id"] as? String {
                    createdPlaylistId = plId
                    NSLog("[MusicKitManager] ✅ Created temporary iCloud playlist: '%@'", plId)
                }
            } else {
                let errStr = String(data: data, encoding: .utf8) ?? ""
                NSLog("[MusicKitManager] ❌ Failed to create iCloud playlist (status %d): %@", http.statusCode, errStr)
                return nil
            }
        } catch {
            NSLog("[MusicKitManager] ❌ Error creating temporary iCloud playlist: %@", error.localizedDescription)
            return nil
        }

        guard let plId = createdPlaylistId, !trackCatalogIds.isEmpty else {
            return createdPlaylistId
        }

        // Step 2: Add tracks in batch via POST /v1/me/library/playlists/{id}/tracks
        guard let addUrl = URL(string: "https://api.music.apple.com/v1/me/library/playlists/\(plId)/tracks") else {
            return plId
        }
        var addReq = URLRequest(url: addUrl)
        addReq.httpMethod = "POST"
        addReq.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        addReq.setValue(uToken, forHTTPHeaderField: "Music-User-Token")
        addReq.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let trackData = trackCatalogIds.map { ["id": $0, "type": "songs"] }
        let addPayload: [String: Any] = ["data": trackData]
        guard let addBody = try? JSONSerialization.data(withJSONObject: addPayload) else { return plId }
        addReq.httpBody = addBody

        do {
            let (addData, addResp) = try await session.data(for: addReq)
            if let addHttp = addResp as? HTTPURLResponse, (addHttp.statusCode == 200 || addHttp.statusCode == 201 || addHttp.statusCode == 204) {
                NSLog("[MusicKitManager] ✅ Successfully populated %d tracks into iCloud playlist '%@'", trackCatalogIds.count, plId)
            } else {
                let addErr = String(data: addData, encoding: .utf8) ?? ""
                NSLog("[MusicKitManager] ⚠️ Warning adding tracks to playlist (status %d): %@", (addResp as? HTTPURLResponse)?.statusCode ?? 0, addErr)
            }
        } catch {
            NSLog("[MusicKitManager] ⚠️ Error adding tracks to playlist: %@", error.localizedDescription)
        }

        return plId
    }

    public func deleteTemporaryCloudPlaylist(playlistId: String) async -> Bool {
        guard let devToken = getDeveloperToken(), let uToken = getUserToken(), !uToken.isEmpty else { return false }
        guard let url = URL(string: "https://api.music.apple.com/v1/me/library/playlists/\(playlistId)") else { return false }

        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")

        do {
            let (_, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 204) {
                NSLog("[MusicKitManager] 🗑 Deleted temporary iCloud playlist: '%@'", playlistId)
                return true
            }
        } catch {
            NSLog("[MusicKitManager] Error deleting iCloud playlist: %@", error.localizedDescription)
        }
        return false
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

    /// Injects an in-memory private key for unit testing (e.g. CI environments without AuthKey.p8)
    public func setPrivateKeyForTesting(_ key: P256.Signing.PrivateKey) {
        lock.lock()
        self.privateKey = key
        self.cachedToken = nil
        self.tokenExpiry = nil
        lock.unlock()
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


    public func getCachedArtistStation(for key: String) -> ArtistStationInfo? {
        lock.lock()
        defer { lock.unlock() }
        return artistStationCache[key.lowercased()]
    }

    public func setCachedArtistStation(_ info: ArtistStationInfo, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        artistStationCache[key.lowercased()] = info
    }

    public func getCachedTrackStation(for key: String) -> TrackStationInfo? {
        lock.lock()
        defer { lock.unlock() }
        return trackStationCache[key.lowercased()]
    }

    public func setCachedTrackStation(_ info: TrackStationInfo, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        trackStationCache[key.lowercased()] = info
    }

    // MARK: - Station Fuzzy Matching Helpers

    public static func normalizeQueryText(_ str: String) -> String {
        let lower = str.lowercased()
        let withoutParens = lower
            .replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\[.*?\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: ##"[!"#$%&'()*+,-./:;<=>?@\[\\\]^_`{|}~]"##, with: " ", options: .regularExpression)
        return withoutParens.split(separator: " ").joined(separator: " ")
    }

    public static func computeSongSimilarity(
        queryTitle: String,
        queryArtist: String,
        candidateTitle: String,
        candidateArtist: String
    ) -> (score: Double, isMatch: Bool) {
        let normQT = normalizeQueryText(queryTitle)
        let normQA = normalizeQueryText(queryArtist)
        let normCT = normalizeQueryText(candidateTitle)
        let normCA = normalizeQueryText(candidateArtist)

        var titleScore = 0.0
        if normQT == normCT {
            titleScore = 1.0
        } else if normCT.contains(normQT) || normQT.contains(normCT) {
            titleScore = 0.85
        } else {
            let qWords = Set(normQT.split(separator: " "))
            let cWords = Set(normCT.split(separator: " "))
            let common = qWords.intersection(cWords)
            if !qWords.isEmpty {
                titleScore = Double(common.count) / Double(qWords.count)
            }
        }

        var artistScore = 0.0
        if normQA.isEmpty {
            artistScore = 1.0
        } else if normQA == normCA {
            artistScore = 1.0
        } else if normCA.contains(normQA) || normQA.contains(normCA) {
            artistScore = 0.85
        } else {
            let qWords = Set(normQA.split(separator: " "))
            let cWords = Set(normCA.split(separator: " "))
            let common = qWords.intersection(cWords)
            if !qWords.isEmpty {
                artistScore = Double(common.count) / Double(qWords.count)
            }
        }

        let total = (titleScore * 0.65) + (artistScore * 0.35)
        let isMatch = titleScore >= 0.5 && (normQA.isEmpty || artistScore >= 0.3)
        return (total, isMatch)
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

    public func resolveArtistStation(artist: String, storefront: String = "ru") async -> ArtistStationInfo? {
        let clean = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }

        if let cached = getCachedArtistStation(for: clean) {
            return cached
        }

        let candidates = extractArtistCandidates(from: clean)
        let sfOrder = [storefront.lowercased(), "us", "jp"].filter { !$0.isEmpty }
        var uniqueSfs: [String] = []
        for s in sfOrder {
            if !uniqueSfs.contains(s) { uniqueSfs.append(s) }
        }

        // 1. Try Apple Music Catalog API with developer token
        if let token = getDeveloperToken() {
            for sf in uniqueSfs {
                for candidate in candidates {
                    guard let enc = candidate.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { continue }
                    let urlStr = "https://api.music.apple.com/v1/catalog/\(sf)/search?term=\(enc)&types=artists&limit=5"
                    guard let url = URL(string: urlStr) else { continue }
                    var req = URLRequest(url: url)
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    req.setValue("application/json", forHTTPHeaderField: "Accept")
                    req.timeoutInterval = 3.0

                    guard let (data, resp) = try? await session.data(for: req),
                          let http = resp as? HTTPURLResponse, http.statusCode == 200,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let results = json["results"] as? [String: Any],
                          let artists = results["artists"] as? [String: Any],
                          let dataArr = artists["data"] as? [[String: Any]] else {
                        continue
                    }

                    for item in dataArr {
                        guard let idStr = item["id"] as? String,
                              let artistId = Int(idStr),
                              let attrs = item["attributes"] as? [String: Any],
                              let aName = attrs["name"] as? String else { continue }

                        let normCand = Self.normalizeQueryText(candidate)
                        let normName = Self.normalizeQueryText(aName)
                        let isMatch = normCand == normName || normName.contains(normCand) || normCand.contains(normName)
                        if isMatch {
                            let canonicalName = aName
                            let stationUrl = "https://music.apple.com/\(sf)/station/item/ra.\(artistId)"
                            var artworkUrl: String? = nil
                            if let artObj = attrs["artwork"] as? [String: Any],
                               let artTmpl = artObj["url"] as? String {
                                artworkUrl = artTmpl
                                    .replacingOccurrences(of: "{w}x{h}", with: "600x600")
                                    .replacingOccurrences(of: "{w}", with: "600")
                                    .replacingOccurrences(of: "{h}", with: "600")
                                    .replacingOccurrences(of: "{f}", with: "jpg")
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
                }
            }
        }

        // 2. Fallback to iTunes Store Search API
        for candidate in candidates {
            guard let enc = candidate.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { continue }
            for country in uniqueSfs {
                let countryParam = country.isEmpty ? "" : "&country=\(country)"
                let searchUrlStr = "https://itunes.apple.com/search?term=\(enc)&entity=musicArtist&limit=5\(countryParam)"
                guard let url = URL(string: searchUrlStr) else { continue }
                var req = URLRequest(url: url)
                req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                req.timeoutInterval = 3.0

                guard let (data, resp) = try? await session.data(for: req),
                      let http = resp as? HTTPURLResponse, http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [[String: Any]] else {
                    continue
                }

                for item in results {
                    guard let artistId = item["artistId"] as? Int,
                          let aName = item["artistName"] as? String else { continue }

                    let normCand = Self.normalizeQueryText(candidate)
                    let normName = Self.normalizeQueryText(aName)
                    let isMatch = normCand == normName || normName.contains(normCand) || normCand.contains(normName)
                    guard isMatch else { continue }

                    let canonicalName = aName
                    let cCode = country.isEmpty ? "ru" : country
                    let stationUrl = "https://music.apple.com/\(cCode)/station/item/ra.\(artistId)"

                    var artworkUrl: String? = nil
                    let lookupCountryParam = country.isEmpty ? "" : "&country=\(country)"
                    let lookupStr = "https://itunes.apple.com/lookup?id=\(artistId)&entity=album&limit=1\(lookupCountryParam)"
                    if let lookupUrl = URL(string: lookupStr) {
                        var lreq = URLRequest(url: lookupUrl)
                        lreq.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                        if let (ldata, _) = try? await session.data(for: lreq),
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
        }

        return nil
    }

    public func searchArtistStationUrl(artist: String, storefront: String = "ru") async -> String? {
        if let info = await resolveArtistStation(artist: artist, storefront: storefront) {
            return info.stationUrl
        }
        return nil
    }

    public func resolveTrackStation(title: String, artist: String = "", storefront: String = "ru") async -> String? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = "\(cleanTitle.lowercased())|\(cleanArtist.lowercased())"
        if let cached = getCachedTrackStation(for: cacheKey) {
            return cached.stationUrl
        }

        let normT = Self.normalizeQueryText(cleanTitle)
        let normA = Self.normalizeQueryText(cleanArtist)
        var queries: [String] = []
        if !cleanArtist.isEmpty {
            queries.append("\(cleanTitle) \(cleanArtist)")
            if !normT.isEmpty && !normA.isEmpty && (normT != cleanTitle.lowercased() || normA != cleanArtist.lowercased()) {
                queries.append("\(normT) \(normA)")
            }
        }
        if !normT.isEmpty && normT != cleanTitle.lowercased() {
            queries.append(normT)
        }
        queries.append(cleanTitle)

        let sfOrder = [storefront.lowercased(), "us", "jp"].filter { !$0.isEmpty }
        var uniqueSfs: [String] = []
        for s in sfOrder {
            if !uniqueSfs.contains(s) { uniqueSfs.append(s) }
        }

        // 1. Search via Apple Music Catalog API with developer token
        if let token = getDeveloperToken() {
            var bestCandidate: (songId: String, title: String, artist: String, sf: String, score: Double)? = nil
            for sf in uniqueSfs {
                if let b = bestCandidate, b.score >= 0.85 { break }
                for q in queries {
                    if let b = bestCandidate, b.score >= 0.85 { break }
                    guard let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { continue }
                    let urlStr = "https://api.music.apple.com/v1/catalog/\(sf)/search?term=\(encoded)&types=songs&limit=10"
                    guard let url = URL(string: urlStr) else { continue }
                    var req = URLRequest(url: url)
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    req.setValue("application/json", forHTTPHeaderField: "Accept")
                    req.timeoutInterval = 3.0

                    guard let (data, resp) = try? await session.data(for: req),
                          let http = resp as? HTTPURLResponse, http.statusCode == 200,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let results = json["results"] as? [String: Any],
                          let songs = results["songs"] as? [String: Any],
                          let dataArr = songs["data"] as? [[String: Any]] else {
                        continue
                    }

                    for item in dataArr {
                        guard let id = item["id"] as? String,
                              let attrs = item["attributes"] as? [String: Any],
                              let cName = attrs["name"] as? String,
                              let cArtist = attrs["artistName"] as? String else { continue }

                        let (score, isMatch) = Self.computeSongSimilarity(
                            queryTitle: cleanTitle,
                            queryArtist: cleanArtist,
                            candidateTitle: cName,
                            candidateArtist: cArtist
                        )
                        if isMatch {
                            if bestCandidate == nil || score > bestCandidate!.score {
                                bestCandidate = (id, cName, cArtist, sf, score)
                            }
                        }
                    }
                }
            }

            if let best = bestCandidate {
                var stationUrl: String? = nil
                let stationReqStr = "https://api.music.apple.com/v1/catalog/\(best.sf)/songs/\(best.songId)/station"
                if let stUrl = URL(string: stationReqStr) {
                    var sreq = URLRequest(url: stUrl)
                    sreq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    sreq.setValue("application/json", forHTTPHeaderField: "Accept")
                    sreq.timeoutInterval = 3.0
                    if let (sdata, sresp) = try? await session.data(for: sreq),
                       let shttp = sresp as? HTTPURLResponse, shttp.statusCode == 200,
                       let sjson = try? JSONSerialization.jsonObject(with: sdata) as? [String: Any],
                       let sArr = sjson["data"] as? [[String: Any]],
                       let sFirst = sArr.first,
                       let sAttrs = sFirst["attributes"] as? [String: Any],
                       let officialUrl = sAttrs["url"] as? String, !officialUrl.isEmpty {
                        stationUrl = officialUrl
                    }
                }

                if stationUrl == nil {
                    stationUrl = "https://music.apple.com/\(best.sf)/station/item/ra.\(best.songId)"
                }

                if let finalUrl = stationUrl {
                    let info = TrackStationInfo(
                        trackId: best.songId,
                        title: best.title,
                        artist: best.artist,
                        stationUrl: finalUrl
                    )
                    setCachedTrackStation(info, for: cacheKey)
                    return finalUrl
                }
            }
        }

        // 2. Fallback to iTunes Store Search API
        for country in uniqueSfs {
            for q in queries {
                guard let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { continue }
                let searchUrlStr = "https://itunes.apple.com/search?term=\(enc)&entity=song&limit=10&country=\(country)"
                guard let url = URL(string: searchUrlStr) else { continue }
                var req = URLRequest(url: url)
                req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                req.timeoutInterval = 3.0

                guard let (data, resp) = try? await session.data(for: req),
                      let http = resp as? HTTPURLResponse, http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [[String: Any]] else {
                    continue
                }

                var bestItunes: (trackId: Int, name: String, artist: String, score: Double)? = nil
                for r in results {
                    guard let tid = r["trackId"] as? Int,
                          let tName = r["trackName"] as? String,
                          let tArtist = r["artistName"] as? String else { continue }
                    let (score, isMatch) = Self.computeSongSimilarity(
                        queryTitle: cleanTitle,
                        queryArtist: cleanArtist,
                        candidateTitle: tName,
                        candidateArtist: tArtist
                    )
                    if isMatch {
                        if bestItunes == nil || score > bestItunes!.score {
                            bestItunes = (tid, tName, tArtist, score)
                        }
                    }
                }

                if let b = bestItunes {
                    let cCode = country.isEmpty ? "ru" : country
                    let finalUrl = "https://music.apple.com/\(cCode)/station/item/ra.\(b.trackId)"
                    let info = TrackStationInfo(
                        trackId: "\(b.trackId)",
                        title: b.name,
                        artist: b.artist,
                        stationUrl: finalUrl
                    )
                    setCachedTrackStation(info, for: cacheKey)
                    return finalUrl
                }
            }
        }

        return nil
    }

    public func searchTrackArtwork(name: String, artist: String, album: String = "", storefront: String = "ru") async -> String? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }

        let cacheKey = "\(cleanName.lowercased())|\(cleanArtist.lowercased())|\(cleanAlbum.lowercased())"
        let cached = lock.withLock { () -> String? in
            if let entry = trackArtworkCache[cacheKey] {
                return entry.isEmpty ? nil : entry
            }
            return nil
        }
        if let cached = cached {
            return cached
        }

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
            lock.withLock {
                trackArtworkCache[cacheKey] = artUrl
                trackArtworkCache["\(cleanName.lowercased())|\(cleanArtist.lowercased())"] = artUrl
            }
            return artUrl
        }

        lock.withLock {
            trackArtworkCache[cacheKey] = ""
        }
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
