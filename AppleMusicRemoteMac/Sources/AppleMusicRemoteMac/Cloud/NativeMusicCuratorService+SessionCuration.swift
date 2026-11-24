import Foundation

extension NativeMusicCuratorService {

    /// Generates a semantic curation plan (title, audiophile notes, tags, and catalog seed queries)
    /// from any natural-language prompt in Russian or English.
    public func buildCuratedPlan(for rawPrompt: String, preferEnglish: Bool = false, allowFoundationModels: Bool = true) async -> CuratedSessionPlan {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            let fallback = archetypes[0]
            return CuratedSessionPlan(
                prompt: prompt,
                title: preferEnglish ? fallback.titleEn : fallback.titleRu,
                subtitle: preferEnglish ? fallback.descriptionEn : fallback.descriptionRu,
                tags: preferEnglish ? fallback.tagsEn : fallback.tagsRu,
                engineBadge: activeEngineDescription,
                seedQueries: fallback.seedQueries,
                confidenceScore: 1.0
            )
        }

        // 1. Compute fast on-device NaturalLanguage 512-D NLEmbedding + NLTagger plan (< 5 ms on M1 with vector cache)
        let nlPlan = buildNaturalLanguagePlan(for: prompt, preferEnglish: preferEnglish)

        // 2. If NaturalLanguage 512-D already matched a sonic archetype/concept with high confidence (>= 0.74),
        //    or when running background Infinite AI Wave, return immediately without stalling on M1 LLM cold-start.
        if !allowFoundationModels || nlPlan.confidenceScore >= 0.74 || Task.isCancelled {
            return nlPlan
        }

        // 3. For free-form custom prompts with low archetype overlap, try Apple Intelligence (FoundationModels)
        //    with a strict 2.2s non-blocking timeout and automatic fallback to nlPlan.
        if let fmPlan = await tryFoundationModelsPlan(
            for: prompt,
            preferEnglish: preferEnglish,
            fallbackQueries: nlPlan.seedQueries
        ) {
            return fmPlan
        }

