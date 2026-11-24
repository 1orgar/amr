//
//  ArtworkService.swift
//  AppleMusicRemoteMac
//
//  High-performance artwork extraction, JPEG downscaling, memory caching (NSCache),
//  SSRF-safe Apple CDN fetching, and Base64 Data URI formatting for tracks and playlists.
//

import AppKit
import Foundation
import ImageIO
import ScriptingBridge

// MARK: - SSRF-Safe Apple CDN Artwork Session

final class SafeArtworkFetcher: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private final class TaskState {
        let maxBytes: Int
        var buffer = Data()
        var statusCode: Int = 0
        var exceededLimit = false
        var continuation: CheckedContinuation<Data?, Never>?

        init(maxBytes: Int, continuation: CheckedContinuation<Data?, Never>) {
            self.maxBytes = maxBytes
            self.continuation = continuation
        }
    }

    private let stateLock = NSLock()
    private var tasks: [Int: TaskState] = [:]
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 6.0
        cfg.timeoutIntervalForResource = 15.0
        cfg.httpShouldSetCookies = false
        cfg.httpCookieAcceptPolicy = .never
        cfg.urlCredentialStorage = nil
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    func fetch(
        url: URL,
        timeout: TimeInterval = 4.0,
        maxBytes: Int = 10 * 1024 * 1024,
        userAgent: String? = nil
    ) async -> Data? {
        guard ArtworkService.isAllowedRemoteArtworkURL(url) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        if let ua = userAgent {
            req.setValue(ua, forHTTPHeaderField: "User-Agent")
        }

        return await withCheckedContinuation { continuation in
            let task = session.dataTask(with: req)
            let state = TaskState(maxBytes: maxBytes, continuation: continuation)
            stateLock.lock()
            tasks[task.taskIdentifier] = state
            stateLock.unlock()
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let nextURL = request.url, ArtworkService.isAllowedRemoteArtworkURL(nextURL) {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let finalURL = http.url,
              ArtworkService.isAllowedRemoteArtworkURL(finalURL) else {
            completionHandler(.cancel)
            return
        }

        let maxBytes: Int = stateLock.withLock {
            tasks[dataTask.taskIdentifier]?.statusCode = http.statusCode
            return tasks[dataTask.taskIdentifier]?.maxBytes ?? (10 * 1024 * 1024)
        }
        if http.expectedContentLength > Int64(maxBytes) {
            stateLock.withLock { tasks[dataTask.taskIdentifier]?.exceededLimit = true }
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        var shouldCancel = false
        stateLock.lock()
        if let state = tasks[dataTask.taskIdentifier] {
            if state.buffer.count + data.count > state.maxBytes {
                state.exceededLimit = true
                state.buffer.removeAll(keepingCapacity: false)
                shouldCancel = true
            } else {
                state.buffer.append(data)
            }
        }
        stateLock.unlock()
        if shouldCancel {
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        stateLock.lock()
        let state = tasks.removeValue(forKey: task.taskIdentifier)
        let cont = state?.continuation
        state?.continuation = nil
        let validData: Data? = {
            guard let state,
                  error == nil,
                  !state.exceededLimit,
                  (200...299).contains(state.statusCode),
                  !state.buffer.isEmpty else {
                return nil
            }
            return state.buffer
        }()
        stateLock.unlock()
        cont?.resume(returning: validData)
    }
}

// MARK: - ArtworkService

public final class ArtworkService: @unchecked Sendable {
    public static let shared = ArtworkService()

    final class PaletteResultBox: @unchecked Sendable {
        let value: [String: Any]?
        init(_ value: [String: Any]?) { self.value = value }
    }

    let lock = NSLock()
    let visionLock = NSLock()
    let visionQueue = DispatchQueue(label: "com.amr.artwork.vision", qos: .utility)
    let artworkFetchQueue = DispatchQueue(label: "com.amr.artwork.local", qos: .utility)
    let artworkCache = NSCache<NSString, NSData>()
    let safeArtworkFetcher = SafeArtworkFetcher()

    var playlistArtworkUrlCache: [String: String] = [:]
    var paletteCache: [String: (palette: [String: Any], accessedAt: TimeInterval)] = [:]
    let maxPaletteCacheEntries = 160
    var inFlightPaletteTasks: [String: Task<PaletteResultBox, Never>] = [:]
    var negativeArtworkIds = Set<Int>()
    var negativeLocalAlbums: [String: Date] = [:]
    var fetchingArtworkIds = Set<Int>()
    var negativePlaylistArtworks: [String: Date] = [:]

    var cachedCurArtworkKey: String = ""
    var cachedCurArtworkUri: String = ""

    private init() {
        artworkCache.countLimit = 400
    }

    /// Strict SSRF guard: only permits Apple Music / iTunes / mzstatic CDN hosts (`https`, or `http` strictly on `.mzstatic.com`).
    public static func isAllowedRemoteArtworkURL(_ url: URL) -> Bool {
        guard url.user == nil, url.password == nil else { return false }
        let scheme = (url.scheme ?? "").lowercased()
        guard scheme == "https" || scheme == "http" else { return false }
        if let port = url.port {
            let validPort = (scheme == "https" && port == 443) || (scheme == "http" && port == 80)
            guard validPort else { return false }
        }
        guard let rawHost = url.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !rawHost.isEmpty else {
            return false
        }
        let host = rawHost.hasSuffix(".") ? String(rawHost.dropLast()) : rawHost
        guard !host.isEmpty,
              !host.contains(".."),
              host != "localhost",
              !host.hasSuffix(".local"),
              !host.hasPrefix("[") else {
            return false
        }
        // Reject raw IPv4 / IPv6 literals
        if host.allSatisfy({ $0.isNumber || $0 == "." || $0 == ":" }) {
            return false
        }

        let isMzstatic = (host == "mzstatic.com" || host.hasSuffix(".mzstatic.com"))
        let isApple = (host == "apple.com" || host.hasSuffix(".apple.com"))
        guard isMzstatic || isApple else { return false }

        if scheme == "http" {
            return isMzstatic
        }
        return true
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
            negativeLocalAlbums.removeAll()
            cachedCurArtworkKey = ""
            cachedCurArtworkUri = ""
        }
    }

    public func getCachedTrackArtwork(id: Int) -> Data? {
        guard id > 0 else { return nil }
        let cacheKey = "track_\(id)" as NSString
        return artworkCache.object(forKey: cacheKey) as Data?
    }

    static func localAlbumCacheKey(album: String, artist: String) -> String? {
        let normAlbum = MusicKitManager.normalizedAlbumTitle(album)
        guard !normAlbum.isEmpty else { return nil }
        var baseArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if let ampIdx = baseArtist.range(of: " & ") {
            baseArtist = String(baseArtist[..<ampIdx.lowerBound]).trimmingCharacters(in: .whitespaces)
        } else if let featIdx = baseArtist.range(of: " feat", options: .caseInsensitive) {
            baseArtist = String(baseArtist[..<featIdx.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        let normArtist = MusicKitManager.normalizedAlbumTitle(baseArtist)
        return "local_alb_\(normAlbum)_\(normArtist)"
    }

    public func getCachedLocalAlbumArtwork(album: String, artist: String) -> Data? {
        guard let albKey = Self.localAlbumCacheKey(album: album, artist: artist) else { return nil }
        let nsKey = albKey as NSString
        if let mem = artworkCache.object(forKey: nsKey) as Data? {
            return mem
        }
        if let disk = ArtworkDiskCache.shared.get(key: albKey) {
            artworkCache.setObject(disk as NSData, forKey: nsKey)
            return disk
        }
        return nil
    }

    // MARK: - Track Artwork by Database ID

    public func isKnownMissingTrackArtwork(id: Int) -> Bool {
        guard id > 0 else { return true }
        lock.lock()
        let missing = negativeArtworkIds.contains(id)
        lock.unlock()
        if missing { return true }
        return PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.stagedTemporaryTrackDbIds.contains(id) }
    }

    public func getTrackArtwork(
        id: Int,
        album: String = "",
        artist: String = "",
        skipIfContended: Bool = false
    ) -> Data? {
        // Local Music.app database IDs are small integers (< 10,000,000); 10-digit Apple Music catalog IDs are never local
        guard id > 0 && id < 10_000_000 else { return nil }

        let cacheKey = "track_\(id)" as NSString
        if let cached = artworkCache.object(forKey: cacheKey) as Data? {
            return cached
        }

        // Fast path 0: Check persistent disk LRU cache by track ID
        if let diskData = ArtworkDiskCache.shared.get(key: "track_\(id)") {
            artworkCache.setObject(diskData as NSData, forKey: cacheKey)
            return diskData
        }

        let meta = (album.isEmpty || artist.isEmpty) ? PlaybackStateStore.shared.getTrackMetadata(id: id) : nil
        let effAlbum = !album.isEmpty ? album : (meta?.album ?? "")
        let effArtist = !artist.isEmpty ? artist : (meta?.artist ?? "")
        let albCacheKey = Self.localAlbumCacheKey(album: effAlbum, artist: effArtist)

        // Fast path 1: Check local album-level memory/disk cache so tracks 2..N of the same album never repeat AppleScript
        if let albKey = albCacheKey {
            let nsAlbKey = albKey as NSString
            if let memAlb = artworkCache.object(forKey: nsAlbKey) as Data? {
                artworkCache.setObject(memAlb as NSData, forKey: cacheKey)
                return memAlb
            }
            if let diskAlb = ArtworkDiskCache.shared.get(key: albKey) {
                artworkCache.setObject(diskAlb as NSData, forKey: nsAlbKey)
                artworkCache.setObject(diskAlb as NSData, forKey: cacheKey)
                return diskAlb
            }
        }

        // Fast negative-cache & staged-cloud-track check BEFORE touching Music.app IPC
        if isKnownMissingTrackArtwork(id: id) {
            return nil
        }
        if let albKey = albCacheKey {
            let albNeg: Bool = lock.withLock {
                if let ts = negativeLocalAlbums[albKey], Date().timeIntervalSince(ts) < 600.0 {
                    return true
                }
                return false
            }
            if albNeg {
                return nil
            }
        }

        if skipIfContended && AppleScriptExecutor.shared.isBusy {
            return nil
        }

        // Retrieve embedded track artwork from Music.app via indexed database ID lookup (short budget, never triggers watchdog)
        let script = """
        tell application "Music"
            try
                with timeout of 1.0 seconds
                    set t to (first track of library playlist 1 whose database ID is \(id))
                    if (location of t) is not missing value and (count of artworks of t) > 0 then
                        return raw data of artwork 1 of t
                    end if
                end timeout
            end try
            return missing value
        end tell
        """
        let waitBudget: TimeInterval = skipIfContended ? 0.45 : 1.4
        guard let desc = AppleScriptExecutor.shared.executeDescriptor(script, maxWait: waitBudget, reportTimeout: false) else {
            return nil
        }
        if !desc.data.isEmpty {
            let d = desc.data
            let finalBytes: Data
            if let img = NSImage(data: d), let jpeg = jpegData(from: img, maxDimension: 600) {
                finalBytes = jpeg
            } else {
                finalBytes = d
            }
            artworkCache.setObject(finalBytes as NSData, forKey: cacheKey)
            ArtworkDiskCache.shared.set(key: "track_\(id)", data: finalBytes)
            if let albKey = albCacheKey {
                artworkCache.setObject(finalBytes as NSData, forKey: albKey as NSString)
                ArtworkDiskCache.shared.set(key: albKey, data: finalBytes)
            }
            return finalBytes
        }

        lock.withLock {
            negativeArtworkIds.insert(id)
            if let albKey = albCacheKey {
                negativeLocalAlbums[albKey] = Date()
            }
        }
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

        let isNegativeCached: Bool = {
            lock.lock()
            defer { lock.unlock() }
            if let ts = negativePlaylistArtworks[name], Date().timeIntervalSince(ts) < 600.0 {
                return true
            }
            return false
        }()
        if isNegativeCached {
            return nil
        }

        let escapedPlName = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Music"
            with timeout of 2.5 seconds
                set p to missing value
                try
                    set p to (first user playlist whose name is "\(escapedPlName)")
                on error
                    try
                        set p to (first playlist whose name is "\(escapedPlName)")
                    end try
                end try
                if p is not missing value then
                    try
                        if (count of artworks of p) > 0 then
                            return raw data of artwork 1 of p
                        end if
                    end try
                    try
                        set trCount to (count of tracks of p)
                        if trCount > 5 then set trCount to 5
                        repeat with i from 1 to trCount
                            set t to track i of p
                            if (count of artworks of t) > 0 then
                                return raw data of artwork 1 of t
                            end if
                        end repeat
                    end try
                end if
                return missing value
            end timeout
        end tell
        """

        guard let desc = AppleScriptExecutor.shared.executeDescriptor(script, maxWait: 3.0) else {
            return nil
        }
        guard desc.descriptorType != typeNull else {
            lock.lock()
            negativePlaylistArtworks[name] = Date()
            lock.unlock()
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
        lock.lock()
        negativePlaylistArtworks[name] = Date()
        lock.unlock()
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

    public func clearPlaylistArtworkCache(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock()
        artworkCache.removeObject(forKey: "playlist_\(trimmed)" as NSString)
        playlistArtworkUrlCache.removeValue(forKey: trimmed)
        negativePlaylistArtworks.removeValue(forKey: trimmed)
        lock.unlock()
        ArtworkDiskCache.shared.remove(key: "playlist_\(trimmed)")
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
                    if let nid = t.numericId, nid > 0 {
                        let cacheKey = "track_\(nid)" as NSString
                        if let cached = self.artworkCache.object(forKey: cacheKey) as Data? {
                            return (i, "data:image/jpeg;base64,\(cached.base64EncodedString())")
                        }
                    }
                    if let local = self.findLocalTrackArtwork(name: t.name, artist: t.artist) {
                        return (i, local)
                    }
                    if let cachedCloud = MusicKitManager.shared.getCachedTrackArtwork(name: t.name, artist: t.artist, album: t.album), !cachedCloud.isEmpty {
                        return (i, cachedCloud)
                    }
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
        guard !AppleScriptExecutor.shared.isBusy else { return }
        let stagedIds = PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.stagedTemporaryTrackDbIds }
        var toFetch = [Int]()
        lock.withLock {
            for nid in ids where nid > 0 && nid < 10_000_000 && !stagedIds.contains(nid) {
                let cacheKey = "track_\(nid)" as NSString
                if self.artworkCache.object(forKey: cacheKey) == nil
                    && !self.negativeArtworkIds.contains(nid)
                    && !self.fetchingArtworkIds.contains(nid) {
                    self.fetchingArtworkIds.insert(nid)
                    toFetch.append(nid)
                }
            }
        }

        let fetchIds = toFetch
        if !fetchIds.isEmpty {
            artworkFetchQueue.async { [weak self] in
                guard let self = self else { return }
                for nid in fetchIds {
                    if !AppleScriptExecutor.shared.isBusy {
                        _ = self.getTrackArtwork(id: nid)
                    }
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
