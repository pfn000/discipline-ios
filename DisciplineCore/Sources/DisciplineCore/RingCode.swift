import Foundation

/// NCOM magic-ring code: a circular code the Ouija host page on a computer animates and the phone's
/// camera reads (an Apple-Watch-pairing-style handshake, but an open, documented design).
///
/// Geometry (R = outer radius of the code; everything is bright on a dark background):
/// - a solid hub disc (r <= 0.12 R) and a solid finder circle (0.92 R ... 0.98 R) give centre and scale;
/// - 4 data rings, each with 32 cells around it (a bright cell = 1). Ring i's cells sit at radius
///   `dataRadius[i]` +/- 0.04 R; ring i spins on its own;
/// - just outside each data ring, one bright index tick marks where that ring's cell 0 is,
///   so every ring can be read whatever angle it has spun to. The tick also turns with its ring.
///
/// One frame = 16 bytes = 128 bits (ring 0 holds bits 0...31, MSB first):
///   byte 0 = frame index (high nibble) and frame count - 1 (low nibble), bytes 1...14 = data,
///   byte 15 = CRC-8 (poly 0x07) of bytes 0...14. Bytes 0...14 are XOR-whitened so rings never sit blank.
/// A message longer than 14 bytes is split into up to 16 frames that the page shows one after
/// another (the "dance"); the reader keeps every frame whose CRC checks and stitches them back.
public enum RingCode {
    public static let rings = 4
    public static let cellsPerRing = 32
    public static let frameBytes = 16
    public static let dataBytesPerFrame = 14
    public static let maxFrames = 16

    public static let hubRadius = 0.12
    public static let finderInner = 0.92
    public static let finderOuter = 0.98
    public static let dataRadius: [Double] = [0.28, 0.45, 0.62, 0.79]
    public static let dataHalfWidth = 0.04
    public static let tickOffset = 0.08
    public static let tickHalfWidth = 0.025

    /// Fixed whitening pattern (xorshift32 from 0x4E434F4D, "NCOM"); the JS page uses the same.
    public static let whitening: [UInt8] = {
        var x: UInt32 = 0x4E43_4F4D
        var out: [UInt8] = []
        for _ in 0..<15 {
            x ^= x << 13; x ^= x >> 17; x ^= x << 5
            out.append(UInt8(truncatingIfNeeded: x))
        }
        return out
    }()

    public static func crc8(_ bytes: ArraySlice<UInt8>) -> UInt8 {
        var c: UInt8 = 0
        for b in bytes {
            c ^= b
            for _ in 0..<8 { c = (c & 0x80) != 0 ? (c << 1) ^ 0x07 : c << 1 }
        }
        return c
    }

    public struct Frame: Equatable, Sendable {
        public let index: Int
        public let count: Int
        public let data: [UInt8]   // 14 bytes
        public init(index: Int, count: Int, data: [UInt8]) {
            self.index = index; self.count = count; self.data = data
        }
    }

    // MARK: Frames <-> bits

    public static func frames(for message: [UInt8]) -> [Frame] {
        let n = max(1, (message.count + dataBytesPerFrame - 1) / dataBytesPerFrame)
        precondition(n <= maxFrames, "message too long for a ring code")
        return (0..<n).map { i in
            var chunk = Array(message.dropFirst(i * dataBytesPerFrame).prefix(dataBytesPerFrame))
            chunk += [UInt8](repeating: 0, count: dataBytesPerFrame - chunk.count)
            return Frame(index: i, count: n, data: chunk)
        }
    }

    /// The 16 on-air bytes of a frame (whitened, with CRC).
    public static func bytes(of frame: Frame) -> [UInt8] {
        var raw = [UInt8((frame.index << 4) | (frame.count - 1))] + frame.data
        raw = zip(raw, whitening).map { $0 ^ $1 }
        return raw + [crc8(raw[...])]
    }

    public static func frame(fromBytes b: [UInt8]) -> Frame? {
        guard b.count == frameBytes, crc8(b[0..<15]) == b[15] else { return nil }
        let raw = zip(b[0..<15], whitening).map { $0 ^ $1 }
        let index = Int(raw[0] >> 4), count = Int(raw[0] & 0x0F) + 1
        guard index < count else { return nil }
        return Frame(index: index, count: count, data: Array(raw[1...]))
    }

