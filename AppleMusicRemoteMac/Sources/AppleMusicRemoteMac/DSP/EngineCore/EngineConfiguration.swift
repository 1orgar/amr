//
//  EngineConfiguration.swift
//  AppleMusicRemoteMac
//
//  Architecture & Engineering Spec: Reference Hybrid Real-Time DSP Engine
//  (PCM -> DSD256 DoP / HQ NOS PCM) for Apple Silicon (M1 Firestorm + Metal Unified Memory).
//

import Foundation

/// Основной режим работы референсного DSP-тракта.
public enum DSPEngineMode: String, CaseIterable, Sendable, Codable {
    /// Классический Bit-Perfect PCM (прямой вывод Music.app с автопереключением частоты CoreAudio).
    case bitPerfectPassthrough = "passthrough"
    /// Ветка HQ SDM DoP (7-порядковый дельта-сигма модулятор с Trellis M=8..16 + ISI Balancing -> DoP64/128/256).
    case sdmDoP = "sdm_dop"
    /// Ветка HQ NOS PCM (для дискретных 24/32-битных R2R ЦАПов: FP64 пре-апсемплинг 352.8..768 кГц + TPDF/LNS15).
    case hqNOSPCM = "hq_nos_pcm"

    public static let hqSDMDoP: DSPEngineMode = .sdmDoP

    public var displayName: String {
        switch self {
        case .bitPerfectPassthrough: return "Bit-Perfect PCM"
        case .sdmDoP: return "HQ SDM DoP (1-Bit DSD)"
        case .hqNOSPCM: return "HQ NOS PCM (R2R)"
        }
    }
}

/// Политика маршрутизации тактовых сеток 44.1 кГц и 48 кГц (`ClockGridPolicy`).
public enum ClockGridPolicy: String, CaseIterable, Sendable, Codable {
    /// Кратные 44.1 кГц -> 2.8224/5.6448/11.2896 МГц (DoP 176.4/352.8/705.6k);
    /// кратные 48 кГц -> 3.0720/6.1440/12.2880 МГц (DoP 192/384/768k).
    case adaptiveDualGrid = "adaptiveDualGrid"
    /// Сетка 48 кГц проходит FP64 полифазный ASRC в 176.4 кГц перед модуляцией строго в сетку 44.1k-DSD.
    case strictSACD44k1 = "strictSACD44k1"
    /// Сетка 44.1 кГц идёт в DSD DoP, а сетка 48 кГц идёт в ветку HQ NOS PCM (384/768 кГц).
    case hybrid48kPCM = "hybrid48kPCM"

    public var displayName: String {
        switch self {
        case .adaptiveDualGrid: return "Adaptive Dual-Grid (44.1k & 48k DSD)"
        case .strictSACD44k1: return "Strict SACD 44.1k Grid (FP64 ASRC)"
        case .hybrid48kPCM: return "Hybrid (44.1k DSD / 48k NOS PCM)"
        }
    }
}

/// Выбор аппаратного бэкенда многоступенчатого пре-апсемплера (`OversamplerBackend`).
public enum OversamplerBackendKind: String, CaseIterable, Sendable, Codable {
    /// Accelerate / vDSP / Apple AMX FP64 (Polyphase Kaiser FIR + 2x Half-Band 63/31 + 5-pt Hermite).
    case accelerateAMX = "accelerateAMX"
    /// Metal GPU Compute Overlap-Save с парной арифметикой df64 (Unified Memory Zero-Copy).
    case metalOverlapSave = "metalOverlapSave"

    public static let accelerateAMX64k: OversamplerBackendKind = .accelerateAMX
    public static let metal256k: OversamplerBackendKind = .metalOverlapSave
    public static let metal1M: OversamplerBackendKind = .metalOverlapSave

    public var displayName: String {
        switch self {
        case .accelerateAMX: return "AMX FP64 (64k taps)"
        case .metalOverlapSave: return "Metal GPU df64 (Unified Memory)"
        }
    }

