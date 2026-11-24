//
//  DoPFramePacker.swift
//  AppleMusicRemoteMac
//
//  Bit-exact DSD over PCM (DoP v1.1) Frame Packer (S32_LE & S24_3LE)
//  + Neutral DSD Silence Generator (0x69) + 15ms Cosine Fade Envelope.
//  Zero Heap Allocations, Zero ARC in hot loops.
//

import Foundation

public typealias DoPFramePacker = DoPPackerState

/// Состояние упаковщика DoP v1.1, сохраняемое сквозь границы чанков и буферов CoreAudio IOProc.
@frozen
public struct DoPPackerState: Sendable {
    /// Флаг чередования маркера DoP: `false` -> `0x05`, `true` -> `0xFA`.
    public var altMarker: Bool = false

    /// Байт нейтральной DSD-тишины (`01101001` = 4 единицы и 4 нуля, нулевое среднее напряжение).
    public static let dsdSilenceByte: UInt8 = 0x69

    /// Готовые 32-битные слова DSD-тишины со сдвигом на 8 бит влево к старшему краю S32_LE.
    public static let silenceFrame05: Int32 = Int32(bitPattern: 0x05696900)
    public static let silenceFrameFA: Int32 = Int32(bitPattern: 0xFA696900)

    public init(altMarker: Bool = false) {
        self.altMarker = altMarker
    }

    public mutating func reset() {
        self.altMarker = false
    }

    /// Упаковывает один стерео-фрейм DoP (по 2 байта `msb`, `lsb` на канал) в пару 32-битных `Int32` (`S32_LE`).
    @inlinable
    public mutating func packStereoFrameS32(
        lMSB: UInt8,
        lLSB: UInt8,
        rMSB: UInt8,
        rLSB: UInt8
    ) -> (left: Int32, right: Int32) {
        let marker: UInt32 = altMarker ? 0xFA : 0x05
        altMarker.toggle()
        let frameL = Int32(bitPattern: (marker << 24) | (UInt32(lMSB) << 16) | (UInt32(lLSB) << 8))
        let frameR = Int32(bitPattern: (marker << 24) | (UInt32(rMSB) << 16) | (UInt32(rLSB) << 8))
        return (frameL, frameR)
    }

    /// Генерирует один стерео-фрейм нейтральной DSD-тишины (`0x69`) с корректным чередованием маркеров `0x05` / `0xFA`.
    @inlinable
    public mutating func nextSilenceStereoFrameS32() -> (left: Int32, right: Int32) {
        let word: Int32 = altMarker ? Self.silenceFrameFA : Self.silenceFrame05
        altMarker.toggle()
        return (word, word)
    }

    /// Заполняет выходной интерливированный буфер `Int32` (`stereoFrameCount * 2` слов) нейтральной DSD-тишиной `0x69`.
    /// Категорически исключает запись `0x00000000`, предотвращая срыв DoP-маркера и щелчок в акустике.
    @inlinable
    public mutating func fillSilenceS32(
        into interleavedOutput: UnsafeMutablePointer<Int32>,
        stereoFrameCount: Int
    ) {
        guard stereoFrameCount > 0 else { return }
        var markerFlag = altMarker
        for f in 0..<stereoFrameCount {
            let word: Int32 = markerFlag ? Self.silenceFrameFA : Self.silenceFrame05
            markerFlag.toggle()
            let base = f &<< 1
            interleavedOutput[base] = word
            interleavedOutput[base &+ 1] = word
        }
        altMarker = markerFlag
    }

    @inlinable
    public static func fillSilenceStereo32(
        state: inout DoPPackerState,
        interleavedOutput: UnsafeMutablePointer<Int32>,
        frameCount: Int
    ) {
        state.fillSilenceS32(into: interleavedOutput, stereoFrameCount: frameCount)
    }

    @inlinable
    public mutating func fillNeutralDSDSilenceS32LE(
        dopFrameCount: Int,
        outputInterleaved32: UnsafeMutablePointer<Int32>
    ) {
        fillSilenceS32(into: outputInterleaved32, stereoFrameCount: dopFrameCount)
    }

