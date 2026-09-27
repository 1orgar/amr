import XCTest
@testable import AppleMusicRemoteMac

final class MusicKitTokenTests: XCTestCase {

    func testDeveloperTokenGeneration() {
        let token = MusicKitManager.shared.getDeveloperToken()
        XCTAssertNotNil(token, "Developer token should be generated successfully")

        guard let jwt = token else { return }
        let parts = jwt.components(separatedBy: ".")
        XCTAssertEqual(parts.count, 3, "JWT must consist of header.payload.signature")

        // Validate header
        var headerB64 = parts[0].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while headerB64.count % 4 != 0 { headerB64.append("=") }
        guard let headerData = Data(base64Encoded: headerB64),
              let headerJson = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] else {
            XCTFail("Failed to decode JWT header")
            return
        }

        XCTAssertEqual(headerJson["alg"] as? String, "ES256")
        XCTAssertEqual(headerJson["kid"] as? String, "MJHWRCSZHH")

        // Validate payload
        var payloadB64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payloadB64.count % 4 != 0 { payloadB64.append("=") }
        guard let payloadData = Data(base64Encoded: payloadB64),
              let payloadJson = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            XCTFail("Failed to decode JWT payload")
            return
        }

        XCTAssertEqual(payloadJson["iss"] as? String, "886CSW93R8")
        XCTAssertNotNil(payloadJson["exp"])
        XCTAssertNotNil(payloadJson["iat"])
    }
}
