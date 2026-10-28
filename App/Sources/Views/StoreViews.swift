import SwiftUI
import UIKit
import DisciplineCore

/// The Store tab: the sideload community's apps (Apps), or the GitHub-release finder (GitHub).
struct StoreTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if model.storeMode == .github { GitHubView() } else { StoreBrowseView() }
        }
    }
}

struct StoreModePicker: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Picker("Store", selection: $model.storeMode) {
            Text("Apps").tag(StoreMode.apps)
            Text("GitHub").tag(StoreMode.github)
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
        .accessibilityIdentifier("store.mode")
    }
}

struct StoreBrowseView: View {
    @ObservedObject var store = StoreModel.shared
    @State private var query = ""
    @State private var category: String?
    @State private var showSources = false

    private var filtered: [StoreApp] {
        let base = StoreCatalog.search(store.apps, query)
        guard let c = category else { return base }
        return base.filter { $0.category == c }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if store.apps.isEmpty {
                        emptyState
                    } else {
                        if query.isEmpty && category == nil { trendingCarousel }
                        categoryChips
                        appList
                    }
                    footer
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("Store")
            .toolbar {
                ToolbarItem(placement: .principal) { StoreModePicker() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSources = true } label: { Image(systemName: "list.bullet.rectangle") }
                        .accessibilityLabel("Sources")
                        .accessibilityIdentifier("store.sources")
                }
            }
            .searchable(text: $query, prompt: "Search apps")
            .refreshable { await store.refresh() }
            .task { if store.lastLoad == nil { await store.refresh() } }
            .navigationDestination(for: StoreApp.self) { StoreAppDetail(app: $0) }
            .sheet(isPresented: $showSources) { StoreSourcesSheet() }
            .disciplineListBackdrop()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            if store.loading {
                ProgressView().controlSize(.large)
                Text("Reading the sources…").foregroundStyle(.secondary)
            } else {
                Image(systemName: "wifi.exclamationmark").font(.system(size: 40)).foregroundStyle(.secondary)
                Text("No sources could be loaded").font(.headline)
                Text("Pull to try again. Sources you've loaded before stay available offline.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .accessibilityIdentifier("store.empty")
    }

    private var trendingCarousel: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Featured & Trending").font(.title2.bold())
                Text("Ranked by each source's picks, release freshness and GitHub stars. No source publishes download counts.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(store.trending) { app in
                        NavigationLink(value: app) { TrendingCard(app: app, reasons: store.reasons(app)) }
                            // glass-ok: an artwork card in the app's own tint (content, like the App Store's), not a fake glass surface
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("store.trending.\(app.name)")
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 20)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("store.trending")
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip("All", selected: category == nil) { category = nil }
                ForEach(store.categories, id: \.self) { c in
                    chip(c, selected: category == c) { category = (category == c ? nil : c) }
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("store.categories")
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 8)
        }
        // glass-ok: the chip's capsule is native .glassEffect (applied just below)
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear), in: Capsule())
        .glassEffect(selected ? .regular.tint(.accentColor) : .regular, in: Capsule())
        .accessibilityIdentifier("store.category.\(title)")
    }

    private var appList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(category ?? (query.isEmpty ? "All apps" : "Results"))
                .font(.title3.bold())
                .padding(.horizontal, 20)
            if filtered.isEmpty {
                Text("No apps match.").foregroundStyle(.secondary).padding(20).accessibilityIdentifier("store.noResults")
            }
            ForEach(filtered) { app in
                NavigationLink(value: app) { StoreRow(app: app) }
                    // glass-ok: a list row; its Get pill is native .glassEffect
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("store.app.\(app.name)")
                Divider().padding(.leading, 92)
            }
        }
    }

    private var footer: some View {
        let failed = store.sources.filter { $0.error != nil }
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(store.unique.count) apps from \(store.sources.count - failed.count) of \(store.sources.count) sources")
                .accessibilityIdentifier("store.summary")
            if !failed.isEmpty {
                Text("Couldn't load: " + failed.map { $0.source.name + ($0.fromCache ? " (showing cached copy)" : "") }.joined(separator: ", "))
                    .accessibilityIdentifier("store.failed")
            }
            Text("Discipline only lists and links. Every app downloads from the link its own source publishes.")
            Button("Edit sources") { showSources = true }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.glass)
                .padding(.top, 6)
                .accessibilityIdentifier("store.editSources")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

struct StoreIcon: View {
    let url: String?
    var size: CGFloat = 60
    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { phase in
            if let img = phase.image { img.resizable().scaledToFill() }
            else { ZStack { Rectangle().fill(.quaternary); Image(systemName: "app.dashed").foregroundStyle(.secondary) } }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).strokeBorder(.primary.opacity(0.08)))
    }
}

