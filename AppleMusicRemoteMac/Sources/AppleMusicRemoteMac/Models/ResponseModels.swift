//
//  ResponseModels.swift
//  AppleMusicRemoteMac
//
//  AnyCodable helper, server response DTOs, and personal recommendation models
//

import CoreFoundation
import Foundation

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
        } else if let num = value as? NSNumber, CFGetTypeID(num) == CFBooleanGetTypeID() {
            self = .bool(num.boolValue)
        } else if let bool = value as? Bool {
            self = .bool(bool)
        } else if let int = value as? Int {
            self = .int(int)
        } else if let double = value as? Double {
            self = .double(double.isFinite ? double : 0.0)
        } else if let float = value as? Float {
            self = .double(float.isFinite ? Double(float) : 0.0)
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
        case .double(let d): try container.encode(d.isFinite ? d : 0.0)
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

public struct LibraryRecentResponse: Codable, Sendable {
    public var albums: [AlbumInfo]
    public var songs: [TrackInfo]

    public init(albums: [AlbumInfo] = [], songs: [TrackInfo] = []) {
        self.albums = albums
        self.songs = songs
    }
}

public struct ArtistLibraryDetailResponse: Codable, Sendable {
    public var artist: String
    public var trackCount: Int
    public var albumCount: Int
    public var albums: [AlbumInfo]
    public var songs: [TrackInfo]

    enum CodingKeys: String, CodingKey {
        case artist
        case trackCount = "track_count"
        case albumCount = "album_count"
        case albums
        case songs
    }

    public init(
        artist: String,
        trackCount: Int,
        albumCount: Int,
        albums: [AlbumInfo] = [],
        songs: [TrackInfo] = []
    ) {
        self.artist = artist
        self.trackCount = trackCount
        self.albumCount = albumCount
        self.albums = albums
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

// MARK: - Personal Recommendations & Mixes

public struct RecommendationResource: Codable, Sendable {
    public var id: String
    public var type: String // "stations", "playlists", "albums"
    public var name: String
    public var subtitle: String?
    public var artworkUrl: String?
    public var url: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case name
        case subtitle
        case artworkUrl = "artwork_url"
        case url
    }

    public init(id: String, type: String, name: String, subtitle: String? = nil, artworkUrl: String? = nil, url: String? = nil) {
        self.id = id
        self.type = type
        self.name = name
        self.subtitle = subtitle
        self.artworkUrl = artworkUrl
        self.url = url
    }
}

public struct PersonalRecommendationGroup: Codable, Sendable {
    public var id: String
    public var title: String
    public var contents: [RecommendationResource]

    public init(id: String, title: String, contents: [RecommendationResource] = []) {
        self.id = id
        self.title = title
        self.contents = contents
    }
}

public struct PersonalMixesResponse: Codable, Sendable {
    public var mixes: [PlaylistInfo]
    public var stations: [StationInfo]

    public init(mixes: [PlaylistInfo] = [], stations: [StationInfo] = []) {
        self.mixes = mixes
        self.stations = stations
    }
}
