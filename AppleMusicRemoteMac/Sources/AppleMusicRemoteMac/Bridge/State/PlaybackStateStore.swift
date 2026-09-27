//
//  PlaybackStateStore.swift
//  AppleMusicRemoteMac
//
//  Thread-safe state store for active playback queues, radio stations,
//  optimistic seek coordinates, and metadata caching.
//

import Foundation

public final class PlaybackStateStore: @unchecked Sendable {
    public static let shared = PlaybackStateStore()

    private let lock = NSRecursiveLock()

    // Custom Queue State
    public var activeCustomQueue: [TrackInfo] = []
    public var activeCustomQueueIndex: Int = 0
    public var activeCustomQueueName: String?
    public var isCustomQueuePlayback: Bool = false

    // Radio / Station State
    public var isRadioPlayback: Bool = false
    public var activeStationName: String?

    // Original Playlist / Shuffle Queue State
    public var currentOriginalPlaylistName: String?
    public var activeShuffledQueue: [TrackInfo] = []
    public var activeShuffledPlaylistName: String?
    public var isShuffleQueueActive: Bool = false

    // Cloud / Auto-Advance Tracking
    public var lastWasPlayingCloud: Bool = false
    public var lastCloudPlayTime: Date?

    // Cached History & Upcoming
    public var latestHistoryTracks: [TrackInfo] = []
    public var latestUpcomingTracks: [TrackInfo] = []

    // Optimistic Seek Coordinates
    public var seekTargetPosition: Double?
    public var seekTargetDate: Date = .distantPast

    // Status & Queue Caches
    public var lastPlayerStatusCache: (timestamp: Date, status: PlayerStatus)?
    public var playbackQueueCache: (timestamp: Date, info: PlaybackQueueInfo)?
    public var trackMetadataCache: [Int: (name: String, artist: String, album: String)] = [:]

    private init() {}

    // MARK: - Synchronized Operations

    public func withLock<T>(_ block: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block()
    }

    public func invalidateStatusCache() {
        lock.lock()
        lastPlayerStatusCache = nil
        lock.unlock()
    }

    public func invalidateQueueCache() {
        lock.lock()
        playbackQueueCache = nil
        lastPlayerStatusCache = nil
        lock.unlock()
    }

    public func getTrackMetadata(id: Int) -> (name: String, artist: String, album: String)? {
        lock.lock()
        defer { lock.unlock() }
        return trackMetadataCache[id]
    }

    public func setTrackMetadata(id: Int, name: String, artist: String, album: String) {
        lock.lock()
        trackMetadataCache[id] = (name: name, artist: artist, album: album)
        lock.unlock()
    }

    public func resetPlaybackState(originalPlaylist: String? = nil, isRadio: Bool = false, stationName: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        currentOriginalPlaylistName = originalPlaylist
        isRadioPlayback = isRadio
        activeStationName = stationName
        playbackQueueCache = nil
        isCustomQueuePlayback = false
        activeCustomQueue.removeAll()
        activeCustomQueueName = nil
    }

    public func setSeekTarget(position: Double) {
        lock.lock()
        seekTargetPosition = position
        seekTargetDate = Date()
        lock.unlock()
    }

    public func clearSeekTarget() {
        lock.lock()
        seekTargetPosition = nil
        lock.unlock()
    }
}
