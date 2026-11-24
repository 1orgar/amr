import Darwin
import Darwin.Mach
import Foundation

/// Утилита перевода потоков модулятора в детерминированный планировщик реального времени ядра XNU
/// (`THREAD_TIME_CONSTRAINT_POLICY`) на производительных P-ядрах Apple Silicon (Firestorm / Avalanche / Everest).
public enum MachRealtimeThreadPolicy {
    /// Переводит текущий поток в класс `THREAD_TIME_CONSTRAINT_POLICY` со строгим соблюдением инварианта XNU
    /// `1 <= computation < constraint <= period` при любых размерах блока и частотах дискретизации,
    /// исключая принудительное разжалование RT-потока планировщиком ядра.
    @discardableResult
    public static func promoteCurrentThread(
        periodMs: Double = 20.0,
        computationMs: Double = 10.0,
        constraintMs: Double = 18.0
    ) -> Bool {
        _ = pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)

        var timebase = mach_timebase_info_data_t(numer: 0, denom: 0)
        mach_timebase_info(&timebase)
        guard timebase.numer > 0 && timebase.denom > 0 else { return false }

        let nsToAbs = Double(timebase.denom) / Double(timebase.numer)
        let safePeriodMs = min(max(periodMs.isFinite ? periodMs : 20.0, 1.0), 50.0)
        let safeConstraintMs = min(max(constraintMs.isFinite ? constraintMs : (safePeriodMs * 0.90), 0.5), safePeriodMs)
        let safeCompMs = min(max(computationMs.isFinite ? computationMs : (safeConstraintMs * 0.60), 0.1), safeConstraintMs * 0.85)

        let periodTicks = max(UInt32(4), UInt32((safePeriodMs * 1_000_000.0 * nsToAbs).rounded()))
        let rawConstraintTicks = UInt32((safeConstraintMs * 1_000_000.0 * nsToAbs).rounded())
        let constraintTicks = min(periodTicks, max(UInt32(3), rawConstraintTicks))
        let rawCompTicks = UInt32((safeCompMs * 1_000_000.0 * nsToAbs).rounded())
        let compTicks = min(constraintTicks - 1, max(UInt32(1), rawCompTicks))

        var policy = thread_time_constraint_policy_data_t(
            period: periodTicks,
            computation: compTicks,
            constraint: constraintTicks,
            preemptible: 1
        )

        let threadPort = mach_thread_self()
        defer { mach_port_deallocate(mach_task_self_, threadPort) }

        let count = mach_msg_type_number_t(
            MemoryLayout<thread_time_constraint_policy_data_t>.size / MemoryLayout<integer_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &policy) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                thread_policy_set(
                    threadPort,
                    thread_policy_flavor_t(THREAD_TIME_CONSTRAINT_POLICY),
                    intPtr,
                    count
                )
            }
        }
        return kr == KERN_SUCCESS
    }

    /// Возвращает поток из `THREAD_TIME_CONSTRAINT_POLICY` в интерактивный `THREAD_STANDARD_POLICY`
    /// (`QOS_CLASS_USER_INTERACTIVE`), чтобы вызовы Metal GPU (`MTLCommandBuffer`) не блокировали Mach RT планировщик.
    @discardableResult
    public static func demoteToInteractiveStandardPolicy() -> Bool {
        let threadPort = mach_thread_self()
        defer { mach_port_deallocate(mach_task_self_, threadPort) }

        var stdPolicy = thread_standard_policy_data_t(no_data: 0)
        let count = mach_msg_type_number_t(
            MemoryLayout<thread_standard_policy_data_t>.size / MemoryLayout<integer_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &stdPolicy) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                thread_policy_set(
                    threadPort,
                    thread_policy_flavor_t(THREAD_STANDARD_POLICY),
                    intPtr,
                    count
                )
            }
        }
        _ = pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
        return kr == KERN_SUCCESS
    }
}

/// Двухпоточный параллельный исполнитель 7-порядкового дельта-сигма модулятора (`LeftSDMWorker` + `RightSDMWorker`).
///
/// Правый канал исполняется на выделенном постоянном `pthread_t` с `THREAD_TIME_CONSTRAINT_POLICY`,
/// а левый канал исполняется параллельно на вызывающем RT-потоке конвейера, обеспечивая 2-кратное
/// ускорение на P-ядрах Apple Silicon при нулевых аллокациях в куче.
public final class ParallelStereoSDMExecutor: @unchecked Sendable {
    public var modulatorL: TrellisViterbiModulator
    public var modulatorR: TrellisViterbiModulator

    private var mutex = pthread_mutex_t()
    private var workAvailableCond = pthread_cond_t()
    private var workDoneCond = pthread_cond_t()
    private var rightThread: pthread_t?
    private var isShuttingDown: Bool = false
    private var hasPendingRightJob: Bool = false

