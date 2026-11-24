  function openAlbumDetail(alb, fromOrigin = true, opts = {}) {
    const origin = resolveDetailOrigin(fromOrigin, 'library-albums');
    const albumSource = (opts && opts.source)
      ? opts.source
      : ((origin === 'library-albums' || origin === 'library-recent' || origin === 'library-artist-detail') ? 'library' : 'catalog');
    state.currentAlbumSource = albumSource;
    state.detailReturnOrigin = origin;
    state.albumOpenedFromHome = (origin === 'home' || origin === 'home-grid');
    state.detailOpenedFromHome = (origin === 'home' || origin === 'home-grid');
    state.currentPlaylistDetail = { ...alb, isAlbum: true };
    state.currentAlbumDetail = null;
    const nextAlbId = String(alb.id || '').trim().toLowerCase();
    const nextAlbName = String(alb.name || alb.title || '').trim().toLowerCase();
    if (
      state.isAddingDetailToLibrary &&
      (
        (state.lastDetailLibraryAddId && nextAlbId && state.lastDetailLibraryAddId !== nextAlbId) ||
        (!state.lastDetailLibraryAddId && state.lastDetailLibraryAddName && nextAlbName && state.lastDetailLibraryAddName !== nextAlbName)
      )
    ) {
      state.isAddingDetailToLibrary = false;
    }
    state.currentDetailPlaylistId = '';
    state.currentDetailAlbumId = String(alb.id || '');
    state.currentDetailTitle = String(alb.name || alb.title || '');
    if (dom.detailTitle) dom.detailTitle.textContent = alb.name || alb.title || translateTextToEn('Альбом');
    if (dom.detailMeta) dom.detailMeta.textContent = alb.artist || alb.sub || alb.subtitle || '';
    if (dom.detailArtwork) {
      delete dom.detailArtwork.dataset.fallbackApplied;
      dom.detailArtwork.src = appendDeviceIdToUrl(alb.artwork || alb.artwork_url || 'apple-touch-icon.svg');
    }
    if (dom.detailBadge) dom.detailBadge.textContent = translateTextToEn('АЛЬБОМ');
    if (dom.playlistTracksList) dom.playlistTracksList.innerHTML = `<div class="loading-state">${escapeHtml(translateTextToEn('Загрузка треков альбома...'))}</div>`;
    if (dom.albumCompletenessBannerSlot) dom.albumCompletenessBannerSlot.innerHTML = '';

    const matchedLibAlb = findMatchingLibraryAlbum(alb);
    const alreadyInLib = Boolean(alb.is_local || alb.in_library || matchedLibAlb);
    const canModifyLib = state.allowLibraryModification !== false;

    if (dom.btnRemoveDetailLibrary) {
      if (dom.btnRemoveDetailLibraryText) {
        dom.btnRemoveDetailLibraryText.textContent = translateTextToEn('Удалить из медиатеки');
      }
      dom.btnRemoveDetailLibrary.classList.toggle('hidden', !canModifyLib || !alreadyInLib);
    }

    if (dom.btnAddPlaylistLibrary) {
      dom.btnAddPlaylistLibrary.style.display = '';
      dom.btnAddPlaylistLibrary.title = translateTextToEn('Добавить в медиатеку Apple Music');
      if (!canModifyLib || alb.is_complete_in_library === true || (alreadyInLib && alb.is_complete_in_library !== false)) {
        dom.btnAddPlaylistLibrary.disabled = true;
        dom.btnAddPlaylistLibrary.classList.add('added');
        dom.btnAddPlaylistLibrary.classList.add('hidden');
      } else {
        dom.btnAddPlaylistLibrary.disabled = false;
        if (dom.btnAddPlaylistLibraryText) {
          dom.btnAddPlaylistLibraryText.textContent = translateTextToEn(alreadyInLib ? 'Добавить весь альбом' : 'В медиатеку');
        }
        dom.btnAddPlaylistLibrary.classList.remove('added');
        dom.btnAddPlaylistLibrary.classList.remove('hidden');
      }
    }
    const btnDetailBookletAlb = document.getElementById('btn-detail-booklet');
    if (btnDetailBookletAlb) btnDetailBookletAlb.classList.add('hidden');
    syncDetailAlbumBookletAvailability(alb);

    navigateToView('view-library', 'library', true);
    syncDetailBackLabel(origin);
    syncNavHighlightForDetailOrigin(origin);
    if (dom.playlistsBrowsePane) dom.playlistsBrowsePane.classList.add('hidden');
    if (dom.libraryArtistDetailPane) dom.libraryArtistDetailPane.classList.add('hidden');
    if (dom.playlistDetailPane) dom.playlistDetailPane.classList.remove('hidden');

    send({
      action: 'get_album',
      params: {
        id: alb.id || '',
        name: alb.name || alb.title || '',
        artist: alb.artist || alb.sub || alb.subtitle || '',
        country: getActiveStorefront(),
        source: albumSource
      }
    });
  }

  dom.btnBackToPlaylists.addEventListener('click', () => {
    dom.playlistDetailPane.classList.add('hidden');
    if (dom.albumCompletenessBannerSlot) dom.albumCompletenessBannerSlot.innerHTML = '';
    const origin = state.detailReturnOrigin || (state.albumOpenedFromHome || state.detailOpenedFromHome ? 'home' : 'library');
    state.detailReturnOrigin = null;
    state.albumOpenedFromHome = false;
    state.detailOpenedFromHome = false;

    if (origin === 'playlists') {
      navigateToView('view-playlists', 'playlists');
    } else if (origin === 'search') {
      navigateToView('view-search', 'search');
    } else if (origin === 'player') {
      if (!isDesktopLayout()) {
        switchMobileView('view-now-playing', true);
      } else {
        showLibraryBrowsePane();
        syncNavHighlightForDetailOrigin('library');
      }
    } else if (origin === 'home-grid') {
      navigateToView('view-home', 'home');
      if (dom.viewHome) dom.viewHome.classList.remove('active');
      if (dom.sectionGridView) {
        dom.sectionGridView.classList.remove('hidden');
        dom.sectionGridView.classList.add('active');
      }
    } else if (origin === 'home') {
      navigateToView('view-home', 'home');
    } else if (origin === 'library-artist-detail') {
      if (state.currentLibraryArtistDetail && dom.libraryArtistDetailPane) {
        if (dom.playlistsBrowsePane) dom.playlistsBrowsePane.classList.add('hidden');
        dom.libraryArtistDetailPane.classList.remove('hidden');
        syncNavHighlightForDetailOrigin('library-artists');
      } else {
        showLibraryBrowsePane();
        switchLibrarySubtab('artists', false);
        syncNavHighlightForDetailOrigin('library-artists');
      }
    } else if (origin === 'library-recent') {
      showLibraryBrowsePane();
      switchLibrarySubtab('recent', false);
      syncNavHighlightForDetailOrigin('library-recent');
    } else if (origin === 'library-artists') {
      showLibraryBrowsePane();
      switchLibrarySubtab('artists', false);
      syncNavHighlightForDetailOrigin('library-artists');
    } else if (origin === 'library-albums') {
      showLibraryBrowsePane();
      switchLibrarySubtab('albums', false);
      syncNavHighlightForDetailOrigin('library-albums');
    } else if (origin === 'library-songs') {
      showLibraryBrowsePane();
      switchLibrarySubtab('songs', false);
      syncNavHighlightForDetailOrigin('library-songs');
    } else {
      showLibraryBrowsePane();
      switchLibrarySubtab(state.libraryTab || 'recent', false);
      syncNavHighlightForDetailOrigin('library');
    }
  });

  dom.btnPlayPlaylist.addEventListener('click', () => {
    if (!state.currentPlaylistDetail) return;
    const isAlbum = Boolean(state.currentPlaylistDetail.isAlbum);
    const plName = state.currentPlaylistDetail.name || state.currentPlaylistDetail.title || '';
    const loadedTracks = Array.isArray(state.currentPlaylistTracks) ? state.currentPlaylistTracks : [];
    const matchedLocal = findMatchingLocalPlaylist(plName, state.currentPlaylistDetail.id, loadedTracks.length);
    const isExplicitLocalPlaylist = !isAlbum && Boolean(state.currentPlaylistDetail.is_local);

    optimisticPlay();
    markWaitingForPlayback({ targetName: plName });
    if (isAlbum) {
      setUIBusy(true, 'Запуск альбома...', dom.btnPlayPlaylist);
    } else if (isExplicitLocalPlaylist || matchedLocal) {
      setUIBusy(true, 'Запуск плейлиста...', dom.btnPlayPlaylist);
    } else {
      setUIBusy(true, 'Запуск плейлиста...', dom.btnPlayPlaylist);
    }

    if (isAlbum) {
      send({
        action: 'play_album',
        params: {
          id: state.currentPlaylistDetail.id || '',
          name: plName,
          artist: state.currentPlaylistDetail.artist || state.currentPlaylistDetail.sub || state.currentPlaylistDetail.subtitle || '',
          tracks: (state.currentAlbumDetail && state.currentAlbumDetail.tracks) || [],
          shuffle: false
        }
      });
    } else if (isExplicitLocalPlaylist) {
      send({
        action: 'play_playlist',
        params: {
          playlist: matchedLocal ? matchedLocal.name : plName,
          shuffle: false,
          is_local: true
        }
      });
    } else {
      send({
        action: 'play_playlist',
        params: {
          playlist: plName,
          id: state.currentPlaylistDetail.id || '',
          url: state.currentPlaylistDetail.url || '',
          tracks: loadedTracks,
          shuffle: false
        }
      });
    }
  });

  dom.btnShufflePlaylist.addEventListener('click', () => {
    if (!state.currentPlaylistDetail) return;
    const isAlbum = Boolean(state.currentPlaylistDetail.isAlbum);
    const plName = state.currentPlaylistDetail.name || state.currentPlaylistDetail.title || '';
    const loadedTracks = Array.isArray(state.currentPlaylistTracks) ? state.currentPlaylistTracks : [];
    const matchedLocal = findMatchingLocalPlaylist(plName, state.currentPlaylistDetail.id, loadedTracks.length);
    const isExplicitLocalPlaylist = !isAlbum && Boolean(state.currentPlaylistDetail.is_local);

    optimisticPlay();
    markWaitingForPlayback({ targetName: plName });
    if (isAlbum) {
      setUIBusy(true, 'Перемешивание альбома...', dom.btnShufflePlaylist);
    } else {
      setUIBusy(true, 'Перемешивание...', dom.btnShufflePlaylist);
    }

    if (isAlbum) {
      send({
        action: 'play_album',
        params: {
          id: state.currentPlaylistDetail.id || '',
          name: plName,
          artist: state.currentPlaylistDetail.artist || state.currentPlaylistDetail.sub || state.currentPlaylistDetail.subtitle || '',
          tracks: (state.currentAlbumDetail && state.currentAlbumDetail.tracks) || [],
          shuffle: true
        }
      });
    } else if (isExplicitLocalPlaylist) {
      send({
        action: 'play_playlist',
        params: {
          playlist: matchedLocal ? matchedLocal.name : plName,
          shuffle: true,
          is_local: true
        }
      });
    } else {
      send({
        action: 'play_playlist',
        params: {
          playlist: plName,
          id: state.currentPlaylistDetail.id || '',
          url: state.currentPlaylistDetail.url || '',
          tracks: loadedTracks,
          shuffle: true
        }
      });
    }
  });

  if (dom.btnAddPlaylistLibrary) {
    dom.btnAddPlaylistLibrary.addEventListener('click', () => {
      if (!state.currentPlaylistDetail) return;
      const isAlbum = Boolean(state.currentPlaylistDetail.isAlbum);
      const curAlb = state.currentAlbumDetail;
      const catalogAlbId = (isAlbum && curAlb && curAlb.catalog_album_id) ? String(curAlb.catalog_album_id) : '';
      const rawItemId = state.currentPlaylistDetail.id || (curAlb && curAlb.id) || '';
      const itemId = catalogAlbId || rawItemId;
      const itemName = state.currentPlaylistDetail.name || state.currentPlaylistDetail.title || '';
      const itemArtist = state.currentPlaylistDetail.artist || state.currentPlaylistDetail.sub || state.currentPlaylistDetail.subtitle || (curAlb && curAlb.artist) || '';
      const isPartialLibrarySubset = Boolean(isAlbum && curAlb && curAlb.is_library_view && !curAlb.is_complete_in_library);
      const tracks = isAlbum
        ? (isPartialLibrarySubset ? [] : ((curAlb && curAlb.tracks) || []))
        : (state.currentPlaylistTracks || []);

      state.lastLibraryAddTarget = 'detail';
      state.isAddingDetailToLibrary = true;
      state.lastDetailLibraryAddKey = String(state.currentDetailPlaylistId || state.currentDetailAlbumId || state.currentDetailTitle || itemId || itemName || '');
      state.lastDetailLibraryAddId = String(rawItemId || itemId || '').trim().toLowerCase();
      state.lastDetailLibraryAddName = String(itemName || '').trim().toLowerCase();
      const itemArtwork = state.currentPlaylistDetail.artwork_url || state.currentPlaylistDetail.artworkUrl || state.currentPlaylistDetail.artwork || (curAlb && (curAlb.artwork || curAlb.artwork_url)) || '';
      const itemTrackCount = Number(state.currentPlaylistDetail.track_count || state.currentPlaylistDetail.trackCount || (tracks && tracks.length) || 0);
      dom.btnAddPlaylistLibrary.disabled = true;
      if (dom.btnAddPlaylistLibraryText) dom.btnAddPlaylistLibraryText.textContent = translateTextToEn('Добавление...');
      send({
        action: 'add_playlist_to_library',
        params: {
          id: itemId,
          name: itemName,
          artist: itemArtist,
          artwork: itemArtwork,
          track_count: itemTrackCount,
          is_album: isAlbum,
          tracks: tracks
        }
      });
    });
  }

  if (dom.btnRemoveDetailLibrary) {
    dom.btnRemoveDetailLibrary.addEventListener('click', () => {
      const target = state.currentAlbumDetail || state.currentPlaylistDetail;
      if (!target) return;
      if (state.currentPlaylistDetail && state.currentPlaylistDetail.isAlbum) {
        promptRemoveAlbumFromLibrary(target);
      } else if (state.currentPlaylistDetail) {
        promptRemovePlaylistFromLibrary(state.currentPlaylistDetail);
      }
    });
  }

  function updateAlbumDetails(data) {
    const alb = data.album || data;
    if (!alb) return;
    state.currentAlbumDetail = alb;
    state.currentPlaylistDetail = { ...alb, isAlbum: true };
    const nextAlbId = String(alb.id || '').trim().toLowerCase();
    const nextAlbName = String(alb.name || alb.title || '').trim().toLowerCase();
    if (
      state.isAddingDetailToLibrary &&
      (
        (state.lastDetailLibraryAddId && nextAlbId && state.lastDetailLibraryAddId !== nextAlbId) ||
        (!state.lastDetailLibraryAddId && state.lastDetailLibraryAddName && nextAlbName && state.lastDetailLibraryAddName !== nextAlbName)
      )
    ) {
      state.isAddingDetailToLibrary = false;
    }
    state.currentDetailPlaylistId = '';
    state.currentDetailAlbumId = String(alb.id || state.currentDetailAlbumId || '');
    state.currentDetailTitle = String(alb.name || alb.title || state.currentDetailTitle || '');

    const tracks = Array.isArray(alb.tracks) ? alb.tracks : [];
    const allLocal = tracks.length > 0 && tracks.every(t => Boolean(t.is_local || t.isLocal));
    const localInTracksCount = tracks.filter(t => Boolean(t.is_local || t.isLocal)).length;
    const libCount = alb.library_track_count !== undefined
      ? Number(alb.library_track_count || 0)
      : localInTracksCount;
    const catCount = alb.catalog_track_count !== undefined
      ? Number(alb.catalog_track_count || 0)
      : Number(alb.track_count || tracks.length || 0);
    const inLibrary = alb.in_library !== undefined
      ? Boolean(alb.in_library)
      : Boolean(libCount > 0 || alb.is_local || allLocal);
    const isComplete = alb.is_complete_in_library !== undefined
      ? Boolean(alb.is_complete_in_library)
      : Boolean(inLibrary && (allLocal || (catCount > 0 && libCount >= catCount)));
    const isLibraryView = Boolean(alb.is_library_view);
    const catAlbumId = String(alb.catalog_album_id || (Number(alb.id) >= 10000000 ? alb.id : '') || '').trim();

    if (dom.btnRemoveDetailLibrary) {
      dom.btnRemoveDetailLibrary.classList.toggle('hidden', !(inLibrary || libCount > 0));
    }

    if (dom.btnAddPlaylistLibrary) {
      dom.btnAddPlaylistLibrary.style.display = '';
      const curIdLower = String(state.currentDetailAlbumId || '').trim().toLowerCase();
      const curNameLower = String(state.currentDetailTitle || '').trim().toLowerCase();
      const isSamePendingDetail = Boolean(
        state.isAddingDetailToLibrary &&
        (
          (state.lastDetailLibraryAddId && curIdLower)
            ? (state.lastDetailLibraryAddId === curIdLower)
            : Boolean(state.lastDetailLibraryAddName && curNameLower && state.lastDetailLibraryAddName === curNameLower)
        )
      );
      if (isComplete) {
        state.isAddingDetailToLibrary = false;
        dom.btnAddPlaylistLibrary.disabled = true;
        dom.btnAddPlaylistLibrary.classList.add('added');
        dom.btnAddPlaylistLibrary.classList.add('hidden');
      } else {
        dom.btnAddPlaylistLibrary.classList.remove('hidden');
        if (!isSamePendingDetail) {
          dom.btnAddPlaylistLibrary.disabled = false;
          dom.btnAddPlaylistLibrary.classList.remove('added');
          if (dom.btnAddPlaylistLibraryText) {
            dom.btnAddPlaylistLibraryText.textContent = translateTextToEn(
              (inLibrary || libCount > 0) ? 'Добавить весь альбом' : 'В медиатеку'
            );
          }
        }
      }
    }

    if (dom.detailTitle) dom.detailTitle.textContent = alb.name || translateTextToEn('Альбом');
    if (dom.detailMeta) {
      const parts = [];
      if (alb.artist) parts.push(alb.artist);
      if (alb.release_date) parts.push(String(alb.release_date).slice(0, 4));
      if (isComplete) {
        const totCnt = catCount || tracks.length || Number(alb.track_count || 0);
        if (totCnt > 0) parts.push(formatTracksCount(totCnt));
        parts.push(translateTextToEn('В медиатеке целиком'));
      } else if (!isComplete && isLibraryView && catCount > tracks.length) {
        const shownLib = libCount > 0 ? libCount : tracks.length;
        parts.push(translateTextToEn(`${shownLib} из ${catCount} треков в медиатеке`));
      } else if (!isComplete && !isLibraryView && libCount > 0 && catCount > libCount) {
        const totCnt = catCount || tracks.length || Number(alb.track_count || 0);
        if (totCnt > 0) parts.push(formatTracksCount(totCnt));
        parts.push(translateTextToEn(`${libCount} из ${catCount} треков в медиатеке`));
      } else {
        const totCnt = Number(alb.track_count || tracks.length || 0);
        if (totCnt > 0) parts.push(formatTracksCount(totCnt));
      }
      dom.detailMeta.textContent = parts.join(' • ');
    }
    if (dom.detailArtwork && (alb.artwork || alb.artwork_url)) {
      dom.detailArtwork.src = appendDeviceIdToUrl(alb.artwork || alb.artwork_url);
    }
    if (dom.detailBadge) dom.detailBadge.textContent = translateTextToEn('АЛЬБОМ');

    // Completeness Banner Slot: ONLY shown when !isComplete && isLibraryView && catCount > tracks.length
    if (dom.albumCompletenessBannerSlot) {
      dom.albumCompletenessBannerSlot.innerHTML = '';
      if (!isComplete && isLibraryView && catCount > tracks.length) {
        const banner = document.createElement('div');
        banner.className = 'album-completeness-banner';
        const savedCnt = tracks.length;
        const bannerTitle = translateTextToEn(`В медиатеке сохранено ${savedCnt} из ${catCount} треков этого альбома`);
        const btnLabel = translateTextToEn(`Показать полный альбом (${catCount}) →`);

        banner.innerHTML = `
          <div class="album-completeness-info">
            <span class="album-completeness-title">${escapeHtml(bannerTitle)}</span>
          </div>
          <button type="button" class="btn-show-complete-album">${escapeHtml(btnLabel)}</button>
        `;
        const showFullBtn = banner.querySelector('.btn-show-complete-album');
        if (showFullBtn) {
          showFullBtn.addEventListener('click', () => {
            triggerHaptic('light');
            openAlbumDetail({
              id: catAlbumId || alb.id || '',
              name: alb.name || '',
              artist: alb.artist || '',
              artwork: alb.artwork || alb.artwork_url || ''
            }, state.detailReturnOrigin || 'library-albums', { source: 'catalog' });
          });
        }
        dom.albumCompletenessBannerSlot.appendChild(banner);
      }
    }

    if (tracks.length === 0) {
      dom.playlistTracksList.innerHTML = `<div class="empty-state">${escapeHtml(translateTextToEn('Нет треков'))}</div>`;
      return;
    }

    const showSavedTrackBadge = Boolean(!isComplete && !isLibraryView && libCount > 0 && (catCount === 0 || libCount < catCount));

    dom.playlistTracksList.innerHTML = '';
    tracks.forEach((t, idx) => {
      const row = document.createElement('div');
      row.className = 'track-row';
      const dur = formatTime(t.duration || 0);
      const trackIsLocal = Boolean(t.is_local || t.isLocal);
      const savedBadgeHtml = (showSavedTrackBadge && trackIsLocal)
        ? `<span class="badge-in-lib-check">${escapeHtml(translateTextToEn('✓ В медиатеке'))}</span>`
        : '';

      row.innerHTML = `
        <span class="track-index-num">${escapeHtml(String(t.track_number || (idx + 1)))}</span>
        <div class="track-details">
          <div class="track-row-title-wrap">
            <span class="track-row-title">${escapeHtml(t.name || 'Без названия')}</span>
            ${savedBadgeHtml}
          </div>
          <span class="track-row-artist">${escapeHtml(t.artist || alb.artist || '')}</span>
        </div>
        <span class="track-row-dur">${dur}</span>
      `;

      const actionTrackObj = {
        ...t,
        name: t.name || '',
        artist: t.artist || alb.artist || '',
        album: t.album || alb.name || '',
        album_id: catAlbumId || alb.id || '',
        artwork: t.artwork || t.artwork_url || alb.artwork || alb.artwork_url || '',
        is_local: trackIsLocal || isLibraryView || isComplete
      };
      row.appendChild(createTrackRowActionButtons(actionTrackObj, {
        showDirectDelete: Boolean(trackIsLocal || isLibraryView || isComplete)
      }));

      row.addEventListener('click', () => {
        optimisticPlay();
        markWaitingForPlayback({ targetName: t.name || alb.name || '' });
        setUIBusy(true, 'Запуск трека...');
        send({
          action: 'play_album',
          params: {
            id: alb.id || '',
            name: alb.name || '',
            artist: alb.artist || '',
            tracks: tracks,
            track_index: idx + 1,
            shuffle: false
          }
        });
      });

      dom.playlistTracksList.appendChild(row);
    });
  }

  function updatePlaylistTracks(data) {
    const tracks = data.tracks || [];
    state.currentPlaylistTracks = tracks;
    if (state.currentPlaylistDetail && !state.currentPlaylistDetail.isAlbum) {
      const pl = state.currentPlaylistDetail;
      const plName = pl.name || pl.title || '';
      if (dom.detailMeta && tracks.length > 0) {
        dom.detailMeta.textContent = formatTracksCount(tracks.length);
      }
      const matchedLocal = findMatchingLocalPlaylist(plName, pl.id, tracks.length);
      const isAlreadyInLib = Boolean(pl.is_local || pl.in_library) || Boolean(matchedLocal);
      const canDeletePlaylist = isAlreadyInLib && !isProtectedSystemPlaylistClient(plName);
      if (dom.btnRemoveDetailLibrary) {
        dom.btnRemoveDetailLibrary.classList.toggle('hidden', !canDeletePlaylist);
      }
      if (dom.btnAddPlaylistLibrary && !state.isAddingDetailToLibrary) {
        if (isAlreadyInLib) {
          dom.btnAddPlaylistLibrary.disabled = true;
          dom.btnAddPlaylistLibrary.classList.add('added');
          dom.btnAddPlaylistLibrary.classList.add('hidden');
        } else {
          dom.btnAddPlaylistLibrary.disabled = false;
          if (dom.btnAddPlaylistLibraryText) dom.btnAddPlaylistLibraryText.textContent = translateTextToEn('В плейлисты');
          dom.btnAddPlaylistLibrary.classList.remove('added');
          dom.btnAddPlaylistLibrary.classList.remove('hidden');
        }
      }
    }
    if (!tracks || tracks.length === 0) {
      dom.playlistTracksList.innerHTML = `<div class="empty-state">${escapeHtml(translateTextToEn('Плейлист пуст'))}</div>`;
      return;
    }

    dom.playlistTracksList.innerHTML = '';
    tracks.forEach((t, idx) => {
      const row = document.createElement('div');
      row.className = 'track-row';
      const dur = formatTime(t.duration || 0);
      const trackIsLocal = Boolean(t.is_local || t.isLocal);

      row.innerHTML = `
        <span class="track-index-num">${idx + 1}</span>
        <div class="track-details">
          <span class="track-row-title">${escapeHtml(t.name || 'Без названия')}</span>
          <span class="track-row-artist">${escapeHtml(t.artist || '')}${t.album ? ' &bull; ' + escapeHtml(t.album) : ''}</span>
        </div>
        <span class="track-row-dur">${dur}</span>
      `;

      row.appendChild(createTrackRowActionButtons({
        ...t,
        is_local: trackIsLocal
      }, { showDirectDelete: trackIsLocal }));

      row.addEventListener('click', () => {
        if (!state.currentPlaylistDetail) return;
        const plName = state.currentPlaylistDetail.name || state.currentPlaylistDetail.title || '';
        const matchedLocal = findMatchingLocalPlaylist(plName, state.currentPlaylistDetail.id, tracks.length);
        const isExplicitLocalPlaylist = !state.currentPlaylistDetail.isAlbum && Boolean(state.currentPlaylistDetail.is_local);
        optimisticPlay();
        markWaitingForPlayback({ targetName: t.name || '', expectedTrackName: t.name || '' });
        setUIBusy(true, 'Запуск трека...');
        if (isExplicitLocalPlaylist) {
          send({
            action: 'play_playlist',
            params: {
              playlist: matchedLocal ? matchedLocal.name : plName,
              track_index: idx + 1,
              track_id: t.numeric_id || t.id,
              shuffle: false,
              is_local: true
            }
          });
        } else {
          send({
            action: 'play_playlist',
            params: {
              playlist: plName,
              id: state.currentPlaylistDetail.id || '',
              url: state.currentPlaylistDetail.url || '',
              track_index: idx + 1,
              track_id: t.numeric_id || t.id,
              tracks: state.currentPlaylistTracks || [],
              shuffle: false
            }
          });
        }
      });

      dom.playlistTracksList.appendChild(row);
    });
  }

  // --- Search Handling ---
  let searchDebounceTimer = null;

  function isIncompleteAiStyleQuery(rawQuery) {
    const clean = String(rawQuery || '').trim().toLowerCase();
    if (clean.length < 3) return true;
    return /^(в|в\s+с\w*|в\s+стиле(\s+(гр\w*|гуп\w*|арт\w*|исп\w*|муз\w*))?|как(\s+у(\s+(гр\w*|гуп\w*|арт\w*))?)?|похож\w*(\s+на(\s+(гр\w*|гуп\w*|арт\w*))?)?|в\s+духе(\s+(гр\w*|гуп\w*))?|что-?то(\s+вроде)?|типа(\s+(гр\w*|гуп\w*))?|in(\s+the(\s+style(\s+of)?)?)?|like|similar(\s+to)?)$/i.test(clean);
  }

  dom.searchInput.addEventListener('input', function (e) {
    const q = e.target.value.trim();
    state.searchQuery = q;
    dom.btnClearSearch.classList.toggle('hidden', q.length === 0);

    clearTimeout(searchDebounceTimer);
    if (state.searchScope === 'bridge') {
      return;
    }
    if (!q) {
      renderSearchPlaceholder();
      return;
    }

    if (state.searchScope === 'ai' && isIncompleteAiStyleQuery(q)) {
      return;
    }

    searchDebounceTimer = setTimeout(() => {
      executeSearch(q, state.searchScope);
    }, state.searchScope === 'ai' ? 560 : 280);
  });

  dom.searchInput.addEventListener('keydown', function (e) {
    if (e.key === 'Enter') {
      const q = e.target.value.trim();
      if (!q) return;
      clearTimeout(searchDebounceTimer);
      if (state.searchScope === 'bridge') {
        const arrowParts = q.split(/\s*(?:->|→|—>)\s*/);
        if (arrowParts.length >= 2 && arrowParts[0].trim() && arrowParts[1].trim()) {
          state.sonicBridgeFrom = arrowParts[0].trim();
          state.sonicBridgeTo = arrowParts.slice(1).join(' ').trim();
          triggerSonicBridgeSearch(false);
          return;
        }
        state.searchScope = 'all';
        dom.filterChips.forEach(c => c.classList.toggle('active', c.dataset.scope === 'all'));
      }
      executeSearch(q, state.searchScope);
    }
  });
