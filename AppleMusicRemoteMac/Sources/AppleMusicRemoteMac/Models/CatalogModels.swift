//
//  CatalogModels.swift
//  AppleMusicRemoteMac
//
//  Track, playlist, artist, album, station, and playback queue models
//

import Foundation

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
    public var catalogId: String?
    public var persistentId: String?

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
        case catalogId = "catalog_id"
        case persistentId = "persistent_id"
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
        bitDepth: Int? = nil,
        catalogId: String? = nil,
        persistentId: String? = nil
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
        self.catalogId = catalogId
        self.persistentId = persistentId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.numericId = try container.decodeIfPresent(Int.self, forKey: .numericId)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.artist = try container.decodeIfPresent(String.self, forKey: .artist) ?? ""
        self.album = try container.decodeIfPresent(String.self, forKey: .album) ?? ""
        self.duration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        self.hasArtwork = try container.decodeIfPresent(Bool.self, forKey: .hasArtwork) ?? false
        self.artworkUrl = try container.decodeIfPresent(String.self, forKey: .artworkUrl) ?? ""
        self.artworkDataBase64 = try container.decodeIfPresent(String.self, forKey: .artworkDataBase64)
        self.favorited = try container.decodeIfPresent(Bool.self, forKey: .favorited) ?? false
        self.isLocal = try container.decodeIfPresent(Bool.self, forKey: .isLocal)
        self.playedCount = try container.decodeIfPresent(Int.self, forKey: .playedCount)
        self.playedDate = try container.decodeIfPresent(Double.self, forKey: .playedDate)
        self.dateAdded = try container.decodeIfPresent(Double.self, forKey: .dateAdded)
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
        self.previewUrl = try container.decodeIfPresent(String.self, forKey: .previewUrl)
        self.index = try container.decodeIfPresent(Int.self, forKey: .index)
        self.isCurrent = try container.decodeIfPresent(Bool.self, forKey: .isCurrent)
        self.sampleRate = try container.decodeIfPresent(Int.self, forKey: .sampleRate)
        self.bitDepth = try container.decodeIfPresent(Int.self, forKey: .bitDepth)
        self.catalogId = try container.decodeIfPresent(String.self, forKey: .catalogId)
        self.persistentId = try container.decodeIfPresent(String.self, forKey: .persistentId)
    }
}

// MARK: - Playlist Info

public struct PlaylistInfo: Codable, Sendable {
    public var name: String
    public var trackCount: Int
    public var artworkUrl: String?
    public var isPlaylist: Bool
    public var id: String?
    public var catalogId: String?
    public var alternateNames: [String]?
    public var url: String?
    public var curatorName: String?
    public var description: String?

    enum CodingKeys: String, CodingKey {
        case name
        case trackCount = "track_count"
        case artworkUrl = "artwork_url"
        case isPlaylist = "is_playlist"
        case id
        case catalogId = "catalog_id"
        case alternateNames = "alternate_names"
        case url
        case curatorName = "curator_name"
        case description
    }

    public init(
        name: String,
        trackCount: Int,
        artworkUrl: String? = nil,
        isPlaylist: Bool = true,
        id: String? = nil,
        catalogId: String? = nil,
        alternateNames: [String]? = nil,
        url: String? = nil,
        curatorName: String? = nil,
        description: String? = nil
    ) {
        self.name = name
        self.trackCount = trackCount
        self.artworkUrl = artworkUrl
        self.isPlaylist = isPlaylist
        self.id = id
        self.catalogId = catalogId
        self.alternateNames = alternateNames
        self.url = url
        self.curatorName = curatorName
        self.description = description
    }
}

// MARK: - Artist Info

public struct ArtistInfo: Codable, Sendable {
    public var name: String
    public var id: String?
    public var genre: String?
    public var url: String?
    public var trackCount: Int?
    public var albumCount: Int?
    public var artwork: String?

    enum CodingKeys: String, CodingKey {
        case name
        case id
        case genre
        case url
        case trackCount = "track_count"
        case albumCount = "album_count"
        case artwork
    }

