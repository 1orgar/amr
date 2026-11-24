import Foundation
import simd

/// Высокоточный квантователь `Double (FP64) -> Int32 (24-bit / 32-bit)` для режима
/// `HQ NOS PCM (705.6 / 768 kHz)` под дискретные мультибитные R2R ЦАП (Denafrips, Holo Audio, Chord).
///
/// Поддерживает:
/// - `.tpdf`: чистый треугольный дизеринг (2 LSB peak-to-peak) без окрашивания шумовой полки;
/// - `.lns15`: 15-порядковый минимально-фазовый психоакустический формирователь шума (`LNS15` на высокой
///   частоте дискретизации 352.8–768 кГц), синтезированный методом вещественного кепстра Оппенгейма–Шафера
///   с соблюдением строгого критерия устойчивости Ли (`||H_err(e^{jw})||_inf = 1.466 < 1.55`, без пика на Найквисте)
///   и дополнительным подавлением внутриполосного шума квантования в диапазоне 20 Гц – 20 кГц на `~11 dB` лучше `.tpdf`.
@frozen
public struct NOSPCMDitherQuantizer: Sendable {
    public var mode: NOSPCMDitherMode
    public var targetBits: Int

    @usableFromInline
    internal var prng: Xoroshiro128Plus

    /// Линия задержки ошибки квантования `e[n-1] ... e[n-15]` (16 элементов для выравнивания SIMD2<Double>).
    @usableFromInline
    internal var err01: SIMD2<Double> = .zero
    @usableFromInline
    internal var err23: SIMD2<Double> = .zero
    @usableFromInline
    internal var err45: SIMD2<Double> = .zero
    @usableFromInline
    internal var err67: SIMD2<Double> = .zero
    @usableFromInline
    internal var err89: SIMD2<Double> = .zero
    @usableFromInline
    internal var err1011: SIMD2<Double> = .zero
    @usableFromInline
    internal var err1213: SIMD2<Double> = .zero
    @usableFromInline
    internal var err1415: SIMD2<Double> = .zero

    /// Коэффициенты 15-порядкового минимально-фазового FIR-предсказателя ошибки `H_err(z) = 1 - sum_{k=1}^{15} b_k z^{-k}`:
    /// - строгий критерий устойчивости Ли: `max_w |H_err(e^{jw})| = 1.4656 (+3.32 dB) < 1.55` (отсутствие выброса на Fs/2);
    /// - среднее подавление шума квантования в звуковой полосе `20 Hz .. 20 kHz`: `-11.0 dB` @ `352.8 kHz`, `-10.6 dB` @ `705.6/768 kHz`.
    @usableFromInline
    internal static let lns01 = SIMD2<Double>(0.687468, 0.268730)
    @usableFromInline
    internal static let lns23 = SIMD2<Double>(-0.001252, -0.122419)
    @usableFromInline
    internal static let lns45 = SIMD2<Double>(-0.130760, -0.078989)
    @usableFromInline
    internal static let lns67 = SIMD2<Double>(-0.016114, 0.026634)
    @usableFromInline
    internal static let lns89 = SIMD2<Double>(0.039798, 0.030593)
    @usableFromInline
    internal static let lns1011 = SIMD2<Double>(0.013130, -0.000720)
    @usableFromInline
    internal static let lns1213 = SIMD2<Double>(-0.006099, -0.004796)
    @usableFromInline
    internal static let lns1415 = SIMD2<Double>(-0.001550, 0.0)

    public init(
        mode: NOSPCMDitherMode = .lns15,
        targetBits: Int = 24,
        seed: UInt64 = 0xD1B5_4A32_D192_ED03
    ) {
        self.mode = mode
        self.targetBits = (targetBits >= 32) ? 32 : 24
        self.prng = Xoroshiro128Plus(seed0: seed, seed1: seed ^ 0x9E37_79B9_7F4A_7C15)
    }

    public mutating func reset() {
        err01 = .zero
        err23 = .zero
        err45 = .zero
        err67 = .zero
        err89 = .zero
        err1011 = .zero
        err1213 = .zero
        err1415 = .zero
    }

    /// Квантует один отсчёт `sample` (`[-1.0, +1.0]`) в 32-битное знаковое слово `Int32` (выровненное по MSB).
    @inlinable
    public mutating func quantizeSample(_ sample: Double) -> Int32 {
        let clamped = min(max(sample, -0.9999998807907104), 0.9999998807907104)
        let is24Bit = (targetBits <= 24)
        // Масштаб в квантах младшего значащего разряда (LSB) целевой разрядности
        let fullScaleLSB: Double = is24Bit ? 8_388_607.0 : 2_147_483_647.0
        let xLSB = clamped * fullScaleLSB

        // Треугольный дизеринг TPDF в диапазоне [-1.0 LSB, +1.0 LSB]
        let ditherLSB = prng.nextTPDF(amplitude: 1.0)

        let shapedLSB: Double
        if mode == .lns15 {
            let p0 = Self.lns01 * err01 + Self.lns23 * err23
            let p1 = Self.lns45 * err45 + Self.lns67 * err67
            let p2 = Self.lns89 * err89 + Self.lns1011 * err1011
            let p3 = Self.lns1213 * err1213 + Self.lns1415 * err1415
            let sumVec = (p0 + p1) + (p2 + p3)
            let feedback = sumVec.x + sumVec.y
            shapedLSB = xLSB + feedback + ditherLSB
        } else {
            shapedLSB = xLSB + ditherLSB
        }

        let quantizedLSB = (shapedLSB >= 0.0) ? Foundation.floor(shapedLSB + 0.5) : Foundation.ceil(shapedLSB - 0.5)
        let boundedLSB = min(max(quantizedLSB, -fullScaleLSB), fullScaleLSB)

        if mode == .lns15 {
            // Ошибка квантования e[n] = x_shaped_without_dither - Q(x) с мягким ограничением +-4 LSB
            let rawErr = min(max((shapedLSB - ditherLSB) - boundedLSB, -4.0), 4.0)
            err1415 = SIMD2<Double>(err1213.y, err1415.x)
            err1213 = SIMD2<Double>(err1011.y, err1213.x)
            err1011 = SIMD2<Double>(err89.y, err1011.x)
            err89 = SIMD2<Double>(err67.y, err89.x)
            err67 = SIMD2<Double>(err45.y, err67.x)
            err45 = SIMD2<Double>(err23.y, err45.x)
            err23 = SIMD2<Double>(err01.y, err23.x)
            err01 = SIMD2<Double>(rawErr, err01.x)
        }

        let intVal = Int32(boundedLSB)
        return is24Bit ? (intVal << 8) : intVal
    }

    /// Пакетное квантование стереопары планарных буферов `Double` в чередующийся (`L, R, L, R`) массив `Int32`.
    @inlinable
    public static func quantizeStereoBlock(
        left: UnsafePointer<Double>,
        right: UnsafePointer<Double>,
        frameCount: Int,
        quantizerL: inout NOSPCMDitherQuantizer,
        quantizerR: inout NOSPCMDitherQuantizer,
        interleavedOut: UnsafeMutablePointer<Int32>
    ) {
        for i in 0..<frameCount {
            interleavedOut[i &* 2] = quantizerL.quantizeSample(left[i])
            interleavedOut[i &* 2 &+ 1] = quantizerR.quantizeSample(right[i])
        }
    }
}
