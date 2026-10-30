//
//  MusicAppLifecycleManagerTests.swift
//  AppleMusicRemoteMacTests
//

import XCTest
@testable import AppleMusicRemoteMac

private final class MockContext: @unchecked Sendable {
    var now: Date = Date()
    var currentPids: [pid_t] = [7777]
    var terminatedPids: [pid_t] = []
    var forceTerminatedPids: [pid_t] = []
    var launched: Bool = false
    var eventEmitted: Bool = false
}

final class MusicAppLifecycleManagerTests: XCTestCase {

    var manager: MusicAppLifecycleManager!

    override func setUp() {
        super.setUp()
        manager = MusicAppLifecycleManager.shared
        manager.resetForTesting(state: .running, clearTimestamps: true)
        manager.autoRestartEnabled = false
        manager.failureThreshold = 2
        manager.circuitBreakerMaxRestarts = 3
        manager.circuitBreakerWindow = 60.0
        manager.cooldownDuration = 30.0

        // Reset DI mocks
        manager.probeHandler = nil
        manager.processTerminator = nil
        manager.processLauncher = nil
        manager.processChecker = nil
        manager.nowProvider = { Date() }
        manager.onStateChanged = nil
    }

    override func tearDown() {
        manager.stopWatchdog()
        manager.resetForTesting(state: .running, clearTimestamps: true)
        manager.probeHandler = nil
        manager.processTerminator = nil
        manager.processLauncher = nil
        manager.processChecker = nil
        manager.nowProvider = { Date() }
        manager.onStateChanged = nil
        manager.autoRestartEnabled = true
        super.tearDown()
    }

    func testInitialStateAndHealth() {
        manager.resetForTesting(state: .running)
        XCTAssertEqual(manager.state, .running)
        XCTAssertTrue(manager.isHealthy)

        manager.resetForTesting(state: .unresponsive)
        XCTAssertEqual(manager.state, .unresponsive)
        XCTAssertFalse(manager.isHealthy)

        manager.resetForTesting(state: .terminated)
        XCTAssertEqual(manager.state, .terminated)
        XCTAssertFalse(manager.isHealthy)

        manager.resetForTesting(state: .cooldown)
        XCTAssertEqual(manager.state, .cooldown)
        XCTAssertFalse(manager.isHealthy)

        manager.resetForTesting(state: .recovering)
        XCTAssertEqual(manager.state, .recovering)
        XCTAssertFalse(manager.isHealthy)
    }

    func testProbeFailuresLeadToUnresponsiveState() {
        manager.resetForTesting(state: .running)
        manager.failureThreshold = 2

        // First probe failure: should not immediately mark unresponsive
        manager.handleProbeResult(success: false)
        XCTAssertEqual(manager.state, .running)
        XCTAssertTrue(manager.isHealthy)

        // Second probe failure: hits threshold -> unresponsive
        manager.handleProbeResult(success: false)
        XCTAssertEqual(manager.state, .unresponsive)
        XCTAssertFalse(manager.isHealthy)

        // Succeeded probe recovers state to running
        manager.handleProbeResult(success: true)
        XCTAssertEqual(manager.state, .running)
        XCTAssertTrue(manager.isHealthy)
    }

    func testProcessNotificationsUpdateState() {
        manager.resetForTesting(state: .running)

        // Terminate notification
        manager.handleAppTerminated(pid: 12345)
        XCTAssertEqual(manager.state, .terminated)
        XCTAssertFalse(manager.isHealthy)

        // Launch notification
        manager.handleAppLaunched(pid: 12346)
        XCTAssertEqual(manager.state, .running)
        XCTAssertTrue(manager.isHealthy)
    }

    func testIPCTimeoutTriggersUnresponsive() {
        manager.resetForTesting(state: .running)
        manager.failureThreshold = 2

        manager.reportIPCTimeout()
        XCTAssertEqual(manager.state, .running)

        manager.reportIPCTimeout()
        XCTAssertEqual(manager.state, .unresponsive)
    }

