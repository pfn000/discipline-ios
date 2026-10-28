import SwiftUI
import UIKit
import Network
import PhotosUI
import Vision
import VisionKit
import CoreImage
import UniformTypeIdentifiers
import DisciplineCore

// Discipline keeps the NCOM magic-ring unlock overlay and the code scanner. The Ouija Board itself
// is its own app since v0.5 (see Ouija/).

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
            // Long enough to read the result (and for UI tests on a slow simulator to see it).
            try? await Task.sleep(for: .seconds(2.6))
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
                    .clipShape(RoundedRectangle(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
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
