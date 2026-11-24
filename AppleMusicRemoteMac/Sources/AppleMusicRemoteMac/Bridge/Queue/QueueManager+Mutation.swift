//
//  QueueManager+Mutation.swift
//  AppleMusicRemoteMac
//
//  Play Next / Play Later queue mutation preserving full playlist history and Shuffle-Off ordering.
//

import Foundation
import ScriptingBridge

extension QueueManager {
    private func syncQueueSlicesAndReindexUnlocked() {
        for i in 0..<PlaybackStateStore.shared.activeCustomQueue.count {
            PlaybackStateStore.shared.activeCustomQueue[i].index = i + 1
        }
        for i in 0..<PlaybackStateStore.shared.originalCustomQueue.count {
            PlaybackStateStore.shared.originalCustomQueue[i].index = i + 1
        }
        let curIdx = PlaybackStateStore.shared.activeCustomQueueIndex
        let q = PlaybackStateStore.shared.activeCustomQueue
        if curIdx + 1 < q.count {
            PlaybackStateStore.shared.latestUpcomingTracks = Array(q[(curIdx + 1)...])
        } else {
            PlaybackStateStore.shared.latestUpcomingTracks = []
        }
        if curIdx > 0 && curIdx <= q.count {
            PlaybackStateStore.shared.latestHistoryTracks = Array(q[0..<curIdx].reversed())
        } else {
            PlaybackStateStore.shared.latestHistoryTracks = []
        }
        PlaybackStateStore.shared.playbackQueueCache = nil
    }

    private func insertIntoOriginalCustomQueueUnlocked(
        tracks newTracks: [TrackInfo],
        playNext: Bool,
        anchorTrack: TrackInfo?
    ) {
        if PlaybackStateStore.shared.originalCustomQueue.isEmpty {
            PlaybackStateStore.shared.originalCustomQueue = PlaybackStateStore.shared.activeCustomQueue
            return
        }
        if playNext, let anchor = anchorTrack {
            let orig = PlaybackStateStore.shared.originalCustomQueue
            if let anchorIdx = orig.firstIndex(where: { !anchor.id.isEmpty && $0.id == anchor.id })
                ?? orig.firstIndex(where: { !anchor.name.isEmpty && $0.name == anchor.name && $0.artist == anchor.artist }) {
                let insertPos = min(orig.count, anchorIdx + 1)
                PlaybackStateStore.shared.originalCustomQueue.insert(contentsOf: newTracks, at: insertPos)
                return
            }
        }
        PlaybackStateStore.shared.originalCustomQueue.append(contentsOf: newTracks)
    }

    private func buildCustomQueueFromNativePlaylistSnapshot(
        _ q: PlaybackQueueInfo,
        currentTrack: TrackInfo?
    ) -> (activeQueue: [TrackInfo], activeIndex: Int, unshuffledBase: [TrackInfo]) {
        if !q.tracks.isEmpty {
            let clampedIdx = min(max(0, q.currentIndex), q.tracks.count - 1)
            if !q.shuffle {
                return (q.tracks, clampedIdx, q.tracks)
            }
            // In native shuffle mode, construct [history (oldest..newest)] + [currentTrack] + [upcoming]
            let historyChronological = Array(q.historyTracks.reversed())
            let cur = currentTrack ?? q.tracks[clampedIdx]
            let combined = historyChronological + [cur] + q.upcomingTracks
            return (combined, historyChronological.count, q.tracks)
        }
        var fallbackQueue = [TrackInfo]()
        if let cur = currentTrack {
            fallbackQueue.append(cur)
        }
        if !q.upcomingTracks.isEmpty {
            fallbackQueue.append(contentsOf: q.upcomingTracks)
        }
        return (fallbackQueue, 0, fallbackQueue)
    }

    // MARK: - Enqueue Operations

