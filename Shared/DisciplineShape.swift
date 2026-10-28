import SwiftUI

/// Saidie's corner rule (WhatsApp, Oct 26 2026, 2:41 PM): every rounded card or container uses 37.6.
/// SwiftUI corner radii are in points, so this is 37.6 pt. Shared by Discipline and Ouija.
enum DisciplineShape {
    static let cornerRadius: CGFloat = 37.6
}
