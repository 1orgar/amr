//
//  TrellisViterbiModulator+BlockDispatch.swift
//  AppleMusicRemoteMac
//
//  Block-Level Dispatcher (Fast-Linear M=8 <-> Non-Linear Fallback <-> 5ms Profile Morphing)
//  and MSB-First DSD Byte Packing Entry Point.
//

import simd

extension TrellisViterbiModulator {

    @inline(__always)
    @usableFromInline
    internal static func dispatchSteadyBlock(
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
        if maxSurvivors == 8 && L >= 1 && L <= 63 {
            var doneBytes = 0
            var curCount = initialCurCount
            var peakAmp = initialPeakAmp
            var rng0 = initialPrngS0
            var rng1 = initialPrngS1

            while doneBytes < byteCount {
                let remBytes = byteCount &- doneBytes
                let remSamples = sampleCount &- (doneBytes &<< 3)
                let fastRes = processSteadyBlockM8FastLinear(
                    inputSamples: inputSamples.advanced(by: doneBytes &<< 3),
                    sampleCount: remSamples,
                    byteCount: remBytes,
                    tailNextSample: tailNextSample,
                    dsdOutputBytes: dsdOutputBytes.advanced(by: doneBytes),
                    L: L,
                    isiOn: isiOn,
                    ditherAmp: ditherAmp,
                    coeffs: coeffs,
                    survAPtr: survAPtr,
                    scratchBase: scratchRaw,
                    initialCurCount: curCount,
                    initialPeakAmp: peakAmp,
                    initialPrngS0: rng0,
                    initialPrngS1: rng1
                )
                doneBytes &+= fastRes.completedBytes
                curCount = fastRes.curCount
                peakAmp = fastRes.peakAmp
                rng0 = fastRes.prngS0
                rng1 = fastRes.prngS1
                if doneBytes >= byteCount {
                    break
                }

                // Редкий пиковый транзиент (> bitLinBound): доводим текущий байт через эталонный stepBitCore
                // и пропускаем окно стабилизации (до 32 байт) через полное нелинейное ядро.
                var partial = fastRes.partialByte
                var tmpPrng = Xoroshiro128Plus(seed0: rng0, seed1: rng1)
                var dummyTransRem = 0
                var actC = coeffs
                let expPtr = scratchRaw.assumingMemoryBound(to: TrellisCandidatePath.self)
                let rnkPtr = scratchRaw.advanced(by: 3072).assumingMemoryBound(to: Double.self)
                let vIdxP  = scratchRaw.advanced(by: 3328).assumingMemoryBound(to: Int32.self)
                for bPos in fastRes.abortedBitPos..<8 {
                    let sIdx = (doneBytes &<< 3) &+ bPos
                    let u0 = inputSamples[sIdx]
                    let u1 = (sIdx &+ 1 < sampleCount) ? inputSamples[sIdx &+ 1] : tailNextSample
                    let bit = stepBitCore(
                        u0: u0,
                        u1: u1,
                        maxSurvivors: 8,
                        L: L,
                        isiOn: isiOn,
                        ditherAmplitude: ditherAmp,
                        survPtr: survAPtr,
                        expPtr: expPtr,
                        rankPtr: rnkPtr,
                        vIdxPtr: vIdxP,
                        curCount: &curCount,
                        peakAmp: &peakAmp,
                        prng: &tmpPrng,
                        transRem: &dummyTransRem,
                        transTot: 0,
                        actCoeffs: &actC,
                        srcCoeffs: coeffs,
                        tgtCoeffs: coeffs
                    )
                    if bit {
                        partial |= (UInt8(0x80) >> UInt8(bPos))
                    }
                }
                dsdOutputBytes[doneBytes] = partial
                doneBytes &+= 1
                rng0 = tmpPrng.s0
                rng1 = tmpPrng.s1

                if doneBytes < byteCount {
                    let remAfter = byteCount &- doneBytes
                    let chunkBytes = remAfter < 32 ? remAfter : 32
                    let chunkSamples = sampleCount &- (doneBytes &<< 3)
                    let nlRes = processSteadyBlockTrellis(
                        inputSamples: inputSamples.advanced(by: doneBytes &<< 3),
                        sampleCount: chunkSamples,
                        byteCount: chunkBytes,
                        tailNextSample: tailNextSample,
                        dsdOutputBytes: dsdOutputBytes.advanced(by: doneBytes),
                        maxSurvivors: 8,
                        L: L,
                        isiOn: isiOn,
                        ditherAmp: ditherAmp,
                        coeffs: coeffs,
                        survAPtr: survAPtr,
                        scratchRaw: scratchRaw,
                        initialCurCount: curCount,
                        initialPeakAmp: peakAmp,
                        initialPrngS0: rng0,
                        initialPrngS1: rng1
                    )
                    doneBytes &+= chunkBytes
                    curCount = nlRes.curCount
                    peakAmp = nlRes.peakAmp
                    rng0 = nlRes.prngS0
                    rng1 = nlRes.prngS1
                }
            }

            return (curCount, peakAmp, rng0, rng1)
        }

        return processSteadyBlockTrellis(
            inputSamples: inputSamples,
            sampleCount: sampleCount,
            byteCount: byteCount,
            tailNextSample: tailNextSample,
            dsdOutputBytes: dsdOutputBytes,
            maxSurvivors: maxSurvivors,
            L: L,
            isiOn: isiOn,
            ditherAmp: ditherAmp,
            coeffs: coeffs,
            survAPtr: survAPtr,
            scratchRaw: scratchRaw,
            initialCurCount: initialCurCount,
            initialPeakAmp: initialPeakAmp,
            initialPrngS0: initialPrngS0,
            initialPrngS1: initialPrngS1
        )
    }

