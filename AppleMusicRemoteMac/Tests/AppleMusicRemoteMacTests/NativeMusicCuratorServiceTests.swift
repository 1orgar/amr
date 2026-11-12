//
//  NativeMusicCuratorServiceTests.swift
//  AppleMusicRemoteMacTests
//
//  Unit tests for NativeMusicCuratorService (FoundationModels + NaturalLanguage 512-D NLEmbedding & NLTagger).
//

import AppKit
import XCTest
@testable import AppleMusicRemoteMac

final class NativeMusicCuratorServiceTests: XCTestCase {

    func testRussianNoirJazzSemanticPlan() {
        let plan = NativeMusicCuratorService.shared.buildNaturalLanguagePlan(
            for: "ночной атмосферный джаз с саксофоном и контрабасом",
            preferEnglish: false
        )
        XCTAssertTrue(plan.title.lowercased().contains("джаз"))
        XCTAssertFalse(plan.seedQueries.isEmpty)
        XCTAssertTrue(plan.seedQueries.contains(where: { $0.contains("Miles Davis") || $0.contains("Chet Baker") }))
        XCTAssertGreaterThan(plan.confidenceScore, 0.7)
    }

    func testEnglishProgRockSemanticPlan() {
        let plan = NativeMusicCuratorService.shared.buildNaturalLanguagePlan(
            for: "1970s analog progressive rock with wide holographic soundstage",
            preferEnglish: true
        )
        XCTAssertTrue(plan.title.lowercased().contains("prog") || plan.title.lowercased().contains("rock"))
        XCTAssertTrue(plan.seedQueries.contains(where: { $0.contains("Pink Floyd") || $0.contains("Dire Straits") }))
        XCTAssertFalse(plan.tags.isEmpty)
    }

    func testEntityExtractionInCustomPrompt() {
        let plan = NativeMusicCuratorService.shared.buildNaturalLanguagePlan(
            for: "ночной инструментальный рок с широкой сценой как у Pink Floyd",
            preferEnglish: false
        )
        XCTAssertTrue(plan.seedQueries.contains(where: { $0.contains("Pink Floyd") }))
        XCTAssertTrue(plan.tags.contains(where: { $0.contains("Pink Floyd") }))
    }

    func testArtistStylePromptWithTypoAndLowercaseToolKraftwerkDaftPunk() {
        let service = NativeMusicCuratorService.shared

        // 1. "в стиле гуппы tool" (typo "гуппы" + lowercase "tool")
        let toolPlan = service.buildNaturalLanguagePlan(for: "в стиле гуппы tool", preferEnglish: false)
        XCTAssertTrue(toolPlan.title.contains("Tool"), "Expected Tool in title, got: \(toolPlan.title)")
        XCTAssertFalse(toolPlan.title.lowercased().contains("даб-техно"), "Must not misclassify Tool as dub-techno: \(toolPlan.title)")
        XCTAssertTrue(toolPlan.seedQueries.contains(where: { $0.contains("Tool") }))
        XCTAssertTrue(toolPlan.seedQueries.contains(where: { $0.contains("A Perfect Circle") || $0.contains("Porcupine Tree") || $0.contains("Karnivool") }))

        // 2. "в стиле гуппы kraftwerk"
        let kraftwerkPlan = service.buildNaturalLanguagePlan(for: "в стиле гуппы kraftwerk", preferEnglish: false)
        XCTAssertTrue(kraftwerkPlan.title.contains("Kraftwerk"), "Expected Kraftwerk in title, got: \(kraftwerkPlan.title)")
        XCTAssertFalse(kraftwerkPlan.title.lowercased().contains("блюз-рок"), "Must not mix blues-rock into Kraftwerk: \(kraftwerkPlan.title)")
        XCTAssertTrue(kraftwerkPlan.seedQueries.contains(where: { $0.contains("Kraftwerk") }))

        // 3. "в стиле гуппы daft punk"
        let daftPunkPlan = service.buildNaturalLanguagePlan(for: "в стиле гуппы daft punk", preferEnglish: false)
        XCTAssertTrue(daftPunkPlan.title.contains("Daft Punk"), "Expected Daft Punk in title, got: \(daftPunkPlan.title)")
        XCTAssertTrue(daftPunkPlan.seedQueries.contains(where: { $0.contains("Daft Punk") }))
        XCTAssertTrue(daftPunkPlan.seedQueries.contains(where: { $0.contains("Justice") || $0.contains("Parcels") || $0.contains("Air") }))

        // 4. "в стиле группы кино" (band Кино, not film score)
        let kinoPlan = service.buildNaturalLanguagePlan(for: "в стиле группы кино", preferEnglish: false)
        XCTAssertTrue(kinoPlan.title.contains("Кино"), "Expected Кино in title, got: \(kinoPlan.title)")
        XCTAssertTrue(kinoPlan.seedQueries.contains(where: { $0.contains("Кино") }))

        // 5. Unknown artist with style prefix ("в стиле гуппы khruangbin") must not hallucinate dub-techno
        let customArtistPlan = service.buildNaturalLanguagePlan(for: "в стиле гуппы khruangbin", preferEnglish: false)
        XCTAssertTrue(customArtistPlan.title.contains("Khruangbin"), "Expected Khruangbin in title, got: \(customArtistPlan.title)")
        XCTAssertFalse(customArtistPlan.title.lowercased().contains("даб-техно"), "Must not misclassify custom artist as dub-techno: \(customArtistPlan.title)")
        XCTAssertEqual(customArtistPlan.seedQueries.first, "Khruangbin")
    }

