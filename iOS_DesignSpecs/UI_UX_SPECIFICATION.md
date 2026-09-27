# Apple Music Remote for iOS (AppleMusicRemoteIOS)
## Comprehensive UI/UX Architecture & Native Component Specification
**Target Platform:** iPhone iOS 17.0+ / iOS 18.0+  
**Design Paradigm:** Apple Music Human Interface Guidelines (HIG) + Dark Glassmorphism + Material Vibrancy  
**Document Version:** 2.0.0  
**Author:** Lead UI/UX Designer & iOS Systems Architect  

---

## 1. Executive Summary & Design Philosophy

`AppleMusicRemoteIOS` is a high-performance native iOS application designed to control the macOS Apple Music engine seamlessly over the local network. The app blends the sleek aesthetic of **Apple Music iOS 18** with the robust library navigation and queue control of the classic **iTunes Remote**, elevated with modern iOS features:
- **Dynamic Ambient Glow Engine**: Multi-stop mesh gradient generated in real-time from high-resolution album artwork colors.
- **Glassmorphism & Vibrancy**: Layered materials (`.ultraThinMaterial`, frosted blur layers, hairline specular stroke borders) creating depth and visual hierarchy.
- **Micro-interactions & Tactile Feedback**: Precise Haptic Engine triggers (`UIImpactFeedbackGenerator`, `UINotificationFeedbackGenerator`) synced with transport controls, volume scrubbers, and queue reordering.
- **Live Sync & Zero-Latency Feel**: Server-Sent Events (SSE) event-driven synchronization with local timeline interpolation so scrubbers and playback states never lag.
- **Dynamic Island & Live Activity**: Lock Screen and Dynamic Island widgets allowing playback control without unlocking the iPhone.

```
+-------------------------------------------------------------------------+
|                          NAVIGATION HIERARCHY                           |
+-------------------------------------------------------------------------+
|                                                                         |
|  +-------------------------------------------------------------------+  |
|  |                 GLOBAL TOP BAR (Connection Status & Bonjour)     |  |
|  +-------------------------------------------------------------------+  |
|                                                                         |
|  +-------------------+ +-------------------+ +-----------------------+  |
|  |   TAB 1: NOW      | |   TAB 2: RADIO    | |     TAB 3: LIBRARY    |  |
|  |     PLAYING       | |    & STATIONS     | |   (iTunes Parity)     |  |
|  | Full Ambient Glow | | Curated & Live AM1| | Playlists/Artists/etc |  |
|  +-------------------+ +-------------------+ +-----------------------+  |
|  +-----------------------------------------+ +-----------------------+  |
|  |             TAB 4: SEARCH               | |     TAB 5: QUEUE      |  |
|  | Unified Tri-Scope: All / Lib / Cloud    | | Reorder / Add Next    |  |
|  +-----------------------------------------+ +-----------------------+  |
|                                                                         |
|  +-------------------------------------------------------------------+  |
|  |             PERSISTENT FLOATING MINI-PLAYER (Expandable)          |  |
|  +-------------------------------------------------------------------+  |
|  |             FLOATING LIQUID GLASS TAB BAR (5 Tabs)                |  |
|  +-------------------------------------------------------------------+  |
+-------------------------------------------------------------------------+
```

---

## 2. Information Architecture & Navigation Hierarchy

The application adopts a **5-Tab Navigation Layout** with an omnipresent **Interactive Floating Mini-Player** that expands smoothly via interactive spring gestures into the full-screen **Now Playing** sheet.

### 2.1 Navigation Tabs Matrix

| Tab Index | Tab Title | SF Symbol (Default / Active) | Core Functionality |
|---|---|---|---|
| **Tab 1** | **Сейчас играет** (Now Playing) | `play.circle` / `play.circle.fill` | Full-screen interactive player with ambient mesh glow, ALAC Lossless badge, timeline scrubber, hardware volume slider, transport controls, and queue peek. |
| **Tab 2** | **Радио** (Radio & Stations) | `dot.radiowaves.left.and.right` / `radio.fill` | Curated stations («Для вас», «Прямой эфир Apple Music 1/Hits/Country», «Жанровые станции»). One-tap streaming to Mac. |
| **Tab 3** | **Медиатека** (Library) | `music.note.list` / `music.note.list` | Full iTunes Remote parity: Playlists, Artists, Albums, Songs, Genres with fast alphabetical index scrubber. |
| **Tab 4** | **Поиск** (Search) | `magnifyingglass` / `magnifyingglass` | Unified tri-scope search (`Все` / `Медиатека` / `Apple Music`) with live debounced filtering across songs, albums, and artist carousels. |
| **Tab 5** | **Очередь** (Queue & Up Next) | `list.bullet` / `list.bullet` | Currently playing track card + Up Next list with native drag-and-drop reordering, swipe-to-delete, and Clear Queue button. |

---

## 3. Detailed Component Specifications by Navigation Tab

### 3.1 Tab 1: Now Playing (Full Screen Player)

The **Now Playing** screen is the emotional center of the app. It supports both standalone tab viewing and an interactive modal sheet expanded from the floating Mini-Player.

