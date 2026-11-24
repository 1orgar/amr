import Accelerate
import Darwin
import Foundation
import simd

/// Многоступенчатый оверсэмплер двойной точности (`IEEE-754 FP64`) на сопроцессоре Apple Silicon AMX (`Accelerate / vDSP`).
///
/// Архитектура каскадов (Узел 2 ТЗ):
/// - **Stage 1 (Polyphase FIR `vDSP_dotprD`)**: Подъём базовой частоты (`44.1..192 кГц`) до сетки `DXD (352.8 / 384 кГц)`
///   аподизирующим фильтром Кайзера ($\beta = 16.0$, подавление зеркальных копий `> 160 dB`). При входе `DXD` (`OSR < 32`)
///   автоматически активируется прямой обход Stage 1 (`DXD Bypass`). При несовпадении базовых сеток (`strictSACD44k1`)
///   выполняется табличный полифазный `FP64` ASRC без вызовов тригонометрии в реальном времени.
/// - **Stage 2A & 2B (Half-Band FIR 63 и 31 тап)**: Два каскада `x2` (`DXD -> 705.6/768 кГц -> 1.4112/1.536 МГц`),
///   у которых каждый чётный коэффициент равен нулю.
/// - **Stage 3 (5-Point Lagrange/Hermite Spline `x2..x16`)**: Безынерционная полиномиальная интерполяция
///   до финальной частоты `DSD64 / DSD128 / DSD256 / DSD512`.
public final class AccelerateAMXOversampler: OversamplerBackend, @unchecked Sendable {
    public let backendKind: OversamplerBackendKind = .accelerateAMX
    public var phaseMode: OversamplerPhaseMode {
        didSet {
            if phaseMode != oldValue {
                rebuildPolyphaseFilterBanks()
            }
        }
    }

    public let tapsPerPhase: Int

    // Плоские 64-байтно выровненные полифазные банки Stage 1 (R = 2, 4, 8): 0 ARC / 0 COW в RT-цикле
    internal let bankR2Ptr: UnsafeMutablePointer<Double>
    internal let bankR4Ptr: UnsafeMutablePointer<Double>
    internal let bankR8Ptr: UnsafeMutablePointer<Double>

    // Линии задержки Stage 1 (размер 2 * tapsPerPhase для непрерывного скользящего окна без memmove на каждый отсчёт)
    internal let histStage1L: UnsafeMutablePointer<Double>
    internal let histStage1R: UnsafeMutablePointer<Double>
    internal var histStage1Pos: Int = 0

    // Коэффициенты ненулевых ветвей симметричных полуполосных фильтров Stage 2A (63 тапа -> 16 ненулевых пар)
    // и Stage 2B (31 тап -> 8 ненулевых пар)
    internal let hb63WeightsPtr: UnsafeMutablePointer<Double>
    internal let hb31WeightsPtr: UnsafeMutablePointer<Double>

    internal let histHB63L: UnsafeMutablePointer<Double>
    internal let histHB63R: UnsafeMutablePointer<Double>
    internal var histHB63Pos: Int = 0

    internal let histHB31L: UnsafeMutablePointer<Double>
    internal let histHB31R: UnsafeMutablePointer<Double>
    internal var histHB31Pos: Int = 0

    // История 4 отсчётов для 5-точечного сплайна Лагранжа–Эрмита (Stage 3)
    internal var splineHistL: (Double, Double, Double, Double) = (0.0, 0.0, 0.0, 0.0)
    internal var splineHistR: (Double, Double, Double, Double) = (0.0, 0.0, 0.0, 0.0)

    // Состояние дробной фазы для табличного полифазного ASRC (режим strictSACD44k1 при входе 48/96/192 кГц)
    internal var asrcPhase: Double = 0.0
    internal let asrcHistL: UnsafeMutablePointer<Double>
    internal let asrcHistR: UnsafeMutablePointer<Double>
    internal var asrcHistPos: Int = 0

