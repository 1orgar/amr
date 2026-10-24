//
//  SSDPService.swift
//  AppleMusicRemoteMac
//
//  Simple Service Discovery Protocol (SSDP) for UPnP / DLNA MediaRenderer
//  Listens on UDP 239.255.255.250:1900 and announces MediaRenderer to Home Assistant
//

import Foundation
import Darwin

public final class SSDPService: @unchecked Sendable {
    public static let shared = SSDPService()

    private let multicastAddress = "239.255.255.250"
    private let multicastPort: UInt16 = 1900
    private var socketFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "org.ksholokhov.amr.upnp.ssdp", qos: .utility)
    private var announceTimer: DispatchSourceTimer?

    public var httpPort: UInt16 = 8090

    public private(set) lazy var deviceUUID: String = {
        if let existing = UserDefaults.standard.string(forKey: "AMRUPnPDeviceUUID") {
            return existing
        }
        let generated = UUID().uuidString.lowercased()
        UserDefaults.standard.set(generated, forKey: "AMRUPnPDeviceUUID")
        return generated
    }()

    public var deviceUDN: String {
        return "uuid:\(deviceUUID)"
    }

    public var friendlyName: String {
        get {
            let saved = UserDefaults.standard.string(forKey: "UPnPFriendlyName")?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let saved = saved, !saved.isEmpty {
                return saved
            }
            return "Apple Music Remote (Mac)"
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let val = trimmed.isEmpty ? "Apple Music Remote (Mac)" : trimmed
            UserDefaults.standard.set(val, forKey: "UPnPFriendlyName")
        }
    }

    private init() {}

    deinit {
        stop()
    }

    public func start(httpPort: UInt16 = 8090) {
        self.httpPort = httpPort
        queue.async { [weak self] in
            self?.startInternal()
        }
    }

    public func restart() {
        queue.async { [weak self] in
            guard let self = self else { return }
            NSLog("[SSDPService] 🔄 Restarting SSDP Service...")
            self.stopInternal()
            self.startInternal()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.stopInternal()
        }
    }

    private func startInternal() {
        stopInternal()

        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            NSLog("[SSDPService] ❌ Failed to create UDP socket: %d", errno)
            return
        }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // Bind to 0.0.0.0:1900
        var bindAddr = sockaddr_in()
        bindAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_port = in_port_t(multicastPort).bigEndian
        bindAddr.sin_addr.s_addr = in_addr_t(INADDR_ANY)

        let bindRes = withUnsafePointer(to: &bindAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindRes == 0 else {
            NSLog("[SSDPService] ❌ Failed to bind SSDP socket on port 1900: %d", errno)
            close(fd)
            return
        }

        // Join multicast group 239.255.255.250 on INADDR_ANY and all active LAN interfaces
        var mreqAny = ip_mreq()
        mreqAny.imr_multiaddr.s_addr = inet_addr(multicastAddress)
        mreqAny.imr_interface.s_addr = in_addr_t(INADDR_ANY)
        _ = setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreqAny, socklen_t(MemoryLayout<ip_mreq>.size))

        let lanIPs = WebSocketServer.shared.getLANIPAddresses()
        for ip in lanIPs {
            var mreq = ip_mreq()
            mreq.imr_multiaddr.s_addr = inet_addr(multicastAddress)
            mreq.imr_interface.s_addr = inet_addr(ip)
            _ = setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreq, socklen_t(MemoryLayout<ip_mreq>.size))
        }

        // Enable multicast loopback so local consumers (Home Assistant, tests) receive multicasts
        var loop: u_char = 1
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_LOOP, &loop, socklen_t(MemoryLayout<u_char>.size))

        // Set TTL to 4 for local subnet traversal
        var ttl: u_char = 4
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<u_char>.size))

        // Set default outbound multicast interface if LAN IP available
        if let primaryIP = lanIPs.first {
            var ifAddr = in_addr()
            ifAddr.s_addr = inet_addr(primaryIP)
            setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &ifAddr, socklen_t(MemoryLayout<in_addr>.size))
        }

        // Make socket non-blocking so we can drain all packets cleanly
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        self.socketFD = fd

        // Dispatch source for async packet reading
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readPackets()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.readSource = source

        NSLog("[SSDPService] 📡 SSDP Multicast Listener active on 239.255.255.250:1900 (UDN: %@)", deviceUDN)

        // Broadcast initial alive notification
        sendAliveNotifications()

        // Setup repeating announcement every 60 seconds for reliable discovery without LAN noise (CACHE-CONTROL: max-age=1800)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2.0, repeating: 60.0)
        timer.setEventHandler { [weak self] in
            self?.sendAliveNotifications()
        }
        timer.resume()
        self.announceTimer = timer
    }

    private func stopInternal() {
        sendByebyeNotifications()

        announceTimer?.cancel()
        announceTimer = nil

        if let src = readSource {
            src.cancel()
            readSource = nil
        } else if socketFD >= 0 {
            close(socketFD)
        }
        socketFD = -1
    }

    // MARK: - Incoming Packet Handler

    private func readPackets() {
        guard socketFD >= 0 else { return }

        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            var clientAddr = sockaddr_in()
            var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

            let bytesRead = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(socketFD, &buffer, buffer.count, 0, $0, &addrLen)
                }
            }

            guard bytesRead > 0 else { break }

            if let packetString = String(bytes: buffer.prefix(bytesRead), encoding: .utf8) {
                if packetString.hasPrefix("M-SEARCH") {
                    handleMSearch(packetString, clientAddr: clientAddr)
                }
            }
        }
    }

    public func matchingTargets(for searchTarget: String) -> [String] {
        let supportedTargets: [String] = [
            "ssdp:all",
            "upnp:rootdevice",
            "urn:schemas-upnp-org:device:MediaRenderer:1",
            "urn:schemas-upnp-org:service:AVTransport:1",
            "urn:schemas-upnp-org:service:RenderingControl:1",
            "urn:schemas-upnp-org:service:ConnectionManager:1",
            deviceUDN
        ]

        if searchTarget == "ssdp:all" {
            return [
                "upnp:rootdevice",
                deviceUDN,
                "urn:schemas-upnp-org:device:MediaRenderer:1",
                "urn:schemas-upnp-org:service:AVTransport:1",
                "urn:schemas-upnp-org:service:RenderingControl:1",
                "urn:schemas-upnp-org:service:ConnectionManager:1"
            ]
        } else if supportedTargets.contains(searchTarget) {
            return [searchTarget]
        }
        return []
    }

    public func buildMSearchResponse(target: String, lanIP: String) -> String {
        let usn: String
        if target == deviceUDN {
            usn = deviceUDN
        } else if target == "upnp:rootdevice" {
            usn = "\(deviceUDN)::upnp:rootdevice"
        } else {
            usn = "\(deviceUDN)::\(target)"
        }

        return """
        HTTP/1.1 200 OK\r
        CACHE-CONTROL: max-age=1800\r
        DATE: \(httpDate())\r
        EXT:\r
        LOCATION: http://\(lanIP):\(httpPort)/description.xml\r
        SERVER: macOS/14.0 UPnP/1.0 AppleMusicRemote/2.0\r
        ST: \(target)\r
        USN: \(usn)\r
        BOOTID.UPNP.ORG: 1\r
        CONFIGID.UPNP.ORG: 2\r
        \r\n
        """
    }

    private func handleMSearch(_ request: String, clientAddr: sockaddr_in) {
        let lines = request.components(separatedBy: "\r\n")
        var headers: [String: String] = [:]
        for line in lines {
            if let colonIdx = line.firstIndex(of: ":") {
                let key = line[..<colonIdx].trimmingCharacters(in: .whitespaces).uppercased()
                let val = line[line.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
                headers[key] = val
            }
        }

        guard let st = headers["ST"] else { return }

        let targetsToRespond = matchingTargets(for: st)
        guard !targetsToRespond.isEmpty else { return }

        // Find primary LAN IP
        let lanIP = getLANIP()

        for target in targetsToRespond {
            let response = buildMSearchResponse(target: target, lanIP: lanIP)

            sendUDPResponse(response, to: clientAddr)
        }
    }

    private func sendUDPResponse(_ message: String, to clientAddr: sockaddr_in) {
        guard socketFD >= 0, let data = message.data(using: .utf8) else { return }

        var target = clientAddr
        _ = data.withUnsafeBytes { rawPtr in
            withUnsafePointer(to: &target) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(socketFD, rawPtr.baseAddress, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    // MARK: - SSDP NOTIFY (alive / byebye)

    public func sendAliveNotifications() {
        sendNotifications(subType: "ssdp:alive")
    }

    public func sendByebyeNotifications() {
        sendNotifications(subType: "ssdp:byebye")
    }

    private func sendNotifications(subType: String) {
        guard socketFD >= 0 else { return }

        let lanIP = getLANIP()

        // Keep outbound multicast interface aligned with active LAN IP
        var ifAddr = in_addr()
        ifAddr.s_addr = inet_addr(lanIP)
        setsockopt(socketFD, IPPROTO_IP, IP_MULTICAST_IF, &ifAddr, socklen_t(MemoryLayout<in_addr>.size))

        let targets = [
            "upnp:rootdevice",
            deviceUDN,
            "urn:schemas-upnp-org:device:MediaRenderer:1",
            "urn:schemas-upnp-org:service:AVTransport:1",
            "urn:schemas-upnp-org:service:RenderingControl:1",
            "urn:schemas-upnp-org:service:ConnectionManager:1"
        ]

        var multiAddr = sockaddr_in()
        multiAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        multiAddr.sin_family = sa_family_t(AF_INET)
        multiAddr.sin_port = in_port_t(multicastPort).bigEndian
        multiAddr.sin_addr.s_addr = inet_addr(multicastAddress)

        for target in targets {
            let usn = (target == deviceUDN) ? deviceUDN : "\(deviceUDN)::\(target)"
            let notify = """
            NOTIFY * HTTP/1.1\r
            HOST: \(multicastAddress):\(multicastPort)\r
            CACHE-CONTROL: max-age=1800\r
            LOCATION: http://\(lanIP):\(httpPort)/description.xml\r
            NT: \(target)\r
            NTS: \(subType)\r
            SERVER: macOS/14.0 UPnP/1.0 AppleMusicRemote/2.0\r
            USN: \(usn)\r
            BOOTID.UPNP.ORG: 1\r
            CONFIGID.UPNP.ORG: 2\r
            \r\n
            """

            guard let data = notify.data(using: .utf8) else { continue }
            _ = data.withUnsafeBytes { rawPtr in
                withUnsafePointer(to: &multiAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(socketFD, rawPtr.baseAddress, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }
    }

    // MARK: - Utilities

    private func getLANIP() -> String {
        let ips = WebSocketServer.shared.getLANIPAddresses()
        return ips.first ?? "127.0.0.1"
    }

    private func httpDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(abbreviation: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: Date())
    }
}
