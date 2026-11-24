//
//  LateNightDRCProcessor.swift
//  AppleMusicRemoteMac
//
//  Real-Time 64-Bit ITU-R BS.1770 K-Weighted Dual-Envelope Dynamic Range Processor
//  with -63 dBFS Noise-Floor Gate and 64-Sample Look-Ahead -1.0 dBTP Ceiling Guard.
//

import Foundation
import os.lock

/// Audiophile Late-Night Dynamic Range Control modes (`v2.8.0`).
/// When `.off`, all audio pipelines execute a 100% Bit-Perfect bypass with zero sample modification.
public enum LateNightDRCMode: String, Codable, CaseIterable, Sendable {
    case off = "off"
    case gentle = "gentle"
    case concert = "concert"

    public var isEnabled: Bool {
        self != .off
    }

    public func title(isEnglish: Bool) -> String {
        switch self {
        case .off:
            return isEnglish ? "Off (100% Bit-Perfect)" : "Выкл (100% Bit-Perfect)"
        case .gentle:
            return isEnglish ? "Gentle (Jazz / Vocal)" : "Деликатный (Джаз / Вокал)"
        case .concert:
            return isEnglish ? "Night Concert (Symphony / OST)" : "Ночной концерт (Симфония / OST)"
        }
    }

    public func shortLabel(isEnglish: Bool) -> String {
        switch self {
        case .off:
            return isEnglish ? "Off" : "Выкл"
        case .gentle:
            return isEnglish ? "Gentle" : "Деликатный"
        case .concert:
            return isEnglish ? "Night Concert" : "Ночной концерт"
        }
    }

    public func subtitle(isEnglish: Bool) -> String {
        switch self {
        case .off:
            return isEnglish
                ? "100% Bit-Perfect signal path with zero dynamic range modification."
                : "Прямой 100% Bit-Perfect тракт без динамической обработки сигнала."
        case .gentle:
            return isEnglish
                ? "Smooth upward lift up to +6.0 dB on quiet passages (< -25 LUFS) with 1.8:1 peak control and -63 dBFS noise gate."
                : "Мягкий подъём тихих деталей до +6.0 дБ (< -25 LUFS), сдерживание пиков 1.8:1 и гейт шумовой полки ниже -63 dBFS."
        case .concert:
            return isEnglish
                ? "Psychoacoustic whisper & pianissimo lift up to +9.5 dB with soft-knee 2.5:1 crescendo control and -1.0 dBTP limiter."
                : "Психоакустический подъём шёпота и пианиссимо до +9.5 дБ со сглаживанием крещендо 2.5:1 и защитой пиков -1.0 dBTP."
        }
    }
}

/// Real-time 64-bit floating-point ITU-R BS.1770 K-weighted dual-envelope upward/downward dynamic range processor
/// with a noise-floor gate (prevents tape hiss pumping) and 64-sample look-ahead `-1.0 dBTP` ceiling guard.
/// Zero heap allocations occur inside `processPlanarDouble` or `processStereoFloatPair`.
public final class LateNightDRCProcessor: @unchecked Sendable {
    private struct KWeightBiquad {
        var b0: Double = 1.0
        var b1: Double = 0.0
        var b2: Double = 0.0
        var a1: Double = 0.0
        var a2: Double = 0.0
        var z1L: Double = 0.0
        var z2L: Double = 0.0
        var z1R: Double = 0.0
        var z2R: Double = 0.0

        @inline(__always)
        mutating func resetState() {
            z1L = 0.0; z2L = 0.0
            z1R = 0.0; z2R = 0.0
        }

        @inline(__always)
        mutating func processStereo(left: inout Double, right: inout Double) {
            let outL = b0 * left + z1L
            z1L = b1 * left - a1 * outL + z2L
            z2L = b2 * left - a2 * outL
            left = outL

            let outR = b0 * right + z1R
            z1R = b1 * right - a1 * outR + z2R
            z2R = b2 * right - a2 * outR
            right = outR
        }
    }

    private static let lookAheadSamples: Int = 64
    private static let ceilingLinear: Double = 0.8912509381337456 // -1.0 dBFS

