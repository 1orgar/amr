//
//  ArtworkService.swift
//  AppleMusicRemoteMac
//
//  High-performance artwork extraction, JPEG downscaling, memory caching (NSCache),
//  and Base64 Data URI formatting for tracks and playlists.
//

import AppKit
import Foundation
import ImageIO
import ScriptingBridge

public final class ArtworkService: @unchecked Sendable {
    public static let shared = ArtworkService()

    private let lock = NSLock()
    private let artworkCache = NSCache<NSString, NSData>()
    private var playlistArtworkUrlCache: [String: String] = [:]
    private var negativeArtworkIds = Set<Int>()
    private var fetchingArtworkIds = Set<Int>()

    private var cachedCurArtworkKey: String = ""
    private var cachedCurArtworkUri: String = ""

    private init() {
        artworkCache.countLimit = 200
    }

    // MARK: - Current Track Artwork

    public func getCurrentTrackArtworkDataUri() -> String {
        lock.lock()
        defer { lock.unlock() }

        guard let app = MusicAppProvider.shared.getMusicApp(), let curTrack = app.currentTrack else { return "" }
        let name = (curTrack.value(forKey: "name") as? String) ?? ""
        let artist = (curTrack.value(forKey: "artist") as? String) ?? ""
        let dbId = (curTrack.value(forKey: "databaseID") as? Int) ?? 0
        let key = "\(name)___\(artist)___\(dbId)"

        if !key.isEmpty && key == cachedCurArtworkKey && !cachedCurArtworkUri.isEmpty {
            return cachedCurArtworkUri
        }

        if let data = getCurrentTrackArtworkUnlocked() {
            let uri = "data:image/jpeg;base64,\(data.base64EncodedString())"
            cachedCurArtworkKey = key
            cachedCurArtworkUri = uri
            return uri
        }
        return ""
    }

