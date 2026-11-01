import XCTest
@testable import DisciplineCore

/// Saidie, Nov 1 2026 10:25 AM: "fail safe test this to try to see the vulnerabilities."
/// Each test is an attacker trying something. Fail safe = deny (and burn + lock where it's fraud), never grant.
final class MagicKeyAttackTests: XCTestCase {
    let phone = "owner-phone-key", attacker = "attacker-phone-key"
    let first = "ncom-card-xslukglq7h45dumswwzr"
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // Test stand-in for P-256 signatures: only the holder of `pk` can produce "sig(pk|message)".
    static let check: @Sendable (String, String, String) -> Bool = { pk, msg, sig in sig == "sig(\(pk)|\(msg))" }
    func sign(_ pk: String, _ token: String, _ ts: Int) -> String { "sig(\(pk)|\(MagicHandshake.message(token: token, ts: ts)))" }

    func parties(signed: Bool = false) -> MagicHandshake {
        var vault = MagicKeyLedger(digest: MagicKeyTests.digest)
        vault.enroll(cardID: "0001", ownerName: "Saidie Newara", token: first, device: phone)
        vault.setRecoveryCode(cardID: "0001", code: "RECOVER-1234-5678")
        var dir = NCOMDevDirectory()
        dir.issue(cardID: "0001", owner: "Saidie Newara", device: phone)
        var h = MagicHandshake(directory: dir, vault: vault)
        if signed { h.signatureCheck = Self.check }
        return h
    }
    func granted(_ o: MagicHandshake.Outcome) -> Bool { o.grantedOwner != nil }

    func testAttack01_ReplayAnOldToken() {
        var h = parties(); var g = SeededRNG(state: 101)
        let ok = h.tap(cardToken: first, device: phone, local: nil, rng: &g)
        XCTAssertTrue(granted(ok))
        let replay = h.tap(cardToken: first, device: phone, local: nil, rng: &g)
        XCTAssertFalse(granted(replay)); XCTAssertTrue(replay.cardLocked)
    }

    func testAttack02_ClonedCardOnANewPhone() {
        var h = parties(); var g = SeededRNG(state: 102)
        let o = h.tap(cardToken: first, device: attacker, local: nil, rng: &g)
        XCTAssertFalse(granted(o)); XCTAssertTrue(o.cardLocked)
        XCTAssertEqual(o.failedStep, .glassVaultDeviceMatch)
        XCTAssertTrue(h.vault.card("0001")!.burned.contains(h.vault.digest(first)), "the shown key is burned")
    }

    func testAttack03_CloneUsedFirstThenTheRealCard() {
        // (a) clone on the attacker's phone first: denied + locked; the real card on the owner's phone brings it back,
        //     and the clone's key never works again.
        var h = parties(); var g = SeededRNG(state: 103)
        XCTAssertFalse(granted(h.tap(cardToken: first, device: attacker, local: nil, rng: &g)))
        let owner = h.tap(cardToken: first, device: phone, local: nil, rng: &g)
        XCTAssertTrue(granted(owner))
        XCTAssertFalse(granted(h.tap(cardToken: first, device: attacker, local: nil, rng: &g)))
        XCTAssertFalse(granted(h.tap(cardToken: first, device: phone, local: owner.newRecord, rng: &g)), "old key dead on the owner's phone too")
        // (b) clone used first ON the owner's (unlocked, stolen) phone: it wins once, then the real card's next tap
        //     shows the desync, locks the card, and the clone's new key dies with it.
        var h2 = parties(); var g2 = SeededRNG(state: 1031)
        let cloneTap = h2.tap(cardToken: first, device: phone, local: nil, rng: &g2)
        XCTAssertTrue(granted(cloneTap), "known limit: a copy + the owner's unlocked phone gets one sign-in")
        let realTap = h2.tap(cardToken: first, device: phone, local: nil, rng: &g2)
        XCTAssertFalse(granted(realTap)); XCTAssertTrue(realTap.cardLocked)
        XCTAssertFalse(granted(h2.tap(cardToken: cloneTap.newCardToken, device: phone, local: cloneTap.newRecord, rng: &g2)),
                       "after the desync lock the clone's key no longer works")
    }

