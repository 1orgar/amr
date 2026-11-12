//
//  DiagnosticLogger.swift
//  AppleMusicRemoteMac
//
//  Persistent file logger that captures all NSLog / stdout / stderr output
//  into ~/Library/Logs/AppleMusicRemoteMac/amr.log when enabled in Settings.
//

import AppKit
import Darwin
import Foundation

public final class DiagnosticLogger: @unchecked Sendable {
    public static let shared = DiagnosticLogger()

    private let userDefaultsKey = "AMRFileLoggingEnabled"
    private let maxLogFileBytes: UInt64 = 5 * 1024 * 1024 // 5 MB rotation threshold
    private let queue = DispatchQueue(label: "com.amr.diagnostic.logger", qos: .utility)
    private let stateLock = NSLock()

    private var _isEnabled: Bool
    private var isPipeInstalled: Bool = false
    private var origStdoutFD: Int32 = -1
    private var origStderrFD: Int32 = -1
    private var pipeReadFD: Int32 = -1
    private var pipeWriteFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var logFileFD: Int32 = -1
    private var bytesWrittenSinceCheck: Int = 0

    public let logDirectoryURL: URL
    public let logFileURL: URL
    public let oldLogFileURL: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let logsDir = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("AppleMusicRemoteMac", isDirectory: true)
        self.logDirectoryURL = logsDir
        self.logFileURL = logsDir.appendingPathComponent("amr.log", isDirectory: false)
        self.oldLogFileURL = logsDir.appendingPathComponent("amr.old.log", isDirectory: false)

