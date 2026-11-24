//
//  MasteringRestorationProcessor.swift
//  AppleMusicRemoteMac
//
//  Real-Time 64-Bit Mastering Pre-DSP Processor:
//  State Management, RBJ Filter Synthesis & Block Processing Entry Points.
//

import Foundation
import os.lock

public final class MasteringRestorationProcessor: @unchecked Sendable {
    internal struct BiquadMono {
        var b0: Double = 1.0
        var b1: Double = 0.0
        var b2: Double = 0.0
        var a1: Double = 0.0
        var a2: Double = 0.0
        var z1: Double = 0.0
        var z2: Double = 0.0

        @inline(__always)
        mutating func resetState() {
            z1 = 0.0
            z2 = 0.0
        }

        @inline(__always)
        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }
    }

    internal struct BiquadStereo {
        var b0: Double = 0.0
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
        mutating func processStereo(inL: Double, inR: Double) -> (Double, Double) {
            let outL = b0 * inL + z1L
            z1L = b1 * inL - a1 * outL + z2L
            z2L = b2 * inL - a2 * outL

            let outR = b0 * inR + z1R
            z1R = b1 * inR - a1 * outR + z2R
            z2R = b2 * inR - a2 * outR
            return (outL, outR)
        }
    }

    @usableFromInline
    internal struct ChannelDeClipTracker {
        var adaptiveCeiling: Double = 0.98
        var inClipRun: Bool = false
        var runOverflowed: Bool = false
        var runSign: Double = 1.0
        var runStartCursor: Int64 = 0
        var runLength: Int = 0
        var runMaxAbs: Double = 0.0

        @inline(__always)
        mutating func reset() {
            adaptiveCeiling = 0.98
            inClipRun = false
            runOverflowed = false
            runSign = 1.0
            runStartCursor = 0
            runLength = 0
            runMaxAbs = 0.0
        }
    }

    internal static let ringCapacity: Int = 512
    internal static let ringMask: Int = 511
    internal static let lookAheadSamples: Int = 256

    internal var spinLock = os_unfair_lock_s()
    internal var fastModeLock = os_unfair_lock_s()
    internal var telemetryLock = os_unfair_lock_s()

    internal var currentDeClipMode: MasteringDeClipMode = .off
    internal var currentDeEsserMode: MasteringDeEsserMode = .off
    internal var cachedDeClipFast: MasteringDeClipMode = .off
    internal var cachedDeEsserFast: MasteringDeEsserMode = .off
    internal var autoCleanMasterHint: Bool = false

    internal var configuredSampleRate: Double = 0.0

    // Stage 0a: Pre-allocated 512-frame circular ring buffer for 256-sample look-ahead De-Clipper
    internal var ringL: [Double]
    internal var ringR: [Double]
    internal var sampleCounter: Int64 = 0
    internal var trackerL = ChannelDeClipTracker()
    internal var trackerR = ChannelDeClipTracker()
    internal var coeffCeilingDecay: Double = 0.99999
    internal var coeffPeakMeterDecay: Double = 0.99995
    internal var coeffPadSmooth: Double = 0.999
    internal var currentOutPadGain: Double = 0.0
    internal var maxClipRunSamples: Int = 48
    internal var liveRestoredPeakDB: Double = 0.0
    internal var totalReconstructedClips: UInt64 = 0

    // Stage 0b: Weiss-style Relative Sibilance De-Esser states
    internal var scBodyHPF = BiquadStereo()
    internal var scSibBPF = BiquadMono()
    internal var audioSibBPF = BiquadStereo()
    internal var envBodyPower: Double = 0.0
    internal var envSibPower: Double = 0.0
    internal var envRawPower: Double = 0.0
    internal var currentDeEssCutDB: Double = 0.0
    internal var coeffScEnvAttack: Double = 0.96
    internal var coeffScEnvRelease: Double = 0.998
    internal var coeffDeEssAttack: Double = 0.97
    internal var coeffDeEssRelease: Double = 0.999
    internal var coeffMeterDeEssDecay: Double = 0.9999
    internal var liveDeEssMeterDB: Double = 0.0

    internal var telemetry = MasteringRestorationTelemetrySnapshot()

    public init() {
        self.ringL = [Double](repeating: 0.0, count: Self.ringCapacity)
        self.ringR = [Double](repeating: 0.0, count: Self.ringCapacity)
    }

    public var isAnyEnabled: Bool {
        os_unfair_lock_lock(&fastModeLock)
        let active = (cachedDeClipFast != .off) || (cachedDeEsserFast != .off)
        os_unfair_lock_unlock(&fastModeLock)
        return active
    }

    public var deClipMode: MasteringDeClipMode {
        os_unfair_lock_lock(&fastModeLock)
        let m = cachedDeClipFast
        os_unfair_lock_unlock(&fastModeLock)
        return m
    }

    public var deEsserMode: MasteringDeEsserMode {
        os_unfair_lock_lock(&fastModeLock)
        let m = cachedDeEsserFast
        os_unfair_lock_unlock(&fastModeLock)
        return m
    }

    public func configure(
        deClipMode: MasteringDeClipMode,
        deEsserMode: MasteringDeEsserMode,
        cleanMasterAutoBypass: Bool? = nil
    ) {
        var shouldClearTelemetry = false
        os_unfair_lock_lock(&spinLock)
        let deClipChanged = (currentDeClipMode != deClipMode)
        let deEsserChanged = (currentDeEsserMode != deEsserMode)
        if let cleanMasterAutoBypass {
            autoCleanMasterHint = cleanMasterAutoBypass
        }
        if deClipChanged || deEsserChanged {
            let prevDeClipWasOff = (currentDeClipMode == .off)
            let prevDeEsserWasOff = (currentDeEsserMode == .off)
            currentDeClipMode = deClipMode
            currentDeEsserMode = deEsserMode

            os_unfair_lock_lock(&fastModeLock)
            cachedDeClipFast = deClipMode
            cachedDeEsserFast = deEsserMode
            os_unfair_lock_unlock(&fastModeLock)

            if deClipMode == .off || prevDeClipWasOff {
                resetDeClipLocked()
            }
            if deEsserChanged {
                if configuredSampleRate > 8000.0 {
                    reconfigureDeEsserFiltersLocked(sampleRate: configuredSampleRate)
                }
                if deEsserMode == .off || prevDeEsserWasOff {
                    resetDeEsserStateLocked()
                }
            }
            if deClipMode == .off && deEsserMode == .off {
                shouldClearTelemetry = true
            }
        }
        let snap = MasteringRestorationTelemetrySnapshot(
            restoredPeakDB: currentDeClipMode == .off ? 0.0 : liveRestoredPeakDB,
            reconstructedClipsCount: currentDeClipMode == .off ? 0 : totalReconstructedClips,
            deEsserGainReductionDB: currentDeEsserMode == .off ? 0.0 : liveDeEssMeterDB,
            autoBypassedCleanMaster: (currentDeClipMode == .auto) && autoCleanMasterHint
        )
        os_unfair_lock_unlock(&spinLock)

        os_unfair_lock_lock(&telemetryLock)
        telemetry = shouldClearTelemetry ? MasteringRestorationTelemetrySnapshot() : snap
        os_unfair_lock_unlock(&telemetryLock)
    }

    public func setCleanMasterAutoBypass(_ isCleanMaster: Bool) {
        os_unfair_lock_lock(&spinLock)
        autoCleanMasterHint = isCleanMaster
        let isBypassed = (currentDeClipMode == .auto) && isCleanMaster
        os_unfair_lock_unlock(&spinLock)

        os_unfair_lock_lock(&telemetryLock)
        telemetry.autoBypassedCleanMaster = isBypassed
        os_unfair_lock_unlock(&telemetryLock)
    }

    public func resetState(resetClipCounters: Bool = false) {
        os_unfair_lock_lock(&spinLock)
        resetDeClipLocked(resetClipCounters: resetClipCounters)
        resetDeEsserStateLocked()
        let snap = MasteringRestorationTelemetrySnapshot(
            restoredPeakDB: 0.0,
            reconstructedClipsCount: totalReconstructedClips,
            deEsserGainReductionDB: 0.0,
            autoBypassedCleanMaster: (currentDeClipMode == .auto) && autoCleanMasterHint
        )
        os_unfair_lock_unlock(&spinLock)

        os_unfair_lock_lock(&telemetryLock)
        telemetry = snap
        os_unfair_lock_unlock(&telemetryLock)
    }

    public func telemetrySnapshot() -> MasteringRestorationTelemetrySnapshot {
        os_unfair_lock_lock(&telemetryLock)
        let s = telemetry
        os_unfair_lock_unlock(&telemetryLock)
        return s
    }

    // MARK: - Internal Configuration & Filter Synthesis

    internal func resetDeClipLocked(resetClipCounters: Bool = false) {
        for i in 0..<Self.ringCapacity {
            ringL[i] = 0.0
            ringR[i] = 0.0
        }
        sampleCounter = 0
        trackerL.reset()
        trackerR.reset()
        currentOutPadGain = 0.0
        liveRestoredPeakDB = 0.0
        if resetClipCounters {
            totalReconstructedClips = 0
        }
    }

    internal func resetDeEsserStateLocked() {
        scBodyHPF.resetState()
        scSibBPF.resetState()
        audioSibBPF.resetState()
        envBodyPower = 0.0
        envSibPower = 0.0
        envRawPower = 0.0
        currentDeEssCutDB = 0.0
        liveDeEssMeterDB = 0.0
    }

    internal func ensureSampleRateConfiguredLocked(_ sampleRate: Double) {
        guard sampleRate > 8000.0, abs(sampleRate - configuredSampleRate) > 0.5 else { return }
        configuredSampleRate = sampleRate

        maxClipRunSamples = min(192, max(36, Int((sampleRate * 0.00105).rounded())))
        coeffCeilingDecay = exp(-1.0 / (2.50 * sampleRate))
        coeffPeakMeterDecay = exp(-1.0 / (1.80 * sampleRate))
        coeffPadSmooth = exp(-1.0 / (0.030 * sampleRate))
        coeffMeterDeEssDecay = exp(-1.0 / (0.85 * sampleRate))

        coeffScEnvAttack = exp(-1.0 / (0.0006 * sampleRate))
        coeffScEnvRelease = exp(-1.0 / (0.0140 * sampleRate))

        coeffDeEssAttack = exp(-1.0 / (0.0008 * sampleRate))
        coeffDeEssRelease = exp(-1.0 / (0.0280 * sampleRate))

        reconfigureDeEsserFiltersLocked(sampleRate: sampleRate)
        resetDeClipLocked()
        resetDeEsserStateLocked()
    }

    internal func reconfigureDeEsserFiltersLocked(sampleRate: Double) {
        guard sampleRate > 8000.0 else { return }
        scBodyHPF = Self.makeHighPassStereo(sampleRate: sampleRate, frequencyHz: 180.0, q: 0.70710678)

        let centerHz: Double
        let audioQ: Double
        let scCenterHz: Double
        let scQ: Double
        switch currentDeEsserMode {
        case .off, .gentle:
            centerHz = 7000.0
            audioQ = 1.65
            scCenterHz = 6850.0
            scQ = 1.55
        case .vocal:
            centerHz = 6500.0
            audioQ = 1.30
            scCenterHz = 6350.0
            scQ = 1.25
        }

        scSibBPF = Self.makeZeroPeakBandPassMono(sampleRate: sampleRate, frequencyHz: scCenterHz, q: scQ)
        audioSibBPF = Self.makeZeroPeakBandPassStereo(sampleRate: sampleRate, frequencyHz: centerHz, q: audioQ)
    }

    internal static func makeHighPassStereo(sampleRate: Double, frequencyHz: Double, q: Double) -> BiquadStereo {
        let nyquist = sampleRate * 0.49
        let f0 = min(max(20.0, frequencyHz), nyquist)
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

        return BiquadStereo(
            b0: b0 * invA0,
            b1: b1 * invA0,
            b2: b2 * invA0,
            a1: a1 * invA0,
            a2: a2 * invA0
        )
    }

    internal static func makeZeroPeakBandPassMono(sampleRate: Double, frequencyHz: Double, q: Double) -> BiquadMono {
        let nyquist = sampleRate * 0.46
        let f0 = min(max(500.0, frequencyHz), nyquist)
        let w0 = 2.0 * Double.pi * f0 / sampleRate
        let cosW0 = cos(w0)
        let sinW0 = sin(w0)
        let alpha = sinW0 / (2.0 * max(0.15, q))
        let a0 = 1.0 + alpha
        let invA0 = 1.0 / a0

        return BiquadMono(
            b0: alpha * invA0,
            b1: 0.0,
            b2: -alpha * invA0,
            a1: (-2.0 * cosW0) * invA0,
            a2: (1.0 - alpha) * invA0
        )
    }

    internal static func makeZeroPeakBandPassStereo(sampleRate: Double, frequencyHz: Double, q: Double) -> BiquadStereo {
        let mono = makeZeroPeakBandPassMono(sampleRate: sampleRate, frequencyHz: frequencyHz, q: q)
        return BiquadStereo(
            b0: mono.b0,
            b1: mono.b1,
            b2: mono.b2,
            a1: mono.a1,
            a2: mono.a2
        )
    }

    // MARK: - Block Entry Points

    /// Processes planar `Double` buffers (`applyOutputHeadroom = false` in Exclusive Hog Mode where `HeadroomISPProcessor` follows).
    /// Returns the effective `MasteringDeClipMode` applied under `spinLock` for TOCTOU-free headroom capping.
    @discardableResult
    public func processPlanarDouble(
        left: UnsafeMutablePointer<Double>,
        right: UnsafeMutablePointer<Double>,
        frameCount: Int,
        sampleRate: Double,
        applyOutputHeadroom: Bool = false
    ) -> MasteringDeClipMode {
        guard frameCount > 0 else { return .off }
        os_unfair_lock_lock(&spinLock)
        let dcMode = currentDeClipMode
        let deMode = currentDeEsserMode
        guard dcMode != .off || deMode != .off else {
            os_unfair_lock_unlock(&spinLock)
            return .off
        }
        ensureSampleRateConfiguredLocked(sampleRate)
        let autoBypass = (dcMode == .auto) && autoCleanMasterHint
        let effectiveAppliedDeClip: MasteringDeClipMode = autoBypass ? .off : dcMode
        let targetOutPad = applyOutputHeadroom ? Self.outputHeadroomLinear(for: dcMode, autoBypass: autoBypass) : 1.0
        if currentOutPadGain <= 0.0 {
            currentOutPadGain = targetOutPad
        }
        let padSmooth = coeffPadSmooth
        let maxRun = maxClipRunSamples
        let ceilDecay = coeffCeilingDecay

        for i in 0..<frameCount {
            var sL = left[i].isFinite ? left[i] : 0.0
            var sR = right[i].isFinite ? right[i] : 0.0

            if dcMode != .off {
                liveRestoredPeakDB *= coeffPeakMeterDecay
                let idx = sampleCounter
                sampleCounter &+= 1
                sL = Self.inspectAndRepairChannel(
                    ring: &ringL,
                    tracker: &trackerL,
                    writeSampleIndex: idx,
                    incomingSample: sL,
                    mode: dcMode,
                    autoBypass: autoBypass,
                    maxRunSamples: maxRun,
                    ceilingDecay: ceilDecay,
                    peakRestoredDB: &liveRestoredPeakDB,
                    clipsCount: &totalReconstructedClips
                )
                sR = Self.inspectAndRepairChannel(
                    ring: &ringR,
                    tracker: &trackerR,
                    writeSampleIndex: idx,
                    incomingSample: sR,
                    mode: dcMode,
                    autoBypass: autoBypass,
                    maxRunSamples: maxRun,
                    ceilingDecay: ceilDecay,
                    peakRestoredDB: &liveRestoredPeakDB,
                    clipsCount: &totalReconstructedClips
                )
                if applyOutputHeadroom {
                    currentOutPadGain = padSmooth * currentOutPadGain + (1.0 - padSmooth) * targetOutPad
                    sL = Self.softSafetyCeiling(sL * currentOutPadGain)
                    sR = Self.softSafetyCeiling(sR * currentOutPadGain)
                }
            }

            if deMode != .off {
                let (dL, dR) = processDeEsserSamplePairLocked(inL: sL, inR: sR)
                sL = dL
                sR = dR
            }

            left[i] = sL
            right[i] = sR
        }

        let snap = MasteringRestorationTelemetrySnapshot(
            restoredPeakDB: dcMode == .off ? 0.0 : liveRestoredPeakDB,
            reconstructedClipsCount: dcMode == .off ? 0 : totalReconstructedClips,
            deEsserGainReductionDB: deMode == .off ? 0.0 : -liveDeEssMeterDB,
            autoBypassedCleanMaster: autoBypass
        )
        os_unfair_lock_unlock(&spinLock)

        os_unfair_lock_lock(&telemetryLock)
        telemetry = snap
        os_unfair_lock_unlock(&telemetryLock)
        return effectiveAppliedDeClip
    }

    /// Processes planar `Float32` buffers internally in 64-bit `Double` (used for Local Passthrough & BluOS/DLNA streams).
    public func processPlanarFloat32(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        frameCount: Int,
        sampleRate: Double,
        applyOutputHeadroom: Bool = true
    ) {
        guard frameCount > 0 else { return }
        os_unfair_lock_lock(&spinLock)
        let dcMode = currentDeClipMode
        let deMode = currentDeEsserMode
        guard dcMode != .off || deMode != .off else {
            os_unfair_lock_unlock(&spinLock)
            return
        }
        ensureSampleRateConfiguredLocked(sampleRate)
        let autoBypass = (dcMode == .auto) && autoCleanMasterHint
        let targetOutPad = applyOutputHeadroom ? Self.outputHeadroomLinear(for: dcMode, autoBypass: autoBypass) : 1.0
        if currentOutPadGain <= 0.0 {
            currentOutPadGain = targetOutPad
        }
        let padSmooth = coeffPadSmooth
        let maxRun = maxClipRunSamples
        let ceilDecay = coeffCeilingDecay

        for i in 0..<frameCount {
            var sL = left[i].isFinite ? Double(left[i]) : 0.0
            var sR = right[i].isFinite ? Double(right[i]) : 0.0

            if dcMode != .off {
                liveRestoredPeakDB *= coeffPeakMeterDecay
                let idx = sampleCounter
                sampleCounter &+= 1
                sL = Self.inspectAndRepairChannel(
                    ring: &ringL,
                    tracker: &trackerL,
                    writeSampleIndex: idx,
                    incomingSample: sL,
                    mode: dcMode,
                    autoBypass: autoBypass,
                    maxRunSamples: maxRun,
                    ceilingDecay: ceilDecay,
                    peakRestoredDB: &liveRestoredPeakDB,
                    clipsCount: &totalReconstructedClips
                )
                sR = Self.inspectAndRepairChannel(
                    ring: &ringR,
                    tracker: &trackerR,
                    writeSampleIndex: idx,
                    incomingSample: sR,
                    mode: dcMode,
                    autoBypass: autoBypass,
                    maxRunSamples: maxRun,
                    ceilingDecay: ceilDecay,
                    peakRestoredDB: &liveRestoredPeakDB,
                    clipsCount: &totalReconstructedClips
                )
                if applyOutputHeadroom {
                    currentOutPadGain = padSmooth * currentOutPadGain + (1.0 - padSmooth) * targetOutPad
                    sL = Self.softSafetyCeiling(sL * currentOutPadGain)
                    sR = Self.softSafetyCeiling(sR * currentOutPadGain)
                }
            }

            if deMode != .off {
                let (dL, dR) = processDeEsserSamplePairLocked(inL: sL, inR: sR)
                sL = dL
                sR = dR
            }

            left[i] = Float(sL)
            right[i] = Float(sR)
        }

        let snap = MasteringRestorationTelemetrySnapshot(
            restoredPeakDB: dcMode == .off ? 0.0 : liveRestoredPeakDB,
            reconstructedClipsCount: dcMode == .off ? 0 : totalReconstructedClips,
            deEsserGainReductionDB: deMode == .off ? 0.0 : -liveDeEssMeterDB,
            autoBypassedCleanMaster: autoBypass
        )
        os_unfair_lock_unlock(&spinLock)

        os_unfair_lock_lock(&telemetryLock)
        telemetry = snap
        os_unfair_lock_unlock(&telemetryLock)
    }
}
