import XCTest
import CryptoKit
@testable import AppleMusicRemoteMac

final class Phase3ParallelAndSecurityTests: XCTestCase {

    func testAppStorageProviderIsolatesXCTestProcessPerPIDSuite() {
        XCTAssertTrue(AppStorageProvider.isRunningUnderXCTest)
        let suiteName = AppStorageProvider.activeSuiteName
        XCTAssertEqual(suiteName, "org.ksholokhov.amr.xctest.\(getpid())")
        XCTAssertFalse(AppStorageProvider.shared === UserDefaults.standard, "XCTest runs must never mutate global UserDefaults.standard")
    }

    func testClientDeviceRecordOmitsPlaintextDeviceSecretAndMigratesLegacyUserDefaultsToSecretStore() throws {
        let suiteName = "org.ksholokhov.amr.migration-test.\(UUID().uuidString)"
        let tempDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            tempDefaults.removePersistentDomain(forName: suiteName)
        }

        let legacyDeviceId = "legacy-sec-\(UUID().uuidString.lowercased())"
        let legacySecret = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        defer {
            ClientDeviceManager.shared.removeDevice(deviceId: legacyDeviceId)
            AppSecretStore.shared.deleteSecret(account: ClientDeviceManager.secretAccount(forDeviceId: legacyDeviceId))
        }

        // Simulate pre-Phase-3 UserDefaults JSON containing plaintext `deviceSecret`
        let legacyArray: [[String: Any]] = [[
            "deviceId": legacyDeviceId,
            "deviceName": "Legacy Living Room iPad",
            "deviceType": "tablet",
            "isAuthorized": true,
            "lockScreenControls": false,
            "deviceSecret": legacySecret,
            "hasConfirmedSecret": true,
            "firstSeenAt": 1_730_000_000.0,
            "lastSeenAt": 1_730_000_100.0,
            "lastIPAddress": "192.168.1.42"
        ]]
        let rawLegacyData = try JSONSerialization.data(withJSONObject: legacyArray)
        tempDefaults.set(rawLegacyData, forKey: ClientDeviceManager.shared.storageKey)

        ClientDeviceManager.shared.loadFromDefaults(tempDefaults)

        // 1. Secret was migrated into AppSecretStore
        let migratedSecret = AppSecretStore.shared.readSecret(account: ClientDeviceManager.secretAccount(forDeviceId: legacyDeviceId))
        XCTAssertEqual(migratedSecret, legacySecret)
        XCTAssertEqual(ClientDeviceManager.shared.getDevice(deviceId: legacyDeviceId)?.deviceSecret, legacySecret)

        // 2. Re-saved UserDefaults JSON no longer contains plaintext `deviceSecret`
        let rewrittenData = try XCTUnwrap(tempDefaults.data(forKey: ClientDeviceManager.shared.storageKey))
        let rewrittenString = try XCTUnwrap(String(data: rewrittenData, encoding: .utf8))
        XCTAssertFalse(rewrittenString.contains(legacySecret), "Re-saved UserDefaults JSON must never contain plaintext deviceSecret")
        XCTAssertFalse(rewrittenString.contains("\"deviceSecret\""))
    }

    func testExpiredPreSignedDeveloperJWTSurfacesClearAccountHealthDiagnostic() async throws {
        defer {
            MusicKitManager.shared.reloadKeyForTesting()
        }

        func b64url(_ dict: [String: Any]) throws -> String {
            let d = try JSONSerialization.data(withJSONObject: dict)
            return d.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }

        let expiredEpoch = Int(Date().timeIntervalSince1970) - 86_400
        let header = try b64url(["alg": "ES256", "kid": "MJHWRCSZHH"])
        let payload = try b64url(["iss": "886CSW93R8", "iat": expiredEpoch - 86_400, "exp": expiredEpoch])
        let fakeExpiredJWT = "\(header).\(payload).deadbeefsignature"

        MusicKitManager.shared.reloadKeyForTesting()
        XCTAssertFalse(MusicKitManager.shared.configurePreSignedDeveloperToken(fakeExpiredJWT))

        if case .expired(let expDate) = MusicKitManager.shared.developerTokenHealthState {
            XCTAssertEqual(expDate.timeIntervalSince1970, Double(expiredEpoch), accuracy: 1.0)
        } else {
            XCTFail("Expected .expired DeveloperTokenHealthState for expired pre-signed JWT")
        }

        let health = await AccountHealthService.shared.checkAccountHealth(forceRefresh: true)
        XCTAssertEqual(health.status, "token_expired")
        XCTAssertTrue(health.isTokenExpired)
        XCTAssertTrue(health.message.contains("MusicKit Developer JWT"))
    }

    func testAES256GCMTokenVaultRoundTripWithoutKeychainAPIs() throws {
        let sampleToken = "eyJhbGciOiJFUzI1NiIsImtpZCI6Ik1KSFdSQ1NaSEgifQ.sample_music_user_token_payload"
        let encrypted = try XCTUnwrap(MusicKitManager.encryptUserTokenForDefaults(sampleToken))
        XCTAssertTrue(encrypted.hasPrefix(MusicKitManager.encryptedUserTokenPrefix))
        XCTAssertFalse(encrypted.contains(sampleToken))

        let decoded = try XCTUnwrap(MusicKitManager.decodeStoredUserTokenFromDefaults(encrypted))
        XCTAssertEqual(decoded.plaintext, sampleToken)
        XCTAssertFalse(decoded.wasPlaintext)
    }
}
