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

        // v0.5: the Ouija Board is its own app; Discipline's row leads to the hand-off page.
        tap("more.ouija")
        XCTAssertTrue(el("ouija.handoff").waitForExistence(timeout: 5))
    }
}
