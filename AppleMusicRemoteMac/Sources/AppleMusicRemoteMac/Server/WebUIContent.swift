//  WebUIContent.swift
//  Embedded Web UI static assets for Apple Music Remote

import Foundation

public enum WebUIContent {
    public static let indexHTML: String = ##"""
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <meta name="apple-mobile-web-app-title" content="AMR">
  <meta name="theme-color" content="#000000">
  <meta name="description" content="Apple Music Remote Mac - Bit-Perfect High-Fidelity Controller">
  <title>Apple Music Remote</title>

  <link rel="icon" type="image/svg+xml" href="apple-touch-icon.svg">
  <link rel="apple-touch-icon" href="apple-touch-icon.svg">
  <link rel="manifest" href="manifest.json">
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <!-- Connection Lost Overlay -->
  <div id="connection-overlay" class="overlay-modal hidden" aria-hidden="true">
    <div class="overlay-card">
      <div class="pulse-indicator"></div>
      <h2 class="overlay-title">Нет связи с Mac</h2>
      <p class="overlay-desc" id="connection-status-text">Попытка автоматического переподключения к Apple Music...</p>
      <button id="btn-reconnect" class="btn-primary" type="button">Переподключиться</button>
    </div>
  </div>

  <!-- Main Application Wrapper -->
  <div id="app" class="app-layout">

    <!-- Left Column on Desktop / Full View on Mobile -->
    <section id="view-now-playing" class="view-panel player-panel active">
      <header class="player-top-header">
        <div class="brand-pill">
          <span class="brand-dot"></span>
          <span class="brand-title">APPLE MUSIC REMOTE</span>
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
          <button id="btn-favorite" class="btn-icon btn-fav" type="button" aria-label="Избранное" title="В избранное">
            <svg id="icon-fav" class="svg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"/>
            </svg>
          </button>
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

      <!-- Bit-Perfect Audio Mode Notice -->
      <footer class="player-bottom-notice">
        <span class="dac-status-dot"></span>
        <span class="dac-notice-text">Прямой вывод CoreAudio (Bit-Perfect DAC)</span>
      </footer>
    </section>

    <!-- Right Column on Desktop / Switched Views on Mobile -->
    <main class="content-panel-wrapper">
      <!-- Desktop Navigation Tabs -->
      <nav class="desktop-nav-header">
        <button class="nav-tab-btn" data-target="home">Главная</button>
        <button class="nav-tab-btn active" data-target="library">Медиатека</button>
        <button class="nav-tab-btn" data-target="queue">Очередь</button>
        <button class="nav-tab-btn" data-target="search">Поиск</button>
      </nav>

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
      <section id="view-library" class="view-panel content-view active">
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
      <section id="view-home" class="view-panel content-view">
        <header class="section-header home-header">
          <div>
            <h1 class="main-home-title">Главная</h1>
          </div>
          <div class="country-toggle" id="trends-country-toggle">
            <button class="country-pill active" data-country="ru" type="button">RU</button>
            <button class="country-pill" data-country="us" type="button">US</button>
          </div>
        </header>

        <div class="scroll-pane home-scroll-pane">
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

  <!-- Audio Quality Popover Modal -->
  <div id="quality-modal" class="modal-backdrop hidden" aria-hidden="true">
    <div class="modal-card">
      <div class="modal-header">
        <div class="modal-title-wrap">
          <h3 class="modal-title">Параметры аудиопотока</h3>
          <span class="modal-tag">BIT-PERFECT</span>
        </div>
        <button id="btn-close-modal" class="modal-close" type="button" aria-label="Закрыть">&times;</button>
      </div>

      <div class="modal-body">
        <div class="spec-row">
          <span class="spec-label">Качество потока</span>
          <span id="modal-spec-quality" class="spec-val">Lossless (ALAC)</span>
        </div>
        <div class="spec-row">
          <span class="spec-label">Кодек / Сжатие</span>
          <span class="spec-val">Apple Lossless (ALAC)</span>
        </div>
        <div class="spec-row">
          <span class="spec-label">Режим вывода DAC</span>
          <span class="spec-val highlight-green">Прямой эксклюзивный (CoreAudio)</span>
        </div>
        <div class="spec-row">
          <span class="spec-label">Аппаратная частота</span>
          <span id="modal-spec-rate" class="spec-val">Автосинхронизация (44.1 - 192 кГц)</span>
        </div>
        <div class="spec-row">
          <span class="spec-label">Цифровая регулировка</span>
          <span class="spec-val">Отключена (100% Bit-Perfect)</span>
        </div>

