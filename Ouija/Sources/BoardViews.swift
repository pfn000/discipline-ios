import SwiftUI
import UIKit
import Network
import PhotosUI
import Vision
import VisionKit
import CoreImage
import UniformTypeIdentifiers
import DisciplineCore

// Ouija Board screens (moved from Discipline in v0.5; Ouija is its own app now).

struct OuijaBoardMain: View {
    @EnvironmentObject var model: OuijaModel
    @State var shellInput = ""
    @State var shellOutput = "Type help for local commands. No system shell or hardware link."
    @State var importing = false
    @State var showSettings = false

    private var tiles: [OuijaContent.Tile] { OuijaContent.shared.tiles }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                Picker("Session", selection: $model.settings.ouijaSession) {
                    ForEach(OuijaSessionKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("ouija.session")

                // Native Liquid Glass: each tile face is .glassEffect(.regular.interactive()); the container lets them blend and morph together.
                GlassEffectContainer(spacing: 10) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                        ForEach(tiles) { tile in
                            Button { tap(tile) } label: { tileFace(tile) }
                                .buttonStyle(.plain) // glass-ok: the label itself is native interactive glass (tileFace)
                                .accessibilityIdentifier("ouija.tile.\(tile.id)")
                        }
                    }
                }

                Text(model.ouijaStatus)
                    .font(.footnote.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
                    .accessibilityIdentifier("ouija.status")
                Text(OuijaContent.shared.source == "private" ? "NCOM content" : "Neutral content (NCOM's file isn't in this build)")
                    .font(.caption2).foregroundStyle(.secondary)
                    .accessibilityIdentifier("ouija.contentSource")
                    .accessibilityValue(OuijaContent.shared.source)

                VStack(alignment: .leading, spacing: 8) {
                    Text(OuijaContent.shared.shellTitle).font(.caption.monospaced()).foregroundStyle(.secondary)
                    HStack {
                        TextField("Local command", text: $shellInput)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .submitLabel(.send)
                            .onSubmit { runLocalCommand() }
                            .accessibilityIdentifier("ouija.shellInput")
                        Button("Send") { runLocalCommand() }
                            .buttonStyle(.glass)
                            .accessibilityIdentifier("ouija.shellSend")
                    }
                    Text(shellOutput).font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("ouija.shellOutput")
                }
                .padding()
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data, .data]) { result in
            if case .success(let url) = result, let item = model.importIPA(from: url, origin: "Ouija Board test app") {
                model.ouijaStatus = "Install: \(item.displayName) \(item.version) was picked. Open it in Discipline's Library to hand it to SideStore or LiveContainer."
            }
        }
        .sheet(isPresented: $showSettings) { OuijaSettingsSheet() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: OuijaContent.shared.deviceSymbol).font(.system(size: 34))
                .frame(width: 60, height: 60)
                .glassEffect(.regular, in: Circle())
                .accessibilityIdentifier("ouija.deviceModel")
            VStack(alignment: .leading, spacing: 4) {
                Text(OuijaContent.shared.deviceName).font(.title2.bold()).accessibilityIdentifier("ouija.deviceName")
                NavigationLink { PairingView() } label: {
                    Label("Not connected · pair", systemImage: "circle.fill")
                        .font(.caption).foregroundStyle(.secondary)
                        .labelStyle(ConnectionDotStyle())
                }
                .accessibilityIdentifier("ouija.connection")
            }
            Spacer()
            Button { showSettings = true } label: { Image(systemName: "gearshape.fill").font(.title2) }
                .accessibilityIdentifier("ouija.settings")
        }
        .padding()
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
    }

    @ViewBuilder private func tileFace(_ tile: OuijaContent.Tile) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                if let t = tile.text { Text(t).font(.system(size: 16, weight: .heavy, design: .rounded)) }
                ForEach(tile.symbols, id: \.self) { Image(systemName: $0).font(.system(size: tile.symbols.count > 2 ? 13 : 18, weight: .semibold)) }
            }
            if let c = tile.caption {
                Text(c).font(.system(size: 10, weight: .semibold)).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 70)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
    }

    private func tap(_ tile: OuijaContent.Tile) {
        if tile.action == "import" {
            importing = true
            model.ouijaStatus = "Loading: choose a test app (.ipa)…"
        } else {
            model.ouijaStatus = "Tile \(tile.id): prototype feature. Pair a \(OuijaContent.shared.deviceName) first (\(OuijaContent.shared.pairTitle)). Not connected."
        }
    }

    private func runLocalCommand() {
        let name = shellInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch name {
        case "help": shellOutput = "Local commands: help, apps, device, status. No iOS shell commands."
        case "apps": shellOutput = "\(model.library.count) test apps picked in Ouija; Discipline keeps the IPA Library."
        case "device": shellOutput = "iOS \(UIDevice.current.systemVersion); \(OuijaContent.shared.deviceName): not paired."
        case "status": shellOutput = "Prototype connection: not connected. Session: \(model.settings.ouijaSession.label)."
        default: shellOutput = "Unknown local command. Type help."
        }
        shellInput = ""
    }
}

