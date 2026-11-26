//
//  CloudCatalogService+ExploreFeed.swift
//  AppleMusicRemoteMac
//
//  Personalized Explore / Home feed aggregation, hero cards, seasonal mixes, and caching.
//

import Foundation

extension CloudCatalogService {

    // MARK: - Explore Feed

    public func getExploreFeed(country: String = "") async -> [String: Any] {
        let c = MusicKitManager.sanitizedStorefront(MusicKitManager.shared.resolveEffectiveStorefront(country))

        let lookup: (cached: [String: Any]?, existingTask: Task<UncheckedFeedBox, Never>?) = feedLock.withLock {
            if let entry = cachedFeed[c], Date().timeIntervalSince(entry.timestamp) < 600.0 {
                return (entry.feed, nil)
            }
            if let existing = inFlightFeedTasks[c] {
                return (nil, existing)
            }
            return (nil, nil)
        }
        if let cached = lookup.cached {
            return cached
        }
        if let existingTask = lookup.existingTask {
            return (await existingTask.value).feed
        }

        let task = Task<UncheckedFeedBox, Never> {
            let built = await self.computeExploreFeed(country: c)
            return UncheckedFeedBox(feed: built)
        }
        let taskToAwait: Task<UncheckedFeedBox, Never> = feedLock.withLock {
            if let raced = inFlightFeedTasks[c] {
                task.cancel()
                return raced
            }
            inFlightFeedTasks[c] = task
            return task
        }
        let result = (await taskToAwait.value).feed
        feedLock.withLock {
            if inFlightFeedTasks[c] == taskToAwait {
                inFlightFeedTasks.removeValue(forKey: c)
            }
        }
        return result
    }

