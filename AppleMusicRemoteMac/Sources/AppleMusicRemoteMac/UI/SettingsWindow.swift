//
//  SettingsWindow.swift
//  AppleMusicRemoteMac
//
//  Pure Swift & AppKit Native Settings Window for Apple Music Remote
//  Styled in macOS Sonoma / Sequoia System Settings aesthetic with grouped cards,
//  SF Symbols squircle badges, and native NSSwitch toggles.
//

import AppKit
import CoreAudio

private final class FlippedContentView: NSView {
    override var isFlipped: Bool { true }
}

private final class SettingsCardView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.masksToBounds = true
        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderWidth = 1.0
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        }
    }
}

@MainActor
public final class SettingsWindow: NSWindowController {
    public static let shared = SettingsWindow()

    // UI Elements - System & Autonomy
    private var launchAtLoginSwitch: NSSwitch!
    private var musicAppStatusLabel: NSTextField!
    private var launchMusicButton: NSButton!

    // UI Elements - Audio
    private var devicePopUp: NSPopUpButton!
    private var sampleRatePopUp: NSPopUpButton!
    private var bitPerfectSwitch: NSSwitch!
    private var lockVolume100Switch: NSSwitch!
    private var streamQualityLabel: NSTextField!
    private var discoverDLNASwitch: NSSwitch!
    private var dlnaStatusLabel: NSTextField!

    // UI Elements - WLED DDP Ambilight
    private var enableWLEDSwitch: NSSwitch!
    private var wledIPField: NSTextField!
    private var wledLedCountField: NSTextField!
    private var saveWLEDIPButton: NSButton!
    private var wledModePopUp: NSPopUpButton!
    private var wledStatusLabel: NSTextField!

    // UI Elements - WebSocket / iOS
    private var wsUrlField: NSTextField!
    private var clientsLabel: NSTextField!

    // UI Elements - UPnP & DLNA
    private var enableLocalDMRSwitch: NSSwitch!
    private var upnpFriendlyNameField: NSTextField!
    private var saveNameButton: NSButton!
    private var upnpUrlField: NSTextField!
    private var copyUpnpButton: NSButton!
    private var upnpStatusLabel: NSTextField!

