//
//  RoomAcousticModels.swift
//  AppleMusicRemoteMac
//
//  Room Acoustic Data Models, 64-bit RBJ Biquad Math, Real-Time RoomEQProcessor,
//  and Paul Kellet 7-State Calibrated Pink Noise Generator State.
//

import Foundation
import os

// MARK: - Data Models

public struct RoomEQBand: Codable, Sendable, Equatable {
    public var frequencyHz: Double
    public var gainDB: Double
    public var q: Double
    public var filterType: String // "peaking", "low_shelf", "high_shelf"

    public init(
        frequencyHz: Double,
        gainDB: Double,
        q: Double,
        filterType: String = "peaking"
    ) {
        self.frequencyHz = frequencyHz
        self.gainDB = gainDB
        self.q = q
        self.filterType = filterType
    }

    public var dictionary: [String: Any] {
        [
            "frequency_hz": frequencyHz,
            "gain_db": (gainDB * 100.0).rounded() / 100.0,
            "q": (q * 100.0).rounded() / 100.0,
            "filter_type": filterType
        ]
    }
}

public struct RoomAcousticProfile: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var measuredOnDevice: String
    public var createdAt: TimeInterval
    public var updatedAt: TimeInterval
    public var bandsHz: [Double]
    public var measuredResponseDB: [Double]
    public var targetCurveDB: [Double]
    public var correctedResponseDB: [Double]
    public var maxPeakDeviationDB: Double
    public var eqBands: [RoomEQBand]
    public var preampGainDB: Double

    public init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        measuredOnDevice: String,
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        updatedAt: TimeInterval = Date().timeIntervalSince1970,
        bandsHz: [Double],
        measuredResponseDB: [Double],
        targetCurveDB: [Double],
        correctedResponseDB: [Double],
        maxPeakDeviationDB: Double,
        eqBands: [RoomEQBand],
        preampGainDB: Double
    ) {
        self.id = id
        self.name = name
        self.measuredOnDevice = measuredOnDevice
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.bandsHz = bandsHz
        self.measuredResponseDB = measuredResponseDB
        self.targetCurveDB = targetCurveDB
        self.correctedResponseDB = correctedResponseDB
        self.maxPeakDeviationDB = maxPeakDeviationDB
        self.eqBands = eqBands
        self.preampGainDB = preampGainDB
    }

    public var dictionary: [String: Any] {
        [
            "id": id,
            "name": name,
            "measured_on_device": measuredOnDevice,
            "created_at": createdAt,
            "updated_at": updatedAt,
            "bands_hz": bandsHz,
            "measured_response_db": measuredResponseDB.map { ($0 * 100.0).rounded() / 100.0 },
            "target_curve_db": targetCurveDB.map { ($0 * 100.0).rounded() / 100.0 },
            "corrected_response_db": correctedResponseDB.map { ($0 * 100.0).rounded() / 100.0 },
            "max_peak_deviation_db": (maxPeakDeviationDB * 100.0).rounded() / 100.0,
            "eq_bands": eqBands.map { $0.dictionary },
            "preamp_gain_db": (preampGainDB * 100.0).rounded() / 100.0
        ]
    }
}

// MARK: - 64-bit RBJ Biquad Math & Real-Time Processor

public struct RoomBiquadCoefficients: Sendable, Equatable {
    public var b0: Double = 1.0
    public var b1: Double = 0.0
    public var b2: Double = 0.0
    public var a1: Double = 0.0
    public var a2: Double = 0.0

    public init(b0: Double = 1.0, b1: Double = 0.0, b2: Double = 0.0, a1: Double = 0.0, a2: Double = 0.0) {
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
    }

    public static func makeRBJ(band: RoomEQBand, sampleRate: Double) -> RoomBiquadCoefficients {
        let fs = max(8_000.0, sampleRate)
        let f0 = max(16.0, min(fs * 0.46, band.frequencyHz))
        let q = max(0.25, min(12.0, band.q))
        let db = max(-15.0, min(12.0, band.gainDB))
        if abs(db) < 0.02 {
            return RoomBiquadCoefficients()
        }

        let A = pow(10.0, db / 40.0)
        let w0 = 2.0 * Double.pi * f0 / fs
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)

        let rawB0: Double
        let rawB1: Double
        let rawB2: Double
        let rawA0: Double
        let rawA1: Double
        let rawA2: Double

