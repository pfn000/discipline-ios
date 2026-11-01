import XCTest
@testable import DisciplineCore

/// Ouija v0.4: the sphere's dance (Saidie, Nov 1 2026: "the pattern change sequence cannot be single rotating
/// thing. It needs to have its own pattern movement and changing positions").
final class MagicSphereDanceTests: XCTestCase {
    let gv = "GlassVault sig 7f3a", nd = "NCOM Dev sig 19c2"
    func dance(_ n: String, _ g: String) -> SphereDance { MagicSphere.dance(params: MagicSphere.params(ncomDev: n, glassVault: g)) }

    func testSameHalvesGiveTheSameSequence() {
        let a = dance(nd, gv), b = dance(nd, gv)
        XCTAssertEqual(a, b, "deterministic: same halves, same dance")
        for t in stride(from: 0.0, through: 20.0, by: 0.37) { XCTAssertEqual(a.frame(at: t), b.frame(at: t)) }
    }

    func testDifferentHalvesGiveADifferentSequence() {
        let base = dance(nd, gv)
        for other in [dance(nd + "x", gv), dance(nd, gv + "x"), dance(gv, nd)] {
            XCTAssertNotEqual(base.patterns, other.patterns, "the order of pattern states changes")
            XCTAssertNotEqual(base.beat, other.beat, accuracy: 1e-9)
            XCTAssertNotEqual(base.frame(at: 1.0), other.frame(at: 1.0), "and so does the picture")
        }
        // Across many pairs of halves nearly every order is its own.
        let orders = Set((0..<60).map { dance("n\($0)", "g\($0)").patterns.map(\.rawValue).joined(separator: ",") })
        XCTAssertGreaterThanOrEqual(orders.count, 58)
    }

    func testAtLeastFourDistinctPatternStatesPerCycle() {
        for i in 0..<40 {
            let d = dance("n\(i)", "g\(i)")
            XCTAssertGreaterThanOrEqual(d.distinctPatterns.count, 4)
            XCTAssertTrue(d.distinctPatterns.isSuperset(of: [.spread, .bunch, .split, .flow]))
            XCTAssertGreaterThan(d.cycle, 6); XCTAssertLessThan(d.cycle, 24)
        }
    }

    /// The real proof it is not a rotation: rotation keeps every pairwise distance; here they change between states.
    func testPairwiseDistancesChangeBetweenPhases() {
        let d = dance(nd, gv)
        func maxChange(_ a: [[Double]], _ b: [[Double]]) -> Double {
            var m = 0.0
            for i in a.indices { for j in a.indices { m = max(m, abs(a[i][j] - b[i][j])) } }
            return m
        }
        var changed = 0, pairs = 0
        for k in d.steps.indices {
            let j = (k + 1) % d.steps.count
            let a = d.distances(at: d.holdMid(k)), b = d.distances(at: d.holdMid(j))
            pairs += 1
            if maxChange(a, b) > 0.15 { changed += 1 }
        }
        XCTAssertEqual(changed, pairs, "every state change moves dots relative to each other")
        // The drawn (rotated) positions agree: distances are rotation-invariant, so turning alone could not do this.
        let k = d.steps.firstIndex { $0.pattern == .bunch }!
        let s = d.frame(at: d.holdMid(k - 1)).map(\.pos), b = d.frame(at: d.holdMid(k)).map(\.pos)
        let m = d.steps[k].members
        func spreadOf(_ p: [Vec3]) -> Double {
            var t = 0.0, c = 0.0
            for x in m { for y in m where y > x { t += MagicSphere.dist(p[x], p[y]); c += 1 } }
            return t / c
        }
        XCTAssertLessThan(spreadOf(b), spreadOf(s) * 0.75, "a bunch pulls its dots together")
    }

    func testFlowMovesEveryDotToANewSlotAndSpreadsComeBackDifferent() {
        let d = dance(nd, gv)
        let k = d.steps.firstIndex { $0.pattern == .flow }!
        let before = d.body(at: d.holdMid(k - 1)).map(\.pos), after = d.body(at: d.holdMid(k)).map(\.pos)
        let moved = zip(before, after).filter { MagicSphere.dist($0, $1) > 0.3 }.count
        XCTAssertGreaterThanOrEqual(moved, MagicSphere.danceDotCount - 2, "the bands slide: nearly every dot travels")
        let spreads = d.steps.indices.filter { d.steps[$0].pattern == .spread }
        let layouts = Set(spreads.map { s in d.body(at: d.holdMid(s)).map { "\(Int(($0.pos.x * 50).rounded())),\(Int(($0.pos.y * 50).rounded()))" }.joined() })
        XCTAssertGreaterThanOrEqual(layouts.count, 3, "the spread pattern itself keeps changing")
    }

    func testMotionIsSmoothStaggeredAndLoops() {
        let d = dance(nd, gv)
        // No jumps: one 60 fps frame never moves a dot more than a fraction of the radius, including the loop point.
        var worst = 0.0
        var prev = d.frame(at: 0)
        for f in 1...Int(d.cycle * 2 * 60) {
            let cur = d.frame(at: Double(f) / 60)
            for (a, b) in zip(prev, cur) { worst = max(worst, MagicSphere.dist(a.pos, b.pos)) }
            prev = cur
        }
        XCTAssertLessThan(worst, 0.2, "smooth at 60 fps")
        // Staggered: dots of one state do not all start moving on the same frame.
        XCTAssertGreaterThan(Set(d.stagger.map { ($0 * 1000).rounded() }).count, 10)
        // Depth: some dots face the viewer and some face away at every moment (size and opacity cue).
        let zs = d.frame(at: 3.3).map(\.pos.z)
        XCTAssertGreaterThan(zs.max()!, 0.6); XCTAssertLessThan(zs.min()!, -0.6)
        XCTAssertEqual(d.dotCount, 22)
    }

    func testTumblesOnMoreThanOneAxis() {
        let d = dance(nd, gv)
        XCTAssertGreaterThan(abs(d.spin), 0.3)
        XCTAssertGreaterThan(d.steps.map { abs($0.kickA) }.max()!, 0.1)
        XCTAssertGreaterThan(d.steps.map { abs($0.kickB) }.max()!, 0.05)
        XCTAssertEqual(d.steps.reduce(0) { $0 + $1.kickA }, 2 * Double.pi, accuracy: 1e-9, "a whole somersault per cycle, so it loops")
        XCTAssertEqual(d.steps.reduce(0) { $0 + $1.kickB }, 0, accuracy: 1e-9)
        XCTAssertLessThan(abs(MagicSphere.dot(d.axisA, d.spinAxis)), 0.5, "tumble axis differs from the spin axis")
    }

    func testStillPoseForReduceMotionShowsTheHalvesOwnCluster() {
        let d = dance(nd, gv)
        XCTAssertEqual(d.steps[d.stepIndex(at: d.stillTime)].pattern, .bunch)
        XCTAssertNotEqual(d.frame(at: d.stillTime), dance(nd, gv + "x").frame(at: dance(nd, gv + "x").stillTime))
    }
}
