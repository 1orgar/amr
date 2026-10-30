import Foundation

public struct WebUIContent {
    public static let indexHTML = ##"""
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <meta name="apple-mobile-web-app-title" content="AMR">
  <meta name="apple-touch-fullscreen" content="yes">
  <meta name="format-detection" content="telephone=no">
  <meta name="theme-color" content="#000000" media="(prefers-color-scheme: dark)">
  <meta name="theme-color" content="#000000">
  <meta name="description" content="Apple Music Remote Mac - Bit-Perfect High-Fidelity Controller">
  <title>Apple Music Remote</title>

  <link rel="icon" type="image/svg+xml" href="/apple-touch-icon.svg">
  <link rel="icon" type="image/png" sizes="192x192" href="/apple-touch-icon-192.png">
  <link rel="apple-touch-icon" href="/apple-touch-icon.png">
  <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon-180.png">
  <link rel="apple-touch-icon" sizes="192x192" href="/apple-touch-icon-192.png">
  <link rel="apple-touch-icon" sizes="512x512" href="/apple-touch-icon-512.png">
  <link rel="manifest" href="/manifest.json">
  <link rel="stylesheet" href="/style.css?v=233">
  <script src="https://js-cdn.music.apple.com/musickit/v3/musickit.js" async></script>
</head>
<body>
  <!-- iOS Lock Screen & Background Media Keep-Alive -->
  <audio id="bg-silent-audio" preload="auto" playsinline webkit-playsinline loop src="/assets/silence.m4a?v=2" style="position:fixed;bottom:0;left:0;width:1px;height:1px;opacity:0.001;pointer-events:none;z-index:-1;"></audio>

  <!-- Connection Lost Overlay -->
  <div id="connection-overlay" class="overlay-modal hidden" aria-hidden="true">
    <div class="overlay-card">
      <div class="pulse-indicator"></div>
      <h2 class="overlay-title">Нет связи с Mac</h2>
      <p class="overlay-desc" id="connection-status-text">Попытка автоматического переподключения к Apple Music...</p>
      <button id="btn-reconnect" class="btn-primary" type="button">Переподключиться</button>
    </div>
  </div>

  <!-- Apple TV Style Dynamic Ambient Gradient Backdrop -->
  <div id="ambient-backdrop" class="ambient-backdrop" aria-hidden="true">
    <div class="ambient-layer ambient-layer-a" id="ambient-layer-a">
      <div class="ambient-blob blob-1"></div>
      <div class="ambient-blob blob-2"></div>
      <div class="ambient-blob blob-3"></div>
      <div class="ambient-blob blob-4"></div>
    </div>
    <div class="ambient-layer ambient-layer-b" id="ambient-layer-b">
      <div class="ambient-blob blob-1"></div>
      <div class="ambient-blob blob-2"></div>
      <div class="ambient-blob blob-3"></div>
      <div class="ambient-blob blob-4"></div>
    </div>
    <div class="ambient-vignette"></div>
  </div>

  <!-- Main Application Wrapper -->
  <div id="app" class="app-layout">

    <!-- Left Column on Desktop / Full View on Mobile -->
    <section id="view-now-playing" class="view-panel player-panel active">
      <header class="player-top-header">
        <div class="brand-pill">
          <span class="brand-dot"></span>
          <span class="brand-title">AMR <span class="brand-ver" id="brand-ver">v2.3.0</span></span>
        </div>
        <button id="audio-quality-badge" class="quality-badge" type="button" title="Параметры потока и ЦАП">
          <svg class="icon-dac" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <circle cx="12" cy="12" r="10"/>
            <polygon points="10 8 16 12 10 16 10 8"/>
          </svg>
          <span id="audio-quality-text">LOSSLESS</span>
        </button>
      </header>

      <!-- Artwork Area -->
      <div class="artwork-container">
        <div class="artwork-wrapper">
          <img id="player-artwork" class="player-art" src="apple-touch-icon.svg" alt="Обложка трека">
          <div id="player-art-placeholder" class="art-placeholder hidden">
            <svg viewBox="0 0 24 24" width="64" height="64" fill="currentColor">
              <path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z"/>
            </svg>
          </div>
        </div>
      </div>

      <!-- Track Information -->
      <div class="track-meta">
        <div class="track-title-row">
          <h1 id="player-title" class="track-title" title="Не играет">Не играет</h1>
          <div class="track-actions-group">
            <button id="btn-create-station" class="btn-icon btn-station" type="button" aria-label="Создать радио" title="Создать радиостанцию">
              <svg class="svg-icon icon-station" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M4.93 19.07a10 10 0 0 1 0-14.14"/>
                <path d="M7.76 16.24a6 6 0 0 1 0-8.48"/>
                <circle cx="12" cy="12" r="2" fill="currentColor"/>
                <path d="M16.24 7.76a6 6 0 0 1 0 8.48"/>
                <path d="M19.07 4.93a10 10 0 0 1 0 14.14"/>
              </svg>
            </button>
            <button id="btn-favorite" class="btn-icon btn-fav" type="button" aria-label="Избранное" title="В избранное">
              <svg id="icon-fav" class="svg-icon icon-star" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/>
              </svg>
            </button>
          </div>
        </div>
        <p id="player-artist" class="track-artist">Apple Music</p>
        <p id="player-album" class="track-album"></p>
      </div>

      <!-- Scrubber Timeline (Optimistic 60fps local scrubbing) -->
      <div class="scrubber-section">
        <div class="scrubber-bar-container" id="scrubber-container">
          <div class="scrubber-track">
            <div id="scrubber-fill" class="scrubber-fill" style="width: 0%;"></div>
            <div id="scrubber-thumb" class="scrubber-thumb" style="left: 0%;"></div>
          </div>
          <input type="range" id="scrubber-input" min="0" max="100" value="0" step="0.1" aria-label="Позиция трека">
        </div>
        <div class="scrubber-timestamps">
          <span id="time-elapsed" class="time-label">0:00</span>
          <span id="time-remaining" class="time-label">-0:00</span>
        </div>
      </div>

      <!-- Primary Transport Controls (NO volume slider per bit-perfect mode) -->
      <div class="transport-controls">
        <button id="btn-shuffle" class="btn-icon control-sub" type="button" aria-label="Случайно" title="Перемешать">
          <svg class="svg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <polyline points="16 3 21 3 21 8"/>
            <line x1="4" y1="20" x2="21" y2="3"/>
            <polyline points="21 16 21 21 16 21"/>
            <line x1="15" y1="15" x2="21" y2="21"/>
            <line x1="4" y1="4" x2="9" y2="9"/>
          </svg>
        </button>

        <button id="btn-prev" class="btn-icon control-skip" type="button" aria-label="Предыдущий" title="Предыдущий трек">
          <svg class="svg-icon" viewBox="0 0 24 24" fill="currentColor">
            <polygon points="19 20 9 12 19 4 19 20"/>
            <line x1="5" y1="19" x2="5" y2="5" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"/>
          </svg>
        </button>

        <button id="btn-play-pause" class="btn-icon control-play-main" type="button" aria-label="Воспроизвести" title="Воспроизведение / Пауза">
          <!-- Play SVG -->
          <svg id="icon-play" class="svg-icon-play" viewBox="0 0 24 24" fill="currentColor">
            <polygon points="6 3 20 12 6 21 6 3"/>
          </svg>
          <!-- Pause SVG -->
          <svg id="icon-pause" class="svg-icon-pause hidden" viewBox="0 0 24 24" fill="currentColor">
            <rect x="5" y="4" width="4.5" height="16" rx="1.5"/>
            <rect x="14.5" y="4" width="4.5" height="16" rx="1.5"/>
          </svg>
        </button>

        <button id="btn-next" class="btn-icon control-skip" type="button" aria-label="Следующий" title="Следующий трек">
          <svg class="svg-icon" viewBox="0 0 24 24" fill="currentColor">
            <polygon points="5 4 15 12 5 20 5 4"/>
            <line x1="19" y1="5" x2="19" y2="19" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"/>
          </svg>
        </button>

        <button id="btn-repeat" class="btn-icon control-sub" type="button" aria-label="Повтор" title="Режим повтора">
          <svg class="svg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <polyline points="17 1 21 5 17 9"/>
            <path d="M3 11V9a4 4 0 0 1 4-4h14"/>
            <polyline points="7 23 3 19 7 15"/>
            <path d="M21 13v2a4 4 0 0 1-4 4H3"/>
          </svg>
          <span id="repeat-badge" class="repeat-one-indicator hidden">1</span>
        </button>
      </div>

      <!-- Volume Section (Visible when Lock Volume 100% is OFF) -->
      <div id="volume-section" class="volume-section hidden">
        <button id="btn-volume-mute" class="btn-icon btn-volume-mute" type="button" aria-label="Отключить звук" title="Без звука">
          <svg id="volume-icon" class="svg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/>
            <path id="vol-wave-1" d="M15.54 8.46a5 5 0 0 1 0 7.07"/>
            <path id="vol-wave-2" d="M19.07 4.93a10 10 0 0 1 0 14.14"/>
          </svg>
        </button>
        <div class="volume-slider-container">
          <div class="volume-track">
            <div id="volume-track-fill" class="volume-track-fill" style="width: 100%;"></div>
            <div id="volume-thumb" class="volume-thumb" style="left: 100%;"></div>
          </div>
          <input type="range" id="volume-input" class="volume-input" min="0" max="100" value="100" step="1" aria-label="Громкость">
        </div>
        <span id="volume-level-text" class="volume-level-label">100%</span>
      </div>
    </section>

    <!-- Right Column on Desktop / Switched Views on Mobile -->
    <main class="content-panel-wrapper">
      <!-- Desktop Navigation Tabs -->
      <nav class="desktop-nav-header">
        <div class="desktop-nav-tabs">
          <button class="nav-tab-btn active" data-target="home">Главная</button>
          <button class="nav-tab-btn" data-target="library">Медиатека</button>
          <button class="nav-tab-btn" data-target="queue">Очередь</button>
          <button class="nav-tab-btn" data-target="search">Поиск</button>
        </div>
      </nav>

      <!-- Mobile Top Bar with Permanent DAC Badge (visible on mobile outside Now Playing) -->
      <header class="mobile-top-bar">
        <div class="brand-pill">
          <span class="brand-dot"></span>
          <span class="brand-title">AMR <span class="brand-ver">v2.3.0</span></span>
        </div>
        <button id="mobile-dac-badge" class="quality-badge mobile-dac-badge" type="button" title="Параметры потока и ЦАП">
          <svg class="icon-dac" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <circle cx="12" cy="12" r="10"/>
            <polygon points="10 8 16 12 10 16 10 8"/>
          </svg>
          <span id="mobile-dac-text">LOSSLESS</span>
        </button>
      </header>

      <!-- Queue View -->
      <section id="view-queue" class="view-panel content-view">
        <header class="section-header">
          <div>
            <h2 class="section-title">Очередь воспроизведения</h2>
            <p id="queue-subtitle" class="section-subtitle">0 треков</p>
          </div>
          <button id="btn-clear-queue" class="btn-ghost" type="button">Очистить далее</button>
        </header>

        <div class="scroll-pane">
          <!-- Currently Playing Section -->
          <div id="queue-current-group" class="queue-group">
            <h3 class="group-title">СЕЙЧАС ИГРАЕТ</h3>
            <div id="queue-current-track" class="track-list">
              <!-- Rendered dynamically -->
            </div>
          </div>

          <!-- Upcoming Section -->
          <div class="queue-group">
            <h3 class="group-title">ДАЛЕЕ В ОЧЕРЕДИ</h3>
            <div id="queue-upcoming-list" class="track-list">
              <div class="empty-state">Нет предстоящих треков</div>
            </div>
          </div>
        </div>
      </section>

      <!-- Library View -->
      <section id="view-library" class="view-panel content-view">
        <!-- Playlists List -->
        <div id="playlists-browse-pane" class="library-pane">
          <header class="section-header">
            <div>
              <h2 class="section-title">Медиатека</h2>
              <p class="section-subtitle">Плейлисты и альбомы</p>
            </div>
            <button id="btn-refresh-library" class="btn-ghost" type="button" title="Обновить список">Обновить</button>
          </header>

          <div class="scroll-pane">
            <div id="playlists-grid" class="playlists-grid">
              <div class="loading-state">Загрузка плейлистов...</div>
            </div>
          </div>
        </div>

        <!-- Playlist Detail Pane (Drill-down) -->
        <div id="playlist-detail-pane" class="library-pane hidden">
          <header class="detail-header">
            <button id="btn-back-to-playlists" class="btn-back" type="button">
              <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.5">
                <polyline points="15 18 9 12 15 6"/>
              </svg>
              <span>Плейлисты</span>
            </button>
          </header>

          <div class="detail-hero">
            <img id="detail-artwork" class="detail-art" src="apple-touch-icon.svg" alt="Обложка плейлиста" onerror="this.src='apple-touch-icon.svg'">
            <div class="detail-info">
              <span id="detail-badge" class="detail-badge">ПЛЕЙЛИСТ</span>
              <h2 id="detail-title" class="detail-title">Название</h2>
              <p id="detail-meta" class="detail-meta">0 треков</p>
              <div class="detail-actions">
                <button id="btn-play-playlist" class="btn-primary-action" type="button">
                  <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
                    <polygon points="6 3 20 12 6 21 6 3"/>
                  </svg>
                  <span>Слушать</span>
                </button>
                <button id="btn-shuffle-playlist" class="btn-secondary-action" type="button">
                  <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2">
                    <polyline points="16 3 21 3 21 8"/>
                    <line x1="4" y1="20" x2="21" y2="3"/>
                    <polyline points="21 16 21 21 16 21"/>
                    <line x1="15" y1="15" x2="21" y2="21"/>
                    <line x1="4" y1="4" x2="9" y2="9"/>
                  </svg>
                  <span>Перемешать</span>
                </button>
              </div>
            </div>
          </div>

          <div class="scroll-pane">
            <div id="playlist-tracks-list" class="track-list">
              <div class="loading-state">Загрузка треков...</div>
            </div>
          </div>
        </div>
      </section>

      <!-- Home (Главная) View -->
      <section id="view-home" class="view-panel content-view active">
        <header class="section-header home-header">
          <div>
            <h1 class="main-home-title">Главная</h1>
          </div>
        </header>

        <div class="scroll-pane home-scroll-pane">
          <!-- Account Status Card on Home -->
          <div class="home-account-card" id="home-account-card">
            <div class="account-card-left">
              <div class="account-card-avatar">
                <span class="apple-logo-icon"></span>
                <span class="account-status-dot synced" id="account-status-dot" title="Синхронизировано"></span>
              </div>
              <div class="account-card-info">
                <div class="account-card-email-row">
                  <span class="account-email" id="account-card-email">tse.tds@gmail.com</span>
                  <span class="account-sync-badge" id="account-card-badge">СИНХРОНИЗИРОВАНО</span>
                </div>
                <div class="account-card-subtext" id="account-card-subtext">Apple Music: подписка активна • Регион US • Медиатека синхронизирована</div>
              </div>
            </div>
            <div class="account-card-actions">
              <button class="btn-account-diag" id="btn-account-diag" type="button" title="Диагностика аккаунта">
                <span>Диагностика</span>
                <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2">
                  <polyline points="9 18 15 12 9 6"></polyline>
                </svg>
              </button>
            </div>
          </div>
          <!-- 1. Hero Carousel (Подборка лучших) -->
          <div class="home-section" id="home-hero-section">
            <h2 class="home-section-title">Подборка лучших</h2>
            <div id="home-hero-carousel" class="home-hero-carousel">
              <div class="loading-state">Загрузка...</div>
            </div>
          </div>

          <!-- 2. Recently Played (Вы недавно слушали ›) -->
          <div class="home-section hidden" id="home-recent-section">
            <div class="home-section-header-link" id="home-recent-link">
              <h2 class="home-section-title">Вы недавно слушали</h2>
              <span class="home-chevron">›</span>
            </div>
            <div id="home-recent-carousel" class="home-carousel-row">
              <div class="loading-state">Загрузка...</div>
            </div>
          </div>

          <!-- 3. Stations (Станции для вас ›) -->
          <div class="home-section" id="home-stations-section">
            <div class="home-section-header-link" id="home-stations-link">
              <h2 class="home-section-title">Станции для вас</h2>
              <span class="home-chevron">›</span>
            </div>
            <div id="home-stations-carousel" class="home-stations-grid">
              <div class="loading-state">Загрузка станций...</div>
            </div>
          </div>

          <!-- 4. Popular Albums (Популярные альбомы ›) -->
          <div class="home-section" id="home-albums-section">
            <div class="home-section-header-link" id="home-albums-link">
              <h2 class="home-section-title">Популярные альбомы</h2>
              <span class="home-chevron">›</span>
            </div>
            <div id="home-albums-carousel" class="home-carousel-row">
              <div class="loading-state">Загрузка альбомов...</div>
            </div>
          </div>

          <!-- 5. Genres (Жанры и категории ›) -->
          <div class="home-section" id="home-genres-section">
            <div class="home-section-header-link">
              <h2 class="home-section-title">Жанры и категории</h2>
              <span class="home-chevron">›</span>
            </div>
            <div id="home-genres-grid" class="genres-grid">
              <!-- Rendered dynamically -->
            </div>
          </div>
        </div>
      </section>

      <!-- Recently Played Full View Pane -->
      <section id="recent-detail-pane" class="view-panel content-view hidden">
        <header class="section-header">
          <button id="btn-back-from-recent" class="btn-back" type="button" aria-label="Назад к главной">
            <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2">
              <polyline points="15 18 9 12 15 6"></polyline>
            </svg>
            <span>Главная</span>
          </button>
          <h1 class="header-title">Вы недавно слушали</h1>
        </header>

        <div class="detail-header-compact">
          <div class="detail-info-full">
            <span class="detail-badge">ИСТОРИЯ</span>
            <h2 class="detail-title">Недавно прослушанные треки</h2>
            <p id="recent-total-count" class="detail-meta">0 треков</p>
            <div class="detail-actions">
              <button id="btn-play-recent-all" class="btn-primary-action" type="button">
                <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
                  <polygon points="6 3 20 12 6 21 6 3"/>
                </svg>
                <span>Слушать</span>
              </button>
              <button id="btn-shuffle-recent-all" class="btn-secondary-action" type="button">
                <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2">
                  <polyline points="16 3 21 3 21 8"/>
                  <line x1="4" y1="20" x2="21" y2="3"/>
                  <polyline points="21 16 21 21 16 21"/>
                  <line x1="15" y1="15" x2="21" y2="21"/>
                  <line x1="4" y1="4" x2="9" y2="9"/>
                </svg>
                <span>Перемешать</span>
              </button>
            </div>
          </div>
        </div>

        <div class="scroll-pane">
          <div id="recent-tracks-full-list" class="track-list">
            <div class="loading-state">Загрузка...</div>
          </div>
        </div>
      </section>

      <!-- Search View -->
      <section id="view-search" class="view-panel content-view">
        <header class="section-header search-header-wrap">
          <div class="search-input-box">
            <svg class="search-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <circle cx="11" cy="11" r="8"/>
              <line x1="21" y1="21" x2="16.65" y2="16.65"/>
            </svg>
            <input type="search" id="search-input" placeholder="Поиск в Apple Music..." autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false">
            <button id="btn-clear-search" class="search-clear hidden" type="button" aria-label="Очистить">&times;</button>
          </div>
        </header>

        <div class="search-filters">
          <button class="filter-chip active" data-scope="all">Все</button>
          <button class="filter-chip" data-scope="songs">Песни</button>
          <button class="filter-chip" data-scope="albums">Альбомы</button>
          <button class="filter-chip" data-scope="artists">Артисты</button>
        </div>

