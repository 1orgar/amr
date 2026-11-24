//
//  RoomAcousticService+PinkNoise.swift
//  AppleMusicRemoteMac
//
//  Calibrated Reference Pink Noise Generator (-14 dBFS) & Local DefaultOutput Unit
//

import AudioToolbox
import CoreAudio
import Darwin
import Foundation
import os

extension RoomAcousticService {

    // MARK: - Reference Pink Noise Generator

    public func startTestSignal(durationSeconds: TimeInterval = 18.0, initiatingClientID: UUID? = nil) {
        lock.withLock {
            activeTestSignalClientID = initiatingClientID
        }

        os_unfair_lock_lock(&pinkSpinLock)
        _isTestSignalPlaying = true
        pinkStateL = PinkNoiseGeneratorState(rngState: 0x9E37_79B9_7F4A_7C15)
        pinkStateR = PinkNoiseGeneratorState(rngState: 0xBF58_476D_1CE4_E5B9)
        os_unfair_lock_unlock(&pinkSpinLock)

        scheduleAutoStopTimer(after: max(5.0, min(60.0, durationSeconds)))

        guard !isIsolatedInstance else { return }

        if !PlaybackRouter.shared.isTestingEnvironment && !DLNADiscoveryManager.shared.hasActiveRenderer {
            DispatchQueue.global(qos: .userInitiated).async {
                if let app = MusicAppProvider.shared.getMusicApp(), app.playerState == .playing {
                    _ = PlaybackTransportController.shared.pause()
                }
            }
        }

        if DLNADiscoveryManager.shared.hasActiveRenderer {
            // Ensure /stream/live.wav is running and streaming to BluOS / DLNA renderer
            AudioProcessTapService.shared.startCapture()
            let (streamURL, imageURL, _, metadata) = DLNADiscoveryManager.shared.resolveStreamAndImageURLs()
            DLNADiscoveryManager.shared.setAVTransportURI(
                uri: streamURL,
                metadata: metadata,
                imageURL: imageURL,
                title: "AMR — Тестовый розовый шум (АЧХ)"
            ) { success, _ in
                if success, DLNADiscoveryManager.shared.getActiveRenderer()?.isBluOS != true {
                    DLNADiscoveryManager.shared.play()
                }
            }
        } else if AudioEngineController.shared.isActivePipelineHook {
            // AudioEngineController's realtimePipelineLoop automatically pulls pink noise when isTestSignalPlaying == true
        } else {
            startLocalNoiseOutputUnit()
        }

        NSLog("[RoomAcousticService] 🔊 Started calibrated reference Pink Noise (-14 dBFS)")
    }

    public func stopTestSignal() {
        let wasPlaying: Bool = {
            os_unfair_lock_lock(&pinkSpinLock)
            let prev = _isTestSignalPlaying
            _isTestSignalPlaying = false
            os_unfair_lock_unlock(&pinkSpinLock)
            return prev
        }()

        let timerToCancel: DispatchSourceTimer? = lock.withLock {
            activeTestSignalClientID = nil
            testSignalTimerGeneration &+= 1
            let existing = testSignalAutoStopTimer
            testSignalAutoStopTimer = nil
            return existing
        }
        timerToCancel?.cancel()
        stopLocalNoiseOutputUnit()

        if wasPlaying {
            NSLog("[RoomAcousticService] 🔇 Stopped calibrated reference Pink Noise")
        }
    }

    public func stopTestSignalIfInitiatedBy(clientID: UUID) {
        let matchesInitiator: Bool = lock.withLock {
            activeTestSignalClientID == clientID
        }
        guard matchesInitiator else { return }
        stopTestSignal()
        if !isIsolatedInstance {
            WebSocketServer.shared.broadcastEvent(
                name: "room_acoustic_settings",
                data: RoomAcousticService.shared.statusDictionary()
            )
        }
    }

