import Foundation

/// Результат маршрутизации тактовой сетки для текущей входной частоты дискретизации трека.
@frozen
public struct SampleRateRouteDecision: Sendable, Equatable {
    public let effectiveMode: DSPEngineMode
    public let inputSampleRateHz: Int
    public let baseGrid: BaseClockGrid
    public let dsdMultiplier: DSDRateMultiplier
    public let targetModulatorRateHz: Int
    public let dopCarrierRateHz: Int
    public let usesASRC: Bool
    public let usesDXDBypass: Bool

    public init(
        effectiveMode: DSPEngineMode,
        inputSampleRateHz: Int,
        baseGrid: BaseClockGrid,
        dsdMultiplier: DSDRateMultiplier,
        targetModulatorRateHz: Int,
        dopCarrierRateHz: Int,
        usesASRC: Bool,
        usesDXDBypass: Bool
    ) {
        self.effectiveMode = effectiveMode
        self.inputSampleRateHz = inputSampleRateHz
        self.baseGrid = baseGrid
        self.dsdMultiplier = dsdMultiplier
        self.targetModulatorRateHz = targetModulatorRateHz
        self.dopCarrierRateHz = dopCarrierRateHz
        self.usesASRC = usesASRC
        self.usesDXDBypass = usesDXDBypass
    }
}

