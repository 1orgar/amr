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
}

public final class CoreAudioDeviceManager: @unchecked Sendable {
    public static let shared = CoreAudioDeviceManager()

    public var onDevicesChanged: (([AudioOutputDevice]) -> Void)?
    public var onSampleRateChanged: ((AudioDeviceID, Double) -> Void)?

    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var sampleRateListenerBlock: AudioObjectPropertyListenerBlock?
    private var devicesListListenerBlock: AudioObjectPropertyListenerBlock?
    private var monitoredDeviceID: AudioDeviceID?

    private init() {
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
        if abs(currentRate - targetRate) < 0.5 {
            if bitDepth == nil || isCurrentBitDepth(UInt32(bitDepth!), deviceID: targetID, sampleRate: targetRate) {
                return true
            }
        }

        var rateChanged = false
        if abs(currentRate - targetRate) >= 0.5 {
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

        if rateChanged || bitsChanged {
            let bitDepthStr = bitDepth != nil ? ", \(bitDepth!) бит" : ""
            NSLog("[CoreAudioDeviceManager] ✅ Switched device %u format: %.1f kHz%@ (was %.1f kHz)",
                  targetID, targetRate / 1000.0, bitDepthStr, currentRate / 1000.0)
        }
        return true
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
        if let oldID = monitoredDeviceID, let oldBlock = sampleRateListenerBlock {
            var oldAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(oldID, &oldAddress, nil, oldBlock)
        }

        monitoredDeviceID = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            let currentRate = self.doubleProperty(objectID: deviceID, selector: kAudioDevicePropertyNominalSampleRate) ?? 44100.0
            self.onSampleRateChanged?(deviceID, currentRate)
            let devices = self.getOutputDevices()
            self.onDevicesChanged?(devices)
        }
        self.sampleRateListenerBlock = block
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

        if let oldID = monitoredDeviceID, let oldBlock = sampleRateListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(oldID, &address, nil, oldBlock)
        }
    }
}
