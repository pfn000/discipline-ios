import XCTest
@testable import DisciplineCore

final class OuijaAccountTests: XCTestCase {
    func testNameIsNeverInvented() {
        XCTAssertEqual(OuijaAccount.validName(""), .failure(.empty))
        XCTAssertEqual(OuijaAccount.validName("   \n "), .failure(.empty))
        XCTAssertEqual(OuijaAccount.validName("  Saidie   Newara "), .success("Saidie Newara"))
        XCTAssertEqual(OuijaAccount.validName(String(repeating: "a", count: 61)), .failure(.tooLong))
        XCTAssertEqual(OuijaAccount.initials(of: "Saidie Newara"), "SN")
        XCTAssertEqual(OuijaAccount.initials(of: "saidie"), "S")
        XCTAssertEqual(OuijaAccount.initials(of: ""), "")
    }

    func testAccountRoundTripAndRejectsEmptyStoredName() {
        let a = OuijaAccount(name: "Saidie Newara", createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(OuijaAccount.decode(a.encoded()), a)
        var bad = a; bad.name = "  "
        XCTAssertNil(OuijaAccount.decode(bad.encoded()), "a stored account with no name is no account")
        XCTAssertNil(OuijaAccount.decode(nil))
        XCTAssertNil(OuijaAccount.decode(Data("junk".utf8)))
    }

    func testDeviceIdentityFromSystemValues() {
        let phone = DeviceIdentity(name: "iPhone", model: "iPhone", systemName: "iOS", systemVersion: "27.2",
                                   utsMachine: "iPhone18,1", environment: [:])
        XCTAssertEqual(phone.title, "iPhone")
        XCTAssertEqual(phone.detail, "iOS 27.2 · iPhone18,1")
        XCTAssertFalse(phone.isSimulator)
        let sim = DeviceIdentity(name: "iPhone 18 Pro", model: "iPhone", systemName: "iOS", systemVersion: "27.2",
                                 utsMachine: "arm64", environment: ["SIMULATOR_MODEL_IDENTIFIER": "iPhone18,3"])
        XCTAssertEqual(sim.title, "iPhone 18 Pro")
        XCTAssertEqual(sim.detail, "iOS 27.2 · iPhone18,3 · Simulator")
        XCTAssertTrue(sim.isSimulator)
        XCTAssertFalse(sim.title.localizedCaseInsensitiveContains("focals"))
    }

    func testDiscoveredDevicesSummaryIsHonest() {
        XCTAssertEqual(DiscoveredDevice.summary([], scanned: false), "No device connected · scan")
        XCTAssertEqual(DiscoveredDevice.summary([], scanned: true), "No devices found nearby · scan again")
        let a = DiscoveredDevice(id: "1", name: DiscoveredDevice.unnamed, via: .bluetooth, rssi: -40)
        let b = DiscoveredDevice(id: "2", name: "Studio Mac", via: .localNetwork, rssi: nil)
        let c = DiscoveredDevice(id: "3", name: "AirPods", via: .bluetooth, rssi: -70)
        XCTAssertEqual(DiscoveredDevice.sorted([a, b, c]).map(\.id), ["3", "2", "1"])
        XCTAssertEqual(DiscoveredDevice.summary([a, b, c], scanned: true), "Found AirPods + 2 more")
        XCTAssertEqual(DiscoveredDevice.summary([b], scanned: true), "Found Studio Mac")
    }
}

/// Deterministic generator for the token tests.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

final class MagicKeyTests: XCTestCase {
    // A one-way stand-in for SHA-256 (the ledger never needs to reverse it).
    static let digest: @Sendable (String) -> String = { s in
        String(RingCode.fnv1a(Array(s.utf8)), radix: 16) + ":" + String(s.count)
    }
    let owner = "phoneA", stranger = "phoneB"
    let firstToken = "ncom-card-xslukglq7h45dumswwzr"   // the token on Saidie's card today (30 bytes)

    func ledger() -> MagicKeyLedger {
        var l = MagicKeyLedger(digest: Self.digest)
        l.enroll(cardID: "0001", ownerName: "Saidie Newara", token: firstToken, device: owner)
        return l
    }

    func testTokenFormatMatchesHerCard() {
        XCTAssertTrue(MagicCardToken.isValid(firstToken))
        XCTAssertEqual(MagicCardToken.payload(firstToken).count, 30)
        XCTAssertEqual(MagicCardToken.payload(firstToken).prefix(4), [0x6E, 0x63, 0x6F, 0x6D])
        XCTAssertEqual(MagicCardToken.token(fromPayload: MagicCardToken.payload(firstToken) + [0]), firstToken)
        XCTAssertNil(MagicCardToken.token(fromPayload: Array("https://example.com".utf8)))
        XCTAssertFalse(MagicCardToken.isValid("ncom-card-SHORT"))
        var g = SeededRNG(state: 1)
        let t = MagicCardToken.generate(using: &g)
        XCTAssertTrue(MagicCardToken.isValid(t)); XCTAssertEqual(t.utf8.count, 30)
        XCTAssertNotEqual(t, MagicCardToken.generate(using: &g))
    }

