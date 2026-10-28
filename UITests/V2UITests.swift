import XCTest

/// v0.3: auto refresh, read expiry, auto-update, the NCOM QR magic ring, the saved unlock and the Ouija Board screens.
final class AutoRefreshUITests: DisciplineUITestCase {
    /// An app with 1 day left: opening Discipline starts SideStore's refresh by itself (no reminder, no button).
    func testAutoRefreshStartsByItselfWhenDue() {
        launch(["-uiTestingDueApp", "-uiTestingFakeCompanions"])
        expectToast(contains: "Sent to LocalDevVPN")
        XCTAssertEqual(el("toast").value as? String, "localdevvpn://enable?scheme=sidestore")
        dismissToast()
        tab("Expiry")
        XCTAssertEqual(app.switches["expiry.autoRefresh"].firstMatch.value as? String, "1", "auto refresh is on by default")
        let status = el("expiry.autoStatus")
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("refreshing SideStore") || status.label.contains("refresh started recently"), status.label)
        XCTAssertFalse(el("expiry.reminders").exists, "the reminder switch is gone")
        snap("30-auto-refresh-due")
    }

    func testAutoRefreshOffDoesNothingUntilTurnedOn() {
        launch(["-uiTestingDueApp", "-uiTestingFakeCompanions", "-uiTestingAutoRefreshOff"])
        tab("Expiry")
        let status = el("expiry.autoStatus")
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "Off")
        XCTAssertFalse(el("toast").exists, "nothing was opened while auto refresh is off")
        flip("expiry.autoRefresh")
        expectToast(contains: "Sent to LocalDevVPN")
        dismissToast()
        XCTAssertTrue(el("expiry.ownSignature").exists, "Discipline says whether it could read its own signature")
        snap("31-auto-refresh-on")
    }

    /// A signed .ipa carries its provisioning profile: tracking it needs no typed date.
    func testSignedIPAExpiryIsRead() {
        launch(["-uiTestingSeedSigned", "-uiTestingAutoRefreshOff"])
        tab("Library")
        tap("library.item.com.ncom.signedsample")
        XCTAssertTrue(el("ipa.name").waitForExistence(timeout: 10))
        tap("ipa.track")
        expectToast(contains: "expiry read from its signature")
        dismissToast()
        XCTAssertFalse(el("add.save").exists, "no date sheet for a signed app")
        tab("Expiry")
        XCTAssertTrue(el("expiry.read.com.ncom.signedsample").waitForExistence(timeout: 5))
        snap("32-expiry-read-from-signature")
    }
}

final class UpdatesUITests: DisciplineUITestCase {
    /// Launch check (automatic): Discipline's own newer release with its notes, and saved repos where one fails.
    func testAutomaticUpdateCheckAndSelfUpdate() {
        launch(["-uiTestingMockGitHub", "-uiTestingAutoCheck", "-uiTestingSeedRepos", "-uiTestingFakeCompanions"])
        // The saved-repo check runs after the self check; one 404 repo must not stop the others.
        expectToast(contains: "1 update available")
        XCTAssertTrue(el("toast").label.contains("couldn't check missing/repo"), el("toast").label)
        dismissToast()
        tab("GitHub")
        XCTAssertTrue(el("github.updateBadge.sample-app").waitForExistence(timeout: 5))
        openMore("more.updates")
        // The fixture's "newer" release is v99.0.0 so it stays newer than any real version (CI #26 went red when
        // the app caught up with a v0.3.1 fixture).
        XCTAssertEqual(el("updates.status").label, "Discipline 99.0.0 is available")
        XCTAssertTrue(el("updates.notes").label.contains("what's new in 99.0.0"))
        snap("33-updates-available")
        tap("updates.download")
        XCTAssertTrue(el("ipa.name").waitForExistence(timeout: 15))
        snap("34-update-downloaded")
    }

