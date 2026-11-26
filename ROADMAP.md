# Apple Music Remote (AMR) — Project Roadmap

Strategic engineering roadmap for **Apple Music Remote (AMR)** — the native audiophile CoreAudio server, 64-bit Studio DSP engine, and pure OLED remote control for Apple Music on macOS.

---

## 🧭 Architectural Philosophy

1. **Uncompromising Bit-Perfect Audio & Isolated 64-Bit Studio DSP**:
   - Direct CoreAudio HAL control without intermediate OS software mixers or resamplers by default (`100% Bit-Perfect Passthrough`).
   - Strict hardware sample-rate synchronization (`44.1 – 192 kHz` in Passthrough and up to `768 kHz / DSD512 DoP` in exclusive `Hog Mode`) guarded by automatic 3-stage USB DAC capability verification and 1-click hardware bypass.
   - Enforced `100% Volume Lock` in macOS paired with external hardware volume attenuation over TCP (`Rotel`, `Denon / Marantz`, `Hegel`, `NAD`, `Lyngdorf`) and lossless streamers (`BluOS / DLNA`) for zero word-length degradation.
2. **Headless Mac mini Autonomy**:
   - 24/7 background operation without requiring an open GUI window or brittle Accessibility UI scripting.
   - Native `ScriptingBridge`, AppleScript IPC, `AudioProcessTapService`, and official Apple MusicKit REST API integration with zero user library pollution.
3. **Pure OLED Minimalism & Signal Transparency**:
   - Pitch-black `#000000` Web PWA with optimistic 60 fps PLL-locked scrubbing, tactile controls, and RAM-cached `gzip` delivery.
   - Roon-inspired Signal Path transparency, live mastering telemetry (`TT DR / EBU R128 LUFS / True Peak / 4x ISP / Phase`), and multi-page digital album booklets.

---

## 📊 Release Summary Matrix

