//
//  SettingsWindow+PlaybackAndAudio.swift
//  AppleMusicRemoteMac
//
//  Playback tab builder and CoreAudio / Bit-Perfect / DAC Muting Guard /
//  Spectral Analyzer / DLNA renderer selection actions.
//

import AppKit
import CoreAudio

extension SettingsWindow {
    internal func buildPlaybackTabView() -> NSView {
        let isEn = SettingsTab.isEn

        devicePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        devicePopUp.controlSize = .regular
        devicePopUp.target = self
        devicePopUp.action = #selector(deviceSelectionChanged(_:))
        devicePopUp.widthAnchor.constraint(equalToConstant: 325).isActive = true

        sampleRatePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        sampleRatePopUp.controlSize = .regular
        sampleRatePopUp.target = self
        sampleRatePopUp.action = #selector(sampleRateSelectionChanged(_:))
        sampleRatePopUp.widthAnchor.constraint(equalToConstant: 190).isActive = true

        streamQualityLabel = makeStatusCaption(isEn ? "Current stream: 44.1 kHz (Lossless)" : "Текущий поток: 44.1 кГц (Lossless)")

        let rateRightStack = NSStackView(views: [sampleRatePopUp, streamQualityLabel])
        rateRightStack.orientation = .vertical
        rateRightStack.alignment = .leading
        rateRightStack.spacing = 5

        bitPerfectSwitch = makeCheckbox(
            title: isEn ? "Automatic Bit-Perfect sample rate switching" : "Автоматическое переключение частоты ЦАП (Bit-Perfect)",
            action: #selector(bitPerfectToggled(_:))
        )
        lockVolume100Switch = makeCheckbox(
            title: isEn ? "Lock Music.app volume at 100%" : "Фиксировать громкость Music.app на 100%",
            action: #selector(lockVolume100Toggled(_:))
        )
        dacMutingGuardSwitch = makeCheckbox(
            title: isEn ? "DAC relay muting guard:" : "Защита реле ЦАП (DAC Muting Guard):",
            action: #selector(dacMutingGuardToggled(_:))
        )

        dacMutingGuardPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        dacMutingGuardPopUp.controlSize = .regular
        dacMutingGuardPopUp.target = self
        dacMutingGuardPopUp.action = #selector(dacMutingGuardDurationChanged(_:))
        dacMutingGuardPopUp.widthAnchor.constraint(equalToConstant: 185).isActive = true
        let guardOptions: [(title: String, ms: Int)] = [
            ("50 мс (Быстрый PLL)", 50),
            ("100 мс (Стандарт ЦАП)", 100),
            ("150 мс (Реле ЦАП)", 150),
            ("250 мс (R2R / Лампа)", 250)
        ]
        for opt in guardOptions {
            dacMutingGuardPopUp.addItem(withTitle: opt.title)
            dacMutingGuardPopUp.lastItem?.tag = opt.ms
        }

        let dacGuardLine = NSStackView(views: [dacMutingGuardSwitch, dacMutingGuardPopUp])
        dacGuardLine.orientation = .horizontal
        dacGuardLine.alignment = .centerY
        dacGuardLine.spacing = 10

        let dacGuardDesc = makeIndentedSubcaptionContainer(
            makeMusicSubcaption(
                isEn
                    ? "Click-free micro-silence while the external DAC locks its PLL clock and relays on sample rate changes."
                    : "Бесщелчковая микро-пауза тишины на время перестройки PLL и реле ЦАП при смене частоты."
            )
        )
        let dacGuardStack = NSStackView(views: [dacGuardLine, dacGuardDesc])
        dacGuardStack.orientation = .vertical
        dacGuardStack.alignment = .leading
        dacGuardStack.spacing = 4
        dacGuardDesc.widthAnchor.constraint(equalTo: dacGuardStack.widthAnchor).isActive = true

        spectralAnalyzerSwitch = makeCheckbox(
            title: isEn ? "Real-time spectral integrity verifier (vDSP FFT)" : "Спектральный верификатор подлинности (vDSP FFT)",
            action: #selector(spectralAnalyzerToggled(_:))
        )
        discoverDLNASwitch = makeCheckbox(
            title: isEn ? "Discover external DLNA / BluOS network streamers" : "Искать сетевые стримеры DLNA / BluOS (Bluesound, WiiM)",
            action: #selector(discoverDLNAToggled(_:))
        )
        dlnaStatusLabel = makeStatusCaption(isEn ? "DLNA Status: Disabled" : "Статус DLNA: Отключено")
        let dlnaStatusIndent = makeIndentedViewContainer(dlnaStatusLabel)
        let dlnaRightStack = NSStackView(views: [discoverDLNASwitch, dlnaStatusIndent])
        dlnaRightStack.orientation = .vertical
        dlnaRightStack.alignment = .leading
        dlnaRightStack.spacing = 5
        dlnaStatusIndent.widthAnchor.constraint(equalTo: dlnaRightStack.widthAnchor).isActive = true

        return makeMusicPreferencePage(sections: [
            [
                makeMusicControlRow(
                    category: isEn ? "Audio Output:" : "Аудиовыход:",
                    control: devicePopUp,
                    subtitle: isEn
                        ? "Select a local CoreAudio DAC or external DLNA / BluOS network renderer."
                        : "Выберите локальный ЦАП CoreAudio или внешний сетевой стример DLNA / BluOS."
                ),
                makeMusicTwoColumnRow(category: isEn ? "Sample Rate:" : "Частота ЦАП:", rightContent: rateRightStack, topLabelOffset: 3)
            ],
            [
                makeMusicCheckboxRow(
                    category: "Bit-Perfect:",
                    checkbox: bitPerfectSwitch,
                    subtitle: isEn
                        ? "Automatically match hardware output sample rate and bit depth to the active Music.app ALAC stream."
                        : "Автоматически переключать частоту и разрядность ЦАП под активный поток ALAC в Music.app."
                ),
                makeMusicCheckboxRow(
                    category: "",
                    checkbox: lockVolume100Switch,
                    subtitle: isEn
                        ? "Bypass digital mixer attenuation for bit-accurate output."
                        : "Побитовая передача сигнала без цифровой аттенюации программного микшера."
                ),
                makeMusicTwoColumnRow(category: "", rightContent: dacGuardStack, topLabelOffset: 2),
                makeMusicCheckboxRow(
                    category: "",
                    checkbox: spectralAnalyzerSwitch,
                    subtitle: isEn
                        ? "Analyze live audio bandwidth to detect upsampled lossy masters vs genuine Hi-Res."
                        : "Анализ спектра аудиопотока в реальном времени для проверки подлинности Hi-Res / Lossless."
                )
            ],
            [
                makeMusicTwoColumnRow(category: isEn ? "Network Audio:" : "Сетевой вывод:", rightContent: dlnaRightStack, topLabelOffset: 1)
            ]
        ])
    }

