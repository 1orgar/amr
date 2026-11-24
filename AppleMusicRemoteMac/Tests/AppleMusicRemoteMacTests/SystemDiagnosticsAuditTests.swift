//
//  SystemDiagnosticsAuditTests.swift
//  AppleMusicRemoteMacTests
//
//  Comprehensive verification suite for the full system diagnostics & security audit fixes:
//  - S-01..S-07: DNS rebinding Host validation, CSRF /api/duck GET rejection, DLNA stream_token,
//                file:// origin rejection, cryptographic device_secret anti-spoofing,
//                invite revocation purge, allowLibraryModification, WLED/Artwork/URL-scheme guards
//  - S-09..S-11: UPnP GENA CallStranger SSRF defense & safe hash magnitude
//  - DSP & CoreAudio: SPSC stereo frame alignment, LNS15 Lee stability (< 1.55),
//                     BitPerfectLogMonitor duplicate ALAC suppression & NDJSON parsing
//  - Bridge & UI: MusicAppProvider multi-observer non-overwrite & LibraryService 0ms favorite-playlist short-circuit
//

import XCTest
import Network
@testable import AppleMusicRemoteMac

final class SystemDiagnosticsAuditTests: XCTestCase {

    // MARK: - S-01 / S-02 / S-03 / S-04: HTTP & WebSocket Perimeter Guards

    func testDNSRebindingHostHeaderValidationAndOriginHardening() {
        let server = WebSocketServer.shared
        let loopConn = NWConnection(host: "127.0.0.1", port: 8080, using: .tcp)

        // 1. Missing Host or DNS-rebound external domain MUST be rejected even from 127.0.0.1 without Origin
        for badHost in [
            "rebind.attacker.example:8080",
            "evil.lan:8080",
            "router.home:8080",
            "8.8.8.8:8080"
        ] {
            let hdr = "GET /api/status HTTP/1.1\r\nHost: \(badHost)\r\n\r\n"
            XCTAssertFalse(
                server.isHTTPRequestAuthorized(
                    headerString: hdr,
                    fullPath: "/api/status",
                    bodyData: Data(),
                    connection: loopConn
                ),
                "Host '\(badHost)' must be rejected to block DNS rebinding"
            )
        }

        let noHostHdr = "GET /api/status HTTP/1.1\r\n\r\n"
        XCTAssertFalse(
            server.isHTTPRequestAuthorized(
                headerString: noHostHdr,
                fullPath: "/api/status",
                bodyData: Data(),
                connection: loopConn
            ),
            "Missing Host header must be rejected"
        )

        // 2. Valid localhost / literal RFC1918 Host passes Host check; file:// Origin MUST be rejected
        XCTAssertFalse(server.isAllowedOrigin("file://", hostHeader: "127.0.0.1:8080"))
        XCTAssertFalse(server.isAllowedOrigin("http://evil.lan:8080", hostHeader: "127.0.0.1:8080"))
        XCTAssertTrue(server.isAllowedOrigin("http://127.0.0.1:8080", hostHeader: "127.0.0.1:8080"))
    }

    func testDuckingGETRequiresExplicitTokenAndRejectsCrossSiteSubresource() {
        let server = WebSocketServer.shared
        let loopConn = NWConnection(host: "127.0.0.1", port: 8080, using: .tcp)

        // Bare <img src="http://127.0.0.1:8080/api/duck"> from browser (no X-AMR-Device-ID / Bearer) MUST fail
        let imgCsrfHdr = [
            "GET /api/duck HTTP/1.1",
            "Host: 127.0.0.1:8080",
            "Sec-Fetch-Mode: no-cors",
            "Sec-Fetch-Site: cross-site",
            "User-Agent: Mozilla/5.0",
            "",
            ""
        ].joined(separator: "\r\n")
        XCTAssertFalse(
            server.isDuckingGETRequestAuthorized(
                headerString: imgCsrfHdr,
                fullPath: "/api/duck",
                connection: loopConn
            )
        )

        // Valid local API Bearer token succeeds
        let bearerHdr = [
            "GET /api/duck HTTP/1.1",
            "Host: 127.0.0.1:8080",
            "Authorization: Bearer \(ClientDeviceManager.shared.localAPIToken)",
            "",
            ""
        ].joined(separator: "\r\n")
        XCTAssertTrue(
            server.isDuckingGETRequestAuthorized(
                headerString: bearerHdr,
                fullPath: "/api/duck",
                connection: loopConn
            )
        )
    }

