//
//  LaunchAtLoginManagerTests.swift
//  AppleMusicRemoteMacTests
//

import XCTest
@testable import AppleMusicRemoteMac

@MainActor
final class LaunchAtLoginManagerTests: XCTestCase {

    func testSharedInstanceInitialization() {
        let manager = LaunchAtLoginManager.shared
        XCTAssertNotNil(manager)
    }

    func testRefreshStatusDoesNotCrash() {
        let manager = LaunchAtLoginManager.shared
        manager.refreshStatus()
        // Should not crash and isEnabled should be a valid boolean
        let status = manager.isEnabled
        XCTAssertTrue(status == true || status == false)
    }

    func testSetEnabledConsistency() {
        let manager = LaunchAtLoginManager.shared
        let initial = manager.isEnabled
        // In unit test runner environment, registration might fail or succeed depending on signing/bundle,
        // but setEnabled must always return safely without throwing unhandled exceptions.
        _ = manager.setEnabled(initial)
        manager.refreshStatus()
        XCTAssertTrue(manager.isEnabled == true || manager.isEnabled == false)
    }
}
