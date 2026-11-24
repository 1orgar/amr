//
//  CoreAudioDeviceManager+CapabilitiesAndListeners.swift
//  AppleMusicRemoteMac
//
//  3-Stage Hardware USB/DoP/NOS Capability Evaluation, CoreAudio Property Accessors,
//  and Detached-Queue Hardware Property Listeners
//

import Foundation
import CoreAudio

extension CoreAudioDeviceManager {

    // MARK: - Internal Helpers & DSP Capability Evaluation

    /// 3-ступенчатая аппаратная проверка возможностей ЦАП для режимов DSD (DoP) и HQ NOS PCM:
    /// 1) Физический транспорт CoreAudio HAL (`kAudioDevicePropertyTransportType == kAudioDeviceTransportTypeUSB`) —
    ///    отсекает встроенные динамики Mac, Bluetooth, AirPlay, HDMI/DisplayPort и виртуальные/агрегатные устройства;
    /// 2) Физические выходные потоки (`kAudioStreamPropertyAvailablePhysicalFormats`) — стерео (`>= 2` кан.) и
    ///    аппаратная разрядность PCM `>= 24` бит (обязательно для маркеров DoP `0x05`/`0xFA` и 24-битного шейпера LNS15,
    ///    отсекает 16-битные USB-гарнитуры, спикерфоны и веб-камеры);
    /// 3) Номинальные частоты (`kAudioDevicePropertyAvailableNominalSampleRates`) — `>= 176.4 кГц` для HQ NOS PCM
    ///    и точная поддержка несущих DoP сетки SACD (`176.4 / 352.8 / 705.6 / 1411.2 кГц`) для DSD64..DSD512.
    public static func evaluateDSPCapabilities(
        rawTransport: UInt32?,
        name: String,
        uid: String,
        availableRates: [Double],
        maxBitDepth: Int,
        hasStereoOutput: Bool
    ) -> DeviceDSPCapabilities {
        let transportKey: String = {
            guard let t = rawTransport else { return "unknown" }
            switch t {
            case kAudioDeviceTransportTypeUSB:
                return "usb"
            case kAudioDeviceTransportTypeBuiltIn:
                return "builtin"
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
                return "bluetooth"
            case kAudioDeviceTransportTypeAirPlay:
                return "airplay"
            case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
                return "hdmi"
            case kAudioDeviceTransportTypeThunderbolt:
                return "thunderbolt"
            case kAudioDeviceTransportTypeFireWire:
                return "firewire"
            case kAudioDeviceTransportTypePCI:
                return "pci"
            case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate:
                return "virtual"
            default:
                return "unknown"
            }
        }()

        let isInternalAggregate = name.contains("AMR Tap Aggregate") || uid.contains("AMR-Tap-Aggregate")
        let isUSB = (transportKey == "usb") && !isInternalAggregate
        let maxRate = availableRates.max() ?? 0.0
        let hasRate: (Double) -> Bool = { target in
            availableRates.contains { abs($0 - target) <= 1.5 }
        }

        let is24BitStereoUSBDAC = isUSB && hasStereoOutput && maxBitDepth >= 24
        let supportsNOS = is24BitStereoUSBDAC && maxRate >= 176_399.0

        let maxDSDRate: Int
        if !is24BitStereoUSBDAC {
            maxDSDRate = 0
        } else if hasRate(1_411_200.0) {
            maxDSDRate = 512
        } else if hasRate(705_600.0) {
            maxDSDRate = 256
        } else if hasRate(352_800.0) {
            maxDSDRate = 128
        } else if hasRate(176_400.0) {
            maxDSDRate = 64
        } else {
            maxDSDRate = 0
        }

        return DeviceDSPCapabilities(
            transportType: transportKey,
            isUSB: isUSB,
            maxBitDepth: maxBitDepth,
            supportsNOS: supportsNOS,
            supportsDSDDoP: maxDSDRate >= 64,
            maxDSDRate: maxDSDRate
        )
    }

