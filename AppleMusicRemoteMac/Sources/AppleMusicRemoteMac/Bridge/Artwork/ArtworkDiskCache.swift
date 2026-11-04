//
//  ArtworkDiskCache.swift
//  AppleMusicRemoteMac
//
//  High-speed persistent LRU disk cache for track, album, and playlist artworks.
//

import Foundation
import CryptoKit

public final class ArtworkDiskCache: @unchecked Sendable {
    public static let shared = ArtworkDiskCache()

    private let cacheDirectory: URL
    private let maxCacheSizeBytes: Int64
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.kirill.AppleMusicRemoteMac.ArtworkDiskCache", qos: .utility)
    private let lock = NSLock()

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
        guard fileManager.fileExists(atPath: path.path) else { return nil }

        // Update modification time for LRU tracking
        queue.async { [weak self] in
            guard let self = self else { return }
            try? self.fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path)
        }

        return try? Data(contentsOf: path)
    }

    public func set(key: String, data: Data) {
        guard !key.isEmpty, !data.isEmpty else { return }
        let path = filePath(for: key)

        queue.async { [weak self] in
            guard let self = self else { return }
            try? data.write(to: path, options: .atomic)
            self.cleanLRUIfNeeded()
        }
    }

    public func remove(key: String) {
        guard !key.isEmpty else { return }
        let path = filePath(for: key)
        try? fileManager.removeItem(at: path)
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    public func totalCacheSize() -> Int64 {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for file in files {
            if let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private func cleanLRUIfNeeded() {
        guard totalCacheSize() > maxCacheSizeBytes else { return }

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

    private var urlIndex: [String: IndexEntry] = [:]
    private var inFlightHashes: Set<String> = []

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
        guard remoteUrl.hasPrefix("http://") || remoteUrl.hasPrefix("https://"),
              let url = URL(string: remoteUrl) else {
            completion?(nil)
            return
        }
        if let existingEndpoint = localEndpointIfCached(for: remoteUrl) {
            completion?(existingEndpoint)
            return
        }

        let hash = videoHash(for: remoteUrl)
        lock.lock()
        if inFlightHashes.contains(hash) {
            lock.unlock()
            return
        }
        inFlightHashes.insert(hash)
        lock.unlock()

        var req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15.0)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            guard let self = self else { return }
            defer {
                self.lock.lock()
                self.inFlightHashes.remove(hash)
                self.lock.unlock()
            }
            guard let d = data,
                  d.count > 4096,
                  let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                completion?(nil)
                return
            }
            let dest = self.videoFileURL(forHash: hash)
            self.ioQueue.async {
                do {
                    try d.write(to: dest, options: .atomic)
                    NSLog("[MotionArtworkDiskCache] 💾 Cached motion cover .mp4 on disk (\(d.count / 1024) KB) -> \(hash).mp4")
                    self.cleanLRUIfNeeded()
                    completion?("/api/artwork/motion.mp4?hash=\(hash)")
                } catch {
                    completion?(nil)
                }
            }
        }.resume()
    }

    private func cleanLRUIfNeeded() {
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

        guard currentTotal > maxCacheSizeBytes else { return }
        mp4Files.sort { $0.date < $1.date }

        let targetSize = Int64(Double(maxCacheSizeBytes) * 0.75)
        for item in mp4Files {
            if currentTotal <= targetSize { break }
            if (try? fileManager.removeItem(at: item.url)) != nil {
                currentTotal -= item.size
            }
        }
    }
}
