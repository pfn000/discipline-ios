import SwiftUI
import Charts
import DisciplineCore

// v0.4 visual layer (Saidie: make the screens "graphically visual", not plain lists).
// Everything here is native Liquid Glass (glassEffect / GlassEffectContainer) over a tinted mesh backdrop,
// so the glass has colour to refract. Every rounded container uses DisciplineShape.cornerRadius (37.6 pt).

/// The tinted mesh behind every screen.
struct DisciplineBackdrop: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let t = model.settings.tint.color
        let base: Color = scheme == .dark ? .black : .white
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.62, 0.42], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1]
            ],
            colors: [
                t.opacity(0.55), t.opacity(0.28), Color.indigo.opacity(0.35),
                Color.cyan.opacity(0.20), base, t.opacity(0.22),
                base, Color.purple.opacity(0.22), t.opacity(0.38)
            ]
        )
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// Mesh backdrop for a ScrollView screen.
    func disciplineBackdrop() -> some View {
        background { DisciplineBackdrop() }
    }
    /// Mesh backdrop for a List screen (hides the grey grouped-list background so the mesh shows).
    func disciplineListBackdrop() -> some View {
        scrollContentBackground(.hidden).background { DisciplineBackdrop() }
    }
}

/// One number on a glass tile: an SF Symbol in a tinted glass circle, the value, and a label.
struct StatTile: View {
    let value: String
    let label: String
    let systemImage: String
    var tint: Color = .blue
    let id: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .glassEffect(.regular.tint(tint.opacity(0.22)), in: .circle)
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityIdentifier(id)
    }
}

/// A row of stat tiles that merge as one Liquid Glass group.
struct StatStrip<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) { content }
        }
    }
}

/// A ring that fills with the time an app's signature has left, inside a glass disc.
struct RingGauge<Center: View>: View {
    let progress: Double
    let tint: Color
    var size: CGFloat = 96
    var lineWidth: CGFloat = 11
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.002, min(progress, 1)))
                .stroke(AngularGradient(colors: [tint.opacity(0.55), tint], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: progress)
            center
        }
        .frame(width: size, height: size)
        .padding(10)
        .glassEffect(.regular.tint(tint.opacity(0.14)), in: .circle)
    }
}

extension ExpiryStatus {
    /// Share of the signature's lifetime still left (0 when expired).
    func fractionLeft(of tier: AccountTier) -> Double {
        let total = Double(tier.signatureLifetimeDays) * 86_400
        switch self {
        case .healthy(let r), .refreshSoon(let r): return max(0, min(1, r / total))
        case .expired: return 0
        }
    }
    var daysLeft: Double {
        switch self {
        case .healthy(let r), .refreshSoon(let r): return max(0, r / 86_400)
        case .expired: return 0
        }
    }
    var tintColor: Color {
        switch self {
        case .healthy: return .green
        case .refreshSoon: return .orange
        case .expired: return .red
        }
    }
}

/// Bars of days left per tracked app, coloured green / orange / red.
struct ExpiryChart: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let maxDays = Double(model.trackedApps.map { $0.tier.signatureLifetimeDays }.max() ?? 7)
        Chart(model.trackedApps) { app in
            let s = model.tracker.status(of: app, now: model.now)
            BarMark(x: .value("Days left", s.daysLeft), y: .value("App", app.name))
                .foregroundStyle(s.tintColor.gradient)
                .cornerRadius(8)
                .annotation(position: .trailing) {
                    Text(ExpiryTracker.shortText(s)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
        }
        .chartXScale(domain: 0...maxDays)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        .frame(height: CGFloat(max(1, model.trackedApps.count)) * 36 + 30)
        .accessibilityIdentifier("chart.expiry")
    }
}
