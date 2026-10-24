//
//  CoreAudioDeviceManagerTests.swift
//  AppleMusicRemoteMacTests
//

import XCTest
import CoreAudio
@testable import AppleMusicRemoteMac

final class CoreAudioDeviceManagerTests: XCTestCase {

    func testSharedInstanceInitialization() {
        let manager = CoreAudioDeviceManager.shared
        XCTAssertNotNil(manager)
    }

    func testGetOutputDevicesReturnsValidArray() {
        let manager = CoreAudioDeviceManager.shared
        let devices = manager.getOutputDevices()

        // macOS systems will always have at least 1 audio device (e.g., MacBook speakers, headphones, or virtual)
        XCTAssertFalse(devices.isEmpty, "macOS system should enumerate at least one output device")

        for dev in devices {
            XCTAssertFalse(dev.name.isEmpty, "Device name must not be empty")
            XCTAssertFalse(dev.uid.isEmpty, "Device UID must not be empty")
            XCTAssertTrue(dev.currentSampleRate > 0, "Current sample rate must be positive: \(dev.currentSampleRate)")
            XCTAssertFalse(dev.iconName.isEmpty, "Icon name must be non-empty")
        }
    }

    func testDefaultOutputDeviceDetection() {
        let manager = CoreAudioDeviceManager.shared
        let defaultID = manager.getDefaultOutputDeviceID()
        XCTAssertNotNil(defaultID, "System must report a default output device ID")

        let devices = manager.getOutputDevices()
        let defaultDevices = devices.filter { $0.isDefault }
        XCTAssertEqual(defaultDevices.count, 1, "Exactly one audio output device should be flagged as default")
    }

    func testTransportIconFallback() {
        let manager = CoreAudioDeviceManager.shared
        // For an invalid device ID 0, it should safely return default speaker icon
        let icon = manager.transportIconName(deviceID: 0)
        XCTAssertEqual(icon, "speaker.wave.2.fill")
    }

    func testNearestSupportedSampleRateExactOrFallback() {
        let manager = CoreAudioDeviceManager.shared
        guard let defaultID = manager.getDefaultOutputDeviceID() else { return }

        // Test high-res passthrough / fallback
        let targetRate = 96000.0
        let nearest = manager.nearestSupportedSampleRate(targetRate, deviceID: defaultID)
        XCTAssertNotNil(nearest)
        XCTAssertTrue(nearest! > 0)
    }

    func testSetFormatWithCurrentRateSucceedsImmediately() {
        let manager = CoreAudioDeviceManager.shared
        guard let defaultDevice = manager.getDefaultOutputDevice() else { return }

        // Setting the already-active rate should return true immediately without altering hardware
        let result = manager.setFormat(sampleRate: defaultDevice.currentSampleRate, bitDepth: nil, for: defaultDevice.id)
        XCTAssertTrue(result)
    }
}
