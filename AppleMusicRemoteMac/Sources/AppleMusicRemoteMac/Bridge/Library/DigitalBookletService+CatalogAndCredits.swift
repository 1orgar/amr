//
//  DigitalBookletService+CatalogAndCredits.swift
//  AppleMusicRemoteMac
//
//  Apple Music Catalog metadata resolution and MusicBrainz recording/liner-notes credits.
//

import Foundation

extension DigitalBookletService {

    // MARK: - Apple Music Catalog + MusicBrainz + Wikipedia Comprehensive Fetcher

    internal func fetchAlbumCatalogMetadata(
        album: String,
        artist: String,
        albumId: String?
    ) async -> AlbumCatalogMetadata {
        let trimmedAlbumId = (albumId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var meta = AlbumCatalogMetadata(
            albumId: Self.isValidSafeIdentifier(trimmedAlbumId) ? trimmedAlbumId : "",
            albumName: album,
            artistName: artist
        )

        if PlaybackRouter.shared.isTestingEnvironment {
            return meta
        }

        guard let devToken = MusicKitManager.shared.getDeveloperToken() else {
            return meta
        }

        let rawSf = MusicKitManager.shared.getUserStorefront().lowercased()
        let sf = Self.isValidStorefront(rawSf) ? rawSf : "us"
        let lang = MusicKitManager.shared.getPreferredLanguageTag()

        // 1. Resolve Album ID if not provided
        if meta.albumId.isEmpty {
            let cleanAlbum = album
                .replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s*\[.*?\]"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let searchTerm = "\(cleanAlbum.isEmpty ? album : cleanAlbum) \(artist)".trimmingCharacters(in: .whitespacesAndNewlines)
            var searchComps = URLComponents()
            searchComps.scheme = "https"
            searchComps.host = "api.music.apple.com"
            searchComps.path = "/v1/catalog/\(sf)/search"
            searchComps.queryItems = [
                URLQueryItem(name: "term", value: searchTerm),
                URLQueryItem(name: "types", value: "albums"),
                URLQueryItem(name: "limit", value: "3"),
                URLQueryItem(name: "l", value: lang)
            ]
            if let url = searchComps.url {
                var req = URLRequest(url: url)
                req.timeoutInterval = 4.0
                req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                if let (data, resp) = try? await session.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let results = json["results"] as? [String: Any],
                   let albumsObj = results["albums"] as? [String: Any],
                   let albumsData = albumsObj["data"] as? [[String: Any]],
                   let first = albumsData.first,
                   let candidateId = first["id"] as? String,
                   Self.isValidSafeIdentifier(candidateId) {
                    meta.albumId = candidateId
                }
            }
        }

        guard !meta.albumId.isEmpty, Self.isValidSafeIdentifier(meta.albumId) else {
            return meta
        }

        // 2. Query Apple Music Catalog in both user language and en-US to capture full editorial notes
        let queries: [(sf: String, lang: String)] = lang.lowercased().hasPrefix("en")
            ? [(sf, lang), ("us", "en-US")]
            : [(sf, lang), (sf, "en-US"), ("us", "en-US")]

        var localizedStandard = ""
        var englishStandard = ""

        for (idx, q) in queries.enumerated() {
            guard Self.isValidStorefront(q.sf), Self.isValidSafeIdentifier(meta.albumId) else { continue }
            var albumComps = URLComponents()
            albumComps.scheme = "https"
            albumComps.host = "api.music.apple.com"
            albumComps.path = "/v1/catalog/\(q.sf)/albums/\(meta.albumId)"
            albumComps.queryItems = [URLQueryItem(name: "l", value: q.lang)]
            guard let url = albumComps.url else { continue }

            var req = URLRequest(url: url)
            req.timeoutInterval = 4.5
            req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")

            guard let (data, resp) = try? await session.data(for: req),
                  let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArr = json["data"] as? [[String: Any]],
                  let albumObj = dataArr.first,
                  let attrs = albumObj["attributes"] as? [String: Any] else {
                continue
            }

            if idx == 0 || meta.tracks.isEmpty {
                meta.albumName = (attrs["name"] as? String) ?? meta.albumName
                meta.artistName = (attrs["artistName"] as? String) ?? meta.artistName
                meta.releaseDate = (attrs["releaseDate"] as? String) ?? meta.releaseDate
                meta.recordLabel = (attrs["recordLabel"] as? String) ?? meta.recordLabel
                meta.copyright = (attrs["copyright"] as? String) ?? meta.copyright
                if let genres = attrs["genreNames"] as? [String] {
                    var uniqueGenres: [String] = []
                    for g in genres {
                        let cleanG = g.trimmingCharacters(in: .whitespacesAndNewlines)
                        let lowerG = cleanG.lowercased()
                        if lowerG != "музыка" && lowerG != "music" && !cleanG.isEmpty && !uniqueGenres.contains(where: { $0.caseInsensitiveCompare(cleanG) == .orderedSame }) {
                            uniqueGenres.append(cleanG)
                        }
                    }
                    meta.genre = uniqueGenres.joined(separator: " • ")
                }
                meta.isMasteredForItunes = (attrs["isMasteredForItunes"] as? Bool) ?? false
                meta.audioTraits = (attrs["audioTraits"] as? [String]) ?? []

                if let pdfUrl = (attrs["bookletUrl"] as? String) ?? (attrs["digitalBookletUrl"] as? String),
                   let parsedPdf = URL(string: pdfUrl),
                   ArtworkService.isAllowedRemoteArtworkURL(parsedPdf) {
                    meta.directPdfUrl = pdfUrl
                }

                if let artObj = attrs["artwork"] as? [String: Any],
                   let tmpl = artObj["url"] as? String {
                    meta.artworkUrl = tmpl
                        .replacingOccurrences(of: "{w}x{h}", with: "1000x1000")
                        .replacingOccurrences(of: "{w}", with: "1000")
                        .replacingOccurrences(of: "{h}", with: "1000")
                        .replacingOccurrences(of: "{f}", with: "jpg")
                }

                if let rels = albumObj["relationships"] as? [String: Any],
                   let trksObj = rels["tracks"] as? [String: Any],
                   let trksData = trksObj["data"] as? [[String: Any]] {
                    meta.tracks = trksData.enumerated().compactMap { tIdx, item in
                        guard let tAttrs = item["attributes"] as? [String: Any] else { return nil }
                        let title = tAttrs["name"] as? String ?? ""
                        guard !title.isEmpty else { return nil }
                        let tArtist = tAttrs["artistName"] as? String ?? meta.artistName
                        let composer = tAttrs["composerName"] as? String ?? ""
                        let durMs = tAttrs["durationInMillis"] as? Double ?? 0
                        let num = tIdx + 1
                        let disc = tAttrs["discNumber"] as? Int ?? 1
                        let isrc = tAttrs["isrc"] as? String ?? ""
                        let isADM = (tAttrs["isAppleDigitalMaster"] as? Bool) ?? meta.isMasteredForItunes
                        let variants = (tAttrs["audioVariants"] as? [String]) ?? []
                        var badgeParts: [String] = []
                        if isADM { badgeParts.append("Apple Digital Master") }
                        if variants.contains(where: { $0.lowercased().contains("hi-res") }) {
                            badgeParts.append("Hi-Res Lossless")
                        } else if variants.contains(where: { $0.lowercased().contains("lossless") }) {
                            badgeParts.append("Lossless")
                        }
                        if variants.contains(where: { $0.lowercased().contains("atmos") }) {
                            badgeParts.append("Dolby Atmos")
                        }
                        return CatalogTrackCredit(
                            number: num,
                            discNumber: disc,
                            title: title,
                            artist: tArtist,
                            composer: composer,
                            durationSeconds: durMs / 1000.0,
                            isrc: isrc,
                            audioBadge: badgeParts.joined(separator: " • ")
                        )
                    }
                }
            }

            if let notes = attrs["editorialNotes"] as? [String: Any] {
                if let std = notes["standard"] as? String, !std.isEmpty {
                    let cleaned = Self.stripHtmlTags(std)
                    if q.lang.lowercased().hasPrefix("en") {
                        if englishStandard.isEmpty { englishStandard = cleaned }
                    } else {
                        if localizedStandard.isEmpty { localizedStandard = cleaned }
                    }
                }
                if let sh = notes["short"] as? String, !sh.isEmpty, meta.editorialShort.isEmpty {
                    meta.editorialShort = Self.stripHtmlTags(sh)
                }
            }

            if !localizedStandard.isEmpty && !englishStandard.isEmpty && !meta.tracks.isEmpty {
                break
            }
        }

        meta.editorialStandard = !localizedStandard.isEmpty ? localizedStandard : englishStandard

        // 3. Concurrently enrich with MusicBrainz full recording credits + Wikipedia album & track-by-track descriptions
        let targetAlbum = meta.albumName.isEmpty ? album : meta.albumName
        let targetArtist = meta.artistName.isEmpty ? artist : meta.artistName
        let currentTracks = meta.tracks
        let engFallback = englishStandard

        async let mbTask = fetchMusicBrainzTrackCredits(
            album: targetAlbum,
            artist: targetArtist,
            expectedTrackCount: currentTracks.count
        )
        async let wikiTask = fetchWikipediaAlbumAndTrackNotes(
            album: targetAlbum,
            artist: targetArtist,
            tracks: currentTracks,
            englishEditorialFallback: engFallback
        )

        let (mbCredits, wikiNotes) = await (mbTask, wikiTask)

        if !wikiNotes.albumHistoryParagraphs.isEmpty {
            meta.albumHistoryParagraphs = wikiNotes.albumHistoryParagraphs
        } else if !englishStandard.isEmpty && englishStandard != meta.editorialStandard {
            meta.albumHistoryParagraphs = englishStandard
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        if !mbCredits.releaseStudios.isEmpty {
            meta.recordingStudios = mbCredits.releaseStudios
        }

        // Merge per-track commentary & studio/musician credits into meta.tracks
        for i in 0..<meta.tracks.count {
            let t = meta.tracks[i]
            let normTitle = Self.normalizeTrackKey(t.title)

            if let comm = wikiNotes.trackCommentary[normTitle], !comm.isEmpty {
                meta.tracks[i].commentary = comm
            }

            if let mbTrack = mbCredits.byTrackNumber[t.number] ?? mbCredits.byNormalizedTitle[normTitle] {
                if meta.tracks[i].composer.isEmpty && !mbTrack.writers.isEmpty {
                    meta.tracks[i].composer = mbTrack.writers.joined(separator: ", ")
                } else if !mbTrack.writers.isEmpty {
                    var existing = meta.tracks[i].composer
                    let normExisting = existing.lowercased()
                        .replacingOccurrences(of: ",", with: "")
                        .replacingOccurrences(of: ".", with: "")
                        .replacingOccurrences(of: "‐", with: "-")
                    for w in mbTrack.writers {
                        let normW = w.lowercased()
                            .replacingOccurrences(of: ",", with: "")
                            .replacingOccurrences(of: ".", with: "")
                            .replacingOccurrences(of: "‐", with: "-")
                        if !normExisting.contains(normW) && !existing.localizedCaseInsensitiveContains(w) {
                            existing += ", \(w)"
                        }
                    }
                    meta.tracks[i].composer = existing
                }
                meta.tracks[i].producers = mbTrack.producers
                meta.tracks[i].vocals = mbTrack.vocals
                meta.tracks[i].instruments = mbTrack.instruments
                meta.tracks[i].samples = mbTrack.samples
                meta.tracks[i].studios = mbTrack.studios
            }
        }

        // 4. Fetch cover artwork bytes if we have booklet content to render
        let hasBookletContent = !meta.editorialStandard.isEmpty
            || !meta.editorialShort.isEmpty
            || !meta.albumHistoryParagraphs.isEmpty
            || meta.tracks.contains { !$0.commentary.isEmpty || !$0.instruments.isEmpty || !$0.vocals.isEmpty || !$0.producers.isEmpty }

        if hasBookletContent {
            if let localArt = MusicBridge.shared.getCurrentTrackArtwork(), !localArt.isEmpty,
               let stTrack = MusicBridge.shared.getPlayerStatus().track,
               stTrack.album.lowercased() == album.lowercased() {
                meta.artworkData = localArt
            } else if !meta.artworkUrl.isEmpty,
                      let url = URL(string: meta.artworkUrl),
                      ArtworkService.isAllowedRemoteArtworkURL(url) {
                if let cached = ArtworkDiskCache.shared.get(key: meta.artworkUrl) {
                    meta.artworkData = cached
                } else if let (imgData, resp) = try? await session.data(from: url),
                          imgData.count <= 10 * 1024 * 1024,
                          let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    ArtworkDiskCache.shared.set(key: meta.artworkUrl, data: imgData)
                    meta.artworkData = imgData
                }
            }
        }

        return meta
    }

    // MARK: - MusicBrainz Full Liner Notes & Musician Credits Fetcher

    internal struct MBTrackCreditsResult: Sendable {
        var writers: [String] = []
        var producers: [String] = []
        var vocals: [String] = []
        var instruments: [String] = []
        var samples: [String] = []
        var studios: [String] = []
    }

    internal struct MBAlbumCreditsResult: Sendable {
        var byTrackNumber: [Int: MBTrackCreditsResult] = [:]
        var byNormalizedTitle: [String: MBTrackCreditsResult] = [:]
        var releaseStudios: [String] = []
    }

    internal func fetchMusicBrainzTrackCredits(
        album: String,
        artist: String,
        expectedTrackCount: Int
    ) async -> MBAlbumCreditsResult {
        var result = MBAlbumCreditsResult()
        let cleanAlbum = album
            .replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\[.*?\]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAlbum.isEmpty else { return result }

        let queryStr = "release:\"\(cleanAlbum)\" AND artist:\"\(artist)\""
        var searchComps = URLComponents()
        searchComps.scheme = "https"
        searchComps.host = "musicbrainz.org"
        searchComps.path = "/ws/2/release"
        searchComps.queryItems = [
            URLQueryItem(name: "query", value: queryStr),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "fmt", value: "json")
        ]
        guard let searchUrl = searchComps.url else {
            return result
        }

        var searchReq = URLRequest(url: searchUrl)
        searchReq.timeoutInterval = 4.5
        searchReq.setValue("AppleMusicRemoteMac/2.6 (https://github.com/ksholokhov/amr)", forHTTPHeaderField: "User-Agent")
        searchReq.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (sData, sResp) = try? await session.data(for: searchReq),
              let sHttp = sResp as? HTTPURLResponse, sHttp.statusCode == 200,
              let sJson = try? JSONSerialization.jsonObject(with: sData) as? [String: Any],
              let releases = sJson["releases"] as? [[String: Any]], !releases.isEmpty else {
            return result
        }

        // Pick best matching release (prefer exact track count or closest official release)
        let bestRelease = releases.min { a, b in
            let aCount = a["track-count"] as? Int ?? 0
            let bCount = b["track-count"] as? Int ?? 0
            let aDiff = expectedTrackCount > 0 ? abs(aCount - expectedTrackCount) : 0
            let bDiff = expectedTrackCount > 0 ? abs(bCount - expectedTrackCount) : 0
            if aDiff != bDiff { return aDiff < bDiff }
            let aScore = a["score"] as? Int ?? 0
            let bScore = b["score"] as? Int ?? 0
            return aScore > bScore
        } ?? releases[0]

        guard let releaseId = bestRelease["id"] as? String,
              Self.isValidSafeIdentifier(releaseId) else {
            return result
        }

        var relComps = URLComponents()
        relComps.scheme = "https"
        relComps.host = "musicbrainz.org"
        relComps.path = "/ws/2/release/\(releaseId)"
        relComps.queryItems = [
            URLQueryItem(
                name: "inc",
                value: "recordings+artist-credits+recording-level-rels+artist-rels+work-rels+work-level-rels+place-rels+labels"
            ),
            URLQueryItem(name: "fmt", value: "json")
        ]
        guard let relUrl = relComps.url else {
            return result
        }

        var relReq = URLRequest(url: relUrl)
        relReq.timeoutInterval = 5.0
        relReq.setValue("AppleMusicRemoteMac/2.6 (https://github.com/ksholokhov/amr)", forHTTPHeaderField: "User-Agent")
        relReq.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (rData, rResp) = try? await session.data(for: relReq),
              let rHttp = rResp as? HTTPURLResponse, rHttp.statusCode == 200,
              let rJson = try? JSONSerialization.jsonObject(with: rData) as? [String: Any],
              let mediaArr = rJson["media"] as? [[String: Any]] else {
            return result
        }

        if let relRels = rJson["relations"] as? [[String: Any]] {
            for r in relRels {
                if let place = r["place"] as? [String: Any],
                   let pName = place["name"] as? String, !pName.isEmpty,
                   !result.releaseStudios.contains(pName) {
                    result.releaseStudios.append(pName)
                }
            }
        }

        var globalTrackIndex = 0
        for medium in mediaArr {
            guard let tracksArr = medium["tracks"] as? [[String: Any]] else { continue }
            for trk in tracksArr {
                globalTrackIndex += 1
                let tNum = (trk["position"] as? Int) ?? globalTrackIndex
                let tTitle = (trk["title"] as? String) ?? ""
                guard let rec = trk["recording"] as? [String: Any] else { continue }

                var tc = MBTrackCreditsResult()
                var instByArtist: [String: [String]] = [:]
                var instArtistOrder: [String] = []
                var vocalByArtist: [String: [String]] = [:]
                var vocalArtistOrder: [String] = []
                var prodByArtist: [String: [String]] = [:]
                var prodArtistOrder: [String] = []

                func addGrouped(_ dict: inout [String: [String]], _ order: inout [String], artist: String, role: String) {
                    let cleanA = artist.replacingOccurrences(of: "‐", with: "-")
                    if dict[cleanA] == nil {
                        dict[cleanA] = []
                        order.append(cleanA)
                    }
                    if !role.isEmpty && !(dict[cleanA]?.contains(role) ?? false) {
                        dict[cleanA]?.append(role)
                    }
                }

                let relations = (rec["relations"] as? [[String: Any]]) ?? []
                for rel in relations {
                    let rType = (rel["type"] as? String ?? "").lowercased()
                    let rawAttrs = (rel["attributes"] as? [String]) ?? []
                    let translatedAttrs = rawAttrs.compactMap { a -> String? in
                        let clean = a.trimmingCharacters(in: .whitespacesAndNewlines)
                        if clean.isEmpty || clean == "co" || clean == "additional" { return nil }
                        return Self.translateMusicBrainzAttribute(clean)
                    }

                    if let artObj = rel["artist"] as? [String: Any],
                       let aName = artObj["name"] as? String, !aName.isEmpty {
                        let isEn = AMRLocalization.isEnglish
                        if rType == "instrument" {
                            let roles = translatedAttrs.isEmpty ? [isEn ? "instruments" : "инструменты"] : translatedAttrs
                            for r in roles {
                                addGrouped(&instByArtist, &instArtistOrder, artist: aName, role: r)
                            }
                        } else if rType == "vocal" {
                            let roles = translatedAttrs.isEmpty ? [""] : translatedAttrs
                            for r in roles {
                                addGrouped(&vocalByArtist, &vocalArtistOrder, artist: aName, role: r)
                            }
                        } else if rType == "producer" || rType == "co-producer" {
                            addGrouped(&prodByArtist, &prodArtistOrder, artist: aName, role: isEn ? "producer" : "продюсер")
                        } else if rType == "conductor" {
                            addGrouped(&prodByArtist, &prodArtistOrder, artist: aName, role: isEn ? "conductor" : "дирижёр")
                        } else if rType == "arranger" || rType == "instrument arranger" || rType == "orchestrator" {
                            addGrouped(&prodByArtist, &prodArtistOrder, artist: aName, role: isEn ? "arranger" : "аранжировка")
                        } else if rType == "vocal arranger" {
                            addGrouped(&prodByArtist, &prodArtistOrder, artist: aName, role: isEn ? "vocal arranger" : "аранжировка вокала")
                        } else if rType == "recording" || rType == "engineer" || rType == "audio" {
                            addGrouped(&prodByArtist, &prodArtistOrder, artist: aName, role: isEn ? "recording engineer" : "инженер записи")
                        } else if rType == "mix" {
                            addGrouped(&prodByArtist, &prodArtistOrder, artist: aName, role: isEn ? "mixing" : "сведение")
                        } else if rType == "mastering" {
                            addGrouped(&prodByArtist, &prodArtistOrder, artist: aName, role: isEn ? "mastering" : "мастеринг")
                        } else if rType == "programming" {
                            addGrouped(&prodByArtist, &prodArtistOrder, artist: aName, role: isEn ? "programming" : "программирование")
                        }
                    } else if let placeObj = rel["place"] as? [String: Any],
                              let pName = placeObj["name"] as? String, !pName.isEmpty {
                        if !tc.studios.contains(pName) {
                            tc.studios.append(pName)
                        }
                    } else if let workObj = rel["work"] as? [String: Any],
                              let workRels = workObj["relations"] as? [[String: Any]] {
                        let isEn = AMRLocalization.isEnglish
                        for wr in workRels {
                            let wType = (wr["type"] as? String ?? "").lowercased()
                            let wDir = (wr["direction"] as? String ?? "").lowercased()
                            if let wArt = wr["artist"] as? [String: Any],
                               let wName = (wArt["name"] as? String)?.replacingOccurrences(of: "‐", with: "-"),
                               !wName.isEmpty {
                                if ["writer", "composer", "lyricist", "librettist"].contains(wType) {
                                    if !tc.writers.contains(wName) {
                                        tc.writers.append(wName)
                                    }
                                } else if wType == "vocal arranger" {
                                    addGrouped(&prodByArtist, &prodArtistOrder, artist: wName, role: isEn ? "vocal arranger" : "аранжировка вокала")
                                } else if wType == "arranger" || wType == "instrument arranger" {
                                    addGrouped(&prodByArtist, &prodArtistOrder, artist: wName, role: isEn ? "arranger" : "аранжировка")
                                }
                            } else if let quotedWork = wr["work"] as? [String: Any],
                                      let qTitle = quotedWork["title"] as? String, !qTitle.isEmpty,
                                      wDir == "forward",
                                      ["musical quotation", "based on", "medley"].contains(wType) {
                                if !tc.samples.contains(qTitle) {
                                    tc.samples.append("«\(qTitle)»")
                                }
                            }
                        }
                    }
                }

                tc.instruments = instArtistOrder.map { a in
                    let roles = instByArtist[a] ?? []
                    return roles.isEmpty ? a : "\(a) (\(roles.joined(separator: ", ")))"
                }
                tc.vocals = vocalArtistOrder.map { a in
                    let roles = (vocalByArtist[a] ?? []).filter { !$0.isEmpty }
                    return roles.isEmpty ? a : "\(a) (\(roles.joined(separator: ", ")))"
                }
                tc.producers = prodArtistOrder.map { a in
                    let roles = (prodByArtist[a] ?? []).filter { !$0.isEmpty }
                    return roles.isEmpty ? a : "\(a) (\(roles.joined(separator: ", ")))"
                }

                result.byTrackNumber[tNum] = tc
                let normT = Self.normalizeTrackKey(tTitle)
                if !normT.isEmpty {
                    result.byNormalizedTitle[normT] = tc
                }
            }
        }

        return result
    }

