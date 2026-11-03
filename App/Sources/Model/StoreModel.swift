import Foundation
import SwiftUI
import UIKit
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
    /// Apps Discipline handed to a sideload tool from the store, by bundle ID (the version it knows is installed).
    @Published var installs: [String: StoreInstallRecord] = [:]
    /// Per-app Auto-update switch, by bundle ID. Missing = on.
    @Published var autoUpdate: [String: Bool] = [:]
    /// The last thing the update check did, shown on the store ("Handed NCOM Music 0.2.1 to SideStore").
    @Published var updateNote: String?

    private let dir: URL
    private let defaultsKey = "store.sources.v1"
    private let seenDefaultsKey = "store.defaultsSeen.v1"
    private let installsKey = "store.installs.v1"
    private let autoUpdateKey = "store.autoUpdate.v1"
    private var urlSession: URLSession
    private var poller: Task<Void, Never>?
    /// While Discipline is open, the sources are re-read this often (and on every return to the front).
    static let pollInterval: TimeInterval = 15 * 60

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("store", isDirectory: true)
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uiTestingResetStore") {
            try? FileManager.default.removeItem(at: dir)
            for k in [defaultsKey, seenDefaultsKey, installsKey, autoUpdateKey] { UserDefaults.standard.removeObject(forKey: k) }
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        urlSession = URLSession(configuration: cfg)
        let saved = (UserDefaults.standard.data(forKey: defaultsKey)).flatMap { try? JSONDecoder().decode([StoreSource].self, from: $0) }
        // A list saved before NCOM's source existed gains it once (first); a built-in source removed stays removed.
        let merged = StoreSource.merging(saved: saved, seenDefaults: UserDefaults.standard.stringArray(forKey: seenDefaultsKey))
        sources = merged.sources.map { SourceState(source: $0) }
        UserDefaults.standard.set(merged.seen, forKey: seenDefaultsKey)
        installs = (UserDefaults.standard.data(forKey: installsKey))
            .flatMap { try? JSONDecoder().decode([String: StoreInstallRecord].self, from: $0) } ?? [:]
        autoUpdate = (UserDefaults.standard.dictionary(forKey: autoUpdateKey) as? [String: Bool]) ?? [:]
        // UI tests: "-uiTestingStoreInstalled com.ncom.music=0.1.0" stands in for an earlier hand-off.
        if let seed = TestHooks.value(after: "-uiTestingStoreInstalled") {
            for pair in seed.split(separator: ",") {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard kv.count == 2 else { continue }
                installs[kv[0]] = StoreInstallRecord(bundleID: kv[0], name: kv[0], version: kv[1], tool: "SideStore",
                                                     sourceURL: StoreSource.ncomURL, handedOffAt: Date())
            }
        }
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
        runAutoUpdates()
        await refreshStars()
    }

    // MARK: Updates

    /// Installed apps (handed off from here) whose source now lists a newer version.
    var updates: [StoreApp] { StoreUpdates.available(apps, installed: installs) }

    func update(for app: StoreApp) -> StoreApp? { updates.first { $0.bundleID == app.bundleID && !app.bundleID.isEmpty } }

    func isAutoUpdateOn(_ bundleID: String) -> Bool { autoUpdate[bundleID] ?? true }

    func setAutoUpdate(_ bundleID: String, _ on: Bool) {
        autoUpdate[bundleID] = on
        UserDefaults.standard.set(autoUpdate, forKey: autoUpdateKey)
        if on { runAutoUpdates() }
    }

    private func persistInstalls() {
        if let d = try? JSONEncoder().encode(installs) { UserDefaults.standard.set(d, forKey: installsKey) }
    }

    /// Get / Update: hands the source's own link to SideStore, else LiveContainer, and remembers the version
    /// handed off (iOS doesn't let Discipline read another app's version). Returns the line to show.
    @discardableResult
    func handOff(_ app: StoreApp, automatic: Bool = false) -> String {
        let links = StoreModel.installLinks(for: app)
        let preferred = installs[app.bundleID]?.tool
        let ordered = links.filter { $0.0 == preferred } + links.filter { $0.0 != preferred }
        for (name, url) in ordered where UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            if !app.bundleID.isEmpty {
                var r = installs[app.bundleID] ?? StoreInstallRecord(bundleID: app.bundleID, name: app.name, version: app.version,
                                                                     tool: name, sourceURL: app.sourceURL, handedOffAt: Date())
                r.version = app.version; r.tool = name; r.name = app.name; r.sourceURL = app.sourceURL; r.handedOffAt = Date()
                if automatic { r.autoHandedOffVersion = app.version }
                installs[app.bundleID] = r
                persistInstalls()
            }
            return "Handed to \(name). It downloads \(app.name) \(app.version) from \(app.sourceName)'s link and signs it."
        }
        if automatic, !app.bundleID.isEmpty {   // don't retry the same version on every check
            installs[app.bundleID]?.autoHandedOffVersion = app.version
            persistInstalls()
            return "\(app.name) \(app.version) is out. SideStore or LiveContainer isn't installed, so it wasn't started."
        }
        UIPasteboard.general.string = app.downloadURL
        return "SideStore or LiveContainer isn't installed, so nothing was opened. The download link was copied."
    }

    /// Auto-update: when a source lists a newer version of an app Discipline handed off, and that app's
    /// Auto-update is on, Discipline starts the update itself (once per version) while it's on screen.
    /// The sideload tool still downloads, re-signs and installs it; iOS can ask to confirm.
    func runAutoUpdates() {
        let pending = StoreUpdates.autoHandoffs(apps, installed: installs, autoUpdate: autoUpdate)
        guard let next = pending.first else { return }
        guard UIApplication.shared.applicationState == .active, !TestHooks.isUITesting || TestHooks.autoCheck else {
            updateNote = "\(next.name) \(next.version) is ready to update"
            return
        }
        updateNote = handOff(next, automatic: true)
    }

    /// Discipline came to the front: re-read the sources now (if the last read is over a minute old),
    /// then every `pollInterval` while it stays open.
    func appBecameActive() {
        poller?.cancel()
        // UI tests never touch the network unasked (the store tests ask with -uiTestingResetStore).
        if TestHooks.isUITesting && !ProcessInfo.processInfo.arguments.contains("-uiTestingResetStore") { return }
        poller = Task { [weak self] in
            let fresh = self?.lastLoad.map { Date().timeIntervalSince($0) < 60 } ?? false
            if !fresh { await self?.refresh() }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(StoreModel.pollInterval * 1_000_000_000))
                if Task.isCancelled { break }
                await self?.refresh()
            }
        }
    }

    func appWentBackground() {
        poller?.cancel()
        poller = nil
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
