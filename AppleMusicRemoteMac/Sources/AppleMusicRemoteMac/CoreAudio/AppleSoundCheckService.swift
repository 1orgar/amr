import Foundation
import AVFoundation
import Accelerate

/// Extracts Apple's official `iTunNORM` SoundCheck loudness metadata from local tracks
/// or Apple Music catalog `.m4a` stream headers (`Range: bytes=0-49151`), and for tracks
/// completely lacking `iTunNORM` metadata, computes an acoustic ITU-R BS.1770 / RMS loudness
/// normalization matrix (from local audio slices or live CoreAudio PCM via `SpectralIntegrityAnalyzer`)
/// and caches it persistently by `trackId` and `artist:title`.
public final class AppleSoundCheckService: @unchecked Sendable {
    public static let shared = AppleSoundCheckService()

    internal struct CacheStore: Codable {
        var entries: [String: Double] = [:]
    }

    internal static let maxCacheEntries: Int = 5000
    internal static let maxProvisionalKeys: Int = 512

    internal let lock = NSLock()
    internal let localScanQueue = DispatchQueue(label: "com.amr.soundcheck.local", qos: .utility)
    internal let persistenceQueue = DispatchQueue(label: "com.amr.soundcheck.persistence", qos: .utility)
    internal let usesCustomCacheFileForTesting: Bool
    internal var memoryCache: [String: Double] = [:]
    internal var liveDspProvisionalKeys: Set<String> = []
    internal var liveDspProvisionalOrder: [String] = []
    internal var inFlightKeys: Set<String> = []
    internal var inFlightLocalKeys: Set<String> = []
    internal var lastTrackKey: String = ""
    internal var lastTrackId: String = ""
    internal var lastTrackCatalogId: String?
    internal var lastTrackName: String = ""
    internal var lastTrackArtist: String = ""
    internal var lastTrackAlbum: String = ""
    internal var lastTrackIsLocal: Bool = false
    internal var explicitTransitionLockUntil: Date = .distantPast

    internal let urlSession: URLSession = {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 4.0
        sessionConfig.timeoutIntervalForResource = 5.0
        return URLSession(configuration: sessionConfig)
    }()

    internal let cacheFileURL: URL

