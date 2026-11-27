//
//  BitPerfectLogMonitor.swift
//  AppleMusicRemoteMac
//
//  Real-time Bit-Perfect Sample Rate Detection via macOS Unified Log Stream
//  Inspired by Choritsu (jcongaku/apple-music-lossless-eq)
//

import Foundation
import Darwin
import os

public final class BitPerfectLogMonitor: @unchecked Sendable {
    public static let shared = BitPerfectLogMonitor()

    // Lock-free / nanosecond spin-locked scalar cache for Real-Time CoreAudio IOProcs.
    // NEVER hold fastSpinLock across UserDefaults, NSLog, NSLock, I/O, or callbacks.
    internal var fastSpinLock = os_unfair_lock_s()
    private var _fastIsEnabled: Bool
    private var _currentDetectedSampleRate: Double?

    public var isEnabled: Bool {
        get {
            os_unfair_lock_lock(&fastSpinLock)
            let enabled = _fastIsEnabled
            os_unfair_lock_unlock(&fastSpinLock)
            return enabled
        }
        set {
            os_unfair_lock_lock(&fastSpinLock)
            _fastIsEnabled = newValue
            os_unfair_lock_unlock(&fastSpinLock)
            AppStorageProvider.shared.set(newValue, forKey: "BitPerfectAutoSwitchEnabled")
            NSLog("[BitPerfectLogMonitor] Bit-Perfect auto-switch is now: \(newValue ? "ON" : "OFF")")
            syncMusicAppSmartTransitions(forBitPerfectEnabled: newValue)
            if newValue, let rate = currentDetectedSampleRate {
                applyFormat(rate: rate, bitDepth: currentDetectedBitDepth ?? (rate >= 48000.0 ? 24 : 16))
            }
        }
    }

    private let transitionsPrefLock = NSLock()
    private var lastSmartTransitionEnforcementAt: Date = .distantPast
    internal var musicTransitionsPrefAccessorForTesting: (read: () -> Bool?, write: (Bool) -> Void)? = nil

    private let stateLock = NSLock()
    private var _currentDetectedBitDepth: Int?
    private var _currentDetectedBitRate: Int?
    private var _currentIsLossless: Bool = true
    private var _currentQualityDescription: String = "44.1 кГц (Lossless)"
    private var _isFormatLockedForCurrentTrack: Bool = false
    private var _isAuthoritativelyLocked: Bool = false
    private var _currentLockedTrackKey: String?
    private var _currentLockedCatalogId: String?
    private var _pendingNextTrackFormat: (sampleRate: Double, bitDepth: Int, timestamp: Date)?
    private var _formatSwitchCountForCurrentTrack: Int = 0
    internal var lockTimestamp: Date = .distantPast
    internal var lastResetTimestamp: Date = .distantPast
    internal var isSuppressingTeardownLogs: Bool = false
    internal var teardownSuppressStartedAt: Date = .distantPast

    public internal(set) var currentDetectedSampleRate: Double? {
        get {
            os_unfair_lock_lock(&fastSpinLock)
            let val = _currentDetectedSampleRate
            os_unfair_lock_unlock(&fastSpinLock)
            return val
        }
        set {
            os_unfair_lock_lock(&fastSpinLock)
            _currentDetectedSampleRate = newValue
            os_unfair_lock_unlock(&fastSpinLock)
        }
    }
    public internal(set) var currentDetectedBitDepth: Int? {
        get { stateLock.withLock { _currentDetectedBitDepth } }
        set { stateLock.withLock { _currentDetectedBitDepth = newValue } }
    }
    public internal(set) var currentDetectedBitRate: Int? {
        get { stateLock.withLock { _currentDetectedBitRate } }
        set { stateLock.withLock { _currentDetectedBitRate = newValue } }
    }
    public internal(set) var currentIsLossless: Bool {
        get { stateLock.withLock { _currentIsLossless } }
        set { stateLock.withLock { _currentIsLossless = newValue } }
    }
    public internal(set) var currentQualityDescription: String {
        get { stateLock.withLock { _currentQualityDescription } }
        set { stateLock.withLock { _currentQualityDescription = newValue } }
    }
    public internal(set) var isFormatLockedForCurrentTrack: Bool {
        get { stateLock.withLock { _isFormatLockedForCurrentTrack } }
        set { stateLock.withLock { _isFormatLockedForCurrentTrack = newValue } }
    }
    public internal(set) var isAuthoritativelyLocked: Bool {
        get { stateLock.withLock { _isAuthoritativelyLocked } }
        set { stateLock.withLock { _isAuthoritativelyLocked = newValue } }
    }
    public internal(set) var currentLockedTrackKey: String? {
        get { stateLock.withLock { _currentLockedTrackKey } }
        set { stateLock.withLock { _currentLockedTrackKey = newValue } }
    }
    public internal(set) var currentLockedCatalogId: String? {
        get { stateLock.withLock { _currentLockedCatalogId } }
        set { stateLock.withLock { _currentLockedCatalogId = newValue } }
    }
    public internal(set) var pendingNextTrackFormat: (sampleRate: Double, bitDepth: Int, timestamp: Date)? {
        get { stateLock.withLock { _pendingNextTrackFormat } }
        set { stateLock.withLock { _pendingNextTrackFormat = newValue } }
    }
    public internal(set) var formatSwitchCountForCurrentTrack: Int {
        get { stateLock.withLock { _formatSwitchCountForCurrentTrack } }
        set { stateLock.withLock { _formatSwitchCountForCurrentTrack = newValue } }
    }

