//
//  SettingsWindow.swift
//  AppleMusicRemoteMac
//
//  Pure Swift & AppKit Native Settings Window for Apple Music Remote
//  Styled after macOS Music.app Settings with top icon tabs, grouped cards,
//  SF Symbols squircle badges, and native NSSwitch toggles.
//

import AppKit
import CoreAudio

private enum SettingsTab: Int, CaseIterable {
    case general = 0
    case playback = 1
    case amplifier = 2
    case wled = 3
    case advanced = 4

    private var isEn: Bool {
        let lang = Locale.preferredLanguages.first?.lowercased() ?? "ru"
        return !lang.hasPrefix("ru")
    }

    var tabTitle: String {
        switch self {
        case .general: return isEn ? "General" : "Основные"
        case .playback: return isEn ? "Playback" : "Воспроизведение"
        case .amplifier: return isEn ? "Amplifier" : "Усилитель"
        case .wled: return isEn ? "Lighting" : "Подсветка"
        case .advanced: return isEn ? "Advanced" : "Дополнения"
        }
    }

    var windowTitle: String {
        switch self {
        case .general: return isEn ? "General" : "Основные"
        case .playback: return isEn ? "Playback" : "Воспроизведение"
        case .amplifier: return isEn ? "External Amplifier" : "Управление громкостью усилителя"
        case .wled: return isEn ? "WLED Lighting" : "Подсветка WLED"
        case .advanced: return isEn ? "Advanced" : "Дополнения"
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .playback: return "play.circle"
        case .amplifier: return "dial.medium"
        case .wled: return "sparkles"
        case .advanced: return "gearshape.2"
        }
    }
}

