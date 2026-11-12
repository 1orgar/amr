//
//  WebSocketServer+Broadcast.swift
//  AppleMusicRemoteMac
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

        if let jsonBytes = try? JSONSerialization.data(withJSONObject: baseObj),
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

        // Sanitize data dictionary so AnyCodable or custom Swift structs/enums become native JSON types
        let sanitizedData = sanitizeForJSON(data)
        payload["data"] = sanitizedData

        if let jsonBytes = try? JSONSerialization.data(withJSONObject: payload),
           let text = String(data: jsonBytes, encoding: .utf8) {
            sendText(text, to: connection)
        }
    }

    private func sanitizeForJSON(_ value: Any) -> Any {
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
            return num
        } else if let b = value as? Bool {
            return b
        } else if let i = value as? Int {
            return i
        } else if let d = value as? Double {
            return d
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

        if let jsonBytes = try? JSONSerialization.data(withJSONObject: payload),
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
        if let json = try? JSONSerialization.data(withJSONObject: envelope),
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

        let dict = record.dictionary
        for conn in conns {
            sendEvent(name: "device_auth_status", data: dict, to: conn)
        }

        if newlyAuthorized && record.isAuthorized {
            let status = MusicBridge.shared.getPlayerStatus()
            for conn in conns {
                sendEvent("player_state_changed", data: status, to: conn)
            }
            Task {
                let queue = await MusicBridge.shared.getPlaybackQueue()
                for conn in conns {
                    sendEvent("queue", data: queue, to: conn)
                }
            }
        }
    }

    public func pushDeviceRemoved(for record: ClientDeviceRecord) {
        let connIds = ClientDeviceManager.shared.getConnectionIds(forDeviceId: record.deviceId)
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
        if let json = try? JSONSerialization.data(withJSONObject: envelope),
           let text = String(data: json, encoding: .utf8) {
            broadcastText(text)
        }
    }

    public func sendText(_ text: String, to connection: NWConnection) {
        guard let data = text.data(using: .utf8) else { return }
        let frame = makeWebSocketFrame(payload: data, opcode: 0x01)
        sendLock.lock()
        defer { sendLock.unlock() }
        connection.send(content: frame, completion: .contentProcessed({ error in
            if let err = error {
                NSLog("[WebSocket] sendText error: %@", err.localizedDescription)
            }
        }))
    }

    public func sendBinary(_ data: Data, to connection: NWConnection) {
        let frame = makeWebSocketFrame(payload: data, opcode: 0x02)
        sendLock.lock()
        defer { sendLock.unlock() }
        connection.send(content: frame, completion: .contentProcessed({ _ in }))
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
        var devices = CoreAudioDeviceManager.shared.getOutputDevices().map { dev -> [String: Any] in
            var dict = dev.dictionary
            if isDLNAActive {
                dict["isDefault"] = false
            }
            return dict
        }
        if DLNADiscoveryManager.shared.isEnabled {
            devices.append(contentsOf: DLNADiscoveryManager.shared.getDiscoveredDevices())
        }
        var data: [String: Any] = ["devices": devices]
        if let activeDLNA = DLNADiscoveryManager.shared.getActiveRenderer() {
            data["current_device"] = activeDLNA.dictionary
        } else if let defaultDev = CoreAudioDeviceManager.shared.getDefaultOutputDevice()?.dictionary {
            data["current_device"] = defaultDev
        }
        broadcastEvent(name: "audio_devices", data: data)
    }
}
