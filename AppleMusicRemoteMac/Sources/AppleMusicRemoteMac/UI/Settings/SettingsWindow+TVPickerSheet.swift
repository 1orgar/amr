//
//  SettingsWindow+TVPickerSheet.swift
//  AppleMusicRemoteMac
//
//  Virtualized NSTableView playlist/album picker sheet for StandBy TV Mode
//  with 100ms debounced search filtering for large libraries.
//

import AppKit

extension SettingsWindow {
    private static let tvPickerCellIdentifier = NSUserInterfaceItemIdentifier("TVPickerCheckboxCell")

    internal func presentTVPlaylistsPickerSheet() {
        guard let parentWin = self.window else { return }
        closeTVPickerSheet()

        activeTVPickerKind = .playlists
        tvPickerIsLoading = true
        tvPickerLoadGeneration &+= 1
        let gen = tvPickerLoadGeneration
        let savedNames = TVLibraryConfigurationStore.shared.current.selectedPlaylistNames
        tvPickerSelectedKeys = Set(
            savedNames
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )

        let sheet = makeTVPickerSheetWindow(
            width: 440,
            height: 420,
            symbol: "music.note.list",
            title: isEn ? "Select Playlists for TV Mode" : "Выбор плейлистов для ТВ-режима",
            subtitle: isEn
                ? "Checked playlists appear in StandBy TV Library"
                : "Отмеченные плейлисты отображаются в «Медиатеке» ТВ-режима",
            searchPlaceholder: isEn ? "Filter playlists…" : "Поиск по названию плейлиста…"
        )
        activeTVPickerSheetWindow = sheet
        rebuildTVPickerCheckboxList()
        parentWin.beginSheet(sheet, completionHandler: nil)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fetched = LibraryService.shared.getPlaylists()
            Task { @MainActor [weak self] in
                guard let self = self, self.tvPickerLoadGeneration == gen, self.activeTVPickerSheetWindow != nil else { return }
                self.didLoadTVPickerPlaylists(fetched, savedNames: savedNames)
            }
        }
    }

    private func didLoadTVPickerPlaylists(_ fetched: [PlaylistInfo], savedNames: [String]) {
        var entries: [TVPlaylistPickerEntry] = []
        var seen = Set<String>()

        for pl in fetched {
            let trimmed = pl.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            entries.append(TVPlaylistPickerEntry(name: trimmed, trackCount: pl.trackCount))
        }
        for saved in savedNames {
            let trimmed = saved.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                entries.append(TVPlaylistPickerEntry(name: trimmed, trackCount: nil))
            }
        }

        tvPickerPlaylistEntries = entries
        tvPickerIsLoading = false
        tvPickerDoneButton?.isEnabled = true
        tvPickerSelectAllButton?.isEnabled = !entries.isEmpty
        tvPickerDeselectAllButton?.isEnabled = !entries.isEmpty
        rebuildTVPickerCheckboxList()
    }

    internal func presentTVAlbumsPickerSheet() {
        guard let parentWin = self.window else { return }
        closeTVPickerSheet()

        activeTVPickerKind = .albums
        tvPickerIsLoading = true
        tvPickerLoadGeneration &+= 1
        let gen = tvPickerLoadGeneration
        let savedAlbums = TVLibraryConfigurationStore.shared.current.selectedAlbums
        var initialKeys = Set<String>()
        for sel in savedAlbums {
            let k = !sel.key.isEmpty
                ? sel.key
                : TVLibraryConfigurationStore.makeAlbumSelectionKey(name: sel.name, artist: sel.artist)
            if !k.isEmpty {
                initialKeys.insert(k)
            }
        }
        tvPickerSelectedKeys = initialKeys

        let sheet = makeTVPickerSheetWindow(
            width: 460,
            height: 440,
            symbol: "square.stack.fill",
            title: isEn ? "Select Albums for TV Mode" : "Выбор альбомов для ТВ-режима",
            subtitle: isEn
                ? "Checked albums appear as tiles in StandBy TV Library"
                : "Отмеченные альбомы отображаются плитками в «Медиатеке» ТВ-режима",
            searchPlaceholder: isEn ? "Filter by album or artist…" : "Поиск по названию альбома или артисту…"
        )
        activeTVPickerSheetWindow = sheet
        rebuildTVPickerCheckboxList()
        parentWin.beginSheet(sheet, completionHandler: nil)

        Task { [weak self] in
            let fetched = await Task.detached(priority: .userInitiated) {
                await MusicBridge.shared.getLibraryAlbumsMerged(forceRefresh: false)
            }.value
            guard let self = self, self.tvPickerLoadGeneration == gen, self.activeTVPickerSheetWindow != nil else { return }
            self.didLoadTVPickerAlbums(fetched, savedAlbums: savedAlbums)
        }
    }

    private func didLoadTVPickerAlbums(_ fetched: [AlbumInfo], savedAlbums: [TVLibraryAlbumSelection]) {
        var entries: [TVAlbumPickerEntry] = []
        var seen = Set<String>()

        for alb in fetched {
            let cleanName = alb.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanArtist = alb.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty || !cleanArtist.isEmpty else { continue }
            let key = TVLibraryConfigurationStore.makeAlbumSelectionKey(name: cleanName, artist: cleanArtist)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            entries.append(TVAlbumPickerEntry(key: key, id: alb.id, name: cleanName, artist: cleanArtist))
        }

        for sel in savedAlbums {
            let cleanName = sel.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanArtist = sel.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty || !cleanArtist.isEmpty else { continue }
            let computedKey = TVLibraryConfigurationStore.makeAlbumSelectionKey(name: cleanName, artist: cleanArtist)
            let key = !sel.key.isEmpty ? sel.key : computedKey
            guard !key.isEmpty else { continue }
            if !seen.contains(key) && !seen.contains(computedKey) {
                seen.insert(key)
                entries.append(TVAlbumPickerEntry(key: key, id: sel.id, name: cleanName, artist: cleanArtist))
            } else if seen.contains(computedKey) && tvPickerSelectedKeys.contains(key) {
                tvPickerSelectedKeys.insert(computedKey)
            }
        }

        tvPickerAlbumEntries = entries
        tvPickerIsLoading = false
        tvPickerDoneButton?.isEnabled = true
        tvPickerSelectAllButton?.isEnabled = !entries.isEmpty
        tvPickerDeselectAllButton?.isEnabled = !entries.isEmpty
        rebuildTVPickerCheckboxList()
    }

    private func makeTVPickerSheetWindow(
        width: CGFloat,
        height: CGFloat,
        symbol: String,
        title: String,
        subtitle: String,
        searchPlaceholder: String
    ) -> NSWindow {
        let sheetWin = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheetWin.isReleasedWhenClosed = false

        let rootView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        rootView.autoresizingMask = [.width, .height]
        rootView.blendingMode = .withinWindow
        rootView.material = .windowBackground
        rootView.state = .active
        sheetWin.contentView = rootView

        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 10
        mainStack.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 10

        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 8
        badge.layer?.backgroundColor = MusicSettingsPalette.accent.cgColor
        badge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 30),
            badge.heightAnchor.constraint(equalToConstant: 30)
        ])
        if let symImg = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            let iv = NSImageView(image: symImg.withSymbolConfiguration(cfg) ?? symImg)
            iv.contentTintColor = .white
            iv.translatesAutoresizingMaskIntoConstraints = false
            badge.addSubview(iv)
            NSLayoutConstraint.activate([
                iv.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
                iv.centerYAnchor.constraint(equalTo: badge.centerYAnchor)
            ])
        }

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13.5, weight: .bold)
        titleLabel.textColor = .labelColor

        let subLabel = NSTextField(labelWithString: subtitle)
        subLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subLabel.textColor = .secondaryLabelColor

        let headerTextStack = NSStackView(views: [titleLabel, subLabel])
        headerTextStack.orientation = .vertical
        headerTextStack.alignment = .leading
        headerTextStack.spacing = 2
        headerRow.addArrangedSubview(badge)
        headerRow.addArrangedSubview(headerTextStack)

        let searchField = NSSearchField()
        searchField.placeholderString = searchPlaceholder
        searchField.controlSize = .small
        searchField.font = NSFont.systemFont(ofSize: 12)
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.target = self
        searchField.action = #selector(tvPickerSearchChanged(_:))
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        self.tvPickerSearchField = searchField

        let selectAllBtn = NSButton(title: isEn ? "Select All" : "Выбрать все", target: self, action: #selector(tvPickerSelectAllClicked))
        selectAllBtn.bezelStyle = .rounded
        selectAllBtn.controlSize = .small
        selectAllBtn.isEnabled = false
        selectAllBtn.setContentCompressionResistancePriority(.required, for: .horizontal)
        self.tvPickerSelectAllButton = selectAllBtn

        let deselectAllBtn = NSButton(title: isEn ? "Clear All" : "Снять все", target: self, action: #selector(tvPickerDeselectAllClicked))
        deselectAllBtn.bezelStyle = .rounded
        deselectAllBtn.controlSize = .small
        deselectAllBtn.isEnabled = false
        deselectAllBtn.setContentCompressionResistancePriority(.required, for: .horizontal)
        self.tvPickerDeselectAllButton = deselectAllBtn

        let toolbarRow = NSStackView(views: [searchField, selectAllBtn, deselectAllBtn])
        toolbarRow.orientation = .horizontal
        toolbarRow.alignment = .centerY
        toolbarRow.spacing = 6
        toolbarRow.translatesAutoresizingMaskIntoConstraints = false

        let listCard = SettingsCardView()
        listCard.translatesAutoresizingMaskIntoConstraints = false
        listCard.setContentHuggingPriority(.defaultLow, for: .vertical)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 25
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.style = .plain
        let col = NSTableColumn(identifier: Self.tvPickerCellIdentifier)
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        tableView.dataSource = self
        tableView.delegate = self
        scrollView.documentView = tableView
        self.tvPickerTableView = tableView

        let emptyLabel = makeStatusCaption("")
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        self.tvPickerEmptyOverlayLabel = emptyLabel

        listCard.addSubview(scrollView)
        listCard.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: listCard.topAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: listCard.leadingAnchor, constant: 6),
            scrollView.trailingAnchor.constraint(equalTo: listCard.trailingAnchor, constant: -6),
            scrollView.bottomAnchor.constraint(equalTo: listCard.bottomAnchor, constant: -4),
            emptyLabel.centerXAnchor.constraint(equalTo: listCard.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: listCard.centerYAnchor)
        ])

        let summaryLabel = NSTextField(labelWithString: "")
        summaryLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        summaryLabel.textColor = .secondaryLabelColor
        self.tvPickerSummaryLabel = summaryLabel

        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let cancelBtn = MusicPillButton(title: isEn ? "Cancel" : "Отменить", isPrimary: false, width: 92, target: self, action: #selector(cancelTVPickerSheetClicked))
        cancelBtn.keyEquivalent = "\u{1b}"

        let doneBtn = MusicPillButton(title: isEn ? "OK" : "ОК", isPrimary: true, width: 84, target: self, action: #selector(confirmTVPickerSheetClicked))
        doneBtn.keyEquivalent = "\r"
        doneBtn.isEnabled = false
        self.tvPickerDoneButton = doneBtn

        let footerRow = NSStackView(views: [summaryLabel, footerSpacer, cancelBtn, doneBtn])
        footerRow.orientation = .horizontal
        footerRow.alignment = .centerY
        footerRow.spacing = 8
        footerRow.translatesAutoresizingMaskIntoConstraints = false

        let innerWidth = width - 36
        mainStack.addArrangedSubview(headerRow)
        mainStack.addArrangedSubview(toolbarRow)
        mainStack.addArrangedSubview(listCard)
        mainStack.addArrangedSubview(footerRow)

        NSLayoutConstraint.activate([
            toolbarRow.widthAnchor.constraint(equalToConstant: innerWidth),
            listCard.widthAnchor.constraint(equalToConstant: innerWidth),
            footerRow.widthAnchor.constraint(equalToConstant: innerWidth)
        ])

        rootView.addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: rootView.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])
        return sheetWin
    }

    internal func rebuildTVPickerCheckboxList() {
        if tvPickerIsLoading {
            tvPickerFilteredIndices = []
            tvPickerTableView?.reloadData()
            let loadingText = activeTVPickerKind == .playlists
                ? (isEn ? "⏳ Loading library playlists…" : "⏳ Загрузка плейлистов медиатеки…")
                : (isEn ? "⏳ Loading library albums…" : "⏳ Загрузка альбомов медиатеки…")
            tvPickerEmptyOverlayLabel?.stringValue = loadingText
            tvPickerEmptyOverlayLabel?.isHidden = false
            updateTVPickerSummaryLabel()
            return
        }

        let query = (tvPickerSearchField?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var filtered: [Int] = []
        switch activeTVPickerKind {
        case .playlists:
            filtered.reserveCapacity(tvPickerPlaylistEntries.count)
            for (idx, item) in tvPickerPlaylistEntries.enumerated() {
                if query.isEmpty || item.name.localizedCaseInsensitiveContains(query) {
                    filtered.append(idx)
                }
            }
        case .albums:
            filtered.reserveCapacity(tvPickerAlbumEntries.count)
            for (idx, item) in tvPickerAlbumEntries.enumerated() {
                if query.isEmpty
                    || item.name.localizedCaseInsensitiveContains(query)
                    || item.artist.localizedCaseInsensitiveContains(query) {
                    filtered.append(idx)
                }
            }
        }

        tvPickerFilteredIndices = filtered
        tvPickerTableView?.reloadData()

        if filtered.isEmpty {
            tvPickerEmptyOverlayLabel?.stringValue = !query.isEmpty
                ? (isEn ? "No matches for “\(query)”" : "Ничего не найдено по запросу «\(query)»")
                : (isEn ? "Library is empty" : "В медиатеке пока нет элементов")
            tvPickerEmptyOverlayLabel?.isHidden = false
        } else {
            tvPickerEmptyOverlayLabel?.isHidden = true
        }
        updateTVPickerSummaryLabel()
    }

    public func numberOfRows(in tableView: NSTableView) -> Int {
        guard tableView === tvPickerTableView else { return 0 }
        return tvPickerFilteredIndices.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard tableView === tvPickerTableView,
              row >= 0,
              row < tvPickerFilteredIndices.count else { return nil }
        let entryIdx = tvPickerFilteredIndices[row]

        let cellView: NSTableCellView
        let checkbox: MusicCheckboxButton
        if let reused = tableView.makeView(withIdentifier: Self.tvPickerCellIdentifier, owner: nil) as? NSTableCellView,
           let cb = reused.subviews.first(where: { $0 is MusicCheckboxButton }) as? MusicCheckboxButton {
            cellView = reused
            checkbox = cb
        } else {
            let createdCell = NSTableCellView()
            createdCell.identifier = Self.tvPickerCellIdentifier
            let cb = MusicCheckboxButton(title: "", target: self, action: #selector(tvPickerItemCheckboxToggled(_:)))
            cb.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
            createdCell.addSubview(cb)
            NSLayoutConstraint.activate([
                cb.leadingAnchor.constraint(equalTo: createdCell.leadingAnchor, constant: 6),
                cb.trailingAnchor.constraint(lessThanOrEqualTo: createdCell.trailingAnchor, constant: -6),
                cb.centerYAnchor.constraint(equalTo: createdCell.centerYAnchor)
            ])
            cellView = createdCell
            checkbox = cb
        }

        checkbox.tag = entryIdx
        switch activeTVPickerKind {
        case .playlists:
            guard entryIdx < tvPickerPlaylistEntries.count else { return cellView }
            let item = tvPickerPlaylistEntries[entryIdx]
            if let cnt = item.trackCount {
                checkbox.title = isEn ? "\(item.name) (\(cnt))" : "\(item.name) (\(cnt) тр.)"
            } else {
                checkbox.title = item.name
            }
            checkbox.state = tvPickerSelectedKeys.contains(item.name.lowercased()) ? .on : .off

        case .albums:
            guard entryIdx < tvPickerAlbumEntries.count else { return cellView }
            let item = tvPickerAlbumEntries[entryIdx]
            if item.artist.isEmpty {
                checkbox.title = item.name
            } else if item.name.isEmpty {
                checkbox.title = item.artist
            } else {
                checkbox.title = "\(item.name) — \(item.artist)"
            }
            checkbox.state = tvPickerSelectedKeys.contains(item.key) ? .on : .off
        }
        return cellView
    }

    private func updateTVPickerSummaryLabel() {
        guard let label = tvPickerSummaryLabel else { return }
        let selectedCount: Int
        let totalCount: Int
        switch activeTVPickerKind {
        case .playlists:
            totalCount = tvPickerPlaylistEntries.count
            selectedCount = tvPickerIsLoading
                ? tvPickerSelectedKeys.count
                : tvPickerPlaylistEntries.filter { tvPickerSelectedKeys.contains($0.name.lowercased()) }.count
        case .albums:
            totalCount = tvPickerAlbumEntries.count
            selectedCount = tvPickerIsLoading
                ? tvPickerSelectedKeys.count
                : tvPickerAlbumEntries.filter { tvPickerSelectedKeys.contains($0.key) }.count
        }
        label.stringValue = tvPickerIsLoading
            ? (isEn ? "Selected: \(selectedCount)" : "Выбрано: \(selectedCount)")
            : (isEn ? "Selected: \(selectedCount) of \(totalCount)" : "Выбрано: \(selectedCount) из \(totalCount)")
    }

    @objc internal func tvPickerSearchChanged(_ sender: NSSearchField) {
        tvPickerSearchDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.rebuildTVPickerCheckboxList()
        }
        tvPickerSearchDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: work)
    }

    @objc internal func tvPickerItemCheckboxToggled(_ sender: NSButton) {
        let idx = sender.tag
        let isOn = (sender.state == .on)
        switch activeTVPickerKind {
        case .playlists:
            guard idx >= 0 && idx < tvPickerPlaylistEntries.count else { return }
            let key = tvPickerPlaylistEntries[idx].name.lowercased()
            if isOn { tvPickerSelectedKeys.insert(key) } else { tvPickerSelectedKeys.remove(key) }
        case .albums:
            guard idx >= 0 && idx < tvPickerAlbumEntries.count else { return }
            let key = tvPickerAlbumEntries[idx].key
            if isOn { tvPickerSelectedKeys.insert(key) } else { tvPickerSelectedKeys.remove(key) }
        }
        updateTVPickerSummaryLabel()
    }

    @objc internal func tvPickerSelectAllClicked() {
        let query = (tvPickerSearchField?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch activeTVPickerKind {
        case .playlists:
            for item in tvPickerPlaylistEntries where query.isEmpty || item.name.localizedCaseInsensitiveContains(query) {
                tvPickerSelectedKeys.insert(item.name.lowercased())
            }
        case .albums:
            for item in tvPickerAlbumEntries where query.isEmpty || item.name.localizedCaseInsensitiveContains(query) || item.artist.localizedCaseInsensitiveContains(query) {
                tvPickerSelectedKeys.insert(item.key)
            }
        }
        rebuildTVPickerCheckboxList()
    }

    @objc internal func tvPickerDeselectAllClicked() {
        let query = (tvPickerSearchField?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            tvPickerSelectedKeys.removeAll()
        } else {
            switch activeTVPickerKind {
            case .playlists:
                for item in tvPickerPlaylistEntries where item.name.localizedCaseInsensitiveContains(query) {
                    tvPickerSelectedKeys.remove(item.name.lowercased())
                }
            case .albums:
                for item in tvPickerAlbumEntries where item.name.localizedCaseInsensitiveContains(query) || item.artist.localizedCaseInsensitiveContains(query) {
                    tvPickerSelectedKeys.remove(item.key)
                }
            }
        }
        rebuildTVPickerCheckboxList()
    }

    @objc internal func cancelTVPickerSheetClicked() {
        closeTVPickerSheet()
        refreshTVLibraryControlsState()
    }

    @objc internal func confirmTVPickerSheetClicked() {
        guard !tvPickerIsLoading else { return }
        switch activeTVPickerKind {
        case .playlists:
            let chosenNames = tvPickerPlaylistEntries
                .filter { tvPickerSelectedKeys.contains($0.name.lowercased()) }
                .map { $0.name }
            TVLibraryConfigurationStore.shared.update { cfg in
                cfg.playlistsMode = "selected"
                cfg.selectedPlaylistNames = chosenNames
            }
        case .albums:
            let chosenAlbums = tvPickerAlbumEntries
                .filter { tvPickerSelectedKeys.contains($0.key) }
                .map { TVLibraryAlbumSelection(key: $0.key, id: $0.id, name: $0.name, artist: $0.artist) }
            TVLibraryConfigurationStore.shared.update { cfg in
                cfg.albumsMode = "selected"
                cfg.selectedAlbums = chosenAlbums
            }
        }
        closeTVPickerSheet()
        broadcastTVLibraryConfigChanged()
    }

    internal func closeTVPickerSheet() {
        tvPickerLoadGeneration &+= 1
        tvPickerIsLoading = false
        tvPickerSearchDebounceWorkItem?.cancel()
        tvPickerSearchDebounceWorkItem = nil
        if let sheet = activeTVPickerSheetWindow {
            if let parent = self.window {
                parent.endSheet(sheet)
            }
            sheet.orderOut(nil)
        }
        activeTVPickerSheetWindow = nil
        tvPickerSearchField = nil
        tvPickerTableView = nil
        tvPickerEmptyOverlayLabel = nil
        tvPickerFilteredIndices = []
        tvPickerSummaryLabel = nil
        tvPickerDoneButton = nil
        tvPickerSelectAllButton = nil
        tvPickerDeselectAllButton = nil
        tvPickerPlaylistEntries = []
        tvPickerAlbumEntries = []
        tvPickerSelectedKeys = []
    }
}
