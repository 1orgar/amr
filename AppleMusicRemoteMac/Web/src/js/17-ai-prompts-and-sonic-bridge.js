  const AI_PROMPT_SUGGESTIONS_POOL = [
    {
      labelRu: '🎷 Ночной нуар-джаз с саксофоном',
      labelEn: '🎷 Late-night noir jazz with sax',
      promptRu: 'Ночной нуар-джаз с тёплым саксофоном и контрабасом',
      promptEn: 'Late-night noir jazz with warm tenor saxophone and upright bass'
    },
    {
      labelRu: '🎸 Аналоговый прог-рок 70-х',
      labelEn: '🎸 70s analog progressive rock',
      promptRu: 'Аналоговый прог-рок 70-х с широкой голографической сценой',
      promptEn: '1970s analog progressive rock with wide holographic soundstage'
    },
    {
      labelRu: '🎹 Эмбиент и пианино для фокуса',
      labelEn: '🎹 Deep ambient & piano for focus',
      promptRu: 'Глубокий эмбиент и неоклассическое пианино для фокуса',
      promptEn: 'Deep ambient and neoclassical felt piano for focus'
    },
    {
      labelRu: '🎙️ Эталонный вокал и акустика',
      labelEn: '🎙️ Reference vocals & acoustics',
      promptRu: 'Аудиофильский эталонный женский вокал и живая акустика',
      promptEn: 'Audiophile reference female vocal and intimate acoustic guitar'
    },
    {
      labelRu: '🌃 Кинематографичный синтвейв 80-х',
      labelEn: '🌃 Cinematic 80s synthwave',
      promptRu: 'Кинематографичный синтвейв 80-х и глубокий аналоговый синт',
      promptEn: 'Cinematic 1980s synthwave and deep analog synthesizers'
    },
    {
      labelRu: '🔊 Бристольский трип-хоп и даунтемпо',
      labelEn: '🔊 Bristol trip-hop & downtempo',
      promptRu: 'Бристольский трип-хоп 90-х и глубокий даунтемпо с суббасом',
      promptEn: '1990s Bristol trip-hop and deep downtempo sub-bass groove'
    },
    {
      labelRu: '🎻 Камерные струнные и виолончель',
      labelEn: '🎻 Chamber strings & live cello',
      promptRu: 'Скандинавская неоклассика, живая виолончель и камерные струнные',
      promptEn: 'Nordic neoclassical chamber strings and intimate acoustic cello'
    },
    {
      labelRu: '🌊 Дрим-поп и воздушный шугейз',
      labelEn: '🌊 Dream-pop & airy shoegaze',
      promptRu: 'Атмосферный дрим-поп и воздушный шугейз с гитарным ревербом',
      promptEn: 'Atmospheric dream-pop and ethereal shoegaze with lush reverb'
    },
    {
      labelRu: '🥃 Классический блюз-рок на лампе',
      labelEn: '🥃 Tube-driven blues rock',
      promptRu: 'Аудиофильский блюз-рок с живой ламповой гитарой и органом Hammond',
      promptEn: 'Audiophile blues rock with warm tube guitar and Hammond organ'
    },
    {
      labelRu: '🎺 Джаз-фанк и винтажный Rhodes',
      labelEn: '🎺 Jazz-funk & vintage Rhodes',
      promptRu: 'Винтажный джаз-фанк 70-х, тёплый Fender Rhodes и плотный грув',
      promptEn: '1970s spiritual jazz-funk with warm Fender Rhodes and tight bass'
    },
    {
      labelRu: '🌌 Космическая электроника (Берлин)',
      labelEn: '🌌 Berlin school cosmic synth',
      promptRu: 'Космическая аналоговая электроника в стиле берлинской школы и секвенсоры',
      promptEn: 'Cosmic Berlin-school analog modular synthesizers and arpeggios'
    },
    {
      labelRu: '☕ Босса-нова и акустика 60-х',
      labelEn: '☕ 60s bossa nova & nylon guitar',
      promptRu: 'Тёплая бразильская босса-нова 60-х с нейлоновой гитарой и мягким вокалом',
      promptEn: 'Warm 1960s Brazilian bossa nova with nylon guitar and soft vocals'
    },
    {
      labelRu: '🥁 Сложный мат-рок и полиритмия',
      labelEn: '🥁 Math-rock & odd-meter drums',
      promptRu: 'Инструментальный пост-рок и полиритмический прог с эталонной динамикой барабанов',
      promptEn: 'Instrumental post-rock and polyrhythmic prog with reference drum dynamics'
    },
    {
      labelRu: '🕯️ Дарк-джаз и кинематографичный нуар',
      labelEn: '🕯️ Dark jazz & cinematic noir',
      promptRu: 'Медленный дарк-джаз, баритон-саксофон и атмосфера дождливого ночного города',
      promptEn: 'Slow cinematic dark jazz with baritone sax and rainy midnight atmosphere'
    },
    {
      labelRu: '🎛️ Минимал-техно и даб-аккорды',
      labelEn: '🎛️ Dub techno & deep sub-bass',
      promptRu: 'Глубокий даб-техно и гипнотический минимал с бархатным суббасом',
      promptEn: 'Deep hypnotic dub techno and minimal electronica with cavernous sub-bass'
    },
    {
      labelRu: '🪕 Инди-фолк и камерная акустика',
      labelEn: '🪕 Indie folk & warm acoustics',
      promptRu: 'Камерный инди-фолк, живой пальцевый перебор гитары и интимная сцена',
      promptEn: 'Intimate indie folk with fingerstyle acoustic guitar and natural room acoustics'
    },
    {
      labelRu: '🎼 Симфонические саундтреки',
      labelEn: '🎼 Epic orchestral soundtracks',
      promptRu: 'Масштабные симфонические саундтреки с широким динамическим диапазоном',
      promptEn: 'Epic orchestral film scores with wide audiophile dynamic range'
    },
    {
      labelRu: '🪩 Японский сити-поп 80-х',
      labelEn: '🪩 80s Japanese city pop & funk',
      promptRu: 'Японский сити-поп и соул-фанк 80-х с ярким слэп-басом и духовыми',
      promptEn: '1980s Japanese city pop and boogie funk with slap bass and brass'
    }
  ];

  const AI_DYNAMIC_MOODS = [
    { icon: '🎷', shortRu: 'Ночной нуар', fullRu: 'Ночной атмосферный нуар', shortEn: 'Midnight noir', fullEn: 'Late-night atmospheric noir' },
    { icon: '🌌', shortRu: 'Глубокий космос', fullRu: 'Глубокая космическая атмосфера', shortEn: 'Deep cosmos', fullEn: 'Deep cosmic atmosphere' },
    { icon: '🕯️', shortRu: 'Интимная сцена', fullRu: 'Камерная интимная акустика близкого поля', shortEn: 'Intimate stage', fullEn: 'Near-field intimate chamber acoustics' },
    { icon: '⚡', shortRu: 'Высокий драйв', fullRu: 'Высокодинамичный драйв и панч', shortEn: 'High-energy drive', fullEn: 'High-contrast dynamic drive and punch' },
    { icon: '🌊', shortRu: 'Голографический 3D', fullRu: 'Широкая голографическая звуковая сцена', shortEn: '3D soundstage', fullEn: 'Wide holographic 3D soundstage' },
    { icon: '🥃', shortRu: 'Тёплая лампа', fullRu: 'Тёплое аналоговое ламповое звучание', shortEn: 'Warm tube glow', fullEn: 'Warm analog vacuum-tube timbre' },
    { icon: '🌧️', shortRu: 'Дождливый город', fullRu: 'Меланхолия дождливого ночного мегаполиса', shortEn: 'Rainy midnight', fullEn: 'Rainy midnight metropolis atmosphere' },
    { icon: '🧘', shortRu: 'Глубокий фокус', fullRu: 'Спокойная гипнотическая концентрация', shortEn: 'Deep focus', fullEn: 'Hypnotic calm for deep focus' },
    { icon: '🌆', shortRu: 'Неоновый ретро', fullRu: 'Кинематографичный неоновый ретро-вайб', shortEn: 'Neon retro', fullEn: 'Cinematic neon retro atmosphere' },
    { icon: '🏔️', shortRu: 'Северный воздух', fullRu: 'Прозрачная скандинавская прохлада', shortEn: 'Nordic air', fullEn: 'Crystalline Nordic spaciousness' },
    { icon: '🔥', shortRu: 'Живая студия', fullRu: 'Энергия живой студийной записи с одного дубля', shortEn: 'Live studio take', fullEn: 'Raw one-take live studio energy' },
    { icon: '🌙', shortRu: 'После полуночи', fullRu: 'Мягкий бархатный грув после полуночи', shortEn: 'After-hours', fullEn: 'Velvet after-hours lounge groove' },
    { icon: '💎', shortRu: 'Кристальный Hi-Res', fullRu: 'Эталонная прозрачность и микродинамика', shortEn: 'Reference Hi-Res', fullEn: 'Reference transparency and micro-dynamics' },
    { icon: '🎞️', shortRu: 'Магнитная лента', fullRu: 'Винтажный мастеринг на аналоговую ленту', shortEn: 'Analog tape', fullEn: 'Vintage reel-to-reel analog tape warmth' },
    { icon: '🌅', shortRu: 'Рассветный чилл', fullRu: 'Тёплый солнечный рассветный грув', shortEn: 'Sunrise chill', fullEn: 'Warm golden-hour sunrise groove' },
    { icon: '🌀', shortRu: 'Психоделика', fullRu: 'Глубокое психоделическое погружение', shortEn: 'Psychedelic voyage', fullEn: 'Deep psychedelic sonic immersion' }
  ];

  const AI_DYNAMIC_GENRES = [
    { shortRu: 'прог-рок 70-х', fullRu: 'прогрессивный рок 70-х', shortEn: '70s prog rock', fullEn: '1970s progressive rock' },
    { shortRu: 'кул-джаз', fullRu: 'модальный и кул-джаз', shortEn: 'cool jazz', fullEn: 'modal and cool jazz' },
    { shortRu: 'трип-хоп 90-х', fullRu: 'бристольский трип-хоп и даунтемпо', shortEn: '90s trip-hop', fullEn: 'Bristol trip-hop and downtempo' },
    { shortRu: 'неоклассика', fullRu: 'современная камерная неоклассика', shortEn: 'neoclassical', fullEn: 'modern chamber neoclassical' },
    { shortRu: 'синтвейв 80-х', fullRu: 'аналоговый синтвейв и электроника 80-х', shortEn: '80s synthwave', fullEn: '1980s analog synthwave' },
    { shortRu: 'блюз-рок', fullRu: 'аудиофильский блюз-рок', shortEn: 'blues rock', fullEn: 'audiophile blues rock' },
    { shortRu: 'даб-техно', fullRu: 'глубокое даб-техно и минимал', shortEn: 'dub techno', fullEn: 'deep dub techno and minimal' },
    { shortRu: 'джаз-фанк', fullRu: 'грувовый джаз-фанк и соул', shortEn: 'jazz-funk', fullEn: 'groovy spiritual jazz-funk' },
    { shortRu: 'пост-рок', fullRu: 'инструментальный кинематографичный пост-рок', shortEn: 'post-rock', fullEn: 'cinematic instrumental post-rock' },
    { shortRu: 'босса-нова 60-х', fullRu: 'бразильская босса-нова 60-х', shortEn: '60s bossa nova', fullEn: '1960s Brazilian bossa nova' },
    { shortRu: 'дрим-поп и шугейз', fullRu: 'воздушный дрим-поп и шугейз', shortEn: 'dream-pop & shoegaze', fullEn: 'ethereal dream-pop and shoegaze' },
    { shortRu: 'японский сити-поп', fullRu: 'японский сити-поп и буги-фанк 80-х', shortEn: 'Japanese city pop', fullEn: '1980s Japanese city pop and funk' },
    { shortRu: 'дарк-джаз', fullRu: 'медленный кинематографичный дарк-джаз', shortEn: 'dark jazz', fullEn: 'slow cinematic dark jazz' },
    { shortRu: 'инди-фолк', fullRu: 'акустический инди-фолк', shortEn: 'indie folk', fullEn: 'intimate acoustic indie folk' },
    { shortRu: 'берлинский эмбиент', fullRu: 'космическая электроника берлинской школы', shortEn: 'Berlin school synth', fullEn: 'Berlin-school modular electronica' },
    { shortRu: 'симфо-саундтрек', fullRu: 'эпический оркестровый саундтрек', shortEn: 'epic film score', fullEn: 'epic orchestral film score' },
    { shortRu: 'афробит и фьюжн', fullRu: 'полиритмический афробит и джаз-фьюжн', shortEn: 'afrobeat fusion', fullEn: 'polyrhythmic afrobeat and jazz fusion' },
    { shortRu: 'нео-соул', fullRu: 'бархатный нео-соул и R&B', shortEn: 'neo-soul', fullEn: 'velvet audiophile neo-soul' }
  ];

  const AI_DYNAMIC_INSTRUMENTS = [
    { shortRu: 'с саксофоном', fullRu: 'с бархатным тенор-саксофоном и контрабасом', shortEn: 'with tenor sax', fullEn: 'with warm tenor saxophone and upright bass' },
    { shortRu: 'и фетровое пианино', fullRu: 'с мягким фетровым пианино и виолончелью', shortEn: '& felt piano', fullEn: 'with intimate felt piano and cello' },
    { shortRu: 'и живой вокал', fullRu: 'с эталонным женским вокалом близкого микрофона', shortEn: '& reference vocals', fullEn: 'with close-mic reference female vocals' },
    { shortRu: 'и ламповая гитара', fullRu: 'с певучей электрогитарой и органом Hammond', shortEn: '& tube guitar', fullEn: 'with singing tube guitar and Hammond organ' },
    { shortRu: 'и аналоговый Moog', fullRu: 'с глубоким аналоговым синтезатором Moog и арпеджио', shortEn: '& analog Moog', fullEn: 'with deep Moog synthesizers and arpeggios' },
    { shortRu: 'и глубокий суббас', fullRu: 'с упругим суббасом и чёткой атакой барабанов', shortEn: '& deep sub-bass', fullEn: 'with visceral sub-bass and crisp drum transients' },
    { shortRu: 'и Fender Rhodes', fullRu: 'с тёплым электропиано Fender Rhodes и щётками', shortEn: '& Fender Rhodes', fullEn: 'with warm Fender Rhodes and brushed drums' },
    { shortRu: 'и акустическая гитара', fullRu: 'с живым пальцевым перебором акустической гитары', shortEn: '& acoustic guitar', fullEn: 'with fingerstyle acoustic guitar and natural room reverb' },
    { shortRu: 'и камерные струнные', fullRu: 'с живым струнным квартетом и широким залом', shortEn: '& chamber strings', fullEn: 'with live string quartet and concert hall acoustics' },
    { shortRu: 'и слэп-бас', fullRu: 'с фанковым слэп-басом и духовой секцией', shortEn: '& slap bass', fullEn: 'with tight slap bass and brass section' },
    { shortRu: 'и вибрафон', fullRu: 'с мерцающим вибрафоном и мягкой перкуссией', shortEn: '& vibraphone', fullEn: 'with shimmering vibraphone and percussion' },
    { shortRu: 'и баритон-саксофон', fullRu: 'с низким баритон-саксофоном и густым ревербом', shortEn: '& baritone sax', fullEn: 'with smoky baritone sax and lush reverb' }
  ];

  const seenAiPromptKeys = new Set();
  try {
    const savedSeen = JSON.parse(sessionStorage.getItem('amr_seen_ai_prompts_v1') || '[]');
    if (Array.isArray(savedSeen)) {
      savedSeen.forEach(k => seenAiPromptKeys.add(String(k)));
    }
  } catch (_) {}

  function recordSeenAiPromptKey(key) {
    if (!key) return;
    seenAiPromptKeys.add(key.toLowerCase());
    if (seenAiPromptKeys.size > 160) {
      const arr = Array.from(seenAiPromptKeys).slice(-100);
      seenAiPromptKeys.clear();
      arr.forEach(k => seenAiPromptKeys.add(k));
    }
    try {
      sessionStorage.setItem('amr_seen_ai_prompts_v1', JSON.stringify(Array.from(seenAiPromptKeys)));
    } catch (_) {}
  }

  function synthesizeDynamicClientPrompt() {
    for (let attempt = 0; attempt < 50; attempt++) {
      const m = AI_DYNAMIC_MOODS[Math.floor(Math.random() * AI_DYNAMIC_MOODS.length)];
      const g = AI_DYNAMIC_GENRES[Math.floor(Math.random() * AI_DYNAMIC_GENRES.length)];
      const inst = AI_DYNAMIC_INSTRUMENTS[Math.floor(Math.random() * AI_DYNAMIC_INSTRUMENTS.length)];
      const labelRu = `${m.icon} ${m.shortRu} • ${g.shortRu} ${inst.shortRu}`;
      const promptRu = `${m.fullRu}: ${g.fullRu} ${inst.fullRu}`;
      const labelEn = `${m.icon} ${m.shortEn} • ${g.shortEn} ${inst.shortEn}`;
      const promptEn = `${m.fullEn}: ${g.fullEn} ${inst.fullEn}`;
      if (!seenAiPromptKeys.has(promptRu.toLowerCase())) {
        recordSeenAiPromptKey(promptRu);
        return { labelRu, promptRu, labelEn, promptEn };
      }
    }
    const m = AI_DYNAMIC_MOODS[Math.floor(Math.random() * AI_DYNAMIC_MOODS.length)];
    const g = AI_DYNAMIC_GENRES[Math.floor(Math.random() * AI_DYNAMIC_GENRES.length)];
    const inst = AI_DYNAMIC_INSTRUMENTS[Math.floor(Math.random() * AI_DYNAMIC_INSTRUMENTS.length)];
    return {
      labelRu: `${m.icon} ${m.shortRu} • ${g.shortRu} ${inst.shortRu}`,
      promptRu: `${m.fullRu}: ${g.fullRu} ${inst.fullRu}`,
      labelEn: `${m.icon} ${m.shortEn} • ${g.shortEn} ${inst.shortEn}`,
      promptEn: `${m.fullEn}: ${g.fullEn} ${inst.fullEn}`
    };
  }

  function generateFreshAiPromptsBatch(count = 6) {
    const unseenBase = AI_PROMPT_SUGGESTIONS_POOL
      .filter(p => !seenAiPromptKeys.has((p.promptRu || '').toLowerCase()))
      .sort(() => Math.random() - 0.5);

    const batch = [];
    const baseQuota = Math.min(unseenBase.length, Math.max(2, Math.floor(count / 2)));
    for (let i = 0; i < baseQuota; i++) {
      const item = unseenBase[i];
      recordSeenAiPromptKey(item.promptRu);
      batch.push(item);
    }
    while (batch.length < count) {
      batch.push(synthesizeDynamicClientPrompt());
    }
    return batch.sort(() => Math.random() - 0.5);
  }

  let currentAiPromptsBatch = generateFreshAiPromptsBatch(6);

  function rotateAiPromptSuggestions() {
    currentAiPromptsBatch = generateFreshAiPromptsBatch(6);
    renderAiPromptChipsGrid(true);
    send({
      action: 'refresh_ai_prompts',
      params: {
        exclude_prompts: currentAiPromptsBatch.map(p => IS_EN ? p.promptEn : p.promptRu)
      }
    });
  }

  function isPromptPinnedClient(prompt) {
    const clean = String(prompt || '').trim().toLowerCase();
    if (!clean || !Array.isArray(state.pinnedAiPrompts)) return false;
    return state.pinnedAiPrompts.some((p) => {
      const p1 = String(p.prompt || '').trim().toLowerCase();
      const p2 = String(p.prompt_ru || p.promptRu || '').trim().toLowerCase();
      const p3 = String(p.prompt_en || p.promptEn || '').trim().toLowerCase();
      return p1 === clean || p2 === clean || p3 === clean;
    });
  }

  function renderAiPromptChipItemHtml(item, isPinnedSection = false) {
    const prompt = IS_EN ? (item.promptEn || item.prompt_en || item.prompt || '') : (item.promptRu || item.prompt_ru || item.prompt || '');
    const label = IS_EN ? (item.labelEn || item.label_en || item.label || prompt) : (item.labelRu || item.label_ru || item.label || prompt);
    const pinned = isPinnedSection || isPromptPinnedClient(prompt);
    return `<div class="ai-prompt-chip-item ${pinned ? 'is-pinned' : ''}">
      <button type="button" class="ai-prompt-chip" data-ai-prompt="${escapeHtml(prompt)}" data-ai-label="${escapeHtml(label)}">${escapeHtml(label)}</button>
      <button type="button" class="ai-chip-pin-btn ${pinned ? 'active' : ''}" data-pin-prompt="${escapeHtml(prompt)}" data-pin-label="${escapeHtml(label)}" title="${translateTextToEn(pinned ? 'Убрать из избранных вайбов' : 'Закрепить вайб в избранном')}" aria-label="Pin">${pinned ? '★' : '☆'}</button>
    </div>`;
  }

  function renderPinnedAiSectionHtml() {
    if (!Array.isArray(state.pinnedAiPrompts) || state.pinnedAiPrompts.length === 0) {
      return '';
    }
    const itemsHtml = state.pinnedAiPrompts.map((item) => renderAiPromptChipItemHtml(item, true)).join('');
    return `
      <div class="ai-pinned-section">
        <div class="ai-pinned-header">
          <span class="ai-pinned-badge">★ ${translateTextToEn('ИЗБРАННЫЕ ВАЙБЫ')}</span>
        </div>
        <div class="ai-curator-prompts-grid ai-pinned-grid">
          ${itemsHtml}
        </div>
      </div>`;
  }

  function togglePinAiPrompt(prompt, label) {
    const cleanPrompt = String(prompt || '').trim();
    if (!cleanPrompt) return;
    const cleanLabel = String(label || cleanPrompt).trim();
    const currentlyPinned = isPromptPinnedClient(cleanPrompt);
    triggerHaptic('light');

    if (currentlyPinned) {
      const lower = cleanPrompt.toLowerCase();
      state.pinnedAiPrompts = (state.pinnedAiPrompts || []).filter((p) => {
        const p1 = String(p.prompt || '').trim().toLowerCase();
        const p2 = String(p.prompt_ru || p.promptRu || '').trim().toLowerCase();
        const p3 = String(p.prompt_en || p.promptEn || '').trim().toLowerCase();
        return p1 !== lower && p2 !== lower && p3 !== lower;
      });
      showToast(translateTextToEn('Удалено из избранных вайбов'));
    } else {
      const entry = {
        label: cleanLabel,
        prompt: cleanPrompt,
        label_ru: cleanLabel,
        prompt_ru: cleanPrompt,
        label_en: cleanLabel,
        prompt_en: cleanPrompt
      };
      state.pinnedAiPrompts = [entry, ...(state.pinnedAiPrompts || [])];
      showToast(translateTextToEn('★ Вайб закреплён в избранном'));
    }

    send({
      action: 'toggle_ai_pin_prompt',
      params: {
        prompt: cleanPrompt,
        label: cleanLabel,
        label_ru: cleanLabel,
        prompt_ru: cleanPrompt,
        label_en: cleanLabel,
        prompt_en: cleanPrompt
      }
    });

    syncPinnedAiPromptsUI();
  }

  function syncPinnedAiPromptsUI() {
    const pinnedContainer = document.getElementById('ai-pinned-prompts-container');
    if (pinnedContainer) {
      pinnedContainer.innerHTML = renderPinnedAiSectionHtml();
    }
    const mainGrid = document.getElementById('ai-main-prompts-grid');
    if (mainGrid) {
      mainGrid.innerHTML = currentAiPromptsBatch.map((item) => renderAiPromptChipItemHtml(item, false)).join('');
    }
    if (pinnedContainer || mainGrid) {
      bindAiPromptChips();
    }

    const heroPinBtn = document.getElementById('btn-ai-curated-pin');
    const heroPinText = document.getElementById('btn-ai-curated-pin-text');
    if (heroPinBtn) {
      const pPrompt = heroPinBtn.getAttribute('data-pin-prompt') || state.activeAiCuratedPrompt || '';
      const isPin = isPromptPinnedClient(pPrompt);
      heroPinBtn.classList.toggle('active', isPin);
      if (heroPinText) {
        heroPinText.textContent = translateTextToEn(isPin ? '★ В избранном' : '☆ Закрепить вайб');
      }
    }

    document.querySelectorAll('#standby-ai-tag-cloud .standby-ai-tag-pill').forEach((pill) => {
      const pPrompt = pill.getAttribute('data-ai-prompt') || '';
      const isPin = isPromptPinnedClient(pPrompt);
      pill.classList.toggle('is-pinned', isPin);
      const badge = pill.querySelector('.standby-tag-pin-badge');
      if (badge) {
        badge.textContent = isPin ? '★' : '☆';
        badge.classList.toggle('active', isPin);
      }
    });
  }

  function renderAiPromptChipsGrid(animateBtn = false) {
    const grid = document.getElementById('ai-main-prompts-grid') || document.querySelector('.ai-curator-prompts-grid');
    if (!grid) return;
    grid.innerHTML = currentAiPromptsBatch.map((item) => renderAiPromptChipItemHtml(item, false)).join('');
    const pinnedContainer = document.getElementById('ai-pinned-prompts-container');
    if (pinnedContainer) {
      pinnedContainer.innerHTML = renderPinnedAiSectionHtml();
    }
    bindAiPromptChips();

    if (animateBtn) {
      const refreshBtn = document.getElementById('btn-refresh-ai-prompts');
      if (refreshBtn) {
        refreshBtn.classList.remove('spinning');
        void refreshBtn.offsetWidth;
        refreshBtn.classList.add('spinning');
        setTimeout(() => refreshBtn.classList.remove('spinning'), 460);
      }
    }
  }

  function syncAiCuratorEnabledUI() {
    const aiFilterChip = document.querySelector('.filter-chip-ai');
    if (aiFilterChip) {
      aiFilterChip.classList.toggle('hidden', !state.aiCuratorEnabled);
    }
    const bridgeFilterChip = document.querySelector('.filter-chip-bridge');
    if (bridgeFilterChip) {
      bridgeFilterChip.classList.toggle('hidden', !state.aiCuratorEnabled);
    }
    const standbyAiBtn = document.getElementById('standby-btn-ai-curator');
    if (standbyAiBtn) {
      standbyAiBtn.classList.toggle('hidden', !state.aiCuratorEnabled);
    }
    const standbyAiVibeBtn = document.getElementById('standby-btn-ai-track-vibe');
    if (standbyAiVibeBtn) {
      standbyAiVibeBtn.classList.toggle('hidden', !state.aiCuratorEnabled);
    }
    if (dom.btnAiTrackVibe) {
      dom.btnAiTrackVibe.classList.toggle('hidden', !state.aiCuratorEnabled);
    }
    if (dom.btnAiMixByTrack) {
      dom.btnAiMixByTrack.classList.toggle('hidden', !state.aiCuratorEnabled);
    }
    if (dom.btnSonicBridgeByTrack) {
      dom.btnSonicBridgeByTrack.classList.toggle('hidden', !state.aiCuratorEnabled);
    }
    if (!state.aiCuratorEnabled) {
      const standbyAiModal = document.getElementById('standby-ai-modal');
      if (standbyAiModal && !standbyAiModal.classList.contains('hidden')) {
        standbyAiModal.classList.add('hidden');
        standbyAiModal.setAttribute('aria-hidden', 'true');
      }
    }
    if (!state.aiCuratorEnabled && (state.searchScope === 'ai' || state.searchScope === 'bridge')) {
      state.searchScope = 'all';
      dom.filterChips.forEach(c => c.classList.toggle('active', c.dataset.scope === 'all'));
      if (dom.searchInput) {
        dom.searchInput.placeholder = translateTextToEn('Поиск в Apple Music...');
      }
    }
    if (!state.searchQuery) {
      renderSearchPlaceholder();
    }
  }

  function handleAiCuratorSettings(data) {
    if (!data || typeof data !== 'object') return;
    if (data.is_apple_silicon !== undefined) {
      state.isAppleSilicon = Boolean(data.is_apple_silicon);
    }
    if (Array.isArray(data.pinned)) {
      state.pinnedAiPrompts = data.pinned;
      syncPinnedAiPromptsUI();
    }
    if (data.is_enabled !== undefined || data.isEnabled !== undefined) {
      const nextEnabled = (state.isAppleSilicon === false)
        ? false
        : Boolean(data.is_enabled !== undefined ? data.is_enabled : data.isEnabled);
      if (state.aiCuratorEnabled !== nextEnabled) {
        state.aiCuratorEnabled = nextEnabled;
        syncAiCuratorEnabledUI();
        if (dom.playerArtwork && dom.playerArtwork.complete && currentLoadedArtworkUrl && currentLoadedArtworkUrl !== 'apple-touch-icon.svg') {
          AmbientBackgroundManager.currentPaletteKey = '';
          AmbientBackgroundManager.updateFromImage(dom.playerArtwork, currentLoadedArtworkUrl);
        }
      }
    }
  }

  const SONIC_BRIDGE_EXAMPLES = [
    {
      labelRu: '🎷 Miles Davis → 🤖 Daft Punk',
      labelEn: '🎷 Miles Davis → 🤖 Daft Punk',
      from: 'Miles Davis — Blue in Green',
      to: 'Daft Punk — Veridis Quo'
    },
    {
      labelRu: '🎸 Pink Floyd → 🎹 Nils Frahm',
      labelEn: '🎸 Pink Floyd → 🎹 Nils Frahm',
      from: 'Pink Floyd — Shine On You Crazy Diamond',
      to: 'Nils Frahm — Says'
    },
    {
      labelRu: '🎻 Hans Zimmer → 🌌 Massive Attack',
      labelEn: '🎻 Hans Zimmer → 🌌 Massive Attack',
      from: 'Hans Zimmer — Time',
      to: 'Massive Attack — Teardrop'
    },
    {
      labelRu: '🌙 Sade → 🎛 Radiohead',
      labelEn: '🌙 Sade → 🎛 Radiohead',
      from: 'Sade — No Ordinary Love',
      to: 'Radiohead — Everything In Its Right Place'
    }
  ];

  function buildSonicBridgeCardElement(compact = false) {
    const card = document.createElement('div');
    card.className = `sonic-bridge-builder-card${compact ? ' compact' : ''}`;
    const hasCurrentTrack = Boolean(state.track && state.track.name);
    const steps = Number(state.sonicBridgeSteps) || 12;
    const examplesHtml = compact ? '' : `
      <div class="sonic-bridge-examples">
        ${SONIC_BRIDGE_EXAMPLES.map((ex, i) => `
          <button type="button" class="sonic-bridge-example-chip" data-bridge-idx="${i}">
            ${escapeHtml(IS_EN ? ex.labelEn : ex.labelRu)}
          </button>
        `).join('')}
      </div>
    `;

    card.innerHTML = `
      <div class="sonic-bridge-top">
        <span class="sonic-bridge-pill">🌉 SONIC BRIDGE • 512-D SLERP GEODESIC</span>
      </div>
      ${compact ? '' : `
        <h3 class="sonic-bridge-title">${IS_EN ? 'Sonic Bridge: Smooth Musical Trajectory' : 'Sonic Bridge: плавный ИИ-маршрут между треками'}</h3>
        <p class="sonic-bridge-desc">${IS_EN
          ? 'Specify Point A and Point B (track, artist, or mood). Apple Neural Engine computes a smooth 512-D geodesic SLERP path across tempo, timbre, and atmosphere.'
          : 'Укажите Точку А и Точку Б (трек, артиста или настроение) — Apple Neural Engine построит бесшовную 512-мерную геодезическую траекторию по тембру, темпу и атмосфере.'}</p>
      `}
      <div class="sonic-bridge-endpoints-row">
        <div class="sonic-bridge-endpoint-box">
          <div class="sonic-bridge-endpoint-head">
            <span class="sonic-bridge-endpoint-label">${translateTextToEn('Точка А (откуда)')}</span>
            <button type="button" class="sonic-bridge-use-current-btn" id="btn-bridge-use-current" ${hasCurrentTrack ? '' : 'disabled'}>
              ${translateTextToEn('🎵 Текущий трек')}
            </button>
          </div>
          <input type="text" id="sonic-bridge-from-input" class="sonic-bridge-input"
            value="${escapeHtml(state.sonicBridgeFrom || '')}"
            placeholder="${IS_EN ? 'e.g. Miles Davis — Blue in Green' : 'Напр.: Miles Davis — Blue in Green'}"
            autocomplete="off" autocorrect="off" spellcheck="false">
        </div>

        <button type="button" id="btn-sonic-bridge-swap" class="sonic-bridge-swap-btn" title="${IS_EN ? 'Swap Point A and Point B' : 'Поменять местами А и Б'}">⇄</button>

        <div class="sonic-bridge-endpoint-box">
          <div class="sonic-bridge-endpoint-head">
            <span class="sonic-bridge-endpoint-label">${translateTextToEn('Точка Б (куда)')}</span>
          </div>
          <input type="text" id="sonic-bridge-to-input" class="sonic-bridge-input"
            value="${escapeHtml(state.sonicBridgeTo || '')}"
            placeholder="${IS_EN ? 'e.g. Daft Punk — Veridis Quo' : 'Напр.: Daft Punk — Veridis Quo'}"
            autocomplete="off" autocorrect="off" spellcheck="false">
        </div>
      </div>

      <div class="sonic-bridge-controls-bar">
        <div class="sonic-bridge-steps-wrap">
          <span class="sonic-bridge-steps-label">${translateTextToEn('Длина маршрута:')}</span>
          ${[10, 12, 16].map((n) => `
            <button type="button" class="sonic-bridge-step-pill ${steps === n ? 'active' : ''}" data-step-count="${n}">${n}</button>
          `).join('')}
        </div>
        <div class="sonic-bridge-submit-actions">
          <button type="button" id="btn-sonic-bridge-build" class="btn-sonic-bridge-build">
            <span>🌉 ${translateTextToEn('Построить маршрут')}</span>
          </button>
          <button type="button" id="btn-sonic-bridge-autoplay" class="btn-sonic-bridge-autoplay">
            <span>▶ ${translateTextToEn('Сразу включить')}</span>
          </button>
        </div>
      </div>
      ${examplesHtml}
    `;

    const fromInput = card.querySelector('#sonic-bridge-from-input');
    const toInput = card.querySelector('#sonic-bridge-to-input');
    const useCurrBtn = card.querySelector('#btn-bridge-use-current');
    const swapBtn = card.querySelector('#btn-sonic-bridge-swap');
    const buildBtn = card.querySelector('#btn-sonic-bridge-build');
    const autoPlayBtn = card.querySelector('#btn-sonic-bridge-autoplay');

    if (fromInput) {
      fromInput.addEventListener('input', () => { state.sonicBridgeFrom = fromInput.value; });
      fromInput.addEventListener('keydown', (ev) => {
        if (ev.key === 'Enter') {
          ev.preventDefault();
          if (toInput && !toInput.value.trim()) {
            toInput.focus();
          } else {
            triggerSonicBridgeSearch(false);
          }
        }
      });
    }
    if (toInput) {
      toInput.addEventListener('input', () => { state.sonicBridgeTo = toInput.value; });
      toInput.addEventListener('keydown', (ev) => {
        if (ev.key === 'Enter') {
          ev.preventDefault();
          triggerSonicBridgeSearch(false);
        }
      });
    }
    if (useCurrBtn) {
      useCurrBtn.addEventListener('click', () => {
        if (!state.track || !state.track.name) return;
        triggerHaptic('light');
        const cur = state.track.artist ? `${state.track.artist} — ${state.track.name}` : state.track.name;
        state.sonicBridgeFrom = cur;
        if (fromInput) fromInput.value = cur;
        if (toInput && !toInput.value.trim()) toInput.focus();
      });
    }
    if (swapBtn) {
      swapBtn.addEventListener('click', () => {
        triggerHaptic('light');
        const a = fromInput ? fromInput.value : state.sonicBridgeFrom;
        const b = toInput ? toInput.value : state.sonicBridgeTo;
        state.sonicBridgeFrom = b;
        state.sonicBridgeTo = a;
        if (fromInput) fromInput.value = b;
        if (toInput) toInput.value = a;
      });
    }
    card.querySelectorAll('.sonic-bridge-step-pill').forEach((pill) => {
      pill.addEventListener('click', () => {
        triggerHaptic('light');
        const n = Number(pill.getAttribute('data-step-count')) || 12;
        state.sonicBridgeSteps = n;
        card.querySelectorAll('.sonic-bridge-step-pill').forEach(p => p.classList.toggle('active', Number(p.getAttribute('data-step-count')) === n));
      });
    });
    card.querySelectorAll('.sonic-bridge-example-chip').forEach((chip) => {
      chip.addEventListener('click', () => {
        const idx = Number(chip.getAttribute('data-bridge-idx'));
        const ex = SONIC_BRIDGE_EXAMPLES[idx];
        if (!ex) return;
        triggerHaptic('light');
        state.sonicBridgeFrom = ex.from;
        state.sonicBridgeTo = ex.to;
        if (fromInput) fromInput.value = ex.from;
        if (toInput) toInput.value = ex.to;
        triggerSonicBridgeSearch(false);
      });
    });
    if (buildBtn) {
      buildBtn.addEventListener('click', () => triggerSonicBridgeSearch(false));
    }
    if (autoPlayBtn) {
      autoPlayBtn.addEventListener('click', () => triggerSonicBridgeSearch(true));
    }
    return card;
  }
