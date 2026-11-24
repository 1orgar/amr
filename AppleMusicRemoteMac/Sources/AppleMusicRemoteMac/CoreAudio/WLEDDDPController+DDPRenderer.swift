//
//  WLEDDDPController+DDPRenderer.swift
//  AppleMusicRemoteMac
//
//  40 FPS Flicker-Free Multi-Zone DDP Packet Renderer, Temporal Hysteresis Quantizer,
//  Glitch-Proof Playback State Detector, Off-State Heartbeat & Non-Blocking UDP Socket Lifecycle.
//

import Foundation
import Darwin
import os

extension WLEDDDPController {

    // MARK: - Engine Lifecycle & Off-State Heartbeat

    internal func reconfigureEngine(sendOffSignalIfInactive: Bool = false) {
        ddpQueue.async { [weak self] in
            guard let self = self else { return }
            let (enabled, ip, currentMode) = self.lock.withLock {
                (self._isEnabled, self._ipAddress, self._mode)
            }
            let hasValidIP = Self.validatedUnicastPrivateOrLoopbackIPv4(ip) != nil
            let active = enabled && hasValidIP && currentMode != "off"

            // Enable zero-allocation CoreAudio Float32 tap hook for all dynamic modes
            let needsAudioTap = active && currentMode != "static"
            os_unfair_lock_lock(&self.rtSpinLock)
            self.rtAudioHookActive = needsAudioTap
            os_unfair_lock_unlock(&self.rtSpinLock)

            if needsAudioTap && !self.isTapSubscribed {
                self.isTapSubscribed = true
                self.resetAudioFilterState()
                AudioProcessTapService.shared.setWLEDRealTimeTapConsumerActive(true)
            } else if !needsAudioTap && self.isTapSubscribed {
                self.isTapSubscribed = false
                AudioProcessTapService.shared.setWLEDRealTimeTapConsumerActive(false)
                self.resetAudioFilterState()
            }

            if !hasValidIP || (!active && !sendOffSignalIfInactive) {
                self.stopTimerAndSocket()
                return
            }

            self.ensureSocket(for: ip)

            if active {
                if self.timer == nil || self.timerIntervalMs != 25 {
                    self.timer?.cancel()
                    self.timer = nil
                    let t = DispatchSource.makeTimerSource(queue: self.ddpQueue)
                    // 40 FPS (25 ms) matches ESP32 WLED Wi-Fi throughput without UDP burst drops
                    t.schedule(deadline: .now(), repeating: .milliseconds(25), leeway: .milliseconds(2))
                    t.setEventHandler { [weak self] in
                        self?.tickFrame()
                    }
                    t.resume()
                    self.timer = t
                    self.timerIntervalMs = 25
                    self.sendWledHttpPowerState(ip: ip, on: true)
                    self.bootstrapCurrentTrackPaletteAsync()
                    NSLog("[WLEDDDPController] 💡 Started 16-Zone 40 FPS DDP Ambilight stream -> %@:4048 (mode=%@)", ip, currentMode)
                }
            } else if sendOffSignalIfInactive {
                self.offHeartbeatTickCount = 0
                self.dispatchBlackoutPacketSync(ip: ip)
                self.sendWledHttpPowerState(ip: ip, on: false)

                if self.timer == nil || self.timerIntervalMs != 1500 {
                    self.timer?.cancel()
                    self.timer = nil
                    let t = DispatchSource.makeTimerSource(queue: self.ddpQueue)
                    t.schedule(deadline: .now() + .milliseconds(1500), repeating: .milliseconds(1500), leeway: .milliseconds(100))
                    t.setEventHandler { [weak self] in
                        self?.tickOffStateHeartbeat()
                    }
                    t.resume()
                    self.timer = t
                    self.timerIntervalMs = 1500
                    NSLog("[WLEDDDPController] 🌙 WLED Off-State Heartbeat active for %@ (keeping strip off)", ip)
                }
            }
        }
    }

    internal func tickOffStateHeartbeat() {
        let (enabled, ip, currentMode) = lock.withLock {
            (self._isEnabled, self._ipAddress, self._mode)
        }
        guard Self.validatedUnicastPrivateOrLoopbackIPv4(ip) != nil,
              !(enabled && currentMode != "off") else {
            stopTimerAndSocket()
            return
        }
        dispatchBlackoutPacketSync(ip: ip)
        offHeartbeatTickCount += 1
        if offHeartbeatTickCount >= 2 {
            sendWledHttpPowerState(ip: ip, on: false)
            stopTimerAndSocket()
        }
    }

    internal func stopEngine() {
        os_unfair_lock_lock(&rtSpinLock)
        rtAudioHookActive = false
        os_unfair_lock_unlock(&rtSpinLock)

        ddpQueue.sync {
            if isTapSubscribed {
                isTapSubscribed = false
                AudioProcessTapService.shared.setWLEDRealTimeTapConsumerActive(false)
            }
            stopTimerAndSocket()
        }
    }

