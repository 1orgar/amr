//
//  AppleScriptExecutor.swift
//  AppleMusicRemoteMac
//
//  Thread-safe execution of AppleScript and Apple Events with
//  per-call timeouts and deadlock prevention.
//

import Foundation

public final class AppleScriptExecutor: @unchecked Sendable {
    public static let shared = AppleScriptExecutor()

    private let lock = NSLock()
    private let workerIdleCondition = NSCondition()
    private var isWorkerExecuting: Bool = false
    private let workerQueue = DispatchQueue(label: "com.amr.applescript.worker", qos: .userInitiated)
    /// Strictly confined to `workerQueue` per Apple TN2084.
    private var compiledScripts: [String: NSAppleScript] = [:]

    private final class ExecutionBox: @unchecked Sendable {
        var descriptor: NSAppleEventDescriptor?
        var errorNumber: Int = 0
        var errorMessage: String?
    }

    private init() {}

    /// True when the single serial OpenScripting worker is actively compiling or executing an AppleEvent.
    public var isBusy: Bool {
        workerIdleCondition.lock()
        defer { workerIdleCondition.unlock() }
        return isWorkerExecuting
    }

    /// Executes an AppleScript source and returns the raw NSAppleEventDescriptor.
    /// Safely prevents deadlocks and OpenScripting corruption by:
    /// 1. Strictly serializing ALL NSAppleScript compilation, execution, caching, and deallocation on a single permanent worker queue (Apple TN2084).
    /// 2. Never spawning a second concurrent OSA worker queue while a prior call is still inside OpenScripting.
    /// 3. Failing fast when contended so callers fall back to cached state instead of piling up threads.
    public func executeDescriptor(
        _ source: String,
        maxWait: TimeInterval = 2.4,
        reportTimeout: Bool = true
    ) -> NSAppleEventDescriptor? {
        if PlaybackRouter.shared.isTestingEnvironment {
            return nil
        }
        if (!MusicAppProvider.shared.isMusicAppRunning || !MusicAppLifecycleManager.shared.isHealthy) && source.contains("tell application \"Music\"") {
            return nil
        }

        let lockBudget = max(0.25, min(maxWait, 1.6))
        guard lock.lock(before: Date().addingTimeInterval(lockBudget)) else {
            NSLog("[AppleScriptExecutor] Lock acquisition skipped (busy/contended, budget=%.2fs)", lockBudget)
            return nil
        }
        defer { lock.unlock() }

        // If a prior script timed out on wall-clock wait and is still finishing inside OpenScripting on workerQueue,
        // wait briefly for it to exit rather than queuing unbounded work or violating TN2084.
        workerIdleCondition.lock()
        if isWorkerExecuting {
            let drainDeadline = Date().addingTimeInterval(min(0.6, lockBudget * 0.5))
            while isWorkerExecuting && workerIdleCondition.wait(until: drainDeadline) {}
            if isWorkerExecuting {
                workerIdleCondition.unlock()
                NSLog("[AppleScriptExecutor] Worker still draining prior AppleEvent — skipping new dispatch")
                return nil
            }
        }
        isWorkerExecuting = true
        workerIdleCondition.unlock()

        var timedSource = source
        let lowerSource = timedSource.lowercased()
        let hasTimeoutClause = lowerSource.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("with timeout")
            || lowerSource.contains("\nwith timeout")
            || lowerSource.range(of: #"(?m)^\s+with timeout\b"#, options: .regularExpression) != nil
        if !hasTimeoutClause {
            let tellCount = timedSource.components(separatedBy: "tell application \"Music\"").count - 1
            let endTellCount = timedSource.components(separatedBy: "end tell").count - 1
            if tellCount == 1,
               endTellCount >= 1,
               let tellRange = timedSource.range(of: "tell application \"Music\""),
               let endTellRange = timedSource.range(of: "end tell", options: .backwards),
               tellRange.upperBound <= endTellRange.lowerBound,
               !timedSource[tellRange.upperBound...].hasPrefix(" to ") {
                let prefix = timedSource[..<tellRange.upperBound]
                let body = timedSource[tellRange.upperBound..<endTellRange.lowerBound]
                let suffix = timedSource[endTellRange.lowerBound...]
                timedSource = "\(prefix)\nwith timeout of 2 seconds\(body)\nend timeout\n\(suffix)"
            } else {
                timedSource = "with timeout of 2 seconds\n" + timedSource + "\nend timeout"
            }
        }

        let box = ExecutionBox()
        let sema = DispatchSemaphore(value: 0)
        let scriptText = timedSource
        let shouldCacheCompiled = scriptText.utf8.count <= 2048

        workerQueue.async { [weak self] in
            autoreleasepool {
                var error: NSDictionary?
                let script: NSAppleScript?
                if shouldCacheCompiled, let cached = self?.compiledScripts[scriptText] {
                    script = cached
                } else {
                    let fresh = NSAppleScript(source: scriptText)
                    if shouldCacheCompiled, let self = self, let fresh = fresh {
                        if self.compiledScripts.count >= 32 {
                            self.compiledScripts.removeAll(keepingCapacity: true)
                        }
                        self.compiledScripts[scriptText] = fresh
                    }
                    script = fresh
                }
                let desc = script?.executeAndReturnError(&error)
                if let err = error {
                    box.errorMessage = err[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    box.errorNumber = err[NSAppleScript.errorNumber] as? Int ?? 0
                } else {
                    box.descriptor = desc
                }
            }
            if let self = self {
                self.workerIdleCondition.lock()
                self.isWorkerExecuting = false
                self.workerIdleCondition.broadcast()
                self.workerIdleCondition.unlock()
            }
            sema.signal()
        }

        let waitBudget = max(0.5, maxWait)
        if sema.wait(timeout: .now() + waitBudget) == .timedOut {
            NSLog("[AppleScriptExecutor] ⚠️ Worker execution timed out (>%.1fs)", waitBudget)
            if reportTimeout {
                MusicAppLifecycleManager.shared.reportIPCTimeout()
            }
            return nil
        }

        if let msg = box.errorMessage {
            let errNum = box.errorNumber
            NSLog("[AppleScriptExecutor] Error (\(errNum)): \(msg)")
            if reportTimeout && (errNum == -1712 || msg.contains("timed out") || msg.contains("AppleEvent timed out")) {
                MusicAppLifecycleManager.shared.reportIPCTimeout()
            }
            return nil
        }

        if source.contains("tell application \"Music\"") {
            MusicAppLifecycleManager.shared.reportIPCSuccess()
        }
        return box.descriptor
    }

    /// Executes AppleScript and returns (success, stringValue).
    public func run(_ source: String, maxWait: TimeInterval = 2.4, reportTimeout: Bool = true) -> (Bool, String?) {
        if let desc = executeDescriptor(source, maxWait: maxWait, reportTimeout: reportTimeout) {
            return (true, desc.stringValue)
        }
        return (false, nil)
    }

    /// Convenience wrapper returning (success: Bool, output: String?).
    @discardableResult
    public func execute(_ source: String, maxWait: TimeInterval = 2.4, reportTimeout: Bool = true) -> (success: Bool, output: String?) {
        let (ok, out) = run(source, maxWait: maxWait, reportTimeout: reportTimeout)
        return (ok, out)
    }
}
