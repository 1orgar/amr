//
//  RealtimeIOProc.swift
//  AppleMusicRemoteMac
//
//  Zero-Allocation, Zero-ARC, Zero-Lock @convention(c) CoreAudio HAL IOProc Callback.
//  Reads packed S32_LE DoP or HQ NOS PCM frames via SPSCRingRawView (pure C pointers, zero swift_retain/release),
//  enforces monotonic 0x05 <-> 0xFA DoP marker continuity across any underrun or odd frame size,
//  and outputs neutral DSD Silence (0x69 with 0x05/0xFA markers) on idle/underrun.
//

import Foundation
import CoreAudio
import Darwin

/// Физический формат контейнера выходного потока CoreAudio HAL.
public enum HALPhysicalStreamFormat: UInt32, Sendable {
    /// 32-bit Signed Integer Little-Endian (`S32_LE`, 4 байта на сэмпл / 8 байт на стерео-фрейм, либо 24-in-32 High-Aligned).
    case signedInt32LE = 0
    /// 24-bit Packed Signed Integer Little-Endian (`S24_3LE`, 3 байта на сэмпл / 6 байт на стерео-фрейм).
    case signedInt24PackedLE = 1
    /// 32-bit Float (`Float32`, резервный режим для виртуальных/встроенных устройств без Integer Mode).
    case float32LE = 2
    /// 24-bit Low-Aligned Signed Integer в 32-битном контейнере (`S24_4LE`, значащие биты 0..23).
    case signedInt24LowAligned32LE = 3
}

/// Выровненный в памяти C-контекст для `AudioDeviceIOProc` без ссылок ARC в горячем цикле.
@frozen
public struct RealtimeIOContext {
    /// Прямое Zero-ARC представление кольцевого буфера (сырые указатели на данные и индексы).
    /// Владение объектом `SPSCAtomicRingBuffer` удерживается в `HALDeviceManager` до завершения `AudioDeviceStop`.
    public var ringView: SPSCRingRawView?
    /// Совместимое поле сырого указателя (не разыменовывается через `Unmanaged` в RT-потоке).
    public var ringBufferPtr: UnsafeMutableRawPointer?
    /// `1` — режим DoP (при опустошении генерируется DSD-тишина `0x69` с маркерами `0x05`/`0xFA`);
    /// `0` — режим HQ NOS PCM (при опустошении пишется `0`).
    public var isDoPModeFlag: UInt32 = 0
    /// Физический формат выходного буфера (`HALPhysicalStreamFormat.rawValue`).
    public var physicalFormatRaw: UInt32 = HALPhysicalStreamFormat.signedInt32LE.rawValue
    /// Единый авторитетный счётчик чередования маркера DoP (`false -> 0x05`, `true -> 0xFA`) на стороне IOProc,
    /// гарантирующий 100% непрерывность `0x05 <-> 0xFA` при любых опустошениях буфера и нечётных размерах коллбэка.
    public var fallbackDoPState: DoPPackerState = DoPPackerState()
    /// Предвыделенный scratch-буфер (до 8192 стерео-фреймов = 16384 `Int32`), зафиксированный через `mlock()`.
    public var scratchS32: UnsafeMutablePointer<Int32>
    public let scratchWordCapacity: Int
    /// Счётчик вызовов IOProc для телеметрии.
    public var callbackTickCount: UInt64 = 0

    public init(scratchStereoFrames: Int = 8192) {
        let words = max(2048, scratchStereoFrames * 2)
        self.scratchWordCapacity = words
        let byteLen = words * MemoryLayout<Int32>.stride
        let raw = UnsafeMutableRawPointer.allocate(byteCount: byteLen, alignment: 64)
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: byteLen)
        _ = mlock(raw, byteLen)
        self.scratchS32 = raw.bindMemory(to: Int32.self, capacity: words)
    }

    public mutating func deallocateScratch() {
        let byteLen = scratchWordCapacity * MemoryLayout<Int32>.stride
        munlock(scratchS32, byteLen)
        UnsafeMutableRawPointer(scratchS32).deallocate()
    }
}

