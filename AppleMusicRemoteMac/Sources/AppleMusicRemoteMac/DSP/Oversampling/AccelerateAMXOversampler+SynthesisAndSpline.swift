//
//  AccelerateAMXOversampler+SynthesisAndSpline.swift
//  AppleMusicRemoteMac
//
//  Kaiser Windowed-Sinc & Minimum-Phase Cepstral FIR Synthesis,
//  5-Point Lagrange/Hermite Spline Stage 3, and Precomputed Polyphase FP64 ASRC.
//

import Accelerate
import Darwin
import Foundation
import simd

extension AccelerateAMXOversampler {

    // MARK: - Kaiser Windowed-Sinc & Minimum-Phase Cepstral Synthesis

    /// Модифицированная функция Бесселя первого рода нулевого порядка `I_0(x)` в `IEEE-754 Double`.
    @inlinable
    public static func besselI0(_ x: Double) -> Double {
        var sum = 1.0
        var term = 1.0
        let halfXSq = (0.5 * x) * (0.5 * x)
        var k = 1.0
        while term > 1.0e-17 * sum {
            term *= halfXSq / (k * k)
            sum += term
            k += 1.0
        }
        return sum
    }

    /// Синтезирует ненулевые коэффициенты нечётной ветви симметричного полуполосного фильтра Кайзера.
    public static func synthesizeHalfBandBranchWeights(halfPairs: Int, beta: Double) -> [Double] {
        let totalTaps = 4 * halfPairs - 1
        let center = Double(totalTaps - 1) * 0.5
        let invDenom = 1.0 / besselI0(beta)
        var weights = [Double](repeating: 0.0, count: halfPairs)

        var sumPairs = 0.0
        for m in 0..<halfPairs {
            let oddDist = Double(2 * m + 1)
            let sincVal = sin(0.5 * Double.pi * oddDist) / (Double.pi * oddDist)
            let normPos = oddDist / center
            let winArg = beta * sqrt(max(0.0, 1.0 - normPos * normPos))
            let w = besselI0(winArg) * invDenom
            let h = sincVal * w
            weights[m] = h
            sumPairs += 2.0 * h
        }

        // Точная нормировка суммы полифазной интерполирующей ветви к 1.0000000000000000
        let scale = 1.0 / sumPairs
        for m in 0..<halfPairs {
            weights[m] *= scale
        }
        return weights
    }

    /// Синтезирует полифазный банк аподизирующего фильтра Кайзера ($\beta = 16.0$, подавление `> 160 dB`)
    /// для коэффициента интерполяции `factor` (`R in {2, 4, 8}`).
    public static func synthesizePolyphaseBank(
        factor: Int,
        tapsPerPhase: Int,
        phaseMode: OversamplerPhaseMode,
        beta: Double = 16.0
    ) -> [[Double]] {
        let totalTaps = factor * tapsPerPhase
        let center = Double(totalTaps - 1) * 0.5
        let invDenom = 1.0 / besselI0(beta)
        // Аподизирующая частота среза чуть ниже Найквиста (0.915 / factor) для подавления звона Гиббса у 22.05 кГц
        let cutoff = 0.915 / Double(factor)

        var proto = [Double](repeating: 0.0, count: totalTaps)
        for n in 0..<totalTaps {
            let x = Double(n) - center
            let sinc: Double
            if abs(x) < 1.0e-12 {
                sinc = cutoff * Double(factor)
            } else {
                sinc = sin(Double.pi * cutoff * x) / (Double.pi * x) * Double(factor)
            }
            let r = x / center
            let win = besselI0(beta * sqrt(max(0.0, 1.0 - r * r))) * invDenom
            proto[n] = sinc * win
        }

        if phaseMode == .minimumPhase {
            proto = convertToMinimumPhasePrototype(proto)
        }

        // Разбиение на `factor` полифазных ветвей (обратный порядок для прямой свёртки `vDSP_dotprD`)
        var phases = Array(
            repeating: [Double](repeating: 0.0, count: tapsPerPhase),
            count: factor
        )
        for p in 0..<factor {
            var phaseSum = 0.0
            for k in 0..<tapsPerPhase {
                let c = proto[k * factor + p]
                // Храним в порядке возрастания индекса входного буфера (старые -> новые)
                phases[p][tapsPerPhase - 1 - k] = c
                phaseSum += c
            }
            // Строгая нормировка каждой полифазной ветви к 1.0 для исключения модуляции уровня между фазами
            if abs(phaseSum) > 1.0e-12 {
                let invSum = 1.0 / phaseSum
                for k in 0..<tapsPerPhase {
                    phases[p][k] *= invSum
                }
            }
        }
        return phases
    }

