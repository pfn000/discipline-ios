import SwiftUI
import PhotosUI
import CoreBluetooth
import DisciplineCore

/// "Your account": who is signing in to Ouija. Nothing is pre-filled; the name is what the person types
/// (or what NCOM's verifier returns for a developer card), and it is kept in the Keychain on this iPhone.
struct AccountPage: View {
    @EnvironmentObject var model: OuijaModel
    @State private var name = ""
    @State private var photo: PhotosPickerItem?
    @State private var problem = ""
    @State private var showCard = false
    @FocusState private var nameFocused: Bool

    private var valid: Bool { if case .success = OuijaAccount.validName(name) { return true }; return false }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                avatar.padding(.top, 36)
                VStack(spacing: 6) {
                    Text("Your account").font(.largeTitle.bold()).accessibilityIdentifier("ouija.account")
                    Text("Ouija signs in as you. Type your name; nothing is filled in for you.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                TextField("Your name", text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($nameFocused)
                    .onSubmit { nameFocused = false }
                    .font(.title3)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
                    .accessibilityIdentifier("account.name")
                PhotosPicker(selection: $photo, matching: .images) {
                    Label(model.profileImage == nil ? "Add a profile photo (optional)" : "Change photo", systemImage: "camera")
                        .font(.subheadline)
                }
                .accessibilityIdentifier("account.photo")
                .onChange(of: photo) { _, item in
                    Task { model.setProfilePhoto(try? await item?.loadTransferable(type: Data.self)) }
                }
                ThisDeviceRow().accessibilityIdentifier("account.thisDevice")
                if !problem.isEmpty {
                    Text(problem).font(.footnote).foregroundStyle(OuijaStyle.bad).accessibilityIdentifier("account.problem")
                }
                Button(action: save) {
                    Text(valid ? "Continue as \(OuijaAccount.validName(name).successValue ?? name)" : "Continue")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!valid)
                .accessibilityIdentifier("account.continue")
                Button { showCard = true } label: {
                    Label("NCOM developer? Tap your ID card", systemImage: "wave.3.right.circle")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("account.devCard")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showCard) { DevCardSheet().presentationDetents([.large]) }
    }

    private var avatar: some View {
        ZStack {
            if let img = model.profileImage {
                Image(uiImage: img).resizable().scaledToFill()
            } else if !OuijaAccount.initials(of: name).isEmpty {
                LinearGradient(colors: [OuijaStyle.accent, OuijaStyle.accent.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(OuijaAccount.initials(of: name)).font(.system(size: 34, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            } else {
                Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 44)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(Circle())
        .glassEffect(.regular, in: Circle())
        .accessibilityIdentifier("account.avatar")
    }

    private func save() {
        if let p = model.createAccount(name: name) { problem = p; return }
        problem = ""
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

extension Result {
    var successValue: Success? { if case .success(let v) = self { return v }; return nil }
}

/// The phone Ouija is running on, from what the system reports.
struct ThisDeviceRow: View {
    @EnvironmentObject var model: OuijaModel
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.thisDevice.model.lowercased().contains("ipad") ? "ipad" : "iphone")
                .font(.title2).frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Signing in on \(model.thisDevice.title)").font(.subheadline.weight(.semibold))
                Text(model.thisDevice.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Developer sign-in with the NCOM Magic ID card

struct DevCardSheet: View {
    @EnvironmentObject var model: OuijaModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var flow = MagicCardFlow()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    stage.frame(width: 220, height: 220).padding(.top, 8)
                    status
                    steps
                    buttons
                    footer
                }
                .padding(.horizontal, 22).padding(.bottom, 28)
            }
            .navigationTitle("Developer sign-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.accessibilityIdentifier("devcard.close") } }
            .onAppear { flow.setUpTestCard(model: model) }
        }
    }

    @ViewBuilder private var stage: some View {
        switch flow.phase {
        case .dancing:
            // The rings drawn from BOTH halves of the magic QR (NCOM Dev + GlassVault).
            RingDance(speeds: flow.dance?.speeds ?? [0.08, -0.11, 0.06, -0.09], bits: flow.dance?.bits ?? RingDance.demoBits)
                .accessibilityIdentifier("devcard.dance")
        case .granted:
            ZStack {
                RingDance(tint: OuijaStyle.ok, speeds: flow.dance?.speeds ?? [0.08, -0.11, 0.06, -0.09], bits: flow.dance?.bits ?? RingDance.demoBits)
                    .opacity(0.35)
                Image(systemName: "checkmark.circle.fill").font(.system(size: 80, weight: .semibold)).foregroundStyle(.white, OuijaStyle.ok)
            }
        case .choice, .failed:
            ZStack {
                RingDance(tint: OuijaStyle.bad).opacity(0.25)
                Image(systemName: "exclamationmark.shield.fill").font(.system(size: 80, weight: .semibold)).foregroundStyle(.white, OuijaStyle.bad)
            }
            .accessibilityIdentifier("devcard.stopped")
        case .talking, .waitingForCard:
            ZStack { RingDance().opacity(0.5); ProgressView().controlSize(.large) }
        case .idle:
            Image(systemName: "wave.3.right.circle.fill").font(.system(size: 110)).foregroundStyle(OuijaStyle.accent)
        }
    }

    @ViewBuilder private var status: some View {
        switch flow.phase {
        case .idle:
            Text("Tap your NCOM ID card").font(.title2.bold())
            Text("Hold the card to the top of your iPhone. NCOM Dev, GlassVault and this iPhone must all say yes. The card's key works once; a new one is written every tap.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        case .waitingForCard: Text("Hold your card to the top of your iPhone…").font(.headline)
        case .talking: Text("Checking with NCOM Dev and GlassVault…").font(.headline)
        case .dancing:
            Text("Both halves agree").font(.title2.bold()).accessibilityIdentifier("devcard.agree")
            Text("The rings are drawn from NCOM Dev's and GlassVault's signatures together.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        case .granted(let name):
            Text("Signed in as \(name)").font(.title2.bold()).accessibilityIdentifier("devcard.result")
            Text("Developer card · three thumbs up").font(.callout).foregroundStyle(.secondary)
        case .choice:
            Text("The magic QR doesn't match").font(.title2.bold()).accessibilityIdentifier("devcard.choiceTitle")
            Text(flow.result.report?.detail ?? "One half of the check is missing or wrong.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("Not signed in. The card is locked and this was logged on both sides.").font(.footnote).foregroundStyle(.secondary)
        case .failed(let why):
            Text("Not signed in").font(.title2.bold()).accessibilityIdentifier("devcard.result")
            Text(why).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).accessibilityIdentifier("devcard.why")
        }
    }

    @ViewBuilder private var steps: some View {
        if !flow.result.steps.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(flow.result.steps, id: \.step) { s in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: s.ok ? "hand.thumbsup.fill" : "xmark.octagon.fill")
                            .foregroundStyle(s.ok ? OuijaStyle.ok : OuijaStyle.bad).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(s.step.rawValue). \(s.step.title)").font(.footnote.weight(.semibold))
                            if !s.ok { Text(s.words).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("devcard.step.\(s.step.rawValue)")
                    .accessibilityValue(s.ok ? "yes" : "no")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder private var buttons: some View {
        switch flow.phase {
        case .idle, .failed:
            Button { flow.start(model: model) } label: {
                Text(flow.phase == .idle ? "Tap card" : "Try again").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent).controlSize(.large).accessibilityIdentifier("devcard.start")
        case .granted:
            Button { flow.commit(model: model); dismiss() } label: { Text("Continue").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6) }
                .buttonStyle(.glassProminent).controlSize(.large).accessibilityIdentifier("devcard.continue")
        case .choice:
            VStack(spacing: 10) {
                Button { flow.phase = .failed("To replace the card or this iPhone's key, use your one-time recovery code with NCOM, then tap the new card.") } label: {
                    Label("Replace card / key", systemImage: "arrow.triangle.2.circlepath").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent).controlSize(.large).accessibilityIdentifier("devcard.replace")
                Button { flow.reportToIT(model: model) } label: {
                    Label(flow.reported ? "Reported to IT security" : "Report to IT security", systemImage: flow.reported ? "checkmark.shield" : "exclamationmark.bubble")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glass).controlSize(.large).disabled(flow.reported).accessibilityIdentifier("devcard.report")
            }
        default: EmptyView()
        }
    }

    private var footer: some View {
        let key = model.magicKey
        return VStack(spacing: 4) {
            Text("This iPhone's key \(key.fingerprint) · \(key.kind)").font(.caption2.monospaced())
            Text(model.settings.verifierURL.isEmpty ? (OuijaTest.has("-uiTestingMagicKeyMock") ? "Test verifier on this simulator" : "NCOM verifier: not set up yet")
                                                    : "NCOM verifier: \(model.settings.verifierURL)").font(.caption2)
        }
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .accessibilityIdentifier("devcard.footer")
    }
}

// MARK: - Real nearby devices (Bluetooth LE)

/// Lists the Bluetooth LE devices actually advertising nearby. Nothing is listed that a scan didn't see.
@MainActor
final class NearbyScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published var found: [DiscoveredDevice] = []
    @Published var state = "Not started"
    private var central: CBCentralManager?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func scan(seconds: Double) async -> (devices: [DiscoveredDevice], note: String) {
        found = []
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        // Wait for the radio state (first use asks for Bluetooth permission).
        for _ in 0..<30 where central?.state == .unknown || central?.state == .resetting { try? await Task.sleep(for: .milliseconds(100)) }
        switch central?.state {
        case .poweredOn: break
        case .unsupported: return ([], "Bluetooth isn't available on this device (the simulator has none).")
        case .unauthorized: return ([], "Bluetooth permission is off for Ouija (Settings > Ouija).")
        case .poweredOff: return ([], "Bluetooth is turned off.")
        default: return ([], "Bluetooth didn't start.")
        }
        state = "Scanning"
        central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        try? await Task.sleep(for: .seconds(seconds))
        central?.stopScan()
        state = "Done"
        return (found, found.isEmpty ? "No Bluetooth devices found nearby." : "Found \(found.count) Bluetooth device\(found.count == 1 ? "" : "s").")
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {}

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? DiscoveredDevice.unnamed
        let id = peripheral.identifier.uuidString
        let rssi = RSSI.intValue
        Task { @MainActor in
            if let i = self.found.firstIndex(where: { $0.id == id }) { self.found[i].rssi = rssi }
            else { self.found.append(DiscoveredDevice(id: id, name: name, via: .bluetooth, rssi: rssi)) }
        }
    }
}
