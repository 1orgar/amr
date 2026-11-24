//
//  TrellisViterbiModulator+M1Kernel.swift
//  AppleMusicRemoteMac
//
//  Register-Only Steady-State Kernel for M = 1 (Single-Path Control-Lyapunov Lookahead).
//

import simd

extension TrellisViterbiModulator {

    /// Полностью регистровое ядро стационарного блока для `M = 1` (0 вызовов подпрограмм и 0 `inout`-проверок эксклюзивности).
    @inline(__always)
    @usableFromInline
    internal static func processSteadyBlockM1(
        inputSamples: UnsafePointer<Double>,
        sampleCount: Int,
        byteCount: Int,
        tailNextSample: Double,
        dsdOutputBytes: UnsafeMutablePointer<UInt8>,
        isiOn: Bool,
        ditherAmp: Double,
        coeffs: SDM7SectionCoefficients,
        survAPtr: UnsafeMutablePointer<TrellisCandidatePath>,
        initialPeakAmp: Double,
        initialPrngS0: UInt64,
        initialPrngS1: UInt64
    ) -> (curCount: Int, peakAmp: Double, prngS0: UInt64, prngS1: UInt64) {
        let b0 = coeffs.b0
        let a1 = coeffs.aLink01.x; let a2 = coeffs.aLink01.y; let a3 = coeffs.aLink2Pad.x
        let g1 = coeffs.gFeedback01.x; let g2 = coeffs.gFeedback01.y; let g3 = coeffs.gFeedback2Pad.x
        let c1 = coeffs.cIntegrator01.x; let c2 = coeffs.cIntegrator01.y; let c3 = coeffs.cIntegrator2Pad.x
        let ff0 = coeffs.ff01.x; let ff1 = coeffs.ff01.y
        let ff2 = coeffs.ff23.x; let ff3 = coeffs.ff23.y
        let ff4 = coeffs.ff45.x; let ff5 = coeffs.ff45.y; let ff6 = coeffs.ff6IsiPad.x
        let o0_0 = coeffs.obs0_01.x; let o0_1 = coeffs.obs0_01.y; let o0_2 = coeffs.obs0_23.x
        let o0_3 = coeffs.obs0_23.y; let o0_4 = coeffs.obs0_45.x; let o0_5 = coeffs.obs0_45.y; let o0_6 = coeffs.obs0_6Pad.x
        let o1_0 = coeffs.obs1_01.x; let o1_1 = coeffs.obs1_01.y; let o1_2 = coeffs.obs1_23.x
        let o1_3 = coeffs.obs1_23.y; let o1_4 = coeffs.obs1_45.x; let o1_5 = coeffs.obs1_45.y; let o1_6 = coeffs.obs1_6Pad.x

        let q0_0 = o0_0 + a1 * o0_1 + (c1 * a1) * o0_2
        let q0_1 = o0_1 + c1 * o0_2
        let q0_2 = -g1 * o0_1 + (1.0 - c1 * g1) * o0_2 + a2 * o0_3 + (c2 * a2) * o0_4
        let q0_3 = o0_3 + c2 * o0_4
        let q0_4 = -g2 * o0_3 + (1.0 - c2 * g2) * o0_4 + a3 * o0_5 + (c3 * a3) * o0_6
        let q0_5 = o0_5 + c3 * o0_6
        let q0_6 = -g3 * o0_5 + (1.0 - c3 * g3) * o0_6

        let q1_0 = o1_0 + a1 * o1_1 + (c1 * a1) * o1_2
        let q1_1 = o1_1 + c1 * o1_2
        let q1_2 = -g1 * o1_1 + (1.0 - c1 * g1) * o1_2 + a2 * o1_3 + (c2 * a2) * o1_4
        let q1_3 = o1_3 + c2 * o1_4
        let q1_4 = -g2 * o1_3 + (1.0 - c2 * g2) * o1_4 + a3 * o1_5 + (c3 * a3) * o1_6
        let q1_5 = o1_5 + c3 * o1_6
        let q1_6 = -g3 * o1_5 + (1.0 - c3 * g3) * o1_6

        let ff01Vec = coeffs.ff01; let ff23Vec = coeffs.ff23; let ff45Vec = coeffs.ff45
        let ff12Vec = SIMD2<Double>(ff1, ff2); let ff34Vec = SIMD2<Double>(ff3, ff4); let ff56Vec = SIMD2<Double>(ff5, ff6)
        let q0_12Vec = SIMD2<Double>(q0_1, q0_2); let q0_34Vec = SIMD2<Double>(q0_3, q0_4); let q0_56Vec = SIMD2<Double>(q0_5, q0_6)
        let q1_12Vec = SIMD2<Double>(q1_1, q1_2); let q1_34Vec = SIMD2<Double>(q1_3, q1_4); let q1_56Vec = SIMD2<Double>(q1_5, q1_6)
        let aLink01Vec = coeffs.aLink01; let gFeed01Vec = coeffs.gFeedback01; let cInt01Vec = coeffs.cIntegrator01
        let aLink12Vec = SIMD2<Double>(a2, a3); let gFeed12Vec = SIMD2<Double>(g2, g3); let cInt12Vec = SIMD2<Double>(c2, c3)
        let obs0_34Vec = SIMD2<Double>(o0_3, o0_4); let obs0_56Vec = SIMD2<Double>(o0_5, o0_6)
        let obs1_34Vec = SIMD2<Double>(o1_3, o1_4); let obs1_56Vec = SIMD2<Double>(o1_5, o1_6)
        let y0Vec = SIMD2<Double>(-1.0, 1.0)
        let b0Y0Vec = SIMD2<Double>(-b0, b0)
        let isiLam = coeffs.isiLambda
        let thr = coeffs.softClipThreshold
        let thrVec = SIMD2<Double>(repeating: thr)

        let lim = fmin2(thr, 1.14)
        let L1 = 1.0 + a1 + g1; let L2 = 1.0 + c1 * L1
        let L3 = 1.0 + a2 + g2; let L4 = 1.0 + c2 * L3
        let L5 = 1.0 + a3 + g3; let L6 = 1.0 + c3 * L5
        let L1_2 = L1 + a1 + g1 * L2; let L2_2 = L2 + c1 * L1_2
        let L3_2 = L3 + a2 * L2 + g2 * L4; let L4_2 = L4 + c2 * L3_2
        let L5_2 = L5 + a3 * L4 + g3 * L6; let L6_2 = L6 + c3 * L5_2
        let maxPureResL = fmax2(
            fmax2(fmax2(L1, L2), fmax2(L3, L4)),
            fmax2(fmax2(L5, L6), fmax2(fmax2(L3_2, L4_2), fmax2(L5_2, L6_2)))
        )
        let resPureBound = lim / maxPureResL
        let invL1_2 = 1.0 / L1_2
        let invL2_2 = 1.0 / L2_2

        let p0 = survAPtr[0]
        var ps01 = p0.state.s01
        var ps23 = p0.state.s23
        var ps45 = p0.state.s45
        var ps6I = p0.state.s6Isi
        var pHist = p0.history
        var lastY = p0.lastY
        var maxPeak = initialPeakAmp
        var rng0 = initialPrngS0
        var rng1 = initialPrngS1

        var sampleIdx = 0
        for byteIdx in 0..<byteCount {
            var packedByte: UInt8 = 0
            for bitPos in 0..<8 {
                let u0 = inputSamples[sampleIdx]
                let u1 = (sampleIdx &+ 1 < sampleCount) ? inputSamples[sampleIdx &+ 1] : tailNextSample
                sampleIdx &+= 1

                let dither: Double
                if ditherAmp > 0.0 {
                    let rA = rng0 &+ rng1
                    let x0 = rng1 ^ rng0
                    rng0 = ((rng0 << 24) | (rng0 >> 40)) ^ x0 ^ (x0 << 16)
                    rng1 = (x0 << 37) | (x0 >> 27)
                    let rB = rng0 &+ rng1
                    let x1 = rng1 ^ rng0
                    rng0 = ((rng0 << 24) | (rng0 >> 40)) ^ x1 ^ (x1 << 16)
                    rng1 = (x1 << 37) | (x1 >> 27)
                    let uA = Double(rA >> 11) * 0x1.0p-53 - 0.5
                    let uB = Double(rB >> 11) * 0x1.0p-53 - 0.5
                    dither = (uA + uB) * ditherAmp
                } else {
                    dither = 0.0
                }

                let du0Max = b0 * (1.0 + u0.magnitude)
                let du01Max = du0Max + b0 * (1.0 + u1.magnitude)
                let bitLinBound = fmin2(
                    lim - du01Max,
                    fmin2(
                        resPureBound,
                        fmin2(
                            (lim - a1 * du0Max) * invL1_2,
                            (lim - c1 * a1 * du0Max) * invL2_2
                        )
                    )
                )

                let max03 = simd_max(simd_abs(ps01), simd_abs(ps23))
                let max05 = simd_max(max03, simd_abs(ps45))
                let pMaxState = fmax2(fmax2(max05.x, max05.y), ps6I.x.magnitude)
                let bPrev1 = pHist & 1

                let s12: SIMD2<Double>
                let s34: SIMD2<Double>
                let s56: SIMD2<Double>
                let ns0Vec: SIMD2<Double>
                let rankVec: SIMD2<Double>

                if pMaxState <= bitLinBound {
                    let ffSum = (ff01Vec * ps01 + ff23Vec * ps23) + ff45Vec * ps45
                    let v0 = u0 + (ffSum.x + ffSum.y) + ff6 * ps6I.x + dither
                    let oddInC = SIMD2<Double>(ps23.x, ps45.x)
                    let raw13 = SIMD2<Double>(ps01.y, ps23.y) + aLink01Vec * SIMD2<Double>(ps01.x, ps23.x) - gFeed01Vec * oddInC
                    let raw24 = oddInC + cInt01Vec * raw13
                    let raw5 = ps45.y + a3 * ps45.x - g3 * ps6I.x
                    let raw6 = ps6I.x + c3 * raw5
                    s12 = SIMD2<Double>(raw13.x, raw24.x)
                    s34 = SIMD2<Double>(raw13.y, raw24.y)
                    s56 = SIMD2<Double>(raw5, raw6)

                    var isiVec = SIMD2<Double>.zero
                    if isiOn && v0.magnitude < 1.0e-4 {
                        let maxHi0 = fmax2(fmax2(ps23.y.magnitude, maxAbsSIMD2(ps45)), ps6I.x.magnitude)
                        if maxHi0 < 0.14 {
                            let bPrev2 = (pHist >> 1) & 1
                            let pulseCost = (bPrev1 != bPrev2) ? 1.5e-4 : 0.0
                            let chatterExcess = fmax2(0.0, ps6I.y - 0.46)
                            let w = 1.0 - v0.magnitude * (1.0 / 1.0e-4)
                            let pen = isiLam * (w * w) * (pulseCost + 6.0e-4 * chatterExcess)
                            isiVec = (bPrev1 == 1) ? SIMD2<Double>(pen, 0.0) : SIMD2<Double>(0.0, pen)
                        }
                    }

                    ns0Vec = SIMD2<Double>(repeating: ps01.x + b0 * u0) - b0Y0Vec
                    let err0Vec = SIMD2<Double>(repeating: v0) - y0Vec
                    let v1Pair = (ff12Vec * s12 + ff34Vec * s34) + ff56Vec * s56
                    let p0Pair = (q0_12Vec * s12 + q0_34Vec * s34) + q0_56Vec * s56
                    let p1Pair = (q1_12Vec * s12 + q1_34Vec * s34) + q1_56Vec * s56
                    let v1Vec = SIMD2<Double>(repeating: u1 + (v1Pair.x + v1Pair.y)) + ff0 * ns0Vec
                    let y1Vec = SIMD2<Double>(v1Vec.x >= 0.0 ? 1.0 : -1.0, v1Vec.y >= 0.0 ? 1.0 : -1.0)
                    let err1Vec = v1Vec - y1Vec
                    let du1Vec = SIMD2<Double>(repeating: b0 * u1) - b0 * y1Vec
                    let p0Vec = SIMD2<Double>(repeating: p0Pair.x + p0Pair.y) + q0_0 * ns0Vec + o0_0 * du1Vec
                    let p1Vec = SIMD2<Double>(repeating: p1Pair.x + p1Pair.y) + q1_0 * ns0Vec + o1_0 * du1Vec
                    rankVec = (err0Vec * err0Vec) + isiVec + 0.85 * (err1Vec * err1Vec) + 0.25 * (p0Vec * p0Vec + p1Vec * p1Vec)
                } else {
                    let maxHi0 = fmax2(fmax2(ps23.y.magnitude, maxAbsSIMD2(ps45)), ps6I.x.magnitude)
                    let oddInC = SIMD2<Double>(ps23.x, ps45.x)
                    let v0: Double
                    let raw13: SIMD2<Double>
                    let raw5: Double
                    if maxHi0 <= 1.14 {
                        let ffSum = (ff01Vec * ps01 + ff23Vec * ps23) + ff45Vec * ps45
                        v0 = u0 + (ffSum.x + ffSum.y) + ff6 * ps6I.x + dither
                        raw13 = SIMD2<Double>(ps01.y, ps23.y) + aLink01Vec * SIMD2<Double>(ps01.x, ps23.x) - gFeed01Vec * oddInC
                        raw5 = ps45.y + a3 * ps45.x - g3 * ps6I.x
                    } else {
                        let gov0 = fmin2(0.85, (maxHi0 - 1.14) * (1.0 / 0.30))
                        v0 = u0 + (ff0 * ps01.x + ff1 * ps01.y + ff2 * ps23.x)
                            + (1.0 - 0.50 * gov0) * (ff3 * ps23.y + ff4 * ps45.x)
                            + (1.0 - 0.85 * gov0) * (ff5 * ps45.y + ff6 * ps6I.x) + dither
                        raw13 = SIMD2<Double>(ps01.y, ps23.y) + SIMD2<Double>(a1, (1.0 - 0.45 * gov0) * a2) * SIMD2<Double>(ps01.x, ps23.x) - gFeed01Vec * oddInC
                        raw5 = ps45.y + ((1.0 - 0.80 * gov0) * a3) * ps45.x - g3 * ps6I.x
                    }

                    let sharedBar1: Double
                    if fmax2(maxAbsSIMD2(raw13), raw5.magnitude) <= thr {
                        let raw24 = oddInC + cInt01Vec * raw13
                        let raw6 = ps6I.x + c3 * raw5
                        if fmax2(maxAbsSIMD2(raw24), raw6.magnitude) <= thr {
                            s12 = SIMD2<Double>(raw13.x, raw24.x)
                            s34 = SIMD2<Double>(raw13.y, raw24.y)
                            s56 = SIMD2<Double>(raw5, raw6)
                            sharedBar1 = 0.0
                        } else {
                            s12 = SIMD2<Double>(raw13.x, BiquadLatticeState.softCeiling(raw24.x))
                            s34 = SIMD2<Double>(raw13.y, BiquadLatticeState.softCeiling(raw24.y))
                            s56 = SIMD2<Double>(raw5, BiquadLatticeState.softCeiling(raw6))
                            let ex24 = simd_max(SIMD2<Double>.zero, simd_abs(raw24) - thrVec)
                            let ex6 = fmax2(0.0, raw6.magnitude - thr)
                            let sq24 = ex24 * ex24
                            sharedBar1 = sq24.x + sq24.y + ex6 * ex6
                        }
                    } else {
                        let ns1 = BiquadLatticeState.softCeiling(raw13.x)
                        let ns3 = BiquadLatticeState.softCeiling(raw13.y)
                        let ns5 = BiquadLatticeState.softCeiling(raw5)
                        let raw24 = oddInC + cInt01Vec * SIMD2<Double>(ns1, ns3)
                        let raw6 = ps6I.x + c3 * ns5
                        s12 = SIMD2<Double>(ns1, BiquadLatticeState.softCeiling(raw24.x))
                        s34 = SIMD2<Double>(ns3, BiquadLatticeState.softCeiling(raw24.y))
                        s56 = SIMD2<Double>(ns5, BiquadLatticeState.softCeiling(raw6))
                        let ex13 = simd_max(SIMD2<Double>.zero, simd_abs(raw13) - thrVec)
                        let ex24 = simd_max(SIMD2<Double>.zero, simd_abs(raw24) - thrVec)
                        let ex56 = simd_max(SIMD2<Double>.zero, simd_abs(SIMD2<Double>(raw5, raw6)) - thrVec)
                        let sq = ex13 * ex13 + ex24 * ex24 + ex56 * ex56
                        sharedBar1 = sq.x + sq.y
                    }

                    let maxHi1 = fmax2(maxAbsSIMD2(s34), maxAbsSIMD2(s56))
                    let s46_1 = SIMD2<Double>(s34.y, s56.y)
                    let v1Tail: Double; let raw35_2: SIMD2<Double>
                    if maxHi1 <= 1.14 {
                        let v1Pair = (ff12Vec * s12 + ff34Vec * s34) + ff56Vec * s56
                        v1Tail = u1 + (v1Pair.x + v1Pair.y)
                        raw35_2 = SIMD2<Double>(s34.x, s56.x) + aLink12Vec * SIMD2<Double>(s12.y, s34.y) - gFeed12Vec * s46_1
                    } else {
                        let gov1 = fmin2(0.85, (maxHi1 - 1.14) * (1.0 / 0.30))
                        let p12 = ff12Vec * s12; let p34 = ff34Vec * s34; let p56 = ff56Vec * s56
                        v1Tail = u1 + (p12.x + p12.y) + (1.0 - 0.50 * gov1) * (p34.x + p34.y) + (1.0 - 0.85 * gov1) * (p56.x + p56.y)
                        raw35_2 = SIMD2<Double>(s34.x, s56.x) + SIMD2<Double>((1.0 - 0.45 * gov1) * a2, (1.0 - 0.80 * gov1) * a3) * SIMD2<Double>(s12.y, s34.y) - gFeed12Vec * s46_1
                    }

                    let ns34_2: SIMD2<Double>; let ns56_2: SIMD2<Double>; let sharedBar2: Double
                    if maxAbsSIMD2(raw35_2) <= thr {
                        let raw46_2 = s46_1 + cInt12Vec * raw35_2
                        if maxAbsSIMD2(raw46_2) <= thr {
                            ns34_2 = SIMD2<Double>(raw35_2.x, raw46_2.x)
                            ns56_2 = SIMD2<Double>(raw35_2.y, raw46_2.y)
                            sharedBar2 = 0.0
                        } else {
                            ns34_2 = SIMD2<Double>(raw35_2.x, BiquadLatticeState.softCeiling(raw46_2.x))
                            ns56_2 = SIMD2<Double>(raw35_2.y, BiquadLatticeState.softCeiling(raw46_2.y))
                            let ex46 = simd_max(SIMD2<Double>.zero, simd_abs(raw46_2) - thrVec)
                            let sq = ex46 * ex46; sharedBar2 = sq.x + sq.y
                        }
                    } else {
                        let ns3_2 = BiquadLatticeState.softCeiling(raw35_2.x)
                        let ns5_2 = BiquadLatticeState.softCeiling(raw35_2.y)
                        let raw46_2 = s46_1 + cInt12Vec * SIMD2<Double>(ns3_2, ns5_2)
                        ns34_2 = SIMD2<Double>(ns3_2, BiquadLatticeState.softCeiling(raw46_2.x))
                        ns56_2 = SIMD2<Double>(ns5_2, BiquadLatticeState.softCeiling(raw46_2.y))
                        let ex35 = simd_max(SIMD2<Double>.zero, simd_abs(raw35_2) - thrVec)
                        let ex46 = simd_max(SIMD2<Double>.zero, simd_abs(raw46_2) - thrVec)
                        let sq = ex35 * ex35 + ex46 * ex46; sharedBar2 = sq.x + sq.y
                    }

                    let o0Pair = obs0_34Vec * ns34_2 + obs0_56Vec * ns56_2
                    let obs0Tail = o0Pair.x + o0Pair.y
                    let o1Pair = obs1_34Vec * ns34_2 + obs1_56Vec * ns56_2
                    let obs1Tail = o1Pair.x + o1Pair.y

                    var isiVec = SIMD2<Double>.zero
                    if isiOn && v0.magnitude < 1.0e-4 && maxHi0 < 0.14 {
                        let bPrev2 = (pHist >> 1) & 1
                        let pulseCost = (bPrev1 != bPrev2) ? 1.5e-4 : 0.0
                        let chatterExcess = fmax2(0.0, ps6I.y - 0.46)
                        let w = 1.0 - v0.magnitude * (1.0 / 1.0e-4)
                        let pen = isiLam * (w * w) * (pulseCost + 6.0e-4 * chatterExcess)
                        isiVec = (bPrev1 == 1) ? SIMD2<Double>(pen, 0.0) : SIMD2<Double>(0.0, pen)
                    }

                    let raw0Vec = SIMD2<Double>(repeating: ps01.x + b0 * u0) - b0Y0Vec
                    let bar1Vec: SIMD2<Double>
                    if maxAbsSIMD2(raw0Vec) <= thr {
                        ns0Vec = raw0Vec; bar1Vec = SIMD2<Double>(repeating: sharedBar1)
                    } else {
                        ns0Vec = SIMD2<Double>(BiquadLatticeState.softCeiling(raw0Vec.x), BiquadLatticeState.softCeiling(raw0Vec.y))
                        let ex0 = simd_max(SIMD2<Double>.zero, simd_abs(raw0Vec) - thrVec)
                        bar1Vec = SIMD2<Double>(repeating: sharedBar1) + ex0 * ex0
                    }
                    let err0Vec = SIMD2<Double>(repeating: v0) - y0Vec
                    let v1Vec = SIMD2<Double>(repeating: v1Tail) + ff0 * ns0Vec
                    let y1Vec = SIMD2<Double>(v1Vec.x >= 0.0 ? 1.0 : -1.0, v1Vec.y >= 0.0 ? 1.0 : -1.0)
                    let err1Vec = v1Vec - y1Vec
                    let raw0_2Vec = ns0Vec + (SIMD2<Double>(repeating: b0 * u1) - b0 * y1Vec)
                    let raw1_2Vec = SIMD2<Double>(repeating: s12.x - g1 * s12.y) + a1 * ns0Vec

                    let ns0_2Vec: SIMD2<Double>; let ns1_2Vec: SIMD2<Double>; let ns2_2Vec: SIMD2<Double>; let bar2Vec: SIMD2<Double>
                    if fmax2(maxAbsSIMD2(raw0_2Vec), maxAbsSIMD2(raw1_2Vec)) <= thr {
                        ns0_2Vec = raw0_2Vec; ns1_2Vec = raw1_2Vec
                        let raw2_2Vec = SIMD2<Double>(repeating: s12.y) + c1 * raw1_2Vec
                        if maxAbsSIMD2(raw2_2Vec) <= thr {
                            ns2_2Vec = raw2_2Vec; bar2Vec = SIMD2<Double>(repeating: sharedBar2)
                        } else {
                            ns2_2Vec = SIMD2<Double>(BiquadLatticeState.softCeiling(raw2_2Vec.x), BiquadLatticeState.softCeiling(raw2_2Vec.y))
                            let ex2 = simd_max(SIMD2<Double>.zero, simd_abs(raw2_2Vec) - thrVec)
                            bar2Vec = SIMD2<Double>(repeating: sharedBar2) + ex2 * ex2
                        }
                    } else {
                        ns0_2Vec = SIMD2<Double>(BiquadLatticeState.softCeiling(raw0_2Vec.x), BiquadLatticeState.softCeiling(raw0_2Vec.y))
                        ns1_2Vec = SIMD2<Double>(BiquadLatticeState.softCeiling(raw1_2Vec.x), BiquadLatticeState.softCeiling(raw1_2Vec.y))
                        let raw2_2Vec = SIMD2<Double>(repeating: s12.y) + c1 * ns1_2Vec
                        ns2_2Vec = SIMD2<Double>(BiquadLatticeState.softCeiling(raw2_2Vec.x), BiquadLatticeState.softCeiling(raw2_2Vec.y))
                        let ex0 = simd_max(SIMD2<Double>.zero, simd_abs(raw0_2Vec) - thrVec)
                        let ex1 = simd_max(SIMD2<Double>.zero, simd_abs(raw1_2Vec) - thrVec)
                        let ex2 = simd_max(SIMD2<Double>.zero, simd_abs(raw2_2Vec) - thrVec)
                        bar2Vec = SIMD2<Double>(repeating: sharedBar2) + ex0 * ex0 + ex1 * ex1 + ex2 * ex2
                    }
                    let p0Vec = SIMD2<Double>(repeating: obs0Tail) + o0_0 * ns0_2Vec + o0_1 * ns1_2Vec + o0_2 * ns2_2Vec
                    let p1Vec = SIMD2<Double>(repeating: obs1Tail) + o1_0 * ns0_2Vec + o1_1 * ns1_2Vec + o1_2 * ns2_2Vec
                    rankVec = (err0Vec * err0Vec) + 24.0 * bar1Vec + isiVec + 0.85 * (err1Vec * err1Vec) + 0.25 * (p0Vec * p0Vec + p1Vec * p1Vec) + 36.0 * bar2Vec
                }

                let choosePos = rankVec.y <= rankVec.x
                let chosenBit: UInt64 = choosePos ? 1 : 0
                let chosenNs0 = choosePos ? ns0Vec.y : ns0Vec.x
                let nextIsiVal = 0.90 * ps6I.y + ((bPrev1 != chosenBit) ? 0.10 : 0.0)
                ps01 = SIMD2<Double>(chosenNs0, s12.x)
                ps23 = SIMD2<Double>(s12.y, s34.x)
                ps45 = SIMD2<Double>(s34.y, s56.x)
                ps6I = SIMD2<Double>(s56.y, nextIsiVal)
                pHist = (pHist << 1) | chosenBit
                lastY = choosePos ? 1.0 : -1.0

                let amp = fmax2(fmax2(maxAbsSIMD2(ps01), maxAbsSIMD2(ps23)), fmax2(maxAbsSIMD2(ps45), ps6I.x.magnitude))
                if amp > maxPeak { maxPeak = amp }
                if choosePos {
                    packedByte |= (UInt8(0x80) >> UInt8(bitPos))
                }
            }
            dsdOutputBytes[byteIdx] = packedByte
        }

        survAPtr[0] = TrellisCandidatePath(
            state: BiquadLatticeState(s01: ps01, s23: ps23, s45: ps45, s6Isi: ps6I),
            cost: 0.0,
            history: pHist,
            lastY: lastY
        )
        return (1, maxPeak, rng0, rng1)
    }
}
