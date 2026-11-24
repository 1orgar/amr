//
//  DigitalBookletService+Wikipedia.swift
//  AppleMusicRemoteMac
//
//  Wikipedia album history & track-by-track commentary extraction with URLComponents query encoding.
//

import Foundation

extension DigitalBookletService {

    // MARK: - Wikipedia Album & Track-by-Track Commentary Fetcher

    internal struct WikiBookletNotes: Sendable {
        var albumHistoryParagraphs: [String] = []
        var trackCommentary: [String: String] = [:]
    }

    internal func fetchWikipediaAlbumAndTrackNotes(
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

    internal func fetchBestWikipediaAlbumExtract(album: String, artist: String, lang: String) async -> String {
        let cleanLang = lang.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidWikipediaLang(cleanLang) else { return "" }

        let cleanAlbum = album
            .replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\[.*?\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAlbum.isEmpty else { return "" }

        let query = "\"\(cleanAlbum)\" \"\(artist)\""
        var searchComps = URLComponents()
        searchComps.scheme = "https"
        searchComps.host = "\(cleanLang).wikipedia.org"
        searchComps.path = "/w/api.php"
        searchComps.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: query),
            URLQueryItem(name: "srlimit", value: "6"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let searchUrl = searchComps.url else {
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

        guard let pageTitle = chosenTitle, !pageTitle.isEmpty else {
            return ""
        }

        var extComps = URLComponents()
        extComps.scheme = "https"
        extComps.host = "\(cleanLang).wikipedia.org"
        extComps.path = "/w/api.php"
        extComps.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "prop", value: "extracts"),
            URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "titles", value: pageTitle),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let extUrl = extComps.url else {
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

    internal static func extractAlbumHistoryParagraphs(from wikiExtract: String) -> [String] {
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

    internal static func normalizeForMatching(_ text: String) -> String {
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
}
