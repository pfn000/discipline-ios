import Foundation

// Ouija v0.3: the magic sphere. A 3-D Fibonacci sphere of dots that turns like a thinking orb.
// Its motion comes from a hash of BOTH QRL halves (NCOM Dev + GlassVault). Change either half and the
// motion changes; lose a half or break one and the sphere breaks (dots scatter, stall, turn red).

public struct Vec3: Equatable, Sendable { public var x, y, z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    public var length: Double { (x * x + y * y + z * z).squareRoot() }
}

public struct SphereParams: Equatable, Sendable {
    public let axis: Vec3        // unit rotation axis
    public let spin: Double      // radians per second (signed, slow)
    public let wavePhase: Double // radians
    public let waveSpeed: Double // radians per second
    public let waveFreq: Double  // cycles around the sphere
    public let drift: Double     // 0.02...0.08 of radius, how far dots wander
    public let seed: UInt64
}

public enum SphereState: Equatable, Sendable {
    case idle                                      // nothing to show yet: a calm default sphere
    case alive(SphereParams)                       // both halves present and valid
    case broken(parties: [QRLParty], missing: Bool) // a half missing (missing) or wrong (not missing)

    public var isBroken: Bool { if case .broken = self { return true }; return false }
    public var params: SphereParams? { if case .alive(let p) = self { return p }; return nil }
}

public enum MagicSphere {
    public static let dotCount = 220

    /// Fibonacci sphere: evenly spread points on a unit sphere.
    public static func points(count: Int = dotCount) -> [Vec3] {
        let golden = Double.pi * (3 - 5.0.squareRoot())
        return (0..<count).map { i in
            let y = 1 - (Double(i) + 0.5) / Double(count) * 2
            let r = max(0, 1 - y * y).squareRoot()
            let a = golden * Double(i)
            return Vec3(cos(a) * r, y, sin(a) * r)
        }
    }

    /// 64-bit FNV-1a with a finalizer so near-identical inputs land far apart.
    public static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x0000_0100_0000_01B3 }
        h ^= h >> 33; h = h &* 0xff51_afd7_ed55_8ccd
        h ^= h >> 33; h = h &* 0xc4ce_b9fe_1a85_ec53
        h ^= h >> 33
        return h
    }

    /// Deterministic: the same two signatures always give the same sphere; change either one and it changes.
    public static func params(ncomDev: String, glassVault: String) -> SphereParams {
        let seed = hash("NCOM Dev:\(ncomDev)|GlassVault:\(glassVault)")
        func unit(_ salt: String) -> Double { Double(hash("\(seed)|\(salt)") >> 11) / Double(1 << 53) }
        var ax = Vec3(unit("ax") * 2 - 1, unit("ay") * 2 - 1, unit("az") * 2 - 1)
        if ax.length < 0.2 { ax = Vec3(0.3, 1, 0.2) }
        let n = ax.length
        ax = Vec3(ax.x / n, ax.y / n, ax.z / n)
        let spinMag = 0.18 + unit("spin") * 0.22
        return SphereParams(axis: ax,
                            spin: unit("dir") < 0.5 ? -spinMag : spinMag,
                            wavePhase: unit("phase") * 2 * Double.pi,
                            waveSpeed: 0.8 + unit("wspeed") * 1.2,
                            waveFreq: 1.5 + unit("wfreq") * 2.5,
                            drift: 0.02 + unit("drift") * 0.06,
                            seed: seed)
    }

    /// Alive only when the QRL verdict agrees; a missing or wrong half breaks it. The agreeing dance carries
    /// both signatures, so the sphere is a hash of both halves.
    public static func state(verdict: QRLVerdict?) -> SphereState {
        guard let verdict else { return .idle }
        switch verdict {
        case .agree(let d): return .alive(params(ncomDev: d.ncomDevSignature, glassVault: d.glassVaultSignature))
        case .missing(let p): return .broken(parties: p, missing: true)
        case .mismatch(let p): return .broken(parties: p, missing: false)
        }
    }

    /// A dot's place at time `t`: rotated about the axis, with a travelling wave that breathes it in and out
    /// and a small per-dot drift. Returns unit-sphere coordinates (before projection) and a 0...1 pulse.
    public static func place(_ p: Vec3, index: Int, t: Double, params q: SphereParams) -> (pos: Vec3, pulse: Double) {
        // Rodrigues rotation about q.axis by spin * t.
        let th = q.spin * t, c = cos(th), s = sin(th), k = q.axis
        let dot = k.x * p.x + k.y * p.y + k.z * p.z
        let cross = Vec3(k.y * p.z - k.z * p.y, k.z * p.x - k.x * p.z, k.x * p.y - k.y * p.x)
        let r = Vec3(p.x * c + cross.x * s + k.x * dot * (1 - c),
                     p.y * c + cross.y * s + k.y * dot * (1 - c),
                     p.z * c + cross.z * s + k.z * dot * (1 - c))
        // Wave travels along the axis.
        let along = r.x * k.x + r.y * k.y + r.z * k.z
        let wave = sin(along * q.waveFreq * Double.pi + q.wavePhase + q.waveSpeed * t)
        let wob = Double(hash("\(q.seed)|\(index)") >> 40) / Double(1 << 24)
        let drift = sin(t * 0.7 + wob * 2 * Double.pi) * q.drift
        let scale = 1 + wave * 0.07 + drift
        return (Vec3(r.x * scale, r.y * scale, r.z * scale), (wave + 1) / 2)
    }

    /// Broken sphere: each dot flies off along its own direction, then stalls (the motion stops growing).
    /// `t` is seconds since the break; the scatter stops at ~1.6 s so the picture holds still.
    public static func scatter(_ p: Vec3, index: Int, t: Double) -> Vec3 {
        let h = hash("broken|\(index)")
        func u(_ shift: UInt64) -> Double { Double((h >> shift) & 0xFFFF) / 65535 * 2 - 1 }
        let k = min(max(t, 0), 1.6) / 1.6
        let ease = 1 - (1 - k) * (1 - k)
        return Vec3(p.x * (1 + 0.35 * ease) + u(0) * 0.55 * ease,
                    p.y * (1 + 0.35 * ease) + u(16) * 0.55 * ease,
                    p.z * (1 + 0.35 * ease) + u(32) * 0.55 * ease)
    }
}
