import XCTest
@testable import DisciplineCore

/// NCOM's own source: built in first, read with the ordinary parser, In Development tags, and the
/// version logic auto-update rests on.
final class StoreNCOMTests: XCTestCase {
    func ncomFixture() throws -> Data {
        try Data(contentsOf: Bundle.module.url(forResource: "ncom-source", withExtension: "json", subdirectory: "Fixtures")!)
    }

    func testDefaultsStartWithNCOM() {
        XCTAssertEqual(StoreSource.defaults.first?.url, StoreSource.ncomURL)
        XCTAssertEqual(StoreSource.defaults.first?.name, "NCOM")
        XCTAssertTrue(StoreSource.defaults.first?.builtIn ?? false)
        XCTAssertEqual(StoreSource.defaults.count, 11)
        XCTAssertEqual(Set(StoreSource.defaults.map(\.url)).count, 11, "no duplicate sources")
        XCTAssertTrue(StoreSource.ncomURL.hasPrefix("https://raw.githubusercontent.com/pfn000/ncom-source/"))
    }

    func testNCOMSourceParses() throws {
        let parsed = try StoreCatalog.parse(ncomFixture(), sourceURL: StoreSource.ncomURL, fallbackName: "x")
        XCTAssertEqual(parsed.name, "NCOM")
        XCTAssertEqual(parsed.apps.count, 1)
        let m = parsed.apps[0]
        XCTAssertEqual(m.name, "NCOM Music")
        XCTAssertEqual(m.bundleID, "com.ncom.music")
        XCTAssertEqual(m.developer, "NCOM")
        XCTAssertEqual(m.version, "0.2.0")
        XCTAssertEqual(m.statusTag, "In Development")
        XCTAssertEqual(m.sourceName, "NCOM")
        XCTAssertEqual(m.downloadURL, "https://raw.githubusercontent.com/pfn000/ncom-source/main/ipa/NCOM-Music-unsigned.ipa")
        XCTAssertEqual(m.iconURL, "https://raw.githubusercontent.com/pfn000/ncom-source/main/icons/ncom-music.png")
        XCTAssertFalse(parsed.apps.contains { $0.name.lowercased().contains("ouija") }, "private apps never ride the public source")
    }

    func testStatusTagIsRead() throws {
        XCTAssertEqual(StoreCatalog.statusTag(app: ["ncomStatus": "in-development"]), "In Development")
        XCTAssertEqual(StoreCatalog.statusTag(app: ["ncomStatus": "In Progress"]), "In Progress")
        XCTAssertEqual(StoreCatalog.statusTag(app: [:], version: ["ncomStatus": "wip"]), "In Progress")
        XCTAssertEqual(StoreCatalog.statusTag(app: ["beta": true]), "Beta")
        XCTAssertEqual(StoreCatalog.statusTag(app: ["ncomStatus": "released", "beta": true]), nil)
        XCTAssertNil(StoreCatalog.statusTag(app: ["name": "Plain"]))
        // Any source can use the key (a private source added by hand included).
        let json = #"{"name":"Mine","apps":[{"name":"P","bundleIdentifier":"p.p","developerName":"NCOM","ncomStatus":"in-development","versions":[{"version":"1.0","downloadURL":"https://example.com/p.ipa"}]}]}"#
        let a = try StoreCatalog.parse(Data(json.utf8), sourceURL: "https://example.com/s.json", fallbackName: "x").apps[0]
        XCTAssertEqual(a.statusTag, "In Development")
        // The public sources in the fixture carry no NCOM tag.
        let fx = Bundle.module.url(forResource: "store-fixture", withExtension: "json", subdirectory: "Fixtures")!
        let srcs = (try JSONSerialization.jsonObject(with: Data(contentsOf: fx)) as! [String: Any])["sources"] as! [String: Any]
        for (url, src) in srcs {
            let apps = try StoreCatalog.parse(JSONSerialization.data(withJSONObject: src), sourceURL: url, fallbackName: "x").apps
            XCTAssertFalse(apps.contains { $0.statusTag == "In Development" }, url)
        }
    }

