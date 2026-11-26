  function translateTextToEn(raw) {
    if (!IS_EN || !raw || typeof raw !== 'string') return raw;
    const trimmed = raw.trim();
    if (!trimmed) return raw;
    if (RU_TO_EN_EXACT[trimmed]) {
      return raw.replace(trimmed, RU_TO_EN_EXACT[trimmed]);
    }
    let out = raw;
    out = out
      .replace(/^✨\s*ИИ-подбор по вайбу «(.+)»\.\.\.$/i, '✨ Curating AI vibe from "$1"...')
      .replace(/^✨\s*ИИ-подбор по вайбу «(.+)»$/i, '✨ AI Vibe Mix from "$1"')
      .replace(/^ИИ-микс:\s*(.+)$/i, 'AI Mix: $1')
      .replace(/^Перейти к альбому «(.+)»$/i, 'Go to Album "$1"')
      .replace(/^Поиск:\s*(.+)$/i, 'Search: $1')
      .replace(/^Запуск «Моей станции»\.\.\.$/i, 'Starting My Station...')
      .replace(/^Запуск «Станции открытий»\.\.\.$/i, 'Starting Discovery Station...')
      .replace(/^Запуск «В моём вкусе»\.\.\.$/i, 'Starting Favorites Mix...')
      .replace(/^Запуск «Сейчас на повторе»\.\.\.$/i, 'Starting Heavy Rotation...')
      .replace(/^Запуск радио по треку «(.+)»\.\.\.$/i, 'Starting track station "$1"...')
      .replace(/^Запуск радио по артисту «(.+)»\.\.\.$/i, 'Starting artist station "$1"...')
      .replace(/^Запуск станции «(.+)»\.\.\.$/i, 'Starting station "$1"...')
      .replace(/^Запуск альбома «(.+)»\.\.\.$/i, 'Starting album "$1"...')
      .replace(/^Запуск микса «(.+)»\.\.\.$/i, 'Starting mix "$1"...')
      .replace(/^Запуск радио «(.+)»\.\.\.$/i, 'Starting radio "$1"...')
      .replace(/^Запуск плейлиста «(.+)»\.\.\.$/i, 'Starting playlist "$1"...')
      .replace(/^Запуск «(.+)»\.\.\.$/i, 'Starting "$1"...')
      .replace(/^Станция «(.+)»$/i, '"$1" Station')
      .replace(/^Перемешивание «(.+)»\.\.\.$/i, 'Shuffling "$1"...')
      .replace(/^Подключение к (.+)\.\.\.$/i, 'Connecting to $1...')
      .replace(/^Не удалось запустить станцию «(.+)»\. Проверьте подписку Apple Music на Mac\.$/i, 'Could not start station "$1". Check your Apple Music subscription on Mac.')
      .replace(/^Запуск\s+(.+)\.\.\.$/i, 'Starting $1...')
      .replace(/^Очередь AMR\s*·\s*(\d+)\s*трек(?:ов|а)?$/i, 'AMR Queue · $1 tracks')
      .replace(/^(\d+)\s*трек(?:ов|а)?\s+в очереди$/i, '$1 tracks in queue')
      .replace(/Последний коммит:\s*([^\s(]+)\s*\(([^)]+)\)\s*•\s*(.+)/i, 'Latest commit: $1 ($2) • $3')
      .replace(/UID:\s*([^\s•]+)\s*•\s*Авторизовано на Mac/i, 'UID: $1 • Authorized on Mac')
      .replace(/Попытка переподключения через (\d+)с\.\.\. \(попытка (\d+)\)/i, 'Reconnecting in $1s... (attempt $2)')
      .replace(/Apple Music:\s*подписка активна\s*•\s*Регион\s*([^\s•]+)\s*•\s*Медиатека синхронизирована/i, 'Apple Music: Active • Storefront $1 • Library Synced')
      .replace(/Апсемплинг CD \(срез\s*([\d.]+)\s*(?:кГц|kHz)\)/i, 'Upsampled CD ($1 kHz cut)')
      .replace(/Lossy-транскод \(([^•]+)•\s*срез\s*([\d.]+)\s*(?:кГц|kHz)\)/i, 'Lossy Transcode ($1• $2 kHz cut)')
      .replace(/Lossy-апскейл \(([^)]+)\)/i, 'Lossy Upscale ($1)')
      .replace(/В потоке\s*([\d.]+)\s*(?:кГц|kHz)\s*отсутствует ультразвуковая энергия выше 22\.05\s*(?:кГц|kHz)\s*\(([^)]+)\)\.\s*Трек получен апсемплингом из 44\.1\s*(?:кГц|kHz)\./i, 'No ultrasonic energy above 22.05 kHz ($2) in $1 kHz stream. Track is upsampled from 44.1 kHz.')
      .replace(/Обнаружен резкий кирпичный срез ВЧ на\s*([\d.]+)\s*(?:кГц|kHz)\s*при контейнере ALAC\.\s*Вероятно,\s*исходник был сжат в MP3\/AAC\s*\(([^)]+)\)\./i, 'Brickwall HF cutoff detected at $1 kHz inside ALAC container. Source was likely transcoded from lossy MP3/AAC ($2).')
      .replace(/Несмотря на битрейт потока 256 kbps,\s*спектр резко обрывается на\s*([\d.]+)\s*(?:кГц|kHz)[^.]*\.\s*Запись пережата из низкого битрейта\s*\(([^)]+)\)\./i, 'Despite 256 kbps stream bitrate, spectrum cuts off sharply at $1 kHz. Track was re-encoded from low bitrate ($2).')
      .replace(/Поток AAC 256 kbps соответствует эталонному профилю:\s*верхняя граница спектра простирается до\s*([\d.]+)\s*(?:кГц|kHz)[^.]*\./i, 'AAC 256 kbps stream matches reference profile: upper frequency extends to $1 kHz with no signs of low-bitrate upscale.')
      .replace(/Спектр чистый \(до\s*([\d.]+)\s*(?:кГц|kHz)\),\s*но младшие 8 бит \(17–24\) всех сэмплов равны нулю\.\s*Реальная разрядность мастера — 16 бит\./i, 'Clean spectrum (up to $1 kHz), but lower 8 bits (17–24) are all zero. True master bit depth is 16-bit.')
      .replace(/Подлинный студийный Hi-Res мастер:\s*зафиксирована живая ультразвуковая составляющая до\s*([\d.]+)\s*(?:кГц|kHz)\s*\(([^)]+)\)\s*и честные\s*(\d+)\s*бит\./i, 'Authentic studio Hi-Res master: live ultrasonic energy verified up to $1 kHz ($2) with true $3-bit resolution.')
      .replace(/Подлинный 24-битный студийный мастер 48\s*(?:кГц|kHz):\s*полный спектр до\s*([\d.]+)\s*(?:кГц|kHz)\s*и активные младшие разряды \(LSB 24-bit\)\./i, 'Authentic 24-bit / 48 kHz studio master: full spectrum up to $1 kHz and active 24-bit LSB.')
      .replace(/Честный Lossless-спектр до\s*([\d.]+)\s*(?:кГц|kHz)\s*без признаков психоакустической фильтрации MP3\/AAC\s*\(([^)]+)\)\./i, 'Verified Lossless spectrum up to $1 kHz with no MP3/AAC psychoacoustic filtering ($2).')
      .replace(/Сбор PCM-фреймов из CoreAudio Process Tap\s*\(([^)]+)\)\s*для верификации спектра vDSP FFT\./i, 'Capturing PCM frames from CoreAudio Process Tap ($1) for vDSP FFT verification.')
      .replace(/Накопление пиковой ВЧ-огибающей трека[^.]*\.\.\./i, 'Accumulating peak HF envelope (awaiting high-frequency transients above 16 kHz)...')
      .replace(/Формат контейнера ALAC\s*([^.]+)\.\s*Включите воспроизведение для живого БПФ-анализа спектра\./i, 'ALAC container ($1). Start playback for live FFT spectral verification.')
      .replace(/Воспроизводится сжатый поток AAC\s*\(([^)]+)\)\.\s*Включите воспроизведение для проверки спектра\./i, 'Playing compressed AAC stream ($1). Start playback for spectral check.')
      .replace(/Частота ЦАП \(([^)]+)\) аппаратно синхронизирована с потоком\.\s*Деградация разрядности исключена\./i, 'DAC sample rate ($1) is hardware-locked to the stream. Zero bit-depth degradation.')
      .replace(/Hi-Res PCM поток \(([^)]+)\) захватывается напрямую из Music\.app и передается на сетевой рендерер без передискретизации\./i, 'Hi-Res PCM stream ($1) is captured directly from Music.app and streamed bit-perfectly to the network renderer.')
      .replace(/Воспроизводится сжатый поток AAC 256 kbps \(полоса до ~19\.5 кГц\)\.\s*Для Bit-Perfect переключитесь на ALAC Lossless\./i, 'Playing compressed AAC 256 kbps stream (~19.5 kHz bandwidth). Switch to ALAC Lossless for Bit-Perfect output.')
      .replace(/64-bit DSP • Синхронная частота \(([^)]+)\)/i, '64-bit DSP • Synced Clock ($1)')
      .replace(/Частота ЦАП \(([^)]+)\) синхронизирована 1:1 с потоком без передискретизации\.\s*Активна 64-битная обработка \(([^)]+)\)\./i, 'DAC clock ($1) is synced 1:1 with the source stream without resampling. Active 64-bit processing ($2).')
      .replace(/Системный микшер macOS \(([^)]+)\)/i, 'macOS System Mixer ($1)')
      .replace(/Частота и разрядность совпадают \(([^)]+)\), но поток проходит через микшер macOS CoreAudio\./i, 'Sample rate and bit depth match ($1), routed through macOS CoreAudio mixer.')
      .replace(/Внешний USB ЦАП не подключён:\s*DSD и HQ NOS доступны только для USB ЦАП\s*\(([^)]+)\)/i, 'No external USB DAC connected: DSD and HQ NOS are available only for USB DACs ($1)')
      .replace(/Передискретизация \(([^)]+)\)/i, 'Resampling ($1)')
      .replace(/Преобразование разрядности \(([^)]+)\)/i, 'Bit-Depth Quantization ($1)')
      .replace(/Частота дискретизации синхронизирована 1:1 \(([^)]+)\) без передискретизации;\s*выполняется квантование разрядности \(([^)]+)\)\./i, 'Sample rate is synced 1:1 ($1) without resampling; bit-depth quantization applied ($2).')
      .replace(/Частота дискретизации источника \(([^)]+)\) пересчитывается в режим вывода \(([^)]+)\)\./i, 'Source sample rate ($1) is resampled to output mode ($2).')
      .replace(/Недостаточная частота (DSD\d+) для источника \(([^)]+)\)/i, 'Insufficient $1 Rate for Source ($2)')
      .replace(/Поток источника \(([^)]+)\) превышает оптимальную полосу однобитного режима (DSD\d+)\.\s*Выберите ([^д]+) для раскрытия битрейта без потерь\./i, 'Source stream ($1) exceeds optimal bandwidth of 1-bit $2 mode. Select $3 for lossless resolution.')
      .replace(/Частота или разрядность источника \(([^)]+)\) отличается от текущего режима вывода \(([^)]+)\)\./i, 'Source format ($1) differs from current output mode ($2).')
      .replace(/Прямое подключение macOS CoreAudio HAL \(([^)]+)\)/i, 'Direct macOS CoreAudio HAL ($1)')
      .replace(/Прямой вывод CoreAudio \(Bit-Perfect 100% • Громкость: ([^)]+)\)/i, 'Direct CoreAudio Output (Bit-Perfect 100% • Volume: $1)')
      .replace(/Прямой вывод CoreAudio \(Bit-Perfect 100% • Ожидание ([^)]+)\)/i, 'Direct CoreAudio Output (Bit-Perfect 100% • Waiting for $1)')
      .replace(/Управление громкостью по TCP • Лимит до (\d+)%/gi, 'TCP Volume Control • Cap $1%')
      .replace(/Ожидание подключения по TCP • Лимит до (\d+)%/gi, 'Waiting for TCP connection • Cap $1%')
      .replace(/макс\.\s*(\d+)%/gi, 'max $1%')
      .replace(/Активен профиль «([^»]+)» \(([^•]+)•\s*Headroom\s*([-\d.]+)\s*(?:дБ|dB)\s*•\s*синхронизирован с iCloud Drive\)\./i, 'Active profile "$1" ($2• Headroom $3 dB • synced with iCloud Drive).')
      .replace(/Профиль «([^»]+)» сохранён в облаке \(([^)]+)\)\.\s*Нажмите «Вкл» для активации 64-bit Auto-PEQ\./i, 'Profile "$1" saved in iCloud ($2). Tap "On" to enable 64-bit Auto-PEQ.')
      .replace(/Усреднение спектра в точке прослушивания \(([\d.]+)\s*с\)\.\.\./i, 'Averaging spectrum at listening position ($1s)...')
      .replace(/Профиль «([^»]+)» удалён/i, 'Profile "$1" deleted')
      .replace(/Несовпадение регионов:\s*Mac \(([^)]+)\) и Web \(([^)]+)\)\./i, 'Storefront mismatch: Mac ($1) vs Web ($2).')
      .replace(/Не удалось декодировать аудиофайл микрофона \(код ([^)]+)\)\.[^]*/i, 'Could not decode microphone audio file (code $1). Use iOS Voice Memos / Mic capture (M4A/WAV).')
      .replace(/Срок действия встроенного MusicKit Developer JWT истек\.[^]*/i, 'Built-in MusicKit Developer JWT has expired. Update the app or refresh the developer key.')
      .replace(/⏭\s*«([^»]+)» недоступен в Apple Music — пропуск/i, '⏭ "$1" is unavailable in Apple Music — skipping')
      .replace(/Сетевой (Hi-Res|Lossless|PCM) стриминг \(([^)]+)\)\s*•\s*(.+)/i, 'Network $1 Streaming ($2) • $3')
      .replace(/Сетевой стример\s*•\s*До 192 кГц Hi-Res\s*•\s*(.+)/i, 'Network Streamer • Up to 192 kHz Hi-Res • $1')
      .replace(/\((\d+)\s*частот\)/i, '($1 rates)')
      .replace(/Буфер\s*(\d+(?:\.\d+)?)%/gi, 'Buffer $1%')
      .replace(/Ширина M\/S:/g, 'M/S Width:')
      .replace(/Баланс L\/R:/g, 'L/R Balance:')
      .replace(/Lossless\s*\(Остановлен\)/gi, 'Lossless (Stopped)')
      .replace(/Буферизация/gi, 'Buffering')
      .replace(/Ожидание CDN/gi, 'Waiting for CDN')
      .replace(/Декодирование в PCM/g, 'Decoded to PCM')
      .replace(/Декодирование AAC → PCM/g, 'AAC → PCM Decode')
      .replace(/Бесконечный PCM поток/g, 'Continuous PCM Stream')
      .replace(/Bypass микшера/g, 'Mixer Bypass')
      .replace(/(\d+)-бит\s*\(Честный(?:\s*LSB)?\)/gi, '$1-bit (True LSB)')
      .replace(/(\d+)-бит\s*\(в\s*(\d+)-бит\)/gi, '$1-bit (in $2-bit)')
      .replace(/(\d+)-бит/gi, '$1-bit')
      .replace(/Нет\s*\(<([-\d.]+)\s*dB\)/gi, 'None (<$1 dB)')
      .replace(/Н\/Д\s*\(≤\s*48\s*(?:кГц|kHz)\)/gi, 'N/A (≤ 48 kHz)')
      .replace(/([\d.]+)кГц/gi, '$1kHz')
      .replace(/([\d.]+)Гц/gi, '$1Hz')
      .replace(/([+-]?[\d.]+)\s*дБ/gi, '$1 dB')
      .replace(/([\d.]+)\s*МГц/gi, '$1 MHz')
      .replace(/до\s*([\d.]+)\s*кГц/gi, 'up to $1 kHz')
      .replace(/([\d.]+)\s*кГц/gi, '$1 kHz')
      .replace(/(\d+)\s*Гц/gi, '$1 Hz')
      .replace(/(\d+)\s*мс/gi, '$1 ms')
      .replace(/(\d+)\s*трек(?:ов|а)?/gi, '$1 tracks')
      .replace(/(\d+)\s*альбом(?:ов|а)?/gi, '$1 albums')
      .replace(/(\d+)\s*исполнител(?:ей|я|ь)/gi, '$1 artists')
      .replace(/^Плейлисты Apple Music\s*•\s*(\d+)$/i, 'Apple Music Playlists • $1')
      .replace(/^Альбомы в медиатеке\s*•\s*(\d+)$/i, 'Albums in Library • $1')
      .replace(/^Исполнители в медиатеке\s*•\s*(\d+)$/i, 'Artists in Library • $1')
      .replace(/^Треки в медиатеке\s*•\s*(\d+)$/i, 'Songs in Library • $1')
      .replace(/^Недавно добавленные\s*•\s*(.+)$/i, 'Recently Added • $1')
      .replace(/В медиатеке сохранено\s*(\d+)\s*из\s*(\d+)\s*(?:трек(?:ов|а)?|tracks)\s*этого альбома/gi, '$1 of $2 tracks from this album saved in Library')
      .replace(/^Показать полный альбом\s*\((\d+)\)\s*→$/i, 'Show Complete Album ($1) →')
      .replace(/(\d+)\s*из\s*(\d+)\s*(?:трек(?:ов|а)?|tracks)\s*в медиатеке/gi, '$1 of $2 tracks in Library')
      .replace(/(\d+)\s*из\s*(\d+)\s*в медиатеке/gi, '$1 of $2 in Library')
      .replace(/^Удалено из медиатеки:\s*(.+)$/i, 'Removed from Library: $1')
      .replace(/(\d+)\s*стр\./gi, '$1 pp.')
      .replace(/Страница\s*(\d+)/gi, 'Page $1');
    return out;
  }

  const DYNAMIC_USER_CONTENT_SELECTOR = '.track-title, .track-artist, .track-album, .track-row-title, .track-row-artist, .mini-title, .mini-artist, .standby-title, .standby-artist, .standby-album, .playlist-title, .playlist-card-title, .card-title, .card-subtitle, .media-card-title, .media-card-sub, .collection-tile-title, .collection-tile-sub, .artist-row-name, [data-dynamic-text]';

  function isInsideDynamicUserContent(node) {
    if (!node) return false;
    const el = node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
    return Boolean(el && typeof el.closest === 'function' && el.closest(DYNAMIC_USER_CONTENT_SELECTOR));
  }

  function localizeDomNode(root, skipDynamic = false) {
    if (!IS_EN || !root) return;
    if (skipDynamic && isInsideDynamicUserContent(root)) return;
    if (root.nodeType === Node.TEXT_NODE) {
      const val = root.nodeValue;
      if (val && /[А-Яа-яЁё]/.test(val)) {
        const next = translateTextToEn(val);
        if (next !== val) root.nodeValue = next;
      }
      return;
    }
    if (root.nodeType !== Node.ELEMENT_NODE) return;
    const attrs = ['title', 'placeholder', 'aria-label', 'alt'];
    if (!(skipDynamic && root.matches && root.matches(DYNAMIC_USER_CONTENT_SELECTOR))) {
      for (let i = 0; i < attrs.length; i++) {
        const attr = attrs[i];
        if (root.hasAttribute && root.hasAttribute(attr)) {
          const cur = root.getAttribute(attr);
          if (cur && /[А-Яа-яЁё]/.test(cur)) {
            const next = translateTextToEn(cur);
            if (next !== cur) root.setAttribute(attr, next);
          }
        }
      }
    }
    const filter = skipDynamic
      ? {
          acceptNode(candidate) {
            if (candidate.nodeType === Node.ELEMENT_NODE && candidate.matches && candidate.matches(DYNAMIC_USER_CONTENT_SELECTOR)) {
              return NodeFilter.FILTER_REJECT;
            }
            return NodeFilter.FILTER_ACCEPT;
          }
        }
      : null;
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, filter, false);
    let node = walker.nextNode();
    while (node) {
      if (node.nodeType === Node.TEXT_NODE) {
        if (!skipDynamic || !isInsideDynamicUserContent(node)) {
          const val = node.nodeValue;
          if (val && /[А-Яа-яЁё]/.test(val)) {
            const next = translateTextToEn(val);
            if (next !== val) node.nodeValue = next;
          }
        }
      } else if (node.nodeType === Node.ELEMENT_NODE) {
        for (let i = 0; i < attrs.length; i++) {
          const attr = attrs[i];
          if (node.hasAttribute && node.hasAttribute(attr)) {
            const cur = node.getAttribute(attr);
            if (cur && /[А-Яа-яЁё]/.test(cur)) {
              const next = translateTextToEn(cur);
              if (next !== cur) node.setAttribute(attr, next);
            }
          }
        }
      }
      node = walker.nextNode();
    }
  }

  const I18N_OBSERVE_OPTS = {
    childList: true,
    subtree: true,
    characterData: true,
    attributes: true,
    attributeFilter: ['title', 'placeholder', 'aria-label', 'alt']
  };

  if (IS_EN) {
    const authDescEl = document.querySelector('#device-auth-overlay .overlay-desc');
    if (authDescEl) {
      authDescEl.innerHTML = 'Open <strong>Apple Music Remote Settings</strong> on your Mac ("General" tab) and click <strong>"Authorize"</strong> next to this device.';
    }
    localizeDomNode(document.body, false);
    let isApplyingI18n = false;
    const i18nObserver = new MutationObserver((mutations) => {
      if (isApplyingI18n) return;
      isApplyingI18n = true;
      i18nObserver.disconnect();
      try {
        for (let i = 0; i < mutations.length; i++) {
          const m = mutations[i];
          if (m.type === 'characterData') {
            if (!isInsideDynamicUserContent(m.target)) {
              localizeDomNode(m.target, true);
            }
          } else if (m.type === 'attributes') {
            const el = m.target;
            const attr = m.attributeName;
            if (el && attr && !isInsideDynamicUserContent(el) && el.hasAttribute(attr)) {
              const cur = el.getAttribute(attr);
              if (cur && /[А-Яа-яЁё]/.test(cur)) {
                const next = translateTextToEn(cur);
                if (next !== cur) el.setAttribute(attr, next);
              }
            }
          } else if (m.type === 'childList') {
            for (let j = 0; j < m.addedNodes.length; j++) {
              localizeDomNode(m.addedNodes[j], true);
            }
          }
        }
      } finally {
        i18nObserver.takeRecords();
        if (document.body) {
          i18nObserver.observe(document.body, I18N_OBSERVE_OPTS);
        }
        isApplyingI18n = false;
      }
    });
    if (document.body) {
      i18nObserver.observe(document.body, I18N_OBSERVE_OPTS);
    }
  }

  // --- Global CSP-Safe Image Fallback Handler (Eliminates Inline onerror & Offline Loops) ---
  document.addEventListener('error', (e) => {
    const img = e.target;
    if (!img || img.tagName !== 'IMG' || img.dataset.fallbackApplied) return;
    if (img.dataset.fallbackIcon) {
      img.dataset.fallbackApplied = '1';
      img.src = img.dataset.fallbackIcon;
    } else if (img.dataset.fallbackMode === 'next-flex') {
      img.dataset.fallbackApplied = '1';
      img.style.display = 'none';
      if (img.nextElementSibling) {
        img.nextElementSibling.style.display = 'flex';
      }
    } else if (img.dataset.fallbackMode === 'parent-fallback') {
      img.dataset.fallbackApplied = '1';
      img.style.display = 'none';
      if (img.parentElement) {
        img.parentElement.classList.add('has-fallback');
      }
    }
  }, true);

  // --- PWA Service Worker Registration ---
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('/sw.js').catch((err) => {
        console.warn('AMR ServiceWorker registration:', err);
      });
    });
  }

  // --- Persistent Client Device Identity (Cookie + CacheStorage + localStorage) ---
  function readCookieValue(name) {
    try {
      const target = name.toLowerCase() + '=';
      const parts = (document.cookie || '').split(';');
      for (const p of parts) {
        const trimmed = p.trim();
        if (trimmed.toLowerCase().startsWith(target)) {
          return decodeURIComponent(trimmed.slice(target.length).trim());
        }
      }
    } catch (e) {}
    return '';
  }

  function writePersistentCookie(name, val) {
    try {
      document.cookie = `${name}=${encodeURIComponent(val)}; path=/; max-age=315360000; SameSite=Strict`;
    } catch (e) {}
  }

  function persistDeviceSecret(secret) {
    const clean = String(secret || '').trim();
    if (!clean) return;
    if (typeof state !== 'undefined' && state) {
      state.deviceSecret = clean;
    }
    writePersistentCookie('amr_device_secret', clean);
    try { localStorage.setItem('amr_device_secret', clean); } catch (e) {}
    if (typeof window !== 'undefined' && 'caches' in window && window.caches && typeof window.caches.open === 'function') {
      Promise.resolve()
        .then(() => window.caches.open('amr-device-secure-store-v1'))
        .then((cache) => {
          if (cache && typeof cache.put === 'function' && typeof Response === 'function') {
            return cache.put('/__amr_device_secret', new Response(clean, { headers: { 'Content-Type': 'text/plain' } }));
          }
        })
        .catch(() => {});
    }
  }

  function clearInviteTokenFromClient() {
    if (typeof state !== 'undefined' && state) {
      state.inviteToken = '';
    }
    try { sessionStorage.removeItem('amr_invite_token'); } catch (e) {}
  }

  function buildDeviceAuthHeaders(extraHeaders = {}) {
    const headers = {
      'X-AMR-Device-ID': (typeof state !== 'undefined' && state && state.deviceId) ? state.deviceId : '',
      ...extraHeaders
    };
    if (typeof state !== 'undefined' && state && state.deviceSecret) {
      headers['X-AMR-Device-Secret'] = state.deviceSecret;
    }
    return headers;
  }

  function generateUUIDv4() {
    if (window.crypto && typeof window.crypto.randomUUID === 'function') {
      return window.crypto.randomUUID().toLowerCase();
    }
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
      const r = (Math.random() * 16) | 0;
      const v = c === 'x' ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    });
  }

  function computeShortDeviceId(uid) {
    const clean = String(uid || '').replace(/-/g, '').toUpperCase();
    if (clean.length >= 8) {
      return `${clean.slice(0, 4)}-${clean.slice(4, 8)}`;
    }
    return clean || '----';
  }

  function persistUidToSecureStore(uid) {
    if (!uid) return;
    writePersistentCookie('amr_device_uid', uid);
    try { localStorage.setItem('amr_device_uid', uid); } catch (e) {}
    if (typeof window !== 'undefined' && 'caches' in window && window.caches && typeof window.caches.open === 'function') {
      Promise.resolve()
        .then(() => window.caches.open('amr-device-secure-store-v1'))
        .then((cache) => {
          if (cache && typeof cache.put === 'function' && typeof Response === 'function') {
            return cache.put('/__amr_device_uid', new Response(uid, { headers: { 'Content-Type': 'text/plain' } }));
          }
        })
        .catch(() => {});
    }
  }

  function detectClientDeviceProfile() {
    const ua = navigator.userAgent || '';
    const platform = navigator.platform || '';
    const maxTouch = navigator.maxTouchPoints || 0;
    const isIPad = /iPad/i.test(ua) || (platform === 'MacIntel' && maxTouch > 1);
    const isIPhone = /iPhone|iPod/i.test(ua);
    const isAndroid = /Android/i.test(ua);
    const isAndroidMobile = isAndroid && /Mobile/i.test(ua);
    const isTV = /TV|Web0S|Tizen|BRAVIA|AppleTV|CrKey/i.test(ua);

    let deviceType = 'desktop';
    let defaultName = 'Mac / Desktop';

    if (isTV) {
      deviceType = 'tv';
      defaultName = 'Smart TV';
    } else if (isIPad || (isAndroid && !isAndroidMobile)) {
      deviceType = 'tablet';
      defaultName = isIPad ? 'iPad' : 'Android Tablet';
    } else if (isIPhone || isAndroidMobile) {
      deviceType = 'mobile';
      defaultName = isIPhone ? 'iPhone' : 'Android Phone';
    } else if (/Macintosh|Mac OS X/i.test(ua)) {
      deviceType = 'desktop';
      defaultName = /Safari/i.test(ua) && !/Chrome/i.test(ua) ? 'Mac (Safari)' : 'Mac (Browser)';
    } else if (/Windows/i.test(ua)) {
      deviceType = 'desktop';
      defaultName = 'Windows PC';
    }

    const cookieUid = readCookieValue('amr_device_uid');
    let lsUid = '';
    try { lsUid = (localStorage.getItem('amr_device_uid') || '').trim(); } catch (_) {}
    let uid = lsUid || cookieUid;
    let uidWasFreshlyGenerated = false;
    if (!uid) {
      uid = generateUUIDv4();
      uidWasFreshlyGenerated = true;
    }
    const hasCacheStorage = typeof window !== 'undefined' && 'caches' in window && Boolean(window.caches);
    if (!uidWasFreshlyGenerated || !hasCacheStorage) {
      persistUidToSecureStore(uid);
    }

    let savedName = '';
    try { savedName = localStorage.getItem('amr_device_name') || ''; } catch (e) {}
    const deviceName = savedName.trim() || defaultName;

    let savedLockPref = null;
    const cookieLock = readCookieValue('amr_lock_screen');
    if (cookieLock === 'true' || cookieLock === 'false') {
      savedLockPref = (cookieLock === 'true');
    } else {
      try {
        const lsLock = localStorage.getItem('amr_lock_screen_controls');
        if (lsLock === 'true' || lsLock === 'false') {
          savedLockPref = (lsLock === 'true');
        }
      } catch (e) {}
    }

    const defaultLockScreen = (deviceType === 'mobile');
    const lockScreenControls = savedLockPref !== null ? savedLockPref : defaultLockScreen;

    let inviteToken = '';
    try {
      const urlParams = new URLSearchParams(window.location.search || '');
      const urlInvite = (urlParams.get('invite') || '').trim();
      if (urlInvite) {
        inviteToken = urlInvite;
        try { sessionStorage.setItem('amr_invite_token', urlInvite); } catch (e) {}
        urlParams.delete('invite');
        const newQuery = urlParams.toString();
        const cleanUrl = window.location.pathname + (newQuery ? `?${newQuery}` : '') + (window.location.hash || '');
        if (window.history && typeof window.history.replaceState === 'function') {
          window.history.replaceState({}, document.title, cleanUrl);
        }
      } else {
        inviteToken = (sessionStorage.getItem('amr_invite_token') || '').trim();
      }
    } catch (e) {}

    let lsSecret = '';
    try { lsSecret = (localStorage.getItem('amr_device_secret') || '').trim(); } catch (_) {}
    const cookieSecret = readCookieValue('amr_device_secret');
    const deviceSecret = lsSecret || cookieSecret || '';
    if (deviceSecret) {
      writePersistentCookie('amr_device_secret', deviceSecret);
      try { localStorage.setItem('amr_device_secret', deviceSecret); } catch (_) {}
    }

    return {
      deviceId: uid,
      deviceSecret,
      shortId: computeShortDeviceId(uid),
      deviceIdWasFreshlyGenerated: uidWasFreshlyGenerated,
      deviceName,
      deviceType,
      lockScreenControls,
      inviteToken
    };
  }

  const initialDeviceProfile = detectClientDeviceProfile();

  // --- Application State ---
  const state = {
    connected: false,
    deviceId: initialDeviceProfile.deviceId,
    deviceSecret: initialDeviceProfile.deviceSecret || '',
    deviceShortId: initialDeviceProfile.shortId,
    deviceIdWasFreshlyGenerated: Boolean(initialDeviceProfile.deviceIdWasFreshlyGenerated),
    supersededFreshDeviceId: '',
    deviceName: initialDeviceProfile.deviceName,
    deviceType: initialDeviceProfile.deviceType,
    deviceAuthorized: false, // Updated by server on connect (false -> shows auth waiting screen first)
    deviceAuthChecked: false,
    initialAuthFetched: false,
    inviteToken: initialDeviceProfile.inviteToken || '',
    shareAccessUrl: '',
    lockScreenControls: initialDeviceProfile.lockScreenControls,
    allowDacSelection: true,
    allowDspPresetSelection: true,
    allowRoomMeasurement: true,
    allowLateNightMode: true,
    allowLibraryModification: true,
    isDlnaActive: false,
    lateNightDrcEnabled: false,
    lateNightDrcProfile: 'gentle',
    lateNightDrcMode: 'off',
    lateNightDrcGainDb: 0,
    lateNightDrcSubtitle: '',
    masteringDeclipMode: 'off',
    masteringDeclipRestoredDb: 0,
    masteringDeclipClipsCount: 0,
    masteringDeclipAutoBypassed: false,
    masteringDeclipSubtitle: '',
    masteringDeesserMode: 'off',
    masteringDeesserGainDb: 0,
    masteringDeesserSubtitle: '',
    sonicBridgeFrom: '',
    sonicBridgeTo: '',
    sonicBridgeSteps: 12,
    sonicBridgeAutoPlay: false,
    roomCorrectionActive: false,
    roomProfileName: '',
    isMeasuringRoom: false,
    roomIsPlayingTestSignal: false,
    roomActiveProfileId: '',
    awaitingNativeRoomFilePicker: false,
    nativePickerOpenedAt: 0,
    lastDspSettings: null,
    roomAcoustic: {
      enabled: false,
      is_test_signal_playing: false,
      active_profile_id: '',
      active_profile: null,
      profiles: [],
      bands_hz: []
    },
    aiCuratorEnabled: true,
    pinnedAiPrompts: [],
    activeAiCuratedPrompt: '',
    activeAiCuratedTitle: '',
    aiCurateReqSeq: 0,
    aiCurateTimeoutId: null,
    searchReqSeq: 0,
    lastAiCurateSentAt: 0,
    lastLibraryAddTarget: '',
    isAddingDetailToLibrary: false,
    lastDetailLibraryAddKey: '',
    lastDetailLibraryAddId: '',
    lastDetailLibraryAddName: '',
    currentDetailPlaylistId: '',
    currentDetailAlbumId: '',
    currentDetailTitle: '',
    pendingStandbyAiAutoPlay: false,
    isAiCurating: false,
    gitCommit: '7278dab',
    gitCommitDate: '2026-11-04',
    playbackState: 'stopped', // 'playing', 'paused', 'stopped'
    playerState: 'stopped', // 'playing', 'paused', 'stopped'
    pendingPlayUntil: 0,
    initialViewSelected: false,
    position: 0,
    duration: 0,
    volume: (() => {
      try {
        const raw = localStorage.getItem('amr_last_volume');
        if (raw !== null && !isNaN(Number(raw))) {
          return Math.max(0, Math.min(100, Number(raw)));
        }
      } catch (_) {}
      return 100;
    })(),
    previousVolume: 100,
    lockVolume100: (() => {
      try {
        const raw = localStorage.getItem('amr_lock_volume_100');
        return raw !== null ? (raw === 'true') : true;
      } catch (_) {
        return true;
      }
    })(),
    ampVolumeControlEnabled: (() => {
      try {
        const lockRaw = localStorage.getItem('amr_lock_volume_100');
        const locked = lockRaw !== null ? (lockRaw === 'true') : true;
        return locked && localStorage.getItem('amr_amp_volume_control') === 'true';
      } catch (_) {
        return false;
      }
    })(),
    ampBrandName: (() => {
      try {
        return localStorage.getItem('amr_amp_brand_name') || 'Rotel';
      } catch (_) {
        return 'Rotel';
      }
    })(),
    ampVolume: 35,
    ampMaxVolume: (() => {
      try {
        const raw = Number(localStorage.getItem('amr_amp_max_volume'));
        return (raw > 0 && raw <= 100) ? raw : 96;
      } catch (_) {
        return 96;
      }
    })(),
    ampMuted: (() => {
      try {
        return localStorage.getItem('amr_amp_muted') === 'true';
      } catch (_) {
        return false;
      }
    })(),
    ampConnected: false,
    isDlnaActive: (() => {
      try {
        return localStorage.getItem('amr_is_dlna_active') === 'true';
      } catch (_) {
        return false;
      }
    })(),
    isDraggingVolume: false,
    shuffle: false,
    repeatMode: 'off', // 'off', 'one', 'all'
    audioQuality: 'Lossless (ALAC 24-bit/48kHz)',
    track: null,
    queue: {
      upcoming: [],
      history: [],
      currentIndex: 0,
      totalTracks: 0,
      playlist: ''
    },
    playlists: [],
    libraryAlbums: [],
    libraryRecent: {
      albums: [],
      songs: [],
      loaded: false
    },
    libraryArtists: [],
    libraryArtistsLoaded: false,
    libraryArtistFilter: '',
    currentLibraryArtistDetail: null,
    librarySongs: [],
    librarySongsLoaded: false,
    librarySongsFilter: '',
    librarySongsRenderLimit: 250,
    libraryTab: 'recent',
    currentPlaylistDetail: null,
    currentAlbumDetail: null,
    currentAlbumSource: 'catalog',
    actionTargetTrack: null,
    tvLibraryConfigLoaded: false,
    tvLibraryConfig: {
      show_my_station: true,
      show_discovery_station: true,
      show_favorites_mix: true,
      show_heavy_rotation: true,
      playlists_mode: 'all',
      selected_playlist_names: [],
      albums_mode: 'recent',
      selected_albums: [],
      selected_album_keys: []
    },
    trends: {
      country: '',
      topSongs: [],
      stations: [],
      topAlbums: [],
      genres: [],
      loaded: false
    },
    searchQuery: '',
    searchScope: 'all',
    activeView: 'view-now-playing',
    lastNonPlayerView: 'view-home',
    desktopActiveTab: 'home',

    // Audio Devices & DAC
    audioDeviceName: '',
    audioDeviceSampleRate: 44100,
    isBitPerfect: true,
    dacMutingGuardEnabled: false,
    dacMutingGuardMs: 100,
    audioDevices: [],

    // Apple MusicKit & User Token (region & locale resolved dynamically from account)
    hasUserToken: false,
    developerToken: '',
    userStorefront: '',
    userLocale: '',
    isAccountSynced: false,
    accountHealth: null,

    // Scrubber local tracking & watchdog timestamps
    isScrubbing: false,
    scrubValue: 0,
    isBuffering: false,
    isStreamStalled: false,
    isStagingBuffer: false,
    loadingStage: null,
    loadingStartedAtMs: 0,
    hasStartedAdvancingForTrack: false,
    lastSyncPos: 0,
    lastSyncTime: performance.now(),
    lastServerMessageAt: Date.now(),
    lastClientCommandAt: 0,
    pendingPingSentAt: 0,
    lastSpectralUpdateAt: performance.now(),
    lastEndOfTrackPollAt: 0
  };
