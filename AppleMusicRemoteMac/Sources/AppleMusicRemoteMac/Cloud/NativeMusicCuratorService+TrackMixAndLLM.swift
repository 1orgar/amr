import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

extension NativeMusicCuratorService {

    // MARK: - AI Mix from Current Track (Sonic Vibe Curation by Track)

    public func buildTrackVibePlan(
        name: String,
        artist: String,
        album: String,
        genreHint: String = "",
        releaseYearHint: String = "",
        preferEnglish: Bool = false
    ) -> CuratedSessionPlan {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanGenre = genreHint.trimmingCharacters(in: .whitespacesAndNewlines)

        var decadeHint = ""
        let yearPrefix = String(releaseYearHint.prefix(4))
        if let year = Int(yearPrefix), year >= 1950 && year <= 2030 {
            let decade = (year / 10) * 10
            decadeHint = "\(decade)s \(decade % 100)s"
        }

        // Check if artist or album directly appears in any SonicArchetype's seedQueries
        let artistLower = cleanArtist.lowercased()
        let albumLower = cleanAlbum.lowercased()
        var matchedArchetypeHint = ""
        if !artistLower.isEmpty {
            for arch in archetypes {
                if arch.seedQueries.contains(where: { q in
                    let ql = q.lowercased()
                    return ql.contains(artistLower) || (!albumLower.isEmpty && albumLower.count >= 4 && ql.contains(albumLower))
                }) {
                    matchedArchetypeHint = arch.semanticDescriptorEn + " " + arch.titleRu
                    break
                }
            }
        }

        let compositePrompt = [cleanArtist, cleanName, cleanAlbum, cleanGenre, decadeHint, matchedArchetypeHint]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let basePlan = buildNaturalLanguagePlan(for: compositePrompt, preferEnglish: preferEnglish)

        var finalQueries: [String] = []
        if !cleanArtist.isEmpty && !cleanName.isEmpty {
            finalQueries.append("\(cleanArtist) \(cleanName)")
        }
        if !cleanArtist.isEmpty && !cleanAlbum.isEmpty && cleanAlbum.lowercased() != cleanName.lowercased() {
            finalQueries.append("\(cleanArtist) \(cleanAlbum)")
        } else if !cleanArtist.isEmpty {
            finalQueries.append(cleanArtist)
        }

        for q in basePlan.seedQueries {
            if !finalQueries.contains(where: { $0.caseInsensitiveCompare(q) == .orderedSame }) {
                finalQueries.append(q)
            }
            if finalQueries.count >= 10 { break }
        }

        let sessionTitle: String
        if !cleanName.isEmpty {
            sessionTitle = preferEnglish ? "AI Mix: \(cleanName)" : "ИИ-микс: \(cleanName)"
        } else {
            sessionTitle = basePlan.title
        }

        let sessionSubtitle: String
        if !cleanArtist.isEmpty {
            sessionSubtitle = preferEnglish
                ? "Sonic wave inspired by \(cleanArtist) — «\(cleanName)» • \(basePlan.title)"
                : "Семантическая волна по атмосфере \(cleanArtist) — «\(cleanName)» • \(basePlan.title)"
        } else {
            sessionSubtitle = basePlan.subtitle
        }

        var tags: [String] = []
        if !cleanArtist.isEmpty {
            tags.append("🎵 \(cleanArtist)")
        }
        if !cleanGenre.isEmpty {
            let primaryGenre = cleanGenre.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !primaryGenre.isEmpty && primaryGenre.lowercased() != "музыка" && primaryGenre.lowercased() != "music" {
                tags.append("🏷️ \(primaryGenre)")
            }
        }
        for t in basePlan.tags where tags.count < 5 {
            if !tags.contains(t) {
                tags.append(t)
            }
        }

        return CuratedSessionPlan(
            prompt: compositePrompt,
            title: sessionTitle,
            subtitle: sessionSubtitle,
            tags: tags,
            engineBadge: activeEngineDescription,
            seedQueries: finalQueries,
            confidenceScore: max(0.85, basePlan.confidenceScore)
        )
    }

