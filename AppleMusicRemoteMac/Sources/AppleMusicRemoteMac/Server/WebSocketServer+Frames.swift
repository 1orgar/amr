//
//  WebSocketServer+Frames.swift
//  AppleMusicRemoteMac
//
//  RFC 6455 WebSocket framing, client mask enforcement, Host/Origin validation,
//  per-client FIFO action queue, and LAN IP detection.
//

import CryptoKit
import Darwin
import Foundation
import Network

extension WebSocketServer {
    // MARK: - Per-Client Bounded FIFO Message Queue

    internal func enqueueClientTextMessage(_ text: String, clientId: UUID, connection: NWConnection) {
        clientQueueLock.lock()
        let queuedCount = clientMessageQueues[clientId]?.count ?? 0
        if queuedCount >= Self.maxQueuedClientMessages {
            clientQueueLock.unlock()
            NSLog("[WebSocket] ⚠️ Dropping message from client %@: queue full (%d)", clientId.uuidString, queuedCount)
            return
        }
        clientMessageQueues[clientId, default: []].append(text)
        if activeClientWorkers[clientId] == nil {
            let worker = Task { [weak self] in
                guard let self = self else { return }
                while !Task.isCancelled {
                    let nextMsg: String? = {
                        self.clientQueueLock.lock()
                        defer { self.clientQueueLock.unlock() }
                        guard var queue = self.clientMessageQueues[clientId], !queue.isEmpty else {
                            self.clientMessageQueues.removeValue(forKey: clientId)
                            self.activeClientWorkers.removeValue(forKey: clientId)
                            return nil
                        }
                        let msg = queue.removeFirst()
                        self.clientMessageQueues[clientId] = queue
                        return msg
                    }()
                    guard let msg = nextMsg else { break }
                    await self.processClientTextMessage(msg, clientId: clientId, connection: connection)
                }
            }
            activeClientWorkers[clientId] = worker
        }
        clientQueueLock.unlock()
    }

    internal func cancelClientWorker(for clientId: UUID) {
        clientQueueLock.lock()
        clientMessageQueues.removeValue(forKey: clientId)
        let worker = activeClientWorkers.removeValue(forKey: clientId)
        clientQueueLock.unlock()
        worker?.cancel()
    }

    internal func cancelAllClientWorkers() {
        clientQueueLock.lock()
        clientMessageQueues.removeAll()
        let workers = Array(activeClientWorkers.values)
        activeClientWorkers.removeAll()
        clientQueueLock.unlock()
        for worker in workers {
            worker.cancel()
        }
    }

    // MARK: - RFC 6455 Frame Reader & Decoder

