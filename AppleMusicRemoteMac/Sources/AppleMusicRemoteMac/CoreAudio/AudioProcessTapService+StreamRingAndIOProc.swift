//
//  AudioProcessTapService+StreamRingAndIOProc.swift
//  AppleMusicRemoteMac
//
//  Real-Time CoreAudio IOProc Input Dispatcher, Lock-Free Stream PCM Ring Buffer,
//  Block Pre-DSP Quantizer & Silence / Idle Auto-Suspend Watchdog
//

import Foundation
import Accelerate
import CoreAudio
import os

extension AudioProcessTapService {

    // MARK: - CoreAudio Audio Processing

    internal func processCoreAudioInput(inInputData: UnsafePointer<AudioBufferList>) {
        let bufferList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
        guard !bufferList.isEmpty else { return }

        os_unfair_lock_lock(&mutingGuardSpinLock)
        let hasStreamSubscribers = hasActiveSubscribersFlag
        os_unfair_lock_unlock(&mutingGuardSpinLock)

        let currentDepth = self.bitDepth
        let currentBytesPerFrame = self.channels * (currentDepth / 8)
        var queuedStreamBytes = false
        var processedFrames = 0
        var blockPeakAbs: Float = 0.0

        if bufferList.count >= 2, let leftData = bufferList[0].mData, let rightData = bufferList[1].mData {
            // Non-interleaved stereo (Buffer 0: Left, Buffer 1: Right)
            let frameCount = min(Int(bufferList[0].mDataByteSize), Int(bufferList[1].mDataByteSize)) / MemoryLayout<Float>.size
            guard frameCount > 0 else { return }

            let leftPtr = leftData.assumingMemoryBound(to: Float.self)
            let rightPtr = rightData.assumingMemoryBound(to: Float.self)
            processedFrames = frameCount

            var peakL: Float = 0.0
            var peakR: Float = 0.0
            vDSP_maxmgv(leftPtr, 1, &peakL, vDSP_Length(frameCount))
            vDSP_maxmgv(rightPtr, 1, &peakR, vDSP_Length(frameCount))
            blockPeakAbs = max(peakL, peakR)

            SpectralIntegrityAnalyzer.shared.processNonInterleavedFloatFrames(
                left: leftPtr,
                right: rightPtr,
                frameCount: frameCount
            )
            AudioEngineController.shared.feedPlanarFloat32FromTap(
                left: leftPtr,
                right: rightPtr,
                frames: frameCount
            )
            let currentRate = self.sampleRate
            RoomAcousticService.shared.feedLocalPassthroughPlanarFloat32(
                left: leftPtr,
                right: rightPtr,
                frames: frameCount,
                sampleRate: currentRate
            )
            WLEDDDPController.shared.feedRealTimePlanarFloat32(
                left: leftPtr,
                right: rightPtr,
                frameCount: frameCount,
                sampleRate: currentRate
            )

            if hasStreamSubscribers {
                if isZeroFillingForMutingGuard {
                    enqueueZeroBytesToStreamRing(byteCount: frameCount * currentBytesPerFrame, bytesPerFrame: currentBytesPerFrame)
                } else if RoomAcousticService.shared.isTestSignalPlaying {
                    enqueuePinkNoiseToStreamRing(frameCount: frameCount, bitDepth: currentDepth, bytesPerFrame: currentBytesPerFrame)
                } else {
                    enqueuePlanarStreamWithBlockPreDSP(
                        leftSource: leftPtr,
                        rightSource: rightPtr,
                        frameCount: frameCount,
                        sampleRate: currentRate,
                        bitDepth: currentDepth,
                        bytesPerFrame: currentBytesPerFrame
                    )
                }
                queuedStreamBytes = true
            }
        } else if let firstBuffer = bufferList.first, let rawData = firstBuffer.mData {
            // Interleaved audio (Buffer 0: L, R, ... or mono/multichannel)
            let floatCount = Int(firstBuffer.mDataByteSize) / MemoryLayout<Float>.size
            let srcChannels = max(1, Int(firstBuffer.mNumberChannels))
            let frameCount = floatCount / srcChannels
            guard frameCount > 0 else { return }

            let floatPtr = rawData.assumingMemoryBound(to: Float.self)
            processedFrames = frameCount
            vDSP_maxmgv(floatPtr, 1, &blockPeakAbs, vDSP_Length(frameCount * srcChannels))

            SpectralIntegrityAnalyzer.shared.processInterleavedFloatFrames(
                interleaved: floatPtr,
                floatCount: frameCount * srcChannels,
                channels: srcChannels
            )
            AudioEngineController.shared.feedInterleavedFloat32FromTap(
                interleaved: floatPtr,
                frames: frameCount,
                channels: srcChannels
            )
            let currentRate = self.sampleRate
            RoomAcousticService.shared.feedLocalPassthroughInterleavedFloat32(
                interleaved: floatPtr,
                frames: frameCount,
                channels: srcChannels,
                sampleRate: currentRate
            )
            WLEDDDPController.shared.feedRealTimeInterleavedFloat32(
                interleaved: floatPtr,
                frameCount: frameCount,
                channels: srcChannels,
                sampleRate: currentRate
            )

            if hasStreamSubscribers {
                if isZeroFillingForMutingGuard {
                    enqueueZeroBytesToStreamRing(byteCount: frameCount * currentBytesPerFrame, bytesPerFrame: currentBytesPerFrame)
                } else if RoomAcousticService.shared.isTestSignalPlaying {
                    enqueuePinkNoiseToStreamRing(frameCount: frameCount, bitDepth: currentDepth, bytesPerFrame: currentBytesPerFrame)
                } else {
                    enqueueInterleavedStreamWithBlockPreDSP(
                        interleavedSource: floatPtr,
                        srcChannels: srcChannels,
                        frameCount: frameCount,
                        sampleRate: currentRate,
                        bitDepth: currentDepth,
                        bytesPerFrame: currentBytesPerFrame
                    )
                }
                queuedStreamBytes = true
            }
        } else {
            return
        }

        let nowMono = Double(DispatchTime.now().uptimeNanoseconds) * 1.0e-9
        var shouldSuspendMutedPassthrough = false
        var shouldNotifyNonZeroSignal = false
        let isAnalyzerPlaying = SpectralIntegrityAnalyzer.shared.isPlaying

        os_unfair_lock_lock(&silenceSpinLock)
        lastAudioReceivedTimeMono = nowMono
        autoHealCount = 0
        if blockPeakAbs > 1.0e-7 {
            lastNonZeroAudioTimeMono = nowMono
            mutedZeroSignalAccumulatedSec = 0.0
            shouldNotifyNonZeroSignal = true
        } else if processedFrames > 0
                    && isTapMuted
                    && !isZeroFillingForMutingGuard
                    && isAnalyzerPlaying {
            let blockDurSec = Double(processedFrames) / Double(max(44_100, sampleRate))
            mutedZeroSignalAccumulatedSec += blockDurSec
            if mutedZeroSignalAccumulatedSec >= 1.6 {
                mutedZeroSignalAccumulatedSec = 0.0
                shouldSuspendMutedPassthrough = true
            }
        } else {
            mutedZeroSignalAccumulatedSec = 0.0
        }
        os_unfair_lock_unlock(&silenceSpinLock)

        if shouldNotifyNonZeroSignal && RoomAcousticService.shared.isSuspendedDueToZeroedTap {
            queue.async {
                RoomAcousticService.shared.notifyNonZeroTapSignalDetected()
            }
        } else if shouldSuspendMutedPassthrough && RoomAcousticService.shared.isLocalPassthroughEQActive {
            queue.async {
                RoomAcousticService.shared.suspendLocalPassthroughDueToZeroedTap()
            }
        }

        if queuedStreamBytes {
            streamDrainSignalSource.add(data: 1)
        }
    }

