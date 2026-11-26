//
//  PlaybackTransportController.swift
//  AppleMusicRemoteMac
//
//  Transport control operations: play, pause, playPause, stop, next, previous,
//  seek, and volume. (Shuffle, repeat, favorite, and library addition live in +ShuffleRepeat.swift)
//

import Foundation
import ScriptingBridge

public final class PlaybackTransportController: @unchecked Sendable {
    public static let shared = PlaybackTransportController()

    private init() {}

    // MARK: - Core Playback Controls

    public func play() -> Bool {
        let isCurrentlyStaging: Bool = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isUserPaused = false
            let knownPos = max(0.0, PlaybackStateStore.shared.lastKnownPosition)
            PlaybackStateStore.shared.lastCloudPlayTime = Date().addingTimeInterval(-knownPos)
            return PlaybackStateStore.shared.isStagingCloudTrack || PlaybackStateStore.shared.isActivelyStagingInBuffer
        }
        PlaybackStateStore.shared.invalidateStatusCache(optimisticState: "playing")
        if PlaybackRouter.shared.isTestingEnvironment {
            return true
        }
        // If a cloud stream is actively dispatching right now, do not reset generation or trigger `playOnce` on a stale track!
        if isCurrentlyStaging {
            return true
        }
        MusicAppProvider.shared.ensureMusicAppRunning()
        if let app = MusicAppProvider.shared.getMusicApp() {
            let state = app.playerState
            if state == .paused {
                app.playpause()
            } else if state == .stopped {
                let (isCustom, hasQueue, activeIdx) = PlaybackStateStore.shared.withLock {
                    (
                        PlaybackStateStore.shared.isCustomQueuePlayback,
                        !PlaybackStateStore.shared.activeCustomQueue.isEmpty,
                        PlaybackStateStore.shared.activeCustomQueueIndex
                    )
                }
                if isCustom && hasQueue {
                    return QueueManager.shared.playQueueIndexUnlocked(activeIdx)
                }
                app.playOnce(false)
            } else {
                app.playOnce(false)
            }
            return true
        }
        _ = AppleScriptExecutor.shared.run("tell application \"Music\" to play")
        return true
    }

    public func pause() -> Bool {
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isUserPaused = true
            PlaybackStateStore.shared.isActivelyStagingInBuffer = false
            PlaybackStateStore.shared.activeLoadingStage = nil
            PlaybackStateStore.shared.activeLoadingStartedAt = nil
        }
        PlaybackStateStore.shared.invalidateStatusCache(optimisticState: "paused")
        if PlaybackRouter.shared.isTestingEnvironment {
            return true
        }
        if let app = MusicAppProvider.shared.getMusicApp() {
            app.pause()
            return true
        }
        _ = AppleScriptExecutor.shared.run("tell application \"Music\" to pause")
        return true
    }

    public func stop() -> Bool {
        PlaybackStateStore.shared.clearSeekTarget()
        let wasCustomQueue = PlaybackStateStore.shared.withLock { () -> Bool in
            let wasCustom = PlaybackStateStore.shared.isCustomQueuePlayback
            PlaybackStateStore.shared.playbackGeneration &+= 1
            PlaybackStateStore.shared.isStagingCloudTrack = false
            PlaybackStateStore.shared.isUserPaused = true
            PlaybackStateStore.shared.isActivelyStagingInBuffer = false
            PlaybackStateStore.shared.activeLoadingStage = nil
            PlaybackStateStore.shared.activeLoadingStartedAt = nil
            PlaybackStateStore.shared.isCustomQueuePlayback = false
            PlaybackStateStore.shared.activeCustomQueue.removeAll()
            PlaybackStateStore.shared.activeCustomQueueIndex = 0
            return wasCustom
        }
        PlaybackStateStore.shared.invalidateStatusCache(optimisticState: "stopped")
        if wasCustomQueue {
            PlaybackStateStore.shared.scheduleIdleStagedCleanup(after: 300.0)
            MusicKitManager.shared.cleanupTemporaryPlaybackPlaylists(keepingActiveQueue: false)
        }
        if PlaybackRouter.shared.isTestingEnvironment {
            return true
        }
        if let app = MusicAppProvider.shared.getMusicApp() {
            if let stopFn = app.stop {
                stopFn()
            } else {
                app.pause()
                app.playerPosition = 0
            }
            return true
        }
        let (ok, _) = AppleScriptExecutor.shared.run("tell application \"Music\" to stop")
        return ok
    }

    public func playPause() -> Bool {
        let cachedPlaying: Bool? = PlaybackStateStore.shared.withLock {
            if let cache = PlaybackStateStore.shared.lastPlayerStatusCache,
               Date().timeIntervalSince(cache.timestamp) < 1.5 {
                return cache.status.playerState == "playing"
            }
            return nil
        }
        let isPlaying: Bool
        if let cachedPlaying {
            isPlaying = cachedPlaying
        } else if let app = MusicAppProvider.shared.getMusicApp() {
            isPlaying = app.playerState == .playing
        } else {
            isPlaying = PlaybackStateStore.shared.withLock { !PlaybackStateStore.shared.isUserPaused }
        }
        if isPlaying {
            return pause()
        } else {
            return play()
        }
    }

    private let transportLock = NSLock()
    private var lastNextTrackTime: Date = Date.distantPast
    private var lastPrevTrackTime: Date = Date.distantPast

    func resetDebounceForTesting() {
        transportLock.lock()
        lastNextTrackTime = .distantPast
        lastPrevTrackTime = .distantPast
        transportLock.unlock()
    }

    public func nextTrack() -> Bool {
        transportLock.lock()
        let now = Date()
        if now.timeIntervalSince(lastNextTrackTime) < 0.25 {
            transportLock.unlock()
            return true
        }
        lastNextTrackTime = now
        transportLock.unlock()

        let (isCustom, count, curIdx, repMode) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty,
                PlaybackStateStore.shared.activeCustomQueue.count,
                PlaybackStateStore.shared.activeCustomQueueIndex,
                PlaybackStateStore.shared.repeatMode
            )
        }

        if isCustom {
            let nextIdx = curIdx + 1
            if nextIdx >= count && repMode != "all" && repMode != "one" {
                QueueManager.shared.handleEndOfQueueManualNext()
                return true
            }
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.isUserPaused = false
                PlaybackStateStore.shared.lastSkipTime = now
                PlaybackStateStore.shared.lastForeignInterceptTime = .distantPast
                PlaybackStateStore.shared.lastForeignInterceptKey = nil
                PlaybackStateStore.shared.repeatOnePinnedTrack = nil
                PlaybackStateStore.shared.clearSeekTarget()
                PlaybackStateStore.shared.invalidateStatusCache()
                PlaybackStateStore.shared.invalidateQueueCache()
            }
            if nextIdx < count {
                _ = QueueManager.shared.playQueueIndexUnlocked(nextIdx)
            } else if repMode == "all" && count > 0 {
                QueueManager.shared.advanceOrEndCustomQueueUnlocked(reason: "manual-next")
            } else if repMode == "one" && count > 0 {
                let targetIdx = max(0, min(count - 1, curIdx))
                _ = QueueManager.shared.playQueueIndexUnlocked(targetIdx)
            }
            return true
        }

        BitPerfectLogMonitor.shared.beginExplicitTrackSwitch()
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isUserPaused = false
            PlaybackStateStore.shared.lastSkipTime = now
            PlaybackStateStore.shared.lastForeignInterceptTime = .distantPast
            PlaybackStateStore.shared.lastForeignInterceptKey = nil
            PlaybackStateStore.shared.repeatOnePinnedTrack = nil
            PlaybackStateStore.shared.clearSeekTarget()
            PlaybackStateStore.shared.invalidateStatusCache()
            PlaybackStateStore.shared.invalidateQueueCache()
        }

        if PlaybackRouter.shared.isTestingEnvironment {
            BitPerfectLogMonitor.shared.endExplicitTrackSwitch(trackKey: nil)
            return true
        }

        if let app = MusicAppProvider.shared.getMusicApp() {
            app.nextTrack()
            BitPerfectLogMonitor.shared.endExplicitTrackSwitch(trackKey: nil)
            return true
        }
        let (ok, _) = AppleScriptExecutor.shared.run("tell application \"Music\" to next track")
        BitPerfectLogMonitor.shared.endExplicitTrackSwitch(trackKey: nil)
        return ok
    }

    public func previousTrack(forceTrackChange: Bool = false) -> Bool {
        transportLock.lock()
        let now = Date()
        let timeSinceLastClick = now.timeIntervalSince(lastPrevTrackTime)
        if timeSinceLastClick < 0.15 {
            transportLock.unlock()
            return true
        }
        let isRapidRepeat = timeSinceLastClick < 3.0
        lastPrevTrackTime = now
        transportLock.unlock()

        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isUserPaused = false
            PlaybackStateStore.shared.lastSkipTime = now
            PlaybackStateStore.shared.lastForeignInterceptTime = .distantPast
            PlaybackStateStore.shared.lastForeignInterceptKey = nil
            PlaybackStateStore.shared.clearSeekTarget()
            PlaybackStateStore.shared.invalidateStatusCache()
            PlaybackStateStore.shared.invalidateQueueCache()
        }

        let (isCustom, activeIdx) = PlaybackStateStore.shared.withLock {
            (
                PlaybackStateStore.shared.isCustomQueuePlayback && !PlaybackStateStore.shared.activeCustomQueue.isEmpty,
                PlaybackStateStore.shared.activeCustomQueueIndex
            )
        }

        if isCustom {
            let rawPos = MusicAppProvider.shared.getMusicApp()?.playerPosition ?? 0.0
            let appPos = PlayerStatusEngine.shared.computeOptimisticPosition(rawPosition: rawPos, isPlaying: true, duration: 0)
            // Standard media player behavior: if track played > 3.0 seconds AND this is not a rapid double click,
            // restart current track to 0:00 WITHOUT resetting Bit-Perfect format lock!
            if !forceTrackChange && appPos > 3.0 && !isRapidRepeat {
                return seek(to: 0.0)
            }
            if activeIdx > 0 {
                return QueueManager.shared.playQueueIndexUnlocked(activeIdx - 1)
            } else {
                let (repMode, count) = PlaybackStateStore.shared.withLock {
                    (PlaybackStateStore.shared.repeatMode, PlaybackStateStore.shared.activeCustomQueue.count)
                }
                if repMode == "all" && count > 1 {
                    return QueueManager.shared.playQueueIndexUnlocked(count - 1)
                }
                // At the start of custom queue: rewind to 0:00 of track 0, NEVER fall through to app.previousTrack()!
                return seek(to: 0.0)
            }
        }

        // Radio Playback: Apple Music Radio cannot go back to past songs. Rewind to 0:00 without exiting radio!
        let isRadio = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isRadioPlayback }
        if isRadio {
            return seek(to: 0.0)
        }

        // Standard Library Playlists
        if PlaybackRouter.shared.isTestingEnvironment {
            BitPerfectLogMonitor.shared.resetTrackState(clearPrebuffer: true)
            return true
        }
        guard let app = MusicAppProvider.shared.getMusicApp() else { return false }
        let rawPos = app.playerPosition
        let effectivePos = PlayerStatusEngine.shared.computeOptimisticPosition(rawPosition: rawPos, isPlaying: true, duration: 0)
        if !forceTrackChange && effectivePos > 3.0 && !isRapidRepeat {
            return seek(to: 0.0)
        }
        BitPerfectLogMonitor.shared.beginExplicitTrackSwitch()
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.repeatOnePinnedTrack = nil
        }
        app.playerPosition = 0.0
        app.previousTrack()
        BitPerfectLogMonitor.shared.endExplicitTrackSwitch(trackKey: nil)
        return true
    }

    public func seek(to position: Double) -> Bool {
        let clampedPos = max(0.0, position)
        PlaybackStateStore.shared.setSeekTarget(position: clampedPos)
        if clampedPos < 2.0 {
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.lastKnownPosition = clampedPos
                PlaybackStateStore.shared.scheduledSmartTransitionStart = nil
            }
        }
        PlaybackStateStore.shared.invalidateStatusCache()
        if PlaybackRouter.shared.isTestingEnvironment {
            return true
        }
        if let app = MusicAppProvider.shared.getMusicApp() {
            app.playerPosition = clampedPos
            return true
        }
        let (ok, _) = AppleScriptExecutor.shared.execute(
            "tell application \"Music\" to set player position to \(clampedPos)",
            maxWait: 1.2,
            reportTimeout: false
        )
        return ok
    }

    public func setVolume(_ volume: Int, isFromDuckingController: Bool = false) -> Bool {
        let clamped = max(0, min(100, volume))
        if ExternalAmpTCPController.shared.isActive {
            if !isFromDuckingController {
                AudioDuckingController.shared.notifyManualVolumeChange(clamped)
            }
            ExternalAmpTCPController.shared.setVolume(volume, preserveBaseVolume: isFromDuckingController)
            return true
        }
        if PlaybackStateStore.shared.isVolumeLockedTo100 {
            if !isFromDuckingController && volume != 100 {
                NSLog("[PlaybackTransportController] 🔒 Volume is locked to 100%% (Bit-Perfect). Rejecting volume change to %d%%", volume)
                return false
            }
        }
        // Direct hardware volume control on BluOS / DLNA network streamers when volume lock is off
        // (bypasses ~5s HTTP WAV stream buffer lag while keeping Music.app digital output at 100% Bit-Perfect!)
        if DLNADiscoveryManager.shared.hasActiveRenderer {
            if !isFromDuckingController {
                AudioDuckingController.shared.notifyManualVolumeChange(clamped)
            }
            DLNADiscoveryManager.shared.setVolume(clamped)
            return true
        }
        if !isFromDuckingController {
            AudioDuckingController.shared.notifyManualVolumeChange(clamped)
        }
        let isDLNAMuted = PlaybackStateStore.shared.withLock { () -> Bool in
            PlaybackStateStore.shared.simulatedVolume = clamped
            if PlaybackStateStore.shared.isDLNAMuted && !isFromDuckingController && clamped > 0 {
                PlaybackStateStore.shared.preDLNAVolume = clamped
            }
            return PlaybackStateStore.shared.isDLNAMuted
        }
        CoreAudioDeviceManager.shared.updateSavedGuardVolumeIfNeeded(clamped, isDucked: AudioDuckingController.shared.isDucked)
        if !CoreAudioDeviceManager.shared.isMutingGuardActive && !isDLNAMuted {
            if let app = MusicAppProvider.shared.getMusicApp() {
                app.soundVolume = clamped
            } else if MusicAppProvider.shared.isMusicAppRunning {
                let script = "tell application \"Music\" to set sound volume to \(clamped)"
                _ = AppleScriptExecutor.shared.execute(script)
            }
        }
        PlaybackStateStore.shared.invalidateStatusCache()
        return true
    }

    @discardableResult
    public func checkAndEnforceVolumeLock() -> Bool {
        let isDLNAMuted = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isDLNAMuted }
        guard PlaybackStateStore.shared.isVolumeLockedTo100
              && !isDLNAMuted
              && !AudioDuckingController.shared.isDucked
              && !CoreAudioDeviceManager.shared.isMutingGuardActive else { return false }
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.simulatedVolume = 100
        }
        if PlaybackRouter.shared.isTestingEnvironment {
            return true
        }
        guard MusicAppProvider.shared.isMusicAppRunning else {
            return true
        }
        if let app = MusicAppProvider.shared.getMusicApp() {
            if app.soundVolume != 100 {
                NSLog("[PlaybackTransportController] 🔊 Enforcing 100%% volume lock in Music.app (was %d%%)", app.soundVolume)
                app.soundVolume = 100
            }
        } else {
            let script = """
            tell application "Music"
                try
                    if sound volume is not 100 then
                        set sound volume to 100
                    end if
                    return "ok"
                on error
                    return "error"
                end try
            end tell
            """
            _ = AppleScriptExecutor.shared.execute(script)
        }
        PlaybackStateStore.shared.invalidateStatusCache()
        return true
    }
}