        switch band.filterType {
        case "low_shelf":
            let alpha = sinW0 / 2.0 * sqrt(max(0.05, (A + 1.0 / A) * (1.0 / max(0.3, min(2.0, q)) - 1.0) + 2.0))
            let twoSqrtAAlpha = 2.0 * sqrt(A) * alpha
            rawB0 = A * ((A + 1.0) - (A - 1.0) * cosW0 + twoSqrtAAlpha)
            rawB1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cosW0)
            rawB2 = A * ((A + 1.0) - (A - 1.0) * cosW0 - twoSqrtAAlpha)
            rawA0 = (A + 1.0) + (A - 1.0) * cosW0 + twoSqrtAAlpha
            rawA1 = -2.0 * ((A - 1.0) + (A + 1.0) * cosW0)
            rawA2 = (A + 1.0) + (A - 1.0) * cosW0 - twoSqrtAAlpha
        case "high_shelf":
            let alpha = sinW0 / 2.0 * sqrt(max(0.05, (A + 1.0 / A) * (1.0 / max(0.3, min(2.0, q)) - 1.0) + 2.0))
            let twoSqrtAAlpha = 2.0 * sqrt(A) * alpha
            rawB0 = A * ((A + 1.0) + (A - 1.0) * cosW0 + twoSqrtAAlpha)
            rawB1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cosW0)
            rawB2 = A * ((A + 1.0) + (A - 1.0) * cosW0 - twoSqrtAAlpha)
            rawA0 = (A + 1.0) - (A - 1.0) * cosW0 + twoSqrtAAlpha
            rawA1 = 2.0 * ((A - 1.0) - (A + 1.0) * cosW0)
            rawA2 = (A + 1.0) - (A - 1.0) * cosW0 - twoSqrtAAlpha
        default: // "peaking"
            let alpha = sinW0 / (2.0 * q)
            rawB0 = 1.0 + alpha * A
            rawB1 = -2.0 * cosW0
            rawB2 = 1.0 - alpha * A
            rawA0 = 1.0 + alpha / A
            rawA1 = -2.0 * cosW0
            rawA2 = 1.0 - alpha / A
        }

        let invA0 = 1.0 / rawA0
        return RoomBiquadCoefficients(
            b0: rawB0 * invA0,
            b1: rawB1 * invA0,
            b2: rawB2 * invA0,
            a1: rawA1 * invA0,
            a2: rawA2 * invA0
        )
    }

    public func magnitudeDB(atFrequencyHz freq: Double, sampleRate: Double) -> Double {
        let w = 2.0 * Double.pi * max(1.0, freq) / max(8_000.0, sampleRate)
        let cosW = cos(w)
        let sinW = sin(w)
        let cos2W = cos(2.0 * w)
        let sin2W = sin(2.0 * w)

        let numRe = b0 + b1 * cosW + b2 * cos2W
        let numIm = -(b1 * sinW + b2 * sin2W)
        let denRe = 1.0 + a1 * cosW + a2 * cos2W
        let denIm = -(a1 * sinW + a2 * sin2W)

        let numMagSq = numRe * numRe + numIm * numIm
        let denMagSq = max(1.0e-18, denRe * denRe + denIm * denIm)
        return 10.0 * log10(max(1.0e-18, numMagSq / denMagSq))
    }
}

/// RT-safe 64-bit stereo biquad cascade (up to 8 stages, zero heap allocations in process calls).
public final class RoomEQProcessor: @unchecked Sendable {
    public static let maxStages = 8

    private var spinLock = os_unfair_lock_s()
    private var enabled: Bool = false
    private var configuredBands: [RoomEQBand] = []
    private var preampLinear: Double = 1.0
    private var currentSampleRate: Int = 0
    private var activeStageCount: Int = 0
    private var coeffs: [RoomBiquadCoefficients] = Array(repeating: RoomBiquadCoefficients(), count: 8)
    private var z1L: [Double] = Array(repeating: 0.0, count: 8)
    private var z2L: [Double] = Array(repeating: 0.0, count: 8)
    private var z1R: [Double] = Array(repeating: 0.0, count: 8)
    private var z2R: [Double] = Array(repeating: 0.0, count: 8)

    public init() {}

