import SwiftUI
import UIKit
import Network
import PhotosUI
import Vision
import VisionKit
import CoreImage
import UniformTypeIdentifiers
import DisciplineCore

// NCOM Ouija Board screens: an Attention page with a slide control, an Agreement page with the
// signed-in profile, then the board (device header with connection status, settings and session
// switch; a 4 x 3 tile grid; a loading/install status line; an app-only shell) and a pairing page.
// Words and icons come from OuijaContent (NCOM's private file at build time, or a neutral fallback).
// Prototype hardware is NOT connected: tiles and pairing say so instead of pretending.

struct OuijaBoardView: View {
    @EnvironmentObject var model: AppModel
    @State var understood = false

    var body: some View {
        Group {
            if model.settings.ouijaAgreed {
                OuijaBoardMain()
            } else if understood {
                OuijaAgreementPage { model.settings.ouijaAgreed = true }
            } else {
                OuijaAttentionPage { withAnimation { understood = true } }
            }
        }
        .navigationTitle("NCOM Ouija Board")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// "Attention" page: the developer-only warning and the slide control.
struct OuijaAttentionPage: View {
    let onUnderstood: () -> Void
    @State var slide = 0.0

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 64)).foregroundStyle(.orange)
            Text("Attention").font(.largeTitle.bold()).accessibilityIdentifier("ouija.attention")
            Text("Ouija Board is only meant for NCOM developers.")
                .font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                .accessibilityIdentifier("ouija.warning")
            Text("Prototype hardware control is not connected in this build. The board shows the layout and the parts that work on an iPhone today.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            VStack(spacing: 8) {
                Text(OuijaContent.shared.attentionSlide).font(.headline)
                Slider(value: $slide, in: 0...1) { Text(OuijaContent.shared.attentionSlide) }
                    .accessibilityIdentifier("ouija.slide")
                    .onChange(of: slide) { _, v in if v >= 0.97 { onUnderstood() } }
            }
            .padding()
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        }
        .padding(24)
    }
}

/// "Agreement" page: the signed-in profile and the agree button.
struct OuijaAgreementPage: View {
    @EnvironmentObject var model: AppModel
    let onAgree: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 64)).foregroundStyle(.tint)
            Text("Agreement").font(.largeTitle.bold()).accessibilityIdentifier("ouija.agreement")
            if !OuijaContent.shared.agreementText.isEmpty {
                Text(OuijaContent.shared.agreementText)
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 40))
                VStack(alignment: .leading) {
                    Text(model.settings.ouijaSession.label).font(.headline)
                    Text(OuijaContent.shared.signedInCaption).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ouija.signedIn")
            Spacer()
            Button { onAgree() } label: { Text(OuijaContent.shared.agreeButton).font(.title3.bold()).frame(maxWidth: .infinity) }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("ouija.agree")
        }
        .padding(24)
    }
}

struct OuijaBoardMain: View {
    @EnvironmentObject var model: AppModel
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

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(tiles) { tile in
                        Button { tap(tile) } label: { tileFace(tile) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("ouija.tile.\(tile.id)")
                    }
                }