```
+-------------------------------------------------------------------------+
| [v] Minimize      NOW PLAYING / СЕЙЧАС ИГРАЕТ                 (⋯) Menu  |
|                                                                         |
|                 +-------------------------------------+                 |
|                 |                                     |                 |
|                 |          600x600 ARTWORK            |                 |
|                 |       (Spring Scale 1.0/0.82)       |                 |
|                 |     Ambient Dynamic Back Glow       |                 |
|                 |                                     |                 |
|                 +-------------------------------------+                 |
|                                                                         |
|   Track Title Marquee (Auto-scrolls if long)                     [☆]    |
|   Artist Name & Album Description                              Favorite |
|                                                                         |
|   [ LOSSLESS  ALAC 24-bit/48kHz ] (Tappable Audio Quality Badge)        |
|                                                                         |
|   ●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━○       |
|   01:42                                                          -02:18 |
|                                                                         |
|         [🔀]       [⏮]        [ ▶ / ⏸ ]        [⏭]       [🔁]          |
|        Shuffle     Prev       Play/Pause        Next     Repeat         |
|                                                                         |
|   [🔈]  ════════════════════════●═══════════════════════════  [🔊]       |
|   (Mute)                 Mac Volume Slider                              |
|                                                                         |
|   [ 🖥️ MacBook Pro 16" ]                  [ 📑 Queue Quick Peek ]        |
+-------------------------------------------------------------------------+
```

#### Detailed Specs & States:
1. **Dynamic Ambient Background Glow**:
   - **Algorithm**: Extracts dominant primary (`c1`), secondary (`c2`), and tertiary (`c3`) vibrant colors from album artwork using Core Graphics / Metal color quantization.
   - **Rendering**: Rendered as a multi-point blurred gradient (`blur(radius: 80)`) with a low-pass black overlay (`opacity: 0.45`) ensuring WCAG 2.1 AAA text contrast for all white typography.
   - **Subtle Breathing Animation**: When playing, the glow subtly modulates in scale (`1.00 -> 1.06`) over a 4.0-second ease-in-out curve.
2. **Interactive Artwork Container**:
   - **Physics & Scale**:
     - **Playing State**: Scale `1.0`, Corner Radius `16pt`, Shadow `Color.black.opacity(0.35)`, Radius `24pt`, Y-offset `12pt`.
     - **Paused State**: Smooth spring animation (`.spring(response: 0.45, dampingFraction: 0.7)`) to Scale `0.82`, Shadow Radius `10pt`, Y-offset `4pt`.
3. **Typography & Auto-Marquee**:
   - **Track Title**: SF Pro Rounded, Bold, `22pt`, White. If the text exceeds the container width, an auto-scrolling marquee triggers with a 2-second pause at both endpoints.
   - **Artist / Album**: SF Pro Text, Regular, `17pt`, `Color(white: 0.75)`. Tappable to navigate directly to Artist or Album details.
   - **Favorite Star**: SF Symbol `star` / `star.fill` (Accent Red `#FA2D48`) with a scale-burst particle animation upon toggling.
4. **Lossless Audio Quality Badge**:
   - **Styling**: Translucent pill (`.ultraThinMaterial`, border `0.5pt` white opacity `0.2`, corner radius `6pt`).
   - **Label**: `LOSSLESS` / `HI-RES LOSSLESS` / `DOLBY ATMOS` (SF Pro Rounded Bold `10pt`, letter spacing `0.8pt`).
   - **Modal Popover**: Tapping the badge presents an informative sheet displaying format details: *“Lossless Audio: ALAC 24-bit / 48.0 kHz delivered uncompressed from Apple Music engine to local DAC.”*
5. **Fluid Interactive Scrubber**:
   - **Visuals**: Track height `4pt` (expands to `8pt` on touch), elapsed track fill in pure white `#FFFFFF`, remaining track in `Color.white.opacity(0.24)`.
   - **Thumb**: Circle `14pt` with subtle drop shadow; scales to `20pt` during dragging.
   - **Time Labels**: SF Pro Rounded Medium `12pt` monospaced numbers. Left: `MM:SS` (Elapsed); Right: `-MM:SS` (Remaining).
   - **Haptic Scrubbing**: Triggers `.selection` haptic feedback on whole-second intervals during slow scrubbing and velocity-aware steps during fast seeking.
6. **Transport Controls Cluster**:
   - **Play/Pause Button**: Prominent circular button with SF Symbol `play.fill` or `pause.fill` (`36pt`), white glyph, interactive spring compression (`.scaleEffect(0.88)` on touch down).
   - **Skip Prev / Next**: SF Symbols `backward.fill` / `forward.fill` (`26pt`), white glyph with `.impact(.medium)` feedback on release.
   - **Shuffle & Repeat**: Left and right secondary triggers with illuminated red dot indicator when active (`.repeatOne`, `.repeatAll`, `.shuffleActive`).
7. **Mac Hardware Volume Slider**:
   - **Direct Sync**: Two-way real-time binding to Mac system volume (`0 - 100%`).
   - **Mute Quick Toggle**: Tapping the left speaker icon (`speaker.fill` / `speaker.slash.fill`) instantly toggles mute state, restoring previous volume level on unmute.
   - **Continuous Feedback**: Subtle `.selection` haptic every 10% volume increment.

---

### 3.2 Tab 2: Radio & Stations («Радио»)

The **Radio & Stations** tab provides instant access to personal algorithms, live 24/7 global broadcasts, and genre curated stations with one-tap instant streaming.

