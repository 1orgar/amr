//
//  WebSocketServer+Broadcast.swift
//  AppleMusicRemoteMac
//
//  Outgoing WebSocket envelopes, per-connection backpressure tracking,
//  and live status / audio-device broadcasts.
//

import Foundation
import Network

extension WebSocketServer {
    // MARK: - Outgoing WebSocket Messages

    public func sendSuccess<T: Encodable>(action: String, data: T, id: String?, to connection: NWConnection) {
        var baseObj: [String: Any] = [
            "action": action,
            "event": action,
            "type": action,
            "status": "ok"
        ]
        if let reqId = id {
            baseObj["id"] = reqId
        }

        if let encodedData = try? JSONEncoder().encode(data),
           let dataObj = try? JSONSerialization.jsonObject(with: encodedData) {
            baseObj["data"] = dataObj
        } else {
            baseObj["data"] = "\(data)"
        }

        if JSONSerialization.isValidJSONObject(baseObj),
           let jsonBytes = try? JSONSerialization.data(withJSONObject: baseObj),
           let text = String(data: jsonBytes, encoding: .utf8) {
            sendText(text, to: connection)
        }
    }

    public func sendSuccess(action: String, data: [String: Any], id: String?, to connection: NWConnection) {
        var payload: [String: Any] = [
            "action": action,
            "event": action,
            "type": action,
            "status": "ok"
        ]
        if let reqId = id {
            payload["id"] = reqId
        }

        let sanitizedData = sanitizeForJSON(data)
        payload["data"] = sanitizedData

        if JSONSerialization.isValidJSONObject(payload),
           let jsonBytes = try? JSONSerialization.data(withJSONObject: payload),
           let text = String(data: jsonBytes, encoding: .utf8) {
            sendText(text, to: connection)
        }
    }

