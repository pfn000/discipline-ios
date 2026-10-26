import SwiftUI
import DisciplineCore

/// Auto-update: Discipline's own releases and the saved GitHub repos, checked by themselves.
struct UpdatesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List {
            Section {
                LabeledContent("Installed", value: "Discipline \(model.appVersion)")
                    .accessibilityIdentifier("updates.installed")
                Text(model.selfUpdateStatus).accessibilityIdentifier("updates.status")
                if let u = model.selfUpdate {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(u.title).font(.headline).accessibilityIdentifier("updates.title")
                        if let notes = u.body, !notes.isEmpty {
                            Text(notes).font(.callout).accessibilityIdentifier("updates.notes")
                        }
                    }
                    Button { Task { await model.downloadSelfUpdate() } } label: {
                        Label("Download \(u.tagName)", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("updates.download")
                }
                Button { Task { await model.checkSelfUpdate() } } label: {
                    if model.updateChecking { ProgressView() } else { Label("Check now", systemImage: "arrow.clockwise") }
                }
                .accessibilityIdentifier("updates.check")
            } header: { Text("Discipline") } footer: {
                Text("Discipline reads the release notes of each new version from github.com/\(AppConfig.updateRepo.fullName) Releases. iOS doesn't let an app replace itself: the new .ipa goes to your Library and SideStore or LiveContainer installs it.")
            }
            Section {
                Toggle("Check automatically", isOn: $model.settings.autoCheckUpdates)
                    .accessibilityIdentifier("updates.autoCheck")
                Toggle("Download new versions automatically", isOn: $model.settings.autoDownloadUpdates)
                    .accessibilityIdentifier("updates.autoDownload")
                if let last = model.settings.lastUpdateCheck {
                    Text("Last automatic check: \(last.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                        .accessibilityIdentifier("updates.lastCheck")
                }
            } header: { Text("Automatic") } footer: {
                Text("Checks Discipline and every saved repo in the GitHub tab when you open the app (at most every 6 hours) and when iOS gives Discipline background time. Downloads go to the Library.")
            }
        }
        .navigationTitle("Updates")
    }
}
