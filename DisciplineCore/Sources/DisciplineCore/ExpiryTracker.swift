import Foundation

/// One sideloaded app whose signature Discipline keeps an eye on.
public struct TrackedApp: Codable, Hashable, Identifiable, Sendable {
    public var id: String { bundleID }
    public var name: String
    public var bundleID: String
    public var signedAt: Date
    public var tier: AccountTier

    public init(name: String, bundleID: String, signedAt: Date, tier: AccountTier) {
        self.name = name; self.bundleID = bundleID; self.signedAt = signedAt; self.tier = tier
    }

    public var expiresAt: Date { signedAt.addingTimeInterval(TimeInterval(tier.signatureLifetimeDays) * 86_400) }
}

public enum ExpiryStatus: Equatable, Sendable {
    case healthy(remaining: TimeInterval)
    case refreshSoon(remaining: TimeInterval)   // inside the warning window
    case expired(since: TimeInterval)
}

public struct ExpiryTracker: Sendable {
    /// Start nagging this long before expiry. Default 48 h (two daily chances to refresh).
    public var warningWindow: TimeInterval
    /// Reminder offsets before expiry, in seconds.
    public var reminderOffsets: [TimeInterval]

    public init(warningWindow: TimeInterval = 48 * 3600,
                reminderOffsets: [TimeInterval] = [48 * 3600, 24 * 3600, 2 * 3600]) {
        self.warningWindow = warningWindow
        self.reminderOffsets = reminderOffsets.sorted(by: >)
    }

    public func status(of app: TrackedApp, now: Date) -> ExpiryStatus {
        let remaining = app.expiresAt.timeIntervalSince(now)
        if remaining <= 0 { return .expired(since: -remaining) }
        if remaining <= warningWindow { return .refreshSoon(remaining: remaining) }
        return .healthy(remaining: remaining)
    }

    /// Future reminder dates for one app (past ones are dropped).
    public func reminderDates(for app: TrackedApp, now: Date) -> [Date] {
        reminderOffsets.map { app.expiresAt.addingTimeInterval(-$0) }.filter { $0 > now }
    }

    /// The app that expires first, the one to refresh next.
    public func nextToExpire(_ apps: [TrackedApp]) -> TrackedApp? {
        apps.min { $0.expiresAt < $1.expiresAt }
    }

    /// "6d 3h", "5h 12m", "expired" — short text for the dashboard.
    public static func shortText(_ status: ExpiryStatus) -> String {
        func fmt(_ t: TimeInterval) -> String {
            let mins = Int(t / 60)
            let d = mins / 1440, h = (mins % 1440) / 60, m = mins % 60
            if d > 0 { return "\(d)d \(h)h" }
            if h > 0 { return "\(h)h \(m)m" }
            return "\(m)m"
        }
        switch status {
        case .healthy(let r), .refreshSoon(let r): return fmt(r)
        case .expired: return "expired"
        }
    }
}

/// Free accounts may create 10 App IDs per rolling 7 days. Every app and every app
/// extension signed takes one. This keeps a local log so Discipline can warn before
/// SideStore or Plume Impactor hits Apple's limit.
public struct AppIDBudget: Codable, Equatable, Sendable {
    public var tier: AccountTier
    public private(set) var registrations: [Date]

    public init(tier: AccountTier, registrations: [Date] = []) {
        self.tier = tier; self.registrations = registrations.sorted()
    }

    private static let window: TimeInterval = 7 * 86_400

    public func used(now: Date) -> Int {
        registrations.filter { now.timeIntervalSince($0) < Self.window && $0 <= now }.count
    }

    public func remaining(now: Date) -> Int? {
        guard let cap = tier.appIDsPerWeek else { return nil }
        return max(0, cap - used(now: now))
    }

    public func canRegister(_ count: Int = 1, now: Date) -> Bool {
        guard let left = remaining(now: now) else { return true }
        return left >= count
    }

    /// When enough old registrations roll out of the window to allow `count` more.
    public func nextAvailable(_ count: Int = 1, now: Date) -> Date? {
        guard let cap = tier.appIDsPerWeek else { return now }
        let active = registrations.filter { now.timeIntervalSince($0) < Self.window && $0 <= now }
        let needToFree = active.count + count - cap
        if needToFree <= 0 { return now }
        guard needToFree <= active.count else { return nil } // asking for more than the cap
        return active[needToFree - 1].addingTimeInterval(Self.window)
    }

    public mutating func record(_ date: Date, count: Int = 1) {
        registrations.append(contentsOf: Array(repeating: date, count: count))
        registrations.sort()
    }
}
