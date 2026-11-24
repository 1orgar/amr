import XCTest
import Foundation
import Accelerate
import CoreAudio
@testable import AppleMusicRemoteMac

final class SDMVerificationTests: XCTestCase {

    // MARK: - 1. DoP v1.1 Bit-Exact Packing, Alternating Markers & Underrun Continuity

    func testDoPBitExactPackingAndAlternatingMarkers() {
        var packer = DoPFramePacker()
        let frameCount = 64
        let byteCount = frameCount * 2

        var dsdLeft = [UInt8](repeating: 0, count: byteCount)
        var dsdRight = [UInt8](repeating: 0, count: byteCount)
        for i in 0..<byteCount {
            dsdLeft[i] = UInt8((i * 73 + 19) & 0xFF)
            dsdRight[i] = UInt8((i * 41 + 0x5A) & 0xFF)
        }

        var outPCM = [Int32](repeating: 0, count: frameCount * 2)
        dsdLeft.withUnsafeBufferPointer { lPtr in
            dsdRight.withUnsafeBufferPointer { rPtr in
                outPCM.withUnsafeMutableBufferPointer { outPtr in
                    packer.packS32LE(
                        dsdLeftBytes: lPtr.baseAddress!,
                        dsdRightBytes: rPtr.baseAddress!,
                        dopFrameCount: frameCount,
                        outputInterleaved32: outPtr.baseAddress!
                    )
                }
            }
        }

        // Verify marker alternation (0x05 -> 0xFA -> 0x05 ...) and zeroed LSB [7:0]
        for f in 0..<frameCount {
            let expectedMarker: UInt32 = (f % 2 == 0) ? 0x05 : 0xFA
            let wordL = UInt32(bitPattern: outPCM[f * 2])
            let wordR = UInt32(bitPattern: outPCM[f * 2 + 1])

            XCTAssertEqual((wordL >> 24) & 0xFF, expectedMarker, "Left DoP marker mismatch at frame \(f)")
            XCTAssertEqual((wordR >> 24) & 0xFF, expectedMarker, "Right DoP marker mismatch at frame \(f)")
            XCTAssertEqual(wordL & 0xFF, 0, "Left DoP padding LSB must be 0x00 at frame \(f)")
            XCTAssertEqual(wordR & 0xFF, 0, "Right DoP padding LSB must be 0x00 at frame \(f)")
        }

        // Verify 100% lossless round-trip extraction
        var unpackedL = [UInt8](repeating: 0, count: byteCount)
        var unpackedR = [UInt8](repeating: 0, count: byteCount)
        let markersValid = outPCM.withUnsafeBufferPointer { inPtr in
            unpackedL.withUnsafeMutableBufferPointer { ulPtr in
                unpackedR.withUnsafeMutableBufferPointer { urPtr in
                    DoPFramePacker.unpackS32LE(
                        interleaved32: inPtr.baseAddress!,
                        dopFrameCount: frameCount,
                        outLeftBytes: ulPtr.baseAddress!,
                        outRightBytes: urPtr.baseAddress!
                    )
                }
            }
        }
        XCTAssertTrue(markersValid, "DoP unpack validator should confirm valid alternating markers")
        XCTAssertEqual(unpackedL, dsdLeft, "Unpacked Left DSD bitstream must be bit-identical to input")
        XCTAssertEqual(unpackedR, dsdRight, "Unpacked Right DSD bitstream must be bit-identical to input")

        // Verify neutral DSD silence (0x69 = 0b01101001, zero DC offset)
        var silencePCM = [Int32](repeating: 0, count: 16)
        silencePCM.withUnsafeMutableBufferPointer { ptr in
            packer.fillNeutralDSDSilenceS32LE(dopFrameCount: 8, outputInterleaved32: ptr.baseAddress!)
        }
        for f in 0..<8 {
            let wordL = UInt32(bitPattern: silencePCM[f * 2])
            let payload16 = (wordL >> 8) & 0xFFFF
            XCTAssertEqual(payload16, 0x6969, "Neutral DSD silence payload must be 0x6969")
            XCTAssertEqual(payload16.nonzeroBitCount, 8, "Neutral DSD silence must have exact 50% ones density")
        }

        // Verify monotonic 0x05 <-> 0xFA marker continuity across ring underruns and odd callback frame counts
        let ring = SPSCAtomicRingBuffer(capacityWords: 512)
        var ioDoPState = DoPPackerState()
        var emittedFrames: [Int32] = []

        // Push 11 frames starting at 0x05, read 17 frames (6 silence tail frames), then push 9 frames from a reset producer!
        let callbackSizes = [17, 13, 31, 8, 25]
        for (step, cbFrames) in callbackSizes.enumerated() {
            if step % 2 == 0 {
                // Deliberately reset producer DoPPackerState to simulate resync / fresh prefill with opposite phase
                var freshProducer = DoPPackerState()
                let pushFrames = 11
                let srcBytes = [UInt8](repeating: 0x96, count: pushFrames * 2)
                var tmpWords = [Int32](repeating: 0, count: pushFrames * 2)
                srcBytes.withUnsafeBufferPointer { bPtr in
                    tmpWords.withUnsafeMutableBufferPointer { wPtr in
                        DoPPackerState.packStereoDSDBytesToDoP32(
                            state: &freshProducer,
                            dsdLeftBytes: bPtr.baseAddress!,
                            dsdRightBytes: bPtr.baseAddress!,
                            dopFrameCount: pushFrames,
                            interleavedOutput: wPtr.baseAddress!
                        )
                    }
                }
                _ = tmpWords.withUnsafeBufferPointer { ring.write(from: $0.baseAddress!, count: pushFrames * 2) }
            }

            var cbOut = [Int32](repeating: 0, count: cbFrames * 2)
            cbOut.withUnsafeMutableBufferPointer { outPtr in
                fillAndStampInterleavedS32FromRing(
                    ring: ring,
                    dstInt32: outPtr.baseAddress!,
                    stereoFrames: cbFrames,
                    isDoP: true,
                    dopState: &ioDoPState
                )
            }
            emittedFrames.append(contentsOf: cbOut)
        }

        let totalEmittedStereoFrames = emittedFrames.count / 2
        for f in 0..<totalEmittedStereoFrames {
            let expected: UInt32 = (f % 2 == 0) ? 0x05 : 0xFA
            let mL = (UInt32(bitPattern: emittedFrames[f * 2]) >> 24) & 0xFF
            let mR = (UInt32(bitPattern: emittedFrames[f * 2 + 1]) >> 24) & 0xFF
            XCTAssertEqual(mL, expected, "IOProc DoP Left marker broke continuity at frame \(f)")
            XCTAssertEqual(mR, expected, "IOProc DoP Right marker broke continuity at frame \(f)")
        }
    }

    // MARK: - 2. 7EC Modulator Closed-Loop Spectral SNR (>152 dB), THD (<-155 dBc) & -1.5 dBFS Stability

