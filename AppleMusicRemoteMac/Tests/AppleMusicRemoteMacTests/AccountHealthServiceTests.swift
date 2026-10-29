//
//  AccountHealthServiceTests.swift
//  AppleMusicRemoteMacTests
//

import XCTest
@testable import AppleMusicRemoteMac

final class AccountHealthServiceTests: XCTestCase {

    func testAccountHealthStatusSerialization() throws {
        let status = AccountHealthStatus(
            status: "synchronized",
            macAppleId: "user@example.com",
            macDsid: "123456789",
            isSubscriptionActive: true,
            macStorefront: "143441",
            macCountryCode: "us",
            webStorefront: "us",
            isTokenValid: true,
            isTokenExpired: false,
            isAccountsMatched: true,
            message: "Accounts matched",
            checkedAt: Date()
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(status)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AccountHealthStatus.self, from: data)

        XCTAssertEqual(decoded.status, "synchronized")
        XCTAssertEqual(decoded.macAppleId, "user@example.com")
        XCTAssertEqual(decoded.macDsid, "123456789")
        XCTAssertTrue(decoded.isSubscriptionActive)
        XCTAssertEqual(decoded.macCountryCode, "us")
        XCTAssertTrue(decoded.isTokenValid)
        XCTAssertTrue(decoded.isAccountsMatched)
    }

    func testGetMacAccountInfoDoesNotCrash() {
        let info = AccountHealthService.shared.getMacAccountInfo()
        XCTAssertNotNil(info)
    }

    func testAccountHealthCheckWhenNoToken() async {
        let originalToken = MusicKitManager.shared.getUserToken()
        defer {
            if let orig = originalToken {
                MusicKitManager.shared.setUserToken(orig)
            } else {
                MusicKitManager.shared.clearUserToken()
            }
        }

        MusicKitManager.shared.clearUserToken()
        let status = await AccountHealthService.shared.checkAccountHealth(forceRefresh: true)
        XCTAssertEqual(status.status, "not_authorized")
        XCTAssertFalse(status.isTokenValid)
        XCTAssertFalse(status.isAccountsMatched)
    }
}