    func testTapRotatesAndEachTokenRedeemsOnce() {
        var l = ledger(); var g = SeededRNG(state: 2)
        guard case let .rotate(rid, next) = l.redeem(token: firstToken, device: owner, rng: &g) else { return XCTFail() }
        XCTAssertEqual(l.confirm(rotationID: rid, device: owner), .granted(ownerName: "Saidie Newara", cardID: "0001"))
        XCTAssertEqual(l.confirm(rotationID: rid, device: owner), .noSuchRotation, "a rotation confirms once")
        // The card now holds `next`; the old token is dead.
        guard case let .rotate(rid2, next2) = l.redeem(token: next, device: owner, rng: &g) else { return XCTFail() }
        XCTAssertNotEqual(next, next2)
        XCTAssertEqual(l.confirm(rotationID: rid2, device: owner), .granted(ownerName: "Saidie Newara", cardID: "0001"))
    }

    func testReplayOfUsedTokenLocksTheCard() {
        var l = ledger(); var g = SeededRNG(state: 3)
        guard case let .rotate(rid, next) = l.redeem(token: firstToken, device: owner, rng: &g) else { return XCTFail() }
        _ = l.confirm(rotationID: rid, device: owner)
        // A copy made before that tap still holds firstToken.
        XCTAssertEqual(l.redeem(token: firstToken, device: owner, rng: &g), .outOfSync)
        XCTAssertEqual(l.redeem(token: next, device: owner, rng: &g), .locked(.outOfSync), "locked until NCOM resets it")
        l.reset(cardID: "0001", token: "ncom-card-aaaaaaaaaaaaaaaaaaaa")
        if case .rotate = l.redeem(token: "ncom-card-aaaaaaaaaaaaaaaaaaaa", device: owner, rng: &g) {} else { XCTFail("reset card works again") }
    }

    func testCloneOnAnotherPhoneIsRefusedBurnedAndOwnerUnlocks() {
        var l = ledger(); var g = SeededRNG(state: 4)
        // Someone copies the card and taps the copy on their own phone.
        XCTAssertEqual(l.redeem(token: firstToken, device: stranger, rng: &g), .otherPhone)
        XCTAssertEqual(l.redeem(token: firstToken, device: stranger, rng: &g), .otherPhone, "still refused, nothing issued")
        XCTAssertNil(l.card("0001")?.pending)
        XCTAssertEqual(l.card("0001")?.lock?.reason, .otherPhone)
        // The owner's iPhone taps the real card: it rotates back in and unlocks.
        guard case let .rotate(rid, next) = l.redeem(token: firstToken, device: owner, rng: &g) else { return XCTFail() }
        XCTAssertEqual(l.confirm(rotationID: rid, device: owner), .granted(ownerName: "Saidie Newara", cardID: "0001"))
        XCTAssertNil(l.card("0001")?.lock)
        // The stranger's copy (firstToken) is now a used token: never accepted again.
        XCTAssertEqual(l.redeem(token: firstToken, device: stranger, rng: &g), .otherPhone)
        if case .rotate = l.redeem(token: next, device: owner, rng: &g) {} else { XCTFail() }
    }

    func testConfirmOnlyFromTheTappingPhoneAndInTime() {
        var l = ledger(); var g = SeededRNG(state: 5)
        l.registerPhone(cardID: "0001", device: "phoneC")
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        guard case let .rotate(rid, _) = l.redeem(token: firstToken, device: owner, now: t0, rng: &g) else { return XCTFail() }
        XCTAssertEqual(l.confirm(rotationID: rid, device: "phoneC", now: t0), .wrongPhone)
        XCTAssertEqual(l.confirm(rotationID: rid, device: owner, now: t0.addingTimeInterval(121)), .expired)
    }

    func testLostConfirmStillLetsTheNewTokenIn() {
        var l = ledger(); var g = SeededRNG(state: 6)
        // The new token was written to the card, but the confirm never reached the verifier.
        guard case let .rotate(_, next) = l.redeem(token: firstToken, device: owner, rng: &g) else { return XCTFail() }
        guard case let .rotate(rid2, _) = l.redeem(token: next, device: owner, rng: &g) else { return XCTFail("written token works") }
        XCTAssertEqual(l.confirm(rotationID: rid2, device: owner), .granted(ownerName: "Saidie Newara", cardID: "0001"))
        XCTAssertEqual(l.redeem(token: firstToken, device: owner, rng: &g), .outOfSync, "the old one is burned")
    }

    func testFailedWriteKeepsTheCardsTokenValid() {
        var l = ledger(); var g = SeededRNG(state: 7)
        // Write failed: card still holds firstToken, which is still current. Tapping again works.
        guard case .rotate = l.redeem(token: firstToken, device: owner, rng: &g) else { return XCTFail() }
        guard case let .rotate(rid, _) = l.redeem(token: firstToken, device: owner, rng: &g) else { return XCTFail() }
        XCTAssertEqual(l.confirm(rotationID: rid, device: owner), .granted(ownerName: "Saidie Newara", cardID: "0001"))
    }

    func testUnknownCardAndWords() {
        var l = ledger(); var g = SeededRNG(state: 8)
        XCTAssertEqual(l.redeem(token: "ncom-card-bbbbbbbbbbbbbbbbbbbb", device: owner, rng: &g), .unknownCard)
        XCTAssertEqual(l.redeem(token: "hello", device: owner, rng: &g), .malformed)
        XCTAssertFalse(MagicKeyWords.text(.otherPhone).isEmpty)
    }
}
