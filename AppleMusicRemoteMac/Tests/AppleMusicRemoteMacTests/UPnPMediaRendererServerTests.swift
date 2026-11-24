//
//  UPnPMediaRendererServerTests.swift
//  AppleMusicRemoteMacTests
//

import Network
import XCTest
@testable import AppleMusicRemoteMac

final class UPnPMediaRendererServerTests: XCTestCase {

    func testDeviceDescriptionContainsAllRequiredServices() {
        let server = UPnPMediaRendererServer.shared
        let xml = server.buildDeviceDescriptionXML()

        // 1. Root and device headers
        XCTAssertTrue(xml.contains("<deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>"))
        XCTAssertTrue(xml.contains("<friendlyName>"))
        XCTAssertTrue(xml.contains("<modelName>AMR-MediaRenderer</modelName>"))
        XCTAssertTrue(xml.contains("<UDN>"))

        // 2. AVTransport Service
        XCTAssertTrue(xml.contains("<serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>"))
        XCTAssertTrue(xml.contains("<controlURL>/upnp/control/avtransport</controlURL>"))
        XCTAssertTrue(xml.contains("<eventSubURL>/upnp/event/avtransport</eventSubURL>"))
        XCTAssertTrue(xml.contains("<SCPDURL>/upnp/scpd/avtransport.xml</SCPDURL>"))

        // 3. RenderingControl Service (essential for Home Assistant volume and mute)
        XCTAssertTrue(xml.contains("<serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>"))
        XCTAssertTrue(xml.contains("<controlURL>/upnp/control/renderingcontrol</controlURL>"))
        XCTAssertTrue(xml.contains("<eventSubURL>/upnp/event/renderingcontrol</eventSubURL>"))
        XCTAssertTrue(xml.contains("<SCPDURL>/upnp/scpd/renderingcontrol.xml</SCPDURL>"))

        // 4. ConnectionManager Service
        XCTAssertTrue(xml.contains("<serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>"))
        XCTAssertTrue(xml.contains("<controlURL>/upnp/control/connectionmanager</controlURL>"))
        XCTAssertTrue(xml.contains("<eventSubURL>/upnp/event/connectionmanager</eventSubURL>"))
        XCTAssertTrue(xml.contains("<SCPDURL>/upnp/scpd/connectionmanager.xml</SCPDURL>"))
    }

    func testFormatSecondsToTime() {
        let server = UPnPMediaRendererServer.shared
        XCTAssertEqual(server.formatSecondsToTime(0), "00:00:00")
        XCTAssertEqual(server.formatSecondsToTime(-10), "00:00:00")
        XCTAssertEqual(server.formatSecondsToTime(5), "00:00:05")
        XCTAssertEqual(server.formatSecondsToTime(65), "00:01:05")
        XCTAssertEqual(server.formatSecondsToTime(3600), "01:00:00")
        XCTAssertEqual(server.formatSecondsToTime(3665), "01:01:05")
    }

    func testParseTimeToSeconds() {
        let server = UPnPMediaRendererServer.shared
        XCTAssertEqual(server.parseTimeToSeconds("00:00:00"), 0.0)
        XCTAssertEqual(server.parseTimeToSeconds("00:01:05"), 65.0)
        XCTAssertEqual(server.parseTimeToSeconds("01:01:05"), 3665.0)
        XCTAssertEqual(server.parseTimeToSeconds("02:30"), 150.0)
        XCTAssertEqual(server.parseTimeToSeconds("45"), 45.0)
    }

    func testEscapeXMLText() {
        let server = UPnPMediaRendererServer.shared
        let raw = "Rock & Roll <Live> \"AC/DC\" 'Back in Black'"
        let escaped = server.escapeXMLText(raw)
        XCTAssertEqual(escaped, "Rock &amp; Roll &lt;Live&gt; &quot;AC/DC&quot; &apos;Back in Black&apos;")
    }

