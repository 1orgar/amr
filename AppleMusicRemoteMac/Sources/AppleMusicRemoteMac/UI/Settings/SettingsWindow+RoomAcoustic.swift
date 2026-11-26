//
//  SettingsWindow+RoomAcoustic.swift
//  AppleMusicRemoteMac
//
//  64-bit Room Acoustic Auto-PEQ frequency response chart view, profile
//  management actions (sheet alerts), and RBJ filter inspector sheet.
//

import AppKit

internal final class RoomAcousticChartView: NSView {
    var profile: RoomAcousticProfile? {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let boundsRect = bounds
        NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.11, alpha: 1.0).setFill()
        boundsRect.fill()

        let padLeft: CGFloat = 40
        let padRight: CGFloat = 16
        let padTop: CGFloat = 24
        let padBottom: CGFloat = 24
        let plot = NSRect(
            x: padLeft,
            y: padBottom,
            width: max(40, boundsRect.width - padLeft - padRight),
            height: max(40, boundsRect.height - padTop - padBottom)
        )

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.62, alpha: 1.0)
        ]

        let yForDB: (Double) -> CGFloat = { db in
            let clamped = max(-16.0, min(16.0, db))
            let norm = (clamped + 16.0) / 32.0
            return plot.minY + CGFloat(norm) * plot.height
        }

        for dbTick in [-12.0, -6.0, 0.0, 6.0, 12.0] {
            let y = yForDB(dbTick)
            let path = NSBezierPath()
            path.move(to: NSPoint(x: plot.minX, y: y))
            path.line(to: NSPoint(x: plot.maxX, y: y))
            if abs(dbTick) < 0.01 {
                NSColor(calibratedWhite: 0.42, alpha: 0.65).setStroke()
                path.setLineDash([4, 3], count: 2, phase: 0)
            } else {
                NSColor(calibratedWhite: 0.28, alpha: 0.40).setStroke()
            }
            path.lineWidth = 1.0
            path.stroke()

            let txt = dbTick > 0 ? "+\(Int(dbTick))" : "\(Int(dbTick))"
            (txt as NSString).draw(at: NSPoint(x: 8, y: y - 6), withAttributes: labelAttrs)
        }

        let bands = profile?.bandsHz.isEmpty == false ? (profile?.bandsHz ?? RoomAcousticService.isoThirdOctaveBandsHz) : RoomAcousticService.isoThirdOctaveBandsHz
        let count = max(2, bands.count)
        let xForIndex: (Int) -> CGFloat = { idx in
            plot.minX + (CGFloat(idx) / CGFloat(count - 1)) * plot.width
        }

        let chartIsEn = SettingsTab.isEn
        let tickIndices: [(Int, String)] = chartIsEn
            ? [(0, "20 Hz"), (7, "100 Hz"), (17, "1 kHz"), (27, "10 kHz"), (min(count - 1, 30), "20 kHz")]
            : [(0, "20 Гц"), (7, "100 Гц"), (17, "1 кГц"), (27, "10 кГц"), (min(count - 1, 30), "20 кГц")]
        for (idx, title) in tickIndices where idx < count {
            let x = xForIndex(idx)
            let vPath = NSBezierPath()
            vPath.move(to: NSPoint(x: x, y: plot.minY))
            vPath.line(to: NSPoint(x: x, y: plot.maxY))
            NSColor(calibratedWhite: 0.28, alpha: 0.35).setStroke()
            vPath.lineWidth = 1.0
            vPath.stroke()

            let sz = (title as NSString).size(withAttributes: labelAttrs)
            let drawX = min(boundsRect.maxX - sz.width - 4, max(plot.minX - 4, x - sz.width * 0.5))
            (title as NSString).draw(at: NSPoint(x: drawX, y: 5), withAttributes: labelAttrs)
        }

        let strokeCurve: ([Double], NSColor, CGFloat, Bool) -> Void = { values, color, width, dashed in
            guard values.count >= 2 else { return }
            let path = NSBezierPath()
            let limit = min(count, values.count)
            for i in 0..<limit {
                let pt = NSPoint(x: xForIndex(i), y: yForDB(values[i]))
                if i == 0 { path.move(to: pt) } else { path.line(to: pt) }
            }
            color.setStroke()
            path.lineWidth = width
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            if dashed { path.setLineDash([5, 3], count: 2, phase: 0) }
            path.stroke()
        }

        if let prof = profile {
            strokeCurve(prof.targetCurveDB, NSColor(calibratedRed: 0.62, green: 0.68, blue: 0.78, alpha: 0.85), 1.4, true)
            strokeCurve(prof.measuredResponseDB, NSColor.systemOrange.withAlphaComponent(0.92), 1.8, false)
            strokeCurve(prof.correctedResponseDB, NSColor.systemGreen, 2.2, false)
        }

        let legendItems: [(String, NSColor)] = chartIsEn
            ? [
                ("Harman Target", NSColor(calibratedRed: 0.62, green: 0.68, blue: 0.78, alpha: 0.95)),
                ("Mic Measurement", NSColor.systemOrange),
                ("Auto-PEQ Corrected", NSColor.systemGreen)
            ]
            : [
                ("Целевая Harman", NSColor(calibratedRed: 0.62, green: 0.68, blue: 0.78, alpha: 0.95)),
                ("Замер микрофона", NSColor.systemOrange),
                ("С коррекцией Auto-PEQ", NSColor.systemGreen)
            ]
        var cursorX = plot.minX
        let legendY = boundsRect.maxY - 17
        for (title, color) in legendItems {
            let dotRect = NSRect(x: cursorX, y: legendY + 3, width: 8, height: 8)
            color.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            cursorX += 12
            let itemAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor(calibratedWhite: 0.84, alpha: 1.0)
            ]
            let sz = (title as NSString).size(withAttributes: itemAttrs)
            (title as NSString).draw(at: NSPoint(x: cursorX, y: legendY), withAttributes: itemAttrs)
            cursorX += sz.width + 16
        }

        NSColor(calibratedWhite: 1.0, alpha: 0.12).setStroke()
        let border = NSBezierPath(roundedRect: boundsRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        border.lineWidth = 1.0
        border.stroke()
    }
}

