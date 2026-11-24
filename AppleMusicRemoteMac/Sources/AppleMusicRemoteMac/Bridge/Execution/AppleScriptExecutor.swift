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
    public static let maxPinnedScripts = 24
    public static let maxDynamicScripts = 48
    /// Strictly confined to `workerQueue` per Apple TN2084.
    private var pinnedScripts: [String: NSAppleScript] = [:]
    private var dynamicScripts: [String: NSAppleScript] = [:]
    private var dynamicScriptOrder: [String] = []
    private var scriptHitCounts: [String: Int] = [:]
    private var testPinnedKeys = Set<String>()
    private var testDynamicKeys = Set<String>()
    private var testDynamicOrder: [String] = []
    private let testCacheLock = NSLock()

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

        let scriptText = Self.wrapWithDefaultTimeoutIfNeeded(source)
        let shouldCacheCompiled = scriptText.utf8.count <= 2048

        let box = ExecutionBox()
        let sema = DispatchSemaphore(value: 0)

        workerQueue.async { [weak self] in
            autoreleasepool {
                var error: NSDictionary?
                let script: NSAppleScript?
                if shouldCacheCompiled, let self = self {
                    let hits = (self.scriptHitCounts[scriptText] ?? 0) + 1
                    if self.scriptHitCounts.count > 256 && self.scriptHitCounts[scriptText] == nil {
                        self.scriptHitCounts.removeAll(keepingCapacity: true)
                    }
                    self.scriptHitCounts[scriptText] = hits

                    if let pinned = self.pinnedScripts[scriptText] {
                        script = pinned
                    } else if let dyn = self.dynamicScripts[scriptText] {
                        if hits >= 2 && self.pinnedScripts.count < Self.maxPinnedScripts {
                            self.dynamicScripts.removeValue(forKey: scriptText)
                            self.dynamicScriptOrder.removeAll { $0 == scriptText }
                            self.pinnedScripts[scriptText] = dyn
                        }
                        script = dyn
                    } else {
                        let fresh = NSAppleScript(source: scriptText)
                        if let fresh = fresh {
                            if hits >= 2 && self.pinnedScripts.count < Self.maxPinnedScripts {
                                self.pinnedScripts[scriptText] = fresh
                            } else {
                                while self.dynamicScripts.count >= Self.maxDynamicScripts, !self.dynamicScriptOrder.isEmpty {
                                    let oldest = self.dynamicScriptOrder.removeFirst()
                                    self.dynamicScripts.removeValue(forKey: oldest)
                                }
                                self.dynamicScripts[scriptText] = fresh
                                self.dynamicScriptOrder.append(scriptText)
                            }
                        }
                        script = fresh
                    }
                } else {
                    script = NSAppleScript(source: scriptText)
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

    internal static func wrapWithDefaultTimeoutIfNeeded(_ source: String) -> String {
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
        return timedSource
    }

    /// Pre-compiles and pins a recurring script (`pulseScript`, status polling) so dynamic one-off scripts never evict it.
    public func pinScript(_ source: String) {
        let wrapped = Self.wrapWithDefaultTimeoutIfNeeded(source)
        guard wrapped.utf8.count <= 2048 else { return }
        if PlaybackRouter.shared.isTestingEnvironment {
            testCacheLock.withLock {
                if testPinnedKeys.count < Self.maxPinnedScripts {
                    testPinnedKeys.insert(wrapped)
                    testDynamicKeys.remove(wrapped)
                    testDynamicOrder.removeAll { $0 == wrapped }
                }
            }
            return
        }
        workerQueue.async { [weak self] in
            guard let self = self, self.pinnedScripts[wrapped] == nil else { return }
            guard self.pinnedScripts.count < Self.maxPinnedScripts else { return }
            if let existingDyn = self.dynamicScripts.removeValue(forKey: wrapped) {
                self.dynamicScriptOrder.removeAll { $0 == wrapped }
                self.pinnedScripts[wrapped] = existingDyn
            } else if let compiled = NSAppleScript(source: wrapped) {
                _ = compiled.compileAndReturnError(nil)
                self.pinnedScripts[wrapped] = compiled
            }
        }
    }

    internal func simulateDynamicScriptInsertionForTesting(_ source: String) {
        let wrapped = Self.wrapWithDefaultTimeoutIfNeeded(source)
        testCacheLock.withLock {
            guard !testPinnedKeys.contains(wrapped), !testDynamicKeys.contains(wrapped) else { return }
            while testDynamicKeys.count >= Self.maxDynamicScripts, !testDynamicOrder.isEmpty {
                let oldest = testDynamicOrder.removeFirst()
                testDynamicKeys.remove(oldest)
            }
            testDynamicKeys.insert(wrapped)
            testDynamicOrder.append(wrapped)
        }
    }

    internal func isScriptCachedForTesting(_ source: String) -> (pinned: Bool, dynamic: Bool) {
        let wrapped = Self.wrapWithDefaultTimeoutIfNeeded(source)
        return testCacheLock.withLock {
            (testPinnedKeys.contains(wrapped), testDynamicKeys.contains(wrapped))
        }
    }
}
