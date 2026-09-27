// Apple Music Remote - Touch Web App Engine

(function() {
  'use strict';

  // State
  const state = {
    playerState: 'stopped', // playing, paused, stopped
    volume: 50,
    isMuted: false,
    prevVolume: 50,
    shuffle: false,
    repeat: 'off', // off, one, all
    track: null,
    audioQuality: 'Lossless (ALAC 24-bit/48kHz)',
    isRadio: false,
    country: 'ru',
    serverTime: 0,
    syncPosition: 0,
    localTrackPosition: 0,
    lastPositionSyncTime: 0,
    currentTab: 'pageExplore',
    currentSource: 'cloud', // cloud, library
    activePlaylist: null,
    connected: false,
    isScrubbing: false,
    isVolumeDragging: false,
    actionSheetTrack: null
  };

  let positionTimer = null;
  let eventSource = null;
  let searchDebounceTimer = null;
  let topChartTracks = [];

  // DOM Elements
  const el = {
    // Header
    connectionStatus: document.getElementById('connectionStatus'),
    connectionText: document.getElementById('connectionText'),
    headerQrBtn: document.getElementById('headerQrBtn'),
    countrySelect: document.getElementById('countrySelect'),
    
    // Ambient
    ambientBg: document.getElementById('ambientBg'),
    
    // Now Playing
    trackArtwork: document.getElementById('trackArtwork'),
    artworkPlaceholder: document.getElementById('artworkPlaceholder'),
    artworkGlow: document.getElementById('artworkGlow'),
    playingIndicator: document.getElementById('playingIndicator'),
    trackTitle: document.getElementById('trackTitle'),
    trackArtist: document.getElementById('trackArtist'),
    trackAlbum: document.getElementById('trackAlbum'),
    losslessBadge: document.getElementById('losslessBadge'),
    audioQualityText: document.getElementById('audioQualityText'),
    btnFavorite: document.getElementById('btnFavorite'),
    
    progressBarBg: document.getElementById('progressBarBg'),
    progressBarFill: document.getElementById('progressBarFill'),
    progressThumb: document.getElementById('progressThumb'),
    timeElapsed: document.getElementById('timeElapsed'),
    timeRemaining: document.getElementById('timeRemaining'),
    
    btnShuffle: document.getElementById('btnShuffle'),
    btnPrev: document.getElementById('btnPrev'),
    btnPlayPause: document.getElementById('btnPlayPause'),
    iconPlay: document.getElementById('iconPlay'),
    iconPause: document.getElementById('iconPause'),
    btnNext: document.getElementById('btnNext'),
    btnQueue: document.getElementById('btnQueue'),

    // Volume
    btnMuteToggle: document.getElementById('btnMuteToggle'),
    volumeSliderTrack: document.getElementById('volumeSliderTrack'),
    volumeSliderFill: document.getElementById('volumeSliderFill'),
    volumeSliderThumb: document.getElementById('volumeSliderThumb'),
    
    // Mini Player
    miniPlayer: document.getElementById('miniPlayer'),
    miniProgressBar: document.getElementById('miniProgressBar'),
    miniArt: document.getElementById('miniArt'),
    miniTitle: document.getElementById('miniTitle'),
    miniArtist: document.getElementById('miniArtist'),
    miniBtnPrev: document.getElementById('miniBtnPrev'),
    miniBtnPlay: document.getElementById('miniBtnPlay'),
    miniBtnNext: document.getElementById('miniBtnNext'),
    miniIconPlay: document.getElementById('miniIconPlay'),
    miniIconPause: document.getElementById('miniIconPause'),
    
    // Explore
    storefrontBadge: document.getElementById('storefrontBadge'),
    exploreStations: document.getElementById('exploreStations'),
    exploreTopPicks: document.getElementById('exploreTopPicks'),
    exploreChartList: document.getElementById('exploreChartList'),
    btnPlayTopChart: document.getElementById('btnPlayTopChart'),
    btnShuffleTopChart: document.getElementById('btnShuffleTopChart'),
    exploreRecentlyPlayed: document.getElementById('exploreRecentlyPlayed'),
    explorePlaylistsForYou: document.getElementById('explorePlaylistsForYou'),
    exploreNewReleases: document.getElementById('exploreNewReleases'),
    
    // Library
    libraryNavList: document.getElementById('libraryNavList'),
    libraryContentArea: document.getElementById('libraryContentArea'),
    btnLibraryBack: document.getElementById('btnLibraryBack'),
    libraryContentTitle: document.getElementById('libraryContentTitle'),
    libraryContentList: document.getElementById('libraryContentList'),
    
    // Search
    searchMainArea: document.getElementById('searchMainArea'),
    searchInput: document.getElementById('searchInput'),
    btnClearSearch: document.getElementById('btnClearSearch'),
    searchPreState: document.getElementById('searchPreState'),
    searchResultsState: document.getElementById('searchResultsState'),
    searchList: document.getElementById('searchList'),
    albumDetailArea: document.getElementById('albumDetailArea'),
    btnAlbumBack: document.getElementById('btnAlbumBack'),
    albumDetailContent: document.getElementById('albumDetailContent'),
    
    // Queue Page
    queueCurrentPlaylist: document.getElementById('queueCurrentPlaylist'),
    btnClearQueue: document.getElementById('btnClearQueue'),
    queueNowCover: document.getElementById('queueNowCover'),
    queueNowName: document.getElementById('queueNowName'),
    queueNowArtist: document.getElementById('queueNowArtist'),
    queueNowAlbum: document.getElementById('queueNowAlbum'),
    queueUpcomingLabel: document.getElementById('queueUpcomingLabel'),
    queueFullList: document.getElementById('queueFullList'),
    
    // Action Sheet Modal
    actionSheetBackdrop: document.getElementById('actionSheetBackdrop'),
    sheetTrackCover: document.getElementById('sheetTrackCover'),
    sheetTrackTitle: document.getElementById('sheetTrackTitle'),
    sheetTrackArtist: document.getElementById('sheetTrackArtist'),
    btnSheetPlayNext: document.getElementById('btnSheetPlayNext'),
    btnSheetAddToQueue: document.getElementById('btnSheetAddToQueue'),
    btnSheetPlayRadio: document.getElementById('btnSheetPlayRadio'),
    btnSheetCancel: document.getElementById('btnSheetCancel'),

    // Modals & Toast
    qrModalBackdrop: document.getElementById('qrModalBackdrop'),
    btnQrModalClose: document.getElementById('btnQrModalClose'),
    qrUrlText: document.getElementById('qrUrlText'),
    toastContainer: document.getElementById('toastContainer'),
    
    // Navigation
    navItems: document.querySelectorAll('.nav-item'),
    pages: document.querySelectorAll('.page')
  };

  // =========================================================================
  // API Helpers
  // =========================================================================
  async function apiGet(endpoint) {
    try {
      const res = await fetch(endpoint);
      return await res.json();
    } catch (err) {
      console.error(`[API GET] ${endpoint} failed:`, err);
      return null;
    }
  }

  async function apiPost(endpoint, data = {}) {
    try {
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
      });
      return await res.json();
    } catch (err) {
      console.error(`[API POST] ${endpoint} failed:`, err);
      return null;
    }
  }

  function showToast(message) {
    if (!el.toastContainer) return;
    const toast = document.createElement('div');
    toast.className = 'toast';
    toast.textContent = message;
    el.toastContainer.appendChild(toast);
    setTimeout(() => {
      if (toast.parentNode) toast.parentNode.removeChild(toast);
    }, 3000);
  }

  function formatTime(seconds) {
    if (isNaN(seconds) || seconds < 0) return '0:00';
    const s = Math.floor(seconds);
    const mins = Math.floor(s / 60);
    const secs = s % 60;
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
  }

  // =========================================================================
  // Real-Time Synchronization (SSE + Polling Interpolation)
  // =========================================================================
  function initRealtimeSync() {
    if (eventSource) {
      eventSource.close();
    }

    eventSource = new EventSource('/api/events');

    eventSource.onopen = () => {
      setConnected(true);
    };

    eventSource.addEventListener('status', (e) => {
      try {
        const data = JSON.parse(e.data);
        updateState(data);
      } catch (err) {
        console.error('[SSE] JSON parse error:', err);
      }
    });

    eventSource.onerror = () => {
      setConnected(false);
      eventSource.close();
      setTimeout(initRealtimeSync, 3000);
    };

    // Position ticker timer
    if (positionTimer) clearInterval(positionTimer);
    positionTimer = setInterval(() => {
      if (state.playerState === 'playing' && state.track && !state.isScrubbing) {
        const now = Date.now() / 1000;
        const elapsed = Math.max(0, now - state.lastPositionSyncTime);
        const basePos = state.syncPosition || 0;
        const dur = (state.track && typeof state.track.duration === 'number') ? state.track.duration : 0;
        state.localTrackPosition = dur > 0 ? Math.min(dur, basePos + elapsed) : (basePos + elapsed);
        renderScrubber(state.localTrackPosition, dur);
      }
    }, 250);
  }

  function setConnected(isConnected) {
    state.connected = isConnected;
    if (isConnected) {
      el.connectionStatus.classList.remove('disconnected');
      el.connectionText.textContent = 'Онлайн';
    } else {
      el.connectionStatus.classList.add('disconnected');
      el.connectionText.textContent = 'Офлайн';
    }
  }

  const PLACEHOLDER_ARTWORK = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='200' height='200' viewBox='0 0 200 200'%3E%3Crect width='200' height='200' fill='%231a1a24'/%3E%3C/svg%3E";

  function updateState(data) {
    const prevTrackId = state.track ? (state.track.id || state.track.name) : null;

    state.playerState = data.player_state || 'stopped';
    state.volume = typeof data.volume === 'number' ? data.volume : 50;
    state.shuffle = Boolean(data.shuffle);
    state.repeat = data.repeat || 'off';
    state.track = data.track || null;
    state.audioQuality = data.audio_quality || (state.track ? 'Lossless (ALAC 24-bit/48kHz)' : 'Apple Lossless');
    state.isRadio = Boolean(data.is_radio);
    state.serverTime = data.server_time || Date.now() / 1000;
    
    // Server returns position at top level (data.position) or inside data.track.position
    const pos = (typeof data.position === 'number') 
      ? data.position 
      : (data.track && typeof data.track.position === 'number' ? data.track.position : 0);
    
    state.syncPosition = pos;
    state.localTrackPosition = pos;
    state.lastPositionSyncTime = Date.now() / 1000;

    renderPlayerUI();

    const newTrackId = state.track ? (state.track.id || state.track.name) : null;
    if (prevTrackId !== newTrackId && state.currentTab === 'pageQueue') {
      loadFullQueuePage();
    }
  }

  // =========================================================================
  // Render Player UI
  // =========================================================================
  function renderPlayerUI() {
    const isPlaying = state.playerState === 'playing';
    const isPaused = state.playerState === 'paused';
    const hasTrack = Boolean(state.track);

    // Play/Pause Icons
    if (isPlaying) {
      el.iconPlay.style.display = 'none';
      el.iconPause.style.display = 'block';
      el.miniIconPlay.style.display = 'none';
      el.miniIconPause.style.display = 'block';
      el.playingIndicator.classList.add('active');
    } else {
      el.iconPlay.style.display = 'block';
      el.iconPause.style.display = 'none';
      el.miniIconPlay.style.display = 'block';
      el.miniIconPause.style.display = 'none';
      el.playingIndicator.classList.remove('active');
    }

    // Shuffle & Repeat
    if (state.shuffle) {
      el.btnShuffle.classList.add('active');
    } else {
      el.btnShuffle.classList.remove('active');
    }

    // Lossless Quality Badge
    if (el.audioQualityText) {
      el.audioQualityText.textContent = state.audioQuality || 'Lossless (ALAC 24-bit/48kHz)';
    }

    // Volume Slider Rendering
    if (!state.isVolumeDragging && el.volumeSliderFill && el.volumeSliderThumb) {
      const vol = state.volume;
      el.volumeSliderFill.style.width = `${vol}%`;
      el.volumeSliderThumb.style.left = `${vol}%`;
    }

    // Track Metadata
    if (hasTrack) {
      el.trackTitle.textContent = state.track.name || 'Без названия';
      el.trackArtist.textContent = state.track.artist || 'Неизвестный исполнитель';
      el.trackAlbum.textContent = state.track.album || '';
      el.miniTitle.textContent = state.track.name || 'Без названия';
      el.miniArtist.textContent = state.track.artist || 'Apple Music';
      
      // Artwork
      let artUrl = state.track.artwork_url || ((state.track.has_artwork) 
        ? `/api/artwork/current?id=${state.track.id || ''}&name=${encodeURIComponent(state.track.name || '')}`
        : null);
      
      if (artUrl) {
        if (el.trackArtwork.getAttribute('data-loaded-art') !== artUrl) {
          el.trackArtwork.setAttribute('data-loaded-art', artUrl);
          el.trackArtwork.src = artUrl;
          el.miniArt.src = artUrl;
        }
        el.trackArtwork.style.display = 'block';
        el.artworkPlaceholder.style.display = 'none';
        el.miniArt.style.display = 'block';
        el.trackArtwork.onerror = () => {
          el.trackArtwork.style.display = 'none';
          el.artworkPlaceholder.style.display = 'flex';
          el.miniArt.style.display = 'none';
        };
      } else {
        el.trackArtwork.removeAttribute('data-loaded-art');
        el.trackArtwork.style.display = 'none';
        el.artworkPlaceholder.style.display = 'flex';
        el.miniArt.style.display = 'none';
      }

      // Favorite status
      if (state.track && state.track.favorited) {
        el.btnFavorite.classList.add('active');
      } else {
        el.btnFavorite.classList.remove('active');
      }

      if (!state.isScrubbing) {
        renderScrubber(state.localTrackPosition, state.track.duration);
      }
    } else {
      el.trackTitle.textContent = 'Ничего не играет';
      el.trackArtist.textContent = 'Apple Music на Mac';
      el.trackAlbum.textContent = '';
      el.miniTitle.textContent = 'Ничего не играет';
      el.miniArtist.textContent = 'Apple Music';
      el.btnFavorite.classList.remove('active');
      el.trackArtwork.removeAttribute('data-loaded-art');
      el.trackArtwork.style.display = 'none';
      el.artworkPlaceholder.style.display = 'flex';
      el.miniArt.style.display = 'none';
      renderScrubber(0, 0);
    }

    // Sync Queue Page Now Playing card if present
    if (el.queueNowName) {
      if (state.track && state.track.name) {
        el.queueNowName.textContent = state.track.name;
        el.queueNowArtist.textContent = state.track.artist || 'Apple Music';
        el.queueNowAlbum.textContent = state.track.album || '';
        if (state.track.artwork_url) {
          el.queueNowCover.src = state.track.artwork_url;
        } else if (state.track.has_artwork) {
          el.queueNowCover.src = `/api/artwork/current?id=${state.track.id || ''}`;
        }
      } else {
        el.queueNowName.textContent = 'Ничего не играет';
        el.queueNowArtist.textContent = 'Apple Music';
        el.queueNowAlbum.textContent = '';
      }
    }
  }

  function renderScrubber(pos, dur) {
    const duration = dur || 0;
    const position = Math.min(pos || 0, duration);
    const percent = duration > 0 ? (position / duration) * 100 : 0;
    
    el.progressBarFill.style.width = `${percent}%`;
    el.progressThumb.style.left = `${percent}%`;
    el.miniProgressBar.style.width = `${percent}%`;
    
    el.timeElapsed.textContent = formatTime(position);
    el.timeRemaining.textContent = duration > 0 ? `-${formatTime(Math.max(0, duration - position))}` : '0:00';
  }

  function setupControlListeners() {
    // Play/Pause
    el.btnPlayPause.addEventListener('click', async () => {
      await apiPost('/api/playpause');
    });
    el.miniBtnPlay.addEventListener('click', async (e) => {
      e.stopPropagation();
      await apiPost('/api/playpause');
    });

    // Step
    el.btnNext.addEventListener('click', async () => {
      await apiPost('/api/next');
    });
    el.btnPrev.addEventListener('click', async () => {
      await apiPost('/api/prev');
    });
    el.miniBtnNext?.addEventListener('click', async (e) => {
      e.stopPropagation();
      await apiPost('/api/next');
    });
    el.miniBtnPrev?.addEventListener('click', async (e) => {
      e.stopPropagation();
      await apiPost('/api/prev');
    });

    // Favorite / Star
    el.btnFavorite.addEventListener('click', async () => {
      if (!state.track || !state.track.name) return;
      const isFav = el.btnFavorite.classList.contains('active');
      if (isFav) {
        el.btnFavorite.classList.remove('active');
        showToast('Удалено из избранного');
      } else {
        el.btnFavorite.classList.add('active');
        showToast('Добавлено в избранное ⭐');
      }
      await apiPost('/api/favorite');
    });

    // Shuffle
    el.btnShuffle.addEventListener('click', async () => {
      const nextShuffle = !state.shuffle;
      state.shuffle = nextShuffle;
      renderPlayerUI();
      await apiPost('/api/shuffle', { enabled: nextShuffle });
    });

    // Volume Slider & Mute
    if (el.volumeSliderTrack) {
      function handleVolumeMove(e) {
        const rect = el.volumeSliderTrack.getBoundingClientRect();
        const clientX = e.touches ? e.touches[0].clientX : e.clientX;
        const pos = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
        const targetVol = Math.round(pos * 100);
        state.volume = targetVol;
        el.volumeSliderFill.style.width = `${targetVol}%`;
        el.volumeSliderThumb.style.left = `${targetVol}%`;
        return targetVol;
      }

      el.volumeSliderTrack.addEventListener('pointerdown', (e) => {
        state.isVolumeDragging = true;
        const targetVol = handleVolumeMove(e);

        function onPointerMove(moveEvent) {
          handleVolumeMove(moveEvent);
        }

        async function onPointerUp(upEvent) {
          window.removeEventListener('pointermove', onPointerMove);
          window.removeEventListener('pointerup', onPointerUp);
          const finalVol = handleVolumeMove(upEvent);
          state.isVolumeDragging = false;
          await apiPost('/api/volume', { volume: finalVol });
        }

        window.addEventListener('pointermove', onPointerMove);
        window.addEventListener('pointerup', onPointerUp);
      });
    }

    if (el.btnMuteToggle) {
      el.btnMuteToggle.addEventListener('click', async () => {
        if (state.isMuted) {
          state.isMuted = false;
          state.volume = state.prevVolume || 50;
          await apiPost('/api/volume', { volume: state.volume });
        } else {
          state.isMuted = true;
          state.prevVolume = state.volume;
          state.volume = 0;
          await apiPost('/api/volume', { volume: 0 });
        }
        renderPlayerUI();
      });
    }

    // Country Storefront Selector
    if (el.countrySelect) {
      el.countrySelect.addEventListener('change', async (e) => {
        const country = e.target.value;
        state.country = country;
        await apiPost('/api/settings', { country });
        showToast(`Каталог переключен: ${country.toUpperCase()}`);
        loadExploreData(true);
      });
    }

    // Queue button in player -> Navigate to dedicated Queue tab
    if (el.btnQueue) {
      el.btnQueue.addEventListener('click', () => {
        switchTab('pageQueue');
      });
    }

    // Scrubber Dragging & Touch
    function handleScrubberMove(e) {
      if (!state.track || !state.track.duration) return;
      const rect = el.progressBarBg.getBoundingClientRect();
      const clientX = e.touches ? e.touches[0].clientX : e.clientX;
      const pos = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
      const targetSec = pos * state.track.duration;
      renderScrubber(targetSec, state.track.duration);
      return targetSec;
    }

    el.progressBarBg.addEventListener('pointerdown', (e) => {
      state.isScrubbing = true;
      const targetSec = handleScrubberMove(e);

      function onPointerMove(moveEvent) {
        handleScrubberMove(moveEvent);
      }

      async function onPointerUp(upEvent) {
        window.removeEventListener('pointermove', onPointerMove);
        window.removeEventListener('pointerup', onPointerUp);
        const finalSec = handleScrubberMove(upEvent);
        state.isScrubbing = false;
        if (finalSec !== undefined) {
          state.syncPosition = finalSec;
          state.localTrackPosition = finalSec;
          state.lastPositionSyncTime = Date.now() / 1000;
          renderScrubber(finalSec, state.track ? state.track.duration : 0);
          await apiPost('/api/seek', { position: finalSec });
        }
      }

      window.addEventListener('pointermove', onPointerMove);
      window.addEventListener('pointerup', onPointerUp);
    });

    // Mini Player Click -> Return to Now Playing
    el.miniPlayer.addEventListener('click', () => {
      switchTab('pageNowPlaying');
    });
  }

  // =========================================================================
  // Track Action Sheet Modal (iOS Style)
  // =========================================================================
  function openActionSheet(track) {
    if (!track) return;
    state.actionSheetTrack = track;
    el.sheetTrackTitle.textContent = track.name || 'Без названия';
    el.sheetTrackArtist.textContent = track.artist || 'Apple Music';
    el.sheetTrackCover.src = track.artwork || PLACEHOLDER_ARTWORK;
    el.actionSheetBackdrop.style.display = 'flex';
  }

  function closeActionSheet() {
    el.actionSheetBackdrop.style.display = 'none';
    state.actionSheetTrack = null;
  }

  function setupActionSheetListeners() {
    el.btnSheetCancel.addEventListener('click', closeActionSheet);
    el.actionSheetBackdrop.addEventListener('click', (e) => {
      if (e.target === el.actionSheetBackdrop) closeActionSheet();
    });

    el.btnSheetPlayNext.addEventListener('click', async () => {
      if (!state.actionSheetTrack) return;
      const track = state.actionSheetTrack;
      showToast(`Играть следующим: ${track.name}`);
      closeActionSheet();
      await apiPost('/api/queue/play_next', { track });
    });

    el.btnSheetAddToQueue.addEventListener('click', async () => {
      if (!state.actionSheetTrack) return;
      const track = state.actionSheetTrack;
      showToast(`Добавлено в очередь: ${track.name}`);
      closeActionSheet();
      await apiPost('/api/queue/add', { track });
    });

    el.btnSheetPlayRadio.addEventListener('click', async () => {
      if (!state.actionSheetTrack) return;
      const track = state.actionSheetTrack;
      showToast(`Запуск станции: ${track.artist || track.name}`);
      closeActionSheet();
      const stationUrl = `https://music.apple.com/station/ra.u-${track.id || ''}`;
      await apiPost('/api/play/station', {
        url: stationUrl,
        name: `Радио: ${track.name}`
      });
    });
  }

  // =========================================================================
  // Dedicated Queue Page Logic
  // =========================================================================
  async function loadFullQueuePage() {
    if (!el.queueFullList) return;
    el.queueFullList.innerHTML = '<div class="skeleton-row" style="margin-bottom:8px;"></div><div class="skeleton-row" style="margin-bottom:8px;"></div><div class="skeleton-row"></div>';
    
    // Update Currently Playing Card
    if (state.track && state.track.name) {
      el.queueNowName.textContent = state.track.name;
      el.queueNowArtist.textContent = state.track.artist || 'Apple Music';
      el.queueNowAlbum.textContent = state.track.album || '';
      if (state.track.artwork_url) {
        el.queueNowCover.src = state.track.artwork_url;
      } else if (state.track.has_artwork) {
        el.queueNowCover.src = `/api/artwork/current?id=${state.track.id || ''}`;
      } else {
        el.queueNowCover.src = PLACEHOLDER_ARTWORK;
      }
    } else {
      el.queueNowName.textContent = 'Ничего не играет';
      el.queueNowArtist.textContent = 'Apple Music';
      el.queueNowAlbum.textContent = '';
      el.queueNowCover.src = PLACEHOLDER_ARTWORK;
    }

    const res = await apiGet('/api/player/queue');
    if (!res) {
      el.queueFullList.innerHTML = '<p class="search-empty-state">Не удалось загрузить очередь</p>';
      return;
    }

    const playlistName = res.playlist || 'Музыка';
    if (el.queueCurrentPlaylist) {
      el.queueCurrentPlaylist.textContent = `Плейлист: «${playlistName}» • ${res.total_tracks || 0} треков`;
    }

    const tracks = res.upcoming_tracks || [];
    if (tracks.length === 0) {
      el.queueFullList.innerHTML = '<p class="search-empty-state" style="padding: 24px 0;">Очередь пуста или трек последний в плейлисте</p>';
      return;
    }

    el.queueFullList.innerHTML = tracks.map((t, idx) => `
      <div class="queue-card-tile" data-id="${t.id}" data-index="${t.index}" data-upcoming-idx="${idx}">
        <img class="queue-card-cover" src="${t.artwork || ''}" onerror="this.src='${PLACEHOLDER_ARTWORK}'" loading="lazy">
        <div class="queue-card-info">
          <div class="queue-card-name">${escapeHtml(t.name)}</div>
          <div class="queue-card-sub">${escapeHtml(t.artist)}${t.album ? ` • ${escapeHtml(t.album)}` : ''}</div>
        </div>
        <button class="queue-item-remove-btn" title="Удалить из очереди" aria-label="Удалить">✕</button>
      </div>
    `).join('');

    // Click track to jump
    el.queueFullList.querySelectorAll('.queue-card-tile').forEach(card => {
      card.addEventListener('click', async (e) => {
        if (e.target.classList.contains('queue-item-remove-btn')) return;
        const rawIdx = card.getAttribute('data-index');
        const tIndex = rawIdx ? (parseInt(rawIdx, 10) - 1) : 0;
        const tName = card.querySelector('.queue-card-name')?.textContent || '';
        showToast(`Воспроизведение: ${tName}`);
        await apiPost('/api/queue/play_index', { index: tIndex });
        setTimeout(() => loadFullQueuePage(), 500);
      });

      // Remove single track from queue
      card.querySelector('.queue-item-remove-btn')?.addEventListener('click', async (e) => {
        e.stopPropagation();
        const rawIdx = card.getAttribute('data-index');
        const tIndex = rawIdx ? (parseInt(rawIdx, 10) - 1) : 0;
        const tName = card.querySelector('.queue-card-name')?.textContent || '';
        showToast(`Удалено: ${tName}`);
        await apiPost('/api/queue/remove', { index: tIndex });
        loadFullQueuePage();
      });
    });
  }

  function setupQueueListeners() {
    el.btnClearQueue?.addEventListener('click', async () => {
      showToast('Очередь очищена');
      await apiPost('/api/queue/clear');
      loadFullQueuePage();
    });
  }

  // =========================================================================
  // Navigation & Tabs
  // =========================================================================
  function setupNavigation() {
    el.navItems.forEach(btn => {
      btn.addEventListener('click', () => {
        const targetTab = btn.getAttribute('data-tab');
        switchTab(targetTab);
      });
    });
  }

  function switchTab(tabId) {
    state.currentTab = tabId;

    el.navItems.forEach(btn => {
      if (btn.getAttribute('data-tab') === tabId) {
        btn.classList.add('active');
      } else {
        btn.classList.remove('active');
      }
    });

    el.pages.forEach(page => {
      if (page.id === tabId) {
        page.classList.add('active');
      } else {
        page.classList.remove('active');
      }
    });

    // Mini player visibility
    if (tabId === 'pageNowPlaying') {
      el.miniPlayer.style.display = 'none';
    } else {
      el.miniPlayer.style.display = 'block';
    }

    // Lazy load tab data
    if (tabId === 'pageExplore') {
      loadExploreData();
    } else if (tabId === 'pageQueue') {
      loadFullQueuePage();
    }
  }

  // =========================================================================
  // TAB 2: Explore / Главное & Радио (Apple Music Cloud)
  // =========================================================================
  let lastExploreData = null;
  let exploreLoaded = false;

  async function loadExploreData(force = false) {
    if (exploreLoaded && !force) return;

    const res = await apiGet(`/api/explore?country=${encodeURIComponent(state.country || 'ru')}`);
    if (!res || !res.data) return;
    const data = res.data;
    exploreLoaded = true;
    lastExploreData = data;

    el.storefrontBadge.textContent = (state.country || 'ru').toUpperCase();

    // 1. Stations For You (Станции для вас)
    if (el.exploreStations) {
      const stations = data.stations || [];
      if (stations.length === 0) {
        el.exploreStations.innerHTML = '<div style="color:var(--text-tertiary);font-size:13px;padding:10px 0;">Нет доступных станций</div>';
      } else {
        el.exploreStations.innerHTML = stations.map(st => `
          <div class="station-card" data-url="${escapeHtml(st.url)}" data-name="${escapeHtml(st.name)}">
            <div class="station-cover-wrapper">
              <img class="station-cover-img" src="${st.artwork || ''}" onerror="this.src='${PLACEHOLDER_ARTWORK}'" loading="lazy">
              ${st.is_live ? '<span class="station-live-badge">LIVE</span>' : ''}
              <div class="station-play-icon">
                <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>
              </div>
            </div>
            <div class="station-title">${escapeHtml(st.name)}</div>
            <div class="station-subtitle">${escapeHtml(st.subtitle || 'Apple Music')}</div>
          </div>
        `).join('');

        el.exploreStations.querySelectorAll('.station-card').forEach(card => {
          card.addEventListener('click', async () => {
            const url = card.getAttribute('data-url');
            const name = card.getAttribute('data-name');
            showToast(`Запуск радио: ${name}`);
            await apiPost('/api/play/station', { url, name });
          });
        });
      }
    }

    // Helper to render horizontal cards
    const renderCards = (container, items, isPlaylist = false) => {
      if (!container) return;
      if (!items || items.length === 0) {
        container.innerHTML = '<div style="color:var(--text-tertiary);font-size:13px;padding:10px 0;">Нет данных</div>';
        return;
      }
      container.innerHTML = items.map(item => `
        <div class="hot-pick-card" style="width: 140px; cursor: pointer;" data-id="${item.id || ''}" data-name="${escapeHtml(item.name || '')}" data-is-playlist="${isPlaylist ? '1' : '0'}">
          <img class="card-cover" src="${item.artwork || ''}" onerror="this.src='${PLACEHOLDER_ARTWORK}'" loading="lazy">
          <div class="card-title">${escapeHtml(item.name || '')}</div>
          <div class="card-subtitle">${escapeHtml(isPlaylist ? `${item.track_count || 0} треков` : (item.artist || ''))}</div>
        </div>
      `).join('');
      
      container.querySelectorAll('.hot-pick-card').forEach(card => {
        card.addEventListener('click', async () => {
          const isPl = card.getAttribute('data-is-playlist') === '1';
          const name = card.getAttribute('data-name');
          const id = card.getAttribute('data-id');
          
          if (isPl) {
            showToast(`Воспроизведение: ${name}`);
            state.shuffle = false;
            renderPlayerUI();
            await apiPost('/api/play/playlist', { playlist: name, shuffle: false });
          } else if (id) {
            showToast(`Воспроизведение: ${name}`);
            await apiPost('/api/play/playlist', { playlist: 'Музыка', track_id: parseInt(id, 10), shuffle: false });
          }
        });
      });
    };

    // 2. Top Picks (Подборка лучшего для вас)
    if (data.top_picks) {
      renderCards(el.exploreTopPicks, data.top_picks);
    }

    // 3. Top 50 Songs Chart (Топ треков)
    const chartSongs = data.top_songs || (data.top_picks ? data.top_picks.filter(p => !p.track_count) : []);
    topChartTracks = chartSongs;
    if (el.exploreChartList && chartSongs.length > 0) {
      el.exploreChartList.innerHTML = chartSongs.slice(0, 50).map((s, idx) => `
        <div class="chart-item" data-index="${idx}" data-id="${s.id || ''}" data-name="${escapeHtml(s.name)}" data-artist="${escapeHtml(s.artist || '')}" data-artwork="${escapeHtml(s.artwork || '')}">
          <span class="track-row-idx" style="width:24px; font-weight:700; color:var(--text-tertiary);">${idx + 1}</span>
          <img class="chart-art" src="${s.artwork || ''}" alt="Art" loading="lazy" onerror="this.src='${PLACEHOLDER_ARTWORK}'">
          <div class="chart-info">
            <div class="chart-title">${escapeHtml(s.name)}</div>
            <div class="chart-artist">${escapeHtml(s.artist || '')}${s.album ? ` • ${escapeHtml(s.album)}` : ''}</div>
          </div>
          <button class="track-more-btn" title="Действия с треком" aria-label="Меню">⋯</button>
        </div>
      `).join('');

      el.exploreChartList.querySelectorAll('.chart-item').forEach(item => {
        item.addEventListener('click', async (e) => {
          if (e.target.classList.contains('track-more-btn')) {
            e.stopPropagation();
            const idx = parseInt(item.getAttribute('data-index'), 10) || 0;
            openActionSheet(chartSongs[idx]);
            return;
          }
          const idx = parseInt(item.getAttribute('data-index'), 10) || 0;
          const name = item.getAttribute('data-name');
          showToast(`Воспроизведение: ${name}`);
          await apiPost('/api/play/custom_queue', {
            tracks: chartSongs,
            shuffle: false,
            start_index: idx,
            queue_name: 'Топ-50 чарт'
          });
        });
      });
    }

    // 4. Recently Played (Недавно слушали)
    if (data.recently_played) {
      renderCards(el.exploreRecentlyPlayed, data.recently_played);
    }

    // 5. Playlists For You (Плейлисты специально для вас)
    if (data.playlists_for_you) {
      renderCards(el.explorePlaylistsForYou, data.playlists_for_you, true);
    }

    // 6. New Releases / Popular Albums
    if (data.new_releases) {
      renderCards(el.exploreNewReleases, data.new_releases);
    }
  }

  // Hook Top Chart Play / Shuffle buttons
  function setupExploreListeners() {
    el.btnPlayTopChart?.addEventListener('click', async () => {
      if (topChartTracks.length === 0) return;
      showToast('Воспроизведение: Топ-50');
      await apiPost('/api/play/custom_queue', {
        tracks: topChartTracks,
        shuffle: false,
        start_index: 0,
        queue_name: 'Топ-50 чарт'
      });
    });

    el.btnShuffleTopChart?.addEventListener('click', async () => {
      if (topChartTracks.length === 0) return;
      showToast('Перемешать: Топ-50');
      await apiPost('/api/play/custom_queue', {
        tracks: topChartTracks,
        shuffle: true,
        start_index: 0,
        queue_name: 'Топ-50 чарт'
      });
    });
  }

  async function playCloudUrl(url, name, artist, id) {
    if (!url && !name && !id) return;
    showToast(name ? `Воспроизведение: ${name}` : 'Запуск в Apple Music на Mac...');
    await apiPost('/api/play/cloud', { url, name, artist, id });
  }

  // =========================================================================
  // TAB 3: Library (Медиатека)
  // =========================================================================
  async function loadLibraryCategory(category) {
    el.libraryNavList.style.display = 'none';
    el.libraryContentArea.style.display = 'flex';
    el.libraryContentArea.style.flexDirection = 'column';
    el.libraryContentList.innerHTML = '<div class="skeleton-row"></div><div class="skeleton-row"></div>';

    if (category === 'playlists') {
      el.libraryContentTitle.textContent = 'Плейлисты';
      const res = await apiGet('/api/playlists');
      if (res && res.playlists) {
        el.libraryContentList.innerHTML = res.playlists.map(p => `
          <div class="playlist-card" data-name="${escapeHtml(p.name)}" data-count="${p.track_count}" style="flex-direction: row; align-items: center; gap: 12px; margin-bottom: 8px;">
            <div class="playlist-card-cover" style="width: 48px; height: 48px; border-radius: 8px; margin: 0; box-shadow: none;">
              <svg viewBox="0 0 24 24" width="24" height="24" fill="currentColor"><path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z"/></svg>
            </div>
            <div style="flex: 1; min-width: 0;">
              <div class="playlist-card-title" style="font-size: 16px;">${escapeHtml(p.name)}</div>
              <div class="playlist-card-count" style="font-size: 13px;">${p.track_count} треков</div>
            </div>
          </div>
        `).join('');

        el.libraryContentList.querySelectorAll('.playlist-card').forEach(card => {
          card.addEventListener('click', () => {
            const pName = card.getAttribute('data-name');
            openPlaylistDetails(pName, card.getAttribute('data-count'));
          });
        });
      }
    } else if (category === 'artists') {
      el.libraryContentTitle.textContent = 'Артисты';
      const res = await apiGet('/api/library/artists');
      if (res && res.artists) {
        el.libraryContentList.innerHTML = res.artists.map(a => `
          <div class="artist-row">
            <div class="artist-avatar">
              <svg viewBox="0 0 24 24" width="24" height="24" fill="currentColor"><path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>
            </div>
            <div class="artist-name">${escapeHtml(a.name)}</div>
          </div>
        `).join('');
      }
    } else if (category === 'songs') {
      el.libraryContentTitle.textContent = 'Песни';
      const res = await apiGet('/api/library/songs');
      if (res && res.songs) {
        let songsHtml = `
          <div class="playlist-actions-row">
            <button class="playlist-action-btn btn-play-all" id="btnPlayAllSongs">
              <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>
              <span>Воспроизвести</span>
            </button>
            <button class="playlist-action-btn btn-shuffle-all" id="btnShuffleAllSongs">
              <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M16 3h5v5M4 20l6.5-6.5M21 3l-6.5 6.5M21 21v-5h-5M4 4l17 17"/></svg>
              <span>Перемешать</span>
            </button>
          </div>
        `;
        
        songsHtml += res.songs.map(t => `
          <div class="track-row" data-id="${t.id}" data-index="${t.index}">
            <div class="track-row-info" style="margin-left: 0;">
              <div class="track-row-name">${escapeHtml(t.name)}</div>
              <div class="track-row-sub">${escapeHtml(t.artist)} • ${escapeHtml(t.album)}</div>
            </div>
            <button class="track-more-btn" title="Действия с треком" aria-label="Меню">⋯</button>
          </div>
        `).join('');

        el.libraryContentList.innerHTML = songsHtml;

        document.getElementById('btnPlayAllSongs')?.addEventListener('click', async () => {
          showToast('Воспроизведение: Все песни');
          state.shuffle = false;
          renderPlayerUI();
          await apiPost('/api/play/playlist', { playlist: 'Музыка', shuffle: false });
        });

        document.getElementById('btnShuffleAllSongs')?.addEventListener('click', async () => {
          showToast('Перемешать: Все песни');
          state.shuffle = true;
          renderPlayerUI();
          await apiPost('/api/play/playlist', { playlist: 'Музыка', shuffle: true });
        });

        el.libraryContentList.querySelectorAll('.track-row').forEach(row => {
          row.addEventListener('click', async (e) => {
            if (e.target.classList.contains('track-more-btn')) {
              e.stopPropagation();
              const tId = parseInt(row.getAttribute('data-id'), 10);
              const name = row.querySelector('.track-row-name').textContent;
              openActionSheet({ id: tId, name, artist: 'Медиатека' });
              return;
            }
            const tId = parseInt(row.getAttribute('data-id'), 10);
            showToast(`Воспроизведение: ${row.querySelector('.track-row-name').textContent}`);
            await apiPost('/api/play/playlist', { playlist: 'Музыка', track_id: tId, shuffle: false });
          });
        });
      }
    }
  }

  async function openPlaylistDetails(name, count) {
    el.libraryContentTitle.textContent = name;
    el.libraryContentList.innerHTML = '<div class="skeleton-row" style="margin-bottom: 12px;"></div><div class="skeleton-row"></div>';
    
    const res = await apiGet(`/api/playlists/tracks?name=${encodeURIComponent(name)}`);
    if (!res || !res.tracks || res.tracks.length === 0) {
      el.libraryContentList.innerHTML = '<p class="search-empty-state">Нет треков</p>';
      return;
    }

    let html = `
      <div class="playlist-actions-row">
        <button class="playlist-action-btn btn-play-all" id="btnPlayAllPlaylist">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>
          <span>Воспроизвести</span>
        </button>
        <button class="playlist-action-btn btn-shuffle-all" id="btnShuffleAllPlaylist">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M16 3h5v5M4 20l6.5-6.5M21 3l-6.5 6.5M21 21v-5h-5M4 4l17 17"/></svg>
          <span>Перемешать</span>
        </button>
      </div>
    `;

    html += res.tracks.map(t => `
      <div class="track-row" data-index="${t.index}" data-id="${t.id}">
        <span class="track-row-idx">${t.index}</span>
        <div class="track-row-info">
          <div class="track-row-name">${escapeHtml(t.name)}</div>
          <div class="track-row-sub">${escapeHtml(t.artist)}${t.album ? ` • ${escapeHtml(t.album)}` : ''}</div>
        </div>
        <button class="track-more-btn" title="Действия" aria-label="Меню">⋯</button>
      </div>
    `).join('');

    el.libraryContentList.innerHTML = html;

    document.getElementById('btnPlayAllPlaylist')?.addEventListener('click', async () => {
      showToast(`Воспроизведение: ${name}`);
      state.shuffle = false;
      renderPlayerUI();
      await apiPost('/api/play/playlist', { playlist: name, shuffle: false });
    });

    document.getElementById('btnShuffleAllPlaylist')?.addEventListener('click', async () => {
      showToast(`Перемешать: ${name}`);
      state.shuffle = true;
      renderPlayerUI();
      await apiPost('/api/play/playlist', { playlist: name, shuffle: true });
    });

    el.libraryContentList.querySelectorAll('.track-row').forEach(row => {
      row.addEventListener('click', async (e) => {
        if (e.target.classList.contains('track-more-btn')) {
          e.stopPropagation();
          const tId = parseInt(row.getAttribute('data-id'), 10);
          const tName = row.querySelector('.track-row-name').textContent;
          openActionSheet({ id: tId, name: tName, artist: name });
          return;
        }
        const tId = parseInt(row.getAttribute('data-id'), 10);
        showToast(`Воспроизведение: ${row.querySelector('.track-row-name').textContent}`);
        await apiPost('/api/play/playlist', { playlist: name, track_id: tId });
      });
    });
  }

  function setupLibraryListeners() {
    document.querySelectorAll('.library-nav-item').forEach(btn => {
      btn.addEventListener('click', () => {
        loadLibraryCategory(btn.getAttribute('data-target'));
      });
    });

    el.btnLibraryBack.addEventListener('click', () => {
      el.libraryContentArea.style.display = 'none';
      el.libraryNavList.style.display = 'flex';
      el.libraryContentList.innerHTML = '';
      el.libraryContentTitle.textContent = '';
    });
  }

  // =========================================================================
  // TAB 4: Search (Cloud & Library)
  // =========================================================================
  let lastCloudResults = null;

  function setupSearchListeners() {
    el.searchInput.addEventListener('input', () => {
      const q = el.searchInput.value.trim();
      el.btnClearSearch.style.display = q.length > 0 ? 'flex' : 'none';
      if (q.length === 0) {
        el.searchPreState.style.display = 'block';
        el.searchResultsState.style.display = 'none';
        el.searchList.innerHTML = '';
        lastCloudResults = null;
        return;
      }
      clearTimeout(searchDebounceTimer);
      searchDebounceTimer = setTimeout(() => {
        performSearch(q);
      }, 300);
    });

    el.btnClearSearch.addEventListener('click', () => {
      el.searchInput.value = '';
      el.btnClearSearch.style.display = 'none';
      el.searchPreState.style.display = 'block';
      el.searchResultsState.style.display = 'none';
      el.searchList.innerHTML = '';
      lastCloudResults = null;
    });

    el.btnAlbumBack?.addEventListener('click', () => {
      el.albumDetailArea.style.display = 'none';
      el.searchMainArea.style.display = 'block';
    });
  }

  async function performSearch(query) {
    el.searchMainArea.style.display = 'block';
    el.albumDetailArea.style.display = 'none';
    el.searchPreState.style.display = 'none';
    el.searchResultsState.style.display = 'block';
    el.searchList.innerHTML = '<div class="skeleton-row"></div><div class="skeleton-row"></div><div class="skeleton-row"></div>';

    const res = await apiGet(`/api/search?q=${encodeURIComponent(query)}&country=${state.country || 'ru'}`);
    if (!res || !res.data) {
      el.searchList.innerHTML = '<p class="search-empty-state">Ничего не найдено</p>';
      return;
    }

    const data = res.data;
    const cloudData = data.cloud || {};
    const localData = data.local || {};

    if (localData.tracks && localData.tracks.length > 0) {
      const localSongs = localData.tracks.map(t => ({
        id: t.id,
        name: t.name,
        artist: t.artist,
        album: t.album,
        artwork: t.artwork || `/api/artwork/track?id=${t.id}`,
        duration: t.duration,
        is_local: true
      }));
      cloudData.songs = [...localSongs, ...(cloudData.songs || [])];
    }

    lastCloudResults = cloudData;
    renderCategorizedCloudSearch(cloudData);
  }

  function renderCategorizedCloudSearch(data) {
    const artists = data.artists || [];
    const songs = data.songs || [];
    const albums = data.albums || [];

    if (artists.length === 0 && songs.length === 0 && albums.length === 0) {
      el.searchList.innerHTML = '<div class="search-empty-state"><p>Ничего не найдено в Apple Music</p></div>';
      return;
    }

    let html = '';

    // 1. Artists Section
    if (artists.length > 0) {
      html += `
        <div class="search-group">
          <div class="search-group-title">Исполнители</div>
          <div style="display:flex; flex-direction:column; gap:8px;">
            ${artists.slice(0, 3).map(a => `
              <div class="artist-row" data-artist="${escapeHtml(a.name)}" data-id="${escapeHtml(a.id || '')}">
                <div class="artist-avatar" style="background: ${a.artwork ? 'url('+a.artwork+') center/cover' : ''}">${a.artwork ? '' : escapeHtml(a.name.charAt(0).toUpperCase())}</div>
                <div class="artist-name">${escapeHtml(a.name)}</div>
                <svg viewBox="0 0 24 24" width="16" height="16" fill="var(--text-tertiary)"><path d="M9 18l6-6-6-6"/></svg>
              </div>
            `).join('')}
          </div>
        </div>
      `;
    }

    // 2. Songs Section (Top Tracks with Play & Shuffle actions)
    if (songs.length > 0) {
      const displaySongs = songs.slice(0, 20);
      html += `
        <div class="search-group">
          <div class="search-group-header" style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px;">
            <div class="search-group-title" style="margin-bottom: 0;">Лучшие треки</div>
            <div class="search-actions-row" style="display: flex; gap: 8px;">
              <button class="action-pill-btn btn-play-top-tracks" id="btnPlayTopTracks">
                <svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>
                <span>Воспроизвести</span>
              </button>
              <button class="action-pill-btn btn-shuffle-top-tracks" id="btnShuffleTopTracks">
                <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M16 3h5v5M4 20l6.5-6.5M21 3l-6.5 6.5M21 21v-5h-5M4 4l17 17"/></svg>
                <span>Случайно</span>
              </button>
            </div>
          </div>
          <div class="chart-list">
            ${displaySongs.map((s, idx) => `
              <div class="chart-item" data-index="${idx}" data-url="${escapeHtml(s.url || '')}" data-id="${escapeHtml(s.id || '')}" data-name="${escapeHtml(s.name)}" data-artist="${escapeHtml(s.artist)}">
                <img class="chart-art" src="${s.artwork || ''}" alt="Art" loading="lazy" onerror="this.src='${PLACEHOLDER_ARTWORK}'">
                <div class="chart-info">
                  <div class="chart-title">${escapeHtml(s.name)}</div>
                  <div class="chart-artist">${escapeHtml(s.artist)}${s.album ? ` • ${escapeHtml(s.album)}` : ''}</div>
                </div>
                <button class="track-more-btn" title="Действия" aria-label="Меню">⋯</button>
              </div>
            `).join('')}
          </div>
        </div>
      `;
    }

    // 3. Albums Section
    if (albums.length > 0) {
      const displayAlbums = albums.slice(0, 10);
      html += `
        <div class="search-group">
          <div class="search-group-title">Альбомы</div>
          <div class="horizontal-scroll">
            ${displayAlbums.map(al => `
              <div class="hot-pick-card album-card-btn" style="width:140px; cursor: pointer;" data-id="${escapeHtml(al.id || '')}" data-name="${escapeHtml(al.name)}" data-artist="${escapeHtml(al.artist)}" data-art="${escapeHtml(al.artwork || '')}">
                <img class="card-cover" src="${al.artwork || ''}" alt="Cover" loading="lazy" onerror="this.src='${PLACEHOLDER_ARTWORK}'">
                <div class="card-title">${escapeHtml(al.name)}</div>
                <div class="card-subtitle">${escapeHtml(al.artist)} ${al.release_date ? '• ' + al.release_date.substring(0, 4) : ''}</div>
              </div>
            `).join('')}
          </div>
        </div>
      `;
    }

    el.searchList.innerHTML = html;

    // Attach Artist Click Listeners
    el.searchList.querySelectorAll('.artist-row').forEach(acard => {
      acard.addEventListener('click', () => {
        const aName = acard.getAttribute('data-artist');
        el.searchInput.value = aName;
        el.btnClearSearch.style.display = 'flex';
        performSearch(aName);
      });
    });

    // Attach Top Tracks Play All & Shuffle All Listeners
    document.getElementById('btnPlayTopTracks')?.addEventListener('click', async () => {
      showToast('Воспроизведение лучших треков...');
      await apiPost('/api/play/custom_queue', {
        tracks: songs,
        shuffle: false,
        start_index: 0,
        queue_name: `Лучшие треки (${el.searchInput.value.trim()})`
      });
    });

    document.getElementById('btnShuffleTopTracks')?.addEventListener('click', async () => {
      showToast('Перемешивание лучших треков...');
      await apiPost('/api/play/custom_queue', {
        tracks: songs,
        shuffle: true,
        start_index: 0,
        queue_name: `Лучшие треки (${el.searchInput.value.trim()})`
      });
    });

    // Attach Song Play Listeners & Action sheet
    el.searchList.querySelectorAll('.chart-item').forEach(item => {
      item.addEventListener('click', async (e) => {
        const idx = parseInt(item.getAttribute('data-index'), 10) || 0;
        if (e.target.classList.contains('track-more-btn')) {
          e.stopPropagation();
          openActionSheet(songs[idx]);
          return;
        }
        const name = item.getAttribute('data-name');
        showToast(`Воспроизведение: ${name}`);
        await apiPost('/api/play/custom_queue', {
          tracks: songs,
          shuffle: false,
          start_index: idx,
          queue_name: `Поиск (${el.searchInput.value.trim()})`
        });
      });
    });

    // Attach Album Click Listeners
    el.searchList.querySelectorAll('.album-card-btn').forEach(item => {
      item.addEventListener('click', () => {
        const id = item.getAttribute('data-id');
        openAlbumDetails(id);
      });
    });
  }

  async function openAlbumDetails(albumId) {
    if (!albumId) return;
    el.searchMainArea.style.display = 'none';
    el.albumDetailArea.style.display = 'block';
    el.albumDetailContent.innerHTML = `
      <div class="skeleton-row" style="height: 100px; margin-bottom: 20px; border-radius: 12px;"></div>
      <div class="skeleton-row"></div>
      <div class="skeleton-row"></div>
      <div class="skeleton-row"></div>
    `;

    const res = await apiGet(`/api/album?id=${encodeURIComponent(albumId)}&country=${state.country || 'ru'}`);
    if (!res || !res.album) {
      el.albumDetailContent.innerHTML = '<p class="search-empty-state">Не удалось загрузить альбом</p>';
      return;
    }

    const album = res.album;
    const tracks = album.tracks || [];

    let html = `
      <div class="album-detail-header">
        <img class="album-detail-cover" src="${album.artwork || ''}" alt="Cover" loading="lazy" onerror="this.src='${PLACEHOLDER_ARTWORK}'">
        <div class="album-detail-info">
          <div class="album-detail-title">${escapeHtml(album.name)}</div>
          <div class="album-detail-artist">${escapeHtml(album.artist)}</div>
          <div class="album-detail-meta">${album.release_date ? album.release_date.substring(0, 4) + ' • ' : ''}${album.genre ? escapeHtml(album.genre) + ' • ' : ''}${album.track_count || tracks.length} треков</div>
        </div>
      </div>

      <div class="playlist-actions-row" style="margin-bottom: 20px;">
        <button class="playlist-action-btn btn-play-all" id="btnPlayAllAlbum">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>
          <span>Воспроизвести</span>
        </button>
        <button class="playlist-action-btn btn-shuffle-all" id="btnShuffleAllAlbum">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M16 3h5v5M4 20l6.5-6.5M21 3l-6.5 6.5M21 21v-5h-5M4 4l17 17"/></svg>
          <span>Перемешать</span>
        </button>
      </div>

      <div class="album-tracks-list">
        ${tracks.map((t, idx) => `
          <div class="track-row album-track-row" data-index="${idx}" data-id="${t.id}">
            <span class="track-row-idx">${t.index || (idx + 1)}</span>
            <div class="track-row-info">
              <div class="track-row-name">${escapeHtml(t.name)}</div>
              <div class="track-row-sub">${escapeHtml(t.artist)}</div>
            </div>
            ${t.duration > 0 ? `<div style="font-size: 13px; color: var(--text-tertiary); margin-right: 8px;">${formatTime(t.duration)}</div>` : ''}
            <button class="track-more-btn" title="Действия" aria-label="Меню">⋯</button>
          </div>
        `).join('')}
      </div>
    `;

    el.albumDetailContent.innerHTML = html;

    // Play All in Album
    document.getElementById('btnPlayAllAlbum')?.addEventListener('click', async () => {
      showToast(`Воспроизведение: ${album.name}`);
      await apiPost('/api/play/custom_queue', {
        tracks: tracks,
        shuffle: false,
        start_index: 0,
        queue_name: album.name
      });
    });

    // Shuffle Album
    document.getElementById('btnShuffleAllAlbum')?.addEventListener('click', async () => {
      showToast(`Перемешать: ${album.name}`);
      await apiPost('/api/play/custom_queue', {
        tracks: tracks,
        shuffle: true,
        start_index: 0,
        queue_name: album.name
      });
    });

    // Click single track in album
    el.albumDetailContent.querySelectorAll('.album-track-row').forEach(row => {
      row.addEventListener('click', async (e) => {
        const idx = parseInt(row.getAttribute('data-index'), 10) || 0;
        if (e.target.classList.contains('track-more-btn')) {
          e.stopPropagation();
          openActionSheet(tracks[idx]);
          return;
        }
        const tName = row.querySelector('.track-row-name').textContent;
        showToast(`Воспроизведение: ${tName}`);
        await apiPost('/api/play/custom_queue', {
          tracks: tracks,
          shuffle: false,
          start_index: idx,
          queue_name: album.name
        });
      });
    });
  }

  function setupSettingsListeners() {
    function openQrModal() {
      el.qrModalBackdrop.style.display = 'flex';
    }

    function closeQrModal() {
      el.qrModalBackdrop.style.display = 'none';
    }

    el.headerQrBtn.addEventListener('click', openQrModal);
    el.btnQrModalClose.addEventListener('click', closeQrModal);
    el.qrModalBackdrop.addEventListener('click', (e) => {
      if (e.target === el.qrModalBackdrop) closeQrModal();
    });
  }

  function escapeHtml(str) {
    if (!str) return '';
    return str
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  // =========================================================================
  // Initialize App
  // =========================================================================
  function init() {
    setupControlListeners();
    setupQueueListeners();
    setupNavigation();
    setupExploreListeners();
    setupActionSheetListeners();
    setupLibraryListeners();
    setupSearchListeners();
    setupSettingsListeners();
    initRealtimeSync();

    // Initial Status Check
    apiGet('/api/status').then(data => {
      if (data) updateState(data);
    });

    // Preload info for QR
    apiGet('/api/info').then(info => {
      if (info && info.primary_url) {
        el.qrUrlText.textContent = info.primary_url;
      }
    });

    // Load initial explore tab
    switchTab('pageExplore');
  }

  // Start on DOM ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

})();