        <div class="modal-explanation">
          <p>В режиме Bit-Perfect цифровая шкала громкости в приложении зафиксирована на 100%, исключая математическую деградацию разрядности (DSP truncation). Регулируйте громкость на внешнем ЦАП или усилителе.</p>
        </div>
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

  <script src="app.js"></script>
</body>
</html>

"""##

    public static let styleCSS: String = ##"""
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

  /* iOS Safe Area Insets with Robust Dynamic Island Fallbacks */
  --safe-top: max(env(safe-area-inset-top, 0px), 0px);
  --safe-bottom: max(env(safe-area-inset-bottom, 0px), 0px);
  --safe-left: max(env(safe-area-inset-left, 0px), 0px);
  --safe-right: max(env(safe-area-inset-right, 0px), 0px);
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

html, body {
  width: 100%;
  height: 100%;
  height: 100dvh;
  background-color: var(--bg-pure);
  color: var(--text-primary);
  font-family: var(--font-stack);
  overflow: hidden;
  position: fixed;
  overscroll-behavior: none;
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
   Main Application Layout
   ========================================================================== */

.app-layout {
  width: 100%;
  height: 100%;
  height: 100dvh;
  display: flex;
  background: var(--bg-pure);
  position: relative;
  overflow: hidden;
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
    border-right: 1px solid var(--border-subtle);
    background: var(--bg-pure);
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
    background: var(--surface-base);
    overflow: hidden;
    position: relative;
  }

  .desktop-nav-header {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: calc(var(--safe-top) + 20px) 32px 16px 32px;
    background: var(--surface-base);
    border-bottom: 1px solid var(--border-subtle);
    z-index: 5;
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

  .player-panel {
    display: none;
    width: 100%;
    height: 100%;
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: var(--bg-pure);
    flex-direction: column;
    padding-top: calc(var(--safe-top) + 16px);
    padding-left: calc(var(--safe-left) + 20px);
    padding-right: calc(var(--safe-right) + 20px);
    padding-bottom: calc(var(--safe-bottom) + 72px);
    overflow-y: auto;
    z-index: 20;
    overscroll-behavior-y: contain;
    animation: viewFadeIn 0.2s cubic-bezier(0.2, 0.9, 0.4, 1);
  }

  .player-panel.active {
    display: flex;
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
    padding-top: calc(var(--safe-top) + 16px);
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
}

.artwork-wrapper {
  position: relative;
  width: 100%;
  max-width: min(320px, 75vw, 36vh);
  aspect-ratio: 1 / 1;
  border-radius: 16px;
  overflow: hidden;
  box-shadow: 0 12px 36px rgba(0, 0, 0, 0.8), 0 0 0 1px var(--border-subtle);
  background: var(--surface-card);
  flex-shrink: 1;
}

.player-art {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
  transition: transform var(--transition-smooth);
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

/* Favorite Button - 44x44px touch target */
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
}

.btn-fav.active {
  color: #ffffff;
}

.btn-fav.active svg {
  fill: #ffffff;
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

/* Bottom DAC Notice */
.player-bottom-notice {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  padding-top: 12px;
  border-top: 1px solid var(--border-subtle);
  margin-top: auto;
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

.country-toggle {
  display: inline-flex;
  align-items: center;
  background: var(--surface-card);
  border: 1px solid var(--border-subtle);
  border-radius: 20px;
  padding: 3px;
  gap: 2px;
  flex-shrink: 0;
}

.country-pill {
  padding: 5px 12px;
  min-height: 28px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 14px;
  font-size: 12px;
  font-weight: 500;
  color: var(--text-secondary);
  background: transparent;
  transition: all var(--transition-fast);
  white-space: nowrap;
  touch-action: manipulation;
}

.country-pill:hover {
  color: var(--text-primary);
}

.country-pill.active {
  background: #ffffff;
  color: #000000;
  font-weight: 600;
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
  position: absolute;
  left: calc(var(--safe-left) + 12px);
  right: calc(var(--safe-right) + 12px);
  bottom: calc(var(--safe-bottom) + 62px);
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
  z-index: 30;
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
  position: absolute;
  bottom: 0;
  left: 0;
  right: 0;
  height: calc(var(--safe-bottom) + 54px);
  padding-bottom: var(--safe-bottom);
  padding-left: var(--safe-left);
  padding-right: var(--safe-right);
  background: rgba(14, 14, 16, 0.95);
  backdrop-filter: blur(25px);
  -webkit-backdrop-filter: blur(25px);
  border-top: 1px solid var(--border-subtle);
  display: flex;
  align-items: center;
  justify-content: space-around;
  z-index: 25;
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


"""##

    public static let appJS: String = ##"""
/**
 * Apple Music Remote (AMR) - Client Application
 * Pure Vanilla JS (ES6+), Zero Dependencies.
 */

(function () {
  'use strict';

  // --- Application State ---
  const state = {
    connected: false,
    playbackState: 'stopped', // 'playing', 'paused', 'stopped'
    playerState: 'stopped', // 'playing', 'paused', 'stopped'
    initialViewSelected: false,
    position: 0,
    duration: 0,
    volume: 100,
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
    desktopActiveTab: 'library',

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

    trendsCountryPills: document.querySelectorAll('.country-pill'),
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
    miniBtnPlayPause: document.getElementById('mini-btn-play-pause'),
    miniIconPlay: document.getElementById('mini-icon-play'),
    miniIconPause: document.getElementById('mini-icon-pause'),
    miniBtnNext: document.getElementById('mini-btn-next'),
    miniProgressFill: document.getElementById('mini-progress-fill'),

    // Now Playing Main Player
    playerArtwork: document.getElementById('player-artwork'),
    playerTitle: document.getElementById('player-title'),
    playerArtist: document.getElementById('player-artist'),
    playerAlbum: document.getElementById('player-album'),
    btnFavorite: document.getElementById('btn-favorite'),
    audioQualityBadge: document.getElementById('audio-quality-badge'),
    audioQualityText: document.getElementById('audio-quality-text'),

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

    // Modal
    qualityModal: document.getElementById('quality-modal'),
    btnCloseModal: document.getElementById('btn-close-modal'),
    modalSpecQuality: document.getElementById('modal-spec-quality'),
    modalSpecRate: document.getElementById('modal-spec-rate')
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

      // Request initial status, queue, library, and trends
      send({ action: 'get_status' });
      send({ action: 'get_queue' });
      send({ action: 'get_playlists' });
      send({ action: 'get_catalog_charts', params: { country: state.trends.country } });
      send({ action: 'get_explore', params: { country: state.trends.country } });
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
      'play_station', 'play_recent', 'play_queue_index', 'play_cloud'
    ];
    if (busyDismissActions.includes(type) || msg.status === 'ok' || msg.status === 'error') {
      if (state.isBusyAction) {
        setUIBusy(false);
      }
    }
  }

  function updatePlayerState(data) {
    if (!data) return;

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
      // Smooth sync: only reconcile if reported position drifts from local prediction by > 1.2s
      const now = performance.now();
      const predictedPos = state.playerState === 'playing'
        ? Math.min(state.duration, state.lastSyncPos + (now - state.lastSyncTime) / 1000)
        : state.lastSyncPos;

      if (Math.abs(reportedPos - predictedPos) > 1.2 || reportedPos < 1.0) {
        state.lastSyncPos = reportedPos;
        state.lastSyncTime = now;
        updateScrubberUI(reportedPos, state.duration);
      }
    }

    state.shuffle = Boolean(data.shuffle);
    state.repeatMode = data.repeat || data.repeatMode || 'off';
    state.audioQuality = data.audio_quality || data.audioQuality || 'Lossless (ALAC 24-bit/48kHz)';
    state.track = newTrack;

    renderNowPlaying();
  }

  function formatTime(seconds) {
    if (isNaN(seconds) || seconds < 0) return '0:00';
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
  }

  function getArtworkSrc(track) {
    if (!track) return 'apple-touch-icon.svg';
    if (track.artwork_data_base64) {
      return `data:image/jpeg;base64,${track.artwork_data_base64}`;
    }
    if (track.artwork_url && track.artwork_url.length > 5) {
      return track.artwork_url;
    }
    if (track.artwork && track.artwork.length > 5) {
      return track.artwork;
    }
    if (track.numeric_id && track.numeric_id > 0) {
      return `/api/artwork/track?id=${track.numeric_id}`;
    }
    return '/api/artwork';
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
      if (dom.playerArtwork.getAttribute('src') !== art) {
        dom.playerArtwork.src = art;
      }
      dom.btnFavorite.classList.toggle('active', Boolean(t.favorited));

      // Mini Player sync
      dom.miniTitle.textContent = t.name || 'Без названия';
      dom.miniArtist.textContent = t.artist || 'Apple Music';
      if (dom.miniArt.getAttribute('src') !== art) {
        dom.miniArt.src = art;
      }
    } else {
      dom.playerTitle.textContent = 'Не играет';
      dom.playerArtist.textContent = 'Apple Music';
      dom.playerAlbum.textContent = '';
      if (dom.playerArtwork.getAttribute('src') !== 'apple-touch-icon.svg') {
        dom.playerArtwork.src = 'apple-touch-icon.svg';
      }
      dom.btnFavorite.classList.remove('active');

      dom.miniTitle.textContent = 'Не играет';
      dom.miniArtist.textContent = 'Apple Music';
      if (dom.miniArt.getAttribute('src') !== 'apple-touch-icon.svg') {
        dom.miniArt.src = 'apple-touch-icon.svg';
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

    // Audio Quality Badge
    const aqText = cleanAudioQualityLabel(state.audioQuality);
    dom.audioQualityText.textContent = aqText;
    dom.modalSpecQuality.textContent = state.audioQuality;

    // Extract sample rate if present
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

    // If not scrubbing, update timestamps
    if (!state.isScrubbing) {
      updateScrubberUI(state.lastSyncPos, state.duration);
    }

    renderCurrentQueueTrack(dom.queueCurrentTrack);
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
    state.lastSyncPos = targetPos;
    state.lastSyncTime = performance.now();

    send({
      action: 'seek',
      params: { position: targetPos }
    });
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
    const isPlaying = state.playerState === 'playing';
    state.playerState = isPlaying ? 'paused' : 'playing';
    renderNowPlaying();
    send({ action: isPlaying ? 'pause' : 'play' });
  }

  dom.btnPlayPause.addEventListener('click', togglePlayPause);
  dom.miniBtnPlayPause.addEventListener('click', togglePlayPause);

  dom.btnNext.addEventListener('click', () => send({ action: 'next' }));
  dom.miniBtnNext.addEventListener('click', (e) => {
    e.stopPropagation();
    send({ action: 'next' });
  });

  dom.btnPrev.addEventListener('click', () => send({ action: 'previous' }));

  dom.btnShuffle.addEventListener('click', () => {
    send({
      action: 'set_shuffle',
      params: { enabled: !state.shuffle }
    });
  });

  dom.btnRepeat.addEventListener('click', () => {
    const modes = ['off', 'all', 'one'];
    const nextIdx = (modes.indexOf(state.repeatMode) + 1) % modes.length;
    const nextMode = modes[nextIdx];
    send({
      action: 'set_repeat',
      params: { mode: nextMode }
    });
  });

  dom.btnFavorite.addEventListener('click', () => {
    send({ action: 'favorite' });
  });

  dom.btnReconnect.addEventListener('click', () => {
    connectWebSocket();
  });

  // --- Audio Quality Modal Listeners ---
  dom.audioQualityBadge.addEventListener('click', () => {
    dom.qualityModal.classList.remove('hidden');
  });

  dom.btnCloseModal.addEventListener('click', () => {
    dom.qualityModal.classList.add('hidden');
  });

  dom.qualityModal.addEventListener('click', (e) => {
    if (e.target === dom.qualityModal) {
      dom.qualityModal.classList.add('hidden');
    }
  });

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

    dom.playlistsBrowsePane.classList.add('hidden');
    dom.playlistDetailPane.classList.remove('hidden');

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

  function executeSearch(query, scope) {
    dom.searchResults.innerHTML = '<div class="loading-state">Поиск в каталоге Apple Music...</div>';
    send({
      action: 'search',
      params: {
        query: query,
        country: 'ru',
        scope: scope
      }
    });
  }

  function updateSearchResults(data) {
    if (!data) {
      dom.searchResults.innerHTML = '<div class="empty-state">Ничего не найдено</div>';
      return;
    }

    const songs = data.songs || [];
    const albums = data.albums || [];
    const artists = data.artists || [];

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
        playSearchResultsList(songs, false);
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
        playSearchResultsList(songs, true);
      });

      actionsBar.appendChild(btnPlayAll);
      actionsBar.appendChild(btnShuffle);
      headerRow.appendChild(actionsBar);
      dom.searchResults.appendChild(headerRow);

      const list = document.createElement('div');
      list.className = 'track-list';
      songs.forEach(s => {
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

        list.appendChild(row);
      });
      dom.searchResults.appendChild(list);
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

  function playSearchResultsList(songs, shuffle) {
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

  function loadTrends(country) {
    if (country) {
      state.trends.country = country;
    }
    const c = state.trends.country || 'ru';

    if (dom.trendsCountryPills) {
      dom.trendsCountryPills.forEach(pill => {
        pill.classList.toggle('active', pill.dataset.country === c);
      });
    }

    send({
      action: 'get_catalog_charts',
      params: { country: c }
    });

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
          openPlaylistDetail({ name: c.id || c.title });
          return;
        }

        setUIBusy(true, 'Запуск...');
        send({
          action: 'play_hero_card',
          params: {
            index: c.index,
            name: c.title,
            artist: c.sub || c.subtitle || c.artist || '',
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
      const art = t.artwork || (t.id ? `/api/artwork/track?id=${t.id}` : 'apple-touch-icon.svg');

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
      const art = t.artwork || (t.id ? `/api/artwork/track?id=${t.id}` : 'apple-touch-icon.svg');
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

  // Country pill toggles
  if (dom.trendsCountryPills) {
    dom.trendsCountryPills.forEach(pill => {
      pill.addEventListener('click', () => {
        const country = pill.dataset.country;
        if (country && country !== state.trends.country) {
          state.trends.country = country;
          dom.trendsCountryPills.forEach(p => p.classList.toggle('active', p.dataset.country === country));
          if (dom.trendsSongsList) dom.trendsSongsList.innerHTML = '<div class="loading-state">Загрузка топ-чартов...</div>';
          if (dom.trendsAlbumsGrid) dom.trendsAlbumsGrid.innerHTML = '<div class="loading-state">Загрузка альбомов...</div>';
          loadTrends(country);
        }
      });
    });
  }

  // --- Navigation & View Switching ---

  // Mobile Bottom Tab Bar
  dom.tabItems.forEach(tab => {
    tab.addEventListener('click', () => {
      const targetViewId = tab.dataset.view;
      switchMobileView(targetViewId);
    });
  });

  function switchMobileView(viewId) {
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

  // Tapping Mini-Player body expands Now Playing
  dom.miniTrigger.addEventListener('click', () => {
    switchMobileView('view-now-playing');
  });

  // Desktop Navigation
  dom.desktopNavButtons.forEach(btn => {
    btn.addEventListener('click', () => {
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
  renderHeroCarousel({});
  renderHomeStations(DEFAULT_STATIONS);
  renderHomeGenres(DEFAULT_GENRES);
  handleResize();
  connectWebSocket();

})();

"""##

    public static let manifestJSON: String = ##"""
{
  "name": "Apple Music Remote",
  "short_name": "AMR",
  "description": "Bit-Perfect High-Fidelity Remote for Apple Music on macOS",
  "start_url": "./index.html",
  "scope": "./",
  "display": "standalone",
  "orientation": "portrait-primary",
  "background_color": "#000000",
  "theme_color": "#000000",
  "icons": [
    {
      "src": "apple-touch-icon.svg",
      "sizes": "512x512",
      "type": "image/svg+xml",
      "purpose": "any maskable"
    },
    {
      "src": "apple-touch-icon.svg",
      "sizes": "192x192",
      "type": "image/svg+xml"
    }
  ]
}

"""##

    public static let appleTouchIconSVG: String = ##"""
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
