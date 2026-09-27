//
//  WebSocketClient.swift
//  AppleMusicRemoteIOS
//
//  Bidirectional URLSessionWebSocketTask client for real-time remote control
//

import Foundation

public protocol WebSocketClientDelegate: AnyObject, Sendable {
    func webSocketClient(_ client: WebSocketClient, didUpdateStatus payload: PlayerStatusPayload)
    func webSocketClient(_ client: WebSocketClient, didUpdateQueue payload: QueuePayload)
    func webSocketClient(_ client: WebSocketClient, didReceiveEvent name: String, data: [String: Any])
    func webSocketClient(_ client: WebSocketClient, didChangeConnectionState connected: Bool)
}

public final class WebSocketClient: @unchecked Sendable {
    public static let shared = WebSocketClient()

    public weak var delegate: WebSocketClientDelegate?

    public private(set) var isConnected: Bool = false
    public private(set) var host: String = ""
    public private(set) var port: Int = 8080

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession
    private var pingTimer: Timer?
    private var reconnectTimer: Timer?
    private var isManualDisconnect = false

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 86400 * 7
        self.session = URLSession(configuration: config)
    }

    public func connect(host: String, port: Int = 8080) {
        if isConnected && self.host == host && self.port == port { return }
        if let currentTask = webSocketTask, (currentTask.state == .running || currentTask.state == .suspended), self.host == host, self.port == port {
            return
        }

        stopPingTimer()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil

        self.host = host
        self.port = port
        self.isManualDisconnect = false

        guard let url = URL(string: "ws://\(host):\(port)") else {
            NSLog("[WebSocketClient] Invalid URL: ws://\(host):\(port)")
            return
        }

        NSLog("[WebSocketClient] Connecting to \(url)...")
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = 32 * 1024 * 1024
        self.webSocketTask = task
        task.resume()

        receiveNextMessage()
        startPingTimer()
        sendCommand("get_status")
    }

    public func disconnect() {
        isManualDisconnect = true
        stopPingTimer()
        reconnectTimer?.invalidate()
        reconnectTimer = nil

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil

        if isConnected {
            isConnected = false
            DispatchQueue.main.async {
                self.delegate?.webSocketClient(self, didChangeConnectionState: false)
            }
        }
    }

    // MARK: - Sending Messages

    public func sendCommand(_ action: String, payload: [String: Any] = [:]) {
        var messageDict: [String: Any] = ["action": action]
        for (k, v) in payload {
            messageDict[k] = v
        }

        guard let data = try? JSONSerialization.data(withJSONObject: messageDict),
              let jsonStr = String(data: data, encoding: .utf8) else {
            return
        }

        let message = URLSessionWebSocketTask.Message.string(jsonStr)
        NSLog("[WebSocketClient] sendCommand: %@ payload: %@", action, jsonStr)
        webSocketTask?.send(message) { error in
            if let error = error {
                NSLog("[WebSocketClient] Send error for action \(action): \(error)")
            }
        }
    }

    // MARK: - Receiving Messages

    private func receiveNextMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                if !self.isConnected {
                    self.isConnected = true
                    DispatchQueue.main.async {
                        self.reconnectTimer?.invalidate()
                        self.reconnectTimer = nil
                        self.delegate?.webSocketClient(self, didChangeConnectionState: true)
                    }
                    self.sendCommand("get_status")
                }

                switch message {
                case .string(let text):
                    self.handleIncomingText(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleIncomingText(text)
                    }
                @unknown default:
                    break
                }

                self.receiveNextMessage()

            case .failure(let error):
                NSLog("[WebSocketClient] Receive failed: \(error)")
                self.handleDisconnect()
            }
        }
    }

    private func handleIncomingText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let event = (json["event"] as? String) ?? (json["action"] as? String) ?? (json["type"] as? String) ?? ""

        struct StatusEnvelope: Decodable {
            let data: PlayerStatusPayload?
        }
        struct QueueEnvelope: Decodable {
            let data: QueuePayload?
        }

        if event == "status" || event == "initial_state" || event == "player_state_changed" {
            if let env = try? JSONDecoder().decode(StatusEnvelope.self, from: data), let payload = env.data {
                DispatchQueue.main.async {
                    self.delegate?.webSocketClient(self, didUpdateStatus: payload)
                }
            } else if let payloadDict = json["data"] as? [String: Any],
                      let pData = try? JSONSerialization.data(withJSONObject: payloadDict),
                      let payload = try? JSONDecoder().decode(PlayerStatusPayload.self, from: pData) {
                DispatchQueue.main.async {
                    self.delegate?.webSocketClient(self, didUpdateStatus: payload)
                }
            }
        } else if event == "queue" || event == "get_queue" || event == "queue_changed" || event == "queue_updated" {
            if let env = try? JSONDecoder().decode(QueueEnvelope.self, from: data), let payload = env.data {
                DispatchQueue.main.async {
                    self.delegate?.webSocketClient(self, didUpdateQueue: payload)
                }
            } else if let payloadDict = json["data"] as? [String: Any],
                      let pData = try? JSONSerialization.data(withJSONObject: payloadDict),
                      let payload = try? JSONDecoder().decode(QueuePayload.self, from: pData) {
                DispatchQueue.main.async {
                    self.delegate?.webSocketClient(self, didUpdateQueue: payload)
                }
            } else if let directPayload = try? JSONDecoder().decode(QueuePayload.self, from: data) {
                DispatchQueue.main.async {
                    self.delegate?.webSocketClient(self, didUpdateQueue: directPayload)
                }
            } else {
                NSLog("[WebSocketClient] Failed to decode queue payload for event: %@", event)
            }
        } else {
            let eventData = json["data"] as? [String: Any] ?? json
            DispatchQueue.main.async {
                self.delegate?.webSocketClient(self, didReceiveEvent: event, data: eventData)
            }
        }
    }

    // MARK: - Heartbeat & Reconnection

    private func startPingTimer() {
        stopPingTimer()
        DispatchQueue.main.async {
            let timer = Timer(timeInterval: 10.0, repeats: true) { [weak self] _ in
                guard let self = self, self.isConnected, let task = self.webSocketTask else { return }
                task.sendPing { error in
                    if let error = error {
                        NSLog("[WebSocketClient] Ping warning: %@", error.localizedDescription)
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.pingTimer = timer
        }
    }

    private func stopPingTimer() {
        DispatchQueue.main.async {
            self.pingTimer?.invalidate()
            self.pingTimer = nil
        }
    }

    private func handleDisconnect() {
        stopPingTimer()
        webSocketTask = nil

        if isConnected {
            isConnected = false
            DispatchQueue.main.async {
                self.delegate?.webSocketClient(self, didChangeConnectionState: false)
            }
        }

        if !isManualDisconnect && !host.isEmpty {
            DispatchQueue.main.async {
                self.reconnectTimer?.invalidate()
                let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] t in
                    guard let self = self else {
                        t.invalidate()
                        return
                    }
                    if self.isManualDisconnect || self.isConnected {
                        t.invalidate()
                        self.reconnectTimer = nil
                        return
                    }
                    NSLog("[WebSocketClient] Auto-reconnecting to \(self.host):\(self.port)...")
                    self.connect(host: self.host, port: self.port)
                }
                RunLoop.main.add(timer, forMode: .common)
                self.reconnectTimer = timer
            }
        }
    }
}