        <div class="scroll-pane">
          <div id="search-results" class="search-results-pane">
            <div class="search-placeholder">
              <svg viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="#38383a" stroke-width="1.5">
                <circle cx="11" cy="11" r="8"/>
                <line x1="21" y1="21" x2="16.65" y2="16.65"/>
              </svg>
              <p>Ищите любимые треки, альбомы и исполнителей</p>
            </div>
          </div>
        </div>
      </section>
    </main>

    <!-- Mobile Mini-Player (Docked directly above bottom tabs) -->
    <aside id="mini-player" class="mini-player hidden">
      <div class="mini-player-content" id="mini-player-trigger" title="Развернуть проигрыватель">
        <img id="mini-artwork" class="mini-art" src="apple-touch-icon.svg" alt="Обложка">
        <div class="mini-info">
          <span id="mini-title" class="mini-title">Не играет</span>
          <span id="mini-artist" class="mini-artist">Apple Music</span>
        </div>
      </div>
      <div class="mini-actions">
        <button id="mini-btn-favorite" class="btn-icon mini-btn mini-btn-fav" type="button" aria-label="Избранное" title="В избранное">
          <svg class="svg-icon icon-star" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/>
          </svg>
        </button>
        <button id="mini-btn-play-pause" class="btn-icon mini-btn" type="button" aria-label="Воспроизведение">
          <svg id="mini-icon-play" viewBox="0 0 24 24" width="22" height="22" fill="currentColor">
            <polygon points="6 3 20 12 6 21 6 3"/>
          </svg>
          <svg id="mini-icon-pause" class="hidden" viewBox="0 0 24 24" width="22" height="22" fill="currentColor">
            <rect x="5" y="4" width="4" height="16" rx="1"/>
            <rect x="15" y="4" width="4" height="16" rx="1"/>
          </svg>
        </button>
        <button id="mini-btn-next" class="btn-icon mini-btn" type="button" aria-label="Следующий">
          <svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor">
            <polygon points="5 4 15 12 5 20 5 4"/>
            <line x1="19" y1="5" x2="19" y2="19" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"/>
          </svg>
        </button>
      </div>
      <!-- Mini Progress Line -->
      <div class="mini-progress-track">
        <div id="mini-progress-fill" class="mini-progress-fill" style="width: 0%;"></div>
      </div>
    </aside>

    <!-- Mobile Bottom Tab Bar -->
    <nav id="bottom-tab-bar" class="bottom-tab-bar">
      <button class="tab-item active" data-view="view-now-playing">
        <svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor">
          <circle cx="12" cy="12" r="10"/>
          <polygon points="10 8 16 12 10 16 10 8" fill="#000000"/>
        </svg>
        <span>Сейчас</span>
      </button>

      <button class="tab-item" data-view="view-home">
        <svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor">
          <path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/>
        </svg>
        <span>Главная</span>
      </button>

      <button class="tab-item" data-view="view-library">
        <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">
          <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/>
          <path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>
          <line x1="9" y1="7" x2="15" y2="7"/>
          <line x1="9" y1="11" x2="13" y2="11"/>
        </svg>
        <span>Медиатека</span>
      </button>

      <button class="tab-item" data-view="view-queue">
        <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">
          <line x1="8" y1="6" x2="21" y2="6"/>
          <line x1="8" y1="12" x2="21" y2="12"/>
          <line x1="8" y1="18" x2="21" y2="18"/>
          <line x1="3" y1="6" x2="3.01" y2="6"/>
          <line x1="3" y1="12" x2="3.01" y2="12"/>
          <line x1="3" y1="18" x2="3.01" y2="18"/>
        </svg>
        <span>Очередь</span>
      </button>

      <button class="tab-item" data-view="view-search">
        <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">
          <circle cx="11" cy="11" r="8"/>
          <line x1="21" y1="21" x2="16.65" y2="16.65"/>
        </svg>
        <span>Поиск</span>
      </button>
    </nav>

  </div>

  <!-- Radio Station Picker Modal -->
  <div id="station-picker-modal" class="modal-backdrop hidden" aria-hidden="true">
    <div class="modal-card station-modal-card">
      <div class="modal-header">
        <div class="modal-title-wrap">
          <h3 class="modal-title">Создать радиостанцию</h3>
          <span class="modal-tag">APPLE MUSIC</span>
        </div>
        <button id="btn-close-station-modal" class="modal-close" type="button" aria-label="Закрыть">&times;</button>
      </div>

      <div class="modal-body">
        <p class="modal-subtitle">Бесконечный радиопоток на основе ваших предпочтений</p>
        <div class="station-options-list">
          <button id="btn-station-by-track" class="station-option-btn" type="button">
            <div class="station-opt-icon">
              <svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor">
                <path d="M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z"/>
              </svg>
            </div>
            <div class="station-opt-details">
              <span class="station-opt-primary">По текущему треку</span>
              <span id="station-opt-track-name" class="station-opt-secondary">—</span>
            </div>
          </button>

          <button id="btn-station-by-artist" class="station-option-btn" type="button">
            <div class="station-opt-icon">
              <svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor">
                <path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/>
              </svg>
            </div>
            <div class="station-opt-details">
              <span class="station-opt-primary">По исполнителю</span>
              <span id="station-opt-artist-name" class="station-opt-secondary">—</span>
            </div>
          </button>
        </div>
      </div>
    </div>
  </div>

  <!-- Signal Path Inspector Modal (Roon-like Audio Pipeline) -->
  <div id="quality-modal" class="modal-backdrop hidden" aria-hidden="true">
    <div class="modal-card signal-path-card">
      <div class="modal-header">
        <div class="modal-title-wrap">
          <h3 class="modal-title">Тракт сигнала</h3>
          <span class="modal-tag">BIT-PERFECT DIRECT</span>
        </div>
        <button id="btn-close-modal" class="modal-close" type="button" aria-label="Закрыть">&times;</button>
      </div>

      <div class="modal-body signal-path-body">
        <div class="signal-path-chain">
          <!-- Step 1: Audio Source -->
          <div class="signal-node" id="signal-node-source">
            <div class="signal-node-dot"></div>
            <div class="signal-node-main">
              <div class="signal-node-top">
                <span class="signal-node-badge">ИСТОЧНИК</span>
                <span id="signal-source-badge" class="signal-node-format">ALAC Lossless</span>
              </div>
              <div id="signal-source-title" class="signal-node-name">Apple Music</div>
              <div id="signal-source-details" class="signal-node-meta">24-bit / 192.0 kHz ALAC</div>
            </div>
          </div>

          <div class="signal-connector">
            <div class="signal-connector-line"></div>
          </div>

          <!-- Step 2: AMR Engine -->
          <div class="signal-node" id="signal-node-engine">
            <div class="signal-node-dot active"></div>
            <div class="signal-node-main">
              <div class="signal-node-top">
                <span class="signal-node-badge">АУДИОДВИЖОК</span>
                <span class="signal-node-format highlight-green">0.0 dB FS</span>
              </div>
              <div class="signal-node-name">AMR CoreAudio Engine</div>
              <div class="signal-node-meta">Bit-Perfect 100% Lock • Zero DSP • Bypass микшера</div>
            </div>
          </div>

          <div class="signal-connector">
            <div class="signal-connector-line"></div>
          </div>

          <!-- Step 3: Hardware Output DAC -->
          <div class="signal-node" id="signal-node-dac">
            <div class="signal-node-dot active"></div>
            <div class="signal-node-main">
              <div class="signal-node-top">
                <span class="signal-node-badge">ВЫХОДНОЙ ЦАП</span>
                <span id="signal-dac-rate" class="signal-node-format">192.0 кГц</span>
              </div>
              <div id="signal-dac-name" class="signal-node-name">Аудиовыход</div>
              <div id="signal-dac-details" class="signal-node-meta">Прямое подключение macOS CoreAudio</div>
            </div>
            <button id="btn-open-devices" class="btn-signal-action" type="button" title="Сменить устройство вывода">
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M11 5L6 9H2v6h4l5 4V5z"/>
                <path d="M19.07 4.93a10 10 0 0 1 0 14.14M15.54 8.46a5 5 0 0 1 0 7.07"/>
              </svg>
              <span>ЦАП</span>
            </button>
          </div>
        </div>

        <!-- Verified Bit-Perfect Card -->
        <div class="signal-verified-card">
          <div class="signal-verified-icon">
            <svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor">
              <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/>
            </svg>
          </div>
          <div class="signal-verified-info">
            <div class="signal-verified-title">Bit-Perfect Verified</div>
            <div class="signal-verified-desc">Частота ЦАП аппаратно синхронизирована с потоком. Деградация разрядности исключена.</div>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- Audio Output Devices Modal -->
  <div id="devices-modal" class="modal-backdrop hidden" aria-hidden="true">
    <div class="modal-card devices-modal-card">
      <div class="modal-header">
        <div class="modal-title-wrap">
          <h3 class="modal-title">Аудиоустройства вывода</h3>
          <span class="modal-tag">COREAUDIO &amp; DLNA</span>
        </div>
        <button id="btn-close-devices" class="modal-close" type="button" aria-label="Закрыть">&times;</button>
      </div>
      <div class="modal-body">
        <p class="modal-subtitle">Выберите активный ЦАП, аудиовыход macOS или сетевой стример</p>
        <div id="audio-devices-list" class="audio-devices-list">
          <div class="loading-state">Загрузка устройств...</div>
        </div>
      </div>
    </div>
  </div>

  <!-- Mandatory Apple ID Auth Modal -->
  <div id="modal-apple-auth" class="modal-backdrop auth-modal-backdrop hidden" aria-hidden="true" role="dialog" aria-modal="true">
    <div class="modal-card auth-modal-card">
      <div class="auth-modal-logo">
        <svg viewBox="0 0 24 24" width="44" height="44" fill="currentColor">
          <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M15.97 6.37c.62-.75 1.04-1.8 1.01-2.87-.94.04-2.08.63-2.75 1.41-.58.68-1.09 1.76-1.04 2.81 1.05.08 2.16-.57 2.78-1.35z"/>
        </svg>
      </div>
      <h2 class="auth-modal-title">Подключите Apple ID</h2>
      <p class="auth-modal-desc">
        Для работы с каталогом, воспроизведения очередей в iCloud и персональных рекомендаций требуется авторизация в Apple Music.
      </p>
      <div class="auth-modal-features">
        <div class="auth-feature-item">
          <span class="auth-feature-icon">✓</span>
          <span>Bit-Perfect звук в исходном качестве (ALAC / Hi-Res)</span>
        </div>
        <div class="auth-feature-item">
          <span class="auth-feature-icon">✓</span>
          <span>Синхронизация результатов поиска в iCloud-очереди</span>
        </div>
        <div class="auth-feature-item">
          <span class="auth-feature-icon">✓</span>
          <span>Персональная «Моя станция» и музыкальные открытия</span>
        </div>
      </div>
      <div class="auth-modal-actions">
        <button id="btn-auth-modal-login" class="btn-primary auth-btn-login" type="button">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
            <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M15.97 6.37c.62-.75 1.04-1.8 1.01-2.87-.94.04-2.08.63-2.75 1.41-.58.68-1.09 1.76-1.04 2.81 1.05.08 2.16-.57 2.78-1.35z"/>
          </svg>
          <span>Войти через Apple ID</span>
        </button>
      </div>
      <div id="auth-modal-status" class="auth-modal-status hidden">
        <div class="spinner-sm"></div>
        <span>Инициализация MusicKit...</span>
      </div>
    </div>
  </div>

  <!-- Account Diagnostic Modal -->
  <div id="modal-account-diag" class="modal-backdrop hidden" aria-hidden="true" role="dialog" aria-modal="true">
    <div class="modal-card account-diag-modal-card">
      <div class="modal-header">
        <h3 class="modal-title">Apple ID & Медиатека</h3>
        <button id="btn-close-account-diag" class="btn-close-modal" type="button" aria-label="Закрыть">✕</button>
      </div>
      <div class="diag-details-list">
        <div class="diag-detail-item">
          <span class="diag-label">Учетная запись Mac:</span>
          <span class="diag-value" id="diag-val-account">tse.tds@gmail.com</span>
        </div>
        <div class="diag-detail-item">
          <span class="diag-label">Статус синхронизации:</span>
          <span class="diag-value green" id="diag-val-status">Синхронизировано с Mac</span>
        </div>
        <div class="diag-detail-item">
          <span class="diag-label">Регион Apple Music:</span>
          <span class="diag-value" id="diag-val-storefront">US</span>
        </div>
        <div class="diag-detail-item">
          <span class="diag-label">Подписка Apple Music:</span>
          <span class="diag-value green" id="diag-val-sub">Активна</span>
        </div>
        <div class="diag-detail-item">
          <span class="diag-label">Bit-Perfect CoreAudio:</span>
          <span class="diag-value" id="diag-val-dac">Lossless / Hi-Res (100% Volume Lock)</span>
        </div>
      </div>
      <div class="diag-modal-actions">
        <button id="btn-refresh-account-diag" class="btn-secondary" type="button">Проверить заново</button>
        <button id="btn-done-account-diag" class="btn-primary" type="button">Готово</button>
      </div>
    </div>
  </div>

  <!-- Busy / Action Loading Overlay -->
  <div id="busy-overlay" class="busy-overlay hidden" aria-hidden="true" role="status">
    <div class="busy-card">
      <div class="busy-spinner"></div>
      <span id="busy-message" class="busy-text">Загрузка...</span>
    </div>
  </div>

