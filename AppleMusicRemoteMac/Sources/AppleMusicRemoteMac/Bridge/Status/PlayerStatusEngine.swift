//
//  PlayerStatusEngine.swift
//  AppleMusicRemoteMac
//
//  Aggregates player status from Music.app via atomic AppleScript queries, active custom queues,
//  radio playback, optimistic seek compensation, and real-time audio quality.
//

import Foundation

public struct StaticTrackMetadata: Sendable {
    public var dbId: Int
    public var persistentId: String
    public var name: String
    public var artist: String
    public var album: String
    public var duration: Double
    public var hasLoc: Bool
    public var kind: String
    public var bitRate: Int
    public var sampleRate: Int
    public var isFavorited: Bool
    public var currentPlaylistName: String
    public var shuffle: Bool
    public var repeatMode: String
    public var volume: Int
    public var fetchedAt: Date

    public init(
        dbId: Int,
        persistentId: String = "",
        name: String,
        artist: String,
        album: String,
        duration: Double,
        hasLoc: Bool,
        kind: String,
        bitRate: Int,
        sampleRate: Int,
        isFavorited: Bool,
        currentPlaylistName: String,
        shuffle: Bool,
        repeatMode: String,
        volume: Int,
        fetchedAt: Date = Date()
    ) {
        self.dbId = dbId
        self.persistentId = persistentId
        self.name = name
        self.artist = artist
        self.album = album
        self.duration = duration
        self.hasLoc = hasLoc
        self.kind = kind
        self.bitRate = bitRate
        self.sampleRate = sampleRate
        self.isFavorited = isFavorited
        self.currentPlaylistName = currentPlaylistName
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        self.volume = volume
        self.fetchedAt = fetchedAt
    }
}

public final class PlayerStatusEngine: @unchecked Sendable {
    public static let shared = PlayerStatusEngine()

    static let appleScriptFieldSeparator = "||AMR||"
    static let maxFavoritedOverrides = 512
    static let favoritedOverrideTTL: TimeInterval = 3600.0 * 6.0

    let statusLock = NSRecursiveLock()
    var lastCanonicalTrackKey: String?
    var cachedStaticMetadata: StaticTrackMetadata?
    var favoritedOverrides: [String: (isFavorited: Bool, updatedAt: TimeInterval)] = [:]
    var lastPulsePosition: Double = 0.0
    var _lastPollUsedLightweightPulse: Bool = false
    var streamTrackKey: String = ""
    var streamTrackZeroPosSince: Date? = nil
    var streamTrackHasAdvanced: Bool = false

    public var lastPollUsedLightweightPulse: Bool {
        statusLock.lock()
        defer { statusLock.unlock() }
        return _lastPollUsedLightweightPulse
    }

    public var cachedCurrentPlaylistName: String? {
        statusLock.lock()
        defer { statusLock.unlock() }
        return PlaybackStateStore.shared.withLock {
            cachedStaticMetadata?.currentPlaylistName
        }
    }

    public var cachedLiveTrackTitleAndArtist: (name: String, artist: String)? {
        statusLock.lock()
        defer { statusLock.unlock() }
        return PlaybackStateStore.shared.withLock {
            guard let meta = cachedStaticMetadata else { return nil }
            return (name: meta.name, artist: meta.artist)
        }
    }

    func lookupFavoritedOverrideLocked(for key: String) -> Bool? {
        guard let entry = favoritedOverrides[key] else { return nil }
        let now = Date().timeIntervalSince1970
        if now - entry.updatedAt > Self.favoritedOverrideTTL {
            favoritedOverrides.removeValue(forKey: key)
            return nil
        }
        return entry.isFavorited
    }

    func storeFavoritedOverrideLocked(_ isFav: Bool, for key: String) {
        let now = Date().timeIntervalSince1970
        if favoritedOverrides.count >= Self.maxFavoritedOverrides && favoritedOverrides[key] == nil {
            favoritedOverrides = favoritedOverrides.filter { now - $0.value.updatedAt <= Self.favoritedOverrideTTL }
            if favoritedOverrides.count >= Self.maxFavoritedOverrides {
                let evictCount = max(1, favoritedOverrides.count - (Self.maxFavoritedOverrides / 2))
                let oldestKeys = favoritedOverrides
                    .sorted { $0.value.updatedAt < $1.value.updatedAt }
                    .prefix(evictCount)
                    .map(\.key)
                for k in oldestKeys {
                    favoritedOverrides.removeValue(forKey: k)
                }
            }
        }
        favoritedOverrides[key] = (isFavorited: isFav, updatedAt: now)
    }

    public func currentFavoritedState() -> (isFavorited: Bool, name: String, artist: String) {
        statusLock.lock()
        defer { statusLock.unlock() }
        return PlaybackStateStore.shared.withLock {
            let name = cachedStaticMetadata?.name ?? PlaybackStateStore.shared.lastPlayerStatusCache?.status.track?.name ?? ""
            let artist = cachedStaticMetadata?.artist ?? PlaybackStateStore.shared.lastPlayerStatusCache?.status.track?.artist ?? ""
            let key = "\(artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()):\(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
            if !name.isEmpty, let override = lookupFavoritedOverrideLocked(for: key) {
                return (override, name, artist)
            }
            let cur = cachedStaticMetadata?.isFavorited ?? PlaybackStateStore.shared.lastPlayerStatusCache?.status.track?.favorited ?? false
            return (cur, name, artist)
        }
    }

