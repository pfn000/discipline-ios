import Foundation

// Ouija v0.4: the sphere's dance, rebuilt to move like Saidie's "thinking sphere" reference
// (Nov 1 2026, 3:25 PM: "the pattern change sequence cannot be single rotating thing. It needs to have its own
// pattern movement and changing positions"; 3:28 PM: "take close attention to its rotation, pattern, movement,
// and animations"; 3:52 PM: "they kind of move like a perverted Rubik's cube thing").
//
// What the reference does (studied frame by frame at 30 fps, see OUIJA-PROGRESS.md):
//   - a sparse sphere of ~22 dots, no wireframe; near dots big and bright, far dots small and dim (about 3:1);
//   - the whole sphere turns steadily about an axis close to the line of sight (~0.4 rad/s);
//   - on a quick beat (~0.3 s) a short eased burst (~0.17 s) rearranges it: a few near dots swell, flash and
//     bunch into a tight cluster, then spread back out; the sphere tips a little on another axis as it does;
//   - between active stretches it rests for a few seconds, only turning.
//
// Here the dots sit like the 26 outer pieces of a Rubik's cube pushed out onto a sphere (face centres, edges,
// corners). The dance is a SEQUENCE of pattern states:
//   spread  - every dot on its own place;
//   bunch   - a few near dots slide together into one tight cluster, swelling and flashing;
//   split   - two smaller clusters at once;
//   twist   - one slice turns a quarter turn about its own axis as a group, like a cube layer: the dots in it
//             end up in new places (a scramble);
//   flow    - two slices on one axis turn opposite ways at once;
//   twinkle - the near side swells and flashes in place;
//   glide   - a group of dots slides across the surface together along great circles (and back on the next beat);
//   veer    - a gliding group turns to a new direction halfway along its path;
//   roll    - the whole sphere turns a quarter turn at once, every dot together (an occasional beat);
//   reorient- the whole formation tips to a new pose (its axes flip or tilt).
// Saidie, 3:53 PM: "They slide, they glide, they change different directions, they change orientation.
// Sometimes they rotate all at once". The same motion never runs twice in a row.
// Each dot eases from its place in one state to its place in the next (cubic in-out, staggered per dot; a
// twisting slice turns rigidly along its arc). Late in each cycle the twists are undone in reverse (the cube is
// solved), so the cycle loops cleanly. The order, beat, holds, cluster centres and members, which slices twist,
// which way and in what order, the spin and the tumble axes all come from the hash of BOTH QRL halves
// (SphereParams.seed): different halves give a different dance, the same halves the same one.
// Everything is precomputed into a table (SphereDance) so a frame is a few multiplies per dot.

public enum SpherePattern: String, CaseIterable, Equatable, Sendable {
    case spread, bunch, split, twist, flow, twinkle, glide, veer, roll, reorient
}

/// One state of the dance: ease in from the previous state over `move` seconds, then hold until `duration`.
public struct SphereStep: Equatable, Sendable {
    public let pattern: SpherePattern
    public let start: Double        // seconds into the cycle
    public let duration: Double     // seconds (move + hold)
    public let move: Double         // seconds easing in from the previous state
    public let members: [Int]       // dots that cluster / flash / twist in this state
    public let centers: [Vec3]      // cluster centres (body frame, unit)
    public let turnAxis: Vec3       // twist / flow / roll / glide: the axis the moving dots turn about (body frame)
    public let turnAxis2: Vec3      // veer: the second leg's axis (the new direction)
    public let kickA: Double        // radians tumbled about axis A while easing in
    public let kickB: Double        // radians tumbled about axis B while easing in
}

/// A dot as drawn: view-space position (z toward the viewer) and how much it glows (0...1).
public struct SphereDot: Equatable, Sendable {
    public let pos: Vec3
    public let glow: Double
    public init(pos: Vec3, glow: Double) { self.pos = pos; self.glow = glow }
}