    func testCuratorSettingsToggleAndRegenerateSuggestions() {
        let service = NativeMusicCuratorService.shared
        let originalEnabled = service.isEnabled
        defer { service.isEnabled = originalEnabled }

        service.isEnabled = true
        XCTAssertTrue(service.isEnabled)
        service.isEnabled = false
        XCTAssertFalse(service.isEnabled)
        service.isEnabled = true

        let firstBatch = service.getRandomSuggestions(count: 6)
        XCTAssertEqual(firstBatch.count, 6)
        let excluded = firstBatch.compactMap { $0["prompt_ru"] }
        let secondBatch = service.getRandomSuggestions(count: 6, excludePrompts: excluded)
        XCTAssertEqual(secondBatch.count, 6)
        let secondPrompts = Set(secondBatch.compactMap { $0["prompt_ru"] })
        XCTAssertTrue(secondPrompts.isDisjoint(with: Set(excluded)))
    }

    func testPinnedPromptsPersistenceAndToggle() {
        let service = NativeMusicCuratorService.shared
        let initialPinned = service.getPinnedPrompts()
        defer {
            service.clearPinnedPrompts()
            for item in initialPinned.reversed() {
                if let p = item["prompt"], let l = item["label"] {
                    _ = service.togglePinPrompt(prompt: p, label: l)
                }
            }
        }

        service.clearPinnedPrompts()
        XCTAssertTrue(service.getPinnedPrompts().isEmpty)

        let pinnedNow = service.togglePinPrompt(
            prompt: "ночной нуар-джаз с контрабасом",
            label: "🎷 Ночной нуар-джаз"
        )
        XCTAssertTrue(pinnedNow)
        XCTAssertTrue(service.isPromptPinned("ночной нуар-джаз с контрабасом"))
        XCTAssertEqual(service.getPinnedPrompts().count, 1)

        let unpinnedNow = service.togglePinPrompt(
            prompt: "НОЧНОЙ НУАР-ДЖАЗ С КОНТРАБАСОМ",
            label: "🎷 Ночной нуар-джаз"
        )
        XCTAssertFalse(unpinnedNow)
        XCTAssertFalse(service.isPromptPinned("ночной нуар-джаз с контрабасом"))
        XCTAssertTrue(service.getPinnedPrompts().isEmpty)
    }

    func testBuildTrackVibePlan() {
        let service = NativeMusicCuratorService.shared
        let plan = service.buildTrackVibePlan(
            name: "Shine On You Crazy Diamond",
            artist: "Pink Floyd",
            album: "Wish You Were Here",
            genreHint: "Progressive Rock",
            releaseYearHint: "1975-09-12",
            preferEnglish: false
        )
        XCTAssertTrue(plan.title.contains("ИИ-микс: Shine On You Crazy Diamond"))
        XCTAssertTrue(plan.subtitle.contains("Pink Floyd"))
        XCTAssertGreaterThanOrEqual(plan.seedQueries.count, 5)
        XCTAssertTrue(plan.seedQueries.contains(where: { $0.contains("Pink Floyd") }))
    }

    func testFilterAndInterleaveWaveSongsExcludesPlayedTracks() {
        let service = NativeMusicCuratorService.shared
        let existingQueue: [TrackInfo] = [
            TrackInfo(id: "1001", numericId: 1001, name: "Blue in Green", artist: "Miles Davis", album: "Kind of Blue", duration: 327, index: 1),
            TrackInfo(id: "1002", numericId: 1002, name: "Time", artist: "Pink Floyd", album: "The Dark Side of the Moon", duration: 413, index: 2)
        ]

        let bucket1: [[String: Any]] = [
            ["id": "1001", "name": "Blue in Green", "artist": "Miles Davis", "album": "Kind of Blue", "duration": 327],
            ["id": "2001", "name": "Almost Blue", "artist": "Chet Baker", "album": "Chet Baker Sings", "duration": 290],
            ["id": "2002", "name": "Take Five", "artist": "The Dave Brubeck Quartet", "album": "Time Out", "duration": 324]
        ]
        let bucket2: [[String: Any]] = [
            ["id": "1002", "name": "Time", "artist": "Pink Floyd", "album": "The Dark Side of the Moon", "duration": 413],
            ["id": "3001", "name": "5 Years", "artist": "Björk", "album": "Homogenic", "duration": 269]
        ]

        let wave = service.filterAndInterleaveWaveSongs(
            queryBuckets: [(0, bucket1, []), (1, bucket2, [])],
            excluding: existingQueue,
            maxCount: 10
        )

        XCTAssertEqual(wave.count, 3)
        let waveIds = Set(wave.compactMap { $0["id"] as? String })
        XCTAssertFalse(waveIds.contains("1001"))
        XCTAssertFalse(waveIds.contains("1002"))
        XCTAssertTrue(waveIds.contains("2001"))
        XCTAssertTrue(waveIds.contains("2002"))
        XCTAssertTrue(waveIds.contains("3001"))
    }

