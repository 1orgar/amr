  // --- Section Tiles Grid Drill-down (Recent, Mixes, Albums, Stations) ---
  if (dom.homeRecentLink) {
    dom.homeRecentLink.addEventListener('click', () => {
      openSectionTilesGrid('recent', 'Недавно прослушано');
    });
  }

  if (dom.homeMixesLink) {
    dom.homeMixesLink.addEventListener('click', () => {
      openSectionTilesGrid('mixes', 'Еженедельные миксы');
    });
  }

  if (dom.homeAlbumsLink) {
    dom.homeAlbumsLink.addEventListener('click', () => {
      openSectionTilesGrid('albums', 'Новинки и альбомы');
    });
  }

  if (dom.homeStationsLink) {
    dom.homeStationsLink.addEventListener('click', () => {
      openSectionTilesGrid('stations', 'Станции для вас');
    });
  }

  if (dom.btnBackFromGrid) {
    dom.btnBackFromGrid.addEventListener('click', () => {
      closeSectionTilesGrid();
    });
  }

  function openSectionTilesGrid(sectionKey, title) {
    if (dom.viewHome) dom.viewHome.classList.remove('active');
    if (dom.recentDetailPane) {
      dom.recentDetailPane.classList.remove('active');
      dom.recentDetailPane.classList.add('hidden');
    }
    if (dom.sectionGridView) {
      dom.sectionGridView.classList.remove('hidden');
      dom.sectionGridView.classList.add('active');
    }
    if (dom.gridViewTitle) {
      dom.gridViewTitle.textContent = title;
    }
    renderSectionTiles(sectionKey);
  }

  function closeSectionTilesGrid() {
    if (dom.sectionGridView) {
      dom.sectionGridView.classList.remove('active');
      dom.sectionGridView.classList.add('hidden');
    }
    if (dom.viewHome) {
      dom.viewHome.classList.add('active');
    }
  }

  function renderSectionTiles(key) {
    if (!dom.sectionTilesGrid) return;
    dom.sectionTilesGrid.innerHTML = '';

    let items = [];
    if (key === 'recent') {
      items = state.recentlyPlayed || [];
    } else if (key === 'mixes') {
      items = (state.trends?.personal_mixes && state.trends.personal_mixes.length > 0)
        ? state.trends.personal_mixes
        : [];
    } else if (key === 'albums') {
      const nr = (state.trends?.new_releases && state.trends.new_releases.length > 0) ? state.trends.new_releases : [];
      const ta = (state.trends?.top_albums && state.trends.top_albums.length > 0) ? state.trends.top_albums : (state.trends?.topAlbums || []);
      items = nr.length > 0 ? [...nr, ...ta.filter(a => !nr.some(x => `${x.id}` === `${a.id}`))] : ta;
    } else if (key === 'stations') {
      items = (state.trends?.stations && state.trends.stations.length > 0)
        ? state.trends.stations
        : DEFAULT_STATIONS;
    }

    if (!items || items.length === 0) {
      dom.sectionTilesGrid.innerHTML = '<div class="empty-state">Нет элементов для отображения</div>';
      return;
    }

    items.forEach(item => {
      const tile = document.createElement('div');
      tile.className = 'collection-tile' + (key === 'stations' ? ' is-station' : '');

      const isLive = Boolean(item.isLive || item.is_live);
      const rawGradient = item.color || 'linear-gradient(135deg, #1c1c1e, #2c2c2e)';
      const gradient = sanitizeCssColorValue(rawGradient);
      const artUrl = appendDeviceIdToUrl(item.artwork || item.artworkUrl || item.artwork_url || '');
      const hasImage = Boolean(artUrl && artUrl.trim().length > 0 && !artUrl.includes('apple-touch-icon'));
      const itemName = item.name || item.title || 'Apple Music';
      const itemSub = item.subtitle || item.sub || item.artist || item.curatorName || (key === 'stations' ? 'Радиостанция' : '');
      const animatedPlaque = getAnimatedPlaqueHtml({ ...item, title: itemName, subtitle: itemSub, type: key === 'stations' ? 'station' : item.type });

      const artHtml = animatedPlaque
        ? animatedPlaque
        : (hasImage
          ? `<img class="collection-tile-art" src="${escapeHtml(artUrl)}" alt="" loading="lazy" data-fallback-mode="next-flex">
             <div class="collection-tile-fallback station-animated-bg" style="display:none; background: ${gradient};">
               <svg viewBox="0 0 24 24" width="36" height="36" fill="currentColor"><circle cx="12" cy="12" r="3.2"/><path d="M12 6c-2.76 0-5 2.24-5 5 0 1.63.79 3.08 2 3.99V22l3-2 3 2v-7.01c1.21-.91 2-2.36 2-3.99 0-2.76-2.24-5-5-5z"/></svg>
               <span class="collection-tile-fallback-title">${escapeHtml(itemName)}</span>
             </div>`
          : `<div class="collection-tile-fallback station-animated-bg" style="background: ${gradient};">
               <svg viewBox="0 0 24 24" width="36" height="36" fill="currentColor"><circle cx="12" cy="12" r="3.2"/><path d="M12 6c-2.76 0-5 2.24-5 5 0 1.63.79 3.08 2 3.99V22l3-2 3 2v-7.01c1.21-.91 2-2.36 2-3.99 0-2.76-2.24-5-5-5z"/></svg>
               <span class="collection-tile-fallback-title">${escapeHtml(itemName)}</span>
             </div>`);

      // music Emblem
      const appleMusicBadge = `
        <div class="apple-music-badge">
          <svg viewBox="0 0 170 170"><path d="M150.37 130.25c-2.45 5.66-5.35 10.87-8.71 15.66-4.58 6.53-8.33 11.05-11.22 13.56-4.48 4.12-9.28 6.23-14.42 6.35-3.69 0-8.14-1.05-13.32-3.18-5.19-2.12-9.97-3.17-14.34-3.17-4.58 0-9.49 1.05-14.75 3.17-5.26 2.13-9.5 3.24-12.74 3.35-4.35.13-9.16-1.9-14.42-6.08-3.7-3.04-7.58-7.7-11.63-13.98-5.77-8.91-10.28-18.77-13.55-29.58-3.27-10.81-4.9-21.2-4.9-31.17 0-14.7 3.52-26.69 10.57-35.98 7.05-9.29 16.03-14.07 26.94-14.34 5.33 0 11.22 1.5 17.67 4.5 6.45 3.01 10.57 4.59 12.37 4.74 2.18-.32 6.64-1.99 13.39-5.01 6.75-3.02 12.63-4.33 17.65-3.94 13.17 1.07 23.36 6.09 30.56 15.07-11.75 7.12-17.51 16.97-17.29 29.54.21 9.99 4.14 18.3 11.78 24.93 7.64 6.63 16.59 10.45 26.85 11.46-2.07 6.1-4.47 12.06-7.21 17.89zM119.22 31.85c0-7.39 2.68-14.53 8.04-21.43 5.36-6.9 12.04-10.42 20.03-10.42.22 1.1.33 2.11.33 3.04 0 7.4-2.73 14.44-8.2 21.11-5.46 6.68-12.23 10.29-20.2 10.84v-3.14z"/></svg>
          <span>music</span>
        </div>
      `;

      tile.innerHTML = `
        <div class="collection-tile-art-wrap">
          ${artHtml}
          ${appleMusicBadge}
          <div class="media-play-overlay">
            <div class="media-play-pill">
              <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
                <polygon points="7 4 19 12 7 20 7 4"/>
              </svg>
            </div>
          </div>
        </div>
        <div class="collection-tile-info">
          <span class="collection-tile-title">${escapeHtml(itemName)}</span>
          <span class="collection-tile-sub">${escapeHtml(itemSub)}</span>
        </div>
      `;

      tile.addEventListener('click', () => {
        if (key === 'mixes') {
          openPlaylistDetail({
            id: item.id || '',
            name: itemName,
            url: item.url || '',
            artwork_url: artUrl,
            track_count: Number(item.track_count || item.trackCount || 0),
            curator_name: itemSub
          }, 'home-grid');
          return;
        }
        if (key === 'albums') {
          openAlbumDetail({
            id: `${item.id || ''}`,
            name: itemName,
            artist: itemSub,
            artwork: artUrl,
            url: item.url || ''
          }, 'home-grid');
          return;
        }

        state.pendingPlayUntil = Date.now() + 3000;
        state.playerState = 'playing';
        state.playbackState = 'playing';
        renderNowPlaying();

        if (key === 'stations') {
          markWaitingForPlayback({ isStation: true, targetName: item.name });
          setUIBusy(true, 'Подключение к станции...');
          send({
            action: 'play_station',
            params: {
              url: item.url || '',
              name: item.name || 'Apple Music Radio'
            }
          });
        } else if (key === 'recent') {
          markWaitingForPlayback({ targetName: item.name });
          setUIBusy(true, 'Запуск трека...');
          send({
            action: 'play_cloud',
            params: {
              id: `${item.id || ''}`,
              numeric_id: parseInt(item.id, 10) || 0,
              name: item.name || '',
              artist: item.artist || '',
              url: item.url || '',
              artwork: artUrl
            }
          });
        }
      });

      dom.sectionTilesGrid.appendChild(tile);
    });
  }

  // Fallback detail handlers for Recently Played list view
  if (dom.btnBackFromRecent) {
    dom.btnBackFromRecent.addEventListener('click', () => {
      closeRecentDetail();
    });
  }

  if (dom.btnPlayRecentAll) {
    dom.btnPlayRecentAll.addEventListener('click', () => {
      setUIBusy(true, 'Воспроизведение...', dom.btnPlayRecentAll);
      send({ action: 'play_recent', params: { shuffle: false } });
    });
  }

  if (dom.btnShuffleRecentAll) {
    dom.btnShuffleRecentAll.addEventListener('click', () => {
      setUIBusy(true, 'Перемешивание...', dom.btnShuffleRecentAll);
      send({ action: 'play_recent', params: { shuffle: true } });
    });
  }

  function openRecentDetail() {
    if (dom.viewHome) dom.viewHome.classList.remove('active');
    if (dom.recentDetailPane) {
      dom.recentDetailPane.classList.remove('hidden');
      dom.recentDetailPane.classList.add('active');
    }
    renderRecentFullList();
  }

  function closeRecentDetail() {
    if (dom.recentDetailPane) {
      dom.recentDetailPane.classList.remove('active');
      dom.recentDetailPane.classList.add('hidden');
    }
    if (dom.viewHome) {
      dom.viewHome.classList.add('active');
    }
  }

  function renderRecentFullList() {
    if (!dom.recentTracksFullList) return;
    const list = state.recentlyPlayed && state.recentlyPlayed.length > 0 ? state.recentlyPlayed : [];
    if (dom.recentTotalCount) {
      dom.recentTotalCount.textContent = `${list.length} треков`;
    }
    if (list.length === 0) {
      dom.recentTracksFullList.innerHTML = '<div class="empty-state">Нет недавних треков</div>';
      return;
    }

    dom.recentTracksFullList.innerHTML = '';
    list.forEach((t, idx) => {
      const row = document.createElement('div');
      row.className = 'track-row';
      const art = getArtworkSrc(t);
      const dur = t.duration ? formatTime(t.duration) : '';

      row.innerHTML = `
        <span class="track-index-num">${idx + 1}</span>
        <img class="track-thumb" src="${escapeHtml(art)}" alt="" loading="lazy" data-fallback-icon="apple-touch-icon.svg">
        <div class="track-details">
          <span class="track-row-title">${escapeHtml(t.name || 'Без названия')}</span>
          <span class="track-row-artist">${escapeHtml(t.artist || '')}${t.album ? ' &bull; ' + escapeHtml(t.album) : ''}</span>
        </div>
        ${dur ? `<span class="track-row-dur">${dur}</span>` : ''}
        <button class="btn-chart-play" type="button" aria-label="Слушать">
          <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor">
            <polygon points="6 3 20 12 6 21 6 3"/>
          </svg>
        </button>
      `;

      row.addEventListener('click', () => {
        setUIBusy(true, 'Запуск трека...');
        send({
          action: 'play_cloud',
          params: {
            id: `${t.id || ''}`,
            numeric_id: parseInt(t.id, 10) || 0,
            name: t.name || '',
            artist: t.artist || '',
            url: t.url || '',
            artwork: art
          }
        });
      });

      dom.recentTracksFullList.appendChild(row);
    });
  }

  // Render Popular Albums (Популярные альбомы ›)
  function renderHomeAlbums(albums) {
    const container = dom.homeAlbumsCarousel || dom.trendsAlbumsGrid;
    if (!container) return;
    if (!albums || albums.length === 0) {
      container.innerHTML = '<div class="empty-state">Нет данных по альбомам</div>';
      return;
    }

    container.innerHTML = '';
    albums.forEach(alb => {
      const card = document.createElement('div');
      card.className = 'media-card album-card';
      const art = alb.artwork_url || alb.artwork || 'apple-touch-icon.svg';

      card.innerHTML = `
        <div class="media-card-art-wrap">
          <img class="media-card-art" src="${escapeHtml(art)}" alt="" loading="lazy">
          <div class="media-play-overlay">
            <div class="media-play-pill">
              <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
                <polygon points="7 4 19 12 7 20 7 4"/>
              </svg>
            </div>
          </div>
        </div>
        <span class="media-card-title">${escapeHtml(alb.name || '')}</span>
        <span class="media-card-sub">${escapeHtml(alb.artist || '')}</span>
      `;

      card.addEventListener('click', () => {
        openAlbumDetail({
          id: `${alb.id || ''}`,
          name: alb.name || '',
          artist: alb.artist || '',
          artwork: art,
          url: alb.url || ''
        }, 'home');
      });

      container.appendChild(card);
    });
  }

  // Render Genres (Жанры и категории ›)
  function renderHomeGenres(genres) {
    const container = dom.homeGenresGrid || dom.trendsGenresGrid;
    if (!container) return;
    const list = genres && genres.length > 0 ? genres : DEFAULT_GENRES;

    container.innerHTML = '';
    list.forEach(g => {
      const chip = document.createElement('button');
      chip.type = 'button';
      chip.className = 'genre-card';
      chip.innerHTML = `
        <span class="genre-title">${escapeHtml(g.name || '')}</span>
        <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">
          <polyline points="9 18 15 12 9 6"/>
        </svg>
      `;

      chip.addEventListener('click', () => {
        selectGenre(g.query || g.name || '');
      });

      container.appendChild(chip);
    });
  }

  // Aliases for compatibility
  const renderTrendsStations = renderHomeStations;
  const renderTrendsTopSongs = () => {};
  const renderTrendsAlbums = renderHomeAlbums;
  const renderTrendsGenres = renderHomeGenres;

  function selectGenre(genreQuery) {
    const cleanQ = genreQuery.replace(/^[^\w\sа-яА-ЯёЁ]+/, '').trim();
    dom.searchInput.value = cleanQ;
    state.searchQuery = cleanQ;
    state.searchScope = 'all';
    if (dom.filterChips) {
      dom.filterChips.forEach(c => c.classList.toggle('active', c.dataset.scope === 'all'));
    }
    dom.btnClearSearch.classList.remove('hidden');

    if (isDesktopLayout()) {
      switchDesktopTab('search');
    } else {
      switchMobileView('view-search');
    }

    executeSearch(cleanQ, 'all');
  }

  // --- Navigation & View Switching ---

  // Mobile Bottom Tab Bar
  dom.tabItems.forEach(tab => {
    tab.addEventListener('click', () => {
      triggerHaptic('light');
      const targetViewId = tab.dataset.view;
      switchMobileView(targetViewId);
    });
  });

  function switchMobileView(viewId, skipFetch = false, preserveHomeDrilldown = false) {
    if (viewId !== 'view-search' && dom.searchInput && document.activeElement === dom.searchInput) {
      dom.searchInput.blur();
    }
    if (viewId !== 'view-now-playing') {
      state.lastNonPlayerView = viewId;
    }
    state.activeView = viewId;

    dom.tabItems.forEach(item => {
      item.classList.toggle('active', item.dataset.view === viewId);
    });

    const keepRecentOpen = Boolean(preserveHomeDrilldown && viewId === 'view-home' && dom.recentDetailPane && !dom.recentDetailPane.classList.contains('hidden'));
    const keepGridOpen = Boolean(preserveHomeDrilldown && viewId === 'view-home' && dom.sectionGridView && !dom.sectionGridView.classList.contains('hidden'));

    // Hide all views first
    dom.viewNowPlaying.classList.remove('active');
    dom.viewQueue.classList.remove('active');
    if (dom.viewPlaylists) dom.viewPlaylists.classList.remove('active');
    dom.viewLibrary.classList.remove('active');
    if (dom.viewHome) dom.viewHome.classList.remove('active');
    if (dom.viewTrends) dom.viewTrends.classList.remove('active');
    if (dom.recentDetailPane && !keepRecentOpen) {
      dom.recentDetailPane.classList.remove('active');
      dom.recentDetailPane.classList.add('hidden');
    }
    if (dom.sectionGridView && !keepGridOpen) {
      dom.sectionGridView.classList.remove('active');
      dom.sectionGridView.classList.add('hidden');
    }
    dom.viewSearch.classList.remove('active');

    if (!skipFetch && viewId !== 'view-library' && viewId !== 'view-now-playing') {
      showLibraryBrowsePane();
    }

    // Activate selected view (or keep Home drilldown sub-view active)
    if (keepRecentOpen && dom.recentDetailPane) {
      dom.recentDetailPane.classList.add('active');
    } else if (keepGridOpen && dom.sectionGridView) {
      dom.sectionGridView.classList.add('active');
    } else {
      const target = document.getElementById(viewId);
      if (target) {
        target.classList.add('active');
      }
    }
    syncKeyboardFocusClass();

    // Manage Mini-Player visibility on mobile
    if (viewId === 'view-now-playing') {
      dom.miniPlayer.classList.add('hidden');
    } else {
      dom.miniPlayer.classList.remove('hidden');
    }

    if (viewId === 'view-playlists') {
      if (!skipFetch) {
        send({ action: 'get_playlists' });
      }
    } else if (viewId === 'view-library') {
      if (!skipFetch) {
        showLibraryBrowsePane();
        switchLibrarySubtab(state.libraryTab || 'recent', false);
        if (!state.libraryAlbums || state.libraryAlbums.length === 0) {
          send({ action: 'get_library_albums' });
        }
      }
    } else if (viewId === 'view-queue') {
      if (!skipFetch) send({ action: 'get_queue' });
    } else if (viewId === 'view-home' || viewId === 'view-trends') {
      if (!skipFetch) loadTrends();
    }
    refreshAllTitleMarquees();
  }

  function minimizeNowPlaying() {
    triggerHaptic('light');
    const targetView = state.lastNonPlayerView || 'view-home';
    const isPlDetailOpen = Boolean(dom.playlistDetailPane && !dom.playlistDetailPane.classList.contains('hidden'));
    const isArtDetailOpen = Boolean(dom.libraryArtistDetailPane && !dom.libraryArtistDetailPane.classList.contains('hidden'));
    const hasOpenDetail = targetView === 'view-library' && (isPlDetailOpen || isArtDetailOpen);
    switchMobileView(targetView, hasOpenDetail);
    if (hasOpenDetail) {
      syncNavHighlightForDetailOrigin(isArtDetailOpen ? 'library-artists' : (state.detailReturnOrigin || 'library'));
    }
  }

  function expandNowPlaying() {
    triggerHaptic('light');
    switchMobileView('view-now-playing');
  }

  // Tapping Mini-Player body expands Now Playing
  dom.miniTrigger.addEventListener('click', (e) => {
    if (e.target.closest('button')) return;
    expandNowPlaying();
  });

  // Synthetic click suppression after touch swipes
  let ignoreSyntheticClickUntil = 0;
  document.addEventListener('click', (e) => {
    if (Date.now() < ignoreSyntheticClickUntil) {
      e.preventDefault();
      e.stopPropagation();
      e.stopImmediatePropagation();
    }
  }, true);

  // --- Artwork & Mini-Player Swipe Gestures ---
  function setupArtworkSwipeGestures() {
    const container = dom.artworkContainer;
    const wrapper = dom.artworkWrapper;
    if (!container || !wrapper) return;

    let startX = 0;
    let startY = 0;
    let deltaX = 0;
    let deltaY = 0;
    let startTime = 0;
    let isSwiping = false;

    container.addEventListener('touchstart', (e) => {
      if (e.touches.length !== 1) return;
      const t = e.touches[0];
      startX = t.clientX;
      startY = t.clientY;
      deltaX = 0;
      deltaY = 0;
      startTime = Date.now();
      isSwiping = true;
      wrapper.style.transition = 'none';
    }, { passive: true });

    container.addEventListener('touchmove', (e) => {
      if (!isSwiping || e.touches.length !== 1) return;
      const t = e.touches[0];
      deltaX = t.clientX - startX;
      deltaY = t.clientY - startY;

      if (Math.abs(deltaX) > Math.abs(deltaY)) {
        // Horizontal swipe preview with resistance
        const dampened = deltaX * 0.42;
        const scale = Math.max(0.92, 1 - Math.abs(deltaX) / 1000);
        wrapper.style.transform = `translateX(${dampened}px) scale(${scale})`;
      } else if (deltaY > 0) {
        // Pull down preview to minimize
        const dampenedY = deltaY * 0.35;
        const scale = Math.max(0.92, 1 - deltaY / 1200);
        wrapper.style.transform = `translateY(${dampenedY}px) scale(${scale})`;
      }
    }, { passive: true });

    const handleTouchEnd = () => {
      if (!isSwiping) return;
      isSwiping = false;
      const elapsed = Date.now() - startTime;
      wrapper.style.transition = 'transform 0.28s cubic-bezier(0.2, 0.9, 0.4, 1)';

      const isFastSwipe = elapsed < 320;
      const horizontalThreshold = isFastSwipe ? 50 : 80;
      const verticalThreshold = isFastSwipe ? 55 : 85;

      if (Math.abs(deltaX) > Math.abs(deltaY) && Math.abs(deltaX) > horizontalThreshold) {
        ignoreSyntheticClickUntil = Date.now() + 450;
        if (deltaX < 0) {
          // Swipe Left -> Next Track
          triggerHaptic('medium');
          wrapper.style.transform = 'translateX(-120%) scale(0.9)';
          setTimeout(() => {
            sendThrottledTransport('next');
            wrapper.style.transition = 'none';
            wrapper.style.transform = 'translateX(60%) scale(0.92)';
            requestAnimationFrame(() => {
              wrapper.style.transition = 'transform 0.28s cubic-bezier(0.2, 0.9, 0.4, 1)';
              wrapper.style.transform = 'none';
            });
          }, 160);
          return;
        } else {
          // Swipe Right -> Previous Track
          triggerHaptic('medium');
          wrapper.style.transform = 'translateX(120%) scale(0.9)';
          setTimeout(() => {
            sendThrottledTransport('previous');
            wrapper.style.transition = 'none';
            wrapper.style.transform = 'translateX(-60%) scale(0.92)';
            requestAnimationFrame(() => {
              wrapper.style.transition = 'transform 0.28s cubic-bezier(0.2, 0.9, 0.4, 1)';
              wrapper.style.transform = 'none';
            });
          }, 160);
          return;
        }
      } else if (deltaY > verticalThreshold && Math.abs(deltaX) < deltaY * 0.8) {
        // Swipe Down -> Minimize Now Playing
        triggerHaptic('light');
        wrapper.style.transform = 'translateY(120px) scale(0.85)';
        setTimeout(() => {
          wrapper.style.transform = 'none';
          minimizeNowPlaying();
        }, 140);
        return;
      }

      // Reset if not meeting threshold
      wrapper.style.transform = 'none';
    };

    container.addEventListener('touchend', handleTouchEnd);
    container.addEventListener('touchcancel', handleTouchEnd);
  }
