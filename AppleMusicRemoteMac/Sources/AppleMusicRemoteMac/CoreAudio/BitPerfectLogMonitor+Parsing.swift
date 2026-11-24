//
//  BitPerfectLogMonitor+Parsing.swift
//  AppleMusicRemoteMac
//
//  NDJSON Unified Log Stream Buffering, Regex Parsers & Sample Rate Normalization
//

import Foundation

extension BitPerfectLogMonitor {

    // MARK: - Stream Processing

    internal func drainBuffer() {
        let totalCount = buffer.count
        while bufferReadOffset < totalCount {
            guard let nlIndex = buffer[bufferReadOffset..<totalCount].firstIndex(of: 0x0A) else {
                break
            }
            if nlIndex > bufferReadOffset {
                var lineEnd = nlIndex
                if buffer[lineEnd - 1] == 0x0D {
                    lineEnd -= 1
                }
                if lineEnd > bufferReadOffset {
                    let lineSlice = buffer[bufferReadOffset..<lineEnd]
                    if let line = String(data: lineSlice, encoding: .utf8), !line.isEmpty {
                        handleLine(line)
                    }
                }
            }
            bufferReadOffset = nlIndex + 1
        }

        if bufferReadOffset == buffer.count {
            if !buffer.isEmpty {
                buffer.removeAll(keepingCapacity: buffer.count <= 65536)
            }
            bufferReadOffset = 0
        } else if bufferReadOffset >= 8192 {
            buffer.removeSubrange(0..<bufferReadOffset)
            bufferReadOffset = 0
        }
    }

    internal func handleLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if line.first == "{",
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let message = (json["eventMessage"] as? String)
                ?? (json["message"] as? String)
                ?? (json["formattedMessage"] as? String)

