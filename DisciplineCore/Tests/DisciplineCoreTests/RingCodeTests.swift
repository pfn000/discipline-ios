import XCTest
@testable import DisciplineCore

final class RingCodeTests: XCTestCase {
    let message: [UInt8] = (0..<89).map { UInt8(($0 * 37 + 11) & 0xFF) }

    func testCRCAndWhiteningRoundTrip() {
        for f in RingCode.frames(for: message) {
            XCTAssertEqual(RingCode.frame(fromBytes: RingCode.bytes(of: f)), f)
            XCTAssertEqual(RingCode.bytes(fromBits: RingCode.bits(of: f)), RingCode.bytes(of: f))
        }
        XCTAssertEqual(RingCode.frames(for: message).count, 7)
    }

    func testCorruptedFrameIsRefused() {
        var b = RingCode.bytes(of: RingCode.frames(for: message)[2])
        b[5] ^= 0x10
        XCTAssertNil(RingCode.frame(fromBytes: b))
    }

    func testRenderedFrameReadsBack() {
        let f = RingCode.frames(for: message)[0]
        XCTAssertEqual(RingReader.read(RingRenderer.render(f, size: 360)), f)
    }

    func testEveryRingAtItsOwnRotation() {
        let frames = RingCode.frames(for: message)
        let rotations: [[Double]] = [[0.3, -1.1, 2.0, 4.4], [1.0, 1.0, 1.0, 1.0], [3.1, 0.05, -2.7, 5.9], [-0.5, 2.2, 0.9, -3.3]]
        for (n, angles) in rotations.enumerated() {
            for f in frames {
                let img = RingRenderer.render(f, size: 320, angles: angles)
                XCTAssertEqual(RingReader.read(img), f, "rotation set \(n), frame \(f.index)")
            }
        }
    }

    func testNoisySmallOffCentreFrames() {
        let frames = RingCode.frames(for: message)
        var ok = 0
        for (i, f) in frames.enumerated() {
            var img = RingRenderer.render(f, size: 300, angles: [Double(i), -Double(i) * 0.7, 0.4, Double(i) * 1.9],
                                          scale: 0.72, center: (140, 160))
            RingRenderer.addNoise(&img, salt: 0.02, amplitude: 40, seed: UInt64(1000 + i))
            if RingReader.read(img) == f { ok += 1 }
        }
        XCTAssertEqual(ok, frames.count, "every noisy frame should still read")
    }

    func testMirroredImageStillReads() {
        let f = RingCode.frames(for: message)[3]
        let img = RingRenderer.render(f, size: 320, angles: [0.2, 1.3, -0.8, 2.5])
        var m = img
        for y in 0..<img.height { for x in 0..<img.width { m.pixels[y * img.width + x] = img.at(img.width - 1 - x, y) } }
        XCTAssertEqual(RingReader.read(m), f)
    }

    func testBlankOrRandomImagesGiveNothing() {
        XCTAssertNil(RingReader.read(GrayImage(width: 200, height: 200, fill: 0)))
        var noise = GrayImage(width: 200, height: 200, fill: 128)
        RingRenderer.addNoise(&noise, salt: 0.3, amplitude: 120, seed: 7)
        XCTAssertNil(RingReader.read(noise))
    }

    func testDanceStitchesInAnyOrder() {
        var a = RingCode.Assembler()
        let frames = RingCode.frames(for: message)
        for f in frames.reversed() + frames { a.add(f) }   // repeats are ignored
        XCTAssertTrue(a.isComplete)
        XCTAssertEqual(Array(a.message!.prefix(89)), message)
    }

    func testChoreographyIsPerKeyAndStable() {
        let k1 = [UInt8](repeating: 1, count: 32), k2 = [UInt8](repeating: 2, count: 32)
        XCTAssertEqual(RingCode.choreography(forKey: k1), RingCode.choreography(forKey: k1))
        XCTAssertNotEqual(RingCode.choreography(forKey: k1), RingCode.choreography(forKey: k2))
        XCTAssertTrue(RingCode.choreography(forKey: k1).allSatisfy { abs($0) >= 0.04 && abs($0) <= 0.14 })
    }

    func testLoginParseAndChecksThatNeedNoCrypto() {
        let session = [UInt8](repeating: 0xAB, count: 16)
        let key = [UInt8](repeating: 9, count: 32)
        let m = RingLogin(session: session, issuedAt: 1_800_000_000, keyID: RingCode.fnv1a(key), signature: [UInt8](repeating: 0, count: 64))
        XCTAssertEqual(m.bytes.count, RingLogin.length)
        XCTAssertEqual(RingLogin.parse(m.bytes), m)
        XCTAssertEqual(RingLogin.verify(m.bytes, session: session, enrolled: [[UInt8](repeating: 3, count: 32)]), .unknownKey)
        XCTAssertEqual(RingLogin.verify(m.bytes, session: session, enrolled: [key]), .badSignature)
        XCTAssertEqual(RingLogin.verify([1, 2, 3], session: session, enrolled: [key]), .unreadable)
        XCTAssertEqual(RingLogin.parseKey(RingLogin.keyText(key)), key)
        XCTAssertNil(RingLogin.parseKey("NCOMKEY1.abc"))
        XCTAssertEqual(RingLogin.unhex(RingLogin.hex(session)), session)
    }

    func testPGMParses() {
        let d = Data("P5\n# c\n2 2\n255\n".utf8) + Data([0, 50, 100, 255])
        let g = GrayImage(pgm: d)
        XCTAssertEqual(g?.width, 2); XCTAssertEqual(g?.pixels, [0, 50, 100, 255])
    }
}