  <script src="/app.js?v=232"></script>
</body>
</html>

"""##

    public static let styleCSS = ##"""
/* ==========================================================================
   Apple Music Remote (AMR) - Ultra-Clean Monochrome Production Design
   Color Palette:
     - Pure OLED Black: #000000
     - Deep Surfaces: #0e0e0e, #161616, #1c1c1e, #1f1f21
     - Precision Borders: #262628, #38383a
     - Monochrome Text: #ffffff (primary), #9e9ea3 (secondary), #5c5c60 (muted)
   ========================================================================== */

:root {
  --bg-pure: #000000;
  --surface-base: #0e0e0e;
  --surface-card: #161616;
  --surface-hover: #1f1f21;
  --surface-active: #2a2a2d;

  --border-subtle: #262628;
  --border-bright: #38383a;

  --text-primary: #ffffff;
  --text-secondary: #9e9ea3;
  --text-muted: #5c5c60;

  --font-stack: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "Helvetica Neue", sans-serif;
  --transition-fast: 0.15s cubic-bezier(0.2, 0.9, 0.4, 1);
  --transition-smooth: 0.25s cubic-bezier(0.2, 0.9, 0.4, 1);

  /* iOS Safe Area Insets with Robust Dynamic Island & Home Indicator Fallbacks */
  --safe-top: env(safe-area-inset-top, 0px);
  --safe-bottom: env(safe-area-inset-bottom, 0px);
  --safe-left: env(safe-area-inset-left, 0px);
  --safe-right: env(safe-area-inset-right, 0px);
}

*, *::before, *::after {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  -webkit-tap-highlight-color: transparent;
  user-select: none;
}

html {
  width: 100%;
  height: 100%;
  margin: 0;
  padding: 0;
  background-color: var(--bg-pure);
  overflow: hidden;
}

body {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  width: 100%;
  height: 100%;
  margin: 0;
  padding: 0;
  background-color: var(--bg-pure);
  color: var(--text-primary);
  font-family: var(--font-stack);
  overflow: hidden;
  overscroll-behavior: none;
  -webkit-text-size-adjust: 100%;
}

button {
  background: none;
  border: none;
  color: inherit;
  font: inherit;
  cursor: pointer;
  outline: none;
  touch-action: manipulation;
  -webkit-tap-highlight-color: transparent;
}

input {
  border: none;
  background: none;
  color: var(--text-primary);
  font: inherit;
  outline: none;
}

/* Scrollbar Stylings */
::-webkit-scrollbar {
  width: 6px;
  height: 6px;
}
::-webkit-scrollbar-track {
  background: transparent;
}
::-webkit-scrollbar-thumb {
  background: var(--border-subtle);
  border-radius: 4px;
}
::-webkit-scrollbar-thumb:hover {
  background: var(--border-bright);
}

.hidden {
  display: none !important;
}

/* ==========================================================================
   Apple TV Style Dynamic Blurred Ambient Gradient Background
   ========================================================================== */

.ambient-backdrop {
  position: fixed;
  top: -20%;
  left: -20%;
  width: 140%;
  height: 140%;
  pointer-events: none;
  overflow: hidden;
  z-index: 0;
  background-color: var(--bg-pure);
  opacity: 0;
  transition: opacity 1.2s cubic-bezier(0.2, 0.9, 0.4, 1);
  will-change: opacity;
}

.ambient-backdrop.active {
  opacity: 1;
}

.ambient-layer {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  opacity: 0;
  transition: opacity 1.5s cubic-bezier(0.2, 0.9, 0.4, 1);
  will-change: opacity;
}

.ambient-layer.visible {
  opacity: 1;
}

.ambient-blob {
  position: absolute;
  border-radius: 50%;
  filter: blur(90px) saturate(150%);
  -webkit-filter: blur(90px) saturate(150%);
  opacity: 0.82;
  transform: translate3d(0, 0, 0);
  will-change: transform;
}

/* 4 organic floating blobs positioned for dynamic mesh diffusion */
.ambient-blob.blob-1 {
  width: 55vw;
  height: 55vw;
  min-width: 450px;
  min-height: 450px;
  top: 15%;
  left: 10%;
  background: var(--blob-1, rgba(60, 30, 90, 0.6));
  animation: ambientFloat1 24s ease-in-out infinite alternate;
}

.ambient-blob.blob-2 {
  width: 60vw;
  height: 60vw;
  min-width: 500px;
  min-height: 500px;
  top: 25%;
  right: 10%;
  background: var(--blob-2, rgba(30, 60, 110, 0.55));
  animation: ambientFloat2 28s ease-in-out infinite alternate;
}

.ambient-blob.blob-3 {
  width: 50vw;
  height: 50vw;
  min-width: 400px;
  min-height: 400px;
  bottom: 15%;
  left: 25%;
  background: var(--blob-3, rgba(90, 40, 70, 0.5));
  animation: ambientFloat3 22s ease-in-out infinite alternate;
}

.ambient-blob.blob-4 {
  width: 45vw;
  height: 45vw;
  min-width: 350px;
  min-height: 350px;
  top: 40%;
  left: 40%;
  background: var(--blob-4, rgba(25, 75, 95, 0.45));
  animation: ambientFloat4 26s ease-in-out infinite alternate;
}

/* Organic drifting keyframes in Apple TV style */
@keyframes ambientFloat1 {
  0% { transform: translate3d(0, 0, 0) scale(1); }
  50% { transform: translate3d(8%, -6%, 0) scale(1.12); }
  100% { transform: translate3d(-6%, 8%, 0) scale(0.95); }
}

@keyframes ambientFloat2 {
  0% { transform: translate3d(0, 0, 0) scale(1); }
  50% { transform: translate3d(-10%, 8%, 0) scale(1.08); }
  100% { transform: translate3d(6%, -8%, 0) scale(0.92); }
}

@keyframes ambientFloat3 {
  0% { transform: translate3d(0, 0, 0) scale(1); }
  50% { transform: translate3d(-8%, -10%, 0) scale(1.15); }
  100% { transform: translate3d(10%, 6%, 0) scale(0.9); }
}

@keyframes ambientFloat4 {
  0% { transform: translate3d(0, 0, 0) scale(1); }
  50% { transform: translate3d(10%, 10%, 0) scale(1.1); }
  100% { transform: translate3d(-10%, -6%, 0) scale(0.95); }
}

@media (prefers-reduced-motion: reduce) {
  .ambient-blob {
    animation: none !important;
  }
}

/* Apple TV Vignette / Scrim Overlay to protect OLED black, contrast & readability */
.ambient-vignette {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  background: 
    radial-gradient(ellipse at 50% 35%, rgba(0, 0, 0, 0.28) 0%, rgba(0, 0, 0, 0.72) 65%, #000000 100%),
    linear-gradient(to bottom, rgba(0, 0, 0, 0.2) 0%, rgba(0, 0, 0, 0.45) 60%, rgba(0, 0, 0, 0.9) 100%);
  pointer-events: none;
}

/* ==========================================================================
   Main Application Layout
   ========================================================================== */

.app-layout {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  width: 100%;
  height: 100%;
  display: flex;
  background: transparent;
  overflow: hidden;
  z-index: 1;
}

/* Desktop Dual Column: >= 768px */
@media (min-width: 768px) {
  .app-layout {
    flex-direction: row;
  }

  /* Left Panel: Fixed Sticky Player */
  .player-panel {
    width: 420px;
    min-width: 380px;
    max-width: 460px;
    height: 100%;
    border-right: 1px solid rgba(255, 255, 255, 0.08);
    background: rgba(0, 0, 0, 0.35);
    backdrop-filter: blur(24px);
    -webkit-backdrop-filter: blur(24px);
    display: flex !important;
    flex-direction: column;
    padding: calc(var(--safe-top) + 24px) 28px calc(var(--safe-bottom) + 24px) 28px;
    overflow-y: auto;
    z-index: 10;
  }

  /* Right Panel: Tab Content Wrapper */
  .content-panel-wrapper {
    flex: 1;
    height: 100%;
    display: flex;
    flex-direction: column;
    background: rgba(10, 10, 10, 0.72);
    backdrop-filter: blur(40px);
    -webkit-backdrop-filter: blur(40px);
    overflow: hidden;
    position: relative;
  }

  .desktop-nav-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: calc(var(--safe-top) + 20px) 32px 16px 32px;
    background: var(--surface-base);
    border-bottom: 1px solid var(--border-subtle);
    z-index: 5;
  }

  .desktop-nav-tabs {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .desktop-dac-badge {
    display: none !important;
  }

  .mobile-top-bar {
    display: none !important;
  }

  .nav-tab-btn {
    padding: 8px 18px;
    min-height: 44px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border-radius: 20px;
    font-size: 14px;
    font-weight: 500;
    color: var(--text-secondary);
    background: transparent;
    transition: all var(--transition-fast);
  }

  .nav-tab-btn:hover {
    color: var(--text-primary);
    background: var(--surface-hover);
  }

  .nav-tab-btn.active {
    color: var(--text-primary);
    background: var(--surface-card);
    border: 1px solid var(--border-subtle);
  }

  /* Content views on Desktop */
  .content-view {
    flex: 1;
    display: none;
    flex-direction: column;
    overflow: hidden;
    padding: 24px 32px;
    animation: viewFadeIn 0.2s cubic-bezier(0.2, 0.9, 0.4, 1);
  }

  .content-view.active {
    display: flex;
  }

  /* Mini-player and bottom bar hidden on Desktop */
  .mini-player,
  .bottom-tab-bar {
    display: none !important;
  }
}

/* Mobile Single Column: < 768px */
@media (max-width: 767px) {
  .app-layout {
    flex-direction: column;
  }

  .desktop-nav-header {
    display: none !important;
  }

  .mobile-top-bar {
    display: flex !important;
    align-items: center;
    justify-content: space-between;
    padding: calc(max(var(--safe-top), env(safe-area-inset-top, 0px), 44px) + 8px) calc(var(--safe-left) + 20px) 12px calc(var(--safe-right) + 20px);
    background: var(--bg-pure);
    border-bottom: 1px solid var(--border-subtle);
    flex-shrink: 0;
    z-index: 10;
  }

  .mobile-dac-badge {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 5px 12px;
    height: 32px;
    border-radius: 16px;
    background: var(--surface-card);
    border: 1px solid var(--border-subtle);
    color: var(--text-secondary);
    font-size: 11px;
    font-weight: 500;
    cursor: pointer;
    transition: all var(--transition-fast);
  }

  .mobile-dac-badge:hover,
  .mobile-dac-badge:active {
    color: var(--text-primary);
    background: var(--surface-hover);
    border-color: var(--border-bright);
  }

  .player-panel {
    display: none;
    width: 100%;
    height: 100%;
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: transparent;
    flex-direction: column;
    padding-top: calc(max(var(--safe-top), env(safe-area-inset-top, 0px), 54px) + 16px);
    padding-left: calc(var(--safe-left) + 20px);
    padding-right: calc(var(--safe-right) + 20px);
    padding-bottom: 70px;
    overflow-y: auto;
    z-index: 20;
    overscroll-behavior-y: contain;
    animation: viewFadeIn 0.2s cubic-bezier(0.2, 0.9, 0.4, 1);
  }

  .player-panel.active {
    display: flex;
  }

  .player-panel.active ~ .content-panel-wrapper {
    display: none;
  }

  .content-panel-wrapper {
    flex: 1;
    width: 100%;
    height: 100%;
    display: flex;
    flex-direction: column;
    background: var(--bg-pure);
    overflow: hidden;
    position: relative;
  }

  .content-view {
    display: none;
    flex: 1;
    width: 100%;
    height: 100%;
    flex-direction: column;
    overflow: hidden;
    padding-top: calc(max(var(--safe-top), env(safe-area-inset-top, 0px), 54px) + 16px);
    padding-left: calc(var(--safe-left) + 16px);
    padding-right: calc(var(--safe-right) + 16px);
    padding-bottom: 0;
    animation: viewFadeIn 0.2s cubic-bezier(0.2, 0.9, 0.4, 1);
  }

  .content-view.active {
    display: flex;
  }
}

@keyframes viewFadeIn {
  from {
    opacity: 0;
    transform: translateY(3px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

/* ==========================================================================
   Now Playing Player Panel Components
   ========================================================================== */

.player-top-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 16px;
  flex-shrink: 0;
}

.brand-pill {
  display: flex;
  align-items: center;
  gap: 8px;
}

.brand-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: #ffffff;
  box-shadow: 0 0 8px rgba(255, 255, 255, 0.7);
}

.brand-title {
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 1.5px;
  color: var(--text-secondary);
  text-transform: uppercase;
}

.brand-ver {
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.5px;
  color: var(--text-muted);
  margin-left: 4px;
  text-transform: none;
  background: rgba(255, 255, 255, 0.08);
  padding: 1px 6px;
  border-radius: 4px;
  border: 1px solid rgba(255, 255, 255, 0.08);
}

.quality-badge {
  display: flex;
  align-items: center;
  gap: 6px;
  min-height: 36px;
  padding: 6px 12px;
  border-radius: 8px;
  background: var(--surface-card);
  border: 1px solid var(--border-subtle);
  color: var(--text-secondary);
  font-size: 10.5px;
  font-weight: 700;
  letter-spacing: 0.8px;
  text-transform: uppercase;
  transition: all var(--transition-fast);
  touch-action: manipulation;
}

.quality-badge:hover,
.quality-badge:active {
  background: var(--surface-hover);
  border-color: var(--border-bright);
  color: var(--text-primary);
}

.icon-dac {
  width: 13px;
  height: 13px;
}

/* Artwork Component */
.artwork-container {
  display: flex;
  align-items: center;
  justify-content: center;
  margin-bottom: 16px;
  flex: 1 1 auto;
  min-height: 0;
  touch-action: pan-y;
  user-select: none;
  -webkit-user-select: none;
  cursor: grab;
}

.artwork-container:active {
  cursor: grabbing;
}

.artwork-wrapper {
  position: relative;
  width: 100%;
  max-width: min(380px, 86vw, 42vh);
  aspect-ratio: 1 / 1;
  border-radius: 16px;
  overflow: hidden;
  box-shadow: 0 12px 36px rgba(0, 0, 0, 0.8), 0 0 0 1px var(--border-subtle);
  background: var(--surface-card);
  flex-shrink: 1;
  will-change: transform, opacity;
  transition: transform 0.25s cubic-bezier(0.2, 0.9, 0.4, 1), opacity 0.25s ease;
}

.player-art {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
  pointer-events: none;
  transition: opacity 0.25s ease;
}

.art-placeholder {
  width: 100%;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--surface-card);
  color: var(--text-muted);
}

/* Track Metadata */
.track-meta {
  margin-bottom: 20px;
  flex-shrink: 0;
}

.track-title-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 4px;
}

.track-title {
  font-size: 20px;
  font-weight: 700;
  line-height: 1.25;
  color: var(--text-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  flex: 1;
}

.track-artist {
  font-size: 15px;
  font-weight: 500;
  color: var(--text-secondary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  margin-bottom: 2px;
}

.track-album {
  font-size: 13px;
  font-weight: 400;
  color: var(--text-muted);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

/* Track Actions Group */
.track-actions-group {
  display: flex;
  align-items: center;
  gap: 4px;
  flex-shrink: 0;
}

/* Station Creation Button - 44x44px touch target */
.btn-station {
  width: 44px;
  height: 44px;
  min-width: 44px;
  min-height: 44px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
  border-radius: 50%;
  transition: all var(--transition-fast);
  touch-action: manipulation;
}

.btn-station:hover {
  color: var(--text-primary);
  background: var(--surface-hover);
}

.btn-station:active {
  transform: scale(0.92);
}

/* Favorite Button - 44x44px touch target */
@keyframes favPop {
  0% { transform: scale(1); }
  45% { transform: scale(1.35); }
  75% { transform: scale(0.92); }
  100% { transform: scale(1); }
}

.btn-fav {
  width: 44px;
  height: 44px;
  min-width: 44px;
  min-height: 44px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
  border-radius: 50%;
  transition: all var(--transition-fast);
  touch-action: manipulation;
}

.btn-fav:hover {
  color: var(--text-primary);
  background: var(--surface-hover);
}

.btn-fav.active {
  color: #ffffff;
}

.btn-fav.active svg {
  fill: #ffffff;
  stroke: #ffffff;
  animation: favPop 0.35s cubic-bezier(0.2, 0.9, 0.4, 1);
}

.mini-btn-fav {
  color: var(--text-muted);
  width: 40px;
  height: 40px;
  min-width: 40px;
  min-height: 40px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 50%;
  transition: all var(--transition-fast);
  touch-action: manipulation;
}

.mini-btn-fav:hover {
  color: var(--text-primary);
  background: var(--surface-hover);
}

.mini-btn-fav.active {
  color: #ffffff;
}

.mini-btn-fav.active svg {
  fill: #ffffff;
  stroke: #ffffff;
  animation: favPop 0.35s cubic-bezier(0.2, 0.9, 0.4, 1);
}

/* Custom Monochrome Scrubber */
.scrubber-section {
  margin-bottom: 24px;
  flex-shrink: 0;
}

.scrubber-bar-container {
  position: relative;
  width: 100%;
  height: 36px; /* Expanded 36px touch zone */
  display: flex;
  align-items: center;
  cursor: pointer;
  touch-action: none;
}

.scrubber-track {
  position: relative;
  width: 100%;
  height: 4px;
  background: var(--border-subtle);
  border-radius: 2px;
  pointer-events: none;
  overflow: visible;
  transition: height var(--transition-fast);
}

.scrubber-bar-container:hover .scrubber-track,
.scrubber-bar-container:active .scrubber-track {
  height: 6px;
}

.scrubber-fill {
  position: absolute;
  top: 0;
  left: 0;
  height: 100%;
  background: #ffffff;
  border-radius: 2px;
  width: 0%;
  transition: width 0.05s linear;
}

.scrubber-thumb {
  position: absolute;
  top: 50%;
  left: 0%;
  width: 14px;
  height: 14px;
  border-radius: 50%;
  background: #ffffff;
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.6);
  transform: translate(-50%, -50%) scale(0.9);
  transition: transform var(--transition-fast), left 0.05s linear;
  pointer-events: none;
}

.scrubber-bar-container:hover .scrubber-thumb,
.scrubber-bar-container:active .scrubber-thumb {
  transform: translate(-50%, -50%) scale(1.2);
}

#scrubber-input {
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  opacity: 0;
  cursor: pointer;
  margin: 0;
  z-index: 5;
  touch-action: none;
}

.scrubber-timestamps {
  display: flex;
  justify-content: space-between;
  margin-top: 2px;
}

.time-label {
  font-size: 11.5px;
  font-weight: 500;
  color: var(--text-muted);
  font-variant-numeric: tabular-nums;
}

/* Primary Transport Controls - Minimum 44x44px for All Buttons */
.transport-controls {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 24px;
  padding: 0 4px;
  flex-shrink: 0;
}

.btn-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 50%;
  transition: all var(--transition-fast);
  position: relative;
  touch-action: manipulation;
  -webkit-tap-highlight-color: transparent;
  cursor: pointer;
}

.btn-icon svg {
  pointer-events: none;
}

.btn-icon:active {
  transform: scale(0.92);
}

/* Shuffle & Repeat: Exactly 44x44px Touch Targets */
.control-sub {
  width: 44px;
  height: 44px;
  min-width: 44px;
  min-height: 44px;
  color: var(--text-muted);
}

.control-sub:hover {
  color: var(--text-primary);
  background: var(--surface-hover);
}

.control-sub.active {
  color: var(--text-primary);
}

.repeat-one-indicator {
  position: absolute;
  top: 8px;
  right: 8px;
  font-size: 9px;
  font-weight: 800;
  color: var(--text-primary);
}

/* Skip Previous & Next: 48x48px Touch Targets */
.control-skip {
  width: 48px;
  height: 48px;
  min-width: 48px;
  min-height: 48px;
  color: var(--text-primary);
}

.control-skip:hover {
  background: var(--surface-hover);
}

/* Main Play/Pause: 64x64px Touch Target */
.control-play-main {
  width: 64px;
  height: 64px;
  min-width: 64px;
  min-height: 64px;
  background: #ffffff;
  color: #000000;
  box-shadow: 0 4px 16px rgba(255, 255, 255, 0.15);
}

.control-play-main:hover {
  background: #f0f0f2;
}

.control-play-main:active {
  transform: scale(0.94);
  background: #e5e5e7;
}

.svg-icon {
  width: 20px;
  height: 20px;
}

.svg-icon-play {
  width: 26px;
  height: 26px;
  transform: translateX(1.5px);
}

.svg-icon-pause {
  width: 24px;
  height: 24px;
}

/* Bottom DAC Notice (Hidden per user request) */
.player-bottom-notice {
  display: none !important;
}

@media (max-width: 767px) and (min-height: 800px) {
  .player-panel {
    justify-content: space-evenly;
  }
  .artwork-wrapper {
    max-width: min(400px, 88vw, 45vh);
  }
}

.dac-status-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: #34c759;
}

.dac-notice-text {
  font-size: 11px;
  font-weight: 500;
  color: var(--text-muted);
  letter-spacing: 0.2px;
}

/* ==========================================================================
   Queue, Library, and Search Common Elements
   ========================================================================== */

.section-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 18px;
}

.section-title {
  font-size: 24px;
  font-weight: 700;
  letter-spacing: -0.4px;
  color: var(--text-primary);
}

.section-subtitle {
  font-size: 13px;
  color: var(--text-secondary);
  margin-top: 2px;
}