public struct SphereDance: Equatable, Sendable {
    public let dotCount: Int
    public let beat: Double
    public let spinAxis: Vec3, spin: Double       // steady turn, near the line of sight
    public let axisA: Vec3, axisB: Vec3           // tumble axes, across the line of sight
    public let steps: [SphereStep]
    public let targets: [[Vec3]]                  // per step, per dot: where the dot sits (body frame)
    public let glows: [[Double]]                  // per step, per dot
    public let turns: [[Double]]                  // per step, per dot: radians turned about the step's axis (rigid moves)
    public let turns2: [[Double]]                 // per step, per dot: radians turned about the second axis (veer)
    public let stagger: [Double]                  // per dot delay, seconds
    /// Per dot size weight (like a cube piece's colour): a few dots are always bigger, so when the slices twist and the
    /// groups glide, the pattern of big and small visibly lands somewhere new. From the halves too.
    public let weights: [Double]
    public let cycle: Double
    let kickStartA: [Double], kickStartB: [Double] // tumble angle already done at each step's start

    public var patterns: [SpherePattern] { steps.map(\.pattern) }
    /// Distinct pattern states in one cycle.
    public var distinctPatterns: Set<SpherePattern> { Set(patterns) }

    /// A still pose for Reduce Motion: the middle of the first bunch, so the halves' own shape shows.
    public var stillTime: Double {
        for (k, s) in steps.enumerated() where s.pattern == .bunch { return holdMid(k) }
        return holdMid(0)
    }
    /// The step running at time t (any t; the cycle repeats).
    public func stepIndex(at t: Double) -> Int {
        let u = SphereDance.wrap(t, cycle)
        var lo = 0, hi = steps.count - 1
        while lo < hi { let mid = (lo + hi + 1) / 2; if steps[mid].start <= u { lo = mid } else { hi = mid - 1 } }
        return lo
    }
    /// The middle of step k's hold, in cycle time.
    public func holdMid(_ k: Int) -> Double { let s = steps[k]; return s.start + s.move + (s.duration - s.move) / 2 }

    static func wrap(_ t: Double, _ c: Double) -> Double { let r = t.truncatingRemainder(dividingBy: c); return r < 0 ? r + c : r }

    static func ease(_ x: Double) -> Double {
        let e = min(max(x, 0), 1)
        return e < 0.5 ? 4 * e * e * e : 1 - pow(-2 * e + 2, 3) / 2
    }
    /// Softer ease for rigid turns (a cube layer, the whole sphere): sine in-out.
    static func easeTurn(_ x: Double) -> Double { let e = min(max(x, 0), 1); return (1 - cos(e * Double.pi)) / 2 }

    /// Dot positions in the body frame (before the sphere turns) and glow at time t.
    public func body(at t: Double) -> [SphereDot] {
        let u = SphereDance.wrap(t, cycle), k = stepIndex(at: t), s = steps[k]
        let prev = (k - 1 + steps.count) % steps.count
        let local = u - s.start
        let rigid = turns[k].contains { $0 != 0 }
        return (0..<dotCount).map { i in
            let a1 = turns[k][i], a2 = turns2[k][i]
            let e = (a1 != 0 || a2 != 0) ? SphereDance.easeTurn(local / s.move) : SphereDance.ease((local - (rigid ? 0 : stagger[i])) / s.move)
            let g = glows[prev][i] + (glows[k][i] - glows[prev][i]) * e
            if a1 != 0 || a2 != 0 {
                // A rigid group (a cube slice, the whole sphere, a gliding group) turns along its arc; a veering
                // group runs its first leg, then turns onto the second.
                let e1 = a2 == 0 ? e : min(e * 2, 1), e2 = a2 == 0 ? 0 : max(e * 2 - 1, 0)
                let p1 = MagicSphere.rotate(targets[prev][i], axis: s.turnAxis, angle: a1 * e1)
                return SphereDot(pos: a2 == 0 ? p1 : MagicSphere.rotate(p1, axis: s.turnAxis2, angle: a2 * e2), glow: g)
            }
            return SphereDot(pos: MagicSphere.nlerp(targets[prev][i], targets[k][i], e), glow: g)
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
    /// Dots in the dancing sphere: the 26 outer pieces of a 3x3x3 cube, pushed out onto the sphere
    /// (the reference shows about 20 to 24; 26 keeps every slice twist landing exactly on a place).
    public static let danceDotCount = 26

    /// The 26 places: every (i, j, k) in {-1, 0, 1}^3 but the centre, normalised.
    public static func cubePoints() -> [Vec3] {
        var out = [Vec3]()
        for i in -1...1 { for j in -1...1 { for k in -1...1 where !(i == 0 && j == 0 && k == 0) {
            out.append(unitV(Vec3(Double(i), Double(j), Double(k))))
        } } }
        return out
    }

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
            var k = cross(ua, Vec3(0, 1, 0)); if k.length < 0.1 { k = cross(ua, Vec3(1, 0, 0)) }
            dir = rotate(ua, axis: unitV(k), angle: th * e)
        } else {
            dir = add(mul(ua, sin((1 - e) * th) / s), mul(ub, sin(e * th) / s))
        }
        return mul(unitV(dir), r)
    }

