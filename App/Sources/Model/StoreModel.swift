import Foundation
import SwiftUI
import Combine
import CryptoKit
import DisciplineCore

/// The storefront's data: the community's public AltStore-format sources, read live, cached for offline,
/// with GitHub stars as one of the three real trending signals. Discipline lists and links; it hosts nothing.
@MainActor
final class StoreModel: ObservableObject {
    static let shared = StoreModel()

    struct SourceState: Identifiable, Equatable {
        var id: String { source.url }
        var source: StoreSource
        var appCount = 0
        var error: String?
        var fetchedAt: Date?
        var fromCache = false
    }

    @Published var sources: [SourceState] = []
    @Published var apps: [StoreApp] = []
    @Published var stars: [String: Int] = [:]
    @Published var loading = false
    @Published var lastLoad: Date?

    private let dir: URL
    private let defaultsKey = "store.sources.v1"
    private var urlSession: URLSession

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("store", isDirectory: true)
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uiTestingResetStore") {
            try? FileManager.default.removeItem(at: dir)
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        urlSession = URLSession(configuration: cfg)
        let saved = (UserDefaults.standard.data(forKey: defaultsKey)).flatMap { try? JSONDecoder().decode([StoreSource].self, from: $0) }
        sources = (saved ?? StoreSource.defaults).map { SourceState(source: $0) }
        stars = (try? Data(contentsOf: dir.appendingPathComponent("stars.json")))
            .flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) } ?? [:]
        loadFromCache()
    }

    private func persistSources() {
        if let d = try? JSONEncoder().encode(sources.map(\.source)) { UserDefaults.standard.set(d, forKey: defaultsKey) }
    }

    private func cacheURL(_ source: StoreSource) -> URL {
        let h = SHA256.hash(data: Data(source.url.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent("source-\(h).json")
    }

    private func loadFromCache() {
        var all: [StoreApp] = []
        for i in sources.indices {
            let u = cacheURL(sources[i].source)
            guard let d = try? Data(contentsOf: u),
                  let parsed = try? StoreCatalog.parse(d, sourceURL: sources[i].source.url, fallbackName: sources[i].source.name) else { continue }
            let at = (try? FileManager.default.attributesOfItem(atPath: u.path)[.modificationDate]) as? Date
            sources[i].appCount = parsed.apps.count
            sources[i].fetchedAt = at
            sources[i].fromCache = true
            all += parsed.apps
        }
        apps = all
    }

    /// Reads every source at once. A source that fails keeps its last good copy (marked as cached),
    /// or shows "couldn't load"; the others carry on.
    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let list = sources.map(\.source)
        let session = urlSession
        let results: [(StoreSource, Result<Data, Error>)] = await withTaskGroup(of: (StoreSource, Result<Data, Error>).self) { group in
            for s in list {
                group.addTask {
                    guard let u = URL(string: s.url) else { return (s, .failure(URLError(.badURL))) }
                    do {
                        let (d, r) = try await session.data(from: u)
                        if let code = (r as? HTTPURLResponse)?.statusCode, code != 200 { return (s, .failure(StoreError.http(code))) }
                        return (s, .success(d))
                    } catch { return (s, .failure(error)) }
                }
            }
            var out: [(StoreSource, Result<Data, Error>)] = []
            for await r in group { out.append(r) }
            return out
        }
        var all: [StoreApp] = []
        for (s, r) in results {
            guard let i = sources.firstIndex(where: { $0.source.url == s.url }) else { continue }
            switch r {
            case .success(let d):
                do {
                    let parsed = try StoreCatalog.parse(d, sourceURL: s.url, fallbackName: s.name)
                    try? d.write(to: cacheURL(s), options: .atomic)
                    sources[i].appCount = parsed.apps.count
                    sources[i].error = nil
                    sources[i].fetchedAt = Date()
                    sources[i].fromCache = false
                    if !s.builtIn && s.name != parsed.name && !parsed.name.isEmpty { sources[i].source.name = parsed.name }
                    all += parsed.apps
                } catch {
                    sources[i].error = "Not a sideload source (\(error))"
                    all += cachedApps(s, index: i)
                }
            case .failure(let e):
                sources[i].error = Self.describe(e)
                all += cachedApps(s, index: i)
            }
        }
        // Keep the source order stable (the sources list is the order the store shows).
        let order = Dictionary(uniqueKeysWithValues: sources.enumerated().map { ($1.source.url, $0) })
        apps = all.sorted { (order[$0.sourceURL] ?? 99, $0.sourceRank) < (order[$1.sourceURL] ?? 99, $1.sourceRank) }
        lastLoad = Date()
        persistSources()
        await refreshStars()
    }

    private func cachedApps(_ s: StoreSource, index i: Int) -> [StoreApp] {
        let u = cacheURL(s)
        guard let d = try? Data(contentsOf: u), let parsed = try? StoreCatalog.parse(d, sourceURL: s.url, fallbackName: s.name) else {
            sources[i].appCount = 0
            return []
        }
        sources[i].fromCache = true
        sources[i].appCount = parsed.apps.count
        sources[i].fetchedAt = (try? FileManager.default.attributesOfItem(atPath: u.path)[.modificationDate]) as? Date
        return parsed.apps
    }

    /// GitHub stars for apps whose download is a GitHub release (unauthenticated API: 60 calls an hour,
    /// so stars are cached for a day and at most 40 repos are asked per refresh).
    private func refreshStars() async {
        let starsURL = dir.appendingPathComponent("stars.json")
        let age = ((try? FileManager.default.attributesOfItem(atPath: starsURL.path)[.modificationDate]) as? Date).map { Date().timeIntervalSince($0) } ?? .infinity
        let repos = Array(Set(apps.compactMap(\.gitHubRepo))).sorted()
        let missing = repos.filter { stars[$0] == nil }
        guard age > 86_400 || !missing.isEmpty else { return }
        let ask = Array((age > 86_400 ? repos : missing).prefix(40))
        let session = urlSession
        let got: [String: Int] = await withTaskGroup(of: (String, Int?).self) { group in
            for repo in ask {
                group.addTask {
                    guard let u = URL(string: "https://api.github.com/repos/\(repo)") else { return (repo, nil) }
                    var req = URLRequest(url: u)
                    req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                    guard let res = try? await session.data(for: req), (res.1 as? HTTPURLResponse)?.statusCode == 200,
                          let j = try? JSONSerialization.jsonObject(with: res.0) as? [String: Any] else { return (repo, nil) }
                    return (repo, j["stargazers_count"] as? Int)
                }
            }
            var out: [String: Int] = [:]
            for await (r, n) in group { if let n { out[r] = n } }
            return out
        }
        guard !got.isEmpty else { return }
        stars.merge(got) { _, new in new }
        if let d = try? JSONEncoder().encode(stars) { try? d.write(to: starsURL, options: .atomic) }
    }

    // MARK: Sources

    /// Returns an error line, or nil when the source was added.
    func addSource(_ text: String) async -> String? {
        guard let u = StoreCatalog.validateSourceURL(text) else { return "Enter an https:// source link." }
        if sources.contains(where: { $0.source.url == u.absoluteString }) { return "That source is already in the list." }
        sources.append(SourceState(source: StoreSource(url: u.absoluteString, name: u.host ?? "Source")))
        persistSources()
        await refresh()
        if let s = sources.first(where: { $0.source.url == u.absoluteString }), let e = s.error {
            return "Added, but it couldn't load: \(e)"
        }
        return nil
    }

    func removeSources(at offsets: IndexSet) {
        let gone = offsets.map { sources[$0].source.url }
        sources.remove(atOffsets: offsets)
        apps.removeAll { gone.contains($0.sourceURL) }
        persistSources()
    }

    func restoreDefaults() async {
        let custom = sources.filter { !$0.source.builtIn }
        sources = StoreSource.defaults.map { SourceState(source: $0) } + custom
        persistSources()
        await refresh()
    }

    // MARK: Derived

    var unique: [StoreApp] { StoreCatalog.dedupe(apps) }
    var trending: [StoreApp] { StoreCatalog.trending(apps, stars: stars, now: Date(), limit: 8) }
    var categories: [String] { StoreCatalog.categories(apps) }

    func reasons(_ app: StoreApp) -> [String] {
        let s = StoreCatalog.signals(app, stars: stars, now: Date())
        var out: [String] = []
        if s.featured { out.append("Featured by \(app.sourceName)") }
        if let d = s.daysSinceRelease {
            out.append(d < 1 ? "Updated today" : (d < 2 ? "Updated yesterday" : "Updated \(Int(d)) days ago"))
        }
        if let st = s.stars { out.append("★ \(Self.compact(st)) on GitHub") }
        return out
    }

    static func compact(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000).replacingOccurrences(of: ".0k", with: "k") : "\(n)"
    }

    static func describe(_ e: Error) -> String {
        if let s = e as? StoreError, case .http(let c) = s { return "The source answered \(c)" }
        let ns = e as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet: return "Offline"
            case NSURLErrorTimedOut: return "Timed out"
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return "Host not found"
            default: return "Couldn't connect"
            }
        }
        return "Couldn't load"
    }

    enum StoreError: Error { case http(Int) }

    /// Hands the app's own download link to SideStore or LiveContainer (the same handoff as the Library).
    static func installLinks(for app: StoreApp) -> [(String, URL)] {
        let enc = app.downloadURL.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? app.downloadURL
        var out: [(String, URL)] = []
        if let u = URL(string: "sidestore://install?url=\(enc)") { out.append(("SideStore", u)) }
        if let u = URL(string: "livecontainer://install?url=\(enc)") { out.append(("LiveContainer", u)) }
        return out
    }
}
