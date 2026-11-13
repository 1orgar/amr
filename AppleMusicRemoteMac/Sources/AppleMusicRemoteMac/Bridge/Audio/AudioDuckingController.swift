//
//  AudioDuckingController.swift
//  AppleMusicRemoteMac
//
//  Manages Audio Ducking for voice assistant coexistence:
//  lowers playback volume by a configurable percentage (default 80%)
//  and restores the original pre-duck volume upon deactivation.
//

import Foundation

public final class AudioDuckingController: @unchecked Sendable {
    public static let shared = AudioDuckingController()

    private let lock = NSLock()
    private let volumeApplyLock = NSLock()
    private var _isDucked: Bool = false
    private var _originalVolume: Int?
    private var _reductionPercent: Double = 80.0
    private var _lastDuckedVolume: Int = 20
    private var duckTimer: DispatchSourceTimer?
    private var duckGeneration: UInt64 = 0

    public var isDucked: Bool {
        lock.withLock { _isDucked }
    }

    public var originalVolume: Int? {
        lock.withLock { _originalVolume }
    }

    public var currentDuckedVolume: Int {
        lock.withLock {
            guard _isDucked, let orig = _originalVolume else {
                return _lastDuckedVolume
            }
            let factor = max(0.0, min(1.0, (100.0 - _reductionPercent) / 100.0))
            return orig > 0 ? max(1, min(100, Int((Double(orig) * factor).rounded()))) : 0
        }
    }

    private init() {}

    /// Updates the stored pre-duck volume and cancels ducking when the user manually changes volume while ducking is active.
    public func notifyManualVolumeChange(_ newVolume: Int) {
        let didCancel: Bool = lock.withLock {
            guard _isDucked else { return false }
            duckTimer?.cancel()
            duckTimer = nil
            _isDucked = false
            _originalVolume = nil
            duckGeneration &+= 1
            return true
        }
        if didCancel {
            PlaybackStateStore.shared.invalidateStatusCache()
        }
    }

    /// Activates audio ducking. Lowers volume by reductionPercent (default 80%).
    /// If already ducked, preserves the original pre-duck volume.
    /// Optional timeout (seconds) automatically restores volume if voice assistant fails to unduck.
    @discardableResult
    public func activate(reductionPercent: Double = 80.0, timeout: Double? = nil) -> (success: Bool, duckedVolume: Int, originalVolume: Int) {
        let currentVol: Int
        if ExternalAmpTCPController.shared.isActive {
            currentVol = ExternalAmpTCPController.shared.currentVolume
        } else if PlaybackStateStore.shared.withLock({ PlaybackStateStore.shared.isDLNAMuted }) {
            currentVol = 0
        } else {
            var vol = MusicBridge.shared.getPlayerStatus().volume
            if vol == 0,
               !PlaybackStateStore.shared.isVolumeLockedTo100,
               let app = MusicAppProvider.shared.getMusicApp(),
               app.soundVolume > 0 {
                vol = app.soundVolume
            }
            currentVol = vol
        }

        let (shouldProceed, baseVolume, target, gen): (Bool, Int, Int, UInt64) = lock.withLock {
            if !_isDucked && currentVol <= 0 {
                return (false, 0, 0, duckGeneration)
            }
            let base: Int
            if _isDucked, let orig = _originalVolume {
                base = orig
            } else {
                base = currentVol
                _originalVolume = base
            }

            // Calculate ducked volume: reductionPercent (e.g. 80%) reduces to 20% of base
            _reductionPercent = reductionPercent
            let factor = max(0.0, min(1.0, (100.0 - reductionPercent) / 100.0))
            let ducked = base > 0 ? max(1, Int((Double(base) * factor).rounded())) : 0
            _lastDuckedVolume = ducked

            _isDucked = true
            duckGeneration &+= 1
            let currentGen = duckGeneration

            // Reset any existing auto-unduck timer
            duckTimer?.cancel()
            duckTimer = nil

            if let timeout = timeout, timeout > 0 {
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler { [weak self] in
                    guard let self = self else { return }
                    _ = self.deactivate()
                    DispatchQueue.main.async {
                        WebSocketServer.shared.broadcastStatus(includeQueue: false)
                    }
                }
                timer.resume()
                duckTimer = timer
            }
            return (true, base, ducked, currentGen)
        }

        guard shouldProceed else {
            return (false, 0, 0)
        }

        volumeApplyLock.withLock {
            let stillValid = lock.withLock { _isDucked && duckGeneration == gen }
            guard stillValid else { return }
            if ExternalAmpTCPController.shared.isActive {
                ExternalAmpTCPController.shared.setVolume(target, preserveBaseVolume: true)
            } else {
                _ = PlaybackTransportController.shared.setVolume(target, isFromDuckingController: true)
            }
        }

        return (true, target, baseVolume)
    }

    /// Deactivates audio ducking and restores original pre-duck volume.
    @discardableResult
    public func deactivate() -> (success: Bool, restoredVolume: Int) {
        let (origOpt, gen): (Int?, UInt64) = lock.withLock {
            duckTimer?.cancel()
            duckTimer = nil
            guard _isDucked, let orig = _originalVolume else {
                return (nil, duckGeneration)
            }
            _isDucked = false
            _originalVolume = nil
            duckGeneration &+= 1
            return (orig, duckGeneration)
        }

        guard let orig = origOpt else {
            let currentVol = ExternalAmpTCPController.shared.isActive
                ? ExternalAmpTCPController.shared.currentVolume
                : MusicBridge.shared.getPlayerStatus().volume
            return (false, currentVol)
        }

        if ExternalAmpTCPController.shared.isActive {
            let amp = ExternalAmpTCPController.shared
            let effectiveMax = min(amp.maxVolumeCap, amp.profile.nativeMaxVolume)
            let restored: Int
            if orig <= 0 || amp.baseListeningVolume <= 0 {
                restored = 0
            } else if amp.isSoundCheckEnabled {
                restored = max(1, min(effectiveMax, amp.baseListeningVolume + amp.currentTrackVolumeOffset))
            } else {
                restored = min(effectiveMax, orig)
            }
            volumeApplyLock.withLock {
                let stillValid = lock.withLock { !_isDucked && duckGeneration == gen }
                if stillValid {
                    amp.setVolume(restored, preserveBaseVolume: true)
                }
            }
            return (true, restored)
        }

        let isDLNAMuted = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isDLNAMuted }
        if isDLNAMuted {
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.preDLNAVolume = orig
            }
            return (true, 0)
        }

        volumeApplyLock.withLock {
            let stillValid = lock.withLock { !_isDucked && duckGeneration == gen }
            if stillValid {
                _ = PlaybackTransportController.shared.setVolume(orig, isFromDuckingController: true)
            }
        }
        return (true, orig)
    }

    /// Returns current ducking status snapshot
    public func getStatus() -> (isDucked: Bool, originalVolume: Int?, currentVolume: Int) {
        let (ducked, orig) = lock.withLock { (_isDucked, _originalVolume) }
        let currentVol = MusicBridge.shared.getPlayerStatus().volume
        return (ducked, orig, currentVol)
    }
}
