//
//  SettingsWindow+DSPTabBuilder.swift
//  AppleMusicRemoteMac
//
//  Hybrid DSP Engine + 64-bit Room Acoustic Auto-PEQ + Mastering Restoration
//  tab view construction.
//

import AppKit

extension SettingsWindow {
    internal func buildDSPTabView() -> NSView {
        let isEn = SettingsTab.isEn

        dspPresetPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        dspPresetPopUp.controlSize = .regular
        dspPresetPopUp.target = self
        dspPresetPopUp.action = #selector(dspPresetSelectionChanged(_:))
        dspPresetPopUp.widthAnchor.constraint(equalToConstant: 265).isActive = true

        dspSaveNewPresetButton = NSButton(title: isEn ? "+ Save…" : "+ Сохранить…", target: self, action: #selector(saveNewDSPPresetClicked))
        dspSaveNewPresetButton.bezelStyle = .rounded
        dspSaveNewPresetButton.controlSize = .small
        dspSaveNewPresetButton.toolTip = "Сохранить текущие параметры DSP как новый пользовательский пресет"

        dspUpdatePresetButton = NSButton(title: isEn ? "Update" : "Обновить", target: self, action: #selector(updateSelectedDSPPresetClicked))
        dspUpdatePresetButton.bezelStyle = .rounded
        dspUpdatePresetButton.controlSize = .small

        dspRenamePresetButton = NSButton(title: isEn ? "Rename…" : "Имя…", target: self, action: #selector(renameSelectedDSPPresetClicked))
        dspRenamePresetButton.bezelStyle = .rounded
        dspRenamePresetButton.controlSize = .small

        dspDeletePresetButton = NSButton(title: isEn ? "Delete" : "Удалить", target: self, action: #selector(deleteSelectedDSPPresetClicked))
        dspDeletePresetButton.bezelStyle = .rounded
        dspDeletePresetButton.controlSize = .small

        dspCloudSyncButton = NSButton(title: "☁️ iCloud…", target: self, action: #selector(openCloudSyncTabClicked))
        dspCloudSyncButton.bezelStyle = .rounded
        dspCloudSyncButton.controlSize = .small
        dspCloudSyncButton.toolTip = "Облачная синхронизация пресетов DSP, профилей АЧХ комнаты и нормализации треков"

        let presetActionsStack = NSStackView(views: [
            dspSaveNewPresetButton,
            dspUpdatePresetButton,
            dspRenamePresetButton,
            dspDeletePresetButton,
            dspCloudSyncButton
        ])
        presetActionsStack.orientation = .horizontal
        presetActionsStack.alignment = .centerY
        presetActionsStack.spacing = 6

        dspPresetSubtitleLabel = makeMusicSubcaption("Пресеты доступны для быстрого выбора в Web PWA и верхнем меню macOS")

        let presetRightStack = NSStackView(views: [dspPresetPopUp, presetActionsStack, dspPresetSubtitleLabel])
        presetRightStack.orientation = .vertical
        presetRightStack.alignment = .leading
        presetRightStack.spacing = 6
        dspPresetSubtitleLabel.widthAnchor.constraint(equalTo: presetRightStack.widthAnchor).isActive = true

        dspRoomCorrectionSwitch = makeCheckbox(
            title: isEn ? "Enable 64-bit Room Acoustic Correction (Auto-PEQ)" : "Включить 64-битную коррекцию акустики комнаты (Auto-PEQ)",
            action: #selector(roomCorrectionSwitchToggled(_:))
        )

        dspRoomProfilePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        dspRoomProfilePopUp.controlSize = .small
        dspRoomProfilePopUp.target = self
        dspRoomProfilePopUp.action = #selector(roomProfileSelectionChanged(_:))
        dspRoomProfilePopUp.widthAnchor.constraint(equalToConstant: 195).isActive = true

        dspRoomInspectButton = NSButton(title: isEn ? "📈 Graph & PEQ…" : "📈 АЧХ и фильтры…", target: self, action: #selector(showRoomProfileInspectorClicked))
        dspRoomInspectButton.bezelStyle = .rounded
        dspRoomInspectButton.controlSize = .small

        dspRoomRenameButton = NSButton(title: isEn ? "Rename…" : "Имя…", target: self, action: #selector(renameSelectedRoomProfileClicked))
        dspRoomRenameButton.bezelStyle = .rounded
        dspRoomRenameButton.controlSize = .small

        dspRoomDeleteButton = NSButton(title: isEn ? "Delete" : "Удалить", target: self, action: #selector(deleteSelectedRoomProfileClicked))
        dspRoomDeleteButton.bezelStyle = .rounded
        dspRoomDeleteButton.controlSize = .small

        let roomControlsRow = NSStackView(views: [
            dspRoomProfilePopUp,
            dspRoomInspectButton,
            dspRoomRenameButton,
            dspRoomDeleteButton
        ])
        roomControlsRow.orientation = .horizontal
        roomControlsRow.alignment = .centerY
        roomControlsRow.spacing = 6

        dspRoomStatusLabel = makeStatusCaption("Замерьте АЧХ микрофоном iPhone / iPad в PWA (окно «Тракт сигнала»)")
        dspRoomStatusLabel.lineBreakMode = .byWordWrapping

        let roomIndentedDetails = NSStackView(views: [roomControlsRow, dspRoomStatusLabel])
        roomIndentedDetails.orientation = .vertical
        roomIndentedDetails.alignment = .leading
        roomIndentedDetails.spacing = 5
        dspRoomStatusLabel.widthAnchor.constraint(equalTo: roomIndentedDetails.widthAnchor).isActive = true
        let roomIndentedWrap = makeIndentedViewContainer(roomIndentedDetails)

        let roomRightStack = NSStackView(views: [dspRoomCorrectionSwitch, roomIndentedWrap])
        roomRightStack.orientation = .vertical
        roomRightStack.alignment = .leading
        roomRightStack.spacing = 6
        roomIndentedWrap.widthAnchor.constraint(equalTo: roomRightStack.widthAnchor).isActive = true

        let configurePopUp: (NSPopUpButton, CGFloat) -> Void = { pop, width in
            pop.controlSize = .regular
            pop.target = self
            pop.action = #selector(self.dspSettingsControlChanged(_:))
            pop.widthAnchor.constraint(equalToConstant: width).isActive = true
        }

        dspModePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        configurePopUp(dspModePopUp, 325)
        let modeItems: [(String, DSPEngineMode)] = [
            ("Bit-Perfect Passthrough (Выкл)", .bitPerfectPassthrough),
            ("DSD DoP (7-порядковый 7EC SDM)", .sdmDoP),
            ("HQ NOS PCM (705.6/768 кГц LNS15)", .hqNOSPCM)
        ]
        for (title, m) in modeItems {
            dspModePopUp.addItem(withTitle: title)
            dspModePopUp.lastItem?.representedObject = m.rawValue
        }

        dspRatePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        configurePopUp(dspRatePopUp, 325)
        let rateItems: [(String, Int)] = [
            ("DSD64 (2.82 МГц / DoP 176.4)", 64),
            ("DSD128 (5.64 МГц / DoP 352.8)", 128),
            ("DSD256 (11.29 МГц / DoP 705.6)", 256),
            ("DSD512 (22.58 МГц / DoP 1411.2)", 512)
        ]
        for (title, tag) in rateItems {
            dspRatePopUp.addItem(withTitle: title)
            dspRatePopUp.lastItem?.tag = tag
        }

        dspProfilePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        configurePopUp(dspProfilePopUp, 325)
        let profItems: [(String, Int)] = [
            ("7EC-Transient (OBG 1.38 — Панч)", SDM7Profile.transient.rawValue),
            ("7EC-Balanced (OBG 1.50 — Референс)", SDM7Profile.balanced.rawValue),
            ("7EC-Super (OBG 1.62 — Макс. глубина)", SDM7Profile.superWide.rawValue)
        ]
        for (title, tag) in profItems {
            dspProfilePopUp.addItem(withTitle: title)
            dspProfilePopUp.lastItem?.tag = tag
        }

        dspTrellisPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        configurePopUp(dspTrellisPopUp, 325)
        let trellisItems: [(String, Int)] = [
            ("Greedy M=1 (2-шаговый Look-Ahead)", 1),
            ("Trellis M=4 (4 пути Витерби)", 4),
            ("Trellis M=8 (Оптимум для M1–M4)", 8),
            ("Trellis M=16 (Макс. удержание)", 16)
        ]
        for (title, tag) in trellisItems {
            dspTrellisPopUp.addItem(withTitle: title)
            dspTrellisPopUp.lastItem?.tag = tag
        }

        dspOversamplerPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        configurePopUp(dspOversamplerPopUp, 325)
        let osItems: [(String, String)] = [
            ("Accelerate AMX FP64 (Min-Phase)", "amx:min"),
            ("Accelerate AMX FP64 (Linear-Phase)", "amx:lin"),
            ("Metal GPU Sinc-M (df64 Overlap-Save)", "metal:lin")
        ]
        for (title, rep) in osItems {
            dspOversamplerPopUp.addItem(withTitle: title)
            dspOversamplerPopUp.lastItem?.representedObject = rep
        }

        dspClockPolicyPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        configurePopUp(dspClockPolicyPopUp, 325)
        let clockItems: [(String, ClockGridPolicy)] = [
            ("Adaptive Dual-Grid (44.1k / 48k)", .adaptiveDualGrid),
            ("Strict SACD 44.1k (ASRC для 48k)", .strictSACD44k1),
            ("Hybrid 48k -> HQ NOS PCM (LNS15)", .hybrid48kPCM)
        ]
        for (title, pol) in clockItems {
            dspClockPolicyPopUp.addItem(withTitle: title)
            dspClockPolicyPopUp.lastItem?.representedObject = pol.rawValue
        }

        dspHeadroomPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        configurePopUp(dspHeadroomPopUp, 325)
        let headroomItems: [(String, Double)] = [
            ("-2.5 дБ (Высокий уровень)", -2.5),
            ("-3.0 дБ (Стандарт DSD)", -3.0),
            ("-3.5 дБ (Референс SACD 7EC)", -3.5),
            ("-4.5 дБ (Макс. запас пиков)", -4.5),
            ("-6.0 дБ (Студийный мастер)", -6.0)
        ]
        for (title, db) in headroomItems {
            dspHeadroomPopUp.addItem(withTitle: title)
            dspHeadroomPopUp.lastItem?.representedObject = db
        }

        dspNosDitherPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        configurePopUp(dspNosDitherPopUp, 325)
        let ditherItems: [(String, NOSPCMDitherMode)] = [
            ("LNS15 (Психоакустический 15-го порядка)", .lns15),
            ("TPDF (Линейный треугольный дизеринг)", .tpdf)
        ]
        for (title, dm) in ditherItems {
            dspNosDitherPopUp.addItem(withTitle: title)
            dspNosDitherPopUp.lastItem?.representedObject = dm.rawValue
        }

        dspDeClipPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        dspDeClipPopUp.controlSize = .regular
        dspDeClipPopUp.target = self
        dspDeClipPopUp.action = #selector(dspDeClipModeChanged(_:))
        dspDeClipPopUp.widthAnchor.constraint(equalToConstant: 325).isActive = true
        for m in MasteringDeClipMode.allCases {
            dspDeClipPopUp.addItem(withTitle: m.title(isEnglish: isEn))
            dspDeClipPopUp.lastItem?.representedObject = m.rawValue
            dspDeClipPopUp.lastItem?.toolTip = m.subtitle(isEnglish: isEn)
        }

        dspDeEsserPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        dspDeEsserPopUp.controlSize = .regular
        dspDeEsserPopUp.target = self
        dspDeEsserPopUp.action = #selector(dspDeEsserModeChanged(_:))
        dspDeEsserPopUp.widthAnchor.constraint(equalToConstant: 325).isActive = true
        for m in MasteringDeEsserMode.allCases {
            dspDeEsserPopUp.addItem(withTitle: m.title(isEnglish: isEn))
            dspDeEsserPopUp.lastItem?.representedObject = m.rawValue
            dspDeEsserPopUp.lastItem?.toolTip = m.subtitle(isEnglish: isEn)
        }

        dspLateNightPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        dspLateNightPopUp.controlSize = .regular
        dspLateNightPopUp.target = self
        dspLateNightPopUp.action = #selector(dspLateNightModeChanged(_:))
        dspLateNightPopUp.widthAnchor.constraint(equalToConstant: 325).isActive = true
        for m in LateNightDRCMode.allCases {
            dspLateNightPopUp.addItem(withTitle: m.title(isEnglish: isEn))
            dspLateNightPopUp.lastItem?.representedObject = m.rawValue
            dspLateNightPopUp.lastItem?.toolTip = m.subtitle(isEnglish: isEn)
        }

        dspIsiSwitch = makeCheckbox(
            title: isEn ? "Inter-Symbol Interference regularizer (ISI)" : "Подавитель межсимвольной интерференции (ISI)",
            action: #selector(dspSettingsControlChanged(_:))
        )
        dspIspSwitch = makeCheckbox(
            title: isEn ? "True Peak inter-sample overload protection (ISP)" : "Защита от межсэмпловых пиков (True Peak ISP)",
            action: #selector(dspSettingsControlChanged(_:))
        )
        dspHogSwitch = makeCheckbox(
            title: isEn ? "Exclusive DAC access (Hog & Integer Mode)" : "Эксклюзивный захват ЦАП (Hog & Integer Mode)",
            action: #selector(dspSettingsControlChanged(_:))
        )

        dspStatusLabel = makeStatusCaption("DSP: Bit-Perfect Passthrough (без конвертации)")
        dspStatusLabel.lineBreakMode = .byWordWrapping
        dspStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        return makeMusicPreferencePage(sections: [
            [
                makeMusicTwoColumnRow(category: isEn ? "DSP Preset:" : "Пресет DSP:", rightContent: presetRightStack, topLabelOffset: 3)
            ],
            [
                makeMusicTwoColumnRow(category: isEn ? "Room EQ:" : "АЧХ комнаты:", rightContent: roomRightStack, topLabelOffset: 1)
            ],
            [
                makeMusicControlRow(category: isEn ? "Engine Mode:" : "Режим движка:", control: dspModePopUp, subtitle: nil),
                makeMusicControlRow(category: isEn ? "DSD Rate:" : "Кратность DSD:", control: dspRatePopUp, subtitle: nil),
                makeMusicControlRow(category: isEn ? "7EC Profile:" : "Профиль 7EC:", control: dspProfilePopUp, subtitle: nil),
                makeMusicControlRow(category: "Trellis Viterbi:", control: dspTrellisPopUp, subtitle: nil),
                makeMusicControlRow(category: isEn ? "Oversampler:" : "Оверсэмплер:", control: dspOversamplerPopUp, subtitle: nil),
                makeMusicCheckboxRow(
                    category: "",
                    checkbox: dspIsiSwitch,
                    subtitle: isEn
                        ? "Transition density regularization to lower DAC even-order distortion."
                        : "Регуляризация плотности фронтов переключения 1-битного потока."
                )
            ],
            [
                makeMusicControlRow(category: "De-Clipper:", control: dspDeClipPopUp, subtitle: nil),
                makeMusicControlRow(category: "De-Esser:", control: dspDeEsserPopUp, subtitle: nil),
                makeMusicControlRow(category: isEn ? "Night Mode:" : "Ночной режим:", control: dspLateNightPopUp, subtitle: nil)
            ],
            [
                makeMusicControlRow(category: isEn ? "Clock Policy:" : "Тактовая сетка:", control: dspClockPolicyPopUp, subtitle: nil),
                makeMusicControlRow(category: "Headroom:", control: dspHeadroomPopUp, subtitle: nil),
                makeMusicControlRow(category: isEn ? "NOS Dither:" : "Шейпер NOS:", control: dspNosDitherPopUp, subtitle: nil),
                makeMusicCheckboxRow(category: "", checkbox: dspIspSwitch, subtitle: nil),
                makeMusicCheckboxRow(category: "", checkbox: dspHogSwitch, subtitle: nil),
                makeMusicTwoColumnRow(category: isEn ? "Status:" : "Состояние:", rightContent: dspStatusLabel, topLabelOffset: 0)
            ]
        ], compactSpacing: true)
    }
}