```
+-------------------------------------------------------------------------+
|  РАДИО И СТАНЦИИ                                                        |
|                                                                         |
|  == ДЛЯ ВАС ==========================================================  |
|  +-----------------------------+  +----------------------------------+  |
|  | 🔴 [МОЯ СТАНЦИЯ]            |  | 🟣 [СТАНЦИЯ ОТКРЫТИЙ]            |  |
|  | Любимые треки и новинки     |  | Музыка под ваш персональный вкус |  |
|  | [ ▶ Слушать ]               |  | [ ▶ Открыть ]                    |  |
|  +-----------------------------+  +----------------------------------+  |
|                                                                         |
|  == ПРЯМОЙ ЭФИР ======================================================  |
|  +-------------------+  +--------------------+  +--------------------+  |
|  | [LIVE] AM 1       |  | [LIVE] AM HITS     |  | [LIVE] AM COUNTRY  |  |
|  | Мировые премьеры  |  | Культовые хиты     |  | Кантри и фолк      |  |
|  +-------------------+  +--------------------+  +--------------------+  |
|                                                                         |
|  == ЖАНРОВЫЕ СТАНЦИИ =================================================  |
|  [ ❄️ Chill & Lo-Fi ]   [ 🎸 Рок & Альтернатива ]  [ 🎧 Deep House ]    |
|  [ 🎤 Поп-хиты ]        [ 🎹 Хип-хоп & Рэп ]       [ 🎷 Джаз & Блюз ]   |
|  [ ⚡ Электроника ]                                                     |
+-------------------------------------------------------------------------+
```

#### Curated Sections Specification:
1. **«Для вас» (Personal AI Radio)**:
   - **Cards**: Large hero dual-cards (width `260pt`, height `160pt`, horizontal carousel).
   - **Моя станция (Personal Station)**: Red-crimson gradient (`#FA233B -> #FB5C74`), artwork overlay, subtitles: *"Любимые треки и персональные рекомендации"*.
   - **Станция открытий (Discovery Station)**: Purple-neon gradient (`#7928CA -> #FF0080`), subtitle: *"Новая музыка на основе ваших вкусов"*.
   - **Action**: Single tap fires `/api/play/station?id=station_personal` directly to the Mac engine and pops up playback feedback.
2. **«Прямой эфир» (Apple Music Live Broadcasts)**:
   - **Live Stations**: Apple Music 1 Live (`station_am1`), Apple Music Hits (`station_hits`), Apple Music Country (`station_country`).
   - **Animated LIVE Badge**: Top-left pill badge containing a pulsing red dot indicator (`#FF3B30` pulsing with scale `1.0 -> 1.3` and opacity `1.0 -> 0.4`) and monospaced text `LIVE`.
   - **Equalizer Waveform**: When currently streaming, an animated 3-bar green/white audio visualizer is displayed over the artwork card.
3. **«Жанровые станции» (Curated Mood & Genre Stations)**:
   - **Grid Layout**: 2-column adaptive square cards with corner radius `14pt`.
   - **Included Genres**:
     - *Chill & Lo-Fi* (Cyan-blue gradient `#00B4DB -> #0083B0`)
     - *Поп-хиты Радио* (Pink-crimson `#FA2D48 -> #FF6B8B`)
     - *Рок & Альтернатива* (Amber-orange `#E65100 -> #FF9800`)
     - *Хип-Хоп & Рэп* (Deep purple `#4A148C -> #7B1FA2`)
     - *Электроника & Dance* (Emerald `#00695C -> #00BFA5`)
     - *Deep House & Melodic* (Magenta `#880E4F -> #D81B60`)
     - *Джаз & Блюз* (Slate blue `#37474F -> #78909C`)
   - **Interaction**: Tap triggers `.impact(.light)` and starts continuous radio playback.

---

### 3.3 Tab 3: Library («Медиатека» - iTunes Remote Parity)

The **Library** tab matches the complete hierarchy of the Mac Apple Music library with instantaneous browsing, alphabetical section jumping, and batch actions.

```
+-------------------------------------------------------------------------+
|  МЕДИАТЕКА                                                  (⚙️ Server) |
|                                                                         |
|  [ 📂 Плейлисты ]                                              48 >     |
|  [ 👤 Артисты ]                                               184 >     |
|  [ 💿 Альбомы ]                                               320 >     |
|  [ 🎵 Песни ]                                               1,840 >     |
|  [ 🏷️ Жанры ]                                                  24 >     |
|                                                                         |
|  == НЕДАВНО ДОБАВЛЕННЫЕ =============================================== |
|  +--------------+  +--------------+  +--------------+  +--------------+ |
|  | [Art]        |  | [Art]        |  | [Art]        |  | [Art]        | |
|  | Album Name   |  | Album Name   |  | Album Name   |  | Album Name   | |
|  | Artist       |  | Artist       |  | Artist       |  | Artist       | |
|  +--------------+  +--------------+  +--------------+  +--------------+ |
|                                                                         |
|  == ВСЕ ТРЕКИ (С АЛФАВИТНЫМ СКРАББЕРОМ) ============================= [A|
|  [Art]  Blinding Lights                      03:20  (⋯)                |B|
|         The Weeknd — After Hours                                       |C|
|  [Art]  Bohemian Rhapsody                    05:55  (⋯)                |D|
|         Queen — A Night at the Opera                                   |E|
|  [Art]  Get Lucky                            04:08  (⋯)                |F|
|         Daft Punk — Random Access Memories                             |G|
+-------------------------------------------------------------------------+
```

