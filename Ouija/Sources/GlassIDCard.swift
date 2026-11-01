import SwiftUI
import AVFoundation
import DisciplineCore

// Ouija v0.4: the virtual glass ID (Saidie, Nov 1 2026, 3:54 PM: "It should only ask when to tap my ID, and an
// actual virtual glass ID should float from the top, and when it scanned similar to like Apple Pay, it turns green,
// but if it fails the virtual ID card above jiggles and flashes red"; 3:55 PM: landscape first, her photo fills the
// card with no blank space, and only her real logos — never a made-up one).
// Logos: Assets OuijaLogoWhite (her OuijaBoard_White_Logo) and NCOMLogo (her NCOM-official-logo-full), unchanged.

enum IDCardLook: Equatable { case floating, reading, ok, failed }

/// Side-to-side shake, like a wrong passcode.
struct Shake: GeometryEffect {
    var travel: CGFloat = 10
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * 6), y: 0))
    }
}

struct GlassIDCard: View {
    var look: IDCardLook
    var landscape: Bool = true
    var photo: UIImage? = nil
    var owner: String? = nil
    /// Freeze the shake mid-swing (screenshots).
    var frozenShake: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var arrived = false
    @State private var bob = false
    @State private var shakes: CGFloat = 0

    private var aspect: CGFloat { landscape ? 1.586 : 1 / 1.586 }   // ID-1 card, 85.6 x 54 mm
    private var tint: Color? { look == .ok ? OuijaStyle.ok : look == .failed ? OuijaStyle.bad : nil }

    var body: some View {
        card
            .aspectRatio(aspect, contentMode: .fit)
            .modifier(Shake(animatableData: frozenShake ? 0.25 : shakes))
            .offset(y: arrived ? (reduceMotion ? 0 : (bob ? -5 : 5)) : -520)
            .opacity(arrived ? 1 : 0)
            .shadow(color: (tint ?? OuijaStyle.accent(scheme)).opacity(tint == nil ? 0.18 : 0.55), radius: tint == nil ? 18 : 26)
            .onAppear {
                if reduceMotion || OuijaTest.has("-uiTestingCardStill") { arrived = true; return }
                withAnimation(.spring(response: 0.8, dampingFraction: 0.78)) { arrived = true }
                // The idle bob never ends, so UI tests skip it unless they record it (XCTest waits for animations to settle).
                guard !OuijaTest.active || OuijaTest.has("-uiTestingSphereLive") || OuijaTest.value("-uiTestingIDCardShowcase") == "loop" else { return }
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true).delay(0.8)) { bob = true }
            }
            .onChange(of: look) { _, new in
                if new == .failed && !reduceMotion { withAnimation(.linear(duration: 0.55)) { shakes += 1 } }
            }
            .sensoryFeedback(trigger: look) { (_: IDCardLook, new: IDCardLook) -> SensoryFeedback? in
                switch new { case .ok: return .success; case .failed: return .error; default: return nil }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(look == .ok ? "ID card accepted" : look == .failed ? "ID card refused" : look == .reading ? "Reading ID card" : "Tap your ID")
            .accessibilityValue(look == .ok ? "green" : look == .failed ? "red" : "glass")
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: landscape ? 22 : 26, style: .continuous)
        return GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .bottom) {
                // Her photo fills the whole card, edge to edge (aspect fill, cropped to the card).
                Group {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else {
                        // No photo in the app yet: a labelled slot that fills the card (no stock or made-up face).
                        ZStack {
                            Rectangle().fill(OuijaStyle.hairline)
                            VStack(spacing: 6) {
                                Image(systemName: "person.crop.rectangle").font(.system(size: 34, weight: .light))
                                Text("Photo slot · your photo fills the card").font(.caption2.weight(.semibold))
                                    .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 10)
                            }
                            .foregroundStyle(OuijaStyle.ink.opacity(0.55))
                        }
                        .accessibilityIdentifier("idcard.photoSlot")
                    }
                }
                .frame(width: w, height: h).clipped()
                band(width: w).frame(width: w)
                if let tint {
                    Rectangle().fill(tint.opacity(0.38)).allowsHitTesting(false)
                    Image(systemName: look == .ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: min(w, h) * 0.3, weight: .semibold))
                        .foregroundStyle(OuijaStyle.alwaysWhite, tint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: w, height: h)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder((tint ?? OuijaStyle.accent(scheme)).opacity(tint == nil ? 0.35 : 0.9), lineWidth: tint == nil ? 1 : 2.5))
        .glassEffect(.regular, in: shape)
        .animation(.easeInOut(duration: 0.35), value: look)
    }

    /// The glass band with her two real logos, sized from the card's width so nothing overflows.
    @ViewBuilder private func band(width w: CGFloat) -> some View {
        let title = owner ?? "NCOM Developer ID"
        let sub = owner == nil ? "Tap to the top of your iPhone" : "NCOM Developer ID"
        Group {
            if landscape {
                HStack(spacing: w * 0.03) {
                    Image("OuijaLogoWhite").resizable().scaledToFit().frame(height: w * 0.085)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
                        Text(sub).font(.caption2).opacity(0.8).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(OuijaStyle.alwaysWhite)
                    .layoutPriority(-1)
                    Spacer(minLength: 2)
                    Image("NCOMLogo").resizable().scaledToFit().frame(height: w * 0.062)
                }
                .padding(.horizontal, w * 0.045).padding(.vertical, w * 0.028)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image("OuijaLogoWhite").resizable().scaledToFit().frame(height: w * 0.17)
                        Spacer(minLength: 4)
                        Image("NCOMLogo").resizable().scaledToFit().frame(height: w * 0.11)
                    }
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
                    Text(sub).font(.caption2).opacity(0.8).lineLimit(2).minimumScaleFactor(0.7)
                }
                .foregroundStyle(OuijaStyle.alwaysWhite)
                .padding(w * 0.065)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OuijaStyle.alwaysBlack.opacity(0.42))
        .background(.ultraThinMaterial)
    }
}

