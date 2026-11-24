//
//  ArtworkDiskCache.swift
//  AppleMusicRemoteMac
//
//  High-speed persistent LRU disk cache for track, album, and playlist artworks.
//

import CryptoKit
import Foundation

public final class ArtworkDiskCache: @unchecked Sendable {
    public static let shared = ArtworkDiskCache()

    private let cacheDirectory: URL
    private let maxCacheSizeBytes: Int64
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.kirill.AppleMusicRemoteMac.ArtworkDiskCache", qos: .utility)
    private let lock = NSLock()
    private var cachedTotalBytes: Int64?

    public init(maxSizeMB: Int = 250) {
        self.maxCacheSizeBytes = Int64(maxSizeMB) * 1024 * 1024
        let baseCache = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.cacheDirectory = baseCache.appendingPathComponent("com.kirill.AppleMusicRemoteMac/Artworks", isDirectory: true)

        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private func filePath(for key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8))
        let hexString = hash.compactMap { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(hexString + ".img")
    }

    public func get(key: String) -> Data? {
        guard !key.isEmpty else { return nil }
        let path = filePath(for: key)
        let data: Data? = lock.withLock {
            guard fileManager.fileExists(atPath: path.path) else { return nil }
            return try? Data(contentsOf: path)
        }
        guard data != nil else { return nil }

        // Update modification time for LRU tracking
        queue.async { [weak self] in
            guard let self = self else { return }
            self.lock.withLock {
                try? self.fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path)
            }
        }

        return data
    }

    public func set(key: String, data: Data) {
        guard !key.isEmpty, !data.isEmpty else { return }
        let path = filePath(for: key)

        queue.async { [weak self] in
            guard let self = self else { return }
            self.lock.withLock {
                try? self.fileManager.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
                let currentTotal = self.totalCacheSizeLocked()
                let oldSize = (try? self.fileManager.attributesOfItem(atPath: path.path))?[.size] as? Int64 ?? 0
                if (try? data.write(to: path, options: .atomic)) != nil {
                    self.cachedTotalBytes = max(0, currentTotal - oldSize) + Int64(data.count)
                    self.cleanLRUIfNeededLocked()
                }
            }
        }
    }

    public func remove(key: String) {
        guard !key.isEmpty else { return }
        let path = filePath(for: key)
        lock.withLock {
            let oldSize = (try? fileManager.attributesOfItem(atPath: path.path))?[.size] as? Int64 ?? 0
            if (try? fileManager.removeItem(at: path)) != nil, let current = cachedTotalBytes {
                cachedTotalBytes = max(0, current - oldSize)
            }
        }
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        cachedTotalBytes = 0
    }

    public func totalCacheSize() -> Int64 {
        lock.withLock {
            totalCacheSizeLocked()
        }
    }

    private func totalCacheSizeLocked() -> Int64 {
        if let cached = cachedTotalBytes {
            return cached
        }
        return scanDirectorySizeLocked()
    }

    private func scanDirectorySizeLocked() -> Int64 {
        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else {
            cachedTotalBytes = 0
            return 0
        }
        var total: Int64 = 0
        for file in files {
            if let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                total += Int64(size)
            }
        }
        cachedTotalBytes = total
        return total
    }

    private func cleanLRUIfNeededLocked() {
        guard totalCacheSizeLocked() > maxCacheSizeBytes else { return }

        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return }

        var fileInfos: [(url: URL, date: Date, size: Int64)] = []
        var currentTotal: Int64 = 0

        for file in files {
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let date = values.contentModificationDate,
                  let size = values.fileSize else { continue }
            fileInfos.append((url: file, date: date, size: Int64(size)))
            currentTotal += Int64(size)
        }

        // Sort oldest first
        fileInfos.sort { $0.date < $1.date }

        let targetSize = Int64(Double(maxCacheSizeBytes) * 0.75)
        for item in fileInfos {
            if currentTotal <= targetSize { break }
            if (try? fileManager.removeItem(at: item.url)) != nil {
                currentTotal -= item.size
            }
        }
        cachedTotalBytes = max(0, currentTotal)
    }
}

