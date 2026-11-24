//
//  SPSCAtomicRingBuffer.swift
//  AppleMusicRemoteMac
//
//  Lock-Free Single-Producer Single-Consumer (SPSC) Ring Buffers
//  with 64-byte alignment, 128-byte False-Sharing isolation, and mlock() RAM pinning.
//  Zero ARC, Zero Heap Allocations, and Zero Locks on Real-Time audio threads.
//

import Foundation
import Darwin
import CAtomicPrimitives

/// Выровненное на 2 кэш-линии Apple Silicon (128 байт) хранилище атомарных индексов SPSC,
/// исключающее False Sharing между потоком-писателем (P-Core Worker) и читателем (CoreAudio IOProc).
@frozen
public struct SPSCCacheAlignedIndices {
    // Кэш-линия #0 (0..<128): принадлежит писателю (Producer)
    public var writeIndex: Int64 = 0
    public var _pad0_1: Int64 = 0
    public var _pad0_2: Int64 = 0
    public var _pad0_3: Int64 = 0
    public var _pad0_4: Int64 = 0
    public var _pad0_5: Int64 = 0
    public var _pad0_6: Int64 = 0
    public var _pad0_7: Int64 = 0
    public var _pad0_8: Int64 = 0
    public var _pad0_9: Int64 = 0
    public var _pad0_10: Int64 = 0
    public var _pad0_11: Int64 = 0
    public var _pad0_12: Int64 = 0
    public var _pad0_13: Int64 = 0
    public var _pad0_14: Int64 = 0
    public var _pad0_15: Int64 = 0

    // Кэш-линия #1 (128..<256): принадлежит читателю (Consumer)
    public var readIndex: Int64 = 0
    public var underrunCount: UInt64 = 0
    public var _pad1_2: Int64 = 0
    public var _pad1_3: Int64 = 0
    public var _pad1_4: Int64 = 0
    public var _pad1_5: Int64 = 0
    public var _pad1_6: Int64 = 0
    public var _pad1_7: Int64 = 0
    public var _pad1_8: Int64 = 0
    public var _pad1_9: Int64 = 0
    public var _pad1_10: Int64 = 0
    public var _pad1_11: Int64 = 0
    public var _pad1_12: Int64 = 0
    public var _pad1_13: Int64 = 0
    public var _pad1_14: Int64 = 0
    public var _pad1_15: Int64 = 0

    public init() {}
}

public extension UnsafeMutablePointer where Pointee == SPSCCacheAlignedIndices {
    /// Указатель на `writeIndex` (смещение 0, кэш-линия #0 писателя) без разыменования `.pointee`.
    @inlinable
    var writeIndexAtomicPtr: UnsafeMutablePointer<Int64> {
        UnsafeMutableRawPointer(self).assumingMemoryBound(to: Int64.self)
    }

    /// Указатель на `readIndex` (смещение 128 байт, кэш-линия #1 читателя) без разыменования `.pointee`.
    @inlinable
    var readIndexAtomicPtr: UnsafeMutablePointer<Int64> {
        UnsafeMutableRawPointer(self).advanced(by: 128).assumingMemoryBound(to: Int64.self)
    }

    /// Указатель на `underrunCount` (смещение 136 байт, кэш-линия #1 читателя) без разыменования `.pointee`.
    @inlinable
    var underrunCountAtomicPtr: UnsafeMutablePointer<UInt64> {
        UnsafeMutableRawPointer(self).advanced(by: 136).assumingMemoryBound(to: UInt64.self)
    }
}

/// Zero-ARC C-совместимый дескриптор кольцевого буфера `SPSCAtomicRingBuffer`.
/// Позволяет `@convention(c)` `AudioDeviceIOProc` читать стерео-слова напрямую по сырым указателям
/// без вызовов `swift_retain` / `swift_release`.
@frozen
public struct SPSCRingRawView {
    public var buffer: UnsafeMutablePointer<Int32>
    public var indicesPtr: UnsafeMutablePointer<SPSCCacheAlignedIndices>
    public var capacity: Int
    public var mask: Int

    @inlinable
    public init(
        buffer: UnsafeMutablePointer<Int32>,
        indicesPtr: UnsafeMutablePointer<SPSCCacheAlignedIndices>,
        capacity: Int,
        mask: Int
    ) {
        self.buffer = buffer
        self.indicesPtr = indicesPtr
        self.capacity = capacity
        self.mask = mask
    }

