import Foundation

// Ouija v0.4: the sphere's dance, rebuilt to move like Saidie's "thinking sphere" reference
// (Nov 1 2026, 3:25 PM: "the pattern change sequence cannot be single rotating thing. It needs to have its own
// pattern movement and changing positions"; 3:28 PM: "take close attention to its rotation, pattern, movement,
// and animations").
//
// What the reference does (studied frame by frame at 30 fps, see OUIJA-PROGRESS.md):
//   - a sparse sphere of ~22 dots, no wireframe; near dots big and bright, far dots small and dim (about 3:1);
//   - the whole sphere turns steadily about an axis close to the line of sight (~0.4 rad/s);
//   - on a quick beat (~0.3 s) a short eased burst (~0.17 s) rearranges it: a few near dots swell, flash and
//     bunch into a tight cluster, then spread back out; the sphere tips a little on another axis as it does;
//   - between active stretches it rests for a few seconds, only turning.
//
// Here that is a SEQUENCE of pattern states (spread, bunch, split, flow, twinkle). Each dot eases from its place
// in one state to its place in the next (cubic in-out, staggered per dot). The order, beat, holds, cluster
// centres, members, band directions and tumble axes all come from the hash of BOTH QRL halves
// (SphereParams.seed), so different halves give a different dance and the same halves the same one.
// Everything is precomputed into a table (SphereDance) so a frame is a few multiplies per dot.

public enum SpherePattern: String, CaseIterable, Equatable, Sendable {
    /// Every dot on its own slot of the sphere, evenly spread.
    case spread
    /// A few near dots slide together into one tight cluster, swelling and flashing.
    case bunch
    /// Two smaller clusters at once, on either side of the front.
    case split
    /// The latitude bands slide around the sphere, neighbouring bands in opposite directions: every dot moves
    /// to a new slot, so the next spread is a different pattern.
    case flow
    /// The near side swells: the dots facing the viewer flash and pop outward in place.
    case twinkle
}

/// One state of the dance: ease in from the previous state over `move` seconds, then hold until `duration`.
public struct SphereStep: Equatable, Sendable {
    public let pattern: SpherePattern
    public let start: Double        // seconds into the cycle
    public let duration: Double     // seconds (move + hold)
    public let move: Double         // seconds easing in from the previous state
    public let members: [Int]       // dots that cluster / flash in this state
    public let centers: [Vec3]      // cluster centres (body frame, unit)
    public let kickA: Double        // radians tumbled about axis A while easing in
    public let kickB: Double        // radians tumbled about axis B while easing in
}

/// A dot as drawn: view-space position (z toward the viewer) and how much it glows (0...1).
public struct SphereDot: Equatable, Sendable {
    public let pos: Vec3
    public let glow: Double
}

public struct SphereDance: Equatable, Sendable {
    public let dotCount: Int
    public let beat: Double
    public let spinAxis: Vec3, spin: Double       // steady turn, near the line of sight
    public let axisA: Vec3, axisB: Vec3           // tumble axes, across the line of sight
    public let steps: [SphereStep]
    public let targets: [[Vec3]]                  // per step, per dot: where the dot sits (body frame)
    public let glows: [[Double]]                  // per step, per dot
    public let stagger: [Double]                  // per dot delay, seconds
    public let cycle: Double
    let kickStartA: [Double], kickStartB: [Double] // tumble angle already done at each step's start

    public var patterns: [SpherePattern] { steps.map(\.pattern) }
    /// Distinct pattern states in one cycle.
    public var distinctPatterns: Set<SpherePattern> { Set(patterns) }

    /// A still pose for Reduce Motion: the middle of the first bunch, so the halves' own shape shows.
    public var stillTime: Double {
        for s in steps where s.pattern == .bunch { return s.start + s.move + (s.duration - s.move) / 2 }
        return steps[0].start + steps[0].duration / 2
    }
    /// The step running at time t (any t; the cycle repeats).
    public func stepIndex(at t: Double) -> Int {
        let u = SphereDance.wrap(t, cycle)
        var k = steps.count - 1
        for (i, s) in steps.enumerated() where u < s.start + s.duration { k = i; break }
        return k
    }
    /// The middle of step k's hold, in cycle time.
    public func holdMid(_ k: Int) -> Double { let s = steps[k]; return s.start + s.move + (s.duration - s.move) / 2 }

    static func wrap(_ t: Double, _ c: Double) -> Double { let r = t.truncatingRemainder(dividingBy: c); return r < 0 ? r + c : r }

    static func ease(_ x: Double) -> Double {
        let e = min(max(x, 0), 1)
        return e < 0.5 ? 4 * e * e * e : 1 - pow(-2 * e + 2, 3) / 2
    }

