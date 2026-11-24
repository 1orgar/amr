  function updateAiCuratedResults(data, type = '') {
    const respReqId = data && data.request_id;
    if (respReqId !== undefined && respReqId !== null && state.aiCurateReqSeq && Number(respReqId) !== Number(state.aiCurateReqSeq)) {
      return;
    }
    if (state.aiCurateTimeoutId) {
      clearTimeout(state.aiCurateTimeoutId);
      state.aiCurateTimeoutId = null;
    }
    state.isAiCurating = false;
    const isSearchViewActive = isDesktopLayout()
      ? (state.desktopActiveTab === 'search')
      : (state.activeView === 'view-search' || state.activeMobileView === 'search');
    if (!data || typeof data !== 'object') {
      state.pendingStandbyAiAutoPlay = false;
      setUIBusy(false);
      if (isSearchViewActive && dom.searchResults) {
        dom.searchResults.innerHTML = '<div class="empty-state">Ничего не найдено</div>';
      }
      return;
    }

    const songs = data.songs || [];
    const albums = data.albums || [];
    const title = data.title || (IS_EN ? 'AI Sonic Selection' : 'AI-Подборка');
    const subtitle = data.subtitle || '';
    const engine = data.engine || 'Apple Neural Engine • NaturalLanguage 512-D';
    const tags = Array.isArray(data.tags) ? data.tags : [];
    const shouldAutoPlay = Boolean(data.auto_play || state.pendingStandbyAiAutoPlay);
    if (!shouldAutoPlay && state.searchScope === 'ai' && data.prompt && state.searchQuery) {
      const respPrompt = String(data.prompt).trim().toLowerCase();
      const currQuery = String(state.searchQuery).trim().toLowerCase();
      if (respPrompt && currQuery && respPrompt !== currQuery) {
        return;
      }
    }
    state.pendingStandbyAiAutoPlay = false;
    const curatorPrompt = String(data.prompt || state.searchQuery || title).trim();
    state.activeAiCuratedTitle = `✨ ${title}`;
    state.activeAiCuratedPrompt = curatorPrompt;

    if (shouldAutoPlay && songs.length > 0) {
      showToast(`✨ ${title}`);
      playSearchResultsList([...songs], false, 0, {
        queueName: `✨ ${title}`,
        query: '',
        curatorPrompt: curatorPrompt
      });
    } else if (shouldAutoPlay && songs.length === 0) {
      setUIBusy(false);
      showToast(IS_EN ? 'No matching tracks found' : 'Не удалось подобрать треки по запросу');
    }

    const hasOpenSearchResults = Boolean(
      dom.searchResults &&
      dom.searchResults.children.length > 0 &&
      !dom.searchResults.querySelector('.search-placeholder')
    );
    if ((shouldAutoPlay || type === 'play_ai_track_vibe' || type === 'ai_curate_from_track') && (!isSearchViewActive || (state.searchScope !== 'ai' && hasOpenSearchResults))) {
      return;
    }

    currentSearchSongs = [...songs];
    currentSearchOffset = songs.length;
    currentSearchHasMore = false;

    dom.searchResults.innerHTML = '';

    // 1. Render AI Curated Session Hero Card
    const heroCard = document.createElement('div');
    heroCard.className = 'ai-curated-session-card';

    const tagsHtml = tags.map(t => `<span class="ai-curated-tag">${escapeHtml(String(t))}</span>`).join('');
    const isHeroPinned = isPromptPinnedClient(curatorPrompt);

    heroCard.innerHTML = `
      <div class="ai-curated-header-top">
        <span class="ai-curator-engine-pill">✨ ${escapeHtml(engine)}</span>
      </div>
      <h3 class="ai-curated-title">${escapeHtml(title)}</h3>
      ${subtitle ? `<p class="ai-curated-subtitle">${escapeHtml(subtitle)}</p>` : ''}
      ${tagsHtml ? `<div class="ai-curated-tags">${tagsHtml}</div>` : ''}
      <div class="ai-curated-actions">
        <button type="button" class="btn-search-action btn-search-play-all" id="btn-ai-curated-play">
          <svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor">
            <polygon points="6 3 20 12 6 21 6 3"/>
          </svg>
          <span>${translateTextToEn('Слушать подборку')}</span>
        </button>
        <button type="button" class="btn-search-action btn-search-shuffle" id="btn-ai-curated-shuffle">
          <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2">
            <polyline points="16 3 21 3 21 8"/>
            <line x1="4" y1="20" x2="21" y2="3"/>
            <polyline points="21 16 21 21 16 21"/>
            <line x1="15" y1="15" x2="21" y2="21"/>
            <line x1="4" y1="4" x2="9" y2="9"/>
          </svg>
          <span>${translateTextToEn('Перемешать')}</span>
        </button>
        <button type="button" class="btn-search-action ${isHeroPinned ? 'active' : ''}" id="btn-ai-curated-pin" data-pin-prompt="${escapeHtml(curatorPrompt)}" data-pin-label="${escapeHtml(title)}">
          <span id="btn-ai-curated-pin-text">${translateTextToEn(isHeroPinned ? '★ В избранном' : '☆ Закрепить вайб')}</span>
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

    const btnPlay = heroCard.querySelector('#btn-ai-curated-play');
    const btnShuffle = heroCard.querySelector('#btn-ai-curated-shuffle');
    const btnPin = heroCard.querySelector('#btn-ai-curated-pin');
    const btnSave = heroCard.querySelector('#btn-ai-curated-save');
    const btnSaveText = heroCard.querySelector('#btn-ai-curated-save-text');
    dom.btnAiCuratedSave = btnSave;
    dom.btnAiCuratedSaveText = btnSaveText;

    if (btnPlay && songs.length > 0) {
      btnPlay.addEventListener('click', () => {
        playSearchResultsList([...songs], false, 0, {
          queueName: `✨ ${title}`,
          query: '',
          curatorPrompt: curatorPrompt
        });
      });
    }
    if (btnShuffle && songs.length > 0) {
      btnShuffle.addEventListener('click', () => {
        playSearchResultsList([...songs], true, null, {
          queueName: `✨ ${title}`,
          query: '',
          curatorPrompt: curatorPrompt
        });
      });
    }
    if (btnPin && curatorPrompt) {
      btnPin.addEventListener('click', () => {
        togglePinAiPrompt(curatorPrompt, `✨ ${title}`);
      });
    }
    if (btnSave && songs.length > 0) {
      btnSave.addEventListener('click', () => {
        state.lastLibraryAddTarget = 'ai';
        btnSave.disabled = true;
        if (btnSaveText) btnSaveText.textContent = translateTextToEn('Добавление...');
        send({
          action: 'add_playlist_to_library',
          params: {
            name: `✨ ${title}`,
            tracks: songs
          }
        });
      });
    }

    // 2. Render Curated Tracks
    if (songs.length > 0) {
      const heading = document.createElement('h3');
      heading.className = 'search-section-title';
      heading.textContent = translateTextToEn('ПЕСНИ ПОДБОРКИ');
      dom.searchResults.appendChild(heading);

      const list = document.createElement('div');
      list.id = 'search-songs-list';
      list.className = 'track-list';
      songs.forEach(s => {
        list.appendChild(createTrackRow(s));
      });
      dom.searchResults.appendChild(list);
    }

    // 3. Render Recommended Albums
    if (albums.length > 0) {
      const heading = document.createElement('h3');
      heading.className = 'search-section-title';
      heading.textContent = translateTextToEn('РЕКОМЕНДОВАННЫЕ АЛЬБОМЫ');
      dom.searchResults.appendChild(heading);

      const grid = document.createElement('div');
      grid.className = 'playlists-grid';
      albums.forEach(alb => {
        const card = document.createElement('div');
        card.className = 'playlist-card';
        const art = alb.artwork_url || alb.artwork || 'apple-touch-icon.svg';

        card.innerHTML = `
          <img class="playlist-card-art" src="${escapeHtml(art)}" alt="" loading="lazy">
          <span class="playlist-card-title">${escapeHtml(alb.name || alb.collectionName || '')}</span>
          <span class="playlist-card-count">${escapeHtml(alb.artist || alb.artistName || '')}</span>
        `;

        card.addEventListener('click', () => {
          openAlbumDetail({
            id: `${alb.id || alb.collectionId || ''}`,
            name: alb.name || alb.collectionName || '',
            artist: alb.artist || alb.artistName || '',
            artwork: art,
            url: alb.url || alb.collectionViewUrl || ''
          }, 'search');
        });

        grid.appendChild(card);
      });
      dom.searchResults.appendChild(grid);
    }
  }

  function updateSearchResults(data) {
    const respReqId = data && data.request_id;
    if (respReqId !== undefined && respReqId !== null && state.searchReqSeq && Number(respReqId) !== Number(state.searchReqSeq)) {
      return;
    }
    if (state.isAiCurating || state.searchScope === 'ai') {
      return;
    }
    if (!data) {
      dom.searchResults.innerHTML = '<div class="empty-state">Ничего не найдено</div>';
      return;
    }

    const songs = data.songs || [];
    const albums = data.albums || [];
    const artists = data.artists || [];
    const playlists = data.playlists || [];
    const offset = data.offset || 0;
    const hasMore = Boolean(data.has_more);

    // If this is a page append (offset > 0)
    if (offset > 0) {
      isSearchLoadingMore = false;
      const songList = document.getElementById('search-songs-list');
      if (songList && songs.length > 0) {
        currentSearchSongs.push(...songs);
        songs.forEach(s => {
          songList.appendChild(createTrackRow(s));
        });
        // Append to active AMR queue if currently playing search results
        const curQPl = String((state.queue && state.queue.playlist) || '');
        const isPlayingSearch = Boolean(
          state.queue &&
          (curQPl === 'Результаты поиска' || curQPl === 'Search Results' || curQPl === 'Очередь AMR' || curQPl.startsWith('Поиск: ') || curQPl.startsWith('Search: '))
        );
        if (isPlayingSearch) {
          const formatted = songs.map(s => ({
            id: `${s.id || s.trackId || ''}`,
            numeric_id: s.numeric_id || s.numericId || undefined,
            name: s.name || s.trackName || '',
            artist: s.artist || s.artistName || '',
            album: s.album || s.collectionName || '',
            url: s.url || s.trackViewUrl || '',
            artwork_url: s.artwork_url || s.artwork || '',
            is_local: Boolean(s.is_local || s.isLocal)
          }));
          send({
            action: 'append_search_results',
            params: { tracks: formatted }
          });
        }
      }
      const existingBtn = document.getElementById('btn-search-load-more');
      if (existingBtn) {
        if (hasMore) {
          existingBtn.disabled = false;
          existingBtn.textContent = 'Загрузить ещё';
        } else {
          existingBtn.remove();
        }
      }
      return;
    }

    // Initial search result (offset === 0)
    state.activeAiCuratedTitle = '';
    state.activeAiCuratedPrompt = '';
    currentSearchSongs = [...songs];
    currentSearchOffset = songs.length;
    currentSearchHasMore = hasMore;

    if (songs.length === 0 && albums.length === 0 && artists.length === 0 && playlists.length === 0) {
      dom.searchResults.innerHTML = '<div class="empty-state">Ничего не найдено</div>';
      return;
    }

    dom.searchResults.innerHTML = '';

    // Offer 1-click AI Sonic Curation when user types a multi-word descriptive query
    if (state.aiCuratorEnabled && state.searchScope !== 'ai' && state.searchQuery && state.searchQuery.trim().split(/\s+/).length >= 2) {
      const aiBanner = document.createElement('div');
      aiBanner.className = 'ai-suggest-banner';
      aiBanner.innerHTML = `
        <span class="ai-suggest-banner-text">✨ ${escapeHtml(IS_EN ? `Curate an AI sonic session for «${state.searchQuery}»` : `Собрать AI-подборку по настроению «${state.searchQuery}»`)}</span>
        <span class="ai-suggest-banner-cta">${translateTextToEn('Собрать AI-подборку')} ›</span>
      `;
      aiBanner.addEventListener('click', () => {
        dom.filterChips.forEach(c => c.classList.toggle('active', c.dataset.scope === 'ai'));
        state.searchScope = 'ai';
        executeSearch(state.searchQuery, 'ai');
      });
      dom.searchResults.appendChild(aiBanner);
    }

    // Render Songs
    if (songs.length > 0 && (state.searchScope === 'all' || state.searchScope === 'songs')) {
      const headerRow = document.createElement('div');
      headerRow.className = 'search-header-row';

      const heading = document.createElement('h3');
      heading.className = 'search-section-title';
      heading.textContent = 'ПЕСНИ';
      headerRow.appendChild(heading);

      const actionsBar = document.createElement('div');
      actionsBar.className = 'search-actions-bar';

      const btnPlayAll = document.createElement('button');
      btnPlayAll.className = 'btn-search-action btn-search-play-all';
      btnPlayAll.type = 'button';
      btnPlayAll.innerHTML = `
        <svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor">
          <polygon points="6 3 20 12 6 21 6 3"/>
        </svg>
        <span>Слушать всё</span>
      `;
      btnPlayAll.addEventListener('click', () => {
        playSearchResultsList([...currentSearchSongs], false);
      });

      const btnShuffle = document.createElement('button');
      btnShuffle.className = 'btn-search-action btn-search-shuffle';
      btnShuffle.type = 'button';
      btnShuffle.innerHTML = `
        <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2">
          <polyline points="16 3 21 3 21 8"/>
          <line x1="4" y1="20" x2="21" y2="3"/>
          <polyline points="21 16 21 21 16 21"/>
          <line x1="15" y1="15" x2="21" y2="21"/>
          <line x1="4" y1="4" x2="9" y2="9"/>
        </svg>
        <span>Перемешать</span>
      `;
      btnShuffle.addEventListener('click', () => {
        playSearchResultsList([...currentSearchSongs], true);
      });

      actionsBar.appendChild(btnPlayAll);
      actionsBar.appendChild(btnShuffle);
      headerRow.appendChild(actionsBar);
      dom.searchResults.appendChild(headerRow);

      const list = document.createElement('div');
      list.id = 'search-songs-list';
      list.className = 'track-list';
      songs.forEach(s => {
        list.appendChild(createTrackRow(s));
      });
      dom.searchResults.appendChild(list);

      if (hasMore) {
        const btnLoadMore = document.createElement('button');
        btnLoadMore.id = 'btn-search-load-more';
        btnLoadMore.className = 'btn-search-load-more';
        btnLoadMore.type = 'button';
        btnLoadMore.textContent = 'Загрузить ещё';
        btnLoadMore.addEventListener('click', () => {
          executeSearch(state.searchQuery, state.searchScope, currentSearchSongs.length);
        });
        dom.searchResults.appendChild(btnLoadMore);
      }
    }

    // Render Albums
    if (albums.length > 0 && (state.searchScope === 'all' || state.searchScope === 'albums')) {
      const heading = document.createElement('h3');
      heading.className = 'search-section-title';
      heading.textContent = 'АЛЬБОМЫ';
      dom.searchResults.appendChild(heading);

      const grid = document.createElement('div');
      grid.className = 'playlists-grid';
      albums.forEach(alb => {
        const card = document.createElement('div');
        card.className = 'playlist-card';
        const art = alb.artwork_url || alb.artwork || 'apple-touch-icon.svg';

        card.innerHTML = `
          <img class="playlist-card-art" src="${escapeHtml(art)}" alt="" loading="lazy">
          <span class="playlist-card-title">${escapeHtml(alb.name || alb.collectionName || '')}</span>
          <span class="playlist-card-count">${escapeHtml(alb.artist || alb.artistName || '')}</span>
        `;

        card.addEventListener('click', () => {
          openAlbumDetail({
            id: `${alb.id || alb.collectionId || ''}`,
            name: alb.name || alb.collectionName || '',
            artist: alb.artist || alb.artistName || '',
            artwork: art,
            url: alb.url || alb.collectionViewUrl || ''
          }, 'search');
        });

        grid.appendChild(card);
      });
      dom.searchResults.appendChild(grid);
    }

    // Render Playlists
    if (playlists.length > 0 && (state.searchScope === 'all' || state.searchScope === 'playlists')) {
      const heading = document.createElement('h3');
      heading.className = 'search-section-title';
      heading.textContent = 'ПЛЕЙЛИСТЫ';
      dom.searchResults.appendChild(heading);

      const grid = document.createElement('div');
      grid.className = 'playlists-grid';
      playlists.forEach(pl => {
        const card = document.createElement('div');
        card.className = 'playlist-card';
        const art = appendDeviceIdToUrl(pl.artwork_url || pl.artwork || 'apple-touch-icon.svg');
        const plName = pl.name || 'Плейлист';
        const baseSub = pl.curator_name || pl.curator || pl.subtitle || 'Apple Music';
        const matchedLocal = findMatchingLocalPlaylist(plName, pl.id || '', 0, pl.catalog_id || '');
        const isInLib = Boolean(pl.in_library || pl.is_local || matchedLocal);
        const displaySub = isInLib
          ? `✓ ${IS_EN ? 'In Library' : 'В медиатеке'} • ${baseSub}`
          : baseSub;
        card._searchPlaylistItem = pl;
        card._searchPlaylistBaseSub = baseSub;

        card.innerHTML = `
          <div class="media-card-art-wrap">
            <img class="playlist-card-art" src="${escapeHtml(art)}" alt="" loading="lazy" data-fallback-icon="apple-touch-icon.svg">
          </div>
          <span class="playlist-card-title">${escapeHtml(plName)}</span>
          <span class="playlist-card-count">${escapeHtml(displaySub)}</span>
        `;

        card.addEventListener('click', () => {
          const liveLocal = findMatchingLocalPlaylist(plName, pl.id || '', 0, pl.catalog_id || '');
          const liveInLib = Boolean(liveLocal) || Boolean(pl.in_library || pl.is_local);
          openPlaylistDetail({
            id: pl.id || '',
            catalog_id: pl.catalog_id || (String(pl.id || '').toLowerCase().startsWith('pl.') ? pl.id : ''),
            library_id: pl.library_id || (liveLocal && liveLocal.id) || '',
            local_name: pl.local_name || (liveLocal && liveLocal.name) || '',
            alternate_names: pl.alternate_names || (liveLocal && liveLocal.alternate_names) || [],
            name: plName,
            url: pl.url || '',
            artwork_url: art,
            track_count: Number(pl.track_count || pl.trackCount || (liveLocal && (liveLocal.track_count || liveLocal.trackCount)) || 0),
            curator_name: baseSub,
            is_local: liveInLib,
            in_library: liveInLib
          }, 'search');
        });

        grid.appendChild(card);
      });
      dom.searchResults.appendChild(grid);
    }

    // Render Artists
    if (artists.length > 0 && (state.searchScope === 'all' || state.searchScope === 'artists')) {
      const heading = document.createElement('h3');
      heading.className = 'search-section-title';
      heading.textContent = 'ИСПОЛНИТЕЛИ';
      dom.searchResults.appendChild(heading);

      const list = document.createElement('div');
      list.className = 'track-list';
      artists.forEach(art => {
        const row = document.createElement('div');
        row.className = 'track-row artist-row';
        const artistName = art.name || art.artistName || '';
        const genre = art.genre || 'Исполнитель';

        row.innerHTML = `
          <div class="track-thumb artist-thumb">
            <svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor">
              <path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/>
            </svg>
          </div>
          <div class="track-details">
            <span class="track-row-title">${escapeHtml(artistName)}</span>
            <span class="track-row-artist">${escapeHtml(genre)}</span>
          </div>
          <button class="btn-chart-play" type="button" aria-label="Слушать">
            <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor">
              <polygon points="6 3 20 12 6 21 6 3"/>
            </svg>
          </button>
        `;

        row.addEventListener('click', () => {
          if (!artistName) return;
          // Switch search to artist's songs & load them
          dom.searchInput.value = artistName;
          state.searchQuery = artistName;
          state.searchScope = 'songs';
          dom.filterChips.forEach(c => c.classList.toggle('active', c.dataset.scope === 'songs'));
          dom.btnClearSearch.classList.remove('hidden');
          executeSearch(artistName, 'songs');
        });

        list.appendChild(row);
      });
      dom.searchResults.appendChild(list);
    }
  }

  function syncSearchPlaylistCardsLibraryStatus(targetProbe, inLibrary) {
    if (!dom.searchResults || !targetProbe) return;
    dom.searchResults.querySelectorAll('.playlist-card').forEach(card => {
      const pl = card._searchPlaylistItem;
      if (!pl || !playlistsMatchCrossLocaleClient(pl, targetProbe)) return;
      pl.in_library = Boolean(inLibrary);
      pl.is_local = Boolean(inLibrary);
      const subEl = card.querySelector('.playlist-card-count');
      if (subEl) {
        const baseSub = card._searchPlaylistBaseSub || pl.curator_name || pl.curator || pl.subtitle || 'Apple Music';
        subEl.textContent = inLibrary
          ? `✓ ${IS_EN ? 'In Library' : 'В медиатеке'} • ${baseSub}`
          : baseSub;
      }
    });
  }

  function playSearchResultsList(songs, shuffle, startIndex = null, options = {}) {
    if (!songs || songs.length === 0) return;
    const isAiCurated = Boolean(options.queueName || state.activeAiCuratedTitle);
    const resolvedQuery = String(options.query !== undefined ? options.query : (isAiCurated ? '' : (state.searchQuery || ''))).trim();
    const resolvedQueueName = options.queueName
      || state.activeAiCuratedTitle
      || (resolvedQuery
        ? (IS_EN ? `Search: ${resolvedQuery}` : `Поиск: ${resolvedQuery}`)
        : (IS_EN ? 'Search Results' : 'Результаты поиска'));
    const resolvedCuratorPrompt = options.curatorPrompt !== undefined
      ? options.curatorPrompt
      : (isAiCurated ? (state.activeAiCuratedPrompt || '') : '');
    const hasExplicitStart = Number.isInteger(startIndex) && startIndex >= 0 && startIndex < songs.length;
    const effectiveStartIndex = shuffle ? (hasExplicitStart ? startIndex : -1) : (hasExplicitStart ? startIndex : 0);
    const firstSong = effectiveStartIndex >= 0 ? (songs[effectiveStartIndex] || songs[0]) : songs[0];
    const expectedFirstTitle = firstSong ? (firstSong.name || firstSong.trackName || '') : '';
    optimisticPlay();
    markWaitingForPlayback({
      targetName: resolvedQueueName,
      expectedTrackName: shuffle ? '' : expectedFirstTitle
    });
    const busyText = isAiCurated
      ? (IS_EN ? `Starting «${resolvedQueueName}»...` : `Запуск «${resolvedQueueName}»...`)
      : (shuffle ? 'Перемешивание...' : 'Запуск результатов...');
    setUIBusy(true, busyText);
    const formatted = songs.map(s => ({
      id: `${s.id || s.trackId || ''}`,
      numeric_id: s.numeric_id || s.numericId || undefined,
      name: s.name || s.trackName || '',
      artist: s.artist || s.artistName || '',
      album: s.album || s.collectionName || '',
      duration: Number(s.duration) || (s.trackTimeMillis ? Math.round(s.trackTimeMillis / 1000) : 0),
      url: s.url || s.trackViewUrl || '',
      artwork_url: s.artwork_url || s.artwork || '',
      is_local: Boolean(s.is_local || s.isLocal)
    }));

    send({
      action: 'play_search_results',
      params: {
        tracks: formatted,
        startIndex: effectiveStartIndex,
        pin_start_track: Boolean(!shuffle || hasExplicitStart),
        shuffle: Boolean(shuffle),
        queue_name: resolvedQueueName,
        query: resolvedQuery,
        curator_prompt: resolvedCuratorPrompt
      }
    });

    if (dom.btnPlayPause) {
      dom.btnPlayPause.classList.add('loading-pulse');
      setTimeout(() => dom.btnPlayPause.classList.remove('loading-pulse'), 1200);
    }
  }
