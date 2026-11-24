//
//  SpectralIntegrityAnalyzer+CacheAndCloud.swift
//  AppleMusicRemoteMac
//
//  Spectral Validation Cache Persistence & Cross-Mac Cloud Sync Reconciliation
//

import Foundation

extension SpectralIntegrityAnalyzer {

    // MARK: - Spectral Validation Cache (Local & Cloud Tracks)

    internal static func makeFormatSuffix(sampleRate: Int, claimedBitDepth: Int, isLossless: Bool) -> String {
        let rate = max(44100, sampleRate)
        let depth = isLossless ? (claimedBitDepth >= 24 ? 24 : 16) : 16
        return "\(rate):\(depth):\(isLossless ? 1 : 0)"
    }

    internal static func makeIdCacheKey(
        trackId: String,
        isLocal: Bool,
        sampleRate: Int,
        claimedBitDepth: Int,
        isLossless: Bool
    ) -> String? {
        let cleanId = trackId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanId.isEmpty, cleanId != "0" else { return nil }
        let prefix = isLocal ? "local_id" : "cloud_id"
        let fmt = makeFormatSuffix(sampleRate: sampleRate, claimedBitDepth: claimedBitDepth, isLossless: isLossless)
        return "\(prefix):\(cleanId):\(fmt)"
    }

    internal static func makeMetadataCacheKey(
        trackKey: String,
        sampleRate: Int,
        claimedBitDepth: Int,
        isLossless: Bool
    ) -> String? {
        let cleanKey = trackKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanKey.isEmpty, cleanKey != ":" else { return nil }
        let fmt = makeFormatSuffix(sampleRate: sampleRate, claimedBitDepth: claimedBitDepth, isLossless: isLossless)
        return "track_key:\(cleanKey):\(fmt)"
    }