    /// bits[ring][cell]
    public static func bits(of frame: Frame) -> [[Bool]] {
        let b = bytes(of: frame)
        return (0..<rings).map { r in
            (0..<cellsPerRing).map { c in
                let bit = r * cellsPerRing + c
                return (b[bit / 8] >> (7 - UInt8(bit % 8))) & 1 == 1
            }
        }
    }

    public static func bytes(fromBits bits: [[Bool]]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: frameBytes)
        for r in 0..<rings { for c in 0..<cellsPerRing where bits[r][c] {
            let bit = r * cellsPerRing + c
            out[bit / 8] |= 1 << (7 - UInt8(bit % 8))
        } }
        return out
    }

    // MARK: Stitching the dance back together

    public struct Assembler: Sendable {
        public private(set) var count: Int?
        public private(set) var parts: [Int: [UInt8]] = [:]
        public init() {}
        /// Returns true when the frame was new.
        @discardableResult public mutating func add(_ f: Frame) -> Bool {
            if let c = count, c != f.count { parts = [:] }   // a different message started: start over
            count = f.count
            if parts[f.index] != nil { return false }
            parts[f.index] = f.data
            return true
        }
        public var isComplete: Bool { count.map { parts.count == $0 } ?? false }
        public var message: [UInt8]? {
            guard let c = count, isComplete else { return nil }
            return (0..<c).flatMap { parts[$0]! }
        }
    }

    // MARK: The dance (choreography)

    /// Each enrolled key gives its rings their own spin: direction and speed (turns per second)
    /// for each ring, from FNV-1a of the key. The page and the phone compute the same thing.
    public static func choreography(forKey key: [UInt8]) -> [Double] {
        let h = fnv1a(key)
        return (0..<rings).map { i in
            let nib = Double((h >> (UInt32(i) * 8)) & 0xFF) / 255.0
            let dir: Double = (h >> (UInt32(i) + 28)) & 1 == 1 ? 1 : -1
            return dir * (0.04 + 0.10 * nib)
        }
    }

    public static func fnv1a(_ bytes: [UInt8]) -> UInt32 {
        var h: UInt32 = 0x811C_9DC5
        for b in bytes { h ^= UInt32(b); h = h &* 0x0100_0193 }
        return h
    }
}

// MARK: - A grayscale image, the renderer (for tests and previews) and the reader

public struct GrayImage: Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]
    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width; self.height = height; self.pixels = pixels
    }
    public init(width: Int, height: Int, fill: UInt8 = 0) {
        self.init(width: width, height: height, pixels: [UInt8](repeating: fill, count: width * height))
    }
    @inline(__always) public func at(_ x: Int, _ y: Int) -> UInt8 {
        guard x >= 0, y >= 0, x < width, y < height else { return 0 }
        return pixels[y * width + x]
    }

    /// Parses a binary PGM (P5, 8-bit).
    public init?(pgm data: Data) {
        let bytes = [UInt8](data)
        var i = 0
        func token() -> String? {
            while i < bytes.count {
                if bytes[i] == UInt8(ascii: "#") { while i < bytes.count && bytes[i] != 10 { i += 1 } }
                else if bytes[i] == 32 || bytes[i] == 10 || bytes[i] == 13 || bytes[i] == 9 { i += 1 }
                else { break }
            }
            let s = i
            while i < bytes.count, !(bytes[i] == 32 || bytes[i] == 10 || bytes[i] == 13 || bytes[i] == 9) { i += 1 }
            return s < i ? String(decoding: bytes[s..<i], as: UTF8.self) : nil
        }
        guard token() == "P5", let w = token().flatMap(Int.init), let h = token().flatMap(Int.init),
              let mx = token().flatMap(Int.init), mx <= 255 else { return nil }
        i += 1
        guard bytes.count - i >= w * h else { return nil }
        self.init(width: w, height: h, pixels: Array(bytes[i..<(i + w * h)]))
    }
}

