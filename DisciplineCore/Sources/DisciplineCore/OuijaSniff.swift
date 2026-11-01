import Foundation

// Ouija v0.3: the testing-devices list starts empty. Only a device Ouija sniffed out, hailed and
// connected to is ever listed (Saidie, Nov 1 2026 12:56 PM: "the testing devices should ONLY show the
// device that is possessed"). Nothing here invents a device; every candidate comes from a real scan.

public enum SniffChannel: String, CaseIterable, Codable, Sendable, Identifiable {
    case bluetooth, localNetwork, uwb
    public var id: String { rawValue }
    public var title: String {
        switch self { case .bluetooth: return "Bluetooth"; case .localNetwork: return "Local network"; case .uwb: return "UWB" }
    }
}

/// What one channel honestly reported for the latest sniff.
public enum ChannelOutcome: Equatable, Sendable {
    case notTried
    case scanning
    case found(Int)
    case unavailable(String)     // e.g. "off", "no permission", "no peer", "not on this device"

    public var text: String {
        switch self {
        case .notTried: return "not tried"
        case .scanning: return "scanning"
        case .found(let n): return "\(n) found"
        case .unavailable(let why): return why
        }
    }
    public var isFinished: Bool { if case .scanning = self { return false }; if case .notTried = self { return false }; return true }
}

public struct SniffCandidate: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var channel: SniffChannel
    public var rssi: Int?
    /// True only for stand-ins injected by UI tests; shown with a "test" tag so nobody mistakes them for hardware.
    public var simulated: Bool
    public init(id: String, name: String, channel: SniffChannel, rssi: Int? = nil, simulated: Bool = false) {
        self.id = id; self.name = name; self.channel = channel; self.rssi = rssi; self.simulated = simulated
    }
    public static let unnamed = "Unnamed device"
}

/// The one device Ouija is connected to. Appears only after a successful connect.
public struct PossessedDevice: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var channel: SniffChannel
    public var simulated: Bool
    public var connectedAt: Date
}

public enum SniffPhase: Equatable, Sendable { case idle, sniffing, done }

public struct TestingDevices: Equatable, Sendable {
    public private(set) var phase: SniffPhase = .idle
    public private(set) var channels: [SniffChannel: ChannelOutcome] = Dictionary(uniqueKeysWithValues: SniffChannel.allCases.map { ($0, .notTried) })
    public private(set) var candidates: [SniffCandidate] = []
    public private(set) var possessed: PossessedDevice?
    public private(set) var hailing: String?
    public private(set) var lastError: String?
    public var autoSniff = false

    public init() {}

    /// The testing-devices list: the possessed device, or nothing. Never this iPhone, never a pre-listed device.
    public var listed: [PossessedDevice] { possessed.map { [$0] } ?? [] }

    public mutating func beginSniff() {
        phase = .sniffing
        candidates = []
        lastError = nil
        for c in SniffChannel.allCases { channels[c] = .scanning }
    }

    /// One channel finished (or couldn't run). Candidates are merged; the possessed device is not offered again.
    public mutating func report(_ channel: SniffChannel, found: [SniffCandidate], unavailable: String? = nil) {
        if let why = unavailable, found.isEmpty { channels[channel] = .unavailable(why) }
        else { channels[channel] = .found(found.count) }
        for f in found where !candidates.contains(where: { $0.id == f.id }) && f.id != possessed?.id { candidates.append(f) }
        candidates = Self.sorted(candidates)
        if SniffChannel.allCases.allSatisfy({ channels[$0]?.isFinished == true }) { phase = .done }
    }

    public mutating func finishSniff() {
        for c in SniffChannel.allCases where channels[c] == .scanning { channels[c] = .found(candidates.filter { $0.channel == c }.count) }
        phase = .done
    }

    /// "Bluetooth: 2 found · Local network: 0 found · UWB: no peer"
    public var resultLine: String {
        if phase == .idle { return "Not sniffed yet" }
        return SniffChannel.allCases.map { "\($0.title): \(channels[$0]?.text ?? "not tried")" }.joined(separator: " · ")
    }

    public mutating func hail(_ id: String) -> SniffCandidate? {
        guard possessed == nil, let c = candidates.first(where: { $0.id == id }) else { return nil }
        hailing = id; lastError = nil
        return c
    }

    /// Only a successful connection makes a device "possessed".
    public mutating func connected(_ id: String, now: Date = Date()) {
        guard let c = candidates.first(where: { $0.id == id }) else { hailing = nil; return }
        possessed = PossessedDevice(id: c.id, name: c.name, channel: c.channel, simulated: c.simulated, connectedAt: now)
        candidates.removeAll { $0.id == id }
        hailing = nil
    }

    public mutating func connectFailed(_ id: String, reason: String) {
        hailing = nil
        lastError = "Couldn't connect to \(candidates.first(where: { $0.id == id })?.name ?? "that device"): \(reason)"
    }

    /// Dropping the connection removes the device from the list entirely.
    public mutating func disconnect() { possessed = nil; hailing = nil }

    /// Named devices first, strongest signal first.
    public static func sorted(_ list: [SniffCandidate]) -> [SniffCandidate] {
        list.sorted { a, b in
            let an = a.name != SniffCandidate.unnamed, bn = b.name != SniffCandidate.unnamed
            if an != bn { return an }
            return (a.rssi ?? -999) > (b.rssi ?? -999)
        }
    }

    /// One line for the board header.
    public var headline: String {
        if let p = possessed { return p.name }
        return "No device possessed"
    }
}