    public var tapCount: Int {
        switch self {
        case .accelerateAMX: return 65_536
        case .metalOverlapSave: return 262_144
        }
    }
}

/// Фазовая характеристика пре-апсемплера.
public enum OversamplerPhaseMode: String, CaseIterable, Sendable, Codable {
    /// Линейно-фазовый фильтр с окном Кайзера (beta = 16, подавление зеркал > 165 дБ).
    case linearPhase = "linearPhase"
    /// Минимально-фазовый аподизирующий фильтр (без предзвона).
    case minimumPhase = "minimumPhase"

    public static let linearPhaseKaiser: OversamplerPhaseMode = .linearPhase
    public static let minimumPhaseApodizing: OversamplerPhaseMode = .minimumPhase

    public var displayName: String {
        switch self {
        case .linearPhase: return "Linear-Phase (Kaiser β=16)"
        case .minimumPhase: return "Minimum-Phase Apodizing"
        }
    }
}

/// Число выживших путей M в дереве поиска Trellis / Viterbi (при окне решений L = 8).
public enum TrellisOrder: Int, CaseIterable, Sendable, Codable {
    case m1  = 1
    case m4  = 4
    case m8  = 8
    case m16 = 16

    public static let trellis1: TrellisOrder = .m1
    public static let trellis4: TrellisOrder = .m4
    public static let trellis8: TrellisOrder = .m8
    public static let trellis16: TrellisOrder = .m16

    public var displayName: String {
        switch self {
        case .m1:  return "M=1 (Classic 7EC)"
        case .m4:  return "M=4 (Light Trellis)"
        case .m8:  return "M=8 (Reference M1)"
        case .m16: return "M=16 (Ultra Trellis)"
        }
    }
}

/// Режим квантователя / шейпера шума для ветки HQ NOS PCM (24/32-bit R2R).
public enum NOSPCMDitherMode: String, CaseIterable, Sendable, Codable {
    /// Треугольный TPDF-дизеринг без окраски шумовой полки.
    case tpdf = "tpdf"
    /// Психоакустический шейпер шума 15-го порядка LNS15.
    case lns15 = "lns15"

    public var displayName: String {
        switch self {
        case .tpdf: return "TPDF Dither"
        case .lns15: return "LNS15 Noise Shaper"
        }
    }
}

/// Конфигурация гибридного DSP-движка.
public struct EngineConfiguration: Sendable, Codable, Equatable {
    public var mode: DSPEngineMode
    public var profile: SDM7Profile
    public var dsdRate: DSDRateMultiplier
    public var maxNOSPCMRateHz: Int
    public var clockPolicy: ClockGridPolicy
    public var oversamplerBackend: OversamplerBackendKind
    public var phaseMode: OversamplerPhaseMode
    public var trellisOrder: TrellisOrder
    public var isiRegularizerEnabled: Bool
    /// Прецизионный входной запас по уровню в дБ (-2.0 ... -6.0 dB, по умолчанию -3.5 dB).
    public var headroomDB: Double
    /// Автоматическая защита от межсэмпловых пиков (ISP > -0.5 dBFS).
    public var ispProtectionEnabled: Bool
    public var nosDitherMode: NOSPCMDitherMode
    /// Длительность чанка конвейера в мс (20 или 40 мс; по умолчанию 40 мс).
    public var chunkDurationMs: Int
    /// Эксклюзивный захват USB DDC в Hog Mode + отключение системного микшера.
    public var hogModeEnabled: Bool
    /// UID целевого аудиоустройства вывода CoreAudio (nil = текущее выбранное устройство).
    public var targetDeviceUID: String?

