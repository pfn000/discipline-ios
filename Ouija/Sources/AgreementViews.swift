import SwiftUI
import UIKit
import DisciplineCore

/// "Attention" page: one plain warning and a single "I agree" button (Saidie, Oct 28: "usually it's a
/// simple I agree button here").
struct AttentionPage: View {
    let onAgree: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 54, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
            Text("Attention")
                .font(.largeTitle.bold())
                .padding(.top, 20)
                .accessibilityIdentifier("ouija.attention")
            Text("Ouija is only meant for NCOM developers.")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.top, 10)
                .accessibilityIdentifier("ouija.warning")
            Text("Prototype hardware control isn't connected in this build. You'll read and accept the full agreement next.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
                .frame(maxWidth: 340)
            Spacer()
            Button(action: onAgree) {
                Text("I agree")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .accessibilityIdentifier("ouija.iAgree")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }
}

/// The terms. DRAFT wording written for Saidie on Oct 28, 2026; not legal advice (noted in the review).
enum OuijaTerms {
    struct Clause: Identifiable { let id: Int; let title: String; let body: String }
    static let clauses: [Clause] = [
        Clause(id: 1, title: "What Ouija is",
               body: "Ouija is an advanced, licensed, team-developer tool for penetration testing and for testing prototypes. It is not a consumer product and it is identified only as that tool."),
        Clause(id: 2, title: "Who may use it",
               body: "Only NCOM developers and team members licensed by NCOM may use Ouija, and only on devices, accounts and systems they own or have written permission to test."),
        Clause(id: 3, title: "Your responsibility",
               body: "You accept full legal responsibility for any jailbreaking, modification, or illegal activity carried out on your end, on your devices, or with your accounts, whether or not Ouija was involved."),
        Clause(id: 4, title: "No warranty",
               body: "Ouija is prototype software provided as is. Features may be incomplete, may change, or may stop working, and NCOM gives no promise that any test result is complete or correct."),
        Clause(id: 5, title: "Keys and sign-in",
               body: "Ouija creates a signing key on this iPhone. Apps you approve receive an answer signed with that key. Keep this phone locked; anyone holding it unlocked can approve sign-ins as you."),
        Clause(id: 6, title: "Records",
               body: "Ouija records on this iPhone the time you agree to these terms and each sign-in you approve. Nothing is sent to NCOM by Ouija itself."),
        Clause(id: 7, title: "Your acknowledgement",
               body: "Sliding your own profile picture across the bar below is your personal acknowledgement that you have read these terms, that you agree to them, and that you are the person who slid it."),
    ]
}

