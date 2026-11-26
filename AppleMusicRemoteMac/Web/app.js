/* AUTO-ASSEMBLED FROM Web/src/js/*.js BY Tools/sync_web_ui.py — EDIT Web/src/js/ MODULES */
(() => {
"use strict";

// === MODULE: 01-i18n-dictionary.js ===
  // --- Immediate Frame-0 iOS Standalone Full-Screen Shell Geometry ---
  // With apple-mobile-web-app-status-bar-style="black-translucent" + viewport-fit=cover,
  // iOS WebKit under-reports window.innerHeight / fixed bottom:0 by safe-area-inset-top (e.g. 894pt vs 956pt on Pro Max)
  // while WKWebView.bounds and 100lvh span all 956pt. Setting --standalone-shell-h synchronously before first paint
  // eliminates both the 62pt bottom black band and any startup viewport jerk or hit-test offset.
  function isStandalonePwaMode() {
    return Boolean(
      window.navigator.standalone === true ||
      (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches)
    );
  }

  function syncStandaloneShellGeometry() {
    const root = document.documentElement;
    if (!root) return;
    const standalone = isStandalonePwaMode();
    root.classList.toggle('ios-standalone', standalone);
    if (!standalone) {
      root.style.removeProperty('--standalone-shell-h');
      return;
    }
    const iw = window.innerWidth || 0;
    const ih = window.innerHeight || 0;
    const sw = (window.screen && window.screen.width) ? window.screen.width : 0;
    const sh = (window.screen && window.screen.height) ? window.screen.height : 0;
    let targetPx = ih;
    if (sw > 0 && sh > 0) {
      const minScreen = Math.min(sw, sh);
      const maxScreen = Math.max(sw, sh);
      let isPortrait = ih >= iw;
      if (sw !== sh) {
        if (iw > 0 && Math.abs(iw - minScreen) <= 24) {
          isPortrait = true;
        } else if (iw > 0 && Math.abs(iw - maxScreen) <= 24) {
          isPortrait = false;
        }
      }
      const physicalH = isPortrait ? maxScreen : minScreen;
      const gap = physicalH - ih;
      const isPhoneScreen = minScreen < 768;
      if (isPhoneScreen || (gap > 0 && gap <= 140)) {
        targetPx = physicalH;
      }
    }
    if (targetPx > 0) {
      const nextVal = `${targetPx}px`;
      if (root.style.getPropertyValue('--standalone-shell-h') !== nextVal) {
        root.style.setProperty('--standalone-shell-h', nextVal);
      }
    }
  }
  syncStandaloneShellGeometry();

  // --- Automatic English (EN) Localization for Non-Russian Device Locales ---
  function detectIsEnglishLocale() {
    try {
      const qsLang = new URLSearchParams(window.location.search).get('lang');
      if (qsLang === 'en') return true;
      if (qsLang === 'ru') return false;
      const saved = localStorage.getItem('amr_ui_lang');
      if (saved === 'en') return true;
      if (saved === 'ru') return false;
    } catch (_) {}
    const langs = (navigator.languages && navigator.languages.length > 0)
      ? navigator.languages
      : [navigator.language || 'ru'];
    const primary = String(langs[0] || 'ru').trim().toLowerCase();
    return !primary.startsWith('ru');
  }

  const IS_EN = detectIsEnglishLocale();
  if (IS_EN && document.documentElement) {
    document.documentElement.lang = 'en';
  }

  const RU_TO_EN_EXACT = {
    'Сейчас': 'Now Playing',
    'Главная': 'Home',
    'Медиатека': 'Library',
    'Очередь': 'Up Next',
    'Поиск': 'Search',
    'Подборки': 'Collections',
    'Очередь воспроизведения': 'Playing Next',
    'Очистить далее': 'Clear',
    'Очистить предстоящие треки': 'Clear upcoming tracks',
    'Закрыть очередь': 'Close Queue',
    'Предыдущие, текущий трек и следующие композиции': 'Previous, now playing, and upcoming tracks',
    'ПРЕДЫДУЩИЕ': 'PREVIOUS',
    'РАНЕЕ': 'PREVIOUS',
    'Показать все': 'Show All',
    'Свернуть': 'Show Less',
    'История пуста': 'No previous tracks',
    'СЕЙЧАС ИГРАЕТ': 'NOW PLAYING',
    'ДАЛЕЕ В ОЧЕРЕДИ': 'UP NEXT',
    'Нет предстоящих треков': 'No upcoming tracks',
    'Плейлисты и альбомы': 'Playlists & Albums',
    'Обновить': 'Refresh',
    'Обновить список': 'Refresh list',
    'Загрузка плейлистов...': 'Loading playlists...',
    'Плейлисты не найдены': 'No playlists found',
    'Плейлисты': 'Playlists',
    'ПЛЕЙЛИСТ': 'PLAYLIST',
    'АЛЬБОМ': 'ALBUM',
    'Альбом': 'Album',
    'Плейлист': 'Playlist',
    'Исполнитель': 'Artist',
    'Название': 'Title',
    'Без названия': 'Untitled',
    'Слушать': 'Play',
    'Слушать всё': 'Play All',
    'Перемешать': 'Shuffle',
    'В медиатеку': 'Add to Library',
    'В медиатеке ✓': 'In Library ✓',
    'В плейлисты': 'Add to Playlists',
    'В плейлистах ✓': 'In Playlists ✓',
    'Добавить в плейлисты Apple Music': 'Add to Apple Music Playlists',
    'Добавить в медиатеку Apple Music': 'Add to Apple Music Library',
    '★ Плейлист добавлен в плейлисты Apple Music': '★ Playlist added to Apple Music Playlists',
    'Не удалось добавить в плейлисты': 'Failed to add to playlists',
    'Добавлено ✓': 'Added ✓',
    'Добавление...': 'Adding...',
    'Буклет PDF': 'Booklet PDF',
    'БУКЛЕТ PDF': 'BOOKLET PDF',
    'Загрузка треков...': 'Loading tracks...',
    'Загрузка через буфер AMR…': 'Loading via AMR Buffer…',
    'Загрузка треков альбома...': 'Loading album tracks...',
    'Нет треков': 'No tracks',
    'Плейлист пуст': 'Playlist is empty',
    'Подборка лучших': 'Top Picks',
    'Еженедельные миксы': 'Personal Mixes',
    'Новинки и альбомы': 'New Releases & Albums',
    'Станции для вас': 'Stations for You',
    'Вы недавно слушали': 'Recently Played',
    'Жанры и категории': 'Genres & Moods',
    'Для вас': 'Made for You',
    'Рекомендации': 'Recommendations',
    'ИСТОРИЯ': 'HISTORY',
    'Недавно прослушанные треки': 'Recently Played Tracks',
    'Нет недавних треков': 'No recent tracks',
    'Загрузка миксов...': 'Loading mixes...',
    'Загрузка альбомов...': 'Loading albums...',
    'Загрузка станций...': 'Loading stations...',
    'Нет данных по альбомам': 'No albums available',
    'Моя станция': 'My Station',
    'МОЯ СТАНЦИЯ': 'MY STATION',
    'Станция открытий': 'Discovery Station',
    'СТАНЦИЯ ОТКРЫТИЙ': 'DISCOVERY STATION',
    'В моем вкусе': 'Favorites Mix',
    'В моём вкусе': 'Favorites Mix',
    'В МОЁМ ВКУСЕ': 'FAVORITES MIX',
    'СЕЙЧАС НА ПОВТОРЕ': 'HEAVY ROTATION',
    'НОВИНКИ ДЛЯ ВАС': 'NEW MUSIC MIX',
    'ЧИЛЛ-МИКС': 'CHILL MIX',
    'ДРАЙВ-МИКС': 'GET UP! MIX',
    'МИКС ДЛЯ ДРУЗЕЙ': 'FRIENDS MIX',
    'РАДИОСТАНЦИЯ ПО АРТИСТУ': 'ARTIST STATION',
    'Персональная радиостанция': 'Personal Radio Station',
    'Специально для вас': 'Made for You',
    'Новые треки под ваш вкус': 'New music tailored to your taste',
    'Радиостанция': 'Radio Station',
    'Плейлист медиатеки': 'Library Playlist',
    'Топ-альбом': 'Top Album',
    'Главные мировые релизы': 'Global Premieres & Shows',
    'Культовые хиты': 'Essential Hits',
    'Современное кантри': 'Modern Country',
    'Спокойный ритм и фоновые биты': 'Relaxing beats & ambient grooves',
    'Популярные поп-треки': 'Chart-topping pop anthems',
    'Клубный драйв и энергия': 'Club & festival energy',
    'Глубокий атмосферный грув': 'Deep atmospheric groove',
    'Классика мирового рока': 'Timeless rock legends',
    '🔥 Поп-музыка': '🔥 Pop',
    '🎸 Рок & Альтернатива': '🎸 Rock & Alternative',
    '🎤 Хип-хоп & Рэп': '🎤 Hip-Hop & Rap',
    '⚡ Электроника & Dance': '⚡ Dance & Electronic',
    '🎻 Неоклассика': '🎻 Neoclassical',
    '🎬 Саундтреки': '🎬 Soundtracks',
    'Поиск в Apple Music...': 'Search Apple Music...',
    'Все': 'All',
    'Песни': 'Songs',
    'Альбомы': 'Albums',
    'Артисты': 'Artists',
    'ПЕСНИ': 'SONGS',
    'АЛЬБОМЫ': 'ALBUMS',
    'ПЛЕЙЛИСТЫ': 'PLAYLISTS',
    'ИСПОЛНИТЕЛИ': 'ARTISTS',
    'Ищите любимые треки, альбомы и исполнителей': 'Search for songs, albums, playlists, and artists',
    'Поиск в каталоге Apple Music...': 'Searching Apple Music catalog...',
    'Ничего не найдено': 'No results found',
    'Загрузить ещё': 'Load More',
    'Не играет': 'Not Playing',
    'Действия с треком': 'Track Actions',
    'Перейти к альбому': 'Go to Album',
    'Не указан': 'Unknown Album',
    'Цифровой буклет (PDF)': 'Digital Booklet (PDF)',
    'Официальный буклет альбома Apple Music': 'Official Apple Music Digital Booklet',
    'Создать радио по треку': 'Create Station from Track',
    'Создать радио по исполнителю': 'Create Station from Artist',
    'Избранное': 'Favorite',
    'В избранное': 'Add to Favorites',
    'Ещё': 'More',
    'Случайно': 'Shuffle',
    'Предыдущий': 'Previous',
    'Предыдущий трек': 'Previous Track',
    'Воспроизвести': 'Play',
    'Воспроизведение': 'Play / Pause',
    'Воспроизведение / Пауза': 'Play / Pause',
    'Следующий': 'Next',
    'Следующий трек': 'Next Track',
    'Повтор': 'Repeat',
    'Режим повтора': 'Repeat Mode',
    'Режим повтора (Выкл / Очередь / 1 трек)': 'Repeat Mode (Off / Queue / One Track)',
    'Зациклить текущий трек': 'Loop Current Track',
    'Бесконечный повтор одного трека (Выкл)': 'Infinite single-track loop (Off)',
    'Бесконечный повтор одного трека (Активен)': 'Infinite single-track loop (Active)',
    'Динамический диапазон мастеринга (TT DR / EBU R128)': 'Mastering Dynamic Range (TT DR / EBU R128)',
    'МАСТЕРИНГ И ДИНАМИКА • EBU R128 / TT DR': 'MASTERING & DYNAMICS • EBU R128 / TT DR',
    'DR АНАЛИЗ...': 'DR ANALYZING...',
    'Анализ динамического диапазона...': 'Analyzing dynamic range...',
    'Диапазон LRA': 'LRA Range',
    'Фазовый коррелометр стереопанорамы': 'Stereo Phase Correlation Meter',
    '-1.0 Противофаза': '-1.0 Out of Phase',
    '0.0 Стерео': '0.0 Wide Stereo',
    '+1.0 Моно': '+1.0 Mono',
    'Накопление 3-секундных блоков PCM для расчёта официального индекса TT Dynamic Range и громкости ITU-R BS.1770-4.': 'Accumulating 3-second PCM windows for official TT Dynamic Range and ITU-R BS.1770-4 loudness.',
    'Отключить звук': 'Mute',
    'Без звука': 'Mute',
    'Громкость': 'Volume',
    'Позиция трека': 'Track Position',
    'Развернуть проигрыватель': 'Expand Player',
    'Закрыть': 'Close',
    'Очистить': 'Clear',
    'Назад к главной': 'Back to Home',
    'Параметры потока и ЦАП': 'Signal Path & DAC Settings',
    'Инспектор аудиопотока и спектральный верификатор': 'Signal Path & Spectral Verifier',
    'Статус спектрального верификатора vDSP FFT': 'vDSP FFT Spectral Verifier Status',
    'Тракт сигнала': 'Signal Path',
    'Частота ЦАП аппаратно синхронизирована с потоком. Деградация разрядности исключена.': 'DAC sample rate is hardware-locked to the stream. Zero bit-depth degradation.',
    'ИСТОЧНИК': 'SOURCE',
    'АУДИОДВИЖОК': 'AUDIO ENGINE',
    'ВЫХОДНОЙ ЦАП': 'OUTPUT DAC',
    'УСИЛИТЕЛЬ': 'AMPLIFIER',
    'В плейлист': 'Save as Playlist',
    'Сохранить очередь в плейлист Apple Music': 'Save queue as Apple Music playlist',
    'СЕТЕВОЙ СТРИМЕР': 'NETWORK STREAMER',
    'СЕТЕВОЙ ЦАП': 'NETWORK DAC',
    'ЦАП': 'DAC',
    'Сменить устройство вывода': 'Change Output Device',
    'Аудиовыход': 'Audio Output',
    'Аудиовыход macOS': 'macOS Audio Output',
    'Прямое подключение macOS CoreAudio': 'Direct macOS CoreAudio Output',
    'Bit-Perfect 100% Lock • Zero DSP • Bypass микшера': 'Bit-Perfect 100% Lock • Zero DSP • Mixer Bypass',
    'СПЕКТРАЛЬНЫЙ ВЕРИФИКАТОР • vDSP FFT': 'SPECTRAL VERIFIER • vDSP FFT',
    'FFT АНАЛИЗ...': 'FFT ANALYZING...',
    'Полоса ВЧ': 'HF Bandwidth',
    'Ультразвук (>22k)': 'Ultrasonic (>22k)',
    'Разрядность LSB': 'LSB Bit Depth',
    '24-бит (Честный)': '24-bit (True LSB)',
    '24-бит (Честный LSB)': '24-bit (True LSB)',
    'Подлинный студийный Hi-Res мастер: зафиксирована живая ультразвуковая составляющая и активность всех 24 бит.': 'Authentic studio Hi-Res master: live ultrasonic energy and active 24-bit LSB verified.',
    'Аудиоустройства вывода': 'Audio Output Devices',
    'Выберите активный ЦАП, аудиовыход macOS или сетевой стример': 'Select active DAC, macOS output, or network streamer',
    'Загрузка устройств...': 'Loading devices...',
    'Нет доступных аудиоустройств': 'No audio devices available',
    'DLNA Стример': 'DLNA Streamer',
    'Активен': 'Active',
    'Выбрать': 'Select',
    'СИНХРОНИЗИРОВАНО': 'SYNCHRONIZED',
    'ТРЕБУЕТСЯ ВХОД': 'SIGN IN REQUIRED',
    'Требуется вход': 'Sign in required',
    'Синхронизировано': 'Synchronized',
    'Диагностика': 'Diagnostics',
    'Диагностика аккаунта': 'Account Diagnostics',
    'Apple ID & Медиатека': 'Apple ID & Library',
    'Учетная запись Mac:': 'Mac Account:',
    'Статус синхронизации:': 'Sync Status:',
    'Синхронизировано с Mac': 'Synchronized with Mac',
    'Не синхронизировано': 'Not Synchronized',
    'Проверка...': 'Checking...',
    'Регион Apple Music:': 'Apple Music Storefront:',
    'Подписка Apple Music:': 'Apple Music Subscription:',
    'Активна': 'Active',
    'Не активна': 'Inactive',
    'Проверить заново': 'Check Again',
    'Готово': 'Done',
    'Подключите Apple ID': 'Connect Apple ID',
    'Для работы с каталогом, воспроизведения очередей в iCloud и персональных рекомендаций требуется авторизация в Apple Music.': 'Sign in to Apple Music to browse the catalog, sync iCloud playback queues, and access personal recommendations.',
    'Bit-Perfect звук в исходном качестве (ALAC / Hi-Res)': 'Bit-Perfect audio in native resolution (ALAC / Hi-Res)',
    'Синхронизация результатов поиска в iCloud-очереди': 'Seamless iCloud playback queue synchronization',
    'Персональная «Моя станция» и музыкальные открытия': 'Personal "My Station" and Discovery mixes',
    'Войти через Apple ID': 'Sign In with Apple ID',
    'Инициализация MusicKit...': 'Initializing MusicKit...',
    'Получение ключа разработчика...': 'Fetching developer token...',
    'Ожидание авторизации Apple ID...': 'Waiting for Apple ID sign-in...',
    'Загрузка MusicKit.js... Повторите через 2 секунды': 'Loading MusicKit.js... Try again in 2 seconds',
    '✦ ЖИВАЯ ОБЛОЖКА': '✦ MOTION ARTWORK',
    'Медиатека и станции': 'Library & Stations',
    'Станции, персональные миксы и плейлисты': 'Stations, personal mixes & playlists',
    'Закрыть медиатеку': 'Close Library',
    'Выйти из StandBy / TV Mode (Esc)': 'Exit StandBy / TV Mode (Esc)',
    'Закрыть StandBy Mode': 'Close StandBy Mode',
    'WLED Подсветка': 'WLED Ambilight',
    'Режим работы': 'Lighting Mode',
    'Режим работы WLED DDP': 'WLED DDP Lighting Mode',
    'Настройки WLED DDP': 'WLED DDP Settings',
    'Настройки WLED DDP Ambilight': 'WLED DDP Ambilight Settings',
    'Режим подсветки WLED DDP': 'WLED DDP Lighting Mode',
    'Без подсветки': 'Off',
    'Синусоида ритма (стоячая волна)': 'Rhythm Sine Wave',
    'Синусоида ритма (контрастная волна от центра)': 'Rhythm Sine Wave (Center Contrast)',
    'Спектральный эквалайзер (Бас · Вокал · Верх)': 'Spectral Equalizer (Bass · Mids · Highs)',
    'Симметричный пульс (раскрытие от центра)': 'Symmetric Center VU Pulse',
    'Ударная волна (кольца бита от центра)': 'Shockwave (Beat Rings from Center)',
    'Гармонический резонанс (волны цвета от центра)': 'Harmonic Resonance (Center Color Waves)',
    'Сверхновая (ядро бита и корона от центра)': 'Supernova (Core Flash & Corona)',
    'Призма от центра (перелив оттенков обложки)': 'Center Prism (Flowing Cover Hues)',
    'Встречный импульс (бас в центре · верх с краёв)': 'Counter-Pulse (Center Bass · Edge Highs)',
    'Живой Ambilight (16 зон + пульс музыки)': 'Live Ambilight (16 Zones + Audio Pulse)',
    'Гармонический резонанс (цвет + мелодия)': 'Harmonic Resonance (Color + Melody)',
    'Статичная палитра обложки': 'Static Artwork Palette',
    'Цифровой буклет альбома': 'Digital Album Booklet',
    'Открыть цифровой буклет альбома (PDF)': 'Open Digital Album Booklet (PDF)',
    'Открыть цифровой буклет альбома Apple Music (PDF)': 'Open Apple Music Digital Booklet (PDF)',
    'Закрыть буклет (Esc)': 'Close Booklet (Esc)',
    'Закрыть буклет': 'Close Booklet',
    'Загрузка буклета...': 'Loading booklet...',
    'О версии и настройки устройства': 'Version Info & Device Settings',
    'Система и Устройство': 'System & Device',
    'Авторизованный клиент • Bit-Perfect CoreAudio • vDSP FFT': 'Authorized Client • Bit-Perfect CoreAudio • vDSP FFT',
    'СБОРКА': 'BUILD',
    'УСТРОЙСТВО': 'DEVICE',
    'ЭКРАН БЛОКИРОВКИ • MEDIASESSION': 'LOCK SCREEN • MEDIASESSION',
    'АКТИВНО': 'ACTIVE',
    'ОТКЛЮЧЕНО': 'DISABLED',
    'Сборка': 'Build',
    'Устройство': 'Device',
    'Имя этого устройства': 'This Device Name',
    'Имя устройства': 'Device Name',
    'Экран блокировки и Dynamic Island': 'Lock Screen & Dynamic Island',
    'Управление плеером на заблокированном экране, в Пункте управления и на Apple Watch': 'Player controls on the Lock Screen, Control Center, and Apple Watch',
    'Ожидание авторизации на Mac': 'Waiting for Authorization on Mac',
    'Ожидание авторизации устройства': 'Waiting for Device Authorization',
    'Код устройства': 'Device Code',
    'Экран блокировки включён': 'Lock Screen controls enabled',
    'Экран блокировки выключен': 'Lock Screen controls disabled',
    'Имя устройства сохранено': 'Device name saved',
    'Поделиться доступом': 'Share Access',
    'Скрыть QR-код': 'Hide QR Code',
    'Скопировать ссылку': 'Copy Link',
    'Отправить...': 'Share...',
    'Ссылка для подключения скопирована': 'Connection link copied',
    'Отсканируйте камерой смартфона или планшета — устройство подключится и авторизуется автоматически': 'Scan with a phone or tablet camera — the device will connect and authorize automatically',
    'QR-код для быстрого подключения и авторизации': 'QR code for instant connection and authorization',
    '✨ AI Подбор': '✨ AI Curator',
    'ИИ Подбор': 'AI Curator',
    'ИИ Подбор по атмосфере': 'AI Mood Curator',
    'ИИ Подбор по атмосфере (Apple Neural Engine)': 'AI Mood Curator (Apple Neural Engine)',
    'Закрыть ИИ Подбор': 'Close AI Curator',
    'Нажмите на тег для мгновенного воспроизведения • Листайте вниз для бесконечной подгрузки': 'Tap any tag to play immediately • Scroll down for infinite loading',
    'Подгрузить ещё варианты ↓': 'Load more ideas ↓',
    'Другие варианты': 'Other suggestions',
    'Сгенерировать другие варианты промптов': 'Generate other prompt ideas',
    'Введите название песни, альбома, плейлиста или артиста': 'Enter a song, album, playlist, or artist',
    'Умный семантический поиск и Промпт-Куратор': 'Smart Semantic Search & Prompt Curator',
    'Опишите настроение, звуковую сцену, эпоху или инструменты свободным текстом — нативный движок macOS соберёт готовую аудиофильскую очередь из каталога Apple Music.': 'Describe a mood, soundstage, era, or instruments in free text — the native macOS engine will assemble a ready-to-play audiophile queue from Apple Music.',
    '🎷 Ночной нуар-джаз с саксофоном': '🎷 Late-night noir jazz with sax',
    '🎸 Аналоговый прог-рок 70-х': '🎸 70s analog progressive rock',
    '🎹 Эмбиент и пианино для фокуса': '🎹 Deep ambient & piano for focus',
    '🎙️ Эталонный вокал и акустика': '🎙️ Reference vocals & acoustics',
    '🌃 Кинематографичный синтвейв 80-х': '🌃 Cinematic 80s synthwave',
    '🔊 Бристольский трип-хоп и даунтемпо': '🔊 Bristol trip-hop & downtempo',
    '🎻 Камерные струнные и виолончель': '🎻 Chamber strings & live cello',
    '🌊 Дрим-поп и воздушный шугейз': '🌊 Dream-pop & airy shoegaze',
    '🥃 Классический блюз-рок на лампе': '🥃 Tube-driven blues rock',
    '🎺 Джаз-фанк и винтажный Rhodes': '🎺 Jazz-funk & vintage Rhodes',
    '🌌 Космическая электроника (Берлин)': '🌌 Berlin school cosmic synth',
    '☕ Босса-нова и акустика 60-х': '☕ 60s bossa nova & nylon guitar',
    '🥁 Сложный мат-рок и полиритмия': '🥁 Math-rock & odd-meter drums',
    '🕯️ Дарк-джаз и кинематографичный нуар': '🕯️ Dark jazz & cinematic noir',
    '🎛️ Минимал-техно и даб-аккорды': '🎛️ Dub techno & deep sub-bass',
    '🪕 Инди-фолк и камерная акустика': '🪕 Indie folk & warm acoustics',
    '🎼 Симфонические саундтреки': '🎼 Epic orchestral soundtracks',
    '🪩 Японский сити-поп 80-х': '🪩 80s Japanese city pop & funk',
    'Опишите настроение, сцену или инструменты...': 'Describe mood, soundstage, or instruments...',
    'Подбор нативным ИИ (Apple Neural Engine)...': 'Curating with on-device AI (Apple Neural Engine)...',
    'Слушать подборку': 'Play Session',
    'ПЕСНИ ПОДБОРКИ': 'CURATED TRACKS',
    'РЕКОМЕНДОВАННЫЕ АЛЬБОМЫ': 'RECOMMENDED ALBUMS',
    'Собрать AI-подборку': 'Build AI Session',
    'Нет связи с Mac': 'Disconnected from Mac',
    'Попытка автоматического переподключения к Apple Music...': 'Attempting to reconnect to Apple Music...',
    'Переподключиться': 'Reconnect',
    'Загрузка...': 'Loading...',
    'Запуск трека...': 'Starting track...',
    'Запуск альбома...': 'Starting album...',
    'Запуск плейлиста...': 'Starting playlist...',
    'Перемешивание...': 'Shuffling...',
    'Перемешивание альбома...': 'Shuffling album...',
    'Запуск станции...': 'Starting station...',
    'Подключение к станции...': 'Connecting to station...',
    'Переход к треку...': 'Switching track...',
    'Запуск результатов...': 'Playing search results...',
    'Воспроизведение...': 'Playing...',
    'Синхронизация очереди в Apple Music (~10 сек)...': 'Syncing queue in Apple Music (~10s)...',
    '★ Добавлено в избранное': '★ Added to Favorites',
    '☆ Удалено из избранного': '☆ Removed from Favorites',
    '★ Альбом добавлен в медиатеку Apple Music': '★ Album added to Apple Music Library',
    '★ Плейлист добавлен в медиатеку Apple Music': '★ Playlist added to Apple Music Library',
    'Плейлист добавлен в медиатеку Apple Music': 'Playlist added to Apple Music Library',
    'Не удалось добавить в медиатеку': 'Could not add to Library',
    'У текущего трека нет буклета Apple Music': 'No Digital Booklet for current track',
    'Для этого альбома нет официального буклета в Apple Music': 'No official Digital Booklet available for this album',
    'Не удалось загрузить цифровой буклет Apple Music': 'Failed to load Apple Music Digital Booklet',
    'Обнаружен апскейл Lossy (128 → 256 kbps)': 'Lossy Upscale Detected (128 → 256 kbps)',
    'Обнаружен транскод из Lossy (MP3 / AAC)': 'Lossy Transcode Detected (MP3 / AAC)',
    'Обнаружен апсемплинг (Fake Hi-Res)': 'Upsampling Detected (Fake Hi-Res)',
    'Zero-Padded контейнер (16-бит в 24-бит)': 'Zero-Padded Container (16-bit in 24-bit)',
    'Честный AAC 256 kbps': 'Authentic AAC 256 kbps',
    'Сжатый поток AAC 256 kbps': 'Compressed AAC 256 kbps Stream',
    'Спектральный анализ потока...': 'Analyzing stream spectrum...',
    'Ожидание воспроизведения...': 'Waiting for playback...',
    'Спектральный анализ отключен': 'Spectral analysis disabled',
    'Синхронизировано': 'Synced',
    'Устройство не активно': 'Device Inactive',
    'Перетащить трек': 'Drag track',
    'Закрепить / открепить вайб': 'Pin / unpin vibe',
    'Выйти': 'Sign Out',
    'Не синхронизировано с Mac': 'Not synced with Mac',
    'Не удалось авторизовать Apple Music (MusicKit JS недоступен). Проверьте блокировщики рекламы.': 'Could not authorize Apple Music (MusicKit JS unavailable). Check content blockers.',
    'Воспроизведение не началось — проверьте авторизацию Apple Music на Mac': 'Playback did not start — check Apple Music authorization on Mac',
    'Плейлисты в медиатеке не найдены': 'No playlists found in library',
    'Станции временно недоступны': 'Stations temporarily unavailable',
    'Альбомы временно недоступны': 'Albums temporarily unavailable',
    'Станция недоступна для запуска': 'Station unavailable for playback',
    'ИИ-подбор завершён, но треки не найдены. Попробуйте другой запрос': 'AI curation finished, but no tracks were found. Try another prompt',
    'Не удалось сгенерировать ИИ-подборку': 'Failed to generate AI mix',
    'Для этого трека нет синхронизированного текста в Apple Music': 'No synced lyrics available for this track in Apple Music',
    'Синхронизация по времени недоступна — показан полный текст': 'Time-synced lyrics unavailable — showing full lyrics',
    'Не удалось загрузить текст песни': 'Failed to load lyrics',
    'Очередь обновлена': 'Queue updated',
    '★ Вайб закреплён': '★ Vibe pinned',
    '☆ Вайб откреплён': '☆ Vibe unpinned',
    'Обновлены идеи ИИ-подбора': 'AI prompt ideas refreshed',
    'Сгенерированы новые идеи': 'New prompt ideas generated',
    'На репите': 'Heavy Rotation',
    'Бесконечная волна 20+ треков по атмосфере': 'Endless wave of 20+ tracks matching the vibe',
    'ИИ-волна по треку': 'AI Track Vibe',
    'Сначала запустите трек для ИИ-подбора по вайбу': 'Start a track first to curate an AI vibe mix',
    'Не удалось подобрать треки по запросу': 'No matching tracks found',
    'AI-Подборка': 'AI Sonic Selection',
    '★ В избранном': '★ Pinned',
    '☆ Закрепить вайб': '☆ Pin Vibe',
    'Очередь пуста': 'Queue is empty',
    'История пуста': 'History is empty',
    'История': 'History',
    'Очередь AMR': 'AMR Queue',
    '★ Очередь сохранена в плейлисты Apple Music': '★ Queue saved to Apple Music playlists',
    'Не удалось сохранить очередь в плейлист': 'Could not save queue as playlist',
    'Ошибка выполнения команды': 'Command execution failed',
    'Не удалось загрузить треки': 'Failed to load tracks',
    'Неизвестный исполнитель': 'Unknown Artist',
    'Прямой эфир Apple Music': 'Apple Music Live Radio',
    'Персональная станция': 'Personal Station',
    'Еженедельный микс': 'Weekly Mix',
    'Недавно прослушано': 'Recently Played',
    'Нет элементов для отображения': 'No items to display',
    'Поделиться': 'Share',
    'Пресет DSP': 'DSP Preset',
    'Пользовательский режим': 'Custom Configuration',
    'Bit-Perfect Passthrough (Выкл)': 'Bit-Perfect Passthrough (Off)',
    'Прямая побитовая передача PCM без оверсэмплинга и модуляции': 'Direct bit-perfect PCM output without oversampling or modulation',
    'SACD Эталон (DSD256 • 7EC-Balanced)': 'SACD Reference (DSD256 • 7EC-Balanced)',
    'Макс. сцена и воздух (DSD256 • 7EC-Super • Metal)': 'Max Stage & Air (DSD256 • 7EC-Super • Metal)',
    'Атака и драйв (DSD128 • 7EC-Transient)': 'Attack & Drive (DSD128 • 7EC-Transient)',
    'Оптика / Коаксиал S/PDIF (DSD64 DoP)': 'Optical / Coax S/PDIF (DSD64 DoP)',
    'Мультибит / R2R (HQ PCM NOS • LNS15)': 'Multibit / R2R (HQ PCM NOS • LNS15)',
    'Локальный USB DSP приостановлен: активен сетевой Bit-Perfect PCM поток (DLNA / BluOS)': 'Local USB DSP paused: Bit-Perfect network PCM stream active (DLNA / BluOS)',
    '🌙 Ночной режим (DRC)': '🌙 Late-Night Mode (DRC)',
    'Включить или выключить ночной режим (Late-Night DRC)': 'Enable or disable Late-Night Mode (DRC)',
    'Профиль ночного режима (DRC)': 'Late-Night Mode (DRC) Profile',
    'Выкл (100% Bit-Perfect)': 'Off (100% Bit-Perfect)',
    'Деликатный — Джаз / Вокал (до +6 дБ)': 'Gentle — Jazz / Vocal (up to +6 dB)',
    'Ночной концерт — Симфония / OST (до +9.5 дБ)': 'Night Concert — Symphony / OST (up to +9.5 dB)',
    'Деликатный (Джаз / Вокал)': 'Gentle (Jazz / Vocal)',
    'Ночной концерт (Симфония / OST)': 'Night Concert (Symphony / OST)',
    'Прямой 100% Bit-Perfect тракт без динамической обработки сигнала.': 'Direct 100% Bit-Perfect signal path with zero dynamic processing.',
    'Мягкий подъём тихих деталей (до +6 дБ) с гейтом шума -63 dBFS для джаза, вокала и акустики.': 'Gentle micro-detail lift (up to +6 dB) with -63 dBFS noise-floor gate for jazz, vocals & acoustic.',
    'Глубокий контроль оркестровых пианиссимо и тутти (до +9.5 дБ, -1.0 dBTP) для классики и саундтреков.': 'Deep symphonic pianissimo lift & crescendo control (up to +9.5 dB, -1.0 dBTP) for classical & OST.',
    'Sonic Bridge от этого трека': 'Sonic Bridge from This Track',
    'Плавный ИИ-маршрут к другому треку или артисту': 'Smooth AI trajectory to another track or artist',
    'Точка А (откуда)': 'Point A (Origin)',
    'Точка Б (куда)': 'Point B (Destination)',
    '🎵 Текущий трек': '🎵 Current Track',
    'Длина маршрута:': 'Route Steps:',
    'Построить маршрут': 'Build Route',
    'Сразу включить': 'Play Immediately',
    'Запустить маршрут': 'Play Bridge Route',
    'МАРШРУТ ПЕРЕХОДА': 'SONIC BRIDGE TRAJECTORY',
    'Альбомы': 'Albums',
    'Плейлисты': 'Playlists',
    'Медиатека': 'Library',
    'Плейлисты и альбомы': 'Playlists & Albums',
    'Альбомы в медиатеке': 'Albums in Library',
    'Плейлисты в медиатеке': 'Playlists in Library',
    'Раздел медиатеки': 'Library Section',
    'Загрузка альбомов...': 'Loading albums...',
    'Альбомы в медиатеке не найдены': 'No albums found in library',
    'Станции, персональные миксы, плейлисты и альбомы': 'Stations, Personal Mixes, Playlists & Albums',
    'Главная': 'Home',
    'Поиск': 'Search',
    'Плеер': 'Player',
    'Плейлисты Apple Music': 'Apple Music Playlists',
    'Обновить плейлисты': 'Refresh playlists',
    'Обновить медиатеку': 'Refresh library',
    'Недавние': 'Recent',
    'Треки': 'Songs',
    'Недавно добавленные': 'Recently Added',
    'НЕДАВНО ДОБАВЛЕННЫЕ АЛЬБОМЫ': 'RECENTLY ADDED ALBUMS',
    'НЕДАВНО ДОБАВЛЕННЫЕ ТРЕКИ': 'RECENTLY ADDED SONGS',
    'Недавние в медиатеке': 'Recently Added in Library',
    'Треки медиатеки': 'Library Songs',
    'В медиатеке пока нет недавно добавленных альбомов и треков': 'No recently added albums or songs in your library',
    'Поиск по артистам медиатеки...': 'Filter library artists...',
    'Фильтр треков медиатеки...': 'Filter library songs...',
    'Исполнители в медиатеке': 'Artists in Library',
    'Исполнители в медиатеке не найдены': 'No artists found in library',
    'Треки в медиатеке': 'Songs in Library',
    'Треки в медиатеке не найдены': 'No songs found in library',
    'Загрузка недавних...': 'Loading recently added...',
    'Загрузка артистов...': 'Loading artists...',
    'Загрузка треков медиатеки...': 'Loading library songs...',
    'Загрузка медиатеки артиста...': 'Loading artist library...',
    'ИСПОЛНИТЕЛЬ В МЕДИАТЕКЕ': 'ARTIST IN LIBRARY',
    'АЛЬБОМЫ В МЕДИАТЕКЕ': 'ALBUMS IN LIBRARY',
    'ТРЕКИ В МЕДИАТЕКЕ': 'SONGS IN LIBRARY',
    'В медиатеке целиком': 'Complete in Library',
    '✓ В медиатеке': '✓ In Library',
    'Добавить весь альбом': 'Add Complete Album',
    '+ Дополнить альбом': '+ Complete Album',
    'Из медиатеки': 'Remove',
    'Удалить из медиатеки': 'Remove from Library',
    'Удалить из медиатеки Apple Music': 'Remove from Apple Music Library',
    'Удалить трек из медиатеки': 'Remove Song from Library',
    'Добавить трек в медиатеку': 'Add Song to Library',
    'Сохранить композицию в Apple Music': 'Save song to Apple Music Library',
    'Удалить альбом из медиатеки': 'Remove Album from Library',
    'Удалить исполнителя из медиатеки': 'Remove Artist from Library',
    'Перейти к артисту в медиатеке': 'Go to Artist in Library',
    'Удалить из медиатеки?': 'Remove from Library?',
    'Удалить альбом из медиатеки?': 'Remove Album from Library?',
    'Удалить исполнителя из медиатеки?': 'Remove Artist from Library?',
    'Удалить трек из медиатеки?': 'Remove Song from Library?',
    'Удалить плейлист': 'Delete Playlist',
    'Удалить плейлист?': 'Delete Playlist?',
    'Удалить плейлист из медиатеки': 'Delete Playlist',
    'Элемент будет удалён из вашей медиатеки Apple Music.': 'This item will be removed from your Apple Music Library.',
    'Отмена': 'Cancel',
    'Удалить': 'Remove',
    'Удаление...': 'Removing...',
    'Показать ещё': 'Show More',
    'Все плашки скрыты в настройках Mac (Основные → ТВ-режим)': 'All tiles are hidden in Mac Settings (General → TV Mode)',
    '★ Трек добавлен в медиатеку Apple Music': '★ Song added to Apple Music Library',
    'Музыка': 'Music',
    'МЕДИАТЕКА': 'LIBRARY',
    'Любимые песни': 'Favorite Songs',
    'Сейчас на повторе': 'Heavy Rotation Mix',
    'Микс': 'Mix',
    'Радио': 'Radio',
    'Комната': 'Room',
    'АЧХ': 'Room EQ',
    'Событие': 'Featured',
    'Трек': 'Track',
    'Усилитель': 'Amplifier',
    'Результаты поиска': 'Search Results',
    'Обложка': 'Artwork',
    'Обложка трека': 'Track Artwork',
    'Обложка плейлиста': 'Playlist Artwork',
    'Буклет альбома': 'Album Booklet',
    'Регулировка громкости': 'Volume Control',
    'Без звука (Mute)': 'Mute',
    'Полноэкранный режим StandBy / TV с живыми обложками': 'Full-screen StandBy / TV Mode with Motion Artwork',
    'Авторизовано на Mac • Защищённый UID (Cookie + Cache)': 'Authorized on Mac • Protected UID (Cookie + Cache)',
    'ИИ-подбор по треку': 'AI Mix from Track',
    'ИИ-подбор по вайбу трека': 'AI Vibe Mix from Track',
    'ИИ-подбор по вайбу текущего трека': 'AI Vibe Mix from Current Track',
    '✨ ИИ-подбор по вайбу текущего трека': '✨ AI Vibe Mix from Current Track',
    'Семантическая волна Apple Neural Engine': 'Semantic wave via Apple Neural Engine',
    'ИЗБРАННЫЕ ВАЙБЫ': 'PINNED VIBES',
    'Удалено из избранных вайбов': 'Removed from pinned vibes',
    '★ Вайб закреплён в избранном': '★ Vibe pinned to favorites',
    'Нативные функции ИИ отключены в настройках Mac': 'On-device AI features are disabled in Mac Settings',
    'AI-куратор отключён в настройках Mac': 'AI Curator is disabled in Mac Settings',
    'Не удалось построить маршрут Sonic Bridge': 'Could not build Sonic Bridge route',
    'Не удалось построить маршрут: подходящие треки не найдены': 'Could not build route: no matching tracks found',
    'Автосинхронизация CoreAudio': 'CoreAudio Auto-Sync',
    'Сетевой вывод BluOS / DLNA (Bit-Perfect PCM • 100%)': 'BluOS / DLNA Network Output (Bit-Perfect PCM • 100%)',
    'Прямой вывод CoreAudio (Bit-Perfect DAC • 100%)': 'Direct CoreAudio Output (Bit-Perfect DAC • 100%)',
    'Сетевой вывод BluOS / DLNA (Bit-Perfect PCM 100% • Аппаратная громкость плеера)': 'BluOS / DLNA Network Output (Bit-Perfect PCM 100% • Hardware Player Volume)',
    'Прямой вывод CoreAudio (Регулируемая громкость)': 'Direct CoreAudio Output (Variable Volume)',
    'Сетевой Hi-Res стриминг': 'Network Hi-Res Streaming',
    'Сетевой Lossless стриминг': 'Network Lossless Streaming',
    'Чистый оригинал (Bit-Perfect Passthrough)': 'Pure Original (Bit-Perfect Passthrough)',
    'Реставратор клиппинга (De-Clipper)': 'Clipping Restorer (De-Clipper)',
    '⚡️ Реставратор клиппинга (De-Clipper)': '⚡️ Mastering De-Clipper',
    'Авто — Умная защита (DR ≤ 10)': 'Auto — Smart Guard (DR ≤ 10)',
    'Деликатный (до +2.8 дБ пиков)': 'Gentle (up to +2.8 dB peaks)',
    'Студийная реставрация (до +4.2 дБ)': 'Studio Restoration (up to +4.2 dB)',
    'Прямой 100% Bit-Perfect тракт без реконструкции срезанных верхушек волны.': '100% Bit-Perfect passthrough without waveform peak reconstruction.',
    'Де-эссер (Weiss De-Esser)': 'Weiss Dynamic De-Esser',
    '💎 Де-эссер (Weiss De-Esser)': '💎 Weiss Dynamic De-Esser',
    'Деликатный — Планары / Яркий ВЧ (до -3.5 дБ)': 'Gentle — Planars / Bright HF (up to -3.5 dB)',
    'Студийный Weiss — Резкий вокал (до -6.0 дБ)': 'Studio Weiss — Harsh Vocals (up to -6.0 dB)',
    'Прямой 100% Bit-Perfect тракт без динамического подавления сибилянтов.': '100% Bit-Perfect passthrough without high-frequency dynamic sibilance control.',
    'Ночной режим (DRC)': 'Late-Night Mode (DRC)',
    'АЧХ КОМНАТЫ • AUTO-PEQ 64-BIT • CLOUD': 'ROOM EQ • AUTO-PEQ 64-BIT • CLOUD',
    'Включить или выключить коррекцию комнаты': 'Enable or disable Room Acoustic Correction',
    'Профиль АЧХ комнаты': 'Room Acoustic Profile',
    'Удалить выбранный профиль АЧХ': 'Delete selected Room EQ profile',
    'Удалить профиль АЧХ': 'Delete Room EQ Profile',
    'График АЧХ комнаты': 'Room Frequency Response Graph',
    'Нативная запись микрофоном iPhone / iPad (работает по LAN HTTP без HTTPS)': 'Native iPhone / iPad microphone capture (works over LAN HTTP without HTTPS)',
    'RTA спектр аудиосигнала': 'Real-Time Audio Spectrum (RTA)',
    'Фазовая корреляция стереосигнала от -1 до +1': 'Stereo Phase Correlation (-1 to +1)',
    'ВЫКЛ': 'OFF',
    'Выкл': 'Off',
    'ВКЛ': 'ON',
    'Вкл': 'On',
    'Нет профилей замера': 'No room profiles yet',
    'Целевая': 'Target',
    'Целевая Harman': 'Harman Target',
    'Замер микрофона': 'Mic Measurement',
    'С коррекцией Auto-PEQ': 'Auto-PEQ Corrected',
    'Калибровочный розовый шум...': 'Calibration pink noise...',
    'Быстрый замер микрофоном': 'Measure Room Mic',
    'Замер микрофоном iPhone / iPad': 'Measure via iPhone / iPad Mic',
    'Запись iOS': 'iOS Mic Capture',
    'Стоп': 'Stop',
    'Быстрое измерение АЧХ комнаты отключено для этого устройства в системных настройках Mac.': 'Quick Room EQ measurement is disabled for this device in Mac Settings.',
    'Быстрое измерение АЧХ отключено для этого устройства в настройках Mac': 'Quick Room EQ measurement is disabled for this device in Mac Settings',
    'Сядьте в точку прослушивания с iPhone / iPad: Mac подаст эталонный розовый шум на АС и построит 64-bit Auto-PEQ фильтр с синхронизацией в iCloud.': 'Sit at your listening position with iPhone / iPad: your Mac will play reference pink noise and build a 64-bit Auto-PEQ filter synced with iCloud.',
    'Розовый шум подан на АС — запишите 5–7 сек на микрофон iPhone/iPad и нажмите «Готово»': 'Pink noise is playing on speakers — record 5–7s on iPhone/iPad mic and tap "Done"',
    'Прогрев акустики калибровочным розовым шумом...': 'Warming up speakers with calibration pink noise...',
    'Замер АЧХ завершён — профиль Auto-PEQ сохранён и синхронизирован с iCloud': 'Room EQ measurement complete — Auto-PEQ profile saved & synced with iCloud',
    'Расчёт 4096-pt vDSP FFT и синтез 64-bit Auto-PEQ на Mac...': 'Computing 4096-pt vDSP FFT & synthesizing 64-bit Auto-PEQ on Mac...',
    'Не удалось распознать аудиозапись микрофона': 'Could not analyze microphone audio recording',
    'Профиль АЧХ комнаты создан и синхронизирован с iCloud': 'Room EQ profile created & synced with iCloud',
    'Ошибка отправки записи микрофона на Mac': 'Failed to upload microphone recording to Mac',
    'Ширина M/S:': 'M/S Width:',
    'Баланс L/R:': 'L/R Balance:',
    'Спектр жестко обрезан ниже 16.5 кГц — низкобитрейтный исходник (MP3/AAC 128 kbps) перекодирован в AAC 256 kbps.': 'Spectrum cuts off sharply below 16.5 kHz — low-bitrate source (MP3/AAC 128 kbps) was re-encoded to AAC 256 kbps.',
    'Внутри контейнера ALAC Lossless обнаружен жесткий срез ВЧ, характерный для сжатия с потерями.': 'Brickwall HF cutoff typical of lossy compression detected inside ALAC Lossless container.',
    'Поток передается в Hi-Res контейнере, но спектр ограничен частотой CD (22.05 кГц).': 'Stream is delivered in a Hi-Res container, but spectrum is limited to CD bandwidth (22.05 kHz).',
    'Младшие 8 бит в 24-битном потоке пустые — реальный динамический диапазон составляет 16 бит.': 'Lower 8 bits in the 24-bit stream are zero — true dynamic resolution is 16-bit.',
    'Спектральный анализ потока CoreAudio Process Tap через Accelerate vDSP FFT.': 'Real-time CoreAudio Process Tap spectral analysis via Accelerate vDSP FFT.',
    'Аудиофильский верификатор спектра отключен в настройках приложения.': 'Audiophile spectral verifier is disabled in application settings.',
    'Спектральный анализ...': 'Analyzing spectrum...',
    'Накопление PCM-буферов из CoreAudio Process Tap для расчёта БПФ-спектра.': 'Accumulating PCM buffers from CoreAudio Process Tap for FFT spectrum calculation.',
    'Zero-Padding (16-бит → 24-бит)': 'Zero-Padding (16-bit → 24-bit)',
    'Verified Studio Master 24-бит': 'Verified Studio Master 24-bit',
    'Апсемплинг CD (срез 22.05 кГц)': 'Upsampled CD (22.05 kHz cut)',
    'Не удалось удалить из медиатеки': 'Could not remove from Library',
    'Недавно добавленные в медиатеку': 'Recently Added to Library',
    'Медиатека Apple Music': 'Apple Music Library',
    'Системный плейлист нельзя удалить': 'System playlist cannot be deleted',
    'Устройство не авторизовано': 'Device is not authorized',
    'Генерация QR-приглашений доступна только устройствам с правами администратора ЦАП/аудиовыхода': 'QR invite generation is available only to devices with DAC / audio output permissions',
    'Выбор ЦАП и аудиовыхода отключён для этого устройства в настройках Mac': 'DAC & audio output selection is disabled for this device in Mac Settings',
    'Выбор ЦАП и параметров аудиовыхода отключён для этого устройства в настройках Mac': 'DAC & audio output settings are disabled for this device in Mac Settings',
    'Изменение настроек подсветки WLED отключено для этого устройства в настройках Mac': 'WLED lighting settings are disabled for this device in Mac Settings',
    'Изменение токена Apple Music отключено для этого устройства в настройках Mac': 'Apple Music token modification is disabled for this device in Mac Settings',
    'Выбор пресета DSP отключён для этого устройства в настройках Mac': 'DSP preset selection is disabled for this device in Mac Settings',
    'Выбор пресета DSP отключён при выводе на внешний сетевой плеер BluOS / DLNA': 'DSP preset selection is disabled when outputting to BluOS / DLNA network players',
    'Настройки пресетов DSP недоступны при выводе на внешний сетевой плеер BluOS / DLNA': 'DSP preset settings are unavailable when outputting to BluOS / DLNA network players',
    'Режимы DSD и HQ NOS доступны только при подключении внешнего USB ЦАП (≥ 24-бит / 176.4 кГц)': 'DSD & HQ NOS modes require an external USB DAC (≥ 24-bit / 176.4 kHz)',
    'Внешний USB / Thunderbolt ЦАП не подключён: DSD и HQ NOS доступны только для внешних USB / Thunderbolt ЦАП (≥ 24-бит / 176.4 кГц)': 'No external USB / Thunderbolt DAC connected: DSD & HQ NOS require an external USB / Thunderbolt DAC (≥ 24-bit / 176.4 kHz)',
    'Измерение АЧХ комнаты отключено для этого устройства в настройках Mac': 'Room EQ measurement is disabled for this device in Mac Settings',
    'Некорректные данные спектра (ожидается 31 полоса 1/3 октавы)': 'Invalid spectrum data (expected 31 1/3-octave bands)',
    'Управление коррекцией АЧХ отключено для этого устройства в настройках Mac': 'Room EQ control is disabled for this device in Mac Settings',
    'Выбор профиля АЧХ отключён для этого устройства в настройках Mac': 'Room EQ profile selection is disabled for this device in Mac Settings',
    'Редактирование профилей АЧХ отключено для этого устройства': 'Editing Room EQ profiles is disabled for this device',
    'Не удалось переименовать профиль АЧХ': 'Could not rename Room EQ profile',
    'Удаление профилей АЧХ отключено для этого устройства': 'Deleting Room EQ profiles is disabled for this device',
    'Профиль АЧХ не найден': 'Room EQ profile not found',
    'Доступ к ночному режиму (Late-Night DRC) отключён для этого устройства в настройках Mac': 'Late-Night Mode (DRC) access is disabled for this device in Mac Settings',
    'Управление параметрами DSP отключено для этого устройства в настройках Mac': 'DSP parameter control is disabled for this device in Mac Settings',
    'Управление параметрами DSP отключено для этого устройства': 'DSP parameter control is disabled for this device',
    'Облачная синхронизация выключена в настройках Mac': 'Cloud sync is disabled in Mac Settings',
    'Изменение и удаление медиатеки отключено для этого устройства в настройках Mac': 'Library modification and deletion are disabled for this device in Mac Settings',
    'Управление усилителем отключено для этого устройства в настройках Mac': 'Amplifier control is disabled for this device in Mac Settings',
    'Web UI не авторизован в Apple ID. Выполните вход через карточку на главной странице.': 'Web UI is not signed in to Apple ID. Sign in via the card on the Home tab.',
    'Срок действия сессии Apple ID в браузере истек.': 'Browser Apple ID session has expired.',
    'Учетная запись Apple ID активна (онлайн-проверка отложена).': 'Apple ID account is active (online verification deferred).',
    'Не удалось верифицировать токен Apple ID.': 'Could not verify Apple ID token.',
    'Учетная запись Apple ID полностью синхронизирована с Mac.': 'Apple ID account is fully synchronized with Mac.',
    'Медиатека в браузере отличается от медиатеки Music.app на Mac.': 'Browser library differs from Music.app library on Mac.',
    'Аудиозапись слишком короткая': 'Audio recording is too short',
    'Неподдерживаемый аудиоформат записи': 'Unsupported audio recording format',
    'Запись должна длиться не менее 1–2 секунд во время звучания розового шума': 'Recording must be at least 1–2 seconds long while pink noise is playing',
    'Недостаточно аудиосэмплов для спектрального анализа': 'Insufficient audio samples for spectral analysis',
    'Записана тишина — убедитесь, что доступ к микрофону разрешён и громкость системы достаточна': 'Silence recorded — check microphone permission and speaker volume',
    'Не удалось инициализировать vDSP FFT': 'Failed to initialize vDSP FFT',
    'DoP 705.6 кГц • Trellis M=8 • AMX Min-Phase • ISI • Референсный баланс': 'DoP 705.6 kHz • Trellis M=8 • AMX Min-Phase • ISI • Reference Balance',
    'DoP 705.6 кГц • Trellis M=16 • Metal GPU Sinc-M (262k) • Глубокая сцена': 'DoP 705.6 kHz • Trellis M=16 • Metal GPU Sinc-M (262k) • Deep Soundstage',
    'DoP 352.8 кГц • OBG 1.38 • Min-Phase без предзвона • Панч для рока и метала': 'DoP 352.8 kHz • OBG 1.38 • Zero Pre-Ring Min-Phase • Rock & Metal Punch',
    'DoP 176.4 кГц / 24-bit • Совместимость с S/PDIF и классическими ЦАП': 'DoP 176.4 kHz / 24-bit • S/PDIF & Classic DAC Compatibility',
    'PCM 705.6/768 кГц в обход ЦФ ЦАП • Metal Linear-Phase • Шейпер 15-го порядка': 'PCM 705.6/768 kHz DAC Filter Bypass • Metal Linear-Phase • 15th-Order Shaper',
    'Любимые треки и персональные рекомендации': 'Favorite tracks & personal recommendations',
    'Новая музыка на основе ваших вкусов': 'New music based on what you love',
    'Главные мировые релизы в прямом эфире': 'The new music that matters, live 24/7',
    'Культовые хиты 80-х, 90-х и 2000-х': 'The songs you know and love',
    'Современное и классическое кантри': 'Where country music lives',
    'Самые популярные поп-треки мира': 'The biggest pop anthems right now',
    'Культовые рок-гимны и гитарные соло': 'Greatest guitar anthems & classic rock',
    'Плотные биты и свежие релизы': 'Heavy beats and groundbreaking rap',
    'Клубный драйв и танцевальная энергия': 'Non-stop club bangers & festival anthems',
    'Глубокое электронное звучание': 'Deep melodic house & hypnotic rhythms',
    'Безупречная классика джаза': 'Timeless jazz standards & soothing brass',
    'ПРЯМОЙ ЭФИР': 'LIVE RADIO',
    'Прямой эфир': 'Live Radio',
    'Итоги года Replay': 'Replay Mix',
    'ИТОГИ ГОДА REPLAY': 'REPLAY MIX',
    'Главные новинки': 'New Music Daily',
    'Хиты сегодня': "Today's Hits",
    'Чистый релакс': 'Pure Chill',
    'Энергия тренировки': 'Pure Workout'
  };

// === MODULE: 02-i18n-identity-and-state.js ===
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

// === MODULE: 03-dom-cache-and-websocket.js ===
  function recoverOrPersistDeviceUidBeforeConnect() {
    const hasCacheStorage = typeof window !== 'undefined' && 'caches' in window && Boolean(window.caches) && typeof window.caches.open === 'function';
    const needUidRecovery = Boolean(state.deviceIdWasFreshlyGenerated);
    const needSecretRecovery = !state.deviceSecret;
    if (!needUidRecovery && !needSecretRecovery) {
      persistUidToSecureStore(state.deviceId);
      persistDeviceSecret(state.deviceSecret);
      return Promise.resolve();
    }
    if (!hasCacheStorage) {
      state.deviceIdWasFreshlyGenerated = false;
      persistUidToSecureStore(state.deviceId);
      if (state.deviceSecret) persistDeviceSecret(state.deviceSecret);
      return Promise.resolve();
    }
    const freshlyGeneratedUid = state.deviceId;
    const cacheLookupPromise = Promise.resolve()
      .then(() => window.caches.open('amr-device-secure-store-v1'))
      .then(async (cache) => {
        if (!cache || typeof cache.match !== 'function') return { rawUid: null, rawSecret: null };
        const [uidResp, secResp] = await Promise.all([
          needUidRecovery ? cache.match('/__amr_device_uid').catch(() => null) : Promise.resolve(null),
          needSecretRecovery ? cache.match('/__amr_device_secret').catch(() => null) : Promise.resolve(null)
        ]);
        const rawUid = uidResp && typeof uidResp.text === 'function' ? await uidResp.text().catch(() => null) : null;
        const rawSecret = secResp && typeof secResp.text === 'function' ? await secResp.text().catch(() => null) : null;
        return { rawUid, rawSecret };
      })
      .catch(() => ({ rawUid: null, rawSecret: null }));
    const timeoutPromise = new Promise((resolve) => {
      setTimeout(() => resolve({ rawUid: null, rawSecret: null }), 250);
    });
    return Promise.race([cacheLookupPromise, timeoutPromise])
      .then(({ rawUid, rawSecret }) => {
        if (needUidRecovery) {
          let candidate = String(rawUid || '').trim();
          if (candidate.startsWith('{')) {
            try {
              const parsed = JSON.parse(candidate);
              if (parsed && parsed.uid) candidate = String(parsed.uid).trim();
            } catch (_) {}
          }
          const cachedUid = candidate.toLowerCase();
          if (cachedUid && /^[A-Za-z0-9._-]{8,128}$/.test(cachedUid)) {
            state.deviceId = cachedUid;
            state.deviceShortId = computeShortDeviceId(cachedUid);
            state.supersededFreshDeviceId = freshlyGeneratedUid;
          }
          state.deviceIdWasFreshlyGenerated = false;
        }
        if (needSecretRecovery) {
          const cachedSecret = String(rawSecret || '').trim();
          if (cachedSecret && /^[A-Za-z0-9._-]{16,256}$/.test(cachedSecret)) {
            state.deviceSecret = cachedSecret;
          }
        }
        persistUidToSecureStore(state.deviceId);
        if (state.deviceSecret) {
          persistDeviceSecret(state.deviceSecret);
        }
        if (typeof syncDeviceInfoUI === 'function') {
          syncDeviceInfoUI();
        }
      })
      .catch(() => {
        state.deviceIdWasFreshlyGenerated = false;
        persistUidToSecureStore(state.deviceId);
        if (state.deviceSecret) persistDeviceSecret(state.deviceSecret);
      });
  }

  // --- DOM Elements Cache ---
  const dom = {
    overlay: document.getElementById('connection-overlay'),
    connectionStatusText: document.getElementById('connection-status-text'),
    btnReconnect: document.getElementById('btn-reconnect'),

    // Views
    viewNowPlaying: document.getElementById('view-now-playing'),
    viewQueue: document.getElementById('view-queue'),
    viewPlaylists: document.getElementById('view-playlists'),
    viewLibrary: document.getElementById('view-library'),
    viewHome: document.getElementById('view-home') || document.getElementById('view-trends'),
    viewTrends: document.getElementById('view-home') || document.getElementById('view-trends'),
    viewSearch: document.getElementById('view-search'),

    // Home / Trends Elements
    homeHeroCarousel: document.getElementById('home-hero-carousel'),
    homeRecentSection: document.getElementById('home-recent-section'),
    homeRecentLink: document.getElementById('home-recent-link'),
    homeRecentCarousel: document.getElementById('home-recent-carousel'),
    homeMixesSection: document.getElementById('home-mixes-section'),
    homeMixesLink: document.getElementById('home-mixes-link'),
    homeMixesCarousel: document.getElementById('home-mixes-carousel'),
    homeHeavySection: document.getElementById('home-heavy-section'),
    homeHeavyCarousel: document.getElementById('home-heavy-carousel'),
    homeRecContainer: document.getElementById('home-recommendations-container'),
    searchLanding: document.getElementById('search-landing'),
    homeStationsSection: document.getElementById('home-stations-section'),
    homeStationsLink: document.getElementById('home-stations-link'),
    homeStationsCarousel: document.getElementById('home-stations-carousel'),
    homeAlbumsSection: document.getElementById('home-albums-section'),
    homeAlbumsLink: document.getElementById('home-albums-link'),
    homeAlbumsCarousel: document.getElementById('home-albums-carousel'),
    homeGenresSection: document.getElementById('home-genres-section'),
    homeGenresGrid: document.getElementById('home-genres-grid'),

    // Section Tiles Grid View
    sectionGridView: document.getElementById('section-grid-view'),
    btnBackFromGrid: document.getElementById('btn-back-from-grid'),
    gridViewTitle: document.getElementById('grid-view-title'),
    sectionTilesGrid: document.getElementById('section-tiles-grid'),

    // Recently Played Full Pane
    recentDetailPane: document.getElementById('recent-detail-pane'),
    btnBackFromRecent: document.getElementById('btn-back-from-recent'),
    btnPlayRecentAll: document.getElementById('btn-play-recent-all'),
    btnShuffleRecentAll: document.getElementById('btn-shuffle-recent-all'),
    recentTracksFullList: document.getElementById('recent-tracks-full-list'),
    recentTotalCount: document.getElementById('recent-total-count'),

    headerAccountBadge: document.getElementById('header-account-badge'),
    headerAccountText: document.getElementById('header-account-text'),
    btnHeaderLogout: document.getElementById('btn-header-logout'),

    // Home Account Card & Diagnostic Modal
    homeAccountCard: document.getElementById('home-account-card'),
    accountCardEmail: document.getElementById('account-card-email'),
    accountCardBadge: document.getElementById('account-card-badge'),
    accountStatusDot: document.getElementById('account-status-dot'),
    accountCardSubtext: document.getElementById('account-card-subtext'),
    btnAccountDiag: document.getElementById('btn-account-diag'),
    modalAccountDiag: document.getElementById('modal-account-diag'),
    btnCloseAccountDiag: document.getElementById('btn-close-account-diag'),
    btnDoneAccountDiag: document.getElementById('btn-done-account-diag'),
    btnRefreshAccountDiag: document.getElementById('btn-refresh-account-diag'),
    diagValAccount: document.getElementById('diag-val-account'),
    diagValStatus: document.getElementById('diag-val-status'),
    diagValStorefront: document.getElementById('diag-val-storefront'),
    diagValSub: document.getElementById('diag-val-sub'),
    diagValDac: document.getElementById('diag-val-dac'),
    trendsStationsGrid: document.getElementById('home-stations-carousel') || document.getElementById('trends-stations-grid'),
    trendsAlbumsGrid: document.getElementById('home-albums-carousel') || document.getElementById('trends-albums-grid'),
    trendsGenresGrid: document.getElementById('home-genres-grid') || document.getElementById('trends-genres-grid'),

    // Desktop Nav
    desktopNavButtons: document.querySelectorAll('.nav-tab-btn'),

    // Mobile Bottom Tab Bar
    tabItems: document.querySelectorAll('.tab-item'),

    // Mini Player
    miniPlayer: document.getElementById('mini-player'),
    miniTrigger: document.getElementById('mini-player-trigger'),
    miniArt: document.getElementById('mini-artwork'),
    miniTitle: document.getElementById('mini-title'),
    miniArtist: document.getElementById('mini-artist'),
    miniBtnFavorite: document.getElementById('mini-btn-favorite'),
    miniBtnPlayPause: document.getElementById('mini-btn-play-pause'),
    miniIconPlay: document.getElementById('mini-icon-play'),
    miniIconPause: document.getElementById('mini-icon-pause'),
    miniBtnNext: document.getElementById('mini-btn-next'),
    miniProgressTrack: document.getElementById('mini-progress-track') || document.querySelector('.mini-progress-track'),
    miniProgressFill: document.getElementById('mini-progress-fill'),

    // Ambient Backdrop Elements
    ambientBackdrop: document.getElementById('ambient-backdrop'),
    ambientLayerA: document.getElementById('ambient-layer-a'),
    ambientLayerB: document.getElementById('ambient-layer-b'),

    // Now Playing Main Player
    artworkContainer: document.querySelector('.artwork-container'),
    artworkWrapper: document.querySelector('.artwork-wrapper'),
    playerArtwork: document.getElementById('player-artwork'),
    playerTitle: document.getElementById('player-title'),
    playerArtist: document.getElementById('player-artist'),
    playerAlbum: document.getElementById('player-album'),
    btnGoToAlbum: document.getElementById('btn-go-to-album'),
    btnAiTrackVibe: document.getElementById('btn-ai-track-vibe'),
    btnCreateStation: document.getElementById('btn-create-station'),
    btnFavorite: document.getElementById('btn-favorite'),
    audioQualityBadge: document.getElementById('audio-quality-badge'),
    audioQualityText: document.getElementById('audio-quality-text'),
    desktopDacBadge: document.getElementById('desktop-dac-badge'),
    desktopDacText: document.getElementById('desktop-dac-text'),
    mobileDacBadge: document.getElementById('mobile-dac-badge'),
    mobileDacText: document.getElementById('mobile-dac-text'),

    // Station Picker / Track Actions Modal (•••)
    stationPickerModal: document.getElementById('station-picker-modal'),
    btnCloseStationModal: document.getElementById('btn-close-station-modal'),
    stationModalTrackBanner: document.getElementById('station-modal-track-banner'),
    stationModalTrackArt: document.getElementById('station-modal-track-art'),
    stationModalTrackTitle: document.getElementById('station-modal-track-title'),
    stationModalTrackSub: document.getElementById('station-modal-track-sub'),
    btnAddTrackLibrary: document.getElementById('btn-add-track-library'),
    btnRemoveTrackLibrary: document.getElementById('btn-remove-track-library'),
    btnGoToLibraryArtist: document.getElementById('btn-go-to-library-artist'),
    stationOptLibArtistName: document.getElementById('station-opt-lib-artist-name'),
    btnRemoveArtistLibrary: document.getElementById('btn-remove-artist-library'),
    stationOptRemoveArtistSub: document.getElementById('station-opt-remove-artist-sub'),
    btnAiMixByTrack: document.getElementById('btn-ai-mix-by-track'),
    stationOptAiVibeSub: document.getElementById('station-opt-ai-vibe-sub'),
    btnSonicBridgeByTrack: document.getElementById('btn-sonic-bridge-by-track'),
    stationOptSonicBridgeSub: document.getElementById('station-opt-sonic-bridge-sub'),
    btnStationByTrack: document.getElementById('btn-station-by-track'),
    btnStationByArtist: document.getElementById('btn-station-by-artist'),
    stationOptAlbumName: document.getElementById('station-opt-album-name'),
    stationOptTrackName: document.getElementById('station-opt-track-name'),
    stationOptArtistName: document.getElementById('station-opt-artist-name'),
    moreBookletDot: document.getElementById('more-booklet-dot'),

    // Scrubber
    scrubberContainer: document.getElementById('scrubber-container'),
    scrubberFill: document.getElementById('scrubber-fill'),
    scrubberThumb: document.getElementById('scrubber-thumb'),
    scrubberInput: document.getElementById('scrubber-input'),
    timeElapsed: document.getElementById('time-elapsed'),
    timeRemaining: document.getElementById('time-remaining'),
    playerLoadingStatus: document.getElementById('player-loading-status'),
    playerLoadingText: document.getElementById('player-loading-text'),
    standbyProgressTrack: document.getElementById('standby-progress-track'),
    standbyLoadingStatus: document.getElementById('standby-loading-status'),
    standbyLoadingText: document.getElementById('standby-loading-text'),
    standbyBtnPlayPause: document.getElementById('standby-btn-play-pause'),

    // Transport Controls
    btnShuffle: document.getElementById('btn-shuffle'),
    btnPrev: document.getElementById('btn-prev'),
    btnPlayPause: document.getElementById('btn-play-pause'),
    iconPlay: document.getElementById('icon-play'),
    iconPause: document.getElementById('icon-pause'),
    btnNext: document.getElementById('btn-next'),
    btnRepeat: document.getElementById('btn-repeat'),
    repeatBadge: document.getElementById('repeat-badge'),

    // Queue Elements
    queueSubtitle: document.getElementById('queue-subtitle'),
    queueHistoryGroup: document.getElementById('queue-history-group'),
    queueHistoryList: document.getElementById('queue-history-list'),
    btnToggleQueueHistory: document.getElementById('btn-toggle-queue-history'),
    queueCurrentGroup: document.getElementById('queue-current-group'),
    queueCurrentTrack: document.getElementById('queue-current-track'),
    queueUpcomingList: document.getElementById('queue-upcoming-list'),
    btnSaveQueuePlaylist: document.getElementById('btn-save-queue-playlist'),
    btnSaveQueueText: document.getElementById('btn-save-queue-text'),
    btnClearQueue: document.getElementById('btn-clear-queue'),

    // Playlists & Library Elements
    playlistsSectionSubtitle: document.getElementById('playlists-section-subtitle'),
    btnRefreshPlaylists: document.getElementById('btn-refresh-playlists'),
    playlistsBrowsePane: document.getElementById('playlists-browse-pane'),
    playlistsGrid: document.getElementById('playlists-grid'),
    libraryRecentPane: document.getElementById('library-recent-pane'),
    libraryArtistsPane: document.getElementById('library-artists-pane'),
    libraryArtistsToolbar: document.getElementById('library-artists-toolbar'),
    libraryArtistsFilter: document.getElementById('library-artists-filter'),
    btnClearArtistsFilter: document.getElementById('btn-clear-artists-filter'),
    libraryArtistsList: document.getElementById('library-artists-list'),
    libraryAlbumsGrid: document.getElementById('library-albums-grid'),
    librarySongsPane: document.getElementById('library-songs-pane'),
    librarySongsToolbar: document.getElementById('library-songs-toolbar'),
    librarySongsFilter: document.getElementById('library-songs-filter'),
    btnClearSongsFilter: document.getElementById('btn-clear-songs-filter'),
    btnPlayLibrarySongs: document.getElementById('btn-play-library-songs'),
    btnShuffleLibrarySongs: document.getElementById('btn-shuffle-library-songs'),
    librarySongsList: document.getElementById('library-songs-list'),
    librarySectionSubtitle: document.getElementById('library-section-subtitle'),
    librarySegRecent: document.getElementById('library-seg-recent'),
    librarySegArtists: document.getElementById('library-seg-artists'),
    librarySegAlbums: document.getElementById('library-seg-albums'),
    librarySegSongs: document.getElementById('library-seg-songs'),
    btnRefreshLibrary: document.getElementById('btn-refresh-library'),
    btnRefreshLibraryDesktop: document.getElementById('btn-refresh-library-desktop'),
    libraryArtistDetailPane: document.getElementById('library-artist-detail-pane'),
    btnBackToArtists: document.getElementById('btn-back-to-artists'),
    artistDetailArtwork: document.getElementById('artist-detail-artwork'),
    artistDetailInitials: document.getElementById('artist-detail-initials'),
    artistDetailTitle: document.getElementById('artist-detail-title'),
    artistDetailMeta: document.getElementById('artist-detail-meta'),
    btnPlayArtistLibrary: document.getElementById('btn-play-artist-library'),
    btnShuffleArtistLibrary: document.getElementById('btn-shuffle-artist-library'),
    btnRemoveArtistDetailLibrary: document.getElementById('btn-remove-artist-detail-library'),
    artistDetailContent: document.getElementById('artist-detail-content'),
    playlistDetailPane: document.getElementById('playlist-detail-pane'),
    btnBackToPlaylists: document.getElementById('btn-back-to-playlists'),
    detailBackLabel: document.getElementById('detail-back-label'),
    detailArtwork: document.getElementById('detail-artwork'),
    detailTitle: document.getElementById('detail-title'),
    detailBadge: document.getElementById('detail-badge'),
    detailMeta: document.getElementById('detail-meta'),
    btnPlayPlaylist: document.getElementById('btn-play-playlist'),
    btnShufflePlaylist: document.getElementById('btn-shuffle-playlist'),
    btnAddPlaylistLibrary: document.getElementById('btn-add-playlist-library'),
    btnAddPlaylistLibraryText: document.getElementById('btn-add-playlist-library-text'),
    btnRemoveDetailLibrary: document.getElementById('btn-remove-detail-library'),
    btnRemoveDetailLibraryText: document.getElementById('btn-remove-detail-library-text'),
    playlistTracksList: document.getElementById('playlist-tracks-list'),
    albumCompletenessBannerSlot: document.getElementById('album-completeness-banner-slot'),
    confirmDeleteModal: document.getElementById('library-delete-confirm-modal'),
    confirmDeleteTitle: document.getElementById('confirm-delete-title'),
    confirmDeleteMessage: document.getElementById('confirm-delete-message'),
    btnConfirmDeleteCancel: document.getElementById('btn-confirm-delete-cancel'),
    btnConfirmDeleteOk: document.getElementById('btn-confirm-delete-ok'),

    // Search Elements
    searchInput: document.getElementById('search-input'),
    btnClearSearch: document.getElementById('btn-clear-search'),
    filterChips: document.querySelectorAll('.filter-chip'),
    searchResults: document.getElementById('search-results'),

    // Busy / Action Loading Overlay
    busyOverlay: document.getElementById('busy-overlay'),
    busyMessage: document.getElementById('busy-message'),

    // Volume Section
    volumeSection: document.getElementById('volume-section'),
    btnVolumeMute: document.getElementById('btn-volume-mute'),
    volumeIcon: document.getElementById('volume-icon'),
    volumeInput: document.getElementById('volume-input'),
    volumeTrackFill: document.getElementById('volume-track-fill'),
    volumeThumb: document.getElementById('volume-thumb'),
    volumeLevelText: document.getElementById('volume-level-text'),
    playerBottomNotice: document.querySelector('.player-bottom-notice .dac-notice-text'),
    // StandBy / TV Mode Inline Volume Bar
    standbyVolumeSection: document.getElementById('standby-volume-section'),
    standbyBtnVolumeMute: document.getElementById('standby-btn-volume-mute'),
    standbyVolFill: document.getElementById('standby-vol-fill'),
    standbyVolThumb: document.getElementById('standby-vol-thumb'),
    standbyVolLoupe: document.getElementById('standby-vol-loupe'),
    standbyVolLoupeText: document.getElementById('standby-vol-loupe-text'),
    standbyVolumeInput: document.getElementById('standby-volume-input'),
    standbyVolumeText: document.getElementById('standby-volume-text'),
    // Signal Path Modal
    qualityModal: document.getElementById('quality-modal'),
    btnCloseModal: document.getElementById('btn-close-modal'),
    signalSourceBadge: document.getElementById('signal-source-badge'),
    signalSourceTitle: document.getElementById('signal-source-title'),
    signalSourceDetails: document.getElementById('signal-source-details'),
    signalDacRate: document.getElementById('signal-dac-rate'),
    signalDacName: document.getElementById('signal-dac-name'),
    signalDacDetails: document.getElementById('signal-dac-details'),
    signalConnectorAmp: document.getElementById('signal-connector-amp'),
    signalNodeAmp: document.getElementById('signal-node-amp'),
    signalAmpDot: document.getElementById('signal-amp-dot'),
    signalAmpVolumeBadge: document.getElementById('signal-amp-volume-badge'),
    signalAmpName: document.getElementById('signal-amp-name'),
    signalAmpDetails: document.getElementById('signal-amp-details'),
    btnOpenDevices: document.getElementById('btn-open-devices'),
    // Audio Devices Modal
    devicesModal: document.getElementById('devices-modal'),
    btnCloseDevices: document.getElementById('btn-close-devices'),
    audioDevicesList: document.getElementById('audio-devices-list'),
    // Apple ID Auth Modal
    modalAppleAuth: document.getElementById('modal-apple-auth'),
    btnAuthModalLogin: document.getElementById('btn-auth-modal-login'),
    authModalStatus: document.getElementById('auth-modal-status'),
    topSettingsPopover: document.getElementById('top-settings-popover')
  };

  // --- Busy Overlay & Action Loading Controller ---
  let busyTimeout = null;
  let activeLoadingBtn = null;

  function markWaitingForPlayback(options = {}) {
    state.waitingForPlayback = true;
    state.waitingTrackSignature = (state.track && state.track.name) ? `${state.track.name}:${state.track.artist || ''}` : null;
    state.waitingExpectedTrackName = options.expectedTrackName ? String(options.expectedTrackName).trim().toLowerCase() : null;
    state.waitingStartTime = Date.now();
    state.waitingIsStation = Boolean(options.isStation);
    state.waitingTargetName = options.targetName || null;
    if (options.isStation) {
      state.isLaunchingStation = true;
      if (state.stationLaunchTimeout) clearTimeout(state.stationLaunchTimeout);
      // Safety timeout: unblock UI after 7s if station connection hangs
      state.stationLaunchTimeout = setTimeout(() => {
        state.isLaunchingStation = false;
        state.waitingForPlayback = false;
        state.waitingIsStation = false;
        setUIBusy(false);
      }, 7000);
    }
  }

  function setUIBusy(isBusy, message = 'Загрузка...', sourceBtn = null) {
    state.isBusyAction = Boolean(isBusy);

    if (isBusy) {
      if (busyTimeout) clearTimeout(busyTimeout);
      document.body.classList.add('ui-blocked');

      if (dom.busyMessage) {
        dom.busyMessage.textContent = translateTextToEn(message);
      }
      if (dom.busyOverlay) {
        dom.busyOverlay.classList.remove('hidden');
      }

      if (sourceBtn) {
        if (activeLoadingBtn && activeLoadingBtn !== sourceBtn) {
          activeLoadingBtn.classList.remove('btn-loading');
        }
        activeLoadingBtn = sourceBtn;
        sourceBtn.classList.add('btn-loading');
      }

      // Safety timeout: automatically unblock after timeout if server is slow
      const isLongOp = Boolean(
        state.isAiCurating ||
        message.includes('ИИ') ||
        message.includes('AI') ||
        message.includes('Синхронизация') ||
        message.includes('очереди') ||
        message.includes('Apple Music')
      );
      const safetyMs = isLongOp ? 25000 : 10000;
      busyTimeout = setTimeout(() => {
        if (!state.aiCurateTimeoutId) {
          state.isAiCurating = false;
          state.pendingStandbyAiAutoPlay = false;
        }
        state.waitingForPlayback = false;
        state.waitingTrackSignature = null;
        state.waitingExpectedTrackName = null;
        state.waitingIsStation = false;
        state.waitingTargetName = null;
        if (state.isLaunchingStation) {
          state.isLaunchingStation = false;
          if (state.stationLaunchTimeout) {
            clearTimeout(state.stationLaunchTimeout);
            state.stationLaunchTimeout = null;
          }
        }
        setUIBusy(false);
      }, safetyMs);
    } else {
      state.waitingForPlayback = false;
      state.waitingTrackSignature = null;
      state.waitingExpectedTrackName = null;
      state.waitingIsStation = false;
      state.waitingTargetName = null;
      if (state.isLaunchingStation) {
        state.isLaunchingStation = false;
        if (state.stationLaunchTimeout) {
          clearTimeout(state.stationLaunchTimeout);
          state.stationLaunchTimeout = null;
        }
      }
      if (busyTimeout) {
        clearTimeout(busyTimeout);
        busyTimeout = null;
      }
      document.body.classList.remove('ui-blocked');

      if (dom.busyOverlay) {
        dom.busyOverlay.classList.add('hidden');
      }

      if (activeLoadingBtn) {
        activeLoadingBtn.classList.remove('btn-loading');
        activeLoadingBtn = null;
      }
      document.querySelectorAll('.btn-loading').forEach(b => b.classList.remove('btn-loading'));
    }
  }

  // --- WebSocket Manager ---
  let socket = null;
  let reconnectTimer = null;
  let reconnectAttempt = 0;
  const backoffDelays = [1000, 2000, 3000, 5000];

  function getWsUrl() {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const host = window.location.host || 'localhost:8080';
    return `${protocol}//${host}`;
  }

  const recentGetRpcSentAt = new Map();
  const pendingPreOpenQueue = [];
  let disconnectAudioGraceTimer = null;

  function clearDisconnectAudioGraceTimer() {
    if (disconnectAudioGraceTimer) {
      clearTimeout(disconnectAudioGraceTimer);
      disconnectAudioGraceTimer = null;
    }
  }

  function pauseSilentAudioAfterDisconnectGrace() {
    if (document.hidden && state.playerState === 'playing' && isLockScreenAllowedNow()) {
      // Keep silent audio alive during transient background Wi-Fi/TCP reconnects so iOS does not
      // immediately suspend the locked WebProcess or tear down Prev/Next Lock Screen controls.
      if (!disconnectAudioGraceTimer) {
        disconnectAudioGraceTimer = setTimeout(() => {
          disconnectAudioGraceTimer = null;
          if (!state.connected) {
            syncSilentAudio(false);
          }
        }, 15000);
      }
      return;
    }
    clearDisconnectAudioGraceTimer();
    syncSilentAudio(false);
  }

  function flushPendingPreOpenQueue() {
    if (!socket || socket.readyState !== WebSocket.OPEN || !state.deviceAuthorized) return;
    while (pendingPreOpenQueue.length > 0) {
      const queuedMsg = pendingPreOpenQueue.shift();
      if (queuedMsg) send(queuedMsg);
    }
  }

  function connectWebSocket() {
    clearTimeout(reconnectTimer);

    if (socket) {
      try {
        socket.onopen = null;
        socket.onmessage = null;
        socket.onclose = null;
        socket.onerror = null;
        socket.close();
      } catch (e) {}
    }

    const url = getWsUrl();
    try {
      socket = new WebSocket(url);
    } catch (err) {
      scheduleReconnect();
      return;
    }

    socket.onopen = function () {
      state.connected = true;
      state.lastServerMessageAt = Date.now();
      state.pendingPingSentAt = 0;
      state.lastPlayerStateReceivedAt = 0;
      state.lastQueueReceivedAt = 0;
      state.lastAiSettingsReceivedAt = 0;
      state.initialAuthFetched = false;
      recentGetRpcSentAt.clear();
      trendsInFlightCountry = '';
      trendsInFlightSince = 0;
      reconnectAttempt = 0;
      clearDisconnectAudioGraceTimer();
      dom.overlay.classList.add('hidden');
      ensureScrubberLoopRunning();

      // Step 1: Register this PWA device UID & verify device authorization FIRST.
      // Apple ID / MusicKit / catalog checks run ONLY after the device is authorized on Mac.
      const regParams = {
        device_id: state.deviceId,
        device_name: state.deviceName,
        device_type: state.deviceType,
        lock_screen_controls: state.lockScreenControls,
        invite_token: state.inviteToken || ''
      };
      if (state.deviceSecret) {
        regParams.device_secret = state.deviceSecret;
      }
      send({
        action: 'register_device',
        params: regParams
      });
    };

    socket.onmessage = function (event) {
      try {
        const msg = JSON.parse(event.data);
        handleServerMessage(msg);
      } catch (e) {
        console.error('Failed to parse WebSocket message:', e, event.data);
      }
    };

    socket.onclose = function () {
      state.connected = false;
      state.pendingPingSentAt = 0;
      recentGetRpcSentAt.clear();
      if (state.isMeasuringRoom) {
        stopRoomMeasurementSession(false);
      }
      dom.overlay.classList.remove('hidden');
      pauseSilentAudioAfterDisconnectGrace();
      syncMotionVideoPlaybackState();
      ScreenWakeLockManager.syncByPlaybackAndConnection();
      scheduleReconnect();
    };

    socket.onerror = function () {
      state.connected = false;
      state.pendingPingSentAt = 0;
      dom.overlay.classList.remove('hidden');
      pauseSilentAudioAfterDisconnectGrace();
      syncMotionVideoPlaybackState();
      ScreenWakeLockManager.syncByPlaybackAndConnection();
    };
  }

  function scheduleReconnect() {
    const delay = backoffDelays[Math.min(reconnectAttempt, backoffDelays.length - 1)];
    reconnectAttempt++;
    dom.connectionStatusText.textContent = `Попытка переподключения через ${Math.round(delay / 1000)}с... (попытка ${reconnectAttempt})`;
    clearTimeout(reconnectTimer);
    reconnectTimer = setTimeout(connectWebSocket, delay);
  }

  function send(msgObj) {
    const act = (msgObj && msgObj.action) ? msgObj.action.toLowerCase() : '';
    const isAiCurateAction = (
      act === 'ai_curate' ||
      act === 'ai_curate_from_track' ||
      act === 'play_ai_track_vibe' ||
      act === 'build_sonic_bridge' ||
      act === 'sonic_bridge'
    );
    if (!socket || socket.readyState !== WebSocket.OPEN) {
      if (isAiCurateAction) {
        if (state.aiCurateTimeoutId) {
          clearTimeout(state.aiCurateTimeoutId);
          state.aiCurateTimeoutId = null;
        }
        state.isAiCurating = false;
        state.pendingStandbyAiAutoPlay = false;
        state.sonicBridgeAutoPlay = false;
      } else if (act === 'set_user_token') {
        for (let i = pendingPreOpenQueue.length - 1; i >= 0; i--) {
          const itemAct = pendingPreOpenQueue[i] && pendingPreOpenQueue[i].action
            ? String(pendingPreOpenQueue[i].action).toLowerCase()
            : '';
          if (itemAct === 'set_user_token') {
            pendingPreOpenQueue.splice(i, 1);
          }
        }
        pendingPreOpenQueue.push(msgObj);
        if (!socket || socket.readyState === WebSocket.CLOSED || socket.readyState === WebSocket.CLOSING) {
          connectWebSocket();
        }
      } else if (act === 'previous' || act === 'next' || act === 'play' || act === 'pause') {
        for (let i = pendingPreOpenQueue.length - 1; i >= 0; i--) {
          const itemAct = pendingPreOpenQueue[i] && pendingPreOpenQueue[i].action
            ? String(pendingPreOpenQueue[i].action).toLowerCase()
            : '';
          if (itemAct === 'previous' || itemAct === 'next' || itemAct === 'play' || itemAct === 'pause') {
            pendingPreOpenQueue.splice(i, 1);
          }
        }
        pendingPreOpenQueue.push(msgObj);
        if (!socket || socket.readyState === WebSocket.CLOSED || socket.readyState === WebSocket.CLOSING) {
          connectWebSocket();
        }
      } else if (act.startsWith('get_') && pendingPreOpenQueue.length < 16) {
        if (!pendingPreOpenQueue.some((item) => item && item.action === msgObj.action)) {
          pendingPreOpenQueue.push(msgObj);
        }
      }
      return false;
    }
    const isRealtimeSpectralPoll = (act === 'get_spectral_analysis' || act === 'get_spectral_rta');
    if (act.startsWith('get_') && !isRealtimeSpectralPoll && !(msgObj.params && msgObj.params.refresh === true)) {
      const nowMs = Date.now();
      const dedupeKey = `${act}|${msgObj.params ? JSON.stringify(msgObj.params) : ''}`;
      const prevAt = recentGetRpcSentAt.get(dedupeKey) || 0;
      if (nowMs - prevAt < 500) {
        return true;
      }
      recentGetRpcSentAt.set(dedupeKey, nowMs);
      if (recentGetRpcSentAt.size > 120) {
        for (const [k, ts] of recentGetRpcSentAt.entries()) {
          if (nowMs - ts >= 500) recentGetRpcSentAt.delete(k);
        }
      }
    }
    if (isAiCurateAction) {
      if (!msgObj.params || typeof msgObj.params !== 'object') {
        msgObj.params = {};
      }
      if (!msgObj.request_id && !msgObj.params.request_id) {
        state.aiCurateReqSeq = (state.aiCurateReqSeq || 0) + 1;
      }
      const reqId = msgObj.request_id || msgObj.params.request_id || state.aiCurateReqSeq;
      msgObj.request_id = reqId;
      msgObj.params.request_id = reqId;
      state.lastAiCurateSentAt = Date.now();
      if (state.aiCurateTimeoutId) {
        clearTimeout(state.aiCurateTimeoutId);
      }
      state.aiCurateTimeoutId = setTimeout(() => {
        if (state.aiCurateReqSeq === reqId) {
          state.isAiCurating = false;
          state.pendingStandbyAiAutoPlay = false;
          state.sonicBridgeAutoPlay = false;
          state.aiCurateTimeoutId = null;
        }
      }, 25000);
    } else if (act === 'search') {
      if (!msgObj.params || typeof msgObj.params !== 'object') {
        msgObj.params = {};
      }
      if (!msgObj.request_id && !msgObj.params.request_id) {
        state.searchReqSeq = (state.searchReqSeq || 0) + 1;
      }
      const reqId = msgObj.request_id || msgObj.params.request_id || state.searchReqSeq;
      msgObj.request_id = reqId;
      msgObj.params.request_id = reqId;
    }
    if (
      act === 'play_playlist' ||
      act === 'play_album' ||
      act === 'play_album_tracks' ||
      act === 'play_station' ||
      act === 'play_recent' ||
      act === 'play_recent_tracks'
    ) {
      state.activeAiCuratedTitle = '';
      state.activeAiCuratedPrompt = '';
    }
    if (act === 'play' || act.startsWith('play_') || act.includes('play') || act === 'next' || act === 'previous') {
      state.lastClientCommandAt = Date.now();
      syncSilentAudio(true);
    } else if (act === 'pause' || act === 'stop') {
      state.lastClientCommandAt = Date.now();
      syncSilentAudio(false);
    }
    socket.send(JSON.stringify(msgObj));
    return true;
  }

// === MODULE: 04-server-message-dispatcher.js ===
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

// === MODULE: 05-player-state-sync.js ===
  function updatePlayerState(data) {
    if (!data) return;

    clearTransportLoading();

    const oldTrack = state.track;
    const newTrack = data.track || null;
    const isNewTrack = Boolean(
      (newTrack && (!oldTrack || newTrack.id !== oldTrack.id || newTrack.name !== oldTrack.name || newTrack.artist !== oldTrack.artist)) ||
      (!newTrack && oldTrack)
    );

    const incomingState = data.player_state || data.playerState || 'stopped';
    const incomingTrack = data.track || null;
    const incomingSig = (incomingTrack && incomingTrack.name) ? `${incomingTrack.name}:${incomingTrack.artist || ''}` : '';
    const isRadioNow = Boolean(data.is_radio || data.isRadio || (data.playlist && data.playlist.includes('Станция')));
    state.isRadio = isRadioNow;

    if (incomingState !== 'playing') {
      state.pendingPauseUntil = 0;
    }

    if (state.isAiCurating) {
      // Do not dismiss the busy spinner while the Mac is still generating the AI selection
    } else if (state.waitingForPlayback) {
      // We are waiting for a newly launched track/queue to start.
      // Do NOT dismiss spinner if player is still reporting the OLD track!
      const hasTrackChanged = Boolean(isNewTrack && incomingSig && incomingSig !== state.waitingTrackSignature);
      const matchesExpectedTrack = Boolean(
        state.waitingExpectedTrackName &&
        incomingTrack &&
        incomingTrack.name &&
        incomingTrack.name.trim().toLowerCase() === state.waitingExpectedTrackName
      );
      const isTargetPlaying = Boolean(
        state.waitingTargetName &&
        !state.waitingTrackSignature &&
        ((data.playlist && data.playlist.toLowerCase().includes(state.waitingTargetName.toLowerCase())) ||
         (incomingTrack && incomingTrack.name && incomingTrack.name.toLowerCase().includes(state.waitingTargetName.toLowerCase())))
      );
      const elapsedWaitMs = Date.now() - (state.waitingStartTime || 0);
      const hasWaitedEnough = state.waitingTrackSignature ? (elapsedWaitMs > 6000) : (elapsedWaitMs > 600);
      if ((incomingState === 'playing' && (hasTrackChanged || matchesExpectedTrack || isTargetPlaying || hasWaitedEnough)) || (isRadioNow && (state.isLaunchingStation || state.waitingIsStation))) {
        state.pendingPlayUntil = 0;
        state.pendingPauseUntil = 0;
        state.playerState = 'playing';
        state.waitingForPlayback = false;
        state.waitingTrackSignature = null;
        state.waitingExpectedTrackName = null;
        state.waitingIsStation = false;
        state.isLaunchingStation = false;
        if (state.stationLaunchTimeout) {
          clearTimeout(state.stationLaunchTimeout);
          state.stationLaunchTimeout = null;
        }
        setUIBusy(false);
      }
    } else if (state.pendingPauseUntil && Date.now() < state.pendingPauseUntil && incomingState === 'playing') {
      state.playerState = 'paused';
    } else if (incomingState === 'playing' || (isRadioNow && (state.isLaunchingStation || state.waitingIsStation))) {
      state.pendingPlayUntil = 0;
      state.playerState = 'playing';
      if (state.isLaunchingStation) {
        state.isLaunchingStation = false;
        if (state.stationLaunchTimeout) {
          clearTimeout(state.stationLaunchTimeout);
          state.stationLaunchTimeout = null;
        }
      }
    } else if (state.pendingPlayUntil && Date.now() < state.pendingPlayUntil) {
      // Keep optimistic playing state while stream is starting up
      state.playerState = 'playing';
    } else {
      state.playerState = incomingState;
    }
    state.playbackState = state.playerState;
    try {
      localStorage.setItem('amr_last_was_playing', String(state.playbackState === 'playing'));
    } catch (_) {}

    // Dynamic initial view: on first player state / status message after initial page load
    if (!state.initialViewSelected) {
      state.initialViewSelected = true;
      if (isDesktopLayout()) {
        const detailOpen = Boolean(
          (dom.playlistDetailPane && !dom.playlistDetailPane.classList.contains('hidden')) ||
          (dom.libraryArtistDetailPane && !dom.libraryArtistDetailPane.classList.contains('hidden'))
        );
        switchDesktopTab(state.desktopActiveTab || 'home', detailOpen);
      } else {
        const desiredMobileView = state.playbackState === 'playing' ? 'view-now-playing' : 'view-home';
        if (state.activeView !== desiredMobileView) {
          switchMobileView(desiredMobileView);
        } else if (desiredMobileView === 'view-home') {
          loadTrends();
        }
      }
    }

    state.duration = Number(data.duration) || 0;
    const reportedPos = Math.max(0, Number(data.position) || 0);
    if (data.is_buffering !== undefined || data.isBuffering !== undefined) {
      state.isBuffering = Boolean(data.is_buffering !== undefined ? data.is_buffering : data.isBuffering);
    } else if (state.playerState !== 'playing' || reportedPos > 0.08) {
      state.isBuffering = false;
    }
    if (data.is_stream_stalled !== undefined || data.isStreamStalled !== undefined) {
      state.isStreamStalled = Boolean(data.is_stream_stalled !== undefined ? data.is_stream_stalled : data.isStreamStalled);
    } else if (state.playerState !== 'playing' || reportedPos > 0.08) {
      state.isStreamStalled = false;
    }
    const rawStagingBuffer = data.is_staging_buffer !== undefined ? data.is_staging_buffer : data.isStagingBuffer;
    if (rawStagingBuffer !== undefined) {
      state.isStagingBuffer = Boolean(rawStagingBuffer) && state.playerState === 'playing' && reportedPos <= 0.08;
    } else if (state.playerState !== 'playing' || reportedPos > 0.08 || !state.isBuffering) {
      state.isStagingBuffer = false;
    }
    const rawLoadingStage = data.loading_stage !== undefined ? data.loading_stage : data.loadingStage;
    if (state.playerState !== 'playing' || (!state.isBuffering && !state.isStagingBuffer) || reportedPos > 0.08) {
      state.loadingStage = null;
      state.loadingStartedAtMs = 0;
    } else {
      const nextStage = state.isStagingBuffer ? 'buffer' : (rawLoadingStage || 'cloud');
      if (isNewTrack || !state.loadingStartedAtMs || (nextStage === 'buffer' && state.loadingStage !== 'buffer')) {
        state.loadingStartedAtMs = Date.now();
      }
      state.loadingStage = nextStage;
    }

    if (isNewTrack) {
      state.hasStartedAdvancingForTrack = reportedPos > 0.08;
      state.lastSyncPos = reportedPos;
      state.position = reportedPos;
      state.lastSyncTime = performance.now();
      state.lastSyncPerf = state.lastSyncTime;
      if (!state.isScrubbing) {
        updateScrubberUI(reportedPos, state.duration);
      }
    } else if (!state.isScrubbing) {
      if (reportedPos > 0.08) {
        state.hasStartedAdvancingForTrack = true;
      }
      const now = performance.now();
      const waitingForFirstAudioFrame = state.isBuffering || (!state.hasStartedAdvancingForTrack && reportedPos <= 0.08);
      if (state.playerState !== 'playing' || waitingForFirstAudioFrame) {
        state.lastSyncPos = reportedPos;
        state.position = reportedPos;
        state.lastSyncTime = now;
        state.lastSyncPerf = now;
        updateScrubberUI(reportedPos, state.duration);
      } else {
        const predictedPos = Math.min(
          state.duration,
          state.lastSyncPos + (now - state.lastSyncTime) / 1000
        );
        const diff = reportedPos - predictedPos;
        if (Math.abs(diff) > 4.0 || (reportedPos < 1.0 && predictedPos > 3.0)) {
          // Explicit seek or track skip/restart: sync immediately
          state.lastSyncPos = reportedPos;
          state.position = reportedPos;
          state.lastSyncTime = now;
          state.lastSyncPerf = now;
          updateScrubberUI(reportedPos, state.duration);
        } else {
          // Continuous smooth drift synchronization (Phase-Locked Loop):
          // Smoothly absorb clock drift without ever causing a visible jump/jitter.
          // By applying a 15% damping correction per broadcast, client clock matches
          // server clock within a fraction of a second without jitter.
          state.lastSyncPos = predictedPos + diff * 0.15;
          state.position = state.lastSyncPos;
          state.lastSyncTime = now;
          state.lastSyncPerf = now;
        }
      }
    }

    const incomingShuffle = isRadioNow ? false : Boolean(data.shuffle);
    if (isRadioNow) {
      state.shuffle = false;
      state.pendingShuffleUntil = 0;
    } else if (!state.pendingShuffleUntil || Date.now() >= state.pendingShuffleUntil) {
      state.shuffle = incomingShuffle;
    } else if (incomingShuffle === state.shuffle) {
      state.pendingShuffleUntil = 0;
    }

    let incomingRepeat = normalizeRepeatMode(data.repeat || data.repeat_mode || data.repeatMode || 'off');
    if (isRadioNow && incomingRepeat === 'all') {
      incomingRepeat = 'off';
    }
    if (!state.pendingRepeatUntil || Date.now() >= state.pendingRepeatUntil) {
      state.repeatMode = incomingRepeat;
    } else if (incomingRepeat === state.repeatMode) {
      state.pendingRepeatUntil = 0;
    }
    if (isRadioNow && state.repeatMode === 'all') {
      state.repeatMode = 'off';
      state.pendingRepeatUntil = 0;
    }
    state.audioQuality = data.audio_quality || data.audioQuality || 'Lossless (ALAC 24-bit/48kHz)';
    if (newTrack && state.pendingFavoriteUntil && Date.now() < state.pendingFavoriteUntil) {
      const incomingKey = `${newTrack.artist || ''}|${newTrack.name || ''}`;
      if (state.pendingFavoriteTrackKey === incomingKey) {
        newTrack.favorited = state.pendingFavoriteValue;
      }
    }
    state.track = newTrack;
    state.currentTrackId = (newTrack && (newTrack.id || newTrack.persistent_id || newTrack.numeric_id)) || 0;

    if (data.audio_device_name !== undefined || data.audioDeviceName !== undefined) {
      state.audioDeviceName = data.audio_device_name || data.audioDeviceName || '';
    }
    if (data.audio_device_sample_rate !== undefined || data.audioDeviceSampleRate !== undefined) {
      state.audioDeviceSampleRate = Number(data.audio_device_sample_rate || data.audioDeviceSampleRate) || 44100;
    }
    if (data.audio_device_bit_depth !== undefined || data.audioDeviceBitDepth !== undefined) {
      state.audioDeviceBitDepth = Number(data.audio_device_bit_depth || data.audioDeviceBitDepth) || 24;
    }
    if (data.is_bit_perfect !== undefined || data.isBitPerfect !== undefined) {
      state.isBitPerfect = data.is_bit_perfect !== undefined ? Boolean(data.is_bit_perfect) : Boolean(data.isBitPerfect);
    }
    if (data.is_clock_synced_dsp !== undefined || data.isClockSyncedDsp !== undefined) {
      state.isClockSyncedDsp = data.is_clock_synced_dsp !== undefined ? Boolean(data.is_clock_synced_dsp) : Boolean(data.isClockSyncedDsp);
    }
    if (data.dac_muting_guard_enabled !== undefined || data.isDacMutingGuardEnabled !== undefined) {
      state.dacMutingGuardEnabled = data.dac_muting_guard_enabled !== undefined ? Boolean(data.dac_muting_guard_enabled) : Boolean(data.isDacMutingGuardEnabled);
    }
    if (data.dac_muting_guard_ms !== undefined || data.dacMutingGuardMs !== undefined) {
      state.dacMutingGuardMs = Number(data.dac_muting_guard_ms || data.dacMutingGuardMs) || 100;
    }
    const prevDlnaActive = Boolean(state.isDlnaActive);
    if (data.is_dlna_active !== undefined || data.isDlnaActive !== undefined) {
      state.isDlnaActive = Boolean(data.is_dlna_active !== undefined ? data.is_dlna_active : data.isDlnaActive);
      try { localStorage.setItem('amr_is_dlna_active', String(state.isDlnaActive)); } catch (_) {}
    }
    const dlnaActiveChanged = (Boolean(state.isDlnaActive) !== prevDlnaActive);
    if (data.room_correction_active !== undefined || data.roomCorrectionActive !== undefined) {
      state.roomCorrectionActive = Boolean(data.room_correction_active !== undefined ? data.room_correction_active : data.roomCorrectionActive);
    }
    if (data.room_profile_name !== undefined || data.roomProfileName !== undefined) {
      state.roomProfileName = String(data.room_profile_name || data.roomProfileName || '');
    }
    if (data.late_night_drc_profile !== undefined || data.lateNightDrcProfile !== undefined) {
      const nextProf = String(data.late_night_drc_profile !== undefined ? data.late_night_drc_profile : data.lateNightDrcProfile || 'gentle');
      if (nextProf === 'gentle' || nextProf === 'concert') {
        state.lateNightDrcProfile = nextProf;
      }
    }
    if (data.late_night_drc_enabled !== undefined || data.lateNightDrcEnabled !== undefined) {
      state.lateNightDrcEnabled = Boolean(data.late_night_drc_enabled !== undefined ? data.late_night_drc_enabled : data.lateNightDrcEnabled);
    }
    if (data.late_night_drc_mode !== undefined || data.lateNightDrcMode !== undefined) {
      const nextDrc = String(data.late_night_drc_mode !== undefined ? data.late_night_drc_mode : data.lateNightDrcMode || 'off');
      state.lateNightDrcMode = nextDrc;
      if (nextDrc === 'gentle' || nextDrc === 'concert') {
        state.lateNightDrcProfile = nextDrc;
        if (data.late_night_drc_enabled === undefined && data.lateNightDrcEnabled === undefined) {
          state.lateNightDrcEnabled = true;
        }
      } else if (data.late_night_drc_enabled === undefined && data.lateNightDrcEnabled === undefined) {
        state.lateNightDrcEnabled = false;
      }
    } else if (data.late_night_drc_enabled !== undefined || data.lateNightDrcEnabled !== undefined || data.late_night_drc_profile !== undefined || data.lateNightDrcProfile !== undefined) {
      state.lateNightDrcMode = state.lateNightDrcEnabled ? (state.lateNightDrcProfile || 'gentle') : 'off';
    }
    if (data.late_night_drc_gain_db !== undefined || data.lateNightDrcGainDb !== undefined) {
      state.lateNightDrcGainDb = Number(data.late_night_drc_gain_db !== undefined ? data.late_night_drc_gain_db : data.lateNightDrcGainDb) || 0;
    }
    syncLateNightBadgeOnly();
    if (data.mastering_declip_mode !== undefined || data.masteringDeclipMode !== undefined) {
      const nextDc = String(data.mastering_declip_mode !== undefined ? data.mastering_declip_mode : data.masteringDeclipMode || 'off');
      state.masteringDeclipMode = (nextDc === 'auto' || nextDc === 'gentle' || nextDc === 'studio') ? nextDc : 'off';
    }
    if (data.mastering_declip_restored_db !== undefined || data.masteringDeclipRestoredDb !== undefined) {
      state.masteringDeclipRestoredDb = Number(data.mastering_declip_restored_db !== undefined ? data.mastering_declip_restored_db : data.masteringDeclipRestoredDb) || 0;
    }
    if (data.mastering_deesser_mode !== undefined || data.masteringDeesserMode !== undefined) {
      const nextDe = String(data.mastering_deesser_mode !== undefined ? data.mastering_deesser_mode : data.masteringDeesserMode || 'off');
      state.masteringDeesserMode = (nextDe === 'gentle' || nextDe === 'vocal') ? nextDe : 'off';
    }
    if (data.mastering_deesser_gain_db !== undefined || data.masteringDeesserGainDb !== undefined) {
      state.masteringDeesserGainDb = Number(data.mastering_deesser_gain_db !== undefined ? data.mastering_deesser_gain_db : data.masteringDeesserGainDb) || 0;
    }
    syncMasteringRestorationBadgesOnly();
    if (data.dsp_mode !== undefined || data.dspMode !== undefined) {
      state.dspMode = data.dsp_mode || data.dspMode || 'passthrough';
    }
    if (data.dsp_badge !== undefined || data.dspBadge !== undefined) {
      state.dspBadge = data.dsp_badge || data.dspBadge || '';
    }
    if (data.dsp_profile !== undefined || data.dspProfile !== undefined) {
      state.dspProfile = data.dsp_profile || data.dspProfile || '7EC-Balanced';
    }
    if (data.dsp_output_sample_rate !== undefined || data.dspOutputSampleRate !== undefined) {
      state.dspOutputSampleRate = Number(data.dsp_output_sample_rate || data.dspOutputSampleRate) || 0;
    }
    if (data.dsp_dop_carrier_rate !== undefined || data.dspDoPCarrierRate !== undefined) {
      state.dspDoPCarrierRate = Number(data.dsp_dop_carrier_rate || data.dspDoPCarrierRate) || 0;
    }
    if (data.dsp_is_hog_mode !== undefined || data.dspIsHogMode !== undefined) {
      state.dspIsHogMode = Boolean(data.dsp_is_hog_mode !== undefined ? data.dsp_is_hog_mode : data.dspIsHogMode);
    }
    if (data.dsp_is_integer_mode !== undefined || data.dspIsIntegerMode !== undefined) {
      state.dspIsIntegerMode = Boolean(data.dsp_is_integer_mode !== undefined ? data.dsp_is_integer_mode : data.dspIsIntegerMode);
    }
    if (data.dsp_cpu_load_percent !== undefined || data.dspCpuLoadPercent !== undefined) {
      state.dspCpuLoadPercent = Number(data.dsp_cpu_load_percent !== undefined ? data.dsp_cpu_load_percent : data.dspCpuLoadPercent) || 0;
    }
    if (data.dsp_ring_buffer_fill_percent !== undefined || data.dspRingBufferFillPercent !== undefined) {
      state.dspRingBufferFillPercent = Number(data.dsp_ring_buffer_fill_percent !== undefined ? data.dsp_ring_buffer_fill_percent : data.dspRingBufferFillPercent) || 0;
    }
    const hasTrackSwitched = Boolean(
      oldTrack && newTrack && (newTrack.name !== oldTrack.name || newTrack.artist !== oldTrack.artist)
    );
    const incomingSa = data.spectral_analysis || data.spectralAnalysis;
    if (hasTrackSwitched) {
      spectralPollTickCount = 0;
      const prevEnabled = incomingSa && incomingSa.is_enabled !== undefined
        ? Boolean(incomingSa.is_enabled)
        : (state.spectralAnalysis ? (state.spectralAnalysis.is_enabled !== false && state.spectralAnalysis.isEnabled !== false) : true);
      state.spectralAnalysis = Object.assign({}, incomingSa || {}, {
        is_enabled: prevEnabled,
        verdict: (incomingSa && (incomingSa.is_cached || incomingSa.isCached) && incomingSa.verdict) ? incomingSa.verdict : (prevEnabled ? 'analyzing' : 'disabled'),
        analyzed_frames_count: 0
      });
    } else if (incomingSa) {
      state.spectralAnalysis = incomingSa;
    }

    if (data.lock_volume_100 !== undefined) {
      state.lockVolume100 = Boolean(data.lock_volume_100);
      try { localStorage.setItem('amr_lock_volume_100', String(state.lockVolume100)); } catch (e) {}
    } else if (data.isVolumeLockedTo100 !== undefined) {
      state.lockVolume100 = Boolean(data.isVolumeLockedTo100);
      try { localStorage.setItem('amr_lock_volume_100', String(state.lockVolume100)); } catch (e) {}
    }

    if (data.amp_volume_control !== undefined) {
      state.ampVolumeControlEnabled = Boolean(data.amp_volume_control) && state.lockVolume100;
      try { localStorage.setItem('amr_amp_volume_control', String(state.ampVolumeControlEnabled)); } catch (_) {}
    } else if (!state.lockVolume100) {
      state.ampVolumeControlEnabled = false;
      try { localStorage.setItem('amr_amp_volume_control', 'false'); } catch (_) {}
    }
    if (data.amp_brand_name !== undefined && data.amp_brand_name) {
      state.ampBrandName = String(data.amp_brand_name);
      try { localStorage.setItem('amr_amp_brand_name', state.ampBrandName); } catch (_) {}
    }
    if (data.amp_max_volume !== undefined && Number(data.amp_max_volume) > 0) {
      state.ampMaxVolume = Number(data.amp_max_volume);
      try { localStorage.setItem('amr_amp_max_volume', String(state.ampMaxVolume)); } catch (_) {}
    }
    const prevVol = state.volume;
    const prevMute = state.ampMuted;
    if (data.amp_muted !== undefined) {
      state.ampMuted = Boolean(data.amp_muted);
      try { localStorage.setItem('amr_amp_muted', String(state.ampMuted)); } catch (_) {}
    }
    if (data.amp_connected !== undefined) {
      state.ampConnected = Boolean(data.amp_connected);
    }
    if (data.amp_volume !== undefined && data.amp_volume !== null) {
      state.ampVolume = Math.max(0, Math.min(state.ampMaxVolume || 100, Number(data.amp_volume)));
    }
    if (data.amp_soundcheck_enabled !== undefined) {
      state.ampSoundCheckEnabled = Boolean(data.amp_soundcheck_enabled);
    }
    if (data.amp_soundcheck_gain_db !== undefined) {
      state.ampSoundCheckGainDb = data.amp_soundcheck_gain_db !== null ? Number(data.amp_soundcheck_gain_db) : null;
    }
    if (data.amp_soundcheck_offset !== undefined) {
      state.ampSoundCheckOffset = data.amp_soundcheck_offset !== null ? Number(data.amp_soundcheck_offset) : 0;
    }
    if (data.amp_base_volume !== undefined && data.amp_base_volume !== null) {
      state.ampBaseVolume = Number(data.amp_base_volume);
    }

    const maxVol = (state.lockVolume100 && state.ampVolumeControlEnabled) ? (state.ampMaxVolume || 80) : 100;
    if (data.volume !== undefined && !state.isDraggingVolume) {
      state.volume = Math.max(0, Math.min(maxVol, Number(data.volume)));
      try { localStorage.setItem('amr_last_volume', String(state.volume)); } catch (_) {}
      if (state.volume >= 5) {
        state.previousVolume = state.volume;
      }
    }
    if (!state.isDraggingVolume && !(state.lockVolume100 && !state.ampVolumeControlEnabled) && state.initialViewSelected && (state.volume !== prevVol || state.ampMuted !== prevMute)) {
      triggerStandbyVolumePulse();
    }

    if (dlnaActiveChanged) {
      if (state.lastDspSettings && typeof state.lastDspSettings === 'object') {
        state.lastDspSettings = Object.assign({}, state.lastDspSettings, { is_dlna_active: state.isDlnaActive });
        updateDSPSettingsUI(state.lastDspSettings);
      } else {
        applyDeviceCapabilityPermissionsUI();
      }
    }

    renderNowPlaying();
    if (dom.qualityModal && !dom.qualityModal.classList.contains('hidden')) {
      updateSignalPathDetails();
    }
  }

  function formatTime(seconds) {
    if (isNaN(seconds) || seconds < 0) return '0:00';
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
  }

  function getArtworkSrc(track) {
    if (!track) return 'apple-touch-icon.svg';
    if (track.artworkUrl && track.artworkUrl.length > 5) {
      return appendDeviceIdToUrl(track.artworkUrl);
    }
    if (track.artwork_url && track.artwork_url.length > 5) {
      return appendDeviceIdToUrl(track.artwork_url);
    }
    if (track.artwork && track.artwork.length > 5) {
      return appendDeviceIdToUrl(track.artwork);
    }
    if (track.artwork_data_base64) {
      return `data:image/jpeg;base64,${track.artwork_data_base64}`;
    }
    if (track.is_local && track.id && Number(track.id) > 0) {
      return appendDeviceIdToUrl(`/api/artwork/track?id=${track.id}`);
    }
    if (track.name) {
      const q = new URLSearchParams();
      q.set('name', track.name);
      if (track.artist) q.set('artist', track.artist);
      if (track.album) q.set('album', track.album);
      return appendDeviceIdToUrl(`/api/artwork/search?${q.toString()}`);
    }
    if (track.id && Number(track.id) > 0) {
      return appendDeviceIdToUrl(`/api/artwork/track?id=${track.id}`);
    }
    return appendDeviceIdToUrl('/api/artwork');
  }

// === MODULE: 06-ambient-backdrop-and-artwork.js ===
  // ==========================================================================
  // Apple TV Style Dynamic Blurred Ambient Gradient Background Manager
  // ==========================================================================
  const AmbientBackgroundManager = {
    activeLayer: 'a', // 'a' or 'b'
    currentPaletteKey: '',
    lastRequestedPaletteUrl: '',
    serverPaletteAppliedForUrl: '',
    offscreenCanvas: null,
    offscreenCtx: null,

    init() {
      if (this.offscreenCanvas) return;
      this.offscreenCanvas = document.createElement('canvas');
      this.offscreenCanvas.width = 32;
      this.offscreenCanvas.height = 32;
      this.offscreenCtx = this.offscreenCanvas.getContext('2d', { willReadFrequently: true });
    },

    rgbToHsv(r, g, b) {
      const rf = r / 255;
      const gf = g / 255;
      const bf = b / 255;
      const max = Math.max(rf, gf, bf);
      const min = Math.min(rf, gf, bf);
      const d = max - min;
      let h = 0;
      if (d > 0.0001) {
        if (max === rf) h = 60 * (((gf - bf) / d) % 6);
        else if (max === gf) h = 60 * ((bf - rf) / d + 2);
        else h = 60 * ((rf - gf) / d + 4);
        if (h < 0) h += 360;
      }
      const s = max <= 0.0001 ? 0 : d / max;
      return { h, s, v: max };
    },

    hsvToRgb(h, s, v) {
      const cleanH = ((h % 360) + 360) % 360;
      const c = v * s;
      const x = c * (1 - Math.abs(((cleanH / 60) % 2) - 1));
      const m = v - c;
      let r1 = 0, g1 = 0, b1 = 0;
      if (cleanH < 60) { r1 = c; g1 = x; }
      else if (cleanH < 120) { r1 = x; g1 = c; }
      else if (cleanH < 180) { g1 = c; b1 = x; }
      else if (cleanH < 240) { g1 = x; b1 = c; }
      else if (cleanH < 300) { r1 = x; b1 = c; }
      else { r1 = c; b1 = x; }
      return [
        Math.round((r1 + m) * 255),
        Math.round((g1 + m) * 255),
        Math.round((b1 + m) * 255)
      ];
    },

    hueDistance(h1, h2) {
      const diff = Math.abs(h1 - h2) % 360;
      return diff > 180 ? 360 - diff : diff;
    },

    // Extract 16 spatial perimeter zones + distinct chromatic clusters for WLED DDP
    extractWledZones(img) {
      this.init();
      const ctx = this.offscreenCtx;
      if (!ctx) return [[250, 35, 59], [121, 40, 202], [28, 140, 220], [255, 107, 139]];

      try {
        ctx.clearRect(0, 0, 32, 32);
        ctx.drawImage(img, 0, 0, 32, 32);
        const imgData = ctx.getImageData(0, 0, 32, 32).data;

        // 1. Collect distinct chromatic accent clusters across the whole cover
        const candidates = [];
        for (let i = 0; i < imgData.length; i += 16) {
          const r = imgData[i], g = imgData[i + 1], b = imgData[i + 2], a = imgData[i + 3];
          if (a < 128) continue;
          const hsv = this.rgbToHsv(r, g, b);
          if (hsv.v < 0.08) continue;
          const score = Math.pow(hsv.s, 0.7) * Math.pow(hsv.v, 0.5);
          candidates.push({ r, g, b, h: hsv.h, s: hsv.s, v: hsv.v, score });
        }
        candidates.sort((a, b) => b.score - a.score);

        const distinctAccents = [];
        for (const c of candidates) {
          if (distinctAccents.length >= 6) break;
          if (distinctAccents.every(ex => this.hueDistance(ex.h, c.h) >= 32)) {
            distinctAccents.push(c);
          }
        }
        if (distinctAccents.length === 0 && candidates.length > 0) {
          distinctAccents.push(candidates[0]);
        }

        // 2. Sample 16 spatial perimeter boxes around the 32x32 cover:
        // 0..3: Left edge (bottom -> top)
        // 4..11: Top edge (left -> right)
        // 12..15: Right edge (top -> bottom)
        const boxes = [
          [0, 24, 6, 8], [0, 16, 6, 8], [0, 8, 6, 8], [0, 0, 6, 8],
          [0, 0, 4, 6], [4, 0, 4, 6], [8, 0, 4, 6], [12, 0, 4, 6],
          [16, 0, 4, 6], [20, 0, 4, 6], [24, 0, 4, 6], [28, 0, 4, 6],
          [26, 0, 6, 8], [26, 8, 6, 8], [26, 16, 6, 8], [26, 24, 6, 8]
        ];

        const zones = [];
        for (let z = 0; z < boxes.length; z++) {
          const [bx, by, bw, bh] = boxes[z];
          let bestSample = null;
          let sumR = 0, sumG = 0, sumB = 0, count = 0;

          for (let y = by; y < by + bh; y++) {
            for (let x = bx; x < bx + bw; x++) {
              const idx = (y * 32 + x) * 4;
              const r = imgData[idx], g = imgData[idx + 1], b = imgData[idx + 2];
              sumR += r; sumG += g; sumB += b; count++;
              const hsv = this.rgbToHsv(r, g, b);
              const score = hsv.s * 1.4 + hsv.v * 0.6;
              if (!bestSample || score > bestSample.score) {
                bestSample = { r, g, b, h: hsv.h, s: hsv.s, v: hsv.v, score };
              }
            }
          }

          let chosen = bestSample || {
            r: Math.round(sumR / Math.max(1, count)),
            g: Math.round(sumG / Math.max(1, count)),
            b: Math.round(sumB / Math.max(1, count)),
            ...this.rgbToHsv(sumR / Math.max(1, count), sumG / Math.max(1, count), sumB / Math.max(1, count))
          };

          // If this perimeter zone is dull/monotonous and we have distinct cover accents, weave them in!
          if ((chosen.s < 0.25 || z % 3 === 1) && distinctAccents.length > 1) {
            const acc = distinctAccents[z % distinctAccents.length];
            chosen = { ...acc };
          }

          const boostedS = chosen.s < 0.08 ? 0.85 : Math.min(1.0, Math.pow(chosen.s, 0.45) * 1.2);
          const boostedV = Math.min(1.0, Math.max(0.32, Math.pow(chosen.v, 0.8) * 1.15));
          zones.push(this.hsvToRgb(chosen.h, boostedS, boostedV));
        }

        return zones;
      } catch (e) {
        return [[250, 35, 59], [121, 40, 202], [28, 140, 220], [255, 107, 139]];
      }
    },

    // Extract 4 harmonic ambient colors from image
    extractPalette(img) {
      this.init();
      const ctx = this.offscreenCtx;
      if (!ctx) return this.getDefaultPalette();

      try {
        ctx.clearRect(0, 0, 32, 32);
        ctx.drawImage(img, 0, 0, 32, 32);
        const imgData = ctx.getImageData(0, 0, 32, 32).data;
        const colorSamples = [];

        for (let i = 0; i < imgData.length; i += 16) { // sample every 4th pixel
          const r = imgData[i];
          const g = imgData[i + 1];
          const b = imgData[i + 2];
          const a = imgData[i + 3];

          if (a < 128) continue;

          const max = Math.max(r, g, b) / 255;
          const min = Math.min(r, g, b) / 255;
          const lum = (max + min) / 2;

          // Skip pure black or blown out highlights for ambient background
          if (lum < 0.06 || lum > 0.94) continue;

          const delta = max - min;
          const sat = delta === 0 ? 0 : delta / (1 - Math.abs(2 * lum - 1));
          const hsv = this.rgbToHsv(r, g, b);

          colorSamples.push({ r, g, b, sat, lum, h: hsv.h });
        }

        if (colorSamples.length === 0) {
          return this.getDefaultPalette();
        }

        // Sort by saturation to prioritize vivid, rich hues
        colorSamples.sort((c1, c2) => c2.sat - c1.sat);

        // Pick 4 chromatically distinct colors when available
        const picked = [colorSamples[0]];
        for (const sample of colorSamples) {
          if (picked.length >= 4) break;
          if (picked.every(p => this.hueDistance(p.h, sample.h) >= 28)) {
            picked.push(sample);
          }
        }
        const vibrant = picked[0];
        const secondary = picked[1] || colorSamples[Math.floor(colorSamples.length * 0.35)] || vibrant;
        const tertiary = picked[2] || colorSamples[Math.floor(colorSamples.length * 0.70)] || secondary;
        const deep = picked[3] || colorSamples[colorSamples.length - 1] || tertiary;

        return [
          this.tuneColor(vibrant, 1.5, 0.52),
          this.tuneColor(secondary, 1.4, 0.46),
          this.tuneColor(tertiary, 1.35, 0.48),
          this.tuneColor(deep, 1.25, 0.36)
        ];
      } catch (err) {
        // Fallback for tainted canvas
        return this.getDefaultPalette();
      }
    },

    tuneColor(col, satMultiplier, targetLum) {
      let r = col.r;
      let g = col.g;
      let b = col.b;

      // Adjust brightness toward targetLum
      const currentLum = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
      const factor = currentLum > 0 ? targetLum / currentLum : 1.0;
      r = Math.min(255, Math.max(16, Math.round(r * factor)));
      g = Math.min(255, Math.max(16, Math.round(g * factor)));
      b = Math.min(255, Math.max(16, Math.round(b * factor)));

      // Boost saturation
      const avg = (r + g + b) / 3;
      r = Math.min(255, Math.max(0, Math.round(avg + (r - avg) * satMultiplier)));
      g = Math.min(255, Math.max(0, Math.round(avg + (g - avg) * satMultiplier)));
      b = Math.min(255, Math.max(0, Math.round(avg + (b - avg) * satMultiplier)));

      return `rgba(${r}, ${g}, ${b}, 0.85)`;
    },

    getDefaultPalette() {
      return [
        'rgba(50, 30, 85, 0.65)',
        'rgba(30, 55, 105, 0.60)',
        'rgba(75, 35, 65, 0.55)',
        'rgba(25, 70, 90, 0.50)'
      ];
    },

    updateFromImage(img, artUrl) {
      if (!dom.ambientBackdrop) return;
      if (!artUrl || artUrl === 'apple-touch-icon.svg') {
        this.clear();
        return;
      }

      // Request Apple Neural Engine Vision Saliency palette at most ONCE per artwork URL
      if (state.aiCuratorEnabled && this.lastRequestedPaletteUrl !== artUrl) {
        this.lastRequestedPaletteUrl = artUrl;
        send({
          action: 'get_artwork_palette',
          params: {
            url: artUrl,
            track_id: Number(state.currentTrackId || 0) || 0
          }
        });
      }

      // Do not overwrite an already-applied Vision ANE palette for this exact cover URL
      if (this.serverPaletteAppliedForUrl === artUrl) {
        return;
      }

      const palette = this.extractPalette(img);
      const paletteKey = palette.join('|');
      if (paletteKey === this.currentPaletteKey) return;
      this.currentPaletteKey = paletteKey;

      // Dual buffer swap: 'a' <-> 'b'
      const nextLayer = this.activeLayer === 'a' ? 'b' : 'a';
      const targetElem = nextLayer === 'a' ? dom.ambientLayerA : dom.ambientLayerB;
      const prevElem = this.activeLayer === 'a' ? dom.ambientLayerA : dom.ambientLayerB;

      if (targetElem) {
        targetElem.style.setProperty('--blob-1', palette[0]);
        targetElem.style.setProperty('--blob-2', palette[1]);
        targetElem.style.setProperty('--blob-3', palette[2]);
        targetElem.style.setProperty('--blob-4', palette[3]);

        targetElem.classList.add('visible');
      }

      if (prevElem) {
        prevElem.classList.remove('visible');
      }

      this.activeLayer = nextLayer;
      dom.ambientBackdrop.classList.add('active');

      // Extract 16 spatial perimeter zones for WLED DDP Ambilight ONLY when WLED is enabled
      const rgbColors = palette.map((rgbaStr) => {
        const m = rgbaStr.match(/(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/);
        return m ? [parseInt(m[1], 10), parseInt(m[2], 10), parseInt(m[3], 10)] : [250, 35, 59];
      });
      // Only send fallback client-canvas WLED zones when Mac Vision Neural Engine palette is disabled;
      // otherwise Mac server authoritatively applies the Vision Saliency cover palette without dual-source flicker.
      if (state.wledEnabled && !state.aiCuratorEnabled) {
        const wledZones = this.extractWledZones(img);
        send({
          action: 'update_wled_palette',
          params: { colors: wledZones.length >= 4 ? wledZones : rgbColors }
        });
      }
      const standbyBg = document.getElementById('standby-ambient-bg');
      if (standbyBg && rgbColors.length >= 3) {
        this.applyStandbyAmbientColors(rgbColors);
      }
    },

    lastStandbyBgKey: '',
    applyStandbyAmbientColors(rgbColors) {
      const standbyBg = document.getElementById('standby-ambient-bg');
      if (!standbyBg || !Array.isArray(rgbColors) || rgbColors.length < 3) return;
      const [c0, c1, c2] = rgbColors;
      const bgKey = `${c0[0]},${c0[1]},${c0[2]}|${c1[0]},${c1[1]},${c1[2]}|${c2[0]},${c2[1]},${c2[2]}`;
      if (bgKey === this.lastStandbyBgKey) return;
      this.lastStandbyBgKey = bgKey;
      standbyBg.style.background = `
        radial-gradient(circle at 24% 48%, rgba(${c0[0]}, ${c0[1]}, ${c0[2]}, 0.38), transparent 62%),
        radial-gradient(circle at 78% 32%, rgba(${c1[0]}, ${c1[1]}, ${c1[2]}, 0.30), transparent 65%),
        radial-gradient(circle at 60% 82%, rgba(${c2[0]}, ${c2[1]}, ${c2[2]}, 0.24), transparent 68%),
        #040406
      `;
      const rtaBackdrop = document.getElementById('standby-rta-backdrop');
      if (rtaBackdrop) {
        const br = Math.min(255, Math.round(c0[0] * 0.65 + 110));
        const bg = Math.min(255, Math.round(c0[1] * 0.65 + 110));
        const bb = Math.min(255, Math.round(c0[2] * 0.65 + 110));
        rtaBackdrop.style.setProperty('--rta-bar-rgb', `${br}, ${bg}, ${bb}`);
      }
    },

    applyServerPalette(data) {
      if (!data || data.status !== 'ok' || !Array.isArray(data.ambient_rgb) || data.ambient_rgb.length < 3) {
        return;
      }
      if (!dom.ambientBackdrop) return;
      const rgbList = data.ambient_rgb.map((arr) => [
        Math.max(0, Math.min(255, Number(arr[0]) || 30)),
        Math.max(0, Math.min(255, Number(arr[1]) || 30)),
        Math.max(0, Math.min(255, Number(arr[2]) || 45))
      ]);
      while (rgbList.length < 4) {
        rgbList.push(rgbList[rgbList.length - 1]);
      }

      const tunedBlobs = [
        this.tuneColor({ r: rgbList[0][0], g: rgbList[0][1], b: rgbList[0][2] }, 1.35, 0.42),
        this.tuneColor({ r: rgbList[1][0], g: rgbList[1][1], b: rgbList[1][2] }, 1.25, 0.36),
        this.tuneColor({ r: rgbList[2][0], g: rgbList[2][1], b: rgbList[2][2] }, 1.30, 0.38),
        this.tuneColor({ r: rgbList[3][0], g: rgbList[3][1], b: rgbList[3][2] }, 1.20, 0.32)
      ];
      const serverKey = 'vision|' + tunedBlobs.join('|');
      this.serverPaletteAppliedForUrl = this.lastRequestedPaletteUrl || currentLoadedArtworkUrl || '';
      if (serverKey === this.currentPaletteKey) return;
      this.currentPaletteKey = serverKey;

      const nextLayer = this.activeLayer === 'a' ? 'b' : 'a';
      const targetElem = nextLayer === 'a' ? dom.ambientLayerA : dom.ambientLayerB;
      const prevElem = this.activeLayer === 'a' ? dom.ambientLayerA : dom.ambientLayerB;

      if (targetElem) {
        targetElem.style.setProperty('--blob-1', tunedBlobs[0]);
        targetElem.style.setProperty('--blob-2', tunedBlobs[1]);
        targetElem.style.setProperty('--blob-3', tunedBlobs[2]);
        targetElem.style.setProperty('--blob-4', tunedBlobs[3]);
        targetElem.classList.add('visible');
      }
      if (prevElem) {
        prevElem.classList.remove('visible');
      }
      this.activeLayer = nextLayer;
      dom.ambientBackdrop.classList.add('active');

      this.applyStandbyAmbientColors(rgbList);
    },

    clear() {
      if (!dom.ambientBackdrop) return;
      dom.ambientBackdrop.classList.remove('active');
      if (dom.ambientLayerA) dom.ambientLayerA.classList.remove('visible');
      if (dom.ambientLayerB) dom.ambientLayerB.classList.remove('visible');
      this.currentPaletteKey = '';
      this.lastRequestedPaletteUrl = '';
      this.serverPaletteAppliedForUrl = '';
    }
  };

  let currentLoadedArtworkUrl = '';
  function setPlayerArtwork(artUrl) {
    artUrl = artUrl ? appendDeviceIdToUrl(artUrl) : 'apple-touch-icon.svg';
    if (dom.playerArtwork.dataset.targetSrc === artUrl) {
      return;
    }
    dom.playerArtwork.dataset.targetSrc = artUrl;

    if (artUrl === 'apple-touch-icon.svg') {
      dom.playerArtwork.src = artUrl;
      dom.playerArtwork.style.opacity = '1';
      currentLoadedArtworkUrl = artUrl;
      if (dom.miniArt) {
        dom.miniArt.src = artUrl;
        dom.miniArt.style.opacity = '1';
      }
      AmbientBackgroundManager.clear();
      return;
    }

    // Immediately dim/fade the artwork elements so the old track's image NEVER lingers
    if (currentLoadedArtworkUrl && currentLoadedArtworkUrl !== artUrl) {
      dom.playerArtwork.style.opacity = '0';
      if (dom.miniArt) dom.miniArt.style.opacity = '0.3';
    }

    const applyLoadedImage = (loadedImg) => {
      if (dom.playerArtwork.dataset.targetSrc !== artUrl) return;
      dom.playerArtwork.src = artUrl;
      dom.playerArtwork.style.opacity = '1';
      currentLoadedArtworkUrl = artUrl;
      if (dom.miniArt) {
        dom.miniArt.src = artUrl;
        dom.miniArt.style.opacity = '1';
      }
      AmbientBackgroundManager.updateFromImage(loadedImg, artUrl);
    };

    const applyFallbackIcon = () => {
      if (dom.playerArtwork.dataset.targetSrc !== artUrl) return;
      dom.playerArtwork.src = 'apple-touch-icon.svg';
      dom.playerArtwork.style.opacity = '1';
      currentLoadedArtworkUrl = 'apple-touch-icon.svg';
      if (dom.miniArt) {
        dom.miniArt.src = 'apple-touch-icon.svg';
        dom.miniArt.style.opacity = '1';
      }
      AmbientBackgroundManager.clear();
    };

    // Only set crossOrigin='anonymous' for external http(s) URLs when client-side canvas readback is needed;
    // same-origin /api/artwork/... images are already non-tainted and omit CORS mode so cookies & auth work reliably.
    const isExternalHttp = /^https?:\/\//i.test(artUrl) && !artUrl.startsWith(window.location.origin);
    const useCors = isExternalHttp && (!state.aiCuratorEnabled || state.wledEnabled);

    const img = new Image();
    if (useCors) {
      img.crossOrigin = 'anonymous';
    }
    img.onload = () => applyLoadedImage(img);
    img.onerror = () => {
      // If Safari/WebKit cached a non-CORS response from a queue/standby <img>, retry once without crossOrigin
      if (useCors) {
        const retryImg = new Image();
        retryImg.onload = () => applyLoadedImage(retryImg);
        retryImg.onerror = applyFallbackIcon;
        retryImg.src = artUrl;
        return;
      }
      applyFallbackIcon();
    };
    img.src = artUrl;
  }

  let marqueeRafId = 0;

  function updateSingleTitleMarquee(el, forceRecalc = false) {
    if (!el) return;
    const text = el.textContent || '';
    if (!forceRecalc && el.dataset.marqueeText === text) {
      return;
    }
    const viewport = el.closest('.title-marquee-viewport') || el.parentElement;
    if (!viewport) return;

    const viewportWidth = Math.floor(viewport.clientWidth);
    if (viewportWidth <= 0) return;

    const sig = `${text}|${viewportWidth}`;
    if (!forceRecalc && el.dataset.marqueeSig === sig) {
      el.dataset.marqueeText = text;
      return;
    }
    el.dataset.marqueeSig = sig;
    el.dataset.marqueeText = text;

    el.classList.remove('is-marquee');
    viewport.classList.remove('is-marquee');
    el.style.removeProperty('--marquee-distance');
    el.style.removeProperty('--marquee-duration');

    // Measure true unconstrained single-line width across all browsers (including WebKit/Safari)
    el.style.display = 'inline-block';
    el.style.width = 'max-content';
    el.style.maxWidth = 'none';
    el.style.overflow = 'visible';
    el.style.textOverflow = 'clip';
    const textWidth = Math.ceil(el.getBoundingClientRect().width);
    el.style.display = '';
    el.style.width = '';
    el.style.maxWidth = '';
    el.style.overflow = '';
    el.style.textOverflow = '';

    const overflow = Math.ceil(textWidth - viewportWidth);

    if (overflow > 2) {
      // Extra padding so the last character clears the right-edge gradient mask completely
      const rightPad = Math.max(20, Math.round(viewportWidth * 0.055));
      const distance = -(overflow + rightPad);
      const duration = Math.max(7.0, Math.min(20.0, (Math.abs(distance) / 36) + 3.6));
      el.style.setProperty('--marquee-distance', `${distance}px`);
      el.style.setProperty('--marquee-duration', `${duration.toFixed(1)}s`);
      el.classList.add('is-marquee');
      viewport.classList.add('is-marquee');
    }
  }

  function refreshAllTitleMarquees(forceRecalc = false) {
    if (marqueeRafId) cancelAnimationFrame(marqueeRafId);
    marqueeRafId = requestAnimationFrame(() => {
      marqueeRafId = 0;
      const force = Boolean(forceRecalc === true);
      updateSingleTitleMarquee(dom.playerTitle, force);
      updateSingleTitleMarquee(dom.miniTitle, force);
      updateSingleTitleMarquee(document.getElementById('standby-title'), force);
    });
  }

  window.addEventListener('resize', () => refreshAllTitleMarquees(true));
  window.addEventListener('orientationchange', () => {
    setTimeout(() => refreshAllTitleMarquees(true), 120);
  });

// === MODULE: 07-now-playing-volume-and-haptics.js ===
  function renderNowPlaying() {
    const isPlaying = state.playerState === 'playing';
    const t = state.track;

    // Track Meta
    if (t) {
      const titleText = t.name || translateTextToEn('Без названия');
      const albumText = (t.album || '').trim();
      const artistText = t.artist || translateTextToEn('Неизвестный исполнитель');
      if (dom.playerTitle.textContent !== titleText) {
        dom.playerTitle.textContent = titleText;
      }
      dom.playerTitle.title = titleText;
      if (dom.playerArtist.textContent !== artistText) {
        dom.playerArtist.textContent = artistText;
      }
      if (dom.playerAlbum.textContent !== albumText) {
        dom.playerAlbum.textContent = albumText;
      }
      dom.playerAlbum.classList.toggle('clickable-album', Boolean(albumText));
      dom.playerAlbum.title = albumText ? `Перейти к альбому «${albumText}»` : '';
      if (dom.btnGoToAlbum) {
        dom.btnGoToAlbum.disabled = !albumText;
        dom.btnGoToAlbum.title = albumText ? `Перейти к альбому «${albumText}»` : 'Перейти к альбому';
      }
      if (dom.btnAiTrackVibe) {
        dom.btnAiTrackVibe.disabled = !t.name;
        dom.btnAiTrackVibe.classList.toggle('hidden', !state.aiCuratorEnabled);
        dom.btnAiTrackVibe.title = t.name
          ? translateTextToEn(`✨ ИИ-подбор по вайбу «${t.name}»`)
          : translateTextToEn('✨ ИИ-подбор по вайбу текущего трека');
      }
      const art = getArtworkSrc(t);
      setPlayerArtwork(art);
      dom.btnFavorite.classList.toggle('active', Boolean(t.favorited));
      if (dom.miniBtnFavorite) dom.miniBtnFavorite.classList.toggle('active', Boolean(t.favorited));

      // Mini Player sync
      if (dom.miniTitle.textContent !== titleText) {
        dom.miniTitle.textContent = titleText;
      }
      const miniArtistText = t.artist || 'Apple Music';
      if (dom.miniArtist.textContent !== miniArtistText) {
        dom.miniArtist.textContent = miniArtistText;
      }
    } else {
      const notPlayingText = translateTextToEn('Не играет');
      if (dom.playerTitle.textContent !== notPlayingText) {
        dom.playerTitle.textContent = notPlayingText;
      }
      dom.playerTitle.title = notPlayingText;
      if (dom.playerArtist.textContent !== 'Apple Music') {
        dom.playerArtist.textContent = 'Apple Music';
      }
      if (dom.playerAlbum.textContent !== '') {
        dom.playerAlbum.textContent = '';
      }
      dom.playerAlbum.classList.remove('clickable-album');
      dom.playerAlbum.title = '';
      if (dom.btnGoToAlbum) {
        dom.btnGoToAlbum.disabled = true;
        dom.btnGoToAlbum.title = translateTextToEn('Перейти к альбому');
      }
      if (dom.btnAiTrackVibe) {
        dom.btnAiTrackVibe.disabled = true;
        dom.btnAiTrackVibe.classList.toggle('hidden', !state.aiCuratorEnabled);
        dom.btnAiTrackVibe.title = translateTextToEn('✨ ИИ-подбор по вайбу текущего трека');
      }
      setPlayerArtwork('apple-touch-icon.svg');
      dom.btnFavorite.classList.remove('active');
      if (dom.miniBtnFavorite) dom.miniBtnFavorite.classList.remove('active');

      if (dom.miniTitle.textContent !== notPlayingText) {
        dom.miniTitle.textContent = notPlayingText;
      }
      if (dom.miniArtist.textContent !== 'Apple Music') {
        dom.miniArtist.textContent = 'Apple Music';
      }
    }

    // Play/Pause button icons
    if (isPlaying) {
      dom.iconPlay.classList.add('hidden');
      dom.iconPause.classList.remove('hidden');
      dom.miniIconPlay.classList.add('hidden');
      dom.miniIconPause.classList.remove('hidden');
    } else {
      dom.iconPlay.classList.remove('hidden');
      dom.iconPause.classList.add('hidden');
      dom.miniIconPlay.classList.remove('hidden');
      dom.miniIconPause.classList.add('hidden');
    }

    // Shuffle & Repeat buttons
    const isRadioMode = Boolean(state.isRadio);
    dom.btnShuffle.disabled = isRadioMode;
    dom.btnShuffle.classList.toggle('disabled-control', isRadioMode);
    dom.btnShuffle.classList.toggle('active', !isRadioMode && Boolean(state.shuffle));
    dom.btnShuffle.title = isRadioMode
      ? (IS_EN ? 'Shuffle unavailable on Radio' : 'Перемешивание недоступно для радио')
      : (state.shuffle
        ? (IS_EN ? 'Shuffle: On' : 'Перемешать: Вкл')
        : (IS_EN ? 'Shuffle: Off' : 'Перемешать'));

    const effectiveRepeat = (isRadioMode && state.repeatMode === 'all') ? 'off' : state.repeatMode;
    if (effectiveRepeat === 'one') {
      dom.btnRepeat.classList.add('active');
      dom.repeatBadge.classList.remove('hidden');
      dom.btnRepeat.title = IS_EN ? 'Repeat Mode: One Track (1)' : 'Повтор: Зациклен 1 трек';
    } else if (effectiveRepeat === 'all') {
      dom.btnRepeat.classList.add('active');
      dom.repeatBadge.classList.add('hidden');
      dom.btnRepeat.title = IS_EN ? 'Repeat Mode: Queue' : 'Повтор: Вся очередь';
    } else {
      dom.btnRepeat.classList.remove('active');
      dom.repeatBadge.classList.add('hidden');
      dom.btnRepeat.title = isRadioMode
        ? (IS_EN ? 'Repeat Mode: Off (tap to repeat track)' : 'Повтор трека: Выкл')
        : (IS_EN ? 'Repeat Mode: Off' : 'Режим повтора: Выкл');
    }

    // Audio Quality & Permanent DAC Badge Sync
    const dacText = formatDacPill(state.audioQuality);
    if (dom.audioQualityText) dom.audioQualityText.textContent = dacText;
    if (dom.desktopDacText) dom.desktopDacText.textContent = dacText;
    if (dom.mobileDacText) dom.mobileDacText.textContent = dacText;
    if (dom.modalSpecQuality) dom.modalSpecQuality.textContent = state.audioQuality;
    if (dom.modalSpecRate) {
      if (state.audioQuality.includes('192')) {
        dom.modalSpecRate.textContent = '192.0 кГц (Hi-Res Bit-Perfect)';
      } else if (state.audioQuality.includes('96')) {
        dom.modalSpecRate.textContent = '96.0 кГц (Hi-Res Bit-Perfect)';
      } else if (state.audioQuality.includes('48')) {
        dom.modalSpecRate.textContent = '48.0 кГц (Lossless Bit-Perfect)';
      } else if (state.audioQuality.includes('44.1')) {
        dom.modalSpecRate.textContent = '44.1 кГц (Lossless Bit-Perfect)';
      } else {
        dom.modalSpecRate.textContent = 'Автосинхронизация CoreAudio';
      }
    }
    if (typeof updateSignalPathDetails === 'function') {
      updateSignalPathDetails();
    }

    // Only update scrubber UI here if stopped, paused, or buffering at 0:00.
    // When actively playing, the 60fps scrubberAnimationLoop handles smooth rendering without jitter!
    if (!state.isScrubbing && (state.playerState !== 'playing' || !(state.duration > 0) || state.isBuffering || state.isStagingBuffer || (!state.hasStartedAdvancingForTrack && state.lastSyncPos <= 0.08))) {
      updateScrubberUI(state.lastSyncPos, state.duration);
    }
    syncTrackLoadingIndicatorUI();
    ensureScrubberLoopRunning();

    renderVolumeUI();
    renderCurrentQueueTrack(dom.queueCurrentTrack);
    if (typeof isStandbyQueueModalOpen === 'function' && isStandbyQueueModalOpen()) {
      renderStandbyQueueModal();
    }
    updateMediaSession();
    syncStandbyAndMotionCoverUI();
    syncCurrentTrackBookletAvailability();
    refreshAllTitleMarquees();
  }

  let standbyVolPulseTimer = null;
  let standbyVolLoupeTimer = null;

  function triggerStandbyVolumePulse() {
    if (!dom.standbyVolumeSection) return;
    dom.standbyVolumeSection.classList.add('vol-active-pulse');
    if (standbyVolPulseTimer) clearTimeout(standbyVolPulseTimer);
    standbyVolPulseTimer = setTimeout(() => {
      if (dom.standbyVolumeSection) {
        dom.standbyVolumeSection.classList.remove('vol-active-pulse');
      }
    }, 2200);
  }

  function showStandbyVolumeLoupe(autoHideMs = 0) {
    if (!dom.standbyVolumeSection) return;
    dom.standbyVolumeSection.classList.add('is-scrubbing', 'vol-active-pulse');
    if (dom.standbyVolLoupe) dom.standbyVolLoupe.classList.add('visible');
    if (standbyVolLoupeTimer) clearTimeout(standbyVolLoupeTimer);
    if (autoHideMs > 0) {
      standbyVolLoupeTimer = setTimeout(() => {
        hideStandbyVolumeLoupe();
      }, autoHideMs);
    }
  }

  function hideStandbyVolumeLoupe() {
    if (standbyVolLoupeTimer) {
      clearTimeout(standbyVolLoupeTimer);
      standbyVolLoupeTimer = null;
    }
    if (dom.standbyVolumeSection) {
      dom.standbyVolumeSection.classList.remove('is-scrubbing');
    }
    if (dom.standbyVolLoupe) {
      dom.standbyVolLoupe.classList.remove('visible');
    }
  }

  function updateStandbyLoupePosition(vol, pct, isMuted) {
    const cleanPct = isMuted ? 0 : Math.max(0, Math.min(100, pct));
    if (dom.standbyVolFill) {
      dom.standbyVolFill.style.width = `${cleanPct}%`;
    }
    if (dom.standbyVolThumb) {
      dom.standbyVolThumb.style.left = `${cleanPct}%`;
    }
    if (dom.standbyVolLoupe) {
      const clampedLoupeLeft = Math.max(8, Math.min(92, cleanPct));
      dom.standbyVolLoupe.style.left = `${clampedLoupeLeft}%`;
    }
    if (dom.standbyVolLoupeText) {
      dom.standbyVolLoupeText.textContent = (isMuted || vol === 0) ? 'MUTE' : `${vol}%`;
    }
  }

  function syncSignalPathAmpNode() {
    const isExtAmpMode = Boolean(state.lockVolume100 && state.ampVolumeControlEnabled);
    if (dom.signalConnectorAmp) {
      dom.signalConnectorAmp.classList.toggle('hidden', !isExtAmpMode);
    }
    if (dom.signalNodeAmp) {
      dom.signalNodeAmp.classList.toggle('hidden', !isExtAmpMode);
    }
    if (!isExtAmpMode) return;

    const brand = state.ampBrandName || (IS_EN ? 'Amplifier' : 'Усилитель');
    const maxVol = Math.max(1, Math.min(100, Number(state.ampMaxVolume) || 80));
    const vol = Math.max(0, Math.min(maxVol, Number(state.volume) || 0));

    if (dom.signalAmpDot) {
      dom.signalAmpDot.classList.toggle('active', Boolean(state.ampConnected));
    }
    if (dom.signalAmpName) {
      dom.signalAmpName.textContent = brand;
    }
    if (dom.signalAmpVolumeBadge) {
      dom.signalAmpVolumeBadge.textContent = state.ampMuted ? 'MUTE' : `${vol}%`;
    }
    if (dom.signalAmpDetails) {
      let scNote = '';
      if (state.ampSoundCheckEnabled && state.ampSoundCheckGainDb !== null && state.ampSoundCheckGainDb !== undefined && !isNaN(state.ampSoundCheckGainDb)) {
        const gainVal = Number(state.ampSoundCheckGainDb);
        const gainSign = gainVal >= 0 ? '+' : '';
        const offVal = Number(state.ampSoundCheckOffset) || 0;
        const offSign = offVal >= 0 ? '+' : '';
        const baseVol = state.ampBaseVolume !== undefined ? Number(state.ampBaseVolume) : vol;
        scNote = IS_EN
          ? ` • SoundCheck ${gainSign}${gainVal.toFixed(1)} dB (${offSign}${offVal}%, base ${baseVol}%)`
          : ` • SoundCheck ${gainSign}${gainVal.toFixed(1)} дБ (${offSign}${offVal}%, база ${baseVol}%)`;
      } else if (state.ampSoundCheckEnabled) {
        scNote = IS_EN ? ' • SoundCheck iTunNORM' : ' • SoundCheck iTunNORM';
      }
      dom.signalAmpDetails.textContent = state.ampConnected
        ? (IS_EN ? `TCP Volume Control • Cap ${maxVol}%${scNote}` : `Управление громкостью по TCP • Лимит до ${maxVol}%${scNote}`)
        : (IS_EN ? `Waiting for TCP connection • Cap ${maxVol}%${scNote}` : `Ожидание подключения по TCP • Лимит до ${maxVol}%${scNote}`);
    }
  }

  function renderVolumeUI() {
    const isExtAmpMode = Boolean(state.lockVolume100 && state.ampVolumeControlEnabled);
    const isDlnaHardwareVol = Boolean(state.isDlnaActive && !state.lockVolume100 && !isExtAmpMode);
    syncSignalPathAmpNode();

    if (state.lockVolume100 && !isExtAmpMode) {
      if (dom.volumeSection) dom.volumeSection.classList.add('hidden');
      if (dom.standbyVolumeSection) dom.standbyVolumeSection.classList.add('hidden');
      if (dom.playerBottomNotice) {
        dom.playerBottomNotice.textContent = state.isDlnaActive
          ? translateTextToEn('Сетевой вывод BluOS / DLNA (Bit-Perfect PCM • 100%)')
          : translateTextToEn('Прямой вывод CoreAudio (Bit-Perfect DAC • 100%)');
      }
      return;
    }

    if (dom.volumeSection) dom.volumeSection.classList.remove('hidden');
    if (dom.standbyVolumeSection) dom.standbyVolumeSection.classList.remove('hidden');

    if (isExtAmpMode) {
      const brand = state.ampBrandName || 'AMP';
      const maxVol = Math.max(1, Math.min(100, Number(state.ampMaxVolume) || 80));
      const vol = Math.max(0, Math.min(maxVol, Number(state.volume) || 0));
      const pct = Math.max(0, Math.min(100, (vol / maxVol) * 100));
      const labelStr = state.ampMuted ? `${brand} • MUTE` : `${brand} • ${vol}%`;

      if (dom.playerBottomNotice) {
        let scBadge = '';
        if (state.ampSoundCheckEnabled && state.ampSoundCheckGainDb !== null && state.ampSoundCheckGainDb !== undefined && !isNaN(state.ampSoundCheckGainDb)) {
          const g = Number(state.ampSoundCheckGainDb);
          scBadge = ` • SoundCheck ${g >= 0 ? '+' : ''}${g.toFixed(1)} дБ`;
        }
        dom.playerBottomNotice.textContent = state.ampConnected
          ? `Прямой вывод CoreAudio (Bit-Perfect 100% • Громкость: ${brand} TCP • макс. ${maxVol}%${scBadge})`
          : `Прямой вывод CoreAudio (Bit-Perfect 100% • Ожидание ${brand} TCP${scBadge})`;
      }
      if (dom.volumeInput) {
        dom.volumeInput.min = '0';
        dom.volumeInput.max = String(maxVol);
        if (!state.isDraggingVolume) {
          dom.volumeInput.value = String(vol);
        }
      }
      if (!state.isDraggingVolume) {
        if (dom.volumeTrackFill) {
          dom.volumeTrackFill.style.width = `${pct}%`;
        }
        if (dom.volumeThumb) {
          dom.volumeThumb.style.left = `${pct}%`;
        }
        if (dom.volumeLevelText) {
          dom.volumeLevelText.textContent = labelStr;
        }
      }
      if (dom.standbyVolumeInput) {
        dom.standbyVolumeInput.min = '0';
        dom.standbyVolumeInput.max = String(maxVol);
        if (!state.isDraggingVolume) {
          dom.standbyVolumeInput.value = String(vol);
        }
      }
      if (!state.isDraggingVolume) {
        updateStandbyLoupePosition(vol, pct, Boolean(state.ampMuted));
        if (dom.standbyVolumeText) {
          dom.standbyVolumeText.textContent = labelStr;
        }
        if (dom.standbyBtnVolumeMute) {
          dom.standbyBtnVolumeMute.classList.toggle('muted', Boolean(state.ampMuted || vol === 0));
        }
        updateVolumeIcon(state.ampMuted ? 0 : Math.round(pct));
      }
    } else {
      const labelStr = `${state.volume}%`;
      if (dom.playerBottomNotice) {
        dom.playerBottomNotice.textContent = isDlnaHardwareVol
          ? 'Сетевой вывод BluOS / DLNA (Bit-Perfect PCM 100% • Аппаратная громкость плеера)'
          : 'Прямой вывод CoreAudio (Регулируемая громкость)';
      }
      if (dom.volumeInput) {
        dom.volumeInput.max = '100';
        if (!state.isDraggingVolume) {
          dom.volumeInput.value = String(state.volume);
        }
      }
      if (!state.isDraggingVolume) {
        if (dom.volumeTrackFill) {
          dom.volumeTrackFill.style.width = `${state.volume}%`;
        }
        if (dom.volumeThumb) {
          dom.volumeThumb.style.left = `${state.volume}%`;
        }
        if (dom.volumeLevelText) {
          dom.volumeLevelText.textContent = labelStr;
        }
      }
      if (dom.standbyVolumeInput) {
        dom.standbyVolumeInput.min = '0';
        dom.standbyVolumeInput.max = '100';
        if (!state.isDraggingVolume) {
          dom.standbyVolumeInput.value = String(state.volume);
        }
      }
      if (!state.isDraggingVolume) {
        updateStandbyLoupePosition(state.volume, state.volume, state.volume === 0);
        if (dom.standbyVolumeText) {
          dom.standbyVolumeText.textContent = labelStr;
        }
        if (dom.standbyBtnVolumeMute) {
          dom.standbyBtnVolumeMute.classList.toggle('muted', state.volume === 0);
        }
        updateVolumeIcon(state.volume);
      }
    }
  }

  function updateVolumeIcon(vol) {
    const wave1 = dom.volumeSection ? dom.volumeSection.querySelector('#vol-wave-1') : null;
    const wave2 = dom.volumeSection ? dom.volumeSection.querySelector('#vol-wave-2') : null;
    const sbWave1 = document.getElementById('standby-vol-wave-1');
    const sbWave2 = document.getElementById('standby-vol-wave-2');
    const show1 = vol > 0 ? 'block' : 'none';
    const show2 = vol >= 50 ? 'block' : 'none';
    if (wave1) wave1.style.display = show1;
    if (wave2) wave2.style.display = show2;
    if (sbWave1) sbWave1.style.display = show1;
    if (sbWave2) sbWave2.style.display = show2;
  }

  // --- Tactile & Haptic Engine (Mobile Vibration API Only — Zero Audio/DAC Pulses) ---
  function triggerHaptic(type = 'light') {
    if (
      'vibrate' in navigator &&
      typeof navigator.vibrate === 'function' &&
      (navigator.maxTouchPoints || 0) > 0 &&
      window.matchMedia &&
      window.matchMedia('(hover: none) and (pointer: coarse)').matches
    ) {
      try {
        if (type === 'light') navigator.vibrate(15);
        else if (type === 'medium') navigator.vibrate(28);
        else if (type === 'heavy') navigator.vibrate(45);
        else if (type === 'toggle') navigator.vibrate([15, 30, 25]);
      } catch (e) {}
    }
  }

  // --- Silent Audio Loop for iOS Background & Lock Screen Keep-Alive ---
  let silentAudioEl = null;
  let silentAudioUnlocked = false;
  let mediaSessionHandlersBound = false;
  let mediaSessionPlatformActivated = false;
  let allowAmrMediaSessionMutation = false;

  if (typeof navigator !== 'undefined' && 'mediaSession' in navigator && navigator.mediaSession) {
    try {
      const msProto = Object.getPrototypeOf(navigator.mediaSession);
      const msTarget = (msProto && typeof msProto.setActionHandler === 'function') ? msProto : navigator.mediaSession;
      const nativeSetActionHandler = msTarget.setActionHandler;
      if (typeof nativeSetActionHandler === 'function' && !nativeSetActionHandler._amrGuarded) {
        const guardedSetActionHandler = function (action, handler) {
          if (!allowAmrMediaSessionMutation) return;
          return nativeSetActionHandler.call(this, action, handler);
        };
        guardedSetActionHandler._amrGuarded = true;
        msTarget.setActionHandler = guardedSetActionHandler;
      }
    } catch (_) {}
  }

  function isLockScreenAllowedNow() {
    if (!state.lockScreenControls) return false;
    if (state.deviceAuthChecked && !state.deviceAuthorized) return false;
    return true;
  }

  function attachSilentAudioListeners(el) {
    if (!el || el._amrListenersAttached) return;
    el._amrListenersAttached = true;

    let flushedAfterPlayingAdvance = false;

    const onAudioStateChange = (evt) => {
      if (evt && evt.type === 'playing') {
        flushedAfterPlayingAdvance = false;
      }
      if (!isLockScreenAllowedNow()) return;
      setupMediaSession(true);
      updateMediaSession();
    };

    ['play', 'playing', 'pause', 'canplay', 'loadedmetadata', 'seeked'].forEach((evt) => {
      el.addEventListener(evt, onAudioStateChange, { passive: true });
    });

    // Once silent audio actually advances past 50ms, WebKit's GPUProcess::recomputeNowPlayingOwner
    // seats this page via becomeNowPlayingOwner — flush supported commands across RunLoop turns right then.
    el.addEventListener('timeupdate', () => {
      if (!flushedAfterPlayingAdvance && !el.paused && el.currentTime >= 0.05) {
        flushedAfterPlayingAdvance = true;
        if (isLockScreenAllowedNow()) {
          setupMediaSession(true);
          updateMediaSession();
        }
      }
    }, { passive: true });

    const handleSilentAudioError = () => {
      const curSrc = el.getAttribute('src') || '';
      if (curSrc.includes('silence.m4a') && !el._amrWavFallbackTried) {
        el._amrWavFallbackTried = true;
        el.src = '/assets/silence.wav?v=5';
        try { el.load(); } catch (_) {}
        if (state.playerState === 'playing' && isLockScreenAllowedNow()) {
          try {
            const p = el.play();
            if (p !== undefined) p.catch(() => {});
          } catch (_) {}
        }
      }
    };

    el.addEventListener('error', handleSilentAudioError, { passive: true });
    if (el.error) {
      handleSilentAudioError();
    }
  }

  function initSilentAudio() {
    if (!isLockScreenAllowedNow()) {
      return null;
    }
    if (!silentAudioEl) {
      silentAudioEl = document.getElementById('bg-silent-audio');
    }
    if (!silentAudioEl) {
      silentAudioEl = document.createElement('audio');
      silentAudioEl.id = 'bg-silent-audio';
      silentAudioEl.loop = true;
      silentAudioEl.setAttribute('playsinline', '');
      silentAudioEl.setAttribute('webkit-playsinline', '');
      silentAudioEl.setAttribute('x-webkit-airplay', 'deny');
      silentAudioEl.preload = 'auto';
      silentAudioEl.style.cssText = 'position:fixed;bottom:0;left:0;width:1px;height:1px;opacity:0.001;pointer-events:none;z-index:-1;';
      attachSilentAudioListeners(silentAudioEl);
      silentAudioEl.src = '/assets/silence.m4a?v=4';
      document.body.appendChild(silentAudioEl);
    } else {
      silentAudioEl.preload = 'auto';
      silentAudioEl.setAttribute('x-webkit-airplay', 'deny');
      attachSilentAudioListeners(silentAudioEl);
      if (!silentAudioEl.getAttribute('src') && !silentAudioEl.querySelector('source')) {
        silentAudioEl._amrWavFallbackTried = false;
        silentAudioEl.src = '/assets/silence.m4a?v=4';
      }
    }
    return silentAudioEl;
  }

  function teardownMediaSessionAndSilentAudio() {
    const el = silentAudioEl || document.getElementById('bg-silent-audio');
    if (el) {
      try {
        if (!el.paused) {
          el.pause();
        }
        el.currentTime = 0;
        // Keep src intact so HTMLMediaElement retains HAVE_ENOUGH_DATA and iOS gesture blessing.
      } catch (e) {}
    }
    mediaSessionHandlersBound = false;
    mediaSessionPlatformActivated = false;
    lastMediaSessionKey = '';

    if ('mediaSession' in navigator) {
      allowAmrMediaSessionMutation = true;
      try {
        navigator.mediaSession.playbackState = 'none';
        navigator.mediaSession.metadata = null;
        ['play', 'pause', 'previoustrack', 'nexttrack', 'seekto', 'seekbackward', 'seekforward', 'stop'].forEach((act) => {
          try { navigator.mediaSession.setActionHandler(act, null); } catch (e) {}
        });
      } catch (e) {
      } finally {
        allowAmrMediaSessionMutation = false;
      }
    }
  }

  function syncSilentAudio(isPlaying) {
    if (!isLockScreenAllowedNow()) {
      teardownMediaSessionAndSilentAudio();
      return;
    }
    const el = initSilentAudio();
    if (!el) return;

    if (isPlaying) {
      if (el.paused) {
        const p = el.play();
        if (p !== undefined) {
          p.then(() => {
            silentAudioUnlocked = true;
            removeUnlockAudioGestureListeners();
            setupMediaSession(true);
            updateMediaSession();
            setTimeout(() => {
              if (isLockScreenAllowedNow()) {
                setupMediaSession(true);
              }
            }, 120);
            setTimeout(() => {
              if (isLockScreenAllowedNow()) {
                setupMediaSession(true);
              }
            }, 450);
          }).catch((err) => {
            console.warn('[AudioKeepAlive] play error:', err);
          });
        }
      } else {
        setupMediaSession(true);
      }
    } else if (!el.paused) {
      el.pause();
    }
  }

  const UNLOCK_GESTURE_EVENTS = ['touchend', 'pointerup', 'click'];
  let unlockGestureListenersBound = false;

  function removeUnlockAudioGestureListeners() {
    if (!unlockGestureListenersBound) return;
    unlockGestureListenersBound = false;
    UNLOCK_GESTURE_EVENTS.forEach(evt => {
      window.removeEventListener(evt, unlockAudioOnUserGesture);
    });
  }

  function bindUnlockAudioGestureListeners() {
    if (unlockGestureListenersBound || silentAudioUnlocked) return;
    unlockGestureListenersBound = true;
    UNLOCK_GESTURE_EVENTS.forEach(evt => {
      window.addEventListener(evt, unlockAudioOnUserGesture, { passive: true });
    });
  }

  // Unlock silent keep-alive audio on user activation (even before WebSocket auth finishes)
  function unlockAudioOnUserGesture() {
    if (!isLockScreenAllowedNow()) {
      return;
    }

    if (silentAudioUnlocked) {
      removeUnlockAudioGestureListeners();
      return;
    }

    const el = initSilentAudio();
    if (!silentAudioUnlocked && el) {
      const p = el.play();
      if (p !== undefined) {
        p.then(() => {
          silentAudioUnlocked = true;
          removeUnlockAudioGestureListeners();
          setupMediaSession(true);
          updateMediaSession();
          setTimeout(() => {
            const shouldPlay = state.playerState === 'playing' || Date.now() < (state.pendingPlayUntil || 0);
            if (!shouldPlay && !el.paused) {
              el.pause();
            }
            if (isLockScreenAllowedNow()) {
              setupMediaSession(true);
            }
          }, 160);
        }).catch(() => {});
      }
    }
  }

  bindUnlockAudioGestureListeners();

  // Re-bind MediaSession on BOTH screen lock (document.hidden === true, when WebKit enables NowPlaying visibility) and wake/unlock
  ['visibilitychange', 'pagehide', 'pageshow', 'focus'].forEach((evt) => {
    window.addEventListener(evt, () => {
      if (isLockScreenAllowedNow()) {
        setupMediaSession(true);
        updateMediaSession();
      }
    }, { passive: true });
  });

  // Global tactile feedback on all interactive elements
  let lastGlobalHapticTime = 0;
  document.addEventListener('pointerup', (e) => {
    const now = Date.now();
    if (now - lastGlobalHapticTime < 80) return;
    const target = e.target.closest('button, .track-row, .tv-queue-row, .playlist-card, .hero-card, .station-card, .media-card, .genre-card, .tab-item, .nav-btn, .search-chip, .quality-badge, .pill, .mini-btn, .mini-player-content');
    if (target) {
      lastGlobalHapticTime = now;
      triggerHaptic('light');
    }
  }, { passive: true });

  // Track iPhone Landscape StandBy media query (strictly matching CSS 12-landscape-controls-and-booklet.css)
  const standbyLandscapeMq = (typeof window !== 'undefined' && typeof window.matchMedia === 'function')
    ? window.matchMedia('(max-height: 540px) and (min-width: 568px) and (orientation: landscape) and (hover: none) and (pointer: coarse)')
    : null;

  function syncStandbyLandscapeBodyClass() {
    const isLandscapeStandby = Boolean(standbyLandscapeMq && standbyLandscapeMq.matches && !document.body.classList.contains('keyboard-open'));
    document.body.classList.toggle('standby-landscape-open', isLandscapeStandby);
    if (isLandscapeStandby && typeof closeStandbyQueueModal === 'function') {
      closeStandbyQueueModal();
    }
  }

  if (standbyLandscapeMq) {
    syncStandbyLandscapeBodyClass();
    const onStandbyMqChange = () => {
      syncStandbyLandscapeBodyClass();
      ensureScrubberLoopRunning();
      if (typeof syncActiveMotionVideoTarget === 'function') syncActiveMotionVideoTarget();
      if (typeof syncSpectralPolling === 'function') syncSpectralPolling();
    };
    if (typeof standbyLandscapeMq.addEventListener === 'function') {
      standbyLandscapeMq.addEventListener('change', onStandbyMqChange);
    } else if (typeof standbyLandscapeMq.addListener === 'function') {
      standbyLandscapeMq.addListener(onStandbyMqChange);
    }
  }

  // Track text-input keyboard focus so landscape TV Mode does not hide when buttons/sliders receive focus
  const TEXT_ENTRY_SELECTOR = 'input[type="text"], input[type="search"], input[type="url"], input[type="number"], input:not([type]), textarea, [contenteditable="true"]';
  function syncKeyboardFocusClass() {
    const el = document.activeElement;
    const isTextFocused = Boolean(
      el &&
      el !== document.body &&
      typeof el.matches === 'function' &&
      el.matches(TEXT_ENTRY_SELECTOR) &&
      el.isConnected &&
      !el.disabled &&
      !el.readOnly &&
      el.getClientRects().length > 0
    );
    const hadClass = document.body.classList.contains('keyboard-open');
    document.body.classList.toggle('keyboard-open', isTextFocused);
    syncStandbyLandscapeBodyClass();
    if (hadClass !== isTextFocused) {
      ensureScrubberLoopRunning();
      if (typeof syncActiveMotionVideoTarget === 'function') syncActiveMotionVideoTarget();
      if (typeof syncSpectralPolling === 'function') syncSpectralPolling();
    }
  }
  function blurFocusedInContainer(container) {
    if (container && document.activeElement && container.contains(document.activeElement) && typeof document.activeElement.blur === 'function') {
      document.activeElement.blur();
    }
    syncKeyboardFocusClass();
  }
  document.addEventListener('focusin', syncKeyboardFocusClass, { passive: true });
  document.addEventListener('focusout', () => {
    setTimeout(syncKeyboardFocusClass, 0);
  }, { passive: true });

// === MODULE: 08-silent-audio-and-media-session.js ===
  // --- MediaSession (Lock Screen, Dynamic Island, AirPods, Control Center) ---
  let lastMediaSessionKey = '';

  const msPlayHandler = () => {
    triggerHaptic('medium');
    syncSilentAudio(true);
    optimisticPlay();
    updateMediaSession();
    send({ action: 'play' });
  };

  const msPauseHandler = () => {
    triggerHaptic('medium');
    syncSilentAudio(false);
    state.pendingPlayUntil = 0;
    state.pendingPauseUntil = Date.now() + 2500;
    const now = performance.now();
    if (state.playerState === 'playing' && state.duration > 0) {
      state.lastSyncPos = Math.min(state.duration, state.lastSyncPos + Math.max(0, (now - state.lastSyncTime) / 1000));
      state.position = state.lastSyncPos;
    }
    state.lastSyncTime = now;
    state.lastSyncPerf = now;
    state.playerState = 'paused';
    state.playbackState = 'paused';
    renderNowPlaying();
    updateMediaSession();
    send({ action: 'pause' });
  };

  const keepSilentAudioAliveForTrackSkip = () => {
    if (!isLockScreenAllowedNow()) return;
    const el = initSilentAudio();
    if (el && el.paused) {
      try {
        const p = el.play();
        if (p !== undefined) {
          p.then(() => {
            silentAudioUnlocked = true;
            setTimeout(() => {
              const shouldPlay = state.playerState === 'playing' || Date.now() < (state.pendingPlayUntil || 0);
              if (!shouldPlay && !el.paused) {
                el.pause();
              }
            }, 1200);
          }).catch(() => {});
        }
      } catch (_) {}
    }
  };

  const msPrevHandler = () => {
    triggerHaptic('medium');
    keepSilentAudioAliveForTrackSkip();
    sendThrottledTransport('previous');
  };

  const msNextHandler = () => {
    triggerHaptic('medium');
    keepSilentAudioAliveForTrackSkip();
    sendThrottledTransport('next');
  };

  const msSeekToHandler = (details) => {
    if (details && details.seekTime != null && !isNaN(details.seekTime)) {
      triggerHaptic('light');
      sendSeek(details.seekTime);
    }
  };

  const msStopHandler = () => {
    triggerHaptic('medium');
    syncSilentAudio(false);
    state.pendingPlayUntil = 0;
    state.playerState = 'stopped';
    state.playbackState = 'stopped';
    state.lastSyncPos = 0;
    state.position = 0;
    state.lastSyncTime = performance.now();
    state.lastSyncPerf = state.lastSyncTime;
    renderNowPlaying();
    updateMediaSession();
    send({ action: 'stop' });
  };

  function ensureMediaSessionPlatformActive(isPlaying) {
    if (!('mediaSession' in navigator) || !navigator.mediaSession) return;
    try {
      if (!mediaSessionPlatformActivated) {
        // WebKit C++ (NowPlayingManager.cpp:130, MediaSession.cpp:292):
        // m_remoteCommandListener is nullptr until playbackState = 'playing' activates
        // m_platformSession->setActive(true) -> MediaSessionManagerCocoa::addSession().
        navigator.mediaSession.playbackState = 'playing';
        mediaSessionPlatformActivated = true;
      }
      navigator.mediaSession.playbackState = isPlaying ? 'playing' : 'paused';
    } catch (_) {}
  }

  let mediaSessionCommandFlushTimer = null;
  let mediaSessionFlushStopToggle = false;

  function applyCoreMediaSessionActionHandlers(includeStopHandler) {
    allowAmrMediaSessionMutation = true;
    try {
      // Ensure WebKit RemoteCommandListenerCocoa registers ONLY Play, Pause, PreviousTrack,
      // NextTrack, and SeekToPlaybackPosition — never defaultCommands() (±15s SkipForward/SkipBackward).
      try { navigator.mediaSession.setActionHandler('seekbackward', null); } catch (e) {}
      try { navigator.mediaSession.setActionHandler('seekforward', null); } catch (e) {}
      navigator.mediaSession.setActionHandler('play', msPlayHandler);
      navigator.mediaSession.setActionHandler('pause', msPauseHandler);
      navigator.mediaSession.setActionHandler('previoustrack', msPrevHandler);
      navigator.mediaSession.setActionHandler('nexttrack', msNextHandler);
      navigator.mediaSession.setActionHandler('seekto', msSeekToHandler);
      try { navigator.mediaSession.setActionHandler('stop', includeStopHandler ? msStopHandler : null); } catch (e) {}
      mediaSessionHandlersBound = true;
    } catch (err) {
      console.warn('[MediaSession] Handler setup:', err);
    } finally {
      allowAmrMediaSessionMutation = false;
    }
  }

  function setupMediaSession(forceFlush = true) {
    if (!('mediaSession' in navigator)) return;
    if (!isLockScreenAllowedNow()) {
      teardownMediaSessionAndSilentAudio();
      return;
    }

    initSilentAudio();
    ensureMediaSessionPlatformActive(state.playerState === 'playing');

    if (forceFlush) {
      // WebKit RemoteCommandListener.cpp:81 + RemoteRemoteCommandListener.cpp:92 coalesces synchronous
      // remove+add within the same JS turn and early-returns if m_currentCommands == supportedCommands.
      // Toggling StopCommand across two separate RunLoop turns forces UpdateSupportedCommands IPC to GPUProcess
      // without ever dropping PreviousTrackCommand or NextTrackCommand for even a single frame.
      mediaSessionFlushStopToggle = !mediaSessionFlushStopToggle;
      applyCoreMediaSessionActionHandlers(mediaSessionFlushStopToggle);
      if (mediaSessionCommandFlushTimer) {
        clearTimeout(mediaSessionCommandFlushTimer);
      }
      mediaSessionCommandFlushTimer = setTimeout(() => {
        mediaSessionCommandFlushTimer = null;
        if (!('mediaSession' in navigator) || !isLockScreenAllowedNow()) return;
        mediaSessionFlushStopToggle = false;
        applyCoreMediaSessionActionHandlers(false);
      }, 45);
    } else {
      applyCoreMediaSessionActionHandlers(false);
    }
  }

  function updateMediaSession() {
    if (!('mediaSession' in navigator)) return;
    if (!isLockScreenAllowedNow()) {
      teardownMediaSessionAndSilentAudio();
      return;
    }

    const isPlaying = state.playerState === 'playing';
    ensureMediaSessionPlatformActive(isPlaying);
    syncSilentAudio(isPlaying);
    setupMediaSession(false);

    const t = state.track;
    if (!t || !t.name) return;

    const rawArt = getArtworkSrc(t);
    let fullArt = rawArt;
    if (!fullArt || fullArt.includes('.svg') || fullArt.includes('apple-touch-icon.svg')) {
      fullArt = `${window.location.origin}/apple-touch-icon-512.png`;
    } else if (fullArt.startsWith('/')) {
      fullArt = `${window.location.origin}${fullArt}`;
    }

    const artType = (fullArt.endsWith('.png') || fullArt.includes('icon')) ? 'image/png' : 'image/jpeg';

    const key = `${t.name}_${t.artist}_${t.album}_${fullArt}`;
    if (key !== lastMediaSessionKey) {
      lastMediaSessionKey = key;
      try {
        navigator.mediaSession.metadata = new MediaMetadata({
          title: t.name || 'Без названия',
          artist: t.artist || 'Apple Music',
          album: t.album || '',
          artwork: [
            { src: fullArt, sizes: '96x96', type: artType },
            { src: fullArt, sizes: '128x128', type: artType },
            { src: fullArt, sizes: '192x192', type: artType },
            { src: fullArt, sizes: '256x256', type: artType },
            { src: fullArt, sizes: '512x512', type: artType }
          ]
        });
        setupMediaSession(true);
      } catch (e) {
        console.warn('[MediaSession] Metadata update error:', e);
      }
    }

    if ('setPositionState' in navigator.mediaSession) {
      try {
        // WebKit MediaSession::setPositionState (MediaSession.cpp:459) throws TypeError if playbackRate == 0;
        // WebKit automatically computes actualPlaybackRate = (playbackState == Playing ? playbackRate : 0).
        if (state.duration > 0) {
          const nowPerf = performance.now();
          const syncBase = state.lastSyncPerf || state.lastSyncTime || nowPerf;
          const livePos = (state.lastSyncPos || 0) + (isPlaying ? Math.max(0, (nowPerf - syncBase) / 1000) : 0);
          const curPos = Math.min(Math.max(0, livePos), state.duration);
          navigator.mediaSession.setPositionState({
            duration: Math.max(state.duration, 0.1),
            playbackRate: 1.0,
            position: curPos
          });
        } else {
          navigator.mediaSession.setPositionState({
            duration: 240,
            playbackRate: 1.0,
            position: 0
          });
        }
      } catch (e) {}
    }
  }

  function cleanAudioQualityLabel(raw) {
    if (!raw) return 'LOSSLESS';
    const up = raw.toUpperCase();
    if (up.includes('ОЖИДАНИЕ CDN')) return IS_EN ? 'CDN TIMEOUT' : 'ОЖИДАНИЕ CDN';
    if (up.includes('БУФЕРИЗАЦИЯ')) return IS_EN ? 'BUFFERING…' : 'БУФЕРИЗАЦИЯ…';
    if (up.includes('ОПРЕДЕЛЕНИЕ')) return IS_EN ? 'DETECTING…' : 'ФОРМАТ…';
    if (up.includes('HI-RES')) return 'HI-RES LOSSLESS';
    if (up.includes('LOSSLESS')) return 'LOSSLESS';
    if (up.includes('AAC')) return 'AAC 256';
    if (up.includes('ALAC')) return 'ALAC LOSSLESS';
    return raw;
  }

  function formatDacPill(raw) {
    const up = String(raw || '').toUpperCase();
    if (state.isStreamStalled || up.includes('ОЖИДАНИЕ CDN') || up.includes('WAITING FOR APPLE MUSIC CDN')) {
      return IS_EN ? 'CDN Timeout • 0 kbps' : 'Ожидание CDN • 0 кбит/с';
    }
    if (state.isBuffering || up.includes('ЗАПУСК ИЗ ОБЛАКА') || up.includes('STARTING CLOUD STREAM') || up.includes('БУФЕРИЗАЦИЯ') || up.includes('BUFFERING STREAM')) {
      return IS_EN ? 'Starting Cloud Stream…' : 'Запуск из облака…';
    }
    if (up.includes('ОПРЕДЕЛЕНИЕ') || up.includes('DETECTING FORMAT')) {
      return IS_EN ? 'Detecting Format…' : 'Определение формата…';
    }
    if ((state.dspMode === 'sdm_dop' || state.dspMode === 'hq_nos_pcm') && state.dspBadge) {
      return state.dspBadge;
    }
    if (!raw) return 'Bit-Perfect DAC';
    if (up.includes('192')) return 'Bit-Perfect • 192 kHz / 24-bit';
    if (up.includes('96')) return 'Bit-Perfect • 96 kHz / 24-bit';
    if (up.includes('48')) return 'Lossless • 48 kHz / 24-bit';
    if (up.includes('44.1')) return 'Lossless • 44.1 kHz / 16-bit';
    if (up.includes('HI-RES')) return 'Hi-Res Lossless Bit-Perfect';
    if (up.includes('LOSSLESS') || up.includes('ALAC')) return 'Lossless Bit-Perfect';
    if (up.includes('AAC')) return 'AAC • 256 kbps';
    return raw;
  }

  let cachedSbFill = null;
  let cachedSbThumb = null;
  let cachedSbInput = null;
  let cachedSbElapsed = null;
  let cachedSbRemaining = null;
  let lastRenderedElapsedStr = '';
  let lastRenderedRemStr = '';
  let lastScrubberFrameMs = 0;

  function updateScrubberUI(currentPos, totalDur) {
    if (!cachedSbFill) cachedSbFill = document.getElementById('standby-progress-fill');
    if (!cachedSbThumb) cachedSbThumb = document.getElementById('standby-progress-thumb');
    if (!cachedSbInput) cachedSbInput = document.getElementById('standby-progress-input');
    if (!cachedSbElapsed) cachedSbElapsed = document.getElementById('standby-time-elapsed');
    if (!cachedSbRemaining) cachedSbRemaining = document.getElementById('standby-time-remaining');

    if (totalDur <= 0) {
      dom.scrubberFill.style.width = '0%';
      dom.scrubberThumb.style.left = '0%';
      dom.miniProgressFill.style.width = '0%';
      if (lastRenderedElapsedStr !== '0:00') {
        lastRenderedElapsedStr = '0:00';
        dom.timeElapsed.textContent = '0:00';
        if (cachedSbElapsed) cachedSbElapsed.textContent = '0:00';
      }
      if (lastRenderedRemStr !== '-0:00') {
        lastRenderedRemStr = '-0:00';
        dom.timeRemaining.textContent = '-0:00';
        if (cachedSbRemaining) cachedSbRemaining.textContent = '-0:00';
      }
      dom.scrubberInput.value = 0;
      if (cachedSbFill) cachedSbFill.style.width = '0%';
      if (cachedSbThumb) cachedSbThumb.style.left = '0%';
      if (cachedSbInput) cachedSbInput.value = 0;
      return;
    }

    const clampedPos = Math.max(0, Math.min(currentPos, totalDur));
    const percent = (clampedPos / totalDur) * 100;
    const pctStr = `${percent.toFixed(2)}%`;
    const tvVisible = isStandbyOrLandscapeVisible();

    if (tvVisible) {
      if (cachedSbFill) cachedSbFill.style.width = pctStr;
      if (cachedSbThumb) cachedSbThumb.style.left = pctStr;
      if (cachedSbInput && !state.isScrubbing) cachedSbInput.value = percent;
    } else {
      dom.scrubberFill.style.width = pctStr;
      dom.scrubberThumb.style.left = pctStr;
      dom.miniProgressFill.style.width = pctStr;
      dom.scrubberInput.value = percent;
      if (cachedSbFill) cachedSbFill.style.width = pctStr;
      if (cachedSbThumb) cachedSbThumb.style.left = pctStr;
      if (cachedSbInput && !state.isScrubbing) cachedSbInput.value = percent;
    }

    const elapsedStr = formatTime(clampedPos);
    const remaining = totalDur - clampedPos;
    const remStr = `-${formatTime(remaining)}`;
    if (elapsedStr !== lastRenderedElapsedStr) {
      lastRenderedElapsedStr = elapsedStr;
      dom.timeElapsed.textContent = elapsedStr;
      if (cachedSbElapsed) cachedSbElapsed.textContent = elapsedStr;
    }
    if (remStr !== lastRenderedRemStr) {
      lastRenderedRemStr = remStr;
      dom.timeRemaining.textContent = remStr;
      if (cachedSbRemaining) cachedSbRemaining.textContent = remStr;
    }
  }

  let lastLoadingPillKey = '';
  let lastLoadingTickCheckMs = 0;

  function syncTrackLoadingIndicatorUI() {
    const isPlaying = state.playerState === 'playing';
    const isCloudLoading = Boolean(isPlaying && state.isBuffering);
    const elapsedLoadingMs = state.loadingStartedAtMs ? Math.max(0, Date.now() - state.loadingStartedAtMs) : 0;
    const showLoadingUI = isCloudLoading && elapsedLoadingMs >= 200;
    const showShimmer = isCloudLoading;

    let statusText = '';
    if (showLoadingUI) {
      if (state.isStreamStalled) {
        statusText = IS_EN ? 'Waiting for Apple Music CDN…' : 'Ожидание CDN Apple Music…';
      } else {
        statusText = IS_EN ? 'Starting Cloud Stream…' : 'Запуск из облака…';
      }
    }

    const t = state.track;
    const miniText = t ? (t.artist || 'Apple Music') : 'Apple Music';

    const renderKey = `${showLoadingUI ? 1 : 0}|${showShimmer ? 1 : 0}|${statusText}|${miniText}`;
    if (renderKey === lastLoadingPillKey) {
      return;
    }
    lastLoadingPillKey = renderKey;

    if (dom.playerLoadingStatus) {
      dom.playerLoadingStatus.classList.toggle('hidden', !showLoadingUI);
      dom.playerLoadingStatus.classList.remove('is-buffer');
    }
    if (dom.playerLoadingText && statusText) {
      dom.playerLoadingText.textContent = statusText;
    }
    if (dom.standbyLoadingStatus) {
      dom.standbyLoadingStatus.classList.toggle('hidden', !showLoadingUI);
      dom.standbyLoadingStatus.classList.remove('is-buffer');
    }
    if (dom.standbyLoadingText && statusText) {
      dom.standbyLoadingText.textContent = statusText;
    }

    if (dom.scrubberContainer) {
      dom.scrubberContainer.classList.toggle('is-loading-stream', showShimmer);
      dom.scrubberContainer.classList.remove('is-buffer-staging');
    }
    if (dom.miniProgressTrack) {
      dom.miniProgressTrack.classList.toggle('is-loading-stream', showShimmer);
      dom.miniProgressTrack.classList.remove('is-buffer-staging');
    }
    const sbTrack = dom.standbyProgressTrack || document.getElementById('standby-progress-track');
    if (sbTrack) {
      sbTrack.classList.toggle('is-loading-stream', showShimmer);
      sbTrack.classList.remove('is-buffer-staging');
    }

    if (dom.btnPlayPause) {
      dom.btnPlayPause.classList.toggle('is-loading-ring', showLoadingUI);
      dom.btnPlayPause.classList.remove('is-buffer-ring');
    }
    if (dom.miniBtnPlayPause) {
      dom.miniBtnPlayPause.classList.toggle('is-loading-ring', showLoadingUI);
      dom.miniBtnPlayPause.classList.remove('is-buffer-ring');
    }
    const sbPlayBtn = dom.standbyBtnPlayPause || document.getElementById('standby-btn-play-pause');
    if (sbPlayBtn) {
      sbPlayBtn.classList.toggle('is-loading-ring', showLoadingUI);
      sbPlayBtn.classList.remove('is-buffer-ring');
    }

    if (dom.audioQualityBadge) {
      dom.audioQualityBadge.classList.remove('is-loading-stream');
    }
    const sbDacBadge = document.getElementById('standby-dac-badge');
    if (sbDacBadge) {
      sbDacBadge.classList.remove('is-loading-stream');
    }

    if (dom.miniArtist) {
      dom.miniArtist.classList.remove('is-loading-stream');
      if (dom.miniArtist.textContent !== miniText) {
        dom.miniArtist.textContent = miniText;
      }
    }
  }

  // --- Optimistic Scrubber Loop (rAF normally when duration > 0; 250ms setInterval in StandBy/TV Mode) ---
  let scrubberRafId = 0;
  let standbyScrubberTimerId = null;

  function stopStandbyScrubberInterval() {
    if (standbyScrubberTimerId) {
      clearInterval(standbyScrubberTimerId);
      standbyScrubberTimerId = null;
    }
  }

  function stepScrubberFrame(tsFrame) {
    if ((state.isStagingBuffer || state.isBuffering) && (tsFrame - lastLoadingTickCheckMs >= 250)) {
      lastLoadingTickCheckMs = tsFrame;
      syncTrackLoadingIndicatorUI();
    }
    if (!state.isScrubbing && state.duration > 0) {
      const waitingForFirstAudioFrame = state.isBuffering || state.isStagingBuffer || (!state.hasStartedAdvancingForTrack && state.lastSyncPos <= 0.08);
      const deltaSec = waitingForFirstAudioFrame ? 0 : ((tsFrame - state.lastSyncTime) / 1000);
      const rawPos = state.lastSyncPos + deltaSec;
      const currentPos = Math.min(state.duration, rawPos);
      state.position = currentPos;
      updateScrubberUI(currentPos, state.duration);

      // If spectral data went stale (>1.2s) while RTA bars are still raised above floor, wake up RTA decay loop
      if (!standbyRtaRafId && (tsFrame - (state.lastSpectralUpdateAt || 0)) > 1200 && isStandbyOrLandscapeVisible()) {
        for (let i = 0; i < standbyRtaBarCount; i++) {
          if (standbyRtaCurrent[i] > 0.035 || standbyRtaTarget[i] > 0.035) {
            ensureStandbyRtaAnimLoop();
            break;
          }
        }
      }

      // Watchdog: if seek bar has been pinned at 100% for > 1.5s without a track transition event,
      // actively poll status & queue from the server to recover immediately.
      if (rawPos >= state.duration + 1.5 && state.connected && state.deviceAuthorized) {
        const nowWall = Date.now();
        if (nowWall - (state.lastEndOfTrackPollAt || 0) >= 2500) {
          state.lastEndOfTrackPollAt = nowWall;
          send({ action: 'get_status' });
          send({ action: 'get_queue' });
          send({
            action: 'client_log',
            params: {
              level: 'warn',
              message: `Scrubber pinned at 100% (${Math.round(state.duration)}s) for ${(rawPos - state.duration).toFixed(1)}s on track "${(state.track && state.track.name) || ''}" — polling status & queue`
            }
          });
          ensureStandbyRtaAnimLoop();
        }
      }
    }
  }

  function ensureScrubberLoopRunning() {
    const shouldAnimate = Boolean(state.connected && state.playerState === 'playing' && (state.duration > 0) && !document.hidden);
    if (!shouldAnimate) {
      if (scrubberRafId) {
        cancelAnimationFrame(scrubberRafId);
        scrubberRafId = 0;
      }
      stopStandbyScrubberInterval();
      return;
    }

    if (isStandbyOrLandscapeVisible()) {
      if (scrubberRafId) {
        cancelAnimationFrame(scrubberRafId);
        scrubberRafId = 0;
      }
      if (!standbyScrubberTimerId) {
        standbyScrubberTimerId = setInterval(() => {
          if (!state.connected || state.playerState !== 'playing' || !(state.duration > 0) || document.hidden || !isStandbyOrLandscapeVisible()) {
            stopStandbyScrubberInterval();
            ensureScrubberLoopRunning();
            return;
          }
          const ts = performance.now();
          lastScrubberFrameMs = ts;
          stepScrubberFrame(ts);
        }, 250);
      }
      return;
    }

    stopStandbyScrubberInterval();
    if (!scrubberRafId) {
      scrubberRafId = requestAnimationFrame(scrubberAnimationLoop);
    }
  }

  function scrubberAnimationLoop(nowMs) {
    scrubberRafId = 0;
    if (!state.connected || state.playerState !== 'playing' || !(state.duration > 0) || document.hidden) {
      return;
    }
    if (isStandbyOrLandscapeVisible()) {
      ensureScrubberLoopRunning();
      return;
    }
    const tsFrame = nowMs || performance.now();
    if (tsFrame - lastScrubberFrameMs >= 50) {
      lastScrubberFrameMs = tsFrame;
      stepScrubberFrame(tsFrame);
    }
    scrubberRafId = requestAnimationFrame(scrubberAnimationLoop);
  }
  ensureScrubberLoopRunning();

  // --- WebSocket Liveness, Ping/Pong Probe & Half-Open Watchdog ---
  function checkSocketLiveness(isResumeProbe = false) {
    if (document.hidden && !isResumeProbe) return;

    if (!socket || socket.readyState === WebSocket.CLOSED || socket.readyState === WebSocket.CLOSING) {
      if (isResumeProbe) {
        reconnectAttempt = 0;
        connectWebSocket();
      }
      return;
    }
    if (socket.readyState !== WebSocket.OPEN) return;

    const now = Date.now();
    const lastRx = state.lastServerMessageAt || now;
    const silenceMs = now - lastRx;

    if (state.pendingPingSentAt > 0) {
      if (lastRx >= state.pendingPingSentAt) {
        state.pendingPingSentAt = 0;
      } else if (now - state.pendingPingSentAt >= 4000) {
        state.pendingPingSentAt = 0;
        connectWebSocket();
        return;
      }
    }

    if (state.pendingPingSentAt === 0) {
      if (isResumeProbe && silenceMs >= 3000) {
        state.pendingPingSentAt = now;
        send({ action: 'ping' });
        if (state.deviceAuthorized) {
          send({ action: 'get_status' });
        }
        return;
      }
      if (silenceMs >= 15000) {
        state.pendingPingSentAt = now;
        send({ action: 'ping' });
        return;
      }
    }

    if (state.playerState === 'playing' && state.deviceAuthorized && silenceMs >= 4500 && state.pendingPingSentAt === 0) {
      send({ action: 'get_status' });
      send({ action: 'get_queue' });
      if (silenceMs >= 11000) {
        state.pendingPingSentAt = now;
        send({ action: 'ping' });
      }
    }
  }

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      ensureScrubberLoopRunning();
      checkSocketLiveness(true);
    } else {
      ensureScrubberLoopRunning();
    }
    syncSpectralPolling();
  });

  window.addEventListener('pageshow', () => {
    ensureScrubberLoopRunning();
    checkSocketLiveness(true);
  }, { passive: true });

  window.addEventListener('online', () => {
    reconnectAttempt = 0;
    checkSocketLiveness(true);
  }, { passive: true });

  setInterval(() => {
    checkSocketLiveness(false);
  }, 2000);

  // --- Scrubber User Interaction ---
  dom.scrubberInput.addEventListener('input', function (e) {
    state.isScrubbing = true;
    const percent = parseFloat(e.target.value);
    const targetPos = (percent / 100) * state.duration;
    state.scrubValue = targetPos;

    dom.scrubberFill.style.width = `${percent}%`;
    dom.scrubberThumb.style.left = `${percent}%`;
    dom.timeElapsed.textContent = formatTime(targetPos);
    dom.timeRemaining.textContent = `-${formatTime(Math.max(0, state.duration - targetPos))}`;
  });

  function commitScrub() {
    if (!state.isScrubbing) return;
    const targetPos = state.scrubValue;
    state.isScrubbing = false;
    sendSeek(targetPos);
  }

  function sendSeek(position) {
    const targetPos = Math.max(0, Math.min(state.duration || 0, position));
    state.isBuffering = false;
    state.isStagingBuffer = false;
    state.loadingStage = null;
    state.loadingStartedAtMs = 0;
    state.hasStartedAdvancingForTrack = targetPos > 0.08;
    state.lastSyncPos = targetPos;
    state.lastSyncTime = performance.now();
    state.lastSyncPerf = state.lastSyncTime;
    state.position = targetPos;
    updateScrubberUI(targetPos, state.duration);
    syncTrackLoadingIndicatorUI();
    send({
      action: 'seek',
      params: { position: targetPos }
    });
    updateMediaSession();
  }

  dom.scrubberInput.addEventListener('change', commitScrub);
  dom.scrubberInput.addEventListener('pointerup', commitScrub);
  dom.scrubberInput.addEventListener('touchend', commitScrub);
  dom.scrubberInput.addEventListener('pointercancel', commitScrub);
  dom.scrubberInput.addEventListener('touchcancel', commitScrub);

  // --- Transport Event Listeners ---
  function optimisticPlay() {
    state.pendingPauseUntil = 0;
    state.pendingPlayUntil = Date.now() + 3000;
    state.lastClientCommandAt = Date.now();
    state.lastSyncTime = performance.now();
    state.lastSyncPerf = state.lastSyncTime;
    state.playerState = 'playing';
    state.playbackState = 'playing';
    syncSilentAudio(true);
    renderNowPlaying();
    updateMediaSession();
  }

  function togglePlayPause(e) {
    if (e) {
      e.preventDefault();
      e.stopPropagation();
    }
    triggerHaptic('medium');
    const isPlaying = state.playerState === 'playing';
    if (isPlaying) {
      syncSilentAudio(false);
      state.pendingPlayUntil = 0;
      state.isBuffering = false;
      state.isStagingBuffer = false;
      state.loadingStage = null;
      state.loadingStartedAtMs = 0;
      const now = performance.now();
      state.lastSyncPos = Math.min(state.duration, state.lastSyncPos + (now - state.lastSyncTime) / 1000);
      state.position = state.lastSyncPos;
      state.lastSyncTime = now;
      state.lastSyncPerf = now;
      state.playerState = 'paused';
      state.playbackState = 'paused';
      renderNowPlaying();
      updateMediaSession();
    } else {
      optimisticPlay();
    }
    send({ action: isPlaying ? 'pause' : 'play' });
  }

  let transportLoadingTimer = null;
  function setTransportLoading(action) {
    if (transportLoadingTimer) clearTimeout(transportLoadingTimer);
    if (action === 'next') {
      dom.btnNext?.classList.add('btn-loading');
      dom.miniBtnNext?.classList.add('btn-loading');
    } else if (action === 'previous') {
      dom.btnPrev?.classList.add('btn-loading');
    }
    transportLoadingTimer = setTimeout(clearTransportLoading, 2000);
  }

// === MODULE: 09-transport-and-signal-path.js ===
  function clearTransportLoading() {
    if (transportLoadingTimer) {
      clearTimeout(transportLoadingTimer);
      transportLoadingTimer = null;
    }
    dom.btnNext?.classList.remove('btn-loading');
    dom.miniBtnNext?.classList.remove('btn-loading');
    dom.btnPrev?.classList.remove('btn-loading');
    dom.btnPlayPause?.classList.remove('btn-loading');
    dom.miniBtnPlayPause?.classList.remove('btn-loading');
  }

  let lastNextActionTime = 0;
  let lastPrevActionTime = 0;
  function sendThrottledTransport(action) {
    const now = Date.now();
    if (action === 'next') {
      if (now - lastNextActionTime < 400) return;
      lastNextActionTime = now;
    } else if (action === 'previous') {
      if (now - lastPrevActionTime < 150) return;
      lastPrevActionTime = now;
    } else {
      if (now - lastNextActionTime < 400) return;
      lastNextActionTime = now;
    }
    setTransportLoading(action);
    triggerHaptic('medium');
    send({ action });
  }

  dom.btnPlayPause.addEventListener('click', togglePlayPause);
  dom.miniBtnPlayPause.addEventListener('click', togglePlayPause);

  // Desktop Spacebar shortcut for Play/Pause
  document.addEventListener('keydown', (e) => {
    if (e.code !== 'Space') return;
    const tag = document.activeElement?.tagName;
    if (['INPUT', 'TEXTAREA', 'BUTTON', 'SELECT'].includes(tag) || document.activeElement?.isContentEditable) return;
    const authOverlay = document.getElementById('device-auth-overlay');
    if (authOverlay && !authOverlay.classList.contains('hidden')) return;
    if (dom.modalAppleAuth && !dom.modalAppleAuth.classList.contains('hidden')) return;
    e.preventDefault();
    togglePlayPause();
  });

  dom.btnNext.addEventListener('click', () => sendThrottledTransport('next'));
  dom.miniBtnNext.addEventListener('click', (e) => {
    e.stopPropagation();
    sendThrottledTransport('next');
  });

  dom.btnPrev.addEventListener('click', () => sendThrottledTransport('previous'));

  function normalizeRepeatMode(val) {
    const m = String(val || '').trim().toLowerCase();
    if (m === 'one' || m === '1' || m === 'track') return 'one';
    if (m === 'all') return 'all';
    return 'off';
  }

  function toggleShuffleOptimistic() {
    if (state.isRadio) {
      showToast(IS_EN ? 'Shuffle is unavailable on Radio' : 'Перемешивание недоступно для радио');
      return;
    }
    triggerHaptic('toggle');
    const nextShuffle = !state.shuffle;
    state.shuffle = nextShuffle;
    state.pendingShuffleUntil = Date.now() + 3000;
    renderNowPlaying();
    if (isStandbyOrLandscapeVisible()) updateStandbyUI();
    send({
      action: 'set_shuffle',
      params: { enabled: nextShuffle }
    });
    showToast(nextShuffle
      ? (IS_EN ? '🔀 Shuffle Enabled' : '🔀 Перемешивание включено')
      : (IS_EN ? 'Shuffle Off' : 'Перемешивание выключено'));
  }

  dom.btnShuffle.addEventListener('click', toggleShuffleOptimistic);

  function applyRepeatModeOptimistic(nextMode) {
    let cleanMode = normalizeRepeatMode(nextMode);
    if (state.isRadio && cleanMode === 'all') {
      cleanMode = 'off';
    }
    state.repeatMode = cleanMode;
    state.pendingRepeatUntil = Date.now() + 3000;
    renderNowPlaying();
    if (isStandbyOrLandscapeVisible()) updateStandbyUI();
    send({
      action: 'set_repeat',
      params: { mode: cleanMode }
    });
    if (cleanMode === 'one') {
      showToast(IS_EN ? '🔂 Repeat One Track' : '🔂 Зациклен 1 трек');
    } else if (cleanMode === 'all') {
      showToast(IS_EN ? '🔁 Repeat Queue' : '🔁 Повтор очереди');
    } else {
      showToast(IS_EN ? 'Repeat Off' : 'Повтор выключен');
    }
  }

  function cycleRepeatMode() {
    triggerHaptic('toggle');
    const modes = state.isRadio ? ['off', 'one'] : ['off', 'all', 'one'];
    const curMode = normalizeRepeatMode(state.repeatMode);
    const curIdx = modes.indexOf(curMode);
    const nextIdx = ((curIdx >= 0 ? curIdx : 0) + 1) % modes.length;
    applyRepeatModeOptimistic(modes[nextIdx]);
  }

  dom.btnRepeat.addEventListener('click', cycleRepeatMode);

  let toastTimerId = 0;

  function showToast(message, durationMs = 1900) {
    if (!message) return;
    let hud = document.getElementById('amr-toast-hud');
    if (!hud) {
      hud = document.createElement('div');
      hud.id = 'amr-toast-hud';
      hud.className = 'amr-toast-hud';
      hud.setAttribute('role', 'status');
      hud.setAttribute('aria-live', 'polite');
      document.body.appendChild(hud);
    }
    hud.textContent = translateTextToEn(String(message));
    if (toastTimerId) clearTimeout(toastTimerId);
    requestAnimationFrame(() => {
      hud.classList.add('visible');
    });
    toastTimerId = setTimeout(() => {
      hud.classList.remove('visible');
    }, durationMs);
  }

  function handleToggleFavorite(e) {
    if (e) e.stopPropagation();
    triggerHaptic('toggle');

    const t = state.track;
    const currentFav = Boolean(t && t.favorited);
    const nextFav = !currentFav;

    if (t) {
      t.favorited = nextFav;
      state.pendingFavoriteUntil = Date.now() + 3500;
      state.pendingFavoriteTrackKey = `${t.artist || ''}|${t.name || ''}`;
      state.pendingFavoriteValue = nextFav;
    }

    const sbFavBtn = document.getElementById('standby-btn-favorite');
    [dom.btnFavorite, dom.miniBtnFavorite, sbFavBtn].forEach(btn => {
      if (!btn) return;
      btn.classList.toggle('active', nextFav);
      if (!nextFav) {
        btn.classList.remove('unpop-anim');
        void btn.offsetWidth;
        btn.classList.add('unpop-anim');
      } else {
        btn.classList.remove('unpop-anim');
      }
    });

    showToast(nextFav ? '★ Добавлено в избранное' : '☆ Удалено из избранного');
    send({
      action: 'favorite',
      params: { favorited: nextFav }
    });
  }

  dom.btnFavorite.addEventListener('click', handleToggleFavorite);

  if (dom.miniBtnFavorite) {
    dom.miniBtnFavorite.addEventListener('click', handleToggleFavorite);
  }

  dom.btnReconnect.addEventListener('click', () => {
    triggerHaptic('light');
    connectWebSocket();
  });

  // --- Signal Path Inspector (Roon-like Pipeline) ---
  function updateSignalPathDetails() {
    const t = state.track;
    const quality = state.audioQuality || 'Lossless (ALAC 24-bit/48kHz)';
    const up = quality.toUpperCase();
    const isCdnStall = Boolean(state.isStreamStalled) || up.includes('ОЖИДАНИЕ CDN');
    const isBufferingStream = !isCdnStall && (Boolean(state.isBuffering) || up.includes('ЗАПУСК ИЗ ОБЛАКА') || up.includes('STARTING CLOUD STREAM') || up.includes('БУФЕРИЗАЦИЯ') || up.includes('ОПРЕДЕЛЕНИЕ'));
    const isLossy = up.includes('AAC') || up.includes('MP3');
    const devRateHz = state.audioDeviceSampleRate || 44100;
    const rateKhz = (devRateHz / 1000).toFixed(1).replace(/\.0$/, '');
    const outBitDepth = isLossy ? 16 : (state.audioDeviceBitDepth || (devRateHz >= 48000 ? 24 : 16));

    let formatBadge = 'ALAC Lossless';
    if (isCdnStall) {
      formatBadge = IS_EN ? 'CDN Timeout' : 'Таймаут CDN';
    } else if (isBufferingStream) {
      formatBadge = IS_EN ? 'Buffering…' : 'Буферизация…';
    } else if (up.includes('192') || up.includes('HI-RES')) {
      formatBadge = 'ALAC Hi-Res';
    } else if (isLossy) {
      formatBadge = 'AAC 256k';
    } else if (up.includes('LOSSLESS') || up.includes('ALAC')) {
      formatBadge = 'ALAC Lossless';
    }

    // Parse source sample rate and bit depth for Bit-Perfect & DSP verification
    const rateMatch = quality.match(/(\d+(?:\.\d+)?)\s*(?:kHz|кГц)/i);
    const sourceRateHz = rateMatch ? Math.round(parseFloat(rateMatch[1]) * 1000) : (t && (t.sample_rate || t.sampleRate) ? Number(t.sample_rate || t.sampleRate) : null);
    const depthMatch = quality.match(/(\d+)-(?:bit|бит)/i);
    const sourceBitDepth = depthMatch ? parseInt(depthMatch[1], 10) : (t && (t.bit_depth || t.bitDepth) ? Number(t.bit_depth || t.bitDepth) : null);

    const activeDev = (state.audioDevices || []).find(d => d.name === state.audioDeviceName || d.isDefault || d.is_default);
    const isNetworkRenderer = Boolean(
      state.isDlnaActive ||
      (activeDev && (activeDev.type === 'dlna' || activeDev.isNetwork || activeDev.is_network || activeDev.protocol === 'dlna' || activeDev.protocol === 'bluos'))
    );
    const isLocalDspActive = !isNetworkRenderer && (state.dspMode === 'sdm_dop' || state.dspMode === 'hq_nos_pcm');
    const srcRateVal = sourceRateHz || 44100;
    const srcBitsVal = sourceBitDepth || (isLossy ? 16 : (srcRateVal >= 48000 ? 24 : 16));
    const srcBitratePerCh = srcRateVal * srcBitsVal;
    const outDspRateHz = Number(state.dspOutputSampleRate) || 0;
    const badgeDsdMatch = String(state.dspBadge || '').match(/DSD(\d+)/i);
    const dsdMult = outDspRateHz >= 2822400
      ? Math.round(outDspRateHz / ((outDspRateHz % 48000 === 0) ? 48000 : 44100))
      : (badgeDsdMatch ? Number(badgeDsdMatch[1]) : (Number(state.dspRate) || 256));
    const dsdBaseGrid = (srcRateVal % 48000 === 0 && state.dspClockPolicy !== 'strict_sacd_44k1') ? 48000 : 44100;
    const dsdClockHz = outDspRateHz >= 2822400 ? outDspRateHz : (dsdMult * dsdBaseGrid);
    const dsdFallbackToPcm = state.dspMode === 'sdm_dop' && outDspRateHz > 0 && outDspRateHz < 2822400;
    const isInsufficientDsd = Boolean(
      isLocalDspActive &&
      state.dspMode === 'sdm_dop' &&
      !isLossy &&
      (
        dsdFallbackToPcm ||
        dsdClockHz < srcBitratePerCh ||
        (dsdClockHz / srcRateVal) < 32 ||
        (dsdMult <= 64 && srcRateVal > 48000)
      )
    );

    const ratesMatch = !sourceRateHz || Math.abs(sourceRateHz - devRateHz) <= 500;
    const depthsMatch = !sourceBitDepth || outBitDepth >= sourceBitDepth;
    const isPreDspActive = Boolean(
      (state.lateNightDrcMode && state.lateNightDrcMode !== 'off') ||
      state.lateNightDrcEnabled ||
      (state.masteringDeclipMode && state.masteringDeclipMode !== 'off') ||
      (state.masteringDeesserMode && state.masteringDeesserMode !== 'off') ||
      state.roomCorrectionActive ||
      (state.roomAcoustic && state.roomAcoustic.enabled && state.roomAcoustic.active_profile)
    );
    const isClockSynced64BitDsp = !isLocalDspActive && !isLossy && isPreDspActive && (Boolean(state.isClockSyncedDsp) || ratesMatch);
    const isHardwareMatched = isLocalDspActive
      ? !isInsufficientDsd
      : (isClockSynced64BitDsp || ((state.isBitPerfect !== false) && ratesMatch && depthsMatch));
    const isVerified = isHardwareMatched && !isLossy;

    const sa = state.spectralAnalysis || {};
    const saEnabled = sa.is_enabled !== false && sa.isEnabled !== false && sa.verdict !== 'disabled';
    const saVerdict = saEnabled ? (sa.verdict || 'analyzing') : '';
    const analyzedFrames = Number(sa.analyzed_frames_count !== undefined ? sa.analyzed_frames_count : (sa.analyzedFramesCount || 0));
    const isPendingValidation = !saEnabled || !saVerdict || saVerdict === 'analyzing' || (state.playerState !== 'playing' && analyzedFrames === 0);
    const isSpectralFake = !isPendingValidation && (saVerdict === 'upsampled' || saVerdict === 'lossy_transcode' || saVerdict === 'lossy_upscaled');
    const isSpectralZeroPad = !isPendingValidation && saVerdict === 'zero_padded';

    // Color the play icon (.icon-dac) inside quality badges according to quality match / mismatch,
    // or reset to gray (no color class) when a new track starts / while analyzing
    const sbDacBadge = document.getElementById('standby-dac-badge');
    const qualityBadges = [dom.audioQualityBadge, dom.mobileDacBadge, dom.desktopDacBadge, sbDacBadge].filter(Boolean);
    qualityBadges.forEach(badge => {
      badge.classList.remove('quality-ok', 'quality-warn', 'quality-bad');
      if (isCdnStall) {
        badge.classList.add('quality-warn');
        badge.title = IS_EN
          ? 'Music.app receives 0 bytes from Apple Music CDN (aod.itunes.apple.com) — check DNS (1.1.1.1 / 8.8.8.8) or network route'
          : 'Music.app не получает аудиопоток с CDN Apple Music (aod.itunes.apple.com) — проверьте DNS (1.1.1.1 / 8.8.8.8) или маршрут сети';
      } else if (!isBufferingStream) {
        badge.title = IS_EN ? 'Stream & DAC Signal Path' : 'Параметры потока и ЦАП';
        if (!isPendingValidation) {
          const badgeQualityClass = isSpectralFake
            ? 'quality-bad'
            : ((isSpectralZeroPad || (!isLossy && !isHardwareMatched)) ? 'quality-warn' : 'quality-ok');
          badge.classList.add(badgeQualityClass);
        }
      } else {
        badge.title = IS_EN ? 'Buffering Apple Music stream…' : 'Буферизация потока Apple Music…';
      }
    });

    // Sync TV / StandBy spectral verification pill badge
    const sbSpectralBadge = document.getElementById('standby-spectral-badge');
    if (sbSpectralBadge) {
      sbSpectralBadge.classList.toggle('hidden', !saEnabled);
      if (saEnabled) {
        const tvVerdict = isPendingValidation ? 'analyzing' : saVerdict;
        const sRate = Number(sa.sample_rate || sa.sampleRate || devRateHz);
        const tvBadgeMap = {
          verified_hires: sRate > 48000 ? '✓ TRUE HI-RES' : '✓ TRUE 24-BIT',
          verified_lossless: '✓ TRUE LOSSLESS',
          upsampled: '⚠ FAKE HI-RES • 22K CUT',
          lossy_transcode: '⚠ LOSSY TRANSCODE',
          lossy_upscaled: '⚠ UPSCALE 128→256K',
          zero_padded: '⚠ ZERO-PADDED 16→24',
          aac_lossy: '✓ AAC 256 KBPS',
          analyzing: 'FFT АНАЛИЗ...'
        };
        sbSpectralBadge.textContent = tvBadgeMap[tvVerdict] || 'FFT АНАЛИЗ...';
        sbSpectralBadge.classList.remove('authentic', 'warning', 'bad', 'neutral');
        if (tvVerdict === 'upsampled' || tvVerdict === 'lossy_transcode' || tvVerdict === 'lossy_upscaled') {
          sbSpectralBadge.classList.add('bad');
        } else if (tvVerdict === 'zero_padded') {
          sbSpectralBadge.classList.add('warning');
        } else if (tvVerdict === 'aac_lossy' || tvVerdict === 'analyzing') {
          sbSpectralBadge.classList.add('neutral');
        } else {
          sbSpectralBadge.classList.add('authentic');
        }
      }
    }

    const isModalOpen = Boolean(dom.qualityModal && !dom.qualityModal.classList.contains('hidden'));
    if (!isModalOpen) {
      renderSpectralAnalysisUI();
      return;
    }

    if (dom.signalSourceBadge) dom.signalSourceBadge.textContent = formatBadge;
    if (dom.signalSourceTitle) {
      dom.signalSourceTitle.textContent = t ? `${t.name} — ${t.artist}` : 'Apple Music';
    }
    if (dom.signalSourceDetails) {
      if (isCdnStall) {
        dom.signalSourceDetails.textContent = IS_EN
          ? 'HLS stream timeout from Apple Music CDN (aod.itunes.apple.com) — 0 PCM frames in CoreAudio'
          : 'Таймаут загрузки HLS-потока с CDN Apple Music (aod.itunes.apple.com) — 0 кадров PCM в CoreAudio';
      } else if (isBufferingStream) {
        dom.signalSourceDetails.textContent = IS_EN
          ? 'Buffering Apple Music stream (waiting for decoder start)…'
          : 'Буферизация потока Apple Music (ожидание старта декодера)…';
      } else {
        dom.signalSourceDetails.textContent = isLossy ? 'AAC 256 kbps → Декодирование в PCM 16-бит / 44.1 кГц' : quality;
      }
    }
    if (dom.signalDacRate) {
      dom.signalDacRate.textContent = `${rateKhz} кГц`;
    }

    const dacBadge = document.querySelector('#signal-node-dac .signal-node-badge');
    if (dacBadge) {
      if (isNetworkRenderer) {
        const isBluOS = (activeDev && activeDev.protocol === 'bluos') || (state.audioDeviceName && state.audioDeviceName.includes('Bluesound'));
        dacBadge.textContent = isBluOS ? 'СЕТЕВОЙ СТРИМЕР' : 'СЕТЕВОЙ ЦАП';
      } else {
        dacBadge.textContent = 'ВЫХОДНОЙ ЦАП';
      }
    }
    if (dom.signalDacName) {
      dom.signalDacName.textContent = state.audioDeviceName || 'Аудиовыход macOS';
    }
    if (dom.signalDacDetails) {
      if (isNetworkRenderer) {
        const isBluOS = (activeDev && activeDev.protocol === 'bluos') || (state.audioDeviceName && state.audioDeviceName.includes('Bluesound'));
        if (isLossy) {
          const protoName = isBluOS ? 'BluOS PCM Stream' : 'DLNA / UPnP';
          dom.signalDacDetails.textContent = `Сетевой PCM стриминг (${protoName}) • ${outBitDepth}-бит / ${rateKhz} кГц`;
        } else {
          const isHiRes = devRateHz > 48000;
          const protoName = isBluOS ? (isHiRes ? 'BluOS Hi-Res Stream' : 'BluOS Lossless Stream') : 'DLNA / UPnP';
          const streamLabel = isHiRes ? 'Сетевой Hi-Res стриминг' : 'Сетевой Lossless стриминг';
          dom.signalDacDetails.textContent = `${streamLabel} (${protoName}) • ${outBitDepth}-бит / ${rateKhz} кГц`;
        }
      } else {
        dom.signalDacDetails.textContent = `Прямое подключение macOS CoreAudio HAL (${outBitDepth}-бит / ${rateKhz} кГц)`;
      }
    }
    const signalEngineBadge = document.getElementById('signal-engine-badge');
    const signalEngineName = document.getElementById('signal-engine-name');
    const signalEngineMeta = document.getElementById('signal-engine-details') || document.querySelector('#signal-node-engine .signal-node-meta');
    const dspTelemPill = document.getElementById('dsp-telemetry-pill');
    const dspTelemText = document.getElementById('dsp-telemetry-text');

    const dspPresetSubEl = document.getElementById('dsp-preset-subtitle');
    if (dspPresetSubEl) {
      if (isNetworkRenderer) {
        dspPresetSubEl.textContent = IS_EN
          ? 'External network streamer active: Bit-Perfect PCM (DSD/NOS presets unavailable)'
          : 'Активен внешний сетевой плеер BluOS / DLNA: передаётся Bit-Perfect PCM (DSD/NOS не поддерживаются)';
      } else if (state.dspActivePresetSubtitle) {
        dspPresetSubEl.textContent = translateTextToEn(state.dspActivePresetSubtitle);
      }
    }

    const isDeClipActive = Boolean(state.masteringDeclipMode && state.masteringDeclipMode !== 'off');
    const deClipShort = state.masteringDeclipMode === 'studio'
      ? (IS_EN ? 'Studio De-Clip' : 'Студийный De-Clip')
      : (state.masteringDeclipMode === 'gentle'
        ? (IS_EN ? 'Gentle De-Clip' : 'Деликатный De-Clip')
        : (IS_EN ? 'Smart De-Clip' : 'Авто De-Clip'));
    const deClipSuffix = isDeClipActive ? ` • ⚡️ ${deClipShort}` : '';

    const isDeEsserActive = Boolean(state.masteringDeesserMode && state.masteringDeesserMode !== 'off');
    const deEsserShort = state.masteringDeesserMode === 'vocal'
      ? 'Weiss De-Esser'
      : (IS_EN ? 'Gentle De-Esser' : 'Деликатный De-Esser');
    const deEsserSuffix = isDeEsserActive ? ` • 💎 ${deEsserShort}` : '';

    const roomEqSuffix = (state.roomCorrectionActive || (state.roomAcoustic && state.roomAcoustic.enabled && state.roomAcoustic.active_profile))
      ? ` • Room EQ (${state.roomProfileName || (state.roomAcoustic.active_profile && state.roomAcoustic.active_profile.name) || 'Auto-PEQ'})`
      : '';
    const isDrcActive = Boolean((state.lateNightDrcMode && state.lateNightDrcMode !== 'off') || state.lateNightDrcEnabled);
    const drcModeShort = state.lateNightDrcMode === 'concert'
      ? (IS_EN ? 'Night Concert' : 'Ночной концерт')
      : (IS_EN ? 'Gentle DRC' : 'Деликатный DRC');
    const drcSuffix = isDrcActive ? ` • 🌙 ${drcModeShort}` : '';
    const allPreDspSuffixes = `${deClipSuffix}${deEsserSuffix}${roomEqSuffix}${drcSuffix}`;
    const anyPreDspNodeActive = Boolean(isDeClipActive || isDeEsserActive || roomEqSuffix || isDrcActive);
    syncMasteringRestorationBadgesOnly();
    syncLateNightBadgeOnly();

    if (!isNetworkRenderer && (state.dspMode === 'sdm_dop' || state.dspMode === 'hq_nos_pcm')) {
      const isDSD = (state.dspMode === 'sdm_dop');
      const mhz = ((state.dspOutputSampleRate || 11289600) / 1000000).toFixed(2);
      const dopKhz = ((state.dspDoPCarrierRate || 705600) / 1000).toFixed(1).replace(/\.0$/, '');
      if (signalEngineBadge) {
        signalEngineBadge.textContent = isDSD ? `${mhz} МГц · 1-Bit` : `${dopKhz} кГц · NOS`;
      }
      if (signalEngineName) {
        const presetLabel = (state.dspActivePresetName && state.dspActivePresetId !== 'unsaved_custom')
          ? state.dspActivePresetName
          : (isDSD ? `AMR 7th-Order SDM (${state.dspProfile || '7EC-Balanced'})` : 'AMR HQ NOS PCM Engine (LNS15 Shaper)');
        signalEngineName.textContent = translateTextToEn(presetLabel);
      }
      if (signalEngineMeta) {
        const kernLabel = (state.dspOversamplerBackend === 'metalOverlapSave') ? 'Metal GPU df64' : 'AMX FP64';
        const phaseLabel = (state.dspPhaseMode === 'minimumPhase') ? 'Min-Phase' : 'Lin-Phase';
        const baseMeta = isDSD
          ? `${kernLabel} (${phaseLabel}) → Trellis M=${state.dspTrellisOrder || 8} (${state.dspProfile || '7EC-Balanced'}) → DoP (${dopKhz} кГц)`
          : `${kernLabel} (${phaseLabel}) → 15-Order LNS15 Shaper (${dopKhz} кГц / 24-бит)`;
        signalEngineMeta.textContent = `${baseMeta}${allPreDspSuffixes}`;
      }
      if (dom.signalDacRate) {
        dom.signalDacRate.textContent = isDSD ? `DoP ${dopKhz} кГц` : `${dopKhz} кГц`;
      }
      if (dspTelemPill && dspTelemText) {
        dspTelemPill.classList.remove('hidden');
        const hogTxt = state.dspIsHogMode ? 'Hog Mode' : 'Shared';
        const intTxt = state.dspIsIntegerMode ? 'Integer' : 'Float';
        const cpuTxt = Number(state.dspCpuLoadPercent || 0).toFixed(1);
        const bufTxt = Math.round(Number(state.dspRingBufferFillPercent || 0));
        dspTelemText.textContent = `🟢 ${hogTxt} • ${intTxt} • CPU ${cpuTxt}% • Буфер ${bufTxt}%`;
      }
    } else {
      if (signalEngineBadge) signalEngineBadge.textContent = '0.0 dB FS';
      if (signalEngineName) signalEngineName.textContent = 'AMR CoreAudio Engine';
      if (dspTelemPill) dspTelemPill.classList.add('hidden');
      if (signalEngineMeta) {
        if (isNetworkRenderer) {
          const baseDlna = isLossy
            ? 'CoreAudio Process Tap • Декодирование AAC → PCM 16-бит / 44.1 кГц'
            : (anyPreDspNodeActive
              ? 'CoreAudio Process Tap (64-bit Pre-DSP) • Бесконечный PCM поток'
              : 'CoreAudio Process Tap (Bit-Perfect) • Бесконечный PCM поток');
          signalEngineMeta.textContent = `${baseDlna}${allPreDspSuffixes}`;
        } else {
          const guardLabel = state.dacMutingGuardEnabled === true
            ? `DAC Muting Guard (${state.dacMutingGuardMs || 100} мс)`
            : 'Bypass микшера';
          const ampLabel = (state.lockVolume100 && state.ampVolumeControlEnabled)
            ? `${state.ampBrandName || 'AMP'} TCP Vol ${state.ampMuted ? 'MUTE' : state.volume}`
            : (anyPreDspNodeActive ? '64-bit DSP' : 'Zero DSP');
          signalEngineMeta.textContent = isLossy
            ? `CoreAudio HAL • Декодирование AAC → PCM 16-бит / 44.1 кГц${allPreDspSuffixes}`
            : `${anyPreDspNodeActive ? 'CoreAudio 64-bit Lock' : 'Bit-Perfect 100% Lock'} • ${guardLabel} • ${ampLabel}${allPreDspSuffixes}`;
        }
      }
    }
    const signalVerifiedCard = document.querySelector('#quality-modal .signal-verified-card');
    const signalVerifiedTitle = document.querySelector('#quality-modal .signal-verified-title');
    const signalVerifiedDesc = document.querySelector('#quality-modal .signal-verified-desc');
    const shouldHideDspBanner = isLocalDspActive && !isInsufficientDsd && !isSpectralFake && !isSpectralZeroPad;
    const hasTopWarning = isLocalDspActive
      ? (isInsufficientDsd || isSpectralFake || isSpectralZeroPad)
      : (!isVerified || isSpectralFake || isSpectralZeroPad);
    if (signalVerifiedCard) {
      signalVerifiedCard.classList.toggle('hidden', shouldHideDspBanner);
      signalVerifiedCard.classList.toggle('warning', hasTopWarning);
    }
    if (!shouldHideDspBanner && signalVerifiedTitle && signalVerifiedDesc) {
      if (saVerdict === 'lossy_upscaled') {
        signalVerifiedTitle.textContent = 'Обнаружен апскейл Lossy (128 → 256 kbps)';
        signalVerifiedDesc.textContent = sa.verdict_description || sa.verdictDescription || 'Спектр жестко обрезан ниже 16.5 кГц — низкобитрейтный исходник (MP3/AAC 128 kbps) перекодирован в AAC 256 kbps.';
      } else if (saVerdict === 'lossy_transcode') {
        signalVerifiedTitle.textContent = 'Обнаружен транскод из Lossy (MP3 / AAC)';
        signalVerifiedDesc.textContent = sa.verdict_description || sa.verdictDescription || 'Внутри контейнера ALAC Lossless обнаружен жесткий срез ВЧ, характерный для сжатия с потерями.';
      } else if (saVerdict === 'upsampled') {
        signalVerifiedTitle.textContent = 'Обнаружен апсемплинг (Fake Hi-Res)';
        signalVerifiedDesc.textContent = sa.verdict_description || sa.verdictDescription || 'Поток передается в Hi-Res контейнере, но спектр ограничен частотой CD (22.05 кГц).';
      } else if (saVerdict === 'zero_padded') {
        signalVerifiedTitle.textContent = 'Zero-Padded контейнер (16-бит в 24-бит)';
        signalVerifiedDesc.textContent = sa.verdict_description || sa.verdictDescription || 'Младшие 8 бит в 24-битном потоке пустые — реальный динамический диапазон составляет 16 бит.';
      } else if (isLocalDspActive && isInsufficientDsd) {
        const srcKhz = (srcRateVal / 1000).toFixed(1).replace(/\.0$/, '');
        const recDsd = srcRateVal >= 176400 ? 'DSD256' : 'DSD128 / DSD256';
        signalVerifiedTitle.textContent = `Недостаточная частота DSD${dsdMult} для источника (${srcBitsVal}/${srcKhz})`;
        signalVerifiedDesc.textContent = `Поток источника (${srcBitsVal}-бит / ${srcKhz} кГц) превышает оптимальную полосу однобитного режима DSD${dsdMult}. Выберите ${recDsd} для раскрытия битрейта без потерь.`;
      } else if (isClockSynced64BitDsp) {
        const activeDspParts = [];
        if (isDeClipActive) {
          activeDspParts.push(`⚡️ ${deClipShort}`);
        }
        if (isDeEsserActive) {
          activeDspParts.push(`💎 ${deEsserShort}`);
        }
        if (roomEqSuffix) {
          const profName = state.roomProfileName || (state.roomAcoustic && state.roomAcoustic.active_profile && state.roomAcoustic.active_profile.name) || 'Auto-PEQ';
          activeDspParts.push(`Room EQ «${profName}»`);
        }
        if (isDrcActive) {
          activeDspParts.push(`🌙 ${drcModeShort}`);
        }
        signalVerifiedTitle.textContent = `64-bit DSP • Синхронная частота (${outBitDepth}/${rateKhz})`;
        signalVerifiedDesc.textContent = `Частота ЦАП (${rateKhz} кГц) синхронизирована 1:1 с потоком без передискретизации. Активна 64-битная обработка (${activeDspParts.join(' + ')}).`;
      } else if (isVerified) {
        signalVerifiedTitle.textContent = 'Bit-Perfect Verified';
        if (isNetworkRenderer) {
          signalVerifiedDesc.textContent = `Hi-Res PCM поток (${outBitDepth}-бит / ${rateKhz} кГц) захватывается напрямую из Music.app и передается на сетевой рендерер без передискретизации.`;
        } else {
          signalVerifiedDesc.textContent = `Частота ЦАП (${rateKhz} кГц) аппаратно синхронизирована с потоком. Деградация разрядности исключена.`;
        }
      } else if (isLossy) {
        signalVerifiedTitle.textContent = 'Lossy Stream (AAC 256 kbps)';
        signalVerifiedDesc.textContent = 'Воспроизводится сжатый поток AAC 256 kbps (полоса до ~19.5 кГц). Для Bit-Perfect переключитесь на ALAC Lossless.';
      } else {
        const srcKhz = sourceRateHz ? (sourceRateHz / 1000).toFixed(1).replace(/\.0$/, '') : rateKhz;
        const srcBits = sourceBitDepth || (srcRateVal >= 48000 ? 24 : 16);
        if (srcBits === outBitDepth && srcKhz === rateKhz) {
          signalVerifiedTitle.textContent = `Системный микшер macOS (${outBitDepth}/${rateKhz})`;
          signalVerifiedDesc.textContent = `Частота и разрядность совпадают (${outBitDepth}-бит / ${rateKhz} кГц), но поток проходит через микшер macOS CoreAudio.`;
        } else if (srcKhz === rateKhz) {
          signalVerifiedTitle.textContent = `Преобразование разрядности (${srcBits}-бит → ${outBitDepth}-бит @ ${rateKhz} кГц)`;
          signalVerifiedDesc.textContent = `Частота дискретизации синхронизирована 1:1 (${rateKhz} кГц) без передискретизации; выполняется квантование разрядности (${srcBits}-бит → ${outBitDepth}-бит).`;
        } else {
          signalVerifiedTitle.textContent = `Передискретизация (${srcBits}/${srcKhz} → ${outBitDepth}/${rateKhz})`;
          signalVerifiedDesc.textContent = `Частота дискретизации источника (${srcBits}-бит / ${srcKhz} кГц) пересчитывается в режим вывода (${outBitDepth}-бит / ${rateKhz} кГц).`;
        }
      }
    }
    syncSignalPathAmpNode();
    renderSpectralAnalysisUI();
  }

  let spectralPollTimer = null;
  let spectralPollIntervalMs = 0;
  let spectralRpcInFlightAt = 0;
  let standbyRtaRafId = null;
  let lastStandbyRtaFrameMs = 0;
  let cachedStandbyRtaBackdrop = null;
  let cachedStandbyRtaBarsWrap = null;
  let standbyRtaBarEls = [];
  const standbyRtaBarCount = 64;
  const standbyRtaUnsmoothed = new Float32Array(standbyRtaBarCount);
  const standbyRtaCurrent = new Float32Array(standbyRtaBarCount).fill(0.03);
  const standbyRtaTarget = new Float32Array(standbyRtaBarCount).fill(0.03);
  const standbyRtaVelocity = new Float32Array(standbyRtaBarCount).fill(0.0);
  const standbyRtaRendered = new Float32Array(standbyRtaBarCount).fill(-1);
  const standbyRtaClassState = new Uint8Array(standbyRtaBarCount).fill(255);

  let cachedSpectralModalBarsWrap = null;
  let spectralModalRtaBarEls = [];
  const spectralModalRtaBarCount = 32;
  const spectralModalRtaCurrent = new Float32Array(spectralModalRtaBarCount).fill(0.06);
  const spectralModalRtaTarget = new Float32Array(spectralModalRtaBarCount).fill(0.06);
  const spectralModalRtaRendered = new Float32Array(spectralModalRtaBarCount).fill(-1);
  const spectralModalRtaClassState = new Uint8Array(spectralModalRtaBarCount).fill(255);

  function stepStandbyRtaAnimation(nowMs) {
    const sa = state.spectralAnalysis || {};
    const saEnabled = sa.is_enabled !== false && sa.isEnabled !== false && sa.verdict !== 'disabled';
    const showStandby = saEnabled && isStandbyOrLandscapeVisible() && standbyRtaBarEls.length === standbyRtaBarCount;
    const showModal = saEnabled && Boolean(dom.qualityModal && !dom.qualityModal.classList.contains('hidden')) && spectralModalRtaBarEls.length === spectralModalRtaBarCount;
    if (!showStandby && !showModal) {
      standbyRtaRafId = null;
      return;
    }

    const ts = nowMs || performance.now();
    // Pace GPU scale3d transforms at locked ~60fps (15ms) for zero-judder motion on 60Hz TVs & 120Hz ProMotion
    if (ts - lastStandbyRtaFrameMs < 15) {
      standbyRtaRafId = requestAnimationFrame(stepStandbyRtaAnimation);
      return;
    }
    lastStandbyRtaFrameMs = ts;

    // Decay targets to floor if playback paused or spectral stream stalled (>1.2s)
    const spectralStale = (ts - (state.lastSpectralUpdateAt || 0)) > 1200;
    const shouldDecayToFloor = (state.playerState !== 'playing') || spectralStale;
    let hasMotion = false;

    if (showStandby) {
      for (let i = 0; i < standbyRtaBarCount; i++) {
        if (shouldDecayToFloor && standbyRtaTarget[i] > 0.03) {
          standbyRtaTarget[i] = Math.max(0.03, standbyRtaTarget[i] * 0.86);
          if (standbyRtaTarget[i] > 0.032) hasMotion = true;
        }
        const tgt = Math.max(0.025, Math.min(0.96, standbyRtaTarget[i]));
        const cur = standbyRtaCurrent[i];
        const diff = tgt - cur;
        const factor = diff > 0 ? 0.36 : 0.19;
        standbyRtaVelocity[i] = standbyRtaVelocity[i] * 0.42 + diff * factor;
        const nextVal = Math.max(0.025, Math.min(0.96, cur + standbyRtaVelocity[i]));
        standbyRtaCurrent[i] = nextVal;

        if (Math.abs(diff) > 0.0025 || Math.abs(standbyRtaVelocity[i]) > 0.0018) {
          hasMotion = true;
        }
        if (Math.abs(nextVal - standbyRtaRendered[i]) > 0.0025) {
          standbyRtaRendered[i] = nextVal;
          const bar = standbyRtaBarEls[i];
          if (bar) bar.style.transform = `scale3d(1, ${nextVal.toFixed(3)}, 1)`;
        }
      }
    }

    if (showModal) {
      for (let i = 0; i < spectralModalRtaBarCount; i++) {
        if (shouldDecayToFloor && spectralModalRtaTarget[i] > 0.06) {
          spectralModalRtaTarget[i] = Math.max(0.06, spectralModalRtaTarget[i] * 0.86);
          if (spectralModalRtaTarget[i] > 0.062) hasMotion = true;
        }
        const tgt = Math.max(0.06, Math.min(1.0, spectralModalRtaTarget[i]));
        const cur = spectralModalRtaCurrent[i];
        const diff = tgt - cur;
        const step = diff * (diff > 0 ? 0.44 : 0.24);
        const nextVal = Math.max(0.06, Math.min(1.0, cur + step));
        spectralModalRtaCurrent[i] = nextVal;

        if (Math.abs(diff) > 0.003) {
          hasMotion = true;
        }
        if (Math.abs(nextVal - spectralModalRtaRendered[i]) > 0.0025) {
          spectralModalRtaRendered[i] = nextVal;
          const bar = spectralModalRtaBarEls[i];
          if (bar) bar.style.transform = `scale3d(1, ${nextVal.toFixed(3)}, 1)`;
        }
      }
    }

    if (hasMotion) {
      standbyRtaRafId = requestAnimationFrame(stepStandbyRtaAnimation);
    } else {
      standbyRtaRafId = null;
    }
  }

// === MODULE: 10-rta-mastering-and-spectral.js ===
  function setTextIfChanged(el, nextText) {
    if (el && el.textContent !== nextText) {
      el.textContent = nextText;
    }
  }

  function ensureStandbyRtaAnimLoop() {
    const modalVisible = Boolean(dom.qualityModal && !dom.qualityModal.classList.contains('hidden'));
    if (!standbyRtaRafId && (isStandbyOrLandscapeVisible() || modalVisible)) {
      standbyRtaRafId = requestAnimationFrame(stepStandbyRtaAnimation);
    }
  }

  function renderStandbyRtaBackdrop(sa, saEnabled, isLossy, sRate, isWarning) {
    if (!cachedStandbyRtaBackdrop) cachedStandbyRtaBackdrop = document.getElementById('standby-rta-backdrop');
    if (!cachedStandbyRtaBarsWrap) cachedStandbyRtaBarsWrap = document.getElementById('standby-rta-bars');
    const backdrop = cachedStandbyRtaBackdrop;
    const barsWrap = cachedStandbyRtaBarsWrap;
    if (!backdrop || !barsWrap) return;

    backdrop.classList.toggle('hidden', !saEnabled);
    if (!saEnabled || !isStandbyOrLandscapeVisible()) return;

    const barCount = standbyRtaBarCount;
    if (barsWrap.children.length !== barCount || standbyRtaBarEls.length !== barCount) {
      barsWrap.innerHTML = '';
      standbyRtaBarEls = [];
      const frag = document.createDocumentFragment();
      for (let i = 0; i < barCount; i++) {
        const b = document.createElement('div');
        b.className = 'standby-rta-bar';
        frag.appendChild(b);
        standbyRtaBarEls.push(b);
        standbyRtaRendered[i] = -1;
        standbyRtaClassState[i] = 255;
      }
      barsWrap.appendChild(frag);
    }

    const rawBands = Array.isArray(sa.rta_bands || sa.rtaBands) && (sa.rta_bands || sa.rtaBands).length === 32
      ? (sa.rta_bands || sa.rtaBands)
      : null;
    const isPlaying = state.playerState === 'playing';
    const isHiResRate = sRate >= 88200;
    const splitBarIdx = isHiResRate ? 40 : 48;

    // 1. Interpolate 32 FFT bands to 64 raw targets (zero per-frame heap allocation)
    const unsmoothed = standbyRtaUnsmoothed;
    for (let i = 0; i < barCount; i++) {
      if (!isPlaying || !rawBands) {
        unsmoothed[i] = 0.03;
        continue;
      }
      const pos = (i / (barCount - 1)) * 31;
      const idx0 = Math.floor(pos);
      const idx1 = Math.min(31, idx0 + 1);
      const frac = pos - idx0;
      const t = frac * frac * (3 - 2 * frac);
      const v0 = Number.isFinite(Number(rawBands[idx0])) ? Number(rawBands[idx0]) : 0.03;
      const v1 = Number.isFinite(Number(rawBands[idx1])) ? Number(rawBands[idx1]) : 0.03;
      unsmoothed[i] = v0 * (1 - t) + v1 * t;
    }

    // 2. Apply crisp 5-tap spatial curve across neighboring bars
    for (let i = 0; i < barCount; i++) {
      const bar = standbyRtaBarEls[i];
      if (!isPlaying || !rawBands) {
        standbyRtaTarget[i] = 0.03;
        if (standbyRtaClassState[i] !== 4) {
          standbyRtaClassState[i] = 4;
          bar.classList.remove('ultrasonic', 'warning-bar');
          bar.classList.add('depleted');
        }
        continue;
      }

      const m2 = unsmoothed[Math.max(0, i - 2)];
      const m1 = unsmoothed[Math.max(0, i - 1)];
      const c0 = unsmoothed[i];
      const p1 = unsmoothed[Math.min(barCount - 1, i + 1)];
      const p2 = unsmoothed[Math.min(barCount - 1, i + 2)];
      const val = m2 * 0.05 + m1 * 0.20 + c0 * 0.50 + p1 * 0.20 + p2 * 0.05;

      standbyRtaTarget[i] = Math.max(0.03, Math.min(0.95, val * 0.94));

      const isAboveBoundary = i >= splitBarIdx;
      const isDepleted = isAboveBoundary && (isWarning || isLossy || val < 0.06);
      const isUltra = isAboveBoundary && !isDepleted && !isWarning;
      const isWarn = isWarning && !isDepleted;
      const classMask = (isUltra ? 1 : 0) | (isWarn ? 2 : 0) | (isDepleted ? 4 : 0);
      if (standbyRtaClassState[i] !== classMask) {
        standbyRtaClassState[i] = classMask;
        bar.classList.toggle('ultrasonic', isUltra);
        bar.classList.toggle('warning-bar', isWarn);
        bar.classList.toggle('depleted', isDepleted);
      }
      if (!standbyRtaRafId) {
        const tgtVal = standbyRtaTarget[i];
        standbyRtaRendered[i] = tgtVal;
        bar.style.transform = `scale3d(1, ${tgtVal.toFixed(3)}, 1)`;
      }
    }

    ensureStandbyRtaAnimLoop();
  }

  function renderTopAndStandbyDrBadges(sa, saEnabled) {
    const rawDr = sa.tt_dr_score !== undefined ? sa.tt_dr_score : sa.ttDrScore;
    const hasDr = saEnabled && Boolean(state.track && state.track.name) && rawDr !== null && rawDr !== undefined && Number.isFinite(Number(rawDr));
    const drScore = hasDr ? Math.max(0, Math.min(24, Math.round(Number(rawDr)))) : null;
    const drStatus = drScore === null
      ? 'analyzing'
      : (drScore >= 12 ? 'dynamic' : (drScore >= 8 ? 'balanced' : 'compressed'));
    const drLabel = drScore !== null ? `DR${drScore}` : 'DR--';
    const rawLufs = sa.integrated_lufs !== undefined ? sa.integrated_lufs : sa.integratedLufs;
    const lufsPart = (rawLufs !== null && rawLufs !== undefined && Number.isFinite(Number(rawLufs)))
      ? ` • ${Number(rawLufs).toFixed(1)} LUFS`
      : '';
    const statusHint = drScore === null
      ? ''
      : (drStatus === 'dynamic'
        ? (IS_EN ? 'Audiophile Dynamic Master' : 'Высокая динамика')
        : (drStatus === 'balanced'
          ? (IS_EN ? 'Balanced Master' : 'Сбалансированный мастер')
          : (IS_EN ? 'Loudness War Compression' : 'Перекомпрессирован (Loudness War)')));
    const tooltipText = drScore !== null
      ? `TT DR${drScore}${lufsPart} — ${statusHint}`
      : (IS_EN ? 'Mastering Dynamic Range (TT DR)' : 'Динамический диапазон мастеринга (TT DR)');

    ['player-dr-badge', 'mobile-dr-badge'].forEach((id) => {
      const el = document.getElementById(id);
      if (!el) return;
      el.classList.toggle('hidden', !hasDr);
      if (hasDr) {
        el.textContent = drLabel;
        el.title = tooltipText;
        el.classList.toggle('dynamic', drStatus === 'dynamic');
        el.classList.toggle('balanced', drStatus === 'balanced');
        el.classList.toggle('compressed', drStatus === 'compressed');
      }
    });

    const sbDrEl = document.getElementById('standby-dr-badge');
    if (sbDrEl) {
      sbDrEl.classList.toggle('hidden', !hasDr);
      if (hasDr) {
        sbDrEl.textContent = drStatus === 'compressed' ? `⚠️ ${drLabel}` : drLabel;
        sbDrEl.title = tooltipText;
        sbDrEl.classList.toggle('authentic', drStatus === 'dynamic');
        sbDrEl.classList.toggle('balanced', drStatus === 'balanced');
        sbDrEl.classList.toggle('compressed', drStatus === 'compressed');
        sbDrEl.classList.remove('neutral', 'warning');
      }
    }
  }

  function renderMasteringAndStereoCard(sa, saEnabled) {
    const mCard = document.getElementById('signal-mastering-card');
    if (!mCard) return;
    mCard.classList.toggle('hidden', !saEnabled);
    if (!saEnabled) return;

    const rawDr = sa.tt_dr_score !== undefined ? sa.tt_dr_score : sa.ttDrScore;
    const hasDr = rawDr !== null && rawDr !== undefined && Number.isFinite(Number(rawDr));
    const drScore = hasDr ? Math.max(0, Math.min(24, Math.round(Number(rawDr)))) : null;
    const drStatus = drScore === null
      ? 'analyzing'
      : (drScore >= 12 ? 'dynamic' : (drScore >= 8 ? 'balanced' : 'compressed'));

    mCard.classList.toggle('authentic', drStatus === 'dynamic');
    mCard.classList.toggle('balanced', drStatus === 'balanced');
    mCard.classList.toggle('compressed', drStatus === 'compressed');

    const drBadgeEl = document.getElementById('mastering-dr-badge');
    if (drBadgeEl) {
      drBadgeEl.classList.toggle('neutral', drStatus === 'analyzing');
      drBadgeEl.classList.toggle('balanced', drStatus === 'balanced');
      drBadgeEl.classList.toggle('compressed', drStatus === 'compressed');
      drBadgeEl.classList.remove('warning');
      if (drScore === null) {
        drBadgeEl.textContent = IS_EN ? 'DR ANALYZING...' : 'DR АНАЛИЗ...';
      } else if (drStatus === 'dynamic') {
        drBadgeEl.textContent = `DR${drScore} • DYNAMIC`;
      } else if (drStatus === 'balanced') {
        drBadgeEl.textContent = `DR${drScore} • BALANCED`;
      } else {
        drBadgeEl.textContent = `DR${drScore} • LOUDNESS WAR`;
      }
    }

    const intLufs = sa.integrated_lufs !== undefined ? sa.integrated_lufs : sa.integratedLufs;
    const stLufs = sa.short_term_lufs !== undefined ? sa.short_term_lufs : sa.shortTermLufs;
    const momLufs = sa.momentary_lufs !== undefined ? sa.momentary_lufs : sa.momentaryLufs;
    const lraLu = sa.loudness_range_lu !== undefined ? sa.loudness_range_lu : sa.loudnessRangeLu;
    const tpDbtp = sa.true_peak_dbtp !== undefined ? sa.true_peak_dbtp : sa.truePeakDbtp;
    const ispClips = Number(sa.isp_clip_count !== undefined ? sa.isp_clip_count : (sa.ispClipCount || 0));

    const lufsIntEl = document.getElementById('mastering-lufs-int');
    if (lufsIntEl) {
      lufsIntEl.textContent = (intLufs !== null && intLufs !== undefined && Number.isFinite(Number(intLufs)))
        ? `${Number(intLufs).toFixed(1)} LUFS`
        : '— LUFS';
    }

    const lufsStEl = document.getElementById('mastering-lufs-st');
    if (lufsStEl) {
      const stDisplay = (stLufs !== null && stLufs !== undefined && Number.isFinite(Number(stLufs)))
        ? Number(stLufs)
        : ((momLufs !== null && momLufs !== undefined && Number.isFinite(Number(momLufs))) ? Number(momLufs) : null);
      lufsStEl.textContent = stDisplay !== null ? `${stDisplay.toFixed(1)} LUFS` : '— LUFS';
    }

    const tpEl = document.getElementById('mastering-true-peak');
    if (tpEl) {
      if (tpDbtp !== null && tpDbtp !== undefined && Number.isFinite(Number(tpDbtp))) {
        const tpNum = Number(tpDbtp);
        const sign = tpNum > 0 ? '+' : '';
        tpEl.textContent = `${sign}${tpNum.toFixed(2)} dBTP`;
        tpEl.classList.toggle('tp-warning', tpNum > 0.0 || ispClips > 0);
      } else {
        tpEl.textContent = '— dBTP';
        tpEl.classList.remove('tp-warning');
      }
    }

    const lraEl = document.getElementById('mastering-lra');
    if (lraEl) {
      lraEl.textContent = (lraLu !== null && lraLu !== undefined && Number.isFinite(Number(lraLu)))
        ? `${Number(lraLu).toFixed(1)} LU`
        : '— LU';
    }

    // Stereo Phase Correlation (-1 ... 0 ... +1), Width & Balance
    const rawCorr = Number(sa.phase_correlation !== undefined ? sa.phase_correlation : (sa.phaseCorrelation !== undefined ? sa.phaseCorrelation : 1.0));
    const corr = Number.isFinite(rawCorr) ? Math.max(-1.0, Math.min(1.0, rawCorr)) : 1.0;
    const rawWidth = Number(sa.stereo_width_percent !== undefined ? sa.stereo_width_percent : (sa.stereoWidthPercent || 0));
    const widthPct = Number.isFinite(rawWidth) ? Math.max(0, Math.min(100, Math.round(rawWidth))) : 0;
    const rawBal = Number(sa.channel_balance_db !== undefined ? sa.channel_balance_db : (sa.channelBalanceDb || 0));
    const balDb = Number.isFinite(rawBal) ? rawBal : 0.0;

    const phaseValEl = document.getElementById('phase-meter-val');
    if (phaseValEl) {
      const sign = corr >= 0 ? '+' : '';
      phaseValEl.textContent = `${sign}${corr.toFixed(2)}`;
      phaseValEl.classList.toggle('negative', corr < 0);
      phaseValEl.classList.toggle('wide', corr >= 0 && corr < 0.45);
    }

    const phaseFillEl = document.getElementById('phase-meter-fill');
    const phaseDotEl = document.getElementById('phase-meter-dot');
    const dotPct = ((corr + 1.0) * 0.5) * 100.0;
    if (phaseDotEl) {
      phaseDotEl.style.left = `${dotPct.toFixed(1)}%`;
    }
    if (phaseFillEl) {
      if (corr >= 0) {
        phaseFillEl.style.left = '50%';
        phaseFillEl.style.width = `${(corr * 50.0).toFixed(1)}%`;
        phaseFillEl.classList.add('positive');
        phaseFillEl.classList.remove('negative');
      } else {
        const w = Math.abs(corr) * 50.0;
        phaseFillEl.style.left = `${(50.0 - w).toFixed(1)}%`;
        phaseFillEl.style.width = `${w.toFixed(1)}%`;
        phaseFillEl.classList.add('negative');
        phaseFillEl.classList.remove('positive');
      }
    }

    const widthEl = document.getElementById('stereo-width-val');
    if (widthEl) {
      widthEl.textContent = `${widthPct}%`;
    }

    const balEl = document.getElementById('stereo-balance-val');
    if (balEl) {
      if (Math.abs(balDb) < 0.15) {
        balEl.textContent = IS_EN ? 'Center (0.0 dB)' : 'Центр (0.0 дБ)';
      } else {
        const side = balDb > 0 ? 'R' : 'L';
        balEl.textContent = `${side} +${Math.abs(balDb).toFixed(1)} ${IS_EN ? 'dB' : 'дБ'}`;
      }
    }

    const ispBadge = document.getElementById('isp-clips-badge');
    if (ispBadge) {
      ispBadge.classList.toggle('hidden', ispClips <= 0);
      if (ispClips > 0) {
        ispBadge.textContent = IS_EN ? `ISP Overs: ${ispClips}` : `ISP >0 dBTP: ${ispClips}`;
      }
    }

    const mTitleEl = document.getElementById('mastering-verdict-title');
    const mDescEl = document.getElementById('mastering-verdict-desc');
    if (mTitleEl && mDescEl) {
      if (drScore === null) {
        mTitleEl.textContent = state.playerState === 'playing'
          ? (IS_EN ? 'Measuring TT Dynamic Range & EBU R128...' : 'Расчёт TT Dynamic Range и EBU R128...')
          : (IS_EN ? 'Waiting for playback...' : 'Ожидание воспроизведения...');
        mDescEl.textContent = IS_EN
          ? 'Accumulating 3-second PCM windows for official TT DR score, ITU-R BS.1770-4 loudness, and 4x True Peak.'
          : 'Накопление 3-секундных блоков PCM для расчёта официального индекса TT Dynamic Range, громкости ITU-R BS.1770-4 и 4x True Peak.';
      } else if (drStatus === 'dynamic') {
        mTitleEl.textContent = IS_EN
          ? `Audiophile Dynamic Master (DR${drScore})`
          : `Эталонная динамика мастеринга (DR${drScore})`;
        mDescEl.textContent = IS_EN
          ? 'Natural micro-dynamics and transient punch preserved without brickwall limiting.'
          : 'Свободные транзиенты и живая микродинамика сохранены без агрессивного brickwall-лимитирования.';
      } else if (drStatus === 'balanced') {
        mTitleEl.textContent = IS_EN
          ? `Balanced Studio Master (DR${drScore})`
          : `Сбалансированный студийный мастер (DR${drScore})`;
        mDescEl.textContent = IS_EN
          ? 'Moderate studio bus compression with healthy crest factor for modern genres.'
          : 'Умеренная студийная компрессия с комфортным запасом пик-фактора для современных жанров.';
      } else {
        mTitleEl.textContent = IS_EN
          ? `Heavy Compression • Loudness War (DR${drScore})`
          : `Перекомпрессия «Войны громкости» (DR${drScore})`;
        mDescEl.textContent = ispClips > 0
          ? (IS_EN
            ? `Aggressive brickwall limiting detected with ${ispClips} inter-sample peaks (>0 dBTP). ISP Headroom Guard in DSP Engine prevents DAC clipping.`
            : `Обнаружено жесткое лимитирование и ${ispClips} межсэмпловых перегрузок (>0 dBTP). Защита ISP Headroom Guard в DSP предотвращает клиппинг ЦАПа.`)
          : (IS_EN
            ? 'Dense brickwall limiting reduces transient contrast; after loudness normalization such tracks sound less punchy than high-DR masters.'
            : 'Плотный brickwall-лимитер сжал транзиенты: при выравнивании громкости такой трек звучит субъективно тише и менее рельефно, чем динамичный мастер.');
      }
    }
  }

  function applyDeviceCapabilityPermissionsUI(options = {}) {
    const canSelectDac = state.allowDacSelection !== false;
    const canSelectDspPerm = state.allowDspPresetSelection !== false;
    const canMeasureRoom = state.allowRoomMeasurement !== false;
    const canControlRoomEq = canMeasureRoom || canSelectDspPerm;
    const canControlLateNight = state.allowLateNightMode !== false;
    const canModifyLib = state.allowLibraryModification !== false;
    document.body.classList.toggle('library-mod-locked', !canModifyLib);
    if (dom.btnSaveQueuePlaylist) {
      dom.btnSaveQueuePlaylist.classList.toggle('hidden', !canModifyLib);
      if (!canModifyLib) dom.btnSaveQueuePlaylist.disabled = true;
    }
    if (!canModifyLib) {
      if (dom.btnAddPlaylistLibrary) dom.btnAddPlaylistLibrary.classList.add('hidden');
      if (dom.btnRemoveDetailLibrary) dom.btnRemoveDetailLibrary.classList.add('hidden');
      if (dom.btnRemoveArtistDetailLibrary) dom.btnRemoveArtistDetailLibrary.classList.add('hidden');
      if (dom.btnAddTrackLibrary) dom.btnAddTrackLibrary.classList.add('hidden');
      if (dom.btnRemoveTrackLibrary) dom.btnRemoveTrackLibrary.classList.add('hidden');
      if (dom.btnRemoveArtistLibrary) dom.btnRemoveArtistLibrary.classList.add('hidden');
    }
    const activeDev = (state.audioDevices || []).find(d => d && (d.name === state.audioDeviceName || d.isDefault || d.is_default));
    const isNetworkOut = Boolean(
      state.isDlnaActive ||
      (activeDev && (activeDev.type === 'dlna' || activeDev.isNetwork || activeDev.is_network || activeDev.protocol === 'dlna' || activeDev.protocol === 'bluos'))
    );

    if (dom.btnOpenDevices) {
      dom.btnOpenDevices.classList.toggle('hidden', !canSelectDac);
      dom.btnOpenDevices.disabled = !canSelectDac;
    }
    if (!canSelectDac && dom.devicesModal && !dom.devicesModal.classList.contains('hidden')) {
      blurFocusedInContainer(dom.devicesModal);
      dom.devicesModal.classList.add('hidden');
      dom.devicesModal.setAttribute('aria-hidden', 'true');
    }

    const dspFieldEl = document.getElementById('dsp-preset-field');
    const dspSelectEl = document.getElementById('dsp-preset-select');
    const dspReadonlyEl = document.getElementById('dsp-preset-readonly-note');
    if (dspFieldEl) {
      dspFieldEl.classList.toggle('hidden', !canSelectDspPerm);
    }
    if (dspSelectEl) {
      dspSelectEl.disabled = !canSelectDspPerm || isNetworkOut;
      if (isNetworkOut && Array.from(dspSelectEl.options).some(o => o.value === 'builtin_passthrough')) {
        dspSelectEl.value = 'builtin_passthrough';
      }
    }
    if (dspReadonlyEl) {
      if (!canSelectDspPerm) {
        dspReadonlyEl.classList.remove('hidden');
        const presetLabel = isNetworkOut
          ? 'Bit-Perfect Passthrough'
          : (state.dspActivePresetName
            ? translateTextToEn(state.dspActivePresetName)
            : (state.dspMode === 'sdm_dop' ? `DSD${state.dspRate || 256} DoP` : (state.dspMode === 'hq_nos_pcm' ? 'HQ PCM NOS' : 'Bit-Perfect Passthrough')));
        dspReadonlyEl.textContent = IS_EN
          ? `🔒 Preset: ${presetLabel} (selection locked on Mac)`
          : `🔒 Пресет: ${presetLabel} (выбор закрыт в настройках Mac)`;
      } else if (isNetworkOut) {
        dspReadonlyEl.classList.remove('hidden');
        dspReadonlyEl.textContent = IS_EN
          ? '🌐 DSP presets disabled for external BluOS / DLNA network players'
          : '🌐 Пресеты DSP отключены при выводе на сетевой плеер BluOS / DLNA';
      } else {
        dspReadonlyEl.classList.add('hidden');
      }
    }

    const deClipFieldEl = document.getElementById('mastering-declip-field');
    const deClipSelectEl = document.getElementById('mastering-declip-select');
    const deClipReadonlyEl = document.getElementById('mastering-declip-readonly-note');
    if (deClipFieldEl) {
      deClipFieldEl.classList.toggle('hidden', !canSelectDspPerm);
    }
    if (deClipSelectEl) {
      deClipSelectEl.disabled = !canSelectDspPerm;
    }
    if (deClipReadonlyEl) {
      if (!canSelectDspPerm) {
        deClipReadonlyEl.classList.remove('hidden');
        const dcMode = state.masteringDeclipMode || 'off';
        const dcLabel = dcMode === 'off'
          ? (IS_EN ? 'Off (100% Bit-Perfect)' : 'Выкл (100% Bit-Perfect)')
          : (dcMode === 'studio' ? 'Studio De-Clip' : (dcMode === 'gentle' ? 'Gentle De-Clip' : 'Auto De-Clip'));
        deClipReadonlyEl.textContent = IS_EN
          ? `🔒 De-Clipper: ${dcLabel} (locked on Mac)`
          : `🔒 De-Clipper: ${dcLabel} (доступ закрыт в настройках Mac)`;
      } else {
        deClipReadonlyEl.classList.add('hidden');
      }
    }

    const deEsserFieldEl = document.getElementById('mastering-deesser-field');
    const deEsserSelectEl = document.getElementById('mastering-deesser-select');
    const deEsserReadonlyEl = document.getElementById('mastering-deesser-readonly-note');
    if (deEsserFieldEl) {
      deEsserFieldEl.classList.toggle('hidden', !canSelectDspPerm);
    }
    if (deEsserSelectEl) {
      deEsserSelectEl.disabled = !canSelectDspPerm;
    }
    if (deEsserReadonlyEl) {
      if (!canSelectDspPerm) {
        deEsserReadonlyEl.classList.remove('hidden');
        const deMode = state.masteringDeesserMode || 'off';
        const deLabel = deMode === 'off'
          ? (IS_EN ? 'Off (100% Bit-Perfect)' : 'Выкл (100% Bit-Perfect)')
          : (deMode === 'vocal' ? 'Weiss Studio' : 'Gentle');
        deEsserReadonlyEl.textContent = IS_EN
          ? `🔒 Weiss De-Esser: ${deLabel} (locked on Mac)`
          : `🔒 Weiss De-Esser: ${deLabel} (доступ закрыт в настройках Mac)`;
      } else {
        deEsserReadonlyEl.classList.add('hidden');
      }
    }

    const drcFieldEl = document.getElementById('late-night-drc-field');
    const drcSelectEl = document.getElementById('late-night-drc-select');
    const drcReadonlyEl = document.getElementById('late-night-drc-readonly-note');
    if (drcFieldEl) {
      drcFieldEl.classList.toggle('hidden', !canControlLateNight);
    }
    if (drcSelectEl) {
      drcSelectEl.disabled = !canControlLateNight;
    }
    if (drcReadonlyEl) {
      if (!canControlLateNight) {
        drcReadonlyEl.classList.remove('hidden');
        const activeMode = (state.lateNightDrcMode === 'gentle' || state.lateNightDrcMode === 'concert')
          ? state.lateNightDrcMode
          : 'off';
        const statusTxt = activeMode === 'concert'
          ? (IS_EN ? 'Night Concert' : 'Ночной концерт')
          : (activeMode === 'gentle'
            ? (IS_EN ? 'Gentle DRC' : 'Деликатный')
            : (IS_EN ? 'Off (100% Bit-Perfect)' : 'Выкл (100% Bit-Perfect)'));
        drcReadonlyEl.textContent = IS_EN
          ? `🔒 Late-Night DRC: ${statusTxt} (access disabled on Mac)`
          : `🔒 Ночной режим: ${statusTxt} (доступ закрыт в настройках Mac)`;
      } else {
        drcReadonlyEl.classList.add('hidden');
      }
    }

    const roomActionsEl = document.getElementById('room-measure-actions');
    const roomLockedEl = document.getElementById('room-measure-locked-note');
    const btnStartRoom = document.getElementById('btn-start-room-measure');
    const btnUploadRoom = document.getElementById('btn-upload-room-audio');
    const roomToggleBtn = document.getElementById('btn-room-eq-toggle');
    const roomProfileSelect = document.getElementById('room-profile-select');
    const hasRoomProfiles = Boolean(
      state.roomAcoustic &&
      Array.isArray(state.roomAcoustic.profiles) &&
      state.roomAcoustic.profiles.length > 0
    );
    if (roomActionsEl) {
      roomActionsEl.classList.toggle('hidden', !canMeasureRoom);
    }
    if (btnStartRoom) {
      btnStartRoom.disabled = !canMeasureRoom || state.isMeasuringRoom;
    }
    if (btnUploadRoom) {
      btnUploadRoom.disabled = !canMeasureRoom || state.isMeasuringRoom;
    }
    if (roomToggleBtn) {
      roomToggleBtn.disabled = !hasRoomProfiles || !canControlRoomEq;
    }
    if (roomProfileSelect) {
      roomProfileSelect.disabled = !hasRoomProfiles || !canControlRoomEq;
    }
    if (roomLockedEl) {
      roomLockedEl.classList.toggle('hidden', canMeasureRoom);
    }
    if (!options.fromRoomAcousticUI && state.roomAcoustic) {
      updateRoomAcousticUI(state.roomAcoustic, { skipSignalRefresh: true, skipPermissionsSync: true });
    }
  }

  function renderSpectralAnalysisUI() {
    const quality = state.audioQuality || 'Lossless (ALAC 24-bit/48kHz)';
    const isLossy = quality.toUpperCase().includes('AAC') || quality.toUpperCase().includes('MP3');
    const devRateHz = state.audioDeviceSampleRate || 44100;
    const sa = state.spectralAnalysis || {};
    const saEnabled = sa.is_enabled !== false && sa.isEnabled !== false && sa.verdict !== 'disabled';
    const verdict = sa.verdict || (isLossy ? 'aac_lossy' : (devRateHz > 48000 ? 'verified_hires' : 'verified_lossless'));
    const sRate = Number(sa.sample_rate || sa.sampleRate || devRateHz);
    const isWarning = (verdict === 'upsampled' || verdict === 'lossy_transcode' || verdict === 'zero_padded' || verdict === 'lossy_upscaled');

    renderStandbyRtaBackdrop(sa, saEnabled, isLossy, sRate, isWarning);
    renderTopAndStandbyDrBadges(sa, saEnabled);

    const isModalOpen = Boolean(dom.qualityModal && !dom.qualityModal.classList.contains('hidden'));
    if (!isModalOpen) return;

    renderMasteringAndStereoCard(sa, saEnabled);

    const card = document.getElementById('signal-spectral-card');
    if (!card) return;

    card.classList.toggle('hidden', !saEnabled);
    if (!saEnabled) return;

    const nyquistHz = Number(sa.nyquist_frequency_hz || sa.nyquistFrequencyHz || (sRate / 2));
    const cutoffHz = Number(sa.cutoff_frequency_hz || sa.cutoffFrequencyHz || (isLossy ? 19200 : nyquistHz));
    const effBits = Number(sa.effective_bit_depth || sa.effectiveBitDepth || (isLossy ? 16 : (sRate >= 48000 ? 24 : 16)));
    const claimedBits = Number(sa.claimed_bit_depth || sa.claimedBitDepth || effBits);
    const isZeroPadded = Boolean(sa.is_zero_padded || sa.isZeroPadded);
    const ultraDb = Number(sa.ultrasonic_energy_db !== undefined ? sa.ultrasonic_energy_db : (sa.ultrasonicEnergyDb !== undefined ? sa.ultrasonicEnergyDb : -92));

    const isNeutral = (verdict === 'aac_lossy' || verdict === 'analyzing');

    card.classList.toggle('warning', isWarning);
    card.classList.toggle('authentic', !isWarning && !isNeutral);

    const badgeEl = document.getElementById('spectral-verdict-badge');
    if (badgeEl) {
      badgeEl.classList.toggle('warning', isWarning);
      badgeEl.classList.toggle('neutral', isNeutral);
      const badgeMap = {
        verified_hires: sRate > 48000 ? 'TRUE HI-RES' : 'TRUE 24-BIT',
        verified_lossless: 'TRUE LOSSLESS',
        upsampled: 'FAKE HI-RES • 22k CUT',
        lossy_transcode: 'LOSSY TRANSCODE',
        lossy_upscaled: 'UPSCALE 128→256K',
        zero_padded: 'ZERO-PADDED 16→24',
        aac_lossy: 'AAC 256 KBPS',
        analyzing: 'FFT АНАЛИЗ...'
      };
      setTextIfChanged(badgeEl, badgeMap[verdict] || 'TRUE LOSSLESS');
    }

    const titleEl = document.getElementById('spectral-verdict-title');
    if (titleEl) {
      setTextIfChanged(titleEl, sa.verdict_title || sa.verdictTitle || (isLossy ? 'Сжатый поток AAC 256 kbps' : 'Verified True Lossless'));
    }

    const descEl = document.getElementById('spectral-verdict-desc');
    if (descEl) {
      setTextIfChanged(descEl, sa.verdict_description || sa.verdictDescription || 'Спектральный анализ потока CoreAudio Process Tap через Accelerate vDSP FFT.');
    }

    const cutoffEl = document.getElementById('spectral-metric-cutoff');
    if (cutoffEl) {
      setTextIfChanged(cutoffEl, `до ${(cutoffHz / 1000).toFixed(1)} кГц`);
    }

    const ultraEl = document.getElementById('spectral-metric-ultra');
    if (ultraEl) {
      const ultraText = sRate >= 88200
        ? (ultraDb > -80 ? `${Math.round(ultraDb)} dBFS` : 'Нет (<-82 dB)')
        : 'Н/Д (≤ 48 кГц)';
      setTextIfChanged(ultraEl, ultraText);
    }

    const bitsEl = document.getElementById('spectral-metric-bits');
    if (bitsEl) {
      const bitsText = isZeroPadded
        ? `16-бит (в ${claimedBits}-бит)`
        : `${effBits}-бит (${effBits >= 24 ? 'Честный LSB' : 'PCM'})`;
      setTextIfChanged(bitsEl, bitsText);
    }

    const markerEl = document.getElementById('spectral-cutoff-marker');
    const markerLabelEl = document.getElementById('spectral-cutoff-marker-label');
    const axisRefEl = document.getElementById('spectral-axis-ref');
    const axisNyqEl = document.getElementById('spectral-axis-nyquist');
    const isHiResRate = sRate >= 88200;

    if (markerEl && markerLabelEl) {
      const nextLeft = isHiResRate ? '62.5%' : '75%';
      if (markerEl.style.left !== nextLeft) markerEl.style.left = nextLeft;
      setTextIfChanged(markerLabelEl, isHiResRate ? '22.05 кГц CD' : '18.0 кГц AAC');
    }
    if (axisRefEl) {
      setTextIfChanged(axisRefEl, isHiResRate ? '22.05 кГц' : '18.0 кГц');
    }
    if (axisNyqEl) {
      setTextIfChanged(axisNyqEl, `${(nyquistHz / 1000).toFixed(1).replace(/\.0$/, '')} кГц`);
    }

    if (!cachedSpectralModalBarsWrap) {
      cachedSpectralModalBarsWrap = document.getElementById('spectral-rta-bars');
    }
    const barsContainer = cachedSpectralModalBarsWrap;
    if (barsContainer) {
      if (barsContainer.children.length !== spectralModalRtaBarCount || spectralModalRtaBarEls.length !== spectralModalRtaBarCount) {
        barsContainer.innerHTML = '';
        spectralModalRtaBarEls = [];
        const frag = document.createDocumentFragment();
        for (let i = 0; i < spectralModalRtaBarCount; i++) {
          const b = document.createElement('div');
          b.className = 'spectral-rta-bar';
          frag.appendChild(b);
          spectralModalRtaBarEls.push(b);
          spectralModalRtaRendered[i] = -1;
          spectralModalRtaClassState[i] = 255;
        }
        barsContainer.appendChild(frag);
      }
      const rawBands = Array.isArray(sa.rta_bands || sa.rtaBands) && (sa.rta_bands || sa.rtaBands).length === spectralModalRtaBarCount
        ? (sa.rta_bands || sa.rtaBands)
        : null;
      const isPlaying = state.playerState === 'playing';

      const splitIdx = isHiResRate ? 20 : 24;
      for (let i = 0; i < spectralModalRtaBarCount; i++) {
        const bar = spectralModalRtaBarEls[i];
        let val = (isPlaying && rawBands) ? Number(rawBands[i]) : 0.06;
        if (!Number.isFinite(val)) val = 0.06;
        const clamped = Math.max(0.06, Math.min(1.0, val));
        spectralModalRtaTarget[i] = clamped;

        const isAboveBoundary = i >= splitIdx;
        const isDepleted = isAboveBoundary && (isWarning || isLossy || clamped < 0.065);
        const isUltra = isAboveBoundary && !isDepleted && !isWarning;
        const isWarn = isWarning && !isDepleted;
        const classMask = (isUltra ? 1 : 0) | (isWarn ? 2 : 0) | (isDepleted ? 4 : 0);
        if (spectralModalRtaClassState[i] !== classMask) {
          spectralModalRtaClassState[i] = classMask;
          bar.classList.toggle('ultrasonic', isUltra);
          bar.classList.toggle('warning-bar', isWarn);
          bar.classList.toggle('depleted', isDepleted);
        }
        if (!standbyRtaRafId) {
          spectralModalRtaCurrent[i] = clamped;
          spectralModalRtaRendered[i] = clamped;
          bar.style.transform = `scale3d(1, ${clamped.toFixed(3)}, 1)`;
        }
      }
      ensureStandbyRtaAnimLoop();
    }
  }

// === MODULE: 11-spectral-polling-devices-and-auth.js ===
  let cachedStandbyOverlayEl = null;
  let cachedCoarsePointerMql = null;

  function stopSpectralPolling() {
    if (spectralPollTimer) {
      clearInterval(spectralPollTimer);
      spectralPollTimer = null;
    }
    spectralPollIntervalMs = 0;
    spectralRpcInFlightAt = 0;
  }

  function isStandbyOrLandscapeVisible() {
    if (!cachedStandbyOverlayEl) {
      cachedStandbyOverlayEl = document.getElementById('standby-tv-overlay');
    }
    const isExplicitOpen = Boolean(cachedStandbyOverlayEl && !cachedStandbyOverlayEl.classList.contains('hidden'));
    if (isExplicitOpen) return true;
    if (!cachedCoarsePointerMql && window.matchMedia) {
      cachedCoarsePointerMql = window.matchMedia('(hover: none) and (pointer: coarse)');
    }
    const isTouchPhone = Boolean(cachedCoarsePointerMql && cachedCoarsePointerMql.matches);
    return isTouchPhone && window.innerHeight <= 540 && window.innerWidth >= 568 && window.innerWidth > window.innerHeight && !document.body.classList.contains('keyboard-open');
  }

  function handleSpectralAnalysisMessage(data) {
    spectralRpcInFlightAt = 0;
    if (!data || !data.verdict) return;
    const prev = state.spectralAnalysis || {};
    const prevVerdict = prev.verdict || '';
    const prevRate = Number(prev.sample_rate || prev.sampleRate || 0);
    const prevZeroPad = Boolean(prev.is_zero_padded || prev.isZeroPadded);
    const prevEnabled = prev.is_enabled !== false && prev.isEnabled !== false && prevVerdict !== 'disabled';

    const merged = (prevVerdict === data.verdict && data.verdict_title === undefined && data.verdictTitle === undefined)
      ? Object.assign({}, prev, data)
      : data;
    state.spectralAnalysis = merged;
    state.lastSpectralUpdateAt = performance.now();

    const nextRate = Number(merged.sample_rate || merged.sampleRate || 0);
    const nextZeroPad = Boolean(merged.is_zero_padded || merged.isZeroPadded);
    const nextEnabled = merged.is_enabled !== false && merged.isEnabled !== false && merged.verdict !== 'disabled';

    if (prevVerdict !== merged.verdict || prevRate !== nextRate || prevZeroPad !== nextZeroPad || prevEnabled !== nextEnabled) {
      updateSignalPathDetails();
    } else {
      renderSpectralAnalysisUI();
    }
  }

  let spectralPollTickCount = 0;
  function syncSpectralPolling() {
    if (document.hidden) {
      stopSpectralPolling();
      return;
    }
    const sa = state.spectralAnalysis || {};
    const saEnabled = sa.is_enabled !== false && sa.isEnabled !== false && sa.verdict !== 'disabled';
    const isModalOpen = Boolean(dom.qualityModal && !dom.qualityModal.classList.contains('hidden'));
    const isTvActive = isStandbyOrLandscapeVisible();
    const isCachedPass = Boolean(sa.is_cached || sa.isCached);
    const hasDrScore = (sa.tt_dr_score !== undefined && sa.tt_dr_score !== null) || (sa.ttDrScore !== undefined && sa.ttDrScore !== null);
    const stillAnalyzing = (!isCachedPass && (!sa.verdict || sa.verdict === 'analyzing')) || (!hasDrScore && spectralPollTickCount < 24);
    const needsSoundCheck = Boolean(state.ampSoundCheckEnabled && (state.ampSoundCheckGainDb === null || state.ampSoundCheckGainDb === undefined));
    const isPlayingAndNeeded = state.playerState === 'playing' && saEnabled && (isTvActive || stillAnalyzing || needsSoundCheck);

    if (isModalOpen || isPlayingAndNeeded) {
      const isVisualRtaActive = isModalOpen || (isTvActive && state.playerState === 'playing' && saEnabled);
      const desiredIntervalMs = isVisualRtaActive ? 90 : 220;
      if (spectralPollTimer && spectralPollIntervalMs !== desiredIntervalMs) {
        clearInterval(spectralPollTimer);
        spectralPollTimer = null;
      }
      if (!spectralPollTimer) {
        spectralPollIntervalMs = desiredIntervalMs;
        spectralPollTimer = setInterval(() => {
          if (document.hidden) {
            stopSpectralPolling();
            return;
          }
          spectralPollTickCount += 1;
          const curSa = state.spectralAnalysis || {};
          const curEnabled = curSa.is_enabled !== false && curSa.isEnabled !== false && curSa.verdict !== 'disabled';
          const modalStillOpen = Boolean(dom.qualityModal && !dom.qualityModal.classList.contains('hidden'));
          const tvStillActive = isStandbyOrLandscapeVisible() && state.playerState === 'playing' && curEnabled;
          const curCachedPass = Boolean(curSa.is_cached || curSa.isCached);
          const curHasDr = (curSa.tt_dr_score !== undefined && curSa.tt_dr_score !== null) || (curSa.ttDrScore !== undefined && curSa.ttDrScore !== null);
          const curStillAnalyzing = state.playerState === 'playing' && curEnabled && (
            (!curCachedPass && (!curSa.verdict || curSa.verdict === 'analyzing')) ||
            (!curHasDr && spectralPollTickCount < 24)
          );
          const curNeedsSoundCheck = state.playerState === 'playing' && Boolean(state.ampSoundCheckEnabled && (state.ampSoundCheckGainDb === null || state.ampSoundCheckGainDb === undefined));
          if (!modalStillOpen && !tvStillActive && !curStillAnalyzing && !curNeedsSoundCheck) {
            stopSpectralPolling();
            return;
          }
          const wantFastNow = modalStillOpen || tvStillActive;
          if ((wantFastNow ? 90 : 220) !== spectralPollIntervalMs) {
            syncSpectralPolling();
            return;
          }
          const nowPerf = performance.now();
          if (spectralRpcInFlightAt > 0 && (nowPerf - spectralRpcInFlightAt) < 420) {
            return;
          }
          const hasFullVerdictStrings = Boolean(curSa.verdict && curSa.verdict !== 'analyzing' && (curSa.verdict_title || curSa.verdictTitle));
          const useCompactRta = wantFastNow && hasFullVerdictStrings && (spectralPollTickCount % 12 !== 0);
          spectralRpcInFlightAt = nowPerf;
          if (!send({ action: useCompactRta ? 'get_spectral_rta' : 'get_spectral_analysis' })) {
            spectralRpcInFlightAt = 0;
          }
        }, desiredIntervalMs);
      }
      ensureStandbyRtaAnimLoop();
    } else {
      stopSpectralPolling();
      ensureStandbyRtaAnimLoop();
    }
  }

  const openQualityModal = () => {
    triggerHaptic('light');
    if (dom.qualityModal) {
      dom.qualityModal.classList.remove('hidden');
      dom.qualityModal.setAttribute('aria-hidden', 'false');
    }
    applyDeviceCapabilityPermissionsUI();
    updateSignalPathDetails();
    ensureStandbyRtaAnimLoop();
    send({ action: 'get_dsp_settings' });
    send({ action: 'get_spectral_analysis' });
    syncSpectralPolling();
  };

  if (dom.audioQualityBadge) dom.audioQualityBadge.addEventListener('click', openQualityModal);
  if (dom.desktopDacBadge) dom.desktopDacBadge.addEventListener('click', openQualityModal);
  if (dom.mobileDacBadge) dom.mobileDacBadge.addEventListener('click', openQualityModal);
  const playerDrBadgeEl = document.getElementById('player-dr-badge');
  const mobileDrBadgeEl = document.getElementById('mobile-dr-badge');
  const standbyDacBadgeEl = document.getElementById('standby-dac-badge');
  const standbySpectralBadgeEl = document.getElementById('standby-spectral-badge');
  const standbyDrBadgeEl = document.getElementById('standby-dr-badge');
  if (playerDrBadgeEl) playerDrBadgeEl.addEventListener('click', openQualityModal);
  if (mobileDrBadgeEl) mobileDrBadgeEl.addEventListener('click', openQualityModal);
  if (standbyDacBadgeEl) standbyDacBadgeEl.addEventListener('click', openQualityModal);
  if (standbySpectralBadgeEl) standbySpectralBadgeEl.addEventListener('click', openQualityModal);
  if (standbyDrBadgeEl) standbyDrBadgeEl.addEventListener('click', openQualityModal);

  function closeQualityModal() {
    if (state.isMeasuringRoom || state.roomIsPlayingTestSignal || (state.roomAcoustic && state.roomAcoustic.is_test_signal_playing)) {
      stopRoomMeasurementSession(true);
    }
    if (dom.qualityModal) {
      blurFocusedInContainer(dom.qualityModal);
      dom.qualityModal.classList.add('hidden');
      dom.qualityModal.setAttribute('aria-hidden', 'true');
    }
    syncSpectralPolling();
  }

  if (dom.btnCloseModal) {
    dom.btnCloseModal.addEventListener('click', closeQualityModal);
  }

  // --- Audio Output Devices Modal (DAC Selector) ---
  const openDevicesModal = () => {
    if (state.allowDacSelection === false) {
      showToast(IS_EN ? 'DAC selection is disabled for this device on Mac' : 'Выбор ЦАП отключён для этого устройства в настройках Mac');
      return;
    }
    triggerHaptic('light');
    if (dom.devicesModal) {
      dom.devicesModal.classList.remove('hidden');
      dom.devicesModal.setAttribute('aria-hidden', 'false');
      send({ action: 'get_audio_devices' });
    }
  };

  if (dom.btnOpenDevices) dom.btnOpenDevices.addEventListener('click', openDevicesModal);

  if (dom.btnCloseDevices) {
    dom.btnCloseDevices.addEventListener('click', () => {
      if (dom.devicesModal) {
        blurFocusedInContainer(dom.devicesModal);
        dom.devicesModal.classList.add('hidden');
        dom.devicesModal.setAttribute('aria-hidden', 'true');
      }
    });
  }

  if (dom.devicesModal) {
    dom.devicesModal.addEventListener('click', (e) => {
      if (e.target === dom.devicesModal) {
        blurFocusedInContainer(dom.devicesModal);
        dom.devicesModal.classList.add('hidden');
        dom.devicesModal.setAttribute('aria-hidden', 'true');
      }
    });
  }

  function updateAudioDevices(data) {
    let list = [];
    if (Array.isArray(data)) {
      list = data;
    } else if (data && Array.isArray(data.devices)) {
      list = data.devices;
    }
    state.audioDevices = list;

    const currentDevObj = (data && !Array.isArray(data) && data.current_device && typeof data.current_device === 'object')
      ? data.current_device
      : null;
    const defaultDev = list.find(d => d && (d.isDefault || d.is_default)) || currentDevObj;
    if (defaultDev) {
      state.audioDeviceName = defaultDev.name || defaultDev.friendlyName || state.audioDeviceName;
      if (defaultDev.currentSampleRate || defaultDev.sampleRate) {
        state.audioDeviceSampleRate = defaultDev.currentSampleRate || defaultDev.sampleRate;
      }
      const isNet = Boolean(
        defaultDev.type === 'dlna' ||
        defaultDev.isNetwork ||
        defaultDev.is_network ||
        defaultDev.protocol === 'dlna' ||
        defaultDev.protocol === 'bluos' ||
        (typeof defaultDev.uid === 'string' && defaultDev.uid.startsWith('dlna:'))
      );
      state.isDlnaActive = isNet;
    }
    renderAudioDevicesList();
    if (state.lastDspSettings && typeof state.lastDspSettings === 'object') {
      state.lastDspSettings = Object.assign({}, state.lastDspSettings, { is_dlna_active: state.isDlnaActive });
      updateDSPSettingsUI(state.lastDspSettings);
    } else {
      applyDeviceCapabilityPermissionsUI();
      updateSignalPathDetails();
    }
    if (typeof renderVolumeUI === 'function') {
      renderVolumeUI();
    }
  }

  function renderAudioDevicesList() {
    if (!dom.audioDevicesList) return;
    dom.audioDevicesList.innerHTML = '';

    if (!state.audioDevices || state.audioDevices.length === 0) {
      dom.audioDevicesList.innerHTML = '<div class="empty-state">Нет доступных аудиоустройств</div>';
      return;
    }

    state.audioDevices.forEach(dev => {
      const isDLNA = (dev.type === 'dlna');
      const item = document.createElement('div');
      item.className = `audio-device-item ${isDLNA ? 'dlna-device' : ''} ${dev.isDefault ? 'active' : ''}`;
      item.setAttribute('data-device-id', String(dev.id));
      if (dev.uid) item.setAttribute('data-device-uid', String(dev.uid));

      let iconSvg = '';
      let subtitle = '';

      if (isDLNA) {
        iconSvg = `
          <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2">
            <rect x="2" y="2" width="20" height="8" rx="2" ry="2"/>
            <rect x="2" y="14" width="20" height="8" rx="2" ry="2"/>
            <line x1="6" y1="6" x2="6.01" y2="6"/>
            <line x1="6" y1="18" x2="6.01" y2="18"/>
          </svg>
        `;
        subtitle = `Сетевой стример • До 192 кГц Hi-Res • ${escapeHtml(dev.manufacturer || 'DLNA')}`;
      } else {
        iconSvg = `
          <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M11 5L6 9H2v6h4l5 4V5z"/>
            <path d="M19.07 4.93a10 10 0 0 1 0 14.14M15.54 8.46a5 5 0 0 1 0 7.07"/>
          </svg>
        `;
        const rateText = dev.currentSampleRate ? `${(dev.currentSampleRate / 1000).toFixed(1)} кГц` : '44.1 кГц';
        const ratesCount = Array.isArray(dev.availableSampleRates) ? dev.availableSampleRates.length : 0;
        subtitle = `${rateText} • Bit-Perfect ${ratesCount > 0 ? `(${ratesCount} частот)` : ''}`;
      }

      item.innerHTML = `
        <div class="audio-device-icon">
          ${iconSvg}
        </div>
        <div class="audio-device-info">
          <div class="audio-device-name">
            <span class="audio-device-title">${escapeHtml(dev.name || (isDLNA ? 'DLNA Стример' : 'Аудиовыход'))}</span>
            ${isDLNA ? '<span class="badge-dlna">DLNA</span>' : ''}
          </div>
          <div class="audio-device-meta">${subtitle}</div>
        </div>
        ${dev.isDefault ? '<span class="audio-device-badge active">Активен</span>' : '<span class="audio-device-badge">Выбрать</span>'}
      `;

      item.addEventListener('click', () => {
        if (state.allowDacSelection === false) {
          showToast(IS_EN ? 'DAC selection is disabled for this device on Mac' : 'Выбор ЦАП отключён для этого устройства в настройках Mac');
          return;
        }
        triggerHaptic('medium');
        send({ action: 'set_audio_device', params: { id: dev.id, uid: dev.uid } });
        state.audioDevices.forEach(d => { d.isDefault = (d.id === dev.id); });
        state.audioDeviceName = dev.name;
        if (dev.currentSampleRate) state.audioDeviceSampleRate = dev.currentSampleRate;
        renderAudioDevicesList();
        updateSignalPathDetails();
      });

      dom.audioDevicesList.appendChild(item);
    });
  }

  // --- Apple MusicKit & User Token Handlers ---
  let musicKitInstance = null;
  let musicKitLoadedListenerBound = false;
  let musicKitEventsBound = false;
  let explicitlyLoggedOutThisSession = false;
  let lastSyncedUserTokenSent = '';
  let lastSyncedUserTokenAt = 0;

  function isStandalonePwaMode() {
    try {
      return Boolean(
        window.navigator.standalone === true ||
        (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches)
      );
    } catch (_) {
      return false;
    }
  }

  function decodeBase64Flexible(raw) {
    if (!raw || typeof raw !== 'string') return '';
    let normalized = raw.trim().replace(/-/g, '+').replace(/_/g, '/');
    const pad = normalized.length % 4;
    if (pad > 0) normalized += '='.repeat(4 - pad);
    return atob(normalized);
  }

  function readPendingSessionUserToken() {
    try {
      const s = sessionStorage.getItem('amr_pending_apple_user_token');
      return (s && s.trim().length > 20) ? s.trim() : '';
    } catch (_) {
      return '';
    }
  }

  function writePendingSessionUserToken(token) {
    try {
      if (token && token.trim().length > 20) {
        sessionStorage.setItem('amr_pending_apple_user_token', token.trim());
      } else {
        sessionStorage.removeItem('amr_pending_apple_user_token');
      }
    } catch (_) {}
  }

  function extractAppleUserTokenFromUrlHash() {
    try {
      const rawHash = window.location.hash ? window.location.hash.slice(1).trim() : '';
      if (!rawHash || rawHash.length < 24) return '';
      const unescaped = decodeURIComponent(rawHash);
      const decodedJson = decodeBase64Flexible(unescaped);
      if (!decodedJson || !decodedJson.startsWith('{')) return '';
      const parsed = JSON.parse(decodedJson);
      const candidate = parsed && typeof parsed.musicUserToken === 'string'
        ? parsed.musicUserToken.trim()
        : '';
      if (candidate.length > 20) {
        const cleanUrl = window.location.pathname + window.location.search;
        window.history.replaceState(null, '', cleanUrl || '/');
        explicitlyLoggedOutThisSession = false;
        queueAppleUserTokenForServerSync(candidate);
        return candidate;
      }
    } catch (_) {}
    return '';
  }

  function readExistingMusicKitTokenFromBrowser() {
    if (explicitlyLoggedOutThisSession) return '';
    try {
      if (musicKitInstance && typeof musicKitInstance.musicUserToken === 'string') {
        const instTok = musicKitInstance.musicUserToken.trim();
        if (instTok.length > 20) return instTok;
      }
    } catch (_) {}
    try {
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        if (!key) continue;
        if ((key.startsWith('music.') && key.endsWith('.u')) || key === 'music.ampwebplay.user-token') {
          const val = (localStorage.getItem(key) || '').trim();
          if (val.length > 20) return val;
        }
      }
    } catch (_) {}
    return '';
  }

  function queueAppleUserTokenForServerSync(rawToken) {
    const trimmed = String(rawToken || '').trim();
    if (trimmed.length <= 20) return false;
    explicitlyLoggedOutThisSession = false;
    state.pendingAppleUserToken = trimmed;
    writePendingSessionUserToken(trimmed);
    if (dom.modalAppleAuth) {
      dom.modalAppleAuth.classList.add('hidden');
      dom.modalAppleAuth.setAttribute('aria-hidden', 'true');
    }
    return flushPendingAppleUserToken();
  }

  function flushPendingAppleUserToken() {
    const candidate = (state.pendingAppleUserToken || readPendingSessionUserToken() || '').trim();
    if (candidate.length <= 20) return false;
    state.pendingAppleUserToken = candidate;
    const now = Date.now();
    if (lastSyncedUserTokenSent === candidate && (now - lastSyncedUserTokenAt) < 1200 && state.connected) {
      return true;
    }
    lastSyncedUserTokenSent = candidate;
    lastSyncedUserTokenAt = now;
    return send({ action: 'set_user_token', params: { user_token: candidate } });
  }

  function bindMusicKitInstanceEvents(instance) {
    if (!instance || musicKitEventsBound || typeof instance.addEventListener !== 'function') return;
    musicKitEventsBound = true;
    const onAuthChange = () => {
      if (explicitlyLoggedOutThisSession) return;
      const tok = typeof instance.musicUserToken === 'string' ? instance.musicUserToken.trim() : '';
      if (tok.length > 20 && !state.hasUserToken) {
        queueAppleUserTokenForServerSync(tok);
      }
    };
    try {
      instance.addEventListener('userTokenDidChange', onAuthChange);
      instance.addEventListener('authorizationStatusDidChange', onAuthChange);
    } catch (_) {}
  }

  // Hydrate any redirect hash token or unconfirmed session token immediately at boot
  state.pendingAppleUserToken = readPendingSessionUserToken();
  extractAppleUserTokenFromUrlHash();
  window.addEventListener('hashchange', () => { extractAppleUserTokenFromUrlHash(); });
  window.addEventListener('pageshow', () => { extractAppleUserTokenFromUrlHash(); });

  function refreshAppleAuthStateAfterExternalSheet() {
    extractAppleUserTokenFromUrlHash();
    if (!state.deviceAuthorized || !state.connected) return;
    if (state.pendingAppleUserToken) {
      flushPendingAppleUserToken();
      return;
    }
    const existingTok = readExistingMusicKitTokenFromBrowser();
    if (existingTok && !state.hasUserToken) {
      queueAppleUserTokenForServerSync(existingTok);
      return;
    }
    if (!state.hasUserToken && dom.modalAppleAuth && !dom.modalAppleAuth.classList.contains('hidden')) {
      send({ action: 'get_user_token_status' });
      send({ action: 'get_account_status', params: { refresh: true } });
    }
  }

  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) refreshAppleAuthStateAfterExternalSheet();
  });
  window.addEventListener('focus', () => {
    refreshAppleAuthStateAfterExternalSheet();
  });

  function setupMusicKitFromState(forceConfigure = false) {
    const devToken = state.developerToken;
    if (!devToken || !window.MusicKit) return;
    if (!forceConfigure && musicKitInstance && (state.hasUserToken || state.isAccountSynced)) {
      return;
    }
    try {
      if (!musicKitInstance) {
        window.MusicKit.configure({
          developerToken: devToken,
          app: {
            name: 'Apple Music Remote',
            build: '3.0.0'
          }
        });
        musicKitInstance = window.MusicKit.getInstance();
        bindMusicKitInstanceEvents(musicKitInstance);
        if (state.lockScreenControls && state.deviceAuthorized) {
          setupMediaSession(true);
          updateMediaSession();
        }
      }
      if (!state.hasUserToken && !explicitlyLoggedOutThisSession) {
        const existingTok = readExistingMusicKitTokenFromBrowser();
        if (existingTok) {
          queueAppleUserTokenForServerSync(existingTok);
        }
      }
    } catch (e) {
      console.warn('MusicKit configuration error:', e);
    }
  }

  function initMusicKit(devToken) {
    if (!devToken) return;
    state.developerToken = devToken;
    if (window.MusicKit) {
      setupMusicKitFromState(false);
    } else if (!musicKitLoadedListenerBound) {
      musicKitLoadedListenerBound = true;
      document.addEventListener('musickitloaded', () => setupMusicKitFromState(false), { once: true });
    }
  }

  function updateUserTokenStatus(data) {
    if (!state.deviceAuthorized || (data && data.status === 'error')) {
      if (dom.modalAppleAuth) {
        dom.modalAppleAuth.classList.add('hidden');
        dom.modalAppleAuth.setAttribute('aria-hidden', 'true');
      }
      return;
    }
    const wasSignedIn = Boolean(state.hasUserToken);
    const hasToken = Boolean(data && (data.has_user_token !== undefined ? data.has_user_token : data.hasUserToken));
    state.hasUserToken = hasToken;
    state.userTokenStatusChecked = true;
    if (data && data.storefront) {
      state.userStorefront = String(data.storefront).trim().toLowerCase();
    }
    if (data && data.locale) {
      state.userLocale = String(data.locale).trim();
    }

    if (hasToken || state.isAccountSynced) {
      if (hasToken) {
        state.pendingAppleUserToken = '';
        writePendingSessionUserToken('');
      }
      if (dom.modalAppleAuth) {
        dom.modalAppleAuth.classList.add('hidden');
        dom.modalAppleAuth.setAttribute('aria-hidden', 'true');
      }

      const activeCountry = getActiveStorefront();
      if (activeCountry && state.trends.country !== activeCountry) {
        state.trends.country = activeCountry;
        loadTrends(activeCountry);
      }
      if (hasToken && !wasSignedIn && state.connected) {
        send({ action: 'get_account_status', params: { refresh: true } });
        send({ action: 'get_personal_mixes' });
        send({ action: 'get_playlists' });
        send({ action: 'get_library_albums' });
      }
    } else {
      setupMusicKitFromState(true);
      const pendingOrBrowserToken = !explicitlyLoggedOutThisSession
        ? (state.pendingAppleUserToken || readPendingSessionUserToken() || readExistingMusicKitTokenFromBrowser())
        : '';
      if (pendingOrBrowserToken) {
        queueAppleUserTokenForServerSync(pendingOrBrowserToken);
        return;
      }
      if (isStandalonePwaMode() && !state.appleAuthRedirectInviteToken) {
        send({ action: 'prepare_apple_auth_redirect' });
      }
      if (dom.modalAppleAuth && !state.isAccountSynced) {
        dom.modalAppleAuth.classList.remove('hidden');
        dom.modalAppleAuth.setAttribute('aria-hidden', 'false');
      }
    }
  }

  function getActiveStorefront() {
    const fromHealth = state.accountHealth && (
      state.accountHealth.web_storefront ||
      state.accountHealth.storefront ||
      state.accountHealth.mac_country_code
    );
    const raw = state.userStorefront || fromHealth || (state.trends && state.trends.country) || '';
    return String(raw).trim().toLowerCase();
  }

  function updateAccountHealth(data) {
    if (!data) return;
    state.accountHealth = data;
    const isSynced = data.status === 'synchronized' || data.is_accounts_matched === true;
    state.isAccountSynced = isSynced;
    const detectedSf = String(data.web_storefront || data.storefront || data.mac_country_code || state.userStorefront || '').trim().toLowerCase();
    if (detectedSf && state.userStorefront !== detectedSf) {
      state.userStorefront = detectedSf;
      if (state.trends.country !== detectedSf) {
        state.trends.country = detectedSf;
        loadTrends(detectedSf);
      }
    }
    const email = data.account_email || data.mac_apple_id || data.macos_account || 'Apple Music';
    const storefront = (detectedSf || '—').toUpperCase();
    const hasSub = data.is_subscription_active !== false && data.has_active_subscription !== false;
    const details = data.details || (isSynced ? `Apple Music: подписка активна • Регион ${storefront} • Медиатека синхронизирована` : (data.message || 'Требуется вход'));

    if (dom.homeAccountCard) {
      dom.homeAccountCard.classList.remove('hidden');
    }
    if (dom.accountCardEmail) {
      dom.accountCardEmail.textContent = email;
    }
    if (dom.accountCardBadge) {
      dom.accountCardBadge.textContent = isSynced ? 'СИНХРОНИЗИРОВАНО' : 'ТРЕБУЕТСЯ ВХОД';
      dom.accountCardBadge.className = isSynced ? 'account-sync-badge' : 'account-sync-badge error';
    }
    if (dom.accountStatusDot) {
      dom.accountStatusDot.className = isSynced ? 'account-status-dot synced' : 'account-status-dot error';
    }
    if (dom.accountCardSubtext) {
      dom.accountCardSubtext.textContent = details;
    }

    // Modal details
    if (dom.diagValAccount) dom.diagValAccount.textContent = email;
    if (dom.diagValStatus) {
      dom.diagValStatus.textContent = isSynced ? 'Синхронизировано с Mac' : 'Не синхронизировано';
      dom.diagValStatus.className = isSynced ? 'diag-value green' : 'diag-value red';
    }
    if (dom.diagValStorefront) dom.diagValStorefront.textContent = storefront;
    if (dom.diagValSub) {
      dom.diagValSub.textContent = hasSub ? 'Активна' : 'Не активна';
      dom.diagValSub.className = hasSub ? 'diag-value green' : 'diag-value red';
    }
    if (dom.diagValDac) {
      dom.diagValDac.textContent = state.audioQuality || 'Bit-Perfect Lossless (100% Volume Lock)';
    }

    // If synchronized on Mac, dismiss any blocking modal
    if (isSynced && dom.modalAppleAuth) {
      dom.modalAppleAuth.classList.add('hidden');
      dom.modalAppleAuth.setAttribute('aria-hidden', 'true');
    }
  }

  async function handleAppleIdLogin() {
    triggerHaptic('medium');
    if (dom.authModalStatus) {
      dom.authModalStatus.classList.remove('hidden');
      dom.authModalStatus.innerHTML = '<div class="spinner-sm"></div><span>Инициализация MusicKit...</span>';
    }
    if (dom.btnAuthModalLogin) {
      dom.btnAuthModalLogin.disabled = true;
    }

    if (!window.MusicKit) {
      if (dom.authModalStatus) dom.authModalStatus.innerHTML = '<span>Загрузка MusicKit.js... Повторите через 2 секунды</span>';
      setTimeout(() => {
        if (dom.btnAuthModalLogin) dom.btnAuthModalLogin.disabled = false;
        if (dom.authModalStatus) dom.authModalStatus.classList.add('hidden');
      }, 2500);
      return;
    }

    if (!musicKitInstance && state.developerToken) {
      setupMusicKitFromState(true);
    }

    if (!musicKitInstance) {
      send({ action: 'get_developer_token' });
      if (dom.authModalStatus) dom.authModalStatus.innerHTML = '<div class="spinner-sm"></div><span>Получение ключа разработчика...</span>';
      setTimeout(() => {
        if (dom.btnAuthModalLogin) dom.btnAuthModalLogin.disabled = false;
        if (state.developerToken && !musicKitInstance) {
          setupMusicKitFromState(true);
        }
      }, 1500);
      return;
    }

    try {
      explicitlyLoggedOutThisSession = false;
      if (dom.authModalStatus) dom.authModalStatus.innerHTML = '<div class="spinner-sm"></div><span>Ожидание авторизации Apple ID...</span>';

      // In iOS Home Screen Standalone PWA, `window.open('https://authorize.music.apple.com/...')`
      // opens an isolated SFSafariViewController sheet where `window.opener` is null and Apple
      // falls back to redirecting `referrer` + `#<base64UserToken>`. Temporarily attach a 5-min
      // invite token synchronously before `authorize()` so the callback session auto-authorizes
      // on Mac and broadcasts `user_token_status` back to this PWA!
      const prevRelativeUrl = window.location.pathname + window.location.search + window.location.hash;
      let restoreUrlTimer = null;
      if (isStandalonePwaMode() && state.appleAuthRedirectInviteToken) {
        try {
          const u = new URL(window.location.href);
          u.searchParams.set('invite', state.appleAuthRedirectInviteToken);
          window.history.replaceState(null, '', u.pathname + u.search);
          restoreUrlTimer = setTimeout(() => {
            try { window.history.replaceState(null, '', prevRelativeUrl || '/'); } catch (_) {}
          }, 250);
        } catch (_) {}
      }

      const authPromise = musicKitInstance.authorize();
      const uToken = await authPromise;
      if (restoreUrlTimer) clearTimeout(restoreUrlTimer);
      const resolvedToken = (typeof uToken === 'string' && uToken.trim().length > 20)
        ? uToken.trim()
        : readExistingMusicKitTokenFromBrowser();
      if (resolvedToken) {
        queueAppleUserTokenForServerSync(resolvedToken);
        updateUserTokenStatus({ has_user_token: true });
      }
    } catch (err) {
      console.error('Apple Music authorization error:', err);
      const fallbackToken = extractAppleUserTokenFromUrlHash() || readExistingMusicKitTokenFromBrowser();
      if (fallbackToken) {
        queueAppleUserTokenForServerSync(fallbackToken);
        updateUserTokenStatus({ has_user_token: true });
      }
    } finally {
      if (dom.btnAuthModalLogin) dom.btnAuthModalLogin.disabled = false;
      if (dom.authModalStatus) dom.authModalStatus.classList.add('hidden');
    }
  }

  async function handleAppleIdLogout() {
    triggerHaptic('medium');
    explicitlyLoggedOutThisSession = true;
    state.pendingAppleUserToken = '';
    writePendingSessionUserToken('');
    if (musicKitInstance) {
      try { await musicKitInstance.unauthorize(); } catch (e) {}
    }
    send({ action: 'set_user_token', params: { user_token: '' } });
    updateUserTokenStatus({ has_user_token: false });
  }

  if (dom.btnAuthModalLogin) {
    dom.btnAuthModalLogin.addEventListener('click', handleAppleIdLogin);
  }

  if (dom.btnHeaderLogout) {
    dom.btnHeaderLogout.addEventListener('click', handleAppleIdLogout);
  }

  // Account Diagnostic Modal Listeners
  if (dom.btnAccountDiag) {
    dom.btnAccountDiag.addEventListener('click', () => {
      triggerHaptic('light');
      if (dom.modalAccountDiag) {
        dom.modalAccountDiag.classList.remove('hidden');
        dom.modalAccountDiag.setAttribute('aria-hidden', 'false');
      }
    });
  }
  if (dom.btnCloseAccountDiag) {
    dom.btnCloseAccountDiag.addEventListener('click', () => {
      triggerHaptic('light');
      if (dom.modalAccountDiag) {
        blurFocusedInContainer(dom.modalAccountDiag);
        dom.modalAccountDiag.classList.add('hidden');
        dom.modalAccountDiag.setAttribute('aria-hidden', 'true');
      }
    });
  }
  if (dom.btnDoneAccountDiag) {
    dom.btnDoneAccountDiag.addEventListener('click', () => {
      triggerHaptic('light');
      if (dom.modalAccountDiag) {
        blurFocusedInContainer(dom.modalAccountDiag);
        dom.modalAccountDiag.classList.add('hidden');
        dom.modalAccountDiag.setAttribute('aria-hidden', 'true');
      }
    });
  }
  if (dom.btnRefreshAccountDiag) {
    dom.btnRefreshAccountDiag.addEventListener('click', () => {
      triggerHaptic('light');
      if (dom.diagValStatus) {
        dom.diagValStatus.textContent = 'Проверка...';
      }
      send({ action: 'get_account_status', params: { refresh: true } });
    });
  }

  // --- In-App Confirmation Modal & Track Actions (•••) Modal ---
  let pendingDeleteConfirmCallback = null;

  function closeConfirmDeleteModal() {
    pendingDeleteConfirmCallback = null;
    if (dom.confirmDeleteModal) {
      blurFocusedInContainer(dom.confirmDeleteModal);
      dom.confirmDeleteModal.classList.add('hidden');
      dom.confirmDeleteModal.setAttribute('aria-hidden', 'true');
    }
  }

  function confirmLibraryDeleteModal({
    title,
    message,
    confirmLabel = 'Удалить',
    onConfirm
  }) {
    if (!dom.confirmDeleteModal) {
      if (typeof onConfirm === 'function') onConfirm();
      return;
    }
    triggerHaptic('light');
    pendingDeleteConfirmCallback = typeof onConfirm === 'function' ? onConfirm : null;

    if (dom.confirmDeleteTitle) {
      dom.confirmDeleteTitle.textContent = translateTextToEn(title || 'Удалить из медиатеки?');
    }
    if (dom.confirmDeleteMessage) {
      dom.confirmDeleteMessage.textContent = message || translateTextToEn('Элемент будет удалён из вашей медиатеки Apple Music.');
    }
    if (dom.btnConfirmDeleteOk) {
      dom.btnConfirmDeleteOk.textContent = translateTextToEn(confirmLabel || 'Удалить');
    }
    dom.confirmDeleteModal.classList.remove('hidden');
    dom.confirmDeleteModal.setAttribute('aria-hidden', 'false');
  }

  if (dom.btnConfirmDeleteCancel) {
    dom.btnConfirmDeleteCancel.addEventListener('click', () => {
      triggerHaptic('light');
      closeConfirmDeleteModal();
    });
  }
  if (dom.btnConfirmDeleteOk) {
    dom.btnConfirmDeleteOk.addEventListener('click', () => {
      triggerHaptic('medium');
      const fn = pendingDeleteConfirmCallback;
      closeConfirmDeleteModal();
      if (fn) fn();
    });
  }
  if (dom.confirmDeleteModal) {
    dom.confirmDeleteModal.addEventListener('click', (e) => {
      if (e.target === dom.confirmDeleteModal) {
        closeConfirmDeleteModal();
      }
    });
  }

  function getActiveActionTrack() {
    return state.actionTargetTrack || state.track || null;
  }

  function closeStationPickerModal() {
    state.actionTargetTrack = null;
    if (dom.stationPickerModal) {
      blurFocusedInContainer(dom.stationPickerModal);
      dom.stationPickerModal.classList.add('hidden');
      dom.stationPickerModal.setAttribute('aria-hidden', 'true');
    }
  }

  function resolveCurrentBrowseOrigin() {
    if (dom.libraryArtistDetailPane && !dom.libraryArtistDetailPane.classList.contains('hidden')) {
      return 'library-artist-detail';
    }
    if (dom.playlistDetailPane && !dom.playlistDetailPane.classList.contains('hidden')) {
      return state.detailReturnOrigin || 'library';
    }
    if (isDesktopLayout()) {
      const dt = state.desktopActiveTab || 'home';
      if (dt === 'search') return 'search';
      if (dt === 'playlists') return 'playlists';
      if (dt === 'home' || dt === 'trends') {
        return (dom.sectionGridView && dom.sectionGridView.classList.contains('active')) ? 'home-grid' : 'home';
      }
      if (dt === 'library') return `library-${state.libraryTab || 'recent'}`;
      return 'library';
    }
    const mv = state.activeView || 'view-now-playing';
    if (mv === 'view-now-playing') return 'player';
    if (mv === 'view-search') return 'search';
    if (mv === 'view-playlists') return 'playlists';
    if (mv === 'view-home' || mv === 'view-trends') {
      return (dom.sectionGridView && dom.sectionGridView.classList.contains('active')) ? 'home-grid' : 'home';
    }
    if (mv === 'view-library') return `library-${state.libraryTab || 'recent'}`;
    return 'library';
  }

// === MODULE: 12-track-actions-volume-and-queue.js ===
  function openTrackAlbumForTarget(targetTrack, explicitOrigin = '') {
    const t = targetTrack || state.track;
    const albumName = t && (t.album || t.collectionName) ? String(t.album || t.collectionName).trim() : '';
    if (!albumName) return;
    triggerHaptic('light');
    if (typeof bookletState !== 'undefined' && bookletState.isOpen) {
      closeBookletViewer();
    }
    const art = getArtworkSrc(t);
    const origin = explicitOrigin || resolveCurrentBrowseOrigin();
    openAlbumDetail({
      id: t.album_id || t.collectionId || '',
      name: albumName,
      artist: (t && (t.artist || t.artistName)) ? (t.artist || t.artistName) : '',
      artwork: art,
      url: ''
    }, origin, { source: 'catalog' });
  }

  function openCurrentTrackAlbum() {
    openTrackAlbumForTarget(state.track, isDesktopLayout() ? resolveCurrentBrowseOrigin() : 'player');
  }

  if (dom.btnGoToAlbum) {
    dom.btnGoToAlbum.addEventListener('click', () => {
      const target = getActiveActionTrack();
      const origin = state.actionTargetTrack ? resolveCurrentBrowseOrigin() : (isDesktopLayout() ? resolveCurrentBrowseOrigin() : 'player');
      closeStationPickerModal();
      openTrackAlbumForTarget(target, origin);
    });
  }

  if (dom.playerAlbum) {
    dom.playerAlbum.addEventListener('click', openCurrentTrackAlbum);
  }

  function triggerAiMixFromTrack(targetTrack) {
    triggerHaptic('medium');
    const t = targetTrack || state.track;
    closeStationPickerModal();
    const trackName = (t && (t.name || t.trackName)) ? String(t.name || t.trackName).trim() : '';
    const artistName = (t && (t.artist || t.artistName)) ? String(t.artist || t.artistName).trim() : '';
    const albumName = (t && (t.album || t.collectionName)) ? String(t.album || t.collectionName).trim() : '';
    if (!trackName) {
      showToast(translateTextToEn('Сначала запустите трек для ИИ-подбора по вайбу'));
      return;
    }
    const sbAiVibeBtn = document.getElementById('standby-btn-ai-track-vibe');
    [dom.btnAiTrackVibe, sbAiVibeBtn].forEach((b) => {
      if (!b) return;
      b.classList.add('loading-pulse');
      setTimeout(() => b.classList.remove('loading-pulse'), 2200);
    });
    state.isAiCurating = true;
    state.pendingStandbyAiAutoPlay = true;
    state.aiCurateReqSeq = (state.aiCurateReqSeq || 0) + 1;
    state.lastAiCurateSentAt = Date.now();
    const reqId = state.aiCurateReqSeq;
    setUIBusy(true, translateTextToEn(`✨ ИИ-подбор по вайбу «${trackName}»...`));
    send({
      action: 'ai_curate_from_track',
      request_id: reqId,
      params: {
        name: trackName,
        artist: artistName,
        album: albumName,
        country: getActiveStorefront(),
        auto_play: true,
        request_id: reqId
      }
    });
  }

  function triggerAiMixFromCurrentTrack() {
    triggerAiMixFromTrack(state.track);
  }

  if (dom.btnAiTrackVibe) {
    dom.btnAiTrackVibe.addEventListener('click', () => triggerAiMixFromTrack(state.track));
  }

  if (dom.btnAiMixByTrack) {
    dom.btnAiMixByTrack.addEventListener('click', () => triggerAiMixFromTrack(getActiveActionTrack()));
  }

  if (dom.btnSonicBridgeByTrack) {
    dom.btnSonicBridgeByTrack.addEventListener('click', () => {
      triggerHaptic('light');
      const t = getActiveActionTrack();
      const trackText = (t && (t.name || t.trackName)) ? String(t.name || t.trackName).trim() : '';
      const artistText = (t && (t.artist || t.artistName)) ? String(t.artist || t.artistName).trim() : '';
      if (!trackText) {
        showToast(IS_EN ? 'Start a track first to launch Sonic Bridge' : 'Сначала запустите трек для старта Sonic Bridge');
        return;
      }
      closeStationPickerModal();
      state.sonicBridgeFrom = artistText ? `${artistText} — ${trackText}` : trackText;
      openSonicBridgeTab(true);
    });
  }

  function syncStationPickerModalUI() {
    const t = getActiveActionTrack();
    const trackText = (t && (t.name || t.trackName)) ? String(t.name || t.trackName).trim() : '';
    const artistText = (t && (t.artist || t.artistName)) ? String(t.artist || t.artistName).trim() : '';
    const albumText = (t && (t.album || t.collectionName)) ? String(t.album || t.collectionName).trim() : '';

    if (dom.stationModalTrackBanner) {
      dom.stationModalTrackBanner.classList.toggle('hidden', !trackText);
      if (trackText) {
        if (dom.stationModalTrackArt) {
          delete dom.stationModalTrackArt.dataset.fallbackApplied;
          dom.stationModalTrackArt.dataset.fallbackIcon = 'apple-touch-icon.svg';
          dom.stationModalTrackArt.src = getArtworkSrc(t);
        }
        if (dom.stationModalTrackTitle) dom.stationModalTrackTitle.textContent = trackText;
        if (dom.stationModalTrackSub) {
          dom.stationModalTrackSub.textContent = [artistText, albumText].filter(Boolean).join(' • ') || 'Apple Music';
        }
      }
    }

    const canModifyLib = state.allowLibraryModification !== false;
    const inLib = Boolean(t && trackText && isTrackInLibraryClient(t));
    if (dom.btnAddTrackLibrary) {
      dom.btnAddTrackLibrary.classList.toggle('hidden', !canModifyLib || !trackText || inLib);
    }
    if (dom.btnRemoveTrackLibrary) {
      dom.btnRemoveTrackLibrary.classList.toggle('hidden', !canModifyLib || !trackText || !inLib);
    }

    const libArtist = artistText ? findMatchingLibraryArtist(artistText) : null;
    const artistInLib = Boolean(libArtist || (inLib && artistText));
    if (dom.btnGoToLibraryArtist) {
      dom.btnGoToLibraryArtist.classList.toggle('hidden', !artistInLib);
      if (dom.stationOptLibArtistName) {
        dom.stationOptLibArtistName.textContent = artistText || '—';
      }
    }
    if (dom.btnRemoveArtistLibrary) {
      dom.btnRemoveArtistLibrary.classList.toggle('hidden', !canModifyLib || !artistInLib);
      if (dom.stationOptRemoveArtistSub) {
        const cnt = libArtist && libArtist.track_count ? Number(libArtist.track_count) : 0;
        dom.stationOptRemoveArtistSub.textContent = cnt > 0
          ? `${artistText} • ${formatTracksCount(cnt)}`
          : (artistText || '—');
      }
    }

    const btnOpenBookletModal = document.getElementById('btn-open-booklet');
    if (btnOpenBookletModal && state.actionTargetTrack) {
      const curAlb = (state.track && state.track.album) ? state.track.album.trim().toLowerCase() : '';
      if (!albumText || albumText.toLowerCase() !== curAlb) {
        btnOpenBookletModal.classList.add('hidden');
      }
    }

    if (dom.stationOptAlbumName) {
      dom.stationOptAlbumName.textContent = albumText || translateTextToEn('Не указан');
    }
    if (dom.btnGoToAlbum) {
      dom.btnGoToAlbum.disabled = !albumText;
    }
    if (dom.btnAiMixByTrack) {
      dom.btnAiMixByTrack.disabled = !trackText;
      dom.btnAiMixByTrack.classList.toggle('hidden', !state.aiCuratorEnabled);
    }
    if (dom.stationOptAiVibeSub) {
      dom.stationOptAiVibeSub.textContent = trackText
        ? `${artistText ? artistText + ' — ' : ''}${trackText}`
        : translateTextToEn('Бесконечная волна 20+ треков по атмосфере');
    }
    if (dom.btnSonicBridgeByTrack) {
      dom.btnSonicBridgeByTrack.disabled = !trackText;
      dom.btnSonicBridgeByTrack.classList.toggle('hidden', !state.aiCuratorEnabled);
    }
    if (dom.stationOptSonicBridgeSub) {
      dom.stationOptSonicBridgeSub.textContent = trackText
        ? `${artistText ? artistText + ' — ' : ''}${trackText} → ...`
        : translateTextToEn('Плавный ИИ-маршрут к другому треку или артисту');
    }
    if (dom.stationOptTrackName) {
      dom.stationOptTrackName.textContent = trackText || translateTextToEn('Не играет');
    }
    if (dom.stationOptArtistName) {
      dom.stationOptArtistName.textContent = artistText || 'Apple Music';
    }
    if (dom.btnStationByTrack) {
      dom.btnStationByTrack.disabled = !trackText;
    }
    if (dom.btnStationByArtist) {
      dom.btnStationByArtist.disabled = !artistText;
    }
  }

  function openTrackActionsModal(customTrack = null) {
    triggerHaptic('light');
    state.actionTargetTrack = customTrack || null;
    if (!state.librarySongsLoaded && state.connected && state.deviceAuthorized) {
      send({ action: 'get_library_songs' });
    }
    if (!state.libraryArtistsLoaded && state.connected && state.deviceAuthorized) {
      send({ action: 'get_library_artists' });
    }
    syncStationPickerModalUI();
    if (!customTrack) {
      syncCurrentTrackBookletAvailability();
    }
    if (dom.stationPickerModal) {
      dom.stationPickerModal.classList.remove('hidden');
      dom.stationPickerModal.setAttribute('aria-hidden', 'false');
    }
  }

  if (dom.btnCreateStation) {
    dom.btnCreateStation.addEventListener('click', () => {
      openTrackActionsModal(null);
    });
  }

  if (dom.btnAddTrackLibrary) {
    dom.btnAddTrackLibrary.addEventListener('click', () => {
      const t = getActiveActionTrack();
      if (!t || !(t.name || t.trackName)) return;
      triggerHaptic('medium');
      const tName = String(t.name || t.trackName || '').trim();
      const tArtist = String(t.artist || t.artistName || '').trim();
      const tAlbum = String(t.album || t.collectionName || '').trim();
      const tCatId = String(t.catalog_id || t.catalogId || t.id || t.trackId || '').trim();
      const tNumId = Number(t.numeric_id || t.numericId || 0);
      state.lastLibraryAddTarget = 'track';
      t.is_local = true;
      closeStationPickerModal();
      send({
        action: 'add_to_library',
        params: {
          id: tCatId,
          track_id: tNumId > 0 ? tNumId : undefined,
          name: tName,
          artist: tArtist,
          album: tAlbum,
          url: t.url || ''
        }
      });
    });
  }

  if (dom.btnRemoveTrackLibrary) {
    dom.btnRemoveTrackLibrary.addEventListener('click', () => {
      const t = getActiveActionTrack();
      closeStationPickerModal();
      if (t) {
        promptRemoveTrackFromLibrary(t);
      }
    });
  }

  if (dom.btnGoToLibraryArtist) {
    dom.btnGoToLibraryArtist.addEventListener('click', () => {
      const t = getActiveActionTrack();
      const artistName = t ? String(t.artist || t.artistName || '').trim() : '';
      closeStationPickerModal();
      if (!artistName) return;
      const libArt = findMatchingLibraryArtist(artistName) || { name: artistName };
      navigateToView('view-library', 'library', true);
      switchLibrarySubtab('artists', false);
      openLibraryArtistDetail(libArt);
    });
  }

  if (dom.btnRemoveArtistLibrary) {
    dom.btnRemoveArtistLibrary.addEventListener('click', () => {
      const t = getActiveActionTrack();
      const artistName = t ? String(t.artist || t.artistName || '').trim() : '';
      closeStationPickerModal();
      if (!artistName) return;
      const libArt = findMatchingLibraryArtist(artistName) || { name: artistName };
      promptRemoveArtistFromLibrary(libArt);
    });
  }

  if (dom.btnCloseStationModal) {
    dom.btnCloseStationModal.addEventListener('click', closeStationPickerModal);
  }

  if (dom.stationPickerModal) {
    dom.stationPickerModal.addEventListener('click', (e) => {
      if (e.target === dom.stationPickerModal) {
        closeStationPickerModal();
      }
    });
  }

  if (dom.btnStationByTrack) {
    dom.btnStationByTrack.addEventListener('click', () => {
      triggerHaptic('medium');
      const t = getActiveActionTrack();
      closeStationPickerModal();
      const trackName = t ? String(t.name || t.trackName || '').trim() : '';
      const artistName = t ? String(t.artist || t.artistName || '').trim() : '';
      if (!trackName) return;
      markWaitingForPlayback({ isStation: true, targetName: trackName });
      setUIBusy(true, `Запуск радио по треку «${trackName}»...`);
      send({
        action: 'play_station',
        params: {
          type: 'track',
          title: trackName,
          artist: artistName,
          name: `Станция «${trackName}»`
        }
      });
    });
  }

  if (dom.btnStationByArtist) {
    dom.btnStationByArtist.addEventListener('click', () => {
      triggerHaptic('medium');
      const t = getActiveActionTrack();
      closeStationPickerModal();
      const artistName = t ? String(t.artist || t.artistName || '').trim() : '';
      if (!artistName) return;
      markWaitingForPlayback({ isStation: true, targetName: artistName });
      setUIBusy(true, `Запуск радио по артисту «${artistName}»...`);
      send({
        action: 'play_station',
        params: {
          type: 'artist',
          artist: artistName,
          name: `Станция «${artistName}»`
        }
      });
    });
  }

  dom.qualityModal.addEventListener('click', (e) => {
    if (e.target === dom.qualityModal) {
      closeQualityModal();
    }
  });

  // --- Volume Control & Settings Listeners ---
  let lastVolumeSendTime = 0;
  let volumeSendTimeout = null;

  function sendThrottledVolume(val) {
    const isExtAmpMode = Boolean(state.lockVolume100 && state.ampVolumeControlEnabled);
    if (state.lockVolume100 && !isExtAmpMode) {
      return;
    }
    const maxVol = isExtAmpMode ? Math.max(1, Math.min(100, Number(state.ampMaxVolume) || 80)) : 100;
    const vol = Math.max(0, Math.min(maxVol, Math.round(Number(val) || 0)));
    state.volume = vol;
    try { localStorage.setItem('amr_last_volume', String(vol)); } catch (_) {}
    if (vol >= 5) {
      state.previousVolume = vol;
    }
    if (vol > 0 && isExtAmpMode) {
      state.ampMuted = false;
      try { localStorage.setItem('amr_amp_muted', 'false'); } catch (_) {}
    }

    const pct = Math.max(0, Math.min(100, (vol / maxVol) * 100));
    const brand = state.ampBrandName || 'AMP';
    const labelStr = isExtAmpMode ? `${brand} • ${vol}%` : `${vol}%`;

    if (dom.volumeTrackFill) dom.volumeTrackFill.style.width = `${pct}%`;
    if (dom.volumeThumb) dom.volumeThumb.style.left = `${pct}%`;
    if (dom.volumeLevelText) dom.volumeLevelText.textContent = labelStr;
    updateStandbyLoupePosition(vol, pct, vol === 0);
    if (dom.standbyVolumeText) dom.standbyVolumeText.textContent = labelStr;
    if (dom.standbyBtnVolumeMute) dom.standbyBtnVolumeMute.classList.toggle('muted', vol === 0);
    syncSignalPathAmpNode();
    updateVolumeIcon(Math.round(pct));
    triggerStandbyVolumePulse();

    const now = Date.now();
    const throttleMs = state.isDlnaActive ? 45 : 75;
    if (now - lastVolumeSendTime >= throttleMs) {
      lastVolumeSendTime = now;
      send({ action: 'set_volume', params: { volume: vol } });
    } else {
      if (volumeSendTimeout) clearTimeout(volumeSendTimeout);
      volumeSendTimeout = setTimeout(() => {
        lastVolumeSendTime = Date.now();
        send({ action: 'set_volume', params: { volume: vol } });
      }, throttleMs);
    }
  }

  function handleMuteToggleClick() {
    if (state.lockVolume100 && !state.ampVolumeControlEnabled) {
      return;
    }
    triggerHaptic('toggle');
    triggerStandbyVolumePulse();
    if (state.lockVolume100 && state.ampVolumeControlEnabled) {
      state.ampMuted = !state.ampMuted;
      renderVolumeUI();
      send({ action: 'toggle_amp_mute', params: { muted: state.ampMuted } });
      return;
    }
    if (state.volume > 0) {
      state.previousVolume = state.volume;
      sendThrottledVolume(0);
    } else {
      const restore = state.previousVolume > 0 ? state.previousVolume : 50;
      sendThrottledVolume(restore);
    }
  }

  if (dom.volumeInput) {
    dom.volumeInput.addEventListener('input', (e) => {
      state.isDraggingVolume = true;
      if (dom.standbyVolumeInput) dom.standbyVolumeInput.value = e.target.value;
      sendThrottledVolume(e.target.value);
    });

    const finishVolScrub = (e) => {
      state.isDraggingVolume = false;
      if (e && e.target && e.target.value !== undefined) {
        sendThrottledVolume(e.target.value);
      }
      renderVolumeUI();
      triggerHaptic('light');
    };

    dom.volumeInput.addEventListener('change', finishVolScrub);
    dom.volumeInput.addEventListener('pointerup', () => { state.isDraggingVolume = false; renderVolumeUI(); });
    dom.volumeInput.addEventListener('touchend', () => { state.isDraggingVolume = false; renderVolumeUI(); }, { passive: true });
    dom.volumeInput.addEventListener('pointercancel', () => { state.isDraggingVolume = false; renderVolumeUI(); });
    dom.volumeInput.addEventListener('touchcancel', () => { state.isDraggingVolume = false; renderVolumeUI(); }, { passive: true });
  }

  if (dom.standbyVolumeInput) {
    dom.standbyVolumeInput.addEventListener('pointerdown', () => {
      state.isDraggingVolume = true;
      showStandbyVolumeLoupe(0);
    });
    dom.standbyVolumeInput.addEventListener('touchstart', () => {
      state.isDraggingVolume = true;
      showStandbyVolumeLoupe(0);
    }, { passive: true });

    dom.standbyVolumeInput.addEventListener('input', (e) => {
      state.isDraggingVolume = true;
      showStandbyVolumeLoupe(0);
      if (dom.volumeInput) dom.volumeInput.value = e.target.value;
      sendThrottledVolume(e.target.value);
    });

    const finishStandbyVolScrub = (e) => {
      state.isDraggingVolume = false;
      if (e && e.target && e.target.value !== undefined) {
        sendThrottledVolume(e.target.value);
      }
      renderVolumeUI();
      showStandbyVolumeLoupe(750);
      triggerHaptic('light');
    };

    dom.standbyVolumeInput.addEventListener('change', finishStandbyVolScrub);
    dom.standbyVolumeInput.addEventListener('pointerup', () => {
      state.isDraggingVolume = false;
      renderVolumeUI();
      showStandbyVolumeLoupe(750);
    });
    dom.standbyVolumeInput.addEventListener('touchend', () => {
      state.isDraggingVolume = false;
      renderVolumeUI();
      showStandbyVolumeLoupe(750);
    }, { passive: true });
    dom.standbyVolumeInput.addEventListener('pointercancel', () => {
      state.isDraggingVolume = false;
      renderVolumeUI();
      showStandbyVolumeLoupe(750);
    });
    dom.standbyVolumeInput.addEventListener('touchcancel', () => {
      state.isDraggingVolume = false;
      renderVolumeUI();
      showStandbyVolumeLoupe(750);
    }, { passive: true });
  }

  if (dom.btnVolumeMute) {
    dom.btnVolumeMute.addEventListener('click', handleMuteToggleClick);
  }
  if (dom.standbyBtnVolumeMute) {
    dom.standbyBtnVolumeMute.addEventListener('click', handleMuteToggleClick);
  }

// === MODULE: 12b-queue-view.js ===
  // --- Queue View Handling (Previous, Now Playing, and Upcoming) ---
  const QUEUE_HISTORY_PREVIEW_LIMIT = 3;
  const lastQueueListKey = { upcoming: '', history: '' };
  let lastCurrentQueueTrackKey = '';

  function updateQueue(data) {
    if (!data) return;

    const upcoming = data.upcoming_tracks || data.upcomingTracks || [];
    const history = data.history_tracks || data.historyTracks || [];
    const currentIdx = data.current_index || data.currentIndex || 0;
    const total = data.total_tracks || data.totalTracks || upcoming.length;
    const playlistName = data.playlist || state.queue.playlist || '';

    state.queue.upcoming = upcoming;
    state.queue.history = history;
    state.queue.currentIndex = currentIdx;
    state.queue.totalTracks = total;
    state.queue.playlist = playlistName;
    if (history.length <= QUEUE_HISTORY_PREVIEW_LIMIT) {
      state.queueHistoryExpanded = false;
    }

    const isGenericPl = !playlistName || playlistName === 'Музыка' || playlistName === 'Music' || playlistName === 'Apple Music' || playlistName === 'Очередь';
    const plPrefix = (!isGenericPl && playlistName !== 'Очередь AMR')
      ? `${translateTextToEn(playlistName)} · `
      : (playlistName === 'Очередь AMR' ? (IS_EN ? 'AMR Queue · ' : 'Очередь AMR · ') : '');
    if (IS_EN) {
      dom.queueSubtitle.textContent = history.length > 0
        ? `${plPrefix}${upcoming.length} up next · ${history.length} previous`
        : `${plPrefix}${upcoming.length} tracks in queue`;
    } else {
      dom.queueSubtitle.textContent = history.length > 0
        ? `${plPrefix}${upcoming.length} далее · ${history.length} ранее`
        : `${plPrefix}${upcoming.length} треков в очереди`;
    }

    renderQueueHistorySection(history);
    renderCurrentQueueTrack(dom.queueCurrentTrack);
    renderQueueList(dom.queueUpcomingList, upcoming, 'upcoming');
    syncStandbyQueueBadge();
    if (isStandbyQueueModalOpen()) {
      renderStandbyQueueModal();
    }
  }

  function renderQueueHistorySection(history) {
    if (!dom.queueHistoryGroup || !dom.queueHistoryList) return;
    if (!Array.isArray(history) || history.length === 0) {
      dom.queueHistoryGroup.style.display = 'none';
      dom.queueHistoryList.innerHTML = '';
      lastQueueListKey.history = '';
      return;
    }
    dom.queueHistoryGroup.style.display = 'block';

    const hasOverflow = history.length > QUEUE_HISTORY_PREVIEW_LIMIT;
    const expanded = Boolean(state.queueHistoryExpanded) && hasOverflow;
    if (dom.btnToggleQueueHistory) {
      dom.btnToggleQueueHistory.classList.toggle('hidden', !hasOverflow);
      if (hasOverflow) {
        dom.btnToggleQueueHistory.textContent = expanded
          ? (IS_EN ? 'Show Less' : 'Свернуть')
          : (IS_EN ? `Show All (${history.length})` : `Показать все (${history.length})`);
      }
    }

    // Backend `history[0]` is the most recently played track (`curIdx - 1`);
    // display chronologically top-to-bottom so the last played track sits directly above NOW PLAYING.
    const slice = expanded ? history : history.slice(0, QUEUE_HISTORY_PREVIEW_LIMIT);
    const chronological = slice.map((t, idx) => ({ track: t, historyIdx: idx })).reverse();
    const key = `${expanded ? '1' : '0'}|${chronological.map(({ track: t, historyIdx }) => `${historyIdx}:${t.id || t.numeric_id || t.numericId || ''}:${t.name}:${t.artist}:${t.artwork || t.artwork_url || ''}`).join('|')}`;
    if (key === lastQueueListKey.history) {
      return;
    }
    lastQueueListKey.history = key;

    dom.queueHistoryList.innerHTML = '';
    chronological.forEach(({ track: t, historyIdx }) => {
      const row = document.createElement('div');
      row.className = 'track-row history-track-row';
      const artSrc = getArtworkSrc(t);
      const dur = formatTime(t.duration || 0);
      row.innerHTML = `
        <img class="track-thumb" src="${escapeHtml(artSrc)}" alt="" loading="lazy" data-fallback-icon="apple-touch-icon.svg">
        <div class="track-details">
          <span class="track-row-title">${escapeHtml(t.name || (IS_EN ? 'Untitled' : 'Без названия'))}</span>
          <span class="track-row-artist">${escapeHtml(t.artist || (IS_EN ? 'Unknown Artist' : 'Неизвестный исполнитель'))}</span>
        </div>
        <span class="track-row-dur">${dur}</span>
      `;
      row.addEventListener('click', () => {
        optimisticPlay();
        markWaitingForPlayback({ targetName: t.name || '', expectedTrackName: t.name || '' });
        setUIBusy(true, IS_EN ? 'Switching track...' : 'Переход к треку...');
        send({ action: 'play_history_index', index: historyIdx, params: { index: historyIdx } });
      });
      dom.queueHistoryList.appendChild(row);
    });
  }

  if (dom.btnToggleQueueHistory) {
    dom.btnToggleQueueHistory.addEventListener('click', () => {
      triggerHaptic('light');
      state.queueHistoryExpanded = !state.queueHistoryExpanded;
      lastQueueListKey.history = '';
      renderQueueHistorySection(state.queue.history || []);
    });
  }

  function renderCurrentQueueTrack(container) {
    if (!container) return;
    const cur = state.track;
    if (!cur || !cur.name) {
      if (dom.queueCurrentGroup) dom.queueCurrentGroup.style.display = 'none';
      container.innerHTML = '';
      lastCurrentQueueTrackKey = '';
      return;
    }
    if (dom.queueCurrentGroup) dom.queueCurrentGroup.style.display = 'block';

    const artSrc = getArtworkSrc(cur);
    const dur = formatTime(cur.duration || state.duration || 0);
    const key = `${cur.id || ''}|${cur.name}|${cur.artist}|${artSrc}`;

    if (key === lastCurrentQueueTrackKey) {
      const durEl = container.querySelector('.track-row-dur');
      if (durEl && durEl.textContent !== dur) durEl.textContent = dur;
      return;
    }
    lastCurrentQueueTrackKey = key;

    container.innerHTML = `
      <div class="track-row now-playing-row">
        <img class="track-thumb" src="${escapeHtml(artSrc)}" alt="" loading="lazy" data-fallback-icon="apple-touch-icon.svg">
        <div class="track-details">
          <span class="track-row-title">${escapeHtml(cur.name || (IS_EN ? 'Untitled' : 'Без названия'))}</span>
          <span class="track-row-artist">${escapeHtml(cur.artist || (IS_EN ? 'Unknown Artist' : 'Неизвестный исполнитель'))}</span>
        </div>
        <span class="track-row-dur">${dur}</span>
      </div>
    `;
  }

  function renderQueueList(container, tracks, type) {
    if (!container) return;
    if (!tracks || tracks.length === 0) {
      container.innerHTML = `<div class="empty-state">${type === 'upcoming' ? (IS_EN ? 'No upcoming tracks' : 'Нет предстоящих треков') : (IS_EN ? 'No previous tracks' : 'История пуста')}</div>`;
      lastQueueListKey[type] = '';
      return;
    }

    const currentKey = tracks.map(t => `${t.id || t.numeric_id || t.numericId || ''}:${t.name}:${t.artist}:${t.artwork || t.artwork_url || ''}`).join('|');
    if (currentKey === lastQueueListKey[type]) {
      return;
    }
    lastQueueListKey[type] = currentKey;

    container.innerHTML = '';
    tracks.forEach((t, idx) => {
      const row = document.createElement('div');
      row.className = 'track-row';
      const artSrc = getArtworkSrc(t);
      const dur = formatTime(t.duration || 0);

      row.innerHTML = `
        <img class="track-thumb" src="${escapeHtml(artSrc)}" alt="" loading="lazy" data-fallback-icon="apple-touch-icon.svg">
        <div class="track-details">
          <span class="track-row-title">${escapeHtml(t.name || (IS_EN ? 'Untitled' : 'Без названия'))}</span>
          <span class="track-row-artist">${escapeHtml(t.artist || (IS_EN ? 'Unknown Artist' : 'Неизвестный исполнитель'))}</span>
        </div>
        <span class="track-row-dur">${dur}</span>
      `;

      row.addEventListener('click', () => {
        optimisticPlay();
        markWaitingForPlayback({ targetName: t.name || '', expectedTrackName: t.name || '' });
        setUIBusy(true, IS_EN ? 'Switching track...' : 'Переход к треку...');
        if (type === 'upcoming') {
          send({ action: 'queue_play_index', params: { index: idx } });
        } else {
          send({ action: 'play_history_index', index: idx, params: { index: idx } });
        }
      });

      container.appendChild(row);
    });
  }

  dom.btnClearQueue.addEventListener('click', () => {
    send({ action: 'queue_clear' });
  });

  if (dom.btnSaveQueuePlaylist) {
    dom.btnSaveQueuePlaylist.addEventListener('click', () => {
      const prevChrono = Array.isArray(state.queue.history) ? [...state.queue.history].reverse() : [];
      const cur = (state.track && state.track.name) ? [state.track] : [];
      const upcoming = Array.isArray(state.queue.upcoming) ? state.queue.upcoming : [];
      const allQueueTracks = [...prevChrono, ...cur, ...upcoming];
      if (allQueueTracks.length === 0) {
        showToast(IS_EN ? 'Queue is empty' : 'Очередь пуста');
        return;
      }
      triggerHaptic('medium');
      const GENERIC_QUEUE_NAMES = new Set([
        'очередь amr',
        'очередь',
        'amr queue',
        'результаты поиска',
        'search results'
      ]);
      const rawQueueName = String((state.queue && state.queue.playlist) || '').trim();
      const isGenericQueue = !rawQueueName || GENERIC_QUEUE_NAMES.has(rawQueueName.toLowerCase());
      let plName = '';
      if (!isGenericQueue) {
        plName = rawQueueName;
      } else if (state.activeAiCuratedTitle) {
        plName = state.activeAiCuratedTitle;
      } else if (state.searchQuery && String(state.searchQuery).trim()) {
        const cleanQ = String(state.searchQuery).trim();
        plName = IS_EN ? `Search: ${cleanQ}` : `Поиск: ${cleanQ}`;
      }
      dom.btnSaveQueuePlaylist.disabled = true;
      if (dom.btnSaveQueueText) {
        dom.btnSaveQueueText.textContent = translateTextToEn('Добавление...');
      }
      send({
        action: 'save_queue_to_playlist',
        params: {
          name: plName,
          tracks: allQueueTracks
        }
      });
    });
  }

  // --- StandBy / TV Mode Fullscreen Queue Overlay (Previous, Current, Up Next) ---
  const TV_QUEUE_HISTORY_PREVIEW_LIMIT = 3;
  const lastTvQueueRenderKeys = { history: '', current: '', upcoming: '' };

  function isMobileLandscapeStandbyViewport() {
    if (document.body.classList.contains('standby-landscape-open')) return true;
    if (typeof window !== 'undefined' && typeof window.matchMedia === 'function') {
      return window.matchMedia('(max-height: 540px) and (min-width: 568px) and (orientation: landscape) and (hover: none) and (pointer: coarse)').matches;
    }
    return false;
  }

  function isStandbyQueueModalOpen() {
    const modal = document.getElementById('standby-queue-modal');
    return Boolean(modal && !modal.classList.contains('hidden'));
  }

  function syncStandbyQueueBadge() {
    const badge = document.getElementById('standby-queue-count-badge');
    if (!badge) return;
    const upcomingCount = Array.isArray(state.queue && state.queue.upcoming) ? state.queue.upcoming.length : 0;
    if (upcomingCount > 0) {
      const txt = upcomingCount > 99 ? '99+' : String(upcomingCount);
      if (badge.textContent !== txt) badge.textContent = txt;
      badge.classList.remove('hidden');
    } else {
      badge.classList.add('hidden');
    }
  }

  function formatTvQueueSubHtml(t) {
    const artist = t.artist || (IS_EN ? 'Unknown Artist' : 'Неизвестный исполнитель');
    const album = String(t.album || '').trim();
    const title = String(t.name || '').trim();
    if (album && album.toLowerCase() !== title.toLowerCase()) {
      return `${escapeHtml(artist)}<span class="tv-queue-sub-album"> · ${escapeHtml(album)}</span>`;
    }
    return escapeHtml(artist);
  }

  function renderStandbyQueueModal(opts = {}) {
    const forceRebuild = Boolean(opts && opts.force);
    if (forceRebuild) {
      lastTvQueueRenderKeys.history = '';
      lastTvQueueRenderKeys.current = '';
      lastTvQueueRenderKeys.upcoming = '';
    }

    const history = Array.isArray(state.queue && state.queue.history) ? state.queue.history : [];
    const upcoming = Array.isArray(state.queue && state.queue.upcoming) ? state.queue.upcoming : [];
    const playlistName = (state.queue && state.queue.playlist) || '';
    const cur = (state.track && state.track.name) ? state.track : null;
    const isPlaying = state.playerState === 'playing';

    if (history.length <= TV_QUEUE_HISTORY_PREVIEW_LIMIT) {
      state.tvQueueHistoryExpanded = false;
    }

    const subtitleEl = document.getElementById('standby-queue-subtitle');
    if (subtitleEl) {
      const isGenericPl = !playlistName || playlistName === 'Музыка' || playlistName === 'Music' || playlistName === 'Apple Music' || playlistName === 'Очередь';
      const plPrefix = (!isGenericPl && playlistName !== 'Очередь AMR')
        ? `${translateTextToEn(playlistName)} · `
        : (playlistName === 'Очередь AMR' ? (IS_EN ? 'AMR Queue · ' : 'Очередь AMR · ') : '');
      if (history.length > 0 || upcoming.length > 0) {
        if (IS_EN) {
          subtitleEl.textContent = history.length > 0
            ? `${plPrefix}${upcoming.length} up next · ${history.length} previous`
            : `${plPrefix}${upcoming.length} tracks up next`;
        } else {
          subtitleEl.textContent = history.length > 0
            ? `${plPrefix}${upcoming.length} далее · ${history.length} ранее`
            : `${plPrefix}${upcoming.length} треков далее`;
        }
      } else {
        subtitleEl.textContent = IS_EN
          ? 'Previous, now playing, and upcoming tracks'
          : 'Предыдущие, текущий трек и следующие композиции';
      }
    }

    const clearBtn = document.getElementById('btn-standby-queue-clear');
    if (clearBtn) {
      clearBtn.classList.toggle('hidden', upcoming.length === 0);
    }

    // 1. History ("Ранее")
    const histSection = document.getElementById('standby-queue-history-section');
    const histList = document.getElementById('standby-queue-history-list');
    const histCountEl = document.getElementById('standby-queue-history-count');
    const histToggleBtn = document.getElementById('btn-standby-queue-history-toggle');
    if (histSection && histList) {
      if (history.length === 0) {
        histSection.classList.add('hidden');
        histList.innerHTML = '';
        lastTvQueueRenderKeys.history = '';
      } else {
        histSection.classList.remove('hidden');
        if (histCountEl && histCountEl.textContent !== String(history.length)) {
          histCountEl.textContent = String(history.length);
        }
        const hasOverflow = history.length > TV_QUEUE_HISTORY_PREVIEW_LIMIT;
        const expanded = Boolean(state.tvQueueHistoryExpanded) && hasOverflow;
        if (histToggleBtn) {
          histToggleBtn.classList.toggle('hidden', !hasOverflow);
          if (hasOverflow) {
            histToggleBtn.textContent = expanded
              ? (IS_EN ? 'Show Less' : 'Свернуть')
              : (IS_EN ? `Show All (${history.length})` : `Показать все (${history.length})`);
          }
        }
        const slice = expanded ? history : history.slice(0, TV_QUEUE_HISTORY_PREVIEW_LIMIT);
        const chronological = slice.map((t, idx) => ({ track: t, historyIdx: idx })).reverse();
        const histKey = `${expanded ? '1' : '0'}|${chronological.map(({ track: t, historyIdx }) => `${historyIdx}:${t.id || t.numeric_id || t.numericId || ''}:${t.name}:${t.artist}:${t.album || ''}:${t.artwork || t.artwork_url || ''}`).join('|')}`;
        if (histKey !== lastTvQueueRenderKeys.history) {
          lastTvQueueRenderKeys.history = histKey;
          histList.innerHTML = '';
          chronological.forEach(({ track: t, historyIdx }) => {
            const row = document.createElement('div');
            row.className = 'tv-queue-row is-history';
            const artSrc = getArtworkSrc(t);
            const dur = formatTime(t.duration || 0);
            row.innerHTML = `
              <div class="tv-queue-index">
                <span class="tv-queue-index-num">−${historyIdx + 1}</span>
                <span class="tv-queue-index-play" aria-hidden="true">
                  <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor"><polygon points="6 4 20 12 6 20 6 4"/></svg>
                </span>
              </div>
              <img class="tv-queue-cover" src="${escapeHtml(artSrc)}" alt="" loading="lazy" data-fallback-icon="apple-touch-icon.svg">
              <div class="tv-queue-meta">
                <span class="tv-queue-title">${escapeHtml(t.name || (IS_EN ? 'Untitled' : 'Без названия'))}</span>
                <span class="tv-queue-sub">${formatTvQueueSubHtml(t)}</span>
              </div>
              <div class="tv-queue-right">
                <span class="tv-queue-dur">${dur}</span>
              </div>
            `;
            row.addEventListener('click', () => {
              optimisticPlay();
              markWaitingForPlayback({ targetName: t.name || '', expectedTrackName: t.name || '' });
              setUIBusy(true, IS_EN ? 'Switching track...' : 'Переход к треку...');
              send({ action: 'play_history_index', index: historyIdx, params: { index: historyIdx } });
            });
            histList.appendChild(row);
          });
        }
      }
    }

    // 2. Current ("Сейчас играет")
    const curContainer = document.getElementById('standby-queue-current-track');
    if (curContainer) {
      if (!cur) {
        const emptyKey = '__empty__';
        if (lastTvQueueRenderKeys.current !== emptyKey) {
          lastTvQueueRenderKeys.current = emptyKey;
          curContainer.innerHTML = `<div class="tv-queue-empty">${IS_EN ? 'Nothing playing right now' : 'Сейчас ничего не воспроизводится'}</div>`;
        }
      } else {
        const artSrc = getArtworkSrc(cur);
        const dur = formatTime(cur.duration || state.duration || 0);
        const curKey = `${cur.id || ''}|${cur.name}|${cur.artist}|${cur.album || ''}|${artSrc}`;
        if (curKey !== lastTvQueueRenderKeys.current) {
          lastTvQueueRenderKeys.current = curKey;
          curContainer.innerHTML = '';
          const row = document.createElement('div');
          row.className = 'tv-queue-row is-current';
          row.innerHTML = `
            <div class="tv-queue-index">
              <span class="tv-queue-eq ${isPlaying ? 'is-playing' : ''}" aria-hidden="true">
                <span class="tv-queue-eq-bar"></span>
                <span class="tv-queue-eq-bar"></span>
                <span class="tv-queue-eq-bar"></span>
              </span>
            </div>
            <img class="tv-queue-cover" src="${escapeHtml(artSrc)}" alt="" loading="lazy" data-fallback-icon="apple-touch-icon.svg">
            <div class="tv-queue-meta">
              <span class="tv-queue-title">${escapeHtml(cur.name || (IS_EN ? 'Untitled' : 'Без названия'))}</span>
              <span class="tv-queue-sub">${formatTvQueueSubHtml(cur)}</span>
            </div>
            <div class="tv-queue-right">
              <span class="tv-queue-live-pill ${isPlaying ? '' : 'is-paused'}">${isPlaying ? (IS_EN ? 'PLAYING' : 'ИГРАЕТ') : (IS_EN ? 'PAUSED' : 'ПАУЗА')}</span>
              <span class="tv-queue-dur">${dur}</span>
            </div>
          `;
          row.addEventListener('click', () => {
            togglePlayPause();
          });
          curContainer.appendChild(row);
        } else {
          const eqEl = curContainer.querySelector('.tv-queue-eq');
          if (eqEl) eqEl.classList.toggle('is-playing', isPlaying);
          const pillEl = curContainer.querySelector('.tv-queue-live-pill');
          if (pillEl) {
            pillEl.classList.toggle('is-paused', !isPlaying);
            const pillTxt = isPlaying ? (IS_EN ? 'PLAYING' : 'ИГРАЕТ') : (IS_EN ? 'PAUSED' : 'ПАУЗА');
            if (pillEl.textContent !== pillTxt) pillEl.textContent = pillTxt;
          }
          const durEl = curContainer.querySelector('.tv-queue-dur');
          if (durEl && durEl.textContent !== dur) durEl.textContent = dur;
        }
      }
    }

    // 3. Upcoming ("Далее в очереди")
    const upList = document.getElementById('standby-queue-upcoming-list');
    const upCountEl = document.getElementById('standby-queue-upcoming-count');
    if (upCountEl && upCountEl.textContent !== String(upcoming.length)) {
      upCountEl.textContent = String(upcoming.length);
    }
    if (upList) {
      if (upcoming.length === 0) {
        const emptyUpKey = '__empty_upcoming__';
        if (lastTvQueueRenderKeys.upcoming !== emptyUpKey) {
          lastTvQueueRenderKeys.upcoming = emptyUpKey;
          upList.innerHTML = `<div class="tv-queue-empty">${IS_EN ? 'No upcoming tracks in queue' : 'Нет предстоящих треков в очереди'}</div>`;
        }
      } else {
        const upKey = upcoming.map(t => `${t.id || t.numeric_id || t.numericId || ''}:${t.name}:${t.artist}:${t.album || ''}:${t.artwork || t.artwork_url || ''}`).join('|');
        if (upKey !== lastTvQueueRenderKeys.upcoming) {
          lastTvQueueRenderKeys.upcoming = upKey;
          upList.innerHTML = '';
          upcoming.forEach((t, idx) => {
            const row = document.createElement('div');
            row.className = 'tv-queue-row is-upcoming';
            const artSrc = getArtworkSrc(t);
            const dur = formatTime(t.duration || 0);
            row.innerHTML = `
              <div class="tv-queue-index">
                <span class="tv-queue-index-num">${idx + 1}</span>
                <span class="tv-queue-index-play" aria-hidden="true">
                  <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor"><polygon points="6 4 20 12 6 20 6 4"/></svg>
                </span>
              </div>
              <img class="tv-queue-cover" src="${escapeHtml(artSrc)}" alt="" loading="lazy" data-fallback-icon="apple-touch-icon.svg">
              <div class="tv-queue-meta">
                <span class="tv-queue-title">${escapeHtml(t.name || (IS_EN ? 'Untitled' : 'Без названия'))}</span>
                <span class="tv-queue-sub">${formatTvQueueSubHtml(t)}</span>
              </div>
              <div class="tv-queue-right">
                <span class="tv-queue-dur">${dur}</span>
              </div>
            `;
            row.addEventListener('click', () => {
              optimisticPlay();
              markWaitingForPlayback({ targetName: t.name || '', expectedTrackName: t.name || '' });
              setUIBusy(true, IS_EN ? 'Switching track...' : 'Переход к треку...');
              send({ action: 'queue_play_index', params: { index: idx } });
            });
            upList.appendChild(row);
          });
        }
      }
    }
  }

  function openStandbyQueueModal() {
    if (isMobileLandscapeStandbyViewport()) return;
    const modal = document.getElementById('standby-queue-modal');
    if (!modal) return;
    if (typeof closeStandbyLibraryModal === 'function') closeStandbyLibraryModal();
    if (typeof closeStandbyAiModal === 'function') closeStandbyAiModal();
    const p = document.getElementById('top-settings-popover');
    if (p) {
      blurFocusedInContainer(p);
      p.classList.add('hidden');
      p.setAttribute('aria-hidden', 'true');
    }

    state.tvQueueHistoryExpanded = false;
    renderStandbyQueueModal({ force: true });
    send({ action: 'get_queue' });

    modal.classList.remove('hidden');
    modal.setAttribute('aria-hidden', 'false');

    const scrollEl = document.getElementById('standby-queue-scroll');
    if (scrollEl) {
      scrollEl.scrollTop = 0;
    }
  }

  function closeStandbyQueueModal() {
    const modal = document.getElementById('standby-queue-modal');
    if (!modal) return;
    blurFocusedInContainer(modal);
    modal.classList.add('hidden');
    modal.setAttribute('aria-hidden', 'true');
  }

  const btnStandbyQueueClear = document.getElementById('btn-standby-queue-clear');
  if (btnStandbyQueueClear) {
    btnStandbyQueueClear.addEventListener('click', () => {
      triggerHaptic('light');
      send({ action: 'queue_clear' });
    });
  }

  const btnStandbyQueueHistToggle = document.getElementById('btn-standby-queue-history-toggle');
  if (btnStandbyQueueHistToggle) {
    btnStandbyQueueHistToggle.addEventListener('click', () => {
      triggerHaptic('light');
      state.tvQueueHistoryExpanded = !state.tvQueueHistoryExpanded;
      lastTvQueueRenderKeys.history = '';
      renderStandbyQueueModal();
    });
  }

// === MODULE: 13-library-helpers-and-removal.js ===
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

// === MODULE: 14-playlists-recent-and-artists.js ===
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

// === MODULE: 15-artist-detail-albums-and-songs.js ===
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

// === MODULE: 16-album-detail-and-tracks.js ===
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

// === MODULE: 17-ai-prompts-and-sonic-bridge.js ===
  const AI_PROMPT_SUGGESTIONS_POOL = [
    {
      labelRu: '🎷 Ночной нуар-джаз с саксофоном',
      labelEn: '🎷 Late-night noir jazz with sax',
      promptRu: 'Ночной нуар-джаз с тёплым саксофоном и контрабасом',
      promptEn: 'Late-night noir jazz with warm tenor saxophone and upright bass'
    },
    {
      labelRu: '🎸 Аналоговый прог-рок 70-х',
      labelEn: '🎸 70s analog progressive rock',
      promptRu: 'Аналоговый прог-рок 70-х с широкой голографической сценой',
      promptEn: '1970s analog progressive rock with wide holographic soundstage'
    },
    {
      labelRu: '🎹 Эмбиент и пианино для фокуса',
      labelEn: '🎹 Deep ambient & piano for focus',
      promptRu: 'Глубокий эмбиент и неоклассическое пианино для фокуса',
      promptEn: 'Deep ambient and neoclassical felt piano for focus'
    },
    {
      labelRu: '🎙️ Эталонный вокал и акустика',
      labelEn: '🎙️ Reference vocals & acoustics',
      promptRu: 'Аудиофильский эталонный женский вокал и живая акустика',
      promptEn: 'Audiophile reference female vocal and intimate acoustic guitar'
    },
    {
      labelRu: '🌃 Кинематографичный синтвейв 80-х',
      labelEn: '🌃 Cinematic 80s synthwave',
      promptRu: 'Кинематографичный синтвейв 80-х и глубокий аналоговый синт',
      promptEn: 'Cinematic 1980s synthwave and deep analog synthesizers'
    },
    {
      labelRu: '🔊 Бристольский трип-хоп и даунтемпо',
      labelEn: '🔊 Bristol trip-hop & downtempo',
      promptRu: 'Бристольский трип-хоп 90-х и глубокий даунтемпо с суббасом',
      promptEn: '1990s Bristol trip-hop and deep downtempo sub-bass groove'
    },
    {
      labelRu: '🎻 Камерные струнные и виолончель',
      labelEn: '🎻 Chamber strings & live cello',
      promptRu: 'Скандинавская неоклассика, живая виолончель и камерные струнные',
      promptEn: 'Nordic neoclassical chamber strings and intimate acoustic cello'
    },
    {
      labelRu: '🌊 Дрим-поп и воздушный шугейз',
      labelEn: '🌊 Dream-pop & airy shoegaze',
      promptRu: 'Атмосферный дрим-поп и воздушный шугейз с гитарным ревербом',
      promptEn: 'Atmospheric dream-pop and ethereal shoegaze with lush reverb'
    },
    {
      labelRu: '🥃 Классический блюз-рок на лампе',
      labelEn: '🥃 Tube-driven blues rock',
      promptRu: 'Аудиофильский блюз-рок с живой ламповой гитарой и органом Hammond',
      promptEn: 'Audiophile blues rock with warm tube guitar and Hammond organ'
    },
    {
      labelRu: '🎺 Джаз-фанк и винтажный Rhodes',
      labelEn: '🎺 Jazz-funk & vintage Rhodes',
      promptRu: 'Винтажный джаз-фанк 70-х, тёплый Fender Rhodes и плотный грув',
      promptEn: '1970s spiritual jazz-funk with warm Fender Rhodes and tight bass'
    },
    {
      labelRu: '🌌 Космическая электроника (Берлин)',
      labelEn: '🌌 Berlin school cosmic synth',
      promptRu: 'Космическая аналоговая электроника в стиле берлинской школы и секвенсоры',
      promptEn: 'Cosmic Berlin-school analog modular synthesizers and arpeggios'
    },
    {
      labelRu: '☕ Босса-нова и акустика 60-х',
      labelEn: '☕ 60s bossa nova & nylon guitar',
      promptRu: 'Тёплая бразильская босса-нова 60-х с нейлоновой гитарой и мягким вокалом',
      promptEn: 'Warm 1960s Brazilian bossa nova with nylon guitar and soft vocals'
    },
    {
      labelRu: '🥁 Сложный мат-рок и полиритмия',
      labelEn: '🥁 Math-rock & odd-meter drums',
      promptRu: 'Инструментальный пост-рок и полиритмический прог с эталонной динамикой барабанов',
      promptEn: 'Instrumental post-rock and polyrhythmic prog with reference drum dynamics'
    },
    {
      labelRu: '🕯️ Дарк-джаз и кинематографичный нуар',
      labelEn: '🕯️ Dark jazz & cinematic noir',
      promptRu: 'Медленный дарк-джаз, баритон-саксофон и атмосфера дождливого ночного города',
      promptEn: 'Slow cinematic dark jazz with baritone sax and rainy midnight atmosphere'
    },
    {
      labelRu: '🎛️ Минимал-техно и даб-аккорды',
      labelEn: '🎛️ Dub techno & deep sub-bass',
      promptRu: 'Глубокий даб-техно и гипнотический минимал с бархатным суббасом',
      promptEn: 'Deep hypnotic dub techno and minimal electronica with cavernous sub-bass'
    },
    {
      labelRu: '🪕 Инди-фолк и камерная акустика',
      labelEn: '🪕 Indie folk & warm acoustics',
      promptRu: 'Камерный инди-фолк, живой пальцевый перебор гитары и интимная сцена',
      promptEn: 'Intimate indie folk with fingerstyle acoustic guitar and natural room acoustics'
    },
    {
      labelRu: '🎼 Симфонические саундтреки',
      labelEn: '🎼 Epic orchestral soundtracks',
      promptRu: 'Масштабные симфонические саундтреки с широким динамическим диапазоном',
      promptEn: 'Epic orchestral film scores with wide audiophile dynamic range'
    },
    {
      labelRu: '🪩 Японский сити-поп 80-х',
      labelEn: '🪩 80s Japanese city pop & funk',
      promptRu: 'Японский сити-поп и соул-фанк 80-х с ярким слэп-басом и духовыми',
      promptEn: '1980s Japanese city pop and boogie funk with slap bass and brass'
    }
  ];

  const AI_DYNAMIC_MOODS = [
    { icon: '🎷', shortRu: 'Ночной нуар', fullRu: 'Ночной атмосферный нуар', shortEn: 'Midnight noir', fullEn: 'Late-night atmospheric noir' },
    { icon: '🌌', shortRu: 'Глубокий космос', fullRu: 'Глубокая космическая атмосфера', shortEn: 'Deep cosmos', fullEn: 'Deep cosmic atmosphere' },
    { icon: '🕯️', shortRu: 'Интимная сцена', fullRu: 'Камерная интимная акустика близкого поля', shortEn: 'Intimate stage', fullEn: 'Near-field intimate chamber acoustics' },
    { icon: '⚡', shortRu: 'Высокий драйв', fullRu: 'Высокодинамичный драйв и панч', shortEn: 'High-energy drive', fullEn: 'High-contrast dynamic drive and punch' },
    { icon: '🌊', shortRu: 'Голографический 3D', fullRu: 'Широкая голографическая звуковая сцена', shortEn: '3D soundstage', fullEn: 'Wide holographic 3D soundstage' },
    { icon: '🥃', shortRu: 'Тёплая лампа', fullRu: 'Тёплое аналоговое ламповое звучание', shortEn: 'Warm tube glow', fullEn: 'Warm analog vacuum-tube timbre' },
    { icon: '🌧️', shortRu: 'Дождливый город', fullRu: 'Меланхолия дождливого ночного мегаполиса', shortEn: 'Rainy midnight', fullEn: 'Rainy midnight metropolis atmosphere' },
    { icon: '🧘', shortRu: 'Глубокий фокус', fullRu: 'Спокойная гипнотическая концентрация', shortEn: 'Deep focus', fullEn: 'Hypnotic calm for deep focus' },
    { icon: '🌆', shortRu: 'Неоновый ретро', fullRu: 'Кинематографичный неоновый ретро-вайб', shortEn: 'Neon retro', fullEn: 'Cinematic neon retro atmosphere' },
    { icon: '🏔️', shortRu: 'Северный воздух', fullRu: 'Прозрачная скандинавская прохлада', shortEn: 'Nordic air', fullEn: 'Crystalline Nordic spaciousness' },
    { icon: '🔥', shortRu: 'Живая студия', fullRu: 'Энергия живой студийной записи с одного дубля', shortEn: 'Live studio take', fullEn: 'Raw one-take live studio energy' },
    { icon: '🌙', shortRu: 'После полуночи', fullRu: 'Мягкий бархатный грув после полуночи', shortEn: 'After-hours', fullEn: 'Velvet after-hours lounge groove' },
    { icon: '💎', shortRu: 'Кристальный Hi-Res', fullRu: 'Эталонная прозрачность и микродинамика', shortEn: 'Reference Hi-Res', fullEn: 'Reference transparency and micro-dynamics' },
    { icon: '🎞️', shortRu: 'Магнитная лента', fullRu: 'Винтажный мастеринг на аналоговую ленту', shortEn: 'Analog tape', fullEn: 'Vintage reel-to-reel analog tape warmth' },
    { icon: '🌅', shortRu: 'Рассветный чилл', fullRu: 'Тёплый солнечный рассветный грув', shortEn: 'Sunrise chill', fullEn: 'Warm golden-hour sunrise groove' },
    { icon: '🌀', shortRu: 'Психоделика', fullRu: 'Глубокое психоделическое погружение', shortEn: 'Psychedelic voyage', fullEn: 'Deep psychedelic sonic immersion' }
  ];

  const AI_DYNAMIC_GENRES = [
    { shortRu: 'прог-рок 70-х', fullRu: 'прогрессивный рок 70-х', shortEn: '70s prog rock', fullEn: '1970s progressive rock' },
    { shortRu: 'кул-джаз', fullRu: 'модальный и кул-джаз', shortEn: 'cool jazz', fullEn: 'modal and cool jazz' },
    { shortRu: 'трип-хоп 90-х', fullRu: 'бристольский трип-хоп и даунтемпо', shortEn: '90s trip-hop', fullEn: 'Bristol trip-hop and downtempo' },
    { shortRu: 'неоклассика', fullRu: 'современная камерная неоклассика', shortEn: 'neoclassical', fullEn: 'modern chamber neoclassical' },
    { shortRu: 'синтвейв 80-х', fullRu: 'аналоговый синтвейв и электроника 80-х', shortEn: '80s synthwave', fullEn: '1980s analog synthwave' },
    { shortRu: 'блюз-рок', fullRu: 'аудиофильский блюз-рок', shortEn: 'blues rock', fullEn: 'audiophile blues rock' },
    { shortRu: 'даб-техно', fullRu: 'глубокое даб-техно и минимал', shortEn: 'dub techno', fullEn: 'deep dub techno and minimal' },
    { shortRu: 'джаз-фанк', fullRu: 'грувовый джаз-фанк и соул', shortEn: 'jazz-funk', fullEn: 'groovy spiritual jazz-funk' },
    { shortRu: 'пост-рок', fullRu: 'инструментальный кинематографичный пост-рок', shortEn: 'post-rock', fullEn: 'cinematic instrumental post-rock' },
    { shortRu: 'босса-нова 60-х', fullRu: 'бразильская босса-нова 60-х', shortEn: '60s bossa nova', fullEn: '1960s Brazilian bossa nova' },
    { shortRu: 'дрим-поп и шугейз', fullRu: 'воздушный дрим-поп и шугейз', shortEn: 'dream-pop & shoegaze', fullEn: 'ethereal dream-pop and shoegaze' },
    { shortRu: 'японский сити-поп', fullRu: 'японский сити-поп и буги-фанк 80-х', shortEn: 'Japanese city pop', fullEn: '1980s Japanese city pop and funk' },
    { shortRu: 'дарк-джаз', fullRu: 'медленный кинематографичный дарк-джаз', shortEn: 'dark jazz', fullEn: 'slow cinematic dark jazz' },
    { shortRu: 'инди-фолк', fullRu: 'акустический инди-фолк', shortEn: 'indie folk', fullEn: 'intimate acoustic indie folk' },
    { shortRu: 'берлинский эмбиент', fullRu: 'космическая электроника берлинской школы', shortEn: 'Berlin school synth', fullEn: 'Berlin-school modular electronica' },
    { shortRu: 'симфо-саундтрек', fullRu: 'эпический оркестровый саундтрек', shortEn: 'epic film score', fullEn: 'epic orchestral film score' },
    { shortRu: 'афробит и фьюжн', fullRu: 'полиритмический афробит и джаз-фьюжн', shortEn: 'afrobeat fusion', fullEn: 'polyrhythmic afrobeat and jazz fusion' },
    { shortRu: 'нео-соул', fullRu: 'бархатный нео-соул и R&B', shortEn: 'neo-soul', fullEn: 'velvet audiophile neo-soul' }
  ];

  const AI_DYNAMIC_INSTRUMENTS = [
    { shortRu: 'с саксофоном', fullRu: 'с бархатным тенор-саксофоном и контрабасом', shortEn: 'with tenor sax', fullEn: 'with warm tenor saxophone and upright bass' },
    { shortRu: 'и фетровое пианино', fullRu: 'с мягким фетровым пианино и виолончелью', shortEn: '& felt piano', fullEn: 'with intimate felt piano and cello' },
    { shortRu: 'и живой вокал', fullRu: 'с эталонным женским вокалом близкого микрофона', shortEn: '& reference vocals', fullEn: 'with close-mic reference female vocals' },
    { shortRu: 'и ламповая гитара', fullRu: 'с певучей электрогитарой и органом Hammond', shortEn: '& tube guitar', fullEn: 'with singing tube guitar and Hammond organ' },
    { shortRu: 'и аналоговый Moog', fullRu: 'с глубоким аналоговым синтезатором Moog и арпеджио', shortEn: '& analog Moog', fullEn: 'with deep Moog synthesizers and arpeggios' },
    { shortRu: 'и глубокий суббас', fullRu: 'с упругим суббасом и чёткой атакой барабанов', shortEn: '& deep sub-bass', fullEn: 'with visceral sub-bass and crisp drum transients' },
    { shortRu: 'и Fender Rhodes', fullRu: 'с тёплым электропиано Fender Rhodes и щётками', shortEn: '& Fender Rhodes', fullEn: 'with warm Fender Rhodes and brushed drums' },
    { shortRu: 'и акустическая гитара', fullRu: 'с живым пальцевым перебором акустической гитары', shortEn: '& acoustic guitar', fullEn: 'with fingerstyle acoustic guitar and natural room reverb' },
    { shortRu: 'и камерные струнные', fullRu: 'с живым струнным квартетом и широким залом', shortEn: '& chamber strings', fullEn: 'with live string quartet and concert hall acoustics' },
    { shortRu: 'и слэп-бас', fullRu: 'с фанковым слэп-басом и духовой секцией', shortEn: '& slap bass', fullEn: 'with tight slap bass and brass section' },
    { shortRu: 'и вибрафон', fullRu: 'с мерцающим вибрафоном и мягкой перкуссией', shortEn: '& vibraphone', fullEn: 'with shimmering vibraphone and percussion' },
    { shortRu: 'и баритон-саксофон', fullRu: 'с низким баритон-саксофоном и густым ревербом', shortEn: '& baritone sax', fullEn: 'with smoky baritone sax and lush reverb' }
  ];

  const seenAiPromptKeys = new Set();
  try {
    const savedSeen = JSON.parse(sessionStorage.getItem('amr_seen_ai_prompts_v1') || '[]');
    if (Array.isArray(savedSeen)) {
      savedSeen.forEach(k => seenAiPromptKeys.add(String(k)));
    }
  } catch (_) {}

  function recordSeenAiPromptKey(key) {
    if (!key) return;
    seenAiPromptKeys.add(key.toLowerCase());
    if (seenAiPromptKeys.size > 160) {
      const arr = Array.from(seenAiPromptKeys).slice(-100);
      seenAiPromptKeys.clear();
      arr.forEach(k => seenAiPromptKeys.add(k));
    }
    try {
      sessionStorage.setItem('amr_seen_ai_prompts_v1', JSON.stringify(Array.from(seenAiPromptKeys)));
    } catch (_) {}
  }

  function synthesizeDynamicClientPrompt() {
    for (let attempt = 0; attempt < 50; attempt++) {
      const m = AI_DYNAMIC_MOODS[Math.floor(Math.random() * AI_DYNAMIC_MOODS.length)];
      const g = AI_DYNAMIC_GENRES[Math.floor(Math.random() * AI_DYNAMIC_GENRES.length)];
      const inst = AI_DYNAMIC_INSTRUMENTS[Math.floor(Math.random() * AI_DYNAMIC_INSTRUMENTS.length)];
      const labelRu = `${m.icon} ${m.shortRu} • ${g.shortRu} ${inst.shortRu}`;
      const promptRu = `${m.fullRu}: ${g.fullRu} ${inst.fullRu}`;
      const labelEn = `${m.icon} ${m.shortEn} • ${g.shortEn} ${inst.shortEn}`;
      const promptEn = `${m.fullEn}: ${g.fullEn} ${inst.fullEn}`;
      if (!seenAiPromptKeys.has(promptRu.toLowerCase())) {
        recordSeenAiPromptKey(promptRu);
        return { labelRu, promptRu, labelEn, promptEn };
      }
    }
    const m = AI_DYNAMIC_MOODS[Math.floor(Math.random() * AI_DYNAMIC_MOODS.length)];
    const g = AI_DYNAMIC_GENRES[Math.floor(Math.random() * AI_DYNAMIC_GENRES.length)];
    const inst = AI_DYNAMIC_INSTRUMENTS[Math.floor(Math.random() * AI_DYNAMIC_INSTRUMENTS.length)];
    return {
      labelRu: `${m.icon} ${m.shortRu} • ${g.shortRu} ${inst.shortRu}`,
      promptRu: `${m.fullRu}: ${g.fullRu} ${inst.fullRu}`,
      labelEn: `${m.icon} ${m.shortEn} • ${g.shortEn} ${inst.shortEn}`,
      promptEn: `${m.fullEn}: ${g.fullEn} ${inst.fullEn}`
    };
  }

  function generateFreshAiPromptsBatch(count = 6) {
    const unseenBase = AI_PROMPT_SUGGESTIONS_POOL
      .filter(p => !seenAiPromptKeys.has((p.promptRu || '').toLowerCase()))
      .sort(() => Math.random() - 0.5);

    const batch = [];
    const baseQuota = Math.min(unseenBase.length, Math.max(2, Math.floor(count / 2)));
    for (let i = 0; i < baseQuota; i++) {
      const item = unseenBase[i];
      recordSeenAiPromptKey(item.promptRu);
      batch.push(item);
    }
    while (batch.length < count) {
      batch.push(synthesizeDynamicClientPrompt());
    }
    return batch.sort(() => Math.random() - 0.5);
  }

  let currentAiPromptsBatch = generateFreshAiPromptsBatch(6);

  function rotateAiPromptSuggestions() {
    currentAiPromptsBatch = generateFreshAiPromptsBatch(6);
    renderAiPromptChipsGrid(true);
    send({
      action: 'refresh_ai_prompts',
      params: {
        exclude_prompts: currentAiPromptsBatch.map(p => IS_EN ? p.promptEn : p.promptRu)
      }
    });
  }

  function isPromptPinnedClient(prompt) {
    const clean = String(prompt || '').trim().toLowerCase();
    if (!clean || !Array.isArray(state.pinnedAiPrompts)) return false;
    return state.pinnedAiPrompts.some((p) => {
      const p1 = String(p.prompt || '').trim().toLowerCase();
      const p2 = String(p.prompt_ru || p.promptRu || '').trim().toLowerCase();
      const p3 = String(p.prompt_en || p.promptEn || '').trim().toLowerCase();
      return p1 === clean || p2 === clean || p3 === clean;
    });
  }

  function renderAiPromptChipItemHtml(item, isPinnedSection = false) {
    const prompt = IS_EN ? (item.promptEn || item.prompt_en || item.prompt || '') : (item.promptRu || item.prompt_ru || item.prompt || '');
    const label = IS_EN ? (item.labelEn || item.label_en || item.label || prompt) : (item.labelRu || item.label_ru || item.label || prompt);
    const pinned = isPinnedSection || isPromptPinnedClient(prompt);
    return `<div class="ai-prompt-chip-item ${pinned ? 'is-pinned' : ''}">
      <button type="button" class="ai-prompt-chip" data-ai-prompt="${escapeHtml(prompt)}" data-ai-label="${escapeHtml(label)}">${escapeHtml(label)}</button>
      <button type="button" class="ai-chip-pin-btn ${pinned ? 'active' : ''}" data-pin-prompt="${escapeHtml(prompt)}" data-pin-label="${escapeHtml(label)}" title="${translateTextToEn(pinned ? 'Убрать из избранных вайбов' : 'Закрепить вайб в избранном')}" aria-label="Pin">${pinned ? '★' : '☆'}</button>
    </div>`;
  }

  function renderPinnedAiSectionHtml() {
    if (!Array.isArray(state.pinnedAiPrompts) || state.pinnedAiPrompts.length === 0) {
      return '';
    }
    const itemsHtml = state.pinnedAiPrompts.map((item) => renderAiPromptChipItemHtml(item, true)).join('');
    return `
      <div class="ai-pinned-section">
        <div class="ai-pinned-header">
          <span class="ai-pinned-badge">★ ${translateTextToEn('ИЗБРАННЫЕ ВАЙБЫ')}</span>
        </div>
        <div class="ai-curator-prompts-grid ai-pinned-grid">
          ${itemsHtml}
        </div>
      </div>`;
  }

  function togglePinAiPrompt(prompt, label) {
    const cleanPrompt = String(prompt || '').trim();
    if (!cleanPrompt) return;
    const cleanLabel = String(label || cleanPrompt).trim();
    const currentlyPinned = isPromptPinnedClient(cleanPrompt);
    triggerHaptic('light');

    if (currentlyPinned) {
      const lower = cleanPrompt.toLowerCase();
      state.pinnedAiPrompts = (state.pinnedAiPrompts || []).filter((p) => {
        const p1 = String(p.prompt || '').trim().toLowerCase();
        const p2 = String(p.prompt_ru || p.promptRu || '').trim().toLowerCase();
        const p3 = String(p.prompt_en || p.promptEn || '').trim().toLowerCase();
        return p1 !== lower && p2 !== lower && p3 !== lower;
      });
      showToast(translateTextToEn('Удалено из избранных вайбов'));
    } else {
      const entry = {
        label: cleanLabel,
        prompt: cleanPrompt,
        label_ru: cleanLabel,
        prompt_ru: cleanPrompt,
        label_en: cleanLabel,
        prompt_en: cleanPrompt
      };
      state.pinnedAiPrompts = [entry, ...(state.pinnedAiPrompts || [])];
      showToast(translateTextToEn('★ Вайб закреплён в избранном'));
    }

    send({
      action: 'toggle_ai_pin_prompt',
      params: {
        prompt: cleanPrompt,
        label: cleanLabel,
        label_ru: cleanLabel,
        prompt_ru: cleanPrompt,
        label_en: cleanLabel,
        prompt_en: cleanPrompt
      }
    });

    syncPinnedAiPromptsUI();
  }

  function syncPinnedAiPromptsUI() {
    const pinnedContainer = document.getElementById('ai-pinned-prompts-container');
    if (pinnedContainer) {
      pinnedContainer.innerHTML = renderPinnedAiSectionHtml();
    }
    const mainGrid = document.getElementById('ai-main-prompts-grid');
    if (mainGrid) {
      mainGrid.innerHTML = currentAiPromptsBatch.map((item) => renderAiPromptChipItemHtml(item, false)).join('');
    }
    if (pinnedContainer || mainGrid) {
      bindAiPromptChips();
    }

    const heroPinBtn = document.getElementById('btn-ai-curated-pin');
    const heroPinText = document.getElementById('btn-ai-curated-pin-text');
    if (heroPinBtn) {
      const pPrompt = heroPinBtn.getAttribute('data-pin-prompt') || state.activeAiCuratedPrompt || '';
      const isPin = isPromptPinnedClient(pPrompt);
      heroPinBtn.classList.toggle('active', isPin);
      if (heroPinText) {
        heroPinText.textContent = translateTextToEn(isPin ? '★ В избранном' : '☆ Закрепить вайб');
      }
    }

    document.querySelectorAll('#standby-ai-tag-cloud .standby-ai-tag-pill').forEach((pill) => {
      const pPrompt = pill.getAttribute('data-ai-prompt') || '';
      const isPin = isPromptPinnedClient(pPrompt);
      pill.classList.toggle('is-pinned', isPin);
      const badge = pill.querySelector('.standby-tag-pin-badge');
      if (badge) {
        badge.textContent = isPin ? '★' : '☆';
        badge.classList.toggle('active', isPin);
      }
    });
  }

  function renderAiPromptChipsGrid(animateBtn = false) {
    const grid = document.getElementById('ai-main-prompts-grid') || document.querySelector('.ai-curator-prompts-grid');
    if (!grid) return;
    grid.innerHTML = currentAiPromptsBatch.map((item) => renderAiPromptChipItemHtml(item, false)).join('');
    const pinnedContainer = document.getElementById('ai-pinned-prompts-container');
    if (pinnedContainer) {
      pinnedContainer.innerHTML = renderPinnedAiSectionHtml();
    }
    bindAiPromptChips();

    if (animateBtn) {
      const refreshBtn = document.getElementById('btn-refresh-ai-prompts');
      if (refreshBtn) {
        refreshBtn.classList.remove('spinning');
        void refreshBtn.offsetWidth;
        refreshBtn.classList.add('spinning');
        setTimeout(() => refreshBtn.classList.remove('spinning'), 460);
      }
    }
  }

  function syncAiCuratorEnabledUI() {
    const aiFilterChip = document.querySelector('.filter-chip-ai');
    if (aiFilterChip) {
      aiFilterChip.classList.toggle('hidden', !state.aiCuratorEnabled);
    }
    const bridgeFilterChip = document.querySelector('.filter-chip-bridge');
    if (bridgeFilterChip) {
      bridgeFilterChip.classList.toggle('hidden', !state.aiCuratorEnabled);
    }
    const standbyAiBtn = document.getElementById('standby-btn-ai-curator');
    if (standbyAiBtn) {
      standbyAiBtn.classList.toggle('hidden', !state.aiCuratorEnabled);
    }
    const standbyAiVibeBtn = document.getElementById('standby-btn-ai-track-vibe');
    if (standbyAiVibeBtn) {
      standbyAiVibeBtn.classList.toggle('hidden', !state.aiCuratorEnabled);
    }
    if (dom.btnAiTrackVibe) {
      dom.btnAiTrackVibe.classList.toggle('hidden', !state.aiCuratorEnabled);
    }
    if (dom.btnAiMixByTrack) {
      dom.btnAiMixByTrack.classList.toggle('hidden', !state.aiCuratorEnabled);
    }
    if (dom.btnSonicBridgeByTrack) {
      dom.btnSonicBridgeByTrack.classList.toggle('hidden', !state.aiCuratorEnabled);
    }
    if (!state.aiCuratorEnabled) {
      const standbyAiModal = document.getElementById('standby-ai-modal');
      if (standbyAiModal && !standbyAiModal.classList.contains('hidden')) {
        standbyAiModal.classList.add('hidden');
        standbyAiModal.setAttribute('aria-hidden', 'true');
      }
    }
    if (!state.aiCuratorEnabled && (state.searchScope === 'ai' || state.searchScope === 'bridge')) {
      state.searchScope = 'all';
      dom.filterChips.forEach(c => c.classList.toggle('active', c.dataset.scope === 'all'));
      if (dom.searchInput) {
        dom.searchInput.placeholder = translateTextToEn('Поиск в Apple Music...');
      }
    }
    if (!state.searchQuery) {
      renderSearchPlaceholder();
    }
  }

  function handleAiCuratorSettings(data) {
    if (!data || typeof data !== 'object') return;
    if (data.is_apple_silicon !== undefined) {
      state.isAppleSilicon = Boolean(data.is_apple_silicon);
    }
    if (Array.isArray(data.pinned)) {
      state.pinnedAiPrompts = data.pinned;
      syncPinnedAiPromptsUI();
    }
    if (data.is_enabled !== undefined || data.isEnabled !== undefined) {
      const nextEnabled = (state.isAppleSilicon === false)
        ? false
        : Boolean(data.is_enabled !== undefined ? data.is_enabled : data.isEnabled);
      if (state.aiCuratorEnabled !== nextEnabled) {
        state.aiCuratorEnabled = nextEnabled;
        syncAiCuratorEnabledUI();
        if (dom.playerArtwork && dom.playerArtwork.complete && currentLoadedArtworkUrl && currentLoadedArtworkUrl !== 'apple-touch-icon.svg') {
          AmbientBackgroundManager.currentPaletteKey = '';
          AmbientBackgroundManager.updateFromImage(dom.playerArtwork, currentLoadedArtworkUrl);
        }
      }
    }
  }

  const SONIC_BRIDGE_EXAMPLES = [
    {
      labelRu: '🎷 Miles Davis → 🤖 Daft Punk',
      labelEn: '🎷 Miles Davis → 🤖 Daft Punk',
      from: 'Miles Davis — Blue in Green',
      to: 'Daft Punk — Veridis Quo'
    },
    {
      labelRu: '🎸 Pink Floyd → 🎹 Nils Frahm',
      labelEn: '🎸 Pink Floyd → 🎹 Nils Frahm',
      from: 'Pink Floyd — Shine On You Crazy Diamond',
      to: 'Nils Frahm — Says'
    },
    {
      labelRu: '🎻 Hans Zimmer → 🌌 Massive Attack',
      labelEn: '🎻 Hans Zimmer → 🌌 Massive Attack',
      from: 'Hans Zimmer — Time',
      to: 'Massive Attack — Teardrop'
    },
    {
      labelRu: '🌙 Sade → 🎛 Radiohead',
      labelEn: '🌙 Sade → 🎛 Radiohead',
      from: 'Sade — No Ordinary Love',
      to: 'Radiohead — Everything In Its Right Place'
    }
  ];

  function buildSonicBridgeCardElement(compact = false) {
    const card = document.createElement('div');
    card.className = `sonic-bridge-builder-card${compact ? ' compact' : ''}`;
    const hasCurrentTrack = Boolean(state.track && state.track.name);
    const steps = Number(state.sonicBridgeSteps) || 12;
    const examplesHtml = compact ? '' : `
      <div class="sonic-bridge-examples">
        ${SONIC_BRIDGE_EXAMPLES.map((ex, i) => `
          <button type="button" class="sonic-bridge-example-chip" data-bridge-idx="${i}">
            ${escapeHtml(IS_EN ? ex.labelEn : ex.labelRu)}
          </button>
        `).join('')}
      </div>
    `;

    card.innerHTML = `
      <div class="sonic-bridge-top">
        <span class="sonic-bridge-pill">🌉 SONIC BRIDGE • 512-D SLERP GEODESIC</span>
      </div>
      ${compact ? '' : `
        <h3 class="sonic-bridge-title">${IS_EN ? 'Sonic Bridge: Smooth Musical Trajectory' : 'Sonic Bridge: плавный ИИ-маршрут между треками'}</h3>
        <p class="sonic-bridge-desc">${IS_EN
          ? 'Specify Point A and Point B (track, artist, or mood). Apple Neural Engine computes a smooth 512-D geodesic SLERP path across tempo, timbre, and atmosphere.'
          : 'Укажите Точку А и Точку Б (трек, артиста или настроение) — Apple Neural Engine построит бесшовную 512-мерную геодезическую траекторию по тембру, темпу и атмосфере.'}</p>
      `}
      <div class="sonic-bridge-endpoints-row">
        <div class="sonic-bridge-endpoint-box">
          <div class="sonic-bridge-endpoint-head">
            <span class="sonic-bridge-endpoint-label">${translateTextToEn('Точка А (откуда)')}</span>
            <button type="button" class="sonic-bridge-use-current-btn" id="btn-bridge-use-current" ${hasCurrentTrack ? '' : 'disabled'}>
              ${translateTextToEn('🎵 Текущий трек')}
            </button>
          </div>
          <input type="text" id="sonic-bridge-from-input" class="sonic-bridge-input"
            value="${escapeHtml(state.sonicBridgeFrom || '')}"
            placeholder="${IS_EN ? 'e.g. Miles Davis — Blue in Green' : 'Напр.: Miles Davis — Blue in Green'}"
            autocomplete="off" autocorrect="off" spellcheck="false">
        </div>

        <button type="button" id="btn-sonic-bridge-swap" class="sonic-bridge-swap-btn" title="${IS_EN ? 'Swap Point A and Point B' : 'Поменять местами А и Б'}">⇄</button>

        <div class="sonic-bridge-endpoint-box">
          <div class="sonic-bridge-endpoint-head">
            <span class="sonic-bridge-endpoint-label">${translateTextToEn('Точка Б (куда)')}</span>
          </div>
          <input type="text" id="sonic-bridge-to-input" class="sonic-bridge-input"
            value="${escapeHtml(state.sonicBridgeTo || '')}"
            placeholder="${IS_EN ? 'e.g. Daft Punk — Veridis Quo' : 'Напр.: Daft Punk — Veridis Quo'}"
            autocomplete="off" autocorrect="off" spellcheck="false">
        </div>
      </div>

      <div class="sonic-bridge-controls-bar">
        <div class="sonic-bridge-steps-wrap">
          <span class="sonic-bridge-steps-label">${translateTextToEn('Длина маршрута:')}</span>
          ${[10, 12, 16].map((n) => `
            <button type="button" class="sonic-bridge-step-pill ${steps === n ? 'active' : ''}" data-step-count="${n}">${n}</button>
          `).join('')}
        </div>
        <div class="sonic-bridge-submit-actions">
          <button type="button" id="btn-sonic-bridge-build" class="btn-sonic-bridge-build">
            <span>🌉 ${translateTextToEn('Построить маршрут')}</span>
          </button>
          <button type="button" id="btn-sonic-bridge-autoplay" class="btn-sonic-bridge-autoplay">
            <span>▶ ${translateTextToEn('Сразу включить')}</span>
          </button>
        </div>
      </div>
      ${examplesHtml}
    `;

    const fromInput = card.querySelector('#sonic-bridge-from-input');
    const toInput = card.querySelector('#sonic-bridge-to-input');
    const useCurrBtn = card.querySelector('#btn-bridge-use-current');
    const swapBtn = card.querySelector('#btn-sonic-bridge-swap');
    const buildBtn = card.querySelector('#btn-sonic-bridge-build');
    const autoPlayBtn = card.querySelector('#btn-sonic-bridge-autoplay');

    if (fromInput) {
      fromInput.addEventListener('input', () => { state.sonicBridgeFrom = fromInput.value; });
      fromInput.addEventListener('keydown', (ev) => {
        if (ev.key === 'Enter') {
          ev.preventDefault();
          if (toInput && !toInput.value.trim()) {
            toInput.focus();
          } else {
            triggerSonicBridgeSearch(false);
          }
        }
      });
    }
    if (toInput) {
      toInput.addEventListener('input', () => { state.sonicBridgeTo = toInput.value; });
      toInput.addEventListener('keydown', (ev) => {
        if (ev.key === 'Enter') {
          ev.preventDefault();
          triggerSonicBridgeSearch(false);
        }
      });
    }
    if (useCurrBtn) {
      useCurrBtn.addEventListener('click', () => {
        if (!state.track || !state.track.name) return;
        triggerHaptic('light');
        const cur = state.track.artist ? `${state.track.artist} — ${state.track.name}` : state.track.name;
        state.sonicBridgeFrom = cur;
        if (fromInput) fromInput.value = cur;
        if (toInput && !toInput.value.trim()) toInput.focus();
      });
    }
    if (swapBtn) {
      swapBtn.addEventListener('click', () => {
        triggerHaptic('light');
        const a = fromInput ? fromInput.value : state.sonicBridgeFrom;
        const b = toInput ? toInput.value : state.sonicBridgeTo;
        state.sonicBridgeFrom = b;
        state.sonicBridgeTo = a;
        if (fromInput) fromInput.value = b;
        if (toInput) toInput.value = a;
      });
    }
    card.querySelectorAll('.sonic-bridge-step-pill').forEach((pill) => {
      pill.addEventListener('click', () => {
        triggerHaptic('light');
        const n = Number(pill.getAttribute('data-step-count')) || 12;
        state.sonicBridgeSteps = n;
        card.querySelectorAll('.sonic-bridge-step-pill').forEach(p => p.classList.toggle('active', Number(p.getAttribute('data-step-count')) === n));
      });
    });
    card.querySelectorAll('.sonic-bridge-example-chip').forEach((chip) => {
      chip.addEventListener('click', () => {
        const idx = Number(chip.getAttribute('data-bridge-idx'));
        const ex = SONIC_BRIDGE_EXAMPLES[idx];
        if (!ex) return;
        triggerHaptic('light');
        state.sonicBridgeFrom = ex.from;
        state.sonicBridgeTo = ex.to;
        if (fromInput) fromInput.value = ex.from;
        if (toInput) toInput.value = ex.to;
        triggerSonicBridgeSearch(false);
      });
    });
    if (buildBtn) {
      buildBtn.addEventListener('click', () => triggerSonicBridgeSearch(false));
    }
    if (autoPlayBtn) {
      autoPlayBtn.addEventListener('click', () => triggerSonicBridgeSearch(true));
    }
    return card;
  }

// === MODULE: 18-sonic-bridge-and-search-exec.js ===
  function renderSonicBridgeBuilder() {
    if (!dom.searchResults) return;
    dom.searchResults.innerHTML = '';
    const wrap = document.createElement('div');
    wrap.className = 'search-placeholder';
    wrap.appendChild(buildSonicBridgeCardElement(false));
    dom.searchResults.appendChild(wrap);
  }

  function openSonicBridgeTab(focusDestination = false) {
    if (!state.aiCuratorEnabled) return;
    if (!isDesktopLayout()) {
      switchMobileView('view-search', true);
    } else {
      switchDesktopTab('search', true, { fromResize: true });
    }
    state.searchScope = 'bridge';
    dom.filterChips.forEach(c => c.classList.toggle('active', c.dataset.scope === 'bridge'));
    if (dom.searchInput) {
      dom.searchInput.placeholder = IS_EN
        ? 'Point A -> Point B (or fill route below)...'
        : 'Точка А -> Точка Б (или заполните маршрут ниже)...';
    }
    renderSonicBridgeBuilder();
    setTimeout(() => {
      const targetId = (focusDestination || state.sonicBridgeFrom) ? 'sonic-bridge-to-input' : 'sonic-bridge-from-input';
      const el = document.getElementById(targetId);
      if (el) el.focus();
    }, 60);
  }

  function triggerSonicBridgeSearch(autoPlay = false) {
    const fromEl = document.getElementById('sonic-bridge-from-input');
    const toEl = document.getElementById('sonic-bridge-to-input');
    const fromQ = String((fromEl ? fromEl.value : state.sonicBridgeFrom) || '').trim();
    const toQ = String((toEl ? toEl.value : state.sonicBridgeTo) || '').trim();
    state.sonicBridgeFrom = fromQ;
    state.sonicBridgeTo = toQ;

    if (!fromQ || !toQ) {
      showToast(IS_EN
        ? 'Specify both Point A and Point B for Sonic Bridge'
        : 'Укажите обе точки маршрута (Точку А и Точку Б)');
      if (!fromQ && fromEl) fromEl.focus();
      else if (!toQ && toEl) toEl.focus();
      return;
    }

    triggerHaptic('medium');
    currentSearchSongs = [];
    currentSearchOffset = 0;
    currentSearchHasMore = false;
    state.isAiCurating = true;
    state.sonicBridgeAutoPlay = Boolean(autoPlay);
    state.aiCurateReqSeq = (state.aiCurateReqSeq || 0) + 1;
    state.lastAiCurateSentAt = Date.now();
    const reqId = state.aiCurateReqSeq;

    if (dom.searchResults) {
      dom.searchResults.innerHTML = '';
      dom.searchResults.appendChild(buildSonicBridgeCardElement(true));
      const loadingEl = document.createElement('div');
      loadingEl.className = 'loading-state';
      loadingEl.textContent = IS_EN
        ? `🌉 Computing 512-D Sonic Bridge: ${fromQ} → ${toQ}...`
        : `🌉 Расчёт 512-D маршрута Sonic Bridge: ${fromQ} → ${toQ}...`;
      dom.searchResults.appendChild(loadingEl);
    }

    const sent = send({
      action: 'build_sonic_bridge',
      request_id: reqId,
      params: {
        from: fromQ,
        to: toQ,
        steps: Number(state.sonicBridgeSteps) || 12,
        country: getActiveStorefront(),
        auto_play: Boolean(autoPlay),
        request_id: reqId
      }
    });
    if (!sent) {
      state.isAiCurating = false;
      state.sonicBridgeAutoPlay = false;
      setUIBusy(false);
      if (dom.searchResults) {
        const loadingEl = dom.searchResults.querySelector('.loading-state');
        if (loadingEl) loadingEl.remove();
        const emptyEl = document.createElement('div');
        emptyEl.className = 'empty-state';
        emptyEl.textContent = IS_EN ? 'No connection to Mac server' : 'Нет соединения с сервером Mac';
        dom.searchResults.appendChild(emptyEl);
      }
      showToast(IS_EN ? 'No connection to Mac server' : 'Нет соединения с сервером Mac');
    }
  }

  function renderSearchPlaceholder() {
    if (!dom.searchResults) return;
    if (!state.aiCuratorEnabled) {
      dom.searchResults.innerHTML = `
        <div class="search-placeholder">
          <div class="search-placeholder-minimal">${translateTextToEn('Введите название песни, альбома, плейлиста или артиста')}</div>
        </div>`;
      return;
    }

    if (state.searchScope === 'bridge') {
      renderSonicBridgeBuilder();
      return;
    }

    const chipsHtml = currentAiPromptsBatch.map((item) => renderAiPromptChipItemHtml(item, false)).join('');

    dom.searchResults.innerHTML = `
      <div class="search-placeholder">
        <div class="ai-curator-landing-card">
          <div class="ai-curator-landing-top">
            <span class="ai-curator-engine-pill">✨ APPLE NEURAL ENGINE • ON-DEVICE AI</span>
            <button type="button" id="btn-refresh-ai-prompts" class="ai-refresh-prompts-btn" title="${translateTextToEn('Сгенерировать другие варианты промптов')}">
              <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
                <polyline points="23 4 23 10 17 10"/>
                <polyline points="1 20 1 14 7 14"/>
                <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/>
              </svg>
              <span>${translateTextToEn('Другие варианты')}</span>
            </button>
          </div>
          <h3 class="ai-curator-landing-title">${translateTextToEn('Умный семантический поиск и Промпт-Куратор')}</h3>
          <p class="ai-curator-landing-desc">${translateTextToEn('Опишите настроение, звуковую сцену, эпоху или инструменты свободным текстом — нативный движок macOS соберёт готовую аудиофильскую очередь из каталога Apple Music.')}</p>
          <div id="ai-pinned-prompts-container">${renderPinnedAiSectionHtml()}</div>
          <div id="ai-main-prompts-grid" class="ai-curator-prompts-grid">
            ${chipsHtml}
          </div>
          <button type="button" id="btn-open-sonic-bridge-cta" class="ai-landing-bridge-cta">
            <div class="ai-landing-bridge-cta-texts">
              <span class="ai-landing-bridge-cta-title">🌉 ${IS_EN ? 'Sonic Bridge: Musical Route A → B' : 'Sonic Bridge: плавный ИИ-маршрут А → Б'}</span>
              <span class="ai-landing-bridge-cta-sub">${IS_EN
                ? 'Build a seamless geodesic transition between any two tracks or artists'
                : 'Бесшовный переход от одного трека или артиста к другому в 512-D пространстве'}</span>
            </div>
            <span class="ai-landing-bridge-cta-arrow">→</span>
          </button>
        </div>
      </div>`;
    bindAiPromptChips();
    const bridgeCta = document.getElementById('btn-open-sonic-bridge-cta');
    if (bridgeCta) {
      bridgeCta.addEventListener('click', () => {
        triggerHaptic('light');
        openSonicBridgeTab(false);
      });
    }
  }

  function bindAiPromptChips() {
    document.querySelectorAll('.ai-prompt-chip').forEach((btn) => {
      if (btn.dataset.boundAiChip === '1') return;
      btn.dataset.boundAiChip = '1';
      btn.addEventListener('click', () => {
        const prompt = btn.getAttribute('data-ai-prompt') || '';
        if (!prompt) return;
        dom.filterChips.forEach(c => c.classList.toggle('active', c.dataset.scope === 'ai'));
        state.searchScope = 'ai';
        dom.searchInput.value = prompt;
        dom.searchInput.placeholder = translateTextToEn('Опишите настроение, сцену или инструменты...');
        dom.btnClearSearch.classList.remove('hidden');
        state.searchQuery = prompt;
        executeSearch(prompt, 'ai');
      });
    });

    document.querySelectorAll('.ai-chip-pin-btn').forEach((pinBtn) => {
      if (pinBtn.dataset.boundAiPin === '1') return;
      pinBtn.dataset.boundAiPin = '1';
      pinBtn.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        const pPrompt = pinBtn.getAttribute('data-pin-prompt') || '';
        const pLabel = pinBtn.getAttribute('data-pin-label') || pPrompt;
        togglePinAiPrompt(pPrompt, pLabel);
      });
    });

    const refreshBtn = document.getElementById('btn-refresh-ai-prompts');
    if (refreshBtn && refreshBtn.dataset.boundRefresh !== '1') {
      refreshBtn.dataset.boundRefresh = '1';
      refreshBtn.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        triggerHaptic('light');
        rotateAiPromptSuggestions();
      });
    }
  }

  // Render fresh randomized AI prompt suggestions immediately on startup
  renderSearchPlaceholder();

  dom.btnClearSearch.addEventListener('click', () => {
    dom.searchInput.value = '';
    dom.btnClearSearch.classList.add('hidden');
    state.searchQuery = '';
    renderSearchPlaceholder();
  });

  dom.filterChips.forEach(chip => {
    chip.addEventListener('click', () => {
      dom.filterChips.forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      state.searchScope = chip.dataset.scope;
      if (dom.searchInput) {
        if (state.searchScope === 'bridge') {
          dom.searchInput.placeholder = IS_EN
            ? 'Point A -> Point B (or fill route below)...'
            : 'Точка А -> Точка Б (или заполните маршрут ниже)...';
        } else {
          dom.searchInput.placeholder = translateTextToEn(
            state.searchScope === 'ai'
              ? 'Опишите настроение, сцену или инструменты...'
              : 'Поиск в Apple Music...'
          );
        }
      }
      if (state.searchScope === 'bridge') {
        renderSonicBridgeBuilder();
        return;
      }
      if (state.searchQuery) {
        executeSearch(state.searchQuery, state.searchScope);
      } else {
        renderSearchPlaceholder();
      }
    });
  });

  let currentSearchSongs = [];
  let currentSearchOffset = 0;
  let currentSearchHasMore = false;
  let isSearchLoadingMore = false;

  function executeSearch(query, scope, offset = 0) {
    if (scope === 'bridge') {
      const arrowParts = String(query || '').split(/\s*(?:->|→|—>)\s*/);
      if (arrowParts.length >= 2 && arrowParts[0].trim() && arrowParts[1].trim()) {
        state.sonicBridgeFrom = arrowParts[0].trim();
        state.sonicBridgeTo = arrowParts.slice(1).join(' ').trim();
        triggerSonicBridgeSearch(false);
      } else {
        renderSonicBridgeBuilder();
      }
      return;
    }
    if (scope === 'ai') {
      currentSearchSongs = [];
      currentSearchOffset = 0;
      currentSearchHasMore = false;
      state.isAiCurating = true;
      state.aiCurateReqSeq = (state.aiCurateReqSeq || 0) + 1;
      state.lastAiCurateSentAt = Date.now();
      const reqId = state.aiCurateReqSeq;
      dom.searchResults.innerHTML = `<div class="loading-state">${translateTextToEn('Подбор нативным ИИ (Apple Neural Engine)...')}</div>`;
      const sent = send({
        action: 'ai_curate',
        request_id: reqId,
        params: {
          prompt: query,
          country: getActiveStorefront(),
          request_id: reqId
        }
      });
      if (!sent) {
        state.isAiCurating = false;
        setUIBusy(false);
        if (dom.searchResults) {
          dom.searchResults.innerHTML = `<div class="empty-state">${escapeHtml(IS_EN ? 'No connection to Mac server' : 'Нет соединения с сервером Mac')}</div>`;
        }
        showToast(IS_EN ? 'No connection to Mac server' : 'Нет соединения с сервером Mac');
      }
      return;
    }

    if (offset === 0) {
      if (state.aiCurateTimeoutId) {
        clearTimeout(state.aiCurateTimeoutId);
        state.aiCurateTimeoutId = null;
      }
      state.isAiCurating = false;
      state.aiCurateReqSeq = (state.aiCurateReqSeq || 0) + 1;
      currentSearchSongs = [];
      currentSearchOffset = 0;
      currentSearchHasMore = false;
      dom.searchResults.innerHTML = '<div class="loading-state">Поиск в каталоге Apple Music...</div>';
    } else {
      isSearchLoadingMore = true;
      const btn = document.getElementById('btn-search-load-more');
      if (btn) {
        btn.disabled = true;
        btn.textContent = 'Загрузка...';
      }
    }
    state.searchReqSeq = (state.searchReqSeq || 0) + 1;
    const searchReqId = state.searchReqSeq;
    send({
      action: 'search',
      request_id: searchReqId,
      params: {
        query: query,
        country: getActiveStorefront(),
        locale: state.userLocale || undefined,
        scope: scope,
        limit: 25,
        offset: offset,
        request_id: searchReqId
      }
    });
  }

  function createTrackRow(s) {
    const row = document.createElement('div');
    row.className = 'track-row';
    const artSrc = appendDeviceIdToUrl(s.artwork_url || s.artwork || getArtworkSrc(s) || 'apple-touch-icon.svg');
    const isLocal = Boolean(s.is_local || s.isLocal);
    const localBadge = isLocal ? '<span class="badge-library">МЕДИАТЕКА</span>' : '';

    row.innerHTML = `
      <img class="track-thumb" src="${escapeHtml(artSrc)}" alt="" loading="lazy" data-fallback-icon="apple-touch-icon.svg">
      <div class="track-details">
        <div class="track-row-title-wrap">
          <span class="track-row-title">${escapeHtml(s.name || s.trackName || '')}</span>
          ${localBadge}
        </div>
        <span class="track-row-artist">${escapeHtml(s.artist || s.artistName || '')}</span>
      </div>
    `;

    row.appendChild(createTrackRowActionButtons({
      ...s,
      name: s.name || s.trackName || '',
      artist: s.artist || s.artistName || '',
      album: s.album || s.collectionName || '',
      artwork: s.artwork_url || s.artwork || '',
      is_local: isLocal
    }, { showDirectDelete: isLocal }));

    row.addEventListener('click', () => {
      setUIBusy(true, 'Запуск трека...');
      if (currentSearchSongs && currentSearchSongs.length > 0) {
        const sId = `${s.id || s.trackId || ''}`;
        const idx = currentSearchSongs.findIndex(x => (sId && `${x.id || x.trackId || ''}` === sId) || ((x.name || x.trackName) === (s.name || s.trackName) && (x.artist || x.artistName) === (s.artist || s.artistName)));
        if (idx !== -1) {
          playSearchResultsList(currentSearchSongs, false, idx);
          return;
        }
      }
      send({
        action: 'play_cloud',
        params: {
          numeric_id: s.numeric_id || s.numericId || undefined,
          id: `${s.id || s.trackId || ''}`,
          name: s.name || s.trackName || '',
          artist: s.artist || s.artistName || '',
          url: s.url || s.trackViewUrl || '',
          artwork: s.artwork_url || s.artwork || ''
        }
      });
    });
    return row;
  }

  function createSonicBridgeTrackRow(s, stepIdx, totalSteps) {
    const row = document.createElement('div');
    row.className = 'track-row sonic-bridge-track-row';
    const artSrc = appendDeviceIdToUrl(s.artwork_url || s.artwork || getArtworkSrc(s) || 'apple-touch-icon.svg');
    const isLocal = Boolean(s.is_local || s.isLocal);
    const localBadge = isLocal ? '<span class="badge-library">МЕДИАТЕКА</span>' : '';
    const pct = s.bridge_progress !== undefined
      ? Number(s.bridge_progress)
      : (totalSteps > 1 ? Math.round((stepIdx / (totalSteps - 1)) * 100) : 0);
    let stageLabel = `${pct}%`;
    if (stepIdx === 0) {
      stageLabel = IS_EN ? '0% • Origin A' : '0% • Точка А';
    } else if (stepIdx === totalSteps - 1) {
      stageLabel = IS_EN ? '100% • Dest B' : '100% • Точка Б';
    } else if (Math.abs(pct - 50) <= 7) {
      stageLabel = IS_EN ? `${pct}% • Midpoint` : `${pct}% • Экватор`;
    }

    row.innerHTML = `
      <span class="sonic-bridge-step-num">${stepIdx + 1}</span>
      <img class="track-thumb" src="${escapeHtml(artSrc)}" alt="" loading="lazy" data-fallback-icon="apple-touch-icon.svg">
      <div class="track-details">
        <div class="track-row-title-wrap">
          <span class="track-row-title">${escapeHtml(s.name || s.trackName || '')}</span>
          ${localBadge}
        </div>
        <span class="track-row-artist">${escapeHtml(s.artist || s.artistName || '')}</span>
      </div>
      <span class="bridge-progress-pill">${escapeHtml(stageLabel)}</span>
    `;

    row.addEventListener('click', () => {
      setUIBusy(true, IS_EN ? 'Starting Sonic Bridge...' : 'Запуск маршрута Sonic Bridge...');
      if (currentSearchSongs && currentSearchSongs.length > 0) {
        playSearchResultsList(currentSearchSongs, false, stepIdx, {
          queueName: state.activeAiCuratedTitle || '🌉 Sonic Bridge'
        });
        return;
      }
      send({
        action: 'play_cloud',
        params: {
          numeric_id: s.numeric_id || s.numericId || undefined,
          id: `${s.id || s.trackId || ''}`,
          name: s.name || s.trackName || '',
          artist: s.artist || s.artistName || '',
          url: s.url || s.trackViewUrl || '',
          artwork: s.artwork_url || s.artwork || ''
        }
      });
    });
    return row;
  }

  function updateSonicBridgeResults(data) {
    const respReqId = data && data.request_id;
    if (respReqId !== undefined && respReqId !== null && state.aiCurateReqSeq && Number(respReqId) !== Number(state.aiCurateReqSeq)) {
      return;
    }
    if (state.aiCurateTimeoutId) {
      clearTimeout(state.aiCurateTimeoutId);
      state.aiCurateTimeoutId = null;
    }
    state.isAiCurating = false;
    setUIBusy(false);

    if (!data || typeof data !== 'object' || data.status === 'disabled' || data.status === 'error' || data.error) {
      state.sonicBridgeAutoPlay = false;
      const infoMsg = translateTextToEn(String(
        (data && (data.message || data.error)) ||
        (data && data.status === 'disabled'
          ? 'Нативные функции ИИ отключены в настройках Mac'
          : 'Не удалось построить маршрут Sonic Bridge')
      ));
      showToast(infoMsg);
      if (dom.searchResults) {
        dom.searchResults.innerHTML = '';
        if (state.searchScope === 'bridge') {
          dom.searchResults.appendChild(buildSonicBridgeCardElement(true));
        }
        const emptyEl = document.createElement('div');
        emptyEl.className = 'empty-state';
        emptyEl.textContent = infoMsg;
        dom.searchResults.appendChild(emptyEl);
      }
      return;
    }

    const songs = Array.isArray(data.songs) ? data.songs : [];
    const title = data.title || `${state.sonicBridgeFrom} → ${state.sonicBridgeTo}`;
    const subtitle = data.subtitle || '';
    const engine = data.engine || 'Sonic Bridge • 512-D Geodesic SLERP';
    const tags = Array.isArray(data.tags) ? data.tags : [];
    const shouldAutoPlay = Boolean(data.auto_play || state.sonicBridgeAutoPlay);
    state.sonicBridgeAutoPlay = false;

    if (data.from) state.sonicBridgeFrom = String(data.from);
    if (data.to) state.sonicBridgeTo = String(data.to);
    state.activeAiCuratedTitle = title.startsWith('🌉') ? title : `🌉 ${title}`;

    if (shouldAutoPlay && songs.length > 0) {
      showToast(state.activeAiCuratedTitle);
      playSearchResultsList([...songs], false, 0, {
        queueName: state.activeAiCuratedTitle,
        query: ''
      });
    } else if (songs.length === 0) {
      showToast(IS_EN ? 'No bridge tracks found in catalog' : 'Не удалось найти треки для маршрута в каталоге');
    }

    currentSearchSongs = [...songs];
    currentSearchOffset = songs.length;
    currentSearchHasMore = false;

    if (!dom.searchResults) return;
    dom.searchResults.innerHTML = '';

    // 1. Compact editable Sonic Bridge Route Builder
    dom.searchResults.appendChild(buildSonicBridgeCardElement(true));

    if (songs.length === 0) {
      const emptyEl = document.createElement('div');
      emptyEl.className = 'empty-state';
      emptyEl.textContent = IS_EN ? 'No tracks found for this route' : 'Треки для маршрута не найдены';
      dom.searchResults.appendChild(emptyEl);
      return;
    }

    // 2. Hero Summary Card
    const heroCard = document.createElement('div');
    heroCard.className = 'ai-curated-session-card';
    const tagsHtml = tags.map(t => `<span class="ai-curated-tag">${escapeHtml(String(t))}</span>`).join('');
    heroCard.innerHTML = `
      <div class="ai-curated-header-top">
        <span class="ai-curator-engine-pill">🌉 ${escapeHtml(engine)}</span>
      </div>
      <h3 class="ai-curated-title">${escapeHtml(title)}</h3>
      ${subtitle ? `<p class="ai-curated-subtitle">${escapeHtml(subtitle)}</p>` : ''}
      ${tagsHtml ? `<div class="ai-curated-tags">${tagsHtml}</div>` : ''}
      <div class="ai-curated-actions">
        <button type="button" class="btn-search-action btn-search-play-all" id="btn-sonic-bridge-play-all">
          <svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor">
            <polygon points="6 3 20 12 6 21 6 3"/>
          </svg>
          <span>${translateTextToEn('Запустить маршрут')}</span>
        </button>
        <button type="button" class="btn-search-action" id="btn-ai-curated-save">
          <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.2">
            <line x1="12" y1="5" x2="12" y2="19"/>
            <line x1="5" y1="12" x2="19" y2="12"/>
          </svg>
          <span id="btn-ai-curated-save-text">${translateTextToEn('В плейлисты')}</span>
        </button>
      </div>
    `;
    dom.searchResults.appendChild(heroCard);

    const btnPlayAll = heroCard.querySelector('#btn-sonic-bridge-play-all');
    const btnSave = heroCard.querySelector('#btn-ai-curated-save');
    const btnSaveText = heroCard.querySelector('#btn-ai-curated-save-text');
    dom.btnAiCuratedSave = btnSave;
    dom.btnAiCuratedSaveText = btnSaveText;

    if (btnPlayAll) {
      btnPlayAll.addEventListener('click', () => {
        playSearchResultsList([...songs], false, 0, {
          queueName: state.activeAiCuratedTitle,
          query: ''
        });
      });
    }
    if (btnSave) {
      btnSave.addEventListener('click', () => {
        state.lastLibraryAddTarget = 'ai';
        btnSave.disabled = true;
        if (btnSaveText) btnSaveText.textContent = translateTextToEn('Добавление...');
        send({
          action: 'add_playlist_to_library',
          params: {
            name: state.activeAiCuratedTitle,
            tracks: songs
          }
        });
      });
    }

    // 3. Geodesic Trajectory Track List
    const heading = document.createElement('h3');
    heading.className = 'search-section-title';
    heading.textContent = translateTextToEn('МАРШРУТ ПЕРЕХОДА');
    dom.searchResults.appendChild(heading);

    const list = document.createElement('div');
    list.id = 'search-songs-list';
    list.className = 'track-list';
    songs.forEach((s, idx) => {
      list.appendChild(createSonicBridgeTrackRow(s, idx, songs.length));
    });
    dom.searchResults.appendChild(list);
  }

// === MODULE: 19-ai-curated-and-search-results.js ===
  function updateAiCuratedResults(data, type = '') {
    const respReqId = data && data.request_id;
    if (respReqId !== undefined && respReqId !== null && state.aiCurateReqSeq && Number(respReqId) !== Number(state.aiCurateReqSeq)) {
      return;
    }
    if (state.aiCurateTimeoutId) {
      clearTimeout(state.aiCurateTimeoutId);
      state.aiCurateTimeoutId = null;
    }
    state.isAiCurating = false;
    const isSearchViewActive = isDesktopLayout()
      ? (state.desktopActiveTab === 'search')
      : (state.activeView === 'view-search' || state.activeMobileView === 'search');
    if (!data || typeof data !== 'object') {
      state.pendingStandbyAiAutoPlay = false;
      setUIBusy(false);
      if (isSearchViewActive && dom.searchResults) {
        dom.searchResults.innerHTML = '<div class="empty-state">Ничего не найдено</div>';
      }
      return;
    }

    const songs = data.songs || [];
    const albums = data.albums || [];
    const title = data.title || (IS_EN ? 'AI Sonic Selection' : 'AI-Подборка');
    const subtitle = data.subtitle || '';
    const engine = data.engine || 'Apple Neural Engine • NaturalLanguage 512-D';
    const tags = Array.isArray(data.tags) ? data.tags : [];
    const shouldAutoPlay = Boolean(data.auto_play || state.pendingStandbyAiAutoPlay);
    if (!shouldAutoPlay && state.searchScope === 'ai' && data.prompt && state.searchQuery) {
      const respPrompt = String(data.prompt).trim().toLowerCase();
      const currQuery = String(state.searchQuery).trim().toLowerCase();
      if (respPrompt && currQuery && respPrompt !== currQuery) {
        return;
      }
    }
    state.pendingStandbyAiAutoPlay = false;
    const curatorPrompt = String(data.prompt || state.searchQuery || title).trim();
    state.activeAiCuratedTitle = `✨ ${title}`;
    state.activeAiCuratedPrompt = curatorPrompt;

    if (shouldAutoPlay && songs.length > 0) {
      showToast(`✨ ${title}`);
      playSearchResultsList([...songs], false, 0, {
        queueName: `✨ ${title}`,
        query: '',
        curatorPrompt: curatorPrompt
      });
    } else if (shouldAutoPlay && songs.length === 0) {
      setUIBusy(false);
      showToast(IS_EN ? 'No matching tracks found' : 'Не удалось подобрать треки по запросу');
    }

    const hasOpenSearchResults = Boolean(
      dom.searchResults &&
      dom.searchResults.children.length > 0 &&
      !dom.searchResults.querySelector('.search-placeholder')
    );
    if ((shouldAutoPlay || type === 'play_ai_track_vibe' || type === 'ai_curate_from_track') && (!isSearchViewActive || (state.searchScope !== 'ai' && hasOpenSearchResults))) {
      return;
    }

    currentSearchSongs = [...songs];
    currentSearchOffset = songs.length;
    currentSearchHasMore = false;

    dom.searchResults.innerHTML = '';

    // 1. Render AI Curated Session Hero Card
    const heroCard = document.createElement('div');
    heroCard.className = 'ai-curated-session-card';

    const tagsHtml = tags.map(t => `<span class="ai-curated-tag">${escapeHtml(String(t))}</span>`).join('');
    const isHeroPinned = isPromptPinnedClient(curatorPrompt);

    heroCard.innerHTML = `
      <div class="ai-curated-header-top">
        <span class="ai-curator-engine-pill">✨ ${escapeHtml(engine)}</span>
      </div>
      <h3 class="ai-curated-title">${escapeHtml(title)}</h3>
      ${subtitle ? `<p class="ai-curated-subtitle">${escapeHtml(subtitle)}</p>` : ''}
      ${tagsHtml ? `<div class="ai-curated-tags">${tagsHtml}</div>` : ''}
      <div class="ai-curated-actions">
        <button type="button" class="btn-search-action btn-search-play-all" id="btn-ai-curated-play">
          <svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor">
            <polygon points="6 3 20 12 6 21 6 3"/>
          </svg>
          <span>${translateTextToEn('Слушать подборку')}</span>
        </button>
        <button type="button" class="btn-search-action btn-search-shuffle" id="btn-ai-curated-shuffle">
          <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2">
            <polyline points="16 3 21 3 21 8"/>
            <line x1="4" y1="20" x2="21" y2="3"/>
            <polyline points="21 16 21 21 16 21"/>
            <line x1="15" y1="15" x2="21" y2="21"/>
            <line x1="4" y1="4" x2="9" y2="9"/>
          </svg>
          <span>${translateTextToEn('Перемешать')}</span>
        </button>
        <button type="button" class="btn-search-action ${isHeroPinned ? 'active' : ''}" id="btn-ai-curated-pin" data-pin-prompt="${escapeHtml(curatorPrompt)}" data-pin-label="${escapeHtml(title)}">
          <span id="btn-ai-curated-pin-text">${translateTextToEn(isHeroPinned ? '★ В избранном' : '☆ Закрепить вайб')}</span>
        </button>
        <button type="button" class="btn-search-action" id="btn-ai-curated-save">
          <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.2">
            <line x1="12" y1="5" x2="12" y2="19"/>
            <line x1="5" y1="12" x2="19" y2="12"/>
          </svg>
          <span id="btn-ai-curated-save-text">${translateTextToEn('В плейлисты')}</span>
        </button>
      </div>
    `;
    dom.searchResults.appendChild(heroCard);

    const btnPlay = heroCard.querySelector('#btn-ai-curated-play');
    const btnShuffle = heroCard.querySelector('#btn-ai-curated-shuffle');
    const btnPin = heroCard.querySelector('#btn-ai-curated-pin');
    const btnSave = heroCard.querySelector('#btn-ai-curated-save');
    const btnSaveText = heroCard.querySelector('#btn-ai-curated-save-text');
    dom.btnAiCuratedSave = btnSave;
    dom.btnAiCuratedSaveText = btnSaveText;

    if (btnPlay && songs.length > 0) {
      btnPlay.addEventListener('click', () => {
        playSearchResultsList([...songs], false, 0, {
          queueName: `✨ ${title}`,
          query: '',
          curatorPrompt: curatorPrompt
        });
      });
    }
    if (btnShuffle && songs.length > 0) {
      btnShuffle.addEventListener('click', () => {
        playSearchResultsList([...songs], true, null, {
          queueName: `✨ ${title}`,
          query: '',
          curatorPrompt: curatorPrompt
        });
      });
    }
    if (btnPin && curatorPrompt) {
      btnPin.addEventListener('click', () => {
        togglePinAiPrompt(curatorPrompt, `✨ ${title}`);
      });
    }
    if (btnSave && songs.length > 0) {
      btnSave.addEventListener('click', () => {
        state.lastLibraryAddTarget = 'ai';
        btnSave.disabled = true;
        if (btnSaveText) btnSaveText.textContent = translateTextToEn('Добавление...');
        send({
          action: 'add_playlist_to_library',
          params: {
            name: `✨ ${title}`,
            tracks: songs
          }
        });
      });
    }

    // 2. Render Curated Tracks
    if (songs.length > 0) {
      const heading = document.createElement('h3');
      heading.className = 'search-section-title';
      heading.textContent = translateTextToEn('ПЕСНИ ПОДБОРКИ');
      dom.searchResults.appendChild(heading);

      const list = document.createElement('div');
      list.id = 'search-songs-list';
      list.className = 'track-list';
      songs.forEach(s => {
        list.appendChild(createTrackRow(s));
      });
      dom.searchResults.appendChild(list);
    }

    // 3. Render Recommended Albums
    if (albums.length > 0) {
      const heading = document.createElement('h3');
      heading.className = 'search-section-title';
      heading.textContent = translateTextToEn('РЕКОМЕНДОВАННЫЕ АЛЬБОМЫ');
      dom.searchResults.appendChild(heading);

      const grid = document.createElement('div');
      grid.className = 'playlists-grid';
      albums.forEach(alb => {
        const card = document.createElement('div');
        card.className = 'playlist-card';
        const art = alb.artwork_url || alb.artwork || 'apple-touch-icon.svg';

        card.innerHTML = `
          <img class="playlist-card-art" src="${escapeHtml(art)}" alt="" loading="lazy">
          <span class="playlist-card-title">${escapeHtml(alb.name || alb.collectionName || '')}</span>
          <span class="playlist-card-count">${escapeHtml(alb.artist || alb.artistName || '')}</span>
        `;

        card.addEventListener('click', () => {
          openAlbumDetail({
            id: `${alb.id || alb.collectionId || ''}`,
            name: alb.name || alb.collectionName || '',
            artist: alb.artist || alb.artistName || '',
            artwork: art,
            url: alb.url || alb.collectionViewUrl || ''
          }, 'search');
        });

        grid.appendChild(card);
      });
      dom.searchResults.appendChild(grid);
    }
  }

  function updateSearchResults(data) {
    const respReqId = data && data.request_id;
    if (respReqId !== undefined && respReqId !== null && state.searchReqSeq && Number(respReqId) !== Number(state.searchReqSeq)) {
      return;
    }
    if (state.isAiCurating || state.searchScope === 'ai') {
      return;
    }
    if (!data) {
      dom.searchResults.innerHTML = '<div class="empty-state">Ничего не найдено</div>';
      return;
    }

    const songs = data.songs || [];
    const albums = data.albums || [];
    const artists = data.artists || [];
    const playlists = data.playlists || [];
    const offset = data.offset || 0;
    const hasMore = Boolean(data.has_more);

    // If this is a page append (offset > 0)
    if (offset > 0) {
      isSearchLoadingMore = false;
      const songList = document.getElementById('search-songs-list');
      if (songList && songs.length > 0) {
        currentSearchSongs.push(...songs);
        songs.forEach(s => {
          songList.appendChild(createTrackRow(s));
        });
        // Append to active AMR queue if currently playing search results
        const curQPl = String((state.queue && state.queue.playlist) || '');
        const isPlayingSearch = Boolean(
          state.queue &&
          (curQPl === 'Результаты поиска' || curQPl === 'Search Results' || curQPl === 'Очередь AMR' || curQPl.startsWith('Поиск: ') || curQPl.startsWith('Search: '))
        );
        if (isPlayingSearch) {
          const formatted = songs.map(s => ({
            id: `${s.id || s.trackId || ''}`,
            numeric_id: s.numeric_id || s.numericId || undefined,
            name: s.name || s.trackName || '',
            artist: s.artist || s.artistName || '',
            album: s.album || s.collectionName || '',
            url: s.url || s.trackViewUrl || '',
            artwork_url: s.artwork_url || s.artwork || '',
            is_local: Boolean(s.is_local || s.isLocal)
          }));
          send({
            action: 'append_search_results',
            params: { tracks: formatted }
          });
        }
      }
      const existingBtn = document.getElementById('btn-search-load-more');
      if (existingBtn) {
        if (hasMore) {
          existingBtn.disabled = false;
          existingBtn.textContent = 'Загрузить ещё';
        } else {
          existingBtn.remove();
        }
      }
      return;
    }

    // Initial search result (offset === 0)
    state.activeAiCuratedTitle = '';
    state.activeAiCuratedPrompt = '';
    currentSearchSongs = [...songs];
    currentSearchOffset = songs.length;
    currentSearchHasMore = hasMore;

    if (songs.length === 0 && albums.length === 0 && artists.length === 0 && playlists.length === 0) {
      dom.searchResults.innerHTML = '<div class="empty-state">Ничего не найдено</div>';
      return;
    }

    dom.searchResults.innerHTML = '';

    // Offer 1-click AI Sonic Curation when user types a multi-word descriptive query
    if (state.aiCuratorEnabled && state.searchScope !== 'ai' && state.searchQuery && state.searchQuery.trim().split(/\s+/).length >= 2) {
      const aiBanner = document.createElement('div');
      aiBanner.className = 'ai-suggest-banner';
      aiBanner.innerHTML = `
        <span class="ai-suggest-banner-text">✨ ${escapeHtml(IS_EN ? `Curate an AI sonic session for «${state.searchQuery}»` : `Собрать AI-подборку по настроению «${state.searchQuery}»`)}</span>
        <span class="ai-suggest-banner-cta">${translateTextToEn('Собрать AI-подборку')} ›</span>
      `;
      aiBanner.addEventListener('click', () => {
        dom.filterChips.forEach(c => c.classList.toggle('active', c.dataset.scope === 'ai'));
        state.searchScope = 'ai';
        executeSearch(state.searchQuery, 'ai');
      });
      dom.searchResults.appendChild(aiBanner);
    }

    // Render Songs
    if (songs.length > 0 && (state.searchScope === 'all' || state.searchScope === 'songs')) {
      const headerRow = document.createElement('div');
      headerRow.className = 'search-header-row';

      const heading = document.createElement('h3');
      heading.className = 'search-section-title';
      heading.textContent = 'ПЕСНИ';
      headerRow.appendChild(heading);

      const actionsBar = document.createElement('div');
      actionsBar.className = 'search-actions-bar';

      const btnPlayAll = document.createElement('button');
      btnPlayAll.className = 'btn-search-action btn-search-play-all';
      btnPlayAll.type = 'button';
      btnPlayAll.innerHTML = `
        <svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor">
          <polygon points="6 3 20 12 6 21 6 3"/>
        </svg>
        <span>Слушать всё</span>
      `;
      btnPlayAll.addEventListener('click', () => {
        playSearchResultsList([...currentSearchSongs], false);
      });

      const btnShuffle = document.createElement('button');
      btnShuffle.className = 'btn-search-action btn-search-shuffle';
      btnShuffle.type = 'button';
      btnShuffle.innerHTML = `
        <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2">
          <polyline points="16 3 21 3 21 8"/>
          <line x1="4" y1="20" x2="21" y2="3"/>
          <polyline points="21 16 21 21 16 21"/>
          <line x1="15" y1="15" x2="21" y2="21"/>
          <line x1="4" y1="4" x2="9" y2="9"/>
        </svg>
        <span>Перемешать</span>
      `;
      btnShuffle.addEventListener('click', () => {
        playSearchResultsList([...currentSearchSongs], true);
      });

      actionsBar.appendChild(btnPlayAll);
      actionsBar.appendChild(btnShuffle);
      headerRow.appendChild(actionsBar);
      dom.searchResults.appendChild(headerRow);

      const list = document.createElement('div');
      list.id = 'search-songs-list';
      list.className = 'track-list';
      songs.forEach(s => {
        list.appendChild(createTrackRow(s));
      });
      dom.searchResults.appendChild(list);

      if (hasMore) {
        const btnLoadMore = document.createElement('button');
        btnLoadMore.id = 'btn-search-load-more';
        btnLoadMore.className = 'btn-search-load-more';
        btnLoadMore.type = 'button';
        btnLoadMore.textContent = 'Загрузить ещё';
        btnLoadMore.addEventListener('click', () => {
          executeSearch(state.searchQuery, state.searchScope, currentSearchSongs.length);
        });
        dom.searchResults.appendChild(btnLoadMore);
      }
    }

    // Render Albums
    if (albums.length > 0 && (state.searchScope === 'all' || state.searchScope === 'albums')) {
      const heading = document.createElement('h3');
      heading.className = 'search-section-title';
      heading.textContent = 'АЛЬБОМЫ';
      dom.searchResults.appendChild(heading);

      const grid = document.createElement('div');
      grid.className = 'playlists-grid';
      albums.forEach(alb => {
        const card = document.createElement('div');
        card.className = 'playlist-card';
        const art = alb.artwork_url || alb.artwork || 'apple-touch-icon.svg';

        card.innerHTML = `
          <img class="playlist-card-art" src="${escapeHtml(art)}" alt="" loading="lazy">
          <span class="playlist-card-title">${escapeHtml(alb.name || alb.collectionName || '')}</span>
          <span class="playlist-card-count">${escapeHtml(alb.artist || alb.artistName || '')}</span>
        `;

        card.addEventListener('click', () => {
          openAlbumDetail({
            id: `${alb.id || alb.collectionId || ''}`,
            name: alb.name || alb.collectionName || '',
            artist: alb.artist || alb.artistName || '',
            artwork: art,
            url: alb.url || alb.collectionViewUrl || ''
          }, 'search');
        });

        grid.appendChild(card);
      });
      dom.searchResults.appendChild(grid);
    }

    // Render Playlists
    if (playlists.length > 0 && (state.searchScope === 'all' || state.searchScope === 'playlists')) {
      const heading = document.createElement('h3');
      heading.className = 'search-section-title';
      heading.textContent = 'ПЛЕЙЛИСТЫ';
      dom.searchResults.appendChild(heading);

      const grid = document.createElement('div');
      grid.className = 'playlists-grid';
      playlists.forEach(pl => {
        const card = document.createElement('div');
        card.className = 'playlist-card';
        const art = appendDeviceIdToUrl(pl.artwork_url || pl.artwork || 'apple-touch-icon.svg');
        const plName = pl.name || 'Плейлист';
        const baseSub = pl.curator_name || pl.curator || pl.subtitle || 'Apple Music';
        const matchedLocal = findMatchingLocalPlaylist(plName, pl.id || '', 0, pl.catalog_id || '');
        const isInLib = Boolean(pl.in_library || pl.is_local || matchedLocal);
        const displaySub = isInLib
          ? `✓ ${IS_EN ? 'In Library' : 'В медиатеке'} • ${baseSub}`
          : baseSub;
        card._searchPlaylistItem = pl;
        card._searchPlaylistBaseSub = baseSub;

        card.innerHTML = `
          <div class="media-card-art-wrap">
            <img class="playlist-card-art" src="${escapeHtml(art)}" alt="" loading="lazy" data-fallback-icon="apple-touch-icon.svg">
          </div>
          <span class="playlist-card-title">${escapeHtml(plName)}</span>
          <span class="playlist-card-count">${escapeHtml(displaySub)}</span>
        `;

        card.addEventListener('click', () => {
          const liveLocal = findMatchingLocalPlaylist(plName, pl.id || '', 0, pl.catalog_id || '');
          const liveInLib = Boolean(liveLocal) || Boolean(pl.in_library || pl.is_local);
          openPlaylistDetail({
            id: pl.id || '',
            catalog_id: pl.catalog_id || (String(pl.id || '').toLowerCase().startsWith('pl.') ? pl.id : ''),
            library_id: pl.library_id || (liveLocal && liveLocal.id) || '',
            local_name: pl.local_name || (liveLocal && liveLocal.name) || '',
            alternate_names: pl.alternate_names || (liveLocal && liveLocal.alternate_names) || [],
            name: plName,
            url: pl.url || '',
            artwork_url: art,
            track_count: Number(pl.track_count || pl.trackCount || (liveLocal && (liveLocal.track_count || liveLocal.trackCount)) || 0),
            curator_name: baseSub,
            is_local: liveInLib,
            in_library: liveInLib
          }, 'search');
        });

        grid.appendChild(card);
      });
      dom.searchResults.appendChild(grid);
    }

    // Render Artists
    if (artists.length > 0 && (state.searchScope === 'all' || state.searchScope === 'artists')) {
      const heading = document.createElement('h3');
      heading.className = 'search-section-title';
      heading.textContent = 'ИСПОЛНИТЕЛИ';
      dom.searchResults.appendChild(heading);

      const list = document.createElement('div');
      list.className = 'track-list';
      artists.forEach(art => {
        const row = document.createElement('div');
        row.className = 'track-row artist-row';
        const artistName = art.name || art.artistName || '';
        const genre = art.genre || 'Исполнитель';

        row.innerHTML = `
          <div class="track-thumb artist-thumb">
            <svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor">
              <path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/>
            </svg>
          </div>
          <div class="track-details">
            <span class="track-row-title">${escapeHtml(artistName)}</span>
            <span class="track-row-artist">${escapeHtml(genre)}</span>
          </div>
          <button class="btn-chart-play" type="button" aria-label="Слушать">
            <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor">
              <polygon points="6 3 20 12 6 21 6 3"/>
            </svg>
          </button>
        `;

        row.addEventListener('click', () => {
          if (!artistName) return;
          // Switch search to artist's songs & load them
          dom.searchInput.value = artistName;
          state.searchQuery = artistName;
          state.searchScope = 'songs';
          dom.filterChips.forEach(c => c.classList.toggle('active', c.dataset.scope === 'songs'));
          dom.btnClearSearch.classList.remove('hidden');
          executeSearch(artistName, 'songs');
        });

        list.appendChild(row);
      });
      dom.searchResults.appendChild(list);
    }
  }

  function syncSearchPlaylistCardsLibraryStatus(targetProbe, inLibrary) {
    if (!dom.searchResults || !targetProbe) return;
    dom.searchResults.querySelectorAll('.playlist-card').forEach(card => {
      const pl = card._searchPlaylistItem;
      if (!pl || !playlistsMatchCrossLocaleClient(pl, targetProbe)) return;
      pl.in_library = Boolean(inLibrary);
      pl.is_local = Boolean(inLibrary);
      const subEl = card.querySelector('.playlist-card-count');
      if (subEl) {
        const baseSub = card._searchPlaylistBaseSub || pl.curator_name || pl.curator || pl.subtitle || 'Apple Music';
        subEl.textContent = inLibrary
          ? `✓ ${IS_EN ? 'In Library' : 'В медиатеке'} • ${baseSub}`
          : baseSub;
      }
    });
  }

  function playSearchResultsList(songs, shuffle, startIndex = null, options = {}) {
    if (!songs || songs.length === 0) return;
    const isAiCurated = Boolean(options.queueName || state.activeAiCuratedTitle);
    const resolvedQuery = String(options.query !== undefined ? options.query : (isAiCurated ? '' : (state.searchQuery || ''))).trim();
    const resolvedQueueName = options.queueName
      || state.activeAiCuratedTitle
      || (resolvedQuery
        ? (IS_EN ? `Search: ${resolvedQuery}` : `Поиск: ${resolvedQuery}`)
        : (IS_EN ? 'Search Results' : 'Результаты поиска'));
    const resolvedCuratorPrompt = options.curatorPrompt !== undefined
      ? options.curatorPrompt
      : (isAiCurated ? (state.activeAiCuratedPrompt || '') : '');
    const hasExplicitStart = Number.isInteger(startIndex) && startIndex >= 0 && startIndex < songs.length;
    const effectiveStartIndex = shuffle ? (hasExplicitStart ? startIndex : -1) : (hasExplicitStart ? startIndex : 0);
    const firstSong = effectiveStartIndex >= 0 ? (songs[effectiveStartIndex] || songs[0]) : songs[0];
    const expectedFirstTitle = firstSong ? (firstSong.name || firstSong.trackName || '') : '';
    optimisticPlay();
    markWaitingForPlayback({
      targetName: resolvedQueueName,
      expectedTrackName: shuffle ? '' : expectedFirstTitle
    });
    const busyText = isAiCurated
      ? (IS_EN ? `Starting «${resolvedQueueName}»...` : `Запуск «${resolvedQueueName}»...`)
      : (shuffle ? 'Перемешивание...' : 'Запуск результатов...');
    setUIBusy(true, busyText);
    const formatted = songs.map(s => ({
      id: `${s.id || s.trackId || ''}`,
      numeric_id: s.numeric_id || s.numericId || undefined,
      name: s.name || s.trackName || '',
      artist: s.artist || s.artistName || '',
      album: s.album || s.collectionName || '',
      duration: Number(s.duration) || (s.trackTimeMillis ? Math.round(s.trackTimeMillis / 1000) : 0),
      url: s.url || s.trackViewUrl || '',
      artwork_url: s.artwork_url || s.artwork || '',
      is_local: Boolean(s.is_local || s.isLocal)
    }));

    send({
      action: 'play_search_results',
      params: {
        tracks: formatted,
        startIndex: effectiveStartIndex,
        pin_start_track: Boolean(!shuffle || hasExplicitStart),
        shuffle: Boolean(shuffle),
        queue_name: resolvedQueueName,
        query: resolvedQuery,
        curator_prompt: resolvedCuratorPrompt
      }
    });

    if (dom.btnPlayPause) {
      dom.btnPlayPause.classList.add('loading-pulse');
      setTimeout(() => dom.btnPlayPause.classList.remove('loading-pulse'), 1200);
    }
  }

// === MODULE: 20-trends-and-animated-plaques.js ===
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

// === MODULE: 21-hero-mixes-and-stations.js ===
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
          title: IS_EN ? 'Discovery Station' : 'Станция открытий',
          sub: IS_EN ? 'New music tailored to your taste' : 'Новые треки под ваш вкус',
          tag: IS_EN ? 'Radio Station' : 'Радиостанция',
          id: '',
          type: 'station',
          url: '',
          artwork: '/assets/stations/CoverDiscovery.png'
        },
        {
          index: 3,
          title: IS_EN ? 'Favorite Songs' : 'Любимые песни',
          sub: IS_EN ? 'Library Playlist' : 'Плейлист медиатеки',
          tag: IS_EN ? 'Library' : 'Медиатека',
          id: 'Любимые песни',
          type: 'playlist',
          url: '',
          artwork: '/api/artwork/playlist?name=%D0%9B%D1%8E%D0%B1%D0%B8%D0%BC%D1%8B%D0%B5%20%D0%BF%D0%B5%D1%81%D0%BD%D0%B8'
        },
        {
          index: 4,
          title: IS_EN ? 'Heavy Rotation Mix' : 'Сейчас на повторе',
          sub: IS_EN ? 'Weekly Mix' : 'Еженедельный микс',
          tag: IS_EN ? 'Made for You' : 'Для вас',
          id: 'Сейчас на повторе',
          type: 'playlist',
          url: '',
          artwork: '/assets/stations/CoverHeavyRotation.svg'
        },
        {
          index: 5,
          title: IS_EN ? 'Random Access Memories' : 'Легенда',
          sub: IS_EN ? 'Daft Punk' : 'Кино',
          tag: IS_EN ? 'Top Album' : 'Топ-альбом',
          id: IS_EN ? '617154241' : '1375628135',
          type: 'album',
          url: IS_EN ? 'https://music.apple.com/album/617154241' : 'https://music.apple.com/album/1375628135',
          artwork: IS_EN
            ? 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/e8/43/5f/e8435f2c-1c7b-58f9-81b8-6f40a21ab8db/886443919266.jpg/600x600bb.jpg'
            : 'https://is1-ssl.mzstatic.com/image/thumb/Music118/v4/c7/99/1e/c7991ed1-bee2-8c46-2e66-81d0b8e7eeb2/cover.jpg/600x600bb.jpg'
        },
        {
          index: 6,
          title: 'Mutter',
          sub: 'Rammstein',
          tag: IS_EN ? 'Top Album' : 'Топ-альбом',
          id: '1440770702',
          type: 'album',
          url: 'https://music.apple.com/album/1440770702',
          artwork: 'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/b8/91/bf/b891bf2e-0658-690a-115f-c2ee53f3192e/00602527296685.rgb.jpg/600x600bb.jpg'
        },
        {
          index: 7,
          title: IS_EN ? 'The Dark Side of the Moon' : 'Акустический альбом',
          sub: IS_EN ? 'Pink Floyd' : 'Король и Шут',
          tag: IS_EN ? 'Top Album' : 'Топ-альбом',
          id: IS_EN ? '1065973699' : '1440751918',
          type: 'album',
          url: IS_EN ? 'https://music.apple.com/album/1065973699' : 'https://music.apple.com/album/1440751918',
          artwork: IS_EN
            ? 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/3c/64/73/3c647362-2f0f-2c26-5f20-ef44780d4094/886445635829.jpg/600x600bb.jpg'
            : 'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/44/9a/c0/449ac06f-40e1-7c59-bf7b-6ae9be2d7b14/4607062440191.jpg/600x600bb.jpg'
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

      const heroTagText = translateTextToEn(c.tag || '');
      const heroTitleText = c.type === 'album' ? (c.title || '') : translateTextToEn(c.title || '');
      const heroSubText = c.type === 'album' ? (c.sub || '') : translateTextToEn(c.sub || '');

      el.innerHTML = `
        <div class="hero-card-header">
          <span class="hero-tag">${escapeHtml(heroTagText)}</span>
          <span class="hero-title">${escapeHtml(heroTitleText)}</span>
          <span class="hero-sub">${escapeHtml(heroSubText)}</span>
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
      const mName = mix.name || (IS_EN ? 'Mix' : 'Микс');
      const displayMixName = translateTextToEn(mName);
      const art = appendDeviceIdToUrl(mix.artwork || mix.artwork_url || 'apple-touch-icon.svg');
      const curator = translateTextToEn(mix.curator_name || 'Apple Music');
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
        <div class="media-card-title">${escapeHtml(displayMixName)}</div>
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

      const stFallbackTitle = translateTextToEn(st.name || (IS_EN ? 'Radio' : 'Радио'));
      const stDisplayName = translateTextToEn(st.name || (IS_EN ? 'Radio Station' : 'Радиостанция'));
      const stDisplaySub = translateTextToEn(st.subtitle || (isLive ? 'Прямой эфир Apple Music' : 'Персональная станция'));

      const artHtml = animatedPlaque
        ? animatedPlaque
        : (hasImage
          ? `<img class="media-card-art" src="${escapeHtml(st.artwork)}" alt="" loading="lazy" data-fallback-mode="next-flex">
             <div class="media-card-art-fallback" style="display:none; background: ${gradient};">
               ${iconSvg}
               <span class="station-art-fallback-title">${escapeHtml(stFallbackTitle)}</span>
             </div>`
          : `<div class="media-card-art-fallback" style="background: ${gradient};">
               ${iconSvg}
               <span class="station-art-fallback-title">${escapeHtml(stFallbackTitle)}</span>
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
        <span class="media-card-title">${escapeHtml(stDisplayName)}</span>
        <span class="media-card-sub">${escapeHtml(stDisplaySub)}</span>
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

// === MODULE: 22-section-tiles-and-navigation.js ===
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

// === MODULE: 23-gestures-resize-and-motion-video.js ===
  function setupMiniPlayerGestures() {
    const mini = dom.miniPlayer;
    if (!mini) return;

    let startX = 0;
    let startY = 0;
    let deltaX = 0;
    let deltaY = 0;
    let startTime = 0;
    let isTouch = false;

    mini.addEventListener('touchstart', (e) => {
      if (e.target.closest('button')) return;
      if (e.touches.length !== 1) return;
      const t = e.touches[0];
      startX = t.clientX;
      startY = t.clientY;
      deltaX = 0;
      deltaY = 0;
      startTime = Date.now();
      isTouch = true;
    }, { passive: true });

    mini.addEventListener('touchmove', (e) => {
      if (!isTouch || e.touches.length !== 1) return;
      const t = e.touches[0];
      deltaX = t.clientX - startX;
      deltaY = t.clientY - startY;
    }, { passive: true });

    const handleMiniEnd = (e) => {
      if (!isTouch) return;
      isTouch = false;
      const elapsed = Date.now() - startTime;
      const dist = Math.hypot(deltaX, deltaY);

      if (dist > 45) {
        if (Math.abs(deltaX) > Math.abs(deltaY)) {
          ignoreSyntheticClickUntil = Date.now() + 450;
          if (deltaX < -45) {
            // Swipe Left -> Next
            triggerHaptic('medium');
            sendThrottledTransport('next');
            return;
          } else if (deltaX > 45) {
            // Swipe Right -> Previous
            triggerHaptic('medium');
            sendThrottledTransport('previous');
            return;
          }
        } else if (deltaY < -45) {
          // Swipe Up -> Expand Now Playing
          expandNowPlaying();
          return;
        }
      }

      // Single tap without drag expands Now Playing
      if (dist < 10 && elapsed < 350 && !e.target.closest('button')) {
        expandNowPlaying();
      }
    };

    mini.addEventListener('touchend', handleMiniEnd);
    mini.addEventListener('touchcancel', () => { isTouch = false; });
  }

  // Desktop Navigation
  dom.desktopNavButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      triggerHaptic('light');
      const target = btn.dataset.target;
      switchDesktopTab(target);
    });
  });

  function switchDesktopTab(tabName, keepDetailOpen = false, opts = {}) {
    const skipFetch = Boolean(keepDetailOpen || (opts && opts.skipFetch));
    const preserveHomeDrilldown = Boolean(opts && opts.preserveHomeDrilldown);
    if (tabName !== 'search' && dom.searchInput && document.activeElement === dom.searchInput) {
      dom.searchInput.blur();
    }
    state.desktopActiveTab = tabName;

    dom.desktopNavButtons.forEach(b => {
      b.classList.toggle('active', b.dataset.target === tabName);
    });

    const keepRecentOpen = Boolean(preserveHomeDrilldown && (tabName === 'home' || tabName === 'trends') && dom.recentDetailPane && !dom.recentDetailPane.classList.contains('hidden'));
    const keepGridOpen = Boolean(preserveHomeDrilldown && (tabName === 'home' || tabName === 'trends') && dom.sectionGridView && !dom.sectionGridView.classList.contains('hidden'));

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

    if (!keepDetailOpen && tabName !== 'library') {
      showLibraryBrowsePane();
    }

    if (tabName === 'home' || tabName === 'trends') {
      if (keepRecentOpen && dom.recentDetailPane) {
        dom.recentDetailPane.classList.add('active');
      } else if (keepGridOpen && dom.sectionGridView) {
        dom.sectionGridView.classList.add('active');
      } else if (dom.viewHome) {
        dom.viewHome.classList.add('active');
      } else if (dom.viewTrends) {
        dom.viewTrends.classList.add('active');
      }
      if (!skipFetch) loadTrends();
    } else if (tabName === 'playlists') {
      if (dom.viewPlaylists) dom.viewPlaylists.classList.add('active');
      if (!skipFetch) send({ action: 'get_playlists' });
    } else if (tabName === 'queue') {
      dom.viewQueue.classList.add('active');
      if (!skipFetch) send({ action: 'get_queue' });
    } else if (tabName === 'library') {
      dom.viewLibrary.classList.add('active');
      if (!keepDetailOpen) {
        showLibraryBrowsePane();
        switchLibrarySubtab(state.libraryTab || 'recent', false);
        if (!skipFetch && (!state.libraryAlbums || state.libraryAlbums.length === 0)) {
          send({ action: 'get_library_albums' });
        }
      }
    } else if (tabName === 'search') {
      dom.viewSearch.classList.add('active');
      if (!(opts && opts.fromResize) && dom.searchInput) {
        dom.searchInput.focus();
      }
    }
    syncKeyboardFocusClass();
  }

  // HTML escaping utility
  function escapeHtml(str) {
    if (!str) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  // Handle responsive layout changes on resize (debounced; ignores iOS Safari vertical scroll bar shifts)
  let lastViewportWidth = window.innerWidth;
  let wasMobileLayout = window.innerWidth < 768;
  let resizeDebounceTimer = null;

  function handleResize(opts = {}) {
    const forceInitial = Boolean(opts && opts.force);
    if (typeof syncStandaloneShellGeometry === 'function') {
      syncStandaloneShellGeometry();
    }
    const curWidth = window.innerWidth;
    if (typeof syncStandbyLandscapeBodyClass === 'function') {
      syncStandbyLandscapeBodyClass();
    }
    if (!forceInitial && Math.abs(curWidth - lastViewportWidth) < 2) {
      return;
    }
    lastViewportWidth = curWidth;

    syncStandbyAndMotionCoverUI();
    syncActiveMotionVideoTarget();

    const isMobileLayout = !isDesktopLayout();
    const isPlDetailOpen = Boolean(dom.playlistDetailPane && !dom.playlistDetailPane.classList.contains('hidden'));
    const isArtDetailOpen = Boolean(dom.libraryArtistDetailPane && !dom.libraryArtistDetailPane.classList.contains('hidden'));
    const isSectionGridOpen = Boolean(dom.sectionGridView && !dom.sectionGridView.classList.contains('hidden'));
    const isRecentDetailOpen = Boolean(dom.recentDetailPane && !dom.recentDetailPane.classList.contains('hidden'));
    const detailOpen = isPlDetailOpen || isArtDetailOpen || isSectionGridOpen || isRecentDetailOpen;
    const libDetailOpen = isPlDetailOpen || isArtDetailOpen;
    const homeDrilldownOpen = isSectionGridOpen || isRecentDetailOpen;

    if (forceInitial || isMobileLayout !== wasMobileLayout) {
      wasMobileLayout = isMobileLayout;
      if (!isMobileLayout) {
        const targetDesktopTab = libDetailOpen ? 'library' : (homeDrilldownOpen ? 'home' : state.desktopActiveTab);
        switchDesktopTab(targetDesktopTab, libDetailOpen, {
          fromResize: true,
          skipFetch: true,
          preserveHomeDrilldown: homeDrilldownOpen
        });
      } else {
        switchMobileView(state.activeView, true, homeDrilldownOpen);
      }
      if (detailOpen && (!isMobileLayout || state.activeView === 'view-library')) {
        if (libDetailOpen) {
          syncNavHighlightForDetailOrigin(isArtDetailOpen ? 'library-artists' : (state.detailReturnOrigin || 'library'));
        }
      }
    }
  }

  function scheduleDebouncedResize() {
    if (typeof syncStandaloneShellGeometry === 'function') {
      syncStandaloneShellGeometry();
    }
    if (resizeDebounceTimer) clearTimeout(resizeDebounceTimer);
    resizeDebounceTimer = setTimeout(() => {
      resizeDebounceTimer = null;
      handleResize();
    }, 150);
  }
  window.addEventListener('resize', scheduleDebouncedResize, { passive: true });
  window.addEventListener('orientationchange', () => {
    if (typeof syncStandaloneShellGeometry === 'function') {
      syncStandaloneShellGeometry();
    }
    if (resizeDebounceTimer) clearTimeout(resizeDebounceTimer);
    resizeDebounceTimer = setTimeout(() => {
      resizeDebounceTimer = null;
      lastViewportWidth = -1;
      handleResize();
    }, 150);
  }, { passive: true });

  // ==========================================================================
  // StandBy / TV Mode (Motion Covers) & WLED DDP Ambilight Controller
  // ==========================================================================
  let lastMotionQueryKey = '';
  let currentMotionVideoUrl = '';
  const motionArtworkClientCache = new Map();

  function buildMotionAlbumKey(artist, album) {
    const a = (artist || '').trim().toLowerCase();
    const al = (album || '').trim().toLowerCase();
    return al ? `album|${a}|${al}` : '';
  }

  function buildMotionTrackKey(track, artist, album) {
    return `track|${(track || '').trim().toLowerCase()}|${(artist || '').trim().toLowerCase()}|${(album || '').trim().toLowerCase()}`;
  }

  function unloadVideoElement(vid) {
    if (!vid) return;
    vid.onloadeddata = null;
    vid.onerror = null;
    vid.classList.remove('visible');
    vid.classList.add('hidden');
    try {
      vid.pause();
    } catch (_) {}
    if (vid.hasAttribute('src') || vid.currentSrc) {
      vid.removeAttribute('src');
      try {
        vid.load();
      } catch (_) {}
    }
  }

  function isMotionVideoPlaybackAllowed() {
    return Boolean(state.connected && state.playerState === 'playing');
  }

  function syncMotionVideoPlaybackState() {
    const allowPlay = isMotionVideoPlaybackAllowed();
    const tvActive = isStandbyOrLandscapeVisible();
    const activeVid = document.getElementById(tvActive ? 'standby-motion-video' : 'player-motion-video');
    const inactiveVid = document.getElementById(tvActive ? 'player-motion-video' : 'standby-motion-video');
    if (inactiveVid && !inactiveVid.paused) {
      try { inactiveVid.pause(); } catch (_) {}
    }
    if (!activeVid || !activeVid.getAttribute('src') || !activeVid.classList.contains('visible')) return;
    if (allowPlay) {
      if (activeVid.paused) {
        activeVid.play().catch(() => {});
      }
    } else if (!activeVid.paused) {
      try { activeVid.pause(); } catch (_) {}
    }
  }

  function bindAndPlayMotionVideoElement(vid, url) {
    if (!vid || !url) return;
    if (vid.getAttribute('src') === url && vid.classList.contains('visible')) {
      syncMotionVideoPlaybackState();
      return;
    }
    vid.classList.remove('hidden');
    vid.muted = true;
    vid.loop = true;
    vid.playsInline = true;
    vid.onloadeddata = () => {
      vid.classList.add('visible');
      if (isMotionVideoPlaybackAllowed()) {
        vid.play().catch(() => {});
      } else {
        try { vid.pause(); } catch (_) {}
      }
      if (ScreenWakeLockManager.isActive) {
        ScreenWakeLockManager.syncFallbackVideoState();
      }
    };
    vid.onerror = () => {
      unloadVideoElement(vid);
      const sbBadge = document.getElementById('standby-motion-badge');
      if (sbBadge) sbBadge.classList.add('hidden');
      if (ScreenWakeLockManager.isActive) {
        ScreenWakeLockManager.syncFallbackVideoState();
      }
    };
    vid.src = url;
  }

  function syncActiveMotionVideoTarget() {
    const pVid = document.getElementById('player-motion-video');
    const sbVid = document.getElementById('standby-motion-video');
    const sbBadge = document.getElementById('standby-motion-badge');
    if (!currentMotionVideoUrl) {
      unloadVideoElement(pVid);
      unloadVideoElement(sbVid);
      if (sbBadge) sbBadge.classList.add('hidden');
      return;
    }
    const tvActive = isStandbyOrLandscapeVisible();
    if (tvActive) {
      unloadVideoElement(pVid);
      bindAndPlayMotionVideoElement(sbVid, currentMotionVideoUrl);
    } else {
      unloadVideoElement(sbVid);
      bindAndPlayMotionVideoElement(pVid, currentMotionVideoUrl);
    }
    if (sbBadge) sbBadge.classList.remove('hidden');
  }

  function hideMotionVideos() {
    const pVid = document.getElementById('player-motion-video');
    const sbVid = document.getElementById('standby-motion-video');
    const sbBadge = document.getElementById('standby-motion-badge');
    unloadVideoElement(pVid);
    unloadVideoElement(sbVid);
    if (sbBadge) sbBadge.classList.add('hidden');
    currentMotionVideoUrl = '';
    if (ScreenWakeLockManager.isActive) {
      ScreenWakeLockManager.syncFallbackVideoState();
    }
  }

  function applyMotionVideoUrl(url) {
    if (!url) {
      hideMotionVideos();
      return;
    }
    url = appendDeviceIdToUrl(url);
    if (currentMotionVideoUrl === url) {
      syncActiveMotionVideoTarget();
      return;
    }
    currentMotionVideoUrl = url;
    syncActiveMotionVideoTarget();
  }

  function setBoundedMapValue(map, key, val, maxSize = 200) {
    if (!key) return;
    if (map.has(key)) {
      map.delete(key);
    }
    map.set(key, val);
    while (map.size > maxSize) {
      const oldestKey = map.keys().next().value;
      if (oldestKey === undefined) break;
      map.delete(oldestKey);
    }
  }

  function applyMotionArtwork(data) {
    if (!data) return;
    const url = (data.motion_url || '').trim();
    const respTrack = data.track || '';
    const respArtist = data.artist || '';
    const respAlbum = data.album || '';

    const albKey = buildMotionAlbumKey(respArtist, respAlbum);
    const trkKey = buildMotionTrackKey(respTrack, respArtist, respAlbum);
    if (albKey) setBoundedMapValue(motionArtworkClientCache, albKey, url, 200);
    if (trkKey) setBoundedMapValue(motionArtworkClientCache, trkKey, url, 200);

    const t = state.track;
    if (!t) {
      hideMotionVideos();
      return;
    }
    // Ensure response still matches current track or album
    const sameTrack = respTrack && t.name && respTrack.toLowerCase() === t.name.toLowerCase();
    const sameAlbum = respAlbum && t.album && respAlbum.toLowerCase() === t.album.toLowerCase();
    if (!sameTrack && !sameAlbum) {
      return;
    }
    applyMotionVideoUrl(url);
  }

  function syncStandbyAndMotionCoverUI() {
    const isPlaying = state.playerState === 'playing';
    const t = state.track;

    const sbTitle = document.getElementById('standby-title');
    const sbArtist = document.getElementById('standby-artist');
    const sbAlbum = document.getElementById('standby-album');
    const sbArt = document.getElementById('standby-artwork');
    const sbDac = document.getElementById('standby-dac-badge');
    const sbPlay = document.getElementById('standby-icon-play');
    const sbPause = document.getElementById('standby-icon-pause');
    const sbFav = document.getElementById('standby-btn-favorite');
    const sbShuffleBtn = document.getElementById('standby-btn-shuffle');
    const sbRepeatBtn = document.getElementById('standby-btn-repeat');
    const sbRepeatBadge = document.getElementById('standby-repeat-badge');
    const sbAiVibe = document.getElementById('standby-btn-ai-track-vibe');

    const isRadioMode = Boolean(state.isRadio);
    if (sbShuffleBtn) {
      sbShuffleBtn.disabled = isRadioMode;
      sbShuffleBtn.classList.toggle('disabled-control', isRadioMode);
      sbShuffleBtn.classList.toggle('active', !isRadioMode && Boolean(state.shuffle));
      sbShuffleBtn.title = isRadioMode
        ? (IS_EN ? 'Shuffle unavailable on Radio' : 'Перемешивание недоступно для радио')
        : (state.shuffle
          ? (IS_EN ? 'Shuffle: On' : 'Перемешать: Вкл')
          : (IS_EN ? 'Shuffle: Off' : 'Перемешать'));
    }
    const sbEffectiveRepeat = (isRadioMode && state.repeatMode === 'all') ? 'off' : state.repeatMode;
    if (sbRepeatBtn) {
      const isRepActive = sbEffectiveRepeat === 'one' || sbEffectiveRepeat === 'all';
      sbRepeatBtn.classList.toggle('active', isRepActive);
      sbRepeatBtn.title = sbEffectiveRepeat === 'one'
        ? (IS_EN ? 'Repeat: One Track (1)' : 'Повтор: Зациклен 1 трек')
        : (sbEffectiveRepeat === 'all'
          ? (IS_EN ? 'Repeat: Queue' : 'Повтор: Вся очередь')
          : (isRadioMode
            ? (IS_EN ? 'Repeat: Off (tap to repeat track)' : 'Повтор трека: Выкл')
            : (IS_EN ? 'Repeat: Off' : 'Режим повтора: Выкл')));
    }
    if (sbRepeatBadge) {
      sbRepeatBadge.classList.toggle('hidden', sbEffectiveRepeat !== 'one');
    }

    if (t && t.name) {
      const sbTitleText = t.name || 'Без названия';
      const sbArtistText = t.artist || 'Apple Music';
      const sbAlbumText = t.album || '';
      if (sbTitle && sbTitle.textContent !== sbTitleText) sbTitle.textContent = sbTitleText;
      if (sbArtist && sbArtist.textContent !== sbArtistText) sbArtist.textContent = sbArtistText;
      if (sbAlbum && sbAlbum.textContent !== sbAlbumText) sbAlbum.textContent = sbAlbumText;
      if (sbFav) sbFav.classList.toggle('active', Boolean(t.favorited));
      if (sbAiVibe) {
        sbAiVibe.disabled = false;
        sbAiVibe.classList.toggle('hidden', !state.aiCuratorEnabled);
      }
      const art = getArtworkSrc(t);
      if (sbArt && sbArt.dataset.targetSrc !== art) {
        delete sbArt.dataset.fallbackApplied;
        sbArt.dataset.fallbackIcon = 'apple-touch-icon.svg';
        sbArt.dataset.targetSrc = art;
        sbArt.src = art;
      }

      const mKey = `${t.name || ''}|${t.artist || ''}|${t.album || ''}`;
      if (mKey !== lastMotionQueryKey) {
        lastMotionQueryKey = mKey;
        const albKey = buildMotionAlbumKey(t.artist, t.album);
        const trkKey = buildMotionTrackKey(t.name, t.artist, t.album);

        if (albKey && motionArtworkClientCache.has(albKey)) {
          applyMotionVideoUrl(motionArtworkClientCache.get(albKey));
        } else if (motionArtworkClientCache.has(trkKey)) {
          applyMotionVideoUrl(motionArtworkClientCache.get(trkKey));
        } else {
          hideMotionVideos();
          send({
            action: 'get_motion_artwork',
            params: {
              track: t.name || '',
              artist: t.artist || '',
              album: t.album || ''
            }
          });
        }
      }
    } else {
      const sbNotPlaying = translateTextToEn('Не играет');
      if (sbTitle && sbTitle.textContent !== sbNotPlaying) sbTitle.textContent = sbNotPlaying;
      if (sbArtist && sbArtist.textContent !== 'Apple Music') sbArtist.textContent = 'Apple Music';
      if (sbAlbum && sbAlbum.textContent !== '') sbAlbum.textContent = '';
      if (sbFav) sbFav.classList.remove('active');
      if (sbAiVibe) {
        sbAiVibe.disabled = true;
        sbAiVibe.classList.toggle('hidden', !state.aiCuratorEnabled);
      }
      if (sbArt) {
        sbArt.dataset.targetSrc = 'apple-touch-icon.svg';
        sbArt.src = 'apple-touch-icon.svg';
      }
      if (lastMotionQueryKey !== '') {
        lastMotionQueryKey = '';
        hideMotionVideos();
      }
    }

    const sbDacText = document.getElementById('standby-dac-text');
    const drcTvPart = (state.lateNightDrcEnabled || (state.lateNightDrcMode && state.lateNightDrcMode !== 'off')) ? ' · 🌙' : '';
    if (sbDacText) {
      const devPart = state.audioDeviceName ? ` · ${state.audioDeviceName}` : '';
      sbDacText.textContent = `${formatDacPill(state.audioQuality)}${devPart}${drcTvPart}`;
    } else if (sbDac) {
      const devPart = state.audioDeviceName ? ` · ${state.audioDeviceName}` : '';
      sbDac.textContent = `${formatDacPill(state.audioQuality)}${devPart}${drcTvPart}`;
    }

    if (sbPlay && sbPause) {
      if (isPlaying) {
        sbPlay.classList.add('hidden');
        sbPause.classList.remove('hidden');
      } else {
        sbPlay.classList.remove('hidden');
        sbPause.classList.add('hidden');
      }
    }

    updateStandbyActiveTile();
    syncTrackLoadingIndicatorUI();
    syncMotionVideoPlaybackState();
    ScreenWakeLockManager.syncByPlaybackAndConnection();
    syncSpectralPolling();
    refreshAllTitleMarquees();
  }

  let lastStandbyTilesSignature = '';

  function handleTvLibraryConfig(data) {
    const rawCfg = (data && data.config && typeof data.config === 'object') ? data.config : data;
    if (!rawCfg || typeof rawCfg !== 'object') return;
    state.tvLibraryConfig = {
      ...state.tvLibraryConfig,
      ...rawCfg
    };
    state.tvLibraryConfigLoaded = true;
    lastStandbyTilesSignature = '';
    renderStandbyQuickTiles();
  }

  function openStandbyLibraryModal() {
    const modal = document.getElementById('standby-library-modal');
    if (!modal) return;
    closeStandbyAiModal();
    if (typeof closeStandbyQueueModal === 'function') closeStandbyQueueModal();
    if (!state.tvLibraryConfigLoaded) {
      send({ action: 'get_tv_library_config' });
    }
    renderStandbyQuickTiles();
    if (!state.playlists || state.playlists.length === 0) {
      send({ action: 'get_playlists' });
    }
    if (!state.libraryAlbums || state.libraryAlbums.length === 0) {
      send({ action: 'get_library_albums' });
    }
    modal.classList.remove('hidden');
    modal.setAttribute('aria-hidden', 'false');
    const p = document.getElementById('top-settings-popover');
    if (p) {
      blurFocusedInContainer(p);
      p.classList.add('hidden');
      p.setAttribute('aria-hidden', 'true');
    }
  }

  function closeStandbyLibraryModal() {
    const modal = document.getElementById('standby-library-modal');
    if (!modal) return;
    blurFocusedInContainer(modal);
    modal.classList.add('hidden');
    modal.setAttribute('aria-hidden', 'true');
  }

  // =========================================================================
  // Fullscreen StandBy / TV Mode AI Sonic Curator Tag Cloud (Infinite Scroll)
  // =========================================================================
  const AI_TV_THEMES = ['violet', 'indigo', 'cyan', 'rose', 'amber', 'emerald'];
  const AI_TV_SIZES = ['lg', 'xl', 'md', 'lg', 'xl', 'md'];

  let standbyAiGeneratedCount = 0;
  let standbyAiScrollBound = false;

  function buildNextStandbyAiTagItem() {
    const seq = standbyAiGeneratedCount++;
    const raw = (seq % 3 === 0)
      ? generateFreshAiPromptsBatch(1)[0]
      : synthesizeDynamicClientPrompt();
    const theme = AI_TV_THEMES[Math.floor(Math.random() * AI_TV_THEMES.length)];
    const size = AI_TV_SIZES[seq % AI_TV_SIZES.length];
    return {
      label: IS_EN ? (raw.labelEn || raw.label_en || raw.label) : (raw.labelRu || raw.label_ru || raw.label),
      prompt: IS_EN ? (raw.promptEn || raw.prompt_en || raw.prompt) : (raw.promptRu || raw.prompt_ru || raw.prompt),
      theme,
      size
    };
  }

  function triggerStandbyAiTagPlay(prompt, label) {
    if (!prompt) return;
    triggerHaptic('medium');
    closeStandbyAiModal();
    state.isAiCurating = true;
    state.pendingStandbyAiAutoPlay = true;
    state.searchQuery = prompt;
    state.aiCurateReqSeq = (state.aiCurateReqSeq || 0) + 1;
    state.lastAiCurateSentAt = Date.now();
    const reqId = state.aiCurateReqSeq;
    setUIBusy(true, (IS_EN ? 'AI Curating: ' : 'ИИ-подбор: ') + label.replace(/^[^\w\sа-яА-ЯёЁ]+\s*/, '') + '...');
    send({
      action: 'ai_curate',
      request_id: reqId,
      params: {
        prompt: prompt,
        country: getActiveStorefront(),
        auto_play: true,
        request_id: reqId
      }
    });
  }

  function formatStandbyAiTagHtml(rawLabel) {
    const str = String(rawLabel || '').trim();
    const emojiMatch = str.match(/^(\S+)\s+([\s\S]+)$/);
    let icon = '';
    let rest = str;
    if (emojiMatch && /^[^\wа-яА-ЯёЁ]+$/.test(emojiMatch[1])) {
      icon = emojiMatch[1];
      rest = emojiMatch[2].trim();
    }
    const iconSpan = icon ? `<span class="ai-tag-icon">${escapeHtml(icon)}</span>` : '';
    const parts = rest.split(/\s*•\s*/);
    if (parts.length >= 2) {
      const line1 = parts[0].trim();
      const line2 = parts.slice(1).join(' · ').trim();
      return `<span class="ai-tag-line-top">${iconSpan}<span class="ai-tag-main">${escapeHtml(line1)}</span></span><span class="ai-tag-sub">${escapeHtml(line2)}</span>`;
    }
    const words = rest.split(/\s+/);
    if (words.length >= 3) {
      const mid = Math.ceil(words.length / 2);
      const line1 = words.slice(0, mid).join(' ');
      const line2 = words.slice(mid).join(' ');
      return `<span class="ai-tag-line-top">${iconSpan}<span class="ai-tag-main">${escapeHtml(line1)}</span></span><span class="ai-tag-sub">${escapeHtml(line2)}</span>`;
    }
    return `<span class="ai-tag-line-top">${iconSpan}<span class="ai-tag-main">${escapeHtml(rest)}</span></span>`;
  }

// === MODULE: 24-standby-ai-cloud-and-tiles.js ===
  function createStandbyAiTagPillElement(item, forcePinned = false) {
    const isPinned = forcePinned || isPromptPinnedClient(item.prompt);
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = `standby-ai-tag-pill tag-size-${item.size || 'lg'} tag-theme-${item.theme || 'violet'}${isPinned ? ' is-pinned' : ''}`;
    btn.setAttribute('data-ai-prompt', item.prompt);
    btn.innerHTML = `${formatStandbyAiTagHtml(item.label)}<span class="standby-tag-pin-badge ${isPinned ? 'active' : ''}" title="${translateTextToEn('Закрепить / открепить вайб')}">${isPinned ? '★' : '☆'}</span>`;
    const pinBadge = btn.querySelector('.standby-tag-pin-badge');
    if (pinBadge) {
      pinBadge.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        togglePinAiPrompt(item.prompt, item.label);
      });
    }
    btn.addEventListener('click', () => {
      triggerStandbyAiTagPlay(item.prompt, item.label);
    });
    return btn;
  }

  const MAX_STANDBY_AI_CHIPS = 120;

  function appendStandbyAiTagBatch(count = 24) {
    const cloud = document.getElementById('standby-ai-tag-cloud');
    const sentinel = document.getElementById('standby-ai-sentinel');
    if (!cloud) return;
    const availableSlots = Math.max(0, MAX_STANDBY_AI_CHIPS - cloud.children.length);
    const batchCount = Math.min(count, availableSlots);
    if (batchCount <= 0) {
      if (sentinel) sentinel.classList.add('hidden');
      return;
    }
    const frag = document.createDocumentFragment();
    for (let i = 0; i < batchCount; i++) {
      const item = buildNextStandbyAiTagItem();
      frag.appendChild(createStandbyAiTagPillElement(item, false));
    }
    cloud.appendChild(frag);
    if (sentinel && cloud.children.length >= MAX_STANDBY_AI_CHIPS) {
      sentinel.classList.add('hidden');
    }
  }

  function resetAndGenerateStandbyAiTagCloud() {
    const cloud = document.getElementById('standby-ai-tag-cloud');
    const scrollEl = document.getElementById('standby-ai-scroll');
    const sentinel = document.getElementById('standby-ai-sentinel');
    if (!cloud) return;
    cloud.innerHTML = '';
    if (sentinel) sentinel.classList.remove('hidden');
    if (scrollEl) scrollEl.scrollTop = 0;
    standbyAiGeneratedCount = 0;
    if (Array.isArray(state.pinnedAiPrompts) && state.pinnedAiPrompts.length > 0) {
      const pinFrag = document.createDocumentFragment();
      state.pinnedAiPrompts.slice(0, MAX_STANDBY_AI_CHIPS).forEach((p, idx) => {
        const prompt = IS_EN ? (p.promptEn || p.prompt_en || p.prompt || '') : (p.promptRu || p.prompt_ru || p.prompt || '');
        const label = IS_EN ? (p.labelEn || p.label_en || p.label || prompt) : (p.labelRu || p.label_ru || p.label || prompt);
        if (!prompt) return;
        pinFrag.appendChild(createStandbyAiTagPillElement({
          label,
          prompt,
          size: idx % 2 === 0 ? 'xl' : 'lg',
          theme: AI_TV_THEMES[idx % AI_TV_THEMES.length]
        }, true));
      });
      cloud.appendChild(pinFrag);
    }
    appendStandbyAiTagBatch(28);
  }

  function ensureStandbyAiScrollBinding() {
    if (standbyAiScrollBound) return;
    const scrollEl = document.getElementById('standby-ai-scroll');
    const sentinel = document.getElementById('standby-ai-sentinel');
    const loadMoreBtn = document.getElementById('btn-standby-ai-load-more');
    if (!scrollEl) return;
    standbyAiScrollBound = true;

    if (loadMoreBtn) {
      loadMoreBtn.addEventListener('click', () => {
        triggerHaptic('light');
        appendStandbyAiTagBatch(18);
      });
    }

    if ('IntersectionObserver' in window && sentinel) {
      const io = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            appendStandbyAiTagBatch(18);
          }
        });
      }, { root: scrollEl, rootMargin: '260px' });
      io.observe(sentinel);
    }
  }

  function openStandbyAiModal() {
    if (!state.aiCuratorEnabled) return;
    const modal = document.getElementById('standby-ai-modal');
    if (!modal) return;
    closeStandbyLibraryModal();
    if (typeof closeStandbyQueueModal === 'function') closeStandbyQueueModal();
    const p = document.getElementById('top-settings-popover');
    if (p) {
      blurFocusedInContainer(p);
      p.classList.add('hidden');
      p.setAttribute('aria-hidden', 'true');
    }

    resetAndGenerateStandbyAiTagCloud();
    ensureStandbyAiScrollBinding();

    modal.classList.remove('hidden');
    modal.setAttribute('aria-hidden', 'false');
  }

  function closeStandbyAiModal() {
    const modal = document.getElementById('standby-ai-modal');
    if (!modal) return;
    blurFocusedInContainer(modal);
    modal.classList.add('hidden');
    modal.setAttribute('aria-hidden', 'true');
  }

  function updateStandbyActiveTile() {
    const grid = document.getElementById('standby-library-grid');
    if (!grid) return;
    const curPlaylist = ((state.queue && state.queue.playlist) || '').trim().toLowerCase();
    const activeKey = (state.activeStandbyTileKey || '').toLowerCase();
    grid.querySelectorAll('.standby-square-tile').forEach(tile => {
      const key = (tile.getAttribute('data-tile-key') || '').toLowerCase();
      const name = (tile.getAttribute('data-tile-name') || '').toLowerCase();
      const isMatch = (activeKey && key === activeKey) ||
        (curPlaylist && name && (curPlaylist === name || (curPlaylist.includes('станция') && activeKey === key)));
      tile.classList.toggle('active', Boolean(isMatch));
    });
  }

  function buildAlbumConfigMatchKey(name, artist) {
    return `${normalizeAlbumMatchText(name)}|${normalizeAlbumMatchText(artist)}`;
  }

  function renderStandbyQuickTiles() {
    const grid = document.getElementById('standby-library-grid');
    if (!grid) return;

    const cfg = state.tvLibraryConfig || {};
    const playlistsMode = cfg.playlists_mode || 'all';
    const albumsMode = cfg.albums_mode || 'recent';

    const rawPlaylists = (state.playlists || []).filter(pl => {
      const n = (pl.name || '').trim();
      if (!n) return false;
      if (n.includes('Очередь AMR') || n.startsWith('AMR ')) return false;
      return true;
    });

    const allLibAlbums = Array.isArray(state.libraryAlbums) ? state.libraryAlbums : [];

    const sig = JSON.stringify(cfg) +
      '|pl:' + rawPlaylists.map(p => `${p.name}:${p.artwork_url || p.artworkUrl || ''}:${p.track_count || p.trackCount || 0}`).join('|') +
      '|albums:' + allLibAlbums.map(a => `${a.id || ''}:${a.name || ''}:${a.artist || ''}:${a.artwork || ''}`).join('|') +
      '|mixes:' + ((state.personalMixes || []).map(m => `${m.name}:${m.id || ''}`).join(','));
    if (sig === lastStandbyTilesSignature && grid.children.length > 0) {
      updateStandbyActiveTile();
      return;
    }
    lastStandbyTilesSignature = sig;
    grid.innerHTML = '';

    const playBadgeHtml = `
      <div class="standby-tile-play-badge">
        <svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor">
          <polygon points="7 4 20 12 7 20 7 4"/>
        </svg>
      </div>
    `;

    // 1. Core Personal Stations & Mixes: Моя станция, Станция открытий, В моём вкусе, Сейчас на повторе
    const coreTiles = [
      {
        key: 'my-station',
        visible: cfg.show_my_station !== false,
        title: IS_EN ? 'My Station' : 'Моя станция',
        type: 'station',
        onClick: () => {
          state.activeStandbyTileKey = 'my-station';
          updateStandbyActiveTile();
          closeStandbyLibraryModal();
          optimisticPlay();
          markWaitingForPlayback({ isStation: true, targetName: 'Моя станция' });
          setUIBusy(true, 'Запуск «Моей станции»...');
          send({
            action: 'play_hero_card',
            params: {
              index: 1,
              name: 'Моя станция',
              artist: 'Персональная радиостанция',
              id: '',
              url: '',
              type: 'station'
            }
          });
        }
      },
      {
        key: 'discovery-station',
        visible: cfg.show_discovery_station !== false,
        title: IS_EN ? 'Discovery Station' : 'Станция открытий',
        type: 'station',
        onClick: () => {
          state.activeStandbyTileKey = 'discovery-station';
          updateStandbyActiveTile();
          closeStandbyLibraryModal();
          optimisticPlay();
          markWaitingForPlayback({ isStation: true, targetName: 'Станция открытий' });
          setUIBusy(true, 'Запуск «Станции открытий»...');
          send({
            action: 'play_hero_card',
            params: {
              index: 2,
              name: 'Станция открытий',
              artist: 'Новые треки под ваш вкус',
              id: '',
              url: '',
              type: 'station'
            }
          });
        }
      },
      {
        key: 'favorites-mix',
        visible: cfg.show_favorites_mix !== false,
        title: IS_EN ? 'Favorites Mix' : 'В моём вкусе',
        type: 'playlist',
        onClick: () => {
          state.activeStandbyTileKey = 'favorites-mix';
          updateStandbyActiveTile();
          closeStandbyLibraryModal();
          const mixes = state.personalMixes || [];
          const favMix = mixes.find(m => {
            const n = (m.name || '').toLowerCase();
            return n.includes('в моём вкусе') || n.includes('в моем вкусе') || n.includes('favorites') || n.includes('essentials');
          });
          optimisticPlay();
          markWaitingForPlayback({ targetName: 'В моём вкусе' });
          setUIBusy(true, 'Запуск «В моём вкусе»...');
          send({
            action: 'play_playlist',
            params: {
              playlist: favMix ? favMix.name : 'В моём вкусе',
              id: favMix ? (favMix.id || '') : '',
              url: favMix ? (favMix.url || '') : '',
              shuffle: false
            }
          });
        }
      },
      {
        key: 'heavy-rotation',
        visible: cfg.show_heavy_rotation !== false,
        title: IS_EN ? 'Heavy Rotation' : 'Сейчас на повторе',
        type: 'playlist',
        onClick: () => {
          state.activeStandbyTileKey = 'heavy-rotation';
          updateStandbyActiveTile();
          closeStandbyLibraryModal();
          const mixes = state.personalMixes || [];
          const hrMix = mixes.find(m => {
            const n = (m.name || '').toLowerCase();
            return n.includes('повторе') || n.includes('heavy rotation');
          });
          optimisticPlay();
          markWaitingForPlayback({ targetName: 'Сейчас на повторе' });
          setUIBusy(true, 'Запуск «Сейчас на повторе»...');
          send({
            action: 'play_playlist',
            params: {
              playlist: hrMix ? hrMix.name : 'Сейчас на повторе',
              id: hrMix ? (hrMix.id || '') : '',
              url: hrMix ? (hrMix.url || '') : '',
              shuffle: false
            }
          });
        }
      }
    ].filter(item => item.visible);

    // 2. Filter Playlists according to cfg.playlists_mode ('all' | 'selected' | 'none')
    let filteredPlaylists = [];
    if (playlistsMode === 'none') {
      filteredPlaylists = [];
    } else if (playlistsMode === 'selected') {
      const selectedNames = Array.isArray(cfg.selected_playlist_names) ? cfg.selected_playlist_names : [];
      const seenPl = new Set();
      selectedNames.forEach(rawSel => {
        const cleanSel = String(rawSel || '').trim();
        const lowerSel = cleanSel.toLowerCase();
        if (!lowerSel || seenPl.has(lowerSel)) return;
        const found = rawPlaylists.find(pl => String(pl.name || '').trim().toLowerCase() === lowerSel);
        if (found) {
          seenPl.add(lowerSel);
          filteredPlaylists.push(found);
        } else if (rawPlaylists.length === 0 && cleanSel) {
          seenPl.add(lowerSel);
          filteredPlaylists.push({ name: cleanSel });
        }
      });
    } else {
      filteredPlaylists = rawPlaylists.filter(pl => {
        const lower = (pl.name || '').trim().toLowerCase();
        return lower !== 'в моём вкусе' && lower !== 'в моем вкусе' && lower !== 'сейчас на повторе';
      });
    }

    // 3. Filter Albums according to cfg.albums_mode ('recent' | 'selected' | 'none')
    let filteredAlbums = [];
    if (albumsMode === 'none') {
      filteredAlbums = [];
    } else if (albumsMode === 'selected') {
      const selAlbumObjs = Array.isArray(cfg.selected_albums) ? cfg.selected_albums : [];
      const selAlbumKeys = Array.isArray(cfg.selected_album_keys) ? cfg.selected_album_keys : [];
      const usedLibIndices = new Set();
      const seenOutKeys = new Set();

      const matchLibAlbum = (selItem) => {
        const selId = String((selItem && selItem.id) || '').trim();
        const selKeyRaw = String((selItem && selItem.key) || '').trim().toLowerCase();
        const selKeyNorm = selKeyRaw
          ? selKeyRaw.split('|').map(part => normalizeAlbumMatchText(part)).join('|')
          : '';
        const selName = (selItem && selItem.name) || '';
        const selArtist = (selItem && selItem.artist) || '';

        for (let i = 0; i < allLibAlbums.length; i++) {
          if (usedLibIndices.has(i)) continue;
          const cand = allLibAlbums[i];
          if (!cand) continue;
          const candId = String(cand.id || '').trim();
          const candKeyRaw = String(cand.key || '').trim().toLowerCase();
          const candNormKey = buildAlbumConfigMatchKey(cand.name, cand.artist);
          const candRawPair = `${String(cand.name || '').trim().toLowerCase()}|${String(cand.artist || '').trim().toLowerCase()}`;

          if (
            (selId && candId && selId === candId) ||
            (selKeyRaw && ((candKeyRaw && selKeyRaw === candKeyRaw) || selKeyRaw === candRawPair || selKeyNorm === candNormKey)) ||
            (selName && albumsMatchClient(cand.name, cand.artist, selName, selArtist))
          ) {
            usedLibIndices.add(i);
            return cand;
          }
        }
        return null;
      };

      selAlbumObjs.forEach(selObj => {
        if (!selObj || typeof selObj !== 'object') return;
        const matched = matchLibAlbum(selObj);
        if (matched) {
          const outK = buildAlbumConfigMatchKey(matched.name, matched.artist) || String(matched.id || '');
          if (!seenOutKeys.has(outK)) {
            seenOutKeys.add(outK);
            filteredAlbums.push(matched);
          }
        } else if (allLibAlbums.length === 0 && selObj.name) {
          const outK = buildAlbumConfigMatchKey(selObj.name, selObj.artist) || String(selObj.key || selObj.id || selObj.name);
          if (!seenOutKeys.has(outK)) {
            seenOutKeys.add(outK);
            filteredAlbums.push({
              id: selObj.id || '',
              name: selObj.name || '',
              artist: selObj.artist || '',
              artwork: selObj.artwork || selObj.artwork_url || '',
              track_count: selObj.track_count || 0
            });
          }
        }
      });

      selAlbumKeys.forEach(rawKey => {
        const keyStr = String(rawKey || '').trim();
        if (!keyStr) return;
        let parsedName = '';
        let parsedArtist = '';
        if (keyStr.includes('|')) {
          const parts = keyStr.split('|');
          parsedName = parts[0] || '';
          parsedArtist = parts.slice(1).join('|') || '';
        } else if (keyStr.includes('::')) {
          const parts = keyStr.split('::');
          parsedName = parts[0] || '';
          parsedArtist = parts.slice(1).join('::') || '';
        }
        const probe = { key: keyStr, id: (!parsedName ? keyStr : ''), name: parsedName, artist: parsedArtist };
        const matched = matchLibAlbum(probe);
        if (matched) {
          const outK = buildAlbumConfigMatchKey(matched.name, matched.artist) || String(matched.id || keyStr);
          if (!seenOutKeys.has(outK)) {
            seenOutKeys.add(outK);
            filteredAlbums.push(matched);
          }
        } else if (allLibAlbums.length === 0 && parsedName) {
          const outK = buildAlbumConfigMatchKey(parsedName, parsedArtist) || keyStr.toLowerCase();
          if (!seenOutKeys.has(outK)) {
            seenOutKeys.add(outK);
            filteredAlbums.push({
              id: '',
              name: parsedName,
              artist: parsedArtist,
              artwork: '',
              track_count: 0
            });
          }
        }
      });
    } else {
      filteredAlbums = allLibAlbums.slice(0, 24);
    }

    if (coreTiles.length === 0 && filteredPlaylists.length === 0 && filteredAlbums.length === 0) {
      grid.innerHTML = `<div class="empty-state">${escapeHtml(translateTextToEn('Все плашки скрыты в настройках Mac (Основные → ТВ-режим)'))}</div>`;
      return;
    }

    coreTiles.forEach(item => {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'standby-square-tile';
      btn.setAttribute('data-tile-key', item.key);
      btn.setAttribute('data-tile-name', item.title);
      btn.setAttribute('title', item.title);
      const plaqueHtml = getAnimatedPlaqueHtml({ title: item.title, type: item.type }) || '';
      btn.innerHTML = `${plaqueHtml}${playBadgeHtml}`;
      btn.addEventListener('click', item.onClick);
      grid.appendChild(btn);
    });

    // 2. Local Library Playlists (Large Square Tiles)
    filteredPlaylists.forEach(pl => {
      const plName = (pl.name || '').trim();
      if (!plName) return;

      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'standby-square-tile';
      const tileKey = `pl:${plName}`;
      btn.setAttribute('data-tile-key', tileKey);
      btn.setAttribute('data-tile-name', plName);
      btn.setAttribute('title', plName);

      const count = pl.track_count || pl.trackCount || 0;
      const countText = count > 0 ? `<span class="standby-tile-meta">${count} треков</span>` : '';
      const artUrl = appendDeviceIdToUrl(pl.artwork_url || pl.artworkUrl || `/api/artwork/playlist?name=${encodeURIComponent(plName)}`);
      btn.innerHTML = `
        <img class="standby-tile-cover" src="${escapeHtml(artUrl)}" alt="${escapeHtml(plName)}" loading="lazy" data-fallback-mode="next-flex">
        <div class="standby-tile-fallback" style="display:none;">
          <svg viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="currentColor" stroke-width="1.6">
            <path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>
          </svg>
        </div>
        <div class="standby-tile-scrim">
          <span class="standby-tile-title">${escapeHtml(plName)}</span>
          ${countText}
        </div>
        ${playBadgeHtml}
      `;

      btn.addEventListener('click', () => {
        state.activeStandbyTileKey = tileKey;
        updateStandbyActiveTile();
        closeStandbyLibraryModal();
        optimisticPlay();
        markWaitingForPlayback({ targetName: plName });
        setUIBusy(true, `Запуск «${plName}»...`);
        send({
          action: 'play_playlist',
          params: {
            playlist: plName,
            shuffle: false,
            is_local: true
          }
        });
      });

      grid.appendChild(btn);
    });

    // 3. User Library Albums (Filtered by tv_library_config)
    filteredAlbums.forEach(alb => {
      const albName = (alb.name || '').trim();
      if (!albName) return;
      const albArtist = (alb.artist || '').trim();
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'standby-square-tile';
      const tileKey = `alb:${alb.id || albName}`;
      btn.setAttribute('data-tile-key', tileKey);
      btn.setAttribute('data-tile-name', albName);
      btn.setAttribute('title', albArtist ? `${albName} — ${albArtist}` : albName);

      const count = alb.track_count || alb.trackCount || 0;
      const metaParts = [];
      if (albArtist) metaParts.push(albArtist);
      if (count > 0) metaParts.push(formatTracksCount(count));
      const metaText = metaParts.length > 0
        ? `<span class="standby-tile-meta">${escapeHtml(metaParts.join(' • '))}</span>`
        : '';
      const fallbackArt = `/api/artwork/search?name=${encodeURIComponent(albName)}&artist=${encodeURIComponent(albArtist)}&album=${encodeURIComponent(albName)}`;
      const rawArt = alb.artwork || alb.artwork_url || alb.artworkUrl || fallbackArt;
      const artUrl = appendDeviceIdToUrl(rawArt);

      btn.innerHTML = `
        <img class="standby-tile-cover" src="${escapeHtml(artUrl)}" alt="${escapeHtml(albName)}" loading="lazy" data-fallback-mode="next-flex">
        <div class="standby-tile-fallback" style="display:none;">
          <svg viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="currentColor" stroke-width="1.6">
            <circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="3"/>
          </svg>
        </div>
        <div class="standby-tile-scrim">
          <span class="standby-tile-title">${escapeHtml(albName)}</span>
          ${metaText}
        </div>
        ${playBadgeHtml}
      `;

      btn.addEventListener('click', () => {
        state.activeStandbyTileKey = tileKey;
        updateStandbyActiveTile();
        closeStandbyLibraryModal();
        optimisticPlay();
        markWaitingForPlayback({ targetName: albName });
        setUIBusy(true, `Запуск альбома «${albName}»...`);
        send({
          action: 'play_album',
          params: {
            id: alb.id || '',
            name: albName,
            artist: albArtist,
            shuffle: false
          }
        });
      });

      grid.appendChild(btn);
    });

    updateStandbyActiveTile();
    syncTrackLoadingIndicatorUI();
    syncMotionVideoPlaybackState();
    ScreenWakeLockManager.syncByPlaybackAndConnection();
    syncSpectralPolling();
    refreshAllTitleMarquees();
  }

  function updateWledSettingsUI(data) {
    if (!data) return;
    const enabled = Boolean(data.enabled);
    const ip = data.ip !== undefined ? data.ip : '';
    const mode = data.mode || 'ambilight';
    const isActive = enabled && Boolean(ip) && mode !== 'off';
    state.wledEnabled = enabled;
    state.wledActive = isActive;

    const modeSel = document.getElementById('wled-mode-select');
    const dot = document.getElementById('wled-status-dot');
    const sbWledBadge = document.getElementById('standby-wled-badge');
    const btnTop = document.getElementById('btn-top-settings');
    const btnMob = document.getElementById('mobile-btn-settings');
    const btnPl = document.getElementById('player-btn-settings');
    const btnSb = document.getElementById('standby-btn-wled-toggle');
    const popover = document.getElementById('top-settings-popover');

    if (modeSel) modeSel.value = mode;
    if (dot) dot.classList.toggle('active', isActive);
    if (sbWledBadge) sbWledBadge.classList.toggle('hidden', !isActive);

    // Hide all WLED buttons across Mobile, StandBy/TV, and Tablet/PC when WLED is disabled in AMR settings
    [btnTop, btnMob, btnPl, btnSb].forEach(b => {
      if (!b) return;
      b.classList.toggle('hidden', !enabled);
      b.classList.toggle('active', isActive);
    });

    if (!enabled && popover) {
      blurFocusedInContainer(popover);
      popover.classList.add('hidden');
      popover.setAttribute('aria-hidden', 'true');
    }
  }

// === MODULE: 25-wled-dsp-and-mastering-ui.js ===
  function pushWledSettingsToServer() {
    const modeSel = document.getElementById('wled-mode-select');
    const mode = modeSel ? modeSel.value : 'ambilight';

    send({
      action: 'set_wled_settings',
      params: {
        mode
      }
    });
  }

  function updateDSPSettingsUI(data) {
    if (!data || typeof data !== 'object') return;
    state.lastDspSettings = Object.assign({}, data);
    if (data.is_dlna_active !== undefined) {
      state.isDlnaActive = Boolean(data.is_dlna_active);
    }
    if (data.room_acoustic && typeof data.room_acoustic === 'object') {
      updateRoomAcousticUI(data.room_acoustic, { skipSignalRefresh: true });
    }
    if (data.late_night_drc && typeof data.late_night_drc === 'object') {
      updateLateNightDRCUI(data.late_night_drc, { skipSignalRefresh: true });
    }
    if (data.mastering_restoration && typeof data.mastering_restoration === 'object') {
      updateMasteringRestorationUI(data.mastering_restoration, { skipSignalRefresh: true });
    }
    if (data.mode !== undefined) state.dspMode = String(data.mode || 'passthrough');
    if (data.dsd_rate !== undefined) state.dspRate = Number(data.dsd_rate) || 256;
    if (data.profile !== undefined) {
      const p = String(data.profile || 'balanced');
      state.dspProfileKey = p;
      state.dspProfile = (p === 'transient') ? '7EC-Transient' : ((p === 'superWide') ? '7EC-Super' : '7EC-Balanced');
    }
    if (data.clock_policy !== undefined) state.dspClockPolicy = String(data.clock_policy || 'strictSACD44k1');
    if (data.oversampler_backend !== undefined) state.dspOversamplerBackend = String(data.oversampler_backend || 'accelerateAMX');
    if (data.phase_mode !== undefined) state.dspPhaseMode = String(data.phase_mode || 'linearPhase');
    if (data.trellis_order !== undefined) state.dspTrellisOrder = Number(data.trellis_order) || 8;
    if (data.output_sample_rate !== undefined) state.dspOutputSampleRate = Number(data.output_sample_rate) || 0;
    if (data.dop_carrier_rate !== undefined) state.dspDoPCarrierRate = Number(data.dop_carrier_rate) || 0;
    if (data.is_hog_mode !== undefined) state.dspIsHogMode = Boolean(data.is_hog_mode);
    if (data.is_integer_mode !== undefined) state.dspIsIntegerMode = Boolean(data.is_integer_mode);
    if (data.cpu_load_percent !== undefined) state.dspCpuLoadPercent = Number(data.cpu_load_percent) || 0;
    if (data.ring_buffer_fill_percent !== undefined) state.dspRingBufferFillPercent = Number(data.ring_buffer_fill_percent) || 0;

    if (data.usb_dac_available !== undefined) state.usbDacAvailable = Boolean(data.usb_dac_available);
    if (data.supports_nos_pcm !== undefined) state.dspSupportsNos = Boolean(data.supports_nos_pcm);
    if (data.supports_dsd_dop !== undefined) state.dspSupportsDsd = Boolean(data.supports_dsd_dop);
    if (data.max_dsd_rate !== undefined) state.dspMaxDsdRate = Number(data.max_dsd_rate) || 0;
    if (data.active_output_transport !== undefined) state.dspActiveOutputTransport = String(data.active_output_transport || '');

    if (data.active_preset_id !== undefined) {
      state.dspActivePresetId = String(data.active_preset_id || 'builtin_passthrough');
    }
    if (data.active_preset_name !== undefined) {
      state.dspActivePresetName = String(data.active_preset_name || '');
    }
    if (data.active_preset_subtitle !== undefined) {
      state.dspActivePresetSubtitle = String(data.active_preset_subtitle || '');
    }
    if (Array.isArray(data.presets)) {
      state.dspPresets = data.presets;
    }

    const activeDev = Array.isArray(state.audioDevices)
      ? state.audioDevices.find((d) => d && (d.isDefault || d.is_default))
      : null;
    const isNetDev = Boolean(
      state.isDlnaActive ||
      (activeDev && (activeDev.isNetwork || activeDev.is_network || activeDev.protocol === 'dlna' || activeDev.protocol === 'bluos'))
    );
    const devSupportsNos = state.dspSupportsNos !== undefined
      ? Boolean(state.dspSupportsNos)
      : Boolean(activeDev && (activeDev.supportsNOS || activeDev.supports_nos));
    const devSupportsDsd = state.dspSupportsDsd !== undefined
      ? Boolean(state.dspSupportsDsd)
      : Boolean(activeDev && (activeDev.supportsDSDDoP || activeDev.supports_dsd_dop));
    const hasEligibleUsbDac = state.usbDacAvailable !== undefined
      ? Boolean(state.usbDacAvailable)
      : (devSupportsNos || devSupportsDsd);

    if (!isNetDev && devSupportsDsd && state.dspMode === 'sdm_dop') {
      state.dspBadge = `DSD${state.dspRate || 256} DoP · ${state.dspProfile || '7EC-Balanced'}`;
    } else if (!isNetDev && devSupportsNos && state.dspMode === 'hq_nos_pcm') {
      const khz = ((state.dspDoPCarrierRate || 705600) / 1000).toFixed(1).replace(/\.0$/, '');
      state.dspBadge = `HQ NOS PCM · ${khz} kHz`;
    } else {
      state.dspBadge = '';
    }

    const isPresetSupportedByHardware = (p) => {
      if (!p) return false;
      const pid = String(p.id || '');
      if (pid === 'builtin_passthrough') return true;
      const pMode = String(p.mode || (p.configuration && p.configuration.mode) || '');
      if (pMode === 'passthrough' || pMode === 'bitPerfectPassthrough') return true;
      if (pMode === 'hq_nos_pcm') return devSupportsNos;
      if (pMode === 'sdm_dop') return devSupportsDsd;
      return hasEligibleUsbDac;
    };

    const presetSel = document.getElementById('dsp-preset-select');
    if (presetSel) {
      if (Array.isArray(state.dspPresets) && state.dspPresets.length > 0) {
        presetSel.innerHTML = '';
        state.dspPresets.forEach((p) => {
          if (!p || !p.id) return;
          const opt = document.createElement('option');
          opt.value = String(p.id);
          const isBuiltIn = Boolean(p.is_builtin !== undefined ? p.is_builtin : p.isBuiltIn);
          const rawName = String(p.name || p.id);
          opt.textContent = isBuiltIn ? translateTextToEn(rawName) : `★ ${rawName}`;
          opt.disabled = isNetDev || !isPresetSupportedByHardware(p);
          presetSel.appendChild(opt);
        });
        if (!isNetDev && hasEligibleUsbDac && state.dspActivePresetId === 'unsaved_custom') {
          const customOpt = document.createElement('option');
          customOpt.value = 'unsaved_custom';
          customOpt.disabled = true;
          customOpt.textContent = `✏️ ${translateTextToEn(state.dspActivePresetName || 'Пользовательский режим')}`;
          presetSel.appendChild(customOpt);
        }
      }
      if (isNetDev || !hasEligibleUsbDac) {
        presetSel.value = 'builtin_passthrough';
        presetSel.disabled = true;
      } else if (state.dspActivePresetId) {
        presetSel.value = state.dspActivePresetId;
        presetSel.disabled = (state.allowDspPresetSelection === false);
      }
    }

    const subEl = document.getElementById('dsp-preset-subtitle');
    if (subEl) {
      if (isNetDev) {
        subEl.textContent = IS_EN
          ? 'External network streamer active: Bit-Perfect PCM (DSD/NOS presets unavailable)'
          : 'Активен внешний сетевой плеер BluOS / DLNA: передаётся Bit-Perfect PCM (DSD/NOS не поддерживаются)';
      } else if (!hasEligibleUsbDac) {
        subEl.textContent = IS_EN
          ? 'No external USB / Thunderbolt DAC connected: DSD and HQ NOS modes require a USB or Thunderbolt DAC (≥ 24-bit / 176.4 kHz)'
          : 'Внешний USB / Thunderbolt ЦАП не подключён: режимы DSD и HQ NOS доступны только для USB / Thunderbolt ЦАП (≥ 24-бит / 176.4 кГц)';
      } else if (state.dspActivePresetSubtitle) {
        subEl.textContent = translateTextToEn(state.dspActivePresetSubtitle);
      }
    }

    applyDeviceCapabilityPermissionsUI();
    renderNowPlaying();
    updateSignalPathDetails();
  }

  function pushDSPSettingsToServer() {
    if (state.isDlnaActive) {
      const presetSel = document.getElementById('dsp-preset-select');
      if (presetSel) presetSel.value = 'builtin_passthrough';
      showToast(IS_EN
        ? 'DSP presets are disabled when outputting to BluOS / DLNA network players'
        : 'Выбор пресета DSP отключён при выводе на сетевой плеер BluOS / DLNA');
      return;
    }
    const presetSel = document.getElementById('dsp-preset-select');
    if (!presetSel || !presetSel.value || presetSel.value === 'unsaved_custom') return;
    if (presetSel.value !== 'builtin_passthrough' && state.usbDacAvailable === false) {
      presetSel.value = 'builtin_passthrough';
      showToast(IS_EN
        ? 'DSD & HQ NOS modes are available only for external USB / Thunderbolt DACs'
        : 'Режимы DSD и HQ NOS доступны только для внешних USB / Thunderbolt ЦАП');
      return;
    }
    if (state.allowDspPresetSelection === false) {
      if (state.dspActivePresetId) {
        presetSel.value = state.dspActivePresetId;
      }
      showToast(IS_EN ? 'DSP preset selection is disabled for this device on Mac' : 'Выбор пресета DSP отключён для этого устройства в настройках Mac');
      return;
    }
    triggerHaptic('light');
    send({
      action: 'select_dsp_preset',
      params: {
        preset_id: presetSel.value
      }
    });
  }

  function defaultLateNightSubtitle(mode) {
    if (mode === 'gentle') {
      return translateTextToEn('Мягкий подъём тихих деталей (до +6 дБ) с гейтом шума -63 dBFS для джаза, вокала и акустики.');
    }
    if (mode === 'concert') {
      return translateTextToEn('Глубокий контроль оркестровых пианиссимо и тутти (до +9.5 дБ, -1.0 dBTP) для классики и саундтреков.');
    }
    return translateTextToEn('Прямой 100% Bit-Perfect тракт без динамической обработки сигнала.');
  }

  function syncLateNightBadgeOnly() {
    const badgeEl = document.getElementById('late-night-gain-badge');
    const selectEl = document.getElementById('late-night-drc-select');
    const subEl = document.getElementById('late-night-drc-subtitle');

    const mode = (state.lateNightDrcMode === 'gentle' || state.lateNightDrcMode === 'concert')
      ? state.lateNightDrcMode
      : 'off';
    const isEnabled = mode !== 'off';
    state.lateNightDrcEnabled = isEnabled;
    state.lateNightDrcMode = mode;
    if (isEnabled) {
      state.lateNightDrcProfile = mode;
    }

    if (selectEl && selectEl.value !== mode && Array.from(selectEl.options).some(o => o.value === mode)) {
      selectEl.value = mode;
    }
    if (subEl) {
      subEl.textContent = (isEnabled && state.lateNightDrcSubtitle)
        ? translateTextToEn(state.lateNightDrcSubtitle)
        : defaultLateNightSubtitle(mode);
    }
    if (!badgeEl) return;
    if (!isEnabled) {
      badgeEl.classList.remove('active');
      badgeEl.textContent = '100% Bit-Perfect';
    } else {
      badgeEl.classList.add('active');
      const g = Number(state.lateNightDrcGainDb) || 0;
      if (Math.abs(g) >= 0.15 && state.playerState === 'playing') {
        const sign = g >= 0 ? '+' : '';
        badgeEl.textContent = `64-bit • ${sign}${g.toFixed(1)} dB`;
      } else {
        badgeEl.textContent = mode === 'concert'
          ? (IS_EN ? 'ACTIVE • CONCERT' : 'АКТИВЕН • КОНЦЕРТ')
          : (IS_EN ? 'ACTIVE • GENTLE' : 'АКТИВЕН • ДЕЛИКАТНЫЙ');
      }
    }
  }

  function updateLateNightDRCUI(data, opts = {}) {
    if (!data || typeof data !== 'object') return;
    if (data.profile !== undefined) {
      const nextProf = String(data.profile || 'gentle');
      if (nextProf === 'gentle' || nextProf === 'concert') {
        state.lateNightDrcProfile = nextProf;
      }
    }
    if (data.enabled !== undefined) {
      state.lateNightDrcEnabled = Boolean(data.enabled);
    }
    if (data.mode !== undefined) {
      const nextMode = String(data.mode || 'off');
      if (nextMode === 'gentle' || nextMode === 'concert') {
        state.lateNightDrcProfile = nextMode;
        state.lateNightDrcEnabled = true;
        state.lateNightDrcMode = nextMode;
      } else {
        state.lateNightDrcEnabled = false;
        state.lateNightDrcMode = 'off';
      }
    } else {
      state.lateNightDrcMode = state.lateNightDrcEnabled ? (state.lateNightDrcProfile || 'gentle') : 'off';
    }
    if (data.subtitle !== undefined) {
      state.lateNightDrcSubtitle = String(data.subtitle || '');
    } else if (data.profile_subtitle !== undefined && state.lateNightDrcEnabled) {
      state.lateNightDrcSubtitle = String(data.profile_subtitle || '');
    }
    if (data.current_gain_db !== undefined) {
      state.lateNightDrcGainDb = Number(data.current_gain_db) || 0;
    }
    syncLateNightBadgeOnly();
    const anyPreStillActive = Boolean(
      state.lateNightDrcEnabled ||
      (state.masteringDeclipMode && state.masteringDeclipMode !== 'off') ||
      (state.masteringDeesserMode && state.masteringDeesserMode !== 'off') ||
      state.roomCorrectionActive ||
      (state.roomAcoustic && state.roomAcoustic.enabled && state.roomAcoustic.active_profile)
    );
    state.isClockSyncedDsp = anyPreStillActive;
    if (!anyPreStillActive && state.isBitPerfect === false) {
      state.isBitPerfect = undefined;
    }
    applyDeviceCapabilityPermissionsUI();
    if (!opts.skipSignalRefresh) {
      renderNowPlaying();
      updateSignalPathDetails();
    }
  }

  function pushLateNightDRCToServer() {
    const drcSel = document.getElementById('late-night-drc-select');
    if (!drcSel) return;
    if (state.allowLateNightMode === false) {
      drcSel.value = state.lateNightDrcMode || 'off';
      showToast(IS_EN ? 'Late-Night DRC access is disabled for this device on Mac' : 'Доступ к ночному режиму отключён для этого устройства в настройках Mac');
      return;
    }
    const nextMode = (drcSel.value === 'gentle' || drcSel.value === 'concert') ? drcSel.value : 'off';
    state.lateNightDrcMode = nextMode;
    state.lateNightDrcEnabled = nextMode !== 'off';
    if (nextMode !== 'off') {
      state.lateNightDrcProfile = nextMode;
    }
    state.lateNightDrcSubtitle = '';
    triggerHaptic('light');
    syncLateNightBadgeOnly();
    send({
      action: 'set_late_night_drc',
      params: {
        mode: nextMode
      }
    });
    if (nextMode === 'off') {
      showToast(IS_EN ? '🌙 Late-Night DRC Off (100% Bit-Perfect)' : '🌙 Ночной режим выключен (100% Bit-Perfect)');
    } else if (nextMode === 'concert') {
      showToast(IS_EN ? '🌙 Night Concert Mode enabled' : '🌙 Включён режим «Ночной концерт»');
    } else {
      showToast(IS_EN ? '🌙 Gentle Late-Night DRC enabled' : '🌙 Включён деликатный ночной режим');
    }
  }

  function defaultDeClipSubtitle(mode) {
    if (mode === 'auto') {
      return IS_EN
        ? 'Automatically reconstructs shaved 0 dBFS brickwall plateaus on compressed masters while leaving DR11+ audiophile recordings untouched.'
        : 'Автоматически достраивает срезанные «полки» кирпичного лимитера на зажатых ремастерах, не вмешиваясь в чистые записи DR11+.';
    }
    if (mode === 'gentle') {
      return IS_EN
        ? 'Smooth 64-bit cubic Hermite transient peak restoration up to +2.8 dB with C1 slope continuity.'
        : 'Деликатная 64-битная кубическая Эрмитова реконструкция транзиентов до +2.8 дБ с гладкой сшивкой склонов.';
    }
    if (mode === 'studio') {
      return IS_EN
        ? 'Deep mastering crest reconstruction up to +4.2 dB for heavily clipped Loudness War (DR4–DR7) rock, metal & pop remasters.'
        : 'Глубокое восстановление динамических пиков до +4.2 дБ для жёстко зажатых ремастеров «Войны громкости» (DR4–DR7).';
    }
    return IS_EN
      ? '100% Bit-Perfect passthrough without waveform peak reconstruction.'
      : 'Прямой 100% Bit-Perfect тракт без реконструкции срезанных верхушек волны.';
  }

  function defaultDeEsserSubtitle(mode) {
    if (mode === 'gentle') {
      return IS_EN
        ? 'Level-independent relative detector (7.0 kHz) taming piercing glare up to -3.5 dB on planar headphones and bright tweeters while preserving cymbal air.'
        : 'Относительный детектор в духе Weiss DAC501 (7.0 кГц): смягчает колкие сибилянты до -3.5 дБ на планарах и ярких АС, сохраняя воздух тарелок.';
    }
    if (mode === 'vocal') {
      return IS_EN
        ? 'Mastering-grade relative sibilance control (6.5 kHz, up to -6.0 dB, 0.8 ms attack) eliminating harsh vocal spikes at any volume.'
        : 'Студийное подавление резких вокальных «с/ц/ш» (6.5 кГц, до -6.0 дБ, атака 0.8 мс) с одинаковой точностью на шёпоте и в тутти.';
    }
    return IS_EN
      ? '100% Bit-Perfect passthrough without high-frequency dynamic sibilance control.'
      : 'Прямой 100% Bit-Perfect тракт без динамического подавления сибилянтов.';
  }

  function syncMasteringRestorationBadgesOnly() {
    const dcBadge = document.getElementById('declip-gain-badge');
    const dcSelect = document.getElementById('mastering-declip-select');
    const dcSub = document.getElementById('mastering-declip-subtitle');
    const dcLabel = document.getElementById('signal-declip-label');

    const dcMode = (state.masteringDeclipMode === 'auto' || state.masteringDeclipMode === 'gentle' || state.masteringDeclipMode === 'studio')
      ? state.masteringDeclipMode
      : 'off';
    state.masteringDeclipMode = dcMode;

    if (dcLabel && IS_EN) {
      dcLabel.textContent = '⚡️ Mastering De-Clipper';
    }
    if (dcSelect) {
      if (IS_EN) {
        const enMap = {
          off: 'Off (100% Bit-Perfect)',
          auto: 'Auto — Smart Guard (DR ≤ 10)',
          gentle: 'Gentle (up to +2.8 dB peaks)',
          studio: 'Studio Restoration (up to +4.2 dB)'
        };
        Array.from(dcSelect.options).forEach(opt => {
          if (enMap[opt.value]) opt.textContent = enMap[opt.value];
        });
      }
      if (dcSelect.value !== dcMode && Array.from(dcSelect.options).some(o => o.value === dcMode)) {
        dcSelect.value = dcMode;
      }
    }
    if (dcSub) {
      dcSub.textContent = (dcMode !== 'off' && state.masteringDeclipSubtitle)
        ? translateTextToEn(state.masteringDeclipSubtitle)
        : defaultDeClipSubtitle(dcMode);
    }
    if (dcBadge) {
      if (dcMode === 'off') {
        dcBadge.classList.remove('active');
        dcBadge.textContent = '100% Bit-Perfect';
      } else {
        dcBadge.classList.add('active');
        const restored = Number(state.masteringDeclipRestoredDb) || 0;
        if (dcMode === 'auto' && state.masteringDeclipAutoBypassed) {
          dcBadge.textContent = IS_EN ? 'DR11+ • BYPASS' : 'DR11+ • ЧИСТЫЙ';
        } else if (restored >= 0.1 && state.playerState === 'playing') {
          dcBadge.textContent = `64-bit • +${restored.toFixed(1)} dB`;
        } else {
          dcBadge.textContent = dcMode === 'studio'
            ? (IS_EN ? 'ACTIVE • STUDIO' : 'АКТИВЕН • СТУДИЯ')
            : (dcMode === 'gentle'
              ? (IS_EN ? 'ACTIVE • GENTLE' : 'АКТИВЕН • ДЕЛИКАТНЫЙ')
              : (IS_EN ? 'SMART GUARD' : 'УМНАЯ ЗАЩИТА'));
        }
      }
    }

    const deBadge = document.getElementById('deesser-gain-badge');
    const deSelect = document.getElementById('mastering-deesser-select');
    const deSub = document.getElementById('mastering-deesser-subtitle');
    const deLabel = document.getElementById('signal-deesser-label');

    const deMode = (state.masteringDeesserMode === 'gentle' || state.masteringDeesserMode === 'vocal')
      ? state.masteringDeesserMode
      : 'off';
    state.masteringDeesserMode = deMode;

    if (deLabel && IS_EN) {
      deLabel.textContent = '💎 Weiss Dynamic De-Esser';
    }
    if (deSelect) {
      if (IS_EN) {
        const enDeMap = {
          off: 'Off (100% Bit-Perfect)',
          gentle: 'Gentle — Planars / Bright HF (up to -3.5 dB)',
          vocal: 'Weiss Studio — Harsh Sibilance (up to -6.0 dB)'
        };
        Array.from(deSelect.options).forEach(opt => {
          if (enDeMap[opt.value]) opt.textContent = enDeMap[opt.value];
        });
      }
      if (deSelect.value !== deMode && Array.from(deSelect.options).some(o => o.value === deMode)) {
        deSelect.value = deMode;
      }
    }
    if (deSub) {
      deSub.textContent = (deMode !== 'off' && state.masteringDeesserSubtitle)
        ? translateTextToEn(state.masteringDeesserSubtitle)
        : defaultDeEsserSubtitle(deMode);
    }
    if (deBadge) {
      if (deMode === 'off') {
        deBadge.classList.remove('active');
        deBadge.textContent = '100% Bit-Perfect';
      } else {
        deBadge.classList.add('active');
        const gr = Number(state.masteringDeesserGainDb) || 0;
        if (Math.abs(gr) >= 0.15 && state.playerState === 'playing') {
          deBadge.textContent = `64-bit • ${gr <= 0 ? '' : '-'}${gr.toFixed(1)} dB`;
        } else {
          deBadge.textContent = deMode === 'vocal'
            ? (IS_EN ? 'ACTIVE • WEISS' : 'АКТИВЕН • WEISS')
            : (IS_EN ? 'ACTIVE • GENTLE' : 'АКТИВЕН • ДЕЛИКАТНЫЙ');
        }
      }
    }
  }

  function updateMasteringRestorationUI(data, opts = {}) {
    if (!data || typeof data !== 'object') return;
    if (data.declip_mode !== undefined) {
      const m = String(data.declip_mode || 'off');
      state.masteringDeclipMode = (m === 'auto' || m === 'gentle' || m === 'studio') ? m : 'off';
    }
    if (data.declip_subtitle !== undefined) {
      state.masteringDeclipSubtitle = String(data.declip_subtitle || '');
    }
    if (data.restored_peak_db !== undefined) {
      state.masteringDeclipRestoredDb = Number(data.restored_peak_db) || 0;
    }
    if (data.reconstructed_clips_count !== undefined) {
      state.masteringDeclipClipsCount = Number(data.reconstructed_clips_count) || 0;
    }
    if (data.auto_bypassed_clean_master !== undefined) {
      state.masteringDeclipAutoBypassed = Boolean(data.auto_bypassed_clean_master);
    }
    if (data.deesser_mode !== undefined) {
      const m = String(data.deesser_mode || 'off');
      state.masteringDeesserMode = (m === 'gentle' || m === 'vocal') ? m : 'off';
    }
    if (data.deesser_subtitle !== undefined) {
      state.masteringDeesserSubtitle = String(data.deesser_subtitle || '');
    }
    if (data.deesser_gain_db !== undefined) {
      state.masteringDeesserGainDb = Number(data.deesser_gain_db) || 0;
    }
    syncMasteringRestorationBadgesOnly();
    applyDeviceCapabilityPermissionsUI();
    if (!opts.skipSignalRefresh) {
      renderNowPlaying();
      updateSignalPathDetails();
    }
  }

  function pushMasteringDeClipToServer() {
    const sel = document.getElementById('mastering-declip-select');
    if (!sel) return;
    if (state.allowDspPresetSelection === false) {
      sel.value = state.masteringDeclipMode || 'off';
      showToast(IS_EN ? 'DSP parameters access is locked for this device on Mac' : 'Управление параметрами DSP отключено для этого устройства в настройках Mac');
      return;
    }
    const nextMode = (sel.value === 'auto' || sel.value === 'gentle' || sel.value === 'studio') ? sel.value : 'off';
    state.masteringDeclipMode = nextMode;
    state.masteringDeclipSubtitle = '';
    triggerHaptic('light');
    syncMasteringRestorationBadgesOnly();
    send({
      action: 'set_mastering_restoration',
      params: {
        declip_mode: nextMode
      }
    });
    if (nextMode === 'off') {
      showToast(IS_EN ? '⚡️ De-Clipper Off (100% Bit-Perfect)' : '⚡️ Реставратор клиппинга выключен');
    } else if (nextMode === 'studio') {
      showToast(IS_EN ? '⚡️ Studio Mastering De-Clipper enabled' : '⚡️ Включена студийная реставрация пиков');
    } else if (nextMode === 'gentle') {
      showToast(IS_EN ? '⚡️ Gentle De-Clipper enabled' : '⚡️ Включён деликатный реставратор пиков');
    } else {
      showToast(IS_EN ? '⚡️ Auto Smart Guard De-Clipper enabled' : '⚡️ Включён умный реставратор клиппинга');
    }
  }

  function pushMasteringDeEsserToServer() {
    const sel = document.getElementById('mastering-deesser-select');
    if (!sel) return;
    if (state.allowDspPresetSelection === false) {
      sel.value = state.masteringDeesserMode || 'off';
      showToast(IS_EN ? 'DSP parameters access is locked for this device on Mac' : 'Управление параметрами DSP отключено для этого устройства в настройках Mac');
      return;
    }
    const nextMode = (sel.value === 'gentle' || sel.value === 'vocal') ? sel.value : 'off';
    state.masteringDeesserMode = nextMode;
    state.masteringDeesserSubtitle = '';
    triggerHaptic('light');
    syncMasteringRestorationBadgesOnly();
    send({
      action: 'set_mastering_restoration',
      params: {
        deesser_mode: nextMode
      }
    });
    if (nextMode === 'off') {
      showToast(IS_EN ? '💎 Weiss De-Esser Off (100% Bit-Perfect)' : '💎 Де-эссер выключен (100% Bit-Perfect)');
    } else if (nextMode === 'vocal') {
      showToast(IS_EN ? '💎 Weiss Studio De-Esser enabled' : '💎 Включён студийный Weiss De-Esser');
    } else {
      showToast(IS_EN ? '💎 Gentle Planar De-Esser enabled' : '💎 Включён деликатный De-Esser для планаров/ВЧ');
    }
  }

  function setupDSPControls() {
    const presetSel = document.getElementById('dsp-preset-select');
    if (presetSel) {
      presetSel.addEventListener('change', pushDSPSettingsToServer);
    }
    const deClipSel = document.getElementById('mastering-declip-select');
    if (deClipSel) {
      deClipSel.addEventListener('change', pushMasteringDeClipToServer);
    }
    const deEsserSel = document.getElementById('mastering-deesser-select');
    if (deEsserSel) {
      deEsserSel.addEventListener('change', pushMasteringDeEsserToServer);
    }
    const drcSel = document.getElementById('late-night-drc-select');
    if (drcSel) {
      drcSel.addEventListener('change', pushLateNightDRCToServer);
    }
  }

// === MODULE: 26-room-acoustic-measurement.js ===
  // ==========================================================================
  // Quick Room Frequency Response Measurement (iPhone / iPad Mic + Auto-PEQ 64-bit)
  // ==========================================================================
  const ROOM_ISO_BANDS_HZ = [
    20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160,
    200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600,
    2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
  ];

  let activeRoomMeasureCtx = null;
  let activeRoomMeasureStream = null;
  let activeRoomMeasureTimer = null;

  function roomDbToSvgPoints(valuesDb) {
    if (!Array.isArray(valuesDb) || valuesDb.length === 0) return '';
    const count = valuesDb.length;
    const width = 360;
    const midY = 56; // 0 dB
    const scalePerDb = 3.1; // +-16 dB fits 6..106 inside 112px viewBox
    const pts = [];
    for (let i = 0; i < count; i++) {
      const x = count > 1 ? ((i / (count - 1)) * width) : 0;
      const clampedDb = Math.max(-16, Math.min(16, Number(valuesDb[i]) || 0));
      const y = midY - clampedDb * scalePerDb;
      pts.push(`${x.toFixed(1)},${y.toFixed(1)}`);
    }
    return pts.join(' ');
  }

  function defaultHarmanTargetCurveDb() {
    return ROOM_ISO_BANDS_HZ.map((f) => {
      if (f <= 55) return 3.2;
      if (f < 180) {
        const t = Math.log10(f / 55) / Math.log10(180 / 55);
        return 3.2 * (1 - t);
      }
      if (f <= 1200) return 0;
      const oct = Math.log2(f / 1200);
      return Math.max(-3.0, -0.65 * oct);
    });
  }

  function renderRoomEqChart(profile, liveMeasuredOverrideDb = null) {
    const lineTarget = document.getElementById('room-eq-line-target');
    const lineMeasured = document.getElementById('room-eq-line-measured');
    const lineCorrected = document.getElementById('room-eq-line-corrected');
    const bandsListEl = document.getElementById('room-eq-bands-list');

    const rawTarget = profile && (profile.target_curve_db || profile.target_db);
    const rawMeasured = profile && (profile.measured_response_db || profile.measured_db);
    const rawCorrected = profile && (profile.corrected_response_db || profile.corrected_db);

    const targetArr = (Array.isArray(rawTarget) && rawTarget.length > 0)
      ? rawTarget
      : defaultHarmanTargetCurveDb();
    const measuredArr = Array.isArray(liveMeasuredOverrideDb)
      ? liveMeasuredOverrideDb
      : (Array.isArray(rawMeasured) ? rawMeasured : []);
    const correctedArr = (!liveMeasuredOverrideDb && Array.isArray(rawCorrected))
      ? rawCorrected
      : [];

    if (lineTarget) lineTarget.setAttribute('points', roomDbToSvgPoints(targetArr));
    if (lineMeasured) lineMeasured.setAttribute('points', roomDbToSvgPoints(measuredArr));
    if (lineCorrected) lineCorrected.setAttribute('points', roomDbToSvgPoints(correctedArr));

    if (bandsListEl) {
      const eqBands = (profile && Array.isArray(profile.eq_bands)) ? profile.eq_bands : [];
      if (!liveMeasuredOverrideDb && eqBands.length > 0) {
        bandsListEl.innerHTML = '';
        eqBands.forEach((b) => {
          if (!b || b.enabled === false) return;
          const f = Number(b.frequency_hz || b.frequencyHz || 0);
          const g = Number(b.gain_db || b.gainDB || 0);
          const q = Number(b.q || 1);
          const freqStr = f >= 1000 ? `${(f / 1000).toFixed(f % 1000 === 0 ? 0 : 1)}${IS_EN ? 'k' : 'к'}` : `${Math.round(f)}`;
          const pill = document.createElement('span');
          pill.className = 'room-eq-band-pill';
          pill.textContent = IS_EN
            ? `${freqStr}Hz ${g >= 0 ? '+' : ''}${g.toFixed(1)}dB Q${q.toFixed(1)}`
            : `${freqStr}Гц ${g >= 0 ? '+' : ''}${g.toFixed(1)}дБ Q${q.toFixed(1)}`;
          bandsListEl.appendChild(pill);
        });
        bandsListEl.classList.remove('hidden');
      } else {
        bandsListEl.classList.add('hidden');
        bandsListEl.innerHTML = '';
      }
    }
  }

  function updateRoomAcousticUI(raw, options = {}) {
    if (!raw || typeof raw !== 'object') return;
    const payload = (raw.room_acoustic && typeof raw.room_acoustic === 'object') ? raw.room_acoustic : raw;
    if (payload.status === 'error' && payload.message) {
      showToast(String(payload.message));
      return;
    }

    if (payload.enabled !== undefined) {
      state.roomAcoustic.enabled = Boolean(payload.enabled);
    }
    if (payload.is_test_signal_playing !== undefined) {
      state.roomAcoustic.is_test_signal_playing = Boolean(payload.is_test_signal_playing);
    }
    if (payload.active_profile_id !== undefined) {
      state.roomAcoustic.active_profile_id = String(payload.active_profile_id || '');
    }
    if (Array.isArray(payload.profiles)) {
      state.roomAcoustic.profiles = payload.profiles;
    }
    if (payload.active_profile !== undefined) {
      state.roomAcoustic.active_profile = payload.active_profile || null;
    } else if (Array.isArray(state.roomAcoustic.profiles)) {
      state.roomAcoustic.active_profile = state.roomAcoustic.profiles.find(
        (p) => p && String(p.id) === state.roomAcoustic.active_profile_id
      ) || null;
    }

    const activeProf = state.roomAcoustic.active_profile;
    state.roomIsPlayingTestSignal = Boolean(state.roomAcoustic.is_test_signal_playing);
    state.roomActiveProfileId = String(state.roomAcoustic.active_profile_id || '');
    state.roomCorrectionActive = Boolean(state.roomAcoustic.enabled && activeProf);
    state.roomProfileName = activeProf && activeProf.name ? String(activeProf.name) : '';

    if (
      !state.roomIsPlayingTestSignal &&
      state.isMeasuringRoom &&
      !activeRoomMeasureCtx &&
      (!state.nativePickerOpenedAt || (Date.now() - state.nativePickerOpenedAt > 2500))
    ) {
      state.isMeasuringRoom = false;
      state.awaitingNativeRoomFilePicker = false;
      const progWrap = document.getElementById('room-measure-progress-wrap');
      const stopBtn = document.getElementById('btn-stop-room-measure');
      if (progWrap) progWrap.classList.add('hidden');
      if (stopBtn) stopBtn.classList.add('hidden');
    }

    const badgeEl = document.getElementById('room-eq-status-badge');
    const toggleBtn = document.getElementById('btn-room-eq-toggle');
    const selectEl = document.getElementById('room-profile-select');
    const delBtn = document.getElementById('btn-delete-room-profile');
    const descEl = document.getElementById('room-eq-desc');
    const startLabelEl = document.getElementById('btn-start-room-measure-label');
    const uploadBtnEl = document.getElementById('btn-upload-room-audio');

    const hasProfiles = Array.isArray(state.roomAcoustic.profiles) && state.roomAcoustic.profiles.length > 0;
    const isActive = Boolean(state.roomAcoustic.enabled && activeProf);
    const canControlRoomEq = (state.allowRoomMeasurement !== false) || (state.allowDspPresetSelection !== false);

    if (badgeEl) {
      badgeEl.classList.remove('authentic', 'neutral', 'warning');
      if (state.isMeasuringRoom || state.roomAcoustic.is_test_signal_playing) {
        badgeEl.classList.add('warning');
        badgeEl.textContent = IS_EN ? 'MEASURING...' : 'ЗАМЕР АЧХ...';
      } else if (isActive) {
        badgeEl.classList.add('authentic');
        badgeEl.textContent = IS_EN ? 'ACTIVE • CLOUD' : 'АКТИВНА • CLOUD';
      } else {
        badgeEl.classList.add('neutral');
        badgeEl.textContent = hasProfiles ? (IS_EN ? 'BYPASS' : 'ВЫКЛ') : (IS_EN ? 'NO PROFILE' : 'НЕТ ЗАМЕРА');
      }
    }

    if (toggleBtn) {
      toggleBtn.disabled = !hasProfiles || !canControlRoomEq;
      toggleBtn.classList.toggle('active', isActive);
      toggleBtn.setAttribute('aria-pressed', isActive ? 'true' : 'false');
      toggleBtn.textContent = isActive ? (IS_EN ? 'On' : 'Вкл') : (IS_EN ? 'Off' : 'Выкл');
    }

    if (selectEl) {
      selectEl.innerHTML = '';
      if (!hasProfiles) {
        const emptyOpt = document.createElement('option');
        emptyOpt.value = '';
        emptyOpt.textContent = IS_EN ? 'No room profiles yet' : 'Нет профилей замера';
        selectEl.appendChild(emptyOpt);
        selectEl.disabled = true;
      } else {
        selectEl.disabled = !canControlRoomEq;
        state.roomAcoustic.profiles.forEach((p) => {
          if (!p || !p.id) return;
          const opt = document.createElement('option');
          opt.value = String(p.id);
          const bandsCnt = Array.isArray(p.eq_bands) ? p.eq_bands.length : 0;
          opt.textContent = `${p.name || (IS_EN ? 'Room' : 'Комната')} (${bandsCnt} PEQ)`;
          selectEl.appendChild(opt);
        });
        selectEl.value = state.roomActiveProfileId || '';
      }
    }

    if (delBtn) {
      delBtn.classList.toggle('hidden', !activeProf || state.allowRoomMeasurement === false);
    }

    const canLiveGetUserMedia = Boolean(
      typeof navigator !== 'undefined' &&
      navigator.mediaDevices &&
      typeof navigator.mediaDevices.getUserMedia === 'function'
    );
    if (startLabelEl) {
      startLabelEl.textContent = canLiveGetUserMedia
        ? (IS_EN ? 'Measure Room Mic' : 'Быстрый замер микрофоном')
        : (IS_EN ? 'Measure via iPhone / iPad Mic' : 'Замер микрофоном iPhone / iPad');
    }
    if (uploadBtnEl) {
      uploadBtnEl.classList.toggle('hidden', !canLiveGetUserMedia);
    }

    if (descEl && !state.isMeasuringRoom) {
      if (activeProf) {
        const preGain = Number(activeProf.preamp_gain_db !== undefined ? activeProf.preamp_gain_db : (activeProf.preampGainDB || 0));
        const micLabel = activeProf.measured_on_device || activeProf.mic_device_name || activeProf.micDeviceName || 'iOS Mic';
        descEl.textContent = isActive
          ? `Активен профиль «${activeProf.name}» (${micLabel} • Headroom ${preGain.toFixed(1)} дБ • синхронизирован с iCloud Drive).`
          : `Профиль «${activeProf.name}» сохранён в облаке (${micLabel}). Нажмите «Вкл» для активации 64-bit Auto-PEQ.`;
      } else {
        descEl.textContent = 'Сядьте в точку прослушивания с iPhone / iPad: Mac подаст эталонный розовый шум на АС и построит 64-bit Auto-PEQ фильтр с синхронизацией в iCloud.';
      }
    }

    if (!state.isMeasuringRoom) {
      renderRoomEqChart(activeProf);
    }
    if (!options.skipPermissionsSync) {
      applyDeviceCapabilityPermissionsUI({ fromRoomAcousticUI: true });
    }

    if (!options.skipSignalRefresh) {
      updateSignalPathDetails();
    }
  }

  function stopRoomMeasurementSession(sendStopToServer = true) {
    state.isMeasuringRoom = false;
    state.awaitingNativeRoomFilePicker = false;
    state.nativePickerOpenedAt = 0;
    if (activeRoomMeasureTimer) {
      clearInterval(activeRoomMeasureTimer);
      activeRoomMeasureTimer = null;
    }
    if (activeRoomMeasureStream) {
      try {
        activeRoomMeasureStream.getTracks().forEach((tr) => tr.stop());
      } catch (e) {}
      activeRoomMeasureStream = null;
    }
    if (activeRoomMeasureCtx) {
      try { activeRoomMeasureCtx.close(); } catch (e) {}
      activeRoomMeasureCtx = null;
    }
    if (sendStopToServer && state.connected) {
      send({ action: 'stop_room_test_signal' });
    }
    const progWrap = document.getElementById('room-measure-progress-wrap');
    const stopBtn = document.getElementById('btn-stop-room-measure');
    if (progWrap) progWrap.classList.add('hidden');
    if (stopBtn) stopBtn.classList.add('hidden');
    updateRoomAcousticUI(state.roomAcoustic, { skipSignalRefresh: true });
  }

  function triggerNativeIosMicCapture() {
    if (state.allowRoomMeasurement === false) {
      showToast('Быстрое измерение АЧХ отключено для этого устройства в настройках Mac');
      return;
    }
    const fileInput = document.getElementById('room-mic-file-input');
    if (!fileInput) return;

    state.isMeasuringRoom = true;
    send({ action: 'start_room_test_signal' });

    const progWrap = document.getElementById('room-measure-progress-wrap');
    const progFill = document.getElementById('room-measure-progress-fill');
    const statusTxt = document.getElementById('room-measure-status-text');
    const stopBtn = document.getElementById('btn-stop-room-measure');
    if (progWrap) progWrap.classList.remove('hidden');
    if (progFill) progFill.style.width = '35%';
    if (statusTxt) {
      statusTxt.textContent = 'Розовый шум подан на АС — запишите 5–7 сек на микрофон iPhone/iPad и нажмите «Готово»';
    }
    if (stopBtn) stopBtn.classList.remove('hidden');
    applyDeviceCapabilityPermissionsUI();

    state.awaitingNativeRoomFilePicker = true;
    state.nativePickerOpenedAt = Date.now();
    fileInput.value = '';
    fileInput.click();
  }

  async function startLiveWebAudioRoomMeasurement() {
    if (state.allowRoomMeasurement === false) {
      showToast('Быстрое измерение АЧХ отключено для этого устройства в настройках Mac');
      return;
    }
    const canLive = Boolean(
      typeof navigator !== 'undefined' &&
      navigator.mediaDevices &&
      typeof navigator.mediaDevices.getUserMedia === 'function'
    );
    if (!canLive) {
      triggerNativeIosMicCapture();
      return;
    }

    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: false,
          noiseSuppression: false,
          autoGainControl: false
        }
      });
      activeRoomMeasureStream = stream;
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      const ctx = new AudioCtx();
      activeRoomMeasureCtx = ctx;
      if (ctx.state === 'suspended') {
        await ctx.resume();
      }

      const source = ctx.createMediaStreamSource(stream);
      const analyser = ctx.createAnalyser();
      analyser.fftSize = 8192;
      analyser.smoothingTimeConstant = 0.22;
      source.connect(analyser);

      state.isMeasuringRoom = true;
      send({ action: 'start_room_test_signal' });

      const progWrap = document.getElementById('room-measure-progress-wrap');
      const progFill = document.getElementById('room-measure-progress-fill');
      const statusTxt = document.getElementById('room-measure-status-text');
      const stopBtn = document.getElementById('btn-stop-room-measure');
      if (progWrap) progWrap.classList.remove('hidden');
      if (progFill) progFill.style.width = '5%';
      if (stopBtn) stopBtn.classList.remove('hidden');
      applyDeviceCapabilityPermissionsUI();

      const warmupMs = state.isDlnaActive ? 1900 : 650;
      const captureMs = 5400;
      const totalMs = warmupMs + captureMs;
      const startedAt = performance.now();
      const freqBins = new Float32Array(analyser.frequencyBinCount);
      const nyquist = ctx.sampleRate / 2;
      const binHz = nyquist / analyser.frequencyBinCount;
      const bandLinearSums = new Float64Array(ROOM_ISO_BANDS_HZ.length);
      let accumulatedFrames = 0;

      if (statusTxt) {
        statusTxt.textContent = 'Прогрев акустики калибровочным розовым шумом...';
      }

      activeRoomMeasureTimer = setInterval(() => {
        if (!state.isMeasuringRoom) return;
        const elapsed = performance.now() - startedAt;
        const pct = Math.min(100, Math.round((elapsed / totalMs) * 100));
        if (progFill) progFill.style.width = `${pct}%`;

        if (elapsed >= warmupMs) {
          analyser.getFloatFrequencyData(freqBins);
          const instantDb = new Array(ROOM_ISO_BANDS_HZ.length).fill(0);

          for (let b = 0; b < ROOM_ISO_BANDS_HZ.length; b++) {
            const fc = ROOM_ISO_BANDS_HZ[b];
            const fLow = fc / 1.122462;
            const fHigh = fc * 1.122462;
            const kStart = Math.max(1, Math.floor(fLow / binHz));
            const kEnd = Math.min(freqBins.length - 1, Math.ceil(fHigh / binHz));
            let powerSum = 0;
            let count = 0;
            for (let k = kStart; k <= kEnd; k++) {
              const db = freqBins[k];
              if (Number.isFinite(db) && db > -150) {
                powerSum += Math.pow(10, db / 10);
                count++;
              }
            }
            const avgPower = count > 0 ? (powerSum / count) : 1e-12;
            // Pink noise has 1/f power density -> multiply by fc for flat 1/3-octave acoustic response
            const pinkWeighted = avgPower * fc;
            bandLinearSums[b] += pinkWeighted;
            instantDb[b] = 10 * Math.log10(Math.max(pinkWeighted, 1e-15));
          }
          accumulatedFrames++;

          // Normalize live curve around 250 Hz..2 kHz midrange for live visual feedback
          let midSum = 0;
          let midCnt = 0;
          for (let i = 11; i <= 20; i++) {
            midSum += instantDb[i];
            midCnt++;
          }
          const midRef = midCnt > 0 ? (midSum / midCnt) : 0;
          const relLive = instantDb.map((v, idx) => {
            const f = ROOM_ISO_BANDS_HZ[idx];
            const memsComp = f < 55 ? Math.min(5.5, 1.8 * Math.log2(55 / Math.max(f, 20))) : 0;
            return (v - midRef) + memsComp;
          });
          renderRoomEqChart(null, relLive);

          const remSec = Math.max(0, (totalMs - elapsed) / 1000).toFixed(1);
          if (statusTxt) {
            statusTxt.textContent = `Усреднение спектра в точке прослушивания (${remSec} с)...`;
          }
        }

        if (elapsed >= totalMs) {
          const framesCount = Math.max(1, accumulatedFrames);
          const rawBandsDb = [];
          for (let b = 0; b < ROOM_ISO_BANDS_HZ.length; b++) {
            const f = ROOM_ISO_BANDS_HZ[b];
            const meanPwr = bandLinearSums[b] / framesCount;
            const memsComp = f < 55 ? Math.min(5.5, 1.8 * Math.log2(55 / Math.max(f, 20))) : 0;
            rawBandsDb.push(10 * Math.log10(Math.max(meanPwr, 1e-15)) + memsComp);
          }

          stopRoomMeasurementSession(true);

          const dateLabel = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
          const outLabel = state.audioDeviceName || (IS_EN ? 'Room' : 'Комната');
          const profName = `${outLabel} (${dateLabel})`;
          const sent = send({
            action: 'submit_room_measurement',
            params: {
              name: profName,
              device_name: state.deviceName || 'iPhone / iPad Mic',
              bands_db: rawBandsDb
            }
          });
          if (sent === true) {
            showToast('Замер АЧХ завершён — профиль Auto-PEQ сохранён и синхронизирован с iCloud');
          } else {
            showToast(IS_EN
              ? 'Connection lost — room measurement could not be sent to Mac'
              : 'Соединение потеряно — замер АЧХ не удалось отправить на Mac');
          }
        }
      }, 85);
    } catch (err) {
      stopRoomMeasurementSession(false);
      if (err && (
        err.name === 'NotAllowedError' ||
        err.name === 'PermissionDeniedError' ||
        err.name === 'NotFoundError' ||
        err.name === 'AbortError' ||
        err.name === 'NotReadableError'
      )) {
        showToast(IS_EN
          ? 'Microphone access denied or unavailable'
          : 'Доступ к микрофону запрещён или микрофон недоступен');
        return;
      }
      triggerNativeIosMicCapture();
    }
  }

  async function handleUploadedRoomAudioFile(file) {
    if (!file) {
      stopRoomMeasurementSession(true);
      return;
    }
    send({ action: 'stop_room_test_signal' });
    const progWrap = document.getElementById('room-measure-progress-wrap');
    const progFill = document.getElementById('room-measure-progress-fill');
    const statusTxt = document.getElementById('room-measure-status-text');
    if (progWrap) progWrap.classList.remove('hidden');
    if (progFill) progFill.style.width = '80%';
    if (statusTxt) {
      statusTxt.textContent = 'Расчёт 4096-pt vDSP FFT и синтез 64-bit Auto-PEQ на Mac...';
    }

    try {
      const rawName = String(file.name || 'capture.m4a');
      const dotIdx = rawName.lastIndexOf('.');
      const ext = dotIdx >= 0 ? rawName.slice(dotIdx + 1).toLowerCase() : 'm4a';
      const dateLabel = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
      const outLabel = state.audioDeviceName || 'Комната';
      const profName = `${outLabel} (${dateLabel})`;

      const qs = new URLSearchParams({
        ext,
        name: profName,
        device_name: state.deviceName || 'iPhone / iPad Mic',
        device_id: state.deviceId
      });
      const resp = await fetch(`/api/room-measurement/analyze?${qs.toString()}`, {
        method: 'POST',
        headers: buildDeviceAuthHeaders({
          'Content-Type': file.type || 'application/octet-stream'
        }),
        body: file
      });
      const json = await resp.json();
      stopRoomMeasurementSession(false);
      if (!resp.ok || json.status === 'error') {
        showToast(json.error || json.message || 'Не удалось распознать аудиозапись микрофона');
        return;
      }
      updateRoomAcousticUI(json.room_acoustic || json);
      showToast('Профиль АЧХ комнаты создан и синхронизирован с iCloud');
    } catch (err) {
      stopRoomMeasurementSession(false);
      showToast('Ошибка отправки записи микрофона на Mac');
    }
  }

  function setupRoomAcousticControls() {
    const toggleBtn = document.getElementById('btn-room-eq-toggle');
    const selectEl = document.getElementById('room-profile-select');
    const delBtn = document.getElementById('btn-delete-room-profile');
    const startBtn = document.getElementById('btn-start-room-measure');
    const uploadBtn = document.getElementById('btn-upload-room-audio');
    const stopBtn = document.getElementById('btn-stop-room-measure');
    const fileInput = document.getElementById('room-mic-file-input');

    renderRoomEqChart(null);

    if (toggleBtn) {
      toggleBtn.addEventListener('click', () => {
        if (state.allowRoomMeasurement === false && state.allowDspPresetSelection === false) {
          showToast(IS_EN
            ? 'Room EQ control is disabled for this device on Mac'
            : 'Управление коррекцией комнаты отключено для этого устройства в настройках Mac');
          updateRoomAcousticUI(state.roomAcoustic);
          return;
        }
        triggerHaptic('toggle');
        const nextEnabled = !(state.roomAcoustic && state.roomAcoustic.enabled);
        send({
          action: 'set_room_correction_enabled',
          params: { enabled: nextEnabled }
        });
      });
    }

    if (selectEl) {
      selectEl.addEventListener('change', () => {
        if (state.allowRoomMeasurement === false && state.allowDspPresetSelection === false) {
          showToast(IS_EN
            ? 'Room EQ profile selection is disabled for this device on Mac'
            : 'Выбор профиля АЧХ отключён для этого устройства в настройках Mac');
          updateRoomAcousticUI(state.roomAcoustic);
          return;
        }
        if (!selectEl.value) return;
        triggerHaptic('light');
        send({
          action: 'select_room_profile',
          params: { profile_id: selectEl.value }
        });
      });
    }

    if (delBtn) {
      delBtn.addEventListener('click', () => {
        const prof = state.roomAcoustic && state.roomAcoustic.active_profile;
        if (!prof || !prof.id) return;
        triggerHaptic('light');
        send({
          action: 'delete_room_profile',
          params: { profile_id: prof.id }
        });
        showToast(`Профиль «${prof.name || 'АЧХ'}» удалён`);
      });
    }

    if (startBtn) {
      startBtn.addEventListener('click', () => {
        triggerHaptic('light');
        startLiveWebAudioRoomMeasurement();
      });
    }

    if (uploadBtn) {
      uploadBtn.addEventListener('click', () => {
        triggerHaptic('light');
        triggerNativeIosMicCapture();
      });
    }

    if (stopBtn) {
      stopBtn.addEventListener('click', () => {
        triggerHaptic('light');
        stopRoomMeasurementSession(true);
      });
    }

    if (fileInput) {
      fileInput.addEventListener('change', (e) => {
        state.awaitingNativeRoomFilePicker = false;
        const f = e.target.files && e.target.files[0];
        if (f) {
          handleUploadedRoomAudioFile(f);
        } else {
          stopRoomMeasurementSession(true);
        }
      });

      fileInput.addEventListener('cancel', () => {
        state.awaitingNativeRoomFilePicker = false;
        if (state.isMeasuringRoom || state.roomIsPlayingTestSignal || (state.roomAcoustic && state.roomAcoustic.is_test_signal_playing)) {
          stopRoomMeasurementSession(true);
        }
      });

      window.addEventListener('focus', () => {
        if (!state.awaitingNativeRoomFilePicker) return;
        setTimeout(() => {
          if (state.awaitingNativeRoomFilePicker && (!fileInput.files || fileInput.files.length === 0)) {
            state.awaitingNativeRoomFilePicker = false;
            if (state.isMeasuringRoom || state.roomIsPlayingTestSignal || (state.roomAcoustic && state.roomAcoustic.is_test_signal_playing)) {
              stopRoomMeasurementSession(true);
            }
          }
        }, 700);
      });
    }
  }

// === MODULE: 27-wakelock-and-standby-controls.js ===
  // ==========================================================================
  // Multi-Layer Screen Wake Lock Engine for iPadOS / iOS PWA & Desktop TV Mode
  // Layer 1: W3C Screen Wake Lock API (navigator.wakeLock.request('screen'))
  // Layer 2: Active 2fps <canvas> captureStream -> <video playsinline muted>
  //          (Prevents iPadOS Standalone PWA from auto-locking when no Motion
  //          Cover is playing — works around WebKit Bug #254545)
  // ==========================================================================
  const ScreenWakeLockManager = {
    sentinel: null,
    keepAliveVideo: null,
    keepAliveCanvas: null,
    keepAliveTimer: null,
    tickToggle: false,
    isActive: false,
    lastTouchRearmTs: 0,

    shouldHoldWakeLock() {
      if (!isStandbyOrLandscapeVisible()) return false;
      if (!state.connected) return false;
      const isPlayingOrStarting =
        state.playerState === 'playing' ||
        state.waitingForPlayback ||
        state.isAiCurating ||
        Boolean(state.pendingPlayUntil && Date.now() < state.pendingPlayUntil);
      return isPlayingOrStarting;
    },

    syncByPlaybackAndConnection() {
      if (this.shouldHoldWakeLock()) {
        if (!this.isActive) {
          this.acquire();
        } else {
          this.syncFallbackVideoState();
        }
      } else if (this.isActive) {
        this.release();
      }
    },

    async acquire() {
      if (!this.shouldHoldWakeLock()) {
        this.release();
        return;
      }
      this.isActive = true;
      await this.acquireNativeWakeLock();
      this.syncFallbackVideoState();
    },

    async acquireNativeWakeLock() {
      if (!this.isActive) return;
      if ('wakeLock' in navigator && navigator.wakeLock && typeof navigator.wakeLock.request === 'function') {
        try {
          if (!this.sentinel || this.sentinel.released) {
            const sentinel = await navigator.wakeLock.request('screen');
            if (!this.isActive) {
              try { await sentinel.release(); } catch (_) {}
              return;
            }
            this.sentinel = sentinel;
            this.sentinel.addEventListener('release', () => {
              if (this.isActive && document.visibilityState === 'visible') {
                setTimeout(() => {
                  this.acquireNativeWakeLock().then(() => this.syncFallbackVideoState());
                }, 500);
              }
            });
          }
        } catch (_) {}
      }
    },

    isNativeSentinelHeld() {
      return Boolean(this.sentinel && !this.sentinel.released);
    },

    isStandbyMotionVideoPlaying() {
      const sbVid = document.getElementById('standby-motion-video');
      return Boolean(sbVid && !sbVid.paused && sbVid.classList.contains('visible') && sbVid.currentSrc);
    },

    syncFallbackVideoState() {
      if (!this.isActive) {
        this.stopVideoKeepAlive();
        return;
      }
      // If native W3C Screen Wake Lock is held OR a Motion Cover <video> is actively playing,
      // do NOT waste CPU/GPU running a live canvas.captureStream(2) -> <video> MediaStream pipeline.
      if (this.isNativeSentinelHeld() || this.isStandbyMotionVideoPlaying()) {
        this.stopVideoKeepAlive();
      } else {
        this.startVideoKeepAlive();
      }
    },

    stopVideoKeepAlive(releaseStream = false) {
      if (this.keepAliveTimer) {
        clearInterval(this.keepAliveTimer);
        this.keepAliveTimer = null;
      }
      if (this.keepAliveVideo) {
        if (!this.keepAliveVideo.paused) {
          try {
            this.keepAliveVideo.pause();
          } catch (_) {}
        }
        if (releaseStream && this.keepAliveVideo.srcObject) {
          try {
            const tracks = typeof this.keepAliveVideo.srcObject.getTracks === 'function'
              ? this.keepAliveVideo.srcObject.getTracks()
              : [];
            tracks.forEach((tr) => {
              try { tr.stop(); } catch (_) {}
            });
          } catch (_) {}
          try {
            this.keepAliveVideo.srcObject = null;
          } catch (_) {}
        }
      }
    },

    startVideoKeepAlive() {
      if (!this.isActive) return;
      try {
        if (!this.keepAliveCanvas) {
          const canvas = document.createElement('canvas');
          canvas.width = 16;
          canvas.height = 16;
          this.keepAliveCanvas = canvas;
        }
        const ctx = this.keepAliveCanvas.getContext('2d');
        const drawTick = () => {
          if (!ctx) return;
          this.tickToggle = !this.tickToggle;
          ctx.fillStyle = this.tickToggle ? '#010102' : '#020101';
          ctx.fillRect(0, 0, 16, 16);
        };
        drawTick();

        if (!this.keepAliveTimer) {
          this.keepAliveTimer = setInterval(() => {
            if (!this.isActive) return;
            if (this.isNativeSentinelHeld() || this.isStandbyMotionVideoPlaying()) {
              this.stopVideoKeepAlive();
              return;
            }
            drawTick();
            if (this.keepAliveVideo && this.keepAliveVideo.paused) {
              this.keepAliveVideo.play().catch(() => {});
            }
            if (!this.sentinel || this.sentinel.released) {
              this.acquireNativeWakeLock();
            }
          }, 2000);
        }

        if (!this.keepAliveVideo) {
          const vid = document.createElement('video');
          vid.id = 'standby-wakelock-video';
          vid.muted = true;
          vid.defaultMuted = true;
          vid.loop = true;
          vid.playsInline = true;
          vid.setAttribute('playsinline', '');
          vid.setAttribute('webkit-playsinline', '');
          vid.setAttribute('muted', '');
          // Must have non-zero opacity & size inside the visible viewport so iPadOS WebKit
          // does not cull the video decoder and drop the display sleep assertion
          vid.style.cssText = 'position:fixed;bottom:1px;right:1px;width:2px;height:2px;opacity:0.015;pointer-events:none;z-index:9999;';
          const overlay = document.getElementById('standby-tv-overlay') || document.body;
          overlay.appendChild(vid);
          this.keepAliveVideo = vid;
        }

        if (this.keepAliveVideo && !this.keepAliveVideo.srcObject) {
          const captureFn = this.keepAliveCanvas.captureStream || this.keepAliveCanvas.webkitCaptureStream;
          if (typeof captureFn === 'function') {
            const stream = captureFn.call(this.keepAliveCanvas, 1);
            this.keepAliveVideo.srcObject = stream;
          }
        }

        if (this.keepAliveVideo && this.keepAliveVideo.paused) {
          this.keepAliveVideo.play().catch(() => {});
        }
      } catch (_) {}
    },

    release() {
      this.isActive = false;
      this.stopVideoKeepAlive(true);
      if (this.sentinel) {
        try {
          this.sentinel.release();
        } catch (_) {}
        this.sentinel = null;
      }
    }
  };

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      syncMotionVideoPlaybackState();
      ScreenWakeLockManager.syncByPlaybackAndConnection();
    }
  });

  // Ensure touch/click while TV mode is active re-arms the iPadOS gesture-gated wakeLock when playing (throttled)
  ['touchend', 'click'].forEach((evtName) => {
    document.addEventListener(evtName, () => {
      if (!ScreenWakeLockManager.shouldHoldWakeLock()) return;
      const now = performance.now();
      if (now - ScreenWakeLockManager.lastTouchRearmTs < 3000) return;
      ScreenWakeLockManager.lastTouchRearmTs = now;
      if (!ScreenWakeLockManager.isNativeSentinelHeld()) {
        ScreenWakeLockManager.acquire();
      }
    }, { passive: true });
  });

  function openStandbyMode() {
    if (isMobilePhoneViewport() || window.innerWidth < 768) return;
    const overlay = document.getElementById('standby-tv-overlay');
    if (!overlay) return;
    if (dom.searchInput && document.activeElement === dom.searchInput) {
      dom.searchInput.blur();
    }
    syncKeyboardFocusClass();
    document.body.classList.add('tv-mode-open');
    overlay.classList.remove('hidden');
    overlay.setAttribute('aria-hidden', 'false');
    ScreenWakeLockManager.syncByPlaybackAndConnection();
    try {
      localStorage.setItem('amr_tv_mode_active', '1');
      localStorage.removeItem('amr_default_tv_mode');
    } catch (_) {}
    if (!state.tvLibraryConfigLoaded) {
      send({ action: 'get_tv_library_config' });
    }
    if (!state.playlists || state.playlists.length === 0) {
      send({ action: 'get_playlists' });
    }
    if (!state.libraryAlbums || state.libraryAlbums.length === 0) {
      send({ action: 'get_library_albums' });
    }
    send({ action: 'get_queue' });
    if (typeof syncStandbyQueueBadge === 'function') syncStandbyQueueBadge();
    syncStandbyAndMotionCoverUI();
    syncActiveMotionVideoTarget();
    syncBookletViewerLayoutMode();
    updateScrubberUI(state.lastSyncPos, state.duration);
    ensureScrubberLoopRunning();
    updateStandbyClock();
    refreshAllTitleMarquees(true);
    if (!state.lastDspSettings) {
      send({ action: 'get_dsp_settings' });
    }
    send({ action: 'get_spectral_analysis' });
    syncSpectralPolling();
    const p = document.getElementById('top-settings-popover');
    if (p) {
      blurFocusedInContainer(p);
      p.classList.add('hidden');
      p.setAttribute('aria-hidden', 'true');
    }
  }

  function closeStandbyMode() {
    closeStandbyLibraryModal();
    closeStandbyAiModal();
    if (typeof closeStandbyQueueModal === 'function') closeStandbyQueueModal();
    ScreenWakeLockManager.release();
    document.body.classList.remove('tv-mode-open');
    if (standbyRtaRafId) {
      cancelAnimationFrame(standbyRtaRafId);
      standbyRtaRafId = null;
    }
    const overlay = document.getElementById('standby-tv-overlay');
    if (!overlay) return;
    overlay.classList.add('hidden');
    overlay.setAttribute('aria-hidden', 'true');
    syncActiveMotionVideoTarget();
    syncBookletViewerLayoutMode();
    syncSpectralPolling();
    updateScrubberUI(state.lastSyncPos, state.duration);
    ensureScrubberLoopRunning();
    refreshAllTitleMarquees(true);
    try {
      localStorage.setItem('amr_tv_mode_active', '0');
      localStorage.removeItem('amr_default_tv_mode');
    } catch (_) {}
    const p = document.getElementById('top-settings-popover');
    if (p) {
      blurFocusedInContainer(p);
      p.classList.add('hidden');
      p.setAttribute('aria-hidden', 'true');
    }
  }

  function updateStandbyClock() {
    const el = document.getElementById('standby-clock');
    if (!el) return;
    const now = new Date();
    const hh = String(now.getHours()).padStart(2, '0');
    const mm = String(now.getMinutes()).padStart(2, '0');
    el.textContent = `${hh}:${mm}`;
  }

  function positionSettingsPopoverNearButton(popover, btn) {
    if (!popover || !btn) return;
    const rect = btn.getBoundingClientRect();
    if (!rect || (rect.width === 0 && rect.height === 0)) return;
    const topPos = Math.max(12, Math.min(window.innerHeight - 160, rect.bottom + 8));
    const rightPos = Math.max(12, window.innerWidth - rect.right);
    popover.style.top = `${topPos}px`;
    popover.style.right = `${rightPos}px`;
    popover.style.left = 'auto';
  }

  function setupStandbyAndWledControls() {
    updateStandbyClock();
    setInterval(updateStandbyClock, 15000);

    try {
      const qsStandby = new URLSearchParams(window.location.search || '').get('standby');
      if (qsStandby === '1' || localStorage.getItem('amr_tv_mode_active') === '1') {
        openStandbyMode();
      }
    } catch (_) {}

    const popover = document.getElementById('top-settings-popover');
    let lastSettingsTriggerBtn = null;
    const togglePopover = (e) => {
      if (e) e.stopPropagation();
      if (!popover) return;
      const triggerBtn = e && e.currentTarget ? e.currentTarget : null;
      const isHidden = popover.classList.contains('hidden');
      if (isHidden || (triggerBtn && lastSettingsTriggerBtn !== triggerBtn)) {
        lastSettingsTriggerBtn = triggerBtn;
        send({ action: 'get_wled_settings' });
        popover.classList.remove('hidden');
        popover.setAttribute('aria-hidden', 'false');
        if (triggerBtn) {
          positionSettingsPopoverNearButton(popover, triggerBtn);
        }
      } else {
        blurFocusedInContainer(popover);
        popover.classList.add('hidden');
        popover.setAttribute('aria-hidden', 'true');
      }
    };

    ['btn-top-settings', 'mobile-btn-settings', 'player-btn-settings', 'standby-btn-wled-toggle'].forEach(id => {
      const btn = document.getElementById(id);
      if (btn) btn.addEventListener('click', togglePopover);
    });

    const btnClosePopover = document.getElementById('btn-close-top-settings');
    if (btnClosePopover) {
      btnClosePopover.addEventListener('click', () => {
        if (popover) {
          blurFocusedInContainer(popover);
          popover.classList.add('hidden');
          popover.setAttribute('aria-hidden', 'true');
        }
      });
    }

    document.addEventListener('click', (e) => {
      if (!popover || popover.classList.contains('hidden')) return;
      const insidePopover = popover.contains(e.target);
      const isTrigger = Boolean(e.target.closest('#btn-top-settings, #mobile-btn-settings, #player-btn-settings, #standby-btn-wled-toggle'));
      if (!insidePopover && !isTrigger) {
        blurFocusedInContainer(popover);
        popover.classList.add('hidden');
        popover.setAttribute('aria-hidden', 'true');
      }
    });

    const modeSel = document.getElementById('wled-mode-select');
    if (modeSel) modeSel.addEventListener('change', pushWledSettingsToServer);

    ['btn-standby-mode'].forEach(id => {
      const btn = document.getElementById(id);
      if (btn) btn.addEventListener('click', openStandbyMode);
    });

    const btnCloseStandby = document.getElementById('btn-close-standby');
    if (btnCloseStandby) btnCloseStandby.addEventListener('click', closeStandbyMode);

    const btnStandbyLib = document.getElementById('standby-btn-library');
    if (btnStandbyLib) btnStandbyLib.addEventListener('click', openStandbyLibraryModal);

    const btnCloseStandbyLib = document.getElementById('btn-close-standby-library');
    if (btnCloseStandbyLib) btnCloseStandbyLib.addEventListener('click', closeStandbyLibraryModal);

    const btnStandbyQueue = document.getElementById('standby-btn-queue');
    if (btnStandbyQueue) btnStandbyQueue.addEventListener('click', openStandbyQueueModal);

    const btnCloseStandbyQueue = document.getElementById('btn-close-standby-queue');
    if (btnCloseStandbyQueue) btnCloseStandbyQueue.addEventListener('click', closeStandbyQueueModal);

    const btnStandbyAi = document.getElementById('standby-btn-ai-curator');
    if (btnStandbyAi) btnStandbyAi.addEventListener('click', openStandbyAiModal);

    const btnStandbyAiRefresh = document.getElementById('btn-standby-ai-refresh');
    if (btnStandbyAiRefresh) {
      btnStandbyAiRefresh.addEventListener('click', () => {
        triggerHaptic('light');
        resetAndGenerateStandbyAiTagCloud();
      });
    }

    const btnCloseStandbyAi = document.getElementById('btn-close-standby-ai');
    if (btnCloseStandbyAi) btnCloseStandbyAi.addEventListener('click', closeStandbyAiModal);

    const sbPlayPause = document.getElementById('standby-btn-play-pause');
    const sbPrev = document.getElementById('standby-btn-prev');
    const sbNext = document.getElementById('standby-btn-next');
    const sbFavBtn = document.getElementById('standby-btn-favorite');
    const sbShuffleBtn = document.getElementById('standby-btn-shuffle');
    const sbRepeatBtn = document.getElementById('standby-btn-repeat');
    const sbAiVibeBtn = document.getElementById('standby-btn-ai-track-vibe');
    const sbTrack = document.getElementById('standby-progress-track');

    if (sbPlayPause) sbPlayPause.addEventListener('click', togglePlayPause);
    if (sbPrev) sbPrev.addEventListener('click', () => sendThrottledTransport('previous'));
    if (sbNext) sbNext.addEventListener('click', () => sendThrottledTransport('next'));
    if (sbShuffleBtn) sbShuffleBtn.addEventListener('click', toggleShuffleOptimistic);
    if (sbRepeatBtn) sbRepeatBtn.addEventListener('click', cycleRepeatMode);
    if (sbFavBtn) {
      sbFavBtn.addEventListener('click', handleToggleFavorite);
    }
    if (sbAiVibeBtn) {
      sbAiVibeBtn.addEventListener('click', triggerAiMixFromCurrentTrack);
    }
    const sbProgressInput = document.getElementById('standby-progress-input');
    if (sbProgressInput) {
      sbProgressInput.addEventListener('input', (e) => {
        if (!state.duration || state.duration <= 0) return;
        state.isScrubbing = true;
        const percent = parseFloat(e.target.value);
        const targetPos = (percent / 100) * state.duration;
        state.scrubValue = targetPos;
        const pctStr = `${percent.toFixed(2)}%`;
        const sbFill = document.getElementById('standby-progress-fill');
        const sbThumb = document.getElementById('standby-progress-thumb');
        const sbElapsed = document.getElementById('standby-time-elapsed');
        const sbRem = document.getElementById('standby-time-remaining');
        if (sbFill) sbFill.style.width = pctStr;
        if (sbThumb) sbThumb.style.left = pctStr;
        if (sbElapsed) sbElapsed.textContent = formatTime(targetPos);
        if (sbRem) sbRem.textContent = `-${formatTime(Math.max(0, state.duration - targetPos))}`;
      });
      sbProgressInput.addEventListener('change', commitScrub);
      sbProgressInput.addEventListener('pointerup', commitScrub);
      sbProgressInput.addEventListener('pointercancel', commitScrub);
      sbProgressInput.addEventListener('touchend', commitScrub);
      sbProgressInput.addEventListener('touchcancel', commitScrub);
    } else if (sbTrack) {
      sbTrack.addEventListener('click', (e) => {
        if (!state.duration || state.duration <= 0) return;
        const rect = sbTrack.getBoundingClientRect();
        const ratio = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
        sendSeek(ratio * state.duration);
      });
    }

    renderStandbyQuickTiles();

    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        if (dom.confirmDeleteModal && !dom.confirmDeleteModal.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          closeConfirmDeleteModal();
          return;
        }
        const amrInfoModal = document.getElementById('amr-info-popover');
        if (amrInfoModal && !amrInfoModal.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          blurFocusedInContainer(amrInfoModal);
          amrInfoModal.classList.add('hidden');
          amrInfoModal.setAttribute('aria-hidden', 'true');
          syncKeyboardFocusClass();
          return;
        }
        if (dom.devicesModal && !dom.devicesModal.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          blurFocusedInContainer(dom.devicesModal);
          dom.devicesModal.classList.add('hidden');
          dom.devicesModal.setAttribute('aria-hidden', 'true');
          return;
        }
        if (dom.qualityModal && !dom.qualityModal.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          closeQualityModal();
          return;
        }
        if (dom.stationPickerModal && !dom.stationPickerModal.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          closeStationPickerModal();
          return;
        }
        if (dom.modalAccountDiag && !dom.modalAccountDiag.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          blurFocusedInContainer(dom.modalAccountDiag);
          dom.modalAccountDiag.classList.add('hidden');
          dom.modalAccountDiag.setAttribute('aria-hidden', 'true');
          return;
        }
        const bookletModal = document.getElementById('booklet-viewer-modal');
        if (bookletModal && !bookletModal.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          closeBookletViewer();
          return;
        }
        if (popover && !popover.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          blurFocusedInContainer(popover);
          popover.classList.add('hidden');
          popover.setAttribute('aria-hidden', 'true');
          return;
        }
        const aiModal = document.getElementById('standby-ai-modal');
        if (aiModal && !aiModal.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          closeStandbyAiModal();
          return;
        }
        const queueModal = document.getElementById('standby-queue-modal');
        if (queueModal && !queueModal.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          closeStandbyQueueModal();
          return;
        }
        const libModal = document.getElementById('standby-library-modal');
        if (libModal && !libModal.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          closeStandbyLibraryModal();
          return;
        }
        const overlay = document.getElementById('standby-tv-overlay');
        if (overlay && !overlay.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          closeStandbyMode();
        }
      }
    });
  }

// === MODULE: 28-booklet-viewer.js ===
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

// === MODULE: 29-device-auth-qr-and-init.js ===
  function setupBookletViewerControls() {
    const btnOpenNowPlaying = document.getElementById('btn-open-booklet');
    const btnOpenStandby = document.getElementById('standby-btn-booklet');
    const btnOpenDetail = document.getElementById('btn-detail-booklet');
    const btnClose = document.getElementById('btn-close-booklet');

    if (btnOpenNowPlaying) {
      btnOpenNowPlaying.addEventListener('click', () => {
        closeStationPickerModal();
        openBookletViewer();
      });
    }
    if (btnOpenStandby) {
      btnOpenStandby.addEventListener('click', () => openBookletViewer());
    }
    if (btnOpenDetail) {
      btnOpenDetail.addEventListener('click', () => {
        const det = state.currentPlaylistDetail;
        if (det && det.isAlbum) {
          openBookletViewer({
            album: det.name || det.title || '',
            artist: det.artist || det.sub || det.subtitle || '',
            albumId: det.id || ''
          });
        } else {
          openBookletViewer();
        }
      });
    }
    if (btnClose) btnClose.addEventListener('click', closeBookletViewer);

    window.addEventListener('resize', () => {
      if (bookletState.isOpen) {
        syncBookletViewerLayoutMode();
      }
    });

    document.addEventListener('keydown', (e) => {
      if (bookletState.isOpen && e.key === 'Escape') {
        e.preventDefault();
        closeBookletViewer();
      }
    });
  }

  // --- Device Authorization & Top-Left AMR Info / Lock Screen Controller ---
  function applyLockScreenControlsSetting(enabled, options = {}) {
    const boolVal = Boolean(enabled);
    state.lockScreenControls = boolVal;
    writePersistentCookie('amr_lock_screen', boolVal ? 'true' : 'false');
    try {
      localStorage.setItem('amr_lock_screen_controls', boolVal ? 'true' : 'false');
    } catch (e) {}

    const lockCheckbox = document.getElementById('amr-lock-screen-checkbox');
    if (lockCheckbox && lockCheckbox.checked !== boolVal) {
      lockCheckbox.checked = boolVal;
    }

    if (!boolVal || (state.deviceAuthChecked && !state.deviceAuthorized)) {
      teardownMediaSessionAndSilentAudio();
    } else {
      initSilentAudio();
      setupMediaSession(true);
      updateMediaSession();
      if (state.playerState === 'playing') {
        syncSilentAudio(true);
      }
    }

    if (options.syncServer && state.connected) {
      send({
        action: 'update_device_settings',
        params: {
          device_id: state.deviceId,
          lock_screen_controls: boolVal
        }
      });
    }

    if (options.showFeedback) {
      showToast(boolVal ? 'Экран блокировки включён' : 'Экран блокировки выключен');
    }
    syncDeviceInfoUI();
  }

  function syncDeviceInfoUI() {
    const commitBadgeEl = document.getElementById('amr-info-commit-badge');
    const commitDetailsEl = document.getElementById('amr-info-commit-details');
    const summaryEl = document.getElementById('amr-info-device-summary');
    const deviceUidMetaEl = document.getElementById('amr-info-device-uid');
    const nameInput = document.getElementById('amr-device-name-input');
    const lockCheckbox = document.getElementById('amr-lock-screen-checkbox');
    const lockNodeDot = document.getElementById('amr-lock-node-dot');
    const lockStateBadge = document.getElementById('amr-lock-state-badge');
    const authOverlay = document.getElementById('device-auth-overlay');
    const authShortIdEl = document.getElementById('auth-device-short-id');
    const authNameInput = document.getElementById('auth-device-name-input');
    const authFullIdEl = document.getElementById('auth-device-full-id');

    const commitHash = state.gitCommit || '7278dab';
    const commitDate = state.gitCommitDate || '2026-11-04';
    if (commitBadgeEl) {
      commitBadgeEl.textContent = commitHash;
    }
    if (commitDetailsEl) {
      commitDetailsEl.textContent = translateTextToEn(`Последний коммит: ${commitHash} (${commitDate}) • Pure Swift Server`);
    }

    const shortId = state.deviceShortId || computeShortDeviceId(state.deviceId);
    if (summaryEl) {
      summaryEl.textContent = `ID: ${shortId}`;
    }
    if (deviceUidMetaEl) {
      const dacStatus = state.allowDacSelection !== false
        ? (IS_EN ? 'DAC: On' : 'ЦАП: Вкл')
        : (IS_EN ? 'DAC: Off' : 'ЦАП: Закрыт');
      const dspStatus = state.allowDspPresetSelection !== false
        ? (IS_EN ? 'DSP: On' : 'DSP: Вкл')
        : (IS_EN ? 'DSP: Off' : 'DSP: Закрыт');
      const libStatus = state.allowLibraryModification !== false
        ? ''
        : (IS_EN ? ' • Lib: Read-Only' : ' • Медиатека: Чтение');
      deviceUidMetaEl.textContent = `UID: ${state.deviceId} • ${dacStatus} • ${dspStatus}${libStatus}`;
    }
    if (nameInput && document.activeElement !== nameInput) {
      nameInput.value = state.deviceName;
    }
    const isLockOn = Boolean(state.lockScreenControls);
    if (lockCheckbox) {
      lockCheckbox.checked = isLockOn;
    }
    if (lockNodeDot) {
      lockNodeDot.classList.toggle('active', isLockOn);
    }
    if (lockStateBadge) {
      lockStateBadge.textContent = translateTextToEn(isLockOn ? 'АКТИВНО' : 'ОТКЛЮЧЕНО');
      lockStateBadge.classList.toggle('highlight-green', isLockOn);
    }
    if (authShortIdEl) {
      authShortIdEl.textContent = shortId;
    }
    if (authNameInput && document.activeElement !== authNameInput) {
      authNameInput.value = state.deviceName;
    }
    if (authFullIdEl) {
      authFullIdEl.textContent = `UID: ${state.deviceId}`;
    }

    if (authOverlay) {
      if (!state.deviceAuthorized) {
        authOverlay.classList.remove('hidden');
        authOverlay.setAttribute('aria-hidden', 'false');
        if (dom.modalAppleAuth) {
          blurFocusedInContainer(dom.modalAppleAuth);
          dom.modalAppleAuth.classList.add('hidden');
          dom.modalAppleAuth.setAttribute('aria-hidden', 'true');
        }
      } else {
        if (authNameInput && document.activeElement === authNameInput) {
          authNameInput.blur();
        }
        blurFocusedInContainer(authOverlay);
        authOverlay.classList.add('hidden');
        authOverlay.setAttribute('aria-hidden', 'true');
        syncKeyboardFocusClass();
      }
    }
  }

  function handleDeviceAuthStatus(data) {
    if (!data || typeof data !== 'object') return;

    if (data.git_commit) {
      state.gitCommit = String(data.git_commit);
    }
    if (data.git_commit_date) {
      state.gitCommitDate = String(data.git_commit_date);
    }
    if (data.device_id) {
      const incomingId = String(data.device_id).toLowerCase();
      if (state.supersededFreshDeviceId && incomingId === state.supersededFreshDeviceId.toLowerCase() && state.deviceId !== incomingId) {
        return;
      }
      state.deviceId = incomingId;
      if (!state.deviceIdWasFreshlyGenerated) {
        persistUidToSecureStore(state.deviceId);
      }
    }
    state.deviceShortId = data.short_id || computeShortDeviceId(state.deviceId);

    if (data.device_secret || data.deviceSecret) {
      persistDeviceSecret(data.device_secret || data.deviceSecret);
    }

    if (data.device_name && String(data.device_name).trim()) {
      state.deviceName = String(data.device_name).trim();
      try { localStorage.setItem('amr_device_name', state.deviceName); } catch (e) {}
    }

    if (typeof data.authorized === 'boolean') {
      state.deviceAuthorized = data.authorized;
      state.deviceAuthChecked = true;
    } else if (typeof data.is_authorized === 'boolean') {
      state.deviceAuthorized = data.is_authorized;
      state.deviceAuthChecked = true;
    }

    if (state.deviceAuthorized) {
      clearInviteTokenFromClient();
    }

    if (typeof data.allow_dac_selection === 'boolean') {
      state.allowDacSelection = data.allow_dac_selection;
    }
    if (typeof data.allow_dsp_preset_selection === 'boolean') {
      state.allowDspPresetSelection = data.allow_dsp_preset_selection;
    }
    if (typeof data.allow_room_measurement === 'boolean') {
      state.allowRoomMeasurement = data.allow_room_measurement;
      if (!state.allowRoomMeasurement && state.isMeasuringRoom) {
        stopRoomMeasurementSession(true);
      }
    }
    if (typeof data.allow_late_night_mode === 'boolean') {
      state.allowLateNightMode = data.allow_late_night_mode;
    }
    if (typeof data.allow_library_modification === 'boolean') {
      state.allowLibraryModification = data.allow_library_modification;
    } else if (typeof data.allowLibraryModification === 'boolean') {
      state.allowLibraryModification = data.allowLibraryModification;
    }

    if (typeof data.lock_screen_controls === 'boolean') {
      applyLockScreenControlsSetting(data.lock_screen_controls, { syncServer: false, showFeedback: false });
    } else if (state.deviceAuthorized) {
      if (state.lockScreenControls) {
        initSilentAudio();
        setupMediaSession(true);
        updateMediaSession();
      }
    } else {
      teardownMediaSessionAndSilentAudio();
    }

    if (!state.deviceAuthorized) {
      state.initialAuthFetched = false;
    }

    applyDeviceCapabilityPermissionsUI();
    syncDeviceInfoUI();

    // Load library and Apple ID / MusicKit status ONLY after device is authorized.
    // Note: register_device / device approval already pushes player_state_changed, ai_curator_settings,
    // dsp_settings, tv_library_config, and queue; avoid duplicate startup RPC bursts!
    if (state.deviceAuthorized && !state.initialAuthFetched && state.connected) {
      state.initialAuthFetched = true;
      const authTime = Date.now();
      if (typeof flushPendingAppleUserToken === 'function') {
        flushPendingAppleUserToken();
      }
      flushPendingPreOpenQueue();
      send({ action: 'get_user_token_status' });
      send({ action: 'get_developer_token' });
      send({ action: 'get_audio_devices' });
      send({ action: 'get_wled_settings' });
      send({ action: 'get_info' });
      send({ action: 'get_playlists' });
      send({ action: 'get_library_albums' });
      send({ action: 'get_account_status' });
      state.librarySongsLoaded = false;
      state.libraryArtistsLoaded = false;
      if (state.libraryRecent) {
        state.libraryRecent.loaded = false;
      }
      if (state.activeTab === 'library' && typeof switchLibrarySubtab === 'function') {
        switchLibrarySubtab(state.libraryTab || 'recent', false);
      }

      setTimeout(() => {
        if (state.connected && state.deviceAuthorized) {
          loadTrends();
        }
      }, 120);

      setTimeout(() => {
        if (!state.connected || !state.deviceAuthorized) return;
        if (!state.lastPlayerStateReceivedAt || state.lastPlayerStateReceivedAt < authTime - 2000) {
          send({ action: 'get_status' });
        }
        if (!state.lastQueueReceivedAt || state.lastQueueReceivedAt < authTime - 2000) {
          send({ action: 'get_queue' });
        }
        if (!state.lastAiSettingsReceivedAt || state.lastAiSettingsReceivedAt < authTime - 2000) {
          send({ action: 'get_ai_curator_settings' });
        }
        if (!state.lastDspSettings) {
          send({ action: 'get_dsp_settings' });
        }
        if (!state.tvLibraryConfigLoaded) {
          send({ action: 'get_tv_library_config' });
        }
      }, 900);
    }
  }

  function handleShareAccessQR(data) {
    if (!data || typeof data !== 'object') return;
    const shareUrl = String(data.share_url || data.base_url || window.location.origin);
    const qrDataUrl = data.qr_data_url;
    state.shareAccessUrl = shareUrl;

    const qrPanel = document.getElementById('amr-share-qr-panel');
    const qrImg = document.getElementById('amr-share-qr-img');
    const urlText = document.getElementById('amr-share-url-text');
    const btnNativeShare = document.getElementById('btn-native-share-link');

    if (qrImg && typeof qrDataUrl === 'string' && qrDataUrl.startsWith('data:image/png;base64,')) {
      qrImg.src = qrDataUrl;
    }
    if (urlText) {
      urlText.textContent = shareUrl;
    }
    if (btnNativeShare) {
      btnNativeShare.classList.toggle('hidden', typeof navigator.share !== 'function');
    }
    if (qrPanel) {
      qrPanel.classList.remove('hidden');
    }
  }

  function setupAmrInfoAndDeviceAuthControls() {
    const btnBrand = document.getElementById('btn-brand-info');
    const mobileBtnBrand = document.getElementById('mobile-btn-brand-info');
    const popover = document.getElementById('amr-info-popover');
    const btnClose = document.getElementById('btn-close-amr-info');
    const lockCheckbox = document.getElementById('amr-lock-screen-checkbox');
    const nameInput = document.getElementById('amr-device-name-input');
    const authNameInput = document.getElementById('auth-device-name-input');
    const btnShareAccessQr = document.getElementById('btn-share-access-qr');
    const btnShareAccessLabel = document.getElementById('amr-share-access-btn-label');
    const qrPanel = document.getElementById('amr-share-qr-panel');
    const btnCopyShareLink = document.getElementById('btn-copy-share-link');
    const btnNativeShareLink = document.getElementById('btn-native-share-link');

    syncDeviceInfoUI();

    const togglePopover = (e) => {
      if (e) e.stopPropagation();
      if (!popover) return;
      const topSettings = document.getElementById('top-settings-popover');
      if (topSettings) {
        blurFocusedInContainer(topSettings);
        topSettings.classList.add('hidden');
        topSettings.setAttribute('aria-hidden', 'true');
      }
      syncDeviceInfoUI();
      if (!popover.classList.contains('hidden')) {
        blurFocusedInContainer(popover);
      }
      popover.classList.toggle('hidden');
      popover.setAttribute('aria-hidden', popover.classList.contains('hidden') ? 'true' : 'false');
      syncKeyboardFocusClass();
    };

    if (btnBrand) btnBrand.addEventListener('click', togglePopover);
    if (mobileBtnBrand) mobileBtnBrand.addEventListener('click', togglePopover);
    if (btnClose && popover) {
      btnClose.addEventListener('click', () => {
        blurFocusedInContainer(popover);
        popover.classList.add('hidden');
        popover.setAttribute('aria-hidden', 'true');
        syncKeyboardFocusClass();
      });
    }

    if (popover) {
      popover.addEventListener('click', (e) => {
        if (e.target === popover) {
          blurFocusedInContainer(popover);
          popover.classList.add('hidden');
          popover.setAttribute('aria-hidden', 'true');
          syncKeyboardFocusClass();
        }
      });
    }

    if (btnShareAccessQr && qrPanel) {
      btnShareAccessQr.addEventListener('click', (e) => {
        e.stopPropagation();
        const isCurrentlyHidden = qrPanel.classList.contains('hidden');
        if (isCurrentlyHidden) {
          qrPanel.classList.remove('hidden');
          btnShareAccessQr.classList.add('active');
          if (btnShareAccessLabel) {
            btnShareAccessLabel.textContent = translateTextToEn('Скрыть QR-код');
          }
          send({ action: 'get_share_access_qr' });
        } else {
          qrPanel.classList.add('hidden');
          btnShareAccessQr.classList.remove('active');
          if (btnShareAccessLabel) {
            btnShareAccessLabel.textContent = translateTextToEn('Поделиться доступом');
          }
        }
      });
    }

    if (btnCopyShareLink) {
      btnCopyShareLink.addEventListener('click', (e) => {
        e.stopPropagation();
        const urlToCopy = state.shareAccessUrl || window.location.origin;
        const onCopied = () => showToast('Ссылка для подключения скопирована');
        if (navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
          navigator.clipboard.writeText(urlToCopy).then(onCopied).catch(() => {
            const ta = document.createElement('textarea');
            ta.setAttribute('readonly', '');
            ta.value = urlToCopy;
            ta.style.position = 'fixed';
            ta.style.opacity = '0';
            document.body.appendChild(ta);
            ta.select();
            try { document.execCommand('copy'); } catch (err) {}
            ta.blur();
            document.body.removeChild(ta);
            syncKeyboardFocusClass();
            onCopied();
          });
        } else {
          const ta = document.createElement('textarea');
          ta.setAttribute('readonly', '');
          ta.value = urlToCopy;
          ta.style.position = 'fixed';
          ta.style.opacity = '0';
          document.body.appendChild(ta);
          ta.select();
          try { document.execCommand('copy'); } catch (err) {}
          ta.blur();
          document.body.removeChild(ta);
          syncKeyboardFocusClass();
          onCopied();
        }
      });
    }

    if (btnNativeShareLink) {
      btnNativeShareLink.addEventListener('click', (e) => {
        e.stopPropagation();
        const urlToShare = state.shareAccessUrl || window.location.origin;
        if (typeof navigator.share === 'function') {
          navigator.share({
            title: 'Apple Music Remote',
            text: translateTextToEn('Поделиться доступом'),
            url: urlToShare
          }).catch(() => {});
        }
      });
    }

    if (lockCheckbox) {
      lockCheckbox.addEventListener('change', (e) => {
        applyLockScreenControlsSetting(e.target.checked, { syncServer: true, showFeedback: true });
      });
    }

    const commitDeviceName = (rawVal) => {
      const trimmed = String(rawVal || '').trim();
      if (!trimmed || trimmed === state.deviceName) return;
      state.deviceName = trimmed;
      try { localStorage.setItem('amr_device_name', trimmed); } catch (e) {}
      syncDeviceInfoUI();
      if (state.connected) {
        send({
          action: 'update_device_settings',
          params: {
            device_id: state.deviceId,
            device_name: trimmed
          }
        });
      }
      showToast('Имя устройства сохранено');
    };

    [nameInput, authNameInput].forEach((inp) => {
      if (!inp) return;
      inp.addEventListener('change', (e) => commitDeviceName(e.target.value));
      inp.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
          e.preventDefault();
          inp.blur();
          commitDeviceName(inp.value);
        }
      });
    });
  }

  function bindGenreCards() {
    document.querySelectorAll('#search-landing .genre-card[data-genre]').forEach(card => {
      card.addEventListener('click', () => {
        const genre = card.getAttribute('data-genre');
        if (genre) {
          dom.searchInput.value = genre;
          state.searchQuery = genre;
          state.searchScope = 'all';
          if (dom.filterChips) {
            dom.filterChips.forEach(c => c.classList.toggle('active', c.dataset.scope === 'all'));
          }
          dom.btnClearSearch.classList.remove('hidden');
          executeSearch(genre, 'all');
        }
      });
    });

    const homeGenresHeader = document.querySelector('#home-genres-section .home-section-header-link');
    if (homeGenresHeader && dom.homeGenresGrid) {
      homeGenresHeader.addEventListener('click', () => {
        dom.homeGenresGrid.scrollIntoView({ behavior: 'smooth', block: 'start' });
      });
    }
  }

  // Keep standalone shell geometry synchronized across BFCache restores and software keyboard dismissal
  // without ever mutating <meta name="viewport"> (which causes startup screen jerks and touch-offset bugs).
  syncStandaloneShellGeometry();

  window.addEventListener('pageshow', () => {
    syncStandaloneShellGeometry();
  }, { passive: true });

  document.addEventListener('focusout', () => {
    if (!isStandalonePwaMode()) return;
    setTimeout(() => {
      syncStandaloneShellGeometry();
      if (document.body && !document.body.classList.contains('keyboard-open') && window.scrollY !== 0) {
        try { window.scrollTo(0, 0); } catch (_) {}
      }
    }, 80);
  }, { passive: true });

  // Initialize
  setupAmrInfoAndDeviceAuthControls();
  setupMediaSession();
  setupArtworkSwipeGestures();
  setupMiniPlayerGestures();
  setupStandbyAndWledControls();
  setupDSPControls();
  setupRoomAcousticControls();
  setupBookletViewerControls();
  renderHeroCarousel({});
  renderHomeStations(DEFAULT_STATIONS);
  renderHomeGenres(DEFAULT_GENRES);
  bindGenreCards();
  renderVolumeUI();
  if (!isDesktopLayout()) {
    let cachedWasPlaying = true;
    try {
      const rawPlaying = localStorage.getItem('amr_last_was_playing');
      if (rawPlaying !== null) {
        cachedWasPlaying = (rawPlaying === 'true');
      }
    } catch (_) {}
    if (!cachedWasPlaying) {
      switchMobileView('view-home', true);
    }
  }
  handleResize({ force: true });
  requestAnimationFrame(() => {
    if (document.body) {
      document.body.classList.add('app-ready');
    }
  });
  recoverOrPersistDeviceUidBeforeConnect().finally(() => {
    connectWebSocket();
  });

})();