    internal func populateSampleRates(for dev: AudioOutputDevice) {
        sampleRatePopUp.removeAllItems()
        let standardRates: [Double] = [44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000]
        var rates = Set(dev.availableSampleRates)
        for r in standardRates { rates.insert(r) }

        let unit = isEn ? "kHz" : "кГц"
        for rate in rates.sorted() {
            let khz = rate / 1000.0
            let title: String
            if khz == 352.8 {
                title = "352.8 \(unit) (DXD)"
            } else if khz.truncatingRemainder(dividingBy: 1) == 0 {
                title = String(format: "%.0f %@", khz, unit)
            } else {
                title = String(format: "%.1f %@", khz, unit)
            }
            sampleRatePopUp.addItem(withTitle: title)
            sampleRatePopUp.lastItem?.tag = Int(rate)
        }

        let curInt = Int(dev.currentSampleRate)
        if sampleRatePopUp.indexOfItem(withTag: curInt) != -1 {
            sampleRatePopUp.selectItem(withTag: curInt)
        }
    }

    internal func updateDLNAStatusLabel() {
        let isEn = SettingsTab.isEn
        if DLNADiscoveryManager.shared.isEnabled {
            let count = DLNADiscoveryManager.shared.getDiscoveredCount()
            dlnaStatusLabel.stringValue = isEn
                ? "🟢 DLNA / BluOS discovery active (devices found: \(count))"
                : "🟢 Поиск DLNA / BluOS активен (найдено устройств: \(count))"
            dlnaStatusLabel.textColor = .systemGreen
        } else {
            dlnaStatusLabel.stringValue = isEn
                ? "DLNA Status: External renderer discovery disabled"
                : "Статус DLNA: Поиск внешних рендереров отключен"
            dlnaStatusLabel.textColor = .secondaryLabelColor
        }
    }

