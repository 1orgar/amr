//
//  BonjourAdvertiser.swift
//  AppleMusicRemoteMac
//
//  Pure Swift Bonjour / mDNS service advertiser for Apple Music Remote
//

import Foundation

public final class BonjourAdvertiser: NSObject, NetServiceDelegate, @unchecked Sendable {
    public static let shared = BonjourAdvertiser()

    private var netService: NetService?
    private var isAdvertising = false
    private let lock = NSLock()

    public private(set) var advertisedPort: Int = 8080

    private override init() {
        super.init()
    }

    public func startAdvertising(port: Int, name: String? = nil) {
        lock.lock()
        defer { lock.unlock() }

        stopAdvertisingUnlocked()

        self.advertisedPort = port
        let hostName = Host.current().localizedName ?? Host.current().name ?? "Mac"
        let serviceName = name ?? "\(hostName) (Apple Music Remote)"
        let serviceType = "_applemusicremote._tcp."

        let service = NetService(
            domain: "local.",
            type: serviceType,
            name: serviceName,
            port: Int32(port)
        )

        service.delegate = self
        service.includesPeerToPeer = true

        var txtDict: [String: Data] = [:]
        txtDict["version"] = "2.2.0".data(using: .utf8)
        txtDict["platform"] = "macOS".data(using: .utf8)
        txtDict["protocol"] = "amr-ws".data(using: .utf8)
        txtDict["host"] = (Host.current().name ?? "localhost").data(using: .utf8)
        txtDict["port"] = "\(port)".data(using: .utf8)
        txtDict["name"] = serviceName.data(using: .utf8)

        service.setTXTRecord(NetService.data(fromTXTRecord: txtDict))
        service.publish(options: [.listenForConnections])

        self.netService = service
        self.isAdvertising = true

        NSLog("[Bonjour] Publishing service '%@' of type '%@' on port %d", serviceName, serviceType, port)
    }

    public func stopAdvertising() {
        lock.lock()
        defer { lock.unlock() }
        stopAdvertisingUnlocked()
    }

    private func stopAdvertisingUnlocked() {
        if let service = netService {
            service.stop()
            self.netService = nil
        }
        self.isAdvertising = false
    }

    // MARK: - NetServiceDelegate

    public func netServiceDidPublish(_ sender: NetService) {
        NSLog("[Bonjour] Successfully published: %@", sender.name)
    }

    public func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        NSLog("[Bonjour] Failed to publish: %@", errorDict)
    }

    public func netServiceDidStop(_ sender: NetService) {
        NSLog("[Bonjour] Service stopped")
    }
}
