//
//  PlaybackStateStore+StagedTracks.swift
//  AppleMusicRemoteMac
//
//  Crash-proof pre-journaling, promotion, and deferred cleanup for staged temporary cloud tracks.
//

import AppKit
import Foundation

extension PlaybackStateStore {

    public func stagedAlbumCandidatesSnapshot() -> [(album: String, artist: String)] {
        lock.lock()
        defer { lock.unlock() }
        var result: [(album: String, artist: String)] = []
        var seen = Set<String>()
        func addPair(album: String, artist: String) {
            let cleanAlb = album.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanAlb.isEmpty else { return }
            let cleanArt = artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = "\(cleanAlb.lowercased())|\(cleanArt.lowercased())"
            if seen.insert(key).inserted {
                result.append((album: cleanAlb, artist: cleanArt))
            }
        }
        for sid in stagedTemporaryTrackDbIds {
            if let meta = trackMetadataCache[sid] {
                addPair(album: meta.album, artist: meta.artist)
                addPair(album: meta.name, artist: meta.artist)
            }
        }
        for p in pendingStagedCatalogTracks {
            addPair(album: p.album, artist: p.artist)
            addPair(album: p.name, artist: p.artist)
        }
        let now = Date().timeIntervalSince1970
        for h in recentlyStagedAlbumHistory where now - h.stagedAt <= 3600.0 {
            addPair(album: h.album, artist: h.artist)
            addPair(album: h.trackName, artist: h.artist)
        }
        let pendingIds = Set(pendingStagedCatalogTracks.map { $0.catalogId })
        for qt in activeCustomQueue {
            let nid = qt.numericId ?? 0
            let cid = qt.catalogId ?? qt.id
            if (nid > 0 && stagedTemporaryTrackDbIds.contains(nid)) || pendingIds.contains(cid) {
                addPair(album: qt.album, artist: qt.artist)
                addPair(album: qt.name, artist: qt.artist)
            }
        }
        return result
    }

    public func registerStagedTemporaryTrack(dbId: Int) {
        guard dbId > 0 else { return }
        lock.lock()
        stagedTemporaryTrackDbIds.insert(dbId)
        if !PlaybackRouter.shared.isTestingEnvironment {
            sessionStagedTimestamps[dbId] = Date()
        }
        let snapshot = Array(stagedTemporaryTrackDbIds)
        lock.unlock()
        UserDefaults.standard.set(snapshot, forKey: Self.stagedDbIdsStorageKey)
    }

    public func unregisterStagedTemporaryTrack(dbId: Int) {
        guard dbId > 0 else { return }
        lock.lock()
        sessionStagedTimestamps.removeValue(forKey: dbId)
        let removed = stagedTemporaryTrackDbIds.remove(dbId) != nil
        let snapshot = removed ? Array(stagedTemporaryTrackDbIds) : nil
        lock.unlock()
        if let snap = snapshot {
            UserDefaults.standard.set(snap, forKey: Self.stagedDbIdsStorageKey)
        }
    }

    static func normalizedSavedTrackKey(name: String, artist: String) -> String {
        let n = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let a = artist.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(n)|\(a)"
    }

