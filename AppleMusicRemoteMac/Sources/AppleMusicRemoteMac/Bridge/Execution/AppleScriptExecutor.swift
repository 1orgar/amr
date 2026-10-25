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

    private init() {}

    /// Executes an AppleScript source and returns the raw NSAppleEventDescriptor.
    /// Safely prevents deadlocks by using timed lock acquisition and injecting
    /// IPC timeouts directly inside the `tell application "Music"` block.
    public func executeDescriptor(_ source: String) -> NSAppleEventDescriptor? {
        if PlaybackRouter.shared.isTestingEnvironment {
            return nil
        }
        if !MusicAppProvider.shared.isMusicAppRunning && source.contains("tell application \"Music\"") {
            return nil
        }

        guard lock.lock(before: Date().addingTimeInterval(4.0)) else {
            NSLog("[AppleScriptExecutor] Lock acquisition timeout (contended)")
            return nil
        }
        defer { lock.unlock() }

        var timedSource = source
        if !timedSource.contains("with timeout") {
            if let tellRange = timedSource.range(of: "tell application \"Music\""),
               let endTellRange = timedSource.range(of: "end tell", options: .backwards) {
                let prefix = timedSource[..<tellRange.upperBound]
                let body = timedSource[tellRange.upperBound..<endTellRange.lowerBound]
                let suffix = timedSource[endTellRange.lowerBound...]
                timedSource = "\(prefix)\nwith timeout of 3 seconds\(body)\nend timeout\n\(suffix)"
            } else {
                timedSource = "with timeout of 3 seconds\n" + timedSource + "\nend timeout"
            }
        }

        var error: NSDictionary?
        let script = NSAppleScript(source: timedSource)
        let descriptor = script?.executeAndReturnError(&error)
        if let err = error {
            let msg = err[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            NSLog("[AppleScriptExecutor] Error: \(msg)")
            return nil
        }
        return descriptor
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
