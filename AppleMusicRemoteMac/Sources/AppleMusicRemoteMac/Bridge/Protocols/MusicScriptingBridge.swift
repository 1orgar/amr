//
//  MusicScriptingBridge.swift
//  AppleMusicRemoteMac
//
//  ScriptingBridge protocol declarations, SBObject extensions, and
//  Music.app process connection provider.
//

import AppKit
import Foundation
import ScriptingBridge

// MARK: - ScriptingBridge Objective-C Enums & Protocols

@objc public enum MusicEPlS: Int {
    case stopped = 0x6b505353        // 'kPSS'
    case playing = 0x6b505350        // 'kPSP'
    case paused = 0x6b505370         // 'kPSp'
    case fastForwarding = 0x6b505346 // 'kPSF'
    case rewinding = 0x6b505352      // 'kPSR'
}

@objc public enum MusicERpt: Int {
    case off = 0x6b52504f // 'kRPO'
    case one = 0x6b525031 // 'kRP1'
    case all = 0x6b525041 // 'kRPA'
}

@objc public protocol MusicArtworkProtocol: NSObjectProtocol {
    var data: NSImage? { get }
    var rawData: NSData? { get }
}

@objc public protocol SBAMTrackProtocol: NSObjectProtocol {
    var name: String? { get }
    var artist: String? { get }
    var album: String? { get }
    var duration: Double { get }
    var databaseID: Int { get }
    var persistentID: String? { get }
    var playedCount: Int { get }
    var playedDate: Date? { get }
    var dateAdded: Date? { get }
    var favorited: Bool { get set }
    var loved: Bool { get set }
    func artworks() -> [MusicArtworkProtocol]
    func playOnce(_ once: Bool)
}

@objc public protocol MusicApplicationProtocol: NSObjectProtocol {
    var playerState: MusicEPlS { get }
    var playerPosition: Double { get set }
    var soundVolume: Int { get set }
    var shuffleEnabled: Bool { get set }
    var songRepeat: MusicERpt { get set }
    var currentTrack: SBObject? { get }
    var currentPlaylist: SBObject? { get }
    func playlists() -> SBElementArray
    func tracks() -> SBElementArray
    func playpause()
    func playOnce(_ once: Bool)
    func pause()
    func nextTrack()
    func previousTrack()
    func backTrack()
}

// MARK: - SBObject Convenience Extensions

extension SBObject {
    public var sbName: String { (value(forKey: "name") as? String) ?? "" }
    public var sbArtist: String { (value(forKey: "artist") as? String) ?? "" }
    public var sbAlbum: String { (value(forKey: "album") as? String) ?? "" }
    public var sbDuration: Double { (value(forKey: "duration") as? Double) ?? 0 }
    public var sbDatabaseID: Int { (value(forKey: "databaseID") as? Int) ?? 0 }
    public var sbPlayedCount: Int { (value(forKey: "playedCount") as? Int) ?? 0 }
    public var sbPlayedDate: Date? { value(forKey: "playedDate") as? Date }
    public var sbDateAdded: Date? { value(forKey: "dateAdded") as? Date }
    public var sbBitRate: Int { (value(forKey: "bitRate") as? Int) ?? 0 }
    public var sbSampleRate: Int { (value(forKey: "sampleRate") as? Int) ?? 0 }
    public var sbKind: String { (value(forKey: "kind") as? String) ?? "" }
    public var sbFavorited: Bool {
        get { (value(forKey: "favorited") as? Bool) ?? false }
        set { setValue(newValue, forKey: "favorited") }
    }
    public var sbTracks: SBElementArray? { value(forKey: "tracks") as? SBElementArray }
    public var sbArtworks: SBElementArray? { value(forKey: "artworks") as? SBElementArray }
}

// MARK: - Music Application Connection Provider

public final class MusicAppProvider: @unchecked Sendable {
    public static let shared = MusicAppProvider()

    public var onMusicAppTerminated: (@Sendable () -> Void)?
    public var onMusicAppLaunched: (@Sendable () -> Void)?

    private let lock = NSLock()
    private var musicApp: MusicApplicationProtocol?
    private var lastMusicPid: pid_t = 0
    private var launchObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?

    public var isMusicAppRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
    }

    private init() {
        setupLifecycleObservers()
    }

    deinit {
        if let obs = launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        if let obs = terminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }

    private func setupLifecycleObservers() {
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.Music" else { return }
            NSLog("[MusicAppProvider] 🟢 Music.app launched (PID: %d)", app.processIdentifier)
            self?.lock.lock()
            self?.musicApp = nil
            self?.lastMusicPid = 0
            self?.lock.unlock()

            PlaybackStateStore.shared.invalidateStatusCache()
            PlaybackStateStore.shared.invalidateQueueCache()
            self?.onMusicAppLaunched?()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                PlaybackTransportController.shared.checkAndEnforceVolumeLock()
            }

            DispatchQueue.main.async {
                MenuManager.shared.updateMenuState()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
                UPnPMediaRendererServer.shared.notifySubscribers(force: true)
            }
        }

        terminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.Music" else { return }
            NSLog("[MusicAppProvider] ⚪ Music.app terminated (PID: %d)", app.processIdentifier)
            self?.lock.lock()
            self?.musicApp = nil
            self?.lastMusicPid = 0
            self?.lock.unlock()

            PlaybackStateStore.shared.resetPlaybackState()
            self?.onMusicAppTerminated?()

            DispatchQueue.main.async {
                MenuManager.shared.updateMenuState()
                WebSocketServer.shared.broadcastStatus(includeQueue: true)
                UPnPMediaRendererServer.shared.notifySubscribers(force: true)
            }
        }
    }

    @discardableResult
    public func ensureMusicAppRunning() -> Bool {
        if isMusicAppRunning { return true }
        return launchMusicApp()
    }

    @discardableResult
    public func launchMusicApp(completion: ((Bool) -> Void)? = nil) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else {
            completion?(false)
            return false
        }
        let conf = NSWorkspace.OpenConfiguration()
        conf.activates = false
        conf.hides = true
        NSWorkspace.shared.openApplication(at: url, configuration: conf) { _, error in
            let success = (error == nil)
            if let error = error {
                NSLog("[MusicAppProvider] Failed to launch Music.app: %@", error.localizedDescription)
            } else {
                NSLog("[MusicAppProvider] Successfully requested Music.app launch in background")
            }
            completion?(success)
        }
        return true
    }

    public func getMusicApp() -> MusicApplicationProtocol? {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
        guard let musicProc = runningApps.first else {
            lock.lock()
            musicApp = nil
            lastMusicPid = 0
            lock.unlock()
            return nil
        }

        let currentPid = musicProc.processIdentifier
        lock.lock()
        defer { lock.unlock() }

        if let app = musicApp, currentPid == lastMusicPid {
            return app
        }

        lastMusicPid = currentPid
        if let raw = SBApplication(bundleIdentifier: "com.apple.Music") {
            raw.timeout = 2
            let app = unsafeBitCast(raw, to: MusicApplicationProtocol.self)
            self.musicApp = app
            return app
        }
        return nil
    }
}