    private let handlersLock = NSLock()
    private var _onFormatChanged: ((Double, Int?, String) -> Void)?
    private var formatChangedObservers: [String: (Double, Int?, String) -> Void] = [:]
    private var _onSmartTransitionScheduleDetected: ((Double) -> Void)?
    private var _onSmartTransitionBegan: (() -> Void)?

    public var onSmartTransitionScheduleDetected: ((Double) -> Void)? {
        get { handlersLock.withLock { _onSmartTransitionScheduleDetected } }
        set { handlersLock.withLock { _onSmartTransitionScheduleDetected = newValue } }
    }

    public var onSmartTransitionBegan: (() -> Void)? {
        get { handlersLock.withLock { _onSmartTransitionBegan } }
        set { handlersLock.withLock { _onSmartTransitionBegan = newValue } }
    }

    public func addFormatChangedObserver(id: String, handler: @escaping (Double, Int?, String) -> Void) {
        handlersLock.lock()
        formatChangedObservers[id] = handler
        handlersLock.unlock()
    }

    public var onFormatChanged: ((Double, Int?, String) -> Void)? {
        get {
            handlersLock.lock()
            let primary = _onFormatChanged
            let observers = Array(formatChangedObservers.values)
            handlersLock.unlock()
            guard primary != nil || !observers.isEmpty else { return nil }
            return { rate, bitDepth, desc in
                primary?(rate, bitDepth, desc)
                for observer in observers {
                    observer(rate, bitDepth, desc)
                }
            }
        }
        set {
            handlersLock.lock()
            _onFormatChanged = newValue
            handlersLock.unlock()
        }
    }

    internal var process: Process?
    private var outputHandle: FileHandle?
    internal var sigtermSource: DispatchSourceSignal?
    internal var sigintSource: DispatchSourceSignal?
    internal var buffer = Data()
    internal var bufferReadOffset: Int = 0
    internal let queue = DispatchQueue(label: "org.ksholokhov.amr.bitperfect.logstream", qos: .utility)

    internal var pendingRate: Double?
    internal var pendingBitDepth: Int?
    internal var debounceWorkItem: DispatchWorkItem?
    internal var lossyFallbackWorkItem: DispatchWorkItem?

    // Track format cache to avoid mid-playback re-negotiation on re-played tracks (bounded FIFO <= 2000 entries)
    public static let maxTrackFormatCacheEntries = 2000
    private let cacheLock = NSLock()
    private var trackFormatCache: [String: (sampleRate: Double, bitDepth: Int)] = [:]
    private var trackFormatCacheOrder: [String] = []

    // Common standard audio sample rates
    public static let standardRates: [Double] = [
        44100.0, 48000.0, 88200.0, 96000.0, 176400.0, 192000.0, 352800.0, 384000.0, 705600.0, 768000.0
    ]

    private init() {
        if AppStorageProvider.shared.object(forKey: "BitPerfectAutoSwitchEnabled") == nil {
            self._fastIsEnabled = true
        } else {
            self._fastIsEnabled = AppStorageProvider.shared.bool(forKey: "BitPerfectAutoSwitchEnabled")
        }
    }

    deinit {
        stop()
    }

    // MARK: - Track Format Cache

    internal static func sanitizedCatalogId(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              let num = Int(trimmed),
              num >= 1_000_000 else {
            return nil
        }
        return trimmed
    }

