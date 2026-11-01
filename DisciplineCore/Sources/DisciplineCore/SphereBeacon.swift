import Foundation

// Ouija v0.4: how a camera could read a moving dot sphere off a screen (Saidie, Nov 1 2026, 3:55 PM: "the website
// has the QR code and the phone scans the spinning dots"; 3:56 PM: smart glasses can scan the phone the same way).
//
// The design: the sphere's flashes carry a one-time token. On each beat the screen lights a chosen set of the 26
// dots (the swell/flash beats of the dance); the scanner tracks the 26 dots (they sit on cube places, so after it
// fits the sphere's orientation each flash maps to a dot index) and reads which ones lit. A beat carries 16 bits
// (dots 0-15) plus a beat counter (dots 16-19) and a parity group (dots 20-25), so a missed or misread beat is
// caught and read again on the next cycle. A 128-bit token takes 8 beats (~2.5 s).
//
// What is real here: the encoding and decoding of the flash frames, as pure logic with tests. What is a stand-in:
// the camera step (finding the sphere, fitting its orientation, deciding lit or not per dot) is not built yet; the
// app's scan view feeds the decoder from the verifier's own frames, and says so on screen.

public struct SphereBeaconFrame: Equatable, Sendable {
    public let lit: [Bool]          // 26 dots: lit or not on this beat
    public init(lit: [Bool]) { self.lit = lit }
}

public enum SphereBeacon {
    public static let dots = 26
    static let dataBits = 16, counterBits = 4, parityBits = 6

    /// Flash frames for a token (any bytes; padded to whole beats). Frame k carries bytes 2k and 2k+1.
    public static func encode(_ token: [UInt8]) -> [SphereBeaconFrame] {
        var bytes = token; if bytes.count % 2 == 1 { bytes.append(0) }
        return stride(from: 0, to: bytes.count, by: 2).enumerated().map { k, i in
            let word = UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1])
            var lit = [Bool](repeating: false, count: dots)
            for b in 0..<dataBits { lit[b] = (word >> UInt16(15 - b)) & 1 == 1 }
            for b in 0..<counterBits { lit[dataBits + b] = (k >> (3 - b)) & 1 == 1 }
            let body = Array(lit[0..<(dataBits + counterBits)])
            for g in 0..<parityBits {
                // Parity over every sixth bit of the data + counter, offset by g.
                let ones = stride(from: g, to: body.count, by: parityBits).filter { body[$0] }.count
                lit[dataBits + counterBits + g] = ones % 2 == 1
            }
            return SphereBeaconFrame(lit: lit)
        }
    }

    /// Reads frames back into the token; nil when a frame fails its parity or a beat is missing / out of order.
    public static func decode(_ frames: [SphereBeaconFrame]) -> [UInt8]? {
        var out = [UInt8]()
        for (k, f) in frames.enumerated() {
            guard f.lit.count == dots else { return nil }
            let body = Array(f.lit[0..<(dataBits + counterBits)])
            for g in 0..<parityBits {
                let ones = stride(from: g, to: body.count, by: parityBits).filter { body[$0] }.count
                if (ones % 2 == 1) != f.lit[dataBits + counterBits + g] { return nil }
            }
            var counter = 0
            for b in 0..<counterBits where f.lit[dataBits + b] { counter |= 1 << (3 - b) }
            if counter != k % 16 { return nil }
            var word: UInt16 = 0
            for b in 0..<dataBits where f.lit[b] { word |= 1 << UInt16(15 - b) }
            out.append(UInt8(word >> 8)); out.append(UInt8(word & 0xFF))
        }
        return out
    }
}