    internal func outputStreamCapabilities(deviceID: AudioDeviceID) -> (hasStereoOutput: Bool, maxBitDepth: Int) {
        var streamAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &streamAddr, 0, nil, &streamSize) == noErr,
              streamSize >= UInt32(MemoryLayout<AudioStreamID>.size) else {
            return (false, 0)
        }
        let streamCount = Int(streamSize) / MemoryLayout<AudioStreamID>.size
        var streamIDs = [AudioStreamID](repeating: 0, count: streamCount)
        guard AudioObjectGetPropertyData(deviceID, &streamAddr, 0, nil, &streamSize, &streamIDs) == noErr else {
            return (false, 0)
        }

        var hasStereo = false
        var maxBits = 0
        for sID in streamIDs where sID != 0 {
            var physAddr = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyAvailablePhysicalFormats,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var availSize: UInt32 = 0
            if AudioObjectGetPropertyDataSize(sID, &physAddr, 0, nil, &availSize) == noErr, availSize > 0 {
                let count = Int(availSize) / MemoryLayout<AudioStreamRangedDescription>.size
                var ranged = [AudioStreamRangedDescription](repeating: AudioStreamRangedDescription(), count: count)
                if AudioObjectGetPropertyData(sID, &physAddr, 0, nil, &availSize, &ranged) == noErr {
                    for desc in ranged where desc.mFormat.mFormatID == kAudioFormatLinearPCM {
                        if desc.mFormat.mChannelsPerFrame >= 2 {
                            hasStereo = true
                        }
                        maxBits = max(maxBits, Int(desc.mFormat.mBitsPerChannel))
                    }
                }
            } else {
                var curAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioStreamPropertyPhysicalFormat,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                var asbd = AudioStreamBasicDescription()
                var sz = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                if AudioObjectGetPropertyData(sID, &curAddr, 0, nil, &sz, &asbd) == noErr {
                    if asbd.mChannelsPerFrame >= 2 {
                        hasStereo = true
                    }
                    maxBits = max(maxBits, Int(asbd.mBitsPerChannel))
                }
            }
        }
        return (hasStereo, maxBits > 0 ? maxBits : 16)
    }

    internal func hasOutputStreams(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else { return false }
        return size >= UInt32(MemoryLayout<AudioStreamID>.size)
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

    internal func stringProperty(objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
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

    internal func uint32Property(objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> UInt32? {
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

    internal func doubleProperty(objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> Double? {
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

    internal func setupHardwareListeners() {
        // 1. Listen for default output device changes on dedicated halNotifyQueue,
        // immediately offloading all CoreAudio property queries and listener updates to halWorkerQueue
        // so CoreAudio's HAL notification dispatch can NEVER re-enter or deadlock AudioObjectRemovePropertyListenerBlock.
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let defaultBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.halWorkerQueue.async { [weak self] in
                guard let self = self else { return }
                let devices = self.getOutputDevices()
                self.onDevicesChanged?(devices)
                if let defID = self.getDefaultOutputDeviceID(), defID != 0 {
                    self.lastKnownDefaultOutputID = defID
                    self.updateSampleRateMonitoring(for: defID)
                }
                if AudioEngineController.shared.currentConfigurationSnapshot().mode != .bitPerfectPassthrough {
                    Task {
                        await AudioEngineController.shared.handleHardwareDeviceChange()
                    }
                }
                if !AudioEngineController.shared.isActivePipelineHook {
                    BitPerfectLogMonitor.shared.reapplyCurrentFormat()
                    if RoomAcousticService.shared.isLocalPassthroughEQActive {
                        RoomAcousticService.shared.notifyLocalOutputFormatChanged(forceRecreateUnit: true)
                    }
                }
            }
        }
        listenerLock.withLock {
            self.defaultDeviceListenerBlock = defaultBlock
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, halNotifyQueue, defaultBlock)

        // 2. Listen for device list changes
        var devicesListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let listBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.halWorkerQueue.async { [weak self] in
                guard let self = self else { return }
                let devices = self.getOutputDevices()
                self.onDevicesChanged?(devices)
                let currentDefID = self.getDefaultOutputDeviceID() ?? 0
                let defaultOutputChanged: Bool = self.listenerLock.withLock {
                    let changed = (currentDefID != 0 && currentDefID != self._lastKnownDefaultOutputID)
                    if currentDefID != 0 {
                        self._lastKnownDefaultOutputID = currentDefID
                    }
                    return changed
                }
                if currentDefID != 0 {
                    self.updateSampleRateMonitoring(for: currentDefID)
                }
                if AudioEngineController.shared.currentConfigurationSnapshot().mode != .bitPerfectPassthrough {
                    Task {
                        await AudioEngineController.shared.handleHardwareDeviceChange()
                    }
                }
                if !AudioEngineController.shared.isActivePipelineHook && defaultOutputChanged {
                    BitPerfectLogMonitor.shared.reapplyCurrentFormat()
                    if RoomAcousticService.shared.isLocalPassthroughEQActive {
                        RoomAcousticService.shared.notifyLocalOutputFormatChanged(forceRecreateUnit: true)
                    }
                }
            }
        }
        listenerLock.withLock {
            self.devicesListListenerBlock = listBlock
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devicesListAddress, halNotifyQueue, listBlock)

        halWorkerQueue.async { [weak self] in
            guard let self = self, let defaultID = self.getDefaultOutputDeviceID(), defaultID != 0 else { return }
            self.lastKnownDefaultOutputID = defaultID
            self.updateSampleRateMonitoring(for: defaultID)
        }
    }

    internal func updateSampleRateMonitoring(for deviceID: AudioDeviceID) {
        listenerLock.lock()
        if monitoredDeviceID == deviceID, sampleRateListenerBlock != nil {
            listenerLock.unlock()
            return
        }
        let oldID = monitoredDeviceID
        let oldBlock = sampleRateListenerBlock
        monitoredDeviceID = deviceID

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.halWorkerQueue.async { [weak self] in
                guard let self = self else { return }
                let currentRate = self.doubleProperty(objectID: deviceID, selector: kAudioDevicePropertyNominalSampleRate) ?? 44100.0
                if !AudioEngineController.shared.isActivePipelineHook,
                   !DLNADiscoveryManager.shared.hasActiveRenderer,
                   RoomAcousticService.shared.isLocalPassthroughEQActive {
                    let lockedRate = BitPerfectLogMonitor.shared.isEnabled ? BitPerfectLogMonitor.shared.currentDetectedSampleRate : nil
                    let matchesLockedRate = (lockedRate == nil) || (abs((lockedRate ?? currentRate) - currentRate) <= 500.0)
                    if matchesLockedRate {
                        RoomAcousticService.shared.notifyLocalOutputFormatChanged(sampleRateHz: currentRate)
                        AudioProcessTapService.shared.setFormat(sampleRate: Int(currentRate.rounded()))
                    }
                }
                self.onSampleRateChanged?(deviceID, currentRate)
                let devices = self.getOutputDevices()
                self.onDevicesChanged?(devices)
            }
        }
        self.sampleRateListenerBlock = block
        listenerLock.unlock()

        if let oldID = oldID, let oldBlock = oldBlock {
            var oldAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(oldID, &oldAddress, halNotifyQueue, oldBlock)
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(deviceID, &address, halNotifyQueue, block)
    }

    internal func removeHardwareListeners() {
        let (defaultBlock, listBlock, oldID, oldBlock) = listenerLock.withLock {
            let defB = defaultDeviceListenerBlock
            let lstB = devicesListListenerBlock
            let oID = monitoredDeviceID
            let oBlk = sampleRateListenerBlock
            defaultDeviceListenerBlock = nil
            devicesListListenerBlock = nil
            monitoredDeviceID = nil
            sampleRateListenerBlock = nil
            return (defB, lstB, oID, oBlk)
        }

        if let defaultBlock = defaultBlock {
            var defaultDeviceAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, halNotifyQueue, defaultBlock)
        }

        if let listBlock = listBlock {
            var devicesListAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devicesListAddress, halNotifyQueue, listBlock)
        }

        if let oldID = oldID, let oldBlock = oldBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(oldID, &address, halNotifyQueue, oldBlock)
        }
    }
}