    private var rightInputPtr: UnsafePointer<Double>?
    private var rightSampleCount: Int = 0
    private var rightLookahead: Double = 0.0
    private var rightOutputPtr: UnsafeMutablePointer<UInt8>?

    private let scratchL: UnsafeMutableRawPointer
    private let scratchR: UnsafeMutableRawPointer

    private var callerPromoted: Bool = false
    public private(set) var lastBlockComputeTimeMs: Double = 0.0
    public private(set) var maxObservedIntegratorPeak: Double = 0.0

    private static func allocateLockedScratch() -> UnsafeMutableRawPointer {
        let bytes = TrellisViterbiModulator.steadyScratchByteCount
        var ptr: UnsafeMutableRawPointer?
        let rc = posix_memalign(&ptr, 64, bytes)
        guard rc == 0, let validPtr = ptr else {
            fatalError("posix_memalign(64, \(bytes)) failed for Trellis scratch (rc=\(rc))")
        }
        memset(validPtr, 0, bytes)
        _ = mlock(validPtr, bytes)
        return validPtr
    }

    private static func freeLockedScratch(_ ptr: UnsafeMutableRawPointer) {
        let bytes = TrellisViterbiModulator.steadyScratchByteCount
        _ = munlock(ptr, bytes)
        free(ptr)
    }

    public init(
        profile: SDM7Profile = .balanced,
        rate: DSDRateMultiplier = .dsd256,
        grid: BaseClockGrid = .grid44k1,
        trellisOrder: TrellisOrder = .trellis8,
        isiRegularizerEnabled: Bool = true
    ) {
        self.modulatorL = TrellisViterbiModulator(
            profile: profile,
            rate: rate,
            grid: grid,
            trellisOrder: trellisOrder,
            isiRegularizerEnabled: isiRegularizerEnabled,
            channelSeed: 0x9E37_79B9_7F4A_7C15
        )
        self.modulatorR = TrellisViterbiModulator(
            profile: profile,
            rate: rate,
            grid: grid,
            trellisOrder: trellisOrder,
            isiRegularizerEnabled: isiRegularizerEnabled,
            channelSeed: 0xD1B5_4A32_D192_ED03
        )
        self.scratchL = Self.allocateLockedScratch()
        self.scratchR = Self.allocateLockedScratch()

        pthread_mutex_init(&mutex, nil)
        pthread_cond_init(&workAvailableCond, nil)
        pthread_cond_init(&workDoneCond, nil)
        spawnRightWorkerThread()
    }

    deinit {
        shutdown()
        pthread_cond_destroy(&workDoneCond)
        pthread_cond_destroy(&workAvailableCond)
        pthread_mutex_destroy(&mutex)
        Self.freeLockedScratch(scratchL)
        Self.freeLockedScratch(scratchR)
    }

    public func shutdown() {
        pthread_mutex_lock(&mutex)
        if isShuttingDown {
            pthread_mutex_unlock(&mutex)
            return
        }
        isShuttingDown = true
        hasPendingRightJob = false
        pthread_cond_broadcast(&workAvailableCond)
        pthread_mutex_unlock(&mutex)

        if let thread = rightThread {
            pthread_join(thread, nil)
            rightThread = nil
        }
    }

    private func spawnRightWorkerThread() {
        var attr = pthread_attr_t()
        pthread_attr_init(&attr)
        pthread_attr_set_qos_class_np(&attr, QOS_CLASS_USER_INTERACTIVE, 0)

        let unmanagedSelf = Unmanaged.passUnretained(self).toOpaque()
        var thread: pthread_t?
        let rc = pthread_create(
            &thread,
            &attr,
            { rawCtx -> UnsafeMutableRawPointer? in
                let executor = Unmanaged<ParallelStereoSDMExecutor>.fromOpaque(rawCtx).takeUnretainedValue()
                executor.rightWorkerLoop()
                return nil
            },
            unmanagedSelf
        )
        pthread_attr_destroy(&attr)
        if rc == 0 {
            rightThread = thread
        }
    }

    private func rightWorkerLoop() {
        pthread_setname_np("com.amr.dsp.RightSDMWorker")
        _ = MachRealtimeThreadPolicy.promoteCurrentThread(
            periodMs: 20.0,
            computationMs: 12.0,
            constraintMs: 18.5
        )

        while true {
            pthread_mutex_lock(&mutex)
            while !hasPendingRightJob && !isShuttingDown {
                pthread_cond_wait(&workAvailableCond, &mutex)
            }
            if isShuttingDown {
                pthread_mutex_unlock(&mutex)
                break
            }

            let inPtr = rightInputPtr
            let count = rightSampleCount
            let lookahead = rightLookahead
            let outPtr = rightOutputPtr
            pthread_mutex_unlock(&mutex)

            if let inPtr, let outPtr, count > 0 {
                modulatorR.processBlockToDSDBytes(
                    inputSamples: inPtr,
                    sampleCount: count,
                    lookaheadSample: lookahead,
                    dsdOutputBytes: outPtr,
                    scratchRaw: scratchR
                )
            }

            pthread_mutex_lock(&mutex)
            hasPendingRightJob = false
            pthread_cond_signal(&workDoneCond)
            pthread_mutex_unlock(&mutex)
        }
    }

