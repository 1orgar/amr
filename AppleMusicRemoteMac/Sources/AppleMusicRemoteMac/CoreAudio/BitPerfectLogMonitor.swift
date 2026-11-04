//
//  BitPerfectLogMonitor.swift
//  AppleMusicRemoteMac
//
//  Real-time Bit-Perfect Sample Rate Detection via macOS Unified Log Stream
//  Inspired by Choritsu (jcongaku/apple-music-lossless-eq)
//

import Foundation

public final class BitPerfectLogMonitor: @unchecked Sendable {
    public static let shared = BitPerfectLogMonitor()

    public var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "BitPerfectAutoSwitchEnabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "BitPerfectAutoSwitchEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "BitPerfectAutoSwitchEnabled")
            NSLog("[BitPerfectLogMonitor] Bit-Perfect auto-switch is now: \(newValue ? "ON" : "OFF")")
            if newValue, let rate = currentDetectedSampleRate {
                applyFormat(rate: rate, bitDepth: currentDetectedBitDepth ?? (rate >= 48000.0 ? 24 : 16))
            }
        }
    }

    public private(set) var currentDetectedSampleRate: Double?
    public private(set) var currentDetectedBitDepth: Int?
    public private(set) var currentDetectedBitRate: Int?
    public private(set) var currentIsLossless: Bool = true
    public private(set) var currentQualityDescription: String = "44.1 кГц (Lossless)"
    public private(set) var isFormatLockedForCurrentTrack: Bool = false
    public private(set) var isAuthoritativelyLocked: Bool = false
    public private(set) var currentLockedTrackKey: String?
    public private(set) var pendingNextTrackFormat: (sampleRate: Double, bitDepth: Int, timestamp: Date)?
    public private(set) var formatSwitchCountForCurrentTrack: Int = 0
    private var lockTimestamp: Date = .distantPast

    public var onFormatChanged: ((Double, Int?, String) -> Void)?

    private var process: Process?
    private var outputHandle: FileHandle?
    private var buffer = Data()
    private let queue = DispatchQueue(label: "org.ksholokhov.amr.bitperfect.logstream", qos: .utility)

    private var pendingRate: Double?
    private var pendingBitDepth: Int?
    private var debounceWorkItem: DispatchWorkItem?

    // Track format cache to avoid mid-playback re-negotiation on re-played tracks
    private let cacheLock = NSLock()
    private var trackFormatCache: [String: (sampleRate: Double, bitDepth: Int)] = [:]

    // Common standard audio sample rates
    public static let standardRates: [Double] = [
        44100.0, 48000.0, 88200.0, 96000.0, 176400.0, 192000.0, 352800.0, 384000.0, 705600.0, 768000.0
    ]

    private init() {}

    deinit {
        stop()
    }

    // MARK: - Track Format Cache

    public func getCachedFormat(artist: String, title: String) -> (sampleRate: Double, bitDepth: Int)? {
        guard !title.isEmpty else { return nil }
        let key = "\(artist.trimmingCharacters(in: .whitespacesAndNewlines)):\(title.trimmingCharacters(in: .whitespacesAndNewlines))".lowercased()
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return trackFormatCache[key]
    }

    public func cacheTrackFormat(artist: String, title: String, sampleRate: Double, bitDepth: Int) {
        guard !title.isEmpty else { return }
        let key = "\(artist.trimmingCharacters(in: .whitespacesAndNewlines)):\(title.trimmingCharacters(in: .whitespacesAndNewlines))".lowercased()
        cacheLock.lock()
        trackFormatCache[key] = (sampleRate, bitDepth)
        cacheLock.unlock()
    }

    // MARK: - Lifecycle

    public func start() {
        queue.async { [weak self] in
            self?.startInternal()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.stopInternal()
        }
    }

    public func resetTrackState(trackKey: String? = nil, expectedSampleRate: Double? = nil, expectedBitDepth: Int? = nil) {
        queue.async { [weak self] in
            self?.resetTrackStateInternal(trackKey: trackKey, expectedSampleRate: expectedSampleRate, expectedBitDepth: expectedBitDepth, clearPrebuffer: false)
        }
    }

    public func resetTrackStateSyncForTesting(trackKey: String? = nil, expectedSampleRate: Double? = nil, expectedBitDepth: Int? = nil) {
        queue.sync {
            self.resetTrackStateInternal(trackKey: trackKey, expectedSampleRate: expectedSampleRate, expectedBitDepth: expectedBitDepth, clearPrebuffer: trackKey == nil)
        }
    }

    public func processLogMessageForTesting(_ message: String) {
        queue.sync {
            self.parseMessage(message)
        }
    }

    private func resetTrackStateInternal(trackKey: String?, expectedSampleRate: Double?, expectedBitDepth: Int?, clearPrebuffer: Bool = false) {
        let cleanKey = trackKey?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Guard against false resetTrackState() on intermediate playerInfo notifications for the SAME active track
        if let key = cleanKey, !key.isEmpty,
           let lockedKey = self.currentLockedTrackKey, key == lockedKey,
           self.isFormatLockedForCurrentTrack {
            NSLog("[BitPerfectLogMonitor] 🛡 Ignoring redundant resetTrackState for already-locked track '%@'", key)
            return
        }

        // Guard against unkeyed transport resetTrackState() wiping a format lock that was just established by a keyed track notification < 1.2s ago
        if !clearPrebuffer, (cleanKey == nil || cleanKey?.isEmpty == true), expectedSampleRate == nil,
           let lockedKey = self.currentLockedTrackKey, !lockedKey.isEmpty,
           self.isFormatLockedForCurrentTrack, Date().timeIntervalSince(self.lockTimestamp) < 1.2 {
            NSLog("[BitPerfectLogMonitor] 🛡 Ignoring unkeyed resetTrackState within 1.2s of locking '%@'", lockedKey)
            return
        }

        if let key = cleanKey, !key.isEmpty {
            self.currentLockedTrackKey = key
        } else {
            self.currentLockedTrackKey = nil
        }

        self.debounceWorkItem?.cancel()
        self.debounceWorkItem = nil
        self.pendingRate = nil
        self.pendingBitDepth = nil
        self.formatSwitchCountForCurrentTrack = 0

        if let sr = expectedSampleRate, let norm = self.normalizeRate(sr) {
            let rawDepth = expectedBitDepth ?? (norm >= 48000.0 ? 24 : 16)
            let depth = rawDepth > 0 ? rawDepth : (norm >= 48000.0 ? 24 : 16)
            self.isFormatLockedForCurrentTrack = true
            self.isAuthoritativelyLocked = (depth >= 24)
            self.lockTimestamp = Date()
            self.pendingNextTrackFormat = nil
            NSLog("[BitPerfectLogMonitor] 🔄 Track state reset with pre-inspected format: %.1f kHz, %d-bit [Format Locked]", norm / 1000.0, depth)
            self.confirmSampleRate(norm, bitDepth: depth, isLossless: true, reason: "PreInspectedTrackFormat")
        } else if let key = cleanKey, !key.isEmpty, let prebuffered = self.pendingNextTrackFormat, Date().timeIntervalSince(prebuffered.timestamp) < 45.0 {
            // Apply Gapless Pre-buffered Format strictly at the start of the new track
            self.pendingNextTrackFormat = nil
            self.isFormatLockedForCurrentTrack = true
            self.isAuthoritativelyLocked = true
            self.lockTimestamp = Date()
            NSLog("[BitPerfectLogMonitor] ⚡️ Applying gapless pre-buffered format on new track start: %.1f kHz, %d-bit", prebuffered.sampleRate / 1000.0, prebuffered.bitDepth)
            self.confirmSampleRate(prebuffered.sampleRate, bitDepth: prebuffered.bitDepth, isLossless: true, reason: "PendingNextTrackPrebuffer")
        } else {
            if clearPrebuffer || cleanKey != nil {
                self.pendingNextTrackFormat = nil
            } else if let prebuffered = self.pendingNextTrackFormat, Date().timeIntervalSince(prebuffered.timestamp) >= 15.0 {
                self.pendingNextTrackFormat = nil
            }
            self.currentDetectedSampleRate = nil
            self.currentDetectedBitDepth = nil
            self.currentIsLossless = false
            self.isFormatLockedForCurrentTrack = false
            self.isAuthoritativelyLocked = false
            self.lockTimestamp = .distantPast
            NSLog("[BitPerfectLogMonitor] 🔄 Track state reset on track change (Format lock released)")

            // If playing a lossy AAC stream that emits no ALAC decoder log within 1.1s, fall back to standard 44.1 kHz / 16-bit PCM
            if !PlaybackRouter.shared.isTestingEnvironment, let key = cleanKey, !key.isEmpty {
                let fallbackItem = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    guard !self.isFormatLockedForCurrentTrack, self.currentLockedTrackKey == key else { return }
                    self.isFormatLockedForCurrentTrack = true
                    self.isAuthoritativelyLocked = false
                    self.lockTimestamp = Date()
                    self.confirmSampleRate(44100.0, bitDepth: 16, isLossless: false, reason: "AACStreamDefault16Bit44kHz")
                }
                self.debounceWorkItem = fallbackItem
                self.queue.asyncAfter(deadline: .now() + 1.1, execute: fallbackItem)
            }
        }
    }

    public func reportLocalTrackFormat(sampleRate: Double, bitDepth: Int = 16, isLossless: Bool = true) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard !self.isFormatLockedForCurrentTrack else { return }
            guard let normalized = self.normalizeRate(sampleRate) else { return }
            let depth = !isLossless ? 16 : (bitDepth > 0 ? bitDepth : (normalized >= 48000.0 ? 24 : 16))
            self.debounceWorkItem?.cancel()
            self.debounceWorkItem = nil
            self.isFormatLockedForCurrentTrack = true
            self.confirmSampleRate(normalized, bitDepth: depth, isLossless: isLossless, reason: "LocalTrackMetadata")
        }
    }

    private func startInternal() {
        stopInternal()

        guard isEnabled else {
            NSLog("[BitPerfectLogMonitor] Bit-Perfect auto-switch is disabled, skipping log stream.")
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/log")

        // Focused predicate on Music process to minimize CPU overhead and avoid coreaudiod spam
        let predicate = #"(process == "Music" OR subsystem == "com.apple.Music") AND (eventMessage CONTAINS[c] "sample" OR eventMessage CONTAINS[c] "lossless" OR eventMessage CONTAINS[c] "asbd" OR eventMessage CONTAINS[c] "kHz")"#

        proc.arguments = [
            "stream",
            "--style", "json",
            "--level", "debug",
            "--predicate", predicate
        ]

        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice

        let handle = outPipe.fileHandleForReading
        self.outputHandle = handle

        handle.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty {
                // EOF reached / stream closed: remove handler immediately to prevent 100% CPU busy spin!
                h.readabilityHandler = nil
                return
            }
            self?.queue.async {
                self?.buffer.append(data)
                self?.drainBuffer()
            }
        }

        proc.terminationHandler = { [weak self] p in
            NSLog("[BitPerfectLogMonitor] Log process terminated with code \(p.terminationStatus)")
            self?.queue.async {
                self?.stopInternal()
            }
        }

        do {
            try proc.run()
            self.process = proc
            NSLog("[BitPerfectLogMonitor] 🚀 Focused log stream started successfully (PID: \(proc.processIdentifier)).")
        } catch {
            NSLog("[BitPerfectLogMonitor] ❌ Failed to start log stream: \(error)")
            stopInternal()
        }
    }

    private func stopInternal() {
        outputHandle?.readabilityHandler = nil
        outputHandle = nil
        buffer.removeAll()

        if let proc = process {
            proc.terminationHandler = nil
            if proc.isRunning {
                proc.terminate()
                kill(proc.processIdentifier, SIGKILL)
            }
            process = nil
        }
    }

    // MARK: - Stream Processing

    private func drainBuffer() {
        while let range = buffer.firstRange(of: Data([0x0A])) { // '\n'
            let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex...range.lowerBound)

            guard let line = String(data: lineData, encoding: .utf8), !line.isEmpty else {
                continue
            }
            handleLine(line)
        }
    }

    private func handleLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
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

    private func parseMessage(_ message: String) {
        let lower = message.lowercased()

        // 1. Strict negative filter: immediately drop feedback loops, hardware rates, pre-buffering
        for ignored in Self.ignoredSubstrings {
            if lower.contains(ignored) {
                return
            }
        }

        let fullRange = NSRange(message.startIndex..<message.endIndex, in: message)

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
    private static let ignoredSubstrings: [String] = [
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
    private static let alacDecoderPattern = try! NSRegularExpression(
        pattern: #"(?i)ACAppleLosslessDecoder.*Input format:\s*\d+\s*ch,\s*([0-9]+(?:\.[0-9]+)?)\s*Hz,\s*alac(?:\s*\([^)]*\))?\s*from\s*([0-9]+)-bit"#,
        options: []
    )

    // Authoritative FigStreamPlayer active playback report: gives sample rate and bit depth
    private static let figPlaybackReportPattern = try! NSRegularExpression(
        pattern: #"(?i)fpfs_ReportAudioPlaybackThroughFigLog:.*\[SampleRate\s*([0-9]+)\].*\[BitDepth\s*([0-9]+)\]"#,
        options: []
    )

    // Authoritative AudioQueue creation when active audio pipeline is constructed
    private static let audioQueueBuildPattern = try! NSRegularExpression(
        pattern: #"(?i)subaq_buildCAAudioQueue:.*(?:Creating|Created new) AudioQueue with format:'(?:qlac|alac|lpcm|aac\s*)',.*sampleRate:([0-9]+)"#,
        options: []
    )

    // Authoritative AudioQueue startup sync when samples begin playback
    private static let audioQueueSyncPattern = try! NSRegularExpression(
        pattern: #"(?i)faq->srcASBD->mSampleRate\s*([0-9]+)"#,
        options: []
    )

    // Authoritative generic decoder for lossy / other formats (AAC, MP3)
    private static let genericDecoderPattern = try! NSRegularExpression(
        pattern: #"(?i)Input format:\s*\d+\s*ch,\s*([0-9]+(?:\.[0-9]+)?)\s*Hz,\s*(?:'?(?:aac|mp3|alac|qlac)'?)"#,
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

    // MARK: - DAC Reconnect / Device Switch Support

    public func reapplyCurrentFormat() {
        guard isEnabled, let rate = currentDetectedSampleRate else { return }
        let bitDepth = currentDetectedBitDepth ?? (rate >= 48000.0 ? 24 : 16)
        NSLog("[BitPerfectLogMonitor] 🔄 Reapplying current format to audio device: %.1f kHz, %d-бит", rate / 1000.0, bitDepth)
        applyFormat(rate: rate, bitDepth: bitDepth)
    }

    // MARK: - Debounce & Apply

    private func sampleRateDetected(_ rate: Double, bitDepth: Int, isAuthoritative: Bool, isLossless: Bool = true, reason: String) {
        // Filter out unreasonable rates
        guard rate >= 44100.0 && rate <= 768000.0 else { return }
        let validDepth = !isLossless ? 16 : (bitDepth > 0 ? bitDepth : (rate >= 48000.0 ? 24 : 16))

        // 1. Strict Mid-Playback Format Lock & Gapless Pre-buffering Isolation:
        // Once format is locked for the current playing track (isFormatLockedForCurrentTrack == true),
        // NEVER invoke CoreAudioDeviceManager.setFormat again mid-track!
        // Exception: if a preliminary/fallback lock occurred on a slow network start (!isAuthoritativelyLocked)
        // and the authoritative ALAC decoder arrives within 4.5s, upgrade the current track format immediately.
        if isFormatLockedForCurrentTrack {
            if isAuthoritative {
                if (!isAuthoritativelyLocked && Date().timeIntervalSince(lockTimestamp) < 4.5) ||
                   (rate == currentDetectedSampleRate && Date().timeIntervalSince(lockTimestamp) < 3.5) {
                    isAuthoritativelyLocked = true
                    currentIsLossless = isLossless
                    confirmSampleRate(rate, bitDepth: validDepth, isLossless: isLossless, reason: reason)
                    return
                }
                // Gapless Pre-buffering Isolation: store pre-buffered next track format for the upcoming track transition
                if isLossless {
                    pendingNextTrackFormat = (sampleRate: rate, bitDepth: validDepth, timestamp: Date())
                    if let nextTrack = PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.latestUpcomingTracks.first }) {
                        cacheTrackFormat(artist: nextTrack.artist, title: nextTrack.name, sampleRate: rate, bitDepth: validDepth)
                    }
                    NSLog("[BitPerfectLogMonitor] 🛡 [Strict Format Lock] Buffered next-track format (%.1f kHz, %d-bit) while locked on %.1f kHz", rate / 1000.0, validDepth, (currentDetectedSampleRate ?? 0) / 1000.0)
                }
            }
            return
        }

        // 2. Authoritative ALAC / Fig report: lock track format immediately and apply!
        if isAuthoritative {
            debounceWorkItem?.cancel()
            debounceWorkItem = nil
            isFormatLockedForCurrentTrack = true
            isAuthoritativelyLocked = true
            lockTimestamp = Date()
            pendingNextTrackFormat = nil
            confirmSampleRate(rate, bitDepth: validDepth, isLossless: isLossless, reason: reason)
            return
        }

        // 3. Preliminary / fallback logs: debounce for 0.6s to allow authoritative decoder to arrive first
        if pendingRate == rate && pendingBitDepth == validDepth {
            return
        }

        pendingRate = rate
        pendingBitDepth = validDepth

        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard !self.isFormatLockedForCurrentTrack else { return }
            self.isFormatLockedForCurrentTrack = true
            self.isAuthoritativelyLocked = false
            self.lockTimestamp = Date()
            self.confirmSampleRate(rate, bitDepth: validDepth, isLossless: isLossless, reason: reason)
        }
        debounceWorkItem = item
        queue.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    private func confirmSampleRate(_ rate: Double, bitDepth: Int, isLossless: Bool = true, reason: String) {
        let validDepth = !isLossless ? 16 : (bitDepth > 0 ? bitDepth : (rate >= 48000.0 ? 24 : 16))
        currentDetectedSampleRate = rate
        currentDetectedBitDepth = validDepth
        currentIsLossless = isLossless
        currentDetectedBitRate = isLossless ? Int(rate * Double(validDepth) * 2 / 1000.0) : 256

        let desc = formatQualityString(rate: rate, bitDepth: validDepth, isLossless: isLossless)
        currentQualityDescription = desc

        if isLossless {
            if let lockedKey = currentLockedTrackKey, !lockedKey.isEmpty {
                cacheLock.lock()
                trackFormatCache[lockedKey] = (rate, validDepth)
                cacheLock.unlock()
            } else if let curTrack = PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.lastPlayerStatusCache })?.status.track {
                cacheTrackFormat(artist: curTrack.artist, title: curTrack.name, sampleRate: rate, bitDepth: validDepth)
            }
        }
        PlaybackStateStore.shared.invalidateStatusCache()

        NSLog("[BitPerfectLogMonitor] 🎯 Locked track format: %.1f kHz, %d-бит (%@) [Trigger: %@]", rate / 1000.0, validDepth, desc, reason)

        formatSwitchCountForCurrentTrack += 1
        if isEnabled {
            applyFormat(rate: rate, bitDepth: validDepth)
        }

        let callback = self.onFormatChanged
        DispatchQueue.main.async {
            callback?(rate, validDepth, desc)
            NotificationCenter.default.post(
                name: .bitPerfectFormatDidChange,
                object: nil,
                userInfo: [
                    "sampleRate": rate,
                    "bitDepth": validDepth,
                    "description": desc
                ]
            )
            MenuManager.shared.updateMenuState()
            UPnPMediaRendererServer.shared.notifySubscribers(force: true)
        }
    }

    private func applyFormat(rate: Double, bitDepth: Int) {
        CoreAudioDeviceManager.shared.setFormat(sampleRate: rate, bitDepth: bitDepth)
        if DLNADiscoveryManager.shared.hasActiveRenderer {
            AudioProcessTapService.shared.setFormat(sampleRate: Int(rate), bitDepth: bitDepth)
            DLNADiscoveryManager.shared.handleTrackFormatChanged(sampleRate: Int(rate), bitDepth: bitDepth)
        }
    }

    public func formatQualityString(rate: Double, bitDepth: Int, isLossless: Bool = true) -> String {
        guard isLossless else {
            return "AAC (256 kbps)"
        }
        let khz = rate / 1000.0
        let khzStr = (khz.truncatingRemainder(dividingBy: 1) == 0) ? String(format: "%.0f", khz) : String(format: "%.1f", khz)

        if rate > 48000.0 {
            return "\(khzStr) кГц (Hi-Res Lossless \(bitDepth)-бит)"
        } else {
            return "\(khzStr) кГц (Lossless \(bitDepth)-бит)"
        }
    }
}

public extension Notification.Name {
    static let bitPerfectFormatDidChange = Notification.Name("BitPerfectFormatDidChangeNotification")
}