    /// One cube move: slices (-1, 0 or 1) on a body axis (0 = x, 1 = y, 2 = z), each with quarter turns (+1 / -1).
    struct CubeMove: Equatable { let axis: Int; let slices: [(Int, Int)]
        static func == (a: CubeMove, b: CubeMove) -> Bool { a.axis == b.axis && a.slices.map { [$0.0, $0.1] } == b.slices.map { [$0.0, $0.1] } }
        var inverse: CubeMove { CubeMove(axis: axis, slices: slices.map { ($0.0, -$0.1) }) }
    }
    static let cubeAxes = [Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0, 0, 1)]
    static func coord(_ p: Vec3, _ axis: Int) -> Double { axis == 0 ? p.x : axis == 1 ? p.y : p.z }
    static func slice(_ p: Vec3, _ axis: Int) -> Int { let c = coord(p, axis); return c > 0.3 ? 1 : c < -0.3 ? -1 : 0 }
    /// Snap back onto the exact cube places (twists are quarter turns, so this only removes rounding).
    static func snap(_ p: Vec3) -> Vec3 {
        unitV(Vec3((p.x * 1.5).rounded() == 0 ? 0 : (p.x > 0 ? 1 : -1),
                   (p.y * 1.5).rounded() == 0 ? 0 : (p.y > 0 ? 1 : -1),
                   (p.z * 1.5).rounded() == 0 ? 0 : (p.z > 0 ? 1 : -1)))
    }

    /// The dance for two agreeing halves. Deterministic in `q.seed` (the hash of both halves).
    public static func dance(params q: SphereParams) -> SphereDance {
        var rng = SplitMix64(seed: q.seed ^ 0x5eed_0f0d_a4ce_0004)
        let n = danceDotCount
        var place = cubePoints()                         // where each dot sits now (cube places)

        // The beat and the turn.
        let beat = rng.range(0.27, 0.34)
        let spin = rng.range(0.32, 0.50) * (rng.unit() < 0.5 ? -1 : 1)
        let tiltDir = rng.range(0, 2 * Double.pi), tilt = rng.range(0.12, 0.38)
        let spinAxis = unitV(Vec3(sin(tilt) * cos(tiltDir), sin(tilt) * sin(tiltDir), cos(tilt)))
        let aAng = rng.range(0, Double.pi)
        let axisA = Vec3(cos(aAng), sin(aAng), 0)
        let axisB = unitV(cross(Vec3(0, 0, 1), axisA))

        // The scramble: which slices twist, which way, in what order (never the same axis twice running).
        let twistCount = 3 + rng.int(2), flowCount = 1 + rng.int(2), rollCount = 1
        var kinds = [SpherePattern](repeating: .twist, count: twistCount) + [SpherePattern](repeating: .flow, count: flowCount)
            + [SpherePattern](repeating: .roll, count: rollCount)
        rng.shuffle(&kinds)
        var moves = [(SpherePattern, CubeMove)](), lastAxis = -1
        for kind in kinds {
            var ax = rng.int(3); if ax == lastAxis { ax = (ax + 1 + rng.int(2)) % 3 }
            lastAxis = ax
            let d = rng.unit() < 0.5 ? 1 : -1
            switch kind {
            case .twist: moves.append((kind, CubeMove(axis: ax, slices: [([-1, 0, 1][rng.int(3)], d)])))
            case .flow: moves.append((kind, CubeMove(axis: ax, slices: [(1, d), (-1, -d)])))   // top and bottom turn opposite ways
            default: moves.append((kind, CubeMove(axis: ax, slices: [(-1, d), (0, d), (1, d)])))  // all at once
            }
        }

        // The order. Two halves: the first scrambles (cube moves among the other motions), the second solves
        // (the same moves undone in reverse, again among the other motions), so the cycle loops cleanly.
        // Swell/flash/bunch beats are answered by a spread on the next beat; glides slide back on the next beat;
        // one rest (a long spread, only turning) sits somewhere in the cycle.
        typealias Item = (pattern: SpherePattern, move: CubeMove?)
        func half(_ ms: [(SpherePattern, CubeMove)]) -> [Item] {
            var others: [SpherePattern] = [.bunch, .bunch, .split, .twinkle, .glide, .reorient]
            let bag: [SpherePattern] = [.bunch, .split, .twinkle, .veer, .glide, .bunch]
            for _ in 0..<(1 + rng.int(3)) { others.append(bag[rng.int(bag.count)]) }
            others.append(rng.unit() < 0.5 ? .veer : .split)
            rng.shuffle(&others)
            var items: [Item] = others.map { ($0, nil) }
            for (j, m) in ms.enumerated() {
                let slot = min(items.count, (j * (items.count + 1)) / max(ms.count, 1) + rng.int(2))
                items.insert((m.0, m.1), at: slot)
            }
            // Never the same motion twice running.
            for _ in 0..<4 {
                for i in 1..<items.count where items[i].pattern == items[i - 1].pattern {
                    if let j = (0..<items.count).first(where: { j in
                        items[j].move == nil && items[i].move == nil && items[j].pattern != items[i].pattern
                        && (j == 0 || items[j - 1].pattern != items[i].pattern) && (j + 1 >= items.count || items[j + 1].pattern != items[i].pattern)
                    }) { items.swapAt(i, j) }
                }
            }
            return items
        }
        let firstHalf = half(moves)
        let secondHalf = half(moves.reversed().map { ($0.0, $0.1.inverse) })
        var active = firstHalf + secondHalf
        if active.first?.pattern == active.last?.pattern, let j = active.indices.first(where: { active[$0].move == nil && $0 > 0 && $0 < active.count - 1 && active[$0].pattern != active[0].pattern }) {
            active.swapAt(0, j)   // the loop point too (only free motions move; the cube moves keep their order)
        }
        let restChoices = active.indices.filter { $0 >= 3 && [.bunch, .split, .twinkle].contains(active[$0].pattern) }
        let restAfter = restChoices.isEmpty ? -1 : restChoices[rng.int(restChoices.count)]
        var plan: [(pattern: SpherePattern, beats: Int, move: CubeMove?)] = []
        for (i, a) in active.enumerated() {
            switch a.pattern {
            case .twist, .flow, .roll: plan.append((a.pattern, 1 + rng.int(2), a.move))   // lands on a new layout itself
            case .reorient: plan.append((a.pattern, 2, nil))
            case .glide, .veer:
                plan.append((a.pattern, 1, nil)); plan.append((.spread, 1, nil))
            default:
                plan.append((a.pattern, 1, nil)); plan.append((.spread, i == restAfter ? 9 + rng.int(8) : 1, nil))
            }
        }

        // Tumble kicks: quick beats tip the sphere a little, a reorient tips it a lot (A adds up to one whole
        // somersault per cycle, B comes back to zero, so the cycle loops).
        func weight(_ k: Int) -> Double {
            let p = plan[k]
            if p.pattern == .reorient { return 4.5 }
            return p.beats < 4 && (p.pattern == .bunch || p.pattern == .split || p.pattern == .spread) ? rng.range(0.6, 1.4) : 0
        }
        var kicksA = plan.indices.map(weight)
        let sumA = kicksA.reduce(0, +)
        kicksA = kicksA.map { $0 / sumA * 2 * Double.pi }
        let rawB = plan.indices.map { k -> Double in
            if kicksA[k] == 0 { return 0 }
            let mag = plan[k].pattern == .reorient ? rng.range(0.5, 0.9) : rng.range(0.10, 0.28)
            return mag * (rng.unit() < 0.5 ? -1 : 1)
        }
        let nB = Double(rawB.filter { $0 != 0 }.count)
        let meanB = rawB.reduce(0, +) / max(nB, 1)
        let kicksB = rawB.map { $0 == 0 ? 0 : $0 - meanB }

        var times = [(start: Double, dur: Double, move: Double)]()
        var startsA = [Double](), startsB = [Double]()
        var t = 0.0, doneA = 0.0, doneB = 0.0
        for (k, p) in plan.enumerated() {
            let move: Double
            switch p.pattern {
            case .twist, .flow: move = rng.range(0.36, 0.42)
            case .roll: move = rng.range(0.50, 0.58)
            case .glide: move = rng.range(0.34, 0.42)
            case .veer: move = rng.range(0.50, 0.58)
            case .reorient: move = rng.range(0.48, 0.56)
            case .spread where k > 0 && (plan[k - 1].pattern == .glide || plan[k - 1].pattern == .veer): move = rng.range(0.30, 0.36)
            default: move = rng.range(0.15, 0.19)
            }
            let dur = max(Double(p.beats) * beat, move + 0.05 + 0.06)   // room for the latest staggered dot to land
            times.append((t, dur, move)); startsA.append(doneA); startsB.append(doneB)
            doneA += kicksA[k]; doneB += kicksB[k]; t += dur
        }
        let cycle = t
        let stagger = (0..<n).map { _ in rng.range(0, 0.05) }
        var weights = (0..<n).map { _ in rng.range(0.80, 0.97) }
        var heavy = Array(0..<n); rng.shuffle(&heavy)
        for i in heavy.prefix(7) { weights[i] = rng.range(1.14, 1.24) }

        // "The front" of the sphere in the body frame at a step (so clusters swell toward the viewer).
        func toBody(_ v: Vec3, at k: Int) -> Vec3 {
            let tm = times[k].start + times[k].move
            let a = startsA[k] + kicksA[k], b = startsB[k] + kicksB[k]
            let s = rotate(v, axis: spinAxis, angle: -spin * tm)
            return rotate(rotate(s, axis: axisA, angle: -a), axis: axisB, angle: -b)
        }
        func frontish(_ k: Int, side: Double) -> Vec3 {
            let ang = rng.range(0, 2 * Double.pi), off = rng.range(0.35, 0.65)
            var v = Vec3(cos(ang) * off, sin(ang) * off, 0)
            if side != 0 { v = Vec3(side * rng.range(0.45, 0.7), rng.range(-0.35, 0.35), 0) }
            let z = max(0.25, (1 - v.x * v.x - v.y * v.y)).squareRoot()
            return unitV(toBody(Vec3(v.x, v.y, z), at: k))
        }
        func across(_ c: Vec3) -> Vec3 {
            // A random axis at right angles to c: turning about it slides c along a great circle.
            let r = Vec3(rng.range(-1, 1), rng.range(-1, 1), rng.range(-1, 1))
            let x = cross(c, r)
            return x.length < 0.1 ? unitV(cross(c, Vec3(0.3, 1, 0.2))) : unitV(x)
        }

        var steps = [SphereStep](), targets = [[Vec3]](), glows = [[Double]](), turns = [[Double]](), turns2 = [[Double]]()
        for (k, p) in plan.enumerated() {
            var turn = [Double](repeating: 0, count: n), turn2 = turn
            var axisV = Vec3(0, 0, 1), axisV2 = Vec3(0, 0, 1)
            var members = [Int](), centers = [Vec3]()
            var gl = [Double](repeating: 0, count: n)
            if let m = p.move {
                axisV = cubeAxes[m.axis]
                for i in 0..<n {
                    for (sl, qt) in m.slices where slice(place[i], m.axis) == sl {
                        turn[i] = Double(qt) * Double.pi / 2
                        members.append(i)
                    }
                }
                for i in members { place[i] = snap(rotate(place[i], axis: axisV, angle: turn[i])) }
            }
            var tg = place
            func gather(_ c: Vec3, count m: Int, taken: Set<Int>, tight: Double) -> [Int] {
                let pick = (0..<n).filter { !taken.contains($0) }.sorted { dist(tg[$0], c) < dist(tg[$1], c) }.prefix(m)
                for i in pick { tg[i] = mul(unitV(add(mul(c, 1 - tight), mul(tg[i], tight))), 1.07); gl[i] = 1 }
                return Array(pick)
            }
            switch p.pattern {
            case .spread, .twist, .flow, .roll, .reorient: break
            case .bunch:
                let c = frontish(k, side: 0); centers = [c]
                members = gather(c, count: 3 + rng.int(2), taken: [], tight: rng.range(0.52, 0.68))
            case .split:
                let side = rng.unit() < 0.5 ? -1.0 : 1.0
                let c1 = frontish(k, side: side), c2 = frontish(k, side: -side); centers = [c1, c2]
                let m1 = gather(c1, count: 2 + rng.int(2), taken: [], tight: rng.range(0.52, 0.68))
                let m2 = gather(c2, count: 2 + rng.int(2), taken: Set(m1), tight: rng.range(0.52, 0.68))
                members = m1 + m2
            case .twinkle:
                let c = frontish(k, side: 0); centers = [c]
                members = Array((0..<n).sorted { dist(tg[$0], c) < dist(tg[$1], c) }.prefix(4 + rng.int(3)))
                for i in members { tg[i] = mul(unitV(add(mul(c, 0.25), mul(tg[i], 0.75))), 1.06); gl[i] = 1 }
            case .glide, .veer:
                // A group near the front slides together along great circles (a veer turns halfway).
                let c = frontish(k, side: 0); centers = [c]
                members = Array((0..<n).sorted { dist(tg[$0], c) < dist(tg[$1], c) }.prefix(5 + rng.int(3)))
                axisV = across(c)
                let a1 = rng.range(0.55, 0.85) * (rng.unit() < 0.5 ? -1 : 1)
                let a2: Double
                if p.pattern == .veer {
                    axisV2 = across(rotate(c, axis: axisV, angle: a1))
                    a2 = rng.range(0.45, 0.7) * (rng.unit() < 0.5 ? -1 : 1)
                } else { a2 = 0 }
                for i in members {
                    turn[i] = a1; turn2[i] = a2; gl[i] = 0.35
                    let p1 = rotate(tg[i], axis: axisV, angle: a1)
                    tg[i] = a2 == 0 ? p1 : rotate(p1, axis: axisV2, angle: a2)
                }
            }
            targets.append(tg); glows.append(gl); turns.append(turn); turns2.append(turn2)
            steps.append(SphereStep(pattern: p.pattern, start: times[k].start, duration: times[k].dur, move: times[k].move,
                                    members: members, centers: centers, turnAxis: axisV, turnAxis2: axisV2,
                                    kickA: kicksA[k], kickB: kicksB[k]))
        }
        return SphereDance(dotCount: n, beat: beat, spinAxis: spinAxis, spin: spin, axisA: axisA, axisB: axisB,
                           steps: steps, targets: targets, glows: glows, turns: turns, turns2: turns2, stagger: stagger,
                           weights: weights, cycle: cycle, kickStartA: startsA, kickStartB: startsB)
    }

    /// The idle sphere (nothing to authenticate yet): the same look, from fixed placeholder halves.
    public static let idleDance = dance(params: params(ncomDev: "NCOM Dev", glassVault: "GlassVault"))
}
