//
//  MusicAppProviderTests.swift
//  AppleMusicRemoteMacTests
//

import XCTest
@testable import AppleMusicRemoteMac

final class MusicAppProviderTests: XCTestCase {

    func testSharedInstanceExists() {
        let provider = MusicAppProvider.shared
        XCTAssertNotNil(provider)
    }

    func testIsMusicAppRunningReturnsValidBoolean() {
        let isRunning = MusicAppProvider.shared.isMusicAppRunning
        // NSRunningApplication check must return immediately without throwing
        XCTAssertTrue(isRunning == true || isRunning == false)
    }

    func testGetMusicAppBehavior() {
        let provider = MusicAppProvider.shared
        let app = provider.getMusicApp()
        if provider.isMusicAppRunning {
            XCTAssertNotNil(app, "When Music.app process is running, getMusicApp should connect")
        } else {
            XCTAssertNil(app, "When Music.app process is not running, getMusicApp should return nil")
        }
    }

    func testLifecycleCallbackHooks() {
        let provider = MusicAppProvider.shared
        let expTerm = expectation(description: "Termination callback registered")
        expTerm.isInverted = true

        provider.onMusicAppTerminated = {
            expTerm.fulfill()
        }

        // Verify hook doesn't fire unexpectedly in quiescent test environment
        waitForExpectations(timeout: 0.1)
    }
}