    /// Читает до `count` элементов `Int32` в `destination`. При чётном `count` гарантирует неразрывность стереопар `(L, R)`.
    @discardableResult
    @inlinable
    public func read(into destination: UnsafeMutablePointer<Int32>, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let rPtr = indicesPtr.readIndexAtomicPtr
        let wPtr = indicesPtr.writeIndexAtomicPtr
        let r = amr_atomic_load_i64_relaxed(rPtr)
        let w = amr_atomic_load_i64_acquire(wPtr)

        let avail = max(0, Int(w - r))
        let rawToRead = min(count, avail)
        let toRead = ((count & 1) == 0) ? (rawToRead & ~1) : rawToRead
        if toRead < count {
            _ = amr_atomic_inc_u64_relaxed(indicesPtr.underrunCountAtomicPtr)
        }
        guard toRead > 0 else { return 0 }

        let startIdx = Int(r) & mask
        let firstPart = min(toRead, capacity - startIdx)
        memcpy(destination, buffer.advanced(by: startIdx), firstPart * MemoryLayout<Int32>.stride)
        if toRead > firstPart {
            let secondPart = toRead - firstPart
            memcpy(destination.advanced(by: firstPart), buffer, secondPart * MemoryLayout<Int32>.stride)
        }

        amr_atomic_store_i64_release(rPtr, r + Int64(toRead))
        return toRead
    }
}

/// Lock-Free SPSC кольцевой буфер для 32-битных слов вывода (`Int32` S32_LE DoP и HQ NOS PCM).
/// Безопасен для вызова из `@convention(c)` `AudioDeviceIOProc` без участия ARC.
public final class SPSCAtomicRingBuffer: @unchecked Sendable {
    public let capacity: Int
    public var capacityWords: Int { capacity }
    public let mask: Int
    @usableFromInline internal let storageRaw: UnsafeMutableRawPointer
    @usableFromInline internal let buffer: UnsafeMutablePointer<Int32>
    @usableFromInline internal let indicesPtr: UnsafeMutablePointer<SPSCCacheAlignedIndices>
    private let byteLength: Int
    private var isLockedInRAM: Bool = false

    public convenience init(capacityWords: Int) {
        self.init(minimumCapacity: capacityWords)
    }

    /// Создаёт кольцевой буфер с ёмкостью, округлённой вверх до ближайшей степени двойки.
    public init(minimumCapacity: Int) {
        var pow2 = 1024
        while pow2 < max(1024, minimumCapacity) {
            pow2 <<= 1
        }
        self.capacity = pow2
        self.mask = pow2 - 1
        self.byteLength = pow2 * MemoryLayout<Int32>.stride

        self.storageRaw = UnsafeMutableRawPointer.allocate(
            byteCount: self.byteLength,
            alignment: 64
        )
        self.storageRaw.initializeMemory(as: UInt8.self, repeating: 0, count: self.byteLength)
        self.buffer = self.storageRaw.bindMemory(to: Int32.self, capacity: pow2)

        let idxRaw = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<SPSCCacheAlignedIndices>.stride,
            alignment: 128
        )
        self.indicesPtr = idxRaw.initializeMemory(as: SPSCCacheAlignedIndices.self, repeating: SPSCCacheAlignedIndices(), count: 1)

