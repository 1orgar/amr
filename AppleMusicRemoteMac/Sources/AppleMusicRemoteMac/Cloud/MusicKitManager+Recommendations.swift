//
//  MusicKitManager+Recommendations.swift
//  AppleMusicRemoteMac
//

import Foundation

extension MusicKitManager {
    public func setCachedPersonalData(_ cache: PersonalDataCache) {
        lock.lock()
        defer { lock.unlock() }
        self.personalDataCache = cache
    }

    public func getCachedPlaylistTracks(playlistId: String) -> [TrackInfo]? {
        lock.lock()
        defer { lock.unlock() }
        let cleanId = playlistId.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = playlistTracksCache[cleanId], Date().timeIntervalSince(cached.timestamp) < 3600.0 {
            return cached.tracks
        }
        return nil
    }

    private static let artworkSizeRegex = try? NSRegularExpression(pattern: "/\\d+x\\d+bb\\.(jpg|png|webp)", options: [])

    public static func formatArtworkUrl(_ template: String?, width: Int = 600, height: Int = 600, format: String = "jpg") -> String? {
        guard let template = template, !template.isEmpty else { return nil }
        var result = template
            .replacingOccurrences(of: "{w}x{h}", with: "\(width)x\(height)")
            .replacingOccurrences(of: "{w}", with: "\(width)")
            .replacingOccurrences(of: "{h}", with: "\(height)")
            .replacingOccurrences(of: "{f}", with: format)
            .replacingOccurrences(of: "{c}", with: "bb")
        if let regex = Self.artworkSizeRegex {
            let range = NSRange(location: 0, length: result.utf16.count)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "/\(width)x\(height)bb.$1")
        }
        return result
    }

    // MARK: - REST API Fetchers

    public func fetchPersonalStation() async -> StationInfo? {
        if let cached = getCachedPersonalData()?.personalStation {
            return cached
        }

        guard let devToken = getDeveloperToken(), let uToken = getUserToken(), !uToken.isEmpty else {
            return nil
        }

        let lang = getPreferredLanguageTag()
        guard let url = URL(string: "https://api.music.apple.com/v1/me/stations/personal?l=\(lang)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(lang, forHTTPHeaderField: "Accept-Language")

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
                NSLog("[MusicKitManager] ⚠️ fetchPersonalStation HTTP status %d", status)
                return nil
            }
            if let station = Self.parsePersonalStation(data: data) {
                withLock {
                    var current = self.personalDataCache ?? PersonalDataCache()
                    current.personalStation = station
                    current.timestamp = Date()
                    self.personalDataCache = current
                }
                return station
            }
        } catch {
            NSLog("[MusicKitManager] ❌ fetchPersonalStation error: %@", error.localizedDescription)
        }
        return nil
    }

    public func fetchPersonalRecommendations(limit: Int = 30) async -> [PersonalRecommendationGroup] {
        if let cached = getCachedPersonalData(), !cached.recommendations.isEmpty {
            return cached.recommendations
        }

        guard let devToken = getDeveloperToken(), let uToken = getUserToken(), !uToken.isEmpty else {
            return []
        }

        let lang = getPreferredLanguageTag()
        guard let url = URL(string: "https://api.music.apple.com/v1/me/recommendations?limit=\(limit)&l=\(lang)") else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        req.setValue(uToken, forHTTPHeaderField: "Music-User-Token")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(lang, forHTTPHeaderField: "Accept-Language")

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
                NSLog("[MusicKitManager] ⚠️ fetchPersonalRecommendations HTTP status %d", status)
                return []
            }
            let groups = Self.parsePersonalRecommendations(data: data)
            let mixes = Self.extractMixes(from: groups)
            let (pStation, dStation) = Self.extractStations(from: groups)

            withLock {
                var current = self.personalDataCache ?? PersonalDataCache()
                current.recommendations = groups
                if !mixes.isEmpty { current.mixes = mixes }
                if let p = pStation, current.personalStation == nil { current.personalStation = p }
                if let d = dStation { current.discoveryStation = d }
                current.timestamp = Date()
                self.personalDataCache = current
            }

            return groups
        } catch {
            NSLog("[MusicKitManager] ❌ fetchPersonalRecommendations error: %@", error.localizedDescription)
        }
        return []
    }

    public func fetchPersonalMixes() async -> [PlaylistInfo] {
        if let cached = getCachedPersonalData(), !cached.mixes.isEmpty {
            return cached.mixes
        }
        _ = await fetchPersonalRecommendations(limit: 30)
        return getCachedPersonalData()?.mixes ?? []
    }

    public static let defaultPersonalStationArtwork = "https://is1-ssl.mzstatic.com/image/thumb/Features/v4/e9/31/64/e93164c8-bff1-a5d9-1ad9-99ff0042a5c1/412b88f3-3259-4c12-8d9c-98b28c6371d4.png/600x600sr.jpg"

    public func fetchPersonalStations() async -> (personal: StationInfo?, discovery: StationInfo?) {
        let cached = getCachedPersonalData()
        var p = cached?.personalStation
        var d = cached?.discoveryStation

        if p == nil || d == nil {
            if p == nil {
                p = await fetchPersonalStation()
            }
            if p == nil || d == nil {
                _ = await fetchPersonalRecommendations(limit: 30)
                let updated = getCachedPersonalData()
                if p == nil { p = updated?.personalStation }
                if d == nil { d = updated?.discoveryStation }
            }
        }
        return (p, d)
    }

    // MARK: - Parsers for Personal Content

    public static func parsePersonalStation(data: Data) -> StationInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]],
              let first = arr.first else {
            return nil
        }
        let id = first["id"] as? String ?? "station_personal"
        let attrs = first["attributes"] as? [String: Any] ?? [:]
        let name = attrs["name"] as? String ?? "Моя станция"
        let url = attrs["url"] as? String ?? "https://music.apple.com/station/my-station/\(id)"
        let isLive = attrs["isLive"] as? Bool ?? false
        let artObj = attrs["artwork"] as? [String: Any]
        let artUrl = formatArtworkUrl(artObj?["url"] as? String) ?? defaultPersonalStationArtwork

        return StationInfo(
            id: id,
            name: name,
            subtitle: "Любимые треки и персональные рекомендации",
            artwork: artUrl,
            url: url,
            isLive: isLive,
            color: "linear-gradient(135deg, #fa233b, #fb5c74)",
            isPersonal: true,
            provider: "Apple Music"
        )
    }

    public static func parsePersonalRecommendations(data: Data) -> [PersonalRecommendationGroup] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArr = json["data"] as? [[String: Any]] else {
            return []
        }

        var groups: [PersonalRecommendationGroup] = []

        for item in dataArr {
            let id = item["id"] as? String ?? UUID().uuidString
            let attrs = item["attributes"] as? [String: Any] ?? [:]
            var groupTitle = "Для вас"
            if let titleObj = attrs["title"] as? [String: Any] {
                groupTitle = titleObj["stringForDisplay"] as? String ?? titleObj["text"] as? String ?? groupTitle
            } else if let tStr = attrs["title"] as? String, !tStr.isEmpty {
                groupTitle = tStr
            }

            var resources: [RecommendationResource] = []
            if let relationships = item["relationships"] as? [String: Any],
               let contents = relationships["contents"] as? [String: Any],
               let contentData = contents["data"] as? [[String: Any]] {
                for cItem in contentData {
                    let rId = cItem["id"] as? String ?? ""
                    let rType = cItem["type"] as? String ?? ""
                    let rAttrs = cItem["attributes"] as? [String: Any] ?? [:]
                    let rName = rAttrs["name"] as? String ?? ""
                    let rCurator = rAttrs["curatorName"] as? String
                    let rArtist = rAttrs["artistName"] as? String
                    let rDesc = (rAttrs["description"] as? [String: Any])?["standard"] as? String
                    let rSub = rCurator ?? rArtist ?? rDesc
                    let rUrl = rAttrs["url"] as? String
                    let artObj = rAttrs["artwork"] as? [String: Any]
                    let rArt = formatArtworkUrl(artObj?["url"] as? String)

                    resources.append(RecommendationResource(
                        id: rId,
                        type: rType,
                        name: rName,
                        subtitle: rSub,
                        artworkUrl: rArt,
                        url: rUrl
                    ))
                }
            }

            groups.append(PersonalRecommendationGroup(
                id: id,
                title: groupTitle,
                contents: resources
            ))
        }

        return groups
    }

    public static func extractMixes(from groups: [PersonalRecommendationGroup]) -> [PlaylistInfo] {
        var mixes: [PlaylistInfo] = []
        var secondaryPlaylists: [PlaylistInfo] = []
        var seenIds = Set<String>()

        for group in groups {
            let groupTitleLower = group.title.lowercased()
            // Skip "Recently Played" when collecting mixes so we prioritize fresh recommendations first
            let isRecentlyPlayed = groupTitleLower.contains("recently") || groupTitleLower.contains("недавно")

            for res in group.contents where res.type == "playlists" {
                if seenIds.contains(res.id) { continue }
                let lowerName = res.name.lowercased()
                let isPrimaryMix = res.id.hasPrefix("pl.pm-") ||
                            lowerName.contains("mix") ||
                            lowerName.contains("микс") ||
                            lowerName.contains("favorites") ||
                            lowerName.contains("избранн") ||
                            lowerName.contains("chill") ||
                            lowerName.contains("чилл") ||
                            lowerName.contains("new music") ||
                            lowerName.contains("новинк") ||
                            lowerName.contains("get up") ||
                            lowerName.contains("энерги") ||
                            lowerName.contains("heavy rotation") ||
                            lowerName.contains("повторе") ||
                            lowerName.contains("replay") ||
                            lowerName.contains("итоги") ||
                            groupTitleLower.contains("made for you") ||
                            groupTitleLower.contains("для вас")

                let info = PlaylistInfo(
                    name: res.name,
                    trackCount: 25,
                    artworkUrl: res.artworkUrl,
                    isPlaylist: true,
                    id: res.id,
                    url: res.url,
                    curatorName: res.subtitle ?? "Apple Music",
                    description: res.subtitle ?? group.title
                )

                seenIds.insert(res.id)
                if isPrimaryMix {
                    mixes.append(info)
                } else if !isRecentlyPlayed {
                    secondaryPlaylists.append(info)
                }
            }
        }

        mixes.append(contentsOf: secondaryPlaylists)
        return mixes
    }

    public static func extractStations(from groups: [PersonalRecommendationGroup]) -> (personal: StationInfo?, discovery: StationInfo?) {
        var personal: StationInfo? = nil
        var discovery: StationInfo? = nil

        for group in groups {
            for res in group.contents where res.type == "stations" {
                let lower = res.name.lowercased()
                let isDiscovery = lower.contains("discovery") ||
                                  lower.contains("открыти") ||
                                  lower.contains("в моем вкусе") ||
                                  res.id.hasPrefix("ra.q-")

                let isPersonal = (lower.contains("station") || lower.contains("станция")) &&
                                 (lower.contains("my ") || lower.contains("моя") || res.id.hasPrefix("ra.u-")) &&
                                 !isDiscovery

                if isDiscovery && discovery == nil {
                    discovery = StationInfo(
                        id: res.id,
                        name: res.name.isEmpty ? "Станция открытий" : res.name,
                        subtitle: res.subtitle ?? "Новая музыка на основе ваших вкусов",
                        artwork: res.artworkUrl ?? "/assets/stations/CoverDiscovery.png",
                        url: res.url ?? "https://music.apple.com/station/item/\(res.id)",
                        isLive: false,
                        color: "linear-gradient(135deg, #7928ca, #ff0080)",
                        isPersonal: true,
                        provider: "Apple Music"
                    )
                } else if isPersonal && personal == nil {
                    personal = StationInfo(
                        id: res.id,
                        name: res.name.isEmpty ? "Моя станция" : res.name,
                        subtitle: res.subtitle ?? "Любимые треки и персональные рекомендации",
                        artwork: res.artworkUrl ?? defaultPersonalStationArtwork,
                        url: res.url ?? "https://music.apple.com/station/my-station/\(res.id)",
                        isLive: false,
                        color: "linear-gradient(135deg, #fa233b, #fb5c74)",
                        isPersonal: true,
                        provider: "Apple Music"
                    )
                }
            }
        }
        return (personal, discovery)
    }
}
