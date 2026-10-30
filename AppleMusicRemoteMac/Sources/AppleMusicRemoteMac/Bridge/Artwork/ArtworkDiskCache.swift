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
