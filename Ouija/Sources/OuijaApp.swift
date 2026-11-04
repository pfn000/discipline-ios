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
        .tint(OuijaStyle.accentText)
        .overlay(alignment: .bottomLeading) {
            if OuijaTest.active {
                Text(model.urlTrace + (model.pendingRequest == nil ? " · no pending" : " · pending"))
                    .font(.system(size: 2)).opacity(0.02)
                    .accessibilityIdentifier("ouija.urlTrace")
            }
        }
        .sheet(item: Binding(get: { model.settings.agreedAt == nil ? nil : model.pendingRequest },
                             set: { model.pendingRequest = $0 })) { req in
            AuthorizeSheet(request: req)
                .presentationDetents([.large])
                .interactiveDismissDisabled()
        }
    }
}

enum OuijaStyle {
    /// Ember palette, shared with Discipline: orange #E85002 for fills (always black text on it),
    /// #C10801 for orange text on light backgrounds, #E85002 for orange text on dark ones.
    static let accent = Color(red: 0xE8 / 255, green: 0x50 / 255, blue: 0x02 / 255)
    static let onAccent = Color.black
    static let accentText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xE8 / 255, green: 0x50 / 255, blue: 0x02 / 255, alpha: 1)
            : UIColor(red: 0xC1 / 255, green: 0x08 / 255, blue: 0x01 / 255, alpha: 1)
    })
    /// Her gradient's warm middle (#C10801 → #F16001), for the avatar fill.
    static let gradient = [Color(red: 0xC1 / 255, green: 0x08 / 255, blue: 0x01 / 255), Color(red: 0xF1 / 255, green: 0x60 / 255, blue: 0x01 / 255)]
    static let ok = Color(red: 0.20, green: 0.78, blue: 0.47)
    static let bad = Color(red: 0.95, green: 0.33, blue: 0.33)
}