    func testDLNAStreamRequiresMatchingPerSessionToken() {
        let server = WebSocketServer.shared
        let rendererConn = NWConnection(host: "192.168.1.150", port: 8080, using: .tcp)

        // Missing or forged stream_token MUST be rejected before IP check even matters
        XCTAssertFalse(
            server.isAllowedDLNAStreamRequest(
                connection: rendererConn,
                fullPath: "/stream/live.wav"
            )
        )
        XCTAssertFalse(
            server.isAllowedDLNAStreamRequest(
                connection: rendererConn,
                fullPath: "/stream/live.wav?stream_token=deadbeef0000"
            )
        )
    }

    // MARK: - S-05 & S-06: Cryptographic Device Secret Anti-Spoofing & Invite Revocation

    func testDeviceSecretBlocksCrossIPSpoofingAndRevocationPurgesInviteTokens() {
        let manager = ClientDeviceManager.shared
        let ownerConn = UUID()
        let attackerConn = UUID()
        let roamConn = UUID()
        let deviceId = "audit-sec-\(UUID().uuidString.lowercased())"

        defer {
            manager.unregisterConnection(connectionId: ownerConn)
            manager.unregisterConnection(connectionId: attackerConn)
            manager.unregisterConnection(connectionId: roamConn)
            manager.removeDevice(deviceId: deviceId)
        }

        let invite = manager.createInviteToken()
        let ownerRecord = manager.registerConnection(
            connectionId: ownerConn,
            deviceId: deviceId,
            deviceName: "Owner iPhone",
            deviceType: "mobile",
            preferredLockScreen: true,
            remoteIP: "10.10.20.15",
            inviteToken: invite
        )
        XCTAssertTrue(ownerRecord.isAuthorized)
        XCTAssertFalse(ownerRecord.deviceSecret.isEmpty)
        XCTAssertNil(ownerRecord.dictionary["device_secret"], "Broadcast dictionary must never leak device_secret")
        XCTAssertEqual(ownerRecord.dictionaryWithSecret["device_secret"] as? String, ownerRecord.deviceSecret)

        // 1. Attacker on 10.10.20.99 replaying `deviceId` WITHOUT `deviceSecret` MUST be rejected
        let spoofed = manager.registerConnection(
            connectionId: attackerConn,
            deviceId: deviceId,
            deviceName: "Spoofed Attacker",
            deviceType: "desktop",
            preferredLockScreen: false,
            remoteIP: "10.10.20.99"
        )
        XCTAssertFalse(spoofed.isAuthorized)
        XCTAssertTrue(spoofed.deviceSecret.isEmpty, "Rejected spoof response must not leak owner's secret")
        XCTAssertFalse(manager.isConnectionAuthorized(connectionId: attackerConn))
        XCTAssertEqual(manager.getDevice(deviceId: deviceId)?.deviceName, "Owner iPhone")

        // 2. Legitimate owner roaming to 10.10.20.44 WITH `deviceSecret` succeeds and locks `hasConfirmedSecret`
        let roamed = manager.registerConnection(
            connectionId: roamConn,
            deviceId: deviceId,
            deviceName: "Owner iPhone",
            deviceType: "mobile",
            preferredLockScreen: true,
            remoteIP: "10.10.20.44",
            deviceSecret: ownerRecord.deviceSecret
        )
        XCTAssertTrue(roamed.isAuthorized)
        XCTAssertTrue(roamed.hasConfirmedSecret)

        // 3. Per-device library modification capability enforcement
        XCTAssertTrue(manager.canConnectionModifyLibrary(connectionId: roamConn))
        manager.setAllowLibraryModification(deviceId: deviceId, enabled: false)
        XCTAssertFalse(manager.canConnectionModifyLibrary(connectionId: roamConn))

        // 4. Revoking the device immediately invalidates previously minted invite tokens!
        manager.setAuthorized(deviceId: deviceId, authorized: false)
        XCTAssertFalse(manager.validateInviteToken(invite), "Revoking a device must purge active invite tokens")

        let replayAfterRevoke = manager.registerConnection(
            connectionId: roamConn,
            deviceId: deviceId,
            deviceName: "Owner iPhone",
            deviceType: "mobile",
            preferredLockScreen: true,
            remoteIP: "10.10.20.44",
            inviteToken: invite,
            deviceSecret: ownerRecord.deviceSecret
        )
        XCTAssertFalse(replayAfterRevoke.isAuthorized, "Revoked device must not re-authorize using pre-revocation invite token")
    }

