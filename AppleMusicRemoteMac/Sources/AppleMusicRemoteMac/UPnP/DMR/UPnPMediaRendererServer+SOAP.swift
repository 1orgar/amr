//
//  UPnPMediaRendererServer+SOAP.swift
//  AppleMusicRemoteMac
//
//  UPnP AVTransport, RenderingControl, and ConnectionManager SOAP action handlers,
//  precompiled/linear XML tag extraction, and DIDL-Lite metadata generation.
//

import Foundation
import Network

extension UPnPMediaRendererServer {
    private static let soapActionRegex = try! NSRegularExpression(pattern: #"<u:([A-Za-z0-9_]+)"#, options: [])

    // MARK: - AVTransport SOAP Actions

    internal func handleAVTransportControl(bodyData: Data, headers: [String: String], connection: NWConnection) {
        if headers["ORIGIN"] != nil {
            send400(connection)
            return
        }
        let ct = (headers["CONTENT-TYPE"] ?? "").lowercased()
        if headers["SOAPACTION"] == nil && !ct.contains("xml") {
            send400(connection)
            return
        }
        guard let bodyString = String(data: bodyData, encoding: .utf8) else {
            send400(connection)
            return
        }

        let action = extractSOAPAction(from: headers, body: bodyString)
        if action != "GetPositionInfo" && action != "GetTransportInfo" {
            NSLog("[UPnPMediaRendererServer] 📩 AVTransport SOAP action: %@", action)
        }
        var cachedStatus: PlayerStatus?
        let getStatus: () -> PlayerStatus = { [weak self] in
            if let s = cachedStatus { return s }
            let s = self?.getFastDMRStatus() ?? MusicBridge.shared.getPlayerStatus()
            cachedStatus = s
            return s
        }
        let lanIP = getLANIP()

        switch action {
        case "GetPositionInfo":
            let status = getStatus()
            let durSec = resolveEffectiveTrackDuration(for: status)
            let curSec: Double = stateLock.withLock {
                if Date().timeIntervalSince(optimisticPositionDate) < 5.0, let optPos = optimisticPosition {
                    let elapsed = optimisticPositionIsPlaying ? Date().timeIntervalSince(optimisticPositionDate) : 0.0
                    return min(optPos + elapsed, durSec > 0 ? durSec : (optPos + elapsed))
                }
                return status.position
            }
            let curTimeStr = formatSecondsToTime(curSec)
            let durTimeStr = formatSecondsToTime(durSec)

            let title = status.track?.name ?? AMRLocalization.tr("Untitled", "Без названия")
            let artist = status.track?.artist ?? "Apple Music"
            let album = status.track?.album ?? ""
            let artUri = resolveArtworkURI(for: status.track, lanIP: lanIP)
            let escapedArtUri = escapeXMLText(artUri)

            let didlRaw = generateDIDLLiteXML(title: title, artist: artist, album: album, artUri: artUri, durTimeStr: durTimeStr)
            let didl = escapeForSOAP(didlRaw)

            let response = """
            <u:GetPositionInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <Track>1</Track>
              <TrackDuration>\(durTimeStr)</TrackDuration>
              <TrackMetaData>\(didl)</TrackMetaData>
              <TrackURI>\(escapedArtUri)</TrackURI>
              <RelTime>\(curTimeStr)</RelTime>
              <AbsTime>\(curTimeStr)</AbsTime>
              <RelCount>2147483647</RelCount>
              <AbsCount>2147483647</AbsCount>
            </u:GetPositionInfoResponse>
            """
            sendSOAPResponse(connection, response: response)

        case "GetTransportInfo":
            let stateStr: String
            let optimistic: String? = stateLock.withLock {
                if Date().timeIntervalSince(optimisticStateDate) < 5.0, let optState = optimisticState {
                    return optState
                }
                return nil
            }
            if let opt = optimistic {
                stateStr = opt
            } else {
                let status = getStatus()
                switch status.playerState.lowercased() {
                case "playing": stateStr = "PLAYING"
                case "paused": stateStr = "PAUSED_PLAYBACK"
                default: stateStr = "STOPPED"
                }
            }

            let response = """
            <u:GetTransportInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <CurrentTransportState>\(stateStr)</CurrentTransportState>
              <CurrentTransportStatus>OK</CurrentTransportStatus>
              <CurrentSpeed>1</CurrentSpeed>
            </u:GetTransportInfoResponse>
            """
            sendSOAPResponse(connection, response: response)

        case "GetMediaInfo":
            let status = getStatus()
            let durSec = resolveEffectiveTrackDuration(for: status)
            let durTimeStr = formatSecondsToTime(durSec)
            let title = status.track?.name ?? AMRLocalization.tr("Untitled", "Без названия")
            let artist = status.track?.artist ?? "Apple Music"
            let album = status.track?.album ?? ""
            let artUri = resolveArtworkURI(for: status.track, lanIP: lanIP)
            let escapedArtUri = escapeXMLText(artUri)

            let didlRaw = generateDIDLLiteXML(title: title, artist: artist, album: album, artUri: artUri, durTimeStr: durTimeStr)
            let didl = escapeForSOAP(didlRaw)

            let response = """
            <u:GetMediaInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <NrTracks>1</NrTracks>
              <MediaDuration>\(durTimeStr)</MediaDuration>
              <CurrentURI>\(escapedArtUri)</CurrentURI>
              <CurrentURIMetaData>\(didl)</CurrentURIMetaData>
              <NextURI></NextURI>
              <NextURIMetaData></NextURIMetaData>
              <PlayMedium>NETWORK</PlayMedium>
              <RecordMedium>NOT_IMPLEMENTED</RecordMedium>
              <WriteStatus>NOT_IMPLEMENTED</WriteStatus>
            </u:GetMediaInfoResponse>
            """
            sendSOAPResponse(connection, response: response)

        case "GetDeviceCapabilities":
            let response = """
            <u:GetDeviceCapabilitiesResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <PlayMedia>NONE</PlayMedia>
              <RecMedia>NONE</RecMedia>
              <RecQualityModes>NONE</RecQualityModes>
            </u:GetDeviceCapabilitiesResponse>
            """
            sendSOAPResponse(connection, response: response)

        case "GetTransportSettings":
            let playModeStr = resolveUPnPPlayMode(for: getStatus())
            let response = """
            <u:GetTransportSettingsResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <PlayMode>\(playModeStr)</PlayMode>
              <RecQualityMode>NOT_IMPLEMENTED</RecQualityMode>
            </u:GetTransportSettingsResponse>
            """
            sendSOAPResponse(connection, response: response)

        case "SetPlayMode":
            let mode = extractTagValue(tag: "NewPlayMode", from: bodyString)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ?? "NORMAL"
            DispatchQueue.global(qos: .userInitiated).async {
                switch mode {
                case "SHUFFLE":
                    _ = PlaybackTransportController.shared.setShuffle(true)
                    _ = PlaybackTransportController.shared.setRepeat(mode: "off")
                case "REPEAT_ONE":
                    _ = PlaybackTransportController.shared.setRepeat(mode: "one")
                case "REPEAT_ALL":
                    _ = PlaybackTransportController.shared.setShuffle(false)
                    _ = PlaybackTransportController.shared.setRepeat(mode: "all")
                case "RANDOM":
                    _ = PlaybackTransportController.shared.setShuffle(true)
                    _ = PlaybackTransportController.shared.setRepeat(mode: "all")
                default:
                    _ = PlaybackTransportController.shared.setShuffle(false)
                    _ = PlaybackTransportController.shared.setRepeat(mode: "off")
                }
            }
            sendSOAPResponse(connection, response: "<u:SetPlayModeResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"/>")
            schedulePostTransportRefresh(includeQueue: true, delays: [0.15, 0.6])

        case "Play":
            stateLock.withLock {
                optimisticState = "PLAYING"
                optimisticStateDate = Date()
                optimisticPositionIsPlaying = true
            }
            _ = MusicBridge.shared.play()
            if DLNADiscoveryManager.shared.hasActiveRenderer {
                DLNADiscoveryManager.shared.play()
            }
            sendSOAPResponse(connection, response: "<u:PlayResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"/>")
            schedulePostTransportRefresh(includeQueue: false)

        case "Pause":
            stateLock.withLock {
                optimisticState = "PAUSED_PLAYBACK"
                optimisticStateDate = Date()
                optimisticPositionIsPlaying = false
            }
            _ = MusicBridge.shared.pause()
            if DLNADiscoveryManager.shared.hasActiveRenderer {
                DLNADiscoveryManager.shared.pause()
            }
            sendSOAPResponse(connection, response: "<u:PauseResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"/>")
            schedulePostTransportRefresh(includeQueue: false)

        case "Stop":
            stateLock.withLock {
                optimisticState = "STOPPED"
                optimisticStateDate = Date()
                optimisticPosition = 0
                optimisticPositionDate = Date()
                optimisticPositionIsPlaying = false
            }
            _ = MusicBridge.shared.stop()
            if DLNADiscoveryManager.shared.hasActiveRenderer {
                DLNADiscoveryManager.shared.stopPlayback()
            }
            sendSOAPResponse(connection, response: "<u:StopResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"/>")
            schedulePostTransportRefresh(includeQueue: false)

        case "Next":
            stateLock.withLock {
                optimisticState = "PLAYING"
                optimisticStateDate = Date()
                optimisticPosition = 0
                optimisticPositionDate = Date()
                optimisticPositionIsPlaying = true
            }
            _ = MusicBridge.shared.nextTrack()
            sendSOAPResponse(connection, response: "<u:NextResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"/>")
            schedulePostTransportRefresh(includeQueue: true, delays: [0.2, 0.85, 1.6, 2.8])

        case "Previous":
            let prevStatus = getStatus()
            let prevId = prevStatus.track?.id ?? ""
            let prevTitle = prevStatus.track?.name ?? ""
            stateLock.withLock {
                optimisticState = "PLAYING"
                optimisticStateDate = Date()
                optimisticPosition = 0
                optimisticPositionDate = Date()
                optimisticPositionIsPlaying = true
            }
            _ = MusicBridge.shared.previousTrack(forceTrackChange: true)
            sendSOAPResponse(connection, response: "<u:PreviousResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"/>")
            if DLNADiscoveryManager.shared.hasActiveRenderer {
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.25) {
                    let cur = MusicBridge.shared.getPlayerStatus()
                    if (cur.track?.id ?? "") == prevId && (cur.track?.name ?? "") == prevTitle && cur.isPlaying {
                        DLNADiscoveryManager.shared.refreshStreamAfterSeekIfNeeded()
                    }
                }
            }
            schedulePostTransportRefresh(includeQueue: true, delays: [0.2, 0.85, 1.6, 2.8])

        case "Seek":
            let unit = extractTagValue(tag: "Unit", from: bodyString)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ?? "REL_TIME"
            if let targetVal = extractTagValue(tag: "Target", from: bodyString)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                if unit == "TRACK_NR", let trackNr = Int(targetVal), trackNr >= 1 {
                    let isCustom = PlaybackStateStore.shared.withLock {
                        PlaybackStateStore.shared.isCustomQueuePlayback && trackNr <= PlaybackStateStore.shared.activeCustomQueue.count
                    }
                    if isCustom {
                        _ = QueueManager.shared.playQueueIndexUnlocked(trackNr - 1)
                    }
                } else {
                    let seconds = parseTimeToSeconds(targetVal)
                    stateLock.withLock {
                        optimisticPosition = seconds
                        optimisticPositionDate = Date()
                    }
                    _ = MusicBridge.shared.seek(to: seconds)
                    if DLNADiscoveryManager.shared.hasActiveRenderer {
                        DLNADiscoveryManager.shared.refreshStreamAfterSeekIfNeeded()
                    }
                }
            }
            sendSOAPResponse(connection, response: "<u:SeekResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"/>")
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1) { [weak self] in
                MusicBridge.shared.invalidateStatusCache()
                self?.notifySubscribers(force: true)
                WebSocketServer.shared.broadcastStatus()
            }

        case "SetAVTransportURI":
            sendSOAPResponse(connection, response: "<u:SetAVTransportURIResponse xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\"/>")

        case "GetCurrentTransportActions":
            let response = """
            <u:GetCurrentTransportActionsResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <Actions>Play,Pause,Stop,Seek,Next,Previous</Actions>
            </u:GetCurrentTransportActionsResponse>
            """
            sendSOAPResponse(connection, response: response)

        default:
            sendSOAPError(connection, code: 401, message: "Invalid Action")
        }
    }

    private func schedulePostTransportRefresh(includeQueue: Bool, delays: [TimeInterval] = [0.15, 0.6]) {
        for delay in delays {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) { [weak self] in
                MusicBridge.shared.invalidateStatusCache()
                let status = MusicBridge.shared.getPlayerStatus()
                self?.notifySubscribers(status: status, force: true)
                WebSocketServer.shared.broadcastStatus(status: status, includeQueue: includeQueue)
            }
        }
    }

    // MARK: - RenderingControl SOAP Actions

    internal func handleRenderingControl(bodyData: Data, headers: [String: String], connection: NWConnection) {
        if headers["ORIGIN"] != nil {
            send400(connection)
            return
        }
        let ct = (headers["CONTENT-TYPE"] ?? "").lowercased()
        if headers["SOAPACTION"] == nil && !ct.contains("xml") {
            send400(connection)
            return
        }
        guard let bodyString = String(data: bodyData, encoding: .utf8) else {
            send400(connection)
            return
        }

        let action = extractSOAPAction(from: headers, body: bodyString)
        var cachedStatus: PlayerStatus?
        let getStatus: () -> PlayerStatus = { [weak self] in
            if let s = cachedStatus { return s }
            let s = self?.getFastDMRStatus() ?? MusicBridge.shared.getPlayerStatus()
            cachedStatus = s
            return s
        }

        switch action {
        case "GetVolume":
            let status = getStatus()
            let response = """
            <u:GetVolumeResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              <CurrentVolume>\(status.volume)</CurrentVolume>
            </u:GetVolumeResponse>
            """
            sendSOAPResponse(connection, response: response)

        case "SetVolume":
            if let volStr = extractTagValue(tag: "DesiredVolume", from: bodyString), let vol = Int(volStr) {
                let clamped = min(max(vol, 0), 100)
                DispatchQueue.global(qos: .userInitiated).async {
                    _ = MusicBridge.shared.setVolume(clamped)
                }
            }
            sendSOAPResponse(connection, response: "<u:SetVolumeResponse xmlns:u=\"urn:schemas-upnp-org:service:RenderingControl:1\"/>")
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1) { [weak self] in
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.lastPlayerStatusCache = nil
                }
                self?.notifySubscribers()
                WebSocketServer.shared.broadcastStatus()
            }

        case "GetMute":
            let status = getStatus()
            let isDLNAMuted = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isDLNAMuted }
            let isMutedBool = ExternalAmpTCPController.shared.isActive
                ? ExternalAmpTCPController.shared.isMuted
                : (isDLNAMuted || status.volume == 0)
            let isMuted = isMutedBool ? "1" : "0"
            let response = """
            <u:GetMuteResponse xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              <CurrentMute>\(isMuted)</CurrentMute>
            </u:GetMuteResponse>
            """
            sendSOAPResponse(connection, response: response)

        case "SetMute":
            if let muteStr = extractTagValue(tag: "DesiredMute", from: bodyString) {
                let mute = (muteStr == "1" || muteStr.lowercased() == "true")
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.applyDMRMuteState(mute)
                }
            }
            sendSOAPResponse(connection, response: "<u:SetMuteResponse xmlns:u=\"urn:schemas-upnp-org:service:RenderingControl:1\"/>")
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1) { [weak self] in
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.lastPlayerStatusCache = nil
                }
                self?.notifySubscribers()
                WebSocketServer.shared.broadcastStatus()
            }

