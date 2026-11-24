import Foundation
import NaturalLanguage

extension NativeMusicCuratorService {

    // MARK: - Dynamic Catalog Genre Resolution

    internal func bestArchetypeForCatalogGenre(_ rawGenre: String) -> SonicArchetype? {
        let g = rawGenre.lowercased()
        guard !g.isEmpty else { return nil }
        let byId = Dictionary(uniqueKeysWithValues: archetypes.map { ($0.id, $0) })

        if g.contains("prog") || g.contains("прог") {
            if g.contains("metal") || g.contains("метал") { return byId["prog_alt_metal"] }
            return byId["prog_rock_70s"]
        }
        if g.contains("metal") || g.contains("метал") || g.contains("hard rock") || g.contains("хард-рок") || g.contains("тяжел") || g.contains("панк") || g.contains("punk") {
            if g.contains("alt") || g.contains("альт") || g.contains("prog") { return byId["prog_alt_metal"] }
            return byId["heavy_metal_hard_rock"] ?? byId["prog_alt_metal"]
        }
        if g.contains("alternative") || g.contains("альтернатив") || g.contains("indie") || g.contains("инди") || g.contains("new wave") || g.contains("post-punk") {
            return byId["alt_rock_postpunk"]
        }
        if g.contains("dance") || g.contains("танц") || g.contains("house") || g.contains("хаус") || g.contains("disco") || g.contains("диско") {
            return byId["french_touch_nudisco"]
        }
        if g.contains("techno") || g.contains("техно") || g.contains("minimal") || g.contains("idm") {
            return byId["deep_dub_techno"]
        }
        if g.contains("downtempo") || g.contains("trip-hop") || g.contains("трип-хоп") || g.contains("lounge") || g.contains("chill") {
            return byId["triphop_downtempo_90s"]
        }
        if g.contains("electronic") || g.contains("электрон") || g.contains("synth") {
            return byId["analog_electro_krautrock"] ?? byId["synthwave_retro_electronic"]
        }
        if g.contains("jazz") || g.contains("джаз") {
            return byId["noir_jazz"]
        }
        if g.contains("classical") || g.contains("классик") || g.contains("ambient") || g.contains("эмбиент") || g.contains("soundtrack") || g.contains("саундтрек") || g.contains("score") {
            return byId["ambient_neoclassical_focus"]
        }
        if g.contains("blues") || g.contains("блюз") {
            return byId["blues_tube_guitar"]
        }
        if g.contains("soul") || g.contains("соул") || g.contains("funk") || g.contains("фанк") || g.contains("r&b") || g.contains("motown") {
            return byId["soul_funk_groove"]
        }
        if g.contains("vocal") || g.contains("вокал") || g.contains("singer") || g.contains("акуст") || g.contains("folk") || g.contains("фолк") || g.contains("country") {
            return byId["audiophile_vocal_acoustic"]
        }
        if g.contains("rock") || g.contains("рок") {
            return byId["alt_rock_postpunk"] ?? byId["prog_rock_70s"]
        }
        return nil
    }

