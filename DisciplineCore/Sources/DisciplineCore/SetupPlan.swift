import Foundation

/// The checklist Discipline walks the user through. Each step's state is computed from what
/// the app can observe (installed companions, tunnel state, tracked apps) — never assumed.
public struct SetupPlan: Equatable, Sendable {
    public enum StepID: String, CaseIterable, Codable, Sendable {
        case developerMode, localDevVPN, vpnConnected, sideStore, liveContainer, trackExpiry
    }

    public enum StepState: String, Codable, Sendable { case done, todo, blocked }

    public struct Step: Equatable, Identifiable, Sendable {
        public let id: StepID
        public let title: String
        public let detail: String
        public let state: StepState
    }

    public struct Observations: Equatable, Sendable {
        public var installed: Set<Companion>
        public var tunnel: TunnelState
        public var trackedApps: Int
        public var os: OSVersion
        /// Discipline itself is running, so on iOS 16+ Developer Mode must already be on.
        public var disciplineIsRunning: Bool

        public init(installed: Set<Companion>, tunnel: TunnelState, trackedApps: Int, os: OSVersion, disciplineIsRunning: Bool = true) {
            self.installed = installed; self.tunnel = tunnel; self.trackedApps = trackedApps
            self.os = os; self.disciplineIsRunning = disciplineIsRunning
        }
    }

    public let steps: [Step]

    public var completed: Int { steps.filter { $0.state == .done }.count }
    public var nextStep: Step? { steps.first { $0.state == .todo } }

    public init(_ o: Observations) {
        let hasVPNApp = o.installed.contains(.localDevVPN)
        let vpnUp: Bool = { if case .connected = o.tunnel { return true }; return false }()
        var s: [Step] = []
        s.append(Step(id: .developerMode, title: "Developer Mode",
                      detail: "Needed for any sideloaded app. It's on, or Discipline couldn't open.",
                      state: o.disciplineIsRunning ? .done : .todo))
        s.append(Step(id: .localDevVPN, title: "Get LocalDevVPN",
                      detail: "Free on the App Store. It's the loopback VPN the other apps need.",
                      state: hasVPNApp ? .done : .todo))
        s.append(Step(id: .vpnConnected, title: "Turn the VPN on",
                      detail: "Needed whenever you install or refresh. It never leaves your phone.",
                      state: vpnUp ? .done : (hasVPNApp ? .todo : .blocked)))
        s.append(Step(id: .sideStore, title: "Install SideStore",
                      detail: "Signs and refreshes apps on the phone with your Apple ID.",
                      state: o.installed.contains(.sideStore) ? .done : .todo))
        s.append(Step(id: .liveContainer, title: "Install LiveContainer",
                      detail: "Runs many apps inside one, past the 3-app limit of a free Apple ID.",
                      state: o.installed.contains(.liveContainer) ? .done : .todo))
        s.append(Step(id: .trackExpiry, title: "Track your app expiry",
                      detail: "Add each sideloaded app so Discipline can remind you before its 7 days run out.",
                      state: o.trackedApps > 0 ? .done : .todo))
        steps = s
    }
}
