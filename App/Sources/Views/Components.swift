import SwiftUI
import UIKit
import DisciplineCore

// DisciplineShape (the 37.6 pt corner) lives in Shared/DisciplineShape.swift, used by both apps.

extension TintChoice {
    var color: Color {
        switch self {
        case .ocean: return .blue
        case .violet: return .purple
        case .rose: return .pink
        case .mint: return .mint
        case .amber: return .orange
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
            .glassEffect(tinted ? .regular.tint(model.settings.tint.color.opacity(0.35)) : .regular,
                         in: .rect(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
    }
}

struct StatusDot: View {
    let ok: Bool
    var body: some View {
        Circle().fill(ok ? Color.green : Color.orange).frame(width: 10, height: 10)
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
                .foregroundStyle(toast.isError ? .orange : .green)
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
