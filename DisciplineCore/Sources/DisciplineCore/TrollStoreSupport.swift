import Foundation

/// OS compatibility is not proof TrollStore is installed. The `apple-magnifier` scheme
/// can open Apple's own Magnifier on a phone without TrollStore.
public enum TrollStoreSupport {
    public enum Verdict: String, Equatable, Sendable {
        case eligibleOS = "This iOS version is in TrollStore's published support window; installation is not detected."
        case unsupportedOS = "TrollStore is unavailable on this iOS version. Discipline cannot turn it on."
        case unknownOS = "This iOS version or build is unverified; TrollStore handoff stays off."
    }

    /// Official README: 14.0 beta 2–16.6.1, 16.7 RC (20H18), 17.0.
    /// iOS 14.0 pre-beta-2 cannot be resolved from a public version number; fail closed.
    public static func evaluate(version: OSVersion?, build: String? = nil) -> Verdict {
        guard let v = version else { return .unknownOS }
        if v == OSVersion(16, 7) {
            return build == "20H18" ? .eligibleOS : (build == nil ? .unknownOS : .unsupportedOS)
        }
        if v >= OSVersion(14, 0) && v <= OSVersion(16, 6, 1) { return .eligibleOS }
        if v == OSVersion(17, 0) { return .eligibleOS }
        return .unsupportedOS
    }
}
