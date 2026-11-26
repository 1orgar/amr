  function renderNowPlaying() {
    const isPlaying = state.playerState === 'playing';
    const t = state.track;

    // Track Meta
    if (t) {
      const titleText = t.name || translateTextToEn('Без названия');
      const albumText = (t.album || '').trim();
      const artistText = t.artist || translateTextToEn('Неизвестный исполнитель');
      if (dom.playerTitle.textContent !== titleText) {
        dom.playerTitle.textContent = titleText;
      }
      dom.playerTitle.title = titleText;
      if (dom.playerArtist.textContent !== artistText) {
        dom.playerArtist.textContent = artistText;
      }
      if (dom.playerAlbum.textContent !== albumText) {
        dom.playerAlbum.textContent = albumText;
      }
      dom.playerAlbum.classList.toggle('clickable-album', Boolean(albumText));
      dom.playerAlbum.title = albumText ? `Перейти к альбому «${albumText}»` : '';
      if (dom.btnGoToAlbum) {
        dom.btnGoToAlbum.disabled = !albumText;
        dom.btnGoToAlbum.title = albumText ? `Перейти к альбому «${albumText}»` : 'Перейти к альбому';
      }
      if (dom.btnAiTrackVibe) {
        dom.btnAiTrackVibe.disabled = !t.name;
        dom.btnAiTrackVibe.classList.toggle('hidden', !state.aiCuratorEnabled);
        dom.btnAiTrackVibe.title = t.name
          ? translateTextToEn(`✨ ИИ-подбор по вайбу «${t.name}»`)
          : translateTextToEn('✨ ИИ-подбор по вайбу текущего трека');
      }
      const art = getArtworkSrc(t);
      setPlayerArtwork(art);
      dom.btnFavorite.classList.toggle('active', Boolean(t.favorited));
      if (dom.miniBtnFavorite) dom.miniBtnFavorite.classList.toggle('active', Boolean(t.favorited));

      // Mini Player sync
      if (dom.miniTitle.textContent !== titleText) {
        dom.miniTitle.textContent = titleText;
      }
      const miniArtistText = t.artist || 'Apple Music';
      if (dom.miniArtist.textContent !== miniArtistText) {
        dom.miniArtist.textContent = miniArtistText;
      }
    } else {
      const notPlayingText = translateTextToEn('Не играет');
      if (dom.playerTitle.textContent !== notPlayingText) {
        dom.playerTitle.textContent = notPlayingText;
      }
      dom.playerTitle.title = notPlayingText;
      if (dom.playerArtist.textContent !== 'Apple Music') {
        dom.playerArtist.textContent = 'Apple Music';
      }
      if (dom.playerAlbum.textContent !== '') {
        dom.playerAlbum.textContent = '';
      }
      dom.playerAlbum.classList.remove('clickable-album');
      dom.playerAlbum.title = '';
      if (dom.btnGoToAlbum) {
        dom.btnGoToAlbum.disabled = true;
        dom.btnGoToAlbum.title = translateTextToEn('Перейти к альбому');
      }
      if (dom.btnAiTrackVibe) {
        dom.btnAiTrackVibe.disabled = true;
        dom.btnAiTrackVibe.classList.toggle('hidden', !state.aiCuratorEnabled);
        dom.btnAiTrackVibe.title = translateTextToEn('✨ ИИ-подбор по вайбу текущего трека');
      }
      setPlayerArtwork('apple-touch-icon.svg');
      dom.btnFavorite.classList.remove('active');
      if (dom.miniBtnFavorite) dom.miniBtnFavorite.classList.remove('active');

      if (dom.miniTitle.textContent !== notPlayingText) {
        dom.miniTitle.textContent = notPlayingText;
      }
      if (dom.miniArtist.textContent !== 'Apple Music') {
        dom.miniArtist.textContent = 'Apple Music';
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
    const isRadioMode = Boolean(state.isRadio);
    dom.btnShuffle.disabled = isRadioMode;
    dom.btnShuffle.classList.toggle('disabled-control', isRadioMode);
    dom.btnShuffle.classList.toggle('active', !isRadioMode && Boolean(state.shuffle));
    dom.btnShuffle.title = isRadioMode
      ? (IS_EN ? 'Shuffle unavailable on Radio' : 'Перемешивание недоступно для радио')
      : (state.shuffle
        ? (IS_EN ? 'Shuffle: On' : 'Перемешать: Вкл')
        : (IS_EN ? 'Shuffle: Off' : 'Перемешать'));

    const effectiveRepeat = (isRadioMode && state.repeatMode === 'all') ? 'off' : state.repeatMode;
    if (effectiveRepeat === 'one') {
      dom.btnRepeat.classList.add('active');
      dom.repeatBadge.classList.remove('hidden');
      dom.btnRepeat.title = IS_EN ? 'Repeat Mode: One Track (1)' : 'Повтор: Зациклен 1 трек';
    } else if (effectiveRepeat === 'all') {
      dom.btnRepeat.classList.add('active');
      dom.repeatBadge.classList.add('hidden');
      dom.btnRepeat.title = IS_EN ? 'Repeat Mode: Queue' : 'Повтор: Вся очередь';
    } else {
      dom.btnRepeat.classList.remove('active');
      dom.repeatBadge.classList.add('hidden');
      dom.btnRepeat.title = isRadioMode
        ? (IS_EN ? 'Repeat Mode: Off (tap to repeat track)' : 'Повтор трека: Выкл')
        : (IS_EN ? 'Repeat Mode: Off' : 'Режим повтора: Выкл');
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

    // Only update scrubber UI here if stopped, paused, or buffering at 0:00.
    // When actively playing, the 60fps scrubberAnimationLoop handles smooth rendering without jitter!
    if (!state.isScrubbing && (state.playerState !== 'playing' || !(state.duration > 0) || state.isBuffering || state.isStagingBuffer || (!state.hasStartedAdvancingForTrack && state.lastSyncPos <= 0.08))) {
      updateScrubberUI(state.lastSyncPos, state.duration);
    }
    syncTrackLoadingIndicatorUI();
    ensureScrubberLoopRunning();

    renderVolumeUI();
    renderCurrentQueueTrack(dom.queueCurrentTrack);
    if (typeof isStandbyQueueModalOpen === 'function' && isStandbyQueueModalOpen()) {
      renderStandbyQueueModal();
    }
    updateMediaSession();
    syncStandbyAndMotionCoverUI();
    syncCurrentTrackBookletAvailability();
    refreshAllTitleMarquees();
  }

  let standbyVolPulseTimer = null;
  let standbyVolLoupeTimer = null;

  function triggerStandbyVolumePulse() {
    if (!dom.standbyVolumeSection) return;
    dom.standbyVolumeSection.classList.add('vol-active-pulse');
    if (standbyVolPulseTimer) clearTimeout(standbyVolPulseTimer);
    standbyVolPulseTimer = setTimeout(() => {
      if (dom.standbyVolumeSection) {
        dom.standbyVolumeSection.classList.remove('vol-active-pulse');
      }
    }, 2200);
  }

  function showStandbyVolumeLoupe(autoHideMs = 0) {
    if (!dom.standbyVolumeSection) return;
    dom.standbyVolumeSection.classList.add('is-scrubbing', 'vol-active-pulse');
    if (dom.standbyVolLoupe) dom.standbyVolLoupe.classList.add('visible');
    if (standbyVolLoupeTimer) clearTimeout(standbyVolLoupeTimer);
    if (autoHideMs > 0) {
      standbyVolLoupeTimer = setTimeout(() => {
        hideStandbyVolumeLoupe();
      }, autoHideMs);
    }
  }

  function hideStandbyVolumeLoupe() {
    if (standbyVolLoupeTimer) {
      clearTimeout(standbyVolLoupeTimer);
      standbyVolLoupeTimer = null;
    }
    if (dom.standbyVolumeSection) {
      dom.standbyVolumeSection.classList.remove('is-scrubbing');
    }
    if (dom.standbyVolLoupe) {
      dom.standbyVolLoupe.classList.remove('visible');
    }
  }

  function updateStandbyLoupePosition(vol, pct, isMuted) {
    const cleanPct = isMuted ? 0 : Math.max(0, Math.min(100, pct));
    if (dom.standbyVolFill) {
      dom.standbyVolFill.style.width = `${cleanPct}%`;
    }
    if (dom.standbyVolThumb) {
      dom.standbyVolThumb.style.left = `${cleanPct}%`;
    }
    if (dom.standbyVolLoupe) {
      const clampedLoupeLeft = Math.max(8, Math.min(92, cleanPct));
      dom.standbyVolLoupe.style.left = `${clampedLoupeLeft}%`;
    }
    if (dom.standbyVolLoupeText) {
      dom.standbyVolLoupeText.textContent = (isMuted || vol === 0) ? 'MUTE' : `${vol}%`;
    }
  }

  function syncSignalPathAmpNode() {
    const isExtAmpMode = Boolean(state.lockVolume100 && state.ampVolumeControlEnabled);
    if (dom.signalConnectorAmp) {
      dom.signalConnectorAmp.classList.toggle('hidden', !isExtAmpMode);
    }
    if (dom.signalNodeAmp) {
      dom.signalNodeAmp.classList.toggle('hidden', !isExtAmpMode);
    }
    if (!isExtAmpMode) return;

    const brand = state.ampBrandName || (IS_EN ? 'Amplifier' : 'Усилитель');
    const maxVol = Math.max(1, Math.min(100, Number(state.ampMaxVolume) || 80));
    const vol = Math.max(0, Math.min(maxVol, Number(state.volume) || 0));

    if (dom.signalAmpDot) {
      dom.signalAmpDot.classList.toggle('active', Boolean(state.ampConnected));
    }
    if (dom.signalAmpName) {
      dom.signalAmpName.textContent = brand;
    }
    if (dom.signalAmpVolumeBadge) {
      dom.signalAmpVolumeBadge.textContent = state.ampMuted ? 'MUTE' : `${vol}%`;
    }
    if (dom.signalAmpDetails) {
      let scNote = '';
      if (state.ampSoundCheckEnabled && state.ampSoundCheckGainDb !== null && state.ampSoundCheckGainDb !== undefined && !isNaN(state.ampSoundCheckGainDb)) {
        const gainVal = Number(state.ampSoundCheckGainDb);
        const gainSign = gainVal >= 0 ? '+' : '';
        const offVal = Number(state.ampSoundCheckOffset) || 0;
        const offSign = offVal >= 0 ? '+' : '';
        const baseVol = state.ampBaseVolume !== undefined ? Number(state.ampBaseVolume) : vol;
        scNote = IS_EN
          ? ` • SoundCheck ${gainSign}${gainVal.toFixed(1)} dB (${offSign}${offVal}%, base ${baseVol}%)`
          : ` • SoundCheck ${gainSign}${gainVal.toFixed(1)} дБ (${offSign}${offVal}%, база ${baseVol}%)`;
      } else if (state.ampSoundCheckEnabled) {
        scNote = IS_EN ? ' • SoundCheck iTunNORM' : ' • SoundCheck iTunNORM';
      }
      dom.signalAmpDetails.textContent = state.ampConnected
        ? (IS_EN ? `TCP Volume Control • Cap ${maxVol}%${scNote}` : `Управление громкостью по TCP • Лимит до ${maxVol}%${scNote}`)
        : (IS_EN ? `Waiting for TCP connection • Cap ${maxVol}%${scNote}` : `Ожидание подключения по TCP • Лимит до ${maxVol}%${scNote}`);
    }
  }

  function renderVolumeUI() {
    const isExtAmpMode = Boolean(state.lockVolume100 && state.ampVolumeControlEnabled);
    const isDlnaHardwareVol = Boolean(state.isDlnaActive && !state.lockVolume100 && !isExtAmpMode);
    syncSignalPathAmpNode();

    if (state.lockVolume100 && !isExtAmpMode) {
      if (dom.volumeSection) dom.volumeSection.classList.add('hidden');
      if (dom.standbyVolumeSection) dom.standbyVolumeSection.classList.add('hidden');
      if (dom.playerBottomNotice) {
        dom.playerBottomNotice.textContent = state.isDlnaActive
          ? translateTextToEn('Сетевой вывод BluOS / DLNA (Bit-Perfect PCM • 100%)')
          : translateTextToEn('Прямой вывод CoreAudio (Bit-Perfect DAC • 100%)');
      }
      return;
    }

    if (dom.volumeSection) dom.volumeSection.classList.remove('hidden');
    if (dom.standbyVolumeSection) dom.standbyVolumeSection.classList.remove('hidden');

    if (isExtAmpMode) {
      const brand = state.ampBrandName || 'AMP';
      const maxVol = Math.max(1, Math.min(100, Number(state.ampMaxVolume) || 80));
      const vol = Math.max(0, Math.min(maxVol, Number(state.volume) || 0));
      const pct = Math.max(0, Math.min(100, (vol / maxVol) * 100));
      const labelStr = state.ampMuted ? `${brand} • MUTE` : `${brand} • ${vol}%`;

      if (dom.playerBottomNotice) {
        let scBadge = '';
        if (state.ampSoundCheckEnabled && state.ampSoundCheckGainDb !== null && state.ampSoundCheckGainDb !== undefined && !isNaN(state.ampSoundCheckGainDb)) {
          const g = Number(state.ampSoundCheckGainDb);
          scBadge = ` • SoundCheck ${g >= 0 ? '+' : ''}${g.toFixed(1)} дБ`;
        }
        dom.playerBottomNotice.textContent = state.ampConnected
          ? `Прямой вывод CoreAudio (Bit-Perfect 100% • Громкость: ${brand} TCP • макс. ${maxVol}%${scBadge})`
          : `Прямой вывод CoreAudio (Bit-Perfect 100% • Ожидание ${brand} TCP${scBadge})`;
      }
      if (dom.volumeInput) {
        dom.volumeInput.min = '0';
        dom.volumeInput.max = String(maxVol);
        if (!state.isDraggingVolume) {
          dom.volumeInput.value = String(vol);
        }
      }
      if (!state.isDraggingVolume) {
        if (dom.volumeTrackFill) {
          dom.volumeTrackFill.style.width = `${pct}%`;
        }
        if (dom.volumeThumb) {
          dom.volumeThumb.style.left = `${pct}%`;
        }
        if (dom.volumeLevelText) {
          dom.volumeLevelText.textContent = labelStr;
        }
      }
      if (dom.standbyVolumeInput) {
        dom.standbyVolumeInput.min = '0';
        dom.standbyVolumeInput.max = String(maxVol);
        if (!state.isDraggingVolume) {
          dom.standbyVolumeInput.value = String(vol);
        }
      }
      if (!state.isDraggingVolume) {
        updateStandbyLoupePosition(vol, pct, Boolean(state.ampMuted));
        if (dom.standbyVolumeText) {
          dom.standbyVolumeText.textContent = labelStr;
        }
        if (dom.standbyBtnVolumeMute) {
          dom.standbyBtnVolumeMute.classList.toggle('muted', Boolean(state.ampMuted || vol === 0));
        }
        updateVolumeIcon(state.ampMuted ? 0 : Math.round(pct));
      }
    } else {
      const labelStr = `${state.volume}%`;
      if (dom.playerBottomNotice) {
        dom.playerBottomNotice.textContent = isDlnaHardwareVol
          ? 'Сетевой вывод BluOS / DLNA (Bit-Perfect PCM 100% • Аппаратная громкость плеера)'
          : 'Прямой вывод CoreAudio (Регулируемая громкость)';
      }
      if (dom.volumeInput) {
        dom.volumeInput.max = '100';
        if (!state.isDraggingVolume) {
          dom.volumeInput.value = String(state.volume);
        }
      }
      if (!state.isDraggingVolume) {
        if (dom.volumeTrackFill) {
          dom.volumeTrackFill.style.width = `${state.volume}%`;
        }
        if (dom.volumeThumb) {
          dom.volumeThumb.style.left = `${state.volume}%`;
        }
        if (dom.volumeLevelText) {
          dom.volumeLevelText.textContent = labelStr;
        }
      }
      if (dom.standbyVolumeInput) {
        dom.standbyVolumeInput.min = '0';
        dom.standbyVolumeInput.max = '100';
        if (!state.isDraggingVolume) {
          dom.standbyVolumeInput.value = String(state.volume);
        }
      }
      if (!state.isDraggingVolume) {
        updateStandbyLoupePosition(state.volume, state.volume, state.volume === 0);
        if (dom.standbyVolumeText) {
          dom.standbyVolumeText.textContent = labelStr;
        }
        if (dom.standbyBtnVolumeMute) {
          dom.standbyBtnVolumeMute.classList.toggle('muted', state.volume === 0);
        }
        updateVolumeIcon(state.volume);
      }
    }
  }

  function updateVolumeIcon(vol) {
    const wave1 = dom.volumeSection ? dom.volumeSection.querySelector('#vol-wave-1') : null;
    const wave2 = dom.volumeSection ? dom.volumeSection.querySelector('#vol-wave-2') : null;
    const sbWave1 = document.getElementById('standby-vol-wave-1');
    const sbWave2 = document.getElementById('standby-vol-wave-2');
    const show1 = vol > 0 ? 'block' : 'none';
    const show2 = vol >= 50 ? 'block' : 'none';
    if (wave1) wave1.style.display = show1;
    if (wave2) wave2.style.display = show2;
    if (sbWave1) sbWave1.style.display = show1;
    if (sbWave2) sbWave2.style.display = show2;
  }

  // --- Tactile & Haptic Engine (Mobile Vibration API Only — Zero Audio/DAC Pulses) ---
  function triggerHaptic(type = 'light') {
    if (
      'vibrate' in navigator &&
      typeof navigator.vibrate === 'function' &&
      (navigator.maxTouchPoints || 0) > 0 &&
      window.matchMedia &&
      window.matchMedia('(hover: none) and (pointer: coarse)').matches
    ) {
      try {
        if (type === 'light') navigator.vibrate(15);
        else if (type === 'medium') navigator.vibrate(28);
        else if (type === 'heavy') navigator.vibrate(45);
        else if (type === 'toggle') navigator.vibrate([15, 30, 25]);
      } catch (e) {}
    }
  }

  // --- Silent Audio Loop for iOS Background & Lock Screen Keep-Alive ---
  let silentAudioEl = null;
  let silentAudioUnlocked = false;
  let mediaSessionHandlersBound = false;
  let mediaSessionPlatformActivated = false;
  let allowAmrMediaSessionMutation = false;

  if (typeof navigator !== 'undefined' && 'mediaSession' in navigator && navigator.mediaSession) {
    try {
      const msProto = Object.getPrototypeOf(navigator.mediaSession);
      const msTarget = (msProto && typeof msProto.setActionHandler === 'function') ? msProto : navigator.mediaSession;
      const nativeSetActionHandler = msTarget.setActionHandler;
      if (typeof nativeSetActionHandler === 'function' && !nativeSetActionHandler._amrGuarded) {
        const guardedSetActionHandler = function (action, handler) {
          if (!allowAmrMediaSessionMutation) return;
          return nativeSetActionHandler.call(this, action, handler);
        };
        guardedSetActionHandler._amrGuarded = true;
        msTarget.setActionHandler = guardedSetActionHandler;
      }
    } catch (_) {}
  }

  function isLockScreenAllowedNow() {
    if (!state.lockScreenControls) return false;
    if (state.deviceAuthChecked && !state.deviceAuthorized) return false;
    return true;
  }

  function attachSilentAudioListeners(el) {
    if (!el || el._amrListenersAttached) return;
    el._amrListenersAttached = true;

    let flushedAfterPlayingAdvance = false;

    const onAudioStateChange = (evt) => {
      if (evt && evt.type === 'playing') {
        flushedAfterPlayingAdvance = false;
      }
      if (!isLockScreenAllowedNow()) return;
      setupMediaSession(true);
      updateMediaSession();
    };

    ['play', 'playing', 'pause', 'canplay', 'loadedmetadata', 'seeked'].forEach((evt) => {
      el.addEventListener(evt, onAudioStateChange, { passive: true });
    });

    // Once silent audio actually advances past 50ms, WebKit's GPUProcess::recomputeNowPlayingOwner
    // seats this page via becomeNowPlayingOwner — flush supported commands across RunLoop turns right then.
    el.addEventListener('timeupdate', () => {
      if (!flushedAfterPlayingAdvance && !el.paused && el.currentTime >= 0.05) {
        flushedAfterPlayingAdvance = true;
        if (isLockScreenAllowedNow()) {
          setupMediaSession(true);
          updateMediaSession();
        }
      }
    }, { passive: true });

    const handleSilentAudioError = () => {
      const curSrc = el.getAttribute('src') || '';
      if (curSrc.includes('silence.m4a') && !el._amrWavFallbackTried) {
        el._amrWavFallbackTried = true;
        el.src = '/assets/silence.wav?v=5';
        try { el.load(); } catch (_) {}
        if (state.playerState === 'playing' && isLockScreenAllowedNow()) {
          try {
            const p = el.play();
            if (p !== undefined) p.catch(() => {});
          } catch (_) {}
        }
      }
    };

    el.addEventListener('error', handleSilentAudioError, { passive: true });
    if (el.error) {
      handleSilentAudioError();
    }
  }

  function initSilentAudio() {
    if (!isLockScreenAllowedNow()) {
      return null;
    }
    if (!silentAudioEl) {
      silentAudioEl = document.getElementById('bg-silent-audio');
    }
    if (!silentAudioEl) {
      silentAudioEl = document.createElement('audio');
      silentAudioEl.id = 'bg-silent-audio';
      silentAudioEl.loop = true;
      silentAudioEl.setAttribute('playsinline', '');
      silentAudioEl.setAttribute('webkit-playsinline', '');
      silentAudioEl.setAttribute('x-webkit-airplay', 'deny');
      silentAudioEl.preload = 'auto';
      silentAudioEl.style.cssText = 'position:fixed;bottom:0;left:0;width:1px;height:1px;opacity:0.001;pointer-events:none;z-index:-1;';
      attachSilentAudioListeners(silentAudioEl);
      silentAudioEl.src = '/assets/silence.m4a?v=4';
      document.body.appendChild(silentAudioEl);
    } else {
      silentAudioEl.preload = 'auto';
      silentAudioEl.setAttribute('x-webkit-airplay', 'deny');
      attachSilentAudioListeners(silentAudioEl);
      if (!silentAudioEl.getAttribute('src') && !silentAudioEl.querySelector('source')) {
        silentAudioEl._amrWavFallbackTried = false;
        silentAudioEl.src = '/assets/silence.m4a?v=4';
      }
    }
    return silentAudioEl;
  }

  function teardownMediaSessionAndSilentAudio() {
    const el = silentAudioEl || document.getElementById('bg-silent-audio');
    if (el) {
      try {
        if (!el.paused) {
          el.pause();
        }
        el.currentTime = 0;
        // Keep src intact so HTMLMediaElement retains HAVE_ENOUGH_DATA and iOS gesture blessing.
      } catch (e) {}
    }
    mediaSessionHandlersBound = false;
    mediaSessionPlatformActivated = false;
    lastMediaSessionKey = '';

    if ('mediaSession' in navigator) {
      allowAmrMediaSessionMutation = true;
      try {
        navigator.mediaSession.playbackState = 'none';
        navigator.mediaSession.metadata = null;
        ['play', 'pause', 'previoustrack', 'nexttrack', 'seekto', 'seekbackward', 'seekforward', 'stop'].forEach((act) => {
          try { navigator.mediaSession.setActionHandler(act, null); } catch (e) {}
        });
      } catch (e) {
      } finally {
        allowAmrMediaSessionMutation = false;
      }
    }
  }

  function syncSilentAudio(isPlaying) {
    if (!isLockScreenAllowedNow()) {
      teardownMediaSessionAndSilentAudio();
      return;
    }
    const el = initSilentAudio();
    if (!el) return;

    if (isPlaying) {
      if (el.paused) {
        const p = el.play();
        if (p !== undefined) {
          p.then(() => {
            silentAudioUnlocked = true;
            removeUnlockAudioGestureListeners();
            setupMediaSession(true);
            updateMediaSession();
            setTimeout(() => {
              if (isLockScreenAllowedNow()) {
                setupMediaSession(true);
              }
            }, 120);
            setTimeout(() => {
              if (isLockScreenAllowedNow()) {
                setupMediaSession(true);
              }
            }, 450);
          }).catch((err) => {
            console.warn('[AudioKeepAlive] play error:', err);
          });
        }
      } else {
        setupMediaSession(true);
      }
    } else if (!el.paused) {
      el.pause();
    }
  }

  const UNLOCK_GESTURE_EVENTS = ['touchend', 'pointerup', 'click'];
  let unlockGestureListenersBound = false;

  function removeUnlockAudioGestureListeners() {
    if (!unlockGestureListenersBound) return;
    unlockGestureListenersBound = false;
    UNLOCK_GESTURE_EVENTS.forEach(evt => {
      window.removeEventListener(evt, unlockAudioOnUserGesture);
    });
  }

  function bindUnlockAudioGestureListeners() {
    if (unlockGestureListenersBound || silentAudioUnlocked) return;
    unlockGestureListenersBound = true;
    UNLOCK_GESTURE_EVENTS.forEach(evt => {
      window.addEventListener(evt, unlockAudioOnUserGesture, { passive: true });
    });
  }

  // Unlock silent keep-alive audio on user activation (even before WebSocket auth finishes)
  function unlockAudioOnUserGesture() {
    if (!isLockScreenAllowedNow()) {
      return;
    }

    if (silentAudioUnlocked) {
      removeUnlockAudioGestureListeners();
      return;
    }

    const el = initSilentAudio();
    if (!silentAudioUnlocked && el) {
      const p = el.play();
      if (p !== undefined) {
        p.then(() => {
          silentAudioUnlocked = true;
          removeUnlockAudioGestureListeners();
          setupMediaSession(true);
          updateMediaSession();
          setTimeout(() => {
            const shouldPlay = state.playerState === 'playing' || Date.now() < (state.pendingPlayUntil || 0);
            if (!shouldPlay && !el.paused) {
              el.pause();
            }
            if (isLockScreenAllowedNow()) {
              setupMediaSession(true);
            }
          }, 160);
        }).catch(() => {});
      }
    }
  }

  bindUnlockAudioGestureListeners();

  // Re-bind MediaSession on BOTH screen lock (document.hidden === true, when WebKit enables NowPlaying visibility) and wake/unlock
  ['visibilitychange', 'pagehide', 'pageshow', 'focus'].forEach((evt) => {
    window.addEventListener(evt, () => {
      if (isLockScreenAllowedNow()) {
        setupMediaSession(true);
        updateMediaSession();
      }
    }, { passive: true });
  });

  // Global tactile feedback on all interactive elements
  let lastGlobalHapticTime = 0;
  document.addEventListener('pointerup', (e) => {
    const now = Date.now();
    if (now - lastGlobalHapticTime < 80) return;
    const target = e.target.closest('button, .track-row, .tv-queue-row, .playlist-card, .hero-card, .station-card, .media-card, .genre-card, .tab-item, .nav-btn, .search-chip, .quality-badge, .pill, .mini-btn, .mini-player-content');
    if (target) {
      lastGlobalHapticTime = now;
      triggerHaptic('light');
    }
  }, { passive: true });

  // Track iPhone Landscape StandBy media query (strictly matching CSS 12-landscape-controls-and-booklet.css)
  const standbyLandscapeMq = (typeof window !== 'undefined' && typeof window.matchMedia === 'function')
    ? window.matchMedia('(max-height: 540px) and (min-width: 568px) and (orientation: landscape) and (hover: none) and (pointer: coarse)')
    : null;

  function syncStandbyLandscapeBodyClass() {
    const isLandscapeStandby = Boolean(standbyLandscapeMq && standbyLandscapeMq.matches && !document.body.classList.contains('keyboard-open'));
    document.body.classList.toggle('standby-landscape-open', isLandscapeStandby);
    if (isLandscapeStandby && typeof closeStandbyQueueModal === 'function') {
      closeStandbyQueueModal();
    }
  }

  if (standbyLandscapeMq) {
    syncStandbyLandscapeBodyClass();
    const onStandbyMqChange = () => {
      syncStandbyLandscapeBodyClass();
      ensureScrubberLoopRunning();
      if (typeof syncActiveMotionVideoTarget === 'function') syncActiveMotionVideoTarget();
      if (typeof syncSpectralPolling === 'function') syncSpectralPolling();
    };
    if (typeof standbyLandscapeMq.addEventListener === 'function') {
      standbyLandscapeMq.addEventListener('change', onStandbyMqChange);
    } else if (typeof standbyLandscapeMq.addListener === 'function') {
      standbyLandscapeMq.addListener(onStandbyMqChange);
    }
  }

  // Track text-input keyboard focus so landscape TV Mode does not hide when buttons/sliders receive focus
  const TEXT_ENTRY_SELECTOR = 'input[type="text"], input[type="search"], input[type="url"], input[type="number"], input:not([type]), textarea, [contenteditable="true"]';
  function syncKeyboardFocusClass() {
    const el = document.activeElement;
    const isTextFocused = Boolean(
      el &&
      el !== document.body &&
      typeof el.matches === 'function' &&
      el.matches(TEXT_ENTRY_SELECTOR) &&
      el.isConnected &&
      !el.disabled &&
      !el.readOnly &&
      el.getClientRects().length > 0
    );
    const hadClass = document.body.classList.contains('keyboard-open');
    document.body.classList.toggle('keyboard-open', isTextFocused);
    syncStandbyLandscapeBodyClass();
    if (hadClass !== isTextFocused) {
      ensureScrubberLoopRunning();
      if (typeof syncActiveMotionVideoTarget === 'function') syncActiveMotionVideoTarget();
      if (typeof syncSpectralPolling === 'function') syncSpectralPolling();
    }
  }
  function blurFocusedInContainer(container) {
    if (container && document.activeElement && container.contains(document.activeElement) && typeof document.activeElement.blur === 'function') {
      document.activeElement.blur();
    }
    syncKeyboardFocusClass();
  }
  document.addEventListener('focusin', syncKeyboardFocusClass, { passive: true });
  document.addEventListener('focusout', () => {
    setTimeout(syncKeyboardFocusClass, 0);
  }, { passive: true });