    private var spinLock = os_unfair_lock_s()
    private var modeSpinLock = os_unfair_lock_s()
    private var telemetrySpinLock = os_unfair_lock_s()
    private var currentMode: LateNightDRCMode = .off
    private var cachedModeFast: LateNightDRCMode = .off
    private var configuredSampleRate: Double = 0.0

    // Pre-allocated 64-sample stereo look-ahead buffer (allocated once in init)
    private var delayL: [Double]
    private var delayR: [Double]
    private var delayWriteIndex: Int = 0

    // 2-stage ITU-R BS.1770 K-weighting sidechain filters
    private var kShelfStage = KWeightBiquad()
    private var kHighPassStage = KWeightBiquad()

    // Dual-envelope sidechain state
    private var envFastK: Double = 0.0
    private var envSlowK: Double = 0.0
    private var envRawFloor: Double = 0.0
    private var currentProgramGainDB: Double = 0.0
    private var limiterGainLin: Double = 1.0
    private var lastTotalGainLin: Double = 1.0
    private var lastSlowLUFS: Double = -70.0

    // Precomputed per-sample ballistic coefficients
    private var coeffFastAttack: Double = 0.999
    private var coeffFastRelease: Double = 0.9995
    private var coeffSlowAttack: Double = 0.9998
    private var coeffSlowRelease: Double = 0.9999
    private var coeffRawAttack: Double = 0.995
    private var coeffRawRelease: Double = 0.9995
    private var coeffGainDown: Double = 0.995
    private var coeffGainUp: Double = 0.9999
    private var coeffLimAttack: Double = 0.90
    private var coeffLimRelease: Double = 0.9995

    // Telemetry snapshots (protected by lightweight telemetrySpinLock so UI never contends with audio spinLock)
    private var telemetryGainDB: Double = 0.0
    private var telemetryLUFS: Double = -70.0

    public init() {
        self.delayL = [Double](repeating: 0.0, count: Self.lookAheadSamples)
        self.delayR = [Double](repeating: 0.0, count: Self.lookAheadSamples)
    }

    @inline(__always)
    private func publishTelemetry(gainDB: Double, shortTermLUFS: Double) {
        os_unfair_lock_lock(&telemetrySpinLock)
        telemetryGainDB = gainDB
        telemetryLUFS = shortTermLUFS
        os_unfair_lock_unlock(&telemetrySpinLock)
    }

    public func setMode(_ mode: LateNightDRCMode) {
        var didReset = false
        os_unfair_lock_lock(&spinLock)
        if currentMode != mode {
            let wasOff = (currentMode == .off)
            currentMode = mode
            os_unfair_lock_lock(&modeSpinLock)
            cachedModeFast = mode
            os_unfair_lock_unlock(&modeSpinLock)
            if mode == .off || wasOff {
                resetStateLocked()
                didReset = true
            }
        }
        os_unfair_lock_unlock(&spinLock)
        if didReset {
            publishTelemetry(gainDB: 0.0, shortTermLUFS: -70.0)
        }
    }

    public var mode: LateNightDRCMode {
        os_unfair_lock_lock(&modeSpinLock)
        let m = cachedModeFast
        os_unfair_lock_unlock(&modeSpinLock)
        return m
    }

    public func resetState() {
        os_unfair_lock_lock(&spinLock)
        resetStateLocked()
        os_unfair_lock_unlock(&spinLock)
        publishTelemetry(gainDB: 0.0, shortTermLUFS: -70.0)
    }

    public var activeSampleRateHz: Double {
        os_unfair_lock_lock(&spinLock)
        let sr = configuredSampleRate
        os_unfair_lock_unlock(&spinLock)
        return sr
    }

    public func telemetrySnapshot() -> (gainDB: Double, shortTermLUFS: Double) {
        os_unfair_lock_lock(&telemetrySpinLock)
        let g = telemetryGainDB
        let l = telemetryLUFS
        os_unfair_lock_unlock(&telemetrySpinLock)
        return (g, l)
    }

