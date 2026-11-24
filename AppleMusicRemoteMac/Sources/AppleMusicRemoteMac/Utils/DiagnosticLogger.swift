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
    private let clientRateLock = NSLock()
    private var clientLogTimestamps: [TimeInterval] = []
    private let maxGlobalClientLogsPerWindow: Int = 30
    private let clientLogWindowSeconds: TimeInterval = 10.0

    private var _isEnabled: Bool
    private var isPipeInstalled: Bool = false
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
                         "[\(Self.isoTimestamp())] Diagnostic File Logging ENABLED — Apple Music Remote v3.0.0\n" +
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
        let now = Date().timeIntervalSince1970
        let allowed: Bool = {
            clientRateLock.lock()
            defer { clientRateLock.unlock() }
            clientLogTimestamps.removeAll { now - $0 >= clientLogWindowSeconds }
            guard clientLogTimestamps.count < maxGlobalClientLogsPerWindow else {
                return false
            }
            clientLogTimestamps.append(now)
            return true
        }()
        guard allowed else { return }

        let safeDevice = Self.sanitizeLogToken(device, maxChars: 64)
        let safeLevel = Self.sanitizeLogToken(level, maxChars: 16).uppercased()
        let safeMsg = Self.sanitizeLogToken(message, maxChars: 500)
        guard !safeMsg.isEmpty else { return }
        NSLog("[ClientLog][%@][%@] %@", safeDevice, safeLevel, safeMsg)
    }

    private static func sanitizeLogToken(_ raw: String, maxChars: Int) -> String {
        var out = ""
        out.reserveCapacity(min(raw.count, maxChars))
        var count = 0
        for scalar in raw.unicodeScalars {
            if count >= maxChars { break }
            if scalar == "\r" || scalar == "\n" || scalar == "\t" {
                out.unicodeScalars.append(" ")
            } else if scalar.value < 0x20 || scalar.value == 0x7F {
                continue
            } else {
                out.unicodeScalars.append(scalar)
            }
            count += 1
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func clearLog() {
        queue.sync {
            if logFileFD >= 0 {
                Darwin.close(logFileFD)
                logFileFD = -1
            }
            if !Self.isSymlinkPath(logFileURL.path) {
                try? FileManager.default.removeItem(at: logFileURL)
            }
            if !Self.isSymlinkPath(oldLogFileURL.path) {
                try? FileManager.default.removeItem(at: oldLogFileURL)
            }
            if isEnabled {
                ensureLogDirectoryAndFileLocked()
                let header = "[\(Self.isoTimestamp())] Log cleared by user.\n"
                writeRawToLogFileLocked(header)
            }
        }
    }

    public func logFileSizeDescription() -> String {
        var st = Darwin.stat()
        guard Darwin.lstat(logFileURL.path, &st) == 0,
              (st.st_mode & S_IFMT) == S_IFREG else {
            return "0 КБ"
        }
        let size = UInt64(max(0, st.st_size))
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
        guard !Self.isSymlinkPath(logFileURL.path) else { return }
        NSWorkspace.shared.open(logFileURL)
    }

    @MainActor
    public func revealInFinder() {
        queue.sync {
            ensureLogDirectoryAndFileLocked()
        }
        guard !Self.isSymlinkPath(logFileURL.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
    }

    // MARK: - Internal POSIX Pipe Tee & Rotation

    private static func isSymlinkPath(_ path: String) -> Bool {
        var st = Darwin.stat()
        guard Darwin.lstat(path, &st) == 0 else { return false }
        return (st.st_mode & S_IFMT) == S_IFLNK
    }

    private func ensureLogDirectoryAndFileLocked() {
        guard !Self.isSymlinkPath(logDirectoryURL.path) else { return }
        try? FileManager.default.createDirectory(
            at: logDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        _ = Darwin.chmod(logDirectoryURL.path, S_IRWXU)

        if logFileFD < 0 {
            guard !Self.isSymlinkPath(logFileURL.path) else { return }
            let fd = Darwin.open(
                logFileURL.path,
                O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            )
            guard fd >= 0 else { return }
            var st = Darwin.stat()
            if Darwin.fstat(fd, &st) != 0 || (st.st_mode & S_IFMT) != S_IFREG {
                Darwin.close(fd)
                return
            }
            _ = Darwin.fchmod(fd, S_IRUSR | S_IWUSR)
            logFileFD = fd
        }
    }

    private func rotateIfNeededLocked() {
        guard logFileFD >= 0 else { return }
        var st = Darwin.stat()
        guard Darwin.fstat(logFileFD, &st) == 0,
              (st.st_mode & S_IFMT) == S_IFREG,
              UInt64(max(0, st.st_size)) >= maxLogFileBytes else {
            return
        }
        Darwin.close(logFileFD)
        logFileFD = -1
        guard !Self.isSymlinkPath(oldLogFileURL.path),
              !Self.isSymlinkPath(logFileURL.path) else {
            return
        }
        try? FileManager.default.removeItem(at: oldLogFileURL)
        if (try? FileManager.default.moveItem(at: logFileURL, to: oldLogFileURL)) != nil {
            _ = Darwin.chmod(oldLogFileURL.path, S_IRUSR | S_IWUSR)
        }
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

        // Only pipeReadFD is non-blocking so DispatchSourceRead drains cleanly;
        // pipeWriteFD (stdout/stderr) stays blocking so bursts never drop output with EAGAIN.
        let readFlags = Darwin.fcntl(pipeReadFD, F_GETFL, 0)
        if readFlags >= 0 {
            _ = Darwin.fcntl(pipeReadFD, F_SETFL, readFlags | O_NONBLOCK)
        }

        origStderrFD = Darwin.dup(STDERR_FILENO)
        if origStderrFD < 0 {
            origStderrFD = Darwin.dup(STDOUT_FILENO)
        }
        if origStderrFD >= 0 {
            _ = Darwin.fcntl(origStderrFD, F_SETFD, FD_CLOEXEC)
        }

        Darwin.fflush(stdout)
        Darwin.fflush(stderr)
        _ = Darwin.dup2(pipeWriteFD, STDOUT_FILENO)
        _ = Darwin.dup2(pipeWriteFD, STDERR_FILENO)
        if pipeWriteFD > STDERR_FILENO {
            Darwin.close(pipeWriteFD)
            pipeWriteFD = -1
        }

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
                // 1. Always forward to original stderr so terminal / launchd redirection stays intact
                if origStderrFD >= 0 {
                    _ = Darwin.write(origStderrFD, &buffer, bytesRead)
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
