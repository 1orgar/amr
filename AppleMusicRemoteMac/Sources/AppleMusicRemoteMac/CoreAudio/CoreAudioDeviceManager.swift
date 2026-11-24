//
//  CoreAudioDeviceManager.swift
//  AppleMusicRemoteMac
//
//  CoreAudio Hardware Device Management & Bit-Perfect Sample Rate Control
//  Inspired by Choritsu (jcongaku/apple-music-lossless-eq)
//

import Foundation
import CoreAudio

public struct DeviceDSPCapabilities: Sendable, Equatable {
    public let transportType: String
    public let isUSB: Bool
    public let maxBitDepth: Int
    public let supportsNOS: Bool
    public let supportsDSDDoP: Bool
    public let maxDSDRate: Int

    public init(
        transportType: String,
        isUSB: Bool,
        maxBitDepth: Int,
        supportsNOS: Bool,
        supportsDSDDoP: Bool,
        maxDSDRate: Int
    ) {
        self.transportType = transportType
        self.isUSB = isUSB
        self.maxBitDepth = maxBitDepth
        self.supportsNOS = supportsNOS
        self.supportsDSDDoP = supportsDSDDoP
        self.maxDSDRate = maxDSDRate
    }
}

public struct AudioOutputDevice: Identifiable, Hashable, Sendable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public let iconName: String
    public let currentSampleRate: Double
    public let availableSampleRates: [Double]
    public let isDefault: Bool
    public let transportType: String
    public let isUSB: Bool
    public let maxBitDepth: Int
    public let supportsNOS: Bool
    public let supportsDSDDoP: Bool
    public let maxDSDRate: Int

    public init(
        id: AudioDeviceID,
        uid: String,
        name: String,
        iconName: String,
        currentSampleRate: Double,
        availableSampleRates: [Double],
        isDefault: Bool,
        transportType: String = "unknown",
        isUSB: Bool = false,
        maxBitDepth: Int = 24,
        supportsNOS: Bool = false,
        supportsDSDDoP: Bool = false,
        maxDSDRate: Int = 0
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.iconName = iconName
        self.currentSampleRate = currentSampleRate
        self.availableSampleRates = availableSampleRates
        self.isDefault = isDefault
        self.transportType = transportType
        self.isUSB = isUSB
        self.maxBitDepth = maxBitDepth
        self.supportsNOS = supportsNOS
        self.supportsDSDDoP = supportsDSDDoP
        self.maxDSDRate = maxDSDRate
    }

    public var dictionary: [String: Any] {
        [
            "id": Int(id),
            "uid": uid,
            "name": name,
            "icon": iconName,
            "currentSampleRate": currentSampleRate,
            "availableSampleRates": availableSampleRates,
            "isDefault": isDefault,
            "transportType": transportType,
            "isUSB": isUSB,
            "maxBitDepth": maxBitDepth,
            "supportsNOS": supportsNOS,
            "supportsDSDDoP": supportsDSDDoP,
            "maxDSDRate": maxDSDRate
        ]
    }
}

public final class CoreAudioDeviceManager: @unchecked Sendable {
    public static let shared = CoreAudioDeviceManager()

    private let handlersLock = NSLock()
    private var _onDevicesChanged: (([AudioOutputDevice]) -> Void)?
    private var devicesChangedObservers: [String: ([AudioOutputDevice]) -> Void] = [:]
    private var _onSampleRateChanged: ((AudioDeviceID, Double) -> Void)?
    private var sampleRateChangedObservers: [String: (AudioDeviceID, Double) -> Void] = [:]

    public func addDevicesChangedObserver(id: String, handler: @escaping ([AudioOutputDevice]) -> Void) {
        handlersLock.lock()
        devicesChangedObservers[id] = handler
        handlersLock.unlock()
    }

    public func addSampleRateChangedObserver(id: String, handler: @escaping (AudioDeviceID, Double) -> Void) {
        handlersLock.lock()
        sampleRateChangedObservers[id] = handler
        handlersLock.unlock()
    }

    public var onDevicesChanged: (([AudioOutputDevice]) -> Void)? {
        get {
            handlersLock.lock()
            let primary = _onDevicesChanged
            let observers = Array(devicesChangedObservers.values)
            handlersLock.unlock()
            guard primary != nil || !observers.isEmpty else { return nil }
            return { devices in
                primary?(devices)
                for observer in observers {
                    observer(devices)
                }
            }
        }
        set {
            handlersLock.lock()
            _onDevicesChanged = newValue
            handlersLock.unlock()
        }
    }