    // Предвычисленная 64B-выровненная таблица полифазного ASRC: (2048 + 1) фаз x 32 тапа Кайзера (beta = 14.0)
    internal static let asrcPhaseCount = 2048
    internal static let asrcTaps = 32
    internal static let asrcPolyphaseTable: UnsafePointer<Double> = {
        let rows = asrcPhaseCount + 1
        let count = rows * asrcTaps
        let ptr = allocateAlignedDoubles(count: count)
        let center = 15
        let halfWidth = Double(center)
        let invI0 = 1.0 / besselI0(14.0)

        for p in 0..<rows {
            let frac = Double(p) / Double(asrcPhaseCount)
            var wSum = 0.0
            let rowPtr = ptr.advanced(by: p * asrcTaps)
            for k in 0..<asrcTaps {
                let d = Double(k - center) - frac
                let w: Double
                if abs(d) < 1.0e-12 {
                    w = 1.0
                } else {
                    let arg = Double.pi * 0.92 * d
                    let sinc = Foundation.sin(arg) / arg
                    let norm = min(1.0, abs(d) / halfWidth)
                    let win = besselI0(14.0 * Foundation.sqrt(max(0.0, 1.0 - norm * norm))) * invI0
                    w = sinc * win
                }
                rowPtr[k] = w
                wSum += w
            }
            let invW = (abs(wSum) > 1.0e-12) ? (1.0 / wSum) : 1.0
            for k in 0..<asrcTaps {
                rowPtr[k] *= invW
            }
        }
        return UnsafePointer(ptr)
    }()

    // Промежуточные планарные буферы для каскадов DXD и 4x DXD (1.4112 / 1.536 МГц)
    internal let dxdScratch: AlignedPlanarDoubleBuffer
    internal let hb2xScratch: AlignedPlanarDoubleBuffer
    internal let hb4xScratch: AlignedPlanarDoubleBuffer

    internal static func allocateAlignedDoubles(count: Int) -> UnsafeMutablePointer<Double> {
        let alignedCount = max(8, (count + 7) & ~7)
        let byteCount = alignedCount * MemoryLayout<Double>.stride
        var raw: UnsafeMutableRawPointer?
        let rc = posix_memalign(&raw, 64, byteCount)
        guard rc == 0, let validRaw = raw else {
            fatalError("posix_memalign(64, \(byteCount)) failed with code \(rc)")
        }
        let ptr = validRaw.bindMemory(to: Double.self, capacity: alignedCount)
        ptr.initialize(repeating: 0.0, count: alignedCount)
        _ = mlock(validRaw, byteCount)
        return ptr
    }

    internal static func freeAlignedDoubles(_ ptr: UnsafeMutablePointer<Double>, count: Int) {
        let alignedCount = max(8, (count + 7) & ~7)
        let byteCount = alignedCount * MemoryLayout<Double>.stride
        _ = munlock(ptr, byteCount)
        free(ptr)
    }

    public init(
        phaseMode: OversamplerPhaseMode = .minimumPhase,
        tapsPerPhase: Int = 256,
        maxInputFrames: Int = 4096
    ) {
        let clampedTaps = max(64, min(tapsPerPhase, 4096))
        self.phaseMode = phaseMode
        self.tapsPerPhase = clampedTaps

        self.bankR2Ptr = Self.allocateAlignedDoubles(count: 2 * clampedTaps)
        self.bankR4Ptr = Self.allocateAlignedDoubles(count: 4 * clampedTaps)
        self.bankR8Ptr = Self.allocateAlignedDoubles(count: 8 * clampedTaps)

        self.histStage1L = Self.allocateAlignedDoubles(count: clampedTaps * 2)
        self.histStage1R = Self.allocateAlignedDoubles(count: clampedTaps * 2)

        self.hb63WeightsPtr = Self.allocateAlignedDoubles(count: 16)
        self.hb31WeightsPtr = Self.allocateAlignedDoubles(count: 8)
        let w63 = Self.synthesizeHalfBandBranchWeights(halfPairs: 16, beta: 16.0)
        let w31 = Self.synthesizeHalfBandBranchWeights(halfPairs: 8, beta: 15.0)
        for i in 0..<16 { self.hb63WeightsPtr[i] = w63[i] }
        for i in 0..<8 { self.hb31WeightsPtr[i] = w31[i] }

        self.histHB63L = Self.allocateAlignedDoubles(count: 64)
        self.histHB63R = Self.allocateAlignedDoubles(count: 64)
        self.histHB31L = Self.allocateAlignedDoubles(count: 32)
        self.histHB31R = Self.allocateAlignedDoubles(count: 32)

        self.asrcHistL = Self.allocateAlignedDoubles(count: 64)
        self.asrcHistR = Self.allocateAlignedDoubles(count: 64)

        let maxDXDFrames = maxInputFrames * 16 + 64
        self.dxdScratch = AlignedPlanarDoubleBuffer(capacityFrames: maxDXDFrames)
        self.hb2xScratch = AlignedPlanarDoubleBuffer(capacityFrames: maxDXDFrames * 2)
        self.hb4xScratch = AlignedPlanarDoubleBuffer(capacityFrames: maxDXDFrames * 4)

        _ = Self.asrcPolyphaseTable
        rebuildPolyphaseFilterBanks()
    }

