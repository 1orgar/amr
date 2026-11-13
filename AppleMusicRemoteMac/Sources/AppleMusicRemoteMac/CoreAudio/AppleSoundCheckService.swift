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

    private struct CacheStore: Codable {
        var entries: [String: Double] = [:]
    }

    private let lock = NSLock()
    private var memoryCache: [String: Double] = [:]
    private var liveDspProvisionalKeys: Set<String> = []
    private var inFlightKeys: Set<String> = []
    private var inFlightLocalKeys: Set<String> = []
    private var lastTrackKey: String = ""
    private var lastTrackId: String = ""
    private var lastTrackCatalogId: String?
    private var lastTrackName: String = ""
    private var lastTrackArtist: String = ""
    private var lastTrackAlbum: String = ""
    private var lastTrackIsLocal: Bool = false

    private let urlSession: URLSession = {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 4.0
        sessionConfig.timeoutIntervalForResource = 5.0
        return URLSession(configuration: sessionConfig)
    }()

    private let cacheFileURL: URL = {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let appDir = cachesDir.appendingPathComponent("AppleMusicRemoteMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("soundcheck_itunnorm_cache.json")
    }()

    private init() {
        loadCacheFromDisk()
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
        isLocal: Bool
    ) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTrackId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        let canonicalKey = Self.makeCanonicalKey(artist: cleanArtist, name: cleanName)

        let (alreadySynced, cachedGain, shouldResolve) = lock.withLock { () -> (Bool, Double?, Bool) in
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
                return (isSameTrack, gain, false)
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
            return (isSameTrack, nil, !alreadyInFlight)
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
                ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: canonicalKey, gainDb: resolvedGain)
                WebSocketServer.shared.broadcastStatus(includeQueue: false)
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
            isLocal: snapshot.6
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

        let (shouldApply, activeKey) = lock.withLock { () -> (Bool, String) in
            // Do not overwrite an authoritative iTunNORM or finalized local file scan
            let existingByKey = memoryCache[cleanKey]
            let existingById = (!cleanId.isEmpty && cleanId != "0") ? memoryCache["id:\(cleanId.lowercased())"] : nil
            let isProvisional = liveDspProvisionalKeys.contains(cleanKey)

            if (existingByKey != nil || existingById != nil) && !isProvisional {
                return (false, cleanKey)
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
                liveDspProvisionalKeys.remove(cleanKey)
            } else {
                liveDspProvisionalKeys.insert(cleanKey)
            }

            saveCacheToDiskLocked()
            let isCurrent = (lastTrackKey == cleanKey) || (ExternalAmpTCPController.shared.currentTrackKey == cleanKey)
            return (isCurrent, cleanKey)
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
            liveDspProvisionalKeys.remove(key)
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
        lock.withLock {
            liveDspProvisionalKeys.remove(key)
            memoryCache.removeValue(forKey: key)
            if !cleanId.isEmpty && cleanId != "0" {
                memoryCache.removeValue(forKey: "id:\(cleanId.lowercased())")
                memoryCache.removeValue(forKey: "id:\(cleanId)")
            }
            saveCacheToDiskLocked()
        }
    }

    // MARK: - Multi-Tier Resolution

    private func resolveGainDb(
        canonicalKey: String,
        trackId: String,
        catalogId: String?,
        name: String,
        artist: String,
        album: String,
        isLocal: Bool
    ) async -> Double? {
        if let cached = lock.withLock({ lookupCachedGainLocked(canonicalKey: canonicalKey, trackId: trackId, catalogId: catalogId) }) {
            return cached
        }

        // Tier 1: If true local file in Music.app (without cloud catalogId), inspect local file header first (or scan local PCM slices if iTunNORM is absent)
        let hasCloudCatalogId = Self.isValidCatalogId(catalogId)
        if isLocal && !hasCloudCatalogId, let localGain = readLocalCurrentTrackITunNorm(expectedName: name) {
            storeGainInCache(localGain, canonicalKey: canonicalKey, trackId: trackId, catalogId: catalogId)
            NSLog("[AppleSoundCheck] Local track loudness for '%@ - %@': %+.2f dB", artist, name, localGain)
            return localGain
        }

        // Tier 2: Resolve previewUrl via Apple Music / iTunes Lookup or Search API and read first 48 KB of .m4a
        if let previewURL = await fetchApplePreviewURL(catalogId: catalogId, name: name, artist: artist, album: album),
           let streamGain = await fetchITunNormFromPreviewHeader(previewURL: previewURL) {
            storeGainInCache(streamGain, canonicalKey: canonicalKey, trackId: trackId, catalogId: catalogId)
            NSLog("[AppleSoundCheck] Apple iTunNORM for '%@ - %@': %+.2f dB", artist, name, streamGain)
            return streamGain
        }

        // Tier 3: If track has no metadata anywhere, SpectralIntegrityAnalyzer's live PCM loudness matrix
        // will automatically compute, apply, and cache the loudness gain by trackId + canonicalKey within ~2s of playback.
        return nil
    }

    private func readLocalCurrentTrackITunNorm(expectedName: String) -> Double? {
        let script = """
        tell application "Music"
            if player state is not stopped then
                try
                    set trName to name of current track
                    set loc to location of current track
                    if loc is not missing value then
                        return trName & "|||" & (POSIX path of loc)
                    end if
                end try
            end if
        end tell
        return ""
        """
        let (ok, rawOut) = AppleScriptExecutor.shared.execute(script)
        guard ok, let out = rawOut, !out.isEmpty else {
            return nil
        }
        let parts = out.components(separatedBy: "|||")
        guard parts.count == 2 else { return nil }
        let trName = parts[0].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let posixPath = parts[1].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !posixPath.isEmpty,
              trName.caseInsensitiveCompare(expectedName) == .orderedSame else {
            return nil
        }

        let fileURL = URL(fileURLWithPath: posixPath)
        if let handle = try? FileHandle(forReadingFrom: fileURL) {
            let headerData = try? handle.read(upToCount: 65536)
            try? handle.close()
            if let headerData, !headerData.isEmpty,
               let tagGain = Self.extractITunNormGainDb(from: headerData) {
                return tagGain
            }
        }
        // Fallback for local files without iTunNORM metadata: compute multi-point acoustic loudness via AVAudioFile + vDSP
        return computeLocalFileLoudnessGainDb(fileURL: fileURL)
    }

    /// Scans 8 evenly distributed 16384-frame slices of a local audio file (ALAC, FLAC, WAV, AIFF, MP3, AAC)
    /// using `AVAudioFile` and `vDSP_measqv` to compute its gated SoundCheck gain when `iTunNORM` is missing.
    internal func computeLocalFileLoudnessGainDb(fileURL: URL) -> Double? {
        guard let audioFile = try? AVAudioFile(forReading: fileURL) else { return nil }
        let totalFrames = audioFile.length
        guard totalFrames > 4096 else { return nil }
        let format = audioFile.processingFormat
        let channelCount = Int(format.channelCount)
        guard channelCount > 0 else { return nil }

        let sliceFrames: AVAudioFrameCount = 16384
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: sliceFrames) else {
            return nil
        }

        let slicePositions: [Double] = [0.12, 0.22, 0.32, 0.42, 0.52, 0.62, 0.72, 0.82]
        var gatedPowerSum: Double = 0.0
        var gatedSliceCount: Int = 0

        for posRatio in slicePositions {
            let startFrame = AVAudioFramePosition(Double(totalFrames) * posRatio)
            guard startFrame + AVAudioFramePosition(sliceFrames) < totalFrames else { continue }
            audioFile.framePosition = startFrame
            buffer.frameLength = 0
            guard (try? audioFile.read(into: buffer, frameCount: sliceFrames)) != nil else { continue }
            let readCount = Int(buffer.frameLength)
            guard readCount >= 512, let floatChannels = buffer.floatChannelData else { continue }

            var slicePower: Double = 0.0
            let chToRead = min(channelCount, 2)
            for ch in 0..<chToRead {
                var meanSq: Float = 0
                vDSP_measqv(floatChannels[ch], 1, &meanSq, vDSP_Length(readCount))
                slicePower += Double(meanSq)
            }
            slicePower /= Double(chToRead)
            let sliceDb = 10.0 * log10(max(slicePower, 1e-10))
            if sliceDb > -52.0 {
                gatedPowerSum += slicePower
                gatedSliceCount += 1
            }
        }

        guard gatedSliceCount > 0 else { return nil }
        let meanPower = gatedPowerSum / Double(gatedSliceCount)
        let measuredDb = 10.0 * log10(max(meanPower, 1e-10))
        let rawGainDb = -16.5 - measuredDb
        guard rawGainDb.isFinite else { return nil }
        let clamped = max(-18.0, min(12.0, rawGainDb))
        return (clamped * 100.0).rounded() / 100.0
    }

    private func fetchApplePreviewURL(
        catalogId: String?,
        name: String,
        artist: String,
        album: String
    ) async -> URL? {
        let session = self.urlSession

        var resolvedCid = Self.isValidCatalogId(catalogId) ? catalogId?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        if resolvedCid == nil {
            if let cachedCid = MusicKitManager.shared.getCachedTrackCatalogId(name: name, artist: artist, album: album)?.trimmingCharacters(in: .whitespacesAndNewlines),
               Self.isValidCatalogId(cachedCid) {
                resolvedCid = cachedCid
            }
        }

        // 1. Try direct catalogId lookup if valid Apple Music Adam ID
        if let cid = resolvedCid, Self.isValidCatalogId(cid) {
            for storefront in ["RU", "US"] {
                if let url = URL(string: "https://itunes.apple.com/lookup?id=\(cid)&country=\(storefront)"),
                   let preview = await queryPreviewURLFromEndpoint(url: url, expectedArtist: nil, expectedName: nil, expectedAlbum: nil, session: session) {
                    return preview.url
                }
            }
        }

        // 2. Search by artist + track name across storefronts, preferring exact studio/album match
        let queryTerm = "\(artist) \(name)".trimmingCharacters(in: .whitespacesAndNewlines)
        let encodedTerm = queryTerm.amrQueryValueEncoded
        guard !encodedTerm.isEmpty else {
            return nil
        }
        var bestCandidate: (url: URL, score: Int)?
        for storefront in ["RU", "US"] {
            if let url = URL(string: "https://itunes.apple.com/search?term=\(encodedTerm)&entity=song&limit=8&country=\(storefront)"),
               let candidate = await queryPreviewURLFromEndpoint(url: url, expectedArtist: artist, expectedName: name, expectedAlbum: album, session: session) {
                if candidate.score >= 95 {
                    return candidate.url
                }
                if bestCandidate == nil || candidate.score > bestCandidate!.score {
                    bestCandidate = candidate
                }
            }
        }
        return bestCandidate?.url
    }

    private func queryPreviewURLFromEndpoint(
        url: URL,
        expectedArtist: String?,
        expectedName: String?,
        expectedAlbum: String?,
        session: URLSession
    ) async -> (url: URL, score: Int)? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]], !results.isEmpty else {
                return nil
            }

            if let expName = expectedName, !expName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return Self.selectBestPreviewCandidate(
                    from: results,
                    expectedArtist: expectedArtist ?? "",
                    expectedName: expName,
                    expectedAlbum: expectedAlbum ?? ""
                )
            }

            // Direct catalogId lookup (expectedName == nil): return first result with a previewUrl
            for item in results {
                if let prevStr = item["previewUrl"] as? String, let prevURL = URL(string: prevStr) {
                    return (prevURL, 100)
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    internal static func selectBestPreviewCandidate(
        from results: [[String: Any]],
        expectedArtist: String,
        expectedName: String,
        expectedAlbum: String
    ) -> (url: URL, score: Int)? {
        let expName = expectedName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let expArtist = expectedArtist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let expAlbum = expectedAlbum.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let expBaseName = stripEditionSuffix(expName)
        let expIsLive = expName.contains("live") || expAlbum.contains("live")
        let expIsRemaster = expName.contains("remaster") || expAlbum.contains("remaster")

        var best: (url: URL, score: Int)?
        for item in results {
            guard let prevStr = item["previewUrl"] as? String, let prevURL = URL(string: prevStr) else { continue }
            let rName = (item["trackName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let rArtist = (item["artistName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let rAlbum = (item["collectionName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !rName.isEmpty else { continue }

            // Reject tribute / karaoke covers when searching for an original artist
            if !expArtist.contains("tribute") && (rName.contains("tribute") || rArtist.contains("tribute") || rAlbum.contains("tribute")) {
                continue
            }
            if !expArtist.contains("karaoke") && (rName.contains("karaoke") || rArtist.contains("karaoke") || rAlbum.contains("karaoke")) {
                continue
            }

            var score = 0
            // 1. Artist match check
            if !expArtist.isEmpty {
                if rArtist == expArtist {
                    score += 40
                } else if rArtist.contains(expArtist) || expArtist.contains(rArtist) {
                    score += 20
                } else {
                    continue
                }
            }

            // 2. Track title match check
            let rBaseName = stripEditionSuffix(rName)
            if rName == expName {
                score += 50
            } else if !expBaseName.isEmpty && rBaseName == expBaseName {
                score += 35
            } else if rName.contains(expName) || expName.contains(rName) {
                score += 18
            } else {
                continue
            }

            // 3. Album match bonus
            if !expAlbum.isEmpty && !rAlbum.isEmpty {
                let expBaseAlbum = stripEditionSuffix(expAlbum)
                let rBaseAlbum = stripEditionSuffix(rAlbum)
                if rAlbum == expAlbum {
                    score += 35
                } else if !expBaseAlbum.isEmpty && (rBaseAlbum == expBaseAlbum || rAlbum.contains(expBaseAlbum) || expAlbum.contains(rBaseAlbum)) {
                    score += 20
                }
            }

            // 4. Edition compatibility (Studio vs Live / Remaster)
            let candIsLive = rName.contains("live") || rAlbum.contains("live")
            if expIsLive != candIsLive {
                score -= 45
            }
            let candIsRemaster = rName.contains("remaster") || rAlbum.contains("remaster")
            if expIsRemaster == candIsRemaster {
                score += 15
            } else {
                score -= 8
            }

            if score > 0, (best == nil || score > best!.score) {
                best = (prevURL, score)
            }
        }
        return best
    }

    private static func stripEditionSuffix(_ text: String) -> String {
        var result = text
        if let idx = result.firstIndex(of: "(") {
            result = String(result[..<idx])
        }
        if let idx = result.firstIndex(of: "[") {
            result = String(result[..<idx])
        }
        if let dashRange = result.range(of: " - ") {
            result = String(result[..<dashRange.lowerBound])
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchITunNormFromPreviewHeader(previewURL: URL) async -> Double? {
        let session = self.urlSession

        var request = URLRequest(url: previewURL)
        request.setValue("bytes=0-98303", forHTTPHeaderField: "Range")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (http.statusCode == 206 || http.statusCode == 200),
                  !data.isEmpty else {
                return nil
            }
            return Self.extractITunNormGainDb(from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Cache Helpers

    private static func makeCanonicalKey(artist: String, name: String) -> String {
        let a = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(a):\(n)"
    }

    private func lookupCachedGainLocked(canonicalKey: String, trackId: String = "", catalogId: String?) -> Double? {
        let cleanTrackId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTrackId.isEmpty, cleanTrackId != "0" {
            if let gain = memoryCache["id:\(cleanTrackId.lowercased())"] ?? memoryCache["id:\(cleanTrackId)"] {
                if !canonicalKey.isEmpty && memoryCache[canonicalKey] == nil {
                    memoryCache[canonicalKey] = gain
                }
                return gain
            }
        }
        if let cid = catalogId?.trimmingCharacters(in: .whitespacesAndNewlines), !cid.isEmpty, cid != "0" {
            if let gain = memoryCache["id:\(cid.lowercased())"] ?? memoryCache["id:\(cid)"] {
                if !canonicalKey.isEmpty && memoryCache[canonicalKey] == nil {
                    memoryCache[canonicalKey] = gain
                }
                return gain
            }
        }
        if let gain = memoryCache[canonicalKey] {
            if !cleanTrackId.isEmpty, cleanTrackId != "0", memoryCache["id:\(cleanTrackId.lowercased())"] == nil {
                memoryCache["id:\(cleanTrackId.lowercased())"] = gain
            }
            return gain
        }
        return nil
    }

    private func storeGainInCache(_ gainDb: Double, canonicalKey: String, trackId: String = "", catalogId: String?) {
        let cleanTrackId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.withLock {
            liveDspProvisionalKeys.remove(canonicalKey)
            memoryCache[canonicalKey] = gainDb
            if !cleanTrackId.isEmpty, cleanTrackId != "0" {
                memoryCache["id:\(cleanTrackId.lowercased())"] = gainDb
                memoryCache["id:\(cleanTrackId)"] = gainDb
            }
            if let cid = catalogId?.trimmingCharacters(in: .whitespacesAndNewlines), !cid.isEmpty, cid != "0" {
                memoryCache["id:\(cid.lowercased())"] = gainDb
                memoryCache["id:\(cid)"] = gainDb
            }
            saveCacheToDiskLocked()
        }
    }

    private func loadCacheFromDisk() {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let decoded = try? JSONDecoder().decode(CacheStore.self, from: data) else {
            return
        }
        lock.withLock {
            memoryCache = decoded.entries
        }
    }

    private func saveCacheToDiskLocked() {
        // Keep cache bounded to 5000 entries
        if memoryCache.count > 5000 {
            let keysToDrop = Array(memoryCache.keys.prefix(800))
            for k in keysToDrop {
                memoryCache.removeValue(forKey: k)
            }
        }
        let store = CacheStore(entries: memoryCache)
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: cacheFileURL, options: .atomic)
        }
    }
}
