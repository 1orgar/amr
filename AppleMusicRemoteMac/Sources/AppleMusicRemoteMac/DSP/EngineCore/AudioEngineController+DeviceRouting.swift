//
//  AudioEngineController+DeviceRouting.swift
//  AppleMusicRemoteMac
//
//  USB DAC Eligibility, Anti-Oscillation Pinning, Silence Pre-Fill, Telemetry & Configuration Persistence.
//

import CoreAudio
import Darwin
import Foundation

extension AudioEngineController {

    // MARK: - Silence Pre-Fill & Device Eligibility

    internal func prefillOutputSilence(route: SampleRateRouteDecision, frames: Int) {
        let clampedFrames = min(frames, 131_072)
        guard clampedFrames > 0 else { return }
        let wordCount = clampedFrames * 2
        let temp = UnsafeMutablePointer<Int32>.allocate(capacity: wordCount)
        defer { temp.deallocate() }

        if route.effectiveMode == .sdmDoP {
            DoPPackerState.fillSilenceStereo32(
                state: &dopPackerState,
                interleavedOutput: temp,
                frameCount: clampedFrames
            )
        } else {
            memset(temp, 0, wordCount * MemoryLayout<Int32>.stride)
        }
        _ = outputRingBuffer.write(from: temp, wordCount: wordCount)
    }

    internal func supportsDoPCarrier(_ deviceID: AudioDeviceID) -> Bool {
        guard deviceID != 0, HALDeviceManager.isEligibleExternalDACDevice(deviceID) else { return false }
        let rates = halManager.supportedSampleRates(deviceID: deviceID)
        return rates.contains(where: { $0 >= 176_399.0 })
    }

    public nonisolated func isDeviceEligible(_ device: AudioOutputDevice, for mode: DSPEngineMode) -> Bool {
        switch mode {
        case .bitPerfectPassthrough:
            return true
        case .hqNOSPCM:
            return device.supportsNOS
        case .sdmDoP:
            return device.supportsDSDDoP
        }
    }

    public struct USBDACAvailabilitySummary: Sendable, Equatable {
        public let hasEligibleUSBDAC: Bool
        public let supportsNOS: Bool
        public let supportsDSDDoP: Bool
        public let maxDSDRate: Int
        public let activeTransportType: String
        public let eligibleDeviceName: String?

        public func isModeSupported(_ mode: DSPEngineMode, dsdRate: DSDRateMultiplier? = nil) -> Bool {
            switch mode {
            case .bitPerfectPassthrough:
                return true
            case .hqNOSPCM:
                return supportsNOS
            case .sdmDoP:
                guard supportsDSDDoP else { return false }
                if let reqRate = dsdRate {
                    return maxDSDRate >= reqRate.rawValue || maxDSDRate >= 64
                }
                return true
            }
        }
    }

    public nonisolated func currentUSBDACAvailability(targetDeviceUID: String? = nil) -> USBDACAvailabilitySummary {
        let devices = CoreAudioDeviceManager.shared.getOutputDevices().filter {
            !$0.name.contains("AMR Tap Aggregate") && !$0.uid.contains("AMR-Tap-Aggregate")
        }
        let defDev = devices.first(where: { $0.isDefault }) ?? CoreAudioDeviceManager.shared.getDefaultOutputDevice()
        let activeTransport = defDev?.transportType ?? "unknown"

        if let uid = targetDeviceUID, !uid.isEmpty {
            if let target = devices.first(where: { $0.uid == uid }) {
                return USBDACAvailabilitySummary(
                    hasEligibleUSBDAC: target.supportsNOS || target.supportsDSDDoP,
                    supportsNOS: target.supportsNOS,
                    supportsDSDDoP: target.supportsDSDDoP,
                    maxDSDRate: target.maxDSDRate,
                    activeTransportType: target.transportType,
                    eligibleDeviceName: (target.supportsNOS || target.supportsDSDDoP) ? target.name : nil
                )
            }
            return USBDACAvailabilitySummary(
                hasEligibleUSBDAC: false,
                supportsNOS: false,
                supportsDSDDoP: false,
                maxDSDRate: 0,
                activeTransportType: activeTransport,
                eligibleDeviceName: nil
            )
        }

        let pinnedUID = withStateLock { _pinnedAutoDeviceUID }
        let candidateUSB: AudioOutputDevice? = {
            if let def = defDev, (def.supportsNOS || def.supportsDSDDoP) {
                return def
            }
            if let pinned = pinnedUID, let pinnedDev = devices.first(where: { $0.uid == pinned && ($0.supportsNOS || $0.supportsDSDDoP) }) {
                return pinnedDev
            }
            return devices.first(where: { $0.supportsNOS || $0.supportsDSDDoP })
        }()

        if let usb = candidateUSB {
            return USBDACAvailabilitySummary(
                hasEligibleUSBDAC: true,
                supportsNOS: usb.supportsNOS,
                supportsDSDDoP: usb.supportsDSDDoP,
                maxDSDRate: usb.maxDSDRate,
                activeTransportType: activeTransport,
                eligibleDeviceName: usb.name
            )
        }

        return USBDACAvailabilitySummary(
            hasEligibleUSBDAC: false,
            supportsNOS: false,
            supportsDSDDoP: false,
            maxDSDRate: 0,
            activeTransportType: activeTransport,
            eligibleDeviceName: nil
        )
    }

