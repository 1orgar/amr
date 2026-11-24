//
//  UPnPMediaRendererServer+GENA.swift
//  AppleMusicRemoteMac
//
//  UPnP GENA event subscriptions (SUBSCRIBE / UNSUBSCRIBE / NOTIFY) hardened
//  against CallStranger SSRF: strict callback==sender IP match, port 1024..65535,
//  SID deduplication, <=32 cap, and zero-redirect NOTIFY delivery.
//

import Foundation
import Network

extension UPnPMediaRendererServer {
    private static let maxSubscriptions = 32

    internal func handleSubscription(
        method: String,
        path: String,
        headers: [String: String],
        remoteIP: String,
        connection: NWConnection
    ) {
        let cleanPath = path.components(separatedBy: "?").first ?? path

        if method == "SUBSCRIBE" {
            let sidHeader = headers["SID"]?
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\n", with: "")
                .trimmingCharacters(in: .whitespaces) ?? ""
            let callbackHeader = headers["CALLBACK"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let ntHeader = headers["NT"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if !sidHeader.isEmpty && (!callbackHeader.isEmpty || !ntHeader.isEmpty) {
                send400(connection)
                return
            }

            if !sidHeader.isEmpty {
                let renewSid = sidHeader
                subQueue.async { [weak self] in
                    guard let self = self else { return }
                    if let idx = self.subscriptions.firstIndex(where: { $0.sid == renewSid }) {
                        self.subscriptions[idx].expiryDate = Date().addingTimeInterval(1800)
                        self.subscriptions[idx].failureCount = 0
                        NSLog("[UPnPMediaRendererServer] 🔄 Renewed subscription for %@ (SID: %@)", self.subscriptions[idx].path, renewSid)
                        let response = """
                        HTTP/1.1 200 OK\r
                        SERVER: macOS/14.0 UPnP/1.0 AppleMusicRemote/2.0\r
                        SID: \(renewSid)\r
                        TIMEOUT: Second-1800\r
                        Content-Length: 0\r
                        Connection: close\r
                        \r\n
                        """
                        self.sendRaw(connection, string: response)
                    } else {
                        NSLog("[UPnPMediaRendererServer] ⚠️ Unknown subscription renewal SID: %@, returning 412", renewSid)
                        let response = """
                        HTTP/1.1 412 Precondition Failed\r
                        SERVER: macOS/14.0 UPnP/1.0 AppleMusicRemote/2.0\r
                        Content-Length: 0\r
                        Connection: close\r
                        \r\n
                        """
                        self.sendRaw(connection, string: response)
                    }
                }
                return
            }

            guard !callbackHeader.isEmpty, let rawCallback = headers["CALLBACK"] else {
                send400(connection)
                return
            }
            let clean = rawCallback.trimmingCharacters(in: CharacterSet(charactersIn: "<> \t\r\n"))
            let firstUrlStr = clean.components(separatedBy: CharacterSet(charactersIn: "<> ")).first { !$0.isEmpty } ?? clean
            guard let url = URL(string: firstUrlStr),
                  let scheme = url.scheme?.lowercased(),
                  (scheme == "http" || scheme == "https"),
                  url.user == nil,
                  url.password == nil,
                  let cbPort = url.port,
                  (1024...65535).contains(cbPort),
                  let host = url.host,
                  isAllowedCallbackHost(host, remoteIP: remoteIP) else {
                NSLog("[UPnPMediaRendererServer] ❌ Rejected GENA SUBSCRIBE callback URL: %@ (remoteIP: %@)", firstUrlStr, remoteIP)
                send400(connection)
                return
            }

            subQueue.async { [weak self] in
                guard let self = self else { return }
                let now = Date()
                self.subscriptions.removeAll { now > $0.expiryDate }

                let activeSub: EventSubscription
                if let existingIdx = self.subscriptions.firstIndex(where: { $0.path == cleanPath && $0.callbackURL == url }) {
                    // Reuse existing SID so Home Assistant's periodic re-subscribes don't churn SIDs
                    self.subscriptions[existingIdx].expiryDate = now.addingTimeInterval(1800)
                    self.subscriptions[existingIdx].failureCount = 0
                    self.subscriptions[existingIdx].seq = 0
                    activeSub = self.subscriptions[existingIdx]
                } else {
                    let newSid = "uuid:\(UUID().uuidString.lowercased())"
                    let newHost = LANSubnetGuard.normalizePeerIP(host)
                    self.subscriptions.removeAll {
                        $0.sid == newSid
                            || ($0.path == cleanPath && LANSubnetGuard.normalizePeerIP($0.callbackURL.host ?? "") == newHost)
                    }
                    if self.subscriptions.count >= Self.maxSubscriptions {
                        self.subscriptions.removeFirst(self.subscriptions.count - (Self.maxSubscriptions - 1))
                    }
                    let created = EventSubscription(
                        sid: newSid,
                        callbackURL: url,
                        path: cleanPath,
                        seq: 0,
                        expiryDate: now.addingTimeInterval(1800),
                        failureCount: 0
                    )
                    self.subscriptions.append(created)
                    activeSub = created
                }

                let response = """
                HTTP/1.1 200 OK\r
                SERVER: macOS/14.0 UPnP/1.0 AppleMusicRemote/2.0\r
                SID: \(activeSub.sid)\r
                TIMEOUT: Second-1800\r
                Content-Length: 0\r
                Connection: close\r
                \r\n
                """
                self.sendRaw(connection, string: response)
                self.syncCachedSubscriberCountLocked()

                NSLog("[UPnPMediaRendererServer] 📝 Subscribed to %@ (SID: %@, Total subs: %d)", cleanPath, activeSub.sid, self.subscriptions.count)
                if cleanPath.contains("avtransport") {
                    self.sendNotification(for: activeSub)
                } else if cleanPath.contains("renderingcontrol") {
                    self.sendRenderingControlNotification(for: activeSub)
                } else if cleanPath.contains("connectionmanager") {
                    self.sendConnectionManagerNotification(for: activeSub)
                }
            }
        } else {
            if let sid = headers["SID"]?.trimmingCharacters(in: .whitespacesAndNewlines), !sid.isEmpty {
                subQueue.async { [weak self] in
                    guard let self = self else { return }
                    self.subscriptions.removeAll { $0.sid == sid }
                    self.syncCachedSubscriberCountLocked()
                    NSLog("[UPnPMediaRendererServer] 🔌 Unsubscribed SID: %@", sid)
                }
            }
            let response = """
            HTTP/1.1 200 OK\r
            SERVER: macOS/14.0 UPnP/1.0 AppleMusicRemote/2.0\r
            Content-Length: 0\r
            Connection: close\r
            \r\n
            """
            sendRaw(connection, string: response)
        }
    }

    internal func syncCachedSubscriberCountLocked() {
        let count = subscriptions.count
        stateLock.withLock {
            cachedActiveSubscriberCount = count
        }
    }

    internal func resolveEffectiveTrackDuration(for status: PlayerStatus) -> Double {
        if let dur = status.track?.duration, dur > 0, dur.isFinite {
            return dur
        }
        let fallbackDur: Double = PlaybackStateStore.shared.withLock {
            if PlaybackStateStore.shared.isCustomQueuePlayback {
                let idx = PlaybackStateStore.shared.activeCustomQueueIndex
                if idx >= 0, idx < PlaybackStateStore.shared.activeCustomQueue.count {
                    let qTrack = PlaybackStateStore.shared.activeCustomQueue[idx]
                    if qTrack.duration > 0, qTrack.duration.isFinite {
                        let sName = (status.track?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if sName.isEmpty || qTrack.name.localizedCaseInsensitiveCompare(sName) == .orderedSame {
                            return qTrack.duration
                        }
                    }
                }
            }
            if let smartCutoff = PlaybackStateStore.shared.scheduledSmartTransitionStart,
               smartCutoff > 0, smartCutoff.isFinite {
                return smartCutoff
            }
            return 0.0
        }
        return fallbackDur
    }

    internal func resolveUPnPPlayMode(for status: PlayerStatus) -> String {
        let rep = status.repeatMode.lowercased()
        if rep == "one" {
            return "REPEAT_ONE"
        }
        if status.shuffle && rep == "all" {
            return "RANDOM"
        }
        if status.shuffle {
            return "SHUFFLE"
        }
        if rep == "all" {
            return "REPEAT_ALL"
        }
        return "NORMAL"
    }

    /// CallStranger (CVE-2020-12695) SSRF defense: strictly requires `callbackHost == remoteIP`
    /// on a valid same-subnet (or loopback-to-loopback) literal IP, blocking `169.254.0.0/16` unconditionally.
    internal func isAllowedCallbackHost(_ host: String, remoteIP: String = "") -> Bool {
        let rawHost = LANSubnetGuard.normalizePeerIP(host)
        let rawRemote = LANSubnetGuard.normalizePeerIP(remoteIP)
        guard !rawHost.isEmpty, !rawRemote.isEmpty else { return false }

        guard let cleanHost = DLNADiscoveryManager.normalizeLiteralIP(rawHost),
              let cleanRemote = DLNADiscoveryManager.normalizeLiteralIP(rawRemote) else {
            return false
        }

        // Never allow IPv4 link-local / cloud metadata (169.254.0.0/16) as GENA callback targets
        if cleanHost.hasPrefix("169.254.") || cleanRemote.hasPrefix("169.254.") {
            return false
        }

        // Callback IP MUST strictly match the TCP subscriber's source IP
        guard cleanHost == cleanRemote else {
            return false
        }

        return LANSubnetGuard.isPrivateLANOrLoopbackPeer(cleanRemote)
    }

    // MARK: - Outbound Event Notifications

    public func notifySubscribers(status: PlayerStatus? = nil, force: Bool = false, completion: (() -> Void)? = nil) {
        guard isEnabled else {
            completion?()
            return
        }

        subQueue.async { [weak self] in
            guard let self = self, self.isEnabled else {
                completion?()
                return
            }

            let now = Date()
            self.subscriptions.removeAll { now > $0.expiryDate }
            self.syncCachedSubscriberCountLocked()

            guard !self.subscriptions.isEmpty else {
                completion?()
                return
            }

            let currentStatus = status ?? self.getFastDMRStatus()
            let effectiveDur = self.resolveEffectiveTrackDuration(for: currentStatus)
            let durSecInt = Int(effectiveDur.rounded())
            let curSec: Double = self.stateLock.withLock {
                if now.timeIntervalSince(self.optimisticPositionDate) < 5.0, let optPos = self.optimisticPosition {
                    let elapsed = self.optimisticPositionIsPlaying ? now.timeIntervalSince(self.optimisticPositionDate) : 0.0
                    return min(optPos + elapsed, effectiveDur > 0 ? effectiveDur : (optPos + elapsed))
                }
                return currentStatus.position
            }
            let stateStr: String = self.stateLock.withLock {
                if Date().timeIntervalSince(self.optimisticStateDate) < 5.0, let optState = self.optimisticState {
                    return optState
                }
                switch currentStatus.playerState.lowercased() {
                case "playing": return "PLAYING"
                case "paused": return "PAUSED_PLAYBACK"
                default: return "STOPPED"
                }
            }
            let trackId = currentStatus.track?.id ?? "0"
            let artUrl = currentStatus.track?.artworkUrl ?? ""
            let trackTitle = currentStatus.track?.name ?? ""
            let playModeStr = self.resolveUPnPPlayMode(for: currentStatus)
            let curVol = currentStatus.volume
            let isDLNAMuted = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isDLNAMuted }
            let curMute = ExternalAmpTCPController.shared.isActive
                ? ExternalAmpTCPController.shared.isMuted
                : (isDLNAMuted || curVol == 0)

            let elapsedSinceLastNotify = max(0.0, now.timeIntervalSince(self.lastNotifiedTime))
            let expectedPos = (self.lastNotifiedState == "PLAYING")
                ? (self.lastNotifiedPositionSec + elapsedSinceLastNotify)
                : self.lastNotifiedPositionSec
            let positionDrifted = abs(curSec - expectedPos) > 2.5

            if !force,
               stateStr == self.lastNotifiedState,
               trackId == self.lastNotifiedTrackId,
               artUrl == self.lastNotifiedArtworkUrl,
               trackTitle == self.lastNotifiedTrackTitle,
               durSecInt == self.lastNotifiedDurationSec,
               playModeStr == self.lastNotifiedPlayMode,
               !positionDrifted,
               curVol == self.lastNotifiedVolume,
               curMute == self.lastNotifiedMute,
               elapsedSinceLastNotify < 20.0 {
                completion?()
                return
            }

            self.lastNotifiedState = stateStr
            self.lastNotifiedTrackId = trackId
            self.lastNotifiedArtworkUrl = artUrl
            self.lastNotifiedTrackTitle = trackTitle
            self.lastNotifiedDurationSec = durSecInt
            self.lastNotifiedPositionSec = curSec
            self.lastNotifiedPlayMode = playModeStr
            self.lastNotifiedVolume = curVol
            self.lastNotifiedMute = curMute
            self.lastNotifiedTime = now

            let group = DispatchGroup()
            for idx in 0..<self.subscriptions.count {
                if self.subscriptions[idx].path.contains("avtransport") {
                    self.subscriptions[idx].seq &+= 1
                    group.enter()
                    self.sendNotification(for: self.subscriptions[idx], status: currentStatus, overrideState: stateStr) {
                        group.leave()
                    }
                } else if self.subscriptions[idx].path.contains("renderingcontrol") {
                    self.subscriptions[idx].seq &+= 1
                    group.enter()
                    self.sendRenderingControlNotification(for: self.subscriptions[idx], status: currentStatus) {
                        group.leave()
                    }
                }
            }

            if let comp = completion {
                group.notify(queue: self.subQueue) {
                    comp()
                }
            }
        }
    }

    private func sendRenderingControlNotification(for subscription: EventSubscription, status: PlayerStatus? = nil, completion: (() -> Void)? = nil) {
        let currentStatus = status ?? getFastDMRStatus()
        let isDLNAMuted = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isDLNAMuted }
        let isMutedBool = ExternalAmpTCPController.shared.isActive
            ? ExternalAmpTCPController.shared.isMuted
            : (isDLNAMuted || currentStatus.volume == 0)
        let muteVal = isMutedBool ? "1" : "0"
        let lastChange = """
        <Event xmlns="urn:schemas-upnp-org:metadata-1-0/RCS/">
          <InstanceID val="0">
            <Volume channel="Master" val="\(currentStatus.volume)"/>
            <Mute channel="Master" val="\(muteVal)"/>
          </InstanceID>
        </Event>
        """
        let escapedLastChange = escapeXMLText(lastChange)
        let body = """
        <e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0">
          <e:property>
            <LastChange>\(escapedLastChange)</LastChange>
          </e:property>
        </e:propertyset>
        """
        sendRawNotify(to: subscription.callbackURL, sid: subscription.sid, seq: subscription.seq, body: body, completion: completion)
    }

    private func sendConnectionManagerNotification(for subscription: EventSubscription) {
        let body = """
        <e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0">
          <e:property>
            <SourceProtocolInfo>http-get:*:audio/mpeg:*,http-get:*:audio/mp4:*,http-get:*:audio/x-m4a:*,http-get:*:audio/flac:*</SourceProtocolInfo>
          </e:property>
          <e:property>
            <SinkProtocolInfo>http-get:*:audio/mpeg:*,http-get:*:audio/mp4:*,http-get:*:audio/x-m4a:*,http-get:*:audio/flac:*</SinkProtocolInfo>
          </e:property>
          <e:property>
            <CurrentConnectionIDs>0</CurrentConnectionIDs>
          </e:property>
        </e:propertyset>
        """
        sendRawNotify(to: subscription.callbackURL, sid: subscription.sid, seq: subscription.seq, body: body)
    }

    private func sendNotification(for subscription: EventSubscription, status: PlayerStatus? = nil, overrideState: String? = nil, completion: (() -> Void)? = nil) {
        let currentStatus = status ?? getFastDMRStatus()
        let lanIP = getLANIP()
        let durSec = resolveEffectiveTrackDuration(for: currentStatus)

        let curSec: Double = stateLock.withLock {
            if Date().timeIntervalSince(optimisticPositionDate) < 5.0, let optPos = optimisticPosition {
                let elapsed = optimisticPositionIsPlaying ? Date().timeIntervalSince(optimisticPositionDate) : 0.0
                return min(optPos + elapsed, durSec > 0 ? durSec : (optPos + elapsed))
            }
            return currentStatus.position
        }

        let curTimeStr = formatSecondsToTime(curSec)
        let durTimeStr = formatSecondsToTime(durSec)
        let playModeStr = resolveUPnPPlayMode(for: currentStatus)

        let stateStr = overrideState ?? stateLock.withLock {
            if Date().timeIntervalSince(optimisticStateDate) < 5.0, let optState = optimisticState {
                return optState
            }
            switch currentStatus.playerState.lowercased() {
            case "playing": return "PLAYING"
            case "paused": return "PAUSED_PLAYBACK"
            default: return "STOPPED"
            }
        }

        let title = currentStatus.track?.name ?? "Без названия"
        let artist = currentStatus.track?.artist ?? "Apple Music"
        let album = currentStatus.track?.album ?? ""
        let artUri = resolveArtworkURI(for: currentStatus.track, lanIP: lanIP)
        let artUriForLastChange = escapeForLastChangeVal(artUri)

        let didlRaw = generateDIDLLiteXML(title: title, artist: artist, album: album, artUri: artUri, durTimeStr: durTimeStr)
        let didlForLastChange = escapeForLastChangeVal(didlRaw)

        let lastChange = """
        &lt;Event xmlns="urn:schemas-upnp-org:metadata-1-0/AVT/"&gt;&lt;InstanceID val="0"&gt;&lt;TransportState val="\(stateStr)"/&gt;&lt;TransportStatus val="OK"/&gt;&lt;CurrentPlayMode val="\(playModeStr)"/&gt;&lt;CurrentTransportActions val="Play,Pause,Stop,Seek,Next,Previous"/&gt;&lt;NumberOfTracks val="1"/&gt;&lt;CurrentTrack val="1"/&gt;&lt;CurrentTrackDuration val="\(durTimeStr)"/&gt;&lt;CurrentMediaDuration val="\(durTimeStr)"/&gt;&lt;CurrentTrackMetaData val="\(didlForLastChange)"/&gt;&lt;AVTransportURI val="\(artUriForLastChange)"/&gt;&lt;AVTransportURIMetaData val="\(didlForLastChange)"/&gt;&lt;CurrentTrackURI val="\(artUriForLastChange)"/&gt;&lt;RelativeTimePosition val="\(curTimeStr)"/&gt;&lt;AbsoluteTimePosition val="\(curTimeStr)"/&gt;&lt;/InstanceID&gt;&lt;/Event&gt;
        """
        let body = """
        <e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0">
          <e:property>
            <LastChange>\(lastChange)</LastChange>
          </e:property>
        </e:propertyset>
        """

        sendRawNotify(to: subscription.callbackURL, sid: subscription.sid, seq: subscription.seq, body: body, completion: completion)
    }

    private func sendRawNotify(to url: URL, sid: String, seq: UInt32, body: String, completion: (() -> Void)? = nil) {
        guard let bodyData = body.data(using: .utf8) else {
            completion?()
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "NOTIFY"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "CONTENT-TYPE")
        request.setValue("upnp:event", forHTTPHeaderField: "NT")
        request.setValue("upnp:propchange", forHTTPHeaderField: "NTS")
        request.setValue(sid, forHTTPHeaderField: "SID")
        request.setValue("\(seq)", forHTTPHeaderField: "SEQ")
        request.httpBody = bodyData
        request.timeoutInterval = 2.5

        BoundedNoRedirectHTTPClient.shared.fetch(request: request, maxBytes: 64 * 1024) { [weak self] _, response, error in
            guard let self = self else {
                completion?()
                return
            }

            if let err = error {
                self.subQueue.async {
                    if let idx = self.subscriptions.firstIndex(where: { $0.sid == sid }) {
                        self.subscriptions[idx].failureCount += 1
                        let failCount = self.subscriptions[idx].failureCount
                        if failCount == 1 {
                            NSLog("[UPnPMediaRendererServer] ⚠️ NOTIFY error to %@: %@", url.absoluteString, err.localizedDescription)
                        }
                        if failCount >= 2 {
                            let removedCount = self.subscriptions.filter { $0.callbackURL == url }.count
                            self.subscriptions.removeAll { $0.callbackURL == url }
                            self.syncCachedSubscriberCountLocked()
                            NSLog("[UPnPMediaRendererServer] 🗑️ Removed %d dead subscription(s) for unreachable endpoint %@", removedCount, url.absoluteString)
                        }
                    }
                }
            } else {
                let code = response?.statusCode ?? 0
                if code == 412 || code == 404 || (300...399).contains(code) {
                    NSLog("[UPnPMediaRendererServer] ⚠️ NOTIFY rejected/redirected by client (HTTP %d). Removing subscription SID: %@", code, sid)
                    self.subQueue.async {
                        self.subscriptions.removeAll { $0.sid == sid }
                        self.syncCachedSubscriberCountLocked()
                    }
                } else {
                    self.subQueue.async {
                        if let idx = self.subscriptions.firstIndex(where: { $0.sid == sid }) {
                            self.subscriptions[idx].failureCount = 0
                        }
                    }
                }
            }
            completion?()
        }
    }
}
