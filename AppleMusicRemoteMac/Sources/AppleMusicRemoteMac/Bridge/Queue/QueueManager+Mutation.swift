//
//  QueueManager+Mutation.swift
//  AppleMusicRemoteMac
//

import Foundation
import ScriptingBridge

extension QueueManager {
    // MARK: - Enqueue Operations

    public func enqueueTrack(_ track: TrackInfo, playNext: Bool) async -> Bool {
        let hasCustom = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty
        }

        if !hasCustom {
            let q = await getPlaybackQueue()
            let curTrack = PlayerStatusEngine.shared.getPlayerStatus().track

            return PlaybackStateStore.shared.withLock {
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
                    PlaybackStateStore.shared.activeCustomQueue = [track]
                    PlaybackStateStore.shared.activeCustomQueueIndex = 0
                    PlaybackStateStore.shared.isCustomQueuePlayback = true
                    PlaybackStateStore.shared.activeCustomQueueName = "Очередь"
                    return playQueueIndexUnlocked(0)
                }

                PlaybackStateStore.shared.activeCustomQueue = queue
                PlaybackStateStore.shared.activeCustomQueueIndex = 0
                PlaybackStateStore.shared.isCustomQueuePlayback = true
                PlaybackStateStore.shared.activeCustomQueueName = q.playlist.isEmpty ? "Очередь" : q.playlist

                if playNext {
                    PlaybackStateStore.shared.activeCustomQueue.insert(track, at: 1)
                } else {
                    PlaybackStateStore.shared.activeCustomQueue.append(track)
                }
                return true
            }
        }

        return PlaybackStateStore.shared.withLock {
            if playNext {
                let insertIdx = min(PlaybackStateStore.shared.activeCustomQueue.count, PlaybackStateStore.shared.activeCustomQueueIndex + 1)
                PlaybackStateStore.shared.activeCustomQueue.insert(track, at: insertIdx)
            } else {
                PlaybackStateStore.shared.activeCustomQueue.append(track)
            }
            return true
        }
    }

    public func enqueueTracks(_ tracks: [TrackInfo], playNext: Bool) async -> Bool {
        guard !tracks.isEmpty else { return false }
        let hasCustom = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty
        }

        if !hasCustom {
            let q = await getPlaybackQueue()
            let curTrack = PlayerStatusEngine.shared.getPlayerStatus().track

            return PlaybackStateStore.shared.withLock {
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
                    return PlaybackRouter.shared.playCustomTracksUnlocked(tracks, startIndex: 0, shuffle: false, queueName: "Очередь")
                }

                PlaybackStateStore.shared.activeCustomQueue = queue
                PlaybackStateStore.shared.activeCustomQueueIndex = 0
                PlaybackStateStore.shared.isCustomQueuePlayback = true
                PlaybackStateStore.shared.activeCustomQueueName = q.playlist.isEmpty ? "Очередь" : q.playlist

                if playNext {
                    PlaybackStateStore.shared.activeCustomQueue.insert(contentsOf: tracks, at: 1)
                } else {
                    PlaybackStateStore.shared.activeCustomQueue.append(contentsOf: tracks)
                }
                return true
            }
        }

        return PlaybackStateStore.shared.withLock {
            if playNext {
                let insertIdx = min(PlaybackStateStore.shared.activeCustomQueue.count, PlaybackStateStore.shared.activeCustomQueueIndex + 1)
                PlaybackStateStore.shared.activeCustomQueue.insert(contentsOf: tracks, at: insertIdx)
            } else {
                PlaybackStateStore.shared.activeCustomQueue.append(contentsOf: tracks)
            }
            return true
        }
    }

    public func removeQueueTrack(at index: Int) async -> Bool {
        let hasCustom = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty
        }

        if hasCustom {
            return PlaybackStateStore.shared.withLock {
                let targetIdx = PlaybackStateStore.shared.activeCustomQueueIndex + 1 + index
                guard targetIdx >= 0 && targetIdx < PlaybackStateStore.shared.activeCustomQueue.count else { return false }
                PlaybackStateStore.shared.activeCustomQueue.remove(at: targetIdx)
                return true
            }
        }

        if let app = MusicAppProvider.shared.getMusicApp(), let pName = app.currentPlaylist?.value(forKey: "name") as? String, pName == "Очередь AMR" {
            let curIdx = (app.currentTrack?.value(forKey: "index") as? Int) ?? 1
            let targetIdx = curIdx + 1 + index
            let script = """
            tell application "Music"
                try
                    set qPl to missing value
                    repeat with p in (get every user playlist whose name is "Очередь AMR")
                        if (count of tracks of p) > 0 then
                            set qPl to p
                            exit repeat
                        end if
                    end repeat
                    if qPl is not missing value then
                        delete (track \(targetIdx) of qPl)
                    end if
                end try
            end tell
            """
            _ = AppleScriptExecutor.shared.execute(script)
            LibraryService.shared.invalidatePlaylistCache(name: "Очередь AMR")
            PlaybackStateStore.shared.invalidateQueueCache()
            return true
        }

        let q = await getPlaybackQueue()
        guard index >= 0 && index < q.upcomingTracks.count else { return false }

        return PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.activeCustomQueue = q.tracks
            PlaybackStateStore.shared.activeCustomQueueIndex = q.currentIndex
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueueName = q.playlist
            let targetIdx = PlaybackStateStore.shared.activeCustomQueueIndex + 1 + index
            if targetIdx >= 0 && targetIdx < PlaybackStateStore.shared.activeCustomQueue.count {
                PlaybackStateStore.shared.activeCustomQueue.remove(at: targetIdx)
                return true
            }
            return false
        }
    }

    public func clearUpcomingQueue() async -> Bool {
        PlaybackStateStore.shared.invalidateQueueCache()
        let hasCustom = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty
        }

        if hasCustom {
            return PlaybackStateStore.shared.withLock {
                if PlaybackStateStore.shared.activeCustomQueueIndex + 1 < PlaybackStateStore.shared.activeCustomQueue.count {
                    PlaybackStateStore.shared.activeCustomQueue.removeSubrange((PlaybackStateStore.shared.activeCustomQueueIndex + 1)...)
                }
                return true
            }
        }

        if let app = MusicAppProvider.shared.getMusicApp(), let pName = app.currentPlaylist?.value(forKey: "name") as? String, pName == "Очередь AMR" {
            let curIdx = (app.currentTrack?.value(forKey: "index") as? Int) ?? 1
            let script = """
            tell application "Music"
                try
                    set qPl to missing value
                    repeat with p in (get every user playlist whose name is "Очередь AMR")
                        if (count of tracks of p) > 0 then
                            set qPl to p
                            exit repeat
                        end if
                    end repeat
                    if qPl is not missing value then
                        set c to count of tracks of qPl
                        if c > \(curIdx) then
                            delete (tracks \(curIdx + 1) thru c of qPl)
                        end if
                    end if
                end try
            end tell
            """
            _ = AppleScriptExecutor.shared.execute(script)
            LibraryService.shared.invalidatePlaylistCache(name: "Очередь AMR")
            return true
        }

        let q = await getPlaybackQueue()
        let curTrack = PlayerStatusEngine.shared.getPlayerStatus().track
        return PlaybackStateStore.shared.withLock {
            if let cur = curTrack {
                PlaybackStateStore.shared.activeCustomQueue = [cur]
            } else if q.currentIndex < q.tracks.count {
                PlaybackStateStore.shared.activeCustomQueue = [q.tracks[q.currentIndex]]
            } else {
                PlaybackStateStore.shared.activeCustomQueue = []
            }
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueueName = "Очередь"
            return true
        }
    }
}
