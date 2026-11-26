//
//  DigitalBookletService+LocalDiscovery.swift
//  AppleMusicRemoteMac
//
//  Local Apple Digital Booklet PDF discovery in Music.app / ~/Music media folders,
//  BookletInfo model construction, cache management, and HTML entity stripping.
//

import CoreGraphics
import Foundation
import PDFKit

extension DigitalBookletService {

    // MARK: - Apple Digital Booklet Discovery (Music.app & ~/Music Media Library)

    internal func sanitizeFolderComponent(_ raw: String) -> String? {
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

    internal func isSafeSubpath(_ candidate: URL, under root: URL) -> Bool {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let candidatePath = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : (rootPath + "/")
        return candidatePath == rootPath || candidatePath.hasPrefix(prefix)
    }

    internal func isRegularNonSymlinkFile(_ url: URL) -> Bool {
        guard let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              vals.isRegularFile == true,
              vals.isSymbolicLink != true else {
            return false
        }
        return true
    }

    internal func findAppleDigitalBookletPdf(album: String, artist: String) -> URL? {
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
            if let pathStr = AppleScriptExecutor.shared.execute(script, maxWait: 2.0, reportTimeout: false).output?.trimmingCharacters(in: .whitespacesAndNewlines),
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

    internal func firstPdfInDirectory(_ dir: URL, requireAlbumOrBookletMatch albumMatch: String? = nil) -> URL? {
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

    internal func firstMatchingPdfInDirectory(_ dir: URL, album: String) -> URL? {
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

    // MARK: - BookletInfo Builders & Cache Helpers

    internal func makeUnavailableInfo(bookletId: String, album: String, artist: String) -> BookletInfo {
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

    internal func buildEditorialContentPayload(from meta: AlbumCatalogMetadata) -> BookletEditorialContent {
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

    internal func buildBookletInfo(
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
            let isEn = AMRLocalization.isEnglish
            if let custom = customPageTitles, idx < custom.count {
                pageTitle = custom[idx]
            } else if !isOriginalPdf {
                if idx == 0 { pageTitle = isEn ? "Album Cover" : "Обложка альбома" }
                else if idx == 1 { pageTitle = isEn ? "Release Notes & Recording History" : "О релизе и история записи" }
                else { pageTitle = isEn ? "Track-by-Track Guide (p. \(idx - 1))" : "Описание композиций (стр. \(idx - 1))" }
            } else {
                pageTitle = isEn ? "Page \(idx + 1)" : "Страница \(idx + 1)"
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

    internal func purgeRenderedPagesUnlocked(forBookletId id: String) {
        let prefix = "\(id)|"
        let keysToRemove = renderedPageCache.keys.filter { $0.hasPrefix(prefix) }
        for k in keysToRemove {
            renderedPageCache.removeValue(forKey: k)
        }
        renderedPageOrder.removeAll { $0.hasPrefix(prefix) }
    }

    internal func storeInCache(bookletId: String, info: BookletInfo, pdfData: Data?, fileURL: URL?) {
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

    internal func sanitizeFilename(_ input: String) -> String {
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