        if UserDefaults.standard.object(forKey: userDefaultsKey) == nil {
            self._isEnabled = false
        } else {
            self._isEnabled = UserDefaults.standard.bool(forKey: userDefaultsKey)
        }
    }

    public var isEnabled: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _isEnabled
        }
        set {
            stateLock.lock()
            let changed = (_isEnabled != newValue)
            _isEnabled = newValue
            stateLock.unlock()

            UserDefaults.standard.set(newValue, forKey: userDefaultsKey)
            guard changed else { return }

            if newValue {
                enableLogging()
            } else {
                disableLogging()
            }
        }
    }

    public func setupAtLaunch() {
        if isEnabled {
            enableLogging()
        }
    }

    private func enableLogging() {
        queue.sync {
            ensureLogDirectoryAndFileLocked()
            installStdioTeeIfNeededLocked()
            let banner = "\n================================================================================\n" +
                         "[\(Self.isoTimestamp())] Diagnostic File Logging ENABLED — Apple Music Remote v2.5.0\n" +
                         "Log File: \(logFileURL.path)\n" +
                         "================================================================================\n"
            writeRawToLogFileLocked(banner)
        }
    }

    private func disableLogging() {
        queue.sync {
            let footer = "[\(Self.isoTimestamp())] Diagnostic File Logging DISABLED by user.\n"
            writeRawToLogFileLocked(footer)
            if logFileFD >= 0 {
                Darwin.close(logFileFD)
                logFileFD = -1
            }
        }
    }

    public func logClientEvent(device: String, level: String, message: String) {
        NSLog("[ClientLog][%@][%@] %@", device, level.uppercased(), message)
    }

    public func clearLog() {
        queue.sync {
            if logFileFD >= 0 {
                Darwin.close(logFileFD)
                logFileFD = -1
            }
            try? FileManager.default.removeItem(at: logFileURL)
            try? FileManager.default.removeItem(at: oldLogFileURL)
            if isEnabled {
                ensureLogDirectoryAndFileLocked()
                let header = "[\(Self.isoTimestamp())] Log cleared by user.\n"
                writeRawToLogFileLocked(header)
            }
        }
    }

    public func logFileSizeDescription() -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let size = attrs[.size] as? UInt64 else {
            return "0 КБ"
        }
        if size < 1024 {
            return "\(size) Б"
        } else if size < 1024 * 1024 {
            return String(format: "%.1f КБ", Double(size) / 1024.0)
        } else {
            return String(format: "%.2f МБ", Double(size) / (1024.0 * 1024.0))
        }
    }

    @MainActor
    public func openLogFile() {
        queue.sync {
            ensureLogDirectoryAndFileLocked()
        }
        NSWorkspace.shared.open(logFileURL)
    }

    @MainActor
    public func revealInFinder() {
        queue.sync {
            ensureLogDirectoryAndFileLocked()
        }
        NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
    }

    // MARK: - Internal POSIX Pipe Tee & Rotation

    private func ensureLogDirectoryAndFileLocked() {
        try? FileManager.default.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
        if logFileFD < 0 {
            logFileFD = Darwin.open(
                logFileURL.path,
                O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC,
                S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH
            )
        }
    }

    private func rotateIfNeededLocked() {
        guard logFileFD >= 0 else { return }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let size = attrs[.size] as? UInt64,
              size >= maxLogFileBytes else {
            return
        }
        Darwin.close(logFileFD)
        logFileFD = -1
        try? FileManager.default.removeItem(at: oldLogFileURL)
        try? FileManager.default.moveItem(at: logFileURL, to: oldLogFileURL)
        ensureLogDirectoryAndFileLocked()
        let rotatedNotice = "[\(Self.isoTimestamp())] Log rotated at 5 MB (previous saved to amr.old.log)\n"
        writeRawToLogFileLocked(rotatedNotice)
    }

    private func writeRawToLogFileLocked(_ string: String) {
        guard logFileFD >= 0, let data = string.data(using: .utf8) else { return }
        data.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            _ = Darwin.write(logFileFD, base, rawBuf.count)
        }
    }

    private func installStdioTeeIfNeededLocked() {
        guard !isPipeInstalled else { return }

        var fds: [Int32] = [0, 0]
        guard Darwin.pipe(&fds) == 0 else { return }
        pipeReadFD = fds[0]
        pipeWriteFD = fds[1]

        _ = Darwin.fcntl(pipeReadFD, F_SETFD, FD_CLOEXEC)
        _ = Darwin.fcntl(pipeWriteFD, F_SETFD, FD_CLOEXEC)

        let flags = Darwin.fcntl(pipeReadFD, F_GETFL, 0)
        if flags >= 0 {
            _ = Darwin.fcntl(pipeReadFD, F_SETFL, flags | O_NONBLOCK)
        }

        origStdoutFD = Darwin.dup(STDOUT_FILENO)
        origStderrFD = Darwin.dup(STDERR_FILENO)
        if origStdoutFD >= 0 { _ = Darwin.fcntl(origStdoutFD, F_SETFD, FD_CLOEXEC) }
        if origStderrFD >= 0 { _ = Darwin.fcntl(origStderrFD, F_SETFD, FD_CLOEXEC) }

        Darwin.fflush(stdout)
        Darwin.fflush(stderr)
        _ = Darwin.dup2(pipeWriteFD, STDOUT_FILENO)
        _ = Darwin.dup2(pipeWriteFD, STDERR_FILENO)

        let source = DispatchSource.makeReadSource(fileDescriptor: pipeReadFD, queue: queue)
        source.setEventHandler { [weak self] in
            self?.handlePipeReadableLocked()
        }
        source.resume()
        readSource = source
        isPipeInstalled = true
    }

    private func handlePipeReadableLocked() {
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let bytesRead = Darwin.read(pipeReadFD, &buffer, buffer.count)
            if bytesRead > 0 {
                // 1. Always forward to original stderr (or stdout) so terminal / daemon redirection stays intact
                let targetOrigFD = origStderrFD >= 0 ? origStderrFD : origStdoutFD
                if targetOrigFD >= 0 {
                    _ = Darwin.write(targetOrigFD, &buffer, bytesRead)
                }

                // 2. If file logging is enabled, write to ~/Library/Logs/AppleMusicRemoteMac/amr.log
                if isEnabled {
                    if logFileFD < 0 {
                        ensureLogDirectoryAndFileLocked()
                    }
                    if logFileFD >= 0 {
                        _ = Darwin.write(logFileFD, &buffer, bytesRead)
                        bytesWrittenSinceCheck += bytesRead
                        if bytesWrittenSinceCheck >= 65536 {
                            bytesWrittenSinceCheck = 0
                            rotateIfNeededLocked()
                        }
                    }
                }
            } else {
                break
            }
        }
    }

    private static func isoTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
