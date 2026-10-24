//
//  AudioQualityDetectorTests.swift
//  AppleMusicRemoteMacTests
//

import XCTest
@testable import AppleMusicRemoteMac

final class AudioQualityDetectorTests: XCTestCase {

    func testDetermineAudioQualityDolbyAtmos() {
        XCTAssertEqual(AudioQualityDetector.determineAudioQuality(kind: "Dolby Atmos stream", bitRate: 768, sampleRate: 48000), "Dolby Atmos")
        XCTAssertEqual(AudioQualityDetector.determineAudioQuality(kind: "Spatial Audio", bitRate: 256, sampleRate: 44100), "Dolby Atmos")
        XCTAssertEqual(AudioQualityDetector.determineAudioQuality(kind: "Atmos Audio Track", bitRate: 0, sampleRate: 0), "Dolby Atmos")
    }

    func testDetermineAudioQualityHiResLossless() {
        // High sample rates (> 48000 Hz)
        let q96 = AudioQualityDetector.determineAudioQuality(kind: "Apple Lossless audio file", bitRate: 2304, sampleRate: 96000)
        XCTAssertTrue(q96.contains("Hi-Res Lossless"))
        XCTAssertTrue(q96.contains("96kHz"))

        let q192 = AudioQualityDetector.determineAudioQuality(kind: "ALAC", bitRate: 4608, sampleRate: 192000)
        XCTAssertTrue(q192.contains("Hi-Res Lossless"))
        XCTAssertTrue(q192.contains("192kHz"))

        let q882 = AudioQualityDetector.determineAudioQuality(kind: "FLAC", bitRate: 2116, sampleRate: 88200)
        XCTAssertTrue(q882.contains("Hi-Res Lossless"))
        XCTAssertTrue(q882.contains("88.2kHz"))
    }

    func testDetermineAudioQualityStandardLossless() {
        // Standard lossless formats at 44.1 kHz or 48 kHz
        let qAlac = AudioQualityDetector.determineAudioQuality(kind: "Apple Lossless audio file", bitRate: 900, sampleRate: 44100)
        XCTAssertTrue(qAlac.contains("Lossless"))
        XCTAssertTrue(qAlac.contains("44.1kHz"))

        let qWav = AudioQualityDetector.determineAudioQuality(kind: "WAV audio file", bitRate: 1411, sampleRate: 44100)
        XCTAssertTrue(qWav.contains("Lossless"))

        let qAiff = AudioQualityDetector.determineAudioQuality(kind: "AIFF audio file", bitRate: 1411, sampleRate: 48000)
        XCTAssertTrue(qAiff.contains("Lossless"))
        XCTAssertTrue(qAiff.contains("48kHz"))

        let qFlac = AudioQualityDetector.determineAudioQuality(kind: "FLAC audio file", bitRate: 800, sampleRate: 44100)
        XCTAssertTrue(qFlac.contains("Lossless"))

        // High bitrate without explicit lossless tag
        let qHighBitRate = AudioQualityDetector.determineAudioQuality(kind: "Audio file", bitRate: 850, sampleRate: 44100)
        XCTAssertTrue(qHighBitRate.contains("Lossless"))
    }

    func testDetermineAudioQualityLossyAACAndMP3() {
        let qAac256 = AudioQualityDetector.determineAudioQuality(kind: "AAC audio file", bitRate: 256, sampleRate: 44100)
        XCTAssertEqual(qAac256, "AAC (256 kbps)")

        let qAppleMusic = AudioQualityDetector.determineAudioQuality(kind: "Apple Music stream", bitRate: 256, sampleRate: 44100)
        XCTAssertEqual(qAppleMusic, "AAC (256 kbps)")

        let qMp3320 = AudioQualityDetector.determineAudioQuality(kind: "MPEG audio file", bitRate: 320, sampleRate: 44100)
        XCTAssertEqual(qMp3320, "MP3 (320 kbps)")

        let qMp3Kind = AudioQualityDetector.determineAudioQuality(kind: "MP3 audio", bitRate: 192, sampleRate: 44100)
        XCTAssertEqual(qMp3Kind, "MP3 (192 kbps)")
    }

    func testDetermineAudioQualityEdgeCases() {
        // Zero bitrate and empty kind
        let qEmpty = AudioQualityDetector.determineAudioQuality(kind: "", bitRate: 0, sampleRate: 0)
        XCTAssertEqual(qEmpty, "AAC (256 kbps)")

        // Unknown kind with bitrate
        let qOgg = AudioQualityDetector.determineAudioQuality(kind: "Ogg Vorbis", bitRate: 160, sampleRate: 44100)
        XCTAssertEqual(qOgg, "Ogg Vorbis (160 kbps)")

        // Kind without bitrate
        let qAacNoBitrate = AudioQualityDetector.determineAudioQuality(kind: "Purchased AAC audio file", bitRate: 0, sampleRate: 0)
        XCTAssertEqual(qAacNoBitrate, "AAC (256 kbps)")

        let qMp3NoBitrate = AudioQualityDetector.determineAudioQuality(kind: "MPEG stream", bitRate: 0, sampleRate: 0)
        XCTAssertEqual(qMp3NoBitrate, "MP3")
    }

    func testGetCurrentTrackAudioParamsGracefulFallback() {
        let detector = AudioQualityDetector.shared
        // In test environment, Music.app may not have an active track
        let params = detector.getCurrentTrackAudioParams()
        // Ensure tuple is returned without crash
        if let sr = params.sampleRate {
            XCTAssertGreaterThan(sr, 0)
            XCTAssertNotNil(params.bitDepth)
        }
    }
}
