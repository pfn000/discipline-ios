import Foundation

/// The readable part of an Apple provisioning profile (`embedded.mobileprovision`): a signed CMS
/// envelope around an XML property list. Plume Impactor, SideStore and Xcode put one inside every
/// app they sign. Discipline reads only the property list (it does not check Apple's signature)
/// to learn when the signature runs out, so nobody has to type a date.
public struct ProvisioningProfile: Equatable, Sendable {
    public let name: String?
    public let teamName: String?
    public let appIDName: String?
    public let creationDate: Date?
    public let expirationDate: Date
    public let deviceCount: Int

    public enum ParseError: Error, Equatable, Sendable { case noPropertyList, unreadable, noExpirationDate }

    public init(name: String?, teamName: String?, appIDName: String?, creationDate: Date?, expirationDate: Date, deviceCount: Int) {
        self.name = name; self.teamName = teamName; self.appIDName = appIDName
        self.creationDate = creationDate; self.expirationDate = expirationDate; self.deviceCount = deviceCount
    }

    /// Free Apple ID profiles last 7 days; paid ones up to a year. Unknown creation date: judged by
    /// how far the expiry is from `now`.
    public func tier(now: Date = Date()) -> AccountTier {
        let start = creationDate ?? now
        return expirationDate.timeIntervalSince(start) <= 8 * 86_400 ? .free : .paid
    }

    public static func parse(_ bytes: [UInt8]) throws -> ProvisioningProfile {
        let open = Array("<?xml".utf8), close = Array("</plist>".utf8)
        guard let s = find(open, in: bytes, from: 0), let e = find(close, in: bytes, from: s) else {
            throw ParseError.noPropertyList
        }
        let slice = Data(bytes[s..<(e + close.count)])
        guard let obj = try? PropertyListSerialization.propertyList(from: slice, options: [], format: nil),
              let dict = obj as? [String: Any] else { throw ParseError.unreadable }
        guard let expiry = dict["ExpirationDate"] as? Date else { throw ParseError.noExpirationDate }
        return ProvisioningProfile(name: dict["Name"] as? String,
                                   teamName: dict["TeamName"] as? String,
                                   appIDName: dict["AppIDName"] as? String,
                                   creationDate: dict["CreationDate"] as? Date,
                                   expirationDate: expiry,
                                   deviceCount: (dict["ProvisionedDevices"] as? [Any])?.count ?? 0)
    }

    static func find(_ needle: [UInt8], in hay: [UInt8], from start: Int) -> Int? {
        guard !needle.isEmpty, hay.count >= needle.count, start <= hay.count - needle.count else { return nil }
        var i = start
        let last = hay.count - needle.count
        while i <= last {
            if hay[i] == needle[0] {
                var j = 1
                while j < needle.count && hay[i + j] == needle[j] { j += 1 }
                if j == needle.count { return i }
            }
            i += 1
        }
        return nil
    }
}

public extension IPAReader {
    /// The provisioning profile inside a signed .ipa (`Payload/<App>.app/embedded.mobileprovision`),
    /// or nil for an unsigned .ipa.
    static func provisioningProfile(bytes: [UInt8]) throws -> ProvisioningProfile? {
        let zip = try ZipArchive(bytes: bytes)
        guard let entry = zip.entries.first(where: { e in
            let parts = e.path.split(separator: "/")
            return parts.count == 3 && parts[0] == "Payload" && parts[1].hasSuffix(".app") && parts[2] == "embedded.mobileprovision"
        }) else { return nil }
        return try ProvisioningProfile.parse(zip.data(for: entry))
    }
}