    /// Computes in-band (20 Hz .. 20 kHz) SNR and THD (harmonics 2..9) using a periodic 4-term Blackman-Harris FFT.
    private func measureClosedLoopSpectrum(
        bits: [Double],
        fsDSD: Double,
        log2N: Int
    ) -> (snrDB: Double, thdDB: Double) {
        let nFFT = 1 << log2N
        precondition(bits.count >= nFFT)
        let offset = bits.count - nFFT

        var re = [Double](repeating: 0.0, count: nFFT)
        var im = [Double](repeating: 0.0, count: nFFT)

        // Periodic Schreier C^7 (sin^8(pi * n / N), Hann^4) high-order SDM window:
        // exact w[0] == 0.0 in IEEE-754 binary64 and -54 dB/oct sidelobe decay (> +42 dB/oct 7th-order NTF rise)
        let piOverN = Double.pi / Double(nFFT)
        for n in 0..<nFFT {
            let s = sin(piOverN * Double(n))
            let s2 = s * s
            let s4 = s2 * s2
            let w = s4 * s4
            re[n] = bits[offset + n] * w
        }

        guard let setup = vDSP_create_fftsetupD(vDSP_Length(log2N), FFTRadix(kFFTRadix2)) else {
            return (0.0, 0.0)
        }
        defer { vDSP_destroy_fftsetupD(setup) }

        re.withUnsafeMutableBufferPointer { reBuf in
            im.withUnsafeMutableBufferPointer { imBuf in
                var split = DSPDoubleSplitComplex(realp: reBuf.baseAddress!, imagp: imBuf.baseAddress!)
                vDSP_fft_zipD(setup, &split, 1, vDSP_Length(log2N), FFTDirection(FFT_FORWARD))
            }
        }

        let df = fsDSD / Double(nFFT)
        let minBin = max(5, Int((20.0 / df).rounded(.up)))
        let maxBin = Int((20_000.0 / df).rounded(.down))

        // Locate fundamental bin inside 20 Hz .. 20 kHz
        var fundBin = minBin
        var maxPow = 0.0
        for k in minBin...maxBin {
            let p = re[k] * re[k] + im[k] * im[k]
            if p > maxPow {
                maxPow = p
                fundBin = k
            }
        }

        let sigLo = max(minBin, fundBin - 7)
        let sigHi = min(maxBin, fundBin + 7)
        var sigPow = 0.0
        for k in sigLo...sigHi {
            sigPow += re[k] * re[k] + im[k] * im[k]
        }

        var harmPow = 0.0
        var harmBins = Set<Int>()
        for h in 2...9 {
            let hc = fundBin * h
            if hc <= maxBin {
                for b in max(minBin, hc - 5)...min(maxBin, hc + 5) {
                    harmPow += re[b] * re[b] + im[b] * im[b]
                    harmBins.insert(b)
                }
            }
        }

        var noisePow = 0.0
        for k in minBin...maxBin {
            if k >= sigLo && k <= sigHi { continue }
            noisePow += re[k] * re[k] + im[k] * im[k]
        }

        let snrDB = 10.0 * log10(max(sigPow, 1.0e-30) / max(noisePow, 1.0e-30))
        let thdDB = 10.0 * log10(max(harmPow, 1.0e-30) / max(sigPow, 1.0e-30))
        _ = harmBins
        return (snrDB, thdDB)
    }

    func testSDM7StabilityAndSNRAcrossProfiles() {
        let profiles: [SDM7Profile] = [.transient, .balanced, .superWide]
        let grids: [BaseClockGrid] = [.grid44k1, .grid48k]

        // 2a. Closed-loop DSD256 spectral verification at -3.5 dBFS (131072-pt FFT + 4096 warmup)
        let log2N = 17
        let nFFT = 1 << log2N // 131_072
        let warmup = 4096
        let totalSpecSamples = warmup + nFFT
        let totalSpecDoPFrames = totalSpecSamples / 16
        let fsDSD44 = Double(BaseClockGrid.grid44k1.rawValue * 256)
        let coherentFreqHz = 16.0 * fsDSD44 / Double(nFFT) // ~1378.125 Hz coherent bin
        let amp35 = pow(10.0, -3.5 / 20.0)

        var specInput = [Double](repeating: 0.0, count: totalSpecSamples)
        let phaseInc = 2.0 * Double.pi * coherentFreqHz / fsDSD44
        for n in 0..<totalSpecSamples {
            specInput[n] = amp35 * sin(phaseInc * Double(n))
        }

        for profile in profiles {
            let order: TrellisOrder = (profile == .superWide) ? .m16 : .m8
            var modulator = TrellisViterbiModulator(
                profile: profile,
                rate: .dsd256,
                grid: .grid44k1,
                trellisOrder: order,
                tracebackDepth: 8,
                isiRegularizerEnabled: true,
                ditherAmplitude: 1.0e-7,
                channelSeed: 0x123456789ABCDEF0
            )

            var specBytes = [UInt8](repeating: 0, count: totalSpecDoPFrames * 2)
            specInput.withUnsafeBufferPointer { inPtr in
                specBytes.withUnsafeMutableBufferPointer { outPtr in
                    modulator.processBlockToDSDBytes(
                        inputSamples: inPtr.baseAddress!,
                        sampleCount: totalSpecSamples,
                        lookaheadSample: 0.0,
                        dsdOutputBytes: outPtr.baseAddress!
                    )
                }
            }

            var bits = [Double](repeating: 0.0, count: totalSpecSamples)
            for bIdx in 0..<specBytes.count {
                let byte = specBytes[bIdx]
                let base = bIdx &<< 3
                bits[base + 0] = ((byte & 0x80) != 0) ? 1.0 : -1.0
                bits[base + 1] = ((byte & 0x40) != 0) ? 1.0 : -1.0
                bits[base + 2] = ((byte & 0x20) != 0) ? 1.0 : -1.0
                bits[base + 3] = ((byte & 0x10) != 0) ? 1.0 : -1.0
                bits[base + 4] = ((byte & 0x08) != 0) ? 1.0 : -1.0
                bits[base + 5] = ((byte & 0x04) != 0) ? 1.0 : -1.0
                bits[base + 6] = ((byte & 0x02) != 0) ? 1.0 : -1.0
                bits[base + 7] = ((byte & 0x01) != 0) ? 1.0 : -1.0
            }

            let metrics = measureClosedLoopSpectrum(bits: bits, fsDSD: fsDSD44, log2N: log2N)
            XCTAssertGreaterThanOrEqual(
                metrics.snrDB,
                152.0,
                "Closed-loop DSD256 SNR must exceed 152 dB for \(profile.displayName) (got \(String(format: "%.2f", metrics.snrDB)) dB)"
            )
            XCTAssertLessThanOrEqual(
                metrics.thdDB,
                -155.0,
                "Closed-loop DSD256 THD must be <= -155 dBc for \(profile.displayName) (got \(String(format: "%.2f", metrics.thdDB)) dBc)"
            )
        }

        // 2b. Extreme -1.5 dBFS (0.8414 FS) overload stability across both clock grids and all profiles
        for grid in grids {
            let fsDSD = Double(grid.rawValue * 256)
            let numSamples = 16384
            let dopFrames = numSamples / 16
            let fBin = 7.0
            let freqHz = fBin * fsDSD / Double(numSamples)

            for profile in profiles {
                var modulator = TrellisViterbiModulator(
                    profile: profile,
                    rate: .dsd256,
                    grid: grid,
                    trellisOrder: .m8,
                    tracebackDepth: 8,
                    isiRegularizerEnabled: true,
                    ditherAmplitude: 0.0,
                    channelSeed: 0x123456789ABCDEF0
                )

                let amp = pow(10.0, -1.5 / 20.0)
                var input = [Double](repeating: 0.0, count: numSamples)
                for n in 0..<numSamples {
                    input[n] = amp * sin(2.0 * Double.pi * freqHz * Double(n) / fsDSD)
                }

                var dsdBytes = [UInt8](repeating: 0, count: dopFrames * 2)
                input.withUnsafeBufferPointer { inPtr in
                    dsdBytes.withUnsafeMutableBufferPointer { outPtr in
                        modulator.processBlockToDSDBytes(
                            inputSamples: inPtr.baseAddress!,
                            sampleCount: numSamples,
                            lookaheadSample: 0.0,
                            dsdOutputBytes: outPtr.baseAddress!
                        )
                    }
                }

                let peakState = modulator.consumePeakIntegratorAmplitude()
                XCTAssertFalse(peakState.isNaN, "Modulator state must not be NaN (\(profile.displayName))")
                XCTAssertFalse(peakState.isInfinite, "Modulator state must not be Infinite (\(profile.displayName))")
                XCTAssertLessThanOrEqual(
                    peakState,
                    1.38,
                    "Modulator resonator states must stay strictly bounded <= 1.38 at -1.5 dBFS (\(profile.displayName))"
                )

                var bits = [Double](repeating: 0.0, count: numSamples)
                for bIdx in 0..<dsdBytes.count {
                    let byte = dsdBytes[bIdx]
                    for bit in 0..<8 {
                        let isOne = ((byte >> (7 - bit)) & 1) == 1
                        bits[bIdx * 8 + bit] = isOne ? 1.0 : -1.0
                    }
                }

                let twoPiOverN = 2.0 * Double.pi / Double(numSamples)
                var reSig = 0.0
                var imSig = 0.0
                for n in 0..<numSamples {
                    let angle = twoPiOverN * fBin * Double(n)
                    reSig += bits[n] * cos(angle)
                    imSig += bits[n] * sin(angle)
                }
                let recoveredAmp = 2.0 * sqrt(reSig * reSig + imSig * imSig) / Double(numSamples)
                XCTAssertEqual(
                    recoveredAmp,
                    amp,
                    accuracy: 0.02,
                    "Recovered 1-bit fundamental amplitude must match input -1.5 dBFS sine (\(profile.displayName), \(grid))"
                )
            }
        }
    }

