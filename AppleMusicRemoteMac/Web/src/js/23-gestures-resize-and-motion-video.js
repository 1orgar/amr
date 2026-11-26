  function setupMiniPlayerGestures() {
    const mini = dom.miniPlayer;
    if (!mini) return;

    let startX = 0;
    let startY = 0;
    let deltaX = 0;
    let deltaY = 0;
    let startTime = 0;
    let isTouch = false;

    mini.addEventListener('touchstart', (e) => {
      if (e.target.closest('button')) return;
      if (e.touches.length !== 1) return;
      const t = e.touches[0];
      startX = t.clientX;
      startY = t.clientY;
      deltaX = 0;
      deltaY = 0;
      startTime = Date.now();
      isTouch = true;
    }, { passive: true });

    mini.addEventListener('touchmove', (e) => {
      if (!isTouch || e.touches.length !== 1) return;
      const t = e.touches[0];
      deltaX = t.clientX - startX;
      deltaY = t.clientY - startY;
    }, { passive: true });

    const handleMiniEnd = (e) => {
      if (!isTouch) return;
      isTouch = false;
      const elapsed = Date.now() - startTime;
      const dist = Math.hypot(deltaX, deltaY);

      if (dist > 45) {
        if (Math.abs(deltaX) > Math.abs(deltaY)) {
          ignoreSyntheticClickUntil = Date.now() + 450;
          if (deltaX < -45) {
            // Swipe Left -> Next
            triggerHaptic('medium');
            sendThrottledTransport('next');
            return;
          } else if (deltaX > 45) {
            // Swipe Right -> Previous
            triggerHaptic('medium');
            sendThrottledTransport('previous');
            return;
          }
        } else if (deltaY < -45) {
          // Swipe Up -> Expand Now Playing
          expandNowPlaying();
          return;
        }
      }

      // Single tap without drag expands Now Playing
      if (dist < 10 && elapsed < 350 && !e.target.closest('button')) {
        expandNowPlaying();
      }
    };

    mini.addEventListener('touchend', handleMiniEnd);
    mini.addEventListener('touchcancel', () => { isTouch = false; });
  }

  // Desktop Navigation
  dom.desktopNavButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      triggerHaptic('light');
      const target = btn.dataset.target;
      switchDesktopTab(target);
    });
  });

  function switchDesktopTab(tabName, keepDetailOpen = false, opts = {}) {
    const skipFetch = Boolean(keepDetailOpen || (opts && opts.skipFetch));
    const preserveHomeDrilldown = Boolean(opts && opts.preserveHomeDrilldown);
    if (tabName !== 'search' && dom.searchInput && document.activeElement === dom.searchInput) {
      dom.searchInput.blur();
    }
    state.desktopActiveTab = tabName;

    dom.desktopNavButtons.forEach(b => {
      b.classList.toggle('active', b.dataset.target === tabName);
    });

    const keepRecentOpen = Boolean(preserveHomeDrilldown && (tabName === 'home' || tabName === 'trends') && dom.recentDetailPane && !dom.recentDetailPane.classList.contains('hidden'));
    const keepGridOpen = Boolean(preserveHomeDrilldown && (tabName === 'home' || tabName === 'trends') && dom.sectionGridView && !dom.sectionGridView.classList.contains('hidden'));

    dom.viewQueue.classList.remove('active');
    if (dom.viewPlaylists) dom.viewPlaylists.classList.remove('active');
    dom.viewLibrary.classList.remove('active');
    if (dom.viewHome) dom.viewHome.classList.remove('active');
    if (dom.viewTrends) dom.viewTrends.classList.remove('active');
    if (dom.recentDetailPane && !keepRecentOpen) {
      dom.recentDetailPane.classList.remove('active');
      dom.recentDetailPane.classList.add('hidden');
    }
    if (dom.sectionGridView && !keepGridOpen) {
      dom.sectionGridView.classList.remove('active');
      dom.sectionGridView.classList.add('hidden');
    }
    dom.viewSearch.classList.remove('active');

    if (!keepDetailOpen && tabName !== 'library') {
      showLibraryBrowsePane();
    }

    if (tabName === 'home' || tabName === 'trends') {
      if (keepRecentOpen && dom.recentDetailPane) {
        dom.recentDetailPane.classList.add('active');
      } else if (keepGridOpen && dom.sectionGridView) {
        dom.sectionGridView.classList.add('active');
      } else if (dom.viewHome) {
        dom.viewHome.classList.add('active');
      } else if (dom.viewTrends) {
        dom.viewTrends.classList.add('active');
      }
      if (!skipFetch) loadTrends();
    } else if (tabName === 'playlists') {
      if (dom.viewPlaylists) dom.viewPlaylists.classList.add('active');
      if (!skipFetch) send({ action: 'get_playlists' });
    } else if (tabName === 'queue') {
      dom.viewQueue.classList.add('active');
      if (!skipFetch) send({ action: 'get_queue' });
    } else if (tabName === 'library') {
      dom.viewLibrary.classList.add('active');
      if (!keepDetailOpen) {
        showLibraryBrowsePane();
        switchLibrarySubtab(state.libraryTab || 'recent', false);
        if (!skipFetch && (!state.libraryAlbums || state.libraryAlbums.length === 0)) {
          send({ action: 'get_library_albums' });
        }
      }
    } else if (tabName === 'search') {
      dom.viewSearch.classList.add('active');
      if (!(opts && opts.fromResize) && dom.searchInput) {
        dom.searchInput.focus();
      }
    }
    syncKeyboardFocusClass();
  }

  // HTML escaping utility
  function escapeHtml(str) {
    if (!str) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  // Handle responsive layout changes on resize (debounced; ignores iOS Safari vertical scroll bar shifts)
  let lastViewportWidth = window.innerWidth;
  let wasMobileLayout = window.innerWidth < 768;
  let resizeDebounceTimer = null;

  function handleResize(opts = {}) {
    const forceInitial = Boolean(opts && opts.force);
    if (typeof syncStandaloneShellGeometry === 'function') {
      syncStandaloneShellGeometry();
    }
    const curWidth = window.innerWidth;
    if (typeof syncStandbyLandscapeBodyClass === 'function') {
      syncStandbyLandscapeBodyClass();
    }
    if (!forceInitial && Math.abs(curWidth - lastViewportWidth) < 2) {
      return;
    }
    lastViewportWidth = curWidth;

    syncStandbyAndMotionCoverUI();
    syncActiveMotionVideoTarget();

    const isMobileLayout = !isDesktopLayout();
    const isPlDetailOpen = Boolean(dom.playlistDetailPane && !dom.playlistDetailPane.classList.contains('hidden'));
    const isArtDetailOpen = Boolean(dom.libraryArtistDetailPane && !dom.libraryArtistDetailPane.classList.contains('hidden'));
    const isSectionGridOpen = Boolean(dom.sectionGridView && !dom.sectionGridView.classList.contains('hidden'));
    const isRecentDetailOpen = Boolean(dom.recentDetailPane && !dom.recentDetailPane.classList.contains('hidden'));
    const detailOpen = isPlDetailOpen || isArtDetailOpen || isSectionGridOpen || isRecentDetailOpen;
    const libDetailOpen = isPlDetailOpen || isArtDetailOpen;
    const homeDrilldownOpen = isSectionGridOpen || isRecentDetailOpen;

    if (forceInitial || isMobileLayout !== wasMobileLayout) {
      wasMobileLayout = isMobileLayout;
      if (!isMobileLayout) {
        const targetDesktopTab = libDetailOpen ? 'library' : (homeDrilldownOpen ? 'home' : state.desktopActiveTab);
        switchDesktopTab(targetDesktopTab, libDetailOpen, {
          fromResize: true,
          skipFetch: true,
          preserveHomeDrilldown: homeDrilldownOpen
        });
      } else {
        switchMobileView(state.activeView, true, homeDrilldownOpen);
      }
      if (detailOpen && (!isMobileLayout || state.activeView === 'view-library')) {
        if (libDetailOpen) {
          syncNavHighlightForDetailOrigin(isArtDetailOpen ? 'library-artists' : (state.detailReturnOrigin || 'library'));
        }
      }
    }
  }

  function scheduleDebouncedResize() {
    if (typeof syncStandaloneShellGeometry === 'function') {
      syncStandaloneShellGeometry();
    }
    if (resizeDebounceTimer) clearTimeout(resizeDebounceTimer);
    resizeDebounceTimer = setTimeout(() => {
      resizeDebounceTimer = null;
      handleResize();
    }, 150);
  }
  window.addEventListener('resize', scheduleDebouncedResize, { passive: true });
  window.addEventListener('orientationchange', () => {
    if (typeof syncStandaloneShellGeometry === 'function') {
      syncStandaloneShellGeometry();
    }
    if (resizeDebounceTimer) clearTimeout(resizeDebounceTimer);
    resizeDebounceTimer = setTimeout(() => {
      resizeDebounceTimer = null;
      lastViewportWidth = -1;
      handleResize();
    }, 150);
  }, { passive: true });

  // ==========================================================================
  // StandBy / TV Mode (Motion Covers) & WLED DDP Ambilight Controller
  // ==========================================================================
  let lastMotionQueryKey = '';
  let currentMotionVideoUrl = '';
  const motionArtworkClientCache = new Map();

  function buildMotionAlbumKey(artist, album) {
    const a = (artist || '').trim().toLowerCase();
    const al = (album || '').trim().toLowerCase();
    return al ? `album|${a}|${al}` : '';
  }

  function buildMotionTrackKey(track, artist, album) {
    return `track|${(track || '').trim().toLowerCase()}|${(artist || '').trim().toLowerCase()}|${(album || '').trim().toLowerCase()}`;
  }

  function unloadVideoElement(vid) {
    if (!vid) return;
    vid.onloadeddata = null;
    vid.onerror = null;
    vid.classList.remove('visible');
    vid.classList.add('hidden');
    try {
      vid.pause();
    } catch (_) {}
    if (vid.hasAttribute('src') || vid.currentSrc) {
      vid.removeAttribute('src');
      try {
        vid.load();
      } catch (_) {}
    }
  }

  function isMotionVideoPlaybackAllowed() {
    return Boolean(state.connected && state.playerState === 'playing');
  }

  function syncMotionVideoPlaybackState() {
    const allowPlay = isMotionVideoPlaybackAllowed();
    const tvActive = isStandbyOrLandscapeVisible();
    const activeVid = document.getElementById(tvActive ? 'standby-motion-video' : 'player-motion-video');
    const inactiveVid = document.getElementById(tvActive ? 'player-motion-video' : 'standby-motion-video');
    if (inactiveVid && !inactiveVid.paused) {
      try { inactiveVid.pause(); } catch (_) {}
    }
    if (!activeVid || !activeVid.getAttribute('src') || !activeVid.classList.contains('visible')) return;
    if (allowPlay) {
      if (activeVid.paused) {
        activeVid.play().catch(() => {});
      }
    } else if (!activeVid.paused) {
      try { activeVid.pause(); } catch (_) {}
    }
  }

  function bindAndPlayMotionVideoElement(vid, url) {
    if (!vid || !url) return;
    if (vid.getAttribute('src') === url && vid.classList.contains('visible')) {
      syncMotionVideoPlaybackState();
      return;
    }
    vid.classList.remove('hidden');
    vid.muted = true;
    vid.loop = true;
    vid.playsInline = true;
    vid.onloadeddata = () => {
      vid.classList.add('visible');
      if (isMotionVideoPlaybackAllowed()) {
        vid.play().catch(() => {});
      } else {
        try { vid.pause(); } catch (_) {}
      }
      if (ScreenWakeLockManager.isActive) {
        ScreenWakeLockManager.syncFallbackVideoState();
      }
    };
    vid.onerror = () => {
      unloadVideoElement(vid);
      const sbBadge = document.getElementById('standby-motion-badge');
      if (sbBadge) sbBadge.classList.add('hidden');
      if (ScreenWakeLockManager.isActive) {
        ScreenWakeLockManager.syncFallbackVideoState();
      }
    };
    vid.src = url;
  }

  function syncActiveMotionVideoTarget() {
    const pVid = document.getElementById('player-motion-video');
    const sbVid = document.getElementById('standby-motion-video');
    const sbBadge = document.getElementById('standby-motion-badge');
    if (!currentMotionVideoUrl) {
      unloadVideoElement(pVid);
      unloadVideoElement(sbVid);
      if (sbBadge) sbBadge.classList.add('hidden');
      return;
    }
    const tvActive = isStandbyOrLandscapeVisible();
    if (tvActive) {
      unloadVideoElement(pVid);
      bindAndPlayMotionVideoElement(sbVid, currentMotionVideoUrl);
    } else {
      unloadVideoElement(sbVid);
      bindAndPlayMotionVideoElement(pVid, currentMotionVideoUrl);
    }
    if (sbBadge) sbBadge.classList.remove('hidden');
  }

  function hideMotionVideos() {
    const pVid = document.getElementById('player-motion-video');
    const sbVid = document.getElementById('standby-motion-video');
    const sbBadge = document.getElementById('standby-motion-badge');
    unloadVideoElement(pVid);
    unloadVideoElement(sbVid);
    if (sbBadge) sbBadge.classList.add('hidden');
    currentMotionVideoUrl = '';
    if (ScreenWakeLockManager.isActive) {
      ScreenWakeLockManager.syncFallbackVideoState();
    }
  }

  function applyMotionVideoUrl(url) {
    if (!url) {
      hideMotionVideos();
      return;
    }
    url = appendDeviceIdToUrl(url);
    if (currentMotionVideoUrl === url) {
      syncActiveMotionVideoTarget();
      return;
    }
    currentMotionVideoUrl = url;
    syncActiveMotionVideoTarget();
  }

  function setBoundedMapValue(map, key, val, maxSize = 200) {
    if (!key) return;
    if (map.has(key)) {
      map.delete(key);
    }
    map.set(key, val);
    while (map.size > maxSize) {
      const oldestKey = map.keys().next().value;
      if (oldestKey === undefined) break;
      map.delete(oldestKey);
    }
  }

  function applyMotionArtwork(data) {
    if (!data) return;
    const url = (data.motion_url || '').trim();
    const respTrack = data.track || '';
    const respArtist = data.artist || '';
    const respAlbum = data.album || '';

    const albKey = buildMotionAlbumKey(respArtist, respAlbum);
    const trkKey = buildMotionTrackKey(respTrack, respArtist, respAlbum);
    if (albKey) setBoundedMapValue(motionArtworkClientCache, albKey, url, 200);
    if (trkKey) setBoundedMapValue(motionArtworkClientCache, trkKey, url, 200);

    const t = state.track;
    if (!t) {
      hideMotionVideos();
      return;
    }
    // Ensure response still matches current track or album
    const sameTrack = respTrack && t.name && respTrack.toLowerCase() === t.name.toLowerCase();
    const sameAlbum = respAlbum && t.album && respAlbum.toLowerCase() === t.album.toLowerCase();
    if (!sameTrack && !sameAlbum) {
      return;
    }
    applyMotionVideoUrl(url);
  }

  function syncStandbyAndMotionCoverUI() {
    const isPlaying = state.playerState === 'playing';
    const t = state.track;

    const sbTitle = document.getElementById('standby-title');
    const sbArtist = document.getElementById('standby-artist');
    const sbAlbum = document.getElementById('standby-album');
    const sbArt = document.getElementById('standby-artwork');
    const sbDac = document.getElementById('standby-dac-badge');
    const sbPlay = document.getElementById('standby-icon-play');
    const sbPause = document.getElementById('standby-icon-pause');
    const sbFav = document.getElementById('standby-btn-favorite');
    const sbShuffleBtn = document.getElementById('standby-btn-shuffle');
    const sbRepeatBtn = document.getElementById('standby-btn-repeat');
    const sbRepeatBadge = document.getElementById('standby-repeat-badge');
    const sbAiVibe = document.getElementById('standby-btn-ai-track-vibe');

    const isRadioMode = Boolean(state.isRadio);
    if (sbShuffleBtn) {
      sbShuffleBtn.disabled = isRadioMode;
      sbShuffleBtn.classList.toggle('disabled-control', isRadioMode);
      sbShuffleBtn.classList.toggle('active', !isRadioMode && Boolean(state.shuffle));
      sbShuffleBtn.title = isRadioMode
        ? (IS_EN ? 'Shuffle unavailable on Radio' : 'Перемешивание недоступно для радио')
        : (state.shuffle
          ? (IS_EN ? 'Shuffle: On' : 'Перемешать: Вкл')
          : (IS_EN ? 'Shuffle: Off' : 'Перемешать'));
    }
    const sbEffectiveRepeat = (isRadioMode && state.repeatMode === 'all') ? 'off' : state.repeatMode;
    if (sbRepeatBtn) {
      const isRepActive = sbEffectiveRepeat === 'one' || sbEffectiveRepeat === 'all';
      sbRepeatBtn.classList.toggle('active', isRepActive);
      sbRepeatBtn.title = sbEffectiveRepeat === 'one'
        ? (IS_EN ? 'Repeat: One Track (1)' : 'Повтор: Зациклен 1 трек')
        : (sbEffectiveRepeat === 'all'
          ? (IS_EN ? 'Repeat: Queue' : 'Повтор: Вся очередь')
          : (isRadioMode
            ? (IS_EN ? 'Repeat: Off (tap to repeat track)' : 'Повтор трека: Выкл')
            : (IS_EN ? 'Repeat: Off' : 'Режим повтора: Выкл')));
    }
    if (sbRepeatBadge) {
      sbRepeatBadge.classList.toggle('hidden', sbEffectiveRepeat !== 'one');
    }

    if (t && t.name) {
      const sbTitleText = t.name || 'Без названия';
      const sbArtistText = t.artist || 'Apple Music';
      const sbAlbumText = t.album || '';
      if (sbTitle && sbTitle.textContent !== sbTitleText) sbTitle.textContent = sbTitleText;
      if (sbArtist && sbArtist.textContent !== sbArtistText) sbArtist.textContent = sbArtistText;
      if (sbAlbum && sbAlbum.textContent !== sbAlbumText) sbAlbum.textContent = sbAlbumText;
      if (sbFav) sbFav.classList.toggle('active', Boolean(t.favorited));
      if (sbAiVibe) {
        sbAiVibe.disabled = false;
        sbAiVibe.classList.toggle('hidden', !state.aiCuratorEnabled);
      }
      const art = getArtworkSrc(t);
      if (sbArt && sbArt.dataset.targetSrc !== art) {
        delete sbArt.dataset.fallbackApplied;
        sbArt.dataset.fallbackIcon = 'apple-touch-icon.svg';
        sbArt.dataset.targetSrc = art;
        sbArt.src = art;
      }

      const mKey = `${t.name || ''}|${t.artist || ''}|${t.album || ''}`;
      if (mKey !== lastMotionQueryKey) {
        lastMotionQueryKey = mKey;
        const albKey = buildMotionAlbumKey(t.artist, t.album);
        const trkKey = buildMotionTrackKey(t.name, t.artist, t.album);

        if (albKey && motionArtworkClientCache.has(albKey)) {
          applyMotionVideoUrl(motionArtworkClientCache.get(albKey));
        } else if (motionArtworkClientCache.has(trkKey)) {
          applyMotionVideoUrl(motionArtworkClientCache.get(trkKey));
        } else {
          hideMotionVideos();
          send({
            action: 'get_motion_artwork',
            params: {
              track: t.name || '',
              artist: t.artist || '',
              album: t.album || ''
            }
          });
        }
      }
    } else {
      const sbNotPlaying = translateTextToEn('Не играет');
      if (sbTitle && sbTitle.textContent !== sbNotPlaying) sbTitle.textContent = sbNotPlaying;
      if (sbArtist && sbArtist.textContent !== 'Apple Music') sbArtist.textContent = 'Apple Music';
      if (sbAlbum && sbAlbum.textContent !== '') sbAlbum.textContent = '';
      if (sbFav) sbFav.classList.remove('active');
      if (sbAiVibe) {
        sbAiVibe.disabled = true;
        sbAiVibe.classList.toggle('hidden', !state.aiCuratorEnabled);
      }
      if (sbArt) {
        sbArt.dataset.targetSrc = 'apple-touch-icon.svg';
        sbArt.src = 'apple-touch-icon.svg';
      }
      if (lastMotionQueryKey !== '') {
        lastMotionQueryKey = '';
        hideMotionVideos();
      }
    }

    const sbDacText = document.getElementById('standby-dac-text');
    const drcTvPart = (state.lateNightDrcEnabled || (state.lateNightDrcMode && state.lateNightDrcMode !== 'off')) ? ' · 🌙' : '';
    if (sbDacText) {
      const devPart = state.audioDeviceName ? ` · ${state.audioDeviceName}` : '';
      sbDacText.textContent = `${formatDacPill(state.audioQuality)}${devPart}${drcTvPart}`;
    } else if (sbDac) {
      const devPart = state.audioDeviceName ? ` · ${state.audioDeviceName}` : '';
      sbDac.textContent = `${formatDacPill(state.audioQuality)}${devPart}${drcTvPart}`;
    }

    if (sbPlay && sbPause) {
      if (isPlaying) {
        sbPlay.classList.add('hidden');
        sbPause.classList.remove('hidden');
      } else {
        sbPlay.classList.remove('hidden');
        sbPause.classList.add('hidden');
      }
    }

    updateStandbyActiveTile();
    syncTrackLoadingIndicatorUI();
    syncMotionVideoPlaybackState();
    ScreenWakeLockManager.syncByPlaybackAndConnection();
    syncSpectralPolling();
    refreshAllTitleMarquees();
  }

  let lastStandbyTilesSignature = '';

  function handleTvLibraryConfig(data) {
    const rawCfg = (data && data.config && typeof data.config === 'object') ? data.config : data;
    if (!rawCfg || typeof rawCfg !== 'object') return;
    state.tvLibraryConfig = {
      ...state.tvLibraryConfig,
      ...rawCfg
    };
    state.tvLibraryConfigLoaded = true;
    lastStandbyTilesSignature = '';
    renderStandbyQuickTiles();
  }

  function openStandbyLibraryModal() {
    const modal = document.getElementById('standby-library-modal');
    if (!modal) return;
    closeStandbyAiModal();
    if (typeof closeStandbyQueueModal === 'function') closeStandbyQueueModal();
    if (!state.tvLibraryConfigLoaded) {
      send({ action: 'get_tv_library_config' });
    }
    renderStandbyQuickTiles();
    if (!state.playlists || state.playlists.length === 0) {
      send({ action: 'get_playlists' });
    }
    if (!state.libraryAlbums || state.libraryAlbums.length === 0) {
      send({ action: 'get_library_albums' });
    }
    modal.classList.remove('hidden');
    modal.setAttribute('aria-hidden', 'false');
    const p = document.getElementById('top-settings-popover');
    if (p) {
      blurFocusedInContainer(p);
      p.classList.add('hidden');
      p.setAttribute('aria-hidden', 'true');
    }
  }

  function closeStandbyLibraryModal() {
    const modal = document.getElementById('standby-library-modal');
    if (!modal) return;
    blurFocusedInContainer(modal);
    modal.classList.add('hidden');
    modal.setAttribute('aria-hidden', 'true');
  }

  // =========================================================================
  // Fullscreen StandBy / TV Mode AI Sonic Curator Tag Cloud (Infinite Scroll)
  // =========================================================================
  const AI_TV_THEMES = ['violet', 'indigo', 'cyan', 'rose', 'amber', 'emerald'];
  const AI_TV_SIZES = ['lg', 'xl', 'md', 'lg', 'xl', 'md'];

  let standbyAiGeneratedCount = 0;
  let standbyAiScrollBound = false;

  function buildNextStandbyAiTagItem() {
    const seq = standbyAiGeneratedCount++;
    const raw = (seq % 3 === 0)
      ? generateFreshAiPromptsBatch(1)[0]
      : synthesizeDynamicClientPrompt();
    const theme = AI_TV_THEMES[Math.floor(Math.random() * AI_TV_THEMES.length)];
    const size = AI_TV_SIZES[seq % AI_TV_SIZES.length];
    return {
      label: IS_EN ? (raw.labelEn || raw.label_en || raw.label) : (raw.labelRu || raw.label_ru || raw.label),
      prompt: IS_EN ? (raw.promptEn || raw.prompt_en || raw.prompt) : (raw.promptRu || raw.prompt_ru || raw.prompt),
      theme,
      size
    };
  }

  function triggerStandbyAiTagPlay(prompt, label) {
    if (!prompt) return;
    triggerHaptic('medium');
    closeStandbyAiModal();
    state.isAiCurating = true;
    state.pendingStandbyAiAutoPlay = true;
    state.searchQuery = prompt;
    state.aiCurateReqSeq = (state.aiCurateReqSeq || 0) + 1;
    state.lastAiCurateSentAt = Date.now();
    const reqId = state.aiCurateReqSeq;
    setUIBusy(true, (IS_EN ? 'AI Curating: ' : 'ИИ-подбор: ') + label.replace(/^[^\w\sа-яА-ЯёЁ]+\s*/, '') + '...');
    send({
      action: 'ai_curate',
      request_id: reqId,
      params: {
        prompt: prompt,
        country: getActiveStorefront(),
        auto_play: true,
        request_id: reqId
      }
    });
  }

  function formatStandbyAiTagHtml(rawLabel) {
    const str = String(rawLabel || '').trim();
    const emojiMatch = str.match(/^(\S+)\s+([\s\S]+)$/);
    let icon = '';
    let rest = str;
    if (emojiMatch && /^[^\wа-яА-ЯёЁ]+$/.test(emojiMatch[1])) {
      icon = emojiMatch[1];
      rest = emojiMatch[2].trim();
    }
    const iconSpan = icon ? `<span class="ai-tag-icon">${escapeHtml(icon)}</span>` : '';
    const parts = rest.split(/\s*•\s*/);
    if (parts.length >= 2) {
      const line1 = parts[0].trim();
      const line2 = parts.slice(1).join(' · ').trim();
      return `<span class="ai-tag-line-top">${iconSpan}<span class="ai-tag-main">${escapeHtml(line1)}</span></span><span class="ai-tag-sub">${escapeHtml(line2)}</span>`;
    }
    const words = rest.split(/\s+/);
    if (words.length >= 3) {
      const mid = Math.ceil(words.length / 2);
      const line1 = words.slice(0, mid).join(' ');
      const line2 = words.slice(mid).join(' ');
      return `<span class="ai-tag-line-top">${iconSpan}<span class="ai-tag-main">${escapeHtml(line1)}</span></span><span class="ai-tag-sub">${escapeHtml(line2)}</span>`;
    }
    return `<span class="ai-tag-line-top">${iconSpan}<span class="ai-tag-main">${escapeHtml(rest)}</span></span>`;
  }