/// The scan view: point the camera at the sphere on the NCOM Dev screen. The camera feed is real on an iPhone;
/// reading the flashes off it is not built yet (SphereBeacon is the decoder, fed by a stand-in), and it says so.
struct SphereScanView: View {
    var sphere: SphereState
    var reading: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(OuijaStyle.alwaysBlack)
                CameraPreview().clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                // The NCOM Dev screen's sphere, as the stand-in shows it (no website runs in this build).
                MagicSphereView(state: sphere, tint: OuijaStyle.alwaysWhite).padding(34)
                Viewfinder().stroke(OuijaStyle.alwaysWhite, style: StrokeStyle(lineWidth: 4, lineCap: .round)).padding(14)
            }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityIdentifier("devcard.scanView")
            Text(reading ? "Scan the sphere on the NCOM Dev screen" : "Sphere read").font(.headline)
                .accessibilityIdentifier("devcard.scanPrompt")
            Text("Test stand-in: the NCOM Dev website isn't live yet, so the sphere here is drawn by Ouija and the decoder is fed by the test verifier.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .accessibilityIdentifier("devcard.scanStandIn")
        }
    }
}

/// Four corner brackets.
struct Viewfinder: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); let l = min(r.width, r.height) * 0.16
        for (x, y, dx, dy) in [(r.minX, r.minY, 1.0, 1.0), (r.maxX, r.minY, -1.0, 1.0), (r.minX, r.maxY, 1.0, -1.0), (r.maxX, r.maxY, -1.0, -1.0)] {
            p.move(to: CGPoint(x: x, y: y + dy * l)); p.addLine(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + dx * l, y: y))
        }
        return p
    }
}

/// The back camera's live feed (an iPhone only; the simulator has no camera, so this stays black there).
struct CameraPreview: UIViewRepresentable {
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        let session = AVCaptureSession()
        func start() {
            #if !targetEnvironment(simulator)
            guard !OuijaTest.active, AVCaptureDevice.authorizationStatus(for: .video) != .denied,
                  let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: cam), session.canAddInput(input) else { return }
            session.addInput(input)
            preview.session = session
            preview.videoGravity = .resizeAspectFill
            let s = session
            DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }
            #endif
        }
        func stop() { let s = session; DispatchQueue.global(qos: .utility).async { if s.isRunning { s.stopRunning() } } }
    }
    func makeUIView(context: Context) -> PreviewView { let v = PreviewView(); v.start(); return v }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
    static func dismantleUIView(_ uiView: PreviewView, coordinator: ()) { uiView.stop() }
}

/// Mode (b): the phone shows the sphere for another device to scan (smart glasses, a custom or virtual device).
/// Saidie, 3:56 PM: "the dots will show up on the phone since the glasses will scan".
struct ShowSphereView: View {
    var sphere: SphereState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 16) {
            HStack { Spacer(); Button("Done") { dismiss() }.font(.headline).accessibilityIdentifier("showsphere.done") }
            Spacer()
            MagicSphereView(state: sphere).frame(maxWidth: 360).accessibilityIdentifier("showsphere.sphere")
            Text("Show this to the other device").font(.title3.bold()).accessibilityIdentifier("showsphere.title")
            Text("Smart glasses or a custom or virtual device scans the sphere on this screen. Its dance comes from both halves (NCOM Dev + GlassVault), the same as the website's.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("Test stand-in: no glasses or second device is connected, so nothing is scanning yet.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
        .background(scheme == .dark ? OuijaStyle.alwaysBlack : OuijaStyle.alwaysWhite)
    }
}

/// UI-test only (-uiTestingIDCardShowcase <float|fail|ok|scan|portrait|loop>): the glass ID on its own, for the
/// screenshots and the recorded video (loop: float in, fail and shake red, then succeed green, then the scan view).
struct IDCardShowcase: View {
    let mode: String
    @Environment(\.colorScheme) private var scheme
    @State private var look: IDCardLook = .floating
    @State private var scanning = false

    private var sphere: SphereState { .alive(MagicSphere.params(ncomDev: "NCOM Dev · test card", glassVault: "GlassVault · test card")) }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            if scanning {
                SphereScanView(sphere: sphere, reading: true).padding(.horizontal, 28)
            } else {
                GlassIDCard(look: look, landscape: mode != "portrait", owner: look == .ok ? "Test Owner" : nil, frozenShake: mode == "fail")
                    .frame(maxWidth: mode == "portrait" ? 220 : 340)
                    .accessibilityIdentifier("idcard.card")
                Text(look == .failed ? "Didn't read. Try again." : look == .ok ? "ID accepted" : "Tap your ID").font(.title2.bold())
                    .accessibilityIdentifier("idcard.prompt")
            }
            Text("Test stand-in: success and failure come from the test verifier, not a real card.")
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(scheme == .dark ? OuijaStyle.alwaysBlack : OuijaStyle.alwaysWhite)
        .task {
            switch mode {
            case "fail": look = .failed
            case "ok": look = .ok
            case "scan": scanning = true
            case "loop":
                try? await Task.sleep(for: .seconds(1.6)); look = .reading
                try? await Task.sleep(for: .seconds(0.9)); look = .failed
                try? await Task.sleep(for: .seconds(1.5)); look = .floating
                try? await Task.sleep(for: .seconds(0.7)); look = .reading
                try? await Task.sleep(for: .seconds(0.9)); look = .ok
                try? await Task.sleep(for: .seconds(1.8)); withAnimation(.smooth) { scanning = true }
            default: break
            }
        }
    }
}
