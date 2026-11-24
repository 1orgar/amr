//
//  SettingsWindow+StateAndSnapshot.swift
//  AppleMusicRemoteMac
//
//  Transactional Cancel/OK preference snapshot capture & restore, plus visibility-gated
//  refreshState() and performRefreshState() across all Settings tabs.
//

import AppKit

extension SettingsWindow {
    internal struct PreferencesSnapshot {
        let aiCuratorEnabled: Bool
        let tvLibraryConfig: TVLibraryConfiguration
        let bitPerfectEnabled: Bool
        let lockVolume100: Bool
        let dacMutingGuardEnabled: Bool
        let dacMutingGuardDurationMs: Int
        let spectralAnalyzerEnabled: Bool
        let discoverDLNAEnabled: Bool
        let dspConfiguration: EngineConfiguration
        let roomCorrectionEnabled: Bool
        let roomActiveProfileID: String?
        let deClipMode: MasteringDeClipMode
        let deEsserMode: MasteringDeEsserMode
        let lateNightMode: LateNightDRCMode
        let extAmpEnabled: Bool
        let extAmpProfile: ExternalAmpProfile
        let extAmpHost: String
        let extAmpPort: UInt16
        let extAmpMaxCap: Int
        let extAmpSoundCheck: Bool
        let extAmpLowVolSmartNorm: Bool
        let extAmpCompressionComp: Bool
        let wledEnabled: Bool
        let wledIP: String
        let wledLedCount: Int
        let wledMode: String
        let cloudSyncEnabled: Bool
        let cloudSyncCustomFolderPath: String?
        let localDMREnabled: Bool
        let upnpFriendlyName: String
        let fileLoggingEnabled: Bool
    }

    internal func capturePreferencesSnapshot() -> PreferencesSnapshot {
        let amp = ExternalAmpTCPController.shared
        let wled = WLEDDDPController.shared
        return PreferencesSnapshot(
            aiCuratorEnabled: NativeMusicCuratorService.shared.isEnabled,
            tvLibraryConfig: TVLibraryConfigurationStore.shared.current,
            bitPerfectEnabled: BitPerfectLogMonitor.shared.isEnabled,
            lockVolume100: PlaybackStateStore.shared.isVolumeLockedTo100,
            dacMutingGuardEnabled: CoreAudioDeviceManager.shared.isMutingGuardEnabled,
            dacMutingGuardDurationMs: CoreAudioDeviceManager.shared.mutingGuardDurationMs,
            spectralAnalyzerEnabled: SpectralIntegrityAnalyzer.shared.isEnabled,
            discoverDLNAEnabled: DLNADiscoveryManager.shared.isEnabled,
            dspConfiguration: AudioEngineController.shared.currentConfigurationSnapshot(),
            roomCorrectionEnabled: RoomAcousticService.shared.isCorrectionEnabled,
            roomActiveProfileID: RoomAcousticService.shared.activeProfile?.id,
            deClipMode: MasteringRestorationService.shared.deClipMode,
            deEsserMode: MasteringRestorationService.shared.deEsserMode,
            lateNightMode: LateNightDRCService.shared.mode,
            extAmpEnabled: amp.isEnabled,
            extAmpProfile: amp.profile,
            extAmpHost: amp.host,
            extAmpPort: amp.port,
            extAmpMaxCap: amp.maxVolumeCap,
            extAmpSoundCheck: amp.isSoundCheckEnabled,
            extAmpLowVolSmartNorm: amp.isLowVolumeSmartNormEnabled,
            extAmpCompressionComp: amp.isCompressionCompensationEnabled,
            wledEnabled: wled.isEnabled,
            wledIP: wled.ipAddress,
            wledLedCount: wled.ledCount,
            wledMode: wled.mode,
            cloudSyncEnabled: CloudSettingsSyncService.shared.isEnabled,
            cloudSyncCustomFolderPath: CloudSettingsSyncService.shared.customFolderPath,
            localDMREnabled: UPnPMediaRendererServer.shared.isEnabled,
            upnpFriendlyName: SSDPService.shared.friendlyName,
            fileLoggingEnabled: DiagnosticLogger.shared.isEnabled
        )
    }

