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
    state.isRadio = isRadioNow;

    if (incomingState !== 'playing') {
      state.pendingPauseUntil = 0;
    }

    if (state.isAiCurating) {
      // Do not dismiss the busy spinner while the Mac is still generating the AI selection
    } else if (state.waitingForPlayback) {
      // We are waiting for a newly launched track/queue to start.
      // Do NOT dismiss spinner if player is still reporting the OLD track!
      const hasTrackChanged = Boolean(isNewTrack && incomingSig && incomingSig !== state.waitingTrackSignature);
      const matchesExpectedTrack = Boolean(
        state.waitingExpectedTrackName &&
        incomingTrack &&
        incomingTrack.name &&
        incomingTrack.name.trim().toLowerCase() === state.waitingExpectedTrackName
      );
      const isTargetPlaying = Boolean(
        state.waitingTargetName &&
        !state.waitingTrackSignature &&
        ((data.playlist && data.playlist.toLowerCase().includes(state.waitingTargetName.toLowerCase())) ||
         (incomingTrack && incomingTrack.name && incomingTrack.name.toLowerCase().includes(state.waitingTargetName.toLowerCase())))
      );
      const elapsedWaitMs = Date.now() - (state.waitingStartTime || 0);
      const hasWaitedEnough = state.waitingTrackSignature ? (elapsedWaitMs > 6000) : (elapsedWaitMs > 600);
      if ((incomingState === 'playing' && (hasTrackChanged || matchesExpectedTrack || isTargetPlaying || hasWaitedEnough)) || (isRadioNow && (state.isLaunchingStation || state.waitingIsStation))) {
        state.pendingPlayUntil = 0;
        state.pendingPauseUntil = 0;
        state.playerState = 'playing';
        state.waitingForPlayback = false;
        state.waitingTrackSignature = null;
        state.waitingExpectedTrackName = null;
        state.waitingIsStation = false;
        state.isLaunchingStation = false;
        if (state.stationLaunchTimeout) {
          clearTimeout(state.stationLaunchTimeout);
          state.stationLaunchTimeout = null;
        }
        setUIBusy(false);
      }
    } else if (state.pendingPauseUntil && Date.now() < state.pendingPauseUntil && incomingState === 'playing') {
      state.playerState = 'paused';
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

    // Dynamic initial view: on first player state / status message after initial page load
    if (!state.initialViewSelected) {
      state.initialViewSelected = true;
      if (isDesktopLayout()) {
        const detailOpen = Boolean(
          (dom.playlistDetailPane && !dom.playlistDetailPane.classList.contains('hidden')) ||
          (dom.libraryArtistDetailPane && !dom.libraryArtistDetailPane.classList.contains('hidden'))
        );
        switchDesktopTab(state.desktopActiveTab || 'home', detailOpen);
      } else if (state.playbackState === 'playing') {
        switchMobileView('view-now-playing');
      } else {
        switchMobileView('view-home');
      }
    }

    state.duration = Number(data.duration) || 0;
    const reportedPos = Math.max(0, Number(data.position) || 0);
    if (data.is_buffering !== undefined || data.isBuffering !== undefined) {
      state.isBuffering = Boolean(data.is_buffering !== undefined ? data.is_buffering : data.isBuffering);
    } else if (state.playerState !== 'playing' || reportedPos > 0.08) {
      state.isBuffering = false;
    }
    if (data.is_stream_stalled !== undefined || data.isStreamStalled !== undefined) {
      state.isStreamStalled = Boolean(data.is_stream_stalled !== undefined ? data.is_stream_stalled : data.isStreamStalled);
    } else if (state.playerState !== 'playing' || reportedPos > 0.08) {
      state.isStreamStalled = false;
    }
    const rawStagingBuffer = data.is_staging_buffer !== undefined ? data.is_staging_buffer : data.isStagingBuffer;
    if (rawStagingBuffer !== undefined) {
      state.isStagingBuffer = Boolean(rawStagingBuffer) && state.playerState === 'playing' && reportedPos <= 0.08;
    } else if (state.playerState !== 'playing' || reportedPos > 0.08 || !state.isBuffering) {
      state.isStagingBuffer = false;
    }
    const rawLoadingStage = data.loading_stage !== undefined ? data.loading_stage : data.loadingStage;
    if (state.playerState !== 'playing' || (!state.isBuffering && !state.isStagingBuffer) || reportedPos > 0.08) {
      state.loadingStage = null;
      state.loadingStartedAtMs = 0;
    } else {
      const nextStage = state.isStagingBuffer ? 'buffer' : (rawLoadingStage || 'cloud');
      if (isNewTrack || !state.loadingStartedAtMs || (nextStage === 'buffer' && state.loadingStage !== 'buffer')) {
        state.loadingStartedAtMs = Date.now();
      }
      state.loadingStage = nextStage;
    }

    if (isNewTrack) {
      state.hasStartedAdvancingForTrack = reportedPos > 0.08;
      state.lastSyncPos = reportedPos;
      state.position = reportedPos;
      state.lastSyncTime = performance.now();
      state.lastSyncPerf = state.lastSyncTime;
      if (!state.isScrubbing) {
        updateScrubberUI(reportedPos, state.duration);
      }
    } else if (!state.isScrubbing) {
      if (reportedPos > 0.08) {
        state.hasStartedAdvancingForTrack = true;
      }
      const now = performance.now();
      const waitingForFirstAudioFrame = state.isBuffering || (!state.hasStartedAdvancingForTrack && reportedPos <= 0.08);
      if (state.playerState !== 'playing' || waitingForFirstAudioFrame) {
        state.lastSyncPos = reportedPos;
        state.position = reportedPos;
        state.lastSyncTime = now;
        state.lastSyncPerf = now;
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
          state.position = reportedPos;
          state.lastSyncTime = now;
          state.lastSyncPerf = now;
          updateScrubberUI(reportedPos, state.duration);
        } else {
          // Continuous smooth drift synchronization (Phase-Locked Loop):
          // Smoothly absorb clock drift without ever causing a visible jump/jitter.
          // By applying a 15% damping correction per broadcast, client clock matches
          // server clock within a fraction of a second without jitter.
          state.lastSyncPos = predictedPos + diff * 0.15;
          state.position = state.lastSyncPos;
          state.lastSyncTime = now;
          state.lastSyncPerf = now;
        }
      }
    }

    const incomingShuffle = isRadioNow ? false : Boolean(data.shuffle);
    if (isRadioNow) {
      state.shuffle = false;
      state.pendingShuffleUntil = 0;
    } else if (!state.pendingShuffleUntil || Date.now() >= state.pendingShuffleUntil) {
      state.shuffle = incomingShuffle;
    } else if (incomingShuffle === state.shuffle) {
      state.pendingShuffleUntil = 0;
    }

    let incomingRepeat = normalizeRepeatMode(data.repeat || data.repeat_mode || data.repeatMode || 'off');
    if (isRadioNow && incomingRepeat === 'all') {
      incomingRepeat = 'off';
    }
    if (!state.pendingRepeatUntil || Date.now() >= state.pendingRepeatUntil) {
      state.repeatMode = incomingRepeat;
    } else if (incomingRepeat === state.repeatMode) {
      state.pendingRepeatUntil = 0;
    }
    if (isRadioNow && state.repeatMode === 'all') {
      state.repeatMode = 'off';
      state.pendingRepeatUntil = 0;
    }
    state.audioQuality = data.audio_quality || data.audioQuality || 'Lossless (ALAC 24-bit/48kHz)';
    if (newTrack && state.pendingFavoriteUntil && Date.now() < state.pendingFavoriteUntil) {
      const incomingKey = `${newTrack.artist || ''}|${newTrack.name || ''}`;
      if (state.pendingFavoriteTrackKey === incomingKey) {
        newTrack.favorited = state.pendingFavoriteValue;
      }
    }
    state.track = newTrack;
    state.currentTrackId = (newTrack && (newTrack.id || newTrack.persistent_id || newTrack.numeric_id)) || 0;

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
    if (data.dac_muting_guard_enabled !== undefined || data.isDacMutingGuardEnabled !== undefined) {
      state.dacMutingGuardEnabled = data.dac_muting_guard_enabled !== undefined ? Boolean(data.dac_muting_guard_enabled) : Boolean(data.isDacMutingGuardEnabled);
    }
    if (data.dac_muting_guard_ms !== undefined || data.dacMutingGuardMs !== undefined) {
      state.dacMutingGuardMs = Number(data.dac_muting_guard_ms || data.dacMutingGuardMs) || 100;
    }
    const prevDlnaActive = Boolean(state.isDlnaActive);
    if (data.is_dlna_active !== undefined || data.isDlnaActive !== undefined) {
      state.isDlnaActive = Boolean(data.is_dlna_active !== undefined ? data.is_dlna_active : data.isDlnaActive);
    }
    const dlnaActiveChanged = (Boolean(state.isDlnaActive) !== prevDlnaActive);
    if (data.room_correction_active !== undefined || data.roomCorrectionActive !== undefined) {
      state.roomCorrectionActive = Boolean(data.room_correction_active !== undefined ? data.room_correction_active : data.roomCorrectionActive);
    }
    if (data.room_profile_name !== undefined || data.roomProfileName !== undefined) {
      state.roomProfileName = String(data.room_profile_name || data.roomProfileName || '');
    }
    if (data.late_night_drc_profile !== undefined || data.lateNightDrcProfile !== undefined) {
      const nextProf = String(data.late_night_drc_profile !== undefined ? data.late_night_drc_profile : data.lateNightDrcProfile || 'gentle');
      if (nextProf === 'gentle' || nextProf === 'concert') {
        state.lateNightDrcProfile = nextProf;
      }
    }
    if (data.late_night_drc_enabled !== undefined || data.lateNightDrcEnabled !== undefined) {
      state.lateNightDrcEnabled = Boolean(data.late_night_drc_enabled !== undefined ? data.late_night_drc_enabled : data.lateNightDrcEnabled);
    }
    if (data.late_night_drc_mode !== undefined || data.lateNightDrcMode !== undefined) {
      const nextDrc = String(data.late_night_drc_mode !== undefined ? data.late_night_drc_mode : data.lateNightDrcMode || 'off');
      state.lateNightDrcMode = nextDrc;
      if (nextDrc === 'gentle' || nextDrc === 'concert') {
        state.lateNightDrcProfile = nextDrc;
        if (data.late_night_drc_enabled === undefined && data.lateNightDrcEnabled === undefined) {
          state.lateNightDrcEnabled = true;
        }
      } else if (data.late_night_drc_enabled === undefined && data.lateNightDrcEnabled === undefined) {
        state.lateNightDrcEnabled = false;
      }
    } else if (data.late_night_drc_enabled !== undefined || data.lateNightDrcEnabled !== undefined || data.late_night_drc_profile !== undefined || data.lateNightDrcProfile !== undefined) {
      state.lateNightDrcMode = state.lateNightDrcEnabled ? (state.lateNightDrcProfile || 'gentle') : 'off';
    }
    if (data.late_night_drc_gain_db !== undefined || data.lateNightDrcGainDb !== undefined) {
      state.lateNightDrcGainDb = Number(data.late_night_drc_gain_db !== undefined ? data.late_night_drc_gain_db : data.lateNightDrcGainDb) || 0;
    }
    syncLateNightBadgeOnly();
    if (data.mastering_declip_mode !== undefined || data.masteringDeclipMode !== undefined) {
      const nextDc = String(data.mastering_declip_mode !== undefined ? data.mastering_declip_mode : data.masteringDeclipMode || 'off');
      state.masteringDeclipMode = (nextDc === 'auto' || nextDc === 'gentle' || nextDc === 'studio') ? nextDc : 'off';
    }
    if (data.mastering_declip_restored_db !== undefined || data.masteringDeclipRestoredDb !== undefined) {
      state.masteringDeclipRestoredDb = Number(data.mastering_declip_restored_db !== undefined ? data.mastering_declip_restored_db : data.masteringDeclipRestoredDb) || 0;
    }
    if (data.mastering_deesser_mode !== undefined || data.masteringDeesserMode !== undefined) {
      const nextDe = String(data.mastering_deesser_mode !== undefined ? data.mastering_deesser_mode : data.masteringDeesserMode || 'off');
      state.masteringDeesserMode = (nextDe === 'gentle' || nextDe === 'vocal') ? nextDe : 'off';
    }
    if (data.mastering_deesser_gain_db !== undefined || data.masteringDeesserGainDb !== undefined) {
      state.masteringDeesserGainDb = Number(data.mastering_deesser_gain_db !== undefined ? data.mastering_deesser_gain_db : data.masteringDeesserGainDb) || 0;
    }
    syncMasteringRestorationBadgesOnly();
    if (data.dsp_mode !== undefined || data.dspMode !== undefined) {
      state.dspMode = data.dsp_mode || data.dspMode || 'passthrough';
    }
    if (data.dsp_badge !== undefined || data.dspBadge !== undefined) {
      state.dspBadge = data.dsp_badge || data.dspBadge || '';
    }
    if (data.dsp_profile !== undefined || data.dspProfile !== undefined) {
      state.dspProfile = data.dsp_profile || data.dspProfile || '7EC-Balanced';
    }
    if (data.dsp_output_sample_rate !== undefined || data.dspOutputSampleRate !== undefined) {
      state.dspOutputSampleRate = Number(data.dsp_output_sample_rate || data.dspOutputSampleRate) || 0;
    }
    if (data.dsp_dop_carrier_rate !== undefined || data.dspDoPCarrierRate !== undefined) {
      state.dspDoPCarrierRate = Number(data.dsp_dop_carrier_rate || data.dspDoPCarrierRate) || 0;
    }
    if (data.dsp_is_hog_mode !== undefined || data.dspIsHogMode !== undefined) {
      state.dspIsHogMode = Boolean(data.dsp_is_hog_mode !== undefined ? data.dsp_is_hog_mode : data.dspIsHogMode);
    }
    if (data.dsp_is_integer_mode !== undefined || data.dspIsIntegerMode !== undefined) {
      state.dspIsIntegerMode = Boolean(data.dsp_is_integer_mode !== undefined ? data.dsp_is_integer_mode : data.dspIsIntegerMode);
    }
    if (data.dsp_cpu_load_percent !== undefined || data.dspCpuLoadPercent !== undefined) {
      state.dspCpuLoadPercent = Number(data.dsp_cpu_load_percent !== undefined ? data.dsp_cpu_load_percent : data.dspCpuLoadPercent) || 0;
    }
    if (data.dsp_ring_buffer_fill_percent !== undefined || data.dspRingBufferFillPercent !== undefined) {
      state.dspRingBufferFillPercent = Number(data.dsp_ring_buffer_fill_percent !== undefined ? data.dsp_ring_buffer_fill_percent : data.dspRingBufferFillPercent) || 0;
    }
    const hasTrackSwitched = Boolean(
      oldTrack && newTrack && (newTrack.name !== oldTrack.name || newTrack.artist !== oldTrack.artist)
    );
    const incomingSa = data.spectral_analysis || data.spectralAnalysis;
    if (hasTrackSwitched) {
      spectralPollTickCount = 0;
      const prevEnabled = incomingSa && incomingSa.is_enabled !== undefined
        ? Boolean(incomingSa.is_enabled)
        : (state.spectralAnalysis ? (state.spectralAnalysis.is_enabled !== false && state.spectralAnalysis.isEnabled !== false) : true);
      state.spectralAnalysis = Object.assign({}, incomingSa || {}, {
        is_enabled: prevEnabled,
        verdict: (incomingSa && (incomingSa.is_cached || incomingSa.isCached) && incomingSa.verdict) ? incomingSa.verdict : (prevEnabled ? 'analyzing' : 'disabled'),
        analyzed_frames_count: 0
      });
    } else if (incomingSa) {
      state.spectralAnalysis = incomingSa;
    }

    if (data.lock_volume_100 !== undefined) {
      state.lockVolume100 = Boolean(data.lock_volume_100);
      try { localStorage.setItem('amr_lock_volume_100', String(state.lockVolume100)); } catch (e) {}
    } else if (data.isVolumeLockedTo100 !== undefined) {
      state.lockVolume100 = Boolean(data.isVolumeLockedTo100);
      try { localStorage.setItem('amr_lock_volume_100', String(state.lockVolume100)); } catch (e) {}
    }

    if (data.amp_volume_control !== undefined) {
      state.ampVolumeControlEnabled = Boolean(data.amp_volume_control) && state.lockVolume100;
    } else if (!state.lockVolume100) {
      state.ampVolumeControlEnabled = false;
    }
    if (data.amp_brand_name !== undefined && data.amp_brand_name) {
      state.ampBrandName = String(data.amp_brand_name);
    }
    if (data.amp_max_volume !== undefined && Number(data.amp_max_volume) > 0) {
      state.ampMaxVolume = Number(data.amp_max_volume);
    }
    const prevVol = state.volume;
    const prevMute = state.ampMuted;
    if (data.amp_muted !== undefined) {
      state.ampMuted = Boolean(data.amp_muted);
    }
    if (data.amp_connected !== undefined) {
      state.ampConnected = Boolean(data.amp_connected);
    }
    if (data.amp_volume !== undefined && data.amp_volume !== null) {
      state.ampVolume = Math.max(0, Math.min(state.ampMaxVolume || 100, Number(data.amp_volume)));
    }
    if (data.amp_soundcheck_enabled !== undefined) {
      state.ampSoundCheckEnabled = Boolean(data.amp_soundcheck_enabled);
    }
    if (data.amp_soundcheck_gain_db !== undefined) {
      state.ampSoundCheckGainDb = data.amp_soundcheck_gain_db !== null ? Number(data.amp_soundcheck_gain_db) : null;
    }
    if (data.amp_soundcheck_offset !== undefined) {
      state.ampSoundCheckOffset = data.amp_soundcheck_offset !== null ? Number(data.amp_soundcheck_offset) : 0;
    }
    if (data.amp_base_volume !== undefined && data.amp_base_volume !== null) {
      state.ampBaseVolume = Number(data.amp_base_volume);
    }

    const maxVol = (state.lockVolume100 && state.ampVolumeControlEnabled) ? (state.ampMaxVolume || 80) : 100;
    if (data.volume !== undefined && !state.isDraggingVolume) {
      state.volume = Math.max(0, Math.min(maxVol, Number(data.volume)));
      if (state.volume >= 5) {
        state.previousVolume = state.volume;
      }
    }
    if (!state.isDraggingVolume && !(state.lockVolume100 && !state.ampVolumeControlEnabled) && state.initialViewSelected && (state.volume !== prevVol || state.ampMuted !== prevMute)) {
      triggerStandbyVolumePulse();
    }

    if (dlnaActiveChanged) {
      if (state.lastDspSettings && typeof state.lastDspSettings === 'object') {
        state.lastDspSettings = Object.assign({}, state.lastDspSettings, { is_dlna_active: state.isDlnaActive });
        updateDSPSettingsUI(state.lastDspSettings);
      } else {
        applyDeviceCapabilityPermissionsUI();
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
      return appendDeviceIdToUrl(track.artworkUrl);
    }
    if (track.artwork_url && track.artwork_url.length > 5) {
      return appendDeviceIdToUrl(track.artwork_url);
    }
    if (track.artwork && track.artwork.length > 5) {
      return appendDeviceIdToUrl(track.artwork);
    }
    if (track.artwork_data_base64) {
      return `data:image/jpeg;base64,${track.artwork_data_base64}`;
    }
    if (track.is_local && track.id && Number(track.id) > 0) {
      return appendDeviceIdToUrl(`/api/artwork/track?id=${track.id}`);
    }
    if (track.name) {
      const q = new URLSearchParams();
      q.set('name', track.name);
      if (track.artist) q.set('artist', track.artist);
      if (track.album) q.set('album', track.album);
      return appendDeviceIdToUrl(`/api/artwork/search?${q.toString()}`);
    }
    if (track.id && Number(track.id) > 0) {
      return appendDeviceIdToUrl(`/api/artwork/track?id=${track.id}`);
    }
    return appendDeviceIdToUrl('/api/artwork');
  }