/// Zero-ARC версия заполнения `stereoFrames` интерливированных пар `Int32` напрямую через `SPSCRingRawView`.
@usableFromInline
@inline(__always)
internal func fillAndStampInterleavedS32FromRingView(
    ringView: SPSCRingRawView?,
    dstInt32: UnsafeMutablePointer<Int32>,
    stereoFrames: Int,
    isDoP: Bool,
    dopState: inout DoPPackerState
) {
    let readWords = ringView?.read(into: dstInt32, count: stereoFrames &* 2) ?? 0
    let readFrames = readWords >> 1

    if isDoP {
        var alt = dopState.altMarker
        // 1. Нормализуем маркеры всех прочитанных из кольца DoP-фреймов под непрерывную фазу IOProc
        for f in 0..<readFrames {
            let markerBits: UInt32 = (alt ? 0xFA : 0x05) &<< 24
            alt.toggle()
            let base = f &<< 1
            let rawL = UInt32(bitPattern: dstInt32[base]) & 0x00FF_FF00
            let rawR = UInt32(bitPattern: dstInt32[base &+ 1]) & 0x00FF_FF00
            dstInt32[base] = Int32(bitPattern: markerBits | rawL)
            dstInt32[base &+ 1] = Int32(bitPattern: markerBits | rawR)
        }
        // 2. При нехватке данных дописываем нейтральную DSD-тишину 0x6969 с продолжением той же фазы alt
        if readFrames < stereoFrames {
            for f in readFrames..<stereoFrames {
                let word: Int32 = alt ? DoPPackerState.silenceFrameFA : DoPPackerState.silenceFrame05
                alt.toggle()
                let base = f &<< 1
                dstInt32[base] = word
                dstInt32[base &+ 1] = word
            }
        }
        dopState.altMarker = alt
    } else if readFrames < stereoFrames {
        let missingFrames = stereoFrames - readFrames
        let tailPtr = dstInt32.advanced(by: readFrames &* 2)
        memset(tailPtr, 0, missingFrames &* 2 &* MemoryLayout<Int32>.stride)
    }
}

/// Удобная обёртка для модульных тестов (`SDMVerificationTests`), делегирующая в `fillAndStampInterleavedS32FromRingView`.
@usableFromInline
@inline(__always)
internal func fillAndStampInterleavedS32FromRing(
    ring: SPSCAtomicRingBuffer?,
    dstInt32: UnsafeMutablePointer<Int32>,
    stereoFrames: Int,
    isDoP: Bool,
    dopState: inout DoPPackerState
) {
    fillAndStampInterleavedS32FromRingView(
        ringView: ring?.rawView,
        dstInt32: dstInt32,
        stereoFrames: stereoFrames,
        isDoP: isDoP,
        dopState: &dopState
    )
}

@inline(__always)
private func zeroRemainingBytes(_ basePtr: UnsafeMutableRawPointer, writtenBytes: Int, totalByteSize: Int) {
    if writtenBytes < totalByteSize {
        memset(basePtr.advanced(by: writtenBytes), 0, totalByteSize - writtenBytes)
    }
}

