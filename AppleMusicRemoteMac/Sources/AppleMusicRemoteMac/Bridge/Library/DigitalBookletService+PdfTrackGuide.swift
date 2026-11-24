//
//  DigitalBookletService+PdfTrackGuide.swift
//  AppleMusicRemoteMac
//
//  Track-by-track liner notes card rendering, text height measurement, and PDF headers/footers.
//

import AppKit
import CoreGraphics
import Foundation

extension DigitalBookletService {

    // MARK: - Detailed Track-by-Track Liner Notes & Credits Page Renderer

    internal func buildTrackCreditRows(track: CatalogTrackCredit) -> [(label: String, value: String)] {
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

    internal func measureDetailedTrackCardHeight(
        track: CatalogTrackCredit,
        albumArtist: String,
        contentWidth: CGFloat
    ) -> CGFloat {
        let innerW = contentWidth - 32
        var h: CGFloat = 14
        h += 24
        h += 18

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
            h += 8
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

        h += 14
        return min(h, 690)
    }

    internal func drawDetailedTrackGuidePage(
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

    internal func measureTextHeight(
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

    internal func drawSectionHeader(
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

    internal func drawPageFooter(
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
}
