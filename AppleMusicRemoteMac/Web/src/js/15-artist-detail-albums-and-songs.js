  function updateLibraryArtistDetail(data) {
    if (!data || typeof data !== 'object') return;
    const artistName = String(data.artist || data.name || (state.currentLibraryArtistDetail && state.currentLibraryArtistDetail.artist) || '').trim();
    const albums = Array.isArray(data.albums) ? data.albums : [];
    const songs = Array.isArray(data.songs) ? data.songs : [];
    const albCount = Number(data.album_count !== undefined ? data.album_count : albums.length);
    const trkCount = Number(data.track_count !== undefined ? data.track_count : songs.length);
    const fallbackArt = (albums[0] && (albums[0].artwork || albums[0].artwork_url)) || (songs[0] && (songs[0].artwork || songs[0].artwork_url)) || '';
    const avatarUrl = data.artwork || data.artwork_url || (state.currentLibraryArtistDetail && state.currentLibraryArtistDetail.artwork) || fallbackArt;

    state.currentLibraryArtistDetail = {
      artist: artistName,
      id: data.id || (state.currentLibraryArtistDetail && state.currentLibraryArtistDetail.id) || '',
      album_count: albCount,
      track_count: trkCount,
      artwork: avatarUrl,
      albums,
      songs
    };

    if (dom.artistDetailTitle && artistName) {
      dom.artistDetailTitle.textContent = artistName;
    }
    if (dom.artistDetailMeta) {
      const mParts = [];
      if (albCount > 0) mParts.push(formatAlbumsCount(albCount));
      if (trkCount > 0) mParts.push(formatTracksCount(trkCount));
      dom.artistDetailMeta.textContent = mParts.join(' • ') || translateTextToEn('Медиатека Apple Music');
    }
    syncArtistDetailAvatar(avatarUrl, artistName);

    if (!dom.artistDetailContent) return;
    if (albums.length === 0 && songs.length === 0) {
      dom.artistDetailContent.innerHTML = `<div class="empty-state">${escapeHtml(translateTextToEn('Нет сохранённых треков этого исполнителя'))}</div>`;
      return;
    }

    dom.artistDetailContent.innerHTML = '';

    if (albums.length > 0) {
      const albBlock = document.createElement('div');
      albBlock.className = 'library-group-block';
      const heading = document.createElement('h3');
      heading.className = 'library-group-heading';
      heading.textContent = translateTextToEn('АЛЬБОМЫ В МЕДИАТЕКЕ');
      albBlock.appendChild(heading);

      const grid = document.createElement('div');
      grid.className = 'playlists-grid';
      albums.forEach(alb => {
        grid.appendChild(createLibraryAlbumCardElement({
          ...alb,
          artist: alb.artist || artistName
        }, 'library-artist-detail'));
      });
      albBlock.appendChild(grid);
      dom.artistDetailContent.appendChild(albBlock);
    }

    if (songs.length > 0) {
      const sngBlock = document.createElement('div');
      sngBlock.className = 'library-group-block';
      const heading = document.createElement('h3');
      heading.className = 'library-group-heading';
      heading.textContent = translateTextToEn('ТРЕКИ В МЕДИАТЕКЕ');
      sngBlock.appendChild(heading);

      const listEl = document.createElement('div');
      listEl.className = 'track-list';
      songs.forEach((s, idx) => {
        const enrichedSong = { ...s, artist: s.artist || artistName };
        listEl.appendChild(createLibrarySongRowElement(enrichedSong, () => {
          const pool = songs.map(item => ({ ...item, artist: item.artist || artistName, is_local: true }));
          playLibrarySongsWindow(pool, idx, false, artistName);
        }));
      });
      sngBlock.appendChild(listEl);
      dom.artistDetailContent.appendChild(sngBlock);
    }
  }

  if (dom.btnBackToArtists) {
    dom.btnBackToArtists.addEventListener('click', () => {
      triggerHaptic('light');
      if (dom.libraryArtistDetailPane) dom.libraryArtistDetailPane.classList.add('hidden');
      showLibraryBrowsePane();
      switchLibrarySubtab('artists', false);
      syncNavHighlightForDetailOrigin('library-artists');
    });
  }

  if (dom.btnPlayArtistLibrary) {
    dom.btnPlayArtistLibrary.addEventListener('click', () => {
      const det = state.currentLibraryArtistDetail;
      if (!det || !Array.isArray(det.songs) || det.songs.length === 0) return;
      const pool = det.songs.map(s => ({ ...s, artist: s.artist || det.artist, is_local: true }));
      playLibrarySongsWindow(pool, 0, false, det.artist || 'Медиатека');
    });
  }

  if (dom.btnShuffleArtistLibrary) {
    dom.btnShuffleArtistLibrary.addEventListener('click', () => {
      const det = state.currentLibraryArtistDetail;
      if (!det || !Array.isArray(det.songs) || det.songs.length === 0) return;
      const pool = det.songs.map(s => ({ ...s, artist: s.artist || det.artist, is_local: true }));
      playLibrarySongsWindow(pool, null, true, det.artist || 'Медиатека');
    });
  }

  if (dom.btnRemoveArtistDetailLibrary) {
    dom.btnRemoveArtistDetailLibrary.addEventListener('click', () => {
      if (state.currentLibraryArtistDetail) {
        promptRemoveArtistFromLibrary(state.currentLibraryArtistDetail);
      }
    });
  }

  // Subtab 3: Альбомы
  function renderLibraryAlbums() {
    if (!dom.libraryAlbumsGrid) return;
    const list = state.libraryAlbums || [];
    syncLibrarySubtitle();

    if (list.length === 0) {
      dom.libraryAlbumsGrid.innerHTML = `<div class="empty-state">${escapeHtml(translateTextToEn('Альбомы в медиатеке не найдены'))}</div>`;
      return;
    }

    dom.libraryAlbumsGrid.innerHTML = '';
    const frag = document.createDocumentFragment();
    list.forEach(alb => {
      frag.appendChild(createLibraryAlbumCardElement(alb, 'library-albums'));
    });
    dom.libraryAlbumsGrid.appendChild(frag);
  }

  function updateLibraryAlbums(data) {
    const list = (data && data.albums) ? data.albums : (Array.isArray(data) ? data : []);
    state.libraryAlbums = list;
    renderLibraryAlbums();
    if (state.libraryRecent && state.libraryRecent.loaded) {
      let upgradedAny = false;
      if (Array.isArray(state.libraryRecent.albums)) {
        state.libraryRecent.albums = state.libraryRecent.albums.map(alb => {
          const cur = String(alb.artwork || alb.artwork_url || '').trim();
          const best = resolveBestLibraryAlbumArtwork(alb.name, alb.artist, cur);
          if (best && best !== cur) {
            upgradedAny = true;
            return { ...alb, artwork: best };
          }
          return alb;
        });
      }
      if (Array.isArray(state.libraryRecent.songs)) {
        state.libraryRecent.songs = state.libraryRecent.songs.map(s => {
          const cur = String(s.artwork_url || s.artwork || '').trim();
          const best = resolveBestLibraryAlbumArtwork(s.album || s.collectionName, s.artist || s.artistName, cur);
          if (best && best !== cur) {
            upgradedAny = true;
            return { ...s, artwork_url: best, artwork: best };
          }
          return s;
        });
      }
      if (upgradedAny && state.libraryTab === 'recent') {
        renderLibraryRecent();
      }
    }
    if (typeof renderStandbyQuickTiles === 'function') {
      renderStandbyQuickTiles();
    }
    if (
      state.currentPlaylistDetail &&
      state.currentPlaylistDetail.isAlbum &&
      state.currentAlbumDetail &&
      state.currentAlbumDetail.is_complete_in_library === true &&
      dom.btnAddPlaylistLibrary &&
      (!dom.playlistDetailPane || !dom.playlistDetailPane.classList.contains('hidden')) &&
      findMatchingLibraryAlbum(state.currentPlaylistDetail)
    ) {
      state.isAddingDetailToLibrary = false;
      dom.btnAddPlaylistLibrary.disabled = true;
      dom.btnAddPlaylistLibrary.classList.add('added');
      dom.btnAddPlaylistLibrary.classList.add('hidden');
      if (dom.btnRemoveDetailLibrary) {
        dom.btnRemoveDetailLibrary.classList.remove('hidden');
      }
    }
  }

  // Subtab 4: Треки
  function getFilteredLibrarySongs() {
    const allSongs = Array.isArray(state.librarySongs) ? state.librarySongs : [];
    const rawFilter = String(state.librarySongsFilter || '').trim();
    const q = normalizeTrackMatchText(rawFilter);
    if (!q) return allSongs;
    return allSongs.filter(s => {
      const hay = `${normalizeTrackMatchText(s.name || s.trackName)} ${normalizeTrackMatchText(s.artist || s.artistName)} ${normalizeTrackMatchText(s.album || s.collectionName)}`;
      return hay.includes(q);
    });
  }

  function renderLibrarySongs() {
    if (!dom.librarySongsList) return;
    syncLibrarySubtitle();
    if (!state.librarySongsLoaded) return;

    const allSongs = Array.isArray(state.librarySongs) ? state.librarySongs : [];
    const rawFilter = String(state.librarySongsFilter || '').trim();

    if (dom.librarySongsToolbar) {
      dom.librarySongsToolbar.classList.toggle('hidden', allSongs.length === 0 && !rawFilter);
    }
    if (dom.btnClearSongsFilter) {
      dom.btnClearSongsFilter.classList.toggle('hidden', !rawFilter);
    }

    if (allSongs.length === 0) {
      dom.librarySongsList.innerHTML = `<div class="empty-state">${escapeHtml(translateTextToEn('Треки в медиатеке не найдены'))}</div>`;
      return;
    }

    const filtered = getFilteredLibrarySongs();
    if (filtered.length === 0) {
      dom.librarySongsList.innerHTML = `<div class="empty-state">${escapeHtml(translateTextToEn('Ничего не найдено'))}</div>`;
      return;
    }

    dom.librarySongsList.innerHTML = '';
    const limit = state.librarySongsRenderLimit || 250;
    const visible = filtered.slice(0, limit);
    const frag = document.createDocumentFragment();
    visible.forEach((s, idx) => {
      frag.appendChild(createLibrarySongRowElement(s, () => {
        playLibrarySongsWindow(filtered, idx, false, 'Треки медиатеки');
      }));
    });

    if (filtered.length > limit) {
      const moreWrap = document.createElement('div');
      moreWrap.style.cssText = 'display:flex;justify-content:center;padding:14px 0 6px;';
      const moreBtn = document.createElement('button');
      moreBtn.type = 'button';
      moreBtn.className = 'btn-pill-outline';
      moreBtn.textContent = IS_EN
        ? `Show more (${filtered.length - limit} remaining)`
        : `Показать ещё (${filtered.length - limit})`;
      moreBtn.addEventListener('click', () => {
        state.librarySongsRenderLimit = limit + 300;
        renderLibrarySongs();
      });
      moreWrap.appendChild(moreBtn);
      frag.appendChild(moreWrap);
    }

    dom.librarySongsList.appendChild(frag);
  }

  function updateLibrarySongs(data) {
    const list = (data && Array.isArray(data.songs)) ? data.songs : (Array.isArray(data) ? data : []);
    state.librarySongs = list;
    state.librarySongsLoaded = true;
    renderLibrarySongs();
    if (dom.stationPickerModal && !dom.stationPickerModal.classList.contains('hidden')) {
      syncStationPickerModalUI();
    }
  }

  if (dom.librarySongsFilter) {
    dom.librarySongsFilter.addEventListener('input', (e) => {
      state.librarySongsFilter = e.target.value || '';
      state.librarySongsRenderLimit = 250;
      renderLibrarySongs();
    });
  }
  if (dom.btnClearSongsFilter) {
    dom.btnClearSongsFilter.addEventListener('click', () => {
      state.librarySongsFilter = '';
      state.librarySongsRenderLimit = 250;
      if (dom.librarySongsFilter) dom.librarySongsFilter.value = '';
      renderLibrarySongs();
    });
  }
  if (dom.btnPlayLibrarySongs) {
    dom.btnPlayLibrarySongs.addEventListener('click', () => {
      const pool = getFilteredLibrarySongs();
      if (pool.length === 0) return;
      playLibrarySongsWindow(pool, 0, false, 'Треки медиатеки');
    });
  }
  if (dom.btnShuffleLibrarySongs) {
    dom.btnShuffleLibrarySongs.addEventListener('click', () => {
      const pool = getFilteredLibrarySongs();
      if (pool.length === 0) return;
      playLibrarySongsWindow(pool, null, true, 'Треки медиатеки');
    });
  }

  function switchLibrarySubtab(subtab, forceFetch = false) {
    const allowed = ['recent', 'artists', 'albums', 'songs'];
    const nextTab = allowed.includes(subtab) ? subtab : 'recent';
    state.libraryTab = nextTab;

    const segMap = [
      { key: 'recent', btn: dom.librarySegRecent, pane: dom.libraryRecentPane },
      { key: 'artists', btn: dom.librarySegArtists, pane: dom.libraryArtistsPane },
      { key: 'albums', btn: dom.librarySegAlbums, pane: dom.libraryAlbumsGrid },
      { key: 'songs', btn: dom.librarySegSongs, pane: dom.librarySongsPane }
    ];
    segMap.forEach(({ key, btn, pane }) => {
      const isAct = key === nextTab;
      if (btn) {
        btn.classList.toggle('active', isAct);
        btn.setAttribute('aria-selected', isAct ? 'true' : 'false');
      }
      if (pane) {
        pane.classList.toggle('hidden', !isAct);
      }
    });

    syncLibrarySubtitle();

    if (nextTab === 'recent') {
      if (forceFetch || !state.libraryRecent || !state.libraryRecent.loaded) {
        if (dom.libraryRecentPane && (!state.libraryRecent || !state.libraryRecent.loaded)) {
          dom.libraryRecentPane.innerHTML = `<div class="loading-state">${escapeHtml(translateTextToEn('Загрузка недавних...'))}</div>`;
        }
        send({ action: 'get_library_recent', params: forceFetch ? { refresh: true } : {} });
      } else {
        renderLibraryRecent();
      }
    } else if (nextTab === 'artists') {
      if (forceFetch || !state.libraryArtistsLoaded) {
        if (dom.libraryArtistsList && !state.libraryArtistsLoaded) {
          dom.libraryArtistsList.innerHTML = `<div class="loading-state">${escapeHtml(translateTextToEn('Загрузка исполнителей...'))}</div>`;
        }
        send({ action: 'get_library_artists', params: forceFetch ? { refresh: true } : {} });
      } else {
        renderLibraryArtists();
      }
    } else if (nextTab === 'albums') {
      if (forceFetch || !state.libraryAlbums || state.libraryAlbums.length === 0) {
        if (dom.libraryAlbumsGrid && (!state.libraryAlbums || state.libraryAlbums.length === 0)) {
          dom.libraryAlbumsGrid.innerHTML = `<div class="loading-state">${escapeHtml(translateTextToEn('Загрузка альбомов...'))}</div>`;
        }
        send({ action: 'get_library_albums', params: forceFetch ? { refresh: true } : {} });
      } else {
        renderLibraryAlbums();
      }
    } else if (nextTab === 'songs') {
      if (forceFetch || !state.librarySongsLoaded) {
        if (dom.librarySongsList && !state.librarySongsLoaded) {
          dom.librarySongsList.innerHTML = `<div class="loading-state">${escapeHtml(translateTextToEn('Загрузка треков медиатеки...'))}</div>`;
        }
        send({ action: 'get_library_songs', params: forceFetch ? { refresh: true } : {} });
      } else {
        renderLibrarySongs();
      }
    }
  }

  [
    [dom.librarySegRecent, 'recent'],
    [dom.librarySegArtists, 'artists'],
    [dom.librarySegAlbums, 'albums'],
    [dom.librarySegSongs, 'songs']
  ].forEach(([btnEl, tabKey]) => {
    if (!btnEl) return;
    btnEl.addEventListener('click', () => {
      triggerHaptic('light');
      showLibraryBrowsePane();
      switchLibrarySubtab(tabKey, false);
    });
  });

  function refreshActiveLibrarySection() {
    triggerHaptic('light');
    if (dom.libraryArtistDetailPane && !dom.libraryArtistDetailPane.classList.contains('hidden') && state.currentLibraryArtistDetail) {
      if (dom.artistDetailContent) {
        dom.artistDetailContent.innerHTML = `<div class="loading-state">${escapeHtml(translateTextToEn('Загрузка медиатеки артиста...'))}</div>`;
      }
      send({ action: 'get_library_artist_detail', params: { artist: state.currentLibraryArtistDetail.artist } });
      return;
    }
    const activeSub = state.libraryTab || 'recent';
    if (activeSub === 'recent' && dom.libraryRecentPane) {
      dom.libraryRecentPane.innerHTML = `<div class="loading-state">${escapeHtml(translateTextToEn('Загрузка недавних...'))}</div>`;
    } else if (activeSub === 'artists' && dom.libraryArtistsList) {
      dom.libraryArtistsList.innerHTML = `<div class="loading-state">${escapeHtml(translateTextToEn('Загрузка исполнителей...'))}</div>`;
    } else if (activeSub === 'albums' && dom.libraryAlbumsGrid) {
      dom.libraryAlbumsGrid.innerHTML = `<div class="loading-state">${escapeHtml(translateTextToEn('Загрузка альбомов...'))}</div>`;
    } else if (activeSub === 'songs' && dom.librarySongsList) {
      dom.librarySongsList.innerHTML = `<div class="loading-state">${escapeHtml(translateTextToEn('Загрузка треков медиатеки...'))}</div>`;
    }
    switchLibrarySubtab(activeSub, true);
  }

  if (dom.btnRefreshLibrary) {
    dom.btnRefreshLibrary.addEventListener('click', refreshActiveLibrarySection);
  }
  if (dom.btnRefreshLibraryDesktop) {
    dom.btnRefreshLibraryDesktop.addEventListener('click', refreshActiveLibrarySection);
  }

  function syncNavHighlightForDetailOrigin(origin) {
    let deskTarget = 'library';
    let mobTarget = 'view-library';
    if (origin === 'playlists') {
      deskTarget = 'playlists';
      mobTarget = 'view-playlists';
    } else if (origin === 'search') {
      deskTarget = 'search';
      mobTarget = 'view-search';
    } else if (origin === 'home' || origin === 'home-grid') {
      deskTarget = 'home';
      mobTarget = 'view-home';
    } else if (origin === 'player') {
      deskTarget = state.desktopActiveTab || 'library';
      mobTarget = 'view-library';
    }
    dom.desktopNavButtons.forEach(b => {
      b.classList.toggle('active', b.dataset.target === deskTarget);
    });
    dom.tabItems.forEach(item => {
      item.classList.toggle('active', item.dataset.view === mobTarget);
    });
  }

  function syncDetailBackLabel(origin) {
    const backEl = dom.detailBackLabel || (dom.btnBackToPlaylists && dom.btnBackToPlaylists.querySelector('span'));
    if (!backEl) return;
    let label = 'Медиатека';
    if (origin === 'playlists') label = 'Плейлисты';
    else if (origin === 'library-recent') label = 'Недавние';
    else if (origin === 'library-artists') label = 'Артисты';
    else if (origin === 'library-artist-detail') {
      label = (state.currentLibraryArtistDetail && state.currentLibraryArtistDetail.artist) || 'Артисты';
      backEl.textContent = label;
      return;
    } else if (origin === 'library-albums') label = 'Альбомы';
    else if (origin === 'library-songs') label = 'Треки';
    else if (origin === 'library') {
      const subMap = { recent: 'Недавние', artists: 'Артисты', albums: 'Альбомы', songs: 'Треки' };
      label = subMap[state.libraryTab] || 'Медиатека';
    } else if (origin === 'search') label = 'Поиск';
    else if (origin === 'home' || origin === 'home-grid') label = 'Главная';
    else if (origin === 'player') label = 'Плеер';
    backEl.textContent = translateTextToEn(label);
  }

  function isDesktopLayout() {
    return window.innerWidth >= 768 && window.innerHeight >= 541;
  }

  function isMobilePhoneViewport() {
    return !isDesktopLayout();
  }

  function navigateToView(viewId, desktopTab, skipFetch = false) {
    if (!isDesktopLayout()) {
      switchMobileView(viewId, skipFetch);
    } else {
      switchDesktopTab(desktopTab, skipFetch);
    }
  }

  const PERSONAL_MIX_ALIAS_GROUPS = [
    ['get up! mix', 'get up!', 'get up mix', 'на старт!', 'на старт', 'на старт!: микс', 'энергетический микс', 'драйв-микс'],
    ['chill mix', 'чилл-микс', 'чилл микс', 'для отдыха', 'для отдыха: микс'],
    ['new music mix', 'микс новинок', 'новинки для вас', 'новая музыка', 'новая музыка: микс'],
    ['favorites mix', 'favourites mix', 'фавориты', 'фавориты: микс', 'в моём вкусе', 'в моем вкусе', 'в моём вкусе: микс', 'в моем вкусе: микс', 'избранное: микс'],
    ['friends mix', 'микс друзей', 'микс для друзей'],
    ['heavy rotation mix', 'на повторе', 'сейчас на повторе'],
    ['your essentials', 'мои любимые треки']
  ];

  function normalizePlaylistKeyClient(str) {
    return String(str || '')
      .trim()
      .toLowerCase()
      .replace(/[’‘ʼ`]/g, "'")
      .replace(/[“”]/g, '"')
      .replace(/ё/g, 'е')
      .replace(/[–—]/g, '-');
  }

  function playlistsSharePersonalMixAliasClient(a, b) {
    const na = normalizePlaylistKeyClient(a);
    const nb = normalizePlaylistKeyClient(b);
    if (!na || !nb) return false;
    if (na === nb) return true;
    return PERSONAL_MIX_ALIAS_GROUPS.some(grp => grp.includes(na) && grp.includes(nb));
  }

  function collectPlaylistCandidateNamesClient(pl) {
    if (!pl) return [];
    const out = [];
    const push = (v) => {
      const s = String(v || '').trim();
      if (s && !out.includes(s)) out.push(s);
    };
    push(pl.name);
    push(pl.title);
    push(pl.local_name);
    push(pl.localName);
    const alts = pl.alternate_names || pl.alternateNames;
    if (Array.isArray(alts)) alts.forEach(push);
    return out;
  }

  function playlistsMatchCrossLocaleClient(plA, plB) {
    if (!plA || !plB) return false;
    const idsA = [plA.id, plA.library_id, plA.playlist_id, plA.catalog_id, plA.catalogId]
      .map(v => String(v || '').trim().toLowerCase())
      .filter(Boolean);
    const idsB = [plB.id, plB.library_id, plB.playlist_id, plB.catalog_id, plB.catalogId]
      .map(v => String(v || '').trim().toLowerCase())
      .filter(Boolean);
    if (idsA.length > 0 && idsB.length > 0 && idsA.some(id => idsB.includes(id))) {
      return true;
    }
    const namesA = collectPlaylistCandidateNamesClient(plA);
    const namesB = collectPlaylistCandidateNamesClient(plB);
    return namesA.some(na => namesB.some(nb => playlistsSharePersonalMixAliasClient(na, nb)));
  }

  function findMatchingLocalPlaylist(plName, plId = '', expectedTrackCount = 0, catalogId = '') {
    if (!plName && !plId && !catalogId) return null;
    const probe = {
      id: plId,
      catalog_id: catalogId || (String(plId || '').trim().toLowerCase().startsWith('pl.') ? plId : ''),
      name: plName
    };
    return (state.playlists || []).find(p => playlistsMatchCrossLocaleClient(p, probe)) || null;
  }

  function resolveDetailOrigin(originParam, defaultOrigin = 'library') {
    if (typeof originParam === 'string' && originParam) return originParam;
    if (originParam === true) {
      if (dom.sectionGridView && dom.sectionGridView.classList.contains('active')) {
        return 'home-grid';
      }
      return 'home';
    }
    return defaultOrigin;
  }

  function openPlaylistDetail(pl, fromOrigin = 'playlists') {
    const origin = resolveDetailOrigin(fromOrigin, 'playlists');
    state.detailReturnOrigin = origin;
    state.albumOpenedFromHome = (origin === 'home' || origin === 'home-grid');
    state.detailOpenedFromHome = (origin === 'home' || origin === 'home-grid');
    state.currentPlaylistDetail = pl;
    state.currentAlbumDetail = null;
    const plName = pl.name || pl.title || '';
    const nextPlId = String(pl.id || '').trim().toLowerCase();
    const nextPlName = String(plName).trim().toLowerCase();
    if (
      state.isAddingDetailToLibrary &&
      (
        (state.lastDetailLibraryAddId && nextPlId && state.lastDetailLibraryAddId !== nextPlId) ||
        (!state.lastDetailLibraryAddId && state.lastDetailLibraryAddName && nextPlName && state.lastDetailLibraryAddName !== nextPlName)
      )
    ) {
      state.isAddingDetailToLibrary = false;
    }
    state.currentDetailPlaylistId = String(pl.id || '');
    state.currentDetailAlbumId = '';
    state.currentDetailTitle = String(plName);
    if (dom.detailBadge) dom.detailBadge.textContent = translateTextToEn('ПЛЕЙЛИСТ');
    dom.detailTitle.textContent = plName;
    const count = pl.track_count || pl.trackCount || 0;
    const matchedLocal = findMatchingLocalPlaylist(plName, pl.id, count, pl.catalog_id || pl.catalogId || '');
    const resolvedCount = count > 0 ? count : Number((matchedLocal && (matchedLocal.track_count || matchedLocal.trackCount)) || 0);
    dom.detailMeta.textContent = resolvedCount > 0 ? formatTracksCount(resolvedCount) : (pl.curator_name || pl.curatorName || 'Apple Music');
    delete dom.detailArtwork.dataset.fallbackApplied;
    dom.detailArtwork.src = appendDeviceIdToUrl(pl.artwork_url || pl.artworkUrl || pl.artwork || 'apple-touch-icon.svg');
    dom.playlistTracksList.innerHTML = `<div class="loading-state">${escapeHtml(translateTextToEn('Загрузка треков...'))}</div>`;
    if (dom.albumCompletenessBannerSlot) dom.albumCompletenessBannerSlot.innerHTML = '';
    const isAlreadyInLib = Boolean(matchedLocal) || Boolean(pl.is_local || pl.in_library);
    const canModifyLib = state.allowLibraryModification !== false;
    const canDeletePlaylist = canModifyLib && isAlreadyInLib && !isProtectedSystemPlaylistClient(plName);

    if (dom.btnRemoveDetailLibrary) {
      if (dom.btnRemoveDetailLibraryText) {
        dom.btnRemoveDetailLibraryText.textContent = translateTextToEn('Удалить плейлист');
      }
      dom.btnRemoveDetailLibrary.classList.toggle('hidden', !canDeletePlaylist);
    }

    if (dom.btnAddPlaylistLibrary) {
      dom.btnAddPlaylistLibrary.style.display = '';
      dom.btnAddPlaylistLibrary.title = translateTextToEn('Добавить в плейлисты Apple Music');
      if (isAlreadyInLib || !canModifyLib) {
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
    const btnDetailBookletPl = document.getElementById('btn-detail-booklet');
    if (btnDetailBookletPl) btnDetailBookletPl.classList.add('hidden');

    navigateToView('view-library', 'library', true);
    syncDetailBackLabel(origin);
    syncNavHighlightForDetailOrigin(origin);
    if (dom.playlistsBrowsePane) dom.playlistsBrowsePane.classList.add('hidden');
    if (dom.libraryArtistDetailPane) dom.libraryArtistDetailPane.classList.add('hidden');
    if (dom.playlistDetailPane) dom.playlistDetailPane.classList.remove('hidden');

    send({
      action: 'get_playlist_tracks',
      params: {
        name: plName,
        id: pl.id || '',
        url: pl.url || ''
      }
    });
  }
