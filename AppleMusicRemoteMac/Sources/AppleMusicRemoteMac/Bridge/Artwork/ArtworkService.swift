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
import Vision

public final class ArtworkService: @unchecked Sendable {
    public static let shared = ArtworkService()

    private final class PaletteResultBox: @unchecked Sendable {
        let value: [String: Any]?
        init(_ value: [String: Any]?) { self.value = value }
    }

    private let lock = NSLock()
    private let visionLock = NSLock()
    private let visionQueue = DispatchQueue(label: "com.amr.artwork.vision", qos: .utility)
    private let artworkFetchQueue = DispatchQueue(label: "com.amr.artwork.local", qos: .utility)
    private let artworkCache = NSCache<NSString, NSData>()
    private var playlistArtworkUrlCache: [String: String] = [:]
    private var paletteCache: [String: [String: Any]] = [:]
    private var inFlightPaletteTasks: [String: Task<PaletteResultBox, Never>] = [:]
    private var negativeArtworkIds = Set<Int>()
    private var fetchingArtworkIds = Set<Int>()
    private var negativePlaylistArtworks: [String: Date] = [:]

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

    public func isKnownMissingTrackArtwork(id: Int) -> Bool {
        guard id > 0 else { return true }
        lock.lock()
        let missing = negativeArtworkIds.contains(id)
        lock.unlock()
        if missing { return true }
        return PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.stagedTemporaryTrackDbIds.contains(id) }
    }

    public func getTrackArtwork(id: Int) -> Data? {
        // Local Music.app database IDs are small integers (< 10,000,000); 10-digit Apple Music catalog IDs are never local
        guard id > 0 && id < 10_000_000 else { return nil }

        let cacheKey = "track_\(id)" as NSString
        if let cached = artworkCache.object(forKey: cacheKey) as Data? {
            return cached
        }

        // Fast path 0: Check persistent disk LRU cache
        if let diskData = ArtworkDiskCache.shared.get(key: "track_\(id)") {
            artworkCache.setObject(diskData as NSData, forKey: cacheKey)
            return diskData
        }

        // Fast negative-cache & staged-cloud-track check BEFORE touching Music.app IPC
        if isKnownMissingTrackArtwork(id: id) {
            return nil
        }

        // Retrieve embedded track artwork from Music.app via indexed database ID lookup (short budget, never triggers watchdog)
        let script = """
        tell application "Music"
            try
                with timeout of 1.2 seconds
                    set t to (first track of library playlist 1 whose database ID is \(id))
                    if (location of t) is not missing value and (count of artworks of t) > 0 then
                        return raw data of artwork 1 of t
                    end if
                end timeout
            end try
            return missing value
        end tell
        """
        guard let desc = AppleScriptExecutor.shared.executeDescriptor(script, maxWait: 1.3, reportTimeout: false) else {
            // Executor was contended or timed out — do not poison negative cache if merely contended, just return nil
            return nil
        }
        if !desc.data.isEmpty {
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

        guard let desc = AppleScriptExecutor.shared.executeDescriptor(script) else {
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

    // MARK: - Apple Neural Engine Vision Saliency Palette (TV Ambient & WLED 16-Zone)

    /// Preloads and compiles the `VNGenerateAttentionBasedSaliencyImageRequest` graph on Apple Neural Engine at app launch.
    public func prewarmVisionSaliencyModel() {
        guard NativeMusicCuratorService.shared.isAppleSilicon else { return }
        let size = 32
        var pixels = [UInt8](repeating: 128, count: size * size * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = ctx.makeImage() else {
            return
        }
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }

    /// Analyzes album artwork on the Apple Neural Engine using `VNGenerateAttentionBasedSaliencyImageRequest`
    /// to locate visually salient objects (ignoring wide black/white/grey borders) and extracts:
    /// - `ambient_rgb`: 4 vibrant RGB colors (`[[Int]]`) for TV `#standby-ambient-bg`, RTA backdrop, and player ambient glow
    /// - `wled_zones`: 16 spatial RGB zones (`[[Int]]`) weighted by neural saliency for `WLEDDDPController`
    public func extractVisionSaliencyPalette(
        from imageData: Data,
        useNeuralSaliency: Bool = NativeMusicCuratorService.shared.isEnabled
    ) -> [String: Any]? {
        guard !imageData.isEmpty,
              let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let gridSize = 64
        var pixelData = [UInt8](repeating: 0, count: gridSize * gridSize * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixelData,
            width: gridSize,
            height: gridSize,
            bitsPerComponent: 8,
            bytesPerRow: gridSize * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: gridSize, height: gridSize))

        // 1. Run Apple Neural Engine Attention-Based Saliency if enabled
        var saliencyGrid = [Float](repeating: 0.0, count: gridSize * gridSize)
        var salientBoxes: [[Double]] = []
        var usedNeuralSaliency = false

        if useNeuralSaliency && NativeMusicCuratorService.shared.isAppleSilicon {
            let smallCgImage = ctx.makeImage() ?? cgImage
            visionLock.lock()
            defer { visionLock.unlock() }
            let request = VNGenerateAttentionBasedSaliencyImageRequest()
            let handler = VNImageRequestHandler(cgImage: smallCgImage, options: [:])
            do {
                try handler.perform([request])
                if let observation = request.results?.first as? VNSaliencyImageObservation {
                    usedNeuralSaliency = true

                    // Record normalized bounding boxes (top-left origin [x, y, width, height])
                    if let objects = observation.salientObjects {
                        for obj in objects {
                            let bb = obj.boundingBox
                            let topY = max(0.0, min(1.0, 1.0 - bb.origin.y - bb.size.height))
                            salientBoxes.append([
                                Double(bb.origin.x),
                                Double(topY),
                                Double(bb.size.width),
                                Double(bb.size.height)
                            ])
                        }
                    }

                    // Sample the 68x68 Float32 heatmap buffer + salient bounding boxes into our 64x64 grid
                    let pb = observation.pixelBuffer
                    CVPixelBufferLockBaseAddress(pb, .readOnly)
                    defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

                    let pbWidth = CVPixelBufferGetWidth(pb)
                    let pbHeight = CVPixelBufferGetHeight(pb)
                    let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
                    let basePtr = CVPixelBufferGetBaseAddress(pb)

                    for gy in 0..<gridSize {
                        let normX_YTop = Double(gy) / Double(gridSize - 1)
                        let visionY = 1.0 - normX_YTop
                        let py = min(pbHeight - 1, max(0, Int(visionY * Double(pbHeight - 1))))

                        for gx in 0..<gridSize {
                            let normX = Double(gx) / Double(gridSize - 1)
                            let px = min(pbWidth - 1, max(0, Int(normX * Double(pbWidth - 1))))
                            var heatVal: Float = 0.0

                            if let base = basePtr {
                                let rowPtr = base.advanced(by: py * bytesPerRow).assumingMemoryBound(to: Float.self)
                                heatVal = max(0.0, min(1.0, rowPtr[px]))
                            }

                            // Boost pixels that fall inside any salient object bounding box
                            for box in salientBoxes {
                                if normX >= box[0] && normX <= (box[0] + box[2]) &&
                                   normX_YTop >= box[1] && normX_YTop <= (box[1] + box[3]) {
                                    heatVal = max(heatVal, 0.75)
                                }
                            }
                            saliencyGrid[gy * gridSize + gx] = heatVal
                        }
                    }
                }
            } catch {
                usedNeuralSaliency = false
            }
        }

        // 2. Build 14 perceptual color clusters (12 hue bins + 2 warm/cool midtone bins) weighted by Saliency × Saturation
        struct ColorBucket {
            var rSum: Double = 0
            var gSum: Double = 0
            var bSum: Double = 0
            var weightSum: Double = 0
        }
        var buckets = [ColorBucket](repeating: ColorBucket(), count: 14)

        var fallbackR: Double = 0
        var fallbackG: Double = 0
        var fallbackB: Double = 0
        var fallbackW: Double = 0

        for gy in 0..<gridSize {
            for gx in 0..<gridSize {
                let idx = (gy * gridSize + gx) * 4
                let r = Double(pixelData[idx])
                let g = Double(pixelData[idx + 1])
                let b = Double(pixelData[idx + 2])
                let a = Double(pixelData[idx + 3])
                if a < 128 { continue }

                let maxC = max(r, g, b)
                let minC = min(r, g, b)
                let delta = maxC - minC
                let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                let sat = maxC > 0 ? (delta / maxC) : 0.0
                let sal = Double(saliencyGrid[gy * gridSize + gx])

                // Track global saliency-weighted average for monochrome fallback
                let baseW = 1.0 + sal * 6.0
                fallbackR += r * baseW
                fallbackG += g * baseW
                fallbackB += b * baseW
                fallbackW += baseW

                // Ignore pitch-black margins and pure-white borders when picking vibrant ambient colors
                if lum < 16.0 || lum > 246.0 { continue }

                // Center bias (light) + strong Neural Saliency boost (up to 9x) + saturation preference
                let cx = abs(Double(gx) / Double(gridSize - 1) - 0.5) * 2.0
                let cy = abs(Double(gy) / Double(gridSize - 1) - 0.5) * 2.0
                let centerFactor = max(0.4, 1.15 - 0.35 * (cx * cx + cy * cy))
                let salFactor = usedNeuralSaliency ? (1.0 + sal * 8.5) : centerFactor
                let satFactor = 0.15 + pow(sat, 1.25) * 3.2
                let lumWindow = (lum > 35.0 && lum < 225.0) ? 1.2 : 0.65

                let weight = salFactor * satFactor * lumWindow

                let bucketIdx: Int
                if sat < 0.12 {
                    bucketIdx = (r >= b) ? 12 : 13
                } else {
                    var hue: Double = 0.0
                    if delta > 0.0001 {
                        if maxC == r {
                            hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6.0)
                        } else if maxC == g {
                            hue = ((b - r) / delta) + 2.0
                        } else {
                            hue = ((r - g) / delta) + 4.0
                        }
                        hue *= 60.0
                        if hue < 0 { hue += 360.0 }
                    }
                    bucketIdx = min(11, max(0, Int(hue / 30.0)))
                }

                buckets[bucketIdx].rSum += r * weight
                buckets[bucketIdx].gSum += g * weight
                buckets[bucketIdx].bSum += b * weight
                buckets[bucketIdx].weightSum += weight
            }
        }

        struct RankedColor {
            let r: Int
            let g: Int
            let b: Int
            let weight: Double
        }

        var rankedColors: [RankedColor] = []
        for b in buckets where b.weightSum > 0.01 {
            let avgR = b.rSum / b.weightSum
            let avgG = b.gSum / b.weightSum
            let avgB = b.bSum / b.weightSum
            let (vr, vg, vb) = Self.enhanceAmbientColor(r: avgR, g: avgG, b: avgB)
            rankedColors.append(RankedColor(r: vr, g: vg, b: vb, weight: b.weightSum))
        }
        rankedColors.sort { $0.weight > $1.weight }

        var ambientRGB: [[Int]] = []
        for cand in rankedColors {
            let isDistinct = ambientRGB.allSatisfy { existing in
                let dr = Double(existing[0] - cand.r)
                let dg = Double(existing[1] - cand.g)
                let db = Double(existing[2] - cand.b)
                return sqrt(dr * dr + dg * dg + db * db) >= 36.0
            }
            if isDistinct {
                ambientRGB.append([cand.r, cand.g, cand.b])
                if ambientRGB.count == 4 { break }
            }
        }

        // Fill remaining slots if the cover is minimalist/monochromatic
        if ambientRGB.isEmpty {
            let mr = fallbackW > 0 ? Int((fallbackR / fallbackW).rounded()) : 38
            let mg = fallbackW > 0 ? Int((fallbackG / fallbackW).rounded()) : 34
            let mb = fallbackW > 0 ? Int((fallbackB / fallbackW).rounded()) : 52
            ambientRGB.append([max(18, min(230, mr)), max(18, min(230, mg)), max(18, min(230, mb))])
        }
        while ambientRGB.count < 4 {
            let base = ambientRGB[ambientRGB.count - 1]
            let scale = (ambientRGB.count % 2 == 1) ? 0.78 : 1.18
            let nr = max(14, min(242, Int((Double(base[0]) * scale).rounded())))
            let ng = max(14, min(242, Int((Double(base[1]) * scale).rounded())))
            let nb = max(14, min(242, Int((Double(base[2]) * scale).rounded())))
            ambientRGB.append([nr, ng, nb])
        }

        // 3. Build 16-zone WLED Ambilight palette weighted by Neural Saliency
        let primarySalient = ambientRGB[0]
        var wledZones: [[Int]] = []
        let colsPerZone = max(1, gridSize / 16)

        for z in 0..<16 {
            let startX = z * colsPerZone
            let endX = (z == 15) ? gridSize : min(gridSize, (z + 1) * colsPerZone)
            var zr: Double = 0
            var zg: Double = 0
            var zb: Double = 0
            var zw: Double = 0

            for gy in 0..<gridSize {
                for gx in startX..<endX {
                    let idx = (gy * gridSize + gx) * 4
                    let r = Double(pixelData[idx])
                    let g = Double(pixelData[idx + 1])
                    let b = Double(pixelData[idx + 2])
                    let maxC = max(r, g, b)
                    let minC = min(r, g, b)
                    let sat = maxC > 0 ? ((maxC - minC) / maxC) : 0.0
                    let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                    let sal = Double(saliencyGrid[gy * gridSize + gx])

                    let borderPenalty = (lum < 14.0 || lum > 245.0) ? 0.15 : 1.0
                    let w = (1.0 + sal * 7.5) * (0.25 + sat * 2.4) * borderPenalty
                    zr += r * w
                    zg += g * w
                    zb += b * w
                    zw += w
                }
            }

            if zw > 0.01 {
                var rVal = zr / zw
                var gVal = zg / zw
                var bVal = zb / zw
                let zoneLum = 0.2126 * rVal + 0.7152 * gVal + 0.0722 * bVal
                // If an edge zone is mostly dark/white margin, blend 35% of the primary salient color so WLED stays alive
                if zoneLum < 22.0 || zoneLum > 240.0 {
                    rVal = rVal * 0.65 + Double(primarySalient[0]) * 0.35
                    gVal = gVal * 0.65 + Double(primarySalient[1]) * 0.35
                    bVal = bVal * 0.65 + Double(primarySalient[2]) * 0.35
                }
                let (er, eg, eb) = Self.enhanceAmbientColor(r: rVal, g: gVal, b: bVal)
                wledZones.append([er, eg, eb])
            } else {
                wledZones.append(primarySalient)
            }
        }

        return [
            "status": "ok",
            "ambient_rgb": ambientRGB,
            "wled_zones": wledZones,
            "salient_boxes": salientBoxes,
            "neural_saliency": usedNeuralSaliency,
            "engine": usedNeuralSaliency ? "Apple Neural Engine • Vision Saliency" : "Standard Grid Sampler"
        ]
    }

    private static func enhanceAmbientColor(r: Double, g: Double, b: Double) -> (Int, Int, Int) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let mid = (maxC + minC) * 0.5
        let sat = maxC > 0 ? ((maxC - minC) / maxC) : 0.0
        // Gently boost saturation for vivid TV & WLED glow without clipping
        let boost = (sat > 0.08 && sat < 0.75) ? 1.22 : 1.05
        let nr = max(12, min(248, Int((mid + (r - mid) * boost).rounded())))
        let ng = max(12, min(248, Int((mid + (g - mid) * boost).rounded())))
        let nb = max(12, min(248, Int((mid + (b - mid) * boost).rounded())))
        return (nr, ng, nb)
    }

    /// Resolves artwork bytes from Data URI, remote HTTP(S) URL, relative `/api/artwork/...` URL, or local track database ID
    /// and extracts the Neural Engine Vision Saliency palette (cached + single-flight deduplicated across clients).
    public func resolveArtworkPalette(url: String?, trackId: Int?) async -> [String: Any]? {
        let aiEnabled = NativeMusicCuratorService.shared.isEnabled
        let rawUrl = (url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let tid = trackId ?? 0

        let cacheKey: String
        if !rawUrl.isEmpty && !rawUrl.hasPrefix("data:") {
            cacheKey = "url|\(rawUrl)|ai:\(aiEnabled)"
        } else if tid > 0 {
            cacheKey = "tid|\(tid)|ai:\(aiEnabled)"
        } else if !rawUrl.isEmpty {
            cacheKey = "data|\(rawUrl.prefix(96).hashValue)|ai:\(aiEnabled)"
        } else {
            cacheKey = "current|ai:\(aiEnabled)"
        }

        if let cached = lock.withLock({ paletteCache[cacheKey] }) {
            return cached
        }

        let (existingTask, createdTask): (Task<PaletteResultBox, Never>?, Task<PaletteResultBox, Never>?) = lock.withLock {
            if let existing = inFlightPaletteTasks[cacheKey] {
                return (existing, nil)
            }
            let task = Task<PaletteResultBox, Never> { [weak self] in
                guard let self = self else { return PaletteResultBox(nil) }
                let computed = await self.computeArtworkPalette(rawUrl: rawUrl, tid: tid, aiEnabled: aiEnabled, cacheKey: cacheKey)
                _ = self.lock.withLock {
                    self.inFlightPaletteTasks.removeValue(forKey: cacheKey)
                }
                return PaletteResultBox(computed)
            }
            inFlightPaletteTasks[cacheKey] = task
            return (nil, task)
        }

        let box = await (existingTask ?? createdTask!).value
        return box.value
    }

    private func fetchRemotePaletteImageData(from urlStr: String) async -> Data? {
        if let diskData = ArtworkDiskCache.shared.get(key: urlStr) {
            return diskData
        }
        let fetchUrlStr = urlStr
            .replacingOccurrences(of: "1200x1200bb", with: "300x300bb")
            .replacingOccurrences(of: "600x600bb", with: "300x300bb")
        if let diskSmall = ArtworkDiskCache.shared.get(key: fetchUrlStr) {
            return diskSmall
        }
        guard let remoteUrl = URL(string: fetchUrlStr) else { return nil }
        var req = URLRequest(url: remoteUrl)
        req.timeoutInterval = 4.0
        if let (data, resp) = try? await URLSession.shared.data(for: req),
           let http = resp as? HTTPURLResponse,
           (200...299).contains(http.statusCode),
           !data.isEmpty {
            ArtworkDiskCache.shared.set(key: fetchUrlStr, data: data)
            return data
        }
        return nil
    }

    private func computeArtworkPalette(rawUrl: String, tid: Int, aiEnabled: Bool, cacheKey: String) async -> [String: Any]? {
        var imageData: Data? = nil

        // 1. Data URI
        if rawUrl.hasPrefix("data:image/"), let commaRange = rawUrl.range(of: ",") {
            let b64 = String(rawUrl[commaRange.upperBound...])
            imageData = Data(base64Encoded: b64, options: .ignoreUnknownCharacters)
        }

        // 2. Remote HTTP/HTTPS URL FIRST (never touch AppleScript when CDN URL is already supplied!)
        if imageData == nil, rawUrl.hasPrefix("http://") || rawUrl.hasPrefix("https://") {
            imageData = await fetchRemotePaletteImageData(from: rawUrl)
        }

        // 3. Relative /api/artwork/search or /api/artwork/track URL -> check memory/disk/MusicKit CDN BEFORE AppleScript
        if imageData == nil, rawUrl.hasPrefix("/api/artwork") {
            if let comps = URLComponents(string: "http://localhost\(rawUrl)") {
                let items = comps.queryItems ?? []
                let qId = items.first(where: { $0.name == "id" })?.value.flatMap(Int.init) ?? tid
                let qName = items.first(where: { $0.name == "name" })?.value ?? ""
                let qArtist = items.first(where: { $0.name == "artist" })?.value ?? ""
                let qAlbum = items.first(where: { $0.name == "album" })?.value ?? ""

                if qId > 0 {
                    imageData = getCachedTrackArtwork(id: qId) ?? ArtworkDiskCache.shared.get(key: "track_\(qId)")
                }
                if imageData == nil && !qName.isEmpty {
                    var cdnUrl = MusicKitManager.shared.getCachedTrackArtwork(name: qName, artist: qArtist, album: qAlbum)
                    if (cdnUrl ?? "").isEmpty {
                        cdnUrl = await MusicKitManager.shared.searchTrackArtwork(name: qName, artist: qArtist, album: qAlbum)
                    }
                    if let validCdn = cdnUrl, !validCdn.isEmpty {
                        imageData = await fetchRemotePaletteImageData(from: validCdn)
                    }
                }
            }
        }

        // 4. Local track ID (offloaded to background queue so Swift's cooperative pool never blocks on IPC)
        if imageData == nil, tid > 0, !rawUrl.hasPrefix("http://"), !rawUrl.hasPrefix("https://"), !isKnownMissingTrackArtwork(id: tid) {
            imageData = await withCheckedContinuation { continuation in
                artworkFetchQueue.async { [weak self] in
                    continuation.resume(returning: self?.getTrackArtwork(id: tid))
                }
            }
        }

        // 5. Fallback to current playing local track artwork only when no URL was provided
        if imageData == nil && rawUrl.isEmpty {
            imageData = await withCheckedContinuation { continuation in
                artworkFetchQueue.async { [weak self] in
                    continuation.resume(returning: self?.getCurrentTrackArtwork())
                }
            }
        }

        guard let finalData = imageData else {
            return nil
        }

        // Run Vision ANE saliency on dedicated serial queue without blocking Swift's 8-thread cooperative pool
        let palette: [String: Any]? = await withCheckedContinuation { continuation in
            visionQueue.async { [weak self] in
                let extracted = self?.extractVisionSaliencyPalette(from: finalData, useNeuralSaliency: aiEnabled)
                continuation.resume(returning: extracted)
            }
        }

        guard let palette else { return nil }

        lock.withLock {
            if paletteCache.count > 120 {
                paletteCache.removeAll()
            }
            paletteCache[cacheKey] = palette
        }

        return palette
    }
}
