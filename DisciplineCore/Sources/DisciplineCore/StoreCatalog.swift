import Foundation

/// The sideload community's public app lists ("sources"), as AltStore, SideStore, Feather and
/// LiveContainer read them, plus a best-effort reading of Scarlet's format.
/// Discipline only lists and links: every app downloads from the URL its own source publishes.
public struct StoreSource: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String { url }
    public var url: String
    public var name: String
    public var builtIn: Bool
    public init(url: String, name: String, builtIn: Bool = false) {
        self.url = url; self.name = name; self.builtIn = builtIn
    }

    /// Public sources that answered with a valid list on Oct 28, 2026 (checked live).
    public static let defaults: [StoreSource] = [
        StoreSource(url: "https://cdn.altstore.io/file/altstore/apps.json", name: "AltStore", builtIn: true),
        StoreSource(url: "https://apps.sidestore.io", name: "SideStore", builtIn: true),
        StoreSource(url: "https://community-apps.sidestore.io/sidecommunity.json", name: "SideStore Team Picks", builtIn: true),
        StoreSource(url: "https://alt.getutm.app", name: "UTM", builtIn: true),
        StoreSource(url: "https://provenance-emu.com/apps.json", name: "Provenance", builtIn: true),
        StoreSource(url: "https://alt.crystall1ne.dev", name: "crystall1ne.dev", builtIn: true),
        StoreSource(url: "https://flyinghead.github.io/flycast-builds/altstore.json", name: "Flycast", builtIn: true),
        StoreSource(url: "https://ish.app/altstore.json", name: "iSH", builtIn: true),
        StoreSource(url: "https://stikdebug.xyz/index.json", name: "StikDebug", builtIn: true),
        StoreSource(url: "https://raw.githubusercontent.com/khcrysalis/Feather/main/app-repo.json", name: "Feather", builtIn: true),
    ]
}

public struct StoreApp: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String { sourceURL + "|" + bundleID + "|" + name }
    public var name: String
    public var bundleID: String
    public var developer: String
    public var subtitle: String
    public var summary: String
    public var iconURL: String?
    public var tint: String?
    public var screenshots: [String]
    public var version: String
    public var versionDate: Date?
    public var downloadURL: String
    public var size: Int?
    public var minOS: String?
    public var category: String
    public var categoryGuessed: Bool
    public var featured: Bool
    public var sourceURL: String
    public var sourceName: String
    /// Position of the app in its source's list (the maintainer's own order).
    public var sourceRank: Int

    /// owner/repo when the download is a GitHub release asset.
    public var gitHubRepo: String? { StoreCatalog.gitHubRepo(from: downloadURL) }
}

public struct StoreCatalog: Sendable {
    public enum ParseError: Error, Equatable { case notJSON, noApps }

    static let dateFormats: [String] = ["yyyy-MM-dd'T'HH:mm:ssZZZZZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ", "yyyy-MM-dd"]

