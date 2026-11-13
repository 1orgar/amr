//
//  MusicKitManager.swift
//  AppleMusicRemoteMac
//
//  Pure Swift MusicKit / Apple Music API Developer Token Manager
//  Generates and auto-refreshes ES256 JWT tokens using native CryptoKit
//

import Foundation
import CryptoKit
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

    internal static let keychainService = "org.ksholokhov.amr.musickit"

    public var isTestingProcess: Bool {
        NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static let cachedHasTeamSignature: Bool = {
        var selfCode: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &selfCode) == errSecSuccess, let code = selfCode else {
            return false
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let sCode = staticCode else {
            return false
        }
        var infoRef: CFDictionary?
        let flagsArg = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(sCode, flagsArg, &infoRef) == errSecSuccess,
              let info = infoRef as? [String: Any] else {
            return false
        }
        let sigFlags = (info[kSecCodeInfoFlags as String] as? UInt32) ?? 0
        let adhocMask = UInt32(SecCodeSignatureFlags.adhoc.rawValue)
        if (sigFlags & adhocMask) != 0 {
            return false
        }
        guard let teamId = info[kSecCodeInfoTeamIdentifier as String] as? String,
              !teamId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return true
    }()

    internal static func hasTeamCodeSignature() -> Bool {
        return cachedHasTeamSignature
    }

    internal func readKeychainString(account: String) -> String? {
        guard !isTestingProcess else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip as String
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8),
              !str.isEmpty else {
            return nil
        }
        return str
    }

    @discardableResult
    internal func writeKeychainString(_ value: String, account: String) -> Bool {
        guard !isTestingProcess, let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    internal func deleteKeychainItem(account: String) {
        guard !isTestingProcess else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
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
        var savedToken = readKeychainString(account: "AppleMusicUserToken")
        var legacyToken: String? = defs.string(forKey: "AppleMusicUserToken")
        if legacyToken == nil || legacyToken!.isEmpty {
            for suite in ["org.ksholokhov.amr.mac", "AppleMusicRemoteMac", "org.ksholokhov.AppleMusicRemoteMac"] {
                if let t = UserDefaults(suiteName: suite)?.string(forKey: "AppleMusicUserToken"), !t.isEmpty {
                    legacyToken = t
                    break
                }
            }
        }
        if legacyToken == nil || legacyToken!.isEmpty {
            legacyToken = UserDefaults.standard.string(forKey: "AppleMusicUserToken")
        }
        var keychainSaved = (savedToken != nil && !savedToken!.isEmpty)
        if !keychainSaved, let leg = legacyToken, !leg.isEmpty {
            savedToken = leg
            if !isTestingProcess {
                keychainSaved = writeKeychainString(leg, account: "AppleMusicUserToken")
            }
        }
        let hasTeamSig = Self.hasTeamCodeSignature()
        if !isTestingProcess && keychainSaved && hasTeamSig && legacyToken != nil {
            defs.removeObject(forKey: "AppleMusicUserToken")
            UserDefaults.standard.removeObject(forKey: "AppleMusicUserToken")
            for suite in ["org.ksholokhov.amr.mac", "AppleMusicRemoteMac", "org.ksholokhov.AppleMusicRemoteMac"] {
                UserDefaults(suiteName: suite)?.removeObject(forKey: "AppleMusicUserToken")
            }
        } else if !hasTeamSig, let tok = savedToken, !tok.isEmpty, (legacyToken == nil || legacyToken!.isEmpty) {
            defs.set(tok, forKey: "AppleMusicUserToken")
            UserDefaults.standard.set(tok, forKey: "AppleMusicUserToken")
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
        let env = ProcessInfo.processInfo.environment

        // 1. Check environment variables (inline PEM or custom key file path)
        if let envPem = env["AMR_MUSICKIT_PRIVATE_KEY"], !envPem.isEmpty,
           configureKey(pemString: envPem) {
            NSLog("[MusicKitManager] Loaded MusicKit private key from AMR_MUSICKIT_PRIVATE_KEY")
            return
        }

        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AppleMusicRemoteMac", isDirectory: true)
        let appSupportKeyPath = appSupportDir?.appendingPathComponent("AuthKey_\(keyId).p8").path
        let cwd = FileManager.default.currentDirectoryPath
        let parentDirKeyPath = URL(fileURLWithPath: cwd)
            .deletingLastPathComponent()
            .appendingPathComponent("AuthKey_\(keyId).p8")
            .path

        let rawPaths: [String?] = [
            env["AMR_MUSICKIT_KEY_PATH"],
            appSupportKeyPath,
            "\(cwd)/AuthKey_\(keyId).p8",
            parentDirKeyPath
        ]
        let possiblePaths = rawPaths.compactMap { $0 }.filter { !$0.isEmpty }

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path),
               let keyString = try? String(contentsOfFile: path, encoding: .utf8),
               configureKey(pemString: keyString) {
                NSLog("[MusicKitManager] Loaded MusicKit private key from disk (%@)", (path as NSString).lastPathComponent)
                return
            }
        }

        // Fallback: check pre-signed public Developer JWT token (env, Bundle Resources, Application Support, cwd)
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
        let appSupportJwt = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AppleMusicRemoteMac/musickit_dev_token.jwt").path
        let cwd = FileManager.default.currentDirectoryPath
        let parentJwt = URL(fileURLWithPath: cwd).deletingLastPathComponent().appendingPathComponent("musickit_dev_token.jwt").path

        var candidates: [(source: String, rawJwt: String)] = []
        if let envJwt = env["AMR_MUSICKIT_DEV_TOKEN"], !envJwt.isEmpty {
            candidates.append(("AMR_MUSICKIT_DEV_TOKEN", envJwt))
        }

        let jwtPaths: [String?] = [
            Bundle.main.resourcePath.map { "\($0)/musickit_dev_token.jwt" },
            Bundle.main.bundlePath + "/Contents/Resources/musickit_dev_token.jwt",
            appSupportJwt,
            "\(cwd)/musickit_dev_token.jwt",
            parentJwt
        ]

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
