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

    public func previousTrack() -> Bool {
        PlaybackTransportController.shared.previousTrack()
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

    public func playCustomTracks(_ tracks: [TrackInfo], startIndex: Int, shuffle: Bool, queueName: String?) -> Bool {
        PlaybackRouter.shared.playCustomTracks(tracks, startIndex: startIndex, shuffle: shuffle, queueName: queueName)
    }

    public func playSearchResults(tracks: [TrackInfo], startIndex: Int = 0, shuffle: Bool) async -> Bool {
        await PlaybackRouter.shared.playSearchResults(tracks: tracks, startIndex: startIndex, shuffle: shuffle)
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

    public func getPlaylists() -> [PlaylistInfo] {
        LibraryService.shared.getPlaylists()
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

    public func getLibrarySongs() -> [TrackInfo] {
        LibraryService.shared.getLibrarySongs()
    }

    public func getLibraryArtists() -> [ArtistInfo] {
        LibraryService.shared.getLibraryArtists()
    }

    public func getLibraryAlbums() -> [AlbumInfo] {
        LibraryService.shared.getLibraryAlbums()
    }

    public func getPersonalHomeFeed() -> [String: Any] {
        LibraryService.shared.getPersonalHomeFeed()
    }

    public func addToLibrary(trackId: Int?, name: String?, artist: String?, url: String?) -> Bool {
        LibraryService.shared.addToLibrary(trackId: trackId, name: name, artist: artist, url: url)
    }

    // MARK: - Artwork Services

    public func getCurrentTrackArtworkDataUri() -> String {
        ArtworkService.shared.getCurrentTrackArtworkDataUri()
    }

    public func getCurrentTrackArtwork() -> Data? {
        ArtworkService.shared.getCurrentTrackArtwork()
    }

    public func getTrackArtwork(id: Int) -> Data? {
        ArtworkService.shared.getTrackArtwork(id: id)
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