    func testGenerateDIDLLiteXML() {
        let server = UPnPMediaRendererServer.shared
        let didl = server.generateDIDLLiteXML(
            title: "Comfortably Numb",
            artist: "Pink Floyd & Friends",
            album: "The Wall",
            artUri: "http://127.0.0.1:8090/artwork/current.jpg",
            durTimeStr: "00:06:22"
        )

        XCTAssertTrue(didl.contains("<dc:title>Comfortably Numb</dc:title>"))
        XCTAssertTrue(didl.contains("<dc:creator>Pink Floyd &amp; Friends</dc:creator>"))
        XCTAssertTrue(didl.contains("The Wall"))
        XCTAssertTrue(didl.contains("http://127.0.0.1:8090/artwork/current.jpg"))
        XCTAssertTrue(didl.contains("duration=\"00:06:22\""))
        XCTAssertTrue(didl.contains("xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\""))
    }

    func testArtworkURIWithAmpersandsEscapedInDIDL() {
        let server = UPnPMediaRendererServer.shared
        let artUriWithParams = "http://10.10.20.180:8080/api/artwork/track?id=3456&name=Self%20Esteem&artist=The%20Offspring"
        let didl = server.generateDIDLLiteXML(
            title: "Self Esteem",
            artist: "The Offspring",
            album: "Smash",
            artUri: artUriWithParams,
            durTimeStr: "00:04:17"
        )

        // In DIDL-Lite, & must be escaped as &amp;
        XCTAssertTrue(didl.contains("http://10.10.20.180:8080/api/artwork/track?id=3456&amp;name=Self%20Esteem&amp;artist=The%20Offspring"))
        XCTAssertFalse(didl.contains("&name="))
    }

    func testArtworkURIEscapingForLastChange() {
        let server = UPnPMediaRendererServer.shared
        let artUriWithParams = "http://10.10.20.180:8080/api/artwork/track?id=3456&name=Self%20Esteem&artist=The%20Offspring"
        let escaped = server.escapeForLastChangeVal(artUriWithParams)

        // Inside LastChange element, & in attributes must be &amp;amp; so outer XML parser doesn't break
        XCTAssertTrue(escaped.contains("&amp;amp;name="))
        XCTAssertFalse(escaped.contains("&name="))
    }

