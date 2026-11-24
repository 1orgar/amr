//
//  DLNADiscoveryManager+Transport.swift
//  AppleMusicRemoteMac
//
//  AVTransport SOAP, RenderingControl SOAP, and BluOS HTTP transport/volume/mute
//  commands executed via BoundedNoRedirectHTTPClient with LAN SSRF verification.
//

import Foundation

extension DLNADiscoveryManager {
    public func sendAVTransportAction(action: String, bodyContent: String, completion: ((Bool, String) -> Void)? = nil) {
        guard let renderer = getActiveRenderer(),
              let controlURL = renderer.avTransportControlURL,
              Self.isAllowedLANRendererURL(controlURL) else {
            completion?(false, "No active DLNA renderer or valid controlURL")
            return
        }

        var request = URLRequest(url: controlURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 4.0
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"urn:schemas-upnp-org:service:AVTransport:1#\(action)\"", forHTTPHeaderField: "SOAPACTION")

        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:\(action) xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              \(bodyContent)
            </u:\(action)>
          </s:Body>
        </s:Envelope>
        """
        request.httpBody = Data(envelope.utf8)

        BoundedNoRedirectHTTPClient.shared.fetch(request: request, maxBytes: 256 * 1024) { data, response, error in
            if let error = error {
                NSLog("[DLNADiscovery] ❌ SOAP %@ failed on %@: %@", action, renderer.friendlyName, error.localizedDescription)
                completion?(false, error.localizedDescription)
                return
            }
            let respStr = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let statusCode = response?.statusCode ?? 200
            let hasSoapFault = respStr.contains(":Fault>") || respStr.contains("<Fault>")
            guard (200..<300).contains(statusCode) && !hasSoapFault else {
                NSLog("[DLNADiscovery] ❌ SOAP %@ rejected on %@ (HTTP %d): %@", action, renderer.friendlyName, statusCode, respStr)
                completion?(false, respStr.isEmpty ? "HTTP \(statusCode)" : respStr)
                return
            }
            NSLog("[DLNADiscovery] ✅ SOAP %@ succeeded on %@", action, renderer.friendlyName)
            completion?(true, respStr)
        }
    }

    public func play(completion: ((Bool, String) -> Void)? = nil) {
        markLocalAction()
        lock.withLock { isExplicitlyPaused = false }
        guard let renderer = getActiveRenderer() else {
            completion?(false, "No active renderer")
            return
        }
        if !PlaybackRouter.shared.isTestingEnvironment {
            AudioProcessTapService.shared.startCapture()
        }
        if renderer.isBluOS {
            let (streamURL, imageURL, fullTitle, metadata) = resolveStreamAndImageURLs()
            setAVTransportURI(uri: streamURL, metadata: metadata, imageURL: imageURL, title: fullTitle, completion: completion)
        } else {
            let hasSentStream = lock.withLock { lastSentStreamDate != Date.distantPast }
            let hasLiveSubscriber = PlaybackRouter.shared.isTestingEnvironment || WebSocketServer.shared.hasActiveLiveStreamConnections
            if !hasSentStream || !hasLiveSubscriber {
                let (streamURL, imageURL, fullTitle, metadata) = resolveStreamAndImageURLs()
                setAVTransportURI(uri: streamURL, metadata: metadata, imageURL: imageURL, title: fullTitle) { [weak self] success, msg in
                    if success {
                        self?.sendAVTransportAction(action: "Play", bodyContent: "<Speed>1</Speed>", completion: completion)
                    } else {
                        completion?(false, msg)
                    }
                }
            } else {
                sendAVTransportAction(action: "Play", bodyContent: "<Speed>1</Speed>", completion: completion)
            }
        }
    }

    public func pause(completion: ((Bool, String) -> Void)? = nil) {
        markLocalAction()
        lock.withLock { isExplicitlyPaused = true }
        guard let renderer = getActiveRenderer() else {
            completion?(false, "No active renderer")
            return
        }
        if PlaybackRouter.shared.isTestingEnvironment {
            completion?(true, "test")
            return
        }
        if renderer.isBluOS, let base = renderer.bluOSBaseURL {
            sendBluOSCommand(endpoint: "Pause", base: base, completion: completion)
        } else {
            sendAVTransportAction(action: "Pause", bodyContent: "", completion: completion)
        }
    }

    public func stop(completion: ((Bool, String) -> Void)? = nil) {
        markLocalAction()
        lock.withLock { isExplicitlyPaused = true }
        guard let renderer = getActiveRenderer() else {
            completion?(false, "No active renderer")
            return
        }
        if PlaybackRouter.shared.isTestingEnvironment {
            completion?(true, "test")
            return
        }
        if renderer.isBluOS, let base = renderer.bluOSBaseURL {
            sendBluOSCommand(endpoint: "Pause", base: base, completion: completion)
        } else {
            sendAVTransportAction(action: "Stop", bodyContent: "", completion: completion)
        }
    }

    public func stopPlayback(completion: ((Bool, String) -> Void)? = nil) {
        stop(completion: completion)
    }

    public func pausePlayback(completion: ((Bool, String) -> Void)? = nil) {
        pause(completion: completion)
    }

    public func startPlayback(completion: ((Bool, String) -> Void)? = nil) {
        play(completion: completion)
    }

    public func setVolume(_ level: Int, completion: ((Bool, String) -> Void)? = nil) {
        let clamped = max(0, min(100, level))
        let isTestEnv = PlaybackRouter.shared.isTestingEnvironment
        var scheduledWork: DispatchWorkItem?
        lock.lock()
        lastLocalVolumeCommandDate = Date()
        if let uid = AppStorageProvider.shared.string(forKey: Self.activeRendererDefaultsKey) {
            let cleanId = uid.hasPrefix("dlna:") ? String(uid.dropFirst(5)) : uid
            rendererVolumesByUID[cleanId] = clamped
            if clamped > 0 {
                rendererMutedState = false
            }
            if !isTestEnv {
                AppStorageProvider.shared.set(rendererVolumesByUID, forKey: Self.rendererVolumesDefaultsKey)
            }
        }
        let supersededCompletion = pendingVolumeCompletion
        pendingVolumeCompletion = nil
        pendingVolumeWorkItem?.cancel()
        if isTestEnv {
            pendingVolumeWorkItem = nil
        } else {
            pendingVolumeCompletion = completion
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                let cb: ((Bool, String) -> Void)? = self.lock.withLock {
                    let stored = self.pendingVolumeCompletion
                    self.pendingVolumeCompletion = nil
                    self.pendingVolumeWorkItem = nil
                    return stored
                }
                self.dispatchImmediateRendererVolume(clamped, completion: cb)
            }
            pendingVolumeWorkItem = work
            scheduledWork = work
        }
        lock.unlock()

        supersededCompletion?(true, "superseded")

        PlaybackStateStore.shared.invalidateStatusCache()
        if let work = scheduledWork {
            queue.asyncAfter(deadline: .now() + 0.045, execute: work)
        } else {
            completion?(true, "test")
        }
    }

    private func dispatchImmediateRendererVolume(_ clamped: Int, completion: ((Bool, String) -> Void)?) {
        guard let renderer = getActiveRenderer() else {
            completion?(false, "No active renderer")
            return
        }
        if PlaybackRouter.shared.isTestingEnvironment {
            completion?(true, "test")
            return
        }
        if renderer.isBluOS, let base = renderer.bluOSBaseURL {
            let endpoint = (clamped > 0) ? "Volume?level=\(clamped)&mute=0" : "Volume?level=0"
            guard let url = URL(string: "\(base.absoluteString)/\(endpoint)"),
                  Self.isAllowedLANRendererURL(url) else {
                completion?(false, "Invalid BluOS URL")
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 2.0
            BoundedNoRedirectHTTPClient.shared.fetch(request: request, maxBytes: 128 * 1024) { [weak self] data, response, error in
                guard let self = self else {
                    completion?(false, "Released")
                    return
                }
                if let error = error {
                    self.fetchBluOSRendererVolumeOnce(renderer: renderer)
                    completion?(false, error.localizedDescription)
                    return
                }
                let respStr = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let code = response?.statusCode ?? 0
                let ok = (200...299).contains(code)
                if ok {
                    self.lock.withLock { self.lastLocalVolumeCommandDate = Date() }
                } else {
                    self.fetchBluOSRendererVolumeOnce(renderer: renderer)
                }
                completion?(ok, respStr)
            }
        } else if let controlURL = renderer.renderingControlURL, Self.isAllowedLANRendererURL(controlURL) {
            var request = URLRequest(url: controlURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 2.5
            request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
            request.setValue("\"urn:schemas-upnp-org:service:RenderingControl:1#SetVolume\"", forHTTPHeaderField: "SOAPACTION")
            let envelope = """
            <?xml version="1.0" encoding="utf-8"?>
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
              <s:Body>
                <u:SetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
                  <InstanceID>0</InstanceID>
                  <Channel>Master</Channel>
                  <DesiredVolume>\(clamped)</DesiredVolume>
                </u:SetVolume>
              </s:Body>
            </s:Envelope>
            """
            request.httpBody = Data(envelope.utf8)
            BoundedNoRedirectHTTPClient.shared.fetch(request: request, maxBytes: 128 * 1024) { [weak self] data, response, error in
                guard let self = self else {
                    completion?(false, "Released")
                    return
                }
                if let error = error {
                    self.fetchUPnPRendererVolume(renderer: renderer, ignoreSuppressionWindow: true)
                    completion?(false, error.localizedDescription)
                    return
                }
                let respStr = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let statusCode = response?.statusCode ?? 200
                let hasSoapFault = respStr.contains(":Fault>") || respStr.contains("<Fault>")
                let ok = (200..<300).contains(statusCode) && !hasSoapFault
                if ok {
                    self.lock.withLock { self.lastLocalVolumeCommandDate = Date() }
                } else {
                    self.fetchUPnPRendererVolume(renderer: renderer, ignoreSuppressionWindow: true)
                }
                completion?(ok, respStr)
            }
        } else {
            completion?(false, "No RenderingControl URL")
        }
    }

    internal func fetchBluOSRendererVolumeOnce(renderer: DiscoveredDLNARenderer) {
        guard !PlaybackRouter.shared.isTestingEnvironment,
              renderer.isBluOS,
              let base = renderer.bluOSBaseURL,
              let url = URL(string: "\(base.absoluteString)/Volume"),
              Self.isAllowedLANRendererURL(url) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 2.0
        let rendererID = renderer.id
        BoundedNoRedirectHTTPClient.shared.fetch(request: req, maxBytes: 128 * 1024) { [weak self] data, response, _ in
            guard let self = self,
                  let d = data,
                  let statusCode = response?.statusCode,
                  (200...299).contains(statusCode),
                  let xml = String(data: d, encoding: .utf8) else {
                return
            }
            self.handleBluOSVolumeFromXML(xml: xml, rendererID: rendererID, ignoreSuppressionWindow: true)
        }
    }

    internal func fetchUPnPRendererVolume(renderer: DiscoveredDLNARenderer, ignoreSuppressionWindow: Bool = false) {
        guard !PlaybackRouter.shared.isTestingEnvironment,
              let controlURL = renderer.renderingControlURL,
              Self.isAllowedLANRendererURL(controlURL) else { return }
        var request = URLRequest(url: controlURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 2.5
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"urn:schemas-upnp-org:service:RenderingControl:1#GetVolume\"", forHTTPHeaderField: "SOAPACTION")
        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:GetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              <InstanceID>0</InstanceID>
              <Channel>Master</Channel>
            </u:GetVolume>
          </s:Body>
        </s:Envelope>
        """
        request.httpBody = Data(envelope.utf8)
        let rendererID = renderer.id
        BoundedNoRedirectHTTPClient.shared.fetch(request: request, maxBytes: 128 * 1024) { [weak self] data, response, _ in
            guard let self = self,
                  let d = data,
                  let statusCode = response?.statusCode,
                  (200..<300).contains(statusCode),
                  let xml = String(data: d, encoding: .utf8),
                  let volStr = self.extractXMLTagValue(tag: "CurrentVolume", from: xml),
                  let parsedVol = Int(volStr.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return
            }
            let clamped = max(0, min(100, parsedVol))
            var changed = false
            self.lock.lock()
            if ignoreSuppressionWindow || Date().timeIntervalSince(self.lastLocalVolumeCommandDate) > 3.0 {
                if self.rendererVolumesByUID[rendererID] != clamped {
                    self.rendererVolumesByUID[rendererID] = clamped
                    AppStorageProvider.shared.set(self.rendererVolumesByUID, forKey: Self.rendererVolumesDefaultsKey)
                    changed = true
                }
            }
            self.lock.unlock()
            if changed {
                PlaybackStateStore.shared.invalidateStatusCache()
                WebSocketServer.shared.broadcastStatus(includeQueue: false)
            }
        }
    }

