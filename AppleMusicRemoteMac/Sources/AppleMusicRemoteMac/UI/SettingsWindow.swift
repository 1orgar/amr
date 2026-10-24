//
//  SettingsWindow.swift
//  AppleMusicRemoteMac
//
//  Pure Swift & AppKit Native Settings Window for Apple Music Remote
//  Configures Audio Output Devices, Bit-Perfect Auto-Switching, UPnP/DLNA, and WebSocket Server
//

import AppKit
import CoreAudio

@MainActor
public final class SettingsWindow: NSWindowController {
    public static let shared = SettingsWindow()

    // UI Elements - System & Autonomy
    private var launchAtLoginCheckbox: NSButton!
    private var musicAppStatusLabel: NSTextField!
    private var launchMusicButton: NSButton!

    // UI Elements - Audio
    private var devicePopUp: NSPopUpButton!
    private var sampleRatePopUp: NSPopUpButton!
    private var bitPerfectCheckbox: NSButton!
    private var lockVolume100Checkbox: NSButton!
    private var streamQualityLabel: NSTextField!

    // UI Elements - UPnP
    private var upnpFriendlyNameField: NSTextField!
    private var upnpUrlField: NSTextField!
    private var upnpStatusLabel: NSTextField!

    // UI Elements - WebSocket / iOS
    private var wsUrlField: NSTextField!
    private var clientsLabel: NSTextField!

    private var devices: [AudioOutputDevice] = []

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Настройки Apple Music Remote"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        setupUI()
        setupListeners()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Construction

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        let scrollView = NSScrollView(frame: contentView.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 18
        container.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 24, right: 24)
        container.translatesAutoresizingMaskIntoConstraints = false

        // --- 0. System & Autonomy Section ---
        let systemSectionHeader = makeSectionHeader("⚙️ Автономность и система")
        container.addArrangedSubview(systemSectionHeader)

        launchAtLoginCheckbox = NSButton(
            checkboxWithTitle: "Запускать Apple Music Remote при входе в систему",
            target: self,
            action: #selector(launchAtLoginToggled(_:))
        )
        launchAtLoginCheckbox.font = NSFont.systemFont(ofSize: 12)
        container.addArrangedSubview(launchAtLoginCheckbox)