public enum RingRenderer {
    /// Draws one frame. `angles[i]` is ring i's rotation in radians (clockwise on screen).
    public static func render(_ frame: RingCode.Frame, size: Int, angles: [Double] = [0, 0, 0, 0],
                              scale: Double = 0.9, center: (Double, Double)? = nil) -> GrayImage {
        let bits = RingCode.bits(of: frame)
        var img = GrayImage(width: size, height: size)
        let cx = center?.0 ?? Double(size) / 2, cy = center?.1 ?? Double(size) / 2
        let R = Double(size) / 2 * scale
        let cell = 2 * Double.pi / Double(RingCode.cellsPerRing)
        for y in 0..<size { for x in 0..<size {
            let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
            let r = (dx * dx + dy * dy).squareRoot() / R
            var on = r <= RingCode.hubRadius || (r >= RingCode.finderInner && r <= RingCode.finderOuter)
            if !on {
                let theta = atan2(dy, dx)
                for i in 0..<RingCode.rings {
                    let a = theta - angles[i]
                    var pos = (a / cell).truncatingRemainder(dividingBy: Double(RingCode.cellsPerRing))
                    if pos < 0 { pos += Double(RingCode.cellsPerRing) }
                    let k = Int((pos + 0.5).rounded(.down)) % RingCode.cellsPerRing
                    let frac = abs(pos - (pos + 0.5).rounded(.down))   // distance from the cell centre, in cells
                    if abs(r - RingCode.dataRadius[i]) <= RingCode.dataHalfWidth, frac <= 0.40, bits[i][k] { on = true; break }
                    if abs(r - RingCode.dataRadius[i] - RingCode.tickOffset) <= RingCode.tickHalfWidth, k == 0, frac <= 0.45 { on = true; break }
                }
            }
            if on { img.pixels[y * size + x] = 235 } else { img.pixels[y * size + x] = 20 }
        } }
        return img
    }

    /// Adds salt-and-pepper and uniform noise (deterministic for a seed).
    public static func addNoise(_ img: inout GrayImage, salt: Double, amplitude: Int, seed: UInt64) {
        var s = seed | 1
        func next() -> UInt64 { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s }
        for i in 0..<img.pixels.count {
            let r = next()
            if Double(r % 10_000) / 10_000 < salt { img.pixels[i] = (r >> 20) & 1 == 1 ? 255 : 0; continue }
            let n = Int((r >> 32) % UInt64(2 * amplitude + 1)) - amplitude
            img.pixels[i] = UInt8(clamping: Int(img.pixels[i]) + n)
        }
    }
}

public enum RingReader {
    public struct Located: Equatable, Sendable {
        public let cx: Double, cy: Double, radius: Double
    }

    static func otsu(_ img: GrayImage) -> Int {
        var hist = [Int](repeating: 0, count: 256)
        for p in img.pixels { hist[Int(p)] += 1 }
        let total = Double(img.pixels.count)
        var sum = 0.0
        for t in 0..<256 { sum += Double(t * hist[t]) }
        var sumB = 0.0, wB = 0.0, best = 0.0, threshold = 128
        for t in 0..<256 {
            wB += Double(hist[t]); if wB == 0 { continue }
            let wF = total - wB; if wF == 0 { break }
            sumB += Double(t * hist[t])
            let mB = sumB / wB, mF = (sum - sumB) / wF
            let between = wB * wF * (mB - mF) * (mB - mF)
            if between > best { best = between; threshold = t }
        }
        return threshold
    }

    /// Finds the code: binarise, clean with a 3x3 majority filter, then the extent of what is left.
    public static func locate(_ img: GrayImage, threshold: Int) -> Located? {
        let w = img.width, h = img.height
        var bin = [Bool](repeating: false, count: w * h)
        for i in 0..<bin.count { bin[i] = Int(img.pixels[i]) > threshold }
        var cols = [Int](repeating: 0, count: w), rows = [Int](repeating: 0, count: h)
        for y in 1..<(h - 1) { for x in 1..<(w - 1) {
            var n = 0
            for dy in -1...1 { for dx in -1...1 where bin[(y + dy) * w + x + dx] { n += 1 } }
            if n >= 5 { cols[x] += 1; rows[y] += 1 }
        } }
        let minCount = 2
        guard let x0 = cols.firstIndex(where: { $0 >= minCount }), let x1 = cols.lastIndex(where: { $0 >= minCount }),
              let y0 = rows.firstIndex(where: { $0 >= minCount }), let y1 = rows.lastIndex(where: { $0 >= minCount }) else { return nil }
        let rw = Double(x1 - x0 + 1) / 2, rh = Double(y1 - y0 + 1) / 2
        guard rw > 20, rh > 20, max(rw, rh) / min(rw, rh) < 1.25 else { return nil }
        return Located(cx: Double(x0 + x1 + 1) / 2, cy: Double(y0 + y1 + 1) / 2, radius: (rw + rh) / 2 / RingCode.finderOuter)
    }