// MARK: - Persistent Disk & URL Cache for Apple Music Motion Covers (.mp4)

public final class MotionArtworkDiskCache: @unchecked Sendable {
    public static let shared = MotionArtworkDiskCache()

    public struct IndexEntry: Codable {
        public let remoteUrl: String
        public let updatedAt: Double
    }

    private let cacheDirectory: URL
    private let indexFileURL: URL
    private let maxCacheSizeBytes: Int64
    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "com.kirill.AppleMusicRemoteMac.MotionArtworkDiskCache", qos: .utility)
    private let lock = NSLock()
    private var cachedTotalBytes: Int64?

    private var urlIndex: [String: IndexEntry] = [:]
    private var inFlightCompletions: [String: [@Sendable (String?) -> Void]] = [:]

    /// Positive entries live for 30 days; negative ("") entries expire after 12 hours
    private let positiveTTL: TimeInterval = 86400 * 30
    private let negativeTTL: TimeInterval = 3600 * 12

    public init(maxSizeMB: Int = 500) {
        self.maxCacheSizeBytes = Int64(maxSizeMB) * 1024 * 1024
        let baseCache = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.cacheDirectory = baseCache.appendingPathComponent("com.kirill.AppleMusicRemoteMac/MotionArtworks", isDirectory: true)
        self.indexFileURL = cacheDirectory.appendingPathComponent("motion_index.json")

        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        loadIndexFromDisk()
    }

    private func loadIndexFromDisk() {
        guard fileManager.fileExists(atPath: indexFileURL.path),
              let data = try? Data(contentsOf: indexFileURL),
              let decoded = try? JSONDecoder().decode([String: IndexEntry].self, from: data) else {
            return
        }
        let now = Date().timeIntervalSince1970
        lock.lock()
        self.urlIndex = decoded.filter { _, entry in
            let ttl = entry.remoteUrl.isEmpty ? negativeTTL : positiveTTL
            return (now - entry.updatedAt) < ttl
        }
        lock.unlock()
    }

    private func saveIndexToDiskAsync() {
        lock.lock()
        let snapshot = urlIndex
        lock.unlock()

        ioQueue.async { [weak self] in
            guard let self = self else { return }
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: self.indexFileURL, options: .atomic)
            }
        }
    }

    public func videoHash(for remoteUrl: String) -> String {
        let digest = SHA256.hash(data: Data(remoteUrl.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func videoFileURL(forHash hash: String) -> URL {
        return cacheDirectory.appendingPathComponent(hash + ".mp4")
    }

    /// Looks up the first matching key in the persistent index.
    /// Returns `.some(url)` on hit (`url == ""` means cached negative result), or `nil` on cache miss.
    public func lookupUrl(keys: [String]) -> String? {
        let now = Date().timeIntervalSince1970
        lock.lock()
        defer { lock.unlock() }

        for key in keys where !key.isEmpty {
            if let entry = urlIndex[key] {
                let ttl = entry.remoteUrl.isEmpty ? negativeTTL : positiveTTL
                if (now - entry.updatedAt) < ttl {
                    return entry.remoteUrl
                } else {
                    urlIndex.removeValue(forKey: key)
                }
            }
        }
        return nil
    }

    public func storeUrl(_ remoteUrl: String, forKeys keys: [String]) {
        let now = Date().timeIntervalSince1970
        let entry = IndexEntry(remoteUrl: remoteUrl, updatedAt: now)
        lock.lock()
        for key in keys where !key.isEmpty {
            urlIndex[key] = entry
        }
        lock.unlock()
        saveIndexToDiskAsync()
    }

    /// Returns local HTTP endpoint `/api/artwork/motion.mp4?hash=<sha256>` if the video binary is already cached on disk.
    public func localEndpointIfCached(for remoteUrl: String) -> String? {
        guard !remoteUrl.isEmpty else { return nil }
        let hash = videoHash(for: remoteUrl)
        let path = videoFileURL(forHash: hash)
        guard fileManager.fileExists(atPath: path.path),
              let size = (try? path.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              size > 4096 else {
            return nil
        }
        ioQueue.async { [weak self] in
            try? self?.fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path)
        }
        return "/api/artwork/motion.mp4?hash=\(hash)"
    }

    public func getVideoData(forHash hash: String) -> Data? {
        let cleanHash = hash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleanHash.count == 64,
              cleanHash.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        let path = videoFileURL(forHash: cleanHash)
        guard fileManager.fileExists(atPath: path.path) else { return nil }

        ioQueue.async { [weak self] in
            try? self?.fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path)
        }
        return try? Data(contentsOf: path)
    }

    /// Downloads the remote `.mp4` in the background if not yet cached on disk.
    public func cacheVideoInBackground(remoteUrl: String, completion: (@Sendable (String?) -> Void)? = nil) {
        guard let url = URL(string: remoteUrl),
              ArtworkService.isAllowedRemoteArtworkURL(url) else {
            completion?(nil)
            return
        }
        if let existingEndpoint = localEndpointIfCached(for: remoteUrl) {
            completion?(existingEndpoint)
            return
        }

        let hash = videoHash(for: remoteUrl)
        lock.lock()
        if inFlightCompletions[hash] != nil {
            if let completion {
                inFlightCompletions[hash]?.append(completion)
            }
            lock.unlock()
            return
        }
        inFlightCompletions[hash] = completion.map { [$0] } ?? []
        lock.unlock()

        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            let data = await ArtworkService.shared.safeArtworkFetcher.fetch(
                url: url,
                timeout: 15.0,
                maxBytes: 40 * 1024 * 1024,
                userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
            )
            guard let d = data, d.count > 4096 else {
                let callbacks = self.lock.withLock { self.inFlightCompletions.removeValue(forKey: hash) ?? [] }
                for cb in callbacks {
                    cb(nil)
                }
                return
            }
            let dest = self.videoFileURL(forHash: hash)
            self.ioQueue.async {
                do {
                    let oldSize = (try? self.fileManager.attributesOfItem(atPath: dest.path))?[.size] as? Int64 ?? 0
                    try d.write(to: dest, options: .atomic)
                    NSLog("[MotionArtworkDiskCache] 💾 Cached motion cover .mp4 on disk (\(d.count / 1024) KB) -> \(hash).mp4")
                    self.recordWrittenBytesAndCleanLRUIfNeeded(oldSize: oldSize, newSize: Int64(d.count))
                    let endpoint = "/api/artwork/motion.mp4?hash=\(hash)"
                    let callbacks = self.lock.withLock { self.inFlightCompletions.removeValue(forKey: hash) ?? [] }
                    for cb in callbacks {
                        cb(endpoint)
                    }
                } catch {
                    let callbacks = self.lock.withLock { self.inFlightCompletions.removeValue(forKey: hash) ?? [] }
                    for cb in callbacks {
                        cb(nil)
                    }
                }
            }
        }
    }

    private func scanMp4DirectorySize() -> Int64 {
        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return 0 }
        var total: Int64 = 0
        for file in files where file.pathExtension == "mp4" {
            if let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private func recordWrittenBytesAndCleanLRUIfNeeded(oldSize: Int64, newSize: Int64) {
        let existingTotal: Int64? = lock.withLock { cachedTotalBytes }
        let baseTotal = existingTotal ?? scanMp4DirectorySize()
        let updatedTotal = max(0, baseTotal - oldSize) + newSize
        lock.withLock { cachedTotalBytes = updatedTotal }
        guard updatedTotal > maxCacheSizeBytes else { return }

        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return }

        var mp4Files: [(url: URL, date: Date, size: Int64)] = []
        var currentTotal: Int64 = 0

        for file in files where file.pathExtension == "mp4" {
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let date = values.contentModificationDate,
                  let size = values.fileSize else { continue }
            mp4Files.append((url: file, date: date, size: Int64(size)))
            currentTotal += Int64(size)
        }

        guard currentTotal > maxCacheSizeBytes else {
            lock.withLock { cachedTotalBytes = max(0, currentTotal) }
            return
        }
        mp4Files.sort { $0.date < $1.date }

        let targetSize = Int64(Double(maxCacheSizeBytes) * 0.75)
        for item in mp4Files {
            if currentTotal <= targetSize { break }
            if (try? fileManager.removeItem(at: item.url)) != nil {
                currentTotal -= item.size
            }
        }
        lock.withLock { cachedTotalBytes = max(0, currentTotal) }
    }
}

