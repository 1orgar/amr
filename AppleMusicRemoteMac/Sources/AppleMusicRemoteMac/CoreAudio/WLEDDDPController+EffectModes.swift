//
//  WLEDDDPController+EffectModes.swift
//  AppleMusicRemoteMac
//
//  Multi-Hue Center-Out & Spatial WLED Ambilight Effect Shaders:
//  - `vu_center`    : Symmetric Pulse (Center-Out Multi-Hue VU Bar + Crest Tip)
//  - `shockwave`    : Shockwave (Concentric Traveling Beat Rings from Center)
//  - `harmonic`     : Harmonic Resonance (Concentric Color Waves Radiating from Center)
//  - `supernova`    : Supernova (Explosive Beat Core, Vocal Corona & Treble Nebula)
//  - `prism_center` : Center Prism (Symmetric Kaleidoscopic Cover Hue Unfurling)
//  - `duet_wings`   : Counter-Pulse (Center Bass Jet Colliding with Outer Vocal/Treble Wings)
//  - `spectrum`     : 3-Band Spectral Stage (Distinct Cover Hues for Bass · Vocals · Highs)
//  - `breathing`    : Contrast Standing Wave from Center
//  - `ambilight`    : 16-Zone Spatial Cover Ambilight + Center Beat Bloom
//  - `static`       : Steady Multi-Tone Spatial Cover Palette
//

import Foundation

extension WLEDDDPController {

    internal func stepShockwaveRingsOnQueue(
        nowMono: Double,
        isPlaying: Bool,
        rawBeat: Double,
        smoothedBass: Double
    ) {
        if !isPlaying {
            for idx in shockwaveRings.indices {
                shockwaveRings[idx].pos += 0.035
                shockwaveRings[idx].energy *= 0.88
            }
            shockwaveRings.removeAll { $0.pos > 1.30 || $0.energy < 0.03 }
            prevBeatForRingTrigger = 0.0
            return
        }

        // Advance active concentric rings from center (0.0) outward to both strip ends (1.0)
        let speed = 0.038 + smoothedBass * 0.024
        for idx in shockwaveRings.indices {
            shockwaveRings[idx].pos += speed
            shockwaveRings[idx].energy *= 0.968
        }
        shockwaveRings.removeAll { $0.pos > 1.32 || $0.energy < 0.04 }

        // Spawn a new colored shockwave ring at the center on genuine beat transient edges
        let beatRise = rawBeat - prevBeatForRingTrigger
        prevBeatForRingTrigger = rawBeat
        if beatRise > 0.11 && rawBeat > 0.24 && (nowMono - lastRingSpawnMono) >= 0.14 {
            lastRingSpawnMono = nowMono
            let ringEnergy = min(1.0, 0.58 + rawBeat * 0.52)
            let cIdx = nextRingColorIdx % 4
            nextRingColorIdx += 1
            if shockwaveRings.count >= 5 {
                shockwaveRings.removeFirst()
            }
            shockwaveRings.append(ShockwaveRing(pos: 0.0, energy: ringEnergy, colorIdx: cIdx))
        }
    }

