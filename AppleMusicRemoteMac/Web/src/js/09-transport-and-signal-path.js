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
    if (e.code !== 'Space') return;
    const tag = document.activeElement?.tagName;
    if (['INPUT', 'TEXTAREA', 'BUTTON', 'SELECT'].includes(tag) || document.activeElement?.isContentEditable) return;
    const authOverlay = document.getElementById('device-auth-overlay');
    if (authOverlay && !authOverlay.classList.contains('hidden')) return;
    if (dom.modalAppleAuth && !dom.modalAppleAuth.classList.contains('hidden')) return;
    e.preventDefault();
    togglePlayPause();
  });

  dom.btnNext.addEventListener('click', () => sendThrottledTransport('next'));
  dom.miniBtnNext.addEventListener('click', (e) => {
    e.stopPropagation();
    sendThrottledTransport('next');
  });

  dom.btnPrev.addEventListener('click', () => sendThrottledTransport('previous'));

  function normalizeRepeatMode(val) {
    const m = String(val || '').trim().toLowerCase();
    if (m === 'one' || m === '1' || m === 'track') return 'one';
    if (m === 'all') return 'all';
    return 'off';
  }

  function toggleShuffleOptimistic() {
    if (state.isRadio) {
      showToast(IS_EN ? 'Shuffle is unavailable on Radio' : 'Перемешивание недоступно для радио');
      return;
    }
    triggerHaptic('toggle');
    const nextShuffle = !state.shuffle;
    state.shuffle = nextShuffle;
    state.pendingShuffleUntil = Date.now() + 3000;
    renderNowPlaying();
    if (isStandbyOrLandscapeVisible()) updateStandbyUI();
    send({
      action: 'set_shuffle',
      params: { enabled: nextShuffle }
    });
    showToast(nextShuffle
      ? (IS_EN ? '🔀 Shuffle Enabled' : '🔀 Перемешивание включено')
      : (IS_EN ? 'Shuffle Off' : 'Перемешивание выключено'));
  }

  dom.btnShuffle.addEventListener('click', toggleShuffleOptimistic);

  function applyRepeatModeOptimistic(nextMode) {
    let cleanMode = normalizeRepeatMode(nextMode);
    if (state.isRadio && cleanMode === 'all') {
      cleanMode = 'off';
    }
    state.repeatMode = cleanMode;
    state.pendingRepeatUntil = Date.now() + 3000;
    renderNowPlaying();
    if (isStandbyOrLandscapeVisible()) updateStandbyUI();
    send({
      action: 'set_repeat',
      params: { mode: cleanMode }
    });
    if (cleanMode === 'one') {
      showToast(IS_EN ? '🔂 Repeat One Track' : '🔂 Зациклен 1 трек');
    } else if (cleanMode === 'all') {
      showToast(IS_EN ? '🔁 Repeat Queue' : '🔁 Повтор очереди');
    } else {
      showToast(IS_EN ? 'Repeat Off' : 'Повтор выключен');
    }
  }

  function cycleRepeatMode() {
    triggerHaptic('toggle');
    const modes = state.isRadio ? ['off', 'one'] : ['off', 'all', 'one'];
    const curMode = normalizeRepeatMode(state.repeatMode);
    const curIdx = modes.indexOf(curMode);
    const nextIdx = ((curIdx >= 0 ? curIdx : 0) + 1) % modes.length;
    applyRepeatModeOptimistic(modes[nextIdx]);
  }

  dom.btnRepeat.addEventListener('click', cycleRepeatMode);

  let toastTimerId = 0;

  function showToast(message, durationMs = 1900) {
    if (!message) return;
    let hud = document.getElementById('amr-toast-hud');
    if (!hud) {
      hud = document.createElement('div');
      hud.id = 'amr-toast-hud';
      hud.className = 'amr-toast-hud';
      hud.setAttribute('role', 'status');
      hud.setAttribute('aria-live', 'polite');
      document.body.appendChild(hud);
    }
    hud.textContent = translateTextToEn(String(message));
    if (toastTimerId) clearTimeout(toastTimerId);
    requestAnimationFrame(() => {
      hud.classList.add('visible');
    });
    toastTimerId = setTimeout(() => {
      hud.classList.remove('visible');
    }, durationMs);
  }

  function handleToggleFavorite(e) {
    if (e) e.stopPropagation();
    triggerHaptic('toggle');

    const t = state.track;
    const currentFav = Boolean(t && t.favorited);
    const nextFav = !currentFav;

    if (t) {
      t.favorited = nextFav;
      state.pendingFavoriteUntil = Date.now() + 3500;
      state.pendingFavoriteTrackKey = `${t.artist || ''}|${t.name || ''}`;
      state.pendingFavoriteValue = nextFav;
    }

    const sbFavBtn = document.getElementById('standby-btn-favorite');
    [dom.btnFavorite, dom.miniBtnFavorite, sbFavBtn].forEach(btn => {
      if (!btn) return;
      btn.classList.toggle('active', nextFav);
      if (!nextFav) {
        btn.classList.remove('unpop-anim');
        void btn.offsetWidth;
        btn.classList.add('unpop-anim');
      } else {
        btn.classList.remove('unpop-anim');
      }
    });

    showToast(nextFav ? '★ Добавлено в избранное' : '☆ Удалено из избранного');
    send({
      action: 'favorite',
      params: { favorited: nextFav }
    });
  }

  dom.btnFavorite.addEventListener('click', handleToggleFavorite);

  if (dom.miniBtnFavorite) {
    dom.miniBtnFavorite.addEventListener('click', handleToggleFavorite);
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
    const isCdnStall = Boolean(state.isStreamStalled) || up.includes('ОЖИДАНИЕ CDN');
    const isBufferingStream = !isCdnStall && (Boolean(state.isBuffering) || up.includes('ЗАПУСК ИЗ ОБЛАКА') || up.includes('STARTING CLOUD STREAM') || up.includes('БУФЕРИЗАЦИЯ') || up.includes('ОПРЕДЕЛЕНИЕ'));
    const isLossy = up.includes('AAC') || up.includes('MP3');
    const devRateHz = state.audioDeviceSampleRate || 44100;
    const rateKhz = (devRateHz / 1000).toFixed(1).replace(/\.0$/, '');
    const outBitDepth = isLossy ? 16 : (state.audioDeviceBitDepth || (devRateHz >= 48000 ? 24 : 16));

    let formatBadge = 'ALAC Lossless';
    if (isCdnStall) {
      formatBadge = IS_EN ? 'CDN Timeout' : 'Таймаут CDN';
    } else if (isBufferingStream) {
      formatBadge = IS_EN ? 'Buffering…' : 'Буферизация…';
    } else if (up.includes('192') || up.includes('HI-RES')) {
      formatBadge = 'ALAC Hi-Res';
    } else if (isLossy) {
      formatBadge = 'AAC 256k';
    } else if (up.includes('LOSSLESS') || up.includes('ALAC')) {
      formatBadge = 'ALAC Lossless';
    }

    // Parse source sample rate and bit depth for Bit-Perfect & DSP verification
    const rateMatch = quality.match(/(\d+(?:\.\d+)?)\s*(?:kHz|кГц)/i);
    const sourceRateHz = rateMatch ? Math.round(parseFloat(rateMatch[1]) * 1000) : (t && (t.sample_rate || t.sampleRate) ? Number(t.sample_rate || t.sampleRate) : null);
    const depthMatch = quality.match(/(\d+)-(?:bit|бит)/i);
    const sourceBitDepth = depthMatch ? parseInt(depthMatch[1], 10) : (t && (t.bit_depth || t.bitDepth) ? Number(t.bit_depth || t.bitDepth) : null);

    const activeDev = (state.audioDevices || []).find(d => d.name === state.audioDeviceName || d.isDefault || d.is_default);
    const isNetworkRenderer = Boolean(
      state.isDlnaActive ||
      (activeDev && (activeDev.type === 'dlna' || activeDev.isNetwork || activeDev.is_network || activeDev.protocol === 'dlna' || activeDev.protocol === 'bluos'))
    );
    const isLocalDspActive = !isNetworkRenderer && (state.dspMode === 'sdm_dop' || state.dspMode === 'hq_nos_pcm');
    const srcRateVal = sourceRateHz || 44100;
    const srcBitsVal = sourceBitDepth || (isLossy ? 16 : (srcRateVal >= 48000 ? 24 : 16));
    const srcBitratePerCh = srcRateVal * srcBitsVal;
    const outDspRateHz = Number(state.dspOutputSampleRate) || 0;
    const badgeDsdMatch = String(state.dspBadge || '').match(/DSD(\d+)/i);
    const dsdMult = outDspRateHz >= 2822400
      ? Math.round(outDspRateHz / ((outDspRateHz % 48000 === 0) ? 48000 : 44100))
      : (badgeDsdMatch ? Number(badgeDsdMatch[1]) : (Number(state.dspRate) || 256));
    const dsdBaseGrid = (srcRateVal % 48000 === 0 && state.dspClockPolicy !== 'strict_sacd_44k1') ? 48000 : 44100;
    const dsdClockHz = outDspRateHz >= 2822400 ? outDspRateHz : (dsdMult * dsdBaseGrid);
    const dsdFallbackToPcm = state.dspMode === 'sdm_dop' && outDspRateHz > 0 && outDspRateHz < 2822400;
    const isInsufficientDsd = Boolean(
      isLocalDspActive &&
      state.dspMode === 'sdm_dop' &&
      !isLossy &&
      (
        dsdFallbackToPcm ||
        dsdClockHz < srcBitratePerCh ||
        (dsdClockHz / srcRateVal) < 32 ||
        (dsdMult <= 64 && srcRateVal > 48000)
      )
    );

    const ratesMatch = !sourceRateHz || Math.abs(sourceRateHz - devRateHz) <= 500;
    const depthsMatch = !sourceBitDepth || outBitDepth >= sourceBitDepth;
    const isPreDspActive = Boolean(
      (state.lateNightDrcMode && state.lateNightDrcMode !== 'off') ||
      state.lateNightDrcEnabled ||
      (state.masteringDeclipMode && state.masteringDeclipMode !== 'off') ||
      (state.masteringDeesserMode && state.masteringDeesserMode !== 'off') ||
      state.roomCorrectionActive ||
      (state.roomAcoustic && state.roomAcoustic.enabled && state.roomAcoustic.active_profile)
    );
    const isClockSynced64BitDsp = !isLocalDspActive && !isLossy && isPreDspActive && (Boolean(state.isClockSyncedDsp) || ratesMatch);
    const isHardwareMatched = isLocalDspActive
      ? !isInsufficientDsd
      : (isClockSynced64BitDsp || ((state.isBitPerfect !== false) && ratesMatch && depthsMatch));
    const isVerified = isHardwareMatched && !isLossy;

    const sa = state.spectralAnalysis || {};
    const saEnabled = sa.is_enabled !== false && sa.isEnabled !== false && sa.verdict !== 'disabled';
    const saVerdict = saEnabled ? (sa.verdict || 'analyzing') : '';
    const analyzedFrames = Number(sa.analyzed_frames_count !== undefined ? sa.analyzed_frames_count : (sa.analyzedFramesCount || 0));
    const isPendingValidation = !saEnabled || !saVerdict || saVerdict === 'analyzing' || (state.playerState !== 'playing' && analyzedFrames === 0);
    const isSpectralFake = !isPendingValidation && (saVerdict === 'upsampled' || saVerdict === 'lossy_transcode' || saVerdict === 'lossy_upscaled');
    const isSpectralZeroPad = !isPendingValidation && saVerdict === 'zero_padded';

    // Color the play icon (.icon-dac) inside quality badges according to quality match / mismatch,
    // or reset to gray (no color class) when a new track starts / while analyzing
    const sbDacBadge = document.getElementById('standby-dac-badge');
    const qualityBadges = [dom.audioQualityBadge, dom.mobileDacBadge, dom.desktopDacBadge, sbDacBadge].filter(Boolean);
    qualityBadges.forEach(badge => {
      badge.classList.remove('quality-ok', 'quality-warn', 'quality-bad');
      if (isCdnStall) {
        badge.classList.add('quality-warn');
        badge.title = IS_EN
          ? 'Music.app receives 0 bytes from Apple Music CDN (aod.itunes.apple.com) — check DNS (1.1.1.1 / 8.8.8.8) or network route'
          : 'Music.app не получает аудиопоток с CDN Apple Music (aod.itunes.apple.com) — проверьте DNS (1.1.1.1 / 8.8.8.8) или маршрут сети';
      } else if (!isBufferingStream) {
        badge.title = IS_EN ? 'Stream & DAC Signal Path' : 'Параметры потока и ЦАП';
        if (!isPendingValidation) {
          const badgeQualityClass = isSpectralFake
            ? 'quality-bad'
            : ((isSpectralZeroPad || (!isLossy && !isHardwareMatched)) ? 'quality-warn' : 'quality-ok');
          badge.classList.add(badgeQualityClass);
        }
      } else {
        badge.title = IS_EN ? 'Buffering Apple Music stream…' : 'Буферизация потока Apple Music…';
      }
    });

    // Sync TV / StandBy spectral verification pill badge
    const sbSpectralBadge = document.getElementById('standby-spectral-badge');
    if (sbSpectralBadge) {
      sbSpectralBadge.classList.toggle('hidden', !saEnabled);
      if (saEnabled) {
        const tvVerdict = isPendingValidation ? 'analyzing' : saVerdict;
        const sRate = Number(sa.sample_rate || sa.sampleRate || devRateHz);
        const tvBadgeMap = {
          verified_hires: sRate > 48000 ? '✓ TRUE HI-RES' : '✓ TRUE 24-BIT',
          verified_lossless: '✓ TRUE LOSSLESS',
          upsampled: '⚠ FAKE HI-RES • 22K CUT',
          lossy_transcode: '⚠ LOSSY TRANSCODE',
          lossy_upscaled: '⚠ UPSCALE 128→256K',
          zero_padded: '⚠ ZERO-PADDED 16→24',
          aac_lossy: '✓ AAC 256 KBPS',
          analyzing: 'FFT АНАЛИЗ...'
        };
        sbSpectralBadge.textContent = tvBadgeMap[tvVerdict] || 'FFT АНАЛИЗ...';
        sbSpectralBadge.classList.remove('authentic', 'warning', 'bad', 'neutral');
        if (tvVerdict === 'upsampled' || tvVerdict === 'lossy_transcode' || tvVerdict === 'lossy_upscaled') {
          sbSpectralBadge.classList.add('bad');
        } else if (tvVerdict === 'zero_padded') {
          sbSpectralBadge.classList.add('warning');
        } else if (tvVerdict === 'aac_lossy' || tvVerdict === 'analyzing') {
          sbSpectralBadge.classList.add('neutral');
        } else {
          sbSpectralBadge.classList.add('authentic');
        }
      }
    }

    const isModalOpen = Boolean(dom.qualityModal && !dom.qualityModal.classList.contains('hidden'));
    if (!isModalOpen) {
      renderSpectralAnalysisUI();
      return;
    }

    if (dom.signalSourceBadge) dom.signalSourceBadge.textContent = formatBadge;
    if (dom.signalSourceTitle) {
      dom.signalSourceTitle.textContent = t ? `${t.name} — ${t.artist}` : 'Apple Music';
    }
    if (dom.signalSourceDetails) {
      if (isCdnStall) {
        dom.signalSourceDetails.textContent = IS_EN
          ? 'HLS stream timeout from Apple Music CDN (aod.itunes.apple.com) — 0 PCM frames in CoreAudio'
          : 'Таймаут загрузки HLS-потока с CDN Apple Music (aod.itunes.apple.com) — 0 кадров PCM в CoreAudio';
      } else if (isBufferingStream) {
        dom.signalSourceDetails.textContent = IS_EN
          ? 'Buffering Apple Music stream (waiting for decoder start)…'
          : 'Буферизация потока Apple Music (ожидание старта декодера)…';
      } else {
        dom.signalSourceDetails.textContent = isLossy ? 'AAC 256 kbps → Декодирование в PCM 16-бит / 44.1 кГц' : quality;
      }
    }
    if (dom.signalDacRate) {
      dom.signalDacRate.textContent = `${rateKhz} кГц`;
    }

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
    const signalEngineBadge = document.getElementById('signal-engine-badge');
    const signalEngineName = document.getElementById('signal-engine-name');
    const signalEngineMeta = document.getElementById('signal-engine-details') || document.querySelector('#signal-node-engine .signal-node-meta');
    const dspTelemPill = document.getElementById('dsp-telemetry-pill');
    const dspTelemText = document.getElementById('dsp-telemetry-text');

    const dspPresetSubEl = document.getElementById('dsp-preset-subtitle');
    if (dspPresetSubEl) {
      if (isNetworkRenderer) {
        dspPresetSubEl.textContent = IS_EN
          ? 'External network streamer active: Bit-Perfect PCM (DSD/NOS presets unavailable)'
          : 'Активен внешний сетевой плеер BluOS / DLNA: передаётся Bit-Perfect PCM (DSD/NOS не поддерживаются)';
      } else if (state.dspActivePresetSubtitle) {
        dspPresetSubEl.textContent = translateTextToEn(state.dspActivePresetSubtitle);
      }
    }

    const isDeClipActive = Boolean(state.masteringDeclipMode && state.masteringDeclipMode !== 'off');
    const deClipShort = state.masteringDeclipMode === 'studio'
      ? (IS_EN ? 'Studio De-Clip' : 'Студийный De-Clip')
      : (state.masteringDeclipMode === 'gentle'
        ? (IS_EN ? 'Gentle De-Clip' : 'Деликатный De-Clip')
        : (IS_EN ? 'Smart De-Clip' : 'Авто De-Clip'));
    const deClipSuffix = isDeClipActive ? ` • ⚡️ ${deClipShort}` : '';

    const isDeEsserActive = Boolean(state.masteringDeesserMode && state.masteringDeesserMode !== 'off');
    const deEsserShort = state.masteringDeesserMode === 'vocal'
      ? 'Weiss De-Esser'
      : (IS_EN ? 'Gentle De-Esser' : 'Деликатный De-Esser');
    const deEsserSuffix = isDeEsserActive ? ` • 💎 ${deEsserShort}` : '';

    const roomEqSuffix = (state.roomCorrectionActive || (state.roomAcoustic && state.roomAcoustic.enabled && state.roomAcoustic.active_profile))
      ? ` • Room EQ (${state.roomProfileName || (state.roomAcoustic.active_profile && state.roomAcoustic.active_profile.name) || 'Auto-PEQ'})`
      : '';
    const isDrcActive = Boolean((state.lateNightDrcMode && state.lateNightDrcMode !== 'off') || state.lateNightDrcEnabled);
    const drcModeShort = state.lateNightDrcMode === 'concert'
      ? (IS_EN ? 'Night Concert' : 'Ночной концерт')
      : (IS_EN ? 'Gentle DRC' : 'Деликатный DRC');
    const drcSuffix = isDrcActive ? ` • 🌙 ${drcModeShort}` : '';
    const allPreDspSuffixes = `${deClipSuffix}${deEsserSuffix}${roomEqSuffix}${drcSuffix}`;
    const anyPreDspNodeActive = Boolean(isDeClipActive || isDeEsserActive || roomEqSuffix || isDrcActive);
    syncMasteringRestorationBadgesOnly();
    syncLateNightBadgeOnly();

    if (!isNetworkRenderer && (state.dspMode === 'sdm_dop' || state.dspMode === 'hq_nos_pcm')) {
      const isDSD = (state.dspMode === 'sdm_dop');
      const mhz = ((state.dspOutputSampleRate || 11289600) / 1000000).toFixed(2);
      const dopKhz = ((state.dspDoPCarrierRate || 705600) / 1000).toFixed(1).replace(/\.0$/, '');
      if (signalEngineBadge) {
        signalEngineBadge.textContent = isDSD ? `${mhz} МГц · 1-Bit` : `${dopKhz} кГц · NOS`;
      }
      if (signalEngineName) {
        const presetLabel = (state.dspActivePresetName && state.dspActivePresetId !== 'unsaved_custom')
          ? state.dspActivePresetName
          : (isDSD ? `AMR 7th-Order SDM (${state.dspProfile || '7EC-Balanced'})` : 'AMR HQ NOS PCM Engine (LNS15 Shaper)');
        signalEngineName.textContent = translateTextToEn(presetLabel);
      }
      if (signalEngineMeta) {
        const kernLabel = (state.dspOversamplerBackend === 'metalOverlapSave') ? 'Metal GPU df64' : 'AMX FP64';
        const phaseLabel = (state.dspPhaseMode === 'minimumPhase') ? 'Min-Phase' : 'Lin-Phase';
        const baseMeta = isDSD
          ? `${kernLabel} (${phaseLabel}) → Trellis M=${state.dspTrellisOrder || 8} (${state.dspProfile || '7EC-Balanced'}) → DoP (${dopKhz} кГц)`
          : `${kernLabel} (${phaseLabel}) → 15-Order LNS15 Shaper (${dopKhz} кГц / 24-бит)`;
        signalEngineMeta.textContent = `${baseMeta}${allPreDspSuffixes}`;
      }
      if (dom.signalDacRate) {
        dom.signalDacRate.textContent = isDSD ? `DoP ${dopKhz} кГц` : `${dopKhz} кГц`;
      }
      if (dspTelemPill && dspTelemText) {
        dspTelemPill.classList.remove('hidden');
        const hogTxt = state.dspIsHogMode ? 'Hog Mode' : 'Shared';
        const intTxt = state.dspIsIntegerMode ? 'Integer' : 'Float';
        const cpuTxt = Number(state.dspCpuLoadPercent || 0).toFixed(1);
        const bufTxt = Math.round(Number(state.dspRingBufferFillPercent || 0));
        dspTelemText.textContent = `🟢 ${hogTxt} • ${intTxt} • CPU ${cpuTxt}% • Буфер ${bufTxt}%`;
      }
    } else {
      if (signalEngineBadge) signalEngineBadge.textContent = '0.0 dB FS';
      if (signalEngineName) signalEngineName.textContent = 'AMR CoreAudio Engine';
      if (dspTelemPill) dspTelemPill.classList.add('hidden');
      if (signalEngineMeta) {
        if (isNetworkRenderer) {
          const baseDlna = isLossy
            ? 'CoreAudio Process Tap • Декодирование AAC → PCM 16-бит / 44.1 кГц'
            : (anyPreDspNodeActive
              ? 'CoreAudio Process Tap (64-bit Pre-DSP) • Бесконечный PCM поток'
              : 'CoreAudio Process Tap (Bit-Perfect) • Бесконечный PCM поток');
          signalEngineMeta.textContent = `${baseDlna}${allPreDspSuffixes}`;
        } else {
          const guardLabel = state.dacMutingGuardEnabled === true
            ? `DAC Muting Guard (${state.dacMutingGuardMs || 100} мс)`
            : 'Bypass микшера';
          const ampLabel = (state.lockVolume100 && state.ampVolumeControlEnabled)
            ? `${state.ampBrandName || 'AMP'} TCP Vol ${state.ampMuted ? 'MUTE' : state.volume}`
            : (anyPreDspNodeActive ? '64-bit DSP' : 'Zero DSP');
          signalEngineMeta.textContent = isLossy
            ? `CoreAudio HAL • Декодирование AAC → PCM 16-бит / 44.1 кГц${allPreDspSuffixes}`
            : `${anyPreDspNodeActive ? 'CoreAudio 64-bit Lock' : 'Bit-Perfect 100% Lock'} • ${guardLabel} • ${ampLabel}${allPreDspSuffixes}`;
        }
      }
    }
    const signalVerifiedCard = document.querySelector('#quality-modal .signal-verified-card');
    const signalVerifiedTitle = document.querySelector('#quality-modal .signal-verified-title');
    const signalVerifiedDesc = document.querySelector('#quality-modal .signal-verified-desc');
    const shouldHideDspBanner = isLocalDspActive && !isInsufficientDsd && !isSpectralFake && !isSpectralZeroPad;
    const hasTopWarning = isLocalDspActive
      ? (isInsufficientDsd || isSpectralFake || isSpectralZeroPad)
      : (!isVerified || isSpectralFake || isSpectralZeroPad);
    if (signalVerifiedCard) {
      signalVerifiedCard.classList.toggle('hidden', shouldHideDspBanner);
      signalVerifiedCard.classList.toggle('warning', hasTopWarning);
    }
    if (!shouldHideDspBanner && signalVerifiedTitle && signalVerifiedDesc) {
      if (saVerdict === 'lossy_upscaled') {
        signalVerifiedTitle.textContent = 'Обнаружен апскейл Lossy (128 → 256 kbps)';
        signalVerifiedDesc.textContent = sa.verdict_description || sa.verdictDescription || 'Спектр жестко обрезан ниже 16.5 кГц — низкобитрейтный исходник (MP3/AAC 128 kbps) перекодирован в AAC 256 kbps.';
      } else if (saVerdict === 'lossy_transcode') {
        signalVerifiedTitle.textContent = 'Обнаружен транскод из Lossy (MP3 / AAC)';
        signalVerifiedDesc.textContent = sa.verdict_description || sa.verdictDescription || 'Внутри контейнера ALAC Lossless обнаружен жесткий срез ВЧ, характерный для сжатия с потерями.';
      } else if (saVerdict === 'upsampled') {
        signalVerifiedTitle.textContent = 'Обнаружен апсемплинг (Fake Hi-Res)';
        signalVerifiedDesc.textContent = sa.verdict_description || sa.verdictDescription || 'Поток передается в Hi-Res контейнере, но спектр ограничен частотой CD (22.05 кГц).';
      } else if (saVerdict === 'zero_padded') {
        signalVerifiedTitle.textContent = 'Zero-Padded контейнер (16-бит в 24-бит)';
        signalVerifiedDesc.textContent = sa.verdict_description || sa.verdictDescription || 'Младшие 8 бит в 24-битном потоке пустые — реальный динамический диапазон составляет 16 бит.';
      } else if (isLocalDspActive && isInsufficientDsd) {
        const srcKhz = (srcRateVal / 1000).toFixed(1).replace(/\.0$/, '');
        const recDsd = srcRateVal >= 176400 ? 'DSD256' : 'DSD128 / DSD256';
        signalVerifiedTitle.textContent = `Недостаточная частота DSD${dsdMult} для источника (${srcBitsVal}/${srcKhz})`;
        signalVerifiedDesc.textContent = `Поток источника (${srcBitsVal}-бит / ${srcKhz} кГц) превышает оптимальную полосу однобитного режима DSD${dsdMult}. Выберите ${recDsd} для раскрытия битрейта без потерь.`;
      } else if (isClockSynced64BitDsp) {
        const activeDspParts = [];
        if (isDeClipActive) {
          activeDspParts.push(`⚡️ ${deClipShort}`);
        }
        if (isDeEsserActive) {
          activeDspParts.push(`💎 ${deEsserShort}`);
        }
        if (roomEqSuffix) {
          const profName = state.roomProfileName || (state.roomAcoustic && state.roomAcoustic.active_profile && state.roomAcoustic.active_profile.name) || 'Auto-PEQ';
          activeDspParts.push(`Room EQ «${profName}»`);
        }
        if (isDrcActive) {
          activeDspParts.push(`🌙 ${drcModeShort}`);
        }
        signalVerifiedTitle.textContent = `64-bit DSP • Синхронная частота (${outBitDepth}/${rateKhz})`;
        signalVerifiedDesc.textContent = `Частота ЦАП (${rateKhz} кГц) синхронизирована 1:1 с потоком без передискретизации. Активна 64-битная обработка (${activeDspParts.join(' + ')}).`;
      } else if (isVerified) {
        signalVerifiedTitle.textContent = 'Bit-Perfect Verified';
        if (isNetworkRenderer) {
          signalVerifiedDesc.textContent = `Hi-Res PCM поток (${outBitDepth}-бит / ${rateKhz} кГц) захватывается напрямую из Music.app и передается на сетевой рендерер без передискретизации.`;
        } else {
          signalVerifiedDesc.textContent = `Частота ЦАП (${rateKhz} кГц) аппаратно синхронизирована с потоком. Деградация разрядности исключена.`;
        }
      } else if (isLossy) {
        signalVerifiedTitle.textContent = 'Lossy Stream (AAC 256 kbps)';
        signalVerifiedDesc.textContent = 'Воспроизводится сжатый поток AAC 256 kbps (полоса до ~19.5 кГц). Для Bit-Perfect переключитесь на ALAC Lossless.';
      } else {
        const srcKhz = sourceRateHz ? (sourceRateHz / 1000).toFixed(1).replace(/\.0$/, '') : rateKhz;
        const srcBits = sourceBitDepth || (srcRateVal >= 48000 ? 24 : 16);
        if (srcBits === outBitDepth && srcKhz === rateKhz) {
          signalVerifiedTitle.textContent = `Системный микшер macOS (${outBitDepth}/${rateKhz})`;
          signalVerifiedDesc.textContent = `Частота и разрядность совпадают (${outBitDepth}-бит / ${rateKhz} кГц), но поток проходит через микшер macOS CoreAudio.`;
        } else if (srcKhz === rateKhz) {
          signalVerifiedTitle.textContent = `Преобразование разрядности (${srcBits}-бит → ${outBitDepth}-бит @ ${rateKhz} кГц)`;
          signalVerifiedDesc.textContent = `Частота дискретизации синхронизирована 1:1 (${rateKhz} кГц) без передискретизации; выполняется квантование разрядности (${srcBits}-бит → ${outBitDepth}-бит).`;
        } else {
          signalVerifiedTitle.textContent = `Передискретизация (${srcBits}/${srcKhz} → ${outBitDepth}/${rateKhz})`;
          signalVerifiedDesc.textContent = `Частота дискретизации источника (${srcBits}-бит / ${srcKhz} кГц) пересчитывается в режим вывода (${outBitDepth}-бит / ${rateKhz} кГц).`;
        }
      }
    }
    syncSignalPathAmpNode();
    renderSpectralAnalysisUI();
  }

  let spectralPollTimer = null;
  let spectralPollIntervalMs = 0;
  let spectralRpcInFlightAt = 0;
  let standbyRtaRafId = null;
  let lastStandbyRtaFrameMs = 0;
  let cachedStandbyRtaBackdrop = null;
  let cachedStandbyRtaBarsWrap = null;
  let standbyRtaBarEls = [];
  const standbyRtaBarCount = 64;
  const standbyRtaUnsmoothed = new Float32Array(standbyRtaBarCount);
  const standbyRtaCurrent = new Float32Array(standbyRtaBarCount).fill(0.03);
  const standbyRtaTarget = new Float32Array(standbyRtaBarCount).fill(0.03);
  const standbyRtaVelocity = new Float32Array(standbyRtaBarCount).fill(0.0);
  const standbyRtaRendered = new Float32Array(standbyRtaBarCount).fill(-1);
  const standbyRtaClassState = new Uint8Array(standbyRtaBarCount).fill(255);

  let cachedSpectralModalBarsWrap = null;
  let spectralModalRtaBarEls = [];
  const spectralModalRtaBarCount = 32;
  const spectralModalRtaCurrent = new Float32Array(spectralModalRtaBarCount).fill(0.06);
  const spectralModalRtaTarget = new Float32Array(spectralModalRtaBarCount).fill(0.06);
  const spectralModalRtaRendered = new Float32Array(spectralModalRtaBarCount).fill(-1);
  const spectralModalRtaClassState = new Uint8Array(spectralModalRtaBarCount).fill(255);

  function stepStandbyRtaAnimation(nowMs) {
    const sa = state.spectralAnalysis || {};
    const saEnabled = sa.is_enabled !== false && sa.isEnabled !== false && sa.verdict !== 'disabled';
    const showStandby = saEnabled && isStandbyOrLandscapeVisible() && standbyRtaBarEls.length === standbyRtaBarCount;
    const showModal = saEnabled && Boolean(dom.qualityModal && !dom.qualityModal.classList.contains('hidden')) && spectralModalRtaBarEls.length === spectralModalRtaBarCount;
    if (!showStandby && !showModal) {
      standbyRtaRafId = null;
      return;
    }

    const ts = nowMs || performance.now();
    // Pace GPU scale3d transforms at locked ~60fps (15ms) for zero-judder motion on 60Hz TVs & 120Hz ProMotion
    if (ts - lastStandbyRtaFrameMs < 15) {
      standbyRtaRafId = requestAnimationFrame(stepStandbyRtaAnimation);
      return;
    }
    lastStandbyRtaFrameMs = ts;

    // Decay targets to floor if playback paused or spectral stream stalled (>1.2s)
    const spectralStale = (ts - (state.lastSpectralUpdateAt || 0)) > 1200;
    const shouldDecayToFloor = (state.playerState !== 'playing') || spectralStale;
    let hasMotion = false;

    if (showStandby) {
      for (let i = 0; i < standbyRtaBarCount; i++) {
        if (shouldDecayToFloor && standbyRtaTarget[i] > 0.03) {
          standbyRtaTarget[i] = Math.max(0.03, standbyRtaTarget[i] * 0.86);
          if (standbyRtaTarget[i] > 0.032) hasMotion = true;
        }
        const tgt = Math.max(0.025, Math.min(0.96, standbyRtaTarget[i]));
        const cur = standbyRtaCurrent[i];
        const diff = tgt - cur;
        const factor = diff > 0 ? 0.36 : 0.19;
        standbyRtaVelocity[i] = standbyRtaVelocity[i] * 0.42 + diff * factor;
        const nextVal = Math.max(0.025, Math.min(0.96, cur + standbyRtaVelocity[i]));
        standbyRtaCurrent[i] = nextVal;

        if (Math.abs(diff) > 0.0025 || Math.abs(standbyRtaVelocity[i]) > 0.0018) {
          hasMotion = true;
        }
        if (Math.abs(nextVal - standbyRtaRendered[i]) > 0.0025) {
          standbyRtaRendered[i] = nextVal;
          const bar = standbyRtaBarEls[i];
          if (bar) bar.style.transform = `scale3d(1, ${nextVal.toFixed(3)}, 1)`;
        }
      }
    }

    if (showModal) {
      for (let i = 0; i < spectralModalRtaBarCount; i++) {
        if (shouldDecayToFloor && spectralModalRtaTarget[i] > 0.06) {
          spectralModalRtaTarget[i] = Math.max(0.06, spectralModalRtaTarget[i] * 0.86);
          if (spectralModalRtaTarget[i] > 0.062) hasMotion = true;
        }
        const tgt = Math.max(0.06, Math.min(1.0, spectralModalRtaTarget[i]));
        const cur = spectralModalRtaCurrent[i];
        const diff = tgt - cur;
        const step = diff * (diff > 0 ? 0.44 : 0.24);
        const nextVal = Math.max(0.06, Math.min(1.0, cur + step));
        spectralModalRtaCurrent[i] = nextVal;

        if (Math.abs(diff) > 0.003) {
          hasMotion = true;
        }
        if (Math.abs(nextVal - spectralModalRtaRendered[i]) > 0.0025) {
          spectralModalRtaRendered[i] = nextVal;
          const bar = spectralModalRtaBarEls[i];
          if (bar) bar.style.transform = `scale3d(1, ${nextVal.toFixed(3)}, 1)`;
        }
      }
    }

    if (hasMotion) {
      standbyRtaRafId = requestAnimationFrame(stepStandbyRtaAnimation);
    } else {
      standbyRtaRafId = null;
    }
  }