#### Components & Sub-views:
1. **Top Navigation Sections**:
   - Standard Apple Music grouped cell styling (`.insetGrouped` list) with vibrant SF Symbols in custom colored rounded squares:
     - **Плейлисты**: `music.note.list` (Gradient Red)
     - **Артисты**: `music.mic` (Gradient Blue)
     - **Альбомы**: `square.stack` (Gradient Orange)
     - **Песни**: `music.quarternote.3` (Gradient Purple)
     - **Жанры**: `guitars` (Gradient Green)
   - **Count Badges**: Right-aligned count pill (e.g. `48`, `184`) in `Color.secondary`.
2. **Alphabetical Fast Index Scrubber**:
   - Vertical alphabet rail (`A-Z`, `#`, `А-Я`) anchored to the right screen edge.
   - Touching and dragging dynamically scrolls the list with smooth sticky section headers.
   - **Magnifier HUD**: Floating circular glass bubble displaying the current active letter next to the user's thumb with haptic feedback on each section transition.
3. **Track Row Component**:
   - **Thumbnail**: `48x48pt` rounded image (`cornerRadius: 8pt`) with asynchronous disk/memory caching.
   - **Title**: SF Pro Text Semibold `16pt`, White.
   - **Subtitle**: Artist name and Album separated by middle dot (`•`).
   - **Duration & 3-Dots Menu Button**: Duration (`MM:SS`) in `13pt` Gray + hit-target expanded `⋯` button (`32x32pt`) for contextual actions.
4. **Playlist Detail Header View**:
   - Large mosaic artwork (`180x180pt`) with drop shadow.
   - Title, track count, total duration, and curator note.
   - Dual action buttons: `[ ▶ Слушать ]` (Primary Red Fill) and `[ 🔀 Перемешать ]` (Translucent Glass Fill).

---

### 3.4 Tab 4: Search («Поиск» - Unified Tri-Scope Engine)

The **Search** tab provides instant, debounced querying across local tracks and Apple Music Cloud catalog with segmented scoping.

```
+-------------------------------------------------------------------------+
|  ПОИСК                                                                  |
|  +-------------------------------------------------------------------+  |
|  | 🔍 Поиск по медиатеке и Apple Music...                        (X) |  |
|  +-------------------------------------------------------------------+  |
|                                                                         |
|  [     Все (All)     |   Медиатека (Library)   |   Apple Music (Cloud)   ] |
|                                                                         |
|  == АРТИСТЫ ==========================================================  |
|  (Avatar)          (Avatar)          (Avatar)          (Avatar)         |
|  The Weeknd        Daft Punk         Drake             Taylor Swift     |
|                                                                         |
|  == ЛУЧШИЕ РЕЗУЛЬТАТЫ (ПЕСНИ) =======================================   |
|  1. [Art]  Starboy                                    03:50  [▶]  (⋯)   |
|            The Weeknd feat. Daft Punk                                   |
|  2. [Art]  Blinding Lights                            03:20  [▶]  (⋯)   |
|            The Weeknd                                                   |
|                                                                         |
|  == АЛЬБОМЫ ==========================================================  |
|  +---------------------+  +---------------------+                       |
|  | [ 160x160 Art ]     |  | [ 160x160 Art ]     |                       |
|  | After Hours         |  | Dawn FM             |                       |
|  | The Weeknd (2020)   |  | The Weeknd (2022)   |                       |
|  +---------------------+  +---------------------+                       |
+-------------------------------------------------------------------------+
```

#### Search Architecture & Filtering:
1. **Search Bar & Scope Control**:
   - Native `.searchable` integration with immediate keyboard focus and voice-dictation support.
   - **Segmented Scope Filter**:
     - `Все` (Unified aggregate of local tracks and cloud catalog)
     - `Медиатека` (Instant offline/local index search with zero latency)
     - `Apple Music` (iTunes Cloud Storefront lookup by country: `ru`, `us`, etc.)
2. **Debouncing & Performance**:
   - 200ms debounce timer preventing unnecessary network saturation during typing.
   - Cancel-and-replace `Task` pattern in SwiftUI `AsyncSequence`.
3. **Artists Row**:
   - Horizontal circular avatar carousel (`72x72pt` circular images with border stroke).
   - Tapping an artist opens their full catalog sheet (Top Tracks, Albums, Singles).
4. **Quick Play & Action Buttons**:
   - Every song result contains a direct Quick Play icon `[▶]` that immediately commands the Mac to play the track, plus `⋯` for queuing.

---

### 3.5 Tab 5: Queue & Up Next («Очередь»)

The **Queue** tab displays the current playing track and full queue with native drag-and-drop reordering, swipe deletion, and clear controls.

