//
//  ClientDeviceManager.swift
//  AppleMusicRemoteMac
//
//  Manages PWA client device registration, persistent UIDs, cryptographic device secrets,
//  local API bearer token, and connection-to-device tracking.
//

import Darwin
import Foundation
import Network

public final class ClientDeviceManager: @unchecked Sendable {
    public static let shared = ClientDeviceManager()

    internal struct InviteTokenEntry {
        let createdAt: TimeInterval
        let expiresAt: TimeInterval
    }

    internal let storageKey = "amr_registered_client_devices_v1"
    internal let revokedStorageKey = "amr_revoked_device_timestamps_v1"
    internal let lock = NSRecursiveLock()

    internal var devicesById: [String: ClientDeviceRecord] = [:]
    internal var revokedTimestampsByDeviceId: [String: TimeInterval] = [:]
    internal var connectionToDeviceId: [UUID: String] = [:]
    internal var pendingBrowserConnections: Set<UUID> = []
    internal var inviteTokens: [String: InviteTokenEntry] = [:]
    internal var activeShareToken: String?
    internal var activeShareTokenExpiry: TimeInterval = 0

    public let localAPIToken: String
    public let gitCommitShort: String
    public let gitCommitDate: String

    public var onDevicesChanged: (() -> Void)?

    private init() {
        if let plistCommit = Bundle.main.infoDictionary?["AMRGitCommit"] as? String,
           !plistCommit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.gitCommitShort = plistCommit.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            self.gitCommitShort = "7278dab"
        }
        if let plistDate = Bundle.main.infoDictionary?["AMRGitCommitDate"] as? String,
           !plistDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.gitCommitDate = plistDate.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            self.gitCommitDate = "2026-11-04"
        }
        self.localAPIToken = Self.loadOrCreateLocalAPIToken()
        loadFromDisk()
    }

    // MARK: - Local API Bearer Token (Keychain + Legacy 0600 Migration)

    private static let localAPITokenKeychainAccount = "local_api_token"

    internal static func secretAccount(forDeviceId deviceId: String) -> String {
        "device.\(deviceId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private static func loadOrCreateLocalAPIToken() -> String {
        if let stored = AppSecretStore.shared.readSecret(account: localAPITokenKeychainAccount),
           stored.count >= 32 {
            return stored
        }

        if !AppStorageProvider.isRunningUnderXCTest {
            let appSupportDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("AppleMusicRemoteMac", isDirectory: true)
            let tokenURL = appSupportDir.appendingPathComponent(".local_api_token", isDirectory: false)

            var st = Darwin.stat()
            if Darwin.lstat(tokenURL.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG {
                let readFD = Darwin.open(tokenURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
                if readFD >= 0 {
                    defer { Darwin.close(readFD) }
                    _ = Darwin.fchmod(readFD, S_IRUSR | S_IWUSR)
                    var buf = [UInt8](repeating: 0, count: 256)
                    let n = Darwin.read(readFD, &buf, buf.count)
                    if n > 0,
                       let str = String(bytes: buf.prefix(n), encoding: .utf8)?
                           .trimmingCharacters(in: .whitespacesAndNewlines),
                       str.count >= 32 {
                        _ = AppSecretStore.shared.writeSecret(str, account: localAPITokenKeychainAccount)
                        if MusicKitManager.hasTeamCodeSignature() {
                            _ = Darwin.unlink(tokenURL.path)
                        }
                        return str
                    }
                }
            }
        }

        let generated = ClientDeviceRecord.generateRandomHexSecret(byteCount: 32)
        _ = AppSecretStore.shared.writeSecret(generated, account: localAPITokenKeychainAccount)
        return generated
    }

    public func validateLocalAPIToken(_ candidate: String?) -> Bool {
        guard var raw = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return false
        }
        if raw.lowercased().hasPrefix("bearer ") {
            raw = String(raw.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ClientDeviceRecord.constantTimeEqual(raw, localAPIToken)
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        loadFromDefaults(AppStorageProvider.shared)
    }

    internal func loadFromDefaults(_ defaults: UserDefaults) {
        lock.lock()
        defer { lock.unlock() }

        if let revDict = defaults.dictionary(forKey: revokedStorageKey) as? [String: TimeInterval] {
            revokedTimestampsByDeviceId = revDict
        }
        guard let data = defaults.data(forKey: storageKey),
              let list = try? JSONDecoder().decode([ClientDeviceRecord].self, from: data) else {
            return
        }
        devicesById.removeAll()
        var migratedAnyLegacyPlaintextSecret = false
        for var item in list {
            let secAccount = Self.secretAccount(forDeviceId: item.deviceId)
            if let keychainSecret = AppSecretStore.shared.readSecret(account: secAccount),
               keychainSecret.count >= 32 {
                item.deviceSecret = keychainSecret
                if item.decodedInlineLegacySecret != nil {
                    migratedAnyLegacyPlaintextSecret = true
                }
            } else if let legacySecret = item.decodedInlineLegacySecret, legacySecret.count >= 32 {
                item.deviceSecret = legacySecret
                _ = AppSecretStore.shared.writeSecret(legacySecret, account: secAccount)
                migratedAnyLegacyPlaintextSecret = true
            } else {
                _ = AppSecretStore.shared.writeSecret(item.deviceSecret, account: secAccount)
            }
            item.decodedInlineLegacySecret = nil
            devicesById[item.deviceId] = item
        }
        if migratedAnyLegacyPlaintextSecret {
            saveToDefaultsLocked(defaults)
        }
    }

    internal func saveToDiskLocked() {
        saveToDefaultsLocked(AppStorageProvider.shared)
    }

    internal func saveToDefaultsLocked(_ defaults: UserDefaults) {
        let list = Array(devicesById.values).sorted { $0.firstSeenAt < $1.firstSeenAt }
        for item in list where item.deviceSecret.count >= 32 {
            _ = AppSecretStore.shared.writeSecret(item.deviceSecret, account: Self.secretAccount(forDeviceId: item.deviceId))
        }
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: storageKey)
        }
        defaults.set(revokedTimestampsByDeviceId, forKey: revokedStorageKey)
    }

    internal func notifyObservers() {
        let callback = onDevicesChanged
        DispatchQueue.main.async {
            callback?()
            SettingsWindow.refreshIfVisible()
            MenuManager.shared.updateMenuState()
        }
    }

    // MARK: - Default Capabilities by Device Type

    public static func defaultLockScreenControls(for deviceType: String) -> Bool {
        switch deviceType.lowercased() {
        case "mobile", "phone", "iphone", "android":
            return true
        case "tablet", "ipad", "tv", "desktop":
            return false
        default:
            return false
        }
    }

    // MARK: - Registration & Connection Lifecycle

    @discardableResult
    public func registerConnection(
        connectionId: UUID,
        deviceId: String,
        deviceName: String,
        deviceType: String,
        preferredLockScreen: Bool?,
        remoteIP: String,
        inviteToken: String? = nil,
        deviceSecret: String? = nil
    ) -> ClientDeviceRecord {
        let trimmedId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanId = trimmedId.count >= 8 ? trimmedId : UUID().uuidString.lowercased()
        let safeType = deviceType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedType = ["mobile", "tablet", "tv", "desktop"].contains(safeType) ? safeType : "mobile"
        let trimmedName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSecret = deviceSecret?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let now = Date().timeIntervalSince1970

        lock.lock()
        let minRevokedAt = devicesById[cleanId]?.revokedAt ?? revokedTimestampsByDeviceId[cleanId]
        let hasValidInvite = validateInviteTokenLocked(inviteToken, afterTimestamp: minRevokedAt, now: now)

        var record: ClientDeviceRecord
        if var existing = devicesById[cleanId] {
            let wasAlreadyBound = (connectionToDeviceId[connectionId] == cleanId)
            let secretMatches = !cleanSecret.isEmpty && ClientDeviceRecord.constantTimeEqual(cleanSecret, existing.deviceSecret)
            let isSameIP: Bool
            if !existing.lastIPAddress.isEmpty && !remoteIP.isEmpty {
                isSameIP = existing.lastIPAddress.lowercased() == remoteIP.lowercased()
            } else if !existing.hasConfirmedSecret {
                isSameIP = true
            } else {
                isSameIP = false
            }

            let allowFirstTimeSameIPUpgrade = cleanSecret.isEmpty && !existing.hasConfirmedSecret && isSameIP
            let isVerifiedOwner = secretMatches || hasValidInvite || allowFirstTimeSameIPUpgrade

            guard isVerifiedOwner else {
                // Spoof Rejection: do NOT bind or overwrite `existing`, and do NOT leak `existing.deviceSecret`!
                connectionToDeviceId.removeValue(forKey: connectionId)
                pendingBrowserConnections.insert(connectionId)
                var rejectedCopy = existing
                rejectedCopy.isAuthorized = false
                rejectedCopy.deviceSecret = ""
                lock.unlock()
                NSLog("[ClientDeviceManager] 🛡️ Rejected spoofed/unverified device registration for %@ (%@) from IP %@", existing.deviceName, existing.shortId, remoteIP)
                return rejectedCopy
            }

            pendingBrowserConnections.remove(connectionId)
            connectionToDeviceId[connectionId] = cleanId

            if secretMatches {
                existing.hasConfirmedSecret = true
            }
            if !trimmedName.isEmpty {
                existing.deviceName = trimmedName
            }
            if !existing.isAuthorized || (wasAlreadyBound && existing.deviceType != normalizedType) {
                if let prefLock = preferredLockScreen {
                    existing.lockScreenControls = prefLock
                } else if existing.deviceType != normalizedType {
                    existing.lockScreenControls = Self.defaultLockScreenControls(for: normalizedType)
                }
            }
            existing.deviceType = normalizedType
            existing.lastSeenAt = now
            if !remoteIP.isEmpty {
                existing.lastIPAddress = remoteIP
            }
            if hasValidInvite && !existing.isAuthorized {
                existing.isAuthorized = true
                existing.revokedAt = nil
                revokedTimestampsByDeviceId.removeValue(forKey: cleanId)
                NSLog("[ClientDeviceManager] 🎟️ Existing device auto-authorized via QR invite token: %@ (%@)", existing.deviceName, existing.shortId)
            }
            devicesById[cleanId] = existing
            record = existing
        } else {
            pendingBrowserConnections.remove(connectionId)
            connectionToDeviceId[connectionId] = cleanId

            let defaultLock = preferredLockScreen ?? Self.defaultLockScreenControls(for: normalizedType)
            let fallbackName: String
            switch normalizedType {
            case "mobile": fallbackName = "iPhone / Mobile"
            case "tablet": fallbackName = "iPad / Tablet"
            case "tv": fallbackName = "Smart TV / StandBy"
            default: fallbackName = "Mac / Desktop"
            }
            if hasValidInvite {
                revokedTimestampsByDeviceId.removeValue(forKey: cleanId)
            }
            record = ClientDeviceRecord(
                deviceId: cleanId,
                deviceName: trimmedName.isEmpty ? fallbackName : trimmedName,
                deviceType: normalizedType,
                isAuthorized: hasValidInvite,
                lockScreenControls: defaultLock,
                deviceSecret: ClientDeviceRecord.generateRandomHexSecret(byteCount: 32),
                hasConfirmedSecret: false,
                revokedAt: nil,
                firstSeenAt: now,
                lastSeenAt: now,
                lastIPAddress: remoteIP
            )
            if !record.isAuthorized {
                let unauthorizedRecords = devicesById.values.filter { !$0.isAuthorized }
                if unauthorizedRecords.count >= 64 {
                    let toEvictCount = unauthorizedRecords.count - 63
                    let oldestUnauthorized = unauthorizedRecords.sorted { $0.lastSeenAt < $1.lastSeenAt }.prefix(toEvictCount)
                    for old in oldestUnauthorized {
                        devicesById.removeValue(forKey: old.deviceId)
                        AppSecretStore.shared.deleteSecret(account: Self.secretAccount(forDeviceId: old.deviceId))
                    }
                }
            }
            devicesById[cleanId] = record
            if hasValidInvite {
                NSLog("[ClientDeviceManager] 🎟️ New client device registered & auto-authorized via QR invite: %@ (%@) [%@]", record.deviceName, record.shortId, remoteIP)
            } else {
                NSLog("[ClientDeviceManager] 📱 New client device registered (pending approval): %@ (%@) [%@]", record.deviceName, record.shortId, remoteIP)
            }
        }

        saveToDiskLocked()
        lock.unlock()

        notifyObservers()
        return record
    }

    public func markBrowserConnectionPending(connectionId: UUID) {
        lock.lock()
        pendingBrowserConnections.insert(connectionId)
        lock.unlock()
    }

    public func unregisterConnection(connectionId: UUID) {
        lock.lock()
        pendingBrowserConnections.remove(connectionId)
        let removed = connectionToDeviceId.removeValue(forKey: connectionId)
        if let devId = removed, var existing = devicesById[devId] {
            existing.lastSeenAt = Date().timeIntervalSince1970
            devicesById[devId] = existing
            saveToDiskLocked()
        }
        lock.unlock()

        if removed != nil {
            notifyObservers()
        }
    }

    // MARK: - Device & Connection Lookups

    public func getDeviceId(for connectionId: UUID) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return connectionToDeviceId[connectionId]
    }

    public func getDeviceId(forConnection connectionId: UUID) -> String? {
        return getDeviceId(for: connectionId)
    }

    public func getUnauthorizedConnectionIds() -> Set<UUID> {
        lock.lock()
        defer { lock.unlock() }
        var result = pendingBrowserConnections
        for (connId, devId) in connectionToDeviceId {
            if devicesById[devId]?.isAuthorized != true {
                result.insert(connId)
            }
        }
        return result
    }

    public func getDeviceForConnection(connectionId: UUID) -> ClientDeviceRecord? {
        lock.lock()
        defer { lock.unlock() }
        guard let devId = connectionToDeviceId[connectionId] else { return nil }
        return devicesById[devId]
    }

    public func getDevice(deviceId: String) -> ClientDeviceRecord? {
        let key = deviceId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        lock.lock()
        defer { lock.unlock() }
        return devicesById[key]
    }

    public func device(for deviceId: String) -> ClientDeviceRecord? {
        return getDevice(deviceId: deviceId)
    }

    public func isDeviceOnline(deviceId: String) -> Bool {
        let key = deviceId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        lock.lock()
        defer { lock.unlock() }
        return connectionToDeviceId.values.contains(key)
    }

    public func getConnectionIds(forDeviceId deviceId: String) -> [UUID] {
        let key = deviceId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        lock.lock()
        defer { lock.unlock() }
        return connectionToDeviceId.compactMap { (connId, devId) in
            devId == key ? connId : nil
        }
    }

    public func getAuthorizedConnectionIds() -> Set<UUID> {
        lock.lock()
        defer { lock.unlock() }
        var result = Set<UUID>()
        for (connId, devId) in connectionToDeviceId {
            if devicesById[devId]?.isAuthorized == true {
                result.insert(connId)
            }
        }
        return result
    }

    public func getAllDevices() -> [ClientDeviceRecord] {
        lock.lock()
        let all = Array(devicesById.values)
        let onlineIds = Set(connectionToDeviceId.values)
        lock.unlock()

        return all.sorted { a, b in
            if a.isAuthorized != b.isAuthorized {
                return !a.isAuthorized
            }
            let aOnline = onlineIds.contains(a.deviceId)
            let bOnline = onlineIds.contains(b.deviceId)
            if aOnline != bOnline {
                return aOnline
            }
            return a.lastSeenAt > b.lastSeenAt
        }
    }

    public var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return devicesById.values.filter { !$0.isAuthorized }.count
    }
}
