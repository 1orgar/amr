  // --- Trends & Recommendations Handling ---

  // --- Главная (Home) & Trends Handling ---

  const DEFAULT_STATIONS = [
    {
      id: 'station_personal',
      name: 'Моя станция',
      subtitle: 'Персональная станция',
      color: 'linear-gradient(145deg, #fa233b 0%, #fb5c74 45%, #ff8a65 100%)',
      artwork: '/assets/stations/CoverPersonal.png',
      url: '',
      isLive: false
    },
    {
      id: 'station_discovery',
      name: 'В моем вкусе',
      subtitle: 'Станция открытий',
      color: 'linear-gradient(135deg, #7928ca, #ff0080)',
      artwork: '/assets/stations/CoverDiscovery.png',
      url: '',
      isLive: false
    },
    {
      id: 'station_am1',
      name: 'Apple Music 1',
      subtitle: 'Главные мировые релизы',
      color: 'linear-gradient(135deg, #1c1c1e, #3a3a3c)',
      artwork: '/assets/stations/CoverAppleMusic1.png',
      url: 'https://music.apple.com/us/station/apple-music-1/ra.978194965',
      isLive: true
    },
    {
      id: 'station_hits',
      name: 'Apple Music Hits',
      subtitle: 'Культовые хиты',
      color: 'linear-gradient(135deg, #ff0844, #ffb199)',
      artwork: '/assets/stations/CoverHits.png',
      url: 'https://music.apple.com/us/station/apple-music-hits/ra.1498155548',
      isLive: true
    },
    {
      id: 'station_country',
      name: 'Apple Music Country',
      subtitle: 'Современное кантри',
      color: 'linear-gradient(135deg, #f7971e, #ffd200)',
      artwork: '/assets/stations/CoverCountry.png',
      url: 'https://music.apple.com/us/station/apple-music-country/ra.1498157166',
      isLive: true
    },
    {
      id: 'station_chill',
      name: 'Chill & Lo-Fi',
      subtitle: 'Спокойный ритм и фоновые биты',
      color: 'linear-gradient(135deg, #00b4db, #0083b0)',
      artwork: '/assets/stations/CoverChill.png',
      url: 'https://music.apple.com/us/station/chill-station/ra.985484943',
      isLive: false
    },
    {
      id: 'station_pop',
      name: 'Pop Hits',
      subtitle: 'Популярные поп-треки',
      color: 'linear-gradient(135deg, #fa2d48, #ff6b8b)',
      artwork: '/assets/stations/CoverPop.png',
      url: 'https://music.apple.com/us/station/hits-station/ra.985480047',
      isLive: false
    },
    {
      id: 'station_electronic',
      name: 'Dance & Electronic',
      subtitle: 'Клубный драйв и энергия',
      color: 'linear-gradient(135deg, #ff0844, #ffb199)',
      artwork: '/assets/stations/CoverElectronic.png',
      url: 'https://music.apple.com/us/station/dance-station/ra.985487895',
      isLive: false
    },
    {
      id: 'station_deephouse',
      name: 'Deep House',
      subtitle: 'Глубокий атмосферный грув',
      color: 'linear-gradient(135deg, #1f1c2c, #928dab)',
      artwork: '/assets/stations/CoverDeepHouse.png',
      url: 'https://music.apple.com/us/station/house-station/ra.991194049',
      isLive: false
    },
    {
      id: 'station_rock',
      name: 'Rock Classics',
      subtitle: 'Классика мирового рока',
      color: 'linear-gradient(135deg, #232526, #414345)',
      artwork: '/assets/stations/CoverRock.png',
      url: 'https://music.apple.com/us/station/classic-rock-station/ra.985500514',
      isLive: false
    }
  ];

  const DEFAULT_GENRES = [
    { name: '🔥 Поп-музыка', query: 'Pop Hits' },
    { name: '🎸 Рок & Альтернатива', query: 'Rock Classics' },
    { name: '🎤 Хип-хоп & Рэп', query: 'Hip Hop' },
    { name: '⚡ Электроника & Dance', query: 'Dance Electronic' },
    { name: '☕ Chill & Lo-Fi', query: 'Chill Beats' },
    { name: '🎻 Неоклассика', query: 'Neoclassical' },
    { name: '🎬 Саундтреки', query: 'Soundtrack' }
  ];

  let lastTrendsLoadedTime = 0;
  let lastTrendsCountry = '';
  let trendsInFlightCountry = '';
  let trendsInFlightSince = 0;

  function loadTrends(country, force = false) {
    if (country) {
      state.trends.country = String(country).trim().toLowerCase();
    }
    const c = getActiveStorefront();
    if (c) {
      state.trends.country = c;
    }

    const dedupKey = c || '__account_default__';
    const now = Date.now();
    if (!force && trendsInFlightCountry === dedupKey && now - trendsInFlightSince < 12000) {
      return;
    }
    if (!force && lastTrendsCountry === dedupKey && now - lastTrendsLoadedTime < 30000 && state.trends.stations && state.trends.stations.length > 0) {
      return;
    }
    trendsInFlightCountry = dedupKey;
    trendsInFlightSince = now;
    lastTrendsCountry = dedupKey;

    send({
      action: 'get_explore',
      params: c ? { country: c } : {}
    });
  }

  function updateCatalogCharts(data) {
    // Top charts removed per user request
  }

  function updateExploreFeed(data) {
    trendsInFlightCountry = '';
    trendsInFlightSince = 0;
    lastTrendsLoadedTime = Date.now();
    if (!data) return;

    if (data.stations && data.stations.length > 0) {
      state.trends.stations = data.stations;
    }
    if (data.top_albums && data.top_albums.length > 0) {
      state.trends.topAlbums = data.top_albums;
      state.trends.top_albums = data.top_albums;
    }
    if (data.new_releases && data.new_releases.length > 0) {
      state.trends.new_releases = data.new_releases;
    }
    if (data.personal_mixes && data.personal_mixes.length > 0) {
      state.trends.personal_mixes = data.personal_mixes;
    }
    if (data.genres && data.genres.length > 0) {
      state.trends.genres = data.genres;
    }

    // 1. Section 1: Hero Featured Carousel (Подборка лучших)
    renderHeroCarousel(data);

    // 2. Section 2: Personal Weekly Mixes (Еженедельные миксы)
    renderPersonalMixes(data.personal_mixes);

    // 3. Section 3: New Releases & Popular Albums (Новинки и альбомы)
    const combinedAlbums = (data.new_releases && data.new_releases.length > 0)
      ? [...data.new_releases, ...(state.trends.topAlbums || []).filter(a => !data.new_releases.some(nr => `${nr.id}` === `${a.id}`))]
      : (state.trends.topAlbums || []);
    if (combinedAlbums.length > 0) {
      renderHomeAlbums(combinedAlbums);
    }

    // 4. Dynamic Recommendations & Heavy Rotation
    if (dom.homeRecContainer) {
      dom.homeRecContainer.innerHTML = '';
    }
    renderPersonalRecommendations(data.personal_recommendations);
    renderHeavyRotation(data.heavy_rotation);
    renderSimilarRecommendations(data.recommended_similar);

    // 5. Stations (Станции для вас ›)
    renderHomeStations(state.trends.stations || DEFAULT_STATIONS);

    // 6. Recently Played (Вы недавно слушали ›)
    const recents = (data.recently_played && data.recently_played.length > 0)
      ? data.recently_played
      : (data.top_picks || []);
    state.recentlyPlayed = recents;
    renderRecentlyPlayed(recents);

    // 7. Genres (Жанры и категории ›)
    renderHomeGenres(state.trends.genres || DEFAULT_GENRES);
  }

  const ALLOWED_STATION_SVG_TAGS = new Set([
    'svg', 'g', 'path', 'circle', 'rect', 'ellipse', 'line', 'polyline',
    'polygon', 'defs', 'lineargradient', 'radialgradient', 'stop'
  ]);

  const ALLOWED_STATION_SVG_ATTRS = new Set([
    'viewbox', 'width', 'height', 'fill', 'stroke', 'stroke-width',
    'stroke-linecap', 'stroke-linejoin', 'opacity', 'fill-opacity',
    'stroke-opacity', 'd', 'cx', 'cy', 'r', 'rx', 'ry', 'x', 'y',
    'x1', 'y1', 'x2', 'y2', 'points', 'transform', 'id', 'offset',
    'stop-color', 'stop-opacity', 'gradientunits', 'gradienttransform', 'xmlns'
  ]);

  function sanitizeCssColorValue(rawColor, fallbackColor = 'linear-gradient(135deg, #1c1c1e, #2c2c2e)') {
    const trimmed = String(rawColor || '').trim();
    if (!trimmed || trimmed.length > 240) return fallbackColor;
    if (/url\s*\(|expression\s*\(|@import|[;\\'"<>{}\r\n`]|javascript\s*:|data\s*:/i.test(trimmed)) {
      return fallbackColor;
    }
    if (!/^[#(),.%\-\s0-9a-zA-Z]+$/.test(trimmed)) {
      return fallbackColor;
    }
    return escapeHtml(trimmed);
  }

  function sanitizeStationSvg(rawIcon, fallbackSvg) {
    if (typeof rawIcon !== 'string') return fallbackSvg;
    const trimmed = rawIcon.trim();
    if (!trimmed || !/^<svg[\s>]/i.test(trimmed)) return fallbackSvg;
    try {
      const doc = new DOMParser().parseFromString(trimmed, 'image/svg+xml');
      if (!doc || doc.querySelector('parsererror') || doc.getElementsByTagName('parsererror').length > 0) {
        return fallbackSvg;
      }
      const rootEl = doc.documentElement;
      if (!rootEl || String(rootEl.localName || rootEl.tagName || '').toLowerCase() !== 'svg') {
        return fallbackSvg;
      }
      const allEls = [rootEl, ...Array.from(rootEl.querySelectorAll('*'))];
      for (let i = 0; i < allEls.length; i++) {
        const el = allEls[i];
        const tagLower = String(el.localName || el.tagName || '').toLowerCase();
        if (!ALLOWED_STATION_SVG_TAGS.has(tagLower)) {
          el.remove();
          continue;
        }
        const attrs = Array.from(el.attributes || []);
        for (let j = 0; j < attrs.length; j++) {
          const attr = attrs[j];
          const nameLower = String(attr.localName || attr.name || '').toLowerCase();
          const rawVal = String(attr.value || '');
          const compactLower = rawVal.replace(/[\u0000-\u0020]+/g, '').toLowerCase();
          const hasUnsafeVal = (
            compactLower.includes('javascript:') ||
            compactLower.includes('data:') ||
            compactLower.includes('url(http') ||
            compactLower.includes("url('http") ||
            compactLower.includes('url("http') ||
            compactLower.includes('url(//') ||
            rawVal.includes('<') ||
            /\bon[a-z]+\s*=/i.test(rawVal)
          );
          if (nameLower.startsWith('on') || !ALLOWED_STATION_SVG_ATTRS.has(nameLower) || hasUnsafeVal) {
            el.removeAttribute(attr.name);
          }
        }
        const childNodes = Array.from(el.childNodes || []);
        for (let k = 0; k < childNodes.length; k++) {
          if (childNodes[k].nodeType !== Node.ELEMENT_NODE) {
            el.removeChild(childNodes[k]);
          }
        }
      }
      return new XMLSerializer().serializeToString(rootEl);
    } catch (_) {
      return fallbackSvg;
    }
  }

  // Animated Plaque Generator for Personal Stations, Weekly Mixes & Radio Stations
  let plaqueUidCounter = 0;
  function getAnimatedPlaqueHtml(item) {
    if (!item) return null;
    const rawTitle = String(item.title || item.name || '').trim();
    const rawSub = String(item.subtitle || item.sub || '').trim();
    const lowerTitle = rawTitle.toLowerCase();
    const lowerSub = rawSub.toLowerCase();
    const lowerId = String(item.id || '').toLowerCase();
    const lowerUrl = String(item.url || '').toLowerCase();
    const lowerArt = String(item.artwork || item.artwork_url || item.artworkUrl || '').toLowerCase();
    const lowerType = String(item.type || '').toLowerCase();

    const headerPill = `
      <rect x="184" y="54" width="132" height="26" rx="13" fill="#000000" fill-opacity="0.32" />
      <text x="250" y="71" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="10.5" font-weight="700" letter-spacing="1.6" fill="#ffffff" text-anchor="middle">APPLE MUSIC</text>
    `;

    // 1. Станция открытий (Discovery Station)
    const isDiscovery = lowerTitle.includes('станция открытий') ||
      lowerTitle.includes('discovery station') ||
      (lowerTitle.includes('в моем вкусе') && lowerSub.includes('станция открытий')) ||
      lowerId === 'station_discovery' ||
      lowerId.startsWith('ra.q-') ||
      (lowerArt.includes('coverdiscovery') && !lowerTitle.includes('country') && !lowerTitle.includes('подобные') && !lowerTitle.includes('similar'));

    if (isDiscovery) {
      const dispTitle = IS_EN
        ? 'DISCOVERY STATION'
        : (lowerTitle.includes('в моем вкусе') ? 'СТАНЦИЯ ОТКРЫТИЙ' : (rawTitle.toUpperCase() || 'СТАНЦИЯ ОТКРЫТИЙ'));
      const discGradId = `discStarG-${++plaqueUidCounter}`;
      return `
        <div class="animated-plaque-wrap" style="background: linear-gradient(135deg, #10042c 0%, #3a0ca3 38%, #7209b7 72%, #f72585 100%);">
          <div class="animated-plaque-orb" style="background: radial-gradient(circle, rgba(0,229,255,0.45) 0%, rgba(247,37,133,0) 70%);"></div>
          <svg class="animated-plaque-svg" viewBox="0 0 500 500">
            <defs>
              <linearGradient id="${discGradId}" x1="0%" y1="50%" x2="100%" y2="50%">
                <stop offset="0%" stop-color="#80ffdb" />
                <stop offset="50%" stop-color="#ffffff" />
                <stop offset="100%" stop-color="#ff85a1" />
              </linearGradient>
            </defs>
            ${headerPill}
            <g transform="rotate(-28 250 235)">
              <ellipse class="plaque-dash-flow" cx="250" cy="235" rx="158" ry="86" fill="none" stroke="#48bfe3" stroke-opacity="0.7" stroke-width="2.5" stroke-dasharray="10 12" />
              <circle cx="115" cy="188" r="5" fill="#4cc9f0" class="plaque-breathe" />
              <circle cx="385" cy="282" r="4" fill="#4cc9f0" opacity="0.85" />
            </g>
            <g transform="rotate(24 250 235)">
              <ellipse cx="250" cy="235" rx="152" ry="74" fill="none" stroke="#4cc9f0" stroke-opacity="0.65" stroke-width="2.5" />
              <circle cx="348" cy="176" r="6" fill="#ffffff" class="plaque-breathe" />
              <circle cx="136" cy="285" r="5" fill="#f72585" />
            </g>
            <g class="plaque-spin-slow">
              <polygon points="250,155 264,221 330,235 264,249 250,315 236,249 170,235 236,221" fill="#ffffff" fill-opacity="0.55" transform="rotate(45 250 235)" />
            </g>
            <g class="plaque-breathe">
              <polygon points="250,110 268,217 375,235 268,253 250,360 232,253 125,235 232,217" fill="url(#${discGradId})" />
            </g>
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="27" font-weight="600" fill="#ffffff" text-anchor="middle">${escapeHtml(dispTitle)}</text>
            <text x="250" y="448" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="12" font-weight="600" letter-spacing="2.4" fill="#4cc9f0" text-anchor="middle">DISCOVERY STATION</text>
          </svg>
        </div>
      `;
    }

    // 2. Моя станция (Personal Station)
    const isPersonal = lowerTitle.includes('моя станция') ||
      lowerTitle.includes('my station') ||
      lowerId === 'station_personal' ||
      lowerId.startsWith('ra.u-') ||
      lowerUrl.includes('my-station') ||
      (lowerArt.includes('coverpersonal') && !lowerTitle.includes('hits'));

    if (isPersonal) {
      return `
        <div class="animated-plaque-wrap" style="background: linear-gradient(135deg, #590016 0%, #d41442 38%, #ff2a54 70%, #b5179e 100%);">
          <div class="animated-plaque-orb" style="background: radial-gradient(circle, rgba(255,94,58,0.5) 0%, rgba(250,35,59,0) 70%);"></div>
          <svg class="animated-plaque-svg" viewBox="0 0 500 500">
            ${headerPill}
            <circle class="plaque-spin-slow" cx="250" cy="235" r="154" fill="none" stroke="#ffffff" stroke-opacity="0.45" stroke-width="2.5" stroke-dasharray="28 14 12 14" />
            <circle class="plaque-spin-rev" cx="250" cy="235" r="126" fill="none" stroke="#ffffff" stroke-opacity="0.55" stroke-width="3" stroke-dasharray="36 16 14 16" />
            <circle class="plaque-spin-med" cx="250" cy="235" r="98" fill="none" stroke="#ffffff" stroke-opacity="0.65" stroke-width="3.2" stroke-dasharray="22 12 8 12" />
            <circle class="plaque-spin-rev" cx="250" cy="235" r="70" fill="none" stroke="#ffffff" stroke-opacity="0.7" stroke-width="3" stroke-dasharray="18 10" />
            <circle class="plaque-breathe" cx="250" cy="235" r="42" fill="none" stroke="#ffffff" stroke-opacity="0.5" stroke-width="2.5" />
            <g class="plaque-wave-anim">
              <path d="M 142 235 L 210 235 L 226 172 L 242 298 L 258 194 L 272 262 L 286 235 L 358 235" fill="none" stroke="#ffffff" stroke-width="8.5" stroke-linecap="round" stroke-linejoin="round" />
            </g>
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="29" font-weight="600" fill="#ffffff" text-anchor="middle">${IS_EN ? 'MY STATION' : 'МОЯ СТАНЦИЯ'}</text>
            <text x="250" y="448" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="12" font-weight="500" letter-spacing="2.4" fill="#ffffff" fill-opacity="0.82" text-anchor="middle">PERSONAL STATION</text>
          </svg>
        </div>
      `;
    }

    // 3. В моём вкусе / Favorites Mix / Your Essentials
    const isFavoritesMix = lowerTitle.includes('в моем вкусе') ||
      lowerTitle.includes('в моём вкусе') ||
      lowerTitle.includes('favorites mix') ||
      lowerTitle.includes('your essentials') ||
      lowerTitle.includes('избранн') ||
      lowerId === 'favorites_mix';

    if (isFavoritesMix) {
      return `
        <div class="animated-plaque-wrap" style="background: linear-gradient(135deg, #2b0538 0%, #9b0068 38%, #ff0a6c 72%, #ff5e7e 100%);">
          <div class="animated-plaque-orb" style="background: radial-gradient(circle, rgba(255,10,108,0.55) 0%, rgba(155,0,104,0) 70%);"></div>
          <svg class="animated-plaque-svg" viewBox="0 0 500 500">
            ${headerPill}
            <circle class="plaque-spin-slow" cx="250" cy="235" r="146" fill="none" stroke="#ffffff" stroke-opacity="0.35" stroke-width="2" stroke-dasharray="16 14" />
            <circle class="plaque-spin-rev" cx="250" cy="235" r="114" fill="none" stroke="#ff85a1" stroke-opacity="0.55" stroke-width="2.8" stroke-dasharray="28 14" />
            <circle class="plaque-breathe" cx="250" cy="235" r="84" fill="#ffffff" fill-opacity="0.08" stroke="#ffffff" stroke-opacity="0.45" stroke-width="2" />
            <g class="plaque-heartbeat">
              <path d="M 250 288 C 250 288 188 244 188 202 C 188 178 207 162 228 162 C 241 162 250 171 250 179 C 250 171 259 162 272 162 C 293 162 312 178 312 202 C 312 244 250 288 250 288 Z" fill="#ffffff" fill-opacity="0.95" />
              <path d="M 212 216 L 232 216 L 241 194 L 250 238 L 259 204 L 268 216 L 288 216" fill="none" stroke="#d41442" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round" />
            </g>
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="28" font-weight="600" fill="#ffffff" text-anchor="middle">${IS_EN ? 'FAVORITES MIX' : 'В МОЁМ ВКУСЕ'}</text>
            <text x="250" y="448" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="12" font-weight="500" letter-spacing="2.4" fill="#ffb3c6" text-anchor="middle">FAVORITES MIX</text>
          </svg>
        </div>
      `;
    }

    // 4. Сейчас на повторе (Heavy Rotation Mix)
    const isHeavyRotation = lowerTitle.includes('на повторе') ||
      lowerTitle.includes('heavy rotation') ||
      lowerArt.includes('coverheavyrotation');

    if (isHeavyRotation) {
      return `
        <div class="animated-plaque-wrap" style="background: linear-gradient(135deg, #ff5e3a 0%, #ff2a6d 55%, #7b0046 100%);">
          <div class="animated-plaque-orb" style="background: radial-gradient(circle, rgba(255,180,80,0.45) 0%, rgba(255,42,109,0) 70%);"></div>
          <svg class="animated-plaque-svg" viewBox="0 0 500 500">
            ${headerPill}
            <circle class="plaque-spin-slow" cx="250" cy="235" r="142" fill="none" stroke="#ffffff" stroke-opacity="0.45" stroke-width="2.2" stroke-dasharray="10 10" />
            <circle class="plaque-spin-rev" cx="250" cy="235" r="104" fill="none" stroke="#ffffff" stroke-opacity="0.6" stroke-width="3" stroke-dasharray="16 12" />
            <circle class="plaque-spin-med" cx="250" cy="235" r="66" fill="none" stroke="#ffffff" stroke-opacity="0.75" stroke-width="3.5" stroke-dasharray="32 12" />
            <g class="plaque-spin-med">
              <path d="M 210 215 C 230 195, 270 195, 290 215 C 310 235, 310 265, 290 285 C 270 305, 230 305, 210 285 M 275 285 L 290 285 L 290 300" fill="none" stroke="#ffffff" stroke-width="11" stroke-linecap="round" stroke-linejoin="round" />
            </g>
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="27" font-weight="600" fill="#ffffff" text-anchor="middle">${IS_EN ? 'HEAVY ROTATION' : 'СЕЙЧАС НА ПОВТОРЕ'}</text>
            <text x="250" y="448" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="12" font-weight="500" letter-spacing="2.2" fill="#ffffff" fill-opacity="0.82" text-anchor="middle">HEAVY ROTATION MIX</text>
          </svg>
        </div>
      `;
    }

    // 5. Новинки для вас (New Music Mix)
    const isNewMusicMix = lowerTitle.includes('новинки для вас') ||
      lowerTitle.includes('new music mix') ||
      lowerTitle.includes('микс новинок');

    if (isNewMusicMix) {
      return `
        <div class="animated-plaque-wrap" style="background: linear-gradient(135deg, #051937 0%, #004d7a 42%, #008793 75%, #00bf72 100%);">
          <div class="animated-plaque-orb" style="background: radial-gradient(circle, rgba(0,245,212,0.45) 0%, rgba(0,77,122,0) 70%);"></div>
          <svg class="animated-plaque-svg" viewBox="0 0 500 500">
            ${headerPill}
            <circle class="plaque-spin-slow" cx="250" cy="235" r="144" fill="none" stroke="#80ffdb" stroke-opacity="0.45" stroke-width="2.2" stroke-dasharray="20 12" />
            <circle class="plaque-spin-rev" cx="250" cy="235" r="106" fill="none" stroke="#ffffff" stroke-opacity="0.55" stroke-width="2.8" stroke-dasharray="12 16" />
            <g class="plaque-breathe">
              <polygon points="250,138 268,217 347,235 268,253 250,332 232,253 153,235 232,217" fill="#ffffff" fill-opacity="0.92" />
              <circle cx="250" cy="235" r="24" fill="#00f5d4" />
            </g>
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="27" font-weight="600" fill="#ffffff" text-anchor="middle">${IS_EN ? 'NEW MUSIC MIX' : 'НОВИНКИ ДЛЯ ВАС'}</text>
            <text x="250" y="448" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="12" font-weight="500" letter-spacing="2.2" fill="#80ffdb" text-anchor="middle">NEW MUSIC MIX</text>
          </svg>
        </div>
      `;
    }

    // 6. Чилл-микс / Chill & Lo-Fi
    const isChill = lowerTitle.includes('чилл') ||
      lowerTitle.includes('chill') ||
      lowerArt.includes('coverchill');

    if (isChill) {
      const titleText = lowerTitle.includes('lo-fi') ? 'CHILL & LO-FI' : (IS_EN ? 'CHILL MIX' : 'ЧИЛЛ-МИКС');
      const subText = lowerTitle.includes('lo-fi') ? 'AMBIENT & LO-FI BEATS' : 'CHILL MIX';
      return `
        <div class="animated-plaque-wrap" style="background: linear-gradient(135deg, #0b132b 0%, #1c2541 38%, #0077b6 74%, #00b4d8 100%);">
          <div class="animated-plaque-orb" style="background: radial-gradient(circle, rgba(144,224,239,0.45) 0%, rgba(28,37,65,0) 70%);"></div>
          <svg class="animated-plaque-svg" viewBox="0 0 500 500">
            ${headerPill}
            <circle class="plaque-breathe" cx="250" cy="215" r="78" fill="#90e0ef" fill-opacity="0.22" stroke="#caf0f8" stroke-opacity="0.7" stroke-width="2.5" />
            <circle class="plaque-spin-slow" cx="250" cy="215" r="118" fill="none" stroke="#90e0ef" stroke-opacity="0.4" stroke-width="2" stroke-dasharray="18 14" />
            <g class="plaque-float-y">
              <path d="M 110 255 Q 180 215 250 255 T 390 255" fill="none" stroke="#ffffff" stroke-width="5.5" stroke-linecap="round" />
              <path d="M 130 285 Q 190 248 250 285 T 370 285" fill="none" stroke="#90e0ef" stroke-width="4" stroke-linecap="round" stroke-opacity="0.85" />
              <path d="M 155 312 Q 202 282 250 312 T 345 312" fill="none" stroke="#caf0f8" stroke-width="3" stroke-linecap="round" stroke-opacity="0.6" />
            </g>
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="27" font-weight="600" fill="#ffffff" text-anchor="middle">${escapeHtml(titleText)}</text>
            <text x="250" y="448" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="12" font-weight="500" letter-spacing="2.2" fill="#90e0ef" text-anchor="middle">${escapeHtml(subText)}</text>
          </svg>
        </div>
      `;
    }

    // 7. Драйв-микс / Заряд энергии (Get Up! Mix)
    const isGetUp = lowerTitle.includes('драйв') ||
      lowerTitle.includes('энерг') ||
      lowerTitle.includes('get up');

    if (isGetUp) {
      return `
        <div class="animated-plaque-wrap" style="background: linear-gradient(135deg, #ff4e00 0%, #ff9500 50%, #ff0055 100%);">
          <div class="animated-plaque-orb" style="background: radial-gradient(circle, rgba(255,230,0,0.5) 0%, rgba(255,0,85,0) 70%);"></div>
          <svg class="animated-plaque-svg" viewBox="0 0 500 500">
            ${headerPill}
            <circle class="plaque-spin-slow" cx="250" cy="235" r="142" fill="none" stroke="#ffffff" stroke-opacity="0.5" stroke-width="3" stroke-dasharray="8 16" />
            <circle class="plaque-spin-rev" cx="250" cy="235" r="106" fill="none" stroke="#fff3b0" stroke-opacity="0.7" stroke-width="2.5" stroke-dasharray="24 12" />
            <g class="plaque-wave-anim">
              <rect x="182" y="195" width="16" height="80" rx="8" fill="#ffffff" />
              <rect x="212" y="160" width="16" height="150" rx="8" fill="#ffffff" />
              <rect x="242" y="140" width="16" height="190" rx="8" fill="#fff3b0" />
              <rect x="272" y="168" width="16" height="134" rx="8" fill="#ffffff" />
              <rect x="302" y="200" width="16" height="70" rx="8" fill="#ffffff" />
            </g>
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="27" font-weight="600" fill="#ffffff" text-anchor="middle">${escapeHtml(IS_EN ? 'GET UP! MIX' : (rawTitle.toUpperCase() || 'ДРАЙВ-МИКС'))}</text>
            <text x="250" y="448" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="12" font-weight="500" letter-spacing="2.2" fill="#fff3b0" text-anchor="middle">GET UP! MIX</text>
          </svg>
        </div>
      `;
    }

    // 8. Микс для друзей (Friends Mix)
    const isFriends = lowerTitle.includes('друзей') || lowerTitle.includes('friends');
    if (isFriends) {
      return `
        <div class="animated-plaque-wrap" style="background: linear-gradient(135deg, #240046 0%, #5a189a 45%, #9d4edd 78%, #ff758f 100%);">
          <div class="animated-plaque-orb" style="background: radial-gradient(circle, rgba(255,117,143,0.45) 0%, rgba(90,24,154,0) 70%);"></div>
          <svg class="animated-plaque-svg" viewBox="0 0 500 500">
            ${headerPill}
            <g class="plaque-spin-slow">
              <circle cx="222" cy="235" r="88" fill="none" stroke="#e0aaff" stroke-opacity="0.7" stroke-width="3.5" />
              <circle cx="278" cy="235" r="88" fill="none" stroke="#ffccd5" stroke-opacity="0.7" stroke-width="3.5" />
            </g>
            <circle class="plaque-breathe" cx="250" cy="235" r="136" fill="none" stroke="#ffffff" stroke-opacity="0.35" stroke-width="2" stroke-dasharray="14 14" />
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="27" font-weight="600" fill="#ffffff" text-anchor="middle">${IS_EN ? 'FRIENDS MIX' : 'МИКС ДЛЯ ДРУЗЕЙ'}</text>
            <text x="250" y="448" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="12" font-weight="500" letter-spacing="2.2" fill="#e0aaff" text-anchor="middle">FRIENDS MIX</text>
          </svg>
        </div>
      `;
    }

    // 9. Artist Stations & Genre / Live Stations
    const lowerTag = (item.tag || '').toLowerCase();
    const isArtistStation = lowerTitle.includes('подобные артисты') ||
      lowerTitle.includes('similar artists') ||
      lowerTag.includes('по артисту') ||
      lowerTag.includes('artist station') ||
      lowerSub.includes('по артисту') ||
      lowerSub.includes('artist station');

    if (isArtistStation) {
      if (lowerArt.startsWith('http')) {
        return null;
      }
      const cleanArtist = rawTitle
        .replace(/и другие подобные артисты/gi, '')
        .replace(/& similar artists( station)?/gi, '')
        .replace(/радиостанция/gi, '')
        .trim() || rawTitle;
      const artistFontSize = cleanArtist.length > 18 ? 20 : (cleanArtist.length > 12 ? 24 : 28);
      return `
        <div class="animated-plaque-wrap" style="background: linear-gradient(135deg, #1b1035 0%, #3b1c71 48%, #7b2cbf 82%, #c77dff 100%);">
          <div class="animated-plaque-orb" style="background: radial-gradient(circle, rgba(199,125,255,0.35) 0%, rgba(0,0,0,0) 70%);"></div>
          <svg class="animated-plaque-svg" viewBox="0 0 500 500">
            ${headerPill}
            <circle class="plaque-spin-slow" cx="250" cy="230" r="138" fill="none" stroke="#e0aaff" stroke-opacity="0.38" stroke-width="2" stroke-dasharray="18 12" />
            <circle class="plaque-spin-rev" cx="250" cy="230" r="98" fill="none" stroke="#ffffff" stroke-opacity="0.5" stroke-width="2.5" stroke-dasharray="12 12" />
            <g class="plaque-wave-anim">
              <path d="M 125 230 L 190 230 L 212 165 L 236 290 L 256 190 L 278 270 L 298 178 L 318 275 L 334 230 L 375 230" fill="none" stroke="#ffffff" stroke-width="7" stroke-linecap="round" stroke-linejoin="round" />
            </g>
            <text x="250" y="418" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="${artistFontSize}" font-weight="700" fill="#ffffff" text-anchor="middle">${escapeHtml(cleanArtist.toUpperCase())}</text>
            <text x="250" y="446" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="11.5" font-weight="600" letter-spacing="2" fill="#e0aaff" text-anchor="middle">${IS_EN ? 'ARTIST STATION' : 'РАДИОСТАНЦИЯ ПО АРТИСТУ'}</text>
          </svg>
        </div>
      `;
    }

    const isStationCard = !lowerArt.startsWith('http') && (lowerId.startsWith('station_') || lowerArt.includes('/assets/stations/'));
    if (isStationCard) {
      let bgGrad = 'linear-gradient(135deg, #06281e 0%, #007f5f 48%, #2b9348 78%, #55a630 100%)';
      let accentColor = '#80ffdb';
      let subLabel = 'APPLE MUSIC RADIO';

      if (lowerTitle.includes('electronic') || lowerTitle.includes('dance')) {
        bgGrad = 'linear-gradient(135deg, #041b15 0%, #007f5f 45%, #00b862 82%, #70e000 100%)';
        accentColor = '#80ffdb';
        subLabel = 'CLUB & FESTIVAL BANGERS';
      } else if (lowerTitle.includes('apple music 1')) {
        bgGrad = 'linear-gradient(135deg, #141416 0%, #2c2c30 48%, #fa233b 100%)';
        accentColor = '#ff6b8b';
        subLabel = 'LIVE GLOBAL RADIO';
      } else if (lowerTitle.includes('hits')) {
        bgGrad = 'linear-gradient(135deg, #800f2f 0%, #c9184a 45%, #ff4d6d 80%, #ff8fa3 100%)';
        accentColor = '#ffccd5';
        subLabel = 'ESSENTIAL HITS';
      } else if (lowerTitle.includes('country')) {
        bgGrad = 'linear-gradient(135deg, #582f0e 0%, #b66d0d 48%, #f7971e 82%, #ffd200 100%)';
        accentColor = '#ffe6a7';
        subLabel = 'MODERN COUNTRY';
      } else if (lowerTitle.includes('pop')) {
        bgGrad = 'linear-gradient(135deg, #7209b7 0%, #b5179e 48%, #f72585 100%)';
        accentColor = '#ffafcc';
        subLabel = 'POP ANTHEMS';
      } else if (lowerTitle.includes('deep house') || lowerTitle.includes('house')) {
        bgGrad = 'linear-gradient(135deg, #10002b 0%, #240046 45%, #5a189a 80%, #7b2cbf 100%)';
        accentColor = '#c77dff';
        subLabel = 'DEEP ATMOSPHERIC GROOVE';
      } else if (lowerTitle.includes('rock')) {
        bgGrad = 'linear-gradient(135deg, #1b1b1e 0%, #370617 48%, #9d0208 85%, #dc2f02 100%)';
        accentColor = '#ffba08';
        subLabel = 'ROCK LEGENDS';
      }

      const displayStationTitle = (rawTitle || 'RADIO').toUpperCase();
      const stationFontSize = displayStationTitle.length > 20 ? 19 : (displayStationTitle.length > 14 ? 22 : 25);

      return `
        <div class="animated-plaque-wrap" style="background: ${bgGrad};">
          <div class="animated-plaque-orb" style="background: radial-gradient(circle, rgba(255,255,255,0.22) 0%, rgba(0,0,0,0) 70%);"></div>
          <svg class="animated-plaque-svg" viewBox="0 0 500 500">
            ${headerPill}
            <circle class="plaque-spin-slow" cx="250" cy="235" r="142" fill="none" stroke="${accentColor}" stroke-opacity="0.38" stroke-width="2" stroke-dasharray="22 12" />
            <circle class="plaque-spin-rev" cx="250" cy="235" r="104" fill="none" stroke="#ffffff" stroke-opacity="0.5" stroke-width="2.5" stroke-dasharray="14 14" />
            <g class="plaque-wave-anim">
              <path d="M 110 235 L 185 235 L 208 162 L 234 298 L 256 188 L 278 274 L 300 176 L 320 282 L 336 235 L 390 235" fill="none" stroke="#ffffff" stroke-width="7.5" stroke-linecap="round" stroke-linejoin="round" />
            </g>
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="${stationFontSize}" font-weight="600" fill="#ffffff" text-anchor="middle">${escapeHtml(displayStationTitle)}</text>
            <text x="250" y="448" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="11.5" font-weight="600" letter-spacing="2.2" fill="${accentColor}" text-anchor="middle">${escapeHtml(subLabel)}</text>
          </svg>
        </div>
      `;
    }

    return null;
  }