/// Интеллектуальный маршрутизатор тактовых сеток `44.1 кГц` и `48 кГц` (Раздел 3.1.1 ТЗ).
///
/// Поддерживает 3 политики тактования:
/// 1. `.adaptiveDualGrid` (по умолчанию): кратные `44.1 кГц` (`44.1/88.2/176.4/352.8`) -> сетка `44.1 кГц`
///    (`DoP 705.6 кГц`, `DSD256 11.2896 МГц`); кратные `48 кГц` (`48/96/192/384`) -> сетка `48 кГц`
///    (`DoP 768 кГц`, `DSD256 12.288 МГц`) при поддержке ЦАП.
/// 2. `.strictSACD44k1`: принудительная фиксация на сетке `44.1 кГц` (`11.2896 МГц`) для ЦАП,
///    не принимающих маркеры DoP на частотах `192/384/768 кГц`, с включением полифазного `FP64` ASRC.
/// 3. `.hybrid48kPCM`: `DSD256` (`11.2896 МГц`) для семейства `44.1 кГц` и автоматический переход
///    в `HQ NOS PCM (768/384 кГц)` с шейпером `LNS15` для семейства `48 кГц` без пересчёта сеток.
public enum SampleRateRouter {
    public static func resolveRoute(
        inputSampleRateHz: Int,
        configuration: EngineConfiguration,
        supportedDeviceSampleRates: [Double] = []
    ) -> SampleRateRouteDecision {
        let inRate = max(44_100, inputSampleRateHz)
        let isInput48kFamily = (inRate % 48_000 == 0) && (inRate % 44_100 != 0)
        let isDXDSource = (inRate >= 352_800)

        // 1. Bit-Perfect Passthrough
        if configuration.mode == .bitPerfectPassthrough {
            let grid: BaseClockGrid = isInput48kFamily ? .grid48k : .grid44k1
            return SampleRateRouteDecision(
                effectiveMode: .bitPerfectPassthrough,
                inputSampleRateHz: inRate,
                baseGrid: grid,
                dsdMultiplier: configuration.dsdRate,
                targetModulatorRateHz: inRate,
                dopCarrierRateHz: inRate,
                usesASRC: false,
                usesDXDBypass: false
            )
        }

        // 2. HQ NOS PCM (705.6 / 768 kHz или 352.8 / 384 kHz с учётом потолка configuration.maxNOSPCMRateHz)
        if configuration.mode == .hqNOSPCM {
            let grid: BaseClockGrid = isInput48kFamily ? .grid48k : .grid44k1
            let gridMax = (grid == .grid48k) ? 768_000 : 705_600
            let fallbackDXD = (grid == .grid48k) ? 384_000 : 352_800
            let preferredMax = min(gridMax, max(inRate, configuration.maxNOSPCMRateHz))
            let outRate = pickHighestSupportedPCM(
                preferred: preferredMax,
                fallback: min(preferredMax, fallbackDXD),
                inputRate: inRate,
                supportedRates: supportedDeviceSampleRates
            )
            return SampleRateRouteDecision(
                effectiveMode: .hqNOSPCM,
                inputSampleRateHz: inRate,
                baseGrid: grid,
                dsdMultiplier: configuration.dsdRate,
                targetModulatorRateHz: outRate,
                dopCarrierRateHz: outRate,
                usesASRC: false,
                usesDXDBypass: isDXDSource
            )
        }

        // 3. Гибридный режим 48k -> HQ NOS PCM (Policy C: .hybrid48kPCM)
        if configuration.clockPolicy == .hybrid48kPCM && isInput48kFamily {
            let outRate = pickHighestSupportedPCM(
                preferred: 768_000,
                fallback: 384_000,
                inputRate: inRate,
                supportedRates: supportedDeviceSampleRates
            )
            return SampleRateRouteDecision(
                effectiveMode: .hqNOSPCM,
                inputSampleRateHz: inRate,
                baseGrid: .grid48k,
                dsdMultiplier: configuration.dsdRate,
                targetModulatorRateHz: outRate,
                dopCarrierRateHz: outRate,
                usesASRC: false,
                usesDXDBypass: isDXDSource
            )
        }

        // 4. Режим DSD (DoP64 / DoP128 / DoP256 / DoP512)
        let targetGrid: BaseClockGrid
        let usesASRC: Bool

        switch configuration.clockPolicy {
        case .strictSACD44k1:
            targetGrid = .grid44k1
            usesASRC = isInput48kFamily
        case .adaptiveDualGrid, .hybrid48kPCM:
            if isInput48kFamily {
                // Проверяем, поддерживает ли ЦАП сетку 48k на высоких частотах DoP (192/384/768 кГц)
                let desired48kDoP = (48_000 * configuration.dsdRate.rawValue) / 16
                let supports48kDoP = supportedDeviceSampleRates.isEmpty
                    || supportedDeviceSampleRates.contains(where: { abs($0 - Double(desired48kDoP)) < 1.0 })
                if supports48kDoP {
                    targetGrid = .grid48k
                    usesASRC = false
                } else {
                    targetGrid = .grid44k1
                    usesASRC = true
                }
            } else {
                targetGrid = .grid44k1
                usesASRC = false
            }
        }

        // Подбираем максимальную поддерживаемую ЦАП кратность DSD (не выше запрошенной в конфигурации)
        let negotiated = negotiateDSDMultiplier(
            preferred: configuration.dsdRate,
            grid: targetGrid,
            supportedRates: supportedDeviceSampleRates
        )
        let dsdClockHz = targetGrid.rawValue * negotiated.rawValue
        let dopCarrierHz = dsdClockHz / 16

        // Правило малого OSR (Раздел 2.2.2 ТЗ):
        // если отношение целевой частоты DSD к входной частоте F_DSD / F_in < 32
        // (например, DXD 352.8/384 кГц при потолке DSD128 или 705.6/768 кГц при DSD256),
        // дельта-сигма модулятор автоматически переводится в прямой HQ NOS / Bit-Perfect PCM Bypass.
        if dsdClockHz / inRate < 32 {
            let pcmGrid: BaseClockGrid = isInput48kFamily ? .grid48k : .grid44k1
            let preferredMax = (pcmGrid == .grid48k) ? 768_000 : 705_600
            let fallbackDXD = (pcmGrid == .grid48k) ? 384_000 : 352_800
            let outRate = pickHighestSupportedPCM(
                preferred: max(inRate, fallbackDXD),
                fallback: min(inRate, preferredMax),
                inputRate: inRate,
                supportedRates: supportedDeviceSampleRates
            )
            return SampleRateRouteDecision(
                effectiveMode: .hqNOSPCM,
                inputSampleRateHz: inRate,
                baseGrid: pcmGrid,
                dsdMultiplier: negotiated,
                targetModulatorRateHz: outRate,
                dopCarrierRateHz: outRate,
                usesASRC: false,
                usesDXDBypass: true
            )
        }

        // При входе DXD (352.8 / 384 кГц) и F_DSD / F_in >= 32 (например, DSD256 / DSD512)
        // пропускается первый каскад полифазного FIR-фильтра (Stage 1 DXD Bypass).
        let dxdBypass = isDXDSource && !usesASRC

        return SampleRateRouteDecision(
            effectiveMode: .sdmDoP,
            inputSampleRateHz: inRate,
            baseGrid: targetGrid,
            dsdMultiplier: negotiated,
            targetModulatorRateHz: dsdClockHz,
            dopCarrierRateHz: dopCarrierHz,
            usesASRC: usesASRC,
            usesDXDBypass: dxdBypass
        )
    }

    private static func negotiateDSDMultiplier(
        preferred: DSDRateMultiplier,
        grid: BaseClockGrid,
        supportedRates: [Double]
    ) -> DSDRateMultiplier {
        guard !supportedRates.isEmpty else { return preferred }
        let candidates: [DSDRateMultiplier] = [.dsd512, .dsd256, .dsd128, .dsd64].filter {
            $0.rawValue <= preferred.rawValue
        }
        for mult in candidates {
            let dopRate = Double((grid.rawValue * mult.rawValue) / 16)
            if supportedRates.contains(where: { abs($0 - dopRate) < 1.0 }) {
                return mult
            }
        }
        return .dsd64
    }

    private static func pickHighestSupportedPCM(
        preferred: Int,
        fallback: Int,
        inputRate: Int,
        supportedRates: [Double]
    ) -> Int {
        guard !supportedRates.isEmpty else { return preferred }
        for cand in [preferred, fallback, fallback / 2, inputRate] {
            if supportedRates.contains(where: { abs($0 - Double(cand)) < 1.0 }) {
                return cand
            }
        }
        return inputRate
    }
}
