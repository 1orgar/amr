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
    private var musicAppItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?

    private override init() {
        super.init()
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

        // 1. Header
        let headerItem = NSMenuItem(title: "Apple Music Remote", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        // 2. Client Counter
        let countItem = NSMenuItem(title: "⚪ 0 клиентов подключено", action: nil, keyEquivalent: "")
        countItem.isEnabled = false
        self.clientCountItem = countItem
        menu.addItem(countItem)

        // 3. Bitrate & Quality Display
        let bitItem = NSMenuItem(title: "🎵 Битрейт: 44.1 кГц (Lossless)", action: nil, keyEquivalent: "")
        bitItem.isEnabled = false
        self.bitrateItem = bitItem
        menu.addItem(bitItem)

        // 4. Music.app Status
        let mAppItem = NSMenuItem(title: "Music.app: 🟢 Запущен", action: #selector(toggleMusicAppClicked), keyEquivalent: "")
        mAppItem.target = self
        self.musicAppItem = mAppItem
        menu.addItem(mAppItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Launch at Login
        let loginItem = NSMenuItem(title: "Запускать при входе в систему", action: #selector(toggleLaunchAtLoginClicked), keyEquivalent: "")
        loginItem.target = self
        self.launchAtLoginItem = loginItem
        menu.addItem(loginItem)

        // 6. Dedicated Settings Window
        let settingsItem = NSMenuItem(title: "⚙️ Настройки...", action: #selector(openSettingsClicked), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // 7. Quit
        let quitItem = NSMenuItem(title: "Завершить Apple Music Remote", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    public func updateClientCount(_ count: Int) {
        if count > 0 {
            clientCountItem?.title = "🟢 \(count) iOS \(count == 1 ? "клиент" : "клиентов") на связи"
        } else {
            clientCountItem?.title = "⚪ Нет подключенных клиентов"
        }
    }

    public func updateMenuState(with status: PlayerStatus? = nil) {
        let st = status ?? MusicBridge.shared.getPlayerStatus()
        let isPlaying = (st.playerState == "playing")

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

            // Frequency and Bit Depth directly next to icon
            let rate: Double
            let bitDepth: Int
            if let detected = BitPerfectLogMonitor.shared.currentDetectedSampleRate {
                rate = detected
                bitDepth = BitPerfectLogMonitor.shared.currentDetectedBitDepth ?? (rate >= 48000.0 ? 24 : 16)
            } else {
                let audioParams = MusicBridge.shared.getCurrentTrackAudioParams()
                if let trackRate = audioParams.sampleRate {
                    rate = trackRate
                    bitDepth = audioParams.bitDepth ?? (rate >= 48000.0 ? 24 : 16)
                } else if let curDev = CoreAudioDeviceManager.shared.getOutputDevices().first(where: { $0.isDefault }) {
                    rate = curDev.currentSampleRate
                    bitDepth = 24
                } else {
                    rate = 44100.0
                    bitDepth = 16
                }
            }

            let khz = rate / 1000.0
            let khzStr = (khz.truncatingRemainder(dividingBy: 1) == 0) ? String(format: "%.0f", khz) : String(format: "%.1f", khz)
            button.title = " \(khzStr) кГц • \(bitDepth) бит"
        }

        // 2. Update Audio Format Display
        let qualityDesc = BitPerfectLogMonitor.shared.currentQualityDescription
        bitrateItem?.title = "🎵 Формат: \(qualityDesc)"

        // 3. Client Count
        updateClientCount(WebSocketServer.shared.clientCount)

        // 4. Music.app & Launch at Login status
        let isMusicRunning = MusicAppProvider.shared.isMusicAppRunning
        if isMusicRunning {
            musicAppItem?.title = "Music.app: 🟢 Запущен"
        } else {
            musicAppItem?.title = "Music.app: ⚪ Запустить"
        }

        LaunchAtLoginManager.shared.refreshStatus()
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
        updateMenuState()
    }

    @objc private func openSettingsClicked() {
        SettingsWindow.shared.show()
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }
}