    func testAutoDownloadPutsNewVersionsInLibrary() {
        launch(["-uiTestingMockGitHub", "-uiTestingAutoCheck", "-uiTestingSeedRepos", "-uiTestingAutoDownload"])
        expectToast(contains: "downloaded to Library")
        dismissToast()
        tab("Library")
        XCTAssertTrue(el("library.item.com.ncom.sampleapp").waitForExistence(timeout: 10))
        openMore("more.updates")
        // The Automatic section sits below the release notes; Lists unload rows off screen, so scroll to it.
        let autoDownload = app.switches["updates.autoDownload"].firstMatch
        if !autoDownload.waitForExistence(timeout: 3) { scrollTo(autoDownload) }
        XCTAssertTrue(autoDownload.waitForExistence(timeout: 5), "missing switch updates.autoDownload")
        XCTAssertEqual(autoDownload.value as? String, "1")
    }
}

final class OuijaUITests: DisciplineUITestCase {
    /// The pairing result row sits under the Start button; a List can leave it unloaded below the fold.
    func shown(_ id: String) -> XCUIElement {
        let e = el(id)
        if !e.waitForExistence(timeout: 3) { scrollTo(e, maxSwipes: 8) }
        _ = e.waitForExistence(timeout: 3)
        return e
    }

    // Signed by the UI-test key, which the app accepts only while it runs under -uiTesting.
    static let testCode = "NCOM1.eyJ2IjoxLCJpc3MiOiJOQ09NIFN5c3RlbXMiLCJzdWIiOiJPdWlqYSBCb2FyZCIsImlhdCI6MTc5MjkwMDAwMCwibiI6IjAwMTEyMjMzNDQ1NTY2NzcifQ.OH9zMowlq5wy6fAT2xPHhrzPHN6CrefXrkBHy4_xAxeBit-GHPXi2IL5zbN9AtiyhRUOognhKX4U-QDiH8uZDw"
    // Same message, signed by a different key: must be refused.
    static let foreignCode = "NCOM1.eyJ2IjoxLCJpc3MiOiJOQ09NIFN5c3RlbXMiLCJzdWIiOiJPdWlqYSBCb2FyZCIsImlhdCI6MTc5MjkwMDAwMCwibiI6IjAwMTEyMjMzNDQ1NTY2NzcifQ.xW9l6zENePvoOjNpwDLcUMnVtZUUeWh9Fcqe9loeYTRDD8YnQjdA1VrP3Ak4zyOgpoe5g81zuhEnzJVGW-CcDg"

    /// The Camera app opens discipline://ouija?code=… : the rings dance, the code is signed off, Ouija Board opens.
    func testSignedQRCodeUnlocksWithMagicRing() {
        launch(["-uiTestingOuijaCode", Self.testCode])
        XCTAssertTrue(el("ouija.magicRing").waitForExistence(timeout: 10))
        snap("35-magic-ring")
        let msg = el("ouija.ringMessage")
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline, !(msg.exists && msg.label.contains("Signed")) { usleep(150_000) }
        XCTAssertTrue(msg.exists && msg.label.hasPrefix("Signed"), "ring did not sign off")
        snap("36-magic-ring-signed")
        XCTAssertTrue(el("ouija.attention").waitForExistence(timeout: 10), "Ouija Board opens after the ring")
        back()
        XCTAssertTrue(el("more.ouija").waitForExistence(timeout: 5))
        XCTAssertTrue(el("more.lab").exists)
    }

    func testForeignQRCodeIsRefused() {
        launch(["-uiTestingOuijaCode", Self.foreignCode])
        XCTAssertTrue(el("ouija.magicRing").waitForExistence(timeout: 10))
        expectToast(contains: "isn't signed by NCOM")
        tab("More")
        XCTAssertFalse(el("more.ouija").exists)
        XCTAssertFalse(el("more.lab").exists)
    }

    /// 25 taps unlock, and the unlock is still there after the app is closed and opened again.
    func testTwentyFiveTapUnlockIsSaved() {
        launch(["-uiTestingStateDir", "unlock", "-uiTestingResetState"])
        tab("More")
        XCTAssertFalse(el("more.ouija").exists)
        let version = el("more.version")
        scrollTo(version)
        for _ in 0..<25 { version.tap() }
        expectToast(contains: "Ouija Board developer preview unlocked")
        XCTAssertTrue(el("more.ouija").waitForExistence(timeout: 5))
        app.terminate()
        launch(["-uiTestingStateDir", "unlock"])
        tab("More")
        XCTAssertTrue(el("more.ouija").waitForExistence(timeout: 5), "unlock survives a relaunch")
        XCTAssertTrue(el("more.lab").exists)
    }

