import Foundation

/// The person signed in to Ouija. There is no built-in or default name: the name is what the person
/// typed (or what their NCOM verifier returned for their developer card). Ouija keeps it in the Keychain.
public struct OuijaAccount: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case local          // typed by the person on this iPhone
        case developerCard  // granted by the NCOM verifier after a Magic ID card tap
    }

    public var id: String
    public var name: String
    public var kind: Kind
    public var createdAt: Date

    public init(id: String = UUID().uuidString, name: String, kind: Kind = .local, createdAt: Date = Date()) {
        self.id = id; self.name = name; self.kind = kind; self.createdAt = createdAt
    }

    public enum NameProblem: Error, Equatable, Sendable { case empty, tooLong }
    public static let maxNameLength = 60

    /// Trims the name; refuses an empty or over-long one. Nothing is filled in for the person.
    public static func validName(_ raw: String) -> Result<String, NameProblem> {
        let collapsed = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        if collapsed.isEmpty { return .failure(.empty) }
        if collapsed.count > maxNameLength { return .failure(.tooLong) }
        return .success(collapsed)
    }

    /// Up to two letters from the name, or "" when the name has none.
    public static func initials(of name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap { $0.first(where: { $0.isLetter || $0.isNumber }) }
            .map { String($0).uppercased() }.joined()
    }

    public var initials: String { Self.initials(of: name) }

    public func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
    public static func decode(_ data: Data?) -> OuijaAccount? {
        guard let data, let a = try? JSONDecoder().decode(OuijaAccount.self, from: data),
              case .success = validName(a.name) else { return nil }
        return a
    }
}

/// The phone Ouija is running on, described from what the system reports (never a made-up device).
public struct DeviceIdentity: Equatable, Sendable {
    public let name: String           // UIDevice.current.name ("iPhone" on iOS 16+ without the special entitlement)
    public let model: String          // UIDevice.current.model ("iPhone", "iPad")
    public let systemName: String     // "iOS"
    public let systemVersion: String  // "27.2"
    public let machine: String        // hardware id, e.g. "iPhone18,1"
    public let isSimulator: Bool

    public init(name: String, model: String, systemName: String, systemVersion: String,
                utsMachine: String, environment: [String: String]) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model
        self.systemName = systemName
        self.systemVersion = systemVersion
        if let sim = environment["SIMULATOR_MODEL_IDENTIFIER"], !sim.isEmpty {
            machine = sim; isSimulator = true
        } else {
            machine = utsMachine
            isSimulator = utsMachine == "x86_64" || utsMachine == "arm64" || utsMachine == "i386"
        }
    }

    /// The headline: the device's own name when it reports one beyond its bare model, else the model.
    public var title: String { name.isEmpty ? model : name }

    /// e.g. "iOS 27.2 · iPhone18,1" or "iOS 27.2 · iPhone18,1 · Simulator"
    public var detail: String {
        var parts = ["\(systemName) \(systemVersion)"]
        if !machine.isEmpty && machine != title { parts.append(machine) }
        if isSimulator { parts.append("Simulator") }
        return parts.joined(separator: " · ")
    }
}

/// A device Ouija actually found (Bluetooth LE advertisement or Bonjour service). Nothing is listed
/// unless a scan saw it.
public struct DiscoveredDevice: Codable, Equatable, Hashable, Identifiable, Sendable {
    public enum Via: String, Codable, Sendable { case bluetooth, localNetwork }
    public var id: String           // peripheral UUID or Bonjour service name
    public var name: String
    public var via: Via
    public var rssi: Int?
    public var seenAt: Date

    public init(id: String, name: String, via: Via, rssi: Int? = nil, seenAt: Date = Date()) {
        self.id = id; self.name = name; self.via = via; self.rssi = rssi; self.seenAt = seenAt
    }

    /// Named devices first, strongest signal first; unnamed advertisers are shown as "Unnamed device".
    public static func sorted(_ list: [DiscoveredDevice]) -> [DiscoveredDevice] {
        list.sorted { a, b in
            let an = a.name != DiscoveredDevice.unnamed, bn = b.name != DiscoveredDevice.unnamed
            if an != bn { return an }
            return (a.rssi ?? -999) > (b.rssi ?? -999)
        }
    }
    public static let unnamed = "Unnamed device"

    /// One line for the board header.
    public static func summary(_ list: [DiscoveredDevice], scanned: Bool) -> String {
        if !scanned { return "No device connected · scan" }
        if list.isEmpty { return "No devices found nearby · scan again" }
        let first = sorted(list)[0].name
        return list.count == 1 ? "Found \(first)" : "Found \(first) + \(list.count - 1) more"
    }
}

/// Developer status only ever comes from a Magic ID card tap that NCOM Dev and GlassVault both granted.
/// A typed account (even with the same name) is never a developer: there is no other way in.
public enum DeveloperGate {
    public static func isDeveloper(account: OuijaAccount?, grantedOwner: String?, cardID: String?) -> Bool {
        guard let account, account.kind == .developerCard, let grantedOwner, let cardID, !cardID.isEmpty else { return false }
        return account.name == grantedOwner
    }
}
