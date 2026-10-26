import Foundation

/// "GitHub to iOS": turn a pasted GitHub link into a repo, list its releases' .ipa assets,
/// and notice when a saved repo has a newer release. Uses the public REST API
/// (https://docs.github.com/en/rest/releases/releases): unauthenticated calls are limited to
/// 60 per hour per IP; an optional personal token raises that.
public struct GitHubRepoRef: Codable, Hashable, Identifiable, Sendable {
    public let owner: String
    public let repo: String
    public var tag: String?     // set when the link pointed at one release

    public var id: String { "\(owner)/\(repo)".lowercased() }
    public var fullName: String { "\(owner)/\(repo)" }

    public init(owner: String, repo: String, tag: String? = nil) {
        self.owner = owner; self.repo = repo; self.tag = tag
    }

    /// Accepts "owner/repo", "github.com/owner/repo", "https://github.com/owner/repo(.git)",
    /// ".../releases", ".../releases/tag/v1.2", ".../releases/latest".
    public static func parse(_ text: String) -> GitHubRepoRef? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        for prefix in ["https://", "http://"] where s.lowercased().hasPrefix(prefix) { s.removeFirst(prefix.count) }
        if s.lowercased().hasPrefix("www.") { s.removeFirst(4) }
        if s.lowercased().hasPrefix("github.com/") { s.removeFirst("github.com/".count) }
        else if s.contains(".") && s.split(separator: "/").first?.contains(".") == true { return nil } // other host
        if let q = s.firstIndex(where: { $0 == "?" || $0 == "#" }) { s = String(s[..<q]) }
        let parts = s.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let valid: (String) -> Bool = { p in
            !p.isEmpty && p.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
        }
        var repo = parts[1]
        if repo.hasSuffix(".git") { repo.removeLast(4) }
        guard valid(parts[0]), valid(repo) else { return nil }
        var tag: String?
        if parts.count >= 5, parts[2] == "releases", parts[3] == "tag" { tag = parts[4].removingPercentEncoding ?? parts[4] }
        return GitHubRepoRef(owner: parts[0], repo: repo, tag: tag)
    }

    public var releasesAPI: URL { URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=20")! }
    public var latestAPI: URL { URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")! }
    public var webURL: URL { URL(string: "https://github.com/\(owner)/\(repo)")! }
}

public struct GitHubRelease: Codable, Equatable, Identifiable, Sendable {
    public struct Asset: Codable, Equatable, Identifiable, Sendable {
        public let id: Int
        public let name: String
        public let size: Int
        public let browserDownloadURL: String
        public let downloadCount: Int?

        enum CodingKeys: String, CodingKey {
            case id, name, size
            case browserDownloadURL = "browser_download_url"
            case downloadCount = "download_count"
        }

        public var isIPA: Bool { name.lowercased().hasSuffix(".ipa") || name.lowercased().hasSuffix(".tipa") }
    }

    public let id: Int
    public let tagName: String
    public let name: String?
    public let draft: Bool
    public let prerelease: Bool
    public let publishedAt: String?
    public let assets: [Asset]
    /// The release notes (Markdown) the author wrote: "what's new in this version".
    public let body: String?
    public let htmlURL: String?

    enum CodingKeys: String, CodingKey {
        case id, name, draft, prerelease, assets, body
        case tagName = "tag_name"
        case publishedAt = "published_at"
        case htmlURL = "html_url"
    }

    public var ipaAssets: [Asset] { assets.filter(\.isIPA) }
    public var title: String { (name?.isEmpty == false ? name! : tagName) }

    public static func decodeList(_ data: Data) throws -> [GitHubRelease] {
        try JSONDecoder().decode([GitHubRelease].self, from: data)
    }
}

/// A repo the user saved, with the release they last saw.
public struct SavedRepo: Codable, Hashable, Identifiable, Sendable {
    public var ref: GitHubRepoRef
    public var lastSeenTag: String?
    public var latestKnownTag: String?
    public var includePrereleases: Bool

    public var id: String { ref.id }

    public init(ref: GitHubRepoRef, lastSeenTag: String? = nil, latestKnownTag: String? = nil, includePrereleases: Bool = false) {
        self.ref = ref; self.lastSeenTag = lastSeenTag; self.latestKnownTag = latestKnownTag; self.includePrereleases = includePrereleases
    }

    /// True when the newest release with an .ipa differs from the one the user last saw.
    public var hasUpdate: Bool {
        guard let latest = latestKnownTag else { return false }
        return latest != lastSeenTag
    }
}

public enum ReleasePicker {
    /// Newest non-draft release (optionally including prereleases) that has at least one .ipa.
    /// GitHub returns releases newest first.
    public static func newestWithIPA(_ releases: [GitHubRelease], includePrereleases: Bool) -> GitHubRelease? {
        releases.first { !$0.draft && (includePrereleases || !$0.prerelease) && !$0.ipaAssets.isEmpty }
    }

    /// Of several .ipa assets, prefer one that is not a debug/simulator build and is the largest
    /// (often the full build). The user can still pick any other.
    public static func preferredAsset(_ assets: [GitHubRelease.Asset]) -> GitHubRelease.Asset? {
        let ipas = assets.filter(\.isIPA)
        let clean = ipas.filter { a in
            let n = a.name.lowercased()
            return !n.contains("debug") && !n.contains("simulator") && !n.contains("-sim")
        }
        return (clean.isEmpty ? ipas : clean).max { $0.size < $1.size }
    }
}

/// Compares release tags with the app's own version ("v0.3.1" vs "0.3.0").
public enum VersionCompare {
    /// Numeric parts of a tag: "v1.2.3-beta" -> ([1, 2, 3], "beta").
    public static func parts(_ tag: String) -> (numbers: [Int], suffix: String)? {
        var s = tag.trimmingCharacters(in: .whitespaces)
        if s.lowercased().hasPrefix("v") { s.removeFirst() }
        let main = s.split(separator: "-", maxSplits: 1).map(String.init)
        guard let head = main.first, !head.isEmpty else { return nil }
        var nums: [Int] = []
        for p in head.split(separator: ".", omittingEmptySubsequences: false) {
            guard let n = Int(p) else { return nil }
            nums.append(n)
        }
        return (nums, main.count > 1 ? main[1] : "")
    }

    /// True when `tag` is a higher version than `current`. A pre-release suffix sorts below the
    /// same number without one. Tags that aren't versions are never "newer".
    public static func isNewer(_ tag: String, than current: String) -> Bool {
        guard let a = parts(tag), let b = parts(current) else { return false }
        let n = max(a.numbers.count, b.numbers.count)
        for i in 0..<n {
            let x = i < a.numbers.count ? a.numbers[i] : 0
            let y = i < b.numbers.count ? b.numbers[i] : 0
            if x != y { return x > y }
        }
        if a.suffix.isEmpty != b.suffix.isEmpty { return a.suffix.isEmpty }
        return a.suffix > b.suffix
    }

    /// The newest release (with an .ipa) that is a higher version than `current`, or nil.
    public static func update(for current: String, in releases: [GitHubRelease], includePrereleases: Bool) -> GitHubRelease? {
        releases
            .filter { !$0.draft && (includePrereleases || !$0.prerelease) && !$0.ipaAssets.isEmpty && isNewer($0.tagName, than: current) }
            .max { a, b in isNewer(b.tagName, than: a.tagName) }
    }
}

public struct RateLimit: Equatable, Sendable {
    public let limit: Int?
    public let remaining: Int?
    public let reset: Date?

    public init(headers: [String: String]) {
        func h(_ k: String) -> String? { headers.first { $0.key.lowercased() == k }?.value }
        limit = h("x-ratelimit-limit").flatMap(Int.init)
        remaining = h("x-ratelimit-remaining").flatMap(Int.init)
        reset = h("x-ratelimit-reset").flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }
    }
}
