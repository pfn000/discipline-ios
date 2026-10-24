import SwiftUI
import UIKit
import DisciplineCore

/// NCOM Lab: tap the Discipline label in More 25 times (legacy 7 long presses still supported).
struct LabView: View {
    @EnvironmentObject var model: AppModel
    @State var inspectedID: UUID?
    @State var inspection: IPAInspection?
    @State var inspectError: String?
    @State var preset = SigningPreset.ouijaBoard
    @State var exportURLs: [URL] = []
    @State private var prototypeConsent = false
    @State private var shellInput = ""
    @State private var shellOutput = "Type help for local commands. No system shell or hardware link."

    var body: some View {
        List {
            Section {
                LabeledContent("Signing account", value: model.settings.tier == .free ? "Free Apple ID" : "Paid developer")
                    .accessibilityIdentifier("lab.tier")
                Text("Discipline can't grant entitlements Apple restricts. It tells you what each feature needs and builds the files your signer (Plume Impactor, SideStore) uses.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Ouija Board · developer preview") {
                Text("Ouija Board is only meant for NCOM developers. Prototype hardware control is not connected; these tiles are a layout preview, not a device session.")
                    .font(.caption).foregroundStyle(.orange)
                    .accessibilityIdentifier("lab.prototypeWarning")
                Toggle("I understand the prototype features are unavailable", isOn: $prototypeConsent)
                    .accessibilityIdentifier("lab.prototypeConsent")
                if prototypeConsent {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Focals Pro").font(.title3.weight(.semibold))
                        Text("Device model: concept · connection status: not connected")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("User Profile / Playground ID session: none")
                            .font(.caption).foregroundStyle(.secondary)
                        let tiles = ["Alert", "2.1htz", "Cloud", "Node dial", "Warning", "Visor",
                                     "Terminal", "Starburst", "Hand/tool", "Speed gauge", "DE E", "+ Add Test App"]
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                            ForEach(tiles, id: \.self) { tile in
                                VStack(spacing: 5) {
                                    Image(systemName: tile == "+ Add Test App" ? "plus.app" : "circle.dotted")
                                    Text(tile).font(.system(size: 10, weight: .medium))
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity, minHeight: 65)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                                .accessibilityIdentifier("lab.tile.\(tile)")
                            }
                        }
                        Text("///Shell terminal for App only")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                        HStack {
                            TextField("Local command", text: $shellInput)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .accessibilityIdentifier("lab.shellInput")
                            Button("Send") { runLocalCommand() }
                                .accessibilityIdentifier("lab.shellSend")
                        }
                        Text(shellOutput).font(.caption.monospaced())
                            .accessibilityIdentifier("lab.shellOutput")
                    }
                }
            }

            Section("Capability map") {
                ForEach(DeviceFeature.catalog) { f in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(f.name).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(badge(f)).font(.caption2.bold())
                        }
                        Text(f.notes).font(.caption).foregroundStyle(.secondary)
                        if !f.entitlements.isEmpty {
                            Text(f.entitlements.joined(separator: ", ")).font(.caption2.monospaced())
                        }
                    }
                    .accessibilityIdentifier("lab.feature.\(f.id)")
                }
            }

            Section {
                if model.library.isEmpty {
                    Text("Add an .ipa to the Library first.").foregroundStyle(.secondary)
                } else {
                    Picker("App", selection: $inspectedID) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(model.library) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                    .accessibilityIdentifier("lab.inspectPicker")
                    Button { inspect() } label: { Label("Inspect entitlements", systemImage: "doc.viewfinder") }
                        .disabled(inspectedID == nil)
                        .accessibilityIdentifier("lab.inspect")
                }
                if let inspectError { Text(inspectError).foregroundStyle(.orange).font(.caption) }
                if let ins = inspection {
                    Text("\(ins.entitlementKeys.count) entitlements").font(.headline).accessibilityIdentifier("lab.entitlementCount")
                    ForEach(ins.entitlementSummary, id: \.key) { e in
                        VStack(alignment: .leading) {
                            Text(e.key).font(.caption.monospaced())
                            Text(e.value).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    let blocked = ins.unsignable(for: model.settings.tier)
                    if blocked.isEmpty {
                        Label("Your account can sign all of these", systemImage: "checkmark.seal").foregroundStyle(.green)
                            .accessibilityIdentifier("lab.allSignable")
                    } else {
                        Label("Can't sign on this account: \(blocked.joined(separator: ", "))", systemImage: "xmark.seal")
                            .foregroundStyle(.orange).font(.caption)
                            .accessibilityIdentifier("lab.unsignable")
                    }
                    if !ins.usageDescriptions.isEmpty {
                        Text("Privacy strings").font(.subheadline.weight(.semibold))
                        ForEach(ins.usageDescriptions, id: \.key) { u in
                            Text("\(u.key): \(u.text)").font(.caption2)
                        }
                    }
                }
            } header: { Text("Entitlements inspector") }

            Section {
                TextField("App name", text: $preset.name).accessibilityIdentifier("lab.presetName")
                TextField("Bundle ID", text: $preset.bundleID)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("lab.presetBundle")
                ForEach(DeviceFeature.catalog) { f in
                    Toggle(isOn: Binding(get: { preset.features.contains(f.id) },
                                         set: { on in
                                             if on { if !preset.features.contains(f.id) { preset.features.append(f.id) } }
                                             else { preset.features.removeAll { $0 == f.id } }
                                         })) {
                        Text("\(f.name)  \(badgeIcon(f))")
                    }
                    .accessibilityIdentifier("lab.toggle.\(f.id)")
                }
                let blocked = preset.blocked(for: model.settings.tier)
                Text(blocked.isEmpty ? "Everything selected is signable on your account."
                                     : "Left out for your account: " + blocked.map(\.name).joined(separator: ", "))
                    .font(.caption).foregroundStyle(blocked.isEmpty ? .green : .orange)
                    .accessibilityIdentifier("lab.presetStatus")
                Button { copyEntitlements() } label: { Label("Copy entitlements plist", systemImage: "doc.on.doc") }
                    .accessibilityIdentifier("lab.copy")
                Button { makeExport() } label: { Label("Build preset files", systemImage: "hammer") }
                    .accessibilityIdentifier("lab.build")
                if !exportURLs.isEmpty {
                    ShareLink(items: exportURLs) { Label("Share preset files", systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("lab.share")
                }
                Button("Reset to Ouija Board preset") { preset = .ouijaBoard; exportURLs = [] }
                    .accessibilityIdentifier("lab.reset")
            } header: { Text("Signing preset") } footer: {
                Text("Put the .entitlements file in your app's Xcode project (Code Signing Entitlements) and the Info.plist keys in its Info.plist. Plume Impactor and SideStore then ask Apple for those entitlements when they sign; restricted ones fail on a free account.")
            }
        }
        .navigationTitle("NCOM Lab")
    }

    private func runLocalCommand() {
        let name = shellInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch name {
        case "help": shellOutput = "Local commands: help, apps, device, status. No iOS shell commands."
        case "apps": shellOutput = "\(model.library.count) IPA files in Discipline's Library; none run inside Discipline."
        case "device": shellOutput = "iOS \(UIDevice.current.systemVersion); Focals Pro: concept only, no device linked."
        case "status": shellOutput = "Prototype connection: not connected. Native guest loader: not available."
        default: shellOutput = "Unknown local command. Type help."
        }
        shellInput = ""
    }

    private func badgeIcon(_ f: DeviceFeature) -> String {
        switch f.signability {
        case .freeOK: return "✅"
        case .paidAccount: return model.settings.tier == .paid ? "✅" : "⚠️"
        case .appleApprovalOnly: return "❌"
        }
    }

    private func badge(_ f: DeviceFeature) -> String {
        if f.signability == .paidAccount && model.settings.tier == .paid { return "✅ Signable on your paid account" }
        return f.signability.badge
    }

    private func inspect() {
        guard let id = inspectedID, let item = model.library.first(where: { $0.id == id }) else { return }
        do {
            inspection = try IPAReader.inspect(bytes: [UInt8](try Data(contentsOf: model.fileURL(for: item))))
            inspectError = inspection?.entitlementsError.map { "Entitlements unreadable: \($0)" }
        } catch {
            inspection = nil
            inspectError = "Couldn't read \(item.displayName): \(error)"
        }
    }

    private func copyEntitlements() {
        guard let data = try? preset.entitlementsPlistXML(for: model.settings.tier) else { return }
        UIPasteboard.general.string = String(decoding: data, as: UTF8.self)
        model.show("Entitlements copied (\(preset.entitlements(for: model.settings.tier).count) keys)")
    }

    private func makeExport() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("preset-\(UUID().uuidString.prefix(6))")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let slug = preset.name.filter { $0.isLetter || $0.isNumber }
        do {
            let ent = dir.appendingPathComponent("\(slug).entitlements")
            try preset.entitlementsPlistXML(for: model.settings.tier).write(to: ent)
            let info = dir.appendingPathComponent("\(slug)-Info-additions.plist")
            try PropertyListSerialization.data(fromPropertyList: preset.infoPlistAdditions(), format: .xml, options: 0).write(to: info)
            let json = dir.appendingPathComponent("\(slug)-preset.json")
            try preset.json().write(to: json)
            exportURLs = [ent, info, json]
            model.show("Built 3 preset files")
        } catch {
            model.show("Couldn't build the files: \(error)", error: true)
        }
    }
}
