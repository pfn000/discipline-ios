import SwiftUI
import UIKit
import DisciplineCore

// DisciplineShape (the 37.6 pt corner) lives in Shared/DisciplineShape.swift, used by both apps.

extension TintChoice {
    var color: Color {
        switch self {
        case .ember: return Ember.orange
        case .flame: return Ember.flame
        case .red: return Ember.red
        case .sand: return Ember.sand
        case .steel: return Ember.steel
        }
    }
}

/// A Liquid Glass card (iOS 26+ `glassEffect`, the system material, not a blur imitation).
struct GlassCard<Content: View>: View {
    @EnvironmentObject var model: AppModel
    var tinted = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(GlassCardSurface(hero: tinted))
    }
}

/// A plain card is official Liquid Glass over the Ember mesh. The hero card is the same official glass
/// laid over her black → red → flame → sand gradient (read as dark, so its text stays white).
struct GlassCardSurface: ViewModifier {
    var hero: Bool
    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DisciplineShape.cornerRadius, style: .continuous)
        if hero {
            content
                .foregroundStyle(.white)
                .glassEffect(.regular.tint(Ember.black.opacity(0.18)), in: shape)
                .background(Ember.heroGradient, in: shape)
                .environment(\.colorScheme, .dark)
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

struct StatusDot: View {
    let ok: Bool
    var body: some View {
        Circle().fill(ok ? Ember.ok : Ember.warn).frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}

/// Toast banner shown at the top after an action. Its accessibility value is the exact detail
/// (for example the URL handed to a companion app), which the UI tests read.
struct ToastBanner: View {
    let toast: AppModel.Toast
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? Ember.warnText : Ember.ok)
            Text(toast.text).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(toast.text)
        .accessibilityValue(toast.detail)
        .accessibilityIdentifier("toast")
    }
}

struct AppIconView: View {
    let image: UIImage?
    var size: CGFloat = 56
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: "app.dashed").resizable().scaledToFit().padding(size * 0.2).foregroundStyle(.secondary) }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
    }
}

func byteText(_ n: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file) }
