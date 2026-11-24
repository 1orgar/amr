  function createTrackRowActionButtons(trackObj, opts = {}) {
    const wrap = document.createElement('div');
    wrap.className = 'track-row-actions';

    if (opts.showDirectDelete && state.allowLibraryModification !== false) {
      const delBtn = document.createElement('button');
      delBtn.type = 'button';
      delBtn.className = 'track-row-action-btn track-row-del-btn';
      const delTitle = translateTextToEn('Удалить трек из медиатеки');
      delBtn.title = delTitle;
      delBtn.setAttribute('aria-label', delTitle);
      delBtn.innerHTML = `
        <svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <polyline points="3 6 5 6 21 6"/>
          <path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/>
          <path d="M10 11v6"/>
          <path d="M14 11v6"/>
        </svg>
      `;
      delBtn.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        promptRemoveTrackFromLibrary(trackObj);
      });
      wrap.appendChild(delBtn);
    }

    const moreBtn = document.createElement('button');
    moreBtn.type = 'button';
    moreBtn.className = 'track-row-action-btn track-row-more-btn';
    const moreTitle = translateTextToEn('Действия с треком');
    moreBtn.title = moreTitle;
    moreBtn.setAttribute('aria-label', moreTitle);
    moreBtn.innerHTML = `
      <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor">
        <circle cx="5" cy="12" r="1.8"/>
        <circle cx="12" cy="12" r="1.8"/>
        <circle cx="19" cy="12" r="1.8"/>
      </svg>
    `;
    moreBtn.addEventListener('click', (e) => {
      e.preventDefault();
      e.stopPropagation();
      openTrackActionsModal(trackObj);
    });
    wrap.appendChild(moreBtn);

    return wrap;
  }

  function updatePlaylists(data) {
    const list = data.playlists || (Array.isArray(data) ? data : []);
    state.playlists = list;
    if (dom.playlistsSectionSubtitle) {
      dom.playlistsSectionSubtitle.textContent = list.length > 0
        ? translateTextToEn(`Плейлисты Apple Music • ${list.length}`)
        : translateTextToEn('Плейлисты Apple Music');
    }
    if (typeof renderStandbyQuickTiles === 'function') {
      renderStandbyQuickTiles();
    }
    if (
      state.currentPlaylistDetail &&
      !state.currentPlaylistDetail.isAlbum &&
      dom.playlistDetailPane &&
      !dom.playlistDetailPane.classList.contains('hidden')
    ) {
      const curPlName = state.currentPlaylistDetail.name || state.currentPlaylistDetail.title || '';
      const matchedLocal = findMatchingLocalPlaylist(
        curPlName,
        state.currentPlaylistDetail.id,
        0,
        state.currentPlaylistDetail.catalog_id || state.currentPlaylistDetail.catalogId || ''
      );
      if (matchedLocal) {
        state.isAddingDetailToLibrary = false;
        state.currentPlaylistDetail.is_local = true;
        state.currentPlaylistDetail.in_library = true;
        const syncedCnt = Number(matchedLocal.track_count || matchedLocal.trackCount || 0);
        if (syncedCnt > 0 && dom.detailMeta) {
          state.currentPlaylistDetail.track_count = syncedCnt;
          dom.detailMeta.textContent = formatTracksCount(syncedCnt);
        }
        if (dom.btnAddPlaylistLibrary) {
          dom.btnAddPlaylistLibrary.disabled = true;
          dom.btnAddPlaylistLibrary.classList.add('added');
          dom.btnAddPlaylistLibrary.classList.add('hidden');
        }
        if (dom.btnRemoveDetailLibrary && !isProtectedSystemPlaylistClient(curPlName)) {
          if (dom.btnRemoveDetailLibraryText) {
            dom.btnRemoveDetailLibraryText.textContent = translateTextToEn('Удалить плейлист');
          }
          dom.btnRemoveDetailLibrary.classList.remove('hidden');
        }
      }
    }
    if (!dom.playlistsGrid) return;

    if (list.length === 0) {
      dom.playlistsGrid.innerHTML = `<div class="empty-state">${escapeHtml(translateTextToEn('Плейлисты не найдены'))}</div>`;
      return;
    }

    dom.playlistsGrid.innerHTML = '';
    list.forEach(pl => {
      const card = document.createElement('div');
      card.className = 'playlist-card';
      const art = appendDeviceIdToUrl(pl.artwork_url || pl.artworkUrl || 'apple-touch-icon.svg');
      const count = pl.track_count || pl.trackCount || 0;
      const canDelete = !isProtectedSystemPlaylistClient(pl.name);
      const delBtnTitle = translateTextToEn('Удалить плейлист из медиатеки');

      card.innerHTML = `
        <div class="playlist-card-art-wrap">
          <img class="playlist-card-art" src="${escapeHtml(art)}" alt="" loading="lazy" decoding="async" data-fallback-mode="next-flex">
          <div class="playlist-card-art-fallback" style="display:none;">
            <svg viewBox="0 0 24 24" width="36" height="36" fill="none" stroke="#6e6e73" stroke-width="1.8">
              <path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>
            </svg>
          </div>
          ${canDelete ? `<button type="button" class="playlist-card-del-btn" title="${escapeHtml(delBtnTitle)}" aria-label="${escapeHtml(delBtnTitle)}">
            <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round">
              <polyline points="3 6 5 6 21 6"/>
              <path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/>
              <path d="M10 11v6M14 11v6"/>
            </svg>
          </button>` : ''}
        </div>
        <span class="playlist-card-title">${escapeHtml(pl.name)}</span>
        <span class="playlist-card-count">${escapeHtml(formatTracksCount(count))}</span>
      `;

      const delCardBtn = card.querySelector('.playlist-card-del-btn');
      if (delCardBtn) {
        delCardBtn.addEventListener('click', (e) => {
          e.preventDefault();
          e.stopPropagation();
          promptRemovePlaylistFromLibrary({ ...pl, is_local: true });
        });
      }

      card.addEventListener('click', () => {
        openPlaylistDetail({ ...pl, is_local: true }, 'playlists');
      });

      dom.playlistsGrid.appendChild(card);
    });
  }

  if (dom.btnRefreshPlaylists) {
    dom.btnRefreshPlaylists.addEventListener('click', () => {
      triggerHaptic('light');
      if (dom.playlistsGrid) {
        dom.playlistsGrid.innerHTML = `<div class="loading-state">${escapeHtml(translateTextToEn('Загрузка плейлистов...'))}</div>`;
      }
      send({ action: 'get_playlists', params: { refresh: true } });
    });
  }

  function findMatchingLibraryAlbum(alb) {
    if (!alb) return null;
    const targetId = String(alb.id || '').trim();
    const isCatalogTarget = Number(targetId) >= 10000000;
    const targetName = alb.name || alb.title || '';
    const targetArtist = alb.artist || alb.sub || alb.subtitle || '';
    return (state.libraryAlbums || []).find(item => {
      const itemId = String(item.id || '').trim();
      if (isCatalogTarget && Number(itemId) >= 10000000 && itemId === targetId) {
        return true;
      }
      return albumsMatchClient(item.name, item.artist, targetName, targetArtist);
    }) || null;
  }

  function upsertOptimisticPlaylist(pl) {
    if (!pl || !pl.name) return;
    const rawPlId = String(pl.id || '').trim();
    const rawCatId = String(pl.catalog_id || pl.catalogId || (rawPlId.toLowerCase().startsWith('pl.') ? rawPlId : '')).trim();
    const probe = { id: rawPlId, catalog_id: rawCatId, name: pl.name };
    const existing = Array.isArray(state.playlists) ? [...state.playlists] : [];
    const idx = existing.findIndex(item => playlistsMatchCrossLocaleClient(item, probe));
    const nextArt = pl.artwork_url || pl.artworkUrl || pl.artwork || '';
    const nextCnt = Number(pl.track_count || pl.trackCount || 0);
    if (idx >= 0) {
      const prev = existing[idx];
      const prevArt = prev.artwork_url || prev.artworkUrl || '';
      existing[idx] = {
        ...prev,
        id: prev.id || rawPlId,
        catalog_id: prev.catalog_id || prev.catalogId || rawCatId,
        track_count: Math.max(Number(prev.track_count || prev.trackCount || 0), nextCnt),
        artwork_url: (prevArt && !String(prevArt).startsWith('/api/artwork/playlist'))
          ? prevArt
          : (nextArt || prevArt)
      };
    } else {
      existing.push({
        id: rawPlId,
        catalog_id: rawCatId,
        name: pl.name,
        track_count: nextCnt,
        artwork_url: nextArt,
        is_playlist: true,
        is_local: true,
        in_library: true
      });
      existing.sort((a, b) => String(a.name || '').localeCompare(String(b.name || ''), 'ru', { sensitivity: 'base' }));
    }
    if (typeof syncSearchPlaylistCardsLibraryStatus === 'function') {
      syncSearchPlaylistCardsLibraryStatus(probe, true);
    }
    updatePlaylists({ playlists: existing });
  }

  function upsertOptimisticLibraryAlbum(alb) {
    if (!alb || !alb.name) return;
    const existing = Array.isArray(state.libraryAlbums) ? [...state.libraryAlbums] : [];
    const filtered = existing.filter(item => {
      if (alb.id && item.id && Number(alb.id) >= 10000000 && String(alb.id) === String(item.id)) {
        return false;
      }
      return !albumsMatchClient(item.name, item.artist, alb.name, alb.artist);
    });
    filtered.unshift({ ...alb, in_library: true });
    state.libraryAlbums = filtered;
    renderLibraryAlbums();
    if (typeof renderStandbyQuickTiles === 'function') {
      renderStandbyQuickTiles();
    }
  }

  function showLibraryBrowsePane() {
    if (dom.playlistDetailPane) dom.playlistDetailPane.classList.add('hidden');
    if (dom.libraryArtistDetailPane) dom.libraryArtistDetailPane.classList.add('hidden');
    if (dom.playlistsBrowsePane) dom.playlistsBrowsePane.classList.remove('hidden');
  }

  function syncLibrarySubtitle() {
    if (!dom.librarySectionSubtitle) return;
    const tab = state.libraryTab || 'recent';
    if (tab === 'albums') {
      const cnt = (state.libraryAlbums || []).length;
      dom.librarySectionSubtitle.textContent = cnt > 0
        ? translateTextToEn(`Альбомы в медиатеке • ${cnt}`)
        : translateTextToEn('Альбомы в медиатеке');
    } else if (tab === 'artists') {
      const cnt = (state.libraryArtists || []).length;
      dom.librarySectionSubtitle.textContent = cnt > 0
        ? translateTextToEn(`Исполнители в медиатеке • ${cnt}`)
        : translateTextToEn('Исполнители в медиатеке');
    } else if (tab === 'songs') {
      const cnt = (state.librarySongs || []).length;
      dom.librarySectionSubtitle.textContent = cnt > 0
        ? translateTextToEn(`Треки в медиатеке • ${cnt}`)
        : translateTextToEn('Треки в медиатеке');
    } else {
      dom.librarySectionSubtitle.textContent = translateTextToEn('Недавно добавленные в медиатеку');
    }
  }

  function resolveBestLibraryAlbumArtwork(albumName, artistName, currentArt) {
    const raw = String(currentArt || '').trim();
    if (raw.startsWith('http://') || raw.startsWith('https://') || raw.startsWith('data:')) {
      return raw;
    }
    if (albumName) {
      const pool = Array.isArray(state.libraryAlbums) ? state.libraryAlbums : [];
      for (let i = 0; i < pool.length; i += 1) {
        const cand = pool[i];
        if (!cand) continue;
        const candArt = String(cand.artwork || cand.artwork_url || cand.artworkUrl || '').trim();
        if ((candArt.startsWith('http://') || candArt.startsWith('https://')) &&
            albumsMatchClient(cand.name, cand.artist, albumName, artistName)) {
          return candArt;
        }
      }
    }
    return raw;
  }

  function createLibraryAlbumCardElement(alb, originKey) {
    const card = document.createElement('div');
    card.className = 'playlist-card';
    const candidateArt = resolveBestLibraryAlbumArtwork(
      alb.name,
      alb.artist,
      alb.artwork || alb.artwork_url || alb.artworkUrl || ''
    );
    const rawArt = candidateArt || 'apple-touch-icon.svg';
    const art = appendDeviceIdToUrl(rawArt);
    const count = alb.track_count || alb.trackCount || 0;
    const artistText = (alb.artist || '').trim();
    const metaParts = [];
    if (artistText) metaParts.push(artistText);
    if (count > 0) metaParts.push(formatTracksCount(count));
    const metaStr = metaParts.join(' • ');

    card.innerHTML = `
      <div class="playlist-card-art-wrap">
        <img class="playlist-card-art" src="${escapeHtml(art)}" alt="" loading="lazy" decoding="async" data-fallback-mode="next-flex">
        <div class="playlist-card-art-fallback" style="display:none;">
          <svg viewBox="0 0 24 24" width="36" height="36" fill="none" stroke="#6e6e73" stroke-width="1.8">
            <circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="3"/>
          </svg>
        </div>
      </div>
      <span class="playlist-card-title">${escapeHtml(alb.name || 'Альбом')}</span>
      <span class="playlist-card-count">${escapeHtml(metaStr)}</span>
    `;

    card.addEventListener('click', () => {
      openAlbumDetail({ ...alb, artwork: candidateArt || alb.artwork, in_library: true }, originKey, { source: 'library' });
    });

    return card;
  }

  function createLibrarySongRowElement(s, onPlayClick) {
    const row = document.createElement('div');
    row.className = 'track-row';
    const artistStr = s.artist || s.artistName || '';
    const albumStr = s.album || s.collectionName || '';
    const upgradedArt = resolveBestLibraryAlbumArtwork(
      albumStr,
      artistStr,
      s.artwork_url || s.artwork || getArtworkSrc(s) || ''
    );
    const artSrc = appendDeviceIdToUrl(upgradedArt || 'apple-touch-icon.svg');
    const dur = s.duration ? formatTime(s.duration) : '';
    const subParts = [artistStr, albumStr].filter(Boolean);

    row.innerHTML = `
      <img class="track-thumb" src="${escapeHtml(artSrc)}" alt="" loading="lazy" decoding="async" data-fallback-icon="apple-touch-icon.svg">
      <div class="track-details">
        <span class="track-row-title">${escapeHtml(s.name || s.trackName || 'Без названия')}</span>
        <span class="track-row-artist">${escapeHtml(subParts.join(' • '))}</span>
      </div>
      ${dur ? `<span class="track-row-dur">${dur}</span>` : ''}
    `;

    const normalizedTrack = {
      ...s,
      name: s.name || s.trackName || '',
      artist: artistStr,
      album: albumStr,
      artwork: s.artwork || s.artwork_url || '',
      is_local: true
    };
    row.appendChild(createTrackRowActionButtons(normalizedTrack, { showDirectDelete: true }));
    row.addEventListener('click', onPlayClick);
    return row;
  }

  function playLibrarySongsWindow(pool, startIdx, shuffle, queueTitle) {
    if (!Array.isArray(pool) || pool.length === 0) return;
    const maxBatch = 350;
    let sliceSongs = pool;
    let adjustedIdx = startIdx;
    if (!shuffle && pool.length > maxBatch && Number.isInteger(startIdx) && startIdx >= 0) {
      const winStart = Math.max(0, Math.min(startIdx - 25, pool.length - maxBatch));
      sliceSongs = pool.slice(winStart, winStart + maxBatch);
      adjustedIdx = startIdx - winStart;
    } else if (pool.length > maxBatch) {
      sliceSongs = pool.slice(0, maxBatch);
      if (Number.isInteger(adjustedIdx) && adjustedIdx >= maxBatch) adjustedIdx = 0;
    }
    const localMarked = sliceSongs.map(x => ({ ...x, is_local: true }));
    playSearchResultsList(localMarked, Boolean(shuffle), shuffle ? null : adjustedIdx, {
      queueName: translateTextToEn(queueTitle || 'Треки медиатеки'),
      query: ''
    });
  }

  // Subtab 1: Недавние
  function renderLibraryRecent() {
    if (!dom.libraryRecentPane) return;
    syncLibrarySubtitle();
    if (!state.libraryRecent || !state.libraryRecent.loaded) return;

    const albums = Array.isArray(state.libraryRecent.albums) ? state.libraryRecent.albums : [];
    const songs = Array.isArray(state.libraryRecent.songs) ? state.libraryRecent.songs : [];

    if (albums.length === 0 && songs.length === 0) {
      dom.libraryRecentPane.innerHTML = `<div class="empty-state">${escapeHtml(translateTextToEn('Недавно добавленные элементы не найдены'))}</div>`;
      return;
    }

    dom.libraryRecentPane.innerHTML = '';

    if (albums.length > 0) {
      const albBlock = document.createElement('div');
      albBlock.className = 'library-group-block';
      const heading = document.createElement('h3');
      heading.className = 'library-group-heading';
      heading.textContent = translateTextToEn('НЕДАВНО ДОБАВЛЕННЫЕ АЛЬБОМЫ');
      albBlock.appendChild(heading);

      const grid = document.createElement('div');
      grid.className = 'playlists-grid';
      albums.forEach(alb => {
        grid.appendChild(createLibraryAlbumCardElement(alb, 'library-recent'));
      });
      albBlock.appendChild(grid);
      dom.libraryRecentPane.appendChild(albBlock);
    }

    if (songs.length > 0) {
      const sngBlock = document.createElement('div');
      sngBlock.className = 'library-group-block';
      const heading = document.createElement('h3');
      heading.className = 'library-group-heading';
      heading.textContent = translateTextToEn('НЕДАВНО ДОБАВЛЕННЫЕ ТРЕКИ');
      sngBlock.appendChild(heading);

      const listEl = document.createElement('div');
      listEl.className = 'track-list';
      songs.forEach((s, idx) => {
        listEl.appendChild(createLibrarySongRowElement(s, () => {
          playLibrarySongsWindow(songs, idx, false, 'Недавние в медиатеке');
        }));
      });
      sngBlock.appendChild(listEl);
      dom.libraryRecentPane.appendChild(sngBlock);
    }
  }

  function updateLibraryRecent(data) {
    const albums = (data && Array.isArray(data.albums)) ? data.albums : [];
    const songs = (data && Array.isArray(data.songs)) ? data.songs : [];
    state.libraryRecent = {
      albums,
      songs,
      loaded: true
    };
    renderLibraryRecent();
  }

  // Subtab 2: Артисты + Artist Library Detail
  function renderLibraryArtists() {
    if (!dom.libraryArtistsList) return;
    syncLibrarySubtitle();
    if (!state.libraryArtistsLoaded) return;

    const allArtists = Array.isArray(state.libraryArtists) ? state.libraryArtists : [];
    const rawFilter = String(state.libraryArtistFilter || '').trim();
    const q = normalizeTrackMatchText(rawFilter);

    if (dom.libraryArtistsToolbar) {
      dom.libraryArtistsToolbar.classList.toggle('hidden', allArtists.length <= 8 && !rawFilter);
    }
    if (dom.btnClearArtistsFilter) {
      dom.btnClearArtistsFilter.classList.toggle('hidden', !rawFilter);
    }

    if (allArtists.length === 0) {
      dom.libraryArtistsList.innerHTML = `<div class="empty-state">${escapeHtml(translateTextToEn('Исполнители в медиатеке не найдены'))}</div>`;
      return;
    }

    const filtered = q
      ? allArtists.filter(a => normalizeTrackMatchText(a && (a.name || a.artist)).includes(q))
      : allArtists;

    if (filtered.length === 0) {
      dom.libraryArtistsList.innerHTML = `<div class="empty-state">${escapeHtml(translateTextToEn('Ничего не найдено'))}</div>`;
      return;
    }

    dom.libraryArtistsList.innerHTML = '';
    const frag = document.createDocumentFragment();
    filtered.forEach(art => {
      const artName = String(art.name || art.artist || '').trim();
      if (!artName) return;
      const row = document.createElement('div');
      row.className = 'library-artist-row';

      const albCount = Number(art.album_count || art.albumCount || 0);
      const trkCount = Number(art.track_count || art.trackCount || 0);
      const metaParts = [];
      if (albCount > 0) metaParts.push(formatAlbumsCount(albCount));
      if (trkCount > 0) metaParts.push(formatTracksCount(trkCount));
      const metaStr = metaParts.join(' • ');
      const rawAvatar = art.artwork || art.artwork_url || '';
      const avatarUrl = rawAvatar ? appendDeviceIdToUrl(rawAvatar) : '';
      const initials = getArtistInitials(artName);

      row.innerHTML = `
        <div class="artist-avatar-circle">
          ${avatarUrl ? `<img src="${escapeHtml(avatarUrl)}" alt="" loading="lazy" data-fallback-mode="next-flex">` : ''}
          <span class="artist-avatar-initials" style="${avatarUrl ? 'display:none;' : ''}">${escapeHtml(initials)}</span>
        </div>
        <div class="artist-row-info">
          <span class="artist-row-name">${escapeHtml(artName)}</span>
          ${metaStr ? `<span class="artist-row-meta">${escapeHtml(metaStr)}</span>` : ''}
        </div>
      `;

      const actionsWrap = document.createElement('div');
      actionsWrap.className = 'track-row-actions';
      const delBtn = document.createElement('button');
      delBtn.type = 'button';
      delBtn.className = 'track-row-action-btn track-row-del-btn';
      const delTitle = translateTextToEn('Удалить исполнителя из медиатеки');
      delBtn.title = delTitle;
      delBtn.setAttribute('aria-label', delTitle);
      delBtn.innerHTML = `
        <svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <polyline points="3 6 5 6 21 6"/>
          <path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/>
          <path d="M10 11v6"/>
          <path d="M14 11v6"/>
        </svg>
      `;
      delBtn.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        promptRemoveArtistFromLibrary(art);
      });
      actionsWrap.appendChild(delBtn);
      row.appendChild(actionsWrap);

      const chev = document.createElement('span');
      chev.className = 'artist-row-chevron';
      chev.innerHTML = `<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><polyline points="9 18 15 12 9 6"/></svg>`;
      row.appendChild(chev);

      row.addEventListener('click', () => {
        openLibraryArtistDetail(art);
      });

      frag.appendChild(row);
    });
    dom.libraryArtistsList.appendChild(frag);
  }

  function updateLibraryArtists(data) {
    const list = (data && Array.isArray(data.artists)) ? data.artists : (Array.isArray(data) ? data : []);
    state.libraryArtists = list;
    state.libraryArtistsLoaded = true;
    renderLibraryArtists();
    if (dom.stationPickerModal && !dom.stationPickerModal.classList.contains('hidden')) {
      syncStationPickerModalUI();
    }
  }

  if (dom.libraryArtistsFilter) {
    dom.libraryArtistsFilter.addEventListener('input', (e) => {
      state.libraryArtistFilter = e.target.value || '';
      renderLibraryArtists();
    });
  }
  if (dom.btnClearArtistsFilter) {
    dom.btnClearArtistsFilter.addEventListener('click', () => {
      state.libraryArtistFilter = '';
      if (dom.libraryArtistsFilter) dom.libraryArtistsFilter.value = '';
      renderLibraryArtists();
    });
  }

  function syncArtistDetailAvatar(artUrl, artistName) {
    const initials = getArtistInitials(artistName);
    if (dom.artistDetailInitials) {
      dom.artistDetailInitials.textContent = initials;
    }
    if (dom.artistDetailArtwork) {
      if (artUrl) {
        dom.artistDetailArtwork.src = appendDeviceIdToUrl(artUrl);
        dom.artistDetailArtwork.classList.remove('hidden');
        if (dom.artistDetailInitials) dom.artistDetailInitials.classList.add('hidden');
        dom.artistDetailArtwork.onerror = () => {
          dom.artistDetailArtwork.classList.add('hidden');
          if (dom.artistDetailInitials) dom.artistDetailInitials.classList.remove('hidden');
        };
      } else {
        dom.artistDetailArtwork.classList.add('hidden');
        if (dom.artistDetailInitials) dom.artistDetailInitials.classList.remove('hidden');
      }
    }
  }

  function openLibraryArtistDetail(art) {
    const artistName = String((art && (art.name || art.artist)) || '').trim();
    if (!artistName) return;
    triggerHaptic('light');

    const albCount = Number((art && (art.album_count || art.albumCount)) || 0);
    const trkCount = Number((art && (art.track_count || art.trackCount)) || 0);
    const rawAvatar = (art && (art.artwork || art.artwork_url)) || '';

    state.currentLibraryArtistDetail = {
      artist: artistName,
      id: (art && art.id) || '',
      album_count: albCount,
      track_count: trkCount,
      artwork: rawAvatar,
      albums: [],
      songs: []
    };

    if (dom.artistDetailTitle) dom.artistDetailTitle.textContent = artistName;
    if (dom.artistDetailMeta) {
      const mParts = [];
      if (albCount > 0) mParts.push(formatAlbumsCount(albCount));
      if (trkCount > 0) mParts.push(formatTracksCount(trkCount));
      dom.artistDetailMeta.textContent = mParts.join(' • ') || translateTextToEn('Медиатека Apple Music');
    }
    syncArtistDetailAvatar(rawAvatar, artistName);

    if (dom.artistDetailContent) {
      dom.artistDetailContent.innerHTML = `<div class="loading-state">${escapeHtml(translateTextToEn('Загрузка медиатеки артиста...'))}</div>`;
    }

    navigateToView('view-library', 'library', true);
    syncNavHighlightForDetailOrigin('library-artists');
    if (dom.playlistsBrowsePane) dom.playlistsBrowsePane.classList.add('hidden');
    if (dom.playlistDetailPane) dom.playlistDetailPane.classList.add('hidden');
    if (dom.libraryArtistDetailPane) dom.libraryArtistDetailPane.classList.remove('hidden');

    send({
      action: 'get_library_artist_detail',
      params: {
        artist: artistName
      }
    });
  }