    // MARK: - 3. Idle-Tone Prevention & Zero-Distortion ISI Regularizer

    func testIdleToneAndISIRegularizer() {
        let numSamples = 16384
        let dopFrames = numSamples / 16
        let dcInput = [Double](repeating: pow(10.0, -90.0 / 20.0), count: numSamples)
        var dsdBytes = [UInt8](repeating: 0, count: dopFrames * 2)

        var mod = TrellisViterbiModulator(
            profile: .balanced,
            rate: .dsd256,
            grid: .grid44k1,
            trellisOrder: .m8,
            tracebackDepth: 8,
            isiRegularizerEnabled: true,
            ditherAmplitude: 1.5e-5,
            channelSeed: 0xCAFEBABE12345678
        )

        dcInput.withUnsafeBufferPointer { inPtr in
            dsdBytes.withUnsafeMutableBufferPointer { outPtr in
                mod.processBlockToDSDBytes(
                    inputSamples: inPtr.baseAddress!,
                    sampleCount: numSamples,
                    lookaheadSample: 0.0,
                    dsdOutputBytes: outPtr.baseAddress!
                )
            }
        }

        var onesCount = 0
        var transitions = 0
        var prevBit: UInt8 = (dsdBytes[0] >> 7) & 1
        for byte in dsdBytes {
            onesCount += byte.nonzeroBitCount
            for bitPos in 0..<8 {
                let curBit = (byte >> (7 - bitPos)) & 1
                if curBit != prevBit {
                    transitions += 1
                }
                prevBit = curBit
            }
        }

        let onesRatio = Double(onesCount) / Double(numSamples)
        let transitionDensity = Double(transitions) / Double(numSamples)

        XCTAssertEqual(onesRatio, 0.50, accuracy: 0.015, "DSD silence ones density must be ~50%")
        XCTAssertGreaterThan(transitionDensity, 0.35, "Transition density must remain healthy without DC lock-up")
        XCTAssertLessThan(transitionDensity, 0.68, "Transition density must be regularized against high-frequency limit cycles")
    }

    // MARK: - 4. Oversampler Passband, Minimum-Phase Cepstrum, Half-Band Phase Order, SampleRateRouter & NOS PCM