    deinit {
        Self.freeAlignedDoubles(bankR2Ptr, count: 2 * tapsPerPhase)
        Self.freeAlignedDoubles(bankR4Ptr, count: 4 * tapsPerPhase)
        Self.freeAlignedDoubles(bankR8Ptr, count: 8 * tapsPerPhase)
        Self.freeAlignedDoubles(histStage1L, count: tapsPerPhase * 2)
        Self.freeAlignedDoubles(histStage1R, count: tapsPerPhase * 2)
        Self.freeAlignedDoubles(hb63WeightsPtr, count: 16)
        Self.freeAlignedDoubles(hb31WeightsPtr, count: 8)
        Self.freeAlignedDoubles(histHB63L, count: 64)
        Self.freeAlignedDoubles(histHB63R, count: 64)
        Self.freeAlignedDoubles(histHB31L, count: 32)
        Self.freeAlignedDoubles(histHB31R, count: 32)
        Self.freeAlignedDoubles(asrcHistL, count: 64)
        Self.freeAlignedDoubles(asrcHistR, count: 64)
    }

    public func reset() {
        memset(histStage1L, 0, tapsPerPhase * 2 * MemoryLayout<Double>.stride)
        memset(histStage1R, 0, tapsPerPhase * 2 * MemoryLayout<Double>.stride)
        histStage1Pos = 0

        memset(histHB63L, 0, 64 * MemoryLayout<Double>.stride)
        memset(histHB63R, 0, 64 * MemoryLayout<Double>.stride)
        histHB63Pos = 0

        memset(histHB31L, 0, 32 * MemoryLayout<Double>.stride)
        memset(histHB31R, 0, 32 * MemoryLayout<Double>.stride)
        histHB31Pos = 0

        splineHistL = (0.0, 0.0, 0.0, 0.0)
        splineHistR = (0.0, 0.0, 0.0, 0.0)

        asrcPhase = 0.0
        memset(asrcHistL, 0, 64 * MemoryLayout<Double>.stride)
        memset(asrcHistR, 0, 64 * MemoryLayout<Double>.stride)
        asrcHistPos = 0
    }

    // MARK: - Stage 1 History Sync (GPU <-> CPU Fallback Continuity)

    /// Импортирует последние `min(count, tapsPerPhase - 1)` входных отсчётов (`oldest -> newest`) из `df64` истории GPU в кольцо Stage 1 CPU.
    internal func importStage1HistoryFromDF64(
        histL: UnsafePointer<SIMD2<Float>>,
        histR: UnsafePointer<SIMD2<Float>>,
        count: Int
    ) {
        let taps = tapsPerPhase
        memset(histStage1L, 0, taps * 2 * MemoryLayout<Double>.stride)
        memset(histStage1R, 0, taps * 2 * MemoryLayout<Double>.stride)
        histStage1Pos = 0

        let copyCount = min(max(0, count), taps - 1)
        guard copyCount > 0 else { return }
        let srcStart = count - copyCount
        let dstStart = taps - copyCount
        for k in 0..<copyCount {
            let vL = Double(histL[srcStart + k].x) + Double(histL[srcStart + k].y)
            let vR = Double(histR[srcStart + k].x) + Double(histR[srcStart + k].y)
            histStage1L[dstStart + k] = vL
            histStage1L[taps + dstStart + k] = vL
            histStage1R[dstStart + k] = vR
            histStage1R[taps + dstStart + k] = vR
        }
    }

