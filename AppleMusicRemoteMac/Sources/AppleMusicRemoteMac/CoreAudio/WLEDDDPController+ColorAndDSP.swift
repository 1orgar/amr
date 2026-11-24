//
//  WLEDDDPController+ColorAndDSP.swift
//  AppleMusicRemoteMac
//
//  Cover-Faithful HSV/RGB Color Science, 16-Zone Spatial Palette Synthesis,
//  and Zero-Allocation Real-Time 3-Band CoreAudio Float32 Beat & Envelope DSP.
//

import Foundation
import os

extension WLEDDDPController {

    // MARK: - Color Science & Cover-Faithful 16-Zone Synthesis

    internal static func rgbToHsv(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
        let rf = min(max(r / 255.0, 0.0), 1.0)
        let gf = min(max(g / 255.0, 0.0), 1.0)
        let bf = min(max(b / 255.0, 0.0), 1.0)
        let maxC = max(rf, gf, bf)
        let minC = min(rf, gf, bf)
        let delta = maxC - minC

        var h: Double = 0.0
        if delta > 0.0001 {
            if maxC == rf {
                h = 60.0 * (((gf - bf) / delta).truncatingRemainder(dividingBy: 6.0))
            } else if maxC == gf {
                h = 60.0 * (((bf - rf) / delta) + 2.0)
            } else {
                h = 60.0 * (((rf - gf) / delta) + 4.0)
            }
            if h < 0 { h += 360.0 }
        }
        let s = maxC <= 0.0001 ? 0.0 : (delta / maxC)
        return (h, s, maxC)
    }

    internal static func hsvToRgb(h: Double, s: Double, v: Double) -> (r: Double, g: Double, b: Double) {
        let cleanH = ((h.truncatingRemainder(dividingBy: 360.0)) + 360.0).truncatingRemainder(dividingBy: 360.0)
        let cleanS = min(max(s, 0.0), 1.0)
        let cleanV = min(max(v, 0.0), 1.0)
        let c = cleanV * cleanS
        let x = c * (1.0 - abs(((cleanH / 60.0).truncatingRemainder(dividingBy: 2.0)) - 1.0))
        let m = cleanV - c
        let (r1, g1, b1): (Double, Double, Double)
        switch cleanH {
        case 0..<60:    (r1, g1, b1) = (c, x, 0)
        case 60..<120:  (r1, g1, b1) = (x, c, 0)
        case 120..<180: (r1, g1, b1) = (0, c, x)
        case 180..<240: (r1, g1, b1) = (0, x, c)
        case 240..<300: (r1, g1, b1) = (x, 0, c)
        default:        (r1, g1, b1) = (c, 0, x)
        }
        return ((r1 + m) * 255.0, (g1 + m) * 255.0, (b1 + m) * 255.0)
    }

    /// Enriches chromatic colors for addressable LEDs while preserving monochrome/grayscale/sepia covers
    /// without inventing false neon hues.
    internal static func saturateForLED(r: Double, g: Double, b: Double) -> (r: Double, g: Double, b: Double) {
        var (h, s, v) = rgbToHsv(r: r, g: g, b: b)
        if s < 0.12 {
            // Neutral / grayscale / dark silver cover: keep subtle natural tint
            s = min(0.18, s * 1.15)
            v = min(0.96, max(0.56, pow(v, 0.78) * 1.08))
        } else {
            s = min(1.0, pow(s, 0.62) * 1.16)
            v = min(1.0, max(0.62, pow(v, 0.76) * 1.10))
        }
        return hsvToRgb(h: h, s: s, v: v)
    }

    internal static func hueDistance(_ h1: Double, _ h2: Double) -> Double {
        let diff = abs(h1 - h2).truncatingRemainder(dividingBy: 360.0)
        return diff > 180.0 ? 360.0 - diff : diff
    }