    private var devices: [AudioOutputDevice] = []

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 760),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Настройки Apple Music Remote"
        window.titlebarSeparatorStyle = .line
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        setupUI()
        setupListeners()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Apple-Friendly macOS System Settings UI Construction

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let visualEffect = NSVisualEffectView(frame: contentView.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.blendingMode = .withinWindow
        visualEffect.material = .windowBackground
        visualEffect.state = .active
        contentView.addSubview(visualEffect)

        let scrollView = NSScrollView(frame: visualEffect.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let flippedDoc = FlippedContentView(frame: NSRect(x: 0, y: 0, width: 560, height: 900))
        flippedDoc.translatesAutoresizingMaskIntoConstraints = false

        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 18
        mainStack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 24, right: 20)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        // --- Hero Banner Card ---
        let heroCard = buildHeroHeaderCard()
        mainStack.addArrangedSubview(heroCard)
        heroCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -40).isActive = true

        // --- 1. Main / General & Remote Control Section ---
        wsUrlField = makeReadonlyMonospaceField("http://127.0.0.1:8080", width: 205)
        let qrButton = NSButton(title: "QR-код", target: self, action: #selector(showQRClicked))
        qrButton.bezelStyle = .rounded
        let restartButton = NSButton(title: "Перезапустить", target: self, action: #selector(restartServerClicked))
        restartButton.bezelStyle = .rounded

        let wsControls = NSStackView(views: [wsUrlField, qrButton, restartButton])
        wsControls.orientation = .horizontal
        wsControls.alignment = .centerY
        wsControls.spacing = 6

        launchAtLoginSwitch = makeSwitch(action: #selector(launchAtLoginToggled(_:)))
        clientsLabel = makeStatusCaption("Клиентов подключено: 0")

        let mainGroup = makeSectionGroup(
            symbol: "gearshape.fill",
            badgeColor: .systemIndigo,
            title: "Основные параметры и Пульт управления (iOS / PWA / StandBy TV)",
            rows: [
                makeControlRow(title: "Адрес сервера", subtitle: "Откройте в Safari на iPhone, iPad, Mac или Smart TV", control: wsControls),
                makeToggleRow(title: "Запускать при входе в macOS", subtitle: "Автоматический старт фонового сервера в строке меню", toggle: launchAtLoginSwitch),
                makeFooterRow(view: clientsLabel)
            ]
        )
        mainStack.addArrangedSubview(mainGroup)
        mainGroup.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -40).isActive = true

        // --- 2. Audio & Bit-Perfect Section ---
        devicePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        devicePopUp.controlSize = .regular
        devicePopUp.target = self
        devicePopUp.action = #selector(deviceSelectionChanged(_:))
        devicePopUp.widthAnchor.constraint(equalToConstant: 250).isActive = true

        sampleRatePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        sampleRatePopUp.controlSize = .regular
        sampleRatePopUp.target = self
        sampleRatePopUp.action = #selector(sampleRateSelectionChanged(_:))
        sampleRatePopUp.widthAnchor.constraint(equalToConstant: 180).isActive = true

        bitPerfectSwitch = makeSwitch(action: #selector(bitPerfectToggled(_:)))
        lockVolume100Switch = makeSwitch(action: #selector(lockVolume100Toggled(_:)))
        discoverDLNASwitch = makeSwitch(action: #selector(discoverDLNAToggled(_:)))

        streamQualityLabel = makeStatusCaption("Текущий поток: 44.1 кГц (Lossless)")
        dlnaStatusLabel = makeStatusCaption("Статус DLNA: Отключено")

        let audioFooter = NSStackView(views: [streamQualityLabel, dlnaStatusLabel])
        audioFooter.orientation = .vertical
        audioFooter.alignment = .leading
        audioFooter.spacing = 3

        let audioGroup = makeSectionGroup(
            symbol: "waveform",
            badgeColor: .systemPink,
            title: "Вывод звука и Bit-Perfect ЦАП",
            rows: [
                makeControlRow(title: "Устройство вывода", subtitle: "Локальный ЦАП CoreAudio или сетевой DLNA-стример", control: devicePopUp),
                makeControlRow(title: "Частота дискретизации", subtitle: "Аппаратная частота выбранного аудиовыхода", control: sampleRatePopUp),
                makeToggleRow(title: "Авто-Bit-Perfect", subtitle: "Автоматически переключать частоту ЦАП под поток Music.app", toggle: bitPerfectSwitch),
                makeToggleRow(title: "Фиксация громкости 100%", subtitle: "Побитовая передача без цифровой аттенюации микшера", toggle: lockVolume100Switch),
                makeToggleRow(title: "Обнаружение сетевых стримеров", subtitle: "Искать внешние рендереры DLNA / BluOS (Bluesound, WiiM)", toggle: discoverDLNASwitch),
                makeFooterRow(view: audioFooter)
            ]
        )
        mainStack.addArrangedSubview(audioGroup)
        audioGroup.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -40).isActive = true

        // --- 2. WLED DDP Ambilight Section ---
        enableWLEDSwitch = makeSwitch(action: #selector(wledEnabledToggled(_:)))

        wledIPField = NSTextField()
        wledIPField.placeholderString = "192.168.1.100"
        wledIPField.bezelStyle = .roundedBezel
        wledIPField.controlSize = .regular
        wledIPField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        wledIPField.widthAnchor.constraint(equalToConstant: 132).isActive = true
        wledIPField.target = self
        wledIPField.action = #selector(saveWLEDIPClicked)

        let ledCountCaption = NSTextField(labelWithString: "LED:")
        ledCountCaption.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        ledCountCaption.textColor = .secondaryLabelColor

        wledLedCountField = NSTextField()
        wledLedCountField.placeholderString = "120"
        wledLedCountField.bezelStyle = .roundedBezel
        wledLedCountField.controlSize = .regular
        wledLedCountField.alignment = .center
        wledLedCountField.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        wledLedCountField.widthAnchor.constraint(equalToConstant: 52).isActive = true
        wledLedCountField.target = self
        wledLedCountField.action = #selector(saveWLEDIPClicked)

        saveWLEDIPButton = NSButton(title: "Применить", target: self, action: #selector(saveWLEDIPClicked))
        saveWLEDIPButton.bezelStyle = .rounded
        saveWLEDIPButton.controlSize = .regular

        let wledAddressControls = NSStackView(views: [wledIPField, ledCountCaption, wledLedCountField, saveWLEDIPButton])
        wledAddressControls.orientation = .horizontal
        wledAddressControls.alignment = .centerY
        wledAddressControls.spacing = 6

        wledModePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        wledModePopUp.controlSize = .regular
        wledModePopUp.target = self
        wledModePopUp.action = #selector(wledModeSelectionChanged(_:))
        wledModePopUp.widthAnchor.constraint(equalToConstant: 265).isActive = true
        let modes: [(title: String, value: String)] = [
            ("Без подсветки", "off"),
            ("Синусоида ритма (стоячая волна под музыку)", "breathing"),
            ("Спектральный эквалайзер (Бас · Вокал · Верх)", "spectrum"),
            ("Симметричный пульс (раскрытие от центра)", "vu_center"),
            ("Живой Ambilight (16 зон + пульс музыки)", "ambilight"),
            ("Гармонический резонанс (цвет и ритм мелодии)", "harmonic"),
            ("Статичная палитра обложки", "static")
        ]
        for m in modes {
            wledModePopUp.addItem(withTitle: m.title)
            wledModePopUp.lastItem?.representedObject = m.value
        }

        wledStatusLabel = makeStatusCaption("Статус WLED: Отключено")

        let wledGroup = makeSectionGroup(
            symbol: "sparkles",
            badgeColor: .systemOrange,
            title: "Подсветка WLED DDP Ambilight",
            rows: [
                makeToggleRow(title: "Включить WLED DDP подсветку", subtitle: "Реалтайм 50 FPS спектр обложки по UDP (порт 4048)", toggle: enableWLEDSwitch),
                makeControlRow(title: "Контроллер WLED", subtitle: "IP-адрес и число светодиодов (авто по /json/info)", control: wledAddressControls),
                makeControlRow(title: "Режим свечения", subtitle: "Алгоритм пространственной заливки адресной ленты", control: wledModePopUp),
                makeFooterRow(view: wledStatusLabel)
            ]
        )
        mainStack.addArrangedSubview(wledGroup)
        wledGroup.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -40).isActive = true

        // --- 4. UPnP / DLNA MediaRenderer (Home Assistant) Section ---
        enableLocalDMRSwitch = makeSwitch(action: #selector(localDMRToggled(_:)))

        upnpFriendlyNameField = NSTextField()
        upnpFriendlyNameField.placeholderString = "Apple Music Remote (Mac)"
        upnpFriendlyNameField.bezelStyle = .roundedBezel
        upnpFriendlyNameField.font = NSFont.systemFont(ofSize: 12)
        upnpFriendlyNameField.widthAnchor.constraint(equalToConstant: 195).isActive = true

        saveNameButton = NSButton(title: "Сохранить", target: self, action: #selector(saveFriendlyNameClicked))
        saveNameButton.bezelStyle = .rounded

        let nameControls = NSStackView(views: [upnpFriendlyNameField, saveNameButton])
        nameControls.orientation = .horizontal
        nameControls.alignment = .centerY
        nameControls.spacing = 6

        upnpUrlField = makeReadonlyMonospaceField("http://127.0.0.1:8090/description.xml", width: 235)
        copyUpnpButton = NSButton(title: "Копировать", target: self, action: #selector(copyUpnpUrlClicked))
        copyUpnpButton.bezelStyle = .rounded

        let upnpUrlControls = NSStackView(views: [upnpUrlField, copyUpnpButton])
        upnpUrlControls.orientation = .horizontal
        upnpUrlControls.alignment = .centerY
        upnpUrlControls.spacing = 6

        upnpStatusLabel = makeStatusCaption("Статус: Отключен в настройках")

        let upnpGroup = makeSectionGroup(
            symbol: "hifispeaker.2.fill",
            badgeColor: .systemBlue,
            title: "Интеграция с Home Assistant (UPnP / DLNA DMR)",
            rows: [
                makeToggleRow(title: "Локальный DLNA DMR-плеер", subtitle: "Управление воспроизведением из Home Assistant (порт 8090)", toggle: enableLocalDMRSwitch),
                makeControlRow(title: "Имя в сети", subtitle: "Отображаемое имя при автообнаружении SSDP", control: nameControls),
                makeControlRow(title: "URL описания XML", subtitle: "Для ручного добавления DLNA Digital Media Renderer", control: upnpUrlControls),
                makeFooterRow(view: upnpStatusLabel)
            ]
        )
        mainStack.addArrangedSubview(upnpGroup)
        upnpGroup.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -40).isActive = true

        flippedDoc.addSubview(mainStack)
        scrollView.documentView = flippedDoc
        visualEffect.addSubview(scrollView)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: flippedDoc.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: flippedDoc.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: flippedDoc.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: flippedDoc.bottomAnchor),
            flippedDoc.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
    }

    // MARK: - Apple-Style Reusable UI Builders

    private func buildHeroHeaderCard() -> NSView {
        let card = SettingsCardView()
        card.translatesAutoresizingMaskIntoConstraints = false

        let hStack = NSStackView()
        hStack.orientation = .horizontal
        hStack.alignment = .centerY
        hStack.spacing = 14
        hStack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        hStack.translatesAutoresizingMaskIntoConstraints = false

        // App Squircle Badge
        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 11
        badge.layer?.backgroundColor = NSColor.systemPink.cgColor
        badge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 44),
            badge.heightAnchor.constraint(equalToConstant: 44)
        ])

        if let img = NSImage(systemSymbolName: "music.note.house.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 21, weight: .semibold)
            let iv = NSImageView(image: img.withSymbolConfiguration(config) ?? img)
            iv.contentTintColor = .white
            iv.translatesAutoresizingMaskIntoConstraints = false
            badge.addSubview(iv)
            NSLayoutConstraint.activate([
                iv.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
                iv.centerYAnchor.constraint(equalTo: badge.centerYAnchor)
            ])
        }

        let titleLabel = NSTextField(labelWithString: "Apple Music Remote")
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .labelColor

        let subLabel = NSTextField(labelWithString: "Bit-Perfect CoreAudio • UPnP/DLNA • WLED Ambilight")
        subLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        subLabel.textColor = .secondaryLabelColor

        musicAppStatusLabel = NSTextField(labelWithString: "🟢 Music.app активен")
        musicAppStatusLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        musicAppStatusLabel.textColor = .secondaryLabelColor

        let textStack = NSStackView(views: [titleLabel, subLabel, musicAppStatusLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        launchMusicButton = NSButton(title: "Запустить Music.app", target: self, action: #selector(launchMusicAppClicked))
        launchMusicButton.bezelStyle = .rounded
        launchMusicButton.controlSize = .small

        hStack.addArrangedSubview(badge)
        hStack.addArrangedSubview(textStack)
        hStack.addArrangedSubview(spacer)
        hStack.addArrangedSubview(launchMusicButton)

        card.addSubview(hStack)
        NSLayoutConstraint.activate([
            hStack.topAnchor.constraint(equalTo: card.topAnchor),
            hStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            hStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            hStack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])
        return card
    }

    private func makeSectionGroup(symbol: String, badgeColor: NSColor, title: String, rows: [NSView]) -> NSView {
        let groupStack = NSStackView()
        groupStack.orientation = .vertical
        groupStack.alignment = .leading
        groupStack.spacing = 8
        groupStack.translatesAutoresizingMaskIntoConstraints = false

        // Header with SF Symbol squircle
        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 8
        headerRow.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)

        let iconBox = NSView()
        iconBox.wantsLayer = true
        iconBox.layer?.cornerRadius = 6
        iconBox.layer?.backgroundColor = badgeColor.cgColor
        iconBox.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconBox.widthAnchor.constraint(equalToConstant: 22),
            iconBox.heightAnchor.constraint(equalToConstant: 22)
        ])

        if let symImg = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            let iv = NSImageView(image: symImg.withSymbolConfiguration(cfg) ?? symImg)
            iv.contentTintColor = .white
            iv.translatesAutoresizingMaskIntoConstraints = false
            iconBox.addSubview(iv)
            NSLayoutConstraint.activate([
                iv.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
                iv.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor)
            ])
        }

        let headerTitle = NSTextField(labelWithString: title)
        headerTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        headerTitle.textColor = .labelColor

        headerRow.addArrangedSubview(iconBox)
        headerRow.addArrangedSubview(headerTitle)
        groupStack.addArrangedSubview(headerRow)

        // Grouped Inset Card
        let card = SettingsCardView()
        card.translatesAutoresizingMaskIntoConstraints = false

        let cardStack = NSStackView()
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 0
        cardStack.translatesAutoresizingMaskIntoConstraints = false

        for (idx, row) in rows.enumerated() {
            cardStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true
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

        groupStack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: groupStack.widthAnchor).isActive = true
        return groupStack
    }

    private func makeToggleRow(title: String, subtitle: String, toggle: NSSwitch) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleField.textColor = .labelColor

        let subField = NSTextField(labelWithString: subtitle)
        subField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subField.textColor = .secondaryLabelColor
        subField.lineBreakMode = .byWordWrapping

        let textStack = NSStackView(views: [titleField, subField])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        row.addArrangedSubview(textStack)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(toggle)
        return row
    }

    private func makeControlRow(title: String, subtitle: String, control: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false

        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleField.textColor = .labelColor

        let subField = NSTextField(labelWithString: subtitle)
        subField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subField.textColor = .secondaryLabelColor

        let textStack = NSStackView(views: [titleField, subField])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        row.addArrangedSubview(textStack)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(control)
        return row
    }

    private func makeFooterRow(view: NSView) -> NSView {
        let row = NSStackView(views: [view])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 9, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func makeSwitch(action: Selector) -> NSSwitch {
        let sw = NSSwitch()
        sw.controlSize = .regular
        sw.target = self
        sw.action = action
        return sw
    }

    private func makeStatusCaption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeReadonlyMonospaceField(_ value: String, width: CGFloat) -> NSTextField {
        let field = NSTextField(string: value)
        field.isEditable = false
        field.isSelectable = true
        field.bezelStyle = .roundedBezel
        field.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        return field
    }

    // MARK: - State Updates

    public func show() {
        refreshState()
        if let docView = (window?.contentView?.subviews.first?.subviews.first as? NSScrollView)?.documentView {
            docView.scroll(.zero)
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func refreshState() {
        // 0. System & Autonomy
        LaunchAtLoginManager.shared.refreshStatus()
        launchAtLoginSwitch.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
        let isMusicRunning = MusicAppProvider.shared.isMusicAppRunning
        musicAppStatusLabel.stringValue = isMusicRunning ? "🟢 Music.app запущен и готов к работе" : "⚪ Music.app не запущен"
        launchMusicButton.isHidden = isMusicRunning

        // 1. Audio Devices
        devices = CoreAudioDeviceManager.shared.getOutputDevices()
        devicePopUp.removeAllItems()

        let hasActiveDLNA = DLNADiscoveryManager.shared.hasActiveRenderer
        let activeDLNA = DLNADiscoveryManager.shared.getActiveRenderer()

        for dev in devices {
            let isDef = !hasActiveDLNA && dev.isDefault
            devicePopUp.addItem(withTitle: "\(dev.name)\(isDef ? " (По умолчанию)" : "")")
            if let item = devicePopUp.lastItem {
                item.tag = Int(dev.id)
                item.representedObject = "coreaudio:\(dev.id)"
            }
        }

        let dlnaDevices = DLNADiscoveryManager.shared.isEnabled ? DLNADiscoveryManager.shared.getDiscoveredRenderers() : []
        if !dlnaDevices.isEmpty {
            devicePopUp.menu?.addItem(NSMenuItem.separator())
            for dlna in dlnaDevices {
                let isSelected = dlna.isSelected
                let title = "🌐 \(dlna.friendlyName) (DLNA)\(isSelected ? " (Активен)" : "")"
                devicePopUp.addItem(withTitle: title)
                if let item = devicePopUp.lastItem {
                    item.tag = dlna.numericId
                    item.representedObject = "dlna:\(dlna.id)"
                }
            }
        }

        if let active = activeDLNA {
            if let item = devicePopUp.itemArray.first(where: { ($0.representedObject as? String) == "dlna:\(active.id)" }) {
                devicePopUp.select(item)
            }
            sampleRatePopUp.removeAllItems()
            sampleRatePopUp.addItem(withTitle: "192 кГц (DLNA Stream)")
            sampleRatePopUp.isEnabled = false
            bitPerfectSwitch.isEnabled = false
            streamQualityLabel.stringValue = "Текущий вывод: DLNA Сетевой стриминг (WAV 192 кГц / 24-бит)"
        } else if let defaultDev = devices.first(where: { $0.isDefault }) {
            if let item = devicePopUp.itemArray.first(where: { ($0.representedObject as? String) == "coreaudio:\(defaultDev.id)" }) {
                devicePopUp.select(item)
            }
            populateSampleRates(for: defaultDev)
            bitPerfectSwitch.isEnabled = true
            sampleRatePopUp.isEnabled = !BitPerfectLogMonitor.shared.isEnabled
            streamQualityLabel.stringValue = "Текущий поток: \(BitPerfectLogMonitor.shared.currentQualityDescription)"
        }

        bitPerfectSwitch.state = BitPerfectLogMonitor.shared.isEnabled ? .on : .off
        lockVolume100Switch.state = PlaybackStateStore.shared.isVolumeLockedTo100 ? .on : .off
        discoverDLNASwitch.state = DLNADiscoveryManager.shared.isEnabled ? .on : .off
        updateDLNAStatusLabel()

        // 2. UPnP & DLNA
        let isDMREnabled = UPnPMediaRendererServer.shared.isEnabled
        enableLocalDMRSwitch.state = isDMREnabled ? .on : .off
        upnpFriendlyNameField.stringValue = SSDPService.shared.friendlyName
        upnpFriendlyNameField.isEnabled = isDMREnabled
        saveNameButton.isEnabled = isDMREnabled
        copyUpnpButton.isEnabled = isDMREnabled

        let upnpPort = UPnPMediaRendererServer.shared.port
        let lanIPs = WebSocketServer.shared.getLANIPAddresses()
        let primaryIP = lanIPs.first ?? "127.0.0.1"
        upnpUrlField.stringValue = "http://\(primaryIP):\(upnpPort)/description.xml"
        if isDMREnabled {
            upnpStatusLabel.stringValue = "🟢 Порт \(upnpPort) • SSDP Discovery активен (UDN: \(SSDPService.shared.deviceUDN))"
            upnpStatusLabel.textColor = .systemGreen
        } else {
            upnpStatusLabel.stringValue = "Статус: Локальный DMR отключен"
            upnpStatusLabel.textColor = .secondaryLabelColor
        }

        // 3. Web UI & WebSocket Server
        let wsPort = WebSocketServer.shared.port
        wsUrlField.stringValue = "http://\(primaryIP):\(wsPort)"
        let clientCount = WebSocketServer.shared.clientCount
        clientsLabel.stringValue = "🟢 Активных подключений по WebSocket: \(clientCount)"

        // 4. WLED DDP Ambilight
        let wled = WLEDDDPController.shared
        enableWLEDSwitch.state = wled.isEnabled ? .on : .off
        wledIPField.stringValue = wled.ipAddress
        wledLedCountField.stringValue = "\(wled.ledCount)"
        wledIPField.isEnabled = wled.isEnabled
        wledLedCountField.isEnabled = wled.isEnabled
        saveWLEDIPButton.isEnabled = wled.isEnabled
        wledModePopUp.isEnabled = wled.isEnabled
        if let item = wledModePopUp.itemArray.first(where: { ($0.representedObject as? String) == wled.mode }) {
            wledModePopUp.select(item)
        }
        if wled.isEnabled && !wled.ipAddress.isEmpty && wled.mode != "off" {
            wledStatusLabel.stringValue = "🟢 Активен: UDP \(wled.ipAddress):4048 • \(wled.ledCount) LED • 16 зон (Gamma 2.4)"
            wledStatusLabel.textColor = .systemGreen
        } else if wled.isEnabled && wled.ipAddress.isEmpty {
            wledStatusLabel.stringValue = "🟠 Укажите IP-адрес контроллера WLED и нажмите «Применить»"
            wledStatusLabel.textColor = .systemOrange
        } else if wled.isEnabled && wled.mode == "off" {
            wledStatusLabel.stringValue = "⚪ Подсветка выключена (режим «Без подсветки» • Heartbeat OFF активен)"
            wledStatusLabel.textColor = .secondaryLabelColor
        } else if !wled.ipAddress.isEmpty {
            wledStatusLabel.stringValue = "Статус WLED: Отключено (Heartbeat OFF удерживает ленту \(wled.ipAddress) выключенной)"
            wledStatusLabel.textColor = .secondaryLabelColor
        } else {
            wledStatusLabel.stringValue = "Статус WLED: Отключено (кнопки WLED скрыты в веб-интерфейсе)"
            wledStatusLabel.textColor = .secondaryLabelColor
        }
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
            } else if khz.truncatingRemainder(dividingBy: 1) == 0 {
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

        DLNADiscoveryManager.shared.onDevicesChanged = { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.updateDLNAStatusLabel()
                self?.refreshState()
            }
        }

        WLEDDDPController.shared.onSettingsChanged = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.refreshState()
            }
        }
    }

    // MARK: - Actions

    @objc private func launchAtLoginToggled(_ sender: NSSwitch) {
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
        guard let selectedItem = sender.selectedItem,
              let repObj = selectedItem.representedObject as? String else {
            return
        }

        if repObj.hasPrefix("dlna:") {
            if let renderer = DLNADiscoveryManager.shared.selectRenderer(uid: repObj) {
                NSLog("[SettingsWindow] Selected DLNA renderer: \(renderer.friendlyName)")
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

                WebSocketServer.shared.broadcastAudioDevices()
                WebSocketServer.shared.broadcastStatus(includeQueue: false)
            }
        } else if repObj.hasPrefix("coreaudio:") {
            let idStr = repObj.replacingOccurrences(of: "coreaudio:", with: "")
            if let parsedId = UInt32(idStr) {
                let devID = AudioDeviceID(parsedId)
                if DLNADiscoveryManager.shared.hasActiveRenderer {
                    DLNADiscoveryManager.shared.stopPlayback()
                    DLNADiscoveryManager.shared.deselectRenderer()
                    AudioProcessTapService.shared.stopCapture()
                }
                _ = CoreAudioDeviceManager.shared.setDefaultOutputDevice(id: devID)
                WebSocketServer.shared.broadcastAudioDevices()
                WebSocketServer.shared.broadcastStatus(includeQueue: false)
            }
        }

        refreshState()
        MenuManager.shared.updateMenuState()
    }

    @objc private func sampleRateSelectionChanged(_ sender: NSPopUpButton) {
        guard !DLNADiscoveryManager.shared.hasActiveRenderer else { return }
        let rate = Double(sender.selectedTag())
        let devID = AudioDeviceID(devicePopUp.selectedTag())
        _ = CoreAudioDeviceManager.shared.setSampleRate(rate, for: devID)
        MenuManager.shared.updateMenuState()
    }

    @objc private func bitPerfectToggled(_ sender: NSSwitch) {
        let isEnabled = (sender.state == .on)
        BitPerfectLogMonitor.shared.isEnabled = isEnabled
        sampleRatePopUp.isEnabled = !isEnabled
        MenuManager.shared.updateMenuState()
    }

    @objc private func lockVolume100Toggled(_ sender: NSSwitch) {
        let enabled = (sender.state == .on)
        PlaybackStateStore.shared.isVolumeLockedTo100 = enabled
        if enabled {
            _ = MusicBridge.shared.setVolume(100)
        }
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
    }

    @objc private func localDMRToggled(_ sender: NSSwitch) {
        let isEnabled = (sender.state == .on)
        UPnPMediaRendererServer.shared.setEnabled(isEnabled)
        refreshState()
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

    @objc private func discoverDLNAToggled(_ sender: NSSwitch) {
        let isEnabled = (sender.state == .on)
        DLNADiscoveryManager.shared.setEnabled(isEnabled)
        if !isEnabled && DLNADiscoveryManager.shared.hasActiveRenderer {
            DLNADiscoveryManager.shared.stop()
            DLNADiscoveryManager.shared.deselectRenderer()
            if PlaybackStateStore.shared.isDLNAMuted {
                let restoreVol = PlaybackStateStore.shared.preDLNAVolume > 0 ? PlaybackStateStore.shared.preDLNAVolume : 100
                _ = MusicBridge.shared.setVolume(restoreVol)
                PlaybackStateStore.shared.isDLNAMuted = false
            }
        }
        updateDLNAStatusLabel()
        refreshState()
        WebSocketServer.shared.broadcastAudioDevices()
    }

    private func updateDLNAStatusLabel() {
        if DLNADiscoveryManager.shared.isEnabled {
            let count = DLNADiscoveryManager.shared.getDiscoveredCount()
            dlnaStatusLabel.stringValue = "🟢 Поиск DLNA / BluOS активен (найдено устройств: \(count))"
            dlnaStatusLabel.textColor = .systemGreen
        } else {
            dlnaStatusLabel.stringValue = "Статус DLNA: Поиск внешних рендереров отключен"
            dlnaStatusLabel.textColor = .secondaryLabelColor
        }
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

    @objc private func wledEnabledToggled(_ sender: NSSwitch) {
        let enabled = (sender.state == .on)
        let ip = wledIPField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedLeds = Int(wledLedCountField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        let updated = WLEDDDPController.shared.updateSettings(enabled: enabled, ip: ip, ledCount: parsedLeds)
        refreshState()
        WebSocketServer.shared.broadcastEvent(name: "wled_settings", data: updated)
    }

    @objc private func saveWLEDIPClicked() {
        let ip = wledIPField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedLeds = Int(wledLedCountField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        let updated = WLEDDDPController.shared.updateSettings(ip: ip, ledCount: parsedLeds)
        refreshState()
        WebSocketServer.shared.broadcastEvent(name: "wled_settings", data: updated)
    }

    @objc private func wledModeSelectionChanged(_ sender: NSPopUpButton) {
        guard let mode = sender.selectedItem?.representedObject as? String else { return }
        let updated = WLEDDDPController.shared.updateSettings(mode: mode)
        refreshState()
        WebSocketServer.shared.broadcastEvent(name: "wled_settings", data: updated)
    }
}