    public func getCachedFormat(artist: String, title: String, catalogId: String? = nil) -> (sampleRate: Double, bitDepth: Int)? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cid = Self.sanitizedCatalogId(catalogId) {
            // Edition-isolated lookup: different catalog IDs of the same song title (e.g. 44.1 kHz standard vs 96 kHz Hi-Res remaster)
            // never collide when `catalogId` is known!
            return trackFormatCache["cid:\(cid)"]
        }
        guard !title.isEmpty else { return nil }
        let key = "\(artist.trimmingCharacters(in: .whitespacesAndNewlines)):\(title.trimmingCharacters(in: .whitespacesAndNewlines))".lowercased()
        return trackFormatCache[key]
    }

    public func cacheTrackFormat(artist: String, title: String, catalogId: String? = nil, sampleRate: Double, bitDepth: Int) {
        let cid = Self.sanitizedCatalogId(catalogId)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cid != nil || !cleanTitle.isEmpty else { return }
        cacheLock.lock()
        if let cid {
            storeTrackFormatLocked(key: "cid:\(cid)", sampleRate: sampleRate, bitDepth: bitDepth)
        }
        if !cleanTitle.isEmpty {
            let key = "\(artist.trimmingCharacters(in: .whitespacesAndNewlines)):\(cleanTitle)".lowercased()
            storeTrackFormatLocked(key: key, sampleRate: sampleRate, bitDepth: bitDepth)
        }
        cacheLock.unlock()
    }

    internal func cacheLockedTrackKeyFormat(_ lockedKey: String, catalogId: String? = nil, sampleRate: Double, bitDepth: Int) {
        let cid = Self.sanitizedCatalogId(catalogId)
        guard !lockedKey.isEmpty || cid != nil else { return }
        cacheLock.lock()
        if let cid {
            storeTrackFormatLocked(key: "cid:\(cid)", sampleRate: sampleRate, bitDepth: bitDepth)
        }
        if !lockedKey.isEmpty {
            storeTrackFormatLocked(key: lockedKey, sampleRate: sampleRate, bitDepth: bitDepth)
        }
        cacheLock.unlock()
    }

    private func storeTrackFormatLocked(key: String, sampleRate: Double, bitDepth: Int) {
        if trackFormatCache[key] == nil {
            while trackFormatCache.count >= Self.maxTrackFormatCacheEntries, !trackFormatCacheOrder.isEmpty {
                let evicted = trackFormatCacheOrder.removeFirst()
                trackFormatCache.removeValue(forKey: evicted)
            }
            trackFormatCacheOrder.append(key)
        }
        trackFormatCache[key] = (sampleRate, bitDepth)
    }

    internal var trackFormatCacheCountForTesting: Int {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return trackFormatCache.count
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

    /// Suppresses trailing decoder teardown logs of the outgoing track while AMR stops/replaces the queue in `Music.app`,
    /// preventing old-track decoder lines from locking onto the incoming track before `play` executes.
    public func beginExplicitTrackSwitch() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.isSuppressingTeardownLogs = true
            self.teardownSuppressStartedAt = Date()
            self.debounceWorkItem?.cancel()
            self.debounceWorkItem = nil
            self.lossyFallbackWorkItem?.cancel()
            self.lossyFallbackWorkItem = nil
            self.pendingRate = nil
            self.pendingBitDepth = nil
            self.pendingNextTrackFormat = nil
            self.isFormatLockedForCurrentTrack = false
            self.isAuthoritativelyLocked = false
            self.currentLockedTrackKey = nil
            self.currentLockedCatalogId = nil
        }
    }

    /// Releases the teardown suppression gate right as the new track begins playback in `Music.app`.
    public func endExplicitTrackSwitch(
        trackKey: String?,
        catalogId: String? = nil,
        expectedSampleRate: Double? = nil,
        expectedBitDepth: Int? = nil
    ) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.isSuppressingTeardownLogs = false
            self.resetTrackStateInternal(
                trackKey: trackKey,
                catalogId: catalogId,
                expectedSampleRate: expectedSampleRate,
                expectedBitDepth: expectedBitDepth,
                clearPrebuffer: true
            )
        }
    }

    public func resetTrackState(
        trackKey: String? = nil,
        catalogId: String? = nil,
        expectedSampleRate: Double? = nil,
        expectedBitDepth: Int? = nil,
        clearPrebuffer: Bool = false
    ) {
        queue.async { [weak self] in
            self?.resetTrackStateInternal(
                trackKey: trackKey,
                catalogId: catalogId,
                expectedSampleRate: expectedSampleRate,
                expectedBitDepth: expectedBitDepth,
                clearPrebuffer: clearPrebuffer
            )
        }
    }

    public func resetTrackStateSyncForTesting(
        trackKey: String? = nil,
        catalogId: String? = nil,
        expectedSampleRate: Double? = nil,
        expectedBitDepth: Int? = nil
    ) {
        queue.sync {
            self.isSuppressingTeardownLogs = false
            self.resetTrackStateInternal(
                trackKey: trackKey,
                catalogId: catalogId,
                expectedSampleRate: expectedSampleRate,
                expectedBitDepth: expectedBitDepth,
                clearPrebuffer: trackKey == nil
            )
        }
    }

    public func processLogMessageForTesting(_ message: String) {
        queue.sync {
            self.parseMessage(message)
        }
    }

    private func matchesCurrentLockedTrack(incomingKey: String, lockedKey: String, incomingCatalogId: String?) -> Bool {
        if incomingKey == lockedKey {
            return true
        }
        if let inCid = incomingCatalogId, let curCid = self.currentLockedCatalogId, inCid == curCid {
            return true
        }
        if let curCid = self.currentLockedCatalogId, incomingCatalogId == nil,
           let colonIdx = incomingKey.firstIndex(of: ":") {
            let candArtist = String(incomingKey[..<colonIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
            let candTitle = String(incomingKey[incomingKey.index(after: colonIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !candTitle.isEmpty {
                let activeExpected: TrackInfo? = PlaybackStateStore.shared.withLock {
                    guard PlaybackStateStore.shared.isCustomQueuePlayback else { return nil }
                    let q = PlaybackStateStore.shared.activeCustomQueue
                    let idx = PlaybackStateStore.shared.activeCustomQueueIndex
                    guard idx >= 0 && idx < q.count else { return nil }
                    let cur = q[idx]
                    guard MusicKitManager.extractNumericCatalogId(from: cur) == curCid else { return nil }
                    return cur
                }
                if let expected = activeExpected,
                   QueueManager.shared.matchesExpectedQueueTrack(expected, candidateName: candTitle, candidateArtist: candArtist) {
                    return true
                }
            }
        }
        return false
    }

    private func resetTrackStateInternal(
        trackKey: String?,
        catalogId: String? = nil,
        expectedSampleRate: Double?,
        expectedBitDepth: Int?,
        clearPrebuffer: Bool = false
    ) {
        let cleanKey = trackKey?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanCid = Self.sanitizedCatalogId(catalogId)

        // While staging a manual track switch, ignore intermediate unkeyed `stopped` / transport resets until `endExplicitTrackSwitch` runs
        if self.isSuppressingTeardownLogs && Date().timeIntervalSince(self.teardownSuppressStartedAt) < 2.5 {
            if cleanKey == nil || cleanKey?.isEmpty == true {
                return
            }
        }

        // Guard against false resetTrackState() on intermediate or localized (`'wayne shorter:...'` -> `'уэйн шортер:...'`)
        // playerInfo / StatusBuilder notifications for the SAME active track!
        if let key = cleanKey, !key.isEmpty,
           let lockedKey = self.currentLockedTrackKey,
           self.matchesCurrentLockedTrack(incomingKey: key, lockedKey: lockedKey, incomingCatalogId: cleanCid) {
            if let cid = cleanCid, self.currentLockedCatalogId == nil {
                self.currentLockedCatalogId = cid
            }
            if key != lockedKey {
                self.currentLockedTrackKey = key
                if self.isFormatLockedForCurrentTrack, self.currentIsLossless,
                   let rate = self.currentDetectedSampleRate {
                    let depth = self.currentDetectedBitDepth ?? (rate >= 48000.0 ? 24 : 16)
                    self.cacheLockedTrackKeyFormat(key, catalogId: self.currentLockedCatalogId, sampleRate: rate, bitDepth: depth)
                }
            }
            if self.isFormatLockedForCurrentTrack {
                NSLog("[BitPerfectLogMonitor] 🛡 Ignoring redundant resetTrackState for already-locked track '%@'", key)
                return
            }
            if !clearPrebuffer && expectedSampleRate == nil && Date().timeIntervalSince(self.lastResetTimestamp) < 2.5 {
                // Ignore duplicate `PlayerStatusEngine` + `DistributedNotificationCenter` resets arriving milliseconds apart for the same awaiting-decoder track
                return
            }
        }

        // Guard against unkeyed transport resetTrackState() wiping a format lock that was just established by a keyed track notification < 1.2s ago
        if !clearPrebuffer, (cleanKey == nil || cleanKey?.isEmpty == true), expectedSampleRate == nil,
           let lockedKey = self.currentLockedTrackKey, !lockedKey.isEmpty,
           self.isFormatLockedForCurrentTrack, Date().timeIntervalSince(self.lockTimestamp) < 1.2 {
            NSLog("[BitPerfectLogMonitor] 🛡 Ignoring unkeyed resetTrackState within 1.2s of locking '%@'", lockedKey)
            return
        }

        // Guard against delayed keyed track notification (`PlayerStatusEngine` / `playerInfo` arriving 0.4–1.8s after `next` / `previous`)
        // overwriting a fresh authoritative `ACAppleLosslessDecoder` lock established moments earlier after `lastResetTimestamp`!
        let isActivelyStagingCloud = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isStagingCloudTrack || PlaybackStateStore.shared.isActivelyStagingInBuffer
        }
        if !clearPrebuffer, !isActivelyStagingCloud,
           let key = cleanKey, !key.isEmpty,
           self.currentLockedTrackKey == nil,
           self.isFormatLockedForCurrentTrack, self.isAuthoritativelyLocked,
           self.lockTimestamp >= self.lastResetTimestamp.addingTimeInterval(-0.05),
           Date().timeIntervalSince(self.lockTimestamp) < 4.5,
           let lockedRate = self.currentDetectedSampleRate {
            self.currentLockedTrackKey = key
            self.currentLockedCatalogId = cleanCid
            self.lossyFallbackWorkItem?.cancel()
            self.lossyFallbackWorkItem = nil
            // Keep `isFormatLockedForCurrentTrack = true` so `AACStreamDefault16Bit44kHz` NEVER fires and DAC stays locked,
            // while setting `isAuthoritativelyLocked = false` so if `previous` flushed an outgoing seek before opening the real decoder <12s later, it still self-heals once.
            self.isAuthoritativelyLocked = false
            self.lockTimestamp = Date()
            let lockedDepth = self.currentDetectedBitDepth ?? (lockedRate >= 48000.0 ? 24 : 16)
            if self.currentIsLossless {
                self.cacheLockedTrackKeyFormat(key, catalogId: cleanCid, sampleRate: lockedRate, bitDepth: lockedDepth)
            }
            SpectralIntegrityAnalyzer.shared.resetForNewTrack(trackKey: key)
            NSLog("[BitPerfectLogMonitor] 🛡 Adopted track key '%@' onto active authoritative lock (%.1f kHz, %d-bit)", key, lockedRate / 1000.0, lockedDepth)
            return
        }

        if let key = cleanKey, !key.isEmpty {
            if self.currentLockedTrackKey != key {
                self.currentLockedCatalogId = cleanCid
            } else if let cleanCid {
                self.currentLockedCatalogId = cleanCid
            }
            self.currentLockedTrackKey = key
        } else {
            self.currentLockedTrackKey = nil
            self.currentLockedCatalogId = nil
        }
        self.lastResetTimestamp = Date()

        self.debounceWorkItem?.cancel()
        self.debounceWorkItem = nil
        self.lossyFallbackWorkItem?.cancel()
        self.lossyFallbackWorkItem = nil
        self.pendingRate = nil
        self.pendingBitDepth = nil
        self.formatSwitchCountForCurrentTrack = 0
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.scheduledSmartTransitionStart = nil
            PlaybackStateStore.shared.lastSeekCommandTime = .distantPast
        }
        SpectralIntegrityAnalyzer.shared.resetForNewTrack(trackKey: cleanKey ?? "")

        if let sr = expectedSampleRate, let norm = self.normalizeRate(sr) {
            let rawDepth = expectedBitDepth ?? (norm >= 48000.0 ? 24 : 16)
            let depth = rawDepth > 0 ? rawDepth : (norm >= 48000.0 ? 24 : 16)
            self.isFormatLockedForCurrentTrack = true
            // Pre-inspected format comes from cache/metadata (not live ACAppleLosslessDecoder), so keep `isAuthoritativelyLocked = false`
            // allowing live ACAppleLosslessDecoder verification within 12.0s to confirm or self-heal the rate & bit depth!
            self.isAuthoritativelyLocked = false
            self.lockTimestamp = Date()
            self.pendingNextTrackFormat = nil
            NSLog("[BitPerfectLogMonitor] 🔄 Track state reset with pre-inspected format: %.1f kHz, %d-bit [Format Locked]", norm / 1000.0, depth)
            self.confirmSampleRate(norm, bitDepth: depth, isLossless: true, reason: "PreInspectedTrackFormat")
        } else if !clearPrebuffer, let key = cleanKey, !key.isEmpty, let prebuffered = self.pendingNextTrackFormat, Date().timeIntervalSince(prebuffered.timestamp) < 120.0 {
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
            } else if let prebuffered = self.pendingNextTrackFormat, Date().timeIntervalSince(prebuffered.timestamp) >= 120.0 {
                self.pendingNextTrackFormat = nil
            }
            self.currentDetectedSampleRate = nil
            self.currentDetectedBitDepth = nil
            self.currentIsLossless = false
            self.isFormatLockedForCurrentTrack = false
            self.isAuthoritativelyLocked = false
            self.lockTimestamp = .distantPast
            NSLog("[BitPerfectLogMonitor] 🔄 Track state reset on track change (Format lock released)")

            // If playing a lossy AAC stream that emits no ALAC decoder log, fall back to standard 44.1 kHz / 16-bit PCM
            // ONLY after Music.app has genuinely started rendering audio frames (prevents false AAC lock during cloud buffering / CDN stalls).
            if !PlaybackRouter.shared.isTestingEnvironment, let key = cleanKey, !key.isEmpty {
                var activeAudioDetectedAt: Date? = nil
                func scheduleLossyFallbackCheck(attempt: Int, delay: TimeInterval) {
                    let checkItem = DispatchWorkItem { [weak self] in
                        guard let self = self else { return }
                        guard !self.isFormatLockedForCurrentTrack, !self.currentIsLossless, self.currentLockedTrackKey == key else { return }
                        let (stillTransitioning, cachedState, cachedPos) = PlaybackStateStore.shared.withLock {
                            (
                                PlaybackStateStore.shared.isStagingCloudTrack || PlaybackStateStore.shared.isTransitioningTrack,
                                PlaybackStateStore.shared.lastPlayerStatusCache?.status.playerState ?? "stopped",
                                PlaybackStateStore.shared.lastPlayerStatusCache?.status.position ?? 0.0
                            )
                        }
                        let hasAudioStarted = !stillTransitioning && (
                            (cachedState == "playing" && cachedPos > 0.15) ||
                            AudioProcessTapService.isMusicAppRunningAudioOutput()
                        )
                        if !hasAudioStarted {
                            activeAudioDetectedAt = nil
                            if attempt < 24 {
                                scheduleLossyFallbackCheck(attempt: attempt + 1, delay: 2.5)
                            }
                            return
                        }
                        let now = Date()
                        if activeAudioDetectedAt == nil {
                            activeAudioDetectedAt = now
                        }
                        // Ensure at least 2.2s of genuine audio output elapsed so delayed ALACDecoder log lines are never raced
                        if let started = activeAudioDetectedAt, attempt > 0, now.timeIntervalSince(started) < 2.2 {
                            scheduleLossyFallbackCheck(attempt: attempt + 1, delay: 2.2)
                            return
                        }
                        self.isFormatLockedForCurrentTrack = true
                        self.isAuthoritativelyLocked = false
                        self.lockTimestamp = now
                        self.confirmSampleRate(44100.0, bitDepth: 16, isLossless: false, reason: "AACStreamDefault16Bit44kHz")
                    }
                    self.lossyFallbackWorkItem = checkItem
                    self.queue.asyncAfter(deadline: .now() + delay, execute: checkItem)
                }
                scheduleLossyFallbackCheck(attempt: 0, delay: 3.6)
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
            self.lossyFallbackWorkItem?.cancel()
            self.lossyFallbackWorkItem = nil
            self.isFormatLockedForCurrentTrack = true
            self.confirmSampleRate(normalized, bitDepth: depth, isLossless: isLossless, reason: "LocalTrackMetadata")
        }
    }

    public func syncMusicAppSmartTransitions(forBitPerfectEnabled enabled: Bool, minimumEnforceInterval: TimeInterval = 0) {
        transitionsPrefLock.lock()
        defer { transitionsPrefLock.unlock() }

        if enabled && minimumEnforceInterval > 0 {
            let now = Date()
            if now.timeIntervalSince(lastSmartTransitionEnforcementAt) < minimumEnforceInterval {
                return
            }
            lastSmartTransitionEnforcementAt = now
        }

        let readTransitionsEnabled: () -> Bool?
        let writeTransitionsEnabled: (Bool) -> Void

        if let testAccessor = musicTransitionsPrefAccessorForTesting {
            readTransitionsEnabled = testAccessor.read
            writeTransitionsEnabled = testAccessor.write
        } else {
            guard !PlaybackRouter.shared.isTestingEnvironment else { return }
            let domain = "com.apple.Music" as CFString
            let key = "TransitionsEnabled" as CFString
            readTransitionsEnabled = {
                CFPreferencesAppSynchronize(domain)
                guard let raw = CFPreferencesCopyAppValue(key, domain) else { return nil }
                if let num = raw as? NSNumber {
                    return num.boolValue
                }
                return nil
            }
            writeTransitionsEnabled = { newBool in
                CFPreferencesSetAppValue(key, newBool ? kCFBooleanTrue : kCFBooleanFalse, domain)
                CFPreferencesAppSynchronize(domain)
            }
        }

        let savedRestoreKey = "BitPerfectSavedMusicTransitionsEnabled"
        if enabled {
            let current = readTransitionsEnabled()
            if current == true {
                AppStorageProvider.shared.set(true, forKey: savedRestoreKey)
                writeTransitionsEnabled(false)
                NSLog("[BitPerfectLogMonitor] 🛡 Bit-Perfect ON: Automatically disabled Music.app Smart Transition (AutoMix / Crossfade)")
            } else if current == nil {
                writeTransitionsEnabled(false)
                NSLog("[BitPerfectLogMonitor] 🛡 Bit-Perfect ON: Explicitly set Music.app TransitionsEnabled = false")
            }
        } else {
            let shouldRestore = AppStorageProvider.shared.bool(forKey: savedRestoreKey)
            AppStorageProvider.shared.removeObject(forKey: savedRestoreKey)
            if shouldRestore {
                writeTransitionsEnabled(true)
                NSLog("[BitPerfectLogMonitor] 🔄 Bit-Perfect OFF: Restored Music.app Smart Transition (TransitionsEnabled = true)")
            }
        }
    }

    private func startInternal() {
        if PlaybackRouter.shared.isTestingEnvironment {
            return
        }

        if self.isEnabled {
            syncMusicAppSmartTransitions(forBitPerfectEnabled: true)
        }

        if let existing = self.process, existing.isRunning {
            return
        }
        stopInternal()
        reapPreviousLogStreamPIDFile()
        installSignalCleanupIfNeeded()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/log")

        // Focused predicate on Music process to minimize CPU overhead, capture lossless ALAC stream rates,
        // and observe MediaPlaybackCore Smart Transition / Dead-Air cutoff timestamps before AutoPlay bleed.
        let predicate = #"(process == "Music" OR subsystem == "com.apple.Music") AND (eventMessage CONTAINS[c] "sample" OR eventMessage CONTAINS[c] "lossless" OR eventMessage CONTAINS[c] "asbd" OR eventMessage CONTAINS[c] "kHz" OR eventMessage CONTAINS "Observe transition start:" OR eventMessage CONTAINS "overlapStartSourceTime:" OR eventMessage CONTAINS "smartTransitionWillBegin" OR eventMessage CONTAINS "overlappedPlaybackWillBegin")"#

        proc.arguments = [
            "stream",
            "--style", "ndjson",
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
            writeLogStreamPIDFile(proc.processIdentifier)
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
        bufferReadOffset = 0

        if let proc = process {
            process = nil
            proc.terminationHandler = nil
            clearLogStreamPIDFile()
            if proc.isRunning {
                let pid = proc.processIdentifier
                proc.terminate()
                queue.asyncAfter(deadline: .now() + 0.15) {
                    if proc.isRunning {
                        kill(pid, SIGKILL)
                    }
                }
            }
        }
    }

    // MARK: - DAC Reconnect / Device Switch Support

    public func reapplyCurrentFormat() {
        let dspActive = AudioEngineController.shared.isActivePipelineHook
        let dspConfigured = AudioEngineController.shared.currentConfigurationSnapshot().mode != .bitPerfectPassthrough
        let dlnaActive = DLNADiscoveryManager.shared.hasActiveRenderer
        guard (isEnabled || dspActive || (dspConfigured && dlnaActive)), let rate = currentDetectedSampleRate else { return }
        let bitDepth = currentDetectedBitDepth ?? (rate >= 48000.0 ? 24 : 16)
        if dspActive {
            let effectiveTapRate = AudioProcessTapService.shared.resolveEffectiveTapSampleRate(forRequestedRate: Int(rate.rounded()))
            AudioProcessTapService.shared.setFormat(sampleRate: effectiveTapRate, bitDepth: bitDepth)
            Task {
                await AudioEngineController.shared.notifySourceSampleRateChanged(Double(effectiveTapRate))
            }
            return
        }
        NSLog("[BitPerfectLogMonitor] 🔄 Reapplying current format to audio device: %.1f kHz, %d-бит", rate / 1000.0, bitDepth)
        applyFormat(rate: rate, bitDepth: bitDepth)
    }

    // MARK: - Debounce & Apply

    internal func sampleRateDetected(_ rate: Double, bitDepth: Int, isAuthoritative: Bool, isLossless: Bool = true, reason: String) {
        // Filter out unreasonable rates
        guard rate >= 44100.0 && rate <= 768000.0 else { return }
        let validDepth = !isLossless ? 16 : (bitDepth > 0 ? bitDepth : (rate >= 48000.0 ? 24 : 16))

        // 0. Explicit Track Switch Teardown Gate:
        // Ignore trailing ALACDecoder / AudioQueue logs from the dying outgoing track while AMR is replacing the queue in Music.app!
        if isSuppressingTeardownLogs {
            if Date().timeIntervalSince(teardownSuppressStartedAt) < 2.5 {
                NSLog("[BitPerfectLogMonitor] 🛡 Ignored teardown decoder log (%.1f kHz, %d-bit) while staging new track", rate / 1000.0, validDepth)
                return
            }
            isSuppressingTeardownLogs = false
        }

        // 1. Strict Mid-Playback Format Lock & Gapless Pre-buffering Isolation:
        // Once format is locked for the current playing track (isFormatLockedForCurrentTrack == true),
        // NEVER invoke CoreAudioDeviceManager.setFormat again mid-track!
        // Exception: if a preliminary/pre-inspected lock occurred (!isAuthoritativelyLocked) and the live
        // authoritative ALAC decoder arrives within 12.0s, confirm or self-heal immediately!
        if isFormatLockedForCurrentTrack {
            if isAuthoritative {
                let elapsed = Date().timeIntervalSince(lockTimestamp)
                // Within the first 5.0s of locking the current track, duplicate ALACDecoder / FigPlaybackReport
                // lines belong to the active track itself; after 5.0s, a new authoritative ALACDecoder line is
                // Music.app gaplessly pre-buffering the NEXT track (even if it shares the same rate & bit depth!).
                if isAuthoritativelyLocked &&
                   elapsed < 5.0 &&
                   rate == currentDetectedSampleRate &&
                   validDepth == currentDetectedBitDepth &&
                   isLossless == currentIsLossless {
                    return
                }
                if (!isAuthoritativelyLocked && elapsed < 12.0) ||
                   (rate == currentDetectedSampleRate && (validDepth != currentDetectedBitDepth || isLossless != currentIsLossless) && elapsed < 3.5) {
                    lossyFallbackWorkItem?.cancel()
                    lossyFallbackWorkItem = nil
                    let alreadyMatching = (rate == currentDetectedSampleRate && validDepth == currentDetectedBitDepth && isLossless == currentIsLossless)
                    isAuthoritativelyLocked = true
                    currentIsLossless = isLossless
                    if alreadyMatching {
                        if isLossless, let lockedKey = currentLockedTrackKey, !lockedKey.isEmpty {
                            cacheLockedTrackKeyFormat(lockedKey, catalogId: currentLockedCatalogId, sampleRate: rate, bitDepth: validDepth)
                        }
                        return
                    }
                    confirmSampleRate(rate, bitDepth: validDepth, isLossless: isLossless, reason: reason)
                    return
                }
                // Gapless Pre-buffering Isolation: store pre-buffered next track format ONLY during genuine pre-buffering
                // (never on pause, never within 4.5s of a seek, and never far before EOF on long tracks!)
                if isLossless {
                    let (isPaused, sinceSeek, estPos, trackDur) = PlaybackStateStore.shared.withLock { () -> (Bool, TimeInterval, Double, Double) in
                        let now = Date()
                        let seekAge = now.timeIntervalSince(PlaybackStateStore.shared.lastSeekCommandTime)
                        var pos = PlaybackStateStore.shared.lastKnownPosition
                        var dur = 0.0
                        if let cached = PlaybackStateStore.shared.lastPlayerStatusCache {
                            dur = cached.status.duration
                            let cacheAge = max(0.0, now.timeIntervalSince(cached.timestamp))
                            let interp = cached.status.playerState == "playing" ? cached.status.position + cacheAge : cached.status.position
                            pos = max(pos, interp)
                        }
                        return (PlaybackStateStore.shared.isUserPaused, seekAge, pos, dur)
                    }
                    let isNearTrackEnd = PlaybackRouter.shared.isTestingEnvironment || trackDur <= 55.0 || estPos >= trackDur - 55.0
                    guard !isPaused, sinceSeek >= 4.5, isNearTrackEnd else {
                        return
                    }
                    pendingNextTrackFormat = (sampleRate: rate, bitDepth: validDepth, timestamp: Date())
                    if let nextTrack = PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.latestUpcomingTracks.first }) {
                        let nextCid = MusicKitManager.extractNumericCatalogId(from: nextTrack)
                        cacheTrackFormat(artist: nextTrack.artist, title: nextTrack.name, catalogId: nextCid, sampleRate: rate, bitDepth: validDepth)
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
            lossyFallbackWorkItem?.cancel()
            lossyFallbackWorkItem = nil
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
            self.lossyFallbackWorkItem?.cancel()
            self.lossyFallbackWorkItem = nil
            self.isFormatLockedForCurrentTrack = true
            self.isAuthoritativelyLocked = false
            self.lockTimestamp = Date()
            self.confirmSampleRate(rate, bitDepth: validDepth, isLossless: isLossless, reason: reason)
        }
        debounceWorkItem = item
        queue.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    internal func confirmSampleRate(_ rate: Double, bitDepth: Int, isLossless: Bool = true, reason: String) {
        lossyFallbackWorkItem?.cancel()
        lossyFallbackWorkItem = nil

        let validDepth = !isLossless ? 16 : (bitDepth > 0 ? bitDepth : (rate >= 48000.0 ? 24 : 16))
        currentDetectedSampleRate = rate
        currentDetectedBitDepth = validDepth
        currentIsLossless = isLossless
        currentDetectedBitRate = isLossless ? Int(rate * Double(validDepth) * 2 / 1000.0) : 256

        let desc = formatQualityString(rate: rate, bitDepth: validDepth, isLossless: isLossless)
        currentQualityDescription = desc

        if isLossless, let lockedKey = currentLockedTrackKey, !lockedKey.isEmpty {
            cacheLockedTrackKeyFormat(lockedKey, catalogId: currentLockedCatalogId, sampleRate: rate, bitDepth: validDepth)
        }
        // Do NOT call PlaybackStateStore.shared.invalidateStatusCache() here!
        // PlayerStatusEngine.getPlayerStatus() dynamically overlays BitPerfectLogMonitor's sampleRate/bitDepth/audioQuality
        // onto the cached Music.app track state without forcing a 17-property Tier 2 AppleScript during DAC clock switching.
        MusicAppLifecycleManager.shared.reportAudioActivity()

        NSLog("[BitPerfectLogMonitor] 🎯 Locked track format: %.1f kHz, %d-бит (%@) [Trigger: %@]", rate / 1000.0, validDepth, desc, reason)

        formatSwitchCountForCurrentTrack += 1
        let enabled = self.isEnabled
        let dspActive = AudioEngineController.shared.isActivePipelineHook
        let dspConfigured = AudioEngineController.shared.currentConfigurationSnapshot().mode != .bitPerfectPassthrough
        let dlnaActive = DLNADiscoveryManager.shared.hasActiveRenderer
        if dspActive {
            let effectiveTapRate = AudioProcessTapService.shared.resolveEffectiveTapSampleRate(forRequestedRate: Int(rate.rounded()))
            AudioProcessTapService.shared.setFormat(sampleRate: effectiveTapRate, bitDepth: validDepth)
            Task {
                await AudioEngineController.shared.notifySourceSampleRateChanged(Double(effectiveTapRate))
            }
        } else if enabled || (dspConfigured && dlnaActive) {
            applyFormat(rate: rate, bitDepth: validDepth)
        }

        let callback = self.onFormatChanged
        DispatchQueue.main.async {
            callback?(rate, validDepth, desc)
            if enabled || dspActive || dspConfigured {
                NotificationCenter.default.post(
                    name: .bitPerfectFormatDidChange,
                    object: nil,
                    userInfo: [
                        "sampleRate": rate,
                        "bitDepth": validDepth,
                        "description": desc,
                        "isEnabled": enabled || dspActive || dspConfigured
                    ]
                )
            }
            MenuManager.shared.updateMenuState()
        }
        DispatchQueue.global(qos: .utility).async {
            UPnPMediaRendererServer.shared.notifySubscribers(force: true)
        }
    }

    internal func applyFormat(rate: Double, bitDepth: Int) {
        if AudioEngineController.shared.isActivePipelineHook {
            let effectiveTapRate = AudioProcessTapService.shared.resolveEffectiveTapSampleRate(forRequestedRate: Int(rate.rounded()))
            AudioProcessTapService.shared.setFormat(sampleRate: effectiveTapRate, bitDepth: bitDepth)
            Task {
                await AudioEngineController.shared.notifySourceSampleRateChanged(Double(effectiveTapRate))
            }
        } else if DLNADiscoveryManager.shared.hasActiveRenderer {
            let requestedTapRate = Int(rate.rounded())
            let effectiveTapDepth = (bitDepth == 16) ? 16 : 24
            if AudioProcessTapService.shared.subscriberCount > 0,
               (AudioProcessTapService.shared.sampleRate != requestedTapRate || AudioProcessTapService.shared.bitDepth != effectiveTapDepth) {
                DLNADiscoveryManager.shared.closeLiveStreamConnectionsForFormatSwitch()
            }
            CoreAudioDeviceManager.shared.setFormat(sampleRate: rate, bitDepth: bitDepth)
            AudioProcessTapService.shared.setFormat(sampleRate: requestedTapRate, bitDepth: bitDepth)
        } else {
            CoreAudioDeviceManager.shared.setFormat(sampleRate: rate, bitDepth: bitDepth)
            var effectiveLocalRate = rate
            if !PlaybackRouter.shared.isTestingEnvironment,
               let defID = CoreAudioDeviceManager.shared.getDefaultOutputDeviceID(), defID != 0 {
                let avail = CoreAudioDeviceManager.shared.availableSampleRates(deviceID: defID)
                if !avail.isEmpty && !avail.contains(where: { abs($0 - rate) < 1.0 }) {
                    let candidates = [rate / 2.0, rate / 4.0, (Int(rate.rounded()) % 48_000 == 0) ? 48_000.0 : 44_100.0]
                    if let subRate = candidates.first(where: { cand in cand >= 44_100.0 && avail.contains(where: { abs($0 - cand) < 1.0 }) }) {
                        effectiveLocalRate = subRate
                    } else {
                        let hwRate = HALDeviceManager.nominalSampleRate(deviceID: defID)
                        if hwRate >= 44_100.0 {
                            effectiveLocalRate = hwRate
                        }
                    }
                }
            }
            if RoomAcousticService.shared.isLocalPassthroughEQActive {
                RoomAcousticService.shared.notifyLocalOutputFormatChanged(sampleRateHz: effectiveLocalRate)
            }
            AudioProcessTapService.shared.setFormat(sampleRate: Int(effectiveLocalRate.rounded()), bitDepth: bitDepth)
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
