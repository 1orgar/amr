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
      ? `${playlistName} · `
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
