import XCTest
@testable import AppleMusicRemoteMac

final class AudioProcessTapServiceTests: XCTestCase {

    func testMakeWAVHeaderStructure16Bit() {
        let service = AudioProcessTapService.shared
        let header = service.makeWAVHeader(sampleRate: 44100, bitDepth: 16)

        XCTAssertEqual(header.count, 44, "Standard PCM WAV header must be exactly 44 bytes")

        let riff = String(data: header.subdata(in: 0..<4), encoding: .ascii)
        XCTAssertEqual(riff, "RIFF")

        let wave = String(data: header.subdata(in: 8..<12), encoding: .ascii)
        XCTAssertEqual(wave, "WAVE")

        let fmt = String(data: header.subdata(in: 12..<16), encoding: .ascii)
        XCTAssertEqual(fmt, "fmt ")

        let dataTag = String(data: header.subdata(in: 36..<40), encoding: .ascii)
        XCTAssertEqual(dataTag, "data")

        // Subchunk1 size should be 16 for PCM
        let subchunk1Size: UInt32 = header.subdata(in: 16..<20).withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(subchunk1Size, 16)

        // AudioFormat should be 1 (PCM)
        let format: UInt16 = header.subdata(in: 20..<22).withUnsafeBytes { $0.load(as: UInt16.self) }
        XCTAssertEqual(format, 1)

        // Channels should be 2 (Stereo)
        let channels: UInt16 = header.subdata(in: 22..<24).withUnsafeBytes { $0.load(as: UInt16.self) }
        XCTAssertEqual(channels, 2)

        // Bits per sample should be 16
        let bits: UInt16 = header.subdata(in: 34..<36).withUnsafeBytes { $0.load(as: UInt16.self) }
        XCTAssertEqual(bits, 16)

        // Block align should be channels * (bits / 8) = 2 * 2 = 4
        let blockAlign: UInt16 = header.subdata(in: 32..<34).withUnsafeBytes { $0.load(as: UInt16.self) }
        XCTAssertEqual(blockAlign, 4)

        // Byte rate should be sampleRate * blockAlign = 44100 * 4
        let byteRate: UInt32 = header.subdata(in: 28..<32).withUnsafeBytes { $0.load(as: UInt32.self) }
        let sampleRate: UInt32 = header.subdata(in: 24..<28).withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(sampleRate, 44100)
        XCTAssertEqual(byteRate, 44100 * 4)
    }

    func testMakeWAVHeaderStructure24Bit() {
        let service = AudioProcessTapService.shared
        let header = service.makeWAVHeader(sampleRate: 96000, bitDepth: 24)

        XCTAssertEqual(header.count, 44, "Standard PCM WAV header must be exactly 44 bytes")

        // Bits per sample should be 24
        let bits: UInt16 = header.subdata(in: 34..<36).withUnsafeBytes { $0.load(as: UInt16.self) }
        XCTAssertEqual(bits, 24)

        // Block align should be channels * (bits / 8) = 2 * 3 = 6
        let blockAlign: UInt16 = header.subdata(in: 32..<34).withUnsafeBytes { $0.load(as: UInt16.self) }
        XCTAssertEqual(blockAlign, 6)

        // Byte rate should be sampleRate * blockAlign = 96000 * 6
        let byteRate: UInt32 = header.subdata(in: 28..<32).withUnsafeBytes { $0.load(as: UInt32.self) }
        let sampleRate: UInt32 = header.subdata(in: 24..<28).withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(sampleRate, 96000)
        XCTAssertEqual(byteRate, 96000 * 6)
    }

    func testSubscribersManagement() {
        let service = AudioProcessTapService.shared
        let sub1 = UUID()
        let sub2 = UUID()

        service.addSubscriber(id: sub1) { _ in }
        XCTAssertTrue(service.hasSubscribers)

        service.addSubscriber(id: sub2) { _ in }
        XCTAssertTrue(service.hasSubscribers)

        service.removeSubscriber(id: sub1)
        XCTAssertTrue(service.hasSubscribers)

        service.removeSubscriber(id: sub2)
    }

    func testMakeWAVHeaderWithCustomSampleRatesAndBitDepths() {
        let service = AudioProcessTapService.shared
        for rate in [44100, 48000, 88200, 96000, 176400, 192000] {
            // Test 16-bit
            let header16 = service.makeWAVHeader(sampleRate: rate, bitDepth: 16)
            XCTAssertEqual(header16.count, 44)
            let sRate16: UInt32 = header16.subdata(in: 24..<28).withUnsafeBytes { $0.load(as: UInt32.self) }
            XCTAssertEqual(sRate16, UInt32(rate))
            let byteRate16: UInt32 = header16.subdata(in: 28..<32).withUnsafeBytes { $0.load(as: UInt32.self) }
            XCTAssertEqual(byteRate16, UInt32(rate * 4))
            let bits16: UInt16 = header16.subdata(in: 34..<36).withUnsafeBytes { $0.load(as: UInt16.self) }
            XCTAssertEqual(bits16, 16)

            // Test 24-bit
            let header24 = service.makeWAVHeader(sampleRate: rate, bitDepth: 24)
            XCTAssertEqual(header24.count, 44)
            let sRate24: UInt32 = header24.subdata(in: 24..<28).withUnsafeBytes { $0.load(as: UInt32.self) }
            XCTAssertEqual(sRate24, UInt32(rate))
            let byteRate24: UInt32 = header24.subdata(in: 28..<32).withUnsafeBytes { $0.load(as: UInt32.self) }
            XCTAssertEqual(byteRate24, UInt32(rate * 6))
            let bits24: UInt16 = header24.subdata(in: 34..<36).withUnsafeBytes { $0.load(as: UInt16.self) }
            XCTAssertEqual(bits24, 24)
        }
    }

    func testSetFormat() {
        let service = AudioProcessTapService.shared
        service.setFormat(sampleRate: 96000, bitDepth: 24)
        let header = service.makeWAVHeader(sampleRate: 96000, bitDepth: 24)
        let sRate: UInt32 = header.subdata(in: 24..<28).withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(sRate, 96000)
        let bits: UInt16 = header.subdata(in: 34..<36).withUnsafeBytes { $0.load(as: UInt16.self) }
        XCTAssertEqual(bits, 24)
    }
}
