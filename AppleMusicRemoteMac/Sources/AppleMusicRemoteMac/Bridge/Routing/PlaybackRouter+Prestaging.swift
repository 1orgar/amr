//
//  PlaybackRouter+Prestaging.swift
//  AppleMusicRemoteMac
//
//  100% read-only in-memory Apple Music catalog pre-warming (storefront canonical IDs,
//  ISRC alternates, localized cross-script title variants, and durations).
//  Strictly ZERO writes to `/v1/me/library` or `/v1/me/library/playlists`!
//

import Foundation

extension PlaybackRouter {

    private static let prestageSeqLock = NSLock()
    private static var prestageRequestSeq: UInt64 = 0
    private static var pendingUpcomingPrestageWorkItem: DispatchWorkItem?

    private static let previewPrestageSeqLock = NSLock()
    private static var previewPrestageRequestSeq: UInt64 = 0
    private static var pendingPreviewPrestageWorkItem: DispatchWorkItem?

    private static let prestageWorkerQueue = DispatchQueue(label: "com.amr.router.prestage", qos: .utility)

    internal static func currentPrestageRequestSeqForTesting() -> UInt64 {
        prestageSeqLock.withLock { prestageRequestSeq }
    }

    private static let personalMixPrewarmLock = NSLock()
    private static var lastPersonalMixPrewarmAt: Date = .distantPast

    /// Pre-warms read-only in-memory Apple Music catalog storefront IDs & localized-title caches for personal mixes.
    /// NEVER writes anything to `/v1/me/library` or `/v1/me/library/playlists`.
    public func prewarmPersonalMixesHeadTracks() {
        guard !isTestingEnvironment, MusicKitManager.shared.hasUserToken else { return }
        let shouldRun: Bool = Self.personalMixPrewarmLock.withLock {
            let now = Date()
            guard now.timeIntervalSince(Self.lastPersonalMixPrewarmAt) >= 900.0 else { return false }
            Self.lastPersonalMixPrewarmAt = now
            return true
        }
        guard shouldRun else { return }

        Task.detached(priority: .utility) {
            var mixes = MusicKitManager.shared.getCachedPersonalData()?.mixes ?? []
            if mixes.isEmpty {
                mixes = await MusicKitManager.shared.fetchPersonalMixes()
            }
            let mixIds = mixes.compactMap { m -> String? in
                guard let mid = m.id?.trimmingCharacters(in: .whitespacesAndNewlines),
                      mid.hasPrefix("pl.") || mid.hasPrefix("p.") else { return nil }
                return mid
            }
            guard !mixIds.isEmpty else { return }

            var combinedHeadTracks: [TrackInfo] = []
            for mid in mixIds.prefix(5) {
                let tracks = await MusicKitManager.shared.getPlaylistTracksById(playlistId: mid)
                combinedHeadTracks.append(contentsOf: tracks.prefix(2))
            }
            if !combinedHeadTracks.isEmpty {
                DispatchQueue.global(qos: .utility).async {
                    for tr in combinedHeadTracks.prefix(10) {
                        Self.prewarmSingleCatalogTrackInRAM(tr)
                    }
                }
            }
        }
    }

    /// Read-only in-memory pre-warming when the user opens a playlist or album modal.
    /// Strictly ZERO writes to `/v1/me/library` or `/v1/me/library/playlists`!
    public func prestagePreviewHeadTracks(_ tracks: [TrackInfo], count: Int = 4) {
        guard !isTestingEnvironment else { return }
        let headCandidates = Array(tracks.prefix(max(1, min(count, 6)))).filter { tr in
            guard tr.isLocal != true else { return false }
            if let nid = tr.numericId, nid > 0, nid < 10_000_000 {
                return false
            }
            return true
        }
        guard !headCandidates.isEmpty else { return }

        let capturedGen = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.playbackGeneration }
        let myPreviewSeq: UInt64 = Self.previewPrestageSeqLock.withLock {
            Self.pendingPreviewPrestageWorkItem?.cancel()
            Self.previewPrestageRequestSeq &+= 1
            return Self.previewPrestageRequestSeq
        }

