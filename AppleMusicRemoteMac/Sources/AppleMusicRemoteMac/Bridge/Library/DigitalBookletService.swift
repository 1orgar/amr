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
import CryptoKit
import Foundation
import PDFKit

public final class DigitalBookletService: @unchecked Sendable {
    public static let shared = DigitalBookletService()

    private struct CachedBookletEntry {
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

    private let lock = NSLock()
    private let pdfRenderLock = NSLock()
    private var bookletCache: [String: CachedBookletEntry] = [:]
    private var renderedPageCache: [String: Data] = [:]
    private var renderedPageOrder: [String] = []
    private let maxRenderedPageCacheEntries = 60
    private let session: URLSession

    /// Additional local directories to scan for Apple Digital Booklet PDFs (used by unit tests).
    private var _additionalSearchDirectories: [URL] = []
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
        let status = MusicBridge.shared.getPlayerStatus()
        let effAlbum = (album?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? status.track?.album.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        let effArtist = (artist?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? status.track?.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        let bookletId = Self.makeBookletId(album: effAlbum, artist: effArtist)

        guard !effAlbum.isEmpty else {
            return makeUnavailableInfo(bookletId: bookletId, album: effAlbum, artist: effArtist)
        }

        if !forceRefresh {
            let cachedInfo: BookletInfo? = lock.withLock {
                if let cached = bookletCache[bookletId], Date().timeIntervalSince(cached.timestamp) < 300 {
                    return cached.info
                }
                return nil
            }
            if let info = cachedInfo {
                return info
            }
        }

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

        // 2a. Direct PDF URL from Apple Catalog if present
        if let pdfUrlStr = meta.directPdfUrl,
           let pdfUrl = URL(string: pdfUrlStr),
           let (pdfBytes, resp) = try? await session.data(from: pdfUrl),
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
            let isPlayingRequestedAlbum: Bool = {
                guard let curTrack = status.track else { return false }
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
            let qualityLabel: String? = isPlayingRequestedAlbum ? status.audioQuality : nil
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

    // MARK: - Apple Digital Booklet Discovery (Music.app & ~/Music Media Library)

    private func sanitizeFolderComponent(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != ".",
              trimmed != "..",
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              !trimmed.contains("\0") else {
            return nil
        }
        return trimmed
    }

    private func isSafeSubpath(_ candidate: URL, under root: URL) -> Bool {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let candidatePath = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : (rootPath + "/")
        return candidatePath == rootPath || candidatePath.hasPrefix(prefix)
    }

    private func isRegularNonSymlinkFile(_ url: URL) -> Bool {
        guard let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              vals.isRegularFile == true,
              vals.isSymbolicLink != true else {
            return false
        }
        return true
    }

    private func findAppleDigitalBookletPdf(album: String, artist: String) -> URL? {
        guard !album.isEmpty else { return nil }
        let fm = FileManager.default

        let extraDirs = additionalSearchDirectories
        for root in extraDirs where fm.fileExists(atPath: root.path) {
            if let safeArtist = sanitizeFolderComponent(artist),
               let safeAlbum = sanitizeFolderComponent(album) {
                let candidateDir = root
                    .appendingPathComponent(safeArtist, isDirectory: true)
                    .appendingPathComponent(safeAlbum, isDirectory: true)
                if isSafeSubpath(candidateDir, under: root),
                   let pdf = firstPdfInDirectory(candidateDir),
                   isSafeSubpath(pdf, under: root) {
                    return pdf
                }
            }
            if let pdf = firstMatchingPdfInDirectory(root, album: album) {
                return pdf
            }
        }

        if !PlaybackRouter.shared.isTestingEnvironment && MusicAppProvider.shared.isMusicAppRunning {
            let escAlbum = album
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
            tell application "Music"
                try
                    with timeout of 1.5 seconds
                        set albumTracks to (every file track of library playlist 1 whose album is "\(escAlbum)")
                        repeat with t in albumTracks
                            try
                                set k to (kind of t as string)
                                set loc to POSIX path of (get location of t)
                                if k contains "PDF" or loc ends with ".pdf" or loc ends with ".PDF" then
                                    return loc
                                end if
                            end try
                        end repeat
                        set bookletTracks to (every file track of library playlist 1 whose name contains "Digital Booklet" and name contains "\(escAlbum)")
                        repeat with bt in bookletTracks
                            try
                                set loc to POSIX path of (get location of bt)
                                if loc ends with ".pdf" or loc ends with ".PDF" then
                                    return loc
                                end if
                            end try
                        end repeat
                        if (count of albumTracks) > 0 then
                            set firstLoc to POSIX path of (get location of item 1 of albumTracks)
                            return firstLoc
                        end if
                    end timeout
                end try
                return ""
            end tell
            """
            if let pathStr = AppleScriptExecutor.shared.execute(script).output?.trimmingCharacters(in: .whitespacesAndNewlines),
               !pathStr.isEmpty {
                let url = URL(fileURLWithPath: pathStr)
                if url.pathExtension.lowercased() == "pdf" && fm.fileExists(atPath: url.path) && isRegularNonSymlinkFile(url) {
                    return url
                }
                if isRegularNonSymlinkFile(url) {
                    let albumDir = url.deletingLastPathComponent()
                    let isDedicatedAlbumFolder = albumDir.lastPathComponent.localizedCaseInsensitiveCompare(album) == .orderedSame
                    if isDedicatedAlbumFolder {
                        if let foundInDir = firstPdfInDirectory(albumDir), isSafeSubpath(foundInDir, under: albumDir) {
                            return foundInDir
                        }
                    } else if let foundInDir = firstPdfInDirectory(albumDir, requireAlbumOrBookletMatch: album), isSafeSubpath(foundInDir, under: albumDir) {
                        return foundInDir
                    }
                }
            }
        }

        let home = URL(fileURLWithPath: NSHomeDirectory())
        let musicRoots = [
            home.appendingPathComponent("Music/Music/Media.localized/Music", isDirectory: true),
            home.appendingPathComponent("Music/Music/Media.localized/Apple Music", isDirectory: true),
            home.appendingPathComponent("Music/Music/Media/Music", isDirectory: true),
            home.appendingPathComponent("Music/Music/Media/Apple Music", isDirectory: true),
            home.appendingPathComponent("Music/iTunes/iTunes Media/Music", isDirectory: true),
            home.appendingPathComponent("Music/iTunes/iTunes Media/Apple Music", isDirectory: true)
        ]

        let artistVariants = Set([artist, "Compilations", "Various Artists"].filter { !$0.isEmpty })
        for root in musicRoots where fm.fileExists(atPath: root.path) {
            for artFolder in artistVariants {
                guard let safeArtist = sanitizeFolderComponent(artFolder),
                      let safeAlbum = sanitizeFolderComponent(album) else {
                    continue
                }
                let candidateDir = root
                    .appendingPathComponent(safeArtist, isDirectory: true)
                    .appendingPathComponent(safeAlbum, isDirectory: true)
                guard isSafeSubpath(candidateDir, under: root) else {
                    continue
                }
                if let pdf = firstPdfInDirectory(candidateDir), isSafeSubpath(pdf, under: root) {
                    return pdf
                }
            }
        }

        return nil
    }

    private func firstPdfInDirectory(_ dir: URL, requireAlbumOrBookletMatch albumMatch: String? = nil) -> URL? {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let pdfs = items.filter {
            $0.pathExtension.lowercased() == "pdf" && isRegularNonSymlinkFile($0) && isSafeSubpath($0, under: dir)
        }
        if let bookletPdf = pdfs.first(where: { $0.lastPathComponent.lowercased().contains("booklet") }) {
            return bookletPdf
        }
        if let album = albumMatch?.trimmingCharacters(in: .whitespacesAndNewlines), !album.isEmpty {
            let normAlbum = album.lowercased()
            return pdfs.first(where: { $0.lastPathComponent.lowercased().contains(normAlbum) })
        }
        return pdfs.first
    }

    private func firstMatchingPdfInDirectory(_ dir: URL, album: String) -> URL? {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let normAlbum = album.lowercased()
        return items.first { url in
            url.pathExtension.lowercased() == "pdf"
                && url.lastPathComponent.lowercased().contains(normAlbum)
                && isRegularNonSymlinkFile(url)
                && isSafeSubpath(url, under: dir)
        }
    }

    // MARK: - Apple Music Catalog + MusicBrainz + Wikipedia Comprehensive Fetcher

    private func fetchAlbumCatalogMetadata(
        album: String,
        artist: String,
        albumId: String?
    ) async -> AlbumCatalogMetadata {
        var meta = AlbumCatalogMetadata(
            albumId: (albumId ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            albumName: album,
            artistName: artist
        )

        if PlaybackRouter.shared.isTestingEnvironment {
            return meta
        }

        guard let devToken = MusicKitManager.shared.getDeveloperToken() else {
            return meta
        }

        let sf = MusicKitManager.shared.getUserStorefront().lowercased()
        let lang = MusicKitManager.shared.getPreferredLanguageTag()

        // 1. Resolve Album ID if not provided
        if meta.albumId.isEmpty {
            let cleanAlbum = album
                .replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s*\[.*?\]"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let searchTerm = "\(cleanAlbum.isEmpty ? album : cleanAlbum) \(artist)".trimmingCharacters(in: .whitespacesAndNewlines)
            let encoded = searchTerm.amrQueryValueEncoded
            if let url = URL(string: "https://api.music.apple.com/v1/catalog/\(sf)/search?term=\(encoded)&types=albums&limit=3&l=\(lang)") {
                var req = URLRequest(url: url)
                req.timeoutInterval = 4.0
                req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                if let (data, resp) = try? await session.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let results = json["results"] as? [String: Any],
                   let albumsObj = results["albums"] as? [String: Any],
                   let albumsData = albumsObj["data"] as? [[String: Any]],
                   let first = albumsData.first {
                    meta.albumId = first["id"] as? String ?? ""
                }
            }
        }

        guard !meta.albumId.isEmpty else {
            return meta
        }

        // 2. Query Apple Music Catalog in both user language and en-US to capture full editorial notes
        let queries: [(sf: String, lang: String)] = lang.lowercased().hasPrefix("en")
            ? [(sf, lang), ("us", "en-US")]
            : [(sf, lang), (sf, "en-US"), ("us", "en-US")]

        var localizedStandard = ""
        var englishStandard = ""

        for (idx, q) in queries.enumerated() {
            guard let url = URL(string: "https://api.music.apple.com/v1/catalog/\(q.sf)/albums/\(meta.albumId)?l=\(q.lang)") else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 4.5
            req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")

            guard let (data, resp) = try? await session.data(for: req),
                  let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArr = json["data"] as? [[String: Any]],
                  let albumObj = dataArr.first,
                  let attrs = albumObj["attributes"] as? [String: Any] else {
                continue
            }

            if idx == 0 || meta.tracks.isEmpty {
                meta.albumName = (attrs["name"] as? String) ?? meta.albumName
                meta.artistName = (attrs["artistName"] as? String) ?? meta.artistName
                meta.releaseDate = (attrs["releaseDate"] as? String) ?? meta.releaseDate
                meta.recordLabel = (attrs["recordLabel"] as? String) ?? meta.recordLabel
                meta.copyright = (attrs["copyright"] as? String) ?? meta.copyright
                if let genres = attrs["genreNames"] as? [String] {
                    var uniqueGenres: [String] = []
                    for g in genres {
                        let cleanG = g.trimmingCharacters(in: .whitespacesAndNewlines)
                        let lowerG = cleanG.lowercased()
                        if lowerG != "музыка" && lowerG != "music" && !cleanG.isEmpty && !uniqueGenres.contains(where: { $0.caseInsensitiveCompare(cleanG) == .orderedSame }) {
                            uniqueGenres.append(cleanG)
                        }
                    }
                    meta.genre = uniqueGenres.joined(separator: " • ")
                }
                meta.isMasteredForItunes = (attrs["isMasteredForItunes"] as? Bool) ?? false
                meta.audioTraits = (attrs["audioTraits"] as? [String]) ?? []

                if let pdfUrl = (attrs["bookletUrl"] as? String) ?? (attrs["digitalBookletUrl"] as? String) {
                    meta.directPdfUrl = pdfUrl
                }

                if let artObj = attrs["artwork"] as? [String: Any],
                   let tmpl = artObj["url"] as? String {
                    meta.artworkUrl = tmpl
                        .replacingOccurrences(of: "{w}x{h}", with: "1000x1000")
                        .replacingOccurrences(of: "{w}", with: "1000")
                        .replacingOccurrences(of: "{h}", with: "1000")
                        .replacingOccurrences(of: "{f}", with: "jpg")
                }

                if let rels = albumObj["relationships"] as? [String: Any],
                   let trksObj = rels["tracks"] as? [String: Any],
                   let trksData = trksObj["data"] as? [[String: Any]] {
                    meta.tracks = trksData.enumerated().compactMap { tIdx, item in
                        guard let tAttrs = item["attributes"] as? [String: Any] else { return nil }
                        let title = tAttrs["name"] as? String ?? ""
                        guard !title.isEmpty else { return nil }
                        let tArtist = tAttrs["artistName"] as? String ?? meta.artistName
                        let composer = tAttrs["composerName"] as? String ?? ""
                        let durMs = tAttrs["durationInMillis"] as? Double ?? 0
                        let num = tIdx + 1
                        let disc = tAttrs["discNumber"] as? Int ?? 1
                        let isrc = tAttrs["isrc"] as? String ?? ""
                        let isADM = (tAttrs["isAppleDigitalMaster"] as? Bool) ?? meta.isMasteredForItunes
                        let variants = (tAttrs["audioVariants"] as? [String]) ?? []
                        var badgeParts: [String] = []
                        if isADM { badgeParts.append("Apple Digital Master") }
                        if variants.contains(where: { $0.lowercased().contains("hi-res") }) {
                            badgeParts.append("Hi-Res Lossless")
                        } else if variants.contains(where: { $0.lowercased().contains("lossless") }) {
                            badgeParts.append("Lossless")
                        }
                        if variants.contains(where: { $0.lowercased().contains("atmos") }) {
                            badgeParts.append("Dolby Atmos")
                        }
                        return CatalogTrackCredit(
                            number: num,
                            discNumber: disc,
                            title: title,
                            artist: tArtist,
                            composer: composer,
                            durationSeconds: durMs / 1000.0,
                            isrc: isrc,
                            audioBadge: badgeParts.joined(separator: " • ")
                        )
                    }
                }
            }

            if let notes = attrs["editorialNotes"] as? [String: Any] {
                if let std = notes["standard"] as? String, !std.isEmpty {
                    let cleaned = Self.stripHtmlTags(std)
                    if q.lang.lowercased().hasPrefix("en") {
                        if englishStandard.isEmpty { englishStandard = cleaned }
                    } else {
                        if localizedStandard.isEmpty { localizedStandard = cleaned }
                    }
                }
                if let sh = notes["short"] as? String, !sh.isEmpty, meta.editorialShort.isEmpty {
                    meta.editorialShort = Self.stripHtmlTags(sh)
                }
            }

            if !localizedStandard.isEmpty && !englishStandard.isEmpty && !meta.tracks.isEmpty {
                break
            }
        }

        meta.editorialStandard = !localizedStandard.isEmpty ? localizedStandard : englishStandard

        // 3. Concurrently enrich with MusicBrainz full recording credits + Wikipedia album & track-by-track descriptions
        let targetAlbum = meta.albumName.isEmpty ? album : meta.albumName
        let targetArtist = meta.artistName.isEmpty ? artist : meta.artistName
        let currentTracks = meta.tracks
        let engFallback = englishStandard

        async let mbTask = fetchMusicBrainzTrackCredits(
            album: targetAlbum,
            artist: targetArtist,
            expectedTrackCount: currentTracks.count
        )
        async let wikiTask = fetchWikipediaAlbumAndTrackNotes(
            album: targetAlbum,
            artist: targetArtist,
            tracks: currentTracks,
            englishEditorialFallback: engFallback
        )

        let (mbCredits, wikiNotes) = await (mbTask, wikiTask)

        if !wikiNotes.albumHistoryParagraphs.isEmpty {
            meta.albumHistoryParagraphs = wikiNotes.albumHistoryParagraphs
        } else if !englishStandard.isEmpty && englishStandard != meta.editorialStandard {
            meta.albumHistoryParagraphs = englishStandard
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        if !mbCredits.releaseStudios.isEmpty {
            meta.recordingStudios = mbCredits.releaseStudios
        }

        // Merge per-track commentary & studio/musician credits into meta.tracks
        for i in 0..<meta.tracks.count {
            let t = meta.tracks[i]
            let normTitle = Self.normalizeTrackKey(t.title)

            if let comm = wikiNotes.trackCommentary[normTitle], !comm.isEmpty {
                meta.tracks[i].commentary = comm
            }

            if let mbTrack = mbCredits.byTrackNumber[t.number] ?? mbCredits.byNormalizedTitle[normTitle] {
                if meta.tracks[i].composer.isEmpty && !mbTrack.writers.isEmpty {
                    meta.tracks[i].composer = mbTrack.writers.joined(separator: ", ")
                } else if !mbTrack.writers.isEmpty {
                    // Merge any additional writers not already listed (ignoring punctuation differences like "Jr." vs ", Jr.")
                    var existing = meta.tracks[i].composer
                    let normExisting = existing.lowercased()
                        .replacingOccurrences(of: ",", with: "")
                        .replacingOccurrences(of: ".", with: "")
                        .replacingOccurrences(of: "‐", with: "-")
                    for w in mbTrack.writers {
                        let normW = w.lowercased()
                            .replacingOccurrences(of: ",", with: "")
                            .replacingOccurrences(of: ".", with: "")
                            .replacingOccurrences(of: "‐", with: "-")
                        if !normExisting.contains(normW) && !existing.localizedCaseInsensitiveContains(w) {
                            existing += ", \(w)"
                        }
                    }
                    meta.tracks[i].composer = existing
                }
                meta.tracks[i].producers = mbTrack.producers
                meta.tracks[i].vocals = mbTrack.vocals
                meta.tracks[i].instruments = mbTrack.instruments
                meta.tracks[i].samples = mbTrack.samples
                meta.tracks[i].studios = mbTrack.studios
            }
        }

        // 4. Fetch cover artwork bytes if we have booklet content to render
        let hasBookletContent = !meta.editorialStandard.isEmpty
            || !meta.editorialShort.isEmpty
            || !meta.albumHistoryParagraphs.isEmpty
            || meta.tracks.contains { !$0.commentary.isEmpty || !$0.instruments.isEmpty || !$0.vocals.isEmpty || !$0.producers.isEmpty }

        if hasBookletContent {
            if let localArt = MusicBridge.shared.getCurrentTrackArtwork(), !localArt.isEmpty,
               let stTrack = MusicBridge.shared.getPlayerStatus().track,
               stTrack.album.lowercased() == album.lowercased() {
                meta.artworkData = localArt
            } else if !meta.artworkUrl.isEmpty, let url = URL(string: meta.artworkUrl) {
                if let cached = ArtworkDiskCache.shared.get(key: meta.artworkUrl) {
                    meta.artworkData = cached
                } else if let (imgData, resp) = try? await session.data(from: url),
                          let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    ArtworkDiskCache.shared.set(key: meta.artworkUrl, data: imgData)
                    meta.artworkData = imgData
                }
            }
        }

        return meta
    }

    // MARK: - MusicBrainz Full Liner Notes & Musician Credits Fetcher

    private struct MBTrackCreditsResult: Sendable {
        var writers: [String] = []
        var producers: [String] = []
        var vocals: [String] = []
        var instruments: [String] = []
        var samples: [String] = []
        var studios: [String] = []
    }

    private struct MBAlbumCreditsResult: Sendable {
        var byTrackNumber: [Int: MBTrackCreditsResult] = [:]
        var byNormalizedTitle: [String: MBTrackCreditsResult] = [:]
        var releaseStudios: [String] = []
    }

    private func fetchMusicBrainzTrackCredits(
        album: String,
        artist: String,
        expectedTrackCount: Int
    ) async -> MBAlbumCreditsResult {
        var result = MBAlbumCreditsResult()
        let cleanAlbum = album
            .replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\[.*?\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAlbum.isEmpty else { return result }

        let queryStr = "release:\"\(cleanAlbum)\" AND artist:\"\(artist)\""
        let encodedQ = queryStr.amrQueryValueEncoded
        guard let searchUrl = URL(string: "https://musicbrainz.org/ws/2/release?query=\(encodedQ)&limit=5&fmt=json") else {
            return result
        }

        var searchReq = URLRequest(url: searchUrl)
        searchReq.timeoutInterval = 4.5
        searchReq.setValue("AppleMusicRemoteMac/2.6 (https://github.com/ksholokhov/amr)", forHTTPHeaderField: "User-Agent")
        searchReq.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (sData, sResp) = try? await session.data(for: searchReq),
              let sHttp = sResp as? HTTPURLResponse, sHttp.statusCode == 200,
              let sJson = try? JSONSerialization.jsonObject(with: sData) as? [String: Any],
              let releases = sJson["releases"] as? [[String: Any]], !releases.isEmpty else {
            return result
        }

        // Pick best matching release (prefer exact track count or closest official release)
        let bestRelease = releases.min { a, b in
            let aCount = a["track-count"] as? Int ?? 0
            let bCount = b["track-count"] as? Int ?? 0
            let aDiff = expectedTrackCount > 0 ? abs(aCount - expectedTrackCount) : 0
            let bDiff = expectedTrackCount > 0 ? abs(bCount - expectedTrackCount) : 0
            if aDiff != bDiff { return aDiff < bDiff }
            let aScore = a["score"] as? Int ?? 0
            let bScore = b["score"] as? Int ?? 0
            return aScore > bScore
        } ?? releases[0]

        guard let releaseId = bestRelease["id"] as? String, !releaseId.isEmpty,
              let relUrl = URL(string: "https://musicbrainz.org/ws/2/release/\(releaseId)?inc=recordings+artist-credits+recording-level-rels+artist-rels+work-rels+work-level-rels+place-rels+labels&fmt=json") else {
            return result
        }

        var relReq = URLRequest(url: relUrl)
        relReq.timeoutInterval = 5.0
        relReq.setValue("AppleMusicRemoteMac/2.6 (https://github.com/ksholokhov/amr)", forHTTPHeaderField: "User-Agent")
        relReq.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (rData, rResp) = try? await session.data(for: relReq),
              let rHttp = rResp as? HTTPURLResponse, rHttp.statusCode == 200,
              let rJson = try? JSONSerialization.jsonObject(with: rData) as? [String: Any],
              let mediaArr = rJson["media"] as? [[String: Any]] else {
            return result
        }

        if let relRels = rJson["relations"] as? [[String: Any]] {
            for r in relRels {
                if let place = r["place"] as? [String: Any],
                   let pName = place["name"] as? String, !pName.isEmpty,
                   !result.releaseStudios.contains(pName) {
                    result.releaseStudios.append(pName)
                }
            }
        }

        var globalTrackIndex = 0
        for medium in mediaArr {
            guard let tracksArr = medium["tracks"] as? [[String: Any]] else { continue }
            for trk in tracksArr {
                globalTrackIndex += 1
                let tNum = (trk["position"] as? Int) ?? globalTrackIndex
                let tTitle = (trk["title"] as? String) ?? ""
                guard let rec = trk["recording"] as? [String: Any] else { continue }

                var tc = MBTrackCreditsResult()
                var instByArtist: [String: [String]] = [:]
                var instArtistOrder: [String] = []
                var vocalByArtist: [String: [String]] = [:]
                var vocalArtistOrder: [String] = []
                var prodByArtist: [String: [String]] = [:]
                var prodArtistOrder: [String] = []

                func addGrouped(_ dict: inout [String: [String]], _ order: inout [String], artist: String, role: String) {
                    let cleanA = artist.replacingOccurrences(of: "‐", with: "-")
                    if dict[cleanA] == nil {
                        dict[cleanA] = []
                        order.append(cleanA)
                    }
                    if !role.isEmpty && !(dict[cleanA]?.contains(role) ?? false) {
                        dict[cleanA]?.append(role)
                    }
                }

                let relations = (rec["relations"] as? [[String: Any]]) ?? []
                for rel in relations {
                    let rType = (rel["type"] as? String ?? "").lowercased()
                    let rawAttrs = (rel["attributes"] as? [String]) ?? []
                    let translatedAttrs = rawAttrs.compactMap { a -> String? in
                        let clean = a.trimmingCharacters(in: .whitespacesAndNewlines)
                        if clean.isEmpty || clean == "co" || clean == "additional" { return nil }
                        return Self.translateMusicBrainzAttribute(clean)
                    }

                    if let artObj = rel["artist"] as? [String: Any],
                       let aName = artObj["name"] as? String, !aName.isEmpty {
                        if rType == "instrument" {
                            let roles = translatedAttrs.isEmpty ? ["инструменты"] : translatedAttrs
                            for r in roles {
                                addGrouped(&instByArtist, &instArtistOrder, artist: aName, role: r)
                            }
                        } else if rType == "vocal" {
                            let roles = translatedAttrs.isEmpty ? [""] : translatedAttrs
                            for r in roles {
                                addGrouped(&vocalByArtist, &vocalArtistOrder, artist: aName, role: r)
                            }
                        } else if rType == "producer" || rType == "co-producer" {
                            addGrouped(&prodByArtist, &prodArtistOrder, artist: aName, role: "продюсер")
                        } else if rType == "conductor" {
                            addGrouped(&prodByArtist, &prodArtistOrder, artist: aName, role: "дирижёр")
                        } else if rType == "arranger" || rType == "instrument arranger" || rType == "orchestrator" {
                            addGrouped(&prodByArtist, &prodArtistOrder, artist: aName, role: "аранжировка")
                        } else if rType == "vocal arranger" {
                            addGrouped(&prodByArtist, &prodArtistOrder, artist: aName, role: "аранжировка вокала")
                        } else if rType == "recording" || rType == "engineer" || rType == "audio" {
                            addGrouped(&prodByArtist, &prodArtistOrder, artist: aName, role: "инженер записи")
                        } else if rType == "mix" {
                            addGrouped(&prodByArtist, &prodArtistOrder, artist: aName, role: "сведение")
                        } else if rType == "mastering" {
                            addGrouped(&prodByArtist, &prodArtistOrder, artist: aName, role: "мастеринг")
                        } else if rType == "programming" {
                            addGrouped(&prodByArtist, &prodArtistOrder, artist: aName, role: "программирование")
                        }
                    } else if let placeObj = rel["place"] as? [String: Any],
                              let pName = placeObj["name"] as? String, !pName.isEmpty {
                        if !tc.studios.contains(pName) {
                            tc.studios.append(pName)
                        }
                    } else if let workObj = rel["work"] as? [String: Any],
                              let workRels = workObj["relations"] as? [[String: Any]] {
                        for wr in workRels {
                            let wType = (wr["type"] as? String ?? "").lowercased()
                            let wDir = (wr["direction"] as? String ?? "").lowercased()
                            if let wArt = wr["artist"] as? [String: Any],
                               let wName = (wArt["name"] as? String)?.replacingOccurrences(of: "‐", with: "-"),
                               !wName.isEmpty {
                                if ["writer", "composer", "lyricist", "librettist"].contains(wType) {
                                    if !tc.writers.contains(wName) {
                                        tc.writers.append(wName)
                                    }
                                } else if wType == "vocal arranger" {
                                    addGrouped(&prodByArtist, &prodArtistOrder, artist: wName, role: "аранжировка вокала")
                                } else if wType == "arranger" || wType == "instrument arranger" {
                                    addGrouped(&prodByArtist, &prodArtistOrder, artist: wName, role: "аранжировка")
                                }
                            } else if let quotedWork = wr["work"] as? [String: Any],
                                      let qTitle = quotedWork["title"] as? String, !qTitle.isEmpty,
                                      wDir == "forward",
                                      ["musical quotation", "based on", "medley"].contains(wType) {
                                if !tc.samples.contains(qTitle) {
                                    tc.samples.append("«\(qTitle)»")
                                }
                            }
                        }
                    }
                }

                tc.instruments = instArtistOrder.map { a in
                    let roles = instByArtist[a] ?? []
                    return roles.isEmpty ? a : "\(a) (\(roles.joined(separator: ", ")))"
                }
                tc.vocals = vocalArtistOrder.map { a in
                    let roles = (vocalByArtist[a] ?? []).filter { !$0.isEmpty }
                    return roles.isEmpty ? a : "\(a) (\(roles.joined(separator: ", ")))"
                }
                tc.producers = prodArtistOrder.map { a in
                    let roles = (prodByArtist[a] ?? []).filter { !$0.isEmpty }
                    return roles.isEmpty ? a : "\(a) (\(roles.joined(separator: ", ")))"
                }

                result.byTrackNumber[tNum] = tc
                let normT = Self.normalizeTrackKey(tTitle)
                if !normT.isEmpty {
                    result.byNormalizedTitle[normT] = tc
                }
            }
        }

        return result
    }

    private static func translateMusicBrainzAttribute(_ attr: String) -> String {
        let map: [String: String] = [
            "guitar": "гитара",
            "electric guitar": "электрогитара",
            "acoustic guitar": "акустическая гитара",
            "bass guitar": "бас-гитара",
            "bass": "бас",
            "double bass": "контрабас",
            "synth bass": "бас-синтезатор",
            "drums (drum set)": "ударные",
            "drums": "ударные",
            "drum machine": "драм-машина",
            "percussion": "перкуссия",
            "keyboard": "клавишные",
            "synthesizer": "синтезатор",
            "modular synthesizer": "модульный синтезатор",
            "piano": "фортепиано",
            "electric piano": "электропианино",
            "rhodes piano": "электропианино Fender Rhodes",
            "wurlitzer electric piano": "электропианино Wurlitzer",
            "organ": "орган",
            "hammond organ": "орган Хаммонда",
            "pedal steel guitar": "педал-стил-гитара",
            "lap steel guitar": "лэп-стил-гитара",
            "ondes martenot": "волны Мартено",
            "other instruments": "дополнительные инструменты",
            "strings": "струнные",
            "violin": "скрипка",
            "viola": "альт",
            "cello": "виолончель",
            "trumpet": "труба",
            "trombone": "тромбон",
            "saxophone": "саксофон",
            "tenor saxophone": "тенор-саксофон",
            "alto saxophone": "альт-саксофон",
            "flute": "флейта",
            "harp": "арфа",
            "horncello": "валторна",
            "french horn": "валторна",
            "timpani": "литавры",
            "vocoder": "вокодер",
            "talkbox": "ток-бокс",
            "sampler": "сэмплер",
            "turntables": "вертушки",
            "lead vocals": "ведущий вокал",
            "background vocals": "бэк-вокал",
            "spoken vocals": "монолог / речитатив",
            "choir vocals": "хор",
            "vocals": "вокал",
            "solo": "соло"
        ]
        return map[attr.lowercased()] ?? attr
    }

    // MARK: - Wikipedia Album & Track-by-Track Commentary Fetcher

    private struct WikiBookletNotes: Sendable {
        var albumHistoryParagraphs: [String] = []
        var trackCommentary: [String: String] = [:]
    }

    private func fetchWikipediaAlbumAndTrackNotes(
        album: String,
        artist: String,
        tracks: [CatalogTrackCredit],
        englishEditorialFallback: String
    ) async -> WikiBookletNotes {
        var result = WikiBookletNotes()
        guard !album.isEmpty else { return result }

        let preferRu = MusicKitManager.shared.getPreferredLanguageTag().lowercased().hasPrefix("ru")
        let primaryLang = preferRu ? "ru" : "en"
        let secondaryLang = preferRu ? "en" : "ru"

        var extract = await fetchBestWikipediaAlbumExtract(album: album, artist: artist, lang: primaryLang)
        if extract.isEmpty {
            extract = await fetchBestWikipediaAlbumExtract(album: album, artist: artist, lang: secondaryLang)
        }

        // Also include English Apple Music editorial text as supplemental source for track mentions if needed
        let combinedForTrackParsing = extract.isEmpty ? englishEditorialFallback : (extract + "\n\n" + englishEditorialFallback)
        guard !combinedForTrackParsing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return result
        }

        if !extract.isEmpty {
            result.albumHistoryParagraphs = Self.extractAlbumHistoryParagraphs(from: extract)
        }

        result.trackCommentary = Self.extractTrackByTrackCommentary(
            from: combinedForTrackParsing,
            tracks: tracks
        )

        return result
    }

    private func fetchBestWikipediaAlbumExtract(album: String, artist: String, lang: String) async -> String {
        let cleanAlbum = album
            .replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\[.*?\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAlbum.isEmpty else { return "" }

        let query = "\"\(cleanAlbum)\" \"\(artist)\""
        let encodedQ = query.amrQueryValueEncoded
        guard let searchUrl = URL(string: "https://\(lang).wikipedia.org/w/api.php?action=query&list=search&srsearch=\(encodedQ)&srlimit=6&format=json") else {
            return ""
        }

        var sReq = URLRequest(url: searchUrl)
        sReq.timeoutInterval = 4.0
        sReq.setValue("AppleMusicRemoteMac/2.6", forHTTPHeaderField: "User-Agent")

        guard let (sData, sResp) = try? await session.data(for: sReq),
              let sHttp = sResp as? HTTPURLResponse, sHttp.statusCode == 200,
              let sJson = try? JSONSerialization.jsonObject(with: sData) as? [String: Any],
              let qObj = sJson["query"] as? [String: Any],
              let searchItems = qObj["search"] as? [[String: Any]], !searchItems.isEmpty else {
            return ""
        }

        let normAlb = cleanAlbum.lowercased()
        let normArt = artist.lowercased()
        let excludedSuffixes = ["(песня", "song)", "(сингл", "single)", "(тур", "tour)", "(фильм", "film)", "дискография", "discography"]

        let validItems = searchItems.filter { item in
            let title = (item["title"] as? String ?? "").lowercased()
            if title == normArt { return false }
            for ex in excludedSuffixes where title.contains(ex) { return false }
            return true
        }

        let chosenTitle: String? =
            validItems.first(where: {
                let t = ($0["title"] as? String ?? "").lowercased()
                return t.hasPrefix(normAlb + " (") && (t.contains("альбом") || t.contains("album"))
            })?["title"] as? String
            ?? validItems.first(where: {
                let t = ($0["title"] as? String ?? "").lowercased()
                return t == normAlb
            })?["title"] as? String
            ?? validItems.first(where: {
                let t = ($0["title"] as? String ?? "").lowercased()
                return t.hasPrefix(normAlb)
            })?["title"] as? String

        guard let pageTitle = chosenTitle else {
            return ""
        }
        let encodedTitle = pageTitle.amrQueryValueEncoded
        guard let extUrl = URL(string: "https://\(lang).wikipedia.org/w/api.php?action=query&prop=extracts&explaintext=1&titles=\(encodedTitle)&format=json") else {
            return ""
        }

        var eReq = URLRequest(url: extUrl)
        eReq.timeoutInterval = 4.5
        eReq.setValue("AppleMusicRemoteMac/2.6", forHTTPHeaderField: "User-Agent")

        guard let (eData, eResp) = try? await session.data(for: eReq),
              let eHttp = eResp as? HTTPURLResponse, eHttp.statusCode == 200,
              let eJson = try? JSONSerialization.jsonObject(with: eData) as? [String: Any],
              let eqObj = eJson["query"] as? [String: Any],
              let pagesObj = eqObj["pages"] as? [String: Any],
              let firstPage = pagesObj.values.first as? [String: Any],
              let extract = firstPage["extract"] as? String else {
            return ""
        }

        return extract
    }

    private static func extractAlbumHistoryParagraphs(from wikiExtract: String) -> [String] {
        let stopMarkers = [
            "== Список композиций ==",
            "== Участники записи ==",
            "== Чарты",
            "== Примечания ==",
            "== Track listing ==",
            "== Personnel ==",
            "== Charts =="
        ]
        var mainText = wikiExtract
        for marker in stopMarkers {
            if let r = mainText.range(of: marker) {
                mainText = String(mainText[..<r.lowerBound])
            }
        }

        var paragraphs: [String] = []
        var currentSection = "Введение"
        let allowedSections = ["введение", "предыстория", "история", "запись", "музыка", "концепция", "художественное оформление", "background", "recording", "composition", "music", "concept", "packaging"]

        for rawLine in mainText.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("==") && line.hasSuffix("==") {
                let secName = line.trimmingCharacters(in: CharacterSet(charactersIn: "= ")).lowercased()
                currentSection = secName
                continue
            }
            guard line.count >= 65 else { continue }
            if allowedSections.contains(where: { currentSection.contains($0) }) {
                paragraphs.append(line)
                if paragraphs.count >= 8 {
                    break
                }
            }
        }
        return paragraphs
    }

    public static func normalizeTrackKey(_ title: String) -> String {
        return title
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: #"\s*\(feat\..*?\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\[feat\..*?\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeForMatching(_ text: String) -> String {
        return text
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "«", with: "\"")
            .replacingOccurrences(of: "»", with: "\"")
            .replacingOccurrences(of: "„", with: "\"")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
    }

    public static func extractTrackByTrackCommentary(
        from text: String,
        tracks: [CatalogTrackCredit]
    ) -> [String: String] {
        guard !tracks.isEmpty else { return [:] }

        let stopMarkers = [
            "== Список композиций ==",
            "== Участники записи ==",
            "== Чарты",
            "== Примечания ==",
            "== Track listing ==",
            "== Personnel ==",
            "== Charts =="
        ]
        var mainText = text
        for marker in stopMarkers {
            if let r = mainText.range(of: marker) {
                mainText = String(mainText[..<r.lowerBound])
            }
        }

        let trackKeys: [(key: String, normTitle: String)] = tracks.compactMap { t in
            let k = normalizeTrackKey(t.title)
            guard k.count >= 2 else { return nil }
            return (k, normalizeForMatching(k))
        }

        var buckets: [String: [String]] = [:]
        for tk in trackKeys {
            buckets[tk.key] = []
        }

        let sentenceRegex = try? NSRegularExpression(pattern: #"(?<=[.!?])\s+(?=[А-ЯA-Z«"„“])"#, options: [])

        for rawPara in mainText.components(separatedBy: "\n") {
            let para = rawPara.trimmingCharacters(in: .whitespacesAndNewlines)
            if para.count < 35 || para.hasPrefix("=") { continue }

            let sentences: [String]
            if let regex = sentenceRegex {
                let nsPara = para as NSString
                let matches = regex.matches(in: para, options: [], range: NSRange(location: 0, length: nsPara.length))
                var parts: [String] = []
                var lastIdx = 0
                for m in matches {
                    let chunk = nsPara.substring(with: NSRange(location: lastIdx, length: m.range.location - lastIdx)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !chunk.isEmpty { parts.append(chunk) }
                    lastIdx = m.range.location + m.range.length
                }
                let tail = nsPara.substring(from: lastIdx).trimmingCharacters(in: .whitespacesAndNewlines)
                if !tail.isEmpty { parts.append(tail) }
                sentences = parts
            } else {
                sentences = [para]
            }

            var activeKeys: [String] = []
            for sent in sentences {
                let normSent = normalizeForMatching(sent)
                var mentionedKeys: [String] = []

                for tk in trackKeys {
                    if normSent.contains("\"\(tk.normTitle)\"") {
                        mentionedKeys.append(tk.key)
                    } else if tk.normTitle.count >= 5 {
                        let pattern = "(?<![a-zа-я0-9])\(NSRegularExpression.escapedPattern(for: tk.normTitle))(?![a-zа-я0-9])"
                        if normSent.range(of: pattern, options: .regularExpression) != nil {
                            mentionedKeys.append(tk.key)
                        }
                    }
                }

                if !mentionedKeys.isEmpty {
                    activeKeys = mentionedKeys
                    for k in activeKeys {
                        if !(buckets[k]?.contains(sent) ?? false) {
                            buckets[k, default: []].append(sent)
                        }
                    }
                } else if activeKeys.count == 1 {
                    let k = activeKeys[0]
                    if (buckets[k]?.count ?? 0) < 6 && !(buckets[k]?.contains(sent) ?? false) {
                        buckets[k, default: []].append(sent)
                    }
                }
            }
        }

        var result: [String: String] = [:]
        for (k, sents) in buckets where !sents.isEmpty {
            let joined = sents.prefix(6).joined(separator: " ")
            result[k] = joined
        }
        return result
    }

    // MARK: - Comprehensive Multi-Page PDF Booklet Renderer (CoreGraphics + PDFKit)

    private enum BookletPageKind {
        case cover
        case editorial(paragraphs: [String], showReleaseSpecsCard: Bool, partIndex: Int, totalParts: Int)
        case trackGuide(tracks: [CatalogTrackCredit], partIndex: Int, totalParts: Int)

        var title: String {
            switch self {
            case .cover:
                return "Обложка альбома"
            case .editorial(_, _, let partIdx, let totalParts):
                return totalParts > 1
                    ? "О релизе и история записи (ч. \(partIdx)/\(totalParts))"
                    : "О релизе и история записи"
            case .trackGuide(let trks, _, _):
                if let first = trks.first, let last = trks.last {
                    return first.number == last.number
                        ? String(format: "Композиция %02d: %@", first.number, first.title)
                        : String(format: "Описание композиций: треки %02d–%02d", first.number, last.number)
                }
                return "Описание композиций"
            }
        }
    }

    public func renderOfficialAppleEditorialBookletPdf(meta: AlbumCatalogMetadata, audioQualityLabel: String? = nil) -> Data {
        return renderComprehensiveEditorialBookletPdf(meta: meta, audioQualityLabel: audioQualityLabel).data
    }

    public func renderComprehensiveEditorialBookletPdf(
        meta: AlbumCatalogMetadata,
        audioQualityLabel: String? = nil
    ) -> (data: Data, pageTitles: [String]) {
        let pageW: CGFloat = 720
        let pageH: CGFloat = 960
        let margin: CGFloat = 52
        let contentW = pageW - margin * 2
        var mediaBox = CGRect(x: 0, y: 0, width: pageW, height: pageH)

        // 1. Build Editorial & Album History Paragraphs
        var allEditorialParas: [String] = []
        let primaryEditorial = !meta.editorialStandard.isEmpty ? meta.editorialStandard : meta.editorialShort
        for p in primaryEditorial.components(separatedBy: "\n") {
            let trimmed = p.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !allEditorialParas.contains(trimmed) {
                allEditorialParas.append(trimmed)
            }
        }
        for hp in meta.albumHistoryParagraphs {
            let trimmed = hp.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !allEditorialParas.contains(trimmed) {
                allEditorialParas.append(trimmed)
            }
        }

        // Paginate editorial paragraphs so nothing is ever cut off
        var editorialPagesParas: [[String]] = []
        var currentParas: [String] = []
        var usedH: CGFloat = 0
        let maxEditorialBodyH: CGFloat = 680
        let maxEditorialWithSpecsH: CGFloat = 465

        for para in allEditorialParas {
            let pH = measureTextHeight(
                text: para,
                font: NSFont.systemFont(ofSize: 13.5, weight: .regular),
                lineSpacing: 5.0,
                width: contentW
            ) + 14
            if !currentParas.isEmpty && (usedH + pH > maxEditorialBodyH) {
                editorialPagesParas.append(currentParas)
                currentParas = [para]
                usedH = pH
            } else {
                currentParas.append(para)
                usedH += pH
            }
        }
        if !currentParas.isEmpty {
            editorialPagesParas.append(currentParas)
        }
        if editorialPagesParas.isEmpty {
            editorialPagesParas.append([])
        }

        // Check if the last editorial page has enough room for the Release Specs Card (height ~ 200pt)
        let lastPageParas = editorialPagesParas.last ?? []
        let lastPageTextH = lastPageParas.reduce(CGFloat(0)) { acc, p in
            acc + measureTextHeight(
                text: p,
                font: NSFont.systemFont(ofSize: 13.5, weight: .regular),
                lineSpacing: 5.0,
                width: contentW
            ) + 14
        }
        if lastPageTextH > maxEditorialWithSpecsH && !lastPageParas.isEmpty {
            // Split last page or add a dedicated page for the remaining paragraphs + specs card
            if lastPageParas.count >= 2 {
                let half = lastPageParas.count / 2
                editorialPagesParas[editorialPagesParas.count - 1] = Array(lastPageParas.prefix(half))
                editorialPagesParas.append(Array(lastPageParas.dropFirst(half)))
            } else {
                editorialPagesParas.append([])
            }
        }

        // 2. Paginate Detailed Track-by-Track Cards dynamically
        let maxTrackAreaH: CGFloat = 740 // y from 154 to 894
        var trackPages: [[CatalogTrackCredit]] = []
        var currentTrackGroup: [CatalogTrackCredit] = []
        var currentTrackGroupH: CGFloat = 0

        for track in meta.tracks {
            let cardH = measureDetailedTrackCardHeight(track: track, albumArtist: meta.artistName, contentWidth: contentW)
            if !currentTrackGroup.isEmpty && (currentTrackGroupH + cardH > maxTrackAreaH) {
                trackPages.append(currentTrackGroup)
                currentTrackGroup = [track]
                currentTrackGroupH = cardH
            } else {
                currentTrackGroup.append(track)
                currentTrackGroupH += cardH
            }
        }
        if !currentTrackGroup.isEmpty {
            trackPages.append(currentTrackGroup)
        }

        // 3. Assemble complete list of pages
        var pageLayouts: [BookletPageKind] = [.cover]
        let totalEdParts = editorialPagesParas.count
        for (idx, paras) in editorialPagesParas.enumerated() {
            let isLastEd = (idx == totalEdParts - 1)
            pageLayouts.append(.editorial(paragraphs: paras, showReleaseSpecsCard: isLastEd, partIndex: idx + 1, totalParts: totalEdParts))
        }
        let totalTrkParts = trackPages.count
        for (idx, trkGroup) in trackPages.enumerated() {
            pageLayouts.append(.trackGuide(tracks: trkGroup, partIndex: idx + 1, totalParts: totalTrkParts))
        }

        let totalPages = pageLayouts.count
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let pdfCtx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return (Data(), [])
        }

        for (idx, layout) in pageLayouts.enumerated() {
            let pageNum = idx + 1
            beginFlippedPdfPage(context: pdfCtx, width: pageW, height: pageH)
            switch layout {
            case .cover:
                drawCoverPage(
                    context: pdfCtx,
                    meta: meta,
                    audioQualityLabel: audioQualityLabel ?? "",
                    width: pageW,
                    height: pageH,
                    pageNumber: pageNum,
                    totalPages: totalPages
                )
            case .editorial(let paragraphs, let showSpecs, let partIdx, let totalParts):
                drawEditorialPage(
                    context: pdfCtx,
                    meta: meta,
                    paragraphs: paragraphs,
                    showSpecsCard: showSpecs,
                    partIndex: partIdx,
                    totalParts: totalParts,
                    width: pageW,
                    height: pageH,
                    pageNumber: pageNum,
                    totalPages: totalPages
                )
            case .trackGuide(let tracks, let partIdx, let totalParts):
                drawDetailedTrackGuidePage(
                    context: pdfCtx,
                    meta: meta,
                    tracks: tracks,
                    partIndex: partIdx,
                    totalParts: totalParts,
                    width: pageW,
                    height: pageH,
                    pageNumber: pageNum,
                    totalPages: totalPages
                )
            }
            endFlippedPdfPage(context: pdfCtx)
        }

        pdfCtx.closePDF()
        return (pdfData as Data, pageLayouts.map { $0.title })
    }

    private func beginFlippedPdfPage(context: CGContext, width: CGFloat, height: CGFloat) {
        var box = CGRect(x: 0, y: 0, width: width, height: height)
        context.beginPage(mediaBox: &box)
        context.saveGState()
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1.0, y: -1.0)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    }

    private func endFlippedPdfPage(context: CGContext) {
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
        context.endPage()
    }

    private func drawBookletBackground(context: CGContext, width: CGFloat, height: CGFloat) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            CGColor(red: 0.055, green: 0.055, blue: 0.078, alpha: 1.0),
            CGColor(red: 0.095, green: 0.085, blue: 0.130, alpha: 1.0),
            CGColor(red: 0.045, green: 0.045, blue: 0.062, alpha: 1.0)
        ] as CFArray
        let locations: [CGFloat] = [0.0, 0.52, 1.0]
        if let grad = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
            context.drawLinearGradient(
                grad,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: width, y: height),
                options: []
            )
        } else {
            context.setFillColor(CGColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1.0))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }

        let borderRect = CGRect(x: 24, y: 24, width: width - 48, height: height - 48)
        context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.08))
        context.setLineWidth(1.0)
        context.stroke(borderRect)
    }

    private func drawCoverPage(
        context: CGContext,
        meta: AlbumCatalogMetadata,
        audioQualityLabel: String,
        width: CGFloat,
        height: CGFloat,
        pageNumber: Int,
        totalPages: Int
    ) {
        drawBookletBackground(context: context, width: width, height: height)

        let margin: CGFloat = 52
        let contentW = width - margin * 2

        let headerStyle = NSMutableParagraphStyle()
        headerStyle.alignment = .left
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor(calibratedRed: 0.98, green: 0.22, blue: 0.36, alpha: 1.0),
            .kern: 2.2,
            .paragraphStyle: headerStyle
        ]
        ("APPLE MUSIC • DIGITAL BOOKLET" as NSString).draw(
            in: CGRect(x: margin, y: 48, width: contentW * 0.65, height: 20),
            withAttributes: headerAttrs
        )

        let badgeRightStyle = NSMutableParagraphStyle()
        badgeRightStyle.alignment = .right
        let badgeText = meta.isMasteredForItunes ? "APPLE DIGITAL MASTER" : "APPLE MUSIC EDITION"
        let badgeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.78, alpha: 1.0),
            .kern: 1.4,
            .paragraphStyle: badgeRightStyle
        ]
        (badgeText as NSString).draw(
            in: CGRect(x: margin + contentW * 0.5, y: 48, width: contentW * 0.5, height: 20),
            withAttributes: badgeAttrs
        )

        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
        context.setLineWidth(1.0)
        context.move(to: CGPoint(x: margin, y: 74))
        context.addLine(to: CGPoint(x: width - margin, y: 74))
        context.strokePath()

        let artSize: CGFloat = 500
        let artX = (width - artSize) / 2.0
        let artY: CGFloat = 104
        let artRect = CGRect(x: artX, y: artY, width: artSize, height: artSize)

        if let imgData = meta.artworkData,
           let nsImg = NSImage(data: imgData),
           let cgImg = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.saveGState()
            context.translateBy(x: artRect.minX, y: artRect.maxY)
            context.scaleBy(x: 1.0, y: -1.0)
            context.draw(cgImg, in: CGRect(x: 0, y: 0, width: artRect.width, height: artRect.height))
            context.restoreGState()
        } else {
            context.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 1.0))
            context.fill(artRect)
        }

        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
        context.setLineWidth(1.2)
        context.stroke(artRect)

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 30, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: headerStyle
        ]
        (meta.albumName as NSString).draw(
            in: CGRect(x: margin, y: 632, width: contentW, height: 76),
            withAttributes: titleAttrs
        )

        let artistAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 0.98, green: 0.28, blue: 0.42, alpha: 1.0),
            .paragraphStyle: headerStyle
        ]
        (meta.artistName as NSString).draw(
            in: CGRect(x: margin, y: 712, width: contentW, height: 32),
            withAttributes: artistAttrs
        )

        var metaParts: [String] = []
        if !meta.genre.isEmpty { metaParts.append(meta.genre) }
        if !meta.releaseDate.isEmpty { metaParts.append(String(meta.releaseDate.prefix(4))) }
        if !meta.tracks.isEmpty { metaParts.append("\(meta.tracks.count) композиций") }
        let metaLine = metaParts.joined(separator: "  •  ")

        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.68, alpha: 1.0),
            .paragraphStyle: headerStyle
        ]
        (metaLine as NSString).draw(
            in: CGRect(x: margin, y: 750, width: contentW, height: 24),
            withAttributes: subAttrs
        )

        let summaryQuote = !meta.editorialShort.isEmpty
            ? meta.editorialShort
            : (meta.albumHistoryParagraphs.first ?? "")
        if !summaryQuote.isEmpty {
            let quoteStyle = NSMutableParagraphStyle()
            quoteStyle.lineSpacing = 3.5
            let quoteAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12.8, weight: .regular),
                .foregroundColor: NSColor(calibratedWhite: 0.82, alpha: 1.0),
                .paragraphStyle: quoteStyle
            ]
            (summaryQuote as NSString).draw(
                in: CGRect(x: margin, y: 784, width: contentW, height: 92),
                withAttributes: quoteAttrs
            )
        }

        drawPageFooter(
            context: context,
            leftText: meta.recordLabel.isEmpty ? meta.copyright : meta.recordLabel,
            pageNumber: pageNumber,
            totalPages: totalPages,
            width: width,
            height: height,
            margin: margin
        )
    }

    private func drawEditorialPage(
        context: CGContext,
        meta: AlbumCatalogMetadata,
        paragraphs: [String],
        showSpecsCard: Bool,
        partIndex: Int,
        totalParts: Int,
        width: CGFloat,
        height: CGFloat,
        pageNumber: Int,
        totalPages: Int
    ) {
        drawBookletBackground(context: context, width: width, height: height)

        let margin: CGFloat = 52
        let contentW = width - margin * 2
        let partSuffix = totalParts > 1 ? " (СТР. \(partIndex) ИЗ \(totalParts))" : ""

        drawSectionHeader(
            context: context,
            kicker: "ИСТОРИЯ СОЗДАНИЯ, ЗАПИСЬ И КОНЦЕПЦИЯ АЛЬБОМА\(partSuffix)",
            title: meta.albumName,
            subtitle: meta.artistName,
            margin: margin,
            width: width
        )

        let bodyParagraph = NSMutableParagraphStyle()
        bodyParagraph.lineSpacing = 5.0
        bodyParagraph.alignment = .left

        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13.5, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.90, alpha: 1.0),
            .paragraphStyle: bodyParagraph
        ]

        var curY: CGFloat = 156
        for para in paragraphs {
            let pH = measureTextHeight(
                text: para,
                font: NSFont.systemFont(ofSize: 13.5, weight: .regular),
                lineSpacing: 5.0,
                width: contentW
            )
            (para as NSString).draw(
                in: CGRect(x: margin, y: curY, width: contentW, height: pH + 6),
                withAttributes: bodyAttrs
            )
            curY += pH + 14
        }

        if showSpecsCard {
            let cardH: CGFloat = 196
            let cardY: CGFloat = max(curY + 12, 668)
            let cardRect = CGRect(x: margin, y: cardY, width: contentW, height: cardH)
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.045))
            context.fill(cardRect)
            context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
            context.setLineWidth(1.0)
            context.stroke(cardRect)

            let totalSec = Int(meta.tracks.reduce(0.0) { $0 + $1.durationSeconds })
            let runtimeStr = String(format: "%d мин %02d сек (%d треков)", totalSec / 60, totalSec % 60, meta.tracks.count)

            let specs: [(label: String, value: String)] = [
                ("ИСПОЛНИТЕЛЬ", meta.artistName),
                ("ДАТА РЕЛИЗА", meta.releaseDate.isEmpty ? "—" : meta.releaseDate),
                ("ЖАНР", meta.genre.isEmpty ? "—" : meta.genre),
                ("ЛЕЙБЛ / ИЗДАТЕЛЬ", meta.recordLabel.isEmpty ? "—" : meta.recordLabel),
                ("ХРОНОМЕТРАЖ", runtimeStr),
                ("МАСТЕРИНГ APPLE", meta.isMasteredForItunes ? "Apple Digital Master • Lossless" : (meta.audioTraits.joined(separator: ", ").isEmpty ? "Apple Music Lossless" : meta.audioTraits.joined(separator: ", ")))
            ]

            let colW = (contentW - 48) / 2.0
            for (idx, spec) in specs.enumerated() {
                let col = idx % 2
                let row = idx / 2
                let x = margin + 20 + CGFloat(col) * (colW + 8)
                let y = cardY + 18 + CGFloat(row) * 56

                let lblAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 9.5, weight: .bold),
                    .foregroundColor: NSColor(calibratedWhite: 0.52, alpha: 1.0),
                    .kern: 1.2
                ]
                (spec.label as NSString).draw(in: CGRect(x: x, y: y, width: colW, height: 14), withAttributes: lblAttrs)

                let valAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                    .foregroundColor: NSColor.white
                ]
                (spec.value as NSString).draw(in: CGRect(x: x, y: y + 16, width: colW, height: 22), withAttributes: valAttrs)
            }
        }

        drawPageFooter(
            context: context,
            leftText: meta.copyright.isEmpty ? meta.recordLabel : meta.copyright,
            pageNumber: pageNumber,
            totalPages: totalPages,
            width: width,
            height: height,
            margin: margin
        )
    }

    // MARK: - Detailed Track-by-Track Liner Notes & Credits Page Renderer

    private func buildTrackCreditRows(track: CatalogTrackCredit) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if !track.composer.isEmpty {
            rows.append(("АВТОРЫ И КОМПОЗИТОРЫ", track.composer))
        }
        if !track.producers.isEmpty {
            rows.append(("ПРОДЮСИРОВАНИЕ И АРАНЖИРОВКА", track.producers.joined(separator: " • ")))
        }
        if !track.vocals.isEmpty {
            rows.append(("ВОКАЛ", track.vocals.joined(separator: " • ")))
        }
        if !track.instruments.isEmpty {
            rows.append(("ИНСТРУМЕНТЫ И МУЗЫКАНТЫ", track.instruments.joined(separator: " • ")))
        }
        if !track.samples.isEmpty {
            rows.append(("СЭМПЛЫ И ЦИТАТЫ", track.samples.joined(separator: " • ")))
        }
        if !track.studios.isEmpty {
            rows.append(("СТУДИИ ЗАПИСИ", track.studios.joined(separator: " • ")))
        }
        return rows
    }

    private func measureDetailedTrackCardHeight(
        track: CatalogTrackCredit,
        albumArtist: String,
        contentWidth: CGFloat
    ) -> CGFloat {
        let innerW = contentWidth - 32
        var h: CGFloat = 14 // top padding
        h += 24 // Title + number + duration row
        h += 18 // Subtitle metadata row (Artist / ISRC / Audio Badge)

        if !track.commentary.isEmpty {
            let commH = measureTextHeight(
                text: track.commentary,
                font: NSFont.systemFont(ofSize: 12.4, weight: .regular),
                lineSpacing: 3.8,
                width: innerW
            )
            h += 8 + commH + 6
        }

        let creditRows = buildTrackCreditRows(track: track)
        if !creditRows.isEmpty {
            h += 8 // separator spacing
            for row in creditRows {
                let combined = "\(row.label): \(row.value)"
                let rowH = measureTextHeight(
                    text: combined,
                    font: NSFont.systemFont(ofSize: 11.2, weight: .regular),
                    lineSpacing: 2.5,
                    width: innerW
                )
                h += rowH + 5
            }
        }

        h += 14 // bottom card padding + gap between cards
        return min(h, 690)
    }

    private func drawDetailedTrackGuidePage(
        context: CGContext,
        meta: AlbumCatalogMetadata,
        tracks: [CatalogTrackCredit],
        partIndex: Int,
        totalParts: Int,
        width: CGFloat,
        height: CGFloat,
        pageNumber: Int,
        totalPages: Int
    ) {
        drawBookletBackground(context: context, width: width, height: height)

        let margin: CGFloat = 52
        let contentW = width - margin * 2
        let innerW = contentW - 32
        let partLabel = totalParts > 1 ? " (ЧАСТЬ \(partIndex) ИЗ \(totalParts))" : ""

        drawSectionHeader(
            context: context,
            kicker: "ПОЛНОЕ ОПИСАНИЕ ПО КОМПОЗИЦИЯМ • TRACK-BY-TRACK & CREDITS\(partLabel)",
            title: meta.albumName,
            subtitle: meta.artistName,
            margin: margin,
            width: width
        )

        let rightStyle = NSMutableParagraphStyle()
        rightStyle.alignment = .right

        var curY: CGFloat = 156

        for track in tracks {
            let cardTotalH = measureDetailedTrackCardHeight(track: track, albumArtist: meta.artistName, contentWidth: contentW)
            let boxH = cardTotalH - 10
            let boxRect = CGRect(x: margin, y: curY, width: contentW, height: boxH)

            // Subtle dark glass card per track
            context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.038))
            context.fill(boxRect)
            context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.11))
            context.setLineWidth(0.9)
            context.stroke(boxRect)

            // Left accent bar
            context.setFillColor(CGColor(red: 0.98, green: 0.24, blue: 0.38, alpha: 0.85))
            context.fill(CGRect(x: margin, y: curY, width: 3.5, height: boxH))

            context.saveGState()
            context.clip(to: boxRect)

            let innerX = margin + 16
            var y = curY + 12

            // 1. Track Number + Title + Duration
            let numStr = String(format: "%02d", track.number)
            let numAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 14.5, weight: .bold),
                .foregroundColor: NSColor(calibratedRed: 0.98, green: 0.26, blue: 0.40, alpha: 1.0)
            ]
            (numStr as NSString).draw(in: CGRect(x: innerX, y: y + 1, width: 30, height: 20), withAttributes: numAttrs)

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            (track.title as NSString).draw(in: CGRect(x: innerX + 32, y: y - 1, width: innerW - 104, height: 22), withAttributes: titleAttrs)

            let mins = Int(track.durationSeconds) / 60
            let secs = Int(track.durationSeconds) % 60
            let durStr = track.durationSeconds > 0 ? String(format: "%d:%02d", mins, secs) : "—"
            let durAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13.5, weight: .semibold),
                .foregroundColor: NSColor(calibratedWhite: 0.85, alpha: 1.0),
                .paragraphStyle: rightStyle
            ]
            (durStr as NSString).draw(in: CGRect(x: innerX + innerW - 68, y: y + 1, width: 68, height: 20), withAttributes: durAttrs)
            y += 23

            // 2. Subtitle row: Artist • Audio Master Badge • ISRC
            var metaBadges: [String] = []
            if !track.artist.isEmpty {
                metaBadges.append(track.artist)
            }
            if !track.audioBadge.isEmpty {
                metaBadges.append(track.audioBadge)
            }
            if !track.isrc.isEmpty {
                metaBadges.append("ISRC: \(track.isrc)")
            }
            let metaLine = metaBadges.joined(separator: "   •   ")
            let metaLineAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
                .foregroundColor: NSColor(calibratedRed: 0.96, green: 0.52, blue: 0.60, alpha: 0.95)
            ]
            (metaLine as NSString).draw(in: CGRect(x: innerX + 32, y: y, width: innerW - 32, height: 16), withAttributes: metaLineAttrs)
            y += 18

            // 3. Detailed Track Commentary / Story
            if !track.commentary.isEmpty {
                y += 6
                let commStyle = NSMutableParagraphStyle()
                commStyle.lineSpacing = 3.8
                commStyle.alignment = .left
                let commAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12.4, weight: .regular),
                    .foregroundColor: NSColor(calibratedWhite: 0.91, alpha: 1.0),
                    .paragraphStyle: commStyle
                ]
                let commH = measureTextHeight(
                    text: track.commentary,
                    font: NSFont.systemFont(ofSize: 12.4, weight: .regular),
                    lineSpacing: 3.8,
                    width: innerW
                )
                (track.commentary as NSString).draw(
                    in: CGRect(x: innerX, y: y, width: innerW, height: commH + 4),
                    withAttributes: commAttrs
                )
                y += commH + 8
            }

            // 4. Structured Credits (Writers, Producers, Vocals, Instruments, Samples, Studios)
            let creditRows = buildTrackCreditRows(track: track)
            if !creditRows.isEmpty && y < curY + boxH - 18 {
                context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.08))
                context.setLineWidth(0.7)
                context.move(to: CGPoint(x: innerX, y: y + 2))
                context.addLine(to: CGPoint(x: innerX + innerW, y: y + 2))
                context.strokePath()
                y += 8

                let rowStyle = NSMutableParagraphStyle()
                rowStyle.lineSpacing = 2.5

                for row in creditRows {
                    if y >= curY + boxH - 12 {
                        break
                    }
                    let attrStr = NSMutableAttributedString(
                        string: "\(row.label): ",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 10.6, weight: .bold),
                            .foregroundColor: NSColor(calibratedWhite: 0.62, alpha: 1.0),
                            .paragraphStyle: rowStyle
                        ]
                    )
                    attrStr.append(NSAttributedString(
                        string: row.value,
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 11.2, weight: .regular),
                            .foregroundColor: NSColor(calibratedWhite: 0.86, alpha: 1.0),
                            .paragraphStyle: rowStyle
                        ]
                    ))
                    let combinedText = "\(row.label): \(row.value)"
                    let rH = measureTextHeight(
                        text: combinedText,
                        font: NSFont.systemFont(ofSize: 11.2, weight: .regular),
                        lineSpacing: 2.5,
                        width: innerW
                    )
                    attrStr.draw(in: CGRect(x: innerX, y: y, width: innerW, height: rH + 4))
                    y += rH + 5
                }
            }

            context.restoreGState()

            curY += cardTotalH
        }

        drawPageFooter(
            context: context,
            leftText: meta.copyright.isEmpty ? meta.recordLabel : meta.copyright,
            pageNumber: pageNumber,
            totalPages: totalPages,
            width: width,
            height: height,
            margin: margin
        )
    }

    private func measureTextHeight(
        text: String,
        font: NSFont,
        lineSpacing: CGFloat,
        width: CGFloat
    ) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: style
        ]
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: 4000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        return ceil(rect.height)
    }

    private func drawSectionHeader(
        context: CGContext,
        kicker: String,
        title: String,
        subtitle: String,
        margin: CGFloat,
        width: CGFloat
    ) {
        let contentW = width - margin * 2
        let kickerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .bold),
            .foregroundColor: NSColor(calibratedRed: 0.98, green: 0.24, blue: 0.38, alpha: 1.0),
            .kern: 1.6
        ]
        (kicker as NSString).draw(in: CGRect(x: margin, y: 48, width: contentW, height: 16), withAttributes: kickerAttrs)

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        (title as NSString).draw(in: CGRect(x: margin, y: 68, width: contentW, height: 30), withAttributes: titleAttrs)

        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.70, alpha: 1.0)
        ]
        (subtitle as NSString).draw(in: CGRect(x: margin, y: 100, width: contentW, height: 22), withAttributes: subAttrs)

        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.14))
        context.setLineWidth(1.0)
        context.move(to: CGPoint(x: margin, y: 136))
        context.addLine(to: CGPoint(x: width - margin, y: 136))
        context.strokePath()
    }

    private func drawPageFooter(
        context: CGContext,
        leftText: String,
        pageNumber: Int,
        totalPages: Int,
        width: CGFloat,
        height: CGFloat,
        margin: CGFloat
    ) {
        let footerY = height - 54
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
        context.setLineWidth(0.8)
        context.move(to: CGPoint(x: margin, y: footerY - 10))
        context.addLine(to: CGPoint(x: width - margin, y: footerY - 10))
        context.strokePath()

        let leftAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.55, alpha: 1.0)
        ]
        (leftText as NSString).draw(
            in: CGRect(x: margin, y: footerY, width: width - margin * 2 - 95, height: 18),
            withAttributes: leftAttrs
        )

        let rightStyle = NSMutableParagraphStyle()
        rightStyle.alignment = .right
        let pageAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.75, alpha: 1.0),
            .paragraphStyle: rightStyle
        ]
        ("СТР. \(pageNumber) / \(totalPages)" as NSString).draw(
            in: CGRect(x: width - margin - 95, y: footerY, width: 95, height: 18),
            withAttributes: pageAttrs
        )
    }

    // MARK: - Helpers

    private func makeUnavailableInfo(bookletId: String, album: String, artist: String) -> BookletInfo {
        return BookletInfo(
            available: false,
            bookletId: bookletId,
            title: "",
            album: album,
            artist: artist,
            source: "none",
            sourceTitle: "",
            isOriginalPdf: false,
            hasEditorialNotes: false,
            pageCount: 0,
            fileSizeBytes: 0,
            recordLabel: nil,
            copyright: nil,
            releaseDate: nil,
            pdfUrl: "",
            pages: []
        )
    }

    private func buildEditorialContentPayload(from meta: AlbumCatalogMetadata) -> BookletEditorialContent {
        var allParas: [String] = []
        let primaryEditorial = !meta.editorialStandard.isEmpty ? meta.editorialStandard : meta.editorialShort
        for p in primaryEditorial.components(separatedBy: "\n") {
            let trimmed = p.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !allParas.contains(trimmed) {
                allParas.append(trimmed)
            }
        }
        for hp in meta.albumHistoryParagraphs {
            let trimmed = hp.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !allParas.contains(trimmed) {
                allParas.append(trimmed)
            }
        }
        let summaryQuote = !meta.editorialShort.isEmpty
            ? meta.editorialShort
            : (meta.albumHistoryParagraphs.first ?? "")

        let mappedTracks = meta.tracks.map { t in
            BookletTrackCreditInfo(
                number: t.number,
                discNumber: t.discNumber,
                title: t.title,
                artist: t.artist,
                composer: t.composer,
                durationSeconds: t.durationSeconds,
                isrc: t.isrc,
                audioBadge: t.audioBadge,
                commentary: t.commentary,
                producers: t.producers,
                vocals: t.vocals,
                instruments: t.instruments,
                samples: t.samples,
                studios: t.studios
            )
        }

        return BookletEditorialContent(
            genre: meta.genre,
            releaseDate: meta.releaseDate,
            recordLabel: meta.recordLabel,
            copyright: meta.copyright,
            isMasteredForItunes: meta.isMasteredForItunes,
            audioTraits: meta.audioTraits,
            artworkUrl: meta.artworkUrl,
            summaryQuote: summaryQuote,
            editorialParagraphs: allParas,
            recordingStudios: meta.recordingStudios,
            tracks: mappedTracks
        )
    }

    private func buildBookletInfo(
        bookletId: String,
        doc: PDFDocument,
        pdfData: Data,
        album: String,
        artist: String,
        source: String,
        sourceTitle: String,
        isOriginalPdf: Bool,
        hasEditorialNotes: Bool,
        recordLabel: String? = nil,
        copyright: String? = nil,
        releaseDate: String? = nil,
        customPageTitles: [String]? = nil,
        editorial: BookletEditorialContent? = nil,
        fileURL: URL?
    ) -> BookletInfo {
        let count = doc.pageCount
        var pages: [BookletPageInfo] = []
        pages.reserveCapacity(count)

        for idx in 0..<count {
            let bounds = doc.page(at: idx)?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 720, height: 960)
            let rotation = (((doc.page(at: idx)?.rotation ?? 0) % 360) + 360) % 360
            let w = Double((rotation == 90 || rotation == 270) ? bounds.height : bounds.width)
            let h = Double((rotation == 90 || rotation == 270) ? bounds.width : bounds.height)
            let ratio = h > 0 ? (w / h) : 0.75
            let pageTitle: String
            if let custom = customPageTitles, idx < custom.count {
                pageTitle = custom[idx]
            } else if !isOriginalPdf {
                if idx == 0 { pageTitle = "Обложка альбома" }
                else if idx == 1 { pageTitle = "О релизе и история записи" }
                else { pageTitle = "Описание композиций (стр. \(idx - 1))" }
            } else {
                pageTitle = "Страница \(idx + 1)"
            }
            pages.append(BookletPageInfo(
                pageIndex: idx,
                pageNumber: idx + 1,
                width: w,
                height: h,
                aspectRatio: ratio,
                title: pageTitle,
                imageUrl: "/api/booklet/page?id=\(bookletId)&page=\(idx)&scale=1600",
                thumbUrl: "/api/booklet/page?id=\(bookletId)&page=\(idx)&scale=360"
            ))
        }

        return BookletInfo(
            available: count > 0,
            bookletId: bookletId,
            title: "Digital Booklet — \(album)",
            album: album,
            artist: artist,
            source: source,
            sourceTitle: sourceTitle,
            isOriginalPdf: isOriginalPdf,
            hasEditorialNotes: hasEditorialNotes,
            pageCount: count,
            fileSizeBytes: pdfData.count,
            recordLabel: recordLabel,
            copyright: copyright,
            releaseDate: releaseDate,
            pdfUrl: "/api/booklet/pdf?id=\(bookletId)",
            pages: pages,
            editorial: editorial
        )
    }

    private func purgeRenderedPagesUnlocked(forBookletId id: String) {
        let prefix = "\(id)|"
        let keysToRemove = renderedPageCache.keys.filter { $0.hasPrefix(prefix) }
        for k in keysToRemove {
            renderedPageCache.removeValue(forKey: k)
        }
        renderedPageOrder.removeAll { $0.hasPrefix(prefix) }
    }

    private func storeInCache(bookletId: String, info: BookletInfo, pdfData: Data?, fileURL: URL?) {
        lock.withLock {
            while bookletCache[bookletId] == nil && bookletCache.count >= 12 {
                if let oldestKey = bookletCache.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
                    bookletCache.removeValue(forKey: oldestKey)
                    purgeRenderedPagesUnlocked(forBookletId: oldestKey)
                } else {
                    break
                }
            }
            purgeRenderedPagesUnlocked(forBookletId: bookletId)
            bookletCache[bookletId] = CachedBookletEntry(
                info: info,
                pdfData: pdfData,
                fileURL: fileURL,
                timestamp: Date()
            )
        }
    }

    private func sanitizeFilename(_ input: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = input.components(separatedBy: invalid).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Album" : String(cleaned.prefix(60))
    }

    public static func stripHtmlTags(_ html: String) -> String {
        var text = html
            .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&nbsp;", " "),
            ("&mdash;", "—"),
            ("&ndash;", "–")
        ]
        for (ent, rep) in entities {
            text = text.replacingOccurrences(of: ent, with: rep)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
