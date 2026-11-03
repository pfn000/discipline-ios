import XCTest

/// NCOM's own source, built into the store: NCOM Music listed by NCOM with its In Development tag, the
/// Updates row (an earlier hand-off at 0.1.0 is seeded), and the per-app Auto-update switch.
/// Reads the live NCOM source on the network, like the storefront test.
final class StoreNCOMUITests: DisciplineUITestCase {
    func testNCOMSourceListingTagAndAutoUpdate() {
        launch(["-uiTestingResetStore", "-uiTestingStoreInstalled", "com.ncom.music=0.1.0"])
        tab("Store Apps")
        let row = el("store.updateRow.NCOM Music")
        XCTAssertTrue(row.waitForExistence(timeout: 90),
                      el("store.empty").exists ? "the store loaded no sources" : "NCOM Music never showed as an update")
        XCTAssertTrue(row.label.contains("In Development"), "row label: \(row.label)")
        XCTAssertTrue(row.label.contains("NCOM"), "row label: \(row.label)")
        XCTAssertTrue(row.label.contains("Update"), "row label: \(row.label)")
        sleep(4)   // icons
        snap("70-store-ncom-updates")

        // The All apps list: NCOM's source is first, so NCOM Music leads it.
        let listed = el("store.app.NCOM Music")
        scrollTo(listed, maxSwipes: 20)
        XCTAssertTrue(listed.exists, "NCOM Music isn't in All apps")
        XCTAssertTrue(listed.label.contains("In Development"), "list label: \(listed.label)")
        sleep(1)
        snap("71-store-ncom-list")

        // Detail: publisher NCOM, the tag, Auto-update on by default.
        listed.tap()
        XCTAssertTrue(el("store.detail.name").waitForExistence(timeout: 10))
        XCTAssertEqual(el("store.detail.developer").label, "NCOM")
        XCTAssertTrue(el("store.tag").exists, "no In Development tag on the detail page")
        sleep(3)
        snap("72-store-ncom-detail")
        let toggle = app.switches["store.autoUpdate"]
        scrollTo(toggle, maxSwipes: 6)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "no Auto-update switch")
        XCTAssertEqual(toggle.value as? String, "1", "Auto-update should default on")
        XCTAssertTrue(el("store.update").exists, "no Update button for 0.1.0 -> 0.2.0")
        XCTAssertTrue(el("store.installedLine").label.contains("0.1.0"), el("store.installedLine").label)
        snap("73-store-ncom-autoupdate")
        back()

        // Sources: NCOM first, verified.
        if el("store.sources").waitForExistence(timeout: 3) { tap("store.sources") }
        else { let edit = el("store.editSources"); scrollTo(edit, maxSwipes: 20); tap("store.editSources") }
        let ncom = el("source.NCOM")
        XCTAssertTrue(ncom.waitForExistence(timeout: 10), "NCOM isn't in the sources list")
        sleep(1)
        snap("74-store-sources-ncom")
        tap("source.done")
    }
}