    internal func evaluateModePixelRGB(
        mode currentMode: String,
        normPos: Double,
        distFromCenter: Double,
        baseZoneIdx: Double,
        zonesSnapshot: [(r: Double, g: Double, b: Double)],
        anchors: [(r: Double, g: Double, b: Double)],
        effectiveBri: Double,
        motionWeight: Double,
        bassEnergy: Double,
        midEnergy: Double,
        highEnergy: Double,
        beatPunch: Double
    ) -> (r: Double, g: Double, b: Double) {
        let a0: (r: Double, g: Double, b: Double) = anchors.count > 0 ? anchors[0] : (r: 246.0, g: 36.0, b: 68.0)   // Core Hero
        let a1: (r: Double, g: Double, b: Double) = anchors.count > 1 ? anchors[1] : (r: 255.0, g: 138.0, b: 24.0)  // Secondary Harmonic
        let a2: (r: Double, g: Double, b: Double) = anchors.count > 2 ? anchors[2] : (r: 158.0, g: 28.0, b: 196.0)  // Deep Wing Contrast
        let a3: (r: Double, g: Double, b: Double) = anchors.count > 3 ? anchors[3] : (r: 255.0, g: 206.0, b: 96.0)  // Luminous Crest

        if currentMode == "static" || motionWeight < 0.01 {
            let col = sampleZone(at: baseZoneIdx, zones: zonesSnapshot)
            return (col.r * effectiveBri, col.g * effectiveBri, col.b * effectiveBri)
        }

        let rawRGB: (r: Double, g: Double, b: Double)
        let activeEnv: Double

        switch currentMode {
        case "vu_center":
            // Symmetric Center-Out Bar with 3-hue gradient: Hot Core (A3/A0) -> Harmonic Body (A1) -> Crest Tip (A3) over Deep Wing (A2)
            let span = 0.16 + 0.84 * min(1.0, bassEnergy * 0.74 + midEnergy * 0.36)
            let feather = 0.20
            let tEdge = min(1.0, max(0.0, (span + feather * 0.5 - distFromCenter) / feather))
            let smoothBar = tEdge * tEdge * (3.0 - 2.0 * tEdge)

            let barProgress = min(1.0, distFromCenter / max(0.18, span))
            let coreHot = Self.blendRGB(a0, a3, t: min(0.75, beatPunch * 0.75 * exp(-pow(distFromCenter / 0.24, 2.0))))
            var barColor = Self.blendRGB(coreHot, a1, t: pow(barProgress, 0.85))
            let tipGlow = exp(-pow((distFromCenter - span) / 0.11, 2.0)) * min(1.0, bassEnergy + midEnergy * 0.5)
            barColor = Self.blendRGB(barColor, a3, t: min(0.80, tipGlow * 0.85))

            let wingBackdrop = Self.blendRGB(a2, a1, t: highEnergy * 0.35)
            rawRGB = Self.blendRGB(wingBackdrop, barColor, t: smoothBar)
            activeEnv = min(1.0, 0.22 + 0.78 * smoothBar * (0.48 + 0.52 * max(bassEnergy, midEnergy)) + highEnergy * (1.0 - smoothBar) * 0.18)

        case "shockwave":
            // Concentric colored beat rings launching from center (0.0) and racing symmetrically to both ends (1.0)
            let baseBackdrop = Self.blendRGB(a0, a2, t: pow(distFromCenter, 0.85))
            let corePulse = exp(-pow(distFromCenter / 0.20, 2.0)) * min(1.0, bassEnergy * 0.85 + beatPunch * 0.45)
            let coreCol = Self.blendRGB(a0, a3, t: min(0.85, beatPunch * 0.85))

            var accumR = baseBackdrop.r * 0.24 + coreCol.r * corePulse * 0.85
            var accumG = baseBackdrop.g * 0.24 + coreCol.g * corePulse * 0.85
            var accumB = baseBackdrop.b * 0.24 + coreCol.b * corePulse * 0.85
            var totalLift = 0.24 + corePulse * 0.80

            if shockwaveRings.isEmpty {
                // Smooth melodic outward ripple during beatless vocal/ambient passages
                let gentleRipple = 0.5 + 0.5 * cos((distFromCenter * 2.2 - phase * 0.9) * Double.pi * 2.0)
                let vocalWave = gentleRipple * midEnergy * 0.55
                let vocalCol = Self.blendRGB(a1, a2, t: distFromCenter)
                accumR += vocalCol.r * vocalWave
                accumG += vocalCol.g * vocalWave
                accumB += vocalCol.b * vocalWave
                totalLift += vocalWave
            } else {
                for ring in shockwaveRings {
                    let ringBell = exp(-pow((distFromCenter - ring.pos) / 0.135, 2.0)) * ring.energy
                    guard ringBell > 0.01 else { continue }
                    let startAnchor: (r: Double, g: Double, b: Double)
                    let endAnchor: (r: Double, g: Double, b: Double)
                    switch ring.colorIdx {
                    case 0:  startAnchor = a3; endAnchor = a1
                    case 1:  startAnchor = a1; endAnchor = a2
                    case 2:  startAnchor = a0; endAnchor = a1
                    default: startAnchor = a3; endAnchor = a0
                    }
                    let ringCol = Self.blendRGB(startAnchor, endAnchor, t: min(1.0, ring.pos * 0.95))
                    accumR += ringCol.r * ringBell * 0.95
                    accumG += ringCol.g * ringBell * 0.95
                    accumB += ringCol.b * ringBell * 0.95
                    totalLift += ringBell * 0.88
                }
            }

            let normScale = totalLift > 1.0 ? (1.0 / totalLift) : 1.0
            rawRGB = (
                min(255.0, accumR * normScale / max(0.24, min(1.0, totalLift))),
                min(255.0, accumG * normScale / max(0.24, min(1.0, totalLift))),
                min(255.0, accumB * normScale / max(0.24, min(1.0, totalLift)))
            )
            activeEnv = min(1.0, totalLift)

        case "harmonic":
            // Center-Out Harmonic Resonance: concentric melodic color waves radiating symmetrically from center!
            let radialCoord = distFromCenter * 2.2 - phase * 0.78 - beatPhase * 0.28
            let flowingHarmony = sampleAnchor(at: radialCoord * 2.2 + midEnergy * 1.15, anchors: anchors)
            let centerGlowWeight = exp(-pow(distFromCenter / 0.34, 2.0))
            let centerCoreCol = Self.blendRGB(a0, a3, t: min(0.75, beatPunch * 0.75))

            var col = Self.blendRGB(flowingHarmony, centerCoreCol, t: centerGlowWeight * (0.35 + 0.50 * bassEnergy))
            if distFromCenter > 0.65 {
                let rimSpark = ((distFromCenter - 0.65) / 0.35) * highEnergy * 0.55
                col = Self.blendRGB(col, a3, t: min(0.65, rimSpark))
            }

            let crestWave = 0.5 + 0.5 * cos(radialCoord * Double.pi * 2.0)
            rawRGB = col
            activeEnv = min(
                1.0,
                0.30 + 0.70 * (
                    centerGlowWeight * bassEnergy * 0.65 +
                    crestWave * (0.28 + 0.72 * midEnergy) * 0.65 +
                    highEnergy * 0.22
                )
            )

        case "supernova":
            // Supernova: incandescent beat core + swirling vocal plasma corona + contrasting outer nebula tips
            let coreRadius = 0.20 + 0.26 * bassEnergy
            let coreMask = exp(-pow(distFromCenter / max(0.14, coreRadius), 2.0))
            let coronaMask = exp(-pow((distFromCenter - (0.46 + 0.14 * midEnergy)) / 0.24, 2.0))
            let nebulaMask = pow(distFromCenter, 1.5)

            let coreCol = Self.blendRGB(a0, a3, t: min(0.90, 0.30 + beatPunch * 0.70))
            let coronaCol = Self.blendRGB(a1, a0, t: 0.35 * sin(phase * 1.1 + distFromCenter * 3.0) + 0.35)
            let nebulaCol = Self.blendRGB(a2, a3, t: min(0.65, highEnergy * 0.75))

            let wCore = coreMask * (0.40 + 0.85 * bassEnergy)
            let wCorona = coronaMask * (0.32 + 0.82 * midEnergy)
            let wNebula = nebulaMask * (0.26 + 0.74 * max(highEnergy, midEnergy * 0.45))
            let wSum = max(0.001, wCore + wCorona + wNebula)

            rawRGB = (
                (coreCol.r * wCore + coronaCol.r * wCorona + nebulaCol.r * wNebula) / wSum,
                (coreCol.g * wCore + coronaCol.g * wCorona + nebulaCol.g * wNebula) / wSum,
                (coreCol.b * wCore + coronaCol.b * wCorona + nebulaCol.b * wNebula) / wSum
            )
            activeEnv = min(1.0, 0.26 + 0.74 * max(wCore, max(wCorona, wNebula * 0.85)))

        case "prism_center":
            // Symmetric Kaleidoscopic Cover Prism unfurling all 4 harmonic anchors outward from center
            let stretch = 2.8 - 0.9 * bassEnergy
            let anchorCoord = distFromCenter * stretch - beatPhase * 0.48 + sin(phase * 0.65) * 0.30
            var prismCol = sampleAnchor(at: anchorCoord, anchors: anchors)
            let centerFlash = exp(-pow(distFromCenter / 0.22, 2.0)) * beatPunch * 0.55
            prismCol = Self.blendRGB(prismCol, a3, t: min(0.70, centerFlash))

            let ripple = 0.78 + 0.22 * cos((distFromCenter * 2.0 - beatPhase * 0.5) * Double.pi * 2.0)
            rawRGB = prismCol
            activeEnv = min(1.0, (0.36 + 0.64 * (bassEnergy * 0.60 + midEnergy * 0.40)) * ripple)

        case "duet_wings":
            // Counter-Pulse: Center Bass Jet (A0->A1) expanding outward vs Outer Treble/Vocal Wings (A2->A3) pushing inward
            let centerSpan = 0.14 + 0.66 * bassEnergy
            let wingSpan = 0.14 + 0.66 * min(1.0, midEnergy * 0.62 + highEnergy * 0.58)
            let feather = 0.20

            let tCenter = min(1.0, max(0.0, (centerSpan + feather * 0.5 - distFromCenter) / feather))
            let centerJet = tCenter * tCenter * (3.0 - 2.0 * tCenter)

            let distFromEdge = 1.0 - distFromCenter
            let tWing = min(1.0, max(0.0, (wingSpan + feather * 0.5 - distFromEdge) / feather))
            let edgeWing = tWing * tWing * (3.0 - 2.0 * tWing)

            let collision = min(1.0, centerJet * edgeWing * 2.2)
            let jetCol = Self.blendRGB(a0, a1, t: min(1.0, distFromCenter / max(0.16, centerSpan)))
            let wingCol = Self.blendRGB(a2, a3, t: min(1.0, highEnergy * 0.70 + 0.15))

            let wJ = 0.12 + centerJet * (0.35 + 0.65 * bassEnergy)
            let wW = 0.12 + edgeWing * (0.35 + 0.65 * max(midEnergy, highEnergy))
            let baseMix = Self.blendRGB(jetCol, wingCol, t: wW / max(0.001, wJ + wW))
            rawRGB = Self.blendRGB(baseMix, a3, t: min(0.85, collision * 0.85))
            activeEnv = min(1.0, 0.24 + 0.76 * max(centerJet * (0.45 + 0.55 * bassEnergy), edgeWing * (0.45 + 0.55 * max(midEnergy, highEnergy))) + collision * 0.25)

        case "spectrum":
            // Symmetric 3-Band Equalizer Stage with 3 distinct cover hues: Center=A0/A3 (Bass), Mid=A1 (Vocals), Outer=A2/A3 (Highs)
            let bassWeight = exp(-pow(distFromCenter / 0.36, 2.0))
            let midWeight  = exp(-pow((distFromCenter - 0.54) / 0.25, 2.0))
            let highWeight = exp(-pow((distFromCenter - 0.92) / 0.25, 2.0))
            let wNorm = max(0.001, bassWeight + midWeight + highWeight)

            let bassCol = Self.blendRGB(a0, a3, t: min(0.60, beatPunch * 0.60))
            let midCol  = a1
            let highCol = Self.blendRGB(a2, a3, t: min(0.65, highEnergy * 0.65))

            rawRGB = (
                (bassCol.r * bassWeight + midCol.r * midWeight + highCol.r * highWeight) / wNorm,
                (bassCol.g * bassWeight + midCol.g * midWeight + highCol.g * highWeight) / wNorm,
                (bassCol.b * bassWeight + midCol.b * midWeight + highCol.b * highWeight) / wNorm
            )
            let bandLift = (bassWeight * bassEnergy + midWeight * midEnergy + highWeight * highEnergy) / max(1.0, wNorm)
            activeEnv = min(1.0, 0.28 + 0.72 * bandLift)

        case "breathing":
            // Symmetric Standing Wave from Center with two-tone crest (A0/A1) vs valley (A2) contrast
            let wave = 0.5 + 0.5 * cos((distFromCenter * 2.2 - beatPhase * 0.45) * Double.pi)
            let crestCol = Self.blendRGB(a0, a1, t: 0.35 + 0.65 * midEnergy)
            var waveCol = Self.blendRGB(a2, crestCol, t: wave)
            waveCol = Self.blendRGB(waveCol, a3, t: min(0.45, wave * beatPunch * 0.45))

            rawRGB = waveCol
            activeEnv = min(1.0, 0.32 + 0.68 * (0.38 * wave * (0.30 + 0.70 * midEnergy) + 0.62 * bassEnergy))

        default:
            // "ambilight": Enriched 16-zone spatial cover palette + organic sway + center beat bloom
            let sway = sin(normPos * Double.pi * 2.0) * sin(phase * 0.55) * (0.45 + 0.65 * midEnergy)
            let spCol = sampleZone(at: baseZoneIdx + sway, zones: zonesSnapshot)
            let centerBloomMask = exp(-pow(distFromCenter / 0.38, 2.0)) * beatPunch * 0.52
            let bloomCol = Self.blendRGB(a1, a3, t: 0.45)
            var col = Self.blendRGB(spCol, bloomCol, t: min(0.65, centerBloomMask))
            if distFromCenter > 0.65 {
                col = Self.blendRGB(col, a2, t: ((distFromCenter - 0.65) / 0.35) * 0.35)
            }

            rawRGB = col
            activeEnv = min(1.0, 0.38 + 0.62 * (bassEnergy * 0.68 + midEnergy * 0.32))
        }

        let blendedEnv = (1.0 - motionWeight) * 0.90 + motionWeight * activeEnv
        return (
            rawRGB.r * effectiveBri * blendedEnv,
            rawRGB.g * effectiveBri * blendedEnv,
            rawRGB.b * effectiveBri * blendedEnv
        )
    }
}
