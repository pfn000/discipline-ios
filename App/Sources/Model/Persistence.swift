import Foundation
import DisciplineCore

/// One .ipa Discipline has seen: imported from Files/Share, downloaded from GitHub, or opened from a link.
struct LibraryItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var fileName: String              // stored under Documents/Library/
    var displayName: String
    var bundleID: String
    var version: String
    var build: String?
    var minimumOS: String?
    var extensionCount: Int
    var fileSize: Int
    var origin: String                // "Files", "GitHub owner/repo vX", ...
    var remoteURL: String?            // set for GitHub downloads, lets SideStore/LiveContainer fetch it directly
    var addedAt: Date
    var hasIcon: Bool

    var appIDCost: Int { 1 + extensionCount }
}

enum AppearanceChoice: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum TintChoice: String, Codable, CaseIterable, Identifiable {
    case ocean, violet, rose, mint, amber
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Ouija Board header: which kind of session is signed in (labels come from OuijaContent).
enum OuijaSessionKind: String, Codable, CaseIterable, Identifiable {
    case userProfile, playgroundID
    var id: String { rawValue }
    var label: String { self == .userProfile ? OuijaContent.shared.sessionUser : OuijaContent.shared.sessionAlt }
}

struct AppSettings: Codable, Equatable {
    var tier: AccountTier = .free
    var remindersEnabled: Bool = false
    var expectedTunnelIP: String = ""
    var appearance: AppearanceChoice = .system
    var tint: TintChoice = .ocean
    var includePrereleases: Bool = false
    // v0.3
    var autoRefresh: Bool = true
    var lastAutoRefresh: Date?
    var autoCheckUpdates: Bool = true
    var autoDownloadUpdates: Bool = false
    var lastUpdateCheck: Date?
    var ouijaUnlocked: Bool = false
    var ouijaAgreed: Bool = false
    var ouijaSession: OuijaSessionKind = .userProfile

    init() {}

    /// Every key is optional so state saved by older versions still loads (a missing key keeps its default).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        tier = (try? c.decodeIfPresent(AccountTier.self, forKey: .tier)) ?? d.tier
        remindersEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .remindersEnabled)) ?? d.remindersEnabled
        expectedTunnelIP = (try? c.decodeIfPresent(String.self, forKey: .expectedTunnelIP)) ?? d.expectedTunnelIP
        appearance = (try? c.decodeIfPresent(AppearanceChoice.self, forKey: .appearance)) ?? d.appearance
        tint = (try? c.decodeIfPresent(TintChoice.self, forKey: .tint)) ?? d.tint
        includePrereleases = (try? c.decodeIfPresent(Bool.self, forKey: .includePrereleases)) ?? d.includePrereleases
        autoRefresh = (try? c.decodeIfPresent(Bool.self, forKey: .autoRefresh)) ?? d.autoRefresh
        lastAutoRefresh = try? c.decodeIfPresent(Date.self, forKey: .lastAutoRefresh)
        autoCheckUpdates = (try? c.decodeIfPresent(Bool.self, forKey: .autoCheckUpdates)) ?? d.autoCheckUpdates
        autoDownloadUpdates = (try? c.decodeIfPresent(Bool.self, forKey: .autoDownloadUpdates)) ?? d.autoDownloadUpdates
        lastUpdateCheck = try? c.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)
        ouijaUnlocked = (try? c.decodeIfPresent(Bool.self, forKey: .ouijaUnlocked)) ?? d.ouijaUnlocked
        ouijaAgreed = (try? c.decodeIfPresent(Bool.self, forKey: .ouijaAgreed)) ?? d.ouijaAgreed
        ouijaSession = (try? c.decodeIfPresent(OuijaSessionKind.self, forKey: .ouijaSession)) ?? d.ouijaSession
    }
}

/// Everything Discipline keeps, in one JSON file. An exported backup uses the same format with `library` left empty.
struct Snapshot: Codable, Equatable {
    var version: Int = 1
    var trackedApps: [TrackedApp] = []
    var savedRepos: [SavedRepo] = []
    var library: [LibraryItem] = []
    var budget: AppIDBudget = AppIDBudget(tier: .free)
    var settings: AppSettings = AppSettings()
}

struct Persistence {
    let directory: URL

    static func standard() -> Persistence {
        let fm = FileManager.default
        if TestHooks.isUITesting {
            // -uiTestingStateDir <name> keeps state between launches of one test (to prove it persists).
            let name = TestHooks.stateDir.map { "discipline-uitest-\($0)" } ?? "discipline-uitest-\(UUID().uuidString)"
            let dir = fm.temporaryDirectory.appendingPathComponent(name)
            if TestHooks.resetState { try? fm.removeItem(at: dir) }
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return Persistence(directory: dir)
        }
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return Persistence(directory: docs)
    }

    var stateFile: URL { directory.appendingPathComponent("discipline-state.json") }
    var libraryFolder: URL {
        let u = directory.appendingPathComponent("Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    func iconFile(for id: UUID) -> URL { libraryFolder.appendingPathComponent("\(id.uuidString).png") }
    func ipaFile(_ name: String) -> URL { libraryFolder.appendingPathComponent(name) }

    func load() -> Snapshot {
        guard let data = try? Data(contentsOf: stateFile) else { return Snapshot() }
        return (try? Self.decoder.decode(Snapshot.self, from: data)) ?? Snapshot()
    }

    func save(_ s: Snapshot) {
        guard let data = try? Self.encoder.encode(s) else { return }
        try? data.write(to: stateFile, options: .atomic)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
}