    internal func resolveTargetOutputDevice(cfg: EngineConfiguration) -> (id: AudioDeviceID, uid: String, name: String)? {
        let devices = CoreAudioDeviceManager.shared.getOutputDevices().filter {
            !$0.name.contains("AMR Tap Aggregate") && !$0.uid.contains("AMR-Tap-Aggregate")
        }

        if let uid = cfg.targetDeviceUID, !uid.isEmpty {
            guard let chosen = devices.first(where: { $0.uid == uid }),
                  isDeviceEligible(chosen, for: cfg.mode) else {
                return nil
            }
            return (chosen.id, chosen.uid, chosen.name)
        }

        let defDev = devices.first(where: { $0.isDefault }) ?? CoreAudioDeviceManager.shared.getDefaultOutputDevice()
        let pinnedUID = withStateLock { _pinnedAutoDeviceUID }

        // 1. Если текущее системное устройство — валидный внешний USB ЦАП с поддержкой выбранного режима (DSD DoP / HQ NOS), закрепляем его
        if let def = defDev, !def.name.contains("AMR Tap Aggregate"), isDeviceEligible(def, for: cfg.mode) {
            withStateLock { _pinnedAutoDeviceUID = def.uid }
            return (def.id, def.uid, def.name)
        }

        // 2. Если macOS эвакуировала системный выход на встроенные динамики из-за нашего Hog Mode,
        // удерживаем закреплённый внешний USB ЦАП, пока он физически подключён по USB!
        if let pinned = pinnedUID,
           let stillConnected = devices.first(where: { $0.uid == pinned }),
           isDeviceEligible(stillConnected, for: cfg.mode) {
            return (stillConnected.id, stillConnected.uid, stillConnected.name)
        }

        // 3. Автоматический поиск подключённого внешнего USB ЦАП, поддерживающего выбранный режим
        if let extUSB = devices.first(where: { isDeviceEligible($0, for: cfg.mode) }) {
            withStateLock { _pinnedAutoDeviceUID = extUSB.uid }
            return (extUSB.id, extUSB.uid, extUSB.name)
        }

        return nil
    }

    // MARK: - Telemetry & Persistence

    internal func refreshTelemetrySnapshot() {
        let hogLocked = halManager.isHogModeLocked
        let intMode = (halManager.negotiatedPhysicalFormat?.isIntegerMode ?? false)
        let clips = headroomISP.ispClipCount
        let underruns = outputRingBuffer.underrunCount
        let fillPct = outputRingBuffer.fillPercentage

        withStateLock {
            let route = _activeRoute
            let active = _isPipelineActive
            _cachedTelemetry.isRunning = active
            _cachedTelemetry.activeMode = active ? route.effectiveMode : .bitPerfectPassthrough
            _cachedTelemetry.inputSampleRateHz = route.inputSampleRateHz
            _cachedTelemetry.outputSampleRateHz = active ? route.targetModulatorRateHz : route.inputSampleRateHz
            _cachedTelemetry.dopCarrierRateHz = active ? route.dopCarrierRateHz : route.inputSampleRateHz
            _cachedTelemetry.activeClockGrid = route.baseGrid
            _cachedTelemetry.isHogModeActive = active && hogLocked
            _cachedTelemetry.isIntegerModeActive = active && intMode
            _cachedTelemetry.ispClipCount = clips
            _cachedTelemetry.underrunCount = underruns
            _cachedTelemetry.ringBufferFillPercent = fillPct
            _cachedTelemetry.outputDeviceName = active ? _activeOutputDeviceName : ""
            if !active {
                _cachedTelemetry.processingLoadPercent = 0.0
            }
        }
    }

    internal static func loadPersistedConfiguration() -> EngineConfiguration {
        if isTestingEnvironment {
            return EngineConfiguration()
        }
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode(EngineConfiguration.self, from: data) {
            return decoded
        }
        if let legacyData = UserDefaults.standard.data(forKey: legacyUserDefaultsKeyV1),
           var legacyDecoded = try? JSONDecoder().decode(EngineConfiguration.self, from: legacyData) {
            if legacyDecoded.clockPolicy == .adaptiveDualGrid {
                legacyDecoded.clockPolicy = .strictSACD44k1
            }
            persistConfiguration(legacyDecoded)
            return legacyDecoded
        }
        return EngineConfiguration()
    }

    internal static func persistConfiguration(_ config: EngineConfiguration) {
        guard !isTestingEnvironment else { return }
        if let encoded = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
}
