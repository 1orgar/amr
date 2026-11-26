//
//  PlaybackRouter+CloudSync.swift
//  AppleMusicRemoteMac
//
//  Synchronous Bit-Perfect ALAC Lossless & Hi-Res cloud playback engine in `Music.app`:
//  plays Apple Music catalog tracks directly via `SystemMusicPlayerBridge` (`MPMusicPlayerController.systemMusicPlayer`)
//  with ZERO `/v1/me/library` writes, ZERO playlists, ZERO cloud-sync spinners, and full account storefront & locale support.
//

import AppKit
import Foundation

extension PlaybackRouter {

    public func playCloudSync(
        url: String?,
        id: String?,
        name: String?,
        artist: String?,
        skipInitialMusicAppLookup: Bool = false,
        expectedGeneration: UInt64? = nil
    ) -> Bool {
        if let exp = expectedGeneration {
            let validBeforeStop = PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.playbackGeneration == exp && !PlaybackStateStore.shared.isUserPaused
            }
            guard validBeforeStop else { return false }
        }
        if !isTestingEnvironment && urlOpener == nil {
            BitPerfectLogMonitor.shared.beginExplicitTrackSwitch()
        }
        stopAndClearAMRQueue()
        let stateCheck: (inMultiQueue: Bool, gen: UInt64)? = PlaybackStateStore.shared.withLock {
            if let exp = expectedGeneration {
                guard PlaybackStateStore.shared.playbackGeneration == exp && !PlaybackStateStore.shared.isUserPaused else {
                    return nil
                }
            }
            PlaybackStateStore.shared.isStagingCloudTrack = true
            PlaybackStateStore.shared.isActivelyStagingInBuffer = false
            PlaybackStateStore.shared.activeLoadingStage = "cloud"
            PlaybackStateStore.shared.activeLoadingStartedAt = Date()
            return (
                PlaybackStateStore.shared.isCustomQueuePlayback && PlaybackStateStore.shared.activeCustomQueue.count > 1,
                expectedGeneration ?? PlaybackStateStore.shared.playbackGeneration
            )
        }
        guard let (inMultiQueue, gen) = stateCheck else { return false }
        defer {
            PlaybackStateStore.shared.withLock {
                if PlaybackStateStore.shared.playbackGeneration == gen {
                    PlaybackStateStore.shared.isStagingCloudTrack = false
                    PlaybackStateStore.shared.isActivelyStagingInBuffer = false
                }
            }
        }
        if !inMultiQueue {
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.isRadioPlayback = false
                PlaybackStateStore.shared.activeStationName = nil
            }
        }

        // 1. Mock / unit-test fast path (preserves deterministic URL routing for tests)
        if isTestingEnvironment || urlOpener != nil {
            if let u = url, !u.isEmpty {
                if openMusicUrl(u) {
                    let now = Date()
                    PlaybackStateStore.shared.withLock {
                        if PlaybackStateStore.shared.playbackGeneration == gen {
                            PlaybackStateStore.shared.lastCloudPlayTime = now
                            PlaybackStateStore.shared.lastSkipTime = now
                            PlaybackStateStore.shared.activeLoadingStage = nil
                            PlaybackStateStore.shared.activeLoadingStartedAt = nil
                        }
                    }
                    resumePlaybackIfNeeded(generation: gen)
                    PlaybackStateStore.shared.invalidateQueueCache()
                    PlaybackStateStore.shared.invalidateStatusCache()
                    return true
                }
            }
            if (url == nil || url?.isEmpty == true), let sId = id, Int(sId) != nil {
                let sf = MusicKitManager.shared.getUserStorefront()
                let synthUrl = "music://music.apple.com/\(sf)/album/_?i=\(sId)"
                if openMusicUrl(synthUrl) {
                    let now = Date()
                    PlaybackStateStore.shared.withLock {
                        if PlaybackStateStore.shared.playbackGeneration == gen {
                            PlaybackStateStore.shared.lastCloudPlayTime = now
                            PlaybackStateStore.shared.lastSkipTime = now
                            PlaybackStateStore.shared.activeLoadingStage = nil
                            PlaybackStateStore.shared.activeLoadingStartedAt = nil
                        }
                    }
                    resumePlaybackIfNeeded(generation: gen)
                    PlaybackStateStore.shared.invalidateQueueCache()
                    PlaybackStateStore.shared.invalidateStatusCache()
                    return true
                }
            }
            return false
        }

        // 2. Fast ~2 ms read-only check for permanent user library tracks ALREADY in Music.app (`library playlist 1` only)
        let cachedVariants = MusicKitManager.shared.cachedTitleVariants(catalogId: id)
        let cachedAltTitles = cachedVariants.map(\.name).filter { !$0.isEmpty }
        let cachedAltArtists = cachedVariants.map(\.artist).filter { !$0.isEmpty }
        if !skipInitialMusicAppLookup,
           let n = name, !n.isEmpty,
           !LibraryService.shared.hasConfirmedEmptyLibraryCache() {
            if let existing = MusicKitManager.shared.findTrackDatabaseIdDetailedInMusicApp(
                name: n,
                artist: artist ?? "",
                checkSubscriptionPlaylists: false,
                alternateTitles: cachedAltTitles,
                alternateArtists: cachedAltArtists
            ), existing.dbId > 0, existing.isPermanentLibrary {
                let isStagedTemp = PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.stagedTemporaryTrackDbIds.contains(existing.dbId)
                }
                if !isStagedTemp && playTrackByDatabaseIdViaAMRQueue(existing.dbId, generation: gen) {
                    let cleanA = (artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let key = "\(cleanA.lowercased()):\(n.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
                    let cachedFmt = BitPerfectLogMonitor.shared.getCachedFormat(artist: cleanA, title: n, catalogId: id)
                    BitPerfectLogMonitor.shared.endExplicitTrackSwitch(
                        trackKey: key,
                        catalogId: id,
                        expectedSampleRate: cachedFmt?.sampleRate,
                        expectedBitDepth: cachedFmt?.bitDepth
                    )
                    let now = Date()
                    PlaybackStateStore.shared.withLock {
                        if PlaybackStateStore.shared.playbackGeneration == gen {
                            if !cachedVariants.isEmpty {
                                PlaybackStateStore.shared.activeTrackTitleVariants = cachedVariants
                            }
                            let idx = PlaybackStateStore.shared.activeCustomQueueIndex
                            if idx >= 0 && idx < PlaybackStateStore.shared.activeCustomQueue.count {
                                PlaybackStateStore.shared.activeCustomQueue[idx].numericId = existing.dbId
                                if existing.isPermanentLibrary {
                                    PlaybackStateStore.shared.activeCustomQueue[idx].isLocal = true
                                }
                            }
                            PlaybackStateStore.shared.lastCloudPlayTime = now
                            PlaybackStateStore.shared.lastSkipTime = now
                            PlaybackStateStore.shared.lastWasPlayingCloud = true
                            PlaybackStateStore.shared.activeLoadingStage = nil
                            PlaybackStateStore.shared.activeLoadingStartedAt = nil
                            PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                        }
                    }
                    PlaybackStateStore.shared.invalidateQueueCache()
                    PlaybackStateStore.shared.invalidateStatusCache()
                    return true
                }
            }
        }

        // 3. PRIMARY ENGINE — Direct Native `Music.app` Cloud Playback (`SystemMusicPlayerBridge`, Bit-Perfect ALAC Lossless & Hi-Res, ZERO library writes!)
        let cleanName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = (artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if SystemMusicPlayerBridge.shared.playCatalogTrackSync(
            id: id,
            url: url,
            name: cleanName,
            artist: cleanArtist,
            expectedGeneration: gen
        ) {
            let now = Date()
            PlaybackStateStore.shared.withLock {
                if PlaybackStateStore.shared.playbackGeneration == gen {
                    PlaybackStateStore.shared.lastCloudPlayTime = now
                    PlaybackStateStore.shared.lastSkipTime = now
                    PlaybackStateStore.shared.lastWasPlayingCloud = true
                    PlaybackStateStore.shared.activeLoadingStage = nil
                    PlaybackStateStore.shared.activeLoadingStartedAt = nil
                    PlaybackStateStore.shared.currentOriginalPlaylistName = "Очередь AMR"
                }
            }
            PlaybackStateStore.shared.invalidateQueueCache()
            PlaybackStateStore.shared.invalidateStatusCache()
            return true
        }

        // Inside a multi-track queue, never fall back to `ra.<songId>` radio stations — cleanly skip genuinely unavailable items.
        if inMultiQueue {
            PlaybackStateStore.shared.withLock {
                if PlaybackStateStore.shared.playbackGeneration == gen {
                    PlaybackStateStore.shared.activeLoadingStage = nil
                    PlaybackStateStore.shared.activeLoadingStartedAt = nil
                }
            }
            NSLog("[PlaybackRouter] ⏭️ Cloud track '%@ — %@' (id=%@) is unavailable in Apple Music — skipping in playlist order",
                  cleanArtist, cleanName, id ?? "nil")
            return false
        }

        // 4. Single-track fallback (`ra.<songId>`) only when outside multi-track queues
        var directSongId: String? = nil
        if let u = url, let comp = URLComponents(string: u),
           let qi = comp.queryItems?.first(where: { $0.name == "i" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
           let num = Int(qi), num >= 1_000_000 {
            directSongId = qi
        }
        if directSongId == nil, let rawId = id?.trimmingCharacters(in: .whitespacesAndNewlines),
           let num = Int(rawId), num >= 1_000_000 {
            directSongId = rawId
        }
        if let sId = directSongId, openMusicUrl("music://music.apple.com/station/item/ra.\(sId)") {
            let key = !cleanName.isEmpty ? "\(cleanArtist.lowercased()):\(cleanName.lowercased())" : nil
            BitPerfectLogMonitor.shared.endExplicitTrackSwitch(trackKey: key, catalogId: sId)
            let now = Date()
            PlaybackStateStore.shared.withLock {
                if PlaybackStateStore.shared.playbackGeneration == gen {
                    PlaybackStateStore.shared.lastCloudPlayTime = now
                    PlaybackStateStore.shared.lastSkipTime = now
                    PlaybackStateStore.shared.lastWasPlayingCloud = true
                    PlaybackStateStore.shared.activeLoadingStage = "cloud"
                    PlaybackStateStore.shared.currentOriginalPlaylistName = nil
                }
            }
            resumePlaybackIfNeeded(generation: gen)
            PlaybackStateStore.shared.invalidateQueueCache()
            PlaybackStateStore.shared.invalidateStatusCache()
            return true
        }

        PlaybackStateStore.shared.withLock {
            if PlaybackStateStore.shared.playbackGeneration == gen {
                PlaybackStateStore.shared.activeLoadingStage = nil
                PlaybackStateStore.shared.activeLoadingStartedAt = nil
            }
        }
        return false
    }
}
