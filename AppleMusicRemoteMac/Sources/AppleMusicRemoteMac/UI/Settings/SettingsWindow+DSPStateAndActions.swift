//
//  SettingsWindow+DSPStateAndActions.swift
//  AppleMusicRemoteMac
//
//  Hybrid DSP Engine state refresh, parameter actions, and non-blocking sheet
//  alerts for preset creation / rename / deletion.
//

import AppKit

extension SettingsWindow {
    internal func refreshDSPControlsState() {
        guard dspModePopUp != nil else { return }
        let cfg = AudioEngineController.shared.currentConfigurationSnapshot()
        let tel = AudioEngineController.shared.latestTelemetrySnapshot()
        let isDLNAActive = DLNADiscoveryManager.shared.hasActiveRenderer
        let usbAvail = AudioEngineController.shared.currentUSBDACAvailability(targetDeviceUID: cfg.targetDeviceUID)

        if dspPresetPopUp != nil {
            dspPresetPopUp.autoenablesItems = false
            dspPresetPopUp.removeAllItems()
            let builtIns = DSPPresetManager.builtInPresets
            let customs = DSPPresetManager.shared.customPresets()
            let matched = DSPPresetManager.shared.matchingPreset(for: cfg)

            for preset in builtIns {
                dspPresetPopUp.addItem(withTitle: preset.name)
                dspPresetPopUp.lastItem?.representedObject = preset.id
                dspPresetPopUp.lastItem?.toolTip = preset.subtitle
                let supported = usbAvail.isModeSupported(preset.configuration.mode, dsdRate: preset.configuration.dsdRate)
                dspPresetPopUp.lastItem?.isEnabled = !isDLNAActive && supported
            }

            if !customs.isEmpty {
                dspPresetPopUp.menu?.addItem(NSMenuItem.separator())
                for preset in customs {
                    dspPresetPopUp.addItem(withTitle: "★ \(preset.name)")
                    dspPresetPopUp.lastItem?.representedObject = preset.id
                    dspPresetPopUp.lastItem?.toolTip = preset.subtitle
                    let supported = usbAvail.isModeSupported(preset.configuration.mode, dsdRate: preset.configuration.dsdRate)
                    dspPresetPopUp.lastItem?.isEnabled = !isDLNAActive && supported
                }
            }

            if isDLNAActive {
                if let bpItem = dspPresetPopUp.itemArray.first {
                    dspPresetPopUp.select(bpItem)
                }
                dspPresetPopUp.isEnabled = false
                dspSaveNewPresetButton.isEnabled = false
                dspUpdatePresetButton.isEnabled = false
                dspRenamePresetButton.isEnabled = false
                dspDeletePresetButton.isEnabled = false
                dspPresetSubtitleLabel.stringValue = isEn
                    ? "DSP preset selection is disabled when streaming to an external BluOS / DLNA player (DSD/NOS unsupported)"
                    : "Выбор пресета DSP отключён при выводе на внешний плеер BluOS / DLNA (не поддерживает DSD/NOS)"
            } else if !usbAvail.hasEligibleUSBDAC {
                if let bpItem = dspPresetPopUp.itemArray.first {
                    dspPresetPopUp.select(bpItem)
                }
                dspPresetPopUp.isEnabled = false
                dspSaveNewPresetButton.isEnabled = false
                dspUpdatePresetButton.isEnabled = false
                dspRenamePresetButton.isEnabled = false
                dspDeletePresetButton.isEnabled = false
                dspPresetSubtitleLabel.stringValue = isEn
                    ? "DSD (DoP) and HQ NOS PCM modes require an external USB DAC (≥ 24-bit / 176.4 kHz)"
                    : "Режимы DSD (DoP) и HQ NOS PCM доступны только при подключении внешнего USB ЦАП (≥ 24-бит / 176.4 кГц)"
            } else {
                dspPresetPopUp.isEnabled = true
                dspSaveNewPresetButton.isEnabled = true
                if let matched {
                    if let item = dspPresetPopUp.itemArray.first(where: { ($0.representedObject as? String) == matched.id }) {
                        dspPresetPopUp.select(item)
                    }
                    dspPresetSubtitleLabel.stringValue = isEn
                        ? "Preset details: \(matched.subtitle)"
                        : "Описание пресета: \(matched.subtitle)"
                    let isCustomSelected = !matched.isBuiltIn
                    dspUpdatePresetButton.isEnabled = false
                    dspRenamePresetButton.isEnabled = isCustomSelected
                    dspDeletePresetButton.isEnabled = isCustomSelected
                } else {
                    dspPresetPopUp.menu?.addItem(NSMenuItem.separator())
                    dspPresetPopUp.addItem(withTitle: isEn ? "✏️ Custom (Unsaved)" : "✏️ Пользовательский (не сохранён)")
                    dspPresetPopUp.lastItem?.representedObject = DSPPresetManager.unsavedCustomPresetID
                    if let last = dspPresetPopUp.lastItem {
                        dspPresetPopUp.select(last)
                    }
                    dspPresetSubtitleLabel.stringValue = isEn
                        ? "Current settings: \(DSPPresetManager.summarizeConfiguration(cfg)) — click '+ Save…' to store"
                        : "Текущие параметры: \(DSPPresetManager.summarizeConfiguration(cfg)) — нажмите «+ Сохранить как новый…»"
                    let prefCustomID = DSPPresetManager.shared.preferredCustomPresetID()
                    dspUpdatePresetButton.isEnabled = (prefCustomID != nil)
                    dspRenamePresetButton.isEnabled = (prefCustomID != nil)
                    dspDeletePresetButton.isEnabled = (prefCustomID != nil)
                }
            }
        }

        dspModePopUp.autoenablesItems = false
        for item in dspModePopUp.itemArray {
            if let modeRaw = item.representedObject as? String, let m = DSPEngineMode(rawValue: modeRaw) {
                item.isEnabled = !isDLNAActive && usbAvail.isModeSupported(m)
            }
        }
        let effectiveDisplayedMode: DSPEngineMode = (!isDLNAActive && usbAvail.isModeSupported(cfg.mode))
            ? cfg.mode
            : .bitPerfectPassthrough
        if let item = dspModePopUp.itemArray.first(where: { ($0.representedObject as? String) == effectiveDisplayedMode.rawValue }) {
            dspModePopUp.select(item)
        }
        if dspRatePopUp.indexOfItem(withTag: cfg.dsdRate.rawValue) != -1 {
            dspRatePopUp.selectItem(withTag: cfg.dsdRate.rawValue)
        }
        if dspProfilePopUp.indexOfItem(withTag: cfg.profile.rawValue) != -1 {
            dspProfilePopUp.selectItem(withTag: cfg.profile.rawValue)
        }
        if dspTrellisPopUp.indexOfItem(withTag: cfg.trellisOrder.rawValue) != -1 {
            dspTrellisPopUp.selectItem(withTag: cfg.trellisOrder.rawValue)
        }

        let osKey = (cfg.oversamplerBackend == .metalOverlapSave)
            ? "metal:lin"
            : ((cfg.phaseMode == .linearPhase) ? "amx:lin" : "amx:min")
        if let item = dspOversamplerPopUp.itemArray.first(where: { ($0.representedObject as? String) == osKey }) {
            dspOversamplerPopUp.select(item)
        }
        if let item = dspClockPolicyPopUp.itemArray.first(where: { ($0.representedObject as? String) == cfg.clockPolicy.rawValue }) {
            dspClockPolicyPopUp.select(item)
        }
        if let item = dspHeadroomPopUp.itemArray.first(where: {
            guard let val = $0.representedObject as? Double else { return false }
            return abs(val - cfg.headroomDB) < 0.05
        }) {
            dspHeadroomPopUp.select(item)
        }
        if let item = dspNosDitherPopUp.itemArray.first(where: { ($0.representedObject as? String) == cfg.nosDitherMode.rawValue }) {
            dspNosDitherPopUp.select(item)
        }
        dspIsiSwitch.state = cfg.isiRegularizerEnabled ? .on : .off
        dspIspSwitch.state = cfg.ispProtectionEnabled ? .on : .off
        dspHogSwitch.state = cfg.hogModeEnabled ? .on : .off

        let roomSvc = RoomAcousticService.shared
        let roomProfiles = roomSvc.allProfiles()
        let activeRoomProfile = roomSvc.activeProfile
        let isRoomEQActive = roomSvc.isCorrectionEnabled && activeRoomProfile != nil
        if dspRoomProfilePopUp != nil {
            dspRoomProfilePopUp.removeAllItems()
            if roomProfiles.isEmpty {
                dspRoomProfilePopUp.addItem(withTitle: isEn ? "No Measured Profiles" : "Нет профилей замера")
                dspRoomProfilePopUp.isEnabled = false
                dspRoomCorrectionSwitch.state = .off
                dspRoomCorrectionSwitch.isEnabled = false
                dspRoomInspectButton.isEnabled = false
                dspRoomRenameButton.isEnabled = false
                dspRoomDeleteButton.isEnabled = false
                dspRoomStatusLabel.stringValue = isEn
                    ? "Open 'Signal Path' in the PWA on iPhone / iPad for a quick room acoustic measurement"
                    : "Откройте «Тракт сигнала» в PWA на iPhone / iPad для быстрого замера АЧХ"
                dspRoomStatusLabel.textColor = .secondaryLabelColor
            } else {
                dspRoomProfilePopUp.isEnabled = true
                for prof in roomProfiles {
                    dspRoomProfilePopUp.addItem(withTitle: "\(prof.name) (\(prof.eqBands.count) PEQ)")
                    dspRoomProfilePopUp.lastItem?.representedObject = prof.id
                    dspRoomProfilePopUp.lastItem?.toolTip = String(
                        format: isEn
                            ? "%@ • %d PEQ bands • Headroom %.1f dB • Max deviation ±%.1f dB"
                            : "%@ • %d полос PEQ • Запас %.1f дБ • Макс. отклонение ±%.1f дБ",
                        prof.measuredOnDevice, prof.eqBands.count, prof.preampGainDB, prof.maxPeakDeviationDB
                    )
                }
                if let activeID = activeRoomProfile?.id,
                   let matchItem = dspRoomProfilePopUp.itemArray.first(where: { ($0.representedObject as? String) == activeID }) {
                    dspRoomProfilePopUp.select(matchItem)
                }
                dspRoomCorrectionSwitch.isEnabled = true
                dspRoomCorrectionSwitch.state = isRoomEQActive ? .on : .off
                dspRoomInspectButton.isEnabled = (activeRoomProfile != nil)
                dspRoomRenameButton.isEnabled = (activeRoomProfile != nil)
                dspRoomDeleteButton.isEnabled = (activeRoomProfile != nil)

                if let prof = activeRoomProfile {
                    if isRoomEQActive {
                        dspRoomStatusLabel.stringValue = String(
                            format: isEn
                                ? "🟢 Active: %d PEQ • Preamp %.1f dB • %@ (iCloud)"
                                : "🟢 Активна: %d PEQ • Preamp %.1f дБ • %@ (iCloud)",
                            prof.eqBands.count, prof.preampGainDB, prof.measuredOnDevice
                        )
                        dspRoomStatusLabel.textColor = .systemGreen
                    } else {
                        dspRoomStatusLabel.stringValue = String(
                            format: isEn
                                ? "⚪ Off: '%@' (%d PEQ, %.1f dB) — check the box above"
                                : "⚪ Выкл: «%@» (%d PEQ, %.1f дБ) — отметьте флажок выше",
                            prof.name, prof.eqBands.count, prof.preampGainDB
                        )
                        dspRoomStatusLabel.textColor = .secondaryLabelColor
                    }
                }
            }
        }

        let isDSD = !isDLNAActive && usbAvail.supportsDSDDoP && (cfg.mode == .sdmDoP)
        let isNOS = !isDLNAActive && usbAvail.supportsNOS && (cfg.mode == .hqNOSPCM)
        let isActiveDSP = isDSD || isNOS
        dspModePopUp.isEnabled = !isDLNAActive && usbAvail.hasEligibleUSBDAC
        dspRatePopUp.isEnabled = isDSD
        dspProfilePopUp.isEnabled = isDSD
        dspTrellisPopUp.isEnabled = isDSD
        dspIsiSwitch.isEnabled = isDSD
        dspNosDitherPopUp.isEnabled = isNOS || (isDSD && cfg.clockPolicy == .hybrid48kPCM)
        dspOversamplerPopUp.isEnabled = isActiveDSP
        dspClockPolicyPopUp.isEnabled = isActiveDSP
        dspHeadroomPopUp.isEnabled = isActiveDSP
        dspIspSwitch.isEnabled = isActiveDSP
        dspHogSwitch.isEnabled = isActiveDSP

        let mrSvc = MasteringRestorationService.shared
        let activeDeClipMode = mrSvc.deClipMode
        let activeDeEsserMode = mrSvc.deEsserMode
        if dspDeClipPopUp != nil {
            dspDeClipPopUp.isEnabled = true
            if let matchItem = dspDeClipPopUp.itemArray.first(where: { ($0.representedObject as? String) == activeDeClipMode.rawValue }) {
                dspDeClipPopUp.select(matchItem)
            }
        }
        if dspDeEsserPopUp != nil {
            dspDeEsserPopUp.isEnabled = true
            if let matchItem = dspDeEsserPopUp.itemArray.first(where: { ($0.representedObject as? String) == activeDeEsserMode.rawValue }) {
                dspDeEsserPopUp.select(matchItem)
            }
        }

        let activeDRCMode = LateNightDRCService.shared.mode
        if dspLateNightPopUp != nil {
            dspLateNightPopUp.isEnabled = true
            if let matchItem = dspLateNightPopUp.itemArray.first(where: { ($0.representedObject as? String) == activeDRCMode.rawValue }) {
                dspLateNightPopUp.select(matchItem)
            }
        }

        let deClipSuffix = activeDeClipMode.isEnabled ? " + ⚡️ \(activeDeClipMode.shortLabel(isEnglish: isEn))" : ""
        let deEsserSuffix = activeDeEsserMode.isEnabled ? " + 💎 \(activeDeEsserMode.shortLabel(isEnglish: isEn))" : ""
        let drcSuffix = activeDRCMode.isEnabled ? " + 🌙 DRC (\(activeDRCMode.shortLabel(isEnglish: isEn)))" : ""
        let roomSuffix: String = {
            var parts = deClipSuffix + deEsserSuffix
            if isRoomEQActive, let prof = activeRoomProfile {
                parts += " + Auto-PEQ «\(prof.name)»"
            }
            parts += drcSuffix
            return parts
        }()

        if isDLNAActive {
            if isRoomEQActive, let prof = activeRoomProfile {
                dspStatusLabel.stringValue = String(
                    format: isEn
                        ? "🟢 BluOS / DLNA: 64-bit room correction '%@'%@ active (Preamp %.1f dB • DSD/NOS off)"
                        : "🟢 BluOS / DLNA: активна 64-bit коррекция комнаты «%@»%@ (Preamp %.1f дБ • DSD/NOS откл.)",
                    prof.name, drcSuffix, prof.preampGainDB
                )
                dspStatusLabel.textColor = .systemGreen
            } else if activeDRCMode.isEnabled {
                dspStatusLabel.stringValue = isEn
                    ? "🟢 BluOS / DLNA: 64-bit Late-Night DRC '\(activeDRCMode.shortLabel(isEnglish: isEn))' active (DSD/NOS off)"
                    : "🟢 BluOS / DLNA: активен 64-bit ночной контроль динамики «\(activeDRCMode.shortLabel(isEnglish: isEn))» (DSD/NOS откл.)"
                dspStatusLabel.textColor = .systemGreen
            } else {
                dspStatusLabel.stringValue = isEn
                    ? "ℹ️ BluOS / DLNA network output active: DSD / HQ NOS presets disabled (Bit-Perfect PCM stream)"
                    : "ℹ️ Активен сетевой вывод BluOS / DLNA: пресеты DSD / HQ NOS отключены (поток Bit-Perfect PCM)"
                dspStatusLabel.textColor = .secondaryLabelColor
            }
        } else if !isActiveDSP {
            if cfg.mode != .bitPerfectPassthrough && !usbAvail.isModeSupported(cfg.mode) {
                dspStatusLabel.stringValue = isEn
                    ? "ℹ️ No external USB DAC connected: DSD / HQ NOS paused, Bit-Perfect PCM output active\(roomSuffix)"
                    : "ℹ️ Внешний USB ЦАП не подключён: DSD / HQ NOS приостановлены, активен вывод Bit-Perfect PCM\(roomSuffix)"
                dspStatusLabel.textColor = .secondaryLabelColor
            } else if isRoomEQActive, let prof = activeRoomProfile {
                dspStatusLabel.stringValue = String(
                    format: isEn
                        ? "🟢 Local output + 64-bit Auto-PEQ '%@'%@ (%d bands, Preamp %.1f dB)"
                        : "🟢 Локальный вывод + 64-bit Auto-PEQ комнаты «%@»%@ (%d полос, Preamp %.1f дБ)",
                    prof.name, drcSuffix, prof.eqBands.count, prof.preampGainDB
                )
                dspStatusLabel.textColor = .systemGreen
            } else if activeDRCMode.isEnabled {
                dspStatusLabel.stringValue = isEn
                    ? "🟢 Local output + 64-bit Late-Night DRC '\(activeDRCMode.title(isEnglish: isEn))'"
                    : "🟢 Локальный вывод + 64-bit Ночной режим DRC «\(activeDRCMode.title(isEnglish: isEn))»"
                dspStatusLabel.textColor = .systemGreen
            } else {
                dspStatusLabel.stringValue = isEn
                    ? "DSP Status: Bit-Perfect Passthrough (bit-exact transfer without oversampling)"
                    : "Статус DSP: Bit-Perfect Passthrough (побитовая передача без оверсэмплинга)"
                dspStatusLabel.textColor = .secondaryLabelColor
            }
        } else if tel.isRunning {
            let hogStr = tel.isHogModeActive ? "Hog Mode" : "Shared"
            let intStr = tel.isIntegerModeActive ? "Integer" : "Float"
            let cpuStr = String(format: "%.1f%%", tel.processingLoadPercent)
            let bufStr = String(format: "%.0f%%", tel.ringBufferFillPercent)
            if isDSD {
                let mhz = Double(tel.outputSampleRateHz) / 1_000_000.0
                let dopKhz = Double(tel.dopCarrierRateHz) / 1_000.0
                dspStatusLabel.stringValue = String(
                    format: isEn
                        ? "🟢 DSD%d (%.2f MHz / DoP %.1f kHz)%@ • %@ • %@ • CPU %@ • Buffer %@"
                        : "🟢 DSD%d (%.2f МГц / DoP %.1f кГц)%@ • %@ • %@ • CPU %@ • Буфер %@",
                    cfg.dsdRate.rawValue, mhz, dopKhz, roomSuffix, hogStr, intStr, cpuStr, bufStr
                )
            } else {
                let khz = Double(tel.outputSampleRateHz) / 1_000.0
                dspStatusLabel.stringValue = String(
                    format: isEn
                        ? "🟢 HQ NOS PCM %.1f kHz (%@)%@ • %@ • %@ • CPU %@ • Buffer %@"
                        : "🟢 HQ NOS PCM %.1f кГц (%@)%@ • %@ • %@ • CPU %@ • Буфер %@",
                    khz, cfg.nosDitherMode.displayName, roomSuffix, hogStr, intStr, cpuStr, bufStr
                )
            }
            dspStatusLabel.textColor = .systemGreen
        } else {
            dspStatusLabel.stringValue = isEn
                ? "🟠 DSP configured\(roomSuffix) (waiting for Music.app audio stream)"
                : "🟠 DSP сконфигурирован\(roomSuffix) (ожидание захвата аудиопотока Music.app)"
            dspStatusLabel.textColor = .systemOrange
        }
    }