    public func configure(enabled: Bool, bands: [RoomEQBand], preampGainDB: Double) {
        let clampedBands = Array(bands.prefix(Self.maxStages))
        let gainLin = pow(10.0, max(-15.0, min(0.0, preampGainDB)) / 20.0)
        os_unfair_lock_lock(&spinLock)
        self.enabled = enabled && !clampedBands.isEmpty
        self.configuredBands = clampedBands
        self.preampLinear = gainLin
        self.currentSampleRate = 0 // Force coefficient rebuild on next audio block
        for idx in 0..<Self.maxStages {
            z1L[idx] = 0.0
            z2L[idx] = 0.0
            z1R[idx] = 0.0
            z2R[idx] = 0.0
        }
        os_unfair_lock_unlock(&spinLock)
    }

    public func resetState() {
        os_unfair_lock_lock(&spinLock)
        for idx in 0..<Self.maxStages {
            z1L[idx] = 0.0
            z2L[idx] = 0.0
            z1R[idx] = 0.0
            z2R[idx] = 0.0
        }
        os_unfair_lock_unlock(&spinLock)
    }

    public var activeSampleRateHz: Int {
        os_unfair_lock_lock(&spinLock)
        let sr = currentSampleRate
        os_unfair_lock_unlock(&spinLock)
        return sr
    }

    private func rebuildCoefficientsLocked(sampleRate: Int) {
        currentSampleRate = sampleRate
        let count = min(Self.maxStages, configuredBands.count)
        activeStageCount = count
        let fs = Double(max(8_000, sampleRate))
        for idx in 0..<count {
            coeffs[idx] = RoomBiquadCoefficients.makeRBJ(band: configuredBands[idx], sampleRate: fs)
            z1L[idx] = 0.0
            z2L[idx] = 0.0
            z1R[idx] = 0.0
            z2R[idx] = 0.0
        }
    }

    public func processPlanarDouble(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frameCount: Int,
        sampleRate: Int
    ) {
        guard frameCount > 0 else { return }
        os_unfair_lock_lock(&spinLock)
        defer { os_unfair_lock_unlock(&spinLock) }
        guard enabled else { return }
        if currentSampleRate != sampleRate {
            rebuildCoefficientsLocked(sampleRate: sampleRate)
        }
        let stages = activeStageCount
        guard stages > 0 else { return }
        let pre = preampLinear

        for i in 0..<frameCount {
            var xl = left[i] * pre
            var xr = right[i] * pre
            for s in 0..<stages {
                let c = coeffs[s]
                let yl = c.b0 * xl + z1L[s]
                z1L[s] = c.b1 * xl - c.a1 * yl + z2L[s]
                z2L[s] = c.b2 * xl - c.a2 * yl
                xl = yl

                let yr = c.b0 * xr + z1R[s]
                z1R[s] = c.b1 * xr - c.a1 * yr + z2R[s]
                z2R[s] = c.b2 * xr - c.a2 * yr
                xr = yr
            }
            left[i] = xl
            right[i] = xr
        }
    }

    public func processPlanarFloat32(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        frameCount: Int,
        sampleRate: Int
    ) {
        guard frameCount > 0 else { return }
        os_unfair_lock_lock(&spinLock)
        defer { os_unfair_lock_unlock(&spinLock) }
        guard enabled else { return }
        if currentSampleRate != sampleRate {
            rebuildCoefficientsLocked(sampleRate: sampleRate)
        }
        let stages = activeStageCount
        guard stages > 0 else { return }
        let pre = preampLinear

        for i in 0..<frameCount {
            var xl = Double(left[i]) * pre
            var xr = Double(right[i]) * pre
            for s in 0..<stages {
                let c = coeffs[s]
                let yl = c.b0 * xl + z1L[s]
                z1L[s] = c.b1 * xl - c.a1 * yl + z2L[s]
                z2L[s] = c.b2 * xl - c.a2 * yl
                xl = yl

                let yr = c.b0 * xr + z1R[s]
                z1R[s] = c.b1 * xr - c.a1 * yr + z2R[s]
                z2R[s] = c.b2 * xr - c.a2 * yr
                xr = yr
            }
            left[i] = Float(max(-1.0, min(1.0, xl)))
            right[i] = Float(max(-1.0, min(1.0, xr)))
        }
    }

