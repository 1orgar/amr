  function recoverOrPersistDeviceUidBeforeConnect() {
    const hasCacheStorage = typeof window !== 'undefined' && 'caches' in window && Boolean(window.caches) && typeof window.caches.open === 'function';
    const needUidRecovery = Boolean(state.deviceIdWasFreshlyGenerated);
    const needSecretRecovery = !state.deviceSecret;
    if (!needUidRecovery && !needSecretRecovery) {
      persistUidToSecureStore(state.deviceId);
      persistDeviceSecret(state.deviceSecret);
      return Promise.resolve();
    }
    if (!hasCacheStorage) {
      state.deviceIdWasFreshlyGenerated = false;
      persistUidToSecureStore(state.deviceId);
      if (state.deviceSecret) persistDeviceSecret(state.deviceSecret);
      return Promise.resolve();
    }
    const freshlyGeneratedUid = state.deviceId;
    const cacheLookupPromise = Promise.resolve()
      .then(() => window.caches.open('amr-device-secure-store-v1'))
      .then(async (cache) => {
        if (!cache || typeof cache.match !== 'function') return { rawUid: null, rawSecret: null };
        const [uidResp, secResp] = await Promise.all([
          needUidRecovery ? cache.match('/__amr_device_uid').catch(() => null) : Promise.resolve(null),
          needSecretRecovery ? cache.match('/__amr_device_secret').catch(() => null) : Promise.resolve(null)
        ]);
        const rawUid = uidResp && typeof uidResp.text === 'function' ? await uidResp.text().catch(() => null) : null;
        const rawSecret = secResp && typeof secResp.text === 'function' ? await secResp.text().catch(() => null) : null;
        return { rawUid, rawSecret };
      })
      .catch(() => ({ rawUid: null, rawSecret: null }));
    const timeoutPromise = new Promise((resolve) => {
      setTimeout(() => resolve({ rawUid: null, rawSecret: null }), 250);
    });
    return Promise.race([cacheLookupPromise, timeoutPromise])
      .then(({ rawUid, rawSecret }) => {
        if (needUidRecovery) {
          let candidate = String(rawUid || '').trim();
          if (candidate.startsWith('{')) {
            try {
              const parsed = JSON.parse(candidate);
              if (parsed && parsed.uid) candidate = String(parsed.uid).trim();
            } catch (_) {}
          }
          const cachedUid = candidate.toLowerCase();
          if (cachedUid && /^[A-Za-z0-9._-]{8,128}$/.test(cachedUid)) {
            state.deviceId = cachedUid;
            state.deviceShortId = computeShortDeviceId(cachedUid);
            state.supersededFreshDeviceId = freshlyGeneratedUid;
          }
          state.deviceIdWasFreshlyGenerated = false;
        }
        if (needSecretRecovery) {
          const cachedSecret = String(rawSecret || '').trim();
          if (cachedSecret && /^[A-Za-z0-9._-]{16,256}$/.test(cachedSecret)) {
            state.deviceSecret = cachedSecret;
          }
        }
        persistUidToSecureStore(state.deviceId);
        if (state.deviceSecret) {
          persistDeviceSecret(state.deviceSecret);
        }
        if (typeof syncDeviceInfoUI === 'function') {
          syncDeviceInfoUI();
        }
      })
      .catch(() => {
        state.deviceIdWasFreshlyGenerated = false;
        persistUidToSecureStore(state.deviceId);
        if (state.deviceSecret) persistDeviceSecret(state.deviceSecret);
      });
  }

  // --- DOM Elements Cache ---
  const dom = {
    overlay: document.getElementById('connection-overlay'),
    connectionStatusText: document.getElementById('connection-status-text'),
    btnReconnect: document.getElementById('btn-reconnect'),

    // Views
    viewNowPlaying: document.getElementById('view-now-playing'),
    viewQueue: document.getElementById('view-queue'),
    viewPlaylists: document.getElementById('view-playlists'),
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
    miniProgressTrack: document.getElementById('mini-progress-track') || document.querySelector('.mini-progress-track'),
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
    btnGoToAlbum: document.getElementById('btn-go-to-album'),
    btnAiTrackVibe: document.getElementById('btn-ai-track-vibe'),
    btnCreateStation: document.getElementById('btn-create-station'),
    btnFavorite: document.getElementById('btn-favorite'),
    audioQualityBadge: document.getElementById('audio-quality-badge'),
    audioQualityText: document.getElementById('audio-quality-text'),
    desktopDacBadge: document.getElementById('desktop-dac-badge'),
    desktopDacText: document.getElementById('desktop-dac-text'),
    mobileDacBadge: document.getElementById('mobile-dac-badge'),
    mobileDacText: document.getElementById('mobile-dac-text'),

    // Station Picker / Track Actions Modal (•••)
    stationPickerModal: document.getElementById('station-picker-modal'),
    btnCloseStationModal: document.getElementById('btn-close-station-modal'),
    stationModalTrackBanner: document.getElementById('station-modal-track-banner'),
    stationModalTrackArt: document.getElementById('station-modal-track-art'),
    stationModalTrackTitle: document.getElementById('station-modal-track-title'),
    stationModalTrackSub: document.getElementById('station-modal-track-sub'),
    btnAddTrackLibrary: document.getElementById('btn-add-track-library'),
    btnRemoveTrackLibrary: document.getElementById('btn-remove-track-library'),
    btnGoToLibraryArtist: document.getElementById('btn-go-to-library-artist'),
    stationOptLibArtistName: document.getElementById('station-opt-lib-artist-name'),
    btnRemoveArtistLibrary: document.getElementById('btn-remove-artist-library'),
    stationOptRemoveArtistSub: document.getElementById('station-opt-remove-artist-sub'),
    btnAiMixByTrack: document.getElementById('btn-ai-mix-by-track'),
    stationOptAiVibeSub: document.getElementById('station-opt-ai-vibe-sub'),
    btnSonicBridgeByTrack: document.getElementById('btn-sonic-bridge-by-track'),
    stationOptSonicBridgeSub: document.getElementById('station-opt-sonic-bridge-sub'),
    btnStationByTrack: document.getElementById('btn-station-by-track'),
    btnStationByArtist: document.getElementById('btn-station-by-artist'),
    stationOptAlbumName: document.getElementById('station-opt-album-name'),
    stationOptTrackName: document.getElementById('station-opt-track-name'),
    stationOptArtistName: document.getElementById('station-opt-artist-name'),
    moreBookletDot: document.getElementById('more-booklet-dot'),

    // Scrubber
    scrubberContainer: document.getElementById('scrubber-container'),
    scrubberFill: document.getElementById('scrubber-fill'),
    scrubberThumb: document.getElementById('scrubber-thumb'),
    scrubberInput: document.getElementById('scrubber-input'),
    timeElapsed: document.getElementById('time-elapsed'),
    timeRemaining: document.getElementById('time-remaining'),
    playerLoadingStatus: document.getElementById('player-loading-status'),
    playerLoadingText: document.getElementById('player-loading-text'),
    standbyProgressTrack: document.getElementById('standby-progress-track'),
    standbyLoadingStatus: document.getElementById('standby-loading-status'),
    standbyLoadingText: document.getElementById('standby-loading-text'),
    standbyBtnPlayPause: document.getElementById('standby-btn-play-pause'),

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
    queueHistoryGroup: document.getElementById('queue-history-group'),
    queueHistoryList: document.getElementById('queue-history-list'),
    btnToggleQueueHistory: document.getElementById('btn-toggle-queue-history'),
    queueCurrentGroup: document.getElementById('queue-current-group'),
    queueCurrentTrack: document.getElementById('queue-current-track'),
    queueUpcomingList: document.getElementById('queue-upcoming-list'),
    btnSaveQueuePlaylist: document.getElementById('btn-save-queue-playlist'),
    btnSaveQueueText: document.getElementById('btn-save-queue-text'),
    btnClearQueue: document.getElementById('btn-clear-queue'),

    // Playlists & Library Elements
    playlistsSectionSubtitle: document.getElementById('playlists-section-subtitle'),
    btnRefreshPlaylists: document.getElementById('btn-refresh-playlists'),
    playlistsBrowsePane: document.getElementById('playlists-browse-pane'),
    playlistsGrid: document.getElementById('playlists-grid'),
    libraryRecentPane: document.getElementById('library-recent-pane'),
    libraryArtistsPane: document.getElementById('library-artists-pane'),
    libraryArtistsToolbar: document.getElementById('library-artists-toolbar'),
    libraryArtistsFilter: document.getElementById('library-artists-filter'),
    btnClearArtistsFilter: document.getElementById('btn-clear-artists-filter'),
    libraryArtistsList: document.getElementById('library-artists-list'),
    libraryAlbumsGrid: document.getElementById('library-albums-grid'),
    librarySongsPane: document.getElementById('library-songs-pane'),
    librarySongsToolbar: document.getElementById('library-songs-toolbar'),
    librarySongsFilter: document.getElementById('library-songs-filter'),
    btnClearSongsFilter: document.getElementById('btn-clear-songs-filter'),
    btnPlayLibrarySongs: document.getElementById('btn-play-library-songs'),
    btnShuffleLibrarySongs: document.getElementById('btn-shuffle-library-songs'),
    librarySongsList: document.getElementById('library-songs-list'),
    librarySectionSubtitle: document.getElementById('library-section-subtitle'),
    librarySegRecent: document.getElementById('library-seg-recent'),
    librarySegArtists: document.getElementById('library-seg-artists'),
    librarySegAlbums: document.getElementById('library-seg-albums'),
    librarySegSongs: document.getElementById('library-seg-songs'),
    btnRefreshLibrary: document.getElementById('btn-refresh-library'),
    btnRefreshLibraryDesktop: document.getElementById('btn-refresh-library-desktop'),
    libraryArtistDetailPane: document.getElementById('library-artist-detail-pane'),
    btnBackToArtists: document.getElementById('btn-back-to-artists'),
    artistDetailArtwork: document.getElementById('artist-detail-artwork'),
    artistDetailInitials: document.getElementById('artist-detail-initials'),
    artistDetailTitle: document.getElementById('artist-detail-title'),
    artistDetailMeta: document.getElementById('artist-detail-meta'),
    btnPlayArtistLibrary: document.getElementById('btn-play-artist-library'),
    btnShuffleArtistLibrary: document.getElementById('btn-shuffle-artist-library'),
    btnRemoveArtistDetailLibrary: document.getElementById('btn-remove-artist-detail-library'),
    artistDetailContent: document.getElementById('artist-detail-content'),
    playlistDetailPane: document.getElementById('playlist-detail-pane'),
    btnBackToPlaylists: document.getElementById('btn-back-to-playlists'),
    detailBackLabel: document.getElementById('detail-back-label'),
    detailArtwork: document.getElementById('detail-artwork'),
    detailTitle: document.getElementById('detail-title'),
    detailBadge: document.getElementById('detail-badge'),
    detailMeta: document.getElementById('detail-meta'),
    btnPlayPlaylist: document.getElementById('btn-play-playlist'),
    btnShufflePlaylist: document.getElementById('btn-shuffle-playlist'),
    btnAddPlaylistLibrary: document.getElementById('btn-add-playlist-library'),
    btnAddPlaylistLibraryText: document.getElementById('btn-add-playlist-library-text'),
    btnRemoveDetailLibrary: document.getElementById('btn-remove-detail-library'),
    btnRemoveDetailLibraryText: document.getElementById('btn-remove-detail-library-text'),
    playlistTracksList: document.getElementById('playlist-tracks-list'),
    albumCompletenessBannerSlot: document.getElementById('album-completeness-banner-slot'),
    confirmDeleteModal: document.getElementById('library-delete-confirm-modal'),
    confirmDeleteTitle: document.getElementById('confirm-delete-title'),
    confirmDeleteMessage: document.getElementById('confirm-delete-message'),
    btnConfirmDeleteCancel: document.getElementById('btn-confirm-delete-cancel'),
    btnConfirmDeleteOk: document.getElementById('btn-confirm-delete-ok'),

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
    // StandBy / TV Mode Inline Volume Bar
    standbyVolumeSection: document.getElementById('standby-volume-section'),
    standbyBtnVolumeMute: document.getElementById('standby-btn-volume-mute'),
    standbyVolFill: document.getElementById('standby-vol-fill'),
    standbyVolThumb: document.getElementById('standby-vol-thumb'),
    standbyVolLoupe: document.getElementById('standby-vol-loupe'),
    standbyVolLoupeText: document.getElementById('standby-vol-loupe-text'),
    standbyVolumeInput: document.getElementById('standby-volume-input'),
    standbyVolumeText: document.getElementById('standby-volume-text'),
    // Signal Path Modal
    qualityModal: document.getElementById('quality-modal'),
    btnCloseModal: document.getElementById('btn-close-modal'),
    signalSourceBadge: document.getElementById('signal-source-badge'),
    signalSourceTitle: document.getElementById('signal-source-title'),
    signalSourceDetails: document.getElementById('signal-source-details'),
    signalDacRate: document.getElementById('signal-dac-rate'),
    signalDacName: document.getElementById('signal-dac-name'),
    signalDacDetails: document.getElementById('signal-dac-details'),
    signalConnectorAmp: document.getElementById('signal-connector-amp'),
    signalNodeAmp: document.getElementById('signal-node-amp'),
    signalAmpDot: document.getElementById('signal-amp-dot'),
    signalAmpVolumeBadge: document.getElementById('signal-amp-volume-badge'),
    signalAmpName: document.getElementById('signal-amp-name'),
    signalAmpDetails: document.getElementById('signal-amp-details'),
    btnOpenDevices: document.getElementById('btn-open-devices'),
    // Audio Devices Modal
    devicesModal: document.getElementById('devices-modal'),
    btnCloseDevices: document.getElementById('btn-close-devices'),
    audioDevicesList: document.getElementById('audio-devices-list'),
    // Apple ID Auth Modal
    modalAppleAuth: document.getElementById('modal-apple-auth'),
    btnAuthModalLogin: document.getElementById('btn-auth-modal-login'),
    authModalStatus: document.getElementById('auth-modal-status'),
    topSettingsPopover: document.getElementById('top-settings-popover')
  };

  // --- Busy Overlay & Action Loading Controller ---
  let busyTimeout = null;
  let activeLoadingBtn = null;

  function markWaitingForPlayback(options = {}) {
    state.waitingForPlayback = true;
    state.waitingTrackSignature = (state.track && state.track.name) ? `${state.track.name}:${state.track.artist || ''}` : null;
    state.waitingExpectedTrackName = options.expectedTrackName ? String(options.expectedTrackName).trim().toLowerCase() : null;
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
        dom.busyMessage.textContent = translateTextToEn(message);
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
      const isLongOp = Boolean(
        state.isAiCurating ||
        message.includes('ИИ') ||
        message.includes('AI') ||
        message.includes('Синхронизация') ||
        message.includes('очереди') ||
        message.includes('Apple Music')
      );
      const safetyMs = isLongOp ? 25000 : 10000;
      busyTimeout = setTimeout(() => {
        if (!state.aiCurateTimeoutId) {
          state.isAiCurating = false;
          state.pendingStandbyAiAutoPlay = false;
        }
        state.waitingForPlayback = false;
        state.waitingTrackSignature = null;
        state.waitingExpectedTrackName = null;
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
      state.waitingExpectedTrackName = null;
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

  const recentGetRpcSentAt = new Map();
  const pendingPreOpenQueue = [];
  let disconnectAudioGraceTimer = null;

  function clearDisconnectAudioGraceTimer() {
    if (disconnectAudioGraceTimer) {
      clearTimeout(disconnectAudioGraceTimer);
      disconnectAudioGraceTimer = null;
    }
  }

  function pauseSilentAudioAfterDisconnectGrace() {
    if (document.hidden && state.playerState === 'playing' && isLockScreenAllowedNow()) {
      // Keep silent audio alive during transient background Wi-Fi/TCP reconnects so iOS does not
      // immediately suspend the locked WebProcess or tear down Prev/Next Lock Screen controls.
      if (!disconnectAudioGraceTimer) {
        disconnectAudioGraceTimer = setTimeout(() => {
          disconnectAudioGraceTimer = null;
          if (!state.connected) {
            syncSilentAudio(false);
          }
        }, 15000);
      }
      return;
    }
    clearDisconnectAudioGraceTimer();
    syncSilentAudio(false);
  }

  function flushPendingPreOpenQueue() {
    if (!socket || socket.readyState !== WebSocket.OPEN || !state.deviceAuthorized) return;
    while (pendingPreOpenQueue.length > 0) {
      const queuedMsg = pendingPreOpenQueue.shift();
      if (queuedMsg) send(queuedMsg);
    }
  }

  function connectWebSocket() {
    clearTimeout(reconnectTimer);

    if (socket) {
      try {
        socket.onopen = null;
        socket.onmessage = null;
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
      state.lastServerMessageAt = Date.now();
      state.pendingPingSentAt = 0;
      state.lastPlayerStateReceivedAt = 0;
      state.lastQueueReceivedAt = 0;
      state.lastAiSettingsReceivedAt = 0;
      state.initialAuthFetched = false;
      recentGetRpcSentAt.clear();
      trendsInFlightCountry = '';
      trendsInFlightSince = 0;
      reconnectAttempt = 0;
      clearDisconnectAudioGraceTimer();
      dom.overlay.classList.add('hidden');
      ensureScrubberLoopRunning();

      // Step 1: Register this PWA device UID & verify device authorization FIRST.
      // Apple ID / MusicKit / catalog checks run ONLY after the device is authorized on Mac.
      const regParams = {
        device_id: state.deviceId,
        device_name: state.deviceName,
        device_type: state.deviceType,
        lock_screen_controls: state.lockScreenControls,
        invite_token: state.inviteToken || ''
      };
      if (state.deviceSecret) {
        regParams.device_secret = state.deviceSecret;
      }
      send({
        action: 'register_device',
        params: regParams
      });
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
      state.pendingPingSentAt = 0;
      recentGetRpcSentAt.clear();
      if (state.isMeasuringRoom) {
        stopRoomMeasurementSession(false);
      }
      dom.overlay.classList.remove('hidden');
      pauseSilentAudioAfterDisconnectGrace();
      syncMotionVideoPlaybackState();
      ScreenWakeLockManager.syncByPlaybackAndConnection();
      scheduleReconnect();
    };

    socket.onerror = function () {
      state.connected = false;
      state.pendingPingSentAt = 0;
      dom.overlay.classList.remove('hidden');
      pauseSilentAudioAfterDisconnectGrace();
      syncMotionVideoPlaybackState();
      ScreenWakeLockManager.syncByPlaybackAndConnection();
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
    const act = (msgObj && msgObj.action) ? msgObj.action.toLowerCase() : '';
    const isAiCurateAction = (
      act === 'ai_curate' ||
      act === 'ai_curate_from_track' ||
      act === 'play_ai_track_vibe' ||
      act === 'build_sonic_bridge' ||
      act === 'sonic_bridge'
    );
    if (!socket || socket.readyState !== WebSocket.OPEN) {
      if (isAiCurateAction) {
        if (state.aiCurateTimeoutId) {
          clearTimeout(state.aiCurateTimeoutId);
          state.aiCurateTimeoutId = null;
        }
        state.isAiCurating = false;
        state.pendingStandbyAiAutoPlay = false;
        state.sonicBridgeAutoPlay = false;
      } else if (act === 'previous' || act === 'next' || act === 'play' || act === 'pause') {
        for (let i = pendingPreOpenQueue.length - 1; i >= 0; i--) {
          const itemAct = pendingPreOpenQueue[i] && pendingPreOpenQueue[i].action
            ? String(pendingPreOpenQueue[i].action).toLowerCase()
            : '';
          if (itemAct === 'previous' || itemAct === 'next' || itemAct === 'play' || itemAct === 'pause') {
            pendingPreOpenQueue.splice(i, 1);
          }
        }
        pendingPreOpenQueue.push(msgObj);
        if (!socket || socket.readyState === WebSocket.CLOSED || socket.readyState === WebSocket.CLOSING) {
          connectWebSocket();
        }
      } else if (act.startsWith('get_') && pendingPreOpenQueue.length < 16) {
        if (!pendingPreOpenQueue.some((item) => item && item.action === msgObj.action)) {
          pendingPreOpenQueue.push(msgObj);
        }
      }
      return false;
    }
    const isRealtimeSpectralPoll = (act === 'get_spectral_analysis' || act === 'get_spectral_rta');
    if (act.startsWith('get_') && !isRealtimeSpectralPoll && !(msgObj.params && msgObj.params.refresh === true)) {
      const nowMs = Date.now();
      const dedupeKey = `${act}|${msgObj.params ? JSON.stringify(msgObj.params) : ''}`;
      const prevAt = recentGetRpcSentAt.get(dedupeKey) || 0;
      if (nowMs - prevAt < 500) {
        return true;
      }
      recentGetRpcSentAt.set(dedupeKey, nowMs);
      if (recentGetRpcSentAt.size > 120) {
        for (const [k, ts] of recentGetRpcSentAt.entries()) {
          if (nowMs - ts >= 500) recentGetRpcSentAt.delete(k);
        }
      }
    }
    if (isAiCurateAction) {
      if (!msgObj.params || typeof msgObj.params !== 'object') {
        msgObj.params = {};
      }
      if (!msgObj.request_id && !msgObj.params.request_id) {
        state.aiCurateReqSeq = (state.aiCurateReqSeq || 0) + 1;
      }
      const reqId = msgObj.request_id || msgObj.params.request_id || state.aiCurateReqSeq;
      msgObj.request_id = reqId;
      msgObj.params.request_id = reqId;
      state.lastAiCurateSentAt = Date.now();
      if (state.aiCurateTimeoutId) {
        clearTimeout(state.aiCurateTimeoutId);
      }
      state.aiCurateTimeoutId = setTimeout(() => {
        if (state.aiCurateReqSeq === reqId) {
          state.isAiCurating = false;
          state.pendingStandbyAiAutoPlay = false;
          state.sonicBridgeAutoPlay = false;
          state.aiCurateTimeoutId = null;
        }
      }, 25000);
    } else if (act === 'search') {
      if (!msgObj.params || typeof msgObj.params !== 'object') {
        msgObj.params = {};
      }
      if (!msgObj.request_id && !msgObj.params.request_id) {
        state.searchReqSeq = (state.searchReqSeq || 0) + 1;
      }
      const reqId = msgObj.request_id || msgObj.params.request_id || state.searchReqSeq;
      msgObj.request_id = reqId;
      msgObj.params.request_id = reqId;
    }
    if (
      act === 'play_playlist' ||
      act === 'play_album' ||
      act === 'play_album_tracks' ||
      act === 'play_station' ||
      act === 'play_recent' ||
      act === 'play_recent_tracks'
    ) {
      state.activeAiCuratedTitle = '';
      state.activeAiCuratedPrompt = '';
    }
    if (act === 'play' || act.startsWith('play_') || act.includes('play') || act === 'next' || act === 'previous') {
      state.lastClientCommandAt = Date.now();
      syncSilentAudio(true);
    } else if (act === 'pause' || act === 'stop') {
      state.lastClientCommandAt = Date.now();
      syncSilentAudio(false);
    }
    socket.send(JSON.stringify(msgObj));
    return true;
  }
