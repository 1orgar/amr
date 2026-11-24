import Foundation

extension NativeMusicCuratorService {

    // MARK: - Stage 2: NaturalLanguage 512-D NLEmbedding, Artist Style Graph & NLTagger Engine

    public func buildNaturalLanguagePlan(for prompt: String, preferEnglish: Bool = false) -> CuratedSessionPlan {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmedPrompt.lowercased()

        // 0. Detect "в стиле [группы/гуппы] <Artist>" / "как у <Artist>" / "похоже на <Artist>" intent
        let styleIntent = extractArtistStyleIntent(from: trimmedPrompt)

        // If user is mid-typing an incomplete style prefix (e.g. "в стиле", "в стиле гуппы", "как у") with no subject yet,
        // return a neutral prompt plan instead of matching a random archetype via embedding noise.
        if styleIntent.isIncompletePrefixOnly {
            let fallbackArch = archetypes[0]
            return CuratedSessionPlan(
                prompt: prompt,
                title: preferEnglish ? "AI Sonic Selection" : "AI-Подборка по стилю и артисту",
                subtitle: preferEnglish
                    ? "Enter an artist, band, or sonic mood to curate a matching session."
                    : "Введите название группы, артиста или описание звучания для подбора треков.",
                tags: preferEnglish ? ["✨ Neural 512-D", "🎚️ Lossless Priority"] : ["✨ Neural 512-D", "🎚️ Lossless Приоритет"],
                engineBadge: activeEngineDescription,
                seedQueries: Array(fallbackArch.seedQueries.prefix(6)),
                confidenceScore: 0.90
            )
        }

        // Check if targetArtist (or the prompt itself) matches a known ArtistStyleProfile
        let matchedArtistProfile: ArtistStyleProfile? = {
            if !styleIntent.targetArtist.isEmpty,
               let prof = findArtistStyleProfile(for: styleIntent.targetArtist) {
                return prof
            }
            return findArtistStyleProfileInPrompt(lowerPrompt: lower)
        }()

        // Pure artist-style request (e.g. "в стиле гуппы tool", "в стиле kraftwerk", "похоже на daft punk", or just "tool")
        let hasMoodContext = styleIntent.moodContext.count >= 4
        if let profile = matchedArtistProfile, !hasMoodContext {
            let parentArch = archetypes.first(where: { $0.id == profile.archetypeId }) ?? archetypes[0]
            let title = preferEnglish
                ? "In the Style of \(profile.canonicalArtist) • \(profile.styleTitleEn)"
                : "В стиле \(profile.canonicalArtist) • \(profile.styleTitleRu)"
            let subtitle = preferEnglish
                ? (profile.customDescriptionEn ?? parentArch.descriptionEn)
                : (profile.customDescriptionRu ?? parentArch.descriptionRu)

            var tags: [String] = ["🎙️ \(profile.canonicalArtist)"]
            let baseTags = preferEnglish ? parentArch.tagsEn : parentArch.tagsRu
            for t in baseTags where tags.count < 4 {
                if !tags.contains(t) { tags.append(t) }
            }

            // Keep top 2 anchor queries for the artist at the front, shuffle peer queries for variety
            let anchors = Array(profile.seedQueries.prefix(2))
            let peers = Array(profile.seedQueries.dropFirst(2)).shuffled()
            let queries = Array((anchors + peers).prefix(10))

            return CuratedSessionPlan(
                prompt: prompt,
                title: title,
                subtitle: subtitle,
                tags: tags,
                engineBadge: activeEngineDescription,
                seedQueries: queries,
                confidenceScore: 0.96
            )
        }

        // 1. Extract tokens, lemmas, and named entities using NLTagger (serialized via nlEngineLock)
        var (tokens, extractedEntities) = extractTokensAndEntities(from: trimmedPrompt)
        if let profile = matchedArtistProfile {
            if !extractedEntities.contains(where: { $0.caseInsensitiveCompare(profile.canonicalArtist) == .orderedSame }) {
                extractedEntities.insert(profile.canonicalArtist, at: 0)
            }
        } else if !styleIntent.targetArtist.isEmpty {
            let displayArtist = Self.titleCaseArtistName(styleIntent.targetArtist)
            if !extractedEntities.contains(where: { $0.caseInsensitiveCompare(displayArtist) == .orderedSame }) {
                extractedEntities.insert(displayArtist, at: 0)
            }
        }

        // 2. Translate Russian musical/mood tokens into English semantic space for 512-D NLEmbedding comparison
        let semanticSourceText = hasMoodContext ? styleIntent.moodContext.lowercased() : lower
        let translatedEnPrompt = translatePromptToEnglishSemanticSpace(
            lowerPrompt: semanticSourceText,
            tokens: tokens,
            excludingArtistName: styleIntent.targetArtist.lowercased()
        )

        // 3. Precompute normalized vectors for the prompt ONCE (instead of inside the archetype loop)
        let promptSentVec = translatedEnPrompt.isEmpty ? nil : normalizedSentenceVector(for: translatedEnPrompt)
        let enTokens = translatedEnPrompt
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
        var promptWordVecs: [(token: String, vec: [Double])] = []
        for tok in enTokens.prefix(6) {
            if let wv = normalizedWordVector(for: tok) {
                promptWordVecs.append((tok, wv))
            }
        }

        let promptWordSet = Set(
            lower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        )
        let translatedWordSet = Set(enTokens)

        // 4. Score all Sonic Archetypes using hybrid:
        //    (a) Bilingual keyword & stem overlap + ArtistStyleProfile archetype boost
        //    (b) 512-dimensional NLEmbedding sentence cosine similarity (strictly gated against background noise)
        //    (c) Word embedding neighbor proximity
        var scored: [(archetype: SonicArchetype, score: Double, keywordScore: Double)] = []

        for arch in archetypes {
            var keywordScore: Double = 0.0
            var embeddingScore: Double = 0.0

            if let profile = matchedArtistProfile, profile.archetypeId == arch.id {
                keywordScore += 4.2
            }

            // (a) Direct Russian & English keyword/stem match
            for kwRu in arch.keywordsRu {
                if kwRu.count <= 3 {
                    if promptWordSet.contains(kwRu) {
                        keywordScore += 1.6
                    }
                } else if lower.contains(kwRu) {
                    keywordScore += (kwRu.count >= 5) ? 2.4 : 1.7
                }
            }
            for kwEn in arch.keywordsEn {
                if kwEn.contains(" ") {
                    if lower.contains(kwEn) || translatedEnPrompt.contains(kwEn) {
                        keywordScore += 2.6
                    }
                } else if kwEn.count <= 4 {
                    if promptWordSet.contains(kwEn) || translatedWordSet.contains(kwEn) {
                        keywordScore += 1.8
                    }
                } else if lower.contains(kwEn) || translatedEnPrompt.contains(kwEn) {
                    keywordScore += 2.2
                }
            }

            // Also check if any seedQuery artist name appears in the prompt
            for sq in arch.seedQueries {
                let sqLower = sq.lowercased()
                let sqWords = sqLower.split(separator: " ").map(String.init)
                if sqWords.count >= 2 {
                    let artistCand = sqWords.prefix(2).joined(separator: " ")
                    if artistCand.count >= 5 && lower.contains(artistCand) {
                        keywordScore += 3.0
                        break
                    }
                }
            }

            // (b) 512-D Neural Sentence Embedding Cosine Similarity
            // Cosine distance is in [0, 2]; background unrelated English sentences sit around 0.72..0.95.
            // Only reward genuine semantic closeness (dist < 0.58).
            if let pVec = promptSentVec, let archVec = normalizedSentenceVector(for: arch.semanticDescriptorEn) {
                let dist = Self.cosineDistanceNormalized(pVec, archVec)
                if dist < 0.58 {
                    let similarity = max(0.0, (0.58 - dist) * 3.4)
                    embeddingScore += similarity
                }
            }

            // (c) Word-level neural embedding similarity for English mood/genre tokens
            if !promptWordVecs.isEmpty {
                for (tok, tokVec) in promptWordVecs {
                    for kwEn in arch.keywordsEn.prefix(8) where !kwEn.contains(" ") && kwEn != tok {
                        if let kwVec = normalizedWordVector(for: kwEn) {
                            let wDist = Self.cosineDistanceNormalized(tokVec, kwVec)
                            if wDist < 0.46 {
                                embeddingScore += (0.46 - wDist) * 1.5
                            }
                        }
                    }
                }
            }

            let totalScore = keywordScore + embeddingScore
            scored.append((arch, totalScore, keywordScore))
        }

        scored.sort { $0.score > $1.score }

        let primary = scored[0].archetype
        let primaryScore = scored[0].score
        let primaryKeywordScore = scored[0].keywordScore
        // Only blend a secondary archetype when BOTH primary and secondary have genuine keyword/concept matches!
        let secondary: SonicArchetype? = {
            guard scored.count > 1 else { return nil }
            let sec = scored[1]
            if primaryKeywordScore >= 1.5 && sec.keywordScore >= 1.6 && sec.score >= max(2.2, primaryScore * 0.58) {
                return sec.archetype
            }
            return nil
        }()

        // If user asked "в стиле <UnknownArtist>" and no mood/genre archetype matched by keyword,
        // return an artist-focused plan ready for dynamic catalog resolution instead of a random preset archetype!
        if !styleIntent.targetArtist.isEmpty && matchedArtistProfile == nil && primaryKeywordScore < 1.2 {
            let displayArtist = Self.titleCaseArtistName(styleIntent.targetArtist)
            let title = preferEnglish
                ? "In the Style of \(displayArtist) • AI Sonic Mix"
                : "В стиле \(displayArtist) • ИИ-подборка по звучанию"
            let subtitle = preferEnglish
                ? "Semantic curation of tracks and kindred artists matching the sonic signature of \(displayArtist)."
                : "Семантическая подборка треков и близких по духу исполнителей по музыкальному почерку \(displayArtist)."
            let tags = preferEnglish
                ? ["🎙️ \(displayArtist)", "✨ Neural 512-D", "🎚️ Lossless Priority"]
                : ["🎙️ \(displayArtist)", "✨ Neural 512-D", "🎚️ Lossless Приоритет"]
            var queries: [String] = [displayArtist]
            for q in primary.seedQueries.shuffled().prefix(6) where !queries.contains(q) {
                queries.append(q)
            }
            return CuratedSessionPlan(
                prompt: prompt,
                title: title,
                subtitle: subtitle,
                tags: tags,
                engineBadge: activeEngineDescription,
                seedQueries: queries,
                confidenceScore: 0.88
            )
        }

        // 5. Build blended seed queries (shuffled per session so curations always start with fresh tracks)
        var finalQueries: [String] = []

        // If user mentioned specific artist/entity names (e.g. "как у Pink Floyd" or "с саксофоном Miles Davis"), prioritize them!
        for entity in extractedEntities.prefix(2) {
            if !finalQueries.contains(where: { $0.caseInsensitiveCompare(entity) == .orderedSame }) {
                finalQueries.append(entity)
            }
        }
        if let profile = matchedArtistProfile {
            for pq in profile.seedQueries.prefix(4) {
                if !finalQueries.contains(where: { $0.caseInsensitiveCompare(pq) == .orderedSame }) {
                    finalQueries.append(pq)
                }
            }
        }

        let primaryFlagship = primary.seedQueries.first.map { [$0] } ?? []
        let primaryRest = Array(primary.seedQueries.dropFirst()).shuffled()
        let primaryOrdered = primaryFlagship + primaryRest
        if let sec = secondary {
            let primaryPicked = Array(primaryOrdered.prefix(5)).shuffled()
            let secFlagship = sec.seedQueries.first.map { [$0] } ?? []
            let secPicked = Array((secFlagship + Array(sec.seedQueries.dropFirst()).shuffled()).prefix(5)).shuffled()
            for i in 0..<max(primaryPicked.count, secPicked.count) {
                if i < primaryPicked.count && finalQueries.count < 10 {
                    let q = primaryPicked[i]
                    if !finalQueries.contains(q) { finalQueries.append(q) }
                }
                if i < secPicked.count && finalQueries.count < 10 {
                    let q = secPicked[i]
                    if !finalQueries.contains(q) { finalQueries.append(q) }
                }
            }
        } else {
            let primaryPicked = Array(primaryOrdered.prefix(10)).shuffled()
            for q in primaryPicked where !finalQueries.contains(q) {
                finalQueries.append(q)
                if finalQueries.count >= 10 { break }
            }
        }

        // If the prompt didn't strongly hit a preset archetype, include the cleaned prompt itself as a direct catalog query
        if primaryScore < 1.6 {
            let cleanedPrompt = cleanPromptForDirectSearch(trimmedPrompt)
            if !cleanedPrompt.isEmpty && !finalQueries.contains(where: { $0.caseInsensitiveCompare(cleanedPrompt) == .orderedSame }) {
                finalQueries.insert(cleanedPrompt, at: 0)
            }
        }

        // 6. Compose title, subtitle, and semantic tags
        let title: String
        let subtitle: String
        var tags: [String]

        if let sec = secondary, primaryScore >= 2.0 {
            if preferEnglish {
                title = "\(primary.titleEn) × \(sec.titleEn)"
                subtitle = "\(primary.descriptionEn) Blended with elements of \(sec.titleEn.lowercased())."
                tags = Array((primary.tagsEn.prefix(2) + sec.tagsEn.prefix(2)))
            } else {
                title = "\(primary.titleRu) × \(sec.titleRu)"
                subtitle = "\(primary.descriptionRu) С элементами эстетики «\(sec.titleRu)»."
                tags = Array((primary.tagsRu.prefix(2) + sec.tagsRu.prefix(2)))
            }
        } else if primaryScore >= 1.5 {
            title = preferEnglish ? primary.titleEn : primary.titleRu
            subtitle = preferEnglish ? primary.descriptionEn : primary.descriptionRu
            tags = preferEnglish ? primary.tagsEn : primary.tagsRu
        } else {
            let cleanLabel = cleanPromptForDirectSearch(trimmedPrompt)
            let displayPrompt = cleanLabel.isEmpty ? trimmedPrompt : cleanLabel
            title = preferEnglish ? "AI Sonic Selection: «\(displayPrompt)»" : "AI-Подборка: «\(displayPrompt)»"
            subtitle = preferEnglish
                ? "Semantic curation powered by macOS NaturalLanguage 512-D neural embeddings and reference Apple Music catalog matching."
                : "Семантическая подборка на базе нейросетевых эмбеддингов macOS NaturalLanguage (512-D) и эталонного каталога Apple Music."
            tags = preferEnglish
                ? ["✨ Neural 512-D", "🎚️ Lossless Priority", primary.titleEn]
                : ["✨ Neural 512-D", "🎚️ Lossless Приоритет", primary.titleRu]
        }

        for entity in extractedEntities.prefix(2) {
            let tag = "🎙️ \(entity)"
            if !tags.contains(tag) && tags.count < 5 {
                tags.append(tag)
            }
        }

        let normalizedConfidence: Double
        if primaryScore >= 1.5 {
            normalizedConfidence = min(0.98, max(0.75, 0.68 + (primaryScore / 10.0)))
        } else {
            normalizedConfidence = 0.65
        }

        return CuratedSessionPlan(
            prompt: prompt,
            title: title,
            subtitle: subtitle,
            tags: tags,
            engineBadge: activeEngineDescription,
            seedQueries: Array(finalQueries.prefix(10)),
            confidenceScore: normalizedConfidence
        )
    }