    /// Экспортирует последние `min(dstCount, tapsPerPhase - 1)` входных отсчётов Stage 1 CPU в хвост `df64` истории GPU.
    internal func exportStage1HistoryToDF64(
        dstHistL: UnsafeMutablePointer<SIMD2<Float>>,
        dstHistR: UnsafeMutablePointer<SIMD2<Float>>,
        dstCount: Int
    ) {
        guard dstCount > 0 else { return }
        memset(dstHistL, 0, dstCount * MemoryLayout<SIMD2<Float>>.stride)
        memset(dstHistR, 0, dstCount * MemoryLayout<SIMD2<Float>>.stride)

        let avail = tapsPerPhase - 1
        let copyCount = min(dstCount, avail)
        guard copyCount > 0 else { return }
        let srcBaseL = histStage1L.advanced(by: histStage1Pos + 1 + (avail - copyCount))
        let srcBaseR = histStage1R.advanced(by: histStage1Pos + 1 + (avail - copyCount))
        let dstOffset = dstCount - copyCount
        for k in 0..<copyCount {
            let xL = srcBaseL[k]
            let hiL = Float(xL)
            dstHistL[dstOffset + k] = SIMD2<Float>(hiL, Float(xL - Double(hiL)))

            let xR = srcBaseR[k]
            let hiR = Float(xR)
            dstHistR[dstOffset + k] = SIMD2<Float>(hiR, Float(xR - Double(hiR)))
        }
    }

    // MARK: - Stage Execution

    public func oversampleStereoBlock(
        inputL: UnsafePointer<Double>,
        inputR: UnsafePointer<Double>,
        inputFrames: Int,
        inputRateHz: Int,
        targetRateHz: Int,
        outputBuffer: AlignedPlanarDoubleBuffer
    ) -> Int {
        guard inputFrames > 0 && inputRateHz > 0 && targetRateHz >= inputRateHz else { return 0 }

        // Определяем целевую сетку (44.1k vs 48k) по targetRateHz
        let isTarget44k1Grid = (targetRateHz % 44_100 == 0)
        let dxdRateHz = isTarget44k1Grid ? 352_800 : 384_000
        let isInput44k1Grid = (inputRateHz % 44_100 == 0)

        // 1. Stage 1: подъём до DXD (352.8 / 384 кГц) или прямой DXD Bypass
        if inputRateHz >= 352_800 && isInput44k1Grid == isTarget44k1Grid {
            let clampedDXD = min(inputFrames, dxdScratch.capacityFrames)
            return oversampleFromDXD(
                dxdL: inputL,
                dxdR: inputR,
                dxdFrames: clampedDXD,
                dxdRateHz: inputRateHz,
                targetRateHz: targetRateHz,
                outputBuffer: outputBuffer
            )
        }

        let dxdFrames: Int
        if isInput44k1Grid != isTarget44k1Grid {
            // Несовпадение сеток (например, strictSACD44k1 на треке 48/96/192 кГц) -> табличный полифазный FP64 ASRC
            dxdFrames = resampleArbitraryToDXD(
                inputL: inputL,
                inputR: inputR,
                inputFrames: inputFrames,
                inputRateHz: inputRateHz,
                dxdRateHz: dxdRateHz,
                outL: dxdScratch.left,
                outR: dxdScratch.right,
                maxOutFrames: dxdScratch.capacityFrames
            )
        } else {
            let factorStage1 = max(1, dxdRateHz / inputRateHz)
            let clampedIn = min(inputFrames, dxdScratch.capacityFrames / factorStage1)
            dxdFrames = runPolyphaseStage1(
                inputL: inputL,
                inputR: inputR,
                inputFrames: clampedIn,
                factor: factorStage1,
                outL: dxdScratch.left,
                outR: dxdScratch.right
            )
        }

        return oversampleFromDXD(
            dxdL: dxdScratch.left,
            dxdR: dxdScratch.right,
            dxdFrames: dxdFrames,
            dxdRateHz: dxdRateHz,
            targetRateHz: targetRateHz,
            outputBuffer: outputBuffer
        )
    }