/// Глобальная `@convention(c)` функция обратного вызова CoreAudio HAL.
/// Не захватывает контекст, не вызывает ARC (`swift_retain`/`swift_release`) и не берёт блокировок.
public let realtimeHALAudioIOProc: AudioDeviceIOProc = { (
    _ inDevice: AudioObjectID,
    _ inNow: UnsafePointer<AudioTimeStamp>,
    _ inInputData: UnsafePointer<AudioBufferList>,
    _ inInputTime: UnsafePointer<AudioTimeStamp>,
    _ outOutputData: UnsafeMutablePointer<AudioBufferList>,
    _ inOutputTime: UnsafePointer<AudioTimeStamp>,
    _ inClientData: UnsafeMutableRawPointer?
) -> OSStatus in
    let abl = UnsafeMutableAudioBufferListPointer(outOutputData)
    guard !abl.isEmpty else { return noErr }

    guard let clientRaw = inClientData else {
        for idx in 0..<abl.count {
            if let data = abl[idx].mData, abl[idx].mDataByteSize > 0 {
                memset(data, 0, Int(abl[idx].mDataByteSize))
            }
        }
        return noErr
    }

    let ctxPtr = clientRaw.assumingMemoryBound(to: RealtimeIOContext.self)
    ctxPtr.pointee.callbackTickCount &+= 1

    let isDoP = (ctxPtr.pointee.isDoPModeFlag != 0)
    let format = HALPhysicalStreamFormat(rawValue: ctxPtr.pointee.physicalFormatRaw) ?? .signedInt32LE
    let ringView = ctxPtr.pointee.ringView

    if abl.count == 1, let outData = abl[0].mData {
        // Интерливированный выходной буфер (2 канала в одном AudioBuffer)
        let byteSize = Int(abl[0].mDataByteSize)
        guard byteSize > 0 else { return noErr }

        switch format {
        case .signedInt32LE:
            let totalWords = byteSize / MemoryLayout<Int32>.stride
            let stereoFrames = totalWords / 2
            guard stereoFrames > 0 else {
                memset(outData, 0, byteSize)
                return noErr
            }
            let dstInt32 = outData.assumingMemoryBound(to: Int32.self)
            fillAndStampInterleavedS32FromRingView(
                ringView: ringView,
                dstInt32: dstInt32,
                stereoFrames: stereoFrames,
                isDoP: isDoP,
                dopState: &ctxPtr.pointee.fallbackDoPState
            )
            zeroRemainingBytes(outData, writtenBytes: stereoFrames * 2 * MemoryLayout<Int32>.stride, totalByteSize: byteSize)

        case .signedInt24PackedLE:
            let stereoFrames = min(byteSize / 6, ctxPtr.pointee.scratchWordCapacity / 2)
            guard stereoFrames > 0 else {
                memset(outData, 0, byteSize)
                return noErr
            }
            let scratch = ctxPtr.pointee.scratchS32
            fillAndStampInterleavedS32FromRingView(
                ringView: ringView,
                dstInt32: scratch,
                stereoFrames: stereoFrames,
                isDoP: isDoP,
                dopState: &ctxPtr.pointee.fallbackDoPState
            )
            let dstUInt8 = outData.assumingMemoryBound(to: UInt8.self)
            DoPPackerState.convertS32ToPacked24LE(
                from: scratch,
                wordCount: stereoFrames * 2,
                into: dstUInt8
            )
            zeroRemainingBytes(outData, writtenBytes: stereoFrames * 6, totalByteSize: byteSize)

        case .signedInt24LowAligned32LE:
            let totalWords = byteSize / MemoryLayout<Int32>.stride
            let stereoFrames = min(totalWords / 2, ctxPtr.pointee.scratchWordCapacity / 2)
            guard stereoFrames > 0 else {
                memset(outData, 0, byteSize)
                return noErr
            }
            let scratch = ctxPtr.pointee.scratchS32
            fillAndStampInterleavedS32FromRingView(
                ringView: ringView,
                dstInt32: scratch,
                stereoFrames: stereoFrames,
                isDoP: isDoP,
                dopState: &ctxPtr.pointee.fallbackDoPState
            )
            let dstInt32 = outData.assumingMemoryBound(to: Int32.self)
            for i in 0..<(stereoFrames * 2) {
                dstInt32[i] = scratch[i] >> 8
            }
            zeroRemainingBytes(outData, writtenBytes: stereoFrames * 2 * MemoryLayout<Int32>.stride, totalByteSize: byteSize)

        case .float32LE:
            let totalFloats = byteSize / MemoryLayout<Float>.stride
            let stereoFrames = min(totalFloats / 2, ctxPtr.pointee.scratchWordCapacity / 2)
            guard stereoFrames > 0 else {
                memset(outData, 0, byteSize)
                return noErr
            }
            let scratch = ctxPtr.pointee.scratchS32
            fillAndStampInterleavedS32FromRingView(
                ringView: ringView,
                dstInt32: scratch,
                stereoFrames: stereoFrames,
                isDoP: isDoP,
                dopState: &ctxPtr.pointee.fallbackDoPState
            )
            let dstFloat = outData.assumingMemoryBound(to: Float.self)
            if isDoP {
                // Точное биективное отображение 24-битного слова DoP в мантиссу IEEE-754 Float32 (2^-23 без ошибки округления)
                let scale24 = Float(bitPattern: 0x3400_0000)
                for i in 0..<(stereoFrames * 2) {
                    dstFloat[i] = Float(scratch[i] >> 8) * scale24
                }
            } else {
                let scale32 = Float(bitPattern: 0x3000_0000)
                for i in 0..<(stereoFrames * 2) {
                    dstFloat[i] = Float(scratch[i]) * scale32
                }
            }
            zeroRemainingBytes(outData, writtenBytes: stereoFrames * 2 * MemoryLayout<Float>.stride, totalByteSize: byteSize)
        }
    } else if abl.count >= 2, let leftOut = abl[0].mData, let rightOut = abl[1].mData {
        // Неинтерливированный (планарный) выходной буфер
        let leftByteSize = Int(abl[0].mDataByteSize)
        let rightByteSize = Int(abl[1].mDataByteSize)
        let byteSize = min(leftByteSize, rightByteSize)
        let bytesPerSample = (format == .signedInt24PackedLE) ? 3 : 4
        let stereoFrames = min(byteSize / bytesPerSample, ctxPtr.pointee.scratchWordCapacity / 2)

        if abl.count > 2 {
            for ch in 2..<abl.count {
                if let extraData = abl[ch].mData, abl[ch].mDataByteSize > 0 {
                    memset(extraData, 0, Int(abl[ch].mDataByteSize))
                }
            }
        }

        guard stereoFrames > 0 else {
            if leftByteSize > 0 { memset(leftOut, 0, leftByteSize) }
            if rightByteSize > 0 { memset(rightOut, 0, rightByteSize) }
            return noErr
        }

        let scratch = ctxPtr.pointee.scratchS32
        fillAndStampInterleavedS32FromRingView(
            ringView: ringView,
            dstInt32: scratch,
            stereoFrames: stereoFrames,
            isDoP: isDoP,
            dopState: &ctxPtr.pointee.fallbackDoPState
        )

        switch format {
        case .float32LE:
            let lDst = leftOut.assumingMemoryBound(to: Float.self)
            let rDst = rightOut.assumingMemoryBound(to: Float.self)
            if isDoP {
                let scale24 = Float(bitPattern: 0x3400_0000)
                for f in 0..<stereoFrames {
                    lDst[f] = Float(scratch[f * 2] >> 8) * scale24
                    rDst[f] = Float(scratch[f * 2 + 1] >> 8) * scale24
                }
            } else {
                let scale32 = Float(bitPattern: 0x3000_0000)
                for f in 0..<stereoFrames {
                    lDst[f] = Float(scratch[f * 2]) * scale32
                    rDst[f] = Float(scratch[f * 2 + 1]) * scale32
                }
            }
        case .signedInt24PackedLE:
            let lDst = leftOut.assumingMemoryBound(to: UInt8.self)
            let rDst = rightOut.assumingMemoryBound(to: UInt8.self)
            for f in 0..<stereoFrames {
                let uL = UInt32(bitPattern: scratch[f * 2])
                let uR = UInt32(bitPattern: scratch[f * 2 + 1])
                let dstIdx = f * 3
                lDst[dstIdx] = UInt8((uL >> 8) & 0xFF)
                lDst[dstIdx + 1] = UInt8((uL >> 16) & 0xFF)
                lDst[dstIdx + 2] = UInt8((uL >> 24) & 0xFF)
                rDst[dstIdx] = UInt8((uR >> 8) & 0xFF)
                rDst[dstIdx + 1] = UInt8((uR >> 16) & 0xFF)
                rDst[dstIdx + 2] = UInt8((uR >> 24) & 0xFF)
            }
        case .signedInt24LowAligned32LE:
            let lDst = leftOut.assumingMemoryBound(to: Int32.self)
            let rDst = rightOut.assumingMemoryBound(to: Int32.self)
            for f in 0..<stereoFrames {
                lDst[f] = scratch[f * 2] >> 8
                rDst[f] = scratch[f * 2 + 1] >> 8
            }
        case .signedInt32LE:
            let lDst = leftOut.assumingMemoryBound(to: Int32.self)
            let rDst = rightOut.assumingMemoryBound(to: Int32.self)
            for f in 0..<stereoFrames {
                lDst[f] = scratch[f * 2]
                rDst[f] = scratch[f * 2 + 1]
            }
        }

        let writtenBytesPerCh = stereoFrames * bytesPerSample
        zeroRemainingBytes(leftOut, writtenBytes: writtenBytesPerCh, totalByteSize: leftByteSize)
        zeroRemainingBytes(rightOut, writtenBytes: writtenBytesPerCh, totalByteSize: rightByteSize)
    } else {
        for idx in 0..<abl.count {
            if let data = abl[idx].mData, abl[idx].mDataByteSize > 0 {
                memset(data, 0, Int(abl[idx].mDataByteSize))
            }
        }
    }

    return noErr
}
