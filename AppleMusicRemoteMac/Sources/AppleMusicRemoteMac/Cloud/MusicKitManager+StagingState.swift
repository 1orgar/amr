//
//  MusicKitManager+StagingState.swift
//  AppleMusicRemoteMac
//
//  Cloud song staging deduplication, unstageable/preferred-alternate catalog tracking,
//  temporary staging playlist cleanup, and `/v1/me/library` song staging POSTs.
//

import AppKit
import Foundation

extension MusicKitManager {

    // MARK: - Fast Cloud Song Library Staging State

    internal static let stageDedupLock = NSLock()
    internal static var recentlyStagedCatalogIds: [String: Date] = [:]
    internal static var lastCloudMenuNudgeAt: Date = .distantPast
    internal static var lastCloudStagePostAt: Date = .distantPast
    internal static let unstageableLock = NSLock()
    internal static var unstageableCatalogIds: [String: Date] = [:]
    internal static var preferredAlternateCatalogSongs: [String: (id: String, name: String, artist: String, recordedAt: Date)] = [:]
    internal static let stagingPlaylistOpsLock = NSLock()
    internal static let stagePollLock = NSLock()

    public static func clearRecentlyStagedCatalogIds() {
        stageDedupLock.withLock {
            recentlyStagedCatalogIds.removeAll()
        }
    }

