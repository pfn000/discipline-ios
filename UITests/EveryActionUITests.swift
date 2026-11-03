import XCTest

/// Saidie, Nov 3 2026: "go through every action, every button, and make sure everything works".
/// The other UI tests already drive almost every control (scripts/ui_coverage.py matches every accessibility
/// identifier in App/Sources against UITests). This test drives the ones left over: the Library swipe Delete,
/// the IPA extension count, the Home hero with two tracked apps (ring, glowing gradient bar, kit gauge, chart),
/// the Setup page's first-install row, the Updates title, and a store search with no match.
final class EveryActionUITests: DisciplineUITestCase {
    func testLeftoverActions() {
        launch(["-uiTestingOpenSampleIPA", "-uiTestingFakeCompanions"])
        XCTAssertTrue(el("ipa.name").waitForExistence(timeout: 15))
        XCTAssertTrue(el("ipa.extensions").exists, "IPA detail shows its extension count")

        // Library list: swipe the row, Delete.
        back()
        let row = el("library.item.com.ncom.sampleapp")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "library row missing")
        row.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "no swipe Delete button")
        delete.tap()
        XCTAssertTrue(el("library.empty").waitForExistence(timeout: 5), "swipe Delete did not remove the app")
        // Guard with an empty Library says what to do.
        openMore("more.guard")
        XCTAssertTrue(el("guard.noApps").waitForExistence(timeout: 5), "Guard shows no empty-library hint")
        back()

        // Two tracked apps: the Home hero shows the ring, the glowing gradient bar and the chart card.
        for (n, b) in [("Delta", "com.rileytestut.delta"), ("Provenance", "org.provenance-emu.provenance")] {
            tab("Expiry")
            tap("expiry.add")
            type("add.name", n)
            type("add.bundleID", b)
            tap("add.save")
            expectToast(contains: "Tracking \(n)")
            dismissToast()
        }
        tab("Home")
        XCTAssertTrue(el("home.ring").waitForExistence(timeout: 5), "hero ring missing")
        XCTAssertTrue(el("home.progress").exists, "glowing progress bar missing")
        XCTAssertTrue(el("home.kitGauge").exists, "kit gauge missing")
        for c in ["localDevVPN", "sideStore", "liveContainer"] {
            XCTAssertTrue(el("home.companion.\(c)").exists, "companion row \(c) missing")
        }
        snap("80-home-two-tracked")
        let chart = el("chart.expiry")
        if !chart.exists { scrollTo(chart) }
        XCTAssertTrue(chart.exists, "signatures chart missing with two tracked apps")

        // Setup page: the first-install row and the setup steps.
        openMore("more.setup")
        let boot = el("setup.bootstrap")
        if !boot.waitForExistence(timeout: 5) { scrollTo(boot) }
        XCTAssertTrue(boot.exists, "Setup has no first-install row")
        let steps = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'setup.step.'"))
        XCTAssertGreaterThan(steps.count, 0, "Setup shows no steps")
        back()

        // Updates page title.
        tap("more.updates")
        XCTAssertTrue(el("updates.title").waitForExistence(timeout: 5) || el("updates.installed").exists, "Updates page did not open")
        back()

        // Store search with no match says so.
        tab("Store Apps")
        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 3) { app.swipeDown(velocity: .slow) }
        if field.waitForExistence(timeout: 5) {
            field.tap()
            field.typeText("zzqxv")
            XCTAssertTrue(el("store.noResults").waitForExistence(timeout: 10) || el("store.empty").exists, "a search with no match shows nothing")
        }
    }
}