extension SettingsWindow {
    internal func broadcastRoomAcousticChanged() {
        let roomPayload = RoomAcousticService.shared.statusDictionary()
        WebSocketServer.shared.broadcastEvent(name: "room_acoustic_settings", data: roomPayload)
        WebSocketServer.shared.broadcastEvent(name: "dsp_settings", data: WebSocketServer.buildDSPSettingsDictionary())
        WebSocketServer.shared.broadcastStatus(includeQueue: false)
        refreshDSPControlsState()
        MenuManager.shared.updateMenuState()
    }

    @objc internal func roomCorrectionSwitchToggled(_ sender: NSButton) {
        RoomAcousticService.shared.setCorrectionEnabled(sender.state == .on)
        broadcastRoomAcousticChanged()
    }

    @objc internal func roomProfileSelectionChanged(_ sender: NSPopUpButton) {
        guard let profID = sender.selectedItem?.representedObject as? String, !profID.isEmpty else { return }
        _ = RoomAcousticService.shared.selectProfile(id: profID)
        broadcastRoomAcousticChanged()
    }

    @objc internal func renameSelectedRoomProfileClicked() {
        guard let active = RoomAcousticService.shared.activeProfile else { return }
        let profileID = active.id
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = isEn ? "Rename Room Acoustic Profile" : "Переименовать профиль АЧХ комнаты"
        alert.informativeText = isEn
            ? "Enter a new name for '\(active.name)' (changes sync with iCloud Drive and PWA):"
            : "Укажите новое название для профиля «\(active.name)» (изменения синхронизируются с iCloud Drive и PWA):"
        alert.addButton(withTitle: isEn ? "Save" : "Сохранить")
        alert.addButton(withTitle: isEn ? "Cancel" : "Отмена")

        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        inputField.stringValue = active.name
        inputField.placeholderString = isEn ? "e.g. Living Room (Rotel + KEF)" : "Например: Гостиная (Rotel + KEF)"
        alert.accessoryView = inputField
        alert.window.initialFirstResponder = inputField

        presentAlert(alert) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            guard RoomAcousticService.shared.renameProfile(id: profileID, newName: inputField.stringValue) != nil else { return }
            self?.broadcastRoomAcousticChanged()
        }
    }

    @objc internal func deleteSelectedRoomProfileClicked() {
        guard let active = RoomAcousticService.shared.activeProfile else { return }
        let profileID = active.id
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = isEn ? "Delete room profile '\(active.name)'?" : "Удалить профиль АЧХ «\(active.name)»?"
        alert.informativeText = isEn
            ? "This room measurement profile will be removed from this Mac and iCloud Drive."
            : "Профиль замера комнаты будет удалён на этом Mac и в облаке iCloud Drive."
        alert.addButton(withTitle: isEn ? "Delete" : "Удалить")
        alert.addButton(withTitle: isEn ? "Cancel" : "Отмена")

        presentAlert(alert) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            guard RoomAcousticService.shared.deleteProfile(id: profileID) else { return }
            self?.broadcastRoomAcousticChanged()
        }
    }

    @objc internal func showRoomProfileInspectorClicked() {
        guard let prof = RoomAcousticService.shared.activeProfile, let parentWin = self.window else { return }
        closeRoomProfileInspectorSheet()

        let sheetWidth: CGFloat = 620
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: sheetWidth, height: 460),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheet.isReleasedWhenClosed = false

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 16, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false

        let dateStr = DateFormatter.localizedString(
            from: Date(timeIntervalSince1970: prof.updatedAt),
            dateStyle: .medium,
            timeStyle: .short
        )
        let isEnabled = RoomAcousticService.shared.isCorrectionEnabled
        let statusPill = isEnabled
            ? (isEn ? "🟢 64-bit Auto-PEQ Active" : "🟢 64-bit Auto-PEQ активна")
            : (isEn ? "⚪ Auto-PEQ Disabled (Bypass)" : "⚪ Auto-PEQ выключена (Bypass)")

        let titleLabel = NSTextField(
            labelWithString: isEn ? "Room Acoustic Profile '\(prof.name)'" : "Акустический профиль «\(prof.name)»"
        )
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .bold)

        let metaText = String(
            format: isEn
                ? "%@ • Mic: %@ • Measured: %@ • Deviation: ±%.1f dB • Preamp Headroom: %.1f dB"
                : "%@ • Микрофон: %@ • Замер: %@ • Отклонение АЧХ: ±%.1f дБ • Preamp Headroom: %.1f дБ",
            statusPill, prof.measuredOnDevice, dateStr, prof.maxPeakDeviationDB, prof.preampGainDB
        )
        let metaLabel = NSTextField(wrappingLabelWithString: metaText)
        metaLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        metaLabel.textColor = .secondaryLabelColor

        let chartView = RoomAcousticChartView(frame: NSRect(x: 0, y: 0, width: sheetWidth - 40, height: 190))
        chartView.profile = prof
        chartView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            chartView.widthAnchor.constraint(equalToConstant: sheetWidth - 40),
            chartView.heightAnchor.constraint(equalToConstant: 190)
        ])

        let bandsHeader = NSTextField(
            labelWithString: isEn
                ? "Synthesized 64-bit RBJ Biquad Filters (\(prof.eqBands.count) of \(RoomEQProcessor.maxStages)):"
                : "Синтезированные 64-bit биквадратные фильтры RBJ (\(prof.eqBands.count) из \(RoomEQProcessor.maxStages)):"
        )
        bandsHeader.font = NSFont.systemFont(ofSize: 12, weight: .semibold)

        let bandsCard = SettingsCardView()
        bandsCard.translatesAutoresizingMaskIntoConstraints = false
        let bandsStack = NSStackView()
        bandsStack.orientation = .vertical
        bandsStack.alignment = .leading
        bandsStack.spacing = 5
        bandsStack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        bandsStack.translatesAutoresizingMaskIntoConstraints = false

        if prof.eqBands.isEmpty {
            let flatLabel = NSTextField(
                labelWithString: isEn
                    ? "Room response already closely matches the Harman target curve (deviations < 1.4 dB, no correction needed)."
                    : "АЧХ комнаты уже близка к целевой кривой Harman (отклонения < 1.4 дБ, коррекция не требуется)."
            )
            flatLabel.font = NSFont.systemFont(ofSize: 11.5)
            flatLabel.textColor = .secondaryLabelColor
            bandsStack.addArrangedSubview(flatLabel)
        } else {
            for (idx, band) in prof.eqBands.enumerated() {
                let freqStr = band.frequencyHz >= 1000
                    ? String(format: isEn ? "%.2f kHz" : "%.2f кГц", band.frequencyHz / 1000.0)
                    : String(format: isEn ? "%.0f Hz" : "%.0f Гц", band.frequencyHz)
                let sign = band.gainDB >= 0 ? "+" : ""
                let roleStr = band.gainDB < 0
                    ? (band.frequencyHz <= 300
                        ? (isEn ? "room standing-mode / boom cut" : "срез комнатной стоячей моды / гула")
                        : (isEn ? "resonance peak taming" : "смягчение резонансного пика"))
                    : (isEn ? "gentle acoustic dip fill" : "деликатная компенсация акустического провала")
                let line = String(
                    format: isEn
                        ? "%d. %@   •   %@%.1f dB   •   Q = %.2f   (%@)"
                        : "%d. %@   •   %@%.1f дБ   •   Q = %.2f   (%@)",
                    idx + 1, freqStr, sign, band.gainDB, band.q, roleStr
                )
                let lbl = NSTextField(labelWithString: line)
                lbl.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
                lbl.textColor = band.gainDB < 0 ? .labelColor : .secondaryLabelColor
                bandsStack.addArrangedSubview(lbl)
            }
        }

        bandsCard.addSubview(bandsStack)
        NSLayoutConstraint.activate([
            bandsStack.topAnchor.constraint(equalTo: bandsCard.topAnchor),
            bandsStack.leadingAnchor.constraint(equalTo: bandsCard.leadingAnchor),
            bandsStack.trailingAnchor.constraint(equalTo: bandsCard.trailingAnchor),
            bandsStack.bottomAnchor.constraint(equalTo: bandsCard.bottomAnchor),
            bandsCard.widthAnchor.constraint(equalToConstant: sheetWidth - 40)
        ])

        let soundHint = NSTextField(
            wrappingLabelWithString: isEn
                ? "Sonic impact: narrow negative filters (down to -9 dB) remove boomy bass standing waves to clear up midbass and vocal definition, while wide gentle shelves (up to +3.5 dB) fill acoustic dips with automatic Preamp Headroom to prevent clipping."
                : "Как влияет на звук: узкие отрицательные фильтры (до -9 дБ) убирают гудящие стоячие волны комнаты в басу, очищая разборчивость мидбаса и вокала, а широкие плавные подъёмы (не более +3.5 дБ) бережно заполняют провалы с автоматическим запасом Preamp Headroom без клиппинга."
        )
        soundHint.font = NSFont.systemFont(ofSize: 11)
        soundHint.textColor = .secondaryLabelColor
        soundHint.preferredMaxLayoutWidth = sheetWidth - 40

        let toggleBtn = NSButton(
            title: isEnabled
                ? (isEn ? "Disable Auto-PEQ" : "Выключить Auto-PEQ")
                : (isEn ? "Enable Auto-PEQ" : "Включить Auto-PEQ"),
            target: self,
            action: #selector(toggleRoomEQFromInspectorSheetClicked)
        )
        toggleBtn.bezelStyle = .rounded

        let closeBtn = NSButton(title: isEn ? "Close" : "Закрыть", target: self, action: #selector(closeRoomProfileInspectorSheet))
        closeBtn.bezelStyle = .rounded
        closeBtn.keyEquivalent = "\r"

        let btnSpacer = NSView()
        btnSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footerRow = NSStackView(views: [toggleBtn, btnSpacer, closeBtn])
        footerRow.orientation = .horizontal
        footerRow.alignment = .centerY
        footerRow.translatesAutoresizingMaskIntoConstraints = false

        for v in [titleLabel, metaLabel, chartView, bandsHeader, bandsCard, soundHint, footerRow] {
            root.addArrangedSubview(v)
        }
        footerRow.widthAnchor.constraint(equalToConstant: sheetWidth - 40).isActive = true

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: sheetWidth, height: 460))
        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            root.widthAnchor.constraint(equalToConstant: sheetWidth)
        ])
        contentView.layoutSubtreeIfNeeded()
        let fittedH = max(380, ceil(root.fittingSize.height))
        sheet.setContentSize(NSSize(width: sheetWidth, height: fittedH))
        sheet.contentView = contentView

        activeRoomInspectorSheetWindow = sheet
        parentWin.beginSheet(sheet, completionHandler: nil)
    }

    @objc internal func toggleRoomEQFromInspectorSheetClicked() {
        let next = !RoomAcousticService.shared.isCorrectionEnabled
        RoomAcousticService.shared.setCorrectionEnabled(next)
        broadcastRoomAcousticChanged()
        closeRoomProfileInspectorSheet()
    }

    @objc internal func closeRoomProfileInspectorSheet() {
        if let sheet = activeRoomInspectorSheetWindow {
            if let parent = self.window {
                parent.endSheet(sheet)
            }
            sheet.orderOut(nil)
        }
        activeRoomInspectorSheetWindow = nil
    }
}