    internal func lookupCachedValidationLocked(
        trackId: String,
        trackKey: String,
        isLocal: Bool,
        sampleRate: Int,
        claimedBitDepth: Int,
        isLossless: Bool
    ) -> CachedSpectralValidation? {
        let idKey = Self.makeIdCacheKey(
            trackId: trackId,
            isLocal: isLocal,
            sampleRate: sampleRate,
            claimedBitDepth: claimedBitDepth,
            isLossless: isLossless
        )
        let metaKey = Self.makeMetadataCacheKey(
            trackKey: trackKey,
            sampleRate: sampleRate,
            claimedBitDepth: claimedBitDepth,
            isLossless: isLossless
        )

        if let idKey = idKey, let entry = validationCache[idKey], entry.isAuthentic {
            if let metaKey = metaKey, validationCache[metaKey] == nil {
                validationCache[metaKey] = entry
            }
            return entry
        }

        if let metaKey = metaKey, let entry = validationCache[metaKey], entry.isAuthentic {
            if let idKey = idKey, validationCache[idKey] == nil {
                var updated = entry
                if updated.trackId.isEmpty {
                    updated.trackId = trackId.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                validationCache[idKey] = updated
            }
            return entry
        }

        return nil
    }

    internal func storePassedValidationLocked(_ entry: CachedSpectralValidation, isLossless: Bool) {
        guard entry.isAuthentic else { return }

        var wroteNewKey = false
        if let idKey = Self.makeIdCacheKey(
            trackId: entry.trackId,
            isLocal: entry.isLocal,
            sampleRate: entry.sampleRate,
            claimedBitDepth: entry.claimedBitDepth,
            isLossless: isLossless
        ) {
            if validationCache[idKey] != entry {
                validationCache[idKey] = entry
                wroteNewKey = true
            }
        }

        if let metaKey = Self.makeMetadataCacheKey(
            trackKey: entry.trackKey,
            sampleRate: entry.sampleRate,
            claimedBitDepth: entry.claimedBitDepth,
            isLossless: isLossless
        ) {
            if validationCache[metaKey] != entry {
                validationCache[metaKey] = entry
                wroteNewKey = true
            }
        }

        pruneValidationCacheLocked()

        if wroteNewKey {
            let snapshot = validationCache
            let url = cacheFileURL
            persistenceQueue.async {
                if let encoded = try? JSONEncoder().encode(snapshot) {
                    try? encoded.write(to: url, options: .atomic)
                }
            }
            if self === Self.shared && !isTestingEnv {
                CloudSettingsSyncService.shared.schedulePush(reason: "track_dynamics")
            }
        }
    }

    internal func storeValidationForTesting(_ entry: CachedSpectralValidation, isLossless: Bool = true) {
        lock.lock()
        storePassedValidationLocked(entry, isLossless: isLossless)
        lock.unlock()
    }

    // MARK: - Cloud Sync Export & Merge (Mastering Dynamics & Loudness War Metrics)

    /// Returns `true` only for portable cross-Mac validation keys (`track_key:...` or `cloud_id:<catalogId>:...`),
    /// rejecting machine-local Music.app database keys (`local_id:...`).
    public static func isCloudSyncableValidationKey(_ key: String, entry: CachedSpectralValidation) -> Bool {
        guard entry.isAuthentic else { return false }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed.count <= 320 else { return false }
        if trimmed.hasPrefix("local_id:") {
            return false
        }
        if trimmed.hasPrefix("cloud_id:") {
            let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count >= 2 else { return false }
            let cid = String(parts[1])
            return AppleSoundCheckService.isValidCatalogId(cid)
        }
        if trimmed.hasPrefix("track_key:") {
            return !entry.trackKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && entry.trackKey != ":"
        }
        return false
    }

    public func exportCloudSyncValidations() -> [String: CachedSpectralValidation] {
        lock.lock()
        defer { lock.unlock() }
        var exported: [String: CachedSpectralValidation] = [:]
        exported.reserveCapacity(min(validationCache.count, 5000))
        for (key, entry) in validationCache where Self.isCloudSyncableValidationKey(key, entry: entry) {
            var portable = entry
            if portable.isLocal && !AppleSoundCheckService.isValidCatalogId(portable.trackId) {
                portable.trackId = ""
                portable.isLocal = false
            }
            exported[key.lowercased()] = portable
        }
        return exported
    }

    internal static func shouldCandidateReplaceExisting(
        candidate: CachedSpectralValidation,
        existing: CachedSpectralValidation
    ) -> Bool {
        guard candidate != existing else { return false }

        let candHasDR = (candidate.ttDrScore != nil)
        let existHasDR = (existing.ttDrScore != nil)
        if candHasDR != existHasDR {
            return candHasDR
        }
        let candHasLufs = (candidate.integratedLufs != nil)
        let existHasLufs = (existing.integratedLufs != nil)
        if candHasLufs != existHasLufs {
            return candHasLufs
        }

        let candTs = candidate.validatedAt.timeIntervalSince1970
        let existTs = existing.validatedAt.timeIntervalSince1970
        if candTs > existTs + 0.0001 {
            return true
        }
        if abs(candTs - existTs) <= 0.0001 {
            let candTuple = (
                candidate.ttDrScore ?? -1,
                candidate.dynamicRangeCrestDb,
                candidate.integratedLufs ?? -999.0,
                candidate.verdict
            )
            let existTuple = (
                existing.ttDrScore ?? -1,
                existing.dynamicRangeCrestDb,
                existing.integratedLufs ?? -999.0,
                existing.verdict
            )
            return candTuple > existTuple
        }
        return false
    }

    internal func pruneValidationCacheLocked() {
        guard validationCache.count > Self.maxCachedValidations else { return }
        let excess = validationCache.count - Self.maxCachedValidations
        let keysToDrop = validationCache
            .sorted { lhs, rhs in
                let lt = lhs.value.validatedAt.timeIntervalSince1970
                let rt = rhs.value.validatedAt.timeIntervalSince1970
                if abs(lt - rt) > 0.0001 {
                    return lt < rt
                }
                if lhs.value.trackKey != rhs.value.trackKey {
                    return lhs.value.trackKey < rhs.value.trackKey
                }
                return lhs.key < rhs.key
            }
            .prefix(excess)
            .map(\.key)
        for k in keysToDrop {
            validationCache.removeValue(forKey: k)
        }
    }

    @discardableResult
    public func mergeCloudSyncValidations(_ incoming: [String: CachedSpectralValidation]) -> Int {
        guard !incoming.isEmpty else { return 0 }
        var updatedCount = 0
        var snapshotToPersist: [String: CachedSpectralValidation]?
        let url = cacheFileURL

        lock.lock()
        let countBeforePrune = validationCache.count
        for (rawKey, rawEntry) in incoming where Self.isCloudSyncableValidationKey(rawKey, entry: rawEntry) {
            let cleanKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var candidate = rawEntry
            if candidate.isLocal && !AppleSoundCheckService.isValidCatalogId(candidate.trackId) {
                candidate.trackId = ""
                candidate.isLocal = false
            }
            if let existing = validationCache[cleanKey] {
                if Self.shouldCandidateReplaceExisting(candidate: candidate, existing: existing) {
                    validationCache[cleanKey] = candidate
                    updatedCount += 1
                }
            } else {
                validationCache[cleanKey] = candidate
                updatedCount += 1
            }
        }

        pruneValidationCacheLocked()
        if countBeforePrune > Self.maxCachedValidations && validationCache.count == Self.maxCachedValidations {
            updatedCount = max(1, updatedCount)
        }

        if updatedCount > 0 {
            self.activeCachedValidation = lookupCachedValidationLocked(
                trackId: self.currentTrackId,
                trackKey: self.currentTrackKey,
                isLocal: self.currentIsLocal,
                sampleRate: self.currentSampleRate,
                claimedBitDepth: self.claimedBitDepth,
                isLossless: self.isClaimedLossless
            )
            recomputeResultLocked()
            snapshotToPersist = validationCache
        }
        lock.unlock()

        if let snapshot = snapshotToPersist {
            persistenceQueue.async {
                if let encoded = try? JSONEncoder().encode(snapshot) {
                    try? encoded.write(to: url, options: .atomic)
                }
            }
        }
        return updatedCount
    }

    public func getCachedValidation(
        trackId: String = "",
        trackKey: String = "",
        isLocal: Bool = false,
        sampleRate: Int,
        claimedBitDepth: Int,
        isLossless: Bool
    ) -> CachedSpectralValidation? {
        let validRate = max(44100, sampleRate)
        let validDepth = isLossless ? (claimedBitDepth >= 24 ? 24 : 16) : 16
        lock.lock()
        defer { lock.unlock() }
        return lookupCachedValidationLocked(
            trackId: trackId,
            trackKey: trackKey,
            isLocal: isLocal,
            sampleRate: validRate,
            claimedBitDepth: validDepth,
            isLossless: isLossless
        )
    }

    public var isCurrentTrackValidationCached: Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeCachedValidation != nil
    }

    public var cachedValidationEntriesCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return validationCache.count
    }

    public func clearValidationCache() {
        lock.lock()
        validationCache.removeAll()
        activeCachedValidation = nil
        recomputeResultLocked()
        let url = cacheFileURL
        lock.unlock()
        persistenceQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
