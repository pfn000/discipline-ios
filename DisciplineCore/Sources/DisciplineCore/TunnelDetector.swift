import Foundation

/// One network interface address, as getifaddrs(3) reports it. The app fills these in on
/// device; tests build them by hand.
public struct InterfaceAddress: Equatable, Sendable {
    public let name: String          // "utun4", "en0", ...
    public let address: IPv4Address
    public let netmask: IPv4Address?
    public let isUp: Bool

    public init(name: String, address: IPv4Address, netmask: IPv4Address?, isUp: Bool = true) {
        self.name = name; self.address = address; self.netmask = netmask; self.isUp = isUp
    }
}

public enum TunnelState: Equatable, Sendable {
    case connected(interface: String, address: IPv4Address)
    case notConnected
}

/// Detects a LocalDevVPN-style loopback tunnel without any VPN entitlement: a sandboxed app may
/// list interfaces, and LocalDevVPN puts a `utun` interface up with its configured address
/// (10.7.1.1 by default, or an address inside the Wi-Fi subnet with the iOS 26.4+ fix).
public enum TunnelDetector {
    public static let legacyRange = IPv4CIDR("10.7.0.0/16")!

    public static func wifi(in interfaces: [InterfaceAddress]) -> IPv4CIDR? {
        guard let en0 = interfaces.first(where: { $0.name == "en0" && $0.isUp }), let mask = en0.netmask else { return nil }
        return IPv4CIDR(address: en0.address, netmask: mask)
    }

    /// - Parameter expected: the interface address the user configured in LocalDevVPN, if known.
    public static func state(of interfaces: [InterfaceAddress], expected: IPv4Address? = nil) -> TunnelState {
        let wifi = wifi(in: interfaces)
        for i in interfaces where i.isUp && i.name.hasPrefix("utun") {
            if let expected, i.address == expected { return .connected(interface: i.name, address: i.address) }
            if legacyRange.contains(i.address) { return .connected(interface: i.name, address: i.address) }
            // iOS 26.4+ fix: the tunnel address sits inside the Wi-Fi subnet. This branch is a
            // heuristic (an IPv4 utun address inside the LAN); the user can pin the exact address
            // in Settings, which the `expected` check above prefers.
            if let wifi, wifi.contains(i.address), i.address != wifi.address {
                return .connected(interface: i.name, address: i.address)
            }
        }
        return .notConnected
    }
}
