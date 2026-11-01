import XCTest
@testable import DisciplineCore

/// Ouija v0.4: the sphere's dance (Saidie, Nov 1 2026: "the pattern change sequence cannot be single rotating
/// thing. It needs to have its own pattern movement and changing positions"; "like a perverted Rubik's cube";
/// "They slide, they glide, they change different directions, they change orientation. Sometimes they rotate all
/// at once").
final class MagicSphereDanceTests: XCTestCase {
    let gv = "GlassVault sig 7f3a", nd = "NCOM Dev sig 19c2"
    func dance(_ n: String, _ g: String) -> SphereDance { MagicSphere.dance(params: MagicSphere.params(ncomDev: n, glassVault: g)) }

    func testSameHalvesGiveTheSameSequence() {
        let a = dance(nd, gv), b = dance(nd, gv)
        XCTAssertEqual(a, b, "deterministic: same halves, same dance")
        for t in stride(from: 0.0, through: 30.0, by: 0.37) { XCTAssertEqual(a.frame(at: t), b.frame(at: t)) }
    }

    /// Saidie, Nov 1 5:27 PM: every sequence is generated live at scan time from that session's one-time halves,
    /// never pre-stored or reused. The halves are signatures over a one-time challenge (card, rotation id, next key
    /// digest), so a new tap means new halves; the dance is a pure function of them, and nothing writes it anywhere.
    func testSequenceIsLiveFromThisSessionsHalvesAndNothingPersists() throws {
        func session(_ rotation: String) -> SphereDance? {
            let ch = MagicQRL.challenge(cardID: "card-1", rotationID: rotation, nextDigest: "digest-" + rotation)
            let v = MagicQRL.combine(challenge: ch,
                                     ncomDev: QRLHalf(party: .ncomDev, challenge: ch, signature: "nd-sig(" + ch + ")"),
                                     glassVault: QRLHalf(party: .glassVault, challenge: ch, signature: "gv-sig(" + ch + ")"),
                                     verify: { _, _, _ in true })
            return MagicSphere.state(verdict: v).params.map { MagicSphere.dance(params: $0) }
        }
        let defaultsBefore = UserDefaults.standard.dictionaryRepresentation().keys.sorted()

        let first = try XCTUnwrap(session("r1")), second = try XCTUnwrap(session("r2")), third = try XCTUnwrap(session("r3"))
        XCTAssertNotEqual(first.patterns, second.patterns, "same app run, new halves: a new sequence")
        XCTAssertNotEqual(second.patterns, third.patterns)
        XCTAssertNotEqual(first.frame(at: 2), second.frame(at: 2))
        // Nothing carried over inside the run: session 2 after session 1 is what session 2 alone would be.
        XCTAssertEqual(session("r2"), second)

        // Nothing written: no UserDefaults key appeared while the dances were made.
        XCTAssertEqual(UserDefaults.standard.dictionaryRepresentation().keys.sorted(), defaultsBefore)

        // And nothing can persist across launches: the sphere's code (core and app) touches no storage, and what
        // Ouija keeps on the phone (OuijaModel) holds no halves, params or dance.
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let sphereFiles = ["DisciplineCore/Sources/DisciplineCore/MagicSphere.swift",
                           "DisciplineCore/Sources/DisciplineCore/MagicSphereDance.swift",
                           "DisciplineCore/Sources/DisciplineCore/MagicQRL.swift",
                           "DisciplineCore/Sources/DisciplineCore/SphereBeacon.swift",
                           "Ouija/Sources/MagicSphereView.swift", "Ouija/Sources/GlassIDCard.swift"]
        for f in sphereFiles {
            let src = try String(contentsOf: repo.appendingPathComponent(f), encoding: .utf8)
            for word in ["UserDefaults", "AppStorage", "FileManager", "Keychain", "SecItem", "write(to", "NSCache", "static var"] {
                XCTAssertFalse(src.contains(word), "\(f) must not use \(word)")
            }
        }
        let model = try String(contentsOf: repo.appendingPathComponent("Ouija/Sources/OuijaModel.swift"), encoding: .utf8)
        for word in ["SphereParams", "SphereDance", "SphereState", "QRLVerdict", "QRLDance", "Signature"] {
            XCTAssertFalse(model.contains(word), "Ouija's stored state must not hold \(word)")
        }
    }

    func testDifferentHalvesGiveADifferentSequence() {
        let base = dance(nd, gv)
        for other in [dance(nd + "x", gv), dance(nd, gv + "x"), dance(gv, nd)] {
            XCTAssertNotEqual(base.patterns, other.patterns, "the order of pattern states changes")
            XCTAssertNotEqual(base.beat, other.beat, accuracy: 1e-9)
            XCTAssertNotEqual(base.frame(at: 1.0), other.frame(at: 1.0), "and so does the picture")
        }
        let orders = Set((0..<60).map { dance("n\($0)", "g\($0)").patterns.map(\.rawValue).joined(separator: ",") })
        XCTAssertGreaterThanOrEqual(orders.count, 59, "nearly every pair of halves has its own order")
    }

