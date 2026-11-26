  // --- Server Message Dispatcher ---
  function handleServerMessage(msg) {
    if (!msg || typeof msg !== 'object') return;
    state.lastServerMessageAt = Date.now();
    state.pendingPingSentAt = 0;
    const type = (msg.event || msg.action || msg.type || '').toLowerCase();
    if (type === 'ping' || type === 'pong') return;
    const data = msg.data !== undefined ? msg.data : msg;

    if (msg.status === 'cancelled' || (data && typeof data === 'object' && data.status === 'cancelled')) {
      const respReqId = msg.request_id !== undefined ? msg.request_id : (data && data.request_id);
      if (respReqId !== undefined && respReqId !== null && state.aiCurateReqSeq && Number(respReqId) !== Number(state.aiCurateReqSeq)) {
        return;
      }
      if ((respReqId === undefined || respReqId === null) && state.isAiCurating && state.lastAiCurateSentAt && (Date.now() - state.lastAiCurateSentAt < 100)) {
        return;
      }
      if (state.aiCurateTimeoutId) {
        clearTimeout(state.aiCurateTimeoutId);
        state.aiCurateTimeoutId = null;
      }
      state.isAiCurating = false;
      state.pendingStandbyAiAutoPlay = false;
      state.sonicBridgeAutoPlay = false;
      setUIBusy(false);
      return;
    }

    const isSilentErrorType = (
      type === 'device_auth_status' ||
      type === 'register_device' ||
      type === 'get_developer_token' ||
      type === 'prepare_apple_auth_redirect' ||
      type === 'get_artwork' ||
      type === 'get_lyrics' ||
      type === 'get_booklet_info' ||
      type === 'get_tv_library_config' ||
      type === 'tv_library_config' ||
      type === 'client_log'
    );

    if (msg.status === 'error') {
      const isAiErrorType = (
        type === 'ai_curate' ||
        type === 'ai_curate_from_track' ||
        type === 'play_ai_track_vibe' ||
        type === 'curate_music' ||
        type === 'ai_curate_result' ||
        type === 'build_sonic_bridge' ||
        type === 'sonic_bridge'
      );
      if (isAiErrorType) {
        const errReqId = msg.request_id !== undefined ? msg.request_id : (data && data.request_id);
        if (errReqId !== undefined && errReqId !== null && state.aiCurateReqSeq && Number(errReqId) !== Number(state.aiCurateReqSeq)) {
          return;
        }
        if (state.aiCurateTimeoutId) {
          clearTimeout(state.aiCurateTimeoutId);
          state.aiCurateTimeoutId = null;
        }
        state.isAiCurating = false;
        state.pendingStandbyAiAutoPlay = false;
        state.sonicBridgeAutoPlay = false;
        setUIBusy(false);
      }
      if (!isSilentErrorType) {
        state.waitingForPlayback = false;
        state.activeLoadingStationId = null;
        if (!state.isAiCurating) {
          setUIBusy(false);
        }
        if (state.isLaunchingStation) {
          state.isLaunchingStation = false;
          if (state.stationLaunchTimeout) {
            clearTimeout(state.stationLaunchTimeout);
            state.stationLaunchTimeout = null;
          }
        }
        const errText = translateTextToEn(msg.error || (msg.data && msg.data.message) || 'Ошибка выполнения команды');
        if (type === 'select_room_profile' || type === 'set_room_correction_enabled') {
          updateRoomAcousticUI(state.roomAcoustic);
        }
        if (type === 'get_album' || type === 'album' || type === 'get_playlist_tracks' || type === 'playlist_tracks') {
          if (dom.playlistTracksList) {
            dom.playlistTracksList.innerHTML = `<div class="empty-state">${escapeHtml(errText || translateTextToEn('Не удалось загрузить треки'))}</div>`;
          }
        } else if (type === 'get_library_recent' || type === 'library_recent') {
          if (dom.libraryRecentPane && dom.libraryRecentPane.querySelector('.loading-state')) {
            dom.libraryRecentPane.innerHTML = `<div class="empty-state">${escapeHtml(errText)}</div>`;
          }
        } else if (type === 'get_library_artists' || type === 'library_artists') {
          if (dom.libraryArtistsList && dom.libraryArtistsList.querySelector('.loading-state')) {
            dom.libraryArtistsList.innerHTML = `<div class="empty-state">${escapeHtml(errText)}</div>`;
          }
        } else if (type === 'get_library_artist_detail' || type === 'library_artist_detail') {
          if (dom.artistDetailContent && dom.artistDetailContent.querySelector('.loading-state')) {
            dom.artistDetailContent.innerHTML = `<div class="empty-state">${escapeHtml(errText)}</div>`;
          }
        } else if (type === 'get_library_songs' || type === 'library_songs') {
          if (dom.librarySongsList && dom.librarySongsList.querySelector('.loading-state')) {
            dom.librarySongsList.innerHTML = `<div class="empty-state">${escapeHtml(errText)}</div>`;
          }
        } else if (isAiErrorType) {
          isSearchLoadingMore = false;
          if (dom.searchResults && dom.searchResults.querySelector('.loading-state')) {
            if ((type === 'build_sonic_bridge' || type === 'sonic_bridge') && state.searchScope === 'bridge') {
              dom.searchResults.innerHTML = '';
              dom.searchResults.appendChild(buildSonicBridgeCardElement(true));
              const emptyEl = document.createElement('div');
              emptyEl.className = 'empty-state';
              emptyEl.textContent = errText;
              dom.searchResults.appendChild(emptyEl);
            } else {
              dom.searchResults.innerHTML = `<div class="empty-state">${escapeHtml(errText)}</div>`;
            }
          }
        } else if (type === 'search' || type === 'search_result') {
          const errReqId = msg.request_id !== undefined ? msg.request_id : (data && data.request_id);
          const isCurrentSearchErr = !errReqId || !state.searchReqSeq || Number(errReqId) === Number(state.searchReqSeq);
          if (!state.isAiCurating && isCurrentSearchErr) {
            isSearchLoadingMore = false;
            if (dom.searchResults && dom.searchResults.querySelector('.loading-state')) {
              dom.searchResults.innerHTML = `<div class="empty-state">${escapeHtml(errText)}</div>`;
            }
          }
        } else if (type === 'add_playlist_to_library' || type === 'add_album_to_library') {
          const targetSource = (state.lastLibraryAddTarget && typeof state.lastLibraryAddTarget === 'object')
            ? state.lastLibraryAddTarget.source
            : state.lastLibraryAddTarget;
          if (!targetSource || targetSource === 'detail') {
            state.isAddingDetailToLibrary = false;
            const isAlbErr = (type === 'add_album_to_library') || Boolean(state.currentPlaylistDetail && state.currentPlaylistDetail.isAlbum);
            if (dom.btnAddPlaylistLibrary && !dom.btnAddPlaylistLibrary.classList.contains('added')) {
              dom.btnAddPlaylistLibrary.disabled = false;
              if (dom.btnAddPlaylistLibraryText) {
                dom.btnAddPlaylistLibraryText.textContent = translateTextToEn(isAlbErr ? 'В медиатеку' : 'В плейлисты');
              }
            }
          }
          if (!targetSource || targetSource === 'ai' || targetSource === 'hero') {
            const aiSaveBtn = dom.btnAiCuratedSave || document.getElementById('btn-ai-curated-save');
            const aiSaveText = dom.btnAiCuratedSaveText || document.getElementById('btn-ai-curated-save-text');
            if (aiSaveBtn && !aiSaveBtn.classList.contains('added')) {
              aiSaveBtn.disabled = false;
              if (aiSaveText) aiSaveText.textContent = translateTextToEn('В плейлисты');
            }
          }
        } else if (type === 'save_queue_to_playlist') {
          if (dom.btnSaveQueuePlaylist) {
            dom.btnSaveQueuePlaylist.disabled = false;
            dom.btnSaveQueuePlaylist.classList.remove('saved');
          }
          if (dom.btnSaveQueueText) {
            dom.btnSaveQueueText.textContent = translateTextToEn('В плейлист');
          }
        }
        showToast(errText);
        return;
      }
      if (type !== 'device_auth_status' && type !== 'register_device' && type !== 'get_device_status') {
        return;
      }
    }

    switch (type) {
      case 'device_auth_status':
      case 'register_device':
      case 'get_device_status':
        handleDeviceAuthStatus(data);
        break;

      case 'toast':
        if (data && typeof data === 'object') {
          const toastMsg = IS_EN
            ? (data.message_en || data.message || '')
            : (data.message_ru || data.message || '');
          if (toastMsg) showToast(toastMsg, 2400);
        }
        break;

      case 'share_access_qr':
      case 'get_share_access_qr':
      case 'generate_share_access_qr':
        handleShareAccessQR(data);
        break;

      case 'ai_curate':
      case 'ai_curate_from_track':
      case 'play_ai_track_vibe':
      case 'curate_music':
      case 'ai_curate_result':
        if (data && typeof data === 'object' && data.request_id === undefined && msg.request_id !== undefined) {
          data.request_id = msg.request_id;
        }
        updateAiCuratedResults(data, type);
        break;

      case 'build_sonic_bridge':
      case 'sonic_bridge':
        if (data && typeof data === 'object' && data.request_id === undefined && msg.request_id !== undefined) {
          data.request_id = msg.request_id;
        }
        updateSonicBridgeResults(data);
        break;

      case 'ai_curator_settings':
      case 'get_ai_curator_settings':
      case 'refresh_ai_prompts':
        state.lastAiSettingsReceivedAt = Date.now();
        handleAiCuratorSettings(data);
        break;

      case 'get_artwork_palette':
      case 'artwork_palette':
        AmbientBackgroundManager.applyServerPalette(data);
        break;

      case 'player_state_changed':
      case 'status':
      case 'get_status':
        state.lastPlayerStateReceivedAt = Date.now();
        updatePlayerState(data);
        break;

      case 'queue_changed':
      case 'queue':
      case 'get_queue':
        state.lastQueueReceivedAt = Date.now();
        updateQueue(data);
        break;

      case 'playlists':
      case 'get_playlists':
      case 'playlists_result':
        updatePlaylists(data);
        break;

      case 'albums':
      case 'get_albums':
      case 'get_library_albums':
      case 'albums_result':
        updateLibraryAlbums(data);
        break;

      case 'library_recent':
      case 'get_library_recent':
        updateLibraryRecent(data);
        break;

      case 'library_artists':
      case 'get_library_artists':
        updateLibraryArtists(data);
        break;

      case 'library_artist_detail':
      case 'get_library_artist_detail':
        updateLibraryArtistDetail(data);
        break;

      case 'library_songs':
      case 'get_library_songs':
        updateLibrarySongs(data);
        break;

      case 'remove_from_library':
      case 'delete_from_library':
      case 'remove_playlist_from_library':
      case 'delete_playlist_from_library':
      case 'library_changed':
        handleLibraryRemovedOrChanged(data, type, msg);
        break;

      case 'tv_library_config':
      case 'get_tv_library_config':
      case 'set_tv_library_config':
      case 'tv_library_config_changed':
        handleTvLibraryConfig(data);
        break;

      case 'playlist_tracks':
      case 'get_playlist_tracks':
        updatePlaylistTracks(data);
        break;

      case 'get_catalog_charts':
      case 'catalog_charts':
      case 'charts':
        updateCatalogCharts(data);
        break;

      case 'get_explore':
      case 'explore':
        updateExploreFeed(data);
        break;

      case 'get_album':
      case 'album':
        updateAlbumDetails(data);
        break;

      case 'search':
      case 'search_result':
        if (data && typeof data === 'object' && data.request_id === undefined && msg.request_id !== undefined) {
          data.request_id = msg.request_id;
        }
        updateSearchResults(data);
        break;

      case 'get_audio_devices':
      case 'audio_devices':
      case 'audio_devices_changed':
        updateAudioDevices(data);
        break;

      case 'get_user_token_status':
      case 'user_token_status':
      case 'set_user_token':
        updateUserTokenStatus(data);
        break;

      case 'get_developer_token':
        if (data && data.token) {
          state.developerToken = data.token;
          initMusicKit(data.token);
        }
        break;

      case 'prepare_apple_auth_redirect':
        if (data && data.invite_token) {
          state.appleAuthRedirectInviteToken = String(data.invite_token);
        }
        break;

      case 'get_account_status':
      case 'account_status':
      case 'account_health':
        updateAccountHealth(data);
        break;

      case 'wled_settings':
      case 'get_wled_settings':
      case 'set_wled_settings':
        updateWledSettingsUI(data);
        break;

      case 'dsp_settings':
      case 'get_dsp_settings':
      case 'set_dsp_settings':
      case 'select_dsp_preset':
      case 'update_dsp_settings':
        updateDSPSettingsUI(data);
        break;

      case 'room_acoustic_settings':
      case 'get_room_acoustic_settings':
      case 'start_room_test_signal':
      case 'stop_room_test_signal':
      case 'submit_room_measurement':
      case 'set_room_correction_enabled':
      case 'select_room_profile':
      case 'rename_room_profile':
      case 'delete_room_profile':
        updateRoomAcousticUI(data);
        break;

      case 'late_night_drc_settings':
      case 'get_late_night_drc_settings':
      case 'set_late_night_drc':
      case 'set_late_night_drc_mode':
      case 'set_late_night_drc_enabled':
      case 'set_late_night_drc_profile':
        updateLateNightDRCUI(data);
        break;

      case 'mastering_restoration_settings':
      case 'get_mastering_restoration_settings':
      case 'set_mastering_restoration':
      case 'set_mastering_declip_mode':
      case 'set_mastering_deesser_mode':
        updateMasteringRestorationUI(data);
        break;

      case 'set_repeat':
      case 'repeat': {
        if (data && (data.repeat !== undefined || data.repeatMode !== undefined || data.repeat_mode !== undefined)) {
          const ackRepeat = normalizeRepeatMode(data.repeat || data.repeat_mode || data.repeatMode);
          if (!state.pendingRepeatUntil || Date.now() >= state.pendingRepeatUntil) {
            state.repeatMode = ackRepeat;
            renderNowPlaying();
          } else if (ackRepeat === state.repeatMode) {
            state.pendingRepeatUntil = 0;
          }
        }
        break;
      }

      case 'set_shuffle':
      case 'shuffle': {
        if (data && data.shuffle !== undefined) {
          const ackShuf = Boolean(data.shuffle);
          if (!state.pendingShuffleUntil || Date.now() >= state.pendingShuffleUntil) {
            state.shuffle = ackShuf;
            renderNowPlaying();
          } else if (ackShuf === state.shuffle) {
            state.pendingShuffleUntil = 0;
          }
        }
        break;
      }

      case 'motion_artwork':
      case 'get_motion_artwork':
        applyMotionArtwork(data);
        break;

      case 'get_spectral_rta':
      case 'spectral_rta':
      case 'get_spectral_analysis':
      case 'spectral_analysis':
        handleSpectralAnalysisMessage(data);
        break;

      case 'get_info':
      case 'info':
        if (data && data.version) {
          const vEls = document.querySelectorAll('.brand-ver');
          vEls.forEach(el => { el.textContent = `v${data.version}`; });
        }
        if (data && data.git_commit) {
          state.gitCommit = String(data.git_commit);
        }
        if (data && data.git_commit_date) {
          state.gitCommitDate = String(data.git_commit_date);
        }
        if (data && data.ai_curator_enabled !== undefined) {
          state.aiCuratorEnabled = Boolean(data.ai_curator_enabled);
          syncAiCuratorEnabledUI();
        }
        syncDeviceInfoUI();
        break;

      case 'add_playlist_to_library':
      case 'add_album_to_library':
      case 'add_track_to_library':
      case 'add_to_library': {
        const ok = (data && typeof data.status === 'string') ? (data.status === 'ok') : (msg.status === 'ok');
        const targetSource = (state.lastLibraryAddTarget && typeof state.lastLibraryAddTarget === 'object')
          ? state.lastLibraryAddTarget.source
          : state.lastLibraryAddTarget;
        const isTrackTarget = (targetSource === 'track' || type === 'add_track_to_library');
        const isAlb = !isTrackTarget && ((data && typeof data.is_album === 'boolean')
          ? data.is_album
          : (type === 'add_album_to_library' || Boolean(targetSource === 'detail' && state.currentPlaylistDetail && state.currentPlaylistDetail.isAlbum)));
        const aiSaveBtn = dom.btnAiCuratedSave || document.getElementById('btn-ai-curated-save');
        const aiSaveText = dom.btnAiCuratedSaveText || document.getElementById('btn-ai-curated-save-text');
        const isAiTarget = targetSource === 'ai' || Boolean(data && data.name && state.activeAiCuratedTitle && data.name === state.activeAiCuratedTitle);
        const curDet = state.currentPlaylistDetail;
        const curId = String(state.currentDetailPlaylistId || state.currentDetailAlbumId || (curDet && curDet.id) || '').trim().toLowerCase();
        const curName = String(state.currentDetailTitle || (curDet && (curDet.name || curDet.title)) || '').trim().toLowerCase();
        const curKey = String(state.currentDetailPlaylistId || state.currentDetailAlbumId || state.currentDetailTitle || (curDet && (curDet.id || curDet.name || curDet.title)) || '');
        const respId = (data && data.id) ? String(data.id).trim().toLowerCase() : '';
        const respName = (data && data.name) ? String(data.name).trim().toLowerCase() : '';
        const matchesDetailTarget = Boolean(
          !isTrackTarget &&
          curDet &&
          (
            (respId && curId)
              ? (respId === curId)
              : (
                (respName && curName)
                  ? (respName === curName)
                  : (
                    !respId && !respName && (
                      (state.lastDetailLibraryAddId && curId)
                        ? (curId === state.lastDetailLibraryAddId)
                        : Boolean(
                            (state.lastDetailLibraryAddKey && curKey === state.lastDetailLibraryAddKey) ||
                            (state.lastDetailLibraryAddName && curName && curName === state.lastDetailLibraryAddName)
                          )
                    )
                  )
              )
          )
        );
        if (matchesDetailTarget && targetSource !== 'ai') {
          state.isAddingDetailToLibrary = false;
        }
        if (ok) {
          if (isTrackTarget) {
            state.lastLibraryAddTarget = '';
            if (state.actionTargetTrack) state.actionTargetTrack.is_local = true;
            if (state.track && state.actionTargetTrack && state.track.name === state.actionTargetTrack.name) {
              state.track.is_local = true;
            }
            state.libraryRecent.loaded = false;
            state.libraryArtistsLoaded = false;
            state.librarySongsLoaded = false;
            send({ action: 'get_library_songs' });
            send({ action: 'get_library_recent' });
            send({ action: 'get_library_albums' });
            showToast(translateTextToEn('★ Трек добавлен в медиатеку Apple Music'));
            break;
          }
          if (targetSource !== 'ai' && matchesDetailTarget && dom.btnAddPlaylistLibrary && (!dom.playlistDetailPane || !dom.playlistDetailPane.classList.contains('hidden'))) {
            dom.btnAddPlaylistLibrary.disabled = true;
            dom.btnAddPlaylistLibrary.classList.add('added');
            dom.btnAddPlaylistLibrary.classList.add('hidden');
            if (state.currentPlaylistDetail) {
              state.currentPlaylistDetail.is_local = true;
              state.currentPlaylistDetail.in_library = true;
              state.currentPlaylistDetail.is_complete_in_library = true;
            }
            if (isAlb && state.currentAlbumDetail) {
              state.currentAlbumDetail.in_library = true;
              state.currentAlbumDetail.is_complete_in_library = true;
              const tot = Number(state.currentAlbumDetail.catalog_track_count || (state.currentAlbumDetail.tracks && state.currentAlbumDetail.tracks.length) || 0);
              if (tot > 0) state.currentAlbumDetail.library_track_count = tot;
              if (Array.isArray(state.currentAlbumDetail.tracks)) {
                state.currentAlbumDetail.tracks.forEach(tr => { tr.is_local = true; });
              }
              if (dom.albumCompletenessBannerSlot) dom.albumCompletenessBannerSlot.innerHTML = '';
              if (dom.btnRemoveDetailLibrary) dom.btnRemoveDetailLibrary.classList.remove('hidden');
              updateAlbumDetails(state.currentAlbumDetail);
            } else if (!isAlb && dom.btnRemoveDetailLibrary) {
              const curPlName = (state.currentPlaylistDetail && (state.currentPlaylistDetail.name || state.currentPlaylistDetail.title)) || '';
              if (!isProtectedSystemPlaylistClient(curPlName)) {
                if (dom.btnRemoveDetailLibraryText) {
                  dom.btnRemoveDetailLibraryText.textContent = translateTextToEn('Удалить плейлист');
                }
                dom.btnRemoveDetailLibrary.classList.remove('hidden');
              }
            }
          }
          if (isAlb) {
            const addedSrc = state.currentAlbumDetail || state.currentPlaylistDetail || {};
            const addedName = (data && data.name) || addedSrc.name || addedSrc.title || '';
            if (addedName) {
              const optimisticAlb = {
                id: String((data && data.id) || addedSrc.id || ''),
                name: addedName,
                artist: addedSrc.artist || addedSrc.sub || addedSrc.subtitle || '',
                artwork: addedSrc.artwork || addedSrc.artwork_url || '',
                track_count: (data && data.track_count) || addedSrc.track_count || addedSrc.trackCount || ((addedSrc.tracks && addedSrc.tracks.length) || 0),
                in_library: true
              };
              upsertOptimisticLibraryAlbum(optimisticAlb);
            }
            state.libraryRecent.loaded = false;
            state.libraryArtistsLoaded = false;
            state.librarySongsLoaded = false;
            send({ action: 'get_library_albums' });
            if (state.libraryTab === 'recent') send({ action: 'get_library_recent' });
            else if (state.libraryTab === 'artists') send({ action: 'get_library_artists' });
            else if (state.libraryTab === 'songs') send({ action: 'get_library_songs' });
          } else {
            const plSrc = (!isAiTarget && state.currentPlaylistDetail && !state.currentPlaylistDetail.isAlbum)
              ? state.currentPlaylistDetail
              : {};
            const addedPlName = (data && (data.name || data.playlist)) || (isAiTarget ? state.activeAiCuratedTitle : (plSrc.name || plSrc.title || ''));
            if (addedPlName) {
              upsertOptimisticPlaylist({
                id: String((data && data.id) || plSrc.id || ''),
                name: addedPlName,
                artwork_url: (data && data.artwork_url) || plSrc.artwork_url || plSrc.artworkUrl || plSrc.artwork || '',
                track_count: Number((data && data.track_count) || plSrc.track_count || plSrc.trackCount || (state.currentPlaylistTracks && state.currentPlaylistTracks.length) || 0)
              });
            }
            send({ action: 'get_playlists', params: { refresh: true } });
          }
          if (isAiTarget && aiSaveBtn) {
            aiSaveBtn.disabled = true;
            aiSaveBtn.classList.add('added');
            if (aiSaveText) aiSaveText.textContent = translateTextToEn('В плейлистах ✓');
          }
          showToast(translateTextToEn(isAlb ? '★ Альбом добавлен в медиатеку Apple Music' : '★ Плейлист добавлен в плейлисты Apple Music'));
        } else {
          if (isTrackTarget) {
            state.lastLibraryAddTarget = '';
          }
          if ((!targetSource || targetSource === 'detail') && matchesDetailTarget && dom.btnAddPlaylistLibrary && !dom.btnAddPlaylistLibrary.classList.contains('added')) {
            dom.btnAddPlaylistLibrary.disabled = false;
            if (dom.btnAddPlaylistLibraryText) {
              dom.btnAddPlaylistLibraryText.textContent = translateTextToEn(isAlb ? 'В медиатеку' : 'В плейлисты');
            }
          }
          if ((!targetSource || targetSource === 'ai' || targetSource === 'hero') && aiSaveBtn && !aiSaveBtn.classList.contains('added')) {
            aiSaveBtn.disabled = false;
            if (aiSaveText) aiSaveText.textContent = translateTextToEn('В плейлисты');
          }
          showToast(translateTextToEn((data && data.message) || msg.error || (isAlb ? 'Не удалось добавить в медиатеку' : 'Не удалось добавить в плейлисты')));
        }
        break;
      }

      case 'save_queue_to_playlist': {
        const ok = (data && typeof data.status === 'string') ? (data.status === 'ok') : (msg.status === 'ok');
        if (ok) {
          const savedPlName = (data && (data.name || data.playlist)) || '';
          if (savedPlName) {
            upsertOptimisticPlaylist({
              id: String((data && data.id) || ''),
              name: savedPlName,
              artwork_url: (data && data.artwork_url) || '',
              track_count: Number((data && data.track_count) || 0)
            });
          }
          send({ action: 'get_playlists', params: { refresh: true } });
          if (dom.btnSaveQueuePlaylist) {
            dom.btnSaveQueuePlaylist.disabled = true;
            dom.btnSaveQueuePlaylist.classList.add('saved');
          }
          if (dom.btnSaveQueueText) {
            dom.btnSaveQueueText.textContent = translateTextToEn('В плейлистах ✓');
          }
          showToast(
            savedPlName
              ? (IS_EN ? `★ Saved to playlist «${savedPlName}»` : `★ Сохранено в плейлист «${savedPlName}»`)
              : translateTextToEn('★ Очередь сохранена в плейлисты Apple Music')
          );
          setTimeout(() => {
            if (dom.btnSaveQueuePlaylist) {
              dom.btnSaveQueuePlaylist.disabled = false;
              dom.btnSaveQueuePlaylist.classList.remove('saved');
            }
            if (dom.btnSaveQueueText) {
              dom.btnSaveQueueText.textContent = translateTextToEn('В плейлист');
            }
          }, 3200);
        } else {
          if (dom.btnSaveQueuePlaylist) {
            dom.btnSaveQueuePlaylist.disabled = false;
            dom.btnSaveQueuePlaylist.classList.remove('saved');
          }
          if (dom.btnSaveQueueText) {
            dom.btnSaveQueueText.textContent = translateTextToEn('В плейлист');
          }
          showToast(translateTextToEn((data && data.message) || msg.error || 'Не удалось сохранить очередь в плейлист'));
        }
        break;
      }

      default:
        // Check if data has player properties
        if (data && (data.player_state || data.playerState)) {
          updatePlayerState(data);
        } else if (data && (data.upcoming_tracks || data.upcomingTracks)) {
          updateQueue(data);
        }
        break;
    }

    // Dismiss busy overlay ONLY when specific playback actions complete or fail,
    // NEVER on periodic background 'status', 'queue', or 'player_state_changed' ticks!
    const isPlaybackActionResponse = [
      'play_album', 'play_album_tracks', 'play_playlist',
      'play_station', 'play_hero_card', 'play_search_results',
      'play_recent', 'play_queue_index', 'queue_play_index',
      'play_history_index', 'play_cloud'
    ].includes(type);

    const isActionError = msg.status === 'error' || (data && typeof data === 'object' && data.status === 'error');
    if (isActionError && !isSilentErrorType) {
      state.waitingForPlayback = false;
      state.activeLoadingStationId = null;
      setUIBusy(false);
      if (state.isLaunchingStation) {
        state.isLaunchingStation = false;
        if (state.stationLaunchTimeout) {
          clearTimeout(state.stationLaunchTimeout);
          state.stationLaunchTimeout = null;
        }
      }
      if (isPlaybackActionResponse) {
        const errText = (data && data.message) || msg.error || 'Ошибка выполнения команды';
        showToast(translateTextToEn(errText));
      }
    } else if (isPlaybackActionResponse && msg.status === 'ok') {
      // If we are waiting for playback to actually start (Music.app buffering/syncing),
      // DO NOT dismiss the spinner yet! Let updatePlayerState dismiss it when player_state becomes 'playing'
      // or track changes!
      if (!state.waitingForPlayback) {
        if (state.isBusyAction) {
          setUIBusy(false);
        }
        if (state.isLaunchingStation) {
          state.isLaunchingStation = false;
          if (state.stationLaunchTimeout) {
            clearTimeout(state.stationLaunchTimeout);
            state.stationLaunchTimeout = null;
          }
        }
      }
    }
  }
