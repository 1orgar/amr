//
//  AudioEngineController+RealtimeWorker.swift
//  AppleMusicRemoteMac
//
//  Real-Time Pipeline Coordinator Thread (Node 0 -> Node 1 -> Node 2 -> Node 3 -> Node 4):
//  - Mach THREAD_TIME_CONSTRAINT_POLICY promotion (strict computation < constraint <= period)
//  - Lossless 16-sample DSD/ASRC carry-over buffer (zero sample drop on non-multiple-of-16 ASRC blocks)
//  - TOCTOU-free Mastering Restoration & Headroom ISP coordination
//

import Accelerate
import CoreAudio
import Darwin
import Foundation

extension AudioEngineController {

    internal nonisolated func resetSDMCarryOver() {
        sdmCarryCount = 0
        memset(sdmCarryL, 0, 16 * MemoryLayout<Double>.stride)
        memset(sdmCarryR, 0, 16 * MemoryLayout<Double>.stride)
    }

    internal static func computeMachTimeConstraintParams(chunkDurationMs: Int) -> (periodMs: Double, computationMs: Double, constraintMs: Double) {
        let batchMs = min(max(Double(chunkDurationMs), 5.0), 40.0)
        let constraintMs = batchMs * 0.90
        let computationMs = min(batchMs * 0.60, constraintMs - 0.5)
        return (batchMs, computationMs, constraintMs)
    }

    internal func spawnWorkerThread(initialGeneration: UInt64) {
        pipelineShouldStop = false
        _workerStartGeneration = initialGeneration
        var attr = pthread_attr_t()
        pthread_attr_init(&attr)
        pthread_attr_set_qos_class_np(&attr, QOS_CLASS_USER_INTERACTIVE, 0)

        let unmanagedSelf = Unmanaged.passUnretained(self).toOpaque()
        var thread: pthread_t?
        let rc = pthread_create(
            &thread,
            &attr,
            { rawCtx -> UnsafeMutableRawPointer? in
                let controller = Unmanaged<AudioEngineController>.fromOpaque(rawCtx).takeUnretainedValue()
                controller.realtimePipelineLoop()
                return nil
            },
            unmanagedSelf
        )
        pthread_attr_destroy(&attr)
        if rc == 0 {
            pipelineThread = thread
        }
    }

    internal func stopWorkerThreadOnly() {
        pipelineShouldStop = true
        if let thread = pipelineThread {
            pthread_join(thread, nil)
            pipelineThread = nil
        }
    }

