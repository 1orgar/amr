//
//  MusicAppLifecycleManager.swift
//  AppleMusicRemoteMac
//
//  Comprehensive lifecycle management and fault tolerance for Music.app:
//  - Active watchdog heartbeat to detect unresponsive / hanging / beachballing process
//  - Process crash and sudden exit detection
//  - Auto-recovery: force-termination of frozen instance, clean background launch, 100% volume lock restoration
//  - Circuit Breaker: prevents restart storms/loops (max 3 restarts per 60s, cooldown backoff)
//  - Fail-Fast protection: immediately rejects IPC calls without thread contention when Music.app is unhealthy
//  - Real-time lifecycle event broadcasting for clients
//

import AppKit
import Foundation
import ScriptingBridge

public enum MusicAppLifecycleState: String, Codable, Sendable {
    case running = "running"
    case unresponsive = "unresponsive"
    case terminated = "terminated"
    case recovering = "recovering"
    case cooldown = "cooldown"
}

public struct MusicAppLifecycleEvent: Codable, Sendable {
    public let state: MusicAppLifecycleState
    public let reason: String
    public let isHealthy: Bool
    public let restartCount: Int
    public let cooldownRemaining: TimeInterval

    enum CodingKeys: String, CodingKey {
        case state
        case reason
        case isHealthy = "is_healthy"
        case restartCount = "restart_count"
        case cooldownRemaining = "cooldown_remaining"
    }

    public init(
        state: MusicAppLifecycleState,
        reason: String,
        isHealthy: Bool,
        restartCount: Int,
        cooldownRemaining: TimeInterval = 0
    ) {
        self.state = state
        self.reason = reason
        self.isHealthy = isHealthy
        self.restartCount = restartCount
        self.cooldownRemaining = cooldownRemaining
    }
}

public final class MusicAppLifecycleManager: @unchecked Sendable {
    public static let shared = MusicAppLifecycleManager()

    // MARK: - State & Locks

    private let stateLock = NSRecursiveLock()
    private var currentState: MusicAppLifecycleState = .running
    private var consecutiveFailures: Int = 0
    private var restartTimestamps: [Date] = []
    private var cooldownUntil: Date?

    // Configuration
    public var watchdogInterval: TimeInterval = 5.0
    public var probeTimeout: TimeInterval = 1.5
    public var failureThreshold: Int = 2
    public var circuitBreakerMaxRestarts: Int = 3
    public var circuitBreakerWindow: TimeInterval = 60.0
    public var cooldownDuration: TimeInterval = 30.0
    public var autoRestartEnabled: Bool = true

    // Callbacks
    public var onStateChanged: (@Sendable (MusicAppLifecycleEvent) -> Void)?

    // Dependency Injection for Testing
    public var probeHandler: (@Sendable () async -> Bool)?
    public var processTerminator: (@Sendable (pid_t, Bool) -> Bool)?
    public var processLauncher: (@Sendable () -> Bool)?
    public var processChecker: (@Sendable () -> [pid_t])?
    public var nowProvider: (@Sendable () -> Date) = { Date() }

    // Background Watchdog Timer & Probe Queue
    private var watchdogTimer: DispatchSourceTimer?
    private let watchdogQueue = DispatchQueue(label: "com.amr.musicapp.watchdog", qos: .utility)
    private let probeQueue = DispatchQueue(label: "com.amr.lifecycle.probe", qos: .utility)
    private var isWatchdogRunning: Bool = false
    private var isRecoveringInProgress: Bool = false
    private var isApplescriptProbeRunning: Bool = false

    // MARK: - Public Properties