    /// Builds and resolves a 20+ track AI-curated sonic session seeded from a currently playing track.
    public func curateSessionFromTrack(
        name: String,
        artist: String,
        album: String,
        storefront: String = ""
    ) async -> [String: Any] {
        let startTs = Date()
        let preferEnglish = !MusicKitManager.shared.isSystemLocaleRussian
        let sf = MusicKitManager.shared.resolveEffectiveStorefront(storefront)

        // 1. Fast catalog lookup to enrich genre and release year hints for the seed track/artist
        var genreHint = ""
        var releaseYearHint = ""
        let lookupTerm = "\(artist) \(name)".trimmingCharacters(in: .whitespacesAndNewlines)
        if !lookupTerm.isEmpty,
           let lookupRes = await searchCatalogWithTimeout(query: lookupTerm, storefront: sf, limit: 4) {
            if let artists = lookupRes["artists"] as? [[String: Any]],
               let firstGenre = artists.first?["genre"] as? String, !firstGenre.isEmpty {
                genreHint = firstGenre
            }
            if let albums = lookupRes["albums"] as? [[String: Any]],
               let firstRel = albums.first?["release_date"] as? String, !firstRel.isEmpty {
                releaseYearHint = firstRel
            }
        }

        let plan = buildTrackVibePlan(
            name: name,
            artist: artist,
            album: album,
            genreHint: genreHint,
            releaseYearHint: releaseYearHint,
            preferEnglish: preferEnglish
        )

        let queries = Array(plan.seedQueries.prefix(10))
        var queryBuckets: [(Int, [[String: Any]], [[String: Any]])] = []

        await withTaskGroup(of: (Int, [[String: Any]], [[String: Any]]).self) { group in
            for (idx, q) in queries.enumerated() {
                group.addTask { [weak self] in
                    guard let self = self,
                          let res = await self.searchCatalogWithTimeout(query: q, storefront: sf, limit: 12) else {
                        return (idx, [], [])
                    }
                    let rawSongs = (res["songs"] as? [[String: Any]]) ?? []
                    let songs = Self.prioritizeBucketSongsByQuality(rawSongs, shuffleWithinTiers: false)
                    let rawAlbums = (res["albums"] as? [[String: Any]]) ?? []
                    let albums = CloudCatalogService.prioritizeSearchAlbums(rawAlbums, query: q)
                    return (idx, songs, albums)
                }
            }
            for await item in group {
                queryBuckets.append(item)
            }
        }

        queryBuckets.sort { $0.0 < $1.0 }
        var curatedSongs = filterAndInterleaveWaveSongs(queryBuckets: queryBuckets, excluding: [], maxCount: 24)

        if curatedSongs.isEmpty && !Task.isCancelled && !PlaybackRouter.shared.isTestingEnvironment {
            var localPool = LibraryService.shared.getCachedLibrarySongs()
            if localPool.isEmpty {
                localPool = QueueManager.shared.getRecentlyPlayed(limit: 25)
                if localPool.isEmpty && !AppleScriptExecutor.shared.isBusy {
                    Task.detached(priority: .background) {
                        _ = LibraryService.shared.getLibrarySongs()
                    }
                }
            }
            for ls in localPool.shuffled().prefix(20) {
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
                curatedSongs = orderSongsBySemanticFlow(curatedSongs)
                NSLog("[AICurator] 💿 Catalog unreachable in curateSessionFromTrack; populated %d tracks from local Music.app library", curatedSongs.count)
            }
        }

        var curatedAlbums: [[String: Any]] = []
        var albumKeyToIndex: [String: Int] = [:]
        for (_, _, albums) in queryBuckets {
            for alb in albums.prefix(3) {
                let aName = (alb["name"] as? String ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let aArtist = (alb["artist"] as? String ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !aName.isEmpty else { continue }
                let key = "\(aArtist)|\(aName)"
                if let existingIdx = albumKeyToIndex[key] {
                    if CloudCatalogService.audioQualityScore(for: alb) > CloudCatalogService.audioQualityScore(for: curatedAlbums[existingIdx]) {
                        curatedAlbums[existingIdx] = alb
                    }
                    continue
                }
                if curatedAlbums.count < 8 {
                    albumKeyToIndex[key] = curatedAlbums.count
                    curatedAlbums.append(alb)
                }
            }
        }
        curatedAlbums = CloudCatalogService.prioritizeSearchAlbums(curatedAlbums, query: "")

        let elapsedMs = Int(Date().timeIntervalSince(startTs) * 1000)
        NSLog("[AICurator] 🎵 curateSessionFromTrack('%@' - '%@') done in %dms -> %d songs, %d albums",
              artist, name, elapsedMs, curatedSongs.count, curatedAlbums.count)

        return [
            "status": "ok",
            "prompt": plan.prompt,
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

    // MARK: - Stage 1: Apple Intelligence FoundationModels (macOS 26+)

    private static func sanitizeFoundationModelQuery(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Line 4:", "line 4:", "Строка 4:", "строка 4:", "Queries:", "Запросы:"] {
            if s.hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let regex = try? NSRegularExpression(pattern: "^\\d+[\\.\\)\\-]\\s*") {
            s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: s.utf16.count), withTemplate: "")
        }
        s = s.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "«", with: "")
            .replacingOccurrences(of: "»", with: "")
            .replacingOccurrences(of: " - ", with: " ")
            .replacingOccurrences(of: " — ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s
    }

    internal func tryFoundationModelsPlan(
        for prompt: String,
        preferEnglish: Bool,
        fallbackQueries: [String] = []
    ) async -> CuratedSessionPlan? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard !PlaybackRouter.shared.isTestingEnvironment else { return nil }
            // Guard 8GB/16GB M1 Macs from swapping in the ~3GB FoundationModels LLM during interactive search/playback
            guard ProcessInfo.processInfo.physicalMemory > 16 * 1024 * 1024 * 1024 else { return nil }
            guard case .available = SystemLanguageModel.default.availability else {
                return nil
            }

            let canProceed: Bool = lock.withLock {
                if isFoundationModelsInFlight || Date() < foundationModelsCooldownUntil {
                    return false
                }
                isFoundationModelsInFlight = true
                return true
            }
            guard canProceed else { return nil }

            let instructions = preferEnglish
                ? Self.curatorInstructionsEn
                : Self.curatorInstructionsRu

            // Strict 2.2-second non-blocking timeout so M1 LLM cold-start or XPC stall never blocks curation
            let gate = OnceResumeGate<String?>()
            final class LLMTaskState: @unchecked Sendable {
                private let lock = NSLock()
                private var llmTask: Task<Void, Never>?
                private var continuation: CheckedContinuation<String?, Never>?
                private var timedOut = false

                func setContinuation(_ c: CheckedContinuation<String?, Never>) {
                    lock.withLock { continuation = c }
                }
                func setTask(_ t: Task<Void, Never>) {
                    lock.withLock { llmTask = t }
                }
                func markTimedOut() {
                    lock.withLock { timedOut = true }
                }
                var didTimeOut: Bool {
                    lock.withLock { timedOut }
                }
                func takeForCancel() -> (Task<Void, Never>?, CheckedContinuation<String?, Never>?) {
                    lock.withLock { (llmTask, continuation) }
                }
            }
            let taskState = LLMTaskState()

            let rawContent: String? = await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                    taskState.setContinuation(continuation)
                    if Task.isCancelled {
                        self.lock.withLock { self.isFoundationModelsInFlight = false }
                        _ = gate.tryResume(continuation, with: nil)
                        return
                    }
                    let llmTask = Task.detached(priority: .userInitiated) {
                        defer {
                            self.lock.withLock { self.isFoundationModelsInFlight = false }
                        }
                        do {
                            let session = LanguageModelSession(instructions: instructions)
                            let response = try await session.respond(to: prompt)
                            _ = gate.tryResume(continuation, with: response.content)
                        } catch {
                            if !Task.isCancelled {
                                NSLog("[AICurator] FoundationModels error: %@", error.localizedDescription)
                            }
                            _ = gate.tryResume(continuation, with: nil)
                        }
                    }
                    taskState.setTask(llmTask)
                    if Task.isCancelled {
                        llmTask.cancel()
                        _ = gate.tryResume(continuation, with: nil)
                        return
                    }
                    Task.detached(priority: .utility) {
                        try? await Task.sleep(nanoseconds: 2_200_000_000)
                        taskState.markTimedOut()
                        if gate.tryResume(continuation, with: nil) {
                            llmTask.cancel()
                            NSLog("[AICurator] ⏱ FoundationModels timed out (>2.2s on M1); engaging 10-min cooldown & falling back to NaturalLanguage 512-D")
                        }
                    }
                }
            } onCancel: {
                let (t, cont) = taskState.takeForCancel()
                t?.cancel()
                if let cont = cont {
                    _ = gate.tryResume(cont, with: nil)
                }
            }