    @objc internal func deviceSelectionChanged(_ sender: NSPopUpButton) {
        guard let selectedItem = sender.selectedItem,
              let repObj = selectedItem.representedObject as? String else { return }

        if repObj.hasPrefix("dlna:") {
            if let renderer = DLNADiscoveryManager.shared.selectRenderer(uid: repObj) {
                NSLog("[SettingsWindow] Selected DLNA renderer: \(renderer.friendlyName)")
                Task.detached(priority: .userInitiated) {
                    await AudioEngineController.shared.suspendForDLNARouting()
                    let status = MusicBridge.shared.getPlayerStatus()
                    if status.isPlaying {
                        AudioProcessTapService.shared.startCapture()
                        let (streamURL, imageURL, fullTitle, metadata) = DLNADiscoveryManager.shared.resolveStreamAndImageURLs()
                        DLNADiscoveryManager.shared.setAVTransportURI(uri: streamURL, metadata: metadata, imageURL: imageURL, title: fullTitle) { success, _ in
                            if success, !renderer.isBluOS {
                                DLNADiscoveryManager.shared.play()
                            }
                        }
                    } else {
                        let isLossy = status.audioQuality.contains("AAC") || status.audioQuality.contains("MP3")
                        let targetRate = isLossy ? 44100 : (status.track?.sampleRate ?? 44100)
                        let targetDepth = isLossy ? 16 : (status.track?.bitDepth ?? (targetRate >= 48000 ? 24 : 16))
                        AudioProcessTapService.shared.setFormat(sampleRate: targetRate, bitDepth: targetDepth)
                    }

                    RoomAcousticService.shared.refreshLocalPassthroughEQPipeline()
                    WebSocketServer.shared.broadcastAudioDevices()
                    WebSocketServer.shared.broadcastStatus(includeQueue: false)
                    WebSocketServer.shared.broadcastEvent(name: "dsp_settings", data: WebSocketServer.buildDSPSettingsDictionary())
                    WebSocketServer.shared.broadcastEvent(name: "room_acoustic_settings", data: RoomAcousticService.shared.statusDictionary())
                    await MainActor.run {
                        SettingsWindow.refreshIfVisible()
                        MenuManager.shared.updateMenuState()
                    }
                }
            }
        } else if repObj.hasPrefix("coreaudio:") {
            let idStr = repObj.replacingOccurrences(of: "coreaudio:", with: "")
            if let parsedId = UInt32(idStr) {
                let devID = AudioDeviceID(parsedId)
                let hadDLNA = DLNADiscoveryManager.shared.hasActiveRenderer
                if hadDLNA {
                    DLNADiscoveryManager.shared.stopPlayback()
                    DLNADiscoveryManager.shared.deselectRenderer()
                }
                let (wasMuted, restoreVol) = PlaybackStateStore.shared.withLock { () -> (Bool, Int) in
                    let m = PlaybackStateStore.shared.isDLNAMuted
                    let v = PlaybackStateStore.shared.preDLNAVolume > 0 ? PlaybackStateStore.shared.preDLNAVolume : 100
                    PlaybackStateStore.shared.isDLNAMuted = false
                    return (m, v)
                }
                _ = CoreAudioDeviceManager.shared.setDefaultOutputDevice(id: devID)
                Task.detached(priority: .userInitiated) {
                    if wasMuted || hadDLNA {
                        AudioProcessTapService.shared.setMutingGuardZeroFill(false)
                        if wasMuted {
                            Self.restoreMutedPlaybackVolume(restoreVol: restoreVol)
                        }
                    }
                    if AudioEngineController.shared.currentConfigurationSnapshot().mode != .bitPerfectPassthrough {
                        await AudioEngineController.shared.handleUserSelectedLocalDevice(id: devID)
                    }
                    RoomAcousticService.shared.refreshLocalPassthroughEQPipeline()
                    if hadDLNA {
                        AudioProcessTapService.shared.reconcileCaptureAfterRouteChange()
                    }
                    WebSocketServer.shared.broadcastAudioDevices()
                    WebSocketServer.shared.broadcastStatus(includeQueue: false)
                    WebSocketServer.shared.broadcastEvent(name: "dsp_settings", data: WebSocketServer.buildDSPSettingsDictionary())
                    WebSocketServer.shared.broadcastEvent(name: "room_acoustic_settings", data: RoomAcousticService.shared.statusDictionary())
                    await MainActor.run {
                        SettingsWindow.refreshIfVisible()
                        MenuManager.shared.updateMenuState()
                    }
                }
            }
        }

        refreshState()
        MenuManager.shared.updateMenuState()
    }

    @objc internal func sampleRateSelectionChanged(_ sender: NSPopUpButton) {
        guard !DLNADiscoveryManager.shared.hasActiveRenderer else { return }
        let rate = Double(sender.selectedTag())
        let devID = AudioDeviceID(devicePopUp.selectedTag())
        _ = CoreAudioDeviceManager.shared.setSampleRate(rate, for: devID)
        MenuManager.shared.updateMenuState()
    }

    @objc internal func bitPerfectToggled(_ sender: NSButton) {
        let isEnabled = (sender.state == .on)
        BitPerfectLogMonitor.shared.isEnabled = isEnabled
        sampleRatePopUp.isEnabled = !isEnabled
        MenuManager.shared.updateMenuState()
    }

    @objc internal func dacMutingGuardToggled(_ sender: NSButton) {
        let enabled = (sender.state == .on)
        CoreAudioDeviceManager.shared.isMutingGuardEnabled = enabled
        dacMutingGuardPopUp.isEnabled = enabled
        DispatchQueue.global(qos: .userInitiated).async {
            WebSocketServer.shared.broadcastStatus(includeQueue: false)
        }
    }

