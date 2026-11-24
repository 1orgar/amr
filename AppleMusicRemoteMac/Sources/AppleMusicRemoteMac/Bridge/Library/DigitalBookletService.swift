//
//  DigitalBookletService.swift
//  AppleMusicRemoteMac
//
//  Official Apple Digital Booklet (PDF) discovery from Music.app / iTunes Media
//  and comprehensive multi-page album + track-by-track liner notes & credits PDF renderer.
//  Never fabricates synthetic boilerplate: if an album has neither a PDF in Music.app nor
//  real editorial/encyclopedic/credits data, returns available = false.
//

import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import PDFKit

public final class DigitalBookletService: @unchecked Sendable {
    public static let shared = DigitalBookletService()

    internal struct CachedBookletEntry {
        let info: BookletInfo
        let pdfData: Data?
        let fileURL: URL?
        let timestamp: Date
    }

    public struct AlbumCatalogMetadata: Sendable {
        public var albumId: String = ""
        public var albumName: String = ""
        public var artistName: String = ""
        public var releaseDate: String = ""
        public var genre: String = ""
        public var recordLabel: String = ""
        public var copyright: String = ""
        public var editorialStandard: String = ""
        public var editorialShort: String = ""
        public var albumHistoryParagraphs: [String] = []
        public var recordingStudios: [String] = []
        public var isMasteredForItunes: Bool = false
        public var audioTraits: [String] = []
        public var artworkUrl: String = ""
        public var artworkData: Data? = nil
        public var directPdfUrl: String? = nil
        public var tracks: [CatalogTrackCredit] = []

        public init(
            albumId: String = "",
            albumName: String = "",
            artistName: String = "",
            releaseDate: String = "",
            genre: String = "",
            recordLabel: String = "",
            copyright: String = "",
            editorialStandard: String = "",
            editorialShort: String = "",
            albumHistoryParagraphs: [String] = [],
            recordingStudios: [String] = [],
            isMasteredForItunes: Bool = false,
            audioTraits: [String] = [],
            artworkUrl: String = "",
            artworkData: Data? = nil,
            directPdfUrl: String? = nil,
            tracks: [CatalogTrackCredit] = []
        ) {
            self.albumId = albumId
            self.albumName = albumName
            self.artistName = artistName
            self.releaseDate = releaseDate
            self.genre = genre
            self.recordLabel = recordLabel
            self.copyright = copyright
            self.editorialStandard = editorialStandard
            self.editorialShort = editorialShort
            self.albumHistoryParagraphs = albumHistoryParagraphs
            self.recordingStudios = recordingStudios
            self.isMasteredForItunes = isMasteredForItunes
            self.audioTraits = audioTraits
            self.artworkUrl = artworkUrl
            self.artworkData = artworkData
            self.directPdfUrl = directPdfUrl
            self.tracks = tracks
        }
    }

    public struct CatalogTrackCredit: Sendable {
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

    internal struct BookletBox: @unchecked Sendable {
        let info: BookletInfo
    }

    internal let lock = NSLock()
    internal let pdfRenderLock = NSLock()
    /// Serializes AppKit/CoreGraphics PDF synthesis so concurrent tasks never race on `NSGraphicsContext.current` or shared text layout caches.
    internal let pdfSynthesisQueue = DispatchQueue(label: "com.amr.booklet.pdf-synthesis", qos: .userInitiated)
    internal var bookletCache: [String: CachedBookletEntry] = [:]
    internal var inFlightBookletTasks: [String: Task<BookletBox, Never>] = [:]
    internal var renderedPageCache: [String: Data] = [:]
    internal var renderedPageOrder: [String] = []
    internal let maxRenderedPageCacheEntries = 60
    internal let session: URLSession

    /// Additional local directories to scan for Apple Digital Booklet PDFs (used by unit tests).
    internal var _additionalSearchDirectories: [URL] = []
    public var additionalSearchDirectories: [URL] {
        get { lock.withLock { _additionalSearchDirectories } }
        set { lock.withLock { _additionalSearchDirectories = newValue } }
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6.0
        config.timeoutIntervalForResource = 12.0
        self.session = URLSession(configuration: config)
    }

