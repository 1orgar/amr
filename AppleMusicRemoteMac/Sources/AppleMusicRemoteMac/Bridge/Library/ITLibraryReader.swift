//
//  ITLibraryReader.swift
//  AppleMusicRemoteMac
//
//  Fast in-process Music.app library reader backed by Apple's native iTunesLibrary.framework.
//  Eliminates multi-second AppleEvent / OSA IPC stalls on large libraries while preserving
//  automatic fallback to AppleScript when unavailable or running under unit tests.
//

import AppKit
import Foundation
import iTunesLibrary

public struct ITLibraryItemSnapshot: Sendable {
    public let persistentIDHex: String
    public let syntheticTrackId: Int
    public let title: String
    public let artist: String
    public let album: String
    public let durationSeconds: Double
    public let isFileTrack: Bool
    public let hasEmbeddedArtwork: Bool
    public let addedTimestamp: Double?
    public let sampleRateHz: Int
    public let bitsPerSample: Int

    public init(
        persistentIDHex: String,
        syntheticTrackId: Int,
        title: String,
        artist: String,
        album: String,
        durationSeconds: Double,
        isFileTrack: Bool,
        hasEmbeddedArtwork: Bool,
        addedTimestamp: Double?,
        sampleRateHz: Int = 0,
        bitsPerSample: Int = 0
    ) {
        self.persistentIDHex = persistentIDHex
        self.syntheticTrackId = syntheticTrackId
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.isFileTrack = isFileTrack
        self.hasEmbeddedArtwork = hasEmbeddedArtwork
        self.addedTimestamp = addedTimestamp
        self.sampleRateHz = sampleRateHz
        self.bitsPerSample = bitsPerSample
    }
}

public final class ITLibraryReader: @unchecked Sendable {
    public static let shared = ITLibraryReader()

    /// Synthetic IDs live in `5_000_000 ..< 9_999_999` so they never collide with small session `database ID`s
    /// (`1 ..< 5_000_000`) while remaining `< 10_000_000` (local-track range in `ArtworkService` / `LibraryService`).
    public static let syntheticTrackIdBase: Int = 5_000_000
    public static let syntheticTrackIdMax: Int = 9_999_999

    private let lock = NSLock()
    private var itLibrary: ITLibrary?
    private var nextSyntheticOffset: Int = 0
    private var persistentHexToSyntheticId: [String: Int] = [:]
    private var syntheticIdToPersistentHex: [Int: String] = [:]
    private var itemsByPersistentHex: [String: ITLibMediaItem] = [:]
    private var itemsByNormalizedMetadataKey: [String: ITLibMediaItem] = [:]
    private var testArtworkBySyntheticId: [Int: Data] = [:]

    private init() {}

    public static func isSyntheticTrackId(_ id: Int) -> Bool {
        id >= syntheticTrackIdBase && id <= syntheticTrackIdMax
    }

    /// Selects the user's Music Library playlist (`Музыка` / `Медиатека`) rather than `library.allMediaItems`,
    /// because `allMediaItems` also contains playlist-only cloud songs when "Add Playlist Songs to Library" is OFF in Music.app.
    public static func selectMusicLibraryPlaylist<Playlist>(
        from playlists: [Playlist],
        isDistinguishedMusic: (Playlist) -> Bool,
        isPrimaryLibrary: (Playlist) -> Bool
    ) -> Playlist? {
        if let musicPlaylist = playlists.first(where: isDistinguishedMusic) {
            return musicPlaylist
        }
        return playlists.first(where: isPrimaryLibrary)
    }

    private static func metadataLookupKey(title: String, artist: String, album: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let a = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let al = album.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(t)|\(a)|\(al)"
    }

    internal func assignOrLookupSyntheticIdLocked(forPersistentHex hex: String) -> Int {
        if let existing = persistentHexToSyntheticId[hex] {
            return existing
        }
        let capacity = Self.syntheticTrackIdMax - Self.syntheticTrackIdBase
        let assigned = Self.syntheticTrackIdBase + (nextSyntheticOffset % capacity)
        nextSyntheticOffset += 1
        if let evictedHex = syntheticIdToPersistentHex[assigned] {
            persistentHexToSyntheticId.removeValue(forKey: evictedHex)
        }
        persistentHexToSyntheticId[hex] = assigned
        syntheticIdToPersistentHex[assigned] = hex
        return assigned
    }

    public func persistentIDHex(forTrackId trackId: Int) -> String? {
        guard Self.isSyntheticTrackId(trackId) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return syntheticIdToPersistentHex[trackId]
    }

    /// Returns:
    /// - `true` if `trackId` is an `ITLibrary` synthetic ID backed by a real downloaded file on disk (`locationType == .file && location != nil`),
    /// - `false` if `trackId` is an `ITLibrary` synthetic ID for an un-downloaded cloud library item (`shared track`),
    /// - `nil` if `trackId` is outside the synthetic `ITLibrary` range or not cached.
    public func downloadedFileTrackStatus(forTrackId trackId: Int) -> Bool? {
        guard Self.isSyntheticTrackId(trackId) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let hex = syntheticIdToPersistentHex[trackId],
              let item = itemsByPersistentHex[hex] else {
            return nil
        }
        return item.locationType == .file && item.location != nil
    }

