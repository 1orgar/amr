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
    public private(set) var isDucked: Bool = false
    public private(set) var originalVolume: Int?
    private var duckTimer: DispatchSourceTimer?

    private init() {}

    /// Activates audio ducking. Lowers volume by reductionPercent (default 80%).
    /// If already ducked, preserves the original pre-duck volume.
    /// Optional timeout (seconds) automatically restores volume if voice assistant fails to unduck.
    @discardableResult
    public func activate(reductionPercent: Double = 80.0, timeout: Double? = nil) -> (success: Bool, duckedVolume: Int, originalVolume: Int) {
        lock.lock()
        defer { lock.unlock() }

        var currentVol = MusicBridge.shared.getPlayerStatus().volume
        if currentVol == 0, let app = MusicAppProvider.shared.getMusicApp(), app.soundVolume > 0 {
            currentVol = app.soundVolume
        }

        let baseVolume: Int
        if isDucked, let orig = originalVolume {
            baseVolume = orig
        } else {
            baseVolume = currentVol
            originalVolume = baseVolume
        }

        // Calculate ducked volume: reductionPercent (e.g. 80%) reduces to 20% of base
        let factor = max(0.0, min(1.0, (100.0 - reductionPercent) / 100.0))
        let target = baseVolume > 0 ? max(1, Int((Double(baseVolume) * factor).rounded())) : 0

        _ = MusicBridge.shared.setVolume(target)
        isDucked = true

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

        return (true, target, baseVolume)
    }

    /// Deactivates audio ducking and restores original pre-duck volume.
    @discardableResult
    public func deactivate() -> (success: Bool, restoredVolume: Int) {
        lock.lock()
        defer { lock.unlock() }

        duckTimer?.cancel()
        duckTimer = nil

        guard isDucked, let orig = originalVolume else {
            let currentVol = MusicBridge.shared.getPlayerStatus().volume
            return (false, currentVol)
        }

        _ = MusicBridge.shared.setVolume(orig)
        isDucked = false
        originalVolume = nil

        return (true, orig)
    }

    /// Returns current ducking status snapshot
    public func getStatus() -> (isDucked: Bool, originalVolume: Int?, currentVolume: Int) {
        lock.lock()
        defer { lock.unlock() }
        let currentVol = MusicBridge.shared.getPlayerStatus().volume
        return (isDucked, originalVolume, currentVol)
    }
}
