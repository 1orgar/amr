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
            let khz = rate / 1000.0
            let khzStr = (khz.truncatingRemainder(dividingBy: 1) == 0) ? String(format: "%.0f", khz) : String(format: "%.1f", khz)
            button.title = isEn ? " \(khzStr) kHz • \(bitDepth)-bit" : " \(khzStr) кГц • \(bitDepth) бит"
        }

        // 2. Update Audio Format Display
        let isEn = isEnglishUI
        let qualityDesc = BitPerfectLogMonitor.shared.currentQualityDescription
        bitrateItem?.title = isEn ? "🎵 Format: \(qualityDesc)" : "🎵 Формат: \(qualityDesc)"

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

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }
}
