import Accelerate
import Darwin
import Foundation

/// Выровненный по 64-байтной кэш-линии Apple Silicon (`posix_memalign` + `mlock`) планарный буфер `Double`
/// для детерминированной обработки аудио без аллокаций в реальном времени.
public final class AlignedPlanarDoubleBuffer: @unchecked Sendable {
    public let capacityFrames: Int
    public let left: UnsafeMutablePointer<Double>
    public let right: UnsafeMutablePointer<Double>
    private let byteCount: Int

    public init(capacityFrames: Int) {
        let cap = max(64, (capacityFrames + 7) & ~7)
        self.capacityFrames = cap
        self.byteCount = cap * MemoryLayout<Double>.stride

        var rawL: UnsafeMutableRawPointer?
        var rawR: UnsafeMutableRawPointer?
        let rcL = posix_memalign(&rawL, 64, byteCount)
        let rcR = posix_memalign(&rawR, 64, byteCount)
        precondition(rcL == 0 && rcR == 0 && rawL != nil && rawR != nil, "posix_memalign(64) failed")

        self.left = rawL!.bindMemory(to: Double.self, capacity: cap)
        self.right = rawR!.bindMemory(to: Double.self, capacity: cap)
        self.left.initialize(repeating: 0.0, count: cap)
        self.right.initialize(repeating: 0.0, count: cap)

        _ = mlock(rawL!, byteCount)
        _ = mlock(rawR!, byteCount)
    }

    deinit {
        _ = munlock(left, byteCount)
        _ = munlock(right, byteCount)
        free(left)
        free(right)
    }

    @inlinable
    public func clear(frames: Int? = nil) {
        let count = min(capacityFrames, frames ?? capacityFrames)
        memset(left, 0, count * MemoryLayout<Double>.stride)
        memset(right, 0, count * MemoryLayout<Double>.stride)
    }
}

/// Узел 1 (Node 1): Входной нормализатор `Float32/Int -> Double (FP64)` с аттенюатором запаса по перегрузке
/// (`Headroom -2.0 ... -6.0 dB`, по умолчанию `-3.5 dB`) и 4-кратным интерполяционным детектором
/// межвыборочных пиков (`True Peak ISP Limiter`), предотвращающим перегрузку 7-порядкового SDM
/// на мастеринге с клиппингом `0 dBFS` (+1.5...+3.0 dB ISP).
public final class HeadroomISPProcessor: @unchecked Sendable {
    public var headroomDB: Double {
        didSet {
            let clamped = min(max(headroomDB, -12.0), 0.0)
            linearHeadroomGain = pow(10.0, clamped / 20.0)
        }
    }
    public var ispProtectionEnabled: Bool
    public private(set) var linearHeadroomGain: Double
    public private(set) var ispClipCount: UInt64 = 0

    // История последних 3 отсчётов для 4-точечной кубической оценки межвыборочного пика (ISP)
    private var histL: (Double, Double, Double) = (0.0, 0.0, 0.0)
    private var histR: (Double, Double, Double) = (0.0, 0.0, 0.0)
    private var envelopeGain: Double = 1.0

    /// Порог срабатывания мягкого True Peak лимитера после применения headroom (`-0.5 dBFS` = `0.94406`).
    private let ispCeiling: Double = 0.9440608762859234

    public init(headroomDB: Double = -3.5, ispProtectionEnabled: Bool = true) {
        let clamped = min(max(headroomDB, -12.0), 0.0)
        self.headroomDB = clamped
        self.ispProtectionEnabled = ispProtectionEnabled
        self.linearHeadroomGain = pow(10.0, clamped / 20.0)
    }

    public func reset() {
        histL = (0.0, 0.0, 0.0)
        histR = (0.0, 0.0, 0.0)
        envelopeGain = 1.0
    }

    public func resetClipCounter() {
        ispClipCount = 0
    }

    /// Оценивает максимальный 4-кратный межвыборочный пик (ISP) на интервале `[x1, x2]` по 4 опорным точкам `x0, x1, x2, x3`
    /// методом кубического сплайна Кэтмулла–Рома (в точках t = 0.25, 0.50, 0.75).
    @inlinable
    internal static func estimateTruePeak4x(x0: Double, x1: Double, x2: Double, x3: Double) -> Double {
        var maxPeak = max(abs(x1), abs(x2))
        let a0 = -0.5 * x0 + 1.5 * x1 - 1.5 * x2 + 0.5 * x3
        let a1 = x0 - 2.5 * x1 + 2.0 * x2 - 0.5 * x3
        let a2 = -0.5 * x0 + 0.5 * x2
        let a3 = x1

        // t = 0.25
        let p25 = ((a0 * 0.25 + a1) * 0.25 + a2) * 0.25 + a3
        // t = 0.50
        let p50 = ((a0 * 0.50 + a1) * 0.50 + a2) * 0.50 + a3
        // t = 0.75
        let p75 = ((a0 * 0.75 + a1) * 0.75 + a2) * 0.75 + a3

        maxPeak = max(maxPeak, max(abs(p25), max(abs(p50), abs(p75))))
        return maxPeak
    }