    public var onSampleRateChanged: ((AudioDeviceID, Double) -> Void)? {
        get {
            handlersLock.lock()
            let primary = _onSampleRateChanged
            let observers = Array(sampleRateChangedObservers.values)
            handlersLock.unlock()
            guard primary != nil || !observers.isEmpty else { return nil }
            return { deviceID, rate in
                primary?(deviceID, rate)
                for observer in observers {
                    observer(deviceID, rate)
                }
            }
        }
        set {
            handlersLock.lock()
            _onSampleRateChanged = newValue
            handlersLock.unlock()
        }
    }

    // MARK: - DAC Muting Guard Configuration & Telemetry

    private static let keyMutingGuardEnabled = "DACMutingGuardEnabled"
    private static let keyMutingGuardDurationMs = "DACMutingGuardDurationMs"
    public static let supportedMutingGuardDurationsMs: [Int] = [50, 100, 150, 250]

    internal let mutingGuardLock = NSLock()
    internal let mutingGuardQueue = DispatchQueue(label: "org.ksholokhov.amr.dacmutingguard", qos: .userInteractive)
    internal var unmuteWorkItem: DispatchWorkItem?
    internal var mutingGuardGeneration: UInt64 = 0
    internal var isMutingGuardEnabledInternal: Bool
    internal var mutingGuardDurationMsInternal: Int
    internal var isMutingGuardActiveInternal: Bool = false
    internal var mutingGuardActivationCountInternal: Int = 0
    internal var preGuardAppVolume: Int?
    internal var pendingAsyncVolumeRestoreTarget: Int?
    internal var preGuardWasDucked: Bool = false
    internal var preGuardUnduckedVolume: Int?
    internal var hardwareMutedDeviceID: AudioDeviceID?

    /// Whether DAC Muting Guard (click-free relay switching) is enabled in app configuration.
    public var isMutingGuardEnabled: Bool {
        get {
            mutingGuardLock.lock()
            defer { mutingGuardLock.unlock() }
            return isMutingGuardEnabledInternal
        }
        set {
            mutingGuardLock.lock()
            let changed = (isMutingGuardEnabledInternal != newValue)
            isMutingGuardEnabledInternal = newValue
            UserDefaults.standard.set(newValue, forKey: Self.keyMutingGuardEnabled)
            mutingGuardLock.unlock()
            if changed {
                NSLog("[CoreAudioDeviceManager] 🔇 DAC Muting Guard is now: %@", newValue ? "ON (\(mutingGuardDurationMs) ms)" : "OFF")
            }
        }
    }

    /// Silence pre-pause / relay settling duration in milliseconds (30...500 ms, default 100 ms).
    public var mutingGuardDurationMs: Int {
        get {
            mutingGuardLock.lock()
            defer { mutingGuardLock.unlock() }
            return mutingGuardDurationMsInternal
        }
        set {
            let clamped = max(30, min(500, newValue))
            mutingGuardLock.lock()
            let changed = (mutingGuardDurationMsInternal != clamped)
            mutingGuardDurationMsInternal = clamped
            UserDefaults.standard.set(clamped, forKey: Self.keyMutingGuardDurationMs)
            mutingGuardLock.unlock()
            if changed {
                NSLog("[CoreAudioDeviceManager] ⏱️ DAC Muting Guard duration set to: %d ms", clamped)
            }
        }
    }

    /// True while DAC Muting Guard is actively holding digital silence during a sample-rate switch.
    public var isMutingGuardActive: Bool {
        mutingGuardLock.lock()
        defer { mutingGuardLock.unlock() }
        return isMutingGuardActiveInternal
    }

    /// Total number of times DAC Muting Guard has engaged during this session.
    public var mutingGuardActivationCount: Int {
        mutingGuardLock.lock()
        defer { mutingGuardLock.unlock() }
        return mutingGuardActivationCountInternal
    }

    internal let listenerLock = NSLock()
    internal let halNotifyQueue = DispatchQueue(label: "org.ksholokhov.amr.coreaudio.notify", qos: .utility)
    internal let halWorkerQueue = DispatchQueue(label: "org.ksholokhov.amr.coreaudio.worker", qos: .utility)
    internal var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    internal var sampleRateListenerBlock: AudioObjectPropertyListenerBlock?
    internal var devicesListListenerBlock: AudioObjectPropertyListenerBlock?
    internal var monitoredDeviceID: AudioDeviceID?
    internal var _lastKnownDefaultOutputID: AudioDeviceID = 0

    internal var lastKnownDefaultOutputID: AudioDeviceID {
        get { listenerLock.withLock { _lastKnownDefaultOutputID } }
        set { listenerLock.withLock { _lastKnownDefaultOutputID = newValue } }
    }