        let musicRow = NSStackView()
        musicRow.orientation = .horizontal
        musicRow.spacing = 10
        musicAppStatusLabel = NSTextField(labelWithString: "Статус Music.app: Запущен")
        musicAppStatusLabel.font = NSFont.systemFont(ofSize: 12)
        launchMusicButton = NSButton(title: "Запустить Music.app", target: self, action: #selector(launchMusicAppClicked))
        launchMusicButton.bezelStyle = .rounded
        musicRow.addArrangedSubview(musicAppStatusLabel)
        musicRow.addArrangedSubview(launchMusicButton)
        container.addArrangedSubview(musicRow)

        container.addArrangedSubview(makeDivider())

        // --- 1. Audio Output Section ---
        let audioSectionHeader = makeSectionHeader("🎧 Вывод звука и Bit-Perfect")
        container.addArrangedSubview(audioSectionHeader)

        // Device Row
        let devRow = NSStackView()
        devRow.orientation = .horizontal
        devRow.spacing = 10
        let devLabel = NSTextField(labelWithString: "Аудиоустройство:")
        devLabel.widthAnchor.constraint(equalToConstant: 130).isActive = true
        devicePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        devicePopUp.target = self
        devicePopUp.action = #selector(deviceSelectionChanged(_:))
        devRow.addArrangedSubview(devLabel)
        devRow.addArrangedSubview(devicePopUp)
        container.addArrangedSubview(devRow)

        // Sample Rate Row
        let rateRow = NSStackView()
        rateRow.orientation = .horizontal
        rateRow.spacing = 10
        let rateLabel = NSTextField(labelWithString: "Частота ЦАП:")
        rateLabel.widthAnchor.constraint(equalToConstant: 130).isActive = true
        sampleRatePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        sampleRatePopUp.target = self
        sampleRatePopUp.action = #selector(sampleRateSelectionChanged(_:))
        rateRow.addArrangedSubview(rateLabel)
        rateRow.addArrangedSubview(sampleRatePopUp)
        container.addArrangedSubview(rateRow)

        // Bit-Perfect Checkbox
        bitPerfectCheckbox = NSButton(
            checkboxWithTitle: "Авто-Bit-Perfect (подстраивать частоту ЦАП под поток Music.app)",
            target: self,
            action: #selector(bitPerfectToggled(_:))
        )
        bitPerfectCheckbox.font = NSFont.systemFont(ofSize: 12)
        container.addArrangedSubview(bitPerfectCheckbox)

        // Lock Volume 100% Checkbox
        lockVolume100Checkbox = NSButton(
            checkboxWithTitle: "Устанавливать громкость 100% (Bit-Perfect)",
            target: self,
            action: #selector(lockVolume100Toggled(_:))
        )
        lockVolume100Checkbox.font = NSFont.systemFont(ofSize: 12)
        container.addArrangedSubview(lockVolume100Checkbox)

        // Stream Quality Label
        streamQualityLabel = NSTextField(labelWithString: "Текущий поток: 44.1 кГц (Lossless)")
        streamQualityLabel.font = NSFont.systemFont(ofSize: 11)
        streamQualityLabel.textColor = .secondaryLabelColor
        container.addArrangedSubview(streamQualityLabel)

        container.addArrangedSubview(makeDivider())

        // --- 2. UPnP / DLNA MediaRenderer Section ---
        let upnpSectionHeader = makeSectionHeader("📻 UPnP / DLNA плеер (Home Assistant)")
        container.addArrangedSubview(upnpSectionHeader)

        upnpStatusLabel = NSTextField(labelWithString: "Порт: 8090 • SSDP Discovery: Активен")
        upnpStatusLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        container.addArrangedSubview(upnpStatusLabel)

        let nameRow = NSStackView()
        nameRow.orientation = .horizontal
        nameRow.spacing = 10
        let nameLabel = NSTextField(labelWithString: "Сетевое имя:")
        nameLabel.widthAnchor.constraint(equalToConstant: 130).isActive = true
        upnpFriendlyNameField = NSTextField()
        upnpFriendlyNameField.placeholderString = "Apple Music Remote (Mac)"
        upnpFriendlyNameField.widthAnchor.constraint(equalToConstant: 200).isActive = true
        let saveNameButton = NSButton(title: "Сохранить", target: self, action: #selector(saveFriendlyNameClicked))
        saveNameButton.bezelStyle = .rounded
        nameRow.addArrangedSubview(nameLabel)
        nameRow.addArrangedSubview(upnpFriendlyNameField)
        nameRow.addArrangedSubview(saveNameButton)
        container.addArrangedSubview(nameRow)

        let upnpRow = NSStackView()
        upnpRow.orientation = .horizontal
        upnpRow.spacing = 8
        upnpUrlField = NSTextField(string: "http://127.0.0.1:8090/description.xml")
        upnpUrlField.isEditable = false
        upnpUrlField.isSelectable = true
        upnpUrlField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        upnpUrlField.widthAnchor.constraint(equalToConstant: 290).isActive = true

        let copyUpnpButton = NSButton(title: "Копировать", target: self, action: #selector(copyUpnpUrlClicked))
        copyUpnpButton.bezelStyle = .rounded
        upnpRow.addArrangedSubview(upnpUrlField)
        upnpRow.addArrangedSubview(copyUpnpButton)
        container.addArrangedSubview(upnpRow)

        let upnpHint = NSTextField(labelWithString: "В Home Assistant добавьте 'DLNA Digital Media Renderer' с этим URL для полного управления.")
        upnpHint.font = NSFont.systemFont(ofSize: 11)
        upnpHint.textColor = .tertiaryLabelColor
        container.addArrangedSubview(upnpHint)

        container.addArrangedSubview(makeDivider())

        // --- 3. iOS Remote / WebSocket Server Section ---
        let wsSectionHeader = makeSectionHeader("📱 Сервер для iOS (Apple Music Remote)")
        container.addArrangedSubview(wsSectionHeader)

        clientsLabel = NSTextField(labelWithString: "Клиентов подключено: 0")
        clientsLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        container.addArrangedSubview(clientsLabel)

        let wsRow = NSStackView()
        wsRow.orientation = .horizontal
        wsRow.spacing = 8
        wsUrlField = NSTextField(string: "ws://127.0.0.1:8080")
        wsUrlField.isEditable = false
        wsUrlField.isSelectable = true
        wsUrlField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        wsUrlField.widthAnchor.constraint(equalToConstant: 290).isActive = true

        let qrButton = NSButton(title: "QR-код", target: self, action: #selector(showQRClicked))
        qrButton.bezelStyle = .rounded
        wsRow.addArrangedSubview(wsUrlField)
        wsRow.addArrangedSubview(qrButton)
        container.addArrangedSubview(wsRow)

        let srvActionsRow = NSStackView()
        srvActionsRow.orientation = .horizontal
        srvActionsRow.spacing = 10

        let restartButton = NSButton(title: "🔄 Перезапустить сервер", target: self, action: #selector(restartServerClicked))
        restartButton.bezelStyle = .rounded
        srvActionsRow.addArrangedSubview(restartButton)
        container.addArrangedSubview(srvActionsRow)

        // ClipView setup
        let clipView = NSClipView(frame: contentView.bounds)
        clipView.documentView = container
        scrollView.contentView = clipView

        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            container.topAnchor.constraint(equalTo: clipView.topAnchor)
        ])
    }

    private func makeSectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        return label
    }

    private func makeDivider() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 430).isActive = true
        return box
    }

    // MARK: - State Updates

    public func show() {
        refreshState()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func refreshState() {
        // 0. System & Autonomy
        LaunchAtLoginManager.shared.refreshStatus()
        launchAtLoginCheckbox.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
        let isMusicRunning = MusicAppProvider.shared.isMusicAppRunning
        musicAppStatusLabel.stringValue = isMusicRunning ? "Статус Music.app: 🟢 Запущен" : "Статус Music.app: ⚪ Не запущен"
        launchMusicButton.isHidden = isMusicRunning

        // 1. Audio Devices
        devices = CoreAudioDeviceManager.shared.getOutputDevices()
        devicePopUp.removeAllItems()
        for dev in devices {
            devicePopUp.addItem(withTitle: "\(dev.name)\(dev.isDefault ? " (По умолчанию)" : "")")
            devicePopUp.lastItem?.tag = Int(dev.id)
        }

        if let defaultDev = devices.first(where: { $0.isDefault }) {
            devicePopUp.selectItem(withTag: Int(defaultDev.id))
            populateSampleRates(for: defaultDev)
        }

        // Bit-Perfect switch
        bitPerfectCheckbox.state = BitPerfectLogMonitor.shared.isEnabled ? .on : .off
        sampleRatePopUp.isEnabled = !BitPerfectLogMonitor.shared.isEnabled
        lockVolume100Checkbox.state = PlaybackStateStore.shared.isVolumeLockedTo100 ? .on : .off
        streamQualityLabel.stringValue = "Текущий поток: \(BitPerfectLogMonitor.shared.currentQualityDescription)"

        // 2. UPnP
        upnpFriendlyNameField.stringValue = SSDPService.shared.friendlyName
        let upnpPort = UPnPMediaRendererServer.shared.port
        let lanIPs = WebSocketServer.shared.getLANIPAddresses()
        let primaryIP = lanIPs.first ?? "127.0.0.1"
        upnpUrlField.stringValue = "http://\(primaryIP):\(upnpPort)/description.xml"
        upnpStatusLabel.stringValue = "Порт: \(upnpPort) • SSDP Discovery: Активен (UDN: \(SSDPService.shared.deviceUDN))"

        // 3. Web UI & WebSocket Server
        let wsPort = WebSocketServer.shared.port
        wsUrlField.stringValue = "http://\(primaryIP):\(wsPort)"
        let clientCount = WebSocketServer.shared.clientCount
        clientsLabel.stringValue = "Клиентов подключено: \(clientCount) \(clientCount == 1 ? "клиент" : "клиентов")"
    }

    private func populateSampleRates(for dev: AudioOutputDevice) {
        sampleRatePopUp.removeAllItems()

        let standardRates: [Double] = [
            44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000
        ]

        var rates = Set(dev.availableSampleRates)
        for r in standardRates {
            rates.insert(r)
        }

        let sorted = rates.sorted()
        for rate in sorted {
            let khz = rate / 1000.0
            let title: String
            if khz == 352.8 {
                title = "352.8 кГц (DXD)"
            } else if (khz.truncatingRemainder(dividingBy: 1) == 0) {
                title = String(format: "%.0f кГц", khz)
            } else {
                title = String(format: "%.1f кГц", khz)
            }
            sampleRatePopUp.addItem(withTitle: title)
            sampleRatePopUp.lastItem?.tag = Int(rate)
        }

        let curInt = Int(dev.currentSampleRate)
        if sampleRatePopUp.indexOfItem(withTag: curInt) != -1 {
            sampleRatePopUp.selectItem(withTag: curInt)
        }
    }

    private func setupListeners() {
        BitPerfectLogMonitor.shared.onFormatChanged = { [weak self] _, _, desc in
            DispatchQueue.main.async {
                self?.streamQualityLabel.stringValue = "Текущий поток: \(desc)"
                MenuManager.shared.updateMenuState()
            }
        }

        CoreAudioDeviceManager.shared.onDevicesChanged = { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.refreshState()
            }
        }

        MusicAppProvider.shared.onMusicAppLaunched = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.refreshState()
            }
        }

        MusicAppProvider.shared.onMusicAppTerminated = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.refreshState()
            }
        }
    }

    // MARK: - Actions

    @objc private func launchAtLoginToggled(_ sender: NSButton) {
        let enable = (sender.state == .on)
        let success = LaunchAtLoginManager.shared.setEnabled(enable)
        if !success {
            sender.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
        }
        MenuManager.shared.updateMenuState()
    }

    @objc private func launchMusicAppClicked() {
        MusicAppProvider.shared.launchMusicApp { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.refreshState()
                MenuManager.shared.updateMenuState()
            }
        }
    }

    @objc private func deviceSelectionChanged(_ sender: NSPopUpButton) {
        let devID = AudioDeviceID(sender.selectedTag())
        _ = CoreAudioDeviceManager.shared.setDefaultOutputDevice(id: devID)
        if let selectedDev = devices.first(where: { $0.id == devID }) {
            populateSampleRates(for: selectedDev)
        }
        MenuManager.shared.updateMenuState()
    }

    @objc private func sampleRateSelectionChanged(_ sender: NSPopUpButton) {
        let rate = Double(sender.selectedTag())
        let devID = AudioDeviceID(devicePopUp.selectedTag())
        _ = CoreAudioDeviceManager.shared.setSampleRate(rate, for: devID)
        MenuManager.shared.updateMenuState()
    }

    @objc private func bitPerfectToggled(_ sender: NSButton) {
        let isEnabled = (sender.state == .on)
        BitPerfectLogMonitor.shared.isEnabled = isEnabled
        sampleRatePopUp.isEnabled = !isEnabled
        MenuManager.shared.updateMenuState()
    }

    @objc private func lockVolume100Toggled(_ sender: NSButton) {
        let enabled = (sender.state == .on)
        PlaybackStateStore.shared.isVolumeLockedTo100 = enabled
        if enabled {
            _ = MusicBridge.shared.setVolume(100)
        }
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
    }

    @objc private func saveFriendlyNameClicked() {
        let text = upnpFriendlyNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = text.isEmpty ? "Apple Music Remote (Mac)" : text
        SSDPService.shared.friendlyName = name
        upnpFriendlyNameField.stringValue = name
        SSDPService.shared.sendAliveNotifications()
    }

    @objc private func copyUpnpUrlClicked() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(upnpUrlField.stringValue, forType: .string)
    }

    @objc private func showQRClicked() {
        var url = wsUrlField.stringValue
        if url.hasPrefix("ws://") {
            url = "http://" + url.dropFirst(5)
        }
        QRCodeWindow.shared.show(for: url)
    }

    @objc private func restartServerClicked() {
        let port = WebSocketServer.shared.port
        WebSocketServer.shared.stop()
        _ = WebSocketServer.shared.start(port: port)
        refreshState()
        MenuManager.shared.updateMenuState()
    }
}