    @objc internal func dacMutingGuardDurationChanged(_ sender: NSPopUpButton) {
        let ms = sender.selectedTag()
        if ms >= 30 && ms <= 500 {
            CoreAudioDeviceManager.shared.mutingGuardDurationMs = ms
            DispatchQueue.global(qos: .userInitiated).async {
                WebSocketServer.shared.broadcastStatus(includeQueue: false)
            }
        }
    }

    @objc internal func lockVolume100Toggled(_ sender: NSButton) {
        let enabled = (sender.state == .on)
        PlaybackStateStore.shared.isVolumeLockedTo100 = enabled
        refreshState()
        DispatchQueue.global(qos: .userInitiated).async {
            if enabled {
                PlaybackTransportController.shared.checkAndEnforceVolumeLock()
            }
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.lastPlayerStatusCache = nil
            }
            WebSocketServer.shared.broadcastStatus(includeQueue: false)
        }
    }

    @objc internal func spectralAnalyzerToggled(_ sender: NSButton) {
        let enabled = (sender.state == .on)
        SpectralIntegrityAnalyzer.shared.isEnabled = enabled
        DispatchQueue.global(qos: .userInitiated).async {
            WebSocketServer.shared.broadcastStatus(includeQueue: false)
        }
    }

    @objc internal func discoverDLNAToggled(_ sender: NSButton) {
        let isEnabled = (sender.state == .on)
        let hadActiveRenderer = !isEnabled && DLNADiscoveryManager.shared.hasActiveRenderer
        var wasMuted = false
        var restoreVol = 100
        if !isEnabled {
            if hadActiveRenderer {
                DLNADiscoveryManager.shared.stopPlayback()
                DLNADiscoveryManager.shared.deselectRenderer()
            }
            let muteState = PlaybackStateStore.shared.withLock { () -> (Bool, Int) in
                let m = PlaybackStateStore.shared.isDLNAMuted
                let v = PlaybackStateStore.shared.preDLNAVolume > 0 ? PlaybackStateStore.shared.preDLNAVolume : 100
                PlaybackStateStore.shared.isDLNAMuted = false
                return (m, v)
            }
            wasMuted = muteState.0
            restoreVol = muteState.1
            if wasMuted || hadActiveRenderer {
                AudioProcessTapService.shared.setMutingGuardZeroFill(false)
            }
        }
        DLNADiscoveryManager.shared.setEnabled(isEnabled)
        refreshState()

        let shouldRestoreVol = !isEnabled && wasMuted
        let targetRestoreVol = restoreVol
        let shouldResumeLocalDSP = !isEnabled && (AudioEngineController.shared.currentConfigurationSnapshot().mode != .bitPerfectPassthrough)

        Task.detached(priority: .userInitiated) {
            if shouldRestoreVol {
                Self.restoreMutedPlaybackVolume(restoreVol: targetRestoreVol)
            }
            if shouldResumeLocalDSP {
                _ = await AudioEngineController.shared.startOrReconfigurePipeline()
            }
            RoomAcousticService.shared.refreshLocalPassthroughEQPipeline()
            if hadActiveRenderer {
                AudioProcessTapService.shared.reconcileCaptureAfterRouteChange()
            }
            WebSocketServer.shared.broadcastAudioDevices()
            WebSocketServer.shared.broadcastStatus(includeQueue: false)
            WebSocketServer.shared.broadcastEvent(name: "dsp_settings", data: WebSocketServer.buildDSPSettingsDictionary())
            WebSocketServer.shared.broadcastEvent(name: "room_acoustic_settings", data: RoomAcousticService.shared.statusDictionary())
            await MainActor.run {
                SettingsWindow.refreshIfVisible()
                MenuManager.shared.updateMenuState()
            }
        }
    }

    nonisolated private static func restoreMutedPlaybackVolume(restoreVol: Int) {
        if AudioDuckingController.shared.isDucked {
            let duckedVol = AudioDuckingController.shared.currentDuckedVolume
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.simulatedVolume = duckedVol
                PlaybackStateStore.shared.lastPlayerStatusCache = nil
            }
            if let app = MusicAppProvider.shared.getMusicApp() {
                app.soundVolume = duckedVol
            }
        } else if PlaybackStateStore.shared.isVolumeLockedTo100 {
            PlaybackStateStore.shared.withLock {
                PlaybackStateStore.shared.lastPlayerStatusCache = nil
            }
            if let app = MusicAppProvider.shared.getMusicApp() {
                app.soundVolume = 100
            }
        } else {
            _ = MusicBridge.shared.setVolume(restoreVol)
        }
    }
}
