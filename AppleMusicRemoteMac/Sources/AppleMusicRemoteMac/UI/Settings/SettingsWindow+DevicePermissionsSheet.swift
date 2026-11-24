//
//  SettingsWindow+DevicePermissionsSheet.swift
//  AppleMusicRemoteMac
//
//  Client device authorization actions and per-device capability sheet
//  (DAC, DSP, Room EQ, Late-Night DRC, Library Modification, Lock Screen).
//

import AppKit

extension SettingsWindow {
    @objc internal func authorizeClientDeviceClicked(_ sender: NSButton) {
        guard let deviceId = sender.identifier?.rawValue else { return }
        ClientDeviceManager.shared.setAuthorized(deviceId: deviceId, authorized: true)
        refreshState()
    }

    @objc internal func revokeClientDeviceClicked(_ sender: NSButton) {
        guard let deviceId = sender.identifier?.rawValue else { return }
        ClientDeviceManager.shared.setAuthorized(deviceId: deviceId, authorized: false)
        closeClientDeviceSettingsSheet()
        refreshState()
    }

    @objc internal func removeClientDeviceClicked(_ sender: NSButton) {
        guard let deviceId = sender.identifier?.rawValue else { return }
        if activeEditingDeviceId == deviceId {
            closeClientDeviceSettingsSheet()
        }
        ClientDeviceManager.shared.removeDevice(deviceId: deviceId)
        refreshState()
    }

    @objc internal func clientLockScreenSwitchToggled(_ sender: NSButton) {
        guard let deviceId = sender.identifier?.rawValue else { return }
        ClientDeviceManager.shared.setLockScreenControls(deviceId: deviceId, enabled: sender.state == .on)
        refreshState()
    }

    @objc internal func clientAllowDACSwitchToggled(_ sender: NSButton) {
        guard let deviceId = sender.identifier?.rawValue else { return }
        ClientDeviceManager.shared.setAllowDACSelection(deviceId: deviceId, enabled: sender.state == .on)
        refreshState()
    }

    @objc internal func clientAllowDSPSwitchToggled(_ sender: NSButton) {
        guard let deviceId = sender.identifier?.rawValue else { return }
        ClientDeviceManager.shared.setAllowDSPPresetSelection(deviceId: deviceId, enabled: sender.state == .on)
        refreshState()
    }

    @objc internal func clientAllowRoomSwitchToggled(_ sender: NSButton) {
        guard let deviceId = sender.identifier?.rawValue else { return }
        ClientDeviceManager.shared.setAllowRoomMeasurement(deviceId: deviceId, enabled: sender.state == .on)
        refreshState()
    }

    @objc internal func clientAllowLateNightSwitchToggled(_ sender: NSButton) {
        guard let deviceId = sender.identifier?.rawValue else { return }
        ClientDeviceManager.shared.setAllowLateNightMode(deviceId: deviceId, enabled: sender.state == .on)
        refreshState()
    }

    @objc internal func clientAllowLibrarySwitchToggled(_ sender: NSButton) {
        guard let deviceId = sender.identifier?.rawValue else { return }
        ClientDeviceManager.shared.setAllowLibraryModification(deviceId: deviceId, enabled: sender.state == .on)
        refreshState()
    }

    @objc internal func openClientDeviceSettingsClicked(_ sender: NSButton) {
        guard let deviceId = sender.identifier?.rawValue,
              let dev = ClientDeviceManager.shared.getDevice(deviceId: deviceId),
              let parentWin = self.window else { return }

        closeClientDeviceSettingsSheet()
        activeEditingDeviceId = dev.deviceId

        let sheetWidth: CGFloat = 500
        let sheetWin = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: sheetWidth, height: 470),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheetWin.isReleasedWhenClosed = false

