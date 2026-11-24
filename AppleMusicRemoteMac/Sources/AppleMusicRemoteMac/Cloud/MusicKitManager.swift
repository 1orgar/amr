//
//  MusicKitManager.swift
//  AppleMusicRemoteMac
//
//  Pure Swift MusicKit / Apple Music API Developer Token Manager
//  Generates and auto-refreshes ES256 JWT tokens using native CryptoKit
//

import CryptoKit
import Foundation
import Security

public extension String {
    var amrQueryValueEncoded: String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=;?/:#")
        return self.addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

public final class MusicKitManager: @unchecked Sendable {
    public static let shared = MusicKitManager()

    public let keyId: String = "MJHWRCSZHH"
    public let teamId: String = "886CSW93R8"
    public let bundleId: String = "org.ksholokhov.amr"

    internal static let maxArtworkCacheEntries = 2000
    internal static let maxStationCacheEntries = 1000
    internal static let maxPlaylistTracksCacheEntries = 200
    internal static let legacySuites = ["org.ksholokhov.amr.mac", "AppleMusicRemoteMac", "org.ksholokhov.AppleMusicRemoteMac"]

    let lock = NSLock()

    func withLock<T>(_ block: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block()
    }

    var cachedToken: String?
    var tokenExpiry: Date?
    var privateKey: P256.Signing.PrivateKey?
    var trackArtworkCache: [String: String] = [:]
    var trackArtworkNegativeCache: [String: Date] = [:]
    var albumArtworkCacheByNormTitle: [String: [(album: String, artist: String, url: String)]] = [:]
    var trackCatalogIdCache: [String: String] = [:]
    var inFlightTrackArtworkTasks: [String: Task<String?, Never>] = [:]
    var inFlightUserLibraryAlbumsTask: Task<[AlbumInfo], Never>? = nil
    var inFlightMotionArtworkTasks: [String: Task<String?, Never>] = [:]
    var userToken: String?

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

    public static let stagingPlaylistName = "Буфер AMR"
    internal static let stagingCloudPlaylistIdsKey = "AMRStagingCloudPlaylistIds"
    internal static let reusableStagingCloudPlaylistIdKey = "AMRReusableStagingCloudPlaylistId"

    var artistStationCache: [String: ArtistStationInfo] = [:]
    var trackStationCache: [String: TrackStationInfo] = [:]
    var lastTemporaryCloudPlaylistId: String? = nil
    var activeStagingCloudPlaylistId: String? = nil
    var activeStagingCloudPlaylistTrackCount: Int = 0
    var personalStationEndpointUnavailable: Bool = false
    var recentlyAddedLibraryAlbums: [(addedAt: Date, album: AlbumInfo)] = []
    var userLibraryAlbumsCache: (timestamp: Date, albums: [AlbumInfo])? = nil

    let session: URLSession

    static var storageDefaults: UserDefaults {
        if Bundle.main.bundleIdentifier != nil {
            return UserDefaults.standard
        }
        return UserDefaults(suiteName: "org.ksholokhov.amr.mac") ?? UserDefaults.standard
    }

    /// Safely opens a legacy UserDefaults suite without triggering macOS `_NSUserDefaults_Log_Nonsensical_Suites`
    /// when `suite` matches the running app's own `CFBundleIdentifier` (already covered by `UserDefaults.standard`).
    static func legacySuiteDefaults(_ suite: String) -> UserDefaults? {
        if let bundleId = Bundle.main.bundleIdentifier, bundleId == suite {
            return nil
        }
        return UserDefaults(suiteName: suite)
    }

    internal static let keychainService = "org.ksholokhov.amr.musickit"

