//
//  CloudCatalogService.swift
//  AppleMusicRemoteMac
//
//  Pure Swift cloud catalog search, curated radio stations, and iTunes charts
//

import Foundation

public final class CloudCatalogService: @unchecked Sendable {
    public static let shared = CloudCatalogService()

    private let session: URLSession
    private var cachedFeed: [String: (timestamp: Date, feed: [String: Any])] = [:]
    private let feedLock = NSLock()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8.0
        config.timeoutIntervalForResource = 12.0
        self.session = URLSession(configuration: config)
    }

    // MARK: - Artwork URL Helper

    public func upgradeArtworkUrl(_ url: String) -> String {
        guard !url.isEmpty else { return "" }
        var result = url
        if result.contains("{w}") || result.contains("{h}") {
            result = result
                .replacingOccurrences(of: "{w}", with: "600")
                .replacingOccurrences(of: "{h}", with: "600")
                .replacingOccurrences(of: "{f}", with: "jpg")
                .replacingOccurrences(of: "{c}", with: "bb")
        }
        if let regex = try? NSRegularExpression(pattern: "/\\d+x\\d+bb\\.(jpg|png|webp)", options: []) {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "/600x600bb.$1")
        }
        return result
    }

    // MARK: - Curated Stations Catalog

    public func getCuratedStations(country: String = "ru") -> [StationInfo] {
        let c = country.lowercased()
        let isRu = ["ru", "kz", "by", "ua"].contains(c)

        return [
            StationInfo(
                id: "station_personal",
                name: isRu ? "Моя станция (Кирилл Шолохов)" : "My Station (Kirill Sholokhov)",
                subtitle: isRu ? "Любимые треки и персональные рекомендации" : "Favorite tracks & personal recommendations",
                artwork: "/assets/stations/CoverPersonal.png",
                url: "https://music.apple.com/station/my-station/ra.u-96b95a031a2fb0aa1abb70ff757aa95f",
                isLive: false,
                color: "linear-gradient(135deg, #fa233b, #fb5c74)"
            ),
            StationInfo(
                id: "station_discovery",
                name: isRu ? "Станция открытий" : "Discovery Station",
                subtitle: isRu ? "Новая музыка на основе ваших вкусов" : "New music based on what you love",
                artwork: "/assets/stations/CoverDiscovery.png",
                url: "https://music.apple.com/station/item/ra.q-GAI6IDk2Yjk1YTAzMWEyZmIwYWExYWJiNzBmZjc1N2FhOTVm",
                isLive: false,
                color: "linear-gradient(135deg, #7928ca, #ff0080)"
            ),
            StationInfo(
                id: "station_am1",
                name: "Apple Music 1 Live",
                subtitle: isRu ? "Главные мировые релизы в прямом эфире" : "The new music that matters, live 24/7",
                artwork: "/assets/stations/CoverAppleMusic1.png",
                url: "https://music.apple.com/us/station/apple-music-1/ra.978194965",
                isLive: true,
                color: "linear-gradient(135deg, #1c1c1e, #3a3a3c)"
            ),
            StationInfo(
                id: "station_hits",
                name: "Apple Music Hits",
                subtitle: isRu ? "Культовые хиты 80-х, 90-х и 2000-х" : "The songs you know and love",
                artwork: "https://is1-ssl.mzstatic.com/image/thumb/Features221/v4/27/b7/ec/27b7eca8-5bb2-3c46-ca1e-be2877a3cc91/feb0dc99-412b-4688-b8d6-c0fa07059558.png/600x600sr.jpg",
                url: "https://music.apple.com/us/station/apple-music-hits/ra.1498155548",
                isLive: true,
                color: "linear-gradient(135deg, #ff0844, #ffb199)"
            ),
            StationInfo(
                id: "station_country",
                name: "Apple Music Country",
                subtitle: isRu ? "Современное и классическое кантри" : "Where country music lives",
                artwork: "https://is1-ssl.mzstatic.com/image/thumb/Features/v4/89/37/3f/89373f8b-0fe9-ab3d-713d-1ed8b9cb3336/0799e8e4-e4be-44ab-8c3a-aefd9cf8d174.png/600x600sr.jpg",
                url: "https://music.apple.com/us/station/apple-music-country/ra.1498157166",
                isLive: true,
                color: "linear-gradient(135deg, #f7971e, #ffd200)"
            ),
            StationInfo(
                id: "station_chill",
                name: isRu ? "Chill & Lo-Fi" : "Chill Station",
                subtitle: isRu ? "Спокойный ритм и фоновые биты" : "Laid-back sounds and mellow beats",
                artwork: "https://is1-ssl.mzstatic.com/image/thumb/Features/v4/f5/54/f5/f554f538-499a-3dec-1054-d7a90f633e1a/5211c0ce-9a10-4857-b0d0-ea2311fb1fed.png/600x600sr.jpg",
                url: "https://music.apple.com/us/station/chill-station/ra.985484943",
                isLive: false,
                color: "linear-gradient(135deg, #00b4db, #0083b0)"
            ),
            StationInfo(
                id: "station_pop",
                name: isRu ? "Pop Hits" : "Today's Hits Radio",
                subtitle: isRu ? "Самые популярные поп-треки мира" : "The biggest pop anthems right now",
                artwork: "https://is1-ssl.mzstatic.com/image/thumb/Features221/v4/c1/94/de/c194deaa-eae8-75e6-0402-85a45bf76408/ec85d0a7-7073-441d-95be-fd1c4cfdc348.png/600x600sr.jpg",
                url: "https://music.apple.com/us/station/hits-station/ra.985480047",
                isLive: false,
                color: "linear-gradient(135deg, #fa2d48, #ff6b8b)"
            ),
            StationInfo(
                id: "station_rock",
                name: isRu ? "Rock Classics" : "Rock Classics Radio",
                subtitle: isRu ? "Культовые рок-гимны и гитарные соло" : "Greatest guitar anthems & classic rock",
                artwork: "https://is1-ssl.mzstatic.com/image/thumb/Features/v4/db/ba/e4/dbbae45c-8d9a-5c45-3c6b-d8662f0a5873/c07ee270-72ba-4c0d-b01d-bac5d595bbab.png/600x600sr.jpg",
                url: "https://music.apple.com/us/station/classic-rock-station/ra.985500514",
                isLive: false,
                color: "linear-gradient(135deg, #e65100, #ff9800)"
            ),
            StationInfo(
                id: "station_hiphop",
                name: isRu ? "Hip-Hop" : "Hip-Hop & R&B",
                subtitle: isRu ? "Плотные биты и свежие релизы" : "Heavy beats and groundbreaking rap",
                artwork: "https://is1-ssl.mzstatic.com/image/thumb/Features/v4/88/89/43/888943a0-6ce9-c778-5120-8f7ad49bbb73/76991844-0242-404d-949d-ba28b7432f51.png/600x600sr.jpg",
                url: "https://music.apple.com/us/station/hip-hop-station/ra.985488923",
                isLive: false,
                color: "linear-gradient(135deg, #4a148c, #7b1fa2)"
            ),
            StationInfo(
                id: "station_electronic",
                name: isRu ? "Dance & Electronic" : "Dance & Electronic",
                subtitle: isRu ? "Клубный драйв и танцевальная энергия" : "Non-stop club bangers & festival anthems",
                artwork: "https://is1-ssl.mzstatic.com/image/thumb/Features211/v4/0b/36/19/0b36194e-bca3-ca9b-0e0d-f25afacff780/81fc6d0f-6f9d-4d14-ab92-036f5024d6e2.png/600x600sr.jpg",
                url: "https://music.apple.com/us/station/dance-station/ra.985487895",
                isLive: false,
                color: "linear-gradient(135deg, #00695c, #00bfa5)"
            ),
            StationInfo(
                id: "station_deephouse",
                name: "Deep House",
                subtitle: isRu ? "Глубокое электронное звучание" : "Deep melodic house & hypnotic rhythms",
                artwork: "https://is1-ssl.mzstatic.com/image/thumb/Features122/v4/76/66/fd/7666fdf7-1ff0-799e-f1b9-25eb41de9d93/5e4b0619-cc57-4ae6-a3a9-f2620ca68bcc.png/600x600sr.jpg",
                url: "https://music.apple.com/us/station/house-station/ra.991194049",
                isLive: false,
                color: "linear-gradient(135deg, #880e4f, #d81b60)"
            ),
            StationInfo(
                id: "station_jazz",
                name: isRu ? "Jazz" : "Jazz & Blues",
                subtitle: isRu ? "Безупречная классика джаза" : "Timeless jazz standards & soothing brass",
                artwork: "https://is1-ssl.mzstatic.com/image/thumb/Features/v4/06/2e/6c/062e6ce2-1492-456e-091d-880f84d6837e/107f3a79-1ff9-4f6c-9749-f9e53dbc76bf.png/600x600sr.jpg",
                url: "https://music.apple.com/us/station/jazz-station/ra.985496180",
                isLive: false,
                color: "linear-gradient(135deg, #37474f, #78909c)"
            )
        ]
    }

    // MARK: - Search Apple Music / iTunes

    public func search(query: String, country: String = "ru", source: String? = "cloud") async -> [String: AnyCodable] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [
                "artists": AnyCodable([]),
                "songs": AnyCodable([]),
                "albums": AnyCodable([]),
                "all": AnyCodable([])
            ]
        }

        let c = country.isEmpty ? "ru" : country.lowercased()

        let encodedQ = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query

        // Always query local library / cloud tracks in Music.app first
        var localSongDicts = [[String: Any]]()
        let librarySongs = MusicBridge.shared.getLibrarySongs()
        let lowerQ = query.lowercased()
        let filtered = librarySongs.filter {
            $0.name.lowercased().contains(lowerQ) ||
            $0.artist.lowercased().contains(lowerQ) ||
            $0.album.lowercased().contains(lowerQ)
        }
        for t in filtered {
            localSongDicts.append([
                "id": t.id,
                "numeric_id": t.numericId ?? 0,
                "name": t.name,
                "artist": t.artist,
                "album": t.album,
                "duration": t.duration,
                "artwork_url": t.artworkUrl,
                "favorited": t.favorited,
                "is_local": true
            ])
        }

        if source == "library" {
            return [
                "artists": AnyCodable([]),
                "songs": AnyCodable(localSongDicts),
                "albums": AnyCodable([])
            ]
        }

        // 1. Try official Apple Music API with MusicKit developer token
        if let appleMusicResults = await MusicKitManager.shared.searchAppleMusic(query: query, storefront: c) {
            var res = [String: AnyCodable]()
            var cloudSongs = (appleMusicResults["songs"] as? [[String: Any]]) ?? []
            let mergedSongs = localSongDicts + cloudSongs
            res["songs"] = AnyCodable(mergedSongs)
            if let albums = appleMusicResults["albums"] as? [[String: Any]] {
                res["albums"] = AnyCodable(albums)
            }
            if let artists = appleMusicResults["artists"] as? [[String: Any]] {
                res["artists"] = AnyCodable(artists)
            }
            if !res.isEmpty {
                return res
            }
        }

        // 2. Fallback to iTunes Store Search API
        async let artistsTask = fetchArtists(query: encodedQ, country: c)
        async let songsTask = fetchSongs(query: encodedQ, country: c)
        async let albumsTask = fetchAlbums(query: encodedQ, country: c)

        let (artists, songs, albums) = await (artistsTask, songsTask, albumsTask)

        return [
            "artists": AnyCodable(artists),
            "songs": AnyCodable(localSongDicts + songs),
            "albums": AnyCodable(albums)
        ]
    }

    private func fetchArtists(query: String, country: String) async -> [[String: Any]] {
        let urlStr = "https://itunes.apple.com/search?term=\(query)&entity=musicArtist&country=\(country)&limit=8"
        guard let url = URL(string: urlStr) else { return [] }

        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await session.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }

        var list = [[String: Any]]()
        for it in results {
            let name = it["artistName"] as? String ?? ""
            let genre = it["primaryGenreName"] as? String ?? ""
            let url = it["artistLinkUrl"] as? String ?? ""
            let aid = "\(it["artistId"] ?? "")"
            list.append([
                "type": "artist",
                "id": aid,
                "name": name,
                "genre": genre,
                "url": url
            ])
        }
        return list
    }

    private func fetchSongs(query: String, country: String) async -> [[String: Any]] {
        let urlStr = "https://itunes.apple.com/search?term=\(query)&entity=song&country=\(country)&limit=25"
        guard let url = URL(string: urlStr) else { return [] }

        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await session.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }

        var list = [[String: Any]]()
        for it in results {
            let name = it["trackName"] as? String ?? ""
            let artist = it["artistName"] as? String ?? ""
            let album = it["collectionName"] as? String ?? ""
            let url = it["trackViewUrl"] as? String ?? ""
            let rawArt = it["artworkUrl100"] as? String ?? ""
            let art = upgradeArtworkUrl(rawArt)
            let durMs = (it["trackTimeMillis"] as? Double) ?? 0
            let tid = "\(it["trackId"] ?? "")"
            let preview = it["previewUrl"] as? String ?? ""

            list.append([
                "type": "song",
                "id": tid,
                "name": name,
                "artist": artist,
                "album": album,
                "duration": durMs / 1000.0,
                "artwork": art,
                "artwork_url": art,
                "url": url,
                "preview_url": preview
            ])
        }
        return list
    }

    private func fetchAlbums(query: String, country: String) async -> [[String: Any]] {
        let urlStr = "https://itunes.apple.com/search?term=\(query)&entity=album&country=\(country)&limit=12"
        guard let url = URL(string: urlStr) else { return [] }

        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await session.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }

        var list = [[String: Any]]()
        for it in results {
            let name = it["collectionName"] as? String ?? ""
            let artist = it["artistName"] as? String ?? ""
            let url = it["collectionViewUrl"] as? String ?? ""
            let rawArt = it["artworkUrl100"] as? String ?? ""
            let art = upgradeArtworkUrl(rawArt)
            let relDate = it["releaseDate"] as? String ?? ""
            let tCount = (it["trackCount"] as? Int) ?? 0
            let aid = "\(it["collectionId"] ?? "")"

            list.append([
                "type": "album",
                "id": aid,
                "name": name,
                "artist": artist,
                "artwork": art,
                "artwork_url": art,
                "release_date": relDate,
                "track_count": tCount,
                "url": url
            ])
        }
        return list
    }

    // MARK: - Explore Feed

    public func getExploreFeed(country: String = "ru") async -> [String: Any] {
        let c = country.isEmpty ? "ru" : country.lowercased()

        feedLock.lock()
        if let cached = cachedFeed[c], Date().timeIntervalSince(cached.timestamp) < 600.0 {
            feedLock.unlock()
            return cached.feed
        }
        feedLock.unlock()

        let stations = getCuratedStations(country: c)

        let genres: [[String: String]] = [
            ["name": "🔥 Поп-музыка", "query": "Pop Hits", "color": "linear-gradient(135deg, #fa2d48, #ff6b8b)"],
            ["name": "🎸 Рок & Альтернатива", "query": "Rock Classics", "color": "linear-gradient(135deg, #e65100, #ff9800)"],
            ["name": "🎤 Хип-хоп & Рэп", "query": "Hip Hop", "color": "linear-gradient(135deg, #4a148c, #7b1fa2)"],
            ["name": "⚡ Электроника & Dance", "query": "Dance Electronic", "color": "linear-gradient(135deg, #00695c, #00bfa5)"],
            ["name": "☕ Chill & Lo-Fi", "query": "Chill Beats", "color": "linear-gradient(135deg, #1565c0, #42a5f5)"],
            ["name": "🎻 Неоклассика", "query": "Neoclassical", "color": "linear-gradient(135deg, #37474f, #78909c)"],
            ["name": "🎬 Саундтреки", "query": "Soundtrack Movie", "color": "linear-gradient(135deg, #880e4f, #d81b60)"]
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

        // Variant 3: Hybrid Hero Cards
        var heroCards: [[String: Any]] = []

        // Card 1: "Моя станция" (Personal Station)
        heroCards.append([
            "index": 1,
            "title": "Моя станция",
            "name": "Моя станция",
            "subtitle": "Персональная радиостанция",
            "sub": "Персональная радиостанция",
            "tag": "Специально для вас",
            "id": "ra.u-96b95a031a2fb0aa1abb70ff757aa95f",
            "type": "station",
            "url": "https://music.apple.com/station/my-station/ra.u-96b95a031a2fb0aa1abb70ff757aa95f",
            "artwork": "/assets/stations/CoverPersonal.png"
        ])

        // Card 2: "Станция открытий" (Discovery Station)
        heroCards.append([
            "index": 2,
            "title": "Станция открытий",
            "name": "Станция открытий",
            "subtitle": "Новые треки под ваш вкус",
            "sub": "Новые треки под ваш вкус",
            "tag": "Радиостанция",
            "id": "ra.q-GAI6IDk2Yjk1YTAzMWEyZmIwYWExYWJiNzBmZjc1N2FhOTVm",
            "type": "station",
            "url": "https://music.apple.com/station/item/ra.q-GAI6IDk2Yjk1YTAzMWEyZmIwYWExYWJiNzBmZjc1N2FhOTVm",
            "artwork": "/assets/stations/CoverDiscovery.png"
        ])

        // Cards 3-4: User's library playlists (MusicBridge.shared.getPlaylists())
        var libraryPlaylists = MusicBridge.shared.getPlaylists()
        if libraryPlaylists.isEmpty {
            libraryPlaylists = [
                PlaylistInfo(name: "Любимые песни", trackCount: 296, artworkUrl: "/api/artwork/playlist?name=%D0%9B%D1%8E%D0%B1%D0%B8%D0%BC%D1%8B%D0%B5%20%D0%BF%D0%B5%D1%81%D0%BD%D0%B8", isPlaylist: true),
                PlaylistInfo(name: "Ностальгия по ню-металу", trackCount: 98, artworkUrl: "/api/artwork/playlist?name=%D0%9D%D0%BE%D1%81%D1%82%D0%B0%D0%BB%D1%8C%D0%B3%D0%B8%D1%8F%20%D0%BF%D0%BE%20%D0%BD%D1%8E-%D0%BC%D0%B5%D1%82%D0%B0%D0%BB%D1%83", isPlaylist: true)
            ]
        }
        for pl in libraryPlaylists.prefix(2) {
            let enc = pl.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let art = pl.artworkUrl ?? "/api/artwork/playlist?name=\(enc)"
            let countStr = "\(pl.trackCount) треков"
            heroCards.append([
                "index": heroCards.count + 1,
                "title": pl.name,
                "name": pl.name,
                "subtitle": countStr,
                "sub": countStr,
                "tag": "Плейлист медиатеки",
                "id": pl.name,
                "type": "playlist",
                "url": "",
                "artwork": art,
                "track_count": pl.trackCount
            ])
        }

        // Cards 5-7: Top Storefront Albums from topAlbums RSS / MusicKit
        let neededAlbumCards = max(0, 7 - heroCards.count)
        for album in topAlbums.prefix(neededAlbumCards) {
            let aName = album["name"] as? String ?? ""
            let aArtist = album["artist"] as? String ?? ""
            let aId = album["id"] as? String ?? ""
            let aArt = album["artwork"] as? String ?? ""
            let aUrl = album["url"] as? String ?? (!aId.isEmpty ? "https://music.apple.com/album/\(aId)" : "")
            heroCards.append([
                "index": heroCards.count + 1,
                "title": aName,
                "name": aName,
                "subtitle": aArtist,
                "sub": aArtist,
                "tag": "Топ-альбом",
                "id": aId,
                "type": "album",
                "url": aUrl,
                "artwork": aArt
            ])
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

        let recentTracks = MusicBridge.shared.getRecentlyPlayed(limit: 30)
        if !recentTracks.isEmpty {
            feed["recently_played"] = recentTracks.map { t in
                [
                    "id": t.id,
                    "numericId": t.numericId as Any,
                    "name": t.name,
                    "artist": t.artist,
                    "album": t.album,
                    "artwork": t.artworkUrl,
                    "duration": t.duration,
                    "url": t.url ?? ""
                ]
            }
        }

        feedLock.lock()
        cachedFeed[c] = (timestamp: Date(), feed: feed)
        feedLock.unlock()

        return feed
    }

    private func fetchTopSongsRSS(country: String) async -> [[String: Any]] {
        let urlStr = "https://itunes.apple.com/\(country)/rss/topsongs/limit=50/json"
        guard let url = URL(string: urlStr) else { return [] }

        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await session.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feed = json["feed"] as? [String: Any],
              let entries = feed["entry"] as? [[String: Any]] else {
            return []
        }

        var parsed = [[String: Any]]()
        var rank = 1

        for e in entries {
            let name = (e["im:name"] as? [String: Any])?["label"] as? String ?? ""
            let artist = (e["im:artist"] as? [String: Any])?["label"] as? String ?? ""

            var artUrl = ""
            if let images = e["im:image"] as? [[String: Any]], let lastImg = images.last {
                artUrl = upgradeArtworkUrl(lastImg["label"] as? String ?? "")
            }

            var urlStr = ""
            var previewUrl = ""
            if let links = e["link"] as? [[String: Any]] {
                if let first = links.first, let attrs = first["attributes"] as? [String: Any] {
                    urlStr = attrs["href"] as? String ?? ""
                }
                for l in links {
                    if let attrs = l["attributes"] as? [String: Any] {
                        let rel = attrs["rel"] as? String ?? ""
                        let type = attrs["type"] as? String ?? ""
                        if rel == "enclosure" || type.contains("audio") {
                            previewUrl = attrs["href"] as? String ?? ""
                            break
                        }
                    }
                }
            } else if let link = e["link"] as? [String: Any], let attrs = link["attributes"] as? [String: Any] {
                urlStr = attrs["href"] as? String ?? ""
            }

            let idStr = (e["id"] as? [String: Any])?["attributes"] as? [String: Any]
            let trackId = idStr?["im:id"] as? String ?? ""

            parsed.append([
                "rank": rank,
                "id": trackId,
                "name": name,
                "artist": artist,
                "artwork": artUrl,
                "url": urlStr,
                "preview_url": previewUrl
            ])
            rank += 1
        }

        return parsed
    }

    private func fetchTopAlbumsRSS(country: String) async -> [[String: Any]] {
        let urlStr = "https://itunes.apple.com/\(country)/rss/topalbums/limit=50/json"
        guard let url = URL(string: urlStr) else { return [] }

        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await session.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feed = json["feed"] as? [String: Any],
              let entries = feed["entry"] as? [[String: Any]] else {
            return []
        }

        var parsed = [[String: Any]]()
        var rank = 1

        for e in entries {
            let name = (e["im:name"] as? [String: Any])?["label"] as? String ?? ""
            let artist = (e["im:artist"] as? [String: Any])?["label"] as? String ?? ""

            var artUrl = ""
            if let images = e["im:image"] as? [[String: Any]], let lastImg = images.last {
                artUrl = upgradeArtworkUrl(lastImg["label"] as? String ?? "")
            }

            var urlStr = ""
            if let links = e["link"] as? [[String: Any]], let first = links.first, let attrs = first["attributes"] as? [String: Any] {
                urlStr = attrs["href"] as? String ?? ""
            } else if let link = e["link"] as? [String: Any], let attrs = link["attributes"] as? [String: Any] {
                urlStr = attrs["href"] as? String ?? ""
            }

            let idStr = (e["id"] as? [String: Any])?["attributes"] as? [String: Any]
            let albumId = idStr?["im:id"] as? String ?? ""

            parsed.append([
                "rank": rank,
                "id": albumId,
                "name": name,
                "artist": artist,
                "artwork": artUrl,
                "url": urlStr
            ])
            rank += 1
        }

        return parsed
    }

    // MARK: - Album Details

    public func getAlbumDetails(albumId: String, country: String = "ru") async -> AlbumInfo? {
        guard !albumId.isEmpty else { return nil }
        let c = country.isEmpty ? "ru" : country.lowercased()

        // 1. Primary: Official Apple Music Catalog API via Developer Token
        if let mkAlbum = await MusicKitManager.shared.getAlbumDetailsById(albumId: albumId, storefront: c),
           let tracks = mkAlbum.tracks, !tracks.isEmpty {
            return mkAlbum
        }
        if c != "us", let usAlbum = await MusicKitManager.shared.getAlbumDetailsById(albumId: albumId, storefront: "us"),
           let tracks = usAlbum.tracks, !tracks.isEmpty {
            return usAlbum
        }

        // 2. Secondary fallback: iTunes Lookup API
        let urlStr = "https://itunes.apple.com/lookup?id=\(albumId)&entity=song&country=\(c)"
        guard let url = URL(string: urlStr) else { return nil }

        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await session.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]], !results.isEmpty else {
            return nil
        }

        let albumMeta = results[0]
        let aName = albumMeta["collectionName"] as? String ?? ""
        let aArtist = albumMeta["artistName"] as? String ?? ""
        let aArt = upgradeArtworkUrl(albumMeta["artworkUrl100"] as? String ?? "")
        let relDate = albumMeta["releaseDate"] as? String ?? ""
        let genre = albumMeta["primaryGenreName"] as? String ?? ""
        let aUrl = albumMeta["collectionViewUrl"] as? String ?? ""
        let tCount = albumMeta["trackCount"] as? Int ?? 0

        var tracks = [TrackInfo]()
        for i in 1..<results.count {
            let it = results[i]
            if (it["wrapperType"] as? String) == "track" {
                let tName = it["trackName"] as? String ?? ""
                let tArtist = it["artistName"] as? String ?? aArtist
                let tUrl = it["trackViewUrl"] as? String ?? ""
                let tArt = upgradeArtworkUrl(it["artworkUrl100"] as? String ?? aArt)
                let durMs = (it["trackTimeMillis"] as? Double) ?? 0
                let tNum = (it["trackNumber"] as? Int) ?? (tracks.count + 1)
                let tid = "\(it["trackId"] ?? "")"
                let preview = it["previewUrl"] as? String ?? ""

                tracks.append(TrackInfo(
                    id: tid,
                    numericId: Int(tid),
                    name: tName,
                    artist: tArtist,
                    album: aName,
                    duration: durMs / 1000.0,
                    hasArtwork: !tArt.isEmpty,
                    artworkUrl: tArt,
                    favorited: false,
                    isLocal: false,
                    url: tUrl,
                    previewUrl: preview,
                    index: tNum
                ))
            }
        }

        return AlbumInfo(
            id: albumId,
            name: aName,
            artist: aArtist,
            artwork: aArt,
            releaseDate: relDate,
            trackCount: tCount > 0 ? tCount : tracks.count,
            genre: genre,
            url: aUrl,
            tracks: tracks
        )
    }
}
