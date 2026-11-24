//
//  CrossLocalePlaylistAndSearchQueueTests.swift
//  AppleMusicRemoteMacTests
//
//  Tests for search queue & saved playlist naming (`"Поиск: <query>"`) and
//  cross-locale catalog / Personal Mix playlist recognition (`"2010s Metal Essentials"` <-> `"Метал 2010-х: главное"`,
//  `"Get Up! Mix"` <-> `"На старт!"`).
//

import XCTest
@testable import AppleMusicRemoteMac

final class CrossLocalePlaylistAndSearchQueueTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PlaybackStateStore.shared.resetCustomQueue()
        LibraryService.shared.lock.withLock {
            LibraryService.shared.playlistsCache = nil
            LibraryService.shared.recentlyAddedPlaylists.removeAll()
            LibraryService.shared.cloudPlaylistMetadataItems.removeAll()
            LibraryService.shared.cloudPlaylistMetaTimestamp = nil
        }
    }

    override func tearDown() {
        PlaybackStateStore.shared.resetCustomQueue()
        LibraryService.shared.lock.withLock {
            LibraryService.shared.playlistsCache = nil
            LibraryService.shared.recentlyAddedPlaylists.removeAll()
            LibraryService.shared.cloudPlaylistMetadataItems.removeAll()
            LibraryService.shared.cloudPlaylistMetaTimestamp = nil
        }
        super.tearDown()
    }

    // MARK: - 1. Search Queue & Saved Playlist Naming

    func testPlaySearchResultsWithQueryNamesQueueAfterSearchQuery() async {
        let tracks = [
            TrackInfo(id: "1440818890", name: "Numb", artist: "Linkin Park", isLocal: false),
            TrackInfo(id: "1440818892", name: "Faint", artist: "Linkin Park", isLocal: false)
        ]

        _ = await PlaybackRouter.shared.playSearchResults(
            tracks: tracks,
            shuffle: false,
            queueName: "Результаты поиска",
            query: "Linkin Park"
        )

        let store = PlaybackStateStore.shared
        XCTAssertEqual(store.activeCustomQueueName, "Поиск: Linkin Park")
        XCTAssertEqual(store.activeSearchQuery, "Linkin Park")
    }

    func testFormatSearchQueuePlaylistNameHandlesRussianEnglishAndExplicitCuratorTitle() {
        XCTAssertEqual(
            PlaybackRouter.formatSearchQueuePlaylistName(
                query: "2010s Metal",
                explicitQueueName: "Результаты поиска",
                preferEnglish: false
            ),
            "Поиск: 2010s Metal"
        )
        XCTAssertEqual(
            PlaybackRouter.formatSearchQueuePlaylistName(
                query: "2010s Metal",
                explicitQueueName: "Search Results",
                preferEnglish: true
            ),
            "Search: 2010s Metal"
        )
        XCTAssertEqual(
            PlaybackRouter.formatSearchQueuePlaylistName(
                query: "2010s Metal",
                explicitQueueName: "✨ Ночной драйв",
                preferEnglish: false
            ),
            "✨ Ночной драйв"
        )
        XCTAssertEqual(
            PlaybackRouter.formatSearchQueuePlaylistName(
                query: nil,
                explicitQueueName: nil,
                preferEnglish: false
            ),
            "Результаты поиска"
        )
    }

    func testResolveSavedQueuePlaylistNameNeverSavesGenericSearchResultsWhenQueryExists() {
        let savedRu = PlaybackRouter.resolveSavedQueuePlaylistName(
            explicitName: "Результаты поиска",
            activeQueueName: "Результаты поиска",
            activeSearchQuery: "Bring Me The Horizon",
            activeCuratorPrompt: nil,
            preferEnglish: false
        )
        XCTAssertEqual(savedRu, "Поиск: Bring Me The Horizon")

        let savedEn = PlaybackRouter.resolveSavedQueuePlaylistName(
            explicitName: "Очередь AMR",
            activeQueueName: "Search Results",
            activeSearchQuery: "Architects",
            activeCuratorPrompt: nil,
            preferEnglish: true
        )
        XCTAssertEqual(savedEn, "Search: Architects")

        let savedNamedQueue = PlaybackRouter.resolveSavedQueuePlaylistName(
            explicitName: "",
            activeQueueName: "Поиск: Deftones",
            activeSearchQuery: "Deftones",
            activeCuratorPrompt: nil,
            preferEnglish: false
        )
        XCTAssertEqual(savedNamedQueue, "Поиск: Deftones")

        let savedCurator = PlaybackRouter.resolveSavedQueuePlaylistName(
            explicitName: "Очередь AMR",
            activeQueueName: "Очередь AMR",
            activeSearchQuery: nil,
            activeCuratorPrompt: "Киберпанк синтвейв",
            preferEnglish: false
        )
        XCTAssertEqual(savedCurator, "✨ Киберпанк синтвейв")
    }

    // MARK: - 2. Cross-Locale Catalog Playlist Matching ("2010s Metal Essentials" <-> "Метал 2010-х: главное")

    func testCatalogPlaylistMatchesLocalizedRussianLibraryPlaylistByCatalogIdAndAlternateTitle() {
        let libService = LibraryService.shared
        let catalogId = "pl.6daccd753d984513ab0596a356cb50e3"
        let libraryId = "p.V7VY856hZ3x1Ab"

        libService.lock.withLock {
            libService.playlistsCache = (
                timestamp: Date(),
                playlists: [
                    PlaylistInfo(name: "Метал 2010-х: главное", trackCount: 100, isPlaylist: true)
                ]
            )
            libService.cloudPlaylistMetadataItems = [
                CloudLibraryPlaylistMetadata(
                    libraryId: libraryId,
                    catalogId: catalogId,
                    names: ["Метал 2010-х: главное", "2010s Metal Essentials"],
                    artworkUrl: "https://is1-ssl.mzstatic.com/image/thumb/Features/metal2010s.jpg"
                )
            ]
            libService.cloudPlaylistMetaTimestamp = Date()
        }

        // Lookup by English catalog ID + English catalog title
        let matchedByIdAndEnglishName = libService.findMatchingLocalPlaylist(
            id: catalogId,
            name: "2010s Metal Essentials"
        )
        XCTAssertNotNil(matchedByIdAndEnglishName)
        XCTAssertEqual(matchedByIdAndEnglishName?.name, "Метал 2010-х: главное")
        XCTAssertEqual(matchedByIdAndEnglishName?.id, libraryId)
        XCTAssertEqual(matchedByIdAndEnglishName?.catalogId, catalogId)
        XCTAssertEqual(matchedByIdAndEnglishName?.trackCount, 100)

        // Lookup by English title alone (when catalog ID is omitted)
        let matchedByEnglishTitleOnly = libService.findMatchingLocalPlaylist(
            id: nil,
            name: "2010s Metal Essentials"
        )
        XCTAssertEqual(matchedByEnglishTitleOnly?.name, "Метал 2010-х: главное")

        // Optimistic English addition merges cleanly into localized Russian playlist without duplicating
        libService.recordRecentlyAddedPlaylist(
            id: catalogId,
            name: "2010s Metal Essentials",
            trackCount: 100
        )
        libService.lock.withLock {
            libService.playlistsCache = (
                timestamp: Date(),
                playlists: [
                    PlaylistInfo(
                        name: "Метал 2010-х: главное",
                        trackCount: 100,
                        isPlaylist: true,
                        id: libraryId,
                        catalogId: catalogId,
                        alternateNames: ["Метал 2010-х: главное", "2010s Metal Essentials"]
                    )
                ]
            )
        }
        let merged = libService.getPlaylists(forceRefresh: false)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.name, "Метал 2010-х: главное")
        XCTAssertEqual(merged.first?.catalogId, catalogId)
    }

    // MARK: - 3. Personal Mix Cross-Locale Matching ("Get Up! Mix" <-> "На старт!")

    func testPersonalMixGetUpMatchesRussianNaStartWithoutCloudMetadata() {
        let libService = LibraryService.shared
        XCTAssertTrue(LibraryService.playlistsSharePersonalMixAlias("Get Up! Mix", "На старт!"))
        XCTAssertTrue(LibraryService.playlistsSharePersonalMixAlias("Get Up!", "На старт"))
        XCTAssertTrue(LibraryService.playlistsSharePersonalMixAlias("Get Up! Mix", "На старт!: микс"))
        XCTAssertTrue(LibraryService.playlistsSharePersonalMixAlias("Chill Mix", "Для отдыха"))
        XCTAssertTrue(LibraryService.playlistsSharePersonalMixAlias("Favorites Mix", "Фавориты"))
        XCTAssertTrue(LibraryService.playlistsSharePersonalMixAlias("New Music Mix", "Новинки для вас"))
        XCTAssertTrue(LibraryService.playlistsSharePersonalMixAlias("Friends Mix", "Микс друзей"))
        XCTAssertTrue(WebSocketServer.matchesPersonalMix(queryLower: "на старт!", candidateLower: "get up! mix"))

        libService.lock.withLock {
            libService.playlistsCache = (
                timestamp: Date(),
                playlists: [
                    PlaylistInfo(name: "На старт!", trackCount: 25, isPlaylist: true)
                ]
            )
        }

        let matched = libService.findMatchingLocalPlaylist(
            id: "pl.pm-20e98a1f2b3c4d5e",
            name: "Get Up! Mix"
        )
        XCTAssertNotNil(matched)
        XCTAssertEqual(matched?.name, "На старт!")
        XCTAssertEqual(matched?.trackCount, 25)
    }

    // MARK: - 4. Bundled Web UI Regression Checks

    func testWebUIBundleIncludesCrossLocalePlaylistMatchingAndSearchQueueNaming() {
        let js = WebUIContent.appJS
        XCTAssertTrue(js.contains("playlistsMatchCrossLocaleClient"))
        XCTAssertTrue(js.contains("syncSearchPlaylistCardsLibraryStatus"))
        XCTAssertTrue(js.contains("'на старт!'"))
        XCTAssertTrue(js.contains("Поиск: ${resolvedQuery}"))
        XCTAssertFalse(js.contains("track_count: pl.track_count || 25"))
        XCTAssertFalse(js.contains("track_count: mix.track_count || mix.trackCount || 25"))
    }
}