    @inline(__always)
    internal func pushPCMBytesToStreamRing(
        _ srcPtr: UnsafePointer<UInt8>,
        byteCount: Int,
        bytesPerFrame: Int
    ) {
        guard byteCount > 0, bytesPerFrame > 0 else { return }
        let alignedCount = byteCount - (byteCount % bytesPerFrame)
        guard alignedCount > 0 else { return }

        os_unfair_lock_lock(&streamPCMRingSpinLock)
        if streamPCMRingBytesPerFrame != bytesPerFrame {
            streamPCMRingReadIdx = 0
            streamPCMRingWriteIdx = 0
            streamPCMRingCount = 0
            streamPCMRingBytesPerFrame = bytesPerFrame
        }

        let maxFrameAlignedCapacity = Self.streamPCMRingCapacity - (Self.streamPCMRingCapacity % bytesPerFrame)
        let startOffset: Int
        let countToWrite: Int
        if alignedCount > maxFrameAlignedCapacity {
            countToWrite = maxFrameAlignedCapacity
            startOffset = alignedCount - maxFrameAlignedCapacity
        } else {
            countToWrite = alignedCount
            startOffset = 0
        }

        var wIdx = streamPCMRingWriteIdx
        var rIdx = streamPCMRingReadIdx
        var count = streamPCMRingCount

        if count + countToWrite > maxFrameAlignedCapacity {
            let overflow = (count + countToWrite) - maxFrameAlignedCapacity
            let dropBytes = ((overflow + bytesPerFrame - 1) / bytesPerFrame) * bytesPerFrame
            let clampedDrop = min(count, dropBytes)
            rIdx = (rIdx + clampedDrop) & Self.streamPCMRingMask
            count -= clampedDrop
        }

        for i in 0..<countToWrite {
            streamPCMRingBuffer[wIdx] = srcPtr[startOffset + i]
            wIdx = (wIdx + 1) & Self.streamPCMRingMask
        }
        count += countToWrite

        streamPCMRingWriteIdx = wIdx
        streamPCMRingReadIdx = rIdx
        streamPCMRingCount = count
        os_unfair_lock_unlock(&streamPCMRingSpinLock)
    }