    public func enqueueTrack(_ track: TrackInfo, playNext: Bool) async -> Bool {
        let (hasCustom, genBefore) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty,
                PlaybackStateStore.shared.playbackGeneration
            )
        }

        if !hasCustom {
            let q = await getPlaybackQueue()
            let curTrack = PlayerStatusEngine.shared.getPlayerStatus().track

            var shouldPlayFirst = false
            let res = PlaybackStateStore.shared.withLock { () -> Bool in
                if PlaybackStateStore.shared.playbackGeneration != genBefore {
                    guard PlaybackStateStore.shared.isCustomQueuePlayback &&
                          !PlaybackStateStore.shared.activeCustomQueue.isEmpty else {
                        return false
                    }
                    let curIdx = PlaybackStateStore.shared.activeCustomQueueIndex
                    let anchor = (curIdx >= 0 && curIdx < PlaybackStateStore.shared.activeCustomQueue.count)
                        ? PlaybackStateStore.shared.activeCustomQueue[curIdx]
                        : nil
                    PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                    if playNext {
                        let insertIdx = min(PlaybackStateStore.shared.activeCustomQueue.count, curIdx + 1)
                        PlaybackStateStore.shared.activeCustomQueue.insert(track, at: insertIdx)
                    } else {
                        PlaybackStateStore.shared.activeCustomQueue.append(track)
                    }
                    insertIntoOriginalCustomQueueUnlocked(tracks: [track], playNext: playNext, anchorTrack: anchor)
                    syncQueueSlicesAndReindexUnlocked()
                    return true
                }

                let converted = buildCustomQueueFromNativePlaylistSnapshot(q, currentTrack: curTrack)
                PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                PlaybackStateStore.shared.activeSearchQuery = nil
                PlaybackStateStore.shared.isFetchingNextSearchPage = false
                PlaybackStateStore.shared.activeCuratorPrompt = nil
                PlaybackStateStore.shared.isFetchingNextCuratorPage = false
                PlaybackStateStore.shared.lastCloudPlayTime = Date()
                if converted.activeQueue.isEmpty {
                    PlaybackStateStore.shared.activeCustomQueue = [track]
                    PlaybackStateStore.shared.originalCustomQueue = [track]
                    PlaybackStateStore.shared.activeCustomQueueIndex = 0
                    PlaybackStateStore.shared.isCustomQueuePlayback = true
                    PlaybackStateStore.shared.activeCustomQueueName = "Очередь"
                    syncQueueSlicesAndReindexUnlocked()
                    shouldPlayFirst = true
                    return true
                }

                let baseIdx = converted.activeIndex
                let anchor = (baseIdx >= 0 && baseIdx < converted.activeQueue.count) ? converted.activeQueue[baseIdx] : curTrack
                PlaybackStateStore.shared.activeCustomQueue = converted.activeQueue
                PlaybackStateStore.shared.originalCustomQueue = converted.unshuffledBase
                PlaybackStateStore.shared.activeCustomQueueIndex = baseIdx
                PlaybackStateStore.shared.isCustomQueuePlayback = true
                PlaybackStateStore.shared.isShuffleQueueActive = q.shuffle
                PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                PlaybackStateStore.shared.activeCustomQueueName = q.playlist.isEmpty ? "Очередь" : q.playlist

                if playNext {
                    let insertIdx = min(PlaybackStateStore.shared.activeCustomQueue.count, baseIdx + 1)
                    PlaybackStateStore.shared.activeCustomQueue.insert(track, at: insertIdx)
                } else {
                    PlaybackStateStore.shared.activeCustomQueue.append(track)
                }
                insertIntoOriginalCustomQueueUnlocked(tracks: [track], playNext: playNext, anchorTrack: anchor)
                syncQueueSlicesAndReindexUnlocked()
                return true
            }
            PlaybackStateStore.shared.invalidateQueueCache()
            if res {
                startQueueMonitoring()
                let nextIdx = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.activeCustomQueueIndex + 1 }
                PlaybackRouter.shared.prestageUpcomingCloudTracks(fromIndex: nextIdx, count: 5, immediate: true)
            }
            if shouldPlayFirst {
                return playQueueIndexUnlocked(0)
            }
            return res
        }

        let res = PlaybackStateStore.shared.withLock { () -> Bool in
            let curIdx = PlaybackStateStore.shared.activeCustomQueueIndex
            let anchor = (curIdx >= 0 && curIdx < PlaybackStateStore.shared.activeCustomQueue.count)
                ? PlaybackStateStore.shared.activeCustomQueue[curIdx]
                : nil
            if PlaybackStateStore.shared.originalCustomQueue.isEmpty {
                PlaybackStateStore.shared.originalCustomQueue = PlaybackStateStore.shared.activeCustomQueue
            }
            PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
            if playNext {
                let insertIdx = min(PlaybackStateStore.shared.activeCustomQueue.count, curIdx + 1)
                PlaybackStateStore.shared.activeCustomQueue.insert(track, at: insertIdx)
            } else {
                PlaybackStateStore.shared.activeCustomQueue.append(track)
            }
            insertIntoOriginalCustomQueueUnlocked(tracks: [track], playNext: playNext, anchorTrack: anchor)
            syncQueueSlicesAndReindexUnlocked()
            return true
        }
        PlaybackStateStore.shared.invalidateQueueCache()
        if res {
            let nextIdx = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.activeCustomQueueIndex + 1 }
            PlaybackRouter.shared.prestageUpcomingCloudTracks(fromIndex: nextIdx, count: 5, immediate: true)
        }
        return res
    }

    public func enqueueTracks(_ tracks: [TrackInfo], playNext: Bool) async -> Bool {
        guard !tracks.isEmpty else { return false }
        let (hasCustom, genBefore) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty,
                PlaybackStateStore.shared.playbackGeneration
            )
        }

        if !hasCustom {
            let q = await getPlaybackQueue()
            let curTrack = PlayerStatusEngine.shared.getPlayerStatus().track

            var shouldPlayCustomTracks = false
            let res = PlaybackStateStore.shared.withLock { () -> Bool in
                if PlaybackStateStore.shared.playbackGeneration != genBefore {
                    guard PlaybackStateStore.shared.isCustomQueuePlayback &&
                          !PlaybackStateStore.shared.activeCustomQueue.isEmpty else {
                        return false
                    }
                    let curIdx = PlaybackStateStore.shared.activeCustomQueueIndex
                    let anchor = (curIdx >= 0 && curIdx < PlaybackStateStore.shared.activeCustomQueue.count)
                        ? PlaybackStateStore.shared.activeCustomQueue[curIdx]
                        : nil
                    PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                    if playNext {
                        let insertIdx = min(PlaybackStateStore.shared.activeCustomQueue.count, curIdx + 1)
                        PlaybackStateStore.shared.activeCustomQueue.insert(contentsOf: tracks, at: insertIdx)
                    } else {
                        PlaybackStateStore.shared.activeCustomQueue.append(contentsOf: tracks)
                    }
                    insertIntoOriginalCustomQueueUnlocked(tracks: tracks, playNext: playNext, anchorTrack: anchor)
                    syncQueueSlicesAndReindexUnlocked()
                    return true
                }

                let converted = buildCustomQueueFromNativePlaylistSnapshot(q, currentTrack: curTrack)
                if converted.activeQueue.isEmpty {
                    shouldPlayCustomTracks = true
                    return true
                }

                let baseIdx = converted.activeIndex
                let anchor = (baseIdx >= 0 && baseIdx < converted.activeQueue.count) ? converted.activeQueue[baseIdx] : curTrack
                PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                PlaybackStateStore.shared.activeSearchQuery = nil
                PlaybackStateStore.shared.isFetchingNextSearchPage = false
                PlaybackStateStore.shared.activeCuratorPrompt = nil
                PlaybackStateStore.shared.isFetchingNextCuratorPage = false
                PlaybackStateStore.shared.lastCloudPlayTime = Date()
                PlaybackStateStore.shared.activeCustomQueue = converted.activeQueue
                PlaybackStateStore.shared.originalCustomQueue = converted.unshuffledBase
                PlaybackStateStore.shared.activeCustomQueueIndex = baseIdx
                PlaybackStateStore.shared.isCustomQueuePlayback = true
                PlaybackStateStore.shared.isShuffleQueueActive = q.shuffle
                PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                PlaybackStateStore.shared.activeCustomQueueName = q.playlist.isEmpty ? "Очередь" : q.playlist

                if playNext {
                    let insertIdx = min(PlaybackStateStore.shared.activeCustomQueue.count, baseIdx + 1)
                    PlaybackStateStore.shared.activeCustomQueue.insert(contentsOf: tracks, at: insertIdx)
                } else {
                    PlaybackStateStore.shared.activeCustomQueue.append(contentsOf: tracks)
                }
                insertIntoOriginalCustomQueueUnlocked(tracks: tracks, playNext: playNext, anchorTrack: anchor)
                syncQueueSlicesAndReindexUnlocked()
                return true
            }
            if shouldPlayCustomTracks {
                return PlaybackRouter.shared.playCustomTracksUnlocked(tracks, startIndex: 0, shuffle: false, queueName: "Очередь")
            }
            PlaybackStateStore.shared.invalidateQueueCache()
            if res {
                startQueueMonitoring()
                let nextIdx = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.activeCustomQueueIndex + 1 }
                PlaybackRouter.shared.prestageUpcomingCloudTracks(fromIndex: nextIdx, count: 6, immediate: true)
            }
            return res
        }

        let res = PlaybackStateStore.shared.withLock { () -> Bool in
            let curIdx = PlaybackStateStore.shared.activeCustomQueueIndex
            let anchor = (curIdx >= 0 && curIdx < PlaybackStateStore.shared.activeCustomQueue.count)
                ? PlaybackStateStore.shared.activeCustomQueue[curIdx]
                : nil
            if PlaybackStateStore.shared.originalCustomQueue.isEmpty {
                PlaybackStateStore.shared.originalCustomQueue = PlaybackStateStore.shared.activeCustomQueue
            }
            PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
            if playNext {
                let insertIdx = min(PlaybackStateStore.shared.activeCustomQueue.count, curIdx + 1)
                PlaybackStateStore.shared.activeCustomQueue.insert(contentsOf: tracks, at: insertIdx)
            } else {
                PlaybackStateStore.shared.activeCustomQueue.append(contentsOf: tracks)
            }
            insertIntoOriginalCustomQueueUnlocked(tracks: tracks, playNext: playNext, anchorTrack: anchor)
            syncQueueSlicesAndReindexUnlocked()
            return true
        }
        PlaybackStateStore.shared.invalidateQueueCache()
        if res {
            let nextIdx = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.activeCustomQueueIndex + 1 }
            PlaybackRouter.shared.prestageUpcomingCloudTracks(fromIndex: nextIdx, count: 6, immediate: true)
        }
        return res
    }

    public func removeQueueTrack(at index: Int) async -> Bool {
        let (hasCustom, genBefore) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty,
                PlaybackStateStore.shared.playbackGeneration
            )
        }

        if hasCustom {
            let res = PlaybackStateStore.shared.withLock { () -> Bool in
                let targetIdx = PlaybackStateStore.shared.activeCustomQueueIndex + 1 + index
                guard targetIdx > PlaybackStateStore.shared.activeCustomQueueIndex && targetIdx < PlaybackStateStore.shared.activeCustomQueue.count else { return false }
                PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                let removed = PlaybackStateStore.shared.activeCustomQueue.remove(at: targetIdx)
                if let origIdx = PlaybackStateStore.shared.originalCustomQueue.firstIndex(where: { $0.id == removed.id && $0.name == removed.name }) {
                    PlaybackStateStore.shared.originalCustomQueue.remove(at: origIdx)
                }
                syncQueueSlicesAndReindexUnlocked()
                return true
            }
            PlaybackStateStore.shared.invalidateQueueCache()
            if res {
                let nextIdx = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.activeCustomQueueIndex + 1 }
                PlaybackRouter.shared.prestageUpcomingCloudTracks(fromIndex: nextIdx, count: 4, immediate: true)
            }
            return res
        }

        let q = await getPlaybackQueue()
        guard index >= 0 else { return false }

        let res = PlaybackStateStore.shared.withLock { () -> Bool in
            guard PlaybackStateStore.shared.playbackGeneration == genBefore else {
                return false
            }
            guard index < q.upcomingTracks.count else { return false }
            PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
            PlaybackStateStore.shared.activeSearchQuery = nil
            PlaybackStateStore.shared.isFetchingNextSearchPage = false
            PlaybackStateStore.shared.activeCuratorPrompt = nil
            PlaybackStateStore.shared.isFetchingNextCuratorPage = false
            PlaybackStateStore.shared.lastCloudPlayTime = Date()
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
            PlaybackStateStore.shared.activeCustomQueue = q.tracks
            PlaybackStateStore.shared.activeCustomQueueIndex = q.currentIndex
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueueName = q.playlist
            let targetIdx = PlaybackStateStore.shared.activeCustomQueueIndex + 1 + index
            if targetIdx > PlaybackStateStore.shared.activeCustomQueueIndex && targetIdx < PlaybackStateStore.shared.activeCustomQueue.count {
                PlaybackStateStore.shared.activeCustomQueue.remove(at: targetIdx)
                PlaybackStateStore.shared.originalCustomQueue = PlaybackStateStore.shared.activeCustomQueue
                syncQueueSlicesAndReindexUnlocked()
                return true
            }
            return false
        }
        PlaybackStateStore.shared.invalidateQueueCache()
        if res {
            startQueueMonitoring()
        }
        return res
    }

    public func clearUpcomingQueue() async -> Bool {
        PlaybackStateStore.shared.invalidateQueueCache()
        let (hasCustom, genBefore) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty,
                PlaybackStateStore.shared.playbackGeneration
            )
        }

        if hasCustom {
            let res = PlaybackStateStore.shared.withLock { () -> Bool in
                PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                PlaybackStateStore.shared.activeSearchQuery = nil
                PlaybackStateStore.shared.isFetchingNextSearchPage = false
                PlaybackStateStore.shared.activeCuratorPrompt = nil
                PlaybackStateStore.shared.isFetchingNextCuratorPage = false
                if PlaybackStateStore.shared.activeCustomQueueIndex + 1 < PlaybackStateStore.shared.activeCustomQueue.count {
                    PlaybackStateStore.shared.activeCustomQueue.removeSubrange((PlaybackStateStore.shared.activeCustomQueueIndex + 1)...)
                }
                PlaybackStateStore.shared.originalCustomQueue = PlaybackStateStore.shared.activeCustomQueue
                syncQueueSlicesAndReindexUnlocked()
                return true
            }
            PlaybackStateStore.shared.invalidateQueueCache()
            if res {
                let nextIdx = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.activeCustomQueueIndex + 1 }
                PlaybackRouter.shared.prestageUpcomingCloudTracks(fromIndex: nextIdx, count: 4, immediate: true)
            }
            return res
        }

        let q = await getPlaybackQueue()
        let curTrack = PlayerStatusEngine.shared.getPlayerStatus().track
        let res = PlaybackStateStore.shared.withLock { () -> Bool in
            guard PlaybackStateStore.shared.playbackGeneration == genBefore else {
                return false
            }
            PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
            PlaybackStateStore.shared.activeSearchQuery = nil
            PlaybackStateStore.shared.isFetchingNextSearchPage = false
            PlaybackStateStore.shared.activeCuratorPrompt = nil
            PlaybackStateStore.shared.isFetchingNextCuratorPage = false
            PlaybackStateStore.shared.lastCloudPlayTime = Date()
            PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
            if !q.tracks.isEmpty && q.currentIndex >= 0 && q.currentIndex < q.tracks.count {
                let historyAndCurrent = Array(q.tracks[0...q.currentIndex])
                PlaybackStateStore.shared.activeCustomQueue = historyAndCurrent
                PlaybackStateStore.shared.activeCustomQueueIndex = q.currentIndex
            } else if let cur = curTrack {
                PlaybackStateStore.shared.activeCustomQueue = [cur]
                PlaybackStateStore.shared.activeCustomQueueIndex = 0
            } else {
                PlaybackStateStore.shared.activeCustomQueue = []
                PlaybackStateStore.shared.activeCustomQueueIndex = 0
            }
            PlaybackStateStore.shared.originalCustomQueue = PlaybackStateStore.shared.activeCustomQueue
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueueName = q.playlist.isEmpty ? "Очередь" : q.playlist
            syncQueueSlicesAndReindexUnlocked()
            return true
        }
        PlaybackStateStore.shared.invalidateQueueCache()
        if res {
            startQueueMonitoring()
        }
        return res
    }
}