    /// Builds 4 distinct harmonic anchors (`[CoreHero, SecondaryHarmonic, DeepWingContrast, LuminousCrest]`)
    /// from the cover's Vision Saliency clusters so every mode has vivid multi-tone separation across segments
    /// while remaining harmonious with the album artwork.
    internal static func buildDistinctCoverAnchors(from input: [(r: Double, g: Double, b: Double)]) -> [(r: Double, g: Double, b: Double)] {
        guard !input.isEmpty else { return defaultAnchors }
        let hsvList = input.map { rgbToHsv(r: $0.r, g: $0.g, b: $0.b) }
        let maxSat = hsvList.map(\.s).max() ?? 0.0

        // Monochrome / grayscale cover: warm champagne core <-> cool lunar ice wings (s < 0.19)
        if maxSat < 0.14 {
            let baseV = min(0.96, max(0.72, hsvList.map(\.v).max() ?? 0.85))
            return [
                hsvToRgb(h: 34.0,  s: 0.17, v: baseV),          // Warm Champagne Core
                hsvToRgb(h: 48.0,  s: 0.10, v: min(1.0, baseV * 1.04)), // Pearl Silver Mid
                hsvToRgb(h: 214.0, s: 0.18, v: baseV * 0.86),   // Cool Lunar Ice Wing
                hsvToRgb(h: 196.0, s: 0.06, v: 1.00)            // Crisp Diamond Crest
            ]
        }

        // Collect chromatically distinct hues (separated by >= 30°) ordered by perceptual prominence
        let ranked = hsvList
            .filter { $0.s >= 0.15 }
            .sorted { ($0.s * 0.65 + $0.v * 0.35) > ($1.s * 0.65 + $1.v * 0.35) }

        var distinct: [(h: Double, s: Double, v: Double)] = []
        for cand in ranked {
            if distinct.allSatisfy({ hueDistance($0.h, cand.h) >= 30.0 }) {
                distinct.append(cand)
                if distinct.count == 4 { break }
            }
        }
        let hero = distinct.first ?? hsvList[0]
        let h0 = hero.h
        let s0 = min(1.0, max(hero.s, 0.84))
        let v0 = min(1.0, max(hero.v, 0.90))

        let anchor0 = hsvToRgb(h: h0, s: s0, v: v0)

        let anchor1: (r: Double, g: Double, b: Double)
        if distinct.count >= 2 {
            let c1 = distinct[1]
            anchor1 = hsvToRgb(h: c1.h, s: min(1.0, max(c1.s, 0.82)), v: min(1.0, max(c1.v, 0.88)))
        } else {
            // Analogous warm/golden harmonic (+38° shift)
            anchor1 = hsvToRgb(h: h0 + 38.0, s: min(1.0, s0 * 0.95), v: 0.95)
        }

        let anchor2: (r: Double, g: Double, b: Double)
        if distinct.count >= 3 {
            let c2 = distinct[2]
            anchor2 = hsvToRgb(h: c2.h, s: min(1.0, max(c2.s, 0.84)), v: min(0.96, max(c2.v, 0.80)))
        } else {
            // Opposite-side analogous deep harmonic (-44° shift -> 82° total rich span without complementary clash!)
            anchor2 = hsvToRgb(h: h0 - 44.0, s: min(1.0, s0), v: 0.84)
        }

        let anchor3: (r: Double, g: Double, b: Double)
        if distinct.count >= 4 {
            let c3 = distinct[3]
            anchor3 = hsvToRgb(h: c3.h, s: min(0.92, max(c3.s, 0.72)), v: 1.0)
        } else {
            // Luminous high-energy crest accent (+56° shift)
            anchor3 = hsvToRgb(h: h0 + 56.0, s: min(0.84, s0 * 0.80), v: 1.0)
        }

        return [anchor0, anchor1, anchor2, anchor3]
    }