    func testAttack04_RaceTwoScansOfTheSameKey() {
        var h = parties(); var g = SeededRNG(state: 104)
        // Both requests reach GlassVault before either confirms.
        guard case let .rotate(r1, _) = h.vault.redeem(token: first, device: phone, rng: &g),
              case let .rotate(r2, _) = h.vault.redeem(token: first, device: phone, rng: &g) else { return XCTFail() }
        let c1 = h.vault.confirm(rotationID: r1, device: phone)
        let c2 = h.vault.confirm(rotationID: r2, device: phone)
        let wins = [c1, c2].filter { if case .granted = $0 { return true }; return false }.count
        XCTAssertEqual(wins, 1, "only one may win: \(c1), \(c2)")
        // Same race, owner vs attacker: the attacker's tap kills the owner's in-flight rotation and locks the card.
        var h2 = parties(); var g2 = SeededRNG(state: 1041)
        guard case let .rotate(rOwner, _) = h2.vault.redeem(token: first, device: phone, rng: &g2) else { return XCTFail() }
        XCTAssertEqual(h2.vault.redeem(token: first, device: attacker, rng: &g2), .otherPhone)
        XCTAssertEqual(h2.vault.confirm(rotationID: rOwner, device: phone), .noSuchRotation, "nobody wins the contested tap")
    }

    func testAttack05_TamperedOrBitFlippedToken() {
        var h = parties(); var g = SeededRNG(state: 105)
        var bytes = Array(first.utf8); bytes[15] ^= 0x01
        let flipped = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(granted(h.tap(cardToken: flipped, device: phone, local: nil, rng: &g)))
        XCTAssertFalse(granted(h.tap(cardToken: first.uppercased(), device: phone, local: nil, rng: &g)))
        XCTAssertFalse(granted(h.tap(cardToken: first + "a", device: phone, local: nil, rng: &g)))
        XCTAssertTrue(granted(h.tap(cardToken: first, device: phone, local: nil, rng: &g)), "the real card still works")
    }

    func testAttack06_ForgedDeviceSignature() {
        var h = parties(signed: true); var g = SeededRNG(state: 106)
        let ts = Int(t0.timeIntervalSince1970)
        // Claims to be the owner's phone, but signs with its own key.
        let forged = h.tap(cardToken: first, device: phone, local: nil, now: t0, signature: sign(attacker, first, ts), ts: ts, rng: &g)
        XCTAssertFalse(granted(forged)); XCTAssertEqual(forged.failedStep, .glassVaultDeviceMatch)
        XCTAssertFalse(granted(h.tap(cardToken: first, device: phone, local: nil, now: t0, signature: nil, ts: ts, rng: &g)), "unsigned")
        let real = h.tap(cardToken: first, device: phone, local: nil, now: t0, signature: sign(phone, first, ts), ts: ts, rng: &g)
        XCTAssertTrue(granted(real), "\(real.steps)")
    }

    func testAttack07_DeviceKeySwappedOrAppReinstalled() {
        var h = parties(); var g = SeededRNG(state: 107)
        let reinstalled = "owner-phone-NEW-key-after-reinstall"
        let o = h.tap(cardToken: first, device: reinstalled, local: nil, rng: &g)
        XCTAssertFalse(granted(o)); XCTAssertTrue(o.cardLocked)
        // An attacker can't add their phone; a wrong recovery code does nothing.
        XCTAssertFalse(h.approvePhone(cardID: "0001", approver: attacker, newDevice: attacker))
        XCTAssertNil(h.recover(cardID: "0001", code: "GUESS-0000-0000", newDevice: attacker, rng: &g))
        // The owner's one-time recovery code moves the card to the reinstalled app (new key written to the card).
        guard let fresh = h.recover(cardID: "0001", code: "RECOVER-1234-5678", newDevice: reinstalled, rng: &g) else { return XCTFail() }
        XCTAssertTrue(granted(h.tap(cardToken: fresh, device: reinstalled, local: nil, rng: &g)))
        XCTAssertNil(h.recover(cardID: "0001", code: "RECOVER-1234-5678", newDevice: attacker, rng: &g), "recovery code works once")
        XCTAssertFalse(granted(h.tap(cardToken: first, device: phone, local: nil, rng: &g)), "the old phone + old key are out")
    }

    func testAttack08_NCOMDevOrGlassVaultUnreachableMidHandshake() {
        var h = parties(); var g = SeededRNG(state: 108)
        h.ncomDevReachable = false
        XCTAssertFalse(granted(h.tap(cardToken: first, device: phone, local: nil, rng: &g)))
        h.ncomDevReachable = true; h.glassVaultReachable = false
        XCTAssertFalse(granted(h.tap(cardToken: first, device: phone, local: nil, rng: &g)))
        h.glassVaultReachable = true
        XCTAssertTrue(granted(h.tap(cardToken: first, device: phone, local: nil, rng: &g)), "nothing was burned while a system was down")
    }

