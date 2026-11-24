import Foundation

extension NativeMusicCuratorService {

    // MARK: - Full End-to-End Sonic Bridge Builder

    private struct ResolvedBridgeEndpoint: @unchecked Sendable {
        let rawQuery: String
        let displayLabel: String
        let canonicalArtist: String
        let genre: String
        let seedSong: [String: Any]?
        let anchorVector: [Double]
        let archetype: SonicArchetype
        let neighborhoodQueries: [String]
    }

    private struct BridgeSearchBucket: @unchecked Sendable {
        let index: Int
        let songs: [[String: Any]]
    }

    private func resolveBridgeEndpoint(
        query: String,
        storefront: String,
        preferEnglish: Bool
    ) async -> ResolvedBridgeEndpoint {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let basePlan = await buildCuratedPlan(for: trimmed, preferEnglish: preferEnglish, allowFoundationModels: false)

        var resolvedArtist = ""
        var resolvedGenre = ""
        var seedSong: [String: Any]?
        var extraQueries: [String] = []

        if !PlaybackRouter.shared.isTestingEnvironment,
           let catalogRes = await searchCatalogWithTimeout(query: trimmed, storefront: storefront, limit: 8) {
            let songs = (catalogRes["songs"] as? [[String: Any]]) ?? []
            let artists = (catalogRes["artists"] as? [[String: Any]]) ?? []
            let albums = (catalogRes["albums"] as? [[String: Any]]) ?? []

            if let firstArtist = artists.first {
                resolvedArtist = (firstArtist["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                resolvedGenre = (firstArtist["genre"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // Match a concrete opening/closing song if query overlaps artist or song title, or take top catalog song
            let queryTokens = Set(
                Self.foldSemanticText(trimmed)
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter(Self.isValidSemanticToken)
            )

            if let exactSong = songs.first(where: { s in
                let sName = Self.foldSemanticText(s["name"] as? String ?? "")
                let sArtist = Self.foldSemanticText(s["artist"] as? String ?? "")
                return queryTokens.contains(where: { sName.contains($0) || sArtist.contains($0) })
            }) ?? songs.first {
                seedSong = exactSong
                if resolvedArtist.isEmpty {
                    resolvedArtist = (exactSong["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if resolvedGenre.isEmpty {
                    resolvedGenre = (exactSong["genre"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            if resolvedGenre.isEmpty, let albGenre = albums.first?["genre"] as? String {
                resolvedGenre = albGenre
            }

            if !resolvedArtist.isEmpty {
                extraQueries.append(resolvedArtist)
                let foldedArtist = Self.foldSemanticText(resolvedArtist)
                if let prof = findArtistStyleProfile(for: resolvedArtist) ?? (!foldedArtist.isEmpty ? findArtistStyleProfile(for: foldedArtist) : nil) {
                    extraQueries.append(contentsOf: prof.seedQueries.prefix(3))
                }
            }
        }

        let vec = computeSemanticAnchorVector(
            queryText: trimmed,
            resolvedArtist: resolvedArtist,
            resolvedGenre: resolvedGenre
        ) ?? (normalizedSentenceVector(for: archetypes[0].semanticDescriptorEn) ?? [Double](repeating: 0.044, count: 512))

        // Best matching SonicArchetype to vec
        var bestArch = archetypes[0]
        var bestDist = Double.infinity
        for arch in archetypes {
            if let archVec = normalizedSentenceVector(for: arch.semanticDescriptorEn) {
                let d = Self.cosineDistanceNormalized(vec, archVec)
                if d < bestDist {
                    bestDist = d
                    bestArch = arch
                }
            }
        }

        for pq in basePlan.seedQueries where extraQueries.count < 5 {
            if !extraQueries.contains(where: { $0.caseInsensitiveCompare(pq) == .orderedSame }) {
                extraQueries.append(pq)
            }
        }
        for aq in bestArch.seedQueries where extraQueries.count < 6 {
            if !extraQueries.contains(where: { $0.caseInsensitiveCompare(aq) == .orderedSame }) {
                extraQueries.append(aq)
            }
        }

        let displayLabel: String = {
            if let song = seedSong {
                let sArtist = (song["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let sName = (song["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let qFolded = Self.foldSemanticText(trimmed)
                let sNameFolded = Self.foldSemanticText(sName)
                let resolvedArtistFolded = Self.foldSemanticText(resolvedArtist)
                // If user typed both artist & song (or song title), show "Artist — Song"; if artist only, show Artist
                if !sNameFolded.isEmpty && qFolded.contains(sNameFolded) && !sArtist.isEmpty {
                    return "\(sArtist) — \(sName)"
                }
                if !resolvedArtistFolded.isEmpty && (qFolded == resolvedArtistFolded || trimmed.count <= resolvedArtist.count + 3) {
                    return resolvedArtist
                }
            }
            return trimmed.count > 36 ? String(trimmed.prefix(35)) + "…" : trimmed
        }()

        return ResolvedBridgeEndpoint(
            rawQuery: trimmed,
            displayLabel: displayLabel,
            canonicalArtist: resolvedArtist,
            genre: resolvedGenre,
            seedSong: seedSong,
            anchorVector: vec,
            archetype: bestArch,
            neighborhoodQueries: extraQueries
        )
    }

    /// Builds a multi-step Plexamp-style `Sonic Bridge` trajectory between `fromQuery` (Point A) and `toQuery` (Point B)
    /// in the 512-dimensional `NLEmbedding` semantic space.
    public func buildSonicBridge(
        fromQuery: String,
        toQuery: String,
        stepCount: Int = 12,
        storefront: String = ""
    ) async -> [String: Any] {
        let totalStart = Date()
        guard isEnabled else {
            return [
                "status": "disabled",
                "message": "AI-куратор отключён в настройках Mac",
                "songs": []
            ]
        }

        let cleanFrom = fromQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTo = toQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferEnglish = !(cleanFrom + " " + cleanTo).unicodeScalars.contains(where: { $0.value >= 0x0400 && $0.value <= 0x04FF })
            && !MusicKitManager.shared.isSystemLocaleRussian

        guard !cleanFrom.isEmpty && !cleanTo.isEmpty else {
            return [
                "status": "error",
                "message": preferEnglish
                    ? "Enter both Point A and Point B to build a Sonic Bridge."
                    : "Укажите Точку А и Точку Б для построения музыкального маршрута.",
                "songs": []
            ]
        }

        let clampedSteps = max(6, min(20, stepCount))
        let effectiveSf = MusicKitManager.shared.resolveEffectiveStorefront(storefront)

        // 1. Resolve Point A and Point B in parallel
        async let endpointATask = resolveBridgeEndpoint(query: cleanFrom, storefront: effectiveSf, preferEnglish: preferEnglish)
        async let endpointBTask = resolveBridgeEndpoint(query: cleanTo, storefront: effectiveSf, preferEnglish: preferEnglish)
        let (epA, epB) = await (endpointATask, endpointBTask)

        if Task.isCancelled {
            return ["status": "cancelled", "songs": []]
        }

        // 2. Sample geodesic waypoints t in [0.18, 0.34, 0.50, 0.66, 0.82] and select intermediate bridge queries
        let sampleTs: [Double] = [0.18, 0.34, 0.50, 0.66, 0.82]
        var bridgeQueries: [String] = []

        func appendUniqueQuery(_ q: String) {
            let cq = q.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cq.isEmpty else { return }
            if !bridgeQueries.contains(where: { $0.caseInsensitiveCompare(cq) == .orderedSame }) {
                bridgeQueries.append(cq)
            }
        }

        for q in epA.neighborhoodQueries.prefix(2) { appendUniqueQuery(q) }

        var midpointArchetype: SonicArchetype = epA.archetype
        for (wpIdx, t) in sampleTs.enumerated() {
            let wpVec = Self.sphericalInterpolate(epA.anchorVector, epB.anchorVector, t: t)

            // Rank archetypes by cosine closeness to waypoint vector
            let rankedArchetypes = archetypes.sorted { a, b in
                let va = normalizedSentenceVector(for: a.semanticDescriptorEn) ?? wpVec
                let vb = normalizedSentenceVector(for: b.semanticDescriptorEn) ?? wpVec
                return Self.cosineDistanceNormalized(wpVec, va) < Self.cosineDistanceNormalized(wpVec, vb)
            }

            if let topArch = rankedArchetypes.first {
                if wpIdx == 2 {
                    midpointArchetype = topArch
                }
                // Pick 1-2 varied seedQueries from top 2 archetypes near this waypoint
                for arch in rankedArchetypes.prefix(2) {
                    let rotatedOffset = (wpIdx * 3) % max(1, arch.seedQueries.count)
                    for offset in 0..<arch.seedQueries.count {
                        let candidateQ = arch.seedQueries[(rotatedOffset + offset) % arch.seedQueries.count]
                        let beforeCount = bridgeQueries.count
                        appendUniqueQuery(candidateQ)
                        if bridgeQueries.count > beforeCount { break }
                    }
                }
            }
        }

        for q in epB.neighborhoodQueries.prefix(2) { appendUniqueQuery(q) }
        let finalSearchQueries = Array(bridgeQueries.prefix(12))

        // 3. Execute parallel catalog discovery across the trajectory
        var rawCandidates: [[String: Any]] = []
        if !PlaybackRouter.shared.isTestingEnvironment {
            await withTaskGroup(of: BridgeSearchBucket.self) { group in
                for (qIdx, q) in finalSearchQueries.enumerated() {
                    group.addTask { [weak self] in
                        guard let self = self, !Task.isCancelled else {
                            return BridgeSearchBucket(index: qIdx, songs: [])
                        }
                        guard let res = await self.searchCatalogWithTimeout(query: q, storefront: effectiveSf, limit: 6) else {
                            return BridgeSearchBucket(index: qIdx, songs: [])
                        }
                        let songs = (res["songs"] as? [[String: Any]]) ?? []
                        return BridgeSearchBucket(index: qIdx, songs: songs)
                    }
                }

                var buckets: [BridgeSearchBucket] = []
                for await pair in group {
                    if !pair.songs.isEmpty {
                        buckets.append(pair)
                    }
                }
                buckets.sort { $0.index < $1.index }
                for bucket in buckets {
                    rawCandidates.append(contentsOf: bucket.songs)
                }
            }
        }

        if Task.isCancelled {
            return ["status": "cancelled", "songs": []]
        }

        // Local Music.app library fallback if Apple Music catalog is offline or returns too few tracks
        if rawCandidates.count < clampedSteps && !PlaybackRouter.shared.isTestingEnvironment {
            let localTracks = LibraryService.shared.getCachedLibrarySongs().shuffled().prefix(40)
            for ls in localTracks {
                rawCandidates.append([
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
        }

        // 4. Solve optimal geodesic track trajectory from Point A (0%) -> Point B (100%)
        let solvedSongs = solveGeodesicBridgeSequence(
            candidates: rawCandidates,
            endpointA: epA.seedSong,
            endpointB: epB.seedSong,
            vecA: epA.anchorVector,
            vecB: epB.anchorVector,
            stepCount: clampedSteps,
            preferEnglish: preferEnglish
        )

        guard !solvedSongs.isEmpty else {
            return [
                "status": "error",
                "message": "Не удалось построить маршрут: подходящие треки не найдены",
                "songs": [[String: Any]](),
                "step_count": 0
            ]
        }

        let cosineDist = (Self.cosineDistanceNormalized(epA.anchorVector, epB.anchorVector) * 100.0).rounded() / 100.0
        let midTitle = preferEnglish ? midpointArchetype.titleEn : midpointArchetype.titleRu
        let subtitle: String = preferEnglish
            ? "Geodesic \(solvedSongs.count)-track musical bridge from \(epA.displayLabel) to \(epB.displayLabel) via \(midTitle.lowercased())."
            : "Геодезический ИИ-маршрут из \(solvedSongs.count) треков от «\(epA.displayLabel)» к «\(epB.displayLabel)» через \(midTitle.lowercased())."

        let tagStart = preferEnglish ? (epA.archetype.tagsEn.first ?? "Point A") : (epA.archetype.tagsRu.first ?? "Точка А")
        let tagEnd = preferEnglish ? (epB.archetype.tagsEn.first ?? "Point B") : (epB.archetype.tagsRu.first ?? "Точка Б")
        let tags: [String] = [
            "🌉 Sonic Bridge",
            preferEnglish ? "🧭 \(solvedSongs.count) Steps" : "🧭 \(solvedSongs.count) шагов",
            tagStart,
            tagEnd
        ]

        let elapsedMs = Int(Date().timeIntervalSince(totalStart) * 1000)
        NSLog("[SonicBridge] 🌉 Built %d-step bridge '%@' -> '%@' in %dms (cosDist=%.2f, queries=%d, pool=%d)",
              solvedSongs.count, epA.displayLabel, epB.displayLabel, elapsedMs, cosineDist, finalSearchQueries.count, rawCandidates.count)

        return [
            "status": "ok",
            "mode": "sonic_bridge",
            "from_query": cleanFrom,
            "to_query": cleanTo,
            "from_label": epA.displayLabel,
            "to_label": epB.displayLabel,
            "title": "🌉 \(epA.displayLabel) → \(epB.displayLabel)",
            "subtitle": subtitle,
            "tags": tags,
            "engine": activeEngineDescription,
            "seed_queries": finalSearchQueries,
            "step_count": solvedSongs.count,
            "cosine_distance": cosineDist,
            "songs": solvedSongs,
            "albums": []
        ]
    }
}
