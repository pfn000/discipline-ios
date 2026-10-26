import XCTest

/// Controls no other test reached (found by matching every accessibility identifier in App/Sources against UITests):
/// the NCOM code scanner sheet, the Updates screen's manual check and auto-check switch, and the Ouija Board settings sheet.
final class CoverageUITests: DisciplineUITestCase {
    func testRemainingButtonsAndPages() {
        launch(["-uiTestingOuijaUnlocked", "-uiTestingMockGitHub"])

        // Scanner sheet: the simulator has no camera, so the photo route and the explanation show.
        openMore("more.scanQR")
        XCTAssertTrue(el("scan.photo").waitForExistence(timeout: 10), "scanner sheet did not open")
        XCTAssertTrue(el("scan.noCamera").exists)
        snap("50-scanner-sheet")
        tap("scan.close")
        XCTAssertTrue(el("scan.photo").waitForNonExistence(timeout: 5), "scanner sheet did not close")

        // Updates: the manual check button and the auto-check switch.
        tap("more.updates")
        XCTAssertTrue(el("updates.installed").waitForExistence(timeout: 5))
        tap("updates.check")
        let auto = app.switches["updates.autoCheck"].firstMatch
        if !auto.waitForExistence(timeout: 3) { scrollTo(auto) }
        let before = auto.value as? String
        flip("updates.autoCheck")
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, (auto.value as? String) == before { usleep(150_000) }
        XCTAssertNotEqual(auto.value as? String, before, "auto-check switch did not change")
        flip("updates.autoCheck") // put it back
        snap("51-updates")
        back()

        // Ouija Board settings sheet: Done, then "Show the Attention page again".
        tap("more.ouija")
        if el("ouija.attention").waitForExistence(timeout: 5) {
            app.sliders["ouija.slide"].firstMatch.adjust(toNormalizedSliderPosition: 1.0)
            tap("ouija.agree")
        }
        XCTAssertTrue(el("ouija.deviceName").waitForExistence(timeout: 5))
        tap("ouija.settings")
        XCTAssertTrue(el("ouija.settingsDone").waitForExistence(timeout: 5), "settings sheet did not open")
        snap("52-ouija-settings")
        tap("ouija.settingsDone")
        XCTAssertTrue(el("ouija.settingsDone").waitForNonExistence(timeout: 5))
        tap("ouija.settings")
        tap("ouija.resetAgreement")
        XCTAssertTrue(el("ouija.attention").waitForExistence(timeout: 5), "the Attention page should show again")
    }
}
