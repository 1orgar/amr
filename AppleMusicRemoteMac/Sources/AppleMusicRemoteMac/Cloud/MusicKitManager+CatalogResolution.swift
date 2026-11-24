//
//  MusicKitManager+CatalogResolution.swift
//  AppleMusicRemoteMac
//
//  Alternate catalog song resolution (ISRC & multi-locale search), localized title/artist
//  variants caching, and pre-flight direct cloud song eligibility inspection.
//

import Foundation

extension MusicKitManager {

    // MARK: - Alternate Catalog Song & Localized Title Resolution

    public func resolveCatalogSongIdInUserStorefrontSync(name: String, artist: String) -> String? {
        return resolveAlternateCatalogSongIdsSync(name: name, artist: artist, excludingIds: []).first
    }

    public func resolveAlternateCatalogSongIdsSync(
        name: String,
        artist: String,
        excludingIds: Set<String>
    ) -> [String] {
        return resolveAlternateCatalogSongsSync(
            catalogId: nil,
            name: name,
            artist: artist,
            excludingIds: excludingIds
        ).map(\.id)
    }

    public func resolveAlternateCatalogSongsSync(
        catalogId: String?,
        name: String,
        artist: String,
        excludingIds: Set<String>
    ) -> [(id: String, name: String, artist: String)] {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return [] }
        guard let devToken = getDeveloperToken() else { return [] }
        let sf = Self.sanitizedStorefront(getUserStorefront())
        let primaryLang = getPreferredLanguageTag()
        let altLang = getSystemStorefrontAlternateLanguageTag()

        var results: [(id: String, name: String, artist: String)] = []
        var seenIds = excludingIds

        if let cleanCid = catalogId?.trimmingCharacters(in: .whitespacesAndNewlines),
           Self.isValidResourceIdentifier(cleanCid) {
            seenIds.insert(cleanCid)
            if let preferred = preferredAlternateCatalogSong(for: cleanCid),
               !seenIds.contains(preferred.id),
               !isUnstageableCatalogId(preferred.id) {
                seenIds.insert(preferred.id)
                results.append(preferred)
            }

            // Exact ISRC recording lookup (same master audio, zero false-positive remix risk)
            let inspection = inspectCatalogSongDirectCloudEligibilitySync(catalogId: cleanCid)
            if let rawIsrc = inspection?.isrc?.trimmingCharacters(in: .whitespacesAndNewlines),
               Self.isValidResourceIdentifier(rawIsrc),
               let isrcUrl = Self.makeAppleMusicAPIURL(
                   path: "/v1/catalog/\(sf)/songs",
                   queryItems: [
                       URLQueryItem(name: "filter[isrc]", value: rawIsrc),
                       URLQueryItem(name: "l", value: primaryLang)
                   ]
               ) {
                var req = URLRequest(url: isrcUrl, timeoutInterval: 3.2)
                req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                req.setValue(primaryLang, forHTTPHeaderField: "Accept-Language")
                if let uToken = getUserToken(), !uToken.isEmpty {
                    req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")
                }

                let sema = DispatchSemaphore(value: 0)
                let boxLock = NSLock()
                var isrcMatches: [(id: String, name: String, artist: String)] = []
                let task = session.dataTask(with: req) { [weak self] data, resp, _ in
                    defer { sema.signal() }
                    guard let self = self,
                          let d = data,
                          let http = resp as? HTTPURLResponse, http.statusCode == 200,
                          let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                          let arr = json["data"] as? [[String: Any]], !arr.isEmpty else { return }
                    var localMatches: [(id: String, name: String, artist: String)] = []
                    for item in arr {
                        guard let sid = item["id"] as? String,
                              Self.isValidResourceIdentifier(sid),
                              !excludingIds.contains(sid),
                              sid != cleanCid,
                              !self.isUnstageableCatalogId(sid),
                              let attr = item["attributes"] as? [String: Any],
                              attr["playParams"] != nil else { continue }
                        let sName = (attr["name"] as? String) ?? ""
                        let sArtist = (attr["artistName"] as? String) ?? ""
                        if !name.isEmpty && !sName.isEmpty && LibraryService.hasConflictingVersionQualifier(name, sName) {
                            continue
                        }
                        localMatches.append((id: sid, name: sName, artist: sArtist))
                    }
                    boxLock.lock()
                    isrcMatches = localMatches
                    boxLock.unlock()
                }
                task.resume()
                if sema.wait(timeout: .now() + 3.5) == .timedOut {
                    task.cancel()
                }
                boxLock.lock()
                let fetchedIsrc = isrcMatches
                boxLock.unlock()
                for m in fetchedIsrc where !seenIds.contains(m.id) {
                    seenIds.insert(m.id)
                    results.append(m)
                }
            }
        }

