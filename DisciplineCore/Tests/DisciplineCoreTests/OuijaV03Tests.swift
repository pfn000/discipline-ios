import XCTest
@testable import DisciplineCore

final class SniffTests: XCTestCase {
    func ble(_ n: String, _ rssi: Int = -60) -> SniffCandidate { SniffCandidate(id: "ble-\(n)", name: n, channel: .bluetooth, rssi: rssi) }

    func testStartsEmpty() {
        let t = TestingDevices()
        XCTAssertTrue(t.listed.isEmpty); XCTAssertNil(t.possessed); XCTAssertTrue(t.candidates.isEmpty)
        XCTAssertEqual(t.phase, .idle); XCTAssertEqual(t.headline, "No device possessed")
        XCTAssertEqual(t.resultLine, "Not sniffed yet"); XCTAssertFalse(t.autoSniff)
    }

    func testSniffReportsEveryChannelHonestly() {
        var t = TestingDevices(); t.beginSniff()
        XCTAssertEqual(t.phase, .sniffing); XCTAssertTrue(t.listed.isEmpty)
        t.report(.bluetooth, found: [ble("A"), ble("B", -40)])
        XCTAssertEqual(t.phase, .sniffing, "still waiting on the other channels")
        t.report(.localNetwork, found: [])
        t.report(.uwb, found: [], unavailable: "no peer")
        XCTAssertEqual(t.phase, .done)
        XCTAssertEqual(t.resultLine, "Bluetooth: 2 found · Local network: 0 found · UWB: no peer")
        XCTAssertEqual(t.candidates.map(\.name), ["B", "A"], "strongest first")
        XCTAssertTrue(t.listed.isEmpty, "found is not possessed")
    }

    func testChannelThatCannotRunSaysWhy() {
        var t = TestingDevices(); t.beginSniff()
        t.report(.bluetooth, found: [], unavailable: "off")
        XCTAssertEqual(t.channels[.bluetooth], .unavailable("off"))
    }

    func testConnectMakesItPossessedAndOnlyThen() {
        var t = TestingDevices(); t.beginSniff()
        t.report(.bluetooth, found: [ble("A")]); t.report(.localNetwork, found: []); t.report(.uwb, found: [], unavailable: "no peer")
        XCTAssertNotNil(t.hail("ble-A")); XCTAssertEqual(t.hailing, "ble-A")
        XCTAssertTrue(t.listed.isEmpty, "hailing is not connected yet")
        t.connected("ble-A", now: Date(timeIntervalSince1970: 5))
        XCTAssertEqual(t.listed.map(\.name), ["A"]); XCTAssertEqual(t.headline, "A")
        XCTAssertNil(t.hailing); XCTAssertTrue(t.candidates.isEmpty)
    }

    func testFailedConnectListsNothing() {
        var t = TestingDevices(); t.beginSniff(); t.report(.bluetooth, found: [ble("A")])
        _ = t.hail("ble-A"); t.connectFailed("ble-A", reason: "timed out")
        XCTAssertTrue(t.listed.isEmpty); XCTAssertNil(t.possessed)
        XCTAssertEqual(t.lastError, "Couldn't connect to A: timed out")
    }

    func testDisconnectRemovesIt() {
        var t = TestingDevices(); t.beginSniff(); t.report(.bluetooth, found: [ble("A")])
        _ = t.hail("ble-A"); t.connected("ble-A")
        t.disconnect()
        XCTAssertTrue(t.listed.isEmpty); XCTAssertNil(t.possessed); XCTAssertEqual(t.headline, "No device possessed")
    }

    func testOnlyOnePossessedAtATimeAndUnknownIDsIgnored() {
        var t = TestingDevices(); t.beginSniff(); t.report(.bluetooth, found: [ble("A"), ble("B")])
        XCTAssertNil(t.hail("nope"))
        _ = t.hail("ble-A"); t.connected("ble-A")
        XCTAssertNil(t.hail("ble-B"), "already possessing one")
        t.beginSniff(); t.report(.bluetooth, found: [ble("A")])
        XCTAssertTrue(t.candidates.isEmpty, "the possessed device isn't offered again")
    }

    func testNewSniffClearsOldCandidates() {
        var t = TestingDevices(); t.beginSniff(); t.report(.bluetooth, found: [ble("A")])
        t.beginSniff(); XCTAssertTrue(t.candidates.isEmpty)
    }
}

final class MagicSphereTests: XCTestCase {
    func half(_ p: QRLParty, _ sig: String) -> QRLHalf { QRLHalf(party: p, challenge: "c", signature: sig) }

    func testFibonacciPointsAreOnTheUnitSphereAndSpread() {
        let pts = MagicSphere.points(count: 200)
        XCTAssertEqual(pts.count, 200)
        for p in pts { XCTAssertEqual(p.length, 1, accuracy: 1e-9) }
        XCTAssertEqual(Set(pts.map { "\(($0.x*1000).rounded())|\(($0.y*1000).rounded())|\(($0.z*1000).rounded())" }).count, 200)
        XCTAssertEqual(pts.map(\.y).reduce(0, +) / 200, 0, accuracy: 1e-9, "balanced top to bottom")
    }

