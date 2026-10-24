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
                applyFormat(rate: rate, bitDepth: currentDetectedBitDepth ?? (rate > 48000.0 ? 24 : 16))
            }
        }
    }

    public private(set) var currentDetectedSampleRate: Double?
    public private(set) var currentDetectedBitDepth: Int?
    public private(set) var currentDetectedBitRate: Int?
    public private(set) var currentQualityDescription: String = "44.1 кГц (Lossless)"
    public private(set) var isFormatLockedForCurrentTrack: Bool = false

    public var onFormatChanged: ((Double, Int?, String) -> Void)?

    private var process: Process?
    private var outputHandle: FileHandle?
    private var buffer = Data()
    private let queue = DispatchQueue(label: "org.ksholokhov.amr.bitperfect.logstream", qos: .utility)

    private var pendingRate: Double?
    private var pendingBitDepth: Int?
    private var debounceWorkItem: DispatchWorkItem?

    // Common standard audio sample rates
    public static let standardRates: [Double] = [
        44100.0, 48000.0, 88200.0, 96000.0, 176400.0, 192000.0, 352800.0, 384000.0, 705600.0, 768000.0
    ]

    private init() {}

    deinit {
        stop()
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

    public func resetTrackState() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.debounceWorkItem?.cancel()
            self.debounceWorkItem = nil
            self.pendingRate = nil
            self.pendingBitDepth = nil
            self.currentDetectedBitDepth = nil
            self.isFormatLockedForCurrentTrack = false
            NSLog("[BitPerfectLogMonitor] 🔄 Track state reset on track change (Format lock released)")
        }
    }

    public func reportLocalTrackFormat(sampleRate: Double, bitDepth: Int = 16) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard !self.isFormatLockedForCurrentTrack else { return }
            guard let normalized = self.normalizeRate(sampleRate) else { return }
            let depth = bitDepth > 0 ? bitDepth : (normalized > 48000.0 ? 24 : 16)
            self.debounceWorkItem?.cancel()
            self.debounceWorkItem = nil
            self.isFormatLockedForCurrentTrack = true
            self.confirmSampleRate(normalized, bitDepth: depth, reason: "LocalTrackMetadata")
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
           let depth = Int(message[depthRange]) {
            sampleRateDetected(rate, bitDepth: depth, isAuthoritative: true, reason: "ALACDecoder: \(message)")
            return
        }

        // 3. Authoritative FigPlaybackReport (rate + bit depth)
        if let match = Self.figPlaybackReportPattern.firstMatch(in: message, options: [], range: fullRange),
           match.numberOfRanges > 2,
           let rateRange = Range(match.range(at: 1), in: message),
           let depthRange = Range(match.range(at: 2), in: message),
           let rawRate = Double(message[rateRange]),
           let rate = normalizeRate(rawRate),
           let depth = Int(message[depthRange]) {
            sampleRateDetected(rate, bitDepth: depth, isAuthoritative: true, reason: "FigPlaybackReport: \(message)")
            return
        }

        // 4. CoreMedia AudioQueue build (generic preliminary)
        if let match = Self.audioQueueBuildPattern.firstMatch(in: message, options: [], range: fullRange),
           match.numberOfRanges > 1,
           let rateRange = Range(match.range(at: 1), in: message),
           let rawRate = Double(message[rateRange]),
           let rate = normalizeRate(rawRate) {
            let depth = (rate > 48000.0) ? 24 : 16
            sampleRateDetected(rate, bitDepth: depth, isAuthoritative: false, reason: "subaq_buildCAAudioQueue: \(message)")
            return
        }

        // 5. CoreMedia AudioQueue startup sync (generic preliminary)
        if let match = Self.audioQueueSyncPattern.firstMatch(in: message, options: [], range: fullRange),
           match.numberOfRanges > 1,
           let rateRange = Range(match.range(at: 1), in: message),
           let rawRate = Double(message[rateRange]),
           let rate = normalizeRate(rawRate) {
            let depth = (rate > 48000.0) ? 24 : 16
            sampleRateDetected(rate, bitDepth: depth, isAuthoritative: false, reason: "subaq_performStartupSync: \(message)")
            return
        }

        // 6. Generic decoder (AAC, MP3, etc. - preliminary)
        if let match = Self.genericDecoderPattern.firstMatch(in: message, options: [], range: fullRange),
           match.numberOfRanges > 1,
           let rateRange = Range(match.range(at: 1), in: message),
           let rawRate = Double(message[rateRange]),
           let rate = normalizeRate(rawRate) {
            let depth = (rate > 48000.0) ? 24 : 16
            sampleRateDetected(rate, bitDepth: depth, isAuthoritative: false, reason: "GenericDecoder: \(message)")
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
        let bitDepth = currentDetectedBitDepth ?? (rate > 48000.0 ? 24 : 16)
        NSLog("[BitPerfectLogMonitor] 🔄 Reapplying current format to audio device: %.1f kHz, %d-бит", rate / 1000.0, bitDepth)
        applyFormat(rate: rate, bitDepth: bitDepth)
    }

    // MARK: - Debounce & Apply

    private func sampleRateDetected(_ rate: Double, bitDepth: Int, isAuthoritative: Bool, reason: String) {
        // 1. If format is already locked for the active playing track, ignore logs completely!
        // This prevents next-track pre-buffering (gapless preloading) from disrupting the current song.
        if isFormatLockedForCurrentTrack {
            return
        }

        // Filter out unreasonable rates
        guard rate >= 44100.0 && rate <= 768000.0 else { return }

        // 2. Authoritative ALAC / Fig report: lock track format immediately and apply!
        if isAuthoritative {
            debounceWorkItem?.cancel()
            debounceWorkItem = nil
            isFormatLockedForCurrentTrack = true
            confirmSampleRate(rate, bitDepth: bitDepth, reason: reason)
            return
        }

        // 3. Preliminary / fallback logs: debounce for 0.6s to allow authoritative decoder to arrive first
        if pendingRate == rate && pendingBitDepth == bitDepth {
            return
        }

        pendingRate = rate
        pendingBitDepth = bitDepth

        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard !self.isFormatLockedForCurrentTrack else { return }
            self.isFormatLockedForCurrentTrack = true
            self.confirmSampleRate(rate, bitDepth: bitDepth, reason: reason)
        }
        debounceWorkItem = item
        queue.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    private func confirmSampleRate(_ rate: Double, bitDepth: Int, reason: String) {
        currentDetectedSampleRate = rate
        currentDetectedBitDepth = bitDepth
        currentDetectedBitRate = Int(rate * Double(bitDepth) * 2 / 1000.0)

        let desc = formatQualityString(rate: rate, bitDepth: bitDepth)
        currentQualityDescription = desc

        NSLog("[BitPerfectLogMonitor] 🎯 Locked track format: %.1f kHz, %d-бит (%@) [Trigger: %@]", rate / 1000.0, bitDepth, desc, reason)

        if isEnabled {
            applyFormat(rate: rate, bitDepth: bitDepth)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onFormatChanged?(rate, bitDepth, desc)
            MenuManager.shared.updateMenuState()
            UPnPMediaRendererServer.shared.notifySubscribers(force: true)
        }
    }

    private func applyFormat(rate: Double, bitDepth: Int) {
        CoreAudioDeviceManager.shared.setFormat(sampleRate: rate, bitDepth: bitDepth)
    }

    public func formatQualityString(rate: Double, bitDepth: Int) -> String {
        let khz = rate / 1000.0
        let khzStr = (khz.truncatingRemainder(dividingBy: 1) == 0) ? String(format: "%.0f", khz) : String(format: "%.1f", khz)

        if rate > 48000.0 {
            return "\(khzStr) кГц (Hi-Res Lossless \(bitDepth)-бит)"
        } else {
            return "\(khzStr) кГц (Lossless \(bitDepth)-бит)"
        }
    }
}