            if let msg = message {
                parseMessage(msg)
            }
        } else {
            parseMessage(line)
        }
    }

    internal func parseMessage(_ message: String) {
        if message.hasPrefix("Filtering the log data using") {
            return
        }
        let fullRange = NSRange(message.startIndex..<message.endIndex, in: message)

        // 0a. MediaPlaybackCore Smart Transition / Overlap immediate start event (fires ~1.4s before DistributedNotification!)
        if Self.smartTransitionBeginPattern.firstMatch(in: message, options: [], range: fullRange) != nil {
            NSLog("[BitPerfectLogMonitor] ⚡️ Music.app transition begin event detected: %@", message)
            let cb = self.onSmartTransitionBegan
            cb?()
            if !PlaybackRouter.shared.isTestingEnvironment {
                QueueManager.shared.handleImmediateSmartTransitionBegan()
            }
            return
        }

        // 0b. MediaPlaybackCore pre-calculated Smart Transition / Dead-Air Removal start timestamp (logged 10+s in advance)
        if let match = Self.smartTransitionSchedulePattern.firstMatch(in: message, options: [], range: fullRange),
           match.numberOfRanges > 1,
           let secRange = Range(match.range(at: 1), in: message),
           let startSec = Double(message[secRange]) {
            if startSec > 4.0 {
                let changed = PlaybackStateStore.shared.withLock { () -> Bool in
                    let prev = PlaybackStateStore.shared.scheduledSmartTransitionStart
                    if let p = prev, abs(p - startSec) < 0.05 {
                        return false
                    }
                    PlaybackStateStore.shared.scheduledSmartTransitionStart = startSec
                    return true
                }
                if changed {
                    NSLog("[BitPerfectLogMonitor] 🎯 Music.app scheduled Smart Transition / Dead-Air cutoff at %.3fs", startSec)
                }
                let cb = self.onSmartTransitionScheduleDetected
                cb?(startSec)
                if !PlaybackRouter.shared.isTestingEnvironment {
                    QueueManager.shared.handleSmartTransitionScheduleDetected(startSeconds: startSec)
                }
            }
            return
        }

        let lower = message.lowercased()

        // 1. Strict negative filter: immediately drop feedback loops, hardware rates, pre-buffering
        for ignored in Self.ignoredSubstrings {
            if lower.contains(ignored) {
                return
            }
        }

        // 2. Authoritative ALAC Decoder log (rate + bit depth)
        if let match = Self.alacDecoderPattern.firstMatch(in: message, options: [], range: fullRange),
           match.numberOfRanges > 2,
           let rateRange = Range(match.range(at: 1), in: message),
           let depthRange = Range(match.range(at: 2), in: message),
           let rawRate = Double(message[rateRange]),
           let rate = normalizeRate(rawRate),
           let rawDepth = Int(message[depthRange]) {
            let depth = rawDepth > 0 ? rawDepth : (rate >= 48000.0 ? 24 : 16)
            sampleRateDetected(rate, bitDepth: depth, isAuthoritative: true, isLossless: true, reason: "ALACDecoder: \(message)")
            return
        }

        // 3. FigPlaybackReport (rate + bit depth)
        if let match = Self.figPlaybackReportPattern.firstMatch(in: message, options: [], range: fullRange),
           match.numberOfRanges > 2,
           let rateRange = Range(match.range(at: 1), in: message),
           let depthRange = Range(match.range(at: 2), in: message),
           let rawRate = Double(message[rateRange]),
           let rate = normalizeRate(rawRate),
           let rawDepth = Int(message[depthRange]) {
            let isAAC = lower.contains("qaac") || lower.contains("aac")
            if isAAC {
                if isFormatLockedForCurrentTrack && currentIsLossless {
                    return
                }
                sampleRateDetected(rate, bitDepth: 16, isAuthoritative: false, isLossless: false, reason: "FigPlaybackReport(AAC): \(message)")
                return
            }
            // Ignore preliminary 0-bit / 16-bit FigStreamPlayer reports if already locked on 24-bit ALAC, or normalize 0-bit reports
            if rawDepth <= 0 {
                if isFormatLockedForCurrentTrack {
                    return
                }
                let inferredDepth = (rate >= 48000.0) ? 24 : 16
                sampleRateDetected(rate, bitDepth: inferredDepth, isAuthoritative: false, isLossless: true, reason: "FigPlaybackReport(0-bit): \(message)")
                return
            }
            if rawDepth == 16 && isFormatLockedForCurrentTrack && currentDetectedBitDepth == 24 {
                return
            }
            sampleRateDetected(rate, bitDepth: rawDepth, isAuthoritative: true, isLossless: true, reason: "FigPlaybackReport: \(message)")
            return
        }

        // 4. CoreMedia AudioQueue build (generic preliminary)
        if let match = Self.audioQueueBuildPattern.firstMatch(in: message, options: [], range: fullRange),
           match.numberOfRanges > 1,
           let rateRange = Range(match.range(at: 1), in: message),
           let rawRate = Double(message[rateRange]),
           let rate = normalizeRate(rawRate) {
            let isAAC = lower.contains("aac")
            let depth = isAAC ? 16 : ((rate >= 48000.0) ? 24 : 16)
            sampleRateDetected(rate, bitDepth: depth, isAuthoritative: false, isLossless: !isAAC, reason: "subaq_buildCAAudioQueue: \(message)")
            return
        }

        // 5. CoreMedia AudioQueue startup sync (generic preliminary)
        if let match = Self.audioQueueSyncPattern.firstMatch(in: message, options: [], range: fullRange),
           match.numberOfRanges > 1,
           let rateRange = Range(match.range(at: 1), in: message),
           let rawRate = Double(message[rateRange]),
           let rate = normalizeRate(rawRate) {
            let depth = (rate >= 48000.0) ? 24 : 16
            sampleRateDetected(rate, bitDepth: depth, isAuthoritative: false, isLossless: true, reason: "subaq_performStartupSync: \(message)")
            return
        }

        // 6. Generic decoder (AAC, MP3, etc. - preliminary)
        if let match = Self.genericDecoderPattern.firstMatch(in: message, options: [], range: fullRange),
           match.numberOfRanges > 1,
           let rateRange = Range(match.range(at: 1), in: message),
           let rawRate = Double(message[rateRange]),
           let rate = normalizeRate(rawRate) {
            let isLossy = lower.contains("aac") || lower.contains("mp3")
            let depth = isLossy ? 16 : ((rate >= 48000.0) ? 24 : 16)
            sampleRateDetected(rate, bitDepth: depth, isAuthoritative: false, isLossless: !isLossy, reason: "GenericDecoder: \(message)")
            return
        }
    }

    // Negative filter: drop hardware updates, pre-buffering, and non-playback logs
    internal static let ignoredSubstrings: [String] = [
        "mdevicesamplerate",
        "adapttodevice",
        "default-output",
        "auhal",
        "memixerchannel",
        "aqme",
        "output stream",
        "updateformat",
        "updatestreamformat",
        "output render format",
        "devicelatency",
        "audio device latency",
        "priming duration",
        "raw duration",
        "pts",
        "itemoverlap",
        "figplayeroverlap",
        "speedramp",
        "timebase",
        "alternatefilter",
        "mediaformatinfo",
        "activeformat:",
        "qc+3"
    ]

    // MARK: - Regex Parsers for Active Playback

    // Authoritative ALAC Decoder: gives both exact sample rate and bit depth of actively decoded stream
    internal static let alacDecoderPattern = try! NSRegularExpression(
        pattern: #"(?i)ACAppleLosslessDecoder.*Input format:\s*\d+\s*ch,\s*([0-9]+(?:\.[0-9]+)?)\s*Hz,\s*alac(?:\s*\([^)]*\))?\s*from\s*([0-9]+)-bit"#,
        options: []
    )

    // Authoritative FigStreamPlayer active playback report: gives sample rate and bit depth
    internal static let figPlaybackReportPattern = try! NSRegularExpression(
        pattern: #"(?i)fpfs_ReportAudioPlaybackThroughFigLog:.*\[SampleRate\s*([0-9]+)\].*\[BitDepth\s*([0-9]+)\]"#,
        options: []
    )

    // Authoritative AudioQueue creation when active audio pipeline is constructed
    internal static let audioQueueBuildPattern = try! NSRegularExpression(
        pattern: #"(?i)subaq_buildCAAudioQueue:.*(?:Creating|Created new) AudioQueue with format:'(?:qlac|alac|lpcm|aac\s*)',.*sampleRate:([0-9]+)"#,
        options: []
    )

    // Authoritative AudioQueue startup sync when samples begin playback
    internal static let audioQueueSyncPattern = try! NSRegularExpression(
        pattern: #"(?i)faq->srcASBD->mSampleRate\s*([0-9]+)"#,
        options: []
    )

    // Authoritative generic decoder for lossy / other formats (AAC, MP3)
    internal static let genericDecoderPattern = try! NSRegularExpression(
        pattern: #"(?i)Input format:\s*\d+\s*ch,\s*([0-9]+(?:\.[0-9]+)?)\s*Hz,\s*(?:'?(?:aac|mp3|alac|qlac)'?)"#,
        options: []
    )

    // MediaPlaybackCore pre-calculated Smart Transition / Dead-Air Removal start time (seconds)
    internal static let smartTransitionSchedulePattern = try! NSRegularExpression(
        pattern: #"(?:Observe transition start|overlapStartSourceTime):\s*([0-9]+(?:\.[0-9]+)?)"#,
        options: []
    )

    // MediaPlaybackCore immediate Smart Transition / Overlapped playback start signal
    internal static let smartTransitionBeginPattern = try! NSRegularExpression(
        pattern: #"(?:smartTransitionWillBegin|overlappedPlaybackWillBegin)"#,
        options: []
    )

    public func normalizeRate(_ val: Double) -> Double? {
        guard val > 0 else { return nil }
        var hz = val
        if val < 1000.0 {
            hz = val * 1000.0
        }

        // Snap to nearest standard rate if within 300 Hz
        if let nearest = Self.standardRates.min(by: { abs($0 - hz) < abs($1 - hz) }), abs(nearest - hz) <= 300.0 {
            return nearest
        }
        return hz
    }

    // MARK: - Child `/usr/bin/log` Orphan Prevention (SIGTERM & Crash Recovery)

    private static var logStreamPIDFileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Logs/AppleMusicRemoteMac/.logstream.pid")
    }

    internal func writeLogStreamPIDFile(_ pid: pid_t) {
        guard pid > 1 else { return }
        let url = Self.logStreamPIDFileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let fd = Darwin.open(
            url.path,
            O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard fd >= 0 else { return }
        _ = "\(pid)\n".withCString { ptr in
            Darwin.write(fd, ptr, strlen(ptr))
        }
        Darwin.close(fd)
    }

    internal func clearLogStreamPIDFile() {
        try? FileManager.default.removeItem(at: Self.logStreamPIDFileURL)
    }

    internal func reapPreviousLogStreamPIDFile() {
        let url = Self.logStreamPIDFileURL
        guard let raw = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let oldPID = Int32(raw),
              oldPID > 1,
              oldPID != getpid() else {
            clearLogStreamPIDFile()
            return
        }
        clearLogStreamPIDFile()

        // Verify via `proc_pidpath` that `oldPID` is genuinely `/usr/bin/log` before signaling
        var pathBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let ret = proc_pidpath(oldPID, &pathBuf, UInt32(pathBuf.count))
        if ret > 0 {
            let execPath = String(cString: pathBuf)
            if execPath == "/usr/bin/log" {
                kill(oldPID, SIGTERM)
                queue.asyncAfter(deadline: .now() + 0.15) {
                    var checkBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
                    if proc_pidpath(oldPID, &checkBuf, UInt32(checkBuf.count)) > 0,
                       String(cString: checkBuf) == "/usr/bin/log" {
                        kill(oldPID, SIGKILL)
                    }
                }
            }
        }
    }

    internal func installSignalCleanupIfNeeded() {
        guard sigtermSource == nil else { return }
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)

        let handleExitSignal: @Sendable () -> Void = { [weak self] in
            if let proc = self?.process, proc.isRunning {
                let pid = proc.processIdentifier
                proc.terminate()
                kill(pid, SIGKILL)
            }
            self?.clearLogStreamPIDFile()
            Darwin._exit(0)
        }

        let termSrc = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
        termSrc.setEventHandler(handler: handleExitSignal)
        termSrc.resume()
        sigtermSource = termSrc

        let intSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: queue)
        intSrc.setEventHandler(handler: handleExitSignal)
        intSrc.resume()
        sigintSource = intSrc
    }
}
