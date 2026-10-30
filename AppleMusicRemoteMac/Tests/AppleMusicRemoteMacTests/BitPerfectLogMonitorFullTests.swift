//
//  BitPerfectLogMonitorFullTests.swift
//  AppleMusicRemoteMacTests
//

import XCTest
@testable import AppleMusicRemoteMac

final class BitPerfectLogMonitorFullTests: XCTestCase {

    func testReportLocalTrackFormatStandardAndHiRes() {
        let monitor = BitPerfectLogMonitor.shared

        // Reset track state first
        monitor.resetTrackState()

        let expectation1 = expectation(description: "Report 44.1kHz standard format")
        monitor.onFormatChanged = { rate, depth, desc in
            XCTAssertEqual(rate, 44100.0)
            XCTAssertEqual(depth, 16)
            XCTAssertTrue(desc.contains("44.1 кГц"))
            expectation1.fulfill()
        }

        monitor.reportLocalTrackFormat(sampleRate: 44100.0, bitDepth: 16)
        wait(for: [expectation1], timeout: 2.0)

        XCTAssertTrue(monitor.isFormatLockedForCurrentTrack)
        XCTAssertEqual(monitor.currentDetectedSampleRate, 44100.0)
        XCTAssertEqual(monitor.currentDetectedBitDepth, 16)

        // Reset and test Hi-Res (96kHz)
        monitor.resetTrackState()
        let expectation2 = expectation(description: "Report 96kHz Hi-Res format")
        monitor.onFormatChanged = { rate, depth, desc in
            XCTAssertEqual(rate, 96000.0)
            XCTAssertEqual(depth, 24)
            XCTAssertTrue(desc.contains("96 кГц"))
            XCTAssertTrue(desc.contains("Hi-Res Lossless"))
            expectation2.fulfill()
        }

        monitor.reportLocalTrackFormat(sampleRate: 96000.0, bitDepth: 24)
        wait(for: [expectation2], timeout: 2.0)

        XCTAssertTrue(monitor.isFormatLockedForCurrentTrack)
        XCTAssertEqual(monitor.currentDetectedSampleRate, 96000.0)
        XCTAssertEqual(monitor.currentDetectedBitDepth, 24)
    }

    func testReportLocalTrackFormatDoesNotOverrideWhenLocked() {
        let monitor = BitPerfectLogMonitor.shared
        monitor.resetTrackState()

        let expFirst = expectation(description: "Initial lock")
        monitor.onFormatChanged = { _, _, _ in
            expFirst.fulfill()
        }
        monitor.reportLocalTrackFormat(sampleRate: 48000.0, bitDepth: 24)
        wait(for: [expFirst], timeout: 2.0)

        XCTAssertEqual(monitor.currentDetectedSampleRate, 48000.0)

        // Subsequent call while locked should be ignored
        var wasCalledAgain = false
        monitor.onFormatChanged = { _, _, _ in
            wasCalledAgain = true
        }

        monitor.reportLocalTrackFormat(sampleRate: 192000.0, bitDepth: 24)

        let expWait = expectation(description: "Wait check")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            expWait.fulfill()
        }
        wait(for: [expWait], timeout: 1.0)

        XCTAssertFalse(wasCalledAgain, "Report must be ignored when format is locked for current track")
        XCTAssertEqual(monitor.currentDetectedSampleRate, 48000.0)
    }

    func testFormatQualityStringAllStandardRates() {
        let monitor = BitPerfectLogMonitor.shared

        let q44 = monitor.formatQualityString(rate: 44100.0, bitDepth: 16)
        XCTAssertEqual(q44, "44.1 кГц (Lossless 16-бит)")

        let q48 = monitor.formatQualityString(rate: 48000.0, bitDepth: 24)
        XCTAssertEqual(q48, "48 кГц (Lossless 24-бит)")

        let q88 = monitor.formatQualityString(rate: 88200.0, bitDepth: 24)
        XCTAssertEqual(q88, "88.2 кГц (Hi-Res Lossless 24-бит)")

        let q96 = monitor.formatQualityString(rate: 96000.0, bitDepth: 24)
        XCTAssertEqual(q96, "96 кГц (Hi-Res Lossless 24-бит)")

        let q176 = monitor.formatQualityString(rate: 176400.0, bitDepth: 24)
        XCTAssertEqual(q176, "176.4 кГц (Hi-Res Lossless 24-бит)")

        let q192 = monitor.formatQualityString(rate: 192000.0, bitDepth: 24)
        XCTAssertEqual(q192, "192 кГц (Hi-Res Lossless 24-бит)")

        let q384 = monitor.formatQualityString(rate: 384000.0, bitDepth: 32)
        XCTAssertEqual(q384, "384 кГц (Hi-Res Lossless 32-бит)")

        let q768 = monitor.formatQualityString(rate: 768000.0, bitDepth: 32)
        XCTAssertEqual(q768, "768 кГц (Hi-Res Lossless 32-бит)")
    }

    func testNormalizeRateEdgeCases() {
        let monitor = BitPerfectLogMonitor.shared

        // Negative rates
        XCTAssertNil(monitor.normalizeRate(-100.0))
        // Zero rate
        XCTAssertNil(monitor.normalizeRate(0.0))

        // Snapping within 300 Hz
        XCTAssertEqual(monitor.normalizeRate(44200.0), 44100.0)
        XCTAssertEqual(monitor.normalizeRate(43900.0), 44100.0)
        XCTAssertEqual(monitor.normalizeRate(96200.0), 96000.0)
        XCTAssertEqual(monitor.normalizeRate(191850.0), 192000.0)

        // Non-standard rate outside 300 Hz snap threshold is preserved
        let customRate = monitor.normalizeRate(50000.0)
        XCTAssertEqual(customRate, 50000.0)
    }

    func testBitPerfectMonitorEnabledByDefault() {
        let monitor = BitPerfectLogMonitor.shared
        XCTAssertTrue(monitor.isEnabled)
    }

    func testResetTrackStateWithPreInspectedFormat() {
        let monitor = BitPerfectLogMonitor.shared
        let exp = expectation(description: "Queue sync")
        monitor.resetTrackState(expectedSampleRate: 48000.0, expectedBitDepth: 24)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(monitor.currentDetectedSampleRate, 48000.0)
            XCTAssertEqual(monitor.currentDetectedBitDepth, 24)
            XCTAssertTrue(monitor.isFormatLockedForCurrentTrack)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func testThreshold48kHzIs24BitByDefault() {
        let monitor = BitPerfectLogMonitor.shared
        let exp = expectation(description: "Queue sync 48kHz default")
        monitor.resetTrackState(expectedSampleRate: 48000.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(monitor.currentDetectedSampleRate, 48000.0)
            XCTAssertEqual(monitor.currentDetectedBitDepth, 24)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    func testTrackFormatCaching() {
        let monitor = BitPerfectLogMonitor.shared
        monitor.cacheTrackFormat(artist: "Mrs. GREEN APPLE", title: "Inferno", sampleRate: 48000.0, bitDepth: 24)
        let cached = monitor.getCachedFormat(artist: "mrs. green apple", title: "inferno")
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.sampleRate, 48000.0)
        XCTAssertEqual(cached?.bitDepth, 24)

        // Non-cached track
        XCTAssertNil(monitor.getCachedFormat(artist: "Unknown", title: "Nonexistent"))
    }
}
