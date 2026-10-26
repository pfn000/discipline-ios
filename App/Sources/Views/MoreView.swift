import Darwin
import UIKit
import SwiftUI
import UniformTypeIdentifiers
import DisciplineCore

struct MoreView: View {
    @EnvironmentObject var model: AppModel
    @State var versionTaps = 0
    @State var versionHolds = 0
    @State var lastTapAt = Date.distantPast
    @State var scanning = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { SetupView().modifier(MoreNavigationBack()) } label: { Label("Setup checklist", systemImage: "checklist") }
                        .accessibilityIdentifier("more.setup")
                    NavigationLink { SettingsView().modifier(MoreNavigationBack()) } label: { Label("Settings", systemImage: "gearshape") }
                        .accessibilityIdentifier("more.settings")
                    NavigationLink { GuardView().modifier(MoreNavigationBack()) } label: { Label("Ouija Guard", systemImage: "eye.trianglebadge.exclamationmark") }
                        .accessibilityIdentifier("more.guard")
                    NavigationLink { UpdatesView().modifier(MoreNavigationBack()) } label: { Label("Updates", systemImage: "arrow.down.circle") }
                        .accessibilityIdentifier("more.updates")
                    if model.labUnlocked {
                        NavigationLink { OuijaBoardView().modifier(MoreNavigationBack()) } label: { Label("Ouija Board", systemImage: "circle.hexagongrid") }
                            .accessibilityIdentifier("more.ouija")
                        NavigationLink { LabView().modifier(MoreNavigationBack()) } label: { Label("NCOM Lab", systemImage: "flask") }
                            .accessibilityIdentifier("more.lab")
                    }
                }
                Section {
                    NavigationLink { SupportView().modifier(MoreNavigationBack()) } label: { Label("Support / Tip", systemImage: "heart") }
                        .accessibilityIdentifier("more.support")
                    NavigationLink { LimitsView().modifier(MoreNavigationBack()) } label: { Label("Honest limits", systemImage: "exclamationmark.shield") }
                        .accessibilityIdentifier("more.limits")
                    NavigationLink { AboutView().modifier(MoreNavigationBack()) } label: { Label("About & credits", systemImage: "info.circle") }
                        .accessibilityIdentifier("more.about")
                }
                Section {
                    Text("Discipline \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // 25 taps in a row; a pause of more than 3 seconds starts the count again.
                            let now = Date()
                            if now.timeIntervalSince(lastTapAt) > 3 { versionTaps = 0 }
                            lastTapAt = now
                            versionTaps += 1
                            if versionTaps >= 25 && !model.labUnlocked {
                                model.labUnlocked = true
                                model.show("Ouija Board developer preview unlocked")
                            }
                        }
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                            versionHolds += 1
                            if versionHolds >= 7 && !model.labUnlocked {
                                model.labUnlocked = true
                                model.show("NCOM Lab unlocked")
                            }
                        })
                        .accessibilityIdentifier("more.version")
                        .accessibilityAddTraits(.isStaticText)
                    Button { scanning = true } label: {
                        Label("Scan NCOM code", systemImage: "qrcode.viewfinder").font(.footnote)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("more.scanQR")
                }
                .listRowBackground(Color.clear)
                Section {
                    NavigationLink { InstallModesView().modifier(MoreNavigationBack()) } label: { Label("Install modes", systemImage: "square.stack.3d.up") }
                        .accessibilityIdentifier("more.installModes")
                }
            }
            .navigationTitle("More")
            .navigationDestination(isPresented: $model.openOuija) { OuijaBoardView().modifier(MoreNavigationBack()) }
            .sheet(isPresented: $scanning) { OuijaScannerSheet() }
        }
    }
}

