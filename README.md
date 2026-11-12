# Apple Music Remote (AMR)

**English** | [🇷🇺 Русская версия](README_RU.md)

[![CI](https://github.com/1orgar/amr/actions/workflows/ci.yml/badge.svg)](https://github.com/1orgar/amr/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/1orgar/amr)](https://github.com/1orgar/amr/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-black.svg?logo=apple)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Architecture: Universal 2](https://img.shields.io/badge/arch-arm64%20%7C%20x86__64-blue.svg)](https://developer.apple.com/documentation/apple-silicon)

**Apple Music Remote (AMR)** is a high-performance native macOS server and modern remote control for **Apple Music**. Crafted specifically for audiophiles and discerning listeners: audio streams directly from your Mac to an external DAC, delivering true **Bit-Perfect** reproduction without system resamplers, DSP truncation, or loss of fidelity.

---

## ✨ Key Features

### 🎧 Bit-Perfect Audiophile Audio Output (CoreAudio)
* **Automatic DAC Sample Rate Synchronization**: Instant hardware switching between 44.1, 48, 88.2, 96, 176.4, and 192 kHz to match the source track's native rate in Music.app bit-for-bit.
* **100% Volume Lock Mode**: Keeps macOS / Music.app software volume pegged at 100% to eliminate digital volume dithering and word-length degradation.
* **Format Pre-Inspection, Strict Format Lock & AAC vs ALAC Detection**: Pre-inspects stream format parameters (`sampleRate` and `bitDepth`), strictly locks mid-playback DAC format, and distinguishes compressed AAC (`16-bit / 44.1 kHz`, Lossy indicator) from ALAC Lossless / Hi-Res (`24-bit / up to 192 kHz`).
* **Real-Time FFT Spectral Hi-Res Verifier (`SpectralIntegrityAnalyzer`, `vDSP`)**: Performs 4096-point Hann-windowed FFT analysis and LSB bit-depth verification directly on the PCM stream to detect fake upsampled tracks (`TRUE HI-RES`, `FAKE HI-RES • 22K CUT`, `UPSAMPLED 48K`, `16-BIT PADDED`, `CD LOSSLESS`) right inside the Signal Path modal, with persistent two-tier validation caching for local (`persistentID`) and cloud (`catalogId`) tracks.
* **DAC Muting Guard & Click-Free Switcher**: Optional three-stage micro-muting protection during hardware sample rate transitions (`Pre-Mute → Clock Lock → Unmute`) to eliminate relay clicks on external DACs.
* **Audiophile Signal Path Inspection (Тракт сигнала)**: Interactive Roon-style modal detailing every stage of the audio chain: Source stream (codec, bit depth, sample rate), Spectral Integrity Verifier, AMR Bit-Perfect Engine (`0.0 dB FS`, zero DSP), and active Hardware Output DAC or BluOS streamer.
* **In-App DAC Switcher**: Quickly switch between connected external DACs, CoreAudio output devices, and BluOS renderers directly from the Web remote without auto-starting playback when paused.
* **Optional Web Volume Control, External Amplifier TCP Bridge (`ExternalAmpTCPController`) & Hardware Bit-Perfect Normalization (`AppleSoundCheckService`)**:
  * When 100% volume lock is turned off, the Web UI provides a software volume slider.
  * When **100% Bit-Perfect Volume Lock** is enabled, the dedicated **Amplifier** settings tab allows direct hardware volume & mute control over text-based TCP sockets (**Rotel `:9590`**, **Denon / Marantz `:23`**, **Hegel `:50001`**, **NAD `:30000`**, **Lyngdorf `:84`**) with live status polling, configurable maximum volume cap (`1–100%`), zero-jump & max-volume hardware guards, connection diagnostics, an `AMPLIFIER` node in the Signal Path modal, and TV Mode volume control (inline slider on the button row, vertical up/down swipe gesture, and a precision zoom magnifier loupe).
  * **Hardware Bit-Perfect Track Normalization (`AppleSoundCheckService` + Non-Linear Low-Volume Smart Curve)**: Extracts official Apple `iTunNORM` metadata from local files and Apple Music catalog `.m4a` headers (or computes real-time perceptual `ITU-R BS.1770` K-weighted loudness via `SpectralIntegrityAnalyzer` for tracks without tags) and adjusts the external amplifier's hardware attenuator over TCP while keeping macOS CoreAudio output 100% Bit-Perfect (`0.0 dBFS`). Includes a toggleable **Smart Low-Volume Normalization (`< 40%`)** setting tailored for non-linear amplifier attenuators (Rotel, etc.) and human equal-loudness perception at quiet listening levels.
* **Real-Time DAC Badge**: Continuous stream format and hardware DAC rate indicators across all views (Now Playing header, desktop split view, and mobile devices).

### 📺 StandBy / TV Mode, 📊 32-Band RTA & 🌈 WLED DDP Ambilight
* **Fullscreen Living Room TV Mode**: Large album artwork, Apple Music **Motion Covers** (looping HLS video artwork), distance-readable typography, dynamic Ambilight background gradients, and per-session browser mode persistence.
* **32-Band Live RTA Spectrum Analyzer**: Toggleable `RTA` button in TV Mode renders a real-time 60fps 32-band logarithmic spectrum analyzer (`20 Hz – 96 kHz`) highlighting both audible frequencies and ultrasonic Hi-Res content (`> 22.05 kHz`).
* **Fullscreen TV Library Overlay**: Dedicated **Library** button in TV Mode opens a fullscreen vertically scrollable grid with large 1:1 square tiles for Personal Stations (*My Station*, *Discovery Station*, *Feel Good*, *Heavy Rotation*) and all local library playlists.
* **Hardware WLED Ambilight via DDP (UDP Port 4048)**: Ultra-low-latency (`< 2 ms`, 40 FPS) 16-zone bilinear album cover palette streaming with `γ = 2.4` gamma correction and 5 real-time audio-reactive modes driven directly by `AudioProcessTapService` (*Rhythm Sine Wave*, *3-Band Spectral EQ*, *Symmetric Center VU Pulse*, *Harmonic Resonance*, and *Static Cover Palette*), plus smooth 2.5s pause fade-out and background Heartbeat OFF.

### 📖 Digital Album Booklets & Track-by-Track Liner Notes (`DigitalBookletService` + `PDFKit`)
* **Multi-Page Interactive Booklet Reader**: Opens sequentially in place of the right pane on Desktop / Tablet Landscape and fullscreen on TV / Mobile Portrait.
* **Comprehensive Album History & Credits**: Combines Apple Music editorial notes, automatic multilingual Wikipedia fallback (`RU / EN`), track-by-track guides, full studio session credits (musicians, instruments, producers, mixing/mastering engineers, composers), and native high-resolution rendering of local `.pdf` digital booklets via `PDFKit`.

### 📡 BluOS & Network Streaming (Lossless Stream Relay)
* **Direct Audio Process Tap (`AudioProcessTapService`)**: Directly taps Music.app's audio stream via native CoreAudio Process Tap API (`AudioHardwareCreateProcessTap`) on macOS Sonoma/Sequoia without virtual audio cables, without modifying system sound output, and without muting Mac speakers.
* **Bit-Perfect BluOS Streaming**: Streams pure LPCM / WAV up to 192 kHz / 24-bit Hi-Res Lossless (and true 16-bit / 44.1 kHz for AAC) directly to Bluesound (NODE, POWERNODE) and BluOS-compatible streamers.
* **Bidirectional Transport Sync**: Seamless real-time state synchronization (Play, Pause, Seek, Volume) between BluOS hardware, official BluOS app, and Apple Music Remote.

### 📱 Premium Web Remote (PWA) & Apple Music Personalization
* **Personal Recommendations, Stations & Mixes**: Full integration with Apple Music `GET /v1/me/recommendations`, personal stations, and weekly mixes paired with GPU-accelerated **60fps generative SVG/CSS plaques** (*My Station*, *Discovery Station*, *Feel Good*, *Heavy Rotation*, *New Music Mix*, *Chill Mix*, *Get Up! Mix*, *Friends Mix*, and *Artist Stations*).
* **OLED Monochrome Aesthetic**: Pure black `#000000`, hardware-accelerated transitions, visual focus strictly on album artwork with zero clutter.
* **Zero-Latency Transport Controls & Zero-Stall Poller**: Non-blocking Play/Pause toggle with optimistic UI response, two-tier lightweight IPC polling (~15 ms), rapid double-click Previous skip, and desktop Spacebar hotkey.
* **Robust Cloud Album & Search Queue**: Complete multi-track queuing for cloud albums and playlists across all regional storefronts without stopping after track 1 or falling back to Autoplay radio; automatic background cleanup of temporary cloud playlists.
* **High-Speed Artwork Disk Cache (`ArtworkDiskCache`)**: Two-tier memory and persistent disk LRU caching for instant cover art delivery.
* **Automated Apple ID & Storefront Detection**: Detects your active regional storefront directly from macOS settings, eliminating manual country selectors.
* **Clean Catalog Search with Deduplication**: Smart filtering of duplicate releases and album versions for clean, fast search results.
* **Intuitive Touch Gestures**: Swipe artwork left/right to skip tracks; swipe down to collapse Now Playing into a floating mini-player.
* **60fps Phase-Locked Scrubber**: Local optimistic timeline tracking for jitter-free, seamless timecode scrubbing.
* **One-Click Radio Stations**: Instantly generate personal Apple Music stations based on the current track or artist directly from the player (📡).
* **Favorites Synchronization**: Mark tracks as Favorite ("Favorite Songs") in Apple Music with instant visual and haptic confirmation.
* **Charts, Trending, Playlists & Save Queue to Library**: Full access to Apple Music editorial charts, full playlist tracklists, one-click **"+ Add to Library"** synchronization for any catalog or personal playlist, and a **"+ Save as Playlist"** button in the Queue header to save any active queue or Infinite AI Wave as a new Apple Music playlist.
* **PWA Client Device Authorization, QR Invite Sharing & Per-Device Lock Screen Controls (`ClientDeviceManager`)**: Generates a persistent client UID (`HTTP Cookie` + `localStorage` + `CacheStorage`) requiring one-click authorization in macOS Settings before Apple ID checks. Includes per-device `MediaSession` Lock Screen & Dynamic Island toggles (configurable per device in macOS Settings or via the Signal Path-style `AMR v2.5.0` badge modal showing the latest Git commit and a **"Share Access (QR)"** invite link `?invite=<token>` for instant camera pairing).
* **Automatic Bilingual UI Localization (`RU / EN`)**: Automatically switches both the Web UI (PWA) and native macOS app (Menu Bar + Settings window) to English for non-Russian device locales while preserving Russian for `ru` locales.
* **On-Device AI Functions on Apple Neural Engine (`NativeMusicCuratorService` + `ArtworkService` — `FoundationModels`, `NaturalLanguage` 512-D `NLEmbedding`, `Vision` Saliency)**: Controlled by a single unified **Native AI Functions (Apple Neural Engine)** switch in macOS Settings (automatically hidden and disabled on Intel `x86_64` Macs). Includes the semantic **AI Prompt Curator** (`✨ AI Curator` in Search & monochrome fullscreen **AI Tag Cloud** in StandBy / TV Mode), **Infinite AI Wave** (seamless background auto-appending of fresh tracks without repeats), **Semantic Cosine Flow Queue Ordering (`NLEmbedding` 512-D)**, **AI Mix from Current Track (`✨`)** in the `•••` menu and TV mode, **Pinned AI Prompts (`★ Favorite Vibes`)**, and **Neural Vision Saliency Artwork Palette (`VNGenerateAttentionBasedSaliencyImageRequest`)** for vivid TV Ambilight and 16-zone WLED strips.

### 📻 UPnP / DLNA MediaRenderer (Home Assistant Integration)
* Full support for **UPnP A/V MediaRenderer (AVTransport / RenderingControl)** standards.
* Auto-discovery across local networks using **SSDP Discovery**.
* **Toggleable Local MediaRenderer**: Configurable option in Settings and Menu Bar to enable or disable the local AMR UPnP renderer when dedicated network streamers (BluOS) or Home Assistant are active.
* Seamless integration with **Home Assistant**, smart speakers, and DLNA controllers: Play, Pause, Stop, Seek, and Volume control.
* Built-in **Audio Ducking** for voice assistants (TTS announcements softly attenuate music and automatically restore level).

### 🍏 100% Native macOS Menu Bar App
* Built in Swift using native frameworks (`CoreAudio`, `Network.framework`, `ScriptingBridge`, `ServiceManagement`).
* **MusicAppLifecycleManager**: Proactive watchdog monitoring Music.app and IPC responsiveness, recovering state automatically from app hangs.
* Standalone **Universal 2** binary (`arm64` Apple Silicon + `x86_64` Intel).
* Menu bar companion: Music.app status, audio device and sample rate picker, settings window, and instant QR code display for pairing mobile devices.
* Optional **Launch at Login** support.

---

## 🏛 Architecture

```
                        ┌──────────────────────────────────────┐
                        │      Apple Music Remote (Mac)        │
                        │                                      │
  📱 iPhone / iPad      │  ┌────────────────────────────────┐  │      🎧 External DAC
  💻 Web / PWA          │  │     CoreAudio Device Manager   ├──┼────► (Bit-Perfect
  (WebSocket / HTTP) ──►│  │   (Auto-Rate 44.1 - 192 kHz)   │  │       44.1-192 kHz)
                        │  └────────────────────────────────┘  │
                        │                                      │
  🏠 Home Assistant     │  ┌────────────────────────────────┐  │      🎵 Apple Music
  📻 UPnP / DLNA    ───►│  │  ScriptingBridge + MusicKit API├──┼────►  (Direct Mac
                        │  └────────────────────────────────┘  │       playback)
                        └──────────────────────────────────────┘
```

---

## 🚀 Installation

### Pre-Built DMG
1. Go to the [Releases](https://github.com/1orgar/amr/releases) page.
2. Download `AppleMusicRemoteMac-Universal.dmg`.
3. Open the disk image and drag `Apple Music Remote.app` into `/Applications`.
4. Launch the app. A 🎵 icon will appear in your macOS menu bar.
5. On first launch, grant permission to control `Music.app` in the macOS Accessibility / Automation prompt.

---

## 🛠 Building from Source

### Requirements
* macOS 14.0 (Sonoma) or newer
* Xcode 15.0+ or Command Line Tools (`xcrun`)
* Swift 5.9+

### Clone the Repository
```bash
git clone https://github.com/1orgar/amr.git
cd amr
```

### Running Tests

#### Swift Unit Tests (262 tests):
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path AppleMusicRemoteMac
```

#### End-to-End Integration Tests (Python):
```bash
python3 -m unittest discover -s tests
```

### Build for Current Mac
```bash
./AppleMusicRemoteMac/build_app.sh
```
The compiled bundle will be available at `AppleMusicRemoteMac/build/AppleMusicRemoteMac.app`.

### Build Universal DMG (Intel + Apple Silicon)
```bash
./build_universal_dmg.sh
```
This script compiles both `arm64` and `x86_64` targets, merges them via `lipo`, applies code signing, and creates `AppleMusicRemoteMac-Universal.dmg`.

---

## 🔌 API & Protocols

The server hosts HTTP and WebSocket services on port `8080` (configurable), and UPnP MediaRenderer on port `8090`.

### WebSocket Protocol (`ws://<mac-ip>:8080`)

All messages use JSON:
```json
{
  "action": "play_pause",
  "params": {},
  "id": "req-1"
}
```

#### Available Actions:
| Action | Parameters | Description |
| :--- | :--- | :--- |
| `play` | — | Resume playback |
| `pause` | — | Pause playback |
| `play_pause` | — | Toggle play / pause |
| `next` | — | Next track |
| `previous` | — | Previous track |
| `seek` | `{"position": 125.5}` | Seek to timestamp in seconds |
| `set_volume` | `{"volume": 80}` | Set volume (0–100%) |
| `set_lock_volume_100` | `{"enabled": true}` | Enable / disable 100% volume lock |
| `set_shuffle` | `{"enabled": true}` | Toggle shuffle mode |
| `set_repeat` | `{"mode": "off"\|"one"\|"all"}` | Set repeat mode |
| `favorite` | — | Toggle favorite status for current track |
| `play_station` | `{"type": "track"\|"artist", "title": "...", "artist": "..."}` | Start personalized Apple Music station |
| `search_and_play` | `{"query": "Depeche Mode"}` | Search catalog and start playback immediately |
| `get_queue` | — | Fetch current playback queue |
| `get_playlists` | — | Fetch user library playlists |

### HTTP REST API

* `GET /api/status` — Current playback status (`PlayerStatus` JSON).
* `POST /api/media` — Dispatch media transport commands (`endpoint` & `params`).
* `POST /api/duck` — Softly attenuate volume (for Home Assistant TTS announcements).
* `POST /api/unduck` — Restore pre-duck volume level.
* `GET /api/artwork/track?id=...` — Retrieve track artwork in native resolution.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