    /// The legacy 7 long presses still unlock (kept from v0.1).
    func testSevenLongPressesStillUnlock() {
        launch()
        tab("More")
        XCTAssertFalse(el("more.lab").exists, "Lab starts hidden")
        let version = el("more.version")
        scrollTo(version)
        for _ in 0..<7 { version.press(forDuration: 0.6) }
        expectToast(contains: "NCOM Lab unlocked")
        dismissToast()
        XCTAssertTrue(el("more.lab").waitForExistence(timeout: 5))
        tap("more.lab")
        XCTAssertTrue(el("lab.tier").waitForExistence(timeout: 5))
    }

    /// The sketch pages: Attention (slide), Agreement (agree button), the board, pairing, the shell.
    /// NCOM's words are private (CI copies them in), so this test checks identifiers, not wording,
    /// and never prints a label.
    func testOuijaBoardScreensFromSketch() {
        launch(["-uiTestingOuijaUnlocked", "-uiTestingSeedLibrary"])
        openMore("more.ouija")
        XCTAssertTrue(el("ouija.attention").waitForExistence(timeout: 5))
        XCTAssertEqual(el("ouija.warning").label, "Ouija Board is only meant for NCOM developers.")
        snap("37-ouija-attention")
        app.sliders["ouija.slide"].firstMatch.adjust(toNormalizedSliderPosition: 1.0)
        XCTAssertTrue(el("ouija.agreement").waitForExistence(timeout: 5))
        XCTAssertTrue(el("ouija.signedIn").exists)
        snap("38-ouija-agreement")
        tap("ouija.agree")
        XCTAssertTrue(el("ouija.deviceName").waitForExistence(timeout: 5))
        XCTAssertFalse(el("ouija.deviceName").label.isEmpty)
        let source = el("ouija.contentSource")
        scrollTo(source)
        XCTAssertEqual(source.value as? String, "private", "CI must build with NCOM's private content")
        for i in 1...12 { XCTAssertTrue(el("ouija.tile.\(i)").exists, "tile \(i)") }
        snap("39-ouija-board")
        tap("ouija.tile.3")
        XCTAssertTrue(el("ouija.status").label.hasPrefix("Tile 3: prototype feature."))
        XCTAssertTrue(el("ouija.status").label.hasSuffix("Not connected."))
        app.segmentedControls["ouija.session"].buttons.element(boundBy: 1).tap()
        tap("ouija.connection")
        XCTAssertTrue(el("pair.instructions").waitForExistence(timeout: 5))
        for i in 1...6 { XCTAssertTrue(el("pair.option.opt\(i)").exists, "pairing option \(i)") }
        tap("pair.start")
        XCTAssertEqual(shown("pair.result").label, "Choose an option first.")
        tap("pair.option.opt4")   // the local-network option: a real Bonjour search (instant and empty under tests)
        tap("pair.start")
        let result = shown("pair.result")
        XCTAssertTrue(result.exists)
        XCTAssertEqual(result.label, "No NCOM devices found on this network.")
        snap("40-start-searching")
        tap("pair.option.opt5")   // a hardware-only option
        tap("pair.start")
        XCTAssertTrue(shown("pair.result").label.hasSuffix("needs NCOM prototype hardware. Nothing is paired."))
        tap("pair.option.opt1")   // the UWB option
        tap("pair.start")
        XCTAssertTrue(shown("pair.result").label.contains("Nearby Interaction"))
        back()
        XCTAssertTrue(el("ouija.deviceName").waitForExistence(timeout: 5))
        let field = el("ouija.shellInput")
        scrollTo(field)
        type("ouija.shellInput", "apps")
        tap("ouija.shellSend")
        XCTAssertEqual(el("ouija.shellOutput").label, "2 IPA files in Discipline's Library; none run inside Discipline.")
        hideKeyboard()
        snap("41-ouija-shell")
        // The agreement is remembered: leaving and coming back goes straight to the board.
        back()
        tap("more.ouija")
        XCTAssertTrue(el("ouija.deviceName").waitForExistence(timeout: 5))
        XCTAssertFalse(el("ouija.attention").exists)
    }
}