    private func resetStateLocked() {
        for i in 0..<Self.lookAheadSamples {
            delayL[i] = 0.0
            delayR[i] = 0.0
        }
        delayWriteIndex = 0
        kShelfStage.resetState()
        kHighPassStage.resetState()
        envFastK = 0.0
        envSlowK = 0.0
        envRawFloor = 0.0
        currentProgramGainDB = 0.0
        limiterGainLin = 1.0
        lastTotalGainLin = 1.0
        lastSlowLUFS = -70.0
    }

    private func ensureSampleRateConfiguredLocked(_ sampleRate: Double) {
        guard sampleRate > 8000.0, abs(sampleRate - configuredSampleRate) > 0.5 else { return }
        configuredSampleRate = sampleRate

        kShelfStage = Self.makeHighShelfBiquad(
            sampleRate: sampleRate,
            frequencyHz: 1681.974450955533,
            gainDB: 3.999843853973347,
            q: 0.7071752369554196
        )
        kHighPassStage = Self.makeHighPassBiquad(
            sampleRate: sampleRate,
            frequencyHz: 38.13547087602444,
            q: 0.5003270373238773
        )

        coeffFastAttack = exp(-1.0 / (0.120 * sampleRate))
        coeffFastRelease = exp(-1.0 / (0.400 * sampleRate))
        coeffSlowAttack = exp(-1.0 / (0.850 * sampleRate))
        coeffSlowRelease = exp(-1.0 / (1.800 * sampleRate))
        coeffRawAttack = exp(-1.0 / (0.025 * sampleRate))
        coeffRawRelease = exp(-1.0 / (0.300 * sampleRate))

        coeffGainDown = exp(-1.0 / (0.012 * sampleRate))
        coeffGainUp = exp(-1.0 / (0.550 * sampleRate))

        let lookAheadSec = max(0.0003, Double(Self.lookAheadSamples) / sampleRate)
        coeffLimAttack = exp(-3.5 / (lookAheadSec * sampleRate))
        coeffLimRelease = exp(-1.0 / (0.120 * sampleRate))

        resetStateLocked()
    }

    private static func makeHighShelfBiquad(
        sampleRate: Double,
        frequencyHz: Double,
        gainDB: Double,
        q: Double
    ) -> KWeightBiquad {
        let nyquist = sampleRate * 0.495
        let f0 = min(max(20.0, frequencyHz), nyquist)
        let aAmp = pow(10.0, gainDB / 40.0)
        let w0 = 2.0 * Double.pi * f0 / sampleRate
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let alpha = sinW0 / (2.0 * max(0.1, q))
        let twoSqrtAAlpha = 2.0 * sqrt(aAmp) * alpha

        let b0 = aAmp * ((aAmp + 1.0) + (aAmp - 1.0) * cosW0 + twoSqrtAAlpha)
        let b1 = -2.0 * aAmp * ((aAmp - 1.0) + (aAmp + 1.0) * cosW0)
        let b2 = aAmp * ((aAmp + 1.0) + (aAmp - 1.0) * cosW0 - twoSqrtAAlpha)
        let a0 = (aAmp + 1.0) - (aAmp - 1.0) * cosW0 + twoSqrtAAlpha
        let a1 = 2.0 * ((aAmp - 1.0) - (aAmp + 1.0) * cosW0)
        let a2 = (aAmp + 1.0) - (aAmp - 1.0) * cosW0 - twoSqrtAAlpha
        let invA0 = 1.0 / a0

        return KWeightBiquad(
            b0: b0 * invA0,
            b1: b1 * invA0,
            b2: b2 * invA0,
            a1: a1 * invA0,
            a2: a2 * invA0
        )
    }

    private static func makeHighPassBiquad(
        sampleRate: Double,
        frequencyHz: Double,
        q: Double
    ) -> KWeightBiquad {
        let nyquist = sampleRate * 0.495
        let f0 = min(max(10.0, frequencyHz), nyquist)
        let w0 = 2.0 * Double.pi * f0 / sampleRate
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let alpha = sinW0 / (2.0 * max(0.1, q))

        let b0 = (1.0 + cosW0) * 0.5
        let b1 = -(1.0 + cosW0)
        let b2 = (1.0 + cosW0) * 0.5
        let a0 = 1.0 + alpha
        let a1 = -2.0 * cosW0
        let a2 = 1.0 - alpha
        let invA0 = 1.0 / a0

        return KWeightBiquad(
            b0: b0 * invA0,
            b1: b1 * invA0,
            b2: b2 * invA0,
            a1: a1 * invA0,
            a2: a2 * invA0
        )
    }

