//
//  WebUIContent+JS.swift
//  AppleMusicRemoteMac
//

import Foundation

extension WebUIContent {
    public static let appJS: String = #"""
/**
 * Apple Music Remote (AMR) - Client Application
 * Pure Vanilla JS (ES6+), Zero Dependencies.
 */

(function () {
  'use strict';

  // --- PWA Service Worker Registration ---
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('/sw.js').catch((err) => {
        console.warn('AMR ServiceWorker registration:', err);
      });
    });
  }

  // --- Application State ---
  const state = {
    connected: false,
    playbackState: 'stopped', // 'playing', 'paused', 'stopped'
    playerState: 'stopped', // 'playing', 'paused', 'stopped'
    pendingPlayUntil: 0,
    initialViewSelected: false,
    position: 0,
    duration: 0,
    volume: 100,
    previousVolume: 100,
    lockVolume100: localStorage.getItem('amr_lock_volume_100') !== null ? (localStorage.getItem('amr_lock_volume_100') === 'true') : true,
    isDraggingVolume: false,
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
    lastNonPlayerView: 'view-home',
    desktopActiveTab: 'home',

    // Audio Devices & DAC
    audioDeviceName: '',
    audioDeviceSampleRate: 44100,
    isBitPerfect: true,
    audioDevices: [],

    // Apple MusicKit & User Token
    hasUserToken: false,
    developerToken: '',
    userStorefront: 'us',
    isAccountSynced: false,
    accountHealth: null,

    // Scrubber local tracking
    isScrubbing: false,
    scrubValue: 0,
    lastSyncPos: 0,
    lastSyncTime: performance.now()
  };
  window.__amr_state = state;

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
    homeMixesSection: document.getElementById('home-mixes-section'),
    homeMixesLink: document.getElementById('home-mixes-link'),
    homeMixesCarousel: document.getElementById('home-mixes-carousel'),
    homeHeavySection: document.getElementById('home-heavy-section'),
    homeHeavyCarousel: document.getElementById('home-heavy-carousel'),
    homeRecContainer: document.getElementById('home-recommendations-container'),
    searchLanding: document.getElementById('search-landing'),
    homeStationsSection: document.getElementById('home-stations-section'),
    homeStationsLink: document.getElementById('home-stations-link'),
    homeStationsCarousel: document.getElementById('home-stations-carousel'),
    homeAlbumsSection: document.getElementById('home-albums-section'),
    homeAlbumsLink: document.getElementById('home-albums-link'),
    homeAlbumsCarousel: document.getElementById('home-albums-carousel'),
    homeGenresSection: document.getElementById('home-genres-section'),
    homeGenresGrid: document.getElementById('home-genres-grid'),

    // Section Tiles Grid View
    sectionGridView: document.getElementById('section-grid-view'),
    btnBackFromGrid: document.getElementById('btn-back-from-grid'),
    gridViewTitle: document.getElementById('grid-view-title'),
    sectionTilesGrid: document.getElementById('section-tiles-grid'),

    // Recently Played Full Pane
    recentDetailPane: document.getElementById('recent-detail-pane'),
    btnBackFromRecent: document.getElementById('btn-back-from-recent'),
    btnPlayRecentAll: document.getElementById('btn-play-recent-all'),
    btnShuffleRecentAll: document.getElementById('btn-shuffle-recent-all'),
    recentTracksFullList: document.getElementById('recent-tracks-full-list'),
    recentTotalCount: document.getElementById('recent-total-count'),

    headerAccountBadge: document.getElementById('header-account-badge'),
    headerAccountText: document.getElementById('header-account-text'),
    btnHeaderLogout: document.getElementById('btn-header-logout'),

    // Home Account Card & Diagnostic Modal
    homeAccountCard: document.getElementById('home-account-card'),
    accountCardEmail: document.getElementById('account-card-email'),
    accountCardBadge: document.getElementById('account-card-badge'),
    accountStatusDot: document.getElementById('account-status-dot'),
    accountCardSubtext: document.getElementById('account-card-subtext'),
    btnAccountDiag: document.getElementById('btn-account-diag'),
    modalAccountDiag: document.getElementById('modal-account-diag'),
    btnCloseAccountDiag: document.getElementById('btn-close-account-diag'),
    btnDoneAccountDiag: document.getElementById('btn-done-account-diag'),
    btnRefreshAccountDiag: document.getElementById('btn-refresh-account-diag'),
    diagValAccount: document.getElementById('diag-val-account'),
    diagValStatus: document.getElementById('diag-val-status'),
    diagValStorefront: document.getElementById('diag-val-storefront'),
    diagValSub: document.getElementById('diag-val-sub'),
    diagValDac: document.getElementById('diag-val-dac'),
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
    miniBtnFavorite: document.getElementById('mini-btn-favorite'),
    miniBtnPlayPause: document.getElementById('mini-btn-play-pause'),
    miniIconPlay: document.getElementById('mini-icon-play'),
    miniIconPause: document.getElementById('mini-icon-pause'),
    miniBtnNext: document.getElementById('mini-btn-next'),
    miniProgressFill: document.getElementById('mini-progress-fill'),

    // Ambient Backdrop Elements
    ambientBackdrop: document.getElementById('ambient-backdrop'),
    ambientLayerA: document.getElementById('ambient-layer-a'),
    ambientLayerB: document.getElementById('ambient-layer-b'),

    // Now Playing Main Player
    artworkContainer: document.querySelector('.artwork-container'),
    artworkWrapper: document.querySelector('.artwork-wrapper'),
    playerArtwork: document.getElementById('player-artwork'),
    playerTitle: document.getElementById('player-title'),
    playerArtist: document.getElementById('player-artist'),
    playerAlbum: document.getElementById('player-album'),
    btnCreateStation: document.getElementById('btn-create-station'),
    btnFavorite: document.getElementById('btn-favorite'),
    audioQualityBadge: document.getElementById('audio-quality-badge'),
    audioQualityText: document.getElementById('audio-quality-text'),
    desktopDacBadge: document.getElementById('desktop-dac-badge'),
    desktopDacText: document.getElementById('desktop-dac-text'),
    mobileDacBadge: document.getElementById('mobile-dac-badge'),
    mobileDacText: document.getElementById('mobile-dac-text'),

    // Station Picker Modal
    stationPickerModal: document.getElementById('station-picker-modal'),
    btnCloseStationModal: document.getElementById('btn-close-station-modal'),
    btnStationByTrack: document.getElementById('btn-station-by-track'),
    btnStationByArtist: document.getElementById('btn-station-by-artist'),
    stationOptTrackName: document.getElementById('station-opt-track-name'),
    stationOptArtistName: document.getElementById('station-opt-artist-name'),

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
    btnAddPlaylistLibrary: document.getElementById('btn-add-playlist-library'),
    btnAddPlaylistLibraryText: document.getElementById('btn-add-playlist-library-text'),
    playlistTracksList: document.getElementById('playlist-tracks-list'),

    // Search Elements
    searchInput: document.getElementById('search-input'),
    btnClearSearch: document.getElementById('btn-clear-search'),
    filterChips: document.querySelectorAll('.filter-chip'),
    searchResults: document.getElementById('search-results'),

    // Busy / Action Loading Overlay
    busyOverlay: document.getElementById('busy-overlay'),
    busyMessage: document.getElementById('busy-message'),

    // Volume Section
    volumeSection: document.getElementById('volume-section'),
    btnVolumeMute: document.getElementById('btn-volume-mute'),
    volumeIcon: document.getElementById('volume-icon'),
    volumeInput: document.getElementById('volume-input'),
    volumeTrackFill: document.getElementById('volume-track-fill'),
    volumeThumb: document.getElementById('volume-thumb'),
    volumeLevelText: document.getElementById('volume-level-text'),
    playerBottomNotice: document.querySelector('.player-bottom-notice .dac-notice-text'),
    // Signal Path Modal
    qualityModal: document.getElementById('quality-modal'),
    btnCloseModal: document.getElementById('btn-close-modal'),
    signalSourceBadge: document.getElementById('signal-source-badge'),
    signalSourceTitle: document.getElementById('signal-source-title'),
    signalSourceDetails: document.getElementById('signal-source-details'),
    signalDacRate: document.getElementById('signal-dac-rate'),
    signalDacName: document.getElementById('signal-dac-name'),
    signalDacDetails: document.getElementById('signal-dac-details'),
    btnOpenDevices: document.getElementById('btn-open-devices'),
    // Audio Devices Modal
    devicesModal: document.getElementById('devices-modal'),
    btnCloseDevices: document.getElementById('btn-close-devices'),
    audioDevicesList: document.getElementById('audio-devices-list'),
    // Apple ID Auth Modal
    modalAppleAuth: document.getElementById('modal-apple-auth'),
    btnAuthModalLogin: document.getElementById('btn-auth-modal-login'),
    authModalStatus: document.getElementById('auth-modal-status')
  };

  // --- Busy Overlay & Action Loading Controller ---
  let busyTimeout = null;
  let activeLoadingBtn = null;

  function markWaitingForPlayback(options = {}) {
    state.waitingForPlayback = true;
    state.waitingTrackSignature = (state.track && state.track.name) ? `${state.track.name}:${state.track.artist || ''}` : null;
    state.waitingStartTime = Date.now();
    state.waitingIsStation = Boolean(options.isStation);
    state.waitingTargetName = options.targetName || null;
    if (options.isStation) {
      state.isLaunchingStation = true;
      if (state.stationLaunchTimeout) clearTimeout(state.stationLaunchTimeout);
      // Safety timeout: unblock UI after 7s if station connection hangs
      state.stationLaunchTimeout = setTimeout(() => {
        state.isLaunchingStation = false;
        state.waitingForPlayback = false;
        state.waitingIsStation = false;
        setUIBusy(false);
      }, 7000);
    }
  }

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

      // Safety timeout: automatically unblock after timeout if server is slow
      const safetyMs = (message.includes('Синхронизация') || message.includes('очереди') || message.includes('Apple Music')) ? 20000 : 8000;
      busyTimeout = setTimeout(() => {
        state.waitingForPlayback = false;
        state.waitingTrackSignature = null;
        state.waitingIsStation = false;
        state.waitingTargetName = null;
        if (state.isLaunchingStation) {
          state.isLaunchingStation = false;
          if (state.stationLaunchTimeout) {
            clearTimeout(state.stationLaunchTimeout);
            state.stationLaunchTimeout = null;
          }
        }
        setUIBusy(false);
      }, safetyMs);
    } else {
      state.waitingForPlayback = false;
      state.waitingTrackSignature = null;
      state.waitingIsStation = false;
      state.waitingTargetName = null;
      if (state.isLaunchingStation) {
        state.isLaunchingStation = false;
        if (state.stationLaunchTimeout) {
          clearTimeout(state.stationLaunchTimeout);
          state.stationLaunchTimeout = null;
        }
      }
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

      // Request initial status, queue, library, and explore feed
      send({ action: 'get_status' });
      send({ action: 'get_queue' });
      send({ action: 'get_playlists' });
      send({ action: 'get_explore', params: { country: state.trends.country } });
      send({ action: 'get_audio_devices' });
      send({ action: 'get_user_token_status' });
      send({ action: 'get_developer_token' });
      send({ action: 'get_account_status' });
      send({ action: 'get_wled_settings' });
      send({ action: 'get_info' });
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
    const act = (msgObj && msgObj.action) ? msgObj.action.toLowerCase() : '';
    if (act === 'play' || act.startsWith('play_') || act.includes('play') || act === 'next' || act === 'previous') {
      syncSilentAudio(true);
    } else if (act === 'pause' || act === 'stop') {
      syncSilentAudio(false);
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

      case 'get_audio_devices':
      case 'audio_devices':
      case 'audio_devices_changed':
        updateAudioDevices(data);
        break;

      case 'get_user_token_status':
      case 'user_token_status':
      case 'set_user_token':
        updateUserTokenStatus(data);
        break;

      case 'get_developer_token':
        if (data && data.token) {
          state.developerToken = data.token;
          initMusicKit(data.token);
        }
        break;

      case 'get_account_status':
      case 'account_status':
      case 'account_health':
        updateAccountHealth(data);
        break;

      case 'wled_settings':
      case 'get_wled_settings':
      case 'set_wled_settings':
        updateWledSettingsUI(data);
        break;

      case 'motion_artwork':
      case 'get_motion_artwork':
        applyMotionArtwork(data);
        break;

      case 'get_info':
      case 'info':
        if (data && data.version) {
          const vEls = document.querySelectorAll('.brand-ver');
          vEls.forEach(el => { el.textContent = `v${data.version}`; });
        }
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

    // Dismiss busy overlay ONLY when specific playback actions complete or fail,
    // NEVER on periodic background 'status', 'queue', or 'player_state_changed' ticks!
    const isPlaybackActionResponse = [
      'play_album', 'play_album_tracks', 'play_playlist',
      'play_station', 'play_hero_card', 'play_search_results',
      'play_recent', 'play_queue_index', 'play_cloud'
    ].includes(type);

    if (msg.status === 'error') {
      state.waitingForPlayback = false;
      setUIBusy(false);
      if (state.isLaunchingStation) {
        state.isLaunchingStation = false;
        if (state.stationLaunchTimeout) {
          clearTimeout(state.stationLaunchTimeout);
          state.stationLaunchTimeout = null;
        }
      }
    } else if (isPlaybackActionResponse && msg.status === 'ok') {
      // If we are waiting for playback to actually start (Music.app buffering/syncing),
      // DO NOT dismiss the spinner yet! Let updatePlayerState dismiss it when player_state becomes 'playing'
      // or track changes!
      if (!state.waitingForPlayback) {
        if (state.isBusyAction) {
          setUIBusy(false);
        }
        if (state.isLaunchingStation) {
          state.isLaunchingStation = false;
          if (state.stationLaunchTimeout) {
            clearTimeout(state.stationLaunchTimeout);
            state.stationLaunchTimeout = null;
          }
        }
      }
    }
  }

  function updatePlayerState(data) {
    if (!data) return;

    clearTransportLoading();

    const oldTrack = state.track;
    const newTrack = data.track || null;
    const isNewTrack = Boolean(
      (newTrack && (!oldTrack || newTrack.id !== oldTrack.id || newTrack.name !== oldTrack.name || newTrack.artist !== oldTrack.artist)) ||
      (!newTrack && oldTrack)
    );

    const incomingState = data.player_state || data.playerState || 'stopped';
    const incomingTrack = data.track || null;
    const incomingSig = (incomingTrack && incomingTrack.name) ? `${incomingTrack.name}:${incomingTrack.artist || ''}` : '';
    const isRadioNow = Boolean(data.is_radio || data.isRadio || (data.playlist && data.playlist.includes('Станция')));

    if (state.waitingForPlayback) {
      // We are waiting for a newly launched track/queue to start.
      // Do NOT dismiss spinner if player is still reporting the OLD track!
      const hasTrackChanged = isNewTrack && incomingSig !== state.waitingTrackSignature;
      const isTargetPlaying = state.waitingTargetName && (
        (data.playlist && (data.playlist.toLowerCase().includes(state.waitingTargetName.toLowerCase()) || data.playlist.includes('Очередь AMR'))) ||
        (incomingTrack && incomingTrack.name && incomingTrack.name.toLowerCase().includes(state.waitingTargetName.toLowerCase()))
      );
      const hasWaitedEnough = (Date.now() - (state.waitingStartTime || 0)) > 600;
      if ((incomingState === 'playing' && (hasTrackChanged || isTargetPlaying || hasWaitedEnough)) || (isRadioNow && (state.isLaunchingStation || state.waitingIsStation))) {
        state.pendingPlayUntil = 0;
        state.playerState = 'playing';
        state.waitingForPlayback = false;
        state.waitingTrackSignature = null;
        state.waitingIsStation = false;
        state.isLaunchingStation = false;
        if (state.stationLaunchTimeout) {
          clearTimeout(state.stationLaunchTimeout);
          state.stationLaunchTimeout = null;
        }
        setUIBusy(false);
      }
    } else if (incomingState === 'playing' || (isRadioNow && (state.isLaunchingStation || state.waitingIsStation))) {
      state.pendingPlayUntil = 0;
      state.playerState = 'playing';
      if (state.isLaunchingStation) {
        state.isLaunchingStation = false;
        if (state.stationLaunchTimeout) {
          clearTimeout(state.stationLaunchTimeout);
          state.stationLaunchTimeout = null;
        }
      }
    } else if (state.pendingPlayUntil && Date.now() < state.pendingPlayUntil) {
      // Keep optimistic playing state while stream is starting up
      state.playerState = 'playing';
    } else {
      state.playerState = incomingState;
    }
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
      const now = performance.now();
      if (state.playerState !== 'playing') {
        state.lastSyncPos = reportedPos;
        state.lastSyncTime = now;
        updateScrubberUI(reportedPos, state.duration);
      } else {
        const predictedPos = Math.min(
          state.duration,
          state.lastSyncPos + (now - state.lastSyncTime) / 1000
        );
        const diff = reportedPos - predictedPos;
        if (Math.abs(diff) > 4.0 || (reportedPos < 1.0 && predictedPos > 3.0)) {
          // Explicit seek or track skip/restart: sync immediately
          state.lastSyncPos = reportedPos;
          state.lastSyncTime = now;
          updateScrubberUI(reportedPos, state.duration);
        } else {
          // Continuous smooth drift synchronization (Phase-Locked Loop):
          // Smoothly absorb clock drift without ever causing a visible jump/jitter.
          // By applying a 15% damping correction per broadcast, client clock matches
          // server clock within a fraction of a second without jitter.
          state.lastSyncPos = predictedPos + diff * 0.15;
          state.lastSyncTime = now;
        }
      }
    }

    state.shuffle = Boolean(data.shuffle);
    state.repeatMode = data.repeat || data.repeatMode || 'off';
    state.audioQuality = data.audio_quality || data.audioQuality || 'Lossless (ALAC 24-bit/48kHz)';
    state.track = newTrack;

    if (data.audio_device_name !== undefined || data.audioDeviceName !== undefined) {
      state.audioDeviceName = data.audio_device_name || data.audioDeviceName || '';
    }
    if (data.audio_device_sample_rate !== undefined || data.audioDeviceSampleRate !== undefined) {
      state.audioDeviceSampleRate = Number(data.audio_device_sample_rate || data.audioDeviceSampleRate) || 44100;
    }
    if (data.audio_device_bit_depth !== undefined || data.audioDeviceBitDepth !== undefined) {
      state.audioDeviceBitDepth = Number(data.audio_device_bit_depth || data.audioDeviceBitDepth) || 24;
    }
    if (data.is_bit_perfect !== undefined || data.isBitPerfect !== undefined) {
      state.isBitPerfect = data.is_bit_perfect !== undefined ? Boolean(data.is_bit_perfect) : Boolean(data.isBitPerfect);
    }

    if (data.lock_volume_100 !== undefined) {
      state.lockVolume100 = Boolean(data.lock_volume_100);
      try { localStorage.setItem('amr_lock_volume_100', String(state.lockVolume100)); } catch (e) {}
    } else if (data.isVolumeLockedTo100 !== undefined) {
      state.lockVolume100 = Boolean(data.isVolumeLockedTo100);
      try { localStorage.setItem('amr_lock_volume_100', String(state.lockVolume100)); } catch (e) {}
    }

    if (data.volume !== undefined) {
      state.volume = Math.max(0, Math.min(100, Number(data.volume)));
      if (state.volume > 0) {
        state.previousVolume = state.volume;
      }
    }

    renderNowPlaying();
    if (dom.qualityModal && !dom.qualityModal.classList.contains('hidden')) {
      updateSignalPathDetails();
    }
  }

  function formatTime(seconds) {
    if (isNaN(seconds) || seconds < 0) return '0:00';
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
  }

  function getArtworkSrc(track) {
    if (!track) return 'apple-touch-icon.svg';
    if (track.artworkUrl && track.artworkUrl.length > 5) {
      return track.artworkUrl;
    }
    if (track.artwork_url && track.artwork_url.length > 5) {
      return track.artwork_url;
    }
    if (track.artwork && track.artwork.length > 5) {
      return track.artwork;
    }
    if (track.artwork_data_base64) {
      return `data:image/jpeg;base64,${track.artwork_data_base64}`;
    }
    if (track.is_local && track.id && Number(track.id) > 0) {
      return `/api/artwork/track?id=${track.id}`;
    }
    if (track.name) {
      const q = new URLSearchParams();
      q.set('name', track.name);
      if (track.artist) q.set('artist', track.artist);
      if (track.album) q.set('album', track.album);
      return `/api/artwork/search?${q.toString()}`;
    }
    if (track.id && Number(track.id) > 0) {
      return `/api/artwork/track?id=${track.id}`;
    }
    return '/api/artwork';
  }

  // ==========================================================================
  // Apple TV Style Dynamic Blurred Ambient Gradient Background Manager
  // ==========================================================================
  const AmbientBackgroundManager = {
    activeLayer: 'a', // 'a' or 'b'
    currentPaletteKey: '',
    offscreenCanvas: null,
    offscreenCtx: null,

    init() {
      if (this.offscreenCanvas) return;
      this.offscreenCanvas = document.createElement('canvas');
      this.offscreenCanvas.width = 32;
      this.offscreenCanvas.height = 32;
      this.offscreenCtx = this.offscreenCanvas.getContext('2d', { willReadFrequently: true });
    },

    rgbToHsv(r, g, b) {
      const rf = r / 255;
      const gf = g / 255;
      const bf = b / 255;
      const max = Math.max(rf, gf, bf);
      const min = Math.min(rf, gf, bf);
      const d = max - min;
      let h = 0;
      if (d > 0.0001) {
        if (max === rf) h = 60 * (((gf - bf) / d) % 6);
        else if (max === gf) h = 60 * ((bf - rf) / d + 2);
        else h = 60 * ((rf - gf) / d + 4);
        if (h < 0) h += 360;
      }
      const s = max <= 0.0001 ? 0 : d / max;
      return { h, s, v: max };
    },

    hsvToRgb(h, s, v) {
      const cleanH = ((h % 360) + 360) % 360;
      const c = v * s;
      const x = c * (1 - Math.abs(((cleanH / 60) % 2) - 1));
      const m = v - c;
      let r1 = 0, g1 = 0, b1 = 0;
      if (cleanH < 60) { r1 = c; g1 = x; }
      else if (cleanH < 120) { r1 = x; g1 = c; }
      else if (cleanH < 180) { g1 = c; b1 = x; }
      else if (cleanH < 240) { g1 = x; b1 = c; }
      else if (cleanH < 300) { r1 = x; b1 = c; }
      else { r1 = c; b1 = x; }
      return [
        Math.round((r1 + m) * 255),
        Math.round((g1 + m) * 255),
        Math.round((b1 + m) * 255)
      ];
    },

    hueDistance(h1, h2) {
      const diff = Math.abs(h1 - h2) % 360;
      return diff > 180 ? 360 - diff : diff;
    },

    // Extract 16 spatial perimeter zones + distinct chromatic clusters for WLED DDP
    extractWledZones(img) {
      this.init();
      const ctx = this.offscreenCtx;
      if (!ctx) return [[250, 35, 59], [121, 40, 202], [28, 140, 220], [255, 107, 139]];

      try {
        ctx.clearRect(0, 0, 32, 32);
        ctx.drawImage(img, 0, 0, 32, 32);
        const imgData = ctx.getImageData(0, 0, 32, 32).data;

        // 1. Collect distinct chromatic accent clusters across the whole cover
        const candidates = [];
        for (let i = 0; i < imgData.length; i += 16) {
          const r = imgData[i], g = imgData[i + 1], b = imgData[i + 2], a = imgData[i + 3];
          if (a < 128) continue;
          const hsv = this.rgbToHsv(r, g, b);
          if (hsv.v < 0.08) continue;
          const score = Math.pow(hsv.s, 0.7) * Math.pow(hsv.v, 0.5);
          candidates.push({ r, g, b, h: hsv.h, s: hsv.s, v: hsv.v, score });
        }
        candidates.sort((a, b) => b.score - a.score);

        const distinctAccents = [];
        for (const c of candidates) {
          if (distinctAccents.length >= 6) break;
          if (distinctAccents.every(ex => this.hueDistance(ex.h, c.h) >= 32)) {
            distinctAccents.push(c);
          }
        }
        if (distinctAccents.length === 0 && candidates.length > 0) {
          distinctAccents.push(candidates[0]);
        }

        // 2. Sample 16 spatial perimeter boxes around the 32x32 cover:
        // 0..3: Left edge (bottom -> top)
        // 4..11: Top edge (left -> right)
        // 12..15: Right edge (top -> bottom)
        const boxes = [
          [0, 24, 6, 8], [0, 16, 6, 8], [0, 8, 6, 8], [0, 0, 6, 8],
          [0, 0, 4, 6], [4, 0, 4, 6], [8, 0, 4, 6], [12, 0, 4, 6],
          [16, 0, 4, 6], [20, 0, 4, 6], [24, 0, 4, 6], [28, 0, 4, 6],
          [26, 0, 6, 8], [26, 8, 6, 8], [26, 16, 6, 8], [26, 24, 6, 8]
        ];

        const zones = [];
        for (let z = 0; z < boxes.length; z++) {
          const [bx, by, bw, bh] = boxes[z];
          let bestSample = null;
          let sumR = 0, sumG = 0, sumB = 0, count = 0;

          for (let y = by; y < by + bh; y++) {
            for (let x = bx; x < bx + bw; x++) {
              const idx = (y * 32 + x) * 4;
              const r = imgData[idx], g = imgData[idx + 1], b = imgData[idx + 2];
              sumR += r; sumG += g; sumB += b; count++;
              const hsv = this.rgbToHsv(r, g, b);
              const score = hsv.s * 1.4 + hsv.v * 0.6;
              if (!bestSample || score > bestSample.score) {
                bestSample = { r, g, b, h: hsv.h, s: hsv.s, v: hsv.v, score };
              }
            }
          }

          let chosen = bestSample || {
            r: Math.round(sumR / Math.max(1, count)),
            g: Math.round(sumG / Math.max(1, count)),
            b: Math.round(sumB / Math.max(1, count)),
            ...this.rgbToHsv(sumR / Math.max(1, count), sumG / Math.max(1, count), sumB / Math.max(1, count))
          };

          // If this perimeter zone is dull/monotonous and we have distinct cover accents, weave them in!
          if ((chosen.s < 0.25 || z % 3 === 1) && distinctAccents.length > 1) {
            const acc = distinctAccents[z % distinctAccents.length];
            chosen = { ...acc };
          }

          const boostedS = chosen.s < 0.08 ? 0.85 : Math.min(1.0, Math.pow(chosen.s, 0.45) * 1.2);
          const boostedV = Math.min(1.0, Math.max(0.32, Math.pow(chosen.v, 0.8) * 1.15));
          zones.push(this.hsvToRgb(chosen.h, boostedS, boostedV));
        }

        return zones;
      } catch (e) {
        return [[250, 35, 59], [121, 40, 202], [28, 140, 220], [255, 107, 139]];
      }
    },

    // Extract 4 harmonic ambient colors from image
    extractPalette(img) {
      this.init();
      const ctx = this.offscreenCtx;
      if (!ctx) return this.getDefaultPalette();

      try {
        ctx.clearRect(0, 0, 32, 32);
        ctx.drawImage(img, 0, 0, 32, 32);
        const imgData = ctx.getImageData(0, 0, 32, 32).data;
        const colorSamples = [];

        for (let i = 0; i < imgData.length; i += 16) { // sample every 4th pixel
          const r = imgData[i];
          const g = imgData[i + 1];
          const b = imgData[i + 2];
          const a = imgData[i + 3];

          if (a < 128) continue;

          const max = Math.max(r, g, b) / 255;
          const min = Math.min(r, g, b) / 255;
          const lum = (max + min) / 2;

          // Skip pure black or blown out highlights for ambient background
          if (lum < 0.06 || lum > 0.94) continue;

          const delta = max - min;
          const sat = delta === 0 ? 0 : delta / (1 - Math.abs(2 * lum - 1));
          const hsv = this.rgbToHsv(r, g, b);

          colorSamples.push({ r, g, b, sat, lum, h: hsv.h });
        }

        if (colorSamples.length === 0) {
          return this.getDefaultPalette();
        }

        // Sort by saturation to prioritize vivid, rich hues
        colorSamples.sort((c1, c2) => c2.sat - c1.sat);

        // Pick 4 chromatically distinct colors when available
        const picked = [colorSamples[0]];
        for (const sample of colorSamples) {
          if (picked.length >= 4) break;
          if (picked.every(p => this.hueDistance(p.h, sample.h) >= 28)) {
            picked.push(sample);
          }
        }
        const vibrant = picked[0];
        const secondary = picked[1] || colorSamples[Math.floor(colorSamples.length * 0.35)] || vibrant;
        const tertiary = picked[2] || colorSamples[Math.floor(colorSamples.length * 0.70)] || secondary;
        const deep = picked[3] || colorSamples[colorSamples.length - 1] || tertiary;

        return [
          this.tuneColor(vibrant, 1.5, 0.52),
          this.tuneColor(secondary, 1.4, 0.46),
          this.tuneColor(tertiary, 1.35, 0.48),
          this.tuneColor(deep, 1.25, 0.36)
        ];
      } catch (err) {
        // Fallback for tainted canvas
        return this.getDefaultPalette();
      }
    },

    tuneColor(col, satMultiplier, targetLum) {
      let r = col.r;
      let g = col.g;
      let b = col.b;

      // Adjust brightness toward targetLum
      const currentLum = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
      const factor = currentLum > 0 ? targetLum / currentLum : 1.0;
      r = Math.min(255, Math.max(16, Math.round(r * factor)));
      g = Math.min(255, Math.max(16, Math.round(g * factor)));
      b = Math.min(255, Math.max(16, Math.round(b * factor)));

      // Boost saturation
      const avg = (r + g + b) / 3;
      r = Math.min(255, Math.max(0, Math.round(avg + (r - avg) * satMultiplier)));
      g = Math.min(255, Math.max(0, Math.round(avg + (g - avg) * satMultiplier)));
      b = Math.min(255, Math.max(0, Math.round(avg + (b - avg) * satMultiplier)));

      return `rgba(${r}, ${g}, ${b}, 0.85)`;
    },

    getDefaultPalette() {
      return [
        'rgba(50, 30, 85, 0.65)',
        'rgba(30, 55, 105, 0.60)',
        'rgba(75, 35, 65, 0.55)',
        'rgba(25, 70, 90, 0.50)'
      ];
    },

    updateFromImage(img, artUrl) {
      if (!dom.ambientBackdrop) return;
      if (!artUrl || artUrl === 'apple-touch-icon.svg') {
        this.clear();
        return;
      }

      const palette = this.extractPalette(img);
      const paletteKey = palette.join('|');
      if (paletteKey === this.currentPaletteKey) return;
      this.currentPaletteKey = paletteKey;

      // Dual buffer swap: 'a' <-> 'b'
      const nextLayer = this.activeLayer === 'a' ? 'b' : 'a';
      const targetElem = nextLayer === 'a' ? dom.ambientLayerA : dom.ambientLayerB;
      const prevElem = this.activeLayer === 'a' ? dom.ambientLayerA : dom.ambientLayerB;

      if (targetElem) {
        targetElem.style.setProperty('--blob-1', palette[0]);
        targetElem.style.setProperty('--blob-2', palette[1]);
        targetElem.style.setProperty('--blob-3', palette[2]);
        targetElem.style.setProperty('--blob-4', palette[3]);

        targetElem.classList.add('visible');
      }

      if (prevElem) {
        prevElem.classList.remove('visible');
      }

      this.activeLayer = nextLayer;
      dom.ambientBackdrop.classList.add('active');

      // Extract 16 spatial perimeter zones for WLED DDP Ambilight & RGB tuples for StandBy TV backdrop
      const wledZones = this.extractWledZones(img);
      const rgbColors = palette.map((rgbaStr) => {
        const m = rgbaStr.match(/(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/);
        return m ? [parseInt(m[1], 10), parseInt(m[2], 10), parseInt(m[3], 10)] : [250, 35, 59];
      });
      send({
        action: 'update_wled_palette',
        params: { colors: wledZones.length >= 4 ? wledZones : rgbColors }
      });
      const standbyBg = document.getElementById('standby-ambient-bg');
      if (standbyBg && rgbColors.length >= 3) {
        const [c0, c1, c2] = rgbColors;
        standbyBg.style.background = `
          radial-gradient(circle at 24% 48%, rgba(${c0[0]}, ${c0[1]}, ${c0[2]}, 0.44), transparent 55%),
          radial-gradient(circle at 78% 32%, rgba(${c1[0]}, ${c1[1]}, ${c1[2]}, 0.34), transparent 58%),
          radial-gradient(circle at 60% 82%, rgba(${c2[0]}, ${c2[1]}, ${c2[2]}, 0.28), rgba(4, 4, 6, 0.96) 75%)
        `;
      }
    },

    clear() {
      if (!dom.ambientBackdrop) return;
      dom.ambientBackdrop.classList.remove('active');
      if (dom.ambientLayerA) dom.ambientLayerA.classList.remove('visible');
      if (dom.ambientLayerB) dom.ambientLayerB.classList.remove('visible');
      this.currentPaletteKey = '';
    }
  };

  let currentLoadedArtworkUrl = '';
  function setPlayerArtwork(artUrl) {
    if (!artUrl) artUrl = 'apple-touch-icon.svg';
    if (dom.playerArtwork.dataset.targetSrc === artUrl) {
      return;
    }
    dom.playerArtwork.dataset.targetSrc = artUrl;

    if (artUrl === 'apple-touch-icon.svg') {
      dom.playerArtwork.src = artUrl;
      dom.playerArtwork.style.opacity = '1';
      currentLoadedArtworkUrl = artUrl;
      if (dom.miniArt) {
        dom.miniArt.src = artUrl;
        dom.miniArt.style.opacity = '1';
      }
      AmbientBackgroundManager.clear();
      return;
    }

    // Immediately dim/fade the artwork elements so the old track's image NEVER lingers
    if (currentLoadedArtworkUrl && currentLoadedArtworkUrl !== artUrl) {
      dom.playerArtwork.style.opacity = '0';
      if (dom.miniArt) dom.miniArt.style.opacity = '0.3';
    }

    // Preload image to prevent showing old track's image if new image fails or loads slowly
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => {
      if (dom.playerArtwork.dataset.targetSrc === artUrl) {
        dom.playerArtwork.src = artUrl;
        dom.playerArtwork.style.opacity = '1';
        currentLoadedArtworkUrl = artUrl;
        if (dom.miniArt) {
          dom.miniArt.src = artUrl;
          dom.miniArt.style.opacity = '1';
        }
        AmbientBackgroundManager.updateFromImage(img, artUrl);
      }
    };
    img.onerror = () => {
      if (dom.playerArtwork.dataset.targetSrc === artUrl) {
        dom.playerArtwork.src = 'apple-touch-icon.svg';
        dom.playerArtwork.style.opacity = '1';
        currentLoadedArtworkUrl = 'apple-touch-icon.svg';
        if (dom.miniArt) {
          dom.miniArt.src = 'apple-touch-icon.svg';
          dom.miniArt.style.opacity = '1';
        }
        AmbientBackgroundManager.clear();
      }
    };
    img.src = artUrl;
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
      setPlayerArtwork(art);
      dom.btnFavorite.classList.toggle('active', Boolean(t.favorited));
      if (dom.miniBtnFavorite) dom.miniBtnFavorite.classList.toggle('active', Boolean(t.favorited));

      // Mini Player sync
      dom.miniTitle.textContent = t.name || 'Без названия';
      dom.miniArtist.textContent = t.artist || 'Apple Music';
    } else {
      dom.playerTitle.textContent = 'Не играет';
      dom.playerArtist.textContent = 'Apple Music';
      dom.playerAlbum.textContent = '';
      setPlayerArtwork('apple-touch-icon.svg');
      dom.btnFavorite.classList.remove('active');
      if (dom.miniBtnFavorite) dom.miniBtnFavorite.classList.remove('active');

      dom.miniTitle.textContent = 'Не играет';
      dom.miniArtist.textContent = 'Apple Music';
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

    // Audio Quality & Permanent DAC Badge Sync
    const dacText = formatDacPill(state.audioQuality);
    if (dom.audioQualityText) dom.audioQualityText.textContent = dacText;
    if (dom.desktopDacText) dom.desktopDacText.textContent = dacText;
    if (dom.mobileDacText) dom.mobileDacText.textContent = dacText;
    if (dom.modalSpecQuality) dom.modalSpecQuality.textContent = state.audioQuality;
    if (dom.modalSpecRate) {
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
    }
    if (typeof updateSignalPathDetails === 'function') {
      updateSignalPathDetails();
    }

    // Only update scrubber UI here if stopped or paused.
    // When playing, the 60fps scrubberAnimationLoop handles smooth rendering without jitter!
    if (!state.isScrubbing && state.playerState !== 'playing') {
      updateScrubberUI(state.lastSyncPos, state.duration);
    }

    renderVolumeUI();
    renderCurrentQueueTrack(dom.queueCurrentTrack);
    updateMediaSession();
    syncStandbyAndMotionCoverUI();
  }

  function renderVolumeUI() {
    if (state.lockVolume100) {
      if (dom.volumeSection) dom.volumeSection.classList.add('hidden');
      if (dom.playerBottomNotice) {
        dom.playerBottomNotice.textContent = 'Прямой вывод CoreAudio (Bit-Perfect DAC • 100%)';
      }
    } else {
      if (dom.volumeSection) dom.volumeSection.classList.remove('hidden');
      if (dom.playerBottomNotice) {
        dom.playerBottomNotice.textContent = 'Прямой вывод CoreAudio (Регулируемая громкость)';
      }
      if (dom.volumeInput && !state.isDraggingVolume) {
        dom.volumeInput.value = state.volume;
      }
      if (dom.volumeTrackFill) {
        dom.volumeTrackFill.style.width = `${state.volume}%`;
      }
      if (dom.volumeThumb) {
        dom.volumeThumb.style.left = `${state.volume}%`;
      }
      if (dom.volumeLevelText) {
        dom.volumeLevelText.textContent = `${state.volume}%`;
      }
      updateVolumeIcon(state.volume);
    }
  }

  function updateVolumeIcon(vol) {
    if (!dom.volumeIcon) return;
    const wave1 = dom.volumeSection ? dom.volumeSection.querySelector('#vol-wave-1') : null;
    const wave2 = dom.volumeSection ? dom.volumeSection.querySelector('#vol-wave-2') : null;
    if (vol === 0) {
      if (wave1) wave1.style.display = 'none';
      if (wave2) wave2.style.display = 'none';
    } else if (vol < 50) {
      if (wave1) wave1.style.display = 'block';
      if (wave2) wave2.style.display = 'none';
    } else {
      if (wave1) wave1.style.display = 'block';
      if (wave2) wave2.style.display = 'block';
    }
  }

  // --- Tactile & Haptic Engine ---
  let hapticAudioCtx = null;
  function getHapticAudioContext() {
    if (!hapticAudioCtx) {
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (AudioCtx) {
        hapticAudioCtx = new AudioCtx();
      }
    }
    if (hapticAudioCtx && hapticAudioCtx.state === 'suspended') {
      hapticAudioCtx.resume().catch(() => {});
    }
    return hapticAudioCtx;
  }

  function triggerHaptic(type = 'light') {
    // 1. Native Vibration API (Android, Chrome, supported browsers)
    if ('vibrate' in navigator) {
      try {
        if (type === 'light') navigator.vibrate(15);
        else if (type === 'medium') navigator.vibrate(28);
        else if (type === 'heavy') navigator.vibrate(45);
        else if (type === 'toggle') navigator.vibrate([15, 30, 25]);
      } catch (e) {}
    }

    // 2. iOS Speaker Transducer Micro-Thump (Physical recoil pulse in iPhone chassis)
    try {
      const ctx = getHapticAudioContext();
      if (!ctx) return;
      if (ctx.state === 'suspended') {
        ctx.resume().catch(() => {});
      }
      const now = ctx.currentTime;
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();

      osc.type = 'sine';
      if (type === 'light') {
        // Fast subtle tap (75Hz down to 25Hz, 18ms, gain 0.85)
        osc.frequency.setValueAtTime(75, now);
        osc.frequency.exponentialRampToValueAtTime(25, now + 0.018);
        gain.gain.setValueAtTime(0.85, now);
        gain.gain.exponentialRampToValueAtTime(0.001, now + 0.018);
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(now);
        osc.stop(now + 0.018);
      } else if (type === 'medium') {
        // Firm mechanical thump (85Hz down to 25Hz, 30ms, gain 1.0)
        osc.frequency.setValueAtTime(85, now);
        osc.frequency.exponentialRampToValueAtTime(25, now + 0.03);
        gain.gain.setValueAtTime(1.0, now);
        gain.gain.exponentialRampToValueAtTime(0.001, now + 0.03);
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(now);
        osc.stop(now + 0.03);
      } else if (type === 'toggle') {
        // Double-click toggle (like switch / like button)
        osc.frequency.setValueAtTime(95, now);
        osc.frequency.exponentialRampToValueAtTime(30, now + 0.018);
        gain.gain.setValueAtTime(0.85, now);
        gain.gain.exponentialRampToValueAtTime(0.001, now + 0.018);
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(now);
        osc.stop(now + 0.018);

        const osc2 = ctx.createOscillator();
        const gain2 = ctx.createGain();
        osc2.type = 'sine';
        osc2.frequency.setValueAtTime(110, now + 0.026);
        osc2.frequency.exponentialRampToValueAtTime(35, now + 0.046);
        gain2.gain.setValueAtTime(0.9, now + 0.026);
        gain2.gain.exponentialRampToValueAtTime(0.001, now + 0.046);
        osc2.connect(gain2);
        gain2.connect(ctx.destination);
        osc2.start(now + 0.026);
        osc2.stop(now + 0.046);
      }
    } catch (e) {}
  }

  // --- Silent Audio Loop for iOS Background & Lock Screen Keep-Alive ---
  let silentAudioEl = null;
  let silentAudioUnlocked = false;

  function attachSilentAudioListeners(el) {
    if (!el || el._amrListenersAttached) return;
    el._amrListenersAttached = true;

    const onAudioStateChange = () => {
      setupMediaSession();
      updateMediaSession();
    };

    ['play', 'playing', 'pause', 'canplay', 'loadedmetadata'].forEach((evt) => {
      el.addEventListener(evt, onAudioStateChange, { passive: true });
    });
  }

  function initSilentAudio() {
    if (!silentAudioEl) {
      silentAudioEl = document.getElementById('bg-silent-audio');
    }
    if (!silentAudioEl) {
      silentAudioEl = document.createElement('audio');
      silentAudioEl.id = 'bg-silent-audio';
      silentAudioEl.loop = true;
      silentAudioEl.setAttribute('playsinline', '');
      silentAudioEl.setAttribute('webkit-playsinline', '');
      silentAudioEl.preload = 'auto';
      silentAudioEl.src = '/assets/silence.m4a?v=2';
      silentAudioEl.style.cssText = 'position:fixed;bottom:0;left:0;width:1px;height:1px;opacity:0.001;pointer-events:none;z-index:-1;';
      document.body.appendChild(silentAudioEl);
    }
    attachSilentAudioListeners(silentAudioEl);
    return silentAudioEl;
  }

  function syncSilentAudio(isPlaying) {
    const el = initSilentAudio();
    if (!el) return;

    if (isPlaying) {
      if (el.paused) {
        const p = el.play();
        if (p !== undefined) {
          p.then(() => {
            silentAudioUnlocked = true;
            setupMediaSession();
            updateMediaSession();
          }).catch((err) => {
            console.warn('[AudioKeepAlive] play error:', err);
          });
        }
      } else {
        setupMediaSession();
      }
    } else {
      if (!el.paused) {
        el.pause();
      }
      setupMediaSession();
    }
  }

  // Synchronously unlock audio & Web Audio on EVERY user gesture until unlocked
  function unlockAudioOnUserGesture() {
    const el = initSilentAudio();
    const ctx = getHapticAudioContext();
    if (ctx && ctx.state === 'suspended') {
      ctx.resume().catch(() => {});
    }

    if (!silentAudioUnlocked && el) {
      const p = el.play();
      if (p !== undefined) {
        p.then(() => {
          silentAudioUnlocked = true;
          if (state.playerState !== 'playing') {
            el.pause();
          }
          setupMediaSession();
          updateMediaSession();
        }).catch(() => {});
      }
    } else {
      setupMediaSession();
    }
  }

  ['pointerdown', 'touchstart', 'touchend', 'click'].forEach(evt => {
    window.addEventListener(evt, unlockAudioOnUserGesture, { passive: true });
  });

  // Re-bind MediaSession on app wake, unlock, or tab switch
  ['visibilitychange', 'pageshow', 'focus'].forEach((evt) => {
    window.addEventListener(evt, () => {
      if (!document.hidden) {
        setupMediaSession();
        updateMediaSession();
      }
    }, { passive: true });
  });

  // Global tactile feedback on all interactive elements
  let lastGlobalHapticTime = 0;
  document.addEventListener('pointerup', (e) => {
    const now = Date.now();
    if (now - lastGlobalHapticTime < 80) return;
    const target = e.target.closest('button, .track-row, .playlist-card, .hero-card, .station-card, .media-card, .genre-card, .tab-item, .nav-btn, .search-chip, .quality-badge, .pill, .mini-btn, .mini-player-content');
    if (target) {
      lastGlobalHapticTime = now;
      triggerHaptic('light');
    }
  }, { passive: true });

  // --- MediaSession (Lock Screen, Dynamic Island, AirPods, Control Center) ---
  let lastMediaSessionKey = '';
  function setupMediaSession() {
    if (!('mediaSession' in navigator)) return;

    try {
      navigator.mediaSession.setActionHandler('play', () => {
        triggerHaptic('medium');
        syncSilentAudio(true);
        state.playerState = 'playing';
        renderNowPlaying();
        setupMediaSession();
        updateMediaSession();
        send({ action: 'play' });
      });

      navigator.mediaSession.setActionHandler('pause', () => {
        triggerHaptic('medium');
        syncSilentAudio(false);
        state.playerState = 'paused';
        renderNowPlaying();
        setupMediaSession();
        updateMediaSession();
        send({ action: 'pause' });
      });

      navigator.mediaSession.setActionHandler('previoustrack', () => {
        triggerHaptic('medium');
        sendThrottledTransport('previous');
      });

      navigator.mediaSession.setActionHandler('nexttrack', () => {
        triggerHaptic('medium');
        sendThrottledTransport('next');
      });

      navigator.mediaSession.setActionHandler('seekto', (details) => {
        if (details.seekTime != null && !isNaN(details.seekTime)) {
          triggerHaptic('light');
          if (silentAudioEl && !isNaN(details.seekTime)) {
            try { silentAudioEl.currentTime = details.seekTime; } catch(e){}
          }
          sendSeek(details.seekTime);
        }
      });

      // Disable seekbackward & seekforward so iOS Lock Screen, Dynamic Island,
      // and Control Center display Previous / Next Track buttons (⏮ / ⏭) instead of ±10s/±15s buttons.
      try { navigator.mediaSession.setActionHandler('seekbackward', null); } catch (e) {}
      try { navigator.mediaSession.setActionHandler('seekforward', null); } catch (e) {}

      navigator.mediaSession.setActionHandler('stop', () => {
        triggerHaptic('medium');
        syncSilentAudio(false);
        setupMediaSession();
        updateMediaSession();
        send({ action: 'stop' });
      });
    } catch (err) {
      console.warn('[MediaSession] Handler setup:', err);
    }
  }

  function updateMediaSession() {
    if (!('mediaSession' in navigator)) return;

    // Ensure action handlers are persistently bound to the active WebKit MediaSession
    setupMediaSession();

    const isPlaying = state.playerState === 'playing';
    syncSilentAudio(isPlaying);

    navigator.mediaSession.playbackState = isPlaying ? 'playing' : 'paused';

    const t = state.track;
    if (!t || !t.name) return;

    const rawArt = getArtworkSrc(t);
    let fullArt = rawArt;
    if (!fullArt || fullArt.includes('.svg') || fullArt.includes('apple-touch-icon.svg')) {
      fullArt = `${window.location.origin}/apple-touch-icon-512.png`;
    } else if (fullArt.startsWith('/')) {
      fullArt = `${window.location.origin}${fullArt}`;
    }

    const artType = (fullArt.endsWith('.png') || fullArt.includes('icon')) ? 'image/png' : 'image/jpeg';

    const key = `${t.name}_${t.artist}_${t.album}_${fullArt}`;
    if (key !== lastMediaSessionKey) {
      lastMediaSessionKey = key;
      try {
        navigator.mediaSession.metadata = new MediaMetadata({
          title: t.name || 'Без названия',
          artist: t.artist || 'Apple Music',
          album: t.album || '',
          artwork: [
            { src: fullArt, sizes: '96x96', type: artType },
            { src: fullArt, sizes: '128x128', type: artType },
            { src: fullArt, sizes: '192x192', type: artType },
            { src: fullArt, sizes: '256x256', type: artType },
            { src: fullArt, sizes: '512x512', type: artType }
          ]
        });
      } catch (e) {
        console.warn('[MediaSession] Metadata update error:', e);
      }
    }

    if ('setPositionState' in navigator.mediaSession && state.duration > 0) {
      try {
        const curPos = Math.min(Math.max(0, state.position || state.lastSyncPos || 0), state.duration);
        navigator.mediaSession.setPositionState({
          duration: Math.max(state.duration, 0.1),
          playbackRate: isPlaying ? 1.0 : 0.0,
          position: curPos
        });
        if (silentAudioEl && !silentAudioEl.paused && curPos >= 0) {
          const drift = Math.abs(silentAudioEl.currentTime - curPos);
          if (drift > 3.0) {
            try { silentAudioEl.currentTime = curPos; } catch(e){}
          }
        }
      } catch (e) {}
    }
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

  function formatDacPill(raw) {
    if (!raw) return 'Bit-Perfect DAC';
    const up = raw.toUpperCase();
    if (up.includes('192')) return 'Bit-Perfect • 192 kHz / 24-bit';
    if (up.includes('96')) return 'Bit-Perfect • 96 kHz / 24-bit';
    if (up.includes('48')) return 'Lossless • 48 kHz / 24-bit';
    if (up.includes('44.1')) return 'Lossless • 44.1 kHz / 16-bit';
    if (up.includes('HI-RES')) return 'Hi-Res Lossless Bit-Perfect';
    if (up.includes('LOSSLESS') || up.includes('ALAC')) return 'Lossless Bit-Perfect';
    if (up.includes('AAC')) return 'AAC • 256 kbps';
    return raw;
  }

  function updateScrubberUI(currentPos, totalDur) {
    const sbFill = document.getElementById('standby-progress-fill');
    const sbElapsed = document.getElementById('standby-time-elapsed');
    const sbRemaining = document.getElementById('standby-time-remaining');
    if (totalDur <= 0) {
      dom.scrubberFill.style.width = '0%';
      dom.scrubberThumb.style.left = '0%';
      dom.miniProgressFill.style.width = '0%';
      dom.timeElapsed.textContent = '0:00';
      dom.timeRemaining.textContent = '-0:00';
      dom.scrubberInput.value = 0;
      if (sbFill) sbFill.style.width = '0%';
      if (sbElapsed) sbElapsed.textContent = '0:00';
      if (sbRemaining) sbRemaining.textContent = '-0:00';
      return;
    }

    const clampedPos = Math.max(0, Math.min(currentPos, totalDur));
    const percent = (clampedPos / totalDur) * 100;

    dom.scrubberFill.style.width = `${percent}%`;
    dom.scrubberThumb.style.left = `${percent}%`;
    dom.miniProgressFill.style.width = `${percent}%`;
    dom.scrubberInput.value = percent;

    const elapsedStr = formatTime(clampedPos);
    const remaining = totalDur - clampedPos;
    const remStr = `-${formatTime(remaining)}`;
    dom.timeElapsed.textContent = elapsedStr;
    dom.timeRemaining.textContent = remStr;
    if (sbFill) sbFill.style.width = `${percent}%`;
    if (sbElapsed) sbElapsed.textContent = elapsedStr;
    if (sbRemaining) sbRemaining.textContent = remStr;
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
    sendSeek(targetPos);
  }

  function sendSeek(position) {
    const targetPos = Math.max(0, Math.min(state.duration || 0, position));
    state.lastSyncPos = targetPos;
    state.lastSyncTime = performance.now();
    state.position = targetPos;
    updateScrubberUI(targetPos, state.duration);
    send({
      action: 'seek',
      params: { position: targetPos }
    });
    updateMediaSession();
  }

  dom.scrubberInput.addEventListener('change', commitScrub);
  dom.scrubberInput.addEventListener('pointerup', commitScrub);
  dom.scrubberInput.addEventListener('touchend', commitScrub);

  // --- Transport Event Listeners ---
  function optimisticPlay() {
    state.pendingPlayUntil = Date.now() + 3000;
    state.lastSyncTime = performance.now();
    state.playerState = 'playing';
    state.playbackState = 'playing';
    renderNowPlaying();
  }

  function togglePlayPause(e) {
    if (e) {
      e.preventDefault();
      e.stopPropagation();
    }
    triggerHaptic('medium');
    const isPlaying = state.playerState === 'playing';
    syncSilentAudio(!isPlaying);
    if (isPlaying) {
      state.pendingPlayUntil = 0;
      const now = performance.now();
      state.lastSyncPos = Math.min(state.duration, state.lastSyncPos + (now - state.lastSyncTime) / 1000);
      state.lastSyncTime = now;
      state.playerState = 'paused';
      state.playbackState = 'paused';
      renderNowPlaying();
    } else {
      optimisticPlay();
    }
    send({ action: isPlaying ? 'pause' : 'play' });
  }

  let transportLoadingTimer = null;
  function setTransportLoading(action) {
    if (transportLoadingTimer) clearTimeout(transportLoadingTimer);
    if (action === 'next') {
      dom.btnNext?.classList.add('btn-loading');
      dom.miniBtnNext?.classList.add('btn-loading');
    } else if (action === 'previous') {
      dom.btnPrev?.classList.add('btn-loading');
    }
    transportLoadingTimer = setTimeout(clearTransportLoading, 2000);
  }

  function clearTransportLoading() {
    if (transportLoadingTimer) {
      clearTimeout(transportLoadingTimer);
      transportLoadingTimer = null;
    }
    dom.btnNext?.classList.remove('btn-loading');
    dom.miniBtnNext?.classList.remove('btn-loading');
    dom.btnPrev?.classList.remove('btn-loading');
    dom.btnPlayPause?.classList.remove('btn-loading');
    dom.miniBtnPlayPause?.classList.remove('btn-loading');
  }

  let lastNextActionTime = 0;
  let lastPrevActionTime = 0;
  function sendThrottledTransport(action) {
    const now = Date.now();
    if (action === 'next') {
      if (now - lastNextActionTime < 400) return;
      lastNextActionTime = now;
    } else if (action === 'previous') {
      if (now - lastPrevActionTime < 150) return;
      lastPrevActionTime = now;
    } else {
      if (now - lastNextActionTime < 400) return;
      lastNextActionTime = now;
    }
    setTransportLoading(action);
    triggerHaptic('medium');
    send({ action });
  }

  dom.btnPlayPause.addEventListener('click', togglePlayPause);
  dom.miniBtnPlayPause.addEventListener('click', togglePlayPause);

  // Desktop Spacebar shortcut for Play/Pause
  document.addEventListener('keydown', (e) => {
    if (e.code === 'Space' && !['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName)) {
      e.preventDefault();
      togglePlayPause();
    }
  });

  dom.btnNext.addEventListener('click', () => sendThrottledTransport('next'));
  dom.miniBtnNext.addEventListener('click', (e) => {
    e.stopPropagation();
    sendThrottledTransport('next');
  });

  dom.btnPrev.addEventListener('click', () => sendThrottledTransport('previous'));

  dom.btnShuffle.addEventListener('click', () => {
    triggerHaptic('toggle');
    send({
      action: 'set_shuffle',
      params: { enabled: !state.shuffle }
    });
  });

  dom.btnRepeat.addEventListener('click', () => {
    triggerHaptic('toggle');
    const modes = ['off', 'all', 'one'];
    const nextIdx = (modes.indexOf(state.repeatMode) + 1) % modes.length;
    const nextMode = modes[nextIdx];
    send({
      action: 'set_repeat',
      params: { mode: nextMode }
    });
  });

  dom.btnFavorite.addEventListener('click', () => {
    triggerHaptic('toggle');
    send({ action: 'favorite' });
  });

  if (dom.miniBtnFavorite) {
    dom.miniBtnFavorite.addEventListener('click', (e) => {
      e.stopPropagation();
      triggerHaptic('toggle');
      send({ action: 'favorite' });
    });
  }

  dom.btnReconnect.addEventListener('click', () => {
    triggerHaptic('light');
    connectWebSocket();
  });

  // --- Signal Path Inspector (Roon-like Pipeline) ---
  function updateSignalPathDetails() {
    const t = state.track;
    const quality = state.audioQuality || 'Lossless (ALAC 24-bit/48kHz)';
    const up = quality.toUpperCase();
    const isLossy = up.includes('AAC') || up.includes('MP3');
    const devRateHz = state.audioDeviceSampleRate || 44100;
    const rateKhz = (devRateHz / 1000).toFixed(1).replace(/\.0$/, '');
    const outBitDepth = isLossy ? 16 : (state.audioDeviceBitDepth || (devRateHz >= 48000 ? 24 : 16));

    let formatBadge = 'ALAC Lossless';
    if (up.includes('192') || up.includes('HI-RES')) {
      formatBadge = 'ALAC Hi-Res';
    } else if (isLossy) {
      formatBadge = 'AAC 256k';
    } else if (up.includes('LOSSLESS') || up.includes('ALAC')) {
      formatBadge = 'ALAC Lossless';
    }

    // Parse source sample rate and bit depth for Bit-Perfect verification
    const rateMatch = quality.match(/(\d+(?:\.\d+)?)\s*(?:kHz|кГц)/i);
    const sourceRateHz = rateMatch ? Math.round(parseFloat(rateMatch[1]) * 1000) : (t && (t.sample_rate || t.sampleRate) ? Number(t.sample_rate || t.sampleRate) : null);
    const depthMatch = quality.match(/(\d+)-(?:bit|бит)/i);
    const sourceBitDepth = depthMatch ? parseInt(depthMatch[1], 10) : (t && (t.bit_depth || t.bitDepth) ? Number(t.bit_depth || t.bitDepth) : null);

    const ratesMatch = !sourceRateHz || Math.abs(sourceRateHz - devRateHz) <= 500;
    const depthsMatch = !sourceBitDepth || outBitDepth >= sourceBitDepth;
    const isVerified = (state.isBitPerfect !== false) && !isLossy && ratesMatch && depthsMatch;

    if (dom.signalSourceBadge) dom.signalSourceBadge.textContent = formatBadge;
    if (dom.signalSourceTitle) {
      dom.signalSourceTitle.textContent = t ? `${t.name} — ${t.artist}` : 'Apple Music';
    }
    if (dom.signalSourceDetails) {
      dom.signalSourceDetails.textContent = isLossy ? 'AAC 256 kbps → Декодирование в PCM 16-бит / 44.1 кГц' : quality;
    }
    if (dom.signalDacRate) {
      dom.signalDacRate.textContent = `${rateKhz} кГц`;
    }
    const activeDev = (state.audioDevices || []).find(d => d.name === state.audioDeviceName || d.isDefault);
    const isNetworkRenderer = (activeDev && activeDev.type === 'dlna') || (state.audioDeviceName && (state.audioDeviceName.includes('(') || state.audioDeviceName.includes('NODE') || state.audioDeviceName.includes('Bluesound') || state.audioDeviceName.includes('DLNA')));

    const dacBadge = document.querySelector('#signal-node-dac .signal-node-badge');
    if (dacBadge) {
      if (isNetworkRenderer) {
        const isBluOS = (activeDev && activeDev.protocol === 'bluos') || (state.audioDeviceName && state.audioDeviceName.includes('Bluesound'));
        dacBadge.textContent = isBluOS ? 'СЕТЕВОЙ СТРИМЕР' : 'СЕТЕВОЙ ЦАП';
      } else {
        dacBadge.textContent = 'ВЫХОДНОЙ ЦАП';
      }
    }
    if (dom.signalDacName) {
      dom.signalDacName.textContent = state.audioDeviceName || 'Аудиовыход macOS';
    }
    if (dom.signalDacDetails) {
      if (isNetworkRenderer) {
        const isBluOS = (activeDev && activeDev.protocol === 'bluos') || (state.audioDeviceName && state.audioDeviceName.includes('Bluesound'));
        if (isLossy) {
          const protoName = isBluOS ? 'BluOS PCM Stream' : 'DLNA / UPnP';
          dom.signalDacDetails.textContent = `Сетевой PCM стриминг (${protoName}) • ${outBitDepth}-бит / ${rateKhz} кГц`;
        } else {
          const isHiRes = devRateHz > 48000;
          const protoName = isBluOS ? (isHiRes ? 'BluOS Hi-Res Stream' : 'BluOS Lossless Stream') : 'DLNA / UPnP';
          const streamLabel = isHiRes ? 'Сетевой Hi-Res стриминг' : 'Сетевой Lossless стриминг';
          dom.signalDacDetails.textContent = `${streamLabel} (${protoName}) • ${outBitDepth}-бит / ${rateKhz} кГц`;
        }
      } else {
        dom.signalDacDetails.textContent = `Прямое подключение macOS CoreAudio HAL (${outBitDepth}-бит / ${rateKhz} кГц)`;
      }
    }
    const signalEngineMeta = document.querySelector('#signal-node-engine .signal-node-meta');
    if (signalEngineMeta) {
      if (isNetworkRenderer) {
        signalEngineMeta.textContent = isLossy
          ? 'CoreAudio Process Tap • Декодирование AAC → PCM 16-бит / 44.1 кГц'
          : 'CoreAudio Process Tap (Bit-Perfect) • Бесконечный PCM поток';
      } else {
        signalEngineMeta.textContent = isLossy
          ? 'CoreAudio HAL • Декодирование AAC → PCM 16-бит / 44.1 кГц'
          : 'Bit-Perfect 100% Lock • Zero DSP • Bypass микшера';
      }
    }
    const signalVerifiedCard = document.querySelector('.signal-verified-card');
    const signalVerifiedTitle = document.querySelector('.signal-verified-title');
    const signalVerifiedDesc = document.querySelector('.signal-verified-desc');
    if (signalVerifiedCard) {
      signalVerifiedCard.classList.toggle('warning', !isVerified);
    }
    if (signalVerifiedTitle && signalVerifiedDesc) {
      if (isVerified) {
        signalVerifiedTitle.textContent = 'Bit-Perfect Verified';
        if (isNetworkRenderer) {
          signalVerifiedDesc.textContent = `Hi-Res PCM поток (${outBitDepth}-бит / ${rateKhz} кГц) захватывается напрямую из Music.app и передается на сетевой рендерер без передискретизации.`;
        } else {
          signalVerifiedDesc.textContent = `Частота ЦАП (${rateKhz} кГц) аппаратно синхронизирована с потоком. Деградация разрядности исключена.`;
        }
      } else if (isLossy) {
        signalVerifiedTitle.textContent = 'Lossy Stream (AAC 256 kbps)';
        signalVerifiedDesc.textContent = 'Воспроизводится сжатый поток AAC. Для Bit-Perfect переключитесь на трек в формате ALAC Lossless.';
      } else {
        const srcKhz = sourceRateHz ? (sourceRateHz / 1000).toFixed(1).replace(/\.0$/, '') : rateKhz;
        const srcBits = sourceBitDepth || 24;
        signalVerifiedTitle.textContent = `Передискретизация (${srcBits}/${srcKhz} → ${outBitDepth}/${rateKhz})`;
        signalVerifiedDesc.textContent = `Частота или разрядность источника (${srcBits}-бит / ${srcKhz} кГц) отличается от текущего режима вывода (${outBitDepth}-бит / ${rateKhz} кГц).`;
      }
    }
  }

  const openQualityModal = () => {
    triggerHaptic('light');
    updateSignalPathDetails();
    if (dom.qualityModal) dom.qualityModal.classList.remove('hidden');
  };

  if (dom.audioQualityBadge) dom.audioQualityBadge.addEventListener('click', openQualityModal);
  if (dom.desktopDacBadge) dom.desktopDacBadge.addEventListener('click', openQualityModal);
  if (dom.mobileDacBadge) dom.mobileDacBadge.addEventListener('click', openQualityModal);

  if (dom.btnCloseModal) {
    dom.btnCloseModal.addEventListener('click', () => {
      if (dom.qualityModal) dom.qualityModal.classList.add('hidden');
    });
  }

  // --- Audio Output Devices Modal (DAC Selector) ---
  const openDevicesModal = () => {
    triggerHaptic('light');
    if (dom.devicesModal) {
      dom.devicesModal.classList.remove('hidden');
      send({ action: 'get_audio_devices' });
    }
  };

  if (dom.btnOpenDevices) dom.btnOpenDevices.addEventListener('click', openDevicesModal);

  if (dom.btnCloseDevices) {
    dom.btnCloseDevices.addEventListener('click', () => {
      if (dom.devicesModal) dom.devicesModal.classList.add('hidden');
    });
  }

  if (dom.devicesModal) {
    dom.devicesModal.addEventListener('click', (e) => {
      if (e.target === dom.devicesModal) {
        dom.devicesModal.classList.add('hidden');
      }
    });
  }

  function updateAudioDevices(data) {
    let list = [];
    if (Array.isArray(data)) {
      list = data;
    } else if (data && Array.isArray(data.devices)) {
      list = data.devices;
    }
    state.audioDevices = list;

    const defaultDev = list.find(d => d.isDefault);
    if (defaultDev) {
      state.audioDeviceName = defaultDev.name || state.audioDeviceName;
      if (defaultDev.currentSampleRate) {
        state.audioDeviceSampleRate = defaultDev.currentSampleRate;
      }
    }
    renderAudioDevicesList();
    updateSignalPathDetails();
  }

  function renderAudioDevicesList() {
    if (!dom.audioDevicesList) return;
    dom.audioDevicesList.innerHTML = '';

    if (!state.audioDevices || state.audioDevices.length === 0) {
      dom.audioDevicesList.innerHTML = '<div class="empty-state">Нет доступных аудиоустройств</div>';
      return;
    }

    state.audioDevices.forEach(dev => {
      const isDLNA = (dev.type === 'dlna');
      const item = document.createElement('div');
      item.className = `audio-device-item ${isDLNA ? 'dlna-device' : ''} ${dev.isDefault ? 'active' : ''}`;
      item.setAttribute('data-device-id', String(dev.id));
      if (dev.uid) item.setAttribute('data-device-uid', String(dev.uid));

      let iconSvg = '';
      let subtitle = '';

      if (isDLNA) {
        iconSvg = `
          <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2">
            <rect x="2" y="2" width="20" height="8" rx="2" ry="2"/>
            <rect x="2" y="14" width="20" height="8" rx="2" ry="2"/>
            <line x1="6" y1="6" x2="6.01" y2="6"/>
            <line x1="6" y1="18" x2="6.01" y2="18"/>
          </svg>
        `;
        subtitle = `Сетевой стример • До 192 кГц Hi-Res • ${dev.manufacturer || 'DLNA'}`;
      } else {
        iconSvg = `
          <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M11 5L6 9H2v6h4l5 4V5z"/>
            <path d="M19.07 4.93a10 10 0 0 1 0 14.14M15.54 8.46a5 5 0 0 1 0 7.07"/>
          </svg>
        `;
        const rateText = dev.currentSampleRate ? `${(dev.currentSampleRate / 1000).toFixed(1)} кГц` : '44.1 кГц';
        const ratesCount = Array.isArray(dev.availableSampleRates) ? dev.availableSampleRates.length : 0;
        subtitle = `${rateText} • Bit-Perfect ${ratesCount > 0 ? `(${ratesCount} частот)` : ''}`;
      }

      item.innerHTML = `
        <div class="audio-device-icon">
          ${iconSvg}
        </div>
        <div class="audio-device-info">
          <div class="audio-device-name">
            <span class="audio-device-title">${dev.name || (isDLNA ? 'DLNA Стример' : 'Аудиовыход')}</span>
            ${isDLNA ? '<span class="badge-dlna">DLNA</span>' : ''}
          </div>
          <div class="audio-device-meta">${subtitle}</div>
        </div>
        ${dev.isDefault ? '<span class="audio-device-badge active">Активен</span>' : '<span class="audio-device-badge">Выбрать</span>'}
      `;

      item.addEventListener('click', () => {
        triggerHaptic('medium');
        send({ action: 'set_audio_device', params: { id: dev.id, uid: dev.uid } });
        state.audioDevices.forEach(d => { d.isDefault = (d.id === dev.id); });
        state.audioDeviceName = dev.name;
        if (dev.currentSampleRate) state.audioDeviceSampleRate = dev.currentSampleRate;
        renderAudioDevicesList();
        updateSignalPathDetails();
      });

      dom.audioDevicesList.appendChild(item);
    });
  }

  // --- Apple MusicKit & User Token Handlers ---
  let musicKitInstance = null;

  function initMusicKit(devToken) {
    if (!devToken) return;
    state.developerToken = devToken;
    const setup = () => {
      if (window.MusicKit) {
        try {
          if (!musicKitInstance) {
            window.MusicKit.configure({
              developerToken: devToken,
              app: {
                name: 'Apple Music Remote',
                build: '2.4.0'
              }
            });
            musicKitInstance = window.MusicKit.getInstance();
            if (musicKitInstance && musicKitInstance.isAuthorized) {
              const uToken = musicKitInstance.musicUserToken;
              if (uToken && !state.hasUserToken) {
                send({ action: 'set_user_token', params: { user_token: uToken } });
              }
            }
          }
        } catch (e) {
          console.warn('MusicKit configuration error:', e);
        }
      }
    };
    if (window.MusicKit) {
      setup();
    } else {
      document.addEventListener('musickitloaded', setup);
    }
  }

  function updateUserTokenStatus(data) {
    const hasToken = Boolean(data && (data.has_user_token !== undefined ? data.has_user_token : data.hasUserToken));
    state.hasUserToken = hasToken;
    if (data && data.storefront) {
      state.userStorefront = data.storefront;
    }

    if (hasToken || state.isAccountSynced) {
      if (dom.modalAppleAuth) {
        dom.modalAppleAuth.classList.add('hidden');
        dom.modalAppleAuth.setAttribute('aria-hidden', 'true');
      }

      const activeCountry = state.userStorefront || state.trends.country || 'us';
      if (state.trends.country !== activeCountry) {
        state.trends.country = activeCountry;
        loadTrends(activeCountry);
      }
    } else {
      if (dom.modalAppleAuth && !state.isAccountSynced) {
        dom.modalAppleAuth.classList.remove('hidden');
        dom.modalAppleAuth.setAttribute('aria-hidden', 'false');
      }
    }
  }

  function updateAccountHealth(data) {
    if (!data) return;
    state.accountHealth = data;
    const isSynced = data.status === 'synchronized' || data.is_accounts_matched === true;
    state.isAccountSynced = isSynced;
    const email = data.account_email || data.mac_apple_id || data.macos_account || 'tse.tds@gmail.com';
    const storefront = (data.mac_country_code || data.storefront || data.web_storefront || state.userStorefront || 'us').toUpperCase();
    const hasSub = data.is_subscription_active !== false && data.has_active_subscription !== false;
    const details = data.details || (isSynced ? `Apple Music: подписка активна • Регион ${storefront} • Медиатека синхронизирована` : (data.message || 'Требуется вход'));

    if (dom.homeAccountCard) {
      dom.homeAccountCard.classList.remove('hidden');
    }
    if (dom.accountCardEmail) {
      dom.accountCardEmail.textContent = email;
    }
    if (dom.accountCardBadge) {
      dom.accountCardBadge.textContent = isSynced ? 'СИНХРОНИЗИРОВАНО' : 'ТРЕБУЕТСЯ ВХОД';
      dom.accountCardBadge.className = isSynced ? 'account-sync-badge' : 'account-sync-badge error';
    }
    if (dom.accountStatusDot) {
      dom.accountStatusDot.className = isSynced ? 'account-status-dot synced' : 'account-status-dot error';
    }
    if (dom.accountCardSubtext) {
      dom.accountCardSubtext.textContent = details;
    }

    // Modal details
    if (dom.diagValAccount) dom.diagValAccount.textContent = email;
    if (dom.diagValStatus) {
      dom.diagValStatus.textContent = isSynced ? 'Синхронизировано с Mac' : 'Не синхронизировано';
      dom.diagValStatus.className = isSynced ? 'diag-value green' : 'diag-value red';
    }
    if (dom.diagValStorefront) dom.diagValStorefront.textContent = storefront;
    if (dom.diagValSub) {
      dom.diagValSub.textContent = hasSub ? 'Активна' : 'Не активна';
      dom.diagValSub.className = hasSub ? 'diag-value green' : 'diag-value red';
    }
    if (dom.diagValDac) {
      dom.diagValDac.textContent = state.audioQuality || 'Bit-Perfect Lossless (100% Volume Lock)';
    }

    // If synchronized on Mac, dismiss any blocking modal
    if (isSynced && dom.modalAppleAuth) {
      dom.modalAppleAuth.classList.add('hidden');
      dom.modalAppleAuth.setAttribute('aria-hidden', 'true');
    }
  }

  async function handleAppleIdLogin() {
    triggerHaptic('medium');
    if (dom.authModalStatus) {
      dom.authModalStatus.classList.remove('hidden');
      dom.authModalStatus.innerHTML = '<div class="spinner-sm"></div><span>Инициализация MusicKit...</span>';
    }
    if (dom.btnAuthModalLogin) {
      dom.btnAuthModalLogin.disabled = true;
    }

    if (!window.MusicKit) {
      if (dom.authModalStatus) dom.authModalStatus.innerHTML = '<span>Загрузка MusicKit.js... Повторите через 2 секунды</span>';
      setTimeout(() => {
        if (dom.btnAuthModalLogin) dom.btnAuthModalLogin.disabled = false;
        if (dom.authModalStatus) dom.authModalStatus.classList.add('hidden');
      }, 2500);
      return;
    }

    if (!musicKitInstance && state.developerToken) {
      initMusicKit(state.developerToken);
    }

    if (!musicKitInstance) {
      send({ action: 'get_developer_token' });
      if (dom.authModalStatus) dom.authModalStatus.innerHTML = '<div class="spinner-sm"></div><span>Получение ключа разработчика...</span>';
      setTimeout(() => {
        if (dom.btnAuthModalLogin) dom.btnAuthModalLogin.disabled = false;
        if (state.developerToken && !musicKitInstance) {
          initMusicKit(state.developerToken);
        }
      }, 1500);
      return;
    }

    try {
      if (dom.authModalStatus) dom.authModalStatus.innerHTML = '<div class="spinner-sm"></div><span>Ожидание авторизации Apple ID...</span>';
      const uToken = await musicKitInstance.authorize();
      if (uToken) {
        send({ action: 'set_user_token', params: { user_token: uToken } });
        updateUserTokenStatus({ has_user_token: true });
      }
    } catch (err) {
      console.error('Apple Music authorization error:', err);
    } finally {
      if (dom.btnAuthModalLogin) dom.btnAuthModalLogin.disabled = false;
      if (dom.authModalStatus) dom.authModalStatus.classList.add('hidden');
    }
  }

  async function handleAppleIdLogout() {
    triggerHaptic('medium');
    if (musicKitInstance) {
      try { await musicKitInstance.unauthorize(); } catch (e) {}
    }
    send({ action: 'set_user_token', params: { user_token: '' } });
    updateUserTokenStatus({ has_user_token: false });
  }

  if (dom.btnAuthModalLogin) {
    dom.btnAuthModalLogin.addEventListener('click', handleAppleIdLogin);
  }

  if (dom.btnHeaderLogout) {
    dom.btnHeaderLogout.addEventListener('click', handleAppleIdLogout);
  }

  // Account Diagnostic Modal Listeners
  if (dom.btnAccountDiag) {
    dom.btnAccountDiag.addEventListener('click', () => {
      triggerHaptic('light');
      if (dom.modalAccountDiag) {
        dom.modalAccountDiag.classList.remove('hidden');
        dom.modalAccountDiag.setAttribute('aria-hidden', 'false');
      }
    });
  }
  if (dom.btnCloseAccountDiag) {
    dom.btnCloseAccountDiag.addEventListener('click', () => {
      triggerHaptic('light');
      if (dom.modalAccountDiag) {
        dom.modalAccountDiag.classList.add('hidden');
        dom.modalAccountDiag.setAttribute('aria-hidden', 'true');
      }
    });
  }
  if (dom.btnDoneAccountDiag) {
    dom.btnDoneAccountDiag.addEventListener('click', () => {
      triggerHaptic('light');
      if (dom.modalAccountDiag) {
        dom.modalAccountDiag.classList.add('hidden');
        dom.modalAccountDiag.setAttribute('aria-hidden', 'true');
      }
    });
  }
  if (dom.btnRefreshAccountDiag) {
    dom.btnRefreshAccountDiag.addEventListener('click', () => {
      triggerHaptic('light');
      if (dom.diagValStatus) {
        dom.diagValStatus.textContent = 'Проверка...';
      }
      send({ action: 'get_account_status', params: { refresh: true } });
    });
  }

  // --- Station Creation Modal Listeners ---
  if (dom.btnCreateStation) {
    dom.btnCreateStation.addEventListener('click', () => {
      triggerHaptic('light');
      if (dom.stationOptTrackName) {
        dom.stationOptTrackName.textContent = (state.track && state.track.name) ? state.track.name : 'Не играет';
      }
      if (dom.stationOptArtistName) {
        dom.stationOptArtistName.textContent = (state.track && state.track.artist) ? state.track.artist : 'Apple Music';
      }
      if (dom.stationPickerModal) {
        dom.stationPickerModal.classList.remove('hidden');
      }
    });
  }

  if (dom.btnCloseStationModal) {
    dom.btnCloseStationModal.addEventListener('click', () => {
      if (dom.stationPickerModal) dom.stationPickerModal.classList.add('hidden');
    });
  }

  if (dom.stationPickerModal) {
    dom.stationPickerModal.addEventListener('click', (e) => {
      if (e.target === dom.stationPickerModal) {
        dom.stationPickerModal.classList.add('hidden');
      }
    });
  }

  if (dom.btnStationByTrack) {
    dom.btnStationByTrack.addEventListener('click', () => {
      triggerHaptic('medium');
      if (dom.stationPickerModal) dom.stationPickerModal.classList.add('hidden');
      const trackName = state.track ? state.track.name : '';
      const artistName = state.track ? state.track.artist : '';
      if (!trackName) return;
      markWaitingForPlayback({ isStation: true, targetName: trackName });
      setUIBusy(true, `Запуск радио по треку «${trackName}»...`);
      send({
        action: 'play_station',
        params: {
          type: 'track',
          title: trackName,
          artist: artistName,
          name: `Станция «${trackName}»`
        }
      });
    });
  }

  if (dom.btnStationByArtist) {
    dom.btnStationByArtist.addEventListener('click', () => {
      triggerHaptic('medium');
      if (dom.stationPickerModal) dom.stationPickerModal.classList.add('hidden');
      const artistName = state.track ? state.track.artist : '';
      if (!artistName) return;
      markWaitingForPlayback({ isStation: true, targetName: artistName });
      setUIBusy(true, `Запуск радио по артисту «${artistName}»...`);
      send({
        action: 'play_station',
        params: {
          type: 'artist',
          artist: artistName,
          name: `Станция «${artistName}»`
        }
      });
    });
  }

  dom.qualityModal.addEventListener('click', (e) => {
    if (e.target === dom.qualityModal) {
      dom.qualityModal.classList.add('hidden');
    }
  });

  // --- Volume Control & Settings Listeners ---
  let lastVolumeSendTime = 0;
  let volumeSendTimeout = null;

  function sendThrottledVolume(val) {
    const vol = Math.max(0, Math.min(100, Math.round(Number(val) || 0)));
    state.volume = vol;
    if (vol > 0) state.previousVolume = vol;

    if (dom.volumeTrackFill) dom.volumeTrackFill.style.width = `${vol}%`;
    if (dom.volumeThumb) dom.volumeThumb.style.left = `${vol}%`;
    if (dom.volumeLevelText) dom.volumeLevelText.textContent = `${vol}%`;
    updateVolumeIcon(vol);

    const now = Date.now();
    if (now - lastVolumeSendTime >= 75) {
      lastVolumeSendTime = now;
      send({ action: 'set_volume', params: { volume: vol } });
    } else {
      if (volumeSendTimeout) clearTimeout(volumeSendTimeout);
      volumeSendTimeout = setTimeout(() => {
        lastVolumeSendTime = Date.now();
        send({ action: 'set_volume', params: { volume: vol } });
      }, 75);
    }
  }

  if (dom.volumeInput) {
    dom.volumeInput.addEventListener('input', (e) => {
      state.isDraggingVolume = true;
      sendThrottledVolume(e.target.value);
    });

    dom.volumeInput.addEventListener('change', (e) => {
      state.isDraggingVolume = false;
      sendThrottledVolume(e.target.value);
      triggerHaptic('light');
    });
  }

  if (dom.btnVolumeMute) {
    dom.btnVolumeMute.addEventListener('click', () => {
      triggerHaptic('toggle');
      if (state.volume > 0) {
        state.previousVolume = state.volume;
        sendThrottledVolume(0);
      } else {
        const restore = state.previousVolume > 0 ? state.previousVolume : 50;
        sendThrottledVolume(restore);
      }
    });
  }

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
    if (typeof renderStandbyQuickTiles === 'function') {
      renderStandbyQuickTiles();
    }

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

  function isMobilePhoneViewport() {
    return window.matchMedia('(hover: none) and (pointer: coarse)').matches &&
      Math.min(window.innerWidth, window.innerHeight) < 600;
  }

  function isDesktopLayout() {
    return window.innerWidth >= 768 && !isMobilePhoneViewport();
  }

  function navigateToView(viewId, desktopTab, skipFetch = false) {
    if (!isDesktopLayout()) {
      switchMobileView(viewId, skipFetch);
    } else {
      switchDesktopTab(desktopTab, skipFetch);
    }
  }

  function findMatchingLocalPlaylist(plName, plId = '') {
    if (!plName && !plId) return null;
    const lower = (plName || '').trim().toLowerCase();
    const id = (plId || '').trim();
    const isEssentials = lower === 'your essentials' || lower === 'мои любимые треки' || id.includes('20e9f373919da080c2f90eaf2e62e914');
    const isChillMix = lower === 'chill mix' || lower === 'чилл-микс';
    const isNewMusicMix = lower === 'new music mix' || lower === 'микс новинок';
    const isFavoritesMix = lower === 'favorites mix' || lower === 'в моём вкусе: микс' || lower === 'в моем вкусе: микс';
    const isGetUpMix = lower === 'get up! mix' || lower === 'энергетический микс';

    return (state.playlists || []).find(p => {
      const pn = (p.name || '').trim().toLowerCase();
      if (pn === lower) return true;
      if (isEssentials && (pn === 'мои любимые треки' || pn === 'your essentials')) return true;
      if (isChillMix && (pn === 'chill mix' || pn === 'чилл-микс')) return true;
      if (isNewMusicMix && (pn === 'new music mix' || pn === 'микс новинок')) return true;
      if (isFavoritesMix && (pn === 'favorites mix' || pn === 'в моём вкусе: микс' || pn === 'в моем вкусе: микс')) return true;
      if (isGetUpMix && (pn === 'get up! mix' || pn === 'энергетический микс')) return true;
      return false;
    }) || null;
  }

  function resolveDetailOrigin(originParam) {
    if (typeof originParam === 'string' && originParam) return originParam;
    if (originParam === true) {
      if (dom.sectionGridView && dom.sectionGridView.classList.contains('active')) {
        return 'home-grid';
      }
      return 'home';
    }
    return 'library';
  }

  function openPlaylistDetail(pl, fromOrigin = false) {
    const origin = resolveDetailOrigin(fromOrigin);
    state.detailReturnOrigin = origin;
    state.albumOpenedFromHome = (origin === 'home' || origin === 'home-grid');
    state.detailOpenedFromHome = (origin === 'home' || origin === 'home-grid');
    state.currentPlaylistDetail = pl;
    if (dom.detailBadge) dom.detailBadge.textContent = 'ПЛЕЙЛИСТ';
    const plName = pl.name || pl.title || '';
    dom.detailTitle.textContent = plName;
    const count = pl.track_count || pl.trackCount || 0;
    dom.detailMeta.textContent = count > 0 ? `${count} треков` : (pl.curator_name || pl.curatorName || 'Apple Music');
    dom.detailArtwork.src = pl.artwork_url || pl.artworkUrl || pl.artwork || 'apple-touch-icon.svg';
    dom.playlistTracksList.innerHTML = '<div class="loading-state">Загрузка треков...</div>';

    const matchedLocal = findMatchingLocalPlaylist(plName, pl.id);
    const isAlreadyInLib = Boolean(pl.is_local) || Boolean(matchedLocal);

    if (dom.btnAddPlaylistLibrary) {
      dom.btnAddPlaylistLibrary.style.display = '';
      if (isAlreadyInLib) {
        dom.btnAddPlaylistLibrary.disabled = true;
        if (dom.btnAddPlaylistLibraryText) dom.btnAddPlaylistLibraryText.textContent = 'В медиатеке ✓';
        dom.btnAddPlaylistLibrary.classList.add('added');
      } else {
        dom.btnAddPlaylistLibrary.disabled = false;
        if (dom.btnAddPlaylistLibraryText) dom.btnAddPlaylistLibraryText.textContent = 'В медиатеку';
        dom.btnAddPlaylistLibrary.classList.remove('added');
      }
    }

    navigateToView('view-library', 'library', true);
    if (dom.playlistsBrowsePane) dom.playlistsBrowsePane.classList.add('hidden');
    if (dom.playlistDetailPane) dom.playlistDetailPane.classList.remove('hidden');

    send({
      action: 'get_playlist_tracks',
      params: {
        name: plName,
        id: pl.id || '',
        url: pl.url || ''
      }
    });
  }

  function openAlbumDetail(alb, fromOrigin = true) {
    const origin = resolveDetailOrigin(fromOrigin);
    state.detailReturnOrigin = origin;
    state.albumOpenedFromHome = (origin === 'home' || origin === 'home-grid');
    state.detailOpenedFromHome = (origin === 'home' || origin === 'home-grid');
    state.currentPlaylistDetail = { ...alb, isAlbum: true };
    if (dom.detailTitle) dom.detailTitle.textContent = alb.name || alb.title || 'Альбом';
    if (dom.detailMeta) dom.detailMeta.textContent = alb.artist || alb.sub || alb.subtitle || '';
    if (dom.detailArtwork) dom.detailArtwork.src = alb.artwork || alb.artwork_url || 'apple-touch-icon.svg';
    if (dom.detailBadge) dom.detailBadge.textContent = 'АЛЬБОМ';
    if (dom.playlistTracksList) dom.playlistTracksList.innerHTML = '<div class="loading-state">Загрузка треков альбома...</div>';

    if (dom.btnAddPlaylistLibrary) {
      dom.btnAddPlaylistLibrary.style.display = 'none';
    }

    navigateToView('view-library', 'library', true);
    if (dom.playlistsBrowsePane) dom.playlistsBrowsePane.classList.add('hidden');
    if (dom.playlistDetailPane) dom.playlistDetailPane.classList.remove('hidden');

    send({
      action: 'get_album',
      params: {
        id: alb.id || '',
        name: alb.name || alb.title || '',
        artist: alb.artist || alb.sub || alb.subtitle || '',
        country: state.userStorefront || state.trends.country || 'us'
      }
    });
  }

  dom.btnBackToPlaylists.addEventListener('click', () => {
    dom.playlistDetailPane.classList.add('hidden');
    const origin = state.detailReturnOrigin || (state.albumOpenedFromHome || state.detailOpenedFromHome ? 'home' : 'library');
    state.detailReturnOrigin = null;
    state.albumOpenedFromHome = false;
    state.detailOpenedFromHome = false;

    if (origin === 'search') {
      navigateToView('view-search', 'search');
    } else if (origin === 'home-grid') {
      navigateToView('view-home', 'home');
      if (dom.viewHome) dom.viewHome.classList.remove('active');
      if (dom.sectionGridView) {
        dom.sectionGridView.classList.remove('hidden');
        dom.sectionGridView.classList.add('active');
      }
    } else if (origin === 'home') {
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
    const plName = state.currentPlaylistDetail.name || state.currentPlaylistDetail.title || '';
    const matchedLocal = findMatchingLocalPlaylist(plName, state.currentPlaylistDetail.id);
    const isLocalPlaylist = !isAlbum && (Boolean(state.currentPlaylistDetail.is_local) || Boolean(matchedLocal));

    optimisticPlay();
    markWaitingForPlayback({ targetName: plName });
    if (isAlbum) {
      setUIBusy(true, 'Запуск альбома...', dom.btnPlayPlaylist);
    } else if (isLocalPlaylist) {
      setUIBusy(true, 'Запуск плейлиста...', dom.btnPlayPlaylist);
    } else {
      setUIBusy(true, 'Синхронизация очереди в Apple Music (~10 сек)...', dom.btnPlayPlaylist);
    }

    if (isAlbum) {
      send({
        action: 'play_album',
        params: {
          id: state.currentPlaylistDetail.id || '',
          name: plName,
          artist: state.currentPlaylistDetail.artist || state.currentPlaylistDetail.sub || state.currentPlaylistDetail.subtitle || '',
          tracks: (state.currentAlbumDetail && state.currentAlbumDetail.tracks) || [],
          shuffle: false
        }
      });
    } else if (isLocalPlaylist) {
      send({
        action: 'play_playlist',
        params: {
          playlist: matchedLocal ? matchedLocal.name : plName,
          shuffle: false,
          is_local: true
        }
      });
    } else {
      send({
        action: 'play_playlist',
        params: {
          playlist: plName,
          id: state.currentPlaylistDetail.id || '',
          url: state.currentPlaylistDetail.url || '',
          tracks: state.currentPlaylistTracks || [],
          shuffle: false
        }
      });
    }
  });

  dom.btnShufflePlaylist.addEventListener('click', () => {
    if (!state.currentPlaylistDetail) return;
    const isAlbum = Boolean(state.currentPlaylistDetail.isAlbum);
    const plName = state.currentPlaylistDetail.name || state.currentPlaylistDetail.title || '';
    const matchedLocal = findMatchingLocalPlaylist(plName, state.currentPlaylistDetail.id);
    const isLocalPlaylist = !isAlbum && (Boolean(state.currentPlaylistDetail.is_local) || Boolean(matchedLocal));

    optimisticPlay();
    markWaitingForPlayback({ targetName: plName });
    if (isAlbum) {
      setUIBusy(true, 'Перемешивание альбома...', dom.btnShufflePlaylist);
    } else if (isLocalPlaylist) {
      setUIBusy(true, 'Перемешивание...', dom.btnShufflePlaylist);
    } else {
      setUIBusy(true, 'Синхронизация очереди в Apple Music (~10 сек)...', dom.btnShufflePlaylist);
    }

    if (isAlbum) {
      send({
        action: 'play_album',
        params: {
          id: state.currentPlaylistDetail.id || '',
          name: plName,
          artist: state.currentPlaylistDetail.artist || state.currentPlaylistDetail.sub || state.currentPlaylistDetail.subtitle || '',
          tracks: (state.currentAlbumDetail && state.currentAlbumDetail.tracks) || [],
          shuffle: true
        }
      });
    } else if (isLocalPlaylist) {
      send({
        action: 'play_playlist',
        params: {
          playlist: matchedLocal ? matchedLocal.name : plName,
          shuffle: true,
          is_local: true
        }
      });
    } else {
      send({
        action: 'play_playlist',
        params: {
          playlist: plName,
          id: state.currentPlaylistDetail.id || '',
          url: state.currentPlaylistDetail.url || '',
          tracks: state.currentPlaylistTracks || [],
          shuffle: true
        }
      });
    }
  });

  if (dom.btnAddPlaylistLibrary) {
    dom.btnAddPlaylistLibrary.addEventListener('click', () => {
      if (!state.currentPlaylistDetail || !state.currentPlaylistDetail.id) return;
      const plId = state.currentPlaylistDetail.id;
      const plName = state.currentPlaylistDetail.name || state.currentPlaylistDetail.title || '';
      dom.btnAddPlaylistLibrary.disabled = true;
      if (dom.btnAddPlaylistLibraryText) dom.btnAddPlaylistLibraryText.textContent = 'Добавление...';
      send({
        action: 'add_playlist_to_library',
        params: { id: plId, name: plName }
      });
      setTimeout(() => {
        if (dom.btnAddPlaylistLibraryText) dom.btnAddPlaylistLibraryText.textContent = 'Добавлено ✓';
        dom.btnAddPlaylistLibrary.classList.add('added');
        showToast('Плейлист добавлен в медиатеку Apple Music');
      }, 1000);
    });
  }

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
        optimisticPlay();
        markWaitingForPlayback({ targetName: t.name || alb.name || '' });
        setUIBusy(true, 'Запуск трека...');
        send({
          action: 'play_album',
          params: {
            id: alb.id || '',
            name: alb.name || '',
            artist: alb.artist || '',
            tracks: tracks,
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
    state.currentPlaylistTracks = tracks;
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
        const plName = state.currentPlaylistDetail.name || state.currentPlaylistDetail.title || '';
        const matchedLocal = findMatchingLocalPlaylist(plName, state.currentPlaylistDetail.id);
        const isLocalPlaylist = !state.currentPlaylistDetail.isAlbum && (Boolean(state.currentPlaylistDetail.is_local) || Boolean(matchedLocal));
        optimisticPlay();
        state.waitingForPlayback = true;
        if (isLocalPlaylist) {
          setUIBusy(true, 'Запуск трека...');
        } else {
          setUIBusy(true, 'Синхронизация очереди в Apple Music (~10 сек)...');
        }
        if (isLocalPlaylist) {
          send({
            action: 'play_playlist',
            params: {
              playlist: matchedLocal ? matchedLocal.name : plName,
              track_index: idx + 1,
              track_id: t.numeric_id || t.id,
              shuffle: false,
              is_local: true
            }
          });
        } else {
          send({
            action: 'play_playlist',
            params: {
              playlist: plName,
              id: state.currentPlaylistDetail.id || '',
              url: state.currentPlaylistDetail.url || '',
              track_index: idx + 1,
              track_id: t.numeric_id || t.id,
              tracks: state.currentPlaylistTracks || []
            }
          });
        }
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

  let currentSearchSongs = [];
  let currentSearchOffset = 0;
  let currentSearchHasMore = false;
  let isSearchLoadingMore = false;

  function executeSearch(query, scope, offset = 0) {
    if (offset === 0) {
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
    send({
      action: 'search',
      params: {
        query: query,
        country: state.userStorefront || state.trends.country || 'us',
        scope: scope,
        limit: 25,
        offset: offset
      }
    });
  }

  function createTrackRow(s) {
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

  function updateSearchResults(data) {
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
        const isPlayingSearch = Boolean(
          state.queue &&
          (state.queue.playlist === 'Результаты поиска' || state.queue.playlist === 'Очередь AMR')
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
    currentSearchSongs = [...songs];
    currentSearchOffset = songs.length;
    currentSearchHasMore = hasMore;

    if (songs.length === 0 && albums.length === 0 && artists.length === 0 && playlists.length === 0) {
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
        const art = pl.artwork_url || pl.artwork || 'apple-touch-icon.svg';
        const plName = pl.name || 'Плейлист';
        const plSub = pl.curator_name || pl.curator || pl.subtitle || 'Apple Music';

        card.innerHTML = `
          <div class="media-card-art-wrap">
            <img class="playlist-card-art" src="${art}" alt="" loading="lazy" onerror="this.src='apple-touch-icon.svg'">
          </div>
          <span class="playlist-card-title">${escapeHtml(plName)}</span>
          <span class="playlist-card-count">${escapeHtml(plSub)}</span>
        `;

        card.addEventListener('click', () => {
          openPlaylistDetail({
            id: pl.id || '',
            name: plName,
            url: pl.url || '',
            artwork_url: art,
            track_count: pl.track_count || 25,
            curator_name: plSub,
            is_local: Boolean(pl.is_local)
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

  function playSearchResultsList(songs, shuffle, startIndex = 0) {
    if (!songs || songs.length === 0) return;
    optimisticPlay();
    markWaitingForPlayback({ targetName: 'Результаты поиска' });
    setUIBusy(true, shuffle ? 'Перемешивание...' : 'Запуск результатов...');
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
        startIndex: startIndex,
        shuffle: Boolean(shuffle),
        query: state.searchQuery || ''
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
      artwork: 'https://is1-ssl.mzstatic.com/image/thumb/Features/v4/e9/31/64/e93164c8-bff1-a5d9-1ad9-99ff0042a5c1/412b88f3-3259-4c12-8d9c-98b28c6371d4.png/600x600sr.jpg',
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

  let lastTrendsLoadedTime = 0;
  let lastTrendsCountry = '';

  function loadTrends(country, force = false) {
    if (country) {
      state.trends.country = country;
    }
    const c = state.userStorefront || state.trends.country || 'us';
    state.trends.country = c;

    const now = Date.now();
    if (!force && lastTrendsCountry === c && now - lastTrendsLoadedTime < 30000 && state.trends.stations && state.trends.stations.length > 0) {
      return;
    }
    lastTrendsLoadedTime = now;
    lastTrendsCountry = c;

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
      state.trends.top_albums = data.top_albums;
    }
    if (data.new_releases && data.new_releases.length > 0) {
      state.trends.new_releases = data.new_releases;
    }
    if (data.personal_mixes && data.personal_mixes.length > 0) {
      state.trends.personal_mixes = data.personal_mixes;
    }
    if (data.genres && data.genres.length > 0) {
      state.trends.genres = data.genres;
    }

    // 1. Section 1: Hero Featured Carousel (Подборка лучших)
    renderHeroCarousel(data);

    // 2. Section 2: Personal Weekly Mixes (Еженедельные миксы)
    renderPersonalMixes(data.personal_mixes);

    // 3. Section 3: New Releases & Popular Albums (Новинки и альбомы)
    const combinedAlbums = (data.new_releases && data.new_releases.length > 0)
      ? [...data.new_releases, ...(state.trends.topAlbums || []).filter(a => !data.new_releases.some(nr => `${nr.id}` === `${a.id}`))]
      : (state.trends.topAlbums || []);
    if (combinedAlbums.length > 0) {
      renderHomeAlbums(combinedAlbums);
    }

    // 4. Dynamic Recommendations & Heavy Rotation
    if (dom.homeRecContainer) {
      dom.homeRecContainer.innerHTML = '';
    }
    renderPersonalRecommendations(data.personal_recommendations);
    renderHeavyRotation(data.heavy_rotation);
    renderSimilarRecommendations(data.recommended_similar);

    // 5. Stations (Станции для вас ›)
    renderHomeStations(state.trends.stations || DEFAULT_STATIONS);

    // 6. Recently Played (Вы недавно слушали ›)
    const recents = (data.recently_played && data.recently_played.length > 0)
      ? data.recently_played
      : (data.top_picks || []);
    state.recentlyPlayed = recents;
    renderRecentlyPlayed(recents);

    // 7. Genres (Жанры и категории ›)
    renderHomeGenres(state.trends.genres || DEFAULT_GENRES);
  }

  // Animated Plaque Generator for Personal Stations, Weekly Mixes & Radio Stations
  function getAnimatedPlaqueHtml(item) {
    if (!item) return null;
    const rawTitle = String(item.title || item.name || '').trim();
    const rawSub = String(item.subtitle || item.sub || '').trim();
    const lowerTitle = rawTitle.toLowerCase();
    const lowerSub = rawSub.toLowerCase();
    const lowerId = String(item.id || '').toLowerCase();
    const lowerUrl = String(item.url || '').toLowerCase();
    const lowerArt = String(item.artwork || item.artwork_url || item.artworkUrl || '').toLowerCase();
    const lowerType = String(item.type || '').toLowerCase();

    const headerPill = `
      <rect x="184" y="54" width="132" height="26" rx="13" fill="#000000" fill-opacity="0.32" />
      <text x="250" y="71" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="10.5" font-weight="700" letter-spacing="1.6" fill="#ffffff" text-anchor="middle">APPLE MUSIC</text>
    `;

    // 1. Станция открытий (Discovery Station)
    const isDiscovery = lowerTitle.includes('станция открытий') ||
      lowerTitle.includes('discovery station') ||
      (lowerTitle.includes('в моем вкусе') && lowerSub.includes('станция открытий')) ||
      lowerId === 'station_discovery' ||
      lowerId.startsWith('ra.q-') ||
      (lowerArt.includes('coverdiscovery') && !lowerTitle.includes('country') && !lowerTitle.includes('подобные') && !lowerTitle.includes('similar'));

    if (isDiscovery) {
      const dispTitle = lowerTitle.includes('в моем вкусе') ? 'СТАНЦИЯ ОТКРЫТИЙ' : (rawTitle.toUpperCase() || 'СТАНЦИЯ ОТКРЫТИЙ');
      return `
        <div class="animated-plaque-wrap" style="background: linear-gradient(135deg, #10042c 0%, #3a0ca3 38%, #7209b7 72%, #f72585 100%);">
          <div class="animated-plaque-orb" style="background: radial-gradient(circle, rgba(0,229,255,0.45) 0%, rgba(247,37,133,0) 70%);"></div>
          <svg class="animated-plaque-svg" viewBox="0 0 500 500">
            <defs>
              <linearGradient id="discStarG" x1="0%" y1="50%" x2="100%" y2="50%">
                <stop offset="0%" stop-color="#80ffdb" />
                <stop offset="50%" stop-color="#ffffff" />
                <stop offset="100%" stop-color="#ff85a1" />
              </linearGradient>
            </defs>
            ${headerPill}
            <g transform="rotate(-28 250 235)">
              <ellipse class="plaque-dash-flow" cx="250" cy="235" rx="158" ry="86" fill="none" stroke="#48bfe3" stroke-opacity="0.7" stroke-width="2.5" stroke-dasharray="10 12" />
              <circle cx="115" cy="188" r="5" fill="#4cc9f0" class="plaque-breathe" />
              <circle cx="385" cy="282" r="4" fill="#4cc9f0" opacity="0.85" />
            </g>
            <g transform="rotate(24 250 235)">
              <ellipse cx="250" cy="235" rx="152" ry="74" fill="none" stroke="#4cc9f0" stroke-opacity="0.65" stroke-width="2.5" />
              <circle cx="348" cy="176" r="6" fill="#ffffff" class="plaque-breathe" />
              <circle cx="136" cy="285" r="5" fill="#f72585" />
            </g>
            <g class="plaque-spin-slow">
              <polygon points="250,155 264,221 330,235 264,249 250,315 236,249 170,235 236,221" fill="#ffffff" fill-opacity="0.55" transform="rotate(45 250 235)" />
            </g>
            <g class="plaque-breathe">
              <polygon points="250,110 268,217 375,235 268,253 250,360 232,253 125,235 232,217" fill="url(#discStarG)" />
            </g>
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="27" font-weight="600" fill="#ffffff" text-anchor="middle">${escapeHtml(dispTitle)}</text>
            <text x="250" y="448" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="12" font-weight="600" letter-spacing="2.4" fill="#4cc9f0" text-anchor="middle">DISCOVERY STATION</text>
          </svg>
        </div>
      `;
    }

    // 2. Моя станция (Personal Station)
    const isPersonal = lowerTitle.includes('моя станция') ||
      lowerTitle.includes('my station') ||
      lowerId === 'station_personal' ||
      lowerId.startsWith('ra.u-') ||
      lowerUrl.includes('my-station') ||
      (lowerArt.includes('coverpersonal') && !lowerTitle.includes('hits'));

    if (isPersonal) {
      return `
        <div class="animated-plaque-wrap" style="background: linear-gradient(135deg, #590016 0%, #d41442 38%, #ff2a54 70%, #b5179e 100%);">
          <div class="animated-plaque-orb" style="background: radial-gradient(circle, rgba(255,94,58,0.5) 0%, rgba(250,35,59,0) 70%);"></div>
          <svg class="animated-plaque-svg" viewBox="0 0 500 500">
            ${headerPill}
            <circle class="plaque-spin-slow" cx="250" cy="235" r="154" fill="none" stroke="#ffffff" stroke-opacity="0.45" stroke-width="2.5" stroke-dasharray="28 14 12 14" />
            <circle class="plaque-spin-rev" cx="250" cy="235" r="126" fill="none" stroke="#ffffff" stroke-opacity="0.55" stroke-width="3" stroke-dasharray="36 16 14 16" />
            <circle class="plaque-spin-med" cx="250" cy="235" r="98" fill="none" stroke="#ffffff" stroke-opacity="0.65" stroke-width="3.2" stroke-dasharray="22 12 8 12" />
            <circle class="plaque-spin-rev" cx="250" cy="235" r="70" fill="none" stroke="#ffffff" stroke-opacity="0.7" stroke-width="3" stroke-dasharray="18 10" />
            <circle class="plaque-breathe" cx="250" cy="235" r="42" fill="none" stroke="#ffffff" stroke-opacity="0.5" stroke-width="2.5" />
            <g class="plaque-wave-anim">
              <path d="M 142 235 L 210 235 L 226 172 L 242 298 L 258 194 L 272 262 L 286 235 L 358 235" fill="none" stroke="#ffffff" stroke-width="8.5" stroke-linecap="round" stroke-linejoin="round" />
            </g>
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="29" font-weight="600" fill="#ffffff" text-anchor="middle">МОЯ СТАНЦИЯ</text>
            <text x="250" y="448" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="12" font-weight="500" letter-spacing="2.4" fill="#ffffff" fill-opacity="0.82" text-anchor="middle">PERSONAL STATION</text>
          </svg>
        </div>
      `;
    }

    // 3. В моём вкусе / Favorites Mix / Your Essentials
    const isFavoritesMix = lowerTitle.includes('в моем вкусе') ||
      lowerTitle.includes('в моём вкусе') ||
      lowerTitle.includes('favorites mix') ||
      lowerTitle.includes('your essentials') ||
      lowerTitle.includes('избранн') ||
      lowerId === 'favorites_mix';

    if (isFavoritesMix) {
      return `
        <div class="animated-plaque-wrap" style="background: linear-gradient(135deg, #2b0538 0%, #9b0068 38%, #ff0a6c 72%, #ff5e7e 100%);">
          <div class="animated-plaque-orb" style="background: radial-gradient(circle, rgba(255,10,108,0.55) 0%, rgba(155,0,104,0) 70%);"></div>
          <svg class="animated-plaque-svg" viewBox="0 0 500 500">
            ${headerPill}
            <circle class="plaque-spin-slow" cx="250" cy="235" r="146" fill="none" stroke="#ffffff" stroke-opacity="0.35" stroke-width="2" stroke-dasharray="16 14" />
            <circle class="plaque-spin-rev" cx="250" cy="235" r="114" fill="none" stroke="#ff85a1" stroke-opacity="0.55" stroke-width="2.8" stroke-dasharray="28 14" />
            <circle class="plaque-breathe" cx="250" cy="235" r="84" fill="#ffffff" fill-opacity="0.08" stroke="#ffffff" stroke-opacity="0.45" stroke-width="2" />
            <g class="plaque-heartbeat">
              <path d="M 250 288 C 250 288 188 244 188 202 C 188 178 207 162 228 162 C 241 162 250 171 250 179 C 250 171 259 162 272 162 C 293 162 312 178 312 202 C 312 244 250 288 250 288 Z" fill="#ffffff" fill-opacity="0.95" />
              <path d="M 212 216 L 232 216 L 241 194 L 250 238 L 259 204 L 268 216 L 288 216" fill="none" stroke="#d41442" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round" />
            </g>
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="28" font-weight="600" fill="#ffffff" text-anchor="middle">В МОЁМ ВКУСЕ</text>
            <text x="250" y="448" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="12" font-weight="500" letter-spacing="2.4" fill="#ffb3c6" text-anchor="middle">FAVORITES MIX</text>
          </svg>
        </div>
      `;
    }

    // 4. Сейчас на повторе (Heavy Rotation Mix)
    const isHeavyRotation = lowerTitle.includes('на повторе') ||
      lowerTitle.includes('heavy rotation') ||
      lowerArt.includes('coverheavyrotation');

    if (isHeavyRotation) {
      return `
        <div class="animated-plaque-wrap" style="background: linear-gradient(135deg, #ff5e3a 0%, #ff2a6d 55%, #7b0046 100%);">
          <div class="animated-plaque-orb" style="background: radial-gradient(circle, rgba(255,180,80,0.45) 0%, rgba(255,42,109,0) 70%);"></div>
          <svg class="animated-plaque-svg" viewBox="0 0 500 500">
            ${headerPill}
            <circle class="plaque-spin-slow" cx="250" cy="235" r="142" fill="none" stroke="#ffffff" stroke-opacity="0.45" stroke-width="2.2" stroke-dasharray="10 10" />
            <circle class="plaque-spin-rev" cx="250" cy="235" r="104" fill="none" stroke="#ffffff" stroke-opacity="0.6" stroke-width="3" stroke-dasharray="16 12" />
            <circle class="plaque-spin-med" cx="250" cy="235" r="66" fill="none" stroke="#ffffff" stroke-opacity="0.75" stroke-width="3.5" stroke-dasharray="32 12" />
            <g class="plaque-spin-med">
              <path d="M 210 215 C 230 195, 270 195, 290 215 C 310 235, 310 265, 290 285 C 270 305, 230 305, 210 285 M 275 285 L 290 285 L 290 300" fill="none" stroke="#ffffff" stroke-width="11" stroke-linecap="round" stroke-linejoin="round" />
            </g>
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="27" font-weight="600" fill="#ffffff" text-anchor="middle">СЕЙЧАС НА ПОВТОРЕ</text>
            <text x="250" y="448" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="12" font-weight="500" letter-spacing="2.2" fill="#ffffff" fill-opacity="0.82" text-anchor="middle">HEAVY ROTATION MIX</text>
          </svg>
        </div>
      `;
    }

    // 5. Новинки для вас (New Music Mix)
    const isNewMusicMix = lowerTitle.includes('новинки для вас') ||
      lowerTitle.includes('new music mix') ||
      lowerTitle.includes('микс новинок');

    if (isNewMusicMix) {
      return `
        <div class="animated-plaque-wrap" style="background: linear-gradient(135deg, #051937 0%, #004d7a 42%, #008793 75%, #00bf72 100%);">
          <div class="animated-plaque-orb" style="background: radial-gradient(circle, rgba(0,245,212,0.45) 0%, rgba(0,77,122,0) 70%);"></div>
          <svg class="animated-plaque-svg" viewBox="0 0 500 500">
            ${headerPill}
            <circle class="plaque-spin-slow" cx="250" cy="235" r="144" fill="none" stroke="#80ffdb" stroke-opacity="0.45" stroke-width="2.2" stroke-dasharray="20 12" />
            <circle class="plaque-spin-rev" cx="250" cy="235" r="106" fill="none" stroke="#ffffff" stroke-opacity="0.55" stroke-width="2.8" stroke-dasharray="12 16" />
            <g class="plaque-breathe">
              <polygon points="250,138 268,217 347,235 268,253 250,332 232,253 153,235 232,217" fill="#ffffff" fill-opacity="0.92" />
              <circle cx="250" cy="235" r="24" fill="#00f5d4" />
            </g>
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="27" font-weight="600" fill="#ffffff" text-anchor="middle">НОВИНКИ ДЛЯ ВАС</text>
            <text x="250" y="448" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="12" font-weight="500" letter-spacing="2.2" fill="#80ffdb" text-anchor="middle">NEW MUSIC MIX</text>
          </svg>
        </div>
      `;
    }

    // 6. Чилл-микс / Chill & Lo-Fi
    const isChill = lowerTitle.includes('чилл') ||
      lowerTitle.includes('chill') ||
      lowerArt.includes('coverchill');

    if (isChill) {
      const titleText = lowerTitle.includes('lo-fi') ? 'CHILL & LO-FI' : 'ЧИЛЛ-МИКС';
      const subText = lowerTitle.includes('lo-fi') ? 'AMBIENT & LO-FI BEATS' : 'CHILL MIX';
      return `
        <div class="animated-plaque-wrap" style="background: linear-gradient(135deg, #0b132b 0%, #1c2541 38%, #0077b6 74%, #00b4d8 100%);">
          <div class="animated-plaque-orb" style="background: radial-gradient(circle, rgba(144,224,239,0.45) 0%, rgba(28,37,65,0) 70%);"></div>
          <svg class="animated-plaque-svg" viewBox="0 0 500 500">
            ${headerPill}
            <circle class="plaque-breathe" cx="250" cy="215" r="78" fill="#90e0ef" fill-opacity="0.22" stroke="#caf0f8" stroke-opacity="0.7" stroke-width="2.5" />
            <circle class="plaque-spin-slow" cx="250" cy="215" r="118" fill="none" stroke="#90e0ef" stroke-opacity="0.4" stroke-width="2" stroke-dasharray="18 14" />
            <g class="plaque-float-y">
              <path d="M 110 255 Q 180 215 250 255 T 390 255" fill="none" stroke="#ffffff" stroke-width="5.5" stroke-linecap="round" />
              <path d="M 130 285 Q 190 248 250 285 T 370 285" fill="none" stroke="#90e0ef" stroke-width="4" stroke-linecap="round" stroke-opacity="0.85" />
              <path d="M 155 312 Q 202 282 250 312 T 345 312" fill="none" stroke="#caf0f8" stroke-width="3" stroke-linecap="round" stroke-opacity="0.6" />
            </g>
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="27" font-weight="600" fill="#ffffff" text-anchor="middle">${escapeHtml(titleText)}</text>
            <text x="250" y="448" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="12" font-weight="500" letter-spacing="2.2" fill="#90e0ef" text-anchor="middle">${escapeHtml(subText)}</text>
          </svg>
        </div>
      `;
    }

    // 7. Драйв-микс / Заряд энергии (Get Up! Mix)
    const isGetUp = lowerTitle.includes('драйв') ||
      lowerTitle.includes('энерг') ||
      lowerTitle.includes('get up');

    if (isGetUp) {
      return `
        <div class="animated-plaque-wrap" style="background: linear-gradient(135deg, #ff4e00 0%, #ff9500 50%, #ff0055 100%);">
          <div class="animated-plaque-orb" style="background: radial-gradient(circle, rgba(255,230,0,0.5) 0%, rgba(255,0,85,0) 70%);"></div>
          <svg class="animated-plaque-svg" viewBox="0 0 500 500">
            ${headerPill}
            <circle class="plaque-spin-slow" cx="250" cy="235" r="142" fill="none" stroke="#ffffff" stroke-opacity="0.5" stroke-width="3" stroke-dasharray="8 16" />
            <circle class="plaque-spin-rev" cx="250" cy="235" r="106" fill="none" stroke="#fff3b0" stroke-opacity="0.7" stroke-width="2.5" stroke-dasharray="24 12" />
            <g class="plaque-wave-anim">
              <rect x="182" y="195" width="16" height="80" rx="8" fill="#ffffff" />
              <rect x="212" y="160" width="16" height="150" rx="8" fill="#ffffff" />
              <rect x="242" y="140" width="16" height="190" rx="8" fill="#fff3b0" />
              <rect x="272" y="168" width="16" height="134" rx="8" fill="#ffffff" />
              <rect x="302" y="200" width="16" height="70" rx="8" fill="#ffffff" />
            </g>
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="27" font-weight="600" fill="#ffffff" text-anchor="middle">${escapeHtml(rawTitle.toUpperCase() || 'ДРАЙВ-МИКС')}</text>
            <text x="250" y="448" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="12" font-weight="500" letter-spacing="2.2" fill="#fff3b0" text-anchor="middle">GET UP! MIX</text>
          </svg>
        </div>
      `;
    }

    // 8. Микс для друзей (Friends Mix)
    const isFriends = lowerTitle.includes('друзей') || lowerTitle.includes('friends');
    if (isFriends) {
      return `
        <div class="animated-plaque-wrap" style="background: linear-gradient(135deg, #240046 0%, #5a189a 45%, #9d4edd 78%, #ff758f 100%);">
          <div class="animated-plaque-orb" style="background: radial-gradient(circle, rgba(255,117,143,0.45) 0%, rgba(90,24,154,0) 70%);"></div>
          <svg class="animated-plaque-svg" viewBox="0 0 500 500">
            ${headerPill}
            <g class="plaque-spin-slow">
              <circle cx="222" cy="235" r="88" fill="none" stroke="#e0aaff" stroke-opacity="0.7" stroke-width="3.5" />
              <circle cx="278" cy="235" r="88" fill="none" stroke="#ffccd5" stroke-opacity="0.7" stroke-width="3.5" />
            </g>
            <circle class="plaque-breathe" cx="250" cy="235" r="136" fill="none" stroke="#ffffff" stroke-opacity="0.35" stroke-width="2" stroke-dasharray="14 14" />
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="27" font-weight="600" fill="#ffffff" text-anchor="middle">МИКС ДЛЯ ДРУЗЕЙ</text>
            <text x="250" y="448" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="12" font-weight="500" letter-spacing="2.2" fill="#e0aaff" text-anchor="middle">FRIENDS MIX</text>
          </svg>
        </div>
      `;
    }

    // 9. Artist Stations & Genre / Live Stations
    const lowerTag = (item.tag || '').toLowerCase();
    const isArtistStation = lowerTitle.includes('подобные артисты') ||
      lowerTitle.includes('similar artists') ||
      lowerTag.includes('по артисту') ||
      lowerTag.includes('artist station') ||
      lowerSub.includes('по артисту') ||
      lowerSub.includes('artist station');

    if (isArtistStation) {
      if (lowerArt.startsWith('http')) {
        return null;
      }
      const cleanArtist = rawTitle
        .replace(/и другие подобные артисты/gi, '')
        .replace(/& similar artists( station)?/gi, '')
        .replace(/радиостанция/gi, '')
        .trim() || rawTitle;
      const artistFontSize = cleanArtist.length > 18 ? 20 : (cleanArtist.length > 12 ? 24 : 28);
      return `
        <div class="animated-plaque-wrap" style="background: linear-gradient(135deg, #1b1035 0%, #3b1c71 48%, #7b2cbf 82%, #c77dff 100%);">
          <div class="animated-plaque-orb" style="background: radial-gradient(circle, rgba(199,125,255,0.35) 0%, rgba(0,0,0,0) 70%);"></div>
          <svg class="animated-plaque-svg" viewBox="0 0 500 500">
            ${headerPill}
            <circle class="plaque-spin-slow" cx="250" cy="230" r="138" fill="none" stroke="#e0aaff" stroke-opacity="0.38" stroke-width="2" stroke-dasharray="18 12" />
            <circle class="plaque-spin-rev" cx="250" cy="230" r="98" fill="none" stroke="#ffffff" stroke-opacity="0.5" stroke-width="2.5" stroke-dasharray="12 12" />
            <g class="plaque-wave-anim">
              <path d="M 125 230 L 190 230 L 212 165 L 236 290 L 256 190 L 278 270 L 298 178 L 318 275 L 334 230 L 375 230" fill="none" stroke="#ffffff" stroke-width="7" stroke-linecap="round" stroke-linejoin="round" />
            </g>
            <text x="250" y="418" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="${artistFontSize}" font-weight="700" fill="#ffffff" text-anchor="middle">${escapeHtml(cleanArtist.toUpperCase())}</text>
            <text x="250" y="446" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="11.5" font-weight="600" letter-spacing="2" fill="#e0aaff" text-anchor="middle">РАДИОСТАНЦИЯ ПО АРТИСТУ</text>
          </svg>
        </div>
      `;
    }

    const isStationCard = !lowerArt.startsWith('http') && (lowerId.startsWith('station_') || lowerArt.includes('/assets/stations/'));
    if (isStationCard) {
      let bgGrad = 'linear-gradient(135deg, #06281e 0%, #007f5f 48%, #2b9348 78%, #55a630 100%)';
      let accentColor = '#80ffdb';
      let subLabel = 'APPLE MUSIC RADIO';

      if (lowerTitle.includes('electronic') || lowerTitle.includes('dance')) {
        bgGrad = 'linear-gradient(135deg, #041b15 0%, #007f5f 45%, #00b862 82%, #70e000 100%)';
        accentColor = '#80ffdb';
        subLabel = 'CLUB & FESTIVAL BANGERS';
      } else if (lowerTitle.includes('apple music 1')) {
        bgGrad = 'linear-gradient(135deg, #141416 0%, #2c2c30 48%, #fa233b 100%)';
        accentColor = '#ff6b8b';
        subLabel = 'LIVE GLOBAL RADIO';
      } else if (lowerTitle.includes('hits')) {
        bgGrad = 'linear-gradient(135deg, #800f2f 0%, #c9184a 45%, #ff4d6d 80%, #ff8fa3 100%)';
        accentColor = '#ffccd5';
        subLabel = 'ESSENTIAL HITS';
      } else if (lowerTitle.includes('country')) {
        bgGrad = 'linear-gradient(135deg, #582f0e 0%, #b66d0d 48%, #f7971e 82%, #ffd200 100%)';
        accentColor = '#ffe6a7';
        subLabel = 'MODERN COUNTRY';
      } else if (lowerTitle.includes('pop')) {
        bgGrad = 'linear-gradient(135deg, #7209b7 0%, #b5179e 48%, #f72585 100%)';
        accentColor = '#ffafcc';
        subLabel = 'POP ANTHEMS';
      } else if (lowerTitle.includes('deep house') || lowerTitle.includes('house')) {
        bgGrad = 'linear-gradient(135deg, #10002b 0%, #240046 45%, #5a189a 80%, #7b2cbf 100%)';
        accentColor = '#c77dff';
        subLabel = 'DEEP ATMOSPHERIC GROOVE';
      } else if (lowerTitle.includes('rock')) {
        bgGrad = 'linear-gradient(135deg, #1b1b1e 0%, #370617 48%, #9d0208 85%, #dc2f02 100%)';
        accentColor = '#ffba08';
        subLabel = 'ROCK LEGENDS';
      }

      const displayStationTitle = (rawTitle || 'RADIO').toUpperCase();
      const stationFontSize = displayStationTitle.length > 20 ? 19 : (displayStationTitle.length > 14 ? 22 : 25);

      return `
        <div class="animated-plaque-wrap" style="background: ${bgGrad};">
          <div class="animated-plaque-orb" style="background: radial-gradient(circle, rgba(255,255,255,0.22) 0%, rgba(0,0,0,0) 70%);"></div>
          <svg class="animated-plaque-svg" viewBox="0 0 500 500">
            ${headerPill}
            <circle class="plaque-spin-slow" cx="250" cy="235" r="142" fill="none" stroke="${accentColor}" stroke-opacity="0.38" stroke-width="2" stroke-dasharray="22 12" />
            <circle class="plaque-spin-rev" cx="250" cy="235" r="104" fill="none" stroke="#ffffff" stroke-opacity="0.5" stroke-width="2.5" stroke-dasharray="14 14" />
            <g class="plaque-wave-anim">
              <path d="M 110 235 L 185 235 L 208 162 L 234 298 L 256 188 L 278 274 L 300 176 L 320 282 L 336 235 L 390 235" fill="none" stroke="#ffffff" stroke-width="7.5" stroke-linecap="round" stroke-linejoin="round" />
            </g>
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="${stationFontSize}" font-weight="600" fill="#ffffff" text-anchor="middle">${escapeHtml(displayStationTitle)}</text>
            <text x="250" y="448" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="11.5" font-weight="600" letter-spacing="2.2" fill="${accentColor}" text-anchor="middle">${escapeHtml(subLabel)}</text>
          </svg>
        </div>
      `;
    }

    return null;
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
        if (!art) {
          if (lowerTitle.includes('моя станция') || lowerTitle.includes('my station')) art = 'https://is1-ssl.mzstatic.com/image/thumb/Features/v4/e9/31/64/e93164c8-bff1-a5d9-1ad9-99ff0042a5c1/412b88f3-3259-4c12-8d9c-98b28c6371d4.png/600x600sr.jpg';
          else if (lowerTitle.includes('в моем вкусе') || lowerTitle.includes('открытий') || lowerTitle.includes('discovery')) art = '/assets/stations/CoverDiscovery.png';
          else if (lowerTitle.includes('заряд') || lowerTitle.includes('энерг')) art = '/assets/stations/CoverElectronic.png';
          else if (lowerTitle.includes('one ok rock') || lowerTitle.includes('рок')) art = '/assets/stations/CoverRock.png';
        }

        heroCards.push({
          index: c.index || 0,
          title: c.title || 'Apple Music',
          name: c.name || '',
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
          artwork: 'https://is1-ssl.mzstatic.com/image/thumb/Features/v4/e9/31/64/e93164c8-bff1-a5d9-1ad9-99ff0042a5c1/412b88f3-3259-4c12-8d9c-98b28c6371d4.png/600x600sr.jpg'
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

      const cardColor = c.color || 'linear-gradient(135deg, #1c1c1e, #2c2c2e)';
      const animatedPlaque = getAnimatedPlaqueHtml(c);
      const hasArt = c.artwork && c.artwork.trim().length > 0;
      const mediaHtml = animatedPlaque ? animatedPlaque : (hasArt ? `
        <img class="hero-art-img" src="${c.artwork}" alt="${escapeHtml(c.title)}" loading="eager" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
        <div class="hero-art-fallback" style="display:none; background: ${cardColor};">
          <svg viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="currentColor" stroke-width="1.8">
            <path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>
          </svg>
        </div>
      ` : `
        <div class="hero-art-gradient" style="background: ${cardColor}">
          <svg viewBox="0 0 24 24" width="56" height="56" fill="none" stroke="#ffffff" stroke-width="1.8">
            <path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>
          </svg>
        </div>
      `);

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
          openPlaylistDetail({
            id: c.id,
            name: c.name || c.title,
            url: c.url,
            artwork_url: c.artwork,
            track_count: c.track_count || 25
          }, true);
          return;
        }

        optimisticPlay();
        markWaitingForPlayback({
          isStation: (c.type === 'station'),
          targetName: c.title || c.name || ''
        });
        setUIBusy(true, c.type === 'station' ? 'Запуск станции...' : `Запуск ${c.title || c.name || ''}...`);
        send({
          action: 'play_hero_card',
          params: {
            index: c.index,
            name: c.name || c.title,
            artist: c.name || c.sub || c.subtitle || c.artist || '',
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

  // Render Heavy Rotation
  function renderHeavyRotation(heavyRotation) {
    if (!dom.homeHeavyCarousel) return;
    const list = heavyRotation || [];
    if (list.length === 0) {
      if (dom.homeHeavySection) dom.homeHeavySection.classList.add('hidden');
      return;
    }
    if (dom.homeHeavySection) dom.homeHeavySection.classList.remove('hidden');
    dom.homeHeavyCarousel.innerHTML = '';
    list.forEach(t => {
      const card = document.createElement('div');
      card.className = 'media-card';
      const art = t.artwork || 'apple-touch-icon.svg';
      card.innerHTML = `
          <div class="media-card-art-wrap">
            <img class="media-card-art" src="${art}" loading="lazy" alt="Cover">
            <div class="media-play-overlay">
              <div class="media-play-pill">
                <svg viewBox="0 0 24 24" width="16" height="16" fill="#000000"><polygon points="8 5 19 12 8 19 8 5"/></svg>
              </div>
            </div>
          </div>
          <div class="media-card-title">${escapeHtml(t.name || t.album || 'Unknown')}</div>
          <div class="media-card-sub">${escapeHtml(t.artist || '')}</div>
        `;
      card.addEventListener('click', () => {
        openAlbumDetail({
          id: `${t.id || ''}`,
          name: t.name || t.album || '',
          artist: t.artist || '',
          artwork: art,
          url: t.url || ''
        }, 'home');
      });
      dom.homeHeavyCarousel.appendChild(card);
    });
  }

  // Render Personal Weekly Mixes (New Music, Chill, Favorites, Get Up!)
  function renderPersonalMixes(mixes) {
    const list = mixes || [];
    state.personalMixes = list;
    if (typeof renderStandbyQuickTiles === 'function') {
      renderStandbyQuickTiles();
    }
    if (!dom.homeMixesCarousel) return;
    if (list.length === 0) {
      if (dom.homeMixesSection) dom.homeMixesSection.classList.add('hidden');
      return;
    }
    if (dom.homeMixesSection) dom.homeMixesSection.classList.remove('hidden');
    dom.homeMixesCarousel.innerHTML = '';

    list.forEach(mix => {
      const card = document.createElement('div');
      card.className = 'media-card';
      const mName = mix.name || 'Микс';
      const art = mix.artwork || mix.artwork_url || 'apple-touch-icon.svg';
      const curator = mix.curator_name || 'Apple Music';
      const animatedPlaque = getAnimatedPlaqueHtml({ ...mix, title: mName, subtitle: curator });
      const artContent = animatedPlaque
        ? animatedPlaque
        : `<img class="media-card-art" src="${art}" loading="lazy" alt="Cover" onerror="this.src='apple-touch-icon.svg'">`;
      card.innerHTML = `
        <div class="media-card-art-wrap">
          ${artContent}
          <div class="media-play-overlay">
            <div class="media-play-pill">
              <svg viewBox="0 0 24 24" width="16" height="16" fill="#000000"><polygon points="8 5 19 12 8 19 8 5"/></svg>
            </div>
          </div>
        </div>
        <div class="media-card-title">${escapeHtml(mName)}</div>
        <div class="media-card-sub">${escapeHtml(curator)}</div>
      `;
      card.addEventListener('click', () => {
        openPlaylistDetail({
          id: mix.id || '',
          name: mName,
          url: mix.url || '',
          artwork_url: art,
          track_count: mix.track_count || mix.trackCount || 25,
          curator_name: curator
        }, 'home');
      });
      dom.homeMixesCarousel.appendChild(card);
    });
  }

  // Render Personal Recommendations (from Apple Music /v1/me/recommendations)
  function renderPersonalRecommendations(groups) {
    if (!dom.homeRecContainer) return;
    const list = groups || [];
    if (list.length === 0) {
      return;
    }

    list.forEach(grp => {
      const contents = grp.contents || [];
      if (contents.length === 0) return;

      const sec = document.createElement('div');
      sec.className = 'home-section';
      sec.innerHTML = `
        <div class="home-section-header-link">
          <h2 class="home-section-title">${escapeHtml(grp.title || 'Для вас')}</h2>
        </div>
        <div class="home-carousel-row"></div>
      `;
      const carousel = sec.querySelector('.home-carousel-row');

      contents.forEach(item => {
        const card = document.createElement('div');
        card.className = 'media-card';
        const iName = item.name || '';
        const iSub = item.subtitle || '';
        const art = item.artwork || item.artwork_url || 'apple-touch-icon.svg';
        const animatedPlaque = getAnimatedPlaqueHtml({ ...item, title: iName, subtitle: iSub });
        const artContent = animatedPlaque
          ? animatedPlaque
          : `<img class="media-card-art" src="${art}" loading="lazy" alt="Cover" onerror="this.src='apple-touch-icon.svg'">`;

        card.innerHTML = `
          <div class="media-card-art-wrap">
            ${artContent}
            <div class="media-play-overlay">
              <div class="media-play-pill">
                <svg viewBox="0 0 24 24" width="16" height="16" fill="#000000"><polygon points="8 5 19 12 8 19 8 5"/></svg>
              </div>
            </div>
          </div>
          <div class="media-card-title">${escapeHtml(iName)}</div>
          <div class="media-card-sub">${escapeHtml(iSub)}</div>
        `;

        card.addEventListener('click', () => {
          const itemType = (item.type || '').toLowerCase();
          if (itemType === 'album' || itemType === 'albums') {
            openAlbumDetail({
              id: `${item.id || ''}`,
              name: iName,
              artist: iSub,
              artwork: art,
              url: item.url || ''
            }, 'home');
          } else if (itemType === 'playlist' || itemType === 'playlists') {
            openPlaylistDetail({
              id: item.id || '',
              name: iName,
              url: item.url || '',
              artwork_url: art,
              track_count: item.track_count || 25,
              curator_name: iSub
            }, 'home');
          } else {
            optimisticPlay();
            markWaitingForPlayback({ isStation: true, targetName: iName });
            setUIBusy(true, `Запуск ${iName}...`);
            send({
              action: 'play_hero_card',
              params: {
                index: 0,
                name: iName,
                id: item.id || '',
                url: item.url || '',
                type: 'station'
              }
            });
          }
        });

        carousel.appendChild(card);
      });

      dom.homeRecContainer.appendChild(sec);
    });
  }

  // Render Recommendations
  function renderSimilarRecommendations(recommendedArray) {
    if (!dom.homeRecContainer) return;

    if (!recommendedArray || !Array.isArray(recommendedArray) || recommendedArray.length === 0) {
      return;
    }
    
    recommendedArray.forEach((rec, idx) => {
      const list = rec.items || [];
      if (list.length === 0) return;
      
      const section = document.createElement('div');
      section.className = 'home-section';
      
      const title = document.createElement('h2');
      title.className = 'home-section-title';
      title.textContent = rec.title || 'Рекомендации';
      
      const carousel = document.createElement('div');
      carousel.className = 'home-carousel-row';
      
      list.forEach(a => {
        const card = document.createElement('div');
        card.className = 'media-card';
        const aName = a.name || (a.title ? a.title : '');
        const art = a.artwork || 'apple-touch-icon.svg';
        card.innerHTML = `
          <div class="media-card-art-wrap">
            <img class="media-card-art" src="${art}" loading="lazy" alt="Cover">
            <div class="media-play-overlay">
              <div class="media-play-pill">
                <svg viewBox="0 0 24 24" width="16" height="16" fill="#000000"><polygon points="8 5 19 12 8 19 8 5"/></svg>
              </div>
            </div>
          </div>
          <div class="media-card-title">${escapeHtml(aName)}</div>
          <div class="media-card-sub">${escapeHtml(a.artist || '')}</div>
        `;
        card.addEventListener('click', () => {
          openAlbumDetail({
            id: `${a.id || ''}`,
            name: aName,
            artist: a.artist || '',
            artwork: art,
            url: a.url || ''
          }, 'home');
        });
        carousel.appendChild(card);
      });
      
      section.appendChild(title);
      section.appendChild(carousel);
      dom.homeRecContainer.appendChild(section);
    });
  }

  function executeAction(action, params) {
    if (action === 'play_album') {
      setUIBusy(true, 'Запуск альбома...');
      send({
        action: 'play_album',
        params: {
          id: `${params?.id || ''}`,
          name: params?.name || '',
          artist: params?.artist || '',
          url: params?.url || '',
          shuffle: false
        }
      });
    }
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
    const homeList = list.slice(0, 10);

    homeList.forEach(t => {
      const card = document.createElement('div');
      card.className = 'media-card';
      const art = getArtworkSrc(t);

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
        optimisticPlay();
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
    const homeList = list.slice(0, 10);

    container.innerHTML = '';
    homeList.forEach(st => {
      const card = document.createElement('div');
      card.className = 'media-card station-card';
      const isLive = Boolean(st.isLive || st.is_live);
      const gradient = st.color || 'linear-gradient(135deg, #1c1c1e, #2c2c2e)';
      const iconSvg = st.icon || '<svg viewBox="0 0 24 24" width="36" height="36" fill="currentColor"><circle cx="12" cy="12" r="3.2"/><path d="M12 6c-2.76 0-5 2.24-5 5 0 1.63.79 3.08 2 3.99V22l3-2 3 2v-7.01c1.21-.91 2-2.36 2-3.99 0-2.76-2.24-5-5-5z"/></svg>';
      const animatedPlaque = getAnimatedPlaqueHtml({ ...st, type: 'station' });
      const hasImage = Boolean(st.artwork && st.artwork.trim().length > 0 && !st.artwork.includes('apple-touch-icon'));

      const artHtml = animatedPlaque
        ? animatedPlaque
        : (hasImage
          ? `<img class="media-card-art" src="${st.artwork}" alt="" loading="lazy" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
             <div class="media-card-art-fallback" style="display:none; background: ${gradient};">
               ${iconSvg}
               <span class="station-art-fallback-title">${escapeHtml(st.name || 'Радио')}</span>
             </div>`
          : `<div class="media-card-art-fallback" style="background: ${gradient};">
               ${iconSvg}
               <span class="station-art-fallback-title">${escapeHtml(st.name || 'Радио')}</span>
             </div>`);

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
        optimisticPlay();
        markWaitingForPlayback({ isStation: true, targetName: st.name });
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

  // --- Section Tiles Grid Drill-down (Recent, Mixes, Albums, Stations) ---
  if (dom.homeRecentLink) {
    dom.homeRecentLink.addEventListener('click', () => {
      openSectionTilesGrid('recent', 'Недавно прослушано');
    });
  }

  if (dom.homeMixesLink) {
    dom.homeMixesLink.addEventListener('click', () => {
      openSectionTilesGrid('mixes', 'Еженедельные миксы');
    });
  }

  if (dom.homeAlbumsLink) {
    dom.homeAlbumsLink.addEventListener('click', () => {
      openSectionTilesGrid('albums', 'Новинки и альбомы');
    });
  }

  if (dom.homeStationsLink) {
    dom.homeStationsLink.addEventListener('click', () => {
      openSectionTilesGrid('stations', 'Станции для вас');
    });
  }

  if (dom.btnBackFromGrid) {
    dom.btnBackFromGrid.addEventListener('click', () => {
      closeSectionTilesGrid();
    });
  }

  function openSectionTilesGrid(sectionKey, title) {
    if (dom.viewHome) dom.viewHome.classList.remove('active');
    if (dom.recentDetailPane) {
      dom.recentDetailPane.classList.remove('active');
      dom.recentDetailPane.classList.add('hidden');
    }
    if (dom.sectionGridView) {
      dom.sectionGridView.classList.remove('hidden');
      dom.sectionGridView.classList.add('active');
    }
    if (dom.gridViewTitle) {
      dom.gridViewTitle.textContent = title;
    }
    renderSectionTiles(sectionKey);
  }

  function closeSectionTilesGrid() {
    if (dom.sectionGridView) {
      dom.sectionGridView.classList.remove('active');
      dom.sectionGridView.classList.add('hidden');
    }
    if (dom.viewHome) {
      dom.viewHome.classList.add('active');
    }
  }

  function renderSectionTiles(key) {
    if (!dom.sectionTilesGrid) return;
    dom.sectionTilesGrid.innerHTML = '';

    let items = [];
    if (key === 'recent') {
      items = state.recentlyPlayed || [];
    } else if (key === 'mixes') {
      items = (state.trends?.personal_mixes && state.trends.personal_mixes.length > 0)
        ? state.trends.personal_mixes
        : [];
    } else if (key === 'albums') {
      const nr = (state.trends?.new_releases && state.trends.new_releases.length > 0) ? state.trends.new_releases : [];
      const ta = (state.trends?.top_albums && state.trends.top_albums.length > 0) ? state.trends.top_albums : (state.trends?.topAlbums || []);
      items = nr.length > 0 ? [...nr, ...ta.filter(a => !nr.some(x => `${x.id}` === `${a.id}`))] : ta;
    } else if (key === 'stations') {
      items = (state.trends?.stations && state.trends.stations.length > 0)
        ? state.trends.stations
        : DEFAULT_STATIONS;
    }

    if (!items || items.length === 0) {
      dom.sectionTilesGrid.innerHTML = '<div class="empty-state">Нет элементов для отображения</div>';
      return;
    }

    items.forEach(item => {
      const tile = document.createElement('div');
      tile.className = 'collection-tile' + (key === 'stations' ? ' is-station' : '');

      const isLive = Boolean(item.isLive || item.is_live);
      const gradient = item.color || 'linear-gradient(135deg, #1c1c1e, #2c2c2e)';
      const artUrl = item.artwork || item.artworkUrl || item.artwork_url || '';
      const hasImage = Boolean(artUrl && artUrl.trim().length > 0 && !artUrl.includes('apple-touch-icon'));
      const itemName = item.name || item.title || 'Apple Music';
      const itemSub = item.subtitle || item.sub || item.artist || item.curatorName || (key === 'stations' ? 'Радиостанция' : '');
      const animatedPlaque = getAnimatedPlaqueHtml({ ...item, title: itemName, subtitle: itemSub, type: key === 'stations' ? 'station' : item.type });

      const artHtml = animatedPlaque
        ? animatedPlaque
        : (hasImage
          ? `<img class="collection-tile-art" src="${artUrl}" alt="" loading="lazy" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
             <div class="collection-tile-fallback station-animated-bg" style="display:none; background: ${gradient};">
               <svg viewBox="0 0 24 24" width="36" height="36" fill="currentColor"><circle cx="12" cy="12" r="3.2"/><path d="M12 6c-2.76 0-5 2.24-5 5 0 1.63.79 3.08 2 3.99V22l3-2 3 2v-7.01c1.21-.91 2-2.36 2-3.99 0-2.76-2.24-5-5-5z"/></svg>
               <span class="collection-tile-fallback-title">${escapeHtml(itemName)}</span>
             </div>`
          : `<div class="collection-tile-fallback station-animated-bg" style="background: ${gradient};">
               <svg viewBox="0 0 24 24" width="36" height="36" fill="currentColor"><circle cx="12" cy="12" r="3.2"/><path d="M12 6c-2.76 0-5 2.24-5 5 0 1.63.79 3.08 2 3.99V22l3-2 3 2v-7.01c1.21-.91 2-2.36 2-3.99 0-2.76-2.24-5-5-5z"/></svg>
               <span class="collection-tile-fallback-title">${escapeHtml(itemName)}</span>
             </div>`);

      // music Emblem
      const appleMusicBadge = `
        <div class="apple-music-badge">
          <svg viewBox="0 0 170 170"><path d="M150.37 130.25c-2.45 5.66-5.35 10.87-8.71 15.66-4.58 6.53-8.33 11.05-11.22 13.56-4.48 4.12-9.28 6.23-14.42 6.35-3.69 0-8.14-1.05-13.32-3.18-5.19-2.12-9.97-3.17-14.34-3.17-4.58 0-9.49 1.05-14.75 3.17-5.26 2.13-9.5 3.24-12.74 3.35-4.35.13-9.16-1.9-14.42-6.08-3.7-3.04-7.58-7.7-11.63-13.98-5.77-8.91-10.28-18.77-13.55-29.58-3.27-10.81-4.9-21.2-4.9-31.17 0-14.7 3.52-26.69 10.57-35.98 7.05-9.29 16.03-14.07 26.94-14.34 5.33 0 11.22 1.5 17.67 4.5 6.45 3.01 10.57 4.59 12.37 4.74 2.18-.32 6.64-1.99 13.39-5.01 6.75-3.02 12.63-4.33 17.65-3.94 13.17 1.07 23.36 6.09 30.56 15.07-11.75 7.12-17.51 16.97-17.29 29.54.21 9.99 4.14 18.3 11.78 24.93 7.64 6.63 16.59 10.45 26.85 11.46-2.07 6.1-4.47 12.06-7.21 17.89zM119.22 31.85c0-7.39 2.68-14.53 8.04-21.43 5.36-6.9 12.04-10.42 20.03-10.42.22 1.1.33 2.11.33 3.04 0 7.4-2.73 14.44-8.2 21.11-5.46 6.68-12.23 10.29-20.2 10.84v-3.14z"/></svg>
          <span>music</span>
        </div>
      `;

      tile.innerHTML = `
        <div class="collection-tile-art-wrap">
          ${artHtml}
          ${appleMusicBadge}
          <div class="media-play-overlay">
            <div class="media-play-pill">
              <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
                <polygon points="7 4 19 12 7 20 7 4"/>
              </svg>
            </div>
          </div>
        </div>
        <div class="collection-tile-info">
          <span class="collection-tile-title">${escapeHtml(itemName)}</span>
          <span class="collection-tile-sub">${escapeHtml(itemSub)}</span>
        </div>
      `;

      tile.addEventListener('click', () => {
        if (key === 'mixes') {
          openPlaylistDetail({
            id: item.id || '',
            name: itemName,
            url: item.url || '',
            artwork_url: artUrl,
            track_count: item.track_count || item.trackCount || 25,
            curator_name: itemSub
          }, 'home-grid');
          return;
        }
        if (key === 'albums') {
          openAlbumDetail({
            id: `${item.id || ''}`,
            name: itemName,
            artist: itemSub,
            artwork: artUrl,
            url: item.url || ''
          }, 'home-grid');
          return;
        }

        state.pendingPlayUntil = Date.now() + 3000;
        state.playerState = 'playing';
        state.playbackState = 'playing';
        renderNowPlaying();

        if (key === 'stations') {
          markWaitingForPlayback({ isStation: true, targetName: item.name });
          setUIBusy(true, 'Подключение к станции...');
          send({
            action: 'play_station',
            params: {
              url: item.url || '',
              name: item.name || 'Apple Music Radio'
            }
          });
        } else if (key === 'recent') {
          markWaitingForPlayback({ targetName: item.name });
          setUIBusy(true, 'Запуск трека...');
          send({
            action: 'play_cloud',
            params: {
              id: `${item.id || ''}`,
              numeric_id: parseInt(item.id, 10) || 0,
              name: item.name || '',
              artist: item.artist || '',
              url: item.url || '',
              artwork: artUrl
            }
          });
        }
      });

      dom.sectionTilesGrid.appendChild(tile);
    });
  }

  // Fallback detail handlers for Recently Played list view
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
      const art = getArtworkSrc(t);
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

      card.addEventListener('click', () => {
        openAlbumDetail({
          id: `${alb.id || ''}`,
          name: alb.name || '',
          artist: alb.artist || '',
          artwork: art,
          url: alb.url || ''
        }, 'home');
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

    if (isDesktopLayout()) {
      switchDesktopTab('search');
    } else {
      switchMobileView('view-search');
    }

    executeSearch(cleanQ, state.searchScope);
  }

  // --- Navigation & View Switching ---

  // Mobile Bottom Tab Bar
  dom.tabItems.forEach(tab => {
    tab.addEventListener('click', () => {
      triggerHaptic('light');
      const targetViewId = tab.dataset.view;
      switchMobileView(targetViewId);
    });
  });

  function switchMobileView(viewId, skipFetch = false) {
    if (viewId !== 'view-now-playing') {
      state.lastNonPlayerView = viewId;
    }
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
    if (dom.sectionGridView) {
      dom.sectionGridView.classList.remove('active');
      dom.sectionGridView.classList.add('hidden');
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
      if (!skipFetch) {
        if (dom.playlistsBrowsePane) dom.playlistsBrowsePane.classList.remove('hidden');
        if (dom.playlistDetailPane) dom.playlistDetailPane.classList.add('hidden');
        send({ action: 'get_playlists' });
      }
    } else if (viewId === 'view-queue') {
      if (!skipFetch) send({ action: 'get_queue' });
    } else if (viewId === 'view-home' || viewId === 'view-trends') {
      if (!skipFetch) loadTrends();
    }
  }

  function minimizeNowPlaying() {
    triggerHaptic('light');
    switchMobileView(state.lastNonPlayerView || 'view-home');
  }

  function expandNowPlaying() {
    triggerHaptic('light');
    switchMobileView('view-now-playing');
  }

  // Tapping Mini-Player body expands Now Playing
  dom.miniTrigger.addEventListener('click', (e) => {
    if (e.target.closest('button')) return;
    expandNowPlaying();
  });

  // Synthetic click suppression after touch swipes
  let ignoreSyntheticClickUntil = 0;
  document.addEventListener('click', (e) => {
    if (Date.now() < ignoreSyntheticClickUntil) {
      e.preventDefault();
      e.stopPropagation();
      e.stopImmediatePropagation();
    }
  }, true);

  // --- Artwork & Mini-Player Swipe Gestures ---
  function setupArtworkSwipeGestures() {
    const container = dom.artworkContainer;
    const wrapper = dom.artworkWrapper;
    if (!container || !wrapper) return;

    let startX = 0;
    let startY = 0;
    let deltaX = 0;
    let deltaY = 0;
    let startTime = 0;
    let isSwiping = false;

    container.addEventListener('touchstart', (e) => {
      if (e.touches.length !== 1) return;
      const t = e.touches[0];
      startX = t.clientX;
      startY = t.clientY;
      deltaX = 0;
      deltaY = 0;
      startTime = Date.now();
      isSwiping = true;
      wrapper.style.transition = 'none';
    }, { passive: true });

    container.addEventListener('touchmove', (e) => {
      if (!isSwiping || e.touches.length !== 1) return;
      const t = e.touches[0];
      deltaX = t.clientX - startX;
      deltaY = t.clientY - startY;

      if (Math.abs(deltaX) > Math.abs(deltaY)) {
        // Horizontal swipe preview with resistance
        const dampened = deltaX * 0.42;
        const scale = Math.max(0.92, 1 - Math.abs(deltaX) / 1000);
        wrapper.style.transform = `translateX(${dampened}px) scale(${scale})`;
      } else if (deltaY > 0) {
        // Pull down preview to minimize
        const dampenedY = deltaY * 0.35;
        const scale = Math.max(0.92, 1 - deltaY / 1200);
        wrapper.style.transform = `translateY(${dampenedY}px) scale(${scale})`;
      }
    }, { passive: true });

    const handleTouchEnd = () => {
      if (!isSwiping) return;
      isSwiping = false;
      const elapsed = Date.now() - startTime;
      wrapper.style.transition = 'transform 0.28s cubic-bezier(0.2, 0.9, 0.4, 1)';

      const isFastSwipe = elapsed < 320;
      const horizontalThreshold = isFastSwipe ? 50 : 80;
      const verticalThreshold = isFastSwipe ? 55 : 85;

      if (Math.abs(deltaX) > Math.abs(deltaY) && Math.abs(deltaX) > horizontalThreshold) {
        ignoreSyntheticClickUntil = Date.now() + 450;
        if (deltaX < 0) {
          // Swipe Left -> Next Track
          triggerHaptic('medium');
          wrapper.style.transform = 'translateX(-120%) scale(0.9)';
          setTimeout(() => {
            sendThrottledTransport('next');
            wrapper.style.transition = 'none';
            wrapper.style.transform = 'translateX(60%) scale(0.92)';
            requestAnimationFrame(() => {
              wrapper.style.transition = 'transform 0.28s cubic-bezier(0.2, 0.9, 0.4, 1)';
              wrapper.style.transform = 'none';
            });
          }, 160);
          return;
        } else {
          // Swipe Right -> Previous Track
          triggerHaptic('medium');
          wrapper.style.transform = 'translateX(120%) scale(0.9)';
          setTimeout(() => {
            sendThrottledTransport('previous');
            wrapper.style.transition = 'none';
            wrapper.style.transform = 'translateX(-60%) scale(0.92)';
            requestAnimationFrame(() => {
              wrapper.style.transition = 'transform 0.28s cubic-bezier(0.2, 0.9, 0.4, 1)';
              wrapper.style.transform = 'none';
            });
          }, 160);
          return;
        }
      } else if (deltaY > verticalThreshold && Math.abs(deltaX) < deltaY * 0.8) {
        // Swipe Down -> Minimize Now Playing
        triggerHaptic('light');
        wrapper.style.transform = 'translateY(120px) scale(0.85)';
        setTimeout(() => {
          wrapper.style.transform = 'none';
          minimizeNowPlaying();
        }, 140);
        return;
      }

      // Reset if not meeting threshold
      wrapper.style.transform = 'none';
    };

    container.addEventListener('touchend', handleTouchEnd);
    container.addEventListener('touchcancel', handleTouchEnd);
  }

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

  function switchDesktopTab(tabName, skipFetch = false) {
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
    if (dom.sectionGridView) {
      dom.sectionGridView.classList.remove('active');
      dom.sectionGridView.classList.add('hidden');
    }
    dom.viewSearch.classList.remove('active');

    if (tabName === 'home' || tabName === 'trends') {
      if (dom.viewHome) dom.viewHome.classList.add('active');
      else if (dom.viewTrends) dom.viewTrends.classList.add('active');
      if (!skipFetch) loadTrends();
    } else if (tabName === 'queue') {
      dom.viewQueue.classList.add('active');
      if (!skipFetch) send({ action: 'get_queue' });
    } else if (tabName === 'library') {
      dom.viewLibrary.classList.add('active');
      if (!skipFetch) {
        if (dom.playlistsBrowsePane) dom.playlistsBrowsePane.classList.remove('hidden');
        if (dom.playlistDetailPane) dom.playlistDetailPane.classList.add('hidden');
        send({ action: 'get_playlists' });
      }
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
    if (isMobilePhoneViewport() && screen.orientation && typeof screen.orientation.lock === 'function') {
      screen.orientation.lock('portrait').catch(() => {});
    }
    const detailOpen = Boolean(dom.playlistDetailPane && !dom.playlistDetailPane.classList.contains('hidden'));
    if (isDesktopLayout()) {
      // On desktop, ensure right column displays active desktop tab
      switchDesktopTab(state.desktopActiveTab, detailOpen);
    } else {
      // On mobile, ensure active mobile view is respected
      switchMobileView(state.activeView, detailOpen);
    }
  }
  window.addEventListener('resize', handleResize);

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

  function hideMotionVideos() {
    const pVid = document.getElementById('player-motion-video');
    const sbVid = document.getElementById('standby-motion-video');
    const sbBadge = document.getElementById('standby-motion-badge');
    if (pVid) {
      pVid.classList.remove('visible');
      pVid.classList.add('hidden');
      pVid.removeAttribute('src');
    }
    if (sbVid) {
      sbVid.classList.remove('visible');
      sbVid.classList.add('hidden');
      sbVid.removeAttribute('src');
    }
    if (sbBadge) sbBadge.classList.add('hidden');
    currentMotionVideoUrl = '';
  }

  function applyMotionVideoUrl(url) {
    if (!url) {
      hideMotionVideos();
      return;
    }
    if (currentMotionVideoUrl === url) return;
    currentMotionVideoUrl = url;

    const pVid = document.getElementById('player-motion-video');
    const sbVid = document.getElementById('standby-motion-video');
    const sbBadge = document.getElementById('standby-motion-badge');

    [pVid, sbVid].forEach((vid) => {
      if (!vid) return;
      vid.classList.remove('hidden');
      vid.src = url;
      vid.muted = true;
      vid.loop = true;
      vid.playsInline = true;
      vid.onloadeddata = () => {
        vid.classList.add('visible');
        vid.play().catch(() => {});
      };
      vid.onerror = () => {
        vid.classList.remove('visible');
        vid.classList.add('hidden');
      };
    });
    if (sbBadge) sbBadge.classList.remove('hidden');
  }

  function applyMotionArtwork(data) {
    if (!data) return;
    const url = (data.motion_url || '').trim();
    const respTrack = data.track || '';
    const respArtist = data.artist || '';
    const respAlbum = data.album || '';

    const albKey = buildMotionAlbumKey(respArtist, respAlbum);
    const trkKey = buildMotionTrackKey(respTrack, respArtist, respAlbum);
    if (albKey) motionArtworkClientCache.set(albKey, url);
    if (trkKey) motionArtworkClientCache.set(trkKey, url);

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

    if (t && t.name) {
      if (sbTitle) sbTitle.textContent = t.name || 'Без названия';
      if (sbArtist) sbArtist.textContent = t.artist || 'Apple Music';
      if (sbAlbum) sbAlbum.textContent = t.album || '';
      const art = getArtworkSrc(t);
      if (sbArt && sbArt.dataset.targetSrc !== art) {
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
      if (sbTitle) sbTitle.textContent = 'Не играет';
      if (sbArtist) sbArtist.textContent = 'Apple Music';
      if (sbAlbum) sbAlbum.textContent = '';
      if (sbArt) {
        sbArt.dataset.targetSrc = 'apple-touch-icon.svg';
        sbArt.src = 'apple-touch-icon.svg';
      }
      if (lastMotionQueryKey !== '') {
        lastMotionQueryKey = '';
        hideMotionVideos();
      }
    }

    if (sbDac) {
      const devPart = state.audioDeviceName ? ` · ${state.audioDeviceName}` : '';
      sbDac.textContent = `${formatDacPill(state.audioQuality)}${devPart}`;
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
  }

  let lastStandbyTilesSignature = '';

  function openStandbyLibraryModal() {
    const modal = document.getElementById('standby-library-modal');
    if (!modal) return;
    renderStandbyQuickTiles();
    if (!state.playlists || state.playlists.length === 0) {
      send({ action: 'get_playlists' });
    }
    modal.classList.remove('hidden');
    modal.setAttribute('aria-hidden', 'false');
    const p = document.getElementById('top-settings-popover');
    if (p) p.classList.add('hidden');
  }

  function closeStandbyLibraryModal() {
    const modal = document.getElementById('standby-library-modal');
    if (!modal) return;
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

  function renderStandbyQuickTiles() {
    const grid = document.getElementById('standby-library-grid');
    if (!grid) return;

    const rawPlaylists = (state.playlists || []).filter(pl => {
      const n = (pl.name || '').trim();
      if (!n) return false;
      if (n.includes('Очередь AMR') || n.startsWith('AMR ')) return false;
      return true;
    });

    const sig = rawPlaylists.map(p => `${p.name}:${p.artwork_url || p.artworkUrl || ''}:${p.track_count || p.trackCount || 0}`).join('|') +
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
        title: 'Моя станция',
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
              id: 'ra.u-96b95a031a2fb0aa1abb70ff757aa95f',
              url: 'https://music.apple.com/station/my-station/ra.u-96b95a031a2fb0aa1abb70ff757aa95f',
              type: 'station'
            }
          });
        }
      },
      {
        key: 'discovery-station',
        title: 'Станция открытий',
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
              id: 'ra.q-GAI6IDk2Yjk1YTAzMWEyZmIwYWExYWJiNzBmZjc1N2FhOTVm',
              url: 'https://music.apple.com/station/item/ra.q-GAI6IDk2Yjk1YTAzMWEyZmIwYWExYWJiNzBmZjc1N2FhOTVm',
              type: 'station'
            }
          });
        }
      },
      {
        key: 'favorites-mix',
        title: 'В моём вкусе',
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
        title: 'Сейчас на повторе',
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
              id: hrMix ? (hrMix.id || 'pl.pm-20e9f373919da080ba0f21cc6adb1672') : 'pl.pm-20e9f373919da080ba0f21cc6adb1672',
              url: hrMix ? (hrMix.url || '') : '',
              shuffle: false
            }
          });
        }
      }
    ];

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
    rawPlaylists.forEach(pl => {
      const plName = (pl.name || '').trim();
      const lower = plName.toLowerCase();
      if (lower === 'в моём вкусе' || lower === 'в моем вкусе' || lower === 'сейчас на повторе') return;

      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'standby-square-tile';
      const tileKey = `pl:${plName}`;
      btn.setAttribute('data-tile-key', tileKey);
      btn.setAttribute('data-tile-name', plName);
      btn.setAttribute('title', plName);

      const count = pl.track_count || pl.trackCount || 0;
      const countText = count > 0 ? `<span class="standby-tile-meta">${count} треков</span>` : '';
      const artUrl = pl.artwork_url || pl.artworkUrl || `/api/artwork/playlist?name=${encodeURIComponent(plName)}`;
      btn.innerHTML = `
        <img class="standby-tile-cover" src="${artUrl}" alt="${escapeHtml(plName)}" loading="lazy" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
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

    updateStandbyActiveTile();
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
      popover.classList.add('hidden');
    }
  }

  function pushWledSettingsToServer() {
    const modeSel = document.getElementById('wled-mode-select');
    const mode = modeSel ? modeSel.value : 'ambilight';

    send({
      action: 'set_wled_settings',
      params: {
        mode
      }
    });
  }

  function openStandbyMode() {
    if (isMobilePhoneViewport() || window.innerWidth < 768) return;
    const overlay = document.getElementById('standby-tv-overlay');
    if (!overlay) return;
    overlay.classList.remove('hidden');
    overlay.setAttribute('aria-hidden', 'false');
    try {
      localStorage.setItem('amr_tv_mode_active', '1');
      localStorage.removeItem('amr_default_tv_mode');
    } catch (_) {}
    renderStandbyQuickTiles();
    if (!state.playlists || state.playlists.length === 0) {
      send({ action: 'get_playlists' });
    }
    syncStandbyAndMotionCoverUI();
    updateStandbyClock();
    const p = document.getElementById('top-settings-popover');
    if (p) p.classList.add('hidden');
  }

  function closeStandbyMode() {
    closeStandbyLibraryModal();
    const overlay = document.getElementById('standby-tv-overlay');
    if (!overlay) return;
    overlay.classList.add('hidden');
    overlay.setAttribute('aria-hidden', 'true');
    try {
      localStorage.setItem('amr_tv_mode_active', '0');
      localStorage.removeItem('amr_default_tv_mode');
    } catch (_) {}
    const p = document.getElementById('top-settings-popover');
    if (p) p.classList.add('hidden');
  }

  function updateStandbyClock() {
    const el = document.getElementById('standby-clock');
    if (!el) return;
    const now = new Date();
    const hh = String(now.getHours()).padStart(2, '0');
    const mm = String(now.getMinutes()).padStart(2, '0');
    el.textContent = `${hh}:${mm}`;
  }

  function positionSettingsPopoverNearButton(popover, btn) {
    if (!popover || !btn) return;
    const rect = btn.getBoundingClientRect();
    if (!rect || (rect.width === 0 && rect.height === 0)) return;
    const topPos = Math.max(12, Math.min(window.innerHeight - 160, rect.bottom + 8));
    const rightPos = Math.max(12, window.innerWidth - rect.right);
    popover.style.top = `${topPos}px`;
    popover.style.right = `${rightPos}px`;
    popover.style.left = 'auto';
  }

  function setupStandbyAndWledControls() {
    updateStandbyClock();
    setInterval(updateStandbyClock, 15000);

    try {
      if (localStorage.getItem('amr_tv_mode_active') === '1') {
        openStandbyMode();
      }
    } catch (_) {}

    const popover = document.getElementById('top-settings-popover');
    let lastSettingsTriggerBtn = null;
    const togglePopover = (e) => {
      if (e) e.stopPropagation();
      if (!popover) return;
      const triggerBtn = e && e.currentTarget ? e.currentTarget : null;
      const isHidden = popover.classList.contains('hidden');
      if (isHidden || (triggerBtn && lastSettingsTriggerBtn !== triggerBtn)) {
        lastSettingsTriggerBtn = triggerBtn;
        send({ action: 'get_wled_settings' });
        popover.classList.remove('hidden');
        if (triggerBtn) {
          positionSettingsPopoverNearButton(popover, triggerBtn);
        }
      } else {
        popover.classList.add('hidden');
      }
    };

    ['btn-top-settings', 'mobile-btn-settings', 'player-btn-settings', 'standby-btn-wled-toggle'].forEach(id => {
      const btn = document.getElementById(id);
      if (btn) btn.addEventListener('click', togglePopover);
    });

    const btnClosePopover = document.getElementById('btn-close-top-settings');
    if (btnClosePopover) {
      btnClosePopover.addEventListener('click', () => {
        if (popover) popover.classList.add('hidden');
      });
    }

    document.addEventListener('click', (e) => {
      if (!popover || popover.classList.contains('hidden')) return;
      const insidePopover = popover.contains(e.target);
      const isTrigger = Boolean(e.target.closest('#btn-top-settings, #mobile-btn-settings, #player-btn-settings, #standby-btn-wled-toggle'));
      if (!insidePopover && !isTrigger) {
        popover.classList.add('hidden');
      }
    });

    const modeSel = document.getElementById('wled-mode-select');
    if (modeSel) modeSel.addEventListener('change', pushWledSettingsToServer);

    ['btn-standby-mode'].forEach(id => {
      const btn = document.getElementById(id);
      if (btn) btn.addEventListener('click', openStandbyMode);
    });

    const btnCloseStandby = document.getElementById('btn-close-standby');
    if (btnCloseStandby) btnCloseStandby.addEventListener('click', closeStandbyMode);

    const btnStandbyLib = document.getElementById('standby-btn-library');
    if (btnStandbyLib) btnStandbyLib.addEventListener('click', openStandbyLibraryModal);

    const btnCloseStandbyLib = document.getElementById('btn-close-standby-library');
    if (btnCloseStandbyLib) btnCloseStandbyLib.addEventListener('click', closeStandbyLibraryModal);

    const sbPlayPause = document.getElementById('standby-btn-play-pause');
    const sbPrev = document.getElementById('standby-btn-prev');
    const sbNext = document.getElementById('standby-btn-next');
    const sbTrack = document.getElementById('standby-progress-track');

    if (sbPlayPause) sbPlayPause.addEventListener('click', togglePlayPause);
    if (sbPrev) sbPrev.addEventListener('click', () => sendThrottledTransport('previous'));
    if (sbNext) sbNext.addEventListener('click', () => sendThrottledTransport('next'));
    if (sbTrack) {
      sbTrack.addEventListener('click', (e) => {
        if (!state.duration || state.duration <= 0) return;
        const rect = sbTrack.getBoundingClientRect();
        const ratio = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
        sendSeek(ratio * state.duration);
      });
    }

    renderStandbyQuickTiles();

    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        if (popover && !popover.classList.contains('hidden')) {
          popover.classList.add('hidden');
          return;
        }
        const libModal = document.getElementById('standby-library-modal');
        if (libModal && !libModal.classList.contains('hidden')) {
          closeStandbyLibraryModal();
          return;
        }
        const overlay = document.getElementById('standby-tv-overlay');
        if (overlay && !overlay.classList.contains('hidden')) {
          closeStandbyMode();
        }
      }
    });
  }

  // Initialize
  setupMediaSession();
  setupArtworkSwipeGestures();
  setupMiniPlayerGestures();
  setupStandbyAndWledControls();
  renderHeroCarousel({});
  renderHomeStations(DEFAULT_STATIONS);
  renderHomeGenres(DEFAULT_GENRES);
  handleResize();
  connectWebSocket();

})();

function bindGenreCards() {
  document.querySelectorAll('.genre-card').forEach(card => {
    card.addEventListener('click', () => {
      const genre = card.getAttribute('data-genre');
      if (genre) {
        dom.searchInput.value = genre;
        state.searchQuery = genre;
        dom.btnClearSearch.classList.remove('hidden');
        executeSearch(genre, state.searchScope);
      }
    });
  });
}
bindGenreCards();
"""#
}