    // MARK: - Artist Style Intent Extraction

    internal static let styleActionPrefixes: [String] = [
        "включи ", "поставь ", "найди ", "подбери ", "сделай ", "собери ",
        "хочу послушать ", "хочу ", "дай ", "запусти ",
        "play ", "find ", "curate ", "give me "
    ]

    /// Ordered longest-first so multi-word prefixes ("в стиле гуппы", "в стиле группы") strip completely
    internal static let stylePhrasePrefixes: [String] = [
        "музыка в стиле группы", "музыка в стиле гуппы", "музыка в стиле групы", "музыка в стиле группи",
        "музыка в стиле артиста", "музыка в стиле исполнителя", "музыка в стиле",
        "треки в стиле группы", "треки в стиле гуппы", "треки в стиле групы", "треки в стиле",
        "песни в стиле группы", "песни в стиле гуппы", "песни в стиле групы", "песни в стиле",
        "подборка в стиле группы", "подборка в стиле гуппы", "подборка в стиле",
        "плейлист в стиле группы", "плейлист в стиле гуппы", "плейлист в стиле",
        "что-нибудь в стиле группы", "что-нибудь в стиле гуппы", "что-нибудь в стиле",
        "что-то в стиле группы", "что-то в стиле гуппы", "что-то в стиле",
        "в стиле группы", "в стиле гуппы", "в стиле групы", "в стиле группи",
        "в стиле гр.", "в стиле гр",
        "в стиле артиста", "в стиле исполнителя", "в стиле музыканта", "в стиле коллектива",
        "в стиле певицы", "в стиле певца", "в стиле бэнда", "в стиле банды",
        "в стиле",
        "музыка как у группы", "музыка как у гуппы", "музыка как у групы", "музыка как у",
        "звучание как у группы", "звучание как у гуппы", "звучание как у",
        "саунд как у группы", "саунд как у",
        "как у группы", "как у гуппы", "как у групы", "как у артиста", "как у исполнителя", "как у",
        "похожее на группу", "похожее на гуппу", "похожее на групу", "похожее на",
        "похожие на группу", "похожие на гуппу", "похожие на групу", "похожие на",
        "похоже на группу", "похоже на гуппу", "похоже на групу", "похоже на артиста", "похоже на",
        "похожий на группу", "похожий на",
        "в духе группы", "в духе гуппы", "в духе групы", "в духе артиста", "в духе",
        "что-то вроде группы", "что-то вроде гуппы", "что-то вроде",
        "что-нибудь вроде группы", "что-нибудь вроде гуппы", "что-нибудь вроде",
        "что-то типа группы", "что-то типа гуппы", "что-то типа",
        "типа группы", "типа гуппы", "типа групы", "типа",
        "наподобие группы", "наподобие гуппы", "наподобие",
        "music in the style of the band", "music in the style of", "in the style of the band",
        "in the style of band", "in the style of", "style of the band", "style of",
        "music like the band", "music like", "songs like", "tracks like", "bands like",
        "artists like", "sounds like", "sound like", "similar to the band", "similar to",
        "vibe of", "something like", "like the band"
    ]

