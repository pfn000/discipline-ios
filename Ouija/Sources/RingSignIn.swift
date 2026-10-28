import SwiftUI
import UIKit
import Network
import AVFoundation
import CoreBluetooth
import CryptoKit
import DisciplineCore

// Magic-ring computer sign-in.
// 1. The phone looks for the computer: Bonjour `_ncom-ouija._tcp` on the same Wi-Fi (the computer runs
//    web/ouija_host.py, because a web page can't advertise on Bonjour), and it advertises over Bluetooth
//    so the ring page in Chrome or Edge can connect with Web Bluetooth (Safari and Firefox can't).
// 2. The phone hands the computer a fresh session string, buzzes, and asks you to point the camera at the rings.
// 3. The camera frames go to DisciplineCore's RingReader; frames are stitched and the result is checked
//    with RingLogin.verify against the enrolled keys (Ed25519) and the session string.
// NOT TESTED on hardware: the simulator has no camera, Bluetooth or LAN peers.

enum RingPhase: Equatable {
    case idle
    case searching
    case found(String)          // the computer's name
    case scanning
    case success(String)        // the key's name
    case failure(String)        // why
}

@MainActor
final class RingSignIn: NSObject, ObservableObject {
    @Published var phase: RingPhase = .idle
    @Published var lanStatus = "Not started"
    @Published var bleStatus = "Not started"
    @Published var framesRead = 0
    @Published var framesNeeded = 0
    @Published var viewfinder: UIImage?
    @Published var computerKey: String?   // NCOMKEY1 text the host offered (for enrolling)

    private(set) var session: [UInt8] = []
    private var assembler = RingCode.Assembler()
    private var enrolled: [EnrolledKey] = []
    private var browser: NWBrowser?
    private var peripheral: CBPeripheralManager?
    private var sessionChar: CBMutableCharacteristic?
    private var testTimer: Timer?
    let camera = RingCamera()

    // UI-test-only signer (exists only under -uiTesting; never in a normal run).
    static let testSigner = Curve25519.Signing.PrivateKey()
    static let foreignSigner = Curve25519.Signing.PrivateKey()

