//
//  MasteringRestorationModels.swift
//  AppleMusicRemoteMac
//
//  Modes, Localization & Telemetry Models for 64-Bit Studio Mastering Pre-DSP Suite.
//

import Foundation

public enum MasteringDeClipMode: String, Codable, CaseIterable, Sendable {
    case off = "off"
    case auto = "auto"
    case gentle = "gentle"
    case studio = "studio"

    public var isEnabled: Bool {
        self != .off
    }

    public func title(isEnglish: Bool) -> String {
        switch self {
        case .off:
            return isEnglish ? "Off (100% Bit-Perfect)" : "Выкл (100% Bit-Perfect)"
        case .auto:
            return isEnglish ? "Auto — Smart Guard (DR ≤ 10)" : "Авто — Умная защита (DR ≤ 10)"
        case .gentle:
            return isEnglish ? "Gentle (up to +2.8 dB peaks)" : "Деликатный (до +2.8 дБ пиков)"
        case .studio:
            return isEnglish ? "Studio Restoration (up to +4.2 dB)" : "Студийная реставрация (до +4.2 дБ)"
        }
    }

    public func shortLabel(isEnglish: Bool) -> String {
        switch self {
        case .off:
            return isEnglish ? "Off" : "Выкл"
        case .auto:
            return isEnglish ? "Smart De-Clip" : "Авто De-Clip"
        case .gentle:
            return isEnglish ? "Gentle De-Clip" : "Деликатный De-Clip"
        case .studio:
            return isEnglish ? "Studio De-Clip" : "Студийный De-Clip"
        }
    }

    public func subtitle(isEnglish: Bool) -> String {
        switch self {
        case .off:
            return isEnglish
                ? "100% Bit-Perfect passthrough without waveform peak reconstruction."
                : "Прямой 100% Bit-Perfect тракт без реконструкции срезанных верхушек волны."
        case .auto:
            return isEnglish
                ? "Automatically reconstructs shaved 0 dBFS brickwall plateaus on compressed masters while leaving DR11+ audiophile recordings untouched."
                : "Автоматически достраивает срезанные «полки» кирпичного лимитера на зажатых ремастерах, не вмешиваясь в чистые записи DR11+."
        case .gentle:
            return isEnglish
                ? "Smooth 64-bit cubic Hermite transient peak restoration up to +2.8 dB with C1 slope continuity."
                : "Деликатная 64-битная кубическая Эрмитова реконструкция транзиентов до +2.8 дБ с гладкой сшивкой склонов."
        case .studio:
            return isEnglish
                ? "Deep mastering crest reconstruction up to +4.2 dB for heavily clipped Loudness War (DR4–DR7) rock, metal & pop remasters."
                : "Глубокое восстановление динамических пиков до +4.2 дБ для жёстко зажатых ремастеров «Войны громкости» (DR4–DR7)."
        }
    }
}

public enum MasteringDeEsserMode: String, Codable, CaseIterable, Sendable {
    case off = "off"
    case gentle = "gentle"
    case vocal = "vocal"

    public var isEnabled: Bool {
        self != .off
    }

    public func title(isEnglish: Bool) -> String {
        switch self {
        case .off:
            return isEnglish ? "Off (100% Bit-Perfect)" : "Выкл (100% Bit-Perfect)"
        case .gentle:
            return isEnglish ? "Gentle — Planars / Bright HF (up to -3.5 dB)" : "Деликатный — Планары / Яркий ВЧ (до -3.5 дБ)"
        case .vocal:
            return isEnglish ? "Weiss Studio — Harsh Sibilance (up to -6.0 dB)" : "Студийный Weiss — Резкий вокал (до -6.0 дБ)"
        }
    }

    public func shortLabel(isEnglish: Bool) -> String {
        switch self {
        case .off:
            return isEnglish ? "Off" : "Выкл"
        case .gentle:
            return isEnglish ? "Gentle De-Esser" : "Деликатный De-Esser"
        case .vocal:
            return isEnglish ? "Weiss De-Esser" : "Weiss De-Esser"
        }
    }

    public func subtitle(isEnglish: Bool) -> String {
        switch self {
        case .off:
            return isEnglish
                ? "100% Bit-Perfect passthrough without high-frequency dynamic sibilance control."
                : "Прямой 100% Bit-Perfect тракт без динамического подавления сибилянтов."
        case .gentle:
            return isEnglish
                ? "Level-independent relative detector (7.0 kHz) taming piercing 'S/T' glare up to -3.5 dB on planar headphones and bright tweeters while preserving cymbal air."
                : "Относительный детектор в духе Weiss DAC501 (7.0 кГц): смягчает колкие сибилянтов до -3.5 дБ на планарах и ярких АС, сохраняя воздух тарелок."
        case .vocal:
            return isEnglish
                ? "Mastering-grade relative sibilance control (6.5 kHz, up to -6.0 dB, 0.8 ms attack) eliminating harsh vocal 'S/SH/TS' spikes at any volume."
                : "Студийное подавление резких вокальных «с/ц/ш» (6.5 кГц, до -6.0 дБ, атака 0.8 мс) с одинаковой точностью на шёпоте и в тутти."
        }
    }
}

public struct MasteringRestorationTelemetrySnapshot: Sendable, Equatable {
    public var restoredPeakDB: Double = 0.0
    public var reconstructedClipsCount: UInt64 = 0
    public var deEsserGainReductionDB: Double = 0.0
    public var autoBypassedCleanMaster: Bool = false

    public init(
        restoredPeakDB: Double = 0.0,
        reconstructedClipsCount: UInt64 = 0,
        deEsserGainReductionDB: Double = 0.0,
        autoBypassedCleanMaster: Bool = false
    ) {
        self.restoredPeakDB = restoredPeakDB
        self.reconstructedClipsCount = reconstructedClipsCount
        self.deEsserGainReductionDB = deEsserGainReductionDB
        self.autoBypassedCleanMaster = autoBypassedCleanMaster
    }
}
