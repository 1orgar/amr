import Foundation
import NaturalLanguage

extension NativeMusicCuratorService {

    // MARK: - Geodesic 512-D Vector Interpolation (SLERP)

    /// Computes spherical linear interpolation (SLERP) along the unit hypersphere between two 512-D vectors.
    /// Falls back smoothly to normalized linear interpolation when vectors are nearly collinear or antipodal.
    public static func sphericalInterpolate(
        _ vecA: [Double],
        _ vecB: [Double],
        t rawT: Double
    ) -> [Double] {
        let count = min(vecA.count, vecB.count)
        guard count > 0 else { return vecA }
        let t = max(0.0, min(1.0, rawT))
        if t <= 0.0 { return Array(vecA.prefix(count)) }
        if t >= 1.0 { return Array(vecB.prefix(count)) }

        var dot: Double = 0.0
        for i in 0..<count {
            dot += vecA[i] * vecB[i]
        }
        dot = max(-1.0, min(1.0, dot))

        if dot > 0.9995 || dot < -0.9995 {
            var blended = [Double](repeating: 0.0, count: count)
            var normSq: Double = 0.0
            for i in 0..<count {
                let v = (1.0 - t) * vecA[i] + t * vecB[i]
                blended[i] = v
                normSq += v * v
            }
            if normSq >= 1e-18, let norm = Self.l2Normalize(blended) {
                return norm
            }
            // Antipodal midpoint safety perturbation along an orthogonal equator axis
            let orthIdx = (count > 1 && abs(vecA[0]) > 0.9) ? 1 : 0
            blended[orthIdx] += 1.0
            var vecANormSq: Double = 0.0
            for i in 0..<count {
                vecANormSq += vecA[i] * vecA[i]
            }
            if count > 1 && vecANormSq > 1e-18 {
                var proj: Double = 0.0
                for i in 0..<count {
                    proj += blended[i] * vecA[i]
                }
                let scale = proj / vecANormSq
                for i in 0..<count {
                    blended[i] -= scale * vecA[i]
                }
            }
            return Self.l2Normalize(blended) ?? Array(vecA.prefix(count))
        }

        let theta = acos(dot)
        let sinTheta = sin(theta)
        guard abs(sinTheta) > 1e-9 else {
            return Array(vecA.prefix(count))
        }
        let wA = sin((1.0 - t) * theta) / sinTheta
        let wB = sin(t * theta) / sinTheta

        var out = [Double](repeating: 0.0, count: count)
        for i in 0..<count {
            out[i] = wA * vecA[i] + wB * vecB[i]
        }
        return Self.l2Normalize(out) ?? out
    }

    // MARK: - Semantic 512-D Coordinate Resolution