    /// Builds 16 spatially rich LED zones combining the cover's spatial map with the 4 distinct harmonic anchors
    /// so segments across the strip always exhibit expressive multi-tone depth (never a flat uniform hue).
    internal static func buildRich16Zones(
        from input: [(r: Double, g: Double, b: Double)],
        anchors: [(r: Double, g: Double, b: Double)]? = nil
    ) -> [(r: Double, g: Double, b: Double)] {
        guard !input.isEmpty else { return defaultZones }
        let resolvedAnchors = anchors ?? buildDistinctCoverAnchors(from: input)
        let hsvList = input.map { rgbToHsv(r: $0.r, g: $0.g, b: $0.b) }
        let maxSat = hsvList.map(\.s).max() ?? 0.0

        // 1. Monochrome / Grayscale Cover: smooth symmetric warm-core <-> cool-wing gradient
        if maxSat < 0.14 {
            return (0..<zoneCount).map { i in
                let norm = Double(i) / Double(zoneCount - 1)
                let dist = abs(norm - 0.5) * 2.0
                return blendRGB(resolvedAnchors[0], resolvedAnchors[2], t: dist * 0.85)
            }
        }

        let chromaticSamples = hsvList.filter { $0.s >= 0.16 }
        var maxHueSpread: Double = 0.0
        for i in 0..<chromaticSamples.count {
            for j in (i + 1)..<chromaticSamples.count {
                maxHueSpread = max(maxHueSpread, hueDistance(chromaticSamples[i].h, chromaticSamples[j].h))
            }
        }

        var rawZones: [(r: Double, g: Double, b: Double)] = []
        rawZones.reserveCapacity(zoneCount)

        for i in 0..<zoneCount {
            let norm = Double(i) / Double(zoneCount - 1)
            let dist = abs(norm - 0.5) * 2.0 // 0.0 at center (zones 7..8), 1.0 at outer wings (zones 0, 15)

            // Symmetric harmonic backdrop sweeping CoreHero (center) -> SecondaryHarmonic (mid) -> DeepWing (edges)
            let symmetricHarmony: (r: Double, g: Double, b: Double)
            if dist < 0.5 {
                symmetricHarmony = blendRGB(resolvedAnchors[0], resolvedAnchors[1], t: dist * 2.0)
            } else {
                symmetricHarmony = blendRGB(resolvedAnchors[1], resolvedAnchors[2], t: (dist - 0.5) * 2.0)
            }

            if maxHueSpread >= 36.0 && input.count >= zoneCount {
                // Multi-hue spatial cover: blend 65% spatial cover zone + 35% harmonic gradient for vivid segment contrast
                let sp = hsvList[i]
                let spRgb = hsvToRgb(h: sp.h, s: min(1.0, max(sp.s, 0.72)), v: min(1.0, max(sp.v, 0.74)))
                rawZones.append(blendRGB(symmetricHarmony, spRgb, t: 0.65))
            } else {
                rawZones.append(symmetricHarmony)
            }
        }

        // Gentle 3-tap smoothing `[0.15, 0.70, 0.15]` (clamped at endpoints so wing-to-center contrast stays crisp!)
        var smoothed: [(r: Double, g: Double, b: Double)] = []
        smoothed.reserveCapacity(zoneCount)
        for i in 0..<zoneCount {
            let prev = rawZones[max(0, i - 1)]
            let curr = rawZones[i]
            let next = rawZones[min(zoneCount - 1, i + 1)]
            smoothed.append((
                r: prev.r * 0.15 + curr.r * 0.70 + next.r * 0.15,
                g: prev.g * 0.15 + curr.g * 0.70 + next.g * 0.15,
                b: prev.b * 0.15 + curr.b * 0.70 + next.b * 0.15
            ))
        }
        return smoothed
    }

    @inline(__always)
    internal static func blendRGB(
        _ a: (r: Double, g: Double, b: Double),
        _ b: (r: Double, g: Double, b: Double),
        t: Double
    ) -> (r: Double, g: Double, b: Double) {
        let clamped = min(max(t, 0.0), 1.0)
        return (
            r: a.r + (b.r - a.r) * clamped,
            g: a.g + (b.g - a.g) * clamped,
            b: a.b + (b.b - a.b) * clamped
        )
    }

    internal func sampleZone(at continuousIndex: Double, zones: [(r: Double, g: Double, b: Double)]) -> (r: Double, g: Double, b: Double) {
        let count = zones.count
        guard count > 0 else { return (246, 36, 68) }
        let wrapped = ((continuousIndex.truncatingRemainder(dividingBy: Double(count))) + Double(count)).truncatingRemainder(dividingBy: Double(count))
        let idxA = Int(floor(wrapped)) % count
        let idxB = (idxA + 1) % count
        let frac = wrapped - floor(wrapped)
        let smooth = frac * frac * (3.0 - 2.0 * frac)
        let a = zones[idxA]
        let b = zones[idxB]
        return (
            a.r + (b.r - a.r) * smooth,
            a.g + (b.g - a.g) * smooth,
            a.b + (b.b - a.b) * smooth
        )
    }