                Text(model.ouijaStatus)
                    .font(.footnote.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
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
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data, .data]) { result in
            if case .success(let url) = result, let item = model.importIPA(from: url, origin: "Ouija Board test app") {
                model.ouijaStatus = "Install: \(item.displayName) \(item.version) is in the Library. Hand it to SideStore or LiveContainer to install."
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
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
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
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
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
        case "apps": shellOutput = "\(model.library.count) IPA files in Discipline's Library; none run inside Discipline."
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
    @EnvironmentObject var model: AppModel
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
    @EnvironmentObject var model: AppModel
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
            let found = TestHooks.isUITesting ? [] : await browser.browse(seconds: 8)
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

/// The "circular magic QR code" dance: rings spin in different directions and change the shape and
/// size of their lines, then the code is signed off by NCOM (or refused).
struct MagicRingView: View {
    let state: AppModel.MagicRingState
    let onFinish: () -> Void
    @State var start = Date()
    @State var showResult = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.93).ignoresSafeArea()
            VStack(spacing: 28) {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSince(start)
                    Canvas { ctx, size in
                        draw(&ctx, size: size, t: t)
                    }
                }
                .frame(width: 300, height: 300)
                .overlay {
                    Image(systemName: showResult ? (state.accepted ? "checkmark.seal.fill" : "xmark.octagon.fill") : "qrcode")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(state.accepted ? Color.white : Color.red)
                        .contentTransition(.symbolEffect(.replace))
                }
                VStack(spacing: 6) {
                    Text(showResult ? state.message : "Reading NCOM code…")
                        .font(.title3.bold()).foregroundStyle(.white).multilineTextAlignment(.center)
                        .accessibilityIdentifier("ouija.ringMessage")
                    Text("NCOM Systems").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ouija.magicRing")
        .task {
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(.spring) { showResult = true }
            try? await Task.sleep(for: .seconds(1.6))
            onFinish()
        }
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxR = Double(min(size.width, size.height)) / 2 - 10
        let palette: [Color] = state.accepted ? [.cyan, .purple, .mint, .indigo, .white] : [.red, .orange, .red, .pink, .orange]
        let settle = showResult ? 1.0 : 0.0
        for i in 0..<5 {
            let k = Double(i)
            let direction: Double = i % 2 == 0 ? 1 : -1
            let speed = 0.5 + 0.3 * k
            let collapse = state.accepted ? 1.0 : max(0.25, 1 - max(0, t - 1.5) / 2)
            let radius = maxR * (0.36 + 0.16 * k) * (0.9 + 0.1 * sin(t * 2.1 + k)) * collapse
            let width = 1.5 + 5 * (0.5 + 0.5 * sin(t * 3 + k * 1.3)) * (1 - 0.5 * settle)
            let dash = 3 + 22 * (0.5 + 0.5 * sin(t * 1.7 + k * 0.9))
            let gap = 3 + 12 * (0.5 + 0.5 * cos(t * 2.3 + k))
            var ring = Path()
            ring.addArc(center: c, radius: CGFloat(radius), startAngle: .zero, endAngle: .degrees(360), clockwise: false)
            let angle = direction * t * speed * .pi
            ctx.drawLayer { layer in
                layer.translateBy(x: c.x, y: c.y)
                layer.rotate(by: .radians(angle))
                layer.translateBy(x: -c.x, y: -c.y)
                layer.stroke(ring, with: .color(palette[i]),
                             style: StrokeStyle(lineWidth: CGFloat(width), lineCap: .round,
                                                dash: settle > 0 && state.accepted ? [] : [CGFloat(dash), CGFloat(gap)]))
            }
        }
    }
}

// MARK: Scanning the NCOM QR

struct OuijaScannerSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var photo: PhotosPickerItem?
    @State var message = ""

    private var cameraOK: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if cameraOK {
                    QRCameraView { text in
                        dismiss()
                        model.receiveOuijaCode(text)
                    }
                    .frame(maxWidth: .infinity, minHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                } else {
                    Label("The camera scanner isn't available here. Scan the NCOM QR with the iPhone Camera app (it opens Discipline), or pick a photo of the code.",
                          systemImage: "camera")
                        .accessibilityIdentifier("scan.noCamera")
                }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Pick a photo of the code", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("scan.photo")
                if !message.isEmpty {
                    Text(message).foregroundStyle(.orange).accessibilityIdentifier("scan.message")
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Scan NCOM code")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.accessibilityIdentifier("scan.close") }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let text = QRDecoder.decode(data) {
                        dismiss()
                        model.receiveOuijaCode(text)
                    } else {
                        message = "No QR code found in that photo."
                    }
                }
            }
        }
    }
}

enum QRDecoder {
    static func decode(_ data: Data) -> String? {
        guard let image = CIImage(data: data) else { return nil }
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        return detector?.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }
}

struct QRCameraView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
                                           recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
                                           isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning { try? vc.startScanning() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case .barcode(let code) = item, let text = code.payloadStringValue {
                    done = true
                    dataScanner.stopScanning()
                    onCode(text)
                    return
                }
            }
        }
    }
}