    public func invalidate() {
        lock.lock()
        itemsByPersistentHex.removeAll(keepingCapacity: true)
        itemsByNormalizedMetadataKey.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    /// Proactively initializes `ITLibrary` at first launch so macOS prompts for Media Library access
    /// immediately during initial setup rather than blocking headless background queries later.
    @discardableResult
    public func warmupPermissionAtLaunch() -> Bool {
        if PlaybackRouter.shared.isTestingEnvironment || AppStorageProvider.isRunningUnderXCTest {
            return false
        }
        lock.lock()
        defer { lock.unlock() }
        if let existing = self.itLibrary {
            _ = existing.allPlaylists.count
            return true
        }
        do {
            let created = try ITLibrary(apiVersion: "1.1")
            _ = created.allPlaylists.count
            self.itLibrary = created
            return true
        } catch {
            NSLog("[ITLibraryReader] ℹ️ Media library warmup deferred (%@)", error.localizedDescription)
            return false
        }
    }

    /// Reads all song items directly via `iTunesLibrary.framework` without AppleEvents IPC.
    /// Returns `nil` when running in XCTest or if `ITLibrary` cannot open the user's Music library,
    /// allowing `LibraryService` to fall back cleanly to AppleScript.
    public func readLibrarySongSnapshots(forceReload: Bool = false) -> [ITLibraryItemSnapshot]? {
        if PlaybackRouter.shared.isTestingEnvironment {
            return nil
        }

        lock.lock()
        defer { lock.unlock() }

        let library: ITLibrary
        if let existing = self.itLibrary {
            if forceReload {
                _ = existing.reloadData()
            }
            library = existing
        } else {
            do {
                let created = try ITLibrary(apiVersion: "1.1")
                self.itLibrary = created
                library = created
            } catch {
                NSLog("[ITLibraryReader] ℹ️ ITLibrary unavailable (%@); falling back to AppleScript", error.localizedDescription)
                return nil
            }
        }

        let allItems = library.allMediaItems
        itemsByPersistentHex.removeAll(keepingCapacity: true)
        itemsByNormalizedMetadataKey.removeAll(keepingCapacity: true)

        for item in allItems where item.mediaKind == .kindSong {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let artist = (item.artist?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let album = (item.album.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let persistentHex = String(format: "%016llX", item.persistentID.uint64Value)
            _ = assignOrLookupSyntheticIdLocked(forPersistentHex: persistentHex)
            itemsByPersistentHex[persistentHex] = item
            let metaKey = Self.metadataLookupKey(title: title, artist: artist, album: album)
            if itemsByNormalizedMetadataKey[metaKey] == nil {
                itemsByNormalizedMetadataKey[metaKey] = item
            }
        }

        guard let musicPlaylist = Self.selectMusicLibraryPlaylist(
            from: library.allPlaylists,
            isDistinguishedMusic: { $0.distinguishedKind == .kindMusic },
            isPrimaryLibrary: { $0.isPrimary }
        ) else {
            return nil
        }

        let libraryItems = musicPlaylist.items
        if libraryItems.isEmpty && MusicAppProvider.shared.isMusicAppRunning {
            // Music.app may hold unsaved in-memory/cloud items before first persistence; let AppleScript verify `library playlist 1`.
            return nil
        }

        var snapshots: [ITLibraryItemSnapshot] = []
        snapshots.reserveCapacity(libraryItems.count)

        for item in libraryItems where item.mediaKind == .kindSong {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            let artist = (item.artist?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let album = (item.album.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let durationSec = Double(item.totalTime) / 1000.0
            let persistentHex = String(format: "%016llX", item.persistentID.uint64Value)
            let syntheticId = assignOrLookupSyntheticIdLocked(forPersistentHex: persistentHex)
            let isFile = (item.locationType == .file && item.location != nil)

            let kindLower = (item.kind ?? "").lowercased()
            let isLosslessFile = isFile && (
                kindLower.contains("lossless")
                || kindLower.contains("alac")
                || kindLower.contains("flac")
                || kindLower.contains("wav")
                || kindLower.contains("aiff")
            )
            let inferredBits: Int
            if isLosslessFile {
                inferredBits = (item.sampleRate >= 48_000 || item.bitrate > 1_450) ? 24 : 16
            } else {
                inferredBits = 0
            }

            snapshots.append(
                ITLibraryItemSnapshot(
                    persistentIDHex: persistentHex,
                    syntheticTrackId: syntheticId,
                    title: title,
                    artist: artist,
                    album: album,
                    durationSeconds: durationSec,
                    isFileTrack: isFile,
                    hasEmbeddedArtwork: item.hasArtworkAvailable,
                    addedTimestamp: item.addedDate?.timeIntervalSince1970,
                    sampleRateHz: item.sampleRate,
                    bitsPerSample: inferredBits
                )
            )
        }

        return snapshots
    }

    /// Extracts embedded track artwork in-process via `ITLibArtwork` without AppleEvents IPC.
    public func embeddedArtworkData(
        forTrackId trackId: Int,
        title: String = "",
        artist: String = "",
        album: String = ""
    ) -> Data? {
        if let testData = lock.withLock({ testArtworkBySyntheticId[trackId] }) {
            return testData
        }

        let matchedItem: ITLibMediaItem? = lock.withLock {
            if let hex = syntheticIdToPersistentHex[trackId],
               let item = itemsByPersistentHex[hex] {
                return item
            }
            if !title.isEmpty {
                let key = Self.metadataLookupKey(title: title, artist: artist, album: album)
                if let item = itemsByNormalizedMetadataKey[key] {
                    return item
                }
            }
            return nil
        }

        guard let item = matchedItem,
              item.hasArtworkAvailable,
              let rawData = item.artwork?.imageData,
              !rawData.isEmpty else {
            return nil
        }
        return rawData
    }

    // MARK: - Testing Hooks

    internal func registerSyntheticMappingForTesting(persistentIDHex: String, artworkData: Data? = nil) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let cleanHex = persistentIDHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let sid = assignOrLookupSyntheticIdLocked(forPersistentHex: cleanHex)
        if let artworkData {
            testArtworkBySyntheticId[sid] = artworkData
        } else {
            testArtworkBySyntheticId.removeValue(forKey: sid)
        }
        return sid
    }
}
