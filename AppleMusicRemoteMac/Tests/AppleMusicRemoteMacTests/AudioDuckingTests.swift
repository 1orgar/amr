//
//  AudioDuckingTests.swift
//  AppleMusicRemoteMacTests
//

import XCTest
@testable import AppleMusicRemoteMac

final class AudioDuckingTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PlaybackStateStore.shared.isVolumeLockedTo100 = false
    }

    override func tearDown() {
        PlaybackStateStore.shared.isVolumeLockedTo100 = true
        AudioDuckingController.shared.deactivate()
        super.tearDown()
    }

    func testAudioDuckingActivationAndDeactivation() {
        let controller = AudioDuckingController.shared
        _ = MusicBridge.shared.setVolume(50)

        // Ensure initially not ducked
        _ = controller.deactivate()
        XCTAssertFalse(controller.isDucked)

        // 1. Activate default 80% reduction
        let (ok, duckedVol, origVol) = controller.activate(reductionPercent: 80.0)
        XCTAssertTrue(ok)
        XCTAssertEqual(origVol, 50)
        XCTAssertEqual(duckedVol, 10, "50 reduced by 80% should equal 10")
        XCTAssertTrue(controller.isDucked)
        XCTAssertEqual(controller.originalVolume, 50)

        // 2. Calling activate while already ducked must NOT reduce from ducked volume
        let (ok2, duckedVol2, origVol2) = controller.activate(reductionPercent: 80.0)
        XCTAssertTrue(ok2)
        XCTAssertEqual(origVol2, 50, "Original volume must be preserved across multiple calls")
        XCTAssertEqual(duckedVol2, 10)

        // 3. Deactivate ducking
        let (deactOk, restoredVol) = controller.deactivate()
        XCTAssertTrue(deactOk)
        XCTAssertEqual(restoredVol, 50, "Volume must be restored back to original 50")
        XCTAssertFalse(controller.isDucked)
        XCTAssertNil(controller.originalVolume)
    }

    func testAudioDuckingCustomReductionPercent() {
        let controller = AudioDuckingController.shared
        _ = MusicBridge.shared.setVolume(80)

        // 75% reduction on 80 -> 25% remains -> 20
        let (ok, duckedVol, origVol) = controller.activate(reductionPercent: 75.0)
        XCTAssertTrue(ok)
        XCTAssertEqual(origVol, 80)
        XCTAssertEqual(duckedVol, 20)

        let (deactOk, restoredVol) = controller.deactivate()
        XCTAssertTrue(deactOk)
        XCTAssertEqual(restoredVol, 80)
    }

    func testAudioDuckingAutoTimeout() {
        let controller = AudioDuckingController.shared
        _ = MusicBridge.shared.setVolume(60)

        let exp = expectation(description: "Auto-unduck timer fires")
        controller.activate(reductionPercent: 80.0, timeout: 0.2)
        XCTAssertTrue(controller.isDucked)

        DispatchQueue.global().async {
            let start = Date()
            while Date().timeIntervalSince(start) < 2.0 {
                if !controller.isDucked {
                    exp.fulfill()
                    return
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
            XCTFail("Should have auto-unducked after timeout")
            exp.fulfill()
        }

        waitForExpectations(timeout: 3.0)
        XCTAssertFalse(controller.isDucked)
    }

    func testPlayerStatusCodableWithIsDucked() throws {
        let status = PlayerStatus(
            playerState: "playing",
            position: 12.5,
            duration: 200.0,
            volume: 20,
            isDucked: true
        )

        let data = try JSONEncoder().encode(status)
        let jsonStr = String(data: data, encoding: .utf8)!
        XCTAssertTrue(jsonStr.contains("\"is_ducked\":true"))

        let decoded = try JSONDecoder().decode(PlayerStatus.self, from: data)
        XCTAssertTrue(decoded.isDucked)
        XCTAssertEqual(decoded.volume, 20)
    }
}
