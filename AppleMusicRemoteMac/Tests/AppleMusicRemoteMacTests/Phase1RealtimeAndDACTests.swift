import XCTest
import CoreAudio
@testable import AppleMusicRemoteMac

final class Phase1RealtimeAndDACTests: XCTestCase {

    func testSPSCAtomicRingBufferConcurrentProducerConsumerIntegrity() {
        let ring = SPSCAtomicRingBuffer(minimumCapacity: 4096)
        let totalPairs = 120_000
        let totalWords = totalPairs * 2

        let producerDone = expectation(description: "producer finished")
        let consumerDone = expectation(description: "consumer finished")

        DispatchQueue.global(qos: .userInteractive).async {
            let chunkWords = 256
            let src = UnsafeMutablePointer<Int32>.allocate(capacity: chunkWords)
            defer { src.deallocate() }

            var writtenWords = 0
            while writtenWords < totalWords {
                let remaining = min(chunkWords, totalWords - writtenWords)
                for i in stride(from: 0, to: remaining, by: 2) {
                    let frameIdx = Int32((writtenWords + i) / 2)
                    src[i] = frameIdx
                    src[i + 1] = -frameIdx
                }
                let n = ring.write(from: src, count: remaining)
                if n > 0 {
                    writtenWords += n
                } else {
                    sched_yield()
                }
            }
            producerDone.fulfill()
        }

        var mismatchCount = 0
        DispatchQueue.global(qos: .userInitiated).async {
            let view = ring.rawView
            let chunkWords = 192
            let dst = UnsafeMutablePointer<Int32>.allocate(capacity: chunkWords)
            defer { dst.deallocate() }

            var readWords = 0
            while readWords < totalWords {
                let remaining = min(chunkWords, totalWords - readWords)
                let n = view.read(into: dst, count: remaining)
                if n > 0 {
                    for i in stride(from: 0, to: n, by: 2) {
                        let expectedFrame = Int32((readWords + i) / 2)
                        if dst[i] != expectedFrame || dst[i + 1] != -expectedFrame {
                            mismatchCount += 1
                        }
                    }
                    readWords += n
                } else {
                    sched_yield()
                }
            }
            consumerDone.fulfill()
        }

        wait(for: [producerDone, consumerDone], timeout: 10.0)
        XCTAssertEqual(mismatchCount, 0, "C11 SPSC ring buffer must preserve stereo word order without tearing or data races")
        XCTAssertEqual(ring.availableToRead, 0)
    }

    func testSPSCStereoFloatRingBufferConcurrentPlanarAndWriteZeros() {
        let ring = SPSCStereoFloatRingBuffer(minimumFrameCapacity: 4096)
        let totalFrames = 80_000

        let producerDone = expectation(description: "float producer")
        let consumerDone = expectation(description: "float consumer")

        DispatchQueue.global(qos: .userInteractive).async {
            let block = 128
            let lBuf = UnsafeMutablePointer<Float>.allocate(capacity: block)
            let rBuf = UnsafeMutablePointer<Float>.allocate(capacity: block)
            defer {
                lBuf.deallocate()
                rBuf.deallocate()
            }
            var sent = 0
            while sent < totalFrames {
                let count = min(block, totalFrames - sent)
                for i in 0..<count {
                    let v = Float((sent + i) % 1024) / 1024.0
                    lBuf[i] = v
                    rBuf[i] = -v
                }
                let w = ring.writePlanar(left: lBuf, right: rBuf, frameCount: count)
                if w > 0 {
                    sent += w
                } else {
                    sched_yield()
                }
            }
            producerDone.fulfill()
        }

        var maxErr: Float = 0.0
        DispatchQueue.global(qos: .userInitiated).async {
            let block = 96
            let dstL = UnsafeMutablePointer<Float>.allocate(capacity: block)
            let dstR = UnsafeMutablePointer<Float>.allocate(capacity: block)
            defer {
                dstL.deallocate()
                dstR.deallocate()
            }
            var recv = 0
            while recv < totalFrames {
                let count = min(block, totalFrames - recv)
                let r = ring.readPlanar(intoLeft: dstL, intoRight: dstR, maxFrames: count)
                if r > 0 {
                    for i in 0..<r {
                        let expected = Float((recv + i) % 1024) / 1024.0
                        maxErr = max(maxErr, abs(dstL[i] - expected))
                        maxErr = max(maxErr, abs(dstR[i] + expected))
                    }
                    recv += r
                } else {
                    sched_yield()
                }
            }
            consumerDone.fulfill()
        }

        wait(for: [producerDone, consumerDone], timeout: 10.0)
        XCTAssertLessThanOrEqual(maxErr, 1e-6)

        // Verify writeZeros clears previously written ring slots
        XCTAssertEqual(ring.writeZeros(frameCount: 64), 64)
        var zL = [Float](repeating: 1.0, count: 64)
        var zR = [Float](repeating: -1.0, count: 64)
        let zr = ring.readPlanar(intoLeft: &zL, intoRight: &zR, maxFrames: 64)
        XCTAssertEqual(zr, 64)
        XCTAssertTrue(zL.allSatisfy { $0 == 0.0 })
        XCTAssertTrue(zR.allSatisfy { $0 == 0.0 })
    }

