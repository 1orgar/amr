//
//  Models.swift
//  AppleMusicRemoteIOS
//
//  Data models and WebSocket DTOs for iOS Client
//

import Foundation

public enum PlayerState: String, Codable, Sendable {
    case playing
    case paused
    case stopped
    case fastForwarding = "fast forwarding"
    case rewinding = "rewinding"
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? "stopped"
        self = PlayerState(rawValue: raw) ?? .unknown
    }
}

public struct PlayerStatusPayload: Codable, Sendable {
    public let playerState: PlayerState
    public let position: Double
    public let duration: Double
    public let volume: Int
    public let shuffle: Bool
    public let repeatMode: String
    public let playlist: String?
    public let audioQuality: String?
    public let isRadio: Bool?
    public let track: TrackItem?
    public let serverTime: Double?

    enum CodingKeys: String, CodingKey {
        case position, duration, volume, shuffle, playlist, track
        case playerState = "player_state"
        case repeatMode = "repeat"
        case audioQuality = "audio_quality"
        case isRadio = "is_radio"
        case serverTime = "server_time"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.playerState = (try? container.decode(PlayerState.self, forKey: .playerState)) ?? .stopped
        self.position = (try? container.decode(Double.self, forKey: .position)) ?? 0
        self.duration = (try? container.decode(Double.self, forKey: .duration)) ?? 0
        self.volume = (try? container.decode(Int.self, forKey: .volume)) ?? 100
        self.shuffle = (try? container.decode(Bool.self, forKey: .shuffle)) ?? false
        self.repeatMode = (try? container.decode(String.self, forKey: .repeatMode)) ?? "off"
        self.playlist = try? container.decode(String.self, forKey: .playlist)
        self.audioQuality = try? container.decode(String.self, forKey: .audioQuality)
        self.isRadio = try? container.decode(Bool.self, forKey: .isRadio)
        self.track = try? container.decode(TrackItem.self, forKey: .track)
        self.serverTime = try? container.decode(Double.self, forKey: .serverTime)
    }
}

public struct TrackItem: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let artist: String
    public let album: String?
    public let duration: Double
    public let artworkUrl: String?
    public let isFavorited: Bool?
    public let isLocal: Bool?
    public let url: String?
    public let previewUrl: String?
    public let index: Int?

    public init(
        id: String,
        name: String,
        artist: String,
        album: String? = nil,
        duration: Double = 0,
        artworkUrl: String? = nil,
        isFavorited: Bool? = nil,
        isLocal: Bool? = nil,
        url: String? = nil,
        previewUrl: String? = nil,
        index: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkUrl = artworkUrl
        self.isFavorited = isFavorited
        self.isLocal = isLocal
        self.url = url
        self.previewUrl = previewUrl
        self.index = index
    }

    enum CodingKeys: String, CodingKey {
        case id, name, artist, album, duration, url, index
        case artworkUrl = "artwork_url"
        case artworkAlt = "artwork"
        case isFavorited = "favorited"
        case isLocal = "is_local"
        case previewUrl = "preview_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let stringId = try? container.decode(String.self, forKey: .id) {
            self.id = stringId
        } else if let intId = try? container.decode(Int.self, forKey: .id) {
            self.id = "\(intId)"
        } else {
            self.id = UUID().uuidString
        }

        self.name = (try? container.decode(String.self, forKey: .name)) ?? ""
        self.artist = (try? container.decode(String.self, forKey: .artist)) ?? ""
        self.album = try? container.decode(String.self, forKey: .album)
        self.duration = (try? container.decode(Double.self, forKey: .duration)) ?? 0
        self.artworkUrl = (try? container.decode(String.self, forKey: .artworkUrl)) ?? (try? container.decode(String.self, forKey: .artworkAlt))
        self.isFavorited = try? container.decode(Bool.self, forKey: .isFavorited)
        self.isLocal = try? container.decode(Bool.self, forKey: .isLocal)
        self.url = try? container.decode(String.self, forKey: .url)
        self.previewUrl = try? container.decode(String.self, forKey: .previewUrl)
        self.index = try? container.decode(Int.self, forKey: .index)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(artist, forKey: .artist)
        try container.encodeIfPresent(album, forKey: .album)
        try container.encode(duration, forKey: .duration)
        try container.encodeIfPresent(artworkUrl, forKey: .artworkUrl)
        try container.encodeIfPresent(isFavorited, forKey: .isFavorited)
        try container.encodeIfPresent(isLocal, forKey: .isLocal)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(previewUrl, forKey: .previewUrl)
        try container.encodeIfPresent(index, forKey: .index)
    }
}

public struct PlaylistItem: Identifiable, Codable, Sendable, Hashable {
    public var id: String { name }
    public let name: String
    public let trackCount: Int
    public let artworkUrl: String?

    enum CodingKeys: String, CodingKey {
        case name
        case trackCount = "track_count"
        case artworkUrl = "artwork_url"
        case artworkAlt = "artwork"
    }

    public init(name: String, trackCount: Int, artworkUrl: String?) {
        self.name = name
        self.trackCount = trackCount
        self.artworkUrl = artworkUrl
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = (try? container.decode(String.self, forKey: .name)) ?? ""
        self.trackCount = (try? container.decode(Int.self, forKey: .trackCount)) ?? 0
        self.artworkUrl = (try? container.decode(String.self, forKey: .artworkUrl)) ?? (try? container.decode(String.self, forKey: .artworkAlt))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(trackCount, forKey: .trackCount)
        try container.encodeIfPresent(artworkUrl, forKey: .artworkUrl)
    }
}