    func testSameHalvesSameSphere() {
        XCTAssertEqual(MagicSphere.params(ncomDev: "a", glassVault: "b"), MagicSphere.params(ncomDev: "a", glassVault: "b"))
    }

    func testDifferentHalvesGiveDifferentSpheres() {
        let base = MagicSphere.params(ncomDev: "a", glassVault: "b")
        XCTAssertNotEqual(base, MagicSphere.params(ncomDev: "a2", glassVault: "b"), "changing NCOM Dev's half changes it")
        XCTAssertNotEqual(base, MagicSphere.params(ncomDev: "a", glassVault: "b2"), "changing GlassVault's half changes it")
        XCTAssertNotEqual(base, MagicSphere.params(ncomDev: "b", glassVault: "a"), "swapping halves changes it")
        // Motion really differs, not just the seed.
        var motions = Set<String>()
        for i in 0..<40 {
            let q = MagicSphere.params(ncomDev: "n\(i)", glassVault: "g\(i)")
            motions.insert("\((q.spin * 1000).rounded())|\((q.waveFreq * 1000).rounded())|\((q.axis.x * 1000).rounded())")
        }
        XCTAssertGreaterThan(motions.count, 35)
    }

    func testParamsAreSlowAndBounded() {
        for i in 0..<200 {
            let q = MagicSphere.params(ncomDev: "n\(i)", glassVault: "g\(i)")
            XCTAssertEqual(q.axis.length, 1, accuracy: 1e-9)
            XCTAssertTrue(abs(q.spin) >= 0.18 && abs(q.spin) <= 0.40)
            XCTAssertTrue(q.drift >= 0.02 && q.drift <= 0.08)
            XCTAssertTrue(q.waveFreq >= 1.5 && q.waveFreq <= 4.0)
        }
    }

    func testAgreeingHalvesGiveAnAliveSphere() {
        let n = half(.ncomDev, "sigN"), g = half(.glassVault, "sigG")
        let v = MagicQRL.combine(challenge: "c", ncomDev: n, glassVault: g, verify: { _, _, _ in true })
        let s = MagicSphere.state(verdict: v)
        XCTAssertEqual(s.params, MagicSphere.params(ncomDev: "sigN", glassVault: "sigG"))
        XCTAssertFalse(s.isBroken)
        let v2 = MagicQRL.combine(challenge: "c", ncomDev: half(.ncomDev, "other"), glassVault: g, verify: { _, _, _ in true })
        XCTAssertNotEqual(MagicSphere.state(verdict: v2), s)
    }

    func testMismatchGivesTheBrokenState() {
        let n = half(.ncomDev, "sigN"), g = half(.glassVault, "sigG")
        let v = MagicQRL.combine(challenge: "c", ncomDev: n, glassVault: g, verify: { p, _, _ in p != .glassVault })
        XCTAssertEqual(MagicSphere.state(verdict: v), .broken(parties: [.glassVault], missing: false))
        // Wrong challenge on a half is also a mismatch.
        let bad = QRLHalf(party: .ncomDev, challenge: "other", signature: "sigN")
        let v2 = MagicQRL.combine(challenge: "c", ncomDev: bad, glassVault: g, verify: { _, _, _ in true })
        XCTAssertTrue(MagicSphere.state(verdict: v2).isBroken)
    }

    func testMissingHalfGivesTheBrokenState() {
        let g = half(.glassVault, "sigG")
        let v = MagicQRL.combine(challenge: "c", ncomDev: nil, glassVault: g, verify: { _, _, _ in true })
        XCTAssertEqual(MagicSphere.state(verdict: v), .broken(parties: [.ncomDev], missing: true))
        let both = MagicQRL.combine(challenge: "c", ncomDev: nil, glassVault: nil, verify: { _, _, _ in true })
        XCTAssertEqual(MagicSphere.state(verdict: both), .broken(parties: [.ncomDev, .glassVault], missing: true))
        XCTAssertEqual(MagicSphere.state(verdict: nil), .idle)
    }

    func testMotionMovesAndScatterStalls() {
        let q = MagicSphere.params(ncomDev: "a", glassVault: "b"), p = MagicSphere.points(count: 50)[7]
        let a = MagicSphere.place(p, index: 7, t: 0, params: q).pos, b = MagicSphere.place(p, index: 7, t: 2, params: q).pos
        XCTAssertNotEqual(a, b)
        let s1 = MagicSphere.scatter(p, index: 7, t: 1.6), s2 = MagicSphere.scatter(p, index: 7, t: 9)
        XCTAssertEqual(s1, s2, "stalls once scattered")
        XCTAssertNotEqual(MagicSphere.scatter(p, index: 7, t: 0), s1)
        XCTAssertGreaterThan(s1.length, 1.0)
    }
}