    /// Преобразует симметричный FIR-прототип в точный минимально-фазовый эквивалент с идентичной АЧХ
    /// методом вещественного кепстра Оппенгейма–Шафера (`Hilbert Transform of log|H(e^{jw})|`) в `FP64` через `vDSP_fft_zipD`.
    internal static func convertToMinimumPhasePrototype(_ linearProto: [Double]) -> [Double] {
        let n = linearProto.count
        guard n > 1 else { return linearProto }

        var fftLen = 16384
        let minRequired = max(16384, n * 8)
        while fftLen < minRequired {
            fftLen <<= 1
        }
        let log2N = vDSP_Length(fftLen.trailingZeroBitCount)
        guard let fftSetup = vDSP_create_fftsetupD(log2N, FFTRadix(kFFTRadix2)) else {
            return linearProto
        }
        defer { vDSP_destroy_fftsetupD(fftSetup) }

        var real = [Double](repeating: 0.0, count: fftLen)
        var imag = [Double](repeating: 0.0, count: fftLen)
        for i in 0..<n {
            real[i] = linearProto[i]
        }

        let invN = 1.0 / Double(fftLen)
        let magFloorSq = 1.0e-32 // -320 dB power floor prevents log(0) while preserving >160 dB stopband

        real.withUnsafeMutableBufferPointer { reBuf in
            imag.withUnsafeMutableBufferPointer { imBuf in
                var split = DSPDoubleSplitComplex(realp: reBuf.baseAddress!, imagp: imBuf.baseAddress!)

                // 1. H(k) = FFT(h_lin)
                vDSP_fft_zipD(fftSetup, &split, 1, log2N, FFTDirection(kFFTDirection_Forward))

                // 2. log|H(k)| = 0.5 * ln(max(|H(k)|^2, magFloorSq))
                for k in 0..<fftLen {
                    let r = split.realp[k]
                    let im = split.imagp[k]
                    let magSq = max(r * r + im * im, magFloorSq)
                    split.realp[k] = 0.5 * Foundation.log(magSq)
                    split.imagp[k] = 0.0
                }

                // 3. Вещественный кепстр c[m] = IFFT(log|H(k)|)
                vDSP_fft_zipD(fftSetup, &split, 1, log2N, FFTDirection(kFFTDirection_Inverse))
                for k in 0..<fftLen {
                    split.realp[k] *= invN
                    split.imagp[k] = 0.0
                }

                // 4. Каузальное окно Гильберта в кепстральной области: w[0]=1, w[1..N/2-1]=2, w[N/2]=1, w[N/2+1..N-1]=0
                let half = fftLen >> 1
                if half > 1 {
                    for m in 1..<half {
                        split.realp[m] *= 2.0
                    }
                }
                if half + 1 < fftLen {
                    for m in (half + 1)..<fftLen {
                        split.realp[m] = 0.0
                    }
                }

                // 5. Аналитический логарифм спектра L_min(k) = FFT(w * c)
                vDSP_fft_zipD(fftSetup, &split, 1, log2N, FFTDirection(kFFTDirection_Forward))

                // 6. H_min(k) = exp(Re(L_min)) * (cos(Im(L_min)) + j * sin(Im(L_min)))
                for k in 0..<fftLen {
                    let mag = Foundation.exp(split.realp[k])
                    let ph = split.imagp[k]
                    split.realp[k] = mag * Foundation.cos(ph)
                    split.imagp[k] = mag * Foundation.sin(ph)
                }

                // 7. h_min[n] = IFFT(H_min(k))
                vDSP_fft_zipD(fftSetup, &split, 1, log2N, FFTDirection(kFFTDirection_Inverse))
            }
        }

        // Плавное полукосинусное затухание последних 2% хвоста для подавления усечения кепстра ниже -180 dB
        var out = [Double](repeating: 0.0, count: n)
        let tailLen = max(8, n / 50)
        let tailStart = n - tailLen
        var linSum = 0.0
        var minSum = 0.0
        for i in 0..<n {
            linSum += linearProto[i]
            var v = real[i] * invN
            if i >= tailStart {
                let u = Double(i - tailStart) / Double(tailLen)
                let taper = 0.5 * (1.0 + Foundation.cos(Double.pi * u))
                v *= taper
            }
            out[i] = v
            minSum += v
        }

        if abs(minSum) > 1.0e-12 && abs(linSum) > 1.0e-12 {
            let gainScale = linSum / minSum
            for i in 0..<n {
                out[i] *= gainScale
            }
        }
        return out
    }

