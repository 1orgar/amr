//
//  HALDeviceManager+FormatNegotiation.swift
//  AppleMusicRemoteMac
//
//  CoreAudio HAL Device & Stream Discovery, Direct Non-Mixable Integer Format Negotiation,
//  UAC2 Bit-Transparent Controls, and Mixable Format Rollback/Restoration.
//

import Foundation
import CoreAudio
import AudioToolbox
import Darwin

extension HALDeviceManager {

    // MARK: - Device & Stream Discovery

    public func supportedSampleRates(deviceID: AudioDeviceID) -> [Double] {
        CoreAudioDeviceManager.shared.availableSampleRates(deviceID: deviceID)
    }

    public static func findDeviceID(byUID uid: String) -> AudioDeviceID? {
        let devices = CoreAudioDeviceManager.shared.getOutputDevices()
        return devices.first(where: { $0.uid == uid })?.id
    }

    public static func defaultOutputDeviceID() -> AudioDeviceID? {
        let id = CoreAudioDeviceManager.shared.getDefaultOutputDeviceID()
        return id != 0 ? id : nil
    }

    public static func nominalSampleRate(deviceID: AudioDeviceID) -> Double {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate: Float64 = 44_100.0
        var size = UInt32(MemoryLayout<Float64>.size)
        _ = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &rate)
        return rate
    }

    public static func deviceName(deviceID: AudioDeviceID) -> String {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &cfName)
        guard status == noErr, let str = cfName?.takeRetainedValue() as String? else {
            return ""
        }
        return str
    }

    /// Находит `AudioDeviceID` по его `UID`, либо возвращает текущее системное устройство вывода.
    public func resolveOutputDevice(uid: String?) -> AudioDeviceID? {
        let devices = CoreAudioDeviceManager.shared.getOutputDevices()
        if let targetUID = uid, !targetUID.isEmpty {
            if let match = devices.first(where: { $0.uid == targetUID }) {
                return match.id
            }
        }
        return CoreAudioDeviceManager.shared.getDefaultOutputDeviceID()
    }

    /// Возвращает список выходных `AudioStreamID` для указанного `AudioDeviceID`.
    public func getOutputStreams(for deviceID: AudioDeviceID) -> [AudioStreamID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioStreamID>.size
        var streams = [AudioStreamID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &streams) == noErr else {
            return []
        }
        return streams
    }

    /// Опрашивает `kAudioStreamPropertyAvailablePhysicalFormats` для выходного потока ЦАПа.
    public func getAvailablePhysicalFormats(for streamID: AudioStreamID) -> [AudioStreamRangedDescription] {
        guard streamID != 0 else { return [] }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioStreamPropertyAvailablePhysicalFormats,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(streamID, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioStreamRangedDescription>.size
        var formats = [AudioStreamRangedDescription](repeating: AudioStreamRangedDescription(), count: count)
        guard AudioObjectGetPropertyData(streamID, &address, 0, nil, &size, &formats) == noErr else {
            return []
        }
        return formats
    }

    /// Опрашивает `kAudioStreamPropertyAvailableVirtualFormats` для выходного потока ЦАПа (включая Non-Mixable Direct Integer `0x4c`).
    public func getAvailableVirtualFormats(for streamID: AudioStreamID) -> [AudioStreamRangedDescription] {
        guard streamID != 0 else { return [] }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioStreamPropertyAvailableVirtualFormats,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(streamID, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioStreamRangedDescription>.size
        var formats = [AudioStreamRangedDescription](repeating: AudioStreamRangedDescription(), count: count)
        guard AudioObjectGetPropertyData(streamID, &address, 0, nil, &size, &formats) == noErr else {
            return []
        }
        return formats
    }

    public func currentStreamFormat(for streamID: AudioStreamID, selector: AudioObjectPropertySelector) -> AudioStreamBasicDescription? {
        guard streamID != 0 else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(streamID, &address, 0, nil, &size, &asbd) == noErr else {
            return nil
        }
        return asbd
    }

    public static func isBuiltInDevice(_ deviceID: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &transport) == noErr else {
            return false
        }
        return transport == kAudioDeviceTransportTypeBuiltIn
    }

    public static func isUSBDevice(_ deviceID: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &transport) == noErr else {
            return false
        }
        return transport == kAudioDeviceTransportTypeUSB
    }

    public static func isThunderboltDevice(_ deviceID: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &transport) == noErr else {
            return false
        }
        return transport == kAudioDeviceTransportTypeThunderbolt
    }

    /// Проверяет, что устройство является внешним высокоскоростным ЦАП по шине USB или Thunderbolt
    /// (исключая встроенные динамики, Bluetooth, AirPlay и внутренний агрегат `AMR Tap Aggregate`).
    public static func isEligibleExternalDACDevice(_ deviceID: AudioDeviceID) -> Bool {
        guard deviceID != 0 else { return false }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &transport) == noErr else {
            return false
        }
        guard transport == kAudioDeviceTransportTypeUSB || transport == kAudioDeviceTransportTypeThunderbolt else {
            return false
        }
        let name = deviceName(deviceID: deviceID)
        return !name.contains("AMR Tap Aggregate")
    }

    public static func mapASBDToHALStreamFormat(_ asbd: AudioStreamBasicDescription) -> (format: HALPhysicalStreamFormat, bitDepth: Int, isInteger: Bool) {
        if (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0 {
            return (.float32LE, Int(asbd.mBitsPerChannel), false)
        }
        if (asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0 {
            if asbd.mBitsPerChannel == 32 {
                return (.signedInt32LE, 32, true)
            }
            if asbd.mBitsPerChannel == 24 {
                if asbd.mBytesPerFrame == 6 {
                    return (.signedInt24PackedLE, 24, true)
                }
                let isHighOrPacked = (asbd.mFormatFlags & kAudioFormatFlagIsAlignedHigh) != 0
                    || (asbd.mFormatFlags & kAudioFormatFlagIsPacked) != 0
                return (isHighOrPacked ? .signedInt32LE : .signedInt24LowAligned32LE, 24, true)
            }
            return (.signedInt32LE, Int(asbd.mBitsPerChannel), true)
        }
        return (.float32LE, Int(asbd.mBitsPerChannel), false)
    }

    /// Определяет максимальный поддерживаемый множитель DoP (`DoP512 -> DoP256 -> DoP128 -> DoP64`) для заданной сетки.
    public func negotiateBestDoPRate(
        deviceID: AudioDeviceID,
        grid: BaseClockGrid,
        preferredMax: DSDRateMultiplier = .dsd256
    ) -> (dsdRate: DSDRateMultiplier, containerRateHz: Int)? {
        let supportedRates = CoreAudioDeviceManager.shared.availableSampleRates(deviceID: deviceID)
        let candidates: [DSDRateMultiplier] = [.dsd512, .dsd256, .dsd128, .dsd64].filter {
            $0.rawValue <= preferredMax.rawValue
        }

        for dsd in candidates {
            let containerHz = (grid == .grid44k1 ? 44_100 : 48_000) * (dsd.rawValue / 16)
            if supportedRates.isEmpty || supportedRates.contains(where: { abs(Int(round($0)) - containerHz) <= 1 }) {
                return (dsd, containerHz)
            }
        }
        return nil
    }

    // MARK: - Physical & Virtual Format Negotiation

    /// Выбирает и устанавливает физический и виртуальный формат (`PhysicalFormat` + `VirtualFormat` Direct Non-Mixable Integer `0x4c`) с ожиданием реле клока.
    public func configurePhysicalFormat(
        deviceID: AudioDeviceID,
        targetSampleRateHz: Int,
        preferNonMixable: Bool = true
    ) -> (streamID: AudioStreamID, format: HALPhysicalStreamFormat, bitDepth: Int, isInteger: Bool) {
        let streams = getOutputStreams(for: deviceID)
        let primaryStream = streams.first ?? 0
        let targetRate = Float64(targetSampleRateHz)

        let rateMatches: (AudioStreamRangedDescription) -> Bool = { desc in
            let minR = desc.mSampleRateRange.mMinimum
            let maxR = desc.mSampleRateRange.mMaximum
            return targetRate >= (minR - 1.0) && targetRate <= (maxR + 1.0)
        }

        let isSignedIntFormat: (AudioStreamBasicDescription, UInt32) -> Bool = { f, bits in
            let isInt = (f.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0 && (f.mFormatFlags & kAudioFormatFlagIsFloat) == 0
            return f.mFormatID == kAudioFormatLinearPCM && isInt && f.mBitsPerChannel == bits && f.mChannelsPerFrame >= 2
        }

        let isNonMixable: (AudioStreamBasicDescription) -> Bool = { f in
            (f.mFormatFlags & kAudioFormatFlagIsNonMixable) != 0
        }

        let selectBestPhysASBD: ([AudioStreamRangedDescription]) -> AudioStreamBasicDescription? = { availablePhys in
            if preferNonMixable, let nm32 = availablePhys.first(where: { isSignedIntFormat($0.mFormat, 32) && isNonMixable($0.mFormat) && rateMatches($0) }) {
                var asbd = nm32.mFormat; asbd.mSampleRate = targetRate; return asbd
            }
            if preferNonMixable, let nm24 = availablePhys.first(where: { isSignedIntFormat($0.mFormat, 24) && isNonMixable($0.mFormat) && rateMatches($0) }) {
                var asbd = nm24.mFormat; asbd.mSampleRate = targetRate; return asbd
            }
            if let int32Desc = availablePhys.first(where: { isSignedIntFormat($0.mFormat, 32) && rateMatches($0) }) {
                var asbd = int32Desc.mFormat; asbd.mSampleRate = targetRate; return asbd
            }
            if let int24Desc = availablePhys.first(where: { isSignedIntFormat($0.mFormat, 24) && rateMatches($0) }) {
                var asbd = int24Desc.mFormat; asbd.mSampleRate = targetRate; return asbd
            }
            if let fallbackDesc = availablePhys.first(where: rateMatches) {
                var asbd = fallbackDesc.mFormat; asbd.mSampleRate = targetRate; return asbd
            }
            return nil
        }

        var rateAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let rateSize = UInt32(MemoryLayout<Float64>.size)

        guard primaryStream != 0 else {
            var desiredRate = targetRate
            _ = AudioObjectSetPropertyData(deviceID, &rateAddr, 0, nil, rateSize, &desiredRate)
            return (0, .float32LE, 32, false)
        }

        let asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var physAddr = AudioObjectPropertyAddress(
            mSelector: kAudioStreamPropertyPhysicalFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // 1. Атомарное переключение PhysicalFormat (частота + Non-Mixable Integer 0x4c за один шаг драйвера)
        var chosenPhysASBD = selectBestPhysASBD(getAvailablePhysicalFormats(for: primaryStream))
        var physSetSucceeded = false

        if var targetPhysASBD = chosenPhysASBD {
            let curPhys = currentStreamFormat(for: primaryStream, selector: kAudioStreamPropertyPhysicalFormat)
            let alreadyMatchesPhys = curPhys.map {
                abs($0.mSampleRate - targetPhysASBD.mSampleRate) <= 0.5
                    && $0.mFormatFlags == targetPhysASBD.mFormatFlags
                    && $0.mBitsPerChannel == targetPhysASBD.mBitsPerChannel
                    && $0.mBytesPerFrame == targetPhysASBD.mBytesPerFrame
            } ?? false

            if alreadyMatchesPhys {
                physSetSucceeded = true
            } else if AudioObjectSetPropertyData(primaryStream, &physAddr, 0, nil, asbdSize, &targetPhysASBD) == noErr {
                for _ in 0..<60 {
                    let p = currentStreamFormat(for: primaryStream, selector: kAudioStreamPropertyPhysicalFormat)
                    let v = currentStreamFormat(for: primaryStream, selector: kAudioStreamPropertyVirtualFormat)
                    let pReady = p.map { abs($0.mSampleRate - targetRate) <= 1.0 && $0.mFormatFlags == targetPhysASBD.mFormatFlags } ?? false
                    let vReady = v.map {
                        abs($0.mSampleRate - targetRate) <= 1.0
                            && (!preferNonMixable || !isNonMixable(targetPhysASBD) || isNonMixable($0))
                    } ?? false
                    if pReady && vReady {
                        physSetSucceeded = true
                        break
                    }
                    usleep(10_000)
                }
                if abs(Self.nominalSampleRate(deviceID: deviceID) - targetRate) <= 1.0 {
                    physSetSucceeded = true
                }
            }
        }

        // 2. Резервный путь для встроенных/виртуальных устройств, требующих предварительной смены NominalSampleRate
        if !physSetSucceeded && abs(Self.nominalSampleRate(deviceID: deviceID) - targetRate) > 0.5 {
            var desiredRate = targetRate
            if AudioObjectSetPropertyData(deviceID, &rateAddr, 0, nil, rateSize, &desiredRate) == noErr {
                for _ in 0..<60 {
                    if abs(Self.nominalSampleRate(deviceID: deviceID) - targetRate) <= 1.0 { break }
                    usleep(10_000)
                }
            }
            chosenPhysASBD = selectBestPhysASBD(getAvailablePhysicalFormats(for: primaryStream))
            if var retryPhys = chosenPhysASBD {
                if AudioObjectSetPropertyData(primaryStream, &physAddr, 0, nil, asbdSize, &retryPhys) == noErr {
                    for _ in 0..<40 {
                        if let p = currentStreamFormat(for: primaryStream, selector: kAudioStreamPropertyPhysicalFormat),
                           abs(p.mSampleRate - targetRate) <= 1.0 {
                            break
                        }
                        usleep(10_000)
                    }
                }
            }
        }

        // 3. Проверка и при необходимости доводка VirtualFormat в Non-Mixable Integer (0x4c / 0x54)
        if preferNonMixable {
            let availableVirt = getAvailableVirtualFormats(for: primaryStream)
            let chosenVirtDesc = availableVirt.first(where: { isSignedIntFormat($0.mFormat, 32) && isNonMixable($0.mFormat) && rateMatches($0) })
                ?? availableVirt.first(where: { isSignedIntFormat($0.mFormat, 24) && isNonMixable($0.mFormat) && rateMatches($0) })
                ?? availableVirt.first(where: { isSignedIntFormat($0.mFormat, 32) && rateMatches($0) })
                ?? availableVirt.first(where: { isSignedIntFormat($0.mFormat, 24) && rateMatches($0) })

            if let virtDesc = chosenVirtDesc {
                var targetVirtASBD = virtDesc.mFormat
                targetVirtASBD.mSampleRate = targetRate
                var virtAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioStreamPropertyVirtualFormat,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                let curVirt = currentStreamFormat(for: primaryStream, selector: kAudioStreamPropertyVirtualFormat)
                let alreadyMatchesVirt = curVirt.map {
                    abs($0.mSampleRate - targetVirtASBD.mSampleRate) <= 0.5
                        && $0.mFormatFlags == targetVirtASBD.mFormatFlags
                        && $0.mBitsPerChannel == targetVirtASBD.mBitsPerChannel
                        && $0.mBytesPerFrame == targetVirtASBD.mBytesPerFrame
                } ?? false

                if !alreadyMatchesVirt {
                    var isVirtSettable: DarwinBoolean = false
                    if AudioObjectIsPropertySettable(primaryStream, &virtAddr, &isVirtSettable) == noErr, isVirtSettable.boolValue {
                        if AudioObjectSetPropertyData(primaryStream, &virtAddr, 0, nil, asbdSize, &targetVirtASBD) == noErr {
                            for _ in 0..<40 {
                                if let v = currentStreamFormat(for: primaryStream, selector: kAudioStreamPropertyVirtualFormat),
                                   abs(v.mSampleRate - targetRate) <= 1.0,
                                   v.mFormatFlags == targetVirtASBD.mFormatFlags {
                                    break
                                }
                                usleep(10_000)
                            }
                        }
                    }
                }
            }
        }

        // 4. Согласование оптимального размера аппаратного буфера (BufferFrameSize)
        configureHardwareBufferFrameSize(deviceID: deviceID, sampleRateHz: targetSampleRateHz)

        // 5. Считываем фактический активный VirtualFormat потока, в котором CoreAudio будет вызывать RealtimeIOProc
        if let activeVirt = currentStreamFormat(for: primaryStream, selector: kAudioStreamPropertyVirtualFormat) {
            let mapped = Self.mapASBDToHALStreamFormat(activeVirt)
            let activePhys = currentStreamFormat(for: primaryStream, selector: kAudioStreamPropertyPhysicalFormat)
            NSLog(
                "[HALDeviceManager] 🎛 Stream %u negotiated: rate=%.0fHz, virtFlags=0x%x (%u-bit, %uB/f), physFlags=0x%x (%u-bit), ioFormat=%u, integer=%d",
                primaryStream,
                activeVirt.mSampleRate,
                activeVirt.mFormatFlags,
                activeVirt.mBitsPerChannel,
                activeVirt.mBytesPerFrame,
                activePhys?.mFormatFlags ?? 0,
                activePhys?.mBitsPerChannel ?? 0,
                mapped.format.rawValue,
                mapped.isInteger ? 1 : 0
            )
            return (primaryStream, mapped.format, mapped.bitDepth, mapped.isInteger)
        }

        if let activePhys = currentStreamFormat(for: primaryStream, selector: kAudioStreamPropertyPhysicalFormat) {
            let mapped = Self.mapASBDToHALStreamFormat(activePhys)
            return (primaryStream, mapped.format, mapped.bitDepth, mapped.isInteger)
        }

        return (primaryStream, .float32LE, 32, false)
    }

    internal func configureHardwareBufferFrameSize(deviceID: AudioDeviceID, sampleRateHz: Int) {
        guard deviceID != 0 else { return }
        var rangeAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSizeRange,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var range = AudioValueRange(mMinimum: 64, mMaximum: 4096)
        var rangeSize = UInt32(MemoryLayout<AudioValueRange>.size)
        _ = AudioObjectGetPropertyData(deviceID, &rangeAddr, 0, nil, &rangeSize, &range)

        let preferredFrames: Int
        if sampleRateHz >= 176_400 {
            preferredFrames = 2048
        } else if sampleRateHz >= 88_200 {
            preferredFrames = 1024
        } else {
            preferredFrames = 512
        }
        let maxSafe = min(max(range.mMinimum, 256.0), min(range.mMaximum, 4096.0))
        let clamped = UInt32(min(max(Double(preferredFrames), range.mMinimum), maxSafe))

        var bufAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var curFrames: UInt32 = 0
        var u32Size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(deviceID, &bufAddr, 0, nil, &u32Size, &curFrames) == noErr, curFrames == clamped {
            return
        }
        var targetFrames = clamped
        _ = AudioObjectSetPropertyData(deviceID, &bufAddr, 0, nil, u32Size, &targetFrames)
    }

    // MARK: - Bit-Transparent DoP Controls & Mixable Format Restoration

    /// Гарантирует отсутствие аппаратного Mute и цифрового ослабления громкости (0.0 dB = 1.0) в UAC2 Feature Unit внешнего ЦАП/DDC в режиме DoP.
    internal func ensureBitTransparentHardwareControlsForDoPLocked(deviceID: AudioDeviceID) {
        guard deviceID != 0, !Self.isBuiltInDevice(deviceID) else { return }

        let elements: [UInt32] = [kAudioObjectPropertyElementMain, 1, 2]
        let u32Size = UInt32(MemoryLayout<UInt32>.size)
        let f32Size = UInt32(MemoryLayout<Float32>.size)

        for elem in elements {
            var muteAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: elem
            )
            var settableMute: DarwinBoolean = false
            if AudioObjectHasProperty(deviceID, &muteAddr),
               AudioObjectIsPropertySettable(deviceID, &muteAddr, &settableMute) == noErr,
               settableMute.boolValue {
                var muted: UInt32 = 0
                var sz = u32Size
                if AudioObjectGetPropertyData(deviceID, &muteAddr, 0, nil, &sz, &muted) == noErr, muted != 0 {
                    var unmute: UInt32 = 0
                    _ = AudioObjectSetPropertyData(deviceID, &muteAddr, 0, nil, u32Size, &unmute)
                }
            }

            var volAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: elem
            )
            var settableVol: DarwinBoolean = false
            if AudioObjectHasProperty(deviceID, &volAddr),
               AudioObjectIsPropertySettable(deviceID, &volAddr, &settableVol) == noErr,
               settableVol.boolValue {
                var curVol: Float32 = 1.0
                var sz = f32Size
                if AudioObjectGetPropertyData(deviceID, &volAddr, 0, nil, &sz, &curVol) == noErr, curVol < 0.999 {
                    if !savedOutputVolumes.contains(where: { $0.element == elem }) {
                        savedOutputVolumes.append((element: elem, scalar: curVol))
                    }
                    var unity: Float32 = 1.0
                    _ = AudioObjectSetPropertyData(deviceID, &volAddr, 0, nil, f32Size, &unity)
                    NSLog("[HALDeviceManager] 🔊 Set UAC2 hardware volume element %u to 1.0 (was %.3f) for bit-exact DoP", elem, curVol)
                }
            }
        }
    }

    internal func restoreMixableFormatAndControlsBeforeReleaseLocked(
        deviceID: AudioDeviceID,
        streamID: AudioStreamID,
        restoreOriginalSampleRate: Bool = false
    ) {
        guard deviceID != 0 else { return }

        // Восстанавливаем исходную аппаратную громкость, если меняли её для DoP
        if !savedOutputVolumes.isEmpty {
            let f32Size = UInt32(MemoryLayout<Float32>.size)
            for item in savedOutputVolumes {
                var volAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyVolumeScalar,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: item.element
                )
                var prev = item.scalar
                _ = AudioObjectSetPropertyData(deviceID, &volAddr, 0, nil, f32Size, &prev)
            }
            savedOutputVolumes.removeAll()
        }

        let effectiveStreamID = (streamID != 0) ? streamID : (getOutputStreams(for: deviceID).first ?? 0)
        let targetRestoreRate: Float64 = {
            if restoreOriginalSampleRate, let origRate = savedOriginalSampleRate, origRate > 0 {
                return origRate
            }
            return Self.nominalSampleRate(deviceID: deviceID)
        }()

        if restoreOriginalSampleRate, abs(Self.nominalSampleRate(deviceID: deviceID) - targetRestoreRate) > 0.5 {
            var rateAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var rateVal = targetRestoreRate
            _ = AudioObjectSetPropertyData(deviceID, &rateAddr, 0, nil, UInt32(MemoryLayout<Float64>.size), &rateVal)
        }

        guard effectiveStreamID != 0 else { return }
        let asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

        // При откате сбоя startOutput в первую очередь возвращаем точную сохранённую микшируемую конфигурацию потока
        if restoreOriginalSampleRate,
           var origPhys = savedOriginalPhysicalFormat,
           (origPhys.mFormatFlags & kAudioFormatFlagIsNonMixable) == 0 {
            var physAddr = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyPhysicalFormat,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            _ = AudioObjectSetPropertyData(effectiveStreamID, &physAddr, 0, nil, asbdSize, &origPhys)
        } else {
            let availPhys = getAvailablePhysicalFormats(for: effectiveStreamID)
            if let mixablePhys = availPhys.first(where: { desc in
                let f = desc.mFormat
                let mixable = (f.mFormatFlags & kAudioFormatFlagIsNonMixable) == 0
                let rateOk = targetRestoreRate >= (desc.mSampleRateRange.mMinimum - 1.0) && targetRestoreRate <= (desc.mSampleRateRange.mMaximum + 1.0)
                return f.mFormatID == kAudioFormatLinearPCM && mixable && f.mBitsPerChannel >= 24 && rateOk
            }) {
                var restorePhys = mixablePhys.mFormat
                restorePhys.mSampleRate = targetRestoreRate
                var physAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioStreamPropertyPhysicalFormat,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                _ = AudioObjectSetPropertyData(effectiveStreamID, &physAddr, 0, nil, asbdSize, &restorePhys)
            }
        }

        if restoreOriginalSampleRate,
           var origVirt = savedOriginalVirtualFormat,
           (origVirt.mFormatFlags & kAudioFormatFlagIsNonMixable) == 0 {
            var virtAddr = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyVirtualFormat,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            _ = AudioObjectSetPropertyData(effectiveStreamID, &virtAddr, 0, nil, asbdSize, &origVirt)
        } else {
            let availVirt = getAvailableVirtualFormats(for: effectiveStreamID)
            if let mixableFloatVirt = availVirt.first(where: { desc in
                let f = desc.mFormat
                let isFloatMixable = (f.mFormatFlags & kAudioFormatFlagIsFloat) != 0 && (f.mFormatFlags & kAudioFormatFlagIsNonMixable) == 0
                let rateOk = targetRestoreRate >= (desc.mSampleRateRange.mMinimum - 1.0) && targetRestoreRate <= (desc.mSampleRateRange.mMaximum + 1.0)
                return f.mFormatID == kAudioFormatLinearPCM && isFloatMixable && rateOk
            }) {
                var restoreVirt = mixableFloatVirt.mFormat
                restoreVirt.mSampleRate = targetRestoreRate
                var virtAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioStreamPropertyVirtualFormat,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                _ = AudioObjectSetPropertyData(effectiveStreamID, &virtAddr, 0, nil, asbdSize, &restoreVirt)
            }
        }
    }
}