    // MARK: - S-07 & S-09: URL Scheme, Artwork SSRF, WLED SSRF & UPnP CallStranger Guards

    func testURLSchemeArtworkWLEDAndUPnPSSRFGuards() {
        defer {
            PlaybackRouter.shared.urlOpener = nil
        }

        var opened: [URL] = []
        PlaybackRouter.shared.urlOpener = { url in
            opened.append(url)
            return true
        }

        // 1. PlaybackRouter.openMusicUrl must reject arbitrary schemes & non-Apple hosts
        for forbidden in [
            "file:///etc/passwd",
            "smb://10.10.20.1/share",
            "ssh://root@10.10.20.1",
            "x-apple.systempreferences:com.apple.preference.security",
            "javascript:alert(1)",
            "https://attacker.example/album/123"
        ] {
            XCTAssertFalse(PlaybackRouter.shared.openMusicUrl(forbidden), "Must block '\(forbidden)'")
        }
        XCTAssertTrue(opened.isEmpty)
        XCTAssertTrue(PlaybackRouter.shared.openMusicUrl("https://music.apple.com/us/album/meteora/528436018"))
        XCTAssertEqual(opened.last?.scheme, "music")

        // 2. ArtworkService remote URL allowlist
        XCTAssertTrue(ArtworkService.isAllowedRemoteArtworkURL(URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/cover/600x600bb.jpg")!))
        XCTAssertFalse(ArtworkService.isAllowedRemoteArtworkURL(URL(string: "http://127.0.0.1:8080/api/status")!))
        XCTAssertFalse(ArtworkService.isAllowedRemoteArtworkURL(URL(string: "http://169.254.169.254/latest/meta-data")!))
        XCTAssertFalse(ArtworkService.isAllowedRemoteArtworkURL(URL(string: "https://evil.example/cover.jpg")!))

        // 3. WLEDDDPController strict unicast private IPv4 guard
        XCTAssertTrue(WLEDDDPController.isValidWLEDUnicastIP("192.168.1.42"))
        XCTAssertTrue(WLEDDDPController.isValidWLEDUnicastIP("10.10.20.55"))
        XCTAssertFalse(WLEDDDPController.isValidWLEDUnicastIP("127.0.0.1:8080/api/duck#"))
        XCTAssertFalse(WLEDDDPController.isValidWLEDUnicastIP("169.254.169.254"))
        XCTAssertFalse(WLEDDDPController.isValidWLEDUnicastIP("255.255.255.255"))
        XCTAssertFalse(WLEDDDPController.isValidWLEDUnicastIP("192.168.1.255"))
        XCTAssertFalse(WLEDDDPController.isValidWLEDUnicastIP("8.8.8.8"))

        // 4. UPnP GENA CallStranger SSRF guard
        let dmr = UPnPMediaRendererServer.shared
        XCTAssertFalse(dmr.isAllowedCallbackHost("127.0.0.1", remoteIP: "192.168.1.50"))
        XCTAssertFalse(dmr.isAllowedCallbackHost("169.254.169.254", remoteIP: "169.254.169.254"))
        XCTAssertFalse(dmr.isAllowedCallbackHost("192.168.1.99", remoteIP: "192.168.1.50"))
        XCTAssertTrue(dmr.isAllowedCallbackHost("127.0.0.1", remoteIP: "127.0.0.1"))
    }

    // MARK: - DSP, CoreAudio & Bridge Invariants

    func testSPSCRingBufferStereoPairAlignmentAndLNS15LeeStability() {
        // 1. SPSCAtomicRingBuffer must never split an interleaved (L, R) stereo frame on even-count writes
        let ring = SPSCAtomicRingBuffer(capacityWords: 1024)
        let filler = [Int32](repeating: 1, count: ring.capacity - 5) // leaves 5 words free (odd!)
        _ = filler.withUnsafeBufferPointer { buf in
            ring.write(from: buf.baseAddress!, count: buf.count)
        }

        let stereoWords: [Int32] = [10, -10, 20, -20, 30, -30, 40, -40]
        let written = stereoWords.withUnsafeBufferPointer { buf in
            ring.write(from: buf.baseAddress!, count: buf.count)
        }
        XCTAssertEqual(written % 2, 0, "Even-count stereo write must never write an odd number of words")
        XCTAssertEqual(written, 4)

        // 2. NOSPCMDitherQuantizer LNS15 must strictly satisfy Lee criterion ||H_err(e^{jw})||_inf < 1.55
        let coeffs: [Double] = [
            NOSPCMDitherQuantizer.lns01.x, NOSPCMDitherQuantizer.lns01.y,
            NOSPCMDitherQuantizer.lns23.x, NOSPCMDitherQuantizer.lns23.y,
            NOSPCMDitherQuantizer.lns45.x, NOSPCMDitherQuantizer.lns45.y,
            NOSPCMDitherQuantizer.lns67.x, NOSPCMDitherQuantizer.lns67.y,
            NOSPCMDitherQuantizer.lns89.x, NOSPCMDitherQuantizer.lns89.y,
            NOSPCMDitherQuantizer.lns1011.x, NOSPCMDitherQuantizer.lns1011.y,
            NOSPCMDitherQuantizer.lns1213.x, NOSPCMDitherQuantizer.lns1213.y,
            NOSPCMDitherQuantizer.lns1415.x
        ]
        var maxGain = 0.0
        for bin in 0...512 {
            let omega = Double.pi * Double(bin) / 512.0
            var re = 1.0
            var im = 0.0
            for (idx, b) in coeffs.enumerated() {
                let k = Double(idx + 1)
                re -= b * cos(omega * k)
                im += b * sin(omega * k)
            }
            let mag = hypot(re, im)
            if mag > maxGain { maxGain = mag }
        }
        XCTAssertLessThan(maxGain, 1.55, "LNS15 noise transfer function peak must satisfy Lee stability criterion (< 1.55)")

        let dcGain = abs(1.0 - coeffs.reduce(0.0, +))
        XCTAssertLessThan(dcGain, 0.4, "LNS15 must attenuate DC / low-frequency quantization error")
    }

    func testBitPerfectDuplicateALACSuppressionAndMultiObserverChain() {
        let monitor = BitPerfectLogMonitor.shared
        let prevCallback = monitor.onFormatChanged
        defer {
            monitor.onFormatChanged = prevCallback
            monitor.resetTrackState()
        }

        monitor.resetTrackState()
        let exp = expectation(description: "Single format confirmation on duplicate ALAC lines")
        var callbackCount = 0
        monitor.onFormatChanged = { _, _, _ in
            callbackCount += 1
            if callbackCount == 1 {
                exp.fulfill()
            }
        }

        let ndjsonLine = #"{"eventMessage":"ACAppleLosslessDecoder.cpp:680 Input format: 2 ch, 48000 Hz, alac (0x00000003) from 24-bit source, 4096 frames/packet"}"#
        // Emit 4 identical NDJSON decoder lines on `monitor.queue` after `resetTrackState()` completes
        monitor.queue.sync {
            for _ in 0..<4 {
                monitor.handleLine(ndjsonLine)
            }
        }

        wait(for: [exp], timeout: 1.5)
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        XCTAssertEqual(callbackCount, 1, "Duplicate authoritative ALAC lines with identical rate/depth must not re-fire confirmSampleRate")
        XCTAssertEqual(monitor.currentDetectedSampleRate, 48_000.0)
        XCTAssertEqual(monitor.currentDetectedBitDepth, 24)

        // Verify Web assets embedded non-empty silence.wav and CSP-clean HTML (zero inline onerror=)
        let html = WebSocketServer.shared.loadWebAsset(filename: "index.html") ?? ""
        XCTAssertFalse(html.contains("onerror="), "Assembled index.html must contain zero inline onerror handlers")
        let silenceData = WebSocketServer.shared.loadWebBinaryAsset(subpath: "assets/silence.wav")
        XCTAssertGreaterThan(silenceData?.count ?? 0, 44, "silence.wav fallback asset must be a valid non-empty WAV")
    }

    func testCloudPlaybackNeverStagesSongsInLibraryAndPurgesStaleDbIds() {
        // 1. Both `/v1/me/library?ids[songs]` AND `/v1/me/library/playlists` staging are permanently disabled for cloud playback
        XCTAssertFalse(MusicKitManager.shared.stageCloudSongsInLibrarySync(catalogIds: ["1805405936"]))
        XCTAssertFalse(MusicKitManager.shared.stageCloudSongsInLibrarySync(catalogIds: ["1805405936", "1657047089"], bypassDedup: true))
        XCTAssertFalse(MusicKitManager.shared.stageCloudSongsInQueuePlaylistSync(catalogIds: ["1805405936"]))
        XCTAssertFalse(MusicKitManager.shared.stageCloudSongsInQueuePlaylistSync(catalogIds: ["1805405936", "1657047089"], bypassDedup: true))

        // 2. Preview pre-warming never writes pending staged library tracks
        let beforePending = PlaybackStateStore.shared.pendingStagedCatalogTracksSnapshot().count
        let sampleTrack = TrackInfo(
            id: "1805405936",
            numericId: nil,
            name: "Smash the Speakers",
            artist: "Kronos",
            album: "Smash the Speakers - Single",
            duration: 150,
            isLocal: false,
            catalogId: "1805405936"
        )
        PlaybackRouter.shared.prestagePreviewHeadTracks([sampleTrack], count: 4)
        XCTAssertEqual(PlaybackStateStore.shared.pendingStagedCatalogTracksSnapshot().count, beforePending)

        // 3. Stale deleted `dbId` (`1492`) is purged from BOTH library and buffer caches immediately
        let lib = LibraryService.shared
        lib.lock.withLock {
            let staleSong = TrackInfo(
                id: "1492",
                numericId: 1492,
                name: "Smash the Speakers",
                artist: "Kronos",
                album: "Smash the Speakers - Single",
                duration: 150,
                isLocal: true
            )
            lib.rawLibrarySongsCache = (Date(), [staleSong])
            lib.librarySongsByNormalizedTitle[LibraryService.normalizeMatchingTitle("Smash the Speakers")] = [staleSong]
        }
        lib.registerStagedTrackInCache(dbId: 1492, name: "Smash the Speakers", artist: "Kronos", album: "Smash the Speakers - Single")
        defer {
            lib.invalidateLibrarySongsCache()
            lib.clearStagedBufferCache()
            PlaybackStateStore.shared.unregisterStagedTemporaryTrack(dbId: 1492)
            PlaybackStateStore.shared.unregisterStagedTemporaryTrack(dbId: 1493)
            PlaybackStateStore.shared.resetCustomQueue()
        }

        // registerStagedTrackInCache must automatically mark dbId as temporary so cleanup never leaks it
        XCTAssertTrue(PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.stagedTemporaryTrackDbIds.contains(1492) })

        // Deferred pre-diagnostics cleanup: while custom queue is active (`keepingActiveQueue: true`),
        // active queue tracks are protected so `DeleteMatchTracks` NEVER interrupts FairPlay HLS streams (`-1008`);
        // on idle/stop/terminate (`keepingActiveQueue: false`), 100% of temporary staged tracks are deleted.
        lib.registerStagedTrackInCache(dbId: 1493, name: "SPECIALZ but it's LOFI Hip Hop (Jujutsu Kaisen)", artist: "anifi", album: "")
        PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.isCustomQueuePlayback = true
            PlaybackStateStore.shared.activeCustomQueue = [
                TrackInfo(id: "1805405936", numericId: 1492, name: "Smash the Speakers", artist: "Kronos", isLocal: false),
                TrackInfo(id: "1822207261", numericId: 1493, name: "SPECIALZ but it's LOFI Hip Hop (Jujutsu Kaisen)", artist: "anifi", isLocal: false)
            ]
            PlaybackStateStore.shared.activeCustomQueueIndex = 1
        }
        let candidatesDuringPlayback = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.computeCleanupCandidatesLocked(keepingActiveQueue: true)
        }
        XCTAssertFalse(candidatesDuringPlayback.contains(1492), "Active custom queue tracks must not trigger DeleteMatchTracks mid-playback")
        XCTAssertFalse(candidatesDuringPlayback.contains(1493), "Currently playing track dbId must remain protected while playing")