    /// Обрабатывает блок оверсэмплированных `Double` отсчётов (`count` кратно 8)
    /// и упаковывает выходной DSD-поток побайтно (MSB-first: первый во времени бит -> bit 7)
    /// прямо в предвыделенный буфер `dsdOutputBytes`.
    /// При передаче предвыделенного `scratchRaw` (`4864` байта, выравнивание `64B`) гарантирует 0 аллокаций в куче.
    @inlinable
    public mutating func processBlockToDSDBytes(
        inputSamples: UnsafePointer<Double>,
        sampleCount: Int,
        lookaheadSample: Double,
        dsdOutputBytes: UnsafeMutablePointer<UInt8>,
        scratchRaw: UnsafeMutableRawPointer? = nil
    ) {
        let byteCount = sampleCount >> 3
        guard byteCount > 0 else { return }

        let maxSurvivors = min(max(trellisOrder.rawValue, 1), 16)
        let isiOn = isiRegularizerEnabled
        let L = tracebackDepth
        let ditherAmp = ditherAmplitude

        var curCount = activeSurvivorCount
        var peakAmp = peakIntegratorAmplitude
        var localPrng = prng
        let transRemInitial = transitionSamplesRemaining

        let lastIdx = sampleCount &- 1
        let lastSample = inputSamples[lastIdx]
        let tailNextSample: Double
        if (lookaheadSample - lastSample).magnitude <= 0.05 {
            tailNextSample = lookaheadSample
        } else if sampleCount >= 2 {
            tailNextSample = Self.fmin2(Self.fmax2(lastSample + (lastSample - inputSamples[sampleCount &- 2]), -0.99), 0.99)
        } else {
            tailNextSample = lastSample
        }

        // Быстрый стационарный тракт (>99.999% времени воспроизведения, когда морфинг профиля не активен)
        if transRemInitial == 0 {
            let steadyCoeffs = activeCoefficients
            if maxSurvivors == 1 {
                let res = withUnsafeMutablePointer(to: &survivors) { survARaw in
                    survARaw.withMemoryRebound(to: TrellisCandidatePath.self, capacity: 16) { survAPtr in
                        Self.processSteadyBlockM1(
                            inputSamples: inputSamples,
                            sampleCount: sampleCount,
                            byteCount: byteCount,
                            tailNextSample: tailNextSample,
                            dsdOutputBytes: dsdOutputBytes,
                            isiOn: isiOn,
                            ditherAmp: ditherAmp,
                            coeffs: steadyCoeffs,
                            survAPtr: survAPtr,
                            initialPeakAmp: peakAmp,
                            initialPrngS0: localPrng.s0,
                            initialPrngS1: localPrng.s1
                        )
                    }
                }
                activeSurvivorCount = res.curCount
                peakIntegratorAmplitude = res.peakAmp
                prng = Xoroshiro128Plus(seed0: res.prngS0, seed1: res.prngS1)
            } else if let preallocScratch = scratchRaw {
                let res = withUnsafeMutablePointer(to: &survivors) { survARaw in
                    survARaw.withMemoryRebound(to: TrellisCandidatePath.self, capacity: 16) { survAPtr in
                        Self.dispatchSteadyBlock(
                            inputSamples: inputSamples,
                            sampleCount: sampleCount,
                            byteCount: byteCount,
                            tailNextSample: tailNextSample,
                            dsdOutputBytes: dsdOutputBytes,
                            maxSurvivors: maxSurvivors,
                            L: L,
                            isiOn: isiOn,
                            ditherAmp: ditherAmp,
                            coeffs: steadyCoeffs,
                            survAPtr: survAPtr,
                            scratchRaw: preallocScratch,
                            initialCurCount: curCount,
                            initialPeakAmp: peakAmp,
                            initialPrngS0: localPrng.s0,
                            initialPrngS1: localPrng.s1
                        )
                    }
                }
                activeSurvivorCount = res.curCount
                peakIntegratorAmplitude = res.peakAmp
                prng = Xoroshiro128Plus(seed0: res.prngS0, seed1: res.prngS1)
            } else {
                let res = withUnsafeMutablePointer(to: &survivors) { survARaw in
                    survARaw.withMemoryRebound(to: TrellisCandidatePath.self, capacity: 16) { survAPtr in
                        withUnsafeTemporaryAllocation(byteCount: Self.steadyScratchByteCount, alignment: 64) { rawBuf in
                            Self.dispatchSteadyBlock(
                                inputSamples: inputSamples,
                                sampleCount: sampleCount,
                                byteCount: byteCount,
                                tailNextSample: tailNextSample,
                                dsdOutputBytes: dsdOutputBytes,
                                maxSurvivors: maxSurvivors,
                                L: L,
                                isiOn: isiOn,
                                ditherAmp: ditherAmp,
                                coeffs: steadyCoeffs,
                                survAPtr: survAPtr,
                                scratchRaw: rawBuf.baseAddress!,
                                initialCurCount: curCount,
                                initialPeakAmp: peakAmp,
                                initialPrngS0: localPrng.s0,
                                initialPrngS1: localPrng.s1
                            )
                        }
                    }
                }
                activeSurvivorCount = res.curCount
                peakIntegratorAmplitude = res.peakAmp
                prng = Xoroshiro128Plus(seed0: res.prngS0, seed1: res.prngS1)
            }
            return
        }

        var transRem = transRemInitial

        // Переходный тракт (5 мс морфинг коэффициентов при живом переключении профиля)
        var expanded = TrellisExpandedBank32()
        var rankBank = TrellisRankScoreBank32()
        var idxBank = TrellisIndexBank32()
        let transTot = transitionTotalSamples
        var actCoeffs = activeCoefficients
        let srcCoeffs = sourceCoefficients
        let tgtCoeffs = targetCoefficients

        withUnsafeMutablePointer(to: &survivors) { survRaw in
            survRaw.withMemoryRebound(to: TrellisCandidatePath.self, capacity: 16) { survPtr in
                withUnsafeMutablePointer(to: &expanded) { expRaw in
                    expRaw.withMemoryRebound(to: TrellisCandidatePath.self, capacity: 32) { expPtr in
                        withUnsafeMutablePointer(to: &rankBank) { rankRaw in
                            rankRaw.withMemoryRebound(to: Double.self, capacity: 32) { rankPtr in
                                withUnsafeMutablePointer(to: &idxBank) { idxRaw in
                                    idxRaw.withMemoryRebound(to: Int32.self, capacity: 32) { vIdxPtr in
                                        var sampleIdx = 0
                                        for byteIdx in 0..<byteCount {
                                            var packedByte: UInt8 = 0
                                            if sampleIdx &+ 8 < sampleCount {
                                                for bitPos in 0..<8 {
                                                    let bit = Self.stepBitCore(
                                                        u0: inputSamples[sampleIdx],
                                                        u1: inputSamples[sampleIdx &+ 1],
                                                        maxSurvivors: maxSurvivors,
                                                        L: L,
                                                        isiOn: isiOn,
                                                        ditherAmplitude: ditherAmp,
                                                        survPtr: survPtr,
                                                        expPtr: expPtr,
                                                        rankPtr: rankPtr,
                                                        vIdxPtr: vIdxPtr,
                                                        curCount: &curCount,
                                                        peakAmp: &peakAmp,
                                                        prng: &localPrng,
                                                        transRem: &transRem,
                                                        transTot: transTot,
                                                        actCoeffs: &actCoeffs,
                                                        srcCoeffs: srcCoeffs,
                                                        tgtCoeffs: tgtCoeffs
                                                    )
                                                    if bit {
                                                        packedByte |= (UInt8(0x80) >> UInt8(bitPos))
                                                    }
                                                    sampleIdx &+= 1
                                                }
                                            } else {
                                                for bitPos in 0..<8 {
                                                    let u0 = inputSamples[sampleIdx]
                                                    let u1 = (sampleIdx &+ 1 < sampleCount) ? inputSamples[sampleIdx &+ 1] : tailNextSample
                                                    let bit = Self.stepBitCore(
                                                        u0: u0,
                                                        u1: u1,
                                                        maxSurvivors: maxSurvivors,
                                                        L: L,
                                                        isiOn: isiOn,
                                                        ditherAmplitude: ditherAmp,
                                                        survPtr: survPtr,
                                                        expPtr: expPtr,
                                                        rankPtr: rankPtr,
                                                        vIdxPtr: vIdxPtr,
                                                        curCount: &curCount,
                                                        peakAmp: &peakAmp,
                                                        prng: &localPrng,
                                                        transRem: &transRem,
                                                        transTot: transTot,
                                                        actCoeffs: &actCoeffs,
                                                        srcCoeffs: srcCoeffs,
                                                        tgtCoeffs: tgtCoeffs
                                                    )
                                                    if bit {
                                                        packedByte |= (UInt8(0x80) >> UInt8(bitPos))
                                                    }
                                                    sampleIdx &+= 1
                                                }
                                            }
                                            dsdOutputBytes[byteIdx] = packedByte
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        activeSurvivorCount = curCount
        peakIntegratorAmplitude = peakAmp
        prng = localPrng
        transitionSamplesRemaining = transRem
        activeCoefficients = actCoeffs
    }
}
