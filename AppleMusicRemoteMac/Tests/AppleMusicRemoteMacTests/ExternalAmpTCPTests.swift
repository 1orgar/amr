import XCTest
import Network
@testable import AppleMusicRemoteMac

final class ExternalAmpTCPTests: XCTestCase {
    private var savedLock100: Bool = true
    private var savedAmpEnabled: Bool = false
    private var savedAmpProfile: ExternalAmpProfile = .rotel
    private var savedAmpHost: String = ""
    private var savedAmpPort: UInt16 = 9590
    private var savedAmpCap: Int = 96
    private var savedSoundCheck: Bool = false
    private var savedLowVolSmartNorm: Bool = true

    override func setUp() {
        super.setUp()
        savedLock100 = PlaybackStateStore.shared.isVolumeLockedTo100
        savedAmpEnabled = ExternalAmpTCPController.shared.isEnabled
        savedAmpProfile = ExternalAmpTCPController.shared.profile
        savedAmpHost = ExternalAmpTCPController.shared.host
        savedAmpPort = ExternalAmpTCPController.shared.port
        savedAmpCap = ExternalAmpTCPController.shared.maxVolumeCap
        savedSoundCheck = ExternalAmpTCPController.shared.isSoundCheckEnabled
        savedLowVolSmartNorm = ExternalAmpTCPController.shared.isLowVolumeSmartNormEnabled
    }

    override func tearDown() {
        ExternalAmpTCPController.shared.isLowVolumeSmartNormEnabled = savedLowVolSmartNorm
        ExternalAmpTCPController.shared.isSoundCheckEnabled = savedSoundCheck
        PlaybackStateStore.shared.isVolumeLockedTo100 = savedLock100
        ExternalAmpTCPController.shared.updateConfiguration(
            profile: savedAmpProfile,
            host: savedAmpHost,
            port: savedAmpPort,
            maxVolumeCap: savedAmpCap,
            isEnabled: savedAmpEnabled
        )
        super.tearDown()
    }

    func testRotelCommandGenerationAndStreamParsing() {
        let profile = ExternalAmpProfile.rotel
        XCTAssertEqual(profile.defaultPort, 9590)
        XCTAssertEqual(profile.nativeMaxVolume, 96)
        XCTAssertEqual(profile.buildSetVolumeCommand(45), "vol_45!")
        XCTAssertEqual(profile.buildSetVolumeCommand(5), "vol_05!")
        XCTAssertEqual(profile.buildSetVolumeCommand(120), "vol_96!")
        XCTAssertEqual(profile.buildMuteCommand(muted: true), "mute_on!")
        XCTAssertEqual(profile.buildMuteCommand(muted: false), "mute_off!")
        XCTAssertEqual(profile.buildQueryStatusCommand(), "get_volume!get_mute_status!")

        let p1 = profile.parseToken("volume=42")
        XCTAssertEqual(p1.volume, 42)
        XCTAssertNil(p1.muted)

        let p2 = profile.parseToken("vol=08")
        XCTAssertEqual(p2.volume, 8)

        let p3 = profile.parseToken("mute=on")
        XCTAssertEqual(p3.muted, true)

        let p4 = profile.parseToken("mute=off")
        XCTAssertEqual(p4.muted, false)
    }

    func testDenonHegelNADLyngdorfProtocols() {
        // Denon / Marantz
        let denon = ExternalAmpProfile.denonMarantz
        XCTAssertEqual(denon.buildSetVolumeCommand(50), "MV50\r")
        XCTAssertEqual(denon.parseToken("MV52").volume, 52)
        XCTAssertEqual(denon.parseToken("MV525").volume, 52) // 52.5 dB step
        XCTAssertEqual(denon.parseToken("MUON").muted, true)
        XCTAssertEqual(denon.parseToken("MUOFF").muted, false)

        // Hegel
        let hegel = ExternalAmpProfile.hegel
        XCTAssertEqual(hegel.buildSetVolumeCommand(37), "-v.37\r")
        XCTAssertEqual(hegel.parseToken("-v.37").volume, 37)
        XCTAssertEqual(hegel.parseToken("-m.1").muted, true)
        XCTAssertEqual(hegel.parseToken("-m.0").muted, false)

        // NAD
        let nad = ExternalAmpProfile.nad
        XCTAssertEqual(nad.buildSetVolumeCommand(64), "Main.Volume=64\r\n")
        XCTAssertEqual(nad.parseToken("Main.Volume=64").volume, 64)
        XCTAssertEqual(nad.parseToken("Main.Mute=On").muted, true)

        // Lyngdorf
        let lyngdorf = ExternalAmpProfile.lyngdorf
        let cmd50 = lyngdorf.buildSetVolumeCommand(50)
        XCTAssertEqual(cmd50, "!VOL(-400)\r")
        XCTAssertEqual(lyngdorf.parseToken("!VOL(-400)").volume, 50)
        XCTAssertEqual(lyngdorf.parseToken("!MUTEON").muted, true)
    }

