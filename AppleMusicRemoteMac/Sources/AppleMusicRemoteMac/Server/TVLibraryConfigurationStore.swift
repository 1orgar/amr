//
//  TVLibraryConfigurationStore.swift
//  AppleMusicRemoteMac
//
//  Thread-safe persistent configuration store for TV Web Client Library sections,
//  curated mixes/stations visibility, and user-selected playlists/albums.
//

import Foundation

public struct TVLibraryAlbumSelection: Codable, Sendable, Equatable {
    public var key: String
    public var id: String
    public var name: String
    public var artist: String

    enum CodingKeys: String, CodingKey {
        case key
        case id
        case name
        case artist
    }

    public init(key: String, id: String = "", name: String, artist: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.key = cleanKey.isEmpty
            ? TVLibraryConfigurationStore.makeAlbumSelectionKey(name: cleanName, artist: cleanArtist)
            : cleanKey
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = cleanName
        self.artist = cleanArtist
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawName = (try container.decodeIfPresent(String.self, forKey: .name) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawArtist = (try container.decodeIfPresent(String.self, forKey: .artist) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawId = (try container.decodeIfPresent(String.self, forKey: .id) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawKey = (try container.decodeIfPresent(String.self, forKey: .key) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = rawName
        self.artist = rawArtist
        self.id = rawId
        self.key = rawKey.isEmpty
            ? TVLibraryConfigurationStore.makeAlbumSelectionKey(name: rawName, artist: rawArtist)
            : rawKey
    }
}

public struct TVLibraryConfiguration: Codable, Sendable, Equatable {
    public var showMyStation: Bool
    public var showDiscoveryStation: Bool
    public var showFavoritesMix: Bool
    public var showHeavyRotation: Bool
    public var playlistsMode: String // "all" | "selected" | "none"
    public var selectedPlaylistNames: [String]
    public var albumsMode: String // "recent" | "selected" | "none"
    public var selectedAlbums: [TVLibraryAlbumSelection]

    enum CodingKeys: String, CodingKey {
        case showMyStation = "show_my_station"
        case showDiscoveryStation = "show_discovery_station"
        case showFavoritesMix = "show_favorites_mix"
        case showHeavyRotation = "show_heavy_rotation"
        case playlistsMode = "playlists_mode"
        case selectedPlaylistNames = "selected_playlist_names"
        case albumsMode = "albums_mode"
        case selectedAlbums = "selected_albums"
    }

    public init(
        showMyStation: Bool = true,
        showDiscoveryStation: Bool = true,
        showFavoritesMix: Bool = true,
        showHeavyRotation: Bool = true,
        playlistsMode: String = "all",
        selectedPlaylistNames: [String] = [],
        albumsMode: String = "recent",
        selectedAlbums: [TVLibraryAlbumSelection] = []
    ) {
        self.showMyStation = showMyStation
        self.showDiscoveryStation = showDiscoveryStation
        self.showFavoritesMix = showFavoritesMix
        self.showHeavyRotation = showHeavyRotation
        self.playlistsMode = playlistsMode
        self.selectedPlaylistNames = selectedPlaylistNames
        self.albumsMode = albumsMode
        self.selectedAlbums = selectedAlbums
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.showMyStation = try container.decodeIfPresent(Bool.self, forKey: .showMyStation) ?? true
        self.showDiscoveryStation = try container.decodeIfPresent(Bool.self, forKey: .showDiscoveryStation) ?? true
        self.showFavoritesMix = try container.decodeIfPresent(Bool.self, forKey: .showFavoritesMix) ?? true
        self.showHeavyRotation = try container.decodeIfPresent(Bool.self, forKey: .showHeavyRotation) ?? true
        self.playlistsMode = try container.decodeIfPresent(String.self, forKey: .playlistsMode) ?? "all"
        self.selectedPlaylistNames = try container.decodeIfPresent([String].self, forKey: .selectedPlaylistNames) ?? []
        self.albumsMode = try container.decodeIfPresent(String.self, forKey: .albumsMode) ?? "recent"
        self.selectedAlbums = try container.decodeIfPresent([TVLibraryAlbumSelection].self, forKey: .selectedAlbums) ?? []
    }
}

public final class TVLibraryConfigurationStore: @unchecked Sendable {
    public static let shared = TVLibraryConfigurationStore()

    private static let validPlaylistsModes: Set<String> = ["all", "selected", "none"]
    private static let validAlbumsModes: Set<String> = ["recent", "selected", "none"]

    private static var isRunningUnderXCTest: Bool {
        NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private let lock = NSLock()
    private let userDefaults: UserDefaults
    private let storageKey: String
    private var state: TVLibraryConfiguration

    public init(userDefaults: UserDefaults = AppStorageProvider.shared, storageKey: String = "AMRTVLibraryConfigurationV1") {
        self.userDefaults = userDefaults
        self.storageKey = storageKey

        let skipStandardPersistence = Self.isRunningUnderXCTest && userDefaults === UserDefaults.standard
        if !skipStandardPersistence,
           let data = userDefaults.data(forKey: storageKey),
           var decoded = try? JSONDecoder().decode(TVLibraryConfiguration.self, from: data) {
            Self.sanitize(&decoded)
            self.state = decoded
        } else {
            self.state = TVLibraryConfiguration()
        }
    }

    public var current: TVLibraryConfiguration {
        get {
            lock.lock()
            defer { lock.unlock() }
            return state
        }
        set {
            update { $0 = newValue }
        }
    }

    public static func makeAlbumSelectionKey(name: String, artist: String) -> String {
        MusicKitManager.normalizedAlbumKey(name: name, artist: artist)
    }

    private static func sanitize(_ config: inout TVLibraryConfiguration) {
        let pMode = config.playlistsMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        config.playlistsMode = validPlaylistsModes.contains(pMode) ? pMode : "all"

        let aMode = config.albumsMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        config.albumsMode = validAlbumsModes.contains(aMode) ? aMode : "recent"

        var seenPlaylists = Set<String>()
        var dedupedPlaylists: [String] = []
        dedupedPlaylists.reserveCapacity(config.selectedPlaylistNames.count)
        for rawName in config.selectedPlaylistNames {
            let clean = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            let norm = clean.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            if seenPlaylists.insert(norm).inserted {
                dedupedPlaylists.append(clean)
            }
        }
        config.selectedPlaylistNames = dedupedPlaylists

        var seenAlbumKeys = Set<String>()
        var dedupedAlbums: [TVLibraryAlbumSelection] = []
        dedupedAlbums.reserveCapacity(config.selectedAlbums.count)
        for item in config.selectedAlbums {
            let cleanName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty else { continue }
            let cleanArtist = item.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanId = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let canonicalKey = makeAlbumSelectionKey(name: cleanName, artist: cleanArtist)
            let effectiveKey = canonicalKey.isEmpty
                ? item.key.trimmingCharacters(in: .whitespacesAndNewlines)
                : canonicalKey
            guard !effectiveKey.isEmpty else { continue }
            if seenAlbumKeys.insert(effectiveKey).inserted {
                dedupedAlbums.append(TVLibraryAlbumSelection(
                    key: effectiveKey,
                    id: cleanId,
                    name: cleanName,
                    artist: cleanArtist
                ))
            }
        }
        config.selectedAlbums = dedupedAlbums
    }

    @discardableResult
    public func update(_ mutate: (inout TVLibraryConfiguration) -> Void) -> TVLibraryConfiguration {
        let (snapshot, encodedData): (TVLibraryConfiguration, Data?) = {
            lock.lock()
            defer { lock.unlock() }
            var next = state
            mutate(&next)
            Self.sanitize(&next)
            state = next
            let data = try? JSONEncoder().encode(next)
            return (next, data)
        }()

        let skipStandardPersistence = (PlaybackRouter.shared.isTestingEnvironment || Self.isRunningUnderXCTest)
            && userDefaults === UserDefaults.standard
        if !skipStandardPersistence, let data = encodedData {
            userDefaults.set(data, forKey: storageKey)
        }
        return snapshot
    }

    @discardableResult
    public func applyDictionary(_ dict: [String: Any]) -> TVLibraryConfiguration {
        func parseBool(_ keys: [String]) -> Bool? {
            for k in keys {
                guard let val = dict[k] else { continue }
                if let b = val as? Bool { return b }
                if let n = val as? NSNumber { return n.boolValue }
                if let s = val as? String {
                    let lower = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if lower == "true" || lower == "1" { return true }
                    if lower == "false" || lower == "0" { return false }
                }
            }
            return nil
        }

        func parseString(_ keys: [String]) -> String? {
            for k in keys {
                if let s = dict[k] as? String {
                    return s
                }
            }
            return nil
        }

        return update { cfg in
            if let v = parseBool(["show_my_station", "showMyStation"]) {
                cfg.showMyStation = v
            }
            if let v = parseBool(["show_discovery_station", "showDiscoveryStation"]) {
                cfg.showDiscoveryStation = v
            }
            if let v = parseBool(["show_favorites_mix", "showFavoritesMix"]) {
                cfg.showFavoritesMix = v
            }
            if let v = parseBool(["show_heavy_rotation", "showHeavyRotation"]) {
                cfg.showHeavyRotation = v
            }
            if let pMode = parseString(["playlists_mode", "playlistsMode"]) {
                cfg.playlistsMode = pMode
            }
            if let rawNames = (dict["selected_playlist_names"] ?? dict["selectedPlaylistNames"]) as? [Any] {
                cfg.selectedPlaylistNames = rawNames.compactMap { item -> String? in
                    if let s = item as? String { return s }
                    return nil
                }
            }
            if let aMode = parseString(["albums_mode", "albumsMode"]) {
                cfg.albumsMode = aMode
            }
            if let rawAlbums = (dict["selected_albums"] ?? dict["selectedAlbums"]) as? [Any] {
                var parsed: [TVLibraryAlbumSelection] = []
                parsed.reserveCapacity(rawAlbums.count)
                for elem in rawAlbums {
                    guard let obj = elem as? [String: Any] else { continue }
                    let name = (obj["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { continue }
                    let artist = (obj["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let id = String(describing: obj["id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanId = (obj["id"] == nil || obj["id"] is NSNull) ? "" : id
                    let rawKey = (obj["key"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let key = rawKey.isEmpty ? Self.makeAlbumSelectionKey(name: name, artist: artist) : rawKey
                    parsed.append(TVLibraryAlbumSelection(key: key, id: cleanId, name: name, artist: artist))
                }
                cfg.selectedAlbums = parsed
            }
        }
    }

    public func toDictionary() -> [String: Any] {
        let cfg = current
        let serializedAlbums: [[String: String]] = cfg.selectedAlbums.map { sel in
            [
                "key": sel.key,
                "id": sel.id,
                "name": sel.name,
                "artist": sel.artist
            ]
        }
        let selectedKeys = cfg.selectedAlbums.map(\.key)
        return [
            "show_my_station": cfg.showMyStation,
            "show_discovery_station": cfg.showDiscoveryStation,
            "show_favorites_mix": cfg.showFavoritesMix,
            "show_heavy_rotation": cfg.showHeavyRotation,
            "playlists_mode": cfg.playlistsMode,
            "selected_playlist_names": cfg.selectedPlaylistNames,
            "albums_mode": cfg.albumsMode,
            "selected_albums": serializedAlbums,
            "selected_album_keys": selectedKeys
        ]
    }
}
