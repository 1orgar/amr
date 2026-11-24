//
//  WLEDDDPControllerTests.swift
//  AppleMusicRemoteMacTests
//
//  Regression tests for WLED DDP Ambilight multi-tone harmonic color synthesis,
//  center-out symmetric presets (`vu_center`, `shockwave`, `harmonic`, `supernova`, `prism_center`, `duet_wings`),
//  real-time Float32 beat onset detection, silence stability, and Gamma 2.0 Schmitt-trigger anti-flicker quantization.
//

import XCTest
import os
@testable import AppleMusicRemoteMac

final class WLEDDDPControllerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        let wled = WLEDDDPController.shared
        wled.resetAudioFilterState()
        wled.shockwaveRings.removeAll()
        wled.prevBeatForRingTrigger = 0.0
        wled.lastRingSpawnMono = -1.0e9
        os_unfair_lock_lock(&wled.rtSpinLock)
        wled.rtAudioHookActive = true
        wled.rtAgcPeakBass = 0.06
        wled.rtAgcPeakMid = 0.06
        wled.rtAgcPeakHigh = 0.03
        os_unfair_lock_unlock(&wled.rtSpinLock)
    }

    override func tearDown() {
        let wled = WLEDDDPController.shared
        os_unfair_lock_lock(&wled.rtSpinLock)
        wled.rtAudioHookActive = false
        os_unfair_lock_unlock(&wled.rtSpinLock)
        wled.resetAudioFilterState()
        wled.shockwaveRings.removeAll()
        super.tearDown()
    }

    func testMonochromeCoverPreservesNeutralLowSaturationPalette() {
        let monoInput: [(r: Double, g: Double, b: Double)] = [
            WLEDDDPController.saturateForLED(r: 58, g: 56, b: 55),
            WLEDDDPController.saturateForLED(r: 132, g: 130, b: 128),
            WLEDDDPController.saturateForLED(r: 92, g: 90, b: 88)
        ]
        let zones = WLEDDDPController.buildRich16Zones(from: monoInput)
        XCTAssertEqual(zones.count, 16)
        for z in zones {
            let hsv = WLEDDDPController.rgbToHsv(r: z.r, g: z.g, b: z.b)
            XCTAssertLessThan(hsv.s, 0.20, "Monochrome cover must not be turned into high-saturation neon")
            XCTAssertGreaterThan(hsv.v, 0.45)
        }
    }

    func testCohesiveCrimsonCoverCreatesDistinctAnalogousSegmentHuesWithoutComplementaryClash() {
        let crimsonInput: [(r: Double, g: Double, b: Double)] = [
            WLEDDDPController.saturateForLED(r: 196, g: 24, b: 36),
            WLEDDDPController.saturateForLED(r: 145, g: 18, b: 28),
            WLEDDDPController.saturateForLED(r: 224, g: 40, b: 48)
        ]
        let refHue = WLEDDDPController.rgbToHsv(r: 196, g: 24, b: 36).h
        let anchors = WLEDDDPController.buildDistinctCoverAnchors(from: crimsonInput)
        let zones = WLEDDDPController.buildRich16Zones(from: crimsonInput, anchors: anchors)
        XCTAssertEqual(anchors.count, 4)
        XCTAssertEqual(zones.count, 16)

        var maxPairwiseSpread: Double = 0.0
        for i in 0..<zones.count {
            let hsvI = WLEDDDPController.rgbToHsv(r: zones[i].r, g: zones[i].g, b: zones[i].b)
            let distFromHero = WLEDDDPController.hueDistance(hsvI.h, refHue)
            XCTAssertLessThan(distFromHero, 75.0, "Single-hue crimson cover must stay harmonious without complementary cyan/green (got hue \(hsvI.h))")
            for j in (i + 1)..<zones.count {
                let hsvJ = WLEDDDPController.rgbToHsv(r: zones[j].r, g: zones[j].g, b: zones[j].b)
                maxPairwiseSpread = max(maxPairwiseSpread, WLEDDDPController.hueDistance(hsvI.h, hsvJ.h))
            }
        }
        XCTAssertGreaterThanOrEqual(maxPairwiseSpread, 25.0, "Zones must exhibit rich multi-hue contrast from center to wings")
    }

    func testAllCenterOutPresetsAreSymmetricAndProduceDistinctSegmentHues() {
        let wled = WLEDDDPController.shared
        let anchors = WLEDDDPController.defaultAnchors
        let zones = WLEDDDPController.defaultZones
        wled.shockwaveRings = [
            WLEDDDPController.ShockwaveRing(pos: 0.42, energy: 0.88, colorIdx: 0),
            WLEDDDPController.ShockwaveRing(pos: 0.78, energy: 0.62, colorIdx: 2)
        ]

        let centerSymmetricModes = [
            "vu_center",
            "shockwave",
            "harmonic",
            "supernova",
            "prism_center",
            "duet_wings",
            "spectrum",
            "breathing"
        ]

        for mode in centerSymmetricModes {
            XCTAssertTrue(WLEDDDPController.supportedModes.contains(mode), "Missing mode \(mode) in supportedModes")

            let ledCount = 60
            var pixels: [(r: Double, g: Double, b: Double)] = []
            for i in 0..<ledCount {
                let normPos = Double(i) / Double(ledCount - 1)
                let dist = abs(normPos - 0.5) * 2.0
                let zIdx = normPos * 15.0
                let rgb = wled.evaluateModePixelRGB(
                    mode: mode,
                    normPos: normPos,
                    distFromCenter: dist,
                    baseZoneIdx: zIdx,
                    zonesSnapshot: zones,
                    anchors: anchors,
                    effectiveBri: 1.0,
                    motionWeight: 1.0,
                    bassEnergy: 0.72,
                    midEnergy: 0.58,
                    highEnergy: 0.48,
                    beatPunch: 0.65
                )
                pixels.append(rgb)
            }

            // 1. Exact left/right mirror symmetry from center
            for i in 0..<(ledCount / 2) {
                let left = pixels[i]
                let right = pixels[ledCount - 1 - i]
                XCTAssertEqual(left.r, right.r, accuracy: 0.001, "Mode \(mode) must be symmetric from center")
                XCTAssertEqual(left.g, right.g, accuracy: 0.001, "Mode \(mode) must be symmetric from center")
                XCTAssertEqual(left.b, right.b, accuracy: 0.001, "Mode \(mode) must be symmetric from center")
            }

            // 2. Meaningful hue difference between center and outer segments
            let centerHsv = WLEDDDPController.rgbToHsv(r: pixels[ledCount / 2].r, g: pixels[ledCount / 2].g, b: pixels[ledCount / 2].b)
            var maxHueDelta: Double = 0.0
            for p in pixels {
                let hsv = WLEDDDPController.rgbToHsv(r: p.r, g: p.g, b: p.b)
                maxHueDelta = max(maxHueDelta, WLEDDDPController.hueDistance(centerHsv.h, hsv.h))
            }
            XCTAssertGreaterThanOrEqual(maxHueDelta, 15.0, "Mode \(mode) should vary hues visibly across segments")
        }
    }

    func testShockwaveSpawnsAndAdvancesRingsOnBeatTransients() {
        let wled = WLEDDDPController.shared
        wled.stepShockwaveRingsOnQueue(nowMono: 10.0, isPlaying: true, rawBeat: 0.05, smoothedBass: 0.3)
        XCTAssertTrue(wled.shockwaveRings.isEmpty)

        // Sharp beat transient spawns ring at center (pos == 0.0)
        wled.stepShockwaveRingsOnQueue(nowMono: 10.20, isPlaying: true, rawBeat: 0.75, smoothedBass: 0.6)
        XCTAssertEqual(wled.shockwaveRings.count, 1)
        XCTAssertEqual(wled.shockwaveRings[0].pos, 0.0, accuracy: 0.0001)

        // Subsequent frame advances ring outward toward strip edges
        wled.stepShockwaveRingsOnQueue(nowMono: 10.225, isPlaying: true, rawBeat: 0.55, smoothedBass: 0.6)
        XCTAssertGreaterThan(wled.shockwaveRings[0].pos, 0.04)
    }

    func testRealTimeFloat32KickTransientProducesBeatPulseOverSteadyBackground() {
        let wled = WLEDDDPController.shared
        let sr = 48_000
        let blockFrames = 512

        var phase300: Double = 0.0
        for _ in 0..<35 {
            var block = [Float](repeating: 0, count: blockFrames)
            for i in 0..<blockFrames {
                block[i] = Float(0.18 * sin(phase300))
                phase300 += 2.0 * Double.pi * 300.0 / Double(sr)
            }
            block.withUnsafeBufferPointer { ptr in
                wled.feedRealTimePlanarFloat32(left: ptr.baseAddress!, right: ptr.baseAddress!, frameCount: blockFrames, sampleRate: sr)
            }
        }

        os_unfair_lock_lock(&wled.rtSpinLock)
        let steadyBeat = wled.rtBeatPulse
        os_unfair_lock_unlock(&wled.rtSpinLock)
        XCTAssertLessThan(steadyBeat, 0.15, "Steady continuous tone should not trigger beat pulses")

        var phase55: Double = 0.0
        for _ in 0..<3 {
            var kickBlock = [Float](repeating: 0, count: blockFrames)
            for i in 0..<blockFrames {
                kickBlock[i] = Float(0.75 * sin(phase55) + 0.18 * sin(phase300))
                phase55 += 2.0 * Double.pi * 55.0 / Double(sr)
                phase300 += 2.0 * Double.pi * 300.0 / Double(sr)
            }
            kickBlock.withUnsafeBufferPointer { ptr in
                wled.feedRealTimePlanarFloat32(left: ptr.baseAddress!, right: ptr.baseAddress!, frameCount: blockFrames, sampleRate: sr)
            }
        }

        os_unfair_lock_lock(&wled.rtSpinLock)
        let transientBeat = wled.rtBeatPulse
        let transientBass = wled.rtBassLevel
        os_unfair_lock_unlock(&wled.rtSpinLock)

        XCTAssertGreaterThan(transientBeat, 0.45, "Kick transient must trigger strong beat onset pulse")
        XCTAssertGreaterThan(transientBass, 0.45)
    }

    func testSilenceUpdatesTapTimestampAndDecaysWithoutNoiseAmplification() {
        let wled = WLEDDDPController.shared
        let sr = 48_000
        let blockFrames = 512
        let tinyHiss = [Float](repeating: 0.00005, count: blockFrames)

        for _ in 0..<20 {
            tinyHiss.withUnsafeBufferPointer { ptr in
                wled.feedRealTimePlanarFloat32(left: ptr.baseAddress!, right: ptr.baseAddress!, frameCount: blockFrames, sampleRate: sr)
            }
        }

        os_unfair_lock_lock(&wled.rtSpinLock)
        let lastTap = wled.rtLastTapCallbackMono
        let bass = wled.rtBassLevel
        let beat = wled.rtBeatPulse
        os_unfair_lock_unlock(&wled.rtSpinLock)

        let nowMono = Double(DispatchTime.now().uptimeNanoseconds) * 1.0e-9
        XCTAssertLessThan(nowMono - lastTap, 0.5, "Silence/hiss frames must still refresh tap liveness timestamp")
        XCTAssertEqual(bass, 0.0, accuracy: 0.001)
        XCTAssertEqual(beat, 0.0, accuracy: 0.001)
    }

    func testGamma2QuantizerWithHysteresisPreventsBoundaryStepFlicker() {
        let initial = WLEDDDPController.quantizeGamma2WithHysteresis(linear255: 80.6, previousByte: 0)
        var prev = initial
        var transitions = 0
        for step in 0..<40 {
            let jittered = 80.6 + (step % 2 == 0 ? 0.18 : -0.18)
            let next = WLEDDDPController.quantizeGamma2WithHysteresis(linear255: jittered, previousByte: prev)
            if next != prev {
                transitions += 1
            }
            prev = next
        }
        XCTAssertEqual(transitions, 0, "Sub-LSB jitter must not cause 8-bit boundary step flicker")
    }

    func testWebUIBundleIncludesNewCenterOutLightingPresets() {
        let html = WebUIContent.indexHTML
        XCTAssertTrue(html.contains("value=\"shockwave\""))
        XCTAssertTrue(html.contains("value=\"supernova\""))
        XCTAssertTrue(html.contains("value=\"prism_center\""))
        XCTAssertTrue(html.contains("value=\"duet_wings\""))
        XCTAssertTrue(html.contains("Гармонический резонанс (волны цвета от центра)"))
    }
}
