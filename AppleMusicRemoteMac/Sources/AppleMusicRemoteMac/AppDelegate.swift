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

        // 2. Check and enforce 100% volume in Music.app if volume lock is enabled
        PlaybackTransportController.shared.checkAndEnforceVolumeLock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            PlaybackTransportController.shared.checkAndEnforceVolumeLock()
        }

        // 2. Setup WebSocket server delegate & start server
        WebSocketServer.shared.delegate = self
        let started = WebSocketServer.shared.start(port: 8080)
        if !started {
            NSLog("[AppDelegate] Warning: Could not start WebSocket server on port 8080")
        }

        // 3. Start UPnP / DLNA MediaRenderer Server & SSDP Discovery (if enabled)
        let upnpStarted = UPnPMediaRendererServer.shared.startIfEnabled(port: 8090)
        if upnpStarted {
            NSLog("[AppDelegate] 📻 UPnP MediaRenderer & SSDP active on port 8090.")
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

        // 5. Observe System Sleep / Wake to restore network listeners & multicast discovery
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            NSLog("[AppDelegate] ☀️ System woke from sleep. Restoring SSDP multicast and UPnP...")
            if UPnPMediaRendererServer.shared.isEnabled {
                SSDPService.shared.restart()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    UPnPMediaRendererServer.shared.notifySubscribers(force: true)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
            }
        }

        // 6. Start Music.app Lifecycle Watchdog & Fault Tolerance Monitor
        MusicAppLifecycleManager.shared.startWatchdog()

        // 7. Start DLNA Discovery Manager if enabled
        DLNADiscoveryManager.shared.startIfEnabled()

        NSLog("[AppDelegate] Apple Music Remote initialized successfully.")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        NSLog("[AppDelegate] Terminating Apple Music Remote...")
        MusicAppLifecycleManager.shared.stopWatchdog()
        BitPerfectLogMonitor.shared.stop()
        DLNADiscoveryManager.shared.stop()
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