    func testAttack09_ServersSayYesButTheLocalRecordDoesNotMatch() {
        var h = parties(); var g = SeededRNG(state: 109)
        let ok = h.tap(cardToken: first, device: phone, local: nil, rng: &g)
        let foreignRecord = OuijaKeyRecord(cardID: "0001", expectedDigest: "not-what-i-wrote", deviceID: phone)
        let o = h.tap(cardToken: ok.newCardToken, device: phone, local: foreignRecord, rng: &g)
        XCTAssertFalse(granted(o)); XCTAssertTrue(o.cardLocked); XCTAssertEqual(o.failedStep, .ouijaLocalMatch)
        // And when the two servers disagree about the owner, step 8 denies.
        var h2 = parties(); var g2 = SeededRNG(state: 1091)
        h2.directory.owners["0001"] = "Someone Else"
        let o2 = h2.tap(cardToken: first, device: phone, local: nil, rng: &g2)
        XCTAssertFalse(granted(o2)); XCTAssertEqual(o2.failedStep, .ouijaAuthenticates)
    }

    func testAttack10_ReissueWriteFailsHalfway() {
        // (a) the write fails cleanly: nothing burned, nothing granted, the card's key still works once.
        var h = parties(); var g = SeededRNG(state: 110)
        let fail = h.tap(cardToken: first, device: phone, local: nil, writeSucceeds: false, rng: &g)
        XCTAssertFalse(granted(fail)); XCTAssertFalse(fail.cardLocked)
        // (b) the write got the new key onto the card but the confirmation was lost: the new key works, the old dies.
        guard case let .rotate(_, next) = h.vault.redeem(token: first, device: phone, rng: &g) else { return XCTFail() }
        XCTAssertTrue(granted(h.tap(cardToken: next, device: phone, local: nil, rng: &g)))
        XCTAssertFalse(granted(h.tap(cardToken: first, device: phone, local: nil, rng: &g)))
        // (c) the write left garbage on the card: it never opens; recovery code + the owner's phone re-keys it.
        var h3 = parties(); var g3 = SeededRNG(state: 1101)
        XCTAssertFalse(granted(h3.tap(cardToken: "ncom-card-xslukg", device: phone, local: nil, rng: &g3)))
        guard let fresh = h3.recover(cardID: "0001", code: "RECOVER-1234-5678", newDevice: phone, rng: &g3) else { return XCTFail() }
        XCTAssertTrue(granted(h3.tap(cardToken: fresh, device: phone, local: nil, rng: &g3)))
    }

    func testAttack11_ClockSkewAndExpiredRotation() {
        var h = parties(signed: true); var g = SeededRNG(state: 111)
        let oldTs = Int(t0.timeIntervalSince1970) - 600   // a captured request from 10 minutes ago
        XCTAssertFalse(granted(h.tap(cardToken: first, device: phone, local: nil, now: t0, signature: sign(phone, first, oldTs), ts: oldTs, rng: &g)))
        let futureTs = Int(t0.timeIntervalSince1970) + 600
        XCTAssertFalse(granted(h.tap(cardToken: first, device: phone, local: nil, now: t0, signature: sign(phone, first, futureTs), ts: futureTs, rng: &g)))
        // A rotation confirmed after 2 minutes is refused.
        var v = MagicKeyLedger(digest: MagicKeyTests.digest)
        v.enroll(cardID: "0001", ownerName: "S", token: first, device: phone)
        guard case let .rotate(rid, _) = v.redeem(token: first, device: phone, now: t0, rng: &g) else { return XCTFail() }
        XCTAssertEqual(v.confirm(rotationID: rid, device: phone, now: t0.addingTimeInterval(121)), .expired)
    }

    func testAttack12_BruteForceGuessingIsRateLimited() {
        var h = parties(); var g = SeededRNG(state: 112)
        for i in 0..<5 {
            let guess = MagicCardToken.generate(using: &g)
            XCTAssertFalse(granted(h.tap(cardToken: guess, device: attacker, local: nil, now: t0.addingTimeInterval(Double(i)), rng: &g)))
        }
        XCTAssertTrue(h.lockedOut(attacker, now: t0.addingTimeInterval(10)))
        // Locked out: even a correct key from that phone is refused, and the card is not touched.
        let o = h.tap(cardToken: first, device: attacker, local: nil, now: t0.addingTimeInterval(11), rng: &g)
        XCTAssertFalse(granted(o)); XCTAssertEqual(o.failedStep, .tapped)
        XCTAssertNil(h.vault.card("0001")?.lock, "the lockout stops it before the card is touched")
        XCTAssertFalse(h.lockedOut(phone, now: t0.addingTimeInterval(11)), "the owner's phone isn't affected")
        XCTAssertFalse(h.lockedOut(attacker, now: t0.addingTimeInterval(16 * 60)), "lifts after 15 minutes")
        // 100 bits per key: a guess hits with probability 2^-100.
        XCTAssertEqual(MagicCardToken.bodyLength * 5, 100)
    }

