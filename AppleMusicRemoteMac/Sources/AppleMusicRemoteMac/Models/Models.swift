//
//  Models.swift
//  AppleMusicRemoteMac
//
//  Pure Swift data models for Apple Music Remote
//

import Foundation

// MARK: - Player Status

public struct PlayerStatus: Codable, Sendable {
    public var playerState: String
    public var position: Double
    public var duration: Double
    public var volume: Int
    public var shuffle: Bool
    public var repeatMode: String
    public var playlist: String
    public var isRadio: Bool
    public var audioQuality: String
    public var isMusicAppRunning: Bool
    public var isDucked: Bool
    public var isVolumeLockedTo100: Bool
    public var track: TrackInfo?
    public var audioDeviceName: String?
    public var audioDeviceSampleRate: Double?
    public var isBitPerfect: Bool?

    enum CodingKeys: String, CodingKey {
        case playerState = "player_state"
        case position
        case duration
        case volume
        case shuffle
        case repeatMode = "repeat"
        case playlist
        case isRadio = "is_radio"
        case audioQuality = "audio_quality"
        case isMusicAppRunning = "is_music_app_running"
        case isDucked = "is_ducked"
        case isVolumeLockedTo100 = "lock_volume_100"
        case track
        case audioDeviceName = "audio_device_name"
        case audioDeviceSampleRate = "audio_device_sample_rate"
        case isBitPerfect = "is_bit_perfect"
    }

    public init(
        playerState: String = "stopped",
        position: Double = 0,
        duration: Double = 0,
        volume: Int = 50,
        shuffle: Bool = false,
        repeatMode: String = "off",
        playlist: String = "Музыка",
        isRadio: Bool = false,
        audioQuality: String = "Lossless (ALAC 24-bit/48kHz)",
        isMusicAppRunning: Bool = true,
        isDucked: Bool = false,
        isVolumeLockedTo100: Bool = true,
        track: TrackInfo? = nil,
        audioDeviceName: String? = nil,
        audioDeviceSampleRate: Double? = nil,
        isBitPerfect: Bool? = nil
    ) {
        self.playerState = playerState
        self.position = position
        self.duration = duration
        self.volume = volume
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        self.playlist = playlist
        self.isRadio = isRadio
        self.audioQuality = audioQuality
        self.isMusicAppRunning = isMusicAppRunning
        self.isDucked = isDucked
        self.isVolumeLockedTo100 = isVolumeLockedTo100
        self.track = track
        self.audioDeviceName = audioDeviceName
        self.audioDeviceSampleRate = audioDeviceSampleRate
        self.isBitPerfect = isBitPerfect
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.playerState = try container.decodeIfPresent(String.self, forKey: .playerState) ?? "stopped"
        self.position = try container.decodeIfPresent(Double.self, forKey: .position) ?? 0
        self.duration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        self.volume = try container.decodeIfPresent(Int.self, forKey: .volume) ?? 50
        self.shuffle = try container.decodeIfPresent(Bool.self, forKey: .shuffle) ?? false
        self.repeatMode = try container.decodeIfPresent(String.self, forKey: .repeatMode) ?? "off"
        self.playlist = try container.decodeIfPresent(String.self, forKey: .playlist) ?? "Музыка"
        self.isRadio = try container.decodeIfPresent(Bool.self, forKey: .isRadio) ?? false
        self.audioQuality = try container.decodeIfPresent(String.self, forKey: .audioQuality) ?? "Lossless"
        self.isMusicAppRunning = try container.decodeIfPresent(Bool.self, forKey: .isMusicAppRunning) ?? true
        self.isDucked = try container.decodeIfPresent(Bool.self, forKey: .isDucked) ?? false
        self.isVolumeLockedTo100 = try container.decodeIfPresent(Bool.self, forKey: .isVolumeLockedTo100) ?? true
        self.track = try container.decodeIfPresent(TrackInfo.self, forKey: .track)
        self.audioDeviceName = try container.decodeIfPresent(String.self, forKey: .audioDeviceName)
        self.audioDeviceSampleRate = try container.decodeIfPresent(Double.self, forKey: .audioDeviceSampleRate)
        self.isBitPerfect = try container.decodeIfPresent(Bool.self, forKey: .isBitPerfect)
    }

    public var isPlaying: Bool {
        return playerState == "playing"
    }
}

// MARK: - Track Info

