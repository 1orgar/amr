//
//  AudioProcessTapService+StreamRingAndIOProc.swift
//  AppleMusicRemoteMac
//
//  Real-Time CoreAudio IOProc Input Handler, Lock-Free Float32 Stream Ring Offload,
//  TPDF Dithered Quantization, Subscriber Chunk Dispatcher & Silence Fallback Generator.
//

import Foundation
import Accelerate
import CoreAudio
import os

extension AudioProcessTapService {

    // MARK: - CoreAudio Audio Processing (Zero Heap Allocations, Zero Heavy DSP in RT IOProc)

    internal func processCoreAudioInput(inInputData: UnsafePointer<AudioBufferList>) {
        let bufferList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
        guard !bufferList.isEmpty else { return }

        os_unfair_lock_lock(&mutingGuardSpinLock)
        let hasStreamSubscribers = hasActiveSubscribersFlag
        let isZeroFillGuard = isMutingGuardZeroFill
        os_unfair_lock_unlock(&mutingGuardSpinLock)

        var queuedStreamFrames = false
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
                if isZeroFillGuard || RoomAcousticService.shared.isTestSignalPlaying {
                    queuedStreamFrames = streamFloatRingBuffer.writeZeros(frameCount: frameCount) > 0
                } else {
                    queuedStreamFrames = streamFloatRingBuffer.writePlanar(
                        left: leftPtr,
                        right: rightPtr,
                        frameCount: frameCount
                    ) > 0
                }
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
                if isZeroFillGuard || RoomAcousticService.shared.isTestSignalPlaying {
                    queuedStreamFrames = streamFloatRingBuffer.writeZeros(frameCount: frameCount) > 0
                } else {
                    queuedStreamFrames = streamFloatRingBuffer.writeInterleaved(
                        interleaved: floatPtr,
                        frameCount: frameCount,
                        channels: srcChannels
                    ) > 0
                }
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
                    && !isZeroFillGuard
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

        var controlFlags: UInt = 0
        if shouldNotifyNonZeroSignal && RoomAcousticService.shared.isSuspendedDueToZeroedTap {
            controlFlags |= Self.tapControlSignalNonZeroDetected
        } else if shouldSuspendMutedPassthrough && RoomAcousticService.shared.isLocalPassthroughEQActive {
            controlFlags |= Self.tapControlSignalSuspendZeroedPassthrough
        }
        if controlFlags != 0 {
            tapControlSignalSource.or(data: controlFlags)
        }

        if queuedStreamFrames {
            streamDrainSignalSource.add(data: 1)
        }
    }

    // MARK: - TPDF Dither PRNG & PCM Quantization

    @inline(__always)
    internal static func nextUniformFloat(_ state: inout UInt64) -> Float {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let mixed = state &* 0x2545_F491_4F6C_DD1D
        return Float(mixed >> 40) * (1.0 / 16_777_216.0)
    }

    @inline(__always)
    internal static func nextTPDFSample(_ state: inout UInt64) -> Float {
        let u1 = nextUniformFloat(&state)
        let u2 = nextUniformFloat(&state)
        return u1 - u2
    }