        let rootView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: sheetWidth, height: 470))
        rootView.autoresizingMask = [.width, .height]
        rootView.blendingMode = .withinWindow
        rootView.material = .windowBackground
        rootView.state = .active
        sheetWin.contentView = rootView

        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 14
        mainStack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 10

        let symbolName: String
        switch dev.deviceType.lowercased() {
        case "mobile": symbolName = "iphone"
        case "tablet": symbolName = "ipad"
        case "tv": symbolName = "tv"
        default: symbolName = "laptopcomputer"
        }

        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 8
        badge.layer?.backgroundColor = MusicSettingsPalette.accent.cgColor
        badge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 32),
            badge.heightAnchor.constraint(equalToConstant: 32)
        ])
        if let symImg = NSImage(systemSymbolName: symbolName, accessibilityDescription: dev.deviceName) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            let iv = NSImageView(image: symImg.withSymbolConfiguration(cfg) ?? symImg)
            iv.contentTintColor = .white
            iv.translatesAutoresizingMaskIntoConstraints = false
            badge.addSubview(iv)
            NSLayoutConstraint.activate([
                iv.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
                iv.centerYAnchor.constraint(equalTo: badge.centerYAnchor)
            ])
        }

        let isOnline = ClientDeviceManager.shared.isDeviceOnline(deviceId: dev.deviceId)
        let titleLabel = NSTextField(labelWithString: isEn ? "Device Settings: \(dev.deviceName)" : "Настройки устройства: \(dev.deviceName)")
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = .labelColor

        let ipPart = dev.lastIPAddress.isEmpty ? "LAN" : dev.lastIPAddress
        let onlineStr = isOnline ? (isEn ? "🟢 Online" : "🟢 Онлайн") : (isEn ? "⚪ Offline" : "⚪ Офлайн")
        let codeWord = isEn ? "Code" : "Код"
        let subLabel = NSTextField(labelWithString: "\(onlineStr) • \(codeWord): \(dev.shortId) • IP: \(ipPart)")
        subLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        subLabel.textColor = .secondaryLabelColor

        let headerTextStack = NSStackView(views: [titleLabel, subLabel])
        headerTextStack.orientation = .vertical
        headerTextStack.alignment = .leading
        headerTextStack.spacing = 2
        headerRow.addArrangedSubview(badge)
        headerRow.addArrangedSubview(headerTextStack)

        let itemIdentifier = NSUserInterfaceItemIdentifier(dev.deviceId)

        let nameField = NSTextField(string: dev.deviceName)
        nameField.bezelStyle = .roundedBezel
        nameField.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        nameField.widthAnchor.constraint(equalToConstant: 195).isActive = true
        self.activeDeviceNameField = nameField

        let makeSheetSwitch: (Bool, Selector) -> NSButton = { initialState, action in
            let sw = MusicCheckboxButton(title: "", target: self, action: action)
            sw.state = initialState ? .on : .off
            sw.identifier = itemIdentifier
            return sw
        }

        let allowDACSwitch = makeSheetSwitch(dev.allowDACSelection, #selector(clientAllowDACSwitchToggled(_:)))
        let allowDSPSwitch = makeSheetSwitch(dev.allowDSPPresetSelection, #selector(clientAllowDSPSwitchToggled(_:)))
        let allowRoomSwitch = makeSheetSwitch(dev.allowRoomMeasurement, #selector(clientAllowRoomSwitchToggled(_:)))
        let allowLateNightSwitch = makeSheetSwitch(dev.allowLateNightMode, #selector(clientAllowLateNightSwitchToggled(_:)))
        let allowLibrarySwitch = makeSheetSwitch(dev.allowLibraryModification, #selector(clientAllowLibrarySwitchToggled(_:)))
        let lockSwitch = makeSheetSwitch(dev.lockScreenControls, #selector(clientLockScreenSwitchToggled(_:)))

        self.activeDeviceAllowDACSwitch = allowDACSwitch
        self.activeDeviceAllowDSPSwitch = allowDSPSwitch
        self.activeDeviceAllowRoomSwitch = allowRoomSwitch
        self.activeDeviceAllowLateNightSwitch = allowLateNightSwitch
        self.activeDeviceAllowLibrarySwitch = allowLibrarySwitch
        self.activeDeviceLockSwitch = lockSwitch

        let revokeBtn = NSButton(title: isEn ? "Revoke Access" : "Отозвать доступ", target: self, action: #selector(revokeClientDeviceClicked(_:)))
        revokeBtn.bezelStyle = .rounded
        revokeBtn.controlSize = .small
        revokeBtn.identifier = itemIdentifier

        let rows: [NSView] = [
            makeSheetControlRow(
                title: isEn ? "Device Name" : "Имя устройства",
                subtitle: isEn ? "Display name in client list and PWA" : "Отображаемое имя в списке клиентов и в PWA",
                control: nameField
            ),
            makeSheetToggleRow(
                title: isEn ? "DAC & Audio Output Selection" : "Выбор ЦАП и аудиовыхода",
                subtitle: isEn ? "Allow switching DAC, DLNA streamers, and QR invites" : "Разрешить переключение ЦАП, стримеров DLNA и выпуск QR-приглашений",
                toggle: allowDACSwitch
            ),
            makeSheetToggleRow(
                title: isEn ? "DSP Preset Selection" : "Выбор пресета DSP",
                subtitle: isEn ? "Allow switching DSP presets and engine parameters" : "Разрешить смену пресетов и параметров DSP-движка из PWA",
                toggle: allowDSPSwitch
            ),
            makeSheetToggleRow(
                title: isEn ? "Quick Room EQ Measurement" : "Быстрое измерение АЧХ комнаты",
                subtitle: isEn ? "Allow measuring room acoustics via iPhone / iPad microphone" : "Разрешить замер АЧХ комнаты микрофоном iPhone / iPad из PWA",
                toggle: allowRoomSwitch
            ),
            makeSheetToggleRow(
                title: isEn ? "Late-Night Mode (DRC)" : "Ночной режим (Late-Night DRC)",
                subtitle: isEn ? "Allow toggling Late-Night Dynamic Range Control" : "Разрешить управление ночным контролем динамики из PWA",
                toggle: allowLateNightSwitch
            ),
            makeSheetToggleRow(
                title: isEn ? "Library Deletion, Amp Mute & WLED" : "Удаление из медиатеки, Mute усилителя и WLED",
                subtitle: isEn ? "Allow deleting library items, changing MusicKit user token, amp mute, and WLED settings" : "Разрешить удаление из медиатеки, смену токена Apple Music, Mute усилителя и настройки WLED",
                toggle: allowLibrarySwitch
            ),
            makeSheetToggleRow(
                title: isEn ? "Lock Screen & Dynamic Island" : "Экран блокировки и Dynamic Island",
                subtitle: isEn ? "Playback controls on Lock Screen and Control Center" : "Управление воспроизведением на заблокированном экране и в Пункте управления",
                toggle: lockSwitch
            ),
            makeSheetControlRow(
                title: isEn ? "Device Authorization" : "Авторизация устройства",
                subtitle: "UID: \(dev.deviceId)",
                control: revokeBtn
            )
        ]

        let card = SettingsCardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        let cardStack = NSStackView()
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 0
        cardStack.translatesAutoresizingMaskIntoConstraints = false

        for (idx, r) in rows.enumerated() {
            cardStack.addArrangedSubview(r)
            r.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true
            if idx < rows.count - 1 {
                let sepWrap = NSView()
                sepWrap.translatesAutoresizingMaskIntoConstraints = false
                let sep = NSBox()
                sep.boxType = .separator
                sep.translatesAutoresizingMaskIntoConstraints = false
                sepWrap.addSubview(sep)
                NSLayoutConstraint.activate([
                    sepWrap.heightAnchor.constraint(equalToConstant: 1),
                    sep.leadingAnchor.constraint(equalTo: sepWrap.leadingAnchor, constant: 14),
                    sep.trailingAnchor.constraint(equalTo: sepWrap.trailingAnchor, constant: -14),
                    sep.centerYAnchor.constraint(equalTo: sepWrap.centerYAnchor)
                ])
                cardStack.addArrangedSubview(sepWrap)
                sepWrap.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true
            }
        }
        card.addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: card.topAnchor),
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])

        let footerRow = NSStackView()
        footerRow.orientation = .horizontal
        footerRow.alignment = .centerY
        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let doneBtn = MusicPillButton(
            title: isEn ? "Done" : "Готово",
            isPrimary: true,
            width: 88,
            target: self,
            action: #selector(saveAndCloseDeviceSettingsSheet)
        )
        doneBtn.keyEquivalent = "\r"
        footerRow.addArrangedSubview(footerSpacer)
        footerRow.addArrangedSubview(doneBtn)

        mainStack.addArrangedSubview(headerRow)
        mainStack.addArrangedSubview(card)
        mainStack.addArrangedSubview(footerRow)

        card.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -40).isActive = true
        footerRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -40).isActive = true

        rootView.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: rootView.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor)
        ])
        rootView.layoutSubtreeIfNeeded()
        let fittedSheetHeight = max(440, ceil(mainStack.fittingSize.height))
        sheetWin.setContentSize(NSSize(width: sheetWidth, height: fittedSheetHeight))
        mainStack.bottomAnchor.constraint(lessThanOrEqualTo: rootView.bottomAnchor).isActive = true

        self.activeDeviceSheetWindow = sheetWin
        parentWin.beginSheet(sheetWin, completionHandler: nil)
    }

    private func makeSheetToggleRow(title: String, subtitle: String, toggle: NSButton) -> NSView {
        let row = NSStackView()
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 3
        row.edgeInsets = NSEdgeInsets(top: 7, left: 14, bottom: 7, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false

        toggle.title = title
        let subLabel = makeMusicSubcaption(subtitle)
        let indented = makeIndentedSubcaptionContainer(subLabel)
        row.addArrangedSubview(toggle)
        row.addArrangedSubview(indented)
        indented.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -28).isActive = true
        return row
    }

    private func makeSheetControlRow(title: String, subtitle: String, control: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleField = NSTextField(wrappingLabelWithString: title)
        titleField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        titleField.textColor = .labelColor
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let subField = makeMusicSubcaption(subtitle)
        let textStack = NSStackView(views: [titleField, subField])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)

        row.addArrangedSubview(textStack)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(control)
        return row
    }

    @objc internal func saveAndCloseDeviceSettingsSheet() {
        if let devId = activeEditingDeviceId,
           let nameField = activeDeviceNameField {
            let newName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newName.isEmpty {
                ClientDeviceManager.shared.updateDeviceName(deviceId: devId, name: newName)
            }
        }
        closeClientDeviceSettingsSheet()
        refreshState()
    }

    internal func closeClientDeviceSettingsSheet() {
        if let sheet = activeDeviceSheetWindow {
            if let parent = self.window {
                parent.endSheet(sheet)
            }
            sheet.orderOut(nil)
        }
        activeDeviceSheetWindow = nil
        activeEditingDeviceId = nil
        activeDeviceNameField = nil
        activeDeviceLockSwitch = nil
        activeDeviceAllowDACSwitch = nil
        activeDeviceAllowDSPSwitch = nil
        activeDeviceAllowRoomSwitch = nil
        activeDeviceAllowLateNightSwitch = nil
        activeDeviceAllowLibrarySwitch = nil
    }
}