    public var state: MusicAppLifecycleState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentState
    }

    public var isHealthy: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentState == .running
    }

    public var recentRestartCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        let now = nowProvider()
        return restartTimestamps.filter { now.timeIntervalSince($0) < circuitBreakerWindow }.count
    }

    public var remainingCooldown: TimeInterval {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let until = cooldownUntil else { return 0 }
        let rem = until.timeIntervalSince(nowProvider())
        return max(0, rem)
    }

    // MARK: - Initialization

    public init() {
        // Initial state determination
        let pids = getRunningPids()
        if pids.isEmpty {
            currentState = .terminated
        } else {
            currentState = .running
        }
    }

    // MARK: - Watchdog Lifecycle

    public func startWatchdog() {
        stateLock.lock()
        if isWatchdogRunning {
            stateLock.unlock()
            return
        }
        isWatchdogRunning = true
        stateLock.unlock()

        let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        timer.schedule(deadline: .now() + 2.0, repeating: watchdogInterval)
        timer.setEventHandler { [weak self] in
            self?.performWatchdogCheck()
        }
        watchdogTimer = timer
        timer.resume()
        NSLog("[MusicAppLifecycleManager] 🐕 Watchdog timer started (interval: %.1fs)", watchdogInterval)
    }

    public func stopWatchdog() {
        stateLock.lock()
        isWatchdogRunning = false
        watchdogTimer?.cancel()
        watchdogTimer = nil
        stateLock.unlock()
        NSLog("[MusicAppLifecycleManager] 🐕 Watchdog timer stopped")
    }

    // MARK: - Health Check & Probing

    public func performWatchdogCheck() {
        if PlaybackRouter.shared.isTestingEnvironment && probeHandler == nil && processChecker == nil {
            return
        }

        let pids = getRunningPids()

        stateLock.lock()
        var cooldownNotify: (() -> Void)? = nil
        if let until = cooldownUntil {
            if nowProvider() >= until {
                // Cooldown period expired — reset circuit breaker window so recovery can proceed
                cooldownUntil = nil
                restartTimestamps.removeAll()
                NSLog("[MusicAppLifecycleManager] ❄️ Cooldown period expired. Re-evaluating health...")
                if !pids.isEmpty {
                    cooldownNotify = transitionToStateLocked(.running, reason: "Cooldown expired, re-enabling monitoring")
                }
            } else {
                stateLock.unlock()
                return
            }
        }

        if isRecoveringInProgress {
            stateLock.unlock()
            cooldownNotify?()
            return
        }

        if pids.isEmpty {
            let notify: (() -> Void)?
            if currentState != .terminated {
                notify = transitionToStateLocked(.terminated, reason: "Music.app process not detected")
            } else {
                notify = cooldownNotify
            }
            let shouldRecover = autoRestartEnabled && !isRecoveringInProgress && (!PlaybackRouter.shared.isTestingEnvironment || processLauncher != nil || processTerminator != nil)
            stateLock.unlock()
            notify?()
            if shouldRecover {
                triggerRecovery(reason: "Music.app exited, auto-restart triggered")
            }
            return
        }
        stateLock.unlock()
        cooldownNotify?()

        if PlaybackRouter.shared.isTestingEnvironment && probeHandler == nil {
            return
        }

        // Probe responsiveness asynchronously with timeout
        Task { [weak self] in
            guard let self = self else { return }
            let success = await self.probeResponsiveness()
            self.handleProbeResult(success: success)
        }
    }

    private final class ProbeOnceGate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Bool, Never>?

        init(_ continuation: CheckedContinuation<Bool, Never>) {
            self.continuation = continuation
        }

        func resume(returning value: Bool) {
            lock.lock()
            let cont = continuation
            continuation = nil
            lock.unlock()
            cont?.resume(returning: value)
        }
    }

    private func probeResponsiveness() async -> Bool {
        if let customProbe = probeHandler {
            return await customProbe()
        }

        // Single-flight guard: never stack multiple ScriptingBridge probes if Music.app is hung
        let canStart: Bool = stateLock.withLock {
            if isApplescriptProbeRunning {
                return false
            }
            isApplescriptProbeRunning = true
            return true
        }
        guard canStart else {
            return false
        }

        let timeout = self.probeTimeout
        return await withCheckedContinuation { continuation in
            let gate = ProbeOnceGate(continuation)
            probeQueue.async { [weak self] in
                var ok = false
                if let app = MusicAppProvider.shared.getMusicApp() {
                    let state = app.playerState
                    if let sbApp = app as? SBApplication {
                        ok = sbApp.lastError() == nil && state.rawValue != 0
                    } else {
                        ok = true
                    }
                }
                if let self = self {
                    self.stateLock.lock()
                    self.isApplescriptProbeRunning = false
                    self.stateLock.unlock()
                }
                gate.resume(returning: ok)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                gate.resume(returning: false)
            }
        }
    }

    public func handleProbeResult(success: Bool) {
        stateLock.lock()
        if success {
            if consecutiveFailures > 0 {
                NSLog("[MusicAppLifecycleManager] 🟢 Music.app recovered responsiveness")
            }
            consecutiveFailures = 0
            var notify: (() -> Void)? = nil
            if currentState != .running && !isRecoveringInProgress {
                notify = transitionToStateLocked(.running, reason: "Watchdog probe succeeded")
            }
            stateLock.unlock()
            notify?()
        } else {
            consecutiveFailures += 1
            NSLog("[MusicAppLifecycleManager] ⚠️ Watchdog probe failed (%d/%d)", consecutiveFailures, failureThreshold)

            if consecutiveFailures >= failureThreshold {
                if currentState != .unresponsive && !isRecoveringInProgress && currentState != .cooldown {
                    let notify = transitionToStateLocked(.unresponsive, reason: "Watchdog probe timed out \(consecutiveFailures) consecutive times (hang/beachball detected)")
                    let shouldRecover = autoRestartEnabled && (!PlaybackRouter.shared.isTestingEnvironment || processLauncher != nil || processTerminator != nil)
                    stateLock.unlock()
                    notify?()

                    if shouldRecover {
                        triggerRecovery(reason: "Music.app is unresponsive, auto-recovering")
                    }
                    return
                }
            }
            stateLock.unlock()
        }
    }

    /// Report an external IPC timeout (e.g. from AppleScriptExecutor)
    public func reportIPCTimeout() {
        stateLock.lock()
        consecutiveFailures += 1
        NSLog("[MusicAppLifecycleManager] ⚠️ IPC timeout reported (%d/%d)", consecutiveFailures, failureThreshold)
        if consecutiveFailures >= failureThreshold && currentState == .running {
            let notify = transitionToStateLocked(.unresponsive, reason: "AppleScript IPC timed out (Apple Event deadlock)")
            let shouldRecover = autoRestartEnabled && (!PlaybackRouter.shared.isTestingEnvironment || processLauncher != nil || processTerminator != nil)
            stateLock.unlock()
            notify?()
            if shouldRecover {
                triggerRecovery(reason: "IPC deadlock, auto-recovering")
            }
            return
        }
        stateLock.unlock()
    }

    // MARK: - Process Notifications

    public func handleAppLaunched(pid: pid_t) {
        stateLock.lock()
        guard !isRecoveringInProgress else {
            stateLock.unlock()
            return
        }
        consecutiveFailures = 0
        let notify = transitionToStateLocked(.running, reason: "Music.app launched (PID: \(pid))")
        stateLock.unlock()
        notify?()
    }

    public func handleAppTerminated(pid: pid_t) {
        stateLock.lock()
        if !isRecoveringInProgress {
            let notify = transitionToStateLocked(.terminated, reason: "Music.app terminated (PID: \(pid))")
            let shouldRecover = autoRestartEnabled && (!PlaybackRouter.shared.isTestingEnvironment || processLauncher != nil || processTerminator != nil)
            stateLock.unlock()
            notify?()
            if shouldRecover {
                triggerRecovery(reason: "Music.app terminated, auto-restarting")
            }
        } else {
            stateLock.unlock()
        }
    }

    // MARK: - Recovery & Circuit Breaker

    public func triggerRecovery(reason: String) {
        stateLock.lock()
        if isRecoveringInProgress {
            stateLock.unlock()
            return
        }

        let now = nowProvider()
        // Clean up old timestamps
        restartTimestamps = restartTimestamps.filter { now.timeIntervalSince($0) < circuitBreakerWindow }

        if restartTimestamps.count >= circuitBreakerMaxRestarts {
            // Trip Circuit Breaker
            cooldownUntil = now.addingTimeInterval(cooldownDuration)
            let notify = transitionToStateLocked(.cooldown, reason: "Circuit breaker tripped: \(restartTimestamps.count) restarts in \(Int(circuitBreakerWindow))s. Cooldown for \(Int(cooldownDuration))s")
            stateLock.unlock()
            notify?()
            return
        }

        // Record restart attempt
        restartTimestamps.append(now)
        isRecoveringInProgress = true
        let notify = transitionToStateLocked(.recovering, reason: reason)
        stateLock.unlock()
        notify?()

        if PlaybackRouter.shared.isTestingEnvironment {
            if processLauncher == nil && processTerminator == nil {
                stateLock.lock()
                isRecoveringInProgress = false
                stateLock.unlock()
                return
            }
            self.executeRecoveryRoutine()
            return
        }

        watchdogQueue.async { [weak self] in
            self?.executeRecoveryRoutine()
        }
    }

    private func executeRecoveryRoutine() {
        NSLog("[MusicAppLifecycleManager] 🔄 Starting recovery routine...")

        // 1. Terminate or Force Terminate hung process(es)
        let pids = getRunningPids()
        for pid in pids {
            terminatePid(pid)
        }

        if !PlaybackRouter.shared.isTestingEnvironment && processTerminator == nil {
            // Wait up to 1.5s for process cleanup
            let cleanupDeadline = nowProvider().addingTimeInterval(1.5)
            while !getRunningPids().isEmpty && nowProvider() < cleanupDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }

            // If still alive, force kill
            for pid in getRunningPids() {
                forceTerminatePid(pid)
            }
        }

        // 2. Launch fresh instance
        let launchSuccess = launchInstance()
        guard launchSuccess else {
            NSLog("[MusicAppLifecycleManager] ❌ Failed to launch Music.app during recovery")
            stateLock.lock()
            isRecoveringInProgress = false
            let notify = transitionToStateLocked(.unresponsive, reason: "Failed to launch Music.app")
            stateLock.unlock()
            notify?()
            return
        }

        // 3. Await readiness
        var isReady = false
        if PlaybackRouter.shared.isTestingEnvironment || processLauncher != nil {
            isReady = true
        } else {
            let readyDeadline = nowProvider().addingTimeInterval(6.0)
            while nowProvider() < readyDeadline {
                Thread.sleep(forTimeInterval: 0.2)
                let pidsNow = getRunningPids()
                if !pidsNow.isEmpty {
                    if let app = MusicAppProvider.shared.getMusicApp() {
                        let state = app.playerState
                        let sbError = (app as? SBApplication)?.lastError()
                        if sbError == nil && (app as? SBApplication == nil || state.rawValue != 0) {
                            isReady = true
                            break
                        }
                    }
                }
            }
        }

        stateLock.lock()
        isRecoveringInProgress = false

        if isReady {
            consecutiveFailures = 0
            let notify = transitionToStateLocked(.running, reason: "Recovery successful: fresh Music.app running and responding")
            stateLock.unlock()
            notify?()

            // Reset state store & volume lock
            PlaybackStateStore.shared.invalidateStatusCache()
            PlaybackStateStore.shared.invalidateQueueCache()

            if !PlaybackRouter.shared.isTestingEnvironment {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    PlaybackTransportController.shared.checkAndEnforceVolumeLock()
                }
            }
        } else {
            let notify = transitionToStateLocked(.unresponsive, reason: "Launched Music.app did not become responsive within timeout")
            stateLock.unlock()
            notify?()
        }
    }

    // MARK: - Helper Methods

    private func getRunningPids() -> [pid_t] {
        if let checker = processChecker {
            return checker()
        }
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
        return apps.map { $0.processIdentifier }
    }

    private func terminatePid(_ pid: pid_t) {
        if let customTerminator = processTerminator {
            _ = customTerminator(pid, false)
            return
        }
        if let app = NSRunningApplication(processIdentifier: pid) {
            NSLog("[MusicAppLifecycleManager] 🛑 Gracefully terminating PID %d", pid)
            app.terminate()
        }
    }

    private func forceTerminatePid(_ pid: pid_t) {
        if let customTerminator = processTerminator {
            _ = customTerminator(pid, true)
            return
        }
        if let app = NSRunningApplication(processIdentifier: pid) {
            NSLog("[MusicAppLifecycleManager] 💥 Force terminating (SIGKILL) PID %d", pid)
            app.forceTerminate()
        }
    }

    private func launchInstance() -> Bool {
        if let customLauncher = processLauncher {
            return customLauncher()
        }
        return MusicAppProvider.shared.launchMusicApp()
    }

    private func transitionToStateLocked(_ newState: MusicAppLifecycleState, reason: String) -> (() -> Void)? {
        currentState = newState
        let event = MusicAppLifecycleEvent(
            state: newState,
            reason: reason,
            isHealthy: newState == .running,
            restartCount: restartTimestamps.count,
            cooldownRemaining: cooldownUntil.map { max(0, $0.timeIntervalSince(nowProvider())) } ?? 0
        )
        NSLog("[MusicAppLifecycleManager] 🔔 State -> %@: %@", newState.rawValue, reason)

        guard let callback = onStateChanged else { return nil }
        return { callback(event) }
    }

    // MARK: - Test Reset Support

    public func resetForTesting(state: MusicAppLifecycleState = .running, clearTimestamps: Bool = true) {
        stateLock.lock()
        currentState = state
        consecutiveFailures = 0
        if clearTimestamps {
            restartTimestamps.removeAll()
            cooldownUntil = nil
        }
        isRecoveringInProgress = false
        isApplescriptProbeRunning = false
        stateLock.unlock()
    }
}
