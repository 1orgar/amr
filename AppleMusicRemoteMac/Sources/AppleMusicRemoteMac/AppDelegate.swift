//
//  AppDelegate.swift
//  AppleMusicRemoteMac
//
//  Application Delegate for Apple Music Remote macOS Server
//

import AppKit
import Foundation
import Network

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, WebSocketServerDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[AppDelegate] Starting Apple Music Remote (100%% Pure Swift Server)...")

        // 1. Setup Menu Bar UI
        MenuManager.shared.setup()

        // 2. Setup WebSocket server delegate & start server
        WebSocketServer.shared.delegate = self
        let started = WebSocketServer.shared.start(port: 8080)
        if !started {
            NSLog("[AppDelegate] Warning: Could not start WebSocket server on port 8080")
        }

        // 3. Start UPnP / DLNA MediaRenderer Server & SSDP Discovery
        let upnpStarted = UPnPMediaRendererServer.shared.start(port: 8090)
        if upnpStarted {
            SSDPService.shared.start(httpPort: 8090)
            NSLog("[AppDelegate] 📻 UPnP MediaRenderer & SSDP active on port 8090.")
        } else {
            NSLog("[AppDelegate] Warning: Could not start UPnP server on port 8090")
        }

        // 4. Start Bit-Perfect Unified Log Monitoring & CoreAudio Listeners
        BitPerfectLogMonitor.shared.start()
        BitPerfectLogMonitor.shared.onFormatChanged = { _, _, _ in
            MenuManager.shared.updateMenuState()
        }

        CoreAudioDeviceManager.shared.onDevicesChanged = { _ in
            MenuManager.shared.updateMenuState()
        }
        CoreAudioDeviceManager.shared.onSampleRateChanged = { _, _ in
            MenuManager.shared.updateMenuState()
        }



        NSLog("[AppDelegate] Apple Music Remote initialized successfully.")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        NSLog("[AppDelegate] Terminating Apple Music Remote...")
        BitPerfectLogMonitor.shared.stop()
        SSDPService.shared.stop()
        UPnPMediaRendererServer.shared.stop()
        WebSocketServer.shared.stop()
    }

    // MARK: - WebSocketServerDelegate

    nonisolated public func webSocketServer(_ server: WebSocketServer, didUpdateClientCount count: Int) {
        DispatchQueue.main.async {
            MenuManager.shared.updateClientCount(count)
        }
    }

    nonisolated public func webSocketServer(_ server: WebSocketServer, didChangeState state: NWListener.State) {
        NSLog("[AppDelegate] WebSocket listener state changed to: \(state)")
    }
}
