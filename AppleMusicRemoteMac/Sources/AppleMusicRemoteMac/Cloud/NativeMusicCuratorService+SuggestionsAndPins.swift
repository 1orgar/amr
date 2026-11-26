import Foundation

extension NativeMusicCuratorService {

    internal static let allPromptSuggestions: [PromptSuggestionItem] = [
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
        AppStorageProvider.shared.removeObject(forKey: pinnedStorageKey)
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
        AppStorageProvider.shared.set(serialized, forKey: pinnedStorageKey)
    }

    private static func buildConciseLabel(from rawText: String) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return AMRLocalization.tr("✨ AI Vibe", "✨ AI-вайб") }
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
        let preferEnglish = !MusicKitManager.shared.isSystemLocaleRussian
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
}
