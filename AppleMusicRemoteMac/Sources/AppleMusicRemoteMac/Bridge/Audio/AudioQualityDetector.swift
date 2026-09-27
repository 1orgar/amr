//
//  AudioQualityDetector.swift
//  AppleMusicRemoteMac
//
//  Analysis of audio streams: codec type, bit depth, sample rate,
//  lossless / Hi-Res identification, integration with BitPerfectLogMonitor.
//

import Foundation
import ScriptingBridge

public final class AudioQualityDetector: @unchecked Sendable {
    public static let shared = AudioQualityDetector()

    private init() {}

    /// Analyzes kind, bitrate, and sample rate to produce human-readable quality badge
    /// (e.g. "Hi-Res Lossless (ALAC 24-bit/96kHz)", "Lossless (ALAC 24-bit/48kHz)", "Dolby Atmos", "AAC (256 kbps)").
    public static func determineAudioQuality(kind: String, bitRate: Int, sampleRate: Int) -> String {
        let lKind = kind.lowercased()

        // 1. Dolby Atmos / Spatial Audio
        if lKind.contains("atmos") || lKind.contains("dolby") || lKind.contains("spatial") {
            return "Dolby Atmos"
        }

        // Real-time authoritative format from BitPerfectLogMonitor
        let activeRate = (sampleRate > 0) ? Double(sampleRate) : BitPerfectLogMonitor.shared.currentDetectedSampleRate
        let activeDepth = BitPerfectLogMonitor.shared.currentDetectedBitDepth

        // 2. Hi-Res Lossless (strictly > 48 kHz: 88.2, 96, 176.4, 192 kHz)
        if let rate = activeRate, rate > 48000.0 {
            let khz = rate / 1000.0
            let khzStr = (khz.truncatingRemainder(dividingBy: 1) == 0) ? String(format: "%.0f", khz) : String(format: "%.1f", khz)
            let depthStr = "\(activeDepth ?? 24)-bit"
            return "Hi-Res Lossless (ALAC \(depthStr)/\(khzStr)kHz)"
        }

        // 3. Lossless (ALAC, AIFF, WAV, FLAC, or bitRate >= 700 kbps)
        if lKind.contains("lossless") || lKind.contains("alac") || lKind.contains("aiff") || lKind.contains("wav") || lKind.contains("flac") || (bitRate >= 700 && !lKind.contains("aac")) {
            let khzStr: String
            if let rate = activeRate, rate > 0 {
                let khz = rate / 1000.0
                khzStr = (khz.truncatingRemainder(dividingBy: 1) == 0) ? String(format: "%.0f", khz) : String(format: "%.1f", khz)
            } else {
                khzStr = "44.1"
            }
            let depthStr = "\(activeDepth ?? (bitRate > 1000 ? 24 : 16))-bit"
            return "Lossless (ALAC \(depthStr)/\(khzStr)kHz)"
        }

        // 4. Standard AAC / MP3 / Cloud Stream
        if bitRate > 0 {
            if lKind.contains("aac") || lKind.contains("apple music") {
                return "AAC (\(bitRate) kbps)"
            } else if lKind.contains("mp3") || lKind.contains("mpeg") {
                return "MP3 (\(bitRate) kbps)"
            }
            return "\(kind.isEmpty ? "AAC" : kind) (\(bitRate) kbps)"
        } else if !kind.isEmpty {
            if lKind.contains("aac") {
                return "AAC (256 kbps)"
            } else if lKind.contains("mp3") || lKind.contains("mpeg") {
                return "MP3"
            }
            return kind
        }

        return "AAC (256 kbps)"
    }

    /// Extracts sampleRate, bitDepth, and bitRate from the currently playing track object.
    public func getCurrentTrackAudioParams() -> (sampleRate: Double?, bitDepth: Int?, bitRate: Int?) {
        guard let app = MusicAppProvider.shared.getMusicApp(), let curTrack = app.currentTrack else {
            return (nil, nil, nil)
        }
        var sampleRate: Double?
        var bitRate: Int?
        var bitDepth: Int?
        if let sr = curTrack.value(forKey: "sampleRate") as? NSNumber, sr.doubleValue > 0 {
            sampleRate = sr.doubleValue
        }
        if let br = curTrack.value(forKey: "bitRate") as? NSNumber, br.intValue > 0 {
            bitRate = br.intValue
        }
        if let sr = sampleRate {
            bitDepth = (sr > 48000.0) ? 24 : 16
        }
        return (sampleRate, bitDepth, bitRate)
    }
}