        if mlock(self.storageRaw, self.byteLength) == 0 {
            self.isLockedInRAM = true
        }
        _ = mlock(idxRaw, MemoryLayout<SPSCCacheAlignedIndices>.stride)
    }

    deinit {
        if isLockedInRAM {
            munlock(storageRaw, byteLength)
        }
        munlock(indicesPtr, MemoryLayout<SPSCCacheAlignedIndices>.stride)
        storageRaw.deallocate()
        UnsafeMutableRawPointer(indicesPtr).deallocate()
    }

    /// Прямое Zero-ARC представление для передачи в `RealtimeIOContext`.
    @inlinable
    public var rawView: SPSCRingRawView {
        SPSCRingRawView(buffer: buffer, indicesPtr: indicesPtr, capacity: capacity, mask: mask)
    }

    /// Текущее число доступных для чтения элементов `Int32`.
    @inlinable
    public var availableToRead: Int {
        let w = amr_atomic_load_i64_acquire(indicesPtr.writeIndexAtomicPtr)
        let r = amr_atomic_load_i64_acquire(indicesPtr.readIndexAtomicPtr)
        return max(0, Int(w - r))
    }

    /// Текущее свободное место для записи элементов `Int32`.
    @inlinable
    public var availableToWrite: Int {
        let w = amr_atomic_load_i64_acquire(indicesPtr.writeIndexAtomicPtr)
        let r = amr_atomic_load_i64_acquire(indicesPtr.readIndexAtomicPtr)
        return max(0, capacity - Int(w - r))
    }

    /// Процент заполнения кольца (0.0 ... 100.0).
    @inlinable
    public var fillPercentage: Double {
        Double(availableToRead) * 100.0 / Double(capacity)
    }

    /// Счётчик опустошений буфера (underruns) на стороне чтения.
    @inlinable
    public var underrunCount: UInt64 {
        amr_atomic_load_u64_relaxed(indicesPtr.underrunCountAtomicPtr)
    }

    /// Сброс указателей чтения/записи и счётчика опустошений (вызывается только при остановленном IOProc).
    public func reset() {
        amr_atomic_store_i64_release(indicesPtr.writeIndexAtomicPtr, 0)
        amr_atomic_store_i64_release(indicesPtr.readIndexAtomicPtr, 0)
        amr_atomic_store_u64_relaxed(indicesPtr.underrunCountAtomicPtr, 0)
    }

    /// Записывает до `count` элементов `Int32` из `source`. Возвращает число реально записанных слов.
    /// При чётном `count` маскирует `toWrite` до чётного числа слов (`& ~1`), исключая разрыв стереопары `(L, R)`.
    @discardableResult
    @inlinable
    public func write(from source: UnsafePointer<Int32>, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let wPtr = indicesPtr.writeIndexAtomicPtr
        let rPtr = indicesPtr.readIndexAtomicPtr
        let w = amr_atomic_load_i64_relaxed(wPtr)
        let r = amr_atomic_load_i64_acquire(rPtr)

        let freeSpace = max(0, capacity - Int(w - r))
        let rawToWrite = min(count, freeSpace)
        let toWrite = ((count & 1) == 0) ? (rawToWrite & ~1) : rawToWrite
        guard toWrite > 0 else { return 0 }

        let startIdx = Int(w) & mask
        let firstPart = min(toWrite, capacity - startIdx)
        memcpy(buffer.advanced(by: startIdx), source, firstPart * MemoryLayout<Int32>.stride)
        if toWrite > firstPart {
            let secondPart = toWrite - firstPart
            memcpy(buffer, source.advanced(by: firstPart), secondPart * MemoryLayout<Int32>.stride)
        }

        amr_atomic_store_i64_release(wPtr, w + Int64(toWrite))
        return toWrite
    }

    @discardableResult
    @inlinable
    public func write(from source: UnsafePointer<Int32>, wordCount: Int) -> Int {
        write(from: source, count: wordCount)
    }

    /// Читает до `count` элементов `Int32` в `destination`. Возвращает число реально прочитанных слов.
    @discardableResult
    @inlinable
    public func read(into destination: UnsafeMutablePointer<Int32>, count: Int) -> Int {
        rawView.read(into: destination, count: count)
    }
}

/// Lock-Free SPSC кольцевой буфер для захвата планарных стерео-сэмплов `Float` из `AudioProcessTapService`
/// без аллокаций и блокировок на потоке CoreAudio Tap IOProc.
public final class SPSCStereoFloatRingBuffer: @unchecked Sendable {
    public let frameCapacity: Int
    public let mask: Int
    @usableFromInline internal let leftRaw: UnsafeMutableRawPointer
    @usableFromInline internal let rightRaw: UnsafeMutableRawPointer
    @usableFromInline internal let leftBuffer: UnsafeMutablePointer<Float>
    @usableFromInline internal let rightBuffer: UnsafeMutablePointer<Float>
    @usableFromInline internal let indicesPtr: UnsafeMutablePointer<SPSCCacheAlignedIndices>
    private let byteLength: Int

    public convenience init(capacityFrames: Int) {
        self.init(minimumFrameCapacity: capacityFrames)
    }

    public init(minimumFrameCapacity: Int) {
        var pow2 = 4096
        while pow2 < max(4096, minimumFrameCapacity) {
            pow2 <<= 1
        }
        self.frameCapacity = pow2
        self.mask = pow2 - 1
        self.byteLength = pow2 * MemoryLayout<Float>.stride

        self.leftRaw = UnsafeMutableRawPointer.allocate(byteCount: byteLength, alignment: 64)
        self.rightRaw = UnsafeMutableRawPointer.allocate(byteCount: byteLength, alignment: 64)
        self.leftRaw.initializeMemory(as: UInt8.self, repeating: 0, count: byteLength)
        self.rightRaw.initializeMemory(as: UInt8.self, repeating: 0, count: byteLength)
        self.leftBuffer = self.leftRaw.bindMemory(to: Float.self, capacity: pow2)
        self.rightBuffer = self.rightRaw.bindMemory(to: Float.self, capacity: pow2)

        let idxRaw = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<SPSCCacheAlignedIndices>.stride,
            alignment: 128
        )
        self.indicesPtr = idxRaw.initializeMemory(as: SPSCCacheAlignedIndices.self, repeating: SPSCCacheAlignedIndices(), count: 1)