```
+-------------------------------------------------------------------------+
|  ОЧЕРЕДЬ ВОСПРОИЗВЕДЕНИЯ                              [ Очистить ]      |
|                                                                         |
|  == СЕЙЧАС ИГРАЕТ ====================================================  |
|  +-------------------------------------------------------------------+  |
|  | [ 56x56 Art ]  Midnight City                           04:03      |  |
|  |                M83 — Hurry Up, We're Dreaming          [ ||| ]    |  |
|  +-------------------------------------------------------------------+  |
|                                                                         |
|  == ДАЛЕЕ (ИСТОЧНИК: ПЛЕЙЛИСТ «FAVORITES») =============== [ 🔀 Shuffle ] |
|                                                                         |
|  1. [Art]  Instant Crush                        05:37  (⋯)  [ ≡≡ Reorder ]
|            Daft Punk feat. Julian Casablancas                            |
|                                                                         |
|  2. [Art]  The Less I Know The Better           03:36  (⋯)  [ ≡≡ Reorder ]
|            Tame Impala                                                   |
|                                                                         |
|  3. [Art]  Nightcall                            04:19  (⋯)  [ ≡≡ Reorder ]
|            Kavinsky                                                      |
|                                                                         |
|  [ ➕ Добавить следующее... ]                                            |
|  [ ♾️ Автовоспроизведение похожих треков: ВКЛ ]                          |
+-------------------------------------------------------------------------+
```

#### Queue Capabilities:
1. **Now Playing Card**:
   - Highlighted glass container (`.ultraThinMaterial` with glowing border).
   - Active animated equalizer waveform icon to indicate live Mac output.
2. **Reordering & Editing**:
   - Native SwiftUI `.onMove(perform:)` binding sending reordered indices to `/api/player/queue`.
   - Right-side grab handles (`≡≡`) with immediate tactile haptic `.impact(.light)` when dragging initiates and `.impact(.medium)` upon drop.
3. **Swipe Actions**:
   - Swipe Left: Red `Удалить` (Delete) button with trash SF Symbol -> fires `/api/queue/remove?index=N`.
   - Swipe Right: Blue `Играть следующим` (Play Next).
4. **Queue Control Toolbar**:
   - **Очистить очередь (Clear Queue)**: Prompts confirmation alert dialog to prevent accidental queue loss.
   - **Infinity Auto-Play (Бесконечное автовоспроизведение)**: Toggle switch that dynamically requests similar tracks when the queue is nearing completion.

---

## 4. Server Discovery & Bonjour Connection Modal

The app connects to the macOS sidecar daemon via **Zero-Configuration Networking (Bonjour)** over `_applemusicremote._tcp`.

```
+-------------------------------------------------------------------------+
|                       ПОДКЛЮЧЕНИЕ К MAC                                 |
|                                                                         |
|  [●] СТАТУС: ПОДКЛЮЧЕНО К «Kirill's MacBook Pro M3» (10.10.20.189:8080) |
|                                                                         |
|  == ОБНАРУЖЕННЫЕ СЕРВЕРЫ (BONJOUR _applemusicremote._tcp) ============= |
|  +-------------------------------------------------------------------+  |
|  | 💻  Kirill's MacBook Pro M3 (Основной)                   [ ✓ ]   |  |
|  |     10.10.20.189:8080 • Задержка 4 мс • macOS Sequoia              |  |
|  +-------------------------------------------------------------------+  |
|  | 🖥️  Mac Studio (Студия)                                            |  |
|  |     10.10.20.240:8080 • Задержка 12 мс                            |  |
|  +-------------------------------------------------------------------+  |
|                                                                         |
|  == РУЧНОЕ ПОДКЛЮЧЕНИЕ ===============================================  |
|  IP-адрес:  [ 10.10.20.189                  ]                           |
|  Порт:      [ 8080                          ]                           |
|  [ 📷 Сканировать QR-код с экрана Mac ]                                 |
|                                                                         |
|  [              ПОДКЛЮЧИТЬСЯ ВРУЧНУЮ / RECONNECT                     ]  |
+-------------------------------------------------------------------------+
```

### 4.1 Bonjour Discovery Engine (`NWBrowser`)
- Uses Apple's modern `Network.framework` (`NWBrowser`) with descriptor `.bonjour(type: "_applemusicremote._tcp", domain: "local.")`.
- Dynamically resolves IP, hostname, port, and TXT record metadata (containing Mac machine name and server version).
- Automatically pairs when only one Mac server is found on the local subnet.

### 4.2 Connection State Indicator Banner

| State | Badge Color | Pulsing Animation | Status Text & Action |
|---|---|---|---|
| **Connected** | `#34C759` (Apple Green) | Static Solid | *«Подключено к MacBook Pro»* (Ping: `4ms`) |
| **Connecting** | `#FF9F0A` (Apple Amber) | Slow Pulse (`1.2s`) | *«Поиск сервера в локальной сети...»* |
| **Reconnecting**| `#FF9F0A` (Apple Amber) | Fast Pulse (`0.6s`) | *«Связь потеряна. Повторная попытка (1/5)...»* |
| **Disconnected**| `#FF3B30` (Apple Red) | Static Solid | *«Сервер не найден. Проверьте Wi-Fi или QR-код»* |

---

## 5. Universal Track Action Sheet Modal (`⋯`)

Tapping `⋯` anywhere in the app (Now Playing, Library, Search, Queue) invokes the **Universal Track Action Sheet**.

