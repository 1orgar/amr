//
//  AccountHealthService.swift
//  AppleMusicRemoteMac
//
//  End-to-end Apple ID account verification and health check between macOS Music.app and WebKit/MusicKit.
//

import Foundation

public struct AccountHealthStatus: Codable, Sendable {
    public var status: String // "synchronized", "mismatch", "token_expired", "not_authorized"
    public var macAppleId: String?
    public var macDsid: String?
    public var isSubscriptionActive: Bool
    public var macStorefront: String?
    public var macCountryCode: String?
    public var webStorefront: String?
    public var isTokenValid: Bool
    public var isTokenExpired: Bool
    public var isAccountsMatched: Bool
    public var message: String
    public var checkedAt: Date

    enum CodingKeys: String, CodingKey {
        case status
        case macAppleId = "mac_apple_id"
        case macDsid = "mac_dsid"
        case isSubscriptionActive = "is_subscription_active"
        case macStorefront = "mac_storefront"
        case macCountryCode = "mac_country_code"
        case webStorefront = "web_storefront"
        case isTokenValid = "is_token_valid"
        case isTokenExpired = "is_token_expired"
        case isAccountsMatched = "is_accounts_matched"
        case message
        case checkedAt = "checked_at"
    }

    public init(
        status: String = "not_authorized",
        macAppleId: String? = nil,
        macDsid: String? = nil,
        isSubscriptionActive: Bool = false,
        macStorefront: String? = nil,
        macCountryCode: String? = nil,
        webStorefront: String? = nil,
        isTokenValid: Bool = false,
        isTokenExpired: Bool = false,
        isAccountsMatched: Bool = false,
        message: String = "",
        checkedAt: Date = Date()
    ) {
        self.status = status
        self.macAppleId = macAppleId
        self.macDsid = macDsid
        self.isSubscriptionActive = isSubscriptionActive
        self.macStorefront = macStorefront
        self.macCountryCode = macCountryCode
        self.webStorefront = webStorefront
        self.isTokenValid = isTokenValid
        self.isTokenExpired = isTokenExpired
        self.isAccountsMatched = isAccountsMatched
        self.message = message
        self.checkedAt = checkedAt
    }

    public var dictionary: [String: Any] {
        return [
            "status": status,
            "mac_apple_id": macAppleId as Any,
            "mac_dsid": macDsid as Any,
            "is_subscription_active": isSubscriptionActive,
            "mac_storefront": macStorefront as Any,
            "mac_country_code": macCountryCode as Any,
            "web_storefront": webStorefront as Any,
            "is_token_valid": isTokenValid,
            "is_token_expired": isTokenExpired,
            "is_accounts_matched": isAccountsMatched,
            "message": message,
            "checked_at": ISO8601DateFormatter().string(from: checkedAt)
        ]
    }
}

public final class AccountHealthService: @unchecked Sendable {
    public static let shared = AccountHealthService()

    private let lock = NSLock()
    private var cachedStatus: (timestamp: Date, status: AccountHealthStatus)?

    // Common Apple Music Storefront ID to ISO Country Code mappings
    private let storefrontMap: [String: String] = [
        "143441": "us",
        "143469": "ru",
        "143444": "gb",
        "143442": "fr",
        "143443": "de",
        "143462": "jp",
        "143455": "ca",
        "143460": "au",
        "143465": "it",
        "143454": "es",
        "143467": "nl",
        "143468": "se",
        "143476": "ch",
        "143491": "kr",
        "143477": "br",
        "143472": "tr"
    ]

    private init() {}

    // MARK: - Mac Account Detection