    internal func stopTimerAndSocket() {
        timer?.cancel()
        timer = nil
        timerIntervalMs = 0
        if udpSocket >= 0 {
            Darwin.close(udpSocket)
            udpSocket = -1
        }
        cachedSockAddr = nil
        cachedIPString = ""
    }

    internal func ensureSocket(for ip: String) {
        guard let valid = Self.validatedUnicastPrivateOrLoopbackIPv4(ip) else {
            cachedSockAddr = nil
            cachedIPString = ""
            if udpSocket >= 0 {
                Darwin.close(udpSocket)
                udpSocket = -1
            }
            return
        }
        if udpSocket < 0 {
            let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            if fd >= 0 {
                var nonBlocking: Int32 = 1
                _ = Darwin.ioctl(fd, 0x8004667e /* FIONBIO */, &nonBlocking)
                udpSocket = fd
            }
        }
        if valid.ipString != cachedIPString || cachedSockAddr == nil {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = UInt16(4048).bigEndian
            addr.sin_addr = valid.addr
            cachedSockAddr = addr
            cachedIPString = valid.ipString
        }
    }

    // MARK: - Glitch-Proof Playback Detection

    /// Resolves whether Apple Music is actively playing WITHOUT dropping to `false` when
    /// `lastPlayerStatusCache` is temporarily invalidated (`nil`) or when zero browser tabs are connected.
    private func resolveStablePlaybackState(nowMono: Double, lastNonSilentMono: Double) -> Bool {
        let userExplicitlyPaused = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isUserPaused
        }
        let cachedPlaying: Bool? = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.lastPlayerStatusCache?.status.isPlaying
        }

        // Refresh ultra-fast CoreAudio HAL running check (< 0.1 ms, zero AppleScript) every 250 ms
        if (nowMono - lastHalRunCheckMono) >= 0.25 {
            lastHalRunCheckMono = nowMono
            cachedHalOutputRunning = AudioProcessTapService.isMusicAppRunningAudioOutput()
        }

        let hasLiveSignal = (nowMono - lastNonSilentMono) < 0.45
        let rawPlaying: Bool
        if hasLiveSignal {
            rawPlaying = true
        } else if userExplicitlyPaused && cachedPlaying == false {
            rawPlaying = false
        } else if cachedHalOutputRunning && !userExplicitlyPaused {
            rawPlaying = true
        } else if cachedPlaying == true {
            rawPlaying = true
        } else {
            rawPlaying = false
        }

        if rawPlaying {
            playingHoldUntilMono = nowMono + 0.85
            return true
        }
        if userExplicitlyPaused && !hasLiveSignal && !cachedHalOutputRunning {
            playingHoldUntilMono = -1.0e9
            return false
        }
        return nowMono < playingHoldUntilMono
    }

    // MARK: - 40 FPS Multi-Zone Frame Generator & Flicker-Free DDP Packet Dispatch

    internal func tickFrame() {
        let nowMono = Double(DispatchTime.now().uptimeNanoseconds) * 1.0e-9

        let (active, ip, currentMode, count, baseBri, targetZ, targetA, needsAutoProbe) = lock.withLock {
            (
                self._isEnabled && !self._ipAddress.isEmpty && self._mode != "off",
                self._ipAddress,
                self._mode,
                self._ledCount,
                self._brightness,
                self.targetZones,
                self.targetAnchors,
                self.lastProbedIP != self._ipAddress && !self.isProbingDeviceInfo
            )
        }
        guard active, count > 0 else { return }

        // If WLED controller was powered on after app launch, re-probe `/json/info` at most every 12s until discovered
        if needsAutoProbe && (nowMono - lastAutoProbeAttemptMono) >= 12.0 {
            lastAutoProbeAttemptMono = nowMono
            probeWledDeviceInfoIfNeeded(ip: ip)
        }

        ensureSocket(for: ip)
        guard udpSocket >= 0, var addr = cachedSockAddr else { return }

        // Read RT audio telemetry under leaf spinlock (~15 ns)
        os_unfair_lock_lock(&rtSpinLock)
        let rawBass = rtBassLevel
        let rawMid = rtMidLevel
        let rawHigh = rtHighLevel
        let rawBeat = rtBeatPulse
        let lastTapMono = rtLastTapCallbackMono
        let lastNonSilentMono = rtLastNonSilentMono
        os_unfair_lock_unlock(&rtSpinLock)

        // Smoothly crossfade `currentZones -> targetZones` and `currentAnchors -> targetAnchors` (~0.7s silk crossfade)
        let zoneLerp = 0.065
        for i in 0..<min(currentZones.count, targetZ.count) {
            currentZones[i].r += (targetZ[i].r - currentZones[i].r) * zoneLerp
            currentZones[i].g += (targetZ[i].g - currentZones[i].g) * zoneLerp
            currentZones[i].b += (targetZ[i].b - currentZones[i].b) * zoneLerp
        }
        for i in 0..<min(currentAnchors.count, targetA.count) {
            currentAnchors[i].r += (targetA[i].r - currentAnchors[i].r) * zoneLerp
            currentAnchors[i].g += (targetA[i].g - currentAnchors[i].g) * zoneLerp
            currentAnchors[i].b += (targetA[i].b - currentAnchors[i].b) * zoneLerp
        }

        let isPlaying = resolveStablePlaybackState(nowMono: nowMono, lastNonSilentMono: lastNonSilentMono)
        let hasLiveLocalTap = (nowMono - lastTapMono) < 0.65

        // Smooth dim transition between playing (1.0) and paused/idle ambient glow (0.18)
        let targetDim = isPlaying ? 1.0 : 0.18
        playbackDimFactor += (targetDim - playbackDimFactor) * (isPlaying ? 0.10 : 0.05)

        // Smooth 40 FPS audio envelopes: fast attack for crisp beat lock, smooth release to prevent flicker
        if !isPlaying {
            smoothedBass += (0.0 - smoothedBass) * 0.14
            smoothedMid  += (0.0 - smoothedMid)  * 0.14
            smoothedHigh += (0.0 - smoothedHigh) * 0.14
            smoothedBeat += (0.0 - smoothedBeat) * 0.18
        } else if hasLiveLocalTap {
            smoothedBass += (rawBass - smoothedBass) * (rawBass > smoothedBass ? 0.52 : 0.20)
            smoothedMid  += (rawMid  - smoothedMid)  * (rawMid  > smoothedMid  ? 0.45 : 0.18)
            smoothedHigh += (rawHigh - smoothedHigh) * (rawHigh > smoothedHigh ? 0.48 : 0.20)
            smoothedBeat += (rawBeat - smoothedBeat) * (rawBeat > smoothedBeat ? 0.62 : 0.22)
        } else if DLNADiscoveryManager.shared.hasActiveRenderer {
            // Gentle slow breath ONLY when streaming to an external network renderer without local CoreAudio output
            let gentlePulse = 0.5 + 0.5 * sin(phase * 0.9)
            smoothedBass += (gentlePulse * 0.45 - smoothedBass) * 0.08
            smoothedMid  += ((0.5 + 0.5 * cos(phase * 0.6)) * 0.38 - smoothedMid) * 0.08
            smoothedHigh += (0.20 - smoothedHigh) * 0.08
            smoothedBeat += (gentlePulse * 0.30 - smoothedBeat) * 0.08
        } else {
            smoothedBass += (0.0 - smoothedBass) * 0.14
            smoothedMid  += (0.0 - smoothedMid)  * 0.14
            smoothedHigh += (0.0 - smoothedHigh) * 0.14
            smoothedBeat += (0.0 - smoothedBeat) * 0.16
        }

        if isPlaying {
            phase += 0.018 + smoothedMid * 0.012
            beatPhase += 0.020 + smoothedBeat * 0.065
            if phase > Double.pi * 400.0 { phase -= Double.pi * 400.0 }
            if beatPhase > Double.pi * 400.0 { beatPhase -= Double.pi * 400.0 }
        }

        stepShockwaveRingsOnQueue(
            nowMono: nowMono,
            isPlaying: isPlaying,
            rawBeat: rawBeat,
            smoothedBass: smoothedBass
        )

        // Resize temporal anti-flicker buffers if strip LED count changed
        if renderedLinearRGB.count != count {
            renderedLinearRGB = Array(repeating: (0.0, 0.0, 0.0), count: count)
            lastQuantizedRGB = Array(repeating: 0, count: count * 3)
        }

        let payloadByteCount = count * 3
        var packet = [UInt8](repeating: 0, count: 10 + payloadByteCount)

        // DDP 10-byte Header
        packet[0] = 0x41 // Version 1 + PUSH flag
        packet[1] = sequenceNumber
        sequenceNumber = (sequenceNumber % 15) + 1
        packet[2] = 0x01 // RGB 8-bit
        packet[3] = 0x01 // Default destination ID
        let lenBE = UInt16(payloadByteCount).bigEndian
        packet[8] = UInt8(lenBE & 0xFF)
        packet[9] = UInt8((lenBE >> 8) & 0xFF)

        let zCount = Double(Self.zoneCount)
        let zonesSnapshot = currentZones
        let anchorsSnapshot = currentAnchors
        let effectiveBri = baseBri * playbackDimFactor
        let motionWeight = max(0.0, min(1.0, (playbackDimFactor - 0.18) / 0.82))

        let bassEnergy = min(1.0, smoothedBass * 0.55 + smoothedBeat * 0.65)
        let midEnergy  = min(1.0, smoothedMid)
        let highEnergy = min(1.0, smoothedHigh)
        let beatPunch  = min(1.0, smoothedBeat)

        for i in 0..<count {
            let normPos = count > 1 ? Double(i) / Double(count - 1) : 0.0
            let distFromCenter = abs(normPos - 0.5) * 2.0 // 0.0 at center, 1.0 at edges
            let baseZoneIdx = normPos * (zCount - 1.0)
            let (targetR, targetG, targetB) = evaluateModePixelRGB(
                mode: currentMode,
                normPos: normPos,
                distFromCenter: distFromCenter,
                baseZoneIdx: baseZoneIdx,
                zonesSnapshot: zonesSnapshot,
                anchors: anchorsSnapshot,
                effectiveBri: effectiveBri,
                motionWeight: motionWeight,
                bassEnergy: bassEnergy,
                midEnergy: midEnergy,
                highEnergy: highEnergy,
                beatPunch: beatPunch
            )

            // Per-LED temporal smoothing + Gamma 2.0 with 0.42 LSB deadband hysteresis (zero step-flicker!)
            let prevLin = renderedLinearRGB[i]
            let smoothCoeffR = targetR > prevLin.r ? 0.55 : 0.26
            let smoothCoeffG = targetG > prevLin.g ? 0.55 : 0.26
            let smoothCoeffB = targetB > prevLin.b ? 0.55 : 0.26
            let linR = prevLin.r + (targetR - prevLin.r) * smoothCoeffR
            let linG = prevLin.g + (targetG - prevLin.g) * smoothCoeffG
            let linB = prevLin.b + (targetB - prevLin.b) * smoothCoeffB
            renderedLinearRGB[i] = (linR, linG, linB)

            let outOffset = i * 3
            let qR = Self.quantizeGamma2WithHysteresis(linear255: linR, previousByte: lastQuantizedRGB[outOffset])
            let qG = Self.quantizeGamma2WithHysteresis(linear255: linG, previousByte: lastQuantizedRGB[outOffset + 1])
            let qB = Self.quantizeGamma2WithHysteresis(linear255: linB, previousByte: lastQuantizedRGB[outOffset + 2])
            lastQuantizedRGB[outOffset]     = qR
            lastQuantizedRGB[outOffset + 1] = qG
            lastQuantizedRGB[outOffset + 2] = qB

            let baseIdx = 10 + outOffset
            packet[baseIdx]     = qR
            packet[baseIdx + 1] = qG
            packet[baseIdx + 2] = qB
        }

        packet.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                    _ = Darwin.sendto(udpSocket, base, packet.count, 0, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    @inline(__always)
    internal static func quantizeGamma2WithHysteresis(linear255: Double, previousByte: UInt8) -> UInt8 {
        let clamped = min(max(linear255 / 255.0, 0.0), 1.0)
        // Perceptual Gamma 2.0 + Schmitt-trigger deadband (> 0.65 LSB) prevents `.5` rounding boundary chatter
        let gammaScaled = (clamped * clamped) * 255.0
        if abs(gammaScaled - Double(previousByte)) <= 0.65 {
            return previousByte
        }
        return UInt8(min(max(Int(gammaScaled.rounded()), 0), 255))
    }

    internal func dispatchBlackoutPacketSync(ip: String) {
        guard !PlaybackRouter.shared.isTestingEnvironment,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              Self.validatedUnicastPrivateOrLoopbackIPv4(ip) != nil else {
            return
        }
        let count = lock.withLock { self._ledCount }
        guard count > 0 else { return }
        ensureSocket(for: ip)
        guard udpSocket >= 0, var addr = self.cachedSockAddr else { return }

        let payloadByteCount = count * 3
        var packet = [UInt8](repeating: 0, count: 10 + payloadByteCount)
        packet[0] = 0x41
        packet[1] = sequenceNumber
        sequenceNumber = (sequenceNumber % 15) + 1
        packet[2] = 0x01
        packet[3] = 0x01
        let lenBE = UInt16(payloadByteCount).bigEndian
        packet[8] = UInt8(lenBE & 0xFF)
        packet[9] = UInt8((lenBE >> 8) & 0xFF)

        packet.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                    _ = Darwin.sendto(udpSocket, base, packet.count, 0, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    internal func sendBlackoutFrame(targetIP: String? = nil) {
        ddpQueue.async { [weak self] in
            guard let self = self else { return }
            let ip = targetIP ?? self.lock.withLock { self._ipAddress }
            self.dispatchBlackoutPacketSync(ip: ip)
        }
    }
}
