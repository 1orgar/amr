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
* **Optional Web Volume Control**: When volume lock is turned off via menu bar settings, the Web UI automatically displays a smooth volume slider (with an instant Mute button) for setups lacking a hardware volume pot.
* **Real-Time DAC Badge**: Continuous stream format and hardware DAC rate indicators across all views (Now Playing header, desktop split view, and mobile devices).

### 📱 Premium Web Remote (PWA)
* **OLED Monochrome Aesthetic**: Pure black `#000000`, hardware-accelerated transitions, visual focus strictly on album artwork with zero clutter.
* **Intuitive Touch Gestures**: Swipe artwork left/right to skip tracks; swipe down to collapse Now Playing into a floating mini-player.
* **60fps Phase-Locked Scrubber**: Local optimistic timeline tracking for jitter-free, seamless timecode scrubbing.
* **One-Click Radio Stations**: Instantly generate personal Apple Music stations based on the current track or artist directly from the player (📡).
* **Favorites Synchronization**: Mark tracks as Favorite ("Favorite Songs") in Apple Music with instant visual and haptic confirmation.
* **Charts, Trending & Library**: Full access to Apple Music editorial charts, user library playlists, recent releases, and instant cloud catalog search.
* **Lock Screen & MediaSession**: Background audio playback integration on iOS and Android with lock screen artwork and transport controls.

### 📻 UPnP / DLNA MediaRenderer (Home Assistant Integration)
* Full support for **UPnP A/V MediaRenderer (AVTransport / RenderingControl)** standards.
* Auto-discovery across local networks using **SSDP Discovery**.
* Seamless integration with **Home Assistant**, smart speakers, and DLNA controllers: Play, Pause, Stop, Seek, and Volume control.
* Built-in **Audio Ducking** for voice assistants (TTS announcements softly attenuate music and automatically restore level).

### 🍏 100% Native macOS Menu Bar App
* Built in Swift using native frameworks (`CoreAudio`, `Network.framework`, `ScriptingBridge`, `ServiceManagement`).
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

#### Swift Unit Tests (132 tests):
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