    internal func computeExploreFeed(country c: String) async -> [String: Any] {
        let isRu = ["ru", "kz", "by", "ua"].contains(c) || MusicKitManager.shared.isSystemLocaleRussian || MusicKitManager.shared.getPreferredLanguageTag().lowercased().hasPrefix("ru")

        var personalMixes: [PlaylistInfo] = []
        var personalRecs: [PersonalRecommendationGroup] = []
        var dynamicPersonalStation: StationInfo? = nil
        var dynamicDiscoveryStation: StationInfo? = nil

        if MusicKitManager.shared.hasUserToken {
            let (pStation, dStation) = await MusicKitManager.shared.fetchPersonalStations()
            dynamicPersonalStation = pStation
            dynamicDiscoveryStation = dStation
            personalMixes = await MusicKitManager.shared.fetchPersonalMixes()
            personalRecs = await MusicKitManager.shared.fetchPersonalRecommendations(limit: 30)
        }

        var stations = getCuratedStations(country: c)

        let genres: [[String: String]] = [
            ["name": isRu ? "🔥 Поп-музыка" : "🔥 Pop Music", "query": "Pop Hits", "color": "linear-gradient(135deg, #fa2d48, #ff6b8b)"],
            ["name": isRu ? "🎸 Рок & Альтернатива" : "🎸 Rock & Alternative", "query": "Rock Classics", "color": "linear-gradient(135deg, #e65100, #ff9800)"],
            ["name": isRu ? "🎤 Хип-хоп & Рэп" : "🎤 Hip-Hop & Rap", "query": "Hip Hop", "color": "linear-gradient(135deg, #4a148c, #7b1fa2)"],
            ["name": isRu ? "⚡ Электроника & Dance" : "⚡ Electronic & Dance", "query": "Dance Electronic", "color": "linear-gradient(135deg, #00695c, #00bfa5)"],
            ["name": "☕ Chill & Lo-Fi", "query": "Chill Beats", "color": "linear-gradient(135deg, #1565c0, #42a5f5)"],
            ["name": isRu ? "🎻 Неоклассика" : "🎻 Neoclassical", "query": "Neoclassical", "color": "linear-gradient(135deg, #37474f, #78909c)"],
            ["name": isRu ? "🎬 Саундтреки" : "🎬 Soundtracks", "query": "Soundtrack Movie", "color": "linear-gradient(135deg, #880e4f, #d81b60)"]
        ]

        let charts: (songs: [[String: Any]], albums: [[String: Any]]) = await withTaskGroup(of: (songs: [[String: Any]], albums: [[String: Any]]).self) { group in
            group.addTask {
                await MusicKitManager.shared.getTopChartsFull(storefront: c, limit: 30)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                return ([], [])
            }
            let first = await group.next() ?? ([], [])
            group.cancelAll()
            return first
        }

        var topSongs = charts.songs
        var topAlbums = charts.albums
        if topSongs.isEmpty || topAlbums.isEmpty {
            let rssData: (songs: [[String: Any]], albums: [[String: Any]]) = await withTaskGroup(of: (songs: [[String: Any]], albums: [[String: Any]]).self) { group in
                group.addTask {
                    async let s = self.fetchTopSongsRSS(country: c)
                    async let a = self.fetchTopAlbumsRSS(country: c)
                    return await (s, a)
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    return ([], [])
                }
                let first = await group.next() ?? ([], [])
                group.cancelAll()
                return first
            }
            if topSongs.isEmpty { topSongs = rssData.songs }
            if topAlbums.isEmpty { topAlbums = rssData.albums }
        }
        if topAlbums.isEmpty {
            topAlbums = [
                [
                    "id": "1375628135",
                    "name": "Легенда",
                    "artist": "Кино",
                    "artwork": "https://is1-ssl.mzstatic.com/image/thumb/Music118/v4/c7/99/1e/c7991ed1-bee2-8c46-2e66-81d0b8e7eeb2/cover.jpg/600x600bb.jpg",
                    "url": "https://music.apple.com/album/1375628135"
                ],
                [
                    "id": "1440770702",
                    "name": "Mutter",
                    "artist": "Rammstein",
                    "artwork": "https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/b8/91/bf/b891bf2e-0658-690a-115f-c2ee53f3192e/00602527296685.rgb.jpg/600x600bb.jpg",
                    "url": "https://music.apple.com/album/1440770702"
                ],
                [
                    "id": "1440751918",
                    "name": "Акустический альбом",
                    "artist": "Король и Шут",
                    "artwork": "https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/44/9a/c0/449ac06f-40e1-7c59-bf7b-6ae9be2d7b14/4607062440191.jpg/600x600bb.jpg",
                    "url": "https://music.apple.com/album/1440751918"
                ]
            ]
        }
        let hotTracks = topSongs.count > 10 ? Array(topSongs.prefix(10)) : topSongs

        // Section 1: Hero Cards
        var heroCards: [[String: Any]] = []

        if MusicKitManager.shared.hasUserToken {
            let pRawName = dynamicPersonalStation?.name ?? ""
            var ownerName = pRawName
                .replacingOccurrences(of: "’s Station", with: "")
                .replacingOccurrences(of: "'s Station", with: "")
                .replacingOccurrences(of: " Station", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if ownerName.isEmpty || ownerName == "My" || ownerName == "Personal" || ownerName == "Моя станция" || ownerName == "You" {
                if let cur = personalMixes.compactMap({ $0.curatorName }).first(where: { $0.contains("Apple Music for ") }) {
                    ownerName = cur.replacingOccurrences(of: "Apple Music for ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            if ownerName.isEmpty || ownerName == "My" || ownerName == "Personal" || ownerName == "Моя станция" {
                ownerName = "You"
            }
            let pTitle = isRu ? "Моя станция" : "My Station"
            let pSub = "Apple Music for \(ownerName)"
            let pUrl = dynamicPersonalStation?.url ?? ""
            let pId = dynamicPersonalStation?.id ?? "station_personal"
            let pArt = (dynamicPersonalStation?.artwork.isEmpty == false) ? dynamicPersonalStation!.artwork : MusicKitManager.defaultPersonalStationArtwork
            heroCards.append([
                "index": 1,
                "title": pTitle,
                "name": pTitle,
                "subtitle": pSub,
                "sub": pSub,
                "tag": isRu ? "Радиостанция" : "Radio Station",
                "id": pId,
                "type": "station",
                "url": pUrl,
                "artwork": pArt
            ])

            let dTitle = isRu ? "Станция открытий" : "Discovery Station"
            let dSub = isRu ? "Новые треки под ваш вкус" : "New music based on what you love"
            let dUrl = dynamicDiscoveryStation?.url ?? ""
            let dId = dynamicDiscoveryStation?.id ?? "station_discovery"
            let dArt = (dynamicDiscoveryStation?.artwork.isEmpty == false) ? dynamicDiscoveryStation!.artwork : "/assets/stations/CoverDiscovery.png"
            heroCards.append([
                "index": 2,
                "title": dTitle,
                "name": dTitle,
                "subtitle": dSub,
                "sub": dSub,
                "tag": isRu ? "Радиостанция" : "Radio Station",
                "id": dId,
                "type": "station",
                "url": dUrl,
                "artwork": dArt
            ])

            let favMix = personalMixes.first(where: { m in
                let n = m.name.lowercased()
                return n.contains("в моем вкусе") || n.contains("в моём вкусе") || n.contains("favorites") || n.contains("essentials") || n.contains("избранн")
            })
            let favTitle = favMix?.name ?? (isRu ? "В моём вкусе" : "Favorites Mix")
            let favId = favMix?.id ?? "favorites_mix"
            let safeFavId = MusicKitManager.isValidResourceIdentifier(favId) ? favId : "favorites_mix"
            let favUrl = favMix?.url ?? ((safeFavId != "favorites_mix" && !safeFavId.isEmpty) ? "https://music.apple.com/playlist/\(safeFavId)" : "")
            let favArt = (favMix?.artworkUrl?.isEmpty == false) ? favMix!.artworkUrl! : "/assets/stations/CoverElectronic.png"
            heroCards.append([
                "index": 3,
                "title": favTitle,
                "name": favTitle,
                "subtitle": favMix?.description ?? (isRu ? "Микс на основе ваших вкусов" : "Your all-time favorites"),
                "sub": favMix?.description ?? (isRu ? "Микс на основе ваших вкусов" : "Your all-time favorites"),
                "tag": isRu ? "Микс" : "Personal Mix",
                "id": favId,
                "type": "playlist",
                "url": favUrl,
                "artwork": favArt
            ])

            let hrMix = personalMixes.first(where: { m in
                let n = m.name.lowercased()
                return n.contains("повторе") || n.contains("heavy rotation") || n.contains("rotation")
            })
            let hrTitle = hrMix?.name ?? (isRu ? "Сейчас на повторе" : "Heavy Rotation Mix")
            let hrId = hrMix?.id ?? "heavy_rotation_mix"
            let safeHrId = MusicKitManager.isValidResourceIdentifier(hrId) ? hrId : "heavy_rotation_mix"
            let hrUrl = hrMix?.url ?? (hrMix?.id != nil && safeHrId != "heavy_rotation_mix" ? "https://music.apple.com/playlist/heavy-rotation-mix/\(safeHrId)" : "")
            let hrArt = (hrMix?.artworkUrl?.isEmpty == false) ? hrMix!.artworkUrl! : "/assets/stations/CoverHeavyRotation.svg"
            heroCards.append([
                "index": 4,
                "title": hrTitle,
                "name": hrTitle,
                "subtitle": hrMix?.description ?? (isRu ? "Музыка, которую вы часто слушаете" : "Music you listen to most right now"),
                "sub": hrMix?.description ?? (isRu ? "Музыка, которую вы часто слушаете" : "Music you listen to most right now"),
                "tag": isRu ? "Микс" : "Personal Mix",
                "id": hrId,
                "type": "playlist",
                "url": hrUrl,
                "artwork": hrArt
            ])

            var seasonMix = personalMixes.first(where: { m in
                let n = m.name.lowercased()
                return n.contains("replay") || n.contains("итоги") || n.contains("сезон")
            })
            if seasonMix == nil {
                for grp in personalRecs {
                    if let res = grp.contents.first(where: { r in
                        let n = r.name.lowercased()
                        let t = grp.title.lowercased()
                        return (r.type == "playlists") && (n.contains("replay") || n.contains("итоги") || t.contains("replay") || t.contains("итоги") || t.contains("seasonal") || t.contains("сезон"))
                    }) {
                        seasonMix = PlaylistInfo(
                            name: res.name,
                            trackCount: 50,
                            artworkUrl: res.artworkUrl,
                            isPlaylist: true,
                            id: res.id,
                            url: res.url,
                            curatorName: res.subtitle ?? "Apple Music",
                            description: res.subtitle
                        )
                        break
                    }
                }
            }
            let seasonTitle = seasonMix?.name ?? (isRu ? "Итоги года Replay" : "Replay")
            let seasonId = seasonMix?.id ?? "replay_playlist"
            let safeSeasonId = MusicKitManager.isValidResourceIdentifier(seasonId) ? seasonId : "replay_playlist"
            let seasonUrl = seasonMix?.url ?? ((safeSeasonId != "replay_playlist" && !safeSeasonId.isEmpty) ? "https://music.apple.com/playlist/\(safeSeasonId)" : "")
            let seasonArt = (seasonMix?.artworkUrl?.isEmpty == false) ? seasonMix!.artworkUrl! : "/assets/stations/CoverRock.png"
            heroCards.append([
                "index": 5,
                "title": seasonTitle,
                "name": seasonTitle,
                "subtitle": seasonMix?.description ?? (isRu ? "Ваши главные треки года" : "Your top tracks"),
                "sub": seasonMix?.description ?? (isRu ? "Ваши главные треки года" : "Your top tracks"),
                "tag": isRu ? "Сезонная подборка" : "Seasonal",
                "id": seasonId,
                "type": "playlist",
                "url": seasonUrl,
                "artwork": seasonArt,
                "artwork_url": seasonArt
            ])

            let month = Calendar.current.component(.month, from: Date())
            let eventId: String
            let eventTitle: String
            let eventSub: String
            let eventArt: String
            let eventUrl: String
            let eventColor: String

            if (3...5).contains(month) {
                eventId = "pl.2b0e6e332fdf4b7a91164da3162127b5"
                eventTitle = isRu ? "Весеннее настроение" : "Spring Vibes"
                eventSub = isRu ? "Свежие треки и весенняя энергия" : "Fresh hits for spring days"
                eventArt = "/assets/stations/CoverPop.png"
                eventUrl = "https://music.apple.com/us/playlist/new-music-daily/\(eventId)"
                eventColor = "linear-gradient(135deg, #11998e, #38ef7d)"
            } else if (6...8).contains(month) {
                eventId = "pl.f4d106fed2bd41149aaacabb233eb5eb"
                eventTitle = isRu ? "Летние хиты" : "Summer Hits"
                eventSub = isRu ? "Главные саундтреки этого лета" : "Sun-soaked anthems & party tracks"
                eventArt = "/assets/stations/CoverHits.png"
                eventUrl = "https://music.apple.com/us/playlist/todays-hits/\(eventId)"
                eventColor = "linear-gradient(135deg, #ff8008, #ffc837)"
            } else if month == 9 {
                eventId = "pl.c7be009ba325420394d51269b3c4a9fe"
                eventTitle = isRu ? "Осенний уют" : "Autumn Chill"
                eventSub = isRu ? "Тёплая атмосфера для осенних вечеров" : "Cozy & atmospheric autumn sounds"
                eventArt = "/assets/stations/CoverChill.png"
                eventUrl = "https://music.apple.com/us/playlist/pure-chill/\(eventId)"
                eventColor = "linear-gradient(135deg, #b24592, #f15f79)"
            } else if month == 10 {
                eventId = "pl.14572caaa2c0493994f3b7beff6b1b10"
                eventTitle = "Halloween Essentials"
                eventSub = isRu ? "Хэллоуин в Apple Music" : "Halloween Party & Hits"
                eventArt = "https://is1-ssl.mzstatic.com/image/thumb/Features/v4/14/57/2c/14572caa-a2c0-4939-94f3-b7beff6b1b10/mza_10818274191630138981.png/600x600bb.jpg"
                eventUrl = "https://music.apple.com/us/playlist/halloween-essentials/\(eventId)"
                eventColor = "linear-gradient(135deg, #e65c00, #f9d423)"
            } else {
                eventId = "pl.aa7d95d6eb4f45d3879bd7ca1ea515ff"
                eventTitle = isRu ? "Новый год: Вечеринка" : "New Year’s Eve: Dinner Party"
                eventSub = isRu ? "Праздничные хиты и танцы" : "Countdown & party starters"
                eventArt = "https://is1-ssl.mzstatic.com/image/thumb/Features114/v4/c2/0e/f3/c20ef30c-5720-8dfc-3227-e9962300c63e/U0MtTVMtV1ctTmV3X1llYXJzX0V2ZV9EaW5uZXJfUGFydHktQURBTV9JRD0xMDY3NDcwNjYxLnBuZw.png/600x600cc.jpg"
                eventUrl = "https://music.apple.com/us/playlist/new-years-eve-dinner-party/\(eventId)"
                eventColor = "linear-gradient(135deg, #1b0a2a, #3c1361, #75225b)"
            }

            heroCards.append([
                "index": 6,
                "title": eventTitle,
                "name": eventTitle,
                "subtitle": eventSub,
                "sub": eventSub,
                "tag": isRu ? "Событие" : "Event",
                "id": eventId,
                "type": "playlist",
                "url": eventUrl,
                "artwork": eventArt,
                "artwork_url": eventArt,
                "color": eventColor
            ])

            var seenStationIds = Set<String>()
            for s in stations { seenStationIds.insert(s.id) }
            if let pId = dynamicPersonalStation?.id { seenStationIds.insert(pId) }
            if let dId = dynamicDiscoveryStation?.id { seenStationIds.insert(dId) }

            var artistStations: [StationInfo] = []
            var firstArtistRawName: String? = nil
            for grp in personalRecs {
                let grpTitle = grp.title.lowercased()
                if grpTitle.contains("recently") || grpTitle.contains("недавно") {
                    continue
                }

                for res in grp.contents where res.type == "stations" {
                    if seenStationIds.contains(res.id) { continue }
                    if res.id.hasPrefix("ra.u-") || res.id.hasPrefix("ra.q-") { continue }
                    guard MusicKitManager.isValidResourceIdentifier(res.id) else { continue }
                    let lower = res.name.lowercased()
                    if lower.contains("discovery") || lower.contains("открыти") || lower.contains("my station") || lower.contains("моя станция") {
                        continue
                    }

                    let isArtistStation = lower.contains("similar") || lower.contains("подобные") || grpTitle.contains("stations") || grpTitle.contains("станции")
                    let isSongStation = !lower.contains("similar") && !lower.contains("подобные") && !grpTitle.contains("stations")
                    if !isArtistStation || isSongStation {
                        continue
                    }

                    seenStationIds.insert(res.id)
                    if firstArtistRawName == nil {
                        firstArtistRawName = res.name
                    }

                    let cleanName = res.name
                        .replacingOccurrences(of: " & Similar Artists Station", with: "")
                        .replacingOccurrences(of: " Station", with: "")
                        .replacingOccurrences(of: " и другие подобные артисты", with: "")
                        .replacingOccurrences(of: " Станция", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let sTitle = isRu ? "\(cleanName) и другие подобные артисты" : "\(cleanName) & Similar Artists"
                    let sSub = res.subtitle ?? (isRu ? "Радиостанция по артисту" : "Artist Station")
                    let sUrl = res.url ?? "https://music.apple.com/station/\(res.id)"
                    let sArt = (res.artworkUrl?.isEmpty == false) ? res.artworkUrl! : "/assets/stations/CoverDiscovery.png"

                    artistStations.append(StationInfo(
                        id: res.id,
                        name: sTitle,
                        subtitle: sSub,
                        artwork: sArt,
                        url: sUrl,
                        isLive: false,
                        color: "linear-gradient(135deg, #1c1c1e, #3a3a3c)"
                    ))
                }
            }

            if let firstArtist = artistStations.first {
                heroCards.append([
                    "index": 7,
                    "title": firstArtist.name,
                    "name": firstArtistRawName ?? firstArtist.name,
                    "subtitle": firstArtist.subtitle,
                    "sub": firstArtist.subtitle,
                    "tag": isRu ? "Радиостанция по артисту" : "Artist Station",
                    "id": firstArtist.id,
                    "type": "station",
                    "url": firstArtist.url,
                    "artwork": firstArtist.artwork
                ])
            }

            stations.append(contentsOf: artistStations)
        } else {
            let pName = "Apple Music 1 Live"
            let pUrl = "https://music.apple.com/us/station/apple-music-1/ra.978194965"
            let pArt = "/assets/stations/CoverAppleMusic1.png"
            heroCards.append([
                "index": 1,
                "title": pName,
                "name": pName,
                "subtitle": isRu ? "Главные мировые релизы в прямом эфире" : "The new music that matters, live 24/7",
                "sub": isRu ? "Главные мировые релизы в прямом эфире" : "The new music that matters, live 24/7",
                "tag": isRu ? "Прямой эфир" : "Live Radio",
                "id": "station_am1",
                "type": "station",
                "url": pUrl,
                "artwork": pArt
            ])

            let dName = isRu ? "Pop Hits" : "Today's Hits Radio"
            let dUrl = "https://music.apple.com/us/station/hits-station/ra.985480047"
            let dArt = "/assets/stations/CoverHits.png"
            heroCards.append([
                "index": 2,
                "title": dName,
                "name": dName,
                "subtitle": isRu ? "Самые популярные поп-треки мира" : "The biggest pop anthems right now",
                "sub": isRu ? "Самые популярные поп-треки мира" : "The biggest pop anthems right now",
                "tag": isRu ? "Радиостанция" : "Radio Station",
                "id": "station_pop",
                "type": "station",
                "url": dUrl,
                "artwork": dArt
            ])

            var libraryPlaylists = MusicBridge.shared.getPlaylists()
            if libraryPlaylists.isEmpty {
                libraryPlaylists = [
                    PlaylistInfo(name: isRu ? "Любимые песни" : "Favorite Songs", trackCount: 50, artworkUrl: "/assets/stations/CoverElectronic.png", isPlaylist: true)
                ]
            }
            for pl in libraryPlaylists.prefix(2) {
                let enc = pl.name.amrQueryValueEncoded
                let art = pl.artworkUrl ?? "/api/artwork/playlist?name=\(enc)"
                let countStr = isRu
                    ? "\(pl.trackCount) треков"
                    : "\(pl.trackCount) \(pl.trackCount == 1 ? "track" : "tracks")"
                heroCards.append([
                    "index": heroCards.count + 1,
                    "title": pl.name,
                    "name": pl.name,
                    "subtitle": countStr,
                    "sub": countStr,
                    "tag": isRu ? "Плейлист медиатеки" : "Library Playlist",
                    "id": pl.name,
                    "type": "playlist",
                    "url": "",
                    "artwork": art,
                    "track_count": pl.trackCount
                ])
            }

            let neededAlbumCards = max(0, 7 - heroCards.count)
            for album in topAlbums.prefix(neededAlbumCards) {
                let aName = album["name"] as? String ?? ""
                let aArtist = album["artist"] as? String ?? ""
                let aId = album["id"] as? String ?? ""
                let aArt = album["artwork"] as? String ?? ""
                let safeAid = MusicKitManager.isValidResourceIdentifier(aId) ? aId : ""
                let aUrl = album["url"] as? String ?? (!safeAid.isEmpty ? "https://music.apple.com/album/\(safeAid)" : "")
                heroCards.append([
                    "index": heroCards.count + 1,
                    "title": aName,
                    "name": aName,
                    "subtitle": aArtist,
                    "sub": aArtist,
                    "tag": isRu ? "Топ-альбом" : "Top Album",
                    "id": aId,
                    "type": "album",
                    "url": aUrl,
                    "artwork": aArt
                ])
            }
        }

        var newReleases: [[String: Any]] = []
        for grp in personalRecs {
            let t = grp.title.lowercased()
            if t.contains("new release") || t.contains("релиз") || t.contains("новинк") {
                for res in grp.contents where MusicKitManager.isValidResourceIdentifier(res.id) {
                    newReleases.append([
                        "id": res.id,
                        "name": res.name,
                        "artist": res.subtitle ?? "",
                        "subtitle": res.subtitle ?? "",
                        "artwork": res.artworkUrl ?? "",
                        "artwork_url": res.artworkUrl ?? "",
                        "url": res.url ?? "https://music.apple.com/album/\(res.id)",
                        "type": "album"
                    ])
                }
            }
        }

        var feed: [String: Any] = [
            "country": c,
            "hero_cards": heroCards,
            "stations": stations,
            "hot_tracks": hotTracks,
            "top_songs": topSongs,
            "top_albums": topAlbums,
            "genres": genres
        ]
        if !newReleases.isEmpty {
            feed["new_releases"] = newReleases
        }

        let recentTracks = MusicBridge.shared.getRecentlyPlayed(limit: 30)
        if !recentTracks.isEmpty {
            feed["recently_played"] = recentTracks.map { t -> [String: Any] in
                var dict: [String: Any] = [
                    "id": t.id,
                    "name": t.name,
                    "artist": t.artist,
                    "album": t.album,
                    "artwork": t.artworkUrl,
                    "duration": t.duration,
                    "url": t.url ?? ""
                ]
                if let num = t.numericId {
                    dict["numericId"] = num
                }
                return dict
            }
        }

        var seenMixIds = Set(personalMixes.compactMap { $0.id })
        let supplementalMixes: [PlaylistInfo] = [
            PlaylistInfo(
                name: isRu ? "Итоги года Replay" : "Replay",
                trackCount: 100,
                artworkUrl: "/assets/stations/CoverRock.png",
                isPlaylist: true,
                id: "replay_playlist",
                url: "",
                curatorName: "Apple Music Replay",
                description: isRu ? "Ваши главные треки года" : "Your top tracks of the year"
            ),
            PlaylistInfo(
                name: isRu ? "Главные новинки" : "New Music Daily",
                trackCount: 50,
                artworkUrl: "https://is1-ssl.mzstatic.com/image/thumb/Features112/v4/1b/c4/5a/1bc45ab2-799c-1f0d-196a-2bd8e4b628c1/f45875f7-c3b9-4e13-8f7a-498d4ef3a4ef.png/600x600bb.jpg",
                isPlaylist: true,
                id: "pl.2b0e6e332fdf4b7a91164da3162127b5",
                url: "https://music.apple.com/us/playlist/new-music-daily/pl.2b0e6e332fdf4b7a91164da3162127b5",
                curatorName: "Apple Music",
                description: isRu ? "Самые горячие премьеры недели" : "Today's essential new tracks"
            ),
            PlaylistInfo(
                name: isRu ? "Хиты сегодня" : "Today’s Hits",
                trackCount: 50,
                artworkUrl: "https://is1-ssl.mzstatic.com/image/thumb/Features112/v4/e4/2a/9c/e42a9c40-5b85-3842-d068-c3b07c92a431/99f18f2b-47dc-491b-a1ef-9c0c20b9c8e1.png/600x600bb.jpg",
                isPlaylist: true,
                id: "pl.f4d106fed2bd41149aaacabb233eb5eb",
                url: "https://music.apple.com/us/playlist/todays-hits/pl.f4d106fed2bd41149aaacabb233eb5eb",
                curatorName: "Apple Music",
                description: isRu ? "Главные мировые хиты этой недели" : "The biggest songs right now"
            ),
            PlaylistInfo(
                name: isRu ? "Чистый релакс" : "Pure Chill",
                trackCount: 60,
                artworkUrl: "/assets/stations/CoverChill.png",
                isPlaylist: true,
                id: "pl.c7be009ba325420394d51269b3c4a9fe",
                url: "https://music.apple.com/us/playlist/pure-chill/pl.c7be009ba325420394d51269b3c4a9fe",
                curatorName: "Apple Music Chill",
                description: isRu ? "Атмосферные треки для отдыха и концентрации" : "Unwind with peaceful sounds"
            ),
            PlaylistInfo(
                name: isRu ? "Энергия тренировки" : "Pure Workout",
                trackCount: 50,
                artworkUrl: "/assets/stations/CoverHits.png",
                isPlaylist: true,
                id: "pl.79a5236f99f64f1f916c0b818c300f9b",
                url: "https://music.apple.com/us/playlist/pure-workout/pl.79a5236f99f64f1f916c0b818c300f9b",
                curatorName: "Apple Music Fitness",
                description: isRu ? "Максимальный темп и драйв" : "High-energy workout anthems"
            )
        ]

        for extra in supplementalMixes {
            if let eid = extra.id, !seenMixIds.contains(eid) {
                let hasReplayAlready = eid == "replay_playlist" && personalMixes.contains(where: {
                    let n = $0.name.lowercased()
                    return n.contains("replay") || n.contains("итоги")
                })
                if !hasReplayAlready {
                    seenMixIds.insert(eid)
                    personalMixes.append(extra)
                }
            }
        }

        if !personalMixes.isEmpty {
            feed["personal_mixes"] = personalMixes.map { mix in
                [
                    "id": mix.id ?? "",
                    "name": mix.name,
                    "track_count": mix.trackCount,
                    "artwork": mix.artworkUrl ?? "",
                    "artwork_url": mix.artworkUrl ?? "",
                    "url": mix.url ?? "",
                    "curator_name": mix.curatorName ?? "Apple Music",
                    "description": mix.description ?? ""
                ]
            }
        }

        if !personalRecs.isEmpty {
            feed["personal_recommendations"] = personalRecs.map { grp in
                [
                    "id": grp.id,
                    "title": grp.title,
                    "contents": grp.contents.map { res in
                        [
                            "id": res.id,
                            "type": res.type,
                            "name": res.name,
                            "subtitle": res.subtitle ?? "",
                            "artwork": res.artworkUrl ?? "",
                            "url": res.url ?? ""
                        ]
                    }
                ]
            }
        }

        feedLock.withLock {
            if cachedFeed[c] == nil && cachedFeed.count >= Self.maxCachedFeedEntries,
               let oldestKey = cachedFeed.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
                cachedFeed.removeValue(forKey: oldestKey)
            }
            cachedFeed[c] = (timestamp: Date(), feed: feed)
        }

        return feed
    }

    public func invalidateExploreFeedCache() {
        feedLock.withLock {
            cachedFeed.removeAll()
        }
        NSLog("[CloudCatalogService] 🔄 Invalidated explore feed cache")
    }
}
