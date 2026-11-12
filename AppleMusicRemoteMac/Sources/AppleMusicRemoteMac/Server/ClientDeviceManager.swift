//
//  ClientDeviceManager.swift
//  AppleMusicRemoteMac
//
//  Manages PWA client device registration, persistent UIDs, authorization state,
//  and per-device capabilities (such as Lock Screen / MediaSession controls).
//

import AppKit
import CoreImage
import Foundation
import Network

public struct ClientDeviceRecord: Codable, Sendable, Equatable {
    public let deviceId: String
    public var deviceName: String
    public var deviceType: String // "mobile", "tablet", "tv", "desktop"
    public var isAuthorized: Bool
    public var lockScreenControls: Bool
    public var firstSeenAt: TimeInterval
    public var lastSeenAt: TimeInterval
    public var lastIPAddress: String

    public var shortId: String {
        let clean = deviceId.replacingOccurrences(of: "-", with: "").uppercased()
        if clean.count >= 8 {
            let prefix = clean.prefix(4)
            let suffix = clean.dropFirst(4).prefix(4)
            return "\(prefix)-\(suffix)"
        }
        return clean
    }

    public var dictionary: [String: Any] {
        return [
            "device_id": deviceId,
            "short_id": shortId,
            "device_name": deviceName,
            "device_type": deviceType,
            "authorized": isAuthorized,
            "lock_screen_controls": lockScreenControls,
            "first_seen_at": firstSeenAt,
            "last_seen_at": lastSeenAt,
            "last_ip": lastIPAddress,
            "git_commit": ClientDeviceManager.shared.gitCommitShort,
            "git_commit_date": ClientDeviceManager.shared.gitCommitDate
        ]
    }
}

public final class ClientDeviceManager: @unchecked Sendable {
    public static let shared = ClientDeviceManager()

    private let storageKey = "amr_registered_client_devices_v1"
    private let lock = NSRecursiveLock()

