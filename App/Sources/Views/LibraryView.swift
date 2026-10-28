import SwiftUI
import UniformTypeIdentifiers
import DisciplineCore

extension UTType {
    /// Declared in Info.plist (UTImportedTypeDeclarations) so Files and Safari offer "Open in Discipline".
    static let ipa = UTType(importedAs: "com.apple.itunes.ipa", conformingTo: .zip)
}

struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @State var importing = false
    @State var showURLSheet = false

    var body: some View {
        NavigationStack(path: $model.libraryPath) {
            List {
                if !model.library.isEmpty {
                    Section {
                        StatStrip {
                            StatTile(value: "\(model.library.count)", label: "Apps", systemImage: "shippingbox.fill",
                                     tint: model.settings.tint.color, id: "library.stat.apps")
                            StatTile(value: byteText(model.library.reduce(0) { $0 + $1.fileSize }), label: "On device",
                                     systemImage: "internaldrive", tint: .purple, id: "library.stat.size")
                            StatTile(value: "\(model.library.reduce(0) { $0 + $1.appIDCost })", label: "App IDs to sign",
                                     systemImage: "signature", tint: .orange, id: "library.stat.appIDs")
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }
                }
                Section {
                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 12) {
                            Button { importing = true } label: { Label("Import .ipa", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity) }
                                .buttonStyle(.glassProminent)
                                .accessibilityIdentifier("library.import")
                            Button { showURLSheet = true } label: { Label("From link", systemImage: "link").frame(maxWidth: .infinity) }
                                .buttonStyle(.glass)
                                .accessibilityIdentifier("library.fromLink")
                        }
                    }
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Tip: tap any .ipa in Files or Safari and choose Discipline. It opens here.")
                }
                if model.library.isEmpty {
                    Text("No apps yet").foregroundStyle(.secondary).accessibilityIdentifier("library.empty")
                }
                ForEach(model.library) { item in
                    NavigationLink(value: item.id) {
                        HStack(spacing: 12) {
                            AppIconView(image: model.icon(for: item), size: 44)
                            VStack(alignment: .leading) {
                                Text(item.displayName).font(.headline)
                                Text("\(item.version) · \(item.origin)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("library.item.\(item.bundleID)")
                    .swipeActions {
                        Button(role: .destructive) { model.deleteLibraryItem(item) } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .disciplineListBackdrop()
            .navigationTitle("Library")
            .navigationDestination(for: UUID.self) { id in
                if let item = model.library.first(where: { $0.id == id }) { IPADetailView(item: item) }
                else { Text("This app was removed.") }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.ipa, .zip, .data]) { result in
                switch result {
                case .success(let url): model.importIPA(from: url, origin: "Files")
                case .failure(let error): model.show("Import cancelled: \(error.localizedDescription)", error: true)
                }
            }
            .sheet(isPresented: $showURLSheet) { InstallFromLinkSheet() }
        }
    }
}

struct IPADetailView: View {
    @EnvironmentObject var model: AppModel
    let item: LibraryItem
    @State var confirmDelete = false
    @State var trackSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard(tinted: true) {
                    HStack(spacing: 14) {
                        AppIconView(image: model.icon(for: item), size: 72)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.displayName).font(.title2.bold()).accessibilityIdentifier("ipa.name")
                            Text(item.bundleID).font(.caption.monospaced()).foregroundStyle(.secondary).accessibilityIdentifier("ipa.bundleID")
                            Text("Version \(item.version)\(item.build.map { " (\($0))" } ?? "")").font(.subheadline).accessibilityIdentifier("ipa.version")
                        }
                    }
                    LabeledContent("Size", value: byteText(item.fileSize))
                    LabeledContent("Needs iOS", value: item.minimumOS ?? "not stated")
                    LabeledContent("Extensions", value: "\(item.extensionCount)").accessibilityIdentifier("ipa.extensions")
                    LabeledContent("From", value: item.origin)
                }

                GlassCard {
                    Text("Install").font(.headline)
                    Text(model.settings.tier == .free
     ? "LiveContainer runs it inside one app: no extra App IDs, and only LiveContainer itself needs refreshing. SideStore signs it as its own app: \(item.appIDCost) of your 10 weekly App IDs and one of your 3 app slots."
     : "LiveContainer runs it inside one app. SideStore signs it as its own app for a year with your paid account.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let remote = item.remoteURL.flatMap(URL.init(string:)) {
                        GlassEffectContainer(spacing: 12) {
                            VStack(spacing: 10) {
                                Button { Task { await model.installRemote(remote, with: .liveContainer, appIDCost: item.appIDCost) } } label: {
                                    Label("Install via LiveContainer", systemImage: "square.stack.3d.up").frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.glassProminent)
                                .accessibilityIdentifier("ipa.installLiveContainer")
                                Button { Task { await model.installRemote(remote, with: .sideStore, appIDCost: item.appIDCost) } } label: {
                                    Label("Install via SideStore", systemImage: "arrow.down.app").frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.glass)
                                .accessibilityIdentifier("ipa.installSideStore")
                            }
                        }
                    } else {
                        ShareLink(item: model.fileURL(for: item)) {
                            Label("Install via LiveContainer or SideStore", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .accessibilityIdentifier("ipa.share")
                        Text("Pick LiveContainer or SideStore in the share sheet. Both accept .ipa files.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button { model.noteSideStoreShare(item); model.show("Logged \(item.appIDCost) App ID use") } label: {
                            Label("I installed it with SideStore", systemImage: "number").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("ipa.logSideStore")
                    }
                }

                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        Button { if !model.trackFromProfile(item) { trackSheet = true } } label: { Label("Track expiry", systemImage: "timer").frame(maxWidth: .infinity) }
                            .buttonStyle(.glass)
                            .accessibilityIdentifier("ipa.track")
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash").frame(maxWidth: .infinity) }
                            .buttonStyle(.glass)
                            .accessibilityIdentifier("ipa.delete")
                    }
                }
            }
            .padding()
        }
        .navigationTitle(item.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete \(item.displayName) from the library?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { model.deleteLibraryItem(item) }
                .accessibilityIdentifier("ipa.confirmDelete")
        }
        .sheet(isPresented: $trackSheet) {
            AddTrackedAppSheet(name: item.displayName, bundleID: item.bundleID)
        }
    }
}

struct InstallFromLinkSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var text = ""
    @State var target: Companion = .liveContainer
    @State var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Link to an .ipa or an app source") {
                    TextField("https://…/App.ipa", text: $text)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .accessibilityIdentifier("link.field")
                    Picker("Send to", selection: $target) {
                        Text("LiveContainer").tag(Companion.liveContainer)
                        Text("SideStore").tag(Companion.sideStore)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("link.target")
                }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("link.error") }
                Section {
                    Button("Install app") { go(source: false) }.accessibilityIdentifier("link.install")
                    Button("Add as source (repo)") { go(source: true) }.accessibilityIdentifier("link.addSource")
                }
            }
            .navigationTitle("From link")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.accessibilityIdentifier("link.close") }
            }
        }
    }

    private func go(source: Bool) {
        do {
            let url = try DeepLinks.normalizeWebURL(text)
            let link = source ? try DeepLinks.addSource(url, to: target) : try DeepLinks.install(ipa: url, with: target)
            self.error = nil
            dismiss()
            Task { await model.send(link, to: target) }
        } catch DeepLinkError.emptyInput {
            self.error = "Paste a link first."
        } catch {
            self.error = "That doesn't look like a web link."
        }
    }
}
