import Foundation

/// The loopback trick that LocalDevVPN (and before it SideStore's em_proxy) uses so an
/// iPhone can talk to its own lockdown service: every IPv4 packet that enters the tunnel
/// is sent straight back with its source and destination addresses swapped. To the
/// phone, traffic it sent to the "peer" address (10.7.0.1 by default) appears to come
/// back from that peer over a network interface.
///
/// This is an independent re-implementation of that publicly described technique
/// (https://jkcoxson.com/blog/i-made-apple-mad); no LocalDevVPN source is copied.
/// Credit: Jackson Coxson (em_proxy), Stossy11 and the SideStore team (StosVPN/LocalDevVPN).
public enum PacketReflector {
    public enum Outcome: Equatable, Sendable {
        case reflected
        case skippedNotIPv4
        case skippedTooShort
        case skippedBadHeaderLength
    }

    /// Swaps source (bytes 12..<16) and destination (16..<20) in place.
    /// The IPv4 header checksum is a ones'-complement sum of 16-bit words, which does not
    /// depend on word order, so it stays valid without being recomputed. The same holds for
    /// the TCP/UDP pseudo-header checksums, which also sum both addresses.
    @discardableResult
    public static func reflect(_ packet: inout [UInt8]) -> Outcome {
        guard packet.count >= 20 else { return .skippedTooShort }
        let version = packet[0] >> 4
        guard version == 4 else { return .skippedNotIPv4 }
        let ihlBytes = Int(packet[0] & 0x0F) * 4
        guard ihlBytes >= 20, ihlBytes <= packet.count else { return .skippedBadHeaderLength }
        for i in 0..<4 { packet.swapAt(12 + i, 16 + i) }
        return .reflected
    }

    /// Convenience for `Data`, the type NEPacketTunnelFlow hands out.
    public static func reflected(_ data: Data) -> (Data, Outcome) {
        var bytes = [UInt8](data)
        let outcome = reflect(&bytes)
        return (Data(bytes), outcome)
    }

    /// RFC 1071 IPv4 header checksum over the header bytes (checksum field included).
    /// A valid header sums to 0. Used by tests and by the tunnel's debug logging.
    public static func headerChecksum(_ header: ArraySlice<UInt8>) -> UInt16 {
        var sum: UInt32 = 0
        var i = header.startIndex
        while i + 1 < header.endIndex {
            sum &+= UInt32(header[i]) << 8 | UInt32(header[i + 1])
            i += 2
        }
        if i < header.endIndex { sum &+= UInt32(header[i]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) &+ (sum >> 16) }
        return ~UInt16(truncatingIfNeeded: sum)
    }
}