    internal func sanitizeForJSON(_ value: Any) -> Any {
        if let ac = value as? AnyCodable {
            return sanitizeForJSON(ac.value ?? NSNull())
        } else if let dict = value as? [String: Any] {
            var res = [String: Any]()
            for (k, v) in dict {
                res[k] = sanitizeForJSON(v)
            }
            return res
        } else if let arr = value as? [Any] {
            return arr.map { sanitizeForJSON($0) }
        } else if let str = value as? String {
            return str
        } else if let num = value as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return num.boolValue
            }
            let d = num.doubleValue
            if !d.isFinite {
                return 0.0
            }
            return num
        } else if let b = value as? Bool {
            return b
        } else if let i = value as? Int {
            return i
        } else if let d = value as? Double {
            return d.isFinite ? d : 0.0
        } else if let f = value as? Float {
            return f.isFinite ? Double(f) : 0.0
        } else if let s = value as? StationInfo {
            if let data = try? JSONEncoder().encode(s),
               let obj = try? JSONSerialization.jsonObject(with: data) {
                return obj
            }
            return s.name
        } else if let t = value as? TrackInfo {
            if let data = try? JSONEncoder().encode(t),
               let obj = try? JSONSerialization.jsonObject(with: data) {
                return obj
            }
            return t.name
        } else if let sel = value as? TVLibraryAlbumSelection {
            if let data = try? JSONEncoder().encode(sel),
               let obj = try? JSONSerialization.jsonObject(with: data) {
                return obj
            }
            return ["key": sel.key, "id": sel.id, "name": sel.name, "artist": sel.artist]
        } else if value is NSNull {
            return NSNull()
        } else {
            return String(describing: value)
        }
    }

    public func sendError(action: String, error: String, id: String?, to connection: NWConnection) {
        var payload: [String: Any] = [
            "action": action,
            "status": "error",
            "error": error
        ]
        if let reqId = id {
            payload["id"] = reqId
        }

        if JSONSerialization.isValidJSONObject(payload),
           let jsonBytes = try? JSONSerialization.data(withJSONObject: payload),
           let text = String(data: jsonBytes, encoding: .utf8) {
            sendText(text, to: connection)
        }
    }

    public struct EventEnvelope<T: Encodable>: Encodable {
        public let event: String
        public let type: String
        public let data: T
    }

    public func sendEvent<T: Encodable>(_ eventName: String, data: T, to connection: NWConnection) {
        let env = EventEnvelope(event: eventName, type: eventName, data: data)
        if let encoded = try? JSONEncoder().encode(env),
           let text = String(data: encoded, encoding: .utf8) {
            sendText(text, to: connection)
        }
    }

    public func sendEvent(name: String, data: [String: Any], to connection: NWConnection) {
        let envelope: [String: Any] = [
            "event": name,
            "type": name,
            "data": sanitizeForJSON(data)
        ]
        if JSONSerialization.isValidJSONObject(envelope),
           let json = try? JSONSerialization.data(withJSONObject: envelope),
           let text = String(data: json, encoding: .utf8) {
            sendText(text, to: connection)
        }
    }

    public func pushDeviceAuthStatus(for record: ClientDeviceRecord, newlyAuthorized: Bool) {
        let connIds = ClientDeviceManager.shared.getConnectionIds(forDeviceId: record.deviceId)
        guard !connIds.isEmpty else { return }

        clientLock.lock()
        let conns = connIds.compactMap { clients[$0] }
        clientLock.unlock()

        let dict = record.dictionaryWithSecret
        for conn in conns {
            sendEvent(name: "device_auth_status", data: dict, to: conn)
        }

        if newlyAuthorized && record.isAuthorized {
            Task.detached(priority: .utility) { [weak self] in
                guard let self = self else { return }
                let status = MusicBridge.shared.getPlayerStatus()
                let aiSettings = NativeMusicCuratorService.shared.getSettingsDictionary()
                let dspSettings = Self.buildDSPSettingsDictionary()
                let tvConfig = TVLibraryConfigurationStore.shared.toDictionary()
                for conn in conns {
                    self.sendEvent("player_state_changed", data: status, to: conn)
                    self.sendEvent(name: "ai_curator_settings", data: aiSettings, to: conn)
                    self.sendEvent(name: "dsp_settings", data: dspSettings, to: conn)
                    self.sendEvent(name: "tv_library_config", data: tvConfig, to: conn)
                }
                let queue = await MusicBridge.shared.getPlaybackQueue()
                for conn in conns {
                    self.sendEvent("queue", data: queue, to: conn)
                }
            }
        }
    }

    public func pushDeviceRemoved(for record: ClientDeviceRecord, connectionIds: [UUID]? = nil) {
        let connIds = connectionIds ?? ClientDeviceManager.shared.getConnectionIds(forDeviceId: record.deviceId)
        guard !connIds.isEmpty else { return }

        clientLock.lock()
        let conns = connIds.compactMap { clients[$0] }
        clientLock.unlock()

        var dict = record.dictionary
        dict["authorized"] = false
        dict["removed"] = true
        for conn in conns {
            sendEvent(name: "device_auth_status", data: dict, to: conn)
        }
    }

    public func broadcastEvent<T: Encodable>(_ eventName: String, data: T) {
        let env = EventEnvelope(event: eventName, type: eventName, data: data)
        if let encoded = try? JSONEncoder().encode(env),
           let text = String(data: encoded, encoding: .utf8) {
            broadcastText(text)
        }
    }

    public func broadcastEvent(name: String, data: [String: Any]) {
        let envelope: [String: Any] = [
            "event": name,
            "type": name,
            "data": sanitizeForJSON(data)
        ]
        if JSONSerialization.isValidJSONObject(envelope),
           let json = try? JSONSerialization.data(withJSONObject: envelope),
           let text = String(data: json, encoding: .utf8) {
            broadcastText(text)
        }
    }

    private func sendFrameWithBackpressure(_ frame: Data, to connection: NWConnection) {
        let objId = ObjectIdentifier(connection)
        sendLock.lock()
        let isTrackedSocket: Bool = {
            clientLock.lock()
            defer { clientLock.unlock() }
            return clients.values.contains(where: { $0 === connection })
        }()
        if isTrackedSocket {
            let pending = (pendingOutboundFrames[objId] ?? 0) + 1
            if pending > Self.maxPendingOutboundFrames {
                pendingOutboundFrames.removeValue(forKey: objId)
                sendLock.unlock()
                NSLog("[WebSocket] ⚠️ Disconnecting slow WebSocket client due to outbound backpressure (> %d frames)", Self.maxPendingOutboundFrames)
                connection.cancel()
                return
            }
            pendingOutboundFrames[objId] = pending
        }
        connection.send(content: frame, completion: .contentProcessed({ [weak self] error in
            if let self = self, isTrackedSocket {
                self.sendLock.lock()
                if let current = self.pendingOutboundFrames[objId] {
                    if current <= 1 {
                        self.pendingOutboundFrames.removeValue(forKey: objId)
                    } else {
                        self.pendingOutboundFrames[objId] = current - 1
                    }
                }
                self.sendLock.unlock()
            }
            if let err = error {
                NSLog("[WebSocket] send error: %@", err.localizedDescription)
            }
        }))
        sendLock.unlock()
    }

    public func sendText(_ text: String, to connection: NWConnection) {
        guard let data = text.data(using: .utf8) else { return }
        let frame = makeWebSocketFrame(payload: data, opcode: 0x01)
        sendFrameWithBackpressure(frame, to: connection)
    }

    public func sendBinary(_ data: Data, to connection: NWConnection) {
        let frame = makeWebSocketFrame(payload: data, opcode: 0x02)
        sendFrameWithBackpressure(frame, to: connection)
    }

    public func broadcastText(_ text: String) {
        let unauthIds = ClientDeviceManager.shared.getUnauthorizedConnectionIds()
        clientLock.lock()
        let active = clients.compactMap { (id, conn) -> NWConnection? in
            unauthIds.contains(id) ? nil : conn
        }
        clientLock.unlock()

        for conn in active {
            sendText(text, to: conn)
        }
    }

    public func broadcastStatus(status customStatus: PlayerStatus? = nil, includeQueue: Bool = false) {
        if customStatus == nil && Thread.isMainThread && !PlaybackRouter.shared.isTestingEnvironment {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.broadcastStatus(status: nil, includeQueue: includeQueue)
            }
            return
        }
        let status = customStatus ?? MusicBridge.shared.getPlayerStatus()
        let unauthIds = ClientDeviceManager.shared.getUnauthorizedConnectionIds()
        clientLock.lock()
        let active = clients.compactMap { (id, conn) -> NWConnection? in
            unauthIds.contains(id) ? nil : conn
        }
        clientLock.unlock()

        for conn in active {
            sendEvent("player_state_changed", data: status, to: conn)
        }

        if includeQueue {
            Task {
                let queue = await MusicBridge.shared.getPlaybackQueue()
                for conn in active {
                    sendEvent("queue_changed", data: queue, to: conn)
                }
            }
        }

        Task { @MainActor in
            MenuManager.shared.updateMenuState(with: status)
        }

        UPnPMediaRendererServer.shared.notifySubscribers(status: status)
        DLNADiscoveryManager.shared.handleTrackChanged(status: status)
    }

    public func broadcastAudioDevices() {
        let isDLNAActive = DLNADiscoveryManager.shared.hasActiveRenderer
        let dspActiveDev = isDLNAActive ? nil : AudioEngineController.shared.activeHardwareOutputDeviceInfo
        let coreDevices = CoreAudioDeviceManager.shared.getOutputDevices()

        var devices = coreDevices.map { dev -> [String: Any] in
            var dict = dev.dictionary
            if isDLNAActive {
                dict["isDefault"] = false
            } else if let dspDev = dspActiveDev {
                dict["isDefault"] = (dev.id == dspDev.id)
                if dev.id == dspDev.id {
                    let tel = AudioEngineController.shared.latestTelemetrySnapshot()
                    if tel.dopCarrierRateHz > 0 {
                        dict["sampleRate"] = Double(tel.dopCarrierRateHz)
                    }
                }
            }
            return dict
        }
        if DLNADiscoveryManager.shared.isEnabled {
            devices.append(contentsOf: DLNADiscoveryManager.shared.getDiscoveredDevices())
        }
        var data: [String: Any] = ["devices": devices]
        if let activeDLNA = DLNADiscoveryManager.shared.getActiveRenderer() {
            data["current_device"] = activeDLNA.dictionary
        } else if let dspDev = dspActiveDev,
                  var matched = coreDevices.first(where: { $0.id == dspDev.id })?.dictionary {
            matched["isDefault"] = true
            let tel = AudioEngineController.shared.latestTelemetrySnapshot()
            if tel.dopCarrierRateHz > 0 {
                matched["sampleRate"] = Double(tel.dopCarrierRateHz)
            }
            data["current_device"] = matched
        } else if let defaultDev = CoreAudioDeviceManager.shared.getDefaultOutputDevice()?.dictionary {
            data["current_device"] = defaultDev
        }
        broadcastEvent(name: "audio_devices", data: data)
        broadcastEvent(name: "dsp_settings", data: Self.buildDSPSettingsDictionary())
    }
}