    internal func enqueueZeroBytesToStreamRing(byteCount: Int, bytesPerFrame: Int) {
        guard byteCount > 0, bytesPerFrame > 0 else { return }
        let alignedCount = byteCount - (byteCount % bytesPerFrame)
        guard alignedCount > 0 else { return }

        os_unfair_lock_lock(&streamPCMRingSpinLock)
        if streamPCMRingBytesPerFrame != bytesPerFrame {
            streamPCMRingReadIdx = 0
            streamPCMRingWriteIdx = 0
            streamPCMRingCount = 0
            streamPCMRingBytesPerFrame = bytesPerFrame
        }
        let maxFrameAlignedCapacity = Self.streamPCMRingCapacity - (Self.streamPCMRingCapacity % bytesPerFrame)
        let countToWrite = min(alignedCount, maxFrameAlignedCapacity)
        var wIdx = streamPCMRingWriteIdx
        var rIdx = streamPCMRingReadIdx
        var count = streamPCMRingCount

        if count + countToWrite > maxFrameAlignedCapacity {
            let overflow = (count + countToWrite) - maxFrameAlignedCapacity
            let dropBytes = ((overflow + bytesPerFrame - 1) / bytesPerFrame) * bytesPerFrame
            let clampedDrop = min(count, dropBytes)
            rIdx = (rIdx + clampedDrop) & Self.streamPCMRingMask
            count -= clampedDrop
        }
        for _ in 0..<countToWrite {
            streamPCMRingBuffer[wIdx] = 0
            wIdx = (wIdx + 1) & Self.streamPCMRingMask
        }
        count += countToWrite
        streamPCMRingWriteIdx = wIdx
        streamPCMRingReadIdx = rIdx
        streamPCMRingCount = count
        os_unfair_lock_unlock(&streamPCMRingSpinLock)
    }