    func testOversamplerPassbandAndDXDBypass() {
        // 4a. SampleRateRouter ClockGridPolicy & ТЗ §2.2.2 low-OSR rule verification
        var cfg = EngineConfiguration()
        cfg.mode = .sdmDoP
        cfg.dsdRate = .dsd256
        cfg.clockPolicy = .adaptiveDualGrid

        let plan44 = SampleRateRouter.resolveRoute(
            inputSampleRateHz: 44_100,
            configuration: cfg,
            supportedDeviceSampleRates: [44100, 48000, 176400, 352800, 705600, 768000]
        )
        XCTAssertEqual(plan44.effectiveMode, .sdmDoP)
        XCTAssertEqual(plan44.baseGrid, .grid44k1)
        XCTAssertEqual(plan44.dsdMultiplier, .dsd256)
        XCTAssertEqual(plan44.dopCarrierRateHz, 705_600)
        XCTAssertEqual(plan44.targetModulatorRateHz / plan44.inputSampleRateHz, 256)
        XCTAssertFalse(plan44.usesASRC)

        let plan96 = SampleRateRouter.resolveRoute(
            inputSampleRateHz: 96_000,
            configuration: cfg,
            supportedDeviceSampleRates: [44100, 48000, 176400, 352800, 705600, 768000]
        )
        XCTAssertEqual(plan96.baseGrid, .grid48k)
        XCTAssertEqual(plan96.dopCarrierRateHz, 768_000)
        XCTAssertEqual(plan96.targetModulatorRateHz / plan96.inputSampleRateHz, 128)
        XCTAssertFalse(plan96.usesASRC)

        // DXD 352.8 kHz -> DSD256 has OSR = 32 >= 32: stays in SDM DoP with Stage-1 DXD FIR bypass
        let planDXD352 = SampleRateRouter.resolveRoute(
            inputSampleRateHz: 352_800,
            configuration: cfg,
            supportedDeviceSampleRates: [44100, 352800, 705600]
        )
        XCTAssertEqual(planDXD352.effectiveMode, .sdmDoP)
        XCTAssertTrue(planDXD352.usesDXDBypass, "352.8 kHz -> DSD256 (OSR=32) should bypass Stage-1 DXD FIR")

        // ТЗ §2.2.2: 705.6 kHz -> DSD256 has OSR = 16 < 32: must auto-bypass to HQ NOS PCM!
        let planDXD705 = SampleRateRouter.resolveRoute(
            inputSampleRateHz: 705_600,
            configuration: cfg,
            supportedDeviceSampleRates: [44100, 352800, 705600]
        )
        XCTAssertEqual(planDXD705.effectiveMode, .hqNOSPCM, "OSR = 16 < 32 must automatically switch to HQ NOS PCM per ТЗ §2.2.2")
        XCTAssertTrue(planDXD705.usesDXDBypass)

        cfg.clockPolicy = .strictSACD44k1
        let planStrict = SampleRateRouter.resolveRoute(
            inputSampleRateHz: 96_000,
            configuration: cfg,
            supportedDeviceSampleRates: [44100, 352800, 705600]
        )
        XCTAssertEqual(planStrict.baseGrid, .grid44k1)
        XCTAssertEqual(planStrict.dopCarrierRateHz, 705_600)
        XCTAssertTrue(planStrict.usesASRC)

        // 4b. AccelerateAMXOversampler passband flatness (1 kHz & 18 kHz) in BOTH Linear & Minimum Phase + Half-Band continuity
        let inFrames = 128
        for phaseMode in [OversamplerPhaseMode.linearPhase, OversamplerPhaseMode.minimumPhase] {
            let oversampler = AccelerateAMXOversampler(
                phaseMode: phaseMode,
                tapsPerPhase: 128,
                maxInputFrames: 256
            )
            // Test full 256x cascade (Stage 1 Polyphase 16x + Stage 2 HB63 2x + Stage 3 HB31 x3 8x)
            let outFrames256 = inFrames * 256
            let outBuf = AlignedPlanarDoubleBuffer(capacityFrames: outFrames256 + 1024)

            for testFreqHz in [1_000.0, 18_000.0] {
                oversampler.reset()
                var inL = [Double](repeating: 0.0, count: inFrames)
                var inR = [Double](repeating: 0.0, count: inFrames)
                var producedFrames = 0

                for block in 0..<8 {
                    for i in 0..<inFrames {
                        let sampleIndex = block * inFrames + i
                        let phase = 2.0 * Double.pi * testFreqHz * Double(sampleIndex) / 44_100.0
                        inL[i] = 0.668 * sin(phase)
                        inR[i] = 0.668 * cos(phase)
                    }
                    inL.withUnsafeBufferPointer { il in
                        inR.withUnsafeBufferPointer { ir in
                            producedFrames = oversampler.oversampleStereoBlock(
                                inputL: il.baseAddress!,
                                inputR: ir.baseAddress!,
                                inputFrames: inFrames,
                                inputRateHz: 44_100,
                                targetRateHz: 44_100 * 256,
                                outputBuffer: outBuf
                            )
                        }
                    }
                }

                XCTAssertEqual(producedFrames, outFrames256)
                var peakOutL = 0.0
                var maxAdjacentStep = 0.0
                for i in 0..<producedFrames {
                    let v = abs(outBuf.left[i])
                    if v > peakOutL { peakOutL = v }
                    if i > 0 {
                        let step = abs(outBuf.left[i] - outBuf.left[i - 1])
                        if step > maxAdjacentStep { maxAdjacentStep = step }
                    }
                }

                XCTAssertEqual(
                    peakOutL,
                    0.668,
                    accuracy: 0.015,
                    "Oversampler (\(phaseMode.rawValue)) passband gain at \(Int(testFreqHz)) Hz must be unity (0.0 dB)"
                )
                // Theoretical max adjacent step for 18 kHz sine at 11.2896 MHz is 0.668 * 2*pi*18000/11289600 = 0.0067.
                // Reversed Half-Band phases would cause ~2x..3x alternating sample jumps!
                let theoreticalStep = 0.668 * 2.0 * Double.pi * testFreqHz / Double(44_100 * 256)
                XCTAssertLessThanOrEqual(
                    maxAdjacentStep,
                    theoreticalStep * 1.15,
                    "Half-Band causal phase order must produce smooth interpolation without Fs/2 sample reversal (\(phaseMode.rawValue), \(Int(testFreqHz)) Hz)"
                )
            }
        }

        // 4c. Cross-grid Kaiser Polyphase ASRC (48 kHz -> 705.6 kHz) continuity & unity gain
        let asrcOversampler = AccelerateAMXOversampler(phaseMode: .linearPhase, tapsPerPhase: 128, maxInputFrames: 256)
        let asrcBuf = AlignedPlanarDoubleBuffer(capacityFrames: 8192)
        var totalIn = 0
        var totalOut = 0
        var asrcPeak = 0.0
        for block in 0..<20 {
            var inL = [Double](repeating: 0.0, count: 160) // 160 frames @ 48 kHz -> exact 2352 frames @ 705.6 kHz
            var inR = [Double](repeating: 0.0, count: 160)
            for i in 0..<160 {
                let ph = 2.0 * Double.pi * 1_000.0 * Double(block * 160 + i) / 48_000.0
                inL[i] = 0.5 * sin(ph)
                inR[i] = 0.5 * cos(ph)
            }
            let outCount = inL.withUnsafeBufferPointer { il in
                inR.withUnsafeBufferPointer { ir in
                    asrcOversampler.oversampleStereoBlock(
                        inputL: il.baseAddress!,
                        inputR: ir.baseAddress!,
                        inputFrames: 160,
                        inputRateHz: 48_000,
                        targetRateHz: 705_600,
                        outputBuffer: asrcBuf
                    )
                }
            }
            totalIn += 160
            totalOut += outCount
            if block >= 6 {
                for i in 0..<outCount {
                    asrcPeak = max(asrcPeak, abs(asrcBuf.left[i]))
                }
            }
        }
        let expectedRatio = 705_600.0 / 48_000.0
        XCTAssertEqual(Double(totalOut) / Double(totalIn), expectedRatio, accuracy: 0.02, "ASRC output/input frame ratio must match 705.6/48.0")
        XCTAssertEqual(asrcPeak, 0.5, accuracy: 0.015, "Kaiser polyphase ASRC passband gain must be unity")

        // 4d. NOSPCMDitherQuantizer (LNS15) verification
        var inL = [Double](repeating: 0.0, count: inFrames)
        var inR = [Double](repeating: 0.0, count: inFrames)
        for i in 0..<inFrames {
            let ph = 2.0 * Double.pi * 1000.0 * Double(i) / 44_100.0
            inL[i] = 0.668 * sin(ph)
            inR[i] = 0.668 * cos(ph)
        }
        var quantizerL = NOSPCMDitherQuantizer(mode: .lns15, targetBits: 24)
        var quantizerR = NOSPCMDitherQuantizer(mode: .lns15, targetBits: 24)
        var pcmOut = [Int32](repeating: 0, count: inFrames * 2)
        inL.withUnsafeBufferPointer { il in
            inR.withUnsafeBufferPointer { ir in
                pcmOut.withUnsafeMutableBufferPointer { outPtr in
                    NOSPCMDitherQuantizer.quantizeStereoBlock(
                        left: il.baseAddress!,
                        right: ir.baseAddress!,
                        frameCount: inFrames,
                        quantizerL: &quantizerL,
                        quantizerR: &quantizerR,
                        interleavedOut: outPtr.baseAddress!
                    )
                }
            }
        }
        let maxQuantized = pcmOut.map { abs(Double($0)) }.max() ?? 0.0
        XCTAssertGreaterThan(maxQuantized, Double(Int32.max) * 0.60, "LNS15 quantizer should scale to 24-bit MSB-aligned Int32")
    }

