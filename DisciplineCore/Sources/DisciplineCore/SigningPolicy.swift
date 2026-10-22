import Foundation

/// What Apple allows for apps signed with a given kind of Apple account.
/// Sources (read 2026-10-22):
///  - Capability table: https://developer.apple.com/help/account/reference/supported-capabilities-ios/
///    (column "Apple Developer" = free account; "ADP" = paid Apple Developer Program)
///  - Limits: https://docs.sidestore.io/docs/faq (free: 3 active apps incl. the installer,
///    10 App IDs per 7 days, 7-day expiry; paid $99/yr: 365-day expiry)
public enum AccountTier: String, Codable, CaseIterable, Sendable {
    case free   // personal Apple ID, no paid membership (what Plume Impactor / SideStore use by default)
    case paid   // Apple Developer Program, $99/year

    public var signatureLifetimeDays: Int { self == .free ? 7 : 365 }

    /// Apps signed with this account that may be installed at once (nil = no practical cap).
    public var activeAppLimit: Int? { self == .free ? 3 : nil }

    /// New App IDs (each app AND each app extension needs one) per rolling 7 days.
    public var appIDsPerWeek: Int? { self == .free ? 10 : nil }
}

public enum Capability: String, CaseIterable, Codable, Sendable {
    case appGroups, backgroundModes, keychainSharing, dataProtection, healthKit
    case networkExtensions, personalVPN, familyControlsDevelopment, pushNotifications
    case associatedDomains, timeSensitiveNotifications, increasedMemoryLimit, siri

    /// Whether Apple's capability table lists it for a free account.
    public var availableOnFreeAccount: Bool {
        switch self {
        case .appGroups, .backgroundModes, .keychainSharing, .dataProtection, .healthKit: return true
        case .networkExtensions, .personalVPN, .familyControlsDevelopment, .pushNotifications,
             .associatedDomains, .timeSensitiveNotifications, .increasedMemoryLimit, .siri: return false
        }
    }

    public func available(on tier: AccountTier) -> Bool {
        tier == .paid ? true : availableOnFreeAccount
    }
}

/// Which Discipline build fits an account.
public enum DisciplineEdition: String, Codable, Sendable {
    /// No app extensions. Uses the App Store LocalDevVPN for the tunnel. Works with a free Apple ID.
    case standard
    /// Embeds its own packet-tunnel extension (Network Extensions). Needs a paid account.
    case pro

    public var requiredCapabilities: [Capability] {
        switch self {
        case .standard: return []
        case .pro: return [.networkExtensions]
        }
    }

    /// App IDs consumed when installed (main app + each extension).
    public var appIDCost: Int { self == .standard ? 1 : 2 }

    public func canBeSigned(by tier: AccountTier) -> Bool {
        requiredCapabilities.allSatisfy { $0.available(on: tier) }
    }

    public static func recommended(for tier: AccountTier) -> DisciplineEdition {
        tier == .paid ? .pro : .standard
    }
}
