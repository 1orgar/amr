//
//  MusicKitManager+Auth.swift
//  AppleMusicRemoteMac
//
//  Keychain & AES-GCM encrypted fallback storage for AppleMusicUserToken,
//  code-signature team detection, and account storefront/locale resolution.
//

import CryptoKit
import Darwin
import Foundation
import Security

extension MusicKitManager {

    internal static let encryptedUserTokenPrefix = "enc:v1:"
    private static let tokenKeyLock = NSLock()
    private static var cachedFallbackSymmetricKey: SymmetricKey?

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

    // MARK: - Local AES-256-GCM Encrypted Token Storage (Zero Keychain Prompts)

    internal func readKeychainString(account: String) -> String? {
        return nil
    }

    @discardableResult
    internal func writeKeychainString(_ value: String, account: String) -> Bool {
        return false
    }

    internal func deleteKeychainItem(account: String) {
        // Intentionally does not touch macOS File-Based Keychain to avoid securityd password dialogs.
    }

    internal static func loadOrCreateFallbackTokenKey() -> SymmetricKey {
        tokenKeyLock.lock()
        defer { tokenKeyLock.unlock() }

        if let cached = cachedFallbackSymmetricKey {
            return cached
        }

        if AppStorageProvider.isRunningUnderXCTest {
            let ephemeral = SymmetricKey(size: .bits256)
            cachedFallbackSymmetricKey = ephemeral
            return ephemeral
        }

        guard let appSupportBase = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            let ephemeral = SymmetricKey(size: .bits256)
            cachedFallbackSymmetricKey = ephemeral
            return ephemeral
        }