    public func setMute(_ mute: Bool, completion: ((Bool, String) -> Void)? = nil) {
        markLocalAction()
        lock.lock()
        lastLocalVolumeCommandDate = Date()
        rendererMutedState = mute
        lock.unlock()
        PlaybackStateStore.shared.invalidateStatusCache()
        guard let renderer = getActiveRenderer() else {
            completion?(false, "No active renderer")
            return
        }
        if PlaybackRouter.shared.isTestingEnvironment {
            completion?(true, "test")
            return
        }
        if renderer.isBluOS, let base = renderer.bluOSBaseURL {
            sendBluOSCommand(endpoint: "Volume?mute=\(mute ? 1 : 0)", base: base, completion: completion)
        } else if let controlURL = renderer.renderingControlURL, Self.isAllowedLANRendererURL(controlURL) {
            var request = URLRequest(url: controlURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 4.0
            request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
            request.setValue("\"urn:schemas-upnp-org:service:RenderingControl:1#SetMute\"", forHTTPHeaderField: "SOAPACTION")
            let desiredMute = mute ? "1" : "0"
            let envelope = """
            <?xml version="1.0" encoding="utf-8"?>
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
              <s:Body>
                <u:SetMute xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
                  <InstanceID>0</InstanceID>
                  <Channel>Master</Channel>
                  <DesiredMute>\(desiredMute)</DesiredMute>
                </u:SetMute>
              </s:Body>
            </s:Envelope>
            """
            request.httpBody = Data(envelope.utf8)
            BoundedNoRedirectHTTPClient.shared.fetch(request: request, maxBytes: 128 * 1024) { data, response, error in
                if let error = error {
                    completion?(false, error.localizedDescription)
                    return
                }
                let respStr = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let statusCode = response?.statusCode ?? 200
                let hasSoapFault = respStr.contains(":Fault>") || respStr.contains("<Fault>")
                guard (200..<300).contains(statusCode) && !hasSoapFault else {
                    completion?(false, respStr.isEmpty ? "HTTP \(statusCode)" : respStr)
                    return
                }
                completion?(true, respStr)
            }
        } else {
            completion?(false, "No RenderingControl URL")
        }
    }

    public func setAVTransportURI(
        uri: String,
        metadata: String = "",
        imageURL: String? = nil,
        title: String? = nil,
        completion: ((Bool, String) -> Void)? = nil
    ) {
        markLocalAction()
        guard let renderer = getActiveRenderer() else {
            completion?(false, "No active renderer")
            return
        }
        if let uriComps = URLComponents(string: uri), let qItems = uriComps.queryItems {
            let parsedRate = qItems.first(where: { $0.name == "rate" })?.value.flatMap { Int($0) }
            let parsedBits = qItems.first(where: { $0.name == "bits" || $0.name == "depth" })?.value.flatMap { Int($0) }
            lock.lock()
            if let r = parsedRate { lastSentStreamRate = r }
            if let b = parsedBits { lastSentStreamDepth = b }
            if let t = title, !t.isEmpty { lastSentStreamTitle = t }
            isExplicitlyPaused = false
            lastSentStreamDate = Date()
            lock.unlock()
        }
        if PlaybackRouter.shared.isTestingEnvironment {
            completion?(true, "test")
            return
        }
        if renderer.isBluOS, let base = renderer.bluOSBaseURL {
            var comps = URLComponents(string: "\(base.absoluteString)/Play")
            var queryItems: [URLQueryItem] = [URLQueryItem(name: "url", value: uri)]
            if let t = title, !t.isEmpty {
                // BluOS firmware ignores title2/title3 for service=http custom URLs and only displays title1
                queryItems.append(URLQueryItem(name: "title1", value: t))
            }
            if let img = imageURL, !img.isEmpty {
                queryItems.append(URLQueryItem(name: "image", value: img))
            }
            comps?.queryItems = queryItems
            guard let url = comps?.url, Self.isAllowedLANRendererURL(url) else {
                completion?(false, "Invalid BluOS URL")
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 4.0
            BoundedNoRedirectHTTPClient.shared.fetch(request: request, maxBytes: 256 * 1024) { data, response, error in
                if let error = error {
                    NSLog("[DLNADiscovery] ❌ BluOS Play failed: %@", error.localizedDescription)
                    completion?(false, error.localizedDescription)
                    return
                }
                let respStr = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let statusCode = response?.statusCode ?? 0
                guard (200...299).contains(statusCode) else {
                    NSLog("[DLNADiscovery] ❌ BluOS Play rejected (HTTP %d): %@", statusCode, respStr)
                    completion?(false, respStr.isEmpty ? "HTTP \(statusCode)" : respStr)
                    return
                }
                NSLog("[DLNADiscovery] ✅ BluOS Play succeeded: %@", url.absoluteString)
                completion?(true, respStr)
            }
        } else {
            let escapedURI = Self.escapeXMLText(uri)
            let escapedMeta = Self.escapeXMLText(metadata)
            let body = "<CurrentURI>\(escapedURI)</CurrentURI><CurrentURIMetaData>\(escapedMeta)</CurrentURIMetaData>"
            sendAVTransportAction(action: "SetAVTransportURI", bodyContent: body, completion: completion)
        }
    }

    internal static func escapeXMLText(_ raw: String) -> String {
        return raw
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    public func sendBluOSCommand(endpoint: String, base: URL, completion: ((Bool, String) -> Void)? = nil) {
        if PlaybackRouter.shared.isTestingEnvironment {
            completion?(true, "test")
            return
        }
        guard let url = URL(string: "\(base.absoluteString)/\(endpoint)"),
              Self.isAllowedLANRendererURL(url) else {
            completion?(false, "Invalid BluOS URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4.0
        BoundedNoRedirectHTTPClient.shared.fetch(request: request, maxBytes: 256 * 1024) { data, response, error in
            if let error = error {
                NSLog("[DLNADiscovery] ❌ BluOS %@ failed: %@", endpoint, error.localizedDescription)
                completion?(false, error.localizedDescription)
                return
            }
            let respStr = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let statusCode = response?.statusCode ?? 0
            guard (200...299).contains(statusCode) else {
                NSLog("[DLNADiscovery] ❌ BluOS %@ rejected (HTTP %d): %@", endpoint, statusCode, respStr)
                completion?(false, respStr.isEmpty ? "HTTP \(statusCode)" : respStr)
                return
            }
            NSLog("[DLNADiscovery] ✅ BluOS %@ succeeded", endpoint)
            completion?(true, respStr)
        }
    }
}
