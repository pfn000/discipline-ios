import Foundation

/// A parsed iOS version such as "27.2" or "26.4.1".
public struct OSVersion: Comparable, Hashable, CustomStringConvertible, Sendable {
    public let major: Int, minor: Int, patch: Int

    public init(_ major: Int, _ minor: Int = 0, _ patch: Int = 0) {
        self.major = major; self.minor = minor; self.patch = patch
    }

    public init?(_ text: String) {
        let nums = text.split(separator: ".").map { Int($0) }
        guard !nums.isEmpty, nums.count <= 3, nums.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        let n = nums.map { $0! }
        self.init(n[0], n.count > 1 ? n[1] : 0, n.count > 2 ? n[2] : 0)
    }

    public static func < (a: OSVersion, b: OSVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }

    public var description: String { patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)" }
}

/// How the companion setup can be bootstrapped on a given iOS version.
/// Sources (read 2026-10-22): SideInstaller README compatibility table
/// (github.com/FrizzleM/SideInstaller), SideStore docs (docs.sidestore.io), LiveContainer README,
/// jkcoxson.com/blog/i-made-apple-mad (iOS 26.4 lockdown change).
public struct CompatibilityReport: Equatable, Sendable {
    public enum Bootstrap: Equatable, Sendable {
        /// SideInstaller claims a fully on-device first install (no computer) on iOS 27.0.1+.
        case onDeviceSupported
        /// Works, but a pairing file made on a computer (e.g. with Plume Impactor/iloader) is needed once.
        case needsPairingFileFromComputer
        /// On-device sideloading tools do not support this version.
        case unsupported
    }

    public let version: OSVersion
    public let bootstrap: Bootstrap
    public let disciplineRuns: Bool         // Discipline's own deployment target is iOS 26.0
    public let needsInSubnetPeer: Bool       // iOS 26.4+ lockdown check, see PeerAddressPlanner
    public let isBeta: Bool
    public let notes: [String]

    public static let disciplineMinimum = OSVersion(26, 0)

    public static func evaluate(_ v: OSVersion, isBeta: Bool = false) -> CompatibilityReport {
        let bootstrap: Bootstrap
        if v >= OSVersion(27, 0, 1) { bootstrap = .onDeviceSupported }
        else if v >= OSVersion(17, 4) { bootstrap = .needsPairingFileFromComputer }
        else { bootstrap = .unsupported }
        var notes: [String] = []
        if v >= OSVersion(26, 4) {
            notes.append("iOS 26.4+ checks VPN connections against your Wi-Fi subnet. Keep LocalDevVPN updated (in-subnet peer fix).")
        }
        if v.major >= 26 {
            notes.append("JIT on iOS 26+ works only for a short list of apps (SideStore docs). Most apps run without JIT in LiveContainer.")
        }
        if isBeta {
            notes.append("Beta iOS: Apple can change lockdown or signing behaviour between betas. Re-test after each beta update.")
        }
        if bootstrap == .needsPairingFileFromComputer {
            notes.append("Make a pairing file once on a computer (Plume Impactor can generate it).")
        }
        return CompatibilityReport(version: v, bootstrap: bootstrap, disciplineRuns: v >= disciplineMinimum,
                                   needsInSubnetPeer: v >= OSVersion(26, 4), isBeta: isBeta, notes: notes)
    }
}