| Release | Codename | Status | Key Deliverables |
| :--- | :--- | :--- | :--- |
| **v2.1.0** | **"Beethoven"** | ✅ Completed | 1. Queue navigation (`Smart Prev`, transition isolation)<br>2. Hardware `100% Volume Lock` with drift protection<br>3. Core unit test suite & Universal 2 build pipeline |
| **v2.2.0** | **"Chopin"** | ✅ Completed | 1. Autonomous catalog queue controller (`Smart Auto-Advance`)<br>2. Interactive Apple ID authorization (`Music-User-Token`)<br>3. Signal Path Inspector v1 & remote Web UI DAC switcher |
| **v2.3.0** | **"Bach"** | ✅ Completed | 1. Bit-Perfect BluOS streaming via `AudioProcessTapService` (`24/192`)<br>2. Stream format pre-inspection & strict `Format Lock`<br>3. `MusicAppLifecycleManager` watchdog & persistent `ArtworkDiskCache` |
| **v2.4.0** | **"Brahms"** | ✅ Completed | 1. Apple Music personalization: Listen Now, mixes & personal stations<br>2. Fullscreen StandBy / TV Mode (Motion Covers) + 40 FPS WLED DDP Ambilight<br>3. Anti-Stutter, AAC vs. ALAC detection & lightweight Zero-Stall IPC poller |
| **v2.5.0** | **"Liszt"** | ✅ Completed | 1. `vDSP` FFT Spectral Hi-Res Verifier + persistent cache + 32-band TV RTA<br>2. `DAC Muting Guard` click-free sample-rate relay switcher<br>3. 📖 Multi-page Digital Album Booklets (`PDFKit`) + Studio Credits<br>4. 🔐 PWA Device Authorization, QR Invite sharing & per-device Lock Screen<br>5. ➕ Playlist management & Save AI Queue as Playlist + `EN / RU` localization<br>6. 🪄 On-device Apple Neural Engine AI (`FoundationModels` + 512-D `NLEmbedding` + `Vision` Saliency): Prompt Curator, Infinite AI Wave & semantic queue flow<br>7. 🔊 External Amplifier TCP volume bridge + hardware `iTunNORM` SoundCheck |
| **v3.0.0** | **"Wagner"** | ✅ **Released** | 1. 🎛 Hybrid 64-Bit Studio DSP + `CoreAudio Exclusive Hog Mode`: `DSD64–DSD512 DoP (7EC + Trellis)`, `2x–16x` synchronous upsampling up to `768 kHz` (`AMX FP64` 65k / `Metal df64` 262k Sinc + `HQ PCM NOS` with `LNS15`), 3-stage USB DAC verifier & DSP presets<br>2. 📐 In-browser iPhone / iPad Room Acoustic Measurement (`RoomAcousticService`) + 64-bit 8-band `Auto-PEQ` toward Harman Target<br>3. 📊 Live Mastering Telemetry (`TT DR`, `EBU R128 LUFS / True Peak`, `4x ISP`, `Phase`) + Pre-DSP Restoration (`MasteringDeClipper` + `Weiss Dynamic De-Esser`) + `Audiophile Late-Night DRC` & `Repeat One`<br>4. ☁️ Two-way **iCloud Drive** sync (DSP presets, DR/SoundCheck caches, Room PEQ), granular PWA device permissions, Zero-Keychain `AES-256-GCM` vault, Apple Notarized Universal DMG & `< 50 ms` `BluOS / DLNA` volume<br>5. 🌉 **`Sonic Bridge`** 512-D `SLERP` geodesic AI trajectory router<br>6. 🗂 Dedicated **Playlists** vs. 4-tab **Library** (`Recent / Artists / Albums / Songs`), full library deletion, Album Completeness Detector & configurable TV Library<br>7. ⚡ Sub-second (`0.5–0.9 s`) Direct Cloud ALAC/Hi-Res engine with single reusable staging buffer, zero library pollution & RAM `gzip` asset cache |
| **v3.1.0** | **"Schumann"** | 📋 Planned | 1. 🛡 `Stereo Master Enforcement` (prevents hidden 48 kHz Dolby Atmos downmixes on stereo DACs)<br>2. ⬆️ Linn Kazoo-style live queue mutations (`Play Next`, `Add to Queue`, `↑`, `×`), ⏸ `Stop After Current Track` & 1-tap Artist deep-links<br>3. 👎 `DislikedTracksStore` (instant skip + AI/Radio/Search exclusion) + `±1%` micro-step amplifier volume & TCP `Standby / Wake`<br>4. 🎤 Time-synced `TTML / LRC` karaoke lyrics + 📖 clickable Roon-style interactive booklet credits |
| **v3.2.0** | **"Mendelssohn"** | 📋 Planned | 1. 🎸 Real-time `SoundAnalysis` Neural Engine instrument & vocal detector<br>2. 🧠 `CloudTasteProfileService` (`75% Taste / 25% Discovery` across OST, Metal, Electronic, Jazz & Classical)<br>3. 🕒 Recent AI Waves history & live `NLEmbedding` prompt expansion chips<br>4. 📈 Roon-style `Waveform Seekbar`, TV `Up Next` banner & remote hotkeys<br>5. 🌌 `3D Cover Flow & 4K Album Wall` + 👥 QR Guest `Party Mode` |
| **v3.3.0** | **"Tchaikovsky"** | 📋 Planned | 1. 🎚 `Discovery Slider` (*Charts ↔ Deep Cuts*) + clean studio edition filter<br>2. 🎻 `Multi-Part Work Grouping & Gapless Live Guard` + Camelot BPM harmonic queue<br>3. 🌅 Synchronized `Sleep Timer & WLED DDP Sunset Fade`<br>4. 🎙️ Natural-language command intent parser in Search |
| **v3.4.0** | **"Grieg"** | 📋 Planned | 1. 🔍 Multi-faceted `Roon Focus` filter builder (`+ Include / − Exclude` by `DR`, sample rate, decade, genre) + `Smart Bookmarks`<br>2. 📡 Native **ESPHome** I2S DAC HTTP WAV streaming<br>3. 🔀 Lossless Stream Relay (`FLAC / LPCM` up to `24/192`) for **WiiM** & **UPnP AV**<br>4. 🏡 Two-way **Home Assistant** MQTT / WebSocket bridge + Smart Amp power trigger<br>5. 🖥 Quick launch for `★ Favorite Vibes` & `AI Track Mix` in the macOS Menu Bar |
| **v3.5.0** | **"Debussy"** | 📋 Planned | 1. ⚡ `Zero-Jitter RAM Buffer (Memory Play)` via non-pageable `mlock` RAM<br>2. 🎚 `Per-Device & Per-Headphone Volume Memory` + `Safe Startup Volume & Jump Guard`<br>3. 🎛 Output profiles, `0°/180° Phase Invert` & `0.1 dB` L/R channel balance<br>4. 🎧 Studio `Bauer / Meier Natural Crossfeed` for headphones (with Bit-Perfect bypass)<br>5. 🌙 Equal-loudness `ISO 226 / RME Loudness Contour` |
| **v3.6.0** | **"Ravel"** | 📋 Planned | 1. 🧬 Local SQLite `Sonic Object Graph` (*Composition ↔ Performance ↔ Credits ↔ Acoustic Passport*)<br>2. 🎙 Optional on-device `AI Radio Host & Voice Liner Notes` between AI Wave tracks<br>3. 📊 Private local Hi-Res listening analytics & `Musical Time Machine` anniversaries<br>4. 📈 Headless **Last.fm / ListenBrainz** scrobbler + Mac mini `Audiophile Health Monitor` |
| **v3.7.0** | **"Dvořák"** | 📋 Planned | 1. 💿 `Master Edition Comparator` (automated `DR`, `True Peak` & bandwidth comparison across album remasters)<br>2. 📸 `Vinyl Sleeve & Barcode Camera Scanner → Play in Hi-Res` (`Vision`)<br>3. 🔀 Phase-synchronized multi-room `AMR SyncGroup` (USB DAC + BluOS + WiiM + ESPHome) |
| **v3.8.0** | **"Mahler"** | 📋 Planned | 1. 🎼 Classical & Jazz `Composer / Work / Recording Matrix` (*Compare Performances*)<br>2. 💿 `Album-First / Vinyl Side A & Side B Ritual Mode`<br>3. 🎛 Ballistic `IEC 60268-17` *McIntosh / Nagra* Analog VU Meters (`Peak Hold`)<br>4. 🕯 `Zero-Photon Pitch-Black OLED & WLED Blackout Mode` for critical dark-room listening<br>5. 📡 Rack mini-display & StreamDeck / E-Ink webhook API (`/api/v1/now-playing`) |
| **v4.0.0** | **"Rachmaninoff"** | 📋 Planned | 1. 📱 Native **SwiftUI** client for iOS, iPadOS (Live Activities) & watchOS (Digital Crown)<br>2. 🎛 64-bit `Convolution FIR Engine` (`.wav` REW impulses up to 65k taps) + `AutoEQ` (4,000+ headphone profiles)<br>3. 🔊 HTTP REST / CoreMIDI preamp control (`Yamaha MusicCast`, `KEF`, `Cambridge`, `RME ADI-2 MIDI`) + `Auto-Source Input Select`<br>4. 🧬 `Personal Audiogram EQ` hearing calibration<br>5. 🔬 `0.1 LUFS` Level-Matched Blind `A/B & ABX Comparator` + `Reference Acoustic Test Suite` |

