# Apple Music Remote 2.1.0 — "Beethoven"

Minor release **v2.1.0 ("Beethoven")** introduces queue navigation fixes for search results and custom playlists, guarantees queue integrity when skipping backward and forward without falling through into Apple Music radio streams of unrelated artists, enforces 100% Bit-Perfect volume lock at application startup and in runtime, and expands the automated unit test suite.

---

### ✨ What's New & What Changed:

#### 1. 🔄 Queue Navigation Integrity
* **Transition State Protection (`isTransitioningTrack`)**:
  - Eliminated race conditions when skipping to the previous track: while the target track is buffering in Music.app, trailing audio from the prior track is isolated and can no longer prematurely advance the active queue index.
  - Whole-queue matching properly distinguishes between current track confirmation, natural forward progression, and history protection against false rollbacks.
  - Prevented false-positive foreign track steering for songs already present in the active queue.
* **Queue Boundary Safeguards & Radio Fallthrough Prevention**:
  - In `PlaybackTransportController.nextTrack()`, eliminated fallthrough to system `app.nextTrack()` at the boundary of custom queues, which previously caused Apple Music radio to autoplay songs by unrelated artists.
  - Smart `previousTrack()`: if playback elapsed time > 3.0s, rewinds the current track to `0:00`; if < 3.0s, steps back to `activeIdx - 1`; on the first track of the queue, rewinds to `0:00` without escaping into previous library playlists.
  - For radio stations, calling "Previous Track" rewinds the live stream to `0:00` without dropping out of radio mode.
* **Full Queue Preservation for Search Results**:
  - `playSearchResults(tracks:startIndex:shuffle:)` now supports an arbitrary `startIndex`, preserving all search results in the active queue.
  - Clicking any song in Web UI search results immediately queues the entire list starting from the clicked track, properly populating history and upcoming tracks.

#### 2. 🔊 100% Volume Lock for Bit-Perfect Mode
* **Startup Validation & Enforcement**:
  - On `AppleMusicRemoteMac` launch, the "keep volume at 100% in Music.app" setting (`isVolumeLockedTo100`) is checked. If enabled, Music.app volume is automatically set to 100% via ScriptingBridge & AppleScript.
* **Music.app Launch Observer**:
  - If Music.app is launched after AMR, `NSWorkspace.didLaunchApplicationNotification` immediately validates and locks volume to 100%.
* **Runtime Volume Drift Recovery**:
  - `PlayerStatusEngine` continuously monitors software volume: if an inadvertent reduction is detected (and Audio Ducking is inactive), volume is immediately restored to 100%.
  - External volume modification requests are rejected when Bit-Perfect mode is active.

#### 3. 🧪 Test Suite Expansion & CI Stabilization
* Test suite expanded to **132 automated unit tests** (100% pass rate):
  - `testQueueMonitoringIgnoresDrainingTrackDuringTransition`
  - `testPreviousTrackInRadioPlaybackRewindsWithoutExitingRadio`
  - `testPreviousTrackAtBeginningOfCustomQueueRewindsWithoutFallingOutOfQueue`
  - `testNextTrackAtEndOfCustomQueueDoesNotFallThroughToAppNextTrack`
  - `testPlaySearchResultsWithStartIndexSetsCorrectActiveIndexAndUpcoming`
  - `testCheckAndEnforceVolumeLockWhenLockedSetsSimulatedVolumeTo100`
  - `testCheckAndEnforceVolumeLockWhenUnlockedDoesNotEnforce`
  - `testSetVolumeRespectsVolumeLockState`
* **CI Test Isolation**:
  - Isolated AppleScript and `NSWorkspace` calls during unit test runs to eliminate headless AppleEvent timeouts and Cocoa runloop observer inconsistencies on GitHub Actions runners.
  - Split Release workflow on GitHub Actions into a blocking test gate job and a dependent build-and-publish job to ensure release assets are never built if tests fail.