    public var isTestingProcess: Bool {
        NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    // MARK: - Safe Identifier, Storefront & Pagination URL Validation

    public static func isValidStorefrontCode(_ raw: String) -> Bool {
        return raw.range(of: #"^[a-zA-Z]{2,5}$"#, options: .regularExpression) != nil
    }

    public static func sanitizedStorefront(_ raw: String?, fallback: String = "us") -> String {
        let clean = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if isValidStorefrontCode(clean) {
            return clean
        }
        let cleanFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return isValidStorefrontCode(cleanFallback) ? cleanFallback : "us"
    }

    public static func isValidResourceIdentifier(_ raw: String) -> Bool {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 128 else { return false }
        return clean.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    }

    public static func isTrustedAppleMusicAPIURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "api.music.apple.com",
              url.user == nil,
              url.password == nil,
              (url.port == nil || url.port == 443),
              url.path.hasPrefix("/v1/"),
              !url.path.contains("..") else {
            return false
        }
        return true
    }

    public static func makeAppleMusicAPIURL(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        guard path.hasPrefix("/v1/"), !path.contains(".."), !path.contains("//") else {
            return nil
        }
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "api.music.apple.com"
        comps.path = path
        if !queryItems.isEmpty {
            comps.queryItems = queryItems
        }
        guard let url = comps.url, isTrustedAppleMusicAPIURL(url) else {
            return nil
        }
        return url
    }

    public static func resolveSafeAppleMusicPaginationURL(
        _ nextPath: String,
        extraQueryItems: [URLQueryItem] = []
    ) -> URL? {
        let trimmed = nextPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(".."), !trimmed.hasPrefix("//") else {
            return nil
        }
        var comps: URLComponents?
        if trimmed.lowercased().hasPrefix("https://") {
            comps = URLComponents(string: trimmed)
        } else if trimmed.hasPrefix("/v1/") {
            comps = URLComponents(string: "https://api.music.apple.com" + trimmed)
        } else {
            return nil
        }
        guard var validComps = comps else { return nil }
        if !extraQueryItems.isEmpty {
            var items = validComps.queryItems ?? []
            for extra in extraQueryItems where !items.contains(where: { $0.name == extra.name }) {
                items.append(extra)
            }
            validComps.queryItems = items
        }
        guard let url = validComps.url, isTrustedAppleMusicAPIURL(url) else {
            return nil
        }
        return url
    }

    public internal(set) var userStorefront: String = ""
    public internal(set) var supportedLanguageTags: [String] = []
    public internal(set) var defaultLanguageTag: String = ""

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 15.0
        self.session = URLSession(configuration: config)

        let defs = Self.storageDefaults
        self.userToken = loadAndMigrateInitialUserToken(defs: defs)

        var savedSf = defs.string(forKey: "AppleMusicUserStorefront")
        if savedSf == nil || savedSf!.isEmpty {
            for suite in Self.legacySuites {
                if let sf = Self.legacySuiteDefaults(suite)?.string(forKey: "AppleMusicUserStorefront"), !sf.isEmpty {
                    savedSf = sf
                    break
                }
            }
        }
        if savedSf == nil || savedSf!.isEmpty {
            savedSf = UserDefaults.standard.string(forKey: "AppleMusicUserStorefront")
        }
        if (savedSf == nil || savedSf!.isEmpty) && !isTestingProcess {
            savedSf = AccountHealthService.shared.getMacAccountInfo().countryCode
        }
        if savedSf == nil || savedSf!.isEmpty {
            savedSf = Locale.current.region?.identifier.lowercased()
        }
        let trimmedSf = (savedSf ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.userStorefront = Self.isValidStorefrontCode(trimmedSf) ? trimmedSf : ""

        if let savedLangs = defs.stringArray(forKey: "AppleMusicSupportedLanguageTags"), !savedLangs.isEmpty {
            self.supportedLanguageTags = savedLangs
        } else if let stdLangs = UserDefaults.standard.stringArray(forKey: "AppleMusicSupportedLanguageTags"), !stdLangs.isEmpty {
            self.supportedLanguageTags = stdLangs
        }
        self.defaultLanguageTag = defs.string(forKey: "AppleMusicDefaultLanguageTag")
            ?? UserDefaults.standard.string(forKey: "AppleMusicDefaultLanguageTag")
            ?? ""

        loadPrivateKey()
        if !isTestingProcess {
            let persisted = ArtworkUrlDiskCache.shared.snapshot()
            var boundedTracks: [String: String] = [:]
            for (k, v) in persisted.tracks where boundedTracks.count < Self.maxArtworkCacheEntries {
                boundedTracks[k] = v
            }
            self.trackArtworkCache = boundedTracks
            var hydratedAlbums: [String: [(album: String, artist: String, url: String)]] = [:]
            hydratedAlbums.reserveCapacity(min(persisted.albums.count, Self.maxArtworkCacheEntries))
            for (normTitle, records) in persisted.albums where hydratedAlbums.count < Self.maxArtworkCacheEntries {
                hydratedAlbums[normTitle] = Array(records.suffix(8)).map { ($0.album, $0.artist, $0.url) }
            }
            self.albumArtworkCacheByNormTitle = hydratedAlbums
        }
        if self.userToken != nil && !self.userToken!.isEmpty {
            Task.detached(priority: .utility) { [weak self] in
                _ = await self?.fetchUserStorefront()
            }
        }
    }

    public struct PersonalDataCache: Sendable {
        public var timestamp: Date
        public var personalStation: StationInfo?
        public var discoveryStation: StationInfo?
        public var mixes: [PlaylistInfo]
        public var recommendations: [PersonalRecommendationGroup]

        public init(
            timestamp: Date = Date(),
            personalStation: StationInfo? = nil,
            discoveryStation: StationInfo? = nil,
            mixes: [PlaylistInfo] = [],
            recommendations: [PersonalRecommendationGroup] = []
        ) {
            self.timestamp = timestamp
            self.personalStation = personalStation
            self.discoveryStation = discoveryStation
            self.mixes = mixes
            self.recommendations = recommendations
        }
    }

    var personalDataCache: PersonalDataCache?
    var playlistTracksCache: [String: (timestamp: Date, tracks: [TrackInfo])] = [:]
    let personalCacheTTL: TimeInterval = 3600 // 1 hour

    public func invalidatePersonalCache() {
        lock.lock()
        self.personalDataCache = nil
        self.playlistTracksCache.removeAll()
        lock.unlock()
        CloudCatalogService.shared.invalidateExploreFeedCache()
        NSLog("[MusicKitManager] 🔄 Invalidated personal data cache")
    }

    public func getCachedPersonalData() -> PersonalDataCache? {
        lock.lock()
        defer { lock.unlock() }
        guard let c = personalDataCache, Date().timeIntervalSince(c.timestamp) < personalCacheTTL else {
            return nil
        }
        return c
    }

    // MARK: - Key Loading

    private var allowWorkspaceKeyProbing: Bool {
        #if DEBUG
        return true
        #else
        return isTestingProcess || PlaybackRouter.shared.isTestingEnvironment
        #endif
    }

    private func loadPrivateKey() {
        let env = ProcessInfo.processInfo.environment
        let allowDevProbe = allowWorkspaceKeyProbing

        // 1. In DEBUG or XCTest, allow inline PEM environment override
        if allowDevProbe,
           let envPem = env["AMR_MUSICKIT_PRIVATE_KEY"], !envPem.isEmpty,
           configureKey(pemString: envPem) {
            NSLog("[MusicKitManager] Loaded MusicKit private key from AMR_MUSICKIT_PRIVATE_KEY")
            return
        }

        let bundleResourceKeyPath = Bundle.main.path(forResource: "AuthKey_\(keyId)", ofType: "p8")
            ?? Bundle.main.resourcePath.map { "\($0)/AuthKey_\(keyId).p8" }
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AppleMusicRemoteMac", isDirectory: true)
        let appSupportKeyPath = appSupportDir?.appendingPathComponent("AuthKey_\(keyId).p8").path

        var rawPaths: [String?] = [
            bundleResourceKeyPath,
            appSupportKeyPath
        ]
        if allowDevProbe {
            let cwd = FileManager.default.currentDirectoryPath
            let parentDirKeyPath = URL(fileURLWithPath: cwd)
                .deletingLastPathComponent()
                .appendingPathComponent("AuthKey_\(keyId).p8")
                .path
            rawPaths.insert(env["AMR_MUSICKIT_KEY_PATH"], at: 0)
            rawPaths.append("\(cwd)/AuthKey_\(keyId).p8")
            rawPaths.append(parentDirKeyPath)
        }

        let possiblePaths = rawPaths.compactMap { $0 }.filter { !$0.isEmpty }
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path),
               let keyString = try? String(contentsOfFile: path, encoding: .utf8),
               configureKey(pemString: keyString) {
                NSLog("[MusicKitManager] Loaded MusicKit private key from disk (%@)", (path as NSString).lastPathComponent)
                return
            }
        }