    func testStateChangedCallbackEmitsAccurateEvent() {
        let exp = expectation(description: "onStateChanged called")
        manager.resetForTesting(state: .running)

        manager.onStateChanged = { event in
            if event.state == .unresponsive {
                XCTAssertFalse(event.isHealthy)
                XCTAssertTrue(event.reason.contains("hang"))
                exp.fulfill()
            }
        }

        manager.handleProbeResult(success: false)
        manager.handleProbeResult(success: false)

        waitForExpectations(timeout: 1.0)
    }

    func testCircuitBreakerTripsAfterMaxRestarts() {
        let ctx = MockContext()
        manager.nowProvider = { ctx.now }
        manager.circuitBreakerMaxRestarts = 3
        manager.circuitBreakerWindow = 60.0
        manager.cooldownDuration = 30.0

        // Restart 1
        manager.triggerRecovery(reason: "Restart 1")
        XCTAssertEqual(manager.state, .recovering)
        XCTAssertEqual(manager.recentRestartCount, 1)

        manager.resetForTesting(state: .unresponsive, clearTimestamps: false)
        // Restart 2 (10s later)
        ctx.now = ctx.now.addingTimeInterval(10.0)
        manager.triggerRecovery(reason: "Restart 2")
        XCTAssertEqual(manager.state, .recovering)
        XCTAssertEqual(manager.recentRestartCount, 2)

        manager.resetForTesting(state: .unresponsive, clearTimestamps: false)
        // Restart 3 (20s later)
        ctx.now = ctx.now.addingTimeInterval(10.0)
        manager.triggerRecovery(reason: "Restart 3")
        XCTAssertEqual(manager.state, .recovering)
        XCTAssertEqual(manager.recentRestartCount, 3)

        manager.resetForTesting(state: .unresponsive, clearTimestamps: false)
        // Restart 4 (attempted within window -> trips circuit breaker)
        ctx.now = ctx.now.addingTimeInterval(5.0)
        manager.triggerRecovery(reason: "Restart 4 (should trip)")
        XCTAssertEqual(manager.state, .cooldown)
        XCTAssertTrue(manager.remainingCooldown > 0)

        // Watchdog check during cooldown remains in cooldown
        manager.performWatchdogCheck()
        XCTAssertEqual(manager.state, .cooldown)

        // Advance time beyond cooldown duration
        ctx.now = ctx.now.addingTimeInterval(35.0)
        manager.processChecker = { [9999] }
        manager.performWatchdogCheck()
        XCTAssertEqual(manager.state, .running)
    }

    func testRecoveryRoutineExecutesGracefulAndForceTermination() {
        let ctx = MockContext()

        manager.processChecker = { ctx.currentPids }
        manager.processTerminator = { pid, force in
            if force {
                ctx.forceTerminatedPids.append(pid)
                ctx.currentPids.removeAll { $0 == pid }
            } else {
                ctx.terminatedPids.append(pid)
                ctx.currentPids.removeAll { $0 == pid }
            }
            return true
        }
        manager.processLauncher = {
            ctx.launched = true
            ctx.currentPids = [8888]
            return true
        }

        manager.onStateChanged = { event in
            if event.state == .running && ctx.launched {
                ctx.eventEmitted = true
            }
        }

        manager.resetForTesting(state: .unresponsive, clearTimestamps: true)
        manager.triggerRecovery(reason: "Test recovery")

        XCTAssertTrue(ctx.terminatedPids.contains(7777))
        XCTAssertTrue(ctx.launched)
        XCTAssertTrue(ctx.eventEmitted)
        XCTAssertEqual(manager.state, .running)
    }

    func testFailFastInAppleScriptExecutorWhenUnhealthy() {
        manager.resetForTesting(state: .unresponsive)
        XCTAssertFalse(manager.isHealthy)

        // Any AppleScript targeting Music should fail-fast without blocking
        let (ok, out) = AppleScriptExecutor.shared.run("tell application \"Music\" to play")
        XCTAssertFalse(ok)
        XCTAssertNil(out)
    }

    func testFailFastInPlayerStatusEngineWhenUnhealthy() {
        manager.resetForTesting(state: .unresponsive)
        XCTAssertFalse(manager.isHealthy)

        let status = PlayerStatusEngine.shared.getPlayerStatus()
        // Fast path immediately returns status with isMusicAppRunning = false
        XCTAssertFalse(status.isMusicAppRunning)
    }
}