    // MARK: - 5. HeadroomISPProcessor 2-Sample Lookahead Protection Against +3 dB Inter-Sample Peaks

    func testHeadroomISPProcessorLookaheadProtection() {
        let isp = HeadroomISPProcessor(headroomDB: 0.0, ispProtectionEnabled: true)
        let frameCount = 64
        // Classic Fs/4 +3.01 dB inter-sample peak sequence: [+0.85, +0.85, -0.85, -0.85] -> true peak ~ 1.202 (> 0.9441 ceiling)
        var inL = [Float](repeating: 0.0, count: frameCount)
        var inR = [Float](repeating: 0.0, count: frameCount)
        for i in 8..<frameCount {
            let sign: Float = (((i - 8) / 2) % 2 == 0) ? 1.0 : -1.0
            inL[i] = 0.85 * sign
            inR[i] = 0.85 * sign
        }

        var outL = [Double](repeating: 0.0, count: frameCount)
        var outR = [Double](repeating: 0.0, count: frameCount)
        inL.withUnsafeBufferPointer { il in
            inR.withUnsafeBufferPointer { ir in
                outL.withUnsafeMutableBufferPointer { ol in
                    outR.withUnsafeMutableBufferPointer { orp in
                        isp.processPlanarFloat32ToDouble(
                            inputL: il.baseAddress!,
                            inputR: ir.baseAddress!,
                            outputL: ol.baseAddress!,
                            outputR: orp.baseAddress!,
                            frameCount: frameCount
                        )
                    }
                }
            }
        }

        XCTAssertGreaterThan(isp.ispClipCount, 0, "ISP detector should trigger on +3 dB Fs/4 inter-sample peaks")
        var maxTruePeakOut = 0.0
        for i in 3..<frameCount {
            let tp = HeadroomISPProcessor.estimateTruePeak4x(
                x0: outL[i - 3],
                x1: outL[i - 2],
                x2: outL[i - 1],
                x3: outL[i]
            )
            maxTruePeakOut = max(maxTruePeakOut, tp)
        }
        XCTAssertLessThanOrEqual(
            maxTruePeakOut,
            0.955,
            "2-sample lookahead ISP limiter must attenuate BEFORE the inter-sample peak exits (max TP = \(maxTruePeakOut))"
        )
    }

    // MARK: - 6. Mode C Sony .dsf Native 1-Bit File -> LSB-to-MSB Reversal -> DoP Streaming

    func testModeCLocalDSFStreamingToDoP() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("amr_test_\(UUID().uuidString).dsf")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let blockSizePerCh = 64 // 32 DoP frames per block
        let dataBytesTotal = blockSizePerCh * 2
        var dsfData = Data(count: 92 + dataBytesTotal)

        // Build valid 92-byte Sony DSF header ('DSD ' + 'fmt ' + 'data')
        dsfData.replaceSubrange(0..<4, with: Data("DSD ".utf8))
        dsfData.withUnsafeMutableBytes { raw in
            raw.storeBytes(of: UInt64(28).littleEndian, toByteOffset: 4, as: UInt64.self)
            raw.storeBytes(of: UInt64(92 + dataBytesTotal).littleEndian, toByteOffset: 12, as: UInt64.self)
            raw.storeBytes(of: UInt64(0).littleEndian, toByteOffset: 20, as: UInt64.self)
        }
        dsfData.replaceSubrange(28..<32, with: Data("fmt ".utf8))
        dsfData.withUnsafeMutableBytes { raw in
            raw.storeBytes(of: UInt64(52).littleEndian, toByteOffset: 32, as: UInt64.self)
            raw.storeBytes(of: UInt32(1).littleEndian, toByteOffset: 40, as: UInt32.self) // format version 1
            raw.storeBytes(of: UInt32(0).littleEndian, toByteOffset: 44, as: UInt32.self) // DSD raw
            raw.storeBytes(of: UInt32(2).littleEndian, toByteOffset: 48, as: UInt32.self) // stereo
            raw.storeBytes(of: UInt32(2).littleEndian, toByteOffset: 52, as: UInt32.self) // 2 ch
            raw.storeBytes(of: UInt32(11_289_600).littleEndian, toByteOffset: 56, as: UInt32.self) // DSD256
            raw.storeBytes(of: UInt32(1).littleEndian, toByteOffset: 60, as: UInt32.self) // 1-bit LSB-first
            raw.storeBytes(of: UInt64(blockSizePerCh * 8).littleEndian, toByteOffset: 64, as: UInt64.self)
            raw.storeBytes(of: UInt32(blockSizePerCh).littleEndian, toByteOffset: 68, as: UInt32.self)
            raw.storeBytes(of: UInt32(0).littleEndian, toByteOffset: 72, as: UInt32.self)
        }
        dsfData.replaceSubrange(80..<84, with: Data("data".utf8))
        dsfData.withUnsafeMutableBytes { raw in
            raw.storeBytes(of: UInt64(12 + dataBytesTotal).littleEndian, toByteOffset: 84, as: UInt64.self)
        }

        // Known LSB-first bytes: 0x01 (0b00000001) -> MSB-first 0x80; 0xB2 (0b10110010) -> MSB-first 0x4D (0b01001101)
        for i in 0..<blockSizePerCh {
            dsfData[92 + i] = (i % 2 == 0) ? 0x01 : 0xB2
            dsfData[92 + blockSizePerCh + i] = 0x96 // 0b10010110 -> reversed 0b01101001 = 0x69!
        }
        try dsfData.write(to: tempURL)

        let source = LocalAudioFileSource()
        try source.open(url: tempURL)
        XCTAssertTrue(source.isNativeDSD)
        XCTAssertEqual(source.sampleRateHz, 11_289_600)

        let ring = SPSCAtomicRingBuffer(capacityWords: 256)
        var dopState = DoPPackerState()
        let framesWritten = source.readNextDSFDoPWords(into: ring, dopPackerState: &dopState, maxDoPFrames: 64)
        XCTAssertEqual(framesWritten, blockSizePerCh / 2)