    // MARK: - DSP Actions & Sheet Preset Dialogs

    @objc internal func dspSettingsControlChanged(_ sender: Any?) {
        guard !DLNADiscoveryManager.shared.hasActiveRenderer else {
            refreshDSPControlsState()
            return
        }
        var cfg = AudioEngineController.shared.currentConfigurationSnapshot()

        if let modeRaw = dspModePopUp.selectedItem?.representedObject as? String,
           let mode = DSPEngineMode(rawValue: modeRaw) {
            let usbAvail = AudioEngineController.shared.currentUSBDACAvailability(targetDeviceUID: cfg.targetDeviceUID)
            guard usbAvail.isModeSupported(mode) else {
                refreshDSPControlsState()
                return
            }
            cfg.mode = mode
        }
        if let rate = DSDRateMultiplier(rawValue: dspRatePopUp.selectedTag()) {
            cfg.dsdRate = rate
        }
        if let prof = SDM7Profile(rawValue: dspProfilePopUp.selectedTag()) {
            cfg.profile = prof
        }
        if let trellis = TrellisOrder(rawValue: dspTrellisPopUp.selectedTag()) {
            cfg.trellisOrder = trellis
        }
        if let osRep = dspOversamplerPopUp.selectedItem?.representedObject as? String {
            if osRep == "metal:lin" {
                cfg.oversamplerBackend = .metalOverlapSave
                cfg.phaseMode = .linearPhase
            } else if osRep == "amx:lin" {
                cfg.oversamplerBackend = .accelerateAMX
                cfg.phaseMode = .linearPhase
            } else {
                cfg.oversamplerBackend = .accelerateAMX
                cfg.phaseMode = .minimumPhase
            }
        }
        if let clockRaw = dspClockPolicyPopUp.selectedItem?.representedObject as? String,
           let pol = ClockGridPolicy(rawValue: clockRaw) {
            cfg.clockPolicy = pol
        }
        if let headroomVal = dspHeadroomPopUp.selectedItem?.representedObject as? Double {
            cfg.headroomDB = headroomVal
        }
        if let ditherRaw = dspNosDitherPopUp.selectedItem?.representedObject as? String,
           let dm = NOSPCMDitherMode(rawValue: ditherRaw) {
            cfg.nosDitherMode = dm
        }
        cfg.isiRegularizerEnabled = (dspIsiSwitch.state == .on)
        cfg.ispProtectionEnabled = (dspIspSwitch.state == .on)
        cfg.hogModeEnabled = (dspHogSwitch.state == .on)

        Task {
            await AudioEngineController.shared.updateConfiguration(cfg)
            let payload = WebSocketServer.buildDSPSettingsDictionary()
            WebSocketServer.shared.broadcastEvent(name: "dsp_settings", data: payload)
            WebSocketServer.shared.broadcastAudioDevices()
            WebSocketServer.shared.broadcastStatus(includeQueue: false)
            await MainActor.run {
                self.refreshState()
                MenuManager.shared.updateMenuState()
            }
        }
    }

