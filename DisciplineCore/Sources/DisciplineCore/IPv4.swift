import Foundation

/// A plain IPv4 address held as a big-endian 32-bit value.
public struct IPv4Address: Hashable, Comparable, CustomStringConvertible, Sendable {
    public let value: UInt32

    public init(_ value: UInt32) { self.value = value }

    /// Parses dotted-quad text such as "10.7.0.1". Returns nil on anything else.
    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var v: UInt32 = 0
        for p in parts {
            guard !p.isEmpty, p.count <= 3, p.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let octet = UInt32(p), octet <= 255 else { return nil }
            v = (v << 8) | octet
        }
        self.value = v
    }

    public var octets: [UInt8] {
        [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
         UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
    }

    public var description: String { octets.map(String.init).joined(separator: ".") }

    public static func < (a: IPv4Address, b: IPv4Address) -> Bool { a.value < b.value }
}

/// An IPv4 network written as address/prefix, e.g. "192.168.1.23/24".
public struct IPv4CIDR: Hashable, CustomStringConvertible, Sendable {
    public let address: IPv4Address
    public let prefix: Int

    public init?(address: IPv4Address, prefix: Int) {
        guard (0...32).contains(prefix) else { return nil }
        self.address = address
        self.prefix = prefix
    }

    /// Parses "a.b.c.d/n". A bare address takes `defaultPrefix`.
    public init?(_ text: String, defaultPrefix: Int = 32) {
        let pieces = text.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count == 1 || pieces.count == 2, let addr = IPv4Address(String(pieces[0])) else { return nil }
        var prefix = defaultPrefix
        if pieces.count == 2 {
            guard let p = Int(pieces[1]) else { return nil }
            prefix = p
        }
        self.init(address: addr, prefix: prefix)
    }

    /// Builds a CIDR from an address and a dotted netmask ("255.255.255.0").
    /// Returns nil when the mask is not contiguous.
    public init?(address: IPv4Address, netmask: IPv4Address) {
        let m = netmask.value
        let prefix = m.nonzeroBitCount
        let expected: UInt32 = prefix == 0 ? 0 : UInt32.max << (32 - prefix)
        guard m == expected else { return nil }
        self.init(address: address, prefix: prefix)
    }

    public var mask: UInt32 { prefix == 0 ? 0 : UInt32.max << (32 - prefix) }
    public var netmask: IPv4Address { IPv4Address(mask) }
    public var network: IPv4Address { IPv4Address(address.value & mask) }
    public var broadcast: IPv4Address { IPv4Address(network.value | ~mask) }

    public func contains(_ ip: IPv4Address) -> Bool { (ip.value & mask) == network.value }

    /// Number of usable host addresses (excludes network and broadcast for prefixes < 31).
    public var usableHostCount: UInt64 {
        let total = UInt64(1) << UInt64(32 - prefix)
        return prefix >= 31 ? total : total - 2
    }

    public var description: String { "\(address)/\(prefix)" }
}
