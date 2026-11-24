//
//  SettingsWindow+TVMode.swift
//  AppleMusicRemoteMac
//
//  StandBy TV Mode tab builder, summary state updater, and WebSocket broadcast helper.
//

import AppKit

extension SettingsWindow {
    internal func buildTVTabView() -> NSView {
        let isEn = SettingsTab.isEn

        let makeTileCheckbox: (String, Int) -> NSButton = { title, tag in
            let cb = MusicCheckboxButton(title: title, target: self, action: #selector(self.tvCoreTileCheckboxChanged(_:)))
            cb.tag = tag
            return cb
        }

        tvMyStationCheckbox = makeTileCheckbox(isEn ? "My Station" : "Моя станция", 1)
        tvDiscoveryStationCheckbox = makeTileCheckbox(isEn ? "Discovery Station" : "Станция открытий", 2)
        tvFavoritesMixCheckbox = makeTileCheckbox(isEn ? "Favorites Mix" : "В моём вкусе (Favorites Mix)", 3)
        tvHeavyRotationCheckbox = makeTileCheckbox(isEn ? "Heavy Rotation" : "Сейчас на повторе (Heavy Rotation)", 4)

        let stationsDesc = makeMusicSubcaption(
            isEn
                ? "Selected Apple Music stations and mixes appear at the top of the Library screen in StandBy TV Mode."
                : "Отмеченные персональные радиостанции и миксы Apple Music отображаются в начале раздела «Медиатека» в ТВ-режиме."
        )
        let stationsDescIndent = makeIndentedSubcaptionContainer(stationsDesc)

        let stationsStack = NSStackView(views: [
            tvMyStationCheckbox,
            tvDiscoveryStationCheckbox,
            tvFavoritesMixCheckbox,
            tvHeavyRotationCheckbox,
            stationsDescIndent
        ])
        stationsStack.orientation = .vertical
        stationsStack.alignment = .leading
        stationsStack.spacing = 8
        stationsDescIndent.widthAnchor.constraint(equalTo: stationsStack.widthAnchor).isActive = true

        tvPlaylistsModePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        tvPlaylistsModePopUp.controlSize = .regular
        tvPlaylistsModePopUp.target = self
        tvPlaylistsModePopUp.action = #selector(tvPlaylistsModeChanged(_:))
        tvPlaylistsModePopUp.widthAnchor.constraint(equalToConstant: 210).isActive = true
        let playlistModeOptions: [(title: String, tag: Int, mode: String)] = [
            (isEn ? "All Playlists" : "Все плейлисты", 0, "all"),
            (isEn ? "Select Manually…" : "Выбрать вручную…", 1, "selected"),
            (isEn ? "Hide All" : "Не показывать", 2, "none")
        ]
        for opt in playlistModeOptions {
            tvPlaylistsModePopUp.addItem(withTitle: opt.title)
            tvPlaylistsModePopUp.lastItem?.tag = opt.tag
            tvPlaylistsModePopUp.lastItem?.representedObject = opt.mode
        }

        tvChoosePlaylistsButton = NSButton(
            title: isEn ? "Choose…" : "Выбрать…",
            target: self,
            action: #selector(chooseTVPlaylistsClicked)
        )
        tvChoosePlaylistsButton.bezelStyle = .rounded
        tvChoosePlaylistsButton.controlSize = .regular

        let playlistsControls = NSStackView(views: [tvPlaylistsModePopUp, tvChoosePlaylistsButton])
        playlistsControls.orientation = .horizontal
        playlistsControls.alignment = .centerY
        playlistsControls.spacing = 8

        tvAlbumsModePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        tvAlbumsModePopUp.controlSize = .regular
        tvAlbumsModePopUp.target = self
        tvAlbumsModePopUp.action = #selector(tvAlbumsModeChanged(_:))
        tvAlbumsModePopUp.widthAnchor.constraint(equalToConstant: 210).isActive = true
        let albumModeOptions: [(title: String, tag: Int, mode: String)] = [
            (isEn ? "Recent Albums (up to 24)" : "Недавние альбомы (до 24)", 0, "recent"),
            (isEn ? "Select Manually…" : "Выбрать вручную…", 1, "selected"),
            (isEn ? "Hide All" : "Не показывать", 2, "none")
        ]
        for opt in albumModeOptions {
            tvAlbumsModePopUp.addItem(withTitle: opt.title)
            tvAlbumsModePopUp.lastItem?.tag = opt.tag
            tvAlbumsModePopUp.lastItem?.representedObject = opt.mode
        }

        tvChooseAlbumsButton = NSButton(
            title: isEn ? "Choose…" : "Выбрать…",
            target: self,
            action: #selector(chooseTVAlbumsClicked)
        )
        tvChooseAlbumsButton.bezelStyle = .rounded
        tvChooseAlbumsButton.controlSize = .regular

        let albumsControls = NSStackView(views: [tvAlbumsModePopUp, tvChooseAlbumsButton])
        albumsControls.orientation = .horizontal
        albumsControls.alignment = .centerY
        albumsControls.spacing = 8

        tvConfigStatusLabel = makeStatusCaption("")
        tvConfigStatusLabel.lineBreakMode = .byWordWrapping

        let page = makeMusicPreferencePage(sections: [
            [
                makeMusicTwoColumnRow(category: isEn ? "Show:" : "Показывать:", rightContent: stationsStack, topLabelOffset: 1)
            ],
            [
                makeMusicControlRow(
                    category: isEn ? "Playlists:" : "Плейлисты:",
                    control: playlistsControls,
                    subtitle: isEn
                        ? "Choose whether StandBy TV Library displays all playlists, hand-picked playlists, or hides them."
                        : "Выберите, какие плейлисты отображать в разделе «Медиатека» ТВ-режима."
                ),
                makeMusicControlRow(
                    category: isEn ? "Albums:" : "Альбомы:",
                    control: albumsControls,
                    subtitle: isEn
                        ? "Display recently added library albums or a pinned selection of favorite albums."
                        : "Показывать недавно добавленные альбомы или выбранную вручную подборку."
                )
            ],
            [
                makeMusicTwoColumnRow(category: isEn ? "Summary:" : "Сводка:", rightContent: tvConfigStatusLabel, topLabelOffset: 0)
            ]
        ])

        refreshTVLibraryControlsState()
        return page
    }

    internal func refreshTVLibraryControlsState() {
        guard tvMyStationCheckbox != nil,
              tvPlaylistsModePopUp != nil,
              tvAlbumsModePopUp != nil,
              tvConfigStatusLabel != nil else { return }

        let cfg = TVLibraryConfigurationStore.shared.current
        tvMyStationCheckbox.state = cfg.showMyStation ? .on : .off
        tvDiscoveryStationCheckbox.state = cfg.showDiscoveryStation ? .on : .off
        tvFavoritesMixCheckbox.state = cfg.showFavoritesMix ? .on : .off
        tvHeavyRotationCheckbox.state = cfg.showHeavyRotation ? .on : .off

        let plTag: Int
        switch cfg.playlistsMode.lowercased() {
        case "selected": plTag = 1
        case "none": plTag = 2
        default: plTag = 0
        }
        if tvPlaylistsModePopUp.indexOfItem(withTag: plTag) != -1 {
            tvPlaylistsModePopUp.selectItem(withTag: plTag)
        }

        let albTag: Int
        switch cfg.albumsMode.lowercased() {
        case "selected": albTag = 1
        case "none": albTag = 2
        default: albTag = 0
        }
        if tvAlbumsModePopUp.indexOfItem(withTag: albTag) != -1 {
            tvAlbumsModePopUp.selectItem(withTag: albTag)
        }

        let coreCount = [cfg.showMyStation, cfg.showDiscoveryStation, cfg.showFavoritesMix, cfg.showHeavyRotation].filter { $0 }.count

        let plSummary: String
        switch plTag {
        case 1: plSummary = isEn ? "Playlists: \(cfg.selectedPlaylistNames.count) selected" : "Плейлисты: выбрано \(cfg.selectedPlaylistNames.count)"
        case 2: plSummary = isEn ? "Playlists: Hidden" : "Плейлисты: Скрыты"
        default: plSummary = isEn ? "Playlists: All" : "Плейлисты: Все"
        }

        let albSummary: String
        switch albTag {
        case 1: albSummary = isEn ? "Albums: \(cfg.selectedAlbums.count) selected" : "Альбомы: выбрано \(cfg.selectedAlbums.count)"
        case 2: albSummary = isEn ? "Albums: Hidden" : "Альбомы: Скрыты"
        default: albSummary = isEn ? "Albums: Recent" : "Альбомы: Недавние"
        }

        tvConfigStatusLabel.stringValue = isEn
            ? "Stations & Mixes: \(coreCount) of 4 • \(plSummary) • \(albSummary)"
            : "Станции и миксы: \(coreCount) из 4 • \(plSummary) • \(albSummary)"
    }

    internal func broadcastTVLibraryConfigChanged() {
        refreshTVLibraryControlsState()
        WebSocketServer.shared.broadcastEvent(
            name: "tv_library_config",
            data: TVLibraryConfigurationStore.shared.toDictionary()
        )
    }

    @objc internal func tvCoreTileCheckboxChanged(_ sender: NSButton) {
        let showMy = (tvMyStationCheckbox.state == .on)
        let showDisc = (tvDiscoveryStationCheckbox.state == .on)
        let showFav = (tvFavoritesMixCheckbox.state == .on)
        let showHeavy = (tvHeavyRotationCheckbox.state == .on)
        TVLibraryConfigurationStore.shared.update { cfg in
            cfg.showMyStation = showMy
            cfg.showDiscoveryStation = showDisc
            cfg.showFavoritesMix = showFav
            cfg.showHeavyRotation = showHeavy
        }
        broadcastTVLibraryConfigChanged()
    }

    @objc internal func tvPlaylistsModeChanged(_ sender: NSPopUpButton) {
        let tag = sender.selectedTag()
        if tag == 1 {
            if !TVLibraryConfigurationStore.shared.current.selectedPlaylistNames.isEmpty {
                TVLibraryConfigurationStore.shared.update { $0.playlistsMode = "selected" }
                broadcastTVLibraryConfigChanged()
            }
            presentTVPlaylistsPickerSheet()
        } else {
            let newMode = (tag == 2) ? "none" : "all"
            TVLibraryConfigurationStore.shared.update { $0.playlistsMode = newMode }
            broadcastTVLibraryConfigChanged()
        }
    }

    @objc internal func chooseTVPlaylistsClicked() {
        presentTVPlaylistsPickerSheet()
    }

    @objc internal func tvAlbumsModeChanged(_ sender: NSPopUpButton) {
        let tag = sender.selectedTag()
        if tag == 1 {
            if !TVLibraryConfigurationStore.shared.current.selectedAlbums.isEmpty {
                TVLibraryConfigurationStore.shared.update { $0.albumsMode = "selected" }
                broadcastTVLibraryConfigChanged()
            }
            presentTVAlbumsPickerSheet()
        } else {
            let newMode = (tag == 2) ? "none" : "recent"
            TVLibraryConfigurationStore.shared.update { $0.albumsMode = newMode }
            broadcastTVLibraryConfigChanged()
        }
    }

    @objc internal func chooseTVAlbumsClicked() {
        presentTVAlbumsPickerSheet()
    }
}
