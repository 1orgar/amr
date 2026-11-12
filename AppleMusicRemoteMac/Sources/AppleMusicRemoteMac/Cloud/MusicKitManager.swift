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
    var trackCatalogIdCache: [String: String] = [:]
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

    var artistStationCache: [String: ArtistStationInfo] = [:]
    var trackStationCache: [String: TrackStationInfo] = [:]
    var lastTemporaryCloudPlaylistId: String? = nil

    let session: URLSession

    static var storageDefaults: UserDefaults {
        let bundleId = Bundle.main.bundleIdentifier ?? "org.ksholokhov.amr.mac"
        return UserDefaults(suiteName: bundleId) ?? UserDefaults.standard
    }

    public internal(set) var userStorefront: String = "us"
    public internal(set) var supportedLanguageTags: [String] = []
    public internal(set) var defaultLanguageTag: String = ""

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 15.0
        self.session = URLSession(configuration: config)

        let defs = Self.storageDefaults
        var savedToken = defs.string(forKey: "AppleMusicUserToken")
        if savedToken == nil || savedToken!.isEmpty {
            for suite in ["org.ksholokhov.amr.mac", "AppleMusicRemoteMac", "org.ksholokhov.AppleMusicRemoteMac"] {
                if let t = UserDefaults(suiteName: suite)?.string(forKey: "AppleMusicUserToken"), !t.isEmpty {
                    savedToken = t
                    break
                }
            }
        }
        if savedToken == nil || savedToken!.isEmpty {
            savedToken = UserDefaults.standard.string(forKey: "AppleMusicUserToken")
        }
        self.userToken = (savedToken?.isEmpty == false) ? savedToken : nil

        var savedSf = defs.string(forKey: "AppleMusicUserStorefront")
        if savedSf == nil || savedSf!.isEmpty {
            for suite in ["org.ksholokhov.amr.mac", "AppleMusicRemoteMac", "org.ksholokhov.AppleMusicRemoteMac"] {
                if let sf = UserDefaults(suiteName: suite)?.string(forKey: "AppleMusicUserStorefront"), !sf.isEmpty {
                    savedSf = sf
                    break
                }
            }
        }
        self.userStorefront = (savedSf?.isEmpty == false) ? savedSf! : "us"

        if let savedLangs = defs.stringArray(forKey: "AppleMusicSupportedLanguageTags"), !savedLangs.isEmpty {
            self.supportedLanguageTags = savedLangs
        } else if let stdLangs = UserDefaults.standard.stringArray(forKey: "AppleMusicSupportedLanguageTags"), !stdLangs.isEmpty {
            self.supportedLanguageTags = stdLangs
        }
        self.defaultLanguageTag = defs.string(forKey: "AppleMusicDefaultLanguageTag")
            ?? UserDefaults.standard.string(forKey: "AppleMusicDefaultLanguageTag")
            ?? ""

        loadPrivateKey()
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
}