    func testTPDFDitherQuantizationUnbiasedSubLSBSignalAndFullScaleClamping() {
        let tap = AudioProcessTapService.shared
        let frames = 4096

        // 1. Sub-LSB constant signal (+0.25 LSB at 16-bit): truncation rounds EVERY sample to 0,
        // whereas TPDF dither recovers the +0.25 LSB mean linearly without bias or distortion!
        let quarterLSB16: Float = 0.25 / 32767.0
        var leftIn = [Float](repeating: quarterLSB16, count: frames)
        var rightIn = [Float](repeating: -quarterLSB16, count: frames)
        var outTrunc = [UInt8](repeating: 0, count: frames * 4)
        var outDither = [UInt8](repeating: 0, count: frames * 4)

        var idxTrunc = 0
        tap.quantizeScratchTileToPCMBytes(
            left: &leftIn,
            right: &rightIn,
            tileCount: frames,
            bitDepth: 16,
            dstPtr: &outTrunc,
            dstIdx: &idxTrunc,
            enableTPDFDither: false
        )
        XCTAssertTrue(outTrunc.allSatisfy { $0 == 0 }, "Undithered round() loses sub-LSB signals completely (dead-zone distortion)")

        var idxDither = 0
        tap.quantizeScratchTileToPCMBytes(
            left: &leftIn,
            right: &rightIn,
            tileCount: frames,
            bitDepth: 16,
            dstPtr: &outDither,
            dstIdx: &idxDither,
            enableTPDFDither: true
        )
        var sumL: Double = 0
        var nonZeroCount = 0
        for i in 0..<frames {
            let lo = UInt16(outDither[i * 4])
            let hi = UInt16(outDither[i * 4 + 1]) << 8
            let sample = Int16(bitPattern: lo | hi)
            if sample != 0 { nonZeroCount += 1 }
            sumL += Double(sample)
        }
        let meanLSB = sumL / Double(frames)
        XCTAssertGreaterThan(nonZeroCount, 500, "TPDF dither must toggle LSB stochastically on sub-LSB signals")
        XCTAssertEqual(meanLSB, 0.25, accuracy: 0.06, "TPDF dither must preserve exact +0.25 LSB expected value")

        // 2. Full-scale saturation check (±1.0 in 16-bit and 24-bit must NEVER wrap around)
        var peakL = [Float](repeating: 1.0, count: 512)
        var peakR = [Float](repeating: -1.0, count: 512)
        var out24 = [UInt8](repeating: 0, count: 512 * 6)
        var idx24 = 0
        tap.quantizeScratchTileToPCMBytes(
            left: &peakL,
            right: &peakR,
            tileCount: 512,
            bitDepth: 24,
            dstPtr: &out24,
            dstIdx: &idx24,
            enableTPDFDither: true
        )
        for i in 0..<512 {
            let b0 = Int32(out24[i * 6])
            let b1 = Int32(out24[i * 6 + 1]) << 8
            let b2 = Int32(Int8(bitPattern: out24[i * 6 + 2])) << 16
            let valL = b0 | b1 | b2
            XCTAssertGreaterThanOrEqual(valL, 8_388_605, "+1.0 FS 24-bit sample with TPDF dither must clamp at +8388607 and never wrap negative")
            XCTAssertLessThanOrEqual(valL, 8_388_607)
        }
    }

