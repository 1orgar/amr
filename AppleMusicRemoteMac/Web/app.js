/**
 * Apple Music Remote (AMR) - Client Application
 * Pure Vanilla JS (ES6+), Zero Dependencies.
 */

(function () {
  'use strict';

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
    'Добавлено ✓': 'Added ✓',
    'Добавление...': 'Adding...',
    'Буклет PDF': 'Booklet PDF',
    'БУКЛЕТ PDF': 'BOOKLET PDF',
    'Загрузка треков...': 'Loading tracks...',
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
    'Спектральный эквалайзер (Бас · Вокал · Верх)': 'Spectral Equalizer (Bass · Mids · Highs)',
    'Симметричный пульс (раскрытие от центра)': 'Symmetric Center VU Pulse',
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
    'Поделиться': 'Share'
  };

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
      .replace(/Apple Music:\s*подписка активна\s*•\s*Регион\s*([A-Z]+)\s*•\s*Медиатека синхронизирована/i, 'Apple Music: Active • Storefront $1 • Library Synced')
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
      .replace(/Передискретизация \(([^)]+)\)/i, 'Resampling ($1)')
      .replace(/Частота или разрядность источника \(([^)]+)\) отличается от текущего режима вывода \(([^)]+)\)\./i, 'Source format ($1) differs from current output mode ($2).')
      .replace(/Прямое подключение macOS CoreAudio HAL \(([^)]+)\)/i, 'Direct macOS CoreAudio HAL ($1)')
      .replace(/Прямой вывод CoreAudio \(Bit-Perfect 100% • Громкость: ([^)]+)\)/i, 'Direct CoreAudio Output (Bit-Perfect 100% • Volume: $1)')
      .replace(/Прямой вывод CoreAudio \(Bit-Perfect 100% • Ожидание ([^)]+)\)/i, 'Direct CoreAudio Output (Bit-Perfect 100% • Waiting for $1)')
      .replace(/Сетевой (Hi-Res|Lossless|PCM) стриминг \(([^)]+)\)\s*•\s*(.+)/i, 'Network $1 Streaming ($2) • $3')
      .replace(/Сетевой стример\s*•\s*До 192 кГц Hi-Res\s*•\s*(.+)/i, 'Network Streamer • Up to 192 kHz Hi-Res • $1')
      .replace(/\((\d+)\s*частот\)/i, '($1 rates)')
      .replace(/Декодирование в PCM/g, 'Decoded to PCM')
      .replace(/Декодирование AAC → PCM/g, 'AAC → PCM Decode')
      .replace(/Бесконечный PCM поток/g, 'Continuous PCM Stream')
      .replace(/Bypass микшера/g, 'Mixer Bypass')
      .replace(/(\d+)-бит\s*\(Честный(?:\s*LSB)?\)/gi, '$1-bit (True LSB)')
      .replace(/(\d+)-бит\s*\(в\s*(\d+)-бит\)/gi, '$1-bit (in $2-bit)')
      .replace(/(\d+)-бит/gi, '$1-bit')
      .replace(/Нет\s*\(<([-\d.]+)\s*dB\)/gi, 'None (<$1 dB)')
      .replace(/Н\/Д\s*\(≤\s*48\s*(?:кГц|kHz)\)/gi, 'N/A (≤ 48 kHz)')
      .replace(/до\s*([\d.]+)\s*кГц/gi, 'up to $1 kHz')
      .replace(/([\d.]+)\s*кГц/gi, '$1 kHz')
      .replace(/(\d+)\s*Гц/gi, '$1 Hz')
      .replace(/(\d+)\s*мс/gi, '$1 ms')
      .replace(/(\d+)\s*трек(?:ов|а)?/gi, '$1 tracks')
      .replace(/(\d+)\s*стр\./gi, '$1 pp.')
      .replace(/Страница\s*(\d+)/gi, 'Page $1');
    return out;
  }

  function localizeDomNode(root) {
    if (!IS_EN || !root) return;
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
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, null, false);
    let node = walker.nextNode();
    while (node) {
      if (node.nodeType === Node.TEXT_NODE) {
        const val = node.nodeValue;
        if (val && /[А-Яа-яЁё]/.test(val)) {
          const next = translateTextToEn(val);
          if (next !== val) node.nodeValue = next;
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

  if (IS_EN) {
    const authDescEl = document.querySelector('#device-auth-overlay .overlay-desc');
    if (authDescEl) {
      authDescEl.innerHTML = 'Open <strong>Apple Music Remote Settings</strong> on your Mac ("General" tab) and click <strong>"Authorize"</strong> next to this device.';
    }
    localizeDomNode(document.body);
    const i18nObserver = new MutationObserver((mutations) => {
      for (let i = 0; i < mutations.length; i++) {
        const m = mutations[i];
        if (m.type === 'characterData') {
          localizeDomNode(m.target);
        } else if (m.type === 'attributes') {
          const el = m.target;
          const attr = m.attributeName;
          if (el && attr && el.hasAttribute(attr)) {
            const cur = el.getAttribute(attr);
            if (cur && /[А-Яа-яЁё]/.test(cur)) {
              const next = translateTextToEn(cur);
              if (next !== cur) el.setAttribute(attr, next);
            }
          }
        } else if (m.type === 'childList') {
          for (let j = 0; j < m.addedNodes.length; j++) {
            localizeDomNode(m.addedNodes[j]);
          }
        }
      }
    });
    if (document.body) {
      i18nObserver.observe(document.body, {
        childList: true,
        subtree: true,
        characterData: true,
        attributes: true,
        attributeFilter: ['title', 'placeholder', 'aria-label', 'alt']
      });
    }
  }

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
      document.cookie = `${name}=${encodeURIComponent(val)}; path=/; max-age=315360000; SameSite=Lax`;
    } catch (e) {}
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

    return {
      deviceId: uid,
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
    deviceShortId: initialDeviceProfile.shortId,
    deviceIdWasFreshlyGenerated: Boolean(initialDeviceProfile.deviceIdWasFreshlyGenerated),
    supersededFreshDeviceId: '',
    deviceName: initialDeviceProfile.deviceName,
    deviceType: initialDeviceProfile.deviceType,
    deviceAuthorized: false, // Updated by server on connect (false -> shows auth waiting screen first)
    initialAuthFetched: false,
    inviteToken: initialDeviceProfile.inviteToken || '',
    shareAccessUrl: '',
    lockScreenControls: initialDeviceProfile.lockScreenControls,
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
    volume: 100,
    previousVolume: 100,
    lockVolume100: localStorage.getItem('amr_lock_volume_100') !== null ? (localStorage.getItem('amr_lock_volume_100') === 'true') : true,
    ampVolumeControlEnabled: false,
    ampBrandName: 'Rotel',
    ampVolume: 35,
    ampMaxVolume: 96,
    ampMuted: false,
    ampConnected: false,
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
    currentPlaylistDetail: null,
    trends: {
      country: 'ru',
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

    // Apple MusicKit & User Token
    hasUserToken: false,
    developerToken: '',
    userStorefront: 'us',
    isAccountSynced: false,
    accountHealth: null,

    // Scrubber local tracking & watchdog timestamps
    isScrubbing: false,
    scrubValue: 0,
    lastSyncPos: 0,
    lastSyncTime: performance.now(),
    lastServerMessageAt: Date.now(),
    lastSpectralUpdateAt: performance.now(),
    lastEndOfTrackPollAt: 0
  };
  window.__amr_state = state;

  function recoverOrPersistDeviceUidBeforeConnect() {
    const hasCacheStorage = typeof window !== 'undefined' && 'caches' in window && Boolean(window.caches);
    if (!state.deviceIdWasFreshlyGenerated) {
      persistUidToSecureStore(state.deviceId);
      return Promise.resolve();
    }
    if (!hasCacheStorage || typeof window.caches.open !== 'function') {
      state.deviceIdWasFreshlyGenerated = false;
      persistUidToSecureStore(state.deviceId);
      return Promise.resolve();
    }
    const freshlyGeneratedUid = state.deviceId;
    const cacheLookupPromise = Promise.resolve()
      .then(() => window.caches.open('amr-device-secure-store-v1'))
      .then((cache) => (cache && typeof cache.match === 'function' ? cache.match('/__amr_device_uid') : null))
      .then((resp) => (resp && typeof resp.text === 'function' ? resp.text() : null))
      .catch(() => null);
    const timeoutPromise = new Promise((resolve) => {
      setTimeout(() => resolve(null), 250);
    });
    return Promise.race([cacheLookupPromise, timeoutPromise])
      .then((rawCachedUid) => {
        let candidate = String(rawCachedUid || '').trim();
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
          state.deviceIdWasFreshlyGenerated = false;
          state.supersededFreshDeviceId = freshlyGeneratedUid;
          persistUidToSecureStore(cachedUid);
          if (typeof syncDeviceInfoUI === 'function') {
            syncDeviceInfoUI();
          }
        } else {
          state.deviceIdWasFreshlyGenerated = false;
          persistUidToSecureStore(state.deviceId);
        }
      })
      .catch(() => {
        state.deviceIdWasFreshlyGenerated = false;
        persistUidToSecureStore(state.deviceId);
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
    btnAiMixByTrack: document.getElementById('btn-ai-mix-by-track'),
    stationOptAiVibeSub: document.getElementById('station-opt-ai-vibe-sub'),
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
    queueCurrentGroup: document.getElementById('queue-current-group'),
    queueCurrentTrack: document.getElementById('queue-current-track'),
    queueUpcomingList: document.getElementById('queue-upcoming-list'),
    btnSaveQueuePlaylist: document.getElementById('btn-save-queue-playlist'),
    btnSaveQueueText: document.getElementById('btn-save-queue-text'),
    btnClearQueue: document.getElementById('btn-clear-queue'),

    // Library Elements
    playlistsBrowsePane: document.getElementById('playlists-browse-pane'),
    playlistsGrid: document.getElementById('playlists-grid'),
    btnRefreshLibrary: document.getElementById('btn-refresh-library'),
    playlistDetailPane: document.getElementById('playlist-detail-pane'),
    btnBackToPlaylists: document.getElementById('btn-back-to-playlists'),
    detailArtwork: document.getElementById('detail-artwork'),
    detailTitle: document.getElementById('detail-title'),
    detailBadge: document.getElementById('detail-badge'),
    detailMeta: document.getElementById('detail-meta'),
    btnPlayPlaylist: document.getElementById('btn-play-playlist'),
    btnShufflePlaylist: document.getElementById('btn-shuffle-playlist'),
    btnAddPlaylistLibrary: document.getElementById('btn-add-playlist-library'),
    btnAddPlaylistLibraryText: document.getElementById('btn-add-playlist-library-text'),
    playlistTracksList: document.getElementById('playlist-tracks-list'),

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

  function connectWebSocket() {
    clearTimeout(reconnectTimer);
    state.initialViewSelected = false;

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
      state.initialAuthFetched = false;
      reconnectAttempt = 0;
      dom.overlay.classList.add('hidden');
      ensureScrubberLoopRunning();

      // Step 1: Register this PWA device UID & verify device authorization FIRST.
      // Apple ID / MusicKit / catalog checks run ONLY after the device is authorized on Mac.
      send({
        action: 'register_device',
        params: {
          device_id: state.deviceId,
          device_name: state.deviceName,
          device_type: state.deviceType,
          lock_screen_controls: state.lockScreenControls,
          invite_token: state.inviteToken || ''
        }
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
      state.initialViewSelected = false;
      dom.overlay.classList.remove('hidden');
      syncSilentAudio(false);
      syncMotionVideoPlaybackState();
      ScreenWakeLockManager.syncByPlaybackAndConnection();
      scheduleReconnect();
    };

    socket.onerror = function () {
      state.connected = false;
      state.initialViewSelected = false;
      dom.overlay.classList.remove('hidden');
      syncSilentAudio(false);
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
    if (!socket || socket.readyState !== WebSocket.OPEN) {
      return false;
    }
    const act = (msgObj && msgObj.action) ? msgObj.action.toLowerCase() : '';
    if (act === 'ai_curate' || act === 'ai_curate_from_track' || act === 'play_ai_track_vibe') {
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
      syncSilentAudio(true);
    } else if (act === 'pause' || act === 'stop') {
      syncSilentAudio(false);
    }
    socket.send(JSON.stringify(msgObj));
    return true;
  }

  // --- Server Message Dispatcher ---
  function handleServerMessage(msg) {
    if (!msg || typeof msg !== 'object') return;
    state.lastServerMessageAt = Date.now();
    const type = (msg.event || msg.action || msg.type || '').toLowerCase();
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
      setUIBusy(false);
      return;
    }

    const isSilentErrorType = (
      type === 'device_auth_status' ||
      type === 'register_device' ||
      type === 'get_developer_token' ||
      type === 'get_artwork' ||
      type === 'get_lyrics' ||
      type === 'get_booklet_info' ||
      type === 'client_log'
    );

    if (msg.status === 'error') {
      const isAiErrorType = (
        type === 'ai_curate' ||
        type === 'ai_curate_from_track' ||
        type === 'play_ai_track_vibe' ||
        type === 'curate_music' ||
        type === 'ai_curate_result'
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
        if (type === 'get_album' || type === 'album' || type === 'get_playlist_tracks' || type === 'playlist_tracks') {
          if (dom.playlistTracksList) {
            dom.playlistTracksList.innerHTML = `<div class="empty-state">${escapeHtml(errText || translateTextToEn('Не удалось загрузить треки'))}</div>`;
          }
        } else if (isAiErrorType) {
          isSearchLoadingMore = false;
          if (dom.searchResults && dom.searchResults.querySelector('.loading-state')) {
            dom.searchResults.innerHTML = `<div class="empty-state">${escapeHtml(errText)}</div>`;
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
            if (dom.btnAddPlaylistLibrary && !dom.btnAddPlaylistLibrary.classList.contains('added')) {
              dom.btnAddPlaylistLibrary.disabled = false;
              if (dom.btnAddPlaylistLibraryText) dom.btnAddPlaylistLibraryText.textContent = 'В медиатеку';
            }
          }
          if (!targetSource || targetSource === 'ai' || targetSource === 'hero') {
            const aiSaveBtn = dom.btnAiCuratedSave || document.getElementById('btn-ai-curated-save');
            const aiSaveText = dom.btnAiCuratedSaveText || document.getElementById('btn-ai-curated-save-text');
            if (aiSaveBtn && !aiSaveBtn.classList.contains('added')) {
              aiSaveBtn.disabled = false;
              if (aiSaveText) aiSaveText.textContent = translateTextToEn('В медиатеку');
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

      case 'ai_curator_settings':
      case 'get_ai_curator_settings':
      case 'refresh_ai_prompts':
        handleAiCuratorSettings(data);
        break;

      case 'get_artwork_palette':
      case 'artwork_palette':
        AmbientBackgroundManager.applyServerPalette(data);
        break;

      case 'player_state_changed':
      case 'status':
      case 'get_status':
        updatePlayerState(data);
        break;

      case 'queue_changed':
      case 'queue':
      case 'get_queue':
        updateQueue(data);
        break;

      case 'playlists':
      case 'get_playlists':
      case 'playlists_result':
        updatePlaylists(data);
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

      case 'motion_artwork':
      case 'get_motion_artwork':
        applyMotionArtwork(data);
        break;

      case 'get_spectral_analysis':
      case 'spectral_analysis':
        if (data && data.verdict) {
          state.spectralAnalysis = data;
          state.lastSpectralUpdateAt = performance.now();
          updateSignalPathDetails();
        }
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
      case 'add_album_to_library': {
        const ok = (data && typeof data.status === 'string') ? (data.status === 'ok') : (msg.status === 'ok');
        const targetSource = (state.lastLibraryAddTarget && typeof state.lastLibraryAddTarget === 'object')
          ? state.lastLibraryAddTarget.source
          : state.lastLibraryAddTarget;
        const isAlb = (data && typeof data.is_album === 'boolean')
          ? data.is_album
          : (type === 'add_album_to_library' || Boolean(targetSource === 'detail' && state.currentPlaylistDetail && state.currentPlaylistDetail.isAlbum));
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
          if (targetSource !== 'ai' && matchesDetailTarget && dom.btnAddPlaylistLibrary && (!dom.playlistDetailPane || !dom.playlistDetailPane.classList.contains('hidden'))) {
            dom.btnAddPlaylistLibrary.disabled = true;
            if (dom.btnAddPlaylistLibraryText) dom.btnAddPlaylistLibraryText.textContent = 'В медиатеке ✓';
            dom.btnAddPlaylistLibrary.classList.add('added');
            if (state.currentPlaylistDetail) {
              state.currentPlaylistDetail.is_local = true;
            }
          }
          if (isAiTarget && aiSaveBtn) {
            aiSaveBtn.disabled = true;
            aiSaveBtn.classList.add('added');
            if (aiSaveText) aiSaveText.textContent = translateTextToEn('В медиатеке ✓');
          }
          showToast(isAlb ? '★ Альбом добавлен в медиатеку Apple Music' : '★ Плейлист добавлен в медиатеку Apple Music');
        } else {
          if ((!targetSource || targetSource === 'detail') && matchesDetailTarget && dom.btnAddPlaylistLibrary && !dom.btnAddPlaylistLibrary.classList.contains('added')) {
            dom.btnAddPlaylistLibrary.disabled = false;
            if (dom.btnAddPlaylistLibraryText) dom.btnAddPlaylistLibraryText.textContent = 'В медиатеку';
          }
          if ((!targetSource || targetSource === 'ai' || targetSource === 'hero') && aiSaveBtn && !aiSaveBtn.classList.contains('added')) {
            aiSaveBtn.disabled = false;
            if (aiSaveText) aiSaveText.textContent = translateTextToEn('В медиатеку');
          }
          showToast(translateTextToEn((data && data.message) || msg.error || 'Не удалось добавить в медиатеку'));
        }
        break;
      }

      case 'save_queue_to_playlist': {
        const ok = (data && typeof data.status === 'string') ? (data.status === 'ok') : (msg.status === 'ok');
        if (ok) {
          if (dom.btnSaveQueuePlaylist) {
            dom.btnSaveQueuePlaylist.disabled = true;
            dom.btnSaveQueuePlaylist.classList.add('saved');
          }
          if (dom.btnSaveQueueText) {
            dom.btnSaveQueueText.textContent = translateTextToEn('В медиатеке ✓');
          }
          showToast(translateTextToEn('★ Очередь сохранена в плейлисты Apple Music'));
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

    // Dynamic initial view: on first player state / status message after connection
    if (!state.initialViewSelected) {
      state.initialViewSelected = true;
      if (state.playbackState === 'playing') {
        switchMobileView('view-now-playing');
      } else {
        switchMobileView('view-home');
        switchDesktopTab('home');
      }
    }

    state.duration = Number(data.duration) || 0;
    const reportedPos = Math.max(0, Number(data.position) || 0);

    if (isNewTrack) {
      state.lastSyncPos = reportedPos;
      state.position = reportedPos;
      state.lastSyncTime = performance.now();
      state.lastSyncPerf = state.lastSyncTime;
      if (!state.isScrubbing) {
        updateScrubberUI(reportedPos, state.duration);
      }
    } else if (!state.isScrubbing) {
      const now = performance.now();
      if (state.playerState !== 'playing') {
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

    state.shuffle = Boolean(data.shuffle);
    state.repeatMode = data.repeat || data.repeatMode || 'off';
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
    if (data.dac_muting_guard_enabled !== undefined || data.isDacMutingGuardEnabled !== undefined) {
      state.dacMutingGuardEnabled = data.dac_muting_guard_enabled !== undefined ? Boolean(data.dac_muting_guard_enabled) : Boolean(data.isDacMutingGuardEnabled);
    }
    if (data.dac_muting_guard_ms !== undefined || data.dacMutingGuardMs !== undefined) {
      state.dacMutingGuardMs = Number(data.dac_muting_guard_ms || data.dacMutingGuardMs) || 100;
    }
    const hasTrackSwitched = Boolean(
      oldTrack && newTrack && (newTrack.name !== oldTrack.name || newTrack.artist !== oldTrack.artist)
    );
    const incomingSa = data.spectral_analysis || data.spectralAnalysis;
    if (hasTrackSwitched) {
      const prevEnabled = incomingSa && incomingSa.is_enabled !== undefined
        ? Boolean(incomingSa.is_enabled)
        : (state.spectralAnalysis ? (state.spectralAnalysis.is_enabled !== false && state.spectralAnalysis.isEnabled !== false) : true);
      state.spectralAnalysis = Object.assign({}, incomingSa || {}, {
        is_enabled: prevEnabled,
        verdict: prevEnabled ? 'analyzing' : 'disabled',
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
    } else if (!state.lockVolume100) {
      state.ampVolumeControlEnabled = false;
    }
    if (data.amp_brand_name !== undefined && data.amp_brand_name) {
      state.ampBrandName = String(data.amp_brand_name);
    }
    if (data.amp_max_volume !== undefined && Number(data.amp_max_volume) > 0) {
      state.ampMaxVolume = Number(data.amp_max_volume);
    }
    const prevVol = state.volume;
    const prevMute = state.ampMuted;
    if (data.amp_muted !== undefined) {
      state.ampMuted = Boolean(data.amp_muted);
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
      if (state.volume >= 5) {
        state.previousVolume = state.volume;
      }
    }
    if (!state.isDraggingVolume && state.initialViewSelected && (state.volume !== prevVol || state.ampMuted !== prevMute)) {
      triggerStandbyVolumePulse();
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
      return track.artworkUrl;
    }
    if (track.artwork_url && track.artwork_url.length > 5) {
      return track.artwork_url;
    }
    if (track.artwork && track.artwork.length > 5) {
      return track.artwork;
    }
    if (track.artwork_data_base64) {
      return `data:image/jpeg;base64,${track.artwork_data_base64}`;
    }
    if (track.is_local && track.id && Number(track.id) > 0) {
      return `/api/artwork/track?id=${track.id}`;
    }
    if (track.name) {
      const q = new URLSearchParams();
      q.set('name', track.name);
      if (track.artist) q.set('artist', track.artist);
      if (track.album) q.set('album', track.album);
      return `/api/artwork/search?${q.toString()}`;
    }
    if (track.id && Number(track.id) > 0) {
      return `/api/artwork/track?id=${track.id}`;
    }
    return '/api/artwork';
  }

  // ==========================================================================
  // Apple TV Style Dynamic Blurred Ambient Gradient Background Manager
  // ==========================================================================
  const AmbientBackgroundManager = {
    activeLayer: 'a', // 'a' or 'b'
    currentPaletteKey: '',
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
      if (state.wledEnabled) {
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

      // When Native AI (Apple Neural Engine) is enabled, request Vision Saliency palette from macOS
      if (state.aiCuratorEnabled) {
        send({
          action: 'get_artwork_palette',
          params: {
            url: artUrl,
            track_id: Number(state.currentTrackId || 0) || 0
          }
        });
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
    }
  };

  let currentLoadedArtworkUrl = '';
  function setPlayerArtwork(artUrl) {
    if (!artUrl) artUrl = 'apple-touch-icon.svg';
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

    // Preload image to prevent showing old track's image if new image fails or loads slowly
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => {
      if (dom.playerArtwork.dataset.targetSrc === artUrl) {
        dom.playerArtwork.src = artUrl;
        dom.playerArtwork.style.opacity = '1';
        currentLoadedArtworkUrl = artUrl;
        if (dom.miniArt) {
          dom.miniArt.src = artUrl;
          dom.miniArt.style.opacity = '1';
        }
        AmbientBackgroundManager.updateFromImage(img, artUrl);
      }
    };
    img.onerror = () => {
      if (dom.playerArtwork.dataset.targetSrc === artUrl) {
        dom.playerArtwork.src = 'apple-touch-icon.svg';
        dom.playerArtwork.style.opacity = '1';
        currentLoadedArtworkUrl = 'apple-touch-icon.svg';
        if (dom.miniArt) {
          dom.miniArt.src = 'apple-touch-icon.svg';
          dom.miniArt.style.opacity = '1';
        }
        AmbientBackgroundManager.clear();
      }
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

  function renderNowPlaying() {
    const isPlaying = state.playerState === 'playing';
    const t = state.track;

    // Track Meta
    if (t) {
      const titleText = t.name || 'Без названия';
      const albumText = (t.album || '').trim();
      const artistText = t.artist || 'Неизвестный исполнитель';
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
      if (dom.playerTitle.textContent !== 'Не играет') {
        dom.playerTitle.textContent = 'Не играет';
      }
      dom.playerTitle.title = 'Не играет';
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
        dom.btnGoToAlbum.title = 'Перейти к альбому';
      }
      if (dom.btnAiTrackVibe) {
        dom.btnAiTrackVibe.disabled = true;
        dom.btnAiTrackVibe.classList.toggle('hidden', !state.aiCuratorEnabled);
        dom.btnAiTrackVibe.title = translateTextToEn('✨ ИИ-подбор по вайбу текущего трека');
      }
      setPlayerArtwork('apple-touch-icon.svg');
      dom.btnFavorite.classList.remove('active');
      if (dom.miniBtnFavorite) dom.miniBtnFavorite.classList.remove('active');

      if (dom.miniTitle.textContent !== 'Не играет') {
        dom.miniTitle.textContent = 'Не играет';
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
    dom.btnShuffle.classList.toggle('active', state.shuffle);
    if (state.repeatMode === 'one') {
      dom.btnRepeat.classList.add('active');
      dom.repeatBadge.classList.remove('hidden');
    } else if (state.repeatMode === 'all') {
      dom.btnRepeat.classList.add('active');
      dom.repeatBadge.classList.add('hidden');
    } else {
      dom.btnRepeat.classList.remove('active');
      dom.repeatBadge.classList.add('hidden');
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

    // Only update scrubber UI here if stopped or paused.
    // When playing, the 60fps scrubberAnimationLoop handles smooth rendering without jitter!
    if (!state.isScrubbing && state.playerState !== 'playing') {
      updateScrubberUI(state.lastSyncPos, state.duration);
    }
    ensureScrubberLoopRunning();

    renderVolumeUI();
    renderCurrentQueueTrack(dom.queueCurrentTrack);
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

    const brand = state.ampBrandName || 'Усилитель';
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
    syncSignalPathAmpNode();

    if (state.lockVolume100 && !isExtAmpMode) {
      if (dom.volumeSection) dom.volumeSection.classList.add('hidden');
      if (dom.standbyVolumeSection) dom.standbyVolumeSection.classList.add('hidden');
      if (dom.playerBottomNotice) {
        dom.playerBottomNotice.textContent = 'Прямой вывод CoreAudio (Bit-Perfect DAC • 100%)';
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
        dom.playerBottomNotice.textContent = 'Прямой вывод CoreAudio (Регулируемая громкость)';
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

  // --- Tactile & Haptic Engine ---
  let hapticAudioCtx = null;
  function getHapticAudioContext() {
    if (!hapticAudioCtx) {
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (AudioCtx) {
        hapticAudioCtx = new AudioCtx();
      }
    }
    if (hapticAudioCtx && hapticAudioCtx.state === 'suspended') {
      hapticAudioCtx.resume().catch(() => {});
    }
    return hapticAudioCtx;
  }

  function triggerHaptic(type = 'light') {
    // 1. Native Vibration API (Android, Chrome, supported browsers)
    if ('vibrate' in navigator) {
      try {
        if (type === 'light') navigator.vibrate(15);
        else if (type === 'medium') navigator.vibrate(28);
        else if (type === 'heavy') navigator.vibrate(45);
        else if (type === 'toggle') navigator.vibrate([15, 30, 25]);
      } catch (e) {}
    }

    // 2. iOS Speaker Transducer Micro-Thump (Physical recoil pulse in iPhone chassis)
    try {
      const ctx = getHapticAudioContext();
      if (!ctx) return;
      if (ctx.state === 'suspended') {
        ctx.resume().catch(() => {});
      }
      const now = ctx.currentTime;
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.onended = () => {
        try { osc.disconnect(); } catch (_) {}
        try { gain.disconnect(); } catch (_) {}
      };

      osc.type = 'sine';
      if (type === 'light') {
        // Fast subtle tap (75Hz down to 25Hz, 18ms, gain 0.85)
        osc.frequency.setValueAtTime(75, now);
        osc.frequency.exponentialRampToValueAtTime(25, now + 0.018);
        gain.gain.setValueAtTime(0.85, now);
        gain.gain.exponentialRampToValueAtTime(0.001, now + 0.018);
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(now);
        osc.stop(now + 0.018);
      } else if (type === 'medium') {
        // Firm mechanical thump (85Hz down to 25Hz, 30ms, gain 1.0)
        osc.frequency.setValueAtTime(85, now);
        osc.frequency.exponentialRampToValueAtTime(25, now + 0.03);
        gain.gain.setValueAtTime(1.0, now);
        gain.gain.exponentialRampToValueAtTime(0.001, now + 0.03);
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(now);
        osc.stop(now + 0.03);
      } else if (type === 'toggle') {
        // Double-click toggle (like switch / like button)
        osc.frequency.setValueAtTime(95, now);
        osc.frequency.exponentialRampToValueAtTime(30, now + 0.018);
        gain.gain.setValueAtTime(0.85, now);
        gain.gain.exponentialRampToValueAtTime(0.001, now + 0.018);
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(now);
        osc.stop(now + 0.018);

        const osc2 = ctx.createOscillator();
        const gain2 = ctx.createGain();
        osc2.onended = () => {
          try { osc2.disconnect(); } catch (_) {}
          try { gain2.disconnect(); } catch (_) {}
        };
        osc2.type = 'sine';
        osc2.frequency.setValueAtTime(110, now + 0.026);
        osc2.frequency.exponentialRampToValueAtTime(35, now + 0.046);
        gain2.gain.setValueAtTime(0.9, now + 0.026);
        gain2.gain.exponentialRampToValueAtTime(0.001, now + 0.046);
        osc2.connect(gain2);
        gain2.connect(ctx.destination);
        osc2.start(now + 0.026);
        osc2.stop(now + 0.046);
      }
    } catch (e) {}
  }

  // --- Silent Audio Loop for iOS Background & Lock Screen Keep-Alive ---
  let silentAudioEl = null;
  let silentAudioUnlocked = false;

  function attachSilentAudioListeners(el) {
    if (!el || el._amrListenersAttached) return;
    el._amrListenersAttached = true;

    const onAudioStateChange = () => {
      setupMediaSession();
      updateMediaSession();
    };

    ['play', 'playing', 'pause', 'canplay', 'loadedmetadata'].forEach((evt) => {
      el.addEventListener(evt, onAudioStateChange, { passive: true });
    });

    const handleSilentAudioError = () => {
      const curSrc = el.getAttribute('src') || '';
      if (curSrc.includes('silence.m4a') && !el._amrWavFallbackTried) {
        el._amrWavFallbackTried = true;
        el.src = '/assets/silence.wav?v=2';
        try { el.load(); } catch (_) {}
        if (state.playerState === 'playing' && state.lockScreenControls && state.deviceAuthorized) {
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
    if (!state.lockScreenControls || !state.deviceAuthorized) {
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
      silentAudioEl.preload = 'auto';
      silentAudioEl.style.cssText = 'position:fixed;bottom:0;left:0;width:1px;height:1px;opacity:0.001;pointer-events:none;z-index:-1;';
      attachSilentAudioListeners(silentAudioEl);
      silentAudioEl.src = '/assets/silence.m4a?v=2';
      document.body.appendChild(silentAudioEl);
    } else {
      silentAudioEl.preload = 'auto';
      attachSilentAudioListeners(silentAudioEl);
      if (!silentAudioEl.getAttribute('src') && !silentAudioEl.querySelector('source')) {
        silentAudioEl._amrWavFallbackTried = false;
        silentAudioEl.src = '/assets/silence.m4a?v=2';
      }
    }
    return silentAudioEl;
  }

  function teardownMediaSessionAndSilentAudio() {
    const el = silentAudioEl || document.getElementById('bg-silent-audio');
    if (el) {
      try {
        el.pause();
        el.currentTime = 0;
        if (el.hasAttribute('src')) {
          el.removeAttribute('src');
          el.load();
        }
      } catch (e) {}
    }
    silentAudioUnlocked = false;
    lastMediaSessionKey = '';
    bindUnlockAudioGestureListeners();

    if ('mediaSession' in navigator) {
      try {
        navigator.mediaSession.playbackState = 'none';
        navigator.mediaSession.metadata = null;
        ['play', 'pause', 'previoustrack', 'nexttrack', 'seekto', 'seekbackward', 'seekforward', 'stop'].forEach((act) => {
          try { navigator.mediaSession.setActionHandler(act, null); } catch (e) {}
        });
      } catch (e) {}
    }
  }

  function syncSilentAudio(isPlaying) {
    if (!state.lockScreenControls || !state.deviceAuthorized) {
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
            setupMediaSession();
            updateMediaSession();
          }).catch((err) => {
            console.warn('[AudioKeepAlive] play error:', err);
          });
        }
      } else {
        setupMediaSession();
      }
    } else {
      if (!el.paused) {
        el.pause();
      }
      setupMediaSession();
    }
  }

  const UNLOCK_GESTURE_EVENTS = ['pointerdown', 'touchstart', 'touchend', 'click'];
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

  // Synchronously unlock audio & Web Audio on user gesture until unlocked
  function unlockAudioOnUserGesture() {
    const ctx = getHapticAudioContext();
    if (ctx && ctx.state === 'suspended') {
      ctx.resume().catch(() => {});
    }

    if (!state.lockScreenControls || !state.deviceAuthorized) {
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
          if (state.playerState !== 'playing') {
            el.pause();
          }
          setupMediaSession();
          updateMediaSession();
        }).catch(() => {});
      }
    }
  }

  bindUnlockAudioGestureListeners();

  // Re-bind MediaSession on app wake, unlock, or tab switch
  ['visibilitychange', 'pageshow', 'focus'].forEach((evt) => {
    window.addEventListener(evt, () => {
      if (!document.hidden) {
        setupMediaSession();
        updateMediaSession();
      }
    }, { passive: true });
  });

  // Global tactile feedback on all interactive elements
  let lastGlobalHapticTime = 0;
  document.addEventListener('pointerup', (e) => {
    const now = Date.now();
    if (now - lastGlobalHapticTime < 80) return;
    const target = e.target.closest('button, .track-row, .playlist-card, .hero-card, .station-card, .media-card, .genre-card, .tab-item, .nav-btn, .search-chip, .quality-badge, .pill, .mini-btn, .mini-player-content');
    if (target) {
      lastGlobalHapticTime = now;
      triggerHaptic('light');
    }
  }, { passive: true });

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
    if (hadClass !== isTextFocused) {
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

  // --- MediaSession (Lock Screen, Dynamic Island, AirPods, Control Center) ---
  let lastMediaSessionKey = '';
  function setupMediaSession() {
    if (!('mediaSession' in navigator)) return;
    if (!state.lockScreenControls || !state.deviceAuthorized) {
      teardownMediaSessionAndSilentAudio();
      return;
    }

    try {
      navigator.mediaSession.setActionHandler('play', () => {
        triggerHaptic('medium');
        syncSilentAudio(true);
        optimisticPlay();
        setupMediaSession();
        updateMediaSession();
        send({ action: 'play' });
      });

      navigator.mediaSession.setActionHandler('pause', () => {
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
        setupMediaSession();
        updateMediaSession();
        send({ action: 'pause' });
      });

      navigator.mediaSession.setActionHandler('previoustrack', () => {
        triggerHaptic('medium');
        sendThrottledTransport('previous');
      });

      navigator.mediaSession.setActionHandler('nexttrack', () => {
        triggerHaptic('medium');
        sendThrottledTransport('next');
      });

      navigator.mediaSession.setActionHandler('seekto', (details) => {
        if (details.seekTime != null && !isNaN(details.seekTime)) {
          triggerHaptic('light');
          const curPos = Math.max(0, details.seekTime);
          if (silentAudioEl && Number.isFinite(silentAudioEl.duration) && silentAudioEl.duration > 0) {
            try { silentAudioEl.currentTime = curPos % silentAudioEl.duration; } catch (e) {}
          }
          sendSeek(details.seekTime);
        }
      });

      // Disable seekbackward & seekforward so iOS Lock Screen, Dynamic Island,
      // and Control Center display Previous / Next Track buttons (⏮ / ⏭) instead of ±10s/±15s buttons.
      try { navigator.mediaSession.setActionHandler('seekbackward', null); } catch (e) {}
      try { navigator.mediaSession.setActionHandler('seekforward', null); } catch (e) {}

      navigator.mediaSession.setActionHandler('stop', () => {
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
        setupMediaSession();
        updateMediaSession();
        send({ action: 'stop' });
      });
    } catch (err) {
      console.warn('[MediaSession] Handler setup:', err);
    }
  }

  function updateMediaSession() {
    if (!('mediaSession' in navigator)) return;
    if (!state.lockScreenControls || !state.deviceAuthorized) {
      teardownMediaSessionAndSilentAudio();
      return;
    }

    // Ensure action handlers are persistently bound to the active WebKit MediaSession
    setupMediaSession();

    const isPlaying = state.playerState === 'playing';
    syncSilentAudio(isPlaying);

    navigator.mediaSession.playbackState = isPlaying ? 'playing' : 'paused';

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
      } catch (e) {
        console.warn('[MediaSession] Metadata update error:', e);
      }
    }

    if ('setPositionState' in navigator.mediaSession) {
      if (state.duration > 0) {
        try {
          const nowPerf = performance.now();
          const syncBase = state.lastSyncPerf || state.lastSyncTime || nowPerf;
          const livePos = (state.lastSyncPos || 0) + (isPlaying ? Math.max(0, (nowPerf - syncBase) / 1000) : 0);
          const curPos = Math.min(Math.max(0, livePos), state.duration);
          navigator.mediaSession.setPositionState({
            duration: Math.max(state.duration, 0.1),
            playbackRate: isPlaying ? 1.0 : 0.0,
            position: curPos
          });
          if (silentAudioEl && !silentAudioEl.paused && curPos >= 0 && Number.isFinite(silentAudioEl.duration) && silentAudioEl.duration > 0) {
            const targetLoopPos = curPos % silentAudioEl.duration;
            const drift = Math.abs(silentAudioEl.currentTime - targetLoopPos);
            if (drift > 3.0) {
              try { silentAudioEl.currentTime = targetLoopPos; } catch (e) {}
            }
          }
        } catch (e) {}
      } else {
        try { navigator.mediaSession.setPositionState(null); } catch (e) {}
      }
    }
  }

  function cleanAudioQualityLabel(raw) {
    if (!raw) return 'LOSSLESS';
    const up = raw.toUpperCase();
    if (up.includes('HI-RES')) return 'HI-RES LOSSLESS';
    if (up.includes('LOSSLESS')) return 'LOSSLESS';
    if (up.includes('AAC')) return 'AAC 256';
    if (up.includes('ALAC')) return 'ALAC LOSSLESS';
    return raw;
  }

  function formatDacPill(raw) {
    if (!raw) return 'Bit-Perfect DAC';
    const up = raw.toUpperCase();
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

  // --- Optimistic Scrubber Loop (throttled to ~20fps normally, 4fps in TV Mode) ---
  let scrubberRafId = 0;

  function ensureScrubberLoopRunning() {
    if (!scrubberRafId && state.connected && state.playerState === 'playing' && !document.hidden) {
      scrubberRafId = requestAnimationFrame(scrubberAnimationLoop);
    }
  }

  function scrubberAnimationLoop(nowMs) {
    scrubberRafId = 0;
    if (!state.connected || state.playerState !== 'playing' || document.hidden) {
      return;
    }
    if (!state.isScrubbing && state.duration > 0) {
      const ts = nowMs || performance.now();
      const intervalMs = isStandbyOrLandscapeVisible() ? 250 : 50;
      if (ts - lastScrubberFrameMs >= intervalMs) {
        lastScrubberFrameMs = ts;
        const deltaSec = (ts - state.lastSyncTime) / 1000;
        const rawPos = state.lastSyncPos + deltaSec;
        const currentPos = Math.min(state.duration, rawPos);
        state.position = currentPos;
        updateScrubberUI(currentPos, state.duration);

        // If spectral data went stale (>1.2s) while RTA bars are still raised above floor, wake up RTA decay loop
        if (!standbyRtaRafId && (ts - (state.lastSpectralUpdateAt || 0)) > 1200 && isStandbyOrLandscapeVisible()) {
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
    scrubberRafId = requestAnimationFrame(scrubberAnimationLoop);
  }
  ensureScrubberLoopRunning();

  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) {
      ensureScrubberLoopRunning();
    }
    syncSpectralPolling();
  });

  // --- WebSocket Half-Open & Track Transition Watchdog ---
  setInterval(() => {
    if (!state.connected || !state.deviceAuthorized) return;
    if (document.hidden) return;
    const silenceMs = Date.now() - (state.lastServerMessageAt || Date.now());
    if (state.playerState === 'playing') {
      if (silenceMs >= 9000) {
        // Half-open TCP/WebSocket connection stalled for >9s during active playback: force reconnect
        connectWebSocket();
      } else if (silenceMs >= 4500) {
        send({ action: 'get_status' });
        send({ action: 'get_queue' });
      }
    }
  }, 2500);

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
    state.lastSyncPos = targetPos;
    state.lastSyncTime = performance.now();
    state.lastSyncPerf = state.lastSyncTime;
    state.position = targetPos;
    updateScrubberUI(targetPos, state.duration);
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
    state.lastSyncTime = performance.now();
    state.lastSyncPerf = state.lastSyncTime;
    state.playerState = 'playing';
    state.playbackState = 'playing';
    renderNowPlaying();
  }

  function togglePlayPause(e) {
    if (e) {
      e.preventDefault();
      e.stopPropagation();
    }
    triggerHaptic('medium');
    const isPlaying = state.playerState === 'playing';
    syncSilentAudio(!isPlaying);
    if (isPlaying) {
      state.pendingPlayUntil = 0;
      const now = performance.now();
      state.lastSyncPos = Math.min(state.duration, state.lastSyncPos + (now - state.lastSyncTime) / 1000);
      state.position = state.lastSyncPos;
      state.lastSyncTime = now;
      state.lastSyncPerf = now;
      state.playerState = 'paused';
      state.playbackState = 'paused';
      renderNowPlaying();
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

  dom.btnShuffle.addEventListener('click', () => {
    triggerHaptic('toggle');
    send({
      action: 'set_shuffle',
      params: { enabled: !state.shuffle }
    });
  });

  dom.btnRepeat.addEventListener('click', () => {
    triggerHaptic('toggle');
    const modes = ['off', 'all', 'one'];
    const nextIdx = (modes.indexOf(state.repeatMode) + 1) % modes.length;
    const nextMode = modes[nextIdx];
    send({
      action: 'set_repeat',
      params: { mode: nextMode }
    });
  });

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
    hud.textContent = message;
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
    const isLossy = up.includes('AAC') || up.includes('MP3');
    const devRateHz = state.audioDeviceSampleRate || 44100;
    const rateKhz = (devRateHz / 1000).toFixed(1).replace(/\.0$/, '');
    const outBitDepth = isLossy ? 16 : (state.audioDeviceBitDepth || (devRateHz >= 48000 ? 24 : 16));

    let formatBadge = 'ALAC Lossless';
    if (up.includes('192') || up.includes('HI-RES')) {
      formatBadge = 'ALAC Hi-Res';
    } else if (isLossy) {
      formatBadge = 'AAC 256k';
    } else if (up.includes('LOSSLESS') || up.includes('ALAC')) {
      formatBadge = 'ALAC Lossless';
    }

    // Parse source sample rate and bit depth for Bit-Perfect verification
    const rateMatch = quality.match(/(\d+(?:\.\d+)?)\s*(?:kHz|кГц)/i);
    const sourceRateHz = rateMatch ? Math.round(parseFloat(rateMatch[1]) * 1000) : (t && (t.sample_rate || t.sampleRate) ? Number(t.sample_rate || t.sampleRate) : null);
    const depthMatch = quality.match(/(\d+)-(?:bit|бит)/i);
    const sourceBitDepth = depthMatch ? parseInt(depthMatch[1], 10) : (t && (t.bit_depth || t.bitDepth) ? Number(t.bit_depth || t.bitDepth) : null);

    const ratesMatch = !sourceRateHz || Math.abs(sourceRateHz - devRateHz) <= 500;
    const depthsMatch = !sourceBitDepth || outBitDepth >= sourceBitDepth;
    const isHardwareMatched = (state.isBitPerfect !== false) && ratesMatch && depthsMatch;
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
      if (!isPendingValidation) {
        const badgeQualityClass = isSpectralFake
          ? 'quality-bad'
          : ((isSpectralZeroPad || (!isLossy && !isHardwareMatched)) ? 'quality-warn' : 'quality-ok');
        badge.classList.add(badgeQualityClass);
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
      dom.signalSourceDetails.textContent = isLossy ? 'AAC 256 kbps → Декодирование в PCM 16-бит / 44.1 кГц' : quality;
    }
    if (dom.signalDacRate) {
      dom.signalDacRate.textContent = `${rateKhz} кГц`;
    }
    const activeDev = (state.audioDevices || []).find(d => d.name === state.audioDeviceName || d.isDefault);
    const isNetworkRenderer = (activeDev && activeDev.type === 'dlna') || (state.audioDeviceName && (state.audioDeviceName.includes('(') || state.audioDeviceName.includes('NODE') || state.audioDeviceName.includes('Bluesound') || state.audioDeviceName.includes('DLNA')));

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
    const signalEngineMeta = document.querySelector('#signal-node-engine .signal-node-meta');
    if (signalEngineMeta) {
      if (isNetworkRenderer) {
        signalEngineMeta.textContent = isLossy
          ? 'CoreAudio Process Tap • Декодирование AAC → PCM 16-бит / 44.1 кГц'
          : 'CoreAudio Process Tap (Bit-Perfect) • Бесконечный PCM поток';
      } else {
        const guardLabel = state.dacMutingGuardEnabled === true
          ? `DAC Muting Guard (${state.dacMutingGuardMs || 100} мс)`
          : 'Bypass микшера';
        const ampLabel = (state.lockVolume100 && state.ampVolumeControlEnabled)
          ? `${state.ampBrandName || 'AMP'} TCP Vol ${state.ampMuted ? 'MUTE' : state.volume}`
          : 'Zero DSP';
        signalEngineMeta.textContent = isLossy
          ? 'CoreAudio HAL • Декодирование AAC → PCM 16-бит / 44.1 кГц'
          : `Bit-Perfect 100% Lock • ${guardLabel} • ${ampLabel}`;
      }
    }
    const signalVerifiedCard = document.querySelector('.signal-verified-card');
    const signalVerifiedTitle = document.querySelector('.signal-verified-title');
    const signalVerifiedDesc = document.querySelector('.signal-verified-desc');
    const hasTopWarning = !isVerified || isSpectralFake || isSpectralZeroPad;
    if (signalVerifiedCard) {
      signalVerifiedCard.classList.toggle('warning', hasTopWarning);
    }
    if (signalVerifiedTitle && signalVerifiedDesc) {
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
        const srcBits = sourceBitDepth || 24;
        signalVerifiedTitle.textContent = `Передискретизация (${srcBits}/${srcKhz} → ${outBitDepth}/${rateKhz})`;
        signalVerifiedDesc.textContent = `Частота или разрядность источника (${srcBits}-бит / ${srcKhz} кГц) отличается от текущего режима вывода (${outBitDepth}-бит / ${rateKhz} кГц).`;
      }
    }
    syncSignalPathAmpNode();
    renderSpectralAnalysisUI();
  }

  let spectralPollTimer = null;
  let standbyRtaRafId = null;
  let lastStandbyRtaFrameMs = 0;
  let cachedStandbyRtaBackdrop = null;
  let cachedStandbyRtaBarsWrap = null;
  let standbyRtaBarEls = [];
  const standbyRtaBarCount = 64;
  const standbyRtaCurrent = new Float32Array(standbyRtaBarCount).fill(0.03);
  const standbyRtaTarget = new Float32Array(standbyRtaBarCount).fill(0.03);
  const standbyRtaVelocity = new Float32Array(standbyRtaBarCount).fill(0.0);
  const standbyRtaRendered = new Float32Array(standbyRtaBarCount).fill(-1);
  const standbyRtaClassState = new Uint8Array(standbyRtaBarCount).fill(255);

  function stepStandbyRtaAnimation(nowMs) {
    const sa = state.spectralAnalysis || {};
    const saEnabled = sa.is_enabled !== false && sa.isEnabled !== false && sa.verdict !== 'disabled';
    if (standbyRtaBarEls.length !== standbyRtaBarCount || !saEnabled || !isStandbyOrLandscapeVisible()) {
      standbyRtaRafId = null;
      return;
    }

    const ts = nowMs || performance.now();
    // Cap RTA GPU transform updates to ~24fps (40ms) so iPad mini / ProMotion displays stay cool
    if (ts - lastStandbyRtaFrameMs < 40) {
      standbyRtaRafId = requestAnimationFrame(stepStandbyRtaAnimation);
      return;
    }
    lastStandbyRtaFrameMs = ts;

    // If spectral updates stopped arriving (>1.2s stale) or player is not playing, decay targets to floor
    // so spectrum bars never freeze in mid-air during track transitions or stalls.
    const spectralStale = (ts - (state.lastSpectralUpdateAt || 0)) > 1200;
    const shouldDecayToFloor = (state.playerState !== 'playing') || spectralStale;

    let hasMotion = false;

    for (let i = 0; i < standbyRtaBarCount; i++) {
      if (shouldDecayToFloor && standbyRtaTarget[i] > 0.03) {
        standbyRtaTarget[i] = Math.max(0.03, standbyRtaTarget[i] * 0.82);
        if (standbyRtaTarget[i] > 0.032) {
          hasMotion = true;
        }
      }
      const tgt = Math.max(0.025, Math.min(0.96, standbyRtaTarget[i]));
      const cur = standbyRtaCurrent[i];
      const diff = tgt - cur;

      // Smooth spring-damped interpolation (soft attack, silky exponential release)
      const factor = diff > 0 ? 0.24 : 0.13;
      standbyRtaVelocity[i] = standbyRtaVelocity[i] * 0.52 + diff * factor;
      const nextVal = Math.max(0.025, Math.min(0.96, cur + standbyRtaVelocity[i]));
      standbyRtaCurrent[i] = nextVal;

      if (Math.abs(diff) > 0.003 || Math.abs(standbyRtaVelocity[i]) > 0.002) {
        hasMotion = true;
      }

      if (Math.abs(nextVal - standbyRtaRendered[i]) > 0.003) {
        standbyRtaRendered[i] = nextVal;
        const bar = standbyRtaBarEls[i];
        if (bar) {
          bar.style.transform = `scale3d(1, ${nextVal.toFixed(3)}, 1)`;
        }
      }
    }

    if (hasMotion) {
      standbyRtaRafId = requestAnimationFrame(stepStandbyRtaAnimation);
    } else {
      standbyRtaRafId = null;
    }
  }

  function ensureStandbyRtaAnimLoop() {
    if (!standbyRtaRafId && isStandbyOrLandscapeVisible()) {
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

    // 1. Interpolate 32 FFT bands to 64 raw targets
    const unsmoothed = new Float32Array(barCount);
    for (let i = 0; i < barCount; i++) {
      if (!isPlaying || !rawBands) {
        unsmoothed[i] = 0.03;
        continue;
      }
      const pos = (i / (barCount - 1)) * 31;
      const idx0 = Math.floor(pos);
      const idx1 = Math.min(31, idx0 + 1);
      const frac = pos - idx0;
      // Smoothstep interpolation between bins
      const t = frac * frac * (3 - 2 * frac);
      const v0 = Number.isFinite(Number(rawBands[idx0])) ? Number(rawBands[idx0]) : 0.03;
      const v1 = Number.isFinite(Number(rawBands[idx1])) ? Number(rawBands[idx1]) : 0.03;
      unsmoothed[i] = v0 * (1 - t) + v1 * t;
    }

    // 2. Apply 5-tap Gaussian spatial smoothing across neighboring bars for a liquid wave curve
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
      const val = m2 * 0.08 + m1 * 0.22 + c0 * 0.40 + p1 * 0.22 + p2 * 0.08;

      standbyRtaTarget[i] = Math.max(0.03, Math.min(0.95, val * 0.92));

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

    const isModalOpen = Boolean(dom.qualityModal && !dom.qualityModal.classList.contains('hidden'));
    if (!isModalOpen) return;

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
      badgeEl.textContent = badgeMap[verdict] || 'TRUE LOSSLESS';
    }

    const titleEl = document.getElementById('spectral-verdict-title');
    if (titleEl) {
      titleEl.textContent = sa.verdict_title || sa.verdictTitle || (isLossy ? 'Сжатый поток AAC 256 kbps' : 'Verified True Lossless');
    }

    const descEl = document.getElementById('spectral-verdict-desc');
    if (descEl) {
      descEl.textContent = sa.verdict_description || sa.verdictDescription || 'Спектральный анализ потока CoreAudio Process Tap через Accelerate vDSP FFT.';
    }

    const cutoffEl = document.getElementById('spectral-metric-cutoff');
    if (cutoffEl) {
      cutoffEl.textContent = `до ${(cutoffHz / 1000).toFixed(1)} кГц`;
    }

    const ultraEl = document.getElementById('spectral-metric-ultra');
    if (ultraEl) {
      if (sRate >= 88200) {
        ultraEl.textContent = ultraDb > -80 ? `${Math.round(ultraDb)} dBFS` : 'Нет (<-82 dB)';
      } else {
        ultraEl.textContent = 'Н/Д (≤ 48 кГц)';
      }
    }

    const bitsEl = document.getElementById('spectral-metric-bits');
    if (bitsEl) {
      if (isZeroPadded) {
        bitsEl.textContent = `16-бит (в ${claimedBits}-бит)`;
      } else {
        bitsEl.textContent = `${effBits}-бит (${effBits >= 24 ? 'Честный LSB' : 'PCM'})`;
      }
    }

    const markerEl = document.getElementById('spectral-cutoff-marker');
    const markerLabelEl = document.getElementById('spectral-cutoff-marker-label');
    const axisRefEl = document.getElementById('spectral-axis-ref');
    const axisNyqEl = document.getElementById('spectral-axis-nyquist');
    const isHiResRate = sRate >= 88200;

    if (markerEl && markerLabelEl) {
      markerEl.style.left = isHiResRate ? '62.5%' : '75%';
      markerLabelEl.textContent = isHiResRate ? '22.05 кГц CD' : '18.0 кГц AAC';
    }
    if (axisRefEl) {
      axisRefEl.textContent = isHiResRate ? '22.05 кГц' : '18.0 кГц';
    }
    if (axisNyqEl) {
      axisNyqEl.textContent = `${(nyquistHz / 1000).toFixed(1).replace(/\.0$/, '')} кГц`;
    }

    const barsContainer = document.getElementById('spectral-rta-bars');
    if (barsContainer) {
      if (barsContainer.children.length !== 32) {
        barsContainer.innerHTML = '';
        for (let i = 0; i < 32; i++) {
          const b = document.createElement('div');
          b.className = 'spectral-rta-bar';
          barsContainer.appendChild(b);
        }
      }
      const rawBands = Array.isArray(sa.rta_bands || sa.rtaBands) && (sa.rta_bands || sa.rtaBands).length === 32
        ? (sa.rta_bands || sa.rtaBands)
        : null;

      const splitIdx = isHiResRate ? 20 : 24;
      for (let i = 0; i < 32; i++) {
        const bar = barsContainer.children[i];
        let val = rawBands ? Number(rawBands[i]) : 0.08;
        if (!Number.isFinite(val)) val = 0.05;
        const pct = Math.max(6, Math.min(100, Math.round(val * 100)));
        bar.style.height = `${pct}%`;

        const isAboveBoundary = i >= splitIdx;
        const isDepleted = isAboveBoundary && (isWarning || isLossy || val < 0.06);
        bar.classList.toggle('ultrasonic', isAboveBoundary && !isDepleted && !isWarning);
        bar.classList.toggle('warning-bar', isWarning && !isDepleted);
        bar.classList.toggle('depleted', isDepleted);
      }
    }
  }

  function stopSpectralPolling() {
    if (spectralPollTimer) {
      clearInterval(spectralPollTimer);
      spectralPollTimer = null;
    }
  }

  function isStandbyOrLandscapeVisible() {
    const overlay = document.getElementById('standby-tv-overlay');
    const isExplicitOpen = Boolean(overlay && !overlay.classList.contains('hidden'));
    const isTouchPhone = Boolean(window.matchMedia && window.matchMedia('(hover: none) and (pointer: coarse)').matches);
    const isMobileLandscape = isTouchPhone && window.innerHeight <= 540 && window.innerWidth >= 568 && window.innerWidth > window.innerHeight && !document.body.classList.contains('keyboard-open');
    return isExplicitOpen || isMobileLandscape;
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
    const stillAnalyzing = !isCachedPass && (!sa.verdict || sa.verdict === 'analyzing');
    const needsSoundCheck = Boolean(state.ampSoundCheckEnabled && (state.ampSoundCheckGainDb === null || state.ampSoundCheckGainDb === undefined));
    const isPlayingAndNeeded = state.playerState === 'playing' && saEnabled && (isTvActive || stillAnalyzing || needsSoundCheck);

    if (isModalOpen || isPlayingAndNeeded) {
      if (!spectralPollTimer) {
        spectralPollTickCount = 0;
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
          const curStillAnalyzing = state.playerState === 'playing' && curEnabled && !curCachedPass && (!curSa.verdict || curSa.verdict === 'analyzing');
          const curNeedsSoundCheck = state.playerState === 'playing' && Boolean(state.ampSoundCheckEnabled && (state.ampSoundCheckGainDb === null || state.ampSoundCheckGainDb === undefined));
          if (!modalStillOpen && !tvStillActive && !curStillAnalyzing && !curNeedsSoundCheck) {
            stopSpectralPolling();
            return;
          }
          if (modalStillOpen || tvStillActive || curStillAnalyzing || curNeedsSoundCheck) {
            send({ action: 'get_spectral_analysis' });
          }
        }, 210);
      }
      ensureStandbyRtaAnimLoop();
    } else {
      stopSpectralPolling();
      ensureStandbyRtaAnimLoop();
    }
  }

  const openQualityModal = () => {
    triggerHaptic('light');
    updateSignalPathDetails();
    if (dom.qualityModal) {
      dom.qualityModal.classList.remove('hidden');
      dom.qualityModal.setAttribute('aria-hidden', 'false');
    }
    send({ action: 'get_spectral_analysis' });
    syncSpectralPolling();
  };

  if (dom.audioQualityBadge) dom.audioQualityBadge.addEventListener('click', openQualityModal);
  if (dom.desktopDacBadge) dom.desktopDacBadge.addEventListener('click', openQualityModal);
  if (dom.mobileDacBadge) dom.mobileDacBadge.addEventListener('click', openQualityModal);
  const standbyDacBadgeEl = document.getElementById('standby-dac-badge');
  const standbySpectralBadgeEl = document.getElementById('standby-spectral-badge');
  if (standbyDacBadgeEl) standbyDacBadgeEl.addEventListener('click', openQualityModal);
  if (standbySpectralBadgeEl) standbySpectralBadgeEl.addEventListener('click', openQualityModal);

  if (dom.btnCloseModal) {
    dom.btnCloseModal.addEventListener('click', () => {
      if (dom.qualityModal) {
        blurFocusedInContainer(dom.qualityModal);
        dom.qualityModal.classList.add('hidden');
        dom.qualityModal.setAttribute('aria-hidden', 'true');
      }
      syncSpectralPolling();
    });
  }

  // --- Audio Output Devices Modal (DAC Selector) ---
  const openDevicesModal = () => {
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

    const defaultDev = list.find(d => d.isDefault);
    if (defaultDev) {
      state.audioDeviceName = defaultDev.name || state.audioDeviceName;
      if (defaultDev.currentSampleRate) {
        state.audioDeviceSampleRate = defaultDev.currentSampleRate;
      }
    }
    renderAudioDevicesList();
    updateSignalPathDetails();
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

  function setupMusicKitFromState() {
    const devToken = state.developerToken;
    if (!devToken || !window.MusicKit) return;
    try {
      if (!musicKitInstance) {
        window.MusicKit.configure({
          developerToken: devToken,
          app: {
            name: 'Apple Music Remote',
            build: '2.5.0'
          }
        });
        musicKitInstance = window.MusicKit.getInstance();
        if (musicKitInstance && musicKitInstance.isAuthorized) {
          const uToken = musicKitInstance.musicUserToken;
          if (uToken && !state.hasUserToken) {
            send({ action: 'set_user_token', params: { user_token: uToken } });
          }
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
      setupMusicKitFromState();
    } else if (!musicKitLoadedListenerBound) {
      musicKitLoadedListenerBound = true;
      document.addEventListener('musickitloaded', setupMusicKitFromState, { once: true });
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
    const hasToken = Boolean(data && (data.has_user_token !== undefined ? data.has_user_token : data.hasUserToken));
    state.hasUserToken = hasToken;
    if (data && data.storefront) {
      state.userStorefront = data.storefront;
    }

    if (hasToken || state.isAccountSynced) {
      if (dom.modalAppleAuth) {
        dom.modalAppleAuth.classList.add('hidden');
        dom.modalAppleAuth.setAttribute('aria-hidden', 'true');
      }

      const activeCountry = state.userStorefront || state.trends.country || 'us';
      if (state.trends.country !== activeCountry) {
        state.trends.country = activeCountry;
        loadTrends(activeCountry);
      }
    } else {
      if (dom.modalAppleAuth && !state.isAccountSynced) {
        dom.modalAppleAuth.classList.remove('hidden');
        dom.modalAppleAuth.setAttribute('aria-hidden', 'false');
      }
    }
  }

  function updateAccountHealth(data) {
    if (!data) return;
    state.accountHealth = data;
    const isSynced = data.status === 'synchronized' || data.is_accounts_matched === true;
    state.isAccountSynced = isSynced;
    const email = data.account_email || data.mac_apple_id || data.macos_account || 'Apple Music';
    const storefront = (data.mac_country_code || data.storefront || data.web_storefront || state.userStorefront || 'us').toUpperCase();
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
      initMusicKit(state.developerToken);
    }

    if (!musicKitInstance) {
      send({ action: 'get_developer_token' });
      if (dom.authModalStatus) dom.authModalStatus.innerHTML = '<div class="spinner-sm"></div><span>Получение ключа разработчика...</span>';
      setTimeout(() => {
        if (dom.btnAuthModalLogin) dom.btnAuthModalLogin.disabled = false;
        if (state.developerToken && !musicKitInstance) {
          initMusicKit(state.developerToken);
        }
      }, 1500);
      return;
    }

    try {
      if (dom.authModalStatus) dom.authModalStatus.innerHTML = '<div class="spinner-sm"></div><span>Ожидание авторизации Apple ID...</span>';
      const uToken = await musicKitInstance.authorize();
      if (uToken) {
        send({ action: 'set_user_token', params: { user_token: uToken } });
        updateUserTokenStatus({ has_user_token: true });
      }
    } catch (err) {
      console.error('Apple Music authorization error:', err);
    } finally {
      if (dom.btnAuthModalLogin) dom.btnAuthModalLogin.disabled = false;
      if (dom.authModalStatus) dom.authModalStatus.classList.add('hidden');
    }
  }

  async function handleAppleIdLogout() {
    triggerHaptic('medium');
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

  // --- Go to Album Action & Station Creation Modal Listeners ---
  function openCurrentTrackAlbum() {
    const t = state.track;
    const albumName = t && t.album ? t.album.trim() : '';
    if (!albumName) return;
    triggerHaptic('light');
    if (typeof bookletState !== 'undefined' && bookletState.isOpen) {
      closeBookletViewer();
    }
    const art = getArtworkSrc(t);
    const origin = isDesktopLayout() ? 'library' : 'player';
    openAlbumDetail({
      id: '',
      name: albumName,
      artist: (t && t.artist) ? t.artist : '',
      artwork: art,
      url: ''
    }, origin);
  }

  if (dom.btnGoToAlbum) {
    dom.btnGoToAlbum.addEventListener('click', () => {
      if (dom.stationPickerModal) {
        blurFocusedInContainer(dom.stationPickerModal);
        dom.stationPickerModal.classList.add('hidden');
        dom.stationPickerModal.setAttribute('aria-hidden', 'true');
      }
      openCurrentTrackAlbum();
    });
  }

  if (dom.playerAlbum) {
    dom.playerAlbum.addEventListener('click', openCurrentTrackAlbum);
  }

  function triggerAiMixFromCurrentTrack() {
    triggerHaptic('medium');
    if (dom.stationPickerModal) {
      blurFocusedInContainer(dom.stationPickerModal);
      dom.stationPickerModal.classList.add('hidden');
      dom.stationPickerModal.setAttribute('aria-hidden', 'true');
    }
    const trackName = (state.track && state.track.name) ? state.track.name.trim() : '';
    const artistName = (state.track && state.track.artist) ? state.track.artist.trim() : '';
    const albumName = (state.track && state.track.album) ? state.track.album.trim() : '';
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
        country: state.userStorefront || state.trends.country || 'ru',
        auto_play: true,
        request_id: reqId
      }
    });
  }

  if (dom.btnAiTrackVibe) {
    dom.btnAiTrackVibe.addEventListener('click', triggerAiMixFromCurrentTrack);
  }

  if (dom.btnAiMixByTrack) {
    dom.btnAiMixByTrack.addEventListener('click', triggerAiMixFromCurrentTrack);
  }

  if (dom.btnCreateStation) {
    dom.btnCreateStation.addEventListener('click', () => {
      triggerHaptic('light');
      const albumText = (state.track && state.track.album) ? state.track.album.trim() : '';
      const trackText = (state.track && state.track.name) ? state.track.name.trim() : '';
      const artistText = (state.track && state.track.artist) ? state.track.artist.trim() : '';
      if (dom.stationOptAlbumName) {
        dom.stationOptAlbumName.textContent = albumText || 'Не указан';
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
      if (dom.stationOptTrackName) {
        dom.stationOptTrackName.textContent = trackText || 'Не играет';
      }
      if (dom.stationOptArtistName) {
        dom.stationOptArtistName.textContent = artistText || 'Apple Music';
      }
      if (dom.stationPickerModal) {
        dom.stationPickerModal.classList.remove('hidden');
        dom.stationPickerModal.setAttribute('aria-hidden', 'false');
      }
    });
  }

  if (dom.btnCloseStationModal) {
    dom.btnCloseStationModal.addEventListener('click', () => {
      if (dom.stationPickerModal) {
        blurFocusedInContainer(dom.stationPickerModal);
        dom.stationPickerModal.classList.add('hidden');
        dom.stationPickerModal.setAttribute('aria-hidden', 'true');
      }
    });
  }

  if (dom.stationPickerModal) {
    dom.stationPickerModal.addEventListener('click', (e) => {
      if (e.target === dom.stationPickerModal) {
        blurFocusedInContainer(dom.stationPickerModal);
        dom.stationPickerModal.classList.add('hidden');
        dom.stationPickerModal.setAttribute('aria-hidden', 'true');
      }
    });
  }

  if (dom.btnStationByTrack) {
    dom.btnStationByTrack.addEventListener('click', () => {
      triggerHaptic('medium');
      if (dom.stationPickerModal) {
        blurFocusedInContainer(dom.stationPickerModal);
        dom.stationPickerModal.classList.add('hidden');
        dom.stationPickerModal.setAttribute('aria-hidden', 'true');
      }
      const trackName = state.track ? state.track.name : '';
      const artistName = state.track ? state.track.artist : '';
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
      if (dom.stationPickerModal) {
        blurFocusedInContainer(dom.stationPickerModal);
        dom.stationPickerModal.classList.add('hidden');
        dom.stationPickerModal.setAttribute('aria-hidden', 'true');
      }
      const artistName = state.track ? state.track.artist : '';
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
      blurFocusedInContainer(dom.qualityModal);
      dom.qualityModal.classList.add('hidden');
      dom.qualityModal.setAttribute('aria-hidden', 'true');
      syncSpectralPolling();
    }
  });

  // --- Volume Control & Settings Listeners ---
  let lastVolumeSendTime = 0;
  let volumeSendTimeout = null;

  function sendThrottledVolume(val) {
    const isExtAmpMode = Boolean(state.lockVolume100 && state.ampVolumeControlEnabled);
    const maxVol = isExtAmpMode ? Math.max(1, Math.min(100, Number(state.ampMaxVolume) || 80)) : 100;
    const vol = Math.max(0, Math.min(maxVol, Math.round(Number(val) || 0)));
    state.volume = vol;
    if (vol >= 5) {
      state.previousVolume = vol;
    }
    if (vol > 0 && isExtAmpMode) {
      state.ampMuted = false;
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
    if (now - lastVolumeSendTime >= 75) {
      lastVolumeSendTime = now;
      send({ action: 'set_volume', params: { volume: vol } });
    } else {
      if (volumeSendTimeout) clearTimeout(volumeSendTimeout);
      volumeSendTimeout = setTimeout(() => {
        lastVolumeSendTime = Date.now();
        send({ action: 'set_volume', params: { volume: vol } });
      }, 75);
    }
  }

  function handleMuteToggleClick() {
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

  // --- Queue View Handling ---
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

    const isAMR = playlistName === 'Очередь AMR' || Boolean(state.isRadio);
    if (isAMR) {
      const displayCount = total > 0 ? total : (upcoming.length + (state.track && state.track.name ? 1 : 0));
      dom.queueSubtitle.textContent = `Очередь AMR · ${displayCount} трек${displayCount === 1 ? '' : (displayCount >= 2 && displayCount <= 4 ? 'а' : 'ов')}`;
    } else {
      dom.queueSubtitle.textContent = `${upcoming.length} треков в очереди`;
    }

    renderCurrentQueueTrack(dom.queueCurrentTrack);
    renderQueueList(dom.queueUpcomingList, upcoming, 'upcoming');
  }

  let lastCurrentQueueTrackKey = '';
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
        <img class="track-thumb" src="${escapeHtml(artSrc)}" alt="" loading="lazy" onerror="this.onerror=null;this.src='apple-touch-icon.svg';">
        <div class="track-details">
          <span class="track-row-title">${escapeHtml(cur.name || 'Без названия')}</span>
          <span class="track-row-artist">${escapeHtml(cur.artist || 'Неизвестный исполнитель')}</span>
        </div>
        <span class="track-row-dur">${dur}</span>
      </div>
    `;
  }

  const lastQueueListKey = { upcoming: '', history: '' };
  function renderQueueList(container, tracks, type) {
    if (!container) return;
    if (!tracks || tracks.length === 0) {
      container.innerHTML = `<div class="empty-state">${type === 'upcoming' ? 'Нет предстоящих треков' : 'История пуста'}</div>`;
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
        <img class="track-thumb" src="${escapeHtml(artSrc)}" alt="" loading="lazy" onerror="this.onerror=null;this.src='apple-touch-icon.svg';">
        <div class="track-details">
          <span class="track-row-title">${escapeHtml(t.name || 'Без названия')}</span>
          <span class="track-row-artist">${escapeHtml(t.artist || 'Неизвестный исполнитель')}</span>
        </div>
        <span class="track-row-dur">${dur}</span>
      `;

      row.addEventListener('click', () => {
        optimisticPlay();
        markWaitingForPlayback({ targetName: t.name || '', expectedTrackName: t.name || '' });
        setUIBusy(true, 'Переход к треку...');
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
      const cur = (state.track && state.track.name) ? [state.track] : [];
      const upcoming = Array.isArray(state.queue.upcoming) ? state.queue.upcoming : [];
      const allQueueTracks = [...cur, ...upcoming];
      if (allQueueTracks.length === 0) {
        showToast(IS_EN ? 'Queue is empty' : 'Очередь пуста');
        return;
      }
      triggerHaptic('medium');
      let plName = '';
      if (state.activeAiCuratedTitle && (!state.queue.playlist || state.queue.playlist === 'Очередь AMR')) {
        plName = state.activeAiCuratedTitle;
      } else if (state.queue.playlist && state.queue.playlist !== 'Очередь AMR') {
        plName = state.queue.playlist;
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

  // --- Library / Playlists Handling ---
  function updatePlaylists(data) {
    const list = data.playlists || (Array.isArray(data) ? data : []);
    state.playlists = list;
    if (typeof renderStandbyQuickTiles === 'function') {
      renderStandbyQuickTiles();
    }

    if (list.length === 0) {
      dom.playlistsGrid.innerHTML = '<div class="empty-state">Плейлисты не найдены</div>';
      return;
    }

    dom.playlistsGrid.innerHTML = '';
    list.forEach(pl => {
      const card = document.createElement('div');
      card.className = 'playlist-card';
      const art = pl.artwork_url || pl.artworkUrl || 'apple-touch-icon.svg';
      const count = pl.track_count || pl.trackCount || 0;

      card.innerHTML = `
        <div class="playlist-card-art-wrap">
          <img class="playlist-card-art" src="${escapeHtml(art)}" alt="" loading="lazy" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
          <div class="playlist-card-art-fallback" style="display:none;">
            <svg viewBox="0 0 24 24" width="36" height="36" fill="none" stroke="#6e6e73" stroke-width="1.8">
              <path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>
            </svg>
          </div>
        </div>
        <span class="playlist-card-title">${escapeHtml(pl.name)}</span>
        <span class="playlist-card-count">${count} треков</span>
      `;

      card.addEventListener('click', () => {
        openPlaylistDetail(pl);
      });

      dom.playlistsGrid.appendChild(card);
    });
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

  function findMatchingLocalPlaylist(plName, plId = '') {
    if (!plName && !plId) return null;
    const lower = (plName || '').trim().toLowerCase();
    const isEssentials = lower === 'your essentials' || lower === 'мои любимые треки';
    const isChillMix = lower === 'chill mix' || lower === 'чилл-микс';
    const isNewMusicMix = lower === 'new music mix' || lower === 'микс новинок';
    const isFavoritesMix = lower === 'favorites mix' || lower === 'в моём вкусе: микс' || lower === 'в моем вкусе: микс';
    const isGetUpMix = lower === 'get up! mix' || lower === 'энергетический микс';

    return (state.playlists || []).find(p => {
      const pn = (p.name || '').trim().toLowerCase();
      if (pn === lower) return true;
      if (isEssentials && (pn === 'мои любимые треки' || pn === 'your essentials')) return true;
      if (isChillMix && (pn === 'chill mix' || pn === 'чилл-микс')) return true;
      if (isNewMusicMix && (pn === 'new music mix' || pn === 'микс новинок')) return true;
      if (isFavoritesMix && (pn === 'favorites mix' || pn === 'в моём вкусе: микс' || pn === 'в моем вкусе: микс')) return true;
      if (isGetUpMix && (pn === 'get up! mix' || pn === 'энергетический микс')) return true;
      return false;
    }) || null;
  }

  function resolveDetailOrigin(originParam) {
    if (typeof originParam === 'string' && originParam) return originParam;
    if (originParam === true) {
      if (dom.sectionGridView && dom.sectionGridView.classList.contains('active')) {
        return 'home-grid';
      }
      return 'home';
    }
    return 'library';
  }

  function openPlaylistDetail(pl, fromOrigin = false) {
    const origin = resolveDetailOrigin(fromOrigin);
    state.detailReturnOrigin = origin;
    state.albumOpenedFromHome = (origin === 'home' || origin === 'home-grid');
    state.detailOpenedFromHome = (origin === 'home' || origin === 'home-grid');
    state.currentPlaylistDetail = pl;
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
    if (dom.detailBadge) dom.detailBadge.textContent = 'ПЛЕЙЛИСТ';
    dom.detailTitle.textContent = plName;
    const count = pl.track_count || pl.trackCount || 0;
    dom.detailMeta.textContent = count > 0 ? `${count} треков` : (pl.curator_name || pl.curatorName || 'Apple Music');
    dom.detailArtwork.src = pl.artwork_url || pl.artworkUrl || pl.artwork || 'apple-touch-icon.svg';
    dom.playlistTracksList.innerHTML = '<div class="loading-state">Загрузка треков...</div>';

    const matchedLocal = findMatchingLocalPlaylist(plName, pl.id);
    const isAlreadyInLib = Boolean(pl.is_local) || Boolean(matchedLocal);

    if (dom.btnAddPlaylistLibrary) {
      dom.btnAddPlaylistLibrary.style.display = '';
      if (isAlreadyInLib) {
        dom.btnAddPlaylistLibrary.disabled = true;
        if (dom.btnAddPlaylistLibraryText) dom.btnAddPlaylistLibraryText.textContent = 'В медиатеке ✓';
        dom.btnAddPlaylistLibrary.classList.add('added');
      } else {
        dom.btnAddPlaylistLibrary.disabled = false;
        if (dom.btnAddPlaylistLibraryText) dom.btnAddPlaylistLibraryText.textContent = 'В медиатеку';
        dom.btnAddPlaylistLibrary.classList.remove('added');
      }
    }
    const btnDetailBookletPl = document.getElementById('btn-detail-booklet');
    if (btnDetailBookletPl) btnDetailBookletPl.classList.add('hidden');

    navigateToView('view-library', 'library', true);
    if (dom.playlistsBrowsePane) dom.playlistsBrowsePane.classList.add('hidden');
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

  function openAlbumDetail(alb, fromOrigin = true) {
    const origin = resolveDetailOrigin(fromOrigin);
    state.detailReturnOrigin = origin;
    state.albumOpenedFromHome = (origin === 'home' || origin === 'home-grid');
    state.detailOpenedFromHome = (origin === 'home' || origin === 'home-grid');
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
    state.currentDetailAlbumId = String(alb.id || '');
    state.currentDetailTitle = String(alb.name || alb.title || '');
    if (dom.detailTitle) dom.detailTitle.textContent = alb.name || alb.title || 'Альбом';
    if (dom.detailMeta) dom.detailMeta.textContent = alb.artist || alb.sub || alb.subtitle || '';
    if (dom.detailArtwork) dom.detailArtwork.src = alb.artwork || alb.artwork_url || 'apple-touch-icon.svg';
    if (dom.detailBadge) dom.detailBadge.textContent = 'АЛЬБОМ';
    if (dom.playlistTracksList) dom.playlistTracksList.innerHTML = '<div class="loading-state">Загрузка треков альбома...</div>';

    if (dom.btnAddPlaylistLibrary) {
      dom.btnAddPlaylistLibrary.style.display = '';
      if (alb.is_local || alb.in_library) {
        dom.btnAddPlaylistLibrary.disabled = true;
        if (dom.btnAddPlaylistLibraryText) dom.btnAddPlaylistLibraryText.textContent = 'В медиатеке ✓';
        dom.btnAddPlaylistLibrary.classList.add('added');
      } else {
        dom.btnAddPlaylistLibrary.disabled = false;
        if (dom.btnAddPlaylistLibraryText) dom.btnAddPlaylistLibraryText.textContent = 'В медиатеку';
        dom.btnAddPlaylistLibrary.classList.remove('added');
      }
    }
    const btnDetailBookletAlb = document.getElementById('btn-detail-booklet');
    if (btnDetailBookletAlb) btnDetailBookletAlb.classList.add('hidden');
    syncDetailAlbumBookletAvailability(alb);

    navigateToView('view-library', 'library', true);
    if (dom.playlistsBrowsePane) dom.playlistsBrowsePane.classList.add('hidden');
    if (dom.playlistDetailPane) dom.playlistDetailPane.classList.remove('hidden');

    send({
      action: 'get_album',
      params: {
        id: alb.id || '',
        name: alb.name || alb.title || '',
        artist: alb.artist || alb.sub || alb.subtitle || '',
        country: state.userStorefront || state.trends.country || 'us'
      }
    });
  }

  dom.btnBackToPlaylists.addEventListener('click', () => {
    dom.playlistDetailPane.classList.add('hidden');
    const origin = state.detailReturnOrigin || (state.albumOpenedFromHome || state.detailOpenedFromHome ? 'home' : 'library');
    state.detailReturnOrigin = null;
    state.albumOpenedFromHome = false;
    state.detailOpenedFromHome = false;

    if (origin === 'search') {
      navigateToView('view-search', 'search');
    } else if (origin === 'player') {
      if (!isDesktopLayout()) {
        switchMobileView('view-now-playing', true);
      } else {
        dom.playlistsBrowsePane.classList.remove('hidden');
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
    } else {
      dom.playlistsBrowsePane.classList.remove('hidden');
    }
  });

  dom.btnRefreshLibrary.addEventListener('click', () => {
    dom.playlistsGrid.innerHTML = '<div class="loading-state">Загрузка плейлистов...</div>';
    send({ action: 'get_playlists' });
  });

  dom.btnPlayPlaylist.addEventListener('click', () => {
    if (!state.currentPlaylistDetail) return;
    const isAlbum = Boolean(state.currentPlaylistDetail.isAlbum);
    const plName = state.currentPlaylistDetail.name || state.currentPlaylistDetail.title || '';
    const matchedLocal = findMatchingLocalPlaylist(plName, state.currentPlaylistDetail.id);
    const isLocalPlaylist = !isAlbum && (Boolean(state.currentPlaylistDetail.is_local) || Boolean(matchedLocal));

    optimisticPlay();
    markWaitingForPlayback({ targetName: plName });
    if (isAlbum) {
      setUIBusy(true, 'Запуск альбома...', dom.btnPlayPlaylist);
    } else if (isLocalPlaylist) {
      setUIBusy(true, 'Запуск плейлиста...', dom.btnPlayPlaylist);
    } else {
      setUIBusy(true, 'Синхронизация очереди в Apple Music (~10 сек)...', dom.btnPlayPlaylist);
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
    } else if (isLocalPlaylist) {
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
          tracks: state.currentPlaylistTracks || [],
          shuffle: false
        }
      });
    }
  });

  dom.btnShufflePlaylist.addEventListener('click', () => {
    if (!state.currentPlaylistDetail) return;
    const isAlbum = Boolean(state.currentPlaylistDetail.isAlbum);
    const plName = state.currentPlaylistDetail.name || state.currentPlaylistDetail.title || '';
    const matchedLocal = findMatchingLocalPlaylist(plName, state.currentPlaylistDetail.id);
    const isLocalPlaylist = !isAlbum && (Boolean(state.currentPlaylistDetail.is_local) || Boolean(matchedLocal));

    optimisticPlay();
    markWaitingForPlayback({ targetName: plName });
    if (isAlbum) {
      setUIBusy(true, 'Перемешивание альбома...', dom.btnShufflePlaylist);
    } else if (isLocalPlaylist) {
      setUIBusy(true, 'Перемешивание...', dom.btnShufflePlaylist);
    } else {
      setUIBusy(true, 'Синхронизация очереди в Apple Music (~10 сек)...', dom.btnShufflePlaylist);
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
    } else if (isLocalPlaylist) {
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
          tracks: state.currentPlaylistTracks || [],
          shuffle: true
        }
      });
    }
  });

  if (dom.btnAddPlaylistLibrary) {
    dom.btnAddPlaylistLibrary.addEventListener('click', () => {
      if (!state.currentPlaylistDetail) return;
      const isAlbum = Boolean(state.currentPlaylistDetail.isAlbum);
      const itemId = state.currentPlaylistDetail.id || (state.currentAlbumDetail && state.currentAlbumDetail.id) || '';
      const itemName = state.currentPlaylistDetail.name || state.currentPlaylistDetail.title || '';
      const itemArtist = state.currentPlaylistDetail.artist || state.currentPlaylistDetail.sub || state.currentPlaylistDetail.subtitle || (state.currentAlbumDetail && state.currentAlbumDetail.artist) || '';
      const tracks = isAlbum
        ? ((state.currentAlbumDetail && state.currentAlbumDetail.tracks) || [])
        : (state.currentPlaylistTracks || []);

      state.lastLibraryAddTarget = 'detail';
      state.isAddingDetailToLibrary = true;
      state.lastDetailLibraryAddKey = String(state.currentDetailPlaylistId || state.currentDetailAlbumId || state.currentDetailTitle || itemId || itemName || '');
      state.lastDetailLibraryAddId = String(itemId || '').trim().toLowerCase();
      state.lastDetailLibraryAddName = String(itemName || '').trim().toLowerCase();
      dom.btnAddPlaylistLibrary.disabled = true;
      if (dom.btnAddPlaylistLibraryText) dom.btnAddPlaylistLibraryText.textContent = 'Добавление...';
      send({
        action: 'add_playlist_to_library',
        params: {
          id: itemId,
          name: itemName,
          artist: itemArtist,
          is_album: isAlbum,
          tracks: tracks
        }
      });
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
    if (dom.btnAddPlaylistLibrary) {
      dom.btnAddPlaylistLibrary.style.display = '';
      const tracksArr = alb.tracks || [];
      const allLocal = tracksArr.length > 0 && tracksArr.every(t => Boolean(t.is_local || t.isLocal));
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
      if (alb.is_local || alb.in_library || allLocal) {
        state.isAddingDetailToLibrary = false;
        dom.btnAddPlaylistLibrary.disabled = true;
        if (dom.btnAddPlaylistLibraryText) dom.btnAddPlaylistLibraryText.textContent = 'В медиатеке ✓';
        dom.btnAddPlaylistLibrary.classList.add('added');
      } else if (!dom.btnAddPlaylistLibrary.classList.contains('added') && !isSamePendingDetail) {
        dom.btnAddPlaylistLibrary.disabled = false;
        if (dom.btnAddPlaylistLibraryText) dom.btnAddPlaylistLibraryText.textContent = 'В медиатеку';
      }
    }
    if (dom.detailTitle) dom.detailTitle.textContent = alb.name || 'Альбом';
    if (dom.detailMeta) {
      const parts = [];
      if (alb.artist) parts.push(alb.artist);
      if (alb.release_date) parts.push(alb.release_date.slice(0, 4));
      if (alb.track_count) parts.push(`${alb.track_count} треков`);
      dom.detailMeta.textContent = parts.join(' • ');
    }
    if (dom.detailArtwork && (alb.artwork || alb.artwork_url)) {
      dom.detailArtwork.src = alb.artwork || alb.artwork_url;
    }
    if (dom.detailBadge) dom.detailBadge.textContent = 'АЛЬБОМ';

    const tracks = alb.tracks || [];
    if (tracks.length === 0) {
      dom.playlistTracksList.innerHTML = '<div class="empty-state">Нет треков</div>';
      return;
    }

    dom.playlistTracksList.innerHTML = '';
    tracks.forEach((t, idx) => {
      const row = document.createElement('div');
      row.className = 'track-row';
      const dur = formatTime(t.duration || 0);

      row.innerHTML = `
        <span class="track-index-num">${idx + 1}</span>
        <div class="track-details">
          <span class="track-row-title">${escapeHtml(t.name || 'Без названия')}</span>
          <span class="track-row-artist">${escapeHtml(t.artist || alb.artist || '')}</span>
        </div>
        <span class="track-row-dur">${dur}</span>
      `;

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
    if (!tracks || tracks.length === 0) {
      dom.playlistTracksList.innerHTML = '<div class="empty-state">Плейлист пуст</div>';
      return;
    }

    dom.playlistTracksList.innerHTML = '';
    tracks.forEach((t, idx) => {
      const row = document.createElement('div');
      row.className = 'track-row';
      const dur = formatTime(t.duration || 0);

      row.innerHTML = `
        <span class="track-index-num">${idx + 1}</span>
        <div class="track-details">
          <span class="track-row-title">${escapeHtml(t.name || 'Без названия')}</span>
          <span class="track-row-artist">${escapeHtml(t.artist || '')} &bull; ${escapeHtml(t.album || '')}</span>
        </div>
        <span class="track-row-dur">${dur}</span>
      `;

      row.addEventListener('click', () => {
        if (!state.currentPlaylistDetail) return;
        const plName = state.currentPlaylistDetail.name || state.currentPlaylistDetail.title || '';
        const matchedLocal = findMatchingLocalPlaylist(plName, state.currentPlaylistDetail.id);
        const isLocalPlaylist = !state.currentPlaylistDetail.isAlbum && (Boolean(state.currentPlaylistDetail.is_local) || Boolean(matchedLocal));
        optimisticPlay();
        markWaitingForPlayback({ targetName: t.name || '', expectedTrackName: t.name || '' });
        if (isLocalPlaylist) {
          setUIBusy(true, 'Запуск трека...');
        } else {
          setUIBusy(true, 'Синхронизация очереди в Apple Music (~10 сек)...');
        }
        if (isLocalPlaylist) {
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
              tracks: state.currentPlaylistTracks || []
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
      executeSearch(q, state.searchScope);
    }
  });

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
    if (!state.aiCuratorEnabled) {
      const standbyAiModal = document.getElementById('standby-ai-modal');
      if (standbyAiModal && !standbyAiModal.classList.contains('hidden')) {
        standbyAiModal.classList.add('hidden');
        standbyAiModal.setAttribute('aria-hidden', 'true');
      }
    }
    if (!state.aiCuratorEnabled && state.searchScope === 'ai') {
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

  function renderSearchPlaceholder() {
    if (!dom.searchResults) return;
    if (!state.aiCuratorEnabled) {
      dom.searchResults.innerHTML = `
        <div class="search-placeholder">
          <div class="search-placeholder-minimal">${translateTextToEn('Введите название песни, альбома, плейлиста или артиста')}</div>
        </div>`;
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
        </div>
      </div>`;
    bindAiPromptChips();
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
        dom.searchInput.placeholder = translateTextToEn(
          state.searchScope === 'ai'
            ? 'Опишите настроение, сцену или инструменты...'
            : 'Поиск в Apple Music...'
        );
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
    if (scope === 'ai') {
      currentSearchSongs = [];
      currentSearchOffset = 0;
      currentSearchHasMore = false;
      state.isAiCurating = true;
      state.aiCurateReqSeq = (state.aiCurateReqSeq || 0) + 1;
      state.lastAiCurateSentAt = Date.now();
      const reqId = state.aiCurateReqSeq;
      dom.searchResults.innerHTML = `<div class="loading-state">${translateTextToEn('Подбор нативным ИИ (Apple Neural Engine)...')}</div>`;
      send({
        action: 'ai_curate',
        request_id: reqId,
        params: {
          prompt: query,
          country: state.userStorefront || state.trends.country || 'ru',
          request_id: reqId
        }
      });
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
        country: state.userStorefront || state.trends.country || 'us',
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
    const artSrc = s.artwork_url || s.artwork || 'apple-touch-icon.svg';
    const isLocal = Boolean(s.is_local || s.isLocal);
    const localBadge = isLocal ? '<span class="badge-library">МЕДИАТЕКА</span>' : '';

    row.innerHTML = `
      <img class="track-thumb" src="${escapeHtml(artSrc)}" alt="" loading="lazy" onerror="this.onerror=null;this.src='apple-touch-icon.svg';">
      <div class="track-details">
        <div class="track-row-title-wrap">
          <span class="track-row-title">${escapeHtml(s.name || s.trackName || '')}</span>
          ${localBadge}
        </div>
        <span class="track-row-artist">${escapeHtml(s.artist || s.artistName || '')}</span>
      </div>
    `;

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
          <span id="btn-ai-curated-save-text">${translateTextToEn('В медиатеку')}</span>
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
        playSearchResultsList([...songs], true, 0, {
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
        const isPlayingSearch = Boolean(
          state.queue &&
          (state.queue.playlist === 'Результаты поиска' || state.queue.playlist === 'Очередь AMR')
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
        const art = pl.artwork_url || pl.artwork || 'apple-touch-icon.svg';
        const plName = pl.name || 'Плейлист';
        const plSub = pl.curator_name || pl.curator || pl.subtitle || 'Apple Music';

        card.innerHTML = `
          <div class="media-card-art-wrap">
            <img class="playlist-card-art" src="${escapeHtml(art)}" alt="" loading="lazy" onerror="this.src='apple-touch-icon.svg'">
          </div>
          <span class="playlist-card-title">${escapeHtml(plName)}</span>
          <span class="playlist-card-count">${escapeHtml(plSub)}</span>
        `;

        card.addEventListener('click', () => {
          openPlaylistDetail({
            id: pl.id || '',
            name: plName,
            url: pl.url || '',
            artwork_url: art,
            track_count: pl.track_count || 25,
            curator_name: plSub,
            is_local: Boolean(pl.is_local)
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

  function playSearchResultsList(songs, shuffle, startIndex = 0, options = {}) {
    if (!songs || songs.length === 0) return;
    const isAiCurated = Boolean(options.queueName || state.activeAiCuratedTitle);
    const resolvedQueueName = options.queueName || state.activeAiCuratedTitle || 'Результаты поиска';
    const resolvedQuery = options.query !== undefined ? options.query : (isAiCurated ? '' : (state.searchQuery || ''));
    const resolvedCuratorPrompt = options.curatorPrompt !== undefined
      ? options.curatorPrompt
      : (isAiCurated ? (state.activeAiCuratedPrompt || '') : '');
    const firstSong = songs[startIndex] || songs[0];
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
        startIndex: startIndex,
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

  function loadTrends(country, force = false) {
    if (country) {
      state.trends.country = country;
    }
    const c = state.userStorefront || state.trends.country || 'us';
    state.trends.country = c;

    const now = Date.now();
    if (!force && lastTrendsCountry === c && now - lastTrendsLoadedTime < 30000 && state.trends.stations && state.trends.stations.length > 0) {
      return;
    }
    lastTrendsLoadedTime = now;
    lastTrendsCountry = c;

    send({
      action: 'get_explore',
      params: { country: c }
    });
  }

  function updateCatalogCharts(data) {
    // Top charts removed per user request
  }

  function updateExploreFeed(data) {
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

  // Animated Plaque Generator for Personal Stations, Weekly Mixes & Radio Stations
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
      const dispTitle = lowerTitle.includes('в моем вкусе') ? 'СТАНЦИЯ ОТКРЫТИЙ' : (rawTitle.toUpperCase() || 'СТАНЦИЯ ОТКРЫТИЙ');
      return `
        <div class="animated-plaque-wrap" style="background: linear-gradient(135deg, #10042c 0%, #3a0ca3 38%, #7209b7 72%, #f72585 100%);">
          <div class="animated-plaque-orb" style="background: radial-gradient(circle, rgba(0,229,255,0.45) 0%, rgba(247,37,133,0) 70%);"></div>
          <svg class="animated-plaque-svg" viewBox="0 0 500 500">
            <defs>
              <linearGradient id="discStarG" x1="0%" y1="50%" x2="100%" y2="50%">
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
              <polygon points="250,110 268,217 375,235 268,253 250,360 232,253 125,235 232,217" fill="url(#discStarG)" />
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
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="29" font-weight="600" fill="#ffffff" text-anchor="middle">МОЯ СТАНЦИЯ</text>
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
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="28" font-weight="600" fill="#ffffff" text-anchor="middle">В МОЁМ ВКУСЕ</text>
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
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="27" font-weight="600" fill="#ffffff" text-anchor="middle">СЕЙЧАС НА ПОВТОРЕ</text>
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
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="27" font-weight="600" fill="#ffffff" text-anchor="middle">НОВИНКИ ДЛЯ ВАС</text>
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
      const titleText = lowerTitle.includes('lo-fi') ? 'CHILL & LO-FI' : 'ЧИЛЛ-МИКС';
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
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="27" font-weight="600" fill="#ffffff" text-anchor="middle">${escapeHtml(rawTitle.toUpperCase() || 'ДРАЙВ-МИКС')}</text>
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
            <text x="250" y="422" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="27" font-weight="600" fill="#ffffff" text-anchor="middle">МИКС ДЛЯ ДРУЗЕЙ</text>
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
            <text x="250" y="446" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif" font-size="11.5" font-weight="600" letter-spacing="2" fill="#e0aaff" text-anchor="middle">РАДИОСТАНЦИЯ ПО АРТИСТУ</text>
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
      const cardColor = escapeHtml(String(rawCardColor).replace(/[;"<>]/g, ''));
      const animatedPlaque = getAnimatedPlaqueHtml(c);
      const hasArt = c.artwork && c.artwork.trim().length > 0;
      const mediaHtml = animatedPlaque ? animatedPlaque : (hasArt ? `
        <img class="hero-art-img" src="${escapeHtml(c.artwork)}" alt="${escapeHtml(c.title)}" loading="eager" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
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
            track_count: c.track_count || 25
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
      const art = mix.artwork || mix.artwork_url || 'apple-touch-icon.svg';
      const curator = mix.curator_name || 'Apple Music';
      const animatedPlaque = getAnimatedPlaqueHtml({ ...mix, title: mName, subtitle: curator });
      const artContent = animatedPlaque
        ? animatedPlaque
        : `<img class="media-card-art" src="${escapeHtml(art)}" loading="lazy" alt="Cover" onerror="this.src='apple-touch-icon.svg'">`;
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
          track_count: mix.track_count || mix.trackCount || 25,
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
        const art = item.artwork || item.artwork_url || 'apple-touch-icon.svg';
        const animatedPlaque = getAnimatedPlaqueHtml({ ...item, title: iName, subtitle: iSub });
        const artContent = animatedPlaque
          ? animatedPlaque
          : `<img class="media-card-art" src="${escapeHtml(art)}" loading="lazy" alt="Cover" onerror="this.src='apple-touch-icon.svg'">`;

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
              track_count: item.track_count || 25,
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
          <img class="media-card-art" src="${escapeHtml(art)}" alt="" loading="lazy" onerror="this.style.display='none'; this.parentElement.classList.add('has-fallback');">
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
      const gradient = escapeHtml(String(rawGradient).replace(/[;"<>]/g, ''));
      const defaultIconSvg = '<svg viewBox="0 0 24 24" width="36" height="36" fill="currentColor"><circle cx="12" cy="12" r="3.2"/><path d="M12 6c-2.76 0-5 2.24-5 5 0 1.63.79 3.08 2 3.99V22l3-2 3 2v-7.01c1.21-.91 2-2.36 2-3.99 0-2.76-2.24-5-5-5z"/></svg>';
      const rawIcon = typeof st.icon === 'string' ? st.icon.trim() : '';
      const iconSvg = (rawIcon.startsWith('<svg') && !/on\w+\s*=|<script|javascript:/i.test(rawIcon)) ? rawIcon : defaultIconSvg;
      const animatedPlaque = getAnimatedPlaqueHtml({ ...st, type: 'station' });
      const hasImage = Boolean(st.artwork && st.artwork.trim().length > 0 && !st.artwork.includes('apple-touch-icon'));

      const artHtml = animatedPlaque
        ? animatedPlaque
        : (hasImage
          ? `<img class="media-card-art" src="${escapeHtml(st.artwork)}" alt="" loading="lazy" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
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
      const gradient = escapeHtml(String(rawGradient).replace(/[;"<>]/g, ''));
      const artUrl = item.artwork || item.artworkUrl || item.artwork_url || '';
      const hasImage = Boolean(artUrl && artUrl.trim().length > 0 && !artUrl.includes('apple-touch-icon'));
      const itemName = item.name || item.title || 'Apple Music';
      const itemSub = item.subtitle || item.sub || item.artist || item.curatorName || (key === 'stations' ? 'Радиостанция' : '');
      const animatedPlaque = getAnimatedPlaqueHtml({ ...item, title: itemName, subtitle: itemSub, type: key === 'stations' ? 'station' : item.type });

      const artHtml = animatedPlaque
        ? animatedPlaque
        : (hasImage
          ? `<img class="collection-tile-art" src="${escapeHtml(artUrl)}" alt="" loading="lazy" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
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
            track_count: item.track_count || item.trackCount || 25,
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
        <img class="track-thumb" src="${escapeHtml(art)}" alt="" loading="lazy" onerror="this.src='apple-touch-icon.svg'">
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

  function switchMobileView(viewId, skipFetch = false) {
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

    // Hide all views first
    dom.viewNowPlaying.classList.remove('active');
    dom.viewQueue.classList.remove('active');
    dom.viewLibrary.classList.remove('active');
    if (dom.viewHome) dom.viewHome.classList.remove('active');
    if (dom.viewTrends) dom.viewTrends.classList.remove('active');
    if (dom.recentDetailPane) {
      dom.recentDetailPane.classList.remove('active');
      dom.recentDetailPane.classList.add('hidden');
    }
    if (dom.sectionGridView) {
      dom.sectionGridView.classList.remove('active');
      dom.sectionGridView.classList.add('hidden');
    }
    dom.viewSearch.classList.remove('active');

    // Activate selected view
    const target = document.getElementById(viewId);
    if (target) {
      target.classList.add('active');
    }
    syncKeyboardFocusClass();

    // Manage Mini-Player visibility on mobile
    if (viewId === 'view-now-playing') {
      dom.miniPlayer.classList.add('hidden');
    } else {
      dom.miniPlayer.classList.remove('hidden');
    }

    if (viewId === 'view-library') {
      if (!skipFetch) {
        if (dom.playlistsBrowsePane) dom.playlistsBrowsePane.classList.remove('hidden');
        if (dom.playlistDetailPane) dom.playlistDetailPane.classList.add('hidden');
        send({ action: 'get_playlists' });
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
    switchMobileView(state.lastNonPlayerView || 'view-home');
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
    if (tabName !== 'search' && dom.searchInput && document.activeElement === dom.searchInput) {
      dom.searchInput.blur();
    }
    state.desktopActiveTab = tabName;

    dom.desktopNavButtons.forEach(b => {
      b.classList.toggle('active', b.dataset.target === tabName);
    });

    dom.viewQueue.classList.remove('active');
    dom.viewLibrary.classList.remove('active');
    if (dom.viewHome) dom.viewHome.classList.remove('active');
    if (dom.viewTrends) dom.viewTrends.classList.remove('active');
    if (dom.recentDetailPane) {
      dom.recentDetailPane.classList.remove('active');
      dom.recentDetailPane.classList.add('hidden');
    }
    if (dom.sectionGridView) {
      dom.sectionGridView.classList.remove('active');
      dom.sectionGridView.classList.add('hidden');
    }
    dom.viewSearch.classList.remove('active');

    if (tabName === 'home' || tabName === 'trends') {
      if (dom.viewHome) dom.viewHome.classList.add('active');
      else if (dom.viewTrends) dom.viewTrends.classList.add('active');
      if (!keepDetailOpen) loadTrends();
    } else if (tabName === 'queue') {
      dom.viewQueue.classList.add('active');
      if (!keepDetailOpen) send({ action: 'get_queue' });
    } else if (tabName === 'library') {
      dom.viewLibrary.classList.add('active');
      if (!keepDetailOpen) {
        if (dom.playlistsBrowsePane) dom.playlistsBrowsePane.classList.remove('hidden');
        if (dom.playlistDetailPane) dom.playlistDetailPane.classList.add('hidden');
        send({ action: 'get_playlists' });
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

  // Handle responsive layout changes on resize
  function handleResize() {
    syncStandbyAndMotionCoverUI();
    syncActiveMotionVideoTarget();
    const detailOpen = Boolean(dom.playlistDetailPane && !dom.playlistDetailPane.classList.contains('hidden'));
    if (isDesktopLayout()) {
      // On desktop, ensure right column displays active desktop tab
      switchDesktopTab(state.desktopActiveTab, detailOpen, { fromResize: true });
    } else {
      // On mobile, ensure active mobile view is respected
      switchMobileView(state.activeView, detailOpen);
    }
  }
  window.addEventListener('resize', handleResize);
  window.addEventListener('orientationchange', handleResize);

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
    const sbAiVibe = document.getElementById('standby-btn-ai-track-vibe');

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
      if (sbTitle && sbTitle.textContent !== 'Не играет') sbTitle.textContent = 'Не играет';
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
    if (sbDacText) {
      const devPart = state.audioDeviceName ? ` · ${state.audioDeviceName}` : '';
      sbDacText.textContent = `${formatDacPill(state.audioQuality)}${devPart}`;
    } else if (sbDac) {
      const devPart = state.audioDeviceName ? ` · ${state.audioDeviceName}` : '';
      sbDac.textContent = `${formatDacPill(state.audioQuality)}${devPart}`;
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
    syncMotionVideoPlaybackState();
    ScreenWakeLockManager.syncByPlaybackAndConnection();
    syncSpectralPolling();
    refreshAllTitleMarquees();
  }

  let lastStandbyTilesSignature = '';

  function openStandbyLibraryModal() {
    const modal = document.getElementById('standby-library-modal');
    if (!modal) return;
    closeStandbyAiModal();
    renderStandbyQuickTiles();
    if (!state.playlists || state.playlists.length === 0) {
      send({ action: 'get_playlists' });
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
        country: state.userStorefront || state.trends.country || 'ru',
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

  function appendStandbyAiTagBatch(count = 24) {
    const cloud = document.getElementById('standby-ai-tag-cloud');
    if (!cloud) return;
    const frag = document.createDocumentFragment();
    for (let i = 0; i < count; i++) {
      const item = buildNextStandbyAiTagItem();
      frag.appendChild(createStandbyAiTagPillElement(item, false));
    }
    cloud.appendChild(frag);
  }

  function resetAndGenerateStandbyAiTagCloud() {
    const cloud = document.getElementById('standby-ai-tag-cloud');
    const scrollEl = document.getElementById('standby-ai-scroll');
    if (!cloud) return;
    cloud.innerHTML = '';
    if (scrollEl) scrollEl.scrollTop = 0;
    standbyAiGeneratedCount = 0;
    if (Array.isArray(state.pinnedAiPrompts) && state.pinnedAiPrompts.length > 0) {
      const pinFrag = document.createDocumentFragment();
      state.pinnedAiPrompts.forEach((p, idx) => {
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

    let throttleTick = false;
    scrollEl.addEventListener('scroll', () => {
      if (throttleTick) return;
      throttleTick = true;
      requestAnimationFrame(() => {
        throttleTick = false;
        if (scrollEl.scrollTop + scrollEl.clientHeight >= scrollEl.scrollHeight - 320) {
          appendStandbyAiTagBatch(18);
        }
      });
    }, { passive: true });

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

  function renderStandbyQuickTiles() {
    const grid = document.getElementById('standby-library-grid');
    if (!grid) return;

    const rawPlaylists = (state.playlists || []).filter(pl => {
      const n = (pl.name || '').trim();
      if (!n) return false;
      if (n.includes('Очередь AMR') || n.startsWith('AMR ')) return false;
      return true;
    });

    const sig = rawPlaylists.map(p => `${p.name}:${p.artwork_url || p.artworkUrl || ''}:${p.track_count || p.trackCount || 0}`).join('|') +
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
        title: 'Моя станция',
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
        title: 'Станция открытий',
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
        title: 'В моём вкусе',
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
        title: 'Сейчас на повторе',
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
    ];

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
    rawPlaylists.forEach(pl => {
      const plName = (pl.name || '').trim();
      const lower = plName.toLowerCase();
      if (lower === 'в моём вкусе' || lower === 'в моем вкусе' || lower === 'сейчас на повторе') return;

      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'standby-square-tile';
      const tileKey = `pl:${plName}`;
      btn.setAttribute('data-tile-key', tileKey);
      btn.setAttribute('data-tile-name', plName);
      btn.setAttribute('title', plName);

      const count = pl.track_count || pl.trackCount || 0;
      const countText = count > 0 ? `<span class="standby-tile-meta">${count} треков</span>` : '';
      const artUrl = pl.artwork_url || pl.artworkUrl || `/api/artwork/playlist?name=${encodeURIComponent(plName)}`;
      btn.innerHTML = `
        <img class="standby-tile-cover" src="${escapeHtml(artUrl)}" alt="${escapeHtml(plName)}" loading="lazy" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
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

    updateStandbyActiveTile();
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

    stopVideoKeepAlive() {
      if (this.keepAliveTimer) {
        clearInterval(this.keepAliveTimer);
        this.keepAliveTimer = null;
      }
      if (this.keepAliveVideo && !this.keepAliveVideo.paused) {
        try {
          this.keepAliveVideo.pause();
        } catch (_) {}
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

          const captureFn = this.keepAliveCanvas.captureStream || this.keepAliveCanvas.webkitCaptureStream;
          if (typeof captureFn === 'function') {
            const stream = captureFn.call(this.keepAliveCanvas, 1);
            vid.srcObject = stream;
          }
        }

        if (this.keepAliveVideo && this.keepAliveVideo.paused) {
          this.keepAliveVideo.play().catch(() => {});
        }
      } catch (_) {}
    },

    release() {
      this.isActive = false;
      this.stopVideoKeepAlive();
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
    if (!state.playlists || state.playlists.length === 0) {
      send({ action: 'get_playlists' });
    }
    syncStandbyAndMotionCoverUI();
    syncActiveMotionVideoTarget();
    syncBookletViewerLayoutMode();
    updateScrubberUI(state.lastSyncPos, state.duration);
    updateStandbyClock();
    refreshAllTitleMarquees(true);
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
      if (localStorage.getItem('amr_tv_mode_active') === '1') {
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
    const sbAiVibeBtn = document.getElementById('standby-btn-ai-track-vibe');
    const sbTrack = document.getElementById('standby-progress-track');

    if (sbPlayPause) sbPlayPause.addEventListener('click', togglePlayPause);
    if (sbPrev) sbPrev.addEventListener('click', () => sendThrottledTransport('previous'));
    if (sbNext) sbNext.addEventListener('click', () => sendThrottledTransport('next'));
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
          blurFocusedInContainer(dom.qualityModal);
          dom.qualityModal.classList.add('hidden');
          dom.qualityModal.setAttribute('aria-hidden', 'true');
          syncSpectralPolling();
          return;
        }
        if (dom.stationPickerModal && !dom.stationPickerModal.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          blurFocusedInContainer(dom.stationPickerModal);
          dom.stationPickerModal.classList.add('hidden');
          dom.stationPickerModal.setAttribute('aria-hidden', 'true');
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
      headers: {
        'X-AMR-Device-ID': state.deviceId || ''
      }
    });
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    const info = await resp.json();
    setBoundedMapValue(bookletAvailabilityCache, cacheKey, info, 200);
    return info;
  }

  async function syncCurrentTrackBookletAvailability() {
    const btnOpenNowPlaying = document.getElementById('btn-open-booklet');
    const btnOpenStandby = document.getElementById('standby-booklet-btn');
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

  function setupBookletViewerControls() {
    const btnOpenNowPlaying = document.getElementById('btn-open-booklet');
    const btnOpenStandby = document.getElementById('standby-booklet-btn');
    const btnOpenDetail = document.getElementById('btn-detail-booklet');
    const btnClose = document.getElementById('btn-close-booklet');

    if (btnOpenNowPlaying) {
      btnOpenNowPlaying.addEventListener('click', () => {
        if (dom.stationPickerModal) {
          blurFocusedInContainer(dom.stationPickerModal);
          dom.stationPickerModal.classList.add('hidden');
          dom.stationPickerModal.setAttribute('aria-hidden', 'true');
        }
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

    if (!boolVal || !state.deviceAuthorized) {
      teardownMediaSessionAndSilentAudio();
    } else {
      initSilentAudio();
      setupMediaSession();
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
      deviceUidMetaEl.textContent = translateTextToEn(`UID: ${state.deviceId} • Авторизовано на Mac`);
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

    if (data.device_name && String(data.device_name).trim()) {
      state.deviceName = String(data.device_name).trim();
      try { localStorage.setItem('amr_device_name', state.deviceName); } catch (e) {}
    }

    if (typeof data.authorized === 'boolean') {
      state.deviceAuthorized = data.authorized;
    }

    if (typeof data.lock_screen_controls === 'boolean') {
      applyLockScreenControlsSetting(data.lock_screen_controls, { syncServer: false, showFeedback: false });
    } else if (!state.deviceAuthorized) {
      teardownMediaSessionAndSilentAudio();
    }

    if (!state.deviceAuthorized) {
      state.initialAuthFetched = false;
    }

    syncDeviceInfoUI();

    // Load status, queue, library, and Apple ID / MusicKit status ONLY after device is authorized
    if (state.deviceAuthorized && !state.initialAuthFetched && state.connected) {
      state.initialAuthFetched = true;
      send({ action: 'get_status' });
      send({ action: 'get_queue' });
      send({ action: 'get_playlists' });
      send({ action: 'get_explore', params: { country: state.trends.country } });
      send({ action: 'get_audio_devices' });
      send({ action: 'get_user_token_status' });
      send({ action: 'get_developer_token' });
      send({ action: 'get_account_status' });
      send({ action: 'get_wled_settings' });
      send({ action: 'get_ai_curator_settings' });
      send({ action: 'get_info' });
    }
  }

  function handleShareAccessQR(data) {
    if (!data || typeof data !== 'object') return;
    const shareUrl = String(data.share_url || data.base_url || window.location.origin);
    const qrDataUrl = String(data.qr_data_url || '');
    state.shareAccessUrl = shareUrl;

    const qrPanel = document.getElementById('amr-share-qr-panel');
    const qrImg = document.getElementById('amr-share-qr-img');
    const urlText = document.getElementById('amr-share-url-text');
    const btnNativeShare = document.getElementById('btn-native-share-link');

    if (qrImg && qrDataUrl) {
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

  // Initialize
  setupAmrInfoAndDeviceAuthControls();
  setupMediaSession();
  setupArtworkSwipeGestures();
  setupMiniPlayerGestures();
  setupStandbyAndWledControls();
  setupBookletViewerControls();
  renderHeroCarousel({});
  renderHomeStations(DEFAULT_STATIONS);
  renderHomeGenres(DEFAULT_GENRES);
  bindGenreCards();
  handleResize();
  recoverOrPersistDeviceUidBeforeConnect().finally(() => {
    connectWebSocket();
  });

})();
