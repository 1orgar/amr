//
//  MusicBridge.swift
//  AppleMusicRemoteMac
//
//  Unified Facade providing a clean, backward-compatible API to macOS Music.app
//  by coordinating specialized modular services:
//  - MusicAppProvider (ScriptingBridge connection & process management)
//  - AppleScriptExecutor (thread-safe, timed Apple Events)
//  - AudioQualityDetector (real-time stream codec & sample-rate analysis)
//  - ArtworkService (memory cache, downscaling, Base64 Data URI)
//  - PlaybackStateStore (thread-safe active playback & queue state)
//  - PlaybackTransportController (transport actions: play, pause, seek, etc.)
//  - PlayerStatusEngine (PlayerStatus aggregation with optimistic position)
//  - QueueManager (queue generation, history, AMR queue, cloud auto-advance)
//  - PlaybackRouter (playlist, album, radio, cloud track, search & play routing)
//  - LibraryService (playlists, tracks, artists, albums, personal home feed)
//

import AppKit
import Foundation
import ScriptingBridge

public final class MusicBridge: @unchecked Sendable {
    public static let shared = MusicBridge()

    private init() {}

    // MARK: - Backward-Compatible State & Invalidation Helpers

    public var isShuffleQueueActive: Bool {
        PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isShuffleQueueActive }
    }

    public var latestUpcomingTracks: [TrackInfo] {
        PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.latestUpcomingTracks }
    }

    public var latestHistoryTracks: [TrackInfo] {
        PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.latestHistoryTracks }
    }

    public func invalidateStatusCache() {
        PlaybackStateStore.shared.invalidateStatusCache()
    }

    public func invalidateQueueCache() {
        PlaybackStateStore.shared.invalidateQueueCache()
    }

    public func getTrackMetadata(id: Int) -> (name: String, artist: String, album: String)? {
        PlaybackStateStore.shared.getTrackMetadata(id: id)
    }

    public func isRadioActive() -> Bool {
        PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isRadioPlayback }
    }

    public func getCurrentOriginalPlaylistName() -> String {
        PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.currentOriginalPlaylistName ?? "" }
    }

    // MARK: - Audio Quality Analysis

    public static func determineAudioQuality(kind: String, bitRate: Int, sampleRate: Int) -> String {
        AudioQualityDetector.determineAudioQuality(kind: kind, bitRate: bitRate, sampleRate: sampleRate)
    }

    public func getCurrentTrackAudioParams() -> (sampleRate: Double?, bitDepth: Int?, bitRate: Int?) {
        AudioQualityDetector.shared.getCurrentTrackAudioParams()
    }

    // MARK: - AppleScript Execution

    public func executeAppleScriptDescriptor(_ source: String) -> NSAppleEventDescriptor? {
        AppleScriptExecutor.shared.executeDescriptor(source)
    }

    public func runAppleScript(_ source: String) -> (Bool, String?) {
        AppleScriptExecutor.shared.run(source)
    }

    @discardableResult
    public func executeAppleScript(_ source: String) -> (success: Bool, output: String?) {
        AppleScriptExecutor.shared.execute(source)
    }

    // MARK: - Player Status

    public func getPlayerStatus() -> PlayerStatus {
        PlayerStatusEngine.shared.getPlayerStatus()
    }

    // MARK: - Player Transport Controls

    public func play() -> Bool {
        PlaybackTransportController.shared.play()
    }

    public func pause() -> Bool {
        PlaybackTransportController.shared.pause()
    }

    public func stop() -> Bool {
        PlaybackTransportController.shared.stop()
    }

    public func playPause() -> Bool {
        PlaybackTransportController.shared.playPause()
    }

    public func nextTrack() -> Bool {
        PlaybackTransportController.shared.nextTrack()
    }

    public func previousTrack(forceTrackChange: Bool = false) -> Bool {
        PlaybackTransportController.shared.previousTrack(forceTrackChange: forceTrackChange)
    }

    public func seek(to position: Double) -> Bool {
        PlaybackTransportController.shared.seek(to: position)
    }

    public func setVolume(_ volume: Int) -> Bool {
        PlaybackTransportController.shared.setVolume(volume)
    }

    @discardableResult
    public func checkAndEnforceVolumeLock() -> Bool {
        PlaybackTransportController.shared.checkAndEnforceVolumeLock()
    }

    public func setShuffle(_ enabled: Bool) -> Bool {
        PlaybackTransportController.shared.setShuffle(enabled)
    }

    public func setRepeat(mode: String) -> Bool {
        PlaybackTransportController.shared.setRepeat(mode: mode)
    }

    public func toggleFavorite() -> Bool {
        PlaybackTransportController.shared.toggleFavorite()
    }

    public func setFavorite(_ fav: Bool) -> Bool {
        PlaybackTransportController.shared.setFavorite(fav)
    }

    public func addCurrentTrackToLibrary() -> Bool {
        PlaybackTransportController.shared.addCurrentTrackToLibrary()
    }

    // MARK: - Audio Ducking

    @discardableResult
    public func activateDucking(reductionPercent: Double = 80.0, timeout: Double? = nil) -> (success: Bool, duckedVolume: Int, originalVolume: Int) {
        AudioDuckingController.shared.activate(reductionPercent: reductionPercent, timeout: timeout)
    }

    @discardableResult
    public func deactivateDucking() -> (success: Bool, restoredVolume: Int) {
        AudioDuckingController.shared.deactivate()
    }

    public var isAudioDucked: Bool {
        AudioDuckingController.shared.isDucked
    }

    public func getAudioDuckingStatus() -> (isDucked: Bool, originalVolume: Int?, currentVolume: Int) {
        AudioDuckingController.shared.getStatus()
    }

    // MARK: - Queue & History Management

    public func getRecentlyPlayed(limit: Int = 30) -> [TrackInfo] {
        QueueManager.shared.getRecentlyPlayed(limit: limit)
    }

    public func getPlaybackQueue() async -> PlaybackQueueInfo {
        await QueueManager.shared.getPlaybackQueue()
    }

    public func enqueueTrack(_ track: TrackInfo, playNext: Bool) async -> Bool {
        await QueueManager.shared.enqueueTrack(track, playNext: playNext)
    }

    public func enqueueTracks(_ tracks: [TrackInfo], playNext: Bool) async -> Bool {
        await QueueManager.shared.enqueueTracks(tracks, playNext: playNext)
    }

    public func removeQueueTrack(at index: Int) async -> Bool {
        await QueueManager.shared.removeQueueTrack(at: index)
    }

    public func clearUpcomingQueue() async -> Bool {
        await QueueManager.shared.clearUpcomingQueue()
    }

    public func playQueueIndex(_ index: Int) async -> Bool {
        await QueueManager.shared.playQueueIndex(index)
    }

    public func playHistoryTrack(name: String, artist: String) async -> Bool {
        await QueueManager.shared.playHistoryTrack(name: name, artist: artist)
    }

    public func playHistoryIndex(_ index: Int) async -> Bool {
        await QueueManager.shared.playHistoryIndex(index)
    }

    public func playRecentTracks(shuffle: Bool) async -> Bool {
        await QueueManager.shared.playRecentTracks(shuffle: shuffle)
    }

    public func checkAndAutoAdvanceCloudQueue() {
        QueueManager.shared.checkAndAutoAdvanceCloudQueue()
    }

    // MARK: - Playback Routing

    public func playPlaylist(name: String, trackId: Int? = nil, trackIndex: Int? = nil, shuffle: Bool = false) -> Bool {
        PlaybackRouter.shared.playPlaylist(name: name, trackId: trackId, trackIndex: trackIndex, shuffle: shuffle)
    }

    public func playStation(url: String, name: String) async -> Bool {
        await PlaybackRouter.shared.playStation(url: url, name: name)
    }

    public func playStation(url: String, name: String, type: String, trackTitle: String, artistName: String) async -> Bool {
        await PlaybackRouter.shared.playStation(url: url, name: name, type: type, trackTitle: trackTitle, artistName: artistName)
    }

    public func playAlbumWithTracks(tracks: [TrackInfo], name: String, artist: String, startIndex: Int = 0, shuffle: Bool = false) async -> Bool {
        await PlaybackRouter.shared.playAlbumWithTracks(tracks: tracks, name: name, artist: artist, startIndex: startIndex, shuffle: shuffle)
    }

    public func playAlbum(id: String, name: String, artist: String, startIndex: Int = 0, shuffle: Bool = false) async -> Bool {
        await PlaybackRouter.shared.playAlbum(id: id, name: name, artist: artist, startIndex: startIndex, shuffle: shuffle)
    }

    public func playHeroCard(index: Int, name: String, artist: String? = nil, cardId: String?, url: String?, type: String? = nil) async -> Bool {
        await PlaybackRouter.shared.playHeroCard(index: index, name: name, artist: artist, cardId: cardId, url: url, type: type)
    }

    public func playCloud(url: String?, id: String?, name: String?, artist: String?, numericId: Int? = nil, isLocal: Bool? = nil) async -> Bool {
        await PlaybackRouter.shared.playCloud(url: url, id: id, name: name, artist: artist, numericId: numericId, isLocal: isLocal)
    }

    public func playCloudSync(url: String?, id: String?, name: String?, artist: String?) -> Bool {
        PlaybackRouter.shared.playCloudSync(url: url, id: id, name: name, artist: artist)
    }

    public func openMusicUrl(_ urlString: String) -> Bool {
        PlaybackRouter.shared.openMusicUrl(urlString)
    }

    public func playCustomTracks(_ tracks: [TrackInfo], startIndex: Int, shuffle: Bool, queueName: String?) -> Bool {
        PlaybackRouter.shared.playCustomTracks(tracks, startIndex: startIndex, shuffle: shuffle, queueName: queueName)
    }

    public func playSearchResults(tracks: [TrackInfo], startIndex: Int = 0, shuffle: Bool, queueName: String? = nil, query: String? = nil, curatorPrompt: String? = nil) async -> Bool {
        await PlaybackRouter.shared.playSearchResults(tracks: tracks, startIndex: startIndex, shuffle: shuffle, queueName: queueName, query: query, curatorPrompt: curatorPrompt)
    }

    public func appendTracksToAMRQueue(tracks: [TrackInfo]) async -> Bool {
        await PlaybackRouter.shared.appendTracksToAMRQueue(newTracks: tracks)
    }

    public func searchAndPlayDetailed(query: String) async -> PlaybackRouter.SearchAndPlayResult {
        await PlaybackRouter.shared.searchAndPlayDetailed(query: query)
    }

    public func searchAndPlay(query: String) async -> Bool {
        await PlaybackRouter.shared.searchAndPlay(query: query)
    }

    @discardableResult
    public func syncCurrentTrackToAMRQueue(clearQueue: Bool = false) -> Bool {
        PlaybackRouter.shared.syncCurrentTrackToAMRQueue(clearQueue: clearQueue)
    }

    // MARK: - Library & Playlist Services

    public func getPlaylists(forceRefresh: Bool = false) -> [PlaylistInfo] {
        LibraryService.shared.getPlaylists(forceRefresh: forceRefresh)
    }

    public func getPlaylistsWithArtworks() async -> [PlaylistInfo] {
        await LibraryService.shared.getPlaylistsWithArtworks()
    }

    public func getPlaylistTracks(name: String) -> [TrackInfo] {
        LibraryService.shared.getPlaylistTracks(name: name)
    }

    public func updatePlaylistTracksCache(name: String, tracks: [TrackInfo]) {
        LibraryService.shared.updatePlaylistTracksCache(name: name, tracks: tracks)
    }

    public func invalidatePlaylistCache(name: String) {
        LibraryService.shared.invalidatePlaylistCache(name: name)
    }

    public func getCurrentPlaylistTracks() -> [TrackInfo] {
        LibraryService.shared.getCurrentPlaylistTracks()
    }

    public func getLibrarySongs(forceRefresh: Bool = false) -> [TrackInfo] {
        LibraryService.shared.getLibrarySongs(forceRefresh: forceRefresh)
    }

    public func getTopPlayedTracks(limit: Int = 25) -> [TrackInfo] {
        LibraryService.shared.getTopPlayedTracks(limit: limit)
    }

    public func getLibraryArtists(forceRefresh: Bool = false) -> [ArtistInfo] {
        LibraryService.shared.getLibraryArtists(forceRefresh: forceRefresh)
    }

    public func getLibraryArtistDetail(artist: String) -> ArtistLibraryDetailResponse {
        LibraryService.shared.getLibraryArtistDetail(artist: artist)
    }

    public func getLibraryAlbums(forceRefresh: Bool = false) -> [AlbumInfo] {
        LibraryService.shared.getLibraryAlbums(forceRefresh: forceRefresh)
    }

    public func getLibraryAlbumTracks(album: String, artist: String) -> [TrackInfo] {
        LibraryService.shared.getLibraryAlbumTracks(album: album, artist: artist)
    }

    public func getLibraryRecent(
        limitAlbums: Int = 30,
        limitSongs: Int = 60,
        forceRefresh: Bool = false
    ) -> LibraryRecentResponse {
        LibraryService.shared.getLibraryRecent(
            limitAlbums: limitAlbums,
            limitSongs: limitSongs,
            forceRefresh: forceRefresh
        )
    }

    public func getLibraryRecentMerged(
        limitAlbums: Int = 30,
        limitSongs: Int = 60,
        forceRefresh: Bool = false
    ) async -> LibraryRecentResponse {
        if forceRefresh {
            LibraryService.shared.invalidateLibrarySongsCache()
            MusicKitManager.shared.invalidateUserLibraryAlbumsCache()
        }
        async let cloudTask = MusicKitManager.shared.fetchUserLibraryAlbums(forceRefresh: forceRefresh)
        _ = LibraryService.shared.getLibrarySongs(forceRefresh: false)
        _ = await cloudTask
        return LibraryService.shared.getLibraryRecent(
            limitAlbums: limitAlbums,
            limitSongs: limitSongs,
            forceRefresh: false
        )
    }

    public func getLibraryArtistsMerged(forceRefresh: Bool = false) async -> [ArtistInfo] {
        if forceRefresh {
            LibraryService.shared.invalidateLibrarySongsCache()
            MusicKitManager.shared.invalidateUserLibraryAlbumsCache()
        }
        async let cloudTask = MusicKitManager.shared.fetchUserLibraryAlbums(forceRefresh: forceRefresh)
        _ = LibraryService.shared.getLibrarySongs(forceRefresh: false)
        _ = await cloudTask
        return LibraryService.shared.getLibraryArtists(forceRefresh: false)
    }

    public func getLibraryArtistDetailMerged(artist: String) async -> ArtistLibraryDetailResponse {
        if MusicKitManager.shared.getCachedUserLibraryAlbumsSnapshot().isEmpty {
            async let cloudTask = MusicKitManager.shared.fetchUserLibraryAlbums(forceRefresh: false)
            _ = LibraryService.shared.getLibrarySongs(forceRefresh: false)
            _ = await cloudTask
        }
        return LibraryService.shared.getLibraryArtistDetail(artist: artist)
    }

    public func getLibrarySongsMerged(forceRefresh: Bool = false) async -> [TrackInfo] {
        if forceRefresh {
            LibraryService.shared.invalidateLibrarySongsCache()
            MusicKitManager.shared.invalidateUserLibraryAlbumsCache()
        }
        async let cloudTask = MusicKitManager.shared.fetchUserLibraryAlbums(forceRefresh: forceRefresh)
        _ = LibraryService.shared.getLibrarySongs(forceRefresh: false)
        _ = await cloudTask
        return LibraryService.shared.getLibrarySongs(forceRefresh: false)
    }

    public func getLibraryAlbumsMerged(forceRefresh: Bool = false) async -> [AlbumInfo] {
        if forceRefresh {
            LibraryService.shared.invalidateLibrarySongsCache()
            MusicKitManager.shared.invalidateUserLibraryAlbumsCache()
        }
        async let cloudTask = MusicKitManager.shared.fetchUserLibraryAlbums(forceRefresh: forceRefresh)
        let localAlbums = LibraryService.shared.getLibraryAlbums()
        let cloudAlbums = await cloudTask
        let recentAlbums = MusicKitManager.shared.getRecentlyAddedLibraryAlbumsSnapshot()
        return Self.mergeLibraryAlbums(cloud: cloudAlbums, local: localAlbums, recentlyAdded: recentAlbums)
    }

    public static func mergeLibraryAlbums(
        cloud: [AlbumInfo],
        local: [AlbumInfo],
        recentlyAdded: [AlbumInfo] = []
    ) -> [AlbumInfo] {
        var consumedLocalIndices = Set<Int>()
        var result: [AlbumInfo] = []
        result.reserveCapacity(cloud.count + local.count)
        let stagedAlbums = PlaybackStateStore.shared.stagedAlbumCandidatesSnapshot()

        for var c in cloud {
            let localMatchIdx = local.indices.first(where: { idx in
                !consumedLocalIndices.contains(idx) &&
                MusicKitManager.albumMatches(c.name, c.artist, local[idx].name, local[idx].artist)
            })
            if localMatchIdx == nil,
               !MusicKitManager.shared.isExplicitlyAddedAlbumInSession(albumId: c.id, name: c.name, artist: c.artist),
               stagedAlbums.contains(where: { MusicKitManager.albumMatches(c.name, c.artist, $0.album, $0.artist) }) {
                continue
            }
            c.inLibrary = true
            if c.catalogAlbumId == nil, (Int(c.id) ?? 0) >= 10_000_000 {
                c.catalogAlbumId = c.id
            }
            if c.libraryTrackCount == nil, let tc = c.trackCount, tc > 0 {
                c.libraryTrackCount = tc
            }
            if !c.artwork.hasPrefix("http"),
               let cachedArt = MusicKitManager.shared.getCachedAlbumArtwork(album: c.name, artist: c.artist),
               !cachedArt.isEmpty {
                c.artwork = cachedArt
            }
            if let matchIdx = localMatchIdx {
                consumedLocalIndices.insert(matchIdx)
                let loc = local[matchIdx]
                if (c.artwork.isEmpty || (!c.artwork.hasPrefix("http") && loc.artwork.hasPrefix("http"))) && !loc.artwork.isEmpty {
                    c.artwork = loc.artwork
                }
                let maxTracks = max(c.trackCount ?? 0, loc.trackCount ?? 0)
                if maxTracks > 0 {
                    c.trackCount = maxTracks
                }
                let maxLibTracks = max(c.libraryTrackCount ?? 0, loc.libraryTrackCount ?? loc.trackCount ?? 0)
                if maxLibTracks > 0 {
                    c.libraryTrackCount = maxLibTracks
                }
                if let locDate = loc.dateAdded, locDate > (c.dateAdded ?? 0) {
                    c.dateAdded = locDate
                }
                if let catCount = c.catalogTrackCount, catCount > 0, let libCount = c.libraryTrackCount {
                    c.isCompleteInLibrary = (libCount >= catCount)
                }
            }
            result.append(c)
        }

        for (idx, var loc) in local.enumerated() where !consumedLocalIndices.contains(idx) {
            loc.inLibrary = true
            if loc.libraryTrackCount == nil {
                loc.libraryTrackCount = loc.trackCount
            }
            if !loc.artwork.hasPrefix("http"),
               let cachedArt = MusicKitManager.shared.getCachedAlbumArtwork(album: loc.name, artist: loc.artist),
               !cachedArt.isEmpty {
                loc.artwork = cachedArt
            }
            result.append(loc)
        }

        for r in recentlyAdded.reversed() {
            if let existingIdx = result.firstIndex(where: { item in
                (!r.id.isEmpty && !item.id.isEmpty && r.id.caseInsensitiveCompare(item.id) == .orderedSame) ||
                MusicKitManager.albumMatches(r.name, r.artist, item.name, item.artist)
            }) {
                var promoted = result.remove(at: existingIdx)
                if (Int(promoted.id) ?? 0) < 10_000_000, (Int(r.id) ?? 0) >= 10_000_000 {
                    promoted.id = r.id
                }
                if promoted.catalogAlbumId == nil, let cid = r.catalogAlbumId {
                    promoted.catalogAlbumId = cid
                }
                if (promoted.artwork.isEmpty || (!promoted.artwork.hasPrefix("http") && r.artwork.hasPrefix("http"))) && !r.artwork.isEmpty {
                    promoted.artwork = r.artwork
                }
                if (promoted.trackCount ?? 0) == 0, let rc = r.trackCount, rc > 0 {
                    promoted.trackCount = rc
                }
                if let rDate = r.dateAdded, rDate > (promoted.dateAdded ?? 0) {
                    promoted.dateAdded = rDate
                }
                if r.isCompleteInLibrary == true {
                    promoted.isCompleteInLibrary = true
                    if let catCount = r.catalogTrackCount {
                        promoted.catalogTrackCount = catCount
                        promoted.libraryTrackCount = max(promoted.libraryTrackCount ?? 0, catCount)
                    }
                }
                promoted.inLibrary = true
                result.insert(promoted, at: 0)
            } else {
                var fresh = r
                fresh.inLibrary = true
                result.insert(fresh, at: 0)
            }
        }

        return result
    }

    public func getPersonalHomeFeed() -> [String: Any] {
        LibraryService.shared.getPersonalHomeFeed()
    }

    public func addToLibrary(id: String? = nil, trackId: Int?, name: String?, artist: String?, url: String?) -> Bool {
        LibraryService.shared.addToLibrary(id: id, trackId: trackId, name: name, artist: artist, url: url)
    }

    public func addPlaylistToLibrary(playlistId: String, name: String = "", tracks: [TrackInfo] = []) async -> Bool {
        await MusicKitManager.shared.addPlaylistToLibrary(playlistId: playlistId, name: name, tracks: tracks)
    }

    public func addAlbumToLibrary(albumId: String, name: String, artist: String, tracks: [TrackInfo] = []) async -> Bool {
        await MusicKitManager.shared.addAlbumToLibrary(albumId: albumId, name: name, artist: artist, tracks: tracks)
    }

    public func removeTrackFromLibrary(
        id: String? = nil,
        trackId: Int? = nil,
        name: String? = nil,
        artist: String? = nil,
        album: String? = nil
    ) -> Int {
        LibraryService.shared.removeTrackFromLibrary(
            id: id,
            trackId: trackId,
            name: name,
            artist: artist,
            album: album
        )
    }

    public func removeAlbumFromLibrary(albumId: String? = nil, name: String, artist: String = "") -> Int {
        LibraryService.shared.removeAlbumFromLibrary(albumId: albumId, name: name, artist: artist)
    }

    public func removeArtistFromLibrary(artist: String) -> Int {
        LibraryService.shared.removeArtistFromLibrary(artist: artist)
    }

    public func removePlaylistFromLibrary(
        playlistId: String? = nil,
        name: String
    ) async -> Bool {
        await LibraryService.shared.removePlaylistFromLibrary(
            playlistId: playlistId,
            name: name
        )
    }

    // MARK: - Artwork Services

    public func getCurrentTrackArtworkDataUri() -> String {
        ArtworkService.shared.getCurrentTrackArtworkDataUri()
    }

    public func getCurrentTrackArtwork() -> Data? {
        ArtworkService.shared.getCurrentTrackArtwork()
    }

    public func getTrackArtwork(
        id: Int,
        album: String = "",
        artist: String = "",
        skipIfContended: Bool = false
    ) -> Data? {
        ArtworkService.shared.getTrackArtwork(
            id: id,
            album: album,
            artist: artist,
            skipIfContended: skipIfContended
        )
    }

    public func getTrackArtworkDataUri(id: Int) -> String {
        ArtworkService.shared.getTrackArtworkDataUri(id: id)
    }

    public func findLocalTrackArtwork(name: String, artist: String) -> String? {
        ArtworkService.shared.findLocalTrackArtwork(name: name, artist: artist)
    }

    public func getPlaylistArtwork(name: String) -> Data? {
        ArtworkService.shared.getPlaylistArtwork(name: name)
    }

    public func getPlaylistArtworkDataUri(name: String) -> String {
        ArtworkService.shared.getPlaylistArtworkDataUri(name: name)
    }

    public func getPlaylistArtworkThumbnailUri(name: String) -> String {
        ArtworkService.shared.getPlaylistArtworkThumbnailUri(name: name)
    }

    public func enrichTracksArtwork(_ tracks: [TrackInfo], limit: Int = 75) async -> [TrackInfo] {
        await ArtworkService.shared.enrichTracksArtwork(tracks, limit: limit)
    }
}
