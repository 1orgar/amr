  // ==========================================================================
  // Quick Room Frequency Response Measurement (iPhone / iPad Mic + Auto-PEQ 64-bit)
  // ==========================================================================
  const ROOM_ISO_BANDS_HZ = [
    20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160,
    200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600,
    2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
  ];

  let activeRoomMeasureCtx = null;
  let activeRoomMeasureStream = null;
  let activeRoomMeasureTimer = null;

  function roomDbToSvgPoints(valuesDb) {
    if (!Array.isArray(valuesDb) || valuesDb.length === 0) return '';
    const count = valuesDb.length;
    const width = 360;
    const midY = 56; // 0 dB
    const scalePerDb = 3.1; // +-16 dB fits 6..106 inside 112px viewBox
    const pts = [];
    for (let i = 0; i < count; i++) {
      const x = count > 1 ? ((i / (count - 1)) * width) : 0;
      const clampedDb = Math.max(-16, Math.min(16, Number(valuesDb[i]) || 0));
      const y = midY - clampedDb * scalePerDb;
      pts.push(`${x.toFixed(1)},${y.toFixed(1)}`);
    }
    return pts.join(' ');
  }

  function defaultHarmanTargetCurveDb() {
    return ROOM_ISO_BANDS_HZ.map((f) => {
      if (f <= 55) return 3.2;
      if (f < 180) {
        const t = Math.log10(f / 55) / Math.log10(180 / 55);
        return 3.2 * (1 - t);
      }
      if (f <= 1200) return 0;
      const oct = Math.log2(f / 1200);
      return Math.max(-3.0, -0.65 * oct);
    });
  }

  function renderRoomEqChart(profile, liveMeasuredOverrideDb = null) {
    const lineTarget = document.getElementById('room-eq-line-target');
    const lineMeasured = document.getElementById('room-eq-line-measured');
    const lineCorrected = document.getElementById('room-eq-line-corrected');
    const bandsListEl = document.getElementById('room-eq-bands-list');

    const rawTarget = profile && (profile.target_curve_db || profile.target_db);
    const rawMeasured = profile && (profile.measured_response_db || profile.measured_db);
    const rawCorrected = profile && (profile.corrected_response_db || profile.corrected_db);

    const targetArr = (Array.isArray(rawTarget) && rawTarget.length > 0)
      ? rawTarget
      : defaultHarmanTargetCurveDb();
    const measuredArr = Array.isArray(liveMeasuredOverrideDb)
      ? liveMeasuredOverrideDb
      : (Array.isArray(rawMeasured) ? rawMeasured : []);
    const correctedArr = (!liveMeasuredOverrideDb && Array.isArray(rawCorrected))
      ? rawCorrected
      : [];

    if (lineTarget) lineTarget.setAttribute('points', roomDbToSvgPoints(targetArr));
    if (lineMeasured) lineMeasured.setAttribute('points', roomDbToSvgPoints(measuredArr));
    if (lineCorrected) lineCorrected.setAttribute('points', roomDbToSvgPoints(correctedArr));

    if (bandsListEl) {
      const eqBands = (profile && Array.isArray(profile.eq_bands)) ? profile.eq_bands : [];
      if (!liveMeasuredOverrideDb && eqBands.length > 0) {
        bandsListEl.innerHTML = '';
        eqBands.forEach((b) => {
          if (!b || b.enabled === false) return;
          const f = Number(b.frequency_hz || b.frequencyHz || 0);
          const g = Number(b.gain_db || b.gainDB || 0);
          const q = Number(b.q || 1);
          const freqStr = f >= 1000 ? `${(f / 1000).toFixed(f % 1000 === 0 ? 0 : 1)}к` : `${Math.round(f)}`;
          const pill = document.createElement('span');
          pill.className = 'room-eq-band-pill';
          pill.textContent = `${freqStr}Гц ${g >= 0 ? '+' : ''}${g.toFixed(1)}дБ Q${q.toFixed(1)}`;
          bandsListEl.appendChild(pill);
        });
        bandsListEl.classList.remove('hidden');
      } else {
        bandsListEl.classList.add('hidden');
        bandsListEl.innerHTML = '';
      }
    }
  }

  function updateRoomAcousticUI(raw, options = {}) {
    if (!raw || typeof raw !== 'object') return;
    const payload = (raw.room_acoustic && typeof raw.room_acoustic === 'object') ? raw.room_acoustic : raw;
    if (payload.status === 'error' && payload.message) {
      showToast(String(payload.message));
      return;
    }

    if (payload.enabled !== undefined) {
      state.roomAcoustic.enabled = Boolean(payload.enabled);
    }
    if (payload.is_test_signal_playing !== undefined) {
      state.roomAcoustic.is_test_signal_playing = Boolean(payload.is_test_signal_playing);
    }
    if (payload.active_profile_id !== undefined) {
      state.roomAcoustic.active_profile_id = String(payload.active_profile_id || '');
    }
    if (Array.isArray(payload.profiles)) {
      state.roomAcoustic.profiles = payload.profiles;
    }
    if (payload.active_profile !== undefined) {
      state.roomAcoustic.active_profile = payload.active_profile || null;
    } else if (Array.isArray(state.roomAcoustic.profiles)) {
      state.roomAcoustic.active_profile = state.roomAcoustic.profiles.find(
        (p) => p && String(p.id) === state.roomAcoustic.active_profile_id
      ) || null;
    }

    const activeProf = state.roomAcoustic.active_profile;
    state.roomIsPlayingTestSignal = Boolean(state.roomAcoustic.is_test_signal_playing);
    state.roomActiveProfileId = String(state.roomAcoustic.active_profile_id || '');
    state.roomCorrectionActive = Boolean(state.roomAcoustic.enabled && activeProf);
    state.roomProfileName = activeProf && activeProf.name ? String(activeProf.name) : '';

    if (
      !state.roomIsPlayingTestSignal &&
      state.isMeasuringRoom &&
      !activeRoomMeasureCtx &&
      (!state.nativePickerOpenedAt || (Date.now() - state.nativePickerOpenedAt > 2500))
    ) {
      state.isMeasuringRoom = false;
      state.awaitingNativeRoomFilePicker = false;
      const progWrap = document.getElementById('room-measure-progress-wrap');
      const stopBtn = document.getElementById('btn-stop-room-measure');
      if (progWrap) progWrap.classList.add('hidden');
      if (stopBtn) stopBtn.classList.add('hidden');
    }

    const badgeEl = document.getElementById('room-eq-status-badge');
    const toggleBtn = document.getElementById('btn-room-eq-toggle');
    const selectEl = document.getElementById('room-profile-select');
    const delBtn = document.getElementById('btn-delete-room-profile');
    const descEl = document.getElementById('room-eq-desc');
    const startLabelEl = document.getElementById('btn-start-room-measure-label');
    const uploadBtnEl = document.getElementById('btn-upload-room-audio');

    const hasProfiles = Array.isArray(state.roomAcoustic.profiles) && state.roomAcoustic.profiles.length > 0;
    const isActive = Boolean(state.roomAcoustic.enabled && activeProf);
    const canControlRoomEq = (state.allowRoomMeasurement !== false) || (state.allowDspPresetSelection !== false);

    if (badgeEl) {
      badgeEl.classList.remove('authentic', 'neutral', 'warning');
      if (state.isMeasuringRoom || state.roomAcoustic.is_test_signal_playing) {
        badgeEl.classList.add('warning');
        badgeEl.textContent = IS_EN ? 'MEASURING...' : 'ЗАМЕР АЧХ...';
      } else if (isActive) {
        badgeEl.classList.add('authentic');
        badgeEl.textContent = IS_EN ? 'ACTIVE • CLOUD' : 'АКТИВНА • CLOUD';
      } else {
        badgeEl.classList.add('neutral');
        badgeEl.textContent = hasProfiles ? (IS_EN ? 'BYPASS' : 'ВЫКЛ') : (IS_EN ? 'NO PROFILE' : 'НЕТ ЗАМЕРА');
      }
    }

    if (toggleBtn) {
      toggleBtn.disabled = !hasProfiles || !canControlRoomEq;
      toggleBtn.classList.toggle('active', isActive);
      toggleBtn.setAttribute('aria-pressed', isActive ? 'true' : 'false');
      toggleBtn.textContent = isActive ? (IS_EN ? 'On' : 'Вкл') : (IS_EN ? 'Off' : 'Выкл');
    }

    if (selectEl) {
      selectEl.innerHTML = '';
      if (!hasProfiles) {
        const emptyOpt = document.createElement('option');
        emptyOpt.value = '';
        emptyOpt.textContent = IS_EN ? 'No room profiles yet' : 'Нет профилей замера';
        selectEl.appendChild(emptyOpt);
        selectEl.disabled = true;
      } else {
        selectEl.disabled = !canControlRoomEq;
        state.roomAcoustic.profiles.forEach((p) => {
          if (!p || !p.id) return;
          const opt = document.createElement('option');
          opt.value = String(p.id);
          const bandsCnt = Array.isArray(p.eq_bands) ? p.eq_bands.length : 0;
          opt.textContent = `${p.name || 'Комната'} (${bandsCnt} PEQ)`;
          selectEl.appendChild(opt);
        });
        selectEl.value = state.roomActiveProfileId || '';
      }
    }

    if (delBtn) {
      delBtn.classList.toggle('hidden', !activeProf || state.allowRoomMeasurement === false);
    }

    const canLiveGetUserMedia = Boolean(
      typeof navigator !== 'undefined' &&
      navigator.mediaDevices &&
      typeof navigator.mediaDevices.getUserMedia === 'function'
    );
    if (startLabelEl) {
      startLabelEl.textContent = canLiveGetUserMedia
        ? (IS_EN ? 'Measure Room Mic' : 'Быстрый замер микрофоном')
        : (IS_EN ? 'Measure via iPhone / iPad Mic' : 'Замер микрофоном iPhone / iPad');
    }
    if (uploadBtnEl) {
      uploadBtnEl.classList.toggle('hidden', !canLiveGetUserMedia);
    }

    if (descEl && !state.isMeasuringRoom) {
      if (activeProf) {
        const preGain = Number(activeProf.preamp_gain_db !== undefined ? activeProf.preamp_gain_db : (activeProf.preampGainDB || 0));
        const micLabel = activeProf.measured_on_device || activeProf.mic_device_name || activeProf.micDeviceName || 'iOS Mic';
        descEl.textContent = isActive
          ? `Активен профиль «${activeProf.name}» (${micLabel} • Headroom ${preGain.toFixed(1)} дБ • синхронизирован с iCloud Drive).`
          : `Профиль «${activeProf.name}» сохранён в облаке (${micLabel}). Нажмите «Вкл» для активации 64-bit Auto-PEQ.`;
      } else {
        descEl.textContent = 'Сядьте в точку прослушивания с iPhone / iPad: Mac подаст эталонный розовый шум на АС и построит 64-bit Auto-PEQ фильтр с синхронизацией в iCloud.';
      }
    }

    if (!state.isMeasuringRoom) {
      renderRoomEqChart(activeProf);
    }
    if (!options.skipPermissionsSync) {
      applyDeviceCapabilityPermissionsUI({ fromRoomAcousticUI: true });
    }

    if (!options.skipSignalRefresh) {
      updateSignalPathDetails();
    }
  }

  function stopRoomMeasurementSession(sendStopToServer = true) {
    state.isMeasuringRoom = false;
    state.awaitingNativeRoomFilePicker = false;
    state.nativePickerOpenedAt = 0;
    if (activeRoomMeasureTimer) {
      clearInterval(activeRoomMeasureTimer);
      activeRoomMeasureTimer = null;
    }
    if (activeRoomMeasureStream) {
      try {
        activeRoomMeasureStream.getTracks().forEach((tr) => tr.stop());
      } catch (e) {}
      activeRoomMeasureStream = null;
    }
    if (activeRoomMeasureCtx) {
      try { activeRoomMeasureCtx.close(); } catch (e) {}
      activeRoomMeasureCtx = null;
    }
    if (sendStopToServer && state.connected) {
      send({ action: 'stop_room_test_signal' });
    }
    const progWrap = document.getElementById('room-measure-progress-wrap');
    const stopBtn = document.getElementById('btn-stop-room-measure');
    if (progWrap) progWrap.classList.add('hidden');
    if (stopBtn) stopBtn.classList.add('hidden');
    updateRoomAcousticUI(state.roomAcoustic, { skipSignalRefresh: true });
  }

  function triggerNativeIosMicCapture() {
    if (state.allowRoomMeasurement === false) {
      showToast('Быстрое измерение АЧХ отключено для этого устройства в настройках Mac');
      return;
    }
    const fileInput = document.getElementById('room-mic-file-input');
    if (!fileInput) return;

    state.isMeasuringRoom = true;
    send({ action: 'start_room_test_signal' });

    const progWrap = document.getElementById('room-measure-progress-wrap');
    const progFill = document.getElementById('room-measure-progress-fill');
    const statusTxt = document.getElementById('room-measure-status-text');
    const stopBtn = document.getElementById('btn-stop-room-measure');
    if (progWrap) progWrap.classList.remove('hidden');
    if (progFill) progFill.style.width = '35%';
    if (statusTxt) {
      statusTxt.textContent = 'Розовый шум подан на АС — запишите 5–7 сек на микрофон iPhone/iPad и нажмите «Готово»';
    }
    if (stopBtn) stopBtn.classList.remove('hidden');
    applyDeviceCapabilityPermissionsUI();

    state.awaitingNativeRoomFilePicker = true;
    state.nativePickerOpenedAt = Date.now();
    fileInput.value = '';
    fileInput.click();
  }

  async function startLiveWebAudioRoomMeasurement() {
    if (state.allowRoomMeasurement === false) {
      showToast('Быстрое измерение АЧХ отключено для этого устройства в настройках Mac');
      return;
    }
    const canLive = Boolean(
      typeof navigator !== 'undefined' &&
      navigator.mediaDevices &&
      typeof navigator.mediaDevices.getUserMedia === 'function'
    );
    if (!canLive) {
      triggerNativeIosMicCapture();
      return;
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: false,
          noiseSuppression: false,
          autoGainControl: false
        }
      });
      activeRoomMeasureStream = stream;
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      const ctx = new AudioCtx();
      activeRoomMeasureCtx = ctx;
      if (ctx.state === 'suspended') {
        await ctx.resume();
      }

      const source = ctx.createMediaStreamSource(stream);
      const analyser = ctx.createAnalyser();
      analyser.fftSize = 8192;
      analyser.smoothingTimeConstant = 0.22;
      source.connect(analyser);

      state.isMeasuringRoom = true;
      send({ action: 'start_room_test_signal' });

      const progWrap = document.getElementById('room-measure-progress-wrap');
      const progFill = document.getElementById('room-measure-progress-fill');
      const statusTxt = document.getElementById('room-measure-status-text');
      const stopBtn = document.getElementById('btn-stop-room-measure');
      if (progWrap) progWrap.classList.remove('hidden');
      if (progFill) progFill.style.width = '5%';
      if (stopBtn) stopBtn.classList.remove('hidden');
      applyDeviceCapabilityPermissionsUI();

      const warmupMs = state.isDlnaActive ? 1900 : 650;
      const captureMs = 5400;
      const totalMs = warmupMs + captureMs;
      const startedAt = performance.now();
      const freqBins = new Float32Array(analyser.frequencyBinCount);
      const nyquist = ctx.sampleRate / 2;
      const binHz = nyquist / analyser.frequencyBinCount;
      const bandLinearSums = new Float64Array(ROOM_ISO_BANDS_HZ.length);
      let accumulatedFrames = 0;

      if (statusTxt) {
        statusTxt.textContent = 'Прогрев акустики калибровочным розовым шумом...';
      }

      activeRoomMeasureTimer = setInterval(() => {
        if (!state.isMeasuringRoom) return;
        const elapsed = performance.now() - startedAt;
        const pct = Math.min(100, Math.round((elapsed / totalMs) * 100));
        if (progFill) progFill.style.width = `${pct}%`;

        if (elapsed >= warmupMs) {
          analyser.getFloatFrequencyData(freqBins);
          const instantDb = new Array(ROOM_ISO_BANDS_HZ.length).fill(0);

          for (let b = 0; b < ROOM_ISO_BANDS_HZ.length; b++) {
            const fc = ROOM_ISO_BANDS_HZ[b];
            const fLow = fc / 1.122462;
            const fHigh = fc * 1.122462;
            const kStart = Math.max(1, Math.floor(fLow / binHz));
            const kEnd = Math.min(freqBins.length - 1, Math.ceil(fHigh / binHz));
            let powerSum = 0;
            let count = 0;
            for (let k = kStart; k <= kEnd; k++) {
              const db = freqBins[k];
              if (Number.isFinite(db) && db > -150) {
                powerSum += Math.pow(10, db / 10);
                count++;
              }
            }
            const avgPower = count > 0 ? (powerSum / count) : 1e-12;
            // Pink noise has 1/f power density -> multiply by fc for flat 1/3-octave acoustic response
            const pinkWeighted = avgPower * fc;
            bandLinearSums[b] += pinkWeighted;
            instantDb[b] = 10 * Math.log10(Math.max(pinkWeighted, 1e-15));
          }
          accumulatedFrames++;

          // Normalize live curve around 250 Hz..2 kHz midrange for live visual feedback
          let midSum = 0;
          let midCnt = 0;
          for (let i = 11; i <= 20; i++) {
            midSum += instantDb[i];
            midCnt++;
          }
          const midRef = midCnt > 0 ? (midSum / midCnt) : 0;
          const relLive = instantDb.map((v, idx) => {
            const f = ROOM_ISO_BANDS_HZ[idx];
            const memsComp = f < 55 ? Math.min(5.5, 1.8 * Math.log2(55 / Math.max(f, 20))) : 0;
            return (v - midRef) + memsComp;
          });
          renderRoomEqChart(null, relLive);

          const remSec = Math.max(0, (totalMs - elapsed) / 1000).toFixed(1);
          if (statusTxt) {
            statusTxt.textContent = `Усреднение спектра в точке прослушивания (${remSec} с)...`;
          }
        }

        if (elapsed >= totalMs) {
          const framesCount = Math.max(1, accumulatedFrames);
          const rawBandsDb = [];
          for (let b = 0; b < ROOM_ISO_BANDS_HZ.length; b++) {
            const f = ROOM_ISO_BANDS_HZ[b];
            const meanPwr = bandLinearSums[b] / framesCount;
            const memsComp = f < 55 ? Math.min(5.5, 1.8 * Math.log2(55 / Math.max(f, 20))) : 0;
            rawBandsDb.push(10 * Math.log10(Math.max(meanPwr, 1e-15)) + memsComp);
          }

          stopRoomMeasurementSession(true);

          const dateLabel = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
          const outLabel = state.audioDeviceName || 'Комната';
          const profName = `${outLabel} (${dateLabel})`;
          const sent = send({
            action: 'submit_room_measurement',
            params: {
              name: profName,
              device_name: state.deviceName || 'iPhone / iPad Mic',
              bands_db: rawBandsDb
            }
          });
          if (sent === true) {
            showToast('Замер АЧХ завершён — профиль Auto-PEQ сохранён и синхронизирован с iCloud');
          } else {
            showToast(IS_EN
              ? 'Connection lost — room measurement could not be sent to Mac'
              : 'Соединение потеряно — замер АЧХ не удалось отправить на Mac');
          }
        }
      }, 85);
    } catch (err) {
      stopRoomMeasurementSession(false);
      if (err && (
        err.name === 'NotAllowedError' ||
        err.name === 'PermissionDeniedError' ||
        err.name === 'NotFoundError' ||
        err.name === 'AbortError' ||
        err.name === 'NotReadableError'
      )) {
        showToast(IS_EN
          ? 'Microphone access denied or unavailable'
          : 'Доступ к микрофону запрещён или микрофон недоступен');
        return;
      }
      triggerNativeIosMicCapture();
    }
  }

  async function handleUploadedRoomAudioFile(file) {
    if (!file) {
      stopRoomMeasurementSession(true);
      return;
    }
    send({ action: 'stop_room_test_signal' });
    const progWrap = document.getElementById('room-measure-progress-wrap');
    const progFill = document.getElementById('room-measure-progress-fill');
    const statusTxt = document.getElementById('room-measure-status-text');
    if (progWrap) progWrap.classList.remove('hidden');
    if (progFill) progFill.style.width = '80%';
    if (statusTxt) {
      statusTxt.textContent = 'Расчёт 4096-pt vDSP FFT и синтез 64-bit Auto-PEQ на Mac...';
    }

    try {
      const rawName = String(file.name || 'capture.m4a');
      const dotIdx = rawName.lastIndexOf('.');
      const ext = dotIdx >= 0 ? rawName.slice(dotIdx + 1).toLowerCase() : 'm4a';
      const dateLabel = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
      const outLabel = state.audioDeviceName || 'Комната';
      const profName = `${outLabel} (${dateLabel})`;

      const qs = new URLSearchParams({
        ext,
        name: profName,
        device_name: state.deviceName || 'iPhone / iPad Mic',
        device_id: state.deviceId
      });
      const resp = await fetch(`/api/room-measurement/analyze?${qs.toString()}`, {
        method: 'POST',
        headers: buildDeviceAuthHeaders({
          'Content-Type': file.type || 'application/octet-stream'
        }),
        body: file
      });
      const json = await resp.json();
      stopRoomMeasurementSession(false);
      if (!resp.ok || json.status === 'error') {
        showToast(json.error || json.message || 'Не удалось распознать аудиозапись микрофона');
        return;
      }
      updateRoomAcousticUI(json.room_acoustic || json);
      showToast('Профиль АЧХ комнаты создан и синхронизирован с iCloud');
    } catch (err) {
      stopRoomMeasurementSession(false);
      showToast('Ошибка отправки записи микрофона на Mac');
    }
  }

  function setupRoomAcousticControls() {
    const toggleBtn = document.getElementById('btn-room-eq-toggle');
    const selectEl = document.getElementById('room-profile-select');
    const delBtn = document.getElementById('btn-delete-room-profile');
    const startBtn = document.getElementById('btn-start-room-measure');
    const uploadBtn = document.getElementById('btn-upload-room-audio');
    const stopBtn = document.getElementById('btn-stop-room-measure');
    const fileInput = document.getElementById('room-mic-file-input');

    renderRoomEqChart(null);

    if (toggleBtn) {
      toggleBtn.addEventListener('click', () => {
        if (state.allowRoomMeasurement === false && state.allowDspPresetSelection === false) {
          showToast(IS_EN
            ? 'Room EQ control is disabled for this device on Mac'
            : 'Управление коррекцией комнаты отключено для этого устройства в настройках Mac');
          updateRoomAcousticUI(state.roomAcoustic);
          return;
        }
        triggerHaptic('toggle');
        const nextEnabled = !(state.roomAcoustic && state.roomAcoustic.enabled);
        send({
          action: 'set_room_correction_enabled',
          params: { enabled: nextEnabled }
        });
      });
    }

    if (selectEl) {
      selectEl.addEventListener('change', () => {
        if (state.allowRoomMeasurement === false && state.allowDspPresetSelection === false) {
          showToast(IS_EN
            ? 'Room EQ profile selection is disabled for this device on Mac'
            : 'Выбор профиля АЧХ отключён для этого устройства в настройках Mac');
          updateRoomAcousticUI(state.roomAcoustic);
          return;
        }
        if (!selectEl.value) return;
        triggerHaptic('light');
        send({
          action: 'select_room_profile',
          params: { profile_id: selectEl.value }
        });
      });
    }

    if (delBtn) {
      delBtn.addEventListener('click', () => {
        const prof = state.roomAcoustic && state.roomAcoustic.active_profile;
        if (!prof || !prof.id) return;
        triggerHaptic('light');
        send({
          action: 'delete_room_profile',
          params: { profile_id: prof.id }
        });
        showToast(`Профиль «${prof.name || 'АЧХ'}» удалён`);
      });
    }

    if (startBtn) {
      startBtn.addEventListener('click', () => {
        triggerHaptic('light');
        startLiveWebAudioRoomMeasurement();
      });
    }

    if (uploadBtn) {
      uploadBtn.addEventListener('click', () => {
        triggerHaptic('light');
        triggerNativeIosMicCapture();
      });
    }

    if (stopBtn) {
      stopBtn.addEventListener('click', () => {
        triggerHaptic('light');
        stopRoomMeasurementSession(true);
      });
    }

    if (fileInput) {
      fileInput.addEventListener('change', (e) => {
        state.awaitingNativeRoomFilePicker = false;
        const f = e.target.files && e.target.files[0];
        if (f) {
          handleUploadedRoomAudioFile(f);
        } else {
          stopRoomMeasurementSession(true);
        }
      });

      fileInput.addEventListener('cancel', () => {
        state.awaitingNativeRoomFilePicker = false;
        if (state.isMeasuringRoom || state.roomIsPlayingTestSignal || (state.roomAcoustic && state.roomAcoustic.is_test_signal_playing)) {
          stopRoomMeasurementSession(true);
        }
      });

      window.addEventListener('focus', () => {
        if (!state.awaitingNativeRoomFilePicker) return;
        setTimeout(() => {
          if (state.awaitingNativeRoomFilePicker && (!fileInput.files || fileInput.files.length === 0)) {
            state.awaitingNativeRoomFilePicker = false;
            if (state.isMeasuringRoom || state.roomIsPlayingTestSignal || (state.roomAcoustic && state.roomAcoustic.is_test_signal_playing)) {
              stopRoomMeasurementSession(true);
            }
          }
        }, 700);
      });
    }
  }
