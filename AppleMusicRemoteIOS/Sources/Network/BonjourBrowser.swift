//
//  BonjourBrowser.swift
//  AppleMusicRemoteIOS
//
//  Network.framework Bonjour auto-discovery of Mac servers (_applemusicremote._tcp)
//

import Combine
import Foundation
import Network

public final class BonjourBrowser: ObservableObject, @unchecked Sendable {
    public static let shared = BonjourBrowser()

    @Published public var discoveredServers: [ServerHost] = []
    @Published public var isScanning: Bool = false

    private var browser: NWBrowser?
    private let browserQueue = DispatchQueue(label: "com.applemusicremote.ios.bonjour", qos: .userInitiated)

    private init() {}

    public func startDiscovery() {
        guard browser == nil else { return }

        let descriptor = NWBrowser.Descriptor.bonjour(type: "_applemusicremote._tcp", domain: "local.")
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let newBrowser = NWBrowser(for: descriptor, using: parameters)
        self.browser = newBrowser
        DispatchQueue.main.async { self.isScanning = true }

        newBrowser.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                NSLog("[BonjourBrowser] Browser ready, scanning for Macs...")
            case .failed(let error):
                NSLog("[BonjourBrowser] Browser failed: \(error)")
                self.stopDiscovery()
            case .cancelled:
                DispatchQueue.main.async { self.isScanning = false }
            default:
                break
            }
        }

        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }
            self.handleResults(results)
        }

        newBrowser.start(queue: browserQueue)
    }

    public func stopDiscovery() {
        browser?.cancel()
        browser = nil
        DispatchQueue.main.async { self.isScanning = false }
    }

    private func handleResults(_ results: Set<NWBrowser.Result>) {
        var servers: [ServerHost] = []

        for result in results {
            if case let .service(name, _, _, interface) = result.endpoint {
                #if targetEnvironment(simulator)
                let resolvedIp = "127.0.0.1"
                #else
                let resolvedIp = name.contains(" ") ? "127.0.0.1" : "\(name).local"
                #endif
                let host = ServerHost(
                    id: "\(name)_\(interface?.name ?? "all")",
                    name: name,
                    hostName: "\(name).local",
                    port: 8080,
                    ipAddress: resolvedIp,
                    pingMs: 4
                )
                servers.append(host)
            }
        }

        DispatchQueue.main.async {
            self.discoveredServers = servers
        }
    }
}
