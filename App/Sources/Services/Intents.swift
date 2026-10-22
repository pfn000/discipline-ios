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
        AppShortcut(intent: VPNOnIntent(),
                    phrases: ["Turn on the sideload VPN with \(.applicationName)"],
                    shortTitle: "VPN On", systemImageName: "bolt.horizontal.circle")
    }
}
