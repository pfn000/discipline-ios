import SwiftUI
import DisciplineCore

struct ExpiryView: View {
    @EnvironmentObject var model: AppModel
    @State var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(get: { model.settings.autoRefresh },
                                         set: { on in Task { await model.setAutoRefresh(on) } })) {
                        Label("Auto refresh", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityIdentifier("expiry.autoRefresh")
                    if !model.autoRefreshStatus.isEmpty {
                        Text(model.autoRefreshStatus).font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("expiry.autoStatus")
                    }
                    ownSignatureRow
                } footer: {
                    Text("No reminders. When an app has 2 days or less left, Discipline starts SideStore's refresh by itself as soon as you open it (LocalDevVPN on, then SideStore). For a fully hands-off refresh, add Discipline's \"Auto Refresh Due Apps\" action to a Shortcuts automation (for example, when your iPhone starts charging). iOS doesn't let any app open SideStore from the background.")
                }

                Section("Apps") {
                    if model.trackedApps.isEmpty {
                        Text("Nothing tracked yet").foregroundStyle(.secondary).accessibilityIdentifier("expiry.empty")
                    }
                    ForEach(model.trackedApps) { app in
                        let status = model.tracker.status(of: app, now: model.now)
                        HStack {
                            VStack(alignment: .leading) {
                                Text(app.name).font(.headline)
                                if app.expiryIsRead {
                                    Text("Expiry read from its signature").font(.caption).foregroundStyle(.secondary)
                                        .accessibilityIdentifier("expiry.read.\(app.bundleID)")
                                } else {
                                    Text("\(app.tier == .free ? "7-day" : "1-year") signature").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(ExpiryTracker.shortText(status))
                                .font(.subheadline.monospacedDigit().bold())
                                .foregroundStyle(color(status))
                                .accessibilityIdentifier("expiry.left.\(app.bundleID)")
                            Button("Refreshed") { model.markRefreshed(app) }
                                .buttonStyle(.glass)
                                .accessibilityIdentifier("expiry.refreshed.\(app.bundleID)")
                        }
                        .accessibilityElement(children: .contain)
                        .swipeActions {
                            Button(role: .destructive) { model.removeTracked(app) } label: { Label("Stop tracking", systemImage: "trash") }
                        }
                        .accessibilityIdentifier("expiry.row.\(app.bundleID)")
                    }
                    Button { showAdd = true } label: { Label("Add app", systemImage: "plus") }
                        .accessibilityIdentifier("expiry.add")
                }

                Section {
                    let used = model.budget.used(now: model.now)
                    if let cap = model.settings.tier.appIDsPerWeek {
                        Gauge(value: Double(min(used, cap)), in: 0...Double(cap)) {
                            Text("App IDs this week")
                        } currentValueLabel: {
                            Text("\(used)/\(cap)")
                        }
                        .accessibilityIdentifier("expiry.budgetGauge")
                        if let next = model.budget.nextAvailable(now: model.now), next > model.now {
                            Text("Next free slot: \(next.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                        }
                    } else {
                        Text("Paid account: no weekly App ID limit").accessibilityIdentifier("expiry.budgetUnlimited")
                    }
                    Button { model.budget.record(Date()); model.show("Logged 1 App ID") } label: { Label("Log an App ID use", systemImage: "plus.circle") }
                        .accessibilityIdentifier("expiry.logAppID")
                    Button(role: .destructive) { model.resetBudget() } label: { Label("Clear App ID log", systemImage: "arrow.counterclockwise") }
                        .accessibilityIdentifier("expiry.resetBudget")
                } header: { Text("App ID slots") } footer: {
                    Text("A free Apple ID can create 10 App IDs per 7 days; every app and every extension signed directly uses one. Apps inside LiveContainer use none.")
                }

                if !model.trackedApps.isEmpty {
                    Section("At a glance") {
                        ExpiryChart()
                            .padding(.vertical, 6)
                    }
                }
            }
            .disciplineListBackdrop()
            .navigationTitle("Expiry")
            .sheet(isPresented: $showAdd) { AddTrackedAppSheet() }
        }
    }

    @ViewBuilder private var ownSignatureRow: some View {
        switch model.ownSignature {
        case .notRead:
            EmptyView()
        case .unreadable(let why):
            Label(why, systemImage: "signature").font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("expiry.ownSignature")
        case .read(let expires, let tier):
            Label("Discipline's own signature (\(tier == .free ? "free Apple ID" : "paid account")) runs out \(expires.formatted(date: .abbreviated, time: .shortened))",
                  systemImage: "signature")
                .font(.caption)
                .accessibilityIdentifier("expiry.ownSignature")
        }
    }

    private func color(_ s: ExpiryStatus) -> Color {
        switch s {
        case .healthy: return .green
        case .refreshSoon: return .orange
        case .expired: return .red
        }
    }
}

struct AddTrackedAppSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var name: String
    @State var bundleID: String
    @State var signedAt = Date()

    /// The signing date can't be read from an .ipa, so the user confirms when it was last signed or refreshed.
    init(name: String = "", bundleID: String = "") {
        _name = State(initialValue: name)
        _bundleID = State(initialValue: bundleID)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("App name", text: $name).accessibilityIdentifier("add.name")
                TextField("Bundle ID (optional)", text: $bundleID)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("add.bundleID")
                Section {
                    DatePicker("Signed / refreshed", selection: $signedAt, in: ...Date())
                        .accessibilityIdentifier("add.date")
                } footer: {
                    Text("Only needed for apps Discipline can't read. Pick when Plume Impactor or SideStore last signed or refreshed it; the countdown counts from this date. Signed .ipa files in the Library are tracked with their real expiry.")
                }
            }
            .navigationTitle("Track an app")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("add.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let id = bundleID.trimmingCharacters(in: .whitespaces)
                        let n = name.trimmingCharacters(in: .whitespaces)
                        model.addTracked(TrackedApp(name: n, bundleID: id.isEmpty ? "manual.\(n.lowercased().filter { $0.isLetter || $0.isNumber })" : id,
                                                    signedAt: signedAt, tier: model.settings.tier))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("add.save")
                }
            }
        }
    }
}
