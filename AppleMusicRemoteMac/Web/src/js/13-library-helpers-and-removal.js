  // --- Library / Playlists Helpers, Browse Views, Completeness & Deletion ---
  function formatTracksCount(n) {
    const num = Math.max(0, Number(n) || 0);
    if (IS_EN) {
      return num === 1 ? '1 track' : `${num} tracks`;
    }
    const mod10 = num % 10;
    const mod100 = num % 100;
    if (mod10 === 1 && mod100 !== 11) return `${num} трек`;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return `${num} трека`;
    return `${num} треков`;
  }

  function formatAlbumsCount(n) {
    const num = Math.max(0, Number(n) || 0);
    if (IS_EN) {
      return num === 1 ? '1 album' : `${num} albums`;
    }
    const mod10 = num % 10;
    const mod100 = num % 100;
    if (mod10 === 1 && mod100 !== 11) return `${num} альбом`;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return `${num} альбома`;
    return `${num} альбомов`;
  }

  function normalizeAlbumMatchText(val) {
    if (!val) return '';
    let s = String(val).trim().toLowerCase();
    if (typeof s.normalize === 'function') {
      s = s.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
    }
    return s;
  }

  const normalizeTrackMatchText = normalizeAlbumMatchText;

  function albumsMatchClient(lhsName, lhsArtist, rhsName, rhsArtist) {
    const ln = normalizeAlbumMatchText(lhsName);
    const rn = normalizeAlbumMatchText(rhsName);
    if (!ln || ln !== rn) return false;
    const la = normalizeAlbumMatchText(lhsArtist);
    const ra = normalizeAlbumMatchText(rhsArtist);
    if (!la || !ra) return true;
    return la === ra || la.includes(ra) || ra.includes(la);
  }

  function tracksMatchClient(lhs, rhs) {
    if (!lhs || !rhs) return false;
    const lhsId = String(lhs.id || lhs.track_id || lhs.trackId || lhs.numeric_id || '').trim();
    const rhsId = String(rhs.id || rhs.track_id || rhs.trackId || rhs.numeric_id || '').trim();
    if (lhsId && rhsId && lhsId === rhsId) return true;
    const ln = normalizeTrackMatchText(lhs.name || lhs.trackName || '');
    const rn = normalizeTrackMatchText(rhs.name || rhs.trackName || '');
    if (!ln || ln !== rn) return false;
    const la = normalizeTrackMatchText(lhs.artist || lhs.artistName || '');
    const ra = normalizeTrackMatchText(rhs.artist || rhs.artistName || '');
    if (!la || !ra) return true;
    return la === ra || la.includes(ra) || ra.includes(la);
  }

  function findMatchingLibrarySong(trackObj) {
    if (!trackObj) return null;
    const fromSongs = (state.librarySongs || []).find(item => tracksMatchClient(item, trackObj));
    if (fromSongs) return fromSongs;
    const fromRecent = (state.libraryRecent && Array.isArray(state.libraryRecent.songs))
      ? state.libraryRecent.songs.find(item => tracksMatchClient(item, trackObj))
      : null;
    return fromRecent || null;
  }

  function isTrackInLibraryClient(trackObj) {
    if (!trackObj) return false;
    if (trackObj.is_local || trackObj.isLocal || trackObj.in_library) return true;
    return Boolean(findMatchingLibrarySong(trackObj));
  }

  function findMatchingLibraryArtist(artistName) {
    const target = normalizeTrackMatchText(artistName);
    if (!target) return null;
    return (state.libraryArtists || []).find(a => {
      const an = normalizeTrackMatchText(a && (a.name || a.artist));
      return an && an === target;
    }) || null;
  }

  function getArtistInitials(name) {
    const clean = String(name || '').replace(/[^\p{L}\p{N}\s]/gu, ' ').trim();
    if (!clean) return '♪';
    const parts = clean.split(/\s+/).filter(Boolean);
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return clean.slice(0, 2).toUpperCase();
  }

  function promptRemoveTrackFromLibrary(trackObj) {
    if (!trackObj) return;
    const tName = String(trackObj.name || trackObj.trackName || '').trim();
    const tArtist = String(trackObj.artist || trackObj.artistName || '').trim();
    const tAlbum = String(trackObj.album || trackObj.collectionName || '').trim();
    const matchedSong = findMatchingLibrarySong(trackObj);
    const rawId = String(
      trackObj.id ||
      trackObj.track_id ||
      trackObj.trackId ||
      trackObj.numeric_id ||
      (matchedSong && (matchedSong.id || matchedSong.track_id || matchedSong.numeric_id)) ||
      ''
    ).trim();
    if (!tName && !rawId) return;

    const msg = IS_EN
      ? `Track “${tName || 'Selected track'}”${tArtist ? ` — ${tArtist}` : ''} will be removed from your Apple Music library.`
      : `Трек «${tName || 'Выбранный трек'}»${tArtist ? ` (${tArtist})` : ''} будет удалён из вашей медиатеки Apple Music.`;

    confirmLibraryDeleteModal({
      title: 'Удалить трек из медиатеки?',
      message: msg,
      confirmLabel: 'Удалить',
      onConfirm: () => {
        send({
          action: 'remove_from_library',
          params: {
            type: 'track',
            id: rawId,
            track_id: rawId,
            name: tName,
            artist: tArtist,
            album: tAlbum
          }
        });
      }
    });
  }

  function promptRemoveAlbumFromLibrary(albObj) {
    if (!albObj) return;
    const aName = String(albObj.name || albObj.title || '').trim();
    const aArtist = String(albObj.artist || albObj.sub || albObj.subtitle || '').trim();
    const matchedAlb = findMatchingLibraryAlbum(albObj);
    const rawId = String(albObj.id || albObj.album_id || (matchedAlb && matchedAlb.id) || '').trim();
    if (!aName && !rawId) return;

    const msg = IS_EN
      ? `Album “${aName}”${aArtist ? ` — ${aArtist}` : ''} will be removed from your Apple Music library.`
      : `Альбом «${aName}»${aArtist ? ` — ${aArtist}` : ''} будет удалён из медиатеки Apple Music.`;

    confirmLibraryDeleteModal({
      title: 'Удалить альбом из медиатеки?',
      message: msg,
      confirmLabel: 'Удалить',
      onConfirm: () => {
        send({
          action: 'remove_from_library',
          params: {
            type: 'album',
            id: rawId,
            album_id: rawId,
            name: aName,
            album: aName,
            artist: aArtist
          }
        });
      }
    });
  }

  const PROTECTED_SYSTEM_PLAYLISTS = new Set([
    'музыка', 'music', 'медиатека', 'библиотека', 'musik', 'musique', 'música', 'musica', 'ミュージック', '音乐',
    'очередь amr', 'буфер amr', 'любимые песни', 'favorites', 'favourite songs', 'favorite songs', 'покупки', 'purchased', 'загружено', 'downloaded'
  ]);

  function isProtectedSystemPlaylistClient(name) {
    const clean = String(name || '').trim().toLowerCase();
    if (!clean) return false;
    return PROTECTED_SYSTEM_PLAYLISTS.has(clean);
  }

  function promptRemovePlaylistFromLibrary(plObj) {
    if (!plObj) return;
    const pName = String(plObj.name || plObj.title || '').trim();
    const matchedLocal = findMatchingLocalPlaylist(pName, plObj.id, 0, plObj.catalog_id || plObj.catalogId || '');
    const effectiveName = (matchedLocal && matchedLocal.name) ? matchedLocal.name : (plObj.local_name || pName);
    const rawId = String(plObj.id || plObj.playlist_id || (matchedLocal && (matchedLocal.id || matchedLocal.catalog_id)) || '').trim();
    if (!effectiveName && !rawId) return;
    if (isProtectedSystemPlaylistClient(effectiveName)) {
      showToast(IS_EN ? 'System playlist cannot be deleted' : 'Системный плейлист нельзя удалить');
      return;
    }

    const trkCount = Number(
      plObj.track_count ||
      plObj.trackCount ||
      (matchedLocal && (matchedLocal.track_count || matchedLocal.trackCount)) ||
      (Array.isArray(plObj.tracks) ? plObj.tracks.length : 0) ||
      0
    );

    const cntPart = trkCount > 0 ? ` (${formatTracksCount(trkCount)})` : '';
    const msg = IS_EN
      ? `Playlist “${effectiveName}”${cntPart} will be removed from your Apple Music playlists.`
      : `Плейлист «${effectiveName}»${cntPart} будет удалён из ваших плейлистов Apple Music.`;

    confirmLibraryDeleteModal({
      title: 'Удалить плейлист?',
      message: msg,
      confirmLabel: 'Удалить',
      onConfirm: () => {
        send({
          action: 'remove_from_library',
          params: {
            type: 'playlist',
            id: rawId,
            playlist_id: rawId,
            name: effectiveName,
            playlist: effectiveName
          }
        });
      }
    });
  }

  function promptRemoveArtistFromLibrary(artistObjOrName) {
    if (!artistObjOrName) return;
    const isObj = typeof artistObjOrName === 'object';
    const artName = String(isObj ? (artistObjOrName.name || artistObjOrName.artist || '') : artistObjOrName).trim();
    if (!artName) return;
    const matchedArt = findMatchingLibraryArtist(artName);
    const artId = String((isObj && artistObjOrName.id) || (matchedArt && matchedArt.id) || '').trim();
    const trkCount = Number((isObj && artistObjOrName.track_count) || (matchedArt && matchedArt.track_count) || 0);

    const msg = trkCount > 0
      ? (IS_EN
        ? `All tracks by ${artName} (${trkCount}) will be removed from your Apple Music library.`
        : `Все треки ${artName} (${trkCount}) будут удалены из вашей медиатеки Apple Music.`)
      : (IS_EN
        ? `All saved tracks by ${artName} will be removed from your Apple Music library.`
        : `Все сохранённые треки ${artName} будут удалены из вашей медиатеки Apple Music.`);

    confirmLibraryDeleteModal({
      title: 'Удалить исполнителя из медиатеки?',
      message: msg,
      confirmLabel: 'Удалить',
      onConfirm: () => {
        send({
          action: 'remove_from_library',
          params: {
            type: 'artist',
            id: artId,
            artist: artName,
            name: artName
          }
        });
      }
    });
  }

  let lastLibraryRemovalToastSig = '';
  let lastLibraryRemovalToastAt = 0;
  let librarySyncRefetchTimer = null;

  function handleLibraryRemovedOrChanged(data, eventType = 'library_changed', rawMsg = null) {
    const payload = (data && typeof data === 'object') ? data : {};
    const statusStr = payload.status || (rawMsg && rawMsg.status) || 'ok';
    if (statusStr === 'error') {
      const errMsg = translateTextToEn(payload.message || payload.error || (rawMsg && rawMsg.error) || 'Не удалось удалить из медиатеки');
      showToast(errMsg);
      return;
    }

    const remType = String(payload.type || '').toLowerCase();
    const delCount = payload.deleted_count !== undefined ? Number(payload.deleted_count) : null;
    const remId = String(payload.id || '').trim();
    const remName = String(payload.name || '').trim();
    const remArtist = String(payload.artist || '').trim();
    const remAlbum = String(payload.album || (remType === 'album' ? remName : '')).trim();
    const label = remName || remAlbum || remArtist;

    const isExplicitRemove = (
      eventType === 'remove_from_library' ||
      eventType === 'delete_from_library' ||
      eventType === 'remove_playlist_from_library' ||
      eventType === 'delete_playlist_from_library' ||
      Boolean(remType)
    );
    if (isExplicitRemove && (remType === 'playlist' || delCount === null || delCount > 0 || eventType !== 'library_changed')) {
      const toastSig = `${remType}|${label.toLowerCase()}|${delCount || 0}`;
      const now = Date.now();
      if (toastSig !== lastLibraryRemovalToastSig || (now - lastLibraryRemovalToastAt) > 1800) {
        lastLibraryRemovalToastSig = toastSig;
        lastLibraryRemovalToastAt = now;
        let toastText;
        if (remType === 'playlist') {
          toastText = IS_EN
            ? `Playlist deleted: ${label || 'playlist'}`
            : `Плейлист удалён: ${label || 'плейлист'}`;
        } else {
          const cntSuffix = (delCount && delCount > 0) ? ` (${delCount})` : '';
          toastText = IS_EN
            ? `Removed from Library: ${label || 'item'}${cntSuffix}`
            : `Удалено из медиатеки: ${label || 'элемент'}${cntSuffix}`;
        }
        showToast(toastText);
      }
    }

    if (remType !== 'playlist') {
      if (state.libraryRecent) state.libraryRecent.loaded = false;
      state.libraryArtistsLoaded = false;
      state.librarySongsLoaded = false;
    }

    const artistMatchesClientTarget = (candArtist, targetNorm) => {
      const ca = normalizeTrackMatchText(candArtist);
      if (!ca || !targetNorm) return false;
      if (ca === targetNorm) return true;
      const parts = ca.split(/\s*(?:,|&|\bfeat\.?\b|\bft\.?\b|\bwith\b|\/|;)\s*/i);
      return parts.some(p => p.trim() === targetNorm);
    };

    // Optimistic client state pruning
    if (remType === 'track') {
      const probe = { id: remId, name: remName, artist: remArtist, album: remAlbum };
      if (Array.isArray(state.librarySongs)) {
        state.librarySongs = state.librarySongs.filter(s => !tracksMatchClient(s, probe));
      }
      if (state.libraryRecent && Array.isArray(state.libraryRecent.songs)) {
        state.libraryRecent.songs = state.libraryRecent.songs.filter(s => !tracksMatchClient(s, probe));
      }
      if (state.track && tracksMatchClient(state.track, probe)) {
        state.track.is_local = false;
      }
      if (state.currentLibraryArtistDetail && Array.isArray(state.currentLibraryArtistDetail.songs)) {
        const beforeLen = state.currentLibraryArtistDetail.songs.length;
        state.currentLibraryArtistDetail.songs = state.currentLibraryArtistDetail.songs.filter(s => !tracksMatchClient(s, probe));
        if (state.currentLibraryArtistDetail.songs.length !== beforeLen) {
          state.currentLibraryArtistDetail.track_count = Math.max(0, (Number(state.currentLibraryArtistDetail.track_count) || beforeLen) - 1);
          if (dom.libraryArtistDetailPane && !dom.libraryArtistDetailPane.classList.contains('hidden')) {
            updateLibraryArtistDetail(state.currentLibraryArtistDetail);
          }
        }
      }
      if (
        state.currentAlbumDetail &&
        state.currentPlaylistDetail &&
        state.currentPlaylistDetail.isAlbum &&
        dom.playlistDetailPane &&
        !dom.playlistDetailPane.classList.contains('hidden')
      ) {
        const curAlb = state.currentAlbumDetail;
        const tracksArr = Array.isArray(curAlb.tracks) ? curAlb.tracks : [];
        const hasMatch = tracksArr.some(t => tracksMatchClient(t, probe));
        if (hasMatch) {
          if (curAlb.is_library_view) {
            curAlb.tracks = tracksArr.filter(t => !tracksMatchClient(t, probe));
          } else {
            tracksArr.forEach(t => {
              if (tracksMatchClient(t, probe)) {
                t.is_local = false;
                t.isLocal = false;
              }
            });
          }
          const prevLibCnt = Number(curAlb.library_track_count ?? tracksArr.length);
          curAlb.library_track_count = Math.max(0, prevLibCnt - 1);
          curAlb.in_library = curAlb.library_track_count > 0;
          curAlb.is_local = curAlb.in_library;
          curAlb.is_complete_in_library = false;
          updateAlbumDetails(curAlb);
        }
      }
    } else if (remType === 'album') {
      const targetAlbName = remAlbum || remName;
      if (Array.isArray(state.libraryAlbums)) {
        state.libraryAlbums = state.libraryAlbums.filter(a => {
          if (remId && String(a.id || '') === remId) return false;
          return !albumsMatchClient(a.name, a.artist, targetAlbName, remArtist);
        });
      }
      if (state.libraryRecent && Array.isArray(state.libraryRecent.albums)) {
        state.libraryRecent.albums = state.libraryRecent.albums.filter(a => {
          if (remId && String(a.id || '') === remId) return false;
          return !albumsMatchClient(a.name, a.artist, targetAlbName, remArtist);
        });
      }
      if (Array.isArray(state.librarySongs) && targetAlbName) {
        state.librarySongs = state.librarySongs.filter(s => !albumsMatchClient(s.album, s.artist, targetAlbName, remArtist));
      }
      if (state.libraryRecent && Array.isArray(state.libraryRecent.songs) && targetAlbName) {
        state.libraryRecent.songs = state.libraryRecent.songs.filter(s => !albumsMatchClient(s.album, s.artist, targetAlbName, remArtist));
      }
      if (state.track && targetAlbName && albumsMatchClient(state.track.album, state.track.artist, targetAlbName, remArtist)) {
        state.track.is_local = false;
      }
      if (state.currentLibraryArtistDetail) {
        const det = state.currentLibraryArtistDetail;
        if (Array.isArray(det.albums)) {
          det.albums = det.albums.filter(a => !albumsMatchClient(a.name, a.artist || det.artist, targetAlbName, remArtist));
          det.album_count = det.albums.length;
        }
        if (Array.isArray(det.songs) && targetAlbName) {
          det.songs = det.songs.filter(s => !albumsMatchClient(s.album, s.artist || det.artist, targetAlbName, remArtist));
          det.track_count = det.songs.length;
        }
        if (dom.libraryArtistDetailPane && !dom.libraryArtistDetailPane.classList.contains('hidden')) {
          updateLibraryArtistDetail(det);
        }
      }
      if (
        state.currentAlbumDetail &&
        state.currentPlaylistDetail &&
        state.currentPlaylistDetail.isAlbum &&
        dom.playlistDetailPane &&
        !dom.playlistDetailPane.classList.contains('hidden')
      ) {
        const curAlb = state.currentAlbumDetail;
        const idMatches = remId && String(curAlb.id || '') === remId;
        if (idMatches || albumsMatchClient(curAlb.name, curAlb.artist, targetAlbName, remArtist)) {
          curAlb.in_library = false;
          curAlb.is_local = false;
          curAlb.is_complete_in_library = false;
          curAlb.is_library_view = false;
          curAlb.library_track_count = 0;
          if (Array.isArray(curAlb.tracks)) {
            curAlb.tracks.forEach(t => {
              t.is_local = false;
              t.isLocal = false;
            });
          }
          updateAlbumDetails(curAlb);
        }
      }
    } else if (remType === 'artist') {
      const normArt = normalizeTrackMatchText(remArtist || remName);
      if (normArt) {
        if (Array.isArray(state.libraryArtists)) {
          state.libraryArtists = state.libraryArtists.filter(a => normalizeTrackMatchText(a.name || a.artist) !== normArt);
        }
        if (Array.isArray(state.libraryAlbums)) {
          state.libraryAlbums = state.libraryAlbums.filter(a => !artistMatchesClientTarget(a.artist, normArt));
        }
        if (Array.isArray(state.librarySongs)) {
          state.librarySongs = state.librarySongs.filter(s => !artistMatchesClientTarget(s.artist, normArt));
        }
        if (state.libraryRecent) {
          if (Array.isArray(state.libraryRecent.albums)) {
            state.libraryRecent.albums = state.libraryRecent.albums.filter(a => !artistMatchesClientTarget(a.artist, normArt));
          }
          if (Array.isArray(state.libraryRecent.songs)) {
            state.libraryRecent.songs = state.libraryRecent.songs.filter(s => !artistMatchesClientTarget(s.artist, normArt));
          }
        }
        if (state.track && artistMatchesClientTarget(state.track.artist, normArt)) {
          state.track.is_local = false;
        }
        if (
          state.currentLibraryArtistDetail &&
          normalizeTrackMatchText(state.currentLibraryArtistDetail.artist) === normArt
        ) {
          state.currentLibraryArtistDetail = null;
          if (dom.libraryArtistDetailPane && !dom.libraryArtistDetailPane.classList.contains('hidden')) {
            dom.libraryArtistDetailPane.classList.add('hidden');
            showLibraryBrowsePane();
            switchLibrarySubtab('artists', false);
          }
        }
        if (
          state.currentAlbumDetail &&
          state.currentPlaylistDetail &&
          state.currentPlaylistDetail.isAlbum &&
          dom.playlistDetailPane &&
          !dom.playlistDetailPane.classList.contains('hidden') &&
          normalizeTrackMatchText(state.currentAlbumDetail.artist) === normArt
        ) {
          const curAlb = state.currentAlbumDetail;
          curAlb.in_library = false;
          curAlb.is_local = false;
          curAlb.is_complete_in_library = false;
          curAlb.is_library_view = false;
          curAlb.library_track_count = 0;
          if (Array.isArray(curAlb.tracks)) {
            curAlb.tracks.forEach(t => {
              t.is_local = false;
              t.isLocal = false;
            });
          }
          updateAlbumDetails(curAlb);
        }
      }
    } else if (remType === 'playlist') {
      const remCatalogId = String(payload.catalog_id || '').trim();
      const remLocalName = String(payload.local_name || '').trim();
      const targetProbe = {
        id: remId,
        catalog_id: remCatalogId || (remId.toLowerCase().startsWith('pl.') ? remId : ''),
        name: remName,
        local_name: remLocalName
      };
      if (Array.isArray(state.playlists) && (remName || remLocalName || remId || remCatalogId)) {
        const filteredPls = state.playlists.filter(pl => {
          if (!pl) return false;
          return !playlistsMatchCrossLocaleClient(pl, targetProbe);
        });
        updatePlaylists({ playlists: filteredPls });
      }
      if (typeof syncSearchPlaylistCardsLibraryStatus === 'function') {
        syncSearchPlaylistCardsLibraryStatus(targetProbe, false);
      }
      if (
        state.currentPlaylistDetail &&
        !state.currentPlaylistDetail.isAlbum &&
        dom.playlistDetailPane &&
        !dom.playlistDetailPane.classList.contains('hidden')
      ) {
        const matchesCurrentDetail = playlistsMatchCrossLocaleClient(state.currentPlaylistDetail, targetProbe);
        if (matchesCurrentDetail) {
          state.currentPlaylistDetail.is_local = false;
          state.currentPlaylistDetail.in_library = false;
          if (state.detailReturnOrigin === 'playlists') {
            dom.playlistDetailPane.classList.add('hidden');
            state.detailReturnOrigin = null;
            navigateToView('view-playlists', 'playlists');
          } else {
            if (dom.btnRemoveDetailLibrary) {
              dom.btnRemoveDetailLibrary.classList.add('hidden');
            }
            if (dom.btnAddPlaylistLibrary) {
              dom.btnAddPlaylistLibrary.disabled = false;
              dom.btnAddPlaylistLibrary.classList.remove('added');
              dom.btnAddPlaylistLibrary.classList.remove('hidden');
              dom.btnAddPlaylistLibrary.title = translateTextToEn('Добавить в плейлисты Apple Music');
              if (dom.btnAddPlaylistLibraryText) {
                dom.btnAddPlaylistLibraryText.textContent = translateTextToEn('В плейлисты');
              }
            }
          }
        }
      }
    }

    if (remType !== 'playlist') {
      renderLibraryRecent();
      renderLibraryArtists();
      renderLibraryAlbums();
      renderLibrarySongs();
    }
    if (typeof renderStandbyQuickTiles === 'function') {
      renderStandbyQuickTiles();
    }
    if (dom.stationPickerModal && !dom.stationPickerModal.classList.contains('hidden')) {
      syncStationPickerModalUI();
    }

    // Debounced background sync from server
    if (librarySyncRefetchTimer) {
      clearTimeout(librarySyncRefetchTimer);
    }
    librarySyncRefetchTimer = setTimeout(() => {
      librarySyncRefetchTimer = null;
      if (!state.connected || !state.deviceAuthorized) return;
      if (remType === 'playlist') {
        send({ action: 'get_playlists', params: { refresh: true } });
        return;
      }
      send({ action: 'get_library_albums', params: { refresh: true } });
      const activeLibTab = state.libraryTab || 'recent';
      if (activeLibTab === 'recent') {
        send({ action: 'get_library_recent', params: { refresh: true } });
      } else if (activeLibTab === 'artists') {
        send({ action: 'get_library_artists', params: { refresh: true } });
      } else if (activeLibTab === 'songs') {
        send({ action: 'get_library_songs', params: { refresh: true } });
      }
    }, 280);
  }
