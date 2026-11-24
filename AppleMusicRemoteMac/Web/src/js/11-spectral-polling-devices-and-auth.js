  let cachedStandbyOverlayEl = null;
  let cachedCoarsePointerMql = null;

  function stopSpectralPolling() {
    if (spectralPollTimer) {
      clearInterval(spectralPollTimer);
      spectralPollTimer = null;
    }
    spectralPollIntervalMs = 0;
    spectralRpcInFlightAt = 0;
  }

  function isStandbyOrLandscapeVisible() {
    if (!cachedStandbyOverlayEl) {
      cachedStandbyOverlayEl = document.getElementById('standby-tv-overlay');
    }
    const isExplicitOpen = Boolean(cachedStandbyOverlayEl && !cachedStandbyOverlayEl.classList.contains('hidden'));
    if (isExplicitOpen) return true;
    if (!cachedCoarsePointerMql && window.matchMedia) {
      cachedCoarsePointerMql = window.matchMedia('(hover: none) and (pointer: coarse)');
    }
    const isTouchPhone = Boolean(cachedCoarsePointerMql && cachedCoarsePointerMql.matches);
    return isTouchPhone && window.innerHeight <= 540 && window.innerWidth >= 568 && window.innerWidth > window.innerHeight && !document.body.classList.contains('keyboard-open');
  }

  function handleSpectralAnalysisMessage(data) {
    spectralRpcInFlightAt = 0;
    if (!data || !data.verdict) return;
    const prev = state.spectralAnalysis || {};
    const prevVerdict = prev.verdict || '';
    const prevRate = Number(prev.sample_rate || prev.sampleRate || 0);
    const prevZeroPad = Boolean(prev.is_zero_padded || prev.isZeroPadded);
    const prevEnabled = prev.is_enabled !== false && prev.isEnabled !== false && prevVerdict !== 'disabled';

    const merged = (prevVerdict === data.verdict && data.verdict_title === undefined && data.verdictTitle === undefined)
      ? Object.assign({}, prev, data)
      : data;
    state.spectralAnalysis = merged;
    state.lastSpectralUpdateAt = performance.now();

    const nextRate = Number(merged.sample_rate || merged.sampleRate || 0);
    const nextZeroPad = Boolean(merged.is_zero_padded || merged.isZeroPadded);
    const nextEnabled = merged.is_enabled !== false && merged.isEnabled !== false && merged.verdict !== 'disabled';

    if (prevVerdict !== merged.verdict || prevRate !== nextRate || prevZeroPad !== nextZeroPad || prevEnabled !== nextEnabled) {
      updateSignalPathDetails();
    } else {
      renderSpectralAnalysisUI();
    }
  }

  let spectralPollTickCount = 0;
  function syncSpectralPolling() {
    if (document.hidden) {
      stopSpectralPolling();
      return;
    }
    const sa = state.spectralAnalysis || {};
    const saEnabled = sa.is_enabled !== false && sa.isEnabled !== false && sa.verdict !== 'disabled';
    const isModalOpen = Boolean(dom.qualityModal && !dom.qualityModal.classList.contains('hidden'));
    const isTvActive = isStandbyOrLandscapeVisible();
    const isCachedPass = Boolean(sa.is_cached || sa.isCached);
    const hasDrScore = (sa.tt_dr_score !== undefined && sa.tt_dr_score !== null) || (sa.ttDrScore !== undefined && sa.ttDrScore !== null);
    const stillAnalyzing = (!isCachedPass && (!sa.verdict || sa.verdict === 'analyzing')) || (!hasDrScore && spectralPollTickCount < 24);
    const needsSoundCheck = Boolean(state.ampSoundCheckEnabled && (state.ampSoundCheckGainDb === null || state.ampSoundCheckGainDb === undefined));
    const isPlayingAndNeeded = state.playerState === 'playing' && saEnabled && (isTvActive || stillAnalyzing || needsSoundCheck);

    if (isModalOpen || isPlayingAndNeeded) {
      const isVisualRtaActive = isModalOpen || (isTvActive && state.playerState === 'playing' && saEnabled);
      const desiredIntervalMs = isVisualRtaActive ? 90 : 220;
      if (spectralPollTimer && spectralPollIntervalMs !== desiredIntervalMs) {
        clearInterval(spectralPollTimer);
        spectralPollTimer = null;
      }
      if (!spectralPollTimer) {
        spectralPollIntervalMs = desiredIntervalMs;
        spectralPollTimer = setInterval(() => {
          if (document.hidden) {
            stopSpectralPolling();
            return;
          }
          spectralPollTickCount += 1;
          const curSa = state.spectralAnalysis || {};
          const curEnabled = curSa.is_enabled !== false && curSa.isEnabled !== false && curSa.verdict !== 'disabled';
          const modalStillOpen = Boolean(dom.qualityModal && !dom.qualityModal.classList.contains('hidden'));
          const tvStillActive = isStandbyOrLandscapeVisible() && state.playerState === 'playing' && curEnabled;
          const curCachedPass = Boolean(curSa.is_cached || curSa.isCached);
          const curHasDr = (curSa.tt_dr_score !== undefined && curSa.tt_dr_score !== null) || (curSa.ttDrScore !== undefined && curSa.ttDrScore !== null);
          const curStillAnalyzing = state.playerState === 'playing' && curEnabled && (
            (!curCachedPass && (!curSa.verdict || curSa.verdict === 'analyzing')) ||
            (!curHasDr && spectralPollTickCount < 24)
          );
          const curNeedsSoundCheck = state.playerState === 'playing' && Boolean(state.ampSoundCheckEnabled && (state.ampSoundCheckGainDb === null || state.ampSoundCheckGainDb === undefined));
          if (!modalStillOpen && !tvStillActive && !curStillAnalyzing && !curNeedsSoundCheck) {
            stopSpectralPolling();
            return;
          }
          const wantFastNow = modalStillOpen || tvStillActive;
          if ((wantFastNow ? 90 : 220) !== spectralPollIntervalMs) {
            syncSpectralPolling();
            return;
          }
          const nowPerf = performance.now();
          if (spectralRpcInFlightAt > 0 && (nowPerf - spectralRpcInFlightAt) < 420) {
            return;
          }
          const hasFullVerdictStrings = Boolean(curSa.verdict && curSa.verdict !== 'analyzing' && (curSa.verdict_title || curSa.verdictTitle));
          const useCompactRta = wantFastNow && hasFullVerdictStrings && (spectralPollTickCount % 12 !== 0);
          spectralRpcInFlightAt = nowPerf;
          if (!send({ action: useCompactRta ? 'get_spectral_rta' : 'get_spectral_analysis' })) {
            spectralRpcInFlightAt = 0;
          }
        }, desiredIntervalMs);
      }
      ensureStandbyRtaAnimLoop();
    } else {
      stopSpectralPolling();
      ensureStandbyRtaAnimLoop();
    }
  }

  const openQualityModal = () => {
    triggerHaptic('light');
    if (dom.qualityModal) {
      dom.qualityModal.classList.remove('hidden');
      dom.qualityModal.setAttribute('aria-hidden', 'false');
    }
    applyDeviceCapabilityPermissionsUI();
    updateSignalPathDetails();
    ensureStandbyRtaAnimLoop();
    send({ action: 'get_dsp_settings' });
    send({ action: 'get_spectral_analysis' });
    syncSpectralPolling();
  };

  if (dom.audioQualityBadge) dom.audioQualityBadge.addEventListener('click', openQualityModal);
  if (dom.desktopDacBadge) dom.desktopDacBadge.addEventListener('click', openQualityModal);
  if (dom.mobileDacBadge) dom.mobileDacBadge.addEventListener('click', openQualityModal);
  const playerDrBadgeEl = document.getElementById('player-dr-badge');
  const mobileDrBadgeEl = document.getElementById('mobile-dr-badge');
  const standbyDacBadgeEl = document.getElementById('standby-dac-badge');
  const standbySpectralBadgeEl = document.getElementById('standby-spectral-badge');
  const standbyDrBadgeEl = document.getElementById('standby-dr-badge');
  if (playerDrBadgeEl) playerDrBadgeEl.addEventListener('click', openQualityModal);
  if (mobileDrBadgeEl) mobileDrBadgeEl.addEventListener('click', openQualityModal);
  if (standbyDacBadgeEl) standbyDacBadgeEl.addEventListener('click', openQualityModal);
  if (standbySpectralBadgeEl) standbySpectralBadgeEl.addEventListener('click', openQualityModal);
  if (standbyDrBadgeEl) standbyDrBadgeEl.addEventListener('click', openQualityModal);

  function closeQualityModal() {
    if (state.isMeasuringRoom || state.roomIsPlayingTestSignal || (state.roomAcoustic && state.roomAcoustic.is_test_signal_playing)) {
      stopRoomMeasurementSession(true);
    }
    if (dom.qualityModal) {
      blurFocusedInContainer(dom.qualityModal);
      dom.qualityModal.classList.add('hidden');
      dom.qualityModal.setAttribute('aria-hidden', 'true');
    }
    syncSpectralPolling();
  }

  if (dom.btnCloseModal) {
    dom.btnCloseModal.addEventListener('click', closeQualityModal);
  }

  // --- Audio Output Devices Modal (DAC Selector) ---
  const openDevicesModal = () => {
    if (state.allowDacSelection === false) {
      showToast(IS_EN ? 'DAC selection is disabled for this device on Mac' : 'Выбор ЦАП отключён для этого устройства в настройках Mac');
      return;
    }
    triggerHaptic('light');
    if (dom.devicesModal) {
      dom.devicesModal.classList.remove('hidden');
      dom.devicesModal.setAttribute('aria-hidden', 'false');
      send({ action: 'get_audio_devices' });
    }
  };

  if (dom.btnOpenDevices) dom.btnOpenDevices.addEventListener('click', openDevicesModal);

  if (dom.btnCloseDevices) {
    dom.btnCloseDevices.addEventListener('click', () => {
      if (dom.devicesModal) {
        blurFocusedInContainer(dom.devicesModal);
        dom.devicesModal.classList.add('hidden');
        dom.devicesModal.setAttribute('aria-hidden', 'true');
      }
    });
  }

  if (dom.devicesModal) {
    dom.devicesModal.addEventListener('click', (e) => {
      if (e.target === dom.devicesModal) {
        blurFocusedInContainer(dom.devicesModal);
        dom.devicesModal.classList.add('hidden');
        dom.devicesModal.setAttribute('aria-hidden', 'true');
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

    const currentDevObj = (data && !Array.isArray(data) && data.current_device && typeof data.current_device === 'object')
      ? data.current_device
      : null;
    const defaultDev = list.find(d => d && (d.isDefault || d.is_default)) || currentDevObj;
    if (defaultDev) {
      state.audioDeviceName = defaultDev.name || defaultDev.friendlyName || state.audioDeviceName;
      if (defaultDev.currentSampleRate || defaultDev.sampleRate) {
        state.audioDeviceSampleRate = defaultDev.currentSampleRate || defaultDev.sampleRate;
      }
      const isNet = Boolean(
        defaultDev.type === 'dlna' ||
        defaultDev.isNetwork ||
        defaultDev.is_network ||
        defaultDev.protocol === 'dlna' ||
        defaultDev.protocol === 'bluos' ||
        (typeof defaultDev.uid === 'string' && defaultDev.uid.startsWith('dlna:'))
      );
      state.isDlnaActive = isNet;
    }
    renderAudioDevicesList();
    if (state.lastDspSettings && typeof state.lastDspSettings === 'object') {
      state.lastDspSettings = Object.assign({}, state.lastDspSettings, { is_dlna_active: state.isDlnaActive });
      updateDSPSettingsUI(state.lastDspSettings);
    } else {
      applyDeviceCapabilityPermissionsUI();
      updateSignalPathDetails();
    }
    if (typeof renderVolumeUI === 'function') {
      renderVolumeUI();
    }
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
        subtitle = `Сетевой стример • До 192 кГц Hi-Res • ${escapeHtml(dev.manufacturer || 'DLNA')}`;
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
            <span class="audio-device-title">${escapeHtml(dev.name || (isDLNA ? 'DLNA Стример' : 'Аудиовыход'))}</span>
            ${isDLNA ? '<span class="badge-dlna">DLNA</span>' : ''}
          </div>
          <div class="audio-device-meta">${subtitle}</div>
        </div>
        ${dev.isDefault ? '<span class="audio-device-badge active">Активен</span>' : '<span class="audio-device-badge">Выбрать</span>'}
      `;

      item.addEventListener('click', () => {
        if (state.allowDacSelection === false) {
          showToast(IS_EN ? 'DAC selection is disabled for this device on Mac' : 'Выбор ЦАП отключён для этого устройства в настройках Mac');
          return;
        }
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
  let musicKitLoadedListenerBound = false;

  function setupMusicKitFromState(forceConfigure = false) {
    const devToken = state.developerToken;
    if (!devToken || !window.MusicKit) return;
    if (!forceConfigure && (state.hasUserToken || state.isAccountSynced || !state.userTokenStatusChecked)) {
      return;
    }
    try {
      if (!musicKitInstance) {
        window.MusicKit.configure({
          developerToken: devToken,
          app: {
            name: 'Apple Music Remote',
            build: '3.0.0'
          }
        });
        musicKitInstance = window.MusicKit.getInstance();
        if (musicKitInstance && musicKitInstance.isAuthorized) {
          const uToken = musicKitInstance.musicUserToken;
          if (uToken && !state.hasUserToken) {
            send({ action: 'set_user_token', params: { user_token: uToken } });
          }
        }
        if (state.lockScreenControls && state.deviceAuthorized) {
          setupMediaSession(true);
          updateMediaSession();
        }
      }
    } catch (e) {
      console.warn('MusicKit configuration error:', e);
    }
  }

  function initMusicKit(devToken) {
    if (!devToken) return;
    state.developerToken = devToken;
    if (window.MusicKit) {
      setupMusicKitFromState(false);
    } else if (!musicKitLoadedListenerBound) {
      musicKitLoadedListenerBound = true;
      document.addEventListener('musickitloaded', () => setupMusicKitFromState(false), { once: true });
    }
  }

  function updateUserTokenStatus(data) {
    if (!state.deviceAuthorized || (data && data.status === 'error')) {
      if (dom.modalAppleAuth) {
        dom.modalAppleAuth.classList.add('hidden');
        dom.modalAppleAuth.setAttribute('aria-hidden', 'true');
      }
      return;
    }
    const hasToken = Boolean(data && (data.has_user_token !== undefined ? data.has_user_token : data.hasUserToken));
    state.hasUserToken = hasToken;
    state.userTokenStatusChecked = true;
    if (data && data.storefront) {
      state.userStorefront = String(data.storefront).trim().toLowerCase();
    }
    if (data && data.locale) {
      state.userLocale = String(data.locale).trim();
    }

    if (hasToken || state.isAccountSynced) {
      if (dom.modalAppleAuth) {
        dom.modalAppleAuth.classList.add('hidden');
        dom.modalAppleAuth.setAttribute('aria-hidden', 'true');
      }

      const activeCountry = getActiveStorefront();
      if (activeCountry && state.trends.country !== activeCountry) {
        state.trends.country = activeCountry;
        loadTrends(activeCountry);
      }
    } else {
      setupMusicKitFromState(true);
      if (dom.modalAppleAuth && !state.isAccountSynced) {
        dom.modalAppleAuth.classList.remove('hidden');
        dom.modalAppleAuth.setAttribute('aria-hidden', 'false');
      }
    }
  }

  function getActiveStorefront() {
    const fromHealth = state.accountHealth && (
      state.accountHealth.web_storefront ||
      state.accountHealth.storefront ||
      state.accountHealth.mac_country_code
    );
    const raw = state.userStorefront || fromHealth || (state.trends && state.trends.country) || '';
    return String(raw).trim().toLowerCase();
  }

  function updateAccountHealth(data) {
    if (!data) return;
    state.accountHealth = data;
    const isSynced = data.status === 'synchronized' || data.is_accounts_matched === true;
    state.isAccountSynced = isSynced;
    const detectedSf = String(data.web_storefront || data.storefront || data.mac_country_code || state.userStorefront || '').trim().toLowerCase();
    if (detectedSf && state.userStorefront !== detectedSf) {
      state.userStorefront = detectedSf;
      if (state.trends.country !== detectedSf) {
        state.trends.country = detectedSf;
        loadTrends(detectedSf);
      }
    }
    const email = data.account_email || data.mac_apple_id || data.macos_account || 'Apple Music';
    const storefront = (detectedSf || '—').toUpperCase();
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
      setupMusicKitFromState(true);
    }

    if (!musicKitInstance) {
      send({ action: 'get_developer_token' });
      if (dom.authModalStatus) dom.authModalStatus.innerHTML = '<div class="spinner-sm"></div><span>Получение ключа разработчика...</span>';
      setTimeout(() => {
        if (dom.btnAuthModalLogin) dom.btnAuthModalLogin.disabled = false;
        if (state.developerToken && !musicKitInstance) {
          setupMusicKitFromState(true);
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
        blurFocusedInContainer(dom.modalAccountDiag);
        dom.modalAccountDiag.classList.add('hidden');
        dom.modalAccountDiag.setAttribute('aria-hidden', 'true');
      }
    });
  }
  if (dom.btnDoneAccountDiag) {
    dom.btnDoneAccountDiag.addEventListener('click', () => {
      triggerHaptic('light');
      if (dom.modalAccountDiag) {
        blurFocusedInContainer(dom.modalAccountDiag);
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

  // --- In-App Confirmation Modal & Track Actions (•••) Modal ---
  let pendingDeleteConfirmCallback = null;

  function closeConfirmDeleteModal() {
    pendingDeleteConfirmCallback = null;
    if (dom.confirmDeleteModal) {
      blurFocusedInContainer(dom.confirmDeleteModal);
      dom.confirmDeleteModal.classList.add('hidden');
      dom.confirmDeleteModal.setAttribute('aria-hidden', 'true');
    }
  }

  function confirmLibraryDeleteModal({
    title,
    message,
    confirmLabel = 'Удалить',
    onConfirm
  }) {
    if (!dom.confirmDeleteModal) {
      if (typeof onConfirm === 'function') onConfirm();
      return;
    }
    triggerHaptic('light');
    pendingDeleteConfirmCallback = typeof onConfirm === 'function' ? onConfirm : null;

    if (dom.confirmDeleteTitle) {
      dom.confirmDeleteTitle.textContent = translateTextToEn(title || 'Удалить из медиатеки?');
    }
    if (dom.confirmDeleteMessage) {
      dom.confirmDeleteMessage.textContent = message || translateTextToEn('Элемент будет удалён из вашей медиатеки Apple Music.');
    }
    if (dom.btnConfirmDeleteOk) {
      dom.btnConfirmDeleteOk.textContent = translateTextToEn(confirmLabel || 'Удалить');
    }
    dom.confirmDeleteModal.classList.remove('hidden');
    dom.confirmDeleteModal.setAttribute('aria-hidden', 'false');
  }

  if (dom.btnConfirmDeleteCancel) {
    dom.btnConfirmDeleteCancel.addEventListener('click', () => {
      triggerHaptic('light');
      closeConfirmDeleteModal();
    });
  }
  if (dom.btnConfirmDeleteOk) {
    dom.btnConfirmDeleteOk.addEventListener('click', () => {
      triggerHaptic('medium');
      const fn = pendingDeleteConfirmCallback;
      closeConfirmDeleteModal();
      if (fn) fn();
    });
  }
  if (dom.confirmDeleteModal) {
    dom.confirmDeleteModal.addEventListener('click', (e) => {
      if (e.target === dom.confirmDeleteModal) {
        closeConfirmDeleteModal();
      }
    });
  }

  function getActiveActionTrack() {
    return state.actionTargetTrack || state.track || null;
  }

  function closeStationPickerModal() {
    state.actionTargetTrack = null;
    if (dom.stationPickerModal) {
      blurFocusedInContainer(dom.stationPickerModal);
      dom.stationPickerModal.classList.add('hidden');
      dom.stationPickerModal.setAttribute('aria-hidden', 'true');
    }
  }

  function resolveCurrentBrowseOrigin() {
    if (dom.libraryArtistDetailPane && !dom.libraryArtistDetailPane.classList.contains('hidden')) {
      return 'library-artist-detail';
    }
    if (dom.playlistDetailPane && !dom.playlistDetailPane.classList.contains('hidden')) {
      return state.detailReturnOrigin || 'library';
    }
    if (isDesktopLayout()) {
      const dt = state.desktopActiveTab || 'home';
      if (dt === 'search') return 'search';
      if (dt === 'playlists') return 'playlists';
      if (dt === 'home' || dt === 'trends') {
        return (dom.sectionGridView && dom.sectionGridView.classList.contains('active')) ? 'home-grid' : 'home';
      }
      if (dt === 'library') return `library-${state.libraryTab || 'recent'}`;
      return 'library';
    }
    const mv = state.activeView || 'view-now-playing';
    if (mv === 'view-now-playing') return 'player';
    if (mv === 'view-search') return 'search';
    if (mv === 'view-playlists') return 'playlists';
    if (mv === 'view-home' || mv === 'view-trends') {
      return (dom.sectionGridView && dom.sectionGridView.classList.contains('active')) ? 'home-grid' : 'home';
    }
    if (mv === 'view-library') return `library-${state.libraryTab || 'recent'}`;
    return 'library';
  }
