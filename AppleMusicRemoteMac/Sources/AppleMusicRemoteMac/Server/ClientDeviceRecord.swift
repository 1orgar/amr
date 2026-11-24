//
//  ClientDeviceRecord.swift
//  AppleMusicRemoteMac
//
//  Persistent model for registered PWA client devices, per-device permissions,
//  and cryptographic anti-spoofing device secrets.
//

import Foundation
import Security

public struct ClientDeviceRecord: Codable, Sendable, Equatable {
    public let deviceId: String
    public var deviceName: String
    public var deviceType: String // "mobile", "tablet", "tv", "desktop"
    public var isAuthorized: Bool
    public var lockScreenControls: Bool
    public var allowDACSelection: Bool
    public var allowDSPPresetSelection: Bool
    public var allowRoomMeasurement: Bool
    public var allowLateNightMode: Bool
    public var allowLibraryModification: Bool
    public var deviceSecret: String
    public var hasConfirmedSecret: Bool
    public var revokedAt: TimeInterval?
    public var firstSeenAt: TimeInterval
    public var lastSeenAt: TimeInterval
    public var lastIPAddress: String
    internal var decodedInlineLegacySecret: String? = nil

    private enum CodingKeys: String, CodingKey {
        case deviceId
        case deviceName
        case deviceType
        case isAuthorized
        case lockScreenControls
        case allowDACSelection
        case allowDSPPresetSelection
        case allowRoomMeasurement
        case allowLateNightMode
        case allowLibraryModification
        case deviceSecret
        case hasConfirmedSecret
        case revokedAt
        case firstSeenAt
        case lastSeenAt
        case lastIPAddress
    }

