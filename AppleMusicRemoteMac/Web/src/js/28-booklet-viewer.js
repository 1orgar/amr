  // =========================================================================
  // APPLE DIGITAL BOOKLET VIEWER (OFFICIAL APPLE PDF READER)
  // - Desktop / Tablet Landscape: Replaces right column (.inline-right-pane)
  // - StandBy TV & Mobile Portrait: Fullscreen (.fullscreen-mode)
  // - Pages rendered sequentially on the full width of the area
  // =========================================================================

  const bookletState = {
    isOpen: false,
    info: null,
    targetAlbum: '',
    targetArtist: '',
    targetAlbumId: '',
    lastCheckedTrackKey: ''
  };

  const bookletAvailabilityCache = new Map();

  function openRawBookletPdf(rawPdfUrl) {
    if (!rawPdfUrl || typeof rawPdfUrl !== 'string') return;
    const trimmed = rawPdfUrl.trim();
    if (!trimmed.startsWith('/api/') && !trimmed.startsWith('https://')) return;
    window.open(trimmed, '_blank', 'noopener,noreferrer');
  }

  function makeBookletCacheKey(album, artist) {
    return `${(artist || '').trim().toLowerCase()}|${(album || '').trim().toLowerCase()}`;
  }

  function syncBookletViewerLayoutMode() {
    const modal = document.getElementById('booklet-viewer-modal');
    if (!modal) return;

    const isTvOrMobileLandscape = isStandbyOrLandscapeVisible();
    const isDesktopTwoCol = isDesktopLayout() && !isTvOrMobileLandscape;

    if (isDesktopTwoCol) {
      modal.classList.add('inline-right-pane');
      modal.classList.remove('fullscreen-mode');
      const rightPane = document.querySelector('.content-panel-wrapper');
      if (rightPane) {
        const rect = rightPane.getBoundingClientRect();
        if (rect.width > 100 && rect.left > 0) {
          modal.style.left = `${Math.round(rect.left)}px`;
        } else {
          modal.style.left = '';
        }
      }
    } else {
      modal.classList.add('fullscreen-mode');
      modal.classList.remove('inline-right-pane');
      modal.style.left = '';
    }

    const btnOpenNowPlaying = document.getElementById('btn-open-booklet');
    if (btnOpenNowPlaying) {
      btnOpenNowPlaying.classList.toggle('active', bookletState.isOpen);
    }
  }

  async function fetchBookletInfoCached({ album, artist, albumId = '', trackName = '', refresh = false }) {
    const cleanAlbum = (album || '').trim();
    const cleanArtist = (artist || '').trim();
    if (!cleanAlbum) return null;

    const cacheKey = makeBookletCacheKey(cleanAlbum, cleanArtist);
    if (!refresh && bookletAvailabilityCache.has(cacheKey)) {
      return bookletAvailabilityCache.get(cacheKey);
    }

    const qs = new URLSearchParams({
      album: cleanAlbum,
      artist: cleanArtist,
      album_id: albumId || '',
      track: trackName || '',
      refresh: refresh ? '1' : '0',
      device_id: state.deviceId || ''
    });
    const resp = await fetch(`/api/booklet/info?${qs.toString()}`, {
      cache: 'no-store',
      headers: buildDeviceAuthHeaders()
    });
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    const info = await resp.json();
    setBoundedMapValue(bookletAvailabilityCache, cacheKey, info, 200);
    return info;
  }

  async function syncCurrentTrackBookletAvailability() {
    const btnOpenNowPlaying = document.getElementById('btn-open-booklet');
    const btnOpenStandby = document.getElementById('standby-btn-booklet');
    const moreDot = dom.moreBookletDot || document.getElementById('more-booklet-dot');
    const bookletSub = document.getElementById('station-opt-booklet-sub');
    const t = state.track;
    const album = t && t.album ? t.album.trim() : '';
    const artist = t && t.artist ? t.artist.trim() : '';

    if (!album) {
      bookletState.lastCheckedTrackKey = '';
      if (btnOpenNowPlaying) btnOpenNowPlaying.classList.add('hidden');
      if (btnOpenStandby) btnOpenStandby.classList.add('hidden');
      if (moreDot) moreDot.classList.add('hidden');
      if (bookletState.isOpen && !bookletState.targetAlbumId) {
        closeBookletViewer();
      }
      return;
    }

    const key = makeBookletCacheKey(album, artist);
    if (key === bookletState.lastCheckedTrackKey && bookletAvailabilityCache.has(key)) {
      const cached = bookletAvailabilityCache.get(key);
      const isAvail = Boolean(cached && cached.available && cached.page_count > 0);
      if (btnOpenNowPlaying) btnOpenNowPlaying.classList.toggle('hidden', !isAvail);
      if (btnOpenStandby) btnOpenStandby.classList.toggle('hidden', !isAvail);
      if (moreDot) moreDot.classList.toggle('hidden', !isAvail);
      if (bookletSub && isAvail) {
        bookletSub.textContent = `${album} • ${cached.page_count} стр.`;
      }
      if (bookletState.isOpen && !bookletState.targetAlbumId && bookletState.targetAlbum !== album) {
        if (isAvail) {
          bookletState.targetAlbum = album;
          bookletState.targetArtist = artist;
          fetchAndRenderBooklet({ album, artist, trackName: (t && t.name) || '' });
        } else {
          closeBookletViewer();
        }
      }
      return;
    }

    bookletState.lastCheckedTrackKey = key;
    if (btnOpenNowPlaying) btnOpenNowPlaying.classList.add('hidden');
    if (btnOpenStandby) btnOpenStandby.classList.add('hidden');
    if (moreDot) moreDot.classList.add('hidden');

    try {
      const info = await fetchBookletInfoCached({
        album,
        artist,
        trackName: (t && t.name) || ''
      });
      if (bookletState.lastCheckedTrackKey !== key) return;
      const isAvail = Boolean(info && info.available && info.page_count > 0);
      if (btnOpenNowPlaying) btnOpenNowPlaying.classList.toggle('hidden', !isAvail);
      if (btnOpenStandby) btnOpenStandby.classList.toggle('hidden', !isAvail);
      if (moreDot) moreDot.classList.toggle('hidden', !isAvail);
      if (bookletSub && isAvail) {
        bookletSub.textContent = `${album} • ${info.page_count} стр.`;
      }
      if (bookletState.isOpen && !bookletState.targetAlbumId && bookletState.targetAlbum !== album) {
        if (isAvail) {
          bookletState.targetAlbum = album;
          bookletState.targetArtist = artist;
          fetchAndRenderBooklet({ album, artist, trackName: (t && t.name) || '' });
        } else {
          closeBookletViewer();
        }
      }
    } catch (err) {
      if (btnOpenNowPlaying) btnOpenNowPlaying.classList.add('hidden');
      if (btnOpenStandby) btnOpenStandby.classList.add('hidden');
      if (moreDot) moreDot.classList.add('hidden');
      if (bookletState.isOpen && !bookletState.targetAlbumId && bookletState.targetAlbum !== album) {
        closeBookletViewer();
      }
    }
  }

  async function syncDetailAlbumBookletAvailability(alb) {
    const btnDetailBooklet = document.getElementById('btn-detail-booklet');
    if (!btnDetailBooklet || !alb) return;
    btnDetailBooklet.classList.add('hidden');

    const album = (alb.name || alb.title || '').trim();
    const artist = (alb.artist || alb.sub || alb.subtitle || '').trim();
    const albumId = alb.id || '';
    if (!album) return;

    try {
      const info = await fetchBookletInfoCached({ album, artist, albumId });
      const curDet = state.currentPlaylistDetail;
      if (!curDet || !curDet.isAlbum || (curDet.name || curDet.title || '').trim() !== album) return;
      const isAvail = Boolean(info && info.available && info.page_count > 0);
      btnDetailBooklet.classList.toggle('hidden', !isAvail);
    } catch (err) {
      btnDetailBooklet.classList.add('hidden');
    }
  }

  async function openBookletViewer(customTarget = null) {
    triggerHaptic('light');
    const modal = document.getElementById('booklet-viewer-modal');
    if (!modal) return;

    const album = (customTarget && customTarget.album)
      || (state.track && state.track.album)
      || '';
    const artist = (customTarget && customTarget.artist)
      || (state.track && state.track.artist)
      || '';
    const albumId = (customTarget && customTarget.albumId) || '';
    const trackName = (state.track && state.track.name) || '';

    if (!album) {
      showToast('У текущего трека нет буклета Apple Music');
      return;
    }

    // If clicking the Now Playing booklet button while it's already open for this album, toggle close
    if (!customTarget && bookletState.isOpen && bookletState.targetAlbum === album) {
      closeBookletViewer();
      return;
    }

    bookletState.isOpen = true;
    bookletState.targetAlbum = album;
    bookletState.targetArtist = artist;
    bookletState.targetAlbumId = albumId;

    const btnOpenNowPlaying = document.getElementById('btn-open-booklet');
    const btnOpenStandby = document.getElementById('standby-btn-booklet');
    if (!customTarget) {
      if (btnOpenNowPlaying) btnOpenNowPlaying.classList.add('active');
      if (btnOpenStandby) btnOpenStandby.classList.add('active');
    }

    syncBookletViewerLayoutMode();
    modal.classList.remove('hidden');
    modal.setAttribute('aria-hidden', 'false');

    const loadingEl = document.getElementById('booklet-loading');
    const listEl = document.getElementById('booklet-pages-list');
    const viewport = document.getElementById('booklet-viewport');

    if (loadingEl) loadingEl.classList.remove('hidden');
    if (listEl) listEl.innerHTML = '';
    if (viewport) viewport.scrollTop = 0;

    await fetchAndRenderBooklet({ album, artist, albumId, trackName, refresh: false });
  }

  function closeBookletViewer() {
    const modal = document.getElementById('booklet-viewer-modal');
    if (!modal) return;
    blurFocusedInContainer(modal);
    bookletState.isOpen = false;
    modal.classList.add('hidden');
    modal.setAttribute('aria-hidden', 'true');
    const btnOpenNowPlaying = document.getElementById('btn-open-booklet');
    if (btnOpenNowPlaying) {
      btnOpenNowPlaying.classList.remove('active');
    }
    const btnOpenStandby = document.getElementById('standby-btn-booklet');
    if (btnOpenStandby) {
      btnOpenStandby.classList.remove('active');
    }
  }

  async function fetchAndRenderBooklet({ album, artist, albumId = '', trackName = '', refresh = false }) {
    const loadingEl = document.getElementById('booklet-loading');
    try {
      const info = await fetchBookletInfoCached({ album, artist, albumId, trackName, refresh });
      if (!info || !info.available || !info.pages || info.pages.length === 0) {
        closeBookletViewer();
        showToast('Для этого альбома нет официального буклета в Apple Music');
        return;
      }
      applyBookletInfo(info);
    } catch (err) {
      console.warn('Booklet load error:', err);
      closeBookletViewer();
      showToast('Не удалось загрузить цифровой буклет Apple Music');
    } finally {
      if (loadingEl) loadingEl.classList.add('hidden');
    }
  }

  function appendDeviceIdToUrl(url) {
    if (!url || typeof url !== 'string') return url || '';
    const trimmed = url.trim();
    if (!trimmed.startsWith('/api/') || /[?&]device_id=/.test(trimmed)) return trimmed;
    const hashIdx = trimmed.indexOf('#');
    const base = hashIdx >= 0 ? trimmed.slice(0, hashIdx) : trimmed;
    const hash = hashIdx >= 0 ? trimmed.slice(hashIdx) : '';
    const sep = base.includes('?') ? '&' : '?';
    return `${base}${sep}device_id=${encodeURIComponent(state.deviceId || '')}${hash}`;
  }

  function applyBookletInfo(info) {
    if (!info || !info.available || !info.pages || info.pages.length === 0) return;
    bookletState.info = {
      ...info,
      pdf_url: info.pdf_url ? appendDeviceIdToUrl(info.pdf_url) : info.pdf_url
    };
    renderBookletSequentialPages();
  }

  function renderBookletSequentialPages() {
    const listEl = document.getElementById('booklet-pages-list');
    const info = bookletState.info;
    if (!listEl || !info || !info.pages) return;

    listEl.innerHTML = '';

    // When structured editorial data is present (non-scanned PDF), render native responsive HTML
    // using the system / PWA font stack & rem sizes so mobile text is crisp and comfortable to read.
    if (info.editorial && !info.is_original_pdf) {
      renderNativeEditorialBookletDOM(listEl, info, info.editorial);
      return;
    }

    info.pages.forEach((p, idx) => {
      const card = document.createElement('div');
      card.className = 'booklet-seq-page-card';

      const img = document.createElement('img');
      img.className = 'booklet-seq-page-img';
      img.src = appendDeviceIdToUrl(p.image_url);
      img.alt = p.title || `Страница ${idx + 1}`;
      img.loading = idx < 2 ? 'eager' : 'lazy';

      card.appendChild(img);
      listEl.appendChild(card);
    });
  }

  function renderNativeEditorialBookletDOM(container, info, ed) {
    const albumName = info.album || bookletState.targetAlbum || '';
    const artistName = info.artist || bookletState.targetArtist || '';
    const releaseDate = ed.release_date || info.release_date || '';
    const recordLabel = ed.record_label || info.record_label || '';
    const copyright = ed.copyright || info.copyright || '';
    const genre = ed.genre || '';
    const isADM = Boolean(ed.is_mastered_for_itunes);
    const traits = Array.isArray(ed.audio_traits) ? ed.audio_traits : [];
    const tracks = Array.isArray(ed.tracks) ? ed.tracks : [];
    const paras = Array.isArray(ed.editorial_paragraphs) ? ed.editorial_paragraphs : [];
    const coverSrc = appendDeviceIdToUrl(ed.artwork_url || (state.track ? getArtworkSrc(state.track) : 'apple-touch-icon.svg'));
    const totalSections = 2 + (tracks.length > 0 ? 1 : 0);

    // 1. Cover Section
    const coverSec = document.createElement('section');
    coverSec.className = 'booklet-native-page';
    const metaParts = [];
    if (genre) metaParts.push(genre);
    if (releaseDate) metaParts.push(String(releaseDate).slice(0, 4));
    if (tracks.length > 0) {
      metaParts.push(IS_EN ? `${tracks.length} tracks` : `${tracks.length} композиций`);
    }
    const summaryQuote = ed.summary_quote || '';
    const badgeLabel = isADM ? 'APPLE DIGITAL MASTER' : 'APPLE MUSIC EDITION';

    coverSec.innerHTML = `
      <div class="booklet-native-topbar">
        <span class="booklet-native-kicker">APPLE MUSIC • DIGITAL BOOKLET</span>
        <span class="booklet-native-edition-badge">${escapeHtml(badgeLabel)}</span>
      </div>
      <div class="booklet-native-cover-wrap">
        <img class="booklet-native-cover-img" src="${escapeHtml(coverSrc)}" alt="${escapeHtml(albumName)}" loading="eager">
        <div class="booklet-native-cover-meta">
          <h1 class="booklet-native-album-title">${escapeHtml(albumName)}</h1>
          <div class="booklet-native-album-artist">${escapeHtml(artistName)}</div>
          ${metaParts.length ? `<div class="booklet-native-album-sub">${escapeHtml(metaParts.join('  •  '))}</div>` : ''}
          ${summaryQuote ? `<p class="booklet-native-quote">${escapeHtml(summaryQuote)}</p>` : ''}
        </div>
      </div>
      <div class="booklet-native-footer">
        <span>${escapeHtml(recordLabel || copyright)}</span>
        <span>${IS_EN ? `PAGE 1 / ${totalSections}` : `СТР. 1 / ${totalSections}`}</span>
      </div>
    `;
    container.appendChild(coverSec);

    // 2. Editorial & Release Specs Section
    const edSec = document.createElement('section');
    edSec.className = 'booklet-native-page';
    const totalSec = Math.round(tracks.reduce((acc, t) => acc + (Number(t.duration_seconds) || 0), 0));
    const runtimeStr = tracks.length > 0
      ? (IS_EN
        ? `${Math.floor(totalSec / 60)} min ${String(totalSec % 60).padStart(2, '0')} sec (${tracks.length} tracks)`
        : `${Math.floor(totalSec / 60)} мин ${String(totalSec % 60).padStart(2, '0')} сек (${tracks.length} треков)`)
      : '—';
    const masteringStr = isADM
      ? 'Apple Digital Master • Lossless'
      : (traits.length > 0 ? traits.join(', ') : 'Apple Music Lossless');

    const specs = [
      { label: IS_EN ? 'ARTIST' : 'ИСПОЛНИТЕЛЬ', value: artistName || '—' },
      { label: IS_EN ? 'RELEASE DATE' : 'ДАТА РЕЛИЗА', value: releaseDate || '—' },
      { label: IS_EN ? 'GENRE' : 'ЖАНР', value: genre || '—' },
      { label: IS_EN ? 'RECORD LABEL' : 'ЛЕЙБЛ / ИЗДАТЕЛЬ', value: recordLabel || '—' },
      { label: IS_EN ? 'RUNTIME' : 'ХРОНОМЕТРАЖ', value: runtimeStr },
      { label: IS_EN ? 'APPLE MASTERING' : 'МАСТЕРИНГ APPLE', value: masteringStr }
    ];

    const parasHtml = paras.map(p => `<p class="booklet-native-para">${escapeHtml(p)}</p>`).join('');
    const specsHtml = specs.map(s => `
      <div class="booklet-native-spec-item">
        <span class="booklet-native-spec-label">${escapeHtml(s.label)}</span>
        <span class="booklet-native-spec-value">${escapeHtml(s.value)}</span>
      </div>
    `).join('');

    edSec.innerHTML = `
      <div class="booklet-native-sec-header">
        <div class="booklet-native-kicker">${IS_EN ? 'ALBUM STORY, RECORDING & CONCEPT' : 'ИСТОРИЯ СОЗДАНИЯ, ЗАПИСЬ И КОНЦЕПЦИЯ АЛЬБОМА'}</div>
        <h2 class="booklet-native-sec-title">${escapeHtml(albumName)}</h2>
        <div class="booklet-native-sec-sub">${escapeHtml(artistName)}</div>
      </div>
      ${parasHtml ? `<div class="booklet-native-body">${parasHtml}</div>` : ''}
      <div class="booklet-native-specs-card">${specsHtml}</div>
      <div class="booklet-native-footer">
        <span>${escapeHtml(copyright || recordLabel)}</span>
        <span>${IS_EN ? `PAGE 2 / ${totalSections}` : `СТР. 2 / ${totalSections}`}</span>
      </div>
    `;
    container.appendChild(edSec);

    // 3. Track-by-Track & Credits Section
    if (tracks.length > 0) {
      const trkSec = document.createElement('section');
      trkSec.className = 'booklet-native-page';

      const tracksHtml = tracks.map(t => {
        const numStr = String(t.number || 1).padStart(2, '0');
        const durSec = Math.round(Number(t.duration_seconds) || 0);
        const durStr = durSec > 0
          ? `${Math.floor(durSec / 60)}:${String(durSec % 60).padStart(2, '0')}`
          : '—';
        const badges = [];
        if (t.artist) badges.push(t.artist);
        if (t.audio_badge) badges.push(t.audio_badge);
        if (t.isrc) badges.push(`ISRC: ${t.isrc}`);

        const creditRows = [];
        if (t.composer) {
          creditRows.push({
            label: IS_EN ? 'WRITERS & COMPOSERS' : 'АВТОРЫ И КОМПОЗИТОРЫ',
            val: t.composer
          });
        }
        if (Array.isArray(t.producers) && t.producers.length > 0) {
          creditRows.push({
            label: IS_EN ? 'PRODUCTION & ARRANGEMENT' : 'ПРОДЮСИРОВАНИЕ И АРАНЖИРОВКА',
            val: t.producers.join(' • ')
          });
        }
        if (Array.isArray(t.vocals) && t.vocals.length > 0) {
          creditRows.push({
            label: IS_EN ? 'VOCALS' : 'ВОКАЛ',
            val: t.vocals.join(' • ')
          });
        }
        if (Array.isArray(t.instruments) && t.instruments.length > 0) {
          creditRows.push({
            label: IS_EN ? 'INSTRUMENTS & MUSICIANS' : 'ИНСТРУМЕНТЫ И МУЗЫКАНТЫ',
            val: t.instruments.join(' • ')
          });
        }
        if (Array.isArray(t.samples) && t.samples.length > 0) {
          creditRows.push({
            label: IS_EN ? 'SAMPLES & INTERPOLATIONS' : 'СЭМПЛЫ И ЦИТАТЫ',
            val: t.samples.join(' • ')
          });
        }
        if (Array.isArray(t.studios) && t.studios.length > 0) {
          creditRows.push({
            label: IS_EN ? 'RECORDING STUDIOS' : 'СТУДИИ ЗАПИСИ',
            val: t.studios.join(' • ')
          });
        }

        const creditsHtml = creditRows.length > 0
          ? `<div class="booklet-native-track-credits">${creditRows.map(r => `
              <div class="booklet-native-credit-row">
                <span class="booklet-native-credit-label">${escapeHtml(r.label)}:</span> ${escapeHtml(r.val)}
              </div>
            `).join('')}</div>`
          : '';

        return `
          <article class="booklet-native-track-card">
            <div class="booklet-native-track-top">
              <div class="booklet-native-track-title-wrap">
                <span class="booklet-native-track-num">${escapeHtml(numStr)}</span>
                <h3 class="booklet-native-track-title">${escapeHtml(t.title || '')}</h3>
              </div>
              <span class="booklet-native-track-dur">${escapeHtml(durStr)}</span>
            </div>
            ${badges.length ? `<div class="booklet-native-track-badges">${escapeHtml(badges.join('   •   '))}</div>` : ''}
            ${t.commentary ? `<p class="booklet-native-track-comm">${escapeHtml(t.commentary)}</p>` : ''}
            ${creditsHtml}
          </article>
        `;
      }).join('');

      trkSec.innerHTML = `
        <div class="booklet-native-sec-header">
          <div class="booklet-native-kicker">${IS_EN ? 'TRACK-BY-TRACK GUIDE & CREDITS' : 'ПОЛНОЕ ОПИСАНИЕ ПО КОМПОЗИЦИЯМ • TRACK-BY-TRACK & CREDITS'}</div>
          <h2 class="booklet-native-sec-title">${escapeHtml(albumName)}</h2>
          <div class="booklet-native-sec-sub">${escapeHtml(artistName)}</div>
        </div>
        <div class="booklet-native-tracks-list">${tracksHtml}</div>
        <div class="booklet-native-footer">
          <span>${escapeHtml(copyright || recordLabel)}</span>
          <span>${IS_EN ? `PAGE 3 / ${totalSections}` : `СТР. 3 / ${totalSections}`}</span>
        </div>
      `;
      container.appendChild(trkSec);
    }
  }