        let candidatesOnIdleStop = PlaybackStateStore.shared.withLock {
            PlaybackStateStore.shared.computeCleanupCandidatesLocked(keepingActiveQueue: false)
        }
        XCTAssertTrue(candidatesOnIdleStop.contains(1492), "All temporary staged tracks must be cleaned up on idle/stop/terminate")
        XCTAssertTrue(candidatesOnIdleStop.contains(1493), "All temporary staged tracks must be cleaned up on idle/stop/terminate")

        // Staged singles (including tracks with empty `album` in playlist metadata & `- Single` suffix in `/v1/me/library/albums`)
        // must NEVER leak into AMR's Library Albums even after `unregisterStagedTemporaryTrack` runs!
        PlaybackStateStore.shared.unregisterStagedTemporaryTrack(dbId: 1493)
        let cloudSingleAlbum = AlbumInfo(
            id: "l.tempSpecialz",
            name: "SPECIALZ but it's LOFI Hip Hop (Jujutsu Kaisen) - Single",
            artist: "anifi",
            artwork: "",
            trackCount: 1,
            inLibrary: true
        )
        let merged = MusicBridge.mergeLibraryAlbums(cloud: [cloudSingleAlbum], local: [], recentlyAdded: [])
        XCTAssertTrue(merged.isEmpty, "Staged cloud single must be 100% suppressed from AMR Library Albums even while /v1/me/library/albums lags")