    // MARK: - Input Validation Helpers

    public static func isValidSafeIdentifier(_ raw: String) -> Bool {
        guard !raw.isEmpty, raw.count <= 128 else { return false }
        return raw.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    }

    public static func isValidStorefront(_ raw: String) -> Bool {
        return raw.range(of: #"^[a-zA-Z]{2,5}$"#, options: .regularExpression) != nil
    }

    internal static func isValidWikipediaLang(_ raw: String) -> Bool {
        return raw.range(of: #"^[a-z]{2,12}(-[a-z]{2,8})?$"#, options: .regularExpression) != nil
    }

    // MARK: - Deterministic Booklet ID

    public static func makeBookletId(album: String, artist: String) -> String {
        let normAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let raw = "booklet|\(normArtist)|\(normAlbum)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    public func clearCache() {
        lock.withLock {
            bookletCache.removeAll()
            renderedPageCache.removeAll()
            renderedPageOrder.removeAll()
        }
    }

    // MARK: - Public Resolution API

    public func resolveBooklet(
        album: String? = nil,
        artist: String? = nil,
        albumId: String? = nil,
        trackName: String? = nil,
        forceRefresh: Bool = false
    ) async -> BookletInfo {
        let trimmedAlbum = (album?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        let trimmedArtist = (artist?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        let fallbackStatus: PlayerStatus? = (trimmedAlbum == nil || trimmedArtist == nil) ? MusicBridge.shared.getPlayerStatus() : nil

        let effAlbum = trimmedAlbum
            ?? fallbackStatus?.track?.album.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        let effArtist = trimmedArtist
            ?? fallbackStatus?.track?.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        let bookletId = Self.makeBookletId(album: effAlbum, artist: effArtist)

        guard !effAlbum.isEmpty else {
            return makeUnavailableInfo(bookletId: bookletId, album: effAlbum, artist: effArtist)
        }

        if !forceRefresh {
            let lookup: (cached: BookletInfo?, existingTask: Task<BookletBox, Never>?) = lock.withLock {
                if let cached = bookletCache[bookletId], Date().timeIntervalSince(cached.timestamp) < 300 {
                    return (cached.info, nil)
                }
                return (nil, inFlightBookletTasks[bookletId])
            }
            if let info = lookup.cached {
                return info
            }
            if let existing = lookup.existingTask {
                return (await existing.value).info
            }

            let task = Task<BookletBox, Never> {
                let resolved = await self.performResolveBooklet(
                    bookletId: bookletId,
                    effAlbum: effAlbum,
                    effArtist: effArtist,
                    albumId: albumId,
                    trackName: trackName,
                    fallbackStatus: fallbackStatus
                )
                return BookletBox(info: resolved)
            }
            let taskToAwait: Task<BookletBox, Never> = lock.withLock {
                if let raced = inFlightBookletTasks[bookletId] {
                    task.cancel()
                    return raced
                }
                inFlightBookletTasks[bookletId] = task
                return task
            }
            let result = (await taskToAwait.value).info
            lock.withLock {
                if inFlightBookletTasks[bookletId] == taskToAwait {
                    inFlightBookletTasks.removeValue(forKey: bookletId)
                }
            }
            return result
        }

        return await performResolveBooklet(
            bookletId: bookletId,
            effAlbum: effAlbum,
            effArtist: effArtist,
            albumId: albumId,
            trackName: trackName,
            fallbackStatus: fallbackStatus
        )
    }

    internal func performResolveBooklet(
        bookletId: String,
        effAlbum: String,
        effArtist: String,
        albumId: String?,
        trackName: String?,
        fallbackStatus: PlayerStatus?
    ) async -> BookletInfo {

        // 1. Check Music.app library & local Apple Music / iTunes Media folders for a native PDF file
        if let localPdfUrl = findAppleDigitalBookletPdf(album: effAlbum, artist: effArtist),
           let data = try? Data(contentsOf: localPdfUrl),
           let doc = PDFDocument(data: data), doc.pageCount > 0 {
            let info = buildBookletInfo(
                bookletId: bookletId,
                doc: doc,
                pdfData: data,
                album: effAlbum,
                artist: effArtist,
                source: "apple_music_library_pdf",
                sourceTitle: "Apple Digital Booklet (PDF)",
                isOriginalPdf: true,
                hasEditorialNotes: true,
                fileURL: localPdfUrl
            )
            storeInCache(bookletId: bookletId, info: info, pdfData: data, fileURL: localPdfUrl)
            return info
        }

        // 2. Check Apple Music Catalog + MusicBrainz + Wikipedia for comprehensive album & track-by-track booklet data
        let meta = await fetchAlbumCatalogMetadata(
            album: effAlbum,
            artist: effArtist,
            albumId: albumId
        )

        // 2a. Direct PDF URL from Apple Catalog if present (strictly validated on Apple CDN hosts)
        if let pdfUrlStr = meta.directPdfUrl,
           let pdfUrl = URL(string: pdfUrlStr),
           ArtworkService.isAllowedRemoteArtworkURL(pdfUrl),
           let (pdfBytes, resp) = try? await session.data(from: pdfUrl),
           pdfBytes.count <= 50 * 1024 * 1024,
           let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
           let doc = PDFDocument(data: pdfBytes), doc.pageCount > 0 {
            let info = buildBookletInfo(
                bookletId: bookletId,
                doc: doc,
                pdfData: pdfBytes,
                album: meta.albumName.isEmpty ? effAlbum : meta.albumName,
                artist: meta.artistName.isEmpty ? effArtist : meta.artistName,
                source: "apple_music_catalog_pdf",
                sourceTitle: "Apple Digital Booklet (PDF)",
                isOriginalPdf: true,
                hasEditorialNotes: true,
                recordLabel: meta.recordLabel.isEmpty ? nil : meta.recordLabel,
                copyright: meta.copyright.isEmpty ? nil : meta.copyright,
                releaseDate: meta.releaseDate.isEmpty ? nil : meta.releaseDate,
                fileURL: nil
            )
            storeInCache(bookletId: bookletId, info: info, pdfData: pdfBytes, fileURL: nil)
            return info
        }

        // 2b. Official Apple Music Editorial & Comprehensive Track-by-Track Booklet
        let hasRichContent = !meta.editorialStandard.isEmpty
            || !meta.editorialShort.isEmpty
            || !meta.albumHistoryParagraphs.isEmpty
            || meta.tracks.contains { !$0.commentary.isEmpty || !$0.instruments.isEmpty || !$0.vocals.isEmpty || !$0.producers.isEmpty }

        if hasRichContent {
            let cachedStatus = fallbackStatus ?? PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.lastPlayerStatusCache?.status }
            let isPlayingRequestedAlbum: Bool = {
                guard let curTrack = cachedStatus?.track else { return false }
                let curAlbum = curTrack.album.trimmingCharacters(in: .whitespacesAndNewlines)
                if !curAlbum.isEmpty && curAlbum.localizedCaseInsensitiveCompare(effAlbum) == .orderedSame {
                    return true
                }
                if let reqTrack = trackName?.trimmingCharacters(in: .whitespacesAndNewlines), !reqTrack.isEmpty,
                   curTrack.name.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(reqTrack) == .orderedSame {
                    return true
                }
                return false
            }()
            let qualityLabel: String? = isPlayingRequestedAlbum ? cachedStatus?.audioQuality : nil
            let (pdfData, pageTitles) = renderComprehensiveEditorialBookletPdf(meta: meta, audioQualityLabel: qualityLabel)
            if let doc = PDFDocument(data: pdfData), doc.pageCount > 0 {
                let editorialPayload = buildEditorialContentPayload(from: meta)
                let info = buildBookletInfo(
                    bookletId: bookletId,
                    doc: doc,
                    pdfData: pdfData,
                    album: meta.albumName.isEmpty ? effAlbum : meta.albumName,
                    artist: meta.artistName.isEmpty ? effArtist : meta.artistName,
                    source: "apple_music_editorial",
                    sourceTitle: "Apple Music Digital Booklet",
                    isOriginalPdf: false,
                    hasEditorialNotes: true,
                    recordLabel: meta.recordLabel.isEmpty ? nil : meta.recordLabel,
                    copyright: meta.copyright.isEmpty ? nil : meta.copyright,
                    releaseDate: meta.releaseDate.isEmpty ? nil : meta.releaseDate,
                    customPageTitles: pageTitles,
                    editorial: editorialPayload,
                    fileURL: nil
                )
                storeInCache(bookletId: bookletId, info: info, pdfData: pdfData, fileURL: nil)
                return info
            }
        }

        // 3. No booklet or editorial notes exist for this album -> unavailable
        let unavailable = makeUnavailableInfo(bookletId: bookletId, album: effAlbum, artist: effArtist)
        storeInCache(bookletId: bookletId, info: unavailable, pdfData: nil, fileURL: nil)
        return unavailable
    }

    // MARK: - Raw PDF & High-DPI Page Rendering (PDFKit)

    public func getPdfData(bookletId: String) -> (data: Data, filename: String)? {
        return lock.withLock {
            guard let entry = bookletCache[bookletId],
                  entry.info.available,
                  let data = entry.pdfData,
                  !data.isEmpty else {
                return nil
            }
            let safeArtist = sanitizeFilename(entry.info.artist)
            let safeAlbum = sanitizeFilename(entry.info.album)
            let filename = "Digital Booklet - \(safeArtist) - \(safeAlbum).pdf"
            return (data, filename)
        }
    }

    public func renderPageImage(bookletId: String, pageIndex: Int, maxDimension: CGFloat = 1600) -> Data? {
        let clampedDim = max(240, min(2400, maxDimension))
        let cacheKey = "\(bookletId)|\(pageIndex)|\(Int(clampedDim))"

        let cachedOrPdf: (cachedImage: Data?, pdfData: Data?) = lock.withLock {
            if let img = renderedPageCache[cacheKey] {
                return (img, nil)
            }
            return (nil, bookletCache[bookletId]?.pdfData)
        }

        if let cachedImg = cachedOrPdf.cachedImage {
            return cachedImg
        }

        pdfRenderLock.lock()
        defer { pdfRenderLock.unlock() }

        if let afterWaitImg = lock.withLock({ renderedPageCache[cacheKey] }) {
            return afterWaitImg
        }

        guard let data = cachedOrPdf.pdfData,
              let doc = PDFDocument(data: data),
              pageIndex >= 0,
              pageIndex < doc.pageCount,
              let page = doc.page(at: pageIndex),
              let jpegData = Self.rasterizePdfPageToJpeg(page: page, maxDimension: clampedDim) else {
            return nil
        }

        lock.withLock {
            while renderedPageCache[cacheKey] == nil && renderedPageCache.count >= maxRenderedPageCacheEntries {
                if !renderedPageOrder.isEmpty {
                    let oldestKey = renderedPageOrder.removeFirst()
                    renderedPageCache.removeValue(forKey: oldestKey)
                } else if let firstKey = renderedPageCache.keys.first {
                    renderedPageCache.removeValue(forKey: firstKey)
                } else {
                    break
                }
            }
            if renderedPageCache[cacheKey] == nil {
                renderedPageOrder.append(cacheKey)
            }
            renderedPageCache[cacheKey] = jpegData
        }
        return jpegData
    }

    public static func rasterizePdfPageToJpeg(page: PDFPage, maxDimension: CGFloat = 1600) -> Data? {
        let rawBounds = page.bounds(for: .mediaBox)
        let rotation = ((page.rotation % 360) + 360) % 360
        let pageWidth = (rotation == 90 || rotation == 270) ? rawBounds.height : rawBounds.width
        let pageHeight = (rotation == 90 || rotation == 270) ? rawBounds.width : rawBounds.height
        guard pageWidth > 1, pageHeight > 1 else { return nil }

        let scale = maxDimension / max(pageWidth, pageHeight)
        let pixelW = max(1, Int((pageWidth * scale).rounded()))
        let pixelH = max(1, Int((pageHeight * scale).rounded()))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        ctx.interpolationQuality = .high
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))

        ctx.saveGState()
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        ctx.restoreGState()

        guard let cgImage = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.88])
    }
}