        let appDir = appSupportBase.appendingPathComponent("AppleMusicRemoteMac", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: appDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let keyPath = appDir.appendingPathComponent(".token_key").path

        // 1. Read existing 32-byte key safely with O_NOFOLLOW (rejecting symlinks)
        let rfd = Darwin.open(keyPath, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if rfd >= 0 {
            var st = stat()
            if fstat(rfd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_size == 32 {
                if (st.st_mode & 0o777) != 0o600 {
                    _ = fchmod(rfd, mode_t(0o600))
                }
                var buf = [UInt8](repeating: 0, count: 32)
                var totalRead = 0
                while totalRead < 32 {
                    let n = buf.withUnsafeMutableBytes { rawBuf -> Int in
                        guard let base = rawBuf.baseAddress else { return -1 }
                        return Darwin.read(rfd, base.advanced(by: totalRead), 32 - totalRead)
                    }
                    if n < 0 && errno == EINTR { continue }
                    if n <= 0 { break }
                    totalRead += n
                }
                Darwin.close(rfd)
                if totalRead == 32 {
                    let loadedKey = SymmetricKey(data: Data(buf))
                    cachedFallbackSymmetricKey = loadedKey
                    return loadedKey
                }
            } else {
                Darwin.close(rfd)
            }
        }

        // 2. Generate and persist a new 256-bit key with O_NOFOLLOW and strict 0600 permissions
        let freshKey = SymmetricKey(size: .bits256)
        let rawKeyBytes = freshKey.withUnsafeBytes { Data($0) }

        var lst = stat()
        if lstat(keyPath, &lst) == 0 {
            if (lst.st_mode & S_IFMT) != S_IFREG {
                // Refuse to touch non-regular / symlink entries
                cachedFallbackSymmetricKey = freshKey
                return freshKey
            }
            _ = Darwin.unlink(keyPath)
        }

        let wfd = Darwin.open(keyPath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        if wfd >= 0 {
            _ = fchmod(wfd, mode_t(0o600))
            var totalWritten = 0
            while totalWritten < rawKeyBytes.count {
                let n = rawKeyBytes.withUnsafeBytes { rawBuf -> Int in
                    guard let base = rawBuf.baseAddress else { return -1 }
                    return Darwin.write(wfd, base.advanced(by: totalWritten), rawKeyBytes.count - totalWritten)
                }
                if n < 0 && errno == EINTR { continue }
                if n <= 0 { break }
                totalWritten += n
            }
            _ = fsync(wfd)
            Darwin.close(wfd)
        }

        cachedFallbackSymmetricKey = freshKey
        return freshKey
    }

    internal static func encryptUserTokenForDefaults(_ plaintext: String) -> String? {
        let trimmed = plaintext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8) else {
            return nil
        }
        let key = loadOrCreateFallbackTokenKey()
        guard let sealed = try? AES.GCM.seal(data, using: key),
              let combined = sealed.combined else {
            return nil
        }
        return encryptedUserTokenPrefix + combined.base64EncodedString()
    }

    internal static func decodeStoredUserTokenFromDefaults(_ rawStored: String) -> (plaintext: String, wasPlaintext: Bool)? {
        let trimmed = rawStored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix(encryptedUserTokenPrefix) {
            let b64 = String(trimmed.dropFirst(encryptedUserTokenPrefix.count))
            guard let combined = Data(base64Encoded: b64),
                  let box = try? AES.GCM.SealedBox(combined: combined),
                  let decryptedData = try? AES.GCM.open(box, using: loadOrCreateFallbackTokenKey()),
                  let plaintext = String(data: decryptedData, encoding: .utf8),
                  !plaintext.isEmpty else {
                return nil
            }
            return (plaintext: plaintext, wasPlaintext: false)
        }
        return (plaintext: trimmed, wasPlaintext: true)
    }

    internal func wipeUserTokenFromAllDefaults() {
        Self.storageDefaults.removeObject(forKey: "AppleMusicUserToken")
        AppStorageProvider.shared.removeObject(forKey: "AppleMusicUserToken")
        for suite in Self.legacySuites {
            Self.legacySuiteDefaults(suite)?.removeObject(forKey: "AppleMusicUserToken")
        }
    }

    internal func loadAndMigrateInitialUserToken(defs: UserDefaults) -> String? {
        var savedToken = readKeychainString(account: "AppleMusicUserToken")
        var rawDefaultsCandidates: [String] = []
        if let t = defs.string(forKey: "AppleMusicUserToken"), !t.isEmpty {
            rawDefaultsCandidates.append(t)
        }
        if let t = AppStorageProvider.shared.string(forKey: "AppleMusicUserToken"), !t.isEmpty, !rawDefaultsCandidates.contains(t) {
            rawDefaultsCandidates.append(t)
        }
        for suite in Self.legacySuites {
            if let t = Self.legacySuiteDefaults(suite)?.string(forKey: "AppleMusicUserToken"), !t.isEmpty, !rawDefaultsCandidates.contains(t) {
                rawDefaultsCandidates.append(t)
            }
        }

        var decodedDefaultsToken: String?
        var sawPlaintextInDefaults = false
        var sawCorruptedCiphertext = false
        for cand in rawDefaultsCandidates {
            if let decoded = Self.decodeStoredUserTokenFromDefaults(cand) {
                if decodedDefaultsToken == nil {
                    decodedDefaultsToken = decoded.plaintext
                }
                if decoded.wasPlaintext {
                    sawPlaintextInDefaults = true
                }
            } else if cand.hasPrefix(Self.encryptedUserTokenPrefix) {
                sawCorruptedCiphertext = true
            }
        }

        var keychainSaved = (savedToken != nil && !savedToken!.isEmpty)
        if !keychainSaved, let leg = decodedDefaultsToken, !leg.isEmpty {
            savedToken = leg
            if !isTestingProcess {
                keychainSaved = writeKeychainString(leg, account: "AppleMusicUserToken")
            }
        }

        let hasTeamSig = Self.hasTeamCodeSignature()
        if !isTestingProcess && keychainSaved && hasTeamSig {
            if !rawDefaultsCandidates.isEmpty {
                wipeUserTokenFromAllDefaults()
            }
        } else if let tok = savedToken, !tok.isEmpty {
            if sawPlaintextInDefaults || sawCorruptedCiphertext || rawDefaultsCandidates.isEmpty {
                wipeUserTokenFromAllDefaults()
                if let encrypted = Self.encryptUserTokenForDefaults(tok) {
                    defs.set(encrypted, forKey: "AppleMusicUserToken")
                    AppStorageProvider.shared.set(encrypted, forKey: "AppleMusicUserToken")
                }
            }
        } else if sawPlaintextInDefaults || sawCorruptedCiphertext {
            wipeUserTokenFromAllDefaults()
        }

        return (savedToken?.isEmpty == false) ? savedToken : nil
    }

    // MARK: - User Token & Storefront API

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
        let cached = withLock { userStorefront.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if Self.isValidStorefrontCode(cached) {
            return cached
        }
        var detected: String? = nil
        if !PlaybackRouter.shared.isTestingEnvironment {
            detected = AccountHealthService.shared.getMacAccountInfo().countryCode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        if detected == nil || !Self.isValidStorefrontCode(detected!) {
            detected = Locale.current.region?.identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        if detected == nil || !Self.isValidStorefrontCode(detected!) {
            for raw in Locale.preferredLanguages {
                let parts = raw.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
                if parts.count >= 2, parts[1].count == 2, Self.isValidStorefrontCode(parts[1]) {
                    detected = parts[1].lowercased()
                    break
                }
            }
        }
        let resolved = Self.sanitizedStorefront(detected, fallback: "us")
        withLock {
            if userStorefront.isEmpty {
                userStorefront = resolved
            }
        }
        return resolved
    }

    /// Resolves the effective Apple Music storefront dynamically from the signed-in account (or Mac account / explicit override when unsigned).
    public func resolveEffectiveStorefront(_ requested: String? = nil) -> String {
        if !PlaybackRouter.shared.isTestingEnvironment && hasUserToken {
            let activeSf = getUserStorefront()
            if Self.isValidStorefrontCode(activeSf) {
                return activeSf
            }
        }
        if let req = requested?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           Self.isValidStorefrontCode(req) {
            return req
        }
        return getUserStorefront()
    }

    /// Indicates whether the user's macOS / app UI display language is Russian (independent of Apple Music account storefront).
    public var isSystemLocaleRussian: Bool {
        var candidates: [String] = []
        candidates.append(contentsOf: Locale.preferredLanguages)
        if let appleLangs = UserDefaults.standard.stringArray(forKey: "AppleLanguages") {
            candidates.append(contentsOf: appleLangs)
        }
        candidates.append(Locale.current.identifier)
        for raw in candidates {
            let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !clean.isEmpty else { continue }
            return clean.hasPrefix("ru")
        }
        return false
    }

    /// Resolves the active Apple Music API language tag (`?l=` & `Accept-Language`) strictly from the account storefront's
    /// `defaultLanguageTag` and `supportedLanguageTags` (so a US account uses `en-US` even on Russian macOS, a RU account uses `ru`, a JP account uses `ja`).
    public func getPreferredLanguageTag(preferredLanguagesOverride: [String]? = nil) -> String {
        let (sf, supported, defLang) = withLock {
            (
                self.userStorefront.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                self.supportedLanguageTags,
                self.defaultLanguageTag.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        var rawCandidates: [String] = []
        if let overrideLangs = preferredLanguagesOverride {
            rawCandidates.append(contentsOf: overrideLangs)
        } else {
            rawCandidates.append(contentsOf: Locale.preferredLanguages)
            if let appleLangs = UserDefaults.standard.stringArray(forKey: "AppleLanguages") {
                rawCandidates.append(contentsOf: appleLangs)
            }
            rawCandidates.append(Locale.current.identifier)
        }

        if !defLang.isEmpty {
            if !supported.isEmpty && !sf.isEmpty {
                for raw in rawCandidates {
                    let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "_", with: "-")
                    guard !clean.isEmpty else { continue }
                    let parts = clean.split(separator: "-").map(String.init)
                    let primary = parts.first?.lowercased() ?? ""
                    let region = parts.count >= 2 ? parts.last!.lowercased() : ""
                    guard region == sf, !primary.isEmpty else { continue }
                    if let exact = supported.first(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
                        return exact
                    }
                    if let primaryMatch = supported.first(where: { $0.caseInsensitiveCompare(primary) == .orderedSame }) {
                        return primaryMatch
                    }
                    if let prefixMatch = supported.first(where: { $0.lowercased().hasPrefix("\(primary)-") }) {
                        return prefixMatch
                    }
                }
            }
            return defLang
        }

        if !supported.isEmpty {
            for raw in rawCandidates {
                let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "_", with: "-")
                guard !clean.isEmpty else { continue }

                let parts = clean.split(separator: "-").map(String.init)
                guard let primary = parts.first?.lowercased(), !primary.isEmpty else { continue }

                if let exact = supported.first(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
                    return exact
                }
                if let primaryMatch = supported.first(where: { $0.caseInsensitiveCompare(primary) == .orderedSame }) {
                    return primaryMatch
                }
                if let prefixMatch = supported.first(where: { $0.lowercased().hasPrefix("\(primary)-") }) {
                    return prefixMatch
                }
            }
            return supported[0]
        }

        for raw in rawCandidates {
            let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "_", with: "-")
            guard !clean.isEmpty else { continue }
            let parts = clean.split(separator: "-").map(String.init)
            guard let primary = parts.first?.lowercased(), !primary.isEmpty else { continue }
            if primary == "zh" && parts.count >= 2 {
                return "\(primary)-\(parts[1])"
            }
            return primary
        }

        return Locale.current.language.languageCode?.identifier.lowercased() ?? "en-US"
    }

    public func getSystemStorefrontAlternateLanguageTag() -> String? {
        let supported = withLock { self.supportedLanguageTags }
        guard !supported.isEmpty else { return nil }
        let primaryAccountLang = getPreferredLanguageTag()
        var candidates: [String] = []
        candidates.append(contentsOf: Locale.preferredLanguages)
        if let appleLangs = UserDefaults.standard.stringArray(forKey: "AppleLanguages") {
            candidates.append(contentsOf: appleLangs)
        }
        for raw in candidates {
            let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: "-")
            guard !clean.isEmpty else { continue }
            let primary = clean.split(separator: "-").first.map(String.init)?.lowercased() ?? ""
            guard !primary.isEmpty else { continue }
            if let match = supported.first(where: {
                $0.caseInsensitiveCompare(clean) == .orderedSame ||
                $0.caseInsensitiveCompare(primary) == .orderedSame ||
                $0.lowercased().hasPrefix("\(primary)-")
            }), match.caseInsensitiveCompare(primaryAccountLang) != .orderedSame {
                return match
            }
        }
        return nil
    }

    internal func storefrontMetadataSnapshot() -> (storefront: String, supportedLanguages: [String], defaultLanguage: String) {
        withLock { (userStorefront, supportedLanguageTags, defaultLanguageTag) }
    }

    internal func configureStorefrontMetadataForTesting(
        storefront: String,
        supportedLanguages: [String],
        defaultLanguage: String
    ) {
        withLock {
            userStorefront = storefront.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            supportedLanguageTags = supportedLanguages
            defaultLanguageTag = defaultLanguage
        }
    }

    public func updateStorefrontMetadata(from storefrontObject: [String: Any]) {
        let sfId = (storefrontObject["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let attrs = storefrontObject["attributes"] as? [String: Any] ?? [:]
        let supported = attrs["supportedLanguageTags"] as? [String] ?? []
        let defLang = attrs["defaultLanguageTag"] as? String ?? ""

        withLock {
            if Self.isValidStorefrontCode(sfId) {
                let lower = sfId.lowercased()
                self.userStorefront = lower
                Self.storageDefaults.set(lower, forKey: "AppleMusicUserStorefront")
                AppStorageProvider.shared.set(lower, forKey: "AppleMusicUserStorefront")
            }
            if !supported.isEmpty {
                self.supportedLanguageTags = supported
                Self.storageDefaults.set(supported, forKey: "AppleMusicSupportedLanguageTags")
                AppStorageProvider.shared.set(supported, forKey: "AppleMusicSupportedLanguageTags")
            }
            if !defLang.isEmpty {
                self.defaultLanguageTag = defLang
                Self.storageDefaults.set(defLang, forKey: "AppleMusicDefaultLanguageTag")
                AppStorageProvider.shared.set(defLang, forKey: "AppleMusicDefaultLanguageTag")
            }
        }
    }

    public func fetchUserStorefront() async -> String {
        guard let devToken = getDeveloperToken(), let uToken = getUserToken(), !uToken.isEmpty else {
            return self.getUserStorefront()
        }
        guard let url = Self.makeAppleMusicAPIURL(path: "/v1/me/storefront") else { return self.getUserStorefront() }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")
        req.setValue(getPreferredLanguageTag(), forHTTPHeaderField: "Accept-Language")
        do {
            let (data, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let arr = json["data"] as? [[String: Any]],
               let first = arr.first,
               let sfId = first["id"] as? String, Self.isValidStorefrontCode(sfId) {
                let lower = sfId.lowercased()
                updateStorefrontMetadata(from: first)
                NSLog("[MusicKitManager] 🌍 Detected active Apple ID storefront: '%@' (locale: '%@')", lower, getPreferredLanguageTag())
                return lower
            }
        } catch {
            NSLog("[MusicKitManager] Error fetching user storefront: %@", error.localizedDescription)
        }
        return self.getUserStorefront()
    }

    public func setUserToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearUserToken()
            return
        }
        let hasTeamSig = Self.hasTeamCodeSignature()
        let savedToKeychain = !isTestingProcess && writeKeychainString(trimmed, account: "AppleMusicUserToken")
        let shouldOmitDefaultsFallback = savedToKeychain && hasTeamSig
        let encryptedFallback = shouldOmitDefaultsFallback ? nil : Self.encryptUserTokenForDefaults(trimmed)

        lock.lock()
        self.userToken = trimmed
        self.personalStationEndpointUnavailable = false
        wipeUserTokenFromAllDefaults()
        if let encrypted = encryptedFallback {
            Self.storageDefaults.set(encrypted, forKey: "AppleMusicUserToken")
            AppStorageProvider.shared.set(encrypted, forKey: "AppleMusicUserToken")
        }
        self.personalDataCache = nil
        self.playlistTracksCache.removeAll()
        lock.unlock()
        CloudCatalogService.shared.invalidateExploreFeedCache()
        AccountHealthService.shared.invalidateCache()
        NSLog("[MusicKitManager] ✅ Saved Apple Music User Token (len: %d)", trimmed.count)
        if !isTestingProcess && !PlaybackRouter.shared.isTestingEnvironment {
            Task.detached(priority: .userInitiated) { [weak self] in
                _ = await self?.fetchUserStorefront()
            }
        }
    }

    public func clearUserToken() {
        lock.lock()
        self.userToken = nil
        self.personalStationEndpointUnavailable = false
        self.personalDataCache = nil
        self.playlistTracksCache.removeAll()
        self.trackArtworkCache.removeAll()
        self.trackArtworkNegativeCache.removeAll()
        self.albumArtworkCacheByNormTitle.removeAll()
        self.userLibraryAlbumsCache = nil
        self.trackCatalogIdCache.removeAll()
        self.artistStationCache.removeAll()
        self.trackStationCache.removeAll()
        wipeUserTokenFromAllDefaults()
        lock.unlock()
        deleteKeychainItem(account: "AppleMusicUserToken")
        CloudCatalogService.shared.invalidateExploreFeedCache()
        AccountHealthService.shared.invalidateCache()
        NSLog("[MusicKitManager] Cleared Apple Music User Token")
    }
}
