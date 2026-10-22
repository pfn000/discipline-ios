import Foundation
import SwiftUI
import UIKit
import DisciplineCore

enum AppTab: Hashable { case home, library, github, expiry, more }

@MainActor
final class AppModel: ObservableObject {
    // Persistent state
    @Published var trackedApps: [TrackedApp] = [] { didSet { persist() } }
    @Published var savedRepos: [SavedRepo] = [] { didSet { persist() } }
    @Published var library: [LibraryItem] = [] { didSet { persist() } }
    @Published var budget: AppIDBudget = AppIDBudget(tier: .free) { didSet { persist() } }
    @Published var settings: AppSettings = AppSettings() { didSet { persist(); if oldValue.tier != settings.tier { budget.tier = settings.tier } } }

    // Live state
    @Published var tab: AppTab = .home
    @Published var libraryPath: [UUID] = []
    @Published var installed: Set<Companion> = []
    @Published var tunnel: TunnelState = .notConnected
    @Published var toast: Toast?
    @Published var labUnlocked = false
    @Published var now = Date()

    // GitHub
    @Published var gitHubQuery = ""
    @Published var gitHubRef: GitHubRepoRef?
    @Published var releases: [GitHubRelease] = []
    @Published var gitHubLoading = false
    @Published var gitHubError: String?
    @Published var downloadingAssetID: Int?

    struct Toast: Equatable, Identifiable {
        let id = UUID()
        let text: String
        let detail: String   // exposed as the accessibility value (the exact URL, for tests)
        let isError: Bool
    }

    /// The live model, for App Intents (Shortcuts) that run in the app's process.
    static weak var current: AppModel?

    let persistence: Persistence
    let companions = CompanionService()
    let gitHub = GitHubService.make()
    let tracker = ExpiryTracker()
    private var loading = true

    init(persistence: Persistence = .standard()) {
        self.persistence = persistence
        let s = persistence.load()
        trackedApps = s.trackedApps
        savedRepos = s.savedRepos
        library = s.library
        budget = s.budget
        settings = s.settings
        loading = false
        refreshEnvironment()
        AppModel.current = self
        if TestHooks.seedLibrary {
            for name in ["Tracked", "Sample"] {
                if let url = Bundle.main.url(forResource: name, withExtension: "ipa") { importIPA(from: url, origin: "Test fixture") }
            }
            tab = .home
            libraryPath = []
        }
        if TestHooks.openSampleIPA, let url = TestHooks.sampleIPAURL {
            handleIncoming(url)
        }
    }

    var snapshot: Snapshot {
        Snapshot(trackedApps: trackedApps, savedRepos: savedRepos, library: library, budget: budget, settings: settings)
    }

    private func persist() {
        guard !loading else { return }
        persistence.save(snapshot)
    }

    // MARK: Environment

    var osVersion: OSVersion { OSVersion(UIDevice.current.systemVersion) ?? OSVersion(26, 0) }
    var compatibility: CompatibilityReport { CompatibilityReport.evaluate(osVersion) }

    func refreshEnvironment() {
        now = Date()
        installed = Set(Companion.allCases.filter { companions.isInstalled($0) })
        let expected = IPv4Address(settings.expectedTunnelIP.trimmingCharacters(in: .whitespaces))
        tunnel = TunnelDetector.state(of: CompanionService.interfaces(), expected: expected)
    }

    var setupPlan: SetupPlan {
        SetupPlan(SetupPlan.Observations(installed: installed, tunnel: tunnel, trackedApps: trackedApps.count, os: osVersion))
    }

    func show(_ text: String, detail: String = "", error: Bool = false) {
        toast = Toast(text: text, detail: detail, isError: error)
    }

    // MARK: Opening other apps