            guard let content = rawContent else {
                if taskState.didTimeOut || !Task.isCancelled {
                    lock.withLock {
                        foundationModelsCooldownUntil = Date().addingTimeInterval(600)
                    }
                }
                return nil
            }

            let lines = content
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if lines.count >= 4 {
                let title = lines[0]
                    .replacingOccurrences(of: "Line 1:", with: "")
                    .replacingOccurrences(of: "Строка 1:", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let subtitle = lines[1]
                    .replacingOccurrences(of: "Line 2:", with: "")
                    .replacingOccurrences(of: "Строка 2:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let tags = lines[2]
                    .replacingOccurrences(of: "Line 3:", with: "")
                    .replacingOccurrences(of: "Строка 3:", with: "")
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                var queries = lines[3]
                    .components(separatedBy: "|")
                    .map { Self.sanitizeFoundationModelQuery($0) }
                    .filter { $0.count >= 3 }

                // Append NaturalLanguage archetype fallback queries so we always have 10 reliable catalog queries
                for fq in fallbackQueries where queries.count < 10 {
                    if !queries.contains(where: { $0.caseInsensitiveCompare(fq) == .orderedSame }) {
                        queries.append(fq)
                    }
                }

                if !queries.isEmpty && !title.isEmpty {
                    return CuratedSessionPlan(
                        prompt: prompt,
                        title: title,
                        subtitle: subtitle,
                        tags: tags.isEmpty ? (preferEnglish ? ["✨ Apple Intelligence", "Hi-Res Curated"] : ["✨ Apple Intelligence", "Hi-Res Подбор"]) : tags,
                        engineBadge: "Apple Intelligence • FoundationModels",
                        seedQueries: queries,
                        confidenceScore: 0.96
                    )
                }
            }
        }
        #endif
        return nil
    }
}
