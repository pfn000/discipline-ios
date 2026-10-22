import Foundation

public enum IPAError: Error, Equatable, Sendable {
    case notAZip
    case noAppBundle
    case missingInfoPlist
    case unreadableInfoPlist
    case unsupportedCompression(Int)
    case encrypted
    case corrupt(String)
}

/// Reads entries out of a ZIP archive (an .ipa is a ZIP with Payload/<Name>.app/ inside)
/// using the central directory. Supports methods 0 (stored) and 8 (deflate). ZIP64 is not
/// supported (only matters for archives over 4 GB).
public struct ZipArchive: Sendable {
    public struct Entry: Equatable, Sendable {
        public let path: String
        public let method: Int
        public let compressedSize: Int
        public let uncompressedSize: Int
        public let localHeaderOffset: Int
        public let encrypted: Bool
    }

    public let bytes: [UInt8]
    public let entries: [Entry]

    public init(bytes: [UInt8]) throws {
        self.bytes = bytes
        self.entries = try Self.readCentralDirectory(bytes)
    }

    public init(contentsOf url: URL) throws {
        try self.init(bytes: [UInt8](try Data(contentsOf: url, options: .mappedIfSafe)))
    }

    private static func u16(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
    private static func u32(_ b: [UInt8], _ o: Int) -> Int {
        Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24
    }

    private static func readCentralDirectory(_ b: [UInt8]) throws -> [Entry] {
        guard b.count >= 22 else { throw IPAError.notAZip }
        // End of central directory record: signature 0x06054b50, within the last 64 KB + 22.
        var eocd = -1
        var i = b.count - 22
        let stop = max(0, b.count - 22 - 65_535)
        while i >= stop {
            if b[i] == 0x50 && b[i + 1] == 0x4b && b[i + 2] == 0x05 && b[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw IPAError.notAZip }
        let count = u16(b, eocd + 10)
        let cdSize = u32(b, eocd + 12)
        let cdOffset = u32(b, eocd + 16)
        guard cdOffset + cdSize <= b.count else { throw IPAError.corrupt("central directory out of range") }
        var entries: [Entry] = []
        var p = cdOffset
        for _ in 0..<count {
            guard p + 46 <= b.count, u32(b, p) == 0x02014b50 else { throw IPAError.corrupt("bad central header") }
            let flags = u16(b, p + 8)
            let method = u16(b, p + 10)
            let csize = u32(b, p + 20)
            let usize = u32(b, p + 24)
            let nameLen = u16(b, p + 28)
            let extraLen = u16(b, p + 30)
            let commentLen = u16(b, p + 32)
            let local = u32(b, p + 42)
            guard p + 46 + nameLen <= b.count else { throw IPAError.corrupt("name out of range") }
            let name = String(decoding: b[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            entries.append(Entry(path: name, method: method, compressedSize: csize, uncompressedSize: usize,
                                 localHeaderOffset: local, encrypted: flags & 1 != 0))
            p += 46 + nameLen + extraLen + commentLen
        }
        return entries
    }

    public func entry(_ path: String) -> Entry? { entries.first { $0.path == path } }

    public func data(for e: Entry, limit: Int = 64 * 1024 * 1024) throws -> [UInt8] {
        guard !e.encrypted else { throw IPAError.encrypted }
        let o = e.localHeaderOffset
        guard o + 30 <= bytes.count, Self.u32(bytes, o) == 0x04034b50 else { throw IPAError.corrupt("bad local header") }
        let start = o + 30 + Self.u16(bytes, o + 26) + Self.u16(bytes, o + 28)
        guard start + e.compressedSize <= bytes.count else { throw IPAError.corrupt("entry out of range") }
        let raw = Array(bytes[start..<(start + e.compressedSize)])
        switch e.method {
        case 0: return raw
        case 8: return try Inflate.inflate(raw, limit: limit)
        default: throw IPAError.unsupportedCompression(e.method)
        }
    }
}

/// What Discipline shows about an .ipa before handing it to SideStore or LiveContainer.
public struct IPAInfo: Equatable, Sendable {
    public let appFolder: String          // "Payload/Name.app/"
    public let displayName: String
    public let bundleID: String
    public let version: String
    public let build: String?
    public let minimumOS: String?
    public let iconPNG: [UInt8]?          // may be Apple's CgBI PNG variant; UIImage decodes it on iOS
    public let hasExtensions: Bool        // app extensions each need an extra App ID on a free account
    public let fileSize: Int

    /// App IDs a free account spends to sign this app directly (app + each extension).
    public let extensionCount: Int
    public var appIDCost: Int { 1 + extensionCount }
}

public enum IPAReader {
    public static func read(contentsOf url: URL) throws -> IPAInfo {
        try read(bytes: [UInt8](try Data(contentsOf: url, options: .mappedIfSafe)))
    }

    public static func read(bytes: [UInt8]) throws -> IPAInfo {
        let zip = try ZipArchive(bytes: bytes)
        // The app bundle is the first-level "Payload/<X>.app/" folder.
        var appFolder: String?
        for e in zip.entries {
            let parts = e.path.split(separator: "/", omittingEmptySubsequences: false)
            if parts.count >= 3, parts[0] == "Payload", parts[1].hasSuffix(".app") {
                appFolder = "Payload/\(parts[1])/"
                break
            }
        }
        guard let folder = appFolder else { throw IPAError.noAppBundle }
        guard let plistEntry = zip.entry(folder + "Info.plist") else { throw IPAError.missingInfoPlist }
        let plistBytes = try zip.data(for: plistEntry)
        guard let obj = try? PropertyListSerialization.propertyList(from: Data(plistBytes), options: [], format: nil),
              let dict = obj as? [String: Any] else { throw IPAError.unreadableInfoPlist }

        let bundleID = dict["CFBundleIdentifier"] as? String ?? "unknown"
        let name = (dict["CFBundleDisplayName"] as? String) ?? (dict["CFBundleName"] as? String)
            ?? String(folder.dropFirst("Payload/".count).dropLast(".app/".count))
        let version = dict["CFBundleShortVersionString"] as? String ?? "?"
        let build = dict["CFBundleVersion"] as? String
        let minOS = dict["MinimumOSVersion"] as? String

        // Extensions live in <app>/PlugIns/<X>.appex/ (and <app>/Extensions/ for ExtensionKit).
        var appexes = Set<String>()
        for e in zip.entries where e.path.hasPrefix(folder) {
            let rest = e.path.dropFirst(folder.count)
            let parts = rest.split(separator: "/")
            if parts.count >= 2, (parts[0] == "PlugIns" || parts[0] == "Extensions"), parts[1].hasSuffix(".appex") {
                appexes.insert(String(parts[1]))
            }
        }

        return IPAInfo(appFolder: folder, displayName: name, bundleID: bundleID, version: version, build: build,
                       minimumOS: minOS, iconPNG: iconBytes(zip, folder: folder, info: dict),
                       hasExtensions: !appexes.isEmpty, fileSize: bytes.count, extensionCount: appexes.count)
    }

    /// Finds the largest icon PNG the Info.plist names (CFBundleIcons → CFBundlePrimaryIcon →
    /// CFBundleIconFiles), falling back to any top-level AppIcon*.png.
    static func iconBytes(_ zip: ZipArchive, folder: String, info: [String: Any]) -> [UInt8]? {
        var names: [String] = []
        if let icons = info["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] { names += files }
        if let files = info["CFBundleIconFiles"] as? [String] { names += files }
        let pngs = zip.entries.filter { e in
            guard e.path.hasPrefix(folder), e.path.lowercased().hasSuffix(".png") else { return false }
            let file = String(e.path.dropFirst(folder.count))
            guard !file.contains("/") else { return false }
            if names.contains(where: { file.hasPrefix($0) }) { return true }
            return file.hasPrefix("AppIcon")
        }
        guard let best = pngs.max(by: { $0.uncompressedSize < $1.uncompressedSize }) else { return nil }
        return try? zip.data(for: best, limit: 4 * 1024 * 1024)
    }
}


/// What the NCOM Lab shows about an app's signing needs.
public struct IPAInspection: Sendable {
    public let entitlementKeys: [String]                 // sorted keys of the signed entitlements
    public let entitlementSummary: [(key: String, value: String)]
    public let usageDescriptions: [(key: String, text: String)]
    public let entitlementsError: String?                // why entitlements could not be read, if so

    /// Restricted entitlements this app carries that the given account cannot sign.
    public func unsignable(for tier: AccountTier) -> [String] {
        entitlementKeys.filter { key in
            guard let f = DeviceFeature.lookup(entitlement: key) else { return false }
            switch f.signability {
            case .freeOK: return false
            case .paidAccount: return tier == .free
            case .appleApprovalOnly: return true
            }
        }
    }
}

extension IPAReader {
    public static func inspect(bytes: [UInt8]) throws -> IPAInspection {
        let zip = try ZipArchive(bytes: bytes)
        let info = try read(bytes: bytes)
        guard let plistEntry = zip.entry(info.appFolder + "Info.plist"),
              let obj = try? PropertyListSerialization.propertyList(from: Data(try zip.data(for: plistEntry)), options: [], format: nil),
              let dict = obj as? [String: Any] else { throw IPAError.unreadableInfoPlist }
        let usage = EntitlementReader.usageDescriptions(dict)
        var keys: [String] = [], summary: [(String, String)] = [], err: String?
        if let exe = dict["CFBundleExecutable"] as? String, let e = zip.entry(info.appFolder + exe) {
            do {
                let ents = try EntitlementReader.entitlements(fromMachO: try zip.data(for: e, limit: 512 * 1024 * 1024))
                keys = ents.keys.sorted()
                summary = keys.map { k in (k, describe(ents[k] as Any)) }
            } catch {
                err = "\(error)"
            }
        } else {
            err = "executable not found"
        }
        return IPAInspection(entitlementKeys: keys, entitlementSummary: summary, usageDescriptions: usage, entitlementsError: err)
    }

    static func describe(_ v: Any) -> String {
        if let b = v as? Bool { return b ? "true" : "false" }
        if let s = v as? String { return s }
        if let a = v as? [Any] { return "[" + a.map { describe($0) }.joined(separator: ", ") + "]" }
        if let n = v as? NSNumber { return n.stringValue }
        return "\(v)"
    }
}
