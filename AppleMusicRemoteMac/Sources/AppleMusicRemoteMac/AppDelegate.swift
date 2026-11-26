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
        // 0. Initialize Persistent Diagnostic File Logger (if enabled in Settings)
        DiagnosticLogger.shared.setupAtLaunch()

        NSLog("[AppDelegate] Starting Apple Music Remote (100%% Pure Swift Server)...")

        // 1. Setup Menu Bar UI
        MenuManager.shared.setup()

        // 2. Start network and system services immediately so clients never wait on ANE warmup,
        //    and preload Neural Engine / NL 512-D / Vision weights asynchronously in the background after cold-launch settles.
        startNetworkAndSystemServices()

        if NativeMusicCuratorService.shared.isEnabled {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 6.0) {
                NSLog("[AppDelegate] 🧠 AI functions enabled — warming up model weights in background...")
                NativeMusicCuratorService.shared.preloadModelWeightsSynchronously()
            }
        }
    }

    private func startNetworkAndSystemServices() {
        // 2. Check and enforce 100% volume in Music.app off the main thread if volume lock is enabled
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) {
            PlaybackTransportController.shared.checkAndEnforceVolumeLock()
        }

        // 3. Setup WebSocket server delegate & start server
        WebSocketServer.shared.delegate = self
        let started = WebSocketServer.shared.start(port: 8080)
        if !started {
            NSLog("[AppDelegate] Warning: Could not start WebSocket server on port 8080")
        }

        // 4. Start UPnP / DLNA MediaRenderer Server & SSDP Discovery (if enabled)
        let upnpStarted = UPnPMediaRendererServer.shared.startIfEnabled(port: 8090)
        if upnpStarted {
            NSLog("[AppDelegate] 📻 UPnP MediaRenderer & SSDP active on port 8090.")
        }

        // 5. Start Bit-Perfect Unified Log Monitoring & CoreAudio Listeners
        BitPerfectLogMonitor.shared.start()
        BitPerfectLogMonitor.shared.addFormatChangedObserver(id: "AppDelegate") { _, _, _ in
            Task { @MainActor in
                MenuManager.shared.updateMenuState()
            }
        }

        CoreAudioDeviceManager.shared.addDevicesChangedObserver(id: "AppDelegate") { _ in
            Task { @MainActor in
                MenuManager.shared.updateMenuState()
            }
        }
        CoreAudioDeviceManager.shared.addSampleRateChangedObserver(id: "AppDelegate") { _, _ in
            Task { @MainActor in
                MenuManager.shared.updateMenuState()
            }
        }

        // 6. Observe System Sleep / Wake to restore network listeners & multicast discovery
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            NSLog("[AppDelegate] ☀️ System woke from sleep. Restoring SSDP multicast and UPnP...")
            if UPnPMediaRendererServer.shared.isEnabled {
                SSDPService.shared.restart()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) {
                    UPnPMediaRendererServer.shared.notifySubscribers(force: true)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                DLNADiscoveryManager.shared.startIfEnabled()
                ExternalAmpTCPController.shared.startIfActive()
                CloudSettingsSyncService.shared.syncIfEnabled(reason: "wake")
                if AudioEngineController.shared.currentConfigurationSnapshot().mode != .bitPerfectPassthrough {
                    Task(priority: .userInitiated) {
                        _ = await AudioEngineController.shared.startOrReconfigurePipeline()
                        await MainActor.run {
                            MenuManager.shared.updateMenuState()
                        }
                    }
                }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.2) {
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
            }
        }

        // 7. Start Music.app Lifecycle Watchdog & Fault Tolerance Monitor
        let existingLifecycleHandler = MusicAppLifecycleManager.shared.onStateChanged
        MusicAppLifecycleManager.shared.onStateChanged = { event in
            existingLifecycleHandler?(event)
            if event.state == .running {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.5) {
                    MusicKitManager.shared.reconcilePendingStagedCatalogTracksOnLaunch()
                    PlaybackStateStore.shared.scheduleIdleStagedCleanup(after: 120.0)
                }
            }
        }
        MusicAppProvider.shared.addMusicAppLaunchedObserver {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.5) {
                if BitPerfectLogMonitor.shared.isEnabled {
                    BitPerfectLogMonitor.shared.syncMusicAppSmartTransitions(forBitPerfectEnabled: true)
                }
                MusicKitManager.shared.reconcilePendingStagedCatalogTracksOnLaunch()
                PlaybackStateStore.shared.scheduleIdleStagedCleanup(after: 120.0)
            }
        }
        MusicAppLifecycleManager.shared.startWatchdog()

        // 8. Start DLNA Discovery Manager if enabled
        DLNADiscoveryManager.shared.startIfEnabled()

        // 9. Start External Amplifier TCP Socket Controller if active
        ExternalAmpTCPController.shared.onStateChanged = {
            WebSocketServer.shared.broadcastStatus(includeQueue: false)
            UPnPMediaRendererServer.shared.notifySubscribers()
            DispatchQueue.main.async {
                SettingsWindow.refreshAmpStatusIfVisible()
            }
        }
        ExternalAmpTCPController.shared.startIfActive()

        // 10. Start Hybrid DSP Engine if persisted mode is DSD DoP or HQ NOS PCM,
        //     or activate persisted Room EQ / Late-Night DRC in local passthrough mode
        let persistedDSP = AudioEngineController.shared.currentConfigurationSnapshot()
        if persistedDSP.mode != .bitPerfectPassthrough {
            AudioProcessTapService.shared.startCapture()
            Task(priority: .userInitiated) {
                _ = await AudioEngineController.shared.startOrReconfigurePipeline()
                await MainActor.run {
                    MenuManager.shared.updateMenuState()
                }
            }
        } else {
            RoomAcousticService.shared.refreshLocalPassthroughEQPipeline()
        }

        // Clean up any leftover crash-orphaned temporary staged tracks from previous runs ONCE at +1.8s on launch
        // (before Explore pre-warming stages current-session personal mixes).
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.8) {
            Self.performStartupStagedTracksCleanupPass()
        }

        // 11. Start Cloud Sync for DSP Presets & Track Normalization (if enabled by user)
        CloudSettingsSyncService.shared.onStatusChanged = {
            DispatchQueue.main.async {
                SettingsWindow.refreshCloudSyncStatusIfVisible()
            }
        }
        CloudSettingsSyncService.shared.startIfEnabled()

        NSLog("[AppDelegate] Apple Music Remote initialized successfully.")
    }

    nonisolated private static func performStartupStagedTracksCleanupPass() {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else { return }

        MusicKitManager.shared.reconcilePendingStagedCatalogTracksOnLaunch()
        // Defer crash-orphan deletion until 120s of idle time so cold-launch playback never triggers an `amplibraryd` delete-push cooldown!
        PlaybackStateStore.shared.scheduleIdleStagedCleanup(after: 120.0)

        let isCustomQueueActive = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback
        }
        if !isCustomQueueActive {
            MusicKitManager.shared.cleanupTemporaryPlaybackPlaylists(keepingActiveQueue: false)
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        NSLog("[AppDelegate] Terminating Apple Music Remote...")
        PlaybackStateStore.shared.cleanupStagedTemporaryTracksSyncOnTerminate()
        MusicKitManager.shared.cleanupTemporaryPlaybackPlaylists(keepingActiveQueue: false, synchronous: true)
        let sema = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            await AudioEngineController.shared.stopPipeline(restartTapAfterStop: false)
            sema.signal()
        }
        _ = sema.wait(timeout: .now() + 0.5)
        CloudSettingsSyncService.shared.stopMonitoring()
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