    internal init(customCacheFileURL: URL? = nil) {
        if let customURL = customCacheFileURL {
            try? FileManager.default.createDirectory(at: customURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            self.cacheFileURL = customURL
            self.usesCustomCacheFileForTesting = true
        } else {
            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let appDir = cachesDir.appendingPathComponent("AppleMusicRemoteMac", isDirectory: true)
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
            self.cacheFileURL = appDir.appendingPathComponent("soundcheck_itunnorm_cache.json")
            self.usesCustomCacheFileForTesting = false
        }
        loadCacheFromDisk()
    }

    internal func insertProvisionalKeyLocked(_ key: String) {
        if liveDspProvisionalKeys.contains(key) {
            return
        }
        if liveDspProvisionalKeys.count >= Self.maxProvisionalKeys {
            while liveDspProvisionalKeys.count >= Self.maxProvisionalKeys && !liveDspProvisionalOrder.isEmpty {
                let oldest = liveDspProvisionalOrder.removeFirst()
                liveDspProvisionalKeys.remove(oldest)
            }
        }
        liveDspProvisionalKeys.insert(key)
        liveDspProvisionalOrder.append(key)
    }

    internal func removeProvisionalKeyLocked(_ key: String) {
        if liveDspProvisionalKeys.remove(key) != nil {
            if let idx = liveDspProvisionalOrder.firstIndex(of: key) {
                liveDspProvisionalOrder.remove(at: idx)
            }
        }
    }

    internal func flushSyncForTesting() {
        persistenceQueue.sync {}
    }

    // MARK: - Public API

    /// Parses an `iTunNORM` string (10 space-separated 8-digit hex integers) into a dB gain offset.
    ///
    /// Apple's SoundCheck formula:
    /// `gainDb = -10.0 * log10(max(v0, v1) / 1000.0)`
    /// where `v0` (Left) and `v1` (Right) are the first two 32-bit hex integers,
    /// and `0x000003E8` (`1000`) represents `0.0 dB` reference level.
    public static func parseITunNormHex(_ rawString: String) -> Double? {
        let tokens = rawString
            .split(whereSeparator: { $0.isWhitespace || $0 == "\0" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count == 8 && $0.allSatisfy({ $0.isHexDigit }) }

        guard tokens.count >= 2,
              let v0 = UInt64(tokens[0], radix: 16),
              let v1 = UInt64(tokens[1], radix: 16) else {
            return nil
        }

        let peakNorm = Double(max(v0, v1))
        // Guard against zero or uninitialized 0xFFFFFFFF tags
        guard peakNorm > 0, peakNorm < 0x0FFFFFFF else {
            return nil
        }

        let rawDb = -10.0 * log10(peakNorm / 1000.0)
        guard rawDb.isFinite else { return nil }

        // Clamp to a sane acoustic range (-18 dB ... +12 dB) and round to 2 decimal places
        let clamped = max(-18.0, min(12.0, rawDb))
        return (clamped * 100.0).rounded() / 100.0
    }

    /// Checks whether a string is a valid Apple Music / iTunes catalog Adam ID (numeric, >= 5,000,000),
    /// filtering out small local Music.app `database ID` integers (like `4135` or `9099`).
    public static func isValidCatalogId(_ raw: String?) -> Bool {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed.allSatisfy({ $0.isNumber }),
              let val = Int64(trimmed),
              val >= 5_000_000 else {
            return false
        }
        return true
    }

    /// Scans binary MP4 (`moov.udta.meta.ilst`), ID3v2 (UTF-8 or UTF-16), or Vorbis tag bytes for the `iTunNORM` atom
    /// and extracts the SoundCheck gain in dB.
    public static func extractITunNormGainDb(from data: Data) -> Double? {
        let utf8Markers = [
            Data("iTunNORM".utf8),
            Data("ITUNNORM".utf8),
            Data("itunnorm".utf8)
        ]
        for marker in utf8Markers {
            if let markerRange = data.range(of: marker) {
                let searchStart = markerRange.upperBound
                let searchEnd = min(data.count, searchStart + 320)
                if searchStart < searchEnd {
                    let windowData = data.subdata(in: searchStart..<searchEnd)
                    var asciiChars = [Character]()
                    asciiChars.reserveCapacity(windowData.count)
                    for byte in windowData {
                        if (byte >= 0x30 && byte <= 0x39) ||
                           (byte >= 0x41 && byte <= 0x46) ||
                           (byte >= 0x61 && byte <= 0x66) {
                            asciiChars.append(Character(UnicodeScalar(byte)))
                        } else {
                            asciiChars.append(" ")
                        }
                    }
                    if let parsed = parseITunNormHex(String(asciiChars)) {
                        return parsed
                    }
                }
            }
        }

        // Check UTF-16LE / UTF-16BE ID3v2.3 COMM frame ("i\0T\0u\0n\0N\0O\0R\0M")
        let utf16Marker = Data([0x69, 0x00, 0x54, 0x00, 0x75, 0x00, 0x6E, 0x00, 0x4E, 0x00, 0x4F, 0x00, 0x52, 0x00, 0x4D])
        if let markerRange = data.range(of: utf16Marker) {
            let searchStart = markerRange.upperBound
            let searchEnd = min(data.count, searchStart + 640)
            if searchStart < searchEnd {
                let windowData = data.subdata(in: searchStart..<searchEnd)
                var asciiChars = [Character]()
                asciiChars.reserveCapacity(windowData.count / 2)
                for byte in windowData {
                    if byte == 0x00 { continue }
                    if (byte >= 0x30 && byte <= 0x39) ||
                       (byte >= 0x41 && byte <= 0x46) ||
                       (byte >= 0x61 && byte <= 0x66) {
                        asciiChars.append(Character(UnicodeScalar(byte)))
                    } else {
                        asciiChars.append(" ")
                    }
                }
                if let parsed = parseITunNormHex(String(asciiChars)) {
                    return parsed
                }
            }
        }

        return nil
    }

    /// Synchronizes the currently playing track with the SoundCheck service.
    /// If cached, immediately applies the hardware volume offset on `ExternalAmpTCPController`.
    /// Otherwise resolves `iTunNORM` (or computes local acoustic loudness) asynchronously and applies it once fetched.
    public func syncCurrentTrack(
        trackKey: String,
        trackId: String = "",
        catalogId: String?,
        name: String,
        artist: String,
        album: String,
        isLocal: Bool,
        isExplicitTransition: Bool = false
    ) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTrackId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        let canonicalKey = Self.makeCanonicalKey(artist: cleanArtist, name: cleanName)

        let (skipStalePoll, alreadySynced, cachedGain, shouldResolve) = lock.withLock { () -> (Bool, Bool, Double?, Bool) in
            let now = Date()
            if isExplicitTransition {
                self.explicitTransitionLockUntil = now.addingTimeInterval(2.2)
            } else if !self.lastTrackKey.isEmpty && self.lastTrackKey != canonicalKey && now < self.explicitTransitionLockUntil {
                // Ignore stale outgoing Music.app poll while staging the newly requested queue track
                return (true, true, nil, false)
            }

            let isSameTrack = (self.lastTrackKey == canonicalKey)
            self.lastTrackKey = canonicalKey
            if !cleanTrackId.isEmpty && cleanTrackId != "0" {
                self.lastTrackId = cleanTrackId
            } else if !isSameTrack {
                self.lastTrackId = ""
            }
            self.lastTrackCatalogId = catalogId
            self.lastTrackName = cleanName
            self.lastTrackArtist = cleanArtist
            self.lastTrackAlbum = album
            self.lastTrackIsLocal = isLocal

            if let gain = self.lookupCachedGainLocked(canonicalKey: canonicalKey, trackId: cleanTrackId, catalogId: catalogId) {
                return (false, isSameTrack, gain, false)
            }
            let alreadyInFlight = isLocal
                ? self.inFlightLocalKeys.contains(canonicalKey)
                : self.inFlightKeys.contains(canonicalKey)
            if !alreadyInFlight {
                if isLocal {
                    self.inFlightLocalKeys.insert(canonicalKey)
                } else {
                    self.inFlightKeys.insert(canonicalKey)
                }
            }
            return (false, isSameTrack, nil, !alreadyInFlight)
        }

        if skipStalePoll {
            return
        }

        if let cachedGain {
            if !alreadySynced
                || ExternalAmpTCPController.shared.currentTrackKey != canonicalKey
                || ExternalAmpTCPController.shared.currentTrackGainDb != cachedGain {
                ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: canonicalKey, gainDb: cachedGain)
            }
            return
        }

        guard shouldResolve else { return }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let resolvedGain = await self.resolveGainDb(
                canonicalKey: canonicalKey,
                trackId: cleanTrackId,
                catalogId: catalogId,
                name: cleanName,
                artist: cleanArtist,
                album: album,
                isLocal: isLocal
            )
            let isStillCurrent = self.lock.withLock { () -> Bool in
                if isLocal {
                    self.inFlightLocalKeys.remove(canonicalKey)
                } else {
                    self.inFlightKeys.remove(canonicalKey)
                }
                return self.lastTrackKey == canonicalKey
            }
            if isStillCurrent {
                if let gain = resolvedGain {
                    ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: canonicalKey, gainDb: gain)
                    WebSocketServer.shared.broadcastStatus(includeQueue: false)
                } else if ExternalAmpTCPController.shared.currentTrackGainDb == nil {
                    // Preserve existing comfortable volume offset while awaiting Tier-3 live PCM LUFS (~1.5s) instead of spiking to 0.00 dB!
                    ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: canonicalKey, gainDb: nil)
                }
            }
        }
    }

    /// Re-applies SoundCheck for the last known track (e.g., when the user toggles SoundCheck ON in Settings).
    public func reapplyCurrentTrack() {
        let snapshot = lock.withLock {
            (lastTrackKey, lastTrackId, lastTrackCatalogId, lastTrackName, lastTrackArtist, lastTrackAlbum, lastTrackIsLocal)
        }
        guard !snapshot.0.isEmpty, !snapshot.3.isEmpty else { return }
        lock.withLock {
            lastTrackKey = ""
        }
        syncCurrentTrack(
            trackKey: snapshot.0,
            trackId: snapshot.1,
            catalogId: snapshot.2,
            name: snapshot.3,
            artist: snapshot.4,
            album: snapshot.5,
            isLocal: snapshot.6,
            isExplicitTransition: true
        )
    }

    /// Prefetches `iTunNORM` metadata for upcoming queue tracks so track transitions apply volume offsets with 0ms latency.
    public func prefetchTrack(trackId: String = "", catalogId: String?, name: String, artist: String, album: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTrackId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        let canonicalKey = Self.makeCanonicalKey(artist: cleanArtist, name: cleanName)
        let shouldStart = lock.withLock { () -> Bool in
            if lookupCachedGainLocked(canonicalKey: canonicalKey, trackId: cleanTrackId, catalogId: catalogId) != nil {
                return false
            }
            if inFlightKeys.contains(canonicalKey) {
                return false
            }
            inFlightKeys.insert(canonicalKey)
            return true
        }
        guard shouldStart else { return }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let resolvedGain = await self.resolveGainDb(
                canonicalKey: canonicalKey,
                trackId: cleanTrackId,
                catalogId: catalogId,
                name: cleanName,
                artist: cleanArtist,
                album: album,
                isLocal: false
            )
            let (isNowCurrent, effectiveGain, hasAuthoritativeCachedGain): (Bool, Double?, Bool) = self.lock.withLock {
                _ = self.inFlightKeys.remove(canonicalKey)
                let cached = self.lookupCachedGainLocked(canonicalKey: canonicalKey, trackId: cleanTrackId, catalogId: catalogId)
                return (self.lastTrackKey == canonicalKey, resolvedGain ?? cached, cached != nil)
            }
            if isNowCurrent {
                if effectiveGain != nil || (!hasAuthoritativeCachedGain && ExternalAmpTCPController.shared.currentTrackGainDb == nil) {
                    ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: canonicalKey, gainDb: effectiveGain)
                    WebSocketServer.shared.broadcastStatus(includeQueue: false)
                }
            }
        }
    }

    /// Returns cached SoundCheck gain (in dB) if already known.
    public func getCachedGainDb(artist: String, name: String, trackId: String = "", catalogId: String? = nil) -> Double? {
        let canonicalKey = Self.makeCanonicalKey(artist: artist, name: name)
        return lock.withLock {
            lookupCachedGainLocked(canonicalKey: canonicalKey, trackId: trackId, catalogId: catalogId)
        }
    }

    /// Returns `true` if the track already has an authoritative `iTunNORM` or finalized DSP loudness entry in cache.
    public func hasFinalizedCachedGain(trackId: String, trackKey: String) -> Bool {
        let cleanKey = trackKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanId = trackId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lock.withLock {
            if !cleanKey.isEmpty, liveDspProvisionalKeys.contains(cleanKey) {
                return false
            }
            if !cleanId.isEmpty, cleanId != "0", memoryCache["id:\(cleanId)"] != nil {
                return true
            }
            if !cleanKey.isEmpty, memoryCache[cleanKey] != nil {
                return true
            }
            return false
        }
    }

    /// Records a self-computed DSP loudness normalization gain (in dB) from `SpectralIntegrityAnalyzer`
    /// for tracks that completely lack `iTunNORM` metadata, caching it persistently by `trackId` and `trackKey`
    /// and immediately updating `ExternalAmpTCPController` if the track is currently playing.
    public func recordLiveDSPLoudness(
        trackId: String,
        trackKey: String,
        gainDb: Double,
        isRefined: Bool
    ) {
        guard gainDb.isFinite else { return }
        let clamped = (max(-18.0, min(12.0, gainDb)) * 100.0).rounded() / 100.0
        let cleanKey = trackKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty && cleanKey != ":" else { return }

        let (shouldApply, activeKey, snapshotToSave) = lock.withLock { () -> (Bool, String, [String: Double]?) in
            // Do not overwrite an authoritative iTunNORM or finalized local file scan
            let existingByKey = memoryCache[cleanKey]
            let existingById = (!cleanId.isEmpty && cleanId != "0") ? memoryCache["id:\(cleanId.lowercased())"] : nil
            let isProvisional = liveDspProvisionalKeys.contains(cleanKey)

            if (existingByKey != nil || existingById != nil) && !isProvisional {
                return (false, cleanKey, nil)
            }

            memoryCache[cleanKey] = clamped
            if !cleanId.isEmpty && cleanId != "0" {
                memoryCache["id:\(cleanId.lowercased())"] = clamped
                memoryCache["id:\(cleanId)"] = clamped
            }
            if let cid = lastTrackCatalogId, !cid.isEmpty, cid != "0", lastTrackKey == cleanKey {
                memoryCache["id:\(cid.lowercased())"] = clamped
                memoryCache["id:\(cid)"] = clamped
            }

            if isRefined {
                removeProvisionalKeyLocked(cleanKey)
            } else {
                insertProvisionalKeyLocked(cleanKey)
            }

            let snap = memoryCache
            let isCurrent = (lastTrackKey == cleanKey) || (ExternalAmpTCPController.shared.currentTrackKey == cleanKey)
            return (isCurrent, cleanKey, snap)
        }

        if let snap = snapshotToSave {
            scheduleSaveCacheToDisk(snap)
        }

        if shouldApply {
            NSLog("[AppleSoundCheck] Live DSP loudness matrix for '%@' (id=%@): %+.2f dB (refined=%d)", cleanKey, cleanId, clamped, isRefined ? 1 : 0)
            ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: activeKey, gainDb: clamped)
            WebSocketServer.shared.broadcastStatus(includeQueue: false)
        }
    }

    /// Computes a perceptual ITU-R BS.1770 / SoundCheck loudness normalization gain (in dB)
    /// directly from mono or stereo Float32 PCM samples relative to the `-16.5 dBFS` SoundCheck reference.
    public static func computePerceptualLoudnessGainDb(fromSamples samples: [Float]) -> Double? {
        guard samples.count >= 512 else { return nil }
        let windowSize = min(4096, samples.count)
        let strideStep = max(windowSize / 2, 512)
        var gatedPowerSum: Double = 0.0
        var gatedWindowsCount: Int = 0

        var offset = 0
        while offset + windowSize <= samples.count {
            var meanSq: Float = 0
            samples.withUnsafeBufferPointer { ptr in
                guard let base = ptr.baseAddress else { return }
                vDSP_measqv(base.advanced(by: offset), 1, &meanSq, vDSP_Length(windowSize))
            }
            let winDb = 10.0 * log10(Double(max(meanSq, 1e-10)))
            // Silence gating at -52 dBFS (ignores intro/outro silence)
            if winDb > -52.0 {
                gatedPowerSum += Double(meanSq)
                gatedWindowsCount += 1
            }
            offset += strideStep
        }

        guard gatedWindowsCount > 0 else { return nil }
        let meanPower = gatedPowerSum / Double(gatedWindowsCount)
        let measuredDb = 10.0 * log10(max(meanPower, 1e-10))
        // Apple SoundCheck reference target is -16.5 dBFS gated RMS (~ -16 LUFS)
        let rawGainDb = -16.5 - measuredDb
        guard rawGainDb.isFinite else { return nil }
        let clamped = max(-18.0, min(12.0, rawGainDb))
        return (clamped * 100.0).rounded() / 100.0
    }

    /// Seeds a known gain value into the cache (used in unit tests).
    internal func seedCacheForTesting(artist: String, name: String, trackId: String = "", gainDb: Double) {
        let key = Self.makeCanonicalKey(artist: artist, name: name)
        let cleanId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.withLock {
            removeProvisionalKeyLocked(key)
            memoryCache[key] = gainDb
            if !cleanId.isEmpty && cleanId != "0" {
                memoryCache["id:\(cleanId.lowercased())"] = gainDb
                memoryCache["id:\(cleanId)"] = gainDb
            }
        }
    }

    /// Removes a specific entry from the cache (used in unit tests).
    internal func clearCacheEntryForTesting(artist: String, name: String, trackId: String = "") {
        let key = Self.makeCanonicalKey(artist: artist, name: name)
        let cleanId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot: [String: Double] = lock.withLock {
            removeProvisionalKeyLocked(key)
            memoryCache.removeValue(forKey: key)
            if !cleanId.isEmpty && cleanId != "0" {
                memoryCache.removeValue(forKey: "id:\(cleanId.lowercased())")
                memoryCache.removeValue(forKey: "id:\(cleanId)")
            }
            return memoryCache
        }
        scheduleSaveCacheToDisk(snapshot)
    }
}
