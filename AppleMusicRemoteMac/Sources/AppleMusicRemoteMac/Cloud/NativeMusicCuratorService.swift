//
//  NativeMusicCuratorService.swift
//  AppleMusicRemoteMac
//
//  100% Native macOS AI Sonic Curator & Semantic Prompt Engine
//  powered by Apple FoundationModels (Apple Intelligence LLM) +
//  NaturalLanguage framework (512-D NLEmbedding & NLTagger).
//

import Foundation
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

public struct SonicArchetype: Sendable {
    public let id: String
    public let titleRu: String
    public let titleEn: String
    public let descriptionRu: String
    public let descriptionEn: String
    public let semanticDescriptorEn: String
    public let keywordsRu: [String]
    public let keywordsEn: [String]
    public let tagsRu: [String]
    public let tagsEn: [String]
    public let seedQueries: [String]
}

public struct CuratedSessionPlan: Sendable {
    public let prompt: String
    public let title: String
    public let subtitle: String
    public let tags: [String]
    public let engineBadge: String
    public let seedQueries: [String]
    public let confidenceScore: Double
}

internal struct ArtistStyleProfile: Sendable {
    let canonicalArtist: String
    let aliases: [String]
    let archetypeId: String
    let styleTitleRu: String
    let styleTitleEn: String
    let customDescriptionRu: String?
    let customDescriptionEn: String?
    let seedQueries: [String]
}

internal struct ArtistStyleIntent: Sendable {
    let targetArtist: String
    let moodContext: String
    let isExplicitStylePrefix: Bool
    let isIncompletePrefixOnly: Bool
}

public final class NativeMusicCuratorService: @unchecked Sendable {
    public static let shared = NativeMusicCuratorService()

    internal let lock = NSLock()
    /// Serializes all access to Apple's `NLEmbedding` and `NLTagger` (which are NOT thread-safe across concurrent tasks on Apple Silicon)
    internal let nlEngineLock = NSLock()
    internal let enabledStorageKey = "amr_ai_curator_enabled_v1"
    internal let pinnedStorageKey = "amr_ai_curator_pinned_v1"
    internal var _isEnabled: Bool
    internal var _pinnedPrompts: [PromptSuggestionItem] = []
    internal let archetypes: [SonicArchetype]
    internal let artistStyleProfiles: [ArtistStyleProfile]
    internal var preloadedSentenceVectors: [String: [Double]] = [:]
    internal var preloadedWordVectors: [String: [Double]] = [:]
    internal var cachedSentenceVectors: [String: [Double]] = [:]
    internal var cachedWordVectors: [String: [Double]] = [:]
    internal var isPreloadingWeights: Bool = false
    internal var hasPreloadedWeights: Bool = false
    internal var foundationModelsCooldownUntil: Date = .distantPast
    internal var isFoundationModelsInFlight: Bool = false
    internal var recentPromptsHistory: [String] = []
    internal let historyLock = NSLock()
    internal var cachedEngineDescriptionCache: (timestamp: Date, desc: String)?

    internal static let curatorInstructionsEn = "You are an audiophile music curator for Apple Music. Respond ONLY with 4 lines: Line 1: Session Title. Line 2: One-sentence audiophile description of the mood and soundstage. Line 3: 4 short tags separated by |. Line 4: 6 specific Apple Music search queries (Artist Song or Artist Album) separated by |."
    internal static let curatorInstructionsRu = "Ты аудиофильский музыкальный куратор Apple Music. Ответь СТРОГО в 4 строки без лишнего текста: Строка 1: Название подборки. Строка 2: Одно предложение с описанием звучания, сцены и атмосферы. Строка 3: 4 коротких тега через |. Строка 4: 6 точных поисковых запросов для Apple Music (Артист Трек или Артист Альбом) через |."

