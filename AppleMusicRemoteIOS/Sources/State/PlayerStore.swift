//
//  PlayerStore.swift
//  AppleMusicRemoteIOS
//
//  Central state container for real-time playback, media library, and stations
//

import Combine
import Foundation
import SwiftUI

public final class PlayerStore: ObservableObject, @unchecked Sendable, WebSocketClientDelegate {
    public static let shared = PlayerStore()

    // Connection State
    @Published public var isConnected: Bool = false
    @Published public var currentServer: ServerHost?
    @Published public var showDiscoverySheet: Bool = false
    @Published public var selectedTab: Int = 2

    // Playback State
    @Published public var playerState: PlayerState = .stopped
    @Published public var position: Double = 0.0
    @Published public var duration: Double = 0.0
    @Published public var volume: Double = 50.0
    @Published public var isMuted: Bool = false
    private var preMuteVolume: Double = 50.0
    @Published public var isShuffle: Bool = false
    @Published public var repeatMode: String = "off"
    @Published public var audioQuality: String = "Lossless (ALAC 24-bit/48kHz)"
    @Published public var isRadio: Bool = false
    @Published public var currentTrack: TrackItem?
    @Published public var currentPlaylistName: String = "Музыка"

    // Queue State
    @Published public var upcomingTracks: [TrackItem] = []
    @Published public var fullQueueTracks: [TrackItem] = []
    @Published public var historyTracks: [TrackItem] = []

    // Library State
    @Published public var playlists: [PlaylistItem] = []
    @Published public var selectedPlaylist: PlaylistItem? = nil
    @Published public var isLoadingPlaylists: Bool = false
    @Published public var playlistTracks: [String: [TrackItem]] = [:]
    @Published public var isLoadingPlaylistTracks: Bool = false
    @Published public var artists: [ArtistItem] = []
    @Published public var albums: [AlbumItem] = []
    @Published public var songs: [TrackItem] = []

    // Stations & Cloud State
    @Published public var curatedStations: [StationItem] = []
    @Published public var topChartSongs: [TrackItem] = []
    @Published public var topChartAlbums: [AlbumItem] = []
    @Published public var selectedCountry: String = "ru"

    // Search State
    @Published public var searchResultsTracks: [TrackItem] = []
    @Published public var searchResultsArtists: [ArtistItem] = []
    @Published public var searchResultsAlbums: [AlbumItem] = []
    @Published public var isSearching: Bool = false

    // Active Action Sheet Track
    @Published public var actionSheetTrack: TrackItem?

    // Volume Drag & Throttle State
    @Published public var isDraggingVolume: Bool = false
    private var lastVolumeSendTime: Date = .distantPast
    private var pendingVolumeWorkItem: DispatchWorkItem?

    // Local position tick timer
    private var positionTimer: Timer?
    private var lastSyncTime: Date = Date()
    private var basePosition: Double = 0.0
    private var lastPlayPauseTapTime: Date = .distantPast