    /// Синхронное обновление конфигурации обоих каналов (с поддержкой бесшовного 5-мс переключения профиля).
    public func updateConfiguration(
        profile: SDM7Profile,
        rate: DSDRateMultiplier,
        grid: BaseClockGrid,
        trellisOrder: TrellisOrder,
        isiRegularizerEnabled: Bool,
        resetStates: Bool = false
    ) {
        pthread_mutex_lock(&mutex)
        while hasPendingRightJob {
            pthread_cond_wait(&workDoneCond, &mutex)
        }
        modulatorL.trellisOrder = trellisOrder
        modulatorR.trellisOrder = trellisOrder
        modulatorL.isiRegularizerEnabled = isiRegularizerEnabled
        modulatorR.isiRegularizerEnabled = isiRegularizerEnabled

        if resetStates {
            modulatorL.reset(profile: profile, rate: rate, grid: grid)
            modulatorR.reset(profile: profile, rate: rate, grid: grid)
        } else {
            modulatorL.transitionToProfile(profile, rate: rate, grid: grid)
            modulatorR.transitionToProfile(profile, rate: rate, grid: grid)
        }
        pthread_mutex_unlock(&mutex)
    }

    /// Параллельно модулирует блок левого и правого каналов `Double` (на частоте DSD) в массивы байтов DSD (`MSB-first`).
    public func processStereoBlock(
        leftSamples: UnsafePointer<Double>,
        rightSamples: UnsafePointer<Double>,
        sampleCount: Int,
        lookaheadL: Double = 0.0,
        lookaheadR: Double = 0.0,
        leftDSDOut: UnsafeMutablePointer<UInt8>,
        rightDSDOut: UnsafeMutablePointer<UInt8>,
        allowCallerTimeConstraint: Bool = true,
        callerAlreadyPromoted: Bool = false
    ) {
        guard sampleCount > 0 else { return }
        if !callerAlreadyPromoted {
            if allowCallerTimeConstraint && !callerPromoted {
                callerPromoted = MachRealtimeThreadPolicy.promoteCurrentThread(
                    periodMs: 20.0,
                    computationMs: 12.0,
                    constraintMs: 18.5
                )
            } else if !allowCallerTimeConstraint && callerPromoted {
                callerPromoted = false
                _ = MachRealtimeThreadPolicy.demoteToInteractiveStandardPolicy()
            }
        }

        let t0 = DispatchTime.now().uptimeNanoseconds

        if rightThread != nil {
            pthread_mutex_lock(&mutex)
            rightInputPtr = rightSamples
            rightSampleCount = sampleCount
            rightLookahead = lookaheadR
            rightOutputPtr = rightDSDOut
            hasPendingRightJob = true
            pthread_cond_signal(&workAvailableCond)
            pthread_mutex_unlock(&mutex)

            // Левый канал модулируется параллельно на текущем P-ядре
            modulatorL.processBlockToDSDBytes(
                inputSamples: leftSamples,
                sampleCount: sampleCount,
                lookaheadSample: lookaheadL,
                dsdOutputBytes: leftDSDOut,
                scratchRaw: scratchL
            )

            // Ожидаем завершения правого канала
            pthread_mutex_lock(&mutex)
            while hasPendingRightJob {
                pthread_cond_wait(&workDoneCond, &mutex)
            }
            pthread_mutex_unlock(&mutex)
        } else {
            modulatorL.processBlockToDSDBytes(
                inputSamples: leftSamples,
                sampleCount: sampleCount,
                lookaheadSample: lookaheadL,
                dsdOutputBytes: leftDSDOut,
                scratchRaw: scratchL
            )
            modulatorR.processBlockToDSDBytes(
                inputSamples: rightSamples,
                sampleCount: sampleCount,
                lookaheadSample: lookaheadR,
                dsdOutputBytes: rightDSDOut,
                scratchRaw: scratchR
            )
        }

        let elapsedNs = DispatchTime.now().uptimeNanoseconds &- t0
        lastBlockComputeTimeMs = Double(elapsedNs) * 1.0e-6
        let peakL = modulatorL.consumePeakIntegratorAmplitude()
        let peakR = modulatorR.consumePeakIntegratorAmplitude()
        maxObservedIntegratorPeak = max(peakL, peakR)
    }
}
