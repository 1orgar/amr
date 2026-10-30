//
//  MockDLNARendererServer.swift
//  MockDLNARenderer
//
//  Lightweight standalone mock DLNA MediaRenderer server emulating a Bluesound NODE NANO streamer
//

import Foundation
import Network
import Darwin

public final class MockDLNARendererServer: @unchecked Sendable {
    public static let shared = MockDLNARendererServer()

    private var listener: NWListener?
    private var ssdpSocketFD: Int32 = -1
    private var ssdpReadSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "org.ksholokhov.amr.mock.dlna", qos: .utility)
    private let lock = NSLock()

    public private(set) var isRunning: Bool = false
    public private(set) var port: UInt16 = 8095

    public let friendlyName: String = "Bluesound NODE NANO (Mock)"
    public let manufacturer: String = "Bluesound"
    public let modelName: String = "NODE NANO"
    public let udn: String = "uuid:mock-bluesound-node-nano-8095"

    // Mock playback state
    public var currentTransportState: String = "STOPPED" // "STOPPED", "PLAYING", "PAUSED_PLAYBACK"
    public var currentURI: String = ""

    public init() {}

    deinit {
        stop()
    }

    @discardableResult
    public func start(preferredPort: UInt16 = 8095) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if isRunning { return true }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            let nwPort = NWEndpoint.Port(rawValue: preferredPort) ?? .any
            let listener = try NWListener(using: parameters, on: nwPort)

            listener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    let assignedPort = listener.port?.rawValue ?? preferredPort
                    self.lock.lock()
                    self.port = assignedPort
                    self.isRunning = true
                    self.lock.unlock()
                    NSLog("[MockDLNARenderer] ✅ Mock DLNA Renderer listening on port %u (Model: %@)", assignedPort, self.modelName)
                    self.sendSSDPAlive()
                case .failed(let error):
                    NSLog("[MockDLNARenderer] ❌ Listener failed: %@", error.localizedDescription)
                    self.stop()
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            self.listener = listener
            listener.start(queue: queue)
            self.isRunning = true
            self.port = preferredPort

            setupSSDPListener()
            return true
        } catch {
            NSLog("[MockDLNARenderer] ❌ Failed to start listener: %@", error.localizedDescription)
            return false
        }
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        if let l = listener {
            l.cancel()
            listener = nil
        }
        if let source = ssdpReadSource {
            source.cancel()
            ssdpReadSource = nil
        } else if ssdpSocketFD >= 0 {
            close(ssdpSocketFD)
        }
        ssdpSocketFD = -1
        isRunning = false
        NSLog("[MockDLNARenderer] ⏹ Mock DLNA Renderer stopped")
    }

    // MARK: - SSDP M-SEARCH Responder

    private func setupSSDPListener() {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            NSLog("[MockDLNARenderer] ⚠️ Failed to create SSDP UDP socket: %d", errno)
            return
        }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var bindAddr = sockaddr_in()
        bindAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_port = in_port_t(1900).bigEndian
        bindAddr.sin_addr.s_addr = in_addr_t(INADDR_ANY)

        let bindRes = withUnsafePointer(to: &bindAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindRes >= 0 else {
            NSLog("[MockDLNARenderer] ⚠️ Failed to bind SSDP socket on 1900: %d", errno)
            close(fd)
            return
        }

        var loop: u_char = 1
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_LOOP, &loop, socklen_t(MemoryLayout<u_char>.size))

        var allIPs = getLANIPAddresses()
        if !allIPs.contains("127.0.0.1") { allIPs.append("127.0.0.1") }
        for ip in allIPs {
            var mreq = ip_mreq()
            mreq.imr_multiaddr.s_addr = inet_addr("239.255.255.250")
            mreq.imr_interface.s_addr = inet_addr(ip)
            _ = setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreq, socklen_t(MemoryLayout<ip_mreq>.size))
        }

        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        self.ssdpSocketFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readSSDPPackets()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.ssdpReadSource = source
    }

    private func readSSDPPackets() {
        guard ssdpSocketFD >= 0 else { return }

        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            var clientAddr = sockaddr_in()
            var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

            let bytesRead = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(ssdpSocketFD, &buffer, buffer.count, 0, $0, &addrLen)
                }
            }

            guard bytesRead > 0 else { break }

            if let packetString = String(bytes: buffer.prefix(bytesRead), encoding: .utf8),
               packetString.hasPrefix("M-SEARCH") {
                handleMSearch(packetString, clientAddr: clientAddr)
            }
        }
    }

    private func handleMSearch(_ text: String, clientAddr: sockaddr_in) {
        let targets = [
            "ssdp:all",
            "urn:schemas-upnp-org:device:MediaRenderer:1",
            "urn:schemas-upnp-org:service:AVTransport:1",
            udn
        ]
        var matched = false
        for target in targets {
            if text.contains(target) {
                matched = true
                break
            }
        }
        guard matched else { return }

        let lanIP = getLANIPAddresses().first ?? "127.0.0.1"
        let location = "http://\(lanIP):\(port)/mock/description.xml"
        let response = [
            "HTTP/1.1 200 OK",
            "CACHE-CONTROL: max-age=1800",
            "LOCATION: \(location)",
            "ST: urn:schemas-upnp-org:device:MediaRenderer:1",
            "USN: \(udn)::urn:schemas-upnp-org:device:MediaRenderer:1",
            "SERVER: Linux/4.19 UPnP/1.0 BluOS/4.6.0",
            "EXT:",
            "",
            ""
        ].joined(separator: "\r\n")

        var replyAddr = clientAddr
        let data = Array(response.utf8)
        _ = withUnsafePointer(to: &replyAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(ssdpSocketFD, data, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    public func sendSSDPAlive() {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }

        var loop: u_char = 1
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_LOOP, &loop, socklen_t(MemoryLayout<u_char>.size))

        var destAddr = sockaddr_in()
        destAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destAddr.sin_family = sa_family_t(AF_INET)
        destAddr.sin_port = in_port_t(1900).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &destAddr.sin_addr)

        let lanIP = getLANIPAddresses().first ?? "127.0.0.1"
        let location = "http://\(lanIP):\(port)/mock/description.xml"

        let notify = [
            "NOTIFY * HTTP/1.1",
            "HOST: 239.255.255.250:1900",
            "CACHE-CONTROL: max-age=1800",
            "LOCATION: \(location)",
            "NT: urn:schemas-upnp-org:device:MediaRenderer:1",
            "NTS: ssdp:alive",
            "SERVER: Linux/4.19 UPnP/1.0 BluOS/4.6.0",
            "USN: \(udn)::urn:schemas-upnp-org:device:MediaRenderer:1",
            "",
            ""
        ].joined(separator: "\r\n")

        let data = Array(notify.utf8)
        _ = withUnsafePointer(to: &destAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(fd, data, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    // MARK: - HTTP Request Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveNext(connection: connection, buffer: Data())
    }

    private func receiveNext(connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] data, _, isComplete, error in
            guard let self = self, let connection = connection else { return }

            if error != nil {
                connection.cancel()
                return
            }

            var currentBuffer = buffer
            if let data = data, !data.isEmpty {
                currentBuffer.append(data)
            }

            if let requestString = String(data: currentBuffer, encoding: .utf8),
               requestString.contains("\r\n\r\n") {
                self.processHTTPRequest(requestString, rawData: currentBuffer, connection: connection)
            } else if !isComplete {
                self.receiveNext(connection: connection, buffer: currentBuffer)
            } else {
                connection.cancel()
            }
        }
    }

    private func processHTTPRequest(_ request: String, rawData: Data, connection: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, status: "400 Bad Request", contentType: "text/plain", body: "Bad Request")
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: "400 Bad Request", contentType: "text/plain", body: "Bad Request")
            return
        }

        _ = String(parts[0])
        let path = String(parts[1])

        switch path {
        case "/mock/description.xml":
            sendResponse(connection: connection, status: "200 OK", contentType: "text/xml; charset=\"utf-8\"", body: deviceDescriptionXML)
        case "/mock/AVTransport/scpd.xml":
            sendResponse(connection: connection, status: "200 OK", contentType: "text/xml; charset=\"utf-8\"", body: avTransportSCPDXML)
        case "/mock/RenderingControl/scpd.xml":
            sendResponse(connection: connection, status: "200 OK", contentType: "text/xml; charset=\"utf-8\"", body: renderingControlSCPDXML)
        case "/mock/AVTransport/control":
            handleAVTransportSOAP(request: request, connection: connection)
        case "/mock/RenderingControl/control":
            handleRenderingControlSOAP(request: request, connection: connection)
        default:
            sendResponse(connection: connection, status: "404 Not Found", contentType: "text/plain", body: "Not Found")
        }
    }

    private func handleAVTransportSOAP(request: String, connection: NWConnection) {
        if request.contains("SetAVTransportURI") {
            if let uriMatch = extractTagValue(tag: "CurrentURI", from: request) {
                currentURI = uriMatch
                NSLog("[MockDLNARenderer] 🎵 SetAVTransportURI: %@", uriMatch)
            }
            let resp = makeSOAPResponse(action: "SetAVTransportURI", serviceType: "urn:schemas-upnp-org:service:AVTransport:1", bodyContent: "")
            sendResponse(connection: connection, status: "200 OK", contentType: "text/xml; charset=\"utf-8\"", body: resp)
        } else if request.contains("Play") {
            currentTransportState = "PLAYING"
            NSLog("[MockDLNARenderer] ▶️ Play requested. State: PLAYING")
            let resp = makeSOAPResponse(action: "Play", serviceType: "urn:schemas-upnp-org:service:AVTransport:1", bodyContent: "")
            sendResponse(connection: connection, status: "200 OK", contentType: "text/xml; charset=\"utf-8\"", body: resp)
        } else if request.contains("Pause") {
            currentTransportState = "PAUSED_PLAYBACK"
            NSLog("[MockDLNARenderer] ⏸ Pause requested. State: PAUSED_PLAYBACK")
            let resp = makeSOAPResponse(action: "Pause", serviceType: "urn:schemas-upnp-org:service:AVTransport:1", bodyContent: "")
            sendResponse(connection: connection, status: "200 OK", contentType: "text/xml; charset=\"utf-8\"", body: resp)
        } else if request.contains("Stop") {
            currentTransportState = "STOPPED"
            NSLog("[MockDLNARenderer] ⏹ Stop requested. State: STOPPED")
            let resp = makeSOAPResponse(action: "Stop", serviceType: "urn:schemas-upnp-org:service:AVTransport:1", bodyContent: "")
            sendResponse(connection: connection, status: "200 OK", contentType: "text/xml; charset=\"utf-8\"", body: resp)
        } else if request.contains("GetTransportInfo") {
            let body = """
            <CurrentTransportState>\(currentTransportState)</CurrentTransportState>
            <CurrentTransportStatus>OK</CurrentTransportStatus>
            <CurrentSpeed>1</CurrentSpeed>
            """
            let resp = makeSOAPResponse(action: "GetTransportInfo", serviceType: "urn:schemas-upnp-org:service:AVTransport:1", bodyContent: body)
            sendResponse(connection: connection, status: "200 OK", contentType: "text/xml; charset=\"utf-8\"", body: resp)
        } else if request.contains("GetPositionInfo") {
            let body = """
            <Track>1</Track>
            <TrackDuration>00:03:45</TrackDuration>
            <TrackMetaData></TrackMetaData>
            <TrackURI>\(currentURI)</TrackURI>
            <RelTime>00:01:15</RelTime>
            <AbsTime>00:01:15</RelTime>
            <RelCount>2147483647</RelCount>
            <AbsCount>2147483647</AbsCount>
            """
            let resp = makeSOAPResponse(action: "GetPositionInfo", serviceType: "urn:schemas-upnp-org:service:AVTransport:1", bodyContent: body)
            sendResponse(connection: connection, status: "200 OK", contentType: "text/xml; charset=\"utf-8\"", body: resp)
        } else {
            let resp = makeSOAPResponse(action: "UnknownAction", serviceType: "urn:schemas-upnp-org:service:AVTransport:1", bodyContent: "")
            sendResponse(connection: connection, status: "200 OK", contentType: "text/xml; charset=\"utf-8\"", body: resp)
        }
    }

    private func handleRenderingControlSOAP(request: String, connection: NWConnection) {
        if request.contains("GetVolume") {
            let body = "<CurrentVolume>85</CurrentVolume>"
            let resp = makeSOAPResponse(action: "GetVolume", serviceType: "urn:schemas-upnp-org:service:RenderingControl:1", bodyContent: body)
            sendResponse(connection: connection, status: "200 OK", contentType: "text/xml; charset=\"utf-8\"", body: resp)
        } else if request.contains("SetVolume") {
            let resp = makeSOAPResponse(action: "SetVolume", serviceType: "urn:schemas-upnp-org:service:RenderingControl:1", bodyContent: "")
            sendResponse(connection: connection, status: "200 OK", contentType: "text/xml; charset=\"utf-8\"", body: resp)
        } else {
            let resp = makeSOAPResponse(action: "UnknownAction", serviceType: "urn:schemas-upnp-org:service:RenderingControl:1", bodyContent: "")
            sendResponse(connection: connection, status: "200 OK", contentType: "text/xml; charset=\"utf-8\"", body: resp)
        }
    }

    private func sendResponse(connection: NWConnection, status: String, contentType: String, body: String) {
        let bodyData = Data(body.utf8)
        let header = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(bodyData.count)",
            "Server: Linux/4.19 UPnP/1.0 BluOS/4.6.0",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")

        var fullData = Data(header.utf8)
        fullData.append(bodyData)

        connection.send(content: fullData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func makeSOAPResponse(action: String, serviceType: String, bodyContent: String) -> String {
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:\(action)Response xmlns:u="\(serviceType)">
              \(bodyContent)
            </u:\(action)Response>
          </s:Body>
        </s:Envelope>
        """
    }

    private func extractTagValue(tag: String, from xml: String) -> String? {
        let pattern = "<\(tag)[^>]*>([^<]*)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsText = xml as NSString
        guard let match = regex.firstMatch(in: xml, options: [], range: NSRange(location: 0, length: nsText.length)) else { return nil }
        return nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func getLANIPAddresses() -> [String] {
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

    // MARK: - XML Templates

    public var deviceDescriptionXML: String {
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <root xmlns="urn:schemas-upnp-org:device-1-0">
          <specVersion>
            <major>1</major>
            <minor>0</minor>
          </specVersion>
          <device>
            <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
            <friendlyName>\(friendlyName)</friendlyName>
            <manufacturer>\(manufacturer)</manufacturer>
            <manufacturerURL>https://www.bluesound.com</manufacturerURL>
            <modelDescription>Bluesound NODE NANO Wireless Music Streamer</modelDescription>
            <modelName>\(modelName)</modelName>
            <modelNumber>N030</modelNumber>
            <modelURL>https://www.bluesound.com/products/node-nano/</modelURL>
            <serialNumber>001122334455</serialNumber>
            <UDN>\(udn)</UDN>
            <serviceList>
              <service>
                <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
                <serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>
                <SCPDURL>/mock/AVTransport/scpd.xml</SCPDURL>
                <controlURL>/mock/AVTransport/control</controlURL>
                <eventSubURL>/mock/AVTransport/events</eventSubURL>
              </service>
              <service>
                <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
                <serviceId>urn:upnp-org:serviceId:RenderingControl</serviceId>
                <SCPDURL>/mock/RenderingControl/scpd.xml</SCPDURL>
                <controlURL>/mock/RenderingControl/control</controlURL>
                <eventSubURL>/mock/RenderingControl/events</eventSubURL>
              </service>
            </serviceList>
          </device>
        </root>
        """
    }

    public var avTransportSCPDXML: String {
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <scpd xmlns="urn:schemas-upnp-org:service-1-0">
          <specVersion><major>1</major><minor>0</minor></specVersion>
          <actionList>
            <action><name>SetAVTransportURI</name></action>
            <action><name>Play</name></action>
            <action><name>Pause</name></action>
            <action><name>Stop</name></action>
            <action><name>GetTransportInfo</name></action>
            <action><name>GetPositionInfo</name></action>
          </actionList>
        </scpd>
        """
    }

    public var renderingControlSCPDXML: String {
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <scpd xmlns="urn:schemas-upnp-org:service-1-0">
          <specVersion><major>1</major><minor>0</minor></specVersion>
          <actionList>
            <action><name>GetVolume</name></action>
            <action><name>SetVolume</name></action>
          </actionList>
        </scpd>
        """
    }
}