    public func getMacAccountInfo() -> (appleId: String?, dsid: String?, isSubscriptionActive: Bool, storefrontId: String?, countryCode: String?) {
        var appleId: String? = nil
        var dsid: String? = nil
        var isSubscriptionActive = false
        var storefrontId: String? = nil

        // 1. Primary Apple ID email from MobileMeAccounts
        if let prefs = UserDefaults(suiteName: "MobileMeAccounts"),
           let accounts = prefs.array(forKey: "Accounts") as? [[String: Any]] {
            for acc in accounts {
                if let aid = acc["AccountID"] as? String, !aid.isEmpty {
                    appleId = aid
                    break
                }
            }
        }

        // 2. Music.app active subscription & DSID from iTunes Cloud preferences
        let itunesCloudPath = ("~/Library/Preferences/com.apple.itunescloud.plist" as NSString).expandingTildeInPath
        if let dict = NSDictionary(contentsOfFile: itunesCloudPath) as? [String: Any],
           let sub = dict["ICDefaultsCachedSubscriptionStatus"] as? [String: Any] {
            if let d = sub["lastKnownActiveDSID"] {
                dsid = "\(d)"
            }
            if let responses = sub["responses"] as? [String: Any], let activeDsid = dsid {
                for (k, v) in responses {
                    if k.contains("\"dsid\":\"\(activeDsid)\""),
                       let obj = v as? [String: Any],
                       let statusDict = obj["status"] as? [String: Any] {
                        if let music = statusDict["music"] as? [String: Any],
                           let s = music["status"] as? String {
                            isSubscriptionActive = (s.localizedCaseInsensitiveCompare("Enabled") == .orderedSame)
                        }
                        if let data = k.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let sf = json["storefrontID"] as? String {
                            storefrontId = sf
                        }
                    }
                }
            }
        }

        // Fallback: If subscription not in responses, check if lastKnownActiveDSID is present
        if !isSubscriptionActive && dsid != nil {
            isSubscriptionActive = true
        }

        // Fallback for storefront: check MusicKitManager storefront
        let defaultSf = MusicKitManager.shared.getUserStorefront()
        let countryCode = storefrontId.flatMap { storefrontMap[$0] } ?? defaultSf
        return (appleId, dsid, isSubscriptionActive, storefrontId, countryCode)
    }

    // MARK: - Health Check & Cross-Verification

    private func getCachedStatus(forceRefresh: Bool) -> AccountHealthStatus? {
        lock.lock()
        defer { lock.unlock() }
        if !forceRefresh, let cached = cachedStatus, Date().timeIntervalSince(cached.timestamp) < 60 {
            return cached.status
        }
        return nil
    }

    public func checkAccountHealth(forceRefresh: Bool = false) async -> AccountHealthStatus {
        if let cached = getCachedStatus(forceRefresh: forceRefresh) {
            return cached
        }

        let macInfo = getMacAccountInfo()
        let userToken = MusicKitManager.shared.getUserToken()

        guard let token = userToken, !token.isEmpty else {
            let status = AccountHealthStatus(
                status: "not_authorized",
                macAppleId: macInfo.appleId,
                macDsid: macInfo.dsid,
                isSubscriptionActive: macInfo.isSubscriptionActive,
                macStorefront: macInfo.storefrontId,
                macCountryCode: macInfo.countryCode,
                webStorefront: nil,
                isTokenValid: false,
                isTokenExpired: false,
                isAccountsMatched: false,
                message: "Web UI не авторизован в Apple ID. Выполните вход через карточку на главной странице.",
                checkedAt: Date()
            )
            updateCache(status)
            return status
        }

        // Validate token with Apple Music REST API
        let tokenCheck = await validateToken(userToken: token)
        if tokenCheck.isExpired {
            let status = AccountHealthStatus(
                status: "token_expired",
                macAppleId: macInfo.appleId,
                macDsid: macInfo.dsid,
                isSubscriptionActive: macInfo.isSubscriptionActive,
                macStorefront: macInfo.storefrontId,
                macCountryCode: macInfo.countryCode,
                webStorefront: tokenCheck.storefront ?? macInfo.countryCode,
                isTokenValid: false,
                isTokenExpired: true,
                isAccountsMatched: false,
                message: "Срок действия сессии Apple ID в браузере истек.",
                checkedAt: Date()
            )
            updateCache(status)
            return status
        }

        guard tokenCheck.isValid else {
            let status = AccountHealthStatus(
                status: macInfo.appleId != nil ? "synchronized" : "not_authorized",
                macAppleId: macInfo.appleId,
                macDsid: macInfo.dsid,
                isSubscriptionActive: macInfo.isSubscriptionActive,
                macStorefront: macInfo.storefrontId,
                macCountryCode: macInfo.countryCode,
                webStorefront: tokenCheck.storefront ?? macInfo.countryCode,
                isTokenValid: false,
                isTokenExpired: false,
                isAccountsMatched: macInfo.appleId != nil,
                message: macInfo.appleId != nil
                    ? "Учетная запись Apple ID авторизована на Mac (\(macInfo.appleId!))."
                    : "Не удалось верифицировать токен Apple ID.",
                checkedAt: Date()
            )
            updateCache(status)
            return status
        }

        // Check storefront mismatch if detectable
        if let macCountry = macInfo.countryCode, let webSf = tokenCheck.storefront, !webSf.isEmpty {
            if macCountry.lowercased() != webSf.lowercased() {
                let status = AccountHealthStatus(
                    status: "mismatch",
                    macAppleId: macInfo.appleId,
                    macDsid: macInfo.dsid,
                    isSubscriptionActive: macInfo.isSubscriptionActive,
                    macStorefront: macInfo.storefrontId,
                    macCountryCode: macInfo.countryCode,
                    webStorefront: webSf,
                    isTokenValid: true,
                    isTokenExpired: false,
                    isAccountsMatched: false,
                    message: "Несовпадение регионов: Mac (\(macCountry.uppercased())) и Web (\(webSf.uppercased())).",
                    checkedAt: Date()
                )
                updateCache(status)
                return status
            }
        }

        // Verify library fingerprint matching (compare playlist titles)
        let fingerprintMatched = await verifyLibraryFingerprint(userToken: token)

        let overallStatus = fingerprintMatched ? "synchronized" : "mismatch"
        let msg = fingerprintMatched
            ? "Учетная запись Apple ID полностью синхронизирована с Mac."
            : "Медиатека в браузере отличается от медиатеки Music.app на Mac."

        let status = AccountHealthStatus(
            status: overallStatus,
            macAppleId: macInfo.appleId,
            macDsid: macInfo.dsid,
            isSubscriptionActive: macInfo.isSubscriptionActive,
            macStorefront: macInfo.storefrontId,
            macCountryCode: macInfo.countryCode,
            webStorefront: tokenCheck.storefront ?? macInfo.countryCode,
            isTokenValid: true,
            isTokenExpired: false,
            isAccountsMatched: fingerprintMatched,
            message: msg,
            checkedAt: Date()
        )
        updateCache(status)
        return status
    }