    private static let midSentenceStyleConnectors: [String] = [
        " в стиле группы ", " в стиле гуппы ", " в стиле групы ", " в стиле группи ",
        " в стиле артиста ", " в стиле исполнителя ", " в стиле ",
        " как у группы ", " как у гуппы ", " как у групы ", " как у ",
        " похоже на группу ", " похоже на гуппу ", " похоже на ", " похожие на ", " похожее на ",
        " в духе группы ", " в духе гуппы ", " в духе ",
        " типа группы ", " типа гуппы ", " типа ",
        " in the style of ", " similar to ", " sounds like ", " like "
    ]

    private static let leadingGroupNouns: [String] = [
        "группы ", "гуппы ", "групы ", "группи ", "группа ", "гуппа ", "група ",
        "артиста ", "исполнителя ", "музыканта ", "коллектива ", "бэнда ", "банды ",
        "band ", "the band ", "artist "
    ]

    internal func extractArtistStyleIntent(from rawPrompt: String) -> ArtistStyleIntent {
        var working = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.isEmpty else {
            return ArtistStyleIntent(targetArtist: "", moodContext: "", isExplicitStylePrefix: false, isIncompletePrefixOnly: false)
        }

        let lowerInitial = working.lowercased()
        for act in Self.styleActionPrefixes {
            if lowerInitial.hasPrefix(act) {
                working = String(working.dropFirst(act.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        let lowerWorking = working.lowercased()

        // 1. Check leading style prefixes ("в стиле гуппы tool", "как у daft punk", etc.)
        for prefix in Self.stylePhrasePrefixes {
            if lowerWorking == prefix {
                return ArtistStyleIntent(targetArtist: "", moodContext: "", isExplicitStylePrefix: true, isIncompletePrefixOnly: true)
            }
            if lowerWorking.hasPrefix(prefix + " ") {
                var remainder = String(working.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                let remLower = remainder.lowercased()
                for noun in Self.leadingGroupNouns {
                    if remLower.hasPrefix(noun) {
                        remainder = String(remainder.dropFirst(noun.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                }
                remainder = remainder.trimmingCharacters(in: CharacterSet(charactersIn: "\"'«».,!?;:-—"))
                if remainder.isEmpty || Self.isDanglingGroupNoun(remainder.lowercased()) {
                    return ArtistStyleIntent(targetArtist: "", moodContext: "", isExplicitStylePrefix: true, isIncompletePrefixOnly: true)
                }
                return ArtistStyleIntent(targetArtist: remainder, moodContext: "", isExplicitStylePrefix: true, isIncompletePrefixOnly: false)
            }
        }

        // Check partial typing of "в с", "в сти", "в стиле г", "как", "похож"
        if Self.isDanglingStyleInput(lowerWorking) {
            return ArtistStyleIntent(targetArtist: "", moodContext: "", isExplicitStylePrefix: true, isIncompletePrefixOnly: true)
        }

        // 2. Check mid-sentence style connectors ("ночной инструментальный рок как у Pink Floyd")
        for conn in Self.midSentenceStyleConnectors {
            if let range = lowerWorking.range(of: conn) {
                let moodPart = String(working[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                var artistPart = String(working[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let artLower = artistPart.lowercased()
                for noun in Self.leadingGroupNouns {
                    if artLower.hasPrefix(noun) {
                        artistPart = String(artistPart.dropFirst(noun.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                }
                artistPart = artistPart.trimmingCharacters(in: CharacterSet(charactersIn: "\"'«».,!?;:-—"))
                if !artistPart.isEmpty && !Self.isDanglingGroupNoun(artistPart.lowercased()) {
                    return ArtistStyleIntent(
                        targetArtist: artistPart,
                        moodContext: moodPart,
                        isExplicitStylePrefix: true,
                        isIncompletePrefixOnly: false
                    )
                }
            }
        }

        // 3. Check if prompt starts with "группа <Artist>" / "группы <Artist>" / "гуппы <Artist>"
        for noun in Self.leadingGroupNouns {
            if lowerWorking.hasPrefix(noun) {
                let remainder = String(working.dropFirst(noun.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'«».,!?;:-—"))
                if !remainder.isEmpty {
                    return ArtistStyleIntent(targetArtist: remainder, moodContext: "", isExplicitStylePrefix: true, isIncompletePrefixOnly: false)
                }
            }
        }

        return ArtistStyleIntent(targetArtist: "", moodContext: working, isExplicitStylePrefix: false, isIncompletePrefixOnly: false)
    }

    private static func isDanglingGroupNoun(_ lower: String) -> Bool {
        let partials: Set<String> = [
            "г", "гр", "гру", "груп", "групп", "группы", "группа", "гу", "гуп", "гупп", "гуппы", "групы", "группи",
            "арт", "артист", "артиста", "исп", "исполнителя"
        ]
        return partials.contains(lower)
    }

    private static func isDanglingStyleInput(_ lower: String) -> Bool {
        let prefixes: Set<String> = [
            "в", "в с", "в ст", "в сти", "в стил", "в стиле",
            "как", "как у", "похож", "похоже", "похоже на", "в духе", "типа"
        ]
        if prefixes.contains(lower) { return true }
        if lower.hasPrefix("в стиле ") {
            let tail = String(lower.dropFirst("в стиле ".count)).trimmingCharacters(in: .whitespaces)
            if isDanglingGroupNoun(tail) { return true }
        }
        return false
    }

    internal static func titleCaseArtistName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.lowercased() == "ac/dc" || trimmed.lowercased() == "acdc" { return "AC/DC" }
        if trimmed.lowercased() == "ddt" || trimmed.lowercased() == "ддт" { return "ДДТ" }
        // If user already typed uppercase letters inside (e.g. "Pink Floyd", "Depeche Mode"), preserve them
        if trimmed.contains(where: { $0.isUppercase }) {
            return trimmed
        }
        return trimmed
            .split(separator: " ")
            .map { word -> String in
                let w = String(word)
                guard let first = w.first else { return w }
                return String(first).uppercased() + String(w.dropFirst())
            }
            .joined(separator: " ")
    }

    internal func findArtistStyleProfile(for rawArtist: String) -> ArtistStyleProfile? {
        let clean = rawArtist
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'«».,!?;:-—"))
        guard clean.count >= 2 else { return nil }

        // 1. Exact alias or canonical match
        for profile in artistStyleProfiles {
            if profile.canonicalArtist.lowercased() == clean || profile.aliases.contains(clean) {
                return profile
            }
        }

        // 2. Whole-word boundary match inside rawArtist (e.g. "группы tool" -> "tool")
        let words = Set(clean.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        for profile in artistStyleProfiles {
            for alias in profile.aliases {
                if alias.contains(" ") {
                    if clean.contains(alias) { return profile }
                } else if alias.count >= 3 && words.contains(alias) {
                    return profile
                }
            }
        }
        return nil
    }

    internal func findArtistStyleProfileInPrompt(lowerPrompt: String) -> ArtistStyleProfile? {
        let clean = lowerPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2 else { return nil }

        // Direct match if the entire prompt is an artist name (e.g. "tool", "kraftwerk", "daft punk")
        for profile in artistStyleProfiles {
            if profile.canonicalArtist.lowercased() == clean || profile.aliases.contains(clean) {
                return profile
            }
        }

        // Multi-word artist alias match inside prompt, or unambiguous single-word band alias (>= 4 chars)
        let words = Set(clean.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        let nonUnambiguousSingleWords: Set<String> = ["air", "yes", "can", "low", "war", "rush", "kino", "кино"]
        for profile in artistStyleProfiles {
            for alias in profile.aliases {
                if alias.contains(" ") {
                    if clean.contains(alias) { return profile }
                } else if alias.count >= 4 && !nonUnambiguousSingleWords.contains(alias) && words.contains(alias) {
                    return profile
                }
            }
        }
        return nil
    }
}