    /// Dot positions in the body frame (before the sphere turns) and glow at time t.
    public func body(at t: Double) -> [SphereDot] {
        let u = SphereDance.wrap(t, cycle), k = stepIndex(at: t), s = steps[k]
        let prev = (k - 1 + steps.count) % steps.count
        let local = u - s.start
        return (0..<dotCount).map { i in
            let e = SphereDance.ease((local - stagger[i]) / s.move)
            let p = MagicSphere.nlerp(targets[prev][i], targets[k][i], e)
            let g = glows[prev][i] + (glows[k][i] - glows[prev][i]) * e
            return SphereDot(pos: p, glow: g)
        }
    }

    /// Tumble angles (about A and B) at time t; A adds up to a full turn over the cycle, B returns to zero,
    /// so the cycle loops without a jump.
    func tumble(at t: Double) -> (Double, Double) {
        let u = SphereDance.wrap(t, cycle), k = stepIndex(at: t), s = steps[k]
        let e = SphereDance.ease((u - s.start) / s.move)
        return (kickStartA[k] + s.kickA * e, kickStartB[k] + s.kickB * e)
    }

    /// The sphere's orientation at t: steady spin (absolute time, so it never jumps) after the two tumbles.
    public func orient(_ p: Vec3, at t: Double) -> Vec3 {
        let (a, b) = tumble(at: t)
        let q = MagicSphere.rotate(MagicSphere.rotate(p, axis: axisB, angle: b), axis: axisA, angle: a)
        return MagicSphere.rotate(q, axis: spinAxis, angle: spin * t)
    }

    /// Everything the view draws: view-space positions (z toward the viewer) and glow.
    public func frame(at t: Double) -> [SphereDot] {
        body(at: t).map { SphereDot(pos: orient($0.pos, at: t), glow: $0.glow) }
    }

    /// Pairwise distances between dots at time t (rotation does not change them, rearranging does).
    public func distances(at t: Double) -> [[Double]] {
        let p = body(at: t).map(\.pos)
        return p.map { a in p.map { b in MagicSphere.dist(a, b) } }
    }
}

struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * unit() }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func shuffle<T>(_ a: inout [T]) { for i in stride(from: a.count - 1, to: 0, by: -1) { a.swapAt(i, int(i + 1)) } }
}

extension MagicSphere {
    /// Dots in the dancing sphere (the reference shows about 20 to 24).
    public static let danceDotCount = 22

