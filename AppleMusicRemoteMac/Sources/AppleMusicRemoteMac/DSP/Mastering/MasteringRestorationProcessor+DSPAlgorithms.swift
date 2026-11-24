//
//  MasteringRestorationProcessor+DSPAlgorithms.swift
//  AppleMusicRemoteMac
//
//  Stage 0a: C1 Cubic Hermite Look-Ahead De-Clipper
//  Stage 0b: Weiss-Style Level-Independent Relative Sibilance Dynamic De-Esser
//

import Foundation

extension MasteringRestorationProcessor {

    // MARK: - Stage 0a: C1 Cubic Hermite De-Clipper

    @usableFromInline
    @inline(__always)
    internal static func inspectAndRepairChannel(
        ring: inout [Double],
        tracker: inout ChannelDeClipTracker,
        writeSampleIndex: Int64,
        incomingSample: Double,
        mode: MasteringDeClipMode,
        autoBypass: Bool,
        maxRunSamples: Int,
        ceilingDecay: Double,
        peakRestoredDB: inout Double,
        clipsCount: inout UInt64
    ) -> Double {
        let writeSlot = Int(writeSampleIndex) & Self.ringMask
        ring[writeSlot] = incomingSample

        let minCeilingFloor: Double = (mode == .studio) ? 0.84 : 0.89
        let absIn = abs(incomingSample)
        if absIn > tracker.adaptiveCeiling {
            tracker.adaptiveCeiling = min(1.0, 0.88 * tracker.adaptiveCeiling + 0.12 * absIn)
        } else {
            tracker.adaptiveCeiling = max(minCeilingFloor, tracker.adaptiveCeiling * ceilingDecay)
        }

        let cursor = writeSampleIndex - 3
        if cursor >= 4 {
            let cSlot = Int(cursor) & Self.ringMask
            let xc = ring[cSlot]
            let absXc = abs(xc)
            let clipThreshold = max(minCeilingFloor, tracker.adaptiveCeiling * 0.982)
            let signXc: Double = xc >= 0.0 ? 1.0 : -1.0

            if absXc >= clipThreshold {
                if !tracker.inClipRun {
                    tracker.inClipRun = true
                    tracker.runOverflowed = false
                    tracker.runSign = signXc
                    tracker.runStartCursor = cursor
                    tracker.runLength = 1
                    tracker.runMaxAbs = absXc
                } else if signXc == tracker.runSign {
                    tracker.runLength &+= 1
                    if absXc > tracker.runMaxAbs {
                        tracker.runMaxAbs = absXc
                    }
                    if tracker.runLength > maxRunSamples {
                        tracker.runOverflowed = true
                    }
                } else {
                    if !tracker.runOverflowed && tracker.runLength >= 2 && !autoBypass {
                        Self.reconstructRunInRing(
                            ring: &ring,
                            runStart: tracker.runStartCursor,
                            runLength: tracker.runLength,
                            sign: tracker.runSign,
                            plateauMax: tracker.runMaxAbs,
                            mode: mode,
                            peakRestoredDB: &peakRestoredDB,
                            clipsCount: &clipsCount
                        )
                    }
                    tracker.inClipRun = true
                    tracker.runOverflowed = false
                    tracker.runSign = signXc
                    tracker.runStartCursor = cursor
                    tracker.runLength = 1
                    tracker.runMaxAbs = absXc
                }
            } else if tracker.inClipRun {
                if !tracker.runOverflowed && tracker.runLength >= 2 && !autoBypass {
                    Self.reconstructRunInRing(
                        ring: &ring,
                        runStart: tracker.runStartCursor,
                        runLength: tracker.runLength,
                        sign: tracker.runSign,
                        plateauMax: tracker.runMaxAbs,
                        mode: mode,
                        peakRestoredDB: &peakRestoredDB,
                        clipsCount: &clipsCount
                    )
                }
                tracker.inClipRun = false
                tracker.runOverflowed = false
                tracker.runLength = 0
            }
        }

        let readIndex = writeSampleIndex - Int64(Self.lookAheadSamples)
        if readIndex < 0 {
            return 0.0
        }
        return ring[Int(readIndex) & Self.ringMask]
    }

