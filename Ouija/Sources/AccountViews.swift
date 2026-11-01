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
                        .font(.headline).foregroundStyle(OuijaStyle.onAccent).frame(maxWidth: .infinity).padding(.vertical, 6)
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
                OuijaStyle.accent
                Text(OuijaAccount.initials(of: name)).font(.system(size: 34, weight: .semibold, design: .rounded)).foregroundStyle(OuijaStyle.onAccent)
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
    @State private var showSphere = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    stage.padding(.top, 8)
                    status
                    buttons      // above the steps so the choice is always on screen
                    steps
                    footer
                }
                .padding(.horizontal, 22).padding(.bottom, 28)
            }
            .navigationTitle("Developer sign-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.accessibilityIdentifier("devcard.close") } }
            .onAppear { flow.setUpTestCard(model: model) }
            .task {
                // On an iPhone the reader opens by itself once the card has floated in: the screen only asks for the tap.
                guard !OuijaTest.active, flow.phase == .idle else { return }
                try? await Task.sleep(for: .seconds(1.1))
                if flow.phase == .idle { flow.start(model: model) }
            }
            .fullScreenCover(isPresented: $showSphere) { ShowSphereView(sphere: sphereState) }
        }
    }

    private var sphereState: SphereState { flow.result.qrl.map { MagicSphere.state(verdict: $0) } ?? .idle }

    private var cardLook: IDCardLook {
        switch flow.phase {
        case .idle: return .floating
        case .waitingForCard, .talking: return .reading
        case .failed: return .failed
        default: return .ok
        }
    }

    private var cardOwner: String? { if case .granted(let n) = flow.phase { return n }; return flow.result.grantedOwner }

    @ViewBuilder private var stage: some View {
        switch flow.phase {
        case .idle, .waitingForCard, .talking, .failed, .cardOK:
            // The virtual glass ID floats down and hovers; tapping it (or the real card) starts the read.
            Button { if flow.phase == .idle || flow.isFailed { flow.start(model: model) } } label: {
                GlassIDCard(look: cardLook, landscape: true, photo: model.profileImage, owner: cardLook == .ok ? cardOwner : nil)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 360)
            .accessibilityLabel(cardLook == .ok ? "ID card accepted" : cardLook == .failed ? "ID card refused" : "Tap your ID")
            .accessibilityValue(cardLook == .ok ? "green" : cardLook == .failed ? "red" : "glass")
            .accessibilityIdentifier("devcard.start")
        case .scanning:
            // Green card, then the camera: scan the sphere the NCOM Dev website shows.
            SphereScanView(sphere: .idle, reading: true)
        case .dancing:
            // The sphere moves to a hash of BOTH halves of the magic QR (NCOM Dev + GlassVault).
            MagicSphereView(state: sphereState)
                .frame(width: 240, height: 240)
                .accessibilityIdentifier("devcard.dance")
        case .granted:
            ZStack {
                MagicSphereView(state: sphereState, tint: OuijaStyle.ok).opacity(0.45)
                Image(systemName: "checkmark.circle.fill").font(.system(size: 80, weight: .semibold)).foregroundStyle(OuijaStyle.onAccent, OuijaStyle.ok)
            }
            .frame(width: 220, height: 220)
        case .choice:
            ZStack {
                // Missing or wrong half: the sphere breaks (dots scatter, stall, turn red).
                MagicSphereView(state: sphereState.isBroken ? sphereState : .broken(parties: [], missing: false))
                Image(systemName: "exclamationmark.shield.fill").font(.system(size: 64, weight: .semibold)).foregroundStyle(OuijaStyle.onAccent, OuijaStyle.bad)
            }
            .frame(width: 220, height: 220)
            .accessibilityIdentifier("devcard.stopped")
        }
    }

    @ViewBuilder private var status: some View {
        switch flow.phase {
        case .idle, .waitingForCard, .talking:
            Text("Tap your ID").font(.title2.bold()).accessibilityIdentifier("devcard.prompt")
        case .cardOK:
            Text("ID accepted").font(.title2.bold()).accessibilityIdentifier("devcard.cardOK")
        case .scanning:
            EmptyView()
        case .dancing:
            Text("Both halves agree").font(.title2.bold()).accessibilityIdentifier("devcard.agree")
            Text("The sphere moves to NCOM Dev's and GlassVault's signatures together.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
        // The eight checks show only once there is an outcome (the tap itself asks for nothing else).
        if flow.showsSteps && !flow.result.steps.isEmpty {
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
        case .failed:
            Button { flow.start(model: model) } label: {
                Text("Try again").font(.headline).foregroundStyle(OuijaStyle.onAccent).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent).controlSize(.large).accessibilityIdentifier("devcard.retry")
        case .scanning, .dancing:
            // Mode (b): the phone shows the sphere instead, for smart glasses or another device to scan.
            Button { showSphere = true } label: {
                Label("Show sphere for another device", systemImage: "eyeglasses").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.glass).accessibilityIdentifier("devcard.showSphere")
        case .granted:
            Button { flow.commit(model: model); dismiss() } label: { Text("Continue").font(.headline).foregroundStyle(OuijaStyle.onAccent).frame(maxWidth: .infinity).padding(.vertical, 6) }
                .buttonStyle(.glassProminent).controlSize(.large).accessibilityIdentifier("devcard.continue")
        case .choice:
            VStack(spacing: 10) {
                Button { flow.phase = .failed("To replace the card or this iPhone's key, use your one-time recovery code with NCOM, then tap the new card.") } label: {
                    Label("Replace card / key", systemImage: "arrow.triangle.2.circlepath").font(.headline).foregroundStyle(OuijaStyle.onAccent).frame(maxWidth: .infinity).padding(.vertical, 6)
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

/// Scans for the Bluetooth LE devices actually advertising nearby and can connect to one. Nothing is
/// reported that a scan didn't see.
@MainActor
final class NearbyScanner: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var found: [SniffCandidate] = []
    private var central: CBCentralManager?
    private var peripherals: [String: CBPeripheral] = [:]
    private var connectWaiter: CheckedContinuation<String?, Never>?

    /// `unavailable` is a short honest reason when the radio couldn't run ("off", "permission off", "not on this device").
    func scan(seconds: Double) async -> (devices: [SniffCandidate], unavailable: String?) {
        found = []
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        for _ in 0..<30 where central?.state == .unknown || central?.state == .resetting { try? await Task.sleep(for: .milliseconds(100)) }
        switch central?.state {
        case .poweredOn: break
        case .unsupported: return ([], "not on this device")
        case .unauthorized: return ([], "permission off")
        case .poweredOff: return ([], "turned off")
        default: return ([], "didn't start")
        }
        central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        try? await Task.sleep(for: .seconds(seconds))
        central?.stopScan()
        return (found, nil)
    }

    /// nil = connected; otherwise the reason it wasn't.
    func connect(id: String, timeout: Double = 8) async -> String? {
        guard let p = peripherals[id], let central else { return "it's out of range now" }
        return await withCheckedContinuation { cont in
            connectWaiter = cont
            central.connect(p)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                if let self, let w = self.connectWaiter { self.connectWaiter = nil; central.cancelPeripheralConnection(p); w.resume(returning: "timed out") }
            }
        }
    }

    func disconnect(id: String) { if let p = peripherals[id] { central?.cancelPeripheralConnection(p) } }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {}

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? SniffCandidate.unnamed
        let id = peripheral.identifier.uuidString
        let rssi = RSSI.intValue
        Task { @MainActor in
            self.peripherals[id] = peripheral
            if let i = self.found.firstIndex(where: { $0.id == id }) { self.found[i].rssi = rssi }
            else { self.found.append(SniffCandidate(id: id, name: name, channel: .bluetooth, rssi: rssi)) }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in if let w = self.connectWaiter { self.connectWaiter = nil; w.resume(returning: nil) } }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let why = error?.localizedDescription ?? "the device refused"
        Task { @MainActor in if let w = self.connectWaiter { self.connectWaiter = nil; w.resume(returning: why) } }
    }
}