    internal static func translateMusicBrainzAttribute(_ attr: String) -> String {
        if AMRLocalization.isEnglish {
            let enMap: [String: String] = [
                "drums (drum set)": "drums",
                "rhodes piano": "Fender Rhodes electric piano",
                "wurlitzer electric piano": "Wurlitzer electric piano",
                "hammond organ": "Hammond organ",
                "ondes martenot": "Ondes Martenot",
                "horncello": "French horn",
                "french horn": "French horn"
            ]
            return enMap[attr.lowercased()] ?? attr
        }
        let map: [String: String] = [
            "guitar": "гитара",
            "electric guitar": "электрогитара",
            "acoustic guitar": "акустическая гитара",
            "bass guitar": "бас-гитара",
            "bass": "бас",
            "double bass": "контрабас",
            "synth bass": "бас-синтезатор",
            "drums (drum set)": "ударные",
            "drums": "ударные",
            "drum machine": "драм-машина",
            "percussion": "перкуссия",
            "keyboard": "клавишные",
            "synthesizer": "синтезатор",
            "modular synthesizer": "модульный синтезатор",
            "piano": "фортепиано",
            "electric piano": "электропианино",
            "rhodes piano": "электропианино Fender Rhodes",
            "wurlitzer electric piano": "электропианино Wurlitzer",
            "organ": "орган",
            "hammond organ": "орган Хаммонда",
            "pedal steel guitar": "педал-стил-гитара",
            "lap steel guitar": "лэп-стил-гитара",
            "ondes martenot": "волны Мартено",
            "other instruments": "дополнительные инструменты",
            "strings": "струнные",
            "violin": "скрипка",
            "viola": "альт",
            "cello": "виолончель",
            "trumpet": "труба",
            "trombone": "тромбон",
            "saxophone": "саксофон",
            "tenor saxophone": "тенор-саксофон",
            "alto saxophone": "альт-саксофон",
            "flute": "флейта",
            "harp": "арфа",
            "horncello": "валторна",
            "french horn": "валторна",
            "timpani": "литавры",
            "vocoder": "вокодер",
            "talkbox": "ток-бокс",
            "sampler": "сэмплер",
            "turntables": "вертушки",
            "lead vocals": "ведущий вокал",
            "background vocals": "бэк-вокал",
            "spoken vocals": "монолог / речитатив",
            "choir vocals": "хор",
            "vocals": "вокал",
            "solo": "соло"
        ]
        return map[attr.lowercased()] ?? attr
    }
}