    func testIntelArchitectureGuardForcesAiDisabled() {
        let service = NativeMusicCuratorService.shared
        let prevEnabled = service.isEnabled
        defer {
            service.simulatedArchitectureIsAppleSilicon = nil
            service.isEnabled = prevEnabled
        }

        service.simulatedArchitectureIsAppleSilicon = false
        XCTAssertFalse(service.isAppleSilicon)
        XCTAssertFalse(service.isEnabled)

        // Attempting to enable AI on Intel must remain false
        service.isEnabled = true
        XCTAssertFalse(service.isEnabled)

        let dict = service.getSettingsDictionary()
        XCTAssertEqual(dict["is_apple_silicon"] as? Bool, false)
        XCTAssertEqual(dict["is_enabled"] as? Bool, false)
    }

    func testSemanticCosineFlowQueueOrderingAvoidsConsecutiveSameArtistAndGroupsVibe() {
        let service = NativeMusicCuratorService.shared
        let prevEnabled = service.isEnabled
        defer { service.isEnabled = prevEnabled }
        service.isEnabled = true

        let inputSongs: [[String: Any]] = [
            ["id": "1", "name": "So What", "artist": "Miles Davis", "album": "Kind of Blue", "genre": "Jazz"],
            ["id": "2", "name": "Freddie Freeloader", "artist": "Miles Davis", "album": "Kind of Blue", "genre": "Jazz"],
            ["id": "3", "name": "Techno Bunker", "artist": "Berlin Warehouse", "album": "Industrial Rave", "genre": "Electronic Techno"],
            ["id": "4", "name": "My Funny Valentine", "artist": "Chet Baker", "album": "Chet Baker Sings", "genre": "Cool Jazz Trumpet"]
        ]

        let ordered = service.orderSongsBySemanticFlow(inputSongs)
        XCTAssertEqual(ordered.count, 4)
        // First track stays anchor ("So What" - Miles Davis)
        XCTAssertEqual(ordered[0]["id"] as? String, "1")
        // Second track should be Chet Baker (Jazz, different artist) rather than consecutive Miles Davis or Industrial Techno
        XCTAssertEqual(ordered[1]["id"] as? String, "4")
        // No two consecutive tracks should share the same artist when avoidable
        for i in 1..<ordered.count {
            let prevArtist = ordered[i - 1]["artist"] as? String
            let curArtist = ordered[i]["artist"] as? String
            XCTAssertNotEqual(prevArtist, curArtist)
        }
    }

    func testVisionNeuralSaliencyArtworkPaletteExtractsVividSubjectOverBlackMargins() throws {
        let width = 128
        let height = 128
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ), let ptr = rep.bitmapData else {
            XCTFail("Failed to allocate bitmap")
            return
        }

        // Fill 85% with near-black margin (6, 6, 8) and draw a vivid crimson/orange salient prism in the center
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if x >= 44 && x <= 84 && y >= 44 && y <= 84 {
                    ptr[offset] = 235     // R
                    ptr[offset + 1] = 45  // G
                    ptr[offset + 2] = 90  // B
                    ptr[offset + 3] = 255 // A
                } else {
                    ptr[offset] = 6
                    ptr[offset + 1] = 6
                    ptr[offset + 2] = 8
                    ptr[offset + 3] = 255
                }
            }
        }

        guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) else {
            XCTFail("Failed to encode JPEG")
            return
        }

        let palette = ArtworkService.shared.extractVisionSaliencyPalette(from: jpegData, useNeuralSaliency: true)
        XCTAssertNotNil(palette)
        let ambient = palette?["ambient_rgb"] as? [[Int]]
        let wled = palette?["wled_zones"] as? [[Int]]
        XCTAssertEqual(ambient?.count, 4)
        XCTAssertEqual(wled?.count, 16)

        if let primary = ambient?.first, primary.count == 3 {
            // Primary extracted color must reflect the vivid crimson subject (high Red), not the black border
            XCTAssertGreaterThan(primary[0], 140)
            XCTAssertGreaterThan(primary[0], primary[1] * 2)
        } else {
            XCTFail("Missing primary ambient RGB color")
        }
    }
}
