import SwiftUI
import UIKit

/// Ouija's ONE palette (Saidie, Nov 1 2026: "that purple too often"; logo = clear glass + black).
/// Every colour in Ouija and its widget comes from here, light and dark:
///   - ink: true black text in light, true white in dark (system label)
///   - accent: the single neutral accent, black in light mode and white in dark mode
///   - ok / bad: green means yes, red means no. Nothing else is coloured.
/// scripts/ouija-palette-lint.sh fails the build on any purple, violet, indigo or stray colour in Ouija/.
enum OuijaStyle {
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    /// The one accent: black on light, white on dark.
    static let accent = dynamic(light: .black, dark: .white)
    /// Text or icons placed on top of the accent (the inverse of it).
    static let onAccent = dynamic(light: .white, dark: .black)
    /// Primary text: true black / true white.
    static let ink = Color(uiColor: .label)
    /// Hairlines and glass edges: the accent, faint.
    static let hairline = dynamic(light: UIColor.black.withAlphaComponent(0.18), dark: UIColor.white.withAlphaComponent(0.28))

    /// Yes.
    static let ok = Color(red: 0.20, green: 0.78, blue: 0.47)
    /// No.
    static let bad = Color(red: 0.95, green: 0.27, blue: 0.27)

    /// The accent for a known appearance (Canvas and widgets that can't read the trait collection).
    static func accent(_ scheme: ColorScheme) -> Color { scheme == .dark ? .white : .black }

    /// Fixed glass-and-black pair for surfaces that are always dark (lock screen Live Activity).
    static let alwaysWhite = Color.white
    static let alwaysBlack = Color.black
}
