//
//  MusicKitManager+Stations.swift
//  AppleMusicRemoteMac
//
//  Artist & track radio station resolution and fuzzy similarity scoring.
//

import Foundation

extension MusicKitManager {

    // MARK: - Station Fuzzy Matching Helpers

    public static func normalizeQueryText(_ str: String) -> String {
        let lower = str.lowercased()
        let withoutParens = lower
            .replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\[.*?\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: ##"[!"#$%&'()*+,-./:;<=>?@\[\\\]^_`{|}~]"##, with: " ", options: .regularExpression)
        return withoutParens.split(separator: " ").joined(separator: " ")
    }

    public static func computeSongSimilarity(
        queryTitle: String,
        queryArtist: String,
        candidateTitle: String,
        candidateArtist: String
    ) -> (score: Double, isMatch: Bool) {
        let normQT = normalizeQueryText(queryTitle)
        let normQA = normalizeQueryText(queryArtist)
        let normCT = normalizeQueryText(candidateTitle)
        let normCA = normalizeQueryText(candidateArtist)

        var titleScore = 0.0
        if normQT == normCT {
            titleScore = 1.0
        } else if normCT.contains(normQT) || normQT.contains(normCT) {
            titleScore = 0.85
        } else {
            let qWords = Set(normQT.split(separator: " "))
            let cWords = Set(normCT.split(separator: " "))
            let common = qWords.intersection(cWords)
            if !qWords.isEmpty {
                titleScore = Double(common.count) / Double(qWords.count)
            }
        }

        var artistScore = 0.0
        if normQA.isEmpty {
            artistScore = 1.0
        } else if normQA == normCA {
            artistScore = 1.0
        } else if normCA.contains(normQA) || normQA.contains(normCA) {
            artistScore = 0.85
        } else {
            let qWords = Set(normQA.split(separator: " "))
            let cWords = Set(normCA.split(separator: " "))
            let common = qWords.intersection(cWords)
            if !qWords.isEmpty {
                artistScore = Double(common.count) / Double(qWords.count)
            }
        }

        let total = (titleScore * 0.65) + (artistScore * 0.35)
        let isMatch = titleScore >= 0.5 && (normQA.isEmpty || artistScore >= 0.3)
        return (total, isMatch)
    }

    public func extractArtistCandidates(from raw: String) -> [String] {
        var result: [String] = []
        func add(_ s: String) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count > 1 && !result.contains(t) {
                result.append(t)
            }
        }

        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = cleaned.range(of: " и другие", options: .caseInsensitive) {
            cleaned = String(cleaned[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if cleaned.lowercased().hasPrefix("при участии:") {
            cleaned = String(cleaned.dropFirst("при участии:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        add(raw)
        add(cleaned)

        if let lastAmp = cleaned.range(of: " & ", options: .backwards) {
            let beforeLast = String(cleaned[..<lastAmp.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            add(beforeLast)
        }

        var subParts = [cleaned]
        let sepList = [" & ", ", ", " feat. ", " feat ", " ft. ", " ft ", " / ", " with ", " x ", " X "]
        for sep in sepList {
            var nextParts: [String] = []
            for part in subParts {
                let chunks = part.components(separatedBy: sep)
                nextParts.append(contentsOf: chunks)
            }
            subParts = nextParts
        }

        for p in subParts {
            add(p)
        }

        if let firstAmp = cleaned.components(separatedBy: " & ").first {
            add(firstAmp)
        }

        return result
    }

    public func resolveArtistStation(artist: String, storefront: String = "") async -> ArtistStationInfo? {
        let clean = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }

        if let cached = getCachedArtistStation(for: clean) {
            return cached
        }

        let candidates = extractArtistCandidates(from: clean)
        let primarySf = Self.sanitizedStorefront(storefront, fallback: getUserStorefront())
        var uniqueSfs: [String] = []
        for s in [primarySf, "us", "jp"] where Self.isValidStorefrontCode(s) && !uniqueSfs.contains(s) {
            uniqueSfs.append(s)
        }

        // 1. Try Apple Music Catalog API with developer token
        if let token = getDeveloperToken() {
            let lang = getPreferredLanguageTag()
            for sf in uniqueSfs {
                for candidate in candidates {
                    guard let url = Self.makeAppleMusicAPIURL(
                        path: "/v1/catalog/\(sf)/search",
                        queryItems: [
                            URLQueryItem(name: "term", value: candidate),
                            URLQueryItem(name: "types", value: "artists"),
                            URLQueryItem(name: "limit", value: "5"),
                            URLQueryItem(name: "l", value: lang)
                        ]
                    ) else { continue }
                    var req = URLRequest(url: url)
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    req.setValue("application/json", forHTTPHeaderField: "Accept")
                    req.setValue(lang, forHTTPHeaderField: "Accept-Language")
                    req.timeoutInterval = 3.0

                    guard let (data, resp) = try? await session.data(for: req),
                          let http = resp as? HTTPURLResponse, http.statusCode == 200,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let results = json["results"] as? [String: Any],
                          let artists = results["artists"] as? [String: Any],
                          let dataArr = artists["data"] as? [[String: Any]] else {
                        continue
                    }

                    for item in dataArr {
                        guard let idStr = item["id"] as? String,
                              let artistId = Int(idStr),
                              artistId > 0,
                              let attrs = item["attributes"] as? [String: Any],
                              let aName = attrs["name"] as? String else { continue }

                        let normCand = Self.normalizeQueryText(candidate)
                        let normName = Self.normalizeQueryText(aName)
                        let isMatch = normCand == normName || normName.contains(normCand) || normCand.contains(normName)
                        if isMatch {
                            let canonicalName = aName
                            let stationUrl = "https://music.apple.com/\(sf)/station/item/ra.\(artistId)"
                            var artworkUrl: String? = nil
                            if let artObj = attrs["artwork"] as? [String: Any],
                               let artTmpl = artObj["url"] as? String {
                                artworkUrl = artTmpl
                                    .replacingOccurrences(of: "{w}x{h}", with: "600x600")
                                    .replacingOccurrences(of: "{w}", with: "600")
                                    .replacingOccurrences(of: "{h}", with: "600")
                                    .replacingOccurrences(of: "{f}", with: "jpg")
                            }

                            let info = ArtistStationInfo(
                                artistId: artistId,
                                canonicalName: canonicalName,
                                stationUrl: stationUrl,
                                artworkUrl: artworkUrl
                            )
                            setCachedArtistStation(info, for: clean)
                            if clean.lowercased() != candidate.lowercased() {
                                setCachedArtistStation(info, for: candidate)
                            }
                            return info
                        }
                    }
                }
            }
        }

        // 2. Fallback to iTunes Store Search API
        for candidate in candidates {
            for country in uniqueSfs {
                var sComps = URLComponents()
                sComps.scheme = "https"
                sComps.host = "itunes.apple.com"
                sComps.path = "/search"
                sComps.queryItems = [
                    URLQueryItem(name: "term", value: candidate),
                    URLQueryItem(name: "entity", value: "musicArtist"),
                    URLQueryItem(name: "limit", value: "5"),
                    URLQueryItem(name: "country", value: country)
                ]
                guard let url = sComps.url else { continue }
                var req = URLRequest(url: url)
                req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                req.timeoutInterval = 3.0

                guard let (data, resp) = try? await session.data(for: req),
                      let http = resp as? HTTPURLResponse, http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [[String: Any]] else {
                    continue
                }

                for item in results {
                    guard let artistId = item["artistId"] as? Int,
                          artistId > 0,
                          let aName = item["artistName"] as? String else { continue }

                    let normCand = Self.normalizeQueryText(candidate)
                    let normName = Self.normalizeQueryText(aName)
                    let isMatch = normCand == normName || normName.contains(normCand) || normCand.contains(normName)
                    guard isMatch else { continue }

                    let canonicalName = aName
                    let stationUrl = "https://music.apple.com/\(country)/station/item/ra.\(artistId)"

                    var artworkUrl: String? = nil
                    var lComps = URLComponents()
                    lComps.scheme = "https"
                    lComps.host = "itunes.apple.com"
                    lComps.path = "/lookup"
                    lComps.queryItems = [
                        URLQueryItem(name: "id", value: "\(artistId)"),
                        URLQueryItem(name: "entity", value: "album"),
                        URLQueryItem(name: "limit", value: "1"),
                        URLQueryItem(name: "country", value: country)
                    ]
                    if let lookupUrl = lComps.url {
                        var lreq = URLRequest(url: lookupUrl)
                        lreq.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                        if let (ldata, _) = try? await session.data(for: lreq),
                           let ljson = try? JSONSerialization.jsonObject(with: ldata) as? [String: Any],
                           let lresults = ljson["results"] as? [[String: Any]],
                           lresults.count > 1,
                           let rawArt = lresults[1]["artworkUrl100"] as? String {
                            artworkUrl = rawArt.replacingOccurrences(of: "100x100bb", with: "600x600bb")
                        }
                    }

                    let info = ArtistStationInfo(
                        artistId: artistId,
                        canonicalName: canonicalName,
                        stationUrl: stationUrl,
                        artworkUrl: artworkUrl
                    )

                    setCachedArtistStation(info, for: clean)
                    if clean.lowercased() != candidate.lowercased() {
                        setCachedArtistStation(info, for: candidate)
                    }
                    return info
                }
            }
        }

        return nil
    }

    public func searchArtistStationUrl(artist: String, storefront: String = "") async -> String? {
        if let info = await resolveArtistStation(artist: artist, storefront: storefront) {
            return info.stationUrl
        }
        return nil
    }

    public func resolveTrackStation(title: String, artist: String = "", storefront: String = "") async -> String? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = "\(cleanTitle.lowercased())|\(cleanArtist.lowercased())"
        if let cached = getCachedTrackStation(for: cacheKey) {
            return cached.stationUrl
        }

        let normT = Self.normalizeQueryText(cleanTitle)
        let normA = Self.normalizeQueryText(cleanArtist)
        var queries: [String] = []
        if !cleanArtist.isEmpty {
            queries.append("\(cleanTitle) \(cleanArtist)")
            if !normT.isEmpty && !normA.isEmpty && (normT != cleanTitle.lowercased() || normA != cleanArtist.lowercased()) {
                queries.append("\(normT) \(normA)")
            }
        }
        if !normT.isEmpty && normT != cleanTitle.lowercased() {
            queries.append(normT)
        }
        queries.append(cleanTitle)

        let primarySf = Self.sanitizedStorefront(storefront, fallback: getUserStorefront())
        var uniqueSfs: [String] = []
        for s in [primarySf, "us", "jp"] where Self.isValidStorefrontCode(s) && !uniqueSfs.contains(s) {
            uniqueSfs.append(s)
        }

        // 1. Search via Apple Music Catalog API with developer token
        if let token = getDeveloperToken() {
            let lang = getPreferredLanguageTag()
            var bestCandidate: (songId: String, title: String, artist: String, sf: String, score: Double)? = nil
            for sf in uniqueSfs {
                if let b = bestCandidate, b.score >= 0.85 { break }
                for q in queries {
                    if let b = bestCandidate, b.score >= 0.85 { break }
                    guard let url = Self.makeAppleMusicAPIURL(
                        path: "/v1/catalog/\(sf)/search",
                        queryItems: [
                            URLQueryItem(name: "term", value: q),
                            URLQueryItem(name: "types", value: "songs"),
                            URLQueryItem(name: "limit", value: "10"),
                            URLQueryItem(name: "l", value: lang)
                        ]
                    ) else { continue }
                    var req = URLRequest(url: url)
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    req.setValue("application/json", forHTTPHeaderField: "Accept")
                    req.setValue(lang, forHTTPHeaderField: "Accept-Language")
                    req.timeoutInterval = 3.0

                    guard let (data, resp) = try? await session.data(for: req),
                          let http = resp as? HTTPURLResponse, http.statusCode == 200,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let results = json["results"] as? [String: Any],
                          let songs = results["songs"] as? [String: Any],
                          let dataArr = songs["data"] as? [[String: Any]] else {
                        continue
                    }

                    for item in dataArr {
                        guard let id = item["id"] as? String,
                              Self.isValidResourceIdentifier(id),
                              let attrs = item["attributes"] as? [String: Any],
                              let cName = attrs["name"] as? String,
                              let cArtist = attrs["artistName"] as? String else { continue }

                        let (score, isMatch) = Self.computeSongSimilarity(
                            queryTitle: cleanTitle,
                            queryArtist: cleanArtist,
                            candidateTitle: cName,
                            candidateArtist: cArtist
                        )
                        if isMatch {
                            if bestCandidate == nil || score > bestCandidate!.score {
                                bestCandidate = (id, cName, cArtist, sf, score)
                            }
                        }
                    }
                }
            }

            if let best = bestCandidate,
               Self.isValidStorefrontCode(best.sf),
               Self.isValidResourceIdentifier(best.songId) {
                var stationUrl: String? = nil
                if let stUrl = Self.makeAppleMusicAPIURL(
                    path: "/v1/catalog/\(best.sf)/songs/\(best.songId)/station",
                    queryItems: [URLQueryItem(name: "l", value: lang)]
                ) {
                    var sreq = URLRequest(url: stUrl)
                    sreq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    sreq.setValue("application/json", forHTTPHeaderField: "Accept")
                    sreq.setValue(lang, forHTTPHeaderField: "Accept-Language")
                    sreq.timeoutInterval = 3.0
                    if let (sdata, sresp) = try? await session.data(for: sreq),
                       let shttp = sresp as? HTTPURLResponse, shttp.statusCode == 200,
                       let sjson = try? JSONSerialization.jsonObject(with: sdata) as? [String: Any],
                       let sArr = sjson["data"] as? [[String: Any]],
                       let sFirst = sArr.first,
                       let sAttrs = sFirst["attributes"] as? [String: Any],
                       let officialUrl = sAttrs["url"] as? String, !officialUrl.isEmpty {
                        stationUrl = officialUrl
                    }
                }

                if stationUrl == nil {
                    stationUrl = "https://music.apple.com/\(best.sf)/station/item/ra.\(best.songId)"
                }

                if let finalUrl = stationUrl {
                    let info = TrackStationInfo(
                        trackId: best.songId,
                        title: best.title,
                        artist: best.artist,
                        stationUrl: finalUrl
                    )
                    setCachedTrackStation(info, for: cacheKey)
                    return finalUrl
                }
            }
        }

        // 2. Fallback to iTunes Store Search API
        for country in uniqueSfs {
            for q in queries {
                var sComps = URLComponents()
                sComps.scheme = "https"
                sComps.host = "itunes.apple.com"
                sComps.path = "/search"
                sComps.queryItems = [
                    URLQueryItem(name: "term", value: q),
                    URLQueryItem(name: "entity", value: "song"),
                    URLQueryItem(name: "limit", value: "10"),
                    URLQueryItem(name: "country", value: country)
                ]
                guard let url = sComps.url else { continue }
                var req = URLRequest(url: url)
                req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                req.timeoutInterval = 3.0

                guard let (data, resp) = try? await session.data(for: req),
                      let http = resp as? HTTPURLResponse, http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [[String: Any]] else {
                    continue
                }

                var bestItunes: (trackId: Int, name: String, artist: String, score: Double)? = nil
                for r in results {
                    guard let tid = r["trackId"] as? Int,
                          tid > 0,
                          let tName = r["trackName"] as? String,
                          let tArtist = r["artistName"] as? String else { continue }
                    let (score, isMatch) = Self.computeSongSimilarity(
                        queryTitle: cleanTitle,
                        queryArtist: cleanArtist,
                        candidateTitle: tName,
                        candidateArtist: tArtist
                    )
                    if isMatch {
                        if bestItunes == nil || score > bestItunes!.score {
                            bestItunes = (tid, tName, tArtist, score)
                        }
                    }
                }

                if let b = bestItunes {
                    let finalUrl = "https://music.apple.com/\(country)/station/item/ra.\(b.trackId)"
                    let info = TrackStationInfo(
                        trackId: "\(b.trackId)",
                        title: b.name,
                        artist: b.artist,
                        stationUrl: finalUrl
                    )
                    setCachedTrackStation(info, for: cacheKey)
                    return finalUrl
                }
            }
        }

        return nil
    }
}