    public static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        for fmt in dateFormats {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    static func str(_ v: Any?) -> String? {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }
    static func int(_ v: Any?) -> Int? {
        if let n = v as? Int { return n }
        if let s = v as? String { return Int(s) }
        if let d = v as? Double { return Int(d) }
        return nil
    }

    /// Parses one source's JSON. Returns the source's own name and its apps.
    public static func parse(_ data: Data, sourceURL: String, fallbackName: String) throws -> (name: String, apps: [StoreApp]) {
        guard let obj = try? JSONSerialization.jsonObject(with: data), let root = obj as? [String: Any] else { throw ParseError.notJSON }
        if let list = root["apps"] as? [[String: Any]] {
            let name = str(root["name"]) ?? fallbackName
            let featured = Set((root["featuredApps"] as? [String]) ?? [])
            var apps: [StoreApp] = []
            for (rank, a) in list.enumerated() {
                let versions = (a["versions"] as? [[String: Any]]) ?? []
                let v0 = versions.first ?? [:]
                guard let appName = str(a["name"]),
                      let dl = str(v0["downloadURL"]) ?? str(a["downloadURL"]), !dl.isEmpty else { continue }
                let bundle = str(a["bundleIdentifier"]) ?? ""
                let shots: [String] = {
                    if let s = a["screenshotURLs"] as? [String] { return s }
                    if let s = a["screenshots"] as? [String] { return s }
                    if let s = a["screenshots"] as? [[String: Any]] { return s.compactMap { str($0["imageURL"]) } }
                    if let s = a["screenshots"] as? [String: Any], let i = s["iphone"] as? [Any] {
                        return i.compactMap { ($0 as? String) ?? str(($0 as? [String: Any])?["imageURL"]) }
                    }
                    return []
                }()
                let subtitle = str(a["subtitle"]) ?? ""
                let given = str(a["category"])
                let cat = given.map(prettyCategory) ?? guessCategory(name: appName, subtitle: subtitle + " " + (str(a["localizedDescription"]) ?? ""))
                apps.append(StoreApp(
                    name: appName, bundleID: bundle, developer: str(a["developerName"]) ?? "",
                    subtitle: subtitle, summary: str(a["localizedDescription"]) ?? "",
                    iconURL: str(a["iconURL"]), tint: str(a["tintColor"]), screenshots: shots,
                    version: str(v0["version"]) ?? str(a["version"]) ?? "",
                    versionDate: parseDate(str(v0["date"]) ?? str(a["versionDate"])),
                    downloadURL: dl, size: int(v0["size"]) ?? int(a["size"]),
                    minOS: str(v0["minOSVersion"]) ?? str(a["minOSVersion"]),
                    category: cat, categoryGuessed: given == nil,
                    featured: featured.contains(bundle), sourceURL: sourceURL, sourceName: name, sourceRank: rank))
            }
            guard !apps.isEmpty else { throw ParseError.noApps }
            return (name, apps)
        }
        // Scarlet: {"META": {"repoName": ...}, "<Category>": [{name, version, icon, down, dev, description, bundleID}]}
        if let meta = root["META"] as? [String: Any] {
            let name = str(meta["repoName"]) ?? fallbackName
            var apps: [StoreApp] = []
            var rank = 0
            for (key, value) in root.sorted(by: { $0.key < $1.key }) where key != "META" {
                guard let items = value as? [[String: Any]] else { continue }
                for a in items {
                    guard let appName = str(a["name"]), let dl = str(a["down"]), !dl.isEmpty else { continue }
                    apps.append(StoreApp(
                        name: appName, bundleID: str(a["bundleID"]) ?? "", developer: str(a["dev"]) ?? "",
                        subtitle: "", summary: str(a["description"]) ?? "", iconURL: str(a["icon"]), tint: nil,
                        screenshots: (a["screenshots"] as? [String]) ?? [], version: str(a["version"]) ?? "",
                        versionDate: nil, downloadURL: dl, size: nil, minOS: nil, category: key, categoryGuessed: false,
                        featured: false, sourceURL: sourceURL, sourceName: name, sourceRank: rank))
                    rank += 1
                }
            }
            guard !apps.isEmpty else { throw ParseError.noApps }
            return (name, apps)
        }
        throw ParseError.noApps
    }

    static func prettyCategory(_ c: String) -> String {
        switch c.lowercased() {
        case "developer": return "Developer"
        case "entertainment": return "Entertainment"
        case "games": return "Games"
        case "lifestyle": return "Lifestyle"
        case "photo-video": return "Photo & Video"
        case "social": return "Social"
        case "utilities": return "Utilities"
        default: return c.prefix(1).uppercased() + c.dropFirst()
        }
    }

    /// A guess from the words, used only when the source names no category (labelled as a guess in the app).
    public static func guessCategory(name: String, subtitle: String) -> String {
        let t = (name + " " + subtitle).lowercased()
        let rules: [(String, [String])] = [
            ("Emulators", ["emulator", "emulat", "nintendo", "playstation", "psp", "gamecube", "dreamcast", "retro", "nes", "gba", "ds "]),
            ("Developer", ["debug", "jit", "terminal", "shell", "linux", "virtual machine", "vm", "sign", "developer", "pair"]),
            ("Photo & Video", ["video", "youtube", "photo", "camera", "music", "stream"]),
            ("Social", ["reddit", "twitter", "social", "discord", "instagram"]),
            ("Games", ["game", "minecraft", "launcher"]),
            ("Utilities", ["store", "install", "app", "tool", "utility"]),
        ]
        for (cat, words) in rules where words.contains(where: { t.contains($0) }) { return cat }
        return "Other"
    }

    public static func gitHubRepo(from url: String) -> String? {
        guard let u = URL(string: url), u.host?.lowercased() == "github.com" else { return nil }
        let parts = u.path.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        return "\(parts[0])/\(parts[1])"
    }

    // MARK: Trending (real signals only)

    public struct Signals: Equatable, Sendable {
        public var featured: Bool
        public var daysSinceRelease: Double?
        public var stars: Int?
    }

    public static func signals(_ app: StoreApp, stars: [String: Int], now: Date) -> Signals {
        Signals(featured: app.featured,
                daysSinceRelease: app.versionDate.map { max(0, now.timeIntervalSince($0) / 86_400) },
                stars: app.gitHubRepo.flatMap { stars[$0] })
    }

    /// Score from the three real signals: the source's featured pick, how fresh the newest release is,
    /// and GitHub stars (log scale). Nothing here measures downloads: no source publishes them.
    public static func trendingScore(_ s: Signals) -> Double {
        var score = 0.0
        if s.featured { score += 3 }
        if let d = s.daysSinceRelease { score += 3 * exp(-d / 45) }
        if let st = s.stars { score += log10(Double(st) + 1) }
        return score
    }

    public static func trending(_ apps: [StoreApp], stars: [String: Int], now: Date, limit: Int = 8) -> [StoreApp] {
        let unique = dedupe(apps)
        return Array(unique.sorted {
            let a = trendingScore(signals($0, stars: stars, now: now)), b = trendingScore(signals($1, stars: stars, now: now))
            return a != b ? a > b : $0.name < $1.name
        }.prefix(limit))
    }

    /// The same app listed by two sources (or a beta beside it) shows once: first source wins.
    public static func dedupe(_ apps: [StoreApp]) -> [StoreApp] {
        var seen = Set<String>()
        return apps.filter { a in
            let key = (a.bundleID.isEmpty ? a.name : a.bundleID).lowercased() + "|" + a.name.lowercased()
            return seen.insert(key).inserted
        }
    }

    public static func search(_ apps: [StoreApp], _ query: String) -> [StoreApp] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return dedupe(apps) }
        return dedupe(apps).filter {
            $0.name.lowercased().contains(q) || $0.subtitle.lowercased().contains(q) ||
            $0.developer.lowercased().contains(q) || $0.bundleID.lowercased().contains(q)
        }
    }

    public static func categories(_ apps: [StoreApp]) -> [String] {
        Array(Set(dedupe(apps).map(\.category))).sorted()
    }

    public static func validateSourceURL(_ text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: t), u.scheme?.lowercased() == "https", let h = u.host, h.contains(".") else { return nil }
        return u
    }
}
