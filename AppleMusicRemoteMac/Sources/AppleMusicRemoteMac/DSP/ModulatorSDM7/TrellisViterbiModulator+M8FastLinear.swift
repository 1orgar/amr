//
//  TrellisViterbiModulator+M8FastLinear.swift
//  AppleMusicRemoteMac
//
//  Zero-Spill 2-Parent Vertical SIMD2 NEON Fast-Linear Leaf Kernel for M = 8 (1 <= L <= 63).
//

import simd

extension TrellisViterbiModulator {

    /// Сверхбыстрое безспилловое листовое ядро стационарного блока для штатного режима `M = 8` (`1 <= L <= 63`):
    /// - Удерживает ровно `<= 21` векторных регистров NEON (`v0..v31`) и `<= 16` GP-регистров (`x0..x28`) в горячем цикле (`0` стековых спиллов `[sp, #...]`);
    /// - Переиспользует векторные пары `(nextS23, nextS45, ns16)` напрямую под раскладку `ff23 / ff45` и `BiquadLatticeState` без переупорядочивания;
    /// - При редком пиковом выходе любого выжившего за `bitLinBound` мгновенно откатывает генератор дизеринга бита и передаёт управление нелинейному ядру.
    @inline(never)
    @usableFromInline
    internal static func processSteadyBlockM8FastLinear(
        inputSamples: UnsafePointer<Double>,
        sampleCount: Int,
        byteCount: Int,
        tailNextSample: Double,
        dsdOutputBytes: UnsafeMutablePointer<UInt8>,
        L: Int,
        isiOn: Bool,
        ditherAmp: Double,
        coeffs: SDM7SectionCoefficients,
        survAPtr: UnsafeMutablePointer<TrellisCandidatePath>,
        scratchBase: UnsafeMutableRawPointer,
        initialCurCount: Int,
        initialPeakAmp: Double,
        initialPrngS0: UInt64,
        initialPrngS1: UInt64
    ) -> FastLinearBlockResult {
        let b0 = coeffs.b0
        let a1 = coeffs.aLink01.x; let a2 = coeffs.aLink01.y; let a3 = coeffs.aLink2Pad.x
        let g1 = coeffs.gFeedback01.x; let g2 = coeffs.gFeedback01.y; let g3 = coeffs.gFeedback2Pad.x
        let c1 = coeffs.cIntegrator01.x; let c2 = coeffs.cIntegrator01.y; let c3 = coeffs.cIntegrator2Pad.x
        let ff6 = coeffs.ff6IsiPad.x
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

        // Ровно 18 регистров SIMD2<Double> для горячего вертикального 2-Parent SIMD2 цикла Phase 1:
        let ff01     = coeffs.ff01
        let ff23     = coeffs.ff23
        let ff45     = coeffs.ff45
        let b0_ff6   = SIMD2<Double>(b0, ff6)
        let a12      = coeffs.aLink01
        let g12      = coeffs.gFeedback01
        let c12      = coeffs.cIntegrator01
        let ag3      = SIMD2<Double>(a3, g3)
        let c3_disc  = SIMD2<Double>(c3, 0.92)
        let q0_01    = SIMD2<Double>(q0_0, q0_1)
        let q0_23    = SIMD2<Double>(q0_2, q0_3)
        let q0_45    = SIMD2<Double>(q0_4, q0_5)
        let q06_o00  = SIMD2<Double>(q0_6, o0_0)
        let q1_01    = SIMD2<Double>(q1_0, q1_1)
        let q1_23    = SIMD2<Double>(q1_2, q1_3)
        let q1_45    = SIMD2<Double>(q1_4, q1_5)
        let q16_o10  = SIMD2<Double>(q1_6, o1_0)
        let w1_isiThr = SIMD2<Double>(0.85, 1.0e-4)

        let lim = fmin2(coeffs.softClipThreshold, 1.14)
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

        let hdrVec = scratchBase.assumingMemoryBound(to: SIMD2<Double>.self)
        hdrVec[0] = SIMD2<Double>(lim, resPureBound)
        hdrVec[1] = SIMD2<Double>(lim * invL1_2, lim * invL2_2)
        hdrVec[2] = SIMD2<Double>(a1 * invL1_2, c1 * a1 * invL2_2)
        hdrVec[3] = SIMD2<Double>(0x1.0p-53, ditherAmp)
        hdrVec[4] = SIMD2<Double>(0.90, 0.10)
        hdrVec[5] = SIMD2<Double>(0.14, 1.5e-4)
        hdrVec[6] = SIMD2<Double>(0.46, 6.0e-4)
        hdrVec[7] = SIMD2<Double>(10000.0, 1.0e300)
        scratchBase.advanced(by: 2240).assumingMemoryBound(to: Double.self)[0] = coeffs.isiLambda

        var srcPtr = scratchBase.advanced(by: 128).assumingMemoryBound(to: FastLinearSlot.self)
        var dstPtr = scratchBase.advanced(by: 768).assumingMemoryBound(to: FastLinearSlot.self)

        var nSurv = initialCurCount <= 8 ? initialCurCount : 8
        var maxPeak = initialPeakAmp
        var rng0 = initialPrngS0
        var rng1 = initialPrngS1
        let ditherActive = ditherAmp > 0.0
        let shiftLm1 = UInt64(L &- 1)
        let validKeyLimit: UInt64 = 0x7FF0_0000_0000_0000

        let fallbackSurv = survAPtr[0]
        for i in 0..<8 {
            let p = (i < nSurv) ? survAPtr[i] : fallbackSurv
            let sl = FastLinearSlot(
                s01: p.state.s01,
                s23: p.state.s23,
                s45: p.state.s45,
                s6I: p.state.s6Isi,
                cost: p.cost,
                hist: p.history
            )
            srcPtr[i] = sl
            dstPtr[i] = sl
        }

        for byteIdx in 0..<byteCount {
            var packedByte: UInt8 = 0
            for bitPos in 0..<8 {
                let sampleIdx = (byteIdx &<< 3) &+ bitPos
                let u0 = inputSamples[sampleIdx]
                let u1 = (sampleIdx &+ 1 < sampleCount) ? inputSamples[sampleIdx &+ 1] : tailNextSample

                let prevRng0 = rng0
                let prevRng1 = rng1
                let dither: Double
                if ditherActive {
                    let ds = scratchBase.assumingMemoryBound(to: SIMD2<Double>.self)[3]
                    let rA = rng0 &+ rng1
                    let x0 = rng1 ^ rng0
                    rng0 = ((rng0 << 24) | (rng0 >> 40)) ^ x0 ^ (x0 << 16)
                    rng1 = (x0 << 37) | (x0 >> 27)
                    let rB = rng0 &+ rng1
                    let x1 = rng1 ^ rng0
                    rng0 = ((rng0 << 24) | (rng0 >> 40)) ^ x1 ^ (x1 << 16)
                    rng1 = (x1 << 37) | (x1 >> 27)
                    let uA = Double(rA >> 11) * ds.x - 0.5
                    let uB = Double(rB >> 11) * ds.x - 0.5
                    dither = (uA + uB) * ds.y
                } else {
                    dither = 0.0
                }

                let hv = scratchBase.assumingMemoryBound(to: SIMD2<Double>.self)
                let limRes = hv[0]
                let du0Max = b0_ff6.x * (1.0 + fabs2(u0))
                let du01Max = du0Max + b0_ff6.x * (1.0 + fabs2(u1))
                let bVec = hv[1] - hv[2] * SIMD2<Double>(repeating: du0Max)
                let bitLinBound = fmin2(fmin2(limRes.x - du01Max, limRes.y), fmin2(bVec.x, bVec.y))

                let bitVec = SIMD2<Double>(u0 + dither, b0_ff6.x * u0)
                let u1_bound = SIMD2<Double>(u1, bitLinBound)

                let sharedSubPtr = scratchBase.advanced(by: 1408).assumingMemoryBound(to: SIMD2<Double>.self)
                let ns0VecPtr    = scratchBase.advanced(by: 1792).assumingMemoryBound(to: SIMD2<Double>.self)
                let gCostVecPtr  = scratchBase.advanced(by: 1920).assumingMemoryBound(to: SIMD2<Double>.self)
                let keyPairPtr   = scratchBase.advanced(by: 2048).assumingMemoryBound(to: UInt64.self)

                var tbBits: UInt64 = 0

                for pair in 0..<4 {
                    let iA = pair &<< 1
                    let iB = iA &+ 1

                    let a01 = srcPtr[iA].s01; let b01 = srcPtr[iB].s01
                    let a23 = srcPtr[iA].s23; let b23 = srcPtr[iB].s23
                    let m03 = simd_max(simd_max(simd_abs(a01), simd_abs(b01)), simd_max(simd_abs(a23), simd_abs(b23)))
                    let s0 = SIMD2<Double>(a01.x, b01.x)
                    let s1 = SIMD2<Double>(a01.y, b01.y)
                    let s2 = SIMD2<Double>(a23.x, b23.x)
                    let s3 = SIMD2<Double>(a23.y, b23.y)

                    let a45 = srcPtr[iA].s45; let b45 = srcPtr[iB].s45
                    let a6I = srcPtr[iA].s6I; let b6I = srcPtr[iB].s6I
                    let s6 = SIMD2<Double>(a6I.x, b6I.x)
                    let mAll = simd_max(simd_max(m03, simd_max(simd_abs(a45), simd_abs(b45))), simd_abs(s6))
                    if fmax2(mAll.x, mAll.y) > u1_bound.y {
                        for i in 0..<nSurv {
                            let sl = srcPtr[i]
                            let h = sl.hist
                            survAPtr[i] = TrellisCandidatePath(
                                state: BiquadLatticeState(s01: sl.s01, s23: sl.s23, s45: sl.s45, s6Isi: sl.s6I),
                                cost: sl.cost,
                                history: h,
                                lastY: (h & 1) == 1 ? 1.0 : -1.0
                            )
                        }
                        let partialOut: UInt8 = bitPos > 0 ? (packedByte << UInt8(8 &- bitPos)) : 0
                        return FastLinearBlockResult(
                            completedBytes: byteIdx,
                            abortedBitPos: bitPos,
                            partialByte: partialOut,
                            curCount: nSurv,
                            peakAmp: maxPeak,
                            prngS0: prevRng0,
                            prngS1: prevRng1
                        )
                    }
                    let s4 = SIMD2<Double>(a45.x, b45.x)
                    let s5 = SIMD2<Double>(a45.y, b45.y)

                    let histA = srcPtr[iA].hist
                    let histB = srcPtr[iB].hist
                    tbBits |= (((histA >> shiftLm1) & 1) << UInt64(iA)) | (((histB >> shiftLm1) & 1) << UInt64(iB))

                    var v0AB = SIMD2<Double>(repeating: bitVec.x)
                    v0AB += ff01.x * s0 + ff01.y * s1
                    v0AB += ff23.x * s2 + ff23.y * s3
                    v0AB += ff45.x * s4 + ff45.y * s5
                    v0AB += b0_ff6.y * s6

                    let pCostAB = SIMD2<Double>(srcPtr[iA].cost, srcPtr[iB].cost)
                    let err0Neg = v0AB + SIMD2<Double>(repeating: 1.0)
                    let err0Pos = v0AB - SIMD2<Double>(repeating: 1.0)
                    let discCost = c3_disc.y * pCostAB
                    var gNeg = discCost + err0Neg * err0Neg
                    var gPos = discCost + err0Pos * err0Pos

                    if isiOn {
                        let av0 = simd_abs(v0AB)
                        if fmin2(av0.x, av0.y) < w1_isiThr.y {
                            let isiHdr = scratchBase.assumingMemoryBound(to: Double.self)
                            let isiLam = scratchBase.advanced(by: 2240).assumingMemoryBound(to: Double.self)[0]
                            if av0.x < w1_isiThr.y {
                                let maxHiA = fmax2(fmax2(fabs2(s3.x), fmax2(fabs2(s4.x), fabs2(s5.x))), fabs2(s6.x))
                                if maxHiA < isiHdr[10] {
                                    let b1A = histA & 1
                                    let b2A = (histA >> 1) & 1
                                    let pulseA = (b1A != b2A) ? isiHdr[11] : 0.0
                                    let chatA = fmax2(0.0, srcPtr[iA].s6I.y - isiHdr[12])
                                    let wA = 1.0 - av0.x * isiHdr[14]
                                    let penA = isiLam * (wA * wA) * (pulseA + isiHdr[13] * chatA)
                                    if b1A == 1 { gNeg.x += penA } else { gPos.x += penA }
                                }
                            }
                            if av0.y < w1_isiThr.y {
                                let maxHiB = fmax2(fmax2(fabs2(s3.y), fmax2(fabs2(s4.y), fabs2(s5.y))), fabs2(s6.y))
                                if maxHiB < isiHdr[10] {
                                    let b1B = histB & 1
                                    let b2B = (histB >> 1) & 1
                                    let pulseB = (b1B != b2B) ? isiHdr[11] : 0.0
                                    let chatB = fmax2(0.0, srcPtr[iB].s6I.y - isiHdr[12])
                                    let wB = 1.0 - av0.y * isiHdr[14]
                                    let penB = isiLam * (wB * wB) * (pulseB + isiHdr[13] * chatB)
                                    if b1B == 1 { gNeg.y += penB } else { gPos.y += penB }
                                }
                            }
                        }
                    }

                    gCostVecPtr[iA] = SIMD2<Double>(gNeg.x, gPos.x)
                    gCostVecPtr[iB] = SIMD2<Double>(gNeg.y, gPos.y)

                    let ns1 = s1 + a12.x * s0 - g12.x * s2
                    let s0Base = s0 + SIMD2<Double>(repeating: bitVec.y)
                    let ns2 = s2 + c12.x * ns1
                    let ns3 = s3 + a12.y * s2 - g12.y * s4
                    let ns4 = s4 + c12.y * ns3
                    let ns5 = s5 + ag3.x * s4 - ag3.y * s6
                    let ns6 = s6 + c3_disc.x * ns5

                    let subA = iA &* 3
                    sharedSubPtr[subA]      = SIMD2<Double>(ns2.x, ns3.x)
                    sharedSubPtr[subA &+ 1] = SIMD2<Double>(ns4.x, ns5.x)
                    sharedSubPtr[subA &+ 2] = SIMD2<Double>(ns1.x, ns6.x)
                    sharedSubPtr[subA &+ 3] = SIMD2<Double>(ns2.y, ns3.y)
                    sharedSubPtr[subA &+ 4] = SIMD2<Double>(ns4.y, ns5.y)
                    sharedSubPtr[subA &+ 5] = SIMD2<Double>(ns1.y, ns6.y)

                    var v1Base = SIMD2<Double>(repeating: u1_bound.x)
                    v1Base += ff01.y * ns1 + ff23.x * ns2
                    v1Base += ff23.y * ns3 + ff45.x * ns4
                    v1Base += ff45.y * ns5 + b0_ff6.y * ns6

                    var p0Tail = q0_01.y * ns1 + q0_23.x * ns2
                    p0Tail += q0_23.y * ns3 + q0_45.x * ns4
                    p0Tail += q0_45.y * ns5 + q06_o00.x * ns6

                    var p1Tail = q1_01.y * ns1 + q1_23.x * ns2
                    p1Tail += q1_23.y * ns3 + q1_45.x * ns4
                    p1Tail += q1_45.y * ns5 + q16_o10.x * ns6

                    let b0Vec = SIMD2<Double>(repeating: b0_ff6.x)
                    let u1Vec = SIMD2<Double>(repeating: u1_bound.x)
                    let ns0Neg = s0Base + b0Vec
                    let ns0Pos = s0Base - b0Vec
                    ns0VecPtr[iA] = SIMD2<Double>(ns0Neg.x, ns0Pos.x)
                    ns0VecPtr[iB] = SIMD2<Double>(ns0Neg.y, ns0Pos.y)

                    let v1Neg = v1Base + ff01.x * ns0Neg
                    let y1Neg = SIMD2<Double>(v1Neg.x >= 0.0 ? 1.0 : -1.0, v1Neg.y >= 0.0 ? 1.0 : -1.0)
                    let err1Neg = v1Neg - y1Neg
                    let du1Neg = b0_ff6.x * (u1Vec - y1Neg)
                    let p0Neg: SIMD2<Double> = p0Tail + (q0_01.x * ns0Neg + q06_o00.y * du1Neg)
                    let p1Neg: SIMD2<Double> = p1Tail + (q1_01.x * ns0Neg + q16_o10.y * du1Neg)
                    let e1NegCost: SIMD2<Double> = w1_isiThr.x * (err1Neg * err1Neg)
                    let pNegCost: SIMD2<Double> = 0.25 * (p0Neg * p0Neg + p1Neg * p1Neg)
                    let fNeg: SIMD2<Double> = (gNeg + e1NegCost) + pNegCost

                    let v1Pos = v1Base + ff01.x * ns0Pos
                    let y1Pos = SIMD2<Double>(v1Pos.x >= 0.0 ? 1.0 : -1.0, v1Pos.y >= 0.0 ? 1.0 : -1.0)
                    let err1Pos = v1Pos - y1Pos
                    let du1Pos = b0_ff6.x * (u1Vec - y1Pos)
                    let p0Pos: SIMD2<Double> = p0Tail + (q0_01.x * ns0Pos + q06_o00.y * du1Pos)
                    let p1Pos: SIMD2<Double> = p1Tail + (q1_01.x * ns0Pos + q16_o10.y * du1Pos)
                    let e1PosCost: SIMD2<Double> = w1_isiThr.x * (err1Pos * err1Pos)
                    let pPosCost: SIMD2<Double> = 0.25 * (p0Pos * p0Pos + p1Pos * p1Pos)
                    let fPos: SIMD2<Double> = (gPos + e1PosCost) + pPosCost

                    let cA0 = UInt64(iA &<< 1)
                    let (loKA, hiKA) = sort2Keys(packRankKey(fNeg.x, cA0), packRankKey(fPos.x, cA0 | 1))
                    let kpBase = iA &<< 1
                    keyPairPtr[kpBase]      = loKA
                    keyPairPtr[kpBase &+ 1] = hiKA

                    let cB0 = cA0 &+ 2
                    let (loKB, hiKB) = sort2Keys(packRankKey(fNeg.y, cB0), packRankKey(fPos.y, cB0 | 1))
                    keyPairPtr[kpBase &+ 2] = loKB
                    keyPairPtr[kpBase &+ 3] = hiKB
                }

                let activeMask = (UInt64(1) << UInt64(nSurv)) &- 1
                let rLo0 = keyPairPtr[0];  let rLo1 = keyPairPtr[2]
                let rLo2 = keyPairPtr[4];  let rLo3 = keyPairPtr[6]
                let rLo4 = keyPairPtr[8];  let rLo5 = keyPairPtr[10]
                let rLo6 = keyPairPtr[12]; let rLo7 = keyPairPtr[14]

                var lo0 = (((activeMask >> 0) & 1) &- 1) | rLo0
                var lo1 = (((activeMask >> 1) & 1) &- 1) | rLo1
                var lo2 = (((activeMask >> 2) & 1) &- 1) | rLo2
                var lo3 = (((activeMask >> 3) & 1) &- 1) | rLo3
                var lo4 = (((activeMask >> 4) & 1) &- 1) | rLo4
                var lo5 = (((activeMask >> 5) & 1) &- 1) | rLo5
                var lo6 = (((activeMask >> 6) & 1) &- 1) | rLo6
                var lo7 = (((activeMask >> 7) & 1) &- 1) | rLo7

                let m01 = lo0 < lo1 ? lo0 : lo1
                let m23 = lo2 < lo3 ? lo2 : lo3
                let m45 = lo4 < lo5 ? lo4 : lo5
                let m67 = lo6 < lo7 ? lo6 : lo7
                let m03 = m01 < m23 ? m01 : m23
                let m47 = m45 < m67 ? m45 : m67
                let bestKey = m03 < m47 ? m03 : m47
                let bestParent = (bestKey & 15) >> 1
                let committedBit = (tbBits >> bestParent) & 1

                let validMask = ((committedBit == 1) ? tbBits : ~tbBits) & activeMask

                lo0 |= (((validMask >> 0) & 1) &- 1)
                lo1 |= (((validMask >> 1) & 1) &- 1)
                lo2 |= (((validMask >> 2) & 1) &- 1)
                lo3 |= (((validMask >> 3) & 1) &- 1)
                lo4 |= (((validMask >> 4) & 1) &- 1)
                lo5 |= (((validMask >> 5) & 1) &- 1)
                lo6 |= (((validMask >> 6) & 1) &- 1)
                lo7 |= (((validMask >> 7) & 1) &- 1)

                (lo0, lo1) = sort2Keys(lo0, lo1); (lo2, lo3) = sort2Keys(lo2, lo3)
                (lo4, lo5) = sort2Keys(lo4, lo5); (lo6, lo7) = sort2Keys(lo6, lo7)
                (lo0, lo2) = sort2Keys(lo0, lo2); (lo1, lo3) = sort2Keys(lo1, lo3)
                (lo4, lo6) = sort2Keys(lo4, lo6); (lo5, lo7) = sort2Keys(lo5, lo7)
                (lo1, lo2) = sort2Keys(lo1, lo2); (lo5, lo6) = sort2Keys(lo5, lo6)
                (lo0, lo4) = sort2Keys(lo0, lo4); (lo1, lo5) = sort2Keys(lo1, lo5)
                (lo2, lo6) = sort2Keys(lo2, lo6); (lo3, lo7) = sort2Keys(lo3, lo7)
                (lo2, lo4) = sort2Keys(lo2, lo4); (lo3, lo5) = sort2Keys(lo3, lo5)
                (lo1, lo2) = sort2Keys(lo1, lo2); (lo3, lo4) = sort2Keys(lo3, lo4); (lo5, lo6) = sort2Keys(lo5, lo6)

                let loSpillPtr = scratchBase.advanced(by: 2176).assumingMemoryBound(to: UInt64.self)
                loSpillPtr[0] = lo0; loSpillPtr[1] = lo1; loSpillPtr[2] = lo2; loSpillPtr[3] = lo3
                loSpillPtr[4] = lo4; loSpillPtr[5] = lo5; loSpillPtr[6] = lo6; loSpillPtr[7] = lo7

                let rHi0 = keyPairPtr[1];  let rHi1 = keyPairPtr[3]
                let rHi2 = keyPairPtr[5];  let rHi3 = keyPairPtr[7]
                let rHi4 = keyPairPtr[9];  let rHi5 = keyPairPtr[11]
                let rHi6 = keyPairPtr[13]; let rHi7 = keyPairPtr[15]

                var hi0 = (((validMask >> 0) & 1) &- 1) | rHi0
                var hi1 = (((validMask >> 1) & 1) &- 1) | rHi1
                var hi2 = (((validMask >> 2) & 1) &- 1) | rHi2
                var hi3 = (((validMask >> 3) & 1) &- 1) | rHi3
                var hi4 = (((validMask >> 4) & 1) &- 1) | rHi4
                var hi5 = (((validMask >> 5) & 1) &- 1) | rHi5
                var hi6 = (((validMask >> 6) & 1) &- 1) | rHi6
                var hi7 = (((validMask >> 7) & 1) &- 1) | rHi7

                (hi0, hi1) = sort2Keys(hi0, hi1); (hi2, hi3) = sort2Keys(hi2, hi3)
                (hi0, hi2) = sort2Keys(hi0, hi2); (hi1, hi3) = sort2Keys(hi1, hi3); (hi1, hi2) = sort2Keys(hi1, hi2)
                (hi4, hi5) = sort2Keys(hi4, hi5); (hi6, hi7) = sort2Keys(hi6, hi7)
                (hi4, hi6) = sort2Keys(hi4, hi6); (hi5, hi7) = sort2Keys(hi5, hi7); (hi5, hi6) = sort2Keys(hi5, hi6)
                (hi0, hi7) = sort2Keys(hi0, hi7); (hi1, hi6) = sort2Keys(hi1, hi6)
                (hi2, hi5) = sort2Keys(hi2, hi5); (hi3, hi4) = sort2Keys(hi3, hi4)
                (hi0, hi2) = sort2Keys(hi0, hi2); (hi1, hi3) = sort2Keys(hi1, hi3)
                (hi0, hi1) = sort2Keys(hi0, hi1); (hi2, hi3) = sort2Keys(hi2, hi3)

                var w0 = loSpillPtr[0]; var w1 = loSpillPtr[1]; var w2 = loSpillPtr[2]; var w3 = loSpillPtr[3]
                var w4 = loSpillPtr[4]; var w5 = loSpillPtr[5]; var w6 = loSpillPtr[6]; var w7 = loSpillPtr[7]

                (w7, hi0) = sort2Keys(w7, hi0)
                (w6, hi1) = sort2Keys(w6, hi1)
                (w5, hi2) = sort2Keys(w5, hi2)
                (w4, hi3) = sort2Keys(w4, hi3)
                (w0, w4) = sort2Keys(w0, w4); (w1, w5) = sort2Keys(w1, w5)
                (w2, w6) = sort2Keys(w2, w6); (w3, w7) = sort2Keys(w3, w7)
                (w0, w2) = sort2Keys(w0, w2); (w1, w3) = sort2Keys(w1, w3)
                (w4, w6) = sort2Keys(w4, w6); (w5, w7) = sort2Keys(w5, w7)
                (w0, w1) = sort2Keys(w0, w1); (w2, w3) = sort2Keys(w2, w3)
                (w4, w5) = sort2Keys(w4, w5); (w6, w7) = sort2Keys(w6, w7)

                let vCnt03: UInt64 = ((~w0) >> 63) &+ ((~w1) >> 63) &+ ((~w2) >> 63) &+ ((~w3) >> 63)
                let vCnt47: UInt64 = ((~w4) >> 63) &+ ((~w5) >> 63) &+ ((~w6) >> 63) &+ ((~w7) >> 63)
                let keepCount = Int(vCnt03 &+ vCnt47)

                let gCostPtr = scratchBase.advanced(by: 1920).assumingMemoryBound(to: Double.self)
                let ns0Ptr   = scratchBase.advanced(by: 1792).assumingMemoryBound(to: Double.self)
                let infCost  = scratchBase.assumingMemoryBound(to: Double.self)[15]
                let rg0 = gCostPtr[Int(w0 & 15)]; let c0v = (w0 < validKeyLimit) ? rg0 : infCost
                let rg1 = gCostPtr[Int(w1 & 15)]; let c1v = (w1 < validKeyLimit) ? rg1 : infCost
                let rg2 = gCostPtr[Int(w2 & 15)]; let c2v = (w2 < validKeyLimit) ? rg2 : infCost
                let rg3 = gCostPtr[Int(w3 & 15)]; let c3v = (w3 < validKeyLimit) ? rg3 : infCost
                let rg4 = gCostPtr[Int(w4 & 15)]; let c4v = (w4 < validKeyLimit) ? rg4 : infCost
                let rg5 = gCostPtr[Int(w5 & 15)]; let c5v = (w5 < validKeyLimit) ? rg5 : infCost
                let rg6 = gCostPtr[Int(w6 & 15)]; let c6v = (w6 < validKeyLimit) ? rg6 : infCost
                let rg7 = gCostPtr[Int(w7 & 15)]; let c7v = (w7 < validKeyLimit) ? rg7 : infCost
                let min03 = fmin2(fmin2(c0v, c1v), fmin2(c2v, c3v))
                let min47 = fmin2(fmin2(c4v, c5v), fmin2(c6v, c7v))
                let minSelectedGCost = fmin2(min03, min47)
                let normOffset = minSelectedGCost < infCost ? minSelectedGCost : 0.0

                let isiDec = scratchBase.assumingMemoryBound(to: SIMD2<Double>.self)[4]
                let subRO = UnsafePointer(sharedSubPtr)
                let srcRO = UnsafePointer(srcPtr)
                let ns0RO = UnsafePointer(ns0Ptr)
                let gcRO  = UnsafePointer(gCostPtr)
                writeFastLinearWinner(0, w0, w0, validKeyLimit, normOffset, isiDec, subRO, ns0RO, gcRO, srcRO, dstPtr)
                writeFastLinearWinner(1, w1, w0, validKeyLimit, normOffset, isiDec, subRO, ns0RO, gcRO, srcRO, dstPtr)
                writeFastLinearWinner(2, w2, w0, validKeyLimit, normOffset, isiDec, subRO, ns0RO, gcRO, srcRO, dstPtr)
                writeFastLinearWinner(3, w3, w0, validKeyLimit, normOffset, isiDec, subRO, ns0RO, gcRO, srcRO, dstPtr)
                writeFastLinearWinner(4, w4, w0, validKeyLimit, normOffset, isiDec, subRO, ns0RO, gcRO, srcRO, dstPtr)
                writeFastLinearWinner(5, w5, w0, validKeyLimit, normOffset, isiDec, subRO, ns0RO, gcRO, srcRO, dstPtr)
                writeFastLinearWinner(6, w6, w0, validKeyLimit, normOffset, isiDec, subRO, ns0RO, gcRO, srcRO, dstPtr)
                writeFastLinearWinner(7, w7, w0, validKeyLimit, normOffset, isiDec, subRO, ns0RO, gcRO, srcRO, dstPtr)

                let s0 = dstPtr[0]
                let b01 = simd_max(simd_abs(s0.s01), simd_abs(s0.s23))
                let b05 = simd_max(b01, simd_abs(s0.s45))
                let amp = fmax2(fmax2(b05.x, b05.y), fabs2(s0.s6I.x))
                maxPeak = fmax2(maxPeak, amp)

                let tmp = srcPtr; srcPtr = dstPtr; dstPtr = tmp
                nSurv = keepCount > 1 ? keepCount : 1
                packedByte = (packedByte &<< 1) | UInt8(truncatingIfNeeded: committedBit)
            }
            dsdOutputBytes[byteIdx] = packedByte
        }

        for i in 0..<nSurv {
            let sl = srcPtr[i]
            let h = sl.hist
            survAPtr[i] = TrellisCandidatePath(
                state: BiquadLatticeState(s01: sl.s01, s23: sl.s23, s45: sl.s45, s6Isi: sl.s6I),
                cost: sl.cost,
                history: h,
                lastY: (h & 1) == 1 ? 1.0 : -1.0
            )
        }

        return FastLinearBlockResult(
            completedBytes: byteCount,
            abortedBitPos: 0,
            partialByte: 0,
            curCount: nSurv,
            peakAmp: maxPeak,
            prngS0: rng0,
            prngS1: rng1
        )
    }
}
