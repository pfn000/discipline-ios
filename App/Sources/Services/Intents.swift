import AppIntents
import DisciplineCore

/// Shortcuts / Siri Suggestions actions. App Intents live in the main app (no extension, no
/// extra App ID) and need no restricted entitlement.
struct RefreshAllIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh All Sideloaded Apps"
    static var description = IntentDescription("Turns on LocalDevVPN, which then opens SideStore so you can refresh.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.current?.refreshEnvironment()
        await AppModel.current?.refreshAll()
        return .result()
    }
}

/// For a Shortcuts personal automation (e.g. "When iPhone starts charging" → this, run immediately):
/// opens Discipline and starts SideStore's refresh only if an app is due. Nothing happens otherwise.
struct AutoRefreshIntent: AppIntent {
    static var title: LocalizedStringResource = "Auto Refresh Due Apps"
    static var description = IntentDescription("If a tracked app has 2 days or less left, turns on LocalDevVPN and opens SideStore to refresh it.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let model = AppModel.current else { return .result() }
        model.refreshEnvironment()
        model.readOwnSignature()
        await model.runAutoRefreshIfDue()
        return .result()
    }
}

struct VPNOnIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn On LocalDevVPN"
    static var description = IntentDescription("Asks LocalDevVPN to connect, then comes back to Discipline.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.current?.refreshEnvironment()
        await AppModel.current?.vpnOn()
        return .result()
    }
}

struct DisciplineShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RefreshAllIntent(),
                    phrases: ["Refresh my apps with \(.applicationName)", "\(.applicationName) refresh all"],
                    shortTitle: "Refresh All", systemImageName: "arrow.triangle.2.circlepath")
        AppShortcut(intent: AutoRefreshIntent(),
                    phrases: ["Auto refresh with \(.applicationName)"],
                    shortTitle: "Auto Refresh", systemImageName: "arrow.triangle.2.circlepath.circle")
        AppShortcut(intent: VPNOnIntent(),
                    phrases: ["Turn on the sideload VPN with \(.applicationName)"],
                    shortTitle: "VPN On", systemImageName: "bolt.horizontal.circle")
    }
}
