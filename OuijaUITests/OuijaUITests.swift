import XCTest

/// The Ouija app: Attention (single "I agree"), the Agreement (slider locked until the terms are scrolled
/// to the end, then the profile slide), the board, the authorize sheet + Live Activity, and the ring sign-in.
final class OuijaAgreementUITests: DisciplineUITestCase {
    func testAttentionThenAgreementLockedUntilScrolled() {
        launch(["-uiTestingResetState", "-uiTestingProfileName", "Saidie Newara"])
        XCTAssertTrue(el("ouija.attention").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["ouija.iAgree"].exists, "Attention has one I agree button")
        XCTAssertEqual(app.sliders.count, 0, "no slider on Attention any more")
        snap("80-ouija-attention-after")
        tap("ouija.iAgree")

        let handle = el("agreement.handle")
        XCTAssertTrue(handle.waitForExistence(timeout: 10))
        XCTAssertEqual(handle.value as? String, "locked", "slider must start locked")
        // Dragging while locked does nothing.
        handle.press(forDuration: 0.2, thenDragTo: handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 320, dy: 0)))
        XCTAssertEqual(handle.value as? String, "locked", "a drag before scrolling must not agree")
        XCTAssertTrue(el("ouija.agreement").exists)
        snap("81-ouija-agreement-locked")

        let terms = el("agreement.terms")
        for _ in 0..<10 where (handle.value as? String) == "locked" { terms.swipeUp() }
        XCTAssertEqual(handle.value as? String, "unlocked", "scrolling to the end unlocks the slider")
        snap("82-ouija-agreement-unlocked")

        handle.press(forDuration: 0.2, thenDragTo: handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 330, dy: 0)))
        XCTAssertEqual(handle.value as? String, "agreed")
        XCTAssertTrue(el("agreement.status").label.hasPrefix("Agreed "), "the time is recorded: \(el("agreement.status").label)")
        snap("83-ouija-agreement-agreed")
        XCTAssertTrue(el("ouija.deviceName").waitForExistence(timeout: 10), "board opens after agreeing")

        // The agreement time is kept (Keys tab).
        tab("Keys")
        XCTAssertTrue(el("keys.agreedAt").waitForExistence(timeout: 5))
    }

    func testBoardAndSettings() {
        launch(["-uiTestingResetState", "-uiTestingAgreed"])
        XCTAssertTrue(el("ouija.deviceName").waitForExistence(timeout: 10))
        snap("84-ouija-board")
        tap("ouija.connection")
        XCTAssertTrue(el("pair.instructions").waitForExistence(timeout: 5))
        tap("pair.start")
        XCTAssertTrue(el("pair.result").waitForExistence(timeout: 5))
        back()
        tap("ouija.settings")
        XCTAssertTrue(el("ouija.settingsDone").waitForExistence(timeout: 5))
        snap("85-ouija-settings")
        tap("ouija.resetAgreement")
        XCTAssertTrue(el("ouija.attention").waitForExistence(timeout: 5), "the Attention page shows again")
    }
}

final class OuijaAuthorizeUITests: DisciplineUITestCase {
    static let request = "ouija://authorize?client=Discipline&nonce=00112233445566778899aabbccddeeff&callback=discipline%3A%2F%2Fouija-callback"

    func testAuthorizeSheetAndLiveActivity() {
        launch(["-uiTestingResetState", "-uiTestingAgreed", "-uiTestingProfileName", "Saidie Newara", "-uiTestingOpenURL", Self.request])
        XCTAssertTrue(el("authorize.title").waitForExistence(timeout: 10))
        XCTAssertEqual(el("authorize.title").label, "Discipline wants to sign in to your account")
        XCTAssertEqual(el("authorize.account").label, "Saidie Newara")
        sleep(1)
        snap("86-ouija-authorize-sheet")

        // The Live Activity (Dynamic Island on Pro simulators, banner on the Lock Screen).
        XCUIDevice.shared.press(.home)
        sleep(3)
        snap("87-live-activity-island")
        app.activate()
        XCTAssertTrue(el("authorize.handle").waitForExistence(timeout: 10))

        let h = el("authorize.handle")
        h.press(forDuration: 0.2, thenDragTo: h.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 330, dy: 0)))
        XCTAssertEqual(h.value as? String, "agreed")
        snap("88-ouija-authorize-approved")
    }

    func testBadLinkIsRefused() {
        launch(["-uiTestingResetState", "-uiTestingAgreed", "-uiTestingOpenURL", "ouija://authorize?client=Evil&nonce=short&callback=https%3A%2F%2Fevil.example"])
        XCTAssertTrue(el("ouija.deviceName").waitForExistence(timeout: 10))
        XCTAssertFalse(el("authorize.title").waitForExistence(timeout: 3), "an https callback must be refused")
    }
}

final class OuijaRingUITests: DisciplineUITestCase {
    func testRingSignInAcceptsEnrolledKey() {
        launch(["-uiTestingResetState", "-uiTestingAgreed", "-uiTestingTab", "rings", "-uiTestingRingFrames"])
        XCTAssertTrue(el("rings.dance").waitForExistence(timeout: 10))
        snap("90-rings-idle")
        tap("rings.find")
        XCTAssertTrue(el("rings.prompt").waitForExistence(timeout: 10), "no 'point the camera' prompt")
        snap("91-rings-found-point-camera")
        tap("rings.scan")
        XCTAssertTrue(el("rings.viewfinder").waitForExistence(timeout: 5))
        sleep(1)
        snap("92-rings-scanning")
        XCTAssertTrue(el("rings.success").waitForExistence(timeout: 40), "the rings were not accepted")
        sleep(1)
        snap("93-rings-success")
    }

    func testRingSignInRefusesUnknownKey() {
        launch(["-uiTestingResetState", "-uiTestingAgreed", "-uiTestingTab", "rings", "-uiTestingRingForeign"])
        tap("rings.find")
        tap("rings.scan", timeout: 15)
        XCTAssertTrue(el("rings.failure").waitForExistence(timeout: 40), "a key that isn't enrolled must fail")
        XCTAssertTrue(el("rings.reason").label.contains("isn't enrolled"))
        sleep(1)
        snap("94-rings-failure")
    }

    func testKeysAndProfile() {
        launch(["-uiTestingResetState", "-uiTestingAgreed", "-uiTestingTab", "keys", "-uiTestingProfileName", "Saidie Newara"])
        XCTAssertTrue(el("keys.empty").waitForExistence(timeout: 10))
        type("keys.newName", "Studio Mac")
        type("keys.newKey", "NCOMKEY1.not-a-key")
        tap("keys.enroll")
        XCTAssertEqual(el("keys.message").label, "That isn't an NCOMKEY1 key.")
        type("keys.newKey", "NCOMKEY1.11qYAYKxCrfVS_7TyWQHOg7hcvPapiMlrwIaaPcHURo", clear: true)
        tap("keys.enroll")
        XCTAssertEqual(el("keys.message").label, "Enrolled.")
        hideKeyboard()
        snap("95-ouija-keys")
    }
}