    internal func scheduleAutoStopTimer(after seconds: TimeInterval) {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        let (oldTimer, generation): (DispatchSourceTimer?, UInt64) = lock.withLock {
            let prev = testSignalAutoStopTimer
            testSignalTimerGeneration &+= 1
            testSignalAutoStopTimer = timer
            return (prev, testSignalTimerGeneration)
        }
        oldTimer?.cancel()

        timer.schedule(deadline: .now() + seconds)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let isCurrentGen = self.lock.withLock { self.testSignalTimerGeneration == generation }
            guard isCurrentGen else { return }
            self.stopTestSignal()
            if !self.isIsolatedInstance {
                WebSocketServer.shared.broadcastEvent(
                    name: "room_acoustic_settings",
                    data: RoomAcousticService.shared.statusDictionary()
                )
            }
        }
        timer.resume()
    }

    /// Fills planar Float32 stereo buffers with calibrated correlated/semi-correlated Pink Noise (RT-safe).
    public func fillPinkNoiseStereoFloat32(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) {
        guard frameCount > 0 else { return }
        os_unfair_lock_lock(&pinkSpinLock)
        for i in 0..<frameCount {
            // 85% mono-correlated + 15% stereo decorrelated avoids sharp acoustic comb-cancellation off-axis
            let mono = pinkStateL.nextPinkSample(amplitude: 0.20)
            let side = pinkStateR.nextPinkSample(amplitude: 0.04)
            left[i] = max(-0.9, min(0.9, mono + side))
            right[i] = max(-0.9, min(0.9, mono - side))
        }
        os_unfair_lock_unlock(&pinkSpinLock)
    }

    public func makePinkNoiseWAVChunk(sampleRate: Int, bitDepth: Int, frameCount: Int) -> Data {
        guard frameCount > 0 else { return Data() }
        let bytesPerFrame = 2 * ((bitDepth == 16) ? 2 : 3)
        var out = Data(count: frameCount * bytesPerFrame)
        out.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            guard let ptr = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            os_unfair_lock_lock(&pinkSpinLock)
            var idx = 0
            for _ in 0..<frameCount {
                let mono = pinkStateL.nextPinkSample(amplitude: 0.20)
                let side = pinkStateR.nextPinkSample(amplitude: 0.04)
                let l = max(-0.9, min(0.9, mono + side))
                let r = max(-0.9, min(0.9, mono - side))
                if bitDepth == 16 {
                    let li = Int16(round(l * 32767.0))
                    let ri = Int16(round(r * 32767.0))
                    ptr[idx] = UInt8(li & 0xFF)
                    ptr[idx + 1] = UInt8((li >> 8) & 0xFF)
                    ptr[idx + 2] = UInt8(ri & 0xFF)
                    ptr[idx + 3] = UInt8((ri >> 8) & 0xFF)
                    idx += 4
                } else {
                    let li = Int32(round(l * 8388607.0))
                    let ri = Int32(round(r * 8388607.0))
                    ptr[idx] = UInt8(li & 0xFF)
                    ptr[idx + 1] = UInt8((li >> 8) & 0xFF)
                    ptr[idx + 2] = UInt8((li >> 16) & 0xFF)
                    ptr[idx + 3] = UInt8(ri & 0xFF)
                    ptr[idx + 4] = UInt8((ri >> 8) & 0xFF)
                    ptr[idx + 5] = UInt8((ri >> 16) & 0xFF)
                    idx += 6
                }
            }
            os_unfair_lock_unlock(&pinkSpinLock)
        }
        return out
    }

    internal func startLocalNoiseOutputUnit() {
        let targetRate = max(44_100.0, resolveActiveLocalOutputFormat().sampleRate)

        localEQUnitLifecycleLock.lock()
        defer { localEQUnitLifecycleLock.unlock() }

        stopLocalNoiseOutputUnitLocked()
        guard isTestSignalPlaying else { return }

        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_DefaultOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let comp = AudioComponentFindNext(nil, &desc) else { return }
        var unit: AudioComponentInstance?
        guard AudioComponentInstanceNew(comp, &unit) == noErr, let au = unit else { return }

        var streamDesc = AudioStreamBasicDescription(
            mSampleRate: targetRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        let fmtStatus = AudioUnitSetProperty(
            au,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,
            &streamDesc,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard fmtStatus == noErr else {
            AudioComponentInstanceDispose(au)
            return
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var cb = AURenderCallbackStruct(
            inputProc: { inRefCon, _, _, _, inNumberFrames, ioData -> OSStatus in
                guard let ioData else { return noErr }
                let abl = UnsafeMutableAudioBufferListPointer(ioData)
                let frames = Int(inNumberFrames)
                let neededBytes = frames * MemoryLayout<Float>.size
                guard frames > 0,
                      abl.count >= 2,
                      Int(abl[0].mDataByteSize) >= neededBytes,
                      Int(abl[1].mDataByteSize) >= neededBytes,
                      let lRaw = abl[0].mData,
                      let rRaw = abl[1].mData else {
                    for idx in 0..<abl.count {
                        if let ptr = abl[idx].mData, abl[idx].mDataByteSize > 0 {
                            memset(ptr, 0, Int(abl[idx].mDataByteSize))
                        }
                    }
                    return noErr
                }
                let service = Unmanaged<RoomAcousticService>.fromOpaque(inRefCon).takeUnretainedValue()
                let lPtr = lRaw.assumingMemoryBound(to: Float.self)
                let rPtr = rRaw.assumingMemoryBound(to: Float.self)
                if service.isTestSignalPlaying {
                    service.fillPinkNoiseStereoFloat32(left: lPtr, right: rPtr, frameCount: frames)
                    if Int(abl[0].mDataByteSize) > neededBytes {
                        memset(lRaw.advanced(by: neededBytes), 0, Int(abl[0].mDataByteSize) - neededBytes)
                    }
                    if Int(abl[1].mDataByteSize) > neededBytes {
                        memset(rRaw.advanced(by: neededBytes), 0, Int(abl[1].mDataByteSize) - neededBytes)
                    }
                } else {
                    memset(lRaw, 0, Int(abl[0].mDataByteSize))
                    memset(rRaw, 0, Int(abl[1].mDataByteSize))
                }
                if abl.count > 2 {
                    for idx in 2..<abl.count {
                        if let ptr = abl[idx].mData, abl[idx].mDataByteSize > 0 {
                            memset(ptr, 0, Int(abl[idx].mDataByteSize))
                        }
                    }
                }
                return noErr
            },
            inputProcRefCon: selfPtr
        )
        let cbStatus = AudioUnitSetProperty(
            au,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input,
            0,
            &cb,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        guard cbStatus == noErr else {
            AudioComponentInstanceDispose(au)
            return
        }

        if isTestSignalPlaying, AudioUnitInitialize(au) == noErr, AudioOutputUnitStart(au) == noErr {
            lock.lock()
            localNoiseAudioUnit = au
            lock.unlock()
        } else {
            AudioComponentInstanceDispose(au)
        }
    }

    internal func stopLocalNoiseOutputUnit() {
        localEQUnitLifecycleLock.lock()
        defer { localEQUnitLifecycleLock.unlock() }
        stopLocalNoiseOutputUnitLocked()
    }

    internal func stopLocalNoiseOutputUnitLocked() {
        lock.lock()
        let au = localNoiseAudioUnit
        localNoiseAudioUnit = nil
        lock.unlock()
        if let au {
            AudioOutputUnitStop(au)
            AudioUnitUninitialize(au)
            AudioComponentInstanceDispose(au)
        }
    }
}
