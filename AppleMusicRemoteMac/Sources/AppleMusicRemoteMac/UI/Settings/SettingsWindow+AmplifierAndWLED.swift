//
//  SettingsWindow+AmplifierAndWLED.swift
//  AppleMusicRemoteMac
//
//  External Amplifier TCP Volume Control + Apple SoundCheck Normalization tab
//  and WLED DDP Ambilight lighting tab builders & actions.
//

import AppKit

extension SettingsWindow {
    // MARK: - Amplifier Tab

    internal func buildAmplifierTabView() -> NSView {
        let isEn = SettingsTab.isEn

        enableExtAmpSwitch = makeCheckbox(
            title: isEn ? "Control external amplifier volume over TCP" : "Управлять громкостью внешнего усилителя по TCP",
            action: #selector(extAmpEnabledToggled(_:))
        )
        extAmpSoundCheckSwitch = makeCheckbox(
            title: isEn ? "Track loudness normalization (Apple SoundCheck)" : "Нормализация громкости треков (Apple SoundCheck)",
            action: #selector(extAmpSoundCheckToggled(_:))
        )
        extAmpLowVolSmartNormSwitch = makeCheckbox(
            title: isEn ? "Smart normalization at low listening volume (< 40%)" : "Умная нормализация на низкой громкости (< 40%)",
            action: #selector(extAmpLowVolSmartNormToggled(_:))
        )
        extAmpCompressionCompSwitch = makeCheckbox(
            title: isEn ? "Dynamic compression compensation (Crest / Loudness War)" : "Компенсация динамического сжатия (Crest / Loudness War)",
            action: #selector(extAmpCompressionCompToggled(_:))
        )

        extAmpProfilePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        extAmpProfilePopUp.controlSize = .regular
        extAmpProfilePopUp.target = self
        extAmpProfilePopUp.action = #selector(extAmpProfileChanged(_:))
        extAmpProfilePopUp.widthAnchor.constraint(equalToConstant: 260).isActive = true
        for prof in ExternalAmpProfile.allCases {
            extAmpProfilePopUp.addItem(withTitle: prof.menuTitle)
            extAmpProfilePopUp.lastItem?.representedObject = prof.rawValue
        }

        extAmpIPField = NSTextField()
        extAmpIPField.placeholderString = "192.168.1.50"
        extAmpIPField.bezelStyle = .roundedBezel
        extAmpIPField.controlSize = .regular
        extAmpIPField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        extAmpIPField.widthAnchor.constraint(equalToConstant: 128).isActive = true
        extAmpIPField.target = self
        extAmpIPField.action = #selector(saveExtAmpSettingsClicked)

        let portCaption = NSTextField(labelWithString: isEn ? "Port:" : "Порт:")
        portCaption.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        portCaption.textColor = .secondaryLabelColor

        extAmpPortField = NSTextField()
        extAmpPortField.placeholderString = "9590"
        extAmpPortField.bezelStyle = .roundedBezel
        extAmpPortField.controlSize = .regular
        extAmpPortField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        extAmpPortField.alignment = .center
        extAmpPortField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        extAmpPortField.target = self
        extAmpPortField.action = #selector(saveExtAmpSettingsClicked)

        extAmpMaxCapField = NSTextField()
        extAmpMaxCapField.placeholderString = "80"
        extAmpMaxCapField.bezelStyle = .roundedBezel
        extAmpMaxCapField.controlSize = .regular
        extAmpMaxCapField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        extAmpMaxCapField.alignment = .center
        extAmpMaxCapField.widthAnchor.constraint(equalToConstant: 54).isActive = true
        extAmpMaxCapField.target = self
        extAmpMaxCapField.action = #selector(saveExtAmpSettingsClicked)

        extAmpMaxCapStepper = NSStepper()
        extAmpMaxCapStepper.minValue = 1
        extAmpMaxCapStepper.maxValue = 100
        extAmpMaxCapStepper.increment = 5
        extAmpMaxCapStepper.valueWraps = false
        extAmpMaxCapStepper.controlSize = .regular
        extAmpMaxCapStepper.target = self
        extAmpMaxCapStepper.action = #selector(extAmpMaxCapStepperChanged(_:))

        let percentSuffixLabel = NSTextField(labelWithString: isEn ? "% (slider range 0% — Max)" : "% (диапазон слайдера 0% — Макс)")
        percentSuffixLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        percentSuffixLabel.textColor = .secondaryLabelColor

        let extAmpMaxCapStack = NSStackView(views: [extAmpMaxCapField, extAmpMaxCapStepper, percentSuffixLabel])
        extAmpMaxCapStack.orientation = .horizontal
        extAmpMaxCapStack.alignment = .centerY
        extAmpMaxCapStack.spacing = 6

        saveExtAmpButton = NSButton(title: isEn ? "Apply" : "Применить", target: self, action: #selector(saveExtAmpSettingsClicked))
        saveExtAmpButton.bezelStyle = .rounded
        saveExtAmpButton.controlSize = .regular

        testExtAmpConnectionButton = NSButton(title: isEn ? "Test Connection" : "Проверить…", target: self, action: #selector(testExtAmpConnectionClicked))
        testExtAmpConnectionButton.bezelStyle = .rounded
        testExtAmpConnectionButton.controlSize = .regular

        let extAmpNetStack = NSStackView(views: [
            extAmpIPField,
            portCaption,
            extAmpPortField,
            saveExtAmpButton,
            testExtAmpConnectionButton
        ])
        extAmpNetStack.orientation = .horizontal
        extAmpNetStack.alignment = .centerY
        extAmpNetStack.spacing = 6

        extAmpStatusLabel = makeStatusCaption(
            isEn
                ? "Status: External amplifier volume control disabled"
                : "Статус: Управление громкостью внешнего усилителя отключено"
        )
        extAmpStatusLabel.lineBreakMode = .byWordWrapping

        return makeMusicPreferencePage(sections: [
            [
                makeMusicCheckboxRow(
                    category: isEn ? "Amplifier:" : "Усилитель:",
                    checkbox: enableExtAmpSwitch,
                    subtitle: isEn
                        ? "Available when Volume Lock 100% is active. Persistent TCP socket with hardware knob & remote feedback."
                        : "Доступно при фиксации громкости 100%. Постоянный TCP-сокет с обратной связью от пульта и энкодера."
                ),
                makeMusicControlRow(category: isEn ? "Model:" : "Протокол:", control: extAmpProfilePopUp, subtitle: nil),
                makeMusicControlRow(category: isEn ? "Max Volume:" : "Макс. уровень:", control: extAmpMaxCapStack, subtitle: nil),
                makeMusicControlRow(category: isEn ? "TCP Address:" : "Сетевой адрес:", control: extAmpNetStack, subtitle: nil),
                makeMusicTwoColumnRow(category: "", rightContent: extAmpStatusLabel, topLabelOffset: 0)
            ],
            [
                makeMusicCheckboxRow(
                    category: isEn ? "Normalization:" : "Нормализация:",
                    checkbox: extAmpSoundCheckSwitch,
                    subtitle: isEn
                        ? "Adjust amplifier volume per track using Apple iTunNORM metadata without altering Bit-Perfect PCM."
                        : "Аналоговое выравнивание громкости через усилитель по метаданным iTunNORM без потерь Bit-Perfect."
                ),
                makeMusicCheckboxRow(
                    category: "",
                    checkbox: extAmpLowVolSmartNormSwitch,
                    subtitle: isEn
                        ? "Adapt dB steps to non-linear attenuator curves and equal-loudness perception below 40%."
                        : "Адаптация шага дБ под нелинейную кривую аттенюатора (Rotel и др.) и восприятие слуха."
                ),
                makeMusicCheckboxRow(
                    category: "",
                    checkbox: extAmpCompressionCompSwitch,
                    subtitle: isEn
                        ? "Soften attenuation on heavily brickwalled masters (DR4–DR7) and prevent double SoundCheck."
                        : "Смягчает занижение пережатых треков (DR4–DR7) по пик-фактору и блокирует двойную коррекцию."
                )
            ]
        ])
    }

    // MARK: - WLED Tab

    internal func buildWLEDTabView() -> NSView {
        let isEn = SettingsTab.isEn

        enableWLEDSwitch = makeCheckbox(
            title: isEn ? "Enable WLED DDP Ambilight lighting" : "Включить подсветку WLED DDP Ambilight",
            action: #selector(wledEnabledToggled(_:))
        )

        wledIPField = NSTextField()
        wledIPField.placeholderString = "192.168.1.100"
        wledIPField.bezelStyle = .roundedBezel
        wledIPField.controlSize = .regular
        wledIPField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        wledIPField.widthAnchor.constraint(equalToConstant: 138).isActive = true
        wledIPField.target = self
        wledIPField.action = #selector(saveWLEDIPClicked)

        let ledCountCaption = NSTextField(labelWithString: "LED:")
        ledCountCaption.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        ledCountCaption.textColor = .secondaryLabelColor

        wledLedCountField = NSTextField()
        wledLedCountField.placeholderString = "120"
        wledLedCountField.bezelStyle = .roundedBezel
        wledLedCountField.controlSize = .regular
        wledLedCountField.alignment = .center
        wledLedCountField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        wledLedCountField.widthAnchor.constraint(equalToConstant: 56).isActive = true
        wledLedCountField.target = self
        wledLedCountField.action = #selector(saveWLEDIPClicked)

        saveWLEDIPButton = NSButton(title: isEn ? "Apply" : "Применить", target: self, action: #selector(saveWLEDIPClicked))
        saveWLEDIPButton.bezelStyle = .rounded
        saveWLEDIPButton.controlSize = .regular

        let wledAddressControls = NSStackView(views: [wledIPField, ledCountCaption, wledLedCountField, saveWLEDIPButton])
        wledAddressControls.orientation = .horizontal
        wledAddressControls.alignment = .centerY
        wledAddressControls.spacing = 8

        wledModePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        wledModePopUp.controlSize = .regular
        wledModePopUp.target = self
        wledModePopUp.action = #selector(wledModeSelectionChanged(_:))
        wledModePopUp.widthAnchor.constraint(equalToConstant: 376).isActive = true
        let modes: [(title: String, value: String)] = isEn
            ? [
                ("Off", "off"),
                ("Symmetric Pulse (Center-Out VU)", "vu_center"),
                ("Shockwave (Beat Rings from Center)", "shockwave"),
                ("Harmonic Resonance (Center Color Waves)", "harmonic"),
                ("Supernova (Core Flash & Corona)", "supernova"),
                ("Center Prism (Flowing Cover Hues)", "prism_center"),
                ("Counter-Pulse (Center Bass · Edge Highs)", "duet_wings"),
                ("Spectral Equalizer (Bass · Mids · Highs)", "spectrum"),
                ("Rhythm Sine Wave (Center Contrast)", "breathing"),
                ("Live Ambilight (16 Zones + Audio Pulse)", "ambilight"),
                ("Static Artwork Palette", "static")
            ]
            : [
                ("Без подсветки", "off"),
                ("Симметричный пульс (раскрытие от центра)", "vu_center"),
                ("Ударная волна (кольца бита от центра)", "shockwave"),
                ("Гармонический резонанс (волны цвета от центра)", "harmonic"),
                ("Сверхновая (ядро бита и корона от центра)", "supernova"),
                ("Призма от центра (перелив оттенков обложки)", "prism_center"),
                ("Встречный импульс (бас в центре · верх с краёв)", "duet_wings"),
                ("Спектральный эквалайзер (Бас · Вокал · Верх)", "spectrum"),
                ("Синусоида ритма (контрастная волна от центра)", "breathing"),
                ("Живой Ambilight (16 зон + пульс музыки)", "ambilight"),
                ("Статичная палитра обложки", "static")
            ]
        for m in modes {
            wledModePopUp.addItem(withTitle: m.title)
            wledModePopUp.lastItem?.representedObject = m.value
        }

        wledStatusLabel = makeStatusCaption(isEn ? "WLED Status: Disabled" : "Статус WLED: Отключено")
        wledStatusLabel.lineBreakMode = .byWordWrapping

        return makeMusicPreferencePage(sections: [
            [
                makeMusicCheckboxRow(
                    category: isEn ? "Lighting:" : "Подсветка:",
                    checkbox: enableWLEDSwitch,
                    subtitle: isEn
                        ? "Stream real-time 40 FPS album artwork colors and audio spectrum over UDP DDP (port 4048)."
                        : "Передача палитры обложки и аудиоспектра 40 FPS в реальном времени по протоколу UDP DDP (порт 4048)."
                )
            ],
            [
                makeMusicControlRow(
                    category: isEn ? "Controller:" : "Контроллер:",
                    control: wledAddressControls,
                    subtitle: isEn
                        ? "WLED IP address and LED strip length (auto-detected via /json/info)."
                        : "IP-адрес контроллера WLED и число светодиодов (определяется автоматически по /json/info)."
                ),
                makeMusicControlRow(category: isEn ? "Effect Mode:" : "Режим свечения:", control: wledModePopUp, subtitle: nil),
                makeMusicTwoColumnRow(category: "", rightContent: wledStatusLabel, topLabelOffset: 0)
            ]
        ])
    }

    // MARK: - Amplifier Actions & Status

    @objc internal func extAmpEnabledToggled(_ sender: NSButton) {
        guard PlaybackStateStore.shared.isVolumeLockedTo100 else {
            sender.state = .off
            refreshState()
            return
        }
        let enabled = (sender.state == .on)
        let selectedProf = (extAmpProfilePopUp.selectedItem?.representedObject as? String).flatMap(ExternalAmpProfile.init(rawValue:)) ?? ExternalAmpTCPController.shared.profile
        let host = extAmpIPField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedPort = UInt16(extAmpPortField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? selectedProf.defaultPort
        let parsedCap = Int(extAmpMaxCapField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ExternalAmpTCPController.shared.maxVolumeCap
        ExternalAmpTCPController.shared.updateConfiguration(
            profile: selectedProf,
            host: host,
            port: parsedPort,
            maxVolumeCap: parsedCap,
            isEnabled: enabled
        )
        refreshState()
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
    }

    @objc internal func extAmpProfileChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let prof = ExternalAmpProfile(rawValue: raw) else { return }
        extAmpPortField.stringValue = "\(prof.defaultPort)"
        let host = extAmpIPField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedCap = Int(extAmpMaxCapField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ExternalAmpTCPController.shared.maxVolumeCap
        ExternalAmpTCPController.shared.updateConfiguration(
            profile: prof,
            host: host,
            port: prof.defaultPort,
            maxVolumeCap: parsedCap
        )
        refreshState()
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
    }

    @objc internal func extAmpMaxCapStepperChanged(_ sender: NSStepper) {
        let clamped = max(1, min(100, sender.integerValue))
        extAmpMaxCapField.stringValue = "\(clamped)"
        ExternalAmpTCPController.shared.maxVolumeCap = clamped
        refreshState()
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
    }

    @objc internal func saveExtAmpSettingsClicked() {
        let selectedProf = (extAmpProfilePopUp.selectedItem?.representedObject as? String).flatMap(ExternalAmpProfile.init(rawValue:)) ?? ExternalAmpTCPController.shared.profile
        let host = extAmpIPField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedPort = UInt16(extAmpPortField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? selectedProf.defaultPort
        let parsedCap = Int(extAmpMaxCapField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ExternalAmpTCPController.shared.maxVolumeCap
        ExternalAmpTCPController.shared.updateConfiguration(
            profile: selectedProf,
            host: host,
            port: parsedPort,
            maxVolumeCap: parsedCap
        )
        refreshState()
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
    }

    @objc internal func testExtAmpConnectionClicked() {
        let selectedProf = (extAmpProfilePopUp.selectedItem?.representedObject as? String).flatMap(ExternalAmpProfile.init(rawValue:)) ?? ExternalAmpTCPController.shared.profile
        let host = extAmpIPField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedPort = UInt16(extAmpPortField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? selectedProf.defaultPort
        let parsedCap = Int(extAmpMaxCapField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? ExternalAmpTCPController.shared.maxVolumeCap
        ExternalAmpTCPController.shared.updateConfiguration(
            profile: selectedProf,
            host: host,
            port: parsedPort,
            maxVolumeCap: parsedCap
        )
        guard !host.isEmpty else {
            extAmpStatusLabel.stringValue = isEn
                ? "🟠 Enter the amplifier IP address to test connection"
                : "🟠 Укажите IP-адрес усилителя для проверки соединения"
            extAmpStatusLabel.textColor = .systemOrange
            return
        }
        testExtAmpConnectionButton.isEnabled = false
        testExtAmpConnectionButton.title = isEn ? "Testing..." : "Проверка..."
        extAmpStatusLabel.stringValue = isEn
            ? "⏳ Testing TCP connection to \(selectedProf.displayName) (\(host):\(parsedPort))..."
            : "⏳ Проверка TCP-соединения с \(selectedProf.displayName) (\(host):\(parsedPort))..."
        extAmpStatusLabel.textColor = .secondaryLabelColor

        ExternalAmpTCPController.shared.testConnection(
            profile: selectedProf,
            host: host,
            port: parsedPort
        ) { [weak self] success, message in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.testExtAmpConnectionButton.title = self.isEn ? "Test Connection" : "Проверить…"
                self.testExtAmpConnectionButton.isEnabled = PlaybackStateStore.shared.isVolumeLockedTo100 && ExternalAmpTCPController.shared.isEnabled
                self.extAmpStatusLabel.stringValue = message
                self.extAmpStatusLabel.textColor = success ? .systemGreen : .systemRed
                WebSocketServer.shared.broadcastStatus(includeQueue: false)
            }
        }
    }

    @objc internal func extAmpSoundCheckToggled(_ sender: NSButton) {
        guard PlaybackStateStore.shared.isVolumeLockedTo100 && ExternalAmpTCPController.shared.isEnabled else {
            sender.state = .off
            ExternalAmpTCPController.shared.isSoundCheckEnabled = false
            refreshState()
            return
        }
        ExternalAmpTCPController.shared.isSoundCheckEnabled = (sender.state == .on)
        refreshState()
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
    }

    @objc internal func extAmpLowVolSmartNormToggled(_ sender: NSButton) {
        guard PlaybackStateStore.shared.isVolumeLockedTo100 && ExternalAmpTCPController.shared.isEnabled && ExternalAmpTCPController.shared.isSoundCheckEnabled else {
            sender.state = .off
            refreshState()
            return
        }
        ExternalAmpTCPController.shared.isLowVolumeSmartNormEnabled = (sender.state == .on)
        refreshState()
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
    }

    @objc internal func extAmpCompressionCompToggled(_ sender: NSButton) {
        guard PlaybackStateStore.shared.isVolumeLockedTo100 && ExternalAmpTCPController.shared.isEnabled && ExternalAmpTCPController.shared.isSoundCheckEnabled else {
            sender.state = .off
            refreshState()
            return
        }
        ExternalAmpTCPController.shared.isCompressionCompensationEnabled = (sender.state == .on)
        refreshState()
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
    }

    public func refreshAmpStatusLabel() {
        guard extAmpStatusLabel != nil else { return }
        let isVolLocked = PlaybackStateStore.shared.isVolumeLockedTo100
        let ampCtrl = ExternalAmpTCPController.shared
        if !isVolLocked {
            extAmpStatusLabel.stringValue = isEn
                ? "⚪ Unavailable: enable 'Lock Volume to 100%' to control amplifier volume"
                : "⚪ Недоступно: включите «Фиксация громкости 100%» для управления громкостью усилителя"
            extAmpStatusLabel.textColor = .secondaryLabelColor
            return
        }
        if !ampCtrl.isEnabled {
            extAmpStatusLabel.stringValue = isEn
                ? "Status: External amplifier volume control disabled"
                : "Статус: Управление громкостью внешнего усилителя отключено"
            extAmpStatusLabel.textColor = .secondaryLabelColor
            return
        }
        if ampCtrl.host.isEmpty {
            extAmpStatusLabel.stringValue = isEn
                ? "🟠 Enter amplifier IP address (\(ampCtrl.profile.displayName)) and click 'Apply'"
                : "🟠 Укажите IP-адрес усилителя (\(ampCtrl.profile.displayName)) и нажмите «Применить»"
            extAmpStatusLabel.textColor = .systemOrange
            return
        }
        var soundCheckSuffix = ""
        if ampCtrl.isSoundCheckEnabled {
            if let gainDb = ampCtrl.currentTrackGainDb {
                let offset = ampCtrl.currentTrackVolumeOffset
                let offsetStr = offset >= 0 ? "+\(offset)%" : "\(offset)%"
                var tags: [String] = []
                if ampCtrl.isDigitalSoundCheckDetected {
                    tags.append("Music.app SC Guard")
                } else {
                    if ampCtrl.isLowVolumeSmartNormEnabled && ampCtrl.baseListeningVolume > 0 && ampCtrl.baseListeningVolume < 40 {
                        tags.append("Smart Low-Vol")
                    }
                    if ampCtrl.isCompressionCompensationEnabled, gainDb < -3.5 {
                        if let crest = ampCtrl.currentTrackCrestDb {
                            tags.append(String(format: "Crest %.1f dB", crest))
                        } else {
                            tags.append("Crest Comp")
                        }
                    }
                }
                let tagStr = tags.isEmpty ? "" : " [\(tags.joined(separator: ", "))]"
                soundCheckSuffix = isEn
                    ? String(format: " • SoundCheck%@: %+.1f dB (%@, base %d%%)", tagStr, gainDb, offsetStr, ampCtrl.baseListeningVolume)
                    : String(format: " • SoundCheck%@: %+.1f дБ (%@, база %d%%)", tagStr, gainDb, offsetStr, ampCtrl.baseListeningVolume)
            } else {
                soundCheckSuffix = isEn ? " • SoundCheck: awaiting track" : " • SoundCheck: ожидание трека"
            }
        }
        if ampCtrl.isConnected {
            let muteBadge = ampCtrl.isMuted ? " • MUTE" : ""
            extAmpStatusLabel.stringValue = isEn
                ? "🟢 Connected: \(ampCtrl.profile.displayName) (\(ampCtrl.host):\(ampCtrl.port)) • Volume: \(ampCtrl.currentVolume)% / max \(ampCtrl.maxVolumeCap)%\(muteBadge)\(soundCheckSuffix)"
                : "🟢 Подключен: \(ampCtrl.profile.displayName) (\(ampCtrl.host):\(ampCtrl.port)) • Громкость: \(ampCtrl.currentVolume)% / макс. \(ampCtrl.maxVolumeCap)%\(muteBadge)\(soundCheckSuffix)"
            extAmpStatusLabel.textColor = .systemGreen
        } else if let err = ampCtrl.lastError, !err.isEmpty {
            extAmpStatusLabel.stringValue = isEn
                ? "🟠 Waiting for socket \(ampCtrl.profile.displayName) (\(ampCtrl.host):\(ampCtrl.port)): \(err)\(soundCheckSuffix)"
                : "🟠 Ожидание сокета \(ampCtrl.profile.displayName) (\(ampCtrl.host):\(ampCtrl.port)): \(err)\(soundCheckSuffix)"
            extAmpStatusLabel.textColor = .systemOrange
        } else {
            extAmpStatusLabel.stringValue = isEn
                ? "🟠 Connecting to \(ampCtrl.profile.displayName) (\(ampCtrl.host):\(ampCtrl.port))...\(soundCheckSuffix)"
                : "🟠 Подключение к \(ampCtrl.profile.displayName) (\(ampCtrl.host):\(ampCtrl.port))...\(soundCheckSuffix)"
            extAmpStatusLabel.textColor = .systemOrange
        }
    }

    // MARK: - WLED Actions

    @objc internal func wledEnabledToggled(_ sender: NSButton) {
        let enabled = (sender.state == .on)
        let ip = wledIPField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedLeds = Int(wledLedCountField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        let updated = WLEDDDPController.shared.updateSettings(enabled: enabled, ip: ip, ledCount: parsedLeds)
        refreshState()
        WebSocketServer.shared.broadcastEvent(name: "wled_settings", data: updated)
    }

    @objc internal func saveWLEDIPClicked() {
        let ip = wledIPField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedLeds = Int(wledLedCountField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        let updated = WLEDDDPController.shared.updateSettings(ip: ip, ledCount: parsedLeds)
        refreshState()
        WebSocketServer.shared.broadcastEvent(name: "wled_settings", data: updated)
    }

    @objc internal func wledModeSelectionChanged(_ sender: NSPopUpButton) {
        guard let mode = sender.selectedItem?.representedObject as? String else { return }
        let updated = WLEDDDPController.shared.updateSettings(mode: mode)
        refreshState()
        WebSocketServer.shared.broadcastEvent(name: "wled_settings", data: updated)
    }
}