```
+-------------------------------------------------------------------------+
|                                  [—]                                    |
|  +--------+  Midnight City                                              |
|  | 64x64  |  M83 • Hurry Up, We're Dreaming                             |
|  | [Art]  |  [ LOSSLESS ALAC 24-bit/48kHz ]                              |
|  +--------+                                                             |
|  ---------------------------------------------------------------------  |
|  [ ⏭ ]  Играть следующим                                (Play Next)     |
|  ---------------------------------------------------------------------  |
|  [ ➕ ]  В конец очереди                                 (Add to Queue)  |
|  ---------------------------------------------------------------------  |
|  [ 📻 ]  Создать станцию по треку                       (Create Station)|
|  ---------------------------------------------------------------------  |
|  [ 📥 ]  Добавить в медиатеку Mac                        (Add to Library)|
|  ---------------------------------------------------------------------  |
|  [ ❤️ ]  Добавить в «Любимые треки»                      (Favorite)      |
|  ---------------------------------------------------------------------  |
|  [ 💿 ]  Перейти к альбому                              (Go to Album)   |
|  ---------------------------------------------------------------------  |
|  [ 👤 ]  Перейти к артисту                              (Go to Artist)  |
|  ---------------------------------------------------------------------  |
|  [ 🔗 ]  Поделиться треком...                           (Share Track)   |
+-------------------------------------------------------------------------+
```

### Action Sheet Specification:
- **Presentation Detents**: `.presentationDetents([.fraction(0.48), .large])` with dynamic glass background.
- **Track Preview Header**: High-res thumbnail, title, artist, album, and format pill.
- **Context Awareness**:
  - If track is already in local library, `Добавить в медиатеку` is replaced with `Удалить из медиатеки`.
  - If track is already favorited, icon toggles to `heart.slash` (*«Удалить из любимых»*).
- **Haptic Confirmation**: Each item tap fires `.impact(.medium)` and executes the respective REST command with a toast notification banner.

---

## 6. Design Tokens, Typography & SwiftUI Guidelines

### 6.1 Color Palette & Tokens

```swift
extension Color {
    // MARK: - Core Accents
    static let amrRed = Color(hex: "#FA2D48")          // Apple Music Signature Red
    static let amrRose = Color(hex: "#FF375F")         // Secondary Vibrancy Accent
    static let amrCrimson = Color(hex: "#FF0844")      // Gradient Stop & Live Badge
    
    // MARK: - Dark Glass & Surfaces
    static let amrBackground = Color(hex: "#000000")   // Pure OLED Black
    static let amrSurfaceGlass = Color(white: 0.12).opacity(0.72)
    static let amrCardSurface = Color(white: 0.18).opacity(0.45)
    static let amrHairlineBorder = Color.white.opacity(0.14)
    
    // MARK: - Text Hierarchies
    static let amrTextPrimary = Color.white
    static let amrTextSecondary = Color(white: 0.72)
    static let amrTextTertiary = Color(white: 0.45)
    
    // MARK: - Status
    static let amrConnected = Color(hex: "#34C759")
    static let amrWarning = Color(hex: "#FF9F0A")
    static let amrError = Color(hex: "#FF3B30")
}
```

### 6.2 Typography System

| Token Name | Font & Weight | Size / Line Height | Usage |
|---|---|---|---|
| `LargeTitle` | SF Pro Rounded Bold | `34pt` / `41pt` | Primary screen headers («Медиатека», «Радио») |
| `Title2` | SF Pro Rounded Bold | `22pt` / `28pt` | Now Playing Track Title, Section Headers |
| `Headline` | SF Pro Display Semibold | `17pt` / `22pt` | Playlist titles, Search result track titles |
| `Body` | SF Pro Text Regular | `15pt` / `20pt` | Subtitles, Artist names, Settings labels |
| `Caption` | SF Pro Text Medium | `12pt` / `16pt` | Timestamps, durations, secondary badges |
| `Badge` | SF Pro Rounded Heavy | `10pt` / `12pt` | `LOSSLESS`, `LIVE` indicators (All Caps) |

### 6.3 Haptic Feedback Specification

```swift
enum AMRHaptics {
    static func buttonTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
    }
    static func playPauseToggle() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 1.0)
    }
    static func trackSkip() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.85)
    }
    static func favoriteSuccess() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func scrubberTick() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
    static func queueLift() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func queueDrop() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
```

---

## 7. Dynamic Island & Live Activity (Lock Screen) Architecture

`AppleMusicRemoteIOS` utilizes **ActivityKit** to project real-time playback state and remote controls to the Dynamic Island and Lock Screen.

```
+-------------------------------------------------------------------------+
|                      DYNAMIC ISLAND PRESENTATIONS                       |
|                                                                         |
| 1. COMPACT LEADING / TRAILING:                                          |
|    [ (Art) ]                      [ (|||) Waveform / 02:14 ]            |
|                                                                         |
| 2. EXPANDED PRESENTATION:                                               |
|    +-----------------------------------------------------------------+  |
|    | [ 44x44 Art ]  Midnight City                       (Mac Connected)|  |
|    |                M83 • Lossless ALAC                              |  |
|    |                                                                 |  |
|    | ●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━○ |  |
|    | 01:42                                                    -02:18 |  |
|    |                                                                 |  |
|    |         [⏮]               [ ▶ / ⏸ ]               [⏭]          |  |
|    +-----------------------------------------------------------------+  |
+-------------------------------------------------------------------------+
```

- **Interactive AppIntents**: Tapping Play/Pause or Skip in the Live Activity executes swift `AppIntent` handlers that dispatch lightweight background HTTP requests directly to the Mac server without launching the full app.

---

## 8. Production-Ready SwiftUI Component Implementations

### 8.1 Now Playing Component (`NowPlayingView.swift`)

