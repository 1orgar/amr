  // Render Hero Carousel (Подборка лучших)
  function renderHeroCarousel(data) {
    if (!dom.homeHeroCarousel) return;
    dom.homeHeroCarousel.innerHTML = '';

    const heroCards = [];

    if (data.hero_cards && data.hero_cards.length > 0) {
      data.hero_cards.forEach(c => {
        let art = c.artwork || '';
        const lowerTitle = (c.title || '').toLowerCase();
        if (!art) {
          if (lowerTitle.includes('моя станция') || lowerTitle.includes('my station')) art = 'https://is1-ssl.mzstatic.com/image/thumb/Features/v4/e9/31/64/e93164c8-bff1-a5d9-1ad9-99ff0042a5c1/412b88f3-3259-4c12-8d9c-98b28c6371d4.png/600x600sr.jpg';
          else if (lowerTitle.includes('в моем вкусе') || lowerTitle.includes('открытий') || lowerTitle.includes('discovery')) art = '/assets/stations/CoverDiscovery.png';
          else if (lowerTitle.includes('заряд') || lowerTitle.includes('энерг')) art = '/assets/stations/CoverElectronic.png';
          else if (lowerTitle.includes('one ok rock') || lowerTitle.includes('рок')) art = '/assets/stations/CoverRock.png';
        }

        heroCards.push({
          index: c.index || 0,
          title: c.title || 'Apple Music',
          name: c.name || '',
          sub: c.subtitle || c.sub || '',
          tag: c.tag || 'Специально для вас',
          id: c.id || '',
          type: c.type || 'station',
          url: c.url || '',
          color: c.color || '',
          artwork: art
        });
      });
    } else {
      // Variant 3 Hybrid Hero Cards
      heroCards.push(
        {
          index: 1,
          title: 'Моя станция',
          sub: 'Персональная радиостанция',
          tag: 'Специально для вас',
          id: '',
          type: 'station',
          url: '',
          artwork: '/assets/stations/CoverPersonal.png'
        },
        {
          index: 2,
          title: 'Станция открытий',
          sub: 'Новые треки под ваш вкус',
          tag: 'Радиостанция',
          id: '',
          type: 'station',
          url: '',
          artwork: '/assets/stations/CoverDiscovery.png'
        },
        {
          index: 3,
          title: 'Любимые песни',
          sub: 'Плейлист медиатеки',
          tag: 'Медиатека',
          id: 'Любимые песни',
          type: 'playlist',
          url: '',
          artwork: '/api/artwork/playlist?name=%D0%9B%D1%8E%D0%B1%D0%B8%D0%BC%D1%8B%D0%B5%20%D0%BF%D0%B5%D1%81%D0%BD%D0%B8'
        },
        {
          index: 4,
          title: 'Сейчас на повторе',
          sub: 'Еженедельный микс',
          tag: 'Для вас',
          id: 'Сейчас на повторе',
          type: 'playlist',
          url: '',
          artwork: '/assets/stations/CoverHeavyRotation.svg'
        },
        {
          index: 5,
          title: 'Легенда',
          sub: 'Кино',
          tag: 'Топ-альбом',
          id: '1375628135',
          type: 'album',
          url: 'https://music.apple.com/album/1375628135',
          artwork: 'https://is1-ssl.mzstatic.com/image/thumb/Music118/v4/c7/99/1e/c7991ed1-bee2-8c46-2e66-81d0b8e7eeb2/cover.jpg/600x600bb.jpg'
        },
        {
          index: 6,
          title: 'Mutter',
          sub: 'Rammstein',
          tag: 'Топ-альбом',
          id: '1440770702',
          type: 'album',
          url: 'https://music.apple.com/album/1440770702',
          artwork: 'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/b8/91/bf/b891bf2e-0658-690a-115f-c2ee53f3192e/00602527296685.rgb.jpg/600x600bb.jpg'
        },
        {
          index: 7,
          title: 'Акустический альбом',
          sub: 'Король и Шут',
          tag: 'Топ-альбом',
          id: '1440751918',
          type: 'album',
          url: 'https://music.apple.com/album/1440751918',
          artwork: 'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/44/9a/c0/449ac06f-40e1-7c59-bf7b-6ae9be2d7b14/4607062440191.jpg/600x600bb.jpg'
        }
      );
    }

    heroCards.forEach(c => {
      const el = document.createElement('div');
      el.className = 'hero-card';
      el.setAttribute('data-index', c.index);

      const rawCardColor = c.color || 'linear-gradient(135deg, #1c1c1e, #2c2c2e)';
      const cardColor = sanitizeCssColorValue(rawCardColor);
      const animatedPlaque = getAnimatedPlaqueHtml(c);
      const heroArtSrc = c.artwork ? appendDeviceIdToUrl(c.artwork) : '';
      const hasArt = heroArtSrc && heroArtSrc.trim().length > 0;
      const mediaHtml = animatedPlaque ? animatedPlaque : (hasArt ? `
        <img class="hero-art-img" src="${escapeHtml(heroArtSrc)}" alt="${escapeHtml(c.title)}" loading="eager" data-fallback-mode="next-flex">
        <div class="hero-art-fallback" style="display:none; background: ${cardColor};">
          <svg viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="currentColor" stroke-width="1.8">
            <path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>
          </svg>
        </div>
      ` : `
        <div class="hero-art-gradient" style="background: ${cardColor}">
          <svg viewBox="0 0 24 24" width="56" height="56" fill="none" stroke="#ffffff" stroke-width="1.8">
            <path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>
          </svg>
        </div>
      `);

      el.innerHTML = `
        <div class="hero-card-header">
          <span class="hero-tag">${escapeHtml(c.tag)}</span>
          <span class="hero-title">${escapeHtml(c.title)}</span>
          <span class="hero-sub">${escapeHtml(c.sub)}</span>
        </div>
        <div class="hero-card-media">
          ${mediaHtml}
          <button class="hero-play-btn" type="button" aria-label="Воспроизвести">
            <svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor">
              <polygon points="6 4 20 12 6 20 6 4"/>
            </svg>
          </button>
        </div>
      `;

      el.addEventListener('click', (e) => {
        const isPlayBtn = Boolean(e.target.closest('.hero-play-btn'));
        if (c.type === 'album' && !isPlayBtn) {
          openAlbumDetail(c, true);
          return;
        }
        if (c.type === 'playlist' && !isPlayBtn) {
          openPlaylistDetail({
            id: c.id,
            name: c.name || c.title,
            url: c.url,
            artwork_url: c.artwork,
            track_count: Number(c.track_count || c.trackCount || 0)
          }, true);
          return;
        }

        optimisticPlay();
        markWaitingForPlayback({
          isStation: (c.type === 'station'),
          targetName: c.title || c.name || ''
        });
        setUIBusy(true, c.type === 'station' ? 'Запуск станции...' : `Запуск ${c.title || c.name || ''}...`);
        send({
          action: 'play_hero_card',
          params: {
            index: c.index,
            name: c.name || c.title,
            artist: c.name || c.sub || c.subtitle || c.artist || '',
            id: c.id,
            url: c.url,
            type: c.type
          }
        });
        if (dom.btnPlayPause) {
          dom.btnPlayPause.classList.add('loading-pulse');
          setTimeout(() => dom.btnPlayPause.classList.remove('loading-pulse'), 1200);
        }
      });

      dom.homeHeroCarousel.appendChild(el);
    });
  }

  // Render Heavy Rotation
  function renderHeavyRotation(heavyRotation) {
    if (!dom.homeHeavyCarousel) return;
    const list = heavyRotation || [];
    if (list.length === 0) {
      if (dom.homeHeavySection) dom.homeHeavySection.classList.add('hidden');
      return;
    }
    if (dom.homeHeavySection) dom.homeHeavySection.classList.remove('hidden');
    dom.homeHeavyCarousel.innerHTML = '';
    list.forEach(t => {
      const card = document.createElement('div');
      card.className = 'media-card';
      const art = t.artwork || 'apple-touch-icon.svg';
      card.innerHTML = `
          <div class="media-card-art-wrap">
            <img class="media-card-art" src="${escapeHtml(art)}" loading="lazy" alt="Cover">
            <div class="media-play-overlay">
              <div class="media-play-pill">
                <svg viewBox="0 0 24 24" width="16" height="16" fill="#000000"><polygon points="8 5 19 12 8 19 8 5"/></svg>
              </div>
            </div>
          </div>
          <div class="media-card-title">${escapeHtml(t.name || t.album || 'Unknown')}</div>
          <div class="media-card-sub">${escapeHtml(t.artist || '')}</div>
        `;
      card.addEventListener('click', () => {
        openAlbumDetail({
          id: `${t.id || ''}`,
          name: t.name || t.album || '',
          artist: t.artist || '',
          artwork: art,
          url: t.url || ''
        }, 'home');
      });
      dom.homeHeavyCarousel.appendChild(card);
    });
  }

  // Render Personal Weekly Mixes (New Music, Chill, Favorites, Get Up!)
  function renderPersonalMixes(mixes) {
    const list = mixes || [];
    state.personalMixes = list;
    if (typeof renderStandbyQuickTiles === 'function') {
      renderStandbyQuickTiles();
    }
    if (!dom.homeMixesCarousel) return;
    if (list.length === 0) {
      if (dom.homeMixesSection) dom.homeMixesSection.classList.add('hidden');
      return;
    }
    if (dom.homeMixesSection) dom.homeMixesSection.classList.remove('hidden');
    dom.homeMixesCarousel.innerHTML = '';

    list.forEach(mix => {
      const card = document.createElement('div');
      card.className = 'media-card';
      const mName = mix.name || 'Микс';
      const art = appendDeviceIdToUrl(mix.artwork || mix.artwork_url || 'apple-touch-icon.svg');
      const curator = mix.curator_name || 'Apple Music';
      const animatedPlaque = getAnimatedPlaqueHtml({ ...mix, title: mName, subtitle: curator });
      const artContent = animatedPlaque
        ? animatedPlaque
        : `<img class="media-card-art" src="${escapeHtml(art)}" loading="lazy" alt="Cover" data-fallback-icon="apple-touch-icon.svg">`;
      card.innerHTML = `
        <div class="media-card-art-wrap">
          ${artContent}
          <div class="media-play-overlay">
            <div class="media-play-pill">
              <svg viewBox="0 0 24 24" width="16" height="16" fill="#000000"><polygon points="8 5 19 12 8 19 8 5"/></svg>
            </div>
          </div>
        </div>
        <div class="media-card-title">${escapeHtml(mName)}</div>
        <div class="media-card-sub">${escapeHtml(curator)}</div>
      `;
      card.addEventListener('click', () => {
        openPlaylistDetail({
          id: mix.id || '',
          name: mName,
          url: mix.url || '',
          artwork_url: art,
          track_count: Number(mix.track_count || mix.trackCount || 0),
          curator_name: curator
        }, 'home');
      });
      dom.homeMixesCarousel.appendChild(card);
    });
  }

  // Render Personal Recommendations (from Apple Music /v1/me/recommendations)
  function renderPersonalRecommendations(groups) {
    if (!dom.homeRecContainer) return;
    const list = groups || [];
    if (list.length === 0) {
      return;
    }

    list.forEach(grp => {
      const contents = grp.contents || [];
      if (contents.length === 0) return;

      const sec = document.createElement('div');
      sec.className = 'home-section';
      sec.innerHTML = `
        <div class="home-section-header-link">
          <h2 class="home-section-title">${escapeHtml(grp.title || 'Для вас')}</h2>
        </div>
        <div class="home-carousel-row"></div>
      `;
      const carousel = sec.querySelector('.home-carousel-row');

      contents.forEach(item => {
        const card = document.createElement('div');
        card.className = 'media-card';
        const iName = item.name || '';
        const iSub = item.subtitle || '';
        const art = appendDeviceIdToUrl(item.artwork || item.artwork_url || 'apple-touch-icon.svg');
        const animatedPlaque = getAnimatedPlaqueHtml({ ...item, title: iName, subtitle: iSub });
        const artContent = animatedPlaque
          ? animatedPlaque
          : `<img class="media-card-art" src="${escapeHtml(art)}" loading="lazy" alt="Cover" data-fallback-icon="apple-touch-icon.svg">`;

        card.innerHTML = `
          <div class="media-card-art-wrap">
            ${artContent}
            <div class="media-play-overlay">
              <div class="media-play-pill">
                <svg viewBox="0 0 24 24" width="16" height="16" fill="#000000"><polygon points="8 5 19 12 8 19 8 5"/></svg>
              </div>
            </div>
          </div>
          <div class="media-card-title">${escapeHtml(iName)}</div>
          <div class="media-card-sub">${escapeHtml(iSub)}</div>
        `;

        card.addEventListener('click', () => {
          const itemType = (item.type || '').toLowerCase();
          if (itemType === 'album' || itemType === 'albums') {
            openAlbumDetail({
              id: `${item.id || ''}`,
              name: iName,
              artist: iSub,
              artwork: art,
              url: item.url || ''
            }, 'home');
          } else if (itemType === 'playlist' || itemType === 'playlists') {
            openPlaylistDetail({
              id: item.id || '',
              name: iName,
              url: item.url || '',
              artwork_url: art,
              track_count: Number(item.track_count || item.trackCount || 0),
              curator_name: iSub
            }, 'home');
          } else {
            optimisticPlay();
            markWaitingForPlayback({ isStation: true, targetName: iName });
            setUIBusy(true, `Запуск ${iName}...`);
            send({
              action: 'play_hero_card',
              params: {
                index: 0,
                name: iName,
                id: item.id || '',
                url: item.url || '',
                type: 'station'
              }
            });
          }
        });

        carousel.appendChild(card);
      });

      dom.homeRecContainer.appendChild(sec);
    });
  }

  // Render Recommendations
  function renderSimilarRecommendations(recommendedArray) {
    if (!dom.homeRecContainer) return;

    if (!recommendedArray || !Array.isArray(recommendedArray) || recommendedArray.length === 0) {
      return;
    }
    
    recommendedArray.forEach((rec, idx) => {
      const list = rec.items || [];
      if (list.length === 0) return;
      
      const section = document.createElement('div');
      section.className = 'home-section';
      
      const title = document.createElement('h2');
      title.className = 'home-section-title';
      title.textContent = rec.title || 'Рекомендации';
      
      const carousel = document.createElement('div');
      carousel.className = 'home-carousel-row';
      
      list.forEach(a => {
        const card = document.createElement('div');
        card.className = 'media-card';
        const aName = a.name || (a.title ? a.title : '');
        const art = a.artwork || 'apple-touch-icon.svg';
        card.innerHTML = `
          <div class="media-card-art-wrap">
            <img class="media-card-art" src="${escapeHtml(art)}" loading="lazy" alt="Cover">
            <div class="media-play-overlay">
              <div class="media-play-pill">
                <svg viewBox="0 0 24 24" width="16" height="16" fill="#000000"><polygon points="8 5 19 12 8 19 8 5"/></svg>
              </div>
            </div>
          </div>
          <div class="media-card-title">${escapeHtml(aName)}</div>
          <div class="media-card-sub">${escapeHtml(a.artist || '')}</div>
        `;
        card.addEventListener('click', () => {
          openAlbumDetail({
            id: `${a.id || ''}`,
            name: aName,
            artist: a.artist || '',
            artwork: art,
            url: a.url || ''
          }, 'home');
        });
        carousel.appendChild(card);
      });
      
      section.appendChild(title);
      section.appendChild(carousel);
      dom.homeRecContainer.appendChild(section);
    });
  }

  function executeAction(action, params) {
    if (action === 'play_album') {
      setUIBusy(true, 'Запуск альбома...');
      send({
        action: 'play_album',
        params: {
          id: `${params?.id || ''}`,
          name: params?.name || '',
          artist: params?.artist || '',
          url: params?.url || '',
          shuffle: false
        }
      });
    }
  }

  // Render Recently Played (Вы недавно слушали ›)
  function renderRecentlyPlayed(recentTracks) {
    if (!dom.homeRecentCarousel) return;
    const list = recentTracks && recentTracks.length > 0 ? recentTracks : [];
    if (list.length === 0) {
      if (dom.homeRecentSection) dom.homeRecentSection.classList.add('hidden');
      return;
    }
    if (dom.homeRecentSection) dom.homeRecentSection.classList.remove('hidden');
    dom.homeRecentCarousel.innerHTML = '';
    const homeList = list.slice(0, 10);

    homeList.forEach(t => {
      const card = document.createElement('div');
      card.className = 'media-card';
      const art = getArtworkSrc(t);

      card.innerHTML = `
        <div class="media-card-art-wrap">
          <img class="media-card-art" src="${escapeHtml(art)}" alt="" loading="lazy" data-fallback-mode="parent-fallback">
          <div class="media-card-art-fallback" style="background: linear-gradient(135deg, #1c1c1e, #2c2c2e);">
            <svg viewBox="0 0 24 24" width="28" height="28" fill="none" stroke="#6e6e73" stroke-width="1.8">
              <path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>
            </svg>
          </div>
          <div class="media-play-overlay">
            <div class="media-play-pill">
              <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
                <polygon points="7 4 19 12 7 20 7 4"/>
              </svg>
            </div>
          </div>
        </div>
        <span class="media-card-title">${escapeHtml(t.name || 'Без названия')}</span>
        <span class="media-card-sub">${escapeHtml(t.artist || t.album || 'Apple Music')}</span>
      `;

      card.addEventListener('click', () => {
        optimisticPlay();
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

      dom.homeRecentCarousel.appendChild(card);
    });
  }

  // Render Stations (Станции для вас ›)
  function renderHomeStations(stations) {
    const container = dom.homeStationsCarousel || dom.trendsStationsGrid;
    if (!container) return;
    const list = stations && stations.length > 0 ? stations : DEFAULT_STATIONS;
    const homeList = list.slice(0, 10);

    container.innerHTML = '';
    homeList.forEach(st => {
      const card = document.createElement('div');
      card.className = 'media-card station-card';
      const isLive = Boolean(st.isLive || st.is_live);
      const rawGradient = st.color || 'linear-gradient(135deg, #1c1c1e, #2c2c2e)';
      const gradient = sanitizeCssColorValue(rawGradient);
      const defaultIconSvg = '<svg viewBox="0 0 24 24" width="36" height="36" fill="currentColor"><circle cx="12" cy="12" r="3.2"/><path d="M12 6c-2.76 0-5 2.24-5 5 0 1.63.79 3.08 2 3.99V22l3-2 3 2v-7.01c1.21-.91 2-2.36 2-3.99 0-2.76-2.24-5-5-5z"/></svg>';
      const rawIcon = typeof st.icon === 'string' ? st.icon.trim() : '';
      const iconSvg = sanitizeStationSvg(rawIcon, defaultIconSvg);
      const animatedPlaque = getAnimatedPlaqueHtml({ ...st, type: 'station' });
      const hasImage = Boolean(st.artwork && st.artwork.trim().length > 0 && !st.artwork.includes('apple-touch-icon'));

      const artHtml = animatedPlaque
        ? animatedPlaque
        : (hasImage
          ? `<img class="media-card-art" src="${escapeHtml(st.artwork)}" alt="" loading="lazy" data-fallback-mode="next-flex">
             <div class="media-card-art-fallback" style="display:none; background: ${gradient};">
               ${iconSvg}
               <span class="station-art-fallback-title">${escapeHtml(st.name || 'Радио')}</span>
             </div>`
          : `<div class="media-card-art-fallback" style="background: ${gradient};">
               ${iconSvg}
               <span class="station-art-fallback-title">${escapeHtml(st.name || 'Радио')}</span>
             </div>`);

      card.innerHTML = `
        <div class="media-card-art-wrap">
          ${artHtml}
          ${isLive ? '<span class="live-badge">LIVE</span>' : ''}
          <div class="media-play-overlay">
            <div class="media-play-pill">
              <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
                <polygon points="7 4 19 12 7 20 7 4"/>
              </svg>
            </div>
          </div>
        </div>
        <span class="media-card-title">${escapeHtml(st.name || 'Радиостанция')}</span>
        <span class="media-card-sub">${escapeHtml(st.subtitle || (isLive ? 'Прямой эфир Apple Music' : 'Персональная станция'))}</span>
      `;

      card.addEventListener('click', () => {
        optimisticPlay();
        markWaitingForPlayback({ isStation: true, targetName: st.name });
        setUIBusy(true, 'Подключение к станции...');
        send({
          action: 'play_station',
          params: {
            url: st.url || '',
            name: st.name || 'Apple Music Radio'
          }
        });
      });

      container.appendChild(card);
    });
  }