    public init(
        deviceId: String,
        deviceName: String,
        deviceType: String,
        isAuthorized: Bool,
        lockScreenControls: Bool,
        allowDACSelection: Bool = true,
        allowDSPPresetSelection: Bool = true,
        allowRoomMeasurement: Bool = true,
        allowLateNightMode: Bool = true,
        allowLibraryModification: Bool = true,
        deviceSecret: String? = nil,
        hasConfirmedSecret: Bool = false,
        revokedAt: TimeInterval? = nil,
        firstSeenAt: TimeInterval,
        lastSeenAt: TimeInterval,
        lastIPAddress: String
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.isAuthorized = isAuthorized
        self.lockScreenControls = lockScreenControls
        self.allowDACSelection = allowDACSelection
        self.allowDSPPresetSelection = allowDSPPresetSelection
        self.allowRoomMeasurement = allowRoomMeasurement
        self.allowLateNightMode = allowLateNightMode
        self.allowLibraryModification = allowLibraryModification
        if let provided = deviceSecret, provided.count >= 32 {
            self.deviceSecret = provided
        } else {
            self.deviceSecret = Self.generateRandomHexSecret(byteCount: 32)
        }
        self.hasConfirmedSecret = hasConfirmedSecret
        self.revokedAt = revokedAt
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.lastIPAddress = lastIPAddress
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.deviceId = try container.decode(String.self, forKey: .deviceId)
        self.deviceName = try container.decode(String.self, forKey: .deviceName)
        self.deviceType = try container.decode(String.self, forKey: .deviceType)
        self.isAuthorized = try container.decode(Bool.self, forKey: .isAuthorized)
        self.lockScreenControls = try container.decodeIfPresent(Bool.self, forKey: .lockScreenControls)
            ?? ClientDeviceManager.defaultLockScreenControls(for: self.deviceType)
        self.allowDACSelection = try container.decodeIfPresent(Bool.self, forKey: .allowDACSelection) ?? true
        self.allowDSPPresetSelection = try container.decodeIfPresent(Bool.self, forKey: .allowDSPPresetSelection) ?? true
        self.allowRoomMeasurement = try container.decodeIfPresent(Bool.self, forKey: .allowRoomMeasurement) ?? true
        self.allowLateNightMode = try container.decodeIfPresent(Bool.self, forKey: .allowLateNightMode) ?? true
        self.allowLibraryModification = try container.decodeIfPresent(Bool.self, forKey: .allowLibraryModification) ?? true
        if let decodedSecret = try container.decodeIfPresent(String.self, forKey: .deviceSecret),
           decodedSecret.count >= 32 {
            self.deviceSecret = decodedSecret
            self.decodedInlineLegacySecret = decodedSecret
        } else {
            self.deviceSecret = Self.generateRandomHexSecret(byteCount: 32)
            self.decodedInlineLegacySecret = nil
        }
        self.hasConfirmedSecret = try container.decodeIfPresent(Bool.self, forKey: .hasConfirmedSecret) ?? false
        self.revokedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .revokedAt)
        self.firstSeenAt = try container.decodeIfPresent(TimeInterval.self, forKey: .firstSeenAt) ?? 0
        self.lastSeenAt = try container.decodeIfPresent(TimeInterval.self, forKey: .lastSeenAt) ?? 0
        self.lastIPAddress = try container.decodeIfPresent(String.self, forKey: .lastIPAddress) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(deviceName, forKey: .deviceName)
        try container.encode(deviceType, forKey: .deviceType)
        try container.encode(isAuthorized, forKey: .isAuthorized)
        try container.encode(lockScreenControls, forKey: .lockScreenControls)
        try container.encode(allowDACSelection, forKey: .allowDACSelection)
        try container.encode(allowDSPPresetSelection, forKey: .allowDSPPresetSelection)
        try container.encode(allowRoomMeasurement, forKey: .allowRoomMeasurement)
        try container.encode(allowLateNightMode, forKey: .allowLateNightMode)
        try container.encode(allowLibraryModification, forKey: .allowLibraryModification)
        // Intentionally omit `deviceSecret` from UserDefaults JSON — stored exclusively in Keychain (`AppSecretStore`)!
        try container.encode(hasConfirmedSecret, forKey: .hasConfirmedSecret)
        try container.encodeIfPresent(revokedAt, forKey: .revokedAt)
        try container.encode(firstSeenAt, forKey: .firstSeenAt)
        try container.encode(lastSeenAt, forKey: .lastSeenAt)
        try container.encode(lastIPAddress, forKey: .lastIPAddress)
    }

    public static func == (lhs: ClientDeviceRecord, rhs: ClientDeviceRecord) -> Bool {
        lhs.deviceId == rhs.deviceId
            && lhs.deviceName == rhs.deviceName
            && lhs.deviceType == rhs.deviceType
            && lhs.isAuthorized == rhs.isAuthorized
            && lhs.lockScreenControls == rhs.lockScreenControls
            && lhs.allowDACSelection == rhs.allowDACSelection
            && lhs.allowDSPPresetSelection == rhs.allowDSPPresetSelection
            && lhs.allowRoomMeasurement == rhs.allowRoomMeasurement
            && lhs.allowLateNightMode == rhs.allowLateNightMode
            && lhs.allowLibraryModification == rhs.allowLibraryModification
            && lhs.deviceSecret == rhs.deviceSecret
            && lhs.hasConfirmedSecret == rhs.hasConfirmedSecret
            && lhs.revokedAt == rhs.revokedAt
            && lhs.firstSeenAt == rhs.firstSeenAt
            && lhs.lastSeenAt == rhs.lastSeenAt
            && lhs.lastIPAddress == rhs.lastIPAddress
    }

    public var shortId: String {
        let clean = deviceId.replacingOccurrences(of: "-", with: "").uppercased()
        if clean.count >= 8 {
            let prefix = clean.prefix(4)
            let suffix = clean.dropFirst(4).prefix(4)
            return "\(prefix)-\(suffix)"
        }
        return clean
    }

    /// Public metadata dictionary safe for device lists & broadcasts (NEVER includes `device_secret`).
    public var dictionary: [String: Any] {
        return [
            "device_id": deviceId,
            "short_id": shortId,
            "device_name": deviceName,
            "device_type": deviceType,
            "authorized": isAuthorized,
            "lock_screen_controls": lockScreenControls,
            "allow_dac_selection": allowDACSelection,
            "allow_dsp_preset_selection": allowDSPPresetSelection,
            "allow_room_measurement": allowRoomMeasurement,
            "allow_late_night_mode": allowLateNightMode,
            "allow_library_modification": allowLibraryModification,
            "first_seen_at": firstSeenAt,
            "last_seen_at": lastSeenAt,
            "last_ip": lastIPAddress,
            "git_commit": ClientDeviceManager.shared.gitCommitShort,
            "git_commit_date": ClientDeviceManager.shared.gitCommitDate
        ]
    }

    /// Per-connection dictionary sent ONLY directly to the verified device's own socket.
    public var dictionaryWithSecret: [String: Any] {
        var dict = dictionary
        if !deviceSecret.isEmpty {
            dict["device_secret"] = deviceSecret
        }
        return dict
    }

    public static func generateRandomHexSecret(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: max(16, byteCount))
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            let fallback = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
                + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            return String(fallback.prefix(max(32, byteCount * 2)))
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    public static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let lhs = Array(a.utf8)
        let rhs = Array(b.utf8)
        guard !lhs.isEmpty, lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<lhs.count {
            diff |= lhs[i] ^ rhs[i]
        }
        return diff == 0
    }
}
