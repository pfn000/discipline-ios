import SwiftUI
import DisciplineCore

/// The magic sphere (replaces the 2-D rings): a 3-D Fibonacci sphere of dots, turning slowly and pulsing like a
/// thinking orb. Motion comes from a hash of BOTH QRL halves (SphereParams). A missing or wrong half breaks it:
/// the dots scatter, stall and turn red. Reduce Motion freezes it on a still pose.
struct MagicSphereView: View {
    var state: SphereState
    /// Optional colour override (green once the card is accepted). Broken is always red.
    var tint: Color? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var startedAt = Date()

    private static let dots = MagicSphere.points()
    private static let idleParams = MagicSphere.params(ncomDev: "NCOM Dev", glassVault: "GlassVault")

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
        TimelineView(.animation(minimumInterval: 1 / 30, paused: frozen)) { tl in
            let t = frozen ? (state.isBroken ? 2.0 : 3.1) : tl.date.timeIntervalSince(startedAt) + 3.1
            Canvas { ctx, size in draw(&ctx, size: size, t: t) }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .onChange(of: state) { _, _ in startedAt = Date() }
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let R = min(size.width, size.height) / 2 * 0.70
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let broken = state.isBroken
        let color = broken ? OuijaStyle.bad : (tint ?? OuijaStyle.accent(scheme))
        let params = state.params ?? Self.idleParams
        let tilt = 0.38, ct = cos(tilt), st = sin(tilt)
        for (i, p) in Self.dots.enumerated() {
            let (pos, pulse): (Vec3, Double) = broken ? (MagicSphere.scatter(p, index: i, t: t), 0.35)
                                                       : MagicSphere.place(p, index: i, t: t, params: params)
            // Fixed viewing tilt, then a gentle perspective.
            let y2 = pos.y * ct - pos.z * st, z2 = pos.y * st + pos.z * ct
            let persp = 1 / (1 - z2 * 0.22)
            let depth = min(max((z2 + 1.4) / 2.8, 0), 1)
            let r = R * 0.030 * (0.55 + 0.95 * depth) * (0.75 + 0.55 * pulse)
            let x = c.x + pos.x * R * persp, y = c.y + y2 * R * persp
            let a = (broken ? 0.30 : 0.16) + (broken ? 0.70 : 0.84) * depth
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(color.opacity(a)))
        }
    }
}
