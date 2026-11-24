//
//  DLNADiscoveryManager+StreamingAndBluOS.swift
//  AppleMusicRemoteMac
//
//  BluOS two-way long-polling status monitor (percent-encoded etag, LAN SSRF &
//  no-redirect guard) and authenticated live WAV stream / artwork URL builder.
//

import Foundation

extension DLNADiscoveryManager {
    public func startBluOSStatusMonitoring(renderer: DiscoveredDLNARenderer) {
        stopBluOSStatusMonitoring()
        lock.withLock {
            lastKnownBluOSState = ""
        }
        guard renderer.isBluOS,
              let baseURL = renderer.bluOSBaseURL,
              Self.isAllowedLANRendererURL(baseURL) else { return }

        bluOSPollingTask = Task { [weak self] in
            if PlaybackRouter.shared.isTestingEnvironment {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                return
            }
            var lastEtag: String? = nil
            var isFirst = true
            while !Task.isCancelled {
                guard let self = self, self.hasActiveRenderer else { break }

                var comps = URLComponents(string: "\(baseURL.absoluteString)/Status")
                if let etag = lastEtag, !isFirst {
                    comps?.queryItems = [
                        URLQueryItem(name: "timeout", value: "15"),
                        URLQueryItem(name: "etag", value: etag)
                    ]
                }
                isFirst = false

                guard let url = comps?.url, Self.isAllowedLANRendererURL(url) else { break }
                var req = URLRequest(url: url)
                req.timeoutInterval = 20.0

                do {
                    let (data, httpResp) = try await BoundedNoRedirectHTTPClient.shared.fetchAsync(request: req, maxBytes: 256 * 1024)
                    if Task.isCancelled { break }
                    guard (200...299).contains(httpResp.statusCode) else {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        continue
                    }
                    if let xml = String(data: data, encoding: .utf8) {
                        if let etag = self.extractXMLAttribute(attr: "etag", from: xml) {
                            lastEtag = etag
                        }
                        self.handleBluOSVolumeFromXML(xml: xml, rendererID: renderer.id)
                        let service = self.extractXMLTagValue(tag: "service", from: xml) ?? ""
                        let notifyURL = self.extractXMLTagValue(tag: "notifyurl", from: xml) ?? ""
                        if let state = self.extractXMLTagValue(tag: "state", from: xml) {
                            self.handleBluOSStateUpdate(state: state, service: service, notifyURL: notifyURL)
                        }
                    }
                } catch {
                    if Task.isCancelled { break }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
    }

    public func stopBluOSStatusMonitoring() {
        bluOSPollingTask?.cancel()
        bluOSPollingTask = nil
        lock.withLock {
            lastKnownBluOSState = ""
        }
    }

    internal func handleBluOSVolumeFromXML(xml: String, rendererID: String, ignoreSuppressionWindow: Bool = false) {
        let volVal: Int? = {
            if let vStr = extractXMLTagValue(tag: "volume", from: xml)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let d = Double(vStr), d.isFinite {
                return max(0, min(100, Int(d.rounded())))
            }
            return nil
        }()
        let muteVal: Bool? = {
            if let mStr = extractXMLTagValue(tag: "mute", from: xml)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return mStr == "1" || mStr.lowercased() == "true"
            }
            return nil
        }()
        guard volVal != nil || muteVal != nil else { return }

        var didChange = false
        lock.lock()
        let sinceLocalVol = Date().timeIntervalSince(lastLocalVolumeCommandDate)
        if ignoreSuppressionWindow || sinceLocalVol > 3.0 {
            if let v = volVal, v >= 0 {
                if rendererVolumesByUID[rendererID] != v {
                    rendererVolumesByUID[rendererID] = v
                    UserDefaults.standard.set(rendererVolumesByUID, forKey: Self.rendererVolumesDefaultsKey)
                    didChange = true
                }
            }
            if let m = muteVal, rendererMutedState != m {
                rendererMutedState = m
                didChange = true
            }
        }
        lock.unlock()

        if didChange {
            PlaybackStateStore.shared.invalidateStatusCache()
            WebSocketServer.shared.broadcastStatus(includeQueue: false)
        }
    }

    internal static func isExternalBluOSService(_ rawService: String) -> Bool {
        let s = rawService.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return false }
        let external: Set<String> = [
            "spotify", "tidal", "qobuz", "deezer", "airplay", "bluetooth", "roon", "radio paradise", "amazon"
        ]
        return external.contains(s)
    }

    internal func handleBluOSStateUpdate(state: String, service: String = "", notifyURL: String = "") {
        let cleanState = state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanNotify = notifyURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let (prevState, wasExplicitlyPaused): (String, Bool) = lock.withLock {
            let prev = lastKnownBluOSState
            let wasPaused = isExplicitlyPaused
            lastKnownBluOSState = cleanState
            return (prev, wasPaused)
        }

        let elapsed = timeSinceLastLocalAction()
        let musicStatus = MusicBridge.shared.getPlayerStatus()
        let isExternalService = Self.isExternalBluOSService(service)

        if cleanState == "pause" || cleanState == "stop" {
            // Self-heal if BluOS aborted our live WAV stream with `/error?9` while Apple Music is actively playing
            if cleanNotify.hasPrefix("/error"), musicStatus.isPlaying, !isExternalService {
                let canRecover: Bool = lock.withLock {
                    guard Date().timeIntervalSince(lastBluOSStreamRecoveryDate) > 6.0 else { return false }
                    lastBluOSStreamRecoveryDate = Date()
                    return true
                }
                if canRecover {
                    NSLog("[DLNADiscovery] 🔄 BluOS reported stream error '%@' while playing — re-pushing live WAV stream.", cleanNotify)
                    play()
                    return
                }
            }

            if elapsed < 3.5 {
                NSLog("[DLNADiscovery] ⏳ Ignoring BluOS state '%@' (recent local action %.1fs ago)", cleanState, elapsed)
                return
            }

            lock.withLock { isExplicitlyPaused = true }
            if musicStatus.isPlaying {
                NSLog("[DLNADiscovery] ⏸️ BluOS reported %@ state. Pausing Apple Music.", cleanState)
                markLocalAction()
                _ = MusicBridge.shared.pause()
                UPnPMediaRendererServer.shared.notifySubscribers(force: true)
                WebSocketServer.shared.broadcastStatus()
            }
        } else if cleanState == "stream" || cleanState == "play" || cleanState == "connecting" {
            let resumedFromPaused = (prevState == "pause" || prevState == "stop" || wasExplicitlyPaused)
            // Once BluOS already confirmed 'pause'/'stop', only a short 0.55s settle guard is needed so fast HA Pause->Play works!
            let suppressionWindow: TimeInterval = resumedFromPaused ? 0.55 : 3.5
            if elapsed < suppressionWindow {
                NSLog("[DLNADiscovery] ⏳ Ignoring BluOS state '%@' (recent local action %.1fs ago)", cleanState, elapsed)
                return
            }

            lock.withLock { isExplicitlyPaused = false }
            if !musicStatus.isPlaying && resumedFromPaused {
                NSLog("[DLNADiscovery] ▶️ BluOS transitioned from '%@' to '%@'. Resuming Apple Music & refreshing live stream.", prevState, cleanState)
                markLocalAction()
                _ = MusicBridge.shared.play()
                if !isExternalService {
                    // Unseekable `/stream/live.wav` cannot be reliably resumed on BluOS after a pause wait or UPnP Play;
                    // re-push a fresh `/Play?url=...` stream URI exactly like the AMR Web UI Play action!
                    play()
                }
                UPnPMediaRendererServer.shared.notifySubscribers(force: true)
                WebSocketServer.shared.broadcastStatus()
            } else if musicStatus.isPlaying && !isExternalService && !PlaybackRouter.shared.isTestingEnvironment && !WebSocketServer.shared.hasActiveLiveStreamConnections {
                let canRecover: Bool = lock.withLock {
                    guard Date().timeIntervalSince(lastBluOSStreamRecoveryDate) > 6.0 else { return false }
                    lastBluOSStreamRecoveryDate = Date()
                    return true
                }
                if canRecover {
                    NSLog("[DLNADiscovery] 🔄 BluOS entered '%@' with 0 live stream subscribers — re-attaching live WAV stream.", cleanState)
                    play()
                }
            }
        }
    }

    // MARK: - Sample Rate Change & Stream URL Resolution

    public func closeLiveStreamConnectionsForFormatSwitch() {
        guard !PlaybackRouter.shared.isTestingEnvironment else { return }
        WebSocketServer.shared.closeLiveStreamConnections()
    }

    @objc internal func handleFormatChangedNotification(_ notification: Notification) {
        guard BitPerfectLogMonitor.shared.isEnabled || AudioEngineController.shared.currentConfigurationSnapshot().mode != .bitPerfectPassthrough else { return }
        guard let userInfo = notification.userInfo,
              let rate = userInfo["sampleRate"] as? Double else { return }
        let bitDepth = (userInfo["bitDepth"] as? Int) ?? (rate >= 48000.0 ? 24 : 16)
        handleTrackFormatChanged(sampleRate: Int(rate), bitDepth: bitDepth)
    }

    public func resolveStreamAndImageURLs(
        sampleRate: Int? = nil,
        bitDepth: Int? = nil,
        isBluOS: Bool? = nil
    ) -> (streamURL: String, imageURL: String, title: String, metadata: String) {
        let lanIP = WebSocketServer.shared.getLANIPAddresses().first ?? "127.0.0.1"
        let port = WebSocketServer.shared.port
        let status = MusicBridge.shared.getPlayerStatus()
        let isLossy = status.audioQuality.contains("AAC") || status.audioQuality.contains("MP3") || (!BitPerfectLogMonitor.shared.currentIsLossless && sampleRate == nil)
        let rate = sampleRate ?? (isLossy ? 44100 : (status.track?.sampleRate ?? BitPerfectLogMonitor.shared.currentDetectedSampleRate.map { Int($0) } ?? AudioProcessTapService.shared.sampleRate))
        let depth: Int
        if let explicitDepth = bitDepth {
            depth = explicitDepth
        } else if sampleRate != nil {
            depth = rate >= 48000 ? 24 : (isLossy ? 16 : (status.track?.bitDepth ?? BitPerfectLogMonitor.shared.currentDetectedBitDepth ?? 16))
        } else if isLossy {
            depth = 16
        } else {
            depth = status.track?.bitDepth ?? BitPerfectLogMonitor.shared.currentDetectedBitDepth ?? (rate >= 48000 ? 24 : 16)
        }

        let effectiveDepth = (depth == 16) ? 16 : 24
        if AudioProcessTapService.shared.subscriberCount > 0,
           (AudioProcessTapService.shared.sampleRate != rate || AudioProcessTapService.shared.bitDepth != effectiveDepth) {
            closeLiveStreamConnectionsForFormatSwitch()
        }
        AudioProcessTapService.shared.setFormat(sampleRate: rate, bitDepth: depth)

        let timestamp = Int(Date().timeIntervalSince1970)
        let token = currentStreamSessionToken
        let streamInstanceID = ClientDeviceRecord.generateRandomHexSecret(byteCount: 6)
        lock.withLock {
            activeStreamInstanceID = streamInstanceID
            activeStreamFirstConnectedAt = nil
            activeStreamLastClientDisconnectedAt = nil
        }
        let streamURL = "http://\(lanIP):\(port)/stream/live.wav?rate=\(rate)&bits=\(depth)&t=\(timestamp)&sid=\(streamInstanceID)&stream_token=\(token)"

        let trackName = status.track?.name ?? "Apple Music"
        let trackArtist = status.track?.artist ?? ""
        let fullTitle = trackArtist.isEmpty ? trackName : "\(trackArtist) - \(trackName)"

        let activeRenderer = getActiveRenderer()
        let bluOS = isBluOS ?? activeRenderer?.isBluOS ?? false

        let imageURL: String
        if !bluOS, let art = status.track?.artworkUrl, art.hasPrefix("http://") || art.hasPrefix("https://") {
            imageURL = art
        } else {
            imageURL = "http://\(lanIP):\(port)/api/artwork.jpg?t=\(timestamp)&stream_token=\(token)"
        }

        let escapedTitle = Self.escapeXMLText(trackName)
        let escapedArtist = Self.escapeXMLText(trackArtist)
        let escapedArt = Self.escapeXMLText(imageURL)

        let metadata = """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"><item id="0" parentID="-1" restricted="1"><dc:title>\(escapedTitle)</dc:title><dc:creator>\(escapedArtist)</dc:creator><upnp:albumArtURI>\(escapedArt)</upnp:albumArtURI><upnp:class>object.item.audioItem.musicTrack</upnp:class></item></DIDL-Lite>
        """

        return (streamURL, imageURL, fullTitle, metadata)
    }

    public func handleTrackChanged(status: PlayerStatus) {
        guard hasActiveRenderer else { return }
        guard status.isPlaying else { return }
        guard let renderer = getActiveRenderer() else { return }
        guard let track = status.track else { return }

        let curId = track.id
        let curTitle = track.name
        let curArtist = track.artist
        let expectedFullTitle = curArtist.isEmpty ? curTitle : "\(curArtist) - \(curTitle)"

        let cachedFmt = BitPerfectLogMonitor.shared.getCachedFormat(artist: curArtist, title: curTitle)
        let isLossy = status.audioQuality.contains("AAC") || status.audioQuality.contains("MP3") || (!BitPerfectLogMonitor.shared.currentIsLossless && cachedFmt == nil)
        let detectedRate = BitPerfectLogMonitor.shared.currentDetectedSampleRate.map { Int($0) }
        let detectedDepth = BitPerfectLogMonitor.shared.currentDetectedBitDepth
        let targetRate = isLossy ? 44100 : (cachedFmt.map { Int($0.sampleRate) } ?? detectedRate ?? status.track?.sampleRate ?? AudioProcessTapService.shared.sampleRate)
        let targetDepth = isLossy ? 16 : (cachedFmt?.bitDepth ?? detectedDepth ?? status.track?.bitDepth ?? (targetRate >= 48000 ? 24 : 16))

        lock.lock()
        let isSameTrack = (curId == lastTrackId && curTitle == lastTrackTitle && curArtist == lastTrackArtist)
        let alreadySentSameStream = (lastSentStreamTitle == expectedFullTitle && lastSentStreamRate == targetRate && lastSentStreamDepth == targetDepth && Date().timeIntervalSince(lastSentStreamDate) < 3.5)
        if !isSameTrack {
            lastTrackId = curId
            lastTrackTitle = curTitle
            lastTrackArtist = curArtist
        }
        lock.unlock()

        guard !isSameTrack && !alreadySentSameStream else { return }

        NSLog("[DLNADiscovery] 🎵 Track changed while streaming to \(renderer.friendlyName): '\(curArtist) - \(curTitle)' (\(targetRate) Hz / \(targetDepth)-bit)")

        let (streamURL, imageURL, fullTitle, metadata) = resolveStreamAndImageURLs(sampleRate: targetRate, bitDepth: targetDepth)
        setAVTransportURI(uri: streamURL, metadata: metadata, imageURL: imageURL, title: fullTitle) { success, _ in
            if success, status.isPlaying, !renderer.isBluOS {
                self.play()
            }
        }
    }

    public func handleTrackFormatChanged(sampleRate: Int, bitDepth: Int = 16) {
        guard hasActiveRenderer else { return }
        guard let renderer = getActiveRenderer() else { return }
        let currentRate = AudioProcessTapService.shared.sampleRate
        let currentDepth = AudioProcessTapService.shared.bitDepth
        let (sentRate, sentDepth) = lock.withLock { (lastSentStreamRate, lastSentStreamDepth) }

        guard sampleRate > 0, (bitDepth == 16 || bitDepth == 24),
              (sampleRate != currentRate || bitDepth != currentDepth || sampleRate != sentRate || bitDepth != sentDepth) else { return }

        closeLiveStreamConnectionsForFormatSwitch()
        AudioProcessTapService.shared.setFormat(sampleRate: sampleRate, bitDepth: bitDepth)
        PlaybackStateStore.shared.invalidateStatusCache()

        let status = MusicBridge.shared.getPlayerStatus()
        guard status.isPlaying else {
            WebSocketServer.shared.broadcastStatus(includeQueue: false)
            return
        }

        markLocalAction()
        NSLog("[DLNADiscovery] 🎛️ Track format changed to \(sampleRate) Hz / \(bitDepth)-bit while streaming to \(renderer.friendlyName). Recreating stream...")

        let (streamURL, imageURL, fullTitle, metadata) = resolveStreamAndImageURLs(sampleRate: sampleRate, bitDepth: bitDepth)

        if let curTrack = status.track {
            lock.lock()
            lastTrackId = curTrack.id
            lastTrackTitle = curTrack.name
            lastTrackArtist = curTrack.artist
            lock.unlock()
        }

        setAVTransportURI(uri: streamURL, metadata: metadata, imageURL: imageURL, title: fullTitle) { success, _ in
            if success, !renderer.isBluOS {
                let latestStatus = MusicBridge.shared.getPlayerStatus()
                if latestStatus.isPlaying {
                    self.play()
                }
            }
            WebSocketServer.shared.broadcastStatus(includeQueue: false)
        }
    }

    /// Re-pushes the live WAV stream to the active DLNA/BluOS renderer after a user `Seek` or same-track `0:00` rewind
    /// so the streamer flushes its ~5s PCM buffer and plays from the new position immediately.
    public func refreshStreamAfterSeekIfNeeded() {
        guard hasActiveRenderer else { return }
        lock.lock()
        seekRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.hasActiveRenderer else { return }
            let status = MusicBridge.shared.getPlayerStatus()
            guard status.isPlaying else { return }
            self.markLocalAction()
            self.play()
        }
        seekRefreshWorkItem = work
        lock.unlock()
        queue.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    public func noteDLNALiveStreamClientDisconnected(sid: String?) {
        guard let sid = sid?.trimmingCharacters(in: .whitespacesAndNewlines), !sid.isEmpty else { return }
        lock.withLock {
            if sid == activeStreamInstanceID {
                activeStreamLastClientDisconnectedAt = Date()
            }
        }
    }

    public func noteDLNALiveStreamConnected(sid: String?) {
        guard let sid = sid?.trimmingCharacters(in: .whitespacesAndNewlines), !sid.isEmpty else { return }
        let now = Date()
        let shouldTriggerPrev: Bool = lock.withLock {
            guard sid == activeStreamInstanceID else { return false }
            if activeStreamFirstConnectedAt == nil {
                activeStreamFirstConnectedAt = now
                activeStreamLastClientDisconnectedAt = nil
                return false
            }
            guard let firstConn = activeStreamFirstConnectedAt,
                  let lastDisc = activeStreamLastClientDisconnectedAt else {
                return false
            }
            activeStreamLastClientDisconnectedAt = nil
            let streamAge = now.timeIntervalSince(firstConn)
            let reconnectGap = now.timeIntervalSince(lastDisc)
            let sinceLocal = now.timeIntervalSince(lastLocalActionDate)
            let sinceLastPrev = now.timeIntervalSince(lastBluOSPrevTriggerDate)
            guard !isExplicitlyPaused,
                  streamAge >= 1.5,
                  reconnectGap >= 0.002 && reconnectGap <= 0.45,
                  sinceLocal > 2.0,
                  sinceLastPrev > 1.2 else {
                return false
            }
            lastBluOSPrevTriggerDate = now
            return true
        }

        guard shouldTriggerPrev else { return }
        guard let renderer = getActiveRenderer(), renderer.isBluOS else { return }
        let (isUserPaused, cachedStatus) = PlaybackStateStore.shared.withLock {
            (PlaybackStateStore.shared.isUserPaused, PlaybackStateStore.shared.lastPlayerStatusCache?.status)
        }
        guard !isUserPaused else { return }
        if let s = cachedStatus, !s.isPlaying {
            return
        }

        NSLog("[DLNADiscovery] ⏮️ Detected BluOS stream restart (/Back Prev button) on %@ — triggering previousTrack!", renderer.friendlyName)
        markLocalAction()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let prevId = cachedStatus?.track?.id ?? ""
            let prevName = cachedStatus?.track?.name ?? ""
            _ = MusicBridge.shared.previousTrack(forceTrackChange: true)
            for delay in [0.2, 0.85, 1.6] {
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
                    MusicBridge.shared.invalidateStatusCache()
                    let updated = MusicBridge.shared.getPlayerStatus()
                    UPnPMediaRendererServer.shared.notifySubscribers(status: updated, force: true)
                    WebSocketServer.shared.broadcastStatus(status: updated, includeQueue: true)
                    if delay == 0.2 && (updated.track?.id ?? "") == prevId && (updated.track?.name ?? "") == prevName && updated.isPlaying {
                        self?.refreshStreamAfterSeekIfNeeded()
                    }
                }
            }
        }
    }
}
