import SwiftUI
import DisciplineCore

/// The magic sphere (v0.4, matched to Saidie's "thinking sphere" reference): a sparse sphere of 22 dots, near dots
/// big and bright, far dots small and dim, no wireframe. It turns steadily near the line of sight and, on a quick
/// beat, runs a sequence of pattern states (spread, bunch, split, flow, twinkle) in which the dots themselves travel,
/// cluster and spread back, while the sphere tips on two more axes. The sequence comes from the hash of BOTH halves
/// (MagicSphere.dance). A missing or wrong half breaks it: the dots scatter, stall and turn red. Reduce Motion
/// holds one still pose (the halves' first cluster).
struct MagicSphereView: View {
    var state: SphereState
    /// Optional colour override (green once the card is accepted). Broken is always red.
    var tint: Color? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var startedAt = Date()

    private static let home = MagicSphere.points(count: MagicSphere.danceDotCount)

    private let dance: SphereDance

    init(state: SphereState, tint: Color? = nil) {
        self.state = state
        self.tint = tint
        if let p = state.params { dance = MagicSphere.dance(params: p) } else { dance = MagicSphere.idleDance }
    }

    /// UI tests freeze the sphere on a fixed pose unless a test asks for it live (animation proof + video).
    private var frozen: Bool { reduceMotion || (OuijaTest.active && !OuijaTest.has("-uiTestingSphereLive")) }

    private var label: String {
        switch state {
        case .idle: return "Magic sphere, waiting"
        case .alive: return "Magic sphere, both halves agree"
        case .broken(let p, let missing):
            return p.isEmpty ? "Magic sphere broken" : "Magic sphere broken, \(p.map(\.name).joined(separator: " and ")) \(missing ? "missing" : "does not match")"
        }
    }
    private var value: String {
        switch state { case .idle: return "idle"; case .alive: return "alive"; case .broken: return "broken" }
    }

    var body: some View {
        // .animation with no minimum interval runs at the display's own rate (60 Hz, 120 on ProMotion).
        TimelineView(.animation(paused: frozen)) { tl in
            let t = frozen ? (state.isBroken ? 2.0 : dance.stillTime) : tl.date.timeIntervalSince(startedAt)
            Canvas { ctx, size in draw(&ctx, size: size, t: t) }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .onChange(of: state) { _, _ in startedAt = Date() }
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let R = min(size.width, size.height) / 2 * 0.72
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let broken = state.isBroken
        let color = broken ? OuijaStyle.bad : (tint ?? OuijaStyle.accent(scheme))
        let dots: [SphereDot]
        if broken {
            // Scatter from the sphere's still pose, then stall.
            let pose = dance.frame(at: dance.stillTime)
            dots = pose.enumerated().map { i, d in SphereDot(pos: MagicSphere.scatter(d.pos, index: i, t: t), glow: 0) }
        } else {
            dots = dance.frame(at: t)
        }
        // Far dots first so near ones sit on top.
        for d in dots.sorted(by: { $0.pos.z < $1.pos.z }) {
            let z = d.pos.z
            let persp = 1 / (1 - z * 0.18)
            let depth = min(max((z + 1) / 2, 0), 1)
            // Size about 3:1 near to far, as in the reference; a glowing dot swells a little.
            let r = R * (0.06 + 0.085 * depth) * (1 + 0.3 * d.glow)
            let base = (broken ? 0.35 : 0.20) + (broken ? 0.60 : 0.70) * depth
            let a = base + (1 - base) * d.glow
            let x = c.x + d.pos.x * R * persp, y = c.y - d.pos.y * R * persp
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(color.opacity(a)))
        }
    }
}

/// UI-test only (-uiTestingSphereShowcase): the live sphere alone, large, for the recorded comparison video.
struct SphereShowcase: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let s = SphereState.alive(MagicSphere.params(ncomDev: "NCOM Dev · test card", glassVault: "GlassVault · test card"))
        VStack(spacing: 18) {
            Spacer()
            MagicSphereView(state: s)
                .frame(width: 320, height: 320)
                .accessibilityIdentifier("sphere.showcase")
            Text("GlassVault + NCOM Dev").font(.footnote).foregroundStyle(OuijaStyle.ink.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(scheme == .dark ? OuijaStyle.alwaysBlack : OuijaStyle.alwaysWhite)
    }
}