        let workItem = DispatchWorkItem {
            let isStillCurrentPreview: () -> Bool = {
                let latestPreviewSeq = Self.previewPrestageSeqLock.withLock { Self.previewPrestageRequestSeq }
                guard latestPreviewSeq == myPreviewSeq else { return false }
                return PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.playbackGeneration == capturedGen && !PlaybackStateStore.shared.isStagingCloudTrack
                }
            }
            for tr in headCandidates {
                guard isStillCurrentPreview() else { return }
                Self.prewarmSingleCatalogTrackInRAM(tr)
            }
        }
        Self.previewPrestageSeqLock.withLock {
            if Self.previewPrestageRequestSeq == myPreviewSeq {
                Self.pendingPreviewPrestageWorkItem = workItem
            }
        }
        Self.prestageWorkerQueue.async(execute: workItem)
    }

    /// Pre-warms read-only catalog storefront availability (`1508103497 -> 1508140810`), ISRC alternates (`6829729404 -> 6817136270`),
    /// localized cross-script titles (`名前を呼ぶよ <-> Namae wo Yobuyo`), and durations in RAM for upcoming queue tracks.
    /// Strictly ZERO `/v1/me/library` or `/v1/me/library/playlists` calls!
    public func prestageUpcomingCloudTracks(
        fromIndex: Int,
        count: Int = 4,
        expectedGeneration: UInt64? = nil,
        immediate: Bool = false
    ) {
        let (initialSlice, effectiveWindow, targetGen): ([TrackInfo], Int, UInt64) = PlaybackStateStore.shared.withLock {
            let gen = expectedGeneration ?? PlaybackStateStore.shared.playbackGeneration
            let q = PlaybackStateStore.shared.activeCustomQueue
            let curQueueName = PlaybackStateStore.shared.activeCustomQueueName ?? ""
            let isSearchOrCurator = (PlaybackStateStore.shared.activeSearchQuery != nil)
                || (PlaybackStateStore.shared.activeCuratorPrompt != nil)
                || (curQueueName == "Результаты поиска" || curQueueName == "Search Results" || curQueueName.hasPrefix("Поиск: ") || curQueueName.hasPrefix("Search: "))
            let maxWindow = isSearchOrCurator ? 3 : 4
            let win = max(1, min(count, maxWindow))
            guard fromIndex >= 0 && fromIndex < q.count else { return ([], win, gen) }
            let end = min(q.count, fromIndex + win)
            let needWarmup = Array(q[fromIndex..<end]).filter { tr in
                guard tr.isLocal != true else { return false }
                if let nid = tr.numericId, nid > 0, nid < 10_000_000 {
                    return false
                }
                return true
            }
            return (needWarmup, win, gen)
        }
        guard !initialSlice.isEmpty else { return }

        let mySeq: UInt64 = Self.prestageSeqLock.withLock {
            Self.pendingUpcomingPrestageWorkItem?.cancel()
            Self.pendingUpcomingPrestageWorkItem = nil
            Self.prestageRequestSeq &+= 1
            return Self.prestageRequestSeq
        }
        guard !isTestingEnvironment else { return }
        let initialDelay: TimeInterval = immediate ? 0.12 : 1.0

        let workItem = DispatchWorkItem {
            let isStillActive: () -> Bool = {
                let latestSeq = Self.prestageSeqLock.withLock { Self.prestageRequestSeq }
                guard latestSeq == mySeq else { return false }
                return PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.playbackGeneration == targetGen
                        && PlaybackStateStore.shared.isCustomQueuePlayback
                        && !PlaybackStateStore.shared.isUserPaused
                }
            }
            guard isStillActive() else { return }

            let slice: [TrackInfo] = PlaybackStateStore.shared.withLock {
                guard PlaybackStateStore.shared.playbackGeneration == targetGen else { return [] }
                let q = PlaybackStateStore.shared.activeCustomQueue
                guard fromIndex >= 0 && fromIndex < q.count else { return [] }
                let end = min(q.count, fromIndex + effectiveWindow)
                return Array(q[fromIndex..<end]).filter { tr in
                    guard tr.isLocal != true else { return false }
                    if let nid = tr.numericId, nid > 0, nid < 10_000_000 {
                        return false
                    }
                    return true
                }
            }
            guard !slice.isEmpty else { return }

            var updatedAny = false
            for t in slice {
                guard isStillActive() else { return }
                guard let warmed = Self.prewarmSingleCatalogTrackInRAM(t) else { continue }

                PlaybackStateStore.shared.withLock {
                    guard PlaybackStateStore.shared.playbackGeneration == targetGen else { return }
                    for i in 0..<PlaybackStateStore.shared.activeCustomQueue.count {
                        let qt = PlaybackStateStore.shared.activeCustomQueue[i]
                        if qt.id == t.id || (qt.name == t.name && qt.artist == t.artist) {
                            if PlaybackStateStore.shared.activeCustomQueue[i].catalogId != warmed.validCid {
                                PlaybackStateStore.shared.activeCustomQueue[i].catalogId = warmed.validCid
                                updatedAny = true
                            }
                            if let durSec = warmed.durationSeconds, durSec > 0,
                               PlaybackStateStore.shared.activeCustomQueue[i].duration <= 0 {
                                PlaybackStateStore.shared.activeCustomQueue[i].duration = durSec
                                updatedAny = true
                            }
                        }
                    }
                    if updatedAny {
                        let curIdx = PlaybackStateStore.shared.activeCustomQueueIndex
                        let q = PlaybackStateStore.shared.activeCustomQueue
                        if curIdx + 1 < q.count {
                            PlaybackStateStore.shared.latestUpcomingTracks = Array(q[(curIdx + 1)...])
                        }
                    }
                }
            }
            if updatedAny {
                PlaybackStateStore.shared.invalidateQueueCache()
            }
        }
        Self.prestageSeqLock.withLock {
            if Self.prestageRequestSeq == mySeq {
                Self.pendingUpcomingPrestageWorkItem = workItem
            }
        }
        Self.prestageWorkerQueue.asyncAfter(deadline: .now() + initialDelay, execute: workItem)
    }

    @discardableResult
    private static func prewarmSingleCatalogTrackInRAM(_ track: TrackInfo) -> (validCid: String, durationSeconds: Double?)? {
        let userSf = MusicKitManager.shared.getUserStorefront().trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var cid = MusicKitManager.extractNumericCatalogId(from: track)
        var urlHasForeignSf = false
        if let u = track.url, let comp = URLComponents(string: u) {
            let parts = comp.path.split(separator: "/").map(String.init)
            if let urlSf = parts.first?.lowercased(), urlSf.count == 2, !userSf.isEmpty, urlSf != userSf {
                urlHasForeignSf = true
            }
        }
        if (cid == nil || urlHasForeignSf) && !track.name.isEmpty,
           let sfId = MusicKitManager.shared.resolveCatalogSongIdInUserStorefrontSync(name: track.name, artist: track.artist) {
            cid = sfId
        }
        guard let rawCid = cid else { return nil }

        var validCid = rawCid
        if let prefAlt = MusicKitManager.shared.preferredAlternateCatalogSong(for: rawCid) {
            validCid = prefAlt.id
            MusicKitManager.shared.appendCachedTitleVariant(catalogId: rawCid, name: prefAlt.name, artist: prefAlt.artist)
        }

        var info = MusicKitManager.shared.inspectCatalogSongDirectCloudEligibilitySync(catalogId: validCid)
        if info?.durationSeconds == nil || MusicKitManager.shared.isUnstageableCatalogId(validCid) {
            if let sfAlt = MusicKitManager.shared.resolveAlternateCatalogSongsSync(
                catalogId: rawCid,
                name: track.name,
                artist: track.artist,
                excludingIds: [rawCid, validCid]
            ).first {
                MusicKitManager.shared.recordPreferredAlternateCatalogSong(for: rawCid, alternate: sfAlt)
                MusicKitManager.shared.appendCachedTitleVariant(catalogId: rawCid, name: sfAlt.name, artist: sfAlt.artist)
                MusicKitManager.shared.appendCachedTitleVariant(catalogId: sfAlt.id, name: sfAlt.name, artist: sfAlt.artist)
                validCid = sfAlt.id
                info = MusicKitManager.shared.inspectCatalogSongDirectCloudEligibilitySync(catalogId: sfAlt.id)
            }
        }
        _ = MusicKitManager.shared.resolveCatalogSongTitleVariantsSync(catalogId: validCid)
        return (validCid: validCid, durationSeconds: info?.durationSeconds)
    }
}