    /// Maps any track dictionary (`artist`, `name`, `album`, `genre`) or text query into a normalized 512-D `NLEmbedding` coordinate.
    public func computeTrackSemanticVector(_ song: [String: Any]) -> [Double]? {
        let rawArtist = (song["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawName = (song["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawAlbum = (song["album"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawGenre = (song["genre"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawHint = (song["semantic_hint"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        return computeSemanticAnchorVector(
            queryText: [rawArtist, rawName, rawAlbum, rawGenre, rawHint].filter { !$0.isEmpty }.joined(separator: " "),
            resolvedArtist: rawArtist,
            resolvedGenre: rawGenre
        )
    }

    internal static func foldSemanticText(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    internal static func isValidSemanticToken(_ token: String) -> Bool {
        token.count >= 2 && token.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }

    private static func deterministicSemanticTokenVector(for token: String, dimension: Int) -> [Double]? {
        guard !token.isEmpty, dimension > 0 else { return nil }
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in token.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        var state = hash
        var raw = [Double](repeating: 0.0, count: dimension)
        for i in 0..<dimension {
            state &+= 0x9e3779b97f4a7c15
            var z = state
            z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
            z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
            z = z ^ (z >> 31)
            let unit = Double(z >> 11) / 9007199254740992.0
            raw[i] = unit * 2.0 - 1.0
        }
        return Self.l2Normalize(raw)
    }

    internal func computeSemanticAnchorVector(
        queryText: String,
        resolvedArtist: String = "",
        resolvedGenre: String = ""
    ) -> [Double]? {
        let artistLower = resolvedArtist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let queryLower = queryText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let genreLower = resolvedGenre.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let artistFolded = Self.foldSemanticText(resolvedArtist)
        let queryFolded = Self.foldSemanticText(queryText)
        let genreFolded = Self.foldSemanticText(resolvedGenre)

        var matchedArch: SonicArchetype?
        if !artistLower.isEmpty,
           let prof = findArtistStyleProfile(for: artistLower) ?? (!artistFolded.isEmpty ? findArtistStyleProfile(for: artistFolded) : nil),
           let arch = archetypes.first(where: { $0.id == prof.archetypeId }) {
            matchedArch = arch
        }
        if matchedArch == nil,
           let profInPrompt = findArtistStyleProfileInPrompt(lowerPrompt: queryLower) ?? (!queryFolded.isEmpty ? findArtistStyleProfileInPrompt(lowerPrompt: queryFolded) : nil),
           let arch = archetypes.first(where: { $0.id == profInPrompt.archetypeId }) {
            matchedArch = arch
        }
        if matchedArch == nil && !artistFolded.isEmpty {
            matchedArch = archetypes.first { arch in
                arch.seedQueries.contains { Self.foldSemanticText($0).contains(artistFolded) }
            }
        }
        if matchedArch == nil && !genreLower.isEmpty {
            matchedArch = bestArchetypeForCatalogGenre(genreLower) ?? (!genreFolded.isEmpty ? bestArchetypeForCatalogGenre(genreFolded) : nil)
        }
        if matchedArch == nil {
            matchedArch = bestArchetypeForCatalogGenre(queryLower) ?? (!queryFolded.isEmpty ? bestArchetypeForCatalogGenre(queryFolded) : nil)
        }

        let primaryRawLower = [
            queryText,
            resolvedArtist,
            resolvedGenre
        ]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()

        let combinedRaw = [
            primaryRawLower,
            matchedArch?.semanticDescriptorEn ?? "",
            matchedArch?.keywordsEn.joined(separator: " ") ?? ""
        ]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()

        let rawTokens = combinedRaw
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter(Self.isValidSemanticToken)
        let translated = translatePromptToEnglishSemanticSpace(lowerPrompt: combinedRaw, tokens: rawTokens)

        let primaryRawTokens = primaryRawLower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter(Self.isValidSemanticToken)
        let translatedPrimary = translatePromptToEnglishSemanticSpace(lowerPrompt: primaryRawLower, tokens: primaryRawTokens)

        let primaryFolded = Self.foldSemanticText(
            [queryText, resolvedArtist, resolvedGenre, translatedPrimary]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        )
        let englishText = Self.foldSemanticText(
            (combinedRaw + " " + translated).trimmingCharacters(in: .whitespacesAndNewlines)
        )

        let primaryTokens = Array(
            Set(
                primaryFolded
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter(Self.isValidSemanticToken)
            )
        ).sorted()

        let uniqueTokens = Array(
            Set(
                englishText
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter(Self.isValidSemanticToken)
            )
        ).sorted()

        let orderedTokens = primaryTokens + uniqueTokens.filter { !primaryTokens.contains($0) }

        let baseSentVec: [Double]? = {
            if let arch = matchedArch, let v = normalizedSentenceVector(for: arch.semanticDescriptorEn) {
                return v
            }
            return normalizedSentenceVector(for: englishText)
        }()

        let targetDim = baseSentVec?.count
            ?? normalizedSentenceVector(for: "audiophile music recording")?.count
            ?? 512

        // Blend up to 6 word vectors (prioritizing primary query/artist tokens first) so tracks within the same archetype
        // and international/short artist names ("Ólafur", "Björk", "Röyksopp", "U2", "ДДТ", CJK) differentiate cleanly.
        var wordVectors: [[Double]] = []
        var usedTokens = Set<String>()

        nlEngineLock.lock()
        for tok in primaryTokens {
            if let pre = preloadedWordVectors[tok], pre.count == targetDim {
                wordVectors.append(pre)
                usedTokens.insert(tok)
                if wordVectors.count >= 4 { break }
            }
        }
        nlEngineLock.unlock()

        for tok in primaryTokens where !usedTokens.contains(tok) && wordVectors.count < 4 {
            if let wv = normalizedWordVector(for: tok), wv.count == targetDim {
                wordVectors.append(wv)
                usedTokens.insert(tok)
            } else if let detVec = Self.deterministicSemanticTokenVector(for: tok, dimension: targetDim) {
                wordVectors.append(detVec)
                usedTokens.insert(tok)
            }
        }

        if wordVectors.count < 6 {
            nlEngineLock.lock()
            for tok in orderedTokens where !usedTokens.contains(tok) {
                if let pre = preloadedWordVectors[tok], pre.count == targetDim {
                    wordVectors.append(pre)
                    usedTokens.insert(tok)
                    if wordVectors.count >= 6 { break }
                }
            }
            nlEngineLock.unlock()
        }

        if wordVectors.count < 3 {
            for tok in orderedTokens where !usedTokens.contains(tok) && wordVectors.count < 5 {
                if let wv = normalizedWordVector(for: tok), wv.count == targetDim {
                    wordVectors.append(wv)
                    usedTokens.insert(tok)
                }
            }
        }

        if let sVec = baseSentVec, !wordVectors.isEmpty {
            let dim = sVec.count
            var acc = [Double](repeating: 0.0, count: dim)
            for i in 0..<dim {
                acc[i] = sVec[i] * 0.68
            }
            let wScale = 0.32 / Double(wordVectors.count)
            for wv in wordVectors where wv.count == dim {
                for i in 0..<dim {
                    acc[i] += wv[i] * wScale
                }
            }
            if let norm = Self.l2Normalize(acc) {
                return norm
            }
            return sVec
        }

        if let sVec = baseSentVec {
            return sVec
        }

        if !wordVectors.isEmpty {
            let dim = wordVectors[0].count
            var acc = [Double](repeating: 0.0, count: dim)
            for wv in wordVectors where wv.count == dim {
                for i in 0..<dim {
                    acc[i] += wv[i]
                }
            }
            return Self.l2Normalize(acc)
        }

        return normalizedSentenceVector(for: "audiophile music recording")
    }

    // MARK: - Geodesic Path Solver (Deterministic & Unit-Testable)

    /// Orders and selects `stepCount` tracks from `candidates` along the geodesic trajectory `vecA -> vecB` (`0% -> 100%`),
    /// pinning optional `endpointA` at step 1 and `endpointB` at the final step, avoiding duplicate songs and back-to-back same-artist tracks.
    public func solveGeodesicBridgeSequence(
        candidates: [[String: Any]],
        endpointA: [String: Any]? = nil,
        endpointB: [String: Any]? = nil,
        vecA: [Double],
        vecB: [Double],
        stepCount: Int = 12,
        preferEnglish: Bool = false
    ) -> [[String: Any]] {
        let targetSteps = max(4, min(20, stepCount))
        let dim = min(vecA.count, vecB.count)
        guard dim > 0 else { return Array(candidates.prefix(targetSteps)) }

        struct BridgeCandidate {
            let song: [String: Any]
            let dedupKey: String
            let titleKey: String
            let songId: String
            let normArtist: String
            let vec: [Double]
            let projT: Double
        }

        // Scalar projection coordinate along chord (vecB - vecA): 0.0 at vecA, 1.0 at vecB
        var chord = [Double](repeating: 0.0, count: dim)
        var chordNormSq: Double = 0.0
        for i in 0..<dim {
            let d = vecB[i] - vecA[i]
            chord[i] = d
            chordNormSq += d * d
        }

        func makeCandidate(from rawSong: [String: Any], fallbackVec: [Double]) -> BridgeCandidate? {
            let rawName = (rawSong["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let rawArtist = (rawSong["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawName.isEmpty else { return nil }

            let normName = normalizeSongTitleForDedup(rawName)
            let normArtist = normalizeArtistForDedup(rawArtist)
            let songId = String(describing: rawSong["id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let dedupKey = "\(normArtist)|\(normName)"
            let titleKey = normName.count >= 4 ? "title|\(normName)" : dedupKey

            let resolvedVec: [Double]
            if let preVec = rawSong["_test_vec"] as? [Double], preVec.count == dim, let normPre = Self.l2Normalize(preVec) {
                resolvedVec = normPre
            } else if let computed = computeTrackSemanticVector(rawSong), computed.count == dim {
                resolvedVec = computed
            } else {
                resolvedVec = fallbackVec
            }

            let projT: Double
            if chordNormSq > 1e-8 {
                var num: Double = 0.0
                for i in 0..<dim {
                    num += (resolvedVec[i] - vecA[i]) * chord[i]
                }
                projT = max(0.0, min(1.0, num / chordNormSq))
            } else {
                projT = 0.5
            }

            var cleanedSong = rawSong
            cleanedSong.removeValue(forKey: "_test_vec")

            return BridgeCandidate(
                song: cleanedSong,
                dedupKey: dedupKey,
                titleKey: titleKey,
                songId: songId,
                normArtist: normArtist,
                vec: resolvedVec,
                projT: projT
            )
        }

        var pool: [BridgeCandidate] = []
        var seenPoolKeys = Set<String>()

        func insertIntoPool(_ raw: [String: Any], fallback: [Double]) -> BridgeCandidate? {
            guard let cand = makeCandidate(from: raw, fallbackVec: fallback) else { return nil }
            if seenPoolKeys.contains(cand.dedupKey) || seenPoolKeys.contains(cand.titleKey) || (!cand.songId.isEmpty && seenPoolKeys.contains(cand.songId)) {
                return pool.first {
                    $0.dedupKey == cand.dedupKey || $0.titleKey == cand.titleKey || (!cand.songId.isEmpty && $0.songId == cand.songId)
                }
            }
            seenPoolKeys.insert(cand.dedupKey)
            seenPoolKeys.insert(cand.titleKey)
            if !cand.songId.isEmpty { seenPoolKeys.insert(cand.songId) }
            pool.append(cand)
            return cand
        }

        let pinnedStart = endpointA.flatMap { insertIntoPool($0, fallback: vecA) }
        let pinnedEndRaw = endpointB.flatMap { insertIntoPool($0, fallback: vecB) }
        let pinnedEnd: BridgeCandidate? = {
            guard let pe = pinnedEndRaw else { return nil }
            if let ps = pinnedStart, ps.dedupKey == pe.dedupKey {
                return nil
            }
            return pe
        }()

        for song in candidates {
            _ = insertIntoPool(song, fallback: Self.sphericalInterpolate(vecA, vecB, t: 0.5))
        }

        guard !pool.isEmpty else { return [] }
        let effectiveSteps = min(targetSteps, pool.count)
        if effectiveSteps <= 1 {
            return annotateBridgeSteps([pool[0].song], preferEnglish: preferEnglish)
        }

        var usedIndices = Set<Int>()
        var artistUsage: [String: Int] = [:]
        var chosen: [BridgeCandidate?] = Array(repeating: nil, count: effectiveSteps)

        func markUsed(_ idx: Int) {
            usedIndices.insert(idx)
            let art = pool[idx].normArtist
            if !art.isEmpty {
                artistUsage[art, default: 0] += 1
            }
        }

        // Pin or select Step 0 (Point A, t = 0.0)
        if let ps = pinnedStart, let idx = pool.firstIndex(where: { $0.dedupKey == ps.dedupKey }) {
            chosen[0] = pool[idx]
            markUsed(idx)
        } else {
            var bestIdx = 0
            var bestDist = Double.infinity
            for (idx, cand) in pool.enumerated() {
                let d = Self.cosineDistanceNormalized(cand.vec, vecA) + cand.projT * 0.35
                if d < bestDist {
                    bestDist = d
                    bestIdx = idx
                }
            }
            chosen[0] = pool[bestIdx]
            markUsed(bestIdx)
        }

        // Pin or reserve Final Step (Point B, t = 1.0) BEFORE filling intermediate waypoints
        if let pe = pinnedEnd,
           let idx = pool.firstIndex(where: { $0.dedupKey == pe.dedupKey }),
           !usedIndices.contains(idx) {
            chosen[effectiveSteps - 1] = pool[idx]
            markUsed(idx)
        } else {
            var bestEndIdx: Int?
            var bestEndScore = -Double.infinity
            let startArt = chosen[0]?.normArtist ?? ""
            for (idx, cand) in pool.enumerated() where !usedIndices.contains(idx) {
                var s = -Self.cosineDistanceNormalized(cand.vec, vecB) * 3.0 + cand.projT * 1.2
                if effectiveSteps == 2 && !startArt.isEmpty && cand.normArtist == startArt {
                    s -= 8.0
                }
                if s > bestEndScore {
                    bestEndScore = s
                    bestEndIdx = idx
                }
            }
            if let endIdx = bestEndIdx {
                chosen[effectiveSteps - 1] = pool[endIdx]
                markUsed(endIdx)
            }
        }

        // Fill intermediate geodesic waypoints k = 1 ..< (effectiveSteps - 1)
        if effectiveSteps > 2 {
            let finalEndArtist = chosen[effectiveSteps - 1]?.normArtist ?? ""
            let finalEndVec = chosen[effectiveSteps - 1]?.vec ?? vecB

            for step in 1..<(effectiveSteps - 1) {
                let t = Double(step) / Double(effectiveSteps - 1)
                let waypointVec = Self.sphericalInterpolate(vecA, vecB, t: t)
                let prevCand = chosen[step - 1]

                var bestIdx: Int?
                var bestScore = -Double.infinity

                for (idx, cand) in pool.enumerated() where !usedIndices.contains(idx) {
                    // 1. Geodesic cosine closeness to spherical waypoint
                    let distToWaypoint = Self.cosineDistanceNormalized(cand.vec, waypointVec)
                    var score = -distToWaypoint * 3.4

                    // 2. Scalar progression alignment along A -> B
                    score -= abs(cand.projT - t) * 2.0

                    // 3. Smooth step-to-step transition from previous track & monotonic forward flow
                    if let prev = prevCand {
                        let stepDist = Self.cosineDistanceNormalized(prev.vec, cand.vec)
                        score -= stepDist * 0.85
                        if cand.projT < prev.projT - 0.06 {
                            score -= (prev.projT - cand.projT) * 2.2
                        }
                        if !prev.normArtist.isEmpty && prev.normArtist == cand.normArtist {
                            score -= 14.0
                        }
                    }

                    // 4. Smooth hand-off into final pinned track at step == effectiveSteps - 2
                    if step == effectiveSteps - 2 {
                        score -= Self.cosineDistanceNormalized(cand.vec, finalEndVec) * 0.75
                        if !finalEndArtist.isEmpty && cand.normArtist == finalEndArtist {
                            score -= 14.0
                        }
                    }

                    // 5. Artist diversity across the whole bridge
                    let usedCount = artistUsage[cand.normArtist] ?? 0
                    if usedCount >= 2 {
                        score -= 7.0
                    } else if usedCount == 1 {
                        score -= 1.4
                    }

                    if score > bestScore {
                        bestScore = score
                        bestIdx = idx
                    }
                }

                if let picked = bestIdx {
                    chosen[step] = pool[picked]
                    markUsed(picked)
                }
            }
        }

        let orderedSongs = chosen.compactMap { $0?.song }
        return annotateBridgeSteps(orderedSongs, preferEnglish: preferEnglish)
    }

    private func annotateBridgeSteps(_ songs: [[String: Any]], preferEnglish: Bool) -> [[String: Any]] {
        let total = songs.count
        guard total > 0 else { return [] }
        return songs.enumerated().map { idx, raw in
            var dict = raw
            let t = total > 1 ? (Double(idx) / Double(total - 1)) : 0.0
            let pct = Int((t * 100.0).rounded())
            dict["bridge_step"] = idx + 1
            dict["bridge_total"] = total
            dict["bridge_progress"] = pct
            let stage: String = {
                if idx == 0 {
                    return preferEnglish ? "Point A • 0%" : "Точка А • 0%"
                } else if idx == total - 1 {
                    return preferEnglish ? "Point B • 100%" : "Точка Б • 100%"
                } else if abs(pct - 50) <= 9 {
                    return preferEnglish ? "Midpoint • \(pct)%" : "Экватор • \(pct)%"
                } else if pct < 50 {
                    return preferEnglish ? "Departure • \(pct)%" : "Отбытие • \(pct)%"
                } else {
                    return preferEnglish ? "Approach • \(pct)%" : "Сближение • \(pct)%"
                }
            }()
            dict["bridge_stage"] = stage
            return dict
        }
    }
}