extension StoreApp {
    var tintColor: Color {
        guard var t = tint?.trimmingCharacters(in: .whitespaces) else { return .accentColor }
        if t.hasPrefix("#") { t.removeFirst() }
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return .accentColor }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

struct TrendingCard: View {
    let app: StoreApp
    let reasons: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                StoreIcon(url: app.iconURL, size: 64)
                Spacer()
                if app.featured {
                    Text("FEATURED").font(.caption2.weight(.bold)).tracking(0.8)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.white.opacity(0.22), in: Capsule())
                }
            }
            Spacer(minLength: 0)
            Text(app.name).font(.title3.bold()).lineLimit(1)
            Text(app.subtitle.isEmpty ? app.developer : app.subtitle).font(.subheadline).lineLimit(2).opacity(0.85)
            Text(reasons.prefix(2).joined(separator: " · ")).font(.caption.weight(.medium)).lineLimit(1).opacity(0.8)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(width: 290, height: 220, alignment: .topLeading)
        .background {
            LinearGradient(colors: [app.tintColor, app.tintColor.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom))
        }
        .clipShape(RoundedRectangle(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
    }
}

struct StoreRow: View {
    let app: StoreApp
    var body: some View {
        HStack(spacing: 14) {
            StoreIcon(url: app.iconURL, size: 58)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.headline).lineLimit(1)
                Text(app.subtitle.isEmpty ? app.developer : app.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text("\(app.category)\(app.categoryGuessed ? " (guessed)" : "") · \(app.sourceName)")
                    .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("Get").font(.subheadline.bold()).padding(.horizontal, 16).padding(.vertical, 6)
                .glassEffect(.regular.tint(.accentColor.opacity(0.25)), in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

struct StoreAppDetail: View {
    @ObservedObject var store = StoreModel.shared
    let app: StoreApp
    @State private var message = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 16) {
                    StoreIcon(url: app.iconURL, size: 104)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name).font(.title2.bold()).accessibilityIdentifier("store.detail.name")
                        Text(app.developer).font(.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 6)
                        Button { get() } label: {
                            Text("Get").font(.headline).padding(.horizontal, 26).padding(.vertical, 4)
                        }
                        .buttonStyle(.glassProminent)
                        .accessibilityIdentifier("store.get")
                    }
                }
                if !message.isEmpty {
                    Text(message).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("store.getResult")
                }
                facts
                if !store.reasons(app).isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Why it's here").font(.headline)
                        ForEach(store.reasons(app), id: \.self) { Label($0, systemImage: "checkmark.seal").font(.subheadline) }
                    }
                }
                if !app.screenshots.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(app.screenshots.prefix(6), id: \.self) { s in
                                AsyncImage(url: URL(string: s)) { p in
                                    if let i = p.image { i.resizable().scaledToFit() } else { Rectangle().fill(.quaternary) }
                                }
                                .frame(height: 360)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                if !app.summary.isEmpty {
                    Text(app.summary).font(.body).accessibilityIdentifier("store.detail.summary")
                }
                Text("Source: \(app.sourceName)\n\(app.sourceURL)")
                    .font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
            }
            .padding(20)
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var facts: some View {
        HStack(spacing: 0) {
            fact("Version", app.version.isEmpty ? "?" : app.version)
            Divider().frame(height: 34)
            fact("Released", app.versionDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "?")
            Divider().frame(height: 34)
            fact("Size", app.size.map(byteText) ?? "?")
            Divider().frame(height: 34)
            fact("iOS", app.minOS ?? "?")
        }
        .padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    /// Get = hand the source's own download link to SideStore, else LiveContainer. Discipline downloads nothing.
    private func get() {
        for (name, url) in StoreModel.installLinks(for: app) where UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            message = "Handed to \(name). It downloads \(app.name) from \(app.sourceName)'s link and signs it."
            return
        }
        UIPasteboard.general.string = app.downloadURL
        message = "SideStore or LiveContainer isn't installed, so nothing was opened. The download link was copied."
    }
}

struct StoreSourcesSheet: View {
    @ObservedObject var store = StoreModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var newURL = ""
    @State private var adding = false
    @State private var message = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.sources) { s in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(s.source.name).font(.headline)
                                if s.source.builtIn { Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue).font(.caption).accessibilityLabel("verified") }
                            }
                            Text(s.source.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if let e = s.error {
                                Text(s.fromCache ? "\(e). Showing the copy from \(s.fetchedAt?.formatted(date: .abbreviated, time: .shortened) ?? "earlier")." : "Couldn't load: \(e)")
                                    .font(.caption).foregroundStyle(.orange)
                            } else if s.fetchedAt != nil {
                                Text("\(s.appCount) apps").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("source.\(s.source.name)")
                    }
                    .onDelete { store.removeSources(at: $0) }
                } header: { Text("Sources") } footer: {
                    Text("The 10 verified sources were checked live on Oct 28, 2026. Swipe to remove any source.")
                }
                Section("Add source") {
                    TextField("https://…/apps.json", text: $newURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .accessibilityIdentifier("source.newURL")
                    Button(adding ? "Adding…" : "Add source") {
                        adding = true
                        Task {
                            message = await store.addSource(newURL) ?? "Added."
                            if message == "Added." { newURL = "" }
                            adding = false
                        }
                    }
                    .disabled(newURL.isEmpty || adding)
                    .accessibilityIdentifier("source.add")
                    if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("source.message") }
                }
                Section {
                    Button("Restore verified sources") { Task { await store.restoreDefaults() } }
                }
            }
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("source.done") } }
        }
    }
}