    public init(
        name: String,
        id: String? = nil,
        genre: String? = nil,
        url: String? = nil,
        trackCount: Int? = nil,
        albumCount: Int? = nil,
        artwork: String? = nil
    ) {
        self.name = name
        self.id = id
        self.genre = genre
        self.url = url
        self.trackCount = trackCount
        self.albumCount = albumCount
        self.artwork = artwork
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.genre = try container.decodeIfPresent(String.self, forKey: .genre)
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
        self.trackCount = try container.decodeIfPresent(Int.self, forKey: .trackCount)
        self.albumCount = try container.decodeIfPresent(Int.self, forKey: .albumCount)
        self.artwork = try container.decodeIfPresent(String.self, forKey: .artwork)
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
    public var inLibrary: Bool?
    public var libraryTrackCount: Int?
    public var catalogTrackCount: Int?
    public var catalogAlbumId: String?
    public var isCompleteInLibrary: Bool?
    public var isLibraryView: Bool?
    public var dateAdded: Double?

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
        case inLibrary = "in_library"
        case libraryTrackCount = "library_track_count"
        case catalogTrackCount = "catalog_track_count"
        case catalogAlbumId = "catalog_album_id"
        case isCompleteInLibrary = "is_complete_in_library"
        case isLibraryView = "is_library_view"
        case dateAdded = "date_added"
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
        tracks: [TrackInfo]? = nil,
        inLibrary: Bool? = nil,
        libraryTrackCount: Int? = nil,
        catalogTrackCount: Int? = nil,
        catalogAlbumId: String? = nil,
        isCompleteInLibrary: Bool? = nil,
        isLibraryView: Bool? = nil,
        dateAdded: Double? = nil
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
        self.inLibrary = inLibrary
        self.libraryTrackCount = libraryTrackCount
        self.catalogTrackCount = catalogTrackCount
        self.catalogAlbumId = catalogAlbumId
        self.isCompleteInLibrary = isCompleteInLibrary
        self.isLibraryView = isLibraryView
        self.dateAdded = dateAdded
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.artist = try container.decodeIfPresent(String.self, forKey: .artist) ?? ""
        self.artwork = try container.decodeIfPresent(String.self, forKey: .artwork) ?? ""
        self.releaseDate = try container.decodeIfPresent(String.self, forKey: .releaseDate)
        self.trackCount = try container.decodeIfPresent(Int.self, forKey: .trackCount)
        self.genre = try container.decodeIfPresent(String.self, forKey: .genre)
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
        self.tracks = try container.decodeIfPresent([TrackInfo].self, forKey: .tracks)
        self.inLibrary = try container.decodeIfPresent(Bool.self, forKey: .inLibrary)
        self.libraryTrackCount = try container.decodeIfPresent(Int.self, forKey: .libraryTrackCount)
        self.catalogTrackCount = try container.decodeIfPresent(Int.self, forKey: .catalogTrackCount)
        self.catalogAlbumId = try container.decodeIfPresent(String.self, forKey: .catalogAlbumId)
        self.isCompleteInLibrary = try container.decodeIfPresent(Bool.self, forKey: .isCompleteInLibrary)
        self.isLibraryView = try container.decodeIfPresent(Bool.self, forKey: .isLibraryView)
        self.dateAdded = try container.decodeIfPresent(Double.self, forKey: .dateAdded)
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
    public var isPersonal: Bool?
    public var provider: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case subtitle
        case artwork
        case url
        case isLive = "is_live"
        case color
        case isPersonal = "is_personal"
        case provider
    }

    public init(
        id: String,
        name: String,
        subtitle: String,
        artwork: String,
        url: String,
        isLive: Bool,
        color: String,
        isPersonal: Bool? = nil,
        provider: String? = nil
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.artwork = artwork
        self.url = url
        self.isLive = isLive
        self.color = color
        self.isPersonal = isPersonal
        self.provider = provider
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