    @objc internal func dspDeClipModeChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let newMode = MasteringDeClipMode(rawValue: raw) else { return }
        MasteringRestorationService.shared.setDeClipMode(newMode)
        WebSocketServer.shared.broadcastEvent(name: "mastering_restoration_settings", data: MasteringRestorationService.shared.statusDictionary())
        WebSocketServer.shared.broadcastEvent(name: "dsp_settings", data: WebSocketServer.buildDSPSettingsDictionary())
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
        MenuManager.shared.updateMenuState()
        refreshState()
    }

    @objc internal func dspDeEsserModeChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let newMode = MasteringDeEsserMode(rawValue: raw) else { return }
        MasteringRestorationService.shared.setDeEsserMode(newMode)
        WebSocketServer.shared.broadcastEvent(name: "mastering_restoration_settings", data: MasteringRestorationService.shared.statusDictionary())
        WebSocketServer.shared.broadcastEvent(name: "dsp_settings", data: WebSocketServer.buildDSPSettingsDictionary())
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
        MenuManager.shared.updateMenuState()
        refreshState()
    }

    @objc internal func dspLateNightModeChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let newMode = LateNightDRCMode(rawValue: raw) else { return }
        LateNightDRCService.shared.setMode(newMode)
        WebSocketServer.shared.broadcastEvent(name: "late_night_drc_settings", data: LateNightDRCService.shared.statusDictionary())
        WebSocketServer.shared.broadcastEvent(name: "dsp_settings", data: WebSocketServer.buildDSPSettingsDictionary())
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
        MenuManager.shared.updateMenuState()
        refreshState()
    }

    @objc internal func dspPresetSelectionChanged(_ sender: NSPopUpButton) {
        guard !DLNADiscoveryManager.shared.hasActiveRenderer else {
            refreshDSPControlsState()
            return
        }
        guard let presetID = sender.selectedItem?.representedObject as? String,
              presetID != DSPPresetManager.unsavedCustomPresetID else { return }
        if let targetPreset = DSPPresetManager.shared.preset(withID: presetID),
           targetPreset.configuration.mode != .bitPerfectPassthrough {
            let cfg = AudioEngineController.shared.currentConfigurationSnapshot()
            let usbAvail = AudioEngineController.shared.currentUSBDACAvailability(targetDeviceUID: cfg.targetDeviceUID)
            guard usbAvail.isModeSupported(targetPreset.configuration.mode, dsdRate: targetPreset.configuration.dsdRate) else {
                refreshDSPControlsState()
                return
            }
        }
        Task {
            guard await DSPPresetManager.shared.applyPreset(id: presetID) != nil else { return }
            let payload = WebSocketServer.buildDSPSettingsDictionary()
            WebSocketServer.shared.broadcastEvent(name: "dsp_settings", data: payload)
            WebSocketServer.shared.broadcastAudioDevices()
            WebSocketServer.shared.broadcastStatus(includeQueue: false)
            await MainActor.run {
                self.refreshState()
                MenuManager.shared.updateMenuState()
            }
        }
    }

    @objc internal func saveNewDSPPresetClicked() {
        let cfg = AudioEngineController.shared.currentConfigurationSnapshot()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = isEn ? "Save New DSP Preset" : "Сохранить новый пресет DSP"
        alert.informativeText = isEn
            ? "Enter a preset name (\(DSPPresetManager.summarizeConfiguration(cfg))). It will immediately appear in the Web PWA and macOS menu bar:"
            : "Введите название пресета (\(DSPPresetManager.summarizeConfiguration(cfg))). Он сразу появится в Web PWA и верхнем меню macOS:"
        alert.addButton(withTitle: isEn ? "Save" : "Сохранить")
        alert.addButton(withTitle: isEn ? "Cancel" : "Отмена")

        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        let defaultName: String
        switch cfg.mode {
        case .bitPerfectPassthrough:
            defaultName = isEn ? "Custom Bit-Perfect" : "Bit-Perfect Польз."
        case .sdmDoP:
            defaultName = isEn ? "My DSD\(cfg.dsdRate.rawValue) (\(cfg.profile.displayName))" : "Мой DSD\(cfg.dsdRate.rawValue) (\(cfg.profile.displayName))"
        case .hqNOSPCM:
            defaultName = isEn ? "My HQ NOS (\(cfg.nosDitherMode.displayName))" : "Мой HQ NOS (\(cfg.nosDitherMode.displayName))"
        }
        inputField.stringValue = defaultName
        inputField.placeholderString = isEn ? "e.g. Headphones DSD256 Super" : "Например: Наушники DSD256 Super"
        alert.accessoryView = inputField
        alert.window.initialFirstResponder = inputField

        presentAlert(alert) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            _ = DSPPresetManager.shared.saveCustomPreset(name: inputField.stringValue, configuration: cfg)
            self?.broadcastDSPPresetsChanged()
        }
    }

    @objc internal func updateSelectedDSPPresetClicked() {
        let cfg = AudioEngineController.shared.currentConfigurationSnapshot()
        guard let targetID = DSPPresetManager.shared.preferredCustomPresetID(),
              let existing = DSPPresetManager.shared.preset(withID: targetID),
              !existing.isBuiltIn else { return }

        _ = DSPPresetManager.shared.saveCustomPreset(
            name: existing.name,
            configuration: cfg,
            updatingPresetID: targetID
        )
        broadcastDSPPresetsChanged()
    }

    @objc internal func renameSelectedDSPPresetClicked() {
        let cfg = AudioEngineController.shared.currentConfigurationSnapshot()
        let candidateID = DSPPresetManager.shared.matchingPreset(for: cfg).flatMap { $0.isBuiltIn ? nil : $0.id }
            ?? DSPPresetManager.shared.preferredCustomPresetID()
        guard let targetID = candidateID,
              let existing = DSPPresetManager.shared.preset(withID: targetID),
              !existing.isBuiltIn else { return }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = isEn ? "Rename DSP Preset" : "Переименовать пресет DSP"
        alert.informativeText = isEn
            ? "Enter a new name for '\(existing.name)':"
            : "Укажите новое имя для пресета «\(existing.name)»:"
        alert.addButton(withTitle: isEn ? "Save" : "Сохранить")
        alert.addButton(withTitle: isEn ? "Cancel" : "Отмена")

        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        inputField.stringValue = existing.name
        alert.accessoryView = inputField
        alert.window.initialFirstResponder = inputField

        presentAlert(alert) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            _ = DSPPresetManager.shared.renameCustomPreset(id: targetID, newName: inputField.stringValue)
            self?.broadcastDSPPresetsChanged()
        }
    }

    @objc internal func deleteSelectedDSPPresetClicked() {
        let cfg = AudioEngineController.shared.currentConfigurationSnapshot()
        let candidateID = DSPPresetManager.shared.matchingPreset(for: cfg).flatMap { $0.isBuiltIn ? nil : $0.id }
            ?? DSPPresetManager.shared.preferredCustomPresetID()
        guard let targetID = candidateID,
              let existing = DSPPresetManager.shared.preset(withID: targetID),
              !existing.isBuiltIn else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = isEn ? "Delete preset '\(existing.name)'?" : "Удалить пресет «\(existing.name)»?"
        alert.informativeText = isEn
            ? "The preset will be removed from macOS and Web PWA (current DSP parameters will remain active)."
            : "Пресет будет удалён из списка в macOS и Web PWA (текущие параметры DSP останутся активными)."
        alert.addButton(withTitle: isEn ? "Delete" : "Удалить")
        alert.addButton(withTitle: isEn ? "Cancel" : "Отмена")

        presentAlert(alert) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            _ = DSPPresetManager.shared.deleteCustomPreset(id: targetID)
            self?.broadcastDSPPresetsChanged()
        }
    }

    internal func broadcastDSPPresetsChanged() {
        let payload = WebSocketServer.buildDSPSettingsDictionary()
        WebSocketServer.shared.broadcastEvent(name: "dsp_settings", data: payload)
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
        refreshDSPControlsState()
        MenuManager.shared.updateMenuState()
    }
}
