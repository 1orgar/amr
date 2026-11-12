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
}
