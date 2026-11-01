import SwiftUI
import Network
import CoreBluetooth
import DisciplineCore
#if canImport(NearbyInteraction)
import NearbyInteraction
#endif

// Ouija v0.3 testing devices. The list starts empty. Sniff (or Auto-sniff) tries every channel a free
// Apple account allows at the same time; the user picks a candidate to hail; only a successful connection
// makes it the one "possessed" device. Nothing is pre-listed and this iPhone is never listed.

/// Bonjour search for NCOM devices advertising `_ncom-ouija._tcp`, and a TCP connect to one.
@MainActor
final class NCOMBrowser: ObservableObject {
    private var browser: NWBrowser?
    private var endpoints: [String: NWEndpoint] = [:]
    private var connection: NWConnection?

    func browse(seconds: Double) async -> (devices: [SniffCandidate], unavailable: String?) {
        endpoints = [:]
        let b = NWBrowser(for: .bonjour(type: "_ncom-ouija._tcp", domain: nil), using: .tcp)
        browser = b
        var blocked: String?
        b.stateUpdateHandler = { state in
            switch state {
            case .failed, .waiting: blocked = "permission off"
            default: break
            }
        }
        b.browseResultsChangedHandler = { [weak self] results, _ in
            var map: [String: NWEndpoint] = [:]
            for r in results { if case let .service(name, _, _, _) = r.endpoint { map[name] = r.endpoint } }
            Task { @MainActor in self?.endpoints = map }
        }
        b.start(queue: .main)
        try? await Task.sleep(for: .seconds(seconds))
        b.cancel()
        browser = nil
        let list = endpoints.keys.sorted().map { SniffCandidate(id: "net:\($0)", name: $0, channel: .localNetwork) }
        return (list, list.isEmpty ? blocked : nil)
    }

    /// nil = connected; otherwise the reason.
    func connect(name: String, timeout: Double = 8) async -> String? {
        guard let ep = endpoints[name] else { return "it's gone from this network" }
        let c = NWConnection(to: ep, using: .tcp)
        connection = c
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            var done = false
            func finish(_ r: String?) { if !done { done = true; cont.resume(returning: r) } }
            c.stateUpdateHandler = { st in
                switch st {
                case .ready: finish(nil)
                case .failed(let e): finish(e.localizedDescription)
                case .waiting(let e): finish(e.localizedDescription)
                default: break
                }
            }
            c.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish("timed out") }
        }
    }

    func disconnect() { connection?.cancel(); connection = nil }
}

@MainActor
final class Sniffer: ObservableObject {
    @Published private(set) var devices = TestingDevices()
    private let scanner = NearbyScanner()
    private let bonjour = NCOMBrowser()

    init() { if OuijaTest.has("-uiTestingResetState") { UserDefaults.standard.removeObject(forKey: "ouija.autoSniff") } }

    private var simulating: Bool { OuijaTest.has("-uiTestingSniff") }

    /// Tries Bluetooth, local network and UWB at the same time; each reports as soon as it's done.
    func sniff() async {
        guard devices.phase != .sniffing, devices.possessed == nil else { return }
        devices.beginSniff()
        await withTaskGroup(of: (SniffChannel, [SniffCandidate], String?).self) { group in
            for ch in SniffChannel.allCases {
                group.addTask { @MainActor in
                    let r = await self.run(ch)
                    return (ch, r.0, r.1)
                }
            }
            for await (ch, found, why) in group { devices.report(ch, found: found, unavailable: why) }
        }
        devices.finishSniff()
    }

    private func run(_ ch: SniffChannel) async -> ([SniffCandidate], String?) {
        if simulating { return await simulated(ch) }
        if OuijaTest.active { return ([], "not run in UI tests") }
        switch ch {
        case .bluetooth: let r = await scanner.scan(seconds: 6); return (r.devices, r.unavailable)
        case .localNetwork: let r = await bonjour.browse(seconds: 4); return (r.devices, r.unavailable)
        case .uwb: return ([], Self.uwbNote())
        }
    }

    /// UWB / Nearby Interaction needs a peer that hands over a discovery token on another channel, so with
    /// nothing connected there is never a peer to find. "not on this device" when the chip is missing.
    static func uwbNote() -> String {
        #if canImport(NearbyInteraction)
        if #available(iOS 16.0, *) { return NISession.deviceCapabilities.supportsPreciseDistanceMeasurement ? "no peer" : "not on this device" }
        return "not on this device"
        #else
        return "not on this device"
        #endif
    }

    /// Simulator-only stand-ins for UI tests, tagged `simulated` and shown with a "test" label.
    /// `-uiTestingSniff ble=2,lan=1` gives that many candidates; Bluetooth takes longest so a screenshot can catch it mid-scan.
    private func simulated(_ ch: SniffChannel) async -> ([SniffCandidate], String?) {
        let spec = Dictionary(uniqueKeysWithValues: (OuijaTest.value("-uiTestingSniff") ?? "").split(separator: ",").compactMap { kv -> (String, Int)? in
            let p = kv.split(separator: "="); return p.count == 2 ? (String(p[0]), Int(p[1]) ?? 0) : nil
        })
        switch ch {
        case .bluetooth:
            try? await Task.sleep(for: .seconds(OuijaTest.has("-uiTestingSniffHold") ? 30 : 3.5))
            let n = spec["ble"] ?? 0
            return ((0..<n).map { SniffCandidate(id: "sim-ble-\($0)", name: "Test bench \($0 + 1)", channel: .bluetooth, rssi: -48 - $0 * 9, simulated: true) }, nil)
        case .localNetwork:
            try? await Task.sleep(for: .milliseconds(400))
            let n = spec["lan"] ?? 0
            return ((0..<n).map { SniffCandidate(id: "sim-net-\($0)", name: "ncom-test-\($0 + 1)", channel: .localNetwork, simulated: true) }, nil)
        case .uwb:
            try? await Task.sleep(for: .milliseconds(200))
            return ([], "no peer")
        }
    }

