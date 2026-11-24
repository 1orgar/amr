//
//  SettingsWindow+AdvancedTab.swift
//  AppleMusicRemoteMac
//
//  Advanced tab builder (iCloud Sync, UPnP DMR, Diagnostic Logging), off-@MainActor
//  cloud/log-size queries, and action handlers.
//

import AppKit
import UniformTypeIdentifiers

extension SettingsWindow {
    internal func buildAdvancedTabView() -> NSView {
        let isEn = SettingsTab.isEn

        enableCloudSyncSwitch = makeCheckbox(
            title: isEn ? "Sync DSP presets, Room EQ & loudness cache via iCloud" : "Автосинхронизация пресетов DSP, АЧХ и кэша громкости с облаком",
            action: #selector(cloudSyncSwitchToggled(_:))
        )

        cloudSyncFolderField = makeReadonlyMonospaceField("iCloud Drive/AppleMusicRemote", width: 215)

        chooseCloudFolderButton = NSButton(title: isEn ? "Folder…" : "Папка…", target: self, action: #selector(chooseCloudSyncFolderClicked))
        chooseCloudFolderButton.bezelStyle = .rounded
        chooseCloudFolderButton.controlSize = .small

        resetCloudICloudButton = NSButton(title: "iCloud", target: self, action: #selector(resetCloudSyncToICloudClicked))
        resetCloudICloudButton.bezelStyle = .rounded
        resetCloudICloudButton.controlSize = .small
        resetCloudICloudButton.toolTip = isEn ? "Use standard iCloud Drive folder" : "Использовать стандартную папку iCloud Drive"

        revealCloudFolderButton = NSButton(title: "Finder", target: self, action: #selector(revealCloudSyncFolderClicked))
        revealCloudFolderButton.bezelStyle = .rounded
        revealCloudFolderButton.controlSize = .small
        revealCloudFolderButton.toolTip = isEn ? "Reveal sync folder in Finder" : "Показать папку синхронизации в Finder"

        let cloudFolderControls = NSStackView(views: [
            cloudSyncFolderField,
            chooseCloudFolderButton,
            resetCloudICloudButton,
            revealCloudFolderButton
        ])
        cloudFolderControls.orientation = .horizontal
        cloudFolderControls.alignment = .centerY
        cloudFolderControls.spacing = 6

        syncCloudNowButton = NSButton(title: isEn ? "Sync Now" : "Синхронизировать", target: self, action: #selector(syncCloudNowClicked))
        syncCloudNowButton.bezelStyle = .rounded
        syncCloudNowButton.controlSize = .small

        exportCloudSnapshotButton = NSButton(title: isEn ? "Export…" : "Экспорт…", target: self, action: #selector(exportCloudSnapshotClicked))
        exportCloudSnapshotButton.bezelStyle = .rounded
        exportCloudSnapshotButton.controlSize = .small

        importCloudSnapshotButton = NSButton(title: isEn ? "Import…" : "Импорт…", target: self, action: #selector(importCloudSnapshotClicked))
        importCloudSnapshotButton.bezelStyle = .rounded
        importCloudSnapshotButton.controlSize = .small

        let cloudActionsStack = NSStackView(views: [
            syncCloudNowButton,
            exportCloudSnapshotButton,
            importCloudSnapshotButton
        ])
        cloudActionsStack.orientation = .horizontal
        cloudActionsStack.alignment = .centerY
        cloudActionsStack.spacing = 6

        cloudSyncStatusLabel = makeStatusCaption("Автосинхронизация выключена (iCloud Drive)")
        cloudSyncStatusLabel.lineBreakMode = .byWordWrapping

        enableLocalDMRSwitch = makeCheckbox(
            title: isEn ? "Enable local UPnP / DLNA Media Renderer (Home Assistant)" : "Включить локальный DLNA DMR-плеер (Home Assistant, порт 8090)",
            action: #selector(localDMRToggled(_:))
        )

        upnpFriendlyNameField = NSTextField()
        upnpFriendlyNameField.placeholderString = "Apple Music Remote (Mac)"
        upnpFriendlyNameField.bezelStyle = .roundedBezel
        upnpFriendlyNameField.font = NSFont.systemFont(ofSize: 12)
        upnpFriendlyNameField.widthAnchor.constraint(equalToConstant: 215).isActive = true

        saveNameButton = NSButton(title: isEn ? "Save" : "Сохранить", target: self, action: #selector(saveFriendlyNameClicked))
        saveNameButton.bezelStyle = .rounded

        let nameControls = NSStackView(views: [upnpFriendlyNameField, saveNameButton])
        nameControls.orientation = .horizontal
        nameControls.alignment = .centerY
        nameControls.spacing = 6

        upnpUrlField = makeReadonlyMonospaceField("http://127.0.0.1:8090/description.xml", width: 295)
        copyUpnpButton = NSButton(title: isEn ? "Copy" : "Копировать", target: self, action: #selector(copyUpnpUrlClicked))
        copyUpnpButton.bezelStyle = .rounded

        let upnpUrlControls = NSStackView(views: [upnpUrlField, copyUpnpButton])
        upnpUrlControls.orientation = .horizontal
        upnpUrlControls.alignment = .centerY
        upnpUrlControls.spacing = 6

        upnpStatusLabel = makeStatusCaption("Статус: Отключен в настройках")
        upnpStatusLabel.lineBreakMode = .byWordWrapping

        enableFileLoggingSwitch = makeCheckbox(
            title: isEn ? "Write diagnostic debug log to file" : "Вести журнал отладки в файл (amr.log)",
            action: #selector(fileLoggingToggled(_:))
        )

        openLogFileButton = NSButton(title: isEn ? "Open Log" : "Открыть лог", target: self, action: #selector(openLogFileClicked))
        openLogFileButton.bezelStyle = .rounded
        openLogFileButton.controlSize = .small

        revealLogFileButton = NSButton(title: isEn ? "Reveal in Finder" : "Показать в Finder", target: self, action: #selector(revealLogFileClicked))
        revealLogFileButton.bezelStyle = .rounded
        revealLogFileButton.controlSize = .small

        clearLogFileButton = NSButton(title: isEn ? "Clear" : "Очистить", target: self, action: #selector(clearLogFileClicked))
        clearLogFileButton.bezelStyle = .rounded
        clearLogFileButton.controlSize = .small

        let logActionsStack = NSStackView(views: [openLogFileButton, revealLogFileButton, clearLogFileButton])
        logActionsStack.orientation = .horizontal
        logActionsStack.alignment = .centerY
        logActionsStack.spacing = 6

        fileLoggingStatusLabel = makeStatusCaption("Статус: Журналирование в файл отключено")
        fileLoggingStatusLabel.lineBreakMode = .byWordWrapping

        return makeMusicPreferencePage(sections: [
            [
                makeMusicCheckboxRow(
                    category: "iCloud Drive:",
                    checkbox: enableCloudSyncSwitch,
                    subtitle: isEn
                        ? "Two-way merge via iCloud Drive/AppleMusicRemote or custom Dropbox / Syncthing / NAS folder."
                        : "Двустороннее слияние через iCloud Drive/AppleMusicRemote или папку Dropbox / Syncthing / NAS."
                ),
                makeMusicControlRow(category: isEn ? "Sync Folder:" : "Папка облака:", control: cloudFolderControls, subtitle: nil),
                makeMusicControlRow(category: isEn ? "Snapshots:" : "Резервные копии:", control: cloudActionsStack, subtitle: nil),
                makeMusicTwoColumnRow(category: "", rightContent: cloudSyncStatusLabel, topLabelOffset: 0)
            ],
            [
                makeMusicCheckboxRow(category: "DLNA DMR:", checkbox: enableLocalDMRSwitch, subtitle: nil),
                makeMusicControlRow(category: isEn ? "Friendly Name:" : "Имя в сети:", control: nameControls, subtitle: nil),
                makeMusicControlRow(category: "Description XML:", control: upnpUrlControls, subtitle: nil),
                makeMusicTwoColumnRow(category: "", rightContent: upnpStatusLabel, topLabelOffset: 0)
            ],
            [
                makeMusicCheckboxRow(
                    category: isEn ? "Diagnostics:" : "Диагностика:",
                    checkbox: enableFileLoggingSwitch,
                    subtitle: isEn
                        ? "Logs server, queue, CoreAudio, and client events with automatic 5 MB rotation."
                        : "Записывает события очереди, CoreAudio и клиентов с автоматической ротацией при 5 МБ."
                ),
                makeMusicControlRow(category: isEn ? "Log File:" : "Файл журнала:", control: logActionsStack, subtitle: nil),
                makeMusicTwoColumnRow(category: "", rightContent: fileLoggingStatusLabel, topLabelOffset: 0)
            ]
        ])
    }

    // MARK: - Off-@MainActor Cloud & Diagnostic Status Resolution

    internal func refreshFileLoggingStatusLabelAsync() {
        let isLogging = DiagnosticLogger.shared.isEnabled
        enableFileLoggingSwitch.state = isLogging ? .on : .off
        let useEnglish = isEn
        logSizeRequestGeneration &+= 1
        let gen = logSizeRequestGeneration
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let logSizeStr = DiagnosticLogger.shared.logFileSizeDescription()
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.logSizeRequestGeneration == gen, self.fileLoggingStatusLabel != nil else { return }
                if DiagnosticLogger.shared.isEnabled {
                    self.fileLoggingStatusLabel.stringValue = useEnglish
                        ? "🟢 Active • Size: \(logSizeStr) • ~/Library/Logs/AppleMusicRemoteMac/amr.log"
                        : "🟢 Активно • Размер: \(logSizeStr) • ~/Library/Logs/AppleMusicRemoteMac/amr.log"
                    self.fileLoggingStatusLabel.textColor = .systemGreen
                } else {
                    self.fileLoggingStatusLabel.stringValue = useEnglish
                        ? "Status: File logging disabled (log size: \(logSizeStr))"
                        : "Статус: Журналирование в файл отключено (размер лога: \(logSizeStr))"
                    self.fileLoggingStatusLabel.textColor = .secondaryLabelColor
                }
            }
        }
    }

    public func refreshCloudSyncStatusLabel() {
        guard enableCloudSyncSwitch != nil,
              cloudSyncFolderField != nil,
              cloudSyncStatusLabel != nil else { return }

        let service = CloudSettingsSyncService.shared
        enableCloudSyncSwitch.state = service.isEnabled ? .on : .off

        if let customPath = service.customFolderPath, !customPath.isEmpty {
            cloudSyncFolderField.stringValue = (customPath as NSString).abbreviatingWithTildeInPath
            resetCloudICloudButton?.isEnabled = true
        } else {
            cloudSyncFolderField.stringValue = "iCloud Drive/\(CloudSettingsSyncService.defaultSubfolderName)"
            resetCloudICloudButton?.isEnabled = false
        }

        syncCloudNowButton?.isEnabled = !service.isSyncing

        let useEnglish = isEn
        cloudStatusRequestGeneration &+= 1
        let gen = cloudStatusRequestGeneration
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let desc = CloudSettingsSyncService.shared.statusDescription(isEn: useEnglish)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.cloudStatusRequestGeneration == gen, self.cloudSyncStatusLabel != nil else { return }
                if desc.hasWarning {
                    self.cloudSyncStatusLabel.stringValue = "🟠 \(desc.text)"
                    self.cloudSyncStatusLabel.textColor = .systemOrange
                } else if desc.isActive {
                    self.cloudSyncStatusLabel.stringValue = "🟢 \(desc.text)"
                    self.cloudSyncStatusLabel.textColor = .systemGreen
                } else {
                    self.cloudSyncStatusLabel.stringValue = "⚪ \(desc.text)"
                    self.cloudSyncStatusLabel.textColor = .secondaryLabelColor
                }
            }
        }
    }

    // MARK: - UPnP DMR, Logging & Cloud Sync Actions

    @objc internal func localDMRToggled(_ sender: NSButton) {
        UPnPMediaRendererServer.shared.setEnabled(sender.state == .on)
        refreshState()
    }

    @objc internal func saveFriendlyNameClicked() {
        let text = upnpFriendlyNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = text.isEmpty ? "Apple Music Remote (Mac)" : text
        SSDPService.shared.friendlyName = name
        upnpFriendlyNameField.stringValue = name
        SSDPService.shared.sendAliveNotifications()
    }

    @objc internal func copyUpnpUrlClicked() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(upnpUrlField.stringValue, forType: .string)
    }

    @objc internal func fileLoggingToggled(_ sender: NSButton) {
        DiagnosticLogger.shared.isEnabled = (sender.state == .on)
        refreshState()
    }

    @objc internal func openLogFileClicked() {
        DiagnosticLogger.shared.openLogFile()
        refreshState()
    }

    @objc internal func revealLogFileClicked() {
        DiagnosticLogger.shared.revealInFinder()
        refreshState()
    }

    @objc internal func clearLogFileClicked() {
        DiagnosticLogger.shared.clearLog()
        refreshState()
    }

    @objc internal func openCloudSyncTabClicked() {
        selectTab(.advanced, animated: true)
        refreshCloudSyncStatusLabel()
    }

    @objc internal func cloudSyncSwitchToggled(_ sender: NSButton) {
        CloudSettingsSyncService.shared.isEnabled = (sender.state == .on)
        refreshCloudSyncStatusLabel()
    }

    @objc internal func chooseCloudSyncFolderClicked() {
        let panel = NSOpenPanel()
        panel.title = isEn ? "Choose Cloud Sync Folder" : "Выберите папку облачной синхронизации"
        panel.message = isEn
            ? "Select a folder in iCloud Drive, Dropbox, Syncthing or NAS where amr_cloud_sync_v1.json will be synced."
            : "Выберите папку в iCloud Drive, Dropbox, Syncthing или на сетевом диске для файла amr_cloud_sync_v1.json."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let folderURL = panel.url {
            CloudSettingsSyncService.shared.customFolderPath = folderURL.path
            refreshCloudSyncStatusLabel()
        }
    }

    @objc internal func resetCloudSyncToICloudClicked() {
        CloudSettingsSyncService.shared.customFolderPath = nil
        refreshCloudSyncStatusLabel()
    }

    @objc internal func revealCloudSyncFolderClicked() {
        let dirURL = CloudSettingsSyncService.shared.resolvedSyncDirectoryURL()
        let fileURL = CloudSettingsSyncService.shared.resolvedSyncFileURL()
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dirURL.path)
        }
    }

    @objc internal func syncCloudNowClicked() {
        syncCloudNowButton?.isEnabled = false
        CloudSettingsSyncService.shared.syncNow(reason: "settings_manual_button") { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshDSPControlsState()
                self?.refreshCloudSyncStatusLabel()
            }
        }
    }

    @objc internal func exportCloudSnapshotClicked() {
        let panel = NSSavePanel()
        panel.title = isEn ? "Export DSP Presets & Track Normalization" : "Экспорт пресетов DSP и нормализации треков"
        panel.nameFieldStringValue = CloudSettingsSyncService.cloudFileName
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        let useEnglish = isEn
        exportCloudSnapshotButton?.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try CloudSettingsSyncService.shared.exportSnapshot(to: destURL) }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.exportCloudSnapshotButton?.isEnabled = true
                self.refreshState()
                MenuManager.shared.updateMenuState()
                switch result {
                case .success(let exported):
                    let alert = NSAlert()
                    alert.alertStyle = .informational
                    alert.messageText = useEnglish ? "Snapshot Exported" : "Резервная копия сохранена"
                    alert.informativeText = useEnglish
                        ? "Exported \(exported.customDSPPresets.count) custom DSP presets, \(exported.trackLoudnessEntries.count) SoundCheck tracks and \(exported.trackDynamicsEntries.count) DR/LUFS entries."
                        : "Экспортировано: пресетов DSP — \(exported.customDSPPresets.count), записей громкости — \(exported.trackLoudnessEntries.count), замеров DR/LUFS — \(exported.trackDynamicsEntries.count)."
                    self.presentAlert(alert)
                case .failure(let error):
                    self.presentAlert(NSAlert(error: error))
                }
            }
        }
    }

