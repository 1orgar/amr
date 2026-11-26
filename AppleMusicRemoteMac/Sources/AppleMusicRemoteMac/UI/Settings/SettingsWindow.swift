//
//  SettingsWindow.swift
//  AppleMusicRemoteMac
//
//  Pure Swift & AppKit Native Settings Window controller: lazy singleton access,
//  visibility-gated @MainActor refreshes, transactional Cancel/OK handling,
//  sheet alerts, multi-observer Music.app hooks, and Music.app row builders.
//

import AppKit
import CoreAudio

@MainActor
public final class SettingsWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private static var _shared: SettingsWindow?

    public static var shared: SettingsWindow {
        if let existing = _shared {
            return existing
        }
        let created = SettingsWindow()
        _shared = created
        return created
    }

    /// Updates UI controls ONLY if the Settings window has already been created and is currently visible.
    public static func refreshIfVisible() {
        guard let instance = _shared else { return }
        if instance.window?.isVisible == true {
            instance.performRefreshState()
        } else {
            instance.needsRefreshOnShow = true
        }
    }

    public static func refreshAmpStatusIfVisible() {
        guard let instance = _shared, instance.window?.isVisible == true else { return }
        instance.refreshAmpStatusLabel()
    }

    public static func refreshCloudSyncStatusIfVisible() {
        guard let instance = _shared, instance.window?.isVisible == true else { return }
        instance.refreshCloudSyncStatusLabel()
    }

    internal static let standardWindowWidth: CGFloat = 700
    internal static let leftLabelColumnWidth: CGFloat = 164
    internal var isEn: Bool { SettingsTab.isEn }

    internal var needsRefreshOnShow: Bool = true
    internal var sessionSnapshot: PreferencesSnapshot?
    internal var cloudStatusRequestGeneration: UInt64 = 0
    internal var logSizeRequestGeneration: UInt64 = 0

    // Tabs state
    internal var currentTab: SettingsTab = .general
    internal var tabButtons: [SettingsTab: MusicTabButtonView] = [:]
    internal var tabViews: [SettingsTab: NSView] = [:]
    internal var tabContentContainer: NSView!
    internal var tabContainerHeightConstraint: NSLayoutConstraint!

    // UI Elements - System & Autonomy
    internal var launchAtLoginSwitch: NSButton!
    internal var aiCuratorSwitch: NSButton!
    internal var musicAppStatusLabel: NSTextField!
    internal var launchMusicButton: NSButton!
    internal var permissionsStatusLabel: NSTextField!
    internal var checkPermissionsButton: NSButton!

    // UI Elements - Audio
    internal var devicePopUp: NSPopUpButton!
    internal var sampleRatePopUp: NSPopUpButton!
    internal var bitPerfectSwitch: NSButton!
    internal var dacMutingGuardSwitch: NSButton!
    internal var dacMutingGuardPopUp: NSPopUpButton!
    internal var lockVolume100Switch: NSButton!
    internal var spectralAnalyzerSwitch: NSButton!
    internal var streamQualityLabel: NSTextField!
    internal var discoverDLNASwitch: NSButton!
    internal var dlnaStatusLabel: NSTextField!

    // UI Elements - Hybrid DSP Engine + Room Acoustic Auto-PEQ
    internal var dspPresetPopUp: NSPopUpButton!
    internal var dspSaveNewPresetButton: NSButton!
    internal var dspUpdatePresetButton: NSButton!
    internal var dspRenamePresetButton: NSButton!
    internal var dspDeletePresetButton: NSButton!
    internal var dspPresetSubtitleLabel: NSTextField!
    internal var dspRoomProfilePopUp: NSPopUpButton!
    internal var dspRoomCorrectionSwitch: NSButton!
    internal var dspRoomInspectButton: NSButton!
    internal var dspRoomRenameButton: NSButton!
    internal var dspRoomDeleteButton: NSButton!
    internal var dspRoomStatusLabel: NSTextField!
    internal var activeRoomInspectorSheetWindow: NSWindow?
    internal var dspModePopUp: NSPopUpButton!
    internal var dspRatePopUp: NSPopUpButton!
    internal var dspProfilePopUp: NSPopUpButton!
    internal var dspTrellisPopUp: NSPopUpButton!
    internal var dspOversamplerPopUp: NSPopUpButton!
    internal var dspClockPolicyPopUp: NSPopUpButton!
    internal var dspHeadroomPopUp: NSPopUpButton!
    internal var dspNosDitherPopUp: NSPopUpButton!
    internal var dspDeClipPopUp: NSPopUpButton!
    internal var dspDeEsserPopUp: NSPopUpButton!
    internal var dspLateNightPopUp: NSPopUpButton!
    internal var dspIsiSwitch: NSButton!
    internal var dspIspSwitch: NSButton!
    internal var dspHogSwitch: NSButton!
    internal var dspStatusLabel: NSTextField!

    // UI Elements - External Amplifier TCP Volume Control
    internal var enableExtAmpSwitch: NSButton!
    internal var extAmpSoundCheckSwitch: NSButton!
    internal var extAmpLowVolSmartNormSwitch: NSButton!
    internal var extAmpCompressionCompSwitch: NSButton!
    internal var extAmpProfilePopUp: NSPopUpButton!
    internal var extAmpIPField: NSTextField!
    internal var extAmpPortField: NSTextField!
    internal var extAmpMaxCapField: NSTextField!
    internal var extAmpMaxCapStepper: NSStepper!
    internal var saveExtAmpButton: NSButton!
    internal var testExtAmpConnectionButton: NSButton!
    internal var extAmpStatusLabel: NSTextField!

    // UI Elements - WLED DDP Ambilight
    internal var enableWLEDSwitch: NSButton!
    internal var wledIPField: NSTextField!
    internal var wledLedCountField: NSTextField!
    internal var saveWLEDIPButton: NSButton!
    internal var wledModePopUp: NSPopUpButton!
    internal var wledStatusLabel: NSTextField!

    // UI Elements - WebSocket / Client Devices
    internal var wsUrlField: NSTextField!
    internal var clientsLabel: NSTextField!
    internal var clientDevicesStack: NSStackView!
    internal var activeDeviceSheetWindow: NSWindow?
    internal var activeEditingDeviceId: String?
    internal var activeDeviceNameField: NSTextField?
    internal var activeDeviceLockSwitch: NSButton?
    internal var activeDeviceAllowDACSwitch: NSButton?
    internal var activeDeviceAllowDSPSwitch: NSButton?
    internal var activeDeviceAllowRoomSwitch: NSButton?
    internal var activeDeviceAllowLateNightSwitch: NSButton?
    internal var activeDeviceAllowLibrarySwitch: NSButton?

    // UI Elements - StandBy TV Mode Library Tiles (Virtualized NSTableView)
    internal enum TVPickerKind {
        case playlists
        case albums
    }

    internal struct TVPlaylistPickerEntry: Sendable {
        let name: String
        let trackCount: Int?
    }

    internal struct TVAlbumPickerEntry: Sendable {
        let key: String
        let id: String
        let name: String
        let artist: String
    }

    internal var tvMyStationCheckbox: NSButton!
    internal var tvDiscoveryStationCheckbox: NSButton!
    internal var tvFavoritesMixCheckbox: NSButton!
    internal var tvHeavyRotationCheckbox: NSButton!
    internal var tvPlaylistsModePopUp: NSPopUpButton!
    internal var tvChoosePlaylistsButton: NSButton!
    internal var tvAlbumsModePopUp: NSPopUpButton!
    internal var tvChooseAlbumsButton: NSButton!
    internal var tvConfigStatusLabel: NSTextField!
    internal var activeTVPickerSheetWindow: NSWindow?
    internal var activeTVPickerKind: TVPickerKind = .playlists
    internal var tvPickerLoadGeneration: UInt64 = 0
    internal var tvPickerIsLoading: Bool = false
    internal var tvPickerSearchField: NSSearchField?
    internal var tvPickerTableView: NSTableView?
    internal var tvPickerEmptyOverlayLabel: NSTextField?
    internal var tvPickerFilteredIndices: [Int] = []
    internal var tvPickerSearchDebounceWorkItem: DispatchWorkItem?
    internal var tvPickerSummaryLabel: NSTextField?
    internal var tvPickerDoneButton: NSButton?
    internal var tvPickerSelectAllButton: NSButton?
    internal var tvPickerDeselectAllButton: NSButton?
    internal var tvPickerPlaylistEntries: [TVPlaylistPickerEntry] = []
    internal var tvPickerAlbumEntries: [TVAlbumPickerEntry] = []
    internal var tvPickerSelectedKeys: Set<String> = []

    // UI Elements - UPnP & DLNA DMR
    internal var enableLocalDMRSwitch: NSButton!
    internal var upnpFriendlyNameField: NSTextField!
    internal var saveNameButton: NSButton!
    internal var upnpUrlField: NSTextField!
    internal var copyUpnpButton: NSButton!
    internal var upnpStatusLabel: NSTextField!

    // UI Elements - Diagnostic File Logging
    internal var enableFileLoggingSwitch: NSButton!
    internal var openLogFileButton: NSButton!
    internal var revealLogFileButton: NSButton!
    internal var clearLogFileButton: NSButton!
    internal var fileLoggingStatusLabel: NSTextField!

    // UI Elements - Cloud Sync (iCloud Drive / Custom Folder)
    internal var dspCloudSyncButton: NSButton!
    internal var enableCloudSyncSwitch: NSButton!
    internal var cloudSyncFolderField: NSTextField!
    internal var chooseCloudFolderButton: NSButton!
    internal var resetCloudICloudButton: NSButton!
    internal var revealCloudFolderButton: NSButton!
    internal var syncCloudNowButton: NSButton!
    internal var exportCloudSnapshotButton: NSButton!
    internal var importCloudSnapshotButton: NSButton!
    internal var cloudSyncStatusLabel: NSTextField!

    internal var devices: [AudioOutputDevice] = []

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.standardWindowWidth, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = SettingsTab.general.windowTitle
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.backgroundColor = MusicSettingsPalette.windowBackground
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

        let rootSurface = MusicSurfaceView { MusicSettingsPalette.windowBackground }
        rootSurface.frame = contentView.bounds
        rootSurface.autoresizingMask = [.width, .height]
        contentView.addSubview(rootSurface)

        let topBarContainer = MusicSurfaceView { MusicSettingsPalette.tabBarBackground }
        topBarContainer.translatesAutoresizingMaskIntoConstraints = false

        let tabBarStack = NSStackView()
        tabBarStack.orientation = .horizontal
        tabBarStack.alignment = .centerY
        tabBarStack.spacing = 4
        tabBarStack.translatesAutoresizingMaskIntoConstraints = false

        for tab in SettingsTab.allCases {
            let btn = MusicTabButtonView(tab: tab)
            btn.onSelect = { [weak self] selected in
                self?.selectTab(selected, animated: true)
            }
            tabButtons[tab] = btn
            tabBarStack.addArrangedSubview(btn)
        }

        let topSeparator = MusicSurfaceView { MusicSettingsPalette.hairline }
        topSeparator.translatesAutoresizingMaskIntoConstraints = false

        topBarContainer.addSubview(tabBarStack)
        topBarContainer.addSubview(topSeparator)

        NSLayoutConstraint.activate([
            topBarContainer.heightAnchor.constraint(equalToConstant: 66),
            tabBarStack.centerXAnchor.constraint(equalTo: topBarContainer.centerXAnchor),
            tabBarStack.centerYAnchor.constraint(equalTo: topBarContainer.centerYAnchor, constant: -1),
            topSeparator.leadingAnchor.constraint(equalTo: topBarContainer.leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: topBarContainer.trailingAnchor),
            topSeparator.bottomAnchor.constraint(equalTo: topBarContainer.bottomAnchor),
            topSeparator.heightAnchor.constraint(equalToConstant: 1)
        ])

        tabViews[.general] = buildGeneralTabView()
        tabViews[.tv] = buildTVTabView()
        tabViews[.playback] = buildPlaybackTabView()
        tabViews[.dsp] = buildDSPTabView()
        tabViews[.amplifier] = buildAmplifierTabView()
        tabViews[.wled] = buildWLEDTabView()
        tabViews[.advanced] = buildAdvancedTabView()

        tabContentContainer = NSView()
        tabContentContainer.wantsLayer = true
        tabContentContainer.layer?.masksToBounds = true
        tabContentContainer.translatesAutoresizingMaskIntoConstraints = false
        tabContainerHeightConstraint = tabContentContainer.heightAnchor.constraint(equalToConstant: 300)
        tabContainerHeightConstraint.isActive = true

        let bottomBarContainer = NSView()
        bottomBarContainer.wantsLayer = true
        bottomBarContainer.translatesAutoresizingMaskIntoConstraints = false

        let bottomSeparator = MusicSurfaceView { MusicSettingsPalette.hairline }
        bottomSeparator.translatesAutoresizingMaskIntoConstraints = false

        let helpButton = NSButton(title: "", target: self, action: #selector(helpButtonClicked))
        helpButton.bezelStyle = .helpButton
        helpButton.toolTip = "Apple Music Remote v3.0.0 • \(ClientDeviceManager.shared.gitCommitShort)"
        helpButton.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = MusicPillButton(
            title: isEn ? "Cancel" : "Отменить",
            isPrimary: false,
            width: 96,
            target: self,
            action: #selector(cancelButtonClicked)
        )
        cancelButton.keyEquivalent = "\u{1b}"

        let okButton = MusicPillButton(
            title: isEn ? "OK" : "ОК",
            isPrimary: true,
            width: 86,
            target: self,
            action: #selector(okButtonClicked)
        )
        okButton.keyEquivalent = "\r"

        bottomBarContainer.addSubview(bottomSeparator)
        bottomBarContainer.addSubview(helpButton)
        bottomBarContainer.addSubview(cancelButton)
        bottomBarContainer.addSubview(okButton)

        NSLayoutConstraint.activate([
            bottomBarContainer.heightAnchor.constraint(equalToConstant: 54),
            bottomSeparator.topAnchor.constraint(equalTo: bottomBarContainer.topAnchor),
            bottomSeparator.leadingAnchor.constraint(equalTo: bottomBarContainer.leadingAnchor, constant: 22),
            bottomSeparator.trailingAnchor.constraint(equalTo: bottomBarContainer.trailingAnchor, constant: -22),
            bottomSeparator.heightAnchor.constraint(equalToConstant: 1),

            helpButton.leadingAnchor.constraint(equalTo: bottomBarContainer.leadingAnchor, constant: 20),
            helpButton.centerYAnchor.constraint(equalTo: bottomBarContainer.centerYAnchor, constant: 1),

            okButton.trailingAnchor.constraint(equalTo: bottomBarContainer.trailingAnchor, constant: -20),
            okButton.centerYAnchor.constraint(equalTo: bottomBarContainer.centerYAnchor, constant: 1),

            cancelButton.trailingAnchor.constraint(equalTo: okButton.leadingAnchor, constant: -10),
            cancelButton.centerYAnchor.constraint(equalTo: bottomBarContainer.centerYAnchor, constant: 1)
        ])

        rootSurface.addSubview(topBarContainer)
        rootSurface.addSubview(tabContentContainer)
        rootSurface.addSubview(bottomBarContainer)

        NSLayoutConstraint.activate([
            topBarContainer.topAnchor.constraint(equalTo: rootSurface.topAnchor),
            topBarContainer.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
            topBarContainer.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),

            tabContentContainer.topAnchor.constraint(equalTo: topBarContainer.bottomAnchor),
            tabContentContainer.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
            tabContentContainer.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),

            bottomBarContainer.topAnchor.constraint(equalTo: tabContentContainer.bottomAnchor),
            bottomBarContainer.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
            bottomBarContainer.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),
            bottomBarContainer.bottomAnchor.constraint(equalTo: rootSurface.bottomAnchor)
        ])
    }

    internal static func syncWrappingTextFieldsPreferredWidth(in view: NSView, reset: Bool) {
        if let tf = view as? NSTextField,
           !tf.isEditable,
           (tf.usesSingleLineMode == false || tf.cell?.wraps == true) {
            if reset {
                tf.preferredMaxLayoutWidth = 0
            } else if tf.bounds.width > 20 {
                tf.preferredMaxLayoutWidth = floor(tf.bounds.width)
            }
            tf.invalidateIntrinsicContentSize()
        }
        for sub in view.subviews {
            syncWrappingTextFieldsPreferredWidth(in: sub, reset: reset)
        }
    }

    internal func selectTab(_ tab: SettingsTab, animated: Bool) {
        currentTab = tab
        window?.title = tab.windowTitle

        for (t, btn) in tabButtons {
            btn.setSelected(t == tab)
        }

        tabContentContainer.subviews.forEach { $0.removeFromSuperview() }

        guard let targetView = tabViews[tab], let win = window else { return }
        targetView.removeFromSuperview()
        targetView.translatesAutoresizingMaskIntoConstraints = false

        let visibleScreenFrame = (win.screen ?? NSScreen.main)?.visibleFrame
        let targetWidth: CGFloat = Self.standardWindowWidth

        targetView.frame = NSRect(x: 0, y: 0, width: targetWidth, height: 1800)
        let measureWidthConstraint = targetView.widthAnchor.constraint(equalToConstant: targetWidth)
        measureWidthConstraint.isActive = true
        targetView.layoutSubtreeIfNeeded()
        Self.syncWrappingTextFieldsPreferredWidth(in: targetView, reset: false)
        targetView.layoutSubtreeIfNeeded()
        let fittingHeight = max(ceil(targetView.fittingSize.height) + 6, 200)
        Self.syncWrappingTextFieldsPreferredWidth(in: targetView, reset: true)
        measureWidthConstraint.isActive = false

        let topBarHeight: CGFloat = 66
        let bottomBarHeight: CGFloat = 54
        let rawContentHeight = topBarHeight + fittingHeight + bottomBarHeight
        let targetHeight = win.frameRect(forContentRect: NSRect(x: 0, y: 0, width: targetWidth, height: rawContentHeight)).height
        let maxVisibleHeight = (visibleScreenFrame?.height ?? 900) - 24
        let clampedHeight = min(targetHeight, max(480, maxVisibleHeight))
        let clampedContentRect = win.contentRect(forFrameRect: NSRect(x: 0, y: 0, width: targetWidth, height: clampedHeight))
        let displayedContentHeight = max(200, floor(clampedContentRect.height - topBarHeight - bottomBarHeight))

        if fittingHeight > displayedContentHeight + 1 {
            let scrollView = NSScrollView()
            let clipView = FlippedClipView()
            clipView.drawsBackground = false
            scrollView.contentView = clipView
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.translatesAutoresizingMaskIntoConstraints = false

            let docView = FlippedTabDocumentView()
            docView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.documentView = docView
            docView.addSubview(targetView)
            tabContentContainer.addSubview(scrollView)

            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(equalTo: tabContentContainer.topAnchor),
                scrollView.leadingAnchor.constraint(equalTo: tabContentContainer.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: tabContentContainer.trailingAnchor),
                scrollView.bottomAnchor.constraint(equalTo: tabContentContainer.bottomAnchor),

                docView.topAnchor.constraint(equalTo: clipView.topAnchor),
                docView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
                docView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),

                targetView.topAnchor.constraint(equalTo: docView.topAnchor),
                targetView.leadingAnchor.constraint(equalTo: docView.leadingAnchor),
                targetView.trailingAnchor.constraint(equalTo: docView.trailingAnchor),
                targetView.bottomAnchor.constraint(equalTo: docView.bottomAnchor, constant: -8)
            ])
        } else {
            tabContentContainer.addSubview(targetView)
            let bottomGuard = targetView.bottomAnchor.constraint(lessThanOrEqualTo: tabContentContainer.bottomAnchor)
            bottomGuard.priority = .defaultHigh
            NSLayoutConstraint.activate([
                targetView.topAnchor.constraint(equalTo: tabContentContainer.topAnchor),
                targetView.leadingAnchor.constraint(equalTo: tabContentContainer.leadingAnchor),
                targetView.trailingAnchor.constraint(equalTo: tabContentContainer.trailingAnchor),
                bottomGuard
            ])
        }

        tabContainerHeightConstraint.constant = displayedContentHeight

        let targetFrameSize = NSSize(
            width: win.frameRect(forContentRect: NSRect(x: 0, y: 0, width: targetWidth, height: clampedContentRect.height)).width,
            height: clampedHeight
        )

        var newFrame = win.frame
        newFrame.origin.x -= round((targetFrameSize.width - newFrame.size.width) * 0.5)
        newFrame.origin.y += (newFrame.size.height - targetFrameSize.height)
        newFrame.size.width = targetFrameSize.width
        newFrame.size.height = targetFrameSize.height
        if let vis = visibleScreenFrame {
            if newFrame.maxX > vis.maxX - 12 {
                newFrame.origin.x = vis.maxX - 12 - newFrame.size.width
            }
            if newFrame.minX < vis.minX + 12 {
                newFrame.origin.x = vis.minX + 12
            }
            if newFrame.maxY > vis.maxY - 12 {
                newFrame.origin.y = vis.maxY - 12 - newFrame.size.height
            }
        }
        newFrame.origin.y = max((visibleScreenFrame?.minY ?? 24) + 16, newFrame.origin.y)

        win.setFrame(newFrame, display: true, animate: animated)
    }

    // MARK: - Presentation, Listeners & Footer Actions

    public func show(tab: SettingsTab? = nil) {
        let wasVisible = (window?.isVisible == true)
        if !wasVisible {
            sessionSnapshot = capturePreferencesSnapshot()
        }
        if let requestedTab = tab {
            currentTab = requestedTab
        }
        performRefreshState()
        if !wasVisible {
            window?.center()
        }
        selectTab(currentTab, animated: false)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    internal func selectTabForTesting(_ tab: SettingsTab) {
        performRefreshState()
        selectTab(tab, animated: false)
    }

    internal func presentAlert(_ alert: NSAlert, completion: ((NSApplication.ModalResponse) -> Void)? = nil) {
        if let win = self.window, win.isVisible, win.attachedSheet == nil {
            alert.beginSheetModal(for: win) { response in
                completion?(response)
            }
        } else {
            let response = alert.runModal()
            completion?(response)
        }
    }

    private func setupListeners() {
        BitPerfectLogMonitor.shared.addFormatChangedObserver(id: "SettingsWindow") { [weak self] _, _, desc in
            DispatchQueue.main.async {
                guard let self = self, self.window?.isVisible == true else { return }
                self.streamQualityLabel.stringValue = self.isEn
                    ? "Current stream: \(desc)"
                    : "Текущий поток: \(desc)"
                MenuManager.shared.updateMenuState()
            }
        }

        CoreAudioDeviceManager.shared.addDevicesChangedObserver(id: "SettingsWindow") { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.refreshState()
            }
        }

        MusicAppProvider.shared.addMusicAppLaunchedObserver { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.refreshState()
            }
        }

        MusicAppProvider.shared.addMusicAppTerminatedObserver { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.refreshState()
            }
        }

        DLNADiscoveryManager.shared.addDevicesChangedObserver(id: "SettingsWindow") { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.refreshState()
            }
        }

        WLEDDDPController.shared.onSettingsChanged = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.refreshState()
            }
        }
    }

    @objc internal func okButtonClicked() {
        window?.makeFirstResponder(nil)
        commitPendingTextFields()
        sessionSnapshot = nil
        window?.close()
    }

    @objc internal func cancelButtonClicked() {
        window?.endEditing(for: nil)
        window?.makeFirstResponder(nil)
        if let snapshot = sessionSnapshot {
            sessionSnapshot = nil
            restorePreferencesSnapshot(snapshot)
        }
        window?.close()
    }

    @objc internal func helpButtonClicked() {
        var url = wsUrlField.stringValue
        if url.hasPrefix("ws://") {
            url = "http://" + url.dropFirst(5)
        }
        if let nsUrl = URL(string: url) {
            NSWorkspace.shared.open(nsUrl)
        }
    }
}
