//
//  BookletModels.swift
//  AppleMusicRemoteMac
//
//  Apple Digital Booklet Viewer (PDF & editorial) models
//

import Foundation

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