    internal func enqueuePinkNoiseToStreamRing(
        frameCount: Int,
        bitDepth: Int,
        bytesPerFrame: Int
    ) {
        os_unfair_lock_lock(&streamScratchSpinLock)
        defer { os_unfair_lock_unlock(&streamScratchSpinLock) }

        var offset = 0
        while offset < frameCount {
            let tileCount = min(Self.streamScratchTileFrames, frameCount - offset)
            RoomAcousticService.shared.fillPinkNoiseStereoFloat32(
                left: streamScratchL,
                right: streamScratchR,
                frameCount: tileCount
            )
            var dstIdx = 0
            quantizeScratchTileToPCMBytes(
                left: streamScratchL,
                right: streamScratchR,
                tileCount: tileCount,
                bitDepth: bitDepth,
                dstPtr: streamScratchPCMBytes,
                dstIdx: &dstIdx
            )
            pushPCMBytesToStreamRing(streamScratchPCMBytes, byteCount: dstIdx, bytesPerFrame: bytesPerFrame)
            offset += tileCount
        }
    }

    internal func enqueuePlanarStreamWithBlockPreDSP(
        leftSource: UnsafePointer<Float>,
        rightSource: UnsafePointer<Float>,
        frameCount: Int,
        sampleRate: Int,
        bitDepth: Int,
        bytesPerFrame: Int
    ) {
        let currentRateDouble = Double(max(44_100, sampleRate))
        os_unfair_lock_lock(&streamScratchSpinLock)
        defer { os_unfair_lock_unlock(&streamScratchSpinLock) }

        var offset = 0
        while offset < frameCount {
            let tileCount = min(Self.streamScratchTileFrames, frameCount - offset)
            streamScratchL.update(from: leftSource.advanced(by: offset), count: tileCount)
            streamScratchR.update(from: rightSource.advanced(by: offset), count: tileCount)

            MasteringRestorationService.shared.processStreamPlanarFloat32IfEnabled(
                left: streamScratchL,
                right: streamScratchR,
                frameCount: tileCount,
                sampleRate: currentRateDouble
            )
            RoomAcousticService.shared.processStreamPlanarFloat32IfEnabled(
                left: streamScratchL,
                right: streamScratchR,
                frameCount: tileCount,
                sampleRate: sampleRate
            )
            LateNightDRCService.shared.processStreamPlanarFloat32IfEnabled(
                left: streamScratchL,
                right: streamScratchR,
                frameCount: tileCount,
                sampleRate: currentRateDouble
            )

            var dstIdx = 0
            quantizeScratchTileToPCMBytes(
                left: streamScratchL,
                right: streamScratchR,
                tileCount: tileCount,
                bitDepth: bitDepth,
                dstPtr: streamScratchPCMBytes,
                dstIdx: &dstIdx
            )
            pushPCMBytesToStreamRing(streamScratchPCMBytes, byteCount: dstIdx, bytesPerFrame: bytesPerFrame)
            offset += tileCount
        }
    }

