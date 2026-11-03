import SwiftUI
import UIKit

// Ember palette (Saidie, Nov 3 2026: her own reference card IMG_3727, "orange, red, black, dark gray,
// steel grey, light grey and studio white"). These nine values are the whole palette: nothing else,
// no purple, no gold. Every screen reads its colours from here, so a new section picks them up too.
enum Ember {
    // The palette, exactly as on her card.
    static let orange   = Color(emberHex: 0xE85002)   // primary accent
    static let red      = Color(emberHex: 0xC10801)   // gradient stop 2
    static let flame    = Color(emberHex: 0xF16001)   // gradient stop 3
    static let sand     = Color(emberHex: 0xD9C3AB)   // gradient stop 4
    static let black    = Color(emberHex: 0x000000)
    static let charcoal = Color(emberHex: 0x333333)   // dark gray
    static let steel    = Color(emberHex: 0x646464)   // steel / mid gray
    static let silver   = Color(emberHex: 0xA7A7A7)   // light gray
    static let studio   = Color(emberHex: 0xF9F9F9)   // studio white

    /// Her gradient, all four stops: black → red → flame → sand (hero / header).
    static let gradientStops: [Color] = [black, red, flame, sand]
    static let gradient = LinearGradient(colors: gradientStops, startPoint: .leading, endPoint: .trailing)
    static let heroGradient = LinearGradient(colors: gradientStops, startPoint: .bottomLeading, endPoint: .topTrailing)
    /// The lit part of her gradient (red → flame → sand) for fills that must show on black: progress bars, rings.
    static let glowStops: [Color] = [red, flame, sand]
    static let glow = LinearGradient(colors: glowStops, startPoint: .leading, endPoint: .trailing)

    // Roles. Dark mode: black / dark-gray surfaces, white text. Light mode: studio-white / white surfaces,
    // black text, orange accents.
    /// Accent fill for buttons, tints, selected chips (orange in both modes).
    static let accent = orange
    /// Text and glyphs drawn ON the orange accent: black (white on #E85002 fails contrast).
    static let onAccent = black
    /// Orange used as TEXT or a small glyph: #E85002 on dark, the darker #C10801 from her gradient on light.
    static let accentText = dynamic(light: 0xC10801, dark: 0xE85002)
    /// Secondary glyph colour (steel on light, light gray on dark).
    static let muted = dynamic(light: 0x646464, dark: 0xA7A7A7)
    /// Screen background under the mesh.
    static let page = dynamic(light: 0xF9F9F9, dark: 0x000000)
    /// A flat (non-glass) surface: white on light, dark gray on dark.
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x333333)
    /// Hairlines / tracks.
    static let track = dynamic(light: 0xA7A7A7, dark: 0x333333)

    // Status, inside the palette (it has no green): fine = sand (dark) / steel (light), soon = orange, over = red.
    static let ok = dynamic(light: 0x646464, dark: 0xD9C3AB)
    static let warn = orange
    static let bad = red
    /// Error / warning TEXT (legible on both surfaces).
    static let warnText = accentText

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(emberHex: dark) : UIColor(emberHex: light) })
    }
}

extension UIColor {
    convenience init(emberHex v: UInt32) {
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(emberHex v: UInt32) { self.init(uiColor: UIColor(emberHex: v)) }
}

/// The primary button: Apple's official Liquid Glass (`glassEffect`, interactive, tinted Ember orange) in a
/// capsule, with a black label (white on #E85002 fails contrast). The system `.glassProminent` style forces a
/// white label (seen on the Nov 3 simulator run), so this style applies the same official glass itself.
struct EmberProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        let small = controlSize == .small || controlSize == .mini
        configuration.label
            .font(small ? .subheadline.weight(.semibold) : .body.weight(.semibold))
            .foregroundStyle(Ember.onAccent)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, small ? 12 : 16)
            .padding(.vertical, small ? 6 : 10)
            .contentShape(Capsule())
            .glassEffect(.regular.tint(Ember.accent).interactive(), in: .capsule)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == EmberProminentButtonStyle {
    static var emberProminent: EmberProminentButtonStyle { EmberProminentButtonStyle() }
}

/// A glowing progress bar in her gradient, inside an official Liquid Glass capsule.
/// The glow is a coloured shadow (light emitted by the fill), not a blur imitating glass.
struct EmberProgressBar: View {
    let progress: Double
    var height: CGFloat = 10
    /// Official glass capsule around the bar (the Element Gallery's B side turns it off).
    var glass: Bool = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let p = max(0, min(progress, 1))
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Ember.track.opacity(0.55))
                Capsule()
                    .fill(Ember.glow)
                    .frame(width: max(height, geo.size.width * p))
                    .shadow(color: Ember.flame.opacity(reduceTransparency ? 0 : 0.75), radius: 6)
                    .opacity(p == 0 ? 0 : 1)
                    .animation(.smooth, value: p)
            }
        }
        .frame(height: height)
        .padding(5)
        .modifier(BarCapsule(glass: glass))
    }
}

private struct BarCapsule: ViewModifier {
    var glass: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if glass { content.glassEffect(.regular, in: .capsule) } else { content.background(Ember.track.opacity(0.35), in: .capsule) }
    }
}
