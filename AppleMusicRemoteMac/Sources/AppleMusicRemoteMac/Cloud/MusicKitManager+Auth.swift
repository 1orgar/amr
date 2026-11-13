//
//  MusicKitManager+Auth.swift
//  AppleMusicRemoteMac
//

import Foundation

extension MusicKitManager {
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

    /// Resolves the active system/user locale into an Apple Music API language tag (e.g. "ru", "en-US", "ja")
    /// that matches how macOS `Music.app` displays and indexes catalog tracks.
    public func getPreferredLanguageTag() -> String {
        let supported = withLock { self.supportedLanguageTags }

        var rawCandidates: [String] = []
        rawCandidates.append(contentsOf: Locale.preferredLanguages)
        if let appleLangs = UserDefaults.standard.stringArray(forKey: "AppleLanguages") {
            rawCandidates.append(contentsOf: appleLangs)
        }
        rawCandidates.append(Locale.current.identifier)

        for raw in rawCandidates {
            let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "_", with: "-")
            guard !clean.isEmpty else { continue }

            let parts = clean.split(separator: "-").map(String.init)
            guard let primary = parts.first?.lowercased(), !primary.isEmpty else { continue }

            if !supported.isEmpty {
                // 1. Exact BCP-47 tag match in storefront's supportedLanguageTags (e.g. "en-US", "pt-BR", "zh-Hans-CN")
                if let exact = supported.first(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
                    return exact
                }
                // 2. Primary language code match in storefront's supportedLanguageTags (e.g. "ru", "ko", "ar")
                if let primaryMatch = supported.first(where: { $0.caseInsensitiveCompare(primary) == .orderedSame }) {
                    return primaryMatch
                }
                // 3. Regional variant match in storefront's supportedLanguageTags (e.g. "en" -> "en-US", "fr" -> "fr-CA")
                if let prefixMatch = supported.first(where: { $0.lowercased().hasPrefix("\(primary)-") }) {
                    return prefixMatch
                }
            }

            // Fallback when storefront supportedLanguageTags is not yet loaded or doesn't list the tag:
            if primary == "zh" && parts.count >= 2 {
                return "\(primary)-\(parts[1])"
            }
            return primary
        }

        return "ru"
    }

    public func updateStorefrontMetadata(from storefrontObject: [String: Any]) {
        let sfId = (storefrontObject["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let attrs = storefrontObject["attributes"] as? [String: Any] ?? [:]
        let supported = attrs["supportedLanguageTags"] as? [String] ?? []
        let defLang = attrs["defaultLanguageTag"] as? String ?? ""

        withLock {
            if !sfId.isEmpty {
                let lower = sfId.lowercased()
                self.userStorefront = lower
                Self.storageDefaults.set(lower, forKey: "AppleMusicUserStorefront")
                UserDefaults.standard.set(lower, forKey: "AppleMusicUserStorefront")
            }
            if !supported.isEmpty {
                self.supportedLanguageTags = supported
                Self.storageDefaults.set(supported, forKey: "AppleMusicSupportedLanguageTags")
                UserDefaults.standard.set(supported, forKey: "AppleMusicSupportedLanguageTags")
            }
            if !defLang.isEmpty {
                self.defaultLanguageTag = defLang
                Self.storageDefaults.set(defLang, forKey: "AppleMusicDefaultLanguageTag")
                UserDefaults.standard.set(defLang, forKey: "AppleMusicDefaultLanguageTag")
            }
        }
    }

    public func fetchUserStorefront() async -> String {
        guard let devToken = getDeveloperToken(), let uToken = getUserToken(), !uToken.isEmpty else {
            return self.getUserStorefront()
        }
        guard let url = URL(string: "https://api.music.apple.com/v1/me/storefront") else { return self.getUserStorefront() }
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
               let sfId = first["id"] as? String, !sfId.isEmpty {
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
        let hasTeamSig = Self.hasTeamCodeSignature()
        let savedToKeychain = !isTestingProcess && writeKeychainString(token, account: "AppleMusicUserToken")
        let shouldRemovePlaintext = savedToKeychain && hasTeamSig

        lock.lock()
        self.userToken = token
        if shouldRemovePlaintext {
            Self.storageDefaults.removeObject(forKey: "AppleMusicUserToken")
            UserDefaults.standard.removeObject(forKey: "AppleMusicUserToken")
            for suite in ["org.ksholokhov.amr.mac", "AppleMusicRemoteMac", "org.ksholokhov.AppleMusicRemoteMac"] {
                UserDefaults(suiteName: suite)?.removeObject(forKey: "AppleMusicUserToken")
            }
        } else {
            Self.storageDefaults.set(token, forKey: "AppleMusicUserToken")
            UserDefaults.standard.set(token, forKey: "AppleMusicUserToken")
            for suite in ["org.ksholokhov.amr.mac", "AppleMusicRemoteMac", "org.ksholokhov.AppleMusicRemoteMac"] {
                UserDefaults(suiteName: suite)?.set(token, forKey: "AppleMusicUserToken")
            }
        }
        self.personalDataCache = nil
        self.playlistTracksCache.removeAll()
        lock.unlock()
        CloudCatalogService.shared.invalidateExploreFeedCache()
        NSLog("[MusicKitManager] ✅ Saved Apple Music User Token (len: %d)", token.count)
        Task.detached(priority: .userInitiated) { [weak self] in
            _ = await self?.fetchUserStorefront()
        }
    }

    public func clearUserToken() {
        lock.lock()
        self.userToken = nil
        self.personalDataCache = nil
        self.playlistTracksCache.removeAll()
        self.trackArtworkCache.removeAll()
        self.trackCatalogIdCache.removeAll()
        self.artistStationCache.removeAll()
        self.trackStationCache.removeAll()
        Self.storageDefaults.removeObject(forKey: "AppleMusicUserToken")
        UserDefaults.standard.removeObject(forKey: "AppleMusicUserToken")
        for suite in ["org.ksholokhov.amr.mac", "AppleMusicRemoteMac", "org.ksholokhov.AppleMusicRemoteMac"] {
            UserDefaults(suiteName: suite)?.removeObject(forKey: "AppleMusicUserToken")
        }
        lock.unlock()
        deleteKeychainItem(account: "AppleMusicUserToken")
        CloudCatalogService.shared.invalidateExploreFeedCache()
        NSLog("[MusicKitManager] Cleared Apple Music User Token")
    }
}
