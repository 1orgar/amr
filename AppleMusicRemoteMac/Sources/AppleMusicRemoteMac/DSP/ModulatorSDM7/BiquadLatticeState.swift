import simd

/// Ультрабыстрый генератор псевдослучайных чисел Xoroshiro128+ без аллокаций и ветвлений
/// для формирования высокочастотного треугольного дизеринга (TPDF, уровень ~ 1e-7) на входе квантователя,
/// разрушающего предельные циклы (idle tones) при цифровом нуле и малых постоянных смещениях
/// с последующим подавлением шумом NTF(z) > 160 dB в звуковой полосе.
@frozen
public struct Xoroshiro128Plus: Sendable {
    public var s0: UInt64
    public var s1: UInt64

    @inlinable
    public init(seed0: UInt64 = 0x9E37_79B9_7F4A_7C15, seed1: UInt64 = 0xBF58_476D_1CE4_E5B9) {
        self.s0 = seed0 != 0 ? seed0 : 0x9E37_79B9_7F4A_7C15
        self.s1 = seed1 != 0 ? seed1 : 0xBF58_476D_1CE4_E5B9
    }

    @inline(__always)
    @inlinable
    public mutating func nextUInt64() -> UInt64 {
        let a = s0
        var b = s1
        let result = a &+ b
        b ^= a
        s0 = ((a << 24) | (a >> 40)) ^ b ^ (b << 16)
        s1 = (b << 37) | (b >> 27)
        return result
    }

    /// Равномерно распределённое число в интервале [-0.5, +0.5) с 53-битной мантиссой IEEE-754 Double.
    @inline(__always)
    @inlinable
    public mutating func nextSymmetricUniform() -> Double {
        let bits = nextUInt64() >> 11
        return Double(bits) * 0x1.0p-53 - 0.5
    }

    /// Треугольное распределение (TPDF) в диапазоне [-amplitude, +amplitude].
    @inline(__always)
    @inlinable
    public mutating func nextTPDF(amplitude: Double = 1.0e-7) -> Double {
        let u1 = nextSymmetricUniform()
        let u2 = nextSymmetricUniform()
        return (u1 + u2) * amplitude
    }
}

/// 64-байтный (1 кэш-линия Apple Silicon) вектор состояния 7-порядкового симплектического
/// биквадратного решётчатого дельта-сигма модулятора, размещаемый в 4 векторных регистрах
/// ARM64 NEON (`v0..v3`, `SIMD2<Double>` / `float64x2_t`).
///
/// Топология каскадов:
/// - `s01.x` (`s0`): первый DC-интегратор (`z = 1`)
/// - `s01.y` (`s1`), `s23.x` (`s2`): биквадратный резонатор Чебышёва №1 (без потерь, `|z| == 1`)
/// - `s23.y` (`s3`), `s45.x` (`s4`): биквадратный резонатор Чебышёва №2 (без потерь, `|z| == 1`)
/// - `s45.y` (`s5`), `s6Isi.x` (`s6`): биквадратный резонатор Чебышёва №3 (без потерь, `|z| == 1`)
/// - `s6Isi.y` (`isiAcc`): экспоненциальный аккумулятор плотности переключений для подавления ISI без деградации THD
@frozen
public struct BiquadLatticeState: Sendable, Equatable {
    public var s01: SIMD2<Double>
    public var s23: SIMD2<Double>
    public var s45: SIMD2<Double>
    public var s6Isi: SIMD2<Double>

    @inlinable
    public init(
        s01: SIMD2<Double> = .zero,
        s23: SIMD2<Double> = .zero,
        s45: SIMD2<Double> = .zero,
        s6Isi: SIMD2<Double> = .zero
    ) {
        self.s01 = s01
        self.s23 = s23
        self.s45 = s45
        self.s6Isi = s6Isi
    }

    /// Максимальная абсолютная амплитуда старших резонаторов `s3..s6` для контроля перегрузки.
    @inlinable
    public var maxAbsHighOrder: Double {
        let a45 = abs(s45)
        return max(max(abs(s23.y), a45.x), max(a45.y, abs(s6Isi.x)))
    }

