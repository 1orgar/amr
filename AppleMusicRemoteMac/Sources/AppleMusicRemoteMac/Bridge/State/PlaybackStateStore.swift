//
//  PlaybackStateStore.swift
//  AppleMusicRemoteMac
//
//  Thread-safe state store for active playback queues, radio stations,
//  optimistic seek coordinates, and metadata caching.
//

import AppKit
import Foundation

public struct PendingStagedCatalogTrack: Codable, Sendable, Equatable {
    public var catalogId: String
    public var name: String
    public var artist: String
    public var album: String
    public var stagedAt: TimeInterval

    public init(
        catalogId: String,
        name: String,
        artist: String,
        album: String = "",
        stagedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.catalogId = catalogId
        self.name = name
        self.artist = artist
        self.album = album
        self.stagedAt = stagedAt
    }
}

public struct OverlapTransitionSnapshot: Sendable {
    public let outgoingName: String
    public let incomingTrack: TrackInfo
    public let startedAt: Date
    public let initialPosition: Double

    public init(
        outgoingName: String,
        incomingTrack: TrackInfo,
        startedAt: Date = Date(),
        initialPosition: Double = 0.0
    ) {
        self.outgoingName = outgoingName
        self.incomingTrack = incomingTrack
        self.startedAt = startedAt
        self.initialPosition = initialPosition
    }
}

public final class PlaybackStateStore: @unchecked Sendable {
    public static let shared = PlaybackStateStore()

    static let stagedDbIdsStorageKey = "AMRStagedTemporaryTrackDbIds"
    static let pendingStagedStorageKey = "AMRPendingStagedCatalogTracks"

    static var isRunningUnderXCTest: Bool {
        NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    let lock = NSRecursiveLock()
    let stagedCleanupQueue = DispatchQueue(label: "org.ksholokhov.amr.staged-cleanup", qos: .utility)

    // Custom Queue State
    public var activeCustomQueue: [TrackInfo] = []
    public var originalCustomQueue: [TrackInfo] = []
    public var activeCustomQueueIndex: Int = 0
    public var activeCustomQueueName: String?
    public var isCustomQueuePlayback: Bool = false

    // Radio / Station State
    public var isRadioPlayback: Bool = false
    public var activeStationName: String?
    public var repeatOnePinnedTrack: TrackInfo? = nil
    public var lastRepeatOneRewindTime: Date = .distantPast
    public var radioHistoryTracks: [TrackInfo] = []
    public var lastRadioTrackSnapshot: TrackInfo? = nil
    public var resolvingRadioDurationTrackKey: String? = nil

    // Original Playlist / Shuffle Queue State
    public var currentOriginalPlaylistName: String?
    public var activeShuffledQueue: [TrackInfo] = []
    public var activeShuffledIndex: Int = 0
    public var activeShuffledPlaylistName: String?
    public var isShuffleQueueActive: Bool = false
    public var repeatMode: String = "off"

    // Search Query State for Auto-Paging
    public var activeSearchQuery: String?
    public var activeSearchCountry: String?
    public var activeSearchOffset: Int = 0
    public var isFetchingNextSearchPage: Bool = false

    // AI Curator Prompt State for Infinite Wave Auto-Paging
    public var activeCuratorPrompt: String?
    public var isFetchingNextCuratorPage: Bool = false

    // Cloud / Auto-Advance Tracking
    public var lastWasPlayingCloud: Bool = false
    public var lastCloudPlayTime: Date?
    public var currentTrackPlaybackConfirmed: Bool = false
    public var hasTriggeredAdvanceForCurrentTrack: Bool = false
    public var lastKnownPosition: Double = 0.0
    public var scheduledSmartTransitionStart: Double? = nil
    public var nativeQueuedUpcomingCatalogIds: [String] = []
    public var activeOverlapTransition: OverlapTransitionSnapshot? = nil
    public var lastSeekCommandTime: Date = .distantPast

    // Temporary Cloud Tracks Staged in Library Playlist 1
    public var stagedTemporaryTrackDbIds: Set<Int> = {
        let saved = AppStorageProvider.shared.array(forKey: "AMRStagedTemporaryTrackDbIds") as? [Int] ?? []
        return Set(saved)
    }()
    var pendingStagedCatalogTracks: [PendingStagedCatalogTrack] = []
    var permanentlySavedTrackKeys: Set<String> = []
    var sessionStagedTimestamps: [Int: Date] = [:]
    var recentlyStagedAlbumHistory: [(album: String, trackName: String, artist: String, stagedAt: TimeInterval)] = []
    var idleStagedCleanupSeq: UInt64 = 0

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
    public var lastConfirmedTrackTime: Date = .distantPast
    public var lastForeignInterceptTime: Date = .distantPast
    public var lastForeignInterceptKey: String? = nil
    public var transitionPreviousTrackKey: String? = nil
    public var activeTrackTitleVariants: [(name: String, artist: String)] = []
    public var triedAlternateCloudSeedForCurrentTrack: Bool = false
    public var alternateCloudSeedAttemptCount: Int = 0
    public var triedCloudSeedIdsForCurrentTrack: Set<String> = []
    public var lastRepeatSetTime: Date = .distantPast
    public var lastShuffleSetTime: Date = .distantPast
    public var isStagingCloudTrack: Bool = false
    public var isActivelyStagingInBuffer: Bool = false
    public var activeLoadingStage: String? = nil
    public var activeLoadingStartedAt: Date? = nil
    public var playbackGeneration: UInt64 = 0
    public var isTransitioningTrack: Bool {
        isStagingCloudTrack || isActivelyStagingInBuffer || Date().timeIntervalSince(lastSkipTime) < 2.5
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
            if AppStorageProvider.shared.object(forKey: "LockVolume100") == nil {
                return true
            }
            return AppStorageProvider.shared.bool(forKey: "LockVolume100")
        }
        set {
            AppStorageProvider.shared.set(newValue, forKey: "LockVolume100")
            ExternalAmpTCPController.shared.enforceVolumeLockConstraint(isVolumeLockedTo100: newValue)
        }
    }