    internal func enqueueInterleavedStreamWithBlockPreDSP(
        interleavedSource: UnsafePointer<Float>,
        srcChannels: Int,
        frameCount: Int,
        sampleRate: Int,
        bitDepth: Int,
        bytesPerFrame: Int
    ) {
        let currentRateDouble = Double(max(44_100, sampleRate))
        os_unfair_lock_lock(&streamScratchSpinLock)
        defer { os_unfair_lock_unlock(&streamScratchSpinLock) }

        var offset = 0
        while offset < frameCount {
            let tileCount = min(Self.streamScratchTileFrames, frameCount - offset)
            if srcChannels >= 2 {
                for i in 0..<tileCount {
                    let base = (offset + i) * srcChannels
                    streamScratchL[i] = interleavedSource[base]
                    streamScratchR[i] = interleavedSource[base + 1]
                }
            } else {
                for i in 0..<tileCount {
                    let v = interleavedSource[offset + i]
                    streamScratchL[i] = v
                    streamScratchR[i] = v
                }
            }

            MasteringRestorationService.shared.processStreamPlanarFloat32IfEnabled(
                left: streamScratchL,
                right: streamScratchR,
                frameCount: tileCount,
                sampleRate: currentRateDouble
            )
            RoomAcousticService.shared.processStreamPlanarFloat32IfEnabled(
                left: streamScratchL,
                right: streamScratchR,
                frameCount: tileCount,
                sampleRate: sampleRate
            )
            LateNightDRCService.shared.processStreamPlanarFloat32IfEnabled(
                left: streamScratchL,
                right: streamScratchR,
                frameCount: tileCount,
                sampleRate: currentRateDouble
            )

            var dstIdx = 0
            quantizeScratchTileToPCMBytes(
                left: streamScratchL,
                right: streamScratchR,
                tileCount: tileCount,
                bitDepth: bitDepth,
                dstPtr: streamScratchPCMBytes,
                dstIdx: &dstIdx
            )
            pushPCMBytesToStreamRing(streamScratchPCMBytes, byteCount: dstIdx, bytesPerFrame: bytesPerFrame)
            offset += tileCount
        }
    }

    @inline(__always)
    internal func quantizeScratchTileToPCMBytes(
        left: UnsafePointer<Float>,
        right: UnsafePointer<Float>,
        tileCount: Int,
        bitDepth: Int,
        dstPtr: UnsafeMutablePointer<UInt8>,
        dstIdx: inout Int
    ) {
        if bitDepth == 16 {
            for i in 0..<tileCount {
                let leftFloat = max(-1.0, min(1.0, left[i]))
                let rightFloat = max(-1.0, min(1.0, right[i]))
                let leftInt16 = Int16(round(leftFloat * 32767.0))
                dstPtr[dstIdx] = UInt8(leftInt16 & 0xFF)
                dstPtr[dstIdx + 1] = UInt8((leftInt16 >> 8) & 0xFF)
                dstIdx += 2

                let rightInt16 = Int16(round(rightFloat * 32767.0))
                dstPtr[dstIdx] = UInt8(rightInt16 & 0xFF)
                dstPtr[dstIdx + 1] = UInt8((rightInt16 >> 8) & 0xFF)
                dstIdx += 2
            }
        } else {
            for i in 0..<tileCount {
                let leftFloat = max(-1.0, min(1.0, left[i]))
                let rightFloat = max(-1.0, min(1.0, right[i]))
                let leftInt32 = Int32(round(leftFloat * 8388607.0))
                dstPtr[dstIdx] = UInt8(leftInt32 & 0xFF)
                dstPtr[dstIdx + 1] = UInt8((leftInt32 >> 8) & 0xFF)
                dstPtr[dstIdx + 2] = UInt8((leftInt32 >> 16) & 0xFF)
                dstIdx += 3

                let rightInt32 = Int32(round(rightFloat * 8388607.0))
                dstPtr[dstIdx] = UInt8(rightInt32 & 0xFF)
                dstPtr[dstIdx + 1] = UInt8((rightInt32 >> 8) & 0xFF)
                dstPtr[dstIdx + 2] = UInt8((rightInt32 >> 16) & 0xFF)
                dstIdx += 3
            }
        }
    }

