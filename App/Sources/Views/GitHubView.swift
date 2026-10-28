import SwiftUI
import DisciplineCore

struct GitHubView: View {
    @EnvironmentObject var model: AppModel
    @FocusState var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("github.com/owner/repo or owner/repo", text: $model.gitHubQuery)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .focused($focused)
                        .onSubmit { Task { await model.findReleases() } }
                        .accessibilityIdentifier("github.field")
                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 12) {
                            Button { focused = false; Task { await model.findReleases() } } label: {
                                Label("Find releases", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassProminent)
                            .accessibilityIdentifier("github.find")
                            Button { model.toggleSaveCurrentRepo() } label: {
                                Label(model.isCurrentRepoSaved ? "Saved" : "Save repo", systemImage: model.isCurrentRepoSaved ? "star.fill" : "star")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                            .disabled(model.gitHubRef == nil)
                            .accessibilityIdentifier("github.save")
                        }
                    }
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Public repos work without signing in (60 lookups an hour). A token in More → Settings raises that.")
                }

                if model.gitHubLoading { ProgressView().accessibilityIdentifier("github.loading") }
                if let err = model.gitHubError {
                    Text(err).foregroundStyle(.orange).accessibilityIdentifier("github.error")
                }

                ForEach(model.releases) { release in
                    Section {
                        if release.ipaAssets.isEmpty {
                            Text("No .ipa in this release").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(release.ipaAssets) { asset in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(asset.name).font(.subheadline.weight(.semibold))
                                    Text(byteText(asset.size)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.downloadingAssetID == asset.id {
                                    ProgressView()
                                } else {
                                    Button("Get") { Task { await model.download(asset, from: release) } }
                                        .buttonStyle(.glassProminent)
                                        .accessibilityIdentifier("github.get.\(asset.name)")
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(release.title)
                            if release.prerelease { Text("PRE").font(.caption2.bold()).padding(.horizontal, 6).glassEffect(.regular.tint(.orange), in: .capsule) }
                        }
                    }
                }

                if !model.savedRepos.isEmpty {
                    Section {
                        StatStrip {
                            StatTile(value: "\(model.savedRepos.count)", label: "Saved repos", systemImage: "star.fill",
                                     tint: .yellow, id: "github.stat.saved")
                            StatTile(value: "\(model.savedRepos.filter(\.hasUpdate).count)", label: "Updates", systemImage: "arrow.down.app.fill",
                                     tint: .green, id: "github.stat.updates")
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        ForEach(model.savedRepos) { repo in
                            Button { Task { await model.openSaved(repo) } } label: {
                                HStack {
                                    Image(systemName: "shippingbox")
                                    Text(repo.ref.fullName)
                                    Spacer()
                                    if repo.hasUpdate {
                                        Text("Update").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 2)
                                            .glassEffect(.regular.tint(.green), in: .capsule)
                                            .accessibilityIdentifier("github.updateBadge.\(repo.ref.repo)")
                                    } else if let tag = repo.lastSeenTag {
                                        Text(tag).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .accessibilityIdentifier("github.saved.\(repo.ref.repo)")
                        }
                        .onDelete { idx in model.savedRepos.remove(atOffsets: idx) }
                        Button { Task { await model.checkUpdates() } } label: { Label("Check for updates", systemImage: "arrow.clockwise") }
                            .accessibilityIdentifier("github.checkUpdates")
                    } header: { Text("Saved repos") }
                }
            }
            .disciplineListBackdrop()
            .navigationTitle("GitHub to iOS")
        }
    }
}
