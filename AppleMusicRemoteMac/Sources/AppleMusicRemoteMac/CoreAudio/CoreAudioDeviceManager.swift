//
//  CoreAudioDeviceManager.swift
//  AppleMusicRemoteMac
//
//  CoreAudio Hardware Device Management & Bit-Perfect Sample Rate Control
//  Inspired by Choritsu (jcongaku/apple-music-lossless-eq)
//

import Foundation
import CoreAudio

public struct AudioOutputDevice: Identifiable, Hashable, Sendable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public let iconName: String
    public let currentSampleRate: Double
    public let availableSampleRates: [Double]
    public let isDefault: Bool

    public init(
        id: AudioDeviceID,
        uid: String,
        name: String,
        iconName: String,
        currentSampleRate: Double,
        availableSampleRates: [Double],
        isDefault: Bool
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.iconName = iconName
        self.currentSampleRate = currentSampleRate
        self.availableSampleRates = availableSampleRates
        self.isDefault = isDefault
    }

    public var dictionary: [String: Any] {
        [
            "id": Int(id),
            "uid": uid,
            "name": name,
            "icon": iconName,
            "currentSampleRate": currentSampleRate,
            "availableSampleRates": availableSampleRates,
            "isDefault": isDefault
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

    private let mutingGuardLock = NSLock()
    private let mutingGuardQueue = DispatchQueue(label: "org.ksholokhov.amr.dacmutingguard", qos: .userInteractive)
    private var unmuteWorkItem: DispatchWorkItem?
    private var isMutingGuardEnabledInternal: Bool
    private var mutingGuardDurationMsInternal: Int
    private var isMutingGuardActiveInternal: Bool = false
    private var mutingGuardActivationCountInternal: Int = 0
    private var preGuardAppVolume: Int?
    private var preGuardWasDucked: Bool = false
    private var preGuardUnduckedVolume: Int?
    private var hardwareMutedDeviceID: AudioDeviceID?

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

    private let listenerLock = NSLock()
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var sampleRateListenerBlock: AudioObjectPropertyListenerBlock?
    private var devicesListListenerBlock: AudioObjectPropertyListenerBlock?
    private var monitoredDeviceID: AudioDeviceID?

    private init() {
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

                return AudioOutputDevice(
                    id: deviceID,
                    uid: uid,
                    name: name,
                    iconName: icon,
                    currentSampleRate: sampleRate,
                    availableSampleRates: availableRates,
                    isDefault: (deviceID == defaultID)
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
            updateSampleRateMonitoring(for: id)
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
        guard let targetID = deviceID ?? getDefaultOutputDeviceID() else { return false }
        guard let targetRate = nearestSupportedSampleRate(sampleRate, deviceID: targetID) else { return false }

        let currentRate = doubleProperty(objectID: targetID, selector: kAudioDevicePropertyNominalSampleRate) ?? 0

        // If rate is already identical and bit depth does not require modification, skip CoreAudio calls
        let needsRateSwitch = abs(currentRate - targetRate) >= 0.5
        let needsBitDepthSwitch = (bitDepth != nil) && !isCurrentBitDepth(UInt32(bitDepth!), deviceID: targetID, sampleRate: targetRate)
        if !needsRateSwitch && !needsBitDepthSwitch {
            return true
        }

        let useMutingGuard = isMutingGuardEnabled && (needsRateSwitch || needsBitDepthSwitch)
        let guardMs = mutingGuardDurationMs
        if useMutingGuard {
            engageMutingGuardPreSwitch(deviceID: targetID, durationMs: guardMs, fromRate: currentRate, toRate: targetRate)
        }

        var rateChanged = false
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
                }
            }
        }

        var bitsChanged = false
        if let targetBits = bitDepth, targetBits > 0 {
            bitsChanged = setStreamBitDepth(UInt32(targetBits), sampleRate: targetRate, deviceID: targetID)
        }

        if useMutingGuard {
            scheduleMutingGuardPostSwitchRelease(deviceID: targetID, durationMs: guardMs, targetRate: targetRate)
        }

        if rateChanged || bitsChanged {
            let bitDepthStr = bitDepth != nil ? ", \(bitDepth!) бит" : ""
            let guardTag = useMutingGuard ? " [🔇 DAC Muting Guard \(guardMs)ms]" : ""
            NSLog("[CoreAudioDeviceManager] ✅ Switched device %u format: %.1f kHz%@ (was %.1f kHz)%@",
                  targetID, targetRate / 1000.0, bitDepthStr, currentRate / 1000.0, guardTag)
        }
        return (!needsRateSwitch || rateChanged) && (!needsBitDepthSwitch || bitsChanged)
    }

    // MARK: - DAC Muting Guard Implementation (Click-Free Relay Switching)

    /// Executes a deterministic DAC Muting Guard cycle around a custom format-switch closure (used in live switching & unit tests).
    public func performClickFreeSwitchCycle(
        deviceID: AudioDeviceID = 0,
        fromRate: Double,
        toRate: Double,
        switchOperation: () -> Void,
        completion: (() -> Void)? = nil
    ) {
        let needsSwitch = abs(fromRate - toRate) >= 0.5
        guard isMutingGuardEnabled && needsSwitch else {
            switchOperation()
            completion?()
            return
        }
        let guardMs = mutingGuardDurationMs
        engageMutingGuardPreSwitch(deviceID: deviceID, durationMs: guardMs, fromRate: fromRate, toRate: toRate)
        switchOperation()
        scheduleMutingGuardPostSwitchRelease(deviceID: deviceID, durationMs: guardMs, targetRate: toRate, completion: completion)
    }

    public func updateSavedGuardVolumeIfNeeded(_ newVol: Int, isDucked: Bool) {
        mutingGuardLock.lock()
        if isMutingGuardActiveInternal {
            preGuardAppVolume = newVol
            preGuardWasDucked = isDucked
            if !isDucked {
                preGuardUnduckedVolume = newVol
            } else if preGuardUnduckedVolume == nil {
                preGuardUnduckedVolume = AudioDuckingController.shared.originalVolume
            }
        }
        mutingGuardLock.unlock()
    }

    private func engageMutingGuardPreSwitch(deviceID: AudioDeviceID, durationMs: Int, fromRate: Double, toRate: Double) {
        AudioProcessTapService.shared.setMutingGuardZeroFill(true)

        var needSoftwareMute = false
        mutingGuardLock.lock()
        unmuteWorkItem?.cancel()
        unmuteWorkItem = nil
        let wasAlreadyActive = isMutingGuardActiveInternal
        isMutingGuardActiveInternal = true
        mutingGuardActivationCountInternal += 1

        if !wasAlreadyActive && !PlaybackRouter.shared.isTestingEnvironment {
            preGuardWasDucked = AudioDuckingController.shared.isDucked
            preGuardUnduckedVolume = preGuardWasDucked ? AudioDuckingController.shared.originalVolume : nil
            let hwMuted = (deviceID != 0) && setHardwareMute(true, for: deviceID)
            if hwMuted {
                hardwareMutedDeviceID = deviceID
            } else if !ExternalAmpTCPController.shared.isActive && !AppleScriptExecutor.shared.isBusy {
                needSoftwareMute = true
            }
        }
        mutingGuardLock.unlock()

        // Only fall back to ScriptingBridge soundVolume when the DAC lacks hardware kAudioDevicePropertyMute
        // and Music.app IPC is idle — never stall the DAC clock switch on contended AppleEvents.
        if needSoftwareMute, let app = MusicAppProvider.shared.getMusicApp() {
            let currentVol = app.soundVolume
            if currentVol >= 0 {
                mutingGuardLock.lock()
                preGuardAppVolume = currentVol
                mutingGuardLock.unlock()
            }
            app.soundVolume = 0
        }

        // Drain CoreAudio output FIFO with digital silence before flipping the hardware oscillator/relay
        let preDelaySec: Double
        if PlaybackRouter.shared.isTestingEnvironment {
            preDelaySec = min(0.015, Double(durationMs) * 0.30 / 1000.0)
        } else if Thread.isMainThread {
            preDelaySec = min(0.020, Double(durationMs) * 0.25 / 1000.0)
        } else {
            preDelaySec = min(0.045, Double(durationMs) * 0.30 / 1000.0)
        }
        if preDelaySec > 0.001 {
            usleep(UInt32(preDelaySec * 1_000_000))
        }
    }

    private func scheduleMutingGuardPostSwitchRelease(
        deviceID: AudioDeviceID,
        durationMs: Int,
        targetRate: Double,
        completion: (() -> Void)? = nil
    ) {
        let postDelaySec: Double
        if PlaybackRouter.shared.isTestingEnvironment {
            postDelaySec = min(0.035, Double(durationMs) * 0.70 / 1000.0)
        } else {
            postDelaySec = max(0.025, Double(durationMs) * 0.70 / 1000.0)
        }

        mutingGuardLock.lock()
        unmuteWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.releaseMutingGuard(targetRate: targetRate)
            completion?()
        }
        unmuteWorkItem = item
        mutingGuardLock.unlock()

        mutingGuardQueue.asyncAfter(deadline: .now() + postDelaySec, execute: item)
    }

    private func releaseMutingGuard(targetRate: Double) {
        mutingGuardLock.lock()
        let mutedDev = hardwareMutedDeviceID
        hardwareMutedDeviceID = nil
        let savedVol = preGuardAppVolume
        preGuardAppVolume = nil
        let wasDuckedAtEngage = preGuardWasDucked
        preGuardWasDucked = false
        let savedUnduckedVol = preGuardUnduckedVolume
        preGuardUnduckedVolume = nil
        isMutingGuardActiveInternal = false
        unmuteWorkItem = nil
        mutingGuardLock.unlock()

        if !PlaybackRouter.shared.isTestingEnvironment {
            if let devID = mutedDev, devID != 0 {
                _ = setHardwareMute(false, for: devID)
            }
            let isDLNAMuted = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isDLNAMuted }
            if !isDLNAMuted && savedVol != nil {
                let targetAppVol: Int
                if AudioDuckingController.shared.isDucked {
                    targetAppVol = wasDuckedAtEngage
                        ? (savedVol ?? AudioDuckingController.shared.currentDuckedVolume)
                        : AudioDuckingController.shared.currentDuckedVolume
                } else if PlaybackStateStore.shared.isVolumeLockedTo100 {
                    targetAppVol = 100
                } else if wasDuckedAtEngage {
                    let simVol = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.simulatedVolume }
                    targetAppVol = savedUnduckedVol ?? simVol
                } else {
                    let simVol = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.simulatedVolume }
                    targetAppVol = savedVol ?? simVol
                }
                DispatchQueue.global(qos: .utility).async {
                    if let app = MusicAppProvider.shared.getMusicApp() {
                        app.soundVolume = targetAppVol
                    }
                }
            }
        }

        AudioProcessTapService.shared.setMutingGuardZeroFill(false)
    }

    @discardableResult
    private func setHardwareMute(_ mute: Bool, for deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var isSettable: DarwinBoolean = false
        guard AudioObjectHasProperty(deviceID, &address),
              AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr,
              isSettable.boolValue else {
            return false
        }
        var val: UInt32 = mute ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &val) == noErr
    }

    private func isCurrentBitDepth(_ targetBits: UInt32, deviceID: AudioDeviceID, sampleRate: Double) -> Bool {
        var streamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamsSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &streamsAddress, 0, nil, &streamsSize) == noErr, streamsSize > 0 else { return true }

        let streamCount = Int(streamsSize) / MemoryLayout<AudioStreamID>.size
        var streamIDs = [AudioStreamID](repeating: 0, count: streamCount)
        guard AudioObjectGetPropertyData(deviceID, &streamsAddress, 0, nil, &streamsSize, &streamIDs) == noErr else { return true }

        for sID in streamIDs {
            var physAddress = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyPhysicalFormat,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var currentASBD = AudioStreamBasicDescription()
            var currentASBDSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            if AudioObjectGetPropertyData(sID, &physAddress, 0, nil, &currentASBDSize, &currentASBD) == noErr {
                if currentASBD.mBitsPerChannel != targetBits {
                    return false
                }
            }
        }
        return true
    }

    @discardableResult
    private func setStreamBitDepth(_ targetBits: UInt32, sampleRate: Double, deviceID: AudioDeviceID) -> Bool {
        var streamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamsSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &streamsAddress, 0, nil, &streamsSize) == noErr, streamsSize > 0 else { return false }

        let streamCount = Int(streamsSize) / MemoryLayout<AudioStreamID>.size
        var streamIDs = [AudioStreamID](repeating: 0, count: streamCount)
        guard AudioObjectGetPropertyData(deviceID, &streamsAddress, 0, nil, &streamsSize, &streamIDs) == noErr else { return false }

        var anyChanged = false
        for sID in streamIDs {
            var physAddress = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyPhysicalFormat,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var isSettable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(sID, &physAddress, &isSettable) == noErr, isSettable.boolValue else { continue }

            var currentASBD = AudioStreamBasicDescription()
            var currentASBDSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            if AudioObjectGetPropertyData(sID, &physAddress, 0, nil, &currentASBDSize, &currentASBD) == noErr {
                if currentASBD.mBitsPerChannel == targetBits && abs(currentASBD.mSampleRate - sampleRate) < 0.5 {
                    anyChanged = true
                    continue // Already configured
                }
            }

            var availAddress = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyAvailablePhysicalFormats,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var availSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(sID, &availAddress, 0, nil, &availSize) == noErr, availSize > 0 else { continue }

            let count = Int(availSize) / MemoryLayout<AudioStreamRangedDescription>.size
            var ranged = [AudioStreamRangedDescription](repeating: AudioStreamRangedDescription(), count: count)
            guard AudioObjectGetPropertyData(sID, &availAddress, 0, nil, &availSize, &ranged) == noErr else { continue }

            let rateMatches = ranged.filter {
                sampleRate >= ($0.mSampleRateRange.mMinimum - 0.5) &&
                sampleRate <= ($0.mSampleRateRange.mMaximum + 0.5)
            }

            if let match = rateMatches.first(where: { $0.mFormat.mBitsPerChannel == targetBits }) {
                var newASBD = match.mFormat
                newASBD.mSampleRate = sampleRate
                let asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                if AudioObjectSetPropertyData(sID, &physAddress, 0, nil, asbdSize, &newASBD) == noErr {
                    anyChanged = true
                }
            }
        }
        return anyChanged
    }

    // MARK: - Hardware Volume

    public func outputVolume() -> Float? {
        guard let deviceID = getDefaultOutputDeviceID(),
              let (selector, elements) = volumeAddress(deviceID: deviceID) else {
            return nil
        }

        var values: [Float] = []
        for element in elements {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr {
                values.append(value)
            }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Float(values.count)
    }

    @discardableResult
    public func setOutputVolume(_ volume: Float) -> Bool {
        guard let deviceID = getDefaultOutputDeviceID(),
              let (selector, elements) = volumeAddress(deviceID: deviceID) else {
            return false
        }

        let clamped = min(max(volume, 0.0), 1.0)
        var success = false
        for element in elements {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            var isSettable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr, isSettable.boolValue else {
                continue
            }
            var val = Float32(clamped)
            let size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &val) == noErr {
                success = true
            }
        }
        return success
    }

    // MARK: - Internal Helpers

    private func hasOutputStreams(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else { return false }
        return size >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private func volumeAddress(deviceID: AudioDeviceID) -> (selector: AudioObjectPropertySelector, elements: [AudioObjectPropertyElement])? {
        let virtualMainVolume = AudioObjectPropertySelector(0x766D_7663) // 'vmvc'
        let candidates: [AudioObjectPropertyElement] = [kAudioObjectPropertyElementMain, 1, 2]

        for selector in [kAudioDevicePropertyVolumeScalar, virtualMainVolume] {
            let present = candidates.filter { element in
                var address = AudioObjectPropertyAddress(
                    mSelector: selector,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: element
                )
                return AudioObjectHasProperty(deviceID, &address)
            }
            if present.contains(kAudioObjectPropertyElementMain) {
                return (selector, [kAudioObjectPropertyElementMain])
            }
            if !present.isEmpty {
                return (selector, present)
            }
        }
        return nil
    }

    public func transportIconName(deviceID: AudioDeviceID) -> String {
        guard let transport = uint32Property(objectID: deviceID, selector: kAudioDevicePropertyTransportType) else {
            return "speaker.wave.2.fill"
        }

        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return "headphones"
        case kAudioDeviceTransportTypeBuiltIn:
            return "laptopcomputer"
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt,
             kAudioDeviceTransportTypeFireWire, kAudioDeviceTransportTypePCI:
            return "hifispeaker.fill"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "tv"
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeVirtual:
            return "waveform"
        default:
            return "speaker.wave.2.fill"
        }
    }

    private func stringProperty(objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(objectID, &address) else { return nil }
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size) == noErr else { return nil }
        var unmanagedString: Unmanaged<CFString>?
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &unmanagedString)
        guard status == noErr, let cf = unmanagedString?.takeRetainedValue() else { return nil }
        return cf as String
    }

    private func uint32Property(objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(objectID, &address) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value
    }

    private func doubleProperty(objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(objectID, &address) else { return nil }
        var value = Double(0)
        var size = UInt32(MemoryLayout<Double>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value
    }

    // MARK: - Property Listeners

    private func setupHardwareListeners() {
        // 1. Listen for default output device changes
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let defaultBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            let devices = self.getOutputDevices()
            self.onDevicesChanged?(devices)
            if let defID = self.getDefaultOutputDeviceID() {
                self.updateSampleRateMonitoring(for: defID)
            }
            BitPerfectLogMonitor.shared.reapplyCurrentFormat()
        }
        self.defaultDeviceListenerBlock = defaultBlock
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, nil, defaultBlock)

        // 2. Listen for device list changes
        var devicesListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let listBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            let devices = self.getOutputDevices()
            self.onDevicesChanged?(devices)
            BitPerfectLogMonitor.shared.reapplyCurrentFormat()
        }
        self.devicesListListenerBlock = listBlock
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devicesListAddress, nil, listBlock)

        if let defaultID = getDefaultOutputDeviceID() {
            updateSampleRateMonitoring(for: defaultID)
        }
    }

    private func updateSampleRateMonitoring(for deviceID: AudioDeviceID) {
        listenerLock.lock()
        let oldID = monitoredDeviceID
        let oldBlock = sampleRateListenerBlock
        monitoredDeviceID = deviceID

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            let currentRate = self.doubleProperty(objectID: deviceID, selector: kAudioDevicePropertyNominalSampleRate) ?? 44100.0
            self.onSampleRateChanged?(deviceID, currentRate)
            let devices = self.getOutputDevices()
            self.onDevicesChanged?(devices)
        }
        self.sampleRateListenerBlock = block
        listenerLock.unlock()

        if let oldID = oldID, let oldBlock = oldBlock {
            var oldAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(oldID, &oldAddress, nil, oldBlock)
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(deviceID, &address, nil, block)
    }

    private func removeHardwareListeners() {
        if let defaultBlock = defaultDeviceListenerBlock {
            var defaultDeviceAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, nil, defaultBlock)
        }

        if let listBlock = devicesListListenerBlock {
            var devicesListAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devicesListAddress, nil, listBlock)
        }

        listenerLock.lock()
        let oldID = monitoredDeviceID
        let oldBlock = sampleRateListenerBlock
        monitoredDeviceID = nil
        sampleRateListenerBlock = nil
        listenerLock.unlock()

        if let oldID = oldID, let oldBlock = oldBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(oldID, &address, nil, oldBlock)
        }
    }
}