    public func updateFavoritedState(_ isFav: Bool, name: String? = nil, artist: String? = nil) {
        statusLock.lock()
        defer { statusLock.unlock() }
        PlaybackStateStore.shared.withLock {
            let resolvedName = (name ?? cachedStaticMetadata?.name ?? PlaybackStateStore.shared.lastPlayerStatusCache?.status.track?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedArtist = (artist ?? cachedStaticMetadata?.artist ?? PlaybackStateStore.shared.lastPlayerStatusCache?.status.track?.artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !resolvedName.isEmpty {
                let key = "\(resolvedArtist.lowercased()):\(resolvedName.lowercased())"
                storeFavoritedOverrideLocked(isFav, for: key)
            }
            if var meta = cachedStaticMetadata {
                meta.isFavorited = isFav
                cachedStaticMetadata = meta
            }
            if var cached = PlaybackStateStore.shared.lastPlayerStatusCache {
                cached.status.track?.favorited = isFav
                PlaybackStateStore.shared.lastPlayerStatusCache = cached
            }
        }
    }

    public func updateCachedRepeatMode(_ mode: String) {
        statusLock.lock()
        defer { statusLock.unlock() }
        PlaybackStateStore.shared.withLock {
            if var meta = cachedStaticMetadata {
                meta.repeatMode = mode
                cachedStaticMetadata = meta
            }
            if var cached = PlaybackStateStore.shared.lastPlayerStatusCache {
                cached.status.repeatMode = mode
                PlaybackStateStore.shared.lastPlayerStatusCache = (Date(), cached.status)
            }
        }
    }

    public func updateCachedShuffle(_ enabled: Bool) {
        statusLock.lock()
        defer { statusLock.unlock() }
        PlaybackStateStore.shared.withLock {
            if var meta = cachedStaticMetadata {
                meta.shuffle = enabled
                cachedStaticMetadata = meta
            }
            if var cached = PlaybackStateStore.shared.lastPlayerStatusCache {
                cached.status.shuffle = enabled
                PlaybackStateStore.shared.lastPlayerStatusCache = (Date(), cached.status)
            }
        }
    }

    private init() {}

    public func seedStaticMetadataForTesting(_ meta: StaticTrackMetadata) {
        statusLock.lock()
        defer { statusLock.unlock() }
        PlaybackStateStore.shared.withLock {
            cachedStaticMetadata = meta
            lastPulsePosition = 0.0
            PlaybackStateStore.shared.needsStaticMetadataRefresh = false
        }
    }

    public func shouldUseLightweightPulse(rawState: String, rawPosition: Double, rawDbId: Int? = nil, rawTrackName: String? = nil) -> Bool {
        statusLock.lock()
        defer { statusLock.unlock() }
        return PlaybackStateStore.shared.withLock {
            guard !PlaybackStateStore.shared.needsStaticMetadataRefresh,
                  let meta = cachedStaticMetadata else {
                return false
            }
            if Date().timeIntervalSince(meta.fetchedAt) >= 30.0 {
                return false
            }
            let isStopped = (rawState.lowercased() == "stopped")
            if isStopped != meta.name.isEmpty {
                return false
            }
            if !isStopped && meta.duration <= 0 && rawPosition > 0.5 {
                return false
            }
            if let rDbId = rawDbId, rDbId != meta.dbId, (rDbId > 0 || meta.dbId > 0) {
                return false
            }
            if let rName = rawTrackName, !rName.isEmpty || !isStopped, rName != meta.name {
                return false
            }
            let hasSeekTarget = (PlaybackStateStore.shared.seekTargetPosition != nil && Date().timeIntervalSince(PlaybackStateStore.shared.seekTargetDate) < 4.0)
            if !hasSeekTarget && rawPosition < lastPulsePosition - 4.0 && lastPulsePosition > 8.0 {
                return false
            }
            return true
        }
    }

    public func computeOptimisticPosition(rawPosition: Double, isPlaying: Bool, duration: Double) -> Double {
        let (targetPos, targetDate) = PlaybackStateStore.shared.withLock {
            (PlaybackStateStore.shared.seekTargetPosition, PlaybackStateStore.shared.seekTargetDate)
        }

        guard let target = targetPos, Date().timeIntervalSince(targetDate) < 4.0 else {
            return rawPosition
        }

        let elapsed = isPlaying ? Date().timeIntervalSince(targetDate) : 0.0
        let expected = target + elapsed

        if abs(rawPosition - expected) < 1.2 {
            PlaybackStateStore.shared.clearSeekTarget()
            return rawPosition
        }

        return min(expected, duration > 0 ? duration : expected)
    }

    /// Determines whether `Music.app`'s reported `current playlist` name represents an Apple Music Radio station
    /// rather than a local/library user playlist.
    public static func isLikelyRadioPlaylistName(
        _ playlistName: String,
        activeStationName: String?,
        isCurrentlyRadio: Bool,
        hasLocalFile: Bool = false
    ) -> Bool {
        let trimmed = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return isCurrentlyRadio }
        let lower = trimmed.lowercased()
        if lower == "музыка" || lower == "music" || lower == "медиатека" || lower == "библиотека" || lower == "очередь amr" || lower == "буфер amr" {
            return false
        }
        let radioKeywords = [
            "станция", "station", "радио", "radio",
            "apple music 1", "apple music hits", "apple music country",
            "apple music chill", "apple music club", "apple music классика"
        ]
        if radioKeywords.contains(where: { lower.contains($0) }) {
            return true
        }
        if let active = activeStationName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !active.isEmpty,
           (lower == active || active.contains(lower) || lower.contains(active)) {
            return true
        }
        if isCurrentlyRadio && !hasLocalFile && !LibraryService.shared.hasCachedUserPlaylist(named: trimmed) {
            return true
        }
        return false
    }
}