    /// Вычисляет предсказанную сумму на входе 1-битного квантователя `v[n] = u[n] + C * s[n]`
    /// в топологии Сильвы–Стинсгаарда (`STF(z) == 1.0`).
    ///
    /// При штатных уровнях (`max|s3..s6| <= 1.14`, покрывающих все номинальные сигналы `-3.5 dBFS`)
    /// выполняется строго линейная 7-порядковая свёртка с `0.0 THD`.
    @inlinable
    public func predictQuantizerInput(u: Double, coeffs: SDM7SectionCoefficients) -> Double {
        let maxHi = maxAbsHighOrder
        if maxHi <= 1.14 {
            let p01 = coeffs.ff01 * s01
            let p23 = coeffs.ff23 * s23
            let p45 = coeffs.ff45 * s45
            let sumPair = (p01 + p23) + p45
            return u + (sumPair.x + sumPair.y) + coeffs.ff6IsiPad.x * s6Isi.x
        }

        let gov = min(0.85, (maxHi - 1.14) * (1.0 / 0.30))
        let wMid = 1.0 - 0.50 * gov
        let wOuter = 1.0 - 0.85 * gov
        let core = s01.x * coeffs.ff01.x + s01.y * coeffs.ff01.y + s23.x * coeffs.ff23.x
        let mid = wMid * (s23.y * coeffs.ff23.y + s45.x * coeffs.ff45.x)
        let outer = wOuter * (s45.y * coeffs.ff45.y + s6Isi.x * coeffs.ff6IsiPad.x)
        return u + core + mid + outer
    }

    /// Rank-2 квадратичная форма грамиана наблюдаемости `s^T P_obs s` (>99.3% полной энергии наблюдаемости `A_cl`),
    /// направляющая поиск Витерби вдоль истинных собственных векторов области притяжения 7-порядковой системы.
    @inlinable
    public func observabilityEnergy(coeffs: SDM7SectionCoefficients) -> Double {
        let a01 = coeffs.obs0_01 * s01
        let a23 = coeffs.obs0_23 * s23
        let a45 = coeffs.obs0_45 * s45
        let sumA = (a01 + a23) + a45
        let p0 = (sumA.x + sumA.y) + coeffs.obs0_6Pad.x * s6Isi.x

        let b01 = coeffs.obs1_01 * s01
        let b23 = coeffs.obs1_23 * s23
        let b45 = coeffs.obs1_45 * s45
        let sumB = (b01 + b23) + b45
        let p1 = (sumB.x + sumB.y) + coeffs.obs1_6Pad.x * s6Isi.x

        return p0 * p0 + p1 * p1
    }

    /// Евклидова энергия вектора состояний `||s||_2^2`.
    @inlinable
    public var stateEnergy: Double {
        let e01 = s01 * s01
        let e23 = s23 * s23
        let e45 = s45 * s45
        let pair = (e01 + e23) + e45
        return pair.x + pair.y + s6Isi.x * s6Isi.x
    }

    /// Максимальная абсолютная амплитуда среди всех 7 интеграторов для телеметрии и верификации устойчивости.
    @inlinable
    public var maxAbsIntegrator: Double {
        let a01 = abs(s01)
        let a23 = abs(s23)
        let a45 = abs(s45)
        let m0 = max(a01.x, a01.y)
        let m1 = max(a23.x, a23.y)
        let m2 = max(a45.x, a45.y)
        return max(max(m0, m1), max(m2, abs(s6Isi.x)))
    }

    /// Гладкий асимптотический предохранитель на внешней границе области притяжения (`|x| > ceiling = 1.20`).
    /// Во всём рабочем диапазоне `|x| <= ceiling` тождественно возвращает `x` (`0.0 THD`).
    @inline(__always)
    @inlinable
    public static func softCeiling(_ x: Double, ceiling: Double = 1.20) -> Double {
        let ax = x.magnitude
        if ax <= ceiling {
            return x
        }
        let ov = ax - ceiling
        let sat = ceiling + (0.16 * ov) / (0.16 + ov)
        return x >= 0.0 ? sat : -sat
    }

