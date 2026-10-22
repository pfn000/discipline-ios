import Foundation

/// Reads the entitlements an app was signed with, straight from its Mach-O code signature
/// (LC_CODE_SIGNATURE → CS_SuperBlob → CSMAGIC_EMBEDDED_ENTITLEMENTS 0xfade7171), handling
/// thin and fat (universal) binaries. Also reads usage-description keys from Info.plist.
public enum EntitlementReader {
    public enum ReadError: Error, Equatable, Sendable {
        case notMachO
        case noCodeSignature
        case noEntitlements
        case malformed(String)
    }

    private static func be32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) << 24 | UInt32(b[o + 1]) << 16 | UInt32(b[o + 2]) << 8 | UInt32(b[o + 3])
    }
    private static func le32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }

    /// Returns the entitlements plist as a dictionary.
    public static func entitlements(fromMachO b: [UInt8]) throws -> [String: Any] {
        guard let xml = try entitlementsXML(fromMachO: b) else { throw ReadError.noEntitlements }
        guard let obj = try? PropertyListSerialization.propertyList(from: Data(xml), options: [], format: nil),
              let dict = obj as? [String: Any] else { throw ReadError.malformed("entitlements plist") }
        return dict
    }

    public static func entitlementsXML(fromMachO b: [UInt8]) throws -> [UInt8]? {
        guard b.count >= 32 else { throw ReadError.notMachO }
        let magicBE = be32(b, 0)
        if magicBE == 0xCAFEBABE || magicBE == 0xCAFEBABF {
            // Fat header is big-endian. Take the first arm64 slice, else the first slice.
            let n = Int(be32(b, 4))
            let is64 = magicBE == 0xCAFEBABF
            let archSize = is64 ? 32 : 20
            var chosen: (Int, Int)?
            for i in 0..<n {
                let o = 8 + i * archSize
                guard o + archSize <= b.count else { throw ReadError.malformed("fat arch") }
                let cpu = be32(b, o)
                let off: Int, size: Int
                if is64 {
                    off = Int(be32(b, o + 8)) << 32 | Int(be32(b, o + 12))
                    size = Int(be32(b, o + 16)) << 32 | Int(be32(b, o + 20))
                } else {
                    off = Int(be32(b, o + 8)); size = Int(be32(b, o + 12))
                }
                if chosen == nil || cpu == 0x0100000C { chosen = (off, size) }
                if cpu == 0x0100000C { break }
            }
            guard let (off, size) = chosen, off + size <= b.count else { throw ReadError.malformed("fat slice") }
            return try entitlementsXML(fromMachO: Array(b[off..<(off + size)]))
        }
        let magicLE = le32(b, 0)
        guard magicLE == 0xFEEDFACF || magicLE == 0xFEEDFACE else { throw ReadError.notMachO }
        let headerSize = magicLE == 0xFEEDFACF ? 32 : 28
        let ncmds = Int(le32(b, 16))
        var p = headerSize
        for _ in 0..<ncmds {
            guard p + 8 <= b.count else { throw ReadError.malformed("load command") }
            let cmd = le32(b, p), size = Int(le32(b, p + 4))
            guard size >= 8 else { throw ReadError.malformed("load command size") }
            if cmd == 0x1D { // LC_CODE_SIGNATURE
                let dataOff = Int(le32(b, p + 8)), dataSize = Int(le32(b, p + 12))
                guard dataOff + dataSize <= b.count, dataSize >= 12 else { throw ReadError.malformed("signature range") }
                return try entitlementsFromSuperBlob(Array(b[dataOff..<(dataOff + dataSize)]))
            }
            p += size
        }
        throw ReadError.noCodeSignature
    }

    /// Code signature blobs are big-endian.
    static func entitlementsFromSuperBlob(_ s: [UInt8]) throws -> [UInt8]? {
        guard be32(s, 0) == 0xFADE0CC0 else { throw ReadError.malformed("superblob magic") }
        let count = Int(be32(s, 8))
        for i in 0..<count {
            let idx = 12 + i * 8
            guard idx + 8 <= s.count else { throw ReadError.malformed("blob index") }
            let off = Int(be32(s, idx + 4))
            guard off + 8 <= s.count else { continue }
            if be32(s, off) == 0xFADE7171 {
                let len = Int(be32(s, off + 4))
                guard len >= 8, off + len <= s.count else { throw ReadError.malformed("entitlements blob") }
                return Array(s[(off + 8)..<(off + len)])
            }
        }
        return nil
    }

    /// Info.plist privacy strings an app declares (NS…UsageDescription), sorted by key.
    public static func usageDescriptions(_ info: [String: Any]) -> [(key: String, text: String)] {
        info.compactMap { k, v in
            guard k.hasSuffix("UsageDescription"), let s = v as? String else { return nil }
            return (k, s)
        }.sorted { $0.key < $1.key }
    }
}