        _ = mlock(leftRaw, byteLength)
        _ = mlock(rightRaw, byteLength)
        _ = mlock(idxRaw, MemoryLayout<SPSCCacheAlignedIndices>.stride)
    }

    deinit {
        munlock(leftRaw, byteLength)
        munlock(rightRaw, byteLength)
        munlock(indicesPtr, MemoryLayout<SPSCCacheAlignedIndices>.stride)
        leftRaw.deallocate()
        rightRaw.deallocate()
        UnsafeMutableRawPointer(indicesPtr).deallocate()
    }

    @inlinable
    public var availableFramesToRead: Int {
        let w = amr_atomic_load_i64_acquire(indicesPtr.writeIndexAtomicPtr)
        let r = amr_atomic_load_i64_acquire(indicesPtr.readIndexAtomicPtr)
        return max(0, Int(w - r))
    }

    @inlinable
    public var availableFramesToWrite: Int {
        let w = amr_atomic_load_i64_acquire(indicesPtr.writeIndexAtomicPtr)
        let r = amr_atomic_load_i64_acquire(indicesPtr.readIndexAtomicPtr)
        return max(0, frameCapacity - Int(w - r))
    }

    public func reset() {
        amr_atomic_store_i64_release(indicesPtr.writeIndexAtomicPtr, 0)
        amr_atomic_store_i64_release(indicesPtr.readIndexAtomicPtr, 0)
    }

    /// Неаллоцирующая запись нулевых стерео-кадров (например, при Muting Guard или тактировании тест-сигнала) из IOProc.
    @discardableResult
    @inlinable
    public func writeZeros(frameCount: Int) -> Int {
        guard frameCount > 0 else { return 0 }
        let wPtr = indicesPtr.writeIndexAtomicPtr
        let rPtr = indicesPtr.readIndexAtomicPtr
        let w = amr_atomic_load_i64_relaxed(wPtr)
        let r = amr_atomic_load_i64_acquire(rPtr)

        let freeFrames = max(0, frameCapacity - Int(w - r))
        let toWrite = min(frameCount, freeFrames)
        guard toWrite > 0 else { return 0 }

        let startIdx = Int(w) & mask
        let firstPart = min(toWrite, frameCapacity - startIdx)
        memset(leftBuffer.advanced(by: startIdx), 0, firstPart * MemoryLayout<Float>.stride)
        memset(rightBuffer.advanced(by: startIdx), 0, firstPart * MemoryLayout<Float>.stride)
        if toWrite > firstPart {
            let secondPart = toWrite - firstPart
            memset(leftBuffer, 0, secondPart * MemoryLayout<Float>.stride)
            memset(rightBuffer, 0, secondPart * MemoryLayout<Float>.stride)
        }

        amr_atomic_store_i64_release(wPtr, w + Int64(toWrite))
        return toWrite
    }

    /// Неаллоцирующая запись планарных буферов `left` и `right` из IOProc.
    @discardableResult
    @inlinable
    public func writePlanar(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frameCount: Int) -> Int {
        guard frameCount > 0 else { return 0 }
        let wPtr = indicesPtr.writeIndexAtomicPtr
        let rPtr = indicesPtr.readIndexAtomicPtr
        let w = amr_atomic_load_i64_relaxed(wPtr)
        let r = amr_atomic_load_i64_acquire(rPtr)

        let freeFrames = max(0, frameCapacity - Int(w - r))
        let toWrite = min(frameCount, freeFrames)
        guard toWrite > 0 else { return 0 }

        let startIdx = Int(w) & mask
        let firstPart = min(toWrite, frameCapacity - startIdx)
        memcpy(leftBuffer.advanced(by: startIdx), left, firstPart * MemoryLayout<Float>.stride)
        memcpy(rightBuffer.advanced(by: startIdx), right, firstPart * MemoryLayout<Float>.stride)
        if toWrite > firstPart {
            let secondPart = toWrite - firstPart
            memcpy(leftBuffer, left.advanced(by: firstPart), secondPart * MemoryLayout<Float>.stride)
            memcpy(rightBuffer, right.advanced(by: firstPart), secondPart * MemoryLayout<Float>.stride)
        }

        amr_atomic_store_i64_release(wPtr, w + Int64(toWrite))
        return toWrite
    }

    @discardableResult
    @inlinable
    public func writePlanar(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frames: Int) -> Int {
        writePlanar(left: left, right: right, frameCount: frames)
    }

    /// Неаллоцирующая запись интерливированного буфера `Float` из IOProc.
    @discardableResult
    @inlinable
    public func writeInterleaved(interleaved: UnsafePointer<Float>, frameCount: Int, channels: Int) -> Int {
        guard frameCount > 0, channels >= 1 else { return 0 }
        let wPtr = indicesPtr.writeIndexAtomicPtr
        let rPtr = indicesPtr.readIndexAtomicPtr
        let w = amr_atomic_load_i64_relaxed(wPtr)
        let r = amr_atomic_load_i64_acquire(rPtr)

        let freeFrames = max(0, frameCapacity - Int(w - r))
        let toWrite = min(frameCount, freeFrames)
        guard toWrite > 0 else { return 0 }

        for i in 0..<toWrite {
            let dstIdx = (Int(w) + i) & mask
            let base = i * channels
            let l = interleaved[base]
            let rVal = (channels >= 2) ? interleaved[base + 1] : l
            leftBuffer[dstIdx] = l
            rightBuffer[dstIdx] = rVal
        }

        amr_atomic_store_i64_release(wPtr, w + Int64(toWrite))
        return toWrite
    }

    @discardableResult
    @inlinable
    public func writeInterleaved(_ interleaved: UnsafePointer<Float>, frames: Int, channels: Int) -> Int {
        writeInterleaved(interleaved: interleaved, frameCount: frames, channels: channels)
    }

    /// Неаллоцирующее чтение планарных буферов `Float` (`left`, `right`).
    @discardableResult
    @inlinable
    public func readPlanar(
        intoLeft dstLeft: UnsafeMutablePointer<Float>,
        intoRight dstRight: UnsafeMutablePointer<Float>,
        maxFrames: Int
    ) -> Int {
        guard maxFrames > 0 else { return 0 }
        let rPtr = indicesPtr.readIndexAtomicPtr
        let wPtr = indicesPtr.writeIndexAtomicPtr
        let r = amr_atomic_load_i64_relaxed(rPtr)
        let w = amr_atomic_load_i64_acquire(wPtr)

        let avail = max(0, Int(w - r))
        let toRead = min(maxFrames, avail)
        guard toRead > 0 else { return 0 }

        let startIdx = Int(r) & mask
        let firstPart = min(toRead, frameCapacity - startIdx)
        memcpy(dstLeft, leftBuffer.advanced(by: startIdx), firstPart * MemoryLayout<Float>.stride)
        memcpy(dstRight, rightBuffer.advanced(by: startIdx), firstPart * MemoryLayout<Float>.stride)
        if toRead > firstPart {
            let secondPart = toRead - firstPart
            memcpy(dstLeft.advanced(by: firstPart), leftBuffer, secondPart * MemoryLayout<Float>.stride)
            memcpy(dstRight.advanced(by: firstPart), rightBuffer, secondPart * MemoryLayout<Float>.stride)
        }

        amr_atomic_store_i64_release(rPtr, r + Int64(toRead))
        return toRead
    }

    /// Читает `frameCount` стерео-сэмплов с конвертацией в `Double` (`FP64`), аттенюацией Headroom и детекцией ISP.
    @discardableResult
    @inlinable
    public func readConvertedFP64(
        intoLeft dstLeft: UnsafeMutablePointer<Double>,
        intoRight dstRight: UnsafeMutablePointer<Double>,
        frameCount: Int,
        linearGain: Double,
        outMaxAbsSample: inout Double
    ) -> Int {
        guard frameCount > 0 else { return 0 }
        let rPtr = indicesPtr.readIndexAtomicPtr
        let wPtr = indicesPtr.writeIndexAtomicPtr
        let r = amr_atomic_load_i64_relaxed(rPtr)
        let w = amr_atomic_load_i64_acquire(wPtr)

        let avail = max(0, Int(w - r))
        let toRead = min(frameCount, avail)
        guard toRead > 0 else { return 0 }

        var maxPeak: Double = outMaxAbsSample
        for i in 0..<toRead {
            let srcIdx = (Int(r) + i) & mask
            let l = Double(leftBuffer[srcIdx]) * linearGain
            let rv = Double(rightBuffer[srcIdx]) * linearGain
            dstLeft[i] = l
            dstRight[i] = rv
            let absL = abs(l)
            let absR = abs(rv)
            if absL > maxPeak { maxPeak = absL }
            if absR > maxPeak { maxPeak = absR }
        }
        outMaxAbsSample = maxPeak

        amr_atomic_store_i64_release(rPtr, r + Int64(toRead))
        return toRead
    }
}