    func testMutualExclusionWithVolumeLock100() {
        // 1. Enable Volume Lock 100% and configure External Amp
        PlaybackStateStore.shared.isVolumeLockedTo100 = true
        ExternalAmpTCPController.shared.updateConfiguration(
            profile: .rotel,
            host: "127.0.0.1",
            port: 59590,
            maxVolumeCap: 80,
            isEnabled: true
        )
        XCTAssertTrue(ExternalAmpTCPController.shared.isEnabled)
        XCTAssertTrue(ExternalAmpTCPController.shared.isActive)

        // 2. When Volume Lock 100% + External Amp Active, setVolume routes to External Amp (clamped to maxVolumeCap=80)
        let ok = PlaybackTransportController.shared.setVolume(62)
        XCTAssertTrue(ok)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 62)

        let cappedOk = PlaybackTransportController.shared.setVolume(95)
        XCTAssertTrue(cappedOk)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 80)

        // 3. SoundCheck can be enabled when External Amp TCP control is ON, and must automatically turn OFF when Amp control is disabled
        ExternalAmpTCPController.shared.isSoundCheckEnabled = true
        XCTAssertTrue(ExternalAmpTCPController.shared.isSoundCheckEnabled)

        ExternalAmpTCPController.shared.isEnabled = false
        XCTAssertFalse(ExternalAmpTCPController.shared.isEnabled)
        XCTAssertFalse(ExternalAmpTCPController.shared.isSoundCheckEnabled)

        // Attempting to enable SoundCheck while External Amp TCP control is OFF must be rejected
        ExternalAmpTCPController.shared.isSoundCheckEnabled = true
        XCTAssertFalse(ExternalAmpTCPController.shared.isSoundCheckEnabled)

        // Re-enable External Amp + SoundCheck, then verify turning OFF Volume Lock 100% disables both
        ExternalAmpTCPController.shared.isEnabled = true
        ExternalAmpTCPController.shared.isSoundCheckEnabled = true
        XCTAssertTrue(ExternalAmpTCPController.shared.isSoundCheckEnabled)

        PlaybackStateStore.shared.isVolumeLockedTo100 = false
        XCTAssertFalse(ExternalAmpTCPController.shared.isEnabled)
        XCTAssertFalse(ExternalAmpTCPController.shared.isActive)
        XCTAssertFalse(ExternalAmpTCPController.shared.isSoundCheckEnabled)

        // 4. Attempting to enable External Amp or SoundCheck while Volume Lock 100% is OFF must be rejected
        ExternalAmpTCPController.shared.isEnabled = true
        ExternalAmpTCPController.shared.isSoundCheckEnabled = true
        XCTAssertFalse(ExternalAmpTCPController.shared.isEnabled)
        XCTAssertFalse(ExternalAmpTCPController.shared.isActive)
        XCTAssertFalse(ExternalAmpTCPController.shared.isSoundCheckEnabled)
    }

    func testChunkStreamBufferParsingForRotelPushUpdates() {
        PlaybackStateStore.shared.isVolumeLockedTo100 = true
        ExternalAmpTCPController.shared.updateConfiguration(
            profile: .rotel,
            host: "127.0.0.1",
            port: 59591,
            maxVolumeCap: 96,
            isEnabled: true
        )

        // Simulate fragmented TCP stream from Rotel amp when user turns knob on front panel or remote
        ExternalAmpTCPController.shared.processIncomingChunkForTesting("vol")
        ExternalAmpTCPController.shared.processIncomingChunkForTesting("ume=53$mute=on$")
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 53)
        XCTAssertTrue(ExternalAmpTCPController.shared.isMuted)

        ExternalAmpTCPController.shared.processIncomingChunkForTesting("volume=41!mute=off!")
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 41)
        XCTAssertFalse(ExternalAmpTCPController.shared.isMuted)
    }

    func testAppleSoundCheckITunNormParsingAndHardwareNormalization() {
        // 1. Verify Apple SoundCheck iTunNORM hex formula (-10 * log10(max(v0, v1) / 1000))
        // Reference 0x000003E8 (1000) -> 0.0 dB
        let refGain = AppleSoundCheckService.parseITunNormHex(
            " 000003E8 000003E8 000003E8 000003E8 00000000 00000000 00007FFF 00007FFF 00000000 00000000"
        )
        XCTAssertNotNil(refGain)
        XCTAssertEqual(refGain ?? -99, 0.0, accuracy: 0.05)

        // Loud track (Metallica - The Day That Never Comes: 0x0000126D = 4717 -> -6.74 dB)
        let loudGain = AppleSoundCheckService.parseITunNormHex(
            " 0000126D 00000F2E 00004F35 00004B66 00024CA8 00024CA8 00007FFF 00007FFF 00024CA8 00024CA8"
        )
        XCTAssertNotNil(loudGain)
        XCTAssertEqual(loudGain ?? 0, -6.74, accuracy: 0.05)

        // Quiet jazz track (Miles Davis - Blue In Green: 0x0000011C = 284 -> +5.47 dB)
        let quietGain = AppleSoundCheckService.parseITunNormHex(
            " 0000011C 00000056 000005BE 000001D2 0001389A 0001B000 000079C0 000068E3 0000765D 00022B80"
        )
        XCTAssertNotNil(quietGain)
        XCTAssertEqual(quietGain ?? 0, 5.47, accuracy: 0.05)

        // 2. Verify binary MP4 atom scanning for iTunNORM
        var fakeMp4Header = Data([0x00, 0x00, 0x00, 0x1C])
        fakeMp4Header.append(Data("meancom.apple.iTunesnameiTunNORM".utf8))
        fakeMp4Header.append(Data([0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]))
        fakeMp4Header.append(Data(" 0000061F 000005BE 0000192A 000016FA 00024CA8 00024CA8 00007FFF 00007FFF 00024CA8 00024CA8".utf8))
        let extractedDb = AppleSoundCheckService.extractITunNormGainDb(from: fakeMp4Header)
        XCTAssertNotNil(extractedDb)
        XCTAssertEqual(extractedDb ?? 0, -1.95, accuracy: 0.05)

        // 3. Verify Hardware Amplifier Volume Offset & Base Volume Tracking
        PlaybackStateStore.shared.isVolumeLockedTo100 = true
        ExternalAmpTCPController.shared.updateConfiguration(
            profile: .rotel,
            host: "127.0.0.1",
            port: 59592,
            maxVolumeCap: 80,
            isEnabled: true
        )
        ExternalAmpTCPController.shared.isSoundCheckEnabled = false
        ExternalAmpTCPController.shared.setVolume(45)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 45)
        XCTAssertEqual(ExternalAmpTCPController.shared.baseListeningVolume, 45)

        // Enable Hardware SoundCheck
        ExternalAmpTCPController.shared.isSoundCheckEnabled = true

        // Track 1: Loud track (-6.74 dB -> offset -7%) -> Amp goes to 45 - 7 = 38%
        ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: "metallica:the day that never comes", gainDb: -6.74)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentTrackVolumeOffset, -7)
        XCTAssertEqual(ExternalAmpTCPController.shared.baseListeningVolume, 45)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 38)

        // Simulate stale TCP poll echo from amplifier reporting previous volume (45) right after auto-norm step:
        // baseListeningVolume must NOT ratchet up to 45 - (-7) = 52!
        ExternalAmpTCPController.shared.processIncomingChunkForTesting("volume=45$")
        XCTAssertEqual(ExternalAmpTCPController.shared.baseListeningVolume, 45)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 38)

        // Simulate amplifier confirming the auto-norm target volume (38): baseListeningVolume remains 45
        ExternalAmpTCPController.shared.processIncomingChunkForTesting("volume=38$")
        XCTAssertEqual(ExternalAmpTCPController.shared.baseListeningVolume, 45)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 38)

        // User manually nudges volume from 38% -> 40% (+2% louder while loud track is playing)
        // Base listening volume must shift from 45% -> 47% (40 - (-7) = 47)
        ExternalAmpTCPController.shared.setVolume(40)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 40)
        XCTAssertEqual(ExternalAmpTCPController.shared.baseListeningVolume, 47)

        // Track 2: Quiet track (+5.47 dB -> offset +5%) -> Amp goes to 47 + 5 = 52%
        ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: "miles davis:blue in green", gainDb: 5.47)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentTrackVolumeOffset, 5)
        XCTAssertEqual(ExternalAmpTCPController.shared.baseListeningVolume, 47)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 52)

        // Disabling SoundCheck restores amplifier volume back to baseListeningVolume (47%)
        ExternalAmpTCPController.shared.isSoundCheckEnabled = false
        XCTAssertEqual(ExternalAmpTCPController.shared.currentTrackVolumeOffset, 0)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 47)
    }

    func testSelfComputedDSPLoudnessMatrixAndTrackIdCachingForTracksWithoutMetadata() {
        // 1. Direct PCM gated RMS loudness computation
        // Generate a loud sine wave at -10.5 dBFS RMS (~6 dB louder than the -16.5 dBFS reference -> expected gain ~ -6.0 dB)
        let sampleCount = 32768
        let amplitude: Float = 0.4217 // RMS = 0.4217 / sqrt(2) = 0.2982 -> -10.51 dBFS
        var loudSamples = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            loudSamples[i] = amplitude * sin(Float(i) * 2.0 * .pi * 1000.0 / 44100.0)
        }
        let computedGain = AppleSoundCheckService.computePerceptualLoudnessGainDb(fromSamples: loudSamples)
        XCTAssertNotNil(computedGain)
        XCTAssertEqual(computedGain ?? 0, -6.0, accuracy: 0.35)

        // 2. Verify Live DSP Loudness Matrix recording & caching by trackId and artist:name
        let customTrackId = "bootleg_local_998877"
        let customArtist = "Rare Bootleg Artist"
        let customTitle = "Unreleased Studio Jam"
        let canonicalKey = "\(customArtist.lowercased()):\(customTitle.lowercased())"
        AppleSoundCheckService.shared.clearCacheEntryForTesting(artist: customArtist, name: customTitle, trackId: customTrackId)

        PlaybackStateStore.shared.isVolumeLockedTo100 = true
        ExternalAmpTCPController.shared.updateConfiguration(
            profile: .rotel,
            host: "127.0.0.1",
            port: 59592,
            maxVolumeCap: 80,
            isEnabled: true
        )
        ExternalAmpTCPController.shared.isSoundCheckEnabled = true
        ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: canonicalKey, gainDb: nil)
        ExternalAmpTCPController.shared.setVolume(45)
        XCTAssertEqual(ExternalAmpTCPController.shared.baseListeningVolume, 45)

        // Record live DSP loudness matrix result (-4.2 dB) for the metadata-less track
        AppleSoundCheckService.shared.recordLiveDSPLoudness(
            trackId: customTrackId,
            trackKey: canonicalKey,
            gainDb: -4.2,
            isRefined: true
        )

        // Verify cache lookup succeeds both by trackId and by artist+title
        let cachedById = AppleSoundCheckService.shared.getCachedGainDb(
            artist: "Different Alias",
            name: "Different Title",
            trackId: customTrackId
        )
        XCTAssertEqual(cachedById ?? 0, -4.2, accuracy: 0.05)

        let cachedByMeta = AppleSoundCheckService.shared.getCachedGainDb(
            artist: customArtist,
            name: customTitle
        )
        XCTAssertEqual(cachedByMeta ?? 0, -4.2, accuracy: 0.05)
        XCTAssertTrue(AppleSoundCheckService.shared.hasFinalizedCachedGain(trackId: customTrackId, trackKey: canonicalKey))

        // Verify hardware amplifier immediately adjusted to base (45) + offset (-4) = 41
        XCTAssertEqual(ExternalAmpTCPController.shared.currentTrackVolumeOffset, -4)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 41)

        AppleSoundCheckService.shared.clearCacheEntryForTesting(artist: customArtist, name: customTitle, trackId: customTrackId)
        ExternalAmpTCPController.shared.isSoundCheckEnabled = false
    }

    func testInitialSyncWithPendingSoundCheckAndRestartPersistence() {
        PlaybackStateStore.shared.isVolumeLockedTo100 = true
        ExternalAmpTCPController.shared.updateConfiguration(
            profile: .rotel,
            host: "127.0.0.1",
            port: 59593,
            maxVolumeCap: 80,
            isEnabled: true
        )
        ExternalAmpTCPController.shared.isLowVolumeSmartNormEnabled = false
        ExternalAmpTCPController.shared.isSoundCheckEnabled = true

        // Scenario A: Track SoundCheck (-6 dB) is evaluated BEFORE the amplifier's initial TCP volume response arrives
        ExternalAmpTCPController.shared.resetSyncStateForTesting(baseVolume: 20, lastPersistedAmpVolume: 0)
        ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: "tool:lateralus", gainDb: -5.58)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentTrackVolumeOffset, -6)

        // Amplifier connects and reports its un-normalized hardware volume (20):
        // Base listening volume must remain 20 (NOT 20 - (-6) = 26!), and pending offset (-6) must immediately adjust amp to 14
        ExternalAmpTCPController.shared.processIncomingChunkForTesting("volume=20$")
        XCTAssertEqual(ExternalAmpTCPController.shared.baseListeningVolume, 20)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 14)

        // Scenario B: App restarts while amplifier is still at normalized volume (14) from previous session (base=20, lastPersisted=14)
        ExternalAmpTCPController.shared.resetSyncStateForTesting(baseVolume: 20, lastPersistedAmpVolume: 14)
        ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: "tool:lateralus", gainDb: -5.58)
        ExternalAmpTCPController.shared.processIncomingChunkForTesting("volume=14$")
        XCTAssertEqual(ExternalAmpTCPController.shared.baseListeningVolume, 20)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 14)
    }

    func testLoudMastersOffsetRangeAndZeroVolumeRecovery() {
        PlaybackStateStore.shared.isVolumeLockedTo100 = true
        ExternalAmpTCPController.shared.updateConfiguration(
            profile: .rotel,
            host: "127.0.0.1",
            port: 59594,
            maxVolumeCap: 80,
            isEnabled: true
        )
        ExternalAmpTCPController.shared.isLowVolumeSmartNormEnabled = false
        ExternalAmpTCPController.shared.setVolume(20)
        ExternalAmpTCPController.shared.isSoundCheckEnabled = true

        // 1. Verify loud masters between -8.5 dB and -12 dB are differentiated instead of all clamping at -8
        ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: "porcupine tree:the sound of muzak", gainDb: -8.48)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentTrackVolumeOffset, -8)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 12)

        ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: "a perfect circle:judith", gainDb: -9.72)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentTrackVolumeOffset, -10)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 10)

        ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: "deftones:knife prty", gainDb: -10.65)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentTrackVolumeOffset, -11)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 9)

        // 2. Verify automatic SoundCheck floor (minAutoVol = 1, never 0!) when low baseListeningVolume (e.g. 6) is attenuated by a loud track
        ExternalAmpTCPController.shared.setVolume(6) // while offset is -11 -> base becomes 17; now set base to 6 with 0 dB track
        ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: "ref:neutral", gainDb: 0.0)
        ExternalAmpTCPController.shared.setVolume(6)
        XCTAssertEqual(ExternalAmpTCPController.shared.baseListeningVolume, 6)

        ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: "loud:track", gainDb: -10.0)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 1) // Never 0!

        // Next track at -2 dB must recover from 1 -> 6 - 2 = 4!
        ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: "moderate:track", gainDb: -2.0)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 4)
        XCTAssertEqual(ExternalAmpTCPController.shared.baseListeningVolume, 6)

        // 3. Verify manual setVolume(0) during a loud (-10 dB) track keeps baseListeningVolume at 0 (not 0 - (-10) = 10!)
        ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: "loud:track2", gainDb: -10.0)
        ExternalAmpTCPController.shared.setVolume(0)
        XCTAssertEqual(ExternalAmpTCPController.shared.baseListeningVolume, 0)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 0)
        ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: "next:track", gainDb: 0.0)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 0)

        // 4. Verify physical knob adjustment on the amplifier right after an automatic SoundCheck step
        ExternalAmpTCPController.shared.setVolume(20)
        ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: "tool:schism", gainDb: -6.0)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 14)
        // Stale poll echo of previous volume (20) before amp processes vol_14! must be ignored
        ExternalAmpTCPController.shared.processIncomingChunkForTesting("volume=20$")
        XCTAssertEqual(ExternalAmpTCPController.shared.baseListeningVolume, 20)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 14)
        // Amp confirms vol_14!
        ExternalAmpTCPController.shared.processIncomingChunkForTesting("volume=14$")
        XCTAssertEqual(ExternalAmpTCPController.shared.baseListeningVolume, 20)
        // User immediately turns physical knob on the Rotel to 18 (within < 1s of track start)
        ExternalAmpTCPController.shared.processIncomingChunkForTesting("volume=18$")
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 18)
        XCTAssertEqual(ExternalAmpTCPController.shared.baseListeningVolume, 24) // 18 - (-6) = 24

        // 5. Verify AudioDuckingController preserves baseListeningVolume and restores to current track's SoundCheck volume
        ExternalAmpTCPController.shared.setVolume(20) // offset is -6 -> base becomes 26
        let (duckOk, duckedVol, _) = AudioDuckingController.shared.activate(reductionPercent: 80.0)
        XCTAssertTrue(duckOk)
        XCTAssertEqual(duckedVol, 4)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 4)
        XCTAssertEqual(ExternalAmpTCPController.shared.baseListeningVolume, 26)
        // Track changes to -10 dB while ducked: amp must stay ducked at 4 until unduck, then restore to 26 - 10 = 16
        ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: "deftones:bored", gainDb: -10.0)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 4)
        let (unduckOk, restoredVol) = AudioDuckingController.shared.deactivate()
        XCTAssertTrue(unduckOk)
        XCTAssertEqual(restoredVol, 16)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 16)
        XCTAssertEqual(ExternalAmpTCPController.shared.baseListeningVolume, 26)
    }

    func testPreviewCandidateSelectionPrefersStudioAlbumOverLiveAndTribute() {
        let ruResults: [[String: Any]] = [
            [
                "artistName": "Porcupine Tree",
                "trackName": "The Sound of Muzak (Live)",
                "collectionName": "Arriving Somewhere (Live)",
                "previewUrl": "https://example.com/live.m4a"
            ],
            [
                "artistName": "Levi S.",
                "trackName": "The Sound of Muzak (Tribute to Porcupine Tree)",
                "collectionName": "Prog Tributes",
                "previewUrl": "https://example.com/tribute.m4a"
            ],
            [
                "artistName": "Lion Drome",
                "trackName": "Black Light Cobra",
                "collectionName": "Other",
                "previewUrl": "https://example.com/unrelated.m4a"
            ]
        ]

        let usResults: [[String: Any]] = [
            [
                "artistName": "Porcupine Tree",
                "trackName": "The Sound Of Muzak (2017 Remaster)",
                "collectionName": "In Absentia (Deluxe Edition) [2017 Remaster]",
                "previewUrl": "https://example.com/remaster2017.m4a"
            ],
            [
                "artistName": "Porcupine Tree",
                "trackName": "The Sound Of Muzak",
                "collectionName": "In Absentia",
                "previewUrl": "https://example.com/studio_original.m4a"
            ]
        ]

        let ruCand = AppleSoundCheckService.selectBestPreviewCandidate(
            from: ruResults,
            expectedArtist: "Porcupine Tree",
            expectedName: "The Sound Of Muzak",
            expectedAlbum: "In Absentia"
        )
        let usCand = AppleSoundCheckService.selectBestPreviewCandidate(
            from: usResults,
            expectedArtist: "Porcupine Tree",
            expectedName: "The Sound Of Muzak",
            expectedAlbum: "In Absentia"
        )

        XCTAssertNotNil(usCand)
        XCTAssertEqual(usCand?.url.absoluteString, "https://example.com/studio_original.m4a")
        XCTAssertGreaterThan(usCand?.score ?? 0, ruCand?.score ?? 0)
        XCTAssertGreaterThanOrEqual(usCand?.score ?? 0, 95)

        // Unrelated results must return nil (never fallback to random first item on search)
        let unrelatedOnly = [ruResults[2]]
        let noMatch = AppleSoundCheckService.selectBestPreviewCandidate(
            from: unrelatedOnly,
            expectedArtist: "Porcupine Tree",
            expectedName: "The Sound Of Muzak",
            expectedAlbum: "In Absentia"
        )
        XCTAssertNil(noMatch)

        // Catalog ID validation must reject local Music.app database IDs (< 5,000,000) and accept real Apple Music Adam IDs
        XCTAssertFalse(AppleSoundCheckService.isValidCatalogId("0"))
        XCTAssertFalse(AppleSoundCheckService.isValidCatalogId("4135"))
        XCTAssertFalse(AppleSoundCheckService.isValidCatalogId("9099"))
        XCTAssertTrue(AppleSoundCheckService.isValidCatalogId("1474893965"))

        // UTF-16LE ID3v2.3 COMM iTunNORM tag extraction test
        var utf16Payload = Data([0xFF, 0xFE])
        let tagText = "iTunNORM 0000127A 00001100 00002500 00002400 00024CA8 00024CA8 00007FFF 00007FFF 00024CA8 00024CA8"
        for scalar in tagText.unicodeScalars {
            let v = UInt16(scalar.value)
            utf16Payload.append(UInt8(v & 0xFF))
            utf16Payload.append(UInt8((v >> 8) & 0xFF))
        }
        let extractedUtf16 = AppleSoundCheckService.extractITunNormGainDb(from: utf16Payload)
        XCTAssertNotNil(extractedUtf16)
        XCTAssertEqual(extractedUtf16 ?? 0, -6.75, accuracy: 0.05)
    }

    func testSmartLowVolumeNonLinearNormalizationAndLiveToggle() {
        PlaybackStateStore.shared.isVolumeLockedTo100 = true
        ExternalAmpTCPController.shared.updateConfiguration(
            profile: .rotel,
            host: "127.0.0.1",
            port: 59595,
            maxVolumeCap: 80,
            isEnabled: true
        )
        ExternalAmpTCPController.shared.isLowVolumeSmartNormEnabled = true
        ExternalAmpTCPController.shared.isSoundCheckEnabled = true

        // 1. At normal/high listening volume (base = 50 >= 40), smart low-volume curve gives full 1:1 dB step offset (-8)
        ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: "ref:neutral", gainDb: 0.0)
        ExternalAmpTCPController.shared.setVolume(50)
        ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: "porcupine tree:the sound of muzak", gainDb: -8.48)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentTrackVolumeOffset, -8)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 42)

        // 2. At quiet evening listening volume (base = 20 < 40), Rotel's steeper resistor ladder steps are compensated:
        // -8.48 dB produces a gentle -4 step offset (20 -> 16) instead of plunging -8 steps to 12
        ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: "ref:neutral", gainDb: 0.0)
        ExternalAmpTCPController.shared.setVolume(20)
        ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: "porcupine tree:the sound of muzak", gainDb: -8.48)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentTrackVolumeOffset, -4)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 16)

        // 3. Toggling Smart Low-Volume Normalization OFF on the fly immediately switches to linear offset (-8 -> vol 12)
        ExternalAmpTCPController.shared.isLowVolumeSmartNormEnabled = false
        XCTAssertEqual(ExternalAmpTCPController.shared.currentTrackVolumeOffset, -8)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 12)

        // 4. Toggling Smart Low-Volume Normalization back ON immediately restores smart low-volume offset (-4 -> vol 16)
        ExternalAmpTCPController.shared.isLowVolumeSmartNormEnabled = true
        XCTAssertEqual(ExternalAmpTCPController.shared.currentTrackVolumeOffset, -4)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 16)

        // 5. At whisper-quiet listening volume (base = 8), a loud -10 dB track steps down gently (8 -> 5) instead of muting to 0
        ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: "ref:neutral", gainDb: 0.0)
        ExternalAmpTCPController.shared.setVolume(8)
        ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: "deftones:knife prty", gainDb: -10.0)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentTrackVolumeOffset, -3)
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 5)

        // 6. Verify TCP Zero-Jump Guard: sudden uncommanded volume=00$ from amplifier (e.g. Standby / relay transient)
        // when currentVolume >= 6 must NOT collapse currentVolume or baseListeningVolume to 0
        ExternalAmpTCPController.shared.applyTrackSoundCheck(trackKey: "ref:neutral", gainDb: 0.0)
        ExternalAmpTCPController.shared.setVolume(25)
        Thread.sleep(forTimeInterval: 0.5)
        ExternalAmpTCPController.shared.processIncomingChunkForTesting("volume=00$")
        XCTAssertEqual(ExternalAmpTCPController.shared.currentVolume, 25)
        XCTAssertEqual(ExternalAmpTCPController.shared.baseListeningVolume, 25)
    }
}