    /// Opens a companion-app URL, or explains why it could not.
    func send(_ url: URL, to companion: Companion) async {
        guard installed.contains(companion) else {
            show("\(companion.displayName) isn't installed. Get it first.", detail: url.absoluteString, error: true)
            return
        }
        let ok = await companions.open(url)
        if ok { show("Sent to \(companion.displayName)", detail: url.absoluteString) }
        else { show("\(companion.displayName) didn't open.", detail: url.absoluteString, error: true) }
    }

    func openWeb(_ url: URL) async {
        let ok = await companions.open(url)
        if !ok { show("Couldn't open the link.", detail: url.absoluteString, error: true) }
    }

    func openCompanion(_ c: Companion) async {
        if installed.contains(c) { await send(c.openURL, to: c) }
        else { await openWeb(c.officialURL) }
    }

    func vpnOn() async { await send(DeepLinks.enableVPN(), to: .localDevVPN) }
    func vpnOff() async { await send(DeepLinks.disableVPN(), to: .localDevVPN) }

    /// "Refresh all": LocalDevVPN switches the tunnel on and then opens SideStore, where
    /// SideStore's own Refresh All runs (SideStore has no URL that starts a refresh by itself).
    func refreshAll() async {
        if installed.contains(.localDevVPN) {
            await send(DeepLinks.enableVPN(returnTo: Companion.sideStore.scheme), to: .localDevVPN)
        } else if installed.contains(.sideStore) {
            await send(Companion.sideStore.openURL, to: .sideStore)
        } else {
            show("Install LocalDevVPN and SideStore first (More → Setup).", error: true)
        }
    }

    // MARK: Incoming files and links

    func handleIncoming(_ url: URL) {
        if url.isFileURL {
            let ext = url.pathExtension.lowercased()
            if ext == "ipa" || ext == "tipa" { importIPA(from: url, origin: "Files") }
            else if ext == "json" { importBackup(from: url) }
            else { show("Discipline opens .ipa files and Discipline backups.", error: true) }
            return
        }
        guard url.scheme == AppConfig.urlScheme else { return }
        switch url.host ?? "" {
        case "refresh":
            tab = .home
            Task { await refreshAll() }
        case "github":
            tab = .github
            if let repo = DeepLinks.queryValue("repo", in: url) {
                gitHubQuery = repo
                Task { await findReleases() }
            }
        default:
            refreshEnvironment()
            show(tunnelIsUp ? "Back from LocalDevVPN. Tunnel is on." : "Back in Discipline.")
        }
    }

    var tunnelIsUp: Bool { if case .connected = tunnel { return true }; return false }