    func start(enrolled: [EnrolledKey]) {
        self.enrolled = enrolled
        session = RingLogin.newSession()
        assembler = RingCode.Assembler()
        framesRead = 0; framesNeeded = 0
        phase = .searching
        if OuijaTest.has("-uiTestingRingFrames") || OuijaTest.has("-uiTestingRingForeign") {
            lanStatus = "Simulator: no network peers"
            bleStatus = "Simulator: no Bluetooth"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.computerFound("UI test computer (simulator only)") }
            return
        }
        startLAN()
        startBLE()
    }

    func stop() {
        browser?.cancel(); browser = nil
        peripheral?.stopAdvertising(); peripheral = nil
        testTimer?.invalidate(); testTimer = nil
        camera.stop()
    }

    // MARK: Wi-Fi (Bonjour)

    private func startLAN() {
        lanStatus = "Looking on this Wi-Fi…"
        let b = NWBrowser(for: .bonjour(type: "_ncom-ouija._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            guard let r = results.first else { return }
            Task { @MainActor in self?.connect(r.endpoint) }
        }
        b.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .failed(let e): self?.lanStatus = "Wi-Fi search failed: \(e.localizedDescription)"
                case .waiting(let e): self?.lanStatus = "Waiting for Local Network permission (\(e.localizedDescription))"
                default: break
                }
            }
        }
        b.start(queue: .main)
        browser = b
    }

    /// Resolve the Bonjour service to host:port, then hand over the session string over HTTP.
    private func connect(_ endpoint: NWEndpoint) {
        guard case .searching = phase else { return }
        var name = "Computer"
        if case let .service(n, _, _, _) = endpoint { name = n }
        lanStatus = "Found \(name) on Wi-Fi"
        let c = NWConnection(to: endpoint, using: .tcp)
        c.stateUpdateHandler = { [weak self] st in
            guard case .ready = st, let remote = c.currentPath?.remoteEndpoint, case let .hostPort(host, port) = remote else { return }
            c.cancel()
            var h = "\(host)"
            if let pct = h.firstIndex(of: "%") { h = String(h[..<pct]) }
            if h.contains(":") { h = "[\(h)]" }
            Task { @MainActor in self?.handOver(base: "http://\(h):\(port.rawValue)", name: name) }
        }
        c.start(queue: .main)
    }

    private func handOver(base: String, name: String) {
        guard let url = URL(string: base + "/session") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["session": RingLogin.hex(session)])
        req.timeoutInterval = 6
        Task {
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { lanStatus = "\(name) refused the session"; return }
                if let res = try? await URLSession.shared.data(from: URL(string: base + "/pubkey")!),
                   let j = try? JSONSerialization.jsonObject(with: res.0) as? [String: Any], let k = j["key"] as? String {
                    computerKey = k
                }
                computerFound(name)
            } catch {
                lanStatus = "Couldn't reach \(name): \(error.localizedDescription)"
            }
        }
    }

    // MARK: Bluetooth (the phone advertises; the page connects with Web Bluetooth)

    static let serviceUUID = CBUUID(string: "4E434F4D-4F55-494A-4100-000000000001")
    static let sessionUUID = CBUUID(string: "4E434F4D-4F55-494A-4100-000000000002")
    static let helloUUID = CBUUID(string: "4E434F4D-4F55-494A-4100-000000000003")

    private func startBLE() {
        bleStatus = "Starting Bluetooth…"
        peripheral = CBPeripheralManager(delegate: self, queue: .main)
    }

    // MARK: Found → buzz → camera

    func computerFound(_ name: String) {
        guard case .searching = phase else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        phase = .found(name)
    }

    func beginScan() {
        phase = .scanning
        if OuijaTest.has("-uiTestingRingFrames") || OuijaTest.has("-uiTestingRingForeign") {
            startTestFrames(foreign: OuijaTest.has("-uiTestingRingForeign"))
        } else {
            camera.onFrame = { [weak self] img in Task { @MainActor in self?.consume(img) } }
            camera.start { [weak self] ok in
                Task { @MainActor in if !ok { self?.finish(.failure("The camera isn't available, so the rings can't be read.")) } }
            }
        }
    }

    /// UI tests only: the rings the computer page would show, rendered by RingRenderer at changing
    /// rotations with noise, fed through the same reader and the same verify as camera frames.
    private func startTestFrames(foreign: Bool) {
        let signer = foreign ? Self.foreignSigner : Self.testSigner
        let pk = [UInt8](Self.testSigner.publicKey.rawRepresentation)
        let signerPK = [UInt8](signer.publicKey.rawRepresentation)
        let iat = UInt32(Date().timeIntervalSince1970)
        var m = RingLogin(session: session, issuedAt: iat, keyID: RingCode.fnv1a(signerPK), signature: [])
        let sig = (try? signer.signature(for: Data(RingLogin.domain + m.signedPart))) ?? Data()
        m = RingLogin(session: session, issuedAt: iat, keyID: m.keyID, signature: [UInt8](sig))
        let frames = RingCode.frames(for: m.bytes)
        let dance = RingCode.choreography(forKey: signerPK)
        if !enrolled.contains(where: { $0.bytes == pk }) {
            enrolled.append(EnrolledKey(name: "UI test computer (simulator only)", keyText: RingLogin.keyText(pk), added: Date()))
        }
        var tick = 0
        testTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, case .scanning = self.phase else { return }
                let f = frames[tick % frames.count]
                let t = Double(tick) * 0.35
                let angles = dance.map { $0 * 2 * Double.pi * t * 4 }
                var img = RingRenderer.render(f, size: 300, angles: angles)
                RingRenderer.addNoise(&img, salt: 0.01, amplitude: 18, seed: UInt64(tick + 1))
                tick += 1
                self.consume(img)
            }
        }
    }

    func consume(_ img: GrayImage) {
        viewfinder = img.uiImage
        guard case .scanning = phase, let f = RingReader.read(img) else { return }
        if assembler.add(f) {
            framesRead = assembler.parts.count
            framesNeeded = assembler.count ?? 0
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        guard let message = assembler.message else { return }
        let keys = enrolled.map(\.bytes)
        switch RingLogin.verify(message, session: session, enrolled: keys) {
        case .accepted(let kid):
            let name = enrolled.first { RingCode.fnv1a($0.bytes) == kid }?.name ?? "Enrolled key"
            finish(.success(name))
        case .unknownKey: finish(.failure("These rings are signed by a key that isn't enrolled on this iPhone."))
        case .badSignature: finish(.failure("The signature doesn't match. The rings were changed or forged."))
        case .wrongSession: finish(.failure("These rings belong to a different sign-in."))
        case .expired: finish(.failure("These rings are too old. Start again on the computer."))
        case .unreadable: finish(.failure("The rings couldn't be read."))
        }
    }

    private func finish(_ p: RingPhase) {
        testTimer?.invalidate(); testTimer = nil
        camera.stop()
        browser?.cancel(); browser = nil
        peripheral?.stopAdvertising()
        if case .success = p { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        else { UINotificationFeedbackGenerator().notificationOccurred(.error) }
        withAnimation(.spring(duration: 0.6)) { phase = p }
    }
}

extension RingSignIn: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ p: CBPeripheralManager) {
        let state = p.state
        Task { @MainActor in
            switch state {
            case .poweredOn:
                let s = CBMutableCharacteristic(type: Self.sessionUUID, properties: [.read], value: Data(RingLogin.hex(session).utf8), permissions: [.readable])
                let h = CBMutableCharacteristic(type: Self.helloUUID, properties: [.write], value: nil, permissions: [.writeable])
                let svc = CBMutableService(type: Self.serviceUUID, primary: true)
                svc.characteristics = [s, h]
                sessionChar = s
                p.add(svc)
                p.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID], CBAdvertisementDataLocalNameKey: "Ouija"])
                bleStatus = "Advertising over Bluetooth (Chrome or Edge on the computer)"
            case .unsupported: bleStatus = "Bluetooth isn't available on this device"
            case .unauthorized: bleStatus = "Bluetooth permission is off for Ouija"
            case .poweredOff: bleStatus = "Bluetooth is off"
            default: bleStatus = "Bluetooth: waiting"
            }
        }
    }

    nonisolated func peripheralManager(_ p: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for r in requests { p.respond(to: r, withResult: .success) }
        Task { @MainActor in
            bleStatus = "The ring page connected over Bluetooth"
            computerFound("Computer (Bluetooth)")
        }
    }
}