        default:
            sendSOAPError(connection, code: 401, message: "Invalid Action")
        }
    }

    private func applyDMRMuteState(_ mute: Bool) {
        if DLNADiscoveryManager.shared.hasActiveRenderer {
            DLNADiscoveryManager.shared.setMute(mute)
        }
        if ExternalAmpTCPController.shared.isActive {
            ExternalAmpTCPController.shared.setMuted(mute)
        } else if PlaybackStateStore.shared.isVolumeLockedTo100 {
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.isDLNAMuted = mute
                PlaybackStateStore.shared.lastPlayerStatusCache = nil
            }
            AudioProcessTapService.shared.setMutingGuardZeroFill(mute)
            if mute {
                if let app = MusicAppProvider.shared.getMusicApp() {
                    app.soundVolume = 0
                }
            } else if AudioDuckingController.shared.isDucked {
                let orig = AudioDuckingController.shared.originalVolume ?? 100
                let duckVol = max(1, Int((Double(orig) * 0.2).rounded()))
                _ = PlaybackTransportController.shared.setVolume(duckVol, isFromDuckingController: true)
            } else {
                if let app = MusicAppProvider.shared.getMusicApp() {
                    app.soundVolume = 100
                }
                PlaybackStateStore.shared.withLock {
                    PlaybackStateStore.shared.simulatedVolume = 100
                    PlaybackStateStore.shared.lastPlayerStatusCache = nil
                }
            }
        } else if mute {
            let curVol = MusicBridge.shared.getPlayerStatus().volume
            if curVol > 0 {
                stateLock.withLock { preMuteVolume = curVol }
                PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.preDLNAVolume = curVol }
            }
            PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.isDLNAMuted = true }
            _ = MusicBridge.shared.setVolume(0)
        } else {
            let savedPreDLNA = PlaybackStateStore.shared.withLock { () -> Int in
                PlaybackStateStore.shared.isDLNAMuted = false
                return PlaybackStateStore.shared.preDLNAVolume
            }
            AudioProcessTapService.shared.setMutingGuardZeroFill(false)
            let restoreVol = stateLock.withLock { preMuteVolume }
            let targetVol = restoreVol > 0 ? restoreVol : savedPreDLNA
            _ = MusicBridge.shared.setVolume(targetVol > 0 ? targetVol : 50)
        }
    }

    // MARK: - ConnectionManager SOAP Actions

    internal func handleConnectionManagerControl(bodyData: Data, headers: [String: String], connection: NWConnection) {
        if headers["ORIGIN"] != nil {
            send400(connection)
            return
        }
        let ct = (headers["CONTENT-TYPE"] ?? "").lowercased()
        if headers["SOAPACTION"] == nil && !ct.contains("xml") {
            send400(connection)
            return
        }
        guard let bodyString = String(data: bodyData, encoding: .utf8) else {
            send400(connection)
            return
        }

        let action = extractSOAPAction(from: headers, body: bodyString)
        switch action {
        case "GetProtocolInfo":
            let response = """
            <u:GetProtocolInfoResponse xmlns:u="urn:schemas-upnp-org:service:ConnectionManager:1">
              <Source>http-get:*:audio/mpeg:*,http-get:*:audio/mp4:*,http-get:*:audio/aac:*,http-get:*:audio/x-m4a:*,http-get:*:audio/flac:*,http-get:*:audio/wav:*</Source>
              <Sink></Sink>
            </u:GetProtocolInfoResponse>
            """
            sendSOAPResponse(connection, response: response)

        case "GetCurrentConnectionIDs":
            let response = """
            <u:GetCurrentConnectionIDsResponse xmlns:u="urn:schemas-upnp-org:service:ConnectionManager:1">
              <ConnectionIDs>0</ConnectionIDs>
            </u:GetCurrentConnectionIDsResponse>
            """
            sendSOAPResponse(connection, response: response)

        case "GetCurrentConnectionInfo":
            let response = """
            <u:GetCurrentConnectionInfoResponse xmlns:u="urn:schemas-upnp-org:service:ConnectionManager:1">
              <RcsID>0</RcsID>
              <AVTransportID>0</AVTransportID>
              <ProtocolInfo></ProtocolInfo>
              <PeerConnectionManager></PeerConnectionManager>
              <PeerConnectionID>-1</PeerConnectionID>
              <Direction>Input</Direction>
              <Status>OK</Status>
            </u:GetCurrentConnectionInfoResponse>
            """
            sendSOAPResponse(connection, response: response)

        default:
            sendSOAPError(connection, code: 401, message: "Invalid Action")
        }
    }

    // MARK: - Precompiled / Linear XML & Time Helpers

    internal func extractSOAPAction(from headers: [String: String], body: String) -> String {
        if let actionHeader = headers["SOAPACTION"] {
            let clean = actionHeader.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
            if let hashIdx = clean.firstIndex(of: "#") {
                return String(clean[clean.index(after: hashIdx)...])
            }
            return clean
        }

        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        if let match = Self.soapActionRegex.firstMatch(in: body, options: [], range: range),
           let r = Range(match.range(at: 1), in: body) {
            return String(body[r])
        }
        return ""
    }

    internal func extractTagValue(tag: String, from xml: String) -> String? {
        guard !tag.isEmpty else { return nil }
        let openExact = "<\(tag)>"
        let closeExact = "</\(tag)>"

        if let openRange = xml.range(of: openExact, options: .caseInsensitive),
           let closeRange = xml.range(of: closeExact, options: .caseInsensitive, range: openRange.upperBound..<xml.endIndex) {
            let candidate = String(xml[openRange.upperBound..<closeRange.lowerBound])
            if !candidate.isEmpty && !candidate.contains("<") {
                return candidate
            }
        }
        return nil
    }

    private func sendSOAPResponse(_ connection: NWConnection, response: String) {
        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            \(response)
          </s:Body>
        </s:Envelope>
        """
        sendXML(connection, content: envelope)
    }

    private func sendSOAPError(_ connection: NWConnection, code: Int, message: String) {
        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <s:Fault>
              <faultcode>s:Client</faultcode>
              <faultstring>UPnPError</faultstring>
              <detail>
                <UPnPError xmlns="urn:schemas-upnp-org:control-1-0">
                  <errorCode>\(code)</errorCode>
                  <errorDescription>\(escapeXMLText(message))</errorDescription>
                </UPnPError>
              </detail>
            </s:Fault>
          </s:Body>
        </s:Envelope>
        """
        guard let data = envelope.data(using: .utf8) else { return }
        let headers = """
        HTTP/1.1 500 Internal Server Error\r
        Content-Type: text/xml; charset="utf-8"\r
        Content-Length: \(data.count)\r
        Connection: close\r
        \r\n
        """
        sendRawWithBody(connection, headers: headers, body: data)
    }

    public func formatSecondsToTime(_ totalSec: Double) -> String {
        guard totalSec > 0 && !totalSec.isNaN else { return "00:00:00" }
        let sec = Int(totalSec)
        let hours = sec / 3600
        let minutes = (sec % 3600) / 60
        let seconds = sec % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    public func parseTimeToSeconds(_ timeStr: String) -> Double {
        let parts = timeStr.components(separatedBy: ":")
        if parts.count == 3,
           let h = Double(parts[0]),
           let m = Double(parts[1]),
           let s = Double(parts[2]) {
            return h * 3600 + m * 60 + s
        } else if parts.count == 2,
                  let m = Double(parts[0]),
                  let s = Double(parts[1]) {
            return m * 60 + s
        } else if let s = Double(timeStr) {
            return s
        }
        return 0.0
    }

    public func escapeXMLText(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    public func generateDIDLLiteXML(title: String, artist: String, album: String, artUri: String, durTimeStr: String) -> String {
        let t = escapeXMLText(title)
        let a = escapeXMLText(artist)
        let escapedArtUri = escapeXMLText(artUri)

        let rate = BitPerfectLogMonitor.shared.currentDetectedSampleRate ?? 44100.0
        let bitDepth = BitPerfectLogMonitor.shared.currentDetectedBitDepth ?? (rate >= 48000.0 ? 24 : 16)
        let khz = rate / 1000.0
        let khzStr = (khz.truncatingRemainder(dividingBy: 1) == 0) ? String(format: "%.0f", khz) : String(format: "%.1f", khz)
        let qualityBadge = AMRLocalization.isEnglish
            ? "\(khzStr) kHz / \(bitDepth)-bit"
            : "\(khzStr) кГц / \(bitDepth)-бит"

        let displayAlbum = album.isEmpty ? qualityBadge : "\(album) • \(qualityBadge)"
        let alb = escapeXMLText(displayAlbum)
        let qDesc = escapeXMLText(qualityBadge)
        let bytesPerSec = Int(rate * Double(bitDepth) * 2 / 8)
        let sampleFreqInt = Int(rate)

        return "<DIDL-Lite xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\"><item id=\"1\" parentID=\"0\" restricted=\"1\"><dc:title>\(t)</dc:title><dc:creator>\(a)</dc:creator><dc:description>\(qDesc)</dc:description><upnp:artist>\(a)</upnp:artist><upnp:album>\(alb)</upnp:album><upnp:albumArtURI>\(escapedArtUri)</upnp:albumArtURI><upnp:albumArtURI dlna:profileID=\"JPEG_MED\" xmlns:dlna=\"urn:schemas-dlna-org:metadata-1-0/\">\(escapedArtUri)</upnp:albumArtURI><upnp:icon>\(escapedArtUri)</upnp:icon><res duration=\"\(durTimeStr)\" sampleFrequency=\"\(sampleFreqInt)\" bitsPerSample=\"\(bitDepth)\" nrAudioChannels=\"2\" bitrate=\"\(bytesPerSec)\" protocolInfo=\"http-get:*:audio/flac:*\">\(escapedArtUri)</res><upnp:class>object.item.audioItem.musicTrack</upnp:class></item></DIDL-Lite>"
    }

    internal func escapeForSOAP(_ xmlStr: String) -> String {
        return escapeXMLText(xmlStr)
    }

    internal func escapeForLastChangeVal(_ xmlStr: String) -> String {
        return xmlStr
            .replacingOccurrences(of: "&", with: "&amp;amp;")
            .replacingOccurrences(of: "<", with: "&amp;lt;")
            .replacingOccurrences(of: ">", with: "&amp;gt;")
            .replacingOccurrences(of: "\"", with: "&amp;quot;")
            .replacingOccurrences(of: "'", with: "&amp;apos;")
    }
}