    internal func rebuildPolyphaseFilterBanks() {
        let r2 = Self.synthesizePolyphaseBank(factor: 2, tapsPerPhase: tapsPerPhase, phaseMode: phaseMode)
        let r4 = Self.synthesizePolyphaseBank(factor: 4, tapsPerPhase: tapsPerPhase, phaseMode: phaseMode)
        let r8 = Self.synthesizePolyphaseBank(factor: 8, tapsPerPhase: tapsPerPhase, phaseMode: phaseMode)

        for p in 0..<2 {
            for k in 0..<tapsPerPhase {
                bankR2Ptr[p * tapsPerPhase + k] = r2[p][k]
            }
        }
        for p in 0..<4 {
            for k in 0..<tapsPerPhase {
                bankR4Ptr[p * tapsPerPhase + k] = r4[p][k]
            }
        }
        for p in 0..<8 {
            for k in 0..<tapsPerPhase {
                bankR8Ptr[p * tapsPerPhase + k] = r8[p][k]
            }
        }
    }

    // MARK: - Stage 3: 5-Point Lagrange / Hermite Spline Interpolator

    @inlinable
    internal static func evalLagrange5(
        ym2: Double,
        ym1: Double,
        y0: Double,
        yp1: Double,
        yp2: Double,
        t: Double
    ) -> Double {
        let c0 = y0
        let c1 = (ym2 - 8.0 * ym1 + 8.0 * yp1 - yp2) * (1.0 / 12.0)
        let c2 = (-ym2 + 16.0 * ym1 - 30.0 * y0 + 16.0 * yp1 - yp2) * (1.0 / 24.0)
        let c3 = (-ym2 + 2.0 * ym1 - 2.0 * yp1 + yp2) * (1.0 / 12.0)
        let c4 = (ym2 - 4.0 * ym1 + 6.0 * y0 - 4.0 * yp1 + yp2) * (1.0 / 24.0)
        return (((c4 * t + c3) * t + c2) * t + c1) * t + c0
    }

