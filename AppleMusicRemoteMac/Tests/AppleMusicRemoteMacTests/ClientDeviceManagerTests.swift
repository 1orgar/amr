//
//  ClientDeviceManagerTests.swift
//  AppleMusicRemoteMacTests
//
//  Unit tests for ClientDeviceManager (PWA Client Device Auth & Per-Device Lock Screen Controls).
//

import XCTest
@testable import AppleMusicRemoteMac

final class ClientDeviceManagerTests: XCTestCase {

    func testDefaultLockScreenControlsByDeviceType() {
        XCTAssertTrue(ClientDeviceManager.defaultLockScreenControls(for: "mobile"))
        XCTAssertTrue(ClientDeviceManager.defaultLockScreenControls(for: "iphone"))
        XCTAssertFalse(ClientDeviceManager.defaultLockScreenControls(for: "tablet"))
        XCTAssertFalse(ClientDeviceManager.defaultLockScreenControls(for: "ipad"))
        XCTAssertFalse(ClientDeviceManager.defaultLockScreenControls(for: "tv"))
        XCTAssertFalse(ClientDeviceManager.defaultLockScreenControls(for: "desktop"))
    }

    func testDeviceRegistrationAuthorizationAndPerDeviceSettings() {
        let manager = ClientDeviceManager.shared
        let connId = UUID()
        let testDeviceId = "test-device-\(UUID().uuidString.lowercased())"

        defer {
            manager.unregisterConnection(connectionId: connId)
            manager.removeDevice(deviceId: testDeviceId)
        }

        // 1. Register new mobile device -> should start unauthorized with lockScreenControls = true
        let record = manager.registerConnection(
            connectionId: connId,
            deviceId: testDeviceId,
            deviceName: "iPhone 16 Pro Test",
            deviceType: "mobile",
            preferredLockScreen: nil,
            remoteIP: "192.168.1.77"
        )

        XCTAssertEqual(record.deviceId, testDeviceId)
        XCTAssertEqual(record.deviceName, "iPhone 16 Pro Test")
        XCTAssertEqual(record.deviceType, "mobile")
        XCTAssertFalse(record.isAuthorized)
        XCTAssertTrue(record.lockScreenControls)
        XCTAssertFalse(manager.isConnectionAuthorized(connectionId: connId))
        XCTAssertTrue(manager.getUnauthorizedConnectionIds().contains(connId))
        XCTAssertTrue(manager.isDeviceOnline(deviceId: testDeviceId))

        // 2. Authorize device
        manager.setAuthorized(deviceId: testDeviceId, authorized: true)
        XCTAssertTrue(manager.isConnectionAuthorized(connectionId: connId))
        XCTAssertFalse(manager.getUnauthorizedConnectionIds().contains(connId))
        XCTAssertEqual(manager.getDevice(deviceId: testDeviceId)?.isAuthorized, true)

        // 3. Toggle per-device Lock Screen controls
        manager.setLockScreenControls(deviceId: testDeviceId, enabled: false)
        XCTAssertEqual(manager.getDevice(deviceId: testDeviceId)?.lockScreenControls, false)

        // 4. Rename device
        manager.updateDeviceName(deviceId: testDeviceId, name: "iPhone Гостиная")
        XCTAssertEqual(manager.getDevice(deviceId: testDeviceId)?.deviceName, "iPhone Гостиная")
    }

    func testHeadlessAPIConnectionRemainsAuthorizedWithoutDeviceId() {
        let manager = ClientDeviceManager.shared
        let headlessConnId = UUID()
        // A connection that never registered a PWA device UID (e.g. Node.js / Home Assistant script)
        // must remain authorized so search_and_play and transport APIs continue working seamlessly.
        XCTAssertTrue(manager.isConnectionAuthorized(connectionId: headlessConnId))
        XCTAssertFalse(manager.getUnauthorizedConnectionIds().contains(headlessConnId))
    }