    private init() {
        if AppStorageProvider.shared.object(forKey: enabledStorageKey) != nil {
            self._isEnabled = AppStorageProvider.shared.bool(forKey: enabledStorageKey)
        } else {
            self._isEnabled = true
        }
        if let savedPinned = AppStorageProvider.shared.array(forKey: pinnedStorageKey) as? [[String: String]] {
            self._pinnedPrompts = savedPinned.compactMap { dict in
                guard let pRu = dict["prompt_ru"], !pRu.isEmpty else { return nil }
                let lRu = dict["label_ru"] ?? "✨ \(pRu)"
                let pEn = dict["prompt_en"] ?? pRu
                let lEn = dict["label_en"] ?? lRu
                return PromptSuggestionItem(labelRu: lRu, promptRu: pRu, labelEn: lEn, promptEn: pEn)
            }
        }
        self.archetypes = Self.buildArchetypes()
        self.artistStyleProfiles = Self.buildArtistStyleProfiles()
    }

    // MARK: - Thread-Safe Cached 512-D NLEmbedding Vector Math (M1 Optimized)

    internal static func l2Normalize(_ vec: [Double]) -> [Double]? {
        var sumSq: Double = 0.0
        for v in vec {
            if !v.isFinite { return nil }
            sumSq += v * v
        }
        guard sumSq > 1e-12 else { return nil }
        let invNorm = 1.0 / sqrt(sumSq)
        return vec.map { $0 * invNorm }
    }

    /// Computes cosine distance in `[0.0, 2.0]` (matching `NLEmbedding.distance(..., distanceType: .cosine)`)
    /// between two L2-normalized vectors in pure Swift (~500 ns, zero CoreML/ANE overhead).
    @inline(__always)
    internal static func cosineDistanceNormalized(_ a: [Double], _ b: [Double]) -> Double {
        let count = min(a.count, b.count)
        guard count > 0 else { return 2.0 }
        var dot: Double = 0.0
        for i in 0..<count {
            dot += a[i] * b[i]
        }
        return max(0.0, min(2.0, 1.0 - dot))
    }