public struct TrackInfo: Codable, Sendable, Identifiable {
    public var id: String
    public var numericId: Int?
    public var name: String
    public var artist: String
    public var album: String
    public var duration: Double
    public var hasArtwork: Bool
    public var artworkUrl: String
    public var artworkDataBase64: String?
    public var favorited: Bool
    public var isLocal: Bool?
    public var playedCount: Int?
    public var playedDate: Double?
    public var dateAdded: Double?
    public var url: String?
    public var previewUrl: String?
    public var index: Int?
    public var isCurrent: Bool?
    public var sampleRate: Int?
    public var bitDepth: Int?

    public var formattedDuration: String {
        guard duration > 0 else { return "0:00" }
        let total = Int(duration)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case numericId = "numeric_id"
        case name
        case artist
        case album
        case duration
        case hasArtwork = "has_artwork"
        case artworkUrl = "artwork_url"
        case artworkDataBase64 = "artwork_data_base64"
        case favorited
        case isLocal = "is_local"
        case playedCount = "played_count"
        case playedDate = "played_date"
        case dateAdded = "date_added"
        case url
        case previewUrl = "preview_url"
        case index
        case isCurrent = "is_current"
        case sampleRate = "sample_rate"
        case bitDepth = "bit_depth"
    }

    public init(
        id: String = UUID().uuidString,
        numericId: Int? = nil,
        name: String = "",
        artist: String = "",
        album: String = "",
        duration: Double = 0,
        hasArtwork: Bool = false,
        artworkUrl: String = "",
        artworkDataBase64: String? = nil,
        favorited: Bool = false,
        isLocal: Bool? = true,
        playedCount: Int? = nil,
        playedDate: Double? = nil,
        dateAdded: Double? = nil,
        url: String? = nil,
        previewUrl: String? = nil,
        index: Int? = nil,
        isCurrent: Bool? = nil,
        sampleRate: Int? = nil,
        bitDepth: Int? = nil
    ) {
        self.id = id
        self.numericId = numericId
        self.name = name
        self.artist = artist
        self.album = album
        self.duration = duration
        self.hasArtwork = hasArtwork
        self.artworkUrl = artworkUrl
        self.artworkDataBase64 = artworkDataBase64
        self.favorited = favorited
        self.isLocal = isLocal
        self.playedCount = playedCount
        self.playedDate = playedDate
        self.dateAdded = dateAdded
        self.url = url
        self.previewUrl = previewUrl
        self.index = index
        self.isCurrent = isCurrent
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
    }
}

// MARK: - Playlist Info

public struct PlaylistInfo: Codable, Sendable {
    public var name: String
    public var trackCount: Int
    public var artworkUrl: String?
    public var isPlaylist: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case trackCount = "track_count"
        case artworkUrl = "artwork_url"
        case isPlaylist = "is_playlist"
    }

    public init(name: String, trackCount: Int, artworkUrl: String? = nil, isPlaylist: Bool = true) {
        self.name = name
        self.trackCount = trackCount
        self.artworkUrl = artworkUrl
        self.isPlaylist = isPlaylist
    }
}

// MARK: - Artist Info

public struct ArtistInfo: Codable, Sendable {
    public var name: String
    public var id: String?
    public var genre: String?
    public var url: String?

    public init(name: String, id: String? = nil, genre: String? = nil, url: String? = nil) {
        self.name = name
        self.id = id
        self.genre = genre
        self.url = url
    }
}

// MARK: - Album Info

public struct AlbumInfo: Codable, Sendable {
    public var id: String
    public var name: String
    public var artist: String
    public var artwork: String
    public var releaseDate: String?
    public var trackCount: Int?
    public var genre: String?
    public var url: String?
    public var tracks: [TrackInfo]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case artist
        case artwork
        case releaseDate = "release_date"
        case trackCount = "track_count"
        case genre
        case url
        case tracks
    }

    public init(
        id: String,
        name: String,
        artist: String,
        artwork: String,
        releaseDate: String? = nil,
        trackCount: Int? = nil,
        genre: String? = nil,
        url: String? = nil,
        tracks: [TrackInfo]? = nil
    ) {
        self.id = id
        self.name = name
        self.artist = artist
        self.artwork = artwork
        self.releaseDate = releaseDate
        self.trackCount = trackCount
        self.genre = genre
        self.url = url
        self.tracks = tracks
    }
}

// MARK: - Station Info