    static func add(_ a: Vec3, _ b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func sub(_ a: Vec3, _ b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func mul(_ a: Vec3, _ k: Double) -> Vec3 { Vec3(a.x * k, a.y * k, a.z * k) }
    static func dot(_ a: Vec3, _ b: Vec3) -> Double { a.x * b.x + a.y * b.y + a.z * b.z }
    static func cross(_ a: Vec3, _ b: Vec3) -> Vec3 { Vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) }
    static func dist(_ a: Vec3, _ b: Vec3) -> Double { sub(a, b).length }
    static func unitV(_ a: Vec3) -> Vec3 { let n = a.length; return n < 1e-9 ? Vec3(0, 0, 1) : mul(a, 1 / n) }

    /// Rodrigues rotation of p about a unit axis.
    public static func rotate(_ p: Vec3, axis k: Vec3, angle th: Double) -> Vec3 {
        let c = cos(th), s = sin(th), d = dot(k, p), x = cross(k, p)
        return Vec3(p.x * c + x.x * s + k.x * d * (1 - c), p.y * c + x.y * s + k.y * d * (1 - c), p.z * c + x.z * s + k.z * d * (1 - c))
    }

    /// Interpolate along the surface (slerp of the direction, linear radius) so a dot glides over the sphere
    /// instead of cutting through it. Continuous in `e`, even for opposite points.
    static func nlerp(_ a: Vec3, _ b: Vec3, _ e: Double) -> Vec3 {
        if e <= 0 { return a }; if e >= 1 { return b }
        let ra = a.length, rb = b.length, r = ra + (rb - ra) * e
        let ua = unitV(a), ub = unitV(b)
        let c = min(max(dot(ua, ub), -1), 1), th = acos(c)
        if th < 1e-6 { return mul(ua, r) }
        let s = sin(th)
        let dir: Vec3
        if s < 1e-3 {
            // Opposite points: turn about a fixed axis across them.
            var k = cross(ua, Vec3(0, 1, 0)); if k.length < 0.1 { k = cross(ua, Vec3(1, 0, 0)) }
            dir = rotate(ua, axis: unitV(k), angle: th * e)
        } else {
            dir = add(mul(ua, sin((1 - e) * th) / s), mul(ub, sin(e * th) / s))
        }
        return mul(unitV(dir), r)
    }

    /// The dance for two agreeing halves. Deterministic in `q.seed` (the hash of both halves).
    public static func dance(params q: SphereParams) -> SphereDance {
        var rng = SplitMix64(seed: q.seed ^ 0x5eed_0f0d_a4ce_0004)
        let n = danceDotCount
        let home = points(count: n)

        // Latitude bands (for flow): sorted by height. A flow turns each band about the vertical axis,
        // neighbouring bands in opposite directions, so the dots slide past each other into a new pattern.
        let sizes = [4, 5, 4, 5, 4]
        let byY = (0..<n).sorted { home[$0].y > home[$1].y }
        var bandOf = [Int](repeating: 0, count: n), at = 0
        for (bi, sz) in sizes.enumerated() { for j in at..<at + sz { bandOf[byY[j]] = bi }; at += sz }
        let firstDir = rng.unit() < 0.5 ? 1.0 : -1.0
        func bandDir(_ b: Int) -> Double { b % 2 == 0 ? firstDir : -firstDir }
        var bandAngle = [Double](repeating: 0, count: sizes.count)
        func slots() -> [Vec3] { (0..<n).map { rotate(home[$0], axis: Vec3(0, 1, 0), angle: bandAngle[bandOf[$0]]) } }

        // The beat and the turn.
        let beat = rng.range(0.27, 0.34)
        let spin = rng.range(0.32, 0.50) * (rng.unit() < 0.5 ? -1 : 1)
        let tiltDir = rng.range(0, 2 * Double.pi), tilt = rng.range(0.12, 0.38)
        let spinAxis = unitV(Vec3(sin(tilt) * cos(tiltDir), sin(tilt) * sin(tiltDir), cos(tilt)))
        let aAng = rng.range(0, Double.pi)
        let axisA = Vec3(cos(aAng), sin(aAng), 0)
        let axisB = unitV(cross(Vec3(0, 0, 1), axisA))

        // The order: a run of quick active patterns, each answered by a spread on the next beat, with one rest
        // (a long spread, only turning) somewhere in the cycle, as the reference does.
        var active: [SpherePattern] = [.bunch, .bunch, .bunch, .bunch, .split, .split, .split, .flow, .flow, .flow, .twinkle, .twinkle]
        let extra = 2 + rng.int(4)
        let bag: [SpherePattern] = [.bunch, .split, .flow, .twinkle, .bunch]
        for _ in 0..<extra { active.append(bag[rng.int(bag.count)]) }
        rng.shuffle(&active)
        let restChoices = active.indices.filter { $0 >= 4 && active[$0] != .flow }
        let restAfter = restChoices[rng.int(restChoices.count)]
        var plan: [(SpherePattern, Int)] = []          // pattern, beats held
        var flowAngles = [Double]()                    // how far each flow turns the bands
        for (i, p) in active.enumerated() {
            // A flow lands on a new spread by itself (the bands have slid), so it is not answered by one.
            plan.append((p, p == .flow ? 1 + rng.int(2) : 1))
            if p == .flow { flowAngles.append(rng.range(0.55, 0.95)) } else { plan.append((.spread, i == restAfter ? 9 + rng.int(8) : 1)) }
        }
        // Close the loop: one last, slower flow turns the bands home (the shorter way round) so the cycle repeats.
        let net = flowAngles.reduce(0, +)
        let homeTurn = sizes.indices.map { b -> Double in
            var x = (net * bandDir(b)).truncatingRemainder(dividingBy: 2 * Double.pi)
            if x > Double.pi { x -= 2 * Double.pi }; if x < -Double.pi { x += 2 * Double.pi }
            return -x
        }
        plan.append((.flow, 3))
        func tumbles(_ k: Int) -> Bool { plan[k].1 < 4 && plan[k].0 != .twinkle }

        // Timing and tumble kicks (every quick step but twinkles and the rest tips the sphere a little).
        var steps = [SphereStep](), targets = [[Vec3]](), glows = [[Double]]()
        var kicksA = plan.indices.map { tumbles($0) ? rng.range(0.6, 1.4) : 0 }
        let sumA = kicksA.reduce(0, +)
        kicksA = kicksA.map { $0 / sumA * 2 * Double.pi }     // one full somersault per cycle, in small steps
        var kicksB = plan.indices.map { tumbles($0) ? rng.range(0.10, 0.28) * (rng.unit() < 0.5 ? -1 : 1) : 0 }
        let nB = Double(plan.indices.filter(tumbles).count)
        let meanB = kicksB.reduce(0, +) / max(nB, 1)
        kicksB = plan.indices.map { tumbles($0) ? kicksB[$0] - meanB : 0 }   // back to zero per cycle
        var t = 0.0, doneA = 0.0, doneB = 0.0
        var startsA = [Double](), startsB = [Double]()
        var times = [(start: Double, dur: Double, move: Double)]()
        for (k, (p, beats)) in plan.enumerated() {
            let move = p == .flow ? (k == plan.count - 1 ? 0.8 : rng.range(0.26, 0.32)) : rng.range(0.15, 0.19)
            let dur = max(Double(beats) * beat, move + 0.06)
            times.append((t, dur, move)); startsA.append(doneA); startsB.append(doneB)
            doneA += kicksA[k]; doneB += kicksB[k]; t += dur
        }
        let cycle = t
        let stagger = (0..<n).map { _ in rng.range(0, 0.05) }

        // Orientation at a cycle time (spin uses the same t; used only to find "the front" in the body frame).
        func toBody(_ v: Vec3, at k: Int) -> Vec3 {
            let tm = times[k].start + times[k].move
            let a = startsA[k] + kicksA[k], b = startsB[k] + kicksB[k]
            // Inverse of orient: undo spin, then A, then B.
            let s = rotate(v, axis: spinAxis, angle: -spin * tm)
            return rotate(rotate(s, axis: axisA, angle: -a), axis: axisB, angle: -b)
        }
        func frontish(_ k: Int, side: Double) -> Vec3 {
            // A point on the near side, a little off centre, so the cluster swells toward the viewer.
            let ang = rng.range(0, 2 * Double.pi), off = rng.range(0.35, 0.65)
            var v = Vec3(cos(ang) * off, sin(ang) * off, 0)
            if side != 0 { v = Vec3(side * rng.range(0.45, 0.7), rng.range(-0.35, 0.35), 0) }
            let z = max(0.25, (1 - v.x * v.x - v.y * v.y)).squareRoot()
            return unitV(toBody(Vec3(v.x, v.y, z), at: k))
        }

        for (k, (p, _)) in plan.enumerated() {
            if p == .flow {
                if k == plan.count - 1 {
                    for b in bandAngle.indices { bandAngle[b] += homeTurn[b] }
                } else {
                    let turn = flowAngles.removeFirst()
                    for b in bandAngle.indices { bandAngle[b] += bandDir(b) * turn }
                }
            }
            var tg = slots()
            var gl = [Double](repeating: 0, count: n)
            var members = [Int](), centers = [Vec3]()
            func gather(_ c: Vec3, count m: Int, taken: Set<Int>, tight: Double) -> [Int] {
                let pick = (0..<n).filter { !taken.contains($0) }.sorted { dist(tg[$0], c) < dist(tg[$1], c) }.prefix(m)
                for i in pick {
                    tg[i] = mul(unitV(add(mul(c, 1 - tight), mul(tg[i], tight))), 1.07)
                    gl[i] = 1
                }
                return Array(pick)
            }
            switch p {
            case .spread: break
            case .bunch:
                let c = frontish(k, side: 0); centers = [c]
                members = gather(c, count: 3 + rng.int(2), taken: [], tight: rng.range(0.52, 0.68))
            case .split:
                let side = rng.unit() < 0.5 ? -1.0 : 1.0
                let c1 = frontish(k, side: side), c2 = frontish(k, side: -side); centers = [c1, c2]
                let m1 = gather(c1, count: 2 + rng.int(2), taken: [], tight: rng.range(0.52, 0.68))
                let m2 = gather(c2, count: 2 + rng.int(2), taken: Set(m1), tight: rng.range(0.52, 0.68))
                members = m1 + m2
            case .flow:
                for i in 0..<n { gl[i] = 0.25 }
            case .twinkle:
                // The near side swells: the dots facing the viewer flash and pop outward in place.
                let c = frontish(k, side: 0); centers = [c]
                members = Array((0..<n).sorted { dist(tg[$0], c) < dist(tg[$1], c) }.prefix(4 + rng.int(3)))
                for i in members { tg[i] = mul(unitV(add(mul(c, 0.25), mul(tg[i], 0.75))), 1.06); gl[i] = 1 }
            }
            targets.append(tg); glows.append(gl)
            steps.append(SphereStep(pattern: p, start: times[k].start, duration: times[k].dur, move: times[k].move,
                                    members: members, centers: centers, kickA: kicksA[k], kickB: kicksB[k]))
        }
        return SphereDance(dotCount: n, beat: beat, spinAxis: spinAxis, spin: spin, axisA: axisA, axisB: axisB,
                           steps: steps, targets: targets, glows: glows, stagger: stagger, cycle: cycle,
                           kickStartA: startsA, kickStartB: startsB)
    }

    /// The idle sphere (nothing to authenticate yet): the same look, from fixed placeholder halves.
    public static let idleDance = dance(params: params(ncomDev: "NCOM Dev", glassVault: "GlassVault"))
}