    /// Выполняет каскады Stage 2A (Half-Band 63) + Stage 2B (Half-Band 31) + Stage 3 (5-Point Lagrange/Hermite)
    /// напрямую из готового планарного буфера сетки DXD (`352.8 / 384 кГц`) без лишних аллокаций и копирований.
    @usableFromInline
    internal func oversampleFromDXD(
        dxdL: UnsafePointer<Double>,
        dxdR: UnsafePointer<Double>,
        dxdFrames: Int,
        dxdRateHz: Int,
        targetRateHz: Int,
        outputBuffer: AlignedPlanarDoubleBuffer
    ) -> Int {
        guard dxdFrames > 0 else { return 0 }

        // Если целевая частота равна DXD (352.8 / 384 кГц для HQ NOS PCM), копируем и возвращаем
        if targetRateHz <= dxdRateHz {
            let frames = min(dxdFrames, outputBuffer.capacityFrames)
            memcpy(outputBuffer.left, dxdL, frames * MemoryLayout<Double>.stride)
            memcpy(outputBuffer.right, dxdR, frames * MemoryLayout<Double>.stride)
            return frames
        }

        // 2. Stage 2A: симметричный Half-Band FIR 63 тапа (x2 -> 705.6 / 768 кГц)
        let rate2x = dxdRateHz * 2
        if targetRateHz <= rate2x {
            let clamped = min(dxdFrames, outputBuffer.capacityFrames / 2)
            return runHalfBand63Stage(
                inL: dxdL,
                inR: dxdR,
                inFrames: clamped,
                outL: outputBuffer.left,
                outR: outputBuffer.right
            )
        }

        let clampedDXD = min(dxdFrames, hb2xScratch.capacityFrames / 2)
        let frames2x = runHalfBand63Stage(
            inL: dxdL,
            inR: dxdR,
            inFrames: clampedDXD,
            outL: hb2xScratch.left,
            outR: hb2xScratch.right
        )

        // 3. Stage 2B: симметричный Half-Band FIR 31 тап (x2 -> 1.4112 / 1.536 МГц)
        let rate4x = dxdRateHz * 4
        if targetRateHz <= rate4x {
            let clamped2x = min(frames2x, outputBuffer.capacityFrames / 2)
            return runHalfBand31Stage(
                inL: hb2xScratch.left,
                inR: hb2xScratch.right,
                inFrames: clamped2x,
                outL: outputBuffer.left,
                outR: outputBuffer.right
            )
        }

        let clamped2x = min(frames2x, hb4xScratch.capacityFrames / 2)
        let frames4x = runHalfBand31Stage(
            inL: hb2xScratch.left,
            inR: hb2xScratch.right,
            inFrames: clamped2x,
            outL: hb4xScratch.left,
            outR: hb4xScratch.right
        )

        // 4. Stage 3: 5-точечный полиномиальный сплайн Лагранжа–Эрмита (x2 для DSD64, x4 для DSD128, x8 для DSD256, x16 для DSD512)
        let splineFactor = max(1, targetRateHz / rate4x)
        return runLagrange5SplineStage(
            inL: hb4xScratch.left,
            inR: hb4xScratch.right,
            inFrames: frames4x,
            factor: splineFactor,
            outL: outputBuffer.left,
            outR: outputBuffer.right,
            maxOutFrames: outputBuffer.capacityFrames
        )
    }

    // MARK: - Stage 1 Polyphase FIR (`vDSP_dotprD` on Apple AMX)

    internal func runPolyphaseStage1(
        inputL: UnsafePointer<Double>,
        inputR: UnsafePointer<Double>,
        inputFrames: Int,
        factor: Int,
        outL: UnsafeMutablePointer<Double>,
        outR: UnsafeMutablePointer<Double>
    ) -> Int {
        if factor <= 1 {
            memcpy(outL, inputL, inputFrames * MemoryLayout<Double>.stride)
            memcpy(outR, inputR, inputFrames * MemoryLayout<Double>.stride)
            return inputFrames
        }

        let bankBase: UnsafePointer<Double>
        let actualFactor: Int
        switch factor {
        case 2:
            bankBase = UnsafePointer(bankR2Ptr)
            actualFactor = 2
        case 4:
            bankBase = UnsafePointer(bankR4Ptr)
            actualFactor = 4
        default:
            bankBase = UnsafePointer(bankR8Ptr)
            actualFactor = 8
        }
        let taps = tapsPerPhase
        let vLen = vDSP_Length(taps)

        let ptrL = histStage1L
        let ptrR = histStage1R
        var pos = histStage1Pos
        var outIdx = 0

        for i in 0..<inputFrames {
            let xL = inputL[i]
            let xR = inputR[i]

            // Двойная зеркальная запись в кольцевое окно [0..<2*taps] позволяет вызывать vDSP_dotprD
            // по непрерывному срезу памяти `ptr + pos + 1` без копирования истории!
            ptrL[pos] = xL
            ptrL[pos &+ taps] = xL
            ptrR[pos] = xR
            ptrR[pos &+ taps] = xR

            let winL = ptrL.advanced(by: pos &+ 1)
            let winR = ptrR.advanced(by: pos &+ 1)

            for p in 0..<actualFactor {
                let phasePtr = bankBase.advanced(by: p &* taps)
                var sumL = 0.0
                var sumR = 0.0
                vDSP_dotprD(winL, 1, phasePtr, 1, &sumL, vLen)
                vDSP_dotprD(winR, 1, phasePtr, 1, &sumR, vLen)
                outL[outIdx] = sumL
                outR[outIdx] = sumR
                outIdx &+= 1
            }

            pos &+= 1
            if pos >= taps {
                pos = 0
            }
        }

        histStage1Pos = pos
        return outIdx
    }

