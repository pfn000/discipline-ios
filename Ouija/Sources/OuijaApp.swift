import SwiftUI
import DisciplineCore

@main
struct OuijaApp: App {
    @StateObject private var model = OuijaModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            OuijaRoot()
                .environmentObject(model)
                .onOpenURL { model.handle($0) }
                .task {
                    guard let url = model.testURL else { return }
                    model.testURL = nil
                    try? await Task.sleep(for: .milliseconds(700))
                    model.handle(url)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.checkIslandApproval() }
                }
        }
    }
}

struct OuijaRoot: View {
    @EnvironmentObject var model: OuijaModel

    var body: some View {
        Group {
            if !model.settings.attentionAccepted {
                AttentionPage { withAnimation(.smooth) { model.acceptAttention() } }
            } else if model.settings.agreedAt == nil {
                AgreementPage()
            } else {
                TabView(selection: $model.tab) {
                    Tab("Board", systemImage: "square.grid.3x3.fill", value: OuijaTab.board) {
                        NavigationStack {
                            OuijaBoardMain()
                                .navigationTitle("Ouija Board")
                                .navigationBarTitleDisplayMode(.inline)
                        }
                    }
                    Tab("Sign in", systemImage: "circle.circle", value: OuijaTab.rings) { RingSignInView() }
                    Tab("Keys", systemImage: "person.badge.key.fill", value: OuijaTab.keys) { KeysView() }
                }
            }
        }
        .tint(OuijaStyle.accent)
        .sheet(item: Binding(get: { model.settings.agreedAt == nil ? nil : model.pendingRequest },
                             set: { model.pendingRequest = $0 })) { req in
            AuthorizeSheet(request: req)
                .presentationDetents([.large])
                .interactiveDismissDisabled()
        }
    }
}

enum OuijaStyle {
    /// One accent for the whole app: a muted violet that reads on both light and dark glass.
    static let accent = Color(red: 0.48, green: 0.40, blue: 0.95)
    static let ok = Color(red: 0.20, green: 0.78, blue: 0.47)
    static let bad = Color(red: 0.95, green: 0.33, blue: 0.33)
}