    private init() {
        if !Self.isRunningUnderXCTest {
            if let savedPerm = AppStorageProvider.shared.stringArray(forKey: "AMRPermanentlySavedTrackKeys") {
                self.permanentlySavedTrackKeys = Set(savedPerm)
            }
            if let data = AppStorageProvider.shared.data(forKey: Self.pendingStagedStorageKey),
               let decoded = try? JSONDecoder().decode([PendingStagedCatalogTrack].self, from: data) {
                let now = Date().timeIntervalSince1970
                let maxAge: TimeInterval = 7.0 * 86_400.0
                let fresh = decoded.filter { now - $0.stagedAt <= maxAge }
                self.pendingStagedCatalogTracks = fresh
                if fresh.count != decoded.count, let prunedData = try? JSONEncoder().encode(fresh) {
                    AppStorageProvider.shared.set(prunedData, forKey: Self.pendingStagedStorageKey)
                }
            }
        }
    }

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
        if trackMetadataCache.count > 5000 && trackMetadataCache[id] == nil {
            let keepIds = stagedTemporaryTrackDbIds
            var pruned: [Int: (name: String, artist: String, album: String)] = [:]
            for sid in keepIds {
                if let val = trackMetadataCache[sid] {
                    pruned[sid] = val
                }
            }
            for (k, v) in trackMetadataCache where pruned.count < 2500 {
                pruned[k] = v
            }
            trackMetadataCache = pruned
        }
        trackMetadataCache[id] = (name: name, artist: artist, album: album)
        if stagedTemporaryTrackDbIds.contains(id) {
            recordStagedAlbumHistoryLocked(album: album, trackName: name, artist: artist)
        }
        lock.unlock()
    }

    func recordStagedAlbumHistoryLocked(album: String, trackName: String, artist: String) {
        let cleanAlb = album.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = trackName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArt = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAlb.isEmpty || !cleanName.isEmpty else { return }
        let now = Date().timeIntervalSince1970
        recentlyStagedAlbumHistory.removeAll { item in
            if now - item.stagedAt > 3600.0 { return true }
            return item.album.caseInsensitiveCompare(cleanAlb) == .orderedSame
                && item.trackName.caseInsensitiveCompare(cleanName) == .orderedSame
                && item.artist.caseInsensitiveCompare(cleanArt) == .orderedSame
        }
        recentlyStagedAlbumHistory.append((album: cleanAlb, trackName: cleanName, artist: cleanArt, stagedAt: now))
        if recentlyStagedAlbumHistory.count > 200 {
            recentlyStagedAlbumHistory = Array(recentlyStagedAlbumHistory.suffix(200))
        }
    }

    public func resetPlaybackState(
        originalPlaylist: String? = nil,
        isRadio: Bool = false,
        stationName: String? = nil,
        isCustomQueue: Bool = false,
        playlistName: String? = nil
    ) {
        let shouldCleanupStaged: Bool = {
            lock.lock()
            defer { lock.unlock() }
            playbackGeneration &+= 1
            isStagingCloudTrack = false
            isActivelyStagingInBuffer = false
            activeLoadingStage = nil
            activeLoadingStartedAt = nil
            isUserPaused = false
            currentOriginalPlaylistName = playlistName ?? originalPlaylist
            isRadioPlayback = isRadio
            if isRadio && repeatMode == "all" {
                repeatMode = "off"
            }
            activeStationName = stationName
            repeatOnePinnedTrack = nil
            resolvingRadioDurationTrackKey = nil
            if !isRadio {
                radioHistoryTracks.removeAll()
                lastRadioTrackSnapshot = nil
            }
            playbackQueueCache = nil
            isCustomQueuePlayback = isCustomQueue
            if !isCustomQueue {
                activeCustomQueue.removeAll()
                originalCustomQueue.removeAll()
                activeCustomQueueIndex = 0
                activeCustomQueueName = nil
            }
            isShuffleQueueActive = false
            activeShuffledQueue.removeAll()
            activeShuffledIndex = 0
            activeShuffledPlaylistName = nil
            currentTrackPlaybackConfirmed = false
            hasTriggeredAdvanceForCurrentTrack = false
            lastWasPlayingCloud = false
            lastCloudPlayTime = nil
            lastKnownPosition = 0.0
            scheduledSmartTransitionStart = nil
            nativeQueuedUpcomingCatalogIds.removeAll()
            activeOverlapTransition = nil
            lastSeekCommandTime = .distantPast
            lastSkipTime = .distantPast
            lastConfirmedTrackTime = .distantPast
            lastForeignInterceptTime = .distantPast
            lastForeignInterceptKey = nil
            transitionPreviousTrackKey = nil
            activeTrackTitleVariants.removeAll()
            triedAlternateCloudSeedForCurrentTrack = false
            alternateCloudSeedAttemptCount = 0
            triedCloudSeedIdsForCurrentTrack.removeAll()
            activeSearchQuery = nil
            activeSearchCountry = nil
            activeSearchOffset = 0
            isFetchingNextSearchPage = false
            activeCuratorPrompt = nil
            isFetchingNextCuratorPage = false
            needsStaticMetadataRefresh = true
            return !isCustomQueue
        }()

        if shouldCleanupStaged {
            if PlaybackRouter.shared.isTestingEnvironment {
                cleanupStagedTemporaryTracks(keepingActiveQueue: false)
                MusicKitManager.shared.cleanupTemporaryPlaybackPlaylists(keepingActiveQueue: false)
            } else {
                scheduleIdleStagedCleanup(after: 300.0)
                DispatchQueue.global(qos: .utility).async {
                    MusicKitManager.shared.cleanupTemporaryPlaybackPlaylists(keepingActiveQueue: false)
                }
            }
        }
    }

    public func resetCustomQueue() {
        lock.lock()
        defer { lock.unlock() }
        playbackGeneration &+= 1
        isStagingCloudTrack = false
        isActivelyStagingInBuffer = false
        activeLoadingStage = nil
        activeLoadingStartedAt = nil
        isUserPaused = false
        isCustomQueuePlayback = false
        activeCustomQueue.removeAll()
        originalCustomQueue.removeAll()
        activeCustomQueueIndex = 0
        activeCustomQueueName = nil
        isRadioPlayback = false
        activeStationName = nil
        repeatOnePinnedTrack = nil
        resolvingRadioDurationTrackKey = nil
        radioHistoryTracks.removeAll()
        lastRadioTrackSnapshot = nil
        currentOriginalPlaylistName = nil
        playbackQueueCache = nil
        currentTrackPlaybackConfirmed = false
        hasTriggeredAdvanceForCurrentTrack = false
        transitionPreviousTrackKey = nil
        activeTrackTitleVariants.removeAll()
        triedAlternateCloudSeedForCurrentTrack = false
        alternateCloudSeedAttemptCount = 0
        triedCloudSeedIdsForCurrentTrack.removeAll()
        lastWasPlayingCloud = false
        lastCloudPlayTime = nil
        lastKnownPosition = 0.0
        scheduledSmartTransitionStart = nil
        nativeQueuedUpcomingCatalogIds.removeAll()
        activeOverlapTransition = nil
        lastSkipTime = .distantPast
        lastConfirmedTrackTime = .distantPast
        lastForeignInterceptTime = .distantPast
        lastForeignInterceptKey = nil
        isShuffleQueueActive = false
        repeatMode = "off"
        activeShuffledQueue.removeAll()
        activeShuffledIndex = 0
        activeShuffledPlaylistName = nil
        activeSearchQuery = nil
        activeSearchCountry = nil
        activeSearchOffset = 0
        isFetchingNextSearchPage = false
        activeCuratorPrompt = nil
        isFetchingNextCuratorPage = false
        needsStaticMetadataRefresh = true
    }

    public func setSeekTarget(position: Double) {
        lock.lock()
        let now = Date()
        seekTargetPosition = position
        seekTargetDate = now
        lastSeekCommandTime = now
        activeOverlapTransition = nil
        if let smartStart = scheduledSmartTransitionStart, position >= smartStart - 0.25 {
            scheduledSmartTransitionStart = nil
        }
        lock.unlock()
    }

    public func clearSeekTarget() {
        lock.lock()
        seekTargetPosition = nil
        lock.unlock()
    }

    public func recordRadioTrackTransitionLocked(current: TrackInfo, stationName: String?) {
        let curName = current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let curArtist = current.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !curName.isEmpty else { return }
        let lowerName = curName.lowercased()
        let stLower = (stationName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowerName.hasPrefix("станция:") || lowerName.hasPrefix("station:") ||
            lowerName == "apple music radio" ||
            (!stLower.isEmpty && lowerName == stLower && (curArtist.isEmpty || curArtist == "Apple Music")) {
            return
        }

        if let prev = lastRadioTrackSnapshot {
            let sameSong = prev.name.localizedCaseInsensitiveCompare(curName) == .orderedSame &&
                (prev.artist.isEmpty || curArtist.isEmpty || prev.artist.localizedCaseInsensitiveCompare(curArtist) == .orderedSame)
            if sameSong {
                if current.hasArtwork && !prev.hasArtwork {
                    lastRadioTrackSnapshot = current
                } else if current.duration > 0 && prev.duration <= 0 {
                    lastRadioTrackSnapshot = current
                }
                return
            }
            var archived = prev
            archived.isCurrent = false
            radioHistoryTracks.removeAll {
                $0.name.localizedCaseInsensitiveCompare(archived.name) == .orderedSame &&
                $0.artist.localizedCaseInsensitiveCompare(archived.artist) == .orderedSame
            }
            radioHistoryTracks.insert(archived, at: 0)
            if radioHistoryTracks.count > 50 {
                radioHistoryTracks = Array(radioHistoryTracks.prefix(50))
            }
        }
        lastRadioTrackSnapshot = current
    }

    func persistPermanentlySavedKeysIfAllowed(_ keys: Set<String>) {
        guard !Self.isRunningUnderXCTest else { return }
        let sorted = keys.sorted()
        let bounded = sorted.count > 2000 ? Array(sorted.suffix(2000)) : sorted
        AppStorageProvider.shared.set(bounded, forKey: "AMRPermanentlySavedTrackKeys")
    }

    public func removePermanentlySavedTrack(id: String?, name: String?, artist: String?) {
        let cleanId = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanArtist = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normName = cleanName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        lock.lock()
        if !cleanId.isEmpty {
            permanentlySavedTrackKeys.remove("id:\(cleanId)")
        }
        if !cleanName.isEmpty {
            let exactKey = Self.normalizedSavedTrackKey(name: cleanName, artist: cleanArtist)
            permanentlySavedTrackKeys.remove(exactKey)
            if cleanArtist.isEmpty {
                let prefix = "\(normName)|"
                permanentlySavedTrackKeys = permanentlySavedTrackKeys.filter { !$0.hasPrefix(prefix) }
            }
        }
        let savedKeysSnap = permanentlySavedTrackKeys
        lock.unlock()
        persistPermanentlySavedKeysIfAllowed(savedKeysSnap)
    }

    public func isTrackPermanentlySaved(id: String?, name: String, artist: String) -> Bool {
        let cid = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = Self.normalizedSavedTrackKey(name: name, artist: artist)
        lock.lock()
        defer { lock.unlock() }
        if !cid.isEmpty && permanentlySavedTrackKeys.contains("id:\(cid)") {
            return true
        }
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && permanentlySavedTrackKeys.contains(key) {
            return true
        }
        return false
    }
}
