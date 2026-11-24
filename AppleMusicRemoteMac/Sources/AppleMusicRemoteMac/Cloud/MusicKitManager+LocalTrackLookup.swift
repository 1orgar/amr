//
//  MusicKitManager+LocalTrackLookup.swift
//  AppleMusicRemoteMac
//
//  Local Music.app track database ID lookup, atomic single-pass library tail snapshotting,
//  staged queue track harvesting, and cloud sync menu nudging.
//

import AppKit
import ApplicationServices
import Foundation

extension MusicKitManager {

    // MARK: - Local Music.app Track Lookup & Atomic Tail Snapshot

    private static let rowFieldSeparator = "||AMR||"

    public func findTrackDatabaseIdInMusicApp(
        name: String,
        artist: String,
        preferredDbId: Int? = nil,
        checkSubscriptionPlaylists: Bool = false,
        alternateTitles: [String] = [],
        alternateArtists: [String] = []
    ) -> Int? {
        return findTrackDatabaseIdDetailedInMusicApp(
            name: name,
            artist: artist,
            preferredDbId: preferredDbId,
            checkSubscriptionPlaylists: checkSubscriptionPlaylists,
            alternateTitles: alternateTitles,
            alternateArtists: alternateArtists
        )?.dbId
    }

    public func findTrackDatabaseIdDetailedInMusicApp(
        name: String,
        artist: String,
        preferredDbId: Int? = nil,
        checkSubscriptionPlaylists: Bool = false,
        alternateTitles: [String] = [],
        alternateArtists: [String] = []
    ) -> (dbId: Int, isPermanentLibrary: Bool, album: String)? {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return nil }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let validPrefId = (preferredDbId != nil && preferredDbId! > 0 && preferredDbId! < 10_000_000) ? preferredDbId! : 0
        var candidateTitles: [String] = []
        if !cleanName.isEmpty {
            candidateTitles.append(cleanName)
        }
        for alt in alternateTitles {
            let trimmedAlt = alt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedAlt.isEmpty && !candidateTitles.contains(where: { $0.caseInsensitiveCompare(trimmedAlt) == .orderedSame }) {
                candidateTitles.append(trimmedAlt)
            }
        }
        guard !candidateTitles.isEmpty || validPrefId > 0 else { return nil }