    func persistPendingStagedTracksIfAllowed(_ snapshot: [PendingStagedCatalogTrack]) {
        guard !PlaybackRouter.shared.isTestingEnvironment && !Self.isRunningUnderXCTest else { return }
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.pendingStagedStorageKey)
        }
    }

    public func recordPendingStagedCatalogTrack(catalogId: String, name: String, artist: String, album: String = "") {
        let cleanId = catalogId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty || !cleanName.isEmpty else { return }

        let targetKey = cleanName.isEmpty ? "" : Self.normalizedSavedTrackKey(name: cleanName, artist: cleanArtist)
        let now = Date().timeIntervalSince1970

        lock.lock()
        var preservedName = cleanName
        var preservedArtist = cleanArtist
        var preservedAlbum = cleanAlbum
        pendingStagedCatalogTracks.removeAll { item in
            let sameId = !cleanId.isEmpty && !item.catalogId.isEmpty && item.catalogId == cleanId
            let sameKey = !targetKey.isEmpty && !item.name.isEmpty
                && Self.normalizedSavedTrackKey(name: item.name, artist: item.artist) == targetKey
            if sameId || sameKey {
                if preservedName.isEmpty && !item.name.isEmpty { preservedName = item.name }
                if preservedArtist.isEmpty && !item.artist.isEmpty { preservedArtist = item.artist }
                if preservedAlbum.isEmpty && !item.album.isEmpty { preservedAlbum = item.album }
                return true
            }
            return now - item.stagedAt > 7.0 * 86_400.0
        }
        pendingStagedCatalogTracks.append(PendingStagedCatalogTrack(
            catalogId: cleanId,
            name: preservedName,
            artist: preservedArtist,
            album: preservedAlbum,
            stagedAt: now
        ))
        recordStagedAlbumHistoryLocked(album: preservedAlbum, trackName: preservedName, artist: preservedArtist)
        if pendingStagedCatalogTracks.count > 200 {
            pendingStagedCatalogTracks = Array(pendingStagedCatalogTracks.suffix(200))
        }
        let snapshot = pendingStagedCatalogTracks
        lock.unlock()

        persistPendingStagedTracksIfAllowed(snapshot)
    }

    public func clearPendingStagedCatalogTrack(catalogId: String?, name: String = "", artist: String = "") {
        let cleanId = catalogId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty || !cleanName.isEmpty else { return }

        let targetKey = cleanName.isEmpty ? "" : Self.normalizedSavedTrackKey(name: cleanName, artist: cleanArtist)
        let normName = cleanName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        var updatedSnapshot: [PendingStagedCatalogTrack]? = nil
        lock.lock()
        let before = pendingStagedCatalogTracks.count
        pendingStagedCatalogTracks.removeAll { item in
            if !cleanId.isEmpty && !item.catalogId.isEmpty && item.catalogId == cleanId {
                return true
            }
            if !targetKey.isEmpty && !item.name.isEmpty {
                if Self.normalizedSavedTrackKey(name: item.name, artist: item.artist) == targetKey {
                    return true
                }
                if cleanArtist.isEmpty || item.artist.isEmpty {
                    let iName = item.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if iName == normName {
                        return true
                    }
                }
            }
            return false
        }
        if pendingStagedCatalogTracks.count != before {
            updatedSnapshot = pendingStagedCatalogTracks
        }
        lock.unlock()

        if let snap = updatedSnapshot {
            persistPendingStagedTracksIfAllowed(snap)
        }
    }

    public func pendingStagedCatalogTracksSnapshot() -> [PendingStagedCatalogTrack] {
        lock.lock()
        defer { lock.unlock() }
        return pendingStagedCatalogTracks
    }

    public func promoteStagedTrackForSavedSong(dbId: Int?, catalogId: String?, name: String?, artist: String?) {
        let cleanCatalogId = catalogId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanArtist = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normName = cleanName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let normArtist = cleanArtist.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        var snapshotToSave: [Int]? = nil
        var pendingSnapshotToSave: [PendingStagedCatalogTrack]? = nil
        lock.lock()
        if !cleanCatalogId.isEmpty {
            permanentlySavedTrackKeys.insert("id:\(cleanCatalogId)")
        }
        if !cleanName.isEmpty {
            permanentlySavedTrackKeys.insert(Self.normalizedSavedTrackKey(name: cleanName, artist: cleanArtist))
            recentlyStagedAlbumHistory.removeAll { item in
                MusicKitManager.albumMatches(item.trackName, item.artist, cleanName, cleanArtist)
                    || MusicKitManager.albumMatches(item.album, item.artist, cleanName, cleanArtist)
            }
        }

        if !pendingStagedCatalogTracks.isEmpty {
            let beforePending = pendingStagedCatalogTracks.count
            pendingStagedCatalogTracks.removeAll { item in
                if !cleanCatalogId.isEmpty && item.catalogId == cleanCatalogId {
                    return true
                }
                if !normName.isEmpty {
                    let iName = item.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let iArtist = item.artist.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if iName == normName && (normArtist.isEmpty || iArtist.isEmpty || iArtist.contains(normArtist) || normArtist.contains(iArtist)) {
                        return true
                    }
                }
                return false
            }
            if pendingStagedCatalogTracks.count != beforePending {
                pendingSnapshotToSave = pendingStagedCatalogTracks
            }
        }

        if !stagedTemporaryTrackDbIds.isEmpty {
            var idsToPromote = Set<Int>()
            if let tid = dbId, tid > 0, tid < 10_000_000, stagedTemporaryTrackDbIds.contains(tid) {
                idsToPromote.insert(tid)
            }
            for qt in activeCustomQueue {
                guard let nid = qt.numericId, nid > 0, stagedTemporaryTrackDbIds.contains(nid) else { continue }
                if !cleanCatalogId.isEmpty && (qt.id == cleanCatalogId || qt.catalogId == cleanCatalogId) {
                    idsToPromote.insert(nid)
                    continue
                }
                if !normName.isEmpty {
                    let qName = qt.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let qArtist = qt.artist.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if qName == normName && (normArtist.isEmpty || qArtist.isEmpty || qArtist.contains(normArtist) || normArtist.contains(qArtist)) {
                        idsToPromote.insert(nid)
                    }
                }
            }
            if !normName.isEmpty {
                for sid in stagedTemporaryTrackDbIds where !idsToPromote.contains(sid) {
                    if let meta = trackMetadataCache[sid] {
                        let mName = meta.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let mArtist = meta.artist.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if mName == normName && (normArtist.isEmpty || mArtist.isEmpty || mArtist.contains(normArtist) || normArtist.contains(mArtist)) {
                            idsToPromote.insert(sid)
                        }
                    }
                }
            }
            if !idsToPromote.isEmpty {
                stagedTemporaryTrackDbIds.subtract(idsToPromote)
                snapshotToSave = Array(stagedTemporaryTrackDbIds)
            }
        }
        let savedKeysSnap = permanentlySavedTrackKeys
        lock.unlock()

        persistPermanentlySavedKeysIfAllowed(savedKeysSnap)
        if let snapshot = snapshotToSave {
            UserDefaults.standard.set(snapshot, forKey: Self.stagedDbIdsStorageKey)
        }
        if let pendingSnap = pendingSnapshotToSave {
            persistPendingStagedTracksIfAllowed(pendingSnap)
        }
    }

    public func promoteStagedTracksForSavedAlbum(name: String, artist: String, tracks: [TrackInfo] = []) {
        let normAlbum = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normArtist = artist
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitIds = Set(tracks.compactMap { t -> Int? in
            if let nid = t.numericId, nid > 0, nid < 10_000_000 { return nid }
            if let pid = Int(t.id), pid > 0, pid < 10_000_000 { return pid }
            return nil
        })
        let explicitCatalogIds = Set(tracks.compactMap { t -> String? in
            let cid = (t.catalogId ?? t.id).trimmingCharacters(in: .whitespacesAndNewlines)
            if let num = Int(cid), num >= 10_000_000 { return cid }
            return nil
        })

        var snapshotToSave: [Int]? = nil
        var pendingSnapshotToSave: [PendingStagedCatalogTrack]? = nil
        lock.lock()
        if !normAlbum.isEmpty {
            recentlyStagedAlbumHistory.removeAll { item in
                MusicKitManager.albumMatches(item.album, item.artist, name, artist)
                    || MusicKitManager.albumMatches(item.trackName, item.artist, name, artist)
            }
        }
        if !pendingStagedCatalogTracks.isEmpty {
            let beforePending = pendingStagedCatalogTracks.count
            pendingStagedCatalogTracks.removeAll { item in
                if !item.catalogId.isEmpty && explicitCatalogIds.contains(item.catalogId) {
                    return true
                }
                if !normAlbum.isEmpty && !item.album.isEmpty {
                    let iAlbum = item.album.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let iArtist = item.artist.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if iAlbum == normAlbum && (normArtist.isEmpty || iArtist.isEmpty || iArtist.contains(normArtist) || normArtist.contains(iArtist)) {
                        return true
                    }
                }
                return false
            }
            if pendingStagedCatalogTracks.count != beforePending {
                pendingSnapshotToSave = pendingStagedCatalogTracks
            }
        }

        if !stagedTemporaryTrackDbIds.isEmpty {
            var idsToPromote = Set<Int>()
            for sid in stagedTemporaryTrackDbIds {
                if explicitIds.contains(sid) {
                    idsToPromote.insert(sid)
                    continue
                }
                if !normAlbum.isEmpty, let meta = trackMetadataCache[sid] {
                    let mAlbum = meta.album
                        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let mArtist = meta.artist
                        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if mAlbum == normAlbum && (normArtist.isEmpty || mArtist.isEmpty || mArtist.contains(normArtist) || normArtist.contains(mArtist)) {
                        idsToPromote.insert(sid)
                    }
                }
            }
            if !idsToPromote.isEmpty {
                stagedTemporaryTrackDbIds.subtract(idsToPromote)
                snapshotToSave = Array(stagedTemporaryTrackDbIds)
            }
        }
        let savedKeysSnap = permanentlySavedTrackKeys
        lock.unlock()

        persistPermanentlySavedKeysIfAllowed(savedKeysSnap)
        if let snapshot = snapshotToSave {
            UserDefaults.standard.set(snapshot, forKey: Self.stagedDbIdsStorageKey)
        }
        if let pendingSnap = pendingSnapshotToSave {
            persistPendingStagedTracksIfAllowed(pendingSnap)
        }
    }

    func computeCleanupCandidatesLocked(keepingActiveQueue: Bool) -> [Int] {
        var keep = Set<Int>()
        if keepingActiveQueue {
            let now = Date()
            sessionStagedTimestamps = sessionStagedTimestamps.filter { now.timeIntervalSince($0.value) < 900.0 }
            for (sid, _) in sessionStagedTimestamps {
                keep.insert(sid)
            }
            var activeKeys = Set<String>()
            for t in activeCustomQueue {
                if let nid = t.numericId, nid > 0 {
                    keep.insert(nid)
                } else if let pid = Int(t.id), pid > 0, pid < 10_000_000 {
                    keep.insert(pid)
                }
                if !t.name.isEmpty {
                    activeKeys.insert(Self.normalizedSavedTrackKey(name: t.name, artist: t.artist))
                }
            }
            if !activeKeys.isEmpty {
                for sid in stagedTemporaryTrackDbIds where !keep.contains(sid) {
                    if let meta = trackMetadataCache[sid],
                       activeKeys.contains(Self.normalizedSavedTrackKey(name: meta.name, artist: meta.artist)) {
                        keep.insert(sid)
                    }
                }
            }
        }
        return Array(stagedTemporaryTrackDbIds.subtracting(keep))
    }

    static func buildVerifiedStagedCleanupAppleScript(
        idList: String,
        clearEntireAMRQueue: Bool,
        wipeStagedBufferPlaylist: Bool = false,
        timeoutSeconds: Double = 3.0
    ) -> String {
        let clearAMRClause = clearEntireAMRQueue ? """
            try
                repeat with bp in (get every user playlist whose name is "Буфер AMR")
                    try
                        delete bp
                    end try
                end repeat
            end try
        """ : ""

        return """
        tell application "Music"
            with timeout of \(timeoutSeconds) seconds
                if not (exists library playlist 1) then return "NOT_READY"
                set curPlName to ""
                set protectedCurId to 0
                try
                    if player state is not stopped then
                        if exists current playlist then
                            set curPlName to (name of current playlist as string)
                        end if
                        set curId to database ID of current track
                        if curId is in {\(idList)} and \(wipeStagedBufferPlaylist ? "true" : "false") then
                            stop
                            set curPlName to ""
                        else
                            set protectedCurId to curId
                        end if
                    end if
                end try
                if curPlName is not "Очередь AMR" then
                    try
                        repeat with qp in (get every user playlist whose name is "Очередь AMR")
                            try
                                delete qp
                            end try
                        end repeat
                    end try
                end if
                \(clearAMRClause)
                set remainingIds to {}
                set libDeleted to 0
                repeat with tid in {\(idList)}
                    set tVal to (contents of tid)
                    if protectedCurId > 0 and tVal is protectedCurId then
                        set end of remainingIds to (tVal as string)
                    else
                        try
                            if (count of (every track of library playlist 1 whose database ID is tVal)) > 0 then
                                delete (every track of library playlist 1 whose database ID is tVal)
                                set libDeleted to libDeleted + 1
                                if (count of (every track of library playlist 1 whose database ID is tVal)) > 0 then
                                    set end of remainingIds to (tVal as string)
                                end if
                            end if
                        on error
                            set end of remainingIds to (tVal as string)
                        end try
                    end if
                end repeat
                set AppleScript's text item delimiters to ","
                set outStr to remainingIds as string
                set AppleScript's text item delimiters to ""
                return "OK:" & libDeleted & ":" & outStr
            end timeout
        end tell
        """
    }

    static func parseVerifiedRemainingIds(from rawOutput: String?) -> (remaining: Set<Int>, deletedFromLibrary: Int)? {
        guard let trimmed = rawOutput?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.hasPrefix("OK:") else {
            return nil
        }
        let body = String(trimmed.dropFirst(3))
        let payload: String
        let libDeleted: Int
        if let colonIdx = body.firstIndex(of: ":"), let cnt = Int(body[..<colonIdx]) {
            libDeleted = cnt
            payload = String(body[body.index(after: colonIdx)...])
        } else {
            libDeleted = 0
            payload = body
        }
        if payload.isEmpty {
            return ([], libDeleted)
        }
        var remaining = Set<Int>()
        for part in payload.split(separator: ",") {
            if let id = Int(part.trimmingCharacters(in: .whitespacesAndNewlines)), id > 0 {
                remaining.insert(id)
            }
        }
        return (remaining, libDeleted)
    }

    /// Schedules deferred cleanup of staged temporary tracks ONLY after AMR has remained stopped & idle for `delay` seconds.
    public func scheduleIdleStagedCleanup(after delay: TimeInterval = 300.0) {
        let scheduledSeq: UInt64 = withLock {
            idleStagedCleanupSeq &+= 1
            return idleStagedCleanupSeq
        }
        guard !PlaybackRouter.shared.isTestingEnvironment else { return }
        stagedCleanupQueue.asyncAfter(deadline: .now() + max(30.0, delay)) { [weak self] in
            guard let self = self, !PlaybackRouter.shared.isTestingEnvironment else { return }
            let stillIdle: Bool = self.withLock {
                guard self.idleStagedCleanupSeq == scheduledSeq else { return false }
                return !self.isCustomQueuePlayback && !self.isStagingCloudTrack
            }
            guard stillIdle else { return }
            self.cleanupStagedTemporaryTracks(keepingActiveQueue: false)
            MusicKitManager.shared.cleanupTemporaryPlaybackPlaylists(keepingActiveQueue: false)
        }
    }

    public func cleanupStagedTemporaryTracks(keepingActiveQueue: Bool = false) {
        if PlaybackRouter.shared.isTestingEnvironment {
            let initialCandidates: [Int] = withLock {
                computeCleanupCandidatesLocked(keepingActiveQueue: keepingActiveQueue)
            }
            guard !initialCandidates.isEmpty else { return }
            let deletedSet = Set(initialCandidates)
            let snapshot: [Int] = withLock {
                stagedTemporaryTrackDbIds.subtract(deletedSet)
                return Array(stagedTemporaryTrackDbIds)
            }
            UserDefaults.standard.set(snapshot, forKey: Self.stagedDbIdsStorageKey)
            LibraryService.shared.removeStagedTracksFromCache(dbIds: deletedSet)
            MusicKitManager.clearRecentlyStagedCatalogIds()
            return
        }

        let hasPotentialWork: Bool = withLock {
            !computeCleanupCandidatesLocked(keepingActiveQueue: keepingActiveQueue).isEmpty || !pendingStagedCatalogTracks.isEmpty
        }
        guard hasPotentialWork else { return }

        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else {
            let persistedSnapshot = withLock { Array(stagedTemporaryTrackDbIds) }
            UserDefaults.standard.set(persistedSnapshot, forKey: Self.stagedDbIdsStorageKey)
            return
        }

        stagedCleanupQueue.async { [weak self] in
            guard let self = self, !PlaybackRouter.shared.isTestingEnvironment else { return }
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else { return }

            // Never issue `DeleteMatchTracks` while `AMPLibraryAgent` has an active `eSyncCmd` (`isStagingCloudTrack`),
            // as `AMPLibraryAgent` cancels `eSyncCmd` with `status:-128` when an outgoing delete is queued.
            let isStagingNow = self.withLock { self.isStagingCloudTrack }
            if isStagingNow || (keepingActiveQueue && AppleScriptExecutor.shared.isBusy) {
                self.stagedCleanupQueue.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                    guard let self = self else { return }
                    let stillActive = self.withLock { self.isCustomQueuePlayback || self.isStagingCloudTrack }
                    self.cleanupStagedTemporaryTracks(keepingActiveQueue: keepingActiveQueue && stillActive)
                }
                return
            }

            _ = MusicKitManager.shared.harvestPendingStagedCatalogTracksInMusicAppSync()

            let candidates: [Int] = self.withLock {
                self.computeCleanupCandidatesLocked(keepingActiveQueue: keepingActiveQueue)
            }
            guard !candidates.isEmpty else { return }

            let idList = candidates.map { "\($0)" }.joined(separator: ", ")
            let script = Self.buildVerifiedStagedCleanupAppleScript(
                idList: idList,
                clearEntireAMRQueue: !keepingActiveQueue,
                wipeStagedBufferPlaylist: !keepingActiveQueue,
                timeoutSeconds: 2.2
            )
            let rawOut = AppleScriptExecutor.shared.executeDescriptor(script, maxWait: 2.6, reportTimeout: false)?.stringValue
            guard let parsed = Self.parseVerifiedRemainingIds(from: rawOut) else {
                return
            }

            let confirmedDeleted = Set(candidates).subtracting(parsed.remaining)
            if !confirmedDeleted.isEmpty {
                let updatedSnapshot: [Int] = self.withLock {
                    self.stagedTemporaryTrackDbIds.subtract(confirmedDeleted)
                    for did in confirmedDeleted {
                        self.sessionStagedTimestamps.removeValue(forKey: did)
                    }
                    return Array(self.stagedTemporaryTrackDbIds)
                }
                UserDefaults.standard.set(updatedSnapshot, forKey: Self.stagedDbIdsStorageKey)
                LibraryService.shared.removeStagedTracksFromCache(dbIds: confirmedDeleted)
                MusicKitManager.clearRecentlyStagedCatalogIds()
                if parsed.deletedFromLibrary > 0 {
                    LibraryService.shared.invalidateLibrarySongsCache()
                }
            }
        }
    }

    public func cleanupStagedTemporaryTracksSyncOnTerminate() {
        let toDelete: [Int] = withLock {
            Array(stagedTemporaryTrackDbIds)
        }
        guard !toDelete.isEmpty else { return }

        if PlaybackRouter.shared.isTestingEnvironment {
            let deletedSet = Set(toDelete)
            let snapshot: [Int] = withLock {
                stagedTemporaryTrackDbIds.subtract(deletedSet)
                return Array(stagedTemporaryTrackDbIds)
            }
            UserDefaults.standard.set(snapshot, forKey: Self.stagedDbIdsStorageKey)
            LibraryService.shared.removeStagedTracksFromCache(dbIds: deletedSet)
            MusicKitManager.clearRecentlyStagedCatalogIds()
            return
        }

        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else {
            let persistedSnapshot = withLock { Array(stagedTemporaryTrackDbIds) }
            UserDefaults.standard.set(persistedSnapshot, forKey: Self.stagedDbIdsStorageKey)
            return
        }

        let idList = toDelete.map { "\($0)" }.joined(separator: ", ")
        let script = Self.buildVerifiedStagedCleanupAppleScript(
            idList: idList,
            clearEntireAMRQueue: true,
            wipeStagedBufferPlaylist: true,
            timeoutSeconds: 1.3
        )

        let sema = DispatchSemaphore(value: 0)
        let boxLock = NSLock()
        var scriptOutput: String? = nil
        var scriptOk = false

        DispatchQueue.global(qos: .userInitiated).async {
            let (ok, out) = AppleScriptExecutor.shared.execute(script)
            boxLock.lock()
            scriptOk = ok
            scriptOutput = out
            boxLock.unlock()
            sema.signal()
        }

        if sema.wait(timeout: .now() + 1.8) == .timedOut {
            let persistedSnapshot = withLock { Array(stagedTemporaryTrackDbIds) }
            UserDefaults.standard.set(persistedSnapshot, forKey: Self.stagedDbIdsStorageKey)
            return
        }

        boxLock.lock()
        let ok = scriptOk
        let out = scriptOutput
        boxLock.unlock()

        if ok, let parsed = Self.parseVerifiedRemainingIds(from: out) {
            let confirmedDeleted = Set(toDelete).subtracting(parsed.remaining)
            let updatedSnapshot: [Int] = withLock {
                stagedTemporaryTrackDbIds.subtract(confirmedDeleted)
                return Array(stagedTemporaryTrackDbIds)
            }
            UserDefaults.standard.set(updatedSnapshot, forKey: Self.stagedDbIdsStorageKey)
            LibraryService.shared.removeStagedTracksFromCache(dbIds: confirmedDeleted)
            MusicKitManager.clearRecentlyStagedCatalogIds()
        } else {
            let persistedSnapshot = withLock { Array(stagedTemporaryTrackDbIds) }
            UserDefaults.standard.set(persistedSnapshot, forKey: Self.stagedDbIdsStorageKey)
        }
    }
}
