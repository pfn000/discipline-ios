import SwiftUI
import UIKit
import UniformTypeIdentifiers
import DisciplineCore

struct GuardView: View {
    @EnvironmentObject var model: AppModel
    @State var scanned: (name: String, findings: [TrackerFinding])?
    @State var report: PrivacyReport?
    @State var importingReport = false

    var body: some View {
        List {
            Section {
                if model.library.isEmpty {
                    Text("Add an .ipa to the Library to scan it.").foregroundStyle(.secondary).accessibilityIdentifier("guard.noApps")
                }
                ForEach(model.library) { item in
                    HStack {
                        AppIconView(image: model.icon(for: item), size: 32)
                        Text(item.displayName)
                        Spacer()
                        Button("Scan") { scan(item) }
                            .buttonStyle(.glass)
                            .accessibilityIdentifier("guard.scan.\(item.bundleID)")
                    }
                }
                if let scanned {
                    if scanned.findings.isEmpty {
                        Label("No known trackers found in \(scanned.name)", systemImage: "checkmark.shield")
                            .foregroundStyle(.green).accessibilityIdentifier("guard.clean")
                    } else {
                        Text("\(scanned.findings.count) tracker SDK\(scanned.findings.count == 1 ? "" : "s") in \(scanned.name)")
                            .font(.headline).accessibilityIdentifier("guard.findingsCount")
                        ForEach(scanned.findings, id: \.self) { f in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.signature.name).font(.subheadline.weight(.semibold))
                                Text("\(f.signature.category.rawValue) · \(f.evidence.rawValue): \(f.detail)").font(.caption).foregroundStyle(.secondary)
                            }
                            .accessibilityIdentifier("guard.finding.\(f.signature.name)")
                        }
                    }
                }
            } header: { Text("Tracker scan") } footer: {
                Text("Looks for 20 common ads, analytics and attribution SDKs by their framework and class names. A class-name match means \"likely\", not proof.")
            }

            Section {
                Button { importingReport = true } label: { Label("Import App Privacy Report", systemImage: "doc.text.magnifyingglass") }
                    .accessibilityIdentifier("guard.importReport")
                if let report {
                    Text("\(report.apps.count) apps · \(report.totalTrackerContacts) tracker domains contacted")
                        .font(.headline).accessibilityIdentifier("guard.reportSummary")
                    ForEach(report.apps.prefix(25)) { app in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.bundleID).font(.subheadline.monospaced())
                            if !app.sensorAccess.isEmpty {
                                Text("Used: " + app.sensorAccess.sorted { $0.key < $1.key }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")).font(.caption)
                            }
                            if !app.trackerDomains.isEmpty {
                                Text("Trackers: " + app.trackerDomains.sorted { $0.key < $1.key }.map { "\($0.value) (\($0.key))" }.joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            Text("\(app.domains.count) domains").font(.caption2).foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("guard.reportApp.\(app.bundleID)")
                    }
                }
            } header: { Text("App Privacy Report") } footer: {
                Text("On your iPhone: Settings → Privacy & Security → App Privacy Report → Save App Activity. Then import the .ndjson file here. It stays on your phone.")
            }

            Section {
                Button { Task { await model.openWeb(URL(string: UIApplication.openSettingsURLString)!) } } label: {
                    Label("Open Settings", systemImage: "gear")
                }
                .accessibilityIdentifier("guard.openSettings")
            } footer: {
                Text("Apple only lets apps open their own Settings page; from there go back to Privacy & Security.")
            }
        }
        .disciplineListBackdrop()
        .navigationTitle("Ouija Guard")
        .fileImporter(isPresented: $importingReport, allowedContentTypes: [UTType(filenameExtension: "ndjson") ?? .json, .json, .plainText, .data]) { result in
            if case .success(let url) = result { loadReport(url) }
        }
        .onAppear {
            if TestHooks.isUITesting, report == nil, ProcessInfo.processInfo.arguments.contains("-uiTestingPrivacyReport"),
               let url = Bundle.main.url(forResource: "privacy-report", withExtension: "ndjson") { loadReport(url) }
        }
    }

    private func scan(_ item: LibraryItem) {
        do {
            let bytes = [UInt8](try Data(contentsOf: model.fileURL(for: item)))
            scanned = (item.displayName, try TrackerScanner.scan(ipaBytes: bytes))
        } catch {
            model.show("Couldn't scan: \(error)", error: true)
        }
    }

    private func loadReport(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { model.show("Couldn't read that file.", error: true); return }
        let r = PrivacyReport.parse(data)
        if r.apps.isEmpty { model.show("That file has no App Privacy Report entries.", error: true) }
        else { report = r; model.show("Read \(r.lineCount) report lines") }
    }
}
