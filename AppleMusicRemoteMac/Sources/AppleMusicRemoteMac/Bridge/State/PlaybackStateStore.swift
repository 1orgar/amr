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
    public var originalCustomQueue: [TrackInfo] = []
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
    public var repeatMode: String = "off"

    // Search Query State for Auto-Paging
    public var activeSearchQuery: String?
    public var activeSearchCountry: String?
    public var activeSearchOffset: Int = 0
    public var isFetchingNextSearchPage: Bool = false

    // Cloud / Auto-Advance Tracking
    public var lastWasPlayingCloud: Bool = false
    public var lastCloudPlayTime: Date?
    public var currentTrackPlaybackConfirmed: Bool = false
    public var hasTriggeredAdvanceForCurrentTrack: Bool = false
    public var lastKnownPosition: Double = 0.0

    // Temporary Cloud Tracks Staged in Library Playlist 1
    public var stagedTemporaryTrackDbIds: Set<Int> = {
        let saved = UserDefaults.standard.array(forKey: "AMRStagedTemporaryTrackDbIds") as? [Int] ?? []
        return Set(saved)
    }()

    // Cached History & Upcoming
    public var latestHistoryTracks: [TrackInfo] = []
    public var latestUpcomingTracks: [TrackInfo] = []

    // Optimistic Seek Coordinates
    public var seekTargetPosition: Double?
    public var seekTargetDate: Date = .distantPast

    // User Pause Intent State
    public var isUserPaused: Bool = false

    // Track Skip & Stream Transition Debounce
    public var lastSkipTime: Date = .distantPast
    public var isStagingCloudTrack: Bool = false
    public var playbackGeneration: UInt64 = 0
    public var isTransitioningTrack: Bool {
        isStagingCloudTrack || Date().timeIntervalSince(lastSkipTime) < 2.5
    }

    // Status & Queue Caches
    public var lastPlayerStatusCache: (timestamp: Date, status: PlayerStatus)?
    public var playbackQueueCache: (timestamp: Date, info: PlaybackQueueInfo)?
    public var trackMetadataCache: [Int: (name: String, artist: String, album: String)] = [:]
    public var needsStaticMetadataRefresh: Bool = true

    // Volume State (simulated when Music.app is not active or in test runners)
    public var simulatedVolume: Int = 50
    public var preDLNAVolume: Int = 100
    public var isDLNAMuted: Bool = false

    // Volume Lock State (Bit-Perfect 100% volume mode)
    public var isVolumeLockedTo100: Bool {
        get {
            if UserDefaults.standard.object(forKey: "LockVolume100") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "LockVolume100")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "LockVolume100")
        }
    }

    private init() {}

    // MARK: - Synchronized Operations

    public func withLock<T>(_ block: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block()
    }

    public func invalidateStatusCache(optimisticState: String? = nil) {
        lock.lock()
        if let opt = optimisticState {
            if opt == "paused" || opt == "stopped" {
                isUserPaused = true
            } else if opt == "playing" {
                isUserPaused = false
            }
            if let current = lastPlayerStatusCache {
                var updatedStatus = current.status
                updatedStatus.playerState = opt
                lastPlayerStatusCache = (timestamp: Date(), status: updatedStatus)
            } else {
                let initialStatus = PlayerStatus(playerState: opt)
                lastPlayerStatusCache = (timestamp: Date(), status: initialStatus)
            }
        } else {
            lastPlayerStatusCache = nil
            needsStaticMetadataRefresh = true
        }
        lock.unlock()
    }

    public func markStaticMetadataNeedsRefresh() {
        lock.lock()
        needsStaticMetadataRefresh = true
        lock.unlock()
    }

    public func invalidateQueueCache() {
        lock.lock()
        playbackQueueCache = nil
        lastPlayerStatusCache = nil
        needsStaticMetadataRefresh = true
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
        isUserPaused = false
        currentOriginalPlaylistName = originalPlaylist
        isRadioPlayback = isRadio
        activeStationName = stationName
        playbackQueueCache = nil
        isCustomQueuePlayback = false
        activeCustomQueue.removeAll()
        originalCustomQueue.removeAll()
        activeCustomQueueName = nil
        currentTrackPlaybackConfirmed = false
        hasTriggeredAdvanceForCurrentTrack = false
        lastWasPlayingCloud = false
        lastCloudPlayTime = nil
        lastKnownPosition = 0.0
        lastSkipTime = .distantPast
        activeSearchQuery = nil
        activeSearchCountry = nil
        activeSearchOffset = 0
        isFetchingNextSearchPage = false
        needsStaticMetadataRefresh = true
    }

    public func resetCustomQueue() {
        lock.lock()
        defer { lock.unlock() }
        isUserPaused = false
        isCustomQueuePlayback = false
        activeCustomQueue.removeAll()
        originalCustomQueue.removeAll()
        activeCustomQueueIndex = 0
        activeCustomQueueName = nil
        isRadioPlayback = false
        activeStationName = nil
        currentOriginalPlaylistName = nil
        playbackQueueCache = nil
        currentTrackPlaybackConfirmed = false
        hasTriggeredAdvanceForCurrentTrack = false
        lastWasPlayingCloud = false
        lastCloudPlayTime = nil
        lastKnownPosition = 0.0
        lastSkipTime = .distantPast
        isShuffleQueueActive = false
        repeatMode = "off"
        activeShuffledQueue.removeAll()
        activeSearchQuery = nil
        activeSearchCountry = nil
        activeSearchOffset = 0
        isFetchingNextSearchPage = false
        needsStaticMetadataRefresh = true
    }

    public func registerStagedTemporaryTrack(dbId: Int) {
        guard dbId > 0 else { return }
        lock.lock()
        stagedTemporaryTrackDbIds.insert(dbId)
        let snapshot = Array(stagedTemporaryTrackDbIds)
        lock.unlock()
        UserDefaults.standard.set(snapshot, forKey: "AMRStagedTemporaryTrackDbIds")
    }

    public func unregisterStagedTemporaryTrack(dbId: Int) {
        guard dbId > 0 else { return }
        lock.lock()
        stagedTemporaryTrackDbIds.remove(dbId)
        let snapshot = Array(stagedTemporaryTrackDbIds)
        lock.unlock()
        UserDefaults.standard.set(snapshot, forKey: "AMRStagedTemporaryTrackDbIds")
    }

    public func cleanupStagedTemporaryTracks(keepingActiveQueue: Bool = false) {
        let toDelete: [Int] = withLock {
            var keep = Set<Int>()
            if keepingActiveQueue {
                for t in activeCustomQueue {
                    if let nid = t.numericId, nid > 0 {
                        keep.insert(nid)
                    }
                }
            }
            let targets = stagedTemporaryTrackDbIds.subtracting(keep)
            stagedTemporaryTrackDbIds.subtract(targets)
            let snapshot = Array(stagedTemporaryTrackDbIds)
            UserDefaults.standard.set(snapshot, forKey: "AMRStagedTemporaryTrackDbIds")
            return Array(targets)
        }
        guard !toDelete.isEmpty, !PlaybackRouter.shared.isTestingEnvironment else { return }
        let idList = toDelete.map { "\($0)" }.joined(separator: ", ")
        DispatchQueue.global(qos: .utility).async {
            _ = AppleScriptExecutor.shared.execute("""
            tell application "Music"
                try
                    repeat with tid in {\(idList)}
                        try
                            delete (every track of library playlist 1 whose database ID is (contents of tid))
                        end try
                    end repeat
                end try
            end tell
            """)
            LibraryService.shared.invalidateLibrarySongsCache()
        }
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
