  // --- MediaSession (Lock Screen, Dynamic Island, AirPods, Control Center) ---
  let lastMediaSessionKey = '';

  const msPlayHandler = () => {
    triggerHaptic('medium');
    syncSilentAudio(true);
    optimisticPlay();
    updateMediaSession();
    send({ action: 'play' });
  };

  const msPauseHandler = () => {
    triggerHaptic('medium');
    syncSilentAudio(false);
    state.pendingPlayUntil = 0;
    state.pendingPauseUntil = Date.now() + 2500;
    const now = performance.now();
    if (state.playerState === 'playing' && state.duration > 0) {
      state.lastSyncPos = Math.min(state.duration, state.lastSyncPos + Math.max(0, (now - state.lastSyncTime) / 1000));
      state.position = state.lastSyncPos;
    }
    state.lastSyncTime = now;
    state.lastSyncPerf = now;
    state.playerState = 'paused';
    state.playbackState = 'paused';
    renderNowPlaying();
    updateMediaSession();
    send({ action: 'pause' });
  };

  const keepSilentAudioAliveForTrackSkip = () => {
    if (!isLockScreenAllowedNow()) return;
    const el = initSilentAudio();
    if (el && el.paused) {
      try {
        const p = el.play();
        if (p !== undefined) {
          p.then(() => {
            silentAudioUnlocked = true;
            setTimeout(() => {
              const shouldPlay = state.playerState === 'playing' || Date.now() < (state.pendingPlayUntil || 0);
              if (!shouldPlay && !el.paused) {
                el.pause();
              }
            }, 1200);
          }).catch(() => {});
        }
      } catch (_) {}
    }
  };

  const msPrevHandler = () => {
    triggerHaptic('medium');
    keepSilentAudioAliveForTrackSkip();
    sendThrottledTransport('previous');
  };

  const msNextHandler = () => {
    triggerHaptic('medium');
    keepSilentAudioAliveForTrackSkip();
    sendThrottledTransport('next');
  };

  const msSeekToHandler = (details) => {
    if (details && details.seekTime != null && !isNaN(details.seekTime)) {
      triggerHaptic('light');
      sendSeek(details.seekTime);
    }
  };

  const msStopHandler = () => {
    triggerHaptic('medium');
    syncSilentAudio(false);
    state.pendingPlayUntil = 0;
    state.playerState = 'stopped';
    state.playbackState = 'stopped';
    state.lastSyncPos = 0;
    state.position = 0;
    state.lastSyncTime = performance.now();
    state.lastSyncPerf = state.lastSyncTime;
    renderNowPlaying();
    updateMediaSession();
    send({ action: 'stop' });
  };

  function ensureMediaSessionPlatformActive(isPlaying) {
    if (!('mediaSession' in navigator) || !navigator.mediaSession) return;
    try {
      if (!mediaSessionPlatformActivated) {
        // WebKit C++ (NowPlayingManager.cpp:130, MediaSession.cpp:292):
        // m_remoteCommandListener is nullptr until playbackState = 'playing' activates
        // m_platformSession->setActive(true) -> MediaSessionManagerCocoa::addSession().
        navigator.mediaSession.playbackState = 'playing';
        mediaSessionPlatformActivated = true;
      }
      navigator.mediaSession.playbackState = isPlaying ? 'playing' : 'paused';
    } catch (_) {}
  }

  let mediaSessionCommandFlushTimer = null;
  let mediaSessionFlushStopToggle = false;

  function applyCoreMediaSessionActionHandlers(includeStopHandler) {
    allowAmrMediaSessionMutation = true;
    try {
      // Ensure WebKit RemoteCommandListenerCocoa registers ONLY Play, Pause, PreviousTrack,
      // NextTrack, and SeekToPlaybackPosition — never defaultCommands() (±15s SkipForward/SkipBackward).
      try { navigator.mediaSession.setActionHandler('seekbackward', null); } catch (e) {}
      try { navigator.mediaSession.setActionHandler('seekforward', null); } catch (e) {}
      navigator.mediaSession.setActionHandler('play', msPlayHandler);
      navigator.mediaSession.setActionHandler('pause', msPauseHandler);
      navigator.mediaSession.setActionHandler('previoustrack', msPrevHandler);
      navigator.mediaSession.setActionHandler('nexttrack', msNextHandler);
      navigator.mediaSession.setActionHandler('seekto', msSeekToHandler);
      try { navigator.mediaSession.setActionHandler('stop', includeStopHandler ? msStopHandler : null); } catch (e) {}
      mediaSessionHandlersBound = true;
    } catch (err) {
      console.warn('[MediaSession] Handler setup:', err);
    } finally {
      allowAmrMediaSessionMutation = false;
    }
  }

  function setupMediaSession(forceFlush = true) {
    if (!('mediaSession' in navigator)) return;
    if (!isLockScreenAllowedNow()) {
      teardownMediaSessionAndSilentAudio();
      return;
    }

    initSilentAudio();
    ensureMediaSessionPlatformActive(state.playerState === 'playing');

    if (forceFlush) {
      // WebKit RemoteCommandListener.cpp:81 + RemoteRemoteCommandListener.cpp:92 coalesces synchronous
      // remove+add within the same JS turn and early-returns if m_currentCommands == supportedCommands.
      // Toggling StopCommand across two separate RunLoop turns forces UpdateSupportedCommands IPC to GPUProcess
      // without ever dropping PreviousTrackCommand or NextTrackCommand for even a single frame.
      mediaSessionFlushStopToggle = !mediaSessionFlushStopToggle;
      applyCoreMediaSessionActionHandlers(mediaSessionFlushStopToggle);
      if (mediaSessionCommandFlushTimer) {
        clearTimeout(mediaSessionCommandFlushTimer);
      }
      mediaSessionCommandFlushTimer = setTimeout(() => {
        mediaSessionCommandFlushTimer = null;
        if (!('mediaSession' in navigator) || !isLockScreenAllowedNow()) return;
        mediaSessionFlushStopToggle = false;
        applyCoreMediaSessionActionHandlers(false);
      }, 45);
    } else {
      applyCoreMediaSessionActionHandlers(false);
    }
  }

  function updateMediaSession() {
    if (!('mediaSession' in navigator)) return;
    if (!isLockScreenAllowedNow()) {
      teardownMediaSessionAndSilentAudio();
      return;
    }

    const isPlaying = state.playerState === 'playing';
    ensureMediaSessionPlatformActive(isPlaying);
    syncSilentAudio(isPlaying);
    setupMediaSession(false);

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
        setupMediaSession(true);
      } catch (e) {
        console.warn('[MediaSession] Metadata update error:', e);
      }
    }

    if ('setPositionState' in navigator.mediaSession) {
      try {
        // WebKit MediaSession::setPositionState (MediaSession.cpp:459) throws TypeError if playbackRate == 0;
        // WebKit automatically computes actualPlaybackRate = (playbackState == Playing ? playbackRate : 0).
        if (state.duration > 0) {
          const nowPerf = performance.now();
          const syncBase = state.lastSyncPerf || state.lastSyncTime || nowPerf;
          const livePos = (state.lastSyncPos || 0) + (isPlaying ? Math.max(0, (nowPerf - syncBase) / 1000) : 0);
          const curPos = Math.min(Math.max(0, livePos), state.duration);
          navigator.mediaSession.setPositionState({
            duration: Math.max(state.duration, 0.1),
            playbackRate: 1.0,
            position: curPos
          });
        } else {
          navigator.mediaSession.setPositionState({
            duration: 240,
            playbackRate: 1.0,
            position: 0
          });
        }
      } catch (e) {}
    }
  }

  function cleanAudioQualityLabel(raw) {
    if (!raw) return 'LOSSLESS';
    const up = raw.toUpperCase();
    if (up.includes('ОЖИДАНИЕ CDN')) return IS_EN ? 'CDN TIMEOUT' : 'ОЖИДАНИЕ CDN';
    if (up.includes('БУФЕРИЗАЦИЯ')) return IS_EN ? 'BUFFERING…' : 'БУФЕРИЗАЦИЯ…';
    if (up.includes('ОПРЕДЕЛЕНИЕ')) return IS_EN ? 'DETECTING…' : 'ФОРМАТ…';
    if (up.includes('HI-RES')) return 'HI-RES LOSSLESS';
    if (up.includes('LOSSLESS')) return 'LOSSLESS';
    if (up.includes('AAC')) return 'AAC 256';
    if (up.includes('ALAC')) return 'ALAC LOSSLESS';
    return raw;
  }

  function formatDacPill(raw) {
    const up = String(raw || '').toUpperCase();
    if (state.isStreamStalled || up.includes('ОЖИДАНИЕ CDN') || up.includes('WAITING FOR APPLE MUSIC CDN')) {
      return IS_EN ? 'CDN Timeout • 0 kbps' : 'Ожидание CDN • 0 кбит/с';
    }
    if (state.isBuffering || up.includes('ЗАПУСК ИЗ ОБЛАКА') || up.includes('STARTING CLOUD STREAM') || up.includes('БУФЕРИЗАЦИЯ') || up.includes('BUFFERING STREAM')) {
      return IS_EN ? 'Starting Cloud Stream…' : 'Запуск из облака…';
    }
    if (up.includes('ОПРЕДЕЛЕНИЕ') || up.includes('DETECTING FORMAT')) {
      return IS_EN ? 'Detecting Format…' : 'Определение формата…';
    }
    if ((state.dspMode === 'sdm_dop' || state.dspMode === 'hq_nos_pcm') && state.dspBadge) {
      return state.dspBadge;
    }
    if (!raw) return 'Bit-Perfect DAC';
    if (up.includes('192')) return 'Bit-Perfect • 192 kHz / 24-bit';
    if (up.includes('96')) return 'Bit-Perfect • 96 kHz / 24-bit';
    if (up.includes('48')) return 'Lossless • 48 kHz / 24-bit';
    if (up.includes('44.1')) return 'Lossless • 44.1 kHz / 16-bit';
    if (up.includes('HI-RES')) return 'Hi-Res Lossless Bit-Perfect';
    if (up.includes('LOSSLESS') || up.includes('ALAC')) return 'Lossless Bit-Perfect';
    if (up.includes('AAC')) return 'AAC • 256 kbps';
    return raw;
  }

  let cachedSbFill = null;
  let cachedSbThumb = null;
  let cachedSbInput = null;
  let cachedSbElapsed = null;
  let cachedSbRemaining = null;
  let lastRenderedElapsedStr = '';
  let lastRenderedRemStr = '';
  let lastScrubberFrameMs = 0;

  function updateScrubberUI(currentPos, totalDur) {
    if (!cachedSbFill) cachedSbFill = document.getElementById('standby-progress-fill');
    if (!cachedSbThumb) cachedSbThumb = document.getElementById('standby-progress-thumb');
    if (!cachedSbInput) cachedSbInput = document.getElementById('standby-progress-input');
    if (!cachedSbElapsed) cachedSbElapsed = document.getElementById('standby-time-elapsed');
    if (!cachedSbRemaining) cachedSbRemaining = document.getElementById('standby-time-remaining');

    if (totalDur <= 0) {
      dom.scrubberFill.style.width = '0%';
      dom.scrubberThumb.style.left = '0%';
      dom.miniProgressFill.style.width = '0%';
      if (lastRenderedElapsedStr !== '0:00') {
        lastRenderedElapsedStr = '0:00';
        dom.timeElapsed.textContent = '0:00';
        if (cachedSbElapsed) cachedSbElapsed.textContent = '0:00';
      }
      if (lastRenderedRemStr !== '-0:00') {
        lastRenderedRemStr = '-0:00';
        dom.timeRemaining.textContent = '-0:00';
        if (cachedSbRemaining) cachedSbRemaining.textContent = '-0:00';
      }
      dom.scrubberInput.value = 0;
      if (cachedSbFill) cachedSbFill.style.width = '0%';
      if (cachedSbThumb) cachedSbThumb.style.left = '0%';
      if (cachedSbInput) cachedSbInput.value = 0;
      return;
    }

    const clampedPos = Math.max(0, Math.min(currentPos, totalDur));
    const percent = (clampedPos / totalDur) * 100;
    const pctStr = `${percent.toFixed(2)}%`;
    const tvVisible = isStandbyOrLandscapeVisible();

    if (tvVisible) {
      if (cachedSbFill) cachedSbFill.style.width = pctStr;
      if (cachedSbThumb) cachedSbThumb.style.left = pctStr;
      if (cachedSbInput && !state.isScrubbing) cachedSbInput.value = percent;
    } else {
      dom.scrubberFill.style.width = pctStr;
      dom.scrubberThumb.style.left = pctStr;
      dom.miniProgressFill.style.width = pctStr;
      dom.scrubberInput.value = percent;
      if (cachedSbFill) cachedSbFill.style.width = pctStr;
      if (cachedSbThumb) cachedSbThumb.style.left = pctStr;
      if (cachedSbInput && !state.isScrubbing) cachedSbInput.value = percent;
    }

    const elapsedStr = formatTime(clampedPos);
    const remaining = totalDur - clampedPos;
    const remStr = `-${formatTime(remaining)}`;
    if (elapsedStr !== lastRenderedElapsedStr) {
      lastRenderedElapsedStr = elapsedStr;
      dom.timeElapsed.textContent = elapsedStr;
      if (cachedSbElapsed) cachedSbElapsed.textContent = elapsedStr;
    }
    if (remStr !== lastRenderedRemStr) {
      lastRenderedRemStr = remStr;
      dom.timeRemaining.textContent = remStr;
      if (cachedSbRemaining) cachedSbRemaining.textContent = remStr;
    }
  }

  let lastLoadingPillKey = '';
  let lastLoadingTickCheckMs = 0;

  function syncTrackLoadingIndicatorUI() {
    const isPlaying = state.playerState === 'playing';
    const isCloudLoading = Boolean(isPlaying && state.isBuffering);
    const elapsedLoadingMs = state.loadingStartedAtMs ? Math.max(0, Date.now() - state.loadingStartedAtMs) : 0;
    const showLoadingUI = isCloudLoading && elapsedLoadingMs >= 200;
    const showShimmer = isCloudLoading;

    let statusText = '';
    if (showLoadingUI) {
      if (state.isStreamStalled) {
        statusText = IS_EN ? 'Waiting for Apple Music CDN…' : 'Ожидание CDN Apple Music…';
      } else {
        statusText = IS_EN ? 'Starting Cloud Stream…' : 'Запуск из облака…';
      }
    }

    const t = state.track;
    const miniText = t ? (t.artist || 'Apple Music') : 'Apple Music';

    const renderKey = `${showLoadingUI ? 1 : 0}|${showShimmer ? 1 : 0}|${statusText}|${miniText}`;
    if (renderKey === lastLoadingPillKey) {
      return;
    }
    lastLoadingPillKey = renderKey;

    if (dom.playerLoadingStatus) {
      dom.playerLoadingStatus.classList.toggle('hidden', !showLoadingUI);
      dom.playerLoadingStatus.classList.remove('is-buffer');
    }
    if (dom.playerLoadingText && statusText) {
      dom.playerLoadingText.textContent = statusText;
    }
    if (dom.standbyLoadingStatus) {
      dom.standbyLoadingStatus.classList.toggle('hidden', !showLoadingUI);
      dom.standbyLoadingStatus.classList.remove('is-buffer');
    }
    if (dom.standbyLoadingText && statusText) {
      dom.standbyLoadingText.textContent = statusText;
    }

    if (dom.scrubberContainer) {
      dom.scrubberContainer.classList.toggle('is-loading-stream', showShimmer);
      dom.scrubberContainer.classList.remove('is-buffer-staging');
    }
    if (dom.miniProgressTrack) {
      dom.miniProgressTrack.classList.toggle('is-loading-stream', showShimmer);
      dom.miniProgressTrack.classList.remove('is-buffer-staging');
    }
    const sbTrack = dom.standbyProgressTrack || document.getElementById('standby-progress-track');
    if (sbTrack) {
      sbTrack.classList.toggle('is-loading-stream', showShimmer);
      sbTrack.classList.remove('is-buffer-staging');
    }

    if (dom.btnPlayPause) {
      dom.btnPlayPause.classList.toggle('is-loading-ring', showLoadingUI);
      dom.btnPlayPause.classList.remove('is-buffer-ring');
    }
    if (dom.miniBtnPlayPause) {
      dom.miniBtnPlayPause.classList.toggle('is-loading-ring', showLoadingUI);
      dom.miniBtnPlayPause.classList.remove('is-buffer-ring');
    }
    const sbPlayBtn = dom.standbyBtnPlayPause || document.getElementById('standby-btn-play-pause');
    if (sbPlayBtn) {
      sbPlayBtn.classList.toggle('is-loading-ring', showLoadingUI);
      sbPlayBtn.classList.remove('is-buffer-ring');
    }

    if (dom.audioQualityBadge) {
      dom.audioQualityBadge.classList.remove('is-loading-stream');
    }
    const sbDacBadge = document.getElementById('standby-dac-badge');
    if (sbDacBadge) {
      sbDacBadge.classList.remove('is-loading-stream');
    }

    if (dom.miniArtist) {
      dom.miniArtist.classList.remove('is-loading-stream');
      if (dom.miniArtist.textContent !== miniText) {
        dom.miniArtist.textContent = miniText;
      }
    }
  }

  // --- Optimistic Scrubber Loop (rAF normally when duration > 0; 250ms setInterval in StandBy/TV Mode) ---
  let scrubberRafId = 0;
  let standbyScrubberTimerId = null;

  function stopStandbyScrubberInterval() {
    if (standbyScrubberTimerId) {
      clearInterval(standbyScrubberTimerId);
      standbyScrubberTimerId = null;
    }
  }

  function stepScrubberFrame(tsFrame) {
    if ((state.isStagingBuffer || state.isBuffering) && (tsFrame - lastLoadingTickCheckMs >= 250)) {
      lastLoadingTickCheckMs = tsFrame;
      syncTrackLoadingIndicatorUI();
    }
    if (!state.isScrubbing && state.duration > 0) {
      const waitingForFirstAudioFrame = state.isBuffering || state.isStagingBuffer || (!state.hasStartedAdvancingForTrack && state.lastSyncPos <= 0.08);
      const deltaSec = waitingForFirstAudioFrame ? 0 : ((tsFrame - state.lastSyncTime) / 1000);
      const rawPos = state.lastSyncPos + deltaSec;
      const currentPos = Math.min(state.duration, rawPos);
      state.position = currentPos;
      updateScrubberUI(currentPos, state.duration);

      // If spectral data went stale (>1.2s) while RTA bars are still raised above floor, wake up RTA decay loop
      if (!standbyRtaRafId && (tsFrame - (state.lastSpectralUpdateAt || 0)) > 1200 && isStandbyOrLandscapeVisible()) {
        for (let i = 0; i < standbyRtaBarCount; i++) {
          if (standbyRtaCurrent[i] > 0.035 || standbyRtaTarget[i] > 0.035) {
            ensureStandbyRtaAnimLoop();
            break;
          }
        }
      }

      // Watchdog: if seek bar has been pinned at 100% for > 1.5s without a track transition event,
      // actively poll status & queue from the server to recover immediately.
      if (rawPos >= state.duration + 1.5 && state.connected && state.deviceAuthorized) {
        const nowWall = Date.now();
        if (nowWall - (state.lastEndOfTrackPollAt || 0) >= 2500) {
          state.lastEndOfTrackPollAt = nowWall;
          send({ action: 'get_status' });
          send({ action: 'get_queue' });
          send({
            action: 'client_log',
            params: {
              level: 'warn',
              message: `Scrubber pinned at 100% (${Math.round(state.duration)}s) for ${(rawPos - state.duration).toFixed(1)}s on track "${(state.track && state.track.name) || ''}" — polling status & queue`
            }
          });
          ensureStandbyRtaAnimLoop();
        }
      }
    }
  }

  function ensureScrubberLoopRunning() {
    const shouldAnimate = Boolean(state.connected && state.playerState === 'playing' && (state.duration > 0) && !document.hidden);
    if (!shouldAnimate) {
      if (scrubberRafId) {
        cancelAnimationFrame(scrubberRafId);
        scrubberRafId = 0;
      }
      stopStandbyScrubberInterval();
      return;
    }

    if (isStandbyOrLandscapeVisible()) {
      if (scrubberRafId) {
        cancelAnimationFrame(scrubberRafId);
        scrubberRafId = 0;
      }
      if (!standbyScrubberTimerId) {
        standbyScrubberTimerId = setInterval(() => {
          if (!state.connected || state.playerState !== 'playing' || !(state.duration > 0) || document.hidden || !isStandbyOrLandscapeVisible()) {
            stopStandbyScrubberInterval();
            ensureScrubberLoopRunning();
            return;
          }
          const ts = performance.now();
          lastScrubberFrameMs = ts;
          stepScrubberFrame(ts);
        }, 250);
      }
      return;
    }

    stopStandbyScrubberInterval();
    if (!scrubberRafId) {
      scrubberRafId = requestAnimationFrame(scrubberAnimationLoop);
    }
  }

  function scrubberAnimationLoop(nowMs) {
    scrubberRafId = 0;
    if (!state.connected || state.playerState !== 'playing' || !(state.duration > 0) || document.hidden) {
      return;
    }
    if (isStandbyOrLandscapeVisible()) {
      ensureScrubberLoopRunning();
      return;
    }
    const tsFrame = nowMs || performance.now();
    if (tsFrame - lastScrubberFrameMs >= 50) {
      lastScrubberFrameMs = tsFrame;
      stepScrubberFrame(tsFrame);
    }
    scrubberRafId = requestAnimationFrame(scrubberAnimationLoop);
  }
  ensureScrubberLoopRunning();

  // --- WebSocket Liveness, Ping/Pong Probe & Half-Open Watchdog ---
  function checkSocketLiveness(isResumeProbe = false) {
    if (document.hidden && !isResumeProbe) return;

    if (!socket || socket.readyState === WebSocket.CLOSED || socket.readyState === WebSocket.CLOSING) {
      if (isResumeProbe) {
        reconnectAttempt = 0;
        connectWebSocket();
      }
      return;
    }
    if (socket.readyState !== WebSocket.OPEN) return;

    const now = Date.now();
    const lastRx = state.lastServerMessageAt || now;
    const silenceMs = now - lastRx;

    if (state.pendingPingSentAt > 0) {
      if (lastRx >= state.pendingPingSentAt) {
        state.pendingPingSentAt = 0;
      } else if (now - state.pendingPingSentAt >= 4000) {
        state.pendingPingSentAt = 0;
        connectWebSocket();
        return;
      }
    }

    if (state.pendingPingSentAt === 0) {
      if (isResumeProbe && silenceMs >= 3000) {
        state.pendingPingSentAt = now;
        send({ action: 'ping' });
        if (state.deviceAuthorized) {
          send({ action: 'get_status' });
        }
        return;
      }
      if (silenceMs >= 15000) {
        state.pendingPingSentAt = now;
        send({ action: 'ping' });
        return;
      }
    }

    if (state.playerState === 'playing' && state.deviceAuthorized && silenceMs >= 4500 && state.pendingPingSentAt === 0) {
      send({ action: 'get_status' });
      send({ action: 'get_queue' });
      if (silenceMs >= 11000) {
        state.pendingPingSentAt = now;
        send({ action: 'ping' });
      }
    }
  }

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      ensureScrubberLoopRunning();
      checkSocketLiveness(true);
    } else {
      ensureScrubberLoopRunning();
    }
    syncSpectralPolling();
  });

  window.addEventListener('pageshow', () => {
    ensureScrubberLoopRunning();
    checkSocketLiveness(true);
  }, { passive: true });

  window.addEventListener('online', () => {
    reconnectAttempt = 0;
    checkSocketLiveness(true);
  }, { passive: true });

  setInterval(() => {
    checkSocketLiveness(false);
  }, 2000);

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
    state.isBuffering = false;
    state.isStagingBuffer = false;
    state.loadingStage = null;
    state.loadingStartedAtMs = 0;
    state.hasStartedAdvancingForTrack = targetPos > 0.08;
    state.lastSyncPos = targetPos;
    state.lastSyncTime = performance.now();
    state.lastSyncPerf = state.lastSyncTime;
    state.position = targetPos;
    updateScrubberUI(targetPos, state.duration);
    syncTrackLoadingIndicatorUI();
    send({
      action: 'seek',
      params: { position: targetPos }
    });
    updateMediaSession();
  }

  dom.scrubberInput.addEventListener('change', commitScrub);
  dom.scrubberInput.addEventListener('pointerup', commitScrub);
  dom.scrubberInput.addEventListener('touchend', commitScrub);
  dom.scrubberInput.addEventListener('pointercancel', commitScrub);
  dom.scrubberInput.addEventListener('touchcancel', commitScrub);

  // --- Transport Event Listeners ---
  function optimisticPlay() {
    state.pendingPauseUntil = 0;
    state.pendingPlayUntil = Date.now() + 3000;
    state.lastClientCommandAt = Date.now();
    state.lastSyncTime = performance.now();
    state.lastSyncPerf = state.lastSyncTime;
    state.playerState = 'playing';
    state.playbackState = 'playing';
    syncSilentAudio(true);
    renderNowPlaying();
    updateMediaSession();
  }

  function togglePlayPause(e) {
    if (e) {
      e.preventDefault();
      e.stopPropagation();
    }
    triggerHaptic('medium');
    const isPlaying = state.playerState === 'playing';
    if (isPlaying) {
      syncSilentAudio(false);
      state.pendingPlayUntil = 0;
      state.isBuffering = false;
      state.isStagingBuffer = false;
      state.loadingStage = null;
      state.loadingStartedAtMs = 0;
      const now = performance.now();
      state.lastSyncPos = Math.min(state.duration, state.lastSyncPos + (now - state.lastSyncTime) / 1000);
      state.position = state.lastSyncPos;
      state.lastSyncTime = now;
      state.lastSyncPerf = now;
      state.playerState = 'paused';
      state.playbackState = 'paused';
      renderNowPlaying();
      updateMediaSession();
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