    private func updateCache(_ status: AccountHealthStatus) {
        lock.lock()
        cachedStatus = (Date(), status)
        lock.unlock()
    }

    // MARK: - Apple Music API Validation

    private func validateToken(userToken: String) async -> (isValid: Bool, isExpired: Bool, storefront: String?) {
        guard let devToken = MusicKitManager.shared.getDeveloperToken() else {
            return (false, false, nil)
        }

        guard let url = URL(string: "https://api.music.apple.com/v1/me/storefront") else {
            return (false, false, nil)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 6.0
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue(userToken, forHTTPHeaderField: "Music-User-Token")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let dataArr = json["data"] as? [[String: Any]],
                       let first = dataArr.first,
                       let sfId = first["id"] as? String {
                        return (true, false, sfId)
                    }
                    return (true, false, nil)
                } else if http.statusCode == 401 || http.statusCode == 403 {
                    return (false, true, nil)
                }
            }
        } catch {
            NSLog("[AccountHealthService] Error verifying token: %@", error.localizedDescription)
        }
        return (false, false, nil)
    }

    // MARK: - Library Fingerprint Matching

    private func verifyLibraryFingerprint(userToken: String) async -> Bool {
        guard let devToken = MusicKitManager.shared.getDeveloperToken() else { return true }
        guard let url = URL(string: "https://api.music.apple.com/v1/me/library/playlists?limit=8") else { return true }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 6.0
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue(userToken, forHTTPHeaderField: "Music-User-Token")

        var cloudNames = Set<String>()
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dataArr = json["data"] as? [[String: Any]] {
                    for item in dataArr {
                        if let attrs = item["attributes"] as? [String: Any],
                           let name = attrs["name"] as? String {
                            cloudNames.insert(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                        }
                    }
                }
            } else {
                return true
            }
        } catch {
            return true
        }

        if cloudNames.isEmpty {
            return true
        }

        let localPlaylists = LibraryService.shared.getPlaylists()
        let localNames = Set(localPlaylists.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })

        let intersection = cloudNames.intersection(localNames)
        if !intersection.isEmpty {
            return true
        }

        let genericPlaylists: Set<String> = ["музыка", "music", "любимые песни", "favorite songs"]
        let nonGenericCloud = cloudNames.subtracting(genericPlaylists)
        let nonGenericLocal = localNames.subtracting(genericPlaylists)

        if nonGenericCloud.isEmpty || nonGenericLocal.isEmpty {
            return true
        }

        return false
    }
}
