//
//  TrellisViterbiModulator+SoATrellis.swift
//  AppleMusicRemoteMac
//
//  Full Non-Linear SoA + SIMD2 NEON Steady-State Kernel for M in {4, 8, 16} with Soft-Ceiling Overload Barrier.
//

import simd

extension TrellisViterbiModulator {

    /// Высокопроизводительное SoA + SIMD2 NEON ядро стационарного блока для `M in {4, 8, 16}`:
    /// - 0 вызовов `Swift.abs` / `Swift.max` / `_memcpy` / `_swift_beginAccess` внутри горячего цикла;
    /// - Предтранспонированный линейный проектор грамиана наблюдаемости `q = A^T * o` (`0.0` потерь точности);
    /// - 64-битное монотонное представление рангов `UInt64` в сети Бэтчера Top-8.
    @inline(never)
    @usableFromInline
    internal static func processSteadyBlockTrellis(
        inputSamples: UnsafePointer<Double>,
        sampleCount: Int,
        byteCount: Int,
        tailNextSample: Double,
        dsdOutputBytes: UnsafeMutablePointer<UInt8>,
        maxSurvivors: Int,
        L: Int,
        isiOn: Bool,
        ditherAmp: Double,
        coeffs: SDM7SectionCoefficients,
        survAPtr: UnsafeMutablePointer<TrellisCandidatePath>,
        scratchRaw: UnsafeMutableRawPointer,
        initialCurCount: Int,
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

        let ff01Vec    = coeffs.ff01
        let ff23Vec    = coeffs.ff23
        let ff45Vec    = coeffs.ff45
        let ff12Vec    = SIMD2<Double>(ff1, ff2)
        let ff34Vec    = SIMD2<Double>(ff3, ff4)
        let ff56Vec    = SIMD2<Double>(ff5, ff6)
        let q0_12Vec   = SIMD2<Double>(q0_1, q0_2)
        let q0_34Vec   = SIMD2<Double>(q0_3, q0_4)
        let q0_56Vec   = SIMD2<Double>(q0_5, q0_6)
        let q1_12Vec   = SIMD2<Double>(q1_1, q1_2)
        let q1_34Vec   = SIMD2<Double>(q1_3, q1_4)
        let q1_56Vec   = SIMD2<Double>(q1_5, q1_6)
        let aLink01Vec = coeffs.aLink01
        let gFeed01Vec = coeffs.gFeedback01
        let cInt01Vec  = coeffs.cIntegrator01
        let aLink12Vec = SIMD2<Double>(a2, a3)
        let gFeed12Vec = SIMD2<Double>(g2, g3)
        let cInt12Vec  = SIMD2<Double>(c2, c3)
        let obs0_34Vec = SIMD2<Double>(o0_3, o0_4)
        let obs0_56Vec = SIMD2<Double>(o0_5, o0_6)
        let obs1_34Vec = SIMD2<Double>(o1_3, o1_4)
        let obs1_56Vec = SIMD2<Double>(o1_5, o1_6)
        let y0Vec      = SIMD2<Double>(-1.0, 1.0)
        let b0Y0Vec    = SIMD2<Double>(-b0, b0)
        let isiLam     = coeffs.isiLambda
        let thr        = coeffs.softClipThreshold
        let thrVec     = SIMD2<Double>(repeating: thr)

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

        // SoA Ping-Pong Bank A (0..<1280) & Bank B (1280..<2560)
        var srcS01  = scratchRaw.advanced(by: 0).assumingMemoryBound(to: SIMD2<Double>.self)
        var srcS23  = scratchRaw.advanced(by: 256).assumingMemoryBound(to: SIMD2<Double>.self)
        var srcS45  = scratchRaw.advanced(by: 512).assumingMemoryBound(to: SIMD2<Double>.self)
        var srcS6I  = scratchRaw.advanced(by: 768).assumingMemoryBound(to: SIMD2<Double>.self)
        var srcCost = scratchRaw.advanced(by: 1024).assumingMemoryBound(to: Double.self)
        var srcHist = scratchRaw.advanced(by: 1152).assumingMemoryBound(to: UInt64.self)

        var dstS01  = scratchRaw.advanced(by: 1280).assumingMemoryBound(to: SIMD2<Double>.self)
        var dstS23  = scratchRaw.advanced(by: 1536).assumingMemoryBound(to: SIMD2<Double>.self)
        var dstS45  = scratchRaw.advanced(by: 1792).assumingMemoryBound(to: SIMD2<Double>.self)
        var dstS6I  = scratchRaw.advanced(by: 2048).assumingMemoryBound(to: SIMD2<Double>.self)
        var dstCost = scratchRaw.advanced(by: 2304).assumingMemoryBound(to: Double.self)
        var dstHist = scratchRaw.advanced(by: 2432).assumingMemoryBound(to: UInt64.self)

        // Candidate Scratch (2560..<4864)
        let sharedS12Ptr = scratchRaw.advanced(by: 2560).assumingMemoryBound(to: SIMD2<Double>.self)
        let sharedS34Ptr = scratchRaw.advanced(by: 2816).assumingMemoryBound(to: SIMD2<Double>.self)
        let sharedS56Ptr = scratchRaw.advanced(by: 3072).assumingMemoryBound(to: SIMD2<Double>.self)
        let rankPtr      = scratchRaw.advanced(by: 3328).assumingMemoryBound(to: Double.self)
        let gCostPtr     = scratchRaw.advanced(by: 3584).assumingMemoryBound(to: Double.self)
        let ns0Ptr       = scratchRaw.advanced(by: 3840).assumingMemoryBound(to: Double.self)
        let nextIsiPtr   = scratchRaw.advanced(by: 4096).assumingMemoryBound(to: Double.self)
        let histPtr      = scratchRaw.advanced(by: 4352).assumingMemoryBound(to: UInt64.self)
        let vIdxPtr      = scratchRaw.advanced(by: 4608).assumingMemoryBound(to: Int32.self)
        let selIdxPtr    = scratchRaw.advanced(by: 4736).assumingMemoryBound(to: Int32.self)

        var nSurv = initialCurCount
        var maxPeak = initialPeakAmp
        var rng0 = initialPrngS0
        var rng1 = initialPrngS1

        for i in 0..<nSurv {
            let p = survAPtr[i]
            srcS01[i]  = p.state.s01
            srcS23[i]  = p.state.s23
            srcS45[i]  = p.state.s45
            srcS6I[i]  = p.state.s6Isi
            srcCost[i] = p.cost
            srcHist[i] = p.history
        }

        let shiftL = UInt64(L)
        let discount = 0.92
        let validKeyLimit: UInt64 = 0x7FF0_0000_0000_0000
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

                let b0U1Vec = SIMD2<Double>(repeating: b0 * u1)
                let b0U0 = b0 * u0
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

                var expCount = 0

                for idx in 0..<nSurv {
                    let ps01 = srcS01[idx]
                    let ps23 = srcS23[idx]
                    let ps45 = srcS45[idx]
                    let ps6I = srcS6I[idx]
                    let pHist = srcHist[idx]
                    let baseCost = discount * srcCost[idx]
                    let bPrev1 = pHist & 1
                    let decayedIsi = 0.90 * ps6I.y

                    let max03 = simd_max(simd_abs(ps01), simd_abs(ps23))
                    let max05 = simd_max(max03, simd_abs(ps45))
                    let pMaxState = fmax2(fmax2(max05.x, max05.y), ps6I.x.magnitude)

                    let ns0Vec: SIMD2<Double>
                    let gVec: SIMD2<Double>
                    let fVec: SIMD2<Double>

                    if pMaxState <= bitLinBound {
                        let ffSum = (ff01Vec * ps01 + ff23Vec * ps23) + ff45Vec * ps45
                        let v0 = u0 + (ffSum.x + ffSum.y) + ff6 * ps6I.x + dither
                        let oddInC = SIMD2<Double>(ps23.x, ps45.x)
                        let raw13 = SIMD2<Double>(ps01.y, ps23.y) + aLink01Vec * SIMD2<Double>(ps01.x, ps23.x) - gFeed01Vec * oddInC
                        let raw24 = oddInC + cInt01Vec * raw13
                        let raw5 = ps45.y + a3 * ps45.x - g3 * ps6I.x
                        let raw6 = ps6I.x + c3 * raw5

                        let s12 = SIMD2<Double>(raw13.x, raw24.x)
                        let s34 = SIMD2<Double>(raw13.y, raw24.y)
                        let s56 = SIMD2<Double>(raw5, raw6)
                        sharedS12Ptr[idx] = s12
                        sharedS34Ptr[idx] = s34
                        sharedS56Ptr[idx] = s56

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

                        ns0Vec = SIMD2<Double>(repeating: ps01.x + b0U0) - b0Y0Vec
                        let err0Vec = SIMD2<Double>(repeating: v0) - y0Vec
                        gVec = SIMD2<Double>(repeating: baseCost) + err0Vec * err0Vec + isiVec

                        let v1Pair = (ff12Vec * s12 + ff34Vec * s34) + ff56Vec * s56
                        let p0Pair = (q0_12Vec * s12 + q0_34Vec * s34) + q0_56Vec * s56
                        let p1Pair = (q1_12Vec * s12 + q1_34Vec * s34) + q1_56Vec * s56
                        let v1Vec = SIMD2<Double>(repeating: u1 + (v1Pair.x + v1Pair.y)) + ff0 * ns0Vec
                        let y1Vec = SIMD2<Double>(v1Vec.x >= 0.0 ? 1.0 : -1.0, v1Vec.y >= 0.0 ? 1.0 : -1.0)
                        let err1Vec = v1Vec - y1Vec
                        let du1Vec = b0U1Vec - b0 * y1Vec
                        let p0Vec = SIMD2<Double>(repeating: p0Pair.x + p0Pair.y) + q0_0 * ns0Vec + o0_0 * du1Vec
                        let p1Vec = SIMD2<Double>(repeating: p1Pair.x + p1Pair.y) + q1_0 * ns0Vec + o1_0 * du1Vec
                        fVec = gVec + 0.85 * (err1Vec * err1Vec) + 0.25 * (p0Vec * p0Vec + p1Vec * p1Vec)
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

                        let s12: SIMD2<Double>; let s34: SIMD2<Double>; let s56: SIMD2<Double>; let sharedBar1: Double
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

                        sharedS12Ptr[idx] = s12
                        sharedS34Ptr[idx] = s34
                        sharedS56Ptr[idx] = s56

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

                        let raw0Vec = SIMD2<Double>(repeating: ps01.x + b0U0) - b0Y0Vec
                        let bar1Vec: SIMD2<Double>
                        if maxAbsSIMD2(raw0Vec) <= thr {
                            ns0Vec = raw0Vec; bar1Vec = SIMD2<Double>(repeating: sharedBar1)
                        } else {
                            ns0Vec = SIMD2<Double>(BiquadLatticeState.softCeiling(raw0Vec.x), BiquadLatticeState.softCeiling(raw0Vec.y))
                            let ex0 = simd_max(SIMD2<Double>.zero, simd_abs(raw0Vec) - thrVec)
                            bar1Vec = SIMD2<Double>(repeating: sharedBar1) + ex0 * ex0
                        }

                        let err0Vec = SIMD2<Double>(repeating: v0) - y0Vec
                        gVec = SIMD2<Double>(repeating: baseCost) + err0Vec * err0Vec + 24.0 * bar1Vec + isiVec

                        let v1Vec = SIMD2<Double>(repeating: v1Tail) + ff0 * ns0Vec
                        let y1Vec = SIMD2<Double>(v1Vec.x >= 0.0 ? 1.0 : -1.0, v1Vec.y >= 0.0 ? 1.0 : -1.0)
                        let err1Vec = v1Vec - y1Vec
                        let raw0_2Vec = ns0Vec + (b0U1Vec - b0 * y1Vec)
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
                        fVec = gVec + 0.85 * (err1Vec * err1Vec) + 0.25 * (p0Vec * p0Vec + p1Vec * p1Vec) + 36.0 * bar2Vec
                    }

                    let c0 = expCount
                    let c1Idx = expCount &+ 1
                    rankPtr[c0]     = fVec.x
                    rankPtr[c1Idx]  = fVec.y
                    gCostPtr[c0]    = gVec.x
                    gCostPtr[c1Idx] = gVec.y
                    ns0Ptr[c0]      = ns0Vec.x
                    ns0Ptr[c1Idx]   = ns0Vec.y
                    let isiPair = (bPrev1 == 1)
                        ? SIMD2<Double>(decayedIsi + 0.10, decayedIsi)
                        : SIMD2<Double>(decayedIsi, decayedIsi + 0.10)
                    nextIsiPtr[c0]    = isiPair.x
                    nextIsiPtr[c1Idx] = isiPair.y
                    let hShift = pHist << 1
                    histPtr[c0]    = hShift
                    histPtr[c1Idx] = hShift | 1
                    expCount &+= 2
                }

                let committedBit: UInt64
                var keepCount = 0
                var minSelectedGCost = Double.greatestFiniteMagnitude

                if maxSurvivors == 8 && L >= 1 {
                    var (lo0, hi0) = loadSortedKeyPair(0, nSurv, rankPtr)
                    var (lo1, hi1) = loadSortedKeyPair(1, nSurv, rankPtr)
                    var (lo2, hi2) = loadSortedKeyPair(2, nSurv, rankPtr)
                    var (lo3, hi3) = loadSortedKeyPair(3, nSurv, rankPtr)
                    var (lo4, hi4) = loadSortedKeyPair(4, nSurv, rankPtr)
                    var (lo5, hi5) = loadSortedKeyPair(5, nSurv, rankPtr)
                    var (lo6, hi6) = loadSortedKeyPair(6, nSurv, rankPtr)
                    var (lo7, hi7) = loadSortedKeyPair(7, nSurv, rankPtr)

                    let m01 = lo0 < lo1 ? lo0 : lo1
                    let m23 = lo2 < lo3 ? lo2 : lo3
                    let m45 = lo4 < lo5 ? lo4 : lo5
                    let m67 = lo6 < lo7 ? lo6 : lo7
                    let m03 = m01 < m23 ? m01 : m23
                    let m47 = m45 < m67 ? m45 : m67
                    let bestKey = m03 < m47 ? m03 : m47
                    let globalBestIdx = Int(bestKey & 15)
                    committedBit = (histPtr[globalBestIdx] >> shiftL) & 1

                    let inv0: UInt64 = (0 < nSurv && (((histPtr[0] >> shiftL) & 1) == committedBit)) ? 0 : UInt64.max
                    let inv1: UInt64 = (1 < nSurv && (((histPtr[2] >> shiftL) & 1) == committedBit)) ? 0 : UInt64.max
                    let inv2: UInt64 = (2 < nSurv && (((histPtr[4] >> shiftL) & 1) == committedBit)) ? 0 : UInt64.max
                    let inv3: UInt64 = (3 < nSurv && (((histPtr[6] >> shiftL) & 1) == committedBit)) ? 0 : UInt64.max
                    let inv4: UInt64 = (4 < nSurv && (((histPtr[8] >> shiftL) & 1) == committedBit)) ? 0 : UInt64.max
                    let inv5: UInt64 = (5 < nSurv && (((histPtr[10] >> shiftL) & 1) == committedBit)) ? 0 : UInt64.max
                    let inv6: UInt64 = (6 < nSurv && (((histPtr[12] >> shiftL) & 1) == committedBit)) ? 0 : UInt64.max
                    let inv7: UInt64 = (7 < nSurv && (((histPtr[14] >> shiftL) & 1) == committedBit)) ? 0 : UInt64.max

                    lo0 |= inv0; hi0 |= inv0; lo1 |= inv1; hi1 |= inv1
                    lo2 |= inv2; hi2 |= inv2; lo3 |= inv3; hi3 |= inv3
                    lo4 |= inv4; hi4 |= inv4; lo5 |= inv5; hi5 |= inv5
                    lo6 |= inv6; hi6 |= inv6; lo7 |= inv7; hi7 |= inv7

                    (lo0, lo1) = sort2Keys(lo0, lo1); (lo2, lo3) = sort2Keys(lo2, lo3)
                    (lo4, lo5) = sort2Keys(lo4, lo5); (lo6, lo7) = sort2Keys(lo6, lo7)
                    (lo0, lo2) = sort2Keys(lo0, lo2); (lo1, lo3) = sort2Keys(lo1, lo3)
                    (lo4, lo6) = sort2Keys(lo4, lo6); (lo5, lo7) = sort2Keys(lo5, lo7)
                    (lo1, lo2) = sort2Keys(lo1, lo2); (lo5, lo6) = sort2Keys(lo5, lo6)
                    (lo0, lo4) = sort2Keys(lo0, lo4); (lo1, lo5) = sort2Keys(lo1, lo5)
                    (lo2, lo6) = sort2Keys(lo2, lo6); (lo3, lo7) = sort2Keys(lo3, lo7)
                    (lo2, lo4) = sort2Keys(lo2, lo4); (lo3, lo5) = sort2Keys(lo3, lo5)
                    (lo1, lo2) = sort2Keys(lo1, lo2); (lo3, lo4) = sort2Keys(lo3, lo4); (lo5, lo6) = sort2Keys(lo5, lo6)

                    (hi0, hi1) = sort2Keys(hi0, hi1); (hi2, hi3) = sort2Keys(hi2, hi3)
                    (hi0, hi2) = sort2Keys(hi0, hi2); (hi1, hi3) = sort2Keys(hi1, hi3); (hi1, hi2) = sort2Keys(hi1, hi2)
                    (hi4, hi5) = sort2Keys(hi4, hi5); (hi6, hi7) = sort2Keys(hi6, hi7)
                    (hi4, hi6) = sort2Keys(hi4, hi6); (hi5, hi7) = sort2Keys(hi5, hi7); (hi5, hi6) = sort2Keys(hi5, hi6)
                    (hi0, hi7) = sort2Keys(hi0, hi7); (hi1, hi6) = sort2Keys(hi1, hi6)
                    (hi2, hi5) = sort2Keys(hi2, hi5); (hi3, hi4) = sort2Keys(hi3, hi4)
                    (hi0, hi2) = sort2Keys(hi0, hi2); (hi1, hi3) = sort2Keys(hi1, hi3)
                    (hi0, hi1) = sort2Keys(hi0, hi1); (hi2, hi3) = sort2Keys(hi2, hi3)

                    (lo7, hi0) = sort2Keys(lo7, hi0); (lo6, hi1) = sort2Keys(lo6, hi1)
                    (lo5, hi2) = sort2Keys(lo5, hi2); (lo4, hi3) = sort2Keys(lo4, hi3)
                    (lo0, lo4) = sort2Keys(lo0, lo4); (lo1, lo5) = sort2Keys(lo1, lo5)
                    (lo2, lo6) = sort2Keys(lo2, lo6); (lo3, lo7) = sort2Keys(lo3, lo7)
                    (lo0, lo2) = sort2Keys(lo0, lo2); (lo1, lo3) = sort2Keys(lo1, lo3)
                    (lo4, lo6) = sort2Keys(lo4, lo6); (lo5, lo7) = sort2Keys(lo5, lo7)
                    (lo0, lo1) = sort2Keys(lo0, lo1); (lo2, lo3) = sort2Keys(lo2, lo3)
                    (lo4, lo5) = sort2Keys(lo4, lo5); (lo6, lo7) = sort2Keys(lo6, lo7)

                    selIdxPtr[0] = Int32(lo0 & 15); selIdxPtr[1] = Int32(lo1 & 15)
                    selIdxPtr[2] = Int32(lo2 & 15); selIdxPtr[3] = Int32(lo3 & 15)
                    selIdxPtr[4] = Int32(lo4 & 15); selIdxPtr[5] = Int32(lo5 & 15)
                    selIdxPtr[6] = Int32(lo6 & 15); selIdxPtr[7] = Int32(lo7 & 15)

                    keepCount = (lo0 < validKeyLimit ? 1 : 0) &+ (lo1 < validKeyLimit ? 1 : 0)
                        &+ (lo2 < validKeyLimit ? 1 : 0) &+ (lo3 < validKeyLimit ? 1 : 0)
                        &+ (lo4 < validKeyLimit ? 1 : 0) &+ (lo5 < validKeyLimit ? 1 : 0)
                        &+ (lo6 < validKeyLimit ? 1 : 0) &+ (lo7 < validKeyLimit ? 1 : 0)

                    for sel in 0..<keepCount {
                        let gc = gCostPtr[Int(selIdxPtr[sel])]
                        if gc < minSelectedGCost { minSelectedGCost = gc }
                    }
                } else {
                    var globalBestIdx = 0
                    var globalBestRank = rankPtr[0]
                    for i in 1..<expCount {
                        let r = rankPtr[i]
                        if r < globalBestRank {
                            globalBestRank = r
                            globalBestIdx = i
                        }
                    }
                    committedBit = (histPtr[globalBestIdx] >> shiftL) & 1

                    var validCount = 0
                    for i in 0..<expCount {
                        if ((histPtr[i] >> shiftL) & 1) == committedBit {
                            vIdxPtr[validCount] = Int32(i)
                            validCount &+= 1
                        }
                    }

                    keepCount = maxSurvivors < validCount ? maxSurvivors : validCount
                    for sel in 0..<keepCount {
                        var bestPos = sel
                        var bestRank = rankPtr[Int(vIdxPtr[sel])]
                        if sel &+ 1 < validCount {
                            for p in (sel &+ 1)..<validCount {
                                let r = rankPtr[Int(vIdxPtr[p])]
                                if r < bestRank {
                                    bestRank = r
                                    bestPos = p
                                }
                            }
                        }
                        let chosenExpIdx = Int(vIdxPtr[bestPos])
                        vIdxPtr[bestPos] = vIdxPtr[sel]
                        selIdxPtr[sel] = Int32(chosenExpIdx)
                        let gc = gCostPtr[chosenExpIdx]
                        if gc < minSelectedGCost {
                            minSelectedGCost = gc
                        }
                    }
                }

                let normOffset = minSelectedGCost.isFinite ? minSelectedGCost : 0.0
                for sel in 0..<keepCount {
                    let c = Int(selIdxPtr[sel])
                    let pIdx = c >> 1
                    let s12 = sharedS12Ptr[pIdx]
                    let s34 = sharedS34Ptr[pIdx]
                    let s56 = sharedS56Ptr[pIdx]
                    let ns0Val = ns0Ptr[c]
                    dstS01[sel]  = SIMD2<Double>(ns0Val, s12.x)
                    dstS23[sel]  = SIMD2<Double>(s12.y, s34.x)
                    dstS45[sel]  = SIMD2<Double>(s34.y, s56.x)
                    dstS6I[sel]  = SIMD2<Double>(s56.y, nextIsiPtr[c])
                    dstCost[sel] = fmax2(0.0, gCostPtr[c] - normOffset)
                    dstHist[sel] = histPtr[c]
                }

                if keepCount > 0 {
                    let b01 = simd_max(simd_abs(dstS01[0]), simd_abs(dstS23[0]))
                    let b05 = simd_max(b01, simd_abs(dstS45[0]))
                    let amp = fmax2(fmax2(b05.x, b05.y), dstS6I[0].x.magnitude)
                    if amp > maxPeak { maxPeak = amp }
                }

                let tmpS01 = srcS01; srcS01 = dstS01; dstS01 = tmpS01
                let tmpS23 = srcS23; srcS23 = dstS23; dstS23 = tmpS23
                let tmpS45 = srcS45; srcS45 = dstS45; dstS45 = tmpS45
                let tmpS6I = srcS6I; srcS6I = dstS6I; dstS6I = tmpS6I
                let tmpCost = srcCost; srcCost = dstCost; dstCost = tmpCost
                let tmpHist = srcHist; srcHist = dstHist; dstHist = tmpHist

                nSurv = keepCount > 1 ? keepCount : 1
                if committedBit == 1 {
                    packedByte |= (UInt8(0x80) >> UInt8(bitPos))
                }
            }
            dsdOutputBytes[byteIdx] = packedByte
        }

        for i in 0..<nSurv {
            let h = srcHist[i]
            survAPtr[i] = TrellisCandidatePath(
                state: BiquadLatticeState(
                    s01: srcS01[i],
                    s23: srcS23[i],
                    s45: srcS45[i],
                    s6Isi: srcS6I[i]
                ),
                cost: srcCost[i],
                history: h,
                lastY: (h & 1) == 1 ? 1.0 : -1.0
            )
        }

        return (nSurv, maxPeak, rng0, rng1)
    }
}