    @inline(__always)
    private static func computeTargetGainDB(
        mode: LateNightDRCMode,
        slowLUFS: Double,
        fastLUFS: Double,
        rawFloorDB: Double
    ) -> Double {
        let gateWeight: Double
        if rawFloorDB <= -63.0 {
            gateWeight = 0.0
        } else if rawFloorDB >= -55.0 {
            gateWeight = 1.0
        } else {
            let u = (rawFloorDB + 63.0) / 8.0
            gateWeight = u * u * (3.0 - 2.0 * u)
        }

        let maxBoostDB: Double
        let quietStartLUFS: Double
        let quietFullLUFS: Double
        let compThresholdLUFS: Double
        let compSlope: Double
        let kneeWidthDB: Double = 6.0

        switch mode {
        case .off:
            return 0.0
        case .gentle:
            maxBoostDB = 6.0
            quietStartLUFS = -25.0
            quietFullLUFS = -46.0
            compThresholdLUFS = -16.0
            compSlope = 1.0 - (1.0 / 1.8)
        case .concert:
            maxBoostDB = 9.5
            quietStartLUFS = -23.0
            quietFullLUFS = -46.0
            compThresholdLUFS = -18.0
            compSlope = 1.0 - (1.0 / 2.5)
        }

        var boostDB = 0.0
        if gateWeight > 0.0 && slowLUFS < quietStartLUFS {
            let depth = min(1.0, max(0.0, (quietStartLUFS - slowLUFS) / (quietStartLUFS - quietFullLUFS)))
            let curved = depth * (2.0 - depth)
            boostDB = maxBoostDB * curved * gateWeight
        }

        let activeLUFS = max(slowLUFS, fastLUFS)
        let overDB = activeLUFS - compThresholdLUFS
        var compDB = 0.0
        let halfKnee = kneeWidthDB * 0.5
        if overDB > -halfKnee {
            if overDB < halfKnee {
                let x = overDB + halfKnee
                compDB = -compSlope * (x * x) / (2.0 * kneeWidthDB)
            } else {
                compDB = -compSlope * overDB
            }
        }

        return boostDB + compDB
    }

