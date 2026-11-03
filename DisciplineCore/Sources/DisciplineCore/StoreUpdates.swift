import Foundation

/// What Discipline remembers about an app it handed to a sideload tool from the store.
/// iOS doesn't tell one app another app's version (a URL-scheme check only says "installed or not",
/// and only for schemes Discipline declares), so the version Discipline handed off is the installed
/// version it knows.
public struct StoreInstallRecord: Codable, Equatable, Hashable, Sendable {
    public var bundleID: String
    public var name: String
    public var version: String
    /// The tool the link went to ("SideStore", "LiveContainer").
    public var tool: String
    public var sourceURL: String
    public var handedOffAt: Date
    /// The newest version Discipline already handed off on its own, so one update is started once.
    public var autoHandedOffVersion: String?

    public init(bundleID: String, name: String, version: String, tool: String, sourceURL: String,
                handedOffAt: Date, autoHandedOffVersion: String? = nil) {
        self.bundleID = bundleID; self.name = name; self.version = version; self.tool = tool
        self.sourceURL = sourceURL; self.handedOffAt = handedOffAt; self.autoHandedOffVersion = autoHandedOffVersion
    }
}

public enum StoreUpdates {
    /// Version order for store versions: "0.4.0" < "0.4.10", "1.0" == "1.0.0", "1.0-beta" < "1.0".
    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        if VersionCompare.isNewer(a, than: b) { return .orderedDescending }
        if VersionCompare.isNewer(b, than: a) { return .orderedAscending }
        return .orderedSame
    }

    /// For each installed app, the listing with the highest version across all sources, when that
    /// version is higher than the one Discipline handed off.
    public static func available(_ apps: [StoreApp], installed: [String: StoreInstallRecord]) -> [StoreApp] {
        var best: [String: StoreApp] = [:]
        for a in apps where !a.bundleID.isEmpty {
            guard let rec = installed[a.bundleID], VersionCompare.isNewer(a.version, than: rec.version) else { continue }
            if let cur = best[a.bundleID], !VersionCompare.isNewer(a.version, than: cur.version) { continue }
            best[a.bundleID] = a
        }
        return best.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The updates Discipline should start without a tap: auto-update is on for the app (default on)
    /// and that version hasn't been handed off on its own before.
    public static func autoHandoffs(_ apps: [StoreApp], installed: [String: StoreInstallRecord],
                                    autoUpdate: [String: Bool]) -> [StoreApp] {
        available(apps, installed: installed).filter { a in
            guard autoUpdate[a.bundleID] ?? true, let rec = installed[a.bundleID] else { return false }
            if let done = rec.autoHandedOffVersion, !VersionCompare.isNewer(a.version, than: done) { return false }
            return true
        }
    }
}

extension StoreSource {
    /// The built-in sources shipped before NCOM's was added (Oct 28, 2026). A saved list from then has
    /// already "seen" these, so one the user removed stays removed.
    public static let legacyDefaultURLs: [String] = [
        "https://cdn.altstore.io/file/altstore/apps.json", "https://apps.sidestore.io",
        "https://community-apps.sidestore.io/sidecommunity.json", "https://alt.getutm.app",
        "https://provenance-emu.com/apps.json", "https://alt.crystall1ne.dev",
        "https://flyinghead.github.io/flycast-builds/altstore.json", "https://ish.app/altstore.json",
        "https://stikdebug.xyz/index.json", "https://raw.githubusercontent.com/khcrysalis/Feather/main/app-repo.json",
    ]

    /// Brings a saved source list up to date: a built-in source the user has never had is added at its
    /// place in `defaults` (NCOM first); one they had and removed is not brought back.
    /// Returns the list and the built-in URLs now seen.
    public static func merging(saved: [StoreSource]?, seenDefaults: [String]?,
                               defaults: [StoreSource] = StoreSource.defaults) -> (sources: [StoreSource], seen: [String]) {
        let allURLs = defaults.map(\.url)
        guard let saved else { return (defaults, allURLs) }
        let seen = Set(seenDefaults ?? legacyDefaultURLs)
        var out = saved
        let have = Set(saved.map(\.url))
        for (i, d) in defaults.enumerated() where !have.contains(d.url) && !seen.contains(d.url) {
            out.insert(d, at: min(i, out.count))
        }
        let newSeen = (seenDefaults ?? legacyDefaultURLs) + allURLs.filter { !seen.contains($0) }
        return (out, newSeen)
    }
}