    // MARK: - Stage 2A & 2B Symmetric Half-Band FIR (Exact Causal Phase Order + SIMD2 NEON)

    @usableFromInline
    @inline(__always)
    internal func runHalfBand63Stage(
        inL: UnsafePointer<Double>,
        inR: UnsafePointer<Double>,
        inFrames: Int,
        outL: UnsafeMutablePointer<Double>,
        outR: UnsafeMutablePointer<Double>
    ) -> Int {
        let len = 32
        let centerOffset = 16
        let hL = histHB63L
        let hR = histHB63R
        let w = hb63WeightsPtr
        var pos = histHB63Pos
        var outIdx = 0

        for i in 0..<inFrames {
            let xL = inL[i]
            let xR = inR[i]
            hL[pos] = xL
            hL[pos &+ len] = xL
            hR[pos] = xR
            hR[pos &+ len] = xR

            let baseL = hL.advanced(by: pos &+ 1)
            let baseR = hR.advanced(by: pos &+ 1)

            // В окне base[0..31] отсчёт base[31] = x[i], base[16] = x[i - 15.0],
            // а симметричная сумма вокруг индекса 15.5 соответствует более раннему моменту времени x[i - 15.5]!
            // Поэтому сначала выдаётся интерполированная полуцелая фаза x[i - 15.5], а затем задержанный отсчёт x[i - 15.0].
            var acc = SIMD2<Double>.zero
            for m in 0..<16 {
                let c = w[m]
                let idxLo = 15 &- m
                let idxHi = 16 &+ m
                let pairSum = SIMD2<Double>(
                    baseL[idxLo] + baseL[idxHi],
                    baseR[idxLo] + baseR[idxHi]
                )
                acc += c * pairSum
            }
            outL[outIdx] = acc.x
            outR[outIdx] = acc.y
            outIdx &+= 1

            outL[outIdx] = baseL[centerOffset]
            outR[outIdx] = baseR[centerOffset]
            outIdx &+= 1

            pos &+= 1
            if pos >= len { pos = 0 }
        }

        histHB63Pos = pos
        return outIdx
    }

    @usableFromInline
    @inline(__always)
    internal func runHalfBand31Stage(
        inL: UnsafePointer<Double>,
        inR: UnsafePointer<Double>,
        inFrames: Int,
        outL: UnsafeMutablePointer<Double>,
        outR: UnsafeMutablePointer<Double>
    ) -> Int {
        let len = 16
        let centerOffset = 8
        let hL = histHB31L
        let hR = histHB31R
        let w = hb31WeightsPtr
        var pos = histHB31Pos
        var outIdx = 0

        for i in 0..<inFrames {
            let xL = inL[i]
            let xR = inR[i]
            hL[pos] = xL
            hL[pos &+ len] = xL
            hR[pos] = xR
            hR[pos &+ len] = xR

            let baseL = hL.advanced(by: pos &+ 1)
            let baseR = hR.advanced(by: pos &+ 1)

            // base[15] = x[i], симметричная сумма вокруг 7.5 = x[i - 7.5] (выдаётся первой), base[8] = x[i - 7.0] (второй).
            var acc = SIMD2<Double>.zero
            for m in 0..<8 {
                let c = w[m]
                let idxLo = 7 &- m
                let idxHi = 8 &+ m
                let pairSum = SIMD2<Double>(
                    baseL[idxLo] + baseL[idxHi],
                    baseR[idxLo] + baseR[idxHi]
                )
                acc += c * pairSum
            }
            outL[outIdx] = acc.x
            outR[outIdx] = acc.y
            outIdx &+= 1

            outL[outIdx] = baseL[centerOffset]
            outR[outIdx] = baseR[centerOffset]
            outIdx &+= 1

            pos &+= 1
            if pos >= len { pos = 0 }
        }

        histHB31Pos = pos
        return outIdx
    }
}
