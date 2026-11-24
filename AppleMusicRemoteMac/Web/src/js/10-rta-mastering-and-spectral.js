  function setTextIfChanged(el, nextText) {
    if (el && el.textContent !== nextText) {
      el.textContent = nextText;
    }
  }

  function ensureStandbyRtaAnimLoop() {
    const modalVisible = Boolean(dom.qualityModal && !dom.qualityModal.classList.contains('hidden'));
    if (!standbyRtaRafId && (isStandbyOrLandscapeVisible() || modalVisible)) {
      standbyRtaRafId = requestAnimationFrame(stepStandbyRtaAnimation);
    }
  }

  function renderStandbyRtaBackdrop(sa, saEnabled, isLossy, sRate, isWarning) {
    if (!cachedStandbyRtaBackdrop) cachedStandbyRtaBackdrop = document.getElementById('standby-rta-backdrop');
    if (!cachedStandbyRtaBarsWrap) cachedStandbyRtaBarsWrap = document.getElementById('standby-rta-bars');
    const backdrop = cachedStandbyRtaBackdrop;
    const barsWrap = cachedStandbyRtaBarsWrap;
    if (!backdrop || !barsWrap) return;

    backdrop.classList.toggle('hidden', !saEnabled);
    if (!saEnabled || !isStandbyOrLandscapeVisible()) return;

    const barCount = standbyRtaBarCount;
    if (barsWrap.children.length !== barCount || standbyRtaBarEls.length !== barCount) {
      barsWrap.innerHTML = '';
      standbyRtaBarEls = [];
      const frag = document.createDocumentFragment();
      for (let i = 0; i < barCount; i++) {
        const b = document.createElement('div');
        b.className = 'standby-rta-bar';
        frag.appendChild(b);
        standbyRtaBarEls.push(b);
        standbyRtaRendered[i] = -1;
        standbyRtaClassState[i] = 255;
      }
      barsWrap.appendChild(frag);
    }

    const rawBands = Array.isArray(sa.rta_bands || sa.rtaBands) && (sa.rta_bands || sa.rtaBands).length === 32
      ? (sa.rta_bands || sa.rtaBands)
      : null;
    const isPlaying = state.playerState === 'playing';
    const isHiResRate = sRate >= 88200;
    const splitBarIdx = isHiResRate ? 40 : 48;

    // 1. Interpolate 32 FFT bands to 64 raw targets (zero per-frame heap allocation)
    const unsmoothed = standbyRtaUnsmoothed;
    for (let i = 0; i < barCount; i++) {
      if (!isPlaying || !rawBands) {
        unsmoothed[i] = 0.03;
        continue;
      }
      const pos = (i / (barCount - 1)) * 31;
      const idx0 = Math.floor(pos);
      const idx1 = Math.min(31, idx0 + 1);
      const frac = pos - idx0;
      const t = frac * frac * (3 - 2 * frac);
      const v0 = Number.isFinite(Number(rawBands[idx0])) ? Number(rawBands[idx0]) : 0.03;
      const v1 = Number.isFinite(Number(rawBands[idx1])) ? Number(rawBands[idx1]) : 0.03;
      unsmoothed[i] = v0 * (1 - t) + v1 * t;
    }

    // 2. Apply crisp 5-tap spatial curve across neighboring bars
    for (let i = 0; i < barCount; i++) {
      const bar = standbyRtaBarEls[i];
      if (!isPlaying || !rawBands) {
        standbyRtaTarget[i] = 0.03;
        if (standbyRtaClassState[i] !== 4) {
          standbyRtaClassState[i] = 4;
          bar.classList.remove('ultrasonic', 'warning-bar');
          bar.classList.add('depleted');
        }
        continue;
      }

      const m2 = unsmoothed[Math.max(0, i - 2)];
      const m1 = unsmoothed[Math.max(0, i - 1)];
      const c0 = unsmoothed[i];
      const p1 = unsmoothed[Math.min(barCount - 1, i + 1)];
      const p2 = unsmoothed[Math.min(barCount - 1, i + 2)];
      const val = m2 * 0.05 + m1 * 0.20 + c0 * 0.50 + p1 * 0.20 + p2 * 0.05;

      standbyRtaTarget[i] = Math.max(0.03, Math.min(0.95, val * 0.94));

      const isAboveBoundary = i >= splitBarIdx;
      const isDepleted = isAboveBoundary && (isWarning || isLossy || val < 0.06);
      const isUltra = isAboveBoundary && !isDepleted && !isWarning;
      const isWarn = isWarning && !isDepleted;
      const classMask = (isUltra ? 1 : 0) | (isWarn ? 2 : 0) | (isDepleted ? 4 : 0);
      if (standbyRtaClassState[i] !== classMask) {
        standbyRtaClassState[i] = classMask;
        bar.classList.toggle('ultrasonic', isUltra);
        bar.classList.toggle('warning-bar', isWarn);
        bar.classList.toggle('depleted', isDepleted);
      }
      if (!standbyRtaRafId) {
        const tgtVal = standbyRtaTarget[i];
        standbyRtaRendered[i] = tgtVal;
        bar.style.transform = `scale3d(1, ${tgtVal.toFixed(3)}, 1)`;
      }
    }

    ensureStandbyRtaAnimLoop();
  }

  function renderTopAndStandbyDrBadges(sa, saEnabled) {
    const rawDr = sa.tt_dr_score !== undefined ? sa.tt_dr_score : sa.ttDrScore;
    const hasDr = saEnabled && Boolean(state.track && state.track.name) && rawDr !== null && rawDr !== undefined && Number.isFinite(Number(rawDr));
    const drScore = hasDr ? Math.max(0, Math.min(24, Math.round(Number(rawDr)))) : null;
    const drStatus = drScore === null
      ? 'analyzing'
      : (drScore >= 12 ? 'dynamic' : (drScore >= 8 ? 'balanced' : 'compressed'));
    const drLabel = drScore !== null ? `DR${drScore}` : 'DR--';
    const rawLufs = sa.integrated_lufs !== undefined ? sa.integrated_lufs : sa.integratedLufs;
    const lufsPart = (rawLufs !== null && rawLufs !== undefined && Number.isFinite(Number(rawLufs)))
      ? ` • ${Number(rawLufs).toFixed(1)} LUFS`
      : '';
    const statusHint = drScore === null
      ? ''
      : (drStatus === 'dynamic'
        ? (IS_EN ? 'Audiophile Dynamic Master' : 'Высокая динамика')
        : (drStatus === 'balanced'
          ? (IS_EN ? 'Balanced Master' : 'Сбалансированный мастер')
          : (IS_EN ? 'Loudness War Compression' : 'Перекомпрессирован (Loudness War)')));
    const tooltipText = drScore !== null
      ? `TT DR${drScore}${lufsPart} — ${statusHint}`
      : (IS_EN ? 'Mastering Dynamic Range (TT DR)' : 'Динамический диапазон мастеринга (TT DR)');

    ['player-dr-badge', 'mobile-dr-badge'].forEach((id) => {
      const el = document.getElementById(id);
      if (!el) return;
      el.classList.toggle('hidden', !hasDr);
      if (hasDr) {
        el.textContent = drLabel;
        el.title = tooltipText;
        el.classList.toggle('dynamic', drStatus === 'dynamic');
        el.classList.toggle('balanced', drStatus === 'balanced');
        el.classList.toggle('compressed', drStatus === 'compressed');
      }
    });

    const sbDrEl = document.getElementById('standby-dr-badge');
    if (sbDrEl) {
      sbDrEl.classList.toggle('hidden', !hasDr);
      if (hasDr) {
        sbDrEl.textContent = drStatus === 'compressed' ? `⚠️ ${drLabel}` : drLabel;
        sbDrEl.title = tooltipText;
        sbDrEl.classList.toggle('authentic', drStatus === 'dynamic');
        sbDrEl.classList.toggle('balanced', drStatus === 'balanced');
        sbDrEl.classList.toggle('compressed', drStatus === 'compressed');
        sbDrEl.classList.remove('neutral', 'warning');
      }
    }
  }

  function renderMasteringAndStereoCard(sa, saEnabled) {
    const mCard = document.getElementById('signal-mastering-card');
    if (!mCard) return;
    mCard.classList.toggle('hidden', !saEnabled);
    if (!saEnabled) return;

    const rawDr = sa.tt_dr_score !== undefined ? sa.tt_dr_score : sa.ttDrScore;
    const hasDr = rawDr !== null && rawDr !== undefined && Number.isFinite(Number(rawDr));
    const drScore = hasDr ? Math.max(0, Math.min(24, Math.round(Number(rawDr)))) : null;
    const drStatus = drScore === null
      ? 'analyzing'
      : (drScore >= 12 ? 'dynamic' : (drScore >= 8 ? 'balanced' : 'compressed'));

    mCard.classList.toggle('authentic', drStatus === 'dynamic');
    mCard.classList.toggle('balanced', drStatus === 'balanced');
    mCard.classList.toggle('compressed', drStatus === 'compressed');

    const drBadgeEl = document.getElementById('mastering-dr-badge');
    if (drBadgeEl) {
      drBadgeEl.classList.toggle('neutral', drStatus === 'analyzing');
      drBadgeEl.classList.toggle('balanced', drStatus === 'balanced');
      drBadgeEl.classList.toggle('compressed', drStatus === 'compressed');
      drBadgeEl.classList.remove('warning');
      if (drScore === null) {
        drBadgeEl.textContent = IS_EN ? 'DR ANALYZING...' : 'DR АНАЛИЗ...';
      } else if (drStatus === 'dynamic') {
        drBadgeEl.textContent = `DR${drScore} • DYNAMIC`;
      } else if (drStatus === 'balanced') {
        drBadgeEl.textContent = `DR${drScore} • BALANCED`;
      } else {
        drBadgeEl.textContent = `DR${drScore} • LOUDNESS WAR`;
      }
    }

    const intLufs = sa.integrated_lufs !== undefined ? sa.integrated_lufs : sa.integratedLufs;
    const stLufs = sa.short_term_lufs !== undefined ? sa.short_term_lufs : sa.shortTermLufs;
    const momLufs = sa.momentary_lufs !== undefined ? sa.momentary_lufs : sa.momentaryLufs;
    const lraLu = sa.loudness_range_lu !== undefined ? sa.loudness_range_lu : sa.loudnessRangeLu;
    const tpDbtp = sa.true_peak_dbtp !== undefined ? sa.true_peak_dbtp : sa.truePeakDbtp;
    const ispClips = Number(sa.isp_clip_count !== undefined ? sa.isp_clip_count : (sa.ispClipCount || 0));

    const lufsIntEl = document.getElementById('mastering-lufs-int');
    if (lufsIntEl) {
      lufsIntEl.textContent = (intLufs !== null && intLufs !== undefined && Number.isFinite(Number(intLufs)))
        ? `${Number(intLufs).toFixed(1)} LUFS`
        : '— LUFS';
    }

    const lufsStEl = document.getElementById('mastering-lufs-st');
    if (lufsStEl) {
      const stDisplay = (stLufs !== null && stLufs !== undefined && Number.isFinite(Number(stLufs)))
        ? Number(stLufs)
        : ((momLufs !== null && momLufs !== undefined && Number.isFinite(Number(momLufs))) ? Number(momLufs) : null);
      lufsStEl.textContent = stDisplay !== null ? `${stDisplay.toFixed(1)} LUFS` : '— LUFS';
    }

    const tpEl = document.getElementById('mastering-true-peak');
    if (tpEl) {
      if (tpDbtp !== null && tpDbtp !== undefined && Number.isFinite(Number(tpDbtp))) {
        const tpNum = Number(tpDbtp);
        const sign = tpNum > 0 ? '+' : '';
        tpEl.textContent = `${sign}${tpNum.toFixed(2)} dBTP`;
        tpEl.classList.toggle('tp-warning', tpNum > 0.0 || ispClips > 0);
      } else {
        tpEl.textContent = '— dBTP';
        tpEl.classList.remove('tp-warning');
      }
    }

    const lraEl = document.getElementById('mastering-lra');
    if (lraEl) {
      lraEl.textContent = (lraLu !== null && lraLu !== undefined && Number.isFinite(Number(lraLu)))
        ? `${Number(lraLu).toFixed(1)} LU`
        : '— LU';
    }

    // Stereo Phase Correlation (-1 ... 0 ... +1), Width & Balance
    const rawCorr = Number(sa.phase_correlation !== undefined ? sa.phase_correlation : (sa.phaseCorrelation !== undefined ? sa.phaseCorrelation : 1.0));
    const corr = Number.isFinite(rawCorr) ? Math.max(-1.0, Math.min(1.0, rawCorr)) : 1.0;
    const rawWidth = Number(sa.stereo_width_percent !== undefined ? sa.stereo_width_percent : (sa.stereoWidthPercent || 0));
    const widthPct = Number.isFinite(rawWidth) ? Math.max(0, Math.min(100, Math.round(rawWidth))) : 0;
    const rawBal = Number(sa.channel_balance_db !== undefined ? sa.channel_balance_db : (sa.channelBalanceDb || 0));
    const balDb = Number.isFinite(rawBal) ? rawBal : 0.0;

    const phaseValEl = document.getElementById('phase-meter-val');
    if (phaseValEl) {
      const sign = corr >= 0 ? '+' : '';
      phaseValEl.textContent = `${sign}${corr.toFixed(2)}`;
      phaseValEl.classList.toggle('negative', corr < 0);
      phaseValEl.classList.toggle('wide', corr >= 0 && corr < 0.45);
    }

    const phaseFillEl = document.getElementById('phase-meter-fill');
    const phaseDotEl = document.getElementById('phase-meter-dot');
    const dotPct = ((corr + 1.0) * 0.5) * 100.0;
    if (phaseDotEl) {
      phaseDotEl.style.left = `${dotPct.toFixed(1)}%`;
    }
    if (phaseFillEl) {
      if (corr >= 0) {
        phaseFillEl.style.left = '50%';
        phaseFillEl.style.width = `${(corr * 50.0).toFixed(1)}%`;
        phaseFillEl.classList.add('positive');
        phaseFillEl.classList.remove('negative');
      } else {
        const w = Math.abs(corr) * 50.0;
        phaseFillEl.style.left = `${(50.0 - w).toFixed(1)}%`;
        phaseFillEl.style.width = `${w.toFixed(1)}%`;
        phaseFillEl.classList.add('negative');
        phaseFillEl.classList.remove('positive');
      }
    }

    const widthEl = document.getElementById('stereo-width-val');
    if (widthEl) {
      widthEl.textContent = `${widthPct}%`;
    }

    const balEl = document.getElementById('stereo-balance-val');
    if (balEl) {
      if (Math.abs(balDb) < 0.15) {
        balEl.textContent = IS_EN ? 'Center (0.0 dB)' : 'Центр (0.0 дБ)';
      } else {
        const side = balDb > 0 ? 'R' : 'L';
        balEl.textContent = `${side} +${Math.abs(balDb).toFixed(1)} ${IS_EN ? 'dB' : 'дБ'}`;
      }
    }

    const ispBadge = document.getElementById('isp-clips-badge');
    if (ispBadge) {
      ispBadge.classList.toggle('hidden', ispClips <= 0);
      if (ispClips > 0) {
        ispBadge.textContent = IS_EN ? `ISP Overs: ${ispClips}` : `ISP >0 dBTP: ${ispClips}`;
      }
    }

    const mTitleEl = document.getElementById('mastering-verdict-title');
    const mDescEl = document.getElementById('mastering-verdict-desc');
    if (mTitleEl && mDescEl) {
      if (drScore === null) {
        mTitleEl.textContent = state.playerState === 'playing'
          ? (IS_EN ? 'Measuring TT Dynamic Range & EBU R128...' : 'Расчёт TT Dynamic Range и EBU R128...')
          : (IS_EN ? 'Waiting for playback...' : 'Ожидание воспроизведения...');
        mDescEl.textContent = IS_EN
          ? 'Accumulating 3-second PCM windows for official TT DR score, ITU-R BS.1770-4 loudness, and 4x True Peak.'
          : 'Накопление 3-секундных блоков PCM для расчёта официального индекса TT Dynamic Range, громкости ITU-R BS.1770-4 и 4x True Peak.';
      } else if (drStatus === 'dynamic') {
        mTitleEl.textContent = IS_EN
          ? `Audiophile Dynamic Master (DR${drScore})`
          : `Эталонная динамика мастеринга (DR${drScore})`;
        mDescEl.textContent = IS_EN
          ? 'Natural micro-dynamics and transient punch preserved without brickwall limiting.'
          : 'Свободные транзиенты и живая микродинамика сохранены без агрессивного brickwall-лимитирования.';
      } else if (drStatus === 'balanced') {
        mTitleEl.textContent = IS_EN
          ? `Balanced Studio Master (DR${drScore})`
          : `Сбалансированный студийный мастер (DR${drScore})`;
        mDescEl.textContent = IS_EN
          ? 'Moderate studio bus compression with healthy crest factor for modern genres.'
          : 'Умеренная студийная компрессия с комфортным запасом пик-фактора для современных жанров.';
      } else {
        mTitleEl.textContent = IS_EN
          ? `Heavy Compression • Loudness War (DR${drScore})`
          : `Перекомпрессия «Войны громкости» (DR${drScore})`;
        mDescEl.textContent = ispClips > 0
          ? (IS_EN
            ? `Aggressive brickwall limiting detected with ${ispClips} inter-sample peaks (>0 dBTP). ISP Headroom Guard in DSP Engine prevents DAC clipping.`
            : `Обнаружено жесткое лимитирование и ${ispClips} межсэмпловых перегрузок (>0 dBTP). Защита ISP Headroom Guard в DSP предотвращает клиппинг ЦАПа.`)
          : (IS_EN
            ? 'Dense brickwall limiting reduces transient contrast; after loudness normalization such tracks sound less punchy than high-DR masters.'
            : 'Плотный brickwall-лимитер сжал транзиенты: при выравнивании громкости такой трек звучит субъективно тише и менее рельефно, чем динамичный мастер.');
      }
    }
  }

  function applyDeviceCapabilityPermissionsUI(options = {}) {
    const canSelectDac = state.allowDacSelection !== false;
    const canSelectDspPerm = state.allowDspPresetSelection !== false;
    const canMeasureRoom = state.allowRoomMeasurement !== false;
    const canControlRoomEq = canMeasureRoom || canSelectDspPerm;
    const canControlLateNight = state.allowLateNightMode !== false;
    const canModifyLib = state.allowLibraryModification !== false;
    document.body.classList.toggle('library-mod-locked', !canModifyLib);
    if (dom.btnSaveQueuePlaylist) {
      dom.btnSaveQueuePlaylist.classList.toggle('hidden', !canModifyLib);
      if (!canModifyLib) dom.btnSaveQueuePlaylist.disabled = true;
    }
    if (!canModifyLib) {
      if (dom.btnAddPlaylistLibrary) dom.btnAddPlaylistLibrary.classList.add('hidden');
      if (dom.btnRemoveDetailLibrary) dom.btnRemoveDetailLibrary.classList.add('hidden');
      if (dom.btnRemoveArtistDetailLibrary) dom.btnRemoveArtistDetailLibrary.classList.add('hidden');
      if (dom.btnAddTrackLibrary) dom.btnAddTrackLibrary.classList.add('hidden');
      if (dom.btnRemoveTrackLibrary) dom.btnRemoveTrackLibrary.classList.add('hidden');
      if (dom.btnRemoveArtistLibrary) dom.btnRemoveArtistLibrary.classList.add('hidden');
    }
    const activeDev = (state.audioDevices || []).find(d => d && (d.name === state.audioDeviceName || d.isDefault || d.is_default));
    const isNetworkOut = Boolean(
      state.isDlnaActive ||
      (activeDev && (activeDev.type === 'dlna' || activeDev.isNetwork || activeDev.is_network || activeDev.protocol === 'dlna' || activeDev.protocol === 'bluos'))
    );

    if (dom.btnOpenDevices) {
      dom.btnOpenDevices.classList.toggle('hidden', !canSelectDac);
      dom.btnOpenDevices.disabled = !canSelectDac;
    }
    if (!canSelectDac && dom.devicesModal && !dom.devicesModal.classList.contains('hidden')) {
      blurFocusedInContainer(dom.devicesModal);
      dom.devicesModal.classList.add('hidden');
      dom.devicesModal.setAttribute('aria-hidden', 'true');
    }

    const dspFieldEl = document.getElementById('dsp-preset-field');
    const dspSelectEl = document.getElementById('dsp-preset-select');
    const dspReadonlyEl = document.getElementById('dsp-preset-readonly-note');
    if (dspFieldEl) {
      dspFieldEl.classList.toggle('hidden', !canSelectDspPerm);
    }
    if (dspSelectEl) {
      dspSelectEl.disabled = !canSelectDspPerm || isNetworkOut;
      if (isNetworkOut && Array.from(dspSelectEl.options).some(o => o.value === 'builtin_passthrough')) {
        dspSelectEl.value = 'builtin_passthrough';
      }
    }
    if (dspReadonlyEl) {
      if (!canSelectDspPerm) {
        dspReadonlyEl.classList.remove('hidden');
        const presetLabel = isNetworkOut
          ? 'Bit-Perfect Passthrough'
          : (state.dspActivePresetName
            ? translateTextToEn(state.dspActivePresetName)
            : (state.dspMode === 'sdm_dop' ? `DSD${state.dspRate || 256} DoP` : (state.dspMode === 'hq_nos_pcm' ? 'HQ PCM NOS' : 'Bit-Perfect Passthrough')));
        dspReadonlyEl.textContent = IS_EN
          ? `🔒 Preset: ${presetLabel} (selection locked on Mac)`
          : `🔒 Пресет: ${presetLabel} (выбор закрыт в настройках Mac)`;
      } else if (isNetworkOut) {
        dspReadonlyEl.classList.remove('hidden');
        dspReadonlyEl.textContent = IS_EN
          ? '🌐 DSP presets disabled for external BluOS / DLNA network players'
          : '🌐 Пресеты DSP отключены при выводе на сетевой плеер BluOS / DLNA';
      } else {
        dspReadonlyEl.classList.add('hidden');
      }
    }

    const deClipFieldEl = document.getElementById('mastering-declip-field');
    const deClipSelectEl = document.getElementById('mastering-declip-select');
    const deClipReadonlyEl = document.getElementById('mastering-declip-readonly-note');
    if (deClipFieldEl) {
      deClipFieldEl.classList.toggle('hidden', !canSelectDspPerm);
    }
    if (deClipSelectEl) {
      deClipSelectEl.disabled = !canSelectDspPerm;
    }
    if (deClipReadonlyEl) {
      if (!canSelectDspPerm) {
        deClipReadonlyEl.classList.remove('hidden');
        const dcMode = state.masteringDeclipMode || 'off';
        const dcLabel = dcMode === 'off'
          ? (IS_EN ? 'Off (100% Bit-Perfect)' : 'Выкл (100% Bit-Perfect)')
          : (dcMode === 'studio' ? 'Studio De-Clip' : (dcMode === 'gentle' ? 'Gentle De-Clip' : 'Auto De-Clip'));
        deClipReadonlyEl.textContent = IS_EN
          ? `🔒 De-Clipper: ${dcLabel} (locked on Mac)`
          : `🔒 De-Clipper: ${dcLabel} (доступ закрыт в настройках Mac)`;
      } else {
        deClipReadonlyEl.classList.add('hidden');
      }
    }

    const deEsserFieldEl = document.getElementById('mastering-deesser-field');
    const deEsserSelectEl = document.getElementById('mastering-deesser-select');
    const deEsserReadonlyEl = document.getElementById('mastering-deesser-readonly-note');
    if (deEsserFieldEl) {
      deEsserFieldEl.classList.toggle('hidden', !canSelectDspPerm);
    }
    if (deEsserSelectEl) {
      deEsserSelectEl.disabled = !canSelectDspPerm;
    }
    if (deEsserReadonlyEl) {
      if (!canSelectDspPerm) {
        deEsserReadonlyEl.classList.remove('hidden');
        const deMode = state.masteringDeesserMode || 'off';
        const deLabel = deMode === 'off'
          ? (IS_EN ? 'Off (100% Bit-Perfect)' : 'Выкл (100% Bit-Perfect)')
          : (deMode === 'vocal' ? 'Weiss Studio' : 'Gentle');
        deEsserReadonlyEl.textContent = IS_EN
          ? `🔒 Weiss De-Esser: ${deLabel} (locked on Mac)`
          : `🔒 Weiss De-Esser: ${deLabel} (доступ закрыт в настройках Mac)`;
      } else {
        deEsserReadonlyEl.classList.add('hidden');
      }
    }

    const drcFieldEl = document.getElementById('late-night-drc-field');
    const drcSelectEl = document.getElementById('late-night-drc-select');
    const drcReadonlyEl = document.getElementById('late-night-drc-readonly-note');
    if (drcFieldEl) {
      drcFieldEl.classList.toggle('hidden', !canControlLateNight);
    }
    if (drcSelectEl) {
      drcSelectEl.disabled = !canControlLateNight;
    }
    if (drcReadonlyEl) {
      if (!canControlLateNight) {
        drcReadonlyEl.classList.remove('hidden');
        const activeMode = (state.lateNightDrcMode === 'gentle' || state.lateNightDrcMode === 'concert')
          ? state.lateNightDrcMode
          : 'off';
        const statusTxt = activeMode === 'concert'
          ? (IS_EN ? 'Night Concert' : 'Ночной концерт')
          : (activeMode === 'gentle'
            ? (IS_EN ? 'Gentle DRC' : 'Деликатный')
            : (IS_EN ? 'Off (100% Bit-Perfect)' : 'Выкл (100% Bit-Perfect)'));
        drcReadonlyEl.textContent = IS_EN
          ? `🔒 Late-Night DRC: ${statusTxt} (access disabled on Mac)`
          : `🔒 Ночной режим: ${statusTxt} (доступ закрыт в настройках Mac)`;
      } else {
        drcReadonlyEl.classList.add('hidden');
      }
    }

    const roomActionsEl = document.getElementById('room-measure-actions');
    const roomLockedEl = document.getElementById('room-measure-locked-note');
    const btnStartRoom = document.getElementById('btn-start-room-measure');
    const btnUploadRoom = document.getElementById('btn-upload-room-audio');
    const roomToggleBtn = document.getElementById('btn-room-eq-toggle');
    const roomProfileSelect = document.getElementById('room-profile-select');
    const hasRoomProfiles = Boolean(
      state.roomAcoustic &&
      Array.isArray(state.roomAcoustic.profiles) &&
      state.roomAcoustic.profiles.length > 0
    );
    if (roomActionsEl) {
      roomActionsEl.classList.toggle('hidden', !canMeasureRoom);
    }
    if (btnStartRoom) {
      btnStartRoom.disabled = !canMeasureRoom || state.isMeasuringRoom;
    }
    if (btnUploadRoom) {
      btnUploadRoom.disabled = !canMeasureRoom || state.isMeasuringRoom;
    }
    if (roomToggleBtn) {
      roomToggleBtn.disabled = !hasRoomProfiles || !canControlRoomEq;
    }
    if (roomProfileSelect) {
      roomProfileSelect.disabled = !hasRoomProfiles || !canControlRoomEq;
    }
    if (roomLockedEl) {
      roomLockedEl.classList.toggle('hidden', canMeasureRoom);
    }
    if (!options.fromRoomAcousticUI && state.roomAcoustic) {
      updateRoomAcousticUI(state.roomAcoustic, { skipSignalRefresh: true, skipPermissionsSync: true });
    }
  }

  function renderSpectralAnalysisUI() {
    const quality = state.audioQuality || 'Lossless (ALAC 24-bit/48kHz)';
    const isLossy = quality.toUpperCase().includes('AAC') || quality.toUpperCase().includes('MP3');
    const devRateHz = state.audioDeviceSampleRate || 44100;
    const sa = state.spectralAnalysis || {};
    const saEnabled = sa.is_enabled !== false && sa.isEnabled !== false && sa.verdict !== 'disabled';
    const verdict = sa.verdict || (isLossy ? 'aac_lossy' : (devRateHz > 48000 ? 'verified_hires' : 'verified_lossless'));
    const sRate = Number(sa.sample_rate || sa.sampleRate || devRateHz);
    const isWarning = (verdict === 'upsampled' || verdict === 'lossy_transcode' || verdict === 'zero_padded' || verdict === 'lossy_upscaled');

    renderStandbyRtaBackdrop(sa, saEnabled, isLossy, sRate, isWarning);
    renderTopAndStandbyDrBadges(sa, saEnabled);

    const isModalOpen = Boolean(dom.qualityModal && !dom.qualityModal.classList.contains('hidden'));
    if (!isModalOpen) return;

    renderMasteringAndStereoCard(sa, saEnabled);

    const card = document.getElementById('signal-spectral-card');
    if (!card) return;

    card.classList.toggle('hidden', !saEnabled);
    if (!saEnabled) return;

    const nyquistHz = Number(sa.nyquist_frequency_hz || sa.nyquistFrequencyHz || (sRate / 2));
    const cutoffHz = Number(sa.cutoff_frequency_hz || sa.cutoffFrequencyHz || (isLossy ? 19200 : nyquistHz));
    const effBits = Number(sa.effective_bit_depth || sa.effectiveBitDepth || (isLossy ? 16 : (sRate >= 48000 ? 24 : 16)));
    const claimedBits = Number(sa.claimed_bit_depth || sa.claimedBitDepth || effBits);
    const isZeroPadded = Boolean(sa.is_zero_padded || sa.isZeroPadded);
    const ultraDb = Number(sa.ultrasonic_energy_db !== undefined ? sa.ultrasonic_energy_db : (sa.ultrasonicEnergyDb !== undefined ? sa.ultrasonicEnergyDb : -92));

    const isNeutral = (verdict === 'aac_lossy' || verdict === 'analyzing');

    card.classList.toggle('warning', isWarning);
    card.classList.toggle('authentic', !isWarning && !isNeutral);

    const badgeEl = document.getElementById('spectral-verdict-badge');
    if (badgeEl) {
      badgeEl.classList.toggle('warning', isWarning);
      badgeEl.classList.toggle('neutral', isNeutral);
      const badgeMap = {
        verified_hires: sRate > 48000 ? 'TRUE HI-RES' : 'TRUE 24-BIT',
        verified_lossless: 'TRUE LOSSLESS',
        upsampled: 'FAKE HI-RES • 22k CUT',
        lossy_transcode: 'LOSSY TRANSCODE',
        lossy_upscaled: 'UPSCALE 128→256K',
        zero_padded: 'ZERO-PADDED 16→24',
        aac_lossy: 'AAC 256 KBPS',
        analyzing: 'FFT АНАЛИЗ...'
      };
      setTextIfChanged(badgeEl, badgeMap[verdict] || 'TRUE LOSSLESS');
    }

    const titleEl = document.getElementById('spectral-verdict-title');
    if (titleEl) {
      setTextIfChanged(titleEl, sa.verdict_title || sa.verdictTitle || (isLossy ? 'Сжатый поток AAC 256 kbps' : 'Verified True Lossless'));
    }

    const descEl = document.getElementById('spectral-verdict-desc');
    if (descEl) {
      setTextIfChanged(descEl, sa.verdict_description || sa.verdictDescription || 'Спектральный анализ потока CoreAudio Process Tap через Accelerate vDSP FFT.');
    }

    const cutoffEl = document.getElementById('spectral-metric-cutoff');
    if (cutoffEl) {
      setTextIfChanged(cutoffEl, `до ${(cutoffHz / 1000).toFixed(1)} кГц`);
    }

    const ultraEl = document.getElementById('spectral-metric-ultra');
    if (ultraEl) {
      const ultraText = sRate >= 88200
        ? (ultraDb > -80 ? `${Math.round(ultraDb)} dBFS` : 'Нет (<-82 dB)')
        : 'Н/Д (≤ 48 кГц)';
      setTextIfChanged(ultraEl, ultraText);
    }

    const bitsEl = document.getElementById('spectral-metric-bits');
    if (bitsEl) {
      const bitsText = isZeroPadded
        ? `16-бит (в ${claimedBits}-бит)`
        : `${effBits}-бит (${effBits >= 24 ? 'Честный LSB' : 'PCM'})`;
      setTextIfChanged(bitsEl, bitsText);
    }

    const markerEl = document.getElementById('spectral-cutoff-marker');
    const markerLabelEl = document.getElementById('spectral-cutoff-marker-label');
    const axisRefEl = document.getElementById('spectral-axis-ref');
    const axisNyqEl = document.getElementById('spectral-axis-nyquist');
    const isHiResRate = sRate >= 88200;

    if (markerEl && markerLabelEl) {
      const nextLeft = isHiResRate ? '62.5%' : '75%';
      if (markerEl.style.left !== nextLeft) markerEl.style.left = nextLeft;
      setTextIfChanged(markerLabelEl, isHiResRate ? '22.05 кГц CD' : '18.0 кГц AAC');
    }
    if (axisRefEl) {
      setTextIfChanged(axisRefEl, isHiResRate ? '22.05 кГц' : '18.0 кГц');
    }
    if (axisNyqEl) {
      setTextIfChanged(axisNyqEl, `${(nyquistHz / 1000).toFixed(1).replace(/\.0$/, '')} кГц`);
    }

    if (!cachedSpectralModalBarsWrap) {
      cachedSpectralModalBarsWrap = document.getElementById('spectral-rta-bars');
    }
    const barsContainer = cachedSpectralModalBarsWrap;
    if (barsContainer) {
      if (barsContainer.children.length !== spectralModalRtaBarCount || spectralModalRtaBarEls.length !== spectralModalRtaBarCount) {
        barsContainer.innerHTML = '';
        spectralModalRtaBarEls = [];
        const frag = document.createDocumentFragment();
        for (let i = 0; i < spectralModalRtaBarCount; i++) {
          const b = document.createElement('div');
          b.className = 'spectral-rta-bar';
          frag.appendChild(b);
          spectralModalRtaBarEls.push(b);
          spectralModalRtaRendered[i] = -1;
          spectralModalRtaClassState[i] = 255;
        }
        barsContainer.appendChild(frag);
      }
      const rawBands = Array.isArray(sa.rta_bands || sa.rtaBands) && (sa.rta_bands || sa.rtaBands).length === spectralModalRtaBarCount
        ? (sa.rta_bands || sa.rtaBands)
        : null;
      const isPlaying = state.playerState === 'playing';

      const splitIdx = isHiResRate ? 20 : 24;
      for (let i = 0; i < spectralModalRtaBarCount; i++) {
        const bar = spectralModalRtaBarEls[i];
        let val = (isPlaying && rawBands) ? Number(rawBands[i]) : 0.06;
        if (!Number.isFinite(val)) val = 0.06;
        const clamped = Math.max(0.06, Math.min(1.0, val));
        spectralModalRtaTarget[i] = clamped;

        const isAboveBoundary = i >= splitIdx;
        const isDepleted = isAboveBoundary && (isWarning || isLossy || clamped < 0.065);
        const isUltra = isAboveBoundary && !isDepleted && !isWarning;
        const isWarn = isWarning && !isDepleted;
        const classMask = (isUltra ? 1 : 0) | (isWarn ? 2 : 0) | (isDepleted ? 4 : 0);
        if (spectralModalRtaClassState[i] !== classMask) {
          spectralModalRtaClassState[i] = classMask;
          bar.classList.toggle('ultrasonic', isUltra);
          bar.classList.toggle('warning-bar', isWarn);
          bar.classList.toggle('depleted', isDepleted);
        }
        if (!standbyRtaRafId) {
          spectralModalRtaCurrent[i] = clamped;
          spectralModalRtaRendered[i] = clamped;
          bar.style.transform = `scale3d(1, ${clamped.toFixed(3)}, 1)`;
        }
      }
      ensureStandbyRtaAnimLoop();
    }
  }
