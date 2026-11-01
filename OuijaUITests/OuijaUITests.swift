import XCTest

/// The Ouija app: Attention (single "I agree"), the account (typed, never pre-filled), the Agreement (slider locked until the terms are scrolled
/// to the end, then the profile slide), the board, the authorize sheet + Live Activity, and the ring sign-in.
final class OuijaAgreementUITests: DisciplineUITestCase {
    /// No made-up user or device anywhere on the way in.
    func assertNoPlaceholders(_ where_: String) {
        // Case-sensitive: the real button "NCOM developer? Tap your ID card" must not count as the old fake name.
        for fake in ["Focals", "NCOM Developer", "Prototype device"] {
            let hit = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", fake)).firstMatch
            XCTAssertFalse(hit.exists, "placeholder '\(fake)' shown on \(where_)")
        }
    }

    func testAttentionThenAccountThenAgreementLockedUntilScrolled() {
        launch(["-uiTestingResetState"])
        XCTAssertTrue(el("ouija.attention").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["ouija.iAgree"].exists, "Attention has one I agree button")
        XCTAssertEqual(app.sliders.count, 0, "no slider on Attention any more")
        snap("80-ouija-attention-after")
        tap("ouija.iAgree")

        // The account page: empty name, nothing pre-filled, Continue disabled until a name is typed.
        XCTAssertTrue(el("ouija.account").waitForExistence(timeout: 10), "account page after Attention")
        let field = app.textFields["account.name"]
        XCTAssertTrue(field.exists)
        let v = field.value as? String ?? ""
        XCTAssertTrue(v.isEmpty || v == (field.placeholderValue ?? ""), "name field must start empty, had '\(v)'")
        XCTAssertFalse(app.buttons["account.continue"].isEnabled, "Continue needs a typed name")
        XCTAssertTrue(el("account.thisDevice").label.contains("iPhone"), "real device: \(el("account.thisDevice").label)")
        note("79-this-device", el("account.thisDevice").label)
        assertNoPlaceholders("the account page")
        snap("79a-ouija-account-empty")
        type("account.name", "Saidie Newara")
        hideKeyboard()
        XCTAssertTrue(app.buttons["account.continue"].isEnabled)
        snap("79b-ouija-account-filled")
        tap("account.continue")

        let handle = el("agreement.handle")
        XCTAssertTrue(handle.waitForExistence(timeout: 10))
        XCTAssertEqual(handle.value as? String, "locked", "slider must start locked")
        XCTAssertTrue(el("agreement.status").label.contains("Saidie Newara"), "the typed name: \(el("agreement.status").label)")
        // Dragging while locked does nothing.
        handle.slide(by: 320)
        XCTAssertEqual(handle.value as? String, "locked", "a drag before scrolling must not agree")
        XCTAssertTrue(el("ouija.agreement").exists)
        snap("81-ouija-agreement-locked")

        let terms = el("agreement.terms")
        for _ in 0..<10 where (handle.value as? String) == "locked" { terms.swipeUp() }
        XCTAssertEqual(handle.value as? String, "unlocked", "scrolling to the end unlocks the slider")
        snap("82-ouija-agreement-unlocked")

        handle.slide(by: 330)
        XCTAssertEqual(handle.value as? String, "agreed", "slide: \(labelIfAny("agreement.handle.trace")), handle \(handle.frame), screen \(app.frame)")
        XCTAssertTrue(el("agreement.status").label.hasPrefix("Agreed "), "the time is recorded: \(el("agreement.status").label)")
        snap("83-ouija-agreement-agreed")
        XCTAssertTrue(el("ouija.deviceName").waitForExistence(timeout: 10), "board opens after agreeing")
        assertNoPlaceholders("the board")

        // The agreement time and where the account is kept (Keys tab).
        tab("Keys")
        let agreedAt = el("keys.agreedAt")   // in "This iPhone", below the account and key sections
        for _ in 0..<8 where !agreedAt.exists { app.swipeUp() }
        XCTAssertTrue(agreedAt.waitForExistence(timeout: 5))
        note("79-account-store", labelIfAny("keys.accountStore"))
    }