    func testAtLeastFourDistinctPatternStatesPerCycle() {
        for i in 0..<40 {
            let d = dance("n\(i)", "g\(i)")
            XCTAssertGreaterThanOrEqual(d.distinctPatterns.count, 4)
            XCTAssertTrue(d.distinctPatterns.isSuperset(of: [.spread, .bunch, .twist, .glide, .reorient, .roll]), "\(d.distinctPatterns)")
            XCTAssertGreaterThan(d.cycle, 10); XCTAssertLessThan(d.cycle, 40)
        }
    }

    func testNeverTheSameMotionTwiceRunning() {
        for i in 0..<40 {
            let moving = dance("n\(i)", "g\(i)").patterns.filter { $0 != .spread }
            var repeats = 0
            for j in 1..<moving.count where moving[j] == moving[j - 1] { repeats += 1 }
            XCTAssertLessThanOrEqual(repeats, 2, "halves n\(i)/g\(i): \(moving)")
        }
    }

    /// The real proof it is not a rotation: rotation keeps every pairwise distance; here they change between states
    /// (all but the deliberate whole-sphere moves, roll and reorient, which turn every dot together).
    func testPairwiseDistancesChangeBetweenPhases() {
        let d = dance(nd, gv)
        func maxChange(_ a: [[Double]], _ b: [[Double]]) -> Double {
            var m = 0.0
            for i in a.indices { for j in a.indices { m = max(m, abs(a[i][j] - b[i][j])) } }
            return m
        }
        var changed = 0, pairs = 0, wholeSphere = 0
        for k in d.steps.indices {
            let j = (k + 1) % d.steps.count
            let c = maxChange(d.distances(at: d.holdMid(k)), d.distances(at: d.holdMid(j)))
            if d.steps[j].pattern == .roll || d.steps[j].pattern == .reorient {
                XCTAssertLessThan(c, 1e-6, "a whole-sphere move keeps every distance"); wholeSphere += 1; continue
            }
            pairs += 1
            if c > 0.15 { changed += 1 }
        }
        XCTAssertEqual(changed, pairs, "every other state change moves dots relative to each other")
        XCTAssertGreaterThan(wholeSphere, 0)
        // A bunch pulls its dots together.
        let k = d.steps.firstIndex { $0.pattern == .bunch }!
        let s = d.frame(at: d.holdMid((k - 1 + d.steps.count) % d.steps.count)).map(\.pos), b = d.frame(at: d.holdMid(k)).map(\.pos)
        let m = d.steps[k].members
        func spreadOf(_ p: [Vec3]) -> Double {
            var t = 0.0, c = 0.0
            for x in m { for y in m where y > x { t += MagicSphere.dist(p[x], p[y]); c += 1 } }
            return t / c
        }
        XCTAssertLessThan(spreadOf(b), spreadOf(s) * 0.75)
    }

    func testTwistsMoveOneSliceLikeACubeLayerAndTheCycleSolvesIt() {
        let d = dance(nd, gv)
        let k = d.steps.firstIndex { $0.pattern == .twist }!
        let before = d.body(at: d.holdMid((k - 1 + d.steps.count) % d.steps.count)).map(\.pos), after = d.body(at: d.holdMid(k)).map(\.pos)
        let moved = Set(zip(before, after).enumerated().filter { MagicSphere.dist($0.1.0, $0.1.1) > 0.3 }.map(\.offset))
        XCTAssertTrue(moved.isSubset(of: Set(d.steps[k].members)), "only the slice moves")
        XCTAssertTrue([8, 9].contains(d.steps[k].members.count), "a cube slice: 8 or 9 of the 26 dots")
        XCTAssertGreaterThanOrEqual(moved.count, 8, "all of it but the centre piece on the axis")
        // Every place is still a cube place (a quarter turn lands exactly), and the spreads keep changing.
        let places = Set(MagicSphere.cubePoints().map { "\(Int(($0.x * 100).rounded())),\(Int(($0.y * 100).rounded())),\(Int(($0.z * 100).rounded()))" })
        for p in after { XCTAssertTrue(places.contains("\(Int((p.x * 100).rounded())),\(Int((p.y * 100).rounded())),\(Int((p.z * 100).rounded()))")) }
        let spreads = d.steps.indices.filter { d.steps[$0].pattern == .spread }
        let layouts = Set(spreads.map { s in d.body(at: d.holdMid(s)).map { "\(Int(($0.pos.x * 50).rounded())),\(Int(($0.pos.y * 50).rounded()))" }.joined() })
        XCTAssertGreaterThanOrEqual(layouts.count, 3, "the spread pattern itself keeps changing")
        // By the end of the cycle the scramble is solved: every dot is home, so the loop has no jump.
        XCTAssertEqual(d.body(at: d.cycle - 0.01).map(\.pos).map { MagicSphere.dist($0, MagicSphere.cubePoints()[0]) }.count, 26)
        let end = d.body(at: d.cycle - 1e-6).map(\.pos)
        for (p, h) in zip(end, MagicSphere.cubePoints()) { XCTAssertLessThan(MagicSphere.dist(p, h), 1e-6) }
    }

