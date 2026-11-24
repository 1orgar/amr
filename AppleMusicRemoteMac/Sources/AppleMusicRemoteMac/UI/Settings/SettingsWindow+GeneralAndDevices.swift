//
//  SettingsWindow+GeneralAndDevices.swift
//  AppleMusicRemoteMac
//
//  General tab builder, client devices list card, and QR invite launcher.
//

import AppKit

extension SettingsWindow {
    internal func buildGeneralTabView() -> NSView {
        let isEn = SettingsTab.isEn

        musicAppStatusLabel = NSTextField(labelWithString: isEn ? "🟢 Music.app is active" : "🟢 Music.app активен")
        musicAppStatusLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        musicAppStatusLabel.textColor = .labelColor

        launchMusicButton = NSButton(title: isEn ? "Launch Music.app" : "Запустить Music.app", target: self, action: #selector(launchMusicAppClicked))
        launchMusicButton.bezelStyle = .rounded
        launchMusicButton.controlSize = .small

        let musicStatusControls = NSStackView(views: [musicAppStatusLabel, launchMusicButton])
        musicStatusControls.orientation = .horizontal
        musicStatusControls.alignment = .centerY
        musicStatusControls.spacing = 10

        wsUrlField = makeReadonlyMonospaceField("http://127.0.0.1:8080", width: 205)
        let qrButton = NSButton(title: isEn ? "QR Code…" : "QR-код…", target: self, action: #selector(showQRClicked))
        qrButton.bezelStyle = .rounded
        let restartButton = NSButton(title: isEn ? "Restart" : "Перезапустить", target: self, action: #selector(restartServerClicked))
        restartButton.bezelStyle = .rounded

        let wsControls = NSStackView(views: [wsUrlField, qrButton, restartButton])
        wsControls.orientation = .horizontal
        wsControls.alignment = .centerY
        wsControls.spacing = 8

        clientsLabel = makeStatusCaption(isEn ? "Connected clients: 0" : "Клиентов подключено: 0")

        let serverDescLabel = makeMusicSubcaption(
            isEn
                ? "Open this address in Safari on iPhone, iPad, Mac, or Smart TV to control Apple Music remotely."
                : "Откройте адрес в Safari на iPhone, iPad, Mac или Smart TV для управления воспроизведением."
        )
        let serverRightStack = NSStackView(views: [wsControls, serverDescLabel, clientsLabel])
        serverRightStack.orientation = .vertical
        serverRightStack.alignment = .leading
        serverRightStack.spacing = 5
        serverDescLabel.widthAnchor.constraint(equalTo: serverRightStack.widthAnchor).isActive = true

        launchAtLoginSwitch = makeCheckbox(
            title: isEn ? "Launch Apple Music Remote at login" : "Запускать Apple Music Remote при входе в macOS",
            action: #selector(launchAtLoginToggled(_:))
        )
        aiCuratorSwitch = makeCheckbox(
            title: isEn ? "Use Native AI (Apple Neural Engine)" : "Использовать нативный ИИ (Apple Neural Engine)",
            action: #selector(aiCuratorToggled(_:))
        )

        var systemSectionRows: [NSView] = [
            makeMusicCheckboxRow(
                category: isEn ? "Startup:" : "Автозапуск:",
                checkbox: launchAtLoginSwitch,
                subtitle: isEn
                    ? "Automatically start the background server in the macOS menu bar when signing in."
                    : "Автоматически запускать фоновый сервер в строке меню macOS при входе в систему."
            )
        ]
        if NativeMusicCuratorService.shared.isAppleSilicon {
            systemSectionRows.append(
                makeMusicCheckboxRow(
                    category: isEn ? "Intelligence:" : "Интеллект:",
                    checkbox: aiCuratorSwitch,
                    subtitle: isEn
                        ? "Prompt Curator, semantic queue ordering (NLEmbedding), and Vision artwork color palettes for TV & WLED."
                        : "Промпт-Куратор, семантический поток очереди (NLEmbedding) и палитра обложек Vision для ТВ и WLED."
                )
            )
        }

        let devicesRow = buildClientDevicesRow()
        let versionSubcaption = makeMusicSubcaption("Apple Music Remote v3.0.0 • \(ClientDeviceManager.shared.gitCommitShort)")
        let musicRightStack = NSStackView(views: [musicStatusControls, versionSubcaption])
        musicRightStack.orientation = .vertical
        musicRightStack.alignment = .leading
        musicRightStack.spacing = 3

        return makeMusicPreferencePage(sections: [
            [
                makeMusicTwoColumnRow(category: "Music.app:", rightContent: musicRightStack, topLabelOffset: 1),
                makeMusicTwoColumnRow(category: isEn ? "Web Remote:" : "Веб-пульт:", rightContent: serverRightStack, topLabelOffset: 3)
            ],
            systemSectionRows,
            [devicesRow]
        ])
    }

    internal func buildClientDevicesRow() -> NSView {
        let isEn = SettingsTab.isEn
        clientDevicesStack = NSStackView()
        clientDevicesStack.orientation = .vertical
        clientDevicesStack.alignment = .leading
        clientDevicesStack.spacing = 0
        clientDevicesStack.translatesAutoresizingMaskIntoConstraints = false

        refreshClientDevicesSection(updateWindowSize: false)
        return makeMusicTwoColumnRow(
            category: isEn ? "Devices:" : "Устройства:",
            rightContent: clientDevicesStack,
            topLabelOffset: 2
        )
    }

    internal func refreshClientDevicesSection(updateWindowSize: Bool = true) {
        guard let stack = clientDevicesStack else { return }
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let allDevices = ClientDeviceManager.shared.getAllDevices()
        if allDevices.isEmpty {
            let emptyLabel = makeMusicSubcaption(isEn
                ? "No connected devices yet. Open the Web Remote on iPhone, iPad, Mac, or TV — it will appear here for authorization."
                : "Нет подключенных устройств. Откройте веб-пульт на iPhone, iPad, Mac или ТВ — устройство появится здесь для авторизации.")
            stack.addArrangedSubview(emptyLabel)
            emptyLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        } else {
            let listBox = SettingsCardView()
            listBox.translatesAutoresizingMaskIntoConstraints = false
            let innerStack = NSStackView()
            innerStack.orientation = .vertical
            innerStack.alignment = .leading
            innerStack.spacing = 0
            innerStack.translatesAutoresizingMaskIntoConstraints = false

            for (idx, dev) in allDevices.enumerated() {
                let row = makeClientDeviceRow(dev)
                innerStack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: innerStack.widthAnchor).isActive = true

                if idx < allDevices.count - 1 {
                    let sep = MusicSurfaceView { MusicSettingsPalette.hairline }
                    sep.translatesAutoresizingMaskIntoConstraints = false
                    sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
                    innerStack.addArrangedSubview(sep)
                    sep.widthAnchor.constraint(equalTo: innerStack.widthAnchor, constant: -20).isActive = true
                }
            }

            listBox.addSubview(innerStack)
            NSLayoutConstraint.activate([
                innerStack.topAnchor.constraint(equalTo: listBox.topAnchor),
                innerStack.leadingAnchor.constraint(equalTo: listBox.leadingAnchor),
                innerStack.trailingAnchor.constraint(equalTo: listBox.trailingAnchor),
                innerStack.bottomAnchor.constraint(equalTo: listBox.bottomAnchor)
            ])
            stack.addArrangedSubview(listBox)
            listBox.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        if updateWindowSize && currentTab == .general && (window?.isVisible == true),
           let targetView = tabViews[.general], let win = window {
            let w = Self.standardWindowWidth
            targetView.layoutSubtreeIfNeeded()
            Self.syncWrappingTextFieldsPreferredWidth(in: targetView, reset: false)
            targetView.layoutSubtreeIfNeeded()
            let fittingHeight = max(ceil(targetView.fittingSize.height) + 6, 200)
            Self.syncWrappingTextFieldsPreferredWidth(in: targetView, reset: true)

            let topBarHeight: CGFloat = 66
            let bottomBarHeight: CGFloat = 54
            let rawContentHeight: CGFloat = topBarHeight + fittingHeight + bottomBarHeight
            let targetHeight = win.frameRect(forContentRect: NSRect(x: 0, y: 0, width: w, height: rawContentHeight)).height
            let maxVisibleHeight = ((win.screen ?? NSScreen.main)?.visibleFrame.height ?? 860) - 48
            let clampedHeight = min(targetHeight, max(480, maxVisibleHeight))
            let clampedContentRect = win.contentRect(forFrameRect: NSRect(x: 0, y: 0, width: w, height: clampedHeight))
            let displayedContentHeight = max(200, floor(clampedContentRect.height - topBarHeight - bottomBarHeight))

            if abs(tabContainerHeightConstraint.constant - displayedContentHeight) > 1 || abs(win.frame.height - clampedHeight) > 1 {
                tabContainerHeightConstraint.constant = displayedContentHeight
                var newFrame = win.frame
                newFrame.origin.y += (newFrame.size.height - clampedHeight)
                newFrame.size.width = win.frameRect(forContentRect: NSRect(x: 0, y: 0, width: w, height: clampedContentRect.height)).width
                newFrame.size.height = clampedHeight
                if let vis = (win.screen ?? NSScreen.main)?.visibleFrame, newFrame.maxY > vis.maxY - 12 {
                    newFrame.origin.y = vis.maxY - 12 - newFrame.size.height
                }
                newFrame.origin.y = max(((win.screen ?? NSScreen.main)?.visibleFrame.minY ?? 24) + 16, newFrame.origin.y)
                win.setFrame(newFrame, display: true, animate: true)
            }
        }
    }

    private func makeClientDeviceRow(_ dev: ClientDeviceRecord) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false

        let symbolName: String
        switch dev.deviceType.lowercased() {
        case "mobile": symbolName = "iphone"
        case "tablet": symbolName = "ipad"
        case "tv": symbolName = "tv"
        default: symbolName = "laptopcomputer"
        }

        let isOnline = ClientDeviceManager.shared.isDeviceOnline(deviceId: dev.deviceId)
        let iconView = NSImageView()
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: dev.deviceType) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            iconView.image = img.withSymbolConfiguration(cfg) ?? img
        }
        iconView.contentTintColor = !dev.isAuthorized
            ? .systemOrange
            : (isOnline ? MusicSettingsPalette.accent : .secondaryLabelColor)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20)
        ])

        let titleField = NSTextField(labelWithString: "\(dev.deviceName)  •  \(dev.shortId)")
        titleField.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byTruncatingTail

        let ipPart = dev.lastIPAddress.isEmpty ? "" : " • \(dev.lastIPAddress)"
        let statusText: String
        if !dev.isAuthorized {
            statusText = isEn ? "🟠 Pending approval\(ipPart)" : "🟠 Ожидает подтверждения\(ipPart)"
        } else {
            let onlineBadge = isOnline ? (isEn ? "🟢 Online" : "🟢 Онлайн") : (isEn ? "⚪ Offline" : "⚪ Офлайн")
            let dacBadge = dev.allowDACSelection ? (isEn ? "DAC" : "ЦАП") : nil
            let dspBadge = dev.allowDSPPresetSelection ? "DSP" : nil
            let roomBadge = dev.allowRoomMeasurement ? (isEn ? "Room EQ" : "АЧХ") : nil
            let drcBadge = dev.allowLateNightMode ? "DRC" : nil
            let libBadge = dev.allowLibraryModification ? (isEn ? "Lib" : "Медиатека") : nil
            let perms = [dacBadge, dspBadge, roomBadge, drcBadge, libBadge].compactMap { $0 }.joined(separator: ", ")
            let permPart = perms.isEmpty ? "" : " • \(perms)"
            statusText = "\(onlineBadge)\(permPart)\(ipPart)"
        }

        let subField = NSTextField(labelWithString: statusText)
        subField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subField.textColor = !dev.isAuthorized ? .systemOrange : .secondaryLabelColor
        subField.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [titleField, subField])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let controlsStack = NSStackView()
        controlsStack.orientation = .horizontal
        controlsStack.alignment = .centerY
        controlsStack.spacing = 6

        let itemIdentifier = NSUserInterfaceItemIdentifier(dev.deviceId)
        if !dev.isAuthorized {
            let authBtn = MusicPillButton(
                title: isEn ? "Authorize" : "Разрешить",
                isPrimary: true,
                width: 90,
                target: self,
                action: #selector(authorizeClientDeviceClicked(_:))
            )
            authBtn.identifier = itemIdentifier

            let removeBtn = NSButton(title: "✕", target: self, action: #selector(removeClientDeviceClicked(_:)))
            removeBtn.bezelStyle = .rounded
            removeBtn.controlSize = .small
            removeBtn.toolTip = isEn ? "Reject and remove device" : "Отклонить и удалить устройство"
            removeBtn.identifier = itemIdentifier

            controlsStack.addArrangedSubview(authBtn)
            controlsStack.addArrangedSubview(removeBtn)
        } else {
            let settingsBtn = NSButton(title: isEn ? "Options…" : "Параметры…", target: self, action: #selector(openClientDeviceSettingsClicked(_:)))
            settingsBtn.bezelStyle = .rounded
            settingsBtn.controlSize = .small
            settingsBtn.toolTip = isEn ? "Permissions and features for this device" : "Права доступа и функции этого устройства"
            settingsBtn.identifier = itemIdentifier

            let removeBtn = NSButton(title: "✕", target: self, action: #selector(removeClientDeviceClicked(_:)))
            removeBtn.bezelStyle = .rounded
            removeBtn.controlSize = .small
            removeBtn.toolTip = isEn ? "Remove device from list" : "Удалить устройство из списка"
            removeBtn.identifier = itemIdentifier

            controlsStack.addArrangedSubview(settingsBtn)
            controlsStack.addArrangedSubview(removeBtn)
        }

        row.addArrangedSubview(iconView)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(controlsStack)
        return row
    }

    // MARK: - General Actions & QR Invite

    @objc internal func launchAtLoginToggled(_ sender: NSButton) {
        let enable = (sender.state == .on)
        _ = LaunchAtLoginManager.shared.setEnabled(enable)
        LaunchAtLoginManager.shared.refreshStatus()
        sender.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
        MenuManager.shared.updateMenuState()
    }

    @objc internal func aiCuratorToggled(_ sender: NSButton) {
        let enable = (sender.state == .on)
        NativeMusicCuratorService.shared.isEnabled = enable
        WebSocketServer.shared.broadcastEvent(
            name: "ai_curator_settings",
            data: NativeMusicCuratorService.shared.getSettingsDictionary()
        )
    }

    @objc internal func launchMusicAppClicked() {
        MusicAppProvider.shared.launchMusicApp { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.refreshState()
                MenuManager.shared.updateMenuState()
            }
        }
    }

    @objc internal func showQRClicked() {
        let payload = ClientDeviceManager.shared.generateShareAccessPayload()
        let shareURL = (payload["share_url"] as? String) ?? wsUrlField.stringValue
        QRCodeWindow.shared.show(for: shareURL)
    }

    @objc internal func restartServerClicked() {
        let port = WebSocketServer.shared.port
        WebSocketServer.shared.stop()
        _ = WebSocketServer.shared.start(port: port)
        refreshState()
        MenuManager.shared.updateMenuState()
    }
}
