import Foundation

/// The NCOM Lab capability map: device features Saidie's NCOM Ouija Board app wants, what each
/// needs, and whether a free Apple ID can sign it. Sources are listed per entry and in
/// RESEARCH.md. "free" claims come from Apple's capability table
/// (https://developer.apple.com/help/account/reference/supported-capabilities-ios/, read 2026-10-22).
public struct DeviceFeature: Codable, Hashable, Identifiable, Sendable {
    public enum Signability: String, Codable, Sendable {
        case freeOK            // ✅ no restricted entitlement: a free Apple ID can sign it
        case paidAccount       // ⚠️ needs an entitlement only the paid program can provision
        case appleApprovalOnly // ❌ Apple must grant it per app (request form), even for paid accounts

        public var badge: String {
            switch self {
            case .freeOK: return "✅ Signable on a free Apple ID"
            case .paidAccount: return "⚠️ Paid developer account needed"
            case .appleApprovalOnly: return "❌ Apple approval only"
            }
        }
    }

    public let id: String
    public let name: String
    public let framework: String
    public let entitlements: [String]          // keys that go in the entitlements plist
    public let infoPlistKeys: [String: String] // usage strings / Info.plist keys with suggested text
    public let backgroundModes: [String]
    public let signability: Signability
    public let notes: String
    public let source: String

    public static let catalog: [DeviceFeature] = [
        DeviceFeature(id: "uwb", name: "UWB / Nearby Interaction", framework: "NearbyInteraction",
                      entitlements: [],
                      infoPlistKeys: ["NSNearbyInteractionUsageDescription": "Ouija Board uses Ultra Wideband to find and range your NCOM devices."],
                      backgroundModes: ["nearby-interaction"],
                      signability: .freeOK,
                      notes: "iPhone 11+ (U1/U2 chip). Phone-to-phone and third-party UWB accessories (accessory must implement Apple's Nearby Interaction accessory protocol). No restricted entitlement; background ranging uses a background mode, which free accounts can sign.",
                      source: "https://developer.apple.com/documentation/nearbyinteraction"),
        DeviceFeature(id: "ble", name: "Bluetooth LE", framework: "CoreBluetooth",
                      entitlements: [],
                      infoPlistKeys: ["NSBluetoothAlwaysUsageDescription": "Ouija Board talks to NCOM prototypes over Bluetooth."],
                      backgroundModes: ["bluetooth-central"],
                      signability: .freeOK,
                      notes: "No entitlement. Background modes are allowed on free accounts.",
                      source: "https://developer.apple.com/documentation/corebluetooth"),
        DeviceFeature(id: "nfc", name: "NFC tag reading", framework: "CoreNFC",
                      entitlements: ["com.apple.developer.nfc.readersession.formats"],
                      infoPlistKeys: ["NFCReaderUsageDescription": "Ouija Board reads NFC tags on NCOM devices."],
                      backgroundModes: [],
                      signability: .paidAccount,
                      notes: "Apple's table lists 'Near Field Communication (NFC) Tag Reading' for the paid program only.",
                      source: "https://developer.apple.com/help/account/reference/supported-capabilities-ios/"),
        DeviceFeature(id: "wifiaware", name: "Wi-Fi Aware (peer-to-peer Wi-Fi)", framework: "WiFiAware",
                      entitlements: ["com.apple.developer.wifi-aware"],
                      infoPlistKeys: [:],
                      backgroundModes: [],
                      signability: .paidAccount,
                      notes: "Needs the com.apple.developer.wifi-aware entitlement (iOS 26+). It is not in Apple's free-account column; treat as paid. Unverified on a device.",
                      source: "https://developer.apple.com/documentation/wifiaware/adopting-wi-fi-aware"),
        DeviceFeature(id: "localnet", name: "Local network / Bonjour", framework: "Network",
                      entitlements: [],
                      infoPlistKeys: ["NSLocalNetworkUsageDescription": "Ouija Board finds NCOM devices on your Wi-Fi.",
                                      "NSBonjourServices": "_ncom._tcp"],
                      backgroundModes: [],
                      signability: .freeOK,
                      notes: "Unicast and Bonjour need only the usage string. Raw multicast/broadcast needs com.apple.developer.networking.multicast, which Apple grants per app on request.",
                      source: "https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast"),
        DeviceFeature(id: "multicast", name: "Multicast / broadcast UDP", framework: "Network",
                      entitlements: ["com.apple.developer.networking.multicast"],
                      infoPlistKeys: ["NSLocalNetworkUsageDescription": "Ouija Board discovers NCOM devices on your Wi-Fi."],
                      backgroundModes: [],
                      signability: .appleApprovalOnly,
                      notes: "Apple: 'This entitlement requires permission from Apple before you can use it in your app.'",
                      source: "https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast"),
        DeviceFeature(id: "wifiinfo", name: "Wi-Fi network name (SSID)", framework: "NetworkExtension (NEHotspotNetwork)",
                      entitlements: ["com.apple.developer.networking.wifi-info"],
                      infoPlistKeys: ["NSLocationWhenInUseUsageDescription": "Ouija Board reads the Wi-Fi name to pair with NCOM devices."],
                      backgroundModes: [],
                      signability: .paidAccount,
                      notes: "'Access WiFi information' is paid-program only in Apple's table.",
                      source: "https://developer.apple.com/help/account/reference/supported-capabilities-ios/"),
        DeviceFeature(id: "proximity", name: "Proximity sensor", framework: "UIKit (UIDevice)",
                      entitlements: [], infoPlistKeys: [:], backgroundModes: [],
                      signability: .freeOK,
                      notes: "UIDevice.isProximityMonitoringEnabled; no entitlement or usage string.",
                      source: "https://developer.apple.com/documentation/uikit/uidevice/isproximitymonitoringenabled"),
        DeviceFeature(id: "motion", name: "Motion sensors", framework: "CoreMotion",
                      entitlements: [],
                      infoPlistKeys: ["NSMotionUsageDescription": "Ouija Board uses motion to detect how you move the planchette."],
                      backgroundModes: [],
                      signability: .freeOK,
                      notes: "Accelerometer/gyro need nothing; activity and pedometer data need the motion usage string.",
                      source: "https://developer.apple.com/documentation/coremotion"),
        DeviceFeature(id: "eaccessory", name: "External Accessory (MFi)", framework: "ExternalAccessory",
                      entitlements: [],
                      infoPlistKeys: ["UISupportedExternalAccessoryProtocols": "com.ncom.protocol"],
                      backgroundModes: ["external-accessory"],
                      signability: .freeOK,
                      notes: "The app side needs no entitlement, but the hardware must be an MFi-certified accessory (Apple's MFi program) to talk to it.",
                      source: "https://developer.apple.com/documentation/externalaccessory"),
        DeviceFeature(id: "multipeer", name: "Multipeer Connectivity", framework: "MultipeerConnectivity",
                      entitlements: [],
                      infoPlistKeys: ["NSLocalNetworkUsageDescription": "Ouija Board connects to nearby phones.",
                                      "NSBonjourServices": "_ncom-ouija._tcp"],
                      backgroundModes: [],
                      signability: .freeOK,
                      notes: "Needs the local network usage string and its Bonjour service types.",
                      source: "https://developer.apple.com/documentation/multipeerconnectivity"),
    ]

