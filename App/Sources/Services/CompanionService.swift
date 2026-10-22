import Foundation
import UIKit
import DisciplineCore

/// Talks to the companion apps through their URL schemes and reads the tunnel state from the
/// interface list. Nothing here needs a special entitlement.
@MainActor
final class CompanionService {
    /// URLs "opened" while the fake-companion test hook is on (the simulator has none of the apps).
    private(set) var recorded: [URL] = []

    func isInstalled(_ c: Companion) -> Bool {
        if TestHooks.fakeCompanions { return true }
        // Requires the scheme in LSApplicationQueriesSchemes (Info.plist).
        return UIApplication.shared.canOpenURL(c.openURL)
    }

    /// Opens a URL; returns false when nothing could handle it.
    func open(_ url: URL) async -> Bool {
        if TestHooks.fakeCompanions, let scheme = url.scheme, Companion.allCases.contains(where: { $0.scheme == scheme }) {
            recorded.append(url)
            return true
        }
        return await withCheckedContinuation { cont in
            UIApplication.shared.open(url, options: [:]) { ok in cont.resume(returning: ok) }
        }
    }

    /// Current IPv4 interface addresses via getifaddrs(3).
    nonisolated static func interfaces() -> [InterfaceAddress] {
        var result: [InterfaceAddress] = []
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return [] }
        defer { freeifaddrs(ifap) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let ifa = p.pointee
            if let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: ifa.ifa_name)
                let addr = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
                var mask: IPv4Address?
                if let m = ifa.ifa_netmask {
                    mask = IPv4Address(m.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) })
                }
                let up = (Int32(ifa.ifa_flags) & IFF_UP) != 0
                result.append(InterfaceAddress(name: name, address: IPv4Address(addr), netmask: mask, isUp: up))
            }
            ptr = ifa.ifa_next
        }
        return result
    }
}