    internal func sampleAnchor(at continuousIndex: Double, anchors: [(r: Double, g: Double, b: Double)]) -> (r: Double, g: Double, b: Double) {
        return sampleZone(at: continuousIndex, zones: anchors)
    }

    // MARK: - Zero-Allocation Real-Time CoreAudio Float32 Beat & 3-Band Envelope DSP

    internal func resetAudioFilterState() {
        os_unfair_lock_lock(&rtFilterSpinLock)
        rtFilterSampleRate = 0
        lp110Stage1 = 0.0
        lp110Stage2 = 0.0
        lp1800Stage1 = 0.0
        lp1800Stage2 = 0.0
        os_unfair_lock_unlock(&rtFilterSpinLock)

        os_unfair_lock_lock(&rtSpinLock)
        rtFastBass = 0.0
        rtSlowBass = 0.0
        rtFastMid = 0.0
        rtSlowMid = 0.0
        rtFastHigh = 0.0
        rtPrevNormBass = 0.0
        rtPrevNormMid = 0.0
        rtBassLevel = 0.0
        rtMidLevel = 0.0
        rtHighLevel = 0.0
        rtBeatPulse = 0.0
        os_unfair_lock_unlock(&rtSpinLock)
    }

    /// Real-time non-interleaved Float32 tap hook (~10 ms blocks from `AudioProcessTapService` IOProc, zero heap allocations).
    public func feedRealTimePlanarFloat32(
        left: UnsafePointer<Float>,
        right: UnsafePointer<Float>,
        frameCount: Int,
        sampleRate: Int
    ) {
        guard frameCount > 0 else { return }
        os_unfair_lock_lock(&rtSpinLock)
        let active = rtAudioHookActive
        os_unfair_lock_unlock(&rtSpinLock)
        guard active else { return }

        let sr = max(44_100, sampleRate)
        let dt = 1.0 / Double(sr)
        let alpha110 = dt / ((1.0 / (2.0 * Double.pi * 110.0)) + dt)
        let alpha1800 = dt / ((1.0 / (2.0 * Double.pi * 1800.0)) + dt)

        var sBassSq: Double = 0.0
        var sMidSq: Double = 0.0
        var sHighSq: Double = 0.0
        var peakAbs: Double = 0.0

        os_unfair_lock_lock(&rtFilterSpinLock)
        if rtFilterSampleRate != sr {
            rtFilterSampleRate = sr
            lp110Stage1 = 0.0
            lp110Stage2 = 0.0
            lp1800Stage1 = 0.0
            lp1800Stage2 = 0.0
        }
        var b1 = lp110Stage1
        var b2 = lp110Stage2
        var m1 = lp1800Stage1
        var m2 = lp1800Stage2

        for i in 0..<frameCount {
            let mono = 0.5 * (Double(left[i]) + Double(right[i]))
            let absM = abs(mono)
            if absM > peakAbs { peakAbs = absM }

            b1 += alpha110 * (mono - b1)
            b2 += alpha110 * (b1 - b2)
            m1 += alpha1800 * (mono - m1)
            m2 += alpha1800 * (m1 - m2)

            let bass = b2
            let mid = m2 - b2
            let high = mono - m2

            sBassSq += bass * bass
            sMidSq += mid * mid
            sHighSq += high * high
        }

        lp110Stage1 = b1
        lp110Stage2 = b2
        lp1800Stage1 = m1
        lp1800Stage2 = m2
        os_unfair_lock_unlock(&rtFilterSpinLock)

        commitRealTimeBandBlock(
            rmsBass: sqrt(sBassSq / Double(frameCount)),
            rmsMid: sqrt(sMidSq / Double(frameCount)),
            rmsHigh: sqrt(sHighSq / Double(frameCount)),
            peakAbs: peakAbs,
            blockDurationSec: Double(frameCount) * dt
        )
    }