    func testLocalDMRToggleAndPersistence() {
        let server = UPnPMediaRendererServer.shared
        UserDefaults.standard.removeObject(forKey: UPnPMediaRendererServer.defaultsKey)

        // Default should be true
        XCTAssertTrue(server.isEnabled)

        // Toggle to false
        server.setEnabled(false)
        XCTAssertFalse(server.isEnabled)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: UPnPMediaRendererServer.defaultsKey))

        // startIfEnabled should return false when disabled
        XCTAssertFalse(server.startIfEnabled(port: 8090))

        // Toggle back to true (persist preference without leaving network listener active in test process)
        server.isEnabled = true
        server.stop()
        SSDPService.shared.stop()
        XCTAssertTrue(server.isEnabled)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: UPnPMediaRendererServer.defaultsKey))
    }

    func testMultiVLANPrivateLANGuardAllowsLocalVLANsAndBlocksWANOrMetadata() {
        // Multi-VLAN private RFC1918 & IPv6 ULA peers (Home Assistant on 10.10.10.11 / 10.10.30.4, BluOS on 10.10.30.9)
        XCTAssertTrue(LANSubnetGuard.isPrivateLANOrLoopbackPeer("127.0.0.1"))
        XCTAssertTrue(LANSubnetGuard.isPrivateLANOrLoopbackPeer("10.10.10.11"))
        XCTAssertTrue(LANSubnetGuard.isPrivateLANOrLoopbackPeer("10.10.30.4"))
        XCTAssertTrue(LANSubnetGuard.isPrivateLANOrLoopbackPeer("172.20.5.12"))
        XCTAssertTrue(LANSubnetGuard.isPrivateLANOrLoopbackPeer("192.168.50.10"))
        XCTAssertTrue(LANSubnetGuard.isPrivateLANOrLoopbackPeer("fd12:3456:789a::10"))

        // WAN, CGNAT, cloud metadata, multicast, and /24 broadcast must remain blocked
        XCTAssertFalse(LANSubnetGuard.isPrivateLANOrLoopbackPeer("8.8.8.8"))
        XCTAssertFalse(LANSubnetGuard.isPrivateLANOrLoopbackPeer("100.64.10.5"))
        XCTAssertFalse(LANSubnetGuard.isPrivateLANOrLoopbackPeer("169.254.169.254"))
        XCTAssertFalse(LANSubnetGuard.isPrivateLANOrLoopbackPeer("239.255.255.250"))
        XCTAssertFalse(LANSubnetGuard.isPrivateLANOrLoopbackPeer("10.10.30.255"))

        // GENA CallStranger SSRF check allows matching multi-VLAN subscriber IP, rejects mismatched or link-local
        let dmr = UPnPMediaRendererServer.shared
        XCTAssertTrue(dmr.isAllowedCallbackHost("10.10.10.11", remoteIP: "10.10.10.11"))
        XCTAssertTrue(dmr.isAllowedCallbackHost("10.10.30.4", remoteIP: "10.10.30.4"))
        XCTAssertFalse(dmr.isAllowedCallbackHost("10.10.30.9", remoteIP: "10.10.10.11"))
        XCTAssertFalse(dmr.isAllowedCallbackHost("169.254.10.20", remoteIP: "169.254.10.20"))
    }

    func testHomeAssistantArtworkAuthAcrossVLANsAndEncodedStreamTokens() {
        let ws = WebSocketServer.shared
        let dlna = DLNADiscoveryManager.shared
        let token = dlna.currentStreamSessionToken

        let haConn = NWConnection(host: "10.10.10.11", port: 8080, using: .tcp)
        let wanConn = NWConnection(host: "8.8.8.8", port: 8080, using: .tcp)

        let haHeaders = "GET /api/artwork.jpg HTTP/1.1\r\nHost: 10.10.20.74:8080\r\nUser-Agent: HomeAssistant/2026.11 aiohttp/3.10\r\n\r\n"
        // 1. Valid stream_token from Home Assistant on another VLAN succeeds (even if renderer IP is 10.10.30.9)
        XCTAssertTrue(
            ws.isAllowedLANArtworkRequest(
                headerString: haHeaders,
                fullPath: "/api/artwork.jpg?t=1795242788&stream_token=\(token)",
                connection: haConn
            )
        )
        // 2. Percent-encoded query string from UPnP/BluOS XML re-serialization also succeeds
        XCTAssertTrue(
            ws.isAllowedLANArtworkRequest(
                headerString: haHeaders,
                fullPath: "/api/artwork.jpg?t%3D1795242788%26stream_token%3D\(token)",
                connection: haConn
            )
        )
        // 3. WAN IP is rejected even with a valid stream_token
        XCTAssertFalse(
            ws.isAllowedLANArtworkRequest(
                headerString: haHeaders,
                fullPath: "/api/artwork.jpg?t=1795242788&stream_token=\(token)",
                connection: wanConn
            )
        )
        // 4. Unpaired browser with Mozilla User-Agent without stream_token is rejected
        let browserHeaders = "GET /api/artwork/track?id=42 HTTP/1.1\r\nHost: 10.10.20.74:8080\r\nUser-Agent: Mozilla/5.0\r\nSec-Fetch-Dest: image\r\n\r\n"
        XCTAssertFalse(
            ws.isAllowedLANArtworkRequest(
                headerString: browserHeaders,
                fullPath: "/api/artwork/track?id=42",
                connection: haConn
            )
        )
        // 5. Non-browser Home Assistant UPnP client fetching relative DMR artwork succeeds when DMR is enabled
        UPnPMediaRendererServer.shared.isEnabled = true
        XCTAssertTrue(
            ws.isAllowedLANArtworkRequest(
                headerString: haHeaders,
                fullPath: "/api/artwork/track?id=42",
                connection: haConn
            )
        )
    }

    func testBluOSPauseWaitPlayResumesAndPreservesStreamTokenAcrossRotation() {
        let dlna = DLNADiscoveryManager.shared
        let prevActive = dlna.activeRendererUID
        defer {
            dlna.stop()
            dlna.activeRendererUID = prevActive
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.isUserPaused = false
            }
        }

        let r1 = DiscoveredDLNARenderer(
            id: "bluos:TESTNODE01",
            friendlyName: "Living Room NODE",
            manufacturer: "Bluesound",
            modelName: "NODE NANO",
            locationURL: URL(string: "http://192.168.254.99:11000/SyncStatus")!,
            isBluOS: true,
            bluOSBaseURL: URL(string: "http://192.168.254.99:11000")!
        )
        let r2 = DiscoveredDLNARenderer(
            id: "bluos:TESTNODE02",
            friendlyName: "Bedroom NODE",
            manufacturer: "Bluesound",
            modelName: "NODE NANO",
            locationURL: URL(string: "http://10.10.30.10:11000/SyncStatus")!,
            isBluOS: true,
            bluOSBaseURL: URL(string: "http://10.10.30.10:11000")!
        )
        dlna.registerDevice(r1)
        dlna.registerDevice(r2)

        _ = dlna.selectRenderer(uid: r1.id)
        let firstToken = dlna.currentStreamSessionToken
        XCTAssertTrue(dlna.validateStreamSessionToken(firstToken))

        // Switching to a second renderer rotates token while keeping previous token valid for in-flight cover fetches
        _ = dlna.selectRenderer(uid: r2.id)
        let secondToken = dlna.currentStreamSessionToken
        XCTAssertNotEqual(firstToken, secondToken)
        XCTAssertTrue(dlna.validateStreamSessionToken(secondToken))
        XCTAssertTrue(dlna.validateStreamSessionToken(firstToken))

        // Simulate Pause -> Wait -> Play from Home Assistant on NODE (even < 3.5s after Pause!)
        _ = MusicBridge.shared.pause()
        dlna.pause()
        XCTAssertTrue(dlna.isRendererPausedOrStopped)

        dlna.lock.withLock {
            dlna.lastKnownBluOSState = "pause"
            dlna.lastLocalActionDate = Date().addingTimeInterval(-1.2)
        }
        dlna.handleBluOSStateUpdate(state: "play", service: "Capture", notifyURL: "")
        XCTAssertFalse(dlna.isRendererPausedOrStopped)
        XCTAssertFalse(PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isUserPaused })
    }

    func testVolumeLockHidesAndBlocksVolumeSliderEvenWhenNodeNanoDLNAIsSelected() {
        let dlna = DLNADiscoveryManager.shared
        let store = PlaybackStateStore.shared
        let prevActive = dlna.activeRendererUID
        let prevLock = store.isVolumeLockedTo100
        let prevAmp = ExternalAmpTCPController.shared.isEnabled
        defer {
            dlna.stop()
            dlna.activeRendererUID = prevActive
            store.isVolumeLockedTo100 = prevLock
            ExternalAmpTCPController.shared.isEnabled = prevAmp
        }

        let nodeNano = DiscoveredDLNARenderer(
            id: "bluos:905682B70680",
            friendlyName: "Гостиная (Bluesound NODE NANO)",
            manufacturer: "Bluesound",
            modelName: "NODE NANO",
            locationURL: URL(string: "http://192.168.254.99:11000/SyncStatus")!,
            isBluOS: true,
            bluOSBaseURL: URL(string: "http://192.168.254.99:11000")!
        )
        dlna.registerDevice(nodeNano)
        _ = dlna.selectRenderer(uid: nodeNano.id)
        dlna.setVolume(65)

        ExternalAmpTCPController.shared.isEnabled = false
        store.isVolumeLockedTo100 = true

        // 1. Backend rejects volume changes (< 100%) on NODE NANO when volume lock is enabled
        XCTAssertFalse(PlaybackTransportController.shared.setVolume(40))
        var status = PlayerStatus(volume: 65, isVolumeLockedTo100: true)
        _ = PlayerStatusEngine.shared.applyLiveAudioPipelineOverlay(to: &status, updateTapFormatIfNeeded: false)
        XCTAssertEqual(status.isDlnaActive, true)
        XCTAssertEqual(status.volume, 100)

        // 2. When volume lock is disabled, NODE NANO hardware volume is exposed and controllable
        store.isVolumeLockedTo100 = false
        XCTAssertTrue(PlaybackTransportController.shared.setVolume(55))
        var unlockedStatus = PlayerStatus(volume: 100, isVolumeLockedTo100: false)
        _ = PlayerStatusEngine.shared.applyLiveAudioPipelineOverlay(to: &unlockedStatus, updateTapFormatIfNeeded: false)
        XCTAssertEqual(unlockedStatus.volume, 55)

        // 3. Assembled Web UI hides volume slider whenever `state.lockVolume100 && !isExtAmpMode` regardless of `isDlnaActive`
        let appJS = WebSocketServer.shared.loadWebAsset(filename: "app.js") ?? ""
        XCTAssertTrue(appJS.contains("if (state.lockVolume100 && !isExtAmpMode) {"))
        XCTAssertFalse(appJS.contains("if (state.lockVolume100 && !isExtAmpMode && !isDlnaHardwareVol)"))
    }

    func testDMRDurationFallbackAndGENAReEmissionWhenCloudDurationResolves() {
        let server = UPnPMediaRendererServer.shared
        let store = PlaybackStateStore.shared
        let prevEnabled = server.isEnabled
        defer {
            server.isEnabled = prevEnabled
            server.subQueue.sync {
                server.subscriptions.removeAll()
                server.syncCachedSubscriberCountLocked()
            }
            store.withLock {
                store.isCustomQueuePlayback = false
                store.activeCustomQueue = []
                store.activeCustomQueueIndex = 0
                store.scheduledSmartTransitionStart = nil
            }
        }

        server.isEnabled = true

        // 1. SCPD exposes ABS_TIME + REL_TIME Seek modes and SetPlayMode / CurrentPlayMode values for Home Assistant dlna_dmr
        let scpd = UPnPMediaRendererServer.avTransportSCPD
        XCTAssertTrue(scpd.contains("<allowedValue>ABS_TIME</allowedValue>"))
        XCTAssertTrue(scpd.contains("<allowedValue>REL_TIME</allowedValue>"))
        XCTAssertTrue(scpd.contains("<name>SetPlayMode</name>"))
        XCTAssertTrue(scpd.contains("<allowedValue>REPEAT_ONE</allowedValue>"))

        // 2. Fallback duration resolves from activeCustomQueue or scheduledSmartTransitionStart when Music.app initially reports 0.0
        let queueTrack = TrackInfo(id: "cloud-1", name: "Running Up That Hill", artist: "Samuel Kim", duration: 135.0)
        store.withLock {
            store.isCustomQueuePlayback = true
            store.activeCustomQueue = [queueTrack]
            store.activeCustomQueueIndex = 0
        }
        let zeroDurStatus = PlayerStatus(
            playerState: "playing",
            position: 0.4,
            duration: 0.0,
            volume: 100,
            shuffle: true,
            repeatMode: "all",
            track: TrackInfo(id: "cloud-1", name: "Running Up That Hill", artist: "Samuel Kim", duration: 0.0)
        )
        XCTAssertEqual(server.resolveEffectiveTrackDuration(for: zeroDurStatus), 135.0, accuracy: 0.01)
        XCTAssertEqual(server.resolveUPnPPlayMode(for: zeroDurStatus), "RANDOM")

        // 3. GENA notifySubscribers does NOT suppress the update when track duration transitions from 0s -> 189s
        store.withLock {
            store.isCustomQueuePlayback = false
            store.activeCustomQueue = []
            store.scheduledSmartTransitionStart = nil
        }

        let testSub = UPnPMediaRendererServer.EventSubscription(
            sid: "uuid:test-ha-sub",
            callbackURL: URL(string: "http://127.0.0.1:65530/notify")!,
            path: "/upnp/event/avtransport",
            seq: 0,
            expiryDate: Date().addingTimeInterval(1800),
            failureCount: 0
        )
        server.subQueue.sync {
            server.subscriptions = [testSub]
            server.syncCachedSubscriberCountLocked()
            server.lastNotifiedTime = .distantPast
            server.lastNotifiedDurationSec = -1
        }
        XCTAssertTrue(server.hasActiveSubscribers)

        let initialZero = PlayerStatus(
            playerState: "playing",
            position: 0.0,
            duration: 0.0,
            volume: 100,
            track: TrackInfo(id: "radio-1", name: "Spider-Man 2099", artist: "Carameii", duration: 0.0)
        )
        let exp1 = expectation(description: "Initial 0s duration notification")
        server.notifySubscribers(status: initialZero, force: false) { exp1.fulfill() }
        wait(for: [exp1], timeout: 4.0)
        XCTAssertEqual(server.subQueue.sync { server.subscriptions.first?.seq }, 1)
        XCTAssertEqual(server.subQueue.sync { server.lastNotifiedDurationSec }, 0)

        // Restore subscription if local loopback 65530 connection error incremented failureCount (still 1 < 2)
        let resolvedStatus = PlayerStatus(
            playerState: "playing",
            position: 1.1,
            duration: 189.0,
            volume: 100,
            track: TrackInfo(id: "radio-1", name: "Spider-Man 2099", artist: "Carameii", duration: 189.0)
        )
        let exp2 = expectation(description: "Resolved 189s duration notification")
        server.notifySubscribers(status: resolvedStatus, force: false) { exp2.fulfill() }
        wait(for: [exp2], timeout: 4.0)
        XCTAssertEqual(server.subQueue.sync { server.lastNotifiedDurationSec }, 189)
    }

    func testBluOSStreamInstancePrevDetectionAndWakeMonitoringRestart() {
        let dlna = DLNADiscoveryManager.shared
        let store = PlaybackStateStore.shared
        let prevActive = dlna.activeRendererUID
        defer {
            dlna.stop()
            dlna.activeRendererUID = prevActive
            store.withLock {
                store.isCustomQueuePlayback = false
                store.activeCustomQueue = []
                store.activeCustomQueueIndex = 0
                store.isUserPaused = false
            }
        }

        let nodeNano = DiscoveredDLNARenderer(
            id: "bluos:905682B70680",
            friendlyName: "Гостиная (Bluesound NODE NANO)",
            manufacturer: "Bluesound",
            modelName: "NODE NANO",
            locationURL: URL(string: "http://192.168.254.99:11000/SyncStatus")!,
            isBluOS: true,
            bluOSBaseURL: URL(string: "http://192.168.254.99:11000")!
        )
        dlna.registerDevice(nodeNano)
        _ = dlna.selectRenderer(uid: nodeNano.id)

        // 1. Re-registering existing BluOS renderer after wake/stopInternal restarts bluOSPollingTask even when isNew == false
        dlna.stopBluOSStatusMonitoring()
        XCTAssertNil(dlna.bluOSPollingTask)
        dlna.registerDevice(nodeNano)
        XCTAssertNotNil(dlna.bluOSPollingTask)

        // 2. Stream URL includes unique `sid=` instance identifier and rapid same-sid client restart triggers previous track
        let t1 = TrackInfo(id: "101", numericId: 101, name: "Track One", artist: "Artist A", duration: 180, isLocal: true)
        let t2 = TrackInfo(id: "102", numericId: 102, name: "Track Two", artist: "Artist B", duration: 200, isLocal: true)
        store.withLock {
            store.isCustomQueuePlayback = true
            store.activeCustomQueue = [t1, t2]
            store.activeCustomQueueIndex = 1
            store.isUserPaused = false
            store.lastPlayerStatusCache = (
                Date(),
                PlayerStatus(playerState: "playing", position: 25.0, duration: 200.0, volume: 100, track: t2)
            )
        }
        dlna.lock.withLock {
            dlna.lastTrackId = t2.id
            dlna.lastTrackTitle = t2.name
            dlna.lastTrackArtist = t2.artist
        }
        PlaybackTransportController.shared.resetDebounceForTesting()

        let (streamURL, _, _, _) = dlna.resolveStreamAndImageURLs(sampleRate: 44100, bitDepth: 16, isBluOS: true)
        let comps = URLComponents(string: streamURL)
        let sid = comps?.queryItems?.first(where: { $0.name == "sid" })?.value
        XCTAssertNotNil(sid)

        // Initial connection
        dlna.noteDLNALiveStreamConnected(sid: sid)
        dlna.lock.withLock {
            dlna.activeStreamFirstConnectedAt = Date().addingTimeInterval(-10.0)
            dlna.lastLocalActionDate = Date().addingTimeInterval(-10.0)
            dlna.isExplicitlyPaused = false
        }

        // Simulate BluOS `/Back` (Prev button): client disconnects and reconnects to same `sid` within 30ms
        dlna.noteDLNALiveStreamClientDisconnected(sid: sid)
        Thread.sleep(forTimeInterval: 0.025)
        dlna.noteDLNALiveStreamConnected(sid: sid)

        let exp = expectation(description: "Wait for async previousTrack dispatch")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        let updatedIdx = store.withLock { store.activeCustomQueueIndex }
        XCTAssertEqual(updatedIdx, 0, "Rapid same-sid BluOS stream restart (/Back) should step back to track index 0")
    }
}