    internal func commitPendingTextFields() {
        if UPnPMediaRendererServer.shared.isEnabled, let field = upnpFriendlyNameField {
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = text.isEmpty ? "Apple Music Remote (Mac)" : text
            if name != SSDPService.shared.friendlyName {
                SSDPService.shared.friendlyName = name
                SSDPService.shared.sendAliveNotifications()
            }
        }
        if PlaybackStateStore.shared.isVolumeLockedTo100 && ExternalAmpTCPController.shared.isEnabled,
           extAmpIPField != nil, extAmpPortField != nil, extAmpMaxCapField != nil {
            let selectedProf = (extAmpProfilePopUp?.selectedItem?.representedObject as? String).flatMap(ExternalAmpProfile.init(rawValue:)) ?? ExternalAmpTCPController.shared.profile
            let host = extAmpIPField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let parsedPort = UInt16(extAmpPortField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? selectedProf.defaultPort
            let parsedCap = Int(extAmpMaxCapField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ExternalAmpTCPController.shared.maxVolumeCap
            ExternalAmpTCPController.shared.updateConfiguration(
                profile: selectedProf,
                host: host,
                port: parsedPort,
                maxVolumeCap: parsedCap
            )
        }
        if WLEDDDPController.shared.isEnabled, wledIPField != nil, wledLedCountField != nil {
            let ip = wledIPField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let parsedLeds = Int(wledLedCountField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
            _ = WLEDDDPController.shared.updateSettings(ip: ip, ledCount: parsedLeds)
        }
    }

    internal func restorePreferencesSnapshot(_ snap: PreferencesSnapshot) {
        var didChangeStatus = false

        if NativeMusicCuratorService.shared.isEnabled != snap.aiCuratorEnabled {
            NativeMusicCuratorService.shared.isEnabled = snap.aiCuratorEnabled
            WebSocketServer.shared.broadcastEvent(name: "ai_curator_settings", data: NativeMusicCuratorService.shared.getSettingsDictionary())
        }
        if TVLibraryConfigurationStore.shared.current != snap.tvLibraryConfig {
            TVLibraryConfigurationStore.shared.update { $0 = snap.tvLibraryConfig }
            WebSocketServer.shared.broadcastEvent(name: "tv_library_config", data: TVLibraryConfigurationStore.shared.toDictionary())
        }
        if BitPerfectLogMonitor.shared.isEnabled != snap.bitPerfectEnabled {
            BitPerfectLogMonitor.shared.isEnabled = snap.bitPerfectEnabled
        }
        if PlaybackStateStore.shared.isVolumeLockedTo100 != snap.lockVolume100 {
            PlaybackStateStore.shared.isVolumeLockedTo100 = snap.lockVolume100
            if snap.lockVolume100 {
                PlaybackTransportController.shared.checkAndEnforceVolumeLock()
            }
            didChangeStatus = true
        }
        if CoreAudioDeviceManager.shared.isMutingGuardEnabled != snap.dacMutingGuardEnabled {
            CoreAudioDeviceManager.shared.isMutingGuardEnabled = snap.dacMutingGuardEnabled
            didChangeStatus = true
        }
        if CoreAudioDeviceManager.shared.mutingGuardDurationMs != snap.dacMutingGuardDurationMs {
            CoreAudioDeviceManager.shared.mutingGuardDurationMs = snap.dacMutingGuardDurationMs
            didChangeStatus = true
        }
        if SpectralIntegrityAnalyzer.shared.isEnabled != snap.spectralAnalyzerEnabled {
            SpectralIntegrityAnalyzer.shared.isEnabled = snap.spectralAnalyzerEnabled
            didChangeStatus = true
        }
        if DLNADiscoveryManager.shared.isEnabled != snap.discoverDLNAEnabled {
            DLNADiscoveryManager.shared.setEnabled(snap.discoverDLNAEnabled)
            WebSocketServer.shared.broadcastAudioDevices()
            didChangeStatus = true
        }

        var didChangeDSP = false
        if RoomAcousticService.shared.activeProfile?.id != snap.roomActiveProfileID {
            _ = RoomAcousticService.shared.selectProfile(id: snap.roomActiveProfileID)
            didChangeDSP = true
        }
        if RoomAcousticService.shared.isCorrectionEnabled != snap.roomCorrectionEnabled {
            RoomAcousticService.shared.setCorrectionEnabled(snap.roomCorrectionEnabled)
            didChangeDSP = true
        }
        if MasteringRestorationService.shared.deClipMode != snap.deClipMode {
            MasteringRestorationService.shared.setDeClipMode(snap.deClipMode)
            didChangeDSP = true
        }
        if MasteringRestorationService.shared.deEsserMode != snap.deEsserMode {
            MasteringRestorationService.shared.setDeEsserMode(snap.deEsserMode)
            didChangeDSP = true
        }
        if LateNightDRCService.shared.mode != snap.lateNightMode {
            LateNightDRCService.shared.setMode(snap.lateNightMode)
            didChangeDSP = true
        }
        if AudioEngineController.shared.currentConfigurationSnapshot() != snap.dspConfiguration {
            let targetDSP = snap.dspConfiguration
            Task {
                await AudioEngineController.shared.updateConfiguration(targetDSP)
                WebSocketServer.shared.broadcastEvent(name: "dsp_settings", data: WebSocketServer.buildDSPSettingsDictionary())
                WebSocketServer.shared.broadcastStatus(includeQueue: false)
                await MainActor.run { MenuManager.shared.updateMenuState() }
            }
        } else if didChangeDSP {
            WebSocketServer.shared.broadcastEvent(name: "dsp_settings", data: WebSocketServer.buildDSPSettingsDictionary())
            didChangeStatus = true
        }

        let amp = ExternalAmpTCPController.shared
        if amp.isEnabled != snap.extAmpEnabled || amp.profile != snap.extAmpProfile || amp.host != snap.extAmpHost || amp.port != snap.extAmpPort || amp.maxVolumeCap != snap.extAmpMaxCap {
            amp.updateConfiguration(profile: snap.extAmpProfile, host: snap.extAmpHost, port: snap.extAmpPort, maxVolumeCap: snap.extAmpMaxCap, isEnabled: snap.extAmpEnabled)
            didChangeStatus = true
        }
        amp.isSoundCheckEnabled = snap.extAmpSoundCheck
        amp.isLowVolumeSmartNormEnabled = snap.extAmpLowVolSmartNorm
        amp.isCompressionCompensationEnabled = snap.extAmpCompressionComp

        let wled = WLEDDDPController.shared
        if wled.isEnabled != snap.wledEnabled || wled.ipAddress != snap.wledIP || wled.ledCount != snap.wledLedCount || wled.mode != snap.wledMode {
            let updated = wled.updateSettings(enabled: snap.wledEnabled, ip: snap.wledIP, mode: snap.wledMode, ledCount: snap.wledLedCount)
            WebSocketServer.shared.broadcastEvent(name: "wled_settings", data: updated)
        }

        if CloudSettingsSyncService.shared.customFolderPath != snap.cloudSyncCustomFolderPath {
            CloudSettingsSyncService.shared.customFolderPath = snap.cloudSyncCustomFolderPath
        }
        if CloudSettingsSyncService.shared.isEnabled != snap.cloudSyncEnabled {
            CloudSettingsSyncService.shared.isEnabled = snap.cloudSyncEnabled
        }
        if SSDPService.shared.friendlyName != snap.upnpFriendlyName {
            SSDPService.shared.friendlyName = snap.upnpFriendlyName
        }
        if UPnPMediaRendererServer.shared.isEnabled != snap.localDMREnabled {
            UPnPMediaRendererServer.shared.setEnabled(snap.localDMREnabled)
        }
        if DiagnosticLogger.shared.isEnabled != snap.fileLoggingEnabled {
            DiagnosticLogger.shared.isEnabled = snap.fileLoggingEnabled
        }

        if didChangeStatus {
            WebSocketServer.shared.broadcastStatus(includeQueue: false)
        }
        MenuManager.shared.updateMenuState()
    }

    // MARK: - Visibility-Gated State Refresh

    public func refreshState() {
        guard let win = window, win.isVisible else {
            needsRefreshOnShow = true
            return
        }
        performRefreshState()
    }

    internal func performRefreshState() {
        needsRefreshOnShow = false
        let isEn = SettingsTab.isEn

        LaunchAtLoginManager.shared.refreshStatus()
        launchAtLoginSwitch.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
        aiCuratorSwitch?.state = NativeMusicCuratorService.shared.isEnabled ? .on : .off
        aiCuratorSwitch?.isHidden = !NativeMusicCuratorService.shared.isAppleSilicon
        let isMusicRunning = MusicAppProvider.shared.isMusicAppRunning
        musicAppStatusLabel.stringValue = isMusicRunning
            ? (isEn ? "🟢 Music.app is running and ready" : "🟢 Music.app запущен и готов к работе")
            : (isEn ? "⚪ Music.app is not running" : "⚪ Music.app не запущен")
        launchMusicButton.isHidden = isMusicRunning

        devices = CoreAudioDeviceManager.shared.getOutputDevices()
        devicePopUp.removeAllItems()

        let hasActiveDLNA = DLNADiscoveryManager.shared.hasActiveRenderer
        let activeDLNA = DLNADiscoveryManager.shared.getActiveRenderer()
        let dspActiveDev = hasActiveDLNA ? nil : AudioEngineController.shared.activeHardwareOutputDeviceInfo

        for dev in devices {
            let isEffectiveActive = hasActiveDLNA ? false : (dspActiveDev != nil ? (dev.id == dspActiveDev?.id) : dev.isDefault)
            let defSuffix: String
            if isEffectiveActive {
                defSuffix = dspActiveDev != nil ? (isEn ? " (Active DSP)" : " (Активен DSP)") : (isEn ? " (Default)" : " (По умолчанию)")
            } else {
                defSuffix = ""
            }
            devicePopUp.addItem(withTitle: "\(dev.name)\(defSuffix)")
            devicePopUp.lastItem?.tag = Int(dev.id)
            devicePopUp.lastItem?.representedObject = "coreaudio:\(dev.id)"
        }

        let dlnaDevices = DLNADiscoveryManager.shared.isEnabled ? DLNADiscoveryManager.shared.getDiscoveredRenderers() : []
        if !dlnaDevices.isEmpty {
            devicePopUp.menu?.addItem(NSMenuItem.separator())
            for dlna in dlnaDevices {
                let activeSuffix = dlna.isSelected ? (isEn ? " (Active)" : " (Активен)") : ""
                devicePopUp.addItem(withTitle: "🌐 \(dlna.friendlyName) (DLNA)\(activeSuffix)")
                devicePopUp.lastItem?.tag = dlna.numericId
                devicePopUp.lastItem?.representedObject = "dlna:\(dlna.id)"
            }
        }

        let activeLocalDev = dspActiveDev.flatMap { dsp in devices.first(where: { $0.id == dsp.id }) }
            ?? devices.first(where: { $0.isDefault })

        if let active = activeDLNA {
            if let item = devicePopUp.itemArray.first(where: { ($0.representedObject as? String) == "dlna:\(active.id)" }) {
                devicePopUp.select(item)
            }
            sampleRatePopUp.removeAllItems()
            sampleRatePopUp.addItem(withTitle: isEn ? "192 kHz (DLNA Stream)" : "192 кГц (DLNA Stream)")
            sampleRatePopUp.isEnabled = false
            bitPerfectSwitch.isEnabled = false
            streamQualityLabel.stringValue = isEn
                ? "Current output: DLNA Network Streaming (WAV 192 kHz / 24-bit)"
                : "Текущий вывод: DLNA Сетевой стриминг (WAV 192 кГц / 24-бит)"
        } else if let selectedDev = activeLocalDev {
            if let item = devicePopUp.itemArray.first(where: { ($0.representedObject as? String) == "coreaudio:\(selectedDev.id)" }) {
                devicePopUp.select(item)
            }
            populateSampleRates(for: selectedDev)
            bitPerfectSwitch.isEnabled = true
            sampleRatePopUp.isEnabled = !BitPerfectLogMonitor.shared.isEnabled && (dspActiveDev == nil)
            streamQualityLabel.stringValue = isEn
                ? "Current stream: \(BitPerfectLogMonitor.shared.currentQualityDescription)"
                : "Текущий поток: \(BitPerfectLogMonitor.shared.currentQualityDescription)"
        }

        bitPerfectSwitch.state = BitPerfectLogMonitor.shared.isEnabled ? .on : .off
        let guardEnabled = CoreAudioDeviceManager.shared.isMutingGuardEnabled
        let guardMs = CoreAudioDeviceManager.shared.mutingGuardDurationMs
        dacMutingGuardSwitch.state = guardEnabled ? .on : .off
        dacMutingGuardPopUp.isEnabled = guardEnabled
        dacMutingGuardPopUp.selectItem(withTag: dacMutingGuardPopUp.indexOfItem(withTag: guardMs) != -1 ? guardMs : 100)

        let isVolLocked = PlaybackStateStore.shared.isVolumeLockedTo100
        lockVolume100Switch.state = isVolLocked ? .on : .off
        spectralAnalyzerSwitch.state = SpectralIntegrityAnalyzer.shared.isEnabled ? .on : .off
        discoverDLNASwitch.state = DLNADiscoveryManager.shared.isEnabled ? .on : .off
        updateDLNAStatusLabel()
        refreshDSPControlsState()

        let ampCtrl = ExternalAmpTCPController.shared
        let ampEnabled = isVolLocked && ampCtrl.isEnabled
        let soundCheckEnabled = ampEnabled && ampCtrl.isSoundCheckEnabled
        enableExtAmpSwitch.isEnabled = isVolLocked
        enableExtAmpSwitch.state = ampEnabled ? .on : .off
        extAmpSoundCheckSwitch.isEnabled = ampEnabled
        extAmpSoundCheckSwitch.state = soundCheckEnabled ? .on : .off
        extAmpLowVolSmartNormSwitch.isEnabled = soundCheckEnabled
        extAmpLowVolSmartNormSwitch.state = (soundCheckEnabled && ampCtrl.isLowVolumeSmartNormEnabled) ? .on : .off
        extAmpCompressionCompSwitch.isEnabled = soundCheckEnabled
        extAmpCompressionCompSwitch.state = (soundCheckEnabled && ampCtrl.isCompressionCompensationEnabled) ? .on : .off
        if let item = extAmpProfilePopUp.itemArray.first(where: { ($0.representedObject as? String) == ampCtrl.profile.rawValue }) {
            extAmpProfilePopUp.select(item)
        }
        if extAmpIPField.currentEditor() == nil { extAmpIPField.stringValue = ampCtrl.host }
        if extAmpPortField.currentEditor() == nil { extAmpPortField.stringValue = "\(ampCtrl.port)" }
        if extAmpMaxCapField.currentEditor() == nil { extAmpMaxCapField.stringValue = "\(ampCtrl.maxVolumeCap)" }
        extAmpMaxCapStepper.integerValue = ampCtrl.maxVolumeCap
        extAmpProfilePopUp.isEnabled = ampEnabled
        extAmpIPField.isEnabled = ampEnabled
        extAmpPortField.isEnabled = ampEnabled
        extAmpMaxCapField.isEnabled = ampEnabled
        extAmpMaxCapStepper.isEnabled = ampEnabled
        saveExtAmpButton.isEnabled = ampEnabled
        testExtAmpConnectionButton.isEnabled = ampEnabled
        refreshAmpStatusLabel()

        let isDMREnabled = UPnPMediaRendererServer.shared.isEnabled
        enableLocalDMRSwitch.state = isDMREnabled ? .on : .off
        if upnpFriendlyNameField.currentEditor() == nil {
            upnpFriendlyNameField.stringValue = SSDPService.shared.friendlyName
        }
        upnpFriendlyNameField.isEnabled = isDMREnabled
        saveNameButton.isEnabled = isDMREnabled
        copyUpnpButton.isEnabled = isDMREnabled

        let upnpPort = UPnPMediaRendererServer.shared.port
        let primaryIP = WebSocketServer.shared.getLANIPAddresses().first ?? "127.0.0.1"
        upnpUrlField.stringValue = "http://\(primaryIP):\(upnpPort)/description.xml"
        if isDMREnabled {
            upnpStatusLabel.stringValue = isEn
                ? "🟢 Port \(upnpPort) • SSDP Discovery active (UDN: \(SSDPService.shared.deviceUDN))"
                : "🟢 Порт \(upnpPort) • SSDP Discovery активен (UDN: \(SSDPService.shared.deviceUDN))"
            upnpStatusLabel.textColor = .systemGreen
        } else {
            upnpStatusLabel.stringValue = isEn ? "Status: Local DMR disabled" : "Статус: Локальный DMR отключен"
            upnpStatusLabel.textColor = .secondaryLabelColor
        }

        refreshFileLoggingStatusLabelAsync()
        refreshCloudSyncStatusLabel()

        let wsPort = WebSocketServer.shared.port
        wsUrlField.stringValue = "http://\(primaryIP):\(wsPort)"
        let clientCount = WebSocketServer.shared.clientCount
        let pendingCount = ClientDeviceManager.shared.pendingCount
        if pendingCount > 0 {
            clientsLabel.stringValue = isEn
                ? "🟠 Active connections: \(clientCount) • Pending authorization: \(pendingCount)"
                : "🟠 Активных подключений: \(clientCount) • Ожидают авторизации: \(pendingCount)"
            clientsLabel.textColor = .systemOrange
        } else {
            clientsLabel.stringValue = isEn
                ? "🟢 Active WebSocket connections: \(clientCount)"
                : "🟢 Активных подключений по WebSocket: \(clientCount)"
            clientsLabel.textColor = .secondaryLabelColor
        }
        refreshTVLibraryControlsState()
        refreshClientDevicesSection(updateWindowSize: true)
        if let editingId = activeEditingDeviceId,
           let dev = ClientDeviceManager.shared.getDevice(deviceId: editingId) {
            activeDeviceLockSwitch?.state = dev.lockScreenControls ? .on : .off
            activeDeviceAllowDACSwitch?.state = dev.allowDACSelection ? .on : .off
            activeDeviceAllowDSPSwitch?.state = dev.allowDSPPresetSelection ? .on : .off
            activeDeviceAllowRoomSwitch?.state = dev.allowRoomMeasurement ? .on : .off
            activeDeviceAllowLateNightSwitch?.state = dev.allowLateNightMode ? .on : .off
            activeDeviceAllowLibrarySwitch?.state = dev.allowLibraryModification ? .on : .off
        }

        let wled = WLEDDDPController.shared
        enableWLEDSwitch.state = wled.isEnabled ? .on : .off
        if wledIPField.currentEditor() == nil { wledIPField.stringValue = wled.ipAddress }
        if wledLedCountField.currentEditor() == nil { wledLedCountField.stringValue = "\(wled.ledCount)" }
        wledIPField.isEnabled = wled.isEnabled
        wledLedCountField.isEnabled = wled.isEnabled
        saveWLEDIPButton.isEnabled = wled.isEnabled
        wledModePopUp.isEnabled = wled.isEnabled
        if let item = wledModePopUp.itemArray.first(where: { ($0.representedObject as? String) == wled.mode }) {
            wledModePopUp.select(item)
        }
        if wled.isEnabled && !wled.ipAddress.isEmpty && wled.mode != "off" {
            wledStatusLabel.stringValue = isEn
                ? "🟢 Active: UDP \(wled.ipAddress):4048 • \(wled.ledCount) LED • 16 zones • 40 FPS (Gamma 2.0)"
                : "🟢 Активен: UDP \(wled.ipAddress):4048 • \(wled.ledCount) LED • 16 зон • 40 FPS (Gamma 2.0)"
            wledStatusLabel.textColor = .systemGreen
        } else if wled.isEnabled && wled.ipAddress.isEmpty {
            wledStatusLabel.stringValue = isEn
                ? "🟠 Enter WLED controller IP address and click 'Apply'"
                : "🟠 Укажите IP-адрес контроллера WLED и нажмите «Применить»"
            wledStatusLabel.textColor = .systemOrange
        } else if wled.isEnabled && wled.mode == "off" {
            wledStatusLabel.stringValue = isEn
                ? "⚪ Ambilight off ('Off' mode • Heartbeat OFF active)"
                : "⚪ Подсветка выключена (режим «Без подсветки» • Heartbeat OFF активен)"
            wledStatusLabel.textColor = .secondaryLabelColor
        } else if !wled.ipAddress.isEmpty {
            wledStatusLabel.stringValue = isEn
                ? "WLED Status: Disabled (Heartbeat OFF keeps strip \(wled.ipAddress) off)"
                : "Статус WLED: Отключено (Heartbeat OFF удерживает ленту \(wled.ipAddress) выключенной)"
            wledStatusLabel.textColor = .secondaryLabelColor
        } else {
            wledStatusLabel.stringValue = isEn
                ? "WLED Status: Disabled (WLED buttons hidden in Web UI)"
                : "Статус WLED: Отключено (кнопки WLED скрыты в веб-интерфейсе)"
            wledStatusLabel.textColor = .secondaryLabelColor
        }
    }
}
