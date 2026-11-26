  // --- Queue View Handling (Previous, Now Playing, and Upcoming) ---
  const QUEUE_HISTORY_PREVIEW_LIMIT = 3;
  const lastQueueListKey = { upcoming: '', history: '' };
  let lastCurrentQueueTrackKey = '';

  function updateQueue(data) {
    if (!data) return;

    const upcoming = data.upcoming_tracks || data.upcomingTracks || [];
    const history = data.history_tracks || data.historyTracks || [];
    const currentIdx = data.current_index || data.currentIndex || 0;
    const total = data.total_tracks || data.totalTracks || upcoming.length;
    const playlistName = data.playlist || state.queue.playlist || '';

    state.queue.upcoming = upcoming;
    state.queue.history = history;
    state.queue.currentIndex = currentIdx;
    state.queue.totalTracks = total;
    state.queue.playlist = playlistName;
    if (history.length <= QUEUE_HISTORY_PREVIEW_LIMIT) {
      state.queueHistoryExpanded = false;
    }

    const isGenericPl = !playlistName || playlistName === 'Музыка' || playlistName === 'Music' || playlistName === 'Apple Music' || playlistName === 'Очередь';
    const plPrefix = (!isGenericPl && playlistName !== 'Очередь AMR')
      ? `${translateTextToEn(playlistName)} · `
      : (playlistName === 'Очередь AMR' ? (IS_EN ? 'AMR Queue · ' : 'Очередь AMR · ') : '');
    if (IS_EN) {
      dom.queueSubtitle.textContent = history.length > 0
        ? `${plPrefix}${upcoming.length} up next · ${history.length} previous`
        : `${plPrefix}${upcoming.length} tracks in queue`;
    } else {
      dom.queueSubtitle.textContent = history.length > 0
        ? `${plPrefix}${upcoming.length} далее · ${history.length} ранее`
        : `${plPrefix}${upcoming.length} треков в очереди`;
    }

    renderQueueHistorySection(history);
    renderCurrentQueueTrack(dom.queueCurrentTrack);
    renderQueueList(dom.queueUpcomingList, upcoming, 'upcoming');
    syncStandbyQueueBadge();
    if (isStandbyQueueModalOpen()) {
      renderStandbyQueueModal();
    }
  }

  function renderQueueHistorySection(history) {
    if (!dom.queueHistoryGroup || !dom.queueHistoryList) return;
    if (!Array.isArray(history) || history.length === 0) {
      dom.queueHistoryGroup.style.display = 'none';
      dom.queueHistoryList.innerHTML = '';
      lastQueueListKey.history = '';
      return;
    }
    dom.queueHistoryGroup.style.display = 'block';

    const hasOverflow = history.length > QUEUE_HISTORY_PREVIEW_LIMIT;
    const expanded = Boolean(state.queueHistoryExpanded) && hasOverflow;
    if (dom.btnToggleQueueHistory) {
      dom.btnToggleQueueHistory.classList.toggle('hidden', !hasOverflow);
      if (hasOverflow) {
        dom.btnToggleQueueHistory.textContent = expanded
          ? (IS_EN ? 'Show Less' : 'Свернуть')
          : (IS_EN ? `Show All (${history.length})` : `Показать все (${history.length})`);
      }
    }

    // Backend `history[0]` is the most recently played track (`curIdx - 1`);
    // display chronologically top-to-bottom so the last played track sits directly above NOW PLAYING.
    const slice = expanded ? history : history.slice(0, QUEUE_HISTORY_PREVIEW_LIMIT);
    const chronological = slice.map((t, idx) => ({ track: t, historyIdx: idx })).reverse();
    const key = `${expanded ? '1' : '0'}|${chronological.map(({ track: t, historyIdx }) => `${historyIdx}:${t.id || t.numeric_id || t.numericId || ''}:${t.name}:${t.artist}:${t.artwork || t.artwork_url || ''}`).join('|')}`;
    if (key === lastQueueListKey.history) {
      return;
    }
    lastQueueListKey.history = key;

    dom.queueHistoryList.innerHTML = '';
    chronological.forEach(({ track: t, historyIdx }) => {
      const row = document.createElement('div');
      row.className = 'track-row history-track-row';
      const artSrc = getArtworkSrc(t);
      const dur = formatTime(t.duration || 0);
      row.innerHTML = `
        <img class="track-thumb" src="${escapeHtml(artSrc)}" alt="" loading="lazy" data-fallback-icon="apple-touch-icon.svg">
        <div class="track-details">
          <span class="track-row-title">${escapeHtml(t.name || (IS_EN ? 'Untitled' : 'Без названия'))}</span>
          <span class="track-row-artist">${escapeHtml(t.artist || (IS_EN ? 'Unknown Artist' : 'Неизвестный исполнитель'))}</span>
        </div>
        <span class="track-row-dur">${dur}</span>
      `;
      row.addEventListener('click', () => {
        optimisticPlay();
        markWaitingForPlayback({ targetName: t.name || '', expectedTrackName: t.name || '' });
        setUIBusy(true, IS_EN ? 'Switching track...' : 'Переход к треку...');
        send({ action: 'play_history_index', index: historyIdx, params: { index: historyIdx } });
      });
      dom.queueHistoryList.appendChild(row);
    });
  }

  if (dom.btnToggleQueueHistory) {
    dom.btnToggleQueueHistory.addEventListener('click', () => {
      triggerHaptic('light');
      state.queueHistoryExpanded = !state.queueHistoryExpanded;
      lastQueueListKey.history = '';
      renderQueueHistorySection(state.queue.history || []);
    });
  }

  function renderCurrentQueueTrack(container) {
    if (!container) return;
    const cur = state.track;
    if (!cur || !cur.name) {
      if (dom.queueCurrentGroup) dom.queueCurrentGroup.style.display = 'none';
      container.innerHTML = '';
      lastCurrentQueueTrackKey = '';
      return;
    }
    if (dom.queueCurrentGroup) dom.queueCurrentGroup.style.display = 'block';

    const artSrc = getArtworkSrc(cur);
    const dur = formatTime(cur.duration || state.duration || 0);
    const key = `${cur.id || ''}|${cur.name}|${cur.artist}|${artSrc}`;

    if (key === lastCurrentQueueTrackKey) {
      const durEl = container.querySelector('.track-row-dur');
      if (durEl && durEl.textContent !== dur) durEl.textContent = dur;
      return;
    }
    lastCurrentQueueTrackKey = key;

    container.innerHTML = `
      <div class="track-row now-playing-row">
        <img class="track-thumb" src="${escapeHtml(artSrc)}" alt="" loading="lazy" data-fallback-icon="apple-touch-icon.svg">
        <div class="track-details">
          <span class="track-row-title">${escapeHtml(cur.name || (IS_EN ? 'Untitled' : 'Без названия'))}</span>
          <span class="track-row-artist">${escapeHtml(cur.artist || (IS_EN ? 'Unknown Artist' : 'Неизвестный исполнитель'))}</span>
        </div>
        <span class="track-row-dur">${dur}</span>
      </div>
    `;
  }

  function renderQueueList(container, tracks, type) {
    if (!container) return;
    if (!tracks || tracks.length === 0) {
      container.innerHTML = `<div class="empty-state">${type === 'upcoming' ? (IS_EN ? 'No upcoming tracks' : 'Нет предстоящих треков') : (IS_EN ? 'No previous tracks' : 'История пуста')}</div>`;
      lastQueueListKey[type] = '';
      return;
    }

    const currentKey = tracks.map(t => `${t.id || t.numeric_id || t.numericId || ''}:${t.name}:${t.artist}:${t.artwork || t.artwork_url || ''}`).join('|');
    if (currentKey === lastQueueListKey[type]) {
      return;
    }
    lastQueueListKey[type] = currentKey;

    container.innerHTML = '';
    tracks.forEach((t, idx) => {
      const row = document.createElement('div');
      row.className = 'track-row';
      const artSrc = getArtworkSrc(t);
      const dur = formatTime(t.duration || 0);

      row.innerHTML = `
        <img class="track-thumb" src="${escapeHtml(artSrc)}" alt="" loading="lazy" data-fallback-icon="apple-touch-icon.svg">
        <div class="track-details">
          <span class="track-row-title">${escapeHtml(t.name || (IS_EN ? 'Untitled' : 'Без названия'))}</span>
          <span class="track-row-artist">${escapeHtml(t.artist || (IS_EN ? 'Unknown Artist' : 'Неизвестный исполнитель'))}</span>
        </div>
        <span class="track-row-dur">${dur}</span>
      `;

      row.addEventListener('click', () => {
        optimisticPlay();
        markWaitingForPlayback({ targetName: t.name || '', expectedTrackName: t.name || '' });
        setUIBusy(true, IS_EN ? 'Switching track...' : 'Переход к треку...');
        if (type === 'upcoming') {
          send({ action: 'queue_play_index', params: { index: idx } });
        } else {
          send({ action: 'play_history_index', index: idx, params: { index: idx } });
        }
      });

      container.appendChild(row);
    });
  }

  dom.btnClearQueue.addEventListener('click', () => {
    send({ action: 'queue_clear' });
  });

  if (dom.btnSaveQueuePlaylist) {
    dom.btnSaveQueuePlaylist.addEventListener('click', () => {
      const prevChrono = Array.isArray(state.queue.history) ? [...state.queue.history].reverse() : [];
      const cur = (state.track && state.track.name) ? [state.track] : [];
      const upcoming = Array.isArray(state.queue.upcoming) ? state.queue.upcoming : [];
      const allQueueTracks = [...prevChrono, ...cur, ...upcoming];
      if (allQueueTracks.length === 0) {
        showToast(IS_EN ? 'Queue is empty' : 'Очередь пуста');
        return;
      }
      triggerHaptic('medium');
      const GENERIC_QUEUE_NAMES = new Set([
        'очередь amr',
        'очередь',
        'amr queue',
        'результаты поиска',
        'search results'
      ]);
      const rawQueueName = String((state.queue && state.queue.playlist) || '').trim();
      const isGenericQueue = !rawQueueName || GENERIC_QUEUE_NAMES.has(rawQueueName.toLowerCase());
      let plName = '';
      if (!isGenericQueue) {
        plName = rawQueueName;
      } else if (state.activeAiCuratedTitle) {
        plName = state.activeAiCuratedTitle;
      } else if (state.searchQuery && String(state.searchQuery).trim()) {
        const cleanQ = String(state.searchQuery).trim();
        plName = IS_EN ? `Search: ${cleanQ}` : `Поиск: ${cleanQ}`;
      }
      dom.btnSaveQueuePlaylist.disabled = true;
      if (dom.btnSaveQueueText) {
        dom.btnSaveQueueText.textContent = translateTextToEn('Добавление...');
      }
      send({
        action: 'save_queue_to_playlist',
        params: {
          name: plName,
          tracks: allQueueTracks
        }
      });
    });
  }

  // --- StandBy / TV Mode Fullscreen Queue Overlay (Previous, Current, Up Next) ---
  const TV_QUEUE_HISTORY_PREVIEW_LIMIT = 3;
  const lastTvQueueRenderKeys = { history: '', current: '', upcoming: '' };

  function isMobileLandscapeStandbyViewport() {
    if (document.body.classList.contains('standby-landscape-open')) return true;
    if (typeof window !== 'undefined' && typeof window.matchMedia === 'function') {
      return window.matchMedia('(max-height: 540px) and (min-width: 568px) and (orientation: landscape) and (hover: none) and (pointer: coarse)').matches;
    }
    return false;
  }

  function isStandbyQueueModalOpen() {
    const modal = document.getElementById('standby-queue-modal');
    return Boolean(modal && !modal.classList.contains('hidden'));
  }

  function syncStandbyQueueBadge() {
    const badge = document.getElementById('standby-queue-count-badge');
    if (!badge) return;
    const upcomingCount = Array.isArray(state.queue && state.queue.upcoming) ? state.queue.upcoming.length : 0;
    if (upcomingCount > 0) {
      const txt = upcomingCount > 99 ? '99+' : String(upcomingCount);
      if (badge.textContent !== txt) badge.textContent = txt;
      badge.classList.remove('hidden');
    } else {
      badge.classList.add('hidden');
    }
  }

  function formatTvQueueSubHtml(t) {
    const artist = t.artist || (IS_EN ? 'Unknown Artist' : 'Неизвестный исполнитель');
    const album = String(t.album || '').trim();
    const title = String(t.name || '').trim();
    if (album && album.toLowerCase() !== title.toLowerCase()) {
      return `${escapeHtml(artist)}<span class="tv-queue-sub-album"> · ${escapeHtml(album)}</span>`;
    }
    return escapeHtml(artist);
  }

  function renderStandbyQueueModal(opts = {}) {
    const forceRebuild = Boolean(opts && opts.force);
    if (forceRebuild) {
      lastTvQueueRenderKeys.history = '';
      lastTvQueueRenderKeys.current = '';
      lastTvQueueRenderKeys.upcoming = '';
    }

    const history = Array.isArray(state.queue && state.queue.history) ? state.queue.history : [];
    const upcoming = Array.isArray(state.queue && state.queue.upcoming) ? state.queue.upcoming : [];
    const playlistName = (state.queue && state.queue.playlist) || '';
    const cur = (state.track && state.track.name) ? state.track : null;
    const isPlaying = state.playerState === 'playing';

    if (history.length <= TV_QUEUE_HISTORY_PREVIEW_LIMIT) {
      state.tvQueueHistoryExpanded = false;
    }

    const subtitleEl = document.getElementById('standby-queue-subtitle');
    if (subtitleEl) {
      const isGenericPl = !playlistName || playlistName === 'Музыка' || playlistName === 'Music' || playlistName === 'Apple Music' || playlistName === 'Очередь';
      const plPrefix = (!isGenericPl && playlistName !== 'Очередь AMR')
        ? `${translateTextToEn(playlistName)} · `
        : (playlistName === 'Очередь AMR' ? (IS_EN ? 'AMR Queue · ' : 'Очередь AMR · ') : '');
      if (history.length > 0 || upcoming.length > 0) {
        if (IS_EN) {
          subtitleEl.textContent = history.length > 0
            ? `${plPrefix}${upcoming.length} up next · ${history.length} previous`
            : `${plPrefix}${upcoming.length} tracks up next`;
        } else {
          subtitleEl.textContent = history.length > 0
            ? `${plPrefix}${upcoming.length} далее · ${history.length} ранее`
            : `${plPrefix}${upcoming.length} треков далее`;
        }
      } else {
        subtitleEl.textContent = IS_EN
          ? 'Previous, now playing, and upcoming tracks'
          : 'Предыдущие, текущий трек и следующие композиции';
      }
    }

    const clearBtn = document.getElementById('btn-standby-queue-clear');
    if (clearBtn) {
      clearBtn.classList.toggle('hidden', upcoming.length === 0);
    }

    // 1. History ("Ранее")
    const histSection = document.getElementById('standby-queue-history-section');
    const histList = document.getElementById('standby-queue-history-list');
    const histCountEl = document.getElementById('standby-queue-history-count');
    const histToggleBtn = document.getElementById('btn-standby-queue-history-toggle');
    if (histSection && histList) {
      if (history.length === 0) {
        histSection.classList.add('hidden');
        histList.innerHTML = '';
        lastTvQueueRenderKeys.history = '';
      } else {
        histSection.classList.remove('hidden');
        if (histCountEl && histCountEl.textContent !== String(history.length)) {
          histCountEl.textContent = String(history.length);
        }
        const hasOverflow = history.length > TV_QUEUE_HISTORY_PREVIEW_LIMIT;
        const expanded = Boolean(state.tvQueueHistoryExpanded) && hasOverflow;
        if (histToggleBtn) {
          histToggleBtn.classList.toggle('hidden', !hasOverflow);
          if (hasOverflow) {
            histToggleBtn.textContent = expanded
              ? (IS_EN ? 'Show Less' : 'Свернуть')
              : (IS_EN ? `Show All (${history.length})` : `Показать все (${history.length})`);
          }
        }
        const slice = expanded ? history : history.slice(0, TV_QUEUE_HISTORY_PREVIEW_LIMIT);
        const chronological = slice.map((t, idx) => ({ track: t, historyIdx: idx })).reverse();
        const histKey = `${expanded ? '1' : '0'}|${chronological.map(({ track: t, historyIdx }) => `${historyIdx}:${t.id || t.numeric_id || t.numericId || ''}:${t.name}:${t.artist}:${t.album || ''}:${t.artwork || t.artwork_url || ''}`).join('|')}`;
        if (histKey !== lastTvQueueRenderKeys.history) {
          lastTvQueueRenderKeys.history = histKey;
          histList.innerHTML = '';
          chronological.forEach(({ track: t, historyIdx }) => {
            const row = document.createElement('div');
            row.className = 'tv-queue-row is-history';
            const artSrc = getArtworkSrc(t);
            const dur = formatTime(t.duration || 0);
            row.innerHTML = `
              <div class="tv-queue-index">
                <span class="tv-queue-index-num">−${historyIdx + 1}</span>
                <span class="tv-queue-index-play" aria-hidden="true">
                  <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor"><polygon points="6 4 20 12 6 20 6 4"/></svg>
                </span>
              </div>
              <img class="tv-queue-cover" src="${escapeHtml(artSrc)}" alt="" loading="lazy" data-fallback-icon="apple-touch-icon.svg">
              <div class="tv-queue-meta">
                <span class="tv-queue-title">${escapeHtml(t.name || (IS_EN ? 'Untitled' : 'Без названия'))}</span>
                <span class="tv-queue-sub">${formatTvQueueSubHtml(t)}</span>
              </div>
              <div class="tv-queue-right">
                <span class="tv-queue-dur">${dur}</span>
              </div>
            `;
            row.addEventListener('click', () => {
              optimisticPlay();
              markWaitingForPlayback({ targetName: t.name || '', expectedTrackName: t.name || '' });
              setUIBusy(true, IS_EN ? 'Switching track...' : 'Переход к треку...');
              send({ action: 'play_history_index', index: historyIdx, params: { index: historyIdx } });
            });
            histList.appendChild(row);
          });
        }
      }
    }

    // 2. Current ("Сейчас играет")
    const curContainer = document.getElementById('standby-queue-current-track');
    if (curContainer) {
      if (!cur) {
        const emptyKey = '__empty__';
        if (lastTvQueueRenderKeys.current !== emptyKey) {
          lastTvQueueRenderKeys.current = emptyKey;
          curContainer.innerHTML = `<div class="tv-queue-empty">${IS_EN ? 'Nothing playing right now' : 'Сейчас ничего не воспроизводится'}</div>`;
        }
      } else {
        const artSrc = getArtworkSrc(cur);
        const dur = formatTime(cur.duration || state.duration || 0);
        const curKey = `${cur.id || ''}|${cur.name}|${cur.artist}|${cur.album || ''}|${artSrc}`;
        if (curKey !== lastTvQueueRenderKeys.current) {
          lastTvQueueRenderKeys.current = curKey;
          curContainer.innerHTML = '';
          const row = document.createElement('div');
          row.className = 'tv-queue-row is-current';
          row.innerHTML = `
            <div class="tv-queue-index">
              <span class="tv-queue-eq ${isPlaying ? 'is-playing' : ''}" aria-hidden="true">
                <span class="tv-queue-eq-bar"></span>
                <span class="tv-queue-eq-bar"></span>
                <span class="tv-queue-eq-bar"></span>
              </span>
            </div>
            <img class="tv-queue-cover" src="${escapeHtml(artSrc)}" alt="" loading="lazy" data-fallback-icon="apple-touch-icon.svg">
            <div class="tv-queue-meta">
              <span class="tv-queue-title">${escapeHtml(cur.name || (IS_EN ? 'Untitled' : 'Без названия'))}</span>
              <span class="tv-queue-sub">${formatTvQueueSubHtml(cur)}</span>
            </div>
            <div class="tv-queue-right">
              <span class="tv-queue-live-pill ${isPlaying ? '' : 'is-paused'}">${isPlaying ? (IS_EN ? 'PLAYING' : 'ИГРАЕТ') : (IS_EN ? 'PAUSED' : 'ПАУЗА')}</span>
              <span class="tv-queue-dur">${dur}</span>
            </div>
          `;
          row.addEventListener('click', () => {
            togglePlayPause();
          });
          curContainer.appendChild(row);
        } else {
          const eqEl = curContainer.querySelector('.tv-queue-eq');
          if (eqEl) eqEl.classList.toggle('is-playing', isPlaying);
          const pillEl = curContainer.querySelector('.tv-queue-live-pill');
          if (pillEl) {
            pillEl.classList.toggle('is-paused', !isPlaying);
            const pillTxt = isPlaying ? (IS_EN ? 'PLAYING' : 'ИГРАЕТ') : (IS_EN ? 'PAUSED' : 'ПАУЗА');
            if (pillEl.textContent !== pillTxt) pillEl.textContent = pillTxt;
          }
          const durEl = curContainer.querySelector('.tv-queue-dur');
          if (durEl && durEl.textContent !== dur) durEl.textContent = dur;
        }
      }
    }

    // 3. Upcoming ("Далее в очереди")
    const upList = document.getElementById('standby-queue-upcoming-list');
    const upCountEl = document.getElementById('standby-queue-upcoming-count');
    if (upCountEl && upCountEl.textContent !== String(upcoming.length)) {
      upCountEl.textContent = String(upcoming.length);
    }
    if (upList) {
      if (upcoming.length === 0) {
        const emptyUpKey = '__empty_upcoming__';
        if (lastTvQueueRenderKeys.upcoming !== emptyUpKey) {
          lastTvQueueRenderKeys.upcoming = emptyUpKey;
          upList.innerHTML = `<div class="tv-queue-empty">${IS_EN ? 'No upcoming tracks in queue' : 'Нет предстоящих треков в очереди'}</div>`;
        }
      } else {
        const upKey = upcoming.map(t => `${t.id || t.numeric_id || t.numericId || ''}:${t.name}:${t.artist}:${t.album || ''}:${t.artwork || t.artwork_url || ''}`).join('|');
        if (upKey !== lastTvQueueRenderKeys.upcoming) {
          lastTvQueueRenderKeys.upcoming = upKey;
          upList.innerHTML = '';
          upcoming.forEach((t, idx) => {
            const row = document.createElement('div');
            row.className = 'tv-queue-row is-upcoming';
            const artSrc = getArtworkSrc(t);
            const dur = formatTime(t.duration || 0);
            row.innerHTML = `
              <div class="tv-queue-index">
                <span class="tv-queue-index-num">${idx + 1}</span>
                <span class="tv-queue-index-play" aria-hidden="true">
                  <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor"><polygon points="6 4 20 12 6 20 6 4"/></svg>
                </span>
              </div>
              <img class="tv-queue-cover" src="${escapeHtml(artSrc)}" alt="" loading="lazy" data-fallback-icon="apple-touch-icon.svg">
              <div class="tv-queue-meta">
                <span class="tv-queue-title">${escapeHtml(t.name || (IS_EN ? 'Untitled' : 'Без названия'))}</span>
                <span class="tv-queue-sub">${formatTvQueueSubHtml(t)}</span>
              </div>
              <div class="tv-queue-right">
                <span class="tv-queue-dur">${dur}</span>
              </div>
            `;
            row.addEventListener('click', () => {
              optimisticPlay();
              markWaitingForPlayback({ targetName: t.name || '', expectedTrackName: t.name || '' });
              setUIBusy(true, IS_EN ? 'Switching track...' : 'Переход к треку...');
              send({ action: 'queue_play_index', params: { index: idx } });
            });
            upList.appendChild(row);
          });
        }
      }
    }
  }

  function openStandbyQueueModal() {
    if (isMobileLandscapeStandbyViewport()) return;
    const modal = document.getElementById('standby-queue-modal');
    if (!modal) return;
    if (typeof closeStandbyLibraryModal === 'function') closeStandbyLibraryModal();
    if (typeof closeStandbyAiModal === 'function') closeStandbyAiModal();
    const p = document.getElementById('top-settings-popover');
    if (p) {
      blurFocusedInContainer(p);
      p.classList.add('hidden');
      p.setAttribute('aria-hidden', 'true');
    }

    state.tvQueueHistoryExpanded = false;
    renderStandbyQueueModal({ force: true });
    send({ action: 'get_queue' });

    modal.classList.remove('hidden');
    modal.setAttribute('aria-hidden', 'false');

    const scrollEl = document.getElementById('standby-queue-scroll');
    if (scrollEl) {
      scrollEl.scrollTop = 0;
    }
  }

  function closeStandbyQueueModal() {
    const modal = document.getElementById('standby-queue-modal');
    if (!modal) return;
    blurFocusedInContainer(modal);
    modal.classList.add('hidden');
    modal.setAttribute('aria-hidden', 'true');
  }

  const btnStandbyQueueClear = document.getElementById('btn-standby-queue-clear');
  if (btnStandbyQueueClear) {
    btnStandbyQueueClear.addEventListener('click', () => {
      triggerHaptic('light');
      send({ action: 'queue_clear' });
    });
  }

  const btnStandbyQueueHistToggle = document.getElementById('btn-standby-queue-history-toggle');
  if (btnStandbyQueueHistToggle) {
    btnStandbyQueueHistToggle.addEventListener('click', () => {
      triggerHaptic('light');
      state.tvQueueHistoryExpanded = !state.tvQueueHistoryExpanded;
      lastTvQueueRenderKeys.history = '';
      renderStandbyQueueModal();
    });
  }
