import Foundation

/// A small, dependency-free raw DEFLATE (RFC 1951) decoder, enough to read files out of
/// .ipa archives (ZIP method 8). Written for Discipline; modelled on the classic "tinf"
/// structure (stored, fixed-Huffman and dynamic-Huffman blocks). Pure Swift so it runs on
/// iOS and in the Linux test suite alike.
public enum InflateError: Error, Equatable, Sendable {
    case unexpectedEnd
    case invalidBlockType
    case invalidStoredLength
    case invalidHuffmanTable
    case invalidSymbol
    case invalidDistance
    case outputTooLarge
}

public enum Inflate {
    private struct Huffman {
        var counts = [UInt16](repeating: 0, count: 16)
        var symbols: [UInt16]

        init(lengths: ArraySlice<UInt8>) throws {
            symbols = [UInt16](repeating: 0, count: lengths.count)
            for l in lengths { counts[Int(l)] += 1 }
            counts[0] = 0
            // Reject over-subscribed tables.
            var left = 1
            for len in 1..<16 {
                left <<= 1
                left -= Int(counts[len])
                if left < 0 { throw InflateError.invalidHuffmanTable }
            }
            // offs[len] = index of the first symbol with that code length.
            var offs = [UInt16](repeating: 0, count: 16)
            var sum: UInt16 = 0
            for i in 1..<16 { offs[i] = sum; sum += counts[i] }
            for (i, l) in lengths.enumerated() where l != 0 {
                symbols[Int(offs[Int(l)])] = UInt16(i)
                offs[Int(l)] += 1
            }
        }
    }

    private struct BitReader {
        let data: [UInt8]
        var pos: Int
        var bitBuf: UInt32 = 0
        var bitCount: Int = 0

        init(_ data: [UInt8]) { self.data = data; self.pos = 0 }

        mutating func bits(_ n: Int) throws -> Int {
            while bitCount < n {
                guard pos < data.count else { throw InflateError.unexpectedEnd }
                bitBuf |= UInt32(data[pos]) << UInt32(bitCount)
                pos += 1
                bitCount += 8
            }
            let v = Int(bitBuf & ((1 << UInt32(n)) - 1))
            bitBuf >>= UInt32(n)
            bitCount -= n
            return v
        }

        mutating func alignToByte() { bitBuf = 0; bitCount = 0 }

        mutating func decode(_ h: Huffman) throws -> Int {
            var code = 0, first = 0, index = 0
            for len in 1..<16 {
                code |= try bits(1)
                let count = Int(h.counts[len])
                if code - count < first { return Int(h.symbols[index + (code - first)]) }
                index += count
                first += count
                first <<= 1
                code <<= 1
            }
            throw InflateError.invalidSymbol
        }
    }

    private static let lengthBase: [Int] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
                                            35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
                                             3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distBase: [Int] = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
                                          257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
                                          8193, 12289, 16385, 24577]
    private static let distExtra: [Int] = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
                                           7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    private static let codeLengthOrder: [Int] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    private static let fixed: (Huffman, Huffman) = {
        var l = [UInt8](repeating: 0, count: 288)
        for i in 0..<144 { l[i] = 8 }
        for i in 144..<256 { l[i] = 9 }
        for i in 256..<280 { l[i] = 7 }
        for i in 280..<288 { l[i] = 8 }
        let d = [UInt8](repeating: 5, count: 30)
        return (try! Huffman(lengths: l[...]), try! Huffman(lengths: d[...]))
    }()

    /// Decompresses raw DEFLATE data. `limit` guards against zip bombs.
    public static func inflate(_ input: [UInt8], limit: Int = 512 * 1024 * 1024) throws -> [UInt8] {
        var r = BitReader(input)
        var out: [UInt8] = []
        out.reserveCapacity(min(limit, input.count * 4))
        var final = 0
        repeat {
            final = try r.bits(1)
            let type = try r.bits(2)
            switch type {
            case 0:
                r.alignToByte()
                guard r.pos + 4 <= input.count else { throw InflateError.unexpectedEnd }
                let len = Int(input[r.pos]) | Int(input[r.pos + 1]) << 8
                let nlen = Int(input[r.pos + 2]) | Int(input[r.pos + 3]) << 8
                guard len == (~nlen & 0xFFFF) else { throw InflateError.invalidStoredLength }
                r.pos += 4
                guard r.pos + len <= input.count else { throw InflateError.unexpectedEnd }
                guard out.count + len <= limit else { throw InflateError.outputTooLarge }
                out.append(contentsOf: input[r.pos..<(r.pos + len)])
                r.pos += len
            case 1:
                try block(&r, &out, fixed.0, fixed.1, limit)
            case 2:
                let (lit, dist) = try dynamicTables(&r)
                try block(&r, &out, lit, dist, limit)
            default:
                throw InflateError.invalidBlockType
            }
        } while final == 0
        return out
    }

    private static func dynamicTables(_ r: inout BitReader) throws -> (Huffman, Huffman) {
        let hlit = try r.bits(5) + 257
        let hdist = try r.bits(5) + 1
        let hclen = try r.bits(4) + 4
        guard hlit <= 286, hdist <= 30 else { throw InflateError.invalidHuffmanTable }
        var clLengths = [UInt8](repeating: 0, count: 19)
        for i in 0..<hclen { clLengths[codeLengthOrder[i]] = UInt8(try r.bits(3)) }
        let clTable = try Huffman(lengths: clLengths[...])
        var lengths = [UInt8](repeating: 0, count: hlit + hdist)
        var i = 0
        while i < hlit + hdist {
            let sym = try r.decode(clTable)
            switch sym {
            case 0...15:
                lengths[i] = UInt8(sym); i += 1
            case 16:
                guard i > 0 else { throw InflateError.invalidHuffmanTable }
                let prev = lengths[i - 1]
                let n = 3 + (try r.bits(2))
                guard i + n <= lengths.count else { throw InflateError.invalidHuffmanTable }
                for _ in 0..<n { lengths[i] = prev; i += 1 }
            case 17:
                let n = 3 + (try r.bits(3))
                guard i + n <= lengths.count else { throw InflateError.invalidHuffmanTable }
                i += n
            case 18:
                let n = 11 + (try r.bits(7))
                guard i + n <= lengths.count else { throw InflateError.invalidHuffmanTable }
                i += n
            default:
                throw InflateError.invalidSymbol
            }
        }
        guard lengths[256] != 0 else { throw InflateError.invalidHuffmanTable }
        return (try Huffman(lengths: lengths[0..<hlit]), try Huffman(lengths: lengths[hlit...]))
    }

    private static func block(_ r: inout BitReader, _ out: inout [UInt8], _ lit: Huffman, _ dist: Huffman, _ limit: Int) throws {
        while true {
            let sym = try r.decode(lit)
            if sym < 256 {
                guard out.count < limit else { throw InflateError.outputTooLarge }
                out.append(UInt8(sym))
            } else if sym == 256 {
                return
            } else {
                let li = sym - 257
                guard li < lengthBase.count else { throw InflateError.invalidSymbol }
                let length = lengthBase[li] + (try r.bits(lengthExtra[li]))
                let di = try r.decode(dist)
                guard di < distBase.count else { throw InflateError.invalidDistance }
                let distance = distBase[di] + (try r.bits(distExtra[di]))
                guard distance <= out.count else { throw InflateError.invalidDistance }
                guard out.count + length <= limit else { throw InflateError.outputTooLarge }
                let start = out.count - distance
                for k in 0..<length { out.append(out[start + k]) }
            }
        }
    }
}