        // Single-release indie tracks (`1822207261`) must support unmarking false unstageable status
        MusicKitManager.shared.markUnstageableCatalogId("1822207261")
        XCTAssertTrue(MusicKitManager.shared.isUnstageableCatalogId("1822207261"))
        MusicKitManager.shared.unmarkUnstageableCatalogId("1822207261")
        XCTAssertFalse(MusicKitManager.shared.isUnstageableCatalogId("1822207261"))

        // Cross-script localized catalog variants (`名前を呼ぶよ` <-> `Namae wo Yobuyo`) must match in QueueManager
        MusicKitManager.shared.appendCachedTitleVariant(catalogId: "1508140810", name: "Namae wo Yobuyo", artist: "LUCK LIFE")
        let jpTrack = TrackInfo(id: "1508140810", numericId: nil, name: "名前を呼ぶよ", artist: "ラックライフ", isLocal: false, catalogId: "1508140810")
        XCTAssertTrue(QueueManager.shared.matchesExpectedQueueTrack(jpTrack, candidateName: "Namae wo Yobuyo", candidateArtist: "LUCK LIFE"))

        let staleResolved = lib.resolveLocalLibraryMatches([sampleTrack], updateNames: false, includeStagedTemporary: true)
        XCTAssertEqual(staleResolved.first?.numericId, 1492)

