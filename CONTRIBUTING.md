# Contributing to Apple Music Remote (AMR)

Thank you for your interest in contributing to **Apple Music Remote (AMR)**!

## Core Engineering Invariants

1. **100% Bit-Perfect by Default**: `Bit-Perfect Passthrough (Off)` must remain bit-identical (`0.0 dBFS`, zero sample-rate conversion, zero DSP overhead) unless the user explicitly enables an exclusive 64-bit DSP preset or Pre-DSP stage.
2. **Real-Time Audio Safety**: Never perform heap allocations, locks, Objective-C messaging, or disk/network I/O inside CoreAudio `IOProc` callbacks. Use lock-free `SPSCAtomicRingBuffer` primitives.
3. **Zero External Bloat**: AMR is built in pure Swift using native Apple frameworks (`CoreAudio`, `AudioToolbox`, `Accelerate / vDSP`, `Metal`, `Network`, `MusicKit`, `FoundationModels`, `NaturalLanguage`, `Vision`, `PDFKit`, `CryptoKit`).
4. **Headless Operation**: Never introduce Accessibility UI scripting that requires an unlocked screen or foreground window.

## Development Setup & Verification

- **macOS 14.0 (Sonoma)** or newer
- **Xcode 15.2+** (`Swift 5.9+`)

```bash
# Run the full unit & DSP verification suite (410+ tests)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path AppleMusicRemoteMac --parallel

# If you modified Web PWA sources under AppleMusicRemoteMac/Web/src/{html,css,js}/:
python3 AppleMusicRemoteMac/Tools/sync_web_ui.py

# Verify Universal 2 compilation (arm64 + x86_64)
xcrun swift build --package-path AppleMusicRemoteMac --triple arm64-apple-macosx14.0
xcrun swift build --package-path AppleMusicRemoteMac --triple x86_64-apple-macosx14.0
```

## Submitting Pull Requests

1. Open an issue or discussion first for major architectural or DSP changes.
2. Add or update unit tests under `AppleMusicRemoteMac/Tests/AppleMusicRemoteMacTests/` for any new DSP, networking, or queue behavior.
3. Ensure both `EN` and `RU` UI strings remain localized and synchronized.