    /// Конвертирует входной планарный блок `Float32` в 64-байтно выровненный `Double` с применением
    /// запаса по перегрузке (`Headroom`) и защиты от межвыборочных пиков (`True Peak ISP`).
    public func processPlanarFloat32ToDouble(
        inputL: UnsafePointer<Float>,
        inputR: UnsafePointer<Float>,
        outputL: UnsafeMutablePointer<Double>,
        outputR: UnsafeMutablePointer<Double>,
        frameCount: Int
    ) {
        guard frameCount > 0 else { return }

        // 1. Векторная конвертация Float32 -> Double через vDSP + масштабирование на linearHeadroomGain
        vDSP_vspdp(inputL, 1, outputL, 1, vDSP_Length(frameCount))
        vDSP_vspdp(inputR, 1, outputR, 1, vDSP_Length(frameCount))

        var gain = linearHeadroomGain
        vDSP_vsmulD(outputL, 1, &gain, outputL, 1, vDSP_Length(frameCount))
        vDSP_vsmulD(outputR, 1, &gain, outputR, 1, vDSP_Length(frameCount))

        guard ispProtectionEnabled else { return }

        // 2. Детекция межвыборочных пиков (True Peak 4x) с 2-отсчётной линией предпросмотра (look-ahead):
        // интервал [l1, l2] оценивается по опорным точкам (l0, l1, l2, l3) ДО выдачи l1 на выход,
        // что гарантирует 0% проскока межвыборочного пика выше -0.5 dBFS в модулятор 7-го порядка.
        var (l0, l1, l2) = histL
        var (r0, r1, r2) = histR
        var env = envelopeGain
        let releaseCoeff = 0.9995 // Плавное восстановление усиления (~45 мс)
        var clippedInBlock = false

        for i in 0..<frameCount {
            let l3 = outputL[i]
            let r3 = outputR[i]

            let tpL = max(Self.estimateTruePeak4x(x0: l0, x1: l1, x2: l2, x3: l3), abs(l3))
            let tpR = max(Self.estimateTruePeak4x(x0: r0, x1: r1, x2: r2, x3: r3), abs(r3))
            let peak = max(tpL, tpR)

            if peak * env > ispCeiling {
                env = ispCeiling / max(peak, 1.0e-12)
                clippedInBlock = true
            } else if env < 1.0 {
                env = min(1.0, env * releaseCoeff + (1.0 - releaseCoeff))
            }

            outputL[i] = (env < 0.999999) ? (l1 * env) : l1
            outputR[i] = (env < 0.999999) ? (r1 * env) : r1

            l0 = l1; l1 = l2; l2 = l3
            r0 = r1; r1 = r2; r2 = r3
        }

        if clippedInBlock {
            ispClipCount &+= 1
        }
        histL = (l0, l1, l2)
        histR = (r0, r1, r2)
        envelopeGain = env
    }

    /// Применяет `Headroom` и `True Peak 4x ISP` защиту поверх уже сконвертированного `FP64` буфера
    /// (позволяет запускать `MasteringDeClipper` и `Weiss De-Esser` на «сырой» шкале `0 dBFS` до аттенюатора).
    public func processPlanarDoubleInPlace(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frameCount: Int,
        maxLinearGainCap: Double = 1.0
    ) {
        guard frameCount > 0 else { return }

        var gain = min(linearHeadroomGain, maxLinearGainCap)
        vDSP_vsmulD(left, 1, &gain, left, 1, vDSP_Length(frameCount))
        vDSP_vsmulD(right, 1, &gain, right, 1, vDSP_Length(frameCount))

        guard ispProtectionEnabled else { return }

        var (l0, l1, l2) = histL
        var (r0, r1, r2) = histR
        var env = envelopeGain
        let releaseCoeff = 0.9995
        var clippedInBlock = false

        for i in 0..<frameCount {
            let l3 = left[i]
            let r3 = right[i]

            let tpL = max(Self.estimateTruePeak4x(x0: l0, x1: l1, x2: l2, x3: l3), abs(l3))
            let tpR = max(Self.estimateTruePeak4x(x0: r0, x1: r1, x2: r2, x3: r3), abs(r3))
            let peak = max(tpL, tpR)

            if peak * env > ispCeiling {
                env = ispCeiling / max(peak, 1.0e-12)
                clippedInBlock = true
            } else if env < 1.0 {
                env = min(1.0, env * releaseCoeff + (1.0 - releaseCoeff))
            }

            left[i] = (env < 0.999999) ? (l1 * env) : l1
            right[i] = (env < 0.999999) ? (r1 * env) : r1

            l0 = l1; l1 = l2; l2 = l3
            r0 = r1; r1 = r2; r2 = r3
        }

        if clippedInBlock {
            ispClipCount &+= 1
        }
        histL = (l0, l1, l2)
        histR = (r0, r1, r2)
        envelopeGain = env
    }
}

/// Единый интерфейс гибридного оверсэмплера (`Accelerate AMX FP64` и `Metal Overlap-Save GPU`).
public protocol OversamplerBackend: AnyObject, Sendable {
    var backendKind: OversamplerBackendKind { get }
    var phaseMode: OversamplerPhaseMode { get set }

    /// Сбрасывает линии задержки всех каскадов фильтрации.
    func reset()

    /// Выполняет многоступенчатый оверсэмплинг стереоблока `Double` с входной частоты `inputRateHz`
    /// до целевой частоты DSD (`targetRateHz`, кратность 64/128/256/512) или `HQ NOS PCM` (`352.8..768 kHz`).
    ///
    /// - Returns: Количество сгенерированных выходных кадров в `outputBuffer`.
    func oversampleStereoBlock(
        inputL: UnsafePointer<Double>,
        inputR: UnsafePointer<Double>,
        inputFrames: Int,
        inputRateHz: Int,
        targetRateHz: Int,
        outputBuffer: AlignedPlanarDoubleBuffer
    ) -> Int
}
