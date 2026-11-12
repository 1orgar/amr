//
//  DigitalBookletServiceTests.swift
//  AppleMusicRemoteMacTests
//
//  Unit tests for Apple Digital Booklet Viewer (official Apple Music / iTunes PDF
//  discovery, official Apple editorialNotes booklet rendering, unavailable state
//  when no Apple booklet exists, and PDFKit page rasterization).
//

import CoreGraphics
import Foundation
import PDFKit
import XCTest
@testable import AppleMusicRemoteMac

final class DigitalBookletServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        DigitalBookletService.shared.additionalSearchDirectories = []
        DigitalBookletService.shared.clearCache()
    }

    override func tearDown() {
        DigitalBookletService.shared.additionalSearchDirectories = []
        DigitalBookletService.shared.clearCache()
        super.tearDown()
    }

    func testDeterministicBookletIdGeneration() {
        let id1 = DigitalBookletService.makeBookletId(album: "Random Access Memories", artist: "Daft Punk")
        let id2 = DigitalBookletService.makeBookletId(album: "  random access memories ", artist: "DAFT PUNK")
        let id3 = DigitalBookletService.makeBookletId(album: "Discovery", artist: "Daft Punk")

        XCTAssertEqual(id1, id2)
        XCTAssertNotEqual(id1, id3)
        XCTAssertEqual(id1.count, 20)
    }

    func testReturnsUnavailableWhenNoAppleBookletExists() async {
        let info = await DigitalBookletService.shared.resolveBooklet(
            album: "NonExistent Album Without Booklet \(UUID().uuidString.prefix(8))",
            artist: "Unknown Artist",
            forceRefresh: true
        )

        XCTAssertFalse(info.available, "Albums without an official Apple Digital Booklet or editorialNotes must report available == false")
        XCTAssertEqual(info.pageCount, 0)
        XCTAssertTrue(info.pages.isEmpty)
        XCTAssertEqual(info.source, "none")
    }

    func testDiscoversOfficialAppleBookletFromMediaDirectoryAndRasterizesPages() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AMRAppleBookletTest_\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let artist = "Miles Davis"
        let album = "Kind of Blue (Deluxe Edition)"
        let albumDir = tempRoot
            .appendingPathComponent(artist, isDirectory: true)
            .appendingPathComponent(album, isDirectory: true)
        try FileManager.default.createDirectory(at: albumDir, withIntermediateDirectories: true)

        let pdfUrl = albumDir.appendingPathComponent("Digital Booklet - Kind of Blue.pdf")
        let samplePdfData = Self.makeTwoPageSamplePdfData()
        try samplePdfData.write(to: pdfUrl)

        DigitalBookletService.shared.additionalSearchDirectories = [tempRoot]

        let info = await DigitalBookletService.shared.resolveBooklet(
            album: album,
            artist: artist,
            forceRefresh: true
        )

        XCTAssertTrue(info.available, "Official Apple Digital Booklet PDF in album folder must be discovered")
        XCTAssertTrue(info.isOriginalPdf)
        XCTAssertEqual(info.source, "apple_music_library_pdf")
        XCTAssertEqual(info.pageCount, 2)
        XCTAssertEqual(info.pages.count, 2)

        let rawPdf = DigitalBookletService.shared.getPdfData(bookletId: info.bookletId)
        XCTAssertNotNil(rawPdf)
        XCTAssertEqual(rawPdf?.data.count, samplePdfData.count)

        for pageIdx in 0..<info.pageCount {
            let jpegData = DigitalBookletService.shared.renderPageImage(
                bookletId: info.bookletId,
                pageIndex: pageIdx,
                maxDimension: 800
            )
            XCTAssertNotNil(jpegData, "Rendered JPEG for page \(pageIdx) must not be nil")
            XCTAssertGreaterThan(jpegData?.count ?? 0, 1000)
        }
    }

    func testRendersOfficialAppleEditorialBookletWhenEditorialNotesExist() {
        let meta = DigitalBookletService.AlbumCatalogMetadata(
            albumId: "617154241",
            albumName: "Random Access Memories",
            artistName: "Daft Punk",
            releaseDate: "2013-05-17",
            genre: "Танцевальная • Электроника",
            recordLabel: "Columbia",
            copyright: "℗ 2013 Daft Life Limited",
            editorialStandard: "Официальное описание Apple Music для альбома Random Access Memories.",
            editorialShort: "Disco, rediscovered.",
            isMasteredForItunes: true,
            audioTraits: ["lossless", "hi-res-lossless"],
            tracks: [
                DigitalBookletService.CatalogTrackCredit(
                    number: 1,
                    title: "Give Life Back to Music",
                    artist: "Daft Punk",
                    composer: "Thomas Bangalter, Guy-Manuel de Homem-Christo, Paul Jackson Jr. & Nile Rodgers",
                    durationSeconds: 274,
                    isrc: "USQX91300101",
                    audioBadge: "Apple Digital Master • Lossless",
                    commentary: "Открывающая альбом композиция базируется на гитарных партиях Найла Роджерса и Пола Джексона-младшего.",
                    producers: ["Thomas Bangalter (продюсер)", "Guy-Manuel de Homem-Christo (продюсер)"],
                    vocals: ["Daft Punk"],
                    instruments: ["Nile Rodgers (гитара)", "Paul Jackson, Jr. (гитара)", "Nathan East (бас-гитара)"]
                )
            ]
        )

        let pdfData = DigitalBookletService.shared.renderOfficialAppleEditorialBookletPdf(
            meta: meta,
            audioQualityLabel: "Lossless (ALAC 24-bit/44.1kHz)"
        )
        XCTAssertGreaterThan(pdfData.count, 1000)
        guard let doc = PDFDocument(data: pdfData) else {
            XCTFail("Expected valid PDFDocument")
            return
        }
        XCTAssertEqual(doc.pageCount, 3)
    }

    func testExtractsTrackByTrackCommentaryCleanly() {
        let sampleWiki = """
        Открывающая альбом «Give Life Back to Music» базируется на гитарных партиях Найла Роджерса и ударных Джона Робинсона. Песня отражает стремление дуэта создать элегантную пластинку с живыми инструментами. В следующем треке, «The Game of Love», дуэт использовал аналоговый вокодер для передачи эмоций.
        """
        let tracks = [
            DigitalBookletService.CatalogTrackCredit(number: 1, title: "Give Life Back to Music", artist: "Daft Punk", composer: "", durationSeconds: 274),
            DigitalBookletService.CatalogTrackCredit(number: 2, title: "The Game of Love", artist: "Daft Punk", composer: "", durationSeconds: 322)
        ]
        let map = DigitalBookletService.extractTrackByTrackCommentary(from: sampleWiki, tracks: tracks)
        XCTAssertTrue(map["give life back to music"]?.contains("Найла Роджерса") == true)
        XCTAssertTrue(map["give life back to music"]?.contains("элегантную пластинку") == true)
        XCTAssertFalse(map["give life back to music"]?.contains("The Game of Love") == true)
        XCTAssertTrue(map["the game of love"]?.contains("аналоговый вокодер") == true)
    }

    func testStripHtmlTagsCleansEditorialNotes() {
        let html = "<p>Recorded in <b>Paris</b> &amp; Los Angeles.<br/>Mastered by <i>Bob Ludwig</i> &mdash; 24-bit/88.2kHz.</p>"
        let cleaned = DigitalBookletService.stripHtmlTags(html)
        XCTAssertEqual(cleaned, "Recorded in Paris & Los Angeles.\nMastered by Bob Ludwig — 24-bit/88.2kHz.")
    }

    private static func makeTwoPageSamplePdfData() -> Data {
        var mediaBox = CGRect(x: 0, y: 0, width: 720, height: 960)
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        for page in 0..<2 {
            ctx.beginPage(mediaBox: &mediaBox)
            ctx.setFillColor(CGColor(
                red: page == 0 ? 0.12 : 0.18,
                green: 0.15,
                blue: 0.28,
                alpha: 1.0
            ))
            ctx.fill(mediaBox)
            ctx.endPage()
        }
        ctx.closePDF()
        return pdfData as Data
    }
}
