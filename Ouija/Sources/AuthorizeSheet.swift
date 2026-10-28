import SwiftUI
import DisciplineCore

/// The full approval sheet for "Sign in with Ouija": the asking app, the account, and the profile slide.
/// This is where the drag happens (the Dynamic Island only allows buttons).
struct AuthorizeSheet: View {
    @EnvironmentObject var model: OuijaModel
    let request: AuthRequest
    @State private var done = false

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(.quaternary).frame(width: 40, height: 5).padding(.top, 10)
            Spacer(minLength: 20)
            ZStack {
                Circle().fill(OuijaStyle.accent.opacity(0.12)).frame(width: 148, height: 148)
                Circle().strokeBorder(OuijaStyle.accent.opacity(0.35), lineWidth: 1).frame(width: 188, height: 188)
                ProfileAvatar(size: 104)
            }
            Text("\(request.client) wants to sign in to your account")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.top, 24)
                .accessibilityIdentifier("authorize.title")
            VStack(spacing: 4) {
                Text(model.displayName).font(.headline).accessibilityIdentifier("authorize.account")
                Text("Ouija key \(model.deviceFingerprint)")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)
            Text("\(request.client) gets your account name and a one-time answer signed by this iPhone. Nothing else is shared.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
                .frame(maxWidth: 330)
            Spacer()
            ProfileSlideToAgree(locked: false, done: done, identifier: "authorize.handle",
                                lockedText: "", idleText: "Slide your photo to approve") {
                done = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { model.approve(request, how: "slide") }
            }
            Button("Decline", role: .cancel) { model.decline(request) }
                .padding(.top, 14)
                .accessibilityIdentifier("authorize.decline")
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
        .accessibilityIdentifier("authorize.sheet")
    }
}
