//
//  TrellisBankTypes.swift
//  AppleMusicRemoteMac
//
//  Zero-Allocation Register & Stack Bank Types for 7th-Order Trellis Viterbi SDM.
//

import simd

/// Узел-кандидат в решётчатом дереве поиска Витерби (Trellis Look-Ahead SDM).
/// Полностью размещается в регистрах и на стеке (0 аллокаций в куче).
@frozen
public struct TrellisCandidatePath: Sendable {
    public var state: BiquadLatticeState
    public var cost: Double
    public var history: UInt64
    public var lastY: Double

    @inlinable
    public init(
        state: BiquadLatticeState = BiquadLatticeState(),
        cost: Double = 0.0,
        history: UInt64 = 0xAAAA_AAAA_AAAA_AAAA,
        lastY: Double = -1.0
    ) {
        self.state = state
        self.cost = cost
        self.history = history
        self.lastY = lastY
    }
}

/// Компактный 80-байтный слот выжившего пути для безспиллового регистрового ядра `M = 8`.
@frozen
@usableFromInline
internal struct FastLinearSlot: Sendable {
    @usableFromInline var s01: SIMD2<Double>
    @usableFromInline var s23: SIMD2<Double>
    @usableFromInline var s45: SIMD2<Double>
    @usableFromInline var s6I: SIMD2<Double>
    @usableFromInline var cost: Double
    @usableFromInline var hist: UInt64

    @inline(__always)
    @usableFromInline
    init(
        s01: SIMD2<Double>,
        s23: SIMD2<Double>,
        s45: SIMD2<Double>,
        s6I: SIMD2<Double>,
        cost: Double,
        hist: UInt64
    ) {
        self.s01 = s01
        self.s23 = s23
        self.s45 = s45
        self.s6I = s6I
        self.cost = cost
        self.hist = hist
    }
}

/// Результат выполнения безспиллового линейного блока `M = 8` (с поддержкой мгновенного отката на редких пиках `> bitLinBound`).
@frozen
@usableFromInline
internal struct FastLinearBlockResult: Sendable {
    @usableFromInline var completedBytes: Int
    @usableFromInline var abortedBitPos: Int
    @usableFromInline var partialByte: UInt8
    @usableFromInline var curCount: Int
    @usableFromInline var peakAmp: Double
    @usableFromInline var prngS0: UInt64
    @usableFromInline var prngS1: UInt64

    @inline(__always)
    @usableFromInline
    init(
        completedBytes: Int,
        abortedBitPos: Int,
        partialByte: UInt8,
        curCount: Int,
        peakAmp: Double,
        prngS0: UInt64,
        prngS1: UInt64
    ) {
        self.completedBytes = completedBytes
        self.abortedBitPos = abortedBitPos
        self.partialByte = partialByte
        self.curCount = curCount
        self.peakAmp = peakAmp
        self.prngS0 = prngS0
        self.prngS1 = prngS1
    }
}

/// Фиксированный стековый буфер на 16 выживших путей Витерби (0 ARC / 0 heap allocations).
@frozen
public struct TrellisSurvivorBank16: Sendable {
    public var p0: TrellisCandidatePath
    public var p1: TrellisCandidatePath
    public var p2: TrellisCandidatePath
    public var p3: TrellisCandidatePath
    public var p4: TrellisCandidatePath
    public var p5: TrellisCandidatePath
    public var p6: TrellisCandidatePath
    public var p7: TrellisCandidatePath
    public var p8: TrellisCandidatePath
    public var p9: TrellisCandidatePath
    public var p10: TrellisCandidatePath
    public var p11: TrellisCandidatePath
    public var p12: TrellisCandidatePath
    public var p13: TrellisCandidatePath
    public var p14: TrellisCandidatePath
    public var p15: TrellisCandidatePath

    @inlinable
    public init() {
        let def = TrellisCandidatePath()
        self.p0 = def; self.p1 = def; self.p2 = def; self.p3 = def
        self.p4 = def; self.p5 = def; self.p6 = def; self.p7 = def
        self.p8 = def; self.p9 = def; self.p10 = def; self.p11 = def
        self.p12 = def; self.p13 = def; self.p14 = def; self.p15 = def
    }

    @inlinable
    public subscript(index: Int) -> TrellisCandidatePath {
        get {
            return withUnsafePointer(to: self) { ptr in
                ptr.withMemoryRebound(to: TrellisCandidatePath.self, capacity: 16) {
                    $0[index]
                }
            }
        }
        set {
            withUnsafeMutablePointer(to: &self) { ptr in
                ptr.withMemoryRebound(to: TrellisCandidatePath.self, capacity: 16) {
                    $0[index] = newValue
                }
            }
        }
    }
}

/// Фиксированный стековый буфер на 32 развёрнутых дочерних пути (2 * M при M <= 16).
@frozen
public struct TrellisExpandedBank32: Sendable {
    public var lo: TrellisSurvivorBank16
    public var hi: TrellisSurvivorBank16

    @inlinable
    public init() {
        self.lo = TrellisSurvivorBank16()
        self.hi = TrellisSurvivorBank16()
    }
}

/// Фиксированный стековый массив из 32 скалярных ранговых оценок look-ahead (4 x SIMD8<Double>, 0 heap allocations).
@frozen
@usableFromInline
internal struct TrellisRankScoreBank32: Sendable {
    @usableFromInline var s0: SIMD8<Double> = .zero
    @usableFromInline var s1: SIMD8<Double> = .zero
    @usableFromInline var s2: SIMD8<Double> = .zero
    @usableFromInline var s3: SIMD8<Double> = .zero

    @inlinable
    init() {}
}

/// Фиксированный стековый массив из 32 индексов фильтрации (4 x SIMD8<Int32>, 0 heap allocations).
@frozen
@usableFromInline
internal struct TrellisIndexBank32: Sendable {
    @usableFromInline var i0: SIMD8<Int32> = .zero
    @usableFromInline var i1: SIMD8<Int32> = .zero
    @usableFromInline var i2: SIMD8<Int32> = .zero
    @usableFromInline var i3: SIMD8<Int32> = .zero

    @inlinable
    init() {}
}