    /// Real-time interleaved Float32 tap hook (~10 ms blocks from `AudioProcessTapService` IOProc, zero heap allocations).
    public func feedRealTimeInterleavedFloat32(
        interleaved: UnsafePointer<Float>,
        frameCount: Int,
        channels: Int,
        sampleRate: Int
    ) {
        guard frameCount > 0, channels >= 1 else { return }
        os_unfair_lock_lock(&rtSpinLock)
        let active = rtAudioHookActive
        os_unfair_lock_unlock(&rtSpinLock)
        guard active else { return }

        let sr = max(44_100, sampleRate)
        let dt = 1.0 / Double(sr)
        let alpha110 = dt / ((1.0 / (2.0 * Double.pi * 110.0)) + dt)
        let alpha1800 = dt / ((1.0 / (2.0 * Double.pi * 1800.0)) + dt)

        var sBassSq: Double = 0.0
        var sMidSq: Double = 0.0
        var sHighSq: Double = 0.0
        var peakAbs: Double = 0.0

        os_unfair_lock_lock(&rtFilterSpinLock)
        if rtFilterSampleRate != sr {
            rtFilterSampleRate = sr
            lp110Stage1 = 0.0
            lp110Stage2 = 0.0
            lp1800Stage1 = 0.0
            lp1800Stage2 = 0.0
        }
        var b1 = lp110Stage1
        var b2 = lp110Stage2
        var m1 = lp1800Stage1
        var m2 = lp1800Stage2

        if channels >= 2 {
            for i in 0..<frameCount {
                let base = i * channels
                let mono = 0.5 * (Double(interleaved[base]) + Double(interleaved[base + 1]))
                let absM = abs(mono)
                if absM > peakAbs { peakAbs = absM }

                b1 += alpha110 * (mono - b1)
                b2 += alpha110 * (b1 - b2)
                m1 += alpha1800 * (mono - m1)
                m2 += alpha1800 * (m1 - m2)

                let bass = b2
                let mid = m2 - b2
                let high = mono - m2

                sBassSq += bass * bass
                sMidSq += mid * mid
                sHighSq += high * high
            }
        } else {
            for i in 0..<frameCount {
                let mono = Double(interleaved[i])
                let absM = abs(mono)
                if absM > peakAbs { peakAbs = absM }

                b1 += alpha110 * (mono - b1)
                b2 += alpha110 * (b1 - b2)
                m1 += alpha1800 * (mono - m1)
                m2 += alpha1800 * (m1 - m2)

                let bass = b2
                let mid = m2 - b2
                let high = mono - m2

                sBassSq += bass * bass
                sMidSq += mid * mid
                sHighSq += high * high
            }
        }

        lp110Stage1 = b1
        lp110Stage2 = b2
        lp1800Stage1 = m1
        lp1800Stage2 = m2
        os_unfair_lock_unlock(&rtFilterSpinLock)

        commitRealTimeBandBlock(
            rmsBass: sqrt(sBassSq / Double(frameCount)),
            rmsMid: sqrt(sMidSq / Double(frameCount)),
            rmsHigh: sqrt(sHighSq / Double(frameCount)),
            peakAbs: peakAbs,
            blockDurationSec: Double(frameCount) * dt
        )
    }