    static func sample(_ img: GrayImage, _ loc: Located, r: Double, theta: Double) -> Double {
        let x = loc.cx + cos(theta) * r * loc.radius, y = loc.cy + sin(theta) * r * loc.radius
        let xi = Int(x.rounded(.down)), yi = Int(y.rounded(.down))
        return Double(img.at(xi, yi))
    }

    static func median(_ v: [Double]) -> Double { let s = v.sorted(); return s[s.count / 2] }

    /// Reads one frame from an image. Tries both reading directions (a mirrored camera reads backwards).
    public static func read(_ img: GrayImage) -> RingCode.Frame? {
        guard let loc = locate(img, threshold: otsu(img)) else { return nil }
        // Local levels: the hub is always bright, the gap between hub and ring 0 always dark.
        var hub: [Double] = [], gap: [Double] = []
        for s in 0..<64 {
            let th = Double(s) / 64 * 2 * .pi
            hub.append(sample(img, loc, r: 0.06, theta: th))
            gap.append(sample(img, loc, r: 0.185, theta: th))
        }
        let bright = median(hub), dark = median(gap)
        guard bright - dark > 40 else { return nil }
        let thr = (bright + dark) / 2
        let steps = 720
        let cell = 2 * Double.pi / Double(RingCode.cellsPerRing)
        var starts: [Double] = []
        for i in 0..<RingCode.rings {
            let rt = RingCode.dataRadius[i] + RingCode.tickOffset
            var on = [Bool](repeating: false, count: steps)
            for s in 0..<steps {
                let th = Double(s) / Double(steps) * 2 * .pi
                on[s] = median([-0.012, 0.0, 0.012].map { sample(img, loc, r: rt + $0, theta: th) }) > thr
            }
            // The longest bright run (circular) is the tick; one-sample gaps (noise) are bridged.
            for s in 0..<steps where !on[s] && on[(s + steps - 1) % steps] && on[(s + 1) % steps] { on[s] = true }
            guard on.contains(false), on.contains(true) else { return nil }
            var bestLen = 0, bestStart = 0
            let firstOff = on.firstIndex(of: false)!
            var run = 0, runStart = 0
            for k in 1...steps {
                let idx = (firstOff + k) % steps
                if on[idx] { if run == 0 { runStart = idx }; run += 1; if run > bestLen { bestLen = run; bestStart = runStart } }
                else { run = 0 }
            }
            // A tick is about one cell wide (20 samples of 720); refuse runs that are far off.
            guard bestLen >= 8, bestLen <= 36 else { return nil }
            starts.append((Double(bestStart) + Double(bestLen - 1) / 2) / Double(steps) * 2 * .pi)
        }
        for dir in [1.0, -1.0] {
            var bits: [[Bool]] = []
            for i in 0..<RingCode.rings {
                var row: [Bool] = []
                for k in 0..<RingCode.cellsPerRing {
                    let th = starts[i] + dir * Double(k) * cell
                    var v: [Double] = []
                    for dr in [-0.015, 0.0, 0.015] { for da in [-0.08, 0.0, 0.08] {
                        v.append(sample(img, loc, r: RingCode.dataRadius[i] + dr, theta: th + da * cell))
                    } }
                    row.append(median(v) > thr)
                }
                bits.append(row)
            }
            if let f = RingCode.frame(fromBytes: RingCode.bytes(fromBits: bits)) { return f }
        }
        return nil
    }
}