    public init(
        mode: DSPEngineMode = .bitPerfectPassthrough,
        profile: SDM7Profile = .balanced,
        dsdRate: DSDRateMultiplier = .dsd256,
        maxNOSPCMRateHz: Int = 768_000,
        clockPolicy: ClockGridPolicy = .strictSACD44k1,
        oversamplerBackend: OversamplerBackendKind = .accelerateAMX,
        phaseMode: OversamplerPhaseMode = .linearPhase,
        trellisOrder: TrellisOrder = .m8,
        isiRegularizerEnabled: Bool = true,
        headroomDB: Double = -3.5,
        ispProtectionEnabled: Bool = true,
        nosDitherMode: NOSPCMDitherMode = .lns15,
        chunkDurationMs: Int = 40,
        hogModeEnabled: Bool = true,
        targetDeviceUID: String? = nil
    ) {
        self.mode = mode
        self.profile = profile
        self.dsdRate = dsdRate
        self.maxNOSPCMRateHz = max(176_400, min(768_000, maxNOSPCMRateHz))
        self.clockPolicy = clockPolicy
        self.oversamplerBackend = oversamplerBackend
        self.phaseMode = phaseMode
        self.trellisOrder = trellisOrder
        self.isiRegularizerEnabled = isiRegularizerEnabled
        self.headroomDB = max(-12.0, min(0.0, headroomDB))
        self.ispProtectionEnabled = ispProtectionEnabled
        self.nosDitherMode = nosDitherMode
        self.chunkDurationMs = (chunkDurationMs <= 20) ? 20 : 40
        self.hogModeEnabled = hogModeEnabled
        self.targetDeviceUID = targetDeviceUID
    }

    /// Линейный множитель аттенюации входа (для -3.5 dB равен 0.6683439175686146).
    @inlinable
    public var linearHeadroomGain: Double {
        pow(10.0, headroomDB / 20.0)
    }
}

/// Живая телеметрия DSP-движка для UI macOS и мобильных/десктопных клиентов PWA.
public struct EngineTelemetry: Sendable, Codable, Equatable {
    public var isRunning: Bool
    public var activeMode: DSPEngineMode
    public var inputSampleRateHz: Int
    public var outputSampleRateHz: Int
    public var dopCarrierRateHz: Int
    public var activeClockGrid: BaseClockGrid
    public var isHogModeActive: Bool
    public var isIntegerModeActive: Bool
    public var maxIntegratorState: Double
    public var ispClipCount: UInt64
    public var underrunCount: UInt64
    public var ringBufferFillPercent: Double
    public var processingLoadPercent: Double
    public var outputDeviceName: String

    public init(
        isRunning: Bool = false,
        activeMode: DSPEngineMode = .bitPerfectPassthrough,
        inputSampleRateHz: Int = 44_100,
        outputSampleRateHz: Int = 44_100,
        dopCarrierRateHz: Int = 44_100,
        activeClockGrid: BaseClockGrid = .grid44k1,
        isHogModeActive: Bool = false,
        isIntegerModeActive: Bool = false,
        maxIntegratorState: Double = 0.0,
        ispClipCount: UInt64 = 0,
        underrunCount: UInt64 = 0,
        ringBufferFillPercent: Double = 0.0,
        processingLoadPercent: Double = 0.0,
        outputDeviceName: String = ""
    ) {
        self.isRunning = isRunning
        self.activeMode = activeMode
        self.inputSampleRateHz = inputSampleRateHz
        self.outputSampleRateHz = outputSampleRateHz
        self.dopCarrierRateHz = dopCarrierRateHz
        self.activeClockGrid = activeClockGrid
        self.isHogModeActive = isHogModeActive
        self.isIntegerModeActive = isIntegerModeActive
        self.maxIntegratorState = maxIntegratorState
        self.ispClipCount = ispClipCount
        self.underrunCount = underrunCount
        self.ringBufferFillPercent = ringBufferFillPercent
        self.processingLoadPercent = processingLoadPercent
        self.outputDeviceName = outputDeviceName
    }
}

extension SDM7Profile {
    public var displayName: String {
        switch self {
        case .transient: return "7EC-Transient"
        case .balanced: return "7EC-Balanced"
        case .superWide: return "7EC-Super"
        }
    }
}

public typealias SDMClockGrid = BaseClockGrid