    func testShareAccessInviteTokenAndQRCodeAutoAuthorization() {
        let manager = ClientDeviceManager.shared
        let payload = manager.generateShareAccessPayload()
        let token = payload["invite_token"] as? String ?? ""
        let qrDataUrl = payload["qr_data_url"] as? String ?? ""
        let shareUrl = payload["share_url"] as? String ?? ""

        XCTAssertFalse(token.isEmpty)
        XCTAssertTrue(manager.validateInviteToken(token))
        XCTAssertTrue(qrDataUrl.hasPrefix("data:image/png;base64,"))
        XCTAssertTrue(shareUrl.contains("?invite=\(token)"))

        let connId = UUID()
        let invitedDeviceId = "test-invited-\(UUID().uuidString.lowercased())"
        defer {
            manager.unregisterConnection(connectionId: connId)
            manager.removeDevice(deviceId: invitedDeviceId)
        }

        let record = manager.registerConnection(
            connectionId: connId,
            deviceId: invitedDeviceId,
            deviceName: "Invited iPad Pro",
            deviceType: "tablet",
            preferredLockScreen: nil,
            remoteIP: "192.168.1.99",
            inviteToken: token
        )
        XCTAssertTrue(record.isAuthorized)
        XCTAssertTrue(manager.isConnectionAuthorized(connectionId: connId))
    }

    func testPerDeviceDACAndDSPPresetPermissions() {
        let manager = ClientDeviceManager.shared
        let connId = UUID()
        let headlessConnId = UUID()
        let testDeviceId = "test-perms-\(UUID().uuidString.lowercased())"

        defer {
            manager.unregisterConnection(connectionId: connId)
            manager.removeDevice(deviceId: testDeviceId)
        }

        // Unbound headless connections remain allowed
        XCTAssertTrue(manager.canConnectionSelectDAC(connectionId: headlessConnId))
        XCTAssertTrue(manager.canConnectionSelectDSPPreset(connectionId: headlessConnId))

        let initial = manager.registerConnection(
            connectionId: connId,
            deviceId: testDeviceId,
            deviceName: "iPad Гостевой",
            deviceType: "tablet",
            preferredLockScreen: false,
            remoteIP: "192.168.1.120"
        )
        XCTAssertTrue(initial.allowDACSelection)
        XCTAssertTrue(initial.allowDSPPresetSelection)
        XCTAssertEqual(initial.dictionary["allow_dac_selection"] as? Bool, true)
        XCTAssertEqual(initial.dictionary["allow_dsp_preset_selection"] as? Bool, true)

        // While pending authorization, neither DAC nor DSP mutations are permitted
        XCTAssertFalse(manager.canConnectionSelectDAC(connectionId: connId))
        XCTAssertFalse(manager.canConnectionSelectDSPPreset(connectionId: connId))

        // Authorize device -> both allowed by default
        manager.setAuthorized(deviceId: testDeviceId, authorized: true)
        XCTAssertTrue(manager.canConnectionSelectDAC(connectionId: connId))
        XCTAssertTrue(manager.canConnectionSelectDSPPreset(connectionId: connId))

        // Disable DAC selection only
        manager.setAllowDACSelection(deviceId: testDeviceId, enabled: false)
        XCTAssertFalse(manager.canConnectionSelectDAC(connectionId: connId))
        XCTAssertTrue(manager.canConnectionSelectDSPPreset(connectionId: connId))
        XCTAssertEqual(manager.getDevice(deviceId: testDeviceId)?.dictionary["allow_dac_selection"] as? Bool, false)

        // Disable DSP preset selection as well
        manager.setAllowDSPPresetSelection(deviceId: testDeviceId, enabled: false)
        XCTAssertFalse(manager.canConnectionSelectDAC(connectionId: connId))
        XCTAssertFalse(manager.canConnectionSelectDSPPreset(connectionId: connId))
        XCTAssertEqual(manager.getDevice(deviceId: testDeviceId)?.dictionary["allow_dsp_preset_selection"] as? Bool, false)

        // Re-enable DAC selection
        manager.setAllowDACSelection(deviceId: testDeviceId, enabled: true)
        XCTAssertTrue(manager.canConnectionSelectDAC(connectionId: connId))
        XCTAssertFalse(manager.canConnectionSelectDSPPreset(connectionId: connId))
    }

    func testLegacyClientDeviceRecordJSONDecodesWithPermissionsEnabledByDefault() throws {
        let legacyJSON = """
        {
          "deviceId": "legacy-uid-1234",
          "shortId": "1234",
          "deviceName": "Legacy iPhone",
          "deviceType": "mobile",
          "isAuthorized": true,
          "lockScreenControls": true,
          "lastSeenTimestamp": 1730000000,
          "lastIPAddress": "192.168.1.50"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ClientDeviceRecord.self, from: legacyJSON)
        XCTAssertEqual(decoded.deviceId, "legacy-uid-1234")
        XCTAssertTrue(decoded.isAuthorized)
        XCTAssertTrue(decoded.allowDACSelection)
        XCTAssertTrue(decoded.allowDSPPresetSelection)
    }
}
