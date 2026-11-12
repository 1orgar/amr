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

private struct ArtistStyleProfile: Sendable {
    let canonicalArtist: String
    let aliases: [String]
    let archetypeId: String
    let styleTitleRu: String
    let styleTitleEn: String
    let customDescriptionRu: String?
    let customDescriptionEn: String?
    let seedQueries: [String]
}

private struct ArtistStyleIntent: Sendable {
    let targetArtist: String
    let moodContext: String
    let isExplicitStylePrefix: Bool
    let isIncompletePrefixOnly: Bool
}

public final class NativeMusicCuratorService: @unchecked Sendable {
    public static let shared = NativeMusicCuratorService()

    private let lock = NSLock()
    /// Serializes all access to Apple's `NLEmbedding` and `NLTagger` (which are NOT thread-safe across concurrent tasks on Apple Silicon)
    private let nlEngineLock = NSLock()
    private let enabledStorageKey = "amr_ai_curator_enabled_v1"
    private let pinnedStorageKey = "amr_ai_curator_pinned_v1"
    private var _isEnabled: Bool
    private var _pinnedPrompts: [PromptSuggestionItem] = []
    private let archetypes: [SonicArchetype]
    private let artistStyleProfiles: [ArtistStyleProfile]
    private var preloadedSentenceVectors: [String: [Double]] = [:]
    private var preloadedWordVectors: [String: [Double]] = [:]
    private var cachedSentenceVectors: [String: [Double]] = [:]
    private var cachedWordVectors: [String: [Double]] = [:]
    private var isPreloadingWeights: Bool = false
    private var hasPreloadedWeights: Bool = false
    private var foundationModelsCooldownUntil: Date = .distantPast
    private var isFoundationModelsInFlight: Bool = false

    private static let curatorInstructionsEn = "You are an audiophile music curator for Apple Music. Respond ONLY with 4 lines: Line 1: Session Title. Line 2: One-sentence audiophile description of the mood and soundstage. Line 3: 4 short tags separated by |. Line 4: 6 specific Apple Music search queries (Artist Song or Artist Album) separated by |."
    private static let curatorInstructionsRu = "Ты аудиофильский музыкальный куратор Apple Music. Ответь СТРОГО в 4 строки без лишнего текста: Строка 1: Название подборки. Строка 2: Одно предложение с описанием звучания, сцены и атмосферы. Строка 3: 4 коротких тега через |. Строка 4: 6 точных поисковых запросов для Apple Music (Артист Трек или Артист Альбом) через |."

