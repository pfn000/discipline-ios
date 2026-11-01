import SwiftUI
import DisciplineCore

@main
struct OuijaApp: App {
    @StateObject private var model = OuijaModel()
    @StateObject private var sniffer = Sniffer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            OuijaRoot()
                .environmentObject(model)
                .environmentObject(sniffer)
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
            if OuijaTest.has("-uiTestingSphereShowcase") {
                SphereShowcase()
            } else if !model.settings.attentionAccepted {
                AttentionPage { withAnimation(.smooth) { model.acceptAttention() } }
            } else if model.account == nil {
                AccountPage()
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
        .overlay(alignment: .bottomLeading) {
            if OuijaTest.active {
                Text(model.urlTrace + (model.pendingRequest == nil ? " · no pending" : " · pending"))
                    .font(.system(size: 2)).opacity(0.02)
                    .accessibilityIdentifier("ouija.urlTrace")
            }
        }
        .sheet(item: Binding(get: { model.settings.agreedAt == nil || model.account == nil ? nil : model.pendingRequest },
                             set: { model.pendingRequest = $0 })) { req in
            AuthorizeSheet(request: req)
                .tint(OuijaStyle.accent)
                .presentationDetents([.large])
                .interactiveDismissDisabled()
        }
    }
}