    public static func extractNumericCatalogId(from track: TrackInfo) -> String? {
        if let cat = track.catalogId?.trimmingCharacters(in: .whitespacesAndNewlines),
           let num = Int(cat), num >= 1_000_000 {
            return cat
        }
        let rawId = track.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if let num = Int(rawId), num >= 1_000_000 {
            return rawId
        }
        if let u = track.url, let comp = URLComponents(string: u),
           let qi = comp.queryItems?.first(where: { $0.name == "i" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
           let num = Int(qi), num >= 1_000_000 {
            return qi
        }
        return nil
    }

    public func isUnstageableCatalogId(_ catalogId: String) -> Bool {
        let clean = catalogId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        return Self.unstageableLock.withLock {
            guard let ts = Self.unstageableCatalogIds[clean] else { return false }
            if Date().timeIntervalSince(ts) > 1800.0 {
                Self.unstageableCatalogIds.removeValue(forKey: clean)
                return false
            }
            return true
        }
    }

    internal func markUnstageableCatalogId(_ catalogId: String) {
        let clean = catalogId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        Self.unstageableLock.withLock {
            let now = Date()
            if Self.unstageableCatalogIds.count >= 1000 {
                Self.unstageableCatalogIds = Self.unstageableCatalogIds.filter { now.timeIntervalSince($0.value) <= 1800.0 }
                if Self.unstageableCatalogIds.count >= 1000,
                   let oldestKey = Self.unstageableCatalogIds.min(by: { $0.value < $1.value })?.key {
                    Self.unstageableCatalogIds.removeValue(forKey: oldestKey)
                }
            }
            Self.unstageableCatalogIds[clean] = now
        }
        _ = Self.stageDedupLock.withLock {
            Self.recentlyStagedCatalogIds.removeValue(forKey: clean)
        }
    }

    internal func unmarkUnstageableCatalogId(_ catalogId: String) {
        let clean = catalogId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        _ = Self.unstageableLock.withLock {
            Self.unstageableCatalogIds.removeValue(forKey: clean)
        }
    }

    private static let preferredAlternateCatalogStorageKey = "amr_preferred_alternate_catalog_songs_v1"
    private static let preferredAlternateCatalogTTL: TimeInterval = 604_800.0 // 7 days
    private static var didLoadPreferredAlternatesFromDisk = false

    internal static func loadPreferredAlternatesLockedIfNeeded() {
        guard !didLoadPreferredAlternatesFromDisk else { return }
        didLoadPreferredAlternatesFromDisk = true
        guard !PlaybackRouter.shared.isTestingEnvironment,
              let rawDict = storageDefaults.dictionary(forKey: preferredAlternateCatalogStorageKey) as? [String: [String: Any]] else {
            return
        }
        let now = Date()
        for (orig, entry) in rawDict {
            guard let id = entry["id"] as? String, isValidResourceIdentifier(id),
                  let ts = entry["ts"] as? TimeInterval else { continue }
            let recDate = Date(timeIntervalSince1970: ts)
            guard now.timeIntervalSince(recDate) <= preferredAlternateCatalogTTL else { continue }
            let name = (entry["name"] as? String) ?? ""
            let artist = (entry["artist"] as? String) ?? ""
            if preferredAlternateCatalogSongs.count < 300 {
                preferredAlternateCatalogSongs[orig] = (id: id, name: name, artist: artist, recordedAt: recDate)
            }
        }
    }

    internal static func savePreferredAlternatesLocked() {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return }
        let now = Date()
        var out: [String: [String: Any]] = [:]
        for (orig, entry) in preferredAlternateCatalogSongs where now.timeIntervalSince(entry.recordedAt) <= preferredAlternateCatalogTTL {
            out[orig] = [
                "id": entry.id,
                "name": entry.name,
                "artist": entry.artist,
                "ts": entry.recordedAt.timeIntervalSince1970
            ]
        }
        storageDefaults.set(out, forKey: preferredAlternateCatalogStorageKey)
    }

    internal func clearUnstageableCatalogIdsForTesting() {
        Self.unstageableLock.withLock {
            Self.unstageableCatalogIds.removeAll()
            Self.preferredAlternateCatalogSongs.removeAll()
            Self.didLoadPreferredAlternatesFromDisk = true
        }
        Self.stageDedupLock.withLock {
            Self.recentlyStagedCatalogIds.removeAll()
        }
    }

    public func preferredAlternateCatalogSong(for catalogId: String?) -> (id: String, name: String, artist: String)? {
        guard let raw = catalogId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return Self.unstageableLock.withLock {
            Self.loadPreferredAlternatesLockedIfNeeded()
            guard let entry = Self.preferredAlternateCatalogSongs[raw] else { return nil }
            if Date().timeIntervalSince(entry.recordedAt) > Self.preferredAlternateCatalogTTL {
                Self.preferredAlternateCatalogSongs.removeValue(forKey: raw)
                Self.savePreferredAlternatesLocked()
                return nil
            }
            if let ts = Self.unstageableCatalogIds[entry.id], Date().timeIntervalSince(ts) <= 1800.0 {
                Self.preferredAlternateCatalogSongs.removeValue(forKey: raw)
                Self.savePreferredAlternatesLocked()
                return nil
            }
            if PlaybackRouter.hasDirectSeedMismatch(catalogId: entry.id) {
                Self.preferredAlternateCatalogSongs.removeValue(forKey: raw)
                Self.savePreferredAlternatesLocked()
                return nil
            }
            return (id: entry.id, name: entry.name, artist: entry.artist)
        }
    }

    internal func recordPreferredAlternateCatalogSong(
        for originalCatalogId: String,
        alternate: (id: String, name: String, artist: String)
    ) {
        let orig = originalCatalogId.trimmingCharacters(in: .whitespacesAndNewlines)
        let altId = alternate.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidResourceIdentifier(orig),
              Self.isValidResourceIdentifier(altId),
              orig != altId else { return }
        Self.unstageableLock.withLock {
            Self.loadPreferredAlternatesLockedIfNeeded()
            if Self.preferredAlternateCatalogSongs.count >= 300,
               let oldestKey = Self.preferredAlternateCatalogSongs.min(by: { $0.value.recordedAt < $1.value.recordedAt })?.key {
                Self.preferredAlternateCatalogSongs.removeValue(forKey: oldestKey)
            }
            Self.preferredAlternateCatalogSongs[orig] = (
                id: altId,
                name: alternate.name,
                artist: alternate.artist,
                recordedAt: Date()
            )
            Self.savePreferredAlternatesLocked()
        }
        appendCachedTitleVariant(catalogId: orig, name: alternate.name, artist: alternate.artist)
    }

    internal static func recordConfirmedStagedCatalogIds(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let now = Date()
        stageDedupLock.withLock {
            recentlyStagedCatalogIds = recentlyStagedCatalogIds.filter { now.timeIntervalSince($0.value) < 90.0 }
            for cid in ids {
                if recentlyStagedCatalogIds.count >= 1000,
                   let oldest = recentlyStagedCatalogIds.min(by: { $0.value < $1.value })?.key {
                    recentlyStagedCatalogIds.removeValue(forKey: oldest)
                }
                recentlyStagedCatalogIds[cid] = now
            }
        }
    }

    internal func persistReusableStagingPlaylistId(_ playlistId: String?) {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return }
        let clean = (playlistId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        withLock {
            if clean.isEmpty {
                Self.storageDefaults.removeObject(forKey: Self.reusableStagingCloudPlaylistIdKey)
            } else {
                Self.storageDefaults.set(clean, forKey: Self.reusableStagingCloudPlaylistIdKey)
            }
            Self.storageDefaults.set(clean.isEmpty ? [] : [clean], forKey: Self.stagingCloudPlaylistIdsKey)
        }
    }

    internal func removePersistedStagingPlaylistId(_ playlistId: String) {
        let clean = playlistId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !PlaybackRouter.shared.isTestingEnvironment else { return }
        withLock {
            var current = Set(Self.storageDefaults.stringArray(forKey: Self.stagingCloudPlaylistIdsKey) ?? [])
            if current.remove(clean) != nil {
                Self.storageDefaults.set(Array(current), forKey: Self.stagingCloudPlaylistIdsKey)
            }
            if Self.storageDefaults.string(forKey: Self.reusableStagingCloudPlaylistIdKey) == clean {
                Self.storageDefaults.removeObject(forKey: Self.reusableStagingCloudPlaylistIdKey)
            }
        }
    }

    internal func configureReusableStagingStateForTesting(
        reusableId: String?,
        trackCount: Int,
        legacyTempQueueId: String? = nil
    ) {
        withLock {
            activeStagingCloudPlaylistId = reusableId
            activeStagingCloudPlaylistTrackCount = trackCount
            lastTemporaryCloudPlaylistId = legacyTempQueueId
        }
    }

    internal func reusableStagingStateSnapshot() -> (reusableId: String?, trackCount: Int, legacyTempQueueId: String?) {
        withLock {
            (activeStagingCloudPlaylistId, activeStagingCloudPlaylistTrackCount, lastTemporaryCloudPlaylistId)
        }
    }

    internal func discoverExistingCloudTemporaryPlaylistIdsSync(includeQueuePlaylist: Bool, timeout: TimeInterval = 2.8) -> [String] {
        guard !PlaybackRouter.shared.isTestingEnvironment,
              let devToken = getDeveloperToken(),
              let uToken = getUserToken(), !uToken.isEmpty,
              let url = Self.makeAppleMusicAPIURL(
                  path: "/v1/me/library/playlists",
                  queryItems: [URLQueryItem(name: "limit", value: "100")]
              ) else {
            return []
        }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let sema = DispatchSemaphore(value: 0)
        let boxLock = NSLock()
        var matchedIds: [String] = []
        let task = session.dataTask(with: req) { data, resp, _ in
            defer { sema.signal() }
            guard let d = data,
                  let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let arr = json["data"] as? [[String: Any]] else { return }
            var found: [String] = []
            for item in arr {
                guard let pid = item["id"] as? String, Self.isValidResourceIdentifier(pid),
                      let attrs = item["attributes"] as? [String: Any],
                      let pName = attrs["name"] as? String else { continue }
                let isLegacyBuffer = pName.caseInsensitiveCompare(Self.stagingPlaylistName) == .orderedSame
                let isLegacyQueue = includeQueuePlaylist && pName.caseInsensitiveCompare("Очередь AMR") == .orderedSame
                if isLegacyBuffer || isLegacyQueue {
                    found.append(pid)
                }
            }
            if !found.isEmpty {
                boxLock.lock()
                matchedIds = found
                boxLock.unlock()
            }
        }
        task.resume()
        if sema.wait(timeout: .now() + timeout + 0.2) == .timedOut {
            task.cancel()
        }
        boxLock.lock()
        defer { boxLock.unlock() }
        return matchedIds
    }

    internal func deleteCloudPlaylistSync(playlistId: String, timeout: TimeInterval = 3.0) -> Bool {
        let clean = playlistId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidResourceIdentifier(clean),
              let devToken = getDeveloperToken(),
              let uToken = getUserToken(), !uToken.isEmpty,
              let url = Self.makeAppleMusicAPIURL(path: "/v1/me/library/playlists/\(clean)") else {
            return false
        }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")

        let sema = DispatchSemaphore(value: 0)
        let boxLock = NSLock()
        var confirmedGone = false
        let task = session.dataTask(with: req) { _, resp, _ in
            if let http = resp as? HTTPURLResponse,
               (http.statusCode == 200 || http.statusCode == 204 || http.statusCode == 404) {
                boxLock.lock()
                confirmedGone = true
                boxLock.unlock()
            }
            sema.signal()
        }
        task.resume()
        if sema.wait(timeout: .now() + timeout + 0.2) == .timedOut {
            task.cancel()
        }
        boxLock.lock()
        let ok = confirmedGone
        boxLock.unlock()
        if ok {
            removePersistedStagingPlaylistId(clean)
        }
        return ok
    }

    /// Purges all legacy temporary playback playlists from memory, `Music.app`, and Apple Music Cloud Library.
    public func cleanupTemporaryPlaybackPlaylists(keepingActiveQueue: Bool = false, synchronous: Bool = false) {
        if !keepingActiveQueue {
            let isIdle = PlaybackStateStore.shared.withLock {
                !PlaybackStateStore.shared.isCustomQueuePlayback
                    && !PlaybackStateStore.shared.isStagingCloudTrack
                    && PlaybackStateStore.shared.stagedTemporaryTrackDbIds.isEmpty
            }
            if isIdle || synchronous {
                LibraryService.shared.clearStagedBufferCache()
                Self.stageDedupLock.withLock {
                    Self.recentlyStagedCatalogIds.removeAll()
                }
            }
        }

        let (reusableStageId, tempQueueId, persistedIds): (String?, String?, [String]) = withLock {
            let sId = activeStagingCloudPlaylistId
            let qId = lastTemporaryCloudPlaylistId
            activeStagingCloudPlaylistId = nil
            activeStagingCloudPlaylistTrackCount = 0
            if !keepingActiveQueue {
                lastTemporaryCloudPlaylistId = nil
            }
            if PlaybackRouter.shared.isTestingEnvironment {
                return (sId, qId, [])
            }
            var stored = Set(Self.storageDefaults.stringArray(forKey: Self.stagingCloudPlaylistIdsKey) ?? [])
            if let r1 = Self.storageDefaults.string(forKey: Self.reusableStagingCloudPlaylistIdKey), !r1.isEmpty {
                stored.insert(r1)
            }
            if let r2 = UserDefaults.standard.string(forKey: Self.reusableStagingCloudPlaylistIdKey), !r2.isEmpty {
                stored.insert(r2)
            }
            for item in (UserDefaults.standard.stringArray(forKey: Self.stagingCloudPlaylistIdsKey) ?? []) where !item.isEmpty {
                stored.insert(item)
            }
            Self.storageDefaults.removeObject(forKey: Self.reusableStagingCloudPlaylistIdKey)
            Self.storageDefaults.removeObject(forKey: Self.stagingCloudPlaylistIdsKey)
            UserDefaults.standard.removeObject(forKey: Self.reusableStagingCloudPlaylistIdKey)
            UserDefaults.standard.removeObject(forKey: Self.stagingCloudPlaylistIdsKey)
            return (sId, qId, Array(stored))
        }

        if PlaybackRouter.shared.isTestingEnvironment {
            return
        }

        var cloudIdsToDelete = Set<String>()
        if let sId = reusableStageId, Self.isValidResourceIdentifier(sId) {
            cloudIdsToDelete.insert(sId)
        }
        if !keepingActiveQueue, let qId = tempQueueId, Self.isValidResourceIdentifier(qId) {
            cloudIdsToDelete.insert(qId)
        }
        for pid in persistedIds where Self.isValidResourceIdentifier(pid) {
            cloudIdsToDelete.insert(pid)
        }
        let knownIdsSnapshot = cloudIdsToDelete
        let allowQueueDelete = !keepingActiveQueue

        let workBlock: @Sendable () -> Void = { [weak self] in
            guard let self = self else { return }
            Self.stagingPlaylistOpsLock.withLock {
                let activeNow: (isCustomOrStaging: Bool, currentPlId: String?) = {
                    let isAct = PlaybackStateStore.shared.withLock {
                        PlaybackStateStore.shared.isCustomQueuePlayback || PlaybackStateStore.shared.isStagingCloudTrack
                    }
                    let curId = self.withLock { self.activeStagingCloudPlaylistId ?? self.lastTemporaryCloudPlaylistId }
                    return (isAct, curId)
                }()
                let shouldDeleteQueuePlInMusic = allowQueueDelete && (synchronous || !activeNow.isCustomOrStaging)
                if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty {
                    let deleteQueueClause = shouldDeleteQueuePlInMusic ? """
                                    if (not isActivelyPlaying) or (curPlName is not "Очередь AMR") then
                                        repeat with qp in (get every user playlist whose name is "Очередь AMR")
                                            try
                                                delete qp
                                            end try
                                        end repeat
                                    end if
                    """ : ""
                    _ = AppleScriptExecutor.shared.execute("""
                    tell application "Music"
                        try
                            with timeout of 2.5 seconds
                                set curPlName to ""
                                set isActivelyPlaying to false
                                try
                                    if player state is playing then set isActivelyPlaying to true
                                    if player state is not stopped and (exists current playlist) then
                                        set curPlName to (name of current playlist as string)
                                    end if
                                end try
                    \(deleteQueueClause)
                                repeat with bp in (get every user playlist whose name is "\(Self.stagingPlaylistName)")
                                    try
                                        delete bp
                                    end try
                                end repeat
                            end timeout
                        end try
                    end tell
                    """, maxWait: 2.9, reportTimeout: false)
                }

                var finalCloudIds = knownIdsSnapshot
                if shouldDeleteQueuePlInMusic {
                    let discovered = self.discoverExistingCloudTemporaryPlaylistIdsSync(
                        includeQueuePlaylist: true,
                        timeout: synchronous ? 1.2 : 2.8
                    )
                    for did in discovered where Self.isValidResourceIdentifier(did) {
                        finalCloudIds.insert(did)
                    }
                }
                if !synchronous, let liveId = activeNow.currentPlId, !liveId.isEmpty {
                    finalCloudIds.remove(liveId)
                }
                if !finalCloudIds.isEmpty {
                    let timeoutPerCall: TimeInterval = synchronous ? 0.9 : 3.0
                    for cid in finalCloudIds {
                        _ = self.deleteCloudPlaylistSync(playlistId: cid, timeout: timeoutPerCall)
                    }
                }
            }
        }

        if synchronous {
            workBlock()
        } else {
            DispatchQueue.global(qos: .utility).async(execute: workBlock)
        }
    }
}