        let baseName = Self.extractBaseTrackTitle(cleanName)
        let escBase = (baseName.isEmpty ? cleanName : baseName)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let altSearchTerm: String = {
            for alt in candidateTitles.dropFirst() {
                let b = Self.extractBaseTrackTitle(alt)
                let term = b.isEmpty ? alt : b
                if !term.isEmpty && term.caseInsensitiveCompare(baseName.isEmpty ? cleanName : baseName) != .orderedSame {
                    return term
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "\"", with: "\\\"")
                }
            }
            return ""
        }()
        var candidateArtists: [String] = []
        for tok in Self.extractArtistTokens(artist) where !candidateArtists.contains(tok) {
            candidateArtists.append(tok)
        }
        for altArt in alternateArtists {
            for tok in Self.extractArtistTokens(altArt) where !candidateArtists.contains(tok) {
                candidateArtists.append(tok)
            }
        }

        let normalizedTargets: [(raw: String, norm: String, base: String)] = candidateTitles.map { raw in
            let n = LibraryService.normalizeMatchingTitle(raw)
            let bRaw = Self.extractBaseTrackTitle(raw)
            let b = LibraryService.normalizeMatchingTitle(bRaw.isEmpty ? raw : bRaw)
            return (raw: raw, norm: n, base: b)
        }

        let sep = Self.rowFieldSeparator
        func matchCandidateRows(_ raw: String?) -> (dbId: Int, isPermanentLibrary: Bool, album: String)? {
            guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, text != "0" else { return nil }
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed != "0" else { continue }
                let parts = trimmed.components(separatedBy: sep)
                guard parts.count >= 2, let id = Int(parts[1]), id > 0 else { continue }
                let isPerm = (parts[0] == "lib")
                let rowAlbum = parts.count >= 5 ? parts[4] : ""
                if parts.count < 4 || normalizedTargets.isEmpty {
                    return (dbId: id, isPermanentLibrary: isPerm, album: rowAlbum)
                }
                let rowName = parts[2]
                let rowArtist = parts[3]
                if !cleanName.isEmpty && LibraryService.hasConflictingVersionQualifier(cleanName, rowName) {
                    continue
                }
                let rowNorm = LibraryService.normalizeMatchingTitle(rowName)
                let rowBaseRaw = Self.extractBaseTrackTitle(rowName)
                let rowBase = LibraryService.normalizeMatchingTitle(rowBaseRaw.isEmpty ? rowName : rowBaseRaw)

                let nameMatch = normalizedTargets.contains { target in
                    if LibraryService.hasConflictingVersionQualifier(target.raw, rowName) {
                        return false
                    }
                    if !target.norm.isEmpty && rowNorm == target.norm {
                        return true
                    }
                    if !target.base.isEmpty && (rowBase == target.base || (target.base.count >= 4 && rowNorm.contains(target.base))) {
                        return true
                    }
                    return false
                }
                guard nameMatch else { continue }
                if !candidateArtists.isEmpty {
                    guard Self.matchesAnyCandidateArtist(rowArtist, candidates: candidateArtists) else { continue }
                }
                return (dbId: id, isPermanentLibrary: isPerm, album: rowAlbum)
            }
            return nil
        }

        let prefSubCheck = (checkSubscriptionPlaylists && validPrefId > 0) ? """
                        repeat with sp in (get every playlist)
                            try
                                set prefTr to (first track of sp whose database ID is \(validPrefId))
                                return "sub\(sep)" & ((database ID of prefTr as integer) as string) & "\(sep)" & (name of prefTr as string) & "\(sep)" & (artist of prefTr as string) & "\(sep)" & (album of prefTr as string)
                            end try
                        end repeat
        """ : ""

        let prefCheck = validPrefId > 0 ? """
                        try
                            set prefTr to (first track of user playlist "Очередь AMR" whose database ID is \(validPrefId))
                            return "amr\(sep)" & ((database ID of prefTr as integer) as string) & "\(sep)" & (name of prefTr as string) & "\(sep)" & (artist of prefTr as string) & "\(sep)" & (album of prefTr as string)
                        end try
                        try
                            set prefTr to (first track of library playlist 1 whose database ID is \(validPrefId))
                            return "lib\(sep)" & ((database ID of prefTr as integer) as string) & "\(sep)" & (name of prefTr as string) & "\(sep)" & (artist of prefTr as string) & "\(sep)" & (album of prefTr as string)
                        end try
                        \(prefSubCheck)
        """ : ""

        let tailScanCheck = !normalizedTargets.isEmpty ? """
                        try
                            repeat with qp in (get every user playlist whose name is "Очередь AMR")
                                repeat with tr in (every track of qp)
                                    try
                                        set trName to (name of tr as string)
                                        set trArtist to (artist of tr as string)
                                        set trAlbum to (album of tr as string)
                                        set end of outRows to "amr\(sep)" & ((database ID of tr as integer) as string) & "\(sep)" & trName & "\(sep)" & trArtist & "\(sep)" & trAlbum
                                    end try
                                end repeat
                            end repeat
                        end try
        """ : ""

        let altIndexedSearchCheck = !altSearchTerm.isEmpty ? """
                        try
                            set altFoundList to (search (library playlist 1) for "\(altSearchTerm)")
                            repeat with tr in altFoundList
                                try
                                    set trName to (name of tr as string)
                                    set trArtist to (artist of tr as string)
                                    set trAlbum to (album of tr as string)
                                    set end of outRows to "lib\(sep)" & ((database ID of tr as integer) as string) & "\(sep)" & trName & "\(sep)" & trArtist & "\(sep)" & trAlbum
                                end try
                            end repeat
                        end try
        """ : ""

        let subSearchCheck = (checkSubscriptionPlaylists && !escBase.isEmpty) ? """
                        repeat with sp in (get every subscription playlist)
                            try
                                set foundSubList to (search sp for "\(escBase)")
                                repeat with tr in foundSubList
                                    try
                                        set trName to (name of tr as string)
                                        set trArtist to (artist of tr as string)
                                        set trAlbum to (album of tr as string)
                                        set end of outRows to "sub\(sep)" & ((database ID of tr as integer) as string) & "\(sep)" & trName & "\(sep)" & trArtist & "\(sep)" & trAlbum
                                    end try
                                end repeat
                            end try
                        end repeat
        """ : ""

        let indexedSearchCheck = !escBase.isEmpty ? """
                        try
                            set foundList to (search (library playlist 1) for "\(escBase)")
                            repeat with tr in foundList
                                try
                                    set trName to (name of tr as string)
                                    set trArtist to (artist of tr as string)
                                    set trAlbum to (album of tr as string)
                                    set end of outRows to "lib\(sep)" & ((database ID of tr as integer) as string) & "\(sep)" & trName & "\(sep)" & trArtist & "\(sep)" & trAlbum
                                end try
                            end repeat
                        end try
                        \(altIndexedSearchCheck)
                        \(subSearchCheck)
        """ : ""

        let script = """
        tell application "Music"
            try
                with timeout of 2 seconds
                    \(prefCheck)
                    set outRows to {}
                    \(tailScanCheck)
                    \(indexedSearchCheck)
                    if (count of outRows) is 0 then
                        return "0"
                    end if
                    set AppleScript's text item delimiters to linefeed
                    set outText to outRows as string
                    set AppleScript's text item delimiters to ""
                    return outText
                end timeout
            on error
                return "0"
            end try
        end tell
        """
        let (ok, out) = AppleScriptExecutor.shared.execute(script, maxWait: 2.5, reportTimeout: false)
        if ok, let parsed = matchCandidateRows(out) {
            return parsed
        }
        return nil
    }

    /// Reads `(database ID, name, artist, album, duration)` for recently materialized tracks in `library playlist 1`
    /// in a single atomic per-track pass (`~2 ms`), computing `cutoffDate` outside `tell application "Music"` (avoids `-10004`).
    public func snapshotLibraryTailTracksInMusicApp(limit: Int = 45) -> [(dbId: Int, name: String, artist: String, album: String, duration: Double)] {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return [] }
        let maxScan = max(1, min(max(limit * 3, 120), 250))
        let script = """
        set cutoffDate to (current date) - 3600
        tell application "Music"
            try
                with timeout of 2 seconds
                    if not (exists library playlist 1) then return {}
                    set rowsList to {}
                    set scannedCount to 0
                    set recentTracks to {}
                    try
                        set recentTracks to (every track of library playlist 1 whose date added > cutoffDate)
                    end try
                    if (count of recentTracks) is 0 then
                        try
                            if (count of tracks of library playlist 1) ≤ 80 then
                                set recentTracks to (every track of library playlist 1)
                            end if
                        end try
                    end if
                    repeat with tr in recentTracks
                        try
                            set trId to (database ID of tr as integer)
                            set trName to (name of tr as string)
                            set trArtist to (artist of tr as string)
                            set trAlbum to (album of tr as string)
                            set trDur to (duration of tr as real)
                            if trId > 0 and trName is not "" then
                                set end of rowsList to {trId, trName, trArtist, trAlbum, trDur}
                                set scannedCount to scannedCount + 1
                                if scannedCount ≥ \(maxScan) then
                                    exit repeat
                                end if
                            end if
                        end try
                    end repeat
                    return rowsList
                end timeout
            on error
                return {}
            end try
        end tell
        """
        guard let desc = AppleScriptExecutor.shared.executeDescriptor(script, maxWait: 2.5, reportTimeout: false) else {
            return []
        }
        let count = desc.numberOfItems
        guard count > 0 else { return [] }

        var rows: [(dbId: Int, name: String, artist: String, album: String, duration: Double)] = []
        rows.reserveCapacity(count)
        for i in 1...count {
            guard let rowDesc = desc.atIndex(i), rowDesc.numberOfItems >= 5 else { continue }
            let dbId = Int(rowDesc.atIndex(1)?.int32Value ?? 0)
            let tName = rowDesc.atIndex(2)?.stringValue ?? ""
            let tArtist = rowDesc.atIndex(3)?.stringValue ?? ""
            let tAlbum = rowDesc.atIndex(4)?.stringValue ?? ""
            let dur = rowDesc.atIndex(5)?.doubleValue ?? 0
            if dbId > 0 && !tName.isEmpty {
                rows.append((dbId: dbId, name: tName, artist: tArtist, album: tAlbum, duration: dur))
            }
        }
        return rows
    }

    @discardableResult
    public func harvestStagedQueueTrackDbIdsFromLibraryTailSync(expectedGeneration: UInt64? = nil) -> Int {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return 0 }
        let tailRows = snapshotLibraryTailTracksInMusicApp(limit: 45)
        guard !tailRows.isEmpty else { return 0 }

        let (queueSnap, gen): ([TrackInfo], UInt64) = PlaybackStateStore.shared.withLock {
            (PlaybackStateStore.shared.activeCustomQueue, PlaybackStateStore.shared.playbackGeneration)
        }
        if let expGen = expectedGeneration, expGen != gen {
            return 0
        }

        let sf = Self.sanitizedStorefront(getUserStorefront())
        let primaryLang = getPreferredLanguageTag()
        let sysAltLang = getSystemStorefrontAlternateLanguageTag()

        var resolvedByQueueIndex: [(idx: Int, dbId: Int, row: (dbId: Int, name: String, artist: String, album: String, duration: Double), cid: String?)] = []
        for (qIdx, qt) in queueSnap.enumerated() {
            if let existingNid = qt.numericId, existingNid > 0, existingNid < 10_000_000 {
                continue
            }
            let cid = Self.extractNumericCatalogId(from: qt)
            var candidateTitles: [String] = []
            var candidateArtists: [String] = []
            let cleanQtName = qt.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanQtName.isEmpty {
                candidateTitles.append(cleanQtName)
            }
            for tok in Self.extractArtistTokens(qt.artist) where !candidateArtists.contains(tok) {
                candidateArtists.append(tok)
            }
            if let validCid = cid {
                let cacheKey = "\(sf)|\(validCid)|\(primaryLang)|\(sysAltLang ?? "")"
                if let cachedVariants = Self.localizedTitlesCacheLock.withLock({ Self.localizedTitlesCache[cacheKey] }) {
                    for v in cachedVariants {
                        if !v.name.isEmpty && !candidateTitles.contains(where: { $0.caseInsensitiveCompare(v.name) == .orderedSame }) {
                            candidateTitles.append(v.name)
                        }
                        for tok in Self.extractArtistTokens(v.artist) where !candidateArtists.contains(tok) {
                            candidateArtists.append(tok)
                        }
                    }
                }
            }
            guard !candidateTitles.isEmpty else { continue }

            for row in tailRows {
                if !cleanQtName.isEmpty && LibraryService.hasConflictingVersionQualifier(cleanQtName, row.name) {
                    continue
                }
                let rowNorm = LibraryService.normalizeMatchingTitle(row.name)
                let rowBaseRaw = Self.extractBaseTrackTitle(row.name)
                let rowBase = LibraryService.normalizeMatchingTitle(rowBaseRaw.isEmpty ? row.name : rowBaseRaw)
                let titleOk = candidateTitles.contains { candTitle in
                    if LibraryService.hasConflictingVersionQualifier(candTitle, row.name) {
                        return false
                    }
                    let tNorm = LibraryService.normalizeMatchingTitle(candTitle)
                    let tBaseRaw = Self.extractBaseTrackTitle(candTitle)
                    let tBase = LibraryService.normalizeMatchingTitle(tBaseRaw.isEmpty ? candTitle : tBaseRaw)
                    if !tNorm.isEmpty && rowNorm == tNorm { return true }
                    if !tBase.isEmpty && (rowBase == tBase || (tBase.count >= 4 && rowNorm.contains(tBase))) { return true }
                    return false
                }
                guard titleOk else { continue }
                if !candidateArtists.isEmpty {
                    guard Self.matchesAnyCandidateArtist(row.artist, candidates: candidateArtists) else { continue }
                }
                resolvedByQueueIndex.append((idx: qIdx, dbId: row.dbId, row: row, cid: cid))
                break
            }
        }

        // Also sweep pendingStagedCatalogTracks (e.g. from prestagePreviewHeadTracks before queue started)
        let pendingSnap = PlaybackStateStore.shared.pendingStagedCatalogTracksSnapshot()
        for p in pendingSnap {
            let cleanPName = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
            var pTitles: [String] = cleanPName.isEmpty ? [] : [cleanPName]
            var pArtists: [String] = []
            for tok in Self.extractArtistTokens(p.artist) where !pArtists.contains(tok) {
                pArtists.append(tok)
            }
            for v in cachedTitleVariants(catalogId: p.catalogId) {
                if !v.name.isEmpty && !pTitles.contains(where: { $0.caseInsensitiveCompare(v.name) == .orderedSame }) {
                    pTitles.append(v.name)
                }
                for tok in Self.extractArtistTokens(v.artist) where !pArtists.contains(tok) {
                    pArtists.append(tok)
                }
            }
            guard !pTitles.isEmpty else { continue }

            for row in tailRows {
                if !cleanPName.isEmpty && LibraryService.hasConflictingVersionQualifier(cleanPName, row.name) { continue }
                let rNorm = LibraryService.normalizeMatchingTitle(row.name)
                let rBaseRaw = Self.extractBaseTrackTitle(row.name)
                let rBase = LibraryService.normalizeMatchingTitle(rBaseRaw.isEmpty ? row.name : rBaseRaw)
                let titleOk = pTitles.contains { pt in
                    if LibraryService.hasConflictingVersionQualifier(pt, row.name) { return false }
                    let pNorm = LibraryService.normalizeMatchingTitle(pt)
                    let pBaseRaw = Self.extractBaseTrackTitle(pt)
                    let pBase = LibraryService.normalizeMatchingTitle(pBaseRaw.isEmpty ? pt : pBaseRaw)
                    return (!pNorm.isEmpty && rNorm == pNorm) || (!pBase.isEmpty && rBase == pBase)
                }
                guard titleOk else { continue }
                if !pArtists.isEmpty {
                    guard Self.matchesAnyCandidateArtist(row.artist, candidates: pArtists) else { continue }
                }
                if !PlaybackStateStore.shared.isTrackPermanentlySaved(id: p.catalogId, name: p.name, artist: p.artist) {
                    LibraryService.shared.registerStagedTrackInCache(
                        dbId: row.dbId,
                        name: p.name,
                        artist: p.artist.isEmpty ? row.artist : p.artist,
                        album: p.album.isEmpty ? row.album : p.album,
                        duration: row.duration
                    )
                    if row.name.caseInsensitiveCompare(p.name) != .orderedSame {
                        LibraryService.shared.registerStagedTrackInCache(
                            dbId: row.dbId,
                            name: row.name,
                            artist: row.artist,
                            album: p.album.isEmpty ? row.album : p.album,
                            duration: row.duration
                        )
                    }
                }
                PlaybackStateStore.shared.clearPendingStagedCatalogTrack(catalogId: p.catalogId, name: p.name, artist: p.artist)
                break
            }
        }

        guard !resolvedByQueueIndex.isEmpty else { return 0 }

        var newlyAssigned = 0
        for item in resolvedByQueueIndex {
            let qt = queueSnap[item.idx]
            let isPermSaved = (qt.isLocal == true) || PlaybackStateStore.shared.isTrackPermanentlySaved(
                id: item.cid ?? qt.id,
                name: qt.name,
                artist: qt.artist
            )
            if !isPermSaved {
                LibraryService.shared.registerStagedTrackInCache(
                    dbId: item.dbId,
                    name: qt.name.isEmpty ? item.row.name : qt.name,
                    artist: qt.artist.isEmpty ? item.row.artist : qt.artist,
                    album: qt.album.isEmpty ? item.row.album : qt.album,
                    duration: item.row.duration
                )
                if !qt.name.isEmpty && item.row.name.caseInsensitiveCompare(qt.name) != .orderedSame {
                    LibraryService.shared.registerStagedTrackInCache(
                        dbId: item.dbId,
                        name: item.row.name,
                        artist: item.row.artist,
                        album: qt.album.isEmpty ? item.row.album : qt.album,
                        duration: item.row.duration
                    )
                }
            }
            PlaybackStateStore.shared.clearPendingStagedCatalogTrack(
                catalogId: item.cid,
                name: qt.name,
                artist: qt.artist
            )
        }

        PlaybackStateStore.shared.withLock {
            if let expGen = expectedGeneration, PlaybackStateStore.shared.playbackGeneration != expGen {
                return
            }
            for item in resolvedByQueueIndex {
                guard item.idx >= 0 && item.idx < PlaybackStateStore.shared.activeCustomQueue.count else { continue }
                let existing = PlaybackStateStore.shared.activeCustomQueue[item.idx].numericId ?? 0
                if existing <= 0 || existing >= 10_000_000 {
                    PlaybackStateStore.shared.activeCustomQueue[item.idx].numericId = item.dbId
                    if let validCid = item.cid, PlaybackStateStore.shared.activeCustomQueue[item.idx].catalogId == nil {
                        PlaybackStateStore.shared.activeCustomQueue[item.idx].catalogId = validCid
                    }
                    if PlaybackStateStore.shared.activeCustomQueue[item.idx].duration <= 0 && item.row.duration > 0 {
                        PlaybackStateStore.shared.activeCustomQueue[item.idx].duration = item.row.duration
                    }
                    newlyAssigned += 1
                }
            }
            if newlyAssigned > 0 {
                let curIdx = PlaybackStateStore.shared.activeCustomQueueIndex
                let q = PlaybackStateStore.shared.activeCustomQueue
                if curIdx + 1 < q.count {
                    PlaybackStateStore.shared.latestUpcomingTracks = Array(q[(curIdx + 1)...])
                }
                PlaybackStateStore.shared.playbackQueueCache = nil
            }
        }
        return newlyAssigned
    }

    public func snapshotStagedBufferTracksInMusicApp() -> [(dbId: Int, name: String, artist: String)] {
        return snapshotLibraryTailTracksInMusicApp(limit: 40).map { ($0.dbId, $0.name, $0.artist) }
    }

    public func matchTrackInStagedBufferSnapshot(
        name: String,
        artist: String,
        snapshot: [(dbId: Int, name: String, artist: String)]
    ) -> Int? {
        guard !snapshot.isEmpty else { return nil }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }
        let normTarget = LibraryService.normalizeMatchingTitle(cleanName)
        let baseRaw = Self.extractBaseTrackTitle(cleanName)
        let normBase = LibraryService.normalizeMatchingTitle(baseRaw.isEmpty ? cleanName : baseRaw)
        let artistTokens = Self.extractArtistTokens(artist)

        for row in snapshot {
            if LibraryService.hasConflictingVersionQualifier(cleanName, row.name) {
                continue
            }
            let rowNorm = LibraryService.normalizeMatchingTitle(row.name)
            let rowBaseRaw = Self.extractBaseTrackTitle(row.name)
            let rowBase = LibraryService.normalizeMatchingTitle(rowBaseRaw.isEmpty ? row.name : rowBaseRaw)
            let nameMatch = (!normTarget.isEmpty && rowNorm == normTarget)
                || (!normBase.isEmpty && (rowBase == normBase || rowNorm.contains(normBase) || normTarget.contains(rowBase)))
            guard nameMatch else { continue }
            if artistTokens.isEmpty || Self.matchesAnyCandidateArtist(row.artist, candidates: artistTokens) {
                return row.dbId
            }
        }
        return nil
    }

    internal func nudgeCloudSyncMenuForPrestage() {
        nudgeMusicAppCloudSyncMenuOnly()
    }

    /// Scans `library playlist 1` for ANY tracks matching `pendingStagedCatalogTracks` (including late APNs arrivals
    /// and multiple releases of the same song) and registers all non-permanently-saved `dbId`s as temporary staged tracks.
    @discardableResult
    public func harvestPendingStagedCatalogTracksInMusicAppSync() -> Set<Int> {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return [] }
        let pending = PlaybackStateStore.shared.pendingStagedCatalogTracksSnapshot()
        guard !pending.isEmpty else { return [] }

        let snapshot = snapshotLibraryTailTracksInMusicApp(limit: 80)
        let nowTs = Date().timeIntervalSince1970
        var registered = Set<Int>()

        for entry in pending {
            let cleanName = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let normTarget = LibraryService.normalizeMatchingTitle(cleanName)
            let baseRaw = Self.extractBaseTrackTitle(cleanName)
            let normBase = LibraryService.normalizeMatchingTitle(baseRaw.isEmpty ? cleanName : baseRaw)
            let artistTokens = Self.extractArtistTokens(entry.artist)
            var matchedAny = false

            for row in snapshot where row.dbId > 0 {
                let rowNorm = LibraryService.normalizeMatchingTitle(row.name)
                let rowBaseRaw = Self.extractBaseTrackTitle(row.name)
                let rowBase = LibraryService.normalizeMatchingTitle(rowBaseRaw.isEmpty ? row.name : rowBaseRaw)
                let nameMatch = (!normTarget.isEmpty && rowNorm == normTarget)
                    || (!normBase.isEmpty && normBase.count >= 4 && (rowBase == normBase || rowNorm.contains(normBase) || normTarget.contains(rowBase)))
                guard nameMatch else { continue }
                if !artistTokens.isEmpty && !Self.matchesAnyCandidateArtist(row.artist, candidates: artistTokens) {
                    continue
                }
                matchedAny = true
                if !PlaybackStateStore.shared.isTrackPermanentlySaved(id: entry.catalogId, name: row.name, artist: row.artist) {
                    PlaybackStateStore.shared.registerStagedTemporaryTrack(dbId: row.dbId)
                    registered.insert(row.dbId)
                }
            }

            let age = nowTs - entry.stagedAt
            if (matchedAny && age > 45.0) || age > 180.0 {
                PlaybackStateStore.shared.clearPendingStagedCatalogTrack(
                    catalogId: entry.catalogId,
                    name: entry.name,
                    artist: entry.artist
                )
            }
        }
        return registered
    }

    public func scheduleOrphanedStagedTrackSweep(candidates: [(id: String?, name: String, artist: String, album: String)]) {
        guard !PlaybackRouter.shared.isTestingEnvironment, !candidates.isEmpty else { return }
        for cand in candidates {
            if let cid = cand.id, !cid.isEmpty {
                PlaybackStateStore.shared.recordPendingStagedCatalogTrack(
                    catalogId: cid,
                    name: cand.name,
                    artist: cand.artist,
                    album: cand.album
                )
            }
        }
        for delay in [2.5, 8.5, 18.0, 28.0] {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                let (isStaging, isActiveCustom) = PlaybackStateStore.shared.withLock {
                    (PlaybackStateStore.shared.isStagingCloudTrack, PlaybackStateStore.shared.isCustomQueuePlayback)
                }
                guard !isStaging else { return }
                _ = self.harvestPendingStagedCatalogTracksInMusicAppSync()
                PlaybackStateStore.shared.cleanupStagedTemporaryTracks(keepingActiveQueue: isActiveCustom)
            }
        }
    }

    internal func nudgeMusicAppCloudSyncMenuOnly(allowWhilePlaying: Bool = false) {
        guard !PlaybackRouter.shared.isTestingEnvironment, AXIsProcessTrusted() else { return }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else { return }
        let shouldProceed: Bool = Self.stageDedupLock.withLock {
            let now = Date()
            guard now.timeIntervalSince(Self.lastCloudMenuNudgeAt) >= 12.0 else { return false }
            Self.lastCloudMenuNudgeAt = now
            return true
        }
        guard shouldProceed else { return }
        let playingGuard = allowWhilePlaying ? "" : """
            tell application "Music"
                try
                    if player state is playing then return
                end try
            end tell
        """
        DispatchQueue.global(qos: .utility).async {
            let pUpd = Process()
            pUpd.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            pUpd.standardOutput = Pipe()
            pUpd.standardError = Pipe()
            pUpd.arguments = ["-e", """
            \(playingGuard)
            tell application "System Events" to tell process "Music"
                try
                    set libMenu to menu 1 of (first menu item of menu 1 of menu bar item 3 of menu bar 1 whose name contains "Медиатека" or name contains "Library")
                    click (first menu item of libMenu whose name contains "облачн" or name contains "Cloud")
                end try
            end tell
            """]
            let doneSema = DispatchSemaphore(value: 0)
            pUpd.terminationHandler = { _ in
                doneSema.signal()
            }
            do {
                try pUpd.run()
                if doneSema.wait(timeout: .now() + 3.0) == .timedOut {
                    if pUpd.isRunning {
                        pUpd.terminate()
                    }
                }
            } catch {
                // Ignore osascript launch failure
            }
        }
    }

    internal func triggerCloudLibrarySyncInMusicApp() {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return }
        nudgeMusicAppCloudSyncMenuOnly(allowWhilePlaying: true)
        for delay in [2.5, 6.5, 12.0] {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
                LibraryService.shared.invalidateLibrarySongsCache()
                LibraryService.shared.invalidatePlaylistsCache()
            }
        }
    }
}
