import Accelerate
import CoreAudio
import Darwin
import Foundation

/// Главный оркестратор гибридного аудиодвижка реального времени (`PCM -> DSD256 DoP / HQ NOS PCM`).
///
/// Обеспечивает:
/// - Полную изоляцию управляющего контура (`Swift 6 actor`) от неблокирующего RT-конвейера (`pthread` + `THREAD_TIME_CONSTRAINT_POLICY`);
/// - Захват аудио из `AudioProcessTapService` (`CATapDescription`), виртуального `Loopback` или локальных файлов (`.wav/.flac/.alac/.dsf`);
/// - Эксклюзивный захват ЦАП/DDC (`Hog Mode` + `Integer Mode` в `HALDeviceManager`) и выдачу бит-точного потока `DoP` / `NOS PCM`.
public actor AudioEngineController {
    public static let shared = AudioEngineController()

    internal static let userDefaultsKey = "amr.dsp.engine_configuration.v2"
    internal static let legacyUserDefaultsKeyV1 = "amr.dsp.engine_configuration.v1"
    internal static let isTestingEnvironment: Bool = {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }()

    /// Входной lock-free кольцевой буфер для приёма `Float32` стереокадров из `AudioProcessTapService` (`262 144` кадра).
    public nonisolated let captureRingBuffer = SPSCStereoFloatRingBuffer(capacityFrames: 262_144)

    /// Выходной lock-free кольцевой буфер упакованных 32-битных слов (`DoP` или `NOS PCM`) для `RealtimeIOProc` (`1 048 576` слов = 524 288 стереокадров).
    public nonisolated let outputRingBuffer = SPSCAtomicRingBuffer(capacityWords: 1_048_576)

    // Атомарный снимок состояния для неблокирующего чтения из AudioProcessTapService и PlayerStatusEngine
    internal nonisolated(unsafe) var stateLock = os_unfair_lock_s()
    internal nonisolated(unsafe) var _cachedConfig: EngineConfiguration
    internal nonisolated(unsafe) var _cachedTelemetry: EngineTelemetry = EngineTelemetry()
    internal nonisolated(unsafe) var _isPipelineActive: Bool = false
    internal nonisolated(unsafe) var _sourceSampleRateHz: Int = 44_100
    internal nonisolated(unsafe) var _activeRoute: SampleRateRouteDecision
    internal nonisolated(unsafe) var _liveParamGeneration: UInt64 = 0
    internal nonisolated(unsafe) var _isLocalFilePlaybackActive: Bool = false
    internal nonisolated(unsafe) var _activeOutputDeviceID: AudioDeviceID = 0
    internal nonisolated(unsafe) var _activeOutputDeviceUID: String = ""
    internal nonisolated(unsafe) var _activeOutputDeviceName: String = ""
    internal nonisolated(unsafe) var _pinnedAutoDeviceUID: String? = nil
    internal var isReconfiguringHardware: Bool = false
    internal var pendingHardwareDeviceCheck: Bool = false

    // Узлы конвейера обработки:
    // при запущенном pipelineThread исключительное право чтения/модификации принадлежит потоку realtimePipelineLoop;
    // actor модифицирует их ТОЛЬКО после полного завершения pipelineThread (stopWorkerThreadOnly()).
    internal nonisolated let halManager = HALDeviceManager()
    internal nonisolated let headroomISP: HeadroomISPProcessor
    internal nonisolated let amxOversampler: AccelerateAMXOversampler
    internal nonisolated let metalOversampler: MetalOverlapSaveOversampler
    internal nonisolated let sdmExecutor: ParallelStereoSDMExecutor
    internal nonisolated(unsafe) var nosQuantizerL: NOSPCMDitherQuantizer
    internal nonisolated(unsafe) var nosQuantizerR: NOSPCMDitherQuantizer
    internal nonisolated(unsafe) var dopPackerState = DoPPackerState()
    internal nonisolated(unsafe) var fadeEnvelope = CosineFadeEnvelope()
    internal nonisolated let loopbackSession: LoopbackAudioCaptureSession
    internal nonisolated let localFileSource = LocalAudioFileSource()

    // 16-отсчётный стерео буфер переноса остатка DSD/ASRC (предотвращает потерю `oversampledFrames % 16` отсчётов на границах тайлов)
    internal nonisolated(unsafe) let sdmCarryL: UnsafeMutablePointer<Double>
    internal nonisolated(unsafe) let sdmCarryR: UnsafeMutablePointer<Double>
    internal nonisolated(unsafe) var sdmCarryCount: Int = 0

    // Рабочий RT-поток конвейера (Node 1 -> Node 2 -> Node 3 -> Node 4)
    internal nonisolated(unsafe) var pipelineThread: pthread_t?
    internal nonisolated(unsafe) var _workerStartGeneration: UInt64 = 0
    internal nonisolated(unsafe) var workerStopLock = os_unfair_lock_s()
    internal nonisolated(unsafe) var _pipelineShouldStop: Bool = false

    internal nonisolated var pipelineShouldStop: Bool {
        @inline(__always)
        get {
            os_unfair_lock_lock(&workerStopLock)
            let flag = _pipelineShouldStop
            os_unfair_lock_unlock(&workerStopLock)
            return flag
        }
        @inline(__always)
        set {
            os_unfair_lock_lock(&workerStopLock)
            _pipelineShouldStop = newValue
            os_unfair_lock_unlock(&workerStopLock)
        }
    }

    private init() {
        let loadedConfig = Self.loadPersistedConfiguration()
        self._cachedConfig = loadedConfig
        self.headroomISP = HeadroomISPProcessor(
            headroomDB: loadedConfig.headroomDB,
            ispProtectionEnabled: loadedConfig.ispProtectionEnabled
        )
        self.amxOversampler = AccelerateAMXOversampler(
            phaseMode: loadedConfig.phaseMode,
            tapsPerPhase: 256,
            maxInputFrames: 1024
        )
        self.metalOversampler = MetalOverlapSaveOversampler(
            phaseMode: loadedConfig.phaseMode,
            tapsPerPhase: 512,
            maxInputFrames: 1024
        )
        self._activeRoute = SampleRateRouter.resolveRoute(
            inputSampleRateHz: 44_100,
            configuration: loadedConfig
        )
        self.sdmExecutor = ParallelStereoSDMExecutor(
            profile: loadedConfig.profile,
            rate: loadedConfig.dsdRate,
            grid: .grid44k1,
            trellisOrder: loadedConfig.trellisOrder,
            isiRegularizerEnabled: loadedConfig.isiRegularizerEnabled
        )
        self.nosQuantizerL = NOSPCMDitherQuantizer(mode: loadedConfig.nosDitherMode, targetBits: 24, seed: 0x9E37_79B9_7F4A_7C15)
        self.nosQuantizerR = NOSPCMDitherQuantizer(mode: loadedConfig.nosDitherMode, targetBits: 24, seed: 0xD1B5_4A32_D192_ED03)
        self.loopbackSession = LoopbackAudioCaptureSession(captureRingBuffer: captureRingBuffer)

        self.sdmCarryL = UnsafeMutablePointer<Double>.allocate(capacity: 16)
        self.sdmCarryR = UnsafeMutablePointer<Double>.allocate(capacity: 16)
        self.sdmCarryL.initialize(repeating: 0.0, count: 16)
        self.sdmCarryR.initialize(repeating: 0.0, count: 16)
    }

    deinit {
        sdmCarryL.deallocate()
        sdmCarryR.deallocate()
    }

    // MARK: - Non-isolated Fast Snapshots for RT Tap & Status Engine

    @usableFromInline
    @inline(__always)
    internal nonisolated func withStateLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return body()
    }

    /// Возвращает `true`, если DSP-движок активно обрабатывает поток (`sdmDoP` или `hqNOSPCM`) и захватывает аудио из Process Tap.
    public nonisolated var isActivePipelineHook: Bool {
        withStateLock {
            _isPipelineActive && (_cachedConfig.mode != .bitPerfectPassthrough) && !_isLocalFilePlaybackActive
        }
    }

    /// Возвращает `true`, если физическое выходное устройство захвачено в эксклюзивный `Hog Mode`
    /// (в этом случае `AudioProcessTapService` включает `.mutedWhenTapped`, чтобы системный микшер не дублировал звук).
    public nonisolated var isHoldingExclusiveHogMode: Bool {
        withStateLock {
            _cachedTelemetry.isHogModeActive && _isPipelineActive
        }
    }

    public nonisolated var activeHardwareOutputDeviceID: AudioDeviceID {
        withStateLock { _isPipelineActive ? _activeOutputDeviceID : 0 }
    }

    public nonisolated var activeHardwareOutputDeviceInfo: (id: AudioDeviceID, uid: String, name: String)? {
        withStateLock {
            guard _isPipelineActive, _activeOutputDeviceID != 0 else { return nil }
            return (_activeOutputDeviceID, _activeOutputDeviceUID, _activeOutputDeviceName)
        }
    }

    public nonisolated func currentConfigurationSnapshot() -> EngineConfiguration {
        withStateLock { _cachedConfig }
    }

    public nonisolated func latestTelemetrySnapshot() -> EngineTelemetry {
        var tel = withStateLock { _cachedTelemetry }
        tel.ringBufferFillPercent = outputRingBuffer.fillPercentage
        tel.underrunCount = outputRingBuffer.underrunCount
        return tel
    }

    /// Неблокирующая подача входных `Float32` кадров напрямую из `AudioProcessTapService` RT-коллбэка.
    @inlinable
    public nonisolated func feedPlanarFloat32FromTap(
        left: UnsafePointer<Float>,
        right: UnsafePointer<Float>,
        frames: Int
    ) {
        guard isActivePipelineHook else { return }
        _ = captureRingBuffer.writePlanar(left: left, right: right, frames: frames)
    }

    @inlinable
    public nonisolated func feedInterleavedFloat32FromTap(
        interleaved: UnsafePointer<Float>,
        frames: Int,
        channels: Int
    ) {
        guard isActivePipelineHook else { return }
        _ = captureRingBuffer.writeInterleaved(interleaved, frames: frames, channels: channels)
    }

    // MARK: - Control Plane Configuration & Lifecycle

    public func updateConfiguration(_ newConfig: EngineConfiguration, inputSampleRateHz: Int? = nil) async {
        let prevConfig = currentConfigurationSnapshot()
        Self.persistConfiguration(newConfig)

        let (currentInRate, wasActive) = withStateLock { () -> (Int, Bool) in
            _cachedConfig = newConfig
            if let overrideRate = inputSampleRateHz, !_isLocalFilePlaybackActive {
                _sourceSampleRateHz = max(44_100, overrideRate)
            }
            return (_sourceSampleRateHz, _isPipelineActive)
        }

        if prevConfig.targetDeviceUID != newConfig.targetDeviceUID {
            withStateLock { _pinnedAutoDeviceUID = nil }
        }

        if newConfig.mode == .bitPerfectPassthrough {
            await stopPipeline()
            RoomAcousticService.shared.refreshLocalPassthroughEQPipeline()
            return
        }
        RoomAcousticService.shared.refreshLocalPassthroughEQPipeline()

        let needsHardwareRestart = !wasActive
            || prevConfig.mode != newConfig.mode
            || prevConfig.dsdRate != newConfig.dsdRate
            || prevConfig.maxNOSPCMRateHz != newConfig.maxNOSPCMRateHz
            || prevConfig.clockPolicy != newConfig.clockPolicy
            || prevConfig.oversamplerBackend != newConfig.oversamplerBackend
            || prevConfig.phaseMode != newConfig.phaseMode
            || prevConfig.hogModeEnabled != newConfig.hogModeEnabled
            || prevConfig.chunkDurationMs != newConfig.chunkDurationMs
            || prevConfig.targetDeviceUID != newConfig.targetDeviceUID

        if needsHardwareRestart {
            _ = await startOrReconfigurePipeline(inputSampleRateHz: currentInRate)
        } else {
            // Бесшовное применение live-параметров (профиль 7EC 5 мс, M=1..16, ISI, Headroom, ISP, LNS15/TPDF)
            // выполняется исключительно на самом рабочем потоке realtimePipelineLoop без гонок данных!
            withStateLock {
                _liveParamGeneration &+= 1
            }
            refreshTelemetrySnapshot()
        }
    }

    /// Открывает локальный эталонный аудиофайл (`.wav`, `.flac`, `.alac`, `.aiff`, `.dsf`) для прямого воспроизведения (Mode C ТЗ).
    public func openLocalReferenceFile(url: URL) async throws {
        stopWorkerThreadOnly()
        try localFileSource.open(url: url)
        let fileRate = localFileSource.sampleRateHz
        withStateLock {
            _isLocalFilePlaybackActive = true
            _sourceSampleRateHz = fileRate
        }
        _ = await startOrReconfigurePipeline(inputSampleRateHz: fileRate)
    }

    public func closeLocalReferenceFile() async {
        stopWorkerThreadOnly()
        localFileSource.close()
        let inRate = withStateLock { () -> Int in
            _isLocalFilePlaybackActive = false
            return _sourceSampleRateHz
        }
        if currentConfigurationSnapshot().mode != .bitPerfectPassthrough {
            _ = await startOrReconfigurePipeline(inputSampleRateHz: inRate)
        }
    }

    /// Уведомление от `BitPerfectLogMonitor` или `AudioProcessTapService` о смене входной частоты дискретизации трека.
    public func notifySourceSampleRateChanged(_ newSampleRateHz: Double) async {
        let rateInt = max(44_100, Int(newSampleRateHz.rounded()))
        let (prevRate, cfg, active, isLocal) = withStateLock { () -> (Int, EngineConfiguration, Bool, Bool) in
            let p = _sourceSampleRateHz
            if !_isLocalFilePlaybackActive {
                _sourceSampleRateHz = rateInt
            }
            return (p, _cachedConfig, _isPipelineActive, _isLocalFilePlaybackActive)
        }

        guard !isLocal, cfg.mode != .bitPerfectPassthrough else { return }
        guard !DLNADiscoveryManager.shared.hasActiveRenderer else { return }
        if !active || prevRate != rateInt {
            _ = await startOrReconfigurePipeline(inputSampleRateHz: rateInt)
        }
    }

    internal func finishHardwareReconfiguration() {
        isReconfiguringHardware = false
        if pendingHardwareDeviceCheck {
            pendingHardwareDeviceCheck = false
            Task {
                await self.handleHardwareDeviceChange()
            }
        }
    }

    /// Обработчик уведомлений CoreAudio о смене системного устройства вывода или списка аудиоустройств.
    public func handleHardwareDeviceChange() async {
        if isReconfiguringHardware {
            pendingHardwareDeviceCheck = true
            return
        }
        let (cfg, wasActive, curDevID, isLocal) = withStateLock {
            (_cachedConfig, _isPipelineActive, _activeOutputDeviceID, _isLocalFilePlaybackActive)
        }
        guard cfg.mode != .bitPerfectPassthrough, !isLocal else { return }
        if DLNADiscoveryManager.shared.hasActiveRenderer {
            if wasActive {
                await suspendForDLNARouting()
            }
            return
        }

        guard let desired = resolveTargetOutputDevice(cfg: cfg) else {
            if wasActive {
                NSLog("[AudioEngineController] 🔌 Целевой внешний ЦАП отключён — останавливаем DSP-вывод")
                await stopPipeline(restartTapAfterStop: true)
                RoomAcousticService.shared.refreshLocalPassthroughEQPipeline()
            }
            return
        }

        if wasActive && desired.id == curDevID && halManager.currentActiveDeviceID == curDevID {
            return
        }

        _ = await startOrReconfigurePipeline()
    }

    /// Освобождает локальный USB `Hog Mode` на время работы сетевого DLNA-стриминга (сохраняя выбранный пресет DSP).
    public func suspendForDLNARouting() async {
        let (wasActive, isLocal) = withStateLock { (_isPipelineActive, _isLocalFilePlaybackActive) }
        guard wasActive else { return }
        isReconfiguringHardware = true
        defer { finishHardwareReconfiguration() }

        stopWorkerThreadOnly()
        resetSDMCarryOver()
        halManager.stopAndReleaseDevice()
        captureRingBuffer.reset()
        outputRingBuffer.reset()

        withStateLock {
            _isPipelineActive = false
            _activeOutputDeviceID = 0
            _activeOutputDeviceUID = ""
            _activeOutputDeviceName = ""
        }
        refreshTelemetrySnapshot()
        if !isLocal {
            RoomAcousticService.shared.refreshLocalPassthroughEQPipeline()
        }
        NSLog("[AudioEngineController] 🌐 Локальный HAL вывод приостановлен на время активного DLNA рендерера.")
    }

    /// Вызывается при явном выборе локального CoreAudio-устройства пользователем в PWA или Настройках macOS.
    public func handleUserSelectedLocalDevice(id: AudioDeviceID) async {
        let cfg = currentConfigurationSnapshot()
        guard cfg.mode != .bitPerfectPassthrough else {
            _ = CoreAudioDeviceManager.shared.setDefaultOutputDevice(id: id)
            RoomAcousticService.shared.refreshLocalPassthroughEQPipeline()
            return
        }

        let devices = CoreAudioDeviceManager.shared.getOutputDevices()
        guard let chosen = devices.first(where: { $0.id == id }) else { return }

        if !isDeviceEligible(chosen, for: cfg.mode) {
            await stopPipeline(restartTapAfterStop: true, restorePreviousDeviceOutput: false)
            _ = CoreAudioDeviceManager.shared.setDefaultOutputDevice(id: chosen.id)
            RoomAcousticService.shared.refreshLocalPassthroughEQPipeline()
            return
        }

        var updatedCfg = cfg
        if updatedCfg.targetDeviceUID != nil {
            updatedCfg.targetDeviceUID = chosen.uid
            Self.persistConfiguration(updatedCfg)
        }
        withStateLock {
            _cachedConfig = updatedCfg
            _pinnedAutoDeviceUID = chosen.uid
        }
        _ = await startOrReconfigurePipeline()
    }

    /// Запускает или перенастраивает конвейер DSP и физический вывод `HALDeviceManager`.
    @discardableResult
    public func startOrReconfigurePipeline(inputSampleRateHz: Int? = nil) async -> Bool {
        let cfg = currentConfigurationSnapshot()
        guard cfg.mode != .bitPerfectPassthrough else {
            await stopPipeline()
            return true
        }
        if DLNADiscoveryManager.shared.hasActiveRenderer && !withStateLock({ _isLocalFilePlaybackActive }) {
            await suspendForDLNARouting()
            return true
        }

        isReconfiguringHardware = true
        defer { finishHardwareReconfiguration() }

        let (inRate, isLocal) = withStateLock { () -> (Int, Bool) in
            let resolved = inputSampleRateHz ?? _sourceSampleRateHz
            _sourceSampleRateHz = resolved
            return (resolved, _isLocalFilePlaybackActive)
        }

        guard let targetDevice = resolveTargetOutputDevice(cfg: cfg) else {
            NSLog("[AudioEngineController] ⚠️ Не найдено подходящее выходное аудиоустройство (DoP >= 176.4 кГц) для DSP движка")
            stopWorkerThreadOnly()
            resetSDMCarryOver()
            halManager.stopAndReleaseDevice()
            withStateLock {
                _isPipelineActive = false
                _activeOutputDeviceID = 0
                _activeOutputDeviceUID = ""
                _activeOutputDeviceName = ""
            }
            refreshTelemetrySnapshot()
            if !isLocal {
                RoomAcousticService.shared.refreshLocalPassthroughEQPipeline()
            }
            return false
        }
        let devID = targetDevice.id

        let supportedRates = halManager.supportedSampleRates(deviceID: devID)
        var route: SampleRateRouteDecision
        if isLocal && localFileSource.isNativeDSD {
            let dsdClock = localFileSource.sampleRateHz
            let is48k = (dsdClock % 48_000 == 0)
            let grid: BaseClockGrid = is48k ? .grid48k : .grid44k1
            let multRaw = max(64, dsdClock / grid.rawValue)
            let mult = DSDRateMultiplier(rawValue: multRaw) ?? .dsd64
            route = SampleRateRouteDecision(
                effectiveMode: .sdmDoP,
                inputSampleRateHz: dsdClock,
                baseGrid: grid,
                dsdMultiplier: mult,
                targetModulatorRateHz: dsdClock,
                dopCarrierRateHz: dsdClock / 16,
                usesASRC: false,
                usesDXDBypass: true
            )
        } else {
            route = SampleRateRouter.resolveRoute(
                inputSampleRateHz: inRate,
                configuration: cfg,
                supportedDeviceSampleRates: supportedRates
            )
        }

        let existingFmt = halManager.currentNegotiatedFormat
        let canKeepHALOpen = (halManager.currentActiveDeviceID == devID)
            && (existingFmt?.sampleRateHz == route.dopCarrierRateHz)
            && ((existingFmt?.dsdMultiplier != nil) == (route.effectiveMode == .sdmDoP))
            && (existingFmt?.isHogModeLocked == cfg.hogModeEnabled)

        stopWorkerThreadOnly()
        resetSDMCarryOver()
        captureRingBuffer.reset()

        if canKeepHALOpen {
            let targetCushionFrames = max(16_384, route.dopCarrierRateHz / 4)
            let currentFrames = outputRingBuffer.availableToRead / 2
            if currentFrames < targetCushionFrames {
                prefillOutputSilence(route: route, frames: targetCushionFrames - currentFrames)
            }
        }

        headroomISP.headroomDB = cfg.headroomDB
        headroomISP.ispProtectionEnabled = cfg.ispProtectionEnabled
        headroomISP.reset()

        amxOversampler.phaseMode = cfg.phaseMode
        amxOversampler.reset()
        metalOversampler.phaseMode = cfg.phaseMode
        metalOversampler.reset()

        nosQuantizerL.mode = cfg.nosDitherMode
        nosQuantizerR.mode = cfg.nosDitherMode
        nosQuantizerL.reset()
        nosQuantizerR.reset()

        sdmExecutor.updateConfiguration(
            profile: cfg.profile,
            rate: route.dsdMultiplier,
            grid: route.baseGrid,
            trellisOrder: cfg.trellisOrder,
            isiRegularizerEnabled: cfg.isiRegularizerEnabled,
            resetStates: true
        )

        if canKeepHALOpen {
            let targetCushionFrames = max(16_384, route.dopCarrierRateHz / 4)
            let currentFrames = outputRingBuffer.availableToRead / 2
            if currentFrames < targetCushionFrames {
                prefillOutputSilence(route: route, frames: targetCushionFrames - currentFrames)
            }
        } else {
            if halManager.currentActiveDeviceID != 0 && halManager.currentActiveDeviceID != devID {
                halManager.stopAndReleaseDevice()
            } else {
                halManager.stopIOProcPreservingHogMode()
            }
            outputRingBuffer.reset()
            dopPackerState.reset()

            let prefillFrames = max(16_384, route.dopCarrierRateHz / 4)
            prefillOutputSilence(route: route, frames: prefillFrames)

            var negotiated = halManager.startOutput(
                deviceID: devID,
                sampleRateHz: route.dopCarrierRateHz,
                isDoPMode: (route.effectiveMode == .sdmDoP),
                dsdMultiplier: (route.effectiveMode == .sdmDoP) ? route.dsdMultiplier : nil,
                enableHogMode: cfg.hogModeEnabled,
                ringBuffer: outputRingBuffer
            )

            if negotiated == nil && route.effectiveMode == .sdmDoP && !(isLocal && localFileSource.isNativeDSD) {
                let fallbackMultipliers: [DSDRateMultiplier] = [.dsd128, .dsd64].filter { $0.rawValue < route.dsdMultiplier.rawValue }
                for fallbackDSD in fallbackMultipliers {
                    var fallbackCfg = cfg
                    fallbackCfg.dsdRate = fallbackDSD
                    let fallbackRoute = SampleRateRouter.resolveRoute(
                        inputSampleRateHz: inRate,
                        configuration: fallbackCfg,
                        supportedDeviceSampleRates: supportedRates
                    )
                    guard fallbackRoute.effectiveMode == .sdmDoP else { continue }
                    outputRingBuffer.reset()
                    dopPackerState.reset()
                    prefillOutputSilence(route: fallbackRoute, frames: max(4096, fallbackRoute.dopCarrierRateHz / 20))
                    if let okFmt = halManager.startOutput(
                        deviceID: devID,
                        sampleRateHz: fallbackRoute.dopCarrierRateHz,
                        isDoPMode: true,
                        dsdMultiplier: fallbackRoute.dsdMultiplier,
                        enableHogMode: cfg.hogModeEnabled,
                        ringBuffer: outputRingBuffer
                    ) {
                        NSLog("[AudioEngineController] ⚠️ Автопонижение DoP несущей %d -> %d Гц (DSD%d)",
                              route.dopCarrierRateHz, fallbackRoute.dopCarrierRateHz, fallbackRoute.dsdMultiplier.rawValue)
                        route = fallbackRoute
                        sdmExecutor.updateConfiguration(
                            profile: cfg.profile,
                            rate: route.dsdMultiplier,
                            grid: route.baseGrid,
                            trellisOrder: cfg.trellisOrder,
                            isiRegularizerEnabled: cfg.isiRegularizerEnabled,
                            resetStates: true
                        )
                        negotiated = okFmt
                        break
                    }
                }
            }

            guard negotiated != nil else {
                NSLog("[AudioEngineController] ❌ Не удалось запустить HAL вывод на частоте %d Гц", route.dopCarrierRateHz)
                halManager.stopAndReleaseDevice()
                withStateLock {
                    _isPipelineActive = false
                    _activeOutputDeviceID = 0
                    _activeOutputDeviceUID = ""
                    _activeOutputDeviceName = ""
                }
                refreshTelemetrySnapshot()
                if !isLocal {
                    RoomAcousticService.shared.refreshLocalPassthroughEQPipeline()
                }
                return false
            }
        }

        fadeEnvelope.triggerFadeIn(sampleRate: Double(inRate), durationMs: 15.0)

        let startGen = withStateLock { () -> UInt64 in
            _activeRoute = route
            _isPipelineActive = true
            _activeOutputDeviceID = devID
            _activeOutputDeviceUID = targetDevice.uid
            _activeOutputDeviceName = targetDevice.name
            return _liveParamGeneration
        }

        spawnWorkerThread(initialGeneration: startGen)
        refreshTelemetrySnapshot()

        if !isLocal {
            RoomAcousticService.shared.refreshLocalPassthroughEQPipeline()
            BitPerfectLogMonitor.shared.start()
            AudioProcessTapService.shared.startCapture()
        }

        NSLog(
            "[AudioEngineController] 🚀 DSP Engine active: dev='%@' (%u), mode=%@, in=%dHz -> out=%dHz (DoP carrier=%dHz, profile=%@, trellis=M%d, hog=%d, int=%d, hitless=%d)",
            targetDevice.name,
            devID,
            route.effectiveMode.rawValue,
            inRate,
            route.targetModulatorRateHz,
            route.dopCarrierRateHz,
            cfg.profile.displayName,
            cfg.trellisOrder.rawValue,
            halManager.isHogModeLocked ? 1 : 0,
            (halManager.negotiatedPhysicalFormat?.isIntegerMode ?? false) ? 1 : 0,
            canKeepHALOpen ? 1 : 0
        )
        return true
    }

    public func stopPipeline(restartTapAfterStop: Bool = true, restorePreviousDeviceOutput: Bool = true) async {
        isReconfiguringHardware = true
        defer { finishHardwareReconfiguration() }

        let prevUID = withStateLock { _activeOutputDeviceUID }
        stopWorkerThreadOnly()
        resetSDMCarryOver()
        loopbackSession.stop()
        localFileSource.close()
        halManager.stopAndReleaseDevice()
        captureRingBuffer.reset()
        outputRingBuffer.reset()

        withStateLock {
            _isLocalFilePlaybackActive = false
            _isPipelineActive = false
            _activeOutputDeviceID = 0
            _activeOutputDeviceUID = ""
            _activeOutputDeviceName = ""
            _pinnedAutoDeviceUID = nil
        }
        refreshTelemetrySnapshot()

        if restorePreviousDeviceOutput, !prevUID.isEmpty, let restoreID = HALDeviceManager.findDeviceID(byUID: prevUID) {
            _ = CoreAudioDeviceManager.shared.setDefaultOutputDevice(id: restoreID)
        }
        if !Self.isTestingEnvironment && restorePreviousDeviceOutput && !DLNADiscoveryManager.shared.hasActiveRenderer && BitPerfectLogMonitor.shared.isEnabled {
            let fallbackSourceRate = Double(withStateLock { _sourceSampleRateHz })
            let desiredRate = BitPerfectLogMonitor.shared.currentDetectedSampleRate ?? fallbackSourceRate
            if desiredRate >= 44_100.0 {
                _ = CoreAudioDeviceManager.shared.setSampleRate(desiredRate)
            }
        }
        RoomAcousticService.shared.refreshLocalPassthroughEQPipeline()
        if restartTapAfterStop {
            AudioProcessTapService.shared.reconcileCaptureAfterRouteChange()
        }
        NSLog("[AudioEngineController] ⏹️ DSP Engine stopped (returned to Bit-Perfect Passthrough).")
    }
}