    internal func drainStreamPCMRingBufferOnQueue() {
        while true {
            var ringBPF = 4
            os_unfair_lock_lock(&streamPCMRingSpinLock)
            let available = streamPCMRingCount
            if available <= 0 {
                os_unfair_lock_unlock(&streamPCMRingSpinLock)
                return
            }
            ringBPF = max(1, streamPCMRingBytesPerFrame)
            let rawRead = min(available, Self.streamDrainChunkBytes)
            let alignedRead = rawRead - (rawRead % ringBPF)
            if alignedRead <= 0 {
                streamPCMRingReadIdx = 0
                streamPCMRingWriteIdx = 0
                streamPCMRingCount = 0
                os_unfair_lock_unlock(&streamPCMRingSpinLock)
                return
            }
            streamDrainScratch.removeAll(keepingCapacity: true)
            var rIdx = streamPCMRingReadIdx
            for _ in 0..<alignedRead {
                streamDrainScratch.append(streamPCMRingBuffer[rIdx])
                rIdx = (rIdx + 1) & Self.streamPCMRingMask
            }
            streamPCMRingReadIdx = rIdx
            streamPCMRingCount = available - alignedRead
            os_unfair_lock_unlock(&streamPCMRingSpinLock)

            streamDrainScratch.withUnsafeBufferPointer { bufPtr in
                if let base = bufPtr.baseAddress {
                    appendStreamBytesOnQueue(base, count: bufPtr.count, chunkBytesPerFrame: ringBPF)
                }
            }
        }
    }

    internal func appendStreamBytesOnQueue(
        _ bytesPtr: UnsafePointer<UInt8>,
        count: Int,
        chunkBytesPerFrame: Int? = nil
    ) {
        guard !self.subscribers.isEmpty else {
            if !self.chunkAccumulator.isEmpty {
                self.chunkAccumulator.removeAll()
            }
            return
        }
        let bpf = max(1, self.bytesPerFrame)
        let incomingBPF = chunkBytesPerFrame ?? bpf
        if incomingBPF != bpf || count % bpf != 0 || self.chunkAccumulator.count % bpf != 0 {
            self.chunkAccumulator.removeAll(keepingCapacity: true)
            if incomingBPF != bpf || count % bpf != 0 {
                return
            }
        }
        self.chunkAccumulator.append(bytesPtr, count: count)

        // When accumulated ~50ms of audio, dispatch to subscribers
        let targetBytes = self.targetChunkFrameCount * bpf
        var extracted = false
        while self.chunkAccumulator.count >= targetBytes {
            let chunk = self.chunkAccumulator.prefix(targetBytes)
            self.chunkAccumulator.removeFirst(targetBytes)
            extracted = true
            for callback in self.subscribers.values {
                callback(Data(chunk))
            }
        }
        if extracted {
            if self.chunkAccumulator.isEmpty {
                self.chunkAccumulator = Data()
            } else {
                self.chunkAccumulator = Data(self.chunkAccumulator)
            }
        }
    }