    public func processInterleavedStereoOrPair(
        interleaved: UnsafeMutablePointer<Float>,
        frameCount: Int,
        channels: Int,
        sampleRate: Int
    ) {
        guard frameCount > 0, channels >= 1 else { return }
        os_unfair_lock_lock(&spinLock)
        defer { os_unfair_lock_unlock(&spinLock) }
        guard enabled else { return }
        if currentSampleRate != sampleRate {
            rebuildCoefficientsLocked(sampleRate: sampleRate)
        }
        let stages = activeStageCount
        guard stages > 0 else { return }
        let pre = preampLinear

        for i in 0..<frameCount {
            let base = i * channels
            var xl = Double(interleaved[base]) * pre
            var xr = Double(channels >= 2 ? interleaved[base + 1] : interleaved[base]) * pre
            for s in 0..<stages {
                let c = coeffs[s]
                let yl = c.b0 * xl + z1L[s]
                z1L[s] = c.b1 * xl - c.a1 * yl + z2L[s]
                z2L[s] = c.b2 * xl - c.a2 * yl
                xl = yl

                let yr = c.b0 * xr + z1R[s]
                z1R[s] = c.b1 * xr - c.a1 * yr + z2R[s]
                z2R[s] = c.b2 * xr - c.a2 * yr
                xr = yr
            }
            interleaved[base] = Float(max(-1.0, min(1.0, xl)))
            if channels >= 2 {
                interleaved[base + 1] = Float(max(-1.0, min(1.0, xr)))
            }
        }
    }

    public func processStereoFloatPair(
        left: inout Float,
        right: inout Float,
        sampleRate: Int
    ) {
        os_unfair_lock_lock(&spinLock)
        defer { os_unfair_lock_unlock(&spinLock) }
        guard enabled else { return }
        if currentSampleRate != sampleRate {
            rebuildCoefficientsLocked(sampleRate: sampleRate)
        }
        let stages = activeStageCount
        guard stages > 0 else { return }
        var xl = Double(left) * preampLinear
        var xr = Double(right) * preampLinear
        for s in 0..<stages {
            let c = coeffs[s]
            let yl = c.b0 * xl + z1L[s]
            z1L[s] = c.b1 * xl - c.a1 * yl + z2L[s]
            z2L[s] = c.b2 * xl - c.a2 * yl
            xl = yl

            let yr = c.b0 * xr + z1R[s]
            z1R[s] = c.b1 * xr - c.a1 * yr + z2R[s]
            z2R[s] = c.b2 * xr - c.a2 * yr
            xr = yr
        }
        left = Float(max(-1.0, min(1.0, xl)))
        right = Float(max(-1.0, min(1.0, xr)))
    }
}

// MARK: - Paul Kellet 7-State Calibrated Pink Noise State

@usableFromInline
internal struct PinkNoiseGeneratorState {
    @usableFromInline var b0: Double = 0.0
    @usableFromInline var b1: Double = 0.0
    @usableFromInline var b2: Double = 0.0
    @usableFromInline var b3: Double = 0.0
    @usableFromInline var b4: Double = 0.0
    @usableFromInline var b5: Double = 0.0
    @usableFromInline var b6: Double = 0.0
    @usableFromInline var rngState: UInt64 = 0x9E37_79B9_7F4A_7C15

    @usableFromInline
    init(rngState: UInt64 = 0x9E37_79B9_7F4A_7C15) {
        self.rngState = rngState
    }

    @usableFromInline
    @inline(__always)
    mutating func nextWhite() -> Double {
        // xorshift64* deterministic-free fast PRNG in [-1, 1]
        var x = rngState
        x ^= x >> 12
        x ^= x << 25
        x ^= x >> 27
        rngState = x
        let u = (x &* 0x2545_F491_4F6C_DD1D) >> 11
        return (Double(u) * (1.0 / 9007199254740992.0)) * 2.0 - 1.0
    }

    @usableFromInline
    @inline(__always)
    mutating func nextPinkSample(amplitude: Double = 0.18) -> Float {
        let white = nextWhite()
        b0 = 0.99886 * b0 + white * 0.0555179
        b1 = 0.99332 * b1 + white * 0.0750759
        b2 = 0.96900 * b2 + white * 0.1538520
        b3 = 0.86650 * b3 + white * 0.3104856
        b4 = 0.55000 * b4 + white * 0.5329522
        b5 = -0.7616 * b5 - white * 0.0168980
        let pink = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362) * 0.11
        b6 = white * 0.115926
        let scaled = max(-0.92, min(0.92, pink * amplitude))
        return Float(scaled)
    }
}