    func testVersionOrder() {
        XCTAssertEqual(StoreUpdates.compare("0.4.0", "0.4.10"), .orderedAscending)
        XCTAssertEqual(StoreUpdates.compare("0.4.10", "0.4.9"), .orderedDescending)
        XCTAssertEqual(StoreUpdates.compare("1.0", "1.0.0"), .orderedSame)
        XCTAssertEqual(StoreUpdates.compare("v1.2", "1.2.0"), .orderedSame)
        XCTAssertEqual(StoreUpdates.compare("1.0-beta", "1.0"), .orderedAscending)
        XCTAssertEqual(StoreUpdates.compare("0.2.0", "0.10.0"), .orderedAscending)
        XCTAssertEqual(StoreUpdates.compare("2", "1.9.9"), .orderedDescending)
    }

    func app(_ bundle: String, _ v: String, source: String = "https://s") -> StoreApp {
        StoreApp(name: bundle, bundleID: bundle, developer: "NCOM", subtitle: "", summary: "", iconURL: nil, tint: nil,
                 screenshots: [], version: v, versionDate: nil, downloadURL: "https://d/\(bundle).ipa", size: nil, minOS: nil,
                 category: "Other", categoryGuessed: false, featured: false, sourceURL: source, sourceName: "S", sourceRank: 0)
    }

    func rec(_ bundle: String, _ v: String, auto: String? = nil) -> StoreInstallRecord {
        StoreInstallRecord(bundleID: bundle, name: bundle, version: v, tool: "SideStore", sourceURL: "https://s",
                           handedOffAt: Date(timeIntervalSince1970: 0), autoHandedOffVersion: auto)
    }

    func testUpdatesAndAutoHandoff() {
        let apps = [app("com.ncom.music", "0.2.0"), app("com.ncom.music", "0.2.1", source: "https://mirror"),
                    app("x.same", "1.0"), app("y.notInstalled", "9.0")]
        let installed = ["com.ncom.music": rec("com.ncom.music", "0.1.0"), "x.same": rec("x.same", "1.0.0")]
        let up = StoreUpdates.available(apps, installed: installed)
        XCTAssertEqual(up.map(\.bundleID), ["com.ncom.music"])
        XCTAssertEqual(up.first?.version, "0.2.1", "the highest listed version wins")
        // Auto-update defaults on; off stops it; one version is handed off once.
        XCTAssertEqual(StoreUpdates.autoHandoffs(apps, installed: installed, autoUpdate: [:]).count, 1)
        XCTAssertEqual(StoreUpdates.autoHandoffs(apps, installed: installed, autoUpdate: ["com.ncom.music": false]).count, 0)
        let done = ["com.ncom.music": rec("com.ncom.music", "0.1.0", auto: "0.2.1")]
        XCTAssertEqual(StoreUpdates.autoHandoffs(apps, installed: done, autoUpdate: [:]).count, 0)
        XCTAssertEqual(StoreUpdates.available(apps, installed: done).count, 1, "still offered by hand")
    }

    func testSavedListsGainNCOMOnce() {
        let legacy = StoreSource.defaults.dropFirst().map { $0 }
        // Fresh install: the defaults as they are.
        let fresh = StoreSource.merging(saved: nil, seenDefaults: nil)
        XCTAssertEqual(fresh.sources.first?.name, "NCOM")
        // A list saved before NCOM existed (one source removed, one added): NCOM goes in first,
        // the removed one stays removed, the user's own stays.
        let mine = StoreSource(url: "https://example.com/mine.json", name: "Mine")
        let saved = Array(legacy.dropLast()) + [mine]
        let m = StoreSource.merging(saved: saved, seenDefaults: nil)
        XCTAssertEqual(m.sources.first?.url, StoreSource.ncomURL)
        XCTAssertFalse(m.sources.contains { $0.url == legacy.last!.url })
        XCTAssertTrue(m.sources.contains(mine))
        XCTAssertEqual(Set(m.seen), Set(StoreSource.defaults.map(\.url)))
        // Removing NCOM later sticks.
        let again = StoreSource.merging(saved: Array(m.sources.dropFirst()), seenDefaults: m.seen)
        XCTAssertFalse(again.sources.contains { $0.url == StoreSource.ncomURL })
    }
}