        // Fallback: check pre-signed public Developer JWT token (Bundle Resources / Application Support; cwd only in DEBUG/tests)
        if loadFallbackDeveloperToken() {
            return
        }

        NSLog("[MusicKitManager] Warning: AuthKey_%@.p8 and pre-signed developer token not found", keyId)
    }

    internal static func parseDeveloperTokenExpiry(_ rawToken: String) -> (token: String, exp: TimeInterval)? {
        let trimmed = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payloadB64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = payloadB64.count % 4
        if rem > 0 {
            payloadB64 += String(repeating: "=", count: 4 - rem)
        }
        guard let payloadData = Data(base64Encoded: payloadB64),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return nil
        }
        let expVal: TimeInterval?
        if let num = json["exp"] as? NSNumber {
            expVal = num.doubleValue
        } else if let d = json["exp"] as? Double {
            expVal = d
        } else if let i = json["exp"] as? Int {
            expVal = TimeInterval(i)
        } else {
            expVal = nil
        }
        guard let exp = expVal, exp > Date().timeIntervalSince1970 + 3600 else {
            return nil
        }
        return (trimmed, exp)
    }

    @discardableResult
    internal func loadFallbackDeveloperToken() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return loadFallbackDeveloperTokenLocked()
    }

    @discardableResult
    private func loadFallbackDeveloperTokenLocked() -> Bool {
        let env = ProcessInfo.processInfo.environment
        let allowDevProbe = allowWorkspaceKeyProbing
        let appSupportJwt = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AppleMusicRemoteMac/musickit_dev_token.jwt").path

        var candidates: [(source: String, rawJwt: String)] = []
        if allowDevProbe, let envJwt = env["AMR_MUSICKIT_DEV_TOKEN"], !envJwt.isEmpty {
            candidates.append(("AMR_MUSICKIT_DEV_TOKEN", envJwt))
        }

        var jwtPaths: [String?] = [
            Bundle.main.resourcePath.map { "\($0)/musickit_dev_token.jwt" },
            Bundle.main.bundlePath + "/Contents/Resources/musickit_dev_token.jwt",
            appSupportJwt
        ]
        if allowDevProbe {
            let cwd = FileManager.default.currentDirectoryPath
            let parentJwt = URL(fileURLWithPath: cwd).deletingLastPathComponent().appendingPathComponent("musickit_dev_token.jwt").path
            jwtPaths.append("\(cwd)/musickit_dev_token.jwt")
            jwtPaths.append(parentJwt)
        }

        var seenPaths = Set<String>()
        for path in jwtPaths.compactMap({ $0 }) {
            let stdPath = URL(fileURLWithPath: path).standardizedFileURL.path
            guard !seenPaths.contains(stdPath) else { continue }
            seenPaths.insert(stdPath)
            if FileManager.default.fileExists(atPath: stdPath),
               let jwtStr = try? String(contentsOfFile: stdPath, encoding: .utf8) {
                candidates.append(((stdPath as NSString).lastPathComponent, jwtStr))
            }
        }

        var bestMatch: (source: String, token: String, exp: TimeInterval)?
        for cand in candidates {
            if let parsed = Self.parseDeveloperTokenExpiry(cand.rawJwt) {
                if bestMatch == nil || parsed.exp > bestMatch!.exp {
                    bestMatch = (cand.source, parsed.token, parsed.exp)
                }
            }
        }

        if let best = bestMatch {
            self.cachedToken = best.token
            self.tokenExpiry = Date(timeIntervalSince1970: best.exp)
            NSLog("[MusicKitManager] Loaded pre-signed MusicKit Developer JWT from %@", best.source)
            return true
        }
        return false
    }

    @discardableResult
    public func configurePreSignedDeveloperToken(_ rawToken: String) -> Bool {
        guard let parsed = Self.parseDeveloperTokenExpiry(rawToken) else {
            return false
        }
        lock.lock()
        self.cachedToken = parsed.token
        self.tokenExpiry = Date(timeIntervalSince1970: parsed.exp)
        lock.unlock()
        return true
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

    /// Resets any test-injected private key and reloads the real key or fallback developer token
    internal func reloadKeyForTesting() {
        lock.lock()
        self.privateKey = nil
        self.cachedToken = nil
        self.tokenExpiry = nil
        lock.unlock()
        loadPrivateKey()
    }

    // MARK: - Developer Token (JWT)

    public func getDeveloperToken() -> String? {
        lock.lock()
        defer { lock.unlock() }

        if let token = cachedToken, let expiry = tokenExpiry, expiry.timeIntervalSinceNow > 3600 {
            return token
        }

        if privateKey == nil {
            if loadFallbackDeveloperTokenLocked(),
               let token = cachedToken,
               let expiry = tokenExpiry,
               expiry.timeIntervalSinceNow > 3600 {
                return token
            }
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
}
