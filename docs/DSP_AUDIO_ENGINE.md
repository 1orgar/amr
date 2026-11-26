# AMR Hybrid 64-Bit Studio DSP Engine: DSD DoP (7EC SDM), HQ PCM NOS & Room Auto-PEQ

**Apple Music Remote (AMR)** includes a native real-time 64-bit audio engine written in Swift (`Accelerate / AMX FP64` + `Metal GPU df64`), communicating directly with the **macOS CoreAudio HAL** in exclusive **`Hog Mode` + `Direct Non-Mixable Integer (0x4c)`** — while preserving a 1-click return to **100% Bit-Perfect Direct Bypass**.

---

## Table of Contents

1. [Three Audio Engine Modes (and What HQ PCM NOS Does)](#1-three-audio-engine-modes-and-what-hq-pcm-nos-does)
2. [Preset Management](#2-preset-management)
3. [DSP Parameter Reference & Sonic Impact](#3-dsp-parameter-reference--sonic-impact)
4. [CoreAudio HAL Coordination & Network Renderers (BluOS / DLNA)](#4-coreaudio-hal-coordination--network-renderers-bluos--dlna)
5. [Hardware Loudness Normalization, `iTunNORM` & Crest Compensation](#5-hardware-loudness-normalization-itunnorm--crest-compensation)
6. [64-Bit Room Acoustic Correction (`Auto-PEQ` via iPhone / iPad Mic)](#6-64-bit-room-acoustic-correction-auto-peq-via-iphone--ipad-mic)
7. [Audiophile Late-Night Dynamic Range Control (`Late-Night DRC`)](#7-audiophile-late-night-dynamic-range-control-late-night-drc)
8. [Pre-DSP Mastering Restoration (`De-Clipper` & `Weiss Dynamic De-Esser`)](#8-pre-dsp-mastering-restoration-de-clipper--weiss-dynamic-de-esser)

---

## 1. Three Audio Engine Modes (and What HQ PCM NOS Does)

### 1.1. `Bit-Perfect Passthrough (Off)`
Direct bit-for-bit delivery of the native Apple Music PCM stream (`44.1 – 192 kHz`, `16/24-bit`) to your external DAC with zero oversampling, zero modulation, and automatic hardware sample rate switching via `BitPerfectLogMonitor`.

### 1.2. `DSD DoP (7EC SDM)` — 7th-Order 1-Bit Sigma-Delta Modulator
Converts incoming PCM into a high-rate 1-bit **DSD64 / DSD128 / DSD256 / DSD512** stream (`2.82 – 22.58 MHz`) using a 7th-order cascaded modulator with Chebyshev NTF resonator notches (`7EC`) and **Viterbi Trellis lookahead** (`TrellisViterbiModulator`), packed losslessly into **DoP v1.1 (`DSD over PCM`, `0x05 / 0xFA` markers)**.
* When `0x05 / 0xFA` frames arrive over a bit-exact integer transport, your external USB DAC or DDC (such as Topping, SMSL, Holo Audio, Denafrips, Chord, RME, etc.) recognizes native DSD and bypasses its internal on-chip PCM interpolation stages.

### 1.3. `HQ PCM NOS` (High-Quality Non-Oversampling PCM up to 768 kHz)
**`NOS` (*Non-Oversampling*)** feeds an external DAC a pre-upsampled PCM stream locked to the **maximum native sample rate of your DAC** (`705.6 / 768 kHz`, `352.8 / 384 kHz`, or `176.4 / 192 kHz` over S/PDIF).

**Why this matters acoustically:**
1. Conventional DAC chips contain small built-in hardware interpolation filters constrained by silicon die area and power budget (typically dozens to a few hundred taps).
2. Discrete **R2R / Multibit ladder DACs** (*Holo Audio Spring/May, Denafrips Ares/Pontus/Venus/Terminator, Musician Pegasus, Schiit Multibit*) bypass internal digital filters in `NOS` mode. Feeding raw `44.1 kHz` into an unfiltered R2R DAC creates ultrasonic imaging aliases above `22.05 kHz` that can cause intermodulation distortion in tweeters and amplifiers.
3. AMR's **`HQ PCM NOS`** offloads filter math onto Apple Silicon (`AMX FP64`, **65,536 taps**) or GPU (`Metal df64`, **262,144 taps**), upsamples 8×–16× up to `705.6 / 768 kHz`, and requantizes `64-bit Float` into `24/32-bit Integer` through a **15th-order psychoacoustic `LNS15` (*Lipshitz / Wannamaker*) noise shaper**.
4. `LNS15` shifts quantization noise out of the human ear's peak sensitivity band (`1–6 kHz`) above `100 kHz`, pushing the audible noise floor (`20 Hz – 20 kHz`) below **`-165 dBFS`** (**27+ effective bits of resolution** inside a 24-bit word).

---

## 2. Preset Management

* **Authoring & fine-tuning presets** — inside **macOS Settings → `DSP`** (`DSPPresetManager`): save custom presets, update parameters, rename, or delete. All presets sync automatically across Macs via **iCloud Drive**.
* **One-tap preset switching** — inside the **Web PWA (`Signal Path → DSP Preset`)** and the **macOS Menu Bar (`🎛️ DSP Preset`)**, while preserving your selected output DAC.

### Built-In Factory Presets

| Preset | Pipeline Configuration | Target System & Sonic Character |
| :--- | :--- | :--- |
| **Bit-Perfect Passthrough (Off)** | Direct native PCM, zero DSP | 1:1 bit-exact output locked to source sample rate |
| **SACD Reference (DSD256 • 7EC-Balanced)** | `DSD256`, `7EC-Balanced`, `Trellis M=8`, `AMX FP64`, `Lin-Phase`, `Strict 44.1k` | All-around reference: deep soundstage, analog fluidity, neutral tonal balance |
| **Max Soundstage & Air (DSD256 • 7EC-Super • Metal)** | `DSD256`, `7EC-Super`, `Trellis M=16`, `Metal GPU 262k`, `Lin-Phase`, `-4.0 dB` | Holographic depth and micro-detail for classical, acoustic, and jazz recordings |
| **Attack & Drive (DSD128 • 7EC-Transient)** | `DSD128`, `7EC-Transient`, `Trellis M=8`, `AMX FP64`, `Min-Phase`, `Adaptive` | Zero pre-ringing transient punch for rock, metal, funk, and electronic music |
| **Optical / Coax S/PDIF (DSD64 DoP)** | `DSD64` (`DoP 176.4 kHz`), `7EC-Balanced`, `Trellis M=8`, `Strict 44.1k` | Tailored for USB-to-S/PDIF DDC bridges and coaxial/Toslink DAC inputs (`≤ 192 kHz`) |
| **Multibit / R2R (HQ PCM NOS • LNS15)** | `HQ PCM NOS` (up to `768 kHz`), `AMX FP64`, `Min-Phase`, `LNS15 15th-Order` | Maximum timbral density and resolution for R2R ladder and `768 kHz` PCM DACs |

---

## 3. DSP Parameter Reference & Sonic Impact

### 3.1. DSD Rate (`DSD64` / `DSD128` / `DSD256` / `DSD512`)
* **`DSD64`** (`2.8224 MHz`, DoP carrier `176.4 kHz`) — Scarlet Book SACD standard; compatible with optical Toslink and coaxial S/PDIF (`≤ 192 kHz`).
* **`DSD128`** (`5.6448 MHz`, DoP carrier `352.8 kHz`) — pushes ultrasonic modulation noise an octave higher with low CPU usage.
* **`DSD256`** (`11.2896 MHz`, DoP carrier `705.6 kHz`) — sweet spot for modern USB DACs (`> 155 dB` audible SNR).
* **`DSD512`** (`22.5792 MHz`, DoP carrier `1411.2 kHz`) — for USB DACs supporting `1.411 / 1.536 MHz` PCM carriers (automatically negotiates down to the highest supported rate if the DAC caps at `705.6 / 768 kHz`).

### 3.2. 7th-Order Modulator Profile (`7EC`)
* **`7EC-Transient` (`OBG = 1.38`)**: conservative out-of-band gain with fast loop settling for tight bass and percussive slam.
* **`7EC-Balanced` (`OBG = 1.50`)**: reference compromise between audible-band SNR and integrator stability margin.
* **`7EC-Super` (`OBG = 1.62`)**: aggressive noise suppression across vocal and treble bands (best paired with `-3.5 … -4.0 dB` headroom and `Trellis M=8..16`).

### 3.3. Viterbi Trellis Lookahead (`M = Off / 4 / 8 / 16`)
Instead of making a greedy 1-bit decision per clock cycle, **Viterbi Trellis** evaluates `M` parallel 7-integrator state trajectories across 8–16 future steps to minimize cumulative quantization error and eliminate idle tones (`M=8` recommended; `M=16` for flagship presets).

### 3.4. Oversampler Core (`Accelerate AMX FP64` vs `Metal GPU Overlap-Save df64`)
* **`Accelerate AMX (FP64)`**: multi-stage polyphase FIR in true IEEE-754 `Float64` (**65,536 equivalent taps**, `> 155 dB` image rejection) running on Apple Silicon AMX coprocessors with ultra-low latency and minimal power draw.
* **`Metal GPU (Overlap-Save df64)`**: single-stage FFT convolution of a **262,144-tap** Kaiser-windowed Sinc kernel on the GPU using emulated double-float (`df64`, ~48-bit mantissa) for surgical Nyquist transition steepness and orchestral separation.

### 3.5. Phase Response (`Linear-Phase` vs `Minimum-Phase`)
* **`Linear-Phase`**: zero phase dispersion across `20 Hz – 20 kHz` — preserves spatial cues and hall reverb tails.
* **`Minimum-Phase`**: computed via Kolmogorov–Hilbert cepstral factorization — eliminates pre-ringing (`0%` pre-impulse energy) for natural acoustic transient attack.

### 3.6. Clock-Grid Policy (`Strict SACD 44.1k` / `Adaptive Dual-Grid` / `Hybrid 48k NOS`)
* **`Strict SACD (44.1k)`**: converts `48/96/192 kHz` sources via `FP64` polyphase resampling onto the `44.1 kHz` family (`176.4 / 352.8 / 705.6 kHz`) for DACs that only recognize DoP on `44.1k` multiples.
* **`Adaptive Dual-Grid`**: preserves native oscillator families (`44.1k → DoP 705.6k`, `48k → DoP 768k`) on DACs supporting `DSD×48k`.
* **`Hybrid (44.1k DSD / 48k NOS PCM)`**: routes `44.1k`-family tracks to `DSD DoP` and `48k`-family tracks directly to synchronous `HQ PCM NOS` (`384 / 768 kHz` with `LNS15`).

### 3.7. 3-Stage USB DAC Hardware Capability Verifier (`evaluateDSPCapabilities`)
Before engaging `Hog Mode`, AMR inspects transport bus type, native integer bit depth (`≥ 24-bit`), and physical sample rate ranges — automatically blocking `DSD DoP` / `HQ NOS` on built-in Mac speakers, AirPlay, Bluetooth, HDMI, or 16-bit USB headsets so DoP white noise can never reach unsupported outputs.

---

## 4. CoreAudio HAL Coordination & Network Renderers (BluOS / DLNA)

* When `Hog Mode` captures an external USB DAC, `AudioProcessTapService` taps `Music.app` with `.muted` so built-in speakers stay silent while **`SpectralIntegrityAnalyzer`** (`TRUE HI-RES` / `FAKE HI-RES` + **60 FPS 32-band RTA**) and **`WLEDDDPController`** analyze clean pre-modulator PCM.
* When switching output to **Bluesound / BluOS** or **UPnP / DLNA** network streamers, AMR automatically suspends local USB `Hog Mode` and streams uncompressed **Bit-Perfect LPCM / WAV up to `24-bit / 192 kHz`** over HTTP, resuming your USB DSP preset seamlessly when you switch back to your USB DAC.

---

## 5. Hardware Loudness Normalization, `iTunNORM` & Crest Compensation

Scaling digital samples in software destroys bit-perfect integrity (and corrupts `0x05 / 0xFA` DoP markers). AMR performs track loudness normalization strictly in the **external amplifier's hardware attenuator** over TCP (`ExternalAmpTCPController`: **Rotel, Denon / Marantz, Hegel, NAD, Lyngdorf**):

1. **Tier 1 — Local Files**: `AppleSoundCheckService` reads `com.apple.iTunes:iTunNORM` atoms (`.m4a/.mp4`) or `COMM iTunNORM` frames (`.mp3/.aiff`).
2. **Tier 2 — Apple Music Cloud Catalog**: fetches only the initial HTTP byte range (`bytes=0-98303`) of catalog headers to extract official studio `iTunNORM` values in milliseconds.
3. **Tier 3 — Untagged Streams**: `SpectralIntegrityAnalyzer` measures real-time `ITU-R BS.1770` K-weighted loudness (`LUFS`) and caches results on disk + iCloud Drive.
4. **Psychoacoustic Crest Compensation & `[Music.app SC Guard]`**:
   * Heavily brickwalled "Loudness War" masters (`Crest < 10.5 dB`) sound subjectively quieter after plain `-16.5 LUFS` normalization because transient peaks are crushed `7–8 dB` below dynamic masters. AMR's **Crest Compensation** restores up to `+3.5 dB` of perceived punch on hyper-compressed tracks while leaving dynamic `DR11+` recordings untouched (`0.0 dB`).
   * **`[Music.app SC Guard]`** automatically detects if `Music.app`'s internal software Sound Check is inadvertently enabled and cancels duplicate attenuation on the amplifier.

---

## 6. 64-Bit Room Acoustic Correction (`Auto-PEQ` via iPhone / iPad Mic)

* **Pink Noise & iOS MEMS Mic Calibration**: `RoomAcousticService` plays semi-correlated Paul Kellet pink noise (`85% Mid + 15% Side`) through your speakers (local DAC or `BluOS / DLNA`) while your iPhone or iPad records from the listening position directly inside the Web PWA (`4096-pt vDSP Welch FFT`, 31 ISO 1/3-octave bands `20 Hz – 20 kHz`).
* **Harman In-Room Target & Asymmetric 8-Band 64-Bit RBJ Synthesis**:
  * Prioritizes narrow cuts (`up to -9.0 dB`, `Q = 2.0 … 3.6`) on standing room modes (`35 – 220 Hz`) to eliminate bass boom and unmask midrange clarity.
  * Limits acoustic dip boosts to a gentle `+3.5 dB` (`Q = 1.1 … 1.6`) with automatic negative **`Preamp Headroom`** in `Float64` so digital clipping is mathematically impossible.
* **Zero-Overhead Bypass**: When `Auto-PEQ`, `Late-Night DRC`, and Pre-DSP Restoration are all set to `Off` in `Bit-Perfect Passthrough`, the local CoreAudio processor completely unloads for pure 1:1 hardware passthrough.

---

## 7. Audiophile Late-Night Dynamic Range Control (`Late-Night DRC`)

Designed in `64-bit Float64` for late-evening listening to wide-dynamic-range symphonic, jazz, and film score recordings (`DR14–DR20+`) without tape-hiss pumping or transient squashing:

1. **Dual-Envelope `ITU-R BS.1770` K-Weighted Detector**: combines a slow program upward-lift envelope (`~1.8 s`) for quiet passages (`pianissimo`) with a fast soft-knee crest envelope (`25 ms`) for sudden orchestral `tutti`.
2. **`-63 dBFS` Tape Hiss & Pause Gate**: smoothly returns positive make-up gain to `0.0 dB` during track intros, fades, and silent pauses.
3. **64-Sample Look-Ahead True-Peak Limiter (`-1.0 dBTP`)**: guarantees zero clipping with three selectable profiles synced via iCloud Drive: **`Off (100% Bit-Perfect)`**, **`Gentle (Jazz / Vocal)`**, and **`Night Concert (Symphony / OST)`**.

---

## 8. Pre-DSP Mastering Restoration (`De-Clipper` & `Weiss Dynamic De-Esser`)

Positioned at the very front of the `64-bit Float64` pipeline — **strictly ahead of `Headroom`, `Room Auto-PEQ`, and `Late-Night DRC`** so minimum-phase EQ filters never tilt clipped flat-top plateaus prior to reconstruction:

```text
Float32 (Tap) → [0a] Mastering De-Clipper → [0b] Weiss De-Esser → [1] Headroom/ISP → [2] Room Auto-PEQ → [3] Late-Night DRC → Oversampler / DAC / DLNA
```

* **Loudness-War `MasteringDeClipper`**: adaptive brickwall ceiling tracker + 256-sample look-ahead **Cubic Hermite `C1` spline reconstruction** restores shaved transient peaks (up to `+4.2 dB`), while **`Auto — Smart Guard`** automatically bypasses clean audiophile masters (`DR11+`, `100% Bit-Exact` on unclipped samples).
* **Level-Independent `WeissDynamicDeEsser`**: inspired by *Weiss DS1-MK3 / DAC501*, compares Mid-weighted sibilance energy (`6.5–7.0 kHz`) against main signal body (`> 180 Hz`) so vocal harshness is tamed identically at `-26 dBFS` whispers and `0 dBFS` choruses via zero-phase-shift symmetric RBJ subtraction (`y[n] == x[n]` between sibilants).
