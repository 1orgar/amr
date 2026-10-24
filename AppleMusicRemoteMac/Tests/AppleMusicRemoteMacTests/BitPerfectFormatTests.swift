//
//  BitPerfectFormatTests.swift
//  AppleMusicRemoteMacTests
//

import XCTest
@testable import AppleMusicRemoteMac

final class BitPerfectFormatTests: XCTestCase {

    func testStandardSampleRatesDefined() {
        let rates = BitPerfectLogMonitor.standardRates
        XCTAssertTrue(rates.contains(44100.0))
        XCTAssertTrue(rates.contains(48000.0))
        XCTAssertTrue(rates.contains(88200.0))
        XCTAssertTrue(rates.contains(96000.0))
        XCTAssertTrue(rates.contains(176400.0))
        XCTAssertTrue(rates.contains(192000.0))
        XCTAssertTrue(rates.contains(352800.0))
        XCTAssertTrue(rates.contains(384000.0))
        XCTAssertTrue(rates.contains(768000.0))
    }

    func testNormalizeRateExactValues() {
        let monitor = BitPerfectLogMonitor.shared
        XCTAssertEqual(monitor.normalizeRate(44100.0), 44100.0)
        XCTAssertEqual(monitor.normalizeRate(48000.0), 48000.0)
        XCTAssertEqual(monitor.normalizeRate(96000.0), 96000.0)
        XCTAssertEqual(monitor.normalizeRate(192000.0), 192000.0)
    }

    func testNormalizeRateFromKhz() {
        let monitor = BitPerfectLogMonitor.shared
        XCTAssertEqual(monitor.normalizeRate(44.1), 44100.0)
        XCTAssertEqual(monitor.normalizeRate(48.0), 48000.0)
        XCTAssertEqual(monitor.normalizeRate(88.2), 88200.0)
        XCTAssertEqual(monitor.normalizeRate(96.0), 96000.0)
        XCTAssertEqual(monitor.normalizeRate(192.0), 192000.0)
    }

    func testNormalizeRateSnappingWithinThreshold() {
        let monitor = BitPerfectLogMonitor.shared
        // 44090 Hz should snap to 44100 Hz
        XCTAssertEqual(monitor.normalizeRate(44090.0), 44100.0)
        // 48020 Hz should snap to 48000 Hz
        XCTAssertEqual(monitor.normalizeRate(48020.0), 48000.0)
        // 95950 Hz should snap to 96000 Hz
        XCTAssertEqual(monitor.normalizeRate(95950.0), 96000.0)
        // 192100 Hz should snap to 192000 Hz
        XCTAssertEqual(monitor.normalizeRate(192100.0), 192000.0)
    }

    func testNormalizeRateInvalidOrZero() {
        let monitor = BitPerfectLogMonitor.shared
        XCTAssertNil(monitor.normalizeRate(0))
        XCTAssertNil(monitor.normalizeRate(-44100.0))
    }

    func testFormatQualityStringStandardLossless() {
        let monitor = BitPerfectLogMonitor.shared
        let q16 = monitor.formatQualityString(rate: 44100.0, bitDepth: 16)
        XCTAssertEqual(q16, "44.1 кГц (Lossless 16-бит)")

        let q24 = monitor.formatQualityString(rate: 48000.0, bitDepth: 24)
        XCTAssertEqual(q24, "48 кГц (Lossless 24-бит)")
    }

    func testFormatQualityStringHiResLossless() {
        let monitor = BitPerfectLogMonitor.shared
        let q96 = monitor.formatQualityString(rate: 96000.0, bitDepth: 24)
        XCTAssertEqual(q96, "96 кГц (Hi-Res Lossless 24-бит)")

        let q192 = monitor.formatQualityString(rate: 192000.0, bitDepth: 24)
        XCTAssertEqual(q192, "192 кГц (Hi-Res Lossless 24-бит)")

        let q352 = monitor.formatQualityString(rate: 352800.0, bitDepth: 32)
        XCTAssertEqual(q352, "352.8 кГц (Hi-Res Lossless 32-бит)")
    }

    func testReapplyCurrentFormatDoesNotCrash() {
        let monitor = BitPerfectLogMonitor.shared
        // When no sample rate is currently locked or monitor is in initial state
        monitor.reapplyCurrentFormat()
        XCTAssertTrue(true, "reapplyCurrentFormat completed safely without error")
    }

    func testResetTrackStateReleasesLock() {
        let monitor = BitPerfectLogMonitor.shared
        monitor.resetTrackState()

        let exp = expectation(description: "Queue flush")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            XCTAssertFalse(monitor.isFormatLockedForCurrentTrack, "Format lock must be released on track reset")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func testQualityDescriptionDefault() {
        let monitor = BitPerfectLogMonitor.shared
        XCTAssertFalse(monitor.currentQualityDescription.isEmpty)
    }
}
