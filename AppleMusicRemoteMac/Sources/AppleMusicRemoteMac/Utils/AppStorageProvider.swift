//
//  AppStorageProvider.swift
//  AppleMusicRemoteMac
//
//  Process-isolated UserDefaults provider for deterministic parallel XCTest execution (`swift test --parallel`)
//  and Keychain-backed secret storage (`org.ksholokhov.amr.client-secrets`) for client device secrets and API tokens.
//

import Darwin
import Foundation
import Security

private var _xctestSuiteNameToCleanAtExit: UnsafeMutablePointer<CChar>? = nil
private var _xctestCacheDirToCleanAtExit: UnsafeMutablePointer<CChar>? = nil

private func _cleanupXCTestUserDefaultsAtExit() {
    if let cStr = _xctestSuiteNameToCleanAtExit {
        let suite = String(cString: cStr)
        UserDefaults().removePersistentDomain(forName: suite)
    }
    if let dirStr = _xctestCacheDirToCleanAtExit {
        let dirPath = String(cString: dirStr)
        try? FileManager.default.removeItem(atPath: dirPath)
    }
}

public enum AppStorageProvider {
    public static let isRunningUnderXCTest: Bool = {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
            || env["XCTestSessionIdentifier"] != nil {
            return true
        }
        return NSClassFromString("XCTestCase") != nil
    }()

    public static let activeSuiteName: String? = {
        guard isRunningUnderXCTest else { return nil }
        return "org.ksholokhov.amr.xctest.\(getpid())"
    }()

    /// Shared `UserDefaults` instance: `UserDefaults.standard` in production, or a dedicated per-PID suite under `XCTest`
    /// so parallel `xctest` workers never race on `~/Library/Preferences/` keys.
    public static let shared: UserDefaults = {
        guard let suite = activeSuiteName, let isolated = UserDefaults(suiteName: suite) else {
            return UserDefaults.standard
        }
        isolated.removePersistentDomain(forName: suite)
        _xctestSuiteNameToCleanAtExit = strdup(suite)
        atexit(_cleanupXCTestUserDefaultsAtExit)
        return isolated
    }()

    /// Per-PID temporary root directory for disk caches during `XCTest` so parallel `xctest` workers
    /// never race on `~/Library/Caches/com.kirill.AppleMusicRemoteMac/` or wipe user caches.
    public static let testCachesRootDirectory: URL? = {
        guard isRunningUnderXCTest else { return nil }
        _ = shared // Ensure atexit cleanup hook is registered once
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("amr-xctest-caches-\(getpid())", isDirectory: true)
        _xctestCacheDirToCleanAtExit = strdup(dir.path)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}

// MARK: - Keychain & Encrypted Secret Store (`org.ksholokhov.amr.client-secrets`)

public final class AppSecretStore: @unchecked Sendable {
    public static let shared = AppSecretStore()
    public static let serviceName = "org.ksholokhov.amr.client-secrets"
    private static let encryptedDefaultsPrefix = "amr.secret.fallback.v1."

    private let lock = NSLock()
    private var inMemoryTestSecrets: [String: String] = [:]

    private init() {}

    public func readSecret(account: String) -> String? {
        let cleanAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAccount.isEmpty else { return nil }

        if AppStorageProvider.isRunningUnderXCTest {
            return lock.withLock { inMemoryTestSecrets[cleanAccount] }
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: cleanAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip as String
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess,
           let data = item as? Data,
           let secret = String(data: data, encoding: .utf8),
           !secret.isEmpty {
            return secret
        }

        // Ad-hoc unsigned dev fallback: AES-GCM encrypted entry in AppStorageProvider (never plaintext)
        let fallbackKey = Self.encryptedDefaultsPrefix + cleanAccount
        if let rawCipher = AppStorageProvider.shared.string(forKey: fallbackKey),
           rawCipher.hasPrefix(MusicKitManager.encryptedUserTokenPrefix),
           let decoded = MusicKitManager.decodeStoredUserTokenFromDefaults(rawCipher) {
            return decoded.plaintext
        }
        return nil
    }

    @discardableResult
    public func writeSecret(_ secret: String, account: String) -> Bool {
        let cleanAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAccount.isEmpty, !cleanSecret.isEmpty else { return false }

        if AppStorageProvider.isRunningUnderXCTest {
            lock.withLock {
                inMemoryTestSecrets[cleanAccount] = cleanSecret
            }
            return true
        }

        var storedInKeychain = false
        if let data = cleanSecret.data(using: .utf8) {
            let baseQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Self.serviceName,
                kSecAttrAccount as String: cleanAccount
            ]
            SecItemDelete(baseQuery as CFDictionary)
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock as String
            storedInKeychain = (SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess)
        }

        let fallbackKey = Self.encryptedDefaultsPrefix + cleanAccount
        if storedInKeychain && MusicKitManager.hasTeamCodeSignature() {
            AppStorageProvider.shared.removeObject(forKey: fallbackKey)
        } else if let encrypted = MusicKitManager.encryptUserTokenForDefaults(cleanSecret) {
            AppStorageProvider.shared.set(encrypted, forKey: fallbackKey)
        }
        return true
    }

    public func deleteSecret(account: String) {
        let cleanAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAccount.isEmpty else { return }

        if AppStorageProvider.isRunningUnderXCTest {
            _ = lock.withLock {
                inMemoryTestSecrets.removeValue(forKey: cleanAccount)
            }
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: cleanAccount
        ]
        SecItemDelete(query as CFDictionary)
        AppStorageProvider.shared.removeObject(forKey: Self.encryptedDefaultsPrefix + cleanAccount)
    }
}
