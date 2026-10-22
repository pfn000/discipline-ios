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

struct AppSettings: Codable, Equatable {
    var tier: AccountTier = .free
    var remindersEnabled: Bool = false
    var expectedTunnelIP: String = ""
    var appearance: AppearanceChoice = .system
    var tint: TintChoice = .ocean
    var includePrereleases: Bool = false
}

/// Everything Discipline keeps, in one JSON file. Also the format of an exported backup.
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
            let dir = fm.temporaryDirectory.appendingPathComponent("discipline-uitest-\(UUID().uuidString)")
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