        return nlPlan
    }

    /// Full end-to-end curation: analyzes the prompt with on-device Apple AI frameworks,
    /// resolves tracks and albums in parallel via Apple Music catalog, and deduplicates/ranks results.
    public func curateMusicSession(prompt: String, storefront: String = "") async -> [String: Any] {
        let totalStart = Date()
        let preferEnglish = !MusicKitManager.shared.isSystemLocaleRussian
        var plan = await buildCuratedPlan(for: prompt, preferEnglish: preferEnglish, allowFoundationModels: true)

        let sf = MusicKitManager.shared.resolveEffectiveStorefront(storefront)

        // If the user requested "in the style of <Artist>" for an artist not in the static peer graph,
        // dynamically resolve the artist's genre and albums in the Apple Music catalog so any artist works accurately.
        let styleIntent = extractArtistStyleIntent(from: prompt)
        if !Task.isCancelled,
           !styleIntent.targetArtist.isEmpty,
           findArtistStyleProfile(for: styleIntent.targetArtist) == nil,
           !PlaybackRouter.shared.isTestingEnvironment,
           let enrichedPlan = await resolveDynamicCatalogArtistPlan(
               targetArtist: styleIntent.targetArtist,
               basePlan: plan,
               storefront: sf,
               preferEnglish: preferEnglish
           ) {
            plan = enrichedPlan
        }
        let planMs = Int(Date().timeIntervalSince(totalStart) * 1000)

        if Task.isCancelled {
            return [
                "status": "cancelled",
                "prompt": prompt,
                "title": plan.title,
                "subtitle": plan.subtitle,
                "tags": plan.tags,
                "engine": plan.engineBadge,
                "seed_queries": plan.seedQueries,
                "confidence": plan.confidenceScore,
                "songs": [],
                "albums": []
            ]
        }

        // Execute parallel catalog searches for the seed queries
        let searchStart = Date()
        let queries = Array(plan.seedQueries.prefix(10))
        var queryBuckets: [(Int, [[String: Any]], [[String: Any]])] = []

        await withTaskGroup(of: (Int, [[String: Any]], [[String: Any]]).self) { group in
            for (idx, q) in queries.enumerated() {
                group.addTask { [weak self] in
                    guard let self = self,
                          !Task.isCancelled,
                          let res = await self.searchCatalogWithTimeout(query: q, storefront: sf, limit: 8) else {
                        return (idx, [], [])
                    }
                    let songs = (res["songs"] as? [[String: Any]]) ?? []
                    let albums = (res["albums"] as? [[String: Any]]) ?? []
                    return (idx, songs, albums)
                }
            }
            for await item in group {
                queryBuckets.append(item)
            }
        }

        if Task.isCancelled {
            return [
                "status": "cancelled",
                "prompt": prompt,
                "title": plan.title,
                "subtitle": plan.subtitle,
                "tags": plan.tags,
                "engine": plan.engineBadge,
                "seed_queries": plan.seedQueries,
                "confidence": plan.confidenceScore,
                "songs": [],
                "albums": []
            ]
        }

        queryBuckets.sort { $0.0 < $1.0 }

        func interleaveBuckets(_ buckets: [(Int, [[String: Any]], [[String: Any]])]) -> [[String: Any]] {
            var list: [[String: Any]] = []
            var seenTrackKeys = Set<String>()
            var artistCounts: [String: Int] = [:]
            let maxRounds = 8
            for passCap in [1, 2] {
                for round in 0..<maxRounds {
                    for (_, songs, _) in buckets {
                        guard round < songs.count else { continue }
                        let song = songs[round]
                        let id = String(describing: song["id"] ?? "")
                        let rawName = (song["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let rawArtist = (song["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !rawName.isEmpty else { continue }

                        let normName = normalizeSongTitleForDedup(rawName)
                        let normArtist = normalizeArtistForDedup(rawArtist)
                        let dedupKey = "\(normArtist)|\(normName)"
                        let titleOnlyKey = "title|\(normName)"

                        if seenTrackKeys.contains(dedupKey) || seenTrackKeys.contains(titleOnlyKey) || (!id.isEmpty && seenTrackKeys.contains(id)) {
                            continue
                        }
                        let currentArtistCount = artistCounts[normArtist] ?? 0
                        if currentArtistCount >= passCap {
                            continue
                        }

                        seenTrackKeys.insert(dedupKey)
                        if normName.count >= 4 {
                            seenTrackKeys.insert(titleOnlyKey)
                        }
                        if !id.isEmpty { seenTrackKeys.insert(id) }
                        artistCounts[normArtist] = currentArtistCount + 1
                        list.append(song)

                        if list.count >= 24 { break }
                    }
                    if list.count >= 24 { break }
                }
                if list.count >= 24 { break }
            }
            return list
        }

        var curatedSongs = interleaveBuckets(queryBuckets)

        // Fallback 1: If primary storefront or custom LLM queries yielded < 6 songs, supplement with NL archetype queries & "us" storefront
        if curatedSongs.count < 6 && !Task.isCancelled && !PlaybackRouter.shared.isTestingEnvironment {
            let fallbackSf = (sf == "us") ? "ru" : "us"
            let nlFallbackQueries = Array(buildNaturalLanguagePlan(for: prompt, preferEnglish: preferEnglish).seedQueries.prefix(6))
            NSLog("[AICurator] ⚠️ Initial search returned %d songs (sf=%@); running fallback queries on sf=%@", curatedSongs.count, sf, fallbackSf)
            await withTaskGroup(of: (Int, [[String: Any]], [[String: Any]]).self) { group in
                for (offsetIdx, fq) in nlFallbackQueries.enumerated() {
                    let bucketIdx = queries.count + offsetIdx
                    group.addTask { [weak self] in
                        guard let self = self,
                              !Task.isCancelled,
                              let res = await self.searchCatalogWithTimeout(query: fq, storefront: fallbackSf, limit: 8) else {
                            return (bucketIdx, [], [])
                        }
                        let songs = (res["songs"] as? [[String: Any]]) ?? []
                        let albums = (res["albums"] as? [[String: Any]]) ?? []
                        return (bucketIdx, songs, albums)
                    }
                }
                for await item in group {
                    queryBuckets.append(item)
                }
            }
            queryBuckets.sort { $0.0 < $1.0 }
            curatedSongs = interleaveBuckets(queryBuckets)
        }

        // Fallback 2: Offline / Local Library fallback so AI curation NEVER returns 0 tracks
        if curatedSongs.isEmpty && !Task.isCancelled && !PlaybackRouter.shared.isTestingEnvironment {
            let localSongs = LibraryService.shared.getCachedLibrarySongs().shuffled().prefix(20)
            for ls in localSongs {
                curatedSongs.append([
                    "id": ls.id,
                    "numeric_id": ls.numericId ?? 0,
                    "name": ls.name,
                    "artist": ls.artist,
                    "album": ls.album,
                    "duration": ls.duration,
                    "artwork_url": ls.artworkUrl,
                    "is_local": true
                ])
            }
            if !curatedSongs.isEmpty {
                NSLog("[AICurator] 💿 Catalog unreachable; populated %d tracks from local Music.app library", curatedSongs.count)
            }
        }

        let searchMs = Int(Date().timeIntervalSince(searchStart) * 1000)

        // Order curated tracks along a smooth 512-D NLEmbedding cosine trajectory ("Плавный поток")
        let flowStart = Date()
        curatedSongs = orderSongsBySemanticFlow(curatedSongs)
        let flowMs = Int(Date().timeIntervalSince(flowStart) * 1000)

        // Collect deduplicated recommended albums
        var curatedAlbums: [[String: Any]] = []
        var seenAlbumKeys = Set<String>()
        for (_, _, albums) in queryBuckets {
            for album in albums.prefix(2) {
                let name = (album["name"] as? String ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let artist = (album["artist"] as? String ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let key = "\(artist)|\(name)"
                if seenAlbumKeys.contains(key) { continue }
                seenAlbumKeys.insert(key)
                curatedAlbums.append(album)
                if curatedAlbums.count >= 8 { break }
            }
            if curatedAlbums.count >= 8 { break }
        }

        let totalMs = Int(Date().timeIntervalSince(totalStart) * 1000)
        NSLog("[AICurator] ✨ curateMusicSession done in %dms (plan=%dms, search=%dms, flow=%dms) -> %d songs, %d albums | title='%@' | prompt='%@'",
              totalMs, planMs, searchMs, flowMs, curatedSongs.count, curatedAlbums.count, plan.title, prompt)

        return [
            "status": "ok",
            "prompt": prompt,
            "title": plan.title,
            "subtitle": plan.subtitle,
            "tags": plan.tags,
            "engine": plan.engineBadge,
            "seed_queries": plan.seedQueries,
            "confidence": plan.confidenceScore,
            "songs": curatedSongs,
            "albums": curatedAlbums
        ]
    }

    // MARK: - Infinite AI Wave (Auto-Appending Curated Tracks)

    public func filterAndInterleaveWaveSongs(
        queryBuckets: [(Int, [[String: Any]], [[String: Any]])],
        excluding: [TrackInfo],
        maxCount: Int = 20
    ) -> [[String: Any]] {
        var seenTrackKeys = Set<String>()
        for ex in excluding {
            let exId = ex.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if !exId.isEmpty { seenTrackKeys.insert(exId) }
            let normName = normalizeSongTitleForDedup(ex.name)
            let normArtist = normalizeArtistForDedup(ex.artist)
            if !normName.isEmpty {
                seenTrackKeys.insert("\(normArtist)|\(normName)")
                if normName.count >= 4 {
                    seenTrackKeys.insert("title|\(normName)")
                }
            }
        }

        var curatedSongs: [[String: Any]] = []
        var artistCounts: [String: Int] = [:]
        let maxRounds = 12

        for passCap in [1, 2] {
            for round in 0..<maxRounds {
                for (_, songs, _) in queryBuckets {
                    guard round < songs.count else { continue }
                    let song = songs[round]
                    let id = String(describing: song["id"] ?? "")
                    let rawName = (song["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let rawArtist = (song["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !rawName.isEmpty else { continue }

                    let normName = normalizeSongTitleForDedup(rawName)
                    let normArtist = normalizeArtistForDedup(rawArtist)
                    let dedupKey = "\(normArtist)|\(normName)"
                    let titleOnlyKey = "title|\(normName)"

                    if seenTrackKeys.contains(dedupKey) || seenTrackKeys.contains(titleOnlyKey) || (!id.isEmpty && seenTrackKeys.contains(id)) {
                        continue
                    }
                    let currentArtistCount = artistCounts[normArtist] ?? 0
                    if currentArtistCount >= passCap {
                        continue
                    }

                    seenTrackKeys.insert(dedupKey)
                    if normName.count >= 4 {
                        seenTrackKeys.insert(titleOnlyKey)
                    }
                    if !id.isEmpty { seenTrackKeys.insert(id) }
                    artistCounts[normArtist] = currentArtistCount + 1
                    curatedSongs.append(song)

                    if curatedSongs.count >= maxCount { break }
                }
                if curatedSongs.count >= maxCount { break }
            }
            if curatedSongs.count >= maxCount { break }
        }
        return orderSongsBySemanticFlow(curatedSongs)
    }

    // MARK: - Semantic Cosine Flow Queue Ordering ("Плавный поток")

    /// Orders tracks along a smooth semantic trajectory using pre-normalized 512-D `NLEmbedding` vectors
    /// and archetype/token proximity, while strictly avoiding consecutive tracks by the same artist.
    /// Uses preloaded archetype sentence vectors and preloaded word vectors so ordering 24 tracks takes < 1 ms on M1
    /// with zero CoreML/BNNS uncached sentence-transformer evaluations.
    public func orderSongsBySemanticFlow(_ songs: [[String: Any]]) -> [[String: Any]] {
        guard isEnabled, songs.count > 2 else { return songs }

        struct SongSemanticProfile {
            let normArtist: String
            let descriptorEn: String
            let tokenSet: Set<String>
            let sentenceVector: [Double]?
            let wordVectors: [(token: String, vec: [Double])]
        }

        let profiles: [SongSemanticProfile] = songs.map { song in
            let rawArtist = (song["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let rawName = (song["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let rawAlbum = (song["album"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let rawGenre = (song["genre"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            let normArtist = normalizeArtistForDedup(rawArtist)
            let artistLower = rawArtist.lowercased()
            let albumLower = rawAlbum.lowercased()
            let genreLower = rawGenre.lowercased()

            var archetypeDescriptor = ""
            var primaryArchDescriptorKey = ""
            if !artistLower.isEmpty {
                if let styleProf = findArtistStyleProfile(for: artistLower),
                   let arch = archetypes.first(where: { $0.id == styleProf.archetypeId }) {
                    primaryArchDescriptorKey = arch.semanticDescriptorEn
                    archetypeDescriptor += " " + arch.semanticDescriptorEn + " " + arch.keywordsEn.joined(separator: " ")
                }
                for arch in archetypes {
                    if arch.seedQueries.contains(where: { q in
                        let ql = q.lowercased()
                        return ql.contains(artistLower) || (!albumLower.isEmpty && albumLower.count >= 4 && ql.contains(albumLower))
                    }) {
                        if primaryArchDescriptorKey.isEmpty {
                            primaryArchDescriptorKey = arch.semanticDescriptorEn
                        }
                        archetypeDescriptor += " " + arch.semanticDescriptorEn + " " + arch.keywordsEn.joined(separator: " ")
                    }
                }
            }
            if primaryArchDescriptorKey.isEmpty && !genreLower.isEmpty,
               let genreArch = bestArchetypeForCatalogGenre(genreLower) {
                primaryArchDescriptorKey = genreArch.semanticDescriptorEn
                archetypeDescriptor += " " + genreArch.semanticDescriptorEn
            }

            let rawCombined = [rawArtist, rawName, rawAlbum, rawGenre, archetypeDescriptor]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let lowerCombined = rawCombined.lowercased()
            let rawTokens = lowerCombined
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 }
            let translated = translatePromptToEnglishSemanticSpace(lowerPrompt: lowerCombined, tokens: rawTokens)
            let finalDescriptor = (lowerCombined + " " + translated).trimmingCharacters(in: .whitespacesAndNewlines)
            let sortedTokens = Array(
                Set(
                    finalDescriptor
                        .components(separatedBy: CharacterSet.alphanumerics.inverted)
                        .filter { $0.count >= 3 }
                )
            ).sorted()
            let tokenSet = Set(sortedTokens)

            // Use the preloaded archetype 512-D sentence vector (<100ns lookup) instead of running
            // 24 uncached CoreML sentence-embedding neural evaluations on arbitrary song titles.
            let sentVec = primaryArchDescriptorKey.isEmpty ? nil : normalizedSentenceVector(for: primaryArchDescriptorKey)
            var wVecs: [(String, [Double])] = []
            nlEngineLock.lock()
            for tok in sortedTokens {
                if let permanent = preloadedWordVectors[tok] {
                    wVecs.append((tok, permanent))
                    if wVecs.count >= 5 { break }
                }
            }
            nlEngineLock.unlock()

            return SongSemanticProfile(
                normArtist: normArtist,
                descriptorEn: finalDescriptor,
                tokenSet: tokenSet,
                sentenceVector: sentVec,
                wordVectors: wVecs
            )
        }

        func semanticSimilarity(_ a: SongSemanticProfile, _ b: SongSemanticProfile) -> Double {
            var score = 0.0

            // 1. 512-D NLEmbedding sentence cosine similarity (pure-Swift dot product on pre-normalized vectors)
            if let vecA = a.sentenceVector, let vecB = b.sentenceVector {
                let dist = Self.cosineDistanceNormalized(vecA, vecB)
                if dist <= 2.0 {
                    score += max(0.0, (2.0 - dist) * 1.5)
                }
            }

            // 2. Shared semantic/genre/archetype token overlap (Jaccard-weighted)
            if !a.tokenSet.isEmpty && !b.tokenSet.isEmpty {
                let intersectionCount = a.tokenSet.intersection(b.tokenSet).count
                let unionCount = max(1, a.tokenSet.union(b.tokenSet).count)
                score += (Double(intersectionCount) / Double(unionCount)) * 3.0
            }

            // 3. Word-level NLEmbedding proximity on up to 5 precomputed token vectors
            if !a.wordVectors.isEmpty && !b.wordVectors.isEmpty {
                var wordBonus = 0.0
                for (tokA, vecA) in a.wordVectors {
                    for (tokB, vecB) in b.wordVectors where tokA != tokB {
                        let wDist = Self.cosineDistanceNormalized(vecA, vecB)
                        if wDist < 0.7 {
                            wordBonus += (0.7 - wDist) * 0.4
                        }
                    }
                }
                score += min(1.2, wordBonus)
            }

            return score
        }

        var orderedIndices: [Int] = [0]
        var remainingIndices: [Int] = Array(1..<songs.count)

        while !remainingIndices.isEmpty {
            let prevIdx = orderedIndices.last!
            let prevProfile = profiles[prevIdx]

            var bestPos = 0
            var bestScore = -Double.infinity

            for (pos, candIdx) in remainingIndices.enumerated() {
                let candProfile = profiles[candIdx]
                var sim = semanticSimilarity(prevProfile, candProfile)

                // Penalize consecutive tracks by the same artist so the queue never clusters same-artist back-to-back
                if !prevProfile.normArtist.isEmpty && prevProfile.normArtist == candProfile.normArtist {
                    sim -= 10.0
                }
                // Slight tie-breaker favoring original discovery rank
                sim -= Double(pos) * 0.001

                if sim > bestScore {
                    bestScore = sim
                    bestPos = pos
                }
            }

            let chosenIdx = remainingIndices.remove(at: bestPos)
            orderedIndices.append(chosenIdx)
        }

        return orderedIndices.map { songs[$0] }
    }

    /// Generates the next wave of ~18–20 fresh tracks for an active AI-curated session,
    /// strictly excluding all already queued/played tracks.
    public func curateNextWaveTracks(
        prompt: String,
        storefront: String = "",
        excluding: [TrackInfo]
    ) async -> [TrackInfo] {
        let waveStart = Date()
        let preferEnglish = !MusicKitManager.shared.isSystemLocaleRussian
        // Never invoke FoundationModels LLM during background Infinite AI Wave auto-append
        let plan = await buildCuratedPlan(for: prompt, preferEnglish: preferEnglish, allowFoundationModels: false)

        let sf = MusicKitManager.shared.resolveEffectiveStorefront(storefront)

        // Build a diverse set of 10 queries: shuffled seed queries + artist-level deep-cut queries
        var waveQueries = plan.seedQueries.shuffled()
        for q in plan.seedQueries.shuffled().prefix(4) {
            let words = q.split(separator: " ").map(String.init)
            if words.count >= 3 {
                let artistPrefix = words.prefix(2).joined(separator: " ")
                if !waveQueries.contains(artistPrefix) {
                    waveQueries.append(artistPrefix)
                }
            }
        }
        let selectedQueries = Array(waveQueries.prefix(10))
        var queryBuckets: [(Int, [[String: Any]], [[String: Any]])] = []

        await withTaskGroup(of: (Int, [[String: Any]], [[String: Any]]).self) { group in
            for (idx, q) in selectedQueries.enumerated() {
                group.addTask { [weak self] in
                    guard let self = self,
                          let res = await self.searchCatalogWithTimeout(query: q, storefront: sf, limit: 12) else {
                        return (idx, [], [])
                    }
                    var songs = (res["songs"] as? [[String: Any]]) ?? []
                    if songs.count > 2 {
                        songs.shuffle()
                    }
                    let albums = (res["albums"] as? [[String: Any]]) ?? []
                    return (idx, songs, albums)
                }
            }
            for await item in group {
                queryBuckets.append(item)
            }
        }

        queryBuckets.sort { $0.0 < $1.0 }
        let songDicts = filterAndInterleaveWaveSongs(queryBuckets: queryBuckets, excluding: excluding, maxCount: 20)

        var trackInfos: [TrackInfo] = []
        for (idx, item) in songDicts.enumerated() {
            let tid = (item["id"] as? String) ?? "\(excluding.count + idx + 1)"
            let numId = (item["numeric_id"] as? Int) ?? (item["numericId"] as? Int)
            let tName = (item["name"] as? String) ?? ""
            let tArtist = (item["artist"] as? String) ?? ""
            let tAlbum = (item["album"] as? String) ?? ""
            let tUrl = item["url"] as? String
            let tArt = (item["artwork_url"] as? String) ?? (item["artwork"] as? String) ?? ""
            let isLoc = (item["is_local"] as? Bool) ?? (item["isLocal"] as? Bool) ?? false
            let dur = (item["duration"] as? Double) ?? 0
            guard !tName.isEmpty else { continue }
            trackInfos.append(TrackInfo(
                id: tid,
                numericId: numId,
                name: tName,
                artist: tArtist,
                album: tAlbum,
                duration: dur,
                hasArtwork: !tArt.isEmpty,
                artworkUrl: tArt,
                favorited: false,
                isLocal: isLoc,
                url: tUrl,
                index: excluding.count + idx + 1
            ))
        }
        let waveMs = Int(Date().timeIntervalSince(waveStart) * 1000)
        NSLog("[AICurator] ♾️ curateNextWaveTracks done in %dms -> %d fresh tracks (excluded %d) for prompt='%@'",
              waveMs, trackInfos.count, excluding.count, prompt)
        return trackInfos
    }
}
