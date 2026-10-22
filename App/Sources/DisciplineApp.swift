import SwiftUI
import DisciplineCore

@main
struct DisciplineApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onOpenURL { model.handleIncoming($0) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.refreshEnvironment() }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView(selection: $model.tab) {
            Tab("Home", systemImage: "shield.lefthalf.filled", value: AppTab.home) { HomeView() }
            Tab("Library", systemImage: "shippingbox", value: AppTab.library) { LibraryView() }
            Tab("GitHub", systemImage: "arrow.down.app", value: AppTab.github) { GitHubView() }
            Tab("Expiry", systemImage: "timer", value: AppTab.expiry) { ExpiryView() }
            Tab("More", systemImage: "ellipsis.circle", value: AppTab.more) { MoreView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(model.settings.tint.color)
        .preferredColorScheme(model.settings.appearance == .system ? nil : (model.settings.appearance == .dark ? .dark : .light))
        .overlay(alignment: .top) {
            if let t = model.toast {
                ToastBanner(toast: t)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { model.toast = nil }
                    .task(id: t.id) {
                        try? await Task.sleep(for: .seconds(TestHooks.isUITesting ? 6 : 3))
                        if model.toast?.id == t.id { withAnimation { model.toast = nil } }
                    }
            }
        }
        .animation(.snappy, value: model.toast)
    }
}
