//
//  ClientDeviceManager+InviteAndPermissions.swift
//  AppleMusicRemoteMac
//
//  Short-lived QR invite tokens, revocation purge, HTTP/WS capability checks,
//  and per-device permission mutations.
//

import AppKit
import CoreImage
import Foundation

extension ClientDeviceManager {
    // MARK: - Share Access & Short-Lived QR Code Generation (Default 900s = 15 min)

    @discardableResult
    public func createInviteToken(ttlSeconds: TimeInterval = 900) -> String {
        let now = Date().timeIntervalSince1970
        let effectiveTTL = max(1, ttlSeconds)
        lock.lock()
        defer { lock.unlock() }

        inviteTokens = inviteTokens.filter { $0.value.expiresAt > now }

        let reuseThreshold = min(effectiveTTL * 0.5, 300)
        if effectiveTTL >= 300,
           let current = activeShareToken,
           activeShareTokenExpiry > now + reuseThreshold,
           inviteTokens[current] != nil {
            return current
        }

        let token = ClientDeviceRecord.generateRandomHexSecret(byteCount: 16)
        let expiry = now + effectiveTTL
        inviteTokens[token] = InviteTokenEntry(createdAt: now, expiresAt: expiry)
        activeShareToken = token
        activeShareTokenExpiry = expiry
        return token
    }

    public func validateInviteToken(_ token: String?, afterTimestamp minCreatedAt: TimeInterval? = nil) -> Bool {
        let now = Date().timeIntervalSince1970
        lock.lock()
        defer { lock.unlock() }
        return validateInviteTokenLocked(token, afterTimestamp: minCreatedAt, now: now)
    }

    internal func validateInviteTokenLocked(_ token: String?, afterTimestamp minCreatedAt: TimeInterval?, now: TimeInterval) -> Bool {
        guard let raw = token?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else {
            return false
        }
        guard let entry = inviteTokens[raw], entry.expiresAt > now else {
            return false
        }
        if let minTs = minCreatedAt, entry.createdAt <= minTs {
            return false
        }
        return true
    }

