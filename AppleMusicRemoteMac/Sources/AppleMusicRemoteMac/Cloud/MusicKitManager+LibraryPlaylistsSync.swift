//
//  MusicKitManager+LibraryPlaylistsSync.swift
//  AppleMusicRemoteMac
//
//  Read-only `/v1/me/library/playlists` metadata resolver mapping Apple Music library playlists (`p.xxx`),
//  global catalog IDs (`pl.xxx` / `pl.pm-xxx`), and localized titles across storefront + macOS UI languages
//  (e.g. `"2010s Metal Essentials"` <-> `"Метал 2010-х: главное"`, `"Get Up! Mix"` <-> `"На старт!"`).
//

import Foundation

public struct CloudLibraryPlaylistMetadata: Sendable {
    public let libraryId: String
    public var catalogId: String?
    public var names: [String]
    public var artworkUrl: String?

    public init(
        libraryId: String,
        catalogId: String? = nil,
        names: [String] = [],
        artworkUrl: String? = nil
    ) {
        self.libraryId = libraryId
        self.catalogId = catalogId
        self.names = names
        self.artworkUrl = artworkUrl
    }
}

extension MusicKitManager {

    private static let cloudPlaylistsMetaLock = NSLock()
    private static var cloudPlaylistsMetaCache: (timestamp: Date, items: [CloudLibraryPlaylistMetadata])?
    private static let cloudPlaylistsMetaCacheTTL: TimeInterval = 45.0

    public func invalidateCloudLibraryPlaylistsCache() {
        Self.cloudPlaylistsMetaLock.withLock {
            Self.cloudPlaylistsMetaCache = nil
        }
    }

