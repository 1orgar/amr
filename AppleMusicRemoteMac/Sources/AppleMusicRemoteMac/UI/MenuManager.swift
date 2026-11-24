//
//  MenuManager.swift
//  AppleMusicRemoteMac
//
//  Menu Bar Status Item and quick menu for Apple Music Remote
//

import AppKit
import Foundation
import CoreAudio

@MainActor
public final class MenuManager: NSObject {
    public static let shared = MenuManager()

    private var statusItem: NSStatusItem?
    private var animationFrame = 0
    private let iconAnimationFrames = ["music.note", "music.quarternote.3", "music.note.list"]

    private var clientCountItem: NSMenuItem?
    private var bitrateItem: NSMenuItem?
    private var dspMenuItem: NSMenuItem?
    private var roomMenuItem: NSMenuItem?
    private var musicAppItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?

    private override init() {
        super.init()
    }

    private var isEnglishUI: Bool {
        SettingsTab.isEn
    }

    public func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
            button.image?.isTemplate = true
        }

        buildMenu()
        updateMenuState()
    }

    private func buildMenu() {
        let menu = NSMenu()
        let isEn = isEnglishUI

        // 1. Header
        let headerItem = NSMenuItem(title: "Apple Music Remote", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        // 2. Client Counter
        let countItem = NSMenuItem(title: isEn ? "⚪ 0 clients connected" : "⚪ 0 клиентов подключено", action: nil, keyEquivalent: "")
        countItem.isEnabled = false
        self.clientCountItem = countItem
        menu.addItem(countItem)

        // 3. Bitrate & Quality Display
        let bitItem = NSMenuItem(title: isEn ? "🎵 Format: 44.1 kHz (Lossless)" : "🎵 Битрейт: 44.1 кГц (Lossless)", action: nil, keyEquivalent: "")
        bitItem.isEnabled = false
        self.bitrateItem = bitItem
        menu.addItem(bitItem)

        // 3b. Hybrid DSP Engine Presets Submenu
        let dspRoot = NSMenuItem(title: isEn ? "🎛️ DSP Preset: Bit-Perfect" : "🎛️ Пресет DSP: Bit-Perfect", action: nil, keyEquivalent: "")
        dspRoot.submenu = NSMenu()
        self.dspMenuItem = dspRoot
        menu.addItem(dspRoot)
        rebuildDSPPresetsSubmenu()

        // 3c. Room Acoustic Frequency Response (64-bit Auto-PEQ) Submenu
        let roomRoot = NSMenuItem(title: isEn ? "📐 Room EQ: Off" : "📐 АЧХ комнаты: Выкл", action: nil, keyEquivalent: "")
        roomRoot.submenu = NSMenu()
        self.roomMenuItem = roomRoot
        menu.addItem(roomRoot)
        rebuildRoomAcousticSubmenu()

        // 4. Music.app Status
        let mAppItem = NSMenuItem(title: isEn ? "Music.app: 🟢 Running" : "Music.app: 🟢 Запущен", action: #selector(toggleMusicAppClicked), keyEquivalent: "")
        mAppItem.target = self
        self.musicAppItem = mAppItem
        menu.addItem(mAppItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Launch at Login
        LaunchAtLoginManager.shared.refreshStatus()
        let loginItem = NSMenuItem(title: isEn ? "Launch at Login" : "Запускать при входе в систему", action: #selector(toggleLaunchAtLoginClicked), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
        self.launchAtLoginItem = loginItem
        menu.addItem(loginItem)

        // 6. Dedicated Settings Window
        let settingsItem = NSMenuItem(title: isEn ? "⚙️ Settings..." : "⚙️ Настройки...", action: #selector(openSettingsClicked), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // 7. Quit
        let quitItem = NSMenuItem(title: isEn ? "Quit Apple Music Remote" : "Завершить Apple Music Remote", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    public func updateClientCount(_ count: Int) {
        let isEn = isEnglishUI
        let pending = ClientDeviceManager.shared.pendingCount
        if pending > 0 {
            clientCountItem?.isEnabled = true
            clientCountItem?.target = self
            clientCountItem?.action = #selector(openSettingsClicked)
            if isEn {
                clientCountItem?.title = "🟠 \(pending) \(pending == 1 ? "device awaiting" : "devices awaiting") authorization..."
            } else {
                clientCountItem?.title = "🟠 Ожидает авторизации: \(pending) устр. (Открыть...)"
            }
        } else if count > 0 {
            clientCountItem?.isEnabled = false
            clientCountItem?.action = nil
            if isEn {
                clientCountItem?.title = "🟢 \(count) Web/PWA \(count == 1 ? "client" : "clients") connected"
            } else {
                let mod10 = count % 10
                let mod100 = count % 100
                let word = (mod10 == 1 && mod100 != 11)
                    ? "клиент подключён"
                    : ((mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) ? "клиента подключено" : "клиентов подключено")
                clientCountItem?.title = "🟢 \(count) Web/PWA \(word)"
            }
        } else {
            clientCountItem?.isEnabled = false
            clientCountItem?.action = nil
            clientCountItem?.title = isEn ? "⚪ No connected clients" : "⚪ Нет подключенных клиентов"
        }
    }

    public func updateMenuState(with status: PlayerStatus? = nil) {
        // Never block @MainActor with synchronous AppleScript / ScriptingBridge IPC
        let st = status ?? PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.lastPlayerStatusCache?.status }
        let isPlaying = (st?.playerState == "playing")

        // 1. Animated icon and Frequency & Bitrate in Menu Bar
        if let button = statusItem?.button {
            if isPlaying {
                animationFrame = (animationFrame + 1) % iconAnimationFrames.count
                let symbolName = iconAnimationFrames[animationFrame]
                button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            } else {
                button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
            }
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

            // Frequency and Bit Depth directly next to icon (lock-free / IPC-free on Main Thread)
            let rate: Double
            let bitDepth: Int
            if let detected = BitPerfectLogMonitor.shared.currentDetectedSampleRate {
                rate = detected
                bitDepth = BitPerfectLogMonitor.shared.currentDetectedBitDepth ?? (rate >= 48000.0 ? 24 : 16)
            } else if let trackRate = st?.track?.sampleRate, trackRate > 0 {
                rate = Double(trackRate)
                bitDepth = st?.track?.bitDepth ?? (rate >= 48000.0 ? 24 : 16)
            } else if let devRate = st?.audioDeviceSampleRate, devRate > 0 {
                rate = devRate
                bitDepth = st?.audioDeviceBitDepth ?? (rate >= 48000.0 ? 24 : 16)
            } else if let curDev = CoreAudioDeviceManager.shared.getOutputDevices().first(where: { $0.isDefault }) {
                rate = curDev.currentSampleRate
                bitDepth = 24
            } else {
                rate = 44100.0
                bitDepth = 16
            }

            let isEn = isEnglishUI
            let hasActiveDLNA = DLNADiscoveryManager.shared.hasActiveRenderer
            let dspCfg = AudioEngineController.shared.currentConfigurationSnapshot()
            if !hasActiveDLNA && dspCfg.mode == .sdmDoP {
                let profShort = dspCfg.profile == .transient ? "7EC-T" : (dspCfg.profile == .balanced ? "7EC-B" : "7EC-S")
                button.title = " DSD\(dspCfg.dsdRate.rawValue) • \(profShort)"
            } else if !hasActiveDLNA && dspCfg.mode == .hqNOSPCM {
                button.title = " NOS • LNS15"
            } else {
                let khz = rate / 1000.0
                let khzStr = (khz.truncatingRemainder(dividingBy: 1) == 0) ? String(format: "%.0f", khz) : String(format: "%.1f", khz)
                button.title = isEn ? " \(khzStr) kHz • \(bitDepth)-bit" : " \(khzStr) кГц • \(bitDepth) бит"
            }
        }

        // 2. Update Audio Format Display & DSP Submenu state
        let isEn = isEnglishUI
        let hasActiveDLNA = DLNADiscoveryManager.shared.hasActiveRenderer
        let qualityDesc = BitPerfectLogMonitor.shared.currentQualityDescription
        bitrateItem?.title = isEn ? "🎵 Format: \(qualityDesc)" : "🎵 Формат: \(qualityDesc)"

        let dspCfg = AudioEngineController.shared.currentConfigurationSnapshot()
        let activePreset = DSPPresetManager.shared.matchingPreset(for: dspCfg)
        let dspTitle: String = {
            if hasActiveDLNA {
                return isEn ? "🎛️ DSP Preset: Off (BluOS / DLNA)" : "🎛️ Пресет DSP: Выкл (BluOS / DLNA)"
            }
            if dspCfg.mode == .bitPerfectPassthrough {
                return isEn ? "🎛️ DSP Preset: Bit-Perfect" : "🎛️ Пресет DSP: Bit-Perfect"
            }
            if let activePreset {
                return "🎛️ DSP: \(activePreset.name)"
            }
            switch dspCfg.mode {
            case .bitPerfectPassthrough:
                return isEn ? "🎛️ DSP Preset: Bit-Perfect" : "🎛️ Пресет DSP: Bit-Perfect"
            case .sdmDoP:
                return "🎛️ DSP: DSD\(dspCfg.dsdRate.rawValue) DoP (Польз.)"
            case .hqNOSPCM:
                return "🎛️ DSP: HQ NOS PCM (Польз.)"
            }
        }()
        dspMenuItem?.title = dspTitle
        rebuildDSPPresetsSubmenu()

        let roomSvc = RoomAcousticService.shared
        let roomProfiles = roomSvc.allProfiles()
        if roomSvc.isCorrectionEnabled, let prof = roomSvc.activeProfile {
            roomMenuItem?.title = isEn ? "📐 Room EQ: \(prof.name)" : "📐 АЧХ комнаты: \(prof.name)"
        } else if !roomProfiles.isEmpty {
            roomMenuItem?.title = isEn ? "📐 Room EQ: Off" : "📐 АЧХ комнаты: Выкл"
        } else {
            roomMenuItem?.title = isEn ? "📐 Room EQ: No Profile" : "📐 АЧХ комнаты: Нет замера"
        }
        rebuildRoomAcousticSubmenu()

        // 3. Client Count
        updateClientCount(WebSocketServer.shared.clientCount)

        // 4. Music.app & Launch at Login status
        let isMusicRunning = MusicAppProvider.shared.isMusicAppRunning
        if isMusicRunning {
            musicAppItem?.title = isEn ? "Music.app: 🟢 Running" : "Music.app: 🟢 Запущен"
        } else {
            musicAppItem?.title = isEn ? "Music.app: ⚪ Launch" : "Music.app: ⚪ Запустить"
        }

        launchAtLoginItem?.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
    }

    // MARK: - Actions

    @objc private func toggleMusicAppClicked() {
        if !MusicAppProvider.shared.isMusicAppRunning {
            MusicAppProvider.shared.launchMusicApp { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.updateMenuState()
                }
            }
        }
    }

    @objc private func toggleLaunchAtLoginClicked() {
        let newState = !LaunchAtLoginManager.shared.isEnabled
        _ = LaunchAtLoginManager.shared.setEnabled(newState)
        LaunchAtLoginManager.shared.refreshStatus()
        updateMenuState()
    }

    @objc private func openSettingsClicked() {
        SettingsWindow.shared.show()
    }

    @objc private func openDSPSettingsClicked() {
        SettingsWindow.shared.show(tab: .dsp)
    }

    private func rebuildDSPPresetsSubmenu() {
        guard let dspSub = dspMenuItem?.submenu else { return }
        dspSub.removeAllItems()

        let isEn = isEnglishUI
        let hasActiveDLNA = DLNADiscoveryManager.shared.hasActiveRenderer
        let cfg = AudioEngineController.shared.currentConfigurationSnapshot()
        let usbAvail = AudioEngineController.shared.currentUSBDACAvailability(targetDeviceUID: cfg.targetDeviceUID)
        let matched = DSPPresetManager.shared.matchingPreset(for: cfg)
        let builtIns = DSPPresetManager.builtInPresets
        let customs = DSPPresetManager.shared.customPresets()

        if hasActiveDLNA {
            let notice = NSMenuItem(
                title: isEn
                    ? "ℹ️ Unavailable on BluOS / DLNA (Bit-Perfect PCM)"
                    : "ℹ️ Недоступно при выводе на BluOS / DLNA",
                action: nil,
                keyEquivalent: ""
            )
            notice.isEnabled = false
            dspSub.addItem(notice)
            dspSub.addItem(NSMenuItem.separator())
        } else if !usbAvail.hasEligibleUSBDAC {
            let notice = NSMenuItem(
                title: isEn
                    ? "ℹ️ DSD / HQ NOS require an external USB DAC"
                    : "ℹ️ DSD / HQ NOS требуют внешний USB ЦАП",
                action: nil,
                keyEquivalent: ""
            )
            notice.isEnabled = false
            dspSub.addItem(notice)
            dspSub.addItem(NSMenuItem.separator())
        }

        let effectiveMatchedId: String? = (!hasActiveDLNA && usbAvail.isModeSupported(cfg.mode))
            ? matched?.id
            : "builtin_passthrough"

        for preset in builtIns {
            let canUse = !hasActiveDLNA && usbAvail.isModeSupported(preset.configuration.mode, dsdRate: preset.configuration.dsdRate)
            let item = NSMenuItem(
                title: preset.name,
                action: canUse ? #selector(selectDSPPresetMenuItem(_:)) : nil,
                keyEquivalent: ""
            )
            item.target = canUse ? self : nil
            item.isEnabled = canUse
            item.representedObject = preset.id
            item.toolTip = preset.subtitle
            item.state = (!hasActiveDLNA && effectiveMatchedId == preset.id) ? .on : .off
            dspSub.addItem(item)
        }

        if !customs.isEmpty {
            dspSub.addItem(NSMenuItem.separator())
            let header = NSMenuItem(title: isEn ? "Custom Presets" : "Пользовательские пресеты", action: nil, keyEquivalent: "")
            header.isEnabled = false
            dspSub.addItem(header)

            for preset in customs {
                let canUse = !hasActiveDLNA && usbAvail.isModeSupported(preset.configuration.mode, dsdRate: preset.configuration.dsdRate)
                let item = NSMenuItem(
                    title: preset.name,
                    action: canUse ? #selector(selectDSPPresetMenuItem(_:)) : nil,
                    keyEquivalent: ""
                )
                item.target = canUse ? self : nil
                item.isEnabled = canUse
                item.representedObject = preset.id
                item.toolTip = preset.subtitle
                item.state = (!hasActiveDLNA && effectiveMatchedId == preset.id) ? .on : .off
                dspSub.addItem(item)
            }
        }

        if !hasActiveDLNA && matched == nil {
            dspSub.addItem(NSMenuItem.separator())
            let unsaved = NSMenuItem(
                title: "✏️ \(isEn ? "Custom (unsaved)" : "Пользовательский"): \(DSPPresetManager.summarizeConfiguration(cfg))",
                action: nil,
                keyEquivalent: ""
            )
            unsaved.state = .on
            unsaved.isEnabled = false
            dspSub.addItem(unsaved)
        }

        dspSub.addItem(NSMenuItem.separator())
        let itemOpenDSPSettings = NSMenuItem(
            title: isEn ? "⚙️ Manage DSP Presets..." : "⚙️ Управление пресетами DSP...",
            action: #selector(openDSPSettingsClicked),
            keyEquivalent: ""
        )
        itemOpenDSPSettings.target = self
        dspSub.addItem(itemOpenDSPSettings)
    }

    @objc private func selectDSPPresetMenuItem(_ sender: NSMenuItem) {
        guard !DLNADiscoveryManager.shared.hasActiveRenderer else {
            updateMenuState()
            return
        }
        guard let presetID = sender.representedObject as? String else { return }
        Task {
            guard await DSPPresetManager.shared.applyPreset(id: presetID) != nil else { return }
            let payload = WebSocketServer.buildDSPSettingsDictionary()
            WebSocketServer.shared.broadcastEvent(name: "dsp_settings", data: payload)
            WebSocketServer.shared.broadcastAudioDevices()
            WebSocketServer.shared.broadcastStatus(includeQueue: false)
            await MainActor.run {
                self.updateMenuState()
                SettingsWindow.refreshIfVisible()
            }
        }
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }

    private func rebuildRoomAcousticSubmenu() {
        guard let roomSub = roomMenuItem?.submenu else { return }
        roomSub.removeAllItems()

        let isEn = isEnglishUI
        let roomSvc = RoomAcousticService.shared
        let profiles = roomSvc.allProfiles()
        let activeProf = roomSvc.activeProfile
        let isEnabled = roomSvc.isCorrectionEnabled && activeProf != nil

        let toggleItem = NSMenuItem(
            title: isEn ? "Enable 64-bit Room Auto-PEQ" : "Включить коррекцию 64-bit Auto-PEQ",
            action: profiles.isEmpty ? nil : #selector(toggleRoomCorrectionMenuItem),
            keyEquivalent: ""
        )
        toggleItem.target = profiles.isEmpty ? nil : self
        toggleItem.isEnabled = !profiles.isEmpty
        toggleItem.state = isEnabled ? .on : .off
        roomSub.addItem(toggleItem)

        roomSub.addItem(NSMenuItem.separator())

        if profiles.isEmpty {
            let emptyItem = NSMenuItem(
                title: isEn
                    ? "ℹ️ Measure via iPhone / iPad Mic in PWA ('Signal Path')"
                    : "ℹ️ Замерьте микрофоном iPhone / iPad в PWA («Тракт сигнала»)",
                action: nil,
                keyEquivalent: ""
            )
            emptyItem.isEnabled = false
            roomSub.addItem(emptyItem)
        } else {
            let header = NSMenuItem(
                title: isEn ? "Measured Profiles (iCloud)" : "Профили замера АЧХ (iCloud)",
                action: nil,
                keyEquivalent: ""
            )
            header.isEnabled = false
            roomSub.addItem(header)

            for prof in profiles {
                let item = NSMenuItem(
                    title: String(format: "%@ (%d PEQ, %.1f дБ)", prof.name, prof.eqBands.count, prof.preampGainDB),
                    action: #selector(selectRoomProfileMenuItem(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = prof.id
                item.state = (activeProf?.id == prof.id) ? .on : .off
                roomSub.addItem(item)
            }
        }

        roomSub.addItem(NSMenuItem.separator())
        let openInspector = NSMenuItem(
            title: isEn ? "📈 Inspect Curve & DSP Settings..." : "📈 График АЧХ и настройки DSP...",
            action: #selector(openDSPSettingsClicked),
            keyEquivalent: ""
        )
        openInspector.target = self
        roomSub.addItem(openInspector)
    }

    @objc private func toggleRoomCorrectionMenuItem() {
        let next = !RoomAcousticService.shared.isCorrectionEnabled
        RoomAcousticService.shared.setCorrectionEnabled(next)
        WebSocketServer.shared.broadcastEvent(name: "room_acoustic_settings", data: RoomAcousticService.shared.statusDictionary())
        WebSocketServer.shared.broadcastEvent(name: "dsp_settings", data: WebSocketServer.buildDSPSettingsDictionary())
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
        updateMenuState()
        SettingsWindow.refreshIfVisible()
    }

    @objc private func selectRoomProfileMenuItem(_ sender: NSMenuItem) {
        guard let profID = sender.representedObject as? String else { return }
        _ = RoomAcousticService.shared.selectProfile(id: profID)
        if !RoomAcousticService.shared.isCorrectionEnabled {
            RoomAcousticService.shared.setCorrectionEnabled(true)
        }
        WebSocketServer.shared.broadcastEvent(name: "room_acoustic_settings", data: RoomAcousticService.shared.statusDictionary())
        WebSocketServer.shared.broadcastEvent(name: "dsp_settings", data: WebSocketServer.buildDSPSettingsDictionary())
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
        updateMenuState()
        SettingsWindow.refreshIfVisible()
    }
}