    func testGlidesSlideAGroupAlongGreatCirclesAndVeersTurn() {
        for i in 0..<10 {
            let d = dance("n\(i)", "g\(i)")
            for (k, s) in d.steps.enumerated() where s.pattern == .glide || s.pattern == .veer {
                let a = d.body(at: d.holdMid((k - 1 + d.steps.count) % d.steps.count)).map(\.pos), b = d.body(at: d.holdMid(k)).map(\.pos)
                let movers = s.members
                XCTAssertGreaterThanOrEqual(movers.count, 5)
                let mean = movers.map { MagicSphere.dist(a[$0], b[$0]) }.reduce(0, +) / Double(movers.count)
                if s.pattern == .glide { XCTAssertGreaterThan(mean, 0.2, "the group slides") }
                // Rigid: the group keeps its own shape while it slides.
                for x in movers { for y in movers { XCTAssertEqual(MagicSphere.dist(a[x], a[y]), MagicSphere.dist(b[x], b[y]), accuracy: 1e-9) } }
                if s.pattern == .veer { XCTAssertGreaterThan(abs(MagicSphere.dot(s.turnAxis, s.turnAxis2)), -1); XCTAssertNotEqual(s.turnAxis, s.turnAxis2, "turns to a new direction") }
            }
        }
    }

    func testMotionIsSmoothStaggeredAndLoops() {
        let d = dance(nd, gv)
        var worst = 0.0
        var prev = d.frame(at: 0)
        for f in 1...Int(d.cycle * 2 * 60) {
            let cur = d.frame(at: Double(f) / 60)
            for (a, b) in zip(prev, cur) { worst = max(worst, MagicSphere.dist(a.pos, b.pos)) }
            prev = cur
        }
        XCTAssertLessThan(worst, 0.2, "smooth at 60 fps, including the loop point")
        XCTAssertGreaterThan(Set(d.stagger.map { ($0 * 1000).rounded() }).count, 10, "dots start staggered")
        let zs = d.frame(at: 3.3).map(\.pos.z)
        XCTAssertGreaterThan(zs.max()!, 0.6); XCTAssertLessThan(zs.min()!, -0.6)
        XCTAssertEqual(d.dotCount, 26)
        // Pieces have identity (like a cube's colours): a few dots are always bigger.
        XCTAssertEqual(d.weights.filter { $0 > 1.1 }.count, 7)
        XCTAssertNotEqual(d.weights, dance(nd + "x", gv).weights)
    }

    func testTumblesOnMoreThanOneAxis() {
        let d = dance(nd, gv)
        XCTAssertGreaterThan(abs(d.spin), 0.3)
        XCTAssertGreaterThan(d.steps.map { abs($0.kickA) }.max()!, 0.5, "a reorient tips the sphere a lot")
        XCTAssertGreaterThan(d.steps.map { abs($0.kickB) }.max()!, 0.05)
        XCTAssertEqual(d.steps.reduce(0) { $0 + $1.kickA }, 2 * Double.pi, accuracy: 1e-9, "a whole somersault per cycle, so it loops")
        XCTAssertEqual(d.steps.reduce(0) { $0 + $1.kickB }, 0, accuracy: 1e-9)
        XCTAssertLessThan(abs(MagicSphere.dot(d.axisA, d.spinAxis)), 0.5, "tumble axis differs from the spin axis")
    }

    func testStillPoseForReduceMotionShowsTheHalvesOwnCluster() {
        let d = dance(nd, gv)
        XCTAssertEqual(d.steps[d.stepIndex(at: d.stillTime)].pattern, .bunch)
        let e = dance(nd, gv + "x")
        XCTAssertNotEqual(d.frame(at: d.stillTime), e.frame(at: e.stillTime))
    }

    func testBeaconStandInRoundTripsATokenAndCatchesAMisread() {
        let token: [UInt8] = (0..<16).map { UInt8(($0 * 37 + 11) & 0xFF) }
        let frames = SphereBeacon.encode(token)
        XCTAssertEqual(frames.count, 8, "128 bits in 8 beats")
        XCTAssertEqual(SphereBeacon.decode(frames), token)
        var bad = frames
        var lit = bad[3].lit; lit[5].toggle(); bad[3] = SphereBeaconFrame(lit: lit)
        XCTAssertNil(SphereBeacon.decode(bad), "a misread dot fails parity")
        XCTAssertNil(SphereBeacon.decode(Array(frames.dropFirst())), "a missed beat is caught")
    }
}