    internal func resolveDynamicCatalogArtistPlan(
        targetArtist: String,
        basePlan: CuratedSessionPlan,
        storefront: String,
        preferEnglish: Bool
    ) async -> CuratedSessionPlan? {
        guard let res = await searchCatalogWithTimeout(query: targetArtist, storefront: storefront, limit: 8) else {
            return nil
        }
        let artists = (res["artists"] as? [[String: Any]]) ?? []
        let albums = (res["albums"] as? [[String: Any]]) ?? []
        let songs = (res["songs"] as? [[String: Any]]) ?? []

        var canonicalArtist = Self.titleCaseArtistName(targetArtist)
        if let firstArtistName = artists.first?["name"] as? String, !firstArtistName.isEmpty {
            canonicalArtist = firstArtistName
        } else if let firstSongArtist = songs.first?["artist"] as? String, !firstSongArtist.isEmpty {
            canonicalArtist = firstSongArtist
        }

        var catalogGenre = ""
        if let g = artists.first?["genre"] as? String, !g.isEmpty {
            catalogGenre = g
        } else if let g = albums.first?["genre"] as? String, !g.isEmpty {
            catalogGenre = g
        } else if let g = songs.first?["genre"] as? String, !g.isEmpty {
            catalogGenre = g
        }

        // Check if canonicalArtist resolved from catalog matches one of our static profiles
        if let staticProfile = findArtistStyleProfile(for: canonicalArtist) {
            let parentArch = archetypes.first(where: { $0.id == staticProfile.archetypeId }) ?? archetypes[0]
            let title = preferEnglish
                ? "In the Style of \(staticProfile.canonicalArtist) • \(staticProfile.styleTitleEn)"
                : "В стиле \(staticProfile.canonicalArtist) • \(staticProfile.styleTitleRu)"
            let subtitle = preferEnglish
                ? (staticProfile.customDescriptionEn ?? parentArch.descriptionEn)
                : (staticProfile.customDescriptionRu ?? parentArch.descriptionRu)
            var tags = ["🎙️ \(staticProfile.canonicalArtist)"]
            for t in (preferEnglish ? parentArch.tagsEn : parentArch.tagsRu) where tags.count < 4 {
                tags.append(t)
            }
            return CuratedSessionPlan(
                prompt: basePlan.prompt,
                title: title,
                subtitle: subtitle,
                tags: tags,
                engineBadge: activeEngineDescription,
                seedQueries: Array(staticProfile.seedQueries.prefix(10)),
                confidenceScore: 0.95
            )
        }

        let matchedArch = bestArchetypeForCatalogGenre(catalogGenre)
        var seedQueries: [String] = [canonicalArtist]

        let canonicalLower = canonicalArtist.lowercased()
        for alb in albums {
            let aName = (alb["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let aArtist = (alb["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let aLower = aName.lowercased()
            guard !aName.isEmpty,
                  aArtist == canonicalLower,
                  !aLower.contains("remix"),
                  !aLower.contains(" - single") else {
                continue
            }
            let q = "\(canonicalArtist) \(aName)"
            if !seedQueries.contains(where: { $0.caseInsensitiveCompare(q) == .orderedSame }) {
                seedQueries.append(q)
            }
            if seedQueries.count >= 3 { break }
        }

        if let arch = matchedArch {
            for pq in arch.seedQueries.shuffled() where seedQueries.count < 10 {
                if !seedQueries.contains(where: { $0.caseInsensitiveCompare(pq) == .orderedSame }) {
                    seedQueries.append(pq)
                }
            }
        } else {
            for bq in basePlan.seedQueries where seedQueries.count < 10 {
                if !seedQueries.contains(where: { $0.caseInsensitiveCompare(bq) == .orderedSame }) {
                    seedQueries.append(bq)
                }
            }
        }

        let styleDescriptor: String
        if let arch = matchedArch {
            styleDescriptor = preferEnglish ? arch.titleEn : arch.titleRu
        } else if !catalogGenre.isEmpty && catalogGenre.lowercased() != "музыка" && catalogGenre.lowercased() != "music" {
            styleDescriptor = catalogGenre
        } else {
            styleDescriptor = preferEnglish ? "AI Sonic Mix" : "Семантический ИИ-микс"
        }

        let title = preferEnglish
            ? "In the Style of \(canonicalArtist) • \(styleDescriptor)"
            : "В стиле \(canonicalArtist) • \(styleDescriptor)"
        let subtitle: String
        if let arch = matchedArch {
            subtitle = preferEnglish ? arch.descriptionEn : arch.descriptionRu
        } else {
            subtitle = preferEnglish
                ? "Curated session inspired by \(canonicalArtist) and kindred artists in the Apple Music catalog."
                : "Семантическая подборка треков \(canonicalArtist) и близких по звучанию артистов из каталога Apple Music."
        }

        var tags: [String] = ["🎙️ \(canonicalArtist)"]
        if !catalogGenre.isEmpty && catalogGenre.lowercased() != "музыка" && catalogGenre.lowercased() != "music" {
            tags.append("🏷️ \(catalogGenre)")
        }
        if let arch = matchedArch {
            for t in (preferEnglish ? arch.tagsEn : arch.tagsRu) where tags.count < 4 {
                if !tags.contains(t) { tags.append(t) }
            }
        }

        return CuratedSessionPlan(
            prompt: basePlan.prompt,
            title: title,
            subtitle: subtitle,
            tags: tags,
            engineBadge: activeEngineDescription,
            seedQueries: Array(seedQueries.prefix(10)),
            confidenceScore: 0.90
        )
    }

    // MARK: - Normalization & NLTagger Entity Extraction

    private static let dedupBracketRegex = try? NSRegularExpression(pattern: "\\s*[\\[\\(].*?[\\]\\)]", options: [])

    internal func normalizeSongTitleForDedup(_ rawTitle: String) -> String {
        var t = rawTitle.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let regex = Self.dedupBracketRegex {
            t = regex.stringByReplacingMatches(in: t, options: [], range: NSRange(location: 0, length: t.utf16.count), withTemplate: "")
        }
        if let dashRange = t.range(of: " - ") {
            t = String(t[..<dashRange.lowerBound])
        }
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        t = t.components(separatedBy: allowed.inverted).joined(separator: " ")
        return t.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }

    internal func normalizeArtistForDedup(_ rawArtist: String) -> String {
        var a = rawArtist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for sep in [" & ", ", ", " feat.", " feat ", " ft.", " with "] {
            if let r = a.range(of: sep) {
                a = String(a[..<r.lowerBound])
            }
        }
        return a.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let nonArtistStopWords: Set<String> = [
        "hi-res", "alac", "flac", "aac", "dac", "ost", "live", "mix", "vip", "rhodes", "fender",
        "fender rhodes", "wurlitzer", "moog", "hammond", "steinway", "stradivarius", "dolby", "atmos",
        "binaural", "vinyl", "lossless", "bit-perfect", "apple music", "warm", "deep", "late", "night",
        "noir", "ambient", "neoclassical", "jazz", "soul", "funk", "synthwave", "techno", "dub",
        "house", "lounge", "bossa", "nova", "bossa nova", "chillhop", "downtempo", "post-rock",
        "post", "rock", "indie", "acoustic", "classical", "cello", "piano", "saxophone", "trumpet",
        "воздушный", "меланхоличный", "гипнотический", "глубокий", "ламповый", "тёплый", "теплый",
        "ночной", "вечерний", "утренний", "кинематографичный", "драйвовый", "камерный", "кристальный",
        "бархатный", "невесомый", "винтажный", "минималистичный", "акустический", "инструментальный",
        "космический", "приглушенный", "приглушённый", "расслабленный", "энергичный", "томный",
        "полуночный", "уютный", "мягкий", "спокойный", "динамичный", "прозрачный", "широкий",
        "стиле", "группы", "гуппы", "групы", "группа", "артиста", "исполнителя", "похоже", "духе", "музыка"
    ]

    internal func extractTokensAndEntities(from text: String) -> (tokens: [String], entities: [String]) {
        var tokens: [String] = []
        var entities: [String] = []

        nlEngineLock.lock()
        let tagger = NLTagger(tagSchemes: [.nameTypeOrLexicalClass, .lemma])
        tagger.string = text

        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameTypeOrLexicalClass, options: options) { tag, tokenRange in
            let word = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard word.count >= 2 else { return true }
            let lowerWord = word.lowercased()
            tokens.append(lowerWord)

            if Self.nonArtistStopWords.contains(lowerWord) {
                return true
            }

            // Ignore the first capitalized Cyrillic word at the very start of the prompt unless it's multi-word
            let isAtStart = (tokenRange.lowerBound == text.startIndex)
            let isAscii = word.utf8.allSatisfy({ $0 < 128 })

            if let tag = tag, (tag == .personalName || tag == .organizationName) {
                if !isAtStart || isAscii || word.contains(" ") {
                    entities.append(word)
                }
            } else if word.first?.isUppercase == true && isAscii && word.count >= 3 && !isAtStart {
                entities.append(word)
            }
            return true
        }
        nlEngineLock.unlock()

        // Merge consecutive Latin words into a single artist entity (e.g. "Pink" + "Floyd" -> "Pink Floyd")
        let mergedEntities = extractLatinArtistPhrases(from: text, fallbackEntities: entities)
        return (tokens, mergedEntities)
    }

    private func extractLatinArtistPhrases(from text: String, fallbackEntities: [String]) -> [String] {
        let hasCyrillic = text.unicodeScalars.contains(where: { $0.value >= 0x0400 && $0.value <= 0x04FF })
        let pattern = hasCyrillic
            ? "\\b([a-zA-Z][a-zA-Z0-9&'/\\-]+(?:\\s+[a-zA-Z][a-zA-Z0-9&'/\\-]+){0,3})\\b"
            : "\\b([A-Z][a-zA-Z0-9&'/\\-]+(?:\\s+[A-Z][a-zA-Z0-9&'/\\-]+){0,3})\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return fallbackEntities
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsRange)
        var results: [String] = []
        for match in matches {
            if let r = Range(match.range(at: 1), in: text) {
                let isSingleWordAtStart = (!hasCyrillic && r.lowerBound == text.startIndex && !text[r].contains(" "))
                if isSingleWordAtStart { continue }
                let rawCandidate = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                let lowerCandidate = rawCandidate.lowercased()
                if rawCandidate.count >= 3 && !Self.nonArtistStopWords.contains(lowerCandidate) {
                    let formatted = Self.titleCaseArtistName(rawCandidate)
                    results.append(formatted)
                }
            }
        }
        return results.isEmpty ? fallbackEntities : results
    }

    internal func cleanPromptForDirectSearch(_ prompt: String) -> String {
        let intent = extractArtistStyleIntent(from: prompt)
        if !intent.targetArtist.isEmpty {
            return Self.titleCaseArtistName(intent.targetArtist)
        }
        var cleaned = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = cleaned.lowercased()
        for prefix in Self.styleActionPrefixes + Self.stylePhrasePrefixes {
            if lower.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return cleaned
    }

    internal func translatePromptToEnglishSemanticSpace(
        lowerPrompt: String,
        tokens: [String],
        excludingArtistName: String = ""
    ) -> String {
        let ruToEnConceptMap: [(ru: String, en: String)] = [
            ("ночн", "late night nocturnal dark"),
            ("вечер", "evening warm sunset"),
            ("утрен", "morning bright fresh groove"),
            ("утро", "morning bright fresh groove"),
            ("дожд", "rainy melancholic atmospheric"),
            ("джаз", "jazz saxophone trumpet double bass cool noir"),
            ("саксофон", "saxophone tenor sax jazz"),
            ("труб", "trumpet muted miles jazz"),
            ("контрабас", "upright double bass acoustic"),
            ("рояль", "grand piano solo keys"),
            ("пианин", "piano solo intimate keys"),
            ("фортепиан", "piano neoclassical keys"),
            ("неоклассик", "neoclassical modern classical piano strings"),
            ("классик", "classical orchestra symphony chamber strings"),
            ("оркестр", "orchestral cinematic strings symphony"),
            ("скрипк", "violin strings chamber"),
            ("виолончел", "cello strings warm"),
            ("эмбиент", "ambient drone space atmospheric calm"),
            ("атмосфер", "atmospheric spacious soundstage ethereal"),
            ("космос", "space ambient cosmic synth"),
            ("фокус", "deep focus study work instrumental concentration"),
            ("работ", "focus work instrumental flow"),
            ("для сна", "sleep calm peaceful ambient quiet"),
            ("спокойн", "calm peaceful relaxing gentle soft"),
            ("расслаб", "chill relax lounge warm"),
            ("меланхол", "melancholic sad emotional introspective"),
            ("грустн", "sad melancholic emotional"),
            ("мрачн", "dark brooding industrial noir"),
            ("нуар", "noir dark late night jazz cinema"),
            ("прог-метал", "progressive metal polyrhythmic heavy art rock tool"),
            ("прог", "progressive rock 1970s concept art rock"),
            ("полиритм", "polyrhythmic odd meter progressive metal"),
            ("психодел", "psychedelic rock space analog"),
            ("хард-рок", "hard rock heavy guitar riff live drums"),
            ("хеви-метал", "heavy metal riff distortion drums"),
            ("хэви-метал", "heavy metal riff distortion drums"),
            ("альт-рок", "alternative rock indie post-punk"),
            ("альтернатив", "alternative rock indie post-punk"),
            ("пост-панк", "post-punk dark wave indie rock"),
            ("постпанк", "post-punk dark wave indie rock"),
            ("шугейз", "shoegaze dream pop reverb guitars"),
            ("дрим-поп", "dream pop ethereal shoegaze"),
            ("краут", "krautrock motorik analog electronic synthesizer"),
            ("рок", "rock guitars live drums"),
            ("пост-рок", "post-rock instrumental crescendo cinematic guitars"),
            ("построк", "post-rock instrumental crescendo cinematic"),
            ("метал", "heavy metal riff distortion drums"),
            ("тяжел", "heavy riff intense powerful"),
            ("индастриал", "industrial metal dark heavy electronic"),
            ("гранж", "grunge 1990s alternative rock distortion"),
            ("инструментал", "instrumental no vocals musicianship"),
            ("акустич", "acoustic unplugged guitar intimate audiophile"),
            ("гитар", "guitar strings acoustic electric"),
            ("блюз", "blues guitar tube amp soulful"),
            ("вокал", "audiophile vocal singer intimate reference"),
            ("женск", "female vocal singer audiophile"),
            ("сцен", "wide soundstage holographic imaging audiophile reference"),
            ("аудиофил", "audiophile reference recording high dynamic range soundstage"),
            ("эталон", "audiophile reference studio master"),
            ("суббас", "deep bass sub-bass groove low end"),
            ("бас", "deep bass sub-bass groove low end"),
            ("грув", "funky groove bass rhythm soul"),
            ("фанк", "funk soul rhythm groove bass"),
            ("соул", "soul warm vocal motown"),
            ("френч-тач", "french touch nu-disco electro funk daft punk"),
            ("диско", "nu-disco french touch dance groove"),
            ("синтвейв", "synthwave retrowave 1980s analog synthesizer"),
            ("синт", "analog synthesizer electronic"),
            ("электрон", "electronic modular synth idm"),
            ("техно", "dub techno minimal deep electronic hypnotic"),
            ("хаус", "deep house organic electronic groove"),
            ("трип-хоп", "trip-hop bristol downtempo dark groove"),
            ("трипхоп", "trip-hop bristol downtempo"),
            ("даунтемпо", "downtempo chillout lounge"),
            ("лоу-фай", "lo-fi chillhop beats study"),
            ("lofi", "lo-fi chillhop beats"),
            ("босса", "bossa nova brazilian acoustic jazz"),
            ("кинематограф", "cinematic film score soundtrack"),
            ("саундтрек", "soundtrack film score orchestral"),
            ("60", "1960s sixties vintage analog"),
            ("70", "1970s seventies classic analog tape"),
            ("80", "1980s eighties synth retro"),
            ("90", "1990s nineties golden era"),
            ("винил", "warm analog vinyl tape saturation")
        ]

        var mappedParts: [String] = []
        for item in ruToEnConceptMap {
            if lowerPrompt.contains(item.ru) {
                mappedParts.append(item.en)
            }
        }
        let excludedWords = Set(
            excludingArtistName
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
        let styleStopWordsEn: Set<String> = ["in", "the", "style", "of", "band", "music", "like", "similar", "to", "songs", "tracks", "artists"]
        let asciiWords = tokens.filter { tok in
            tok.utf8.allSatisfy({ c in c < 128 }) && !excludedWords.contains(tok) && !styleStopWordsEn.contains(tok)
        }
        if !asciiWords.isEmpty {
            mappedParts.append(asciiWords.joined(separator: " "))
        }
        return mappedParts.joined(separator: " ")
    }
}