    /// Упаковывает планарные массивы байтов DSD (MSB-first, по `stereoFrameCount * 2` байт на канал)
    /// в интерливированный массив `Int32` (`stereoFrameCount * 2` слов `S32_LE`).
    @inlinable
    public mutating func packPlanarBytesToInterleavedS32(
        leftBytes: UnsafePointer<UInt8>,
        rightBytes: UnsafePointer<UInt8>,
        stereoFrameCount: Int,
        into interleavedOutput: UnsafeMutablePointer<Int32>
    ) {
        guard stereoFrameCount > 0 else { return }
        var markerFlag = altMarker
        for f in 0..<stereoFrameCount {
            let byteOffset = f &<< 1
            let lMSB = leftBytes[byteOffset]
            let lLSB = leftBytes[byteOffset &+ 1]
            let rMSB = rightBytes[byteOffset]
            let rLSB = rightBytes[byteOffset &+ 1]

            let marker: UInt32 = markerFlag ? 0xFA : 0x05
            markerFlag.toggle()

            let mShift = marker &<< 24
            let frameL = Int32(bitPattern: mShift | (UInt32(lMSB) &<< 16) | (UInt32(lLSB) &<< 8))
            let frameR = Int32(bitPattern: mShift | (UInt32(rMSB) &<< 16) | (UInt32(rLSB) &<< 8))

            let outBase = f &<< 1
            interleavedOutput[outBase] = frameL
            interleavedOutput[outBase &+ 1] = frameR
        }
        altMarker = markerFlag
    }

    @inlinable
    public static func packStereoDSDBytesToDoP32(
        state: inout DoPPackerState,
        dsdLeftBytes: UnsafePointer<UInt8>,
        dsdRightBytes: UnsafePointer<UInt8>,
        dopFrameCount: Int,
        interleavedOutput: UnsafeMutablePointer<Int32>
    ) {
        state.packPlanarBytesToInterleavedS32(
            leftBytes: dsdLeftBytes,
            rightBytes: dsdRightBytes,
            stereoFrameCount: dopFrameCount,
            into: interleavedOutput
        )
    }

    @inlinable
    public mutating func packS32LE(
        dsdLeftBytes: UnsafePointer<UInt8>,
        dsdRightBytes: UnsafePointer<UInt8>,
        dopFrameCount: Int,
        outputInterleaved32: UnsafeMutablePointer<Int32>
    ) {
        packPlanarBytesToInterleavedS32(
            leftBytes: dsdLeftBytes,
            rightBytes: dsdRightBytes,
            stereoFrameCount: dopFrameCount,
            into: outputInterleaved32
        )
    }

    /// Распаковывает интерливированные 32-битные DoP-слова (`S32_LE`) обратно в планарные массивы байтов DSD,
    /// проверяя корректность чередования маркеров `0x05` / `0xFA`.
    @inlinable
    public static func unpackS32LE(
        interleaved32: UnsafePointer<Int32>,
        dopFrameCount: Int,
        outLeftBytes: UnsafeMutablePointer<UInt8>,
        outRightBytes: UnsafeMutablePointer<UInt8>
    ) -> Bool {
        guard dopFrameCount > 0 else { return true }
        var validMarkers = true
        let firstMarker = UInt8((UInt32(bitPattern: interleaved32[0]) >> 24) & 0xFF)
        var expectFA = (firstMarker == 0xFA)
        if firstMarker != 0x05 && firstMarker != 0xFA {
            validMarkers = false
        }

        for f in 0..<dopFrameCount {
            let wordL = UInt32(bitPattern: interleaved32[f * 2])
            let wordR = UInt32(bitPattern: interleaved32[f * 2 + 1])
            let mL = UInt8((wordL >> 24) & 0xFF)
            let mR = UInt8((wordR >> 24) & 0xFF)
            let expected: UInt8 = expectFA ? 0xFA : 0x05
            if mL != expected || mR != expected {
                validMarkers = false
            }
            expectFA.toggle()

            let byteIdx = f * 2
            outLeftBytes[byteIdx]      = UInt8((wordL >> 16) & 0xFF)
            outLeftBytes[byteIdx + 1]  = UInt8((wordL >> 8) & 0xFF)
            outRightBytes[byteIdx]     = UInt8((wordR >> 16) & 0xFF)
            outRightBytes[byteIdx + 1] = UInt8((wordR >> 8) & 0xFF)
        }
        return validMarkers
    }

    /// Конвертирует интерливированные 32-битные DoP-слова (`S32_LE`, где младший байт равен `0x00`)
    /// в плотный 24-битный формат `S24_3LE` (`6 байт на стерео-фрейм`: `[l_lsb, l_msb, marker, r_lsb, r_msb, marker]`).
    @inlinable
    public static func convertS32ToPacked24LE(
        from s32Input: UnsafePointer<Int32>,
        wordCount: Int,
        into packed24Output: UnsafeMutablePointer<UInt8>
    ) {
        guard wordCount > 0 else { return }
        for i in 0..<wordCount {
            let u = UInt32(bitPattern: s32Input[i])
            let dst = i * 3
            packed24Output[dst]     = UInt8((u &>> 8) & 0xFF)  // LSB
            packed24Output[dst + 1] = UInt8((u &>> 16) & 0xFF) // MSB
            packed24Output[dst + 2] = UInt8((u &>> 24) & 0xFF) // DoP Marker (0x05 / 0xFA)
        }
    }