    func testAccountIsKeptAcrossRelaunch() {
        launch(["-uiTestingResetState", "-uiTestingAgreed"])
        XCTAssertTrue(el("ouija.account").waitForExistence(timeout: 10), "agreed but no account yet: the account page shows")
        type("account.name", "Saidie Newara")
        hideKeyboard()
        tap("account.continue")
        XCTAssertTrue(el("ouija.deviceName").waitForExistence(timeout: 10))
        app.terminate()
        launch(["-uiTestingAgreed"])   // no reset: the account must still be there
        XCTAssertTrue(el("ouija.deviceName").waitForExistence(timeout: 10), "relaunch goes straight to the board")
        XCTAssertFalse(el("ouija.account").exists)
        XCTAssertEqual(el("ouija.accountAvatar").label, "Saidie Newara")
        // Signing out removes it.
        tap("ouija.settings")
        tap("ouija.signOut")
        XCTAssertTrue(el("ouija.account").waitForExistence(timeout: 10), "signed out: back to the account page")
        XCTAssertEqual((app.textFields["account.name"].value as? String).map { $0 == app.textFields["account.name"].placeholderValue || $0.isEmpty }, true)
    }

    func testBoardAndSettings() {
        launch(["-uiTestingResetState", "-uiTestingAgreed", "-uiTestingProfileName", "Saidie Newara"])
        XCTAssertTrue(el("ouija.deviceName").waitForExistence(timeout: 10))
        let device = el("ouija.deviceName").label
        XCTAssertTrue(device.contains("iPhone"), "the real device: \(device)")
        XCTAssertTrue(el("ouija.deviceDetail").label.contains("iOS"), el("ouija.deviceDetail").label)
        XCTAssertTrue(el("ouija.connection").label.contains("No device connected"), el("ouija.connection").label)
        assertNoPlaceholders("the board")
        note("84-board-device", device + " | " + el("ouija.deviceDetail").label + " | " + el("ouija.connection").label)
        snap("84-ouija-board")
        tap("ouija.tile.1")
        XCTAssertTrue(el("ouija.status").label.contains("isn't wired"), "tiles say plainly they do nothing yet")
        tap("ouija.connection")
        XCTAssertTrue(el("pair.instructions").waitForExistence(timeout: 5))
        tap("pair.option.ble")
        tap("pair.start")
        XCTAssertTrue(el("pair.result").waitForExistence(timeout: 15))
        snap("84b-ouija-pairing")
        back()
        XCTAssertTrue(el("ouija.connection").waitForExistence(timeout: 5))
        XCTAssertTrue(el("ouija.connection").label.contains("No devices found"), "after a real scan that found nothing: \(el("ouija.connection").label)")
        tap("ouija.settings")
        XCTAssertTrue(el("ouija.settingsDone").waitForExistence(timeout: 5))
        snap("85-ouija-settings")
        tap("ouija.resetAgreement")
        XCTAssertTrue(el("ouija.attention").waitForExistence(timeout: 5), "the Attention page shows again")
    }
}

/// Developer sign-in with the NCOM Magic ID card. The simulator has no NFC, so these run against the
/// in-memory NCOM Dev + GlassVault (the same rules as the unit tests); the real tap is untested until an iPhone.
final class OuijaDevCardUITests: DisciplineUITestCase {
    func openCardSheet(_ extra: [String]) {
        launch(["-uiTestingResetState", "-uiTestingMagicKeyMock", "-uiTestingMagicKeyOwner", "Saidie Newara"] + extra)
        tap("ouija.iAgree")
        XCTAssertTrue(el("ouija.account").waitForExistence(timeout: 10))
        tap("account.devCard")
        XCTAssertTrue(el("devcard.start").waitForExistence(timeout: 10))
    }

    func testCardTapAllThreeSayYes() {
        openCardSheet([])
        snap("79c-ouija-devcard-idle")
        tap("devcard.start")
        XCTAssertTrue(el("devcard.agree").waitForExistence(timeout: 15), "the rings dance when both halves agree")
        snap("79d-ouija-devcard-dance")
        XCTAssertTrue(el("devcard.result").waitForExistence(timeout: 15))
        XCTAssertEqual(el("devcard.result").label, "Signed in as Saidie Newara")
        for n in 1...8 { XCTAssertEqual(el("devcard.step.\(n)").value as? String, "yes", "step \(n)") }
        snap("79e-ouija-devcard-granted")
        tap("devcard.continue")
        XCTAssertTrue(el("agreement.handle").waitForExistence(timeout: 10), "signed in by card: on to the agreement")
        XCTAssertTrue(el("agreement.status").label.contains("Saidie Newara"))
    }

    func testCardQRLMismatchShowsTheChoice() {
        openCardSheet(["-uiTestingMagicKeyQRL", "mismatch"])
        tap("devcard.start")
        XCTAssertTrue(el("devcard.choiceTitle").waitForExistence(timeout: 15), "a mismatched magic QR asks what to do")
        XCTAssertTrue(el("devcard.replace").exists)
        XCTAssertTrue(el("devcard.report").exists)
        XCTAssertEqual(el("devcard.step.8").value as? String, "no")
        XCTAssertFalse(el("devcard.result").exists, "never signed in")
        snap("79f-ouija-devcard-qrl-mismatch")
        tap("devcard.report")
        XCTAssertFalse(app.buttons["devcard.report"].isEnabled, "reported once")
    }