        if !results.isEmpty {
            return results
        }

        let effectiveSearchName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveSearchArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = "\(effectiveSearchName) \(effectiveSearchArtist)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return results }

        let targetNameNorm = LibraryService.normalizeMatchingTitle(effectiveSearchName)
        let targetBaseNorm = LibraryService.normalizeMatchingTitle(Self.extractBaseTrackTitle(effectiveSearchName))
        let targetArtistTokens = Self.extractArtistTokens(effectiveSearchArtist)

        func runSearchPass(langTag: String) -> (exact: [(id: String, name: String, artist: String)], crossScriptCandidates: [(id: String, name: String, artist: String)]) {
            guard let url = Self.makeAppleMusicAPIURL(
                path: "/v1/catalog/\(sf)/search",
                queryItems: [
                    URLQueryItem(name: "term", value: query),
                    URLQueryItem(name: "types", value: "songs"),
                    URLQueryItem(name: "limit", value: "12"),
                    URLQueryItem(name: "l", value: langTag)
                ]
            ) else {
                return ([], [])
            }
            var req = URLRequest(url: url, timeoutInterval: 3.2)
            req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue(langTag, forHTTPHeaderField: "Accept-Language")
            if let uToken = getUserToken(), !uToken.isEmpty {
                req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")
            }

            let sema = DispatchSemaphore(value: 0)
            let boxLock = NSLock()
            var exactMatched: [(id: String, name: String, artist: String)] = []
            var crossCandidates: [(id: String, name: String, artist: String)] = []

            let task = session.dataTask(with: req) { [weak self] data, resp, _ in
                defer { sema.signal() }
                guard let self = self,
                          let d = data, let http = resp as? HTTPURLResponse, http.statusCode == 200,
                          let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                          let resultsObj = json["results"] as? [String: Any],
                          let songs = resultsObj["songs"] as? [String: Any],
                          let arr = songs["data"] as? [[String: Any]], !arr.isEmpty else { return }

                var found: [(id: String, name: String, artist: String)] = []
                var cross: [(id: String, name: String, artist: String)] = []
                for item in arr {
                    guard let sid = item["id"] as? String,
                          Self.isValidResourceIdentifier(sid),
                          !seenIds.contains(sid),
                          !self.isUnstageableCatalogId(sid),
                          let attr = item["attributes"] as? [String: Any],
                          attr["playParams"] != nil else { continue }
                    let rawSName = (attr["name"] as? String) ?? ""
                    let rawSArtist = (attr["artistName"] as? String) ?? ""
                    if LibraryService.hasConflictingVersionQualifier(effectiveSearchName, rawSName) {
                        continue
                    }
                    let sName = LibraryService.normalizeMatchingTitle(rawSName)
                    let sBase = LibraryService.normalizeMatchingTitle(Self.extractBaseTrackTitle(rawSName))
                    let artistOk = targetArtistTokens.isEmpty || Self.matchesAnyCandidateArtist(rawSArtist, candidates: targetArtistTokens)
                    if artistOk && (sName == targetNameNorm || (!targetBaseNorm.isEmpty && sBase == targetBaseNorm)) {
                        if !found.contains(where: { $0.id == sid }) {
                            found.append((id: sid, name: rawSName, artist: rawSArtist))
                        }
                    } else if artistOk && !cross.contains(where: { $0.id == sid }) && cross.count < 3 {
                        cross.append((id: sid, name: rawSName, artist: rawSArtist))
                    }
                }
                if found.isEmpty && targetArtistTokens.isEmpty {
                    for item in arr {
                        if let sid = item["id"] as? String,
                           Self.isValidResourceIdentifier(sid),
                           !seenIds.contains(sid),
                           !self.isUnstageableCatalogId(sid) {
                            let attr = (item["attributes"] as? [String: Any]) ?? [:]
                            found.append((
                                id: sid,
                                name: (attr["name"] as? String) ?? "",
                                artist: (attr["artistName"] as? String) ?? ""
                            ))
                            break
                        }
                    }
                }
                boxLock.lock()
                exactMatched = found
                crossCandidates = cross
                boxLock.unlock()
            }
            task.resume()
            if sema.wait(timeout: .now() + 3.5) == .timedOut {
                task.cancel()
            }
            boxLock.lock()
            defer { boxLock.unlock() }
            return (exactMatched, crossCandidates)
        }