struct SetupView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let plan = model.setupPlan
        let report = model.compatibility
        List {
            Section {
                Text("\(plan.completed) of \(plan.steps.count) done").font(.headline).accessibilityIdentifier("setup.progress")
            }
            Section("Steps") {
                ForEach(plan.steps) { step in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: step.state == .done ? "checkmark.circle.fill" : (step.state == .blocked ? "lock.circle" : "circle"))
                            .foregroundStyle(step.state == .done ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title).font(.subheadline.weight(.semibold))
                            Text(step.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if step.state == .todo, let action = action(for: step.id) {
                            Button(action.title) { Task { await action.run() } }
                                .buttonStyle(.glass)
                                .accessibilityIdentifier("setup.do.\(step.id.rawValue)")
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("setup.step.\(step.id.rawValue)")
                }
            }
            Section("Your iPhone") {
                LabeledContent("iOS", value: report.version.description)
                LabeledContent("First install", value: bootstrapText(report.bootstrap)).accessibilityIdentifier("setup.bootstrap")
                ForEach(report.notes, id: \.self) { Text($0).font(.caption) }
            }
        }
        .navigationTitle("Setup")
        .onAppear { model.refreshEnvironment() }
    }

    private struct StepAction { let title: String; let run: () async -> Void }

    private func action(for id: SetupPlan.StepID) -> StepAction? {
        switch id {
        case .developerMode: return nil
        case .localDevVPN: return StepAction(title: "Get") { await model.openWeb(Companion.localDevVPN.officialURL) }
        case .vpnConnected: return StepAction(title: "Turn on") { await model.vpnOn() }
        case .sideStore: return StepAction(title: "Get") { await model.openWeb(Companion.sideStore.officialURL) }
        case .liveContainer: return StepAction(title: "Get") { await model.openWeb(Companion.liveContainer.officialURL) }
        case .trackExpiry: return StepAction(title: "Track") { model.tab = .expiry }
        }
    }

    private func bootstrapText(_ b: CompatibilityReport.Bootstrap) -> String {
        switch b {
        case .onDeviceSupported: return "On the phone (no computer)"
        case .needsPairingFileFromComputer: return "Needs a computer once"
        case .unsupported: return "Not supported"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State var token = ""
    @State var importing = false
    @State var backupURL: URL?

    var body: some View {
        Form {
            Section {
                Picker("Apple account", selection: $model.settings.tier) {
                    Text("Free Apple ID (7 days)").tag(AccountTier.free)
                    Text("Paid developer (1 year)").tag(AccountTier.paid)
                }
                .accessibilityIdentifier("settings.tier")
            } footer: {
                Text("A paid Apple Developer Program membership ($99/year) signs apps for 365 days and removes the 3-app and 10-App-ID limits.")
            }
            Section("Look") {
                Picker("Appearance", selection: $model.settings.appearance) {
                    ForEach(AppearanceChoice.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.appearance")
                Picker("Glass tint", selection: $model.settings.tint) {
                    ForEach(TintChoice.allCases) { Text($0.label).tag($0) }
                }
                .accessibilityIdentifier("settings.tint")
            }
            Section {
                TextField("Tunnel address (optional, e.g. 10.7.1.1)", text: $model.settings.expectedTunnelIP)
                    .keyboardType(.numbersAndPunctuation).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .accessibilityIdentifier("settings.tunnelIP")
            } header: { Text("LocalDevVPN") } footer: {
                Text("Set this if you changed LocalDevVPN's device IP, so Home detects the tunnel exactly.")
            }
            Section {
                Toggle("Show pre-releases", isOn: $model.settings.includePrereleases)
                    .accessibilityIdentifier("settings.prereleases")
                SecureField(model.hasToken ? "Token saved (enter a new one to replace)" : "Personal access token (optional)", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("settings.token")
                HStack {
                    Button("Save token") { model.saveToken(token); token = "" }
                        .disabled(token.isEmpty)
                        .accessibilityIdentifier("settings.saveToken")
                    Spacer()
                    Button("Remove token", role: .destructive) { model.saveToken(""); token = "" }
                        .accessibilityIdentifier("settings.removeToken")
                }
                .buttonStyle(.borderless)
            } header: { Text("GitHub") } footer: {
                Text("Stored only in this iPhone's Keychain. A read-only token with no scopes is enough for public repos.")
            }
            Section {
                if let backupURL {
                    ShareLink(item: backupURL) { Label("Share backup file", systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("settings.shareBackup")
                } else {
                    Button { backupURL = model.exportBackup() } label: { Label("Make backup", systemImage: "externaldrive") }
                        .accessibilityIdentifier("settings.makeBackup")
                }
            } header: { Text("Backup") } footer: {
                Text("Saves tracked apps, saved GitHub repos, the App ID log and settings. Imported .ipa files aren't included; keep those in Files.")
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { importing = true } label: { Label("Restore backup", systemImage: "arrow.down.doc") }
                    .accessibilityIdentifier("settings.restore")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { model.importBackup(from: url) }
        }
    }
}

struct SupportView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard(tinted: true) {
                    Text("Discipline is free").font(.title2.bold())
                    Text("No ads, no tracking, no account. If it saves you a weekly headache, a tip keeps it going.")
                        .foregroundStyle(.secondary)
                    Button { Task { await model.openWeb(AppConfig.tipURL) } } label: {
                        Label("Leave a tip", systemImage: "heart.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("support.tip")
                    Text("Opens in Safari. There's no in-app purchase in a sideloaded app.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Support")
    }
}

struct LimitsView: View {
    var body: some View {
        List {
            Section("Signatures") {
                Text("Nothing makes a signature permanent. A free Apple ID signs for 7 days, a paid developer account for 365. Discipline keeps apps alive by starting the refresh itself (auto refresh); it can't stop Apple's clock and it can't re-sign apps by itself.")
                Text("Apps inside LiveContainer don't expire on their own: only LiveContainer (and SideStore) need refreshing.")
            }
            Section("What a free Apple ID can't sign") {
                Text("VPN / Network Extensions, push notifications, Screen Time (Family Controls), NFC tag reading, Siri, iCloud. That's why Discipline uses the App Store LocalDevVPN instead of its own VPN.")
            }
            Section("Refreshing") {
                Text("SideStore has no link that starts a refresh, so auto refresh and Refresh All open LocalDevVPN, which opens SideStore. If SideStore's own background refresh is off, you still tap Refresh All there.")
                Text("Discipline reads its own expiry from its signature. It can't see other apps' signatures on the phone (iOS doesn't allow it), so for those it reads the .ipa you imported, or the date you give it.")
                Text("iOS never lets an app open another app while it's in the background, so auto refresh runs when you open Discipline or when a Shortcuts automation opens it.")
            }
            Section("iOS betas") {
                Text("Apple tightened the VPN check in iOS 26.4. Betas can change it again. Keep LocalDevVPN updated.")
            }
        }
        .navigationTitle("Honest limits")
    }
}

struct AboutView: View {
    struct Credit: Identifiable { let id: String; let who: String; let repo: String }
    let credits: [Credit] = [
        Credit(id: "LocalDevVPN", who: "SideStore team / Jackson Coxson, StosVPN license", repo: "github.com/jkcoxson/LocalDevVPN"),
        Credit(id: "SideStore", who: "SideStore team, AGPL-3.0", repo: "github.com/SideStore/SideStore"),
        Credit(id: "LiveContainer", who: "LiveContainer contributors, AGPL-3.0", repo: "github.com/LiveContainer/LiveContainer"),
        Credit(id: "SideInstaller", who: "FrizzleM, custom non-commercial license", repo: "github.com/FrizzleM/SideInstaller"),
        Credit(id: "Plume Impactor", who: "claration, MIT", repo: "github.com/claration/impactor"),
    ]
    var body: some View {
        List {
            Section {
                Text("Discipline is NCOM's own code. It contains no code from the apps below; it works with them through the links and file types they publish. The loopback-VPN idea it explains comes from em_proxy and LocalDevVPN.")
                    .font(.subheadline)
            }
            Section("Works with") {
                ForEach(credits) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.id).font(.headline)
                        Text(c.who).font(.caption)
                        Text(c.repo).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            Section { Text(AppConfig.sourceCodeNote).font(.caption).foregroundStyle(.secondary) }
        }
        .navigationTitle("About")
    }
}

/// Never present an eligibility table as detection of TrollStore installation or a working loader.
struct InstallModesView: View {
    @EnvironmentObject var model: AppModel
    private var support: TrollStoreSupport.Verdict {
        let build: String? = {
            var size: size_t = 0
            guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else { return nil }
            var buffer = [CChar](repeating: 0, count: size)
            guard buffer.withUnsafeMutableBytes({ ptr in sysctlbyname("kern.osversion", ptr.baseAddress, &size, nil, 0) }) == 0 else { return nil }
            return String(cString: buffer)
        }()
        return TrollStoreSupport.evaluate(version: OSVersion(UIDevice.current.systemVersion), build: build)
    }

    var body: some View {
        List {
            Section("This iPhone") {
                Text("iOS \(UIDevice.current.systemVersion)")
                Text("Only Discipline itself counts as an installed app when a real guest runtime is working. That runtime is not in this build.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Built-in container") {
                Label("Not available yet", systemImage: "hammer")
                Text("Library imports an IPA, but cannot sign or run it inside Discipline. A native loader still needs signing, keychain, entitlement and real-device testing.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("TrollStore") {
                Text(support.rawValue).accessibilityIdentifier("modes.trollStore")
                if support == .eligibleOS {
                    Text("Compatible iOS does not mean TrollStore is installed. Share the IPA to TrollStore explicitly if you already have it; do not use a URL-scheme test as detection.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Section("Available today") {
                Text("Import from Files, inspect the IPA, and hand it to an installed signing or container companion. No silent signing, automatic certificate refresh or free-account cap bypass in Discipline yet.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Install modes")
    }
}

private struct MoreNavigationBack: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label("More", systemImage: "chevron.left") }
                        .accessibilityIdentifier("more.back")
                }
            }
    }
}