    /// Заполняет плотный 24-битный буфер (`S24_3LE`, 6 байт на стерео-фрейм) нейтральной DSD-тишиной `0x69`.
    @inlinable
    public mutating func fillSilencePacked24LE(
        into packed24Output: UnsafeMutablePointer<UInt8>,
        stereoFrameCount: Int
    ) {
        guard stereoFrameCount > 0 else { return }
        var markerFlag = altMarker
        for f in 0..<stereoFrameCount {
            let marker: UInt8 = markerFlag ? 0xFA : 0x05
            markerFlag.toggle()
            let base = f * 6
            packed24Output[base]     = Self.dsdSilenceByte
            packed24Output[base + 1] = Self.dsdSilenceByte
            packed24Output[base + 2] = marker
            packed24Output[base + 3] = Self.dsdSilenceByte
            packed24Output[base + 4] = Self.dsdSilenceByte
            packed24Output[base + 5] = marker
        }
        altMarker = markerFlag
    }
}

/// Упаковщик потока 1-битных отсчётов (`{-1.0, +1.0}` или битов `0/1`) строго в порядок MSB-first.
@frozen
public enum DSDBitPacker {
    /// Упаковывает 8 последовательных значений `Double` (`>= 0.0` -> `1`, `< 0.0` -> `0`) в один байт MSB-first
    /// (первый по времени отсчёт `samples[0]` укладывается в `bit 7`, `samples[7]` — в `bit 0`).
    @inlinable
    public static func pack8SamplesMSBFirst(_ samples: UnsafePointer<Double>) -> UInt8 {
        var byte: UInt8 = 0
        if samples[0] >= 0.0 { byte |= 0x80 }
        if samples[1] >= 0.0 { byte |= 0x40 }
        if samples[2] >= 0.0 { byte |= 0x20 }
        if samples[3] >= 0.0 { byte |= 0x10 }
        if samples[4] >= 0.0 { byte |= 0x08 }
        if samples[5] >= 0.0 { byte |= 0x04 }
        if samples[6] >= 0.0 { byte |= 0x02 }
        if samples[7] >= 0.0 { byte |= 0x01 }
        return byte
    }
}

/// Генератор 15-мс косинусной огибающей fade-in / fade-out на входе модулятора
/// для бесщелчкового старта, паузы и переключения частоты.
@frozen
public struct CosineFadeEnvelope: Sendable {
    public var currentGain: Double = 1.0
    public var targetGain: Double = 1.0
    public var totalSamples: Int = 0
    public var elapsedSamples: Int = 0
    public var startGain: Double = 1.0

    public init(initialGain: Double = 1.0) {
        self.currentGain = initialGain
        self.targetGain = initialGain
        self.startGain = initialGain
    }

    /// Запускает плавный косинусный переход к `target` (`0.0` или `1.0`) за `durationMs` (по умолчанию 15 мс).
    public mutating func startRamp(to target: Double, sampleRateHz: Int, durationMs: Double = 15.0) {
        self.startGain = self.currentGain
        self.targetGain = min(max(target, 0.0), 1.0)
        self.totalSamples = max(1, Int(round(Double(sampleRateHz) * (durationMs / 1000.0))))
        self.elapsedSamples = 0
    }

    public mutating func triggerFadeIn(sampleRate: Double, durationMs: Double = 15.0) {
        self.currentGain = 0.0
        startRamp(to: 1.0, sampleRateHz: max(1, Int(sampleRate.rounded())), durationMs: durationMs)
    }

    /// Возвращает следующий множитель огибающей по закону `0.5 * (1 - cos(pi * t))`.
    @inlinable
    public mutating func nextMultiplier() -> Double {
        guard elapsedSamples < totalSamples else {
            currentGain = targetGain
            return currentGain
        }
        elapsedSamples &+= 1
        let phase = Double(elapsedSamples) / Double(totalSamples)
        let shaped = 0.5 * (1.0 - cos(Double.pi * phase))
        currentGain = startGain + (targetGain - startGain) * shaped
        return currentGain
    }

    @inlinable
    public mutating func nextGain() -> Double {
        nextMultiplier()
    }
}
