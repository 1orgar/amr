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

// MARK: - Local AES-256-GCM Encrypted Secret Store (`org.ksholokhov.amr.client-secrets`)
//
// Uses a strict 0700/0600 local symmetric key (`~/Library/Application Support/AppleMusicRemoteMac/.token_key`)
// with CryptoKit AES-256-GCM instead of macOS File-Based Keychain (`SecItem*`), eliminating scary
// login-keychain password prompts on launch, app relocation, or upgrades.

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

        let fallbackKey = Self.encryptedDefaultsPrefix + cleanAccount
        guard let encrypted = MusicKitManager.encryptUserTokenForDefaults(cleanSecret) else {
            return false
        }
        AppStorageProvider.shared.set(encrypted, forKey: fallbackKey)
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

        AppStorageProvider.shared.removeObject(forKey: Self.encryptedDefaultsPrefix + cleanAccount)
    }
}