    @usableFromInline
    @inline(__always)
    internal static func reconstructRunInRing(
        ring: inout [Double],
        runStart: Int64,
        runLength: Int,
        sign: Double,
        plateauMax: Double,
        mode: MasteringDeClipMode,
        peakRestoredDB: inout Double,
        clipsCount: inout UInt64
    ) {
        let p0 = ring[Int(runStart - 1) & Self.ringMask]
        let xm2 = ring[Int(runStart - 2) & Self.ringMask]
        let xm3 = ring[Int(runStart - 3) & Self.ringMask]

        let endIdx = runStart + Int64(runLength)
        let p1 = ring[Int(endIdx) & Self.ringMask]
        let xp1 = ring[Int(endIdx + 1) & Self.ringMask]
        let xp2 = ring[Int(endIdx + 2) & Self.ringMask]

        let vIn = 0.65 * (p0 - xm2) + 0.35 * 0.5 * (p0 - xm3)
        let vOut = 0.65 * (xp1 - p1) + 0.35 * 0.5 * (xp2 - p1)

        guard sign * vIn > 0.0012, sign * vOut < -0.0012 else { return }

        let slopeScale: Double
        let maxCrestRatio: Double
        switch mode {
        case .off:
            return
        case .gentle:
            slopeScale = 0.88
            maxCrestRatio = 1.3803842646028852 // +2.80 dB
        case .auto:
            slopeScale = 0.96
            maxCrestRatio = 1.4791083881682075 // +3.40 dB
        case .studio:
            slopeScale = 1.05
            maxCrestRatio = 1.6218100973589299 // +4.20 dB
        }

        let span = Double(runLength + 1)
        let m0 = vIn * span * slopeScale
        let m1 = vOut * span * slopeScale
        let maxAllowedApex = max(plateauMax, min(1.0, plateauMax) * maxCrestRatio)

        var peakBaseAtApex = plateauMax
        var peakBulgeAtApex = 0.0
        var maxUnconstrainedAbs = plateauMax

        let invSpan = 1.0 / span
        for k in 0..<runLength {
            let u = Double(k + 1) * invSpan
            let u2 = u * u
            let u3 = u2 * u
            let base = (2.0 * u3 - 3.0 * u2 + 1.0) * p0 + (-2.0 * u3 + 3.0 * u2) * p1
            let bulge = (u3 - 2.0 * u2 + u) * m0 + (u3 - u2) * m1
            let candidateAbs = sign * (base + bulge)
            if candidateAbs > maxUnconstrainedAbs {
                maxUnconstrainedAbs = candidateAbs
                peakBaseAtApex = sign * base
                peakBulgeAtApex = sign * bulge
            }
        }

        var bulgeScale = 1.0
        if maxUnconstrainedAbs > maxAllowedApex && peakBulgeAtApex > 1e-9 {
            bulgeScale = max(0.0, min(1.0, (maxAllowedApex - peakBaseAtApex) / peakBulgeAtApex))
        }

        var achievedMaxAbs = plateauMax
        for k in 0..<runLength {
            let slot = Int(runStart + Int64(k)) & Self.ringMask
            let orig = ring[slot]
            let u = Double(k + 1) * invSpan
            let u2 = u * u
            let u3 = u2 * u
            let base = (2.0 * u3 - 3.0 * u2 + 1.0) * p0 + (-2.0 * u3 + 3.0 * u2) * p1
            let bulge = ((u3 - 2.0 * u2 + u) * m0 + (u3 - u2) * m1) * bulgeScale
            let reconstructed = base + bulge
            let reconPol = sign * reconstructed
            let origPol = sign * orig
            if reconPol > origPol {
                ring[slot] = reconstructed
                if reconPol > achievedMaxAbs {
                    achievedMaxAbs = reconPol
                }
            }
        }

        if achievedMaxAbs > plateauMax * 1.005 {
            let gainDB = 20.0 * log10(achievedMaxAbs / max(0.05, plateauMax))
            if gainDB > peakRestoredDB {
                peakRestoredDB = gainDB
            }
            clipsCount &+= 1
        }
    }

    // MARK: - Stage 0b: Weiss-Style Relative Sibilance Dynamic De-Esser

