  function createStandbyAiTagPillElement(item, forcePinned = false) {
    const isPinned = forcePinned || isPromptPinnedClient(item.prompt);
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = `standby-ai-tag-pill tag-size-${item.size || 'lg'} tag-theme-${item.theme || 'violet'}${isPinned ? ' is-pinned' : ''}`;
    btn.setAttribute('data-ai-prompt', item.prompt);
    btn.innerHTML = `${formatStandbyAiTagHtml(item.label)}<span class="standby-tag-pin-badge ${isPinned ? 'active' : ''}" title="${translateTextToEn('Закрепить / открепить вайб')}">${isPinned ? '★' : '☆'}</span>`;
    const pinBadge = btn.querySelector('.standby-tag-pin-badge');
    if (pinBadge) {
      pinBadge.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        togglePinAiPrompt(item.prompt, item.label);
      });
    }
    btn.addEventListener('click', () => {
      triggerStandbyAiTagPlay(item.prompt, item.label);
    });
    return btn;
  }

  const MAX_STANDBY_AI_CHIPS = 120;

  function appendStandbyAiTagBatch(count = 24) {
    const cloud = document.getElementById('standby-ai-tag-cloud');
    const sentinel = document.getElementById('standby-ai-sentinel');
    if (!cloud) return;
    const availableSlots = Math.max(0, MAX_STANDBY_AI_CHIPS - cloud.children.length);
    const batchCount = Math.min(count, availableSlots);
    if (batchCount <= 0) {
      if (sentinel) sentinel.classList.add('hidden');
      return;
    }
    const frag = document.createDocumentFragment();
    for (let i = 0; i < batchCount; i++) {
      const item = buildNextStandbyAiTagItem();
      frag.appendChild(createStandbyAiTagPillElement(item, false));
    }
    cloud.appendChild(frag);
    if (sentinel && cloud.children.length >= MAX_STANDBY_AI_CHIPS) {
      sentinel.classList.add('hidden');
    }
  }

  function resetAndGenerateStandbyAiTagCloud() {
    const cloud = document.getElementById('standby-ai-tag-cloud');
    const scrollEl = document.getElementById('standby-ai-scroll');
    const sentinel = document.getElementById('standby-ai-sentinel');
    if (!cloud) return;
    cloud.innerHTML = '';
    if (sentinel) sentinel.classList.remove('hidden');
    if (scrollEl) scrollEl.scrollTop = 0;
    standbyAiGeneratedCount = 0;
    if (Array.isArray(state.pinnedAiPrompts) && state.pinnedAiPrompts.length > 0) {
      const pinFrag = document.createDocumentFragment();
      state.pinnedAiPrompts.slice(0, MAX_STANDBY_AI_CHIPS).forEach((p, idx) => {
        const prompt = IS_EN ? (p.promptEn || p.prompt_en || p.prompt || '') : (p.promptRu || p.prompt_ru || p.prompt || '');
        const label = IS_EN ? (p.labelEn || p.label_en || p.label || prompt) : (p.labelRu || p.label_ru || p.label || prompt);
        if (!prompt) return;
        pinFrag.appendChild(createStandbyAiTagPillElement({
          label,
          prompt,
          size: idx % 2 === 0 ? 'xl' : 'lg',
          theme: AI_TV_THEMES[idx % AI_TV_THEMES.length]
        }, true));
      });
      cloud.appendChild(pinFrag);
    }
    appendStandbyAiTagBatch(28);
  }

  function ensureStandbyAiScrollBinding() {
    if (standbyAiScrollBound) return;
    const scrollEl = document.getElementById('standby-ai-scroll');
    const sentinel = document.getElementById('standby-ai-sentinel');
    const loadMoreBtn = document.getElementById('btn-standby-ai-load-more');
    if (!scrollEl) return;
    standbyAiScrollBound = true;

    if (loadMoreBtn) {
      loadMoreBtn.addEventListener('click', () => {
        triggerHaptic('light');
        appendStandbyAiTagBatch(18);
      });
    }

    if ('IntersectionObserver' in window && sentinel) {
      const io = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            appendStandbyAiTagBatch(18);
          }
        });
      }, { root: scrollEl, rootMargin: '260px' });
      io.observe(sentinel);
    }
  }

  function openStandbyAiModal() {
    if (!state.aiCuratorEnabled) return;
    const modal = document.getElementById('standby-ai-modal');
    if (!modal) return;
    closeStandbyLibraryModal();
    if (typeof closeStandbyQueueModal === 'function') closeStandbyQueueModal();
    const p = document.getElementById('top-settings-popover');
    if (p) {
      blurFocusedInContainer(p);
      p.classList.add('hidden');
      p.setAttribute('aria-hidden', 'true');
    }

    resetAndGenerateStandbyAiTagCloud();
    ensureStandbyAiScrollBinding();

    modal.classList.remove('hidden');
    modal.setAttribute('aria-hidden', 'false');
  }

  function closeStandbyAiModal() {
    const modal = document.getElementById('standby-ai-modal');
    if (!modal) return;
    blurFocusedInContainer(modal);
    modal.classList.add('hidden');
    modal.setAttribute('aria-hidden', 'true');
  }

  function updateStandbyActiveTile() {
    const grid = document.getElementById('standby-library-grid');
    if (!grid) return;
    const curPlaylist = ((state.queue && state.queue.playlist) || '').trim().toLowerCase();
    const activeKey = (state.activeStandbyTileKey || '').toLowerCase();
    grid.querySelectorAll('.standby-square-tile').forEach(tile => {
      const key = (tile.getAttribute('data-tile-key') || '').toLowerCase();
      const name = (tile.getAttribute('data-tile-name') || '').toLowerCase();
      const isMatch = (activeKey && key === activeKey) ||
        (curPlaylist && name && (curPlaylist === name || (curPlaylist.includes('станция') && activeKey === key)));
      tile.classList.toggle('active', Boolean(isMatch));
    });
  }

  function buildAlbumConfigMatchKey(name, artist) {
    return `${normalizeAlbumMatchText(name)}|${normalizeAlbumMatchText(artist)}`;
  }

  function renderStandbyQuickTiles() {
    const grid = document.getElementById('standby-library-grid');
    if (!grid) return;

    const cfg = state.tvLibraryConfig || {};
    const playlistsMode = cfg.playlists_mode || 'all';
    const albumsMode = cfg.albums_mode || 'recent';

    const rawPlaylists = (state.playlists || []).filter(pl => {
      const n = (pl.name || '').trim();
      if (!n) return false;
      if (n.includes('Очередь AMR') || n.startsWith('AMR ')) return false;
      return true;
    });

    const allLibAlbums = Array.isArray(state.libraryAlbums) ? state.libraryAlbums : [];

    const sig = JSON.stringify(cfg) +
      '|pl:' + rawPlaylists.map(p => `${p.name}:${p.artwork_url || p.artworkUrl || ''}:${p.track_count || p.trackCount || 0}`).join('|') +
      '|albums:' + allLibAlbums.map(a => `${a.id || ''}:${a.name || ''}:${a.artist || ''}:${a.artwork || ''}`).join('|') +
      '|mixes:' + ((state.personalMixes || []).map(m => `${m.name}:${m.id || ''}`).join(','));
    if (sig === lastStandbyTilesSignature && grid.children.length > 0) {
      updateStandbyActiveTile();
      return;
    }
    lastStandbyTilesSignature = sig;
    grid.innerHTML = '';

    const playBadgeHtml = `
      <div class="standby-tile-play-badge">
        <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor">
          <polygon points="7 4 20 12 7 20 7 4"/>
        </svg>
      </div>
    `;

    // 1. Core Personal Stations & Mixes: Моя станция, Станция открытий, В моём вкусе, Сейчас на повторе
    const coreTiles = [
      {
        key: 'my-station',
        visible: cfg.show_my_station !== false,
        title: IS_EN ? 'My Station' : 'Моя станция',
        type: 'station',
        onClick: () => {
          state.activeStandbyTileKey = 'my-station';
          updateStandbyActiveTile();
          closeStandbyLibraryModal();
          optimisticPlay();
          markWaitingForPlayback({ isStation: true, targetName: 'Моя станция' });
          setUIBusy(true, 'Запуск «Моей станции»...');
          send({
            action: 'play_hero_card',
            params: {
              index: 1,
              name: 'Моя станция',
              artist: 'Персональная радиостанция',
              id: '',
              url: '',
              type: 'station'
            }
          });
        }
      },
      {
        key: 'discovery-station',
        visible: cfg.show_discovery_station !== false,
        title: IS_EN ? 'Discovery Station' : 'Станция открытий',
        type: 'station',
        onClick: () => {
          state.activeStandbyTileKey = 'discovery-station';
          updateStandbyActiveTile();
          closeStandbyLibraryModal();
          optimisticPlay();
          markWaitingForPlayback({ isStation: true, targetName: 'Станция открытий' });
          setUIBusy(true, 'Запуск «Станции открытий»...');
          send({
            action: 'play_hero_card',
            params: {
              index: 2,
              name: 'Станция открытий',
              artist: 'Новые треки под ваш вкус',
              id: '',
              url: '',
              type: 'station'
            }
          });
        }
      },
      {
        key: 'favorites-mix',
        visible: cfg.show_favorites_mix !== false,
        title: IS_EN ? 'Favorites Mix' : 'В моём вкусе',
        type: 'playlist',
        onClick: () => {
          state.activeStandbyTileKey = 'favorites-mix';
          updateStandbyActiveTile();
          closeStandbyLibraryModal();
          const mixes = state.personalMixes || [];
          const favMix = mixes.find(m => {
            const n = (m.name || '').toLowerCase();
            return n.includes('в моём вкусе') || n.includes('в моем вкусе') || n.includes('favorites') || n.includes('essentials');
          });
          optimisticPlay();
          markWaitingForPlayback({ targetName: 'В моём вкусе' });
          setUIBusy(true, 'Запуск «В моём вкусе»...');
          send({
            action: 'play_playlist',
            params: {
              playlist: favMix ? favMix.name : 'В моём вкусе',
              id: favMix ? (favMix.id || '') : '',
              url: favMix ? (favMix.url || '') : '',
              shuffle: false
            }
          });
        }
      },
      {
        key: 'heavy-rotation',
        visible: cfg.show_heavy_rotation !== false,
        title: IS_EN ? 'Heavy Rotation' : 'Сейчас на повторе',
        type: 'playlist',
        onClick: () => {
          state.activeStandbyTileKey = 'heavy-rotation';
          updateStandbyActiveTile();
          closeStandbyLibraryModal();
          const mixes = state.personalMixes || [];
          const hrMix = mixes.find(m => {
            const n = (m.name || '').toLowerCase();
            return n.includes('повторе') || n.includes('heavy rotation');
          });
          optimisticPlay();
          markWaitingForPlayback({ targetName: 'Сейчас на повторе' });
          setUIBusy(true, 'Запуск «Сейчас на повторе»...');
          send({
            action: 'play_playlist',
            params: {
              playlist: hrMix ? hrMix.name : 'Сейчас на повторе',
              id: hrMix ? (hrMix.id || '') : '',
              url: hrMix ? (hrMix.url || '') : '',
              shuffle: false
            }
          });
        }
      }
    ].filter(item => item.visible);

    // 2. Filter Playlists according to cfg.playlists_mode ('all' | 'selected' | 'none')
    let filteredPlaylists = [];
    if (playlistsMode === 'none') {
      filteredPlaylists = [];
    } else if (playlistsMode === 'selected') {
      const selectedNames = Array.isArray(cfg.selected_playlist_names) ? cfg.selected_playlist_names : [];
      const seenPl = new Set();
      selectedNames.forEach(rawSel => {
        const cleanSel = String(rawSel || '').trim();
        const lowerSel = cleanSel.toLowerCase();
        if (!lowerSel || seenPl.has(lowerSel)) return;
        const found = rawPlaylists.find(pl => String(pl.name || '').trim().toLowerCase() === lowerSel);
        if (found) {
          seenPl.add(lowerSel);
          filteredPlaylists.push(found);
        } else if (rawPlaylists.length === 0 && cleanSel) {
          seenPl.add(lowerSel);
          filteredPlaylists.push({ name: cleanSel });
        }
      });
    } else {
      filteredPlaylists = rawPlaylists.filter(pl => {
        const lower = (pl.name || '').trim().toLowerCase();
        return lower !== 'в моём вкусе' && lower !== 'в моем вкусе' && lower !== 'сейчас на повторе';
      });
    }

    // 3. Filter Albums according to cfg.albums_mode ('recent' | 'selected' | 'none')
    let filteredAlbums = [];
    if (albumsMode === 'none') {
      filteredAlbums = [];
    } else if (albumsMode === 'selected') {
      const selAlbumObjs = Array.isArray(cfg.selected_albums) ? cfg.selected_albums : [];
      const selAlbumKeys = Array.isArray(cfg.selected_album_keys) ? cfg.selected_album_keys : [];
      const usedLibIndices = new Set();
      const seenOutKeys = new Set();

      const matchLibAlbum = (selItem) => {
        const selId = String((selItem && selItem.id) || '').trim();
        const selKeyRaw = String((selItem && selItem.key) || '').trim().toLowerCase();
        const selKeyNorm = selKeyRaw
          ? selKeyRaw.split('|').map(part => normalizeAlbumMatchText(part)).join('|')
          : '';
        const selName = (selItem && selItem.name) || '';
        const selArtist = (selItem && selItem.artist) || '';

        for (let i = 0; i < allLibAlbums.length; i++) {
          if (usedLibIndices.has(i)) continue;
          const cand = allLibAlbums[i];
          if (!cand) continue;
          const candId = String(cand.id || '').trim();
          const candKeyRaw = String(cand.key || '').trim().toLowerCase();
          const candNormKey = buildAlbumConfigMatchKey(cand.name, cand.artist);
          const candRawPair = `${String(cand.name || '').trim().toLowerCase()}|${String(cand.artist || '').trim().toLowerCase()}`;

          if (
            (selId && candId && selId === candId) ||
            (selKeyRaw && ((candKeyRaw && selKeyRaw === candKeyRaw) || selKeyRaw === candRawPair || selKeyNorm === candNormKey)) ||
            (selName && albumsMatchClient(cand.name, cand.artist, selName, selArtist))
          ) {
            usedLibIndices.add(i);
            return cand;
          }
        }
        return null;
      };

      selAlbumObjs.forEach(selObj => {
        if (!selObj || typeof selObj !== 'object') return;
        const matched = matchLibAlbum(selObj);
        if (matched) {
          const outK = buildAlbumConfigMatchKey(matched.name, matched.artist) || String(matched.id || '');
          if (!seenOutKeys.has(outK)) {
            seenOutKeys.add(outK);
            filteredAlbums.push(matched);
          }
        } else if (allLibAlbums.length === 0 && selObj.name) {
          const outK = buildAlbumConfigMatchKey(selObj.name, selObj.artist) || String(selObj.key || selObj.id || selObj.name);
          if (!seenOutKeys.has(outK)) {
            seenOutKeys.add(outK);
            filteredAlbums.push({
              id: selObj.id || '',
              name: selObj.name || '',
              artist: selObj.artist || '',
              artwork: selObj.artwork || selObj.artwork_url || '',
              track_count: selObj.track_count || 0
            });
          }
        }
      });

      selAlbumKeys.forEach(rawKey => {
        const keyStr = String(rawKey || '').trim();
        if (!keyStr) return;
        let parsedName = '';
        let parsedArtist = '';
        if (keyStr.includes('|')) {
          const parts = keyStr.split('|');
          parsedName = parts[0] || '';
          parsedArtist = parts.slice(1).join('|') || '';
        } else if (keyStr.includes('::')) {
          const parts = keyStr.split('::');
          parsedName = parts[0] || '';
          parsedArtist = parts.slice(1).join('::') || '';
        }
        const probe = { key: keyStr, id: (!parsedName ? keyStr : ''), name: parsedName, artist: parsedArtist };
        const matched = matchLibAlbum(probe);
        if (matched) {
          const outK = buildAlbumConfigMatchKey(matched.name, matched.artist) || String(matched.id || keyStr);
          if (!seenOutKeys.has(outK)) {
            seenOutKeys.add(outK);
            filteredAlbums.push(matched);
          }
        } else if (allLibAlbums.length === 0 && parsedName) {
          const outK = buildAlbumConfigMatchKey(parsedName, parsedArtist) || keyStr.toLowerCase();
          if (!seenOutKeys.has(outK)) {
            seenOutKeys.add(outK);
            filteredAlbums.push({
              id: '',
              name: parsedName,
              artist: parsedArtist,
              artwork: '',
              track_count: 0
            });
          }
        }
      });
    } else {
      filteredAlbums = allLibAlbums.slice(0, 24);
    }

    if (coreTiles.length === 0 && filteredPlaylists.length === 0 && filteredAlbums.length === 0) {
      grid.innerHTML = `<div class="empty-state">${escapeHtml(translateTextToEn('Все плашки скрыты в настройках Mac (Основные → ТВ-режим)'))}</div>`;
      return;
    }

    coreTiles.forEach(item => {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'standby-square-tile';
      btn.setAttribute('data-tile-key', item.key);
      btn.setAttribute('data-tile-name', item.title);
      btn.setAttribute('title', item.title);
      const plaqueHtml = getAnimatedPlaqueHtml({ title: item.title, type: item.type }) || '';
      btn.innerHTML = `${plaqueHtml}${playBadgeHtml}`;
      btn.addEventListener('click', item.onClick);
      grid.appendChild(btn);
    });

    // 2. Local Library Playlists (Large Square Tiles)
    filteredPlaylists.forEach(pl => {
      const plName = (pl.name || '').trim();
      if (!plName) return;

      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'standby-square-tile';
      const tileKey = `pl:${plName}`;
      btn.setAttribute('data-tile-key', tileKey);
      btn.setAttribute('data-tile-name', plName);
      btn.setAttribute('title', plName);

      const count = pl.track_count || pl.trackCount || 0;
      const countText = count > 0 ? `<span class="standby-tile-meta">${count} треков</span>` : '';
      const artUrl = appendDeviceIdToUrl(pl.artwork_url || pl.artworkUrl || `/api/artwork/playlist?name=${encodeURIComponent(plName)}`);
      btn.innerHTML = `
        <img class="standby-tile-cover" src="${escapeHtml(artUrl)}" alt="${escapeHtml(plName)}" loading="lazy" data-fallback-mode="next-flex">
        <div class="standby-tile-fallback" style="display:none;">
          <svg viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="currentColor" stroke-width="1.6">
            <path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>
          </svg>
        </div>
        <div class="standby-tile-scrim">
          <span class="standby-tile-title">${escapeHtml(plName)}</span>
          ${countText}
        </div>
        ${playBadgeHtml}
      `;

      btn.addEventListener('click', () => {
        state.activeStandbyTileKey = tileKey;
        updateStandbyActiveTile();
        closeStandbyLibraryModal();
        optimisticPlay();
        markWaitingForPlayback({ targetName: plName });
        setUIBusy(true, `Запуск «${plName}»...`);
        send({
          action: 'play_playlist',
          params: {
            playlist: plName,
            shuffle: false,
            is_local: true
          }
        });
      });

      grid.appendChild(btn);
    });

    // 3. User Library Albums (Filtered by tv_library_config)
    filteredAlbums.forEach(alb => {
      const albName = (alb.name || '').trim();
      if (!albName) return;
      const albArtist = (alb.artist || '').trim();
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'standby-square-tile';
      const tileKey = `alb:${alb.id || albName}`;
      btn.setAttribute('data-tile-key', tileKey);
      btn.setAttribute('data-tile-name', albName);
      btn.setAttribute('title', albArtist ? `${albName} — ${albArtist}` : albName);

      const count = alb.track_count || alb.trackCount || 0;
      const metaParts = [];
      if (albArtist) metaParts.push(albArtist);
      if (count > 0) metaParts.push(formatTracksCount(count));
      const metaText = metaParts.length > 0
        ? `<span class="standby-tile-meta">${escapeHtml(metaParts.join(' • '))}</span>`
        : '';
      const fallbackArt = `/api/artwork/search?name=${encodeURIComponent(albName)}&artist=${encodeURIComponent(albArtist)}&album=${encodeURIComponent(albName)}`;
      const rawArt = alb.artwork || alb.artwork_url || alb.artworkUrl || fallbackArt;
      const artUrl = appendDeviceIdToUrl(rawArt);

      btn.innerHTML = `
        <img class="standby-tile-cover" src="${escapeHtml(artUrl)}" alt="${escapeHtml(albName)}" loading="lazy" data-fallback-mode="next-flex">
        <div class="standby-tile-fallback" style="display:none;">
          <svg viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="currentColor" stroke-width="1.6">
            <circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="3"/>
          </svg>
        </div>
        <div class="standby-tile-scrim">
          <span class="standby-tile-title">${escapeHtml(albName)}</span>
          ${metaText}
        </div>
        ${playBadgeHtml}
      `;

      btn.addEventListener('click', () => {
        state.activeStandbyTileKey = tileKey;
        updateStandbyActiveTile();
        closeStandbyLibraryModal();
        optimisticPlay();
        markWaitingForPlayback({ targetName: albName });
        setUIBusy(true, `Запуск альбома «${albName}»...`);
        send({
          action: 'play_album',
          params: {
            id: alb.id || '',
            name: albName,
            artist: albArtist,
            shuffle: false
          }
        });
      });

      grid.appendChild(btn);
    });

    updateStandbyActiveTile();
    syncTrackLoadingIndicatorUI();
    syncMotionVideoPlaybackState();
    ScreenWakeLockManager.syncByPlaybackAndConnection();
    syncSpectralPolling();
    refreshAllTitleMarquees();
  }

  function updateWledSettingsUI(data) {
    if (!data) return;
    const enabled = Boolean(data.enabled);
    const ip = data.ip !== undefined ? data.ip : '';
    const mode = data.mode || 'ambilight';
    const isActive = enabled && Boolean(ip) && mode !== 'off';
    state.wledEnabled = enabled;
    state.wledActive = isActive;

    const modeSel = document.getElementById('wled-mode-select');
    const dot = document.getElementById('wled-status-dot');
    const sbWledBadge = document.getElementById('standby-wled-badge');
    const btnTop = document.getElementById('btn-top-settings');
    const btnMob = document.getElementById('mobile-btn-settings');
    const btnPl = document.getElementById('player-btn-settings');
    const btnSb = document.getElementById('standby-btn-wled-toggle');
    const popover = document.getElementById('top-settings-popover');

    if (modeSel) modeSel.value = mode;
    if (dot) dot.classList.toggle('active', isActive);
    if (sbWledBadge) sbWledBadge.classList.toggle('hidden', !isActive);

    // Hide all WLED buttons across Mobile, StandBy/TV, and Tablet/PC when WLED is disabled in AMR settings
    [btnTop, btnMob, btnPl, btnSb].forEach(b => {
      if (!b) return;
      b.classList.toggle('hidden', !enabled);
      b.classList.toggle('active', isActive);
    });

    if (!enabled && popover) {
      blurFocusedInContainer(popover);
      popover.classList.add('hidden');
      popover.setAttribute('aria-hidden', 'true');
    }
  }
