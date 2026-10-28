import XCTest

/// v0.5 storefront: live public sources (read from the network on the simulator), trending, categories,
/// search, detail, Get hand-off, and a broken source failing gracefully.
final class StoreUITests: DisciplineUITestCase {
    func testStorefrontFromLiveSources() {
        launch(["-uiTestingResetStore"])
        tab("Store Apps")
        let trending = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'store.trending.'")).firstMatch
        XCTAssertTrue(trending.waitForExistence(timeout: 90),
                      el("store.empty").exists ? "the store loaded no sources" : "the store never finished loading")
        sleep(3)   // icons
        snap("60-store")
        let name = String(trending.identifier.dropFirst("store.trending.".count))

        // Categories
        let chips = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'store.category.' AND identifier != 'store.category.All'"))
        if chips.firstMatch.waitForExistence(timeout: 5) {
            chips.firstMatch.tap()
            sleep(1)
            snap("61-store-category")
            tap("store.category.All")
        }

        // Search
        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 3) { app.swipeDown(velocity: .slow) }
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no search field")
        field.tap()
        field.typeText(String(name.prefix(12)))
        XCTAssertTrue(el("store.app.\(name)").waitForExistence(timeout: 10), "search didn't find \(name)")
        snap("62-store-search")
        tap("store.app.\(name)")

        // Detail + Get (no SideStore/LiveContainer on the simulator: nothing opens, the link is copied)
        XCTAssertTrue(el("store.detail.name").waitForExistence(timeout: 10))
        sleep(2)
        snap("63-store-detail")
        tap("store.get")
        XCTAssertTrue(el("store.getResult").waitForExistence(timeout: 5))
        back()
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }

        // Sources: add a broken one, the rest keeps working, then remove it.
        tap("store.sources")
        XCTAssertTrue(el("source.newURL").waitForExistence(timeout: 5))
        snap("64-store-sources")
        type("source.newURL", "https://example.invalid/apps.json")
        tap("source.add")
        let msg = el("source.message")
        XCTAssertTrue(msg.waitForExistence(timeout: 60))
        XCTAssertTrue(msg.label.contains("couldn't load"), "broken source: \(msg.label)")
        snap("65-store-broken-source")
        let row = el("source.example.invalid")
        scrollTo(row)
        if row.exists {
            row.swipeLeft()
            let del = app.buttons["Delete"]
            if del.waitForExistence(timeout: 3) { del.tap() }
            XCTAssertTrue(row.waitForNonExistence(timeout: 5), "the source wasn't removed")
        }
        tap("source.done")
        XCTAssertTrue(trending.waitForExistence(timeout: 10), "the store kept working")
        // The summary sits in the list footer ("N apps from X of Y sources").
        let summary = el("store.summary")
        scrollTo(summary, maxSwipes: 15)
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "no store summary")
        snap("66-store-summary")
    }
}

/// "Sign in with Ouija / NCOM". CI runs testNoOuijaShowsInstallPrompt BEFORE the Ouija app is installed on
/// the simulator, and the round trip AFTER the Ouija UI tests installed it.
final class SignInWithOuijaUITests: DisciplineUITestCase {
    func testNoOuijaShowsInstallPrompt() {
        launch(["-uiTestingResetOuijaLink"])
        tab("More")
        XCTAssertTrue(el("ouijaSignIn.install").waitForExistence(timeout: 10), "expected the Install Ouija prompt")
        XCTAssertFalse(el("ouijaSignIn.button").exists)
        snap("70-signin-install-ouija")
    }

    func testSignInWithOuijaRoundTrip() {
        launch(["-uiTestingResetOuijaLink"])
        tab("More")
        let button = el("ouijaSignIn.button")
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Ouija should be installed for this test")
        snap("71-signin-with-ouija-button")
        button.tap()

        let ouija = XCUIApplication(bundleIdentifier: "com.ncom.ouija")
        XCTAssertTrue(ouija.wait(for: .runningForeground, timeout: 20), "Ouija didn't open")
        // A fresh Ouija shows Attention and the Agreement first.
        let iAgree = ouija.buttons["ouija.iAgree"]
        if iAgree.waitForExistence(timeout: 5) { iAgree.tap() }
        let handle = ouija.descendants(matching: .any)["agreement.handle"]
        if handle.waitForExistence(timeout: 5) {
            let terms = ouija.descendants(matching: .any)["agreement.terms"]
            for _ in 0..<8 where (handle.value as? String) == "locked" { terms.swipeUp() }
            handle.slide(by: 330)
        }
        let sheet = ouija.descendants(matching: .any)["authorize.title"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 15), "no authorize sheet in Ouija")
        sleep(1)
        snap("72-ouija-authorize-from-discipline")
        let ah = ouija.descendants(matching: .any)["authorize.handle"]
        ah.slide(by: 330)

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "Discipline didn't come back")
        let account = el("ouijaSignIn.account")
        XCTAssertTrue(account.waitForExistence(timeout: 10), "not signed in after Ouija's answer")
        snap("73-signed-in-with-ouija")
    }
}