extension GrayImage {
    var uiImage: UIImage? {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                               space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// The back camera's luma plane, cropped square and scaled down to 320 px, as GrayImage frames.
final class RingCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    var onFrame: ((GrayImage) -> Void)?
    private let queue = DispatchQueue(label: "ouija.ring.camera")
    private var lastFrame = Date.distantPast

    func start(_ done: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted, let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: dev) else { done(false); return }
            self.queue.async {
                self.session.beginConfiguration()
                self.session.sessionPreset = .hd1280x720
                if self.session.canAddInput(input) { self.session.addInput(input) }
                let out = AVCaptureVideoDataOutput()
                out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
                out.alwaysDiscardsLateVideoFrames = true
                out.setSampleBufferDelegate(self, queue: self.queue)
                if self.session.canAddOutput(out) { self.session.addOutput(out) }
                self.session.commitConfiguration()
                self.session.startRunning()
                done(true)
            }
        }
    }

    func stop() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sb: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard Date().timeIntervalSince(lastFrame) > 0.08, let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        lastFrame = Date()
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return }
        let w = CVPixelBufferGetWidthOfPlane(pb, 0), h = CVPixelBufferGetHeightOfPlane(pb, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        let src = base.assumingMemoryBound(to: UInt8.self)
        let side = min(w, h), x0 = (w - side) / 2, y0 = (h - side) / 2
        let n = 320
        var px = [UInt8](repeating: 0, count: n * n)
        for y in 0..<n {
            let sy = y0 + y * side / n
            for x in 0..<n { px[y * n + x] = src[sy * stride + x0 + x * side / n] }
        }
        onFrame?(GrayImage(width: n, height: n, pixels: px))
    }
}

/// The magic rings, drawn live: four data rings spinning to the key's dance, a hub and a finder ring.
struct RingDance: View {
    var tint: Color = OuijaStyle.accent
    var speeds: [Double] = [0.08, -0.11, 0.06, -0.09]
    var bits: [[Bool]] = RingDance.demoBits

    static let demoBits: [[Bool]] = RingCode.bits(of: RingCode.frames(for: Array("NCOM OUIJA RINGS".utf8))[0])

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: OuijaTest.active)) { tl in
            let t = OuijaTest.active ? 1.3 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let R = min(size.width, size.height) / 2 * 0.92
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                func circle(_ r: Double) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
                ctx.fill(circle(R * RingCode.hubRadius), with: .color(tint))
                ctx.stroke(circle(R * (RingCode.finderInner + RingCode.finderOuter) / 2), with: .color(tint.opacity(0.9)),
                           lineWidth: R * (RingCode.finderOuter - RingCode.finderInner))
                let cell = 2 * Double.pi / Double(RingCode.cellsPerRing)
                for i in 0..<RingCode.rings {
                    let rot = speeds[i] * 2 * Double.pi * t
                    let r = R * RingCode.dataRadius[i]
                    for k in 0..<RingCode.cellsPerRing where bits[i][k] {
                        var p = Path()
                        p.addArc(center: c, radius: r, startAngle: .radians(rot + (Double(k) - 0.4) * cell),
                                 endAngle: .radians(rot + (Double(k) + 0.4) * cell), clockwise: false)
                        ctx.stroke(p, with: .color(tint.opacity(0.55 + 0.45 * Double(i) / 3)), style: StrokeStyle(lineWidth: R * RingCode.dataHalfWidth * 2, lineCap: .butt))
                    }
                    var tick = Path()
                    let tr = R * (RingCode.dataRadius[i] + RingCode.tickOffset)
                    tick.addArc(center: c, radius: tr, startAngle: .radians(rot - 0.45 * cell), endAngle: .radians(rot + 0.45 * cell), clockwise: false)
                    ctx.stroke(tick, with: .color(tint), style: StrokeStyle(lineWidth: R * RingCode.tickHalfWidth * 2))
                }
            }
        }
    }
}

