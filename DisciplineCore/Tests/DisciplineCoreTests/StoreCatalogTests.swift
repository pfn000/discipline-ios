import XCTest
@testable import DisciplineCore

final class StoreCatalogTests: XCTestCase {
    func fixture() throws -> [String: Any] {
        let url = Bundle.module.url(forResource: "store-fixture", withExtension: "json", subdirectory: "Fixtures")!
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        return obj["sources"] as! [String: Any]
    }
    func allApps() throws -> [StoreApp] {
        var apps: [StoreApp] = []
        for (url, src) in try fixture().sorted(by: { $0.key < $1.key }) {
            let data = try JSONSerialization.data(withJSONObject: src)
            apps += try StoreCatalog.parse(data, sourceURL: url, fallbackName: "x").apps
        }
        return apps
    }

    func testRealSourcesParse() throws {
        let apps = try allApps()
        XCTAssertGreaterThanOrEqual(apps.count, 20)
        XCTAssertTrue(apps.allSatisfy { !$0.downloadURL.isEmpty && !$0.name.isEmpty })
        let delta = try XCTUnwrap(apps.first { $0.name == "Delta" })
        XCTAssertEqual(delta.sourceName, "AltStore")
        XCTAssertNotNil(delta.versionDate)
        XCTAssertTrue(apps.contains { $0.featured }, "AltStore's featuredApps should mark apps")
        XCTAssertTrue(apps.contains { $0.gitHubRepo != nil })
    }

    func testBrokenSourcesThrow() {
        XCTAssertThrowsError(try StoreCatalog.parse(Data("<html>".utf8), sourceURL: "https://x.y", fallbackName: "x"))
        XCTAssertThrowsError(try StoreCatalog.parse(Data("{\"apps\":[]}".utf8), sourceURL: "https://x.y", fallbackName: "x"))
    }

    func testLegacyAndScarletFormats() throws {
        let legacy = #"{"name":"Old","apps":[{"name":"A","bundleIdentifier":"a.b","version":"1.2","versionDate":"2026-01-02","downloadURL":"https://github.com/o/r/releases/download/v1/A.ipa","size":"123"}]}"#
        let a = try StoreCatalog.parse(Data(legacy.utf8), sourceURL: "https://old", fallbackName: "x").apps[0]
        XCTAssertEqual(a.version, "1.2"); XCTAssertEqual(a.size, 123); XCTAssertEqual(a.gitHubRepo, "o/r")
        let scarlet = #"{"META":{"repoName":"Sc"},"Tweaked":[{"name":"T","version":"2","icon":"https://i","down":"https://d/T.ipa","bundleID":"t.t"}]}"#
        let s = try StoreCatalog.parse(Data(scarlet.utf8), sourceURL: "https://sc", fallbackName: "x")
        XCTAssertEqual(s.name, "Sc"); XCTAssertEqual(s.apps[0].category, "Tweaked"); XCTAssertFalse(s.apps[0].categoryGuessed)
    }

    func testTrendingUsesOnlyRealSignals() throws {
        let apps = try allApps()
        let now = StoreCatalog.parseDate("2026-10-28")!
        let top = StoreCatalog.trending(apps, stars: [:], now: now)
        XCTAssertFalse(top.isEmpty)
        // With no stars known, a featured, recently released app beats an old unfeatured one.
        let fresh = StoreCatalog.Signals(featured: true, daysSinceRelease: 3, stars: nil)
        let old = StoreCatalog.Signals(featured: false, daysSinceRelease: 900, stars: nil)
        XCTAssertGreaterThan(StoreCatalog.trendingScore(fresh), StoreCatalog.trendingScore(old))
        XCTAssertGreaterThan(StoreCatalog.trendingScore(.init(featured: false, daysSinceRelease: nil, stars: 50_000)),
                             StoreCatalog.trendingScore(.init(featured: false, daysSinceRelease: nil, stars: 10)))
    }

    func testSearchCategoriesAndDedupe() throws {
        let apps = try allApps()
        XCTAssertTrue(StoreCatalog.search(apps, "delta").contains { $0.name == "Delta" })
        XCTAssertTrue(StoreCatalog.search(apps, "zzzz-nothing").isEmpty)
        XCTAssertFalse(StoreCatalog.categories(apps).isEmpty)
        XCTAssertLessThanOrEqual(StoreCatalog.dedupe(apps + apps).count, apps.count)
        XCTAssertEqual(StoreCatalog.guessCategory(name: "PPSSPP", subtitle: "PSP emulator"), "Emulators")
    }

    func testSourceURLValidation() {
        XCTAssertNotNil(StoreCatalog.validateSourceURL(" https://example.com/apps.json "))
        XCTAssertNil(StoreCatalog.validateSourceURL("http://example.com/apps.json"))
        XCTAssertNil(StoreCatalog.validateSourceURL("not a url"))
        XCTAssertEqual(StoreSource.defaults.count, 10)
    }
}
