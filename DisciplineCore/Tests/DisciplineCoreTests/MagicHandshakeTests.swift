import XCTest
@testable import DisciplineCore

/// Saidie's 8-step handshake (Nov 1 2026): one test per step that can say no, plus the happy path.
final class MagicHandshakeTests: XCTestCase {
    let phone = "saidie-iphone-key", stranger = "other-phone-key"
    let first = "ncom-card-xslukglq7h45dumswwzr"

    func parties(ncomDevPhone: String? = nil, ncomDevOwner: String = "Saidie Newara") -> MagicHandshake {
        var vault = MagicKeyLedger(digest: MagicKeyTests.digest)
        vault.enroll(cardID: "0001", ownerName: "Saidie Newara", token: first, device: phone)
        var dir = NCOMDevDirectory()
        dir.issue(cardID: "0001", owner: ncomDevOwner, device: ncomDevPhone ?? phone)
        return MagicHandshake(directory: dir, vault: vault)
    }

    func testAllEightStepsSayYes() {
        var h = parties(); var g = SeededRNG(state: 11)
        let o = h.tap(cardToken: first, device: phone, local: nil, rng: &g)
        XCTAssertEqual(o.steps.map(\.step), MagicStep.allCases)
        XCTAssertTrue(o.steps.allSatisfy(\.ok), "\(o.steps)")
        XCTAssertEqual(o.grantedOwner, "Saidie Newara")
        XCTAssertNotNil(o.newCardToken); XCTAssertNotEqual(o.newCardToken, first)
        // Next tap with the new key and the record OuijaBoard kept: all yes again.
        let o2 = h.tap(cardToken: o.newCardToken, device: phone, local: o.newRecord, rng: &g)
        XCTAssertNil(o2.failedStep, "\(o2.steps)")
    }

    func testStep1NoKeyOnCard() {
        var h = parties(); var g = SeededRNG(state: 12)
        XCTAssertEqual(h.tap(cardToken: "https://example.com", device: phone, local: nil, rng: &g).failedStep, .tapped)
        XCTAssertEqual(h.tap(cardToken: nil, device: phone, local: nil, rng: &g).failedStep, .tapped)
    }

    func testStep2NCOMDevDoesNotKnowOrRevokedTheCard() {
        var h = parties(); var g = SeededRNG(state: 13)
        XCTAssertEqual(h.tap(cardToken: "ncom-card-bbbbbbbbbbbbbbbbbbbb", device: phone, local: nil, rng: &g).failedStep, .ncomDevKnowsCard)
        h.directory.revoke(cardID: "0001")
        let o = h.tap(cardToken: first, device: phone, local: nil, rng: &g)
        XCTAssertEqual(o.failedStep, .ncomDevKnowsCard)
        XCTAssertTrue(o.cardLocked)
        XCTAssertEqual(h.vault.card("0001")?.lock?.reason, .revoked)
    }

    func testStep3ClonedCardOnAnotherPhoneIsRejectedBurnedAndLocked() {
        var h = parties(); var g = SeededRNG(state: 14)
        let o = h.tap(cardToken: first, device: stranger, local: nil, rng: &g)
        XCTAssertEqual(o.failedStep, .glassVaultDeviceMatch)
        XCTAssertTrue(o.cardLocked); XCTAssertNil(o.newCardToken)
        XCTAssertEqual(h.vault.card("0001")?.lock?.reason, .otherPhone)
        // Card stays dead for everyone else…
        XCTAssertEqual(h.tap(cardToken: first, device: stranger, local: nil, rng: &g).failedStep, .glassVaultDeviceMatch)
        // …until the registered iPhone taps the real card again.
        let back = h.tap(cardToken: first, device: phone, local: nil, rng: &g)
        XCTAssertNil(back.failedStep, "\(back.steps)")
        XCTAssertNil(h.vault.card("0001")?.lock)
    }

    func testStep4OuijaBoardsOwnRecordDisagrees() {
        var h = parties(); var g = SeededRNG(state: 15)
        let ok = h.tap(cardToken: first, device: phone, local: nil, rng: &g)
        var wrong = ok.newRecord!; wrong.expectedDigest = "something-else"
        let o = h.tap(cardToken: ok.newCardToken, device: phone, local: wrong, rng: &g)
        XCTAssertEqual(o.failedStep, .ouijaLocalMatch)
        XCTAssertTrue(o.cardLocked)
        XCTAssertEqual(h.tap(cardToken: ok.newCardToken, device: phone, local: ok.newRecord, rng: &g).failedStep, .glassVaultVerdict,
                       "after a no, the key is burned and the card stays locked")
    }

    func testStep5ReplayOfAUsedKeyIsRefusedAndLocks() {
        var h = parties(); var g = SeededRNG(state: 16)
        let ok = h.tap(cardToken: first, device: phone, local: nil, rng: &g)
        XCTAssertNil(ok.failedStep)
        // A copy of the card made before that tap still holds `first`. On the owner's iPhone (no local record):
        let o = h.tap(cardToken: first, device: phone, local: nil, rng: &g)
        XCTAssertEqual(o.failedStep, .glassVaultVerdict)
        XCTAssertTrue(o.cardLocked)
        // Even the current key is refused now: NCOM has to reset the card.
        XCTAssertEqual(h.tap(cardToken: ok.newCardToken, device: phone, local: ok.newRecord, rng: &g).failedStep, .glassVaultVerdict)
    }

    func testStep6NCOMDevDoesNotHaveThisPhoneOnFile() {
        var h = parties(ncomDevPhone: "a-different-phone"); var g = SeededRNG(state: 17)
        let o = h.tap(cardToken: first, device: phone, local: nil, rng: &g)
        XCTAssertEqual(o.failedStep, .ncomDevApproves)
        XCTAssertTrue(o.cardLocked)
        XCTAssertNil(o.newCardToken, "nothing is written when a party says no")
    }

    func testStep7WriteFailedChangesNothing() {
        var h = parties(); var g = SeededRNG(state: 18)
        let o = h.tap(cardToken: first, device: phone, local: nil, writeSucceeds: false, rng: &g)
        XCTAssertEqual(o.failedStep, .glassVaultRotates)
        XCTAssertFalse(o.cardLocked, "a shaky NFC write is not fraud")
        XCTAssertNil(h.tap(cardToken: first, device: phone, local: nil, rng: &g).failedStep, "the card's key still works once")
    }

    func testStep8SystemsDisagreeAboutTheOwner() {
        var h = parties(ncomDevOwner: "Someone Else"); var g = SeededRNG(state: 19)
        let o = h.tap(cardToken: first, device: phone, local: nil, rng: &g)
        XCTAssertEqual(o.failedStep, .ouijaAuthenticates)
        XCTAssertNil(o.grantedOwner)
        XCTAssertTrue(o.cardLocked)
    }

    func testStepTitlesAreThePlainEightSteps() {
        XCTAssertEqual(MagicStep.allCases.count, 8)
        XCTAssertEqual(MagicStep.allCases.map(\.rawValue), Array(1...8))
        XCTAssertTrue(MagicStep.allCases.allSatisfy { !$0.title.isEmpty })
    }
}