/// "Agreement" page: the terms scroll; the slider stays locked until the end has been reached; then the
/// profile picture becomes a gently pulsing handle you drag across to agree.
struct AgreementPage: View {
    @EnvironmentObject var model: OuijaModel
    @State private var reachedEnd = false
    @State private var agreedAt: Date?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Agreement").font(.largeTitle.bold()).accessibilityIdentifier("ouija.agreement")
                Text("Read to the end to unlock the slider.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(OuijaTerms.clauses) { c in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(c.id). \(c.title)").font(.headline)
                            Text(c.body).font(.body).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("End of agreement")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                        .accessibilityIdentifier("agreement.end")
                }
                .padding(22)
            }
            .scrollIndicators(.visible)
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 12
            } action: { _, atEnd in
                if atEnd && !reachedEnd {
                    withAnimation(.smooth) { reachedEnd = true }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
            .accessibilityIdentifier("agreement.terms")

            VStack(spacing: 10) {
                ProfileSlideToAgree(locked: !reachedEnd, done: agreedAt != nil, identifier: "agreement.handle",
                                    lockedText: "Read to the end to unlock",
                                    idleText: "Slide your photo to agree") {
                    agreedAt = Date()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + (OuijaTest.active ? 1.6 : 1.0)) {
                        withAnimation(.smooth) { model.settings.agreedAt = agreedAt }
                    }
                }
                Text(agreedAt.map { "Agreed \($0.formatted(date: .abbreviated, time: .standard)) as \(model.displayName)" } ?? "Signed in as \(model.displayName)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("agreement.status")
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }
}

/// The user's circular profile picture, or their initials when there is no photo.
struct ProfileAvatar: View {
    @EnvironmentObject var model: OuijaModel
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            if let img = model.profileImage {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [OuijaStyle.accent, OuijaStyle.accent.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(model.initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 2))
    }
}

/// Slide-to-agree with the profile picture as the handle. `locked` greys it out and ignores drags.
/// Its accessibility value is "locked", "unlocked" or "agreed" (the UI tests read it).
struct ProfileSlideToAgree: View {
    let locked: Bool
    let done: Bool
    let identifier: String
    let lockedText: String
    let idleText: String
    let onComplete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var pulse = false
    @State private var trace = "no drag yet"   // UI tests read it when a slide doesn't finish
    private let knob: CGFloat = 56
    private let inset: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let maxX = max(1, geo.size.width - knob - inset * 2)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(OuijaStyle.accent.opacity(done ? 0.35 : 0.12 * Double(offset / maxX) + 0.04))
                Text(done ? "Agreed" : (locked ? lockedText : idleText))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(locked ? HierarchicalShapeStyle.tertiary : HierarchicalShapeStyle.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, knob)
                    .opacity(done ? 1 : 1 - Double(offset / maxX) * 1.4)
                    .accessibilityHidden(true)
                ProfileAvatar(size: knob)
                    .scaleEffect(pulse ? 1.07 : 1)
                    .shadow(color: OuijaStyle.accent.opacity(pulse ? 0.55 : 0.0), radius: pulse ? 14 : 0)
                    .overlay {
                        if done {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white, OuijaStyle.ok)
                                .offset(x: knob * 0.34, y: knob * 0.34)
                        }
                    }
                    .offset(x: inset + offset)
                    .highPriorityGesture(drag(maxX: maxX))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Profile slider")
                    .accessibilityValue(done ? "agreed" : (locked ? "locked" : "unlocked"))
                    .accessibilityAddTraits(.allowsDirectInteraction)
                    .accessibilityIdentifier(identifier)
            }
            .glassEffect(.regular, in: Capsule())
            .onChange(of: done) { _, d in if d { offset = maxX } }
            .overlay(alignment: .bottomTrailing) {
                if OuijaTest.active {
                    Text(trace).font(.system(size: 2)).opacity(0.02)
                        .accessibilityIdentifier(identifier + ".trace")
                }
            }
        }
        .frame(height: knob + inset * 2)
        .opacity(locked ? 0.5 : 1)
        .onChange(of: locked) { _, l in startPulse(!l) }
        .onAppear { startPulse(!locked) }
    }

    private func startPulse(_ on: Bool) {
        // A gentle pulse invites the drag. Under UI tests it stays still so XCTest's idle wait isn't held.
        guard on, !done, !OuijaTest.active else { pulse = false; return }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
    }

    private func drag(maxX: CGFloat) -> some Gesture {
        // Global space: the handle moves with the finger, so a local translation would shrink as it slides.
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { v in
                if OuijaTest.active { trace = "moving \(Int(v.translation.width)) of \(Int(maxX))\(locked ? " locked" : "")" }
                guard !locked, !done else { return }
                offset = min(max(0, v.translation.width), maxX)
            }
            .onEnded { v in
                if OuijaTest.active { trace = "ended \(Int(v.translation.width)) offset \(Int(offset)) of \(Int(maxX))\(locked ? " locked" : "")" }
                guard !locked, !done else { return }
                if offset >= maxX * 0.85 {
                    withAnimation(.spring(duration: 0.25)) { offset = maxX }
                    pulse = false
                    onComplete()
                } else {
                    withAnimation(.spring(duration: 0.35)) { offset = 0 }
                }
            }
    }
}
