import SwiftUI
import BackgroundTasks
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
                    switch phase {
                    case .active: Task { await model.becameActive() }
                    case .background: DisciplineApp.scheduleBackgroundCheck()
                    default: break
                    }
                }
        }
        // iOS wakes Discipline now and then (its own schedule) to check for updates and re-read expiry.
        // iOS doesn't allow opening SideStore from the background, so the refresh itself runs on the next open.
        .backgroundTask(.appRefresh(AppConfig.backgroundRefreshID)) {
            DisciplineApp.scheduleBackgroundCheck()
            await AppModel.current?.backgroundCheck()
        }
    }

    nonisolated static func scheduleBackgroundCheck() {
        let request = BGAppRefreshTaskRequest(identifier: AppConfig.backgroundRefreshID)
        request.earliestBeginDate = Date().addingTimeInterval(6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView(selection: $model.tab) {
            Tab("Home", systemImage: "shield.lefthalf.filled", value: AppTab.home) { HomeView() }
            Tab("Library", systemImage: "shippingbox", value: AppTab.library) { LibraryView() }
            Tab("Store", systemImage: "bag.fill", value: AppTab.github) { StoreTab() }
            Tab("Expiry", systemImage: "timer", value: AppTab.expiry) { ExpiryView() }
            Tab("More", systemImage: "ellipsis.circle", value: AppTab.more) { MoreView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(model.settings.tint.color)
        .preferredColorScheme(model.settings.appearance == .system ? nil : (model.settings.appearance == .dark ? .dark : .light))
        .overlay {
            if let ring = model.magicRing {
                MagicRingView(state: ring) { model.finishMagicRing() }
                    .transition(.opacity)
            }
        }
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
        .task { await model.becameActive() }
    }
}