    private init() {
        URLCache.shared = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024)
        WebSocketClient.shared.delegate = self
        startPositionTicker()
        connectToDefaultOrScan()
    }

    // MARK: - Auto Connection via Bonjour

    public func connectToDefaultOrScan() {
        #if targetEnvironment(simulator)
        self.connect(host: "127.0.0.1", port: 8080)
        #else
        BonjourBrowser.shared.startDiscovery()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self else { return }
            if let first = BonjourBrowser.shared.discoveredServers.first, !first.ipAddress.contains(" ") {
                self.connect(to: first)
            } else {
                self.connect(host: "127.0.0.1", port: 8080)
            }
        }
        #endif
    }

    public func connect(to server: ServerHost) {
        self.currentServer = server
        let host = server.ipAddress.contains(" ") ? "127.0.0.1" : server.ipAddress
        WebSocketClient.shared.connect(host: host, port: server.port)
    }

    public func connect(host: String, port: Int = 8080) {
        let cleanHost = host.contains(" ") ? "127.0.0.1" : host
        let server = ServerHost(id: cleanHost, name: "Mac", hostName: cleanHost, port: port, ipAddress: cleanHost)
        self.currentServer = server
        WebSocketClient.shared.connect(host: cleanHost, port: port)
    }

    public func disconnect() {
        WebSocketClient.shared.disconnect()
        currentServer = nil
    }

    // MARK: - Remote Control Actions

    public func togglePlayPause() {
        AMRHaptics.medium()
        self.playerState = (self.playerState == .playing) ? .paused : .playing
        self.lastPlayPauseTapTime = Date()
        WebSocketClient.shared.sendCommand("play_pause")
    }

    public func stop() {
        AMRHaptics.medium()
        self.playerState = .stopped
        self.position = 0
        self.basePosition = 0
        WebSocketClient.shared.sendCommand("stop")
    }

    public func nextTrack() {
        AMRHaptics.light()
        self.position = 0
        self.basePosition = 0
        self.lastSyncTime = Date()
        WebSocketClient.shared.sendCommand("next")
    }

    public func previousTrack() {
        AMRHaptics.light()
        self.position = 0
        self.basePosition = 0
        self.lastSyncTime = Date()
        WebSocketClient.shared.sendCommand("previous")
    }

    public func seek(to seconds: Double) {
        self.position = seconds
        self.basePosition = seconds
        self.lastSyncTime = Date()
        WebSocketClient.shared.sendCommand("seek", payload: ["position": seconds])
    }

    public func setVolumeThrottled(_ newVol: Double) {
        self.volume = newVol
        let now = Date()
        if now.timeIntervalSince(lastVolumeSendTime) >= 0.08 {
            lastVolumeSendTime = now
            pendingVolumeWorkItem?.cancel()
            WebSocketClient.shared.sendCommand("set_volume", payload: ["volume": Int(newVol)])
        } else {
            pendingVolumeWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.lastVolumeSendTime = Date()
                WebSocketClient.shared.sendCommand("set_volume", payload: ["volume": Int(newVol)])
            }
            pendingVolumeWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
        }
    }

    public func setVolume(_ newVol: Double) {
        self.volume = newVol
        pendingVolumeWorkItem?.cancel()
        lastVolumeSendTime = Date()
        WebSocketClient.shared.sendCommand("set_volume", payload: ["volume": Int(newVol)])
    }

    public func toggleMute() {
        AMRHaptics.selection()
        if isMuted {
            isMuted = false
            setVolume(preMuteVolume > 0 ? preMuteVolume : 50)
        } else {
            isMuted = true
            preMuteVolume = volume
            setVolume(0)
        }
    }

    public func toggleShuffle() {
        AMRHaptics.selection()
        let next = !isShuffle
        isShuffle = next
        WebSocketClient.shared.sendCommand("set_shuffle", payload: ["enabled": next])
    }

    public func toggleFavorite() {
        AMRHaptics.success()
        WebSocketClient.shared.sendCommand("favorite")
    }

    // MARK: - Playback Commands

    public func playPlaylist(name: String, trackId: Int? = nil, trackIndex: Int? = nil, shuffle: Bool = false) {
        AMRHaptics.medium()
        NSLog("[PlayerStore] playPlaylist called: name=%@, trackId=%@, trackIndex=%@, shuffle=%@", name, String(describing: trackId), String(describing: trackIndex), String(shuffle))
        self.currentPlaylistName = name
        self.isShuffle = shuffle

        var payload: [String: Any] = ["playlist": name, "name": name, "shuffle": shuffle]
        if let tid = trackId, tid > 0 { payload["track_id"] = tid }
        if let idx = trackIndex, idx > 0 { payload["track_index"] = idx }
        WebSocketClient.shared.sendCommand("play_playlist", payload: payload)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.loadQueue()
        }
    }

    public func playHistoryTrack(_ track: TrackItem) {
        AMRHaptics.medium()
        WebSocketClient.shared.sendCommand("play_history_track", payload: [
            "name": track.name,
            "artist": track.artist
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.loadQueue()
        }
    }

    public func playHistoryIndex(_ index: Int) {
        AMRHaptics.medium()
        WebSocketClient.shared.sendCommand("play_history_index", payload: ["index": index])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.loadQueue()
        }
    }

    public func playStation(_ station: StationItem) {
        AMRHaptics.medium()
        WebSocketClient.shared.sendCommand("play_station", payload: [
            "url": station.url,
            "name": station.name
        ])
    }

    public func playCloudTrack(_ track: TrackItem) {
        AMRHaptics.medium()
        WebSocketClient.shared.sendCommand("play_cloud", payload: [
            "url": track.url ?? "",
            "name": track.name,
            "artist": track.artist,
            "id": track.id
        ])
    }

    public func addTrackToLibrary(_ track: TrackItem) {
        AMRHaptics.success()
        WebSocketClient.shared.sendCommand("add_to_library", payload: [
            "id": track.id,
            "name": track.name,
            "artist": track.artist
        ])
    }

    public func queuePlayNext(_ track: TrackItem) {
        AMRHaptics.success()
        if let data = try? JSONEncoder().encode(track),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            WebSocketClient.shared.sendCommand("queue_play_next", payload: ["track": dict])
        }
    }

    public func queueAddToEnd(_ track: TrackItem) {
        AMRHaptics.success()
        if let data = try? JSONEncoder().encode(track),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            WebSocketClient.shared.sendCommand("queue_add", payload: ["track": dict])
        }
    }

    public func queueRemove(at index: Int) {
        AMRHaptics.light()
        if index >= 0 && index < upcomingTracks.count {
            upcomingTracks.remove(at: index)
        }
        WebSocketClient.shared.sendCommand("queue_remove", payload: ["index": index])
    }

    public func queueClear() {
        AMRHaptics.warning()
        upcomingTracks.removeAll()
        WebSocketClient.shared.sendCommand("queue_clear")
    }

    public func queuePlayIndex(_ index: Int) {
        AMRHaptics.medium()
        WebSocketClient.shared.sendCommand("queue_play_index", payload: ["index": index])
    }

    // MARK: - Data Fetching
    
    public func loadQueue() {
        WebSocketClient.shared.sendCommand("get_queue")
    }

    public func loadLibraryPlaylists() {
        self.isLoadingPlaylists = true
        WebSocketClient.shared.sendCommand("get_playlists")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            if self?.isLoadingPlaylists == true {
                self?.isLoadingPlaylists = false
            }
        }
    }

    public func loadPlaylistTracks(name: String) {
        isLoadingPlaylistTracks = true
        WebSocketClient.shared.sendCommand("get_playlist_tracks", payload: ["name": name, "playlist": name])
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            if self?.isLoadingPlaylistTracks == true {
                self?.isLoadingPlaylistTracks = false
            }
        }
    }

    public func loadLibrarySongs() {
        WebSocketClient.shared.sendCommand("get_songs")
    }

    public func loadLibraryArtists() {
        WebSocketClient.shared.sendCommand("get_artists")
    }

    public func loadStations() {
        WebSocketClient.shared.sendCommand("get_stations", payload: ["country": selectedCountry])
    }

    public func loadTopCharts() {
        WebSocketClient.shared.sendCommand("get_catalog_charts", payload: ["country": selectedCountry])
    }

    public func performSearch(query: String, scope: String = "all") {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResultsTracks = []
            searchResultsArtists = []
            searchResultsAlbums = []
            isSearching = false
            return
        }
        isSearching = true
        WebSocketClient.shared.sendCommand("search", payload: [
            "query": query,
            "scope": scope,
            "source": scope,
            "country": selectedCountry
        ])
    }

    // MARK: - WebSocketClientDelegate

    public func webSocketClient(_ client: WebSocketClient, didChangeConnectionState connected: Bool) {
        self.isConnected = connected
        if connected {
            self.loadQueue()
            self.loadLibraryPlaylists()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self = self, self.isConnected else { return }
                self.loadStations()
                self.loadTopCharts()
            }
        }
    }

    public func webSocketClient(_ client: WebSocketClient, didUpdateStatus payload: PlayerStatusPayload) {
        self.isConnected = true
        let timeSinceTap = Date().timeIntervalSince(lastPlayPauseTapTime)
        if timeSinceTap >= 0.25 || payload.playerState == self.playerState {
            self.playerState = payload.playerState
        }
        self.basePosition = payload.position
        self.position = payload.position
        self.duration = payload.duration
        if !isDraggingVolume {
            self.volume = Double(payload.volume)
        }
        self.isShuffle = payload.shuffle
        self.repeatMode = payload.repeatMode
        self.audioQuality = payload.audioQuality ?? "Lossless (ALAC 24-bit/48kHz)"
        self.isRadio = payload.isRadio ?? false

        let trackChanged = (self.currentTrack?.id != payload.track?.id) || (self.currentTrack?.name != payload.track?.name)
        let plChanged = (self.currentPlaylistName != (payload.playlist ?? "Музыка"))
        self.currentTrack = payload.track
        self.currentPlaylistName = payload.playlist ?? "Музыка"
        self.lastSyncTime = Date()

        if trackChanged || plChanged {
            self.loadQueue()
        }
    }

    public func webSocketClient(_ client: WebSocketClient, didUpdateQueue payload: QueuePayload) {
        var up = payload.upcomingTracks ?? []
        let all = payload.tracks ?? []
        if up.isEmpty, all.count > 1 {
            if let curIdx = payload.currentIndex, curIdx >= 0, curIdx + 1 < all.count {
                up = Array(all[(curIdx + 1)...])
            } else if let cur = self.currentTrack, let idx = all.firstIndex(where: { $0.id == cur.id || $0.name == cur.name }), idx + 1 < all.count {
                up = Array(all[(idx + 1)...])
            }
        }
        // Guard against transient empty payload while playing
        if up.isEmpty && self.playerState == .playing && !self.upcomingTracks.isEmpty && (payload.playlist == self.currentPlaylistName || payload.playlist == nil) {
            NSLog("[PlayerStore] Retaining upcoming tracks during transient empty update while playing")
        } else {
            self.upcomingTracks = up
        }
        self.fullQueueTracks = all
        self.historyTracks = payload.historyTracks ?? []
        NSLog("[PlayerStore] didUpdateQueue: upcoming: %d, full: %d, history: %d", self.upcomingTracks.count, self.fullQueueTracks.count, self.historyTracks.count)
    }

    public func webSocketClient(_ client: WebSocketClient, didReceiveEvent name: String, data: [String: Any]) {
        let n = name.lowercased()
        if n == "playlists_result" || n == "get_playlists" || n == "playlists" {
            self.isLoadingPlaylists = false
            let inner = (data["data"] as? [String: Any]) ?? data
            let rawList = inner["playlists"] ?? data["playlists"]
            if let rawList = rawList,
               let listData = try? JSONSerialization.data(withJSONObject: rawList),
               let decoded = try? JSONDecoder().decode([PlaylistItem].self, from: listData) {
                self.playlists = decoded
            }
        } else if n == "playlist_tracks" || n == "get_playlist_tracks" || n == "playlist_tracks_result" {
            self.isLoadingPlaylistTracks = false
            let inner = (data["data"] as? [String: Any]) ?? data
            let plName = (inner["playlist"] as? String) ?? (inner["name"] as? String) ?? ""
            let rawTracks = inner["tracks"] ?? data["tracks"]
            if let rawTracks = rawTracks,
               let listData = try? JSONSerialization.data(withJSONObject: rawTracks),
               let decoded = try? JSONDecoder().decode([TrackItem].self, from: listData) {
                if !plName.isEmpty {
                    self.playlistTracks[plName] = decoded
                    let clean = plName.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.playlistTracks[clean] = decoded
                }
            }
        } else if n == "artists_result" || n == "get_artists" || n == "artists" {
            let inner = (data["data"] as? [String: Any]) ?? data
            let rawArtists = inner["artists"] ?? data["artists"]
            if let rawArtists = rawArtists,
               let listData = try? JSONSerialization.data(withJSONObject: rawArtists),
               let decoded = try? JSONDecoder().decode([ArtistItem].self, from: listData) {
                self.artists = decoded
            }
        } else if n == "songs_result" || n == "get_songs" || n == "songs" {
            let inner = (data["data"] as? [String: Any]) ?? data
            let rawSongs = inner["songs"] ?? data["songs"]
            if let rawSongs = rawSongs,
               let listData = try? JSONSerialization.data(withJSONObject: rawSongs),
               let decoded = try? JSONDecoder().decode([TrackItem].self, from: listData) {
                self.songs = decoded
            }
        } else if n == "stations_result" || n == "get_stations" || n == "stations" {
            let inner = (data["data"] as? [String: Any]) ?? data
            let rawStations = inner["stations"] ?? data["stations"]
            if let rawStations = rawStations,
               let listData = try? JSONSerialization.data(withJSONObject: rawStations),
               let decoded = try? JSONDecoder().decode([StationItem].self, from: listData) {
                self.curatedStations = decoded
            }
        } else if n == "get_catalog_charts" || n == "catalog_charts" || n == "charts" {
            let inner = (data["data"] as? [String: Any]) ?? data
            let rawSongs = inner["songs"] ?? data["songs"]
            if let rawSongs = rawSongs,
               let listData = try? JSONSerialization.data(withJSONObject: rawSongs),
               let decoded = try? JSONDecoder().decode([TrackItem].self, from: listData) {
                self.topChartSongs = decoded
            }
        } else if n == "search_result" || n == "search" {
            self.isSearching = false
            if let songsArr = data["songs"] as? [[String: Any]],
               let d = try? JSONSerialization.data(withJSONObject: songsArr),
               let decoded = try? JSONDecoder().decode([TrackItem].self, from: d) {
                self.searchResultsTracks = decoded
            }
            if let artistsArr = data["artists"] as? [[String: Any]],
               let d = try? JSONSerialization.data(withJSONObject: artistsArr),
               let decoded = try? JSONDecoder().decode([ArtistItem].self, from: d) {
                self.searchResultsArtists = decoded
            }
            if let albumsArr = data["albums"] as? [[String: Any]],
               let d = try? JSONSerialization.data(withJSONObject: albumsArr),
               let decoded = try? JSONDecoder().decode([AlbumItem].self, from: d) {
                self.searchResultsAlbums = decoded
            }
        }
    }

    // MARK: - Position Ticker

    private func startPositionTicker() {
        positionTimer?.invalidate()
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.playerState == .playing && self.duration > 0 {
                let elapsed = Date().timeIntervalSince(self.lastSyncTime)
                self.position = min(self.duration, self.basePosition + elapsed)
            }
        }
    }
}