    @inline(__always)
    private func processSamplePairLocked(inL: Double, inR: Double) -> (Double, Double) {
        var kL = inL.isFinite ? inL : 0.0
        var kR = inR.isFinite ? inR : 0.0
        let safeInL = kL
        let safeInR = kR

        let rawPower = 0.5 * (safeInL * safeInL + safeInR * safeInR)
        if rawPower > envRawFloor {
            envRawFloor = coeffRawAttack * envRawFloor + (1.0 - coeffRawAttack) * rawPower
        } else {
            envRawFloor = coeffRawRelease * envRawFloor + (1.0 - coeffRawRelease) * rawPower
        }

        kShelfStage.processStereo(left: &kL, right: &kR)
        kHighPassStage.processStereo(left: &kL, right: &kR)

        let kPower = 0.5 * (kL * kL + kR * kR)
        if kPower > envFastK {
            envFastK = coeffFastAttack * envFastK + (1.0 - coeffFastAttack) * kPower
        } else {
            envFastK = coeffFastRelease * envFastK + (1.0 - coeffFastRelease) * kPower
        }

        if kPower > envSlowK {
            envSlowK = coeffSlowAttack * envSlowK + (1.0 - coeffSlowAttack) * kPower
        } else {
            envSlowK = coeffSlowRelease * envSlowK + (1.0 - coeffSlowRelease) * kPower
        }

        let slowLUFS = -0.691 + 10.0 * log10(max(1e-14, envSlowK))
        let fastLUFS = -0.691 + 10.0 * log10(max(1e-14, envFastK))
        let rawFloorDB = 10.0 * log10(max(1e-14, envRawFloor))

        let targetDB = Self.computeTargetGainDB(
            mode: currentMode,
            slowLUFS: slowLUFS,
            fastLUFS: fastLUFS,
            rawFloorDB: rawFloorDB
        )

        if targetDB < currentProgramGainDB {
            currentProgramGainDB = coeffGainDown * currentProgramGainDB + (1.0 - coeffGainDown) * targetDB
        } else {
            currentProgramGainDB = coeffGainUp * currentProgramGainDB + (1.0 - coeffGainUp) * targetDB
        }

        let programGainLin = pow(10.0, currentProgramGainDB / 20.0)
        let incomingPeakAfterGain = max(abs(safeInL), abs(safeInR)) * programGainLin
        let neededLim = incomingPeakAfterGain > Self.ceilingLinear
            ? (Self.ceilingLinear / incomingPeakAfterGain)
            : 1.0

        if neededLim < limiterGainLin {
            limiterGainLin = coeffLimAttack * limiterGainLin + (1.0 - coeffLimAttack) * neededLim
        } else {
            limiterGainLin = coeffLimRelease * limiterGainLin + (1.0 - coeffLimRelease) * neededLim
        }

        let delayedL = delayL[delayWriteIndex]
        let delayedR = delayR[delayWriteIndex]
        delayL[delayWriteIndex] = safeInL
        delayR[delayWriteIndex] = safeInR
        delayWriteIndex += 1
        if delayWriteIndex >= Self.lookAheadSamples {
            delayWriteIndex = 0
        }

        let totalGain = programGainLin * limiterGainLin
        var outL = delayedL * totalGain
        var outR = delayedR * totalGain

        if outL > Self.ceilingLinear { outL = Self.ceilingLinear }
        else if outL < -Self.ceilingLinear { outL = -Self.ceilingLinear }
        if outR > Self.ceilingLinear { outR = Self.ceilingLinear }
        else if outR < -Self.ceilingLinear { outR = -Self.ceilingLinear }

        lastTotalGainLin = totalGain
        lastSlowLUFS = slowLUFS

        return (outL, outR)
    }

    @inline(__always)
    private func processSamplePairFloat32Locked(inL: Float, inR: Float) -> (Float, Float) {
        var kL = inL.isFinite ? Double(inL) : 0.0
        var kR = inR.isFinite ? Double(inR) : 0.0
        let safeInL = kL
        let safeInR = kR

        let rawPower = 0.5 * (safeInL * safeInL + safeInR * safeInR)
        if rawPower > envRawFloor {
            envRawFloor = coeffRawAttack * envRawFloor + (1.0 - coeffRawAttack) * rawPower
        } else {
            envRawFloor = coeffRawRelease * envRawFloor + (1.0 - coeffRawRelease) * rawPower
        }

        kShelfStage.processStereo(left: &kL, right: &kR)
        kHighPassStage.processStereo(left: &kL, right: &kR)

        let kPower = 0.5 * (kL * kL + kR * kR)
        if kPower > envFastK {
            envFastK = coeffFastAttack * envFastK + (1.0 - coeffFastAttack) * kPower
        } else {
            envFastK = coeffFastRelease * envFastK + (1.0 - coeffFastRelease) * kPower
        }

        if kPower > envSlowK {
            envSlowK = coeffSlowAttack * envSlowK + (1.0 - coeffSlowAttack) * kPower
        } else {
            envSlowK = coeffSlowRelease * envSlowK + (1.0 - coeffSlowRelease) * kPower
        }

        let slowLUFS = Double(-0.691 + 10.0 * log10f(Float(max(1e-14, envSlowK))))
        let fastLUFS = Double(-0.691 + 10.0 * log10f(Float(max(1e-14, envFastK))))
        let rawFloorDB = Double(10.0 * log10f(Float(max(1e-14, envRawFloor))))

        let targetDB = Self.computeTargetGainDB(
            mode: currentMode,
            slowLUFS: slowLUFS,
            fastLUFS: fastLUFS,
            rawFloorDB: rawFloorDB
        )

        if targetDB < currentProgramGainDB {
            currentProgramGainDB = coeffGainDown * currentProgramGainDB + (1.0 - coeffGainDown) * targetDB
        } else {
            currentProgramGainDB = coeffGainUp * currentProgramGainDB + (1.0 - coeffGainUp) * targetDB
        }

        let programGainLin = Double(expf(Float(currentProgramGainDB) * 0.11512925464970229))
        let incomingPeakAfterGain = max(abs(safeInL), abs(safeInR)) * programGainLin
        let neededLim = incomingPeakAfterGain > Self.ceilingLinear
            ? (Self.ceilingLinear / incomingPeakAfterGain)
            : 1.0

        if neededLim < limiterGainLin {
            limiterGainLin = coeffLimAttack * limiterGainLin + (1.0 - coeffLimAttack) * neededLim
        } else {
            limiterGainLin = coeffLimRelease * limiterGainLin + (1.0 - coeffLimRelease) * neededLim
        }

        let delayedL = delayL[delayWriteIndex]
        let delayedR = delayR[delayWriteIndex]
        delayL[delayWriteIndex] = safeInL
        delayR[delayWriteIndex] = safeInR
        delayWriteIndex += 1
        if delayWriteIndex >= Self.lookAheadSamples {
            delayWriteIndex = 0
        }

        let totalGain = programGainLin * limiterGainLin
        var outL = delayedL * totalGain
        var outR = delayedR * totalGain

        if outL > Self.ceilingLinear { outL = Self.ceilingLinear }
        else if outL < -Self.ceilingLinear { outL = -Self.ceilingLinear }
        if outR > Self.ceilingLinear { outR = Self.ceilingLinear }
        else if outR < -Self.ceilingLinear { outR = -Self.ceilingLinear }

        lastTotalGainLin = totalGain
        lastSlowLUFS = slowLUFS

        return (Float(outL), Float(outR))
    }