struct RingSignInView: View {
    @EnvironmentObject var model: OuijaModel
    @StateObject private var flow = RingSignIn()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    stage
                        .frame(width: 280, height: 280)
                        .padding(.top, 12)
                    content
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Sign in on a computer")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear { flow.stop() }
        }
    }

    @ViewBuilder private var stage: some View {
        switch flow.phase {
        case .scanning:
            ZStack {
                if let img = flow.viewfinder {
                    Image(uiImage: img).resizable().interpolation(.medium).scaledToFill()
                } else {
                    Color.black
                }
                RoundedRectangle(cornerRadius: DisciplineShape.cornerRadius, style: .continuous)
                    .strokeBorder(OuijaStyle.accent, lineWidth: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
            .accessibilityIdentifier("rings.viewfinder")
        case .success:
            ZStack {
                RingDance(tint: OuijaStyle.ok).opacity(0.35).scaleEffect(1.08)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 96, weight: .semibold))
                    .foregroundStyle(.white, OuijaStyle.ok)
                    .transition(.scale.combined(with: .opacity))
            }
            .accessibilityIdentifier("rings.success")
        case .failure:
            ZStack {
                RingDance(tint: OuijaStyle.bad).opacity(0.3)
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 96, weight: .semibold))
                    .foregroundStyle(.white, OuijaStyle.bad)
                    .transition(.scale.combined(with: .opacity))
            }
            .accessibilityIdentifier("rings.failure")
        default:
            RingDance().accessibilityIdentifier("rings.dance")
        }
    }

    @ViewBuilder private var content: some View {
        switch flow.phase {
        case .idle:
            Text("Open the ring page on your computer, then let your iPhone find it.")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            primary("Find my computer", id: "rings.find") { flow.start(enrolled: model.settings.enrolled) }
            if model.settings.enrolled.isEmpty && !OuijaTest.active {
                Text("No computer keys are enrolled yet. Add one in Keys first.")
                    .font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
        case .searching:
            ProgressView().controlSize(.large)
            statusRows
        case .found(let name):
            Label("Found \(name)", systemImage: "desktopcomputer").font(.headline).accessibilityIdentifier("rings.found")
            Text("Point the camera at the rings").font(.title2.bold()).multilineTextAlignment(.center)
                .accessibilityIdentifier("rings.prompt")
            primary("Open camera", id: "rings.scan") { flow.beginScan() }
            if let key = flow.computerKey, RingLogin.parseKey(key) != nil,
               !model.settings.enrolled.contains(where: { $0.keyText == key }) {
                Button("Enroll this computer (key \(RingLogin.fingerprint(RingLogin.parseKey(key) ?? [])))") {
                    model.enroll(name: name, keyText: key)
                }
                .font(.footnote)
            }
            statusRows
        case .scanning:
            Text("Hold steady. Reading the ring dance…").font(.headline)
            Text(flow.framesNeeded > 0 ? "\(flow.framesRead) of \(flow.framesNeeded) frames read" : "Looking for the rings")
                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                .accessibilityIdentifier("rings.progress")
        case .success(let keyName):
            Text("Signed in").font(.title.bold()).accessibilityIdentifier("rings.result")
            Text("The rings carry a valid signature from \(keyName) for this sign-in.")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            secondary("Done") { flow.phase = .idle }
        case .failure(let why):
            Text("Not signed in").font(.title.bold()).accessibilityIdentifier("rings.result")
            Text(why).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .accessibilityIdentifier("rings.reason")
            secondary("Try again") { flow.phase = .idle }
        }
    }

    private var statusRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(flow.lanStatus, systemImage: "wifi")
            Label(flow.bleStatus, systemImage: "dot.radiowaves.left.and.right")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
    }

    private func primary(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6) }
            .buttonStyle(.glassProminent).controlSize(.large).accessibilityIdentifier(id)
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(maxWidth: .infinity).padding(.vertical, 4) }
            .buttonStyle(.glass).controlSize(.large).accessibilityIdentifier("rings.again")
    }
}
