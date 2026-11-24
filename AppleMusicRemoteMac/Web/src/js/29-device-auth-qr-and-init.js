  function setupBookletViewerControls() {
    const btnOpenNowPlaying = document.getElementById('btn-open-booklet');
    const btnOpenStandby = document.getElementById('standby-btn-booklet');
    const btnOpenDetail = document.getElementById('btn-detail-booklet');
    const btnClose = document.getElementById('btn-close-booklet');

    if (btnOpenNowPlaying) {
      btnOpenNowPlaying.addEventListener('click', () => {
        closeStationPickerModal();
        openBookletViewer();
      });
    }
    if (btnOpenStandby) {
      btnOpenStandby.addEventListener('click', () => openBookletViewer());
    }
    if (btnOpenDetail) {
      btnOpenDetail.addEventListener('click', () => {
        const det = state.currentPlaylistDetail;
        if (det && det.isAlbum) {
          openBookletViewer({
            album: det.name || det.title || '',
            artist: det.artist || det.sub || det.subtitle || '',
            albumId: det.id || ''
          });
        } else {
          openBookletViewer();
        }
      });
    }
    if (btnClose) btnClose.addEventListener('click', closeBookletViewer);

    window.addEventListener('resize', () => {
      if (bookletState.isOpen) {
        syncBookletViewerLayoutMode();
      }
    });

    document.addEventListener('keydown', (e) => {
      if (bookletState.isOpen && e.key === 'Escape') {
        e.preventDefault();
        closeBookletViewer();
      }
    });
  }

  // --- Device Authorization & Top-Left AMR Info / Lock Screen Controller ---
  function applyLockScreenControlsSetting(enabled, options = {}) {
    const boolVal = Boolean(enabled);
    state.lockScreenControls = boolVal;
    writePersistentCookie('amr_lock_screen', boolVal ? 'true' : 'false');
    try {
      localStorage.setItem('amr_lock_screen_controls', boolVal ? 'true' : 'false');
    } catch (e) {}

    const lockCheckbox = document.getElementById('amr-lock-screen-checkbox');
    if (lockCheckbox && lockCheckbox.checked !== boolVal) {
      lockCheckbox.checked = boolVal;
    }

    if (!boolVal || !state.deviceAuthorized) {
      teardownMediaSessionAndSilentAudio();
    } else {
      initSilentAudio();
      setupMediaSession();
      updateMediaSession();
      if (state.playerState === 'playing') {
        syncSilentAudio(true);
      }
    }

    if (options.syncServer && state.connected) {
      send({
        action: 'update_device_settings',
        params: {
          device_id: state.deviceId,
          lock_screen_controls: boolVal
        }
      });
    }

    if (options.showFeedback) {
      showToast(boolVal ? 'Экран блокировки включён' : 'Экран блокировки выключен');
    }
    syncDeviceInfoUI();
  }

  function syncDeviceInfoUI() {
    const commitBadgeEl = document.getElementById('amr-info-commit-badge');
    const commitDetailsEl = document.getElementById('amr-info-commit-details');
    const summaryEl = document.getElementById('amr-info-device-summary');
    const deviceUidMetaEl = document.getElementById('amr-info-device-uid');
    const nameInput = document.getElementById('amr-device-name-input');
    const lockCheckbox = document.getElementById('amr-lock-screen-checkbox');
    const lockNodeDot = document.getElementById('amr-lock-node-dot');
    const lockStateBadge = document.getElementById('amr-lock-state-badge');
    const authOverlay = document.getElementById('device-auth-overlay');
    const authShortIdEl = document.getElementById('auth-device-short-id');
    const authNameInput = document.getElementById('auth-device-name-input');
    const authFullIdEl = document.getElementById('auth-device-full-id');

    const commitHash = state.gitCommit || '7278dab';
    const commitDate = state.gitCommitDate || '2026-11-04';
    if (commitBadgeEl) {
      commitBadgeEl.textContent = commitHash;
    }
    if (commitDetailsEl) {
      commitDetailsEl.textContent = translateTextToEn(`Последний коммит: ${commitHash} (${commitDate}) • Pure Swift Server`);
    }

    const shortId = state.deviceShortId || computeShortDeviceId(state.deviceId);
    if (summaryEl) {
      summaryEl.textContent = `ID: ${shortId}`;
    }
    if (deviceUidMetaEl) {
      const dacStatus = state.allowDacSelection !== false
        ? (IS_EN ? 'DAC: On' : 'ЦАП: Вкл')
        : (IS_EN ? 'DAC: Off' : 'ЦАП: Закрыт');
      const dspStatus = state.allowDspPresetSelection !== false
        ? (IS_EN ? 'DSP: On' : 'DSP: Вкл')
        : (IS_EN ? 'DSP: Off' : 'DSP: Закрыт');
      const libStatus = state.allowLibraryModification !== false
        ? ''
        : (IS_EN ? ' • Lib: Read-Only' : ' • Медиатека: Чтение');
      deviceUidMetaEl.textContent = `UID: ${state.deviceId} • ${dacStatus} • ${dspStatus}${libStatus}`;
    }
    if (nameInput && document.activeElement !== nameInput) {
      nameInput.value = state.deviceName;
    }
    const isLockOn = Boolean(state.lockScreenControls);
    if (lockCheckbox) {
      lockCheckbox.checked = isLockOn;
    }
    if (lockNodeDot) {
      lockNodeDot.classList.toggle('active', isLockOn);
    }
    if (lockStateBadge) {
      lockStateBadge.textContent = translateTextToEn(isLockOn ? 'АКТИВНО' : 'ОТКЛЮЧЕНО');
      lockStateBadge.classList.toggle('highlight-green', isLockOn);
    }
    if (authShortIdEl) {
      authShortIdEl.textContent = shortId;
    }
    if (authNameInput && document.activeElement !== authNameInput) {
      authNameInput.value = state.deviceName;
    }
    if (authFullIdEl) {
      authFullIdEl.textContent = `UID: ${state.deviceId}`;
    }

    if (authOverlay) {
      if (!state.deviceAuthorized) {
        authOverlay.classList.remove('hidden');
        authOverlay.setAttribute('aria-hidden', 'false');
        if (dom.modalAppleAuth) {
          blurFocusedInContainer(dom.modalAppleAuth);
          dom.modalAppleAuth.classList.add('hidden');
          dom.modalAppleAuth.setAttribute('aria-hidden', 'true');
        }
      } else {
        if (authNameInput && document.activeElement === authNameInput) {
          authNameInput.blur();
        }
        blurFocusedInContainer(authOverlay);
        authOverlay.classList.add('hidden');
        authOverlay.setAttribute('aria-hidden', 'true');
        syncKeyboardFocusClass();
      }
    }
  }

  function handleDeviceAuthStatus(data) {
    if (!data || typeof data !== 'object') return;

    if (data.git_commit) {
      state.gitCommit = String(data.git_commit);
    }
    if (data.git_commit_date) {
      state.gitCommitDate = String(data.git_commit_date);
    }
    if (data.device_id) {
      const incomingId = String(data.device_id).toLowerCase();
      if (state.supersededFreshDeviceId && incomingId === state.supersededFreshDeviceId.toLowerCase() && state.deviceId !== incomingId) {
        return;
      }
      state.deviceId = incomingId;
      if (!state.deviceIdWasFreshlyGenerated) {
        persistUidToSecureStore(state.deviceId);
      }
    }
    state.deviceShortId = data.short_id || computeShortDeviceId(state.deviceId);

    if (data.device_secret || data.deviceSecret) {
      persistDeviceSecret(data.device_secret || data.deviceSecret);
    }

    if (data.device_name && String(data.device_name).trim()) {
      state.deviceName = String(data.device_name).trim();
      try { localStorage.setItem('amr_device_name', state.deviceName); } catch (e) {}
    }

    if (typeof data.authorized === 'boolean') {
      state.deviceAuthorized = data.authorized;
    } else if (typeof data.is_authorized === 'boolean') {
      state.deviceAuthorized = data.is_authorized;
    }

    if (state.deviceAuthorized) {
      clearInviteTokenFromClient();
    }

    if (typeof data.allow_dac_selection === 'boolean') {
      state.allowDacSelection = data.allow_dac_selection;
    }
    if (typeof data.allow_dsp_preset_selection === 'boolean') {
      state.allowDspPresetSelection = data.allow_dsp_preset_selection;
    }
    if (typeof data.allow_room_measurement === 'boolean') {
      state.allowRoomMeasurement = data.allow_room_measurement;
      if (!state.allowRoomMeasurement && state.isMeasuringRoom) {
        stopRoomMeasurementSession(true);
      }
    }
    if (typeof data.allow_late_night_mode === 'boolean') {
      state.allowLateNightMode = data.allow_late_night_mode;
    }
    if (typeof data.allow_library_modification === 'boolean') {
      state.allowLibraryModification = data.allow_library_modification;
    } else if (typeof data.allowLibraryModification === 'boolean') {
      state.allowLibraryModification = data.allowLibraryModification;
    }

    if (typeof data.lock_screen_controls === 'boolean') {
      applyLockScreenControlsSetting(data.lock_screen_controls, { syncServer: false, showFeedback: false });
    } else if (!state.deviceAuthorized) {
      teardownMediaSessionAndSilentAudio();
    }

    if (!state.deviceAuthorized) {
      state.initialAuthFetched = false;
    }

    applyDeviceCapabilityPermissionsUI();
    syncDeviceInfoUI();

    // Load library and Apple ID / MusicKit status ONLY after device is authorized.
    // Note: register_device / device approval already pushes player_state_changed, ai_curator_settings,
    // dsp_settings, tv_library_config, and queue; avoid duplicate startup RPC bursts!
    if (state.deviceAuthorized && !state.initialAuthFetched && state.connected) {
      state.initialAuthFetched = true;
      const authTime = Date.now();
      flushPendingPreOpenQueue();
      send({ action: 'get_user_token_status' });
      send({ action: 'get_developer_token' });
      send({ action: 'get_audio_devices' });
      send({ action: 'get_wled_settings' });
      send({ action: 'get_info' });
      send({ action: 'get_playlists' });
      send({ action: 'get_library_albums' });
      send({ action: 'get_account_status' });

      setTimeout(() => {
        if (state.connected && state.deviceAuthorized) {
          loadTrends();
        }
      }, 120);

      setTimeout(() => {
        if (!state.connected || !state.deviceAuthorized) return;
        if (!state.lastPlayerStateReceivedAt || state.lastPlayerStateReceivedAt < authTime - 2000) {
          send({ action: 'get_status' });
        }
        if (!state.lastQueueReceivedAt || state.lastQueueReceivedAt < authTime - 2000) {
          send({ action: 'get_queue' });
        }
        if (!state.lastAiSettingsReceivedAt || state.lastAiSettingsReceivedAt < authTime - 2000) {
          send({ action: 'get_ai_curator_settings' });
        }
        if (!state.lastDspSettings) {
          send({ action: 'get_dsp_settings' });
        }
        if (!state.tvLibraryConfigLoaded) {
          send({ action: 'get_tv_library_config' });
        }
      }, 900);
    }
  }

  function handleShareAccessQR(data) {
    if (!data || typeof data !== 'object') return;
    const shareUrl = String(data.share_url || data.base_url || window.location.origin);
    const qrDataUrl = data.qr_data_url;
    state.shareAccessUrl = shareUrl;

    const qrPanel = document.getElementById('amr-share-qr-panel');
    const qrImg = document.getElementById('amr-share-qr-img');
    const urlText = document.getElementById('amr-share-url-text');
    const btnNativeShare = document.getElementById('btn-native-share-link');

    if (qrImg && typeof qrDataUrl === 'string' && qrDataUrl.startsWith('data:image/png;base64,')) {
      qrImg.src = qrDataUrl;
    }
    if (urlText) {
      urlText.textContent = shareUrl;
    }
    if (btnNativeShare) {
      btnNativeShare.classList.toggle('hidden', typeof navigator.share !== 'function');
    }
    if (qrPanel) {
      qrPanel.classList.remove('hidden');
    }
  }

  function setupAmrInfoAndDeviceAuthControls() {
    const btnBrand = document.getElementById('btn-brand-info');
    const mobileBtnBrand = document.getElementById('mobile-btn-brand-info');
    const popover = document.getElementById('amr-info-popover');
    const btnClose = document.getElementById('btn-close-amr-info');
    const lockCheckbox = document.getElementById('amr-lock-screen-checkbox');
    const nameInput = document.getElementById('amr-device-name-input');
    const authNameInput = document.getElementById('auth-device-name-input');
    const btnShareAccessQr = document.getElementById('btn-share-access-qr');
    const btnShareAccessLabel = document.getElementById('amr-share-access-btn-label');
    const qrPanel = document.getElementById('amr-share-qr-panel');
    const btnCopyShareLink = document.getElementById('btn-copy-share-link');
    const btnNativeShareLink = document.getElementById('btn-native-share-link');

    syncDeviceInfoUI();

    const togglePopover = (e) => {
      if (e) e.stopPropagation();
      if (!popover) return;
      const topSettings = document.getElementById('top-settings-popover');
      if (topSettings) {
        blurFocusedInContainer(topSettings);
        topSettings.classList.add('hidden');
        topSettings.setAttribute('aria-hidden', 'true');
      }
      syncDeviceInfoUI();
      if (!popover.classList.contains('hidden')) {
        blurFocusedInContainer(popover);
      }
      popover.classList.toggle('hidden');
      popover.setAttribute('aria-hidden', popover.classList.contains('hidden') ? 'true' : 'false');
      syncKeyboardFocusClass();
    };

    if (btnBrand) btnBrand.addEventListener('click', togglePopover);
    if (mobileBtnBrand) mobileBtnBrand.addEventListener('click', togglePopover);
    if (btnClose && popover) {
      btnClose.addEventListener('click', () => {
        blurFocusedInContainer(popover);
        popover.classList.add('hidden');
        popover.setAttribute('aria-hidden', 'true');
        syncKeyboardFocusClass();
      });
    }

    if (popover) {
      popover.addEventListener('click', (e) => {
        if (e.target === popover) {
          blurFocusedInContainer(popover);
          popover.classList.add('hidden');
          popover.setAttribute('aria-hidden', 'true');
          syncKeyboardFocusClass();
        }
      });
    }

    if (btnShareAccessQr && qrPanel) {
      btnShareAccessQr.addEventListener('click', (e) => {
        e.stopPropagation();
        const isCurrentlyHidden = qrPanel.classList.contains('hidden');
        if (isCurrentlyHidden) {
          qrPanel.classList.remove('hidden');
          btnShareAccessQr.classList.add('active');
          if (btnShareAccessLabel) {
            btnShareAccessLabel.textContent = translateTextToEn('Скрыть QR-код');
          }
          send({ action: 'get_share_access_qr' });
        } else {
          qrPanel.classList.add('hidden');
          btnShareAccessQr.classList.remove('active');
          if (btnShareAccessLabel) {
            btnShareAccessLabel.textContent = translateTextToEn('Поделиться доступом');
          }
        }
      });
    }

    if (btnCopyShareLink) {
      btnCopyShareLink.addEventListener('click', (e) => {
        e.stopPropagation();
        const urlToCopy = state.shareAccessUrl || window.location.origin;
        const onCopied = () => showToast('Ссылка для подключения скопирована');
        if (navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
          navigator.clipboard.writeText(urlToCopy).then(onCopied).catch(() => {
            const ta = document.createElement('textarea');
            ta.setAttribute('readonly', '');
            ta.value = urlToCopy;
            ta.style.position = 'fixed';
            ta.style.opacity = '0';
            document.body.appendChild(ta);
            ta.select();
            try { document.execCommand('copy'); } catch (err) {}
            ta.blur();
            document.body.removeChild(ta);
            syncKeyboardFocusClass();
            onCopied();
          });
        } else {
          const ta = document.createElement('textarea');
          ta.setAttribute('readonly', '');
          ta.value = urlToCopy;
          ta.style.position = 'fixed';
          ta.style.opacity = '0';
          document.body.appendChild(ta);
          ta.select();
          try { document.execCommand('copy'); } catch (err) {}
          ta.blur();
          document.body.removeChild(ta);
          syncKeyboardFocusClass();
          onCopied();
        }
      });
    }

    if (btnNativeShareLink) {
      btnNativeShareLink.addEventListener('click', (e) => {
        e.stopPropagation();
        const urlToShare = state.shareAccessUrl || window.location.origin;
        if (typeof navigator.share === 'function') {
          navigator.share({
            title: 'Apple Music Remote',
            text: translateTextToEn('Поделиться доступом'),
            url: urlToShare
          }).catch(() => {});
        }
      });
    }

    if (lockCheckbox) {
      lockCheckbox.addEventListener('change', (e) => {
        applyLockScreenControlsSetting(e.target.checked, { syncServer: true, showFeedback: true });
      });
    }

    const commitDeviceName = (rawVal) => {
      const trimmed = String(rawVal || '').trim();
      if (!trimmed || trimmed === state.deviceName) return;
      state.deviceName = trimmed;
      try { localStorage.setItem('amr_device_name', trimmed); } catch (e) {}
      syncDeviceInfoUI();
      if (state.connected) {
        send({
          action: 'update_device_settings',
          params: {
            device_id: state.deviceId,
            device_name: trimmed
          }
        });
      }
      showToast('Имя устройства сохранено');
    };

    [nameInput, authNameInput].forEach((inp) => {
      if (!inp) return;
      inp.addEventListener('change', (e) => commitDeviceName(e.target.value));
      inp.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
          e.preventDefault();
          inp.blur();
          commitDeviceName(inp.value);
        }
      });
    });
  }

  function bindGenreCards() {
    document.querySelectorAll('#search-landing .genre-card[data-genre]').forEach(card => {
      card.addEventListener('click', () => {
        const genre = card.getAttribute('data-genre');
        if (genre) {
          dom.searchInput.value = genre;
          state.searchQuery = genre;
          state.searchScope = 'all';
          if (dom.filterChips) {
            dom.filterChips.forEach(c => c.classList.toggle('active', c.dataset.scope === 'all'));
          }
          dom.btnClearSearch.classList.remove('hidden');
          executeSearch(genre, 'all');
        }
      });
    });

    const homeGenresHeader = document.querySelector('#home-genres-section .home-section-header-link');
    if (homeGenresHeader && dom.homeGenresGrid) {
      homeGenresHeader.addEventListener('click', () => {
        dom.homeGenresGrid.scrollIntoView({ behavior: 'smooth', block: 'start' });
      });
    }
  }

  // iOS Standalone WebClip Cold-Launch Viewport Repair (WKWebViewIOS.mm _setViewportFitEdges:)
  // On cold Home Screen launch, WKWebView processes <meta name="viewport" viewport-fit=cover> while
  // _shouldDeferGeometryUpdates is YES during SpringBoard's zoom animation, leaving fixed bottom: 0
  // inset by 34pt until rotated. Re-committing viewport-fit=contain -> cover after launch settles
  // invokes _dispatchSetViewLayoutSize & _scheduleVisibleContentRectUpdate without rotating.
  const VIEWPORT_META_COVER = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover';
  const VIEWPORT_META_CONTAIN = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=contain';
  let viewportRepairInFlight = false;

  function isStandalonePwaMode() {
    return Boolean(
      window.navigator.standalone === true ||
      (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches)
    );
  }

  function hasStandaloneColdPortraitGap() {
    if (!isStandalonePwaMode()) return false;
    if (document.body && document.body.classList.contains('keyboard-open')) return false;
    const iw = window.innerWidth || 0;
    const ih = window.innerHeight || 0;
    if (ih <= iw) return false;
    const sh = (window.screen && window.screen.height) ? window.screen.height : 0;
    const sw = (window.screen && window.screen.width) ? window.screen.width : 0;
    const portraitScreenH = Math.max(sh, sw);
    if (!portraitScreenH) return false;
    const gap = portraitScreenH - ih;
    return gap >= 16 && gap <= 120;
  }

  function repairStandaloneColdLaunchViewport(forceToggle = false) {
    if (!isStandalonePwaMode() || viewportRepairInFlight) return;
    if (document.body && document.body.classList.contains('keyboard-open')) return;
    const isPortrait = (window.innerHeight || 0) > (window.innerWidth || 0);
    if (!isPortrait) return;
    if (!forceToggle && !hasStandaloneColdPortraitGap()) return;

    const meta = document.querySelector('meta[name="viewport"]');
    if (!meta) return;

    viewportRepairInFlight = true;
    meta.setAttribute('content', VIEWPORT_META_CONTAIN);
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        setTimeout(() => {
          meta.setAttribute('content', VIEWPORT_META_COVER);
          try { window.scrollTo(0, 0); } catch (_) {}
          viewportRepairInFlight = false;
          lastViewportWidth = -1;
          handleResize({ force: true });
        }, 28);
      });
    });
  }

  function scheduleStandaloneColdLaunchRepairs() {
    if (!isStandalonePwaMode()) return;
    repairStandaloneColdLaunchViewport(false);
    setTimeout(() => repairStandaloneColdLaunchViewport(true), 120);
    setTimeout(() => repairStandaloneColdLaunchViewport(true), 380);
    setTimeout(() => repairStandaloneColdLaunchViewport(false), 800);
  }

  window.addEventListener('load', () => {
    if (isStandalonePwaMode()) {
      setTimeout(() => repairStandaloneColdLaunchViewport(true), 60);
      setTimeout(() => repairStandaloneColdLaunchViewport(false), 420);
    }
  }, { passive: true });

  window.addEventListener('pageshow', (e) => {
    if (isStandalonePwaMode()) {
      setTimeout(() => repairStandaloneColdLaunchViewport(Boolean(e && e.persisted)), 80);
    }
  }, { passive: true });

  // Initialize
  setupAmrInfoAndDeviceAuthControls();
  setupMediaSession();
  setupArtworkSwipeGestures();
  setupMiniPlayerGestures();
  setupStandbyAndWledControls();
  setupDSPControls();
  setupRoomAcousticControls();
  setupBookletViewerControls();
  renderHeroCarousel({});
  renderHomeStations(DEFAULT_STATIONS);
  renderHomeGenres(DEFAULT_GENRES);
  bindGenreCards();
  handleResize({ force: true });
  scheduleStandaloneColdLaunchRepairs();
  recoverOrPersistDeviceUidBeforeConnect().finally(() => {
    connectWebSocket();
  });
