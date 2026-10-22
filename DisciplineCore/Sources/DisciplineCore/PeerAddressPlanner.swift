import Foundation

/// Since iOS 26.4, lockdownd rejects a connection that arrives on a `utun` (VPN)
/// interface unless its source address could plausibly be on the same network as a
/// physical interface (it compares it against the Wi-Fi interface's address and netmask).
/// The community fix (described by Jackson Coxson, implemented in LocalDevVPN builds) is
/// to choose a tunnel peer address INSIDE the Wi-Fi subnet and route it as a /32 so the
/// VPN still wins for that one address.
///
/// This planner picks such an address. It is pure logic so it can be unit-tested; the
/// optional DisciplineTunnel extension applies its answer.
public struct PeerAddressPlanner: Sendable {
    public struct Plan: Equatable, Sendable {
        public let interfaceAddress: IPv4Address   // address given to the utun interface
        public let peerAddress: IPv4Address        // the fake "other computer"
        public let peerPrefix: Int                 // always 32: route only this host
        public let insideWiFiSubnet: Bool
    }

    public enum PlanError: Error, Equatable, Sendable {
        case subnetTooSmall
        case noFreeAddress
    }

    /// Classic defaults used by SideStore/LocalDevVPN before iOS 26.4.
    public static let legacyInterface = IPv4Address("10.7.1.1")!
    public static let legacyPeer = IPv4Address("10.7.0.1")!

    public init() {}

    /// - Parameters:
    ///   - wifi: the phone's Wi-Fi address and prefix (e.g. 192.168.1.23/24), or nil if not on Wi-Fi.
    ///   - taken: addresses known to be in use on the LAN (router, other devices), avoided if possible.
    ///   - iosMajor/iosMinor: the running iOS version.
    public func plan(wifi: IPv4CIDR?, taken: Set<IPv4Address> = [], iosMajor: Int, iosMinor: Int) throws -> Plan {
        let needsInSubnet = (iosMajor, iosMinor) >= (26, 4)
        guard needsInSubnet, let wifi else {
            return Plan(interfaceAddress: Self.legacyInterface, peerAddress: Self.legacyPeer, peerPrefix: 32, insideWiFiSubnet: false)
        }
        guard wifi.prefix <= 30 else { throw PlanError.subnetTooSmall }
        // Walk down from the top of the subnet (usually the least crowded end of a DHCP pool),
        // skipping broadcast, the phone itself and anything known to be taken.
        let first = wifi.network.value &+ 1
        let last = wifi.broadcast.value &- 1
        var candidate = last
        var interfaceAddr: IPv4Address?
        var peerAddr: IPv4Address?
        while candidate >= first {
            let ip = IPv4Address(candidate)
            if ip != wifi.address && !taken.contains(ip) {
                if peerAddr == nil { peerAddr = ip }
                else if interfaceAddr == nil { interfaceAddr = ip; break }
            }
            if candidate == first { break }
            candidate &-= 1
        }
        guard let peer = peerAddr else { throw PlanError.noFreeAddress }
        // The interface address may fall back to the phone's own Wi-Fi address region if the
        // subnet is tiny; it only needs to differ from the peer.
        let iface = interfaceAddr ?? Self.legacyInterface
        return Plan(interfaceAddress: iface, peerAddress: peer, peerPrefix: 32, insideWiFiSubnet: true)
    }
}