```swift
import SwiftUI

public struct NowPlayingView: View {
    @ObservedObject var playerManager: PlayerManager
    @State private var isScrubbing = false
    @State private var scrubPosition: Double = 0
    @State private var showActionSheet = false
    @State private var showQualitySheet = false
    
    public init(playerManager: PlayerManager) {
        self.playerManager = playerManager
    }
    
    public var body: some View {
        ZStack {
            // Ambient Dynamic Mesh Glow Background
            AmbientGlowBackground(artworkImage: playerManager.currentArtwork)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Top Grabber & Header
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                
                Spacer()
                
                // Artwork Container with 3D Spring Physics
                ArtworkView(
                    artwork: playerManager.currentArtwork,
                    isPlaying: playerManager.isPlaying
                )
                .frame(width: 300, height: 300)
                .shadow(
                    color: Color.black.opacity(playerManager.isPlaying ? 0.4 : 0.2),
                    radius: playerManager.isPlaying ? 28 : 12,
                    y: playerManager.isPlaying ? 14 : 6
                )
                
                Spacer()
                
                // Track Metadata & Favorite Star
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        MarqueeText(
                            text: playerManager.currentTrack.title,
                            font: .system(size: 22, weight: .bold, design: .rounded)
                        )
                        .foregroundColor(.white)
                        
                        Text(playerManager.currentTrack.artist + " — " + playerManager.currentTrack.album)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        AMRHaptics.favoriteSuccess()
                        playerManager.toggleFavorite()
                    }) {
                        Image(systemName: playerManager.currentTrack.isFavorited ? "star.fill" : "star")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(playerManager.currentTrack.isFavorited ? .amrRed : .white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 28)
                
                // Audio Quality Badge
                Button(action: { showQualitySheet = true }) {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform")
                            .font(.system(size: 9, weight: .bold))
                        Text("LOSSLESS ALAC 24-bit/48kHz")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(0.5)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
                    .foregroundColor(.white.opacity(0.9))
                }
                
                // Interactive Scrubber Timeline
                VStack(spacing: 8) {
                    CustomSlider(
                        value: Binding(
                            get: { isScrubbing ? scrubPosition : playerManager.playbackPosition },
                            set: { scrubPosition = $0 }
                        ),
                        range: 0...(playerManager.currentTrack.duration > 0 ? playerManager.currentTrack.duration : 1),
                        onEditingChanged: { editing in
                            isScrubbing = editing
                            if !editing {
                                AMRHaptics.trackSkip()
                                playerManager.seek(to: scrubPosition)
                            }
                        }
                    )
                    .frame(height: 18)
                    
                    HStack {
                        Text(formatTime(isScrubbing ? scrubPosition : playerManager.playbackPosition))
                        Spacer()
                        Text("-" + formatTime(max(0, playerManager.currentTrack.duration - (isScrubbing ? scrubPosition : playerManager.playbackPosition))))
                    }
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.6))
                }
                .padding(.horizontal, 28)
                
                // Main Transport Controls
                HStack(spacing: 40) {
                    Button(action: {
                        AMRHaptics.trackSkip()
                        playerManager.previousTrack()
                    }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    Button(action: {
                        AMRHaptics.playPauseToggle()
                        playerManager.togglePlayPause()
                    }) {
                        Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 64, height: 64)
                    }
                    
                    Button(action: {
                        AMRHaptics.trackSkip()
                        playerManager.nextTrack()
                    }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.vertical, 8)
                
                // Volume Slider with Mute Toggle
                HStack(spacing: 14) {
                    Button(action: {
                        AMRHaptics.buttonTap()
                        playerManager.toggleMute()
                    }) {
                        Image(systemName: playerManager.isMuted ? "speaker.slash.fill" : "speaker.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(playerManager.isMuted ? .amrRed : .white.opacity(0.6))
                    }
                    
                    CustomVolumeSlider(volume: $playerManager.volume)
                    
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 28)
                
                // Footer Route & Action Sheet Trigger
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "laptopcomputer")
                        Text(playerManager.connectedHostName)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    
                    Spacer()
                    
                    Button(action: { showActionSheet = true }) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(8)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showActionSheet) {
            TrackActionSheet(track: playerManager.currentTrack, playerManager: playerManager)
                .presentationDetents([.fraction(0.48), .large])
                .presentationDragIndicator(.visible)
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
```

### 8.2 Radio Stations View (`RadioStationsView.swift`)