public struct ArtistItem: Identifiable, Codable, Sendable, Hashable {
    public var id: String { name }
    public let name: String
    public let artworkUrl: String?

    enum CodingKeys: String, CodingKey {
        case name
        case artworkUrl = "artwork_url"
        case artworkAlt = "artwork"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = (try? container.decode(String.self, forKey: .name)) ?? ""
        self.artworkUrl = (try? container.decode(String.self, forKey: .artworkUrl)) ?? (try? container.decode(String.self, forKey: .artworkAlt))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(artworkUrl, forKey: .artworkUrl)
    }
}

public struct AlbumItem: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let artist: String
    public let artworkUrl: String?
    public let releaseDate: String?
    public let trackCount: Int?
    public let tracks: [TrackItem]?

    enum CodingKeys: String, CodingKey {
        case id, name, artist, tracks
        case artworkUrl = "artwork_url"
        case artworkAlt = "artwork"
        case releaseDate = "release_date"
        case trackCount = "track_count"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let stringId = try? container.decode(String.self, forKey: .id) {
            self.id = stringId
        } else if let intId = try? container.decode(Int.self, forKey: .id) {
            self.id = "\(intId)"
        } else {
            self.id = UUID().uuidString
        }
        self.name = (try? container.decode(String.self, forKey: .name)) ?? ""
        self.artist = (try? container.decode(String.self, forKey: .artist)) ?? ""
        self.artworkUrl = (try? container.decode(String.self, forKey: .artworkUrl)) ?? (try? container.decode(String.self, forKey: .artworkAlt))
        self.releaseDate = try? container.decode(String.self, forKey: .releaseDate)
        self.trackCount = try? container.decode(Int.self, forKey: .trackCount)
        self.tracks = try? container.decode([TrackItem].self, forKey: .tracks)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(artist, forKey: .artist)
        try container.encodeIfPresent(artworkUrl, forKey: .artworkUrl)
        try container.encodeIfPresent(releaseDate, forKey: .releaseDate)
        try container.encodeIfPresent(trackCount, forKey: .trackCount)
        try container.encodeIfPresent(tracks, forKey: .tracks)
    }
}

public struct StationItem: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let subtitle: String?
    public let artworkUrl: String?
    public let url: String
    public let isLive: Bool?
    public let color: String?

    enum CodingKeys: String, CodingKey {
        case id, name, subtitle, url, color
        case artworkUrl = "artwork"
        case artworkUrlAlt = "artwork_url"
        case isLive = "is_live"
    }

    public init(
        id: String,
        name: String,
        subtitle: String?,
        artworkUrl: String?,
        url: String,
        isLive: Bool?,
        color: String?
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.artworkUrl = artworkUrl
        self.url = url
        self.isLive = isLive
        self.color = color
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.name = (try? container.decode(String.self, forKey: .name)) ?? ""
        self.subtitle = try? container.decode(String.self, forKey: .subtitle)
        self.artworkUrl = (try? container.decode(String.self, forKey: .artworkUrl)) ?? (try? container.decode(String.self, forKey: .artworkUrlAlt))
        self.url = (try? container.decode(String.self, forKey: .url)) ?? ""
        self.isLive = try? container.decode(Bool.self, forKey: .isLive)
        self.color = try? container.decode(String.self, forKey: .color)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        try container.encodeIfPresent(artworkUrl, forKey: .artworkUrl)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(isLive, forKey: .isLive)
        try container.encodeIfPresent(color, forKey: .color)
    }
}


public struct QueuePayload: Codable, Sendable {
    public let playlist: String?
    public let currentIndex: Int?
    public let totalTracks: Int?
    public let shuffle: Bool?
    public let upcomingTracks: [TrackItem]?
    public let tracks: [TrackItem]?
    public let historyTracks: [TrackItem]?

    enum CodingKeys: String, CodingKey {
        case playlist, shuffle, tracks
        case currentIndex = "current_index"
        case totalTracks = "total_tracks"
        case upcomingTracks = "upcoming_tracks"
        case historyTracks = "history_tracks"
    }

    public init(
        playlist: String? = nil,
        currentIndex: Int? = nil,
        totalTracks: Int? = nil,
        shuffle: Bool? = nil,
        upcomingTracks: [TrackItem]? = nil,
        tracks: [TrackItem]? = nil,
        historyTracks: [TrackItem]? = nil
    ) {
        self.playlist = playlist
        self.currentIndex = currentIndex
        self.totalTracks = totalTracks
        self.shuffle = shuffle
        self.upcomingTracks = upcomingTracks
        self.tracks = tracks
        self.historyTracks = historyTracks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.playlist = try? container.decode(String.self, forKey: .playlist)
        self.currentIndex = try? container.decode(Int.self, forKey: .currentIndex)
        self.totalTracks = try? container.decode(Int.self, forKey: .totalTracks)
        self.shuffle = try? container.decode(Bool.self, forKey: .shuffle)
        self.upcomingTracks = (try? container.decode([TrackItem].self, forKey: .upcomingTracks)) ?? []
        self.tracks = (try? container.decode([TrackItem].self, forKey: .tracks)) ?? []
        self.historyTracks = (try? container.decode([TrackItem].self, forKey: .historyTracks)) ?? []
    }
}

public struct ServerHost: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let hostName: String
    public let port: Int
    public var ipAddress: String
    public var pingMs: Int
    
    public init(id: String, name: String, hostName: String, port: Int, ipAddress: String, pingMs: Int = 0) {
        self.id = id
        self.name = name
        self.hostName = hostName
        self.port = port
        self.ipAddress = ipAddress
        self.pingMs = pingMs
    }
}