    @inline(__always)
    internal func quantizeScratchTileToPCMBytes(
        left: UnsafePointer<Float>,
        right: UnsafePointer<Float>,
        tileCount: Int,
        bitDepth: Int,
        dstPtr: UnsafeMutablePointer<UInt8>,
        dstIdx: inout Int,
        enableTPDFDither: Bool = true
    ) {
        var seedL = ditherSeedL
        var seedR = ditherSeedR
        defer {
            ditherSeedL = seedL
            ditherSeedR = seedR
        }

        if bitDepth == 16 {
            if enableTPDFDither {
                for i in 0..<tileCount {
                    let leftFloat = max(-1.0, min(1.0, left[i]))
                    let rightFloat = max(-1.0, min(1.0, right[i]))
                    let dL = Self.nextTPDFSample(&seedL)
                    let dR = Self.nextTPDFSample(&seedR)

                    let leftInt16 = Int16(clamping: Int32((leftFloat * 32767.0 + dL).rounded()))
                    let leftBits = UInt16(bitPattern: leftInt16)
                    dstPtr[dstIdx] = UInt8(truncatingIfNeeded: leftBits)
                    dstPtr[dstIdx + 1] = UInt8(truncatingIfNeeded: leftBits >> 8)
                    dstIdx += 2

                    let rightInt16 = Int16(clamping: Int32((rightFloat * 32767.0 + dR).rounded()))
                    let rightBits = UInt16(bitPattern: rightInt16)
                    dstPtr[dstIdx] = UInt8(truncatingIfNeeded: rightBits)
                    dstPtr[dstIdx + 1] = UInt8(truncatingIfNeeded: rightBits >> 8)
                    dstIdx += 2
                }
            } else {
                for i in 0..<tileCount {
                    let leftFloat = max(-1.0, min(1.0, left[i]))
                    let rightFloat = max(-1.0, min(1.0, right[i]))
                    let leftInt16 = Int16(clamping: Int32((leftFloat * 32767.0).rounded()))
                    let leftBits = UInt16(bitPattern: leftInt16)
                    dstPtr[dstIdx] = UInt8(truncatingIfNeeded: leftBits)
                    dstPtr[dstIdx + 1] = UInt8(truncatingIfNeeded: leftBits >> 8)
                    dstIdx += 2

                    let rightInt16 = Int16(clamping: Int32((rightFloat * 32767.0).rounded()))
                    let rightBits = UInt16(bitPattern: rightInt16)
                    dstPtr[dstIdx] = UInt8(truncatingIfNeeded: rightBits)
                    dstPtr[dstIdx + 1] = UInt8(truncatingIfNeeded: rightBits >> 8)
                    dstIdx += 2
                }
            }
        } else {
            if enableTPDFDither {
                for i in 0..<tileCount {
                    let leftFloat = max(-1.0, min(1.0, left[i]))
                    let rightFloat = max(-1.0, min(1.0, right[i]))
                    let dL = Self.nextTPDFSample(&seedL)
                    let dR = Self.nextTPDFSample(&seedR)

                    let leftInt32 = max(-8_388_608, min(8_388_607, Int32((leftFloat * 8_388_607.0 + dL).rounded())))
                    let leftBits = UInt32(bitPattern: leftInt32)
                    dstPtr[dstIdx] = UInt8(truncatingIfNeeded: leftBits)
                    dstPtr[dstIdx + 1] = UInt8(truncatingIfNeeded: leftBits >> 8)
                    dstPtr[dstIdx + 2] = UInt8(truncatingIfNeeded: leftBits >> 16)
                    dstIdx += 3

                    let rightInt32 = max(-8_388_608, min(8_388_607, Int32((rightFloat * 8_388_607.0 + dR).rounded())))
                    let rightBits = UInt32(bitPattern: rightInt32)
                    dstPtr[dstIdx] = UInt8(truncatingIfNeeded: rightBits)
                    dstPtr[dstIdx + 1] = UInt8(truncatingIfNeeded: rightBits >> 8)
                    dstPtr[dstIdx + 2] = UInt8(truncatingIfNeeded: rightBits >> 16)
                    dstIdx += 3
                }
            } else {
                for i in 0..<tileCount {
                    let leftFloat = max(-1.0, min(1.0, left[i]))
                    let rightFloat = max(-1.0, min(1.0, right[i]))
                    let leftInt32 = max(-8_388_608, min(8_388_607, Int32((leftFloat * 8_388_607.0).rounded())))
                    let leftBits = UInt32(bitPattern: leftInt32)
                    dstPtr[dstIdx] = UInt8(truncatingIfNeeded: leftBits)
                    dstPtr[dstIdx + 1] = UInt8(truncatingIfNeeded: leftBits >> 8)
                    dstPtr[dstIdx + 2] = UInt8(truncatingIfNeeded: leftBits >> 16)
                    dstIdx += 3

                    let rightInt32 = max(-8_388_608, min(8_388_607, Int32((rightFloat * 8_388_607.0).rounded())))
                    let rightBits = UInt32(bitPattern: rightInt32)
                    dstPtr[dstIdx] = UInt8(truncatingIfNeeded: rightBits)
                    dstPtr[dstIdx + 1] = UInt8(truncatingIfNeeded: rightBits >> 8)
                    dstPtr[dstIdx + 2] = UInt8(truncatingIfNeeded: rightBits >> 16)
                    dstIdx += 3
                }
            }
        }
    }

    // MARK: - Non-RT Stream Pre-DSP & Drain Loop (Runs on `queue`)

    internal func drainStreamPCMRingBufferOnQueue() {
        let currentRate = self.sampleRate
        let currentRateDouble = Double(max(44_100, currentRate))
        let currentDepth = self.bitDepth
        let currentBPF = max(1, self.channels * (currentDepth / 8))

        while true {
            os_unfair_lock_lock(&streamScratchSpinLock)
            let tileCount = streamFloatRingBuffer.readPlanar(
                intoLeft: streamScratchL,
                intoRight: streamScratchR,
                maxFrames: Self.streamScratchTileFrames
            )
            if tileCount <= 0 {
                os_unfair_lock_unlock(&streamScratchSpinLock)
                return
            }

            var dstIdx = 0
            if isZeroFillingForMutingGuard {
                let zeroBytes = tileCount * currentBPF
                memset(streamScratchPCMBytes, 0, zeroBytes)
                dstIdx = zeroBytes
            } else if RoomAcousticService.shared.isTestSignalPlaying {
                RoomAcousticService.shared.fillPinkNoiseStereoFloat32(
                    left: streamScratchL,
                    right: streamScratchR,
                    frameCount: tileCount
                )
                quantizeScratchTileToPCMBytes(
                    left: streamScratchL,
                    right: streamScratchR,
                    tileCount: tileCount,
                    bitDepth: currentDepth,
                    dstPtr: streamScratchPCMBytes,
                    dstIdx: &dstIdx,
                    enableTPDFDither: true
                )
            } else {
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
                    sampleRate: currentRate
                )
                LateNightDRCService.shared.processStreamPlanarFloat32IfEnabled(
                    left: streamScratchL,
                    right: streamScratchR,
                    frameCount: tileCount,
                    sampleRate: currentRateDouble
                )
                quantizeScratchTileToPCMBytes(
                    left: streamScratchL,
                    right: streamScratchR,
                    tileCount: tileCount,
                    bitDepth: currentDepth,
                    dstPtr: streamScratchPCMBytes,
                    dstIdx: &dstIdx,
                    enableTPDFDither: true
                )
            }

            appendStreamBytesOnQueue(streamScratchPCMBytes, count: dstIdx, chunkBytesPerFrame: currentBPF)
            os_unfair_lock_unlock(&streamScratchSpinLock)
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
