//
//  Models.swift
//  AppleMusicRemoteMac
//
//  Pure Swift data models for Apple Music Remote
//

import Foundation

// MARK: - Spectral Integrity & Upsampling Analysis

public struct SpectralAnalysisInfo: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var isCached: Bool
    public var verdict: String
    public var verdictTitle: String
    public var verdictDescription: String
    public var isAuthentic: Bool
    public var sampleRate: Int
    public var claimedBitDepth: Int
    public var effectiveBitDepth: Int
    public var isZeroPadded: Bool
    public var cutoffFrequencyHz: Double
    public var nyquistFrequencyHz: Double
    public var ultrasonicEnergyDb: Double
    public var highBandEnergyDb: Double
    public var dynamicRangeCrestDb: Double
    public var analyzedFramesCount: Int
    public var rtaBands: [Double]

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case isCached = "is_cached"
        case verdict
        case verdictTitle = "verdict_title"
        case verdictDescription = "verdict_description"
        case isAuthentic = "is_authentic"
        case sampleRate = "sample_rate"
        case claimedBitDepth = "claimed_bit_depth"
        case effectiveBitDepth = "effective_bit_depth"
        case isZeroPadded = "is_zero_padded"
        case cutoffFrequencyHz = "cutoff_frequency_hz"
        case nyquistFrequencyHz = "nyquist_frequency_hz"
        case ultrasonicEnergyDb = "ultrasonic_energy_db"
        case highBandEnergyDb = "high_band_energy_db"
        case dynamicRangeCrestDb = "dynamic_range_crest_db"
        case analyzedFramesCount = "analyzed_frames_count"
        case rtaBands = "rta_bands"
    }

    public init(
        isEnabled: Bool = true,
        isCached: Bool = false,
        verdict: String = "analyzing",
        verdictTitle: String = "Спектральный анализ...",
        verdictDescription: String = "Накопление PCM-буферов из CoreAudio Process Tap для расчёта БПФ-спектра.",
        isAuthentic: Bool = true,
        sampleRate: Int = 44100,
        claimedBitDepth: Int = 16,
        effectiveBitDepth: Int = 16,
        isZeroPadded: Bool = false,
        cutoffFrequencyHz: Double = 22050,
        nyquistFrequencyHz: Double = 22050,
        ultrasonicEnergyDb: Double = -96.0,
        highBandEnergyDb: Double = -45.0,
        dynamicRangeCrestDb: Double = 12.0,
        analyzedFramesCount: Int = 0,
        rtaBands: [Double] = Array(repeating: 0.0, count: 32)
    ) {
        self.isEnabled = isEnabled
        self.isCached = isCached
        self.verdict = verdict
        self.verdictTitle = verdictTitle
        self.verdictDescription = verdictDescription
        self.isAuthentic = isAuthentic
        self.sampleRate = sampleRate
        self.claimedBitDepth = claimedBitDepth
        self.effectiveBitDepth = effectiveBitDepth
        self.isZeroPadded = isZeroPadded
        self.cutoffFrequencyHz = cutoffFrequencyHz
        self.nyquistFrequencyHz = nyquistFrequencyHz
        self.ultrasonicEnergyDb = ultrasonicEnergyDb
        self.highBandEnergyDb = highBandEnergyDb
        self.dynamicRangeCrestDb = dynamicRangeCrestDb
        self.analyzedFramesCount = analyzedFramesCount
        self.rtaBands = rtaBands
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.isCached = try container.decodeIfPresent(Bool.self, forKey: .isCached) ?? false
        self.verdict = try container.decodeIfPresent(String.self, forKey: .verdict) ?? "analyzing"
        self.verdictTitle = try container.decodeIfPresent(String.self, forKey: .verdictTitle) ?? "Спектральный анализ..."
        self.verdictDescription = try container.decodeIfPresent(String.self, forKey: .verdictDescription) ?? ""
        self.isAuthentic = try container.decodeIfPresent(Bool.self, forKey: .isAuthentic) ?? true
        self.sampleRate = try container.decodeIfPresent(Int.self, forKey: .sampleRate) ?? 44100
        self.claimedBitDepth = try container.decodeIfPresent(Int.self, forKey: .claimedBitDepth) ?? 16
        self.effectiveBitDepth = try container.decodeIfPresent(Int.self, forKey: .effectiveBitDepth) ?? 16
        self.isZeroPadded = try container.decodeIfPresent(Bool.self, forKey: .isZeroPadded) ?? false
        self.cutoffFrequencyHz = try container.decodeIfPresent(Double.self, forKey: .cutoffFrequencyHz) ?? 22050
        self.nyquistFrequencyHz = try container.decodeIfPresent(Double.self, forKey: .nyquistFrequencyHz) ?? 22050
        self.ultrasonicEnergyDb = try container.decodeIfPresent(Double.self, forKey: .ultrasonicEnergyDb) ?? -96.0
        self.highBandEnergyDb = try container.decodeIfPresent(Double.self, forKey: .highBandEnergyDb) ?? -45.0
        self.dynamicRangeCrestDb = try container.decodeIfPresent(Double.self, forKey: .dynamicRangeCrestDb) ?? 12.0
        self.analyzedFramesCount = try container.decodeIfPresent(Int.self, forKey: .analyzedFramesCount) ?? 0
        self.rtaBands = try container.decodeIfPresent([Double].self, forKey: .rtaBands) ?? Array(repeating: 0.0, count: 32)
    }
}

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
    public var audioDeviceBitDepth: Int?
    public var isBitPerfect: Bool?
    public var isDacMutingGuardEnabled: Bool?
    public var dacMutingGuardMs: Int?
    public var spectralAnalysis: SpectralAnalysisInfo?
    public var ampVolumeControlEnabled: Bool?
    public var ampBrandName: String?
    public var ampVolume: Int?
    public var ampMaxVolume: Int?
    public var ampMuted: Bool?
    public var ampConnected: Bool?
    public var ampSoundCheckEnabled: Bool?
    public var ampLowVolSmartNormEnabled: Bool?
    public var ampSoundCheckGainDb: Double?
    public var ampSoundCheckOffset: Int?
    public var ampBaseVolume: Int?

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
        case audioDeviceBitDepth = "audio_device_bit_depth"
        case isBitPerfect = "is_bit_perfect"
        case isDacMutingGuardEnabled = "dac_muting_guard_enabled"
        case dacMutingGuardMs = "dac_muting_guard_ms"
        case spectralAnalysis = "spectral_analysis"
        case ampVolumeControlEnabled = "amp_volume_control"
        case ampBrandName = "amp_brand_name"
        case ampVolume = "amp_volume"
        case ampMaxVolume = "amp_max_volume"
        case ampMuted = "amp_muted"
        case ampConnected = "amp_connected"
        case ampSoundCheckEnabled = "amp_soundcheck_enabled"
        case ampLowVolSmartNormEnabled = "amp_low_vol_smart_norm_enabled"
        case ampSoundCheckGainDb = "amp_soundcheck_gain_db"
        case ampSoundCheckOffset = "amp_soundcheck_offset"
        case ampBaseVolume = "amp_base_volume"
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
        audioDeviceBitDepth: Int? = nil,
        isBitPerfect: Bool? = nil,
        isDacMutingGuardEnabled: Bool? = nil,
        dacMutingGuardMs: Int? = nil,
        spectralAnalysis: SpectralAnalysisInfo? = nil,
        ampVolumeControlEnabled: Bool? = nil,
        ampBrandName: String? = nil,
        ampVolume: Int? = nil,
        ampMaxVolume: Int? = nil,
        ampMuted: Bool? = nil,
        ampConnected: Bool? = nil,
        ampSoundCheckEnabled: Bool? = nil,
        ampLowVolSmartNormEnabled: Bool? = nil,
        ampSoundCheckGainDb: Double? = nil,
        ampSoundCheckOffset: Int? = nil,
        ampBaseVolume: Int? = nil
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
        self.audioDeviceBitDepth = audioDeviceBitDepth
        self.isBitPerfect = isBitPerfect
        self.isDacMutingGuardEnabled = isDacMutingGuardEnabled
        self.dacMutingGuardMs = dacMutingGuardMs
        self.spectralAnalysis = spectralAnalysis
        self.ampVolumeControlEnabled = ampVolumeControlEnabled
        self.ampBrandName = ampBrandName
        self.ampVolume = ampVolume
        self.ampMaxVolume = ampMaxVolume
        self.ampMuted = ampMuted
        self.ampConnected = ampConnected
        self.ampSoundCheckEnabled = ampSoundCheckEnabled
        self.ampLowVolSmartNormEnabled = ampLowVolSmartNormEnabled
        self.ampSoundCheckGainDb = ampSoundCheckGainDb
        self.ampSoundCheckOffset = ampSoundCheckOffset
        self.ampBaseVolume = ampBaseVolume
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
        self.audioDeviceBitDepth = try container.decodeIfPresent(Int.self, forKey: .audioDeviceBitDepth)
        self.isBitPerfect = try container.decodeIfPresent(Bool.self, forKey: .isBitPerfect)
        self.isDacMutingGuardEnabled = try container.decodeIfPresent(Bool.self, forKey: .isDacMutingGuardEnabled)
        self.dacMutingGuardMs = try container.decodeIfPresent(Int.self, forKey: .dacMutingGuardMs)
        self.spectralAnalysis = try container.decodeIfPresent(SpectralAnalysisInfo.self, forKey: .spectralAnalysis)
        self.ampVolumeControlEnabled = try container.decodeIfPresent(Bool.self, forKey: .ampVolumeControlEnabled)
        self.ampBrandName = try container.decodeIfPresent(String.self, forKey: .ampBrandName)
        self.ampVolume = try container.decodeIfPresent(Int.self, forKey: .ampVolume)
        self.ampMaxVolume = try container.decodeIfPresent(Int.self, forKey: .ampMaxVolume)
        self.ampMuted = try container.decodeIfPresent(Bool.self, forKey: .ampMuted)
        self.ampConnected = try container.decodeIfPresent(Bool.self, forKey: .ampConnected)
        self.ampSoundCheckEnabled = try container.decodeIfPresent(Bool.self, forKey: .ampSoundCheckEnabled)
        self.ampLowVolSmartNormEnabled = try container.decodeIfPresent(Bool.self, forKey: .ampLowVolSmartNormEnabled)
        self.ampSoundCheckGainDb = try container.decodeIfPresent(Double.self, forKey: .ampSoundCheckGainDb)
        self.ampSoundCheckOffset = try container.decodeIfPresent(Int.self, forKey: .ampSoundCheckOffset)
        self.ampBaseVolume = try container.decodeIfPresent(Int.self, forKey: .ampBaseVolume)
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
}