    func testAttack13_DowngradeToTheNormalSignIn() {
        let typed = OuijaAccount(name: "Saidie Newara", kind: .local)
        XCTAssertFalse(DeveloperGate.isDeveloper(account: typed, grantedOwner: "Saidie Newara", cardID: "0001"), "typed name is never a developer")
        XCTAssertFalse(DeveloperGate.isDeveloper(account: typed, grantedOwner: nil, cardID: nil))
        var card = typed; card.kind = .developerCard
        XCTAssertFalse(DeveloperGate.isDeveloper(account: card, grantedOwner: nil, cardID: nil), "no grant, no developer")
        XCTAssertFalse(DeveloperGate.isDeveloper(account: card, grantedOwner: "Someone Else", cardID: "0001"))
        XCTAssertTrue(DeveloperGate.isDeveloper(account: card, grantedOwner: "Saidie Newara", cardID: "0001"))
    }

    // QRL (magic QR): both halves present -> grant; one missing -> no grant + report + choice; mismatched -> same.
    func testAttack14_QRLBothHalvesPresentDanceAndGrant() {
        var h = parties(); var g = SeededRNG(state: 114)
        let o = h.tap(cardToken: first, device: phone, local: nil, rng: &g)
        XCTAssertTrue(granted(o))
        guard case .agree(let dance)? = o.qrl else { return XCTFail("\(String(describing: o.qrl))") }
        XCTAssertEqual(dance.speeds.count, 4); XCTAssertEqual(dance.payload.count, 16)
        XCTAssertFalse(o.needsChoice); XCTAssertNil(o.report)
        // The dance depends on both halves.
        XCTAssertNotEqual(MagicQRL.dance("a", "b"), MagicQRL.dance("a", "c"))
        XCTAssertNotEqual(MagicQRL.dance("a", "b"), MagicQRL.dance("x", "b"))
        XCTAssertEqual(MagicQRL.dance("a", "b"), MagicQRL.dance("a", "b"))
    }

    func testAttack15_QRLOneHalfMissing() {
        for party in QRLParty.allCases {
            var h = parties(); var g = SeededRNG(state: 115)
            if party == .ncomDev { h.ncomDevSign = { _ in nil } } else { h.glassVaultSign = { _ in nil } }
            let o = h.tap(cardToken: first, device: phone, local: nil, rng: &g)
            XCTAssertFalse(granted(o), "\(party)")
            XCTAssertEqual(o.qrl, .missing([party]))
            XCTAssertTrue(o.needsChoice); XCTAssertEqual(o.report?.kind, "qrl-missing"); XCTAssertTrue(o.cardLocked)
        }
    }

    func testAttack16_QRLHalfMismatchedOrForged() {
        var h = parties(); var g = SeededRNG(state: 116)
        h.glassVaultSign = { _ in "glassvault-signed(some other challenge)" }
        let o = h.tap(cardToken: first, device: phone, local: nil, rng: &g)
        XCTAssertFalse(granted(o)); XCTAssertEqual(o.qrl, .mismatch([.glassVault]))
        XCTAssertTrue(o.needsChoice); XCTAssertEqual(o.report?.kind, "qrl-mismatch")
        var h2 = parties(); var g2 = SeededRNG(state: 1161)
        h2.ncomDevSign = { "glassvault-signed(\($0))" }   // one party pretending to be the other
        let o2 = h2.tap(cardToken: first, device: phone, local: nil, rng: &g2)
        XCTAssertFalse(granted(o2)); XCTAssertEqual(o2.qrl, .mismatch([.ncomDev]))
    }

    func testAttack17_EveryFraudNoWritesASecurityReport() {
        var h = parties(); var g = SeededRNG(state: 117)
        let o = h.tap(cardToken: first, device: attacker, local: nil, rng: &g)
        XCTAssertNotNil(o.report); XCTAssertEqual(o.report?.kind, "step-3")
    }
}