    @objc internal func importCloudSnapshotClicked() {
        let panel = NSOpenPanel()
        panel.title = isEn ? "Import DSP Presets & Track Normalization" : "Импорт пресетов DSP и нормализации треков"
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let srcURL = panel.url else { return }

        let useEnglish = isEn
        importCloudSnapshotButton?.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try CloudSettingsSyncService.shared.importSnapshot(from: srcURL) }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.importCloudSnapshotButton?.isEnabled = true
                self.refreshState()
                MenuManager.shared.updateMenuState()
                switch result {
                case .success(let summary):
                    let alert = NSAlert()
                    alert.alertStyle = .informational
                    alert.messageText = useEnglish ? "Snapshot Imported & Merged" : "Импорт и слияние завершены"
                    alert.informativeText = useEnglish
                        ? "Total presets: \(summary.totalSyncedPresets) • Added loudness entries: \(summary.mergedLoudnessCount) • Added DR/LUFS entries: \(summary.mergedDynamicsCount)."
                        : "Всего пользовательских пресетов: \(summary.totalSyncedPresets) • Новых записей громкости: \(summary.mergedLoudnessCount) • Новых замеров DR/LUFS: \(summary.mergedDynamicsCount)."
                    self.presentAlert(alert)
                case .failure(let error):
                    self.presentAlert(NSAlert(error: error))
                }
            }
        }
    }
}
