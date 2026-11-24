  function renderSonicBridgeBuilder() {
    if (!dom.searchResults) return;
    dom.searchResults.innerHTML = '';
    const wrap = document.createElement('div');
    wrap.className = 'search-placeholder';
    wrap.appendChild(buildSonicBridgeCardElement(false));
    dom.searchResults.appendChild(wrap);
  }

  function openSonicBridgeTab(focusDestination = false) {
    if (!state.aiCuratorEnabled) return;
    if (!isDesktopLayout()) {
      switchMobileView('view-search', true);
    } else {
      switchDesktopTab('search', true, { fromResize: true });
    }
    state.searchScope = 'bridge';
    dom.filterChips.forEach(c => c.classList.toggle('active', c.dataset.scope === 'bridge'));
    if (dom.searchInput) {
      dom.searchInput.placeholder = IS_EN
        ? 'Point A -> Point B (or fill route below)...'
        : 'Точка А -> Точка Б (или заполните маршрут ниже)...';
    }
    renderSonicBridgeBuilder();
    setTimeout(() => {
      const targetId = (focusDestination || state.sonicBridgeFrom) ? 'sonic-bridge-to-input' : 'sonic-bridge-from-input';
      const el = document.getElementById(targetId);
      if (el) el.focus();
    }, 60);
  }

  function triggerSonicBridgeSearch(autoPlay = false) {
    const fromEl = document.getElementById('sonic-bridge-from-input');
    const toEl = document.getElementById('sonic-bridge-to-input');
    const fromQ = String((fromEl ? fromEl.value : state.sonicBridgeFrom) || '').trim();
    const toQ = String((toEl ? toEl.value : state.sonicBridgeTo) || '').trim();
    state.sonicBridgeFrom = fromQ;
    state.sonicBridgeTo = toQ;

    if (!fromQ || !toQ) {
      showToast(IS_EN
        ? 'Specify both Point A and Point B for Sonic Bridge'
        : 'Укажите обе точки маршрута (Точку А и Точку Б)');
      if (!fromQ && fromEl) fromEl.focus();
      else if (!toQ && toEl) toEl.focus();
      return;
    }

    triggerHaptic('medium');
    currentSearchSongs = [];
    currentSearchOffset = 0;
    currentSearchHasMore = false;
    state.isAiCurating = true;
    state.sonicBridgeAutoPlay = Boolean(autoPlay);
    state.aiCurateReqSeq = (state.aiCurateReqSeq || 0) + 1;
    state.lastAiCurateSentAt = Date.now();
    const reqId = state.aiCurateReqSeq;

    if (dom.searchResults) {
      dom.searchResults.innerHTML = '';
      dom.searchResults.appendChild(buildSonicBridgeCardElement(true));
      const loadingEl = document.createElement('div');
      loadingEl.className = 'loading-state';
      loadingEl.textContent = IS_EN
        ? `🌉 Computing 512-D Sonic Bridge: ${fromQ} → ${toQ}...`
        : `🌉 Расчёт 512-D маршрута Sonic Bridge: ${fromQ} → ${toQ}...`;
      dom.searchResults.appendChild(loadingEl);
    }

    const sent = send({
      action: 'build_sonic_bridge',
      request_id: reqId,
      params: {
        from: fromQ,
        to: toQ,
        steps: Number(state.sonicBridgeSteps) || 12,
        country: getActiveStorefront(),
        auto_play: Boolean(autoPlay),
        request_id: reqId
      }
    });
    if (!sent) {
      state.isAiCurating = false;
      state.sonicBridgeAutoPlay = false;
      setUIBusy(false);
      if (dom.searchResults) {
        const loadingEl = dom.searchResults.querySelector('.loading-state');
        if (loadingEl) loadingEl.remove();
        const emptyEl = document.createElement('div');
        emptyEl.className = 'empty-state';
        emptyEl.textContent = IS_EN ? 'No connection to Mac server' : 'Нет соединения с сервером Mac';
        dom.searchResults.appendChild(emptyEl);
      }
      showToast(IS_EN ? 'No connection to Mac server' : 'Нет соединения с сервером Mac');
    }
  }

  function renderSearchPlaceholder() {
    if (!dom.searchResults) return;
    if (!state.aiCuratorEnabled) {
      dom.searchResults.innerHTML = `
        <div class="search-placeholder">
          <div class="search-placeholder-minimal">${translateTextToEn('Введите название песни, альбома, плейлиста или артиста')}</div>
        </div>`;
      return;
    }

    if (state.searchScope === 'bridge') {
      renderSonicBridgeBuilder();
      return;
    }

    const chipsHtml = currentAiPromptsBatch.map((item) => renderAiPromptChipItemHtml(item, false)).join('');

    dom.searchResults.innerHTML = `
      <div class="search-placeholder">
        <div class="ai-curator-landing-card">
          <div class="ai-curator-landing-top">
            <span class="ai-curator-engine-pill">✨ APPLE NEURAL ENGINE • ON-DEVICE AI</span>
            <button type="button" id="btn-refresh-ai-prompts" class="ai-refresh-prompts-btn" title="${translateTextToEn('Сгенерировать другие варианты промптов')}">
              <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
                <polyline points="23 4 23 10 17 10"/>
                <polyline points="1 20 1 14 7 14"/>
                <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/>
              </svg>
              <span>${translateTextToEn('Другие варианты')}</span>
            </button>
          </div>
          <h3 class="ai-curator-landing-title">${translateTextToEn('Умный семантический поиск и Промпт-Куратор')}</h3>
          <p class="ai-curator-landing-desc">${translateTextToEn('Опишите настроение, звуковую сцену, эпоху или инструменты свободным текстом — нативный движок macOS соберёт готовую аудиофильскую очередь из каталога Apple Music.')}</p>
          <div id="ai-pinned-prompts-container">${renderPinnedAiSectionHtml()}</div>
          <div id="ai-main-prompts-grid" class="ai-curator-prompts-grid">
            ${chipsHtml}
          </div>
          <button type="button" id="btn-open-sonic-bridge-cta" class="ai-landing-bridge-cta">
            <div class="ai-landing-bridge-cta-texts">
              <span class="ai-landing-bridge-cta-title">🌉 ${IS_EN ? 'Sonic Bridge: Musical Route A → B' : 'Sonic Bridge: плавный ИИ-маршрут А → Б'}</span>
              <span class="ai-landing-bridge-cta-sub">${IS_EN
                ? 'Build a seamless geodesic transition between any two tracks or artists'
                : 'Бесшовный переход от одного трека или артиста к другому в 512-D пространстве'}</span>
            </div>
            <span class="ai-landing-bridge-cta-arrow">→</span>
          </button>
        </div>
      </div>`;
    bindAiPromptChips();
    const bridgeCta = document.getElementById('btn-open-sonic-bridge-cta');
    if (bridgeCta) {
      bridgeCta.addEventListener('click', () => {
        triggerHaptic('light');
        openSonicBridgeTab(false);
      });
    }
  }

  function bindAiPromptChips() {
    document.querySelectorAll('.ai-prompt-chip').forEach((btn) => {
      if (btn.dataset.boundAiChip === '1') return;
      btn.dataset.boundAiChip = '1';
      btn.addEventListener('click', () => {
        const prompt = btn.getAttribute('data-ai-prompt') || '';
        if (!prompt) return;
        dom.filterChips.forEach(c => c.classList.toggle('active', c.dataset.scope === 'ai'));
        state.searchScope = 'ai';
        dom.searchInput.value = prompt;
        dom.searchInput.placeholder = translateTextToEn('Опишите настроение, сцену или инструменты...');
        dom.btnClearSearch.classList.remove('hidden');
        state.searchQuery = prompt;
        executeSearch(prompt, 'ai');
      });
    });

    document.querySelectorAll('.ai-chip-pin-btn').forEach((pinBtn) => {
      if (pinBtn.dataset.boundAiPin === '1') return;
      pinBtn.dataset.boundAiPin = '1';
      pinBtn.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        const pPrompt = pinBtn.getAttribute('data-pin-prompt') || '';
        const pLabel = pinBtn.getAttribute('data-pin-label') || pPrompt;
        togglePinAiPrompt(pPrompt, pLabel);
      });
    });

    const refreshBtn = document.getElementById('btn-refresh-ai-prompts');
    if (refreshBtn && refreshBtn.dataset.boundRefresh !== '1') {
      refreshBtn.dataset.boundRefresh = '1';
      refreshBtn.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        triggerHaptic('light');
        rotateAiPromptSuggestions();
      });
    }
  }

  // Render fresh randomized AI prompt suggestions immediately on startup
  renderSearchPlaceholder();

  dom.btnClearSearch.addEventListener('click', () => {
    dom.searchInput.value = '';
    dom.btnClearSearch.classList.add('hidden');
    state.searchQuery = '';
    renderSearchPlaceholder();
  });

  dom.filterChips.forEach(chip => {
    chip.addEventListener('click', () => {
      dom.filterChips.forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      state.searchScope = chip.dataset.scope;
      if (dom.searchInput) {
        if (state.searchScope === 'bridge') {
          dom.searchInput.placeholder = IS_EN
            ? 'Point A -> Point B (or fill route below)...'
            : 'Точка А -> Точка Б (или заполните маршрут ниже)...';
        } else {
          dom.searchInput.placeholder = translateTextToEn(
            state.searchScope === 'ai'
              ? 'Опишите настроение, сцену или инструменты...'
              : 'Поиск в Apple Music...'
          );
        }
      }
      if (state.searchScope === 'bridge') {
        renderSonicBridgeBuilder();
        return;
      }
      if (state.searchQuery) {
        executeSearch(state.searchQuery, state.searchScope);
      } else {
        renderSearchPlaceholder();
      }
    });
  });

  let currentSearchSongs = [];
  let currentSearchOffset = 0;
  let currentSearchHasMore = false;
  let isSearchLoadingMore = false;

  function executeSearch(query, scope, offset = 0) {
    if (scope === 'bridge') {
      const arrowParts = String(query || '').split(/\s*(?:->|→|—>)\s*/);
      if (arrowParts.length >= 2 && arrowParts[0].trim() && arrowParts[1].trim()) {
        state.sonicBridgeFrom = arrowParts[0].trim();
        state.sonicBridgeTo = arrowParts.slice(1).join(' ').trim();
        triggerSonicBridgeSearch(false);
      } else {
        renderSonicBridgeBuilder();
      }
      return;
    }
    if (scope === 'ai') {
      currentSearchSongs = [];
      currentSearchOffset = 0;
      currentSearchHasMore = false;
      state.isAiCurating = true;
      state.aiCurateReqSeq = (state.aiCurateReqSeq || 0) + 1;
      state.lastAiCurateSentAt = Date.now();
      const reqId = state.aiCurateReqSeq;
      dom.searchResults.innerHTML = `<div class="loading-state">${translateTextToEn('Подбор нативным ИИ (Apple Neural Engine)...')}</div>`;
      const sent = send({
        action: 'ai_curate',
        request_id: reqId,
        params: {
          prompt: query,
          country: getActiveStorefront(),
          request_id: reqId
        }
      });
      if (!sent) {
        state.isAiCurating = false;
        setUIBusy(false);
        if (dom.searchResults) {
          dom.searchResults.innerHTML = `<div class="empty-state">${escapeHtml(IS_EN ? 'No connection to Mac server' : 'Нет соединения с сервером Mac')}</div>`;
        }
        showToast(IS_EN ? 'No connection to Mac server' : 'Нет соединения с сервером Mac');
      }
      return;
    }

    if (offset === 0) {
      if (state.aiCurateTimeoutId) {
        clearTimeout(state.aiCurateTimeoutId);
        state.aiCurateTimeoutId = null;
      }
      state.isAiCurating = false;
      state.aiCurateReqSeq = (state.aiCurateReqSeq || 0) + 1;
      currentSearchSongs = [];
      currentSearchOffset = 0;
      currentSearchHasMore = false;
      dom.searchResults.innerHTML = '<div class="loading-state">Поиск в каталоге Apple Music...</div>';
    } else {
      isSearchLoadingMore = true;
      const btn = document.getElementById('btn-search-load-more');
      if (btn) {
        btn.disabled = true;
        btn.textContent = 'Загрузка...';
      }
    }
    state.searchReqSeq = (state.searchReqSeq || 0) + 1;
    const searchReqId = state.searchReqSeq;
    send({
      action: 'search',
      request_id: searchReqId,
      params: {
        query: query,
        country: getActiveStorefront(),
        locale: state.userLocale || undefined,
        scope: scope,
        limit: 25,
        offset: offset,
        request_id: searchReqId
      }
    });
  }

  function createTrackRow(s) {
    const row = document.createElement('div');
    row.className = 'track-row';
    const artSrc = appendDeviceIdToUrl(s.artwork_url || s.artwork || getArtworkSrc(s) || 'apple-touch-icon.svg');
    const isLocal = Boolean(s.is_local || s.isLocal);
    const localBadge = isLocal ? '<span class="badge-library">МЕДИАТЕКА</span>' : '';

    row.innerHTML = `
      <img class="track-thumb" src="${escapeHtml(artSrc)}" alt="" loading="lazy" data-fallback-icon="apple-touch-icon.svg">
      <div class="track-details">
        <div class="track-row-title-wrap">
          <span class="track-row-title">${escapeHtml(s.name || s.trackName || '')}</span>
          ${localBadge}
        </div>
        <span class="track-row-artist">${escapeHtml(s.artist || s.artistName || '')}</span>
      </div>
    `;

    row.appendChild(createTrackRowActionButtons({
      ...s,
      name: s.name || s.trackName || '',
      artist: s.artist || s.artistName || '',
      album: s.album || s.collectionName || '',
      artwork: s.artwork_url || s.artwork || '',
      is_local: isLocal
    }, { showDirectDelete: isLocal }));

    row.addEventListener('click', () => {
      setUIBusy(true, 'Запуск трека...');
      if (currentSearchSongs && currentSearchSongs.length > 0) {
        const sId = `${s.id || s.trackId || ''}`;
        const idx = currentSearchSongs.findIndex(x => (sId && `${x.id || x.trackId || ''}` === sId) || ((x.name || x.trackName) === (s.name || s.trackName) && (x.artist || x.artistName) === (s.artist || s.artistName)));
        if (idx !== -1) {
          playSearchResultsList(currentSearchSongs, false, idx);
          return;
        }
      }
      send({
        action: 'play_cloud',
        params: {
          numeric_id: s.numeric_id || s.numericId || undefined,
          id: `${s.id || s.trackId || ''}`,
          name: s.name || s.trackName || '',
          artist: s.artist || s.artistName || '',
          url: s.url || s.trackViewUrl || '',
          artwork: s.artwork_url || s.artwork || ''
        }
      });
    });
    return row;
  }

  function createSonicBridgeTrackRow(s, stepIdx, totalSteps) {
    const row = document.createElement('div');
    row.className = 'track-row sonic-bridge-track-row';
    const artSrc = appendDeviceIdToUrl(s.artwork_url || s.artwork || getArtworkSrc(s) || 'apple-touch-icon.svg');
    const isLocal = Boolean(s.is_local || s.isLocal);
    const localBadge = isLocal ? '<span class="badge-library">МЕДИАТЕКА</span>' : '';
    const pct = s.bridge_progress !== undefined
      ? Number(s.bridge_progress)
      : (totalSteps > 1 ? Math.round((stepIdx / (totalSteps - 1)) * 100) : 0);
    let stageLabel = `${pct}%`;
    if (stepIdx === 0) {
      stageLabel = IS_EN ? '0% • Origin A' : '0% • Точка А';
    } else if (stepIdx === totalSteps - 1) {
      stageLabel = IS_EN ? '100% • Dest B' : '100% • Точка Б';
    } else if (Math.abs(pct - 50) <= 7) {
      stageLabel = IS_EN ? `${pct}% • Midpoint` : `${pct}% • Экватор`;
    }

    row.innerHTML = `
      <span class="sonic-bridge-step-num">${stepIdx + 1}</span>
      <img class="track-thumb" src="${escapeHtml(artSrc)}" alt="" loading="lazy" data-fallback-icon="apple-touch-icon.svg">
      <div class="track-details">
        <div class="track-row-title-wrap">
          <span class="track-row-title">${escapeHtml(s.name || s.trackName || '')}</span>
          ${localBadge}
        </div>
        <span class="track-row-artist">${escapeHtml(s.artist || s.artistName || '')}</span>
      </div>
      <span class="bridge-progress-pill">${escapeHtml(stageLabel)}</span>
    `;

    row.addEventListener('click', () => {
      setUIBusy(true, IS_EN ? 'Starting Sonic Bridge...' : 'Запуск маршрута Sonic Bridge...');
      if (currentSearchSongs && currentSearchSongs.length > 0) {
        playSearchResultsList(currentSearchSongs, false, stepIdx, {
          queueName: state.activeAiCuratedTitle || '🌉 Sonic Bridge'
        });
        return;
      }
      send({
        action: 'play_cloud',
        params: {
          numeric_id: s.numeric_id || s.numericId || undefined,
          id: `${s.id || s.trackId || ''}`,
          name: s.name || s.trackName || '',
          artist: s.artist || s.artistName || '',
          url: s.url || s.trackViewUrl || '',
          artwork: s.artwork_url || s.artwork || ''
        }
      });
    });
    return row;
  }

  function updateSonicBridgeResults(data) {
    const respReqId = data && data.request_id;
    if (respReqId !== undefined && respReqId !== null && state.aiCurateReqSeq && Number(respReqId) !== Number(state.aiCurateReqSeq)) {
      return;
    }
    if (state.aiCurateTimeoutId) {
      clearTimeout(state.aiCurateTimeoutId);
      state.aiCurateTimeoutId = null;
    }
    state.isAiCurating = false;
    setUIBusy(false);

    if (!data || typeof data !== 'object' || data.status === 'disabled' || data.status === 'error' || data.error) {
      state.sonicBridgeAutoPlay = false;
      const infoMsg = translateTextToEn(String(
        (data && (data.message || data.error)) ||
        (data && data.status === 'disabled'
          ? 'Нативные функции ИИ отключены в настройках Mac'
          : 'Не удалось построить маршрут Sonic Bridge')
      ));
      showToast(infoMsg);
      if (dom.searchResults) {
        dom.searchResults.innerHTML = '';
        if (state.searchScope === 'bridge') {
          dom.searchResults.appendChild(buildSonicBridgeCardElement(true));
        }
        const emptyEl = document.createElement('div');
        emptyEl.className = 'empty-state';
        emptyEl.textContent = infoMsg;
        dom.searchResults.appendChild(emptyEl);
      }
      return;
    }

    const songs = Array.isArray(data.songs) ? data.songs : [];
    const title = data.title || `${state.sonicBridgeFrom} → ${state.sonicBridgeTo}`;
    const subtitle = data.subtitle || '';
    const engine = data.engine || 'Sonic Bridge • 512-D Geodesic SLERP';
    const tags = Array.isArray(data.tags) ? data.tags : [];
    const shouldAutoPlay = Boolean(data.auto_play || state.sonicBridgeAutoPlay);
    state.sonicBridgeAutoPlay = false;

    if (data.from) state.sonicBridgeFrom = String(data.from);
    if (data.to) state.sonicBridgeTo = String(data.to);
    state.activeAiCuratedTitle = title.startsWith('🌉') ? title : `🌉 ${title}`;

    if (shouldAutoPlay && songs.length > 0) {
      showToast(state.activeAiCuratedTitle);
      playSearchResultsList([...songs], false, 0, {
        queueName: state.activeAiCuratedTitle,
        query: ''
      });
    } else if (songs.length === 0) {
      showToast(IS_EN ? 'No bridge tracks found in catalog' : 'Не удалось найти треки для маршрута в каталоге');
    }

    currentSearchSongs = [...songs];
    currentSearchOffset = songs.length;
    currentSearchHasMore = false;

    if (!dom.searchResults) return;
    dom.searchResults.innerHTML = '';

    // 1. Compact editable Sonic Bridge Route Builder
    dom.searchResults.appendChild(buildSonicBridgeCardElement(true));

    if (songs.length === 0) {
      const emptyEl = document.createElement('div');
      emptyEl.className = 'empty-state';
      emptyEl.textContent = IS_EN ? 'No tracks found for this route' : 'Треки для маршрута не найдены';
      dom.searchResults.appendChild(emptyEl);
      return;
    }

    // 2. Hero Summary Card
    const heroCard = document.createElement('div');
    heroCard.className = 'ai-curated-session-card';
    const tagsHtml = tags.map(t => `<span class="ai-curated-tag">${escapeHtml(String(t))}</span>`).join('');
    heroCard.innerHTML = `
      <div class="ai-curated-header-top">
        <span class="ai-curator-engine-pill">🌉 ${escapeHtml(engine)}</span>
      </div>
      <h3 class="ai-curated-title">${escapeHtml(title)}</h3>
      ${subtitle ? `<p class="ai-curated-subtitle">${escapeHtml(subtitle)}</p>` : ''}
      ${tagsHtml ? `<div class="ai-curated-tags">${tagsHtml}</div>` : ''}
      <div class="ai-curated-actions">
        <button type="button" class="btn-search-action btn-search-play-all" id="btn-sonic-bridge-play-all">
          <svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor">
            <polygon points="6 3 20 12 6 21 6 3"/>
          </svg>
          <span>${translateTextToEn('Запустить маршрут')}</span>
        </button>
        <button type="button" class="btn-search-action" id="btn-ai-curated-save">
          <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.2">
            <line x1="12" y1="5" x2="12" y2="19"/>
            <line x1="5" y1="12" x2="19" y2="12"/>
          </svg>
          <span id="btn-ai-curated-save-text">${translateTextToEn('В плейлисты')}</span>
        </button>
      </div>
    `;
    dom.searchResults.appendChild(heroCard);

    const btnPlayAll = heroCard.querySelector('#btn-sonic-bridge-play-all');
    const btnSave = heroCard.querySelector('#btn-ai-curated-save');
    const btnSaveText = heroCard.querySelector('#btn-ai-curated-save-text');
    dom.btnAiCuratedSave = btnSave;
    dom.btnAiCuratedSaveText = btnSaveText;

    if (btnPlayAll) {
      btnPlayAll.addEventListener('click', () => {
        playSearchResultsList([...songs], false, 0, {
          queueName: state.activeAiCuratedTitle,
          query: ''
        });
      });
    }
    if (btnSave) {
      btnSave.addEventListener('click', () => {
        state.lastLibraryAddTarget = 'ai';
        btnSave.disabled = true;
        if (btnSaveText) btnSaveText.textContent = translateTextToEn('Добавление...');
        send({
          action: 'add_playlist_to_library',
          params: {
            name: state.activeAiCuratedTitle,
            tracks: songs
          }
        });
      });
    }

    // 3. Geodesic Trajectory Track List
    const heading = document.createElement('h3');
    heading.className = 'search-section-title';
    heading.textContent = translateTextToEn('МАРШРУТ ПЕРЕХОДА');
    dom.searchResults.appendChild(heading);

    const list = document.createElement('div');
    list.id = 'search-songs-list';
    list.className = 'track-list';
    songs.forEach((s, idx) => {
      list.appendChild(createSonicBridgeTrackRow(s, idx, songs.length));
    });
    dom.searchResults.appendChild(list);
  }
