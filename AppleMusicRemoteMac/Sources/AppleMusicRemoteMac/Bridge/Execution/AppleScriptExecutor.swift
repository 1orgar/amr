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
    private let workerLock = NSLock()
    private var workerGeneration: UInt64 = 1
    private var workerQueue = DispatchQueue(label: "com.amr.applescript.worker.1", qos: .userInitiated)

    private final class ExecutionBox: @unchecked Sendable {
        var descriptor: NSAppleEventDescriptor?
        var errorNumber: Int = 0
        var errorMessage: String?
    }

    private init() {}

    /// Executes an AppleScript source and returns the raw NSAppleEventDescriptor.
    /// Safely prevents deadlocks by:
    /// 1. Confining each NSAppleScript's lifecycle (init, compile, execute, dealloc) to a single thread inside an autoreleasepool (per Apple TN2084).
    /// 2. Enforcing a hard 3.8s wall-clock watchdog with automatic worker queue rotation if macOS OpenScripting / AESendMessage ever stalls.
    public func executeDescriptor(_ source: String) -> NSAppleEventDescriptor? {
        if PlaybackRouter.shared.isTestingEnvironment {
            return nil
        }
        if (!MusicAppProvider.shared.isMusicAppRunning || !MusicAppLifecycleManager.shared.isHealthy) && source.contains("tell application \"Music\"") {
            return nil
        }

        guard lock.lock(before: Date().addingTimeInterval(3.5)) else {
            NSLog("[AppleScriptExecutor] Lock acquisition timeout (contended)")
            return nil
        }
        defer { lock.unlock() }

        var timedSource = source
        if !timedSource.contains("with timeout") {
            if let tellRange = timedSource.range(of: "tell application \"Music\""),
               let endTellRange = timedSource.range(of: "end tell", options: .backwards),
               tellRange.upperBound <= endTellRange.lowerBound {
                let prefix = timedSource[..<tellRange.upperBound]
                let body = timedSource[tellRange.upperBound..<endTellRange.lowerBound]
                let suffix = timedSource[endTellRange.lowerBound...]
                timedSource = "\(prefix)\nwith timeout of 3 seconds\(body)\nend timeout\n\(suffix)"
            } else {
                timedSource = "with timeout of 3 seconds\n" + timedSource + "\nend timeout"
            }
        }

        let (currentWorker, capturedGen): (DispatchQueue, UInt64) = {
            workerLock.lock()
            defer { workerLock.unlock() }
            return (workerQueue, workerGeneration)
        }()

        let box = ExecutionBox()
        let sema = DispatchSemaphore(value: 0)
        let scriptText = timedSource

        currentWorker.async {
            autoreleasepool {
                var error: NSDictionary?
                let script = NSAppleScript(source: scriptText)
                let desc = script?.executeAndReturnError(&error)
                if let err = error {
                    box.errorMessage = err[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    box.errorNumber = err[NSAppleScript.errorNumber] as? Int ?? 0
                } else {
                    box.descriptor = desc
                }
            }
            sema.signal()
        }

        if sema.wait(timeout: .now() + 3.8) == .timedOut {
            workerLock.lock()
            if workerGeneration == capturedGen {
                workerGeneration &+= 1
                workerQueue = DispatchQueue(label: "com.amr.applescript.worker.\(workerGeneration)", qos: .userInitiated)
            }
            let newGen = workerGeneration
            workerLock.unlock()
            NSLog("[AppleScriptExecutor] ⚠️ Worker execution timed out (>3.8s) — rotated worker queue to gen=%llu", newGen)
            MusicAppLifecycleManager.shared.reportIPCTimeout()
            return nil
        }

        if let msg = box.errorMessage {
            let errNum = box.errorNumber
            NSLog("[AppleScriptExecutor] Error (\(errNum)): \(msg)")
            if errNum == -1712 || msg.contains("timed out") || msg.contains("AppleEvent timed out") {
                MusicAppLifecycleManager.shared.reportIPCTimeout()
            }
            return nil
        }
        return box.descriptor
    }

    /// Executes AppleScript and returns (success, stringValue).
    public func run(_ source: String) -> (Bool, String?) {
        if let desc = executeDescriptor(source) {
            return (true, desc.stringValue)
        }
        return (false, nil)
    }

    /// Convenience wrapper returning (success: Bool, output: String?).
    @discardableResult
    public func execute(_ source: String) -> (success: Bool, output: String?) {
        let (ok, out) = run(source)
        return (ok, out)
    }
}