.btn-ghost {
  min-height: 44px;
  padding: 8px 16px;
  font-size: 13px;
  font-weight: 500;
  color: var(--text-secondary);
  border-radius: 10px;
  border: 1px solid var(--border-subtle);
  background: var(--surface-card);
  transition: all var(--transition-fast);
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

.btn-ghost:hover {
  background: var(--surface-hover);
  color: var(--text-primary);
}

.scroll-pane {
  flex: 1;
  overflow-y: auto;
  overflow-x: hidden;
  padding-right: 4px;
  -webkit-overflow-scrolling: touch;
  overscroll-behavior-y: contain;
}

/* Ensure mobile scroll content has clearance for docked mini-player + bottom tab bar */
@media (max-width: 767px) {
  .scroll-pane {
    padding-bottom: calc(var(--safe-bottom) + 140px);
  }
}

/* Empty & Loading States */
.empty-state,
.loading-state,
.search-placeholder {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 12px;
  padding: 48px 16px;
  color: var(--text-muted);
  font-size: 14px;
  text-align: center;
}

.loading-state::before {
  content: "";
  display: block;
  width: 28px;
  height: 28px;
  border: 2.5px solid rgba(255, 255, 255, 0.2);
  border-top-color: #ffffff;
  border-radius: 50%;
  animation: amr-spin 0.65s linear infinite;
  margin-bottom: 4px;
}

/* Track List Elements */
.track-list {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.track-row {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 8px 12px;
  min-height: 54px;
  border-radius: 10px;
  cursor: pointer;
  transition: background var(--transition-fast);
  touch-action: manipulation;
}

.track-row:hover {
  background: var(--surface-hover);
}

.track-row:active {
  background: var(--surface-active);
}

.track-row.now-playing-row {
  background: var(--surface-card);
  border: 1px solid var(--border-subtle);
}

.track-thumb {
  width: 44px;
  height: 44px;
  border-radius: 8px;
  object-fit: cover;
  background: var(--surface-card);
  flex-shrink: 0;
}

.artist-thumb {
  border-radius: 50% !important;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--surface-hover);
  color: var(--text-secondary);
}

.station-art-fallback {
  width: 100%;
  height: 100%;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 6px;
  padding: 12px;
  text-align: center;
}

.station-art-fallback svg {
  width: 36px;
  height: 36px;
  opacity: 0.9;
}

.station-art-fallback-title {
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.5px;
  text-transform: uppercase;
  color: #ffffff;
  text-shadow: 0 1px 4px rgba(0, 0, 0, 0.6);
  max-width: 100%;
  padding: 0 6px;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
  text-overflow: ellipsis;
  word-break: break-word;
  text-align: center;
  box-sizing: border-box;
}

.track-index-num {
  width: 24px;
  font-size: 13px;
  font-weight: 500;
  color: var(--text-muted);
  text-align: center;
  flex-shrink: 0;
}

.track-details {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.track-row-title {
  font-size: 14px;
  font-weight: 600;
  color: var(--text-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.track-row-artist {
  font-size: 12px;
  color: var(--text-secondary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.track-row-dur {
  font-size: 12px;
  color: var(--text-muted);
  font-variant-numeric: tabular-nums;
  flex-shrink: 0;
}

/* ==========================================================================
   Queue Specifics
   ========================================================================== */

.queue-group {
  margin-bottom: 24px;
}

.group-title {
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 1px;
  color: var(--text-muted);
  text-transform: uppercase;
  margin-bottom: 10px;
  padding-left: 12px;
}

/* ==========================================================================
   Library / Playlists Specifics - Responsive 2-Column on Mobile
   ========================================================================== */

.library-pane {
  flex: 1;
  display: flex;
  flex-direction: column;
  height: 100%;
  overflow: hidden;
}

/* Desktop Playlists Grid: min 170px auto-fill */
@media (min-width: 768px) {
  .playlists-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(170px, 1fr));
    gap: 18px;
    padding-bottom: 40px;
  }
}

/* Mobile Playlists Grid: Crisp 2-Column on 375px - 430px screens */
@media (max-width: 767px) {
  .playlists-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 12px;
    padding-bottom: calc(var(--safe-bottom) + 140px);
  }

  .playlist-card {
    padding: 8px !important;
    border-radius: 14px !important;
    background: var(--surface-card);
    border: 1px solid var(--border-subtle);
  }

  .playlist-card-art {
    margin-bottom: 8px !important;
    border-radius: 10px !important;
  }

  .playlist-card-title {
    font-size: 13.5px !important;
    margin-bottom: 2px !important;
  }

  .playlist-card-count {
    font-size: 11.5px !important;
  }
}

.playlist-card {
  display: flex;
  flex-direction: column;
  cursor: pointer;
  border-radius: 12px;
  padding: 10px;
  background: transparent;
  transition: all var(--transition-fast);
  touch-action: manipulation;
  min-width: 0;
  overflow: hidden;
}

.playlist-card:hover {
  background: var(--surface-hover);
}

.playlist-card:active {
  transform: scale(0.97);
}

.playlist-card-art {
  width: 100%;
  aspect-ratio: 1 / 1;
  border-radius: 12px;
  object-fit: cover;
  background: var(--surface-card);
  box-shadow: 0 4px 14px rgba(0, 0, 0, 0.5);
  margin-bottom: 10px;
}

.playlist-card-title {
  font-size: 14px;
  font-weight: 600;
  color: var(--text-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 100%;
  min-width: 0;
  width: 100%;
  box-sizing: border-box;
  margin-bottom: 2px;
}

.playlist-card-count {
  font-size: 12px;
  color: var(--text-secondary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 100%;
  min-width: 0;
  width: 100%;
  box-sizing: border-box;
}

/* Playlist Detail Drill-down */
.detail-header {
  margin-bottom: 16px;
}

.btn-back {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-height: 44px;
  font-size: 14px;
  font-weight: 500;
  color: var(--text-secondary);
  padding: 6px 12px;
  border-radius: 10px;
  transition: all var(--transition-fast);
  touch-action: manipulation;
}

.btn-back:hover {
  color: var(--text-primary);
  background: var(--surface-hover);
}

.detail-hero {
  display: flex;
  gap: 20px;
  align-items: flex-end;
  margin-bottom: 24px;
  padding-bottom: 20px;
  border-bottom: 1px solid var(--border-subtle);
}

@media (max-width: 480px) {
  .detail-hero {
    gap: 14px;
    align-items: center;
  }
  .detail-art {
    width: 110px !important;
    height: 110px !important;
    border-radius: 12px !important;
  }
  .detail-title {
    font-size: 19px !important;
  }
  .detail-actions {
    flex-wrap: wrap;
    gap: 8px;
  }
  .btn-primary-action,
  .btn-secondary-action {
    padding: 8px 14px !important;
    font-size: 12px !important;
    min-height: 44px !important;
  }
}

.detail-art {
  width: 140px;
  height: 140px;
  border-radius: 14px;
  object-fit: cover;
  background: var(--surface-card);
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.6);
  flex-shrink: 0;
}

.detail-info {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
}

.detail-badge {
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 1px;
  color: var(--text-muted);
  text-transform: uppercase;
  margin-bottom: 4px;
}

.detail-title {
  font-size: 22px;
  font-weight: 700;
  color: var(--text-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  margin-bottom: 4px;
}

.detail-meta {
  font-size: 13px;
  color: var(--text-secondary);
  margin-bottom: 16px;
}

.detail-actions {
  display: flex;
  gap: 10px;
}

.btn-primary-action,
.btn-secondary-action {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  padding: 8px 18px;
  min-height: 44px;
  border-radius: 22px;
  font-size: 13px;
  font-weight: 600;
  transition: all var(--transition-fast);
  touch-action: manipulation;
}

.btn-primary-action {
  background: #ffffff;
  color: #000000;
}

.btn-primary-action:hover {
  background: #f0f0f2;
}

.btn-secondary-action {
  background: var(--surface-card);
  color: var(--text-primary);
  border: 1px solid var(--border-subtle);
}

.btn-secondary-action:hover {
  background: var(--surface-hover);
}

/* ==========================================================================
   Search Specifics
   ========================================================================== */

.search-header-wrap {
  margin-bottom: 12px;
}

.search-input-box {
  position: relative;
  width: 100%;
  display: flex;
  align-items: center;
  background: var(--surface-card);
  border: 1px solid var(--border-subtle);
  border-radius: 12px;
  padding: 0 14px;
  transition: border-color var(--transition-fast);
}

.search-input-box:focus-within {
  border-color: var(--border-bright);
}

.search-icon {
  width: 18px;
  height: 18px;
  color: var(--text-muted);
  margin-right: 10px;
  flex-shrink: 0;
}

#search-input {
  width: 100%;
  height: 44px;
  font-size: 14.5px;
  color: var(--text-primary);
}

#search-input::placeholder {
  color: var(--text-muted);
}

.search-clear {
  width: 44px;
  height: 44px;
  min-width: 44px;
  min-height: 44px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 22px;
  line-height: 1;
  color: var(--text-muted);
  cursor: pointer;
  touch-action: manipulation;
}

.search-filters {
  display: flex;
  gap: 8px;
  margin-bottom: 16px;
  overflow-x: auto;
  padding-bottom: 4px;
  -webkit-overflow-scrolling: touch;
}

.filter-chip {
  padding: 8px 16px;
  min-height: 38px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 19px;
  font-size: 12.5px;
  font-weight: 500;
  color: var(--text-secondary);
  background: var(--surface-card);
  border: 1px solid var(--border-subtle);
  white-space: nowrap;
  transition: all var(--transition-fast);
  touch-action: manipulation;
}

.filter-chip.active {
  background: #ffffff;
  color: #000000;
  border-color: #ffffff;
}

.search-header-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin: 16px 8px 10px 12px;
}

.search-section-title {
  font-size: 12px;
  font-weight: 700;
  letter-spacing: 0.8px;
  color: var(--text-muted);
  text-transform: uppercase;
  margin: 0;
}

.search-actions-bar {
  display: flex;
  align-items: center;
  gap: 8px;
}

.btn-search-action {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 6px 12px;
  min-height: 32px;
  border-radius: 16px;
  font-size: 12px;
  font-weight: 600;
  transition: all var(--transition-fast);
  touch-action: manipulation;
}

.btn-search-play-all {
  background: #ffffff;
  color: #000000;
}

.btn-search-play-all:hover {
  background: #f0f0f2;
}

.btn-search-shuffle {
  background: var(--surface-card);
  color: var(--text-primary);
  border: 1px solid var(--border-subtle);
}

.btn-search-shuffle:hover {
  background: var(--surface-hover);
}

.btn-search-load-more {
  display: block;
  width: 100%;
  padding: 10px 16px;
  margin: 10px 0 20px 0;
  border-radius: 12px;
  background: var(--surface-card);
  color: var(--text-primary);
  border: 1px solid var(--border-subtle);
  font-size: 13px;
  font-weight: 600;
  text-align: center;
  cursor: pointer;
  transition: all var(--transition-fast);
}

.btn-search-load-more:hover {
  background: var(--surface-hover);
  border-color: var(--border-hover);
}

.btn-search-load-more:disabled {
  opacity: 0.6;
  cursor: default;
}

.track-row-title-wrap {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}

.badge-library {
  display: inline-flex;
  align-items: center;
  font-size: 9px;
  font-weight: 700;
  letter-spacing: 0.6px;
  color: var(--text-secondary);
  background: var(--surface-hover);
  border: 1px solid var(--border-subtle);
  border-radius: 4px;
  padding: 1px 6px;
  line-height: 1.3;
  flex-shrink: 0;
  text-transform: uppercase;
}

/* ==========================================================================
   Trends & Recommendations Specifics
   ========================================================================== */

.trends-header,
.home-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 12px;
  margin-bottom: 20px;
}

.main-home-title {
  font-size: 30px;
  font-weight: 800;
  color: #ffffff;
  letter-spacing: -0.6px;
  margin: 0;
  line-height: 1.15;
}

/* Home Account Card */
.home-account-card {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  background: var(--surface-card);
  border: 1px solid var(--border-subtle);
  border-radius: 14px;
  padding: 14px 18px;
  margin-bottom: 24px;
  transition: border-color var(--transition-fast), background var(--transition-fast);
}

.home-account-card:hover {
  border-color: var(--border-focus);
}

.account-card-left {
  display: flex;
  align-items: center;
  gap: 14px;
  min-width: 0;
  flex: 1;
}

.account-card-avatar {
  position: relative;
  width: 40px;
  height: 40px;
  border-radius: 10px;
  background: var(--surface-card-subtle);
  border: 1px solid var(--border-subtle);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.apple-logo-icon {
  font-size: 20px;
  color: var(--text-primary);
  line-height: 1;
}

.account-status-dot {
  position: absolute;
  bottom: -2px;
  right: -2px;
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: #30d158;
  border: 2px solid var(--surface-card);
  box-shadow: 0 0 6px rgba(48, 209, 88, 0.4);
}

.account-status-dot.error {
  background: #ff453a;
  box-shadow: 0 0 6px rgba(255, 69, 58, 0.4);
}

.account-card-info {
  display: flex;
  flex-direction: column;
  gap: 3px;
  min-width: 0;
  flex: 1;
}

.account-card-email-row {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}

.account-email {
  font-size: 14px;
  font-weight: 600;
  color: var(--text-primary);
  letter-spacing: -0.2px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.account-sync-badge {
  font-size: 9.5px;
  font-weight: 700;
  letter-spacing: 0.6px;
  text-transform: uppercase;
  color: #30d158;
  background: rgba(48, 209, 88, 0.12);
  border: 1px solid rgba(48, 209, 88, 0.25);
  border-radius: 6px;
  padding: 2px 7px;
  white-space: nowrap;
}

.account-sync-badge.error {
  color: #ff453a;
  background: rgba(255, 69, 58, 0.12);
  border-color: rgba(255, 69, 58, 0.25);
}

.account-card-subtext {
  font-size: 12px;
  color: var(--text-secondary);
  line-height: 1.35;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.account-card-actions {
  flex-shrink: 0;
}

.btn-account-diag {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 7px 12px;
  font-size: 12px;
  font-weight: 500;
  color: var(--text-secondary);
  background: var(--surface-card-subtle);
  border: 1px solid var(--border-subtle);
  border-radius: 8px;
  cursor: pointer;
  transition: all var(--transition-fast);
}

.btn-account-diag:hover {
  color: var(--text-primary);
  border-color: var(--border-focus);
  background: var(--surface-hover);
}

@media (max-width: 480px) {
  .home-account-card {
    padding: 10px 12px;
    gap: 10px;
    margin-bottom: 20px;
  }
  .account-card-left {
    gap: 10px;
  }
  .account-card-avatar {
    width: 34px;
    height: 34px;
    border-radius: 8px;
  }
  .apple-logo-icon {
    font-size: 17px;
  }
  .account-email {
    font-size: 13px;
  }
  .account-sync-badge {
    font-size: 8.5px;
    padding: 1.5px 5px;
  }
  .account-card-subtext {
    font-size: 11px;
  }
  .btn-account-diag {
    padding: 5px 8px;
    font-size: 11px;
    gap: 2px;
  }
}

/* Diagnostic Details Modal */
.account-diag-modal-card {
  max-width: 460px;
  width: 90%;
}

.diag-details-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
  margin: 18px 0;
}

.diag-detail-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
  padding: 10px 14px;
  background: var(--surface-card-subtle);
  border-radius: 8px;
  border: 1px solid var(--border-subtle);
  font-size: 13px;
}

.diag-label {
  color: var(--text-secondary);
  font-size: 12px;
}

.diag-value {
  color: var(--text-primary);
  font-weight: 600;
  font-size: 13px;
  text-align: right;
}

.diag-value.green {
  color: #30d158;
}

.diag-value.red {
  color: #ff453a;
}

.diag-modal-actions {
  display: flex;
  gap: 10px;
  justify-content: flex-end;
  margin-top: 18px;
}

/* Home Section Layout */
.home-section,
.trends-group {
  margin-bottom: 34px;
}

.home-section-title {
  font-size: 21px;
  font-weight: 700;
  color: #ffffff;
  letter-spacing: -0.3px;
  margin: 0;
  line-height: 1.25;
}

.home-section-header-link {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  margin-bottom: 12px;
  cursor: pointer;
  user-select: none;
  transition: opacity var(--transition-fast);
}

.home-section-header-link:hover {
  opacity: 0.85;
}

.home-chevron {
  font-size: 22px;
  font-weight: 400;
  color: var(--text-muted);
  line-height: 1;
  transition: color var(--transition-fast), transform var(--transition-fast);
  margin-top: -1px;
}

.home-section-header-link:hover .home-chevron {
  color: #ffffff;
  transform: translateX(2px);
}

/* Hero Carousel (Подборка лучших) */
.home-hero-carousel {
  display: flex;
  gap: 16px;
  overflow-x: auto;
  scroll-snap-type: x mandatory;
  padding: 4px 2px 14px 2px;
  -webkit-overflow-scrolling: touch;
  scrollbar-width: none;
}

.home-hero-carousel::-webkit-scrollbar {
  display: none;
}

.hero-card {
  width: 260px;
  min-width: 260px;
  flex-shrink: 0;
  scroll-snap-align: start;
  border-radius: 12px;
  position: relative;
  cursor: pointer;
  transition: transform 0.2s cubic-bezier(0.16, 1, 0.3, 1);
  display: flex;
  flex-direction: column;
  user-select: none;
  background: transparent;
  padding: 0;
}

@media (max-width: 767px) {
  .hero-card {
    width: 240px;
    min-width: 240px;
    max-width: 280px;
  }
}

.hero-card:hover {
  transform: translateY(-2px);
}

.hero-card:active {
  transform: scale(0.985);
}

.hero-card-header {
  display: flex;
  flex-direction: column;
  gap: 2px;
  margin-bottom: 10px;
  min-height: 52px;
  max-width: 100%;
  min-width: 0;
  width: 100%;
  overflow: hidden;
  box-sizing: border-box;
}

.hero-tag {
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.6px;
  color: #8e8e93;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 100%;
  min-width: 0;
  width: 100%;
  box-sizing: border-box;
}

.hero-title {
  font-size: 17px;
  font-weight: 700;
  color: #ffffff;
  line-height: 1.25;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 100%;
  min-width: 0;
  width: 100%;
  box-sizing: border-box;
}

.hero-sub {
  font-size: 13px;
  color: #aeaeb2;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 100%;
  min-width: 0;
  width: 100%;
  box-sizing: border-box;
}

.hero-card-media {
  position: relative;
  width: 100%;
  aspect-ratio: 1 / 1;
  height: auto;
  border-radius: 12px;
  overflow: hidden;
  background: #1c1c1e;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.45);
}

.hero-art-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
  transition: transform 0.3s cubic-bezier(0.16, 1, 0.3, 1);
}

.hero-card:hover .hero-art-img {
  transform: scale(1.03);
}

.hero-art-gradient {
  width: 100%;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
}

.hero-art-fallback {
  width: 100%;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #242426;
  color: #636366;
}

.hero-play-btn {
  position: absolute;
  right: 14px;
  bottom: 14px;
  width: 44px;
  height: 44px;
  border-radius: 50%;
  background: rgba(255, 255, 255, 0.95);
  color: #000000;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.5);
  opacity: 0;
  transform: scale(0.85);
  transition: opacity 0.2s cubic-bezier(0.16, 1, 0.3, 1), transform 0.2s cubic-bezier(0.16, 1, 0.3, 1), background 0.15s;
  pointer-events: none;
}

.hero-play-btn svg {
  margin-left: 2px;
}

.hero-card:hover .hero-play-btn,
.hero-card:focus .hero-play-btn {
  opacity: 1;
  transform: scale(1);
}

@media (max-width: 767px) {
  .hero-play-btn {
    opacity: 0.9;
    transform: scale(0.9);
  }
}

/* Horizontal Scrolling Carousel Row */
.home-carousel-row {
  display: flex;
  gap: 15px;
  overflow-x: auto;
  scroll-snap-type: x mandatory;
  padding: 4px 2px 14px 2px;
  -webkit-overflow-scrolling: touch;
  scrollbar-width: none;
}

.home-carousel-row::-webkit-scrollbar {
  display: none;
}

/* Stations Tiled Grid (Плитка) */
.home-stations-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
  gap: 14px;
  padding: 4px 2px 14px 2px;
}

.home-stations-grid .media-card,
.home-stations-grid .station-card {
  width: 100%;
  min-width: 0;
}

@media (max-width: 767px) {
  .home-stations-grid {
    grid-template-columns: repeat(2, 1fr);
    gap: 12px;
  }
}

.detail-header-compact {
  padding: 12px 0 20px 0;
  border-bottom: 1px solid var(--border-subtle);
  margin-bottom: 16px;
}

.detail-info-full .detail-title {
  font-size: 22px;
  font-weight: 700;
  color: var(--text-primary);
  margin: 4px 0 2px 0;
}

#recent-detail-pane .detail-info-full .detail-meta {
  margin-bottom: 16px;
}

#recent-detail-pane .detail-actions {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}

#recent-detail-pane .btn-primary-action,
#recent-detail-pane .btn-secondary-action {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  min-height: 42px;
  padding: 8px 22px;
  border-radius: 21px;
  font-size: 13px;
  font-weight: 600;
  letter-spacing: -0.1px;
  transition: all var(--transition-fast);
  touch-action: manipulation;
  cursor: pointer;
}

#recent-detail-pane .btn-primary-action {
  background: #ffffff;
  color: #000000;
  border: 1px solid #ffffff;
}

#recent-detail-pane .btn-primary-action:hover {
  background: #ebebeb;
  border-color: #ebebeb;
  transform: translateY(-1px);
}

#recent-detail-pane .btn-primary-action:active {
  transform: scale(0.97);
  opacity: 0.9;
}

#recent-detail-pane .btn-secondary-action {
  background: var(--surface-card);
  color: var(--text-primary);
  border: 1px solid var(--border-subtle);
}

#recent-detail-pane .btn-secondary-action:hover {
  background: var(--surface-hover);
  border-color: var(--border-bright);
  transform: translateY(-1px);
}

#recent-detail-pane .btn-secondary-action:active {
  transform: scale(0.97);
  background: var(--surface-active);
}

#recent-detail-pane .btn-primary-action svg,
#recent-detail-pane .btn-secondary-action svg {
  flex-shrink: 0;
}

/* Square Media Card (Recently Played, Stations, Albums) */
.media-card,
.station-card {
  width: 150px;
  min-width: 150px;
  flex-shrink: 0;
  scroll-snap-align: start;
  cursor: pointer;
  display: flex;
  flex-direction: column;
  user-select: none;
  transition: transform var(--transition-fast);
  background: transparent;
  border: none;
  padding: 0;
}

@media (max-width: 767px) {
  .media-card,
  .station-card {
    width: 130px;
    min-width: 130px;
  }
}

.media-card:hover,
.station-card:hover {
  transform: translateY(-3px);
}

.media-card:active,
.station-card:active {
  transform: scale(0.97);
}

.media-card-art-wrap,
.station-art-wrap {
  position: relative;
  width: 100%;
  aspect-ratio: 1 / 1;
  border-radius: 9px;
  overflow: hidden;
  background: #18181a;
  margin-bottom: 8px;
  border: 1px solid rgba(255, 255, 255, 0.08);
}

.media-card-art,
.station-art {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

.station-art-fallback,
.media-card-art-fallback {
  width: 100%;
  height: 100%;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  color: #ffffff;
  padding: 12px;
  text-align: center;
}

.media-card-art-wrap .media-card-art-fallback {
  display: flex;
}

.media-card-art-wrap:has(img.media-card-art:not([style*="display: none"])) .media-card-art-fallback {
  display: none;
}

.media-card-art-wrap.has-fallback .media-card-art-fallback {
  display: flex;
}

.station-art-fallback-title {
  font-size: 11px;
  font-weight: 600;
  margin-top: 6px;
  color: rgba(255, 255, 255, 0.9);
  line-height: 1.2;
  max-width: 100%;
  padding: 0 4px;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
  text-overflow: ellipsis;
  word-break: break-word;
}

.media-play-overlay,
.station-play-overlay,
.album-play-overlay {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.42);
  opacity: 0;
  transition: opacity var(--transition-fast);
  color: #ffffff;
}

