import Foundation
import SwiftUI
import UIKit
import DisciplineCore

enum AppTab: Hashable { case home, library, github, expiry, more }

/// The Store tab shows the sideload sources' apps, or the GitHub-release finder.
enum StoreMode: String, Hashable { case apps, github }

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
    @Published var now = Date()
    /// The Ouija Board / NCOM Lab unlock (25 taps, 7 long presses, or a signed NCOM QR). Saved.
    var labUnlocked: Bool {
        get { settings.ouijaUnlocked }
        set { settings.ouijaUnlocked = newValue }
    }
    /// Shows the magic-ring animation over the app; set when a valid NCOM code arrives.
    @Published var magicRing: MagicRingState?
    /// Asks More to open the Ouija Board screen (after the magic ring finishes).
    @Published var openOuija = false
    @Published var storeMode: StoreMode = .apps
    /// Last thing the Ouija Board did, for its "Loading/install stat message" line.
    @Published var ouijaStatus = "Ready. No prototype device connected."

    // Auto refresh
    @Published var autoRefreshStatus = ""
    /// Discipline's own signature, read from its embedded provisioning profile.
    @Published var ownSignature: OwnSignature = .notRead
    let autoPlanner = AutoRefreshPlanner()

    // Self-update
    @Published var selfUpdate: GitHubRelease?
    @Published var selfUpdateStatus = "Not checked yet"
    @Published var updateChecking = false

    // GitHub
    @Published var gitHubQuery = ""
    @Published var gitHubRef: GitHubRepoRef?
    @Published var releases: [GitHubRelease] = []
    @Published var gitHubLoading = false
    @Published var gitHubError: String?
    @Published var downloadingAssetID: Int?

    enum OwnSignature: Equatable {
        case notRead
        case unreadable(String)
        case read(expires: Date, tier: AccountTier)
    }

    struct MagicRingState: Equatable, Identifiable {
        let id = UUID()
        let accepted: Bool
        let message: String
    }

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
        // v0.2 reminders are replaced by auto refresh (she asked for no reminders).
        if settings.remindersEnabled {
            settings.remindersEnabled = false
            if !TestHooks.isUITesting { ReminderService.cancelAll() }
        }
        if TestHooks.ouijaUnlocked { settings.ouijaUnlocked = true }
        if TestHooks.autoRefreshOff { settings.autoRefresh = false }
        if TestHooks.autoDownload { settings.autoDownloadUpdates = true }
        if TestHooks.dueApp {
            trackedApps = [TrackedApp(name: "SideStore", bundleID: "com.sidestore.test",
                                      signedAt: Date().addingTimeInterval(-6 * 86_400), tier: .free)]
        }
        if TestHooks.seedRepos {
            savedRepos = [SavedRepo(ref: GitHubRepoRef(owner: "missing", repo: "repo")),
                          SavedRepo(ref: GitHubRepoRef(owner: "ncom", repo: "sample-app"), lastSeenTag: "v1.0.0", latestKnownTag: "v1.0.0")]
        }
        if TestHooks.seedSigned, let url = Bundle.main.url(forResource: "Signed", withExtension: "ipa") {
            importIPA(from: url, origin: "Test fixture")
            tab = .home
            libraryPath = []
        }
        readOwnSignature()
        if let code = TestHooks.ouijaCode, let url = URL(string: "discipline://ouija?code=\(code)") {
            handleIncoming(url)
        }
    }

    /// The background app-refresh wake: re-read expiry and check for updates (no UI).
    func backgroundCheck() async {
        readOwnSignature()
        await autoCheckIfDue()
    }

    var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    /// Runs each time Discipline comes to the front (and once at launch): re-reads its own signature,
    /// starts an auto refresh when one is due, and checks for updates when it's time.
    func becameActive() async {
        refreshEnvironment()
        readOwnSignature()
        await runAutoRefreshIfDue()
        await autoCheckIfDue()
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
        case "ouija":
            receiveOuijaCode(url.absoluteString)
        case "ouija-callback":
            tab = .more
            let (line, ok) = OuijaLink.shared.receive(url)
            show(line, error: !ok)
        case "github":
            tab = .github
            storeMode = .github
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
        // App IDs are only counted when the user confirms the install ("I installed it with SideStore").
    }

    /// Called after the share sheet hands a local file to SideStore (direct signing spends App IDs).
    func noteSideStoreShare(_ item: LibraryItem) {
        budget.record(Date(), count: item.appIDCost)
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
        trackedApps[i].profileExpiresAt = nil
        trackedApps.sort { $0.expiresAt < $1.expiresAt }
        show("\(app.name) marked refreshed")
        rescheduleIfNeeded()
    }

    func markAllRefreshed() {
        let d = Date()
        for i in trackedApps.indices where trackedApps[i].bundleID != Bundle.main.bundleIdentifier {
            trackedApps[i].signedAt = d; trackedApps[i].tier = settings.tier; trackedApps[i].profileExpiresAt = nil
        }
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

    /// Checks every saved repo. One failing repo no longer stops the others.
    /// - Parameter quiet: launch/background checks only speak up when something changed.
    func checkUpdates(quiet: Bool = false) async {
        var updated = 0
        var failed: [String] = []
        var downloaded = 0
        for i in savedRepos.indices {
            do {
                let list = try await gitHub.releases(savedRepos[i].ref)
                let newest = ReleasePicker.newestWithIPA(list, includePrereleases: savedRepos[i].includePrereleases)
                savedRepos[i].latestKnownTag = newest?.tagName
                if savedRepos[i].hasUpdate {
                    updated += 1
                    if settings.autoDownloadUpdates, let release = newest, let asset = ReleasePicker.preferredAsset(release.assets) {
                        if await autoDownload(asset, from: release, repo: savedRepos[i].ref) { downloaded += 1 }
                    }
                }
            } catch {
                failed.append(savedRepos[i].ref.fullName)
            }
        }
        var text = updated == 0 ? "All saved repos are up to date" : "\(updated) update\(updated == 1 ? "" : "s") available"
        if downloaded > 0 { text += " · \(downloaded) downloaded to Library" }
        if !failed.isEmpty { text += " · couldn't check \(failed.joined(separator: ", "))" }
        if !quiet || updated > 0 || !failed.isEmpty { show(text, error: updated == 0 && !failed.isEmpty) }
    }

    /// Downloads a saved repo's new .ipa into the Library without switching tabs.
    private func autoDownload(_ asset: GitHubRelease.Asset, from release: GitHubRelease, repo: GitHubRepoRef) async -> Bool {
        let origin = "GitHub \(repo.fullName) \(release.tagName)"
        if library.contains(where: { $0.origin == origin }) { return false }
        do {
            let file = try await gitHub.download(asset)
            defer { try? FileManager.default.removeItem(at: file) }
            let keepTab = tab, keepPath = libraryPath
            let item = importIPA(from: file, origin: origin, remoteURL: asset.browserDownloadURL)
            tab = keepTab; libraryPath = keepPath
            return item != nil
        } catch {
            return false
        }
    }

    // MARK: Self-update and automatic checks

    /// Launch / foreground / background check: saved repos and Discipline itself, at most every 6 hours.
    func autoCheckIfDue(force: Bool = false) async {
        guard settings.autoCheckUpdates else { return }
        if TestHooks.isUITesting && !TestHooks.autoCheck { return }   // tests never touch the network unasked
        if !force, let last = settings.lastUpdateCheck, Date().timeIntervalSince(last) < 6 * 3600, last <= Date() { return }
        settings.lastUpdateCheck = Date()
        await checkSelfUpdate(quiet: true)
        if !savedRepos.isEmpty { await checkUpdates(quiet: true) }
    }

    /// Looks for a newer Discipline on GitHub Releases and keeps its release notes ("what's new").
    func checkSelfUpdate(quiet: Bool = false) async {
        updateChecking = true
        defer { updateChecking = false }
        do {
            let list = try await gitHub.releases(AppConfig.updateRepo)
            if let u = VersionCompare.update(for: appVersion, in: list, includePrereleases: settings.includePrereleases) {
                selfUpdate = u
                var shown = u.tagName
                if shown.lowercased().hasPrefix("v") { shown.removeFirst() }
                selfUpdateStatus = "Discipline \(shown) is available"
                show(selfUpdateStatus, detail: u.tagName)
                if settings.autoDownloadUpdates { await downloadSelfUpdate(openDetail: false) }
            } else {
                selfUpdate = nil
                selfUpdateStatus = list.isEmpty ? "No Discipline release is published on GitHub yet" : "Discipline \(appVersion) is the newest"
                if !quiet { show(selfUpdateStatus) }
            }
        } catch {
            selfUpdateStatus = "Couldn't check: \(error.localizedDescription)"
            if !quiet { show(selfUpdateStatus, error: true) }
        }
    }

    /// Puts the new Discipline .ipa in the Library, where Install with SideStore / LiveContainer re-signs it.
    /// (iOS doesn't let an app replace itself; the signer does the install.)
    func downloadSelfUpdate(openDetail: Bool = true) async {
        guard let u = selfUpdate, let asset = ReleasePicker.preferredAsset(u.assets) else { return }
        let origin = "Discipline update \(u.tagName)"
        if !openDetail, library.contains(where: { $0.origin == origin }) { return }
        do {
            let file = try await gitHub.download(asset)
            defer { try? FileManager.default.removeItem(at: file) }
            let keepTab = tab, keepPath = libraryPath
            let item = importIPA(from: file, origin: origin, remoteURL: asset.browserDownloadURL)
            if !openDetail { tab = keepTab; libraryPath = keepPath }
            if item != nil {
                selfUpdateStatus = "\(u.tagName) downloaded. Install it with SideStore or LiveContainer."
            }
        } catch {
            show("Download failed: \(error.localizedDescription)", error: true)
        }
    }

    // MARK: Auto refresh

    /// Reads the expiry from Discipline's own provisioning profile and keeps it in the tracked list,
    /// so its countdown is always the real one (no typed date).
    func readOwnSignature() {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") else {
            ownSignature = .unreadable("No provisioning profile in this build (simulator or unsigned). On your iPhone the signer adds one and Discipline reads it.")
            return
        }
        do {
            let profile = try ProvisioningProfile.parse([UInt8](try Data(contentsOf: url)))
            let tier = profile.tier()
            ownSignature = .read(expires: profile.expirationDate, tier: tier)
            let id = Bundle.main.bundleIdentifier ?? "com.ncom.discipline"
            let me = TrackedApp(name: "Discipline", bundleID: id, signedAt: profile.creationDate ?? Date(), tier: tier,
                                profileExpiresAt: profile.expirationDate)
            if let i = trackedApps.firstIndex(where: { $0.bundleID == id }) {
                if trackedApps[i] != me { trackedApps[i] = me; trackedApps.sort { $0.expiresAt < $1.expiresAt } }
            } else {
                trackedApps.append(me); trackedApps.sort { $0.expiresAt < $1.expiresAt }
            }
        } catch {
            ownSignature = .unreadable("Couldn't read the provisioning profile (\(error)).")
        }
    }

    func setAutoRefresh(_ on: Bool) async {
        settings.autoRefresh = on
        if on {
            show("Auto refresh on")
            await runAutoRefreshIfDue()
        } else {
            autoRefreshStatus = "Off"
            show("Auto refresh off")
        }
    }

    /// The automatic part: no reminder, no button. When an app is close to expiring, Discipline starts
    /// SideStore's refresh by itself (LocalDevVPN on, then SideStore) the moment it comes to the front,
    /// from the Shortcuts automation, or from discipline://refresh.
    func runAutoRefreshIfDue() async {
        guard settings.autoRefresh else { autoRefreshStatus = "Off"; return }
        let short: (Date) -> String = { $0.formatted(date: .abbreviated, time: .shortened) }
        switch autoPlanner.decide(apps: trackedApps, lastRun: settings.lastAutoRefresh, now: Date()) {
        case .nothingTracked:
            autoRefreshStatus = "On · nothing tracked yet"
        case .nothingDue(let next):
            autoRefreshStatus = "On · next refresh from \(short(next))"
        case .ranRecently(let next):
            autoRefreshStatus = "On · refresh started recently; next try after \(short(next))"
        case .refresh(let due):
            let names = trackedApps.filter { due.contains($0.bundleID) }.map(\.name).joined(separator: ", ")
            guard installed.contains(.localDevVPN) || installed.contains(.sideStore) else {
                autoRefreshStatus = "On · \(names) due, but LocalDevVPN and SideStore aren't installed (More → Setup)"
                return
            }
            settings.lastAutoRefresh = Date()
            autoRefreshStatus = "On · refreshing \(names)"
            await refreshAll()
        }
    }

    /// Track an imported app. A signed .ipa carries its expiry, so nothing is typed.
    /// Returns false when the .ipa has no provisioning profile (the caller asks for the date).
    func trackFromProfile(_ item: LibraryItem) -> Bool {
        guard let data = try? Data(contentsOf: fileURL(for: item)),
              let profile = try? IPAReader.provisioningProfile(bytes: [UInt8](data)) else { return false }
        addTracked(TrackedApp(name: item.displayName, bundleID: item.bundleID, signedAt: profile.creationDate ?? Date(),
                              tier: profile.tier(), profileExpiresAt: profile.expirationDate))
        show("Tracking \(item.displayName) · expiry read from its signature")
        return true
    }

    // MARK: Ouija Board unlock

    /// A QR (from the Camera app link, the in-app scanner, or a photo) was read.
    func receiveOuijaCode(_ text: String) {
        switch OuijaCode.check(text, publicKeys: AppConfig.ouijaKeys) {
        case .valid:
            magicRing = MagicRingState(accepted: true, message: OuijaContent.shared.ringSigned)
        case .notACode:
            show("That QR isn't an NCOM code.", error: true)
        case .badSignature:
            magicRing = MagicRingState(accepted: false, message: "Not signed by NCOM")
        case .wrongContent:
            show("That NCOM code isn't an Ouija Board unlock.", error: true)
        }
    }

    /// Called when the magic ring finishes.
    func finishMagicRing() {
        guard let ring = magicRing else { return }
        magicRing = nil
        if ring.accepted {
            labUnlocked = true
            tab = .more
            openOuija = true
            show("Ouija Board unlocked")
        } else {
            show("That code isn't signed by NCOM. Nothing unlocked.", error: true)
        }
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
        // Settings, tracked apps, saved repos and the App ID log. Imported .ipa files are not included.
        var backup = snapshot
        backup.library = []
        guard let data = try? Persistence.encoder.encode(backup), (try? data.write(to: url, options: .atomic)) != nil else {
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