    internal static func systemUILanguageTag() -> String {
        let raw = (Locale.preferredLanguages.first ?? "ru-RU").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "ru" }
        let lower = raw.lowercased()
        if lower.hasPrefix("ru") {
            return "ru"
        }
        return raw
    }

    private func fetchRawUserLibraryPlaylistsPage(
        devToken: String,
        userToken: String,
        langTag: String
    ) async -> [[String: Any]] {
        guard let url = Self.makeAppleMusicAPIURL(
            path: "/v1/me/library/playlists",
            queryItems: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "include", value: "catalog"),
                URLQueryItem(name: "l", value: langTag)
            ]
        ) else {
            return []
        }
        var req = URLRequest(url: url, timeoutInterval: 4.5)
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue(userToken, forHTTPHeaderField: "Music-User-Token")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(langTag, forHTTPHeaderField: "Accept-Language")

        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]] else {
            return []
        }
        return arr
    }

    private func fetchCatalogPlaylistLocalizedNames(
        catalogIds: [String],
        storefront: String,
        langTag: String,
        devToken: String,
        userToken: String
    ) async -> [String: String] {
        let validIds = Array(catalogIds.filter { Self.isValidResourceIdentifier($0) }.prefix(25))
        guard !validIds.isEmpty,
              Self.isValidStorefrontCode(storefront),
              let url = Self.makeAppleMusicAPIURL(
                  path: "/v1/catalog/\(storefront)/playlists",
                  queryItems: [
                      URLQueryItem(name: "ids", value: validIds.joined(separator: ",")),
                      URLQueryItem(name: "l", value: langTag)
                  ]
              ) else {
            return [:]
        }
        var req = URLRequest(url: url, timeoutInterval: 4.0)
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue(userToken, forHTTPHeaderField: "Music-User-Token")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(langTag, forHTTPHeaderField: "Accept-Language")

        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]] else {
            return [:]
        }
        var out: [String: String] = [:]
        for item in arr {
            guard let cid = item["id"] as? String,
                  let attrs = item["attributes"] as? [String: Any],
                  let name = (attrs["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            out[cid.lowercased()] = name
        }
        return out
    }

    public func fetchCloudLibraryPlaylistsMetadata(forceRefresh: Bool = false) async -> [CloudLibraryPlaylistMetadata] {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return [] }
        if !forceRefresh, let cached = Self.cloudPlaylistsMetaLock.withLock({ () -> [CloudLibraryPlaylistMetadata]? in
            guard let entry = Self.cloudPlaylistsMetaCache,
                  Date().timeIntervalSince(entry.timestamp) < Self.cloudPlaylistsMetaCacheTTL else {
                return nil
            }
            return entry.items
        }) {
            return cached
        }

        guard let devToken = getDeveloperToken(),
              let uToken = getUserToken(), !uToken.isEmpty else {
            return []
        }

        let primaryLang = getPreferredLanguageTag()
        let uiLang = Self.systemUILanguageTag()
        let primaryPrefix = primaryLang.split(separator: "-").first.map(String.init)?.lowercased() ?? primaryLang.lowercased()
        let uiPrefix = uiLang.split(separator: "-").first.map(String.init)?.lowercased() ?? uiLang.lowercased()
        let needSecondLang = !uiPrefix.isEmpty && uiPrefix != primaryPrefix

        async let primaryItemsTask = fetchRawUserLibraryPlaylistsPage(devToken: devToken, userToken: uToken, langTag: primaryLang)
        async let uiItemsTask: [[String: Any]] = needSecondLang
            ? fetchRawUserLibraryPlaylistsPage(devToken: devToken, userToken: uToken, langTag: uiLang)
            : []

        let (primaryItems, uiItems) = await (primaryItemsTask, uiItemsTask)
        guard !primaryItems.isEmpty || !uiItems.isEmpty else { return [] }

        var byLibId: [String: CloudLibraryPlaylistMetadata] = [:]
        var orderedLibIds: [String] = []

        func appendDistinctName(_ rawName: String?, into list: inout [String]) {
            guard let trimmed = rawName?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return }
            if !list.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                list.append(trimmed)
            }
        }

        func ingest(_ arr: [[String: Any]]) {
            for item in arr {
                guard let libId = (item["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      Self.isValidResourceIdentifier(libId) else { continue }
                let attrs = (item["attributes"] as? [String: Any]) ?? [:]
                let attrName = attrs["name"] as? String
                let playParams = attrs["playParams"] as? [String: Any]
                let globalId = (playParams?["globalId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

                var relCatalogId: String? = nil
                var relCatalogName: String? = nil
                var relArtworkUrl: String? = nil
                if let rels = item["relationships"] as? [String: Any],
                   let catObj = rels["catalog"] as? [String: Any],
                   let catData = catObj["data"] as? [[String: Any]],
                   let firstCat = catData.first {
                    relCatalogId = (firstCat["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let catAttrs = firstCat["attributes"] as? [String: Any] {
                        relCatalogName = catAttrs["name"] as? String
                        if let artObj = catAttrs["artwork"] as? [String: Any],
                           let rawUrl = artObj["url"] as? String, !rawUrl.isEmpty {
                            relArtworkUrl = rawUrl
                                .replacingOccurrences(of: "{w}", with: "600")
                                .replacingOccurrences(of: "{h}", with: "600")
                        }
                    }
                }

                var directArtUrl: String? = nil
                if let artObj = attrs["artwork"] as? [String: Any],
                   let rawUrl = artObj["url"] as? String, !rawUrl.isEmpty,
                   rawUrl.hasPrefix("http") {
                    directArtUrl = rawUrl
                        .replacingOccurrences(of: "{w}", with: "600")
                        .replacingOccurrences(of: "{h}", with: "600")
                }

                let resolvedCatId = (globalId?.isEmpty == false ? globalId : relCatalogId)
                var entry = byLibId[libId] ?? {
                    orderedLibIds.append(libId)
                    return CloudLibraryPlaylistMetadata(libraryId: libId)
                }()
                if entry.catalogId == nil, let cid = resolvedCatId, !cid.isEmpty {
                    entry.catalogId = cid
                }
                if entry.artworkUrl == nil, let art = relArtworkUrl ?? directArtUrl, !art.isEmpty {
                    entry.artworkUrl = art
                }
                appendDistinctName(attrName, into: &entry.names)
                appendDistinctName(relCatalogName, into: &entry.names)
                byLibId[libId] = entry
            }
        }

        ingest(primaryItems)
        ingest(uiItems)

        // Ensure catalog playlists (`pl.xxx`) also include both UI-locale and storefront-locale titles
        let sf = Self.sanitizedStorefront(getUserStorefront())
        let cidsNeedingUiLocale: [String] = needSecondLang
            ? orderedLibIds.compactMap { lid -> String? in
                guard let e = byLibId[lid], let cid = e.catalogId, cid.hasPrefix("pl.") else { return nil }
                return cid
            }
            : []
        if !cidsNeedingUiLocale.isEmpty {
            let localizedMap = await fetchCatalogPlaylistLocalizedNames(
                catalogIds: cidsNeedingUiLocale,
                storefront: sf,
                langTag: uiLang,
                devToken: devToken,
                userToken: uToken
            )
            if !localizedMap.isEmpty {
                for lid in orderedLibIds {
                    guard var e = byLibId[lid], let cid = e.catalogId?.lowercased(),
                          let locTitle = localizedMap[cid] else { continue }
                    appendDistinctName(locTitle, into: &e.names)
                    byLibId[lid] = e
                }
            }
        }

        let results = orderedLibIds.compactMap { byLibId[$0] }
        Self.cloudPlaylistsMetaLock.withLock {
            Self.cloudPlaylistsMetaCache = (timestamp: Date(), items: results)
        }
        return results
    }
}