    private var devicesById: [String: ClientDeviceRecord] = [:]
    private var connectionToDeviceId: [UUID: String] = [:]
    private var inviteTokens: [String: TimeInterval] = [:]
    private var activeShareToken: String?
    private var activeShareTokenExpiry: TimeInterval = 0

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
        loadFromDisk()
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        lock.lock()
        defer { lock.unlock() }

        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let list = try? JSONDecoder().decode([ClientDeviceRecord].self, from: data) else {
            return
        }
        devicesById.removeAll()
        for item in list {
            devicesById[item.deviceId] = item
        }
    }

    private func saveToDiskLocked() {
        let list = Array(devicesById.values).sorted { $0.firstSeenAt < $1.firstSeenAt }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func notifyObservers() {
        let callback = onDevicesChanged
        DispatchQueue.main.async {
            callback?()
            SettingsWindow.shared.refreshState()
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
        inviteToken: String? = nil
    ) -> ClientDeviceRecord {
        let trimmedId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let safeId = trimmedId.isEmpty ? UUID().uuidString.lowercased() : trimmedId
        let safeType = deviceType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedType = ["mobile", "tablet", "tv", "desktop"].contains(safeType) ? safeType : "mobile"
        let trimmedName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date().timeIntervalSince1970
        let hasValidInvite = validateInviteToken(inviteToken)

        lock.lock()
        connectionToDeviceId[connectionId] = safeId

        var record: ClientDeviceRecord
        if var existing = devicesById[safeId] {
            if !trimmedName.isEmpty {
                existing.deviceName = trimmedName
            }
            existing.deviceType = normalizedType
            existing.lastSeenAt = now
            if !remoteIP.isEmpty {
                existing.lastIPAddress = remoteIP
            }
            if hasValidInvite && !existing.isAuthorized {
                existing.isAuthorized = true
                NSLog("[ClientDeviceManager] 🎟️ Existing device auto-authorized via QR invite token: %@ (%@)", existing.deviceName, existing.shortId)
            }
            devicesById[safeId] = existing
            record = existing
        } else {
            let defaultLock = preferredLockScreen ?? Self.defaultLockScreenControls(for: normalizedType)
            let fallbackName: String
            switch normalizedType {
            case "mobile": fallbackName = "iPhone / Mobile"
            case "tablet": fallbackName = "iPad / Tablet"
            case "tv": fallbackName = "Smart TV / StandBy"
            default: fallbackName = "Mac / Desktop"
            }
            record = ClientDeviceRecord(
                deviceId: safeId,
                deviceName: trimmedName.isEmpty ? fallbackName : trimmedName,
                deviceType: normalizedType,
                isAuthorized: hasValidInvite,
                lockScreenControls: defaultLock,
                firstSeenAt: now,
                lastSeenAt: now,
                lastIPAddress: remoteIP
            )
            devicesById[safeId] = record
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

    // MARK: - Share Access & QR Code Generation

    @discardableResult
    public func createInviteToken(ttlSeconds: TimeInterval = 86400) -> String {
        let now = Date().timeIntervalSince1970
        lock.lock()
        defer { lock.unlock() }

        // Prune expired tokens
        inviteTokens = inviteTokens.filter { $0.value > now }

        if let current = activeShareToken, activeShareTokenExpiry > now + 600, inviteTokens[current] != nil {
            return current
        }

        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16).description
        let expiry = now + ttlSeconds
        inviteTokens[token] = expiry
        activeShareToken = token
        activeShareTokenExpiry = expiry
        return token
    }

    public func validateInviteToken(_ token: String?) -> Bool {
        guard let raw = token?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else {
            return false
        }
        let now = Date().timeIntervalSince1970
        lock.lock()
        defer { lock.unlock() }
        guard let expiry = inviteTokens[raw], expiry > now else {
            return false
        }
        return true
    }

    public func generateQRCodeDataURL(for string: String) -> String? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return "data:image/png;base64," + pngData.base64EncodedString()
    }

    public func generateShareAccessPayload() -> [String: Any] {
        let token = createInviteToken()
        let lanIP = WebSocketServer.shared.getLANIPAddresses().first ?? "127.0.0.1"
        let port = WebSocketServer.shared.port
        let baseURL = "http://\(lanIP):\(port)"
        let shareURL = "\(baseURL)/?invite=\(token)"
        let qrDataURL = generateQRCodeDataURL(for: shareURL) ?? ""
        return [
            "share_url": shareURL,
            "base_url": baseURL,
            "invite_token": token,
            "qr_data_url": qrDataURL,
            "lan_ip": lanIP,
            "port": Int(port)
        ]
    }

    public func unregisterConnection(connectionId: UUID) {
        lock.lock()
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

    // MARK: - Queries

    public func isConnectionAuthorized(connectionId: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        // If this connection registered as a PWA client device (via Cookie or register_device),
        // enforce its per-device authorization state.
        // Headless API / Node.js / automation WebSocket connections (no PWA deviceId) remain allowed.
        guard let devId = connectionToDeviceId[connectionId] else {
            return true
        }
        return devicesById[devId]?.isAuthorized ?? false
    }

    public func getUnauthorizedConnectionIds() -> Set<UUID> {
        lock.lock()
        defer { lock.unlock() }
        var result = Set<UUID>()
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

        // Sort: Pending first, then Online Authorized, then Offline Authorized by lastSeenAt desc
        return all.sorted { a, b in
            if a.isAuthorized != b.isAuthorized {
                return !a.isAuthorized // Pending (false) comes first
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

    // MARK: - Mutations (Mac Settings & Client Sync)

    public func setAuthorized(deviceId: String, authorized: Bool) {
        let key = deviceId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        lock.lock()
        guard var record = devicesById[key] else {
            lock.unlock()
            return
        }
        record.isAuthorized = authorized
        record.lastSeenAt = Date().timeIntervalSince1970
        devicesById[key] = record
        saveToDiskLocked()
        lock.unlock()

        NSLog("[ClientDeviceManager] 🔐 Device %@ (%@) authorization set to: %@", record.deviceName, record.shortId, authorized ? "AUTHORIZED" : "REVOKED")
        WebSocketServer.shared.pushDeviceAuthStatus(for: record, newlyAuthorized: authorized)
        notifyObservers()
    }

    public func setLockScreenControls(deviceId: String, enabled: Bool) {
        let key = deviceId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        lock.lock()
        guard var record = devicesById[key] else {
            lock.unlock()
            return
        }
        record.lockScreenControls = enabled
        record.lastSeenAt = Date().timeIntervalSince1970
        devicesById[key] = record
        saveToDiskLocked()
        lock.unlock()

        NSLog("[ClientDeviceManager] 🔒 Device %@ (%@) Lock Screen controls set to: %@", record.deviceName, record.shortId, enabled ? "ON" : "OFF")
        WebSocketServer.shared.pushDeviceAuthStatus(for: record, newlyAuthorized: false)
        notifyObservers()
    }

    public func updateDeviceName(deviceId: String, name: String) {
        let key = deviceId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        lock.lock()
        guard var record = devicesById[key] else {
            lock.unlock()
            return
        }
        record.deviceName = trimmed
        devicesById[key] = record
        saveToDiskLocked()
        lock.unlock()

        WebSocketServer.shared.pushDeviceAuthStatus(for: record, newlyAuthorized: false)
        notifyObservers()
    }

    public func removeDevice(deviceId: String) {
        let key = deviceId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        lock.lock()
        let removed = devicesById.removeValue(forKey: key)
        saveToDiskLocked()
        lock.unlock()

        if var rec = removed {
            rec.isAuthorized = false
            NSLog("[ClientDeviceManager] 🗑 Removed device %@ (%@)", rec.deviceName, rec.shortId)
            WebSocketServer.shared.pushDeviceRemoved(for: rec)
            notifyObservers()
        }
    }
}