    func testDACEligibilityAllowsUSBAndThunderboltAndRequiresBitTransparentIntegerForDoP() {
        let hiResRates: [Double] = [44_100, 48_000, 88_200, 96_000, 176_400, 192_000, 352_800, 705_600]

        // 1. Thunderbolt external DAC with 24-bit/32-bit Signed Integer -> eligible for BOTH HQ NOS and DSD256 DoP
        let tbCaps = CoreAudioDeviceManager.evaluateDSPCapabilities(
            rawTransport: kAudioDeviceTransportTypeThunderbolt,
            name: "Universal Audio Apollo Twin X",
            uid: "tb-apollo-uid",
            availableRates: hiResRates,
            maxBitDepth: 24,
            hasStereoOutput: true,
            hasBitTransparentInteger: true
        )
        XCTAssertEqual(tbCaps.transportType, "thunderbolt")
        XCTAssertTrue(tbCaps.supportsNOS)
        XCTAssertTrue(tbCaps.supportsDSDDoP)
        XCTAssertEqual(tbCaps.maxDSDRate, 256)

        // 2. Float-only USB audio interface (no Signed Integer >= 24-bit) -> NOS allowed, DSD DoP BLOCKED
        let floatOnlyUSB = CoreAudioDeviceManager.evaluateDSPCapabilities(
            rawTransport: kAudioDeviceTransportTypeUSB,
            name: "Float-Only USB Mixer",
            uid: "usb-float-only",
            availableRates: hiResRates,
            maxBitDepth: 32,
            hasStereoOutput: true,
            hasBitTransparentInteger: false
        )
        XCTAssertTrue(floatOnlyUSB.supportsNOS)
        XCTAssertFalse(floatOnlyUSB.supportsDSDDoP, "DoP markers must be blocked on streams without >=24-bit Signed Integer")
        XCTAssertEqual(floatOnlyUSB.maxDSDRate, 0)

        // 3. Built-in MacBook Speakers even at 96 kHz / 32-bit -> strictly BLOCKED for both NOS and DSD DoP
        let builtIn = CoreAudioDeviceManager.evaluateDSPCapabilities(
            rawTransport: kAudioDeviceTransportTypeBuiltIn,
            name: "MacBook Pro Speakers",
            uid: "BuiltInSpeakerDevice",
            availableRates: hiResRates,
            maxBitDepth: 32,
            hasStereoOutput: true,
            hasBitTransparentInteger: true
        )
        XCTAssertFalse(builtIn.supportsNOS)
        XCTAssertFalse(builtIn.supportsDSDDoP)
        XCTAssertEqual(builtIn.maxDSDRate, 0)
    }

    func testPlayerStatusIsClockSyncedDspSerializationRoundTrip() throws {
        let status = PlayerStatus(
            playerState: "playing",
            audioQuality: "Lossless (ALAC 16-bit/44.1kHz)",
            isBitPerfect: false,
            isClockSyncedDsp: true,
            lateNightDrcMode: "gentle",
            lateNightDrcEnabled: true
        )
        let data = try JSONEncoder().encode(status)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["is_clock_synced_dsp"] as? Bool, true)
        XCTAssertEqual(json["is_bit_perfect"] as? Bool, false)

        let decoded = try JSONDecoder().decode(PlayerStatus.self, from: data)
        XCTAssertEqual(decoded.isClockSyncedDsp, true)
    }
}