private final class MusicTabButtonView: NSView {
    let tab: SettingsTab
    var onSelect: ((SettingsTab) -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var isSelectedTab: Bool = false
    private var isHovered: Bool = false
    private var trackingArea: NSTrackingArea?

    init(tab: SettingsTab) {
        self.tab = tab
        super.init(frame: NSRect(x: 0, y: 0, width: 96, height: 54))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 96),
            heightAnchor.constraint(equalToConstant: 54)
        ])

        if let img = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: tab.tabTitle) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
            iconView.image = img.withSymbolConfiguration(cfg) ?? img
        }
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = tab.tabTitle
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [iconView, titleLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSelected(_ selected: Bool) {
        isSelectedTab = selected
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?(tab)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if isSelectedTab {
                layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.09).cgColor
                layer?.borderWidth = 1.0
                layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.14).cgColor
                iconView.contentTintColor = .systemPink
                titleLabel.textColor = .systemPink
            } else {
                layer?.backgroundColor = isHovered
                    ? NSColor.labelColor.withAlphaComponent(0.04).cgColor
                    : NSColor.clear.cgColor
                layer?.borderWidth = 0.0
                layer?.borderColor = NSColor.clear.cgColor
                iconView.contentTintColor = .secondaryLabelColor
                titleLabel.textColor = .secondaryLabelColor
            }
        }
    }
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

    // Tabs state
    private var currentTab: SettingsTab = .general
    private var tabButtons: [SettingsTab: MusicTabButtonView] = [:]
    private var tabViews: [SettingsTab: NSView] = [:]
    private var tabContentContainer: NSView!
    private var tabContainerHeightConstraint: NSLayoutConstraint!

    // UI Elements - System & Autonomy
    private var launchAtLoginSwitch: NSSwitch!
    private var aiCuratorSwitch: NSSwitch!
    private var musicAppStatusLabel: NSTextField!
    private var launchMusicButton: NSButton!

    // UI Elements - Audio
    private var devicePopUp: NSPopUpButton!
    private var sampleRatePopUp: NSPopUpButton!
    private var bitPerfectSwitch: NSSwitch!
    private var dacMutingGuardSwitch: NSSwitch!
    private var dacMutingGuardPopUp: NSPopUpButton!
    private var lockVolume100Switch: NSSwitch!
    private var spectralAnalyzerSwitch: NSSwitch!
    private var streamQualityLabel: NSTextField!
    private var discoverDLNASwitch: NSSwitch!
    private var dlnaStatusLabel: NSTextField!

    // UI Elements - External Amplifier TCP Volume Control
    private var enableExtAmpSwitch: NSSwitch!
    private var extAmpSoundCheckSwitch: NSSwitch!
    private var extAmpLowVolSmartNormSwitch: NSSwitch!
    private var extAmpProfilePopUp: NSPopUpButton!
    private var extAmpIPField: NSTextField!
    private var extAmpPortField: NSTextField!
    private var extAmpMaxCapField: NSTextField!
    private var extAmpMaxCapStepper: NSStepper!
    private var saveExtAmpButton: NSButton!
    private var testExtAmpConnectionButton: NSButton!
    private var extAmpStatusLabel: NSTextField!

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
    private var clientDevicesStack: NSStackView!
    private var activeDeviceSheetWindow: NSWindow?
    private var activeEditingDeviceId: String?
    private var activeDeviceNameField: NSTextField?
    private var activeDeviceLockSwitch: NSSwitch?

    // UI Elements - UPnP & DLNA
    private var enableLocalDMRSwitch: NSSwitch!
    private var upnpFriendlyNameField: NSTextField!
    private var saveNameButton: NSButton!
    private var upnpUrlField: NSTextField!
    private var copyUpnpButton: NSButton!
    private var upnpStatusLabel: NSTextField!

    // UI Elements - Diagnostic File Logging
    private var enableFileLoggingSwitch: NSSwitch!
    private var openLogFileButton: NSButton!
    private var revealLogFileButton: NSButton!
    private var clearLogFileButton: NSButton!
    private var fileLoggingStatusLabel: NSTextField!

    private var devices: [AudioOutputDevice] = []

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = SettingsTab.general.windowTitle
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        setupUI()
        setupListeners()
        selectTab(.general, animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Music.app-Style Tabbed Settings UI Construction

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let visualEffect = NSVisualEffectView(frame: contentView.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.blendingMode = .withinWindow
        visualEffect.material = .windowBackground
        visualEffect.state = .active
        contentView.addSubview(visualEffect)

        // 1. Top Icon Tab Bar (Music.app style)
        let topBarContainer = NSView()
        topBarContainer.translatesAutoresizingMaskIntoConstraints = false

        let tabBarStack = NSStackView()
        tabBarStack.orientation = .horizontal
        tabBarStack.alignment = .centerY
        tabBarStack.spacing = 6
        tabBarStack.translatesAutoresizingMaskIntoConstraints = false

        for tab in SettingsTab.allCases {
            let btn = MusicTabButtonView(tab: tab)
            btn.onSelect = { [weak self] selected in
                self?.selectTab(selected, animated: true)
            }
            tabButtons[tab] = btn
            tabBarStack.addArrangedSubview(btn)
        }

        let topSeparator = NSBox()
        topSeparator.boxType = .separator
        topSeparator.translatesAutoresizingMaskIntoConstraints = false

        topBarContainer.addSubview(tabBarStack)
        topBarContainer.addSubview(topSeparator)

        NSLayoutConstraint.activate([
            topBarContainer.heightAnchor.constraint(equalToConstant: 68),
            tabBarStack.centerXAnchor.constraint(equalTo: topBarContainer.centerXAnchor),
            tabBarStack.centerYAnchor.constraint(equalTo: topBarContainer.centerYAnchor, constant: -1),
            topSeparator.leadingAnchor.constraint(equalTo: topBarContainer.leadingAnchor, constant: 18),
            topSeparator.trailingAnchor.constraint(equalTo: topBarContainer.trailingAnchor, constant: -18),
            topSeparator.bottomAnchor.constraint(equalTo: topBarContainer.bottomAnchor)
        ])

        // 2. Build the 5 Tab Views
        tabViews[.general] = buildGeneralTabView()
        tabViews[.playback] = buildPlaybackTabView()
        tabViews[.amplifier] = buildAmplifierTabView()
        tabViews[.wled] = buildWLEDTabView()
        tabViews[.advanced] = buildAdvancedTabView()

        tabContentContainer = NSView()
        tabContentContainer.translatesAutoresizingMaskIntoConstraints = false
        tabContainerHeightConstraint = tabContentContainer.heightAnchor.constraint(equalToConstant: 300)
        tabContainerHeightConstraint.isActive = true

        // 3. Bottom Bar (Help "?" button + Version + Pink "ОК" button, like Music.app)
        let bottomBarContainer = NSView()
        bottomBarContainer.translatesAutoresizingMaskIntoConstraints = false

        let bottomSeparator = NSBox()
        bottomSeparator.boxType = .separator
        bottomSeparator.translatesAutoresizingMaskIntoConstraints = false

        let helpButton = NSButton(title: "", target: self, action: #selector(helpButtonClicked))
        helpButton.bezelStyle = .helpButton
        helpButton.translatesAutoresizingMaskIntoConstraints = false

        let versionLabel = NSTextField(labelWithString: "Apple Music Remote v2.5.0 • \(ClientDeviceManager.shared.gitCommitShort)")
        versionLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        let okButton = NSButton(title: "ОК", target: self, action: #selector(okButtonClicked))
        okButton.bezelStyle = .rounded
        okButton.controlSize = .regular
        okButton.keyEquivalent = "\r"
        okButton.bezelColor = .systemPink
        okButton.contentTintColor = .white
        okButton.translatesAutoresizingMaskIntoConstraints = false
        okButton.widthAnchor.constraint(equalToConstant: 76).isActive = true

        bottomBarContainer.addSubview(bottomSeparator)
        bottomBarContainer.addSubview(helpButton)
        bottomBarContainer.addSubview(versionLabel)
        bottomBarContainer.addSubview(okButton)

        NSLayoutConstraint.activate([
            bottomBarContainer.heightAnchor.constraint(equalToConstant: 52),
            bottomSeparator.topAnchor.constraint(equalTo: bottomBarContainer.topAnchor),
            bottomSeparator.leadingAnchor.constraint(equalTo: bottomBarContainer.leadingAnchor, constant: 18),
            bottomSeparator.trailingAnchor.constraint(equalTo: bottomBarContainer.trailingAnchor, constant: -18),
            helpButton.leadingAnchor.constraint(equalTo: bottomBarContainer.leadingAnchor, constant: 18),
            helpButton.centerYAnchor.constraint(equalTo: bottomBarContainer.centerYAnchor, constant: 1),
            versionLabel.leadingAnchor.constraint(equalTo: helpButton.trailingAnchor, constant: 10),
            versionLabel.centerYAnchor.constraint(equalTo: bottomBarContainer.centerYAnchor, constant: 1),
            okButton.trailingAnchor.constraint(equalTo: bottomBarContainer.trailingAnchor, constant: -18),
            okButton.centerYAnchor.constraint(equalTo: bottomBarContainer.centerYAnchor, constant: 1)
        ])

        visualEffect.addSubview(topBarContainer)
        visualEffect.addSubview(tabContentContainer)
        visualEffect.addSubview(bottomBarContainer)

        NSLayoutConstraint.activate([
            topBarContainer.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            topBarContainer.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            topBarContainer.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),

            tabContentContainer.topAnchor.constraint(equalTo: topBarContainer.bottomAnchor),
            tabContentContainer.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            tabContentContainer.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),

            bottomBarContainer.topAnchor.constraint(equalTo: tabContentContainer.bottomAnchor),
            bottomBarContainer.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            bottomBarContainer.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            bottomBarContainer.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor)
        ])
    }

    private func selectTab(_ tab: SettingsTab, animated: Bool) {
        currentTab = tab
        window?.title = tab.windowTitle

        for (t, btn) in tabButtons {
            btn.setSelected(t == tab)
        }

        tabContentContainer.subviews.forEach { $0.removeFromSuperview() }

        guard let targetView = tabViews[tab] else { return }
        targetView.translatesAutoresizingMaskIntoConstraints = false
        tabContentContainer.addSubview(targetView)

        NSLayoutConstraint.activate([
            targetView.topAnchor.constraint(equalTo: tabContentContainer.topAnchor),
            targetView.leadingAnchor.constraint(equalTo: tabContentContainer.leadingAnchor),
            targetView.trailingAnchor.constraint(equalTo: tabContentContainer.trailingAnchor)
        ])

        targetView.layoutSubtreeIfNeeded()
        let fittingHeight = max(targetView.fittingSize.height, 220)
        tabContainerHeightConstraint.constant = fittingHeight

        guard let win = window else { return }
        let topBarHeight: CGFloat = 68
        let bottomBarHeight: CGFloat = 52
        let targetContentHeight = topBarHeight + fittingHeight + bottomBarHeight
        let targetFrameSize = win.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 580, height: targetContentHeight)).size

        var newFrame = win.frame
        newFrame.origin.y += (newFrame.size.height - targetFrameSize.height)
        newFrame.size.width = 580
        newFrame.size.height = targetFrameSize.height

        win.setFrame(newFrame, display: true, animate: animated)
    }

    // MARK: - Individual Tab Builders

    private func makeTabPageStack(views: [NSView]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        for v in views {
            stack.addArrangedSubview(v)
            v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        }
        return stack
    }

    private func buildGeneralTabView() -> NSView {
        let heroCard = buildHeroHeaderCard()

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
        aiCuratorSwitch = makeSwitch(action: #selector(aiCuratorToggled(_:)))
        clientsLabel = makeStatusCaption("Клиентов подключено: 0")

        var mainRows: [NSView] = [
            makeControlRow(title: "Адрес сервера", subtitle: "Откройте в Safari на iPhone, iPad, Mac или Smart TV", control: wsControls),
            makeToggleRow(title: "Запускать при входе в macOS", subtitle: "Автоматический старт фонового сервера в строке меню", toggle: launchAtLoginSwitch)
        ]
        if NativeMusicCuratorService.shared.isAppleSilicon {
            mainRows.append(
                makeToggleRow(
                    title: "Нативные функции ИИ (Apple Neural Engine)",
                    subtitle: "Промпт-Куратор, семантический поток очереди (NLEmbedding) и палитра обложек Vision (ТВ / WLED)",
                    toggle: aiCuratorSwitch
                )
            )
        }
        mainRows.append(makeFooterRow(view: clientsLabel))

        let mainGroup = makeSectionGroup(
            symbol: "gearshape.fill",
            badgeColor: .systemIndigo,
            title: "Основные параметры и Пульт управления (iOS / PWA / StandBy TV)",
            rows: mainRows
        )

        let devicesGroup = buildClientDevicesGroup()

        return makeTabPageStack(views: [heroCard, mainGroup, devicesGroup])
    }

    private func buildClientDevicesGroup() -> NSView {
        let groupStack = NSStackView()
        groupStack.orientation = .vertical
        groupStack.alignment = .leading
        groupStack.spacing = 8
        groupStack.translatesAutoresizingMaskIntoConstraints = false

        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 8
        headerRow.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)

        let iconBox = NSView()
        iconBox.wantsLayer = true
        iconBox.layer?.cornerRadius = 6
        iconBox.layer?.backgroundColor = NSColor.systemPink.cgColor
        iconBox.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconBox.widthAnchor.constraint(equalToConstant: 22),
            iconBox.heightAnchor.constraint(equalToConstant: 22)
        ])

        if let symImg = NSImage(systemSymbolName: "ipad.and.iphone", accessibilityDescription: "Устройства PWA") {
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

        let headerTitle = NSTextField(labelWithString: "Устройства и Авторизация клиентов (PWA)")
        headerTitle.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        headerTitle.textColor = .labelColor

        headerRow.addArrangedSubview(iconBox)
        headerRow.addArrangedSubview(headerTitle)
        groupStack.addArrangedSubview(headerRow)

        let card = SettingsCardView()
        card.translatesAutoresizingMaskIntoConstraints = false

        clientDevicesStack = NSStackView()
        clientDevicesStack.orientation = .vertical
        clientDevicesStack.alignment = .leading
        clientDevicesStack.spacing = 0
        clientDevicesStack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(clientDevicesStack)
        NSLayoutConstraint.activate([
            clientDevicesStack.topAnchor.constraint(equalTo: card.topAnchor),
            clientDevicesStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            clientDevicesStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            clientDevicesStack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])

        groupStack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: groupStack.widthAnchor).isActive = true

        refreshClientDevicesSection(updateWindowSize: false)
        return groupStack
    }

    private func refreshClientDevicesSection(updateWindowSize: Bool = true) {
        guard let stack = clientDevicesStack else { return }
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let allDevices = ClientDeviceManager.shared.getAllDevices()
        if allDevices.isEmpty {
            let emptyLabel = makeStatusCaption("Нет подключенных устройств. Откройте веб-пульт на iPhone, iPad, Mac или ТВ — устройство появится здесь для авторизации.")
            emptyLabel.lineBreakMode = .byWordWrapping
            let emptyRow = makeFooterRow(view: emptyLabel)
            stack.addArrangedSubview(emptyRow)
            emptyRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        } else {
            for (idx, dev) in allDevices.enumerated() {
                let row = makeClientDeviceRow(dev)
                stack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

                if idx < allDevices.count - 1 {
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
                    stack.addArrangedSubview(sepWrap)
                    sepWrap.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                }
            }
        }

        if updateWindowSize && currentTab == .general && (window?.isVisible == true) {
            if let targetView = tabViews[.general] {
                targetView.layoutSubtreeIfNeeded()
                let fittingHeight = max(targetView.fittingSize.height, 220)
                if abs(tabContainerHeightConstraint.constant - fittingHeight) > 1 {
                    tabContainerHeightConstraint.constant = fittingHeight
                    if let win = window {
                        let targetContentHeight: CGFloat = 68 + fittingHeight + 52
                        let targetFrameSize = win.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 580, height: targetContentHeight)).size
                        var newFrame = win.frame
                        newFrame.origin.y += (newFrame.size.height - targetFrameSize.height)
                        newFrame.size.width = 580
                        newFrame.size.height = targetFrameSize.height
                        win.setFrame(newFrame, display: true, animate: true)
                    }
                }
            }
        }
    }

    private func makeClientDeviceRow(_ dev: ClientDeviceRecord) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
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
            let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            iconView.image = img.withSymbolConfiguration(cfg) ?? img
        }
        if !dev.isAuthorized {
            iconView.contentTintColor = .systemOrange
        } else if isOnline {
            iconView.contentTintColor = .systemGreen
        } else {
            iconView.contentTintColor = .secondaryLabelColor
        }
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22)
        ])

        let titleField = NSTextField(labelWithString: "\(dev.deviceName)  •  \(dev.shortId)")
        titleField.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        titleField.textColor = .labelColor

        let ipPart = dev.lastIPAddress.isEmpty ? "" : " • \(dev.lastIPAddress)"
        let statusText: String
        if !dev.isAuthorized {
            statusText = "🟠 Ожидает подтверждения\(ipPart)"
        } else {
            let onlineBadge = isOnline ? "🟢 Онлайн" : "⚪ Офлайн"
            let lockBadge = dev.lockScreenControls ? "Экран блок.: Вкл" : "Экран блок.: Выкл"
            statusText = "\(onlineBadge) • Авторизован • \(lockBadge)\(ipPart)"
        }

        let subField = NSTextField(labelWithString: statusText)
        subField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subField.textColor = !dev.isAuthorized ? .systemOrange : .secondaryLabelColor

        let textStack = NSStackView(views: [titleField, subField])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let controlsStack = NSStackView()
        controlsStack.orientation = .horizontal
        controlsStack.alignment = .centerY
        controlsStack.spacing = 8

        let itemIdentifier = NSUserInterfaceItemIdentifier(dev.deviceId)

        if !dev.isAuthorized {
            let authBtn = NSButton(title: "Авторизовать", target: self, action: #selector(authorizeClientDeviceClicked(_:)))
            authBtn.bezelStyle = .rounded
            authBtn.controlSize = .small
            authBtn.bezelColor = .systemPink
            authBtn.contentTintColor = .white
            authBtn.identifier = itemIdentifier

            let removeBtn = NSButton(title: "✕", target: self, action: #selector(removeClientDeviceClicked(_:)))
            removeBtn.bezelStyle = .rounded
            removeBtn.controlSize = .small
            removeBtn.toolTip = "Отклонить и удалить устройство"
            removeBtn.identifier = itemIdentifier

            controlsStack.addArrangedSubview(authBtn)
            controlsStack.addArrangedSubview(removeBtn)
        } else {
            let settingsBtn = NSButton(title: "Настройки...", target: self, action: #selector(openClientDeviceSettingsClicked(_:)))
            settingsBtn.bezelStyle = .rounded
            settingsBtn.controlSize = .small
            if let gearImg = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Настройки") {
                settingsBtn.image = gearImg
                settingsBtn.imagePosition = .imageLeading
            }
            settingsBtn.toolTip = "Индивидуальные настройки и функции этого устройства"
            settingsBtn.identifier = itemIdentifier

            let removeBtn = NSButton(title: "✕", target: self, action: #selector(removeClientDeviceClicked(_:)))
            removeBtn.bezelStyle = .rounded
            removeBtn.controlSize = .small
            removeBtn.toolTip = "Удалить устройство из списка"
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

    private func buildPlaybackTabView() -> NSView {
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
        dacMutingGuardSwitch = makeSwitch(action: #selector(dacMutingGuardToggled(_:)))

        dacMutingGuardPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        dacMutingGuardPopUp.controlSize = .regular
        dacMutingGuardPopUp.target = self
        dacMutingGuardPopUp.action = #selector(dacMutingGuardDurationChanged(_:))
        dacMutingGuardPopUp.widthAnchor.constraint(equalToConstant: 165).isActive = true
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

        let dacGuardControls = NSStackView(views: [dacMutingGuardPopUp, dacMutingGuardSwitch])
        dacGuardControls.orientation = .horizontal
        dacGuardControls.alignment = .centerY
        dacGuardControls.spacing = 10

        lockVolume100Switch = makeSwitch(action: #selector(lockVolume100Toggled(_:)))
        spectralAnalyzerSwitch = makeSwitch(action: #selector(spectralAnalyzerToggled(_:)))
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
                makeControlRow(title: "Защита реле ЦАП (DAC Muting Guard)", subtitle: "Бесщелчковая микро-пауза тишины при переключении частоты ЦАП", control: dacGuardControls),
                makeToggleRow(title: "Фиксация громкости 100%", subtitle: "Побитовая передача без цифровой аттенюации микшера", toggle: lockVolume100Switch),
                makeToggleRow(title: "Спектральный верификатор (vDSP FFT)", subtitle: "Анализ подлинности Hi-Res / Lossless и детектор апсемплинга", toggle: spectralAnalyzerSwitch),
                makeToggleRow(title: "Обнаружение сетевых стримеров", subtitle: "Искать внешние рендереры DLNA / BluOS (Bluesound, WiiM)", toggle: discoverDLNASwitch),
                makeFooterRow(view: audioFooter)
            ]
        )

        return makeTabPageStack(views: [audioGroup])
    }

    private func buildAmplifierTabView() -> NSView {
        enableExtAmpSwitch = makeSwitch(action: #selector(extAmpEnabledToggled(_:)))
        extAmpSoundCheckSwitch = makeSwitch(action: #selector(extAmpSoundCheckToggled(_:)))
        extAmpLowVolSmartNormSwitch = makeSwitch(action: #selector(extAmpLowVolSmartNormToggled(_:)))

        extAmpProfilePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        extAmpProfilePopUp.controlSize = .regular
        extAmpProfilePopUp.target = self
        extAmpProfilePopUp.action = #selector(extAmpProfileChanged(_:))
        extAmpProfilePopUp.widthAnchor.constraint(equalToConstant: 240).isActive = true
        for prof in ExternalAmpProfile.allCases {
            extAmpProfilePopUp.addItem(withTitle: prof.menuTitle)
            extAmpProfilePopUp.lastItem?.representedObject = prof.rawValue
        }

        extAmpIPField = NSTextField()
        extAmpIPField.placeholderString = "192.168.1.50"
        extAmpIPField.bezelStyle = .roundedBezel
        extAmpIPField.controlSize = .regular
        extAmpIPField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        extAmpIPField.widthAnchor.constraint(equalToConstant: 122).isActive = true
        extAmpIPField.target = self
        extAmpIPField.action = #selector(saveExtAmpSettingsClicked)

        let portCaption = NSTextField(labelWithString: "Порт:")
        portCaption.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        portCaption.textColor = .secondaryLabelColor

        extAmpPortField = NSTextField()
        extAmpPortField.placeholderString = "9590"
        extAmpPortField.bezelStyle = .roundedBezel
        extAmpPortField.controlSize = .regular
        extAmpPortField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        extAmpPortField.alignment = .center
        extAmpPortField.widthAnchor.constraint(equalToConstant: 58).isActive = true
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

        let percentSuffixLabel = NSTextField(labelWithString: "% (диапазон слайдера 0% — Макс)")
        percentSuffixLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        percentSuffixLabel.textColor = .secondaryLabelColor

        let extAmpMaxCapStack = NSStackView(views: [
            extAmpMaxCapField,
            extAmpMaxCapStepper,
            percentSuffixLabel
        ])
        extAmpMaxCapStack.orientation = .horizontal
        extAmpMaxCapStack.alignment = .centerY
        extAmpMaxCapStack.spacing = 6

        saveExtAmpButton = NSButton(title: "Применить", target: self, action: #selector(saveExtAmpSettingsClicked))
        saveExtAmpButton.bezelStyle = .rounded
        saveExtAmpButton.controlSize = .regular

        testExtAmpConnectionButton = NSButton(title: "Проверить соединение", target: self, action: #selector(testExtAmpConnectionClicked))
        testExtAmpConnectionButton.bezelStyle = .rounded
        testExtAmpConnectionButton.controlSize = .regular

        let extAmpNetStack = NSStackView(views: [
            extAmpIPField,
            portCaption,
            extAmpPortField,
            saveExtAmpButton
        ])
        extAmpNetStack.orientation = .horizontal
        extAmpNetStack.alignment = .centerY
        extAmpNetStack.spacing = 6

        extAmpStatusLabel = makeStatusCaption("Статус: Управление громкостью внешнего усилителя отключено")

        let extAmpGroup = makeSectionGroup(
            symbol: "dial.medium.fill",
            badgeColor: .systemIndigo,
            title: "Управление громкостью усилителя (Text TCP Socket)",
            rows: [
                makeToggleRow(
                    title: "Управление громкостью усилителя",
                    subtitle: "Доступно только при фиксации громкости 100% (постоянный сокет + опрос статуса)",
                    toggle: enableExtAmpSwitch
                ),
                makeToggleRow(
                    title: "Нормализация громкости треков (Apple SoundCheck)",
                    subtitle: "Выравнивание громкости через усилитель по метаданным iTunNORM без потерь Bit-Perfect",
                    toggle: extAmpSoundCheckSwitch
                ),
                makeToggleRow(
                    title: "Умная нормализация на низкой громкости",
                    subtitle: "Адаптация шага dB под нелинейную кривую аттенюатора (Rotel и др.) и слуха на малой громкости (< 40%)",
                    toggle: extAmpLowVolSmartNormSwitch
                ),
                makeControlRow(
                    title: "Марка / протокол усилителя",
                    subtitle: "ASCII-команды громкости и парсинг обратной связи с пульта/энкодера",
                    control: extAmpProfilePopUp
                ),
                makeControlRow(
                    title: "Максимальная громкость (%)",
                    subtitle: "Слайдер громкости AMR оперирует в пределах 0% — заданная максимальная громкость",
                    control: extAmpMaxCapStack
                ),
                makeControlRow(
                    title: "Сетевой адрес усилителя (TCP)",
                    subtitle: "IP-адрес и TCP-порт усилителя в локальной сети",
                    control: extAmpNetStack
                ),
                makeControlRow(
                    title: "Диагностика сокета",
                    subtitle: "Отправить тестовый запрос текущей громкости и проверить отклик усилителя",
                    control: testExtAmpConnectionButton
                ),
                makeFooterRow(view: extAmpStatusLabel)
            ]
        )

        return makeTabPageStack(views: [extAmpGroup])
    }

    private func buildWLEDTabView() -> NSView {
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
                makeToggleRow(title: "Включить WLED DDP подсветку", subtitle: "Реалтайм 40 FPS спектр обложки по UDP (порт 4048)", toggle: enableWLEDSwitch),
                makeControlRow(title: "Контроллер WLED", subtitle: "IP-адрес и число светодиодов (авто по /json/info)", control: wledAddressControls),
                makeControlRow(title: "Режим свечения", subtitle: "Алгоритм пространственной заливки адресной ленты", control: wledModePopUp),
                makeFooterRow(view: wledStatusLabel)
            ]
        )

        return makeTabPageStack(views: [wledGroup])
    }

    private func buildAdvancedTabView() -> NSView {
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

        // Diagnostic File Logging Group
        enableFileLoggingSwitch = makeSwitch(action: #selector(fileLoggingToggled(_:)))

        openLogFileButton = NSButton(title: "Открыть лог", target: self, action: #selector(openLogFileClicked))
        openLogFileButton.bezelStyle = .rounded

        revealLogFileButton = NSButton(title: "Показать в Finder", target: self, action: #selector(revealLogFileClicked))
        revealLogFileButton.bezelStyle = .rounded

        clearLogFileButton = NSButton(title: "Очистить", target: self, action: #selector(clearLogFileClicked))
        clearLogFileButton.bezelStyle = .rounded

        let logActionsStack = NSStackView(views: [openLogFileButton, revealLogFileButton, clearLogFileButton])
        logActionsStack.orientation = .horizontal
        logActionsStack.alignment = .centerY
        logActionsStack.spacing = 6

        fileLoggingStatusLabel = makeStatusCaption("Статус: Журналирование в файл отключено")

        let loggingGroup = makeSectionGroup(
            symbol: "doc.text.magnifyingglass",
            badgeColor: .systemTeal,
            title: "Диагностика и Журналирование (Debug Log)",
            rows: [
                makeToggleRow(
                    title: "Вести журнал отладки в файл",
                    subtitle: "Запись всех событий сервера, очереди, CoreAudio и клиентов в ~/Library/Logs/AppleMusicRemoteMac/amr.log",
                    toggle: enableFileLoggingSwitch
                ),
                makeControlRow(
                    title: "Управление файлом журнала",
                    subtitle: "Автоматическая ротация при достижении 5 МБ (amr.old.log)",
                    control: logActionsStack
                ),
                makeFooterRow(view: fileLoggingStatusLabel)
            ]
        )

        return makeTabPageStack(views: [upnpGroup, loggingGroup])
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
        selectTab(currentTab, animated: false)
        if !(window?.isVisible ?? false) {
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func refreshState() {
        // 0. System & Autonomy
        LaunchAtLoginManager.shared.refreshStatus()
        launchAtLoginSwitch.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
        aiCuratorSwitch?.state = NativeMusicCuratorService.shared.isEnabled ? .on : .off
        aiCuratorSwitch?.isHidden = !NativeMusicCuratorService.shared.isAppleSilicon
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
        let guardEnabled = CoreAudioDeviceManager.shared.isMutingGuardEnabled
        let guardMs = CoreAudioDeviceManager.shared.mutingGuardDurationMs
        dacMutingGuardSwitch.state = guardEnabled ? .on : .off
        dacMutingGuardPopUp.isEnabled = guardEnabled
        if dacMutingGuardPopUp.indexOfItem(withTag: guardMs) != -1 {
            dacMutingGuardPopUp.selectItem(withTag: guardMs)
        } else {
            dacMutingGuardPopUp.selectItem(withTag: 100)
        }
        let isVolLocked = PlaybackStateStore.shared.isVolumeLockedTo100
        lockVolume100Switch.state = isVolLocked ? .on : .off
        spectralAnalyzerSwitch.state = SpectralIntegrityAnalyzer.shared.isEnabled ? .on : .off
        discoverDLNASwitch.state = DLNADiscoveryManager.shared.isEnabled ? .on : .off
        updateDLNAStatusLabel()

        // 1b. External Amplifier TCP Volume Control (only available when Volume Lock 100% is ON)
        let ampCtrl = ExternalAmpTCPController.shared
        let ampEnabled = isVolLocked && ampCtrl.isEnabled
        let soundCheckEnabled = ampEnabled && ampCtrl.isSoundCheckEnabled
        enableExtAmpSwitch.isEnabled = isVolLocked
        enableExtAmpSwitch.state = ampEnabled ? .on : .off
        extAmpSoundCheckSwitch.isEnabled = ampEnabled
        extAmpSoundCheckSwitch.state = soundCheckEnabled ? .on : .off
        extAmpLowVolSmartNormSwitch.isEnabled = soundCheckEnabled
        extAmpLowVolSmartNormSwitch.state = (soundCheckEnabled && ampCtrl.isLowVolumeSmartNormEnabled) ? .on : .off
        if let item = extAmpProfilePopUp.itemArray.first(where: { ($0.representedObject as? String) == ampCtrl.profile.rawValue }) {
            extAmpProfilePopUp.select(item)
        }
        extAmpIPField.stringValue = ampCtrl.host
        extAmpPortField.stringValue = "\(ampCtrl.port)"
        extAmpMaxCapField.stringValue = "\(ampCtrl.maxVolumeCap)"
        extAmpMaxCapStepper.integerValue = ampCtrl.maxVolumeCap
        extAmpProfilePopUp.isEnabled = ampEnabled
        extAmpIPField.isEnabled = ampEnabled
        extAmpPortField.isEnabled = ampEnabled
        extAmpMaxCapField.isEnabled = ampEnabled
        extAmpMaxCapStepper.isEnabled = ampEnabled
        saveExtAmpButton.isEnabled = ampEnabled
        testExtAmpConnectionButton.isEnabled = ampEnabled
        refreshAmpStatusLabel()

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

        // 2b. Diagnostic File Logging
        let isLogging = DiagnosticLogger.shared.isEnabled
        enableFileLoggingSwitch.state = isLogging ? .on : .off
        let logSizeStr = DiagnosticLogger.shared.logFileSizeDescription()
        if isLogging {
            fileLoggingStatusLabel.stringValue = "🟢 Активно • Размер: \(logSizeStr) • ~/Library/Logs/AppleMusicRemoteMac/amr.log"
            fileLoggingStatusLabel.textColor = .systemGreen
        } else {
            fileLoggingStatusLabel.stringValue = "Статус: Журналирование в файл отключено (размер лога: \(logSizeStr))"
            fileLoggingStatusLabel.textColor = .secondaryLabelColor
        }

        // 3. Web UI & WebSocket Server
        let wsPort = WebSocketServer.shared.port
        wsUrlField.stringValue = "http://\(primaryIP):\(wsPort)"
        let clientCount = WebSocketServer.shared.clientCount
        let pendingCount = ClientDeviceManager.shared.pendingCount
        if pendingCount > 0 {
            clientsLabel.stringValue = "🟠 Активных подключений: \(clientCount) • Ожидают авторизации: \(pendingCount)"
            clientsLabel.textColor = .systemOrange
        } else {
            clientsLabel.stringValue = "🟢 Активных подключений по WebSocket: \(clientCount)"
            clientsLabel.textColor = .secondaryLabelColor
        }
        refreshClientDevicesSection(updateWindowSize: true)
        if let editingId = activeEditingDeviceId,
           let dev = ClientDeviceManager.shared.getDevice(deviceId: editingId) {
            activeDeviceLockSwitch?.state = dev.lockScreenControls ? .on : .off
        }

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

    @objc private func okButtonClicked() {
        window?.makeFirstResponder(nil)
        window?.close()
    }

    @objc private func helpButtonClicked() {
        var url = wsUrlField.stringValue
        if url.hasPrefix("ws://") {
            url = "http://" + url.dropFirst(5)
        }
        if let nsUrl = URL(string: url) {
            NSWorkspace.shared.open(nsUrl)
        }
    }

    @objc private func launchAtLoginToggled(_ sender: NSSwitch) {
        let enable = (sender.state == .on)
        let success = LaunchAtLoginManager.shared.setEnabled(enable)
        if !success {
            sender.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
        }
        MenuManager.shared.updateMenuState()
    }

    @objc private func aiCuratorToggled(_ sender: NSSwitch) {
        let enable = (sender.state == .on)
        NativeMusicCuratorService.shared.isEnabled = enable
        WebSocketServer.shared.broadcastEvent(
            name: "ai_curator_settings",
            data: NativeMusicCuratorService.shared.getSettingsDictionary()
        )
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

    @objc private func dacMutingGuardToggled(_ sender: NSSwitch) {
        let enabled = (sender.state == .on)
        CoreAudioDeviceManager.shared.isMutingGuardEnabled = enabled
        dacMutingGuardPopUp.isEnabled = enabled
        PlaybackStateStore.shared.invalidateStatusCache()
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
    }

    @objc private func dacMutingGuardDurationChanged(_ sender: NSPopUpButton) {
        let ms = sender.selectedTag()
        if ms >= 30 && ms <= 500 {
            CoreAudioDeviceManager.shared.mutingGuardDurationMs = ms
            PlaybackStateStore.shared.invalidateStatusCache()
            WebSocketServer.shared.broadcastStatus(includeQueue: false)
        }
    }

    @objc private func lockVolume100Toggled(_ sender: NSSwitch) {
        let enabled = (sender.state == .on)
        PlaybackStateStore.shared.isVolumeLockedTo100 = enabled
        if enabled {
            PlaybackTransportController.shared.checkAndEnforceVolumeLock()
        }
        refreshState()
        PlaybackStateStore.shared.invalidateStatusCache()
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
    }

    @objc private func extAmpEnabledToggled(_ sender: NSSwitch) {
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

    @objc private func extAmpProfileChanged(_ sender: NSPopUpButton) {
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

    @objc private func extAmpMaxCapStepperChanged(_ sender: NSStepper) {
        let clamped = max(1, min(100, sender.integerValue))
        extAmpMaxCapField.stringValue = "\(clamped)"
        ExternalAmpTCPController.shared.maxVolumeCap = clamped
        refreshState()
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
    }

    @objc private func saveExtAmpSettingsClicked() {
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

    @objc private func testExtAmpConnectionClicked() {
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
            extAmpStatusLabel.stringValue = "🟠 Укажите IP-адрес усилителя для проверки соединения"
            extAmpStatusLabel.textColor = .systemOrange
            return
        }
        testExtAmpConnectionButton.isEnabled = false
        testExtAmpConnectionButton.title = "Проверка..."
        extAmpStatusLabel.stringValue = "⏳ Проверка TCP-соединения с \(selectedProf.displayName) (\(host):\(parsedPort))..."
        extAmpStatusLabel.textColor = .secondaryLabelColor

        ExternalAmpTCPController.shared.testConnection(
            profile: selectedProf,
            host: host,
            port: parsedPort
        ) { [weak self] success, message in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.testExtAmpConnectionButton.title = "Проверить соединение"
                self.testExtAmpConnectionButton.isEnabled = PlaybackStateStore.shared.isVolumeLockedTo100 && ExternalAmpTCPController.shared.isEnabled
                self.extAmpStatusLabel.stringValue = message
                self.extAmpStatusLabel.textColor = success ? .systemGreen : .systemRed
                WebSocketServer.shared.broadcastStatus(includeQueue: false)
            }
        }
    }

    @objc private func extAmpSoundCheckToggled(_ sender: NSSwitch) {
        guard PlaybackStateStore.shared.isVolumeLockedTo100 && ExternalAmpTCPController.shared.isEnabled else {
            sender.state = .off
            ExternalAmpTCPController.shared.isSoundCheckEnabled = false
            refreshState()
            return
        }
        let enabled = (sender.state == .on)
        ExternalAmpTCPController.shared.isSoundCheckEnabled = enabled
        refreshState()
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
    }

    @objc private func extAmpLowVolSmartNormToggled(_ sender: NSSwitch) {
        guard PlaybackStateStore.shared.isVolumeLockedTo100 && ExternalAmpTCPController.shared.isEnabled && ExternalAmpTCPController.shared.isSoundCheckEnabled else {
            sender.state = .off
            refreshState()
            return
        }
        let enabled = (sender.state == .on)
        ExternalAmpTCPController.shared.isLowVolumeSmartNormEnabled = enabled
        refreshState()
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
    }

    public func refreshAmpStatusLabel() {
        guard extAmpStatusLabel != nil else { return }
        let isVolLocked = PlaybackStateStore.shared.isVolumeLockedTo100
        let ampCtrl = ExternalAmpTCPController.shared
        if !isVolLocked {
            extAmpStatusLabel.stringValue = "⚪ Недоступно: включите «Фиксация громкости 100%» для управления громкостью усилителя"
            extAmpStatusLabel.textColor = .secondaryLabelColor
            return
        }
        if !ampCtrl.isEnabled {
            extAmpStatusLabel.stringValue = "Статус: Управление громкостью внешнего усилителя отключено"
            extAmpStatusLabel.textColor = .secondaryLabelColor
            return
        }
        if ampCtrl.host.isEmpty {
            extAmpStatusLabel.stringValue = "🟠 Укажите IP-адрес усилителя (\(ampCtrl.profile.displayName)) и нажмите «Применить»"
            extAmpStatusLabel.textColor = .systemOrange
            return
        }
        var soundCheckSuffix = ""
        if ampCtrl.isSoundCheckEnabled {
            if let gainDb = ampCtrl.currentTrackGainDb {
                let offset = ampCtrl.currentTrackVolumeOffset
                let offsetStr = offset >= 0 ? "+\(offset)%" : "\(offset)%"
                let smartTag = (ampCtrl.isLowVolumeSmartNormEnabled && ampCtrl.baseListeningVolume > 0 && ampCtrl.baseListeningVolume < 40) ? " [Smart Low-Vol]" : ""
                soundCheckSuffix = String(format: " • SoundCheck%@: %+.1f дБ (%@, база %d%%)", smartTag, gainDb, offsetStr, ampCtrl.baseListeningVolume)
            } else {
                soundCheckSuffix = " • SoundCheck: ожидание трека"
            }
        }
        if ampCtrl.isConnected {
            let muteBadge = ampCtrl.isMuted ? " • MUTE" : ""
            extAmpStatusLabel.stringValue = "🟢 Подключен: \(ampCtrl.profile.displayName) (\(ampCtrl.host):\(ampCtrl.port)) • Громкость: \(ampCtrl.currentVolume)% / макс. \(ampCtrl.maxVolumeCap)%\(muteBadge)\(soundCheckSuffix)"
            extAmpStatusLabel.textColor = .systemGreen
        } else if let err = ampCtrl.lastError, !err.isEmpty {
            extAmpStatusLabel.stringValue = "🟠 Ожидание сокета \(ampCtrl.profile.displayName) (\(ampCtrl.host):\(ampCtrl.port)): \(err)\(soundCheckSuffix)"
            extAmpStatusLabel.textColor = .systemOrange
        } else {
            extAmpStatusLabel.stringValue = "🟠 Подключение к \(ampCtrl.profile.displayName) (\(ampCtrl.host):\(ampCtrl.port))...\(soundCheckSuffix)"
            extAmpStatusLabel.textColor = .systemOrange
        }
    }

    @objc private func spectralAnalyzerToggled(_ sender: NSSwitch) {
        let enabled = (sender.state == .on)
        SpectralIntegrityAnalyzer.shared.isEnabled = enabled
        PlaybackStateStore.shared.invalidateStatusCache()
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

    @objc private func fileLoggingToggled(_ sender: NSSwitch) {
        DiagnosticLogger.shared.isEnabled = (sender.state == .on)
        refreshState()
    }

    @objc private func openLogFileClicked() {
        DiagnosticLogger.shared.openLogFile()
        refreshState()
    }

    @objc private func revealLogFileClicked() {
        DiagnosticLogger.shared.revealInFinder()
        refreshState()
    }

    @objc private func clearLogFileClicked() {
        DiagnosticLogger.shared.clearLog()
        refreshState()
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

    @objc private func authorizeClientDeviceClicked(_ sender: NSButton) {
        guard let deviceId = sender.identifier?.rawValue else { return }
        ClientDeviceManager.shared.setAuthorized(deviceId: deviceId, authorized: true)
        refreshState()
    }

    @objc private func revokeClientDeviceClicked(_ sender: NSButton) {
        guard let deviceId = sender.identifier?.rawValue else { return }
        ClientDeviceManager.shared.setAuthorized(deviceId: deviceId, authorized: false)
        closeClientDeviceSettingsSheet()
        refreshState()
    }

    @objc private func removeClientDeviceClicked(_ sender: NSButton) {
        guard let deviceId = sender.identifier?.rawValue else { return }
        if activeEditingDeviceId == deviceId {
            closeClientDeviceSettingsSheet()
        }
        ClientDeviceManager.shared.removeDevice(deviceId: deviceId)
        refreshState()
    }

    @objc private func clientLockScreenSwitchToggled(_ sender: NSSwitch) {
        guard let deviceId = sender.identifier?.rawValue else { return }
        let enabled = (sender.state == .on)
        ClientDeviceManager.shared.setLockScreenControls(deviceId: deviceId, enabled: enabled)
        refreshState()
    }

    @objc private func openClientDeviceSettingsClicked(_ sender: NSButton) {
        guard let deviceId = sender.identifier?.rawValue,
              let dev = ClientDeviceManager.shared.getDevice(deviceId: deviceId),
              let parentWin = self.window else { return }

        closeClientDeviceSettingsSheet()
        activeEditingDeviceId = dev.deviceId

        let sheetWin = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 295),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheetWin.isReleasedWhenClosed = false

        let rootView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 470, height: 295))
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

        // Header Row
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
        badge.layer?.backgroundColor = NSColor.systemPink.cgColor
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
        let titleLabel = NSTextField(labelWithString: "Настройки устройства: \(dev.deviceName)")
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = .labelColor

        let ipPart = dev.lastIPAddress.isEmpty ? "LAN" : dev.lastIPAddress
        let subLabel = NSTextField(labelWithString: "\(isOnline ? "🟢 Онлайн" : "⚪ Офлайн") • Код: \(dev.shortId) • IP: \(ipPart)")
        subLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        subLabel.textColor = .secondaryLabelColor

        let headerTextStack = NSStackView(views: [titleLabel, subLabel])
        headerTextStack.orientation = .vertical
        headerTextStack.alignment = .leading
        headerTextStack.spacing = 2

        headerRow.addArrangedSubview(badge)
        headerRow.addArrangedSubview(headerTextStack)

        // Settings Card
        let itemIdentifier = NSUserInterfaceItemIdentifier(dev.deviceId)

        let nameField = NSTextField(string: dev.deviceName)
        nameField.bezelStyle = .roundedBezel
        nameField.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        nameField.widthAnchor.constraint(equalToConstant: 195).isActive = true
        self.activeDeviceNameField = nameField

        let lockSwitch = NSSwitch()
        lockSwitch.controlSize = .regular
        lockSwitch.state = dev.lockScreenControls ? .on : .off
        lockSwitch.target = self
        lockSwitch.action = #selector(clientLockScreenSwitchToggled(_:))
        lockSwitch.identifier = itemIdentifier
        self.activeDeviceLockSwitch = lockSwitch

        let revokeBtn = NSButton(title: "Отозвать доступ", target: self, action: #selector(revokeClientDeviceClicked(_:)))
        revokeBtn.bezelStyle = .rounded
        revokeBtn.controlSize = .small
        revokeBtn.identifier = itemIdentifier

        let rows: [NSView] = [
            makeControlRow(title: "Имя устройства", subtitle: "Отображаемое имя в списке клиентов и в PWA", control: nameField),
            makeToggleRow(title: "Экран блокировки и Dynamic Island", subtitle: "Управление воспроизведением на заблокированном экране и в Пункте управления", toggle: lockSwitch),
            makeControlRow(title: "Авторизация устройства", subtitle: "UID: \(dev.deviceId)", control: revokeBtn)
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

        // Footer with Done button
        let footerRow = NSStackView()
        footerRow.orientation = .horizontal
        footerRow.alignment = .centerY
        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let doneBtn = NSButton(title: "Готово", target: self, action: #selector(saveAndCloseDeviceSettingsSheet))
        doneBtn.bezelStyle = .rounded
        doneBtn.keyEquivalent = "\r"
        doneBtn.bezelColor = .systemPink
        doneBtn.contentTintColor = .white
        doneBtn.widthAnchor.constraint(equalToConstant: 88).isActive = true

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
            mainStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])

        self.activeDeviceSheetWindow = sheetWin
        parentWin.beginSheet(sheetWin, completionHandler: nil)
    }

    @objc private func saveAndCloseDeviceSettingsSheet() {
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

    private func closeClientDeviceSettingsSheet() {
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
    }
}