private struct ConnectionDotStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 7)).foregroundStyle(.red)
            configuration.title
        }
    }
}

struct OuijaSettingsSheet: View {
    @EnvironmentObject var model: OuijaModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Session", selection: $model.settings.ouijaSession) {
                    ForEach(OuijaSessionKind.allCases) { Text($0.label).tag($0) }
                }
                Section {
                    Button("Show the Attention page again") {
                        model.settings.ouijaAgreed = false
                        dismiss()
                    }
                    .accessibilityIdentifier("ouija.resetAgreement")
                } footer: {
                    Text("No prototype device is connected. Pairing options are under the connection status.")
                }
            }
            .navigationTitle("Ouija Board settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("ouija.settingsDone") } }
        }
    }
}

// MARK: Pairing

struct PairingView: View {
    @EnvironmentObject var model: OuijaModel
    @StateObject var browser = NCOMBrowser()
    @State var selected: String?
    @State var searching = false
    @State var result = ""

    private var options: [OuijaContent.PairOption] { OuijaContent.shared.pairOptions }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 36))
                    Text(model.settings.ouijaSession.label).font(.headline)
                    Spacer()
                }
                Label(OuijaContent.shared.pairInstructions, systemImage: "info.circle")
                    .font(.subheadline)
                    .accessibilityIdentifier("pair.instructions")
            }
            Section {
                ForEach(options) { o in
                    Button { selected = o.id; result = "" } label: {
                        HStack {
                            Label(o.title, systemImage: o.symbol)
                            Spacer()
                            if selected == o.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                        }
                    }
                    .accessibilityIdentifier("pair.option.\(o.id)")
                }
            }
            Section {
                // The result shares the button's row so it shows right under the button, never below the fold.
                VStack(alignment: .leading, spacing: 10) {
                    Button { Task { await start() } } label: {
                        HStack {
                            if searching { ProgressView() }
                            Text(searching ? "Searching…" : OuijaContent.shared.pairTitle).font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(searching)
                    .accessibilityIdentifier("pair.start")
                    if !result.isEmpty {
                        Text(result).font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("pair.result")
                    }
                }
            }
        }
        .navigationTitle(OuijaContent.shared.pairTitle)
    }

    private func start() async {
        guard let id = selected, let option = options.first(where: { $0.id == id }) else {
            result = "Choose an option first."
            return
        }
        switch option.kind {
        case "localNetwork":
            searching = true
            model.ouijaStatus = "Loading: looking for NCOM devices on this network…"
            let found = OuijaTest.active ? [] : await browser.browse(seconds: 8)
            searching = false
            result = found.isEmpty ? "No NCOM devices found on this network." : "Found: " + found.joined(separator: ", ") + " (pairing isn't built yet)."
        case "uwb":
            result = "\(option.title): UWB needs a paired NCOM accessory that speaks Apple's Nearby Interaction. None is paired."
        default:
            result = "\(option.title): needs NCOM prototype hardware. Nothing is paired."
        }
        model.ouijaStatus = result
    }
}

/// Looks for NCOM devices advertising `_ncom-ouija._tcp` over Bonjour on the local network.
/// No NCOM device advertises this yet; the search is real, so it will say "none found" until one does.
@MainActor
final class NCOMBrowser: ObservableObject {
    @Published var found: [String] = []
    private var browser: NWBrowser?

    func browse(seconds: Double) async -> [String] {
        found = []
        let b = NWBrowser(for: .bonjour(type: "_ncom-ouija._tcp", domain: nil), using: .tcp)
        browser = b
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let names = results.compactMap { r -> String? in
                if case let .service(name, _, _, _) = r.endpoint { return name }
                return nil
            }
            Task { @MainActor in self?.found = names }
        }
        b.start(queue: .main)
        try? await Task.sleep(for: .seconds(seconds))
        b.cancel()
        browser = nil
        return found
    }
}

// MARK: The magic ring
