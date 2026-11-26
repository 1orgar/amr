//
//  ExternalAmpTCPController+Networking.swift
//  AppleMusicRemoteMac
//
//  NWConnection Persistent TCP Socket Lifecycle, Connection Probing,
//  Fragmented ASCII Push Stream Parser & Separate Pending Volume/Mute Queues
//

import Foundation
import Network

extension ExternalAmpTCPController {

    /// Probes the TCP connection to the amplifier, sends a status query command, and reports the result on the main thread.
    public func testConnection(
        profile: ExternalAmpProfile,
        host: String,
        port: UInt16,
        completion: @escaping @Sendable (_ success: Bool, _ message: String) -> Void
    ) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            DispatchQueue.main.async {
                completion(
                    false,
                    AMRLocalization.tr(
                        "🟠 Enter the amplifier IP address to test connection",
                        "🟠 Укажите IP-адрес усилителя для проверки соединения"
                    )
                )
            }
            return
        }
        let validPort = port > 0 ? port : profile.defaultPort
        guard let nwPort = NWEndpoint.Port(rawValue: validPort) else {
            DispatchQueue.main.async {
                completion(
                    false,
                    AMRLocalization.tr(
                        "❌ Invalid TCP port: \(validPort)",
                        "❌ Некорректный TCP-порт: \(validPort)"
                    )
                )
            }
            return
        }

        let probeQueue = DispatchQueue(label: "com.amr.ext-amp-probe", qos: .userInitiated)
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = 3
        tcpOptions.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        let probeConn = NWConnection(host: NWEndpoint.Host(trimmedHost), port: nwPort, using: params)

        final class ProbeState: @unchecked Sendable {
            var completed = false
            var tcpConnected = false
            var responseBuffer = ""
            var detectedVolume: Int?
            var detectedMute: Bool?
        }
        let state = ProbeState()

        let finish: @Sendable (Bool, String) -> Void = { [weak self] ok, msg in
            guard !state.completed else { return }
            state.completed = true
            probeConn.stateUpdateHandler = nil
            probeConn.cancel()
            if ok, let self {
                let lockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100
                let matchesActiveConfig = self.lock.withLock { () -> Bool in
                    self._cachedVolumeLockedTo100 = lockedTo100
                    let isMatching = self._isEnabled &&
                        self._profile == profile &&
                        self._host == trimmedHost &&
                        self._port == validPort &&
                        lockedTo100
                    guard isMatching else { return false }
                    if let v = state.detectedVolume {
                        if v == 0 && self._baseListeningVolume > 0 {
                            NSLog("[ExternalAmpTCP] testConnection zero-jump guard: ignoring detectedVolume=0 while base=%d", self._baseListeningVolume)
                        } else {
                            self.hasSyncedVolumeWithAmp = true
                            self._currentVolume = v
                            let effectiveMax = max(1, min(100, min(self._maxVolumeCap, profile.nativeMaxVolume)))
                            if self._isSoundCheckEnabled && self.lastPersistedAmpVolume > 0 && v == self.lastPersistedAmpVolume {
                                self.appliedVolumeOffset = v - self._baseListeningVolume
                            } else {
                                let resolved = self.resolveBaseAndOffsetForManualVolume(v, effectiveMax: effectiveMax)
                                self._baseListeningVolume = resolved.base
                                if self._isSoundCheckEnabled {
                                    self._currentTrackVolumeOffset = resolved.offset
                                    self.appliedVolumeOffset = resolved.offset
                                }
                            }
                        }
                    }
                    if let m = state.detectedMute {
                        self._isMuted = m
                    }
                    self._lastError = nil
                    return true
                }
                if matchesActiveConfig {
                    self.reconfigureConnection()
                    self.notifyStateChanged()
                }
            }
            DispatchQueue.main.async {
                completion(ok, msg)
            }
        }

        @Sendable func receiveNextProbeChunk() {
            probeConn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, isComplete, error in
                guard !state.completed else { return }
                if let data, !data.isEmpty,
                   let str = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
                    state.responseBuffer.append(str)
                    let delimiters: Set<Character> = profile == .rotel
                        ? ["$", "!", "\r", "\n"]
                        : ["\r", "\n", "$"]
                    let tokens = state.responseBuffer.split(whereSeparator: { delimiters.contains($0) }).map(String.init)
                    for tok in tokens {
                        let parsed = profile.parseToken(tok)
                        if let v = parsed.volume { state.detectedVolume = v }
                        if let m = parsed.muted { state.detectedMute = m }
                    }
                }
                if let vol = state.detectedVolume {
                    let muteStr = (state.detectedMute == true) ? " • MUTE" : ""
                    finish(
                        true,
                        AMRLocalization.tr(
                            "✅ Connected: \(profile.displayName) (\(trimmedHost):\(validPort)) replied • Volume: \(vol)%\(muteStr)",
                            "✅ Соединение установлено: \(profile.displayName) (\(trimmedHost):\(validPort)) ответил • Громкость: \(vol)%\(muteStr)"
                        )
                    )
                } else if isComplete || error != nil {
                    finish(
                        true,
                        AMRLocalization.tr(
                            "✅ Connected: \(profile.displayName) (\(trimmedHost):\(validPort)) reachable via TCP",
                            "✅ Соединение установлено: \(profile.displayName) (\(trimmedHost):\(validPort)) доступен по TCP"
                        )
                    )
                } else {
                    receiveNextProbeChunk()
                }
            }
        }

        probeQueue.asyncAfter(deadline: .now() + 3.2) {
            guard !state.completed else { return }
            if state.tcpConnected {
                finish(
                    true,
                    AMRLocalization.tr(
                        "✅ TCP socket reachable: \(profile.displayName) (\(trimmedHost):\(validPort)) connected",
                        "✅ TCP-сокет доступен: \(profile.displayName) (\(trimmedHost):\(validPort)) подключен"
                    )
                )
            } else {
                finish(
                    false,
                    AMRLocalization.tr(
                        "❌ Connection timeout to \(profile.displayName) (\(trimmedHost):\(validPort)) — check IP, port, and network",
                        "❌ Таймаут подключения к \(profile.displayName) (\(trimmedHost):\(validPort)) — проверьте IP, порт и сеть"
                    )
                )
            }
        }

        probeConn.stateUpdateHandler = { connState in
            switch connState {
            case .ready:
                state.tcpConnected = true
                let query = profile.buildQueryStatusCommand()
                if let data = query.data(using: .utf8) {
                    probeConn.send(content: data, completion: .contentProcessed { _ in })
                }
                receiveNextProbeChunk()
                probeQueue.asyncAfter(deadline: .now() + 1.1) {
                    guard !state.completed else { return }
                    if let vol = state.detectedVolume {
                        let muteStr = (state.detectedMute == true) ? " • MUTE" : ""
                        finish(
                            true,
                            AMRLocalization.tr(
                                "✅ Connected: \(profile.displayName) (\(trimmedHost):\(validPort)) replied • Volume: \(vol)%\(muteStr)",
                                "✅ Соединение установлено: \(profile.displayName) (\(trimmedHost):\(validPort)) ответил • Громкость: \(vol)%\(muteStr)"
                            )
                        )
                    } else {
                        finish(
                            true,
                            AMRLocalization.tr(
                                "✅ TCP socket reachable: \(profile.displayName) (\(trimmedHost):\(validPort)) connected",
                                "✅ TCP-сокет доступен: \(profile.displayName) (\(trimmedHost):\(validPort)) подключен"
                            )
                        )
                    }
                }

            case .failed(let error):
                finish(
                    false,
                    AMRLocalization.tr(
                        "❌ Connection error to \(trimmedHost):\(validPort): \(error.localizedDescription)",
                        "❌ Ошибка подключения к \(trimmedHost):\(validPort): \(error.localizedDescription)"
                    )
                )

            default:
                break
            }
        }

        probeConn.start(queue: probeQueue)
    }

    // MARK: - Internal Connection Lifecycle

    internal func reconfigureConnection() {
        queue.async { [weak self] in
            self?.teardownConnectionOnQueue()
            guard let self else { return }
            let lockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100
            let (shouldConnect, host, port) = self.lock.withLock { () -> (Bool, String, UInt16) in
                self._cachedVolumeLockedTo100 = lockedTo100
                let active = self._isEnabled &&
                    lockedTo100 &&
                    !self._host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                return (active, self._host, self._port)
            }
            if shouldConnect {
                self.connectOnQueue(host: host, port: port)
            }
        }
    }

    internal func teardownConnectionOnQueue() {
        pollTimer?.cancel()
        pollTimer = nil
        reconnectTimer?.cancel()
        reconnectTimer = nil
        receiveBuffer.removeAll(keepingCapacity: false)

        if let conn = connection {
            conn.stateUpdateHandler = nil
            conn.cancel()
            connection = nil
        }

        let wasConnected = lock.withLock {
            let prev = _isConnected
            _isConnected = false
            return prev
        }
        if wasConnected {
            notifyStateChanged()
        }
    }

    internal func connectOnQueue(host: String, port: UInt16) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            lock.withLock { _lastError = AMRLocalization.tr("Invalid port \(port)", "Некорректный порт \(port)") }
            notifyStateChanged()
            return
        }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 15
        tcpOptions.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                let (prof, pendingVol, pendingMute) = self.lock.withLock { () -> (ExternalAmpProfile, Double?, Bool?) in
                    self._isConnected = true
                    self._lastError = nil
                    let v = self.pendingVolumeCommand
                    let m = self.pendingMuteCommand
                    self.pendingVolumeCommand = nil
                    self.pendingMuteCommand = nil
                    return (self._profile, v, m)
                }
                NSLog("[ExternalAmpTCP] Connected to %@ at %@:%u", prof.displayName, host, port)
                self.receiveBuffer.removeAll(keepingCapacity: false)
                self.startReceiveLoopOnQueue(for: conn)
                self.startPollTimerOnQueue()
                if let pendingVol {
                    let volCmd = prof.buildSetVolumeCommand(Int(pendingVol.rounded()))
                    self.sendRawCommandOnQueue(volCmd, on: conn)
                }
                if let pendingMute {
                    let muteCmd = prof.buildMuteCommand(muted: pendingMute)
                    self.sendRawCommandOnQueue(muteCmd, on: conn)
                }
                // Query initial volume & mute immediately upon connection
                self.sendRawCommandOnQueue(prof.buildQueryStatusCommand(), on: conn)
                self.notifyStateChanged()

            case .failed(let error):
                NSLog("[ExternalAmpTCP] Connection failed (%@:%u): %@", host, port, error.localizedDescription)
                self.lock.withLock {
                    self._isConnected = false
                    self._lastError = error.localizedDescription
                }
                self.notifyStateChanged()
                self.scheduleReconnectOnQueue()

            case .waiting(let error):
                self.lock.withLock {
                    self._isConnected = false
                    self._lastError = error.localizedDescription
                }
                self.notifyStateChanged()

            case .cancelled:
                self.lock.withLock {
                    self._isConnected = false
                }
                self.notifyStateChanged()

            default:
                break
            }
        }

        conn.start(queue: queue)
    }

    internal func startReceiveLoopOnQueue(for conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            guard self.connection === conn else { return }

            if let data, !data.isEmpty, let chunk = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
                self.handleIncomingChunkOnQueue(chunk)
            }

            if let error {
                NSLog("[ExternalAmpTCP] Receive error: %@", error.localizedDescription)
                self.lock.withLock {
                    self._isConnected = false
                    self._lastError = error.localizedDescription
                }
                self.notifyStateChanged()
                self.scheduleReconnectOnQueue()
                return
            }

            if isComplete {
                NSLog("[ExternalAmpTCP] Remote peer closed TCP connection.")
                self.lock.withLock {
                    self._isConnected = false
                }
                self.notifyStateChanged()
                self.scheduleReconnectOnQueue()
                return
            }

            self.startReceiveLoopOnQueue(for: conn)
        }
    }

    /// Processes incoming stream chunks, splitting on `$`, `!` (for Rotel), `\r`, or `\n`.
    /// Exposed internally for unit testing.
    internal func processIncomingChunkForTesting(_ chunk: String) {
        queue.sync {
            handleIncomingChunkOnQueue(chunk)
        }
    }

    internal func handleIncomingChunkOnQueue(_ chunk: String) {
        receiveBuffer.append(chunk)

        let prof = lock.withLock { _profile }
        var stateUpdated = false

        // Delimiters: `$` (Rotel V1/V2 responses), `\r`, `\n`, and `!` (for Rotel)
        let delimiters: Set<Character> = prof == .rotel
            ? ["$", "!", "\r", "\n"]
            : ["\r", "\n", "$"]

        while let idx = receiveBuffer.firstIndex(where: { delimiters.contains($0) }) {
            let token = String(receiveBuffer[..<idx])
            let afterIdx = receiveBuffer.index(after: idx)
            receiveBuffer.removeSubrange(..<afterIdx)

            let parsed = prof.parseToken(token)
            if parsed.volume != nil || parsed.muted != nil {
                let isDucked = AudioDuckingController.shared.isDucked
                let postAdj = MasteringRestorationService.shared.postFilterNormalizationAdjustment()
                var deferredAutoNormTarget: (vol: Int, profile: ExternalAmpProfile)?
                let changed = lock.withLock { () -> Bool in
                    let sinceUserCmd = Date().timeIntervalSince(self.lastUserCommandTime)
                    let sinceAutoCmd = Date().timeIntervalSince(self.lastAutoNormCommandTime)
                    var modified = false
                    if let newVol = parsed.volume {
                        let effectiveMax = max(1, min(100, min(self._maxVolumeCap, self._profile.nativeMaxVolume)))
                        if !self.hasSyncedVolumeWithAmp {
                            if newVol == 0 && self._baseListeningVolume > 0 {
                                // Zero-jump guard on initial connect: amplifier in Standby / relay mute reports volume=00; preserve saved _baseListeningVolume
                                NSLog("[ExternalAmpTCP] Zero-jump guard: ignoring initial volume=0 report while saved base=%d", self._baseListeningVolume)
                            } else {
                                self.hasSyncedVolumeWithAmp = true
                                self._currentVolume = newVol
                                if self._isSoundCheckEnabled && self.lastPersistedAmpVolume > 0 && newVol == self.lastPersistedAmpVolume {
                                    self.appliedVolumeOffset = newVol - self._baseListeningVolume
                                } else {
                                    let offsetToSubtract = self._isSoundCheckEnabled ? self.appliedVolumeOffset : 0
                                    self._baseListeningVolume = max(0, min(effectiveMax, newVol - offsetToSubtract))
                                    AppStorageProvider.shared.set(self._baseListeningVolume, forKey: self.kBaseVolumeKey)
                                }
                                if self._isSoundCheckEnabled {
                                    self._currentTrackVolumeOffset = Self.computeVolumeOffset(
                                        forGainDb: self._currentTrackGainDb,
                                        baseVolume: self._baseListeningVolume,
                                        smartLowVolume: self._isLowVolumeSmartNormEnabled,
                                        compressionCompensation: self._isCompressionCompensationEnabled,
                                        crestFactorDb: self._currentTrackCrestDb,
                                        digitalSoundCheckAlreadyActive: self._isDigitalSoundCheckAlreadyActive,
                                        postFilterRestoredPeakDb: postAdj.restoredPeakDb,
                                        postFilterDigitalPadDb: postAdj.digitalPadDb
                                    )
                                }
                                if self._isSoundCheckEnabled && !self._currentTrackKey.isEmpty && !self._isMuted && (self._baseListeningVolume > 0 || self._currentVolume > 0) && self.appliedVolumeOffset != self._currentTrackVolumeOffset {
                                    let minAutoVol = self._baseListeningVolume > 0 ? 1 : 0
                                    let targetVol = max(minAutoVol, min(effectiveMax, self._baseListeningVolume + self._currentTrackVolumeOffset))
                                    self.appliedVolumeOffset = self._currentTrackVolumeOffset
                                    if targetVol != self._currentVolume {
                                        self.lastAutoNormPreviousVolume = self._currentVolume
                                        self.lastAutoNormTargetVolume = targetVol
                                        self._currentVolume = targetVol
                                        self.lastAutoNormCommandTime = Date()
                                        self.lastPersistedAmpVolume = targetVol
                                        AppStorageProvider.shared.set(targetVol, forKey: self.kLastSentAmpVolumeKey)
                                        deferredAutoNormTarget = (targetVol, self._profile)
                                        NSLog("[ExternalAmpTCP] Initial sync SoundCheck '%@': gain=%+.2f dB, offset=%+d, base=%d -> ampVol=%d",
                                              self._currentTrackKey, self._currentTrackGainDb ?? 0.0, self._currentTrackVolumeOffset, self._baseListeningVolume, targetVol)
                                    }
                                }
                                modified = true
                            }
                        } else if let target = self.lastAutoNormTargetVolume, sinceAutoCmd < 2.5, newVol == target {
                            self.lastAutoNormTargetVolume = nil
                            self.lastAutoNormPreviousVolume = nil
                            self.lastUserCommandTime = .distantPast
                            if self._currentVolume != newVol {
                                self._currentVolume = newVol
                                modified = true
                            }
                        } else if self.lastAutoNormTargetVolume != nil, let prev = self.lastAutoNormPreviousVolume, sinceAutoCmd < 0.85, newVol == prev {
                            // Ignore stale in-flight poll echo of the previous track's volume
                        } else if newVol == 0 && self._currentVolume >= 6 {
                            NSLog("[ExternalAmpTCP] Zero-jump guard: ignoring sudden uncommanded drop from %d to 0", self._currentVolume)
                        } else if sinceUserCmd > 0.45 && self._currentVolume != newVol && !isDucked {
                            self._currentVolume = newVol
                            self.lastAutoNormTargetVolume = nil
                            self.lastAutoNormPreviousVolume = nil
                            let resolved = self.resolveBaseAndOffsetForManualVolume(newVol, effectiveMax: effectiveMax)
                            self._baseListeningVolume = resolved.base
                            if self._isSoundCheckEnabled {
                                self._currentTrackVolumeOffset = resolved.offset
                                self.appliedVolumeOffset = resolved.offset
                            } else {
                                self.appliedVolumeOffset = 0
                            }
                            self.lastPersistedAmpVolume = newVol
                            AppStorageProvider.shared.set(self._baseListeningVolume, forKey: self.kBaseVolumeKey)
                            AppStorageProvider.shared.set(newVol, forKey: self.kLastSentAmpVolumeKey)
                            NSLog("[ExternalAmpTCP] Physical knob/remote volume=%d (offset=%+d) -> new base=%d",
                                  newVol, resolved.offset, self._baseListeningVolume)
                            modified = true
                        }
                    }
                    if let newMute = parsed.muted {
                        if sinceUserCmd > 0.35 || newMute == self._isMuted {
                            if self._isMuted != newMute {
                                self._isMuted = newMute
                                modified = true
                            }
                        }
                    }
                    return modified
                }
                if let v = deferredAutoNormTarget {
                    sendVolumeCommand(v.vol, profile: v.profile)
                }
                if changed {
                    stateUpdated = true
                }
            }
        }

        if receiveBuffer.count > 4096 {
            receiveBuffer.removeAll(keepingCapacity: false)
        }

        if stateUpdated {
            notifyStateChanged()
        }
    }

    internal func startPollTimerOnQueue() {
        pollTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 4.0, repeating: 4.0, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            guard let self, let conn = self.connection else { return }
            let (connected, prof) = self.lock.withLock { (self._isConnected, self._profile) }
            guard connected else { return }
            self.sendRawCommandOnQueue(prof.buildQueryStatusCommand(), on: conn)
        }
        pollTimer = timer
        timer.resume()
    }

    internal func scheduleReconnectOnQueue() {
        pollTimer?.cancel()
        pollTimer = nil
        if let conn = connection {
            conn.stateUpdateHandler = nil
            conn.cancel()
            connection = nil
        }

        reconnectTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 3.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.reconnectTimer = nil
            let lockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100
            let (shouldConnect, host, port) = self.lock.withLock { () -> (Bool, String, UInt16) in
                self._cachedVolumeLockedTo100 = lockedTo100
                let active = self._isEnabled &&
                    lockedTo100 &&
                    !self._host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                return (active, self._host, self._port)
            }
            if shouldConnect {
                self.connectOnQueue(host: host, port: port)
            }
        }
        reconnectTimer = timer
        timer.resume()
    }

    // MARK: - Command Dispatch with Independent Pending Volume & Mute Slots

    internal func sendVolumeCommand(_ targetVolume: Int, profile: ExternalAmpProfile) {
        let cmd = profile.buildSetVolumeCommand(targetVolume)
        queue.async { [weak self] in
            guard let self else { return }
            if let conn = self.connection, self.lock.withLock({ self._isConnected }) {
                self.sendRawCommandOnQueue(cmd, on: conn)
            } else {
                let lockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100
                let (shouldConnect, host, port) = self.lock.withLock { () -> (Bool, String, UInt16) in
                    self._cachedVolumeLockedTo100 = lockedTo100
                    self.pendingVolumeCommand = Double(targetVolume)
                    let active = self._isEnabled &&
                        lockedTo100 &&
                        !self._host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    return (active, self._host, self._port)
                }
                if shouldConnect && self.connection == nil {
                    self.connectOnQueue(host: host, port: port)
                }
            }
        }
    }

    internal func sendMuteCommand(_ targetMuted: Bool, profile: ExternalAmpProfile) {
        let cmd = profile.buildMuteCommand(muted: targetMuted)
        queue.async { [weak self] in
            guard let self else { return }
            if let conn = self.connection, self.lock.withLock({ self._isConnected }) {
                self.sendRawCommandOnQueue(cmd, on: conn)
            } else {
                let lockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100
                let (shouldConnect, host, port) = self.lock.withLock { () -> (Bool, String, UInt16) in
                    self._cachedVolumeLockedTo100 = lockedTo100
                    self.pendingMuteCommand = targetMuted
                    let active = self._isEnabled &&
                        lockedTo100 &&
                        !self._host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    return (active, self._host, self._port)
                }
                if shouldConnect && self.connection == nil {
                    self.connectOnQueue(host: host, port: port)
                }
            }
        }
    }

    internal func sendQueryStatusIfConnected(profile: ExternalAmpProfile) {
        let cmd = profile.buildQueryStatusCommand()
        queue.async { [weak self] in
            guard let self, let conn = self.connection, self.lock.withLock({ self._isConnected }) else { return }
            self.sendRawCommandOnQueue(cmd, on: conn)
        }
    }

    internal func sendRawCommandOnQueue(_ command: String, on conn: NWConnection) {
        guard let data = command.data(using: .utf8) else { return }
        conn.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                NSLog("[ExternalAmpTCP] Send error: %@", error.localizedDescription)
                self?.queue.async {
                    self?.lock.withLock {
                        self?._isConnected = false
                        self?._lastError = error.localizedDescription
                    }
                    self?.notifyStateChanged()
                    self?.scheduleReconnectOnQueue()
                }
            }
        })
    }
}
