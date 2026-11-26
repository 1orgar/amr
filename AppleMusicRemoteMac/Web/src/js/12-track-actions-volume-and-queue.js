  function openTrackAlbumForTarget(targetTrack, explicitOrigin = '') {
    const t = targetTrack || state.track;
    const albumName = t && (t.album || t.collectionName) ? String(t.album || t.collectionName).trim() : '';
    if (!albumName) return;
    triggerHaptic('light');
    if (typeof bookletState !== 'undefined' && bookletState.isOpen) {
      closeBookletViewer();
    }
    const art = getArtworkSrc(t);
    const origin = explicitOrigin || resolveCurrentBrowseOrigin();
    openAlbumDetail({
      id: t.album_id || t.collectionId || '',
      name: albumName,
      artist: (t && (t.artist || t.artistName)) ? (t.artist || t.artistName) : '',
      artwork: art,
      url: ''
    }, origin, { source: 'catalog' });
  }

  function openCurrentTrackAlbum() {
    openTrackAlbumForTarget(state.track, isDesktopLayout() ? resolveCurrentBrowseOrigin() : 'player');
  }

  if (dom.btnGoToAlbum) {
    dom.btnGoToAlbum.addEventListener('click', () => {
      const target = getActiveActionTrack();
      const origin = state.actionTargetTrack ? resolveCurrentBrowseOrigin() : (isDesktopLayout() ? resolveCurrentBrowseOrigin() : 'player');
      closeStationPickerModal();
      openTrackAlbumForTarget(target, origin);
    });
  }

  if (dom.playerAlbum) {
    dom.playerAlbum.addEventListener('click', openCurrentTrackAlbum);
  }

  function triggerAiMixFromTrack(targetTrack) {
    triggerHaptic('medium');
    const t = targetTrack || state.track;
    closeStationPickerModal();
    const trackName = (t && (t.name || t.trackName)) ? String(t.name || t.trackName).trim() : '';
    const artistName = (t && (t.artist || t.artistName)) ? String(t.artist || t.artistName).trim() : '';
    const albumName = (t && (t.album || t.collectionName)) ? String(t.album || t.collectionName).trim() : '';
    if (!trackName) {
      showToast(translateTextToEn('Сначала запустите трек для ИИ-подбора по вайбу'));
      return;
    }
    const sbAiVibeBtn = document.getElementById('standby-btn-ai-track-vibe');
    [dom.btnAiTrackVibe, sbAiVibeBtn].forEach((b) => {
      if (!b) return;
      b.classList.add('loading-pulse');
      setTimeout(() => b.classList.remove('loading-pulse'), 2200);
    });
    state.isAiCurating = true;
    state.pendingStandbyAiAutoPlay = true;
    state.aiCurateReqSeq = (state.aiCurateReqSeq || 0) + 1;
    state.lastAiCurateSentAt = Date.now();
    const reqId = state.aiCurateReqSeq;
    setUIBusy(true, translateTextToEn(`✨ ИИ-подбор по вайбу «${trackName}»...`));
    send({
      action: 'ai_curate_from_track',
      request_id: reqId,
      params: {
        name: trackName,
        artist: artistName,
        album: albumName,
        country: getActiveStorefront(),
        auto_play: true,
        request_id: reqId
      }
    });
  }

  function triggerAiMixFromCurrentTrack() {
    triggerAiMixFromTrack(state.track);
  }

  if (dom.btnAiTrackVibe) {
    dom.btnAiTrackVibe.addEventListener('click', () => triggerAiMixFromTrack(state.track));
  }

  if (dom.btnAiMixByTrack) {
    dom.btnAiMixByTrack.addEventListener('click', () => triggerAiMixFromTrack(getActiveActionTrack()));
  }

  if (dom.btnSonicBridgeByTrack) {
    dom.btnSonicBridgeByTrack.addEventListener('click', () => {
      triggerHaptic('light');
      const t = getActiveActionTrack();
      const trackText = (t && (t.name || t.trackName)) ? String(t.name || t.trackName).trim() : '';
      const artistText = (t && (t.artist || t.artistName)) ? String(t.artist || t.artistName).trim() : '';
      if (!trackText) {
        showToast(IS_EN ? 'Start a track first to launch Sonic Bridge' : 'Сначала запустите трек для старта Sonic Bridge');
        return;
      }
      closeStationPickerModal();
      state.sonicBridgeFrom = artistText ? `${artistText} — ${trackText}` : trackText;
      openSonicBridgeTab(true);
    });
  }

  function syncStationPickerModalUI() {
    const t = getActiveActionTrack();
    const trackText = (t && (t.name || t.trackName)) ? String(t.name || t.trackName).trim() : '';
    const artistText = (t && (t.artist || t.artistName)) ? String(t.artist || t.artistName).trim() : '';
    const albumText = (t && (t.album || t.collectionName)) ? String(t.album || t.collectionName).trim() : '';

    if (dom.stationModalTrackBanner) {
      dom.stationModalTrackBanner.classList.toggle('hidden', !trackText);
      if (trackText) {
        if (dom.stationModalTrackArt) {
          delete dom.stationModalTrackArt.dataset.fallbackApplied;
          dom.stationModalTrackArt.dataset.fallbackIcon = 'apple-touch-icon.svg';
          dom.stationModalTrackArt.src = getArtworkSrc(t);
        }
        if (dom.stationModalTrackTitle) dom.stationModalTrackTitle.textContent = trackText;
        if (dom.stationModalTrackSub) {
          dom.stationModalTrackSub.textContent = [artistText, albumText].filter(Boolean).join(' • ') || 'Apple Music';
        }
      }
    }

    const canModifyLib = state.allowLibraryModification !== false;
    const inLib = Boolean(t && trackText && isTrackInLibraryClient(t));
    if (dom.btnAddTrackLibrary) {
      dom.btnAddTrackLibrary.classList.toggle('hidden', !canModifyLib || !trackText || inLib);
    }
    if (dom.btnRemoveTrackLibrary) {
      dom.btnRemoveTrackLibrary.classList.toggle('hidden', !canModifyLib || !trackText || !inLib);
    }

    const libArtist = artistText ? findMatchingLibraryArtist(artistText) : null;
    const artistInLib = Boolean(libArtist || (inLib && artistText));
    if (dom.btnGoToLibraryArtist) {
      dom.btnGoToLibraryArtist.classList.toggle('hidden', !artistInLib);
      if (dom.stationOptLibArtistName) {
        dom.stationOptLibArtistName.textContent = artistText || '—';
      }
    }
    if (dom.btnRemoveArtistLibrary) {
      dom.btnRemoveArtistLibrary.classList.toggle('hidden', !canModifyLib || !artistInLib);
      if (dom.stationOptRemoveArtistSub) {
        const cnt = libArtist && libArtist.track_count ? Number(libArtist.track_count) : 0;
        dom.stationOptRemoveArtistSub.textContent = cnt > 0
          ? `${artistText} • ${formatTracksCount(cnt)}`
          : (artistText || '—');
      }
    }

    const btnOpenBookletModal = document.getElementById('btn-open-booklet');
    if (btnOpenBookletModal && state.actionTargetTrack) {
      const curAlb = (state.track && state.track.album) ? state.track.album.trim().toLowerCase() : '';
      if (!albumText || albumText.toLowerCase() !== curAlb) {
        btnOpenBookletModal.classList.add('hidden');
      }
    }

    if (dom.stationOptAlbumName) {
      dom.stationOptAlbumName.textContent = albumText || translateTextToEn('Не указан');
    }
    if (dom.btnGoToAlbum) {
      dom.btnGoToAlbum.disabled = !albumText;
    }
    if (dom.btnAiMixByTrack) {
      dom.btnAiMixByTrack.disabled = !trackText;
      dom.btnAiMixByTrack.classList.toggle('hidden', !state.aiCuratorEnabled);
    }
    if (dom.stationOptAiVibeSub) {
      dom.stationOptAiVibeSub.textContent = trackText
        ? `${artistText ? artistText + ' — ' : ''}${trackText}`
        : translateTextToEn('Бесконечная волна 20+ треков по атмосфере');
    }
    if (dom.btnSonicBridgeByTrack) {
      dom.btnSonicBridgeByTrack.disabled = !trackText;
      dom.btnSonicBridgeByTrack.classList.toggle('hidden', !state.aiCuratorEnabled);
    }
    if (dom.stationOptSonicBridgeSub) {
      dom.stationOptSonicBridgeSub.textContent = trackText
        ? `${artistText ? artistText + ' — ' : ''}${trackText} → ...`
        : translateTextToEn('Плавный ИИ-маршрут к другому треку или артисту');
    }
    if (dom.stationOptTrackName) {
      dom.stationOptTrackName.textContent = trackText || translateTextToEn('Не играет');
    }
    if (dom.stationOptArtistName) {
      dom.stationOptArtistName.textContent = artistText || 'Apple Music';
    }
    if (dom.btnStationByTrack) {
      dom.btnStationByTrack.disabled = !trackText;
    }
    if (dom.btnStationByArtist) {
      dom.btnStationByArtist.disabled = !artistText;
    }
  }

  function openTrackActionsModal(customTrack = null) {
    triggerHaptic('light');
    state.actionTargetTrack = customTrack || null;
    if (!state.librarySongsLoaded && state.connected && state.deviceAuthorized) {
      send({ action: 'get_library_songs' });
    }
    if (!state.libraryArtistsLoaded && state.connected && state.deviceAuthorized) {
      send({ action: 'get_library_artists' });
    }
    syncStationPickerModalUI();
    if (!customTrack) {
      syncCurrentTrackBookletAvailability();
    }
    if (dom.stationPickerModal) {
      dom.stationPickerModal.classList.remove('hidden');
      dom.stationPickerModal.setAttribute('aria-hidden', 'false');
    }
  }

  if (dom.btnCreateStation) {
    dom.btnCreateStation.addEventListener('click', () => {
      openTrackActionsModal(null);
    });
  }

  if (dom.btnAddTrackLibrary) {
    dom.btnAddTrackLibrary.addEventListener('click', () => {
      const t = getActiveActionTrack();
      if (!t || !(t.name || t.trackName)) return;
      triggerHaptic('medium');
      const tName = String(t.name || t.trackName || '').trim();
      const tArtist = String(t.artist || t.artistName || '').trim();
      const tAlbum = String(t.album || t.collectionName || '').trim();
      const tCatId = String(t.catalog_id || t.catalogId || t.id || t.trackId || '').trim();
      const tNumId = Number(t.numeric_id || t.numericId || 0);
      state.lastLibraryAddTarget = 'track';
      t.is_local = true;
      closeStationPickerModal();
      send({
        action: 'add_to_library',
        params: {
          id: tCatId,
          track_id: tNumId > 0 ? tNumId : undefined,
          name: tName,
          artist: tArtist,
          album: tAlbum,
          url: t.url || ''
        }
      });
    });
  }

  if (dom.btnRemoveTrackLibrary) {
    dom.btnRemoveTrackLibrary.addEventListener('click', () => {
      const t = getActiveActionTrack();
      closeStationPickerModal();
      if (t) {
        promptRemoveTrackFromLibrary(t);
      }
    });
  }

  if (dom.btnGoToLibraryArtist) {
    dom.btnGoToLibraryArtist.addEventListener('click', () => {
      const t = getActiveActionTrack();
      const artistName = t ? String(t.artist || t.artistName || '').trim() : '';
      closeStationPickerModal();
      if (!artistName) return;
      const libArt = findMatchingLibraryArtist(artistName) || { name: artistName };
      navigateToView('view-library', 'library', true);
      switchLibrarySubtab('artists', false);
      openLibraryArtistDetail(libArt);
    });
  }

  if (dom.btnRemoveArtistLibrary) {
    dom.btnRemoveArtistLibrary.addEventListener('click', () => {
      const t = getActiveActionTrack();
      const artistName = t ? String(t.artist || t.artistName || '').trim() : '';
      closeStationPickerModal();
      if (!artistName) return;
      const libArt = findMatchingLibraryArtist(artistName) || { name: artistName };
      promptRemoveArtistFromLibrary(libArt);
    });
  }

  if (dom.btnCloseStationModal) {
    dom.btnCloseStationModal.addEventListener('click', closeStationPickerModal);
  }

  if (dom.stationPickerModal) {
    dom.stationPickerModal.addEventListener('click', (e) => {
      if (e.target === dom.stationPickerModal) {
        closeStationPickerModal();
      }
    });
  }

  if (dom.btnStationByTrack) {
    dom.btnStationByTrack.addEventListener('click', () => {
      triggerHaptic('medium');
      const t = getActiveActionTrack();
      closeStationPickerModal();
      const trackName = t ? String(t.name || t.trackName || '').trim() : '';
      const artistName = t ? String(t.artist || t.artistName || '').trim() : '';
      if (!trackName) return;
      markWaitingForPlayback({ isStation: true, targetName: trackName });
      setUIBusy(true, `Запуск радио по треку «${trackName}»...`);
      send({
        action: 'play_station',
        params: {
          type: 'track',
          title: trackName,
          artist: artistName,
          name: `Станция «${trackName}»`
        }
      });
    });
  }

  if (dom.btnStationByArtist) {
    dom.btnStationByArtist.addEventListener('click', () => {
      triggerHaptic('medium');
      const t = getActiveActionTrack();
      closeStationPickerModal();
      const artistName = t ? String(t.artist || t.artistName || '').trim() : '';
      if (!artistName) return;
      markWaitingForPlayback({ isStation: true, targetName: artistName });
      setUIBusy(true, `Запуск радио по артисту «${artistName}»...`);
      send({
        action: 'play_station',
        params: {
          type: 'artist',
          artist: artistName,
          name: `Станция «${artistName}»`
        }
      });
    });
  }

  dom.qualityModal.addEventListener('click', (e) => {
    if (e.target === dom.qualityModal) {
      closeQualityModal();
    }
  });

  // --- Volume Control & Settings Listeners ---
  let lastVolumeSendTime = 0;
  let volumeSendTimeout = null;

  function sendThrottledVolume(val) {
    const isExtAmpMode = Boolean(state.lockVolume100 && state.ampVolumeControlEnabled);
    if (state.lockVolume100 && !isExtAmpMode) {
      return;
    }
    const maxVol = isExtAmpMode ? Math.max(1, Math.min(100, Number(state.ampMaxVolume) || 80)) : 100;
    const vol = Math.max(0, Math.min(maxVol, Math.round(Number(val) || 0)));
    state.volume = vol;
    try { localStorage.setItem('amr_last_volume', String(vol)); } catch (_) {}
    if (vol >= 5) {
      state.previousVolume = vol;
    }
    if (vol > 0 && isExtAmpMode) {
      state.ampMuted = false;
      try { localStorage.setItem('amr_amp_muted', 'false'); } catch (_) {}
    }

    const pct = Math.max(0, Math.min(100, (vol / maxVol) * 100));
    const brand = state.ampBrandName || 'AMP';
    const labelStr = isExtAmpMode ? `${brand} • ${vol}%` : `${vol}%`;

    if (dom.volumeTrackFill) dom.volumeTrackFill.style.width = `${pct}%`;
    if (dom.volumeThumb) dom.volumeThumb.style.left = `${pct}%`;
    if (dom.volumeLevelText) dom.volumeLevelText.textContent = labelStr;
    updateStandbyLoupePosition(vol, pct, vol === 0);
    if (dom.standbyVolumeText) dom.standbyVolumeText.textContent = labelStr;
    if (dom.standbyBtnVolumeMute) dom.standbyBtnVolumeMute.classList.toggle('muted', vol === 0);
    syncSignalPathAmpNode();
    updateVolumeIcon(Math.round(pct));
    triggerStandbyVolumePulse();

    const now = Date.now();
    const throttleMs = state.isDlnaActive ? 45 : 75;
    if (now - lastVolumeSendTime >= throttleMs) {
      lastVolumeSendTime = now;
      send({ action: 'set_volume', params: { volume: vol } });
    } else {
      if (volumeSendTimeout) clearTimeout(volumeSendTimeout);
      volumeSendTimeout = setTimeout(() => {
        lastVolumeSendTime = Date.now();
        send({ action: 'set_volume', params: { volume: vol } });
      }, throttleMs);
    }
  }

  function handleMuteToggleClick() {
    if (state.lockVolume100 && !state.ampVolumeControlEnabled) {
      return;
    }
    triggerHaptic('toggle');
    triggerStandbyVolumePulse();
    if (state.lockVolume100 && state.ampVolumeControlEnabled) {
      state.ampMuted = !state.ampMuted;
      renderVolumeUI();
      send({ action: 'toggle_amp_mute', params: { muted: state.ampMuted } });
      return;
    }
    if (state.volume > 0) {
      state.previousVolume = state.volume;
      sendThrottledVolume(0);
    } else {
      const restore = state.previousVolume > 0 ? state.previousVolume : 50;
      sendThrottledVolume(restore);
    }
  }

  if (dom.volumeInput) {
    dom.volumeInput.addEventListener('input', (e) => {
      state.isDraggingVolume = true;
      if (dom.standbyVolumeInput) dom.standbyVolumeInput.value = e.target.value;
      sendThrottledVolume(e.target.value);
    });

    const finishVolScrub = (e) => {
      state.isDraggingVolume = false;
      if (e && e.target && e.target.value !== undefined) {
        sendThrottledVolume(e.target.value);
      }
      renderVolumeUI();
      triggerHaptic('light');
    };

    dom.volumeInput.addEventListener('change', finishVolScrub);
    dom.volumeInput.addEventListener('pointerup', () => { state.isDraggingVolume = false; renderVolumeUI(); });
    dom.volumeInput.addEventListener('touchend', () => { state.isDraggingVolume = false; renderVolumeUI(); }, { passive: true });
    dom.volumeInput.addEventListener('pointercancel', () => { state.isDraggingVolume = false; renderVolumeUI(); });
    dom.volumeInput.addEventListener('touchcancel', () => { state.isDraggingVolume = false; renderVolumeUI(); }, { passive: true });
  }

  if (dom.standbyVolumeInput) {
    dom.standbyVolumeInput.addEventListener('pointerdown', () => {
      state.isDraggingVolume = true;
      showStandbyVolumeLoupe(0);
    });
    dom.standbyVolumeInput.addEventListener('touchstart', () => {
      state.isDraggingVolume = true;
      showStandbyVolumeLoupe(0);
    }, { passive: true });

    dom.standbyVolumeInput.addEventListener('input', (e) => {
      state.isDraggingVolume = true;
      showStandbyVolumeLoupe(0);
      if (dom.volumeInput) dom.volumeInput.value = e.target.value;
      sendThrottledVolume(e.target.value);
    });

    const finishStandbyVolScrub = (e) => {
      state.isDraggingVolume = false;
      if (e && e.target && e.target.value !== undefined) {
        sendThrottledVolume(e.target.value);
      }
      renderVolumeUI();
      showStandbyVolumeLoupe(750);
      triggerHaptic('light');
    };

    dom.standbyVolumeInput.addEventListener('change', finishStandbyVolScrub);
    dom.standbyVolumeInput.addEventListener('pointerup', () => {
      state.isDraggingVolume = false;
      renderVolumeUI();
      showStandbyVolumeLoupe(750);
    });
    dom.standbyVolumeInput.addEventListener('touchend', () => {
      state.isDraggingVolume = false;
      renderVolumeUI();
      showStandbyVolumeLoupe(750);
    }, { passive: true });
    dom.standbyVolumeInput.addEventListener('pointercancel', () => {
      state.isDraggingVolume = false;
      renderVolumeUI();
      showStandbyVolumeLoupe(750);
    });
    dom.standbyVolumeInput.addEventListener('touchcancel', () => {
      state.isDraggingVolume = false;
      renderVolumeUI();
      showStandbyVolumeLoupe(750);
    }, { passive: true });
  }

  if (dom.btnVolumeMute) {
    dom.btnVolumeMute.addEventListener('click', handleMuteToggleClick);
  }
  if (dom.standbyBtnVolumeMute) {
    dom.standbyBtnVolumeMute.addEventListener('click', handleMuteToggleClick);
  }