    private init() {
        if UserDefaults.standard.object(forKey: enabledStorageKey) != nil {
            self._isEnabled = UserDefaults.standard.bool(forKey: enabledStorageKey)
        } else {
            self._isEnabled = true
        }
        if let savedPinned = UserDefaults.standard.array(forKey: pinnedStorageKey) as? [[String: String]] {
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

    private static func l2Normalize(_ vec: [Double]) -> [Double]? {
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
    private static func cosineDistanceNormalized(_ a: [Double], _ b: [Double]) -> Double {
        let count = min(a.count, b.count)
        guard count > 0 else { return 2.0 }
        var dot: Double = 0.0
        for i in 0..<count {
            dot += a[i] * b[i]
        }
        return max(0.0, min(2.0, 1.0 - dot))
    }

    private func normalizedSentenceVector(for text: String) -> [Double]? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        if hasPreloadedWeights, let permanent = preloadedSentenceVectors[clean] {
            return permanent
        }
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

    private func normalizedWordVector(for word: String) -> [Double]? {
        let clean = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard clean.count >= 2 else { return nil }
        if hasPreloadedWeights, let permanent = preloadedWordVectors[clean] {
            return permanent
        }
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
        nlEngineLock.unlock()
        lock.withLock {
            hasPreloadedWeights = true
        }

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
                UserDefaults.standard.set(newValue, forKey: enabledStorageKey)
                needsPreload = newValue && !hasPreloadedWeights
            } else {
                _isEnabled = false
                UserDefaults.standard.set(false, forKey: enabledStorageKey)
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

    private static let allPromptSuggestions: [PromptSuggestionItem] = [
        PromptSuggestionItem(
            labelRu: "🎷 Ночной нуар-джаз с саксофоном",
            promptRu: "Ночной нуар-джаз с тёплым саксофоном и контрабасом",
            labelEn: "🎷 Late-night noir jazz with sax",
            promptEn: "Late-night noir jazz with warm tenor saxophone and upright bass"
        ),
        PromptSuggestionItem(
            labelRu: "🎸 Аналоговый прог-рок 70-х",
            promptRu: "Аналоговый прог-рок 70-х с широкой голографической сценой",
            labelEn: "🎸 70s analog progressive rock",
            promptEn: "1970s analog progressive rock with wide holographic soundstage"
        ),
        PromptSuggestionItem(
            labelRu: "🎹 Эмбиент и пианино для фокуса",
            promptRu: "Глубокий эмбиент и неоклассическое пианино для фокуса",
            labelEn: "🎹 Deep ambient & piano for focus",
            promptEn: "Deep ambient and neoclassical felt piano for focus"
        ),
        PromptSuggestionItem(
            labelRu: "🎙️ Эталонный вокал и акустика",
            promptRu: "Аудиофильский эталонный женский вокал и живая акустика",
            labelEn: "🎙️ Reference vocals & acoustics",
            promptEn: "Audiophile reference female vocal and intimate acoustic guitar"
        ),
        PromptSuggestionItem(
            labelRu: "🌃 Кинематографичный синтвейв 80-х",
            promptRu: "Кинематографичный синтвейв 80-х и глубокий аналоговый синт",
            labelEn: "🌃 Cinematic 80s synthwave",
            promptEn: "Cinematic 1980s synthwave and deep analog synthesizers"
        ),
        PromptSuggestionItem(
            labelRu: "🔊 Бристольский трип-хоп и даунтемпо",
            promptRu: "Бристольский трип-хоп 90-х и глубокий даунтемпо с суббасом",
            labelEn: "🔊 Bristol trip-hop & downtempo",
            promptEn: "1990s Bristol trip-hop and deep downtempo sub-bass groove"
        ),
        PromptSuggestionItem(
            labelRu: "☀️ Тёплый фанк, соул и живой грув",
            promptRu: "Тёплый фанк, соул и живой грув с бас-гитарой и духовыми",
            labelEn: "☀️ Warm funk, soul & live groove",
            promptEn: "Warm funk, soul and live analog groove with bass and brass"
        ),
        PromptSuggestionItem(
            labelRu: "🌌 Инструментальный пост-рок",
            promptRu: "Инструментальный пост-рок и кинематографичные гитарные кульминации",
            labelEn: "🌌 Instrumental post-rock crescendos",
            promptEn: "Instrumental post-rock and sweeping cinematic guitar crescendos"
        ),
        PromptSuggestionItem(
            labelRu: "🎛️ Гипнотический даб-техно и минимал",
            promptRu: "Гипнотический даб-техно и глубокая минимал-электроника с суббасом",
            labelEn: "🎛️ Hypnotic dub techno & minimal",
            promptEn: "Hypnotic dub techno and deep minimal electronics with spatial chords"
        ),
        PromptSuggestionItem(
            labelRu: "🔥 Ламповый блюз-рок и гитара",
            promptRu: "Ламповый блюз-рок и выразительная живая электрогитара без компрессии",
            labelEn: "🔥 Tube-amp blues rock guitar",
            promptEn: "Warm tube-amp blues rock and expressive live electric guitar"
        ),
        PromptSuggestionItem(
            labelRu: "🎻 Камерная классика и струнные Hi-Res",
            promptRu: "Камерная классика, виолончель и оркестр с эталонной сценой",
            labelEn: "🎻 Chamber strings & Hi-Res classical",
            promptEn: "Chamber classical strings, cello and orchestra with reference soundstage"
        ),
        PromptSuggestionItem(
            labelRu: "🎺 Прохладный джаз и труба в стиле Miles Davis",
            promptRu: "Ночной прохладный джаз с трубой и роялем как у Miles Davis",
            labelEn: "🎺 Cool jazz trumpet like Miles Davis",
            promptEn: "Cool nocturnal jazz with muted trumpet and piano like Miles Davis"
        ),
        PromptSuggestionItem(
            labelRu: "🎬 Эпические саундтреки и оркестр",
            promptRu: "Кинематографичные саундтреки, оркестр и глубокий бас для большого звука",
            labelEn: "🎬 Epic film scores & orchestra",
            promptEn: "Cinematic film scores, orchestra and deep sub-bass soundstage"
        ),
        PromptSuggestionItem(
            labelRu: "💿 Французский хаус и диско-грув",
            promptRu: "Тёплый электронный диско-грув и синт-бас как у Daft Punk и Air",
            labelEn: "💿 French touch & nu-disco groove",
            promptEn: "Warm electronic nu-disco groove and analog synth bass like Daft Punk and Air"
        ),
        PromptSuggestionItem(
            labelRu: "🌧️ Атмосферная меланхолия под дождь",
            promptRu: "Меланхоличный вечерний инди-эмбиент и мягкий вокал под дождь",
            labelEn: "🌧️ Rainy evening atmospheric melancholy",
            promptEn: "Rainy evening melancholic atmospheric ambient and gentle vocals"
        ),
        PromptSuggestionItem(
            labelRu: "🪕 Акустический анплагд с эффектом присутствия",
            promptRu: "Живой акустический гитарный анплагд с высокой микродинамикой",
            labelEn: "🪕 Live acoustic unplugged reference",
            promptEn: "Intimate live acoustic guitar unplugged with high micro-dynamics"
        ),
        PromptSuggestionItem(
            labelRu: "🚀 Космический аналоговый эмбиент",
            promptRu: "Космический эмбиент и аналоговые синтезаторы как у Brian Eno и Vangelis",
            labelEn: "🚀 Cosmic analog space ambient",
            promptEn: "Cosmic space ambient and analog synthesizers like Brian Eno and Vangelis"
        ),
        PromptSuggestionItem(
            labelRu: "🥁 Аудиофильский тест барабанов и баса",
            promptRu: "Аудиофильский референсный рок и фьюжн с упругим басом и живыми барабанами",
            labelEn: "🥁 Audiophile drum & bass transient test",
            promptEn: "Audiophile reference rock and jazz fusion with tight bass and live drums"
        )
    ]

    private static let dynamicMoods: [(icon: String, shortRu: String, fullRu: String, shortEn: String, fullEn: String)] = [
        ("🎷", "Ночной нуар", "Ночной атмосферный нуар", "Midnight noir", "Late-night atmospheric noir"),
        ("🌌", "Глубокий космос", "Глубокая космическая атмосфера", "Deep cosmos", "Deep cosmic atmosphere"),
        ("🕯️", "Интимная сцена", "Камерная интимная акустика близкого поля", "Intimate stage", "Near-field intimate chamber acoustics"),
        ("⚡", "Высокий драйв", "Высокодинамичный драйв и панч", "High-energy drive", "High-contrast dynamic drive and punch"),
        ("🌊", "Голографический 3D", "Широкая голографическая звуковая сцена", "3D soundstage", "Wide holographic 3D soundstage"),
        ("🥃", "Тёплая лампа", "Тёплое аналоговое ламповое звучание", "Warm tube glow", "Warm analog vacuum-tube timbre"),
        ("🌧️", "Дождливый город", "Меланхолия дождливого ночного мегаполиса", "Rainy midnight", "Rainy midnight metropolis atmosphere"),
        ("🧘", "Глубокий фокус", "Спокойная гипнотическая концентрация", "Deep focus", "Hypnotic calm for deep focus"),
        ("🌆", "Неоновый ретро", "Кинематографичный неоновый ретро-вайб", "Neon retro", "Cinematic neon retro atmosphere"),
        ("🏔️", "Северный воздух", "Прозрачная скандинавская прохлада", "Nordic air", "Crystalline Nordic spaciousness"),
        ("🔥", "Живая студия", "Энергия живой студийной записи с одного дубля", "Live studio take", "Raw one-take live studio energy"),
        ("🌙", "После полуночи", "Мягкий бархатный грув после полуночи", "After-hours", "Velvet after-hours lounge groove"),
        ("💎", "Кристальный Hi-Res", "Эталонная прозрачность и микродинамика", "Reference Hi-Res", "Reference transparency and micro-dynamics"),
        ("🎞️", "Магнитная лента", "Винтажный мастеринг на аналоговую ленту", "Analog tape", "Vintage reel-to-reel analog tape warmth"),
        ("🌅", "Рассветный чилл", "Тёплый солнечный рассветный грув", "Sunrise chill", "Warm golden-hour sunrise groove"),
        ("🌀", "Психоделический трип", "Глубокое психоделическое погружение", "Psychedelic voyage", "Deep psychedelic sonic immersion")
    ]

    private static let dynamicGenres: [(shortRu: String, fullRu: String, shortEn: String, fullEn: String)] = [
        ("прог-рок 70-х", "прогрессивный рок 70-х", "70s prog rock", "1970s progressive rock"),
        ("кул-джаз", "модальный и кул-джаз", "cool jazz", "modal and cool jazz"),
        ("трип-хоп 90-х", "бристольский трип-хоп и даунтемпо", "90s trip-hop", "Bristol trip-hop and downtempo"),
        ("неоклассика", "современная камерная неоклассика", "neoclassical", "modern chamber neoclassical"),
        ("синтвейв 80-х", "аналоговый синтвейв и электроника 80-х", "80s synthwave", "1980s analog synthwave"),
        ("блюз-рок", "аудиофильский блюз-рок", "blues rock", "audiophile blues rock"),
        ("даб-техно", "глубокое даб-техно и минимал", "dub techno", "deep dub techno and minimal"),
        ("джаз-фанк", "грувовый джаз-фанк и соул", "jazz-funk", "groovy spiritual jazz-funk"),
        ("пост-рок", "инструментальный кинематографичный пост-рок", "post-rock", "cinematic instrumental post-rock"),
        ("босса-нова 60-х", "бразильская босса-нова 60-х", "60s bossa nova", "1960s Brazilian bossa nova"),
        ("дрим-поп и шугейз", "воздушный дрим-поп и шугейз", "dream-pop & shoegaze", "ethereal dream-pop and shoegaze"),
        ("японский сити-поп", "японский сити-поп и буги-фанк 80-х", "Japanese city pop", "1980s Japanese city pop and funk"),
        ("дарк-джаз", "медленный кинематографичный дарк-джаз", "dark jazz", "slow cinematic dark jazz"),
        ("инди-фолк", "акустический инди-фолк", "indie folk", "intimate acoustic indie folk"),
        ("берлинский эмбиент", "космическая электроника берлинской школы", "Berlin school synth", "Berlin-school modular electronica"),
        ("симфо-саундтрек", "эпический оркестровый саундтрек", "epic film score", "epic orchestral film score"),
        ("афробит и фьюжн", "полиритмический афробит и джаз-фьюжн", "afrobeat fusion", "polyrhythmic afrobeat and jazz fusion"),
        ("нео-соул", "бархатный нео-соул и R&B", "neo-soul", "velvet audiophile neo-soul")
    ]

    private static let dynamicInstruments: [(shortRu: String, fullRu: String, shortEn: String, fullEn: String)] = [
        ("с саксофоном", "с бархатным тенор-саксофоном и контрабасом", "with tenor sax", "with warm tenor saxophone and upright bass"),
        ("и фетровое пианино", "с мягким фетровым пианино и виолончелью", "& felt piano", "with intimate felt piano and cello"),
        ("и живой вокал", "с эталонным женским вокалом близкого микрофона", "& reference vocals", "with close-mic reference female vocals"),
        ("и ламповая гитара", "с певучей электрогитарой и органом Hammond", "& tube guitar", "with singing tube guitar and Hammond organ"),
        ("и аналоговый Moog", "с глубоким аналоговым синтезатором Moog и арпеджио", "& analog Moog", "with deep Moog synthesizers and arpeggios"),
        ("и глубокий суббас", "с упругим суббасом и чёткой атакой барабанов", "& deep sub-bass", "with visceral sub-bass and crisp drum transients"),
        ("и Fender Rhodes", "с тёплым электропиано Fender Rhodes и щётками", "& Fender Rhodes", "with warm Fender Rhodes and brushed drums"),
        ("и акустическая гитара", "с живым пальцевым перебором акустической гитары", "& acoustic guitar", "with fingerstyle acoustic guitar and natural room reverb"),
        ("и камерные струнные", "с живым струнным квартетом и широким залом", "& chamber strings", "with live string quartet and concert hall acoustics"),
        ("и слэп-бас", "с фанковым слэп-басом и духовой секцией", "& slap bass", "with tight slap bass and brass section"),
        ("и вибрафон", "с мерцающим вибрафоном и мягкой перкуссией", "& vibraphone", "with shimmering vibraphone and percussion"),
        ("и баритон-саксофон", "с низким баритон-саксофоном и густым ревербом", "& baritone sax", "with smoky baritone sax and lush reverb")
    ]

    private var recentPromptsHistory: [String] = []
    private let historyLock = NSLock()

    private func synthesizeDynamicPrompt(excluding excluded: Set<String>) -> PromptSuggestionItem {
        for _ in 0..<60 {
            let mood = Self.dynamicMoods.randomElement()!
            let genre = Self.dynamicGenres.randomElement()!
            let inst = Self.dynamicInstruments.randomElement()!

            let labelRu = "\(mood.icon) \(mood.shortRu) • \(genre.shortRu) \(inst.shortRu)"
            let promptRu = "\(mood.fullRu): \(genre.fullRu) \(inst.fullRu)"
            let labelEn = "\(mood.icon) \(mood.shortEn) • \(genre.shortEn) \(inst.shortEn)"
            let promptEn = "\(mood.fullEn): \(genre.fullEn) \(inst.fullEn)"

            let keyRu = promptRu.lowercased()
            let keyEn = promptEn.lowercased()
            if !excluded.contains(keyRu) && !excluded.contains(keyEn) {
                return PromptSuggestionItem(labelRu: labelRu, promptRu: promptRu, labelEn: labelEn, promptEn: promptEn)
            }
        }
        let mood = Self.dynamicMoods.randomElement()!
        let genre = Self.dynamicGenres.randomElement()!
        let inst = Self.dynamicInstruments.randomElement()!
        return PromptSuggestionItem(
            labelRu: "\(mood.icon) \(mood.shortRu) • \(genre.shortRu) \(inst.shortRu)",
            promptRu: "\(mood.fullRu): \(genre.fullRu) \(inst.fullRu)",
            labelEn: "\(mood.icon) \(mood.shortEn) • \(genre.shortEn) \(inst.shortEn)",
            promptEn: "\(mood.fullEn): \(genre.fullEn) \(inst.fullEn)"
        )
    }

    public func getRandomSuggestions(count: Int = 6, excludePrompts: [String] = [], preferEnglish: Bool = false) -> [[String: String]] {
        historyLock.lock()
        defer { historyLock.unlock() }

        var excludedSet = Set(excludePrompts.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
        for old in recentPromptsHistory {
            excludedSet.insert(old)
        }

        let unseenBase = Self.allPromptSuggestions.filter { item in
            let pRu = item.promptRu.lowercased()
            let pEn = item.promptEn.lowercased()
            let lRu = item.labelRu.lowercased()
            let lEn = item.labelEn.lowercased()
            return !excludedSet.contains(pRu) && !excludedSet.contains(pEn) && !excludedSet.contains(lRu) && !excludedSet.contains(lEn)
        }.shuffled()

        var results: [PromptSuggestionItem] = []
        // Mix up to half from unseen curated base and synthesize the rest dynamically so every refresh is fresh!
        let baseQuota = min(unseenBase.count, max(2, count / 2))
        for i in 0..<baseQuota {
            let item = unseenBase[i]
            results.append(item)
            excludedSet.insert(item.promptRu.lowercased())
            excludedSet.insert(item.promptEn.lowercased())
        }

        while results.count < count {
            let synth = synthesizeDynamicPrompt(excluding: excludedSet)
            results.append(synth)
            excludedSet.insert(synth.promptRu.lowercased())
            excludedSet.insert(synth.promptEn.lowercased())
        }

        results.shuffle()

        for item in results {
            recentPromptsHistory.append(item.promptRu.lowercased())
            recentPromptsHistory.append(item.promptEn.lowercased())
        }
        if recentPromptsHistory.count > 120 {
            recentPromptsHistory.removeFirst(recentPromptsHistory.count - 120)
        }

        return results.map { item in
            [
                "label": preferEnglish ? item.labelEn : item.labelRu,
                "prompt": preferEnglish ? item.promptEn : item.promptRu,
                "label_ru": item.labelRu,
                "prompt_ru": item.promptRu,
                "label_en": item.labelEn,
                "prompt_en": item.promptEn
            ]
        }
    }

    // MARK: - Pinned Favorite Prompts

    public func getPinnedPrompts(preferEnglish: Bool = false) -> [[String: String]] {
        lock.lock()
        let snapshot = _pinnedPrompts
        lock.unlock()
        return snapshot.map { item in
            [
                "label": preferEnglish ? item.labelEn : item.labelRu,
                "prompt": preferEnglish ? item.promptEn : item.promptRu,
                "label_ru": item.labelRu,
                "prompt_ru": item.promptRu,
                "label_en": item.labelEn,
                "prompt_en": item.promptEn,
                "pinned": "true"
            ]
        }
    }

    public func isPromptPinned(_ prompt: String) -> Bool {
        let target = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        return _pinnedPrompts.contains { item in
            item.promptRu.lowercased() == target ||
            item.promptEn.lowercased() == target ||
            item.labelRu.lowercased() == target ||
            item.labelEn.lowercased() == target
        }
    }

    @discardableResult
    public func togglePinPrompt(
        prompt: String,
        label: String? = nil,
        labelRu: String? = nil,
        promptRu: String? = nil,
        labelEn: String? = nil,
        promptEn: String? = nil
    ) -> Bool {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPromptRu = (promptRu?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? promptRu!.trimmingCharacters(in: .whitespacesAndNewlines)
            : cleanPrompt
        let cleanPromptEn = (promptEn?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? promptEn!.trimmingCharacters(in: .whitespacesAndNewlines)
            : cleanPrompt
        guard !cleanPrompt.isEmpty || !cleanPromptRu.isEmpty else { return false }

        let targetLower = cleanPrompt.lowercased()
        let targetRuLower = cleanPromptRu.lowercased()
        let targetEnLower = cleanPromptEn.lowercased()

        lock.lock()
        defer { lock.unlock() }

        if let existingIdx = _pinnedPrompts.firstIndex(where: { item in
            let pRu = item.promptRu.lowercased()
            let pEn = item.promptEn.lowercased()
            return pRu == targetLower || pEn == targetLower || pRu == targetRuLower || pEn == targetEnLower
        }) {
            _pinnedPrompts.remove(at: existingIdx)
            persistPinnedPromptsLocked()
            return false
        }

        // Resolve from preset pool if matching, otherwise construct custom PromptSuggestionItem
        let matchedPreset = Self.allPromptSuggestions.first { item in
            let pRu = item.promptRu.lowercased()
            let pEn = item.promptEn.lowercased()
            return pRu == targetLower || pEn == targetLower || pRu == targetRuLower || pEn == targetEnLower
        }

        let newItem: PromptSuggestionItem
        if let preset = matchedPreset {
            newItem = preset
        } else {
            let fallbackLabel = Self.buildConciseLabel(from: label ?? cleanPrompt)
            let resolvedLabelRu = (labelRu?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? labelRu!.trimmingCharacters(in: .whitespacesAndNewlines)
                : fallbackLabel
            let resolvedLabelEn = (labelEn?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? labelEn!.trimmingCharacters(in: .whitespacesAndNewlines)
                : fallbackLabel
            newItem = PromptSuggestionItem(
                labelRu: resolvedLabelRu,
                promptRu: cleanPromptRu,
                labelEn: resolvedLabelEn,
                promptEn: cleanPromptEn
            )
        }

        _pinnedPrompts.insert(newItem, at: 0)
        if _pinnedPrompts.count > 24 {
            _pinnedPrompts = Array(_pinnedPrompts.prefix(24))
        }
        persistPinnedPromptsLocked()
        return true
    }

    public func clearPinnedPrompts() {
        lock.lock()
        _pinnedPrompts.removeAll()
        UserDefaults.standard.removeObject(forKey: pinnedStorageKey)
        lock.unlock()
    }

    private func persistPinnedPromptsLocked() {
        let serialized: [[String: String]] = _pinnedPrompts.map { item in
            [
                "label_ru": item.labelRu,
                "prompt_ru": item.promptRu,
                "label_en": item.labelEn,
                "prompt_en": item.promptEn
            ]
        }
        UserDefaults.standard.set(serialized, forKey: pinnedStorageKey)
    }

    private static func buildConciseLabel(from rawText: String) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "✨ AI-вайб" }
        let hasLeadingSymbol = trimmed.unicodeScalars.first.map { !$0.properties.isAlphabetic && !$0.properties.isIdeographic && !CharacterSet.decimalDigits.contains($0) } ?? false
        let maxChars = 42
        let body: String
        if trimmed.count > maxChars {
            let idx = trimmed.index(trimmed.startIndex, offsetBy: maxChars)
            body = String(trimmed[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        } else {
            body = trimmed
        }
        return hasLeadingSymbol ? body : "✨ \(body)"
    }

    public func getSettingsDictionary(excludePrompts: [String] = []) -> [String: Any] {
        let langTag = MusicKitManager.shared.getPreferredLanguageTag().lowercased()
        let preferEnglish = !langTag.hasPrefix("ru")
        let enabled = isEnabled
        let appleSilicon = isAppleSilicon
        return [
            "enabled": enabled,
            "is_enabled": enabled,
            "is_apple_silicon": appleSilicon,
            "engine": appleSilicon ? activeEngineDescription : "Intel x86_64 (Apple Neural Engine Unavailable)",
            "suggestions": getRandomSuggestions(count: 6, excludePrompts: excludePrompts, preferEnglish: preferEnglish),
            "pinned": getPinnedPrompts(preferEnglish: preferEnglish)
        ]
    }

    /// Checks whether Apple Intelligence (FoundationModels) is active on this Mac,
    /// or whether the built-in NaturalLanguage 512-D Neural Embedding engine is used.
    public var activeEngineDescription: String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return "Apple Intelligence • FoundationModels + NLEmbedding"
            }
        }
        #endif
        return "Apple Neural Engine • NaturalLanguage 512-D"
    }

    private final class OnceResumeGate<T: Sendable>: @unchecked Sendable {
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
    private func searchCatalogWithTimeout(query: String, storefront: String, limit: Int) async -> [String: Any]? {
        guard !Task.isCancelled else { return nil }
        return await MusicKitManager.shared.searchAppleMusic(
            query: query,
            storefront: storefront,
            limit: limit,
            offset: 0,
            timeout: 3.5
        )
    }

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
    public func curateMusicSession(prompt: String, storefront: String = "ru") async -> [String: Any] {
        let totalStart = Date()
        let langTag = MusicKitManager.shared.getPreferredLanguageTag().lowercased()
        let preferEnglish = !langTag.hasPrefix("ru")
        var plan = await buildCuratedPlan(for: prompt, preferEnglish: preferEnglish, allowFoundationModels: true)

        let sf = storefront.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? MusicKitManager.shared.getUserStorefront()
            : storefront.lowercased()

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
            for tok in sortedTokens {
                if let permanent = preloadedWordVectors[tok] {
                    wVecs.append((tok, permanent))
                    if wVecs.count >= 5 { break }
                }
            }

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
        storefront: String = "ru",
        excluding: [TrackInfo]
    ) async -> [TrackInfo] {
        let waveStart = Date()
        let langTag = MusicKitManager.shared.getPreferredLanguageTag().lowercased()
        let preferEnglish = !langTag.hasPrefix("ru")
        // Never invoke FoundationModels LLM during background Infinite AI Wave auto-append
        let plan = await buildCuratedPlan(for: prompt, preferEnglish: preferEnglish, allowFoundationModels: false)

        let sf = storefront.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? MusicKitManager.shared.getUserStorefront()
            : storefront.lowercased()

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
        storefront: String = "ru"
    ) async -> [String: Any] {
        let startTs = Date()
        let langTag = MusicKitManager.shared.getPreferredLanguageTag().lowercased()
        let preferEnglish = !langTag.hasPrefix("ru")
        let sf = storefront.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? MusicKitManager.shared.getUserStorefront()
            : storefront.lowercased()

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

        queryBuckets.sort { $0.0 < $1.0 }
        let curatedSongs = filterAndInterleaveWaveSongs(queryBuckets: queryBuckets, excluding: [], maxCount: 24)

        var curatedAlbums: [[String: Any]] = []
        var seenAlbumKeys = Set<String>()
        for (_, _, albums) in queryBuckets {
            for alb in albums.prefix(2) {
                let aName = (alb["name"] as? String ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let aArtist = (alb["artist"] as? String ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !aName.isEmpty else { continue }
                let key = "\(aArtist)|\(aName)"
                if seenAlbumKeys.contains(key) { continue }
                seenAlbumKeys.insert(key)
                curatedAlbums.append(alb)
                if curatedAlbums.count >= 8 { break }
            }
            if curatedAlbums.count >= 8 { break }
        }

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

    private func tryFoundationModelsPlan(
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
            defer {
                lock.withLock { isFoundationModelsInFlight = false }
            }

            let instructions = preferEnglish
                ? Self.curatorInstructionsEn
                : Self.curatorInstructionsRu

            // Strict 2.2-second non-blocking timeout so M1 LLM cold-start or XPC stall never blocks curation
            let rawContent: String? = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                let gate = OnceResumeGate<String?>()
                let llmTask = Task.detached(priority: .userInitiated) {
                    do {
                        let session = LanguageModelSession(instructions: instructions)
                        let response = try await session.respond(to: prompt)
                        _ = gate.tryResume(continuation, with: response.content)
                    } catch {
                        NSLog("[AICurator] FoundationModels error: %@", error.localizedDescription)
                        _ = gate.tryResume(continuation, with: nil)
                    }
                }
                Task.detached(priority: .utility) {
                    try? await Task.sleep(nanoseconds: 2_200_000_000)
                    if gate.tryResume(continuation, with: nil) {
                        llmTask.cancel()
                        NSLog("[AICurator] ⏱ FoundationModels timed out (>2.2s on M1); engaging 10-min cooldown & falling back to NaturalLanguage 512-D")
                    }
                }
            }

            guard let content = rawContent else {
                lock.withLock {
                    foundationModelsCooldownUntil = Date().addingTimeInterval(600)
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

        let primaryPool = primary.seedQueries.shuffled()
        if let sec = secondary {
            let secPool = sec.seedQueries.shuffled()
            for i in 0..<max(primaryPool.count, secPool.count) {
                if i < primaryPool.count && finalQueries.count < 10 {
                    let q = primaryPool[i]
                    if !finalQueries.contains(q) { finalQueries.append(q) }
                }
                if i < secPool.count && finalQueries.count < 10 {
                    let q = secPool[i]
                    if !finalQueries.contains(q) { finalQueries.append(q) }
                }
            }
        } else {
            for q in primaryPool where !finalQueries.contains(q) {
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

    // MARK: - Artist Style Intent & Dynamic Catalog Genre Resolution

    private static let styleActionPrefixes: [String] = [
        "включи ", "поставь ", "найди ", "подбери ", "сделай ", "собери ",
        "хочу послушать ", "хочу ", "дай ", "запусти ",
        "play ", "find ", "curate ", "give me "
    ]

    /// Ordered longest-first so multi-word prefixes ("в стиле гуппы", "в стиле группы") strip completely
    private static let stylePhrasePrefixes: [String] = [
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

    private func extractArtistStyleIntent(from rawPrompt: String) -> ArtistStyleIntent {
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

    private static func titleCaseArtistName(_ raw: String) -> String {
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

    private func findArtistStyleProfile(for rawArtist: String) -> ArtistStyleProfile? {
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

    private func findArtistStyleProfileInPrompt(lowerPrompt: String) -> ArtistStyleProfile? {
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

    private func bestArchetypeForCatalogGenre(_ rawGenre: String) -> SonicArchetype? {
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

    private func resolveDynamicCatalogArtistPlan(
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

    private func normalizeSongTitleForDedup(_ rawTitle: String) -> String {
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

    private func normalizeArtistForDedup(_ rawArtist: String) -> String {
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

    private func extractTokensAndEntities(from text: String) -> (tokens: [String], entities: [String]) {
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

    private func cleanPromptForDirectSearch(_ prompt: String) -> String {
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

    private func translatePromptToEnglishSemanticSpace(
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

    // MARK: - Curated Audiophile Sonic Archetypes Knowledge Base

    private static func buildArchetypes() -> [SonicArchetype] {
        return [
            SonicArchetype(
                id: "noir_jazz",
                titleRu: "Ночной нуар-джаз и тёплый саксофон",
                titleEn: "Late-Night Noir Jazz & Warm Saxophone",
                descriptionRu: "Камерная ночная сцена с бархатным тенор-саксофоном, приглушённой трубой, акустическим контрабасом и естественной реверберацией студий Rudy Van Gelder и ECM.",
                descriptionEn: "Intimate late-night soundstage featuring velvety tenor saxophone, muted trumpet, upright bass, and natural studio room acoustics.",
                semanticDescriptorEn: "late night noir cool jazz saxophone muted trumpet upright double bass dark smoky club rain atmospheric",
                keywordsRu: ["джаз", "нуар", "саксофон", "труб", "контрабас", "ночн", "дожд", "клуб"],
                keywordsEn: ["jazz", "noir", "saxophone", "sax", "trumpet", "miles", "coltrane", "late night", "smoky", "ballad"],
                tagsRu: ["🎷 Тенор-саксофон", "🌙 Ночной нуар", "🎚️ Аналоговая сцена", "Blue Note / ECM"],
                tagsEn: ["🎷 Tenor Sax", "🌙 Late Night Noir", "🎚️ Analog Soundstage", "Blue Note / ECM"],
                seedQueries: [
                    "Miles Davis Kind of Blue",
                    "Chet Baker Almost Blue",
                    "Bohren & der Club of Gore Sunset Mission",
                    "Bill Evans Waltz for Debby",
                    "John Coltrane Ballads",
                    "Stan Getz Getz Gilberto",
                    "Tomasz Stanko Suspended Night",
                    "Dexter Gordon Go",
                    "Wayne Shorter Speak No Evil",
                    "Tord Gustavsen Trio",
                    "Jan Garbarek Officium",
                    "Ibrahim Maalouf Illusions"
                ]
            ),
            SonicArchetype(
                id: "prog_rock_70s",
                titleRu: "Аналоговый прог-рок 70-х и широкая сцена",
                titleEn: "70s Analog Progressive Rock & Wide Soundstage",
                descriptionRu: "Монументальные концептуальные полотна 1970-х с эталонной глубиной стереопанорамы, живыми барабанами, органом Hammond и аналоговыми синтезаторами.",
                descriptionEn: "Monumental 1970s conceptual recordings with holographic stereo imaging, live drums, Hammond organ, and analog synthesizers.",
                semanticDescriptorEn: "1970s seventies progressive rock art rock psychedelic wide soundstage analog tape pink floyd concept album",
                keywordsRu: ["прог", "70", "семидесят", "психодел", "сцен", "аналог", "флойд", "арт-рок"],
                keywordsEn: ["progressive", "prog", "70s", "seventies", "psychedelic", "pink floyd", "art rock", "soundstage", "analog"],
                tagsRu: ["🎸 Прог-рок 70-х", "🌌 Голографическая сцена", "🎞️ Магнитная лента", "Hi-Res Master"],
                tagsEn: ["🎸 70s Prog Rock", "🌌 Holographic Stage", "🎞️ Analog Tape", "Hi-Res Master"],
                seedQueries: [
                    "Pink Floyd Wish You Were Here",
                    "Alan Parsons Project Eye in the Sky",
                    "Dire Straits Love Over Gold",
                    "King Crimson In the Court of the Crimson King",
                    "Supertramp Crime of the Century",
                    "Steely Dan Aja",
                    "Porcupine Tree In Absentia",
                    "Camel Mirage",
                    "Genesis Selling England by the Pound",
                    "Yes Close to the Edge",
                    "Steven Wilson The Raven That Refused to Sing",
                    "Rush Moving Pictures"
                ]
            ),
            SonicArchetype(
                id: "ambient_neoclassical_focus",
                titleRu: "Глубокий эмбиент и неоклассика для фокуса",
                titleEn: "Deep Ambient & Neoclassical Focus",
                descriptionRu: "Прозрачное акустическое пространство с фетровым пианино, камерными струнными и мягкими модулярными текстурами для концентрации и погружения.",
                descriptionEn: "Transparent acoustic space with felt piano, chamber strings, and warm modular textures crafted for deep focus and immersion.",
                semanticDescriptorEn: "deep ambient neoclassical piano strings focus study work calm peaceful atmospheric meditation",
                keywordsRu: ["эмбиент", "неоклассик", "пианин", "фортепиан", "рояль", "фокус", "работ", "спокойн", "струн", "медитац"],
                keywordsEn: ["ambient", "neoclassical", "piano", "focus", "study", "work", "calm", "peaceful", "strings", "drone"],
                tagsRu: ["🎹 Фетровое пианино", "🎻 Камерные струнные", "🧘 Глубокий фокус", "Erased Tapes / DG"],
                tagsEn: ["🎹 Felt Piano", "🎻 Chamber Strings", "🧘 Deep Focus", "Erased Tapes / DG"],
                seedQueries: [
                    "Nils Frahm All Melody",
                    "Max Richter The Blue Notebooks",
                    "Olafur Arnalds re:member",
                    "Brian Eno Apollo Atmospheres",
                    "Hania Rani Esja",
                    "Johann Johannsson Orphee",
                    "Ludovico Einaudi In a Time Lapse",
                    "Joep Beving Solipsism",
                    "Lambert Sweet Apocalypse",
                    "A Winged Victory for the Sullen",
                    "Dustin O'Halloran Lumiere",
                    "Ryuichi Sakamoto async"
                ]
            ),
            SonicArchetype(
                id: "audiophile_vocal_acoustic",
                titleRu: "Аудиофильский референсный вокал и акустика",
                titleEn: "Audiophile Reference Vocals & Acoustic Intimacy",
                descriptionRu: "Эталонные студийные записи с эффектом физического присутствия вокалиста в комнате, микродинамикой щипка струн и безупречным тональным балансом.",
                descriptionEn: "Reference-grade studio recordings with lifelike vocal presence, tactile string micro-dynamics, and natural tonal balance.",
                semanticDescriptorEn: "audiophile reference female vocal acoustic guitar unplugged intimate studio recording high dynamic range soundstage",
                keywordsRu: ["вокал", "аудиофил", "эталон", "акустич", "гитар", "женск", "голос", "тест", "тракт"],
                keywordsEn: ["audiophile", "reference", "vocal", "vocals", "female", "acoustic", "unplugged", "intimate", "soundstage"],
                tagsRu: ["🎙️ Эталонный вокал", "🪕 Живая акустика", "💎 Высокий DR", "Reference Track"],
                tagsEn: ["🎙️ Reference Vocal", "🪕 Pure Acoustic", "💎 High DR", "Reference Track"],
                seedQueries: [
                    "Diana Krall Love Scenes",
                    "Norah Jones Come Away With Me",
                    "Dominique Fils-Aime Nameless",
                    "Eva Cassidy Songbird",
                    "Melody Gardot My One and Only Thrill",
                    "Patricia Barber Cafe Blue",
                    "Chris Jones Roadhouses & Automobiles",
                    "cassandra wilson blue light til dawn",
                    "Rebecca Pidgeon The Raven",
                    "Allan Taylor Colour to the Moon",
                    "Madeleine Peyroux Careless Love",
                    "Gregory Porter Liquid Spirit"
                ]
            ),
            SonicArchetype(
                id: "synthwave_retro_electronic",
                titleRu: "Кинематографичный синтвейв и аналоговый неон",
                titleEn: "Cinematic Synthwave & Analog Neon",
                descriptionRu: "Густые полифонические синтезаторы Juno/Prophet, глубокий суббас и атмосфера ночного мегаполиса в эстетике ретро-футуризма 80-х.",
                descriptionEn: "Lush polyphonic analog synthesizers, deep sub-bass, and nocturnal cyberpunk atmosphere inspired by 1980s retro-futurism.",
                semanticDescriptorEn: "synthwave retrowave 1980s eighties analog synthesizer cyberpunk neon night drive blade runner electronic",
                keywordsRu: ["синтвейв", "синт", "80", "восьмидесят", "неон", "киберпанк", "ретро", "драйв", "ночн"],
                keywordsEn: ["synthwave", "retrowave", "80s", "eighties", "synth", "cyberpunk", "neon", "vangelis", "blade runner", "outrun"],
                tagsRu: ["🎹 Аналоговый синт", "🌃 Неоновый драйв", "🔊 Глубокий суббас", "1980s Aesthetics"],
                tagsEn: ["🎹 Analog Synth", "🌃 Neon Night Drive", "🔊 Deep Sub-Bass", "1980s Aesthetics"],
                seedQueries: [
                    "Vangelis Blade Runner",
                    "Kavinsky OutRun",
                    "The Midnight Endless Summer",
                    "Timecop1983 Night Drive",
                    "Daft Punk Random Access Memories",
                    "Jean-Michel Jarre Oxygene",
                    "FM-84 Atlas",
                    "Gunship Dark All Day",
                    "College A Real Hero",
                    "Miami Nights 1984 Turbulence",
                    "Com Truise Galactic Melt",
                    "Lazerhawk Redline"
                ]
            ),
            SonicArchetype(
                id: "triphop_downtempo_90s",
                titleRu: "Бристольский трип-хоп и глубокий даунтемпо",
                titleEn: "Bristol Trip-Hop & Deep Downtempo",
                descriptionRu: "Гипнотический ломаный ритм, глубокая низкочастотная основа, виниловый кракл и кинематографичная меланхолия школы Бристоля 90-х.",
                descriptionEn: "Hypnotic slow breakbeats, sub-heavy basslines, vinyl warmth, and cinematic Bristol melancholy.",
                semanticDescriptorEn: "trip-hop bristol downtempo 1990s nineties massive attack portishead dark bass groove hypnotic lounge",
                keywordsRu: ["трип-хоп", "трипхоп", "даунтемпо", "бристол", "90", "девяност", "бас", "меланхол", "гипнот"],
                keywordsEn: ["trip-hop", "triphop", "downtempo", "bristol", "90s", "massive attack", "portishead", "tricky", "chillout"],
                tagsRu: ["🔊 Суббас и брейкс", "🌑 Бристольский саунд", "💿 Эстетика 90-х", "Downtempo"],
                tagsEn: ["🔊 Sub-Bass & Breaks", "🌑 Bristol Sound", "💿 90s Classic", "Downtempo"],
                seedQueries: [
                    "Massive Attack Mezzanine",
                    "Portishead Dummy",
                    "Thievery Corporation The Mirror Conspiracy",
                    "Morcheeba Big Calm",
                    "Kruder & Dorfmeister The K&D Sessions",
                    "Zero 7 Simple Things",
                    "Air Moon Safari",
                    "Tricky Maxinquaye",
                    "Bonobo Black Sands",
                    "Hooverphonic A New Stereophonic Sound Spectacular",
                    "Nightmares on Wax Smokers Delight",
                    "UNKLE Psyence Fiction"
                ]
            ),
            SonicArchetype(
                id: "soul_funk_groove",
                titleRu: "Тёплый фанк, соул и живой грув",
                titleEn: "Warm Funk, Soul & Live Analog Groove",
                descriptionRu: "Упругий фанковый бас, духовая секция, винтажный клавесин Fender Rhodes и живая энергия студий Motown и Stax.",
                descriptionEn: "Punchy basslines, brass sections, vintage Fender Rhodes, and infectious live studio groove.",
                semanticDescriptorEn: "warm soul funk groove motown bass rhythm brass upbeat morning feel good live band",
                keywordsRu: ["фанк", "соул", "грув", "утр", "бодр", "ритм", "духов", "танц"],
                keywordsEn: ["funk", "soul", "groove", "motown", "upbeat", "morning", "bassline", "rhodes", "disco"],
                tagsRu: ["🎸 Фанковый бас", "🎺 Духовая секция", "☀️ Тёплый аналог", "Soul & Groove"],
                tagsEn: ["🎸 Funk Bass", "🎺 Brass Section", "☀️ Warm Analog", "Soul & Groove"],
                seedQueries: [
                    "Marvin Gaye What's Going On",
                    "Curtis Mayfield Super Fly",
                    "Khruangbin Con Todo El Mundo",
                    "Jamiroquai Travelling Without Moving",
                    "Sade Diamond Life",
                    "Bill Withers Still Bill",
                    "Vulfpeck Thrill of the Arts",
                    "Parcels Day/Night",
                    "Silk Sonic An Evening with Silk Sonic",
                    "Stevie Wonder Innervisions",
                    "Herbie Hancock Head Hunters",
                    "Roy Ayers Ubiquity Everybody Loves the Sunshine"
                ]
            ),
            SonicArchetype(
                id: "postrock_cinematic",
                titleRu: "Инструментальный пост-рок и звуковые пейзажи",
                titleEn: "Instrumental Post-Rock & Cinematic Crescendos",
                descriptionRu: "Масштабная динамика от шёпота чистых гитар до эпических оркестровых кульминаций с огромным динамическим диапазоном.",
                descriptionEn: "Sweeping dynamic range evolving from delicate clean guitars into monumental atmospheric crescendos.",
                semanticDescriptorEn: "instrumental post-rock cinematic crescendo electric guitar atmospheric epic wide dynamic range",
                keywordsRu: ["пост-рок", "построк", "инструментал", "пейзаж", "эпич", "кульминац", "динамик"],
                keywordsEn: ["post-rock", "postrock", "instrumental", "crescendo", "mogwai", "explosions", "sigur ros", "epic"],
                tagsRu: ["🎸 Пост-рок", "📈 Широкий DR", "🌌 Звуковой пейзаж", "Instrumental"],
                tagsEn: ["🎸 Post-Rock", "📈 Wide Dynamic Range", "🌌 Soundscape", "Instrumental"],
                seedQueries: [
                    "Explosions in the Sky The Earth Is Not a Cold Dead Place",
                    "Mogwai Happy Songs for Happy People",
                    "God Is An Astronaut All Is Violent, All Is Bright",
                    "Sigur Ros Agaetis byrjun",
                    "Mono Hymn to the Immortal Wind",
                    "Hammock Departure Songs",
                    "This Will Destroy You Young Mountain",
                    "Caspian Dust and Disquiet",
                    "Russian Circles Station",
                    "If These Trees Could Talk Red Forest",
                    " Jakob Solace",
                    "Tortoise Millions Now Living Will Never Die"
                ]
            ),
            SonicArchetype(
                id: "deep_dub_techno",
                titleRu: "Гипнотический даб-техно и минимал-электроника",
                titleEn: "Hypnotic Dub Techno & Deep Minimal Electronics",
                descriptionRu: "Глубокие пространственные аккорды с ленточным дилеем, выверенная микроперкуссия и трёхмерная акустическая глубина.",
                descriptionEn: "Cavernous tape-delayed chords, precision micro-percussion, and three-dimensional spatial depth.",
                semanticDescriptorEn: "dub techno minimal deep electronic hypnotic sub bass spatial chords berlin",
                keywordsRu: ["техно", "даб", "минимал", "электрон", "глубок", "ритм", "клуб"],
                keywordsEn: ["techno", "dub techno", "minimal", "electronic", "deep house", "hypnotic", "berlin", "modular"],
                tagsRu: ["🎛️ Модулярный синтез", "🌊 Пространственный даб", "🔊 Суббас 30 Гц", "Deep Electronic"],
                tagsEn: ["🎛️ Modular Synth", "🌊 Spatial Dub", "🔊 30Hz Sub-Bass", "Deep Electronic"],
                seedQueries: [
                    "Basic Channel BCD",
                    "Jan Jelinek Loop-Finding-Jazz-Records",
                    "Trentemoller The Last Resort",
                    "Nicolas Jaar Space Is Only Noise",
                    "Jon Hopkins Immunity",
                    "Moderat II",
                    "Rival Consoles Persona",
                    "Deepchord Liumin",
                    "Rhythm & Sound See Mi Yah",
                    "Kiasmos Kiasmos",
                    "Christian Loffler Mare",
                    "Apparat Walls"
                ]
            ),
            SonicArchetype(
                id: "blues_tube_guitar",
                titleRu: "Ламповый блюз-рок и живая гитара",
                titleEn: "Tube-Amp Blues Rock & Expressive Guitar",
                descriptionRu: "Тёплый ламповый овердрайв, страстная блюзовая гитара и живая динамика классической студийной записи без компрессии.",
                descriptionEn: "Warm tube amplifier overdrive, expressive blues guitar phrasing, and uncompressed studio dynamics.",
                semanticDescriptorEn: "blues rock electric guitar tube amp warm soulful solo Fender Stratocaster",
                keywordsRu: ["блюз", "гитар", "ламп", "соло", "рок-н-ролл"],
                keywordsEn: ["blues", "guitar", "tube", "clapton", "srv", "hendrix", "bb king", "knopfler"],
                tagsRu: ["🎸 Блюзовая гитара", "🔥 Ламповый тракт", "🥁 Живая динамика", "Blues Reference"],
                tagsEn: ["🎸 Blues Guitar", "🔥 Tube Warmth", "🥁 Live Dynamics", "Blues Reference"],
                seedQueries: [
                    "Stevie Ray Vaughan Texas Flood",
                    "Dire Straits Brothers in Arms",
                    "B.B. King Riding with the King",
                    "Eric Clapton Unplugged",
                    "Buddy Guy Blues Singer",
                    "Gary Moore Still Got the Blues",
                    "Joe Bonamassa Sloe Gin",
                    "John Mayer Continuum",
                    "J.J. Cale Naturally",
                    "muddy waters folk singer",
                    "Albert King Born Under a Bad Sign",
                    "Ry Cooder Paris, Texas"
                ]
            ),
            SonicArchetype(
                id: "prog_alt_metal",
                titleRu: "Прогрессив-метал и полиритмический арт-рок",
                titleEn: "Progressive Metal & Polyrhythmic Art-Rock",
                descriptionRu: "Гипнотические полиритмические риффы, сложные нечётные размеры, глубокий рельефный бас и масштабный динамический диапазон современного прогрессивного и альтернативного метала.",
                descriptionEn: "Hypnotic polyrhythmic riffs, intricate odd time signatures, visceral bass articulation, and expansive dynamic range.",
                semanticDescriptorEn: "progressive metal polyrhythmic odd meter art rock heavy guitar bass drums tool a perfect circle porcupine tree deftones",
                keywordsRu: ["прог-метал", "прогрессив-метал", "полиритм", "альт-метал", "арт-метал", "нечетн", "нечётн"],
                keywordsEn: ["prog metal", "progressive metal", "polyrhythmic", "odd meter", "alternative metal", "tool", "a perfect circle", "karnivool", "soen", "deftones", "mastodon", "opeth", "meshuggah", "gojira", "dream theater"],
                tagsRu: ["🥁 Полиритмия", "🎸 Прог-метал", "🔊 Рельефный бас", "🎚️ Высокий DR"],
                tagsEn: ["🥁 Polyrhythmic", "🎸 Prog Metal", "🔊 Visceral Bass", "🎚️ High DR"],
                seedQueries: [
                    "Tool Lateralus",
                    "Tool Aenima",
                    "A Perfect Circle Mer de Noms",
                    "Porcupine Tree In Absentia",
                    "Karnivool Sound Awake",
                    "Soen Lotus",
                    "Deftones White Pony",
                    "Wheel Moving Backwards",
                    "Opeth Damnation",
                    "Mastodon Crack the Skye",
                    "Puscifer Conditions of My Parole",
                    "Katatonia The Great Cold Distance"
                ]
            ),
            SonicArchetype(
                id: "analog_electro_krautrock",
                titleRu: "Аналоговая электроника, краут-рок и IDM",
                titleEn: "Analog Electronic Pioneers, Krautrock & IDM",
                descriptionRu: "Винтажные модулярные синтезаторы, роботизированный вокодер, моторик-пульсация дюссельдорфской и берлинской школ и эталонная пространственная панорама.",
                descriptionEn: "Vintage modular synthesizers, robotic vocoders, hypnotic motorik pulse, and pioneering electronic soundscapes.",
                semanticDescriptorEn: "krautrock analog electronic synthesizer vocoder motorik pioneer kraftwerk jean-michel jarre tangerine dream boards of canada aphex twin idm",
                keywordsRu: ["краутрок", "краут-рок", "модуляр", "секвенсор", "вокодер", "idm", "аналоговая электроника"],
                keywordsEn: ["krautrock", "kraftwerk", "jean-michel jarre", "tangerine dream", "boards of canada", "aphex twin", "idm", "vocoder", "motorik", "yellow magic orchestra", "royksopp", "underworld", "orbital"],
                tagsRu: ["🎹 Аналоговый синтез", "🤖 Краут-рок / IDM", "🎛️ Секвенсоры", "🎚️ Широкая панорама"],
                tagsEn: ["🎹 Analog Synth", "🤖 Krautrock / IDM", "🎛️ Sequencers", "🎚️ Wide Imaging"],
                seedQueries: [
                    "Kraftwerk The Man-Machine",
                    "Kraftwerk Trans-Europe Express",
                    "Jean-Michel Jarre Oxygene",
                    "Tangerine Dream Phaedra",
                    "Boards of Canada Music Has the Right to Children",
                    "Aphex Twin Selected Ambient Works 85-92",
                    "Yellow Magic Orchestra Solid State Survivor",
                    "Neu! Neu! 75",
                    "Giorgio Moroder From Here to Eternity",
                    "Röyksopp Melody A.M.",
                    "Orbital In Sides",
                    "Underworld Dubnobasswithmyheadman"
                ]
            ),
            SonicArchetype(
                id: "french_touch_nudisco",
                titleRu: "Французский электро-фанк, диско-хаус и French Touch",
                titleEn: "French Touch, Electro-Funk & Nu-Disco",
                descriptionRu: "Упругий фанковый бас, винтажные синтезаторы, ток-бокс, живая студийная секция и эталонный грув эстетики French Touch и современного ню-диско.",
                descriptionEn: "Punchy slap bass, talkbox and vocoder textures, live studio instrumentation, and infectious French Touch groove.",
                semanticDescriptorEn: "french touch nu-disco electro funk disco house vocoder slap bass daft punk justice parcels air jamiroquai",
                keywordsRu: ["френч-тач", "французский хаус", "электро-фанк", "ню-диско", "диско-фанк", "ток-бокс"],
                keywordsEn: ["french touch", "nu-disco", "nudisco", "electro funk", "daft punk", "justice", "parcels", "l'imperatrice", "cassius", "modjo", "breakbot", "chromeo"],
                tagsRu: ["🪩 French Touch", "🎸 Электро-фанк", "🤖 Вокодер и грув", "🎚️ Студийный эталон"],
                tagsEn: ["🪩 French Touch", "🎸 Electro-Funk", "🤖 Vocoder Groove", "🎚️ Studio Reference"],
                seedQueries: [
                    "Daft Punk Random Access Memories",
                    "Daft Punk Discovery",
                    "Justice Cross",
                    "Parcels Day/Night",
                    "Air Moon Safari",
                    "L'Imperatrice Tako Tsubo",
                    "Jamiroquai Travelling Without Moving",
                    "Cassius 1999",
                    "Modjo Modjo",
                    "Chromeo Fancy Footwork",
                    "Breakbot By Your Side",
                    "Purple Disco Machine Exotica"
                ]
            ),
            SonicArchetype(
                id: "alt_rock_postpunk",
                titleRu: "Альтернативный рок, инди и атмосферный пост-панк",
                titleEn: "Alternative Rock, Art-Indie & Post-Punk",
                descriptionRu: "Глубокая меланхоличная атмосфера, перегруженные и реверберирующие гитары, выразительная бас-линия и кинематографичная эстетика альтернативной сцены.",
                descriptionEn: "Atmospheric guitars, driving post-punk basslines, art-rock textures, and emotional alternative soundscapes.",
                semanticDescriptorEn: "alternative rock post-punk indie rock shoegaze dream pop dark wave radiohead depeche mode the cure joy division",
                keywordsRu: ["альтернатив", "альт-рок", "пост-панк", "постпанк", "инди-рок", "шугейз", "дрим-поп", "нью-вейв"],
                keywordsEn: ["alternative rock", "post-punk", "indie rock", "shoegaze", "dream pop", "radiohead", "depeche mode", "the cure", "joy division", "new order", "interpol", "slowdive", "muse", "placebo", "tame impala"],
                tagsRu: ["🎸 Альт-рок и инди", "🌑 Пост-панк атмосфера", "🌊 Гитарный реверб", "🎚️ Аналоговый драйв"],
                tagsEn: ["🎸 Alt-Rock & Indie", "🌑 Post-Punk Vibe", "🌊 Lush Reverb", "🎚️ Analog Drive"],
                seedQueries: [
                    "Radiohead In Rainbows",
                    "Radiohead OK Computer",
                    "Depeche Mode Violator",
                    "The Cure Disintegration",
                    "Joy Division Unknown Pleasures",
                    "Interpol Turn On the Bright Lights",
                    "Slowdive Slowdive",
                    "Muse Origin of Symmetry",
                    "The Smashing Pumpkins Siamese Dream",
                    "Placebo Without You I'm Nothing",
                    "Tame Impala Currents",
                    "Arctic Monkeys AM"
                ]
            ),
            SonicArchetype(
                id: "heavy_metal_hard_rock",
                titleRu: "Хард-рок, хеви-метал и индустриальный драйв",
                titleEn: "Hard Rock, Heavy Metal & Industrial Drive",
                descriptionRu: "Мощные гитарные риффы, плотная ударная секция, ламповый перегруз и бескомпромиссная энергия классического хард-рока и метала.",
                descriptionEn: "Crushing guitar riffs, thunderous drums, high-gain tube saturation, and raw rock energy.",
                semanticDescriptorEn: "heavy metal hard rock industrial grunge distortion guitar riffs drums metallica black sabbath led zeppelin rammstein",
                keywordsRu: ["хард-рок", "хеви-метал", "хэви-метал", "метал", "индастриал", "гранж", "рифф", "тяжелый рок"],
                keywordsEn: ["heavy metal", "hard rock", "industrial", "grunge", "metallica", "black sabbath", "led zeppelin", "iron maiden", "rammstein", "nine inch nails", "system of a down", "rage against the machine", "nirvana", "alice in chains"],
                tagsRu: ["🔥 Мощные риффы", "🥁 Панч и драйв", "🎸 Ламповый перегруз", "🎚️ Рок-классика"],
                tagsEn: ["🔥 Heavy Riffs", "🥁 Punch & Drive", "🎸 Tube Distortion", "🎚️ Rock Classics"],
                seedQueries: [
                    "Metallica Master of Puppets",
                    "Black Sabbath Paranoid",
                    "Led Zeppelin Physical Graffiti",
                    "Iron Maiden Powerslave",
                    "Rammstein Mutter",
                    "Nine Inch Nails The Downward Spiral",
                    "System of a Down Toxicity",
                    "Rage Against the Machine Rage Against the Machine",
                    "Alice in Chains Dirt",
                    "Soundgarden Superunknown",
                    "Deep Purple Machine Head",
                    "AC/DC Back in Black"
                ]
            )
        ]
    }

    // MARK: - Curated Artist Style & Peer Graph

    private static func buildArtistStyleProfiles() -> [ArtistStyleProfile] {
        return [
            ArtistStyleProfile(
                canonicalArtist: "Tool",
                aliases: ["tool", "тул", "toolband"],
                archetypeId: "prog_alt_metal",
                styleTitleRu: "Прогрессив-метал и полиритмический арт-рок",
                styleTitleEn: "Progressive Metal & Polyrhythmic Art-Rock",
                customDescriptionRu: "Гипнотические полиритмические риффы, сложные нечётные размеры, глубокий бас Justin Chancellor и масштабная динамика школы Tool и родственных прог-метал проектов.",
                customDescriptionEn: "Hypnotic polyrhythmic riffs, intricate odd meters, visceral bass articulation, and monumental progressive metal dynamics inspired by Tool.",
                seedQueries: [
                    "Tool Lateralus",
                    "Tool Aenima",
                    "Tool Fear Inoculum",
                    "A Perfect Circle Mer de Noms",
                    "Porcupine Tree In Absentia",
                    "Karnivool Sound Awake",
                    "Soen Lotus",
                    "Wheel Moving Backwards",
                    "Deftones White Pony",
                    "Puscifer Conditions of My Parole",
                    "Opeth Damnation",
                    "Mastodon Crack the Skye"
                ]
            ),
            ArtistStyleProfile(
                canonicalArtist: "Kraftwerk",
                aliases: ["kraftwerk", "крафтверк", "крафтверг"],
                archetypeId: "analog_electro_krautrock",
                styleTitleRu: "Аналоговая электроника и краут-рок",
                styleTitleEn: "Analog Electronic Pioneers & Krautrock",
                customDescriptionRu: "Винтажные аналоговые синтезаторы, роботизированный вокодер, гипнотическая моторик-пульсация дюссельдорфской школы и пионеры электронной сцены.",
                customDescriptionEn: "Vintage analog synthesizers, robotic vocoders, hypnotic Düsseldorf motorik pulse, and electronic pioneers.",
                seedQueries: [
                    "Kraftwerk The Man-Machine",
                    "Kraftwerk Trans-Europe Express",
                    "Kraftwerk Computer World",
                    "Jean-Michel Jarre Oxygene",
                    "Tangerine Dream Phaedra",
                    "Yellow Magic Orchestra Solid State Survivor",
                    "Neu! Neu! 75",
                    "Giorgio Moroder From Here to Eternity",
                    "Boards of Canada Music Has the Right to Children",
                    "Röyksopp Melody A.M.",
                    "Aphex Twin Selected Ambient Works 85-92",
                    "Can Future Days"
                ]
            ),
            ArtistStyleProfile(
                canonicalArtist: "Daft Punk",
                aliases: ["daft punk", "дафт панк"],
                archetypeId: "french_touch_nudisco",
                styleTitleRu: "Французский электро-фанк и диско-грув",
                styleTitleEn: "French Touch, Electro-Funk & Nu-Disco",
                customDescriptionRu: "Упругий фанковый бас, винтажные синтезаторы, ток-бокс и вокодер, живая студийная секция и эталонный грув эстетики Daft Punk и French Touch.",
                customDescriptionEn: "Punchy funk basslines, vintage synthesizers, vocoders, live studio instrumentation, and signature French Touch groove.",
                seedQueries: [
                    "Daft Punk Random Access Memories",
                    "Daft Punk Discovery",
                    "Justice Cross",
                    "Parcels Day/Night",
                    "Air Moon Safari",
                    "L'Imperatrice Tako Tsubo",
                    "Cassius 1999",
                    "Modjo Modjo",
                    "Jamiroquai Travelling Without Moving",
                    "Chromeo Fancy Footwork",
                    "Breakbot By Your Side",
                    "Giorgio Moroder From Here to Eternity"
                ]
            ),
            ArtistStyleProfile(
                canonicalArtist: "Pink Floyd",
                aliases: ["pink floyd", "пинк флойд", "флойд", "david gilmour", "дэвид гилмор", "roger waters", "роджер уотерс"],
                archetypeId: "prog_rock_70s",
                styleTitleRu: "Аналоговый прог-рок 70-х и широкая сцена",
                styleTitleEn: "70s Analog Progressive Rock & Wide Soundstage",
                customDescriptionRu: nil,
                customDescriptionEn: nil,
                seedQueries: [
                    "Pink Floyd Wish You Were Here",
                    "Pink Floyd The Dark Side of the Moon",
                    "David Gilmour On an Island",
                    "Alan Parsons Project Eye in the Sky",
                    "Porcupine Tree The Sky Moves Sideways",
                    "Camel Mirage",
                    "Dire Straits Love Over Gold",
                    "King Crimson In the Court of the Crimson King",
                    "Steven Wilson The Raven That Refused to Sing",
                    "Supertramp Crime of the Century",
                    "Air Moon Safari",
                    "RPWL World Through My Eyes"
                ]
            ),
            ArtistStyleProfile(
                canonicalArtist: "Deftones",
                aliases: ["deftones", "дефтонс", "дефтоунс", "team sleep", "crosses"],
                archetypeId: "prog_alt_metal",
                styleTitleRu: "Атмосферный альт-метал и тяжёлый шугейз",
                styleTitleEn: "Atmospheric Alt-Metal & Heavy Shoegaze",
                customDescriptionRu: "Контраст обволакивающего гитарного реверба и плотных низкочастотных риффов, чувственный вокал и гипнотическая ночная атмосфера.",
                customDescriptionEn: "Lush shoegaze reverb colliding with heavy downtuned riffs and hypnotic nocturnal dynamics.",
                seedQueries: [
                    "Deftones White Pony",
                    "Deftones Diamond Eyes",
                    "Deftones Koi No Yokan",
                    "A Perfect Circle Thirteenth Step",
                    "Tool Lateralus",
                    "Team Sleep Team Sleep",
                    "Loathe I Let It in and It Took Everything",
                    "Chevelle Wonder What's Next",
                    "Incubus Morning View",
                    "Smashing Pumpkins Siamese Dream",
                    "Karnivool Sound Awake",
                    "Katatonia The Great Cold Distance"
                ]
            ),
            ArtistStyleProfile(
                canonicalArtist: "Radiohead",
                aliases: ["radiohead", "радиохед", "радиохэд", "thom yorke", "том йорк", "the smile"],
                archetypeId: "alt_rock_postpunk",
                styleTitleRu: "Экспериментальный арт-рок и электроника",
                styleTitleEn: "Experimental Art-Rock & Electronic Melancholy",
                customDescriptionRu: nil,
                customDescriptionEn: nil,
                seedQueries: [
                    "Radiohead In Rainbows",
                    "Radiohead OK Computer",
                    "Radiohead Kid A",
                    "The Smile A Light for Attracting Attention",
                    "Thom Yorke The Eraser",
                    "Portishead Third",
                    "Massive Attack Mezzanine",
                    "Sigur Ros Agaetis byrjun",
                    "Alt-J An Awesome Wave",
                    "Archive Londinium",
                    "Porcupine Tree Stupid Dream",
                    "Talk Talk Laughing Stock"
                ]
            ),
            ArtistStyleProfile(
                canonicalArtist: "Depeche Mode",
                aliases: ["depeche mode", "депеш мод", "дэпеш мод"],
                archetypeId: "alt_rock_postpunk",
                styleTitleRu: "Тёмный синт-поп, дарквейв и электро-рок",
                styleTitleEn: "Dark Synth-Pop, Darkwave & Electro-Rock",
                customDescriptionRu: nil,
                customDescriptionEn: nil,
                seedQueries: [
                    "Depeche Mode Violator",
                    "Depeche Mode Songs of Faith and Devotion",
                    "Depeche Mode Ultra",
                    "New Order Power, Corruption & Lies",
                    "The Cure Disintegration",
                    "Camouflage Voices & Images",
                    "Tears for Fears Songs from the Big Chair",
                    "Massive Attack Mezzanine",
                    "Nine Inch Nails Pretty Hate Machine",
                    "Placebo Black Market Music",
                    "Röyksopp The Inevitable End",
                    "Editors The Back Room"
                ]
            ),
            ArtistStyleProfile(
                canonicalArtist: "Metallica",
                aliases: ["metallica", "металлика", "металика"],
                archetypeId: "heavy_metal_hard_rock",
                styleTitleRu: "Трэш-метал и монументальный хеви-метал",
                styleTitleEn: "Thrash Metal & Monumental Heavy Metal",
                customDescriptionRu: nil,
                customDescriptionEn: nil,
                seedQueries: [
                    "Metallica Master of Puppets",
                    "Metallica Metallica",
                    "Metallica Ride the Lightning",
                    "Megadeth Rust in Peace",
                    "Iron Maiden Powerslave",
                    "Black Sabbath Paranoid",
                    "Pantera Vulgar Display of Power",
                    "Testament The Gathering",
                    "Judas Priest Painkiller",
                    "Alice in Chains Dirt",
                    "Gojira Magma",
                    "Avenged Sevenfold Nightmare"
                ]
            ),
            ArtistStyleProfile(
                canonicalArtist: "Rammstein",
                aliases: ["rammstein", "раммштайн", "рамштайн", "lindemann", "линдеманн"],
                archetypeId: "heavy_metal_hard_rock",
                styleTitleRu: "Индастриал-метал и Neue Deutsche Härte",
                styleTitleEn: "Industrial Metal & Neue Deutsche Härte",
                customDescriptionRu: nil,
                customDescriptionEn: nil,
                seedQueries: [
                    "Rammstein Mutter",
                    "Rammstein Reise, Reise",
                    "Rammstein Sehnsucht",
                    "Nine Inch Nails The Downward Spiral",
                    "Oomph! Wahrheit oder Pflicht",
                    "Eisbrecher Antikörper",
                    "Megaherz Herzwerk II",
                    "Marilyn Manson Antichrist Superstar",
                    "Ministry Psalm 69",
                    "Rob Zombie Hellbilly Deluxe",
                    "KMFDM Nihil",
                    "Lindemann Skills in Pills"
                ]
            ),
            ArtistStyleProfile(
                canonicalArtist: "The Prodigy",
                aliases: ["the prodigy", "prodigy", "продиджи"],
                archetypeId: "analog_electro_krautrock",
                styleTitleRu: "Биг-бит, брейкбит и рейв-электроника 90-х",
                styleTitleEn: "Big Beat, Breakbeat & High-Energy Rave",
                customDescriptionRu: "Взрывной ломаный ритм, кислотные синтезаторы Roland TB-303 и эталонный драйв британской биг-бит и брейкбит-сцены.",
                customDescriptionEn: "Explosive breakbeats, acid synthesizers, and high-octane British big beat energy.",
                seedQueries: [
                    "The Prodigy The Fat of the Land",
                    "The Prodigy Music for the Jilted Generation",
                    "The Chemical Brothers Dig Your Own Hole",
                    "The Chemical Brothers Surrender",
                    "The Crystal Method Vegas",
                    "Fatboy Slim You've Come a Long Way, Baby",
                    "Propellerheads Decksandrumsandrockandroll",
                    "Leftfield Leftism",
                    "Underworld Dubnobasswithmyheadman",
                    "Orbital In Sides",
                    "Justice Cross",
                    "Pendulum Hold Your Colour"
                ]
            ),
            ArtistStyleProfile(
                canonicalArtist: "Кино",
                aliases: ["кино", "группа кино", "виктор цой", "цой", "kino", "viktor tsoi"],
                archetypeId: "alt_rock_postpunk",
                styleTitleRu: "Русский пост-панк и ленинградская новая волна",
                styleTitleEn: "Russian Post-Punk & New Wave Classics",
                customDescriptionRu: "Мелодичная бас-линия, драм-машина, звенящая гитара Каспаряна и культовая атмосфера ленинградского рок-клуба и отечественного пост-панка.",
                customDescriptionEn: "Melodic post-punk basslines, drum machines, jangly guitars, and iconic Leningrad rock club atmosphere.",
                seedQueries: [
                    "Кино Группа крови",
                    "Кино Звезда по имени Солнце",
                    "Кино Черный альбом",
                    "Наутилус Помпилиус Разлука",
                    "Агата Кристи Опиум",
                    "Альянс На заре",
                    "Би-2 Би-2",
                    "Сплин Гранатовый альбом",
                    "ДДТ Актриса Весна",
                    "Молчат Дома Этажи",
                    "Пикник Египтянин",
                    "Земфира Земфира"
                ]
            ),
            ArtistStyleProfile(
                canonicalArtist: "Молчат Дома",
                aliases: ["молчат дома", "molchat doma", "ploho", "дурной вкус", "буерак"],
                archetypeId: "alt_rock_postpunk",
                styleTitleRu: "Холодный пост-панк, колдвейв и синт-вейв",
                styleTitleEn: "Modern Post-Punk, Coldwave & Minimal Synth",
                customDescriptionRu: nil,
                customDescriptionEn: nil,
                seedQueries: [
                    "Молчат Дома Этажи",
                    "Молчат Дома Монумент",
                    "Кино Группа крови",
                    "Альянс На заре",
                    "Joy Division Unknown Pleasures",
                    "New Order Power, Corruption & Lies",
                    "The Cure Seventeen Seconds",
                    "Lebanon Hanover Tomb for Two",
                    "She Past Away Belirdi Gece",
                    "Дурной Вкус Светомузыка",
                    "Ploho Куда птицы улетают умирать",
                    "Буерак Танцы по расчёту"
                ]
            ),
            ArtistStyleProfile(
                canonicalArtist: "Massive Attack",
                aliases: ["massive attack", "массив аттак", "portishead", "портисхед", "tricky", "трики"],
                archetypeId: "triphop_downtempo_90s",
                styleTitleRu: "Бристольский трип-хоп и глубокий даунтемпо",
                styleTitleEn: "Bristol Trip-Hop & Deep Downtempo",
                customDescriptionRu: nil,
                customDescriptionEn: nil,
                seedQueries: [
                    "Massive Attack Mezzanine",
                    "Massive Attack Blue Lines",
                    "Portishead Dummy",
                    "Tricky Maxinquaye",
                    "UNKLE Psyence Fiction",
                    "Archive Londinium",
                    "Morcheeba Big Calm",
                    "Thievery Corporation The Mirror Conspiracy",
                    "Hooverphonic A New Stereophonic Sound Spectacular",
                    "Kruder & Dorfmeister The K&D Sessions",
                    "Lamb Lamb",
                    "Bonobo Black Sands"
                ]
            ),
            ArtistStyleProfile(
                canonicalArtist: "Porcupine Tree",
                aliases: ["porcupine tree", "поркупайн три", "steven wilson", "стивен уилсон"],
                archetypeId: "prog_alt_metal",
                styleTitleRu: "Современный прогрессив-рок и аудиофильский арт-метал",
                styleTitleEn: "Modern Progressive Rock & Audiophile Art-Metal",
                customDescriptionRu: nil,
                customDescriptionEn: nil,
                seedQueries: [
                    "Porcupine Tree In Absentia",
                    "Porcupine Tree Deadwing",
                    "Steven Wilson The Raven That Refused to Sing",
                    "Steven Wilson Hand. Cannot. Erase.",
                    "Opeth Damnation",
                    "Riverside Second Life Syndrome",
                    "Anathema Weather Systems",
                    "Pineapple Thief Your Wilderness",
                    "Tool Lateralus",
                    "Katatonia The Great Cold Distance",
                    "Karnivool Sound Awake",
                    "Pink Floyd Wish You Were Here"
                ]
            ),
            ArtistStyleProfile(
                canonicalArtist: "Nirvana",
                aliases: ["nirvana", "нирвана", "kurt cobain", "курт кобейн", "alice in chains", "элис ин чейнс", "soundgarden"],
                archetypeId: "heavy_metal_hard_rock",
                styleTitleRu: "Сиэтлский гранж и альтернативный рок 90-х",
                styleTitleEn: "Seattle Grunge & 90s Alternative Rock",
                customDescriptionRu: nil,
                customDescriptionEn: nil,
                seedQueries: [
                    "Nirvana Nevermind",
                    "Nirvana MTV Unplugged in New York",
                    "Alice in Chains Dirt",
                    "Alice in Chains Jar of Flies",
                    "Soundgarden Superunknown",
                    "Pearl Jam Ten",
                    "Stone Temple Pilots Core",
                    "Mad Season Above",
                    "Smashing Pumpkins Siamese Dream",
                    "Pixies Doolittle",
                    "Foo Fighters The Colour and the Shape",
                    "Audioslave Audioslave"
                ]
            ),
            ArtistStyleProfile(
                canonicalArtist: "Led Zeppelin",
                aliases: ["led zeppelin", "лед зеппелин", "зеппелин", "deep purple", "дип перпл", "black sabbath", "блэк саббат"],
                archetypeId: "heavy_metal_hard_rock",
                styleTitleRu: "Золотая эра хард-рока и блюз-рока 70-х",
                styleTitleEn: "70s Golden Era Hard Rock & Heavy Blues",
                customDescriptionRu: nil,
                customDescriptionEn: nil,
                seedQueries: [
                    "Led Zeppelin Physical Graffiti",
                    "Led Zeppelin IV",
                    "Deep Purple Machine Head",
                    "Black Sabbath Paranoid",
                    "Rainbow Rising",
                    "Cream Disraeli Gears",
                    "Jimi Hendrix Electric Ladyland",
                    "The Doors L.A. Woman",
                    "AC/DC Back in Black",
                    "Rush Moving Pictures",
                    "Free Fire and Water",
                    "Uriah Heep Demons and Wizards"
                ]
            ),
            ArtistStyleProfile(
                canonicalArtist: "Tame Impala",
                aliases: ["tame impala", "тейм импала", "gorillaz", "гориллаз"],
                archetypeId: "alt_rock_postpunk",
                styleTitleRu: "Нео-психоделия, синт-грув и инди-электроника",
                styleTitleEn: "Neo-Psychedelia, Synth Groove & Indie Electronica",
                customDescriptionRu: nil,
                customDescriptionEn: nil,
                seedQueries: [
                    "Tame Impala Currents",
                    "Tame Impala Lonerism",
                    "Gorillaz Demon Days",
                    "Gorillaz Plastic Beach",
                    "MGMT Oracular Spectacular",
                    "Unknown Mortal Orchestra Multi-Love",
                    "Khruangbin Con Todo El Mundo",
                    "Parcels Day/Night",
                    "Pond The Weather",
                    "Beach House Bloom",
                    "Empire of the Sun Walking On a Dream",
                    "Air Moon Safari"
                ]
            ),
            ArtistStyleProfile(
                canonicalArtist: "Hans Zimmer",
                aliases: ["hans zimmer", "ханс циммер", "циммер", "johann johannsson", "max richter", "макс рихтер", "ludovico einaudi", "эйнауди"],
                archetypeId: "ambient_neoclassical_focus",
                styleTitleRu: "Масштабная неоклассика и эпические саундтреки",
                styleTitleEn: "Epic Cinematic Scores & Modern Neoclassical",
                customDescriptionRu: nil,
                customDescriptionEn: nil,
                seedQueries: [
                    "Hans Zimmer Interstellar",
                    "Hans Zimmer Inception",
                    "Max Richter The Blue Notebooks",
                    "Johann Johannsson Orphee",
                    "Ludovico Einaudi In a Time Lapse",
                    "Nils Frahm All Melody",
                    "Olafur Arnalds re:member",
                    "Ramin Djawadi Westworld",
                    "Clint Mansell The Fountain",
                    "Vangelis Blade Runner",
                    "Howard Shore The Lord of the Rings",
                    "Hildur Gudnadottir Chernobyl"
                ]
            ),
            ArtistStyleProfile(
                canonicalArtist: "Polyphia",
                aliases: ["polyphia", "полифия", "animals as leaders", "plini", "intervals"],
                archetypeId: "prog_alt_metal",
                styleTitleRu: "Инструментальный прог-рок, мат-рок и гитарный виртуоз",
                styleTitleEn: "Instrumental Prog, Math-Rock & Virtuoso Guitar",
                customDescriptionRu: nil,
                customDescriptionEn: nil,
                seedQueries: [
                    "Polyphia Remember That You Will Die",
                    "Polyphia New Levels New Devils",
                    "Animals as Leaders The Joy of Motion",
                    "Plini Handmade Cities",
                    "Intervals Circadian",
                    "Chon Grow",
                    "Covet Effloresce",
                    "Scale the Summit The Migration",
                    "Liquid Tension Experiment",
                    "Tesseract Altered State",
                    "Karnivool Sound Awake",
                    "Tool Lateralus"
                ]
            )
        ]
    }
}