    @inline(__always)
    internal func commitRealTimeBandBlock(
        rmsBass: Double,
        rmsMid: Double,
        rmsHigh: Double,
        peakAbs: Double,
        blockDurationSec: Double
    ) {
        let nowMono = Double(DispatchTime.now().uptimeNanoseconds) * 1.0e-9
        let dt = min(0.10, max(0.001, blockDurationSec))

        // Time-constant-derived IIR coefficients (sample-rate & buffer-size invariant!)
        let fastAttack = 1.0 - exp(-dt / 0.008)   // ~8 ms transient attack
        let fastRelease = 1.0 - exp(-dt / 0.060)  // ~60 ms transient release
        let slowUp = 1.0 - exp(-dt / 0.110)       // ~110 ms sustained-note adaptation
        let slowDown = 1.0 - exp(-dt / 0.240)     // ~240 ms baseline release
        let agcDecay = exp(-dt / 4.20)            // ~4.2 s smooth AGC ceiling release
        let beatDecay = exp(-dt / 0.095)          // ~95 ms crisp beat decay (tracks up to fast double-kick!)

        os_unfair_lock_lock(&rtSpinLock)
        rtLastTapCallbackMono = nowMono

        let totalRms = rmsBass + rmsMid + rmsHigh
        if peakAbs <= 0.00035 || totalRms <= 0.00020 {
            // Genuine silence / quiet gap in song: decay cleanly toward 0 without triggering fake synth fallback
            let quietDecay = exp(-dt / 0.090)
            rtFastBass *= quietDecay
            rtFastMid *= quietDecay
            rtFastHigh *= quietDecay
            rtPrevNormBass *= quietDecay
            rtPrevNormMid *= quietDecay
            rtBassLevel *= quietDecay
            rtMidLevel *= quietDecay
            rtHighLevel *= quietDecay
            rtBeatPulse *= beatDecay
            os_unfair_lock_unlock(&rtSpinLock)
            return
        }

        rtLastNonSilentMono = nowMono

        // 1. Update musical AGC ceilings with safe noise-floor clamps (prevents hiss/quiet pads from normalizing to 100%)
        if rmsBass > rtAgcPeakBass {
            rtAgcPeakBass += (rmsBass - rtAgcPeakBass) * 0.30
        } else {
            rtAgcPeakBass = max(0.032, rtAgcPeakBass * agcDecay)
        }
        if rmsMid > rtAgcPeakMid {
            rtAgcPeakMid += (rmsMid - rtAgcPeakMid) * 0.26
        } else {
            rtAgcPeakMid = max(0.030, rtAgcPeakMid * agcDecay)
        }
        if rmsHigh > rtAgcPeakHigh {
            rtAgcPeakHigh += (rmsHigh - rtAgcPeakHigh) * 0.28
        } else {
            rtAgcPeakHigh = max(0.016, rtAgcPeakHigh * agcDecay)
        }

        // 2. Normalized instantaneous band levels (0.0 ... 1.0) with soft noise gate
        let normBass = min(1.0, max(0.0, (rmsBass - 0.0015) / max(0.032, rtAgcPeakBass * 0.96)))
        let normMid  = min(1.0, max(0.0, (rmsMid  - 0.0012) / max(0.030, rtAgcPeakMid  * 0.96)))
        let normHigh = min(1.0, max(0.0, (rmsHigh - 0.0008) / max(0.016, rtAgcPeakHigh * 0.96)))

        // 3. Positive-derivative Spectral Flux + Fast/Slow onset detector (fires ONLY on genuine drum/note attacks, never on steady drone!)
        let deltaBass = max(0.0, normBass - rtPrevNormBass)
        let deltaMid  = max(0.0, normMid  - rtPrevNormMid)
        rtPrevNormBass = normBass * 0.75 + rtPrevNormBass * 0.25
        rtPrevNormMid  = normMid  * 0.75 + rtPrevNormMid  * 0.25

        rtFastBass += (normBass - rtFastBass) * (normBass > rtFastBass ? fastAttack : fastRelease)
        rtSlowBass += (normBass - rtSlowBass) * (normBass > rtSlowBass ? slowUp : slowDown)

        rtFastMid += (normMid - rtFastMid) * (normMid > rtFastMid ? fastAttack : fastRelease)
        rtSlowMid += (normMid - rtSlowMid) * (normMid > rtSlowMid ? slowUp : slowDown)

        rtFastHigh += (normHigh - rtFastHigh) * (normHigh > rtFastHigh ? fastAttack : fastRelease)

        let kickExcess = max(0.0, rtFastBass - (rtSlowBass * 1.08 + 0.025))
        let snareExcess = max(0.0, rtFastMid - (rtSlowMid * 1.12 + 0.035))
        let kickOnset = (deltaBass > 0.035) ? (kickExcess * 1.9 + deltaBass * 1.6) : 0.0
        let snareOnset = (deltaMid > 0.045) ? (snareExcess * 1.1 + deltaMid * 0.9) : 0.0
        let transientImpulse = min(1.0, kickOnset + snareOnset)
        rtBeatPulse = min(1.0, max(rtBeatPulse * beatDecay, transientImpulse))

        // 4. Dynamic contrast shaping: blend steady body with transient contrast so dense guitars don't pin LEDs at 100%
        let dynamicBass = min(1.0, pow(rtFastBass, 1.30) * 0.55 + rtBeatPulse * 0.65)
        let dynamicMid  = min(1.0, pow(rtFastMid, 1.25) * 0.72 + max(0.0, rtFastMid - rtSlowMid * 0.75) * 0.85)
        let dynamicHigh = min(1.0, pow(rtFastHigh, 1.30))

        rtBassLevel = dynamicBass
        rtMidLevel = dynamicMid
        rtHighLevel = dynamicHigh
        os_unfair_lock_unlock(&rtSpinLock)
    }
}