    internal nonisolated func realtimePipelineLoop() {
        pthread_setname_np("com.amr.dsp.PipelineCoordinator")

        let initialCfg = withStateLock { _cachedConfig }
        var isTimeConstraintPromoted = false
        if initialCfg.oversamplerBackend != .metalOverlapSave {
            let tc = Self.computeMachTimeConstraintParams(chunkDurationMs: initialCfg.chunkDurationMs)
            isTimeConstraintPromoted = MachRealtimeThreadPolicy.promoteCurrentThread(
                periodMs: tc.periodMs,
                computationMs: tc.computationMs,
                constraintMs: tc.constraintMs
            )
        } else {
            _ = MachRealtimeThreadPolicy.demoteToInteractiveStandardPolicy()
        }

        // Обработка выполняется кэш-локальными тайлами по 512 входных кадров (помещаются в L2 кэш Apple Silicon)
        let tileFrames = 512
        let floatInL = UnsafeMutablePointer<Float>.allocate(capacity: tileFrames)
        let floatInR = UnsafeMutablePointer<Float>.allocate(capacity: tileFrames)
        let node1Buf = AlignedPlanarDoubleBuffer(capacityFrames: tileFrames)

        // Максимальный коэффициент оверсэмплинга для 512 входных кадров при DSD512 (x512) = 262 144 кадра
        let maxOversampledFrames = tileFrames * 512 + 64
        let oversampledBuf = AlignedPlanarDoubleBuffer(capacityFrames: maxOversampledFrames)
        // Выровненный буфер склейки [carry (0..15) | oversampledFrames] при дробном ASRC
        let sdmStagingBuf = AlignedPlanarDoubleBuffer(capacityFrames: maxOversampledFrames + 32)

        let maxDSDBytesPerChannel = (maxOversampledFrames + 32) / 8 + 16
        let dsdBytesL = UnsafeMutablePointer<UInt8>.allocate(capacity: maxDSDBytesPerChannel)
        let dsdBytesR = UnsafeMutablePointer<UInt8>.allocate(capacity: maxDSDBytesPerChannel)

        let maxPackedWords = (maxOversampledFrames + 32) * 2 + 32
        let packedWordsOut = UnsafeMutablePointer<Int32>.allocate(capacity: maxPackedWords)

        defer {
            floatInL.deallocate()
            floatInR.deallocate()
            dsdBytesL.deallocate()
            dsdBytesR.deallocate()
            packedWordsOut.deallocate()
        }

        var appliedGen = _workerStartGeneration
        var appliedProfile = initialCfg.profile
        var appliedTrellis = initialCfg.trellisOrder
        var appliedIsi = initialCfg.isiRegularizerEnabled
        var lastEffectiveMode: DSPEngineMode = withStateLock { _activeRoute.effectiveMode }
        var lastInputRateHz: Int = withStateLock { _activeRoute.inputSampleRateHz }

        while !pipelineShouldStop {
            let (cfg, route, curGen, isLocal) = withStateLock {
                (_cachedConfig, _activeRoute, _liveParamGeneration, _isLocalFilePlaybackActive)
            }

            if route.effectiveMode != lastEffectiveMode || route.inputSampleRateHz != lastInputRateHz {
                resetSDMCarryOver()
                lastEffectiveMode = route.effectiveMode
                lastInputRateHz = route.inputSampleRateHz
            }

            // Потокобезопасное применение live-изменений конфигурации строго на рабочем потоке (0 data races!)
            if curGen != appliedGen {
                appliedGen = curGen
                headroomISP.headroomDB = cfg.headroomDB
                headroomISP.ispProtectionEnabled = cfg.ispProtectionEnabled
                nosQuantizerL.mode = cfg.nosDitherMode
                nosQuantizerR.mode = cfg.nosDitherMode

                let wantsTimeConstraint = (cfg.oversamplerBackend != .metalOverlapSave)
                if wantsTimeConstraint && !isTimeConstraintPromoted {
                    let dynTC = Self.computeMachTimeConstraintParams(chunkDurationMs: cfg.chunkDurationMs)
                    isTimeConstraintPromoted = MachRealtimeThreadPolicy.promoteCurrentThread(
                        periodMs: dynTC.periodMs,
                        computationMs: dynTC.computationMs,
                        constraintMs: dynTC.constraintMs
                    )
                } else if !wantsTimeConstraint && isTimeConstraintPromoted {
                    isTimeConstraintPromoted = false
                    _ = MachRealtimeThreadPolicy.demoteToInteractiveStandardPolicy()
                }

                if cfg.profile != appliedProfile || cfg.trellisOrder != appliedTrellis || cfg.isiRegularizerEnabled != appliedIsi {
                    appliedProfile = cfg.profile
                    appliedTrellis = cfg.trellisOrder
                    appliedIsi = cfg.isiRegularizerEnabled
                    sdmExecutor.updateConfiguration(
                        profile: cfg.profile,
                        rate: route.dsdMultiplier,
                        grid: route.baseGrid,
                        trellisOrder: cfg.trellisOrder,
                        isiRegularizerEnabled: cfg.isiRegularizerEnabled,
                        resetStates: false
                    )
                }
            }

            // Если выходной кольцевой буфер заполнен более чем на 75%, ждём 1 мс
            if outputRingBuffer.availableToRead > (outputRingBuffer.capacityWords * 3) / 4 {
                usleep(1000)
                continue
            }

            // Mode C: Прямая передача нативного потока .dsf -> DoP без PCM-децимации
            if isLocal && localFileSource.isNativeDSD {
                let writtenFrames = localFileSource.readNextDSFDoPWords(
                    into: outputRingBuffer,
                    dopPackerState: &dopPackerState,
                    maxDoPFrames: 4096
                )
                if writtenFrames == 0 {
                    usleep(2000)
                }
                continue
            }

            // Mode C: Подкачка локального PCM-файла (WAV/FLAC/ALAC/AIFF) во входное кольцо
            if isLocal && captureRingBuffer.availableFramesToWrite >= 4096 {
                _ = localFileSource.readNextPCMChunk(into: captureRingBuffer, maxFrames: 2048)
            }

            let isTestNoise = RoomAcousticService.shared.isTestSignalPlaying
            let availableIn = isTestNoise ? max(tileFrames, (route.inputSampleRateHz * cfg.chunkDurationMs) / 1000) : captureRingBuffer.availableFramesToRead
            if availableIn < tileFrames {
                let minIdleWords = max(32_768, (route.dopCarrierRateHz / 5) * 2)
                if outputRingBuffer.availableToRead < minIdleWords {
                    let silenceFrames = min(32_768, max(8192, route.dopCarrierRateHz / 20))
                    if route.effectiveMode == .sdmDoP {
                        DoPPackerState.fillSilenceStereo32(
                            state: &dopPackerState,
                            interleavedOutput: packedWordsOut,
                            frameCount: silenceFrames
                        )
                    } else {
                        memset(packedWordsOut, 0, silenceFrames * 2 * MemoryLayout<Int32>.stride)
                    }
                    _ = outputRingBuffer.write(from: packedWordsOut, wordCount: silenceFrames * 2)
                }
                usleep(1000)
                continue
            }

            let osFactor = max(1, route.targetModulatorRateHz / max(1, route.inputSampleRateHz))
            let tileOutFrames = (route.effectiveMode == .sdmDoP)
                ? max(16, (tileFrames * osFactor + 16) / 16)
                : (tileFrames * osFactor)
            let tileNeededWords = min(maxPackedWords, tileOutFrames * 2 + 128)
            if outputRingBuffer.availableToWrite < tileNeededWords {
                usleep(1000)
                continue
            }

            let targetBatchFrames = max(tileFrames, (route.inputSampleRateHz * cfg.chunkDurationMs) / 1000)
            let maxTilesInBatch = max(1, min(availableIn, targetBatchFrames) / tileFrames)

            let batchStartNs = DispatchTime.now().uptimeNanoseconds
            var totalProcessedInFrames = 0

            for _ in 0..<maxTilesInBatch {
                if pipelineShouldStop || outputRingBuffer.availableToWrite < tileNeededWords {
                    break
                }
                let readFrames: Int
                if isTestNoise {
                    _ = captureRingBuffer.readPlanar(intoLeft: floatInL, intoRight: floatInR, maxFrames: tileFrames)
                    RoomAcousticService.shared.fillPinkNoiseStereoFloat32(left: floatInL, right: floatInR, frameCount: tileFrames)
                    readFrames = tileFrames
                } else {
                    readFrames = captureRingBuffer.readPlanar(intoLeft: floatInL, intoRight: floatInR, maxFrames: tileFrames)
                }
                guard readFrames > 0 else { break }
                totalProcessedInFrames &+= readFrames

                // Узел 0: Векторная конвертация Float32 -> Double (FP64) + мастеринговая реставрация без TOCTOU по deClipMode
                vDSP_vspdp(floatInL, 1, node1Buf.left, 1, vDSP_Length(readFrames))
                vDSP_vspdp(floatInR, 1, node1Buf.right, 1, vDSP_Length(readFrames))

                let deClipModeApplied: MasteringDeClipMode
                if !isTestNoise {
                    deClipModeApplied = MasteringRestorationService.shared.processDSPPlanarDoubleIfEnabled(
                        left: node1Buf.left,
                        right: node1Buf.right,
                        frameCount: readFrames,
                        sampleRate: Double(route.inputSampleRateHz)
                    )
                } else {
                    deClipModeApplied = .off
                }

                // Узел 1: Запас по перегрузке (Headroom) из фактически применённого под блокировкой deClipModeApplied + 4x True Peak ISP
                let deClipCapGain: Double = (deClipModeApplied == .studio)
                    ? 0.5956621435290105 // -4.5 dB
                    : ((deClipModeApplied == .off) ? 1.0 : 0.6606934480075959) // -3.6 dB
                headroomISP.processPlanarDoubleInPlace(
                    left: node1Buf.left,
                    right: node1Buf.right,
                    frameCount: readFrames,
                    maxLinearGainCap: deClipCapGain
                )

                // Узел 1b: 64-битная параметрическая коррекция АЧХ комнаты (Room EQ Minimum-Phase Biquads)
                RoomAcousticService.shared.processPlanarDoubleIfEnabled(
                    left: node1Buf.left,
                    right: node1Buf.right,
                    frameCount: readFrames,
                    sampleRate: route.inputSampleRateHz
                )

                // Узел 1c: 64-битный ночной контроль динамики (Late-Night DRC)
                if !isTestNoise {
                    LateNightDRCService.shared.processPlanarDoubleIfEnabled(
                        left: node1Buf.left,
                        right: node1Buf.right,
                        frameCount: readFrames,
                        sampleRate: Double(route.inputSampleRateHz)
                    )
                }

                // Применяем 15-мс косинусный кроссфейд при старте/смене частоты
                for i in 0..<readFrames {
                    let g = fadeEnvelope.nextGain()
                    if g < 0.999999 {
                        node1Buf.left[i] *= g
                        node1Buf.right[i] *= g
                    }
                }

                // Узел 2: Многоступенчатый оверсэмплинг (Accelerate AMX FP64 или Metal Overlap-Save df64)
                let oversampler: OversamplerBackend = (cfg.oversamplerBackend == .metalOverlapSave)
                    ? metalOversampler
                    : amxOversampler

                let oversampledFrames = oversampler.oversampleStereoBlock(
                    inputL: node1Buf.left,
                    inputR: node1Buf.right,
                    inputFrames: readFrames,
                    inputRateHz: route.inputSampleRateHz,
                    targetRateHz: route.targetModulatorRateHz,
                    outputBuffer: oversampledBuf
                )
                guard oversampledFrames > 0 else { continue }

                if route.effectiveMode == .sdmDoP {
                    // Узел 3: Беспотерьная склейка с остатком предыдущего блока (`carryCount: 0..15`) для кратности 16 битам DoP
                    let prevCarry = sdmCarryCount
                    let srcLeft: UnsafePointer<Double>
                    let srcRight: UnsafePointer<Double>
                    let totalAvailable: Int

                    if prevCarry > 0 {
                        let safeFrames = min(oversampledFrames, sdmStagingBuf.capacityFrames - prevCarry)
                        memcpy(sdmStagingBuf.left, sdmCarryL, prevCarry * MemoryLayout<Double>.stride)
                        memcpy(sdmStagingBuf.right, sdmCarryR, prevCarry * MemoryLayout<Double>.stride)
                        memcpy(sdmStagingBuf.left.advanced(by: prevCarry), oversampledBuf.left, safeFrames * MemoryLayout<Double>.stride)
                        memcpy(sdmStagingBuf.right.advanced(by: prevCarry), oversampledBuf.right, safeFrames * MemoryLayout<Double>.stride)
                        srcLeft = UnsafePointer(sdmStagingBuf.left)
                        srcRight = UnsafePointer(sdmStagingBuf.right)
                        totalAvailable = prevCarry + safeFrames
                    } else {
                        srcLeft = UnsafePointer(oversampledBuf.left)
                        srcRight = UnsafePointer(oversampledBuf.right)
                        totalAvailable = oversampledFrames
                    }

                    let alignedSamples = totalAvailable & ~15
                    let remSamples = totalAvailable - alignedSamples

                    if alignedSamples > 0 {
                        // Точный lookahead следующего реального отсчёта при наличии хвоста `remSamples > 0`
                        let lookL = (totalAvailable > alignedSamples) ? srcLeft[alignedSamples] : srcLeft[alignedSamples - 1]
                        let lookR = (totalAvailable > alignedSamples) ? srcRight[alignedSamples] : srcRight[alignedSamples - 1]

                        sdmExecutor.processStereoBlock(
                            leftSamples: srcLeft,
                            rightSamples: srcRight,
                            sampleCount: alignedSamples,
                            lookaheadL: lookL,
                            lookaheadR: lookR,
                            leftDSDOut: dsdBytesL,
                            rightDSDOut: dsdBytesR,
                            allowCallerTimeConstraint: cfg.oversamplerBackend != .metalOverlapSave,
                            callerAlreadyPromoted: isTimeConstraintPromoted
                        )

                        // Узел 4: Бит-точная упаковка DoP (маркеры 0x05 / 0xFA + 16 бит DSD MSB-first в S32_LE)
                        let dopFrames = alignedSamples >> 4
                        DoPPackerState.packStereoDSDBytesToDoP32(
                            state: &dopPackerState,
                            dsdLeftBytes: dsdBytesL,
                            dsdRightBytes: dsdBytesR,
                            dopFrameCount: dopFrames,
                            interleavedOutput: packedWordsOut
                        )
                        _ = outputRingBuffer.write(from: packedWordsOut, wordCount: dopFrames * 2)
                    }

                    if remSamples > 0 {
                        memcpy(sdmCarryL, srcLeft.advanced(by: alignedSamples), remSamples * MemoryLayout<Double>.stride)
                        memcpy(sdmCarryR, srcRight.advanced(by: alignedSamples), remSamples * MemoryLayout<Double>.stride)
                    }
                    sdmCarryCount = remSamples
                } else {
                    // Режим HQ NOS PCM (705.6 / 768 кГц) с 15-порядковым формирователем шума LNS15
                    let targetBits = halManager.negotiatedPhysicalFormat?.bitsPerChannel ?? 24
                    nosQuantizerL.targetBits = targetBits
                    nosQuantizerR.targetBits = targetBits
                    NOSPCMDitherQuantizer.quantizeStereoBlock(
                        left: oversampledBuf.left,
                        right: oversampledBuf.right,
                        frameCount: oversampledFrames,
                        quantizerL: &nosQuantizerL,
                        quantizerR: &nosQuantizerR,
                        interleavedOut: packedWordsOut
                    )
                    _ = outputRingBuffer.write(from: packedWordsOut, wordCount: oversampledFrames * 2)
                }
            }

            guard totalProcessedInFrames > 0 else { continue }

            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds &- batchStartNs) * 1.0e-6
            let batchBudgetMs = (Double(totalProcessedInFrames) / Double(max(1, route.inputSampleRateHz))) * 1000.0
            let cpuPercent = min(100.0, (elapsedMs / max(0.05, batchBudgetMs)) * 100.0)
            let hogActive = halManager.isHogModeLocked
            let intActive = (halManager.negotiatedPhysicalFormat?.isIntegerMode ?? false)
            let peakState = sdmExecutor.maxObservedIntegratorPeak
            let clips = headroomISP.ispClipCount
            let underruns = outputRingBuffer.underrunCount
            let fillPct = outputRingBuffer.fillPercentage

            withStateLock {
                _cachedTelemetry.isRunning = true
                _cachedTelemetry.activeMode = route.effectiveMode
                _cachedTelemetry.inputSampleRateHz = route.inputSampleRateHz
                _cachedTelemetry.outputSampleRateHz = route.targetModulatorRateHz
                _cachedTelemetry.dopCarrierRateHz = route.dopCarrierRateHz
                _cachedTelemetry.activeClockGrid = route.baseGrid
                _cachedTelemetry.isHogModeActive = hogActive
                _cachedTelemetry.isIntegerModeActive = intActive
                _cachedTelemetry.maxIntegratorState = peakState
                _cachedTelemetry.ispClipCount = clips
                _cachedTelemetry.underrunCount = underruns
                _cachedTelemetry.ringBufferFillPercent = fillPct
                _cachedTelemetry.processingLoadPercent = 0.85 * _cachedTelemetry.processingLoadPercent + 0.15 * cpuPercent
            }
        }
    }
}