    @usableFromInline
    @inline(__always)
    internal func runLagrange5SplineStage(
        inL: UnsafePointer<Double>,
        inR: UnsafePointer<Double>,
        inFrames: Int,
        factor: Int,
        outL: UnsafeMutablePointer<Double>,
        outR: UnsafeMutablePointer<Double>,
        maxOutFrames: Int
    ) -> Int {
        var ym2 = SIMD2<Double>(splineHistL.0, splineHistR.0)
        var ym1 = SIMD2<Double>(splineHistL.1, splineHistR.1)
        var y0  = SIMD2<Double>(splineHistL.2, splineHistR.2)
        var yp1 = SIMD2<Double>(splineHistL.3, splineHistR.3)
        let inv12 = 1.0 / 12.0
        let inv24 = 1.0 / 24.0
        var outIdx = 0

        if factor == 8 {
            // Развёрнутое векторное ядро NEON float64x2_t для DSD256 (1.4112 МГц -> 11.2896 МГц)
            for i in 0..<inFrames {
                if outIdx &+ 8 > maxOutFrames { break }
                let yp2 = SIMD2<Double>(inL[i], inR[i])

                let sum2  = ym2 + yp2
                let diff2 = yp2 - ym2
                let sum1  = ym1 + yp1
                let diff1 = yp1 - ym1

                let c1 = (8.0 * diff1 - diff2) * inv12
                let c2 = (16.0 * sum1 - sum2 - 30.0 * y0) * inv24
                let c3 = (diff2 - 2.0 * diff1) * inv12
                let c4 = (sum2 - 4.0 * sum1 + 6.0 * y0) * inv24

                outL[outIdx] = y0.x; outR[outIdx] = y0.y

                let v1 = (((c4 * 0.125 + c3) * 0.125 + c2) * 0.125 + c1) * 0.125 + y0
                outL[outIdx &+ 1] = v1.x; outR[outIdx &+ 1] = v1.y

                let v2 = (((c4 * 0.25 + c3) * 0.25 + c2) * 0.25 + c1) * 0.25 + y0
                outL[outIdx &+ 2] = v2.x; outR[outIdx &+ 2] = v2.y

                let v3 = (((c4 * 0.375 + c3) * 0.375 + c2) * 0.375 + c1) * 0.375 + y0
                outL[outIdx &+ 3] = v3.x; outR[outIdx &+ 3] = v3.y

                let v4 = (((c4 * 0.5 + c3) * 0.5 + c2) * 0.5 + c1) * 0.5 + y0
                outL[outIdx &+ 4] = v4.x; outR[outIdx &+ 4] = v4.y

                let v5 = (((c4 * 0.625 + c3) * 0.625 + c2) * 0.625 + c1) * 0.625 + y0
                outL[outIdx &+ 5] = v5.x; outR[outIdx &+ 5] = v5.y

                let v6 = (((c4 * 0.75 + c3) * 0.75 + c2) * 0.75 + c1) * 0.75 + y0
                outL[outIdx &+ 6] = v6.x; outR[outIdx &+ 6] = v6.y

                let v7 = (((c4 * 0.875 + c3) * 0.875 + c2) * 0.875 + c1) * 0.875 + y0
                outL[outIdx &+ 7] = v7.x; outR[outIdx &+ 7] = v7.y

                outIdx &+= 8
                ym2 = ym1; ym1 = y0; y0 = yp1; yp1 = yp2
            }
        } else if factor == 4 {
            for i in 0..<inFrames {
                if outIdx &+ 4 > maxOutFrames { break }
                let yp2 = SIMD2<Double>(inL[i], inR[i])

                let sum2  = ym2 + yp2
                let diff2 = yp2 - ym2
                let sum1  = ym1 + yp1
                let diff1 = yp1 - ym1

                let c1 = (8.0 * diff1 - diff2) * inv12
                let c2 = (16.0 * sum1 - sum2 - 30.0 * y0) * inv24
                let c3 = (diff2 - 2.0 * diff1) * inv12
                let c4 = (sum2 - 4.0 * sum1 + 6.0 * y0) * inv24

                outL[outIdx] = y0.x; outR[outIdx] = y0.y

                let v1 = (((c4 * 0.25 + c3) * 0.25 + c2) * 0.25 + c1) * 0.25 + y0
                outL[outIdx &+ 1] = v1.x; outR[outIdx &+ 1] = v1.y

                let v2 = (((c4 * 0.5 + c3) * 0.5 + c2) * 0.5 + c1) * 0.5 + y0
                outL[outIdx &+ 2] = v2.x; outR[outIdx &+ 2] = v2.y

                let v3 = (((c4 * 0.75 + c3) * 0.75 + c2) * 0.75 + c1) * 0.75 + y0
                outL[outIdx &+ 3] = v3.x; outR[outIdx &+ 3] = v3.y

                outIdx &+= 4
                ym2 = ym1; ym1 = y0; y0 = yp1; yp1 = yp2
            }
        } else {
            let step = 1.0 / Double(factor)
            for i in 0..<inFrames {
                if outIdx + factor > maxOutFrames { break }
                let yp2 = SIMD2<Double>(inL[i], inR[i])

                let sum2  = ym2 + yp2
                let diff2 = yp2 - ym2
                let sum1  = ym1 + yp1
                let diff1 = yp1 - ym1

                let c1 = (8.0 * diff1 - diff2) * inv12
                let c2 = (16.0 * sum1 - sum2 - 30.0 * y0) * inv24
                let c3 = (diff2 - 2.0 * diff1) * inv12
                let c4 = (sum2 - 4.0 * sum1 + 6.0 * y0) * inv24

                outL[outIdx] = y0.x
                outR[outIdx] = y0.y
                outIdx &+= 1

                for sub in 1..<factor {
                    let t = Double(sub) * step
                    let v = (((c4 * t + c3) * t + c2) * t + c1) * t + y0
                    outL[outIdx] = v.x
                    outR[outIdx] = v.y
                    outIdx &+= 1
                }
                ym2 = ym1; ym1 = y0; y0 = yp1; yp1 = yp2
            }
        }

        splineHistL = (ym2.x, ym1.x, y0.x, yp1.x)
        splineHistR = (ym2.y, ym1.y, y0.y, yp1.y)
        return outIdx
    }