    func hail(_ c: SniffCandidate) async {
        guard devices.hail(c.id) != nil else { return }
        let failure: String?
        if c.simulated {
            try? await Task.sleep(for: .milliseconds(900))
            failure = c.name.contains("refuses") ? "the device refused" : nil
        } else {
            switch c.channel {
            case .bluetooth: failure = await scanner.connect(id: c.id)
            case .localNetwork: failure = await bonjour.connect(name: c.name)
            case .uwb: failure = "UWB needs a peer token from a connected device"
            }
        }
        if let failure { devices.connectFailed(c.id, reason: failure) } else { devices.connected(c.id) }
    }

    func disconnect() {
        if let p = devices.possessed, !p.simulated {
            switch p.channel {
            case .bluetooth: scanner.disconnect(id: p.id)
            case .localNetwork: bonjour.disconnect()
            case .uwb: break
            }
        }
        devices.disconnect()
    }
}

/// The Board's testing-devices card: empty until the user sniffs and connects.
struct TestingDevicesCard: View {
    @EnvironmentObject var sniffer: Sniffer
    @AppStorage("ouija.autoSniff") private var autoSniff = false

    private var d: TestingDevices { sniffer.devices }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let p = d.listed.first { possessedRow(p) } else { emptyState; sniffControls; results; candidates }
            if let e = d.lastError {
                Text(e).font(.footnote).foregroundStyle(OuijaStyle.bad).accessibilityIdentifier("ouija.sniff.error")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DisciplineShape.cornerRadius, style: .continuous))
        .task(id: autoSniff) {
            guard autoSniff else { return }
            while !Task.isCancelled && autoSniff {
                if sniffer.devices.possessed == nil { await sniffer.sniff() }
                try? await Task.sleep(for: .seconds(OuijaTest.active ? 60 : 20))
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 14) {
            Image(systemName: "scope").font(.system(size: 26)).foregroundStyle(OuijaStyle.accent)
                .frame(width: 52, height: 52).glassEffect(.regular, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("No device possessed").font(.title3.bold()).accessibilityIdentifier("ouija.devices.empty")
                Text("Nothing is listed until you sniff and connect to it.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var sniffControls: some View {
        VStack(spacing: 10) {
            Button { Task { await sniffer.sniff() } } label: {
                HStack {
                    if d.phase == .sniffing { ProgressView().tint(OuijaStyle.onAccent) }
                    Text(d.phase == .sniffing ? "Sniffing…" : "Sniff").font(.headline)
                }
                .foregroundStyle(OuijaStyle.onAccent).frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .disabled(d.phase == .sniffing)
            .accessibilityIdentifier("ouija.sniff")
            Toggle("Auto-sniff", isOn: $autoSniff)
                .tint(OuijaStyle.accent)
                .accessibilityIdentifier("ouija.autosniff")
        }
    }

    @ViewBuilder private var results: some View {
        if d.phase != .idle {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(SniffChannel.allCases) { ch in
                    HStack(spacing: 8) {
                        Image(systemName: icon(ch)).frame(width: 18).foregroundStyle(.secondary)
                        Text(ch.title).font(.footnote.weight(.semibold))
                        Spacer()
                        if d.channels[ch] == .scanning { ProgressView().controlSize(.mini) }
                        Text(d.channels[ch]?.text ?? "").font(.footnote.monospaced())
                            .foregroundStyle(isFound(ch) ? OuijaStyle.ok : .secondary)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(d.resultLine)
            .accessibilityIdentifier("ouija.sniff.results")
        }
    }

    @ViewBuilder private var candidates: some View {
        if !d.candidates.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Found. Tap Hail to connect.").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(d.candidates.enumerated()), id: \.element.id) { i, c in
                    HStack(spacing: 10) {
                        Image(systemName: icon(c.channel)).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text([c.channel.title, c.rssi.map { "\($0) dBm" }, c.simulated ? "test stand-in" : nil].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { Task { await sniffer.hail(c) } } label: {
                            Text(d.hailing == c.id ? "Hailing…" : "Hail").font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.glass).disabled(d.hailing != nil)
                        .accessibilityIdentifier("ouija.hail.\(i)")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("ouija.candidate.\(i)")
                }
            }
        }
    }

    private func possessedRow(_ p: PossessedDevice) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon(p.channel)).font(.system(size: 26)).foregroundStyle(OuijaStyle.accent)
                .frame(width: 52, height: 52).glassEffect(.regular, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(p.name).font(.title3.bold()).lineLimit(1).accessibilityIdentifier("ouija.possessed.name")
                HStack(spacing: 5) {
                    Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(OuijaStyle.ok)
                    Text("Possessed · \(p.channel.title)\(p.simulated ? " · test stand-in" : "")").font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("ouija.possessed.status")
            }
            Spacer(minLength: 4)
            Button("Disconnect") { sniffer.disconnect() }
                .buttonStyle(.glass)
                .accessibilityIdentifier("ouija.disconnect")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ouija.possessed")
    }

    private func isFound(_ ch: SniffChannel) -> Bool { if case .found(let n) = d.channels[ch], n > 0 { return true }; return false }
    private func icon(_ ch: SniffChannel) -> String {
        switch ch { case .bluetooth: return "dot.radiowaves.left.and.right"; case .localNetwork: return "network"; case .uwb: return "wave.3.right" }
    }
}