    public func getCurrentTrackArtwork() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return getCurrentTrackArtworkUnlocked()
    }

    private func getCurrentTrackArtworkUnlocked() -> Data? {
        guard let app = MusicAppProvider.shared.getMusicApp(), let curTrack = app.currentTrack else { return nil }
        // Cloud / streaming track:
        // On macOS Music.app, if a track is not a local file (location == nil),
        // curTrack.sbArtworks retains the ghost artwork from previous tracks.
        guard curTrack.value(forKey: "location") != nil else { return nil }

        if let artworks = curTrack.sbArtworks, let firstArt = artworks.firstObject as? SBObject {
            if let desc = firstArt.value(forKey: "data") as? NSAppleEventDescriptor {
                let d = desc.data
                if let img = NSImage(data: d), let jpeg = jpegData(from: img, maxDimension: 400) {
                    return jpeg
                }
                return d
            }
            if let img = firstArt.value(forKey: "data") as? NSImage {
                return jpegData(from: img, maxDimension: 400)
            }
            if let raw = firstArt.value(forKey: "rawData") as? Data {
                return raw
            }
            if let desc = firstArt.value(forKey: "rawData") as? NSAppleEventDescriptor {
                let d = desc.data
                if let img = NSImage(data: d), let jpeg = jpegData(from: img, maxDimension: 400) {
                    return jpeg
                }
                return d
            }
        }
        return nil
    }

    public func clearTrackArtworkCache(id: Int? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let id = id {
            artworkCache.removeObject(forKey: "track_\(id)" as NSString)
            ArtworkDiskCache.shared.remove(key: "track_\(id)")
            negativeArtworkIds.remove(id)
        } else {
            artworkCache.removeAllObjects()
            ArtworkDiskCache.shared.clear()
            negativeArtworkIds.removeAll()
            cachedCurArtworkKey = ""
            cachedCurArtworkUri = ""
        }
    }

    public func getCachedTrackArtwork(id: Int) -> Data? {
        guard id > 0 else { return nil }
        let cacheKey = "track_\(id)" as NSString
        return artworkCache.object(forKey: cacheKey) as Data?
    }

    // MARK: - Track Artwork by Database ID

    public func getTrackArtwork(id: Int) -> Data? {
        guard id > 0 else { return nil }

        let cacheKey = "track_\(id)" as NSString
        if let cached = artworkCache.object(forKey: cacheKey) as Data? {
            return cached
        }

        // Fast path 0: Check persistent disk LRU cache
        if let diskData = ArtworkDiskCache.shared.get(key: "track_\(id)") {
            artworkCache.setObject(diskData as NSData, forKey: cacheKey)
            return diskData
        }

        // Fast path 1: Check if requested id matches currently playing track (must be local file track)
        if let app = MusicAppProvider.shared.getMusicApp(), let curTrack = app.currentTrack {
            if let curId = curTrack.value(forKey: "databaseID") as? Int, curId == id {
                if curTrack.value(forKey: "location") != nil, let d = getCurrentTrackArtwork() {
                    lock.lock()
                    negativeArtworkIds.remove(id)
                    lock.unlock()
                    artworkCache.setObject(d as NSData, forKey: cacheKey)
                    ArtworkDiskCache.shared.set(key: "track_\(id)", data: d)
                    return d
                }
            }
        }

        lock.lock()
        if negativeArtworkIds.contains(id) {
            lock.unlock()
            return nil
        }
        lock.unlock()

        // Fast path 2: Retrieve embedded track artwork from Music.app via indexed database ID lookup
        let script = """
        tell application "Music"
            try
                with timeout of 1.5 seconds
                    set t to (first track of library playlist 1 whose database ID is \(id))
                    if (count of artworks of t) > 0 then
                        return raw data of artwork 1 of t
                    end if
                end timeout
            end try
            return missing value
        end tell
        """
        if let desc = AppleScriptExecutor.shared.executeDescriptor(script), !desc.data.isEmpty {
            let d = desc.data
            if let img = NSImage(data: d), let jpeg = jpegData(from: img, maxDimension: 600) {
                artworkCache.setObject(jpeg as NSData, forKey: cacheKey)
                ArtworkDiskCache.shared.set(key: "track_\(id)", data: jpeg)
                return jpeg
            }
            artworkCache.setObject(d as NSData, forKey: cacheKey)
            ArtworkDiskCache.shared.set(key: "track_\(id)", data: d)
            return d
        }

        lock.lock()
        negativeArtworkIds.insert(id)
        lock.unlock()
        return nil
    }

    public func getTrackArtworkDataUri(id: Int) -> String {
        if let data = getTrackArtwork(id: id) {
            return "data:image/jpeg;base64,\(data.base64EncodedString())"
        }
        return ""
    }

    public func findLocalTrackArtwork(name: String, artist: String) -> String? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanName.isEmpty else { return nil }

        let cachedSongs = LibraryService.shared.getCachedLibrarySongs()
        if let match = cachedSongs.first(where: {
            let n = $0.name.lowercased()
            let a = $0.artist.lowercased()
            if !cleanArtist.isEmpty {
                return n == cleanName && a == cleanArtist
            }
            return n == cleanName
        }), let nid = match.numericId {
            let uri = getTrackArtworkDataUri(id: nid)
            if !uri.isEmpty {
                return uri
            }
        }
        return nil
    }

    // MARK: - Playlist Artwork

    public func getPlaylistArtwork(name: String) -> Data? {
        guard !name.isEmpty else { return nil }
        let cacheKey = "playlist_\(name)" as NSString
        if let cached = artworkCache.object(forKey: cacheKey) as Data? {
            return cached
        }

        // Fast path 0: Check persistent disk LRU cache
        if let diskData = ArtworkDiskCache.shared.get(key: "playlist_\(name)") {
            artworkCache.setObject(diskData as NSData, forKey: cacheKey)
            return diskData
        }

        let escapedPlName = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Music"
            with timeout of 3 seconds
                try
                    set p to (first user playlist whose name is "\(escapedPlName)")
                    if (count of artworks of p) > 0 then
                        return raw data of artwork 1 of p
                    end if
                    repeat with i from 1 to (count of tracks of p)
                        if i > 15 then exit repeat
                        set t to track i of p
                        if (count of artworks of t) > 0 then
                            return raw data of artwork 1 of t
                        end if
                    end repeat
                end try
                try
                    set p to (first playlist whose name is "\(escapedPlName)")
                    if (count of artworks of p) > 0 then
                        return raw data of artwork 1 of p
                    end if
                    repeat with i from 1 to (count of tracks of p)
                        if i > 15 then exit repeat
                        set t to track i of p
                        if (count of artworks of t) > 0 then
                            return raw data of artwork 1 of t
                        end if
                    end repeat
                end try
                return missing value
            end timeout
        end tell
        """

        guard let desc = AppleScriptExecutor.shared.executeDescriptor(script), desc.descriptorType != typeNull else {
            return nil
        }
        let d = desc.data
        if !d.isEmpty, let img = NSImage(data: d) {
            if let jpeg = jpegData(from: img, maxDimension: 300) {
                artworkCache.setObject(jpeg as NSData, forKey: cacheKey)
                ArtworkDiskCache.shared.set(key: "playlist_\(name)", data: jpeg)
                return jpeg
            }
            artworkCache.setObject(d as NSData, forKey: cacheKey)
            ArtworkDiskCache.shared.set(key: "playlist_\(name)", data: d)
            return d
        }
        return nil
    }

    public func getPlaylistArtworkDataUri(name: String) -> String {
        if let data = getPlaylistArtwork(name: name) {
            return "data:image/jpeg;base64,\(data.base64EncodedString())"
        }
        return ""
    }

    public func getPlaylistArtworkThumbnailUri(name: String) -> String {
        lock.lock()
        if let cached = playlistArtworkUrlCache[name], !cached.isEmpty {
            lock.unlock()
            return cached
        }
        lock.unlock()

        if let data = getPlaylistArtwork(name: name), !data.isEmpty {
            let uri = "data:image/jpeg;base64,\(data.base64EncodedString())"
            lock.lock()
            playlistArtworkUrlCache[name] = uri
            lock.unlock()
            return uri
        }
        return ""
    }

    public func setPlaylistArtworkUrl(name: String, url: String) {
        lock.lock()
        playlistArtworkUrlCache[name] = url
        lock.unlock()
    }

    public func getCachedPlaylistArtworkUrl(name: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return playlistArtworkUrlCache[name]
    }

    // MARK: - Batch Enrichment

    public func enrichTracksArtwork(_ tracks: [TrackInfo], limit: Int = 75) async -> [TrackInfo] {
        var enriched = tracks
        let missingIndices = (0..<min(limit, enriched.count)).filter { !enriched[$0].hasArtwork || enriched[$0].artworkUrl.isEmpty }
        guard !missingIndices.isEmpty else { return enriched }

        await withTaskGroup(of: (Int, String?).self) { group in
            for i in missingIndices {
                let t = enriched[i]
                group.addTask {
                    // 1. In-memory cache by numericId
                    if let nid = t.numericId, nid > 0 {
                        let cacheKey = "track_\(nid)" as NSString
                        if let cached = self.artworkCache.object(forKey: cacheKey) as Data? {
                            return (i, "data:image/jpeg;base64,\(cached.base64EncodedString())")
                        }
                    }
                    // 2. Local artwork file cache
                    if let local = self.findLocalTrackArtwork(name: t.name, artist: t.artist) {
                        return (i, local)
                    }
                    // 3. Cached MusicKit artwork
                    if let cachedCloud = MusicKitManager.shared.getCachedTrackArtwork(name: t.name, artist: t.artist, album: t.album), !cachedCloud.isEmpty {
                        return (i, cachedCloud)
                    }
                    // 4. Apple Music Catalog search via MusicKit HTTP
                    if let cloudArt = await MusicKitManager.shared.searchTrackArtwork(name: t.name, artist: t.artist, album: t.album), !cloudArt.isEmpty {
                        return (i, cloudArt)
                    }
                    return (i, nil)
                }
            }

            for await (idx, art) in group {
                if let art = art, !art.isEmpty {
                    enriched[idx].artworkUrl = art
                    enriched[idx].hasArtwork = true
                }
            }
        }

        return enriched
    }

    public func queueNativeArtworkFetch(ids: [Int]) {
        var toFetch = [Int]()
        lock.withLock {
            for nid in ids where nid > 0 {
                let cacheKey = "track_\(nid)" as NSString
                if self.artworkCache.object(forKey: cacheKey) == nil && !self.fetchingArtworkIds.contains(nid) {
                    self.fetchingArtworkIds.insert(nid)
                    toFetch.append(nid)
                }
            }
        }

        let fetchIds = toFetch
        if !fetchIds.isEmpty {
            Task.detached(priority: .utility) {
                for nid in fetchIds {
                    _ = self.getTrackArtwork(id: nid)
                    _ = self.lock.withLock {
                        self.fetchingArtworkIds.remove(nid)
                    }
                }
            }
        }
    }

    // MARK: - Image Compression Helpers

    public func jpegData(from rawData: Data, maxDimension: CGFloat = 400) -> Data? {
        guard let source = CGImageSourceCreateWithData(rawData as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: thumbnail)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }

    public func jpegData(from image: NSImage, maxDimension: CGFloat = 400) -> Data? {
        if let tiff = image.tiffRepresentation {
            return jpegData(from: tiff, maxDimension: maxDimension)
        }
        return nil
    }
}