    @inline(__always)
    public func processPlanarDouble(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frameCount: Int,
        sampleRate: Double
    ) {
        guard frameCount > 0 else { return }
        os_unfair_lock_lock(&spinLock)
        guard currentMode != .off else {
            os_unfair_lock_unlock(&spinLock)
            return
        }
        ensureSampleRateConfiguredLocked(sampleRate)

        for i in 0..<frameCount {
            let (outL, outR) = processSamplePairLocked(inL: left[i], inR: right[i])
            left[i] = outL
            right[i] = outR
        }
        let finalGainDB = 20.0 * log10(max(1e-6, lastTotalGainLin))
        let finalLUFS = max(-70.0, min(0.0, lastSlowLUFS))
        os_unfair_lock_unlock(&spinLock)

        publishTelemetry(gainDB: finalGainDB, shortTermLUFS: finalLUFS)
    }

    @inline(__always)
    public func processPlanarFloat32(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        frameCount: Int,
        sampleRate: Double
    ) {
        guard frameCount > 0 else { return }
        os_unfair_lock_lock(&spinLock)
        guard currentMode != .off else {
            os_unfair_lock_unlock(&spinLock)
            return
        }
        ensureSampleRateConfiguredLocked(sampleRate)

        for i in 0..<frameCount {
            let (outL, outR) = processSamplePairFloat32Locked(inL: left[i], inR: right[i])
            left[i] = outL
            right[i] = outR
        }
        let finalGainDB = Double(20.0 * log10f(Float(max(1e-6, lastTotalGainLin))))
        let finalLUFS = max(-70.0, min(0.0, lastSlowLUFS))
        os_unfair_lock_unlock(&spinLock)

        publishTelemetry(gainDB: finalGainDB, shortTermLUFS: finalLUFS)
    }

    @inline(__always)
    public func processStereoFloatPair(
        left: inout Float,
        right: inout Float,
        sampleRate: Double
    ) {
        os_unfair_lock_lock(&spinLock)
        guard currentMode != .off else {
            os_unfair_lock_unlock(&spinLock)
            return
        }
        ensureSampleRateConfiguredLocked(sampleRate)

        let (outL, outR) = processSamplePairFloat32Locked(inL: left, inR: right)
        left = outL
        right = outR
        let finalGainDB = Double(20.0 * log10f(Float(max(1e-6, lastTotalGainLin))))
        let finalLUFS = max(-70.0, min(0.0, lastSlowLUFS))
        os_unfair_lock_unlock(&spinLock)

        publishTelemetry(gainDB: finalGainDB, shortTermLUFS: finalLUFS)
    }
}
