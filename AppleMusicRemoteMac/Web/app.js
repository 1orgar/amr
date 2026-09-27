/**
 * Apple Music Remote (AMR) - Client Application
 * Pure Vanilla JS (ES6+), Zero Dependencies.
 */

(function () {
  'use strict';

  // --- Application State ---
  const state = {
    connected: false,
    playbackState: 'stopped', // 'playing', 'paused', 'stopped'
    playerState: 'stopped', // 'playing', 'paused', 'stopped'
    initialViewSelected: false,
    position: 0,
    duration: 0,
    volume: 100,
    shuffle: false,
    repeatMode: 'off', // 'off', 'one', 'all'
    audioQuality: 'Lossless (ALAC 24-bit/48kHz)',
    track: null,
    queue: {
      upcoming: [],
      history: [],
      currentIndex: 0,
      totalTracks: 0,
      playlist: ''
    },
    playlists: [],
    currentPlaylistDetail: null,
    trends: {
      country: 'ru',
      topSongs: [],
      stations: [],
      topAlbums: [],
      genres: [],
      loaded: false
    },
    searchQuery: '',
    searchScope: 'all',
    activeView: 'view-now-playing',
    desktopActiveTab: 'library',

    // Scrubber local tracking
    isScrubbing: false,
    scrubValue: 0,
    lastSyncPos: 0,
    lastSyncTime: performance.now()
  };

  // --- DOM Elements Cache ---
  const dom = {
    overlay: document.getElementById('connection-overlay'),
    connectionStatusText: document.getElementById('connection-status-text'),
    btnReconnect: document.getElementById('btn-reconnect'),

    // Views
    viewNowPlaying: document.getElementById('view-now-playing'),
    viewQueue: document.getElementById('view-queue'),
    viewLibrary: document.getElementById('view-library'),
    viewHome: document.getElementById('view-home') || document.getElementById('view-trends'),
    viewTrends: document.getElementById('view-home') || document.getElementById('view-trends'),
    viewSearch: document.getElementById('view-search'),

    // Home / Trends Elements
    homeHeroCarousel: document.getElementById('home-hero-carousel'),
    homeRecentSection: document.getElementById('home-recent-section'),
    homeRecentLink: document.getElementById('home-recent-link'),
    homeRecentCarousel: document.getElementById('home-recent-carousel'),
    homeStationsSection: document.getElementById('home-stations-section'),
    homeStationsCarousel: document.getElementById('home-stations-carousel'),
    homeAlbumsSection: document.getElementById('home-albums-section'),
    homeAlbumsCarousel: document.getElementById('home-albums-carousel'),
    homeGenresSection: document.getElementById('home-genres-section'),
    homeGenresGrid: document.getElementById('home-genres-grid'),

    // Recently Played Full Pane
    recentDetailPane: document.getElementById('recent-detail-pane'),
    btnBackFromRecent: document.getElementById('btn-back-from-recent'),
    btnPlayRecentAll: document.getElementById('btn-play-recent-all'),
    btnShuffleRecentAll: document.getElementById('btn-shuffle-recent-all'),
    recentTracksFullList: document.getElementById('recent-tracks-full-list'),
    recentTotalCount: document.getElementById('recent-total-count'),

    trendsCountryPills: document.querySelectorAll('.country-pill'),
    trendsStationsGrid: document.getElementById('home-stations-carousel') || document.getElementById('trends-stations-grid'),
    trendsAlbumsGrid: document.getElementById('home-albums-carousel') || document.getElementById('trends-albums-grid'),
    trendsGenresGrid: document.getElementById('home-genres-grid') || document.getElementById('trends-genres-grid'),

    // Desktop Nav
    desktopNavButtons: document.querySelectorAll('.nav-tab-btn'),

    // Mobile Bottom Tab Bar
    tabItems: document.querySelectorAll('.tab-item'),

    // Mini Player
    miniPlayer: document.getElementById('mini-player'),
    miniTrigger: document.getElementById('mini-player-trigger'),
    miniArt: document.getElementById('mini-artwork'),
    miniTitle: document.getElementById('mini-title'),
    miniArtist: document.getElementById('mini-artist'),
    miniBtnPlayPause: document.getElementById('mini-btn-play-pause'),
    miniIconPlay: document.getElementById('mini-icon-play'),
    miniIconPause: document.getElementById('mini-icon-pause'),
    miniBtnNext: document.getElementById('mini-btn-next'),
    miniProgressFill: document.getElementById('mini-progress-fill'),

    // Now Playing Main Player
    playerArtwork: document.getElementById('player-artwork'),
    playerTitle: document.getElementById('player-title'),
    playerArtist: document.getElementById('player-artist'),
    playerAlbum: document.getElementById('player-album'),
    btnFavorite: document.getElementById('btn-favorite'),
    audioQualityBadge: document.getElementById('audio-quality-badge'),
    audioQualityText: document.getElementById('audio-quality-text'),

    // Scrubber
    scrubberContainer: document.getElementById('scrubber-container'),
    scrubberFill: document.getElementById('scrubber-fill'),
    scrubberThumb: document.getElementById('scrubber-thumb'),
    scrubberInput: document.getElementById('scrubber-input'),
    timeElapsed: document.getElementById('time-elapsed'),
    timeRemaining: document.getElementById('time-remaining'),

    // Transport Controls
    btnShuffle: document.getElementById('btn-shuffle'),
    btnPrev: document.getElementById('btn-prev'),
    btnPlayPause: document.getElementById('btn-play-pause'),
    iconPlay: document.getElementById('icon-play'),
    iconPause: document.getElementById('icon-pause'),
    btnNext: document.getElementById('btn-next'),
    btnRepeat: document.getElementById('btn-repeat'),
    repeatBadge: document.getElementById('repeat-badge'),

    // Queue Elements
    queueSubtitle: document.getElementById('queue-subtitle'),
    queueCurrentGroup: document.getElementById('queue-current-group'),
    queueCurrentTrack: document.getElementById('queue-current-track'),
    queueUpcomingList: document.getElementById('queue-upcoming-list'),
    btnClearQueue: document.getElementById('btn-clear-queue'),

    // Library Elements
    playlistsBrowsePane: document.getElementById('playlists-browse-pane'),
    playlistsGrid: document.getElementById('playlists-grid'),
    btnRefreshLibrary: document.getElementById('btn-refresh-library'),
    playlistDetailPane: document.getElementById('playlist-detail-pane'),
    btnBackToPlaylists: document.getElementById('btn-back-to-playlists'),
    detailArtwork: document.getElementById('detail-artwork'),
    detailTitle: document.getElementById('detail-title'),
    detailBadge: document.getElementById('detail-badge'),
    detailMeta: document.getElementById('detail-meta'),
    btnPlayPlaylist: document.getElementById('btn-play-playlist'),
    btnShufflePlaylist: document.getElementById('btn-shuffle-playlist'),
    playlistTracksList: document.getElementById('playlist-tracks-list'),

    // Search Elements
    searchInput: document.getElementById('search-input'),
    btnClearSearch: document.getElementById('btn-clear-search'),
    filterChips: document.querySelectorAll('.filter-chip'),
    searchResults: document.getElementById('search-results'),

    // Busy / Action Loading Overlay
    busyOverlay: document.getElementById('busy-overlay'),
    busyMessage: document.getElementById('busy-message'),

    // Modal
    qualityModal: document.getElementById('quality-modal'),
    btnCloseModal: document.getElementById('btn-close-modal'),
    modalSpecQuality: document.getElementById('modal-spec-quality'),
    modalSpecRate: document.getElementById('modal-spec-rate')
  };

  // --- Busy Overlay & Action Loading Controller ---
  let busyTimeout = null;
  let activeLoadingBtn = null;

  function setUIBusy(isBusy, message = 'Загрузка...', sourceBtn = null) {
    state.isBusyAction = Boolean(isBusy);

    if (isBusy) {
      if (busyTimeout) clearTimeout(busyTimeout);
      document.body.classList.add('ui-blocked');

      if (dom.busyMessage) {
        dom.busyMessage.textContent = message;
      }
      if (dom.busyOverlay) {
        dom.busyOverlay.classList.remove('hidden');
      }

      if (sourceBtn) {
        if (activeLoadingBtn && activeLoadingBtn !== sourceBtn) {
          activeLoadingBtn.classList.remove('btn-loading');
        }
        activeLoadingBtn = sourceBtn;
        sourceBtn.classList.add('btn-loading');
      }

      // Safety timeout: automatically unblock after 7 seconds if server is slow
      busyTimeout = setTimeout(() => {
        setUIBusy(false);
      }, 7000);
    } else {
      if (busyTimeout) {
        clearTimeout(busyTimeout);
        busyTimeout = null;
      }
      document.body.classList.remove('ui-blocked');

      if (dom.busyOverlay) {
        dom.busyOverlay.classList.add('hidden');
      }

      if (activeLoadingBtn) {
        activeLoadingBtn.classList.remove('btn-loading');
        activeLoadingBtn = null;
      }
      document.querySelectorAll('.btn-loading').forEach(b => b.classList.remove('btn-loading'));
    }
  }

  // --- WebSocket Manager ---
  let socket = null;
  let reconnectTimer = null;
  let reconnectAttempt = 0;
  const backoffDelays = [1000, 2000, 3000, 5000];

  function getWsUrl() {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const host = window.location.host || 'localhost:8080';
    return `${protocol}//${host}`;
  }

  function connectWebSocket() {
    clearTimeout(reconnectTimer);
    state.initialViewSelected = false;

    if (socket) {
      try {
        socket.onclose = null;
        socket.onerror = null;
        socket.close();
      } catch (e) {}
    }

    const url = getWsUrl();
    try {
      socket = new WebSocket(url);
    } catch (err) {
      scheduleReconnect();
      return;
    }

    socket.onopen = function () {
      state.connected = true;
      reconnectAttempt = 0;
      dom.overlay.classList.add('hidden');

      // Request initial status, queue, library, and trends
      send({ action: 'get_status' });
      send({ action: 'get_queue' });
      send({ action: 'get_playlists' });
      send({ action: 'get_catalog_charts', params: { country: state.trends.country } });
      send({ action: 'get_explore', params: { country: state.trends.country } });
    };

    socket.onmessage = function (event) {
      try {
        const msg = JSON.parse(event.data);
        handleServerMessage(msg);
      } catch (e) {
        console.error('Failed to parse WebSocket message:', e, event.data);
      }
    };

    socket.onclose = function () {
      state.connected = false;
      state.initialViewSelected = false;
      dom.overlay.classList.remove('hidden');
      scheduleReconnect();
    };

    socket.onerror = function () {
      state.connected = false;
      state.initialViewSelected = false;
      dom.overlay.classList.remove('hidden');
    };
  }

  function scheduleReconnect() {
    const delay = backoffDelays[Math.min(reconnectAttempt, backoffDelays.length - 1)];
    reconnectAttempt++;
    dom.connectionStatusText.textContent = `Попытка переподключения через ${Math.round(delay / 1000)}с... (попытка ${reconnectAttempt})`;
    clearTimeout(reconnectTimer);
    reconnectTimer = setTimeout(connectWebSocket, delay);
  }

  function send(msgObj) {
    if (!socket || socket.readyState !== WebSocket.OPEN) {
      return false;
    }
    socket.send(JSON.stringify(msgObj));
    return true;
  }

  // --- Server Message Dispatcher ---
  function handleServerMessage(msg) {
    const type = (msg.event || msg.action || msg.type || '').toLowerCase();
    const data = msg.data !== undefined ? msg.data : msg;

    switch (type) {
      case 'player_state_changed':
      case 'status':
      case 'get_status':
        updatePlayerState(data);
        break;

      case 'queue_changed':
      case 'queue':
      case 'get_queue':
        updateQueue(data);
        break;

      case 'playlists':
      case 'get_playlists':
      case 'playlists_result':
        updatePlaylists(data);
        break;

      case 'playlist_tracks':
      case 'get_playlist_tracks':
        updatePlaylistTracks(data);
        break;

      case 'get_catalog_charts':
      case 'catalog_charts':
      case 'charts':
        updateCatalogCharts(data);
        break;

      case 'get_explore':
      case 'explore':
        updateExploreFeed(data);
        break;

      case 'get_album':
      case 'album':
        updateAlbumDetails(data);
        break;

      case 'search':
      case 'search_result':
        updateSearchResults(data);
        break;

      default:
        // Check if data has player properties
        if (data && (data.player_state || data.playerState)) {
          updatePlayerState(data);
        } else if (data && (data.upcoming_tracks || data.upcomingTracks)) {
          updateQueue(data);
        }
        break;
    }

    // Dismiss busy overlay when playback updates or response arrives
    const busyDismissActions = [
      'player_state_changed', 'status', 'get_status',
      'queue_changed', 'queue', 'get_queue',
      'play', 'pause', 'play_pause', 'next', 'previous',
      'play_album', 'play_album_tracks', 'play_playlist',
      'play_station', 'play_recent', 'play_queue_index', 'play_cloud'
    ];
    if (busyDismissActions.includes(type) || msg.status === 'ok' || msg.status === 'error') {
      if (state.isBusyAction) {
        setUIBusy(false);
      }
    }
  }

  function updatePlayerState(data) {
    if (!data) return;

    const oldTrack = state.track;
    const newTrack = data.track || null;
    const isNewTrack = Boolean(
      (newTrack && (!oldTrack || newTrack.id !== oldTrack.id || newTrack.name !== oldTrack.name || newTrack.artist !== oldTrack.artist)) ||
      (!newTrack && oldTrack)
    );

    state.playerState = data.player_state || data.playerState || 'stopped';
    state.playbackState = state.playerState;

    // Dynamic initial view: on first player state / status message after connection
    if (!state.initialViewSelected) {
      state.initialViewSelected = true;
      if (state.playbackState === 'playing') {
        switchMobileView('view-now-playing');
      } else {
        switchMobileView('view-home');
        switchDesktopTab('home');
      }
    }

    state.duration = Number(data.duration) || 0;
    const reportedPos = Math.max(0, Number(data.position) || 0);

    if (isNewTrack) {
      state.lastSyncPos = reportedPos;
      state.lastSyncTime = performance.now();
      if (!state.isScrubbing) {
        updateScrubberUI(reportedPos, state.duration);
      }
    } else if (!state.isScrubbing) {
      // Smooth sync: only reconcile if reported position drifts from local prediction by > 1.2s
      const now = performance.now();
      const predictedPos = state.playerState === 'playing'
        ? Math.min(state.duration, state.lastSyncPos + (now - state.lastSyncTime) / 1000)
        : state.lastSyncPos;

      if (Math.abs(reportedPos - predictedPos) > 1.2 || reportedPos < 1.0) {
        state.lastSyncPos = reportedPos;
        state.lastSyncTime = now;
        updateScrubberUI(reportedPos, state.duration);
      }
    }

    state.shuffle = Boolean(data.shuffle);
    state.repeatMode = data.repeat || data.repeatMode || 'off';
    state.audioQuality = data.audio_quality || data.audioQuality || 'Lossless (ALAC 24-bit/48kHz)';
    state.track = newTrack;

    renderNowPlaying();
  }

  function formatTime(seconds) {
    if (isNaN(seconds) || seconds < 0) return '0:00';
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
  }

  function getArtworkSrc(track) {
    if (!track) return 'apple-touch-icon.svg';
    if (track.artwork_data_base64) {
      return `data:image/jpeg;base64,${track.artwork_data_base64}`;
    }
    if (track.artwork_url && track.artwork_url.length > 5) {
      return track.artwork_url;
    }
    if (track.artwork && track.artwork.length > 5) {
      return track.artwork;
    }
    if (track.numeric_id && track.numeric_id > 0) {
      return `/api/artwork/track?id=${track.numeric_id}`;
    }
    return '/api/artwork';
  }

  function renderNowPlaying() {
    const isPlaying = state.playerState === 'playing';
    const t = state.track;

    // Track Meta
    if (t) {
      dom.playerTitle.textContent = t.name || 'Без названия';
      dom.playerArtist.textContent = t.artist || 'Неизвестный исполнитель';
      dom.playerAlbum.textContent = t.album || '';
      const art = getArtworkSrc(t);
      if (dom.playerArtwork.getAttribute('src') !== art) {
        dom.playerArtwork.src = art;
      }
      dom.btnFavorite.classList.toggle('active', Boolean(t.favorited));

      // Mini Player sync
      dom.miniTitle.textContent = t.name || 'Без названия';
      dom.miniArtist.textContent = t.artist || 'Apple Music';
      if (dom.miniArt.getAttribute('src') !== art) {
        dom.miniArt.src = art;
      }
    } else {
      dom.playerTitle.textContent = 'Не играет';
      dom.playerArtist.textContent = 'Apple Music';
      dom.playerAlbum.textContent = '';
      if (dom.playerArtwork.getAttribute('src') !== 'apple-touch-icon.svg') {
        dom.playerArtwork.src = 'apple-touch-icon.svg';
      }
      dom.btnFavorite.classList.remove('active');

      dom.miniTitle.textContent = 'Не играет';
      dom.miniArtist.textContent = 'Apple Music';
      if (dom.miniArt.getAttribute('src') !== 'apple-touch-icon.svg') {
        dom.miniArt.src = 'apple-touch-icon.svg';
      }
    }

    // Play/Pause button icons
    if (isPlaying) {
      dom.iconPlay.classList.add('hidden');
      dom.iconPause.classList.remove('hidden');
      dom.miniIconPlay.classList.add('hidden');
      dom.miniIconPause.classList.remove('hidden');
    } else {
      dom.iconPlay.classList.remove('hidden');
      dom.iconPause.classList.add('hidden');
      dom.miniIconPlay.classList.remove('hidden');
      dom.miniIconPause.classList.add('hidden');
    }

    // Shuffle & Repeat buttons
    dom.btnShuffle.classList.toggle('active', state.shuffle);
    if (state.repeatMode === 'one') {
      dom.btnRepeat.classList.add('active');
      dom.repeatBadge.classList.remove('hidden');
    } else if (state.repeatMode === 'all') {
      dom.btnRepeat.classList.add('active');
      dom.repeatBadge.classList.add('hidden');
    } else {
      dom.btnRepeat.classList.remove('active');
      dom.repeatBadge.classList.add('hidden');
    }

    // Audio Quality Badge
    const aqText = cleanAudioQualityLabel(state.audioQuality);
    dom.audioQualityText.textContent = aqText;
    dom.modalSpecQuality.textContent = state.audioQuality;

    // Extract sample rate if present
    if (state.audioQuality.includes('192')) {
      dom.modalSpecRate.textContent = '192.0 кГц (Hi-Res Bit-Perfect)';
    } else if (state.audioQuality.includes('96')) {
      dom.modalSpecRate.textContent = '96.0 кГц (Hi-Res Bit-Perfect)';
    } else if (state.audioQuality.includes('48')) {
      dom.modalSpecRate.textContent = '48.0 кГц (Lossless Bit-Perfect)';
    } else if (state.audioQuality.includes('44.1')) {
      dom.modalSpecRate.textContent = '44.1 кГц (Lossless Bit-Perfect)';
    } else {
      dom.modalSpecRate.textContent = 'Автосинхронизация CoreAudio';
    }

    // If not scrubbing, update timestamps
    if (!state.isScrubbing) {
      updateScrubberUI(state.lastSyncPos, state.duration);
    }

    renderCurrentQueueTrack(dom.queueCurrentTrack);
  }

  function cleanAudioQualityLabel(raw) {
    if (!raw) return 'LOSSLESS';
    const up = raw.toUpperCase();
    if (up.includes('HI-RES')) return 'HI-RES LOSSLESS';
    if (up.includes('LOSSLESS')) return 'LOSSLESS';
    if (up.includes('AAC')) return 'AAC 256';
    if (up.includes('ALAC')) return 'ALAC LOSSLESS';
    return raw;
  }

  function updateScrubberUI(currentPos, totalDur) {
    if (totalDur <= 0) {
      dom.scrubberFill.style.width = '0%';
      dom.scrubberThumb.style.left = '0%';
      dom.miniProgressFill.style.width = '0%';
      dom.timeElapsed.textContent = '0:00';
      dom.timeRemaining.textContent = '-0:00';
      dom.scrubberInput.value = 0;
      return;
    }

    const clampedPos = Math.max(0, Math.min(currentPos, totalDur));
    const percent = (clampedPos / totalDur) * 100;

    dom.scrubberFill.style.width = `${percent}%`;
    dom.scrubberThumb.style.left = `${percent}%`;
    dom.miniProgressFill.style.width = `${percent}%`;
    dom.scrubberInput.value = percent;

    dom.timeElapsed.textContent = formatTime(clampedPos);
    const remaining = totalDur - clampedPos;
    dom.timeRemaining.textContent = `-${formatTime(remaining)}`;
  }

  // --- Optimistic 60fps Scrubber Loop ---
  function scrubberAnimationLoop() {
    if (state.playerState === 'playing' && !state.isScrubbing && state.duration > 0) {
      const now = performance.now();
      const deltaSec = (now - state.lastSyncTime) / 1000;
      const currentPos = Math.min(state.duration, state.lastSyncPos + deltaSec);
      updateScrubberUI(currentPos, state.duration);
    }
    requestAnimationFrame(scrubberAnimationLoop);
  }
  requestAnimationFrame(scrubberAnimationLoop);

  // --- Scrubber User Interaction ---
  dom.scrubberInput.addEventListener('input', function (e) {
    state.isScrubbing = true;
    const percent = parseFloat(e.target.value);
    const targetPos = (percent / 100) * state.duration;
    state.scrubValue = targetPos;

    dom.scrubberFill.style.width = `${percent}%`;
    dom.scrubberThumb.style.left = `${percent}%`;
    dom.timeElapsed.textContent = formatTime(targetPos);
    dom.timeRemaining.textContent = `-${formatTime(Math.max(0, state.duration - targetPos))}`;
  });

  function commitScrub() {
    if (!state.isScrubbing) return;
    const targetPos = state.scrubValue;
    state.isScrubbing = false;
    state.lastSyncPos = targetPos;
    state.lastSyncTime = performance.now();

    send({
      action: 'seek',
      params: { position: targetPos }
    });
  }

  dom.scrubberInput.addEventListener('change', commitScrub);
  dom.scrubberInput.addEventListener('pointerup', commitScrub);
  dom.scrubberInput.addEventListener('touchend', commitScrub);

  // --- Transport Event Listeners ---
  function togglePlayPause(e) {
    if (e) {
      e.preventDefault();
      e.stopPropagation();
    }
    const isPlaying = state.playerState === 'playing';
    state.playerState = isPlaying ? 'paused' : 'playing';
    renderNowPlaying();
    send({ action: isPlaying ? 'pause' : 'play' });
  }

  dom.btnPlayPause.addEventListener('click', togglePlayPause);
  dom.miniBtnPlayPause.addEventListener('click', togglePlayPause);

  dom.btnNext.addEventListener('click', () => send({ action: 'next' }));
  dom.miniBtnNext.addEventListener('click', (e) => {
    e.stopPropagation();
    send({ action: 'next' });
  });

  dom.btnPrev.addEventListener('click', () => send({ action: 'previous' }));

  dom.btnShuffle.addEventListener('click', () => {
    send({
      action: 'set_shuffle',
      params: { enabled: !state.shuffle }
    });
  });

  dom.btnRepeat.addEventListener('click', () => {
    const modes = ['off', 'all', 'one'];
    const nextIdx = (modes.indexOf(state.repeatMode) + 1) % modes.length;
    const nextMode = modes[nextIdx];
    send({
      action: 'set_repeat',
      params: { mode: nextMode }
    });
  });

  dom.btnFavorite.addEventListener('click', () => {
    send({ action: 'favorite' });
  });

  dom.btnReconnect.addEventListener('click', () => {
    connectWebSocket();
  });

  // --- Audio Quality Modal Listeners ---
  dom.audioQualityBadge.addEventListener('click', () => {
    dom.qualityModal.classList.remove('hidden');
  });

  dom.btnCloseModal.addEventListener('click', () => {
    dom.qualityModal.classList.add('hidden');
  });

  dom.qualityModal.addEventListener('click', (e) => {
    if (e.target === dom.qualityModal) {
      dom.qualityModal.classList.add('hidden');
    }
  });

  // --- Queue View Handling ---
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

    const isAMR = playlistName === 'Очередь AMR' || Boolean(state.isRadio);
    if (isAMR) {
      const displayCount = total > 0 ? total : (upcoming.length + (state.track && state.track.name ? 1 : 0));
      dom.queueSubtitle.textContent = `Очередь AMR · ${displayCount} трек${displayCount === 1 ? '' : (displayCount >= 2 && displayCount <= 4 ? 'а' : 'ов')}`;
    } else {
      dom.queueSubtitle.textContent = `${upcoming.length} треков в очереди`;
    }

    renderCurrentQueueTrack(dom.queueCurrentTrack);
    renderQueueList(dom.queueUpcomingList, upcoming, 'upcoming');
  }

  let lastCurrentQueueTrackKey = '';
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
        <img class="track-thumb" src="${artSrc}" alt="" loading="lazy" onerror="this.onerror=null;this.src='apple-touch-icon.svg';">
        <div class="track-details">
          <span class="track-row-title">${escapeHtml(cur.name || 'Без названия')}</span>
          <span class="track-row-artist">${escapeHtml(cur.artist || 'Неизвестный исполнитель')}</span>
        </div>
        <span class="track-row-dur">${dur}</span>
      </div>
    `;
  }

  const lastQueueListKey = { upcoming: '', history: '' };
  function renderQueueList(container, tracks, type) {
    if (!container) return;
    if (!tracks || tracks.length === 0) {
      container.innerHTML = `<div class="empty-state">${type === 'upcoming' ? 'Нет предстоящих треков' : 'История пуста'}</div>`;
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
        <img class="track-thumb" src="${artSrc}" alt="" loading="lazy" onerror="this.onerror=null;this.src='apple-touch-icon.svg';">
        <div class="track-details">
          <span class="track-row-title">${escapeHtml(t.name || 'Без названия')}</span>
          <span class="track-row-artist">${escapeHtml(t.artist || 'Неизвестный исполнитель')}</span>
        </div>
        <span class="track-row-dur">${dur}</span>
      `;

      row.addEventListener('click', () => {
        setUIBusy(true, 'Переход к треку...');
        if (type === 'upcoming') {
          send({ action: 'queue_play_index', params: { index: idx } });
        } else {
          send({ action: 'play_history_index', params: { index: idx } });
        }
      });

      container.appendChild(row);
    });
  }

  dom.btnClearQueue.addEventListener('click', () => {
    send({ action: 'queue_clear' });
  });

  // --- Library / Playlists Handling ---
  function updatePlaylists(data) {
    const list = data.playlists || (Array.isArray(data) ? data : []);
    state.playlists = list;

    if (list.length === 0) {
      dom.playlistsGrid.innerHTML = '<div class="empty-state">Плейлисты не найдены</div>';
      return;
    }

    dom.playlistsGrid.innerHTML = '';
    list.forEach(pl => {
      const card = document.createElement('div');
      card.className = 'playlist-card';
      const art = pl.artwork_url || pl.artworkUrl || 'apple-touch-icon.svg';
      const count = pl.track_count || pl.trackCount || 0;

      card.innerHTML = `
        <div class="playlist-card-art-wrap">
          <img class="playlist-card-art" src="${art}" alt="" loading="lazy" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
          <div class="playlist-card-art-fallback" style="display:none;">
            <svg viewBox="0 0 24 24" width="36" height="36" fill="none" stroke="#6e6e73" stroke-width="1.8">
              <path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>
            </svg>
          </div>
        </div>
        <span class="playlist-card-title">${escapeHtml(pl.name)}</span>
        <span class="playlist-card-count">${count} треков</span>
      `;

      card.addEventListener('click', () => {
        openPlaylistDetail(pl);
      });

      dom.playlistsGrid.appendChild(card);
    });
  }

  function navigateToView(viewId, desktopTab) {
    if (window.innerWidth < 768) {
      switchMobileView(viewId);
    } else {
      switchDesktopTab(desktopTab);
    }
  }

  function openPlaylistDetail(pl) {
    state.albumOpenedFromHome = false;
    state.currentPlaylistDetail = pl;
    if (dom.detailBadge) dom.detailBadge.textContent = 'ПЛЕЙЛИСТ';
    dom.detailTitle.textContent = pl.name;
    const count = pl.track_count || pl.trackCount || 0;
    dom.detailMeta.textContent = `${count} треков`;
    dom.detailArtwork.src = pl.artwork_url || pl.artworkUrl || 'apple-touch-icon.svg';
    dom.playlistTracksList.innerHTML = '<div class="loading-state">Загрузка треков...</div>';

    dom.playlistsBrowsePane.classList.add('hidden');
    dom.playlistDetailPane.classList.remove('hidden');

    send({
      action: 'get_playlist_tracks',
      params: { name: pl.name }
    });
  }

  function openAlbumDetail(alb, fromHome = true) {
    state.albumOpenedFromHome = fromHome;
    state.currentPlaylistDetail = { ...alb, isAlbum: true };
    if (dom.detailTitle) dom.detailTitle.textContent = alb.name || alb.title || 'Альбом';
    if (dom.detailMeta) dom.detailMeta.textContent = alb.artist || alb.sub || alb.subtitle || '';
    if (dom.detailArtwork) dom.detailArtwork.src = alb.artwork || alb.artwork_url || 'apple-touch-icon.svg';
    if (dom.detailBadge) dom.detailBadge.textContent = 'АЛЬБОМ';
    if (dom.playlistTracksList) dom.playlistTracksList.innerHTML = '<div class="loading-state">Загрузка треков альбома...</div>';

    navigateToView('view-library', 'library');
    if (dom.playlistsBrowsePane) dom.playlistsBrowsePane.classList.add('hidden');
    if (dom.playlistDetailPane) dom.playlistDetailPane.classList.remove('hidden');

    send({
      action: 'get_album',
      params: {
        id: alb.id || '',
        name: alb.name || alb.title || '',
        artist: alb.artist || alb.sub || alb.subtitle || '',
        country: state.trends.country || 'ru'
      }
    });
  }

  dom.btnBackToPlaylists.addEventListener('click', () => {
    dom.playlistDetailPane.classList.add('hidden');
    if (state.albumOpenedFromHome) {
      state.albumOpenedFromHome = false;
      navigateToView('view-home', 'home');
    } else {
      dom.playlistsBrowsePane.classList.remove('hidden');
    }
  });

  dom.btnRefreshLibrary.addEventListener('click', () => {
    dom.playlistsGrid.innerHTML = '<div class="loading-state">Загрузка плейлистов...</div>';
    send({ action: 'get_playlists' });
  });

  dom.btnPlayPlaylist.addEventListener('click', () => {
    if (!state.currentPlaylistDetail) return;
    const isAlbum = Boolean(state.currentPlaylistDetail.isAlbum);
    setUIBusy(true, isAlbum ? 'Запуск альбома...' : 'Запуск плейлиста...', dom.btnPlayPlaylist);
    if (isAlbum) {
      send({
        action: 'play_album',
        params: {
          id: state.currentPlaylistDetail.id || '',
          name: state.currentPlaylistDetail.name || state.currentPlaylistDetail.title || '',
          artist: state.currentPlaylistDetail.artist || state.currentPlaylistDetail.sub || state.currentPlaylistDetail.subtitle || '',
          shuffle: false
        }
      });
    } else {
      send({
        action: 'play_playlist',
        params: { playlist: state.currentPlaylistDetail.name, shuffle: false }
      });
    }
  });

  dom.btnShufflePlaylist.addEventListener('click', () => {
    if (!state.currentPlaylistDetail) return;
    const isAlbum = Boolean(state.currentPlaylistDetail.isAlbum);
    setUIBusy(true, 'Перемешивание...', dom.btnShufflePlaylist);
    if (isAlbum) {
      send({
        action: 'play_album',
        params: {
          id: state.currentPlaylistDetail.id || '',
          name: state.currentPlaylistDetail.name || state.currentPlaylistDetail.title || '',
          artist: state.currentPlaylistDetail.artist || state.currentPlaylistDetail.sub || state.currentPlaylistDetail.subtitle || '',
          shuffle: true
        }
      });
    } else {
      send({
        action: 'play_playlist',
        params: { playlist: state.currentPlaylistDetail.name, shuffle: true }
      });
    }
  });

  function updateAlbumDetails(data) {
    const alb = data.album || data;
    if (!alb) return;
    state.currentAlbumDetail = alb;
    state.currentPlaylistDetail = { ...alb, isAlbum: true };
    if (dom.detailTitle) dom.detailTitle.textContent = alb.name || 'Альбом';
    if (dom.detailMeta) {
      const parts = [];
      if (alb.artist) parts.push(alb.artist);
      if (alb.release_date) parts.push(alb.release_date.slice(0, 4));
      if (alb.track_count) parts.push(`${alb.track_count} треков`);
      dom.detailMeta.textContent = parts.join(' • ');
    }
    if (dom.detailArtwork && (alb.artwork || alb.artwork_url)) {
      dom.detailArtwork.src = alb.artwork || alb.artwork_url;
    }
    if (dom.detailBadge) dom.detailBadge.textContent = 'АЛЬБОМ';

    const tracks = alb.tracks || [];
    if (tracks.length === 0) {
      dom.playlistTracksList.innerHTML = '<div class="empty-state">Нет треков</div>';
      return;
    }

    dom.playlistTracksList.innerHTML = '';
    tracks.forEach((t, idx) => {
      const row = document.createElement('div');
      row.className = 'track-row';
      const dur = formatTime(t.duration || 0);

      row.innerHTML = `
        <span class="track-index-num">${t.index || idx + 1}</span>
        <div class="track-details">
          <span class="track-row-title">${escapeHtml(t.name || 'Без названия')}</span>
          <span class="track-row-artist">${escapeHtml(t.artist || alb.artist || '')}</span>
        </div>
        <span class="track-row-dur">${dur}</span>
      `;

      row.addEventListener('click', () => {
        setUIBusy(true, 'Запуск трека...');
        send({
          action: 'play_album',
          params: {
            id: alb.id || '',
            name: alb.name || '',
            artist: alb.artist || '',
            track_index: idx + 1,
            shuffle: false
          }
        });
      });

      dom.playlistTracksList.appendChild(row);
    });
  }

  function updatePlaylistTracks(data) {
    const tracks = data.tracks || [];
    if (!tracks || tracks.length === 0) {
      dom.playlistTracksList.innerHTML = '<div class="empty-state">Плейлист пуст</div>';
      return;
    }

    dom.playlistTracksList.innerHTML = '';
    tracks.forEach((t, idx) => {
      const row = document.createElement('div');
      row.className = 'track-row';
      const dur = formatTime(t.duration || 0);

      row.innerHTML = `
        <span class="track-index-num">${idx + 1}</span>
        <div class="track-details">
          <span class="track-row-title">${escapeHtml(t.name || 'Без названия')}</span>
          <span class="track-row-artist">${escapeHtml(t.artist || '')} &bull; ${escapeHtml(t.album || '')}</span>
        </div>
        <span class="track-row-dur">${dur}</span>
      `;

      row.addEventListener('click', () => {
        if (!state.currentPlaylistDetail) return;
        setUIBusy(true, 'Запуск трека...');
        send({
          action: 'play_playlist',
          params: {
            playlist: state.currentPlaylistDetail.name,
            track_index: idx + 1,
            track_id: t.numeric_id || t.id
          }
        });
      });

      dom.playlistTracksList.appendChild(row);
    });
  }

  // --- Search Handling ---
  let searchDebounceTimer = null;

  dom.searchInput.addEventListener('input', function (e) {
    const q = e.target.value.trim();
    state.searchQuery = q;
    dom.btnClearSearch.classList.toggle('hidden', q.length === 0);

    clearTimeout(searchDebounceTimer);
    if (!q) {
      dom.searchResults.innerHTML = `
        <div class="search-placeholder">
          <svg viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="#38383a" stroke-width="1.5">
            <circle cx="11" cy="11" r="8"/>
            <line x1="21" y1="21" x2="16.65" y2="16.65"/>
          </svg>
          <p>Ищите любимые треки, альбомы и исполнителей</p>
        </div>`;
      return;
    }

    searchDebounceTimer = setTimeout(() => {
      executeSearch(q, state.searchScope);
    }, 280);
  });

  dom.btnClearSearch.addEventListener('click', () => {
    dom.searchInput.value = '';
    dom.btnClearSearch.classList.add('hidden');
    state.searchQuery = '';
    dom.searchResults.innerHTML = `
      <div class="search-placeholder">
        <svg viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="#38383a" stroke-width="1.5">
          <circle cx="11" cy="11" r="8"/>
          <line x1="21" y1="21" x2="16.65" y2="16.65"/>
        </svg>
        <p>Ищите любимые треки, альбомы и исполнителей</p>
      </div>`;
  });

  dom.filterChips.forEach(chip => {
    chip.addEventListener('click', () => {
      dom.filterChips.forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      state.searchScope = chip.dataset.scope;
      if (state.searchQuery) {
        executeSearch(state.searchQuery, state.searchScope);
      }
    });
  });

  function executeSearch(query, scope) {
    dom.searchResults.innerHTML = '<div class="loading-state">Поиск в каталоге Apple Music...</div>';
    send({
      action: 'search',
      params: {
        query: query,
        country: 'ru',
        scope: scope
      }
    });
  }

  function updateSearchResults(data) {
    if (!data) {
      dom.searchResults.innerHTML = '<div class="empty-state">Ничего не найдено</div>';
      return;
    }

    const songs = data.songs || [];
    const albums = data.albums || [];
    const artists = data.artists || [];

    if (songs.length === 0 && albums.length === 0 && artists.length === 0) {
      dom.searchResults.innerHTML = '<div class="empty-state">Ничего не найдено</div>';
      return;
    }

    dom.searchResults.innerHTML = '';

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
        playSearchResultsList(songs, false);
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
        playSearchResultsList(songs, true);
      });

      actionsBar.appendChild(btnPlayAll);
      actionsBar.appendChild(btnShuffle);
      headerRow.appendChild(actionsBar);
      dom.searchResults.appendChild(headerRow);

      const list = document.createElement('div');
      list.className = 'track-list';
      songs.forEach(s => {
        const row = document.createElement('div');
        row.className = 'track-row';
        const artSrc = s.artwork_url || s.artwork || 'apple-touch-icon.svg';
        const isLocal = Boolean(s.is_local || s.isLocal);
        const localBadge = isLocal ? '<span class="badge-library">МЕДИАТЕКА</span>' : '';

        row.innerHTML = `
          <img class="track-thumb" src="${artSrc}" alt="" loading="lazy" onerror="this.onerror=null;this.src='apple-touch-icon.svg';">
          <div class="track-details">
            <div class="track-row-title-wrap">
              <span class="track-row-title">${escapeHtml(s.name || s.trackName || '')}</span>
              ${localBadge}
            </div>
            <span class="track-row-artist">${escapeHtml(s.artist || s.artistName || '')}</span>
          </div>
        `;

        row.addEventListener('click', () => {
          setUIBusy(true, 'Запуск трека...');
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

        list.appendChild(row);
      });
      dom.searchResults.appendChild(list);
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
          <img class="playlist-card-art" src="${art}" alt="" loading="lazy">
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
          }, false);
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

  function playSearchResultsList(songs, shuffle) {
    if (!songs || songs.length === 0) return;
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
      action: 'play_search_results',
      params: {
        tracks: formatted,
        shuffle: Boolean(shuffle)
      }
    });

    if (dom.btnPlayPause) {
      dom.btnPlayPause.classList.add('loading-pulse');
      setTimeout(() => dom.btnPlayPause.classList.remove('loading-pulse'), 1200);
    }
  }

  // --- Trends & Recommendations Handling ---

  // --- Главная (Home) & Trends Handling ---

  const DEFAULT_STATIONS = [
    {
      id: 'station_personal',
      name: 'Моя станция',
      subtitle: 'Кирилл Шолохов',
      color: 'linear-gradient(145deg, #fa233b 0%, #fb5c74 45%, #ff8a65 100%)',
      artwork: '/assets/stations/CoverPersonal.png',
      url: 'https://music.apple.com/station/my-station/ra.u-96b95a031a2fb0aa1abb70ff757aa95f',
      isLive: false
    },
    {
      id: 'station_discovery',
      name: 'В моем вкусе',
      subtitle: 'Станция открытий',
      color: 'linear-gradient(135deg, #7928ca, #ff0080)',
      artwork: '/assets/stations/CoverDiscovery.png',
      url: 'https://music.apple.com/station/item/ra.q-GAI6IDk2Yjk1YTAzMWEyZmIwYWExYWJiNzBmZjc1N2FhOTVm',
      isLive: false
    },
    {
      id: 'station_am1',
      name: 'Apple Music 1',
      subtitle: 'Главные мировые релизы',
      color: 'linear-gradient(135deg, #1c1c1e, #3a3a3c)',
      artwork: '/assets/stations/CoverAppleMusic1.png',
      url: 'https://music.apple.com/us/station/apple-music-1/ra.978194965',
      isLive: true
    },
    {
      id: 'station_hits',
      name: 'Apple Music Hits',
      subtitle: 'Культовые хиты',
      color: 'linear-gradient(135deg, #ff0844, #ffb199)',
      artwork: '/assets/stations/CoverPersonal.png',
      url: 'https://music.apple.com/us/station/apple-music-hits/ra.1498155548',
      isLive: true
    },
    {
      id: 'station_country',
      name: 'Apple Music Country',
      subtitle: 'Современное кантри',
      color: 'linear-gradient(135deg, #f7971e, #ffd200)',
      artwork: '/assets/stations/CoverDiscovery.png',
      url: 'https://music.apple.com/us/station/apple-music-country/ra.1498157166',
      isLive: true
    },
    {
      id: 'station_chill',
      name: 'Chill & Lo-Fi',
      subtitle: 'Спокойный ритм и фоновые биты',
      color: 'linear-gradient(135deg, #00b4db, #0083b0)',
      artwork: '/assets/stations/CoverChill.png',
      url: 'https://music.apple.com/us/station/chill-station/ra.985484943',
      isLive: false
    },
    {
      id: 'station_pop',
      name: 'Pop Hits',
      subtitle: 'Популярные поп-треки',
      color: 'linear-gradient(135deg, #fa2d48, #ff6b8b)',
      artwork: '/assets/stations/CoverPop.png',
      url: 'https://music.apple.com/us/station/hits-station/ra.985480047',
      isLive: false
    },
    {
      id: 'station_electronic',
      name: 'Dance & Electronic',
      subtitle: 'Клубный драйв и энергия',
      color: 'linear-gradient(135deg, #ff0844, #ffb199)',
      artwork: '/assets/stations/CoverElectronic.png',
      url: 'https://music.apple.com/us/station/dance-station/ra.985487895',
      isLive: false
    },
    {
      id: 'station_deephouse',
      name: 'Deep House',
      subtitle: 'Глубокий атмосферный грув',
      color: 'linear-gradient(135deg, #1f1c2c, #928dab)',
      artwork: '/assets/stations/CoverDeepHouse.png',
      url: 'https://music.apple.com/us/station/house-station/ra.991194049',
      isLive: false
    },
    {
      id: 'station_rock',
      name: 'Rock Classics',
      subtitle: 'Классика мирового рока',
      color: 'linear-gradient(135deg, #232526, #414345)',
      artwork: '/assets/stations/CoverRock.png',
      url: 'https://music.apple.com/us/station/classic-rock-station/ra.985500514',
      isLive: false
    }
  ];

  const DEFAULT_GENRES = [
    { name: '🔥 Поп-музыка', query: 'Pop Hits' },
    { name: '🎸 Рок & Альтернатива', query: 'Rock Classics' },
    { name: '🎤 Хип-хоп & Рэп', query: 'Hip Hop' },
    { name: '⚡ Электроника & Dance', query: 'Dance Electronic' },
    { name: '☕ Chill & Lo-Fi', query: 'Chill Beats' },
    { name: '🎻 Неоклассика', query: 'Neoclassical' },
    { name: '🎬 Саундтреки', query: 'Soundtrack' }
  ];

  function loadTrends(country) {
    if (country) {
      state.trends.country = country;
    }
    const c = state.trends.country || 'ru';

    if (dom.trendsCountryPills) {
      dom.trendsCountryPills.forEach(pill => {
        pill.classList.toggle('active', pill.dataset.country === c);
      });
    }

    send({
      action: 'get_catalog_charts',
      params: { country: c }
    });

    send({
      action: 'get_explore',
      params: { country: c }
    });
  }

  function updateCatalogCharts(data) {
    // Top charts removed per user request
  }

  function updateExploreFeed(data) {
    if (!data) return;

    if (data.stations && data.stations.length > 0) {
      state.trends.stations = data.stations;
    }
    if (data.top_albums && data.top_albums.length > 0) {
      state.trends.topAlbums = data.top_albums;
    }
    if (data.genres && data.genres.length > 0) {
      state.trends.genres = data.genres;
    }

    // 1. Render Hero Featured Carousel (Подборка лучших)
    renderHeroCarousel(data);

    // 2. Render Recently Played (Вы недавно слушали ›)
    const recents = (data.recently_played && data.recently_played.length > 0)
      ? data.recently_played
      : (data.top_picks || []);
    state.recentlyPlayed = recents;
    renderRecentlyPlayed(recents);

    // 3. Render Stations (Станции для вас ›)
    renderHomeStations(state.trends.stations || DEFAULT_STATIONS);

    // 4. Render Popular Albums (Популярные альбомы ›)
    if (state.trends.topAlbums && state.trends.topAlbums.length > 0) {
      renderHomeAlbums(state.trends.topAlbums);
    }

    // 5. Render Genres
    renderHomeGenres(state.trends.genres || DEFAULT_GENRES);
  }

  // Render Hero Carousel (Подборка лучших)
  function renderHeroCarousel(data) {
    if (!dom.homeHeroCarousel) return;
    dom.homeHeroCarousel.innerHTML = '';

    const heroCards = [];

    if (data.hero_cards && data.hero_cards.length > 0) {
      data.hero_cards.forEach(c => {
        let art = c.artwork || '';
        const lowerTitle = (c.title || '').toLowerCase();
        if (!art || (art.includes('mzstatic') && (lowerTitle.includes('моя станция') || lowerTitle.includes('в моем вкусе') || lowerTitle.includes('заряд') || lowerTitle.includes('one ok rock')))) {
          if (lowerTitle.includes('моя станция')) art = '/assets/stations/CoverPersonal.png';
          else if (lowerTitle.includes('в моем вкусе') || lowerTitle.includes('открытий')) art = '/assets/stations/CoverDiscovery.png';
          else if (lowerTitle.includes('заряд') || lowerTitle.includes('энерг')) art = '/assets/stations/CoverElectronic.png';
          else if (lowerTitle.includes('one ok rock') || lowerTitle.includes('рок')) art = '/assets/stations/CoverRock.png';
        }

        heroCards.push({
          index: c.index || 0,
          title: c.title || 'Apple Music',
          sub: c.subtitle || c.sub || '',
          tag: c.tag || 'Специально для вас',
          id: c.id || '',
          type: c.type || 'station',
          url: c.url || '',
          artwork: art
        });
      });
    } else {
      // Variant 3 Hybrid Hero Cards
      heroCards.push(
        {
          index: 1,
          title: 'Моя станция',
          sub: 'Персональная радиостанция',
          tag: 'Специально для вас',
          id: 'ra.u-96b95a031a2fb0aa1abb70ff757aa95f',
          type: 'station',
          url: 'https://music.apple.com/station/my-station/ra.u-96b95a031a2fb0aa1abb70ff757aa95f',
          artwork: '/assets/stations/CoverPersonal.png'
        },
        {
          index: 2,
          title: 'Станция открытий',
          sub: 'Новые треки под ваш вкус',
          tag: 'Радиостанция',
          id: 'ra.q-GAI6IDk2Yjk1YTAzMWEyZmIwYWExYWJiNzBmZjc1N2FhOTVm',
          type: 'station',
          url: 'https://music.apple.com/station/item/ra.q-GAI6IDk2Yjk1YTAzMWEyZmIwYWExYWJiNzBmZjc1N2FhOTVm',
          artwork: '/assets/stations/CoverDiscovery.png'
        },
        {
          index: 3,
          title: 'Любимые песни',
          sub: 'Плейлист медиатеки',
          tag: 'Медиатека',
          id: 'Любимые песни',
          type: 'playlist',
          url: '',
          artwork: '/api/artwork/playlist?name=%D0%9B%D1%8E%D0%B1%D0%B8%D0%BC%D1%8B%D0%B5%20%D0%BF%D0%B5%D1%81%D0%BD%D0%B8'
        },
        {
          index: 4,
          title: 'Ностальгия по ню-металу',
          sub: 'Плейлист медиатеки',
          tag: 'Медиатека',
          id: 'Ностальгия по ню-металу',
          type: 'playlist',
          url: '',
          artwork: '/api/artwork/playlist?name=%D0%9D%D0%BE%D1%81%D1%82%D0%B0%D0%BB%D1%8C%D0%B3%D0%B8%D1%8F%20%D0%BF%D0%BE%20%D0%BD%D1%8E-%D0%BC%D0%B5%D1%82%D0%B0%D0%BB%D1%83'
        },
        {
          index: 5,
          title: 'Легенда',
          sub: 'Кино',
          tag: 'Топ-альбом',
          id: '1375628135',
          type: 'album',
          url: 'https://music.apple.com/album/1375628135',
          artwork: 'https://is1-ssl.mzstatic.com/image/thumb/Music118/v4/c7/99/1e/c7991ed1-bee2-8c46-2e66-81d0b8e7eeb2/cover.jpg/600x600bb.jpg'
        },
        {
          index: 6,
          title: 'Mutter',
          sub: 'Rammstein',
          tag: 'Топ-альбом',
          id: '1440770702',
          type: 'album',
          url: 'https://music.apple.com/album/1440770702',
          artwork: 'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/b8/91/bf/b891bf2e-0658-690a-115f-c2ee53f3192e/00602527296685.rgb.jpg/600x600bb.jpg'
        },
        {
          index: 7,
          title: 'Акустический альбом',
          sub: 'Король и Шут',
          tag: 'Топ-альбом',
          id: '1440751918',
          type: 'album',
          url: 'https://music.apple.com/album/1440751918',
          artwork: 'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/44/9a/c0/449ac06f-40e1-7c59-bf7b-6ae9be2d7b14/4607062440191.jpg/600x600bb.jpg'
        }
      );
    }

    heroCards.forEach(c => {
      const el = document.createElement('div');
      el.className = 'hero-card';
      el.setAttribute('data-index', c.index);

      const hasArt = c.artwork && c.artwork.trim().length > 0;
      const mediaHtml = hasArt ? `
        <img class="hero-art-img" src="${c.artwork}" alt="${escapeHtml(c.title)}" loading="eager" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
        <div class="hero-art-fallback" style="display:none;">
          <svg viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="currentColor" stroke-width="1.8">
            <path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>
          </svg>
        </div>
      ` : `
        <div class="hero-art-gradient" style="background: linear-gradient(135deg, #fa233b, #fb5c74)">
          <svg viewBox="0 0 24 24" width="56" height="56" fill="none" stroke="#ffffff" stroke-width="1.8">
            <path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>
          </svg>
        </div>
      `;

      el.innerHTML = `
        <div class="hero-card-header">
          <span class="hero-tag">${escapeHtml(c.tag)}</span>
          <span class="hero-title">${escapeHtml(c.title)}</span>
          <span class="hero-sub">${escapeHtml(c.sub)}</span>
        </div>
        <div class="hero-card-media">
          ${mediaHtml}
          <button class="hero-play-btn" type="button" aria-label="Воспроизвести">
            <svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor">
              <polygon points="6 4 20 12 6 20 6 4"/>
            </svg>
          </button>
        </div>
      `;

      el.addEventListener('click', (e) => {
        const isPlayBtn = Boolean(e.target.closest('.hero-play-btn'));
        if (c.type === 'album' && !isPlayBtn) {
          openAlbumDetail(c, true);
          return;
        }
        if (c.type === 'playlist' && !isPlayBtn) {
          openPlaylistDetail({ name: c.id || c.title });
          return;
        }

        setUIBusy(true, 'Запуск...');
        send({
          action: 'play_hero_card',
          params: {
            index: c.index,
            name: c.title,
            artist: c.sub || c.subtitle || c.artist || '',
            id: c.id,
            url: c.url,
            type: c.type
          }
        });
        if (dom.btnPlayPause) {
          dom.btnPlayPause.classList.add('loading-pulse');
          setTimeout(() => dom.btnPlayPause.classList.remove('loading-pulse'), 1200);
        }
      });

      dom.homeHeroCarousel.appendChild(el);
    });
  }

  // Render Recently Played (Вы недавно слушали ›)
  function renderRecentlyPlayed(recentTracks) {
    if (!dom.homeRecentCarousel) return;
    const list = recentTracks && recentTracks.length > 0 ? recentTracks : [];
    if (list.length === 0) {
      if (dom.homeRecentSection) dom.homeRecentSection.classList.add('hidden');
      return;
    }
    if (dom.homeRecentSection) dom.homeRecentSection.classList.remove('hidden');
    dom.homeRecentCarousel.innerHTML = '';

    list.forEach(t => {
      const card = document.createElement('div');
      card.className = 'media-card';
      const art = t.artwork || (t.id ? `/api/artwork/track?id=${t.id}` : 'apple-touch-icon.svg');

      card.innerHTML = `
        <div class="media-card-art-wrap">
          <img class="media-card-art" src="${art}" alt="" loading="lazy" onerror="this.style.display='none'; this.parentElement.classList.add('has-fallback');">
          <div class="media-card-art-fallback" style="background: linear-gradient(135deg, #1c1c1e, #2c2c2e);">
            <svg viewBox="0 0 24 24" width="28" height="28" fill="none" stroke="#6e6e73" stroke-width="1.8">
              <path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>
            </svg>
          </div>
          <div class="media-play-overlay">
            <div class="media-play-pill">
              <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
                <polygon points="7 4 19 12 7 20 7 4"/>
              </svg>
            </div>
          </div>
        </div>
        <span class="media-card-title">${escapeHtml(t.name || 'Без названия')}</span>
        <span class="media-card-sub">${escapeHtml(t.artist || t.album || 'Apple Music')}</span>
      `;

      card.addEventListener('click', () => {
        setUIBusy(true, 'Запуск трека...');
        send({
          action: 'play_cloud',
          params: {
            id: `${t.id || ''}`,
            numeric_id: parseInt(t.id, 10) || 0,
            name: t.name || '',
            artist: t.artist || '',
            url: t.url || '',
            artwork: art
          }
        });
      });

      dom.homeRecentCarousel.appendChild(card);
    });
  }

  // Render Stations (Станции для вас ›)
  function renderHomeStations(stations) {
    const container = dom.homeStationsCarousel || dom.trendsStationsGrid;
    if (!container) return;
    const list = stations && stations.length > 0 ? stations : DEFAULT_STATIONS;

    container.innerHTML = '';
    list.forEach(st => {
      const card = document.createElement('div');
      card.className = 'media-card station-card';
      const isLive = Boolean(st.isLive || st.is_live);
      const gradient = st.color || 'linear-gradient(135deg, #1c1c1e, #2c2c2e)';
      const iconSvg = st.icon || '<svg viewBox="0 0 24 24" width="36" height="36" fill="currentColor"><circle cx="12" cy="12" r="3.2"/><path d="M12 6c-2.76 0-5 2.24-5 5 0 1.63.79 3.08 2 3.99V22l3-2 3 2v-7.01c1.21-.91 2-2.36 2-3.99 0-2.76-2.24-5-5-5z"/></svg>';
      const hasImage = Boolean(st.artwork && st.artwork.trim().length > 0 && !st.artwork.includes('apple-touch-icon'));

      const artHtml = hasImage
        ? `<img class="media-card-art" src="${st.artwork}" alt="" loading="lazy" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
           <div class="media-card-art-fallback" style="display:none; background: ${gradient};">
             ${iconSvg}
             <span class="station-art-fallback-title">${escapeHtml(st.name || 'Радио')}</span>
           </div>`
        : `<div class="media-card-art-fallback" style="background: ${gradient};">
             ${iconSvg}
             <span class="station-art-fallback-title">${escapeHtml(st.name || 'Радио')}</span>
           </div>`;

      card.innerHTML = `
        <div class="media-card-art-wrap">
          ${artHtml}
          ${isLive ? '<span class="live-badge">LIVE</span>' : ''}
          <div class="media-play-overlay">
            <div class="media-play-pill">
              <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
                <polygon points="7 4 19 12 7 20 7 4"/>
              </svg>
            </div>
          </div>
        </div>
        <span class="media-card-title">${escapeHtml(st.name || 'Радиостанция')}</span>
        <span class="media-card-sub">${escapeHtml(st.subtitle || (isLive ? 'Прямой эфир Apple Music' : 'Персональная станция'))}</span>
      `;

      card.addEventListener('click', () => {
        setUIBusy(true, 'Подключение к станции...');
        send({
          action: 'play_station',
          params: {
            url: st.url || '',
            name: st.name || 'Apple Music Radio'
          }
        });
      });

      container.appendChild(card);
    });
  }

  // Drill-down for Recently Played (Вы недавно слушали ›)
  if (dom.homeRecentLink) {
    dom.homeRecentLink.addEventListener('click', () => {
      openRecentDetail();
    });
  }

  if (dom.btnBackFromRecent) {
    dom.btnBackFromRecent.addEventListener('click', () => {
      closeRecentDetail();
    });
  }

  if (dom.btnPlayRecentAll) {
    dom.btnPlayRecentAll.addEventListener('click', () => {
      setUIBusy(true, 'Воспроизведение...', dom.btnPlayRecentAll);
      send({ action: 'play_recent', params: { shuffle: false } });
    });
  }

  if (dom.btnShuffleRecentAll) {
    dom.btnShuffleRecentAll.addEventListener('click', () => {
      setUIBusy(true, 'Перемешивание...', dom.btnShuffleRecentAll);
      send({ action: 'play_recent', params: { shuffle: true } });
    });
  }

  function openRecentDetail() {
    if (dom.viewHome) dom.viewHome.classList.remove('active');
    if (dom.recentDetailPane) {
      dom.recentDetailPane.classList.remove('hidden');
      dom.recentDetailPane.classList.add('active');
    }
    renderRecentFullList();
  }

  function closeRecentDetail() {
    if (dom.recentDetailPane) {
      dom.recentDetailPane.classList.remove('active');
      dom.recentDetailPane.classList.add('hidden');
    }
    if (dom.viewHome) {
      dom.viewHome.classList.add('active');
    }
  }

  function renderRecentFullList() {
    if (!dom.recentTracksFullList) return;
    const list = state.recentlyPlayed && state.recentlyPlayed.length > 0 ? state.recentlyPlayed : [];
    if (dom.recentTotalCount) {
      dom.recentTotalCount.textContent = `${list.length} треков`;
    }
    if (list.length === 0) {
      dom.recentTracksFullList.innerHTML = '<div class="empty-state">Нет недавних треков</div>';
      return;
    }

    dom.recentTracksFullList.innerHTML = '';
    list.forEach((t, idx) => {
      const row = document.createElement('div');
      row.className = 'track-row';
      const art = t.artwork || (t.id ? `/api/artwork/track?id=${t.id}` : 'apple-touch-icon.svg');
      const dur = t.duration ? formatTime(t.duration) : '';

      row.innerHTML = `
        <span class="track-index-num">${idx + 1}</span>
        <img class="track-thumb" src="${art}" alt="" loading="lazy" onerror="this.src='apple-touch-icon.svg'">
        <div class="track-details">
          <span class="track-row-title">${escapeHtml(t.name || 'Без названия')}</span>
          <span class="track-row-artist">${escapeHtml(t.artist || '')}${t.album ? ' &bull; ' + escapeHtml(t.album) : ''}</span>
        </div>
        ${dur ? `<span class="track-row-dur">${dur}</span>` : ''}
        <button class="btn-chart-play" type="button" aria-label="Слушать">
          <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor">
            <polygon points="6 3 20 12 6 21 6 3"/>
          </svg>
        </button>
      `;

      row.addEventListener('click', () => {
        setUIBusy(true, 'Запуск трека...');
        send({
          action: 'play_cloud',
          params: {
            id: `${t.id || ''}`,
            numeric_id: parseInt(t.id, 10) || 0,
            name: t.name || '',
            artist: t.artist || '',
            url: t.url || '',
            artwork: art
          }
        });
      });

      dom.recentTracksFullList.appendChild(row);
    });
  }

  // Render Popular Albums (Популярные альбомы ›)
  function renderHomeAlbums(albums) {
    const container = dom.homeAlbumsCarousel || dom.trendsAlbumsGrid;
    if (!container) return;
    if (!albums || albums.length === 0) {
      container.innerHTML = '<div class="empty-state">Нет данных по альбомам</div>';
      return;
    }

    container.innerHTML = '';
    albums.forEach(alb => {
      const card = document.createElement('div');
      card.className = 'media-card album-card';
      const art = alb.artwork_url || alb.artwork || 'apple-touch-icon.svg';

      card.innerHTML = `
        <div class="media-card-art-wrap">
          <img class="media-card-art" src="${art}" alt="" loading="lazy">
          <div class="media-play-overlay">
            <div class="media-play-pill">
              <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
                <polygon points="7 4 19 12 7 20 7 4"/>
              </svg>
            </div>
          </div>
        </div>
        <span class="media-card-title">${escapeHtml(alb.name || '')}</span>
        <span class="media-card-sub">${escapeHtml(alb.artist || '')}</span>
      `;

      card.addEventListener('click', (e) => {
        const isPlayBtn = Boolean(e.target.closest('.media-play-overlay'));
        if (!isPlayBtn) {
          openAlbumDetail({
            id: `${alb.id || ''}`,
            name: alb.name || '',
            artist: alb.artist || '',
            artwork: art,
            url: alb.url || ''
          }, true);
          return;
        }

        setUIBusy(true, 'Запуск альбома...');
        send({
          action: 'play_album',
          params: {
            id: `${alb.id || ''}`,
            name: alb.name || '',
            artist: alb.artist || '',
            url: alb.url || '',
            shuffle: false
          }
        });
      });

      container.appendChild(card);
    });
  }

  // Render Genres (Жанры и категории ›)
  function renderHomeGenres(genres) {
    const container = dom.homeGenresGrid || dom.trendsGenresGrid;
    if (!container) return;
    const list = genres && genres.length > 0 ? genres : DEFAULT_GENRES;

    container.innerHTML = '';
    list.forEach(g => {
      const chip = document.createElement('button');
      chip.type = 'button';
      chip.className = 'genre-card';
      chip.innerHTML = `
        <span class="genre-title">${escapeHtml(g.name || '')}</span>
        <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">
          <polyline points="9 18 15 12 9 6"/>
        </svg>
      `;

      chip.addEventListener('click', () => {
        selectGenre(g.query || g.name || '');
      });

      container.appendChild(chip);
    });
  }

  // Aliases for compatibility
  const renderTrendsStations = renderHomeStations;
  const renderTrendsTopSongs = () => {};
  const renderTrendsAlbums = renderHomeAlbums;
  const renderTrendsGenres = renderHomeGenres;

  function selectGenre(genreQuery) {
    const cleanQ = genreQuery.replace(/^[^\w\sа-яА-ЯёЁ]+/, '').trim();
    dom.searchInput.value = cleanQ;
    state.searchQuery = cleanQ;
    dom.btnClearSearch.classList.remove('hidden');

    const isDesktop = window.innerWidth >= 768;
    if (isDesktop) {
      switchDesktopTab('search');
    } else {
      switchMobileView('view-search');
    }

    executeSearch(cleanQ, state.searchScope);
  }

  // Country pill toggles
  if (dom.trendsCountryPills) {
    dom.trendsCountryPills.forEach(pill => {
      pill.addEventListener('click', () => {
        const country = pill.dataset.country;
        if (country && country !== state.trends.country) {
          state.trends.country = country;
          dom.trendsCountryPills.forEach(p => p.classList.toggle('active', p.dataset.country === country));
          if (dom.trendsSongsList) dom.trendsSongsList.innerHTML = '<div class="loading-state">Загрузка топ-чартов...</div>';
          if (dom.trendsAlbumsGrid) dom.trendsAlbumsGrid.innerHTML = '<div class="loading-state">Загрузка альбомов...</div>';
          loadTrends(country);
        }
      });
    });
  }

  // --- Navigation & View Switching ---

  // Mobile Bottom Tab Bar
  dom.tabItems.forEach(tab => {
    tab.addEventListener('click', () => {
      const targetViewId = tab.dataset.view;
      switchMobileView(targetViewId);
    });
  });

  function switchMobileView(viewId) {
    state.activeView = viewId;

    dom.tabItems.forEach(item => {
      item.classList.toggle('active', item.dataset.view === viewId);
    });

    // Hide all views first
    dom.viewNowPlaying.classList.remove('active');
    dom.viewQueue.classList.remove('active');
    dom.viewLibrary.classList.remove('active');
    if (dom.viewHome) dom.viewHome.classList.remove('active');
    if (dom.viewTrends) dom.viewTrends.classList.remove('active');
    if (dom.recentDetailPane) {
      dom.recentDetailPane.classList.remove('active');
      dom.recentDetailPane.classList.add('hidden');
    }
    dom.viewSearch.classList.remove('active');

    // Activate selected view
    const target = document.getElementById(viewId);
    if (target) {
      target.classList.add('active');
    }

    // Manage Mini-Player visibility on mobile
    if (viewId === 'view-now-playing') {
      dom.miniPlayer.classList.add('hidden');
    } else {
      dom.miniPlayer.classList.remove('hidden');
    }

    if (viewId === 'view-library') {
      if (dom.playlistsBrowsePane) dom.playlistsBrowsePane.classList.remove('hidden');
      if (dom.playlistDetailPane) dom.playlistDetailPane.classList.add('hidden');
      send({ action: 'get_playlists' });
    } else if (viewId === 'view-queue') {
      send({ action: 'get_queue' });
    } else if (viewId === 'view-home' || viewId === 'view-trends') {
      loadTrends();
    }
  }

  // Tapping Mini-Player body expands Now Playing
  dom.miniTrigger.addEventListener('click', () => {
    switchMobileView('view-now-playing');
  });

  // Desktop Navigation
  dom.desktopNavButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      const target = btn.dataset.target;
      switchDesktopTab(target);
    });
  });

  function switchDesktopTab(tabName) {
    state.desktopActiveTab = tabName;

    dom.desktopNavButtons.forEach(b => {
      b.classList.toggle('active', b.dataset.target === tabName);
    });

    dom.viewQueue.classList.remove('active');
    dom.viewLibrary.classList.remove('active');
    if (dom.viewHome) dom.viewHome.classList.remove('active');
    if (dom.viewTrends) dom.viewTrends.classList.remove('active');
    if (dom.recentDetailPane) {
      dom.recentDetailPane.classList.remove('active');
      dom.recentDetailPane.classList.add('hidden');
    }
    dom.viewSearch.classList.remove('active');

    if (tabName === 'home' || tabName === 'trends') {
      if (dom.viewHome) dom.viewHome.classList.add('active');
      else if (dom.viewTrends) dom.viewTrends.classList.add('active');
      loadTrends();
    } else if (tabName === 'queue') {
      dom.viewQueue.classList.add('active');
      send({ action: 'get_queue' });
    } else if (tabName === 'library') {
      dom.viewLibrary.classList.add('active');
      if (dom.playlistsBrowsePane) dom.playlistsBrowsePane.classList.remove('hidden');
      if (dom.playlistDetailPane) dom.playlistDetailPane.classList.add('hidden');
      send({ action: 'get_playlists' });
    } else if (tabName === 'search') {
      dom.viewSearch.classList.add('active');
      dom.searchInput.focus();
    }
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

  // Handle responsive layout changes on resize
  function handleResize() {
    const isDesktop = window.innerWidth >= 768;
    if (isDesktop) {
      // On desktop, ensure right column displays active desktop tab
      switchDesktopTab(state.desktopActiveTab);
    } else {
      // On mobile, ensure active mobile view is respected
      switchMobileView(state.activeView);
    }
  }
  window.addEventListener('resize', handleResize);

  // Initialize
  renderHeroCarousel({});
  renderHomeStations(DEFAULT_STATIONS);
  renderHomeGenres(DEFAULT_GENRES);
  handleResize();
  connectWebSocket();

})();
