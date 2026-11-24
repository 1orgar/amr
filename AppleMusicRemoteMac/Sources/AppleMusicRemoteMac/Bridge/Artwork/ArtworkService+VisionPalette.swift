//
//  ArtworkService+VisionPalette.swift
//  AppleMusicRemoteMac
//
//  Apple Neural Engine Vision Saliency palette extraction & SSRF-protected remote artwork fetching.
//

import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import Vision

extension ArtworkService {

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
              imageData.count <= 10 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            return nil
        }

        // Guard against decompression bombs by checking source header dimensions first
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let srcW = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
            let srcH = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
            if srcW > 16_384 || srcH > 16_384 {
                return nil
            }
        }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
                ?? CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        // Validate CGImage dimensions, bitsPerPixel, and bytesPerRow before drawing/sampling
        let minExpectedRowBytes = (cgImage.width * max(1, cgImage.bitsPerPixel) + 7) / 8
        guard cgImage.width > 0,
              cgImage.height > 0,
              cgImage.width <= 16_384,
              cgImage.height <= 16_384,
              cgImage.bitsPerComponent >= 1,
              cgImage.bitsPerPixel >= cgImage.bitsPerComponent,
              cgImage.bytesPerRow >= minExpectedRowBytes else {
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

                    let pb = observation.pixelBuffer
                    CVPixelBufferLockBaseAddress(pb, .readOnly)
                    defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

                    let pbWidth = CVPixelBufferGetWidth(pb)
                    let pbHeight = CVPixelBufferGetHeight(pb)
                    let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
                    let pixelFormat = CVPixelBufferGetPixelFormatType(pb)
                    let basePtr = CVPixelBufferGetBaseAddress(pb)
                    let floatStride = MemoryLayout<Float>.stride
                    let canReadFloatBuffer = pbWidth > 0
                        && pbHeight > 0
                        && pixelFormat == kCVPixelFormatType_OneComponent32Float
                        && bytesPerRow >= pbWidth * floatStride

                    if pbWidth > 0 && pbHeight > 0 {
                        for gy in 0..<gridSize {
                            let normX_YTop = Double(gy) / Double(gridSize - 1)
                            let visionY = 1.0 - normX_YTop
                            let py = min(pbHeight - 1, max(0, Int(visionY * Double(pbHeight - 1))))

                            for gx in 0..<gridSize {
                                let normX = Double(gx) / Double(gridSize - 1)
                                let px = min(pbWidth - 1, max(0, Int(normX * Double(pbWidth - 1))))
                                var heatVal: Float = 0.0

                                if canReadFloatBuffer, let base = basePtr,
                                   (px + 1) * floatStride <= bytesPerRow {
                                    let rowPtr = base.advanced(by: py * bytesPerRow).assumingMemoryBound(to: Float.self)
                                    let rawVal = rowPtr[px]
                                    if rawVal.isFinite {
                                        heatVal = max(0.0, min(1.0, rawVal))
                                    }
                                }

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

                let baseW = 1.0 + sal * 6.0
                fallbackR += r * baseW
                fallbackG += g * baseW
                fallbackB += b * baseW
                fallbackW += baseW

                if lum < 16.0 || lum > 246.0 { continue }

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

    static func enhanceAmbientColor(r: Double, g: Double, b: Double) -> (Int, Int, Int) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let mid = (maxC + minC) * 0.5
        let sat = maxC > 0 ? ((maxC - minC) / maxC) : 0.0
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

        let now = Date().timeIntervalSince1970
        let cachedPalette: [String: Any]? = lock.withLock {
            guard var hit = paletteCache[cacheKey] else { return nil }
            hit.accessedAt = now
            paletteCache[cacheKey] = hit
            return hit.palette
        }
        if let cachedPalette {
            return cachedPalette
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

    func fetchRemotePaletteImageData(from urlStr: String) async -> Data? {
        guard let initialUrl = URL(string: urlStr),
              Self.isAllowedRemoteArtworkURL(initialUrl) else {
            return nil
        }
        if let diskData = ArtworkDiskCache.shared.get(key: urlStr) {
            return diskData
        }
        let fetchUrlStr = urlStr
            .replacingOccurrences(of: "1200x1200bb", with: "300x300bb")
            .replacingOccurrences(of: "600x600bb", with: "300x300bb")
        if let diskSmall = ArtworkDiskCache.shared.get(key: fetchUrlStr) {
            return diskSmall
        }
        guard let remoteUrl = URL(string: fetchUrlStr),
              Self.isAllowedRemoteArtworkURL(remoteUrl) else {
            return nil
        }
        if let data = await safeArtworkFetcher.fetch(url: remoteUrl, timeout: 4.0, maxBytes: 10 * 1024 * 1024),
           !data.isEmpty {
            ArtworkDiskCache.shared.set(key: fetchUrlStr, data: data)
            return data
        }
        return nil
    }

    func computeArtworkPalette(rawUrl: String, tid: Int, aiEnabled: Bool, cacheKey: String) async -> [String: Any]? {
        var imageData: Data? = nil

        // 1. Data URI (capped at 14 MB base64 -> <= 10 MB binary)
        if rawUrl.hasPrefix("data:image/"), rawUrl.count <= 14 * 1024 * 1024, let commaRange = rawUrl.range(of: ",") {
            let b64 = String(rawUrl[commaRange.upperBound...])
            let decoded = Data(base64Encoded: b64, options: .ignoreUnknownCharacters)
            if let decoded, decoded.count <= 10 * 1024 * 1024 {
                imageData = decoded
            }
        }

        // 2. Remote HTTP/HTTPS URL FIRST (strictly validated Apple CDN, never touches AppleScript)
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

        let palette: [String: Any]? = await withCheckedContinuation { continuation in
            visionQueue.async { [weak self] in
                let extracted = self?.extractVisionSaliencyPalette(from: finalData, useNeuralSaliency: aiEnabled)
                continuation.resume(returning: extracted)
            }
        }

        guard let palette else { return nil }

        let now = Date().timeIntervalSince1970
        lock.withLock {
            if paletteCache.count >= maxPaletteCacheEntries {
                // Evict oldest half instead of wiping the entire cache at once
                let evictCount = max(1, paletteCache.count / 2)
                let oldestKeys = paletteCache
                    .sorted { $0.value.accessedAt < $1.value.accessedAt }
                    .prefix(evictCount)
                    .map(\.key)
                for key in oldestKeys {
                    paletteCache.removeValue(forKey: key)
                }
            }
            paletteCache[cacheKey] = (palette: palette, accessedAt: now)
        }

        return palette
    }
}