    internal func sendCloseFrameAndDisconnect(code: UInt16, clientId: UUID, connection: NWConnection) {
        let payload = Data([UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)])
        let closeFrame = makeWebSocketFrame(payload: payload, opcode: 0x08)
        sendLock.lock()
        connection.send(content: closeFrame, completion: .contentProcessed({ [weak self, weak connection] _ in
            guard let self = self else { return }
            self.removeClient(clientId: clientId, connection: connection)
            connection?.cancel()
        }))
        sendLock.unlock()
    }

    internal func readWebSocketFrames(clientId: UUID, connection: NWConnection, buffer: Data) {
        var current = buffer
        var closeErrorCode: UInt16? = nil
        let frames = decodeWebSocketFrames(buffer: &current, requireMask: true, closeErrorCode: &closeErrorCode)
        if let errCode = closeErrorCode {
            NSLog("[WebSocket] ❌ Closing connection with RFC 6455 code %u", errCode)
            sendCloseFrameAndDisconnect(code: errCode, clientId: clientId, connection: connection)
            return
        }

        let connKey = ObjectIdentifier(connection)
        for (opcode, payload, fin) in frames {
            switch opcode {
            case 0x01, 0x02:
                var protocolError = false
                var sizeError = false
                clientLock.lock()
                if fragmentBuffers[connKey] != nil || clients[clientId] == nil {
                    fragmentBuffers.removeValue(forKey: connKey)
                    protocolError = true
                } else if !fin {
                    if payload.count > 16 * 1024 * 1024 {
                        sizeError = true
                    } else {
                        fragmentBuffers[connKey] = (opcode: opcode, data: payload)
                    }
                }
                clientLock.unlock()

                if protocolError || sizeError {
                    sendCloseFrameAndDisconnect(code: sizeError ? 1009 : 1002, clientId: clientId, connection: connection)
                    return
                }

                if fin {
                    if opcode == 0x01 {
                        if let text = String(data: payload, encoding: .utf8) {
                            dispatchClientTextMessage(text, clientId: clientId, connection: connection)
                        } else {
                            sendCloseFrameAndDisconnect(code: 1007, clientId: clientId, connection: connection)
                            return
                        }
                    } else {
                        Task {
                            await self.processClientBinaryMessage(payload, clientId: clientId, connection: connection)
                        }
                    }
                }

            case 0x00:
                var completedMessage: (opcode: UInt8, data: Data)? = nil
                var protocolError = false
                var sizeError = false
                clientLock.lock()
                if clients[clientId] != nil, var existing = fragmentBuffers[connKey] {
                    if existing.data.count + payload.count > 16 * 1024 * 1024 {
                        fragmentBuffers.removeValue(forKey: connKey)
                        sizeError = true
                    } else {
                        existing.data.append(payload)
                        if fin {
                            fragmentBuffers.removeValue(forKey: connKey)
                            completedMessage = existing
                        } else {
                            fragmentBuffers[connKey] = existing
                        }
                    }
                } else {
                    fragmentBuffers.removeValue(forKey: connKey)
                    protocolError = true
                }
                clientLock.unlock()

                if protocolError || sizeError {
                    sendCloseFrameAndDisconnect(code: sizeError ? 1009 : 1002, clientId: clientId, connection: connection)
                    return
                }
                if let msg = completedMessage {
                    if msg.opcode == 0x01 {
                        if let text = String(data: msg.data, encoding: .utf8) {
                            dispatchClientTextMessage(text, clientId: clientId, connection: connection)
                        } else {
                            sendCloseFrameAndDisconnect(code: 1007, clientId: clientId, connection: connection)
                            return
                        }
                    } else if msg.opcode == 0x02 {
                        Task {
                            await self.processClientBinaryMessage(msg.data, clientId: clientId, connection: connection)
                        }
                    }
                }

            case 0x08:
                removeClient(clientId: clientId, connection: connection)
                return

            case 0x09:
                let pong = makeWebSocketFrame(payload: payload, opcode: 0x0A)
                sendLock.lock()
                connection.send(content: pong, completion: .contentProcessed({ _ in }))
                sendLock.unlock()

            case 0x0A:
                break

            default:
                sendCloseFrameAndDisconnect(code: 1002, clientId: clientId, connection: connection)
                return
            }
        }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] content, _, isComplete, error in
            guard let self = self, let conn = connection else { return }
            if error != nil || isComplete {
                self.removeClient(clientId: clientId, connection: conn)
                return
            }
            var next = current
            if let data = content {
                next.append(data)
            }
            if next.count > 16 * 1024 * 1024 + 65536 {
                self.sendCloseFrameAndDisconnect(code: 1009, clientId: clientId, connection: conn)
                return
            }
            self.readWebSocketFrames(clientId: clientId, connection: conn, buffer: next)
        }
    }

    internal func decodeWebSocketFrames(buffer: inout Data, requireMask: Bool = false) -> [(opcode: UInt8, payload: Data, fin: Bool)] {
        var errCode: UInt16? = nil
        return decodeWebSocketFrames(buffer: &buffer, requireMask: requireMask, closeErrorCode: &errCode)
    }

    internal func decodeWebSocketFrames(
        buffer: inout Data,
        requireMask: Bool = false,
        closeErrorCode: inout UInt16?
    ) -> [(opcode: UInt8, payload: Data, fin: Bool)] {
        var results: [(opcode: UInt8, payload: Data, fin: Bool)] = []
        while buffer.count >= 2 {
            let b0 = buffer[buffer.startIndex]
            let fin = (b0 & 0x80) != 0
            let rsv = (b0 & 0x70)
            let opcode = b0 & 0x0F
            let b1 = buffer[buffer.startIndex + 1]
            let isMasked = (b1 & 0x80) != 0
            var payloadLen = UInt64(b1 & 0x7F)
            var offset = 2

            if rsv != 0 {
                closeErrorCode = 1002
                buffer.removeAll()
                return []
            }

            // RFC 6455 §5.1: Server MUST close connection (1002) if client sends an unmasked frame
            if requireMask && !isMasked {
                closeErrorCode = 1002
                buffer.removeAll()
                return []
            }

            // RFC 6455 §5.5: Control frames MUST NOT be fragmented and MUST have payload <= 125 bytes
            if opcode >= 0x08 && (!fin || payloadLen > 125) {
                closeErrorCode = 1002
                buffer.removeAll()
                return []
            }

            if payloadLen == 126 {
                guard buffer.count >= offset + 2 else { break }
                let high = UInt64(buffer[buffer.startIndex + offset])
                let low = UInt64(buffer[buffer.startIndex + offset + 1])
                payloadLen = (high << 8) | low
                offset += 2
            } else if payloadLen == 127 {
                guard buffer.count >= offset + 8 else { break }
                var len: UInt64 = 0
                for i in 0..<8 {
                    len = (len << 8) | UInt64(buffer[buffer.startIndex + offset + i])
                }
                guard len <= UInt64(16 * 1024 * 1024) else {
                    closeErrorCode = 1009
                    buffer.removeAll()
                    return []
                }
                payloadLen = len
                offset += 8
            }

            var maskKey: [UInt8] = [0, 0, 0, 0]
            if isMasked {
                guard buffer.count >= offset + 4 else { break }
                maskKey = [
                    buffer[buffer.startIndex + offset],
                    buffer[buffer.startIndex + offset + 1],
                    buffer[buffer.startIndex + offset + 2],
                    buffer[buffer.startIndex + offset + 3]
                ]
                offset += 4
            }

            let totalFrameLen = offset + Int(payloadLen)
            guard buffer.count >= totalFrameLen else { break }

            let rawPayload = buffer.subdata(in: (buffer.startIndex + offset)..<(buffer.startIndex + totalFrameLen))
            buffer.removeSubrange(buffer.startIndex..<(buffer.startIndex + totalFrameLen))

            var unmasked = Data(count: rawPayload.count)
            if isMasked && !rawPayload.isEmpty {
                let count = rawPayload.count
                rawPayload.withUnsafeBytes { rawPtr in
                    unmasked.withUnsafeMutableBytes { outPtr in
                        let inBytes = rawPtr.bindMemory(to: UInt8.self).baseAddress!
                        let outBytes = outPtr.bindMemory(to: UInt8.self).baseAddress!
                        for i in 0..<count {
                            outBytes[i] = inBytes[i] ^ maskKey[i % 4]
                        }
                    }
                }
            } else {
                unmasked = rawPayload
            }

            results.append((opcode: opcode, payload: unmasked, fin: fin))
        }
        return results
    }

    internal func makeWebSocketFrame(payload: Data, opcode: UInt8) -> Data {
        var frame = Data()
        frame.append(0x80 | (opcode & 0x0F))
        let count = payload.count
        if count <= 125 {
            frame.append(UInt8(count))
        } else if count <= 65535 {
            frame.append(126)
            var len16 = UInt16(count).bigEndian
            withUnsafeBytes(of: &len16) { frame.append(contentsOf: $0) }
        } else {
            frame.append(127)
            var len64 = UInt64(count).bigEndian
            withUnsafeBytes(of: &len64) { frame.append(contentsOf: $0) }
        }
        frame.append(payload)
        return frame
    }

    internal func webSocketAccept(for key: String) -> String {
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let combined = key.trimmingCharacters(in: .whitespacesAndNewlines) + magic
        let digest = Insecure.SHA1.hash(data: Data(combined.utf8))
        return Data(digest).base64EncodedString()
    }

    // MARK: - Header, Cookie, Host & Origin Security Validation

    internal func extractRemoteIP(from connection: NWConnection) -> String {
        switch connection.endpoint {
        case .hostPort(let host, _):
            let raw = "\(host)"
            if let pct = raw.firstIndex(of: "%") {
                return String(raw[..<pct])
            }
            return raw
        default:
            return ""
        }
    }

    internal func extractHeader(named name: String, from headerString: String) -> String? {
        let lines = headerString.components(separatedBy: .newlines)
        let target = name.lowercased() + ":"
        for line in lines {
            if line.lowercased().hasPrefix(target) {
                let value = line.dropFirst(target.count)
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    internal func extractCookie(named name: String, from headerString: String) -> String? {
        guard let cookieLine = extractHeader(named: "cookie", from: headerString) else { return nil }
        let target = name.lowercased() + "="
        for part in cookieLine.components(separatedBy: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix(target) {
                return String(trimmed.dropFirst(target.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static let allowedLocalMDNSHostnames: Set<String> = {
        var names = Set<String>()
        var buf = [CChar](repeating: 0, count: Int(MAXHOSTNAMELEN))
        if Darwin.gethostname(&buf, buf.count) == 0 {
            let raw = String(cString: buf).trimmingCharacters(in: CharacterSet(charactersIn: ". \t\r\n")).lowercased()
            if !raw.isEmpty {
                if raw.hasSuffix(".local") {
                    names.insert(raw)
                } else if let firstLabel = raw.split(separator: ".").first, !firstLabel.isEmpty {
                    names.insert("\(firstLabel).local")
                }
            }
        }
        let procHost = ProcessInfo.processInfo.hostName.trimmingCharacters(in: CharacterSet(charactersIn: ". \t\r\n")).lowercased()
        if !procHost.isEmpty {
            if procHost.hasSuffix(".local") {
                names.insert(procHost)
            } else if let firstLabel = procHost.split(separator: ".").first, !firstLabel.isEmpty {
                names.insert("\(firstLabel).local")
            }
        }
        return names
    }()

    internal static func splitHostAndPort(_ rawHostHeader: String) -> (host: String, port: Int?)? {
        let trimmed = rawHostHeader.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        var hostOnly: String
        var parsedPort: Int? = nil

        if trimmed.hasPrefix("[") {
            guard let closeIdx = trimmed.firstIndex(of: "]") else { return nil }
            hostOnly = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeIdx])
            let remainder = trimmed[trimmed.index(after: closeIdx)...]
            if !remainder.isEmpty {
                guard remainder.hasPrefix(":"),
                      let p = Int(remainder.dropFirst()),
                      (1...65535).contains(p) else {
                    return nil
                }
                parsedPort = p
            }
        } else {
            let colonCount = trimmed.filter { $0 == ":" }.count
            if colonCount == 1 {
                let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
                guard parts.count == 2,
                      let p = Int(parts[1]),
                      (1...65535).contains(p) else {
                    return nil
                }
                hostOnly = String(parts[0])
                parsedPort = p
            } else {
                hostOnly = trimmed
            }
        }

        if let pct = hostOnly.firstIndex(of: "%") {
            hostOnly = String(hostOnly[..<pct])
        }
        if hostOnly.hasSuffix(".") {
            hostOnly.removeLast()
        }
        guard !hostOnly.isEmpty else { return nil }
        return (hostOnly, parsedPort)
    }

    internal func isLiteralPrivateOrLoopbackIP(_ cleanHost: String) -> Bool {
        if cleanHost == "127.0.0.1" || cleanHost == "::1" || cleanHost == "::ffff:127.0.0.1" {
            return true
        }
        let ipv4Candidate = cleanHost.hasPrefix("::ffff:") ? String(cleanHost.dropFirst("::ffff:".count)) : cleanHost
        var addr4 = in_addr()
        if inet_pton(AF_INET, ipv4Candidate, &addr4) == 1 {
            let hostOrder = UInt32(bigEndian: addr4.s_addr)
            let b0 = Int((hostOrder >> 24) & 0xFF)
            let b1 = Int((hostOrder >> 16) & 0xFF)
            let b2 = Int((hostOrder >> 8) & 0xFF)
            let b3 = Int(hostOrder & 0xFF)
            if b0 == 127 || b0 == 10 { return true }
            if b0 == 192 && b1 == 168 { return true }
            if b0 == 172 && (16...31).contains(b1) { return true }
            if b0 == 169 && b1 == 254 {
                return !(b2 == 169 && b3 == 254)
            }
            if getLANIPAddresses().contains(ipv4Candidate) {
                return true
            }
            return false
        }

        var addr6 = in6_addr()
        if inet_pton(AF_INET6, cleanHost, &addr6) == 1 {
            let bytes = withUnsafeBytes(of: &addr6) { Array($0) }
            guard bytes.count == 16 else { return false }
            let isLoopback = bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes[15] == 1
            if isLoopback { return true }
            if (bytes[0] & 0xFE) == 0xFC { return true } // fc00::/7 ULA
            if bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80 { return true } // fe80::/10 link-local
            return false
        }
        return false
    }

    /// S-01: Mandatory `Host:` header validation preventing DNS Rebinding attacks.
    public func isValidHostHeader(_ rawHostHeader: String?) -> Bool {
        guard let raw = rawHostHeader, let parsed = Self.splitHostAndPort(raw) else {
            return false
        }
        let host = parsed.host
        if host == "localhost" || Self.allowedLocalMDNSHostnames.contains(host) {
            return true
        }
        return isLiteralPrivateOrLoopbackIP(host)
    }

    internal func isPrivateOrLocalHost(_ rawHost: String) -> Bool {
        var host = rawHost
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
        if let pct = host.firstIndex(of: "%") {
            host = String(host[..<pct])
        }
        if host.hasSuffix(".") {
            host.removeLast()
        }
        guard !host.isEmpty else { return false }
        if host == "localhost" || isLiteralPrivateOrLoopbackIP(host) {
            return true
        }
        // Only single-label mDNS `.local` allowed (never `.lan` or `.home` which can leak to unicast DNS)
        if host.hasSuffix(".local") {
            let label = host.dropLast(".local".count)
            return !label.isEmpty && !label.contains(".")
        }
        return false
    }

    public func isAllowedWebSocketOrigin(_ origin: String, requestHost: String? = nil) -> Bool {
        let trimmed = origin.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty || trimmed == "null" || trimmed.hasPrefix("file://") {
            return false
        }
        if trimmed.hasPrefix("capacitor://") || trimmed.hasPrefix("ionic://") {
            return requestHost == nil || isValidHostHeader(requestHost)
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https" || scheme == "ws" || scheme == "wss"),
              let rawHost = url.host?.lowercased(),
              !rawHost.isEmpty else {
            return false
        }
        var host = rawHost.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        if let pct = host.firstIndex(of: "%") {
            host = String(host[..<pct])
        }
        guard isPrivateOrLocalHost(host) else {
            return false
        }
        if let rawReqHost = requestHost?.trimmingCharacters(in: .whitespacesAndNewlines), !rawReqHost.isEmpty {
            guard isValidHostHeader(rawReqHost), let parsedReq = Self.splitHostAndPort(rawReqHost) else {
                return false
            }
            let reqHostOnly = parsedReq.host
            let reqPort = parsedReq.port
            let defaultPort = (scheme == "https" || scheme == "wss") ? 443 : 80
            if (url.port != nil || reqPort != nil) && (url.port ?? defaultPort) != (reqPort ?? defaultPort) {
                return false
            }
            if host == reqHostOnly {
                return true
            }
            let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "::ffff:127.0.0.1"]
            if loopbackHosts.contains(host) && loopbackHosts.contains(reqHostOnly) {
                return true
            }
            return false
        }
        return true
    }

    // MARK: - IP Address Detection

    public func getLANIPAddresses() -> [String] {
        var addresses = [String]()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                let flags = Int32(ptr!.pointee.ifa_flags)
                var addr = ptr!.pointee.ifa_addr.pointee
                if (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING) {
                    if addr.sa_family == UInt8(AF_INET) {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(&addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                            let ip = String(cString: hostname)
                            if ip != "127.0.0.1" && !ip.hasPrefix("169.254") {
                                addresses.append(ip)
                            }
                        }
                    }
                }
                ptr = ptr!.pointee.ifa_next
            }
            freeifaddrs(ifaddr)
        }
        return addresses.isEmpty ? ["127.0.0.1"] : addresses
    }
}
