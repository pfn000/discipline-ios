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
    @EnvironmentObject var sniffer: Sniffer
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

    /// Testing devices: empty until the user sniffs and connects. This iPhone's own identity lives in Settings.
    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text("Testing devices").font(.headline).accessibilityIdentifier("ouija.devices.title")
                Spacer()
                ProfileAvatar(size: 34)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(model.displayName)
                    .accessibilityIdentifier("ouija.accountAvatar")
                Button { showSettings = true } label: { Image(systemName: "gearshape.fill").font(.title3) }
                    .accessibilityIdentifier("ouija.settings")
            }
            .padding(.horizontal, 4)
            TestingDevicesCard()
        }
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
            model.ouijaStatus = "Tile \(tile.id) isn't wired to a feature yet. Nothing ran."
        }
    }

    private func runLocalCommand() {
        let name = shellInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch name {
        case "help": shellOutput = "Local commands: help, apps, device, whoami, status. No iOS shell commands."
        case "apps": shellOutput = "\(model.library.count) test apps picked in Ouija; Discipline keeps the IPA Library."
        case "device": shellOutput = sniffer.devices.possessed.map { "Possessed: \($0.name) via \($0.channel.title)." } ?? "No device possessed. Tap Sniff above."
        case "whoami": shellOutput = model.account.map { "\($0.name) (\($0.kind == .developerCard ? "developer card" : "account on this iPhone"))" } ?? "Not signed in."
        case "status": shellOutput = "Signed in as \(model.displayName). Possessed: \(sniffer.devices.possessed?.name ?? "none"). Session: \(model.settings.ouijaSession.label)."
        default: shellOutput = "Unknown local command. Type help."
        }
        shellInput = ""
    }
}

struct OuijaSettingsSheet: View {
    @EnvironmentObject var model: OuijaModel
    @EnvironmentObject var sniffer: Sniffer
    @AppStorage("ouija.autoSniff") private var autoSniff = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Session", selection: $model.settings.ouijaSession) {
                    ForEach(OuijaSessionKind.allCases) { Text($0.label).tag($0) }
                }
                Section("This iPhone") {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.thisDevice.title).font(.headline)
                        Text(model.thisDevice.detail).font(.caption).foregroundStyle(.secondary)
                        Text("Signed in as \(model.displayName)").font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(model.thisDevice.title). \(model.thisDevice.detail). Signed in as \(model.displayName)")
                    .accessibilityIdentifier("ouija.settings.thisDevice")
                }
                Section {
                    Toggle("Auto-sniff", isOn: $autoSniff).tint(OuijaStyle.ok)
                        .accessibilityIdentifier("ouija.settings.autosniff")
                    HStack {
                        Text("Possessed device")
                        Spacer()
                        Text(sniffer.devices.possessed?.name ?? "None").foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Possessed device: \(sniffer.devices.possessed?.name ?? "None")")
                    .accessibilityIdentifier("ouija.settings.possessed")
                } header: { Text("Testing devices") } footer: {
                    Text("The testing-devices list shows only a device you sniffed and connected to. This iPhone is never listed there.")
                }
                Section {
                    Button("Show the Attention page again") {
                        model.settings.ouijaAgreed = false
                        dismiss()
                    }
                    .accessibilityIdentifier("ouija.resetAgreement")
                    Button("Sign out of Ouija", role: .destructive) {
                        model.signOut()
                        dismiss()
                    }
                    .accessibilityIdentifier("ouija.signOut")
                } footer: {
                    Text("Signed in as \(model.displayName) on \(model.thisDevice.title).")
                }
            }
            .navigationTitle("Ouija Board settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("ouija.settingsDone") } }
        }
    }
}