    @discardableResult
    func importIPA(from url: URL, origin: String, remoteURL: String? = nil) -> LibraryItem? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let info = try IPAReader.read(bytes: [UInt8](data))
            var item = LibraryItem(fileName: "", displayName: info.displayName, bundleID: info.bundleID,
                                   version: info.version, build: info.build, minimumOS: info.minimumOS,
                                   extensionCount: info.extensionCount, fileSize: info.fileSize, origin: origin,
                                   remoteURL: remoteURL, addedAt: Date(), hasIcon: info.iconPNG != nil)
            let safeName = info.displayName.filter { $0.isLetter || $0.isNumber || $0 == "-" }
            item.fileName = "\(item.id.uuidString.prefix(8))-\(safeName.isEmpty ? "app" : safeName)-\(info.version).ipa"
            try data.write(to: persistence.ipaFile(item.fileName), options: .atomic)
            if let png = info.iconPNG { try? Data(png).write(to: persistence.iconFile(for: item.id)) }
            library.insert(item, at: 0)
            tab = .library
            libraryPath = [item.id]
            show("Opened \(info.displayName) \(info.version)")
            return item
        } catch {
            show("That file isn't a readable .ipa (\(error)).", error: true)
            return nil
        }
    }

    func fileURL(for item: LibraryItem) -> URL { persistence.ipaFile(item.fileName) }

    func icon(for item: LibraryItem) -> UIImage? {
        guard item.hasIcon else { return nil }
        return UIImage(contentsOfFile: persistence.iconFile(for: item.id).path)
    }

    func deleteLibraryItem(_ item: LibraryItem) {
        try? FileManager.default.removeItem(at: fileURL(for: item))
        try? FileManager.default.removeItem(at: persistence.iconFile(for: item.id))
        library.removeAll { $0.id == item.id }
        libraryPath.removeAll { $0 == item.id }
    }

    /// Remote installs: SideStore and LiveContainer download the .ipa themselves.
    func installRemote(_ remote: URL, with companion: Companion, appIDCost: Int) async {
        guard let link = try? DeepLinks.install(ipa: remote, with: companion) else { return }
        await send(link, to: companion)
        if companion == .sideStore, installed.contains(.sideStore) { budget.record(Date(), count: appIDCost) }
    }

    /// Called after the share sheet hands a local file to SideStore (direct signing spends App IDs).
    func noteSideStoreShare(_ item: LibraryItem) {
        budget.record(Date(), count: item.appIDCost)
    }

    func track(_ item: LibraryItem) {
        let app = TrackedApp(name: item.displayName, bundleID: item.bundleID, signedAt: Date(), tier: settings.tier)
        addTracked(app)
    }

    // MARK: Expiry

    func addTracked(_ app: TrackedApp) {
        trackedApps.removeAll { $0.bundleID == app.bundleID }
        trackedApps.append(app)
        trackedApps.sort { $0.expiresAt < $1.expiresAt }
        show("Tracking \(app.name)")
        rescheduleIfNeeded()
    }

    func markRefreshed(_ app: TrackedApp) {
        guard let i = trackedApps.firstIndex(of: app) else { return }
        trackedApps[i].signedAt = Date()
        trackedApps[i].tier = settings.tier
        trackedApps.sort { $0.expiresAt < $1.expiresAt }
        show("\(app.name) marked refreshed")
        rescheduleIfNeeded()
    }

    func markAllRefreshed() {
        let d = Date()
        for i in trackedApps.indices { trackedApps[i].signedAt = d; trackedApps[i].tier = settings.tier }
        show("All apps marked refreshed")
        rescheduleIfNeeded()
    }

    func removeTracked(_ app: TrackedApp) {
        trackedApps.removeAll { $0.bundleID == app.bundleID }
        rescheduleIfNeeded()
    }

    func setReminders(_ on: Bool) async {
        if on {
            let granted = TestHooks.isUITesting ? true : await ReminderService.requestPermission()
            settings.remindersEnabled = granted
            if granted {
                let n = TestHooks.isUITesting ? trackedApps.reduce(0) { $0 + tracker.reminderDates(for: $1, now: Date()).count }
                                              : await ReminderService.reschedule(trackedApps)
                show("Reminders on: \(n) scheduled")
            } else {
                show("Notifications are off for Discipline in Settings.", error: true)
            }
        } else {
            settings.remindersEnabled = false
            if !TestHooks.isUITesting { ReminderService.cancelAll() }
            show("Reminders off")
        }
    }

    private func rescheduleIfNeeded() {
        guard settings.remindersEnabled, !TestHooks.isUITesting else { return }
        let apps = trackedApps
        Task { await ReminderService.reschedule(apps) }
    }

    var soonest: TrackedApp? { tracker.nextToExpire(trackedApps) }

    // MARK: GitHub

    func findReleases() async {
        gitHubError = nil
        guard let ref = GitHubRepoRef.parse(gitHubQuery) else {
            gitHubError = "Paste a GitHub link or owner/repo."
            releases = []; gitHubRef = nil
            return
        }
        gitHubRef = ref
        gitHubLoading = true
        defer { gitHubLoading = false }
        do {
            releases = try await gitHub.releases(ref).filter { !$0.draft && (settings.includePrereleases || !$0.prerelease) }
            if releases.allSatisfy({ $0.ipaAssets.isEmpty }) { gitHubError = "No .ipa files in \(ref.fullName)'s releases." }
            updateSaved(ref, with: releases)
        } catch {
            releases = []
            gitHubError = error.localizedDescription
        }
    }

    private func updateSaved(_ ref: GitHubRepoRef, with list: [GitHubRelease]) {
        guard let i = savedRepos.firstIndex(where: { $0.id == ref.id }) else { return }
        savedRepos[i].latestKnownTag = ReleasePicker.newestWithIPA(list, includePrereleases: savedRepos[i].includePrereleases)?.tagName
    }

    var isCurrentRepoSaved: Bool { gitHubRef.map { r in savedRepos.contains { $0.id == r.id } } ?? false }

    func toggleSaveCurrentRepo() {
        guard let ref = gitHubRef else { return }
        if let i = savedRepos.firstIndex(where: { $0.id == ref.id }) {
            savedRepos.remove(at: i)
            show("Removed \(ref.fullName)")
        } else {
            let newest = ReleasePicker.newestWithIPA(releases, includePrereleases: settings.includePrereleases)?.tagName
            savedRepos.append(SavedRepo(ref: GitHubRepoRef(owner: ref.owner, repo: ref.repo), lastSeenTag: newest,
                                        latestKnownTag: newest, includePrereleases: settings.includePrereleases))
            show("Saved \(ref.fullName)")
        }
    }

    func checkUpdates() async {
        var updated = 0
        for i in savedRepos.indices {
            do {
                let list = try await gitHub.releases(savedRepos[i].ref)
                savedRepos[i].latestKnownTag = ReleasePicker.newestWithIPA(list, includePrereleases: savedRepos[i].includePrereleases)?.tagName
                if savedRepos[i].hasUpdate { updated += 1 }
            } catch {
                show("Update check failed: \(error.localizedDescription)", error: true)
                return
            }
        }
        show(updated == 0 ? "All saved repos are up to date" : "\(updated) update\(updated == 1 ? "" : "s") available")
    }

    func openSaved(_ repo: SavedRepo) async {
        if let i = savedRepos.firstIndex(of: repo) { savedRepos[i].lastSeenTag = savedRepos[i].latestKnownTag }
        gitHubQuery = repo.ref.fullName
        await findReleases()
    }

    func download(_ asset: GitHubRelease.Asset, from release: GitHubRelease) async {
        guard let ref = gitHubRef else { return }
        downloadingAssetID = asset.id
        defer { downloadingAssetID = nil }
        do {
            let file = try await gitHub.download(asset)
            importIPA(from: file, origin: "GitHub \(ref.fullName) \(release.tagName)", remoteURL: asset.browserDownloadURL)
            try? FileManager.default.removeItem(at: file)
        } catch {
            show("Download failed: \(error.localizedDescription)", error: true)
        }
    }

    // MARK: Settings / backup

    func saveToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if Keychain.save(trimmed) { show(trimmed.isEmpty ? "Token removed" : "Token saved in the Keychain") }
        else { show("Couldn't save the token.", error: true) }
    }

    var hasToken: Bool { (Keychain.load() ?? "").isEmpty == false }

    func exportBackup() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Discipline-backup.json")
        guard let data = try? Persistence.encoder.encode(snapshot), (try? data.write(to: url, options: .atomic)) != nil else {
            show("Couldn't write the backup.", error: true); return nil
        }
        return url
    }

    func importBackup(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let s = try? Persistence.decoder.decode(Snapshot.self, from: data) else {
            show("That isn't a Discipline backup.", error: true); return
        }
        trackedApps = s.trackedApps; savedRepos = s.savedRepos; budget = s.budget; settings = s.settings
        show("Backup restored: \(s.trackedApps.count) apps, \(s.savedRepos.count) repos")
    }

    func resetBudget() { budget = AppIDBudget(tier: settings.tier); show("App ID log cleared") }
}