.media-play-pill {
  width: 38px;
  height: 38px;
  border-radius: 50%;
  background: rgba(255, 255, 255, 0.95);
  color: #000000;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.5);
  transform: scale(0.85);
  transition: transform var(--transition-fast);
}

.media-card:hover .media-play-overlay,
.station-card:hover .station-play-overlay,
.album-card:hover .album-play-overlay {
  opacity: 1;
}

.media-card:hover .media-play-pill,
.station-card:hover .media-play-pill {
  transform: scale(1);
}

.live-badge {
  position: absolute;
  top: 6px;
  left: 6px;
  background: rgba(0, 0, 0, 0.85);
  border: 1px solid #ffffff;
  color: #ffffff;
  font-size: 9px;
  font-weight: 800;
  letter-spacing: 0.8px;
  padding: 2px 6px;
  border-radius: 4px;
  line-height: 1.2;
  z-index: 2;
}

.media-card-title,
.station-name {
  font-size: 13.5px;
  font-weight: 600;
  color: var(--text-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 100%;
  min-width: 0;
  width: 100%;
  box-sizing: border-box;
  margin-bottom: 2px;
  line-height: 1.25;
}

.media-card-sub,
.station-sub {
  font-size: 12px;
  color: var(--text-secondary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 100%;
  min-width: 0;
  width: 100%;
  box-sizing: border-box;
  line-height: 1.2;
}

/* Top Charts */
.chart-row {
  display: flex;
  align-items: center;
}

.track-rank-num {
  width: 28px;
  font-size: 14px;
  font-weight: 700;
  color: var(--text-muted);
  text-align: center;
  font-variant-numeric: tabular-nums;
  flex-shrink: 0;
}

.track-rank-num.rank-top {
  color: #ffffff;
}

.btn-chart-play {
  width: 32px;
  height: 32px;
  min-width: 32px;
  min-height: 32px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
  opacity: 0;
  transition: all var(--transition-fast);
  flex-shrink: 0;
}

.chart-row:hover .btn-chart-play {
  opacity: 1;
  color: var(--text-primary);
  background: var(--surface-hover);
}

/* Album Card Wrap */
.playlist-card-art-wrap {
  position: relative;
  width: 100%;
  aspect-ratio: 1 / 1;
  border-radius: 12px;
  overflow: hidden;
  margin-bottom: 10px;
}

.playlist-card-art-wrap .playlist-card-art {
  margin-bottom: 0;
  border-radius: 0;
}

.playlist-card-art-fallback {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #18181a, #242426);
  border-radius: 12px;
  color: #6e6e73;
}

/* Genres Grid */
.genres-grid {
  display: grid;
  gap: 10px;
  padding-bottom: 8px;
}

@media (min-width: 768px) {
  .genres-grid {
    grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
  }
}

@media (max-width: 767px) {
  .genres-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 8px;
  }
}

.genre-card {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 14px;
  min-height: 44px;
  border-radius: 12px;
  background: var(--surface-card);
  border: 1px solid var(--border-subtle);
  color: var(--text-primary);
  cursor: pointer;
  transition: all var(--transition-fast);
  touch-action: manipulation;
  text-align: left;
}

.genre-card:hover {
  background: var(--surface-hover);
  border-color: var(--border-bright);
}

.genre-card:active {
  transform: scale(0.97);
}

.genre-title {
  font-size: 13px;
  font-weight: 600;
  color: var(--text-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

/* ==========================================================================
   Mobile Mini-Player (Docked) - Enhanced 44x44px Targets & Geometry
   ========================================================================== */

.mini-player {
  position: fixed;
  left: calc(var(--safe-left) + 12px);
  right: calc(var(--safe-right) + 12px);
  bottom: 64px;
  height: 60px;
  background: rgba(22, 22, 24, 0.94);
  backdrop-filter: blur(25px);
  -webkit-backdrop-filter: blur(25px);
  border: 1px solid var(--border-subtle);
  border-radius: 14px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 8px 0 12px;
  z-index: 95;
  box-shadow: 0 8px 28px rgba(0, 0, 0, 0.75);
  cursor: pointer;
  touch-action: manipulation;
}

.mini-player-content {
  flex: 1;
  min-width: 0;
  height: 100%;
  display: flex;
  align-items: center;
  gap: 12px;
}

.mini-art {
  width: 42px;
  height: 42px;
  border-radius: 8px;
  object-fit: cover;
  background: var(--surface-card);
  flex-shrink: 0;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.5);
  transition: opacity 0.25s ease;
}

.mini-info {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
}

.mini-title {
  font-size: 13.5px;
  font-weight: 600;
  color: var(--text-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.mini-artist {
  font-size: 11.5px;
  color: var(--text-secondary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.mini-actions {
  display: flex;
  align-items: center;
  gap: 2px;
  flex-shrink: 0;
}

/* Mini Player Action Buttons - Exactly 44x44px */
.mini-btn {
  width: 44px;
  height: 44px;
  min-width: 44px;
  min-height: 44px;
  color: var(--text-primary);
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 50%;
  touch-action: manipulation;
}

.mini-btn:active {
  transform: scale(0.92);
}

.mini-progress-track {
  position: absolute;
  bottom: 0;
  left: 12px;
  right: 12px;
  height: 2px;
  background: transparent;
  overflow: hidden;
}

.mini-progress-fill {
  height: 100%;
  background: #ffffff;
  width: 0%;
  transition: width 0.1s linear;
}

/* ==========================================================================
   Mobile Bottom Tab Bar - iOS Safe Area & Minimum 44px Targets
   ========================================================================== */

.bottom-tab-bar {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  height: 56px;
  padding-bottom: 4px;
  padding-left: var(--safe-left);
  padding-right: var(--safe-right);
  background: #000000;
  backdrop-filter: blur(25px);
  -webkit-backdrop-filter: blur(25px);
  border-top: 1px solid rgba(255, 255, 255, 0.08);
  display: flex;
  align-items: center;
  justify-content: space-around;
  z-index: 100;
}

.tab-item {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 3px;
  flex: 1;
  height: 100%;
  min-height: 44px;
  color: var(--text-muted);
  transition: color var(--transition-fast);
  touch-action: manipulation;
  -webkit-tap-highlight-color: transparent;
  padding: 4px 0;
}

.tab-item svg {
  pointer-events: none;
}

.tab-item span {
  font-size: 10px;
  font-weight: 500;
  pointer-events: none;
}

.tab-item.active {
  color: var(--text-primary);
}

/* ==========================================================================
   Modals & Overlays
   ========================================================================== */

.overlay-modal {
  position: fixed;
  top: 0;
  left: 0;
  width: 100vw;
  height: 100vh;
  height: 100dvh;
  background: rgba(0, 0, 0, 0.88);
  backdrop-filter: blur(24px);
  -webkit-backdrop-filter: blur(24px);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 24px;
  z-index: 9999;
}

.overlay-card {
  background: var(--surface-card);
  border: 1px solid var(--border-subtle);
  border-radius: 18px;
  padding: 32px 28px;
  max-width: 360px;
  width: 100%;
  text-align: center;
  box-shadow: 0 16px 48px rgba(0, 0, 0, 0.9);
}

.pulse-indicator {
  width: 14px;
  height: 14px;
  border-radius: 50%;
  background: #ff453a;
  margin: 0 auto 20px auto;
  box-shadow: 0 0 0 0 rgba(255, 69, 58, 0.7);
  animation: pulse 1.8s infinite cubic-bezier(0.66, 0, 0, 1);
}

@keyframes pulse {
  to {
    box-shadow: 0 0 0 16px rgba(255, 69, 58, 0);
  }
}

.overlay-title {
  font-size: 18px;
  font-weight: 700;
  color: var(--text-primary);
  margin-bottom: 8px;
}

.overlay-desc {
  font-size: 13px;
  color: var(--text-secondary);
  line-height: 1.5;
  margin-bottom: 24px;
}

.btn-primary {
  width: 100%;
  min-height: 44px;
  padding: 12px;
  background: #ffffff;
  color: #000000;
  border-radius: 12px;
  font-size: 14px;
  font-weight: 600;
  transition: all var(--transition-fast);
  touch-action: manipulation;
}

.btn-primary:active {
  background: #e5e5e7;
  transform: scale(0.98);
}

/* Audio Quality Modal */
.modal-backdrop {
  position: fixed;
  top: 0;
  left: 0;
  width: 100vw;
  height: 100vh;
  height: 100dvh;
  background: rgba(0, 0, 0, 0.7);
  backdrop-filter: blur(16px);
  -webkit-backdrop-filter: blur(16px);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 20px;
  z-index: 999;
}

.modal-card {
  background: var(--surface-card);
  border: 1px solid var(--border-subtle);
  border-radius: 20px;
  width: 100%;
  max-width: 440px;
  padding: 24px;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.9);
}

.modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 20px;
  padding-bottom: 12px;
  border-bottom: 1px solid var(--border-subtle);
}

.modal-title-wrap {
  display: flex;
  align-items: center;
  gap: 10px;
}

.modal-title {
  font-size: 16px;
  font-weight: 700;
  color: var(--text-primary);
}

.modal-tag {
  font-size: 10px;
  font-weight: 700;
  padding: 2px 6px;
  background: #ffffff;
  color: #000000;
  border-radius: 4px;
  letter-spacing: 0.5px;
}

.modal-close {
  width: 44px;
  height: 44px;
  min-width: 44px;
  min-height: 44px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 26px;
  line-height: 1;
  color: var(--text-muted);
  cursor: pointer;
  touch-action: manipulation;
}

.modal-close:hover {
  color: var(--text-primary);
}

.modal-body {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.spec-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  font-size: 13px;
  padding: 4px 0;
}

.spec-label {
  color: var(--text-secondary);
}

.spec-val {
  font-weight: 600;
  color: var(--text-primary);
}

.highlight-green {
  color: #34c759;
}

.modal-explanation {
  margin-top: 12px;
  padding-top: 14px;
  border-top: 1px solid var(--border-subtle);
  font-size: 12px;
  line-height: 1.5;
  color: var(--text-muted);
}

/* ==========================================================================
   AMR Busy Overlay & Action Loading Spinners
   ========================================================================== */

.busy-overlay {
  position: fixed;
  inset: 0;
  z-index: 10000;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.55);
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
  opacity: 1;
  visibility: visible;
  transition: opacity 0.18s ease, visibility 0.18s ease;
  pointer-events: all;
  cursor: wait;
}

.busy-overlay.hidden {
  opacity: 0;
  visibility: hidden;
  pointer-events: none;
}

.busy-card {
  background: rgba(20, 20, 22, 0.95);
  border: 1px solid rgba(255, 255, 255, 0.14);
  border-radius: 20px;
  padding: 24px 32px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 14px;
  min-width: 170px;
  max-width: 280px;
  box-shadow: 0 20px 48px rgba(0, 0, 0, 0.85);
  transform: scale(1);
  transition: transform 0.2s cubic-bezier(0.16, 1, 0.3, 1);
  user-select: none;
}

.busy-overlay.hidden .busy-card {
  transform: scale(0.92);
}

.busy-spinner {
  width: 36px;
  height: 36px;
  border: 3px solid rgba(255, 255, 255, 0.18);
  border-top-color: #ffffff;
  border-radius: 50%;
  animation: amr-spin 0.75s linear infinite;
  box-sizing: border-box;
}

.busy-text {
  font-size: 14px;
  font-weight: 500;
  color: #ffffff;
  letter-spacing: -0.2px;
  text-align: center;
  line-height: 1.3;
}

@keyframes amr-spin {
  0% { transform: rotate(0deg); }
  100% { transform: rotate(360deg); }
}

/* Global interaction blocker when operation in flight */
body.ui-blocked {
  pointer-events: none !important;
  cursor: wait !important;
}

body.ui-blocked #busy-overlay {
  pointer-events: all !important;
}

/* Button loading state */
.btn-loading {
  position: relative !important;
  pointer-events: none !important;
  opacity: 0.8 !important;
}

.btn-loading svg {
  display: none !important;
}

.btn-loading::before {
  content: "";
  display: inline-block;
  width: 15px;
  height: 15px;
  border: 2px solid rgba(255, 255, 255, 0.25);
  border-top-color: currentColor;
  border-radius: 50%;
  animation: amr-spin 0.65s linear infinite;
  vertical-align: middle;
  margin-right: 6px;
  box-sizing: border-box;
}

.ctrl-btn.btn-loading::before {
  margin-right: 0 !important;
  width: 20px !important;
  height: 20px !important;
}

/* Play/Pause buttons should always remain interactive with visible SVGs */
.control-play-main.btn-loading,
.mini-btn.btn-loading,
#btn-play-pause.btn-loading,
#mini-btn-play-pause.btn-loading {
  pointer-events: auto !important;
  opacity: 1 !important;
}

.control-play-main.btn-loading svg,
.mini-btn.btn-loading svg,
#btn-play-pause.btn-loading svg,
#mini-btn-play-pause.btn-loading svg {
  display: block !important;
}

.control-play-main.btn-loading::before,
.mini-btn.btn-loading::before,
#btn-play-pause.btn-loading::before,
#mini-btn-play-pause.btn-loading::before {
  display: none !important;
}


/* Search Landing Categories (Genres) */
#search-landing {
  padding: 16px;
}
.search-category-title {
  font-size: 18px;
  font-weight: 700;
  margin-bottom: 16px;
  color: #fff;
}
.genres-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
  gap: 12px;
}
.genre-card {
  position: relative;
  border-radius: 12px;
  height: 100px;
  padding: 12px;
  font-weight: 700;
  font-size: 16px;
  color: #fff;
  cursor: pointer;
  overflow: hidden;
  box-shadow: 0 4px 10px rgba(0,0,0,0.2);
  transition: transform 0.2s, filter 0.2s;
}
.genre-card:active {
  transform: scale(0.96);
  filter: brightness(0.8);
}

/* Station Picker Modal Card */
.station-modal-card {
  max-width: 420px;
}

.modal-subtitle {
  font-size: 13px;
  color: var(--text-secondary);
  margin-bottom: 18px;
  line-height: 1.4;
}

.station-options-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.station-option-btn {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 12px 14px;
  min-height: 54px;
  background: var(--surface-card);
  border: 1px solid var(--border-subtle);
  border-radius: 14px;
  color: var(--text-primary);
  text-align: left;
  cursor: pointer;
  transition: all var(--transition-fast);
  touch-action: manipulation;
  width: 100%;
}

.station-option-btn:hover {
  background: var(--surface-hover);
  border-color: var(--border-bright);
  transform: translateY(-1px);
}

.station-option-btn:active {
  transform: scale(0.98);
}

.station-opt-icon {
  width: 38px;
  height: 38px;
  border-radius: 10px;
  background: rgba(255, 255, 255, 0.08);
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-primary);
  flex-shrink: 0;
}

.station-opt-details {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
  flex: 1;
}

.station-opt-primary {
  font-size: 14px;
  font-weight: 600;
  color: var(--text-primary);
}

.station-opt-secondary {
  font-size: 12px;
  color: var(--text-secondary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

/* Volume Slider Section */
.volume-section {
  display: flex;
  align-items: center;
  gap: 12px;
  width: 100%;
  max-width: 360px;
  margin: 12px auto 0;
  padding: 0 8px;
  transition: opacity 0.25s ease, transform 0.25s ease;
}

.volume-section.hidden {
  display: none !important;
}

.btn-volume-mute {
  width: 32px;
  height: 32px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-secondary);
  background: transparent;
  border: none;
  border-radius: 8px;
  cursor: pointer;
  padding: 0;
  flex-shrink: 0;
  transition: color var(--transition-fast), transform var(--transition-fast);
}

.btn-volume-mute:hover {
  color: var(--text-primary);
}

.btn-volume-mute:active {
  transform: scale(0.9);
}

.btn-volume-mute svg {
  width: 20px;
  height: 20px;
}

.volume-slider-container {
  position: relative;
  flex: 1;
  height: 32px;
  display: flex;
  align-items: center;
}

.volume-track {
  position: absolute;
  left: 0;
  right: 0;
  height: 4px;
  background: rgba(255, 255, 255, 0.15);
  border-radius: 2px;
  pointer-events: none;
  overflow: visible;
}

.volume-track-fill {
  position: absolute;
  left: 0;
  top: 0;
  height: 100%;
  background: #ffffff;
  border-radius: 2px;
  transition: width 0.05s linear;
}

.volume-thumb {
  position: absolute;
  top: 50%;
  width: 12px;
  height: 12px;
  background: #ffffff;
  border-radius: 50%;
  transform: translate(-50%, -50%);
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.5);
  pointer-events: none;
  transition: left 0.05s linear;
}

.volume-input {
  position: relative;
  width: 100%;
  height: 100%;
  margin: 0;
  opacity: 0;
  cursor: pointer;
  z-index: 2;
  -webkit-appearance: none;
  appearance: none;
}

.volume-level-label {
  font-size: 12px;
  font-variant-numeric: tabular-nums;
  font-weight: 500;
  color: var(--text-secondary);
  min-width: 34px;
  text-align: right;
  flex-shrink: 0;
}

/* ==========================================================================
   v2.2.0 "Chopin" - Signal Path Inspector & Audio Device Switcher
   ========================================================================== */

/* Signal Path Inspector Modal Card */
.signal-path-card {
  max-width: 480px;
  width: 92%;
  background: #0d0d0f;
  border: 1px solid #242428;
  border-radius: 20px;
  box-shadow: 0 16px 48px rgba(0, 0, 0, 0.8), 0 0 0 1px rgba(255, 255, 255, 0.05);
}

.signal-path-body {
  padding: 18px 20px 22px 20px;
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.signal-path-chain {
  display: flex;
  flex-direction: column;
  position: relative;
}

/* Signal Node */
.signal-node {
  display: flex;
  align-items: flex-start;
  gap: 14px;
  background: #141416;
  border: 1px solid #26262a;
  border-radius: 14px;
  padding: 14px 16px;
  position: relative;
  transition: border-color 0.2s, background-color 0.2s;
}

.signal-node-dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: #5c5c60;
  margin-top: 5px;
  flex-shrink: 0;
  transition: background-color 0.3s, box-shadow 0.3s;
}

.signal-node-dot.active {
  background: #30d158;
  box-shadow: 0 0 8px rgba(48, 209, 88, 0.6);
}

