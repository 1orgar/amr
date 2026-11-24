//
//  AppleSoundCheckService+ResolutionAndCloud.swift
//  AppleMusicRemoteMac
//
//  Multi-Tier Local/Catalog iTunNORM & Acoustic Loudness Resolution,
//  Cross-Mac Cloud Sync Export/Merge & Lock-Free Background Disk Persistence
//

import Foundation
import AVFoundation
import Accelerate

extension AppleSoundCheckService {

    // MARK: - Multi-Tier Resolution

    internal func resolveGainDb(
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
        if isLocal && !hasCloudCatalogId, !AppleScriptExecutor.shared.isBusy {
            let localGain: Double? = await withCheckedContinuation { continuation in
                localScanQueue.async { [weak self] in
                    continuation.resume(returning: self?.readLocalCurrentTrackITunNorm(expectedName: name))
                }
            }
            if let localGain {
                storeGainInCache(localGain, canonicalKey: canonicalKey, trackId: trackId, catalogId: catalogId)
                NSLog("[AppleSoundCheck] Local track loudness for '%@ - %@': %+.2f dB", artist, name, localGain)
                return localGain
            }
        }

        // Tier 2: Resolve previewUrl via Apple Music / iTunes Lookup or Search API and read first 96 KB of .m4a
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

    internal func readLocalCurrentTrackITunNorm(expectedName: String) -> Double? {
        guard !AppleScriptExecutor.shared.isBusy else { return nil }
        let script = """
        tell application "Music"
            if player state is not stopped then
                try
                    with timeout of 1.2 seconds
                        set trName to name of current track
                        set loc to location of current track
                        if loc is not missing value then
                            return trName & "|||" & (POSIX path of loc)
                        end if
                    end timeout
                end try
            end if
        end tell
        return ""
        """
        let (ok, rawOut) = AppleScriptExecutor.shared.execute(script, maxWait: 1.3, reportTimeout: false)
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

    internal func fetchApplePreviewURL(
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

    internal func queryPreviewURLFromEndpoint(
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

    internal static func stripEditionSuffix(_ text: String) -> String {
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

    internal func fetchITunNormFromPreviewHeader(previewURL: URL) async -> Double? {
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

    internal static func makeCanonicalKey(artist: String, name: String) -> String {
        let a = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(a):\(n)"
    }

    internal func lookupCachedGainLocked(canonicalKey: String, trackId: String = "", catalogId: String?) -> Double? {
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

    internal func storeGainInCache(_ gainDb: Double, canonicalKey: String, trackId: String = "", catalogId: String?) {
        let cleanTrackId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot: [String: Double] = lock.withLock {
            removeProvisionalKeyLocked(canonicalKey)
            memoryCache[canonicalKey] = gainDb
            if !cleanTrackId.isEmpty, cleanTrackId != "0" {
                memoryCache["id:\(cleanTrackId.lowercased())"] = gainDb
                memoryCache["id:\(cleanTrackId)"] = gainDb
            }
            if let cid = catalogId?.trimmingCharacters(in: .whitespacesAndNewlines), !cid.isEmpty, cid != "0" {
                memoryCache["id:\(cid.lowercased())"] = gainDb
                memoryCache["id:\(cid)"] = gainDb
            }
            return memoryCache
        }
        scheduleSaveCacheToDisk(snapshot)
        if self === Self.shared && !PlaybackRouter.shared.isTestingEnvironment {
            CloudSettingsSyncService.shared.schedulePush(reason: "track_loudness")
        }
    }

    // MARK: - Cloud Sync Export & Merge

    /// Checks whether a cache key represents a portable cross-Mac track identifier
    /// (canonical `artist:title` or an Apple Music catalog ID `id:<>=5_000_000>`),
    /// rejecting machine-local Music.app database IDs (`id:4135`).
    public static func isCloudSyncableCacheKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 260 else { return false }
        if trimmed.lowercased().hasPrefix("id:") {
            let suffix = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            return isValidCatalogId(suffix)
        }
        guard let colonIdx = trimmed.firstIndex(of: ":") else { return false }
        let artistPart = trimmed[..<colonIdx].trimmingCharacters(in: .whitespacesAndNewlines)
        let titlePart = trimmed[trimmed.index(after: colonIdx)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return !artistPart.isEmpty && !titlePart.isEmpty
    }

    public func exportCloudSyncLoudnessEntries() -> [String: Double] {
        lock.withLock {
            var exported: [String: Double] = [:]
            exported.reserveCapacity(min(memoryCache.count, Self.maxCacheEntries))
            for (rawKey, val) in memoryCache {
                guard val.isFinite, abs(val) <= 24.0 else { continue }
                guard !liveDspProvisionalKeys.contains(rawKey) else { continue }
                guard Self.isCloudSyncableCacheKey(rawKey) else { continue }
                let normalizedKey = rawKey.lowercased().hasPrefix("id:")
                    ? "id:\(rawKey.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
                    : rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let rounded = (min(max(val, -18.0), 12.0) * 100.0).rounded() / 100.0
                exported[normalizedKey] = rounded
            }
            return exported
        }
    }

    @discardableResult
    public func mergeCloudSyncLoudnessEntries(_ incoming: [String: Double]) -> Int {
        guard !incoming.isEmpty else { return 0 }
        let (updatedCount, snapshotToSave): (Int, [String: Double]?) = lock.withLock {
            var updated = 0
            for (rawKey, rawVal) in incoming {
                guard rawVal.isFinite, abs(rawVal) <= 24.0 else { continue }
                guard Self.isCloudSyncableCacheKey(rawKey) else { continue }
                let normalizedKey = rawKey.lowercased().hasPrefix("id:")
                    ? "id:\(rawKey.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
                    : rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let clamped = (min(max(rawVal, -18.0), 12.0) * 100.0).rounded() / 100.0
                if let existing = memoryCache[normalizedKey], !liveDspProvisionalKeys.contains(normalizedKey) {
                    let existingRounded = (min(max(existing, -18.0), 12.0) * 100.0).rounded() / 100.0
                    let canonical = (min(existingRounded, clamped) * 100.0).rounded() / 100.0
                    if abs(existing - canonical) > 1e-6 {
                        memoryCache[normalizedKey] = canonical
                        updated += 1
                    }
                } else {
                    removeProvisionalKeyLocked(normalizedKey)
                    memoryCache[normalizedKey] = clamped
                    updated += 1
                }
            }
            return (updated, updated > 0 ? memoryCache : nil)
        }
        if let snap = snapshotToSave {
            scheduleSaveCacheToDisk(snap)
        }
        return updatedCount
    }

    internal func loadCacheFromDisk() {
        guard let data = try? Data(contentsOf: cacheFileURL),
              let decoded = try? JSONDecoder().decode(CacheStore.self, from: data) else {
            return
        }
        lock.withLock {
            memoryCache = decoded.entries
        }
    }

    /// Serializes and writes the SoundCheck cache strictly outside `lock` on `persistenceQueue`
    /// so 5,000-key sorting, JSON encoding, and atomic disk writes never contend with track lookup or DSP loudness callbacks.
    internal func scheduleSaveCacheToDisk(_ rawSnapshot: [String: Double]) {
        let url = self.cacheFileURL
        let work: () -> Void = { [weak self] in
            var entries = rawSnapshot
            var droppedKeys: [String] = []
            if entries.count > Self.maxCacheEntries {
                let excess = entries.count - Self.maxCacheEntries
                droppedKeys = Array(entries.keys.sorted().prefix(excess))
                for k in droppedKeys {
                    entries.removeValue(forKey: k)
                }
            }
            let store = CacheStore(entries: entries)
            if let data = try? JSONEncoder().encode(store) {
                try? data.write(to: url, options: .atomic)
            }
            if !droppedKeys.isEmpty, let self = self {
                self.lock.withLock {
                    if self.memoryCache.count > Self.maxCacheEntries {
                        for k in droppedKeys where self.memoryCache.count > Self.maxCacheEntries {
                            self.memoryCache.removeValue(forKey: k)
                            self.removeProvisionalKeyLocked(k)
                        }
                    }
                }
            }
        }
        if usesCustomCacheFileForTesting {
            persistenceQueue.sync(execute: work)
        } else {
            persistenceQueue.async(execute: work)
        }
    }
}