    public static func lookup(entitlement key: String) -> DeviceFeature? {
        catalog.first { $0.entitlements.contains(key) }
    }
}

/// A signing preset: the entitlements + Info.plist keys an app like Ouija Board needs, and
/// whether a given account can sign them. Exported as JSON and as an entitlements plist.
public struct SigningPreset: Codable, Equatable, Sendable {
    public var name: String
    public var bundleID: String
    public var features: [String]   // DeviceFeature ids

    public init(name: String, bundleID: String, features: [String]) {
        self.name = name; self.bundleID = bundleID; self.features = features
    }

    public static let ouijaBoard = SigningPreset(name: "NCOM Ouija Board", bundleID: "com.ncom.ouijaboard",
                                                 features: ["uwb", "ble", "nfc", "localnet", "proximity", "motion", "multipeer", "eaccessory"])

    public var resolved: [DeviceFeature] { features.compactMap { id in DeviceFeature.catalog.first { $0.id == id } } }

    /// Entitlements a signer must put in the profile (restricted ones only; plain capabilities need none).
    public func entitlements(for tier: AccountTier) -> [String: Any] {
        var e: [String: Any] = [:]
        for f in resolved where f.signability != .appleApprovalOnly && (tier == .paid || f.signability == .freeOK) {
            for key in f.entitlements {
                if key == "com.apple.developer.nfc.readersession.formats" { e[key] = ["TAG"] }
                else if key == "com.apple.developer.wifi-aware" { e[key] = ["Publish", "Subscribe"] }
                else { e[key] = true }
            }
        }
        return e
    }

    public func infoPlistAdditions() -> [String: Any] {
        var d: [String: Any] = [:]
        var modes = Set<String>()
        for f in resolved {
            for (k, v) in f.infoPlistKeys {
                if k == "NSBonjourServices" || k == "UISupportedExternalAccessoryProtocols" {
                    var arr = (d[k] as? [String]) ?? []
                    if !arr.contains(v) { arr.append(v) }
                    d[k] = arr
                } else if d[k] == nil { d[k] = v }
            }
            modes.formUnion(f.backgroundModes)
        }
        if !modes.isEmpty { d["UIBackgroundModes"] = modes.sorted() }
        return d
    }

    /// Features this account cannot sign, with the reason badge.
    public func blocked(for tier: AccountTier) -> [DeviceFeature] {
        resolved.filter { f in
            switch f.signability {
            case .freeOK: return false
            case .paidAccount: return tier == .free
            case .appleApprovalOnly: return true
            }
        }
    }

    public func entitlementsPlistXML(for tier: AccountTier) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: entitlements(for: tier), format: .xml, options: 0)
    }

    public func json() throws -> Data {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(self)
    }
}