.signal-node-main {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.signal-node-top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.signal-node-badge {
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.6px;
  color: #9e9ea3;
  text-transform: uppercase;
}

.signal-node-format {
  font-size: 11px;
  font-weight: 600;
  color: #ffffff;
  background: #242428;
  padding: 2px 8px;
  border-radius: 6px;
}

.signal-node-format.highlight-green {
  color: #30d158;
  background: rgba(48, 209, 88, 0.12);
}

.signal-node-name {
  font-size: 15px;
  font-weight: 600;
  color: #ffffff;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.signal-node-meta {
  font-size: 12px;
  color: #8e8e93;
  line-height: 1.35;
}

/* Connector Between Nodes */
.signal-connector {
  display: flex;
  justify-content: flex-start;
  padding-left: 20px;
  height: 18px;
  position: relative;
}

.signal-connector-line {
  width: 2px;
  height: 100%;
  background: linear-gradient(to bottom, #30d158, #30d158);
  opacity: 0.6;
}

/* Action button inside DAC node */
.btn-signal-action {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  background: #222226;
  border: 1px solid #36363c;
  color: #ffffff;
  font-size: 12px;
  font-weight: 600;
  padding: 6px 10px;
  border-radius: 8px;
  cursor: pointer;
  align-self: center;
  flex-shrink: 0;
  transition: background-color 0.15s, border-color 0.15s, transform 0.1s;
}

.btn-signal-action:hover {
  background: #2c2c32;
  border-color: #4a4a52;
}

.btn-signal-action:active {
  transform: scale(0.96);
}

/* Bit-Perfect Verification Badge Card */
.signal-verified-card {
  display: flex;
  align-items: center;
  gap: 12px;
  background: rgba(48, 209, 88, 0.08);
  border: 1px solid rgba(48, 209, 88, 0.25);
  border-radius: 12px;
  padding: 12px 14px;
}

.signal-verified-icon {
  width: 32px;
  height: 32px;
  border-radius: 50%;
  background: rgba(48, 209, 88, 0.15);
  color: #30d158;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.signal-verified-info {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.signal-verified-title {
  font-size: 13px;
  font-weight: 700;
  color: #30d158;
  letter-spacing: 0.2px;
}

.signal-verified-desc {
  font-size: 11px;
  color: #9e9ea3;
  line-height: 1.3;
}

/* Audio Devices Modal */
.devices-modal-card {
  max-width: 480px;
  width: calc(100% - 32px);
  background: #0f0f12;
  border: 1px solid #242428;
  border-radius: 20px;
}

.audio-devices-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin-top: 10px;
  max-height: 360px;
  overflow-y: auto;
  padding-right: 2px;
}

.audio-device-item {
  display: flex;
  align-items: center;
  gap: 14px;
  background: #161619;
  border: 1px solid #242428;
  border-radius: 12px;
  padding: 12px 14px;
  cursor: pointer;
  transition: background-color 0.15s, border-color 0.15s;
  text-align: left;
  width: 100%;
}

.audio-device-item:hover {
  background: #1e1e23;
  border-color: #38383e;
}

.audio-device-item.active {
  background: #19231c;
  border-color: rgba(48, 209, 88, 0.45);
}

.audio-device-icon {
  width: 36px;
  height: 36px;
  border-radius: 10px;
  background: #222226;
  color: #ffffff;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.audio-device-item.active .audio-device-icon {
  background: rgba(48, 209, 88, 0.2);
  color: #30d158;
}

.audio-device-info {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.audio-device-name {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 14px;
  font-weight: 600;
  color: #ffffff;
  min-width: 0;
}

.audio-device-title {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.audio-device-meta {
  font-size: 11.5px;
  color: #8e8e93;
  line-height: 1.35;
}

.audio-device-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 11px;
  font-weight: 600;
  padding: 5px 12px;
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.08);
  color: #a0a0a5;
  border: 1px solid rgba(255, 255, 255, 0.12);
  flex-shrink: 0;
  white-space: nowrap;
  transition: all 0.2s ease;
}

.audio-device-badge.active {
  background: rgba(48, 209, 88, 0.16);
  color: #30d158;
  border-color: rgba(48, 209, 88, 0.35);
}

.badge-dlna {
  display: inline-flex;
  align-items: center;
  font-size: 9px;
  font-weight: 700;
  letter-spacing: 0.6px;
  padding: 2px 5px;
  border-radius: 4px;
  background: rgba(0, 242, 254, 0.12);
  color: #00f2fe;
  border: 1px solid rgba(0, 242, 254, 0.35);
  flex-shrink: 0;
  line-height: 1;
}

.audio-device-item.dlna-device .audio-device-icon {
  background: rgba(0, 242, 254, 0.1);
  color: #00f2fe;
}

.audio-device-item.dlna-device:hover {
  border-color: rgba(0, 242, 254, 0.4);
}

@media (max-width: 480px) {
  .audio-device-item {
    padding: 10px 12px;
    gap: 10px;
  }
  .audio-device-name {
    font-size: 13px;
  }
  .audio-device-meta {
    font-size: 11px;
  }
  .audio-device-badge {
    padding: 4px 8px;
    font-size: 10px;
  }
}

/* Mandatory Apple ID Auth Modal */
.auth-modal-backdrop {
  z-index: 100000;
  backdrop-filter: blur(28px) saturate(180%);
  -webkit-backdrop-filter: blur(28px) saturate(180%);
  background: rgba(0, 0, 0, 0.78);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 20px;
}

.auth-modal-card {
  max-width: 420px;
  width: 100%;
  background: #121214;
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 24px;
  padding: 32px 28px;
  text-align: center;
  box-shadow: 0 24px 60px rgba(0, 0, 0, 0.8), 0 0 0 1px rgba(255, 255, 255, 0.06);
  animation: authCardPop 0.25s cubic-bezier(0.16, 1, 0.3, 1);
}

@keyframes authCardPop {
  0% { transform: scale(0.94); opacity: 0; }
  100% { transform: scale(1); opacity: 1; }
}

.auth-modal-logo {
  width: 68px;
  height: 68px;
  margin: 0 auto 18px auto;
  border-radius: 18px;
  background: linear-gradient(145deg, #fa233b 0%, #fb5c74 100%);
  color: #ffffff;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 8px 24px rgba(250, 35, 59, 0.35);
}

.auth-modal-title {
  font-size: 22px;
  font-weight: 700;
  color: #ffffff;
  letter-spacing: -0.4px;
  margin: 0 0 8px 0;
}

.auth-modal-desc {
  font-size: 13px;
  line-height: 1.45;
  color: #9e9ea3;
  margin: 0 0 22px 0;
}

.auth-modal-features {
  display: flex;
  flex-direction: column;
  gap: 10px;
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.06);
  border-radius: 14px;
  padding: 14px 16px;
  margin-bottom: 24px;
  text-align: left;
}

.auth-feature-item {
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: 12px;
  color: #d1d1d6;
}

.auth-feature-icon {
  color: #30d158;
  font-weight: 700;
  font-size: 13px;
}

.auth-modal-actions {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.auth-btn-login {
  width: 100%;
  padding: 14px 20px;
  border-radius: 14px;
  background: #ffffff;
  color: #000000;
  font-size: 14px;
  font-weight: 600;
  border: none;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  transition: transform 0.15s, opacity 0.15s;
}

.auth-btn-login:hover {
  opacity: 0.92;
}

.auth-btn-login:active {
  transform: scale(0.98);
}

.auth-modal-status {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  margin-top: 14px;
  font-size: 12px;
  color: #8e8e93;
}


"""##

    public static let appJS = ##"""
/**
 * Apple Music Remote (AMR) - Client Application
 * Pure Vanilla JS (ES6+), Zero Dependencies.
 */

(function () {
  'use strict';

  // --- PWA Service Worker Registration ---
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('/sw.js').catch((err) => {
        console.warn('AMR ServiceWorker registration:', err);
      });
    });
  }

  // --- Application State ---
  const state = {
    connected: false,
    playbackState: 'stopped', // 'playing', 'paused', 'stopped'
    playerState: 'stopped', // 'playing', 'paused', 'stopped'
    initialViewSelected: false,
    position: 0,
    duration: 0,
    volume: 100,
    previousVolume: 100,
    lockVolume100: localStorage.getItem('amr_lock_volume_100') !== null ? (localStorage.getItem('amr_lock_volume_100') === 'true') : true,
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
    audioDevices: [],

    // Apple MusicKit & User Token
    hasUserToken: false,
    developerToken: '',
    userStorefront: 'us',
    isAccountSynced: false,
    accountHealth: null,

    // Scrubber local tracking
    isScrubbing: false,
    scrubValue: 0,
    lastSyncPos: 0,
    lastSyncTime: performance.now()
  };

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
    homeHeavySection: document.getElementById('home-heavy-section'),
    homeHeavyCarousel: document.getElementById('home-heavy-carousel'),
    homeRecContainer: document.getElementById('home-recommendations-container'),
    searchLanding: document.getElementById('search-landing'),
    homeStationsSection: document.getElementById('home-stations-section'),
    homeStationsCarousel: document.getElementById('home-stations-carousel'),
    homeAlbumsSection: document.getElementById('home-albums-section'),
    homeAlbumsCarousel: document.getElementById('home-albums-carousel'),
    homeGenresSection: document.getElementById('home-genres-section'),
    homeGenresGrid: document.getElementById('home-genres-grid'),

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
    btnCreateStation: document.getElementById('btn-create-station'),
    btnFavorite: document.getElementById('btn-favorite'),
    audioQualityBadge: document.getElementById('audio-quality-badge'),
    audioQualityText: document.getElementById('audio-quality-text'),
    desktopDacBadge: document.getElementById('desktop-dac-badge'),
    desktopDacText: document.getElementById('desktop-dac-text'),
    mobileDacBadge: document.getElementById('mobile-dac-badge'),
    mobileDacText: document.getElementById('mobile-dac-text'),

    // Station Picker Modal
    stationPickerModal: document.getElementById('station-picker-modal'),
    btnCloseStationModal: document.getElementById('btn-close-station-modal'),
    btnStationByTrack: document.getElementById('btn-station-by-track'),
    btnStationByArtist: document.getElementById('btn-station-by-artist'),
    stationOptTrackName: document.getElementById('station-opt-track-name'),
    stationOptArtistName: document.getElementById('station-opt-artist-name'),

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
    // Signal Path Modal
    qualityModal: document.getElementById('quality-modal'),
    btnCloseModal: document.getElementById('btn-close-modal'),
    signalSourceBadge: document.getElementById('signal-source-badge'),
    signalSourceTitle: document.getElementById('signal-source-title'),
    signalSourceDetails: document.getElementById('signal-source-details'),
    signalDacRate: document.getElementById('signal-dac-rate'),
    signalDacName: document.getElementById('signal-dac-name'),
    signalDacDetails: document.getElementById('signal-dac-details'),
    btnOpenDevices: document.getElementById('btn-open-devices'),
    // Audio Devices Modal
    devicesModal: document.getElementById('devices-modal'),
    btnCloseDevices: document.getElementById('btn-close-devices'),
    audioDevicesList: document.getElementById('audio-devices-list'),
    // Apple ID Auth Modal
    modalAppleAuth: document.getElementById('modal-apple-auth'),
    btnAuthModalLogin: document.getElementById('btn-auth-modal-login'),
    authModalStatus: document.getElementById('auth-modal-status')
  };

  // --- Busy Overlay & Action Loading Controller ---
  let busyTimeout = null;
  let activeLoadingBtn = null;

  function setUIBusy(isBusy, message = 'Загрузка...', sourceBtn = null) {
    state.isBusyAction = Boolean(isBusy);

    if (isBusy) {
      if (busyTimeout) clearTimeout(busyTimeout);
      document.body.classList.add('ui-blocked');

      if (dom.busyMessage) {
        dom.busyMessage.textContent = message;
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

      // Safety timeout: automatically unblock after 7 seconds if server is slow
      busyTimeout = setTimeout(() => {
        setUIBusy(false);
      }, 7000);
    } else {
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
      reconnectAttempt = 0;
      dom.overlay.classList.add('hidden');

      // Request initial status, queue, library, and explore feed
      send({ action: 'get_status' });
      send({ action: 'get_queue' });
      send({ action: 'get_playlists' });
      send({ action: 'get_explore', params: { country: state.trends.country } });
      send({ action: 'get_audio_devices' });
      send({ action: 'get_user_token_status' });
      send({ action: 'get_developer_token' });
      send({ action: 'get_account_status' });
      send({ action: 'get_info' });
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
      scheduleReconnect();
    };

    socket.onerror = function () {
      state.connected = false;
      state.initialViewSelected = false;
      dom.overlay.classList.remove('hidden');
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
    const type = (msg.event || msg.action || msg.type || '').toLowerCase();
    const data = msg.data !== undefined ? msg.data : msg;

    switch (type) {
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

      case 'get_info':
      case 'info':
        if (data && data.version) {
          const vEls = document.querySelectorAll('.brand-ver');
          vEls.forEach(el => { el.textContent = `v${data.version}`; });
        }
        break;

      default:
        // Check if data has player properties
        if (data && (data.player_state || data.playerState)) {
          updatePlayerState(data);
        } else if (data && (data.upcoming_tracks || data.upcomingTracks)) {
          updateQueue(data);
        }
        break;
    }

    // Dismiss busy overlay when playback updates or response arrives
    const busyDismissActions = [
      'player_state_changed', 'status', 'get_status',
      'queue_changed', 'queue', 'get_queue',
      'play', 'pause', 'play_pause', 'next', 'previous',
      'play_album', 'play_album_tracks', 'play_playlist',
      'play_station', 'play_hero_card', 'play_search_results',
      'play_recent', 'play_queue_index', 'play_cloud'
    ];
    if (busyDismissActions.includes(type) || msg.status === 'ok' || msg.status === 'error') {
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

  function updatePlayerState(data) {
    if (!data) return;

    clearTransportLoading();

    const oldTrack = state.track;
    const newTrack = data.track || null;
    const isNewTrack = Boolean(
      (newTrack && (!oldTrack || newTrack.id !== oldTrack.id || newTrack.name !== oldTrack.name || newTrack.artist !== oldTrack.artist)) ||
      (!newTrack && oldTrack)
    );

    state.playerState = data.player_state || data.playerState || 'stopped';
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
      state.lastSyncTime = performance.now();
      if (!state.isScrubbing) {
        updateScrubberUI(reportedPos, state.duration);
      }
    } else if (!state.isScrubbing) {
      const now = performance.now();
      if (state.playerState !== 'playing') {
        state.lastSyncPos = reportedPos;
        state.lastSyncTime = now;
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
          state.lastSyncTime = now;
          updateScrubberUI(reportedPos, state.duration);
        } else {
          // Continuous smooth drift synchronization (Phase-Locked Loop):
          // Smoothly absorb clock drift without ever causing a visible jump/jitter.
          // By applying a 15% damping correction per broadcast, client clock matches
          // server clock within a fraction of a second without jitter.
          state.lastSyncPos = predictedPos + diff * 0.15;
          state.lastSyncTime = now;
        }
      }
    }

    state.shuffle = Boolean(data.shuffle);
    state.repeatMode = data.repeat || data.repeatMode || 'off';
    state.audioQuality = data.audio_quality || data.audioQuality || 'Lossless (ALAC 24-bit/48kHz)';
    state.track = newTrack;

    if (data.audio_device_name !== undefined || data.audioDeviceName !== undefined) {
      state.audioDeviceName = data.audio_device_name || data.audioDeviceName || '';
    }
    if (data.audio_device_sample_rate !== undefined || data.audioDeviceSampleRate !== undefined) {
      state.audioDeviceSampleRate = Number(data.audio_device_sample_rate || data.audioDeviceSampleRate) || 44100;
    }
    if (data.is_bit_perfect !== undefined || data.isBitPerfect !== undefined) {
      state.isBitPerfect = data.is_bit_perfect !== undefined ? Boolean(data.is_bit_perfect) : Boolean(data.isBitPerfect);
    }

    if (data.lock_volume_100 !== undefined) {
      state.lockVolume100 = Boolean(data.lock_volume_100);
      try { localStorage.setItem('amr_lock_volume_100', String(state.lockVolume100)); } catch (e) {}
    } else if (data.isVolumeLockedTo100 !== undefined) {
      state.lockVolume100 = Boolean(data.isVolumeLockedTo100);
      try { localStorage.setItem('amr_lock_volume_100', String(state.lockVolume100)); } catch (e) {}
    }

    if (data.volume !== undefined) {
      state.volume = Math.max(0, Math.min(100, Number(data.volume)));
      if (state.volume > 0) {
        state.previousVolume = state.volume;
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

          colorSamples.push({ r, g, b, sat, lum });
        }

        if (colorSamples.length === 0) {
          return this.getDefaultPalette();
        }

        // Sort by saturation to prioritize vivid, rich hues
        colorSamples.sort((c1, c2) => c2.sat - c1.sat);

        // Sample across spectrum
        const vibrant = colorSamples[0];
        const secondary = colorSamples[Math.floor(colorSamples.length * 0.35)] || vibrant;
        const tertiary = colorSamples[Math.floor(colorSamples.length * 0.70)] || secondary;
        const deep = colorSamples[colorSamples.length - 1] || tertiary;

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

  function renderNowPlaying() {
    const isPlaying = state.playerState === 'playing';
    const t = state.track;

    // Track Meta
    if (t) {
      dom.playerTitle.textContent = t.name || 'Без названия';
      dom.playerArtist.textContent = t.artist || 'Неизвестный исполнитель';
      dom.playerAlbum.textContent = t.album || '';
      const art = getArtworkSrc(t);
      setPlayerArtwork(art);
      dom.btnFavorite.classList.toggle('active', Boolean(t.favorited));
      if (dom.miniBtnFavorite) dom.miniBtnFavorite.classList.toggle('active', Boolean(t.favorited));

      // Mini Player sync
      dom.miniTitle.textContent = t.name || 'Без названия';
      dom.miniArtist.textContent = t.artist || 'Apple Music';
    } else {
      dom.playerTitle.textContent = 'Не играет';
      dom.playerArtist.textContent = 'Apple Music';
      dom.playerAlbum.textContent = '';
      setPlayerArtwork('apple-touch-icon.svg');
      dom.btnFavorite.classList.remove('active');
      if (dom.miniBtnFavorite) dom.miniBtnFavorite.classList.remove('active');

      dom.miniTitle.textContent = 'Не играет';
      dom.miniArtist.textContent = 'Apple Music';
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

    renderVolumeUI();
    renderCurrentQueueTrack(dom.queueCurrentTrack);
    updateMediaSession();
  }

  function renderVolumeUI() {
    if (state.lockVolume100) {
      if (dom.volumeSection) dom.volumeSection.classList.add('hidden');
      if (dom.playerBottomNotice) {
        dom.playerBottomNotice.textContent = 'Прямой вывод CoreAudio (Bit-Perfect DAC • 100%)';
      }
    } else {
      if (dom.volumeSection) dom.volumeSection.classList.remove('hidden');
      if (dom.playerBottomNotice) {
        dom.playerBottomNotice.textContent = 'Прямой вывод CoreAudio (Регулируемая громкость)';
      }
      if (dom.volumeInput && !state.isDraggingVolume) {
        dom.volumeInput.value = state.volume;
      }
      if (dom.volumeTrackFill) {
        dom.volumeTrackFill.style.width = `${state.volume}%`;
      }
      if (dom.volumeThumb) {
        dom.volumeThumb.style.left = `${state.volume}%`;
      }
      if (dom.volumeLevelText) {
        dom.volumeLevelText.textContent = `${state.volume}%`;
      }
      updateVolumeIcon(state.volume);
    }
  }

  function updateVolumeIcon(vol) {
    if (!dom.volumeIcon) return;
    const wave1 = dom.volumeSection ? dom.volumeSection.querySelector('#vol-wave-1') : null;
    const wave2 = dom.volumeSection ? dom.volumeSection.querySelector('#vol-wave-2') : null;
    if (vol === 0) {
      if (wave1) wave1.style.display = 'none';
      if (wave2) wave2.style.display = 'none';
    } else if (vol < 50) {
      if (wave1) wave1.style.display = 'block';
      if (wave2) wave2.style.display = 'none';
    } else {
      if (wave1) wave1.style.display = 'block';
      if (wave2) wave2.style.display = 'block';
    }
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
  }

  function initSilentAudio() {
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
      silentAudioEl.src = '/assets/silence.m4a?v=2';
      silentAudioEl.style.cssText = 'position:fixed;bottom:0;left:0;width:1px;height:1px;opacity:0.001;pointer-events:none;z-index:-1;';
      document.body.appendChild(silentAudioEl);
    }
    attachSilentAudioListeners(silentAudioEl);
    return silentAudioEl;
  }

  function syncSilentAudio(isPlaying) {
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

  // Synchronously unlock audio & Web Audio on EVERY user gesture until unlocked
  function unlockAudioOnUserGesture() {
    const el = initSilentAudio();
    const ctx = getHapticAudioContext();
    if (ctx && ctx.state === 'suspended') {
      ctx.resume().catch(() => {});
    }

    if (!silentAudioUnlocked && el) {
      const p = el.play();
      if (p !== undefined) {
        p.then(() => {
          silentAudioUnlocked = true;
          if (state.playerState !== 'playing') {
            el.pause();
          }
          setupMediaSession();
          updateMediaSession();
        }).catch(() => {});
      }
    } else {
      setupMediaSession();
    }
  }

  ['pointerdown', 'touchstart', 'touchend', 'click'].forEach(evt => {
    window.addEventListener(evt, unlockAudioOnUserGesture, { passive: true });
  });

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

  // --- MediaSession (Lock Screen, Dynamic Island, AirPods, Control Center) ---
  let lastMediaSessionKey = '';
  function setupMediaSession() {
    if (!('mediaSession' in navigator)) return;

    try {
      navigator.mediaSession.setActionHandler('play', () => {
        triggerHaptic('medium');
        syncSilentAudio(true);
        state.playerState = 'playing';
        renderNowPlaying();
        setupMediaSession();
        updateMediaSession();
        send({ action: 'play' });
      });

      navigator.mediaSession.setActionHandler('pause', () => {
        triggerHaptic('medium');
        syncSilentAudio(false);
        state.playerState = 'paused';
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
          if (silentAudioEl && !isNaN(details.seekTime)) {
            try { silentAudioEl.currentTime = details.seekTime; } catch(e){}
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

    if ('setPositionState' in navigator.mediaSession && state.duration > 0) {
      try {
        const curPos = Math.min(Math.max(0, state.position || state.lastSyncPos || 0), state.duration);
        navigator.mediaSession.setPositionState({
          duration: Math.max(state.duration, 0.1),
          playbackRate: isPlaying ? 1.0 : 0.0,
          position: curPos
        });
        if (silentAudioEl && !silentAudioEl.paused && curPos >= 0) {
          const drift = Math.abs(silentAudioEl.currentTime - curPos);
          if (drift > 3.0) {
            try { silentAudioEl.currentTime = curPos; } catch(e){}
          }
        }
      } catch (e) {}
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

  function updateScrubberUI(currentPos, totalDur) {
    if (totalDur <= 0) {
      dom.scrubberFill.style.width = '0%';
      dom.scrubberThumb.style.left = '0%';
      dom.miniProgressFill.style.width = '0%';
      dom.timeElapsed.textContent = '0:00';
      dom.timeRemaining.textContent = '-0:00';
      dom.scrubberInput.value = 0;
      return;
    }

    const clampedPos = Math.max(0, Math.min(currentPos, totalDur));
    const percent = (clampedPos / totalDur) * 100;

    dom.scrubberFill.style.width = `${percent}%`;
    dom.scrubberThumb.style.left = `${percent}%`;
    dom.miniProgressFill.style.width = `${percent}%`;
    dom.scrubberInput.value = percent;

    dom.timeElapsed.textContent = formatTime(clampedPos);
    const remaining = totalDur - clampedPos;
    dom.timeRemaining.textContent = `-${formatTime(remaining)}`;
  }

  // --- Optimistic 60fps Scrubber Loop ---
  function scrubberAnimationLoop() {
    if (state.playerState === 'playing' && !state.isScrubbing && state.duration > 0) {
      const now = performance.now();
      const deltaSec = (now - state.lastSyncTime) / 1000;
      const currentPos = Math.min(state.duration, state.lastSyncPos + deltaSec);
      updateScrubberUI(currentPos, state.duration);
    }
    requestAnimationFrame(scrubberAnimationLoop);
  }
  requestAnimationFrame(scrubberAnimationLoop);

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

  // --- Transport Event Listeners ---
  function togglePlayPause(e) {
    if (e) {
      e.preventDefault();
      e.stopPropagation();
    }
    triggerHaptic('medium');
    const isPlaying = state.playerState === 'playing';
    syncSilentAudio(!isPlaying);
    if (isPlaying) {
      const now = performance.now();
      state.lastSyncPos = Math.min(state.duration, state.lastSyncPos + (now - state.lastSyncTime) / 1000);
      state.lastSyncTime = now;
      state.playerState = 'paused';
    } else {
      state.lastSyncTime = performance.now();
      state.playerState = 'playing';
    }
    renderNowPlaying();
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
    if (e.code === 'Space' && !['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName)) {
      e.preventDefault();
      togglePlayPause();
    }
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

  dom.btnFavorite.addEventListener('click', () => {
    triggerHaptic('toggle');
    send({ action: 'favorite' });
  });

  if (dom.miniBtnFavorite) {
    dom.miniBtnFavorite.addEventListener('click', (e) => {
      e.stopPropagation();
      triggerHaptic('toggle');
      send({ action: 'favorite' });
    });
  }

  dom.btnReconnect.addEventListener('click', () => {
    triggerHaptic('light');
    connectWebSocket();
  });

  // --- Signal Path Inspector (Roon-like Pipeline) ---
  function updateSignalPathDetails() {
    const t = state.track;
    const quality = state.audioQuality || 'Lossless (ALAC 24-bit/48kHz)';
    const rateKhz = state.audioDeviceSampleRate ? (state.audioDeviceSampleRate / 1000).toFixed(1) : '44.1';

    let formatBadge = 'ALAC Lossless';
    const up = quality.toUpperCase();
    if (up.includes('192') || up.includes('HI-RES')) {
      formatBadge = 'ALAC Hi-Res';
    } else if (up.includes('AAC')) {
      formatBadge = 'AAC 256k';
    } else if (up.includes('LOSSLESS') || up.includes('ALAC')) {
      formatBadge = 'ALAC Lossless';
    }

    if (dom.signalSourceBadge) dom.signalSourceBadge.textContent = formatBadge;
    if (dom.signalSourceTitle) {
      dom.signalSourceTitle.textContent = t ? `${t.name} — ${t.artist}` : 'Apple Music';
    }
    if (dom.signalSourceDetails) {
      dom.signalSourceDetails.textContent = quality;
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
        const protoName = isBluOS ? 'BluOS Hi-Res Stream' : 'DLNA / UPnP';
        dom.signalDacDetails.textContent = `Сетевой Hi-Res стриминг (${protoName}) • 24-бит / ${rateKhz} кГц`;
      } else {
        dom.signalDacDetails.textContent = `Прямое подключение macOS CoreAudio HAL (${rateKhz} кГц)`;
      }
    }
    const signalEngineMeta = document.querySelector('#signal-node-engine .signal-node-meta');
    if (signalEngineMeta) {
      if (isNetworkRenderer) {
        signalEngineMeta.textContent = 'CoreAudio Process Tap (Bit-Perfect) • Бесконечный Hi-Res поток';
      } else {
        signalEngineMeta.textContent = 'Bit-Perfect 100% Lock • Zero DSP • Bypass микшера';
      }
    }
    const signalVerifiedDesc = document.querySelector('.signal-verified-desc');
    if (signalVerifiedDesc) {
      if (isNetworkRenderer) {
        signalVerifiedDesc.textContent = 'Hi-Res PCM поток захватывается напрямую из Music.app и передается на сетевой рендерер без передискретизации.';
      } else {
        signalVerifiedDesc.textContent = 'Частота ЦАП аппаратно синхронизирована с потоком. Деградация разрядности исключена.';
      }
    }
  }

  const openQualityModal = () => {
    triggerHaptic('light');
    updateSignalPathDetails();
    if (dom.qualityModal) dom.qualityModal.classList.remove('hidden');
  };

  if (dom.audioQualityBadge) dom.audioQualityBadge.addEventListener('click', openQualityModal);
  if (dom.desktopDacBadge) dom.desktopDacBadge.addEventListener('click', openQualityModal);
  if (dom.mobileDacBadge) dom.mobileDacBadge.addEventListener('click', openQualityModal);

  if (dom.btnCloseModal) {
    dom.btnCloseModal.addEventListener('click', () => {
      if (dom.qualityModal) dom.qualityModal.classList.add('hidden');
    });
  }

  // --- Audio Output Devices Modal (DAC Selector) ---
  const openDevicesModal = () => {
    triggerHaptic('light');
    if (dom.devicesModal) {
      dom.devicesModal.classList.remove('hidden');
      send({ action: 'get_audio_devices' });
    }
  };

  if (dom.btnOpenDevices) dom.btnOpenDevices.addEventListener('click', openDevicesModal);

  if (dom.btnCloseDevices) {
    dom.btnCloseDevices.addEventListener('click', () => {
      if (dom.devicesModal) dom.devicesModal.classList.add('hidden');
    });
  }

  if (dom.devicesModal) {
    dom.devicesModal.addEventListener('click', (e) => {
      if (e.target === dom.devicesModal) {
        dom.devicesModal.classList.add('hidden');
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
        subtitle = `Сетевой стример • До 192 кГц Hi-Res • ${dev.manufacturer || 'DLNA'}`;
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
            <span class="audio-device-title">${dev.name || (isDLNA ? 'DLNA Стример' : 'Аудиовыход')}</span>
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

  function initMusicKit(devToken) {
    if (!devToken) return;
    state.developerToken = devToken;
    const setup = () => {
      if (window.MusicKit) {
        try {
          if (!musicKitInstance) {
            window.MusicKit.configure({
              developerToken: devToken,
              app: {
                name: 'Apple Music Remote',
                build: '2.3.0'
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
    };
    if (window.MusicKit) {
      setup();
    } else {
      document.addEventListener('musickitloaded', setup);
    }
  }

  function updateUserTokenStatus(data) {
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
    const email = data.account_email || data.mac_apple_id || data.macos_account || 'tse.tds@gmail.com';
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
        dom.modalAccountDiag.classList.add('hidden');
        dom.modalAccountDiag.setAttribute('aria-hidden', 'true');
      }
    });
  }
  if (dom.btnDoneAccountDiag) {
    dom.btnDoneAccountDiag.addEventListener('click', () => {
      triggerHaptic('light');
      if (dom.modalAccountDiag) {
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

  // --- Station Creation Modal Listeners ---
  if (dom.btnCreateStation) {
    dom.btnCreateStation.addEventListener('click', () => {
      triggerHaptic('light');
      if (dom.stationOptTrackName) {
        dom.stationOptTrackName.textContent = (state.track && state.track.name) ? state.track.name : 'Не играет';
      }
      if (dom.stationOptArtistName) {
        dom.stationOptArtistName.textContent = (state.track && state.track.artist) ? state.track.artist : 'Apple Music';
      }
      if (dom.stationPickerModal) {
        dom.stationPickerModal.classList.remove('hidden');
      }
    });
  }

  if (dom.btnCloseStationModal) {
    dom.btnCloseStationModal.addEventListener('click', () => {
      if (dom.stationPickerModal) dom.stationPickerModal.classList.add('hidden');
    });
  }

  if (dom.stationPickerModal) {
    dom.stationPickerModal.addEventListener('click', (e) => {
      if (e.target === dom.stationPickerModal) {
        dom.stationPickerModal.classList.add('hidden');
      }
    });
  }

  if (dom.btnStationByTrack) {
    dom.btnStationByTrack.addEventListener('click', () => {
      triggerHaptic('medium');
      if (dom.stationPickerModal) dom.stationPickerModal.classList.add('hidden');
      const trackName = state.track ? state.track.name : '';
      const artistName = state.track ? state.track.artist : '';
      if (!trackName) return;
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
      if (dom.stationPickerModal) dom.stationPickerModal.classList.add('hidden');
      const artistName = state.track ? state.track.artist : '';
      if (!artistName) return;
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
      dom.qualityModal.classList.add('hidden');
    }
  });

  // --- Volume Control & Settings Listeners ---
  let lastVolumeSendTime = 0;
  let volumeSendTimeout = null;

  function sendThrottledVolume(val) {
    const vol = Math.max(0, Math.min(100, Math.round(Number(val) || 0)));
    state.volume = vol;
    if (vol > 0) state.previousVolume = vol;

    if (dom.volumeTrackFill) dom.volumeTrackFill.style.width = `${vol}%`;
    if (dom.volumeThumb) dom.volumeThumb.style.left = `${vol}%`;
    if (dom.volumeLevelText) dom.volumeLevelText.textContent = `${vol}%`;
    updateVolumeIcon(vol);

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

  if (dom.volumeInput) {
    dom.volumeInput.addEventListener('input', (e) => {
      state.isDraggingVolume = true;
      sendThrottledVolume(e.target.value);
    });

    dom.volumeInput.addEventListener('change', (e) => {
      state.isDraggingVolume = false;
      sendThrottledVolume(e.target.value);
      triggerHaptic('light');
    });
  }

  if (dom.btnVolumeMute) {
    dom.btnVolumeMute.addEventListener('click', () => {
      triggerHaptic('toggle');
      if (state.volume > 0) {
        state.previousVolume = state.volume;
        sendThrottledVolume(0);
      } else {
        const restore = state.previousVolume > 0 ? state.previousVolume : 50;
        sendThrottledVolume(restore);
      }
    });
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
        <img class="track-thumb" src="${artSrc}" alt="" loading="lazy" onerror="this.onerror=null;this.src='apple-touch-icon.svg';">
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
        <img class="track-thumb" src="${artSrc}" alt="" loading="lazy" onerror="this.onerror=null;this.src='apple-touch-icon.svg';">
        <div class="track-details">
          <span class="track-row-title">${escapeHtml(t.name || 'Без названия')}</span>
          <span class="track-row-artist">${escapeHtml(t.artist || 'Неизвестный исполнитель')}</span>
        </div>
        <span class="track-row-dur">${dur}</span>
      `;

      row.addEventListener('click', () => {
        setUIBusy(true, 'Переход к треку...');
        if (type === 'upcoming') {
          send({ action: 'queue_play_index', params: { index: idx } });
        } else {
          send({ action: 'play_history_index', params: { index: idx } });
        }
      });

      container.appendChild(row);
    });
  }

  dom.btnClearQueue.addEventListener('click', () => {
    send({ action: 'queue_clear' });
  });

  // --- Library / Playlists Handling ---
  function updatePlaylists(data) {
    const list = data.playlists || (Array.isArray(data) ? data : []);
    state.playlists = list;

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
          <img class="playlist-card-art" src="${art}" alt="" loading="lazy" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
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

  function navigateToView(viewId, desktopTab) {
    if (window.innerWidth < 768) {
      switchMobileView(viewId);
    } else {
      switchDesktopTab(desktopTab);
    }
  }

  function openPlaylistDetail(pl) {
    state.albumOpenedFromHome = false;
    state.currentPlaylistDetail = pl;
    if (dom.detailBadge) dom.detailBadge.textContent = 'ПЛЕЙЛИСТ';
    dom.detailTitle.textContent = pl.name;
    const count = pl.track_count || pl.trackCount || 0;
    dom.detailMeta.textContent = `${count} треков`;
    dom.detailArtwork.src = pl.artwork_url || pl.artworkUrl || 'apple-touch-icon.svg';
    dom.playlistTracksList.innerHTML = '<div class="loading-state">Загрузка треков...</div>';

    navigateToView('view-library', 'library');
    if (dom.playlistsBrowsePane) dom.playlistsBrowsePane.classList.add('hidden');
    if (dom.playlistDetailPane) dom.playlistDetailPane.classList.remove('hidden');

    send({
      action: 'get_playlist_tracks',
      params: { name: pl.name }
    });
  }

  function openAlbumDetail(alb, fromHome = true) {
    state.albumOpenedFromHome = fromHome;
    state.currentPlaylistDetail = { ...alb, isAlbum: true };
    if (dom.detailTitle) dom.detailTitle.textContent = alb.name || alb.title || 'Альбом';
    if (dom.detailMeta) dom.detailMeta.textContent = alb.artist || alb.sub || alb.subtitle || '';
    if (dom.detailArtwork) dom.detailArtwork.src = alb.artwork || alb.artwork_url || 'apple-touch-icon.svg';
    if (dom.detailBadge) dom.detailBadge.textContent = 'АЛЬБОМ';
    if (dom.playlistTracksList) dom.playlistTracksList.innerHTML = '<div class="loading-state">Загрузка треков альбома...</div>';

    navigateToView('view-library', 'library');
    if (dom.playlistsBrowsePane) dom.playlistsBrowsePane.classList.add('hidden');
    if (dom.playlistDetailPane) dom.playlistDetailPane.classList.remove('hidden');

    send({
      action: 'get_album',
      params: {
        id: alb.id || '',
        name: alb.name || alb.title || '',
        artist: alb.artist || alb.sub || alb.subtitle || '',
        country: state.trends.country || 'ru'
      }
    });
  }

  dom.btnBackToPlaylists.addEventListener('click', () => {
    dom.playlistDetailPane.classList.add('hidden');
    if (state.albumOpenedFromHome) {
      state.albumOpenedFromHome = false;
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
    setUIBusy(true, isAlbum ? 'Запуск альбома...' : 'Запуск плейлиста...', dom.btnPlayPlaylist);
    if (isAlbum) {
      send({
        action: 'play_album',
        params: {
          id: state.currentPlaylistDetail.id || '',
          name: state.currentPlaylistDetail.name || state.currentPlaylistDetail.title || '',
          artist: state.currentPlaylistDetail.artist || state.currentPlaylistDetail.sub || state.currentPlaylistDetail.subtitle || '',
          shuffle: false
        }
      });
    } else {
      send({
        action: 'play_playlist',
        params: { playlist: state.currentPlaylistDetail.name, shuffle: false }
      });
    }
  });

  dom.btnShufflePlaylist.addEventListener('click', () => {
    if (!state.currentPlaylistDetail) return;
    const isAlbum = Boolean(state.currentPlaylistDetail.isAlbum);
    setUIBusy(true, 'Перемешивание...', dom.btnShufflePlaylist);
    if (isAlbum) {
      send({
        action: 'play_album',
        params: {
          id: state.currentPlaylistDetail.id || '',
          name: state.currentPlaylistDetail.name || state.currentPlaylistDetail.title || '',
          artist: state.currentPlaylistDetail.artist || state.currentPlaylistDetail.sub || state.currentPlaylistDetail.subtitle || '',
          shuffle: true
        }
      });
    } else {
      send({
        action: 'play_playlist',
        params: { playlist: state.currentPlaylistDetail.name, shuffle: true }
      });
    }
  });

  function updateAlbumDetails(data) {
    const alb = data.album || data;
    if (!alb) return;
    state.currentAlbumDetail = alb;
    state.currentPlaylistDetail = { ...alb, isAlbum: true };
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
        <span class="track-index-num">${t.index || idx + 1}</span>
        <div class="track-details">
          <span class="track-row-title">${escapeHtml(t.name || 'Без названия')}</span>
          <span class="track-row-artist">${escapeHtml(t.artist || alb.artist || '')}</span>
        </div>
        <span class="track-row-dur">${dur}</span>
      `;

      row.addEventListener('click', () => {
        setUIBusy(true, 'Запуск трека...');
        send({
          action: 'play_album',
          params: {
            id: alb.id || '',
            name: alb.name || '',
            artist: alb.artist || '',
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
        setUIBusy(true, 'Запуск трека...');
        send({
          action: 'play_playlist',
          params: {
            playlist: state.currentPlaylistDetail.name,
            track_index: idx + 1,
            track_id: t.numeric_id || t.id
          }
        });
      });

      dom.playlistTracksList.appendChild(row);
    });
  }

  // --- Search Handling ---
  let searchDebounceTimer = null;

  dom.searchInput.addEventListener('input', function (e) {
    const q = e.target.value.trim();
    state.searchQuery = q;
    dom.btnClearSearch.classList.toggle('hidden', q.length === 0);

    clearTimeout(searchDebounceTimer);
    if (!q) {
      dom.searchResults.innerHTML = `
        <div class="search-placeholder">
          <svg viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="#38383a" stroke-width="1.5">
            <circle cx="11" cy="11" r="8"/>
            <line x1="21" y1="21" x2="16.65" y2="16.65"/>
          </svg>
          <p>Ищите любимые треки, альбомы и исполнителей</p>
        </div>`;
      return;
    }

    searchDebounceTimer = setTimeout(() => {
      executeSearch(q, state.searchScope);
    }, 280);
  });

  dom.btnClearSearch.addEventListener('click', () => {
    dom.searchInput.value = '';
    dom.btnClearSearch.classList.add('hidden');
    state.searchQuery = '';
    dom.searchResults.innerHTML = `
      <div class="search-placeholder">
        <svg viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="#38383a" stroke-width="1.5">
          <circle cx="11" cy="11" r="8"/>
          <line x1="21" y1="21" x2="16.65" y2="16.65"/>
        </svg>
        <p>Ищите любимые треки, альбомы и исполнителей</p>
      </div>`;
  });

  dom.filterChips.forEach(chip => {
    chip.addEventListener('click', () => {
      dom.filterChips.forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      state.searchScope = chip.dataset.scope;
      if (state.searchQuery) {
        executeSearch(state.searchQuery, state.searchScope);
      }
    });
  });

  let currentSearchSongs = [];
  let currentSearchOffset = 0;
  let currentSearchHasMore = false;
  let isSearchLoadingMore = false;

  function executeSearch(query, scope, offset = 0) {
    if (offset === 0) {
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
    send({
      action: 'search',
      params: {
        query: query,
        country: state.userStorefront || state.trends.country || 'us',
        scope: scope,
        limit: 50,
        offset: offset
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
      <img class="track-thumb" src="${artSrc}" alt="" loading="lazy" onerror="this.onerror=null;this.src='apple-touch-icon.svg';">
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

  function updateSearchResults(data) {
    if (!data) {
      dom.searchResults.innerHTML = '<div class="empty-state">Ничего не найдено</div>';
      return;
    }

    const songs = data.songs || [];
    const albums = data.albums || [];
    const artists = data.artists || [];
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
    currentSearchSongs = [...songs];
    currentSearchOffset = songs.length;
    currentSearchHasMore = hasMore;

    if (songs.length === 0 && albums.length === 0 && artists.length === 0) {
      dom.searchResults.innerHTML = '<div class="empty-state">Ничего не найдено</div>';
      return;
    }

    dom.searchResults.innerHTML = '';

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
        playSearchResultsList(currentSearchSongs, false);
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
        playSearchResultsList(currentSearchSongs, true);
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
          <img class="playlist-card-art" src="${art}" alt="" loading="lazy">
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
          }, false);
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

  function playSearchResultsList(songs, shuffle, startIndex = 0) {
    if (!songs || songs.length === 0) return;
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
      action: 'play_search_results',
      params: {
        tracks: formatted,
        startIndex: startIndex,
        shuffle: Boolean(shuffle)
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
      subtitle: 'Кирилл Шолохов',
      color: 'linear-gradient(145deg, #fa233b 0%, #fb5c74 45%, #ff8a65 100%)',
      artwork: '/assets/stations/CoverPersonal.png',
      url: 'https://music.apple.com/station/my-station/ra.u-96b95a031a2fb0aa1abb70ff757aa95f',
      isLive: false
    },
    {
      id: 'station_discovery',
      name: 'В моем вкусе',
      subtitle: 'Станция открытий',
      color: 'linear-gradient(135deg, #7928ca, #ff0080)',
      artwork: '/assets/stations/CoverDiscovery.png',
      url: 'https://music.apple.com/station/item/ra.q-GAI6IDk2Yjk1YTAzMWEyZmIwYWExYWJiNzBmZjc1N2FhOTVm',
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
      artwork: '/assets/stations/CoverPersonal.png',
      url: 'https://music.apple.com/us/station/apple-music-hits/ra.1498155548',
      isLive: true
    },
    {
      id: 'station_country',
      name: 'Apple Music Country',
      subtitle: 'Современное кантри',
      color: 'linear-gradient(135deg, #f7971e, #ffd200)',
      artwork: '/assets/stations/CoverDiscovery.png',
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
    }
    if (data.genres && data.genres.length > 0) {
      state.trends.genres = data.genres;
    }

    // 1. Render Hero Featured Carousel (Подборка лучших)
    renderHeroCarousel(data);

    // 2. Render Recently Played (Вы недавно слушали ›)
    const recents = (data.recently_played && data.recently_played.length > 0)
      ? data.recently_played
      : (data.top_picks || []);
    state.recentlyPlayed = recents;
    renderRecentlyPlayed(recents);
    renderHeavyRotation(data.heavy_rotation);
    renderSimilarRecommendations(data.recommended_similar);

    // 3. Render Stations (Станции для вас ›)
    renderHomeStations(state.trends.stations || DEFAULT_STATIONS);

    // 4. Render Popular Albums (Популярные альбомы ›)
    if (state.trends.topAlbums && state.trends.topAlbums.length > 0) {
      renderHomeAlbums(state.trends.topAlbums);
    }

    // 5. Render Genres
    renderHomeGenres(state.trends.genres || DEFAULT_GENRES);
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
        if (!art || (art.includes('mzstatic') && (lowerTitle.includes('моя станция') || lowerTitle.includes('в моем вкусе') || lowerTitle.includes('заряд') || lowerTitle.includes('one ok rock')))) {
          if (lowerTitle.includes('моя станция')) art = '/assets/stations/CoverPersonal.png';
          else if (lowerTitle.includes('в моем вкусе') || lowerTitle.includes('открытий')) art = '/assets/stations/CoverDiscovery.png';
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
          id: 'ra.u-96b95a031a2fb0aa1abb70ff757aa95f',
          type: 'station',
          url: 'https://music.apple.com/station/my-station/ra.u-96b95a031a2fb0aa1abb70ff757aa95f',
          artwork: '/assets/stations/CoverPersonal.png'
        },
        {
          index: 2,
          title: 'Станция открытий',
          sub: 'Новые треки под ваш вкус',
          tag: 'Радиостанция',
          id: 'ra.q-GAI6IDk2Yjk1YTAzMWEyZmIwYWExYWJiNzBmZjc1N2FhOTVm',
          type: 'station',
          url: 'https://music.apple.com/station/item/ra.q-GAI6IDk2Yjk1YTAzMWEyZmIwYWExYWJiNzBmZjc1N2FhOTVm',
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
          title: 'Ностальгия по ню-металу',
          sub: 'Плейлист медиатеки',
          tag: 'Медиатека',
          id: 'Ностальгия по ню-металу',
          type: 'playlist',
          url: '',
          artwork: '/api/artwork/playlist?name=%D0%9D%D0%BE%D1%81%D1%82%D0%B0%D0%BB%D1%8C%D0%B3%D0%B8%D1%8F%20%D0%BF%D0%BE%20%D0%BD%D1%8E-%D0%BC%D0%B5%D1%82%D0%B0%D0%BB%D1%83'
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

      const hasArt = c.artwork && c.artwork.trim().length > 0;
      const mediaHtml = hasArt ? `
        <img class="hero-art-img" src="${c.artwork}" alt="${escapeHtml(c.title)}" loading="eager" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
        <div class="hero-art-fallback" style="display:none;">
          <svg viewBox="0 0 24 24" width="48" height="48" fill="none" stroke="currentColor" stroke-width="1.8">
            <path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>
          </svg>
        </div>
      ` : `
        <div class="hero-art-gradient" style="background: linear-gradient(135deg, #fa233b, #fb5c74)">
          <svg viewBox="0 0 24 24" width="56" height="56" fill="none" stroke="#ffffff" stroke-width="1.8">
            <path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>
          </svg>
        </div>
      `;

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
          openPlaylistDetail({ name: c.name || c.title });
          return;
        }

        setUIBusy(true, 'Запуск станции...');
        if (c.type === 'station') {
          state.isLaunchingStation = true;
          if (state.stationLaunchTimeout) clearTimeout(state.stationLaunchTimeout);
          state.stationLaunchTimeout = setTimeout(() => {
            state.isLaunchingStation = false;
            setUIBusy(false);
          }, 10000);
        }
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
            <img class="media-card-art" src="${art}" loading="lazy" alt="Cover">
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
        executeAction('play_album', { 
          id: t.id || '', 
          name: t.name || '', 
          artist: t.artist || '' 
        });
      });
      dom.homeHeavyCarousel.appendChild(card);
    });
  }

  // Render Recommendations
  function renderSimilarRecommendations(recommendedArray) {
    if (!dom.homeRecContainer) return;
    dom.homeRecContainer.innerHTML = '';
    
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
            <img class="media-card-art" src="${art}" loading="lazy" alt="Cover">
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
          executeAction('play_album', { 
            id: a.id || '', 
            name: aName, 
            artist: a.artist || '' 
          });
        });
        carousel.appendChild(card);
      });
      
      section.appendChild(title);
      section.appendChild(carousel);
      dom.homeRecContainer.appendChild(section);
    });
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

    list.forEach(t => {
      const card = document.createElement('div');
      card.className = 'media-card';
      const art = getArtworkSrc(t);

      card.innerHTML = `
        <div class="media-card-art-wrap">
          <img class="media-card-art" src="${art}" alt="" loading="lazy" onerror="this.style.display='none'; this.parentElement.classList.add('has-fallback');">
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

    container.innerHTML = '';
    list.forEach(st => {
      const card = document.createElement('div');
      card.className = 'media-card station-card';
      const isLive = Boolean(st.isLive || st.is_live);
      const gradient = st.color || 'linear-gradient(135deg, #1c1c1e, #2c2c2e)';
      const iconSvg = st.icon || '<svg viewBox="0 0 24 24" width="36" height="36" fill="currentColor"><circle cx="12" cy="12" r="3.2"/><path d="M12 6c-2.76 0-5 2.24-5 5 0 1.63.79 3.08 2 3.99V22l3-2 3 2v-7.01c1.21-.91 2-2.36 2-3.99 0-2.76-2.24-5-5-5z"/></svg>';
      const hasImage = Boolean(st.artwork && st.artwork.trim().length > 0 && !st.artwork.includes('apple-touch-icon'));

      const artHtml = hasImage
        ? `<img class="media-card-art" src="${st.artwork}" alt="" loading="lazy" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
           <div class="media-card-art-fallback" style="display:none; background: ${gradient};">
             ${iconSvg}
             <span class="station-art-fallback-title">${escapeHtml(st.name || 'Радио')}</span>
           </div>`
        : `<div class="media-card-art-fallback" style="background: ${gradient};">
             ${iconSvg}
             <span class="station-art-fallback-title">${escapeHtml(st.name || 'Радио')}</span>
           </div>`;

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

  // Drill-down for Recently Played (Вы недавно слушали ›)
  if (dom.homeRecentLink) {
    dom.homeRecentLink.addEventListener('click', () => {
      openRecentDetail();
    });
  }

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
        <img class="track-thumb" src="${art}" alt="" loading="lazy" onerror="this.src='apple-touch-icon.svg'">
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
          <img class="media-card-art" src="${art}" alt="" loading="lazy">
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

      card.addEventListener('click', (e) => {
        const isPlayBtn = Boolean(e.target.closest('.media-play-overlay'));
        if (!isPlayBtn) {
          openAlbumDetail({
            id: `${alb.id || ''}`,
            name: alb.name || '',
            artist: alb.artist || '',
            artwork: art,
            url: alb.url || ''
          }, true);
          return;
        }

        setUIBusy(true, 'Запуск альбома...');
        send({
          action: 'play_album',
          params: {
            id: `${alb.id || ''}`,
            name: alb.name || '',
            artist: alb.artist || '',
            url: alb.url || '',
            shuffle: false
          }
        });
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
    dom.btnClearSearch.classList.remove('hidden');

    const isDesktop = window.innerWidth >= 768;
    if (isDesktop) {
      switchDesktopTab('search');
    } else {
      switchMobileView('view-search');
    }

    executeSearch(cleanQ, state.searchScope);
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

  function switchMobileView(viewId) {
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
    dom.viewSearch.classList.remove('active');

    // Activate selected view
    const target = document.getElementById(viewId);
    if (target) {
      target.classList.add('active');
    }

    // Manage Mini-Player visibility on mobile
    if (viewId === 'view-now-playing') {
      dom.miniPlayer.classList.add('hidden');
    } else {
      dom.miniPlayer.classList.remove('hidden');
    }

    if (viewId === 'view-library') {
      if (dom.playlistsBrowsePane) dom.playlistsBrowsePane.classList.remove('hidden');
      if (dom.playlistDetailPane) dom.playlistDetailPane.classList.add('hidden');
      send({ action: 'get_playlists' });
    } else if (viewId === 'view-queue') {
      send({ action: 'get_queue' });
    } else if (viewId === 'view-home' || viewId === 'view-trends') {
      loadTrends();
    }
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

  function switchDesktopTab(tabName) {
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
    dom.viewSearch.classList.remove('active');

    if (tabName === 'home' || tabName === 'trends') {
      if (dom.viewHome) dom.viewHome.classList.add('active');
      else if (dom.viewTrends) dom.viewTrends.classList.add('active');
      loadTrends();
    } else if (tabName === 'queue') {
      dom.viewQueue.classList.add('active');
      send({ action: 'get_queue' });
    } else if (tabName === 'library') {
      dom.viewLibrary.classList.add('active');
      if (dom.playlistsBrowsePane) dom.playlistsBrowsePane.classList.remove('hidden');
      if (dom.playlistDetailPane) dom.playlistDetailPane.classList.add('hidden');
      send({ action: 'get_playlists' });
    } else if (tabName === 'search') {
      dom.viewSearch.classList.add('active');
      dom.searchInput.focus();
    }
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
    const isDesktop = window.innerWidth >= 768;
    if (isDesktop) {
      // On desktop, ensure right column displays active desktop tab
      switchDesktopTab(state.desktopActiveTab);
    } else {
      // On mobile, ensure active mobile view is respected
      switchMobileView(state.activeView);
    }
  }
  window.addEventListener('resize', handleResize);

  // Initialize
  setupMediaSession();
  setupArtworkSwipeGestures();
  setupMiniPlayerGestures();
  renderHeroCarousel({});
  renderHomeStations(DEFAULT_STATIONS);
  renderHomeGenres(DEFAULT_GENRES);
  handleResize();
  connectWebSocket();

})();

function bindGenreCards() {
  document.querySelectorAll('.genre-card').forEach(card => {
    card.addEventListener('click', () => {
      const genre = card.getAttribute('data-genre');
      if (genre) {
        dom.searchInput.value = genre;
        state.searchQuery = genre;
        dom.btnClearSearch.classList.remove('hidden');
        executeSearch(genre, state.searchScope);
      }
    });
  });
}
bindGenreCards();

"""##

    public static let manifestJSON = ##"""
{
  "name": "Apple Music Remote",
  "short_name": "AMR",
  "description": "Bit-Perfect High-Fidelity Remote for Apple Music on macOS",
  "id": "/",
  "start_url": "/?pwa=1",
  "scope": "/",
  "display": "standalone",
  "display_override": [
    "standalone",
    "fullscreen",
    "window-controls-overlay"
  ],
  "orientation": "portrait-primary",
  "background_color": "#000000",
  "theme_color": "#000000",
  "categories": [
    "music",
    "entertainment",
    "utilities"
  ],
  "icons": [
    {
      "src": "/apple-touch-icon.svg",
      "sizes": "any",
      "type": "image/svg+xml",
      "purpose": "any"
    },
    {
      "src": "/apple-touch-icon-180.png",
      "sizes": "180x180",
      "type": "image/png",
      "purpose": "any maskable"
    },
    {
      "src": "/apple-touch-icon-192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "any maskable"
    },
    {
      "src": "/apple-touch-icon-512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "any maskable"
    },
    {
      "src": "/apple-touch-icon.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "any maskable"
    }
  ]
}

"""##

    public static let swJS = ##"""
// Apple Music Remote (AMR) - Service Worker for PWA
const CACHE_NAME = 'amr-shell-v6';
const STATIC_ASSETS = [
  '/',
  '/index.html',
  '/style.css',
  '/app.js',
  '/manifest.json',
  '/apple-touch-icon.svg',
  '/apple-touch-icon.png',
  '/apple-touch-icon-180.png',
  '/apple-touch-icon-192.png',
  '/apple-touch-icon-512.png',
  '/assets/silence.m4a',
  '/assets/silence.wav',
  '/assets/stations/CoverPersonal.png',
  '/assets/stations/CoverDiscovery.png',
  '/assets/stations/CoverAppleMusic1.png',
  '/assets/stations/CoverHeavyRotation.svg',
  '/assets/stations/CoverElectronic.png',
  '/assets/stations/CoverRock.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(STATIC_ASSETS).catch((err) => {
        console.warn('AMR ServiceWorker pre-cache notice:', err);
      });
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.map((key) => {
          if (key !== CACHE_NAME) {
            return caches.delete(key);
          }
        })
      );
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Always bypass cache for API endpoints, WebSocket, and dynamic search
  if (
    url.pathname.startsWith('/api/') ||
    url.pathname.startsWith('/ws') ||
    event.request.method !== 'GET'
  ) {
    return;
  }

  // Network-first for code assets (HTML, app.js, style.css) so updates are immediate
  if (
    event.request.headers.get('accept')?.includes('text/html') ||
    url.pathname === '/app.js' ||
    url.pathname === '/style.css' ||
    url.pathname === '/manifest.json'
  ) {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          if (response && response.status === 200) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
          }
          return response;
        })
        .catch(() => caches.match(event.request))
    );
    return;
  }

  // Cache-first with background revalidation for static assets
  event.respondWith(
    caches.match(event.request).then((cached) => {
      if (cached) {
        fetch(event.request)
          .then((networkRes) => {
            if (networkRes && networkRes.status === 200) {
              caches.open(CACHE_NAME).then((cache) => cache.put(event.request, networkRes));
            }
          })
          .catch(() => {});
        return cached;
      }
      return fetch(event.request).then((networkRes) => {
        if (networkRes && networkRes.status === 200) {
          const copy = networkRes.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
        }
        return networkRes;
      });
    })
  );
});

"""##

    public static let appleTouchIconSVG = ##"""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <defs>
    <linearGradient id="bgGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#141416"/>
      <stop offset="100%" stop-color="#000000"/>
    </linearGradient>
    <radialGradient id="glow" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.08"/>
      <stop offset="100%" stop-color="#ffffff" stop-opacity="0"/>
    </radialGradient>
  </defs>
  
  <!-- Background with subtle border -->
  <rect width="512" height="512" rx="112" fill="url(#bgGrad)"/>
  <rect width="512" height="512" rx="112" fill="url(#glow)"/>
  <rect x="2" y="2" width="508" height="508" rx="110" fill="none" stroke="#262628" stroke-width="4"/>

  <!-- High-fidelity minimalist soundwave / audio core -->
  <g fill="#ffffff">
    <!-- Bar 1 -->
    <rect x="96" y="216" width="20" height="80" rx="10"/>
    <!-- Bar 2 -->
    <rect x="136" y="176" width="20" height="160" rx="10"/>
    <!-- Bar 3 -->
    <rect x="176" y="128" width="20" height="256" rx="10"/>
    <!-- Bar 4 -->
    <rect x="216" y="200" width="20" height="112" rx="10"/>
    <!-- Bar 5 -->
    <rect x="256" y="96" width="20" height="320" rx="10"/>
    <!-- Bar 6 -->
    <rect x="296" y="160" width="20" height="192" rx="10"/>
    <!-- Bar 7 -->
    <rect x="336" y="120" width="20" height="272" rx="10"/>
    <!-- Bar 8 -->
    <rect x="376" y="192" width="20" height="128" rx="10"/>
    <!-- Bar 9 -->
    <rect x="416" y="232" width="20" height="48" rx="10"/>
  </g>

  <!-- Bit-perfect badge text indicator at bottom center -->
  <text x="256" y="455" text-anchor="middle" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Helvetica Neue', sans-serif" font-size="22" font-weight="700" letter-spacing="5" fill="#8e8e93">BIT-PERFECT</text>
</svg>

"""##
}