---

## 🔗 Architectural Dependency Chains

Every milestone builds directly on primitives delivered in earlier releases:

1. **Mastering Telemetry → Faceted Focus → Edition Comparator → Blind ABX Lab**:
   - `v3.0.0` *(Released)* introduces streaming **`TT DR`**, **`EBU R128 LUFS / True Peak`**, **`4x ISP`**, **`Phase Correlation`**, and **`Late-Night DRC`** synced via iCloud Drive.
   - `v3.4.0` indexes accumulated `DR` and sample-rate metadata inside **`Roon Focus`**.
   - `v3.7.0` pairs `TT DR + SpectralIntegrityAnalyzer` to rank album pressings in **`Master Edition Comparator`**.
   - `v4.0.0` combines `Master Edition Comparator` with `0.1 LUFS` gain matching in the **`Blind A/B & ABX Comparator`**.
2. **Room Measurement & `Exclusive Hog Mode` → Crossfeed/Loudness → `Convolution FIR` & `AutoEQ`**:
   - `v3.0.0` *(Released)* establishes **`CoreAudio Exclusive Hog Mode`**, **`DSD512 DoP (7EC)`**, **`HQ PCM NOS 768 kHz`**, and 64-bit **`Room Auto-PEQ`** ([`docs/DSP_AUDIO_ENGINE.md`](docs/DSP_AUDIO_ENGINE.md)).
   - `v3.5.0` adds **`Phase Invert`**, **`Bauer / Meier Crossfeed`**, and **`ISO 226 Loudness Contour`**.
   - `v4.0.0` layers **`65k-tap Convolution FIR (.wav REW)`**, **`AutoEQ`**, and **`Personal Audiogram EQ`** atop the same exclusive 64-bit engine.
3. **Queue Primitives & Dislikes → Cloud Taste Profile → `Sonic Object Graph` → Classical Matrix**:
   - `v3.0.0` *(Released)* delivers the **Playlists / Library** split, zero-pollution cloud staging, and **`Sonic Bridge`**.
   - `v3.1.0` adds **Linn Kazoo** queue mutations, **`DislikedTracksStore`**, and clickable booklet credits.
   - `v3.2.0–v3.3.0` leverage `DislikedTracksStore` for **`CloudTasteProfileService`** and **`Discovery Slider`**.
   - `v3.6.0–v3.8.0` unify booklet credits and acoustic passports into the SQLite **`Sonic Object Graph`**, powering the **`AI Radio Host`**, **`Vinyl Scanner`**, and **`Classical / Jazz Recording Matrix`**.
4. **Network Renderers → `Memory Play` → Phase-Locked Multi-Room**:
   - `v3.4.0` adds **`ESPHome`** and **`WiiM / UPnP AV`** lossless streaming.
   - `v3.5.0` introduces **`Zero-Jitter RAM Buffer (Memory Play)`** (`mlock`).
   - `v3.7.0` uses `Memory Play` ring offsets to phase-lock USB DACs and network streamers inside **`AMR SyncGroup`**.

---

*Note: Every planned feature preserves AMR's core invariant — 100% Bit-Perfect audio by default with instant zero-DSP hardware bypass and headless Mac mini operation without Accessibility GUI scripting.*