    internal func dispatchAudioChunk(_ data: Data, bytesPerFrame chunkBytesPerFrame: Int? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            data.withUnsafeBytes { rawBuf in
                if let base = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                    self.appendStreamBytesOnQueue(base, count: rawBuf.count, chunkBytesPerFrame: chunkBytesPerFrame)
                }
            }
        }
    }

    // MARK: - Silence Fallback Generator & Passive Tap Idle Auto-Suspend

    internal func startSilenceGenerator() {
        stopSilenceGenerator()
        silenceTickCount = 0
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // Fire every 50ms
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let nowMono = Double(DispatchTime.now().uptimeNanoseconds) * 1.0e-9
            os_unfair_lock_lock(&self.silenceSpinLock)
            let timeSinceLastAudio = nowMono - self.lastAudioReceivedTimeMono
            let timeSinceNonZeroAudio = nowMono - self.lastNonZeroAudioTimeMono
            os_unfair_lock_unlock(&self.silenceSpinLock)

            self.silenceTickCount += 1
            let isAnalyzerPlaying = SpectralIntegrityAnalyzer.shared.isPlaying
            let hasActiveNonPassiveConsumer = !self.subscribers.isEmpty
                || self.isWLEDTapConsumerActive
                || DLNADiscoveryManager.shared.hasActiveRenderer
                || AudioEngineController.shared.isActivePipelineHook
                || RoomAcousticService.shared.isLocalPassthroughEQActive
                || RoomAcousticService.shared.isTestSignalPlaying
            let hasConsumers = hasActiveNonPassiveConsumer || self.isPassiveAnalysisActive

            // Idle auto-suspend (~45s) for purely passive analysis tap while Music.app is paused/stopped
            if self.silenceTickCount % 20 == 0 {
                if !hasActiveNonPassiveConsumer && self.isPassiveAnalysisActive && !isAnalyzerPlaying && timeSinceNonZeroAudio >= 2.0 {
                    if let pausedSince = self.passivePausedSinceMono {
                        if (nowMono - pausedSince) >= Self.passiveIdleSuspendTimeoutSec {
                            NSLog("[AudioProcessTapService] 💤 Passive analysis tap idle for %.0fs while paused/stopped — suspending CATapDescription & Aggregate Device.", nowMono - pausedSince)
                            self.isPassiveTapIdleSuspended = true
                            self.passivePausedSinceMono = nil
                            self.stopCaptureInternal()
                            return
                        }
                    } else {
                        self.passivePausedSinceMono = nowMono
                    }
                } else {
                    self.passivePausedSinceMono = nil
                }
            }

            // Every 20 ticks (~1 second), if real tap is not yet active and we have subscribers, passive analysis, or DSP Engine,
            // retry attaching the real Process Tap to Music.app
            if self.silenceTickCount % 20 == 0 && !self.isRealTapActive && hasConsumers && !(self.isPassiveTapIdleSuspended && !hasActiveNonPassiveConsumer && !isAnalyzerPlaying) {
                self.startCaptureInternal()
            } else if self.silenceTickCount % 80 == 0 && self.isRealTapActive && hasConsumers && isAnalyzerPlaying && timeSinceLastAudio > 4.5 {
                os_unfair_lock_lock(&self.silenceSpinLock)
                let attempts = self.autoHealCount
                if attempts < 1 {
                    self.autoHealCount = attempts + 1
                }
                os_unfair_lock_unlock(&self.silenceSpinLock)
                if attempts < 1 {
                    NSLog("[AudioProcessTapService] 🔄 No CoreAudio frames received for >4.5s while playing; auto-healing Process Tap (attempt 1/1)...")
                    self.stopCaptureInternal()
                    self.startCaptureInternal()
                }
            }

            // If no real CoreAudio frames received for > 200ms while actively playing (e.g. track switch gap),
            // inject 50ms of silence frames (or calibrated Pink Noise if Room Measurement is active!) so connected streamers don't buffer-underrun.
            // Do NOT flood paused network streamers (BluOS/DLNA) with 288 KB/s of zero-PCM frames while paused!
            let isPaused = PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.isUserPaused })
                || DLNADiscoveryManager.shared.isRendererPausedOrStopped
            if timeSinceLastAudio > 0.20 && !self.subscribers.isEmpty && (!isPaused || RoomAcousticService.shared.isTestSignalPlaying) {
                let silenceFrameCount = self.sampleRate / 20 // 50ms
                let outData: Data
                if RoomAcousticService.shared.isTestSignalPlaying {
                    outData = RoomAcousticService.shared.makePinkNoiseWAVChunk(
                        sampleRate: self.sampleRate,
                        bitDepth: self.bitDepth,
                        frameCount: silenceFrameCount
                    )
                } else {
                    let silenceBytes = silenceFrameCount * self.bytesPerFrame
                    outData = Data(repeating: 0, count: silenceBytes)
                }
                for callback in self.subscribers.values {
                    callback(outData)
                }
            }
        }
        timer.resume()
        self.silenceTimer = timer
    }

    internal func stopSilenceGenerator() {
        silenceTimer?.cancel()
        silenceTimer = nil
    }
}