    @usableFromInline
    @inline(__always)
    internal func processDeEsserSamplePairLocked(inL: Double, inR: Double) -> (Double, Double) {
        let mode = currentDeEsserMode
        guard mode != .off else { return (inL, inR) }

        let (bandL, bandR) = audioSibBPF.processStereo(inL: inL, inR: inR)
        let (bodyL, bodyR) = scBodyHPF.processStereo(inL: inL, inR: inR)
        let mid = 0.5 * (inL + inR)
        let sibMid = scSibBPF.process(mid)

        let rawPower = 0.5 * (inL * inL + inR * inR)
        if rawPower > envRawPower {
            envRawPower = coeffScEnvAttack * envRawPower + (1.0 - coeffScEnvAttack) * rawPower
        } else {
            envRawPower = coeffScEnvRelease * envRawPower + (1.0 - coeffScEnvRelease) * rawPower
        }

        let bodyPower = 0.5 * (bodyL * bodyL + bodyR * bodyR)
        if bodyPower > envBodyPower {
            envBodyPower = coeffScEnvAttack * envBodyPower + (1.0 - coeffScEnvAttack) * bodyPower
        } else {
            envBodyPower = coeffScEnvRelease * envBodyPower + (1.0 - coeffScEnvRelease) * bodyPower
        }

        let stereoBandPower = 0.5 * (bandL * bandL + bandR * bandR)
        let weightedSibPower = 0.65 * (sibMid * sibMid) + 0.35 * stereoBandPower
        if weightedSibPower > envSibPower {
            envSibPower = coeffScEnvAttack * envSibPower + (1.0 - coeffScEnvAttack) * weightedSibPower
        } else {
            envSibPower = coeffScEnvRelease * envSibPower + (1.0 - coeffScEnvRelease) * weightedSibPower
        }

        var targetCutDB = 0.0
        if envRawPower > 6.3e-7 { // Noise-floor gate @ -62 dBFS
            let ratioLin = (envSibPower + 1e-13) / (envBodyPower + 1e-12)
            let relDB = Double(10.0 * log10f(Float(max(1e-8, ratioLin))))

            let relThresholdDB: Double
            let maxCutDB: Double
            let slope: Double
            let kneeDB: Double
            switch mode {
            case .off:
                relThresholdDB = 0.0; maxCutDB = 0.0; slope = 0.0; kneeDB = 2.0
            case .gentle:
                relThresholdDB = -4.2
                maxCutDB = 3.5
                slope = 0.65
                kneeDB = 2.0
            case .vocal:
                relThresholdDB = -5.5
                maxCutDB = 6.0
                slope = 0.85
                kneeDB = 2.4
            }

            let overDB = relDB - relThresholdDB
            let halfKnee = kneeDB * 0.5
            if overDB > -halfKnee {
                let rawCut: Double
                if overDB < halfKnee {
                    let x = overDB + halfKnee
                    rawCut = slope * (x * x) / (2.0 * kneeDB)
                } else {
                    rawCut = slope * overDB
                }
                targetCutDB = min(maxCutDB, max(0.0, rawCut))
            }
        }

        if targetCutDB > currentDeEssCutDB {
            currentDeEssCutDB = coeffDeEssAttack * currentDeEssCutDB + (1.0 - coeffDeEssAttack) * targetCutDB
        } else {
            currentDeEssCutDB = coeffDeEssRelease * currentDeEssCutDB + (1.0 - coeffDeEssRelease) * targetCutDB
        }

        if currentDeEssCutDB > liveDeEssMeterDB {
            liveDeEssMeterDB = currentDeEssCutDB
        } else {
            liveDeEssMeterDB *= coeffMeterDeEssDecay
        }

        guard currentDeEssCutDB > 0.005 else {
            return (inL, inR)
        }

        let gainAtCenter = Double(expf(Float(-currentDeEssCutDB) * 0.11512925464970229))
        let k = 1.0 - gainAtCenter
        return (inL - k * bandL, inR - k * bandR)
    }

    // MARK: - Headroom & Soft Safety Ceiling Helpers

    @inline(__always)
    public static func outputHeadroomDB(for mode: MasteringDeClipMode, autoBypass: Bool = false) -> Double {
        if autoBypass && mode == .auto {
            return 0.0
        }
        switch mode {
        case .off:
            return 0.0
        case .gentle:
            return -3.0
        case .auto:
            return -3.6
        case .studio:
            return -4.3
        }
    }

    @usableFromInline
    @inline(__always)
    internal static func outputHeadroomLinear(for mode: MasteringDeClipMode, autoBypass: Bool = false) -> Double {
        if autoBypass && mode == .auto {
            return 1.0
        }
        switch mode {
        case .off:
            return 1.0
        case .gentle:
            return 0.7079457843841379 // -3.0 dB
        case .auto:
            return 0.6606934480075959 // -3.6 dB
        case .studio:
            return 0.6095368972401692 // -4.3 dB
        }
    }

    @usableFromInline
    @inline(__always)
    internal static func softSafetyCeiling(_ x: Double) -> Double {
        let absX = abs(x)
        if absX <= 0.95 {
            return x
        }
        let excess = absX - 0.95
        let compressed = 0.95 + 0.042 * (excess / (0.042 + excess))
        return x >= 0.0 ? compressed : -compressed
    }
}