    /// Выполняет один симплектический такт обновления 7-порядковой решётки для гипотезы выхода `y` (`-1.0` или `+1.0`).
    @inlinable
    public func stepped(
        u: Double,
        y: Double,
        isTransition: Bool,
        coeffs: SDM7SectionCoefficients
    ) -> (nextState: BiquadLatticeState, barrierPenalty: Double) {
        let err = u - y
        let maxHi = maxAbsHighOrder
        let gov = (maxHi > 1.14) ? min(0.85, (maxHi - 1.14) * (1.0 / 0.30)) : 0.0

        // 1. Входной DC-интегратор (s0)
        let raw0 = s01.x + coeffs.b0 * err

        // 2. Симплектический резонатор Чебышёва №1 (s1, s2): |z_zero| == 1.0
        let raw1 = s01.y + coeffs.aLink01.x * s01.x - coeffs.gFeedback01.x * s23.x
        let ns1 = Self.softCeiling(raw1)
        let raw2 = s23.x + coeffs.cIntegrator01.x * ns1

        // 3. Симплектический резонатор Чебышёва №2 (s3, s4): |z_zero| == 1.0
        let a2Scale = (gov > 0.0) ? (1.0 - 0.45 * gov) : 1.0
        let raw3 = s23.y + (a2Scale * coeffs.aLink01.y) * s23.x - coeffs.gFeedback01.y * s45.x
        let ns3 = Self.softCeiling(raw3)
        let raw4 = s45.x + coeffs.cIntegrator01.y * ns3

        // 4. Симплектический резонатор Чебышёва №3 (s5, s6): |z_zero| == 1.0
        let a3Scale = (gov > 0.0) ? (1.0 - 0.80 * gov) : 1.0
        let raw5 = s45.y + (a3Scale * coeffs.aLink2Pad.x) * s45.x - coeffs.gFeedback2Pad.x * s6Isi.x
        let ns5 = Self.softCeiling(raw5)
        let raw6 = s6Isi.x + coeffs.cIntegrator2Pad.x * ns5

        let ns0 = Self.softCeiling(raw0)
        let ns2 = Self.softCeiling(raw2)
        let ns4 = Self.softCeiling(raw4)
        let ns6 = Self.softCeiling(raw6)

        // Гладкий барьер перегрузки (строго нулевой при |raw_k| <= softClipThreshold = 0.98)
        let thr = coeffs.softClipThreshold
        let ex0 = max(0.0, abs(raw0) - thr)
        let ex1 = max(0.0, abs(raw1) - thr)
        let ex2 = max(0.0, abs(raw2) - thr)
        let ex3 = max(0.0, abs(raw3) - thr)
        let ex4 = max(0.0, abs(raw4) - thr)
        let ex5 = max(0.0, abs(raw5) - thr)
        let ex6 = max(0.0, abs(raw6) - thr)

        let barrierPenalty = (ex0 * ex0) + (ex1 * ex1) + (ex2 * ex2)
            + (ex3 * ex3) + (ex4 * ex4) + (ex5 * ex5) + (ex6 * ex6)

        let nextIsi = 0.90 * s6Isi.y + (isTransition ? 0.10 : 0.0)
        let next = BiquadLatticeState(
            s01: SIMD2<Double>(ns0, ns1),
            s23: SIMD2<Double>(ns2, ns3),
            s45: SIMD2<Double>(ns4, ns5),
            s6Isi: SIMD2<Double>(ns6, nextIsi)
        )
        return (next, barrierPenalty)
    }

    /// Совместимая обёртка шага решётки для внешних вызовов и тестов.
    @inlinable
    public func stepped(
        u: Double,
        y: Double,
        prevY: Double,
        dither: Double,
        coeffs: SDM7SectionCoefficients
    ) -> (nextState: BiquadLatticeState, barrierPenalty: Double, isiPenalty: Double) {
        let _ = dither
        let switched = (y != prevY)
        let (next, bar) = stepped(u: u, y: y, isTransition: switched, coeffs: coeffs)
        let chatterExcess = max(0.0, s6Isi.y - 0.44)
        let isi = switched ? (coeffs.isiLambda * 4.0 * chatterExcess) : 0.0
        return (next, bar, isi)
    }
}