    internal func purgeInviteTokensLocked() {
        inviteTokens.removeAll()
        activeShareToken = nil
        activeShareTokenExpiry = 0
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

    // MARK: - Authorization & Per-Device Capabilities

    public func isConnectionAuthorized(connectionId: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if pendingBrowserConnections.contains(connectionId) {
            return false
        }
        guard let devId = connectionToDeviceId[connectionId] else {
            return true
        }
        return devicesById[devId]?.isAuthorized ?? false
    }

    public func isDeviceAuthorized(deviceId: String?) -> Bool {
        guard let raw = deviceId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              raw.count >= 8 else {
            return false
        }
        lock.lock()
        defer { lock.unlock() }
        return devicesById[raw]?.isAuthorized == true
    }

    /// Validates an HTTP request's `deviceId` along with optional `X-AMR-Device-Secret` / `Cookie: amr_device_secret`.
    public func isHTTPDeviceAuthorized(deviceId: String?, providedSecret: String?, remoteIP: String) -> Bool {
        guard let raw = deviceId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              raw.count >= 8 else {
            return false
        }
        let cleanSecret = providedSecret?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanIP = remoteIP.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        lock.lock()
        defer { lock.unlock() }
        guard var record = devicesById[raw], record.isAuthorized else {
            return false
        }

        if !cleanSecret.isEmpty {
            guard ClientDeviceRecord.constantTimeEqual(cleanSecret, record.deviceSecret) else {
                return false
            }
            if !record.hasConfirmedSecret {
                record.hasConfirmedSecret = true
                devicesById[raw] = record
                saveToDiskLocked()
            }
            return true
        }

        if record.hasConfirmedSecret {
            return false
        }

        if !record.lastIPAddress.isEmpty && !cleanIP.isEmpty {
            return record.lastIPAddress.lowercased() == cleanIP
        }
        return true
    }

    public func canConnectionSelectDAC(connectionId: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if pendingBrowserConnections.contains(connectionId) {
            return false
        }
        guard let devId = connectionToDeviceId[connectionId] else {
            return true
        }
        guard let record = devicesById[devId], record.isAuthorized else {
            return false
        }
        return record.allowDACSelection
    }

    public func canConnectionSelectDSPPreset(connectionId: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if pendingBrowserConnections.contains(connectionId) {
            return false
        }
        guard let devId = connectionToDeviceId[connectionId] else {
            return true
        }
        guard let record = devicesById[devId], record.isAuthorized else {
            return false
        }
        return record.allowDSPPresetSelection
    }

    public func canConnectionMeasureRoom(connectionId: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if pendingBrowserConnections.contains(connectionId) {
            return false
        }
        guard let devId = connectionToDeviceId[connectionId] else {
            return true
        }
        guard let record = devicesById[devId], record.isAuthorized else {
            return false
        }
        return record.allowRoomMeasurement
    }

    public func canDeviceMeasureRoom(deviceId: String?) -> Bool {
        guard let raw = deviceId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              raw.count >= 8 else {
            return false
        }
        lock.lock()
        defer { lock.unlock() }
        guard let record = devicesById[raw], record.isAuthorized else {
            return false
        }
        return record.allowRoomMeasurement
    }

    public func canConnectionControlLateNight(connectionId: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if pendingBrowserConnections.contains(connectionId) {
            return false
        }
        guard let devId = connectionToDeviceId[connectionId] else {
            return true
        }
        guard let record = devicesById[devId], record.isAuthorized else {
            return false
        }
        return record.allowLateNightMode
    }

    public func canConnectionModifyLibrary(connectionId: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if pendingBrowserConnections.contains(connectionId) {
            return false
        }
        guard let devId = connectionToDeviceId[connectionId] else {
            return true
        }
        guard let record = devicesById[devId], record.isAuthorized else {
            return false
        }
        return record.allowLibraryModification
    }

    public func canDeviceModifyLibrary(deviceId: String?) -> Bool {
        guard let raw = deviceId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              raw.count >= 8 else {
            return false
        }
        lock.lock()
        defer { lock.unlock() }
        guard let record = devicesById[raw], record.isAuthorized else {
            return false
        }
        return record.allowLibraryModification
    }

    // MARK: - Mutations (Mac Settings & Client Sync)

    public func setAuthorized(deviceId: String, authorized: Bool) {
        let key = deviceId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let now = Date().timeIntervalSince1970
        lock.lock()
        guard var record = devicesById[key] else {
            lock.unlock()
            return
        }
        record.isAuthorized = authorized
        record.lastSeenAt = now
        if !authorized {
            purgeInviteTokensLocked()
            record.revokedAt = now
            revokedTimestampsByDeviceId[key] = now
        } else {
            record.revokedAt = nil
            revokedTimestampsByDeviceId.removeValue(forKey: key)
        }
        devicesById[key] = record
        saveToDiskLocked()
        lock.unlock()

        NSLog("[ClientDeviceManager] 🔐 Device %@ (%@) authorization set to: %@", record.deviceName, record.shortId, authorized ? "AUTHORIZED" : "REVOKED")
        WebSocketServer.shared.pushDeviceAuthStatus(for: record, newlyAuthorized: authorized)
        notifyObservers()
    }

    public func setLockScreenControls(deviceId: String, enabled: Bool) {
        updatePermission(deviceId: deviceId, logLabel: "Lock Screen controls") { $0.lockScreenControls = enabled }
    }

    public func setAllowDACSelection(deviceId: String, enabled: Bool) {
        updatePermission(deviceId: deviceId, logLabel: "DAC selection access") { $0.allowDACSelection = enabled }
    }

    public func setAllowDSPPresetSelection(deviceId: String, enabled: Bool) {
        updatePermission(deviceId: deviceId, logLabel: "DSP preset selection access") { $0.allowDSPPresetSelection = enabled }
    }

    public func setAllowRoomMeasurement(deviceId: String, enabled: Bool) {
        updatePermission(deviceId: deviceId, logLabel: "Room Acoustic Measurement access") { $0.allowRoomMeasurement = enabled }
    }

    public func setAllowLateNightMode(deviceId: String, enabled: Bool) {
        updatePermission(deviceId: deviceId, logLabel: "Late-Night DRC access") { $0.allowLateNightMode = enabled }
    }

    public func setAllowLibraryModification(deviceId: String, enabled: Bool) {
        updatePermission(deviceId: deviceId, logLabel: "Library Modification access") { $0.allowLibraryModification = enabled }
    }

    private func updatePermission(deviceId: String, logLabel: String, mutate: (inout ClientDeviceRecord) -> Void) {
        let key = deviceId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        lock.lock()
        guard var record = devicesById[key] else {
            lock.unlock()
            return
        }
        mutate(&record)
        record.lastSeenAt = Date().timeIntervalSince1970
        devicesById[key] = record
        saveToDiskLocked()
        lock.unlock()

        NSLog("[ClientDeviceManager] 🎛 Device %@ (%@) %@ updated", record.deviceName, record.shortId, logLabel)
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
        let now = Date().timeIntervalSince1970
        lock.lock()
        purgeInviteTokensLocked()
        revokedTimestampsByDeviceId[key] = now
        let boundConnIds = connectionToDeviceId.compactMap { (connId, devId) -> UUID? in
            devId == key ? connId : nil
        }
        for connId in boundConnIds {
            connectionToDeviceId.removeValue(forKey: connId)
            pendingBrowserConnections.insert(connId)
        }
        let removed = devicesById.removeValue(forKey: key)
        saveToDiskLocked()
        lock.unlock()

        if var rec = removed {
            rec.isAuthorized = false
            NSLog("[ClientDeviceManager] 🗑 Removed device %@ (%@)", rec.deviceName, rec.shortId)
            WebSocketServer.shared.pushDeviceRemoved(for: rec, connectionIds: boundConnIds)
            notifyObservers()
        }
    }
}
