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

  function updateDSPSettingsUI(data) {
    if (!data || typeof data !== 'object') return;
    state.lastDspSettings = Object.assign({}, data);
    if (data.is_dlna_active !== undefined) {
      state.isDlnaActive = Boolean(data.is_dlna_active);
    }
    if (data.room_acoustic && typeof data.room_acoustic === 'object') {
      updateRoomAcousticUI(data.room_acoustic, { skipSignalRefresh: true });
    }
    if (data.late_night_drc && typeof data.late_night_drc === 'object') {
      updateLateNightDRCUI(data.late_night_drc, { skipSignalRefresh: true });
    }
    if (data.mastering_restoration && typeof data.mastering_restoration === 'object') {
      updateMasteringRestorationUI(data.mastering_restoration, { skipSignalRefresh: true });
    }
    if (data.mode !== undefined) state.dspMode = String(data.mode || 'passthrough');
    if (data.dsd_rate !== undefined) state.dspRate = Number(data.dsd_rate) || 256;
    if (data.profile !== undefined) {
      const p = String(data.profile || 'balanced');
      state.dspProfileKey = p;
      state.dspProfile = (p === 'transient') ? '7EC-Transient' : ((p === 'superWide') ? '7EC-Super' : '7EC-Balanced');
    }
    if (data.clock_policy !== undefined) state.dspClockPolicy = String(data.clock_policy || 'strictSACD44k1');
    if (data.oversampler_backend !== undefined) state.dspOversamplerBackend = String(data.oversampler_backend || 'accelerateAMX');
    if (data.phase_mode !== undefined) state.dspPhaseMode = String(data.phase_mode || 'linearPhase');
    if (data.trellis_order !== undefined) state.dspTrellisOrder = Number(data.trellis_order) || 8;
    if (data.output_sample_rate !== undefined) state.dspOutputSampleRate = Number(data.output_sample_rate) || 0;
    if (data.dop_carrier_rate !== undefined) state.dspDoPCarrierRate = Number(data.dop_carrier_rate) || 0;
    if (data.is_hog_mode !== undefined) state.dspIsHogMode = Boolean(data.is_hog_mode);
    if (data.is_integer_mode !== undefined) state.dspIsIntegerMode = Boolean(data.is_integer_mode);
    if (data.cpu_load_percent !== undefined) state.dspCpuLoadPercent = Number(data.cpu_load_percent) || 0;
    if (data.ring_buffer_fill_percent !== undefined) state.dspRingBufferFillPercent = Number(data.ring_buffer_fill_percent) || 0;

    if (data.usb_dac_available !== undefined) state.usbDacAvailable = Boolean(data.usb_dac_available);
    if (data.supports_nos_pcm !== undefined) state.dspSupportsNos = Boolean(data.supports_nos_pcm);
    if (data.supports_dsd_dop !== undefined) state.dspSupportsDsd = Boolean(data.supports_dsd_dop);
    if (data.max_dsd_rate !== undefined) state.dspMaxDsdRate = Number(data.max_dsd_rate) || 0;
    if (data.active_output_transport !== undefined) state.dspActiveOutputTransport = String(data.active_output_transport || '');

    if (data.active_preset_id !== undefined) {
      state.dspActivePresetId = String(data.active_preset_id || 'builtin_passthrough');
    }
    if (data.active_preset_name !== undefined) {
      state.dspActivePresetName = String(data.active_preset_name || '');
    }
    if (data.active_preset_subtitle !== undefined) {
      state.dspActivePresetSubtitle = String(data.active_preset_subtitle || '');
    }
    if (Array.isArray(data.presets)) {
      state.dspPresets = data.presets;
    }

    const activeDev = Array.isArray(state.audioDevices)
      ? state.audioDevices.find((d) => d && (d.isDefault || d.is_default))
      : null;
    const isNetDev = Boolean(
      state.isDlnaActive ||
      (activeDev && (activeDev.isNetwork || activeDev.is_network || activeDev.protocol === 'dlna' || activeDev.protocol === 'bluos'))
    );
    const devSupportsNos = state.dspSupportsNos !== undefined
      ? Boolean(state.dspSupportsNos)
      : Boolean(activeDev && (activeDev.supportsNOS || activeDev.supports_nos));
    const devSupportsDsd = state.dspSupportsDsd !== undefined
      ? Boolean(state.dspSupportsDsd)
      : Boolean(activeDev && (activeDev.supportsDSDDoP || activeDev.supports_dsd_dop));
    const hasEligibleUsbDac = state.usbDacAvailable !== undefined
      ? Boolean(state.usbDacAvailable)
      : (devSupportsNos || devSupportsDsd);

    if (!isNetDev && devSupportsDsd && state.dspMode === 'sdm_dop') {
      state.dspBadge = `DSD${state.dspRate || 256} DoP · ${state.dspProfile || '7EC-Balanced'}`;
    } else if (!isNetDev && devSupportsNos && state.dspMode === 'hq_nos_pcm') {
      const khz = ((state.dspDoPCarrierRate || 705600) / 1000).toFixed(1).replace(/\.0$/, '');
      state.dspBadge = `HQ NOS PCM · ${khz} kHz`;
    } else {
      state.dspBadge = '';
    }

    const isPresetSupportedByHardware = (p) => {
      if (!p) return false;
      const pid = String(p.id || '');
      if (pid === 'builtin_passthrough') return true;
      const pMode = String(p.mode || (p.configuration && p.configuration.mode) || '');
      if (pMode === 'passthrough' || pMode === 'bitPerfectPassthrough') return true;
      if (pMode === 'hq_nos_pcm') return devSupportsNos;
      if (pMode === 'sdm_dop') return devSupportsDsd;
      return hasEligibleUsbDac;
    };

    const presetSel = document.getElementById('dsp-preset-select');
    if (presetSel) {
      if (Array.isArray(state.dspPresets) && state.dspPresets.length > 0) {
        presetSel.innerHTML = '';
        state.dspPresets.forEach((p) => {
          if (!p || !p.id) return;
          const opt = document.createElement('option');
          opt.value = String(p.id);
          const isBuiltIn = Boolean(p.is_builtin !== undefined ? p.is_builtin : p.isBuiltIn);
          const rawName = String(p.name || p.id);
          opt.textContent = isBuiltIn ? translateTextToEn(rawName) : `★ ${rawName}`;
          opt.disabled = isNetDev || !isPresetSupportedByHardware(p);
          presetSel.appendChild(opt);
        });
        if (!isNetDev && hasEligibleUsbDac && state.dspActivePresetId === 'unsaved_custom') {
          const customOpt = document.createElement('option');
          customOpt.value = 'unsaved_custom';
          customOpt.disabled = true;
          customOpt.textContent = `✏️ ${translateTextToEn(state.dspActivePresetName || 'Пользовательский режим')}`;
          presetSel.appendChild(customOpt);
        }
      }
      if (isNetDev || !hasEligibleUsbDac) {
        presetSel.value = 'builtin_passthrough';
        presetSel.disabled = true;
      } else if (state.dspActivePresetId) {
        presetSel.value = state.dspActivePresetId;
        presetSel.disabled = (state.allowDspPresetSelection === false);
      }
    }

    const subEl = document.getElementById('dsp-preset-subtitle');
    if (subEl) {
      if (isNetDev) {
        subEl.textContent = IS_EN
          ? 'External network streamer active: Bit-Perfect PCM (DSD/NOS presets unavailable)'
          : 'Активен внешний сетевой плеер BluOS / DLNA: передаётся Bit-Perfect PCM (DSD/NOS не поддерживаются)';
      } else if (!hasEligibleUsbDac) {
        subEl.textContent = IS_EN
          ? 'No external USB DAC connected: DSD and HQ NOS modes require a USB DAC (≥ 24-bit / 176.4 kHz)'
          : 'Внешний USB ЦАП не подключён: режимы DSD и HQ NOS доступны только для USB ЦАП (≥ 24-бит / 176.4 кГц)';
      } else if (state.dspActivePresetSubtitle) {
        subEl.textContent = translateTextToEn(state.dspActivePresetSubtitle);
      }
    }

    applyDeviceCapabilityPermissionsUI();
    renderNowPlaying();
    updateSignalPathDetails();
  }

  function pushDSPSettingsToServer() {
    if (state.isDlnaActive) {
      const presetSel = document.getElementById('dsp-preset-select');
      if (presetSel) presetSel.value = 'builtin_passthrough';
      showToast(IS_EN
        ? 'DSP presets are disabled when outputting to BluOS / DLNA network players'
        : 'Выбор пресета DSP отключён при выводе на сетевой плеер BluOS / DLNA');
      return;
    }
    const presetSel = document.getElementById('dsp-preset-select');
    if (!presetSel || !presetSel.value || presetSel.value === 'unsaved_custom') return;
    if (presetSel.value !== 'builtin_passthrough' && state.usbDacAvailable === false) {
      presetSel.value = 'builtin_passthrough';
      showToast(IS_EN
        ? 'DSD & HQ NOS modes are available only for external USB DACs'
        : 'Режимы DSD и HQ NOS доступны только для внешних USB ЦАП');
      return;
    }
    if (state.allowDspPresetSelection === false) {
      if (state.dspActivePresetId) {
        presetSel.value = state.dspActivePresetId;
      }
      showToast(IS_EN ? 'DSP preset selection is disabled for this device on Mac' : 'Выбор пресета DSP отключён для этого устройства в настройках Mac');
      return;
    }
    triggerHaptic('light');
    send({
      action: 'select_dsp_preset',
      params: {
        preset_id: presetSel.value
      }
    });
  }

  function defaultLateNightSubtitle(mode) {
    if (mode === 'gentle') {
      return translateTextToEn('Мягкий подъём тихих деталей (до +6 дБ) с гейтом шума -63 dBFS для джаза, вокала и акустики.');
    }
    if (mode === 'concert') {
      return translateTextToEn('Глубокий контроль оркестровых пианиссимо и тутти (до +9.5 дБ, -1.0 dBTP) для классики и саундтреков.');
    }
    return translateTextToEn('Прямой 100% Bit-Perfect тракт без динамической обработки сигнала.');
  }

  function syncLateNightBadgeOnly() {
    const badgeEl = document.getElementById('late-night-gain-badge');
    const selectEl = document.getElementById('late-night-drc-select');
    const subEl = document.getElementById('late-night-drc-subtitle');

    const mode = (state.lateNightDrcMode === 'gentle' || state.lateNightDrcMode === 'concert')
      ? state.lateNightDrcMode
      : 'off';
    const isEnabled = mode !== 'off';
    state.lateNightDrcEnabled = isEnabled;
    state.lateNightDrcMode = mode;
    if (isEnabled) {
      state.lateNightDrcProfile = mode;
    }

    if (selectEl && selectEl.value !== mode && Array.from(selectEl.options).some(o => o.value === mode)) {
      selectEl.value = mode;
    }
    if (subEl) {
      subEl.textContent = (isEnabled && state.lateNightDrcSubtitle)
        ? translateTextToEn(state.lateNightDrcSubtitle)
        : defaultLateNightSubtitle(mode);
    }
    if (!badgeEl) return;
    if (!isEnabled) {
      badgeEl.classList.remove('active');
      badgeEl.textContent = '100% Bit-Perfect';
    } else {
      badgeEl.classList.add('active');
      const g = Number(state.lateNightDrcGainDb) || 0;
      if (Math.abs(g) >= 0.15 && state.playerState === 'playing') {
        const sign = g >= 0 ? '+' : '';
        badgeEl.textContent = `64-bit • ${sign}${g.toFixed(1)} dB`;
      } else {
        badgeEl.textContent = mode === 'concert'
          ? (IS_EN ? 'ACTIVE • CONCERT' : 'АКТИВЕН • КОНЦЕРТ')
          : (IS_EN ? 'ACTIVE • GENTLE' : 'АКТИВЕН • ДЕЛИКАТНЫЙ');
      }
    }
  }

  function updateLateNightDRCUI(data, opts = {}) {
    if (!data || typeof data !== 'object') return;
    if (data.profile !== undefined) {
      const nextProf = String(data.profile || 'gentle');
      if (nextProf === 'gentle' || nextProf === 'concert') {
        state.lateNightDrcProfile = nextProf;
      }
    }
    if (data.enabled !== undefined) {
      state.lateNightDrcEnabled = Boolean(data.enabled);
    }
    if (data.mode !== undefined) {
      const nextMode = String(data.mode || 'off');
      if (nextMode === 'gentle' || nextMode === 'concert') {
        state.lateNightDrcProfile = nextMode;
        state.lateNightDrcEnabled = true;
        state.lateNightDrcMode = nextMode;
      } else {
        state.lateNightDrcEnabled = false;
        state.lateNightDrcMode = 'off';
      }
    } else {
      state.lateNightDrcMode = state.lateNightDrcEnabled ? (state.lateNightDrcProfile || 'gentle') : 'off';
    }
    if (data.subtitle !== undefined) {
      state.lateNightDrcSubtitle = String(data.subtitle || '');
    } else if (data.profile_subtitle !== undefined && state.lateNightDrcEnabled) {
      state.lateNightDrcSubtitle = String(data.profile_subtitle || '');
    }
    if (data.current_gain_db !== undefined) {
      state.lateNightDrcGainDb = Number(data.current_gain_db) || 0;
    }
    syncLateNightBadgeOnly();
    applyDeviceCapabilityPermissionsUI();
    if (!opts.skipSignalRefresh) {
      renderNowPlaying();
      updateSignalPathDetails();
    }
  }

  function pushLateNightDRCToServer() {
    const drcSel = document.getElementById('late-night-drc-select');
    if (!drcSel) return;
    if (state.allowLateNightMode === false) {
      drcSel.value = state.lateNightDrcMode || 'off';
      showToast(IS_EN ? 'Late-Night DRC access is disabled for this device on Mac' : 'Доступ к ночному режиму отключён для этого устройства в настройках Mac');
      return;
    }
    const nextMode = (drcSel.value === 'gentle' || drcSel.value === 'concert') ? drcSel.value : 'off';
    state.lateNightDrcMode = nextMode;
    state.lateNightDrcEnabled = nextMode !== 'off';
    if (nextMode !== 'off') {
      state.lateNightDrcProfile = nextMode;
    }
    state.lateNightDrcSubtitle = '';
    triggerHaptic('light');
    syncLateNightBadgeOnly();
    send({
      action: 'set_late_night_drc',
      params: {
        mode: nextMode
      }
    });
    if (nextMode === 'off') {
      showToast(IS_EN ? '🌙 Late-Night DRC Off (100% Bit-Perfect)' : '🌙 Ночной режим выключен (100% Bit-Perfect)');
    } else if (nextMode === 'concert') {
      showToast(IS_EN ? '🌙 Night Concert Mode enabled' : '🌙 Включён режим «Ночной концерт»');
    } else {
      showToast(IS_EN ? '🌙 Gentle Late-Night DRC enabled' : '🌙 Включён деликатный ночной режим');
    }
  }

  function defaultDeClipSubtitle(mode) {
    if (mode === 'auto') {
      return IS_EN
        ? 'Automatically reconstructs shaved 0 dBFS brickwall plateaus on compressed masters while leaving DR11+ audiophile recordings untouched.'
        : 'Автоматически достраивает срезанные «полки» кирпичного лимитера на зажатых ремастерах, не вмешиваясь в чистые записи DR11+.';
    }
    if (mode === 'gentle') {
      return IS_EN
        ? 'Smooth 64-bit cubic Hermite transient peak restoration up to +2.8 dB with C1 slope continuity.'
        : 'Деликатная 64-битная кубическая Эрмитова реконструкция транзиентов до +2.8 дБ с гладкой сшивкой склонов.';
    }
    if (mode === 'studio') {
      return IS_EN
        ? 'Deep mastering crest reconstruction up to +4.2 dB for heavily clipped Loudness War (DR4–DR7) rock, metal & pop remasters.'
        : 'Глубокое восстановление динамических пиков до +4.2 дБ для жёстко зажатых ремастеров «Войны громкости» (DR4–DR7).';
    }
    return IS_EN
      ? '100% Bit-Perfect passthrough without waveform peak reconstruction.'
      : 'Прямой 100% Bit-Perfect тракт без реконструкции срезанных верхушек волны.';
  }

  function defaultDeEsserSubtitle(mode) {
    if (mode === 'gentle') {
      return IS_EN
        ? 'Level-independent relative detector (7.0 kHz) taming piercing glare up to -3.5 dB on planar headphones and bright tweeters while preserving cymbal air.'
        : 'Относительный детектор в духе Weiss DAC501 (7.0 кГц): смягчает колкие сибилянты до -3.5 дБ на планарах и ярких АС, сохраняя воздух тарелок.';
    }
    if (mode === 'vocal') {
      return IS_EN
        ? 'Mastering-grade relative sibilance control (6.5 kHz, up to -6.0 dB, 0.8 ms attack) eliminating harsh vocal spikes at any volume.'
        : 'Студийное подавление резких вокальных «с/ц/ш» (6.5 кГц, до -6.0 дБ, атака 0.8 мс) с одинаковой точностью на шёпоте и в тутти.';
    }
    return IS_EN
      ? '100% Bit-Perfect passthrough without high-frequency dynamic sibilance control.'
      : 'Прямой 100% Bit-Perfect тракт без динамического подавления сибилянтов.';
  }

  function syncMasteringRestorationBadgesOnly() {
    const dcBadge = document.getElementById('declip-gain-badge');
    const dcSelect = document.getElementById('mastering-declip-select');
    const dcSub = document.getElementById('mastering-declip-subtitle');
    const dcLabel = document.getElementById('signal-declip-label');

    const dcMode = (state.masteringDeclipMode === 'auto' || state.masteringDeclipMode === 'gentle' || state.masteringDeclipMode === 'studio')
      ? state.masteringDeclipMode
      : 'off';
    state.masteringDeclipMode = dcMode;

    if (dcLabel && IS_EN) {
      dcLabel.textContent = '⚡️ Mastering De-Clipper';
    }
    if (dcSelect) {
      if (IS_EN) {
        const enMap = {
          off: 'Off (100% Bit-Perfect)',
          auto: 'Auto — Smart Guard (DR ≤ 10)',
          gentle: 'Gentle (up to +2.8 dB peaks)',
          studio: 'Studio Restoration (up to +4.2 dB)'
        };
        Array.from(dcSelect.options).forEach(opt => {
          if (enMap[opt.value]) opt.textContent = enMap[opt.value];
        });
      }
      if (dcSelect.value !== dcMode && Array.from(dcSelect.options).some(o => o.value === dcMode)) {
        dcSelect.value = dcMode;
      }
    }
    if (dcSub) {
      dcSub.textContent = (dcMode !== 'off' && state.masteringDeclipSubtitle)
        ? translateTextToEn(state.masteringDeclipSubtitle)
        : defaultDeClipSubtitle(dcMode);
    }
    if (dcBadge) {
      if (dcMode === 'off') {
        dcBadge.classList.remove('active');
        dcBadge.textContent = '100% Bit-Perfect';
      } else {
        dcBadge.classList.add('active');
        const restored = Number(state.masteringDeclipRestoredDb) || 0;
        if (dcMode === 'auto' && state.masteringDeclipAutoBypassed) {
          dcBadge.textContent = IS_EN ? 'DR11+ • BYPASS' : 'DR11+ • ЧИСТЫЙ';
        } else if (restored >= 0.1 && state.playerState === 'playing') {
          dcBadge.textContent = `64-bit • +${restored.toFixed(1)} dB`;
        } else {
          dcBadge.textContent = dcMode === 'studio'
            ? (IS_EN ? 'ACTIVE • STUDIO' : 'АКТИВЕН • СТУДИЯ')
            : (dcMode === 'gentle'
              ? (IS_EN ? 'ACTIVE • GENTLE' : 'АКТИВЕН • ДЕЛИКАТНЫЙ')
              : (IS_EN ? 'SMART GUARD' : 'УМНАЯ ЗАЩИТА'));
        }
      }
    }

    const deBadge = document.getElementById('deesser-gain-badge');
    const deSelect = document.getElementById('mastering-deesser-select');
    const deSub = document.getElementById('mastering-deesser-subtitle');
    const deLabel = document.getElementById('signal-deesser-label');

    const deMode = (state.masteringDeesserMode === 'gentle' || state.masteringDeesserMode === 'vocal')
      ? state.masteringDeesserMode
      : 'off';
    state.masteringDeesserMode = deMode;

    if (deLabel && IS_EN) {
      deLabel.textContent = '💎 Weiss Dynamic De-Esser';
    }
    if (deSelect) {
      if (IS_EN) {
        const enDeMap = {
          off: 'Off (100% Bit-Perfect)',
          gentle: 'Gentle — Planars / Bright HF (up to -3.5 dB)',
          vocal: 'Weiss Studio — Harsh Sibilance (up to -6.0 dB)'
        };
        Array.from(deSelect.options).forEach(opt => {
          if (enDeMap[opt.value]) opt.textContent = enDeMap[opt.value];
        });
      }
      if (deSelect.value !== deMode && Array.from(deSelect.options).some(o => o.value === deMode)) {
        deSelect.value = deMode;
      }
    }
    if (deSub) {
      deSub.textContent = (deMode !== 'off' && state.masteringDeesserSubtitle)
        ? translateTextToEn(state.masteringDeesserSubtitle)
        : defaultDeEsserSubtitle(deMode);
    }
    if (deBadge) {
      if (deMode === 'off') {
        deBadge.classList.remove('active');
        deBadge.textContent = '100% Bit-Perfect';
      } else {
        deBadge.classList.add('active');
        const gr = Number(state.masteringDeesserGainDb) || 0;
        if (Math.abs(gr) >= 0.15 && state.playerState === 'playing') {
          deBadge.textContent = `64-bit • ${gr <= 0 ? '' : '-'}${gr.toFixed(1)} dB`;
        } else {
          deBadge.textContent = deMode === 'vocal'
            ? (IS_EN ? 'ACTIVE • WEISS' : 'АКТИВЕН • WEISS')
            : (IS_EN ? 'ACTIVE • GENTLE' : 'АКТИВЕН • ДЕЛИКАТНЫЙ');
        }
      }
    }
  }

  function updateMasteringRestorationUI(data, opts = {}) {
    if (!data || typeof data !== 'object') return;
    if (data.declip_mode !== undefined) {
      const m = String(data.declip_mode || 'off');
      state.masteringDeclipMode = (m === 'auto' || m === 'gentle' || m === 'studio') ? m : 'off';
    }
    if (data.declip_subtitle !== undefined) {
      state.masteringDeclipSubtitle = String(data.declip_subtitle || '');
    }
    if (data.restored_peak_db !== undefined) {
      state.masteringDeclipRestoredDb = Number(data.restored_peak_db) || 0;
    }
    if (data.reconstructed_clips_count !== undefined) {
      state.masteringDeclipClipsCount = Number(data.reconstructed_clips_count) || 0;
    }
    if (data.auto_bypassed_clean_master !== undefined) {
      state.masteringDeclipAutoBypassed = Boolean(data.auto_bypassed_clean_master);
    }
    if (data.deesser_mode !== undefined) {
      const m = String(data.deesser_mode || 'off');
      state.masteringDeesserMode = (m === 'gentle' || m === 'vocal') ? m : 'off';
    }
    if (data.deesser_subtitle !== undefined) {
      state.masteringDeesserSubtitle = String(data.deesser_subtitle || '');
    }
    if (data.deesser_gain_db !== undefined) {
      state.masteringDeesserGainDb = Number(data.deesser_gain_db) || 0;
    }
    syncMasteringRestorationBadgesOnly();
    applyDeviceCapabilityPermissionsUI();
    if (!opts.skipSignalRefresh) {
      renderNowPlaying();
      updateSignalPathDetails();
    }
  }

  function pushMasteringDeClipToServer() {
    const sel = document.getElementById('mastering-declip-select');
    if (!sel) return;
    if (state.allowDspPresetSelection === false) {
      sel.value = state.masteringDeclipMode || 'off';
      showToast(IS_EN ? 'DSP parameters access is locked for this device on Mac' : 'Управление параметрами DSP отключено для этого устройства в настройках Mac');
      return;
    }
    const nextMode = (sel.value === 'auto' || sel.value === 'gentle' || sel.value === 'studio') ? sel.value : 'off';
    state.masteringDeclipMode = nextMode;
    state.masteringDeclipSubtitle = '';
    triggerHaptic('light');
    syncMasteringRestorationBadgesOnly();
    send({
      action: 'set_mastering_restoration',
      params: {
        declip_mode: nextMode
      }
    });
    if (nextMode === 'off') {
      showToast(IS_EN ? '⚡️ De-Clipper Off (100% Bit-Perfect)' : '⚡️ Реставратор клиппинга выключен');
    } else if (nextMode === 'studio') {
      showToast(IS_EN ? '⚡️ Studio Mastering De-Clipper enabled' : '⚡️ Включена студийная реставрация пиков');
    } else if (nextMode === 'gentle') {
      showToast(IS_EN ? '⚡️ Gentle De-Clipper enabled' : '⚡️ Включён деликатный реставратор пиков');
    } else {
      showToast(IS_EN ? '⚡️ Auto Smart Guard De-Clipper enabled' : '⚡️ Включён умный реставратор клиппинга');
    }
  }

  function pushMasteringDeEsserToServer() {
    const sel = document.getElementById('mastering-deesser-select');
    if (!sel) return;
    if (state.allowDspPresetSelection === false) {
      sel.value = state.masteringDeesserMode || 'off';
      showToast(IS_EN ? 'DSP parameters access is locked for this device on Mac' : 'Управление параметрами DSP отключено для этого устройства в настройках Mac');
      return;
    }
    const nextMode = (sel.value === 'gentle' || sel.value === 'vocal') ? sel.value : 'off';
    state.masteringDeesserMode = nextMode;
    state.masteringDeesserSubtitle = '';
    triggerHaptic('light');
    syncMasteringRestorationBadgesOnly();
    send({
      action: 'set_mastering_restoration',
      params: {
        deesser_mode: nextMode
      }
    });
    if (nextMode === 'off') {
      showToast(IS_EN ? '💎 Weiss De-Esser Off (100% Bit-Perfect)' : '💎 Де-эссер выключен (100% Bit-Perfect)');
    } else if (nextMode === 'vocal') {
      showToast(IS_EN ? '💎 Weiss Studio De-Esser enabled' : '💎 Включён студийный Weiss De-Esser');
    } else {
      showToast(IS_EN ? '💎 Gentle Planar De-Esser enabled' : '💎 Включён деликатный De-Esser для планаров/ВЧ');
    }
  }

  function setupDSPControls() {
    const presetSel = document.getElementById('dsp-preset-select');
    if (presetSel) {
      presetSel.addEventListener('change', pushDSPSettingsToServer);
    }
    const deClipSel = document.getElementById('mastering-declip-select');
    if (deClipSel) {
      deClipSel.addEventListener('change', pushMasteringDeClipToServer);
    }
    const deEsserSel = document.getElementById('mastering-deesser-select');
    if (deEsserSel) {
      deEsserSel.addEventListener('change', pushMasteringDeEsserToServer);
    }
    const drcSel = document.getElementById('late-night-drc-select');
    if (drcSel) {
      drcSel.addEventListener('change', pushLateNightDRCToServer);
    }
  }