// MARK: - Playlist Info

public struct PlaylistInfo: Codable, Sendable {
    public var name: String
    public var trackCount: Int
    public var artworkUrl: String?
    public var isPlaylist: Bool
    public var id: String?
    public var url: String?
    public var curatorName: String?
    public var description: String?

    enum CodingKeys: String, CodingKey {
        case name
        case trackCount = "track_count"
        case artworkUrl = "artwork_url"
        case isPlaylist = "is_playlist"
        case id
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
        url: String? = nil,
        curatorName: String? = nil,
        description: String? = nil
    ) {
        self.name = name
        self.trackCount = trackCount
        self.artworkUrl = artworkUrl
        self.isPlaylist = isPlaylist
        self.id = id
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

// MARK: - Apple Digital Booklet Viewer (PDF)

public struct BookletPageInfo: Codable, Sendable, Equatable {
    public var pageIndex: Int
    public var pageNumber: Int
    public var width: Double
    public var height: Double
    public var aspectRatio: Double
    public var title: String?
    public var imageUrl: String
    public var thumbUrl: String

    enum CodingKeys: String, CodingKey {
        case pageIndex = "page_index"
        case pageNumber = "page_number"
        case width
        case height
        case aspectRatio = "aspect_ratio"
        case title
        case imageUrl = "image_url"
        case thumbUrl = "thumb_url"
    }

    public init(
        pageIndex: Int,
        pageNumber: Int,
        width: Double,
        height: Double,
        aspectRatio: Double,
        title: String? = nil,
        imageUrl: String,
        thumbUrl: String
    ) {
        self.pageIndex = pageIndex
        self.pageNumber = pageNumber
        self.width = width
        self.height = height
        self.aspectRatio = aspectRatio
        self.title = title
        self.imageUrl = imageUrl
        self.thumbUrl = thumbUrl
    }
}

public struct BookletTrackCreditInfo: Codable, Sendable, Equatable {
    public var number: Int
    public var discNumber: Int
    public var title: String
    public var artist: String
    public var composer: String
    public var durationSeconds: Double
    public var isrc: String
    public var audioBadge: String
    public var commentary: String
    public var producers: [String]
    public var vocals: [String]
    public var instruments: [String]
    public var samples: [String]
    public var studios: [String]

    enum CodingKeys: String, CodingKey {
        case number
        case discNumber = "disc_number"
        case title
        case artist
        case composer
        case durationSeconds = "duration_seconds"
        case isrc
        case audioBadge = "audio_badge"
        case commentary
        case producers
        case vocals
        case instruments
        case samples
        case studios
    }

    public init(
        number: Int,
        discNumber: Int = 1,
        title: String,
        artist: String,
        composer: String,
        durationSeconds: Double,
        isrc: String = "",
        audioBadge: String = "",
        commentary: String = "",
        producers: [String] = [],
        vocals: [String] = [],
        instruments: [String] = [],
        samples: [String] = [],
        studios: [String] = []
    ) {
        self.number = number
        self.discNumber = discNumber
        self.title = title
        self.artist = artist
        self.composer = composer
        self.durationSeconds = durationSeconds
        self.isrc = isrc
        self.audioBadge = audioBadge
        self.commentary = commentary
        self.producers = producers
        self.vocals = vocals
        self.instruments = instruments
        self.samples = samples
        self.studios = studios
    }
}

public struct BookletEditorialContent: Codable, Sendable, Equatable {
    public var genre: String
    public var releaseDate: String
    public var recordLabel: String
    public var copyright: String
    public var isMasteredForItunes: Bool
    public var audioTraits: [String]
    public var artworkUrl: String
    public var summaryQuote: String
    public var editorialParagraphs: [String]
    public var recordingStudios: [String]
    public var tracks: [BookletTrackCreditInfo]

    enum CodingKeys: String, CodingKey {
        case genre
        case releaseDate = "release_date"
        case recordLabel = "record_label"
        case copyright
        case isMasteredForItunes = "is_mastered_for_itunes"
        case audioTraits = "audio_traits"
        case artworkUrl = "artwork_url"
        case summaryQuote = "summary_quote"
        case editorialParagraphs = "editorial_paragraphs"
        case recordingStudios = "recording_studios"
        case tracks
    }

    public init(
        genre: String = "",
        releaseDate: String = "",
        recordLabel: String = "",
        copyright: String = "",
        isMasteredForItunes: Bool = false,
        audioTraits: [String] = [],
        artworkUrl: String = "",
        summaryQuote: String = "",
        editorialParagraphs: [String] = [],
        recordingStudios: [String] = [],
        tracks: [BookletTrackCreditInfo] = []
    ) {
        self.genre = genre
        self.releaseDate = releaseDate
        self.recordLabel = recordLabel
        self.copyright = copyright
        self.isMasteredForItunes = isMasteredForItunes
        self.audioTraits = audioTraits
        self.artworkUrl = artworkUrl
        self.summaryQuote = summaryQuote
        self.editorialParagraphs = editorialParagraphs
        self.recordingStudios = recordingStudios
        self.tracks = tracks
    }
}

public struct BookletInfo: Codable, Sendable, Equatable {
    public var available: Bool
    public var bookletId: String
    public var title: String
    public var album: String
    public var artist: String
    public var source: String
    public var sourceTitle: String
    public var isOriginalPdf: Bool
    public var hasEditorialNotes: Bool
    public var pageCount: Int
    public var fileSizeBytes: Int
    public var recordLabel: String?
    public var copyright: String?
    public var releaseDate: String?
    public var pdfUrl: String
    public var pages: [BookletPageInfo]
    public var editorial: BookletEditorialContent?

    enum CodingKeys: String, CodingKey {
        case available
        case bookletId = "booklet_id"
        case title
        case album
        case artist
        case source
        case sourceTitle = "source_title"
        case isOriginalPdf = "is_original_pdf"
        case hasEditorialNotes = "has_editorial_notes"
        case pageCount = "page_count"
        case fileSizeBytes = "file_size_bytes"
        case recordLabel = "record_label"
        case copyright
        case releaseDate = "release_date"
        case pdfUrl = "pdf_url"
        case pages
        case editorial
    }

    public init(
        available: Bool,
        bookletId: String,
        title: String,
        album: String,
        artist: String,
        source: String,
        sourceTitle: String,
        isOriginalPdf: Bool,
        hasEditorialNotes: Bool = false,
        pageCount: Int,
        fileSizeBytes: Int,
        recordLabel: String? = nil,
        copyright: String? = nil,
        releaseDate: String? = nil,
        pdfUrl: String,
        pages: [BookletPageInfo],
        editorial: BookletEditorialContent? = nil
    ) {
        self.available = available
        self.bookletId = bookletId
        self.title = title
        self.album = album
        self.artist = artist
        self.source = source
        self.sourceTitle = sourceTitle
        self.isOriginalPdf = isOriginalPdf
        self.hasEditorialNotes = hasEditorialNotes
        self.pageCount = pageCount
        self.fileSizeBytes = fileSizeBytes
        self.recordLabel = recordLabel
        self.copyright = copyright
        self.releaseDate = releaseDate
        self.pdfUrl = pdfUrl
        self.pages = pages
        self.editorial = editorial
    }
}