    private init() {
        HALDeviceManager.ensureDetachedHALRunLoop()
        if UserDefaults.standard.object(forKey: Self.keyMutingGuardEnabled) == nil {
            self.isMutingGuardEnabledInternal = false
        } else {
            self.isMutingGuardEnabledInternal = UserDefaults.standard.bool(forKey: Self.keyMutingGuardEnabled)
        }
        let savedMs = UserDefaults.standard.integer(forKey: Self.keyMutingGuardDurationMs)
        self.mutingGuardDurationMsInternal = (savedMs >= 30 && savedMs <= 500) ? savedMs : 100
        setupHardwareListeners()
    }

    deinit {
        removeHardwareListeners()
    }

    // MARK: - Device Enumeration

    public func getOutputDevices() -> [AudioOutputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs) == noErr else {
            return []
        }

        let defaultID = getDefaultOutputDeviceID()

        return deviceIDs
            .filter { hasOutputStreams(deviceID: $0) }
            .compactMap { deviceID in
                let name = stringProperty(objectID: deviceID, selector: kAudioObjectPropertyName) ?? "Аудиоустройство"
                let uid = stringProperty(objectID: deviceID, selector: kAudioDevicePropertyDeviceUID) ?? "\(deviceID)"
                let sampleRate = doubleProperty(objectID: deviceID, selector: kAudioDevicePropertyNominalSampleRate) ?? 44100.0
                let availableRates = availableSampleRates(deviceID: deviceID)
                let icon = transportIconName(deviceID: deviceID)
                let rawTransport = uint32Property(objectID: deviceID, selector: kAudioDevicePropertyTransportType)
                let streamCaps = outputStreamCapabilities(deviceID: deviceID)
                let dspCaps = Self.evaluateDSPCapabilities(
                    rawTransport: rawTransport,
                    name: name,
                    uid: uid,
                    availableRates: availableRates,
                    maxBitDepth: streamCaps.maxBitDepth,
                    hasStereoOutput: streamCaps.hasStereoOutput,
                    hasBitTransparentInteger: streamCaps.hasBitTransparentInteger
                )

                return AudioOutputDevice(
                    id: deviceID,
                    uid: uid,
                    name: name,
                    iconName: icon,
                    currentSampleRate: sampleRate,
                    availableSampleRates: availableRates,
                    isDefault: (deviceID == defaultID),
                    transportType: dspCaps.transportType,
                    isUSB: dspCaps.isUSB,
                    maxBitDepth: dspCaps.maxBitDepth,
                    supportsNOS: dspCaps.supportsNOS,
                    supportsDSDDoP: dspCaps.supportsDSDDoP,
                    maxDSDRate: dspCaps.maxDSDRate
                )
            }
    }

    public func getDefaultOutputDevice() -> AudioOutputDevice? {
        guard let defaultID = getDefaultOutputDeviceID() else { return nil }
        let devices = getOutputDevices()
        return devices.first { $0.id == defaultID }
    }

    public func getDefaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    public func setDefaultOutputDevice(id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var newID = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &newID)
        if status == noErr {
            halWorkerQueue.async { [weak self] in
                self?.updateSampleRateMonitoring(for: id)
            }
            return true
        }
        return false
    }

    // MARK: - Sample Rate Control

    public func availableSampleRates(deviceID: AudioDeviceID) -> [Double] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return [] }

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &ranges) == noErr else { return [] }

        let standardRates: [Double] = [
            44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000
        ]
        var rates = Set<Double>()
        for range in ranges {
            if range.mMinimum == range.mMaximum {
                rates.insert(range.mMinimum)
            } else {
                for rate in standardRates where rate >= (range.mMinimum - 0.5) && rate <= (range.mMaximum + 0.5) {
                    rates.insert(rate)
                }
            }
        }
        return rates.sorted()
    }

    public func nearestSupportedSampleRate(_ desired: Double, deviceID: AudioDeviceID) -> Double? {
        let available = availableSampleRates(deviceID: deviceID)
        guard !available.isEmpty else { return desired }

        // Exact match within 0.5 Hz
        if let exact = available.first(where: { abs($0 - desired) < 0.5 }) {
            return exact
        }

        // If user or stream requests high-res rates (>= 176.4k), allow direct attempt
        if desired >= 176400.0 {
            return desired
        }

        // Integer multiple match (e.g. 44.1k track on DAC supporting 88.2k or 176.4k, or vice versa)
        let exactOrMultiple = available.min(by: { abs($0 - desired) < abs($1 - desired) })
        return exactOrMultiple
    }

    @discardableResult
    public func setSampleRate(_ sampleRate: Double, for deviceID: AudioDeviceID? = nil) -> Bool {
        return setFormat(sampleRate: sampleRate, bitDepth: nil, for: deviceID)
    }

    @discardableResult
    public func setFormat(sampleRate: Double, bitDepth: Int? = nil, for deviceID: AudioDeviceID? = nil) -> Bool {
        // Если активен гибридный DSP-конвейер (SDM DoP / HQ NOS PCM), физический ЦАП управляется исключительно
        // через HALDeviceManager в Non-Mixable Integer / Hog Mode — защищаем его от сброса частоты внешними вызовами.
        if AudioEngineController.shared.isActivePipelineHook {
            let activeDSPDevice = AudioEngineController.shared.activeHardwareOutputDeviceID
            if activeDSPDevice != 0 && (deviceID == nil || deviceID == activeDSPDevice) {
                Task {
                    await AudioEngineController.shared.notifySourceSampleRateChanged(sampleRate)
                }
                return true
            }
        }

        guard let targetID = deviceID ?? getDefaultOutputDeviceID() else { return false }
        guard let targetRate = nearestSupportedSampleRate(sampleRate, deviceID: targetID) else { return false }

        let currentRate = doubleProperty(objectID: targetID, selector: kAudioDevicePropertyNominalSampleRate) ?? 0

        let defaultDevID = getDefaultOutputDeviceID()
        let isTargetingDefaultOutput = (deviceID == nil) || (targetID == defaultDevID)

        // If rate is already identical and bit depth does not require modification, skip CoreAudio calls
        let needsRateSwitch = abs(currentRate - targetRate) >= 0.5
        let needsBitDepthSwitch = (bitDepth != nil) && !isCurrentBitDepth(UInt32(bitDepth!), deviceID: targetID, sampleRate: targetRate)
        if !needsRateSwitch && !needsBitDepthSwitch {
            if isTargetingDefaultOutput && RoomAcousticService.shared.isLocalPassthroughEQActive {
                RoomAcousticService.shared.notifyLocalOutputFormatChanged(sampleRateHz: targetRate)
            }
            return true
        }

        let useMutingGuard = isMutingGuardEnabled && (needsRateSwitch || needsBitDepthSwitch)
        let guardMs = mutingGuardDurationMs
        var guardGeneration: UInt64 = 0
        if useMutingGuard {
            guardGeneration = engageMutingGuardPreSwitch(deviceID: targetID, durationMs: guardMs, fromRate: currentRate, toRate: targetRate)
        }

        var rateChanged = false
        var effectiveAppliedRate = currentRate > 0 ? currentRate : targetRate
        if needsRateSwitch {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var isSettable: DarwinBoolean = false
            if AudioObjectHasProperty(targetID, &address),
               AudioObjectIsPropertySettable(targetID, &address, &isSettable) == noErr, isSettable.boolValue {
                var rate = targetRate
                let size = UInt32(MemoryLayout<Double>.size)
                if AudioObjectSetPropertyData(targetID, &address, 0, nil, size, &rate) == noErr {
                    rateChanged = true
                    effectiveAppliedRate = targetRate
                } else {
                    // Fallback when high-res direct attempt (e.g. 192 kHz on 96 kHz max built-in speakers) is rejected by hardware
                    let avail = availableSampleRates(deviceID: targetID)
                    let submultiples = [targetRate / 2.0, targetRate / 4.0]
                    let fallbackCandidate = submultiples.first(where: { sub in avail.contains(where: { abs($0 - sub) < 1.0 }) })
                        ?? avail.max()
                    if let fb = fallbackCandidate {
                        if abs(currentRate - fb) < 0.5 {
                            effectiveAppliedRate = currentRate
                        } else {
                            var fbRate = fb
                            if AudioObjectSetPropertyData(targetID, &address, 0, nil, size, &fbRate) == noErr {
                                rateChanged = true
                                effectiveAppliedRate = fb
                            }
                        }
                    }
                }
            }
        }

        var bitsChanged = false
        if let targetBits = bitDepth, targetBits > 0 {
            bitsChanged = setStreamBitDepth(UInt32(targetBits), sampleRate: effectiveAppliedRate, deviceID: targetID)
        }

        if isTargetingDefaultOutput && RoomAcousticService.shared.isLocalPassthroughEQActive {
            RoomAcousticService.shared.notifyLocalOutputFormatChanged(sampleRateHz: effectiveAppliedRate)
        }

        if useMutingGuard {
            scheduleMutingGuardPostSwitchRelease(
                deviceID: targetID,
                durationMs: guardMs,
                targetRate: effectiveAppliedRate,
                generation: guardGeneration
            )
        }

        if rateChanged || bitsChanged {
            let bitDepthStr = bitDepth != nil ? ", \(bitDepth!) бит" : ""
            let guardTag = useMutingGuard ? " [🔇 DAC Muting Guard \(guardMs)ms]" : ""
            NSLog("[CoreAudioDeviceManager] ✅ Switched device %u format: %.1f kHz%@ (was %.1f kHz)%@",
                  targetID, effectiveAppliedRate / 1000.0, bitDepthStr, currentRate / 1000.0, guardTag)
        }
        return (!needsRateSwitch || rateChanged) && (!needsBitDepthSwitch || bitsChanged)
    }
}
