//
//  DigitalBookletService+PdfLayout.swift
//  AppleMusicRemoteMac
//
//  Serialized CoreGraphics / AppKit PDF booklet pagination, cover page, and editorial pages.
//

import AppKit
import CoreGraphics
import Foundation
import PDFKit

extension DigitalBookletService {

    // MARK: - Comprehensive Multi-Page PDF Booklet Renderer (CoreGraphics + PDFKit)

    internal enum BookletPageKind {
        case cover
        case editorial(paragraphs: [String], showReleaseSpecsCard: Bool, partIndex: Int, totalParts: Int)
        case trackGuide(tracks: [CatalogTrackCredit], partIndex: Int, totalParts: Int)

        var title: String {
            let isEn = AMRLocalization.isEnglish
            switch self {
            case .cover:
                return isEn ? "Album Cover" : "Обложка альбома"
            case .editorial(_, _, let partIdx, let totalParts):
                if isEn {
                    return totalParts > 1
                        ? "Release Notes & Recording History (pt. \(partIdx)/\(totalParts))"
                        : "Release Notes & Recording History"
                }
                return totalParts > 1
                    ? "О релизе и история записи (ч. \(partIdx)/\(totalParts))"
                    : "О релизе и история записи"
            case .trackGuide(let trks, _, _):
                if let first = trks.first, let last = trks.last {
                    if isEn {
                        return first.number == last.number
                            ? String(format: "Track %02d: %@", first.number, first.title)
                            : String(format: "Track-by-Track Guide: Tracks %02d–%02d", first.number, last.number)
                    }
                    return first.number == last.number
                        ? String(format: "Композиция %02d: %@", first.number, first.title)
                        : String(format: "Описание композиций: треки %02d–%02d", first.number, last.number)
                }
                return isEn ? "Track-by-Track Guide" : "Описание композиций"
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
        return pdfSynthesisQueue.sync {
            autoreleasepool {
                renderComprehensiveEditorialBookletPdfSerialized(meta: meta, audioQualityLabel: audioQualityLabel)
            }
        }
    }

    private func renderComprehensiveEditorialBookletPdfSerialized(
        meta: AlbumCatalogMetadata,
        audioQualityLabel: String?
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
            if lastPageParas.count >= 2 {
                let half = lastPageParas.count / 2
                editorialPagesParas[editorialPagesParas.count - 1] = Array(lastPageParas.prefix(half))
                editorialPagesParas.append(Array(lastPageParas.dropFirst(half)))
            } else {
                editorialPagesParas.append([])
            }
        }

        // 2. Paginate Detailed Track-by-Track Cards dynamically
        let maxTrackAreaH: CGFloat = 740
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
            autoreleasepool {
                withFlippedPdfPage(context: pdfCtx, width: pageW, height: pageH) {
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
                }
            }
        }

        pdfCtx.closePDF()
        return (pdfData as Data, pageLayouts.map { $0.title })
    }

    private func withFlippedPdfPage(
        context: CGContext,
        width: CGFloat,
        height: CGFloat,
        body: () -> Void
    ) {
        var box = CGRect(x: 0, y: 0, width: width, height: height)
        context.beginPage(mediaBox: &box)
        context.saveGState()
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1.0, y: -1.0)
        let previousGraphicsContext = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer {
            NSGraphicsContext.current = previousGraphicsContext
            context.restoreGState()
            context.endPage()
        }
        body()
    }

    internal func drawBookletBackground(context: CGContext, width: CGFloat, height: CGFloat) {
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

    internal func drawCoverPage(
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
        if !meta.tracks.isEmpty {
            metaParts.append(
                AMRLocalization.isEnglish
                    ? "\(meta.tracks.count) \(meta.tracks.count == 1 ? "track" : "tracks")"
                    : "\(meta.tracks.count) композиций"
            )
        }
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

    internal func drawEditorialPage(
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

        let isEn = AMRLocalization.isEnglish
        let margin: CGFloat = 52
        let contentW = width - margin * 2
        let partSuffix = totalParts > 1
            ? (isEn ? " (PAGE \(partIndex) OF \(totalParts))" : " (СТР. \(partIndex) ИЗ \(totalParts))")
            : ""

        drawSectionHeader(
            context: context,
            kicker: isEn
                ? "ALBUM STORY, RECORDING SESSIONS & EDITORIAL NOTES\(partSuffix)"
                : "ИСТОРИЯ СОЗДАНИЯ, ЗАПИСЬ И КОНЦЕПЦИЯ АЛЬБОМА\(partSuffix)",
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
            let runtimeStr = isEn
                ? String(format: "%d min %02d sec (%d %@)", totalSec / 60, totalSec % 60, meta.tracks.count, meta.tracks.count == 1 ? "track" : "tracks")
                : String(format: "%d мин %02d сек (%d треков)", totalSec / 60, totalSec % 60, meta.tracks.count)

            let masteringVal = meta.isMasteredForItunes
                ? "Apple Digital Master • Lossless"
                : (meta.audioTraits.joined(separator: ", ").isEmpty ? "Apple Music Lossless" : meta.audioTraits.joined(separator: ", "))
            let specs: [(label: String, value: String)] = isEn
                ? [
                    ("ARTIST", meta.artistName),
                    ("RELEASE DATE", meta.releaseDate.isEmpty ? "—" : meta.releaseDate),
                    ("GENRE", meta.genre.isEmpty ? "—" : meta.genre),
                    ("RECORD LABEL", meta.recordLabel.isEmpty ? "—" : meta.recordLabel),
                    ("RUNTIME", runtimeStr),
                    ("APPLE MASTERING", masteringVal)
                ]
                : [
                    ("ИСПОЛНИТЕЛЬ", meta.artistName),
                    ("ДАТА РЕЛИЗА", meta.releaseDate.isEmpty ? "—" : meta.releaseDate),
                    ("ЖАНР", meta.genre.isEmpty ? "—" : meta.genre),
                    ("ЛЕЙБЛ / ИЗДАТЕЛЬ", meta.recordLabel.isEmpty ? "—" : meta.recordLabel),
                    ("ХРОНОМЕТРАЖ", runtimeStr),
                    ("МАСТЕРИНГ APPLE", masteringVal)
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
}