    // MARK: - Precomputed Polyphase FP64 ASRC for Cross-Grid Conversion (`strictSACD44k1`)

    internal func resampleArbitraryToDXD(
        inputL: UnsafePointer<Double>,
        inputR: UnsafePointer<Double>,
        inputFrames: Int,
        inputRateHz: Int,
        dxdRateHz: Int,
        outL: UnsafeMutablePointer<Double>,
        outR: UnsafeMutablePointer<Double>,
        maxOutFrames: Int
    ) -> Int {
        let step = Double(inputRateHz) / Double(dxdRateHz)
        let winLen = Self.asrcTaps
        let phaseScale = Double(Self.asrcPhaseCount)
        let table = Self.asrcPolyphaseTable
        let hL = asrcHistL
        let hR = asrcHistR

        var phase = asrcPhase
        var pos = asrcHistPos
        var inIdx = 0
        var outIdx = 0

        while outIdx < maxOutFrames {
            while phase >= 1.0 && inIdx < inputFrames {
                let xL = inputL[inIdx]
                let xR = inputR[inIdx]
                hL[pos] = xL
                hL[pos &+ winLen] = xL
                hR[pos] = xR
                hR[pos &+ winLen] = xR
                pos = (pos &+ 1) & (winLen - 1)
                phase -= 1.0
                inIdx &+= 1
            }
            if phase >= 1.0 { break }

            let scaledPhase = min(max(phase * phaseScale, 0.0), phaseScale)
            let pIdx = min(Int(scaledPhase), Self.asrcPhaseCount - 1)
            let frac = scaledPhase - Double(pIdx)

            let row0 = UnsafeRawPointer(table.advanced(by: pIdx &* winLen))
            let row1 = UnsafeRawPointer(table.advanced(by: (pIdx &+ 1) &* winLen))
            let winRawL = UnsafeRawPointer(hL.advanced(by: pos))
            let winRawR = UnsafeRawPointer(hR.advanced(by: pos))
            let fracVec = SIMD4<Double>(repeating: frac)

            var accL = SIMD4<Double>.zero
            var accR = SIMD4<Double>.zero
            for blk in 0..<8 {
                let byteOff = blk &* 32
                let w0 = row0.loadUnaligned(fromByteOffset: byteOff, as: SIMD4<Double>.self)
                let w1 = row1.loadUnaligned(fromByteOffset: byteOff, as: SIMD4<Double>.self)
                let w = w0 + fracVec * (w1 - w0)
                let xLVec = winRawL.loadUnaligned(fromByteOffset: byteOff, as: SIMD4<Double>.self)
                let xRVec = winRawR.loadUnaligned(fromByteOffset: byteOff, as: SIMD4<Double>.self)
                accL += w * xLVec
                accR += w * xRVec
            }

            outL[outIdx] = (accL[0] + accL[1]) + (accL[2] + accL[3])
            outR[outIdx] = (accR[0] + accR[1]) + (accR[2] + accR[3])
            outIdx &+= 1
            phase += step
        }

        asrcPhase = phase
        asrcHistPos = pos
        return outIdx
    }
}