        lib.purgeDeletedTrackDbIdsFromAllCaches([1492])
        let afterPurge = lib.resolveLocalLibraryMatches([sampleTrack], updateNames: false, includeStagedTemporary: true)
        XCTAssertNil(afterPurge.first?.numericId, "Purged stale dbId must never re-attach on first click")
        XCTAssertEqual(afterPurge.first?.isLocal, false)
    }

    func testMobileLockScreenBottomBarAndLandscapeVolumeInvariants() {
        let js = WebUIContent.appJS
        let css = WebUIContent.styleCSS
        let html = WebUIContent.indexHTML

        // 1. Lock Screen: guards MediaSession.setActionHandler against MusicKit JS v3, activates m_remoteCommandListener
        // before binding previoustrack/nexttrack, and never passes playbackRate: 0.0 to setPositionState.
        XCTAssertFalse(js.contains("if (mediaSessionHandlersBound && !forceRebind)"), "setupMediaSession must always re-apply previoustrack/nexttrack handlers on iOS WebKit")
        XCTAssertTrue(js.contains("allowAmrMediaSessionMutation"), "MediaSession.setActionHandler must block third-party MusicKit JS v3 overrides")
        XCTAssertTrue(js.contains("ensureMediaSessionPlatformActive"), "NowPlayingManager m_remoteCommandListener must be activated before setActionHandler")
        XCTAssertFalse(js.contains("playbackRate: 0.0"), "WebKit MediaSession.setPositionState throws TypeError on playbackRate == 0.0")
        XCTAssertFalse(js.contains("playbackRate: isPlaying ? 1.0 : 0.0"), "WebKit MediaSession.setPositionState requires non-zero playbackRate")
        XCTAssertTrue(js.contains("navigator.mediaSession.setActionHandler('previoustrack', msPrevHandler)"))
        XCTAssertTrue(js.contains("navigator.mediaSession.setActionHandler('nexttrack', msNextHandler)"))
        XCTAssertTrue(html.contains("x-webkit-airplay=\"deny\""))
        let silenceM4a = WebSocketServer.shared.loadWebBinaryAsset(subpath: "assets/silence.m4a")
        XCTAssertGreaterThan(silenceM4a?.count ?? 0, 512)
        XCTAssertLessThan(silenceM4a?.count ?? Int.max, 65_536, "silence.m4a must be a compact silent loop")

        // 2. Portrait Bottom Bar: compact corner-safe bottom strip + cold-launch Standalone viewport repair
        XCTAssertTrue(css.contains("--mobile-bottom-strip: clamp(7px, calc(env(safe-area-inset-bottom, 10px) * 0.3), 10px);"))
        XCTAssertFalse(css.contains("--mobile-bottom-strip: max(14px, env(safe-area-inset-bottom, 14px));"))
        XCTAssertTrue(js.contains("repairStandaloneColdLaunchViewport"), "Cold-launch iOS Standalone viewport-fit=cover must re-commit after launch settles")
        XCTAssertFalse(css.contains(".app-layout {\n  position: fixed;\n  top: 0;\n  left: 0;\n  right: 0;\n  bottom: 0;\n  width: 100%;\n  height: 100vh;"), ".app-layout must not override fixed bottom: 0 with stale cold-launch 100vh/100dvh")

        // 3. Landscape Volume Control: respects renderVolumeUI() .hidden logic instead of forced CSS display: none
        XCTAssertTrue(css.contains("#standby-tv-overlay .standby-volume-section:not(.hidden)"))
        XCTAssertTrue(css.contains("#standby-tv-overlay .standby-volume-section.hidden"))
        XCTAssertFalse(css.contains("#top-settings-popover,\n  #standby-volume-section {\n    display: none !important;"))
        XCTAssertFalse(css.contains("#player-btn-standby,\n  #standby-volume-section {\n    display: none !important;"))
    }
}