        let primaryPass = runSearchPass(langTag: primaryLang)
        var finalItems = primaryPass.exact

        if finalItems.isEmpty, let alt = altLang, !alt.isEmpty, alt.caseInsensitiveCompare(primaryLang) != .orderedSame {
            let altPass = runSearchPass(langTag: alt)
            finalItems = altPass.exact
        }

        if finalItems.isEmpty && !primaryPass.crossScriptCandidates.isEmpty {
            for cand in primaryPass.crossScriptCandidates.prefix(2) {
                let variants = resolveCatalogSongTitleVariantsSync(catalogId: cand.id)
                let matchesVariant = variants.contains { v in
                    guard !LibraryService.hasConflictingVersionQualifier(effectiveSearchName, v.name) else { return false }
                    let vNorm = LibraryService.normalizeMatchingTitle(v.name)
                    let vBase = LibraryService.normalizeMatchingTitle(Self.extractBaseTrackTitle(v.name))
                    return (!targetNameNorm.isEmpty && vNorm == targetNameNorm)
                        || (!targetBaseNorm.isEmpty && vBase == targetBaseNorm)
                }
                if matchesVariant {
                    finalItems.append(cand)
                    break
                }
            }
        }

        if excludingIds.isEmpty && catalogId == nil, let primaryFound = finalItems.first, !primaryFound.id.isEmpty {
            cacheTrackCatalogId(primaryFound.id, name: name, artist: artist, album: "")
        }
        return finalItems
    }

    internal static func extractBaseTrackTitle(_ title: String) -> String {
        var s = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parenIdx = s.firstIndex(of: "(") {
            let prefix = s[..<parenIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            if prefix.count >= 2 {
                s = prefix
            }
        }
        if let bracketIdx = s.firstIndex(of: "[") {
            let prefix = s[..<bracketIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            if prefix.count >= 2 {
                s = prefix
            }
        }
        if let dashRange = s.range(of: " - ") {
            let prefix = s[..<dashRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if prefix.count >= 2 {
                s = prefix
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    internal static func extractPrimaryArtist(_ artist: String) -> String {
        var s = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        for sep in [",", " & ", " feat.", " ft."] {
            if let r = s.range(of: sep, options: .caseInsensitive) {
                let prefix = s[..<r.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                if prefix.count >= 2 {
                    s = prefix
                    break
                }
            }
        }
        return s
    }

    public static func extractArtistTokens(_ artist: String) -> [String] {
        var normalized = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return [] }
        for sep in [" feat. ", " feat ", " ft. ", " ft ", " & ", " x ", " × ", " / ", " with ", ",", ";"] {
            normalized = normalized.replacingOccurrences(of: sep, with: "\u{001F}")
        }
        var tokens: [String] = []
        for rawPart in normalized.components(separatedBy: "\u{001F}") {
            let cleaned = rawPart
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.count >= 2 && !tokens.contains(cleaned) {
                tokens.append(cleaned)
            }
        }
        if tokens.isEmpty {
            let fallback = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !fallback.isEmpty {
                tokens.append(fallback)
            }
        }
        return tokens
    }

    public static func matchesAnyCandidateArtist(_ rowArtist: String, candidates: [String]) -> Bool {
        let rowClean = rowArtist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !rowClean.isEmpty, !candidates.isEmpty else { return true }
        let rowTokens = extractArtistTokens(rowClean)
        for cand in candidates {
            let c = cand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !c.isEmpty else { continue }
            if rowClean.contains(c) || c.contains(rowClean) {
                return true
            }
            if rowTokens.contains(where: { $0 == c || ($0.count >= 3 && c.count >= 3 && ($0.contains(c) || c.contains($0))) }) {
                return true
            }
        }
        return false
    }

    public static func artistsOverlap(_ first: String, _ second: String) -> Bool {
        let a = first.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let b = second.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b || a.contains(b) || b.contains(a) {
            return true
        }
        let tokensA = extractArtistTokens(a)
        guard !tokensA.isEmpty else { return false }
        return matchesAnyCandidateArtist(b, candidates: tokensA)
    }

    internal static let localizedTitlesCacheLock = NSLock()
    internal static var localizedTitlesCache: [String: [(name: String, artist: String)]] = [:]

    internal func fetchCatalogSongTitleSync(catalogId: String, sf: String, lang: String, devToken: String) -> (name: String, artist: String)? {
        guard Self.isValidStorefrontCode(sf),
              Self.isValidResourceIdentifier(catalogId),
              let url = Self.makeAppleMusicAPIURL(
                  path: "/v1/catalog/\(sf)/songs/\(catalogId)",
                  queryItems: [URLQueryItem(name: "l", value: lang)]
              ) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 2.0)
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(lang, forHTTPHeaderField: "Accept-Language")
        if let uToken = getUserToken(), !uToken.isEmpty {
            req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")
        }

        let sema = DispatchSemaphore(value: 0)
        let boxLock = NSLock()
        var resolved: (name: String, artist: String)?
        let task = session.dataTask(with: req) { data, resp, _ in
            defer { sema.signal() }
            guard let d = data, let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let arr = json["data"] as? [[String: Any]],
                  let first = arr.first,
                  let attr = first["attributes"] as? [String: Any],
                  let locName = attr["name"] as? String, !locName.isEmpty else { return }
            let locArtist = (attr["artistName"] as? String) ?? ""
            boxLock.lock()
            resolved = (locName, locArtist)
            boxLock.unlock()
        }
        task.resume()
        if sema.wait(timeout: .now() + 2.2) == .timedOut {
            task.cancel()
        }
        boxLock.lock()
        defer { boxLock.unlock() }
        return resolved
    }

    public func resolveCatalogSongTitleVariantsSync(catalogId: String) -> [(name: String, artist: String)] {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return [] }
        let cleanId = catalogId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty, Int(cleanId) != nil, let devToken = getDeveloperToken() else { return [] }
        let sf = Self.sanitizedStorefront(getUserStorefront())
        let primaryLang = getPreferredLanguageTag()
        let sysAltLang = getSystemStorefrontAlternateLanguageTag()
        let cacheKey = "\(sf)|\(cleanId)|\(primaryLang)|\(sysAltLang ?? "")"

        if let cached = Self.localizedTitlesCacheLock.withLock({ Self.localizedTitlesCache[cacheKey] }) {
            return cached
        }

        var variants: [(name: String, artist: String)] = []
        if let p = fetchCatalogSongTitleSync(catalogId: cleanId, sf: sf, lang: primaryLang, devToken: devToken) {
            variants.append(p)
        }
        if let alt = sysAltLang,
           let s = fetchCatalogSongTitleSync(catalogId: cleanId, sf: sf, lang: alt, devToken: devToken) {
            if !variants.contains(where: { $0.name == s.name && $0.artist == s.artist }) {
                variants.append(s)
            }
        }
        if !variants.isEmpty {
            Self.localizedTitlesCacheLock.withLock {
                if Self.localizedTitlesCache.count >= 500 {
                    var pruned: [String: [(name: String, artist: String)]] = [:]
                    for (k, v) in Self.localizedTitlesCache where pruned.count < 250 {
                        pruned[k] = v
                    }
                    Self.localizedTitlesCache = pruned
                }
                Self.localizedTitlesCache[cacheKey] = variants
            }
        }
        return variants
    }

    public func cachedTitleVariants(catalogId: String?) -> [(name: String, artist: String)] {
        guard let raw = catalogId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, Int(raw) != nil else {
            return []
        }
        let sf = Self.sanitizedStorefront(getUserStorefront())
        let primaryLang = getPreferredLanguageTag()
        let sysAltLang = getSystemStorefrontAlternateLanguageTag()
        let cacheKey = "\(sf)|\(raw)|\(primaryLang)|\(sysAltLang ?? "")"
        return Self.localizedTitlesCacheLock.withLock {
            Self.localizedTitlesCache[cacheKey] ?? []
        }
    }

    internal func appendCachedTitleVariant(catalogId: String, name: String, artist: String) {
        let cleanId = catalogId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty, Int(cleanId) != nil, (!cleanName.isEmpty || !cleanArtist.isEmpty) else { return }
        let sf = Self.sanitizedStorefront(getUserStorefront())
        let primaryLang = getPreferredLanguageTag()
        let sysAltLang = getSystemStorefrontAlternateLanguageTag()
        let cacheKey = "\(sf)|\(cleanId)|\(primaryLang)|\(sysAltLang ?? "")"
        Self.localizedTitlesCacheLock.withLock {
            var existing = Self.localizedTitlesCache[cacheKey] ?? []
            if !existing.contains(where: { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame && $0.artist.caseInsensitiveCompare(cleanArtist) == .orderedSame }) {
                existing.append((name: cleanName, artist: cleanArtist))
                if Self.localizedTitlesCache[cacheKey] == nil && Self.localizedTitlesCache.count >= 500 {
                    var pruned: [String: [(name: String, artist: String)]] = [:]
                    for (k, v) in Self.localizedTitlesCache where pruned.count < 250 {
                        pruned[k] = v
                    }
                    Self.localizedTitlesCache = pruned
                }
                Self.localizedTitlesCache[cacheKey] = existing
            }
        }
    }

    public func resolveLocalizedCatalogSongTitleSync(catalogId: String) -> (name: String, artist: String)? {
        let variants = resolveCatalogSongTitleVariantsSync(catalogId: catalogId)
        if variants.count >= 2 {
            return variants[1]
        }
        return variants.first
    }

    // MARK: - Direct Cloud Song Eligibility Inspection

    public struct DirectCloudSongInspection: Sendable {
        public let hasStationSeed: Bool
        public let isHiResLossless: Bool
        public let isLossless: Bool
        public let durationSeconds: Double?
        public let isrc: String?
        public let catalogName: String?
        public let catalogArtist: String?

        public init(
            hasStationSeed: Bool,
            isHiResLossless: Bool,
            isLossless: Bool,
            durationSeconds: Double?,
            isrc: String? = nil,
            catalogName: String? = nil,
            catalogArtist: String? = nil
        ) {
            self.hasStationSeed = hasStationSeed
            self.isHiResLossless = isHiResLossless
            self.isLossless = isLossless
            self.durationSeconds = durationSeconds
            self.isrc = isrc
            self.catalogName = catalogName
            self.catalogArtist = catalogArtist
        }
    }

    internal static let directInspectionCacheLock = NSLock()
    internal static var directInspectionCache: [String: DirectCloudSongInspection] = [:]

    public func inspectCatalogSongDirectCloudEligibilitySync(catalogId: String) -> DirectCloudSongInspection? {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return nil }
        let cleanId = catalogId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty, Int(cleanId) != nil else { return nil }

        if let cached = Self.directInspectionCacheLock.withLock({ Self.directInspectionCache[cleanId] }) {
            return cached
        }
        guard let devToken = getDeveloperToken() else { return nil }
        let sf = Self.sanitizedStorefront(getUserStorefront())
        guard let url = Self.makeAppleMusicAPIURL(
            path: "/v1/catalog/\(sf)/songs/\(cleanId)",
            queryItems: [
                URLQueryItem(name: "relate", value: "station"),
                URLQueryItem(name: "extend", value: "audioVariants")
            ]
        ) else {
            return nil
        }

        var req = URLRequest(url: url, timeoutInterval: 1.5)
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let uToken = getUserToken(), !uToken.isEmpty {
            req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")
        }

        let sema = DispatchSemaphore(value: 0)
        let boxLock = NSLock()
        var parsed: DirectCloudSongInspection?
        let task = session.dataTask(with: req) { data, resp, _ in
            defer { sema.signal() }
            guard let http = resp as? HTTPURLResponse else { return }
            if http.statusCode == 404 {
                boxLock.lock()
                parsed = DirectCloudSongInspection(hasStationSeed: false, isHiResLossless: false, isLossless: false, durationSeconds: nil)
                boxLock.unlock()
                return
            }
            guard http.statusCode == 200,
                  let d = data,
                  let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let arr = json["data"] as? [[String: Any]],
                  let item = arr.first else { return }

            let attr = (item["attributes"] as? [String: Any]) ?? [:]
            let variants = (attr["audioVariants"] as? [String]) ?? []
            let isHiRes = variants.contains { $0.caseInsensitiveCompare("hi-res-lossless") == .orderedSame }
            let isLossless = isHiRes || variants.contains { $0.caseInsensitiveCompare("lossless") == .orderedSame }
            let durSec: Double? = (attr["durationInMillis"] as? Double).flatMap { $0 > 0 ? ($0 / 1000.0) : nil }
            let rawIsrc = (attr["isrc"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawCatName = (attr["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawCatArtist = (attr["artistName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            var hasStation = false
            if let rels = item["relationships"] as? [String: Any],
               let stationRel = rels["station"] as? [String: Any],
               let stData = stationRel["data"] as? [[String: Any]],
               let stId = stData.first?["id"] as? String,
               !stId.isEmpty {
                hasStation = true
            }

            boxLock.lock()
            parsed = DirectCloudSongInspection(
                hasStationSeed: hasStation,
                isHiResLossless: isHiRes,
                isLossless: isLossless,
                durationSeconds: durSec,
                isrc: (rawIsrc?.isEmpty == false) ? rawIsrc : nil,
                catalogName: (rawCatName?.isEmpty == false) ? rawCatName : nil,
                catalogArtist: (rawCatArtist?.isEmpty == false) ? rawCatArtist : nil
            )
            boxLock.unlock()
        }
        task.resume()
        if sema.wait(timeout: .now() + 1.6) == .timedOut {
            task.cancel()
        }
        boxLock.lock()
        let result = parsed
        boxLock.unlock()
        if let valid = result {
            Self.directInspectionCacheLock.withLock {
                if Self.directInspectionCache.count >= 500 {
                    var pruned: [String: DirectCloudSongInspection] = [:]
                    for (k, v) in Self.directInspectionCache where pruned.count < 250 {
                        pruned[k] = v
                    }
                    Self.directInspectionCache = pruned
                }
                Self.directInspectionCache[cleanId] = valid
            }
        }
        return result
    }

    public func resolveCatalogSongDurationSync(catalogId: String) -> Double? {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return nil }
        let cleanId = catalogId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty, Int(cleanId) != nil, let devToken = getDeveloperToken() else { return nil }
        let sf = Self.sanitizedStorefront(getUserStorefront())
        guard let url = Self.makeAppleMusicAPIURL(path: "/v1/catalog/\(sf)/songs/\(cleanId)") else { return nil }

        var req = URLRequest(url: url, timeoutInterval: 2.5)
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let uToken = getUserToken(), !uToken.isEmpty {
            req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")
        }

        let sema = DispatchSemaphore(value: 0)
        let boxLock = NSLock()
        var durationSec: Double?
        let task = session.dataTask(with: req) { data, resp, _ in
            defer { sema.signal() }
            guard let d = data, let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let arr = json["data"] as? [[String: Any]],
                  let attr = arr.first?["attributes"] as? [String: Any],
                  let durMs = attr["durationInMillis"] as? Double, durMs > 0 else { return }
            boxLock.lock()
            durationSec = durMs / 1000.0
            boxLock.unlock()
        }
        task.resume()
        if sema.wait(timeout: .now() + 2.7) == .timedOut {
            task.cancel()
        }
        boxLock.lock()
        defer { boxLock.unlock() }
        return durationSec
    }
}