```swift
import SwiftUI

public struct RadioStationsView: View {
    @ObservedObject var playerManager: PlayerManager
    
    public var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    
                    // SECTION: ДЛЯ ВАС
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Для вас")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                PersonalStationCard(
                                    title: "Моя станция",
                                    subtitle: "Любимые треки и рекомендации",
                                    gradient: [Color(hex: "#FA233B"), Color(hex: "#FB5C74")],
                                    icon: "sparkles",
                                    action: { playerManager.playStation(id: "station_personal") }
                                )
                                
                                PersonalStationCard(
                                    title: "Станция открытий",
                                    subtitle: "Новая музыка по вашему вкусу",
                                    gradient: [Color(hex: "#7928CA"), Color(hex: "#FF0080")],
                                    icon: "safari.fill",
                                    action: { playerManager.playStation(id: "station_discovery") }
                                )
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    
                    // SECTION: ПРЯМОЙ ЭФИР
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Text("Прямой эфир")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            LivePulsingBadge()
                        }
                        .padding(.horizontal, 16)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                LiveStationCard(
                                    name: "Apple Music 1",
                                    subtitle: "Мировые премьеры 24/7",
                                    stationId: "station_am1",
                                    artwork: "am1_cover",
                                    action: { playerManager.playStation(id: "station_am1") }
                                )
                                
                                LiveStationCard(
                                    name: "Apple Music Hits",
                                    subtitle: "Культовые хиты 80-х, 90-х, 00-х",
                                    stationId: "station_hits",
                                    artwork: "am_hits_cover",
                                    action: { playerManager.playStation(id: "station_hits") }
                                )
                                
                                LiveStationCard(
                                    name: "Apple Music Country",
                                    subtitle: "Современное и классическое кантри",
                                    stationId: "station_country",
                                    artwork: "am_country_cover",
                                    action: { playerManager.playStation(id: "station_country") }
                                )
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    
                    // SECTION: ЖАНРОВЫЕ СТАНЦИИ
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Жанровые станции")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                            GenreStationCell(title: "Chill & Lo-Fi", id: "station_chill", colors: [Color(hex: "#00B4DB"), Color(hex: "#0083B0")]) { playerManager.playStation(id: "station_chill") }
                            GenreStationCell(title: "Поп-хиты", id: "station_pop", colors: [Color(hex: "#FA2D48"), Color(hex: "#FF6B8B")]) { playerManager.playStation(id: "station_pop") }
                            GenreStationCell(title: "Рок & Альтернатива", id: "station_rock", colors: [Color(hex: "#E65100"), Color(hex: "#FF9800")]) { playerManager.playStation(id: "station_rock") }
                            GenreStationCell(title: "Хип-Хоп & Рэп", id: "station_hiphop", colors: [Color(hex: "#4A148C"), Color(hex: "#7B1FA2")]) { playerManager.playStation(id: "station_hiphop") }
                            GenreStationCell(title: "Электроника", id: "station_electronic", colors: [Color(hex: "#00695C"), Color(hex: "#00BFA5")]) { playerManager.playStation(id: "station_electronic") }
                            GenreStationCell(title: "Deep House", id: "station_deephouse", colors: [Color(hex: "#880E4F"), Color(hex: "#D81B60")]) { playerManager.playStation(id: "station_deephouse") }
                            GenreStationCell(title: "Джаз & Блюз", id: "station_jazz", colors: [Color(hex: "#37474F"), Color(hex: "#78909C")]) { playerManager.playStation(id: "station_jazz") }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 120)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Радио")
        }
    }
}
```

### 8.3 Bonjour Server Discovery Manager (`BonjourDiscoveryManager.swift`)

```swift
import Foundation
import Network
import Combine

public final class BonjourDiscoveryManager: ObservableObject {
    @Published public var discoveredServers: [ServerHost] = []
    @Published public var activeConnectionState: ConnectionState = .disconnected
    
    private var browser: NWBrowser?
    private let serviceType = "_applemusicremote._tcp"
    
    public enum ConnectionState {
        case connected(host: String, ip: String)
        case connecting
        case reconnecting(attempt: Int)
        case disconnected
    }
    
    public struct ServerHost: Identifiable, Hashable {
        public let id: String
        public let name: String
        public let hostName: String
        public let port: Int
        public let ipAddress: String
        public var pingMs: Int
    }
    
    public init() {
        startBrowsing()
    }
    
    public func startBrowsing() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        
        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: "local.")
        let newBrowser = NWBrowser(for: descriptor, using: parameters)
        
        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                self?.handleDiscoveredResults(results)
            }
        }
        
        newBrowser.start(queue: .main)
        self.browser = newBrowser
    }
    
    private func handleDiscoveredResults(_ results: Set<NWBrowser.Result>) {
        var servers: [ServerHost] = []
        for result in results {
            if case let .service(name, _, _, _) = result.endpoint {
                servers.append(ServerHost(
                    id: name,
                    name: name,
                    hostName: "\(name).local",
                    port: 8080,
                    ipAddress: "Resolving...",
                    pingMs: 4
                ))
            }
        }
        self.discoveredServers = servers
    }
}
```

---

## 9. Verification & Acceptance Criteria Checklist

| Category | Requirement | Verification Standard |
|---|---|---|
| **Now Playing** | Fluid Mesh Ambient Background | Real-time color extraction, 60fps blur animation, no frame drops during track transitions. |
| **Now Playing** | Lossless Badge & Scrubber | ALAC badge correctly reflects streaming bit depth; scrubber responds smoothly with `-MM:SS` remaining calculation. |
| **Radio** | Curated & Live AM1 Stations | One-tap playback immediately triggers Mac daemon via `/api/play/station`; live badge pulses at `1.2s` intervals. |
| **Library** | iTunes Remote Parity | Alphabetical fast scrubber jumps precisely to section headers with haptic ticks. |
| **Search** | Tri-Scope Filtering | Scope filter switches between `Все`, `Медиатека`, `Apple Music` with 200ms debounce. |
| **Queue** | Reorder & Deletion | Native drag reordering sends updated order to `/api/player/queue`; swipe deletion removes items cleanly. |
| **Bonjour** | Zero-Config Auto Pairing | Discovers Mac servers advertising `_applemusicremote._tcp` on the local Wi-Fi network within `< 2.0s`. |
| **Action Sheet**| 6-Action Modal Trigger | Instant modal response with track header, Play Next, Add to Queue, Station, and Favorite toggling. |