    internal func normalizedSentenceVector(for text: String) -> [Double]? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        nlEngineLock.lock()
        defer { nlEngineLock.unlock() }
        if let permanent = preloadedSentenceVectors[clean] {
            return permanent
        }
        if let cached = cachedSentenceVectors[clean] {
            return cached.isEmpty ? nil : cached
        }
        guard let sentEmb = NLEmbedding.sentenceEmbedding(for: .english),
              let rawVec = sentEmb.vector(for: clean),
              let normVec = Self.l2Normalize(rawVec) else {
            if cachedSentenceVectors.count > 600 { cachedSentenceVectors.removeAll(keepingCapacity: true) }
            cachedSentenceVectors[clean] = []
            return nil
        }
        if cachedSentenceVectors.count > 600 { cachedSentenceVectors.removeAll(keepingCapacity: true) }
        cachedSentenceVectors[clean] = normVec
        return normVec
    }

    internal func normalizedWordVector(for word: String) -> [Double]? {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard clean.count >= 2 else { return nil }
        nlEngineLock.lock()
        defer { nlEngineLock.unlock() }
        if let permanent = preloadedWordVectors[clean] {
            return permanent
        }
        if let cached = cachedWordVectors[clean] {
            return cached.isEmpty ? nil : cached
        }
        guard let wordEmb = NLEmbedding.wordEmbedding(for: .english),
              let rawVec = wordEmb.vector(for: clean),
              let normVec = Self.l2Normalize(rawVec) else {
            if cachedWordVectors.count > 1200 { cachedWordVectors.removeAll(keepingCapacity: true) }
            cachedWordVectors[clean] = []
            return nil
        }
        if cachedWordVectors.count > 1200 { cachedWordVectors.removeAll(keepingCapacity: true) }
        cachedWordVectors[clean] = normVec
        return normVec
    }

    /// Preloads all Neural Engine / NaturalLanguage 512-D / Vision Saliency / FoundationModels weights at app startup
    /// when AI functions are enabled, before accepting client connections.
    public func preloadModelWeightsSynchronously() {
        guard isEnabled, !PlaybackRouter.shared.isTestingEnvironment else { return }
        let shouldPreload: Bool = lock.withLock {
            if isPreloadingWeights || hasPreloadedWeights { return false }
            isPreloadingWeights = true
            return true
        }
        guard shouldPreload else { return }

        let t0 = Date()
        NSLog("[AICurator] 🧠 Preloading AI model weights (NLEmbedding 512-D, NLTagger, Vision ANE Saliency, FoundationModels)...")

        // 1. Load NLEmbedding sentence & word models and precompute all archetype & preset 512-D vectors permanently
        var sentCount = 0
        var wordCount = 0
        nlEngineLock.lock()
        let sentEmb = NLEmbedding.sentenceEmbedding(for: .english)
        let wordEmb = NLEmbedding.wordEmbedding(for: .english)

        if let sEmb = sentEmb {
            for arch in archetypes {
                let key = arch.semanticDescriptorEn.trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty, preloadedSentenceVectors[key] == nil,
                   let raw = sEmb.vector(for: key), let norm = Self.l2Normalize(raw) {
                    preloadedSentenceVectors[key] = norm
                    sentCount += 1
                }
            }
            for item in Self.allPromptSuggestions {
                let key = item.promptEn.trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty, preloadedSentenceVectors[key] == nil,
                   let raw = sEmb.vector(for: key), let norm = Self.l2Normalize(raw) {
                    preloadedSentenceVectors[key] = norm
                    sentCount += 1
                }
            }
        }
        if let wEmb = wordEmb {
            for arch in archetypes {
                for kwEn in arch.keywordsEn where !kwEn.contains(" ") {
                    let clean = kwEn.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if clean.count >= 2, preloadedWordVectors[clean] == nil,
                       let raw = wEmb.vector(for: clean), let norm = Self.l2Normalize(raw) {
                        preloadedWordVectors[clean] = norm
                        wordCount += 1
                    }
                }
            }
        }
        lock.withLock {
            hasPreloadedWeights = true
        }
        nlEngineLock.unlock()

        // 2. Warm NLTagger LinguisticData lemmatizer & NER weights
        _ = extractTokensAndEntities(from: "Late-night noir jazz with warm saxophone Miles Davis ночной джаз")

        // 3. Warm Apple Neural Engine Vision Saliency pipeline (32x32 dummy pass)
        ArtworkService.shared.prewarmVisionSaliencyModel()

        // 4. Prewarm Apple Intelligence FoundationModels LLM session (macOS 26+, only on >16 GB RAM machines so 8/16 GB M1 Macs never swap)
        var fmStatus = "unavailable"
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if ProcessInfo.processInfo.physicalMemory <= 16 * 1024 * 1024 * 1024 {
                fmStatus = "skipped-16gb-m1-guard"
            } else if case .available = SystemLanguageModel.default.availability {
                let sessionRu = LanguageModelSession(instructions: Self.curatorInstructionsRu)
                sessionRu.prewarm()
                let sessionEn = LanguageModelSession(instructions: Self.curatorInstructionsEn)
                sessionEn.prewarm()
                fmStatus = "prewarmed"
            } else {
                fmStatus = "not-ready"
            }
        }
        #endif

        let elapsedMs = Int(Date().timeIntervalSince(t0) * 1000)
        NSLog("[AICurator] ✅ AI model weights preloaded in %dms (sentenceVecs=%d, wordVecs=%d, VisionSaliency=warmed, FoundationModels=%@)",
              elapsedMs, sentCount, wordCount, fmStatus)
    }

    // MARK: - Hardware Architecture & Unified AI Switch

    /// Returns true when compiled and running on Apple Silicon (`arm64`), where Apple Neural Engine is available.
    public static var isAppleSiliconHardware: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    /// Allows unit tests to simulate Intel (`x86_64`) vs Apple Silicon (`arm64`) hardware.
    internal var simulatedArchitectureIsAppleSilicon: Bool? = nil

    /// True only on Apple Silicon Macs (`arm64`). On Intel (`x86_64`), returns `false`.
    public var isAppleSilicon: Bool {
        lock.lock()
        let overrideVal = simulatedArchitectureIsAppleSilicon
        lock.unlock()
        return overrideVal ?? Self.isAppleSiliconHardware
    }

    /// Unified switch that enables or disables ALL Native AI Functions (Prompt Curator, Semantic Flow, Vision Saliency Palette).
    /// On Intel Macs (`!isAppleSilicon`), always returns `false` because Apple Neural Engine is only available on Apple Silicon.
    public var isEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            let isArm = simulatedArchitectureIsAppleSilicon ?? Self.isAppleSiliconHardware
            guard isArm else { return false }
            return _isEnabled
        }
        set {
            lock.lock()
            let isArm = simulatedArchitectureIsAppleSilicon ?? Self.isAppleSiliconHardware
            let needsPreload: Bool
            if isArm {
                _isEnabled = newValue
                AppStorageProvider.shared.set(newValue, forKey: enabledStorageKey)
                needsPreload = newValue && !hasPreloadedWeights
            } else {
                _isEnabled = false
                AppStorageProvider.shared.set(false, forKey: enabledStorageKey)
                needsPreload = false
            }
            lock.unlock()
            if needsPreload {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.preloadModelWeightsSynchronously()
                }
            }
        }
    }

    public struct PromptSuggestionItem: Sendable {
        public let labelRu: String
        public let promptRu: String
        public let labelEn: String
        public let promptEn: String
    }

    /// Checks whether Apple Intelligence (FoundationModels) is active on this Mac,
    /// or whether the built-in NaturalLanguage 512-D Neural Embedding engine is used.
    public var activeEngineDescription: String {
        if let cached = lock.withLock({ cachedEngineDescriptionCache }),
           Date().timeIntervalSince(cached.timestamp) < 60.0 {
            return cached.desc
        }
        var resolved = "Apple Neural Engine • NaturalLanguage 512-D"
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *),
           ProcessInfo.processInfo.physicalMemory > 16 * 1024 * 1024 * 1024 {
            if case .available = SystemLanguageModel.default.availability {
                resolved = "Apple Intelligence • FoundationModels + NLEmbedding"
            }
        }
        #endif
        lock.withLock {
            cachedEngineDescriptionCache = (Date(), resolved)
        }
        return resolved
    }

    internal final class OnceResumeGate<T: Sendable>: @unchecked Sendable {
        private let gateLock = NSLock()
        private var resumed = false
        func tryResume(_ continuation: CheckedContinuation<T, Never>, with value: T) -> Bool {
            gateLock.lock()
            if resumed {
                gateLock.unlock()
                return false
            }
            resumed = true
            gateLock.unlock()
            continuation.resume(returning: value)
            return true
        }
    }

    /// Executes a catalog search with a strict non-blocking 3.5s URLRequest timeout and cancellation check.
    internal func searchCatalogWithTimeout(query: String, storefront: String, limit: Int) async -> [String: Any]? {
        guard !Task.isCancelled else { return nil }
        let effectiveSf: String
        if !PlaybackRouter.shared.isTestingEnvironment && MusicKitManager.shared.hasUserToken {
            let userSf = MusicKitManager.shared.getUserStorefront().trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            effectiveSf = userSf.isEmpty ? storefront : userSf
        } else {
            effectiveSf = storefront
        }
        return await MusicKitManager.shared.searchAppleMusic(
            query: query,
            storefront: effectiveSf,
            limit: limit,
            offset: 0,
            timeout: 3.5
        )
    }
}