        var packedWords = [Int32](repeating: 0, count: framesWritten * 2)
        let wordsRead = packedWords.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, count: framesWritten * 2) }
        XCTAssertEqual(wordsRead, framesWritten * 2)

        var unpackedL = [UInt8](repeating: 0, count: blockSizePerCh)
        var unpackedR = [UInt8](repeating: 0, count: blockSizePerCh)
        let validMarkers = packedWords.withUnsafeBufferPointer { inPtr in
            unpackedL.withUnsafeMutableBufferPointer { ul in
                unpackedR.withUnsafeMutableBufferPointer { ur in
                    DoPFramePacker.unpackS32LE(
                        interleaved32: inPtr.baseAddress!,
                        dopFrameCount: framesWritten,
                        outLeftBytes: ul.baseAddress!,
                        outRightBytes: ur.baseAddress!
                    )
                }
            }
        }
        XCTAssertTrue(validMarkers)
        for i in 0..<blockSizePerCh {
            XCTAssertEqual(unpackedL[i], (i % 2 == 0) ? 0x80 : 0x4D, "Left DSF byte \(i) must be bit-reversed from LSB-first to MSB-first")
            XCTAssertEqual(unpackedR[i], 0x69, "Right DSF byte \(i) 0x96 reversed must equal 0x69")
        }
    }

    // MARK: - 7. Metal GPU df64 Double-Float Precision vs AMX FP64 Reference

    func testMetalDF64OversamplerPrecisionMatchesCPUFP64() {
        let tapsPerPhase = 256
        let blockFrames = 256
        let totalBlocks = 6
        let inRate = 44_100
        let dxdRate = 352_800 // 8x Stage 1 GPU polyphase df64 kernel

        let cpuRef = AccelerateAMXOversampler(
            phaseMode: .linearPhase,
            tapsPerPhase: tapsPerPhase,
            maxInputFrames: blockFrames
        )
        let gpuMetal = MetalOverlapSaveOversampler(
            phaseMode: .linearPhase,
            tapsPerPhase: tapsPerPhase,
            maxInputFrames: blockFrames
        )

        let cpuOut = AlignedPlanarDoubleBuffer(capacityFrames: blockFrames * 8 + 64)
        let gpuOut = AlignedPlanarDoubleBuffer(capacityFrames: blockFrames * 8 + 64)

        let amp = pow(10.0, -3.5 / 20.0)
        var maxAbsDiff = 0.0
        var sigEnergy = 0.0
        var errEnergy = 0.0

        for blk in 0..<totalBlocks {
            var inL = [Double](repeating: 0.0, count: blockFrames)
            var inR = [Double](repeating: 0.0, count: blockFrames)
            for i in 0..<blockFrames {
                let n = Double(blk * blockFrames + i)
                inL[i] = amp * sin(2.0 * Double.pi * 997.0 * n / Double(inRate))
                inR[i] = amp * cos(2.0 * Double.pi * 3125.0 * n / Double(inRate))
            }

            let cCount = inL.withUnsafeBufferPointer { lPtr in
                inR.withUnsafeBufferPointer { rPtr in
                    cpuRef.oversampleStereoBlock(
                        inputL: lPtr.baseAddress!,
                        inputR: rPtr.baseAddress!,
                        inputFrames: blockFrames,
                        inputRateHz: inRate,
                        targetRateHz: dxdRate,
                        outputBuffer: cpuOut
                    )
                }
            }
            let gCount = inL.withUnsafeBufferPointer { lPtr in
                inR.withUnsafeBufferPointer { rPtr in
                    gpuMetal.oversampleStereoBlock(
                        inputL: lPtr.baseAddress!,
                        inputR: rPtr.baseAddress!,
                        inputFrames: blockFrames,
                        inputRateHz: inRate,
                        targetRateHz: dxdRate,
                        outputBuffer: gpuOut
                    )
                }
            }
            XCTAssertEqual(cCount, blockFrames * 8)
            XCTAssertEqual(gCount, blockFrames * 8)

            // Skip filter warmup transient in blocks 0..1
            if blk >= 2 {
                for k in 0..<cCount {
                    let dl = cpuOut.left[k] - gpuOut.left[k]
                    let dr = cpuOut.right[k] - gpuOut.right[k]
                    maxAbsDiff = max(maxAbsDiff, max(abs(dl), abs(dr)))
                    sigEnergy += cpuOut.left[k] * cpuOut.left[k] + cpuOut.right[k] * cpuOut.right[k]
                    errEnergy += dl * dl + dr * dr
                }
            }
        }

        let sqnrDB = 10.0 * log10(sigEnergy / max(errEnergy, 1.0e-36))
        // Plain Float32 fast-math achieves only ~135-140 dB max (or ~125 dB over 256-tap accumulation);
        // true Dekker-Knuth df64 (~48-bit mantissa) achieves > 250 dB SQNR against IEEE-754 FP64!
        XCTAssertGreaterThan(
            sqnrDB,
            200.0,
            "Metal df64 polyphase FIR must preserve true ~48-bit Dekker-Knuth precision (>200 dB SQNR vs FP64, got \(String(format: "%.2f", sqnrDB)) dB, maxDiff=\(maxAbsDiff))"
        )
    }

    // MARK: - 9. XMOS UAC2 DoP Non-Mixable Integer Mapping, Default SACD Grid & v2.5.0 Regressions

    func testDefaultClockPolicyAndHALStreamFormatMappingAndPersonalStationExtraction() {
        // 9a. Default EngineConfiguration must use .strictSACD44k1 so 48/96 kHz Apple Music tracks
        // lock XMOS UAC2 DoP (176.4 / 352.8 / 705.6 kHz) instead of outputting 384/768 kHz PCM.
        var defaultCfg = EngineConfiguration(mode: .sdmDoP, dsdRate: .dsd256)
        XCTAssertEqual(defaultCfg.clockPolicy, .strictSACD44k1)

        let smslRates: [Double] = [44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000]
        let route96_256 = SampleRateRouter.resolveRoute(
            inputSampleRateHz: 96_000,
            configuration: defaultCfg,
            supportedDeviceSampleRates: smslRates
        )
        XCTAssertEqual(route96_256.effectiveMode, .sdmDoP)
        XCTAssertEqual(route96_256.baseGrid, .grid44k1)
        XCTAssertEqual(route96_256.dopCarrierRateHz, 705_600)
        XCTAssertTrue(route96_256.usesASRC)

        defaultCfg.dsdRate = .dsd128
        let route48_128 = SampleRateRouter.resolveRoute(
            inputSampleRateHz: 48_000,
            configuration: defaultCfg,
            supportedDeviceSampleRates: smslRates
        )
        XCTAssertEqual(route48_128.baseGrid, .grid44k1)
        XCTAssertEqual(route48_128.dopCarrierRateHz, 352_800)
        XCTAssertTrue(route48_128.usesASRC)

        // 9b. HALDeviceManager ASBD -> HALPhysicalStreamFormat mapping for SMSL 0x4c (Non-Mixable 32-bit Int) vs 0x9 (Float32)
        let nonMixable32 = AudioStreamBasicDescription(
            mSampleRate: 705_600,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsNonMixable | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8,
            mFramesPerPacket: 1,
            mBytesPerFrame: 8,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        let mappedNM32 = HALDeviceManager.mapASBDToHALStreamFormat(nonMixable32)
        XCTAssertEqual(mappedNM32.format, .signedInt32LE)
        XCTAssertEqual(mappedNM32.bitDepth, 32)
        XCTAssertTrue(mappedNM32.isInteger)

        let floatVirt = AudioStreamBasicDescription(
            mSampleRate: 705_600,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8,
            mFramesPerPacket: 1,
            mBytesPerFrame: 8,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        let mappedFloat = HALDeviceManager.mapASBDToHALStreamFormat(floatVirt)
        XCTAssertEqual(mappedFloat.format, .float32LE)
        XCTAssertFalse(mappedFloat.isInteger)

        // 9c. MusicKitManager.extractStations user-named personal station ("Admin’s Station" / "Станция Admin")
        let mockRecJSON = """
        {
          "data": [
            {
              "id": "group-stations",
              "attributes": { "title": { "stringForDisplay": "Станции для вас" } },
              "relationships": {
                "contents": {
                  "data": [
                    {
                      "id": "ra.987654321",
                      "type": "stations",
                      "attributes": { "name": "Admin’s Station" }
                    },
                    {
                      "id": "ra.q-discovery-1",
                      "type": "stations",
                      "attributes": { "name": "Станция открытий" }
                    }
                  ]
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!
        let groups = MusicKitManager.parsePersonalRecommendations(data: mockRecJSON)
        let extracted = MusicKitManager.extractStations(from: groups)
        XCTAssertEqual(extracted.personal?.id, "ra.987654321")
        XCTAssertEqual(extracted.personal?.name, "Admin’s Station")
        XCTAssertEqual(extracted.discovery?.id, "ra.q-discovery-1")
    }

    // MARK: - 10. Live Physical Hardware Verification on SMSL PO100 PRO (Opt-in via AMR_LIVE_SMSL_VERIFY=1)

    func testLiveSMSLPO100ProHardwareDoP64_128_256() async throws {
        guard ProcessInfo.processInfo.environment["AMR_LIVE_SMSL_VERIFY"] == "1" else {
            return
        }

        let outputDevices = CoreAudioDeviceManager.shared.getOutputDevices()
        guard let smsl = outputDevices.first(where: { $0.name.uppercased().contains("SMSL") }) else {
            XCTFail("SMSL PO100 PRO ('SMSL USB AUDIO') is not connected via USB!")
            return
        }

        print("\n=== [LIVE HARDWARE TEST] Found physical DAC: '\(smsl.name)' (id=\(smsl.id), uid=\(smsl.uid)) ===")

        let halProbe = HALDeviceManager()
        let streams = halProbe.getOutputStreams(for: smsl.id)
        guard let primaryStream = streams.first else {
            XCTFail("No output stream on SMSL device \(smsl.id)")
            return
        }

        // Helper to feed continuous 1 kHz -60 dBFS stereo sine into captureRingBuffer while verifying CoreAudio registers
        let feedSineForDuration: (Int, Double) async throws -> Void = { inRateHz, durationSec in
            let framesPerTick = 2048
            let totalFrames = Int(Double(inRateHz) * durationSec)
            var sentFrames = 0
            var phase = 0.0
            let phaseInc = 2.0 * Double.pi * 997.0 / Double(inRateHz)
            var left = [Float](repeating: 0, count: framesPerTick)
            var right = [Float](repeating: 0, count: framesPerTick)

            let maxBufferedFrames = max(8192, inRateHz / 4)
            while sentFrames < totalFrames {
                if AudioEngineController.shared.captureRingBuffer.availableFramesToRead < maxBufferedFrames,
                   AudioEngineController.shared.captureRingBuffer.availableFramesToWrite >= framesPerTick * 2 {
                    for i in 0..<framesPerTick {
                        let s = Float(0.001 * sin(phase))
                        left[i] = s
                        right[i] = s
                        phase += phaseInc
                        if phase > 2.0 * Double.pi { phase -= 2.0 * Double.pi }
                    }
                    _ = left.withUnsafeBufferPointer { lPtr in
                        right.withUnsafeBufferPointer { rPtr in
                            AudioEngineController.shared.captureRingBuffer.writePlanar(
                                left: lPtr.baseAddress!,
                                right: rPtr.baseAddress!,
                                frames: framesPerTick
                            )
                        }
                    }
                    sentFrames += framesPerTick
                } else {
                    try await Task.sleep(nanoseconds: 2_000_000)
                }
            }
        }

        let readHogPID: (AudioDeviceID) -> pid_t = { devID in
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyHogMode,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var pid: pid_t = -1
            var sz = UInt32(MemoryLayout<pid_t>.size)
            _ = AudioObjectGetPropertyData(devID, &addr, 0, nil, &sz, &pid)
            return pid
        }

        let testCases: [(dsd: DSDRateMultiplier, expectedCarrierHz: Double, inputRates: [Int])] = [
            (.dsd64, 176_400.0, [44_100]),
            (.dsd128, 352_800.0, [44_100, 48_000, 96_000]),
            (.dsd256, 705_600.0, [44_100, 96_000])
        ]

        do {
            for tc in testCases {
                let cfg = EngineConfiguration(
                    mode: .sdmDoP,
                    profile: .balanced,
                    dsdRate: tc.dsd,
                    clockPolicy: .strictSACD44k1,
                    oversamplerBackend: .accelerateAMX,
                    phaseMode: .minimumPhase,
                    trellisOrder: .m8,
                    isiRegularizerEnabled: true,
                    headroomDB: -3.5,
                    ispProtectionEnabled: true,
                    hogModeEnabled: true,
                    targetDeviceUID: nil // Test AUTO selection & anti-oscillation against BuiltInSpeakerDevice!
                )
                await AudioEngineController.shared.updateConfiguration(cfg, inputSampleRateHz: tc.inputRates.first)

                for (rateIdx, inRate) in tc.inputRates.enumerated() {
                    if rateIdx > 0 {
                        await AudioEngineController.shared.notifySourceSampleRateChanged(Double(inRate))
                    }
                    try await feedSineForDuration(inRate, 0.85)

                    let nominalHz = HALDeviceManager.nominalSampleRate(deviceID: smsl.id)
                    let hogPID = readHogPID(smsl.id)
                    let curPhys = halProbe.currentStreamFormat(for: primaryStream, selector: kAudioStreamPropertyPhysicalFormat)
                    let curVirt = halProbe.currentStreamFormat(for: primaryStream, selector: kAudioStreamPropertyVirtualFormat)
                    let tel = AudioEngineController.shared.latestTelemetrySnapshot()
                    let activeDevID = AudioEngineController.shared.activeHardwareOutputDeviceID

                    print(String(
                        format: "[LIVE SMSL CHECK] DSD%d (in=%dHz): activeDev=%u, nominal=%.0fHz, hogPID=%d (myPID=%d), physFlags=0x%x (%u-bit), virtFlags=0x%x (%u-bit), intMode=%d, underruns=%llu, cpu=%.1f%%, fill=%.1f%%",
                        tc.dsd.rawValue,
                        inRate,
                        activeDevID,
                        nominalHz,
                        hogPID,
                        getpid(),
                        curPhys?.mFormatFlags ?? 0,
                        curPhys?.mBitsPerChannel ?? 0,
                        curVirt?.mFormatFlags ?? 0,
                        curVirt?.mBitsPerChannel ?? 0,
                        tel.isIntegerModeActive ? 1 : 0,
                        tel.underrunCount,
                        tel.processingLoadPercent,
                        tel.ringBufferFillPercent
                    ))

                    XCTAssertEqual(activeDevID, smsl.id, "Active output device MUST stay pinned to SMSL PO100 PRO without oscillating to Built-in Speakers!")
                    XCTAssertEqual(nominalHz, tc.expectedCarrierHz, accuracy: 1.0, "SMSL NominalSampleRate must lock to \(tc.expectedCarrierHz) Hz")
                    XCTAssertEqual(hogPID, getpid(), "SMSL must remain exclusively hogged by our PID")
                    XCTAssertNotNil(curVirt)
                    if let v = curVirt {
                        XCTAssertNotEqual(v.mFormatFlags & kAudioFormatFlagIsNonMixable, 0, "VirtualFormat MUST be Non-Mixable (0x4c) so CoreAudio Float32 mixer is bypassed!")
                        XCTAssertNotEqual(v.mFormatFlags & kAudioFormatFlagIsSignedInteger, 0, "VirtualFormat MUST be Signed Integer!")
                        XCTAssertEqual(v.mFormatFlags & kAudioFormatFlagIsFloat, 0, "VirtualFormat MUST NOT be Float32!")
                    }
                    XCTAssertTrue(tel.isRunning)
                    XCTAssertTrue(tel.isHogModeActive)
                    XCTAssertTrue(tel.isIntegerModeActive)
                    XCTAssertEqual(tel.underrunCount, 0, "Zero ring-buffer underruns allowed during live DSD\(tc.dsd.rawValue) streaming!")
                }
            }
        } catch {
            await AudioEngineController.shared.updateConfiguration(EngineConfiguration(mode: .bitPerfectPassthrough))
            throw error
        }

        // Cleanly return to Bit-Perfect Passthrough and verify Hog Mode & Mixable Float32 are restored
        await AudioEngineController.shared.updateConfiguration(EngineConfiguration(mode: .bitPerfectPassthrough))
        let releasedHogPID = readHogPID(smsl.id)
        let restoredVirt = halProbe.currentStreamFormat(for: primaryStream, selector: kAudioStreamPropertyVirtualFormat)
        print(String(
            format: "[LIVE SMSL RELEASE] hogPID=%d, restoredVirtFlags=0x%x",
            releasedHogPID,
            restoredVirt?.mFormatFlags ?? 0
        ))
        XCTAssertNotEqual(releasedHogPID, getpid(), "Hog Mode must be cleanly released on passthrough stop")
    }

    // MARK: - 8. DSP Preset Manager Built-In & Custom CRUD Verification

    func testDSPPresetManagerBuiltInAndCustomCRUD() async {
        let mgr = DSPPresetManager.shared
        let initialCustomIDs = mgr.customPresets().map(\.id)
        defer {
            for p in mgr.customPresets() where !initialCustomIDs.contains(p.id) {
                mgr.deleteCustomPreset(id: p.id)
            }
        }

        // 1. Verify all 6 built-in presets exist and cannot be deleted
        let builtIns = DSPPresetManager.builtInPresets
        XCTAssertEqual(builtIns.count, 6)
        XCTAssertFalse(mgr.deleteCustomPreset(id: "builtin_dsd256_sacd"))

        // 2. Verify hardware targetDeviceUID does not break preset matching and is preserved across applyPreset
        var pinnedCfg = EngineConfiguration(mode: .bitPerfectPassthrough)
        pinnedCfg.targetDeviceUID = "TEST-DAC-UID-999"
        await AudioEngineController.shared.updateConfiguration(pinnedCfg)

        let applied = await mgr.applyPreset(id: "builtin_hq_nos_r2r")
        XCTAssertNotNil(applied)
        let snapAfterApply = AudioEngineController.shared.currentConfigurationSnapshot()
        XCTAssertEqual(snapAfterApply.mode, .hqNOSPCM)
        XCTAssertEqual(snapAfterApply.nosDitherMode, .lns15)
        XCTAssertEqual(snapAfterApply.targetDeviceUID, "TEST-DAC-UID-999")
        XCTAssertEqual(mgr.matchingPreset(for: snapAfterApply)?.id, "builtin_hq_nos_r2r")

        // 3. Create, update, rename, and delete a custom preset
        var customCfg = EngineConfiguration(
            mode: .sdmDoP,
            profile: .superWide,
            dsdRate: .dsd128,
            clockPolicy: .adaptiveDualGrid,
            oversamplerBackend: .accelerateAMX,
            phaseMode: .minimumPhase,
            trellisOrder: .m16,
            isiRegularizerEnabled: true,
            headroomDB: -3.8
        )
        let saved = mgr.saveCustomPreset(name: "Мой R2R/DSD тест", configuration: customCfg)
        XCTAssertFalse(saved.isBuiltIn)
        XCTAssertNil(saved.configuration.targetDeviceUID)
        XCTAssertEqual(mgr.matchingPreset(for: customCfg)?.id, saved.id)

        // Manual tweak diverges from saved preset -> buildTelemetryPresetInfo reports unsaved_custom
        customCfg.headroomDB = -5.0
        let unsavedInfo = mgr.buildTelemetryPresetInfo(for: customCfg)
        XCTAssertEqual(unsavedInfo.activeID, DSPPresetManager.unsavedCustomPresetID)

        // Update existing custom preset with tweaked configuration
        let updated = mgr.saveCustomPreset(
            name: "Мой R2R/DSD тест",
            configuration: customCfg,
            updatingPresetID: saved.id
        )
        XCTAssertEqual(updated.id, saved.id)
        XCTAssertEqual(mgr.matchingPreset(for: customCfg)?.id, saved.id)

        // Rename & delete
        let renamed = mgr.renameCustomPreset(id: saved.id, newName: "Ночной DSD128")
        XCTAssertEqual(renamed?.name, "Ночной DSD128")
        XCTAssertTrue(mgr.deleteCustomPreset(id: saved.id))
        XCTAssertNil(mgr.preset(withID: saved.id))

        // Restore controller to passthrough
        await AudioEngineController.shared.updateConfiguration(EngineConfiguration(mode: .bitPerfectPassthrough))
    }
}