// MARK: - Persistent Disk Cache for Resolved CDN Artwork URLs

public final class ArtworkUrlDiskCache: @unchecked Sendable {
    public static let shared = ArtworkUrlDiskCache()

    public struct AlbumUrlRecord: Codable, Sendable {
        public let album: String
        public let artist: String
        public let url: String
        public let updatedAt: Double

        public init(album: String, artist: String, url: String, updatedAt: Double) {
            self.album = album
            self.artist = artist
            self.url = url
            self.updatedAt = updatedAt
        }
    }

    private struct PersistedStore: Codable {
        var tracks: [String: IndexEntry]
        var albums: [String: [AlbumUrlRecord]]
    }

    public struct IndexEntry: Codable, Sendable {
        public let url: String
        public let updatedAt: Double
    }

    private let cacheDirectory: URL
    private let storeFileURL: URL
    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "com.kirill.AppleMusicRemoteMac.ArtworkUrlDiskCache", qos: .utility)
    private let lock = NSLock()

    private var trackUrls: [String: IndexEntry] = [:]
    private var albumUrlsByNormTitle: [String: [AlbumUrlRecord]] = [:]
    private var savePending = false

    private let positiveTTL: TimeInterval = 86400 * 30
    private let maxTrackEntries = 6000
    private let maxAlbumBuckets = 4000

    public init(directory: URL? = nil) {
        if let directory {
            self.cacheDirectory = directory
        } else {
            let baseCache = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.cacheDirectory = baseCache.appendingPathComponent("com.kirill.AppleMusicRemoteMac/ArtworkUrls", isDirectory: true)
        }
        self.storeFileURL = self.cacheDirectory.appendingPathComponent("artwork_url_index_v1.json")
        try? fileManager.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
        loadFromDisk()
    }

    private func loadFromDisk() {
        guard fileManager.fileExists(atPath: storeFileURL.path),
              let data = try? Data(contentsOf: storeFileURL),
              let decoded = try? JSONDecoder().decode(PersistedStore.self, from: data) else {
            return
        }
        let now = Date().timeIntervalSince1970
        lock.lock()
        self.trackUrls = decoded.tracks.filter { _, entry in
            !entry.url.isEmpty && (now - entry.updatedAt) < positiveTTL
        }
        var filteredAlbums: [String: [AlbumUrlRecord]] = [:]
        for (normTitle, list) in decoded.albums {
            let valid = list.filter { !$0.url.isEmpty && (now - $0.updatedAt) < positiveTTL }
            if !valid.isEmpty {
                filteredAlbums[normTitle] = valid
            }
        }
        self.albumUrlsByNormTitle = filteredAlbums
        lock.unlock()
    }

    public func snapshot() -> (tracks: [String: String], albums: [String: [AlbumUrlRecord]]) {
        let now = Date().timeIntervalSince1970
        lock.lock()
        defer { lock.unlock() }
        var outTracks: [String: String] = [:]
        outTracks.reserveCapacity(trackUrls.count)
        for (k, v) in trackUrls where !v.url.isEmpty && (now - v.updatedAt) < positiveTTL {
            outTracks[k] = v.url
        }
        var outAlbums: [String: [AlbumUrlRecord]] = [:]
        outAlbums.reserveCapacity(albumUrlsByNormTitle.count)
        for (k, list) in albumUrlsByNormTitle {
            let valid = list.filter { !$0.url.isEmpty && (now - $0.updatedAt) < positiveTTL }
            if !valid.isEmpty {
                outAlbums[k] = valid
            }
        }
        return (outTracks, outAlbums)
    }

    public func storeTrackUrl(_ url: String, forKeys keys: [String]) {
        guard url.hasPrefix("http://") || url.hasPrefix("https://") else { return }
        let now = Date().timeIntervalSince1970
        let entry = IndexEntry(url: url, updatedAt: now)
        var changed = false
        lock.lock()
        for key in keys where !key.isEmpty {
            if trackUrls[key]?.url != url {
                trackUrls[key] = entry
                changed = true
            }
        }
        if trackUrls.count > maxTrackEntries {
            let sorted = trackUrls.sorted { $0.value.updatedAt > $1.value.updatedAt }
            trackUrls = Dictionary(uniqueKeysWithValues: sorted.prefix(Int(Double(maxTrackEntries) * 0.8)).map { ($0.key, $0.value) })
            changed = true
        }
        lock.unlock()
        if changed {
            scheduleSave()
        }
    }

    public func storeAlbumArtworks(_ records: [(normTitle: String, album: String, artist: String, url: String)]) {
        guard !records.isEmpty else { return }
        let now = Date().timeIntervalSince1970
        var changed = false
        lock.lock()
        for rec in records {
            guard !rec.normTitle.isEmpty,
                  rec.url.hasPrefix("http://") || rec.url.hasPrefix("https://") else { continue }
            var bucket = albumUrlsByNormTitle[rec.normTitle] ?? []
            if let idx = bucket.firstIndex(where: {
                $0.artist.caseInsensitiveCompare(rec.artist) == .orderedSame
            }) {
                if bucket[idx].url != rec.url {
                    bucket[idx] = AlbumUrlRecord(album: rec.album, artist: rec.artist, url: rec.url, updatedAt: now)
                    changed = true
                }
            } else {
                bucket.append(AlbumUrlRecord(album: rec.album, artist: rec.artist, url: rec.url, updatedAt: now))
                if bucket.count > 8 {
                    bucket.removeFirst(bucket.count - 8)
                }
                changed = true
            }
            albumUrlsByNormTitle[rec.normTitle] = bucket
        }
        if albumUrlsByNormTitle.count > maxAlbumBuckets {
            let sorted = albumUrlsByNormTitle.sorted { lhs, rhs in
                let lMax = lhs.value.map(\.updatedAt).max() ?? 0
                let rMax = rhs.value.map(\.updatedAt).max() ?? 0
                return lMax > rMax
            }
            albumUrlsByNormTitle = Dictionary(uniqueKeysWithValues: sorted.prefix(Int(Double(maxAlbumBuckets) * 0.8)).map { ($0.key, $0.value) })
            changed = true
        }
        lock.unlock()
        if changed {
            scheduleSave()
        }
    }

    public func clear() {
        lock.lock()
        trackUrls.removeAll()
        albumUrlsByNormTitle.removeAll()
        lock.unlock()
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            try? self.fileManager.removeItem(at: self.storeFileURL)
        }
    }

    private func scheduleSave() {
        lock.lock()
        if savePending {
            lock.unlock()
            return
        }
        savePending = true
        lock.unlock()

        ioQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            self.savePending = false
            let store = PersistedStore(tracks: self.trackUrls, albums: self.albumUrlsByNormTitle)
            self.lock.unlock()

            try? self.fileManager.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(store) {
                try? data.write(to: self.storeFileURL, options: .atomic)
            }
        }
    }
}
