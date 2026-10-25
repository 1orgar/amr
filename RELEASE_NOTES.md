# Apple Music Remote 2.2.0 — "Chopin"

Major release **v2.2.0 ("Chopin")** introduces an interactive audiophile Signal Path modal, real-time DAC device selection directly from the Web remote, automated Apple ID storefront detection with first-run authentication, catalog search deduplication, a comprehensive transport control overhaul (flawless play/pause responsiveness, zero-delay toggle, and keyboard controls), and expands automated test coverage to 146 unit and integration tests.

---

### ✨ What's New & What Changed:

#### 1. 🎛️ Audiophile Signal Path & DAC Switcher (Тракт сигнала)
* **Interactive Signal Path Modal**:
  - Visualized audio chain inspection displaying every node in the pipeline:
    1. **Source**: Audio stream format, bit depth, and native sample rate (e.g., *ALAC Lossless 24-bit / 192.0 kHz*).
    2. **AMR Engine**: Active volume lock (`0.0 dB FS`), zero-DSP processing, and mixer bypass status.
    3. **Hardware Output**: Currently connected external DAC / macOS CoreAudio output device and active hardware sampling rate.
* **In-App DAC Selector**:
  - Switch active CoreAudio output devices and DACs directly from the Web interface without opening macOS System Settings.
* **Persistent Status Pill**:
  - Real-time DAC and stream format indicator in Now Playing view and desktop navigation header.

#### 2. 🆔 Seamless Apple ID Auto-Detection & Storefront Sync
* **Automatic Storefront Resolution**:
  - Automatically queries the active Apple ID storefront from macOS Apple Music settings (`MusicKitManager.getUserStorefront()`).
  - Removed manual country picker from home navigation in favor of auto-synced regional storefronts (`us`, `ru`, etc.).
* **First-Run Auth Modal**:
  - Clean, dedicated authentication modal presented when an Apple Music User Token is needed, guiding the user to sign in securely via MusicKit JS before interacting with catalog features.
  - Compact Apple ID account badge in the header displaying signed-in status with one-click sign out.

#### 3. 🔍 Search Deduplication
* **Catalog Result Sanitization**:
  - Eliminated duplicate track entries in search results caused by overlapping standard, deluxe, and remastered album editions.
  - Clean, streamlined track listings (e.g. Guano Apes search reduced from 50 redundant items to 39 unique tracks).

#### 4. ⏯️ Transport Control & Pause Button Overhaul
* **Pause / Play Reliability**:
  - Fixed an unhandled frontend TypeError where obsolete DOM element references aborted `togglePlayPause()` before the WebSocket command was dispatched.
  - Removed `.btn-loading` from transport play/pause buttons, ensuring instant, non-blocking click response and keeping SVG icons visible.
  - Eliminated backend race condition in `PlaybackTransportController.pause()` where rapid state checks could mistakenly trigger `playpause` and resume playback.
  - Added strict `isUserPaused` intent preservation in `PlayerStatusEngine` to prevent transient AppleScript queries from prematurely flipping state back to `playing`.
  - Immediate optimistic status broadcasts for `pause`, `play`, `stop`, and `play_pause`.
* **Desktop Spacebar Control**:
  - Global Spacebar shortcut toggles Play/Pause when focus is not on input elements.
* **Smart Navigation Tweaks**:
  - Rapid double-press on Previous Track (< 1.5s) immediately skips to the previous song in queue instead of rewinding to 0:00.
  - Single-step Next skip in custom queues preventing double-skipping.

#### 5. 🧪 Test Suite Expansion (146 Tests + E2E)
* **146 Automated Swift Tests** (`AppleMusicRemoteMacTests`, 100% pass rate):
  - Added `PlaybackTransportControllerTests` covering `pause()`, `play()`, `stop()`, and `playPause()` toggles.
  - Validated state store resetting across test cases.
* **End-to-End Automated Testing**:
  - Added `test_10_play_pause_transport_control` in `test_amr_e2e.py` verifying bidirectional play/pause cycling, WebSocket status events, and native macOS `Music.app` state via AppleScript.