    func testCardQRLHalfMissingShowsTheChoice() {
        openCardSheet(["-uiTestingMagicKeyQRL", "missing"])
        tap("devcard.start")
        XCTAssertTrue(el("devcard.choiceTitle").waitForExistence(timeout: 15))
        XCTAssertEqual(el("devcard.step.8").value as? String, "no")
    }

    func testCardOnAnotherPhoneIsRefused() {
        openCardSheet(["-uiTestingMagicKeyOtherPhone"])
        tap("devcard.start")
        XCTAssertTrue(el("devcard.result").waitForExistence(timeout: 15))
        XCTAssertEqual(el("devcard.result").label, "Not signed in")
        XCTAssertEqual(el("devcard.step.3").value as? String, "no")
        snap("79g-ouija-devcard-other-phone")
    }

    func testNoVerifierSetUpIsSaidPlainly() {
        launch(["-uiTestingResetState"])
        tap("ouija.iAgree")
        tap("account.devCard")
        tap("devcard.start")
        XCTAssertTrue(el("devcard.why").waitForExistence(timeout: 10))
        XCTAssertTrue(el("devcard.why").label.contains("isn't set up"), el("devcard.why").label)
    }
}

final class OuijaAuthorizeUITests: DisciplineUITestCase {
    static let request = "ouija://authorize?client=Discipline&nonce=00112233445566778899aabbccddeeff&callback=discipline%3A%2F%2Fouija-callback"

    func testAuthorizeSheetAndLiveActivity() {
        launch(["-uiTestingResetState", "-uiTestingAgreed", "-uiTestingProfileName", "Saidie Newara", "-uiTestingOpenURL", Self.request])
        XCTAssertTrue(el("authorize.title").waitForExistence(timeout: 10), "no sheet: \(labelIfAny("ouija.urlTrace"))")
        XCTAssertEqual(el("authorize.title").label, "Discipline wants to sign in to your account")
        XCTAssertEqual(el("authorize.account").label, "Saidie Newara")
        sleep(1)
        snap("86-ouija-authorize-sheet")

        // The Live Activity (Dynamic Island on Pro simulators, banner on the Lock Screen).
        // What ActivityKit answered when Ouija asked for it, saved beside the screenshots.
        let la = el("authorize.liveActivity")
        _ = la.waitForExistence(timeout: 5)
        sleep(2) // a retry inside Ouija lands within 1.5 s
        note("87-live-activity-state", "ActivityKit: \(la.exists ? la.label : "(no readout)")")
        XCUIDevice.shared.press(.home)
        sleep(4)
        snap("87-live-activity-island")
        hostShot("87s-live-activity-island-simctl")
        // Expanded view: touch and hold the Island (the system expands a Live Activity on a long press).
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        note("87-springboard-tree", springboard.debugDescription)
        let w = springboard.frame.width > 0 ? springboard.frame.width : 402
        springboard.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: w / 2, dy: 24)).press(forDuration: 1.2)
        sleep(1)
        snap("87b-live-activity-island-expanded")
        hostShot("87bs-live-activity-island-expanded-simctl", wait: 3)
        app.activate()
        XCTAssertTrue(el("authorize.handle").waitForExistence(timeout: 10))

        let h = el("authorize.handle")
        h.slide(by: 330)
        XCTAssertEqual(h.value as? String, "agreed", "slide: \(labelIfAny("authorize.handle.trace")), handle \(h.frame), screen \(app.frame)")
        snap("88-ouija-authorize-approved")
    }

    func testBadLinkIsRefused() {
        launch(["-uiTestingResetState", "-uiTestingAgreed", "-uiTestingProfileName", "Saidie Newara", "-uiTestingOpenURL", "ouija://authorize?client=Evil&nonce=short&callback=https%3A%2F%2Fevil.example"])
        XCTAssertTrue(el("ouija.deviceName").waitForExistence(timeout: 10))
        XCTAssertFalse(el("authorize.title").waitForExistence(timeout: 3), "an https callback must be refused")
    }
}

final class OuijaRingUITests: DisciplineUITestCase {
    func testRingSignInAcceptsEnrolledKey() {
        launch(["-uiTestingResetState", "-uiTestingAgreed", "-uiTestingProfileName", "Saidie Newara", "-uiTestingTab", "rings", "-uiTestingRingFrames"])
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
        launch(["-uiTestingResetState", "-uiTestingAgreed", "-uiTestingProfileName", "Saidie Newara", "-uiTestingTab", "rings", "-uiTestingRingForeign"])
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