public struct StationInfo: Codable, Sendable {
    public var id: String
    public var name: String
    public var subtitle: String
    public var artwork: String
    public var url: String
    public var isLive: Bool
    public var color: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case subtitle
        case artwork
        case url
        case isLive = "is_live"
        case color
    }

    public init(id: String, name: String, subtitle: String, artwork: String, url: String, isLive: Bool, color: String) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.artwork = artwork
        self.url = url
        self.isLive = isLive
        self.color = color
    }
}

// MARK: - Playback Queue Info

public struct PlaybackQueueInfo: Codable, Sendable {
    public var playlist: String
    public var currentIndex: Int
    public var totalTracks: Int
    public var shuffle: Bool
    public var upcomingTracks: [TrackInfo]
    public var tracks: [TrackInfo]
    public var historyTracks: [TrackInfo]

    enum CodingKeys: String, CodingKey {
        case playlist
        case currentIndex = "current_index"
        case totalTracks = "total_tracks"
        case shuffle
        case upcomingTracks = "upcoming_tracks"
        case tracks
        case historyTracks = "history_tracks"
    }

    public init(
        playlist: String = "Очередь",
        currentIndex: Int = 0,
        totalTracks: Int = 0,
        shuffle: Bool = false,
        upcomingTracks: [TrackInfo] = [],
        tracks: [TrackInfo] = [],
        historyTracks: [TrackInfo] = []
    ) {
        self.playlist = playlist
        self.currentIndex = currentIndex
        self.totalTracks = totalTracks
        self.shuffle = shuffle
        self.upcomingTracks = upcomingTracks
        self.tracks = tracks
        self.historyTracks = historyTracks
    }
}

// MARK: - AnyCodable Value Helper

public enum AnyCodable: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case dictionary([String: AnyCodable])
    case array([AnyCodable])
    case null

    public init(_ value: Any?) {
        guard let value = value else {
            self = .null
            return
        }
        if let string = value as? String {
            self = .string(string)
        } else if let int = value as? Int {
            self = .int(int)
        } else if let double = value as? Double {
            self = .double(double)
        } else if let bool = value as? Bool {
            self = .bool(bool)
        } else if let dict = value as? [String: Any] {
            var converted = [String: AnyCodable]()
            for (k, v) in dict {
                converted[k] = AnyCodable(v)
            }
            self = .dictionary(converted)
        } else if let array = value as? [Any] {
            self = .array(array.map { AnyCodable($0) })
        } else {
            self = .string(String(describing: value))
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodable].self) {
            self = .array(array)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self = .dictionary(dict)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .dictionary(let d): try container.encode(d)
        case .array(let a): try container.encode(a)
        case .null: try container.encodeNil()
        }
    }

    public var value: Any? {
        switch self {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .dictionary(let d): return d.mapValues { $0.value }
        case .array(let a): return a.map { $0.value }
        case .null: return nil
        }
    }
}

// MARK: - Server Response DTOs

public struct PlaylistTracksResponse: Codable, Sendable {
    public var playlist: String
    public var tracks: [TrackInfo]

    public init(playlist: String, tracks: [TrackInfo]) {
        self.playlist = playlist
        self.tracks = tracks
    }
}

public struct PlaylistsResponse: Codable, Sendable {
    public var playlists: [PlaylistInfo]

    public init(playlists: [PlaylistInfo]) {
        self.playlists = playlists
    }
}

public struct ArtistsResponse: Codable, Sendable {
    public var artists: [ArtistInfo]

    public init(artists: [ArtistInfo]) {
        self.artists = artists
    }
}

public struct AlbumsResponse: Codable, Sendable {
    public var albums: [AlbumInfo]

    public init(albums: [AlbumInfo]) {
        self.albums = albums
    }
}

public struct SongsResponse: Codable, Sendable {
    public var songs: [TrackInfo]

    public init(songs: [TrackInfo]) {
        self.songs = songs
    }
}

public struct StationsResponse: Codable, Sendable {
    public var stations: [StationInfo]

    public init(stations: [StationInfo]) {
        self.stations = stations
    }
}

public struct SearchResponse: Codable, Sendable {
    public var songs: [TrackInfo]
    public var albums: [AlbumInfo]
    public var artists: [ArtistInfo]

    public init(songs: [TrackInfo] = [], albums: [AlbumInfo] = [], artists: [ArtistInfo] = []) {
        self.songs = songs
        self.albums = albums
        self.artists = artists
    }
}
