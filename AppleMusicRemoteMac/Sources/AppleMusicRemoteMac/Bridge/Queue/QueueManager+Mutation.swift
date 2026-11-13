//
//  QueueManager+Mutation.swift
//  AppleMusicRemoteMac
//

import Foundation
import ScriptingBridge

extension QueueManager {
    private func syncQueueSlicesAndReindexUnlocked() {
        for i in 0..<PlaybackStateStore.shared.activeCustomQueue.count {
            PlaybackStateStore.shared.activeCustomQueue[i].index = i + 1
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
                    PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                    if playNext {
                        let insertIdx = min(PlaybackStateStore.shared.activeCustomQueue.count, PlaybackStateStore.shared.activeCustomQueueIndex + 1)
                        PlaybackStateStore.shared.activeCustomQueue.insert(track, at: insertIdx)
                    } else {
                        PlaybackStateStore.shared.activeCustomQueue.append(track)
                    }
                    PlaybackStateStore.shared.originalCustomQueue.append(track)
                    syncQueueSlicesAndReindexUnlocked()
                    return true
                }

                var queue = [TrackInfo]()
                if let cur = curTrack {
                    queue.append(cur)
                } else if q.currentIndex < q.tracks.count {
                    queue.append(q.tracks[q.currentIndex])
                }
                if !q.upcomingTracks.isEmpty {
                    queue.append(contentsOf: q.upcomingTracks)
                }

                PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                PlaybackStateStore.shared.activeSearchQuery = nil
                PlaybackStateStore.shared.isFetchingNextSearchPage = false
                PlaybackStateStore.shared.activeCuratorPrompt = nil
                PlaybackStateStore.shared.isFetchingNextCuratorPage = false
                PlaybackStateStore.shared.lastCloudPlayTime = Date()
                if queue.isEmpty {
                    PlaybackStateStore.shared.activeCustomQueue = [track]
                    PlaybackStateStore.shared.originalCustomQueue = [track]
                    PlaybackStateStore.shared.activeCustomQueueIndex = 0
                    PlaybackStateStore.shared.isCustomQueuePlayback = true
                    PlaybackStateStore.shared.activeCustomQueueName = "Очередь"
                    syncQueueSlicesAndReindexUnlocked()
                    shouldPlayFirst = true
                    return true
                }

                PlaybackStateStore.shared.activeCustomQueue = queue
                PlaybackStateStore.shared.activeCustomQueueIndex = 0
                PlaybackStateStore.shared.isCustomQueuePlayback = true
                PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                PlaybackStateStore.shared.activeCustomQueueName = q.playlist.isEmpty ? "Очередь" : q.playlist

                if playNext {
                    PlaybackStateStore.shared.activeCustomQueue.insert(track, at: 1)
                } else {
                    PlaybackStateStore.shared.activeCustomQueue.append(track)
                }
                PlaybackStateStore.shared.originalCustomQueue = PlaybackStateStore.shared.activeCustomQueue
                syncQueueSlicesAndReindexUnlocked()
                return true
            }
            PlaybackStateStore.shared.invalidateQueueCache()
            if res {
                startQueueMonitoring()
            }
            if shouldPlayFirst {
                return playQueueIndexUnlocked(0)
            }
            return res
        }

        let res = PlaybackStateStore.shared.withLock { () -> Bool in
            PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
            if playNext {
                let insertIdx = min(PlaybackStateStore.shared.activeCustomQueue.count, PlaybackStateStore.shared.activeCustomQueueIndex + 1)
                PlaybackStateStore.shared.activeCustomQueue.insert(track, at: insertIdx)
            } else {
                PlaybackStateStore.shared.activeCustomQueue.append(track)
            }
            PlaybackStateStore.shared.originalCustomQueue.append(track)
            syncQueueSlicesAndReindexUnlocked()
            return true
        }
        PlaybackStateStore.shared.invalidateQueueCache()
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
                    PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                    if playNext {
                        let insertIdx = min(PlaybackStateStore.shared.activeCustomQueue.count, PlaybackStateStore.shared.activeCustomQueueIndex + 1)
                        PlaybackStateStore.shared.activeCustomQueue.insert(contentsOf: tracks, at: insertIdx)
                    } else {
                        PlaybackStateStore.shared.activeCustomQueue.append(contentsOf: tracks)
                    }
                    PlaybackStateStore.shared.originalCustomQueue.append(contentsOf: tracks)
                    syncQueueSlicesAndReindexUnlocked()
                    return true
                }

                var queue = [TrackInfo]()
                if let cur = curTrack {
                    queue.append(cur)
                } else if q.currentIndex < q.tracks.count {
                    queue.append(q.tracks[q.currentIndex])
                }
                if !q.upcomingTracks.isEmpty {
                    queue.append(contentsOf: q.upcomingTracks)
                }

                if queue.isEmpty {
                    shouldPlayCustomTracks = true
                    return true
                }

                PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                PlaybackStateStore.shared.activeSearchQuery = nil
                PlaybackStateStore.shared.isFetchingNextSearchPage = false
                PlaybackStateStore.shared.activeCuratorPrompt = nil
                PlaybackStateStore.shared.isFetchingNextCuratorPage = false
                PlaybackStateStore.shared.lastCloudPlayTime = Date()
                PlaybackStateStore.shared.activeCustomQueue = queue
                PlaybackStateStore.shared.activeCustomQueueIndex = 0
                PlaybackStateStore.shared.isCustomQueuePlayback = true
                PlaybackStateStore.shared.currentTrackPlaybackConfirmed = true
                PlaybackStateStore.shared.activeCustomQueueName = q.playlist.isEmpty ? "Очередь" : q.playlist

                if playNext {
                    PlaybackStateStore.shared.activeCustomQueue.insert(contentsOf: tracks, at: 1)
                } else {
                    PlaybackStateStore.shared.activeCustomQueue.append(contentsOf: tracks)
                }
                PlaybackStateStore.shared.originalCustomQueue = PlaybackStateStore.shared.activeCustomQueue
                syncQueueSlicesAndReindexUnlocked()
                return true
            }
            if shouldPlayCustomTracks {
                return PlaybackRouter.shared.playCustomTracksUnlocked(tracks, startIndex: 0, shuffle: false, queueName: "Очередь")
            }
            PlaybackStateStore.shared.invalidateQueueCache()
            if res {
                startQueueMonitoring()
            }
            return res
        }

        let res = PlaybackStateStore.shared.withLock { () -> Bool in
            PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
            if playNext {
                let insertIdx = min(PlaybackStateStore.shared.activeCustomQueue.count, PlaybackStateStore.shared.activeCustomQueueIndex + 1)
                PlaybackStateStore.shared.activeCustomQueue.insert(contentsOf: tracks, at: insertIdx)
            } else {
                PlaybackStateStore.shared.activeCustomQueue.append(contentsOf: tracks)
            }
            PlaybackStateStore.shared.originalCustomQueue.append(contentsOf: tracks)
            syncQueueSlicesAndReindexUnlocked()
            return true
        }
        PlaybackStateStore.shared.invalidateQueueCache()
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
            if let cur = curTrack {
                PlaybackStateStore.shared.activeCustomQueue = [cur]
            } else if q.currentIndex < q.tracks.count {
                PlaybackStateStore.shared.activeCustomQueue = [q.tracks[q.currentIndex]]
            } else {
                PlaybackStateStore.shared.activeCustomQueue = []
            }
            PlaybackStateStore.shared.originalCustomQueue = PlaybackStateStore.shared.activeCustomQueue
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueueName = "Очередь"
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
