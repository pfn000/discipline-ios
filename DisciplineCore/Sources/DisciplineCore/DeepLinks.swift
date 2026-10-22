import Foundation

/// The companion apps Discipline orchestrates, and the URL hooks each one actually handles.
/// Every scheme and query name below was read from the upstream source on 2026-10-22:
///  - LocalDevVPN  `localdevvpn://enable|disable?scheme=<callback>`  (jkcoxson/LocalDevVPN, LocalDevVPNApp.swift handleURL)
///  - SideStore    `sidestore://install?url=` and `sidestore://source?url=`  (docs.sidestore.io/docs/advanced/url-schema)
///  - LiveContainer `livecontainer://install?url=`, `livecontainer://source?url=`,
///                  `livecontainer://livecontainer-launch?bundle-name=`  (LiveContainer/LiveContainer, LCAppListView.swift,
///                  LCAltStoreSourcesView.swift)
public enum Companion: String, CaseIterable, Codable, Identifiable, Sendable {
    case localDevVPN, sideStore, liveContainer

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .localDevVPN: return "LocalDevVPN"
        case .sideStore: return "SideStore"
        case .liveContainer: return "LiveContainer"
        }
    }

    public var scheme: String {
        switch self {
        case .localDevVPN: return "localdevvpn"
        case .sideStore: return "sidestore"
        case .liveContainer: return "livecontainer"
        }
    }

    /// What the companion does in the combined setup.
    public var role: String {
        switch self {
        case .localDevVPN: return "On-device loopback VPN that lets the phone install and refresh apps on itself."
        case .sideStore: return "Signs and refreshes apps with your Apple ID, on the phone."
        case .liveContainer: return "Runs many apps inside one installed app, past the 3-app limit."
        }
    }

    /// Where to get it from its official source (never a mirror).
    public var officialURL: URL {
        switch self {
        case .localDevVPN: return URL(string: "https://apps.apple.com/app/localdevvpn/id6755608044")!
        case .sideStore: return URL(string: "https://sidestore.io")!
        case .liveContainer: return URL(string: "https://github.com/LiveContainer/LiveContainer")!
        }
    }

    /// Bare URL that just opens the app (also used for "is it installed" via canOpenURL).
    public var openURL: URL { URL(string: "\(scheme)://")! }
}

public enum DeepLinkError: Error, Equatable, Sendable {
    case emptyInput
    case notAWebURL
    case unsupported(String)
}

public enum DeepLinks {
    /// Discipline's own scheme, used as LocalDevVPN's callback so the user lands back here.
    public static let disciplineScheme = "discipline"

    /// Validates user-typed text as an http(s) URL. Adds https:// when the scheme is missing.
    public static func normalizeWebURL(_ text: String) throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DeepLinkError.emptyInput }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let comps = URLComponents(string: withScheme),
              let scheme = comps.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = comps.host, !host.isEmpty, host.contains("."), !host.contains(" "),
              let url = comps.url else { throw DeepLinkError.notAWebURL }
        return url
    }

    private static func encodeValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func make(_ scheme: String, _ host: String, rawPairs: [(String, String)]) -> URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = host
        if !rawPairs.isEmpty {
            c.percentEncodedQuery = rawPairs.map { "\($0.0)=\(encodeValue($0.1))" }.joined(separator: "&")
        }
        return c.url!
    }

    public static func enableVPN(returnTo scheme: String? = disciplineScheme) -> URL {
        make("localdevvpn", "enable", rawPairs: scheme.map { [("scheme", $0)] } ?? [])
    }

    public static func disableVPN(returnTo scheme: String? = disciplineScheme) -> URL {
        make("localdevvpn", "disable", rawPairs: scheme.map { [("scheme", $0)] } ?? [])
    }

    /// Install an .ipa from a web URL with SideStore or LiveContainer.
    public static func install(ipa: URL, with companion: Companion) throws -> URL {
        switch companion {
        case .sideStore: return make("sidestore", "install", rawPairs: [("url", ipa.absoluteString)])
        case .liveContainer: return make("livecontainer", "install", rawPairs: [("url", ipa.absoluteString)])
        case .localDevVPN: throw DeepLinkError.unsupported("LocalDevVPN does not install apps")
        }
    }

    /// Add an AltStore-format source (repo) to SideStore or LiveContainer.
    public static func addSource(_ source: URL, to companion: Companion) throws -> URL {
        switch companion {
        case .sideStore: return make("sidestore", "source", rawPairs: [("url", source.absoluteString)])
        case .liveContainer: return make("livecontainer", "source", rawPairs: [("url", source.absoluteString)])
        case .localDevVPN: throw DeepLinkError.unsupported("LocalDevVPN has no sources")
        }
    }

    /// Launch an app that lives inside LiveContainer by its bundle identifier.
    public static func launchInLiveContainer(bundleID: String) throws -> URL {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw DeepLinkError.emptyInput }
        guard id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }) else {
            throw DeepLinkError.unsupported("not a bundle identifier")
        }
        return make("livecontainer", "livecontainer-launch", rawPairs: [("bundle-name", id)])
    }

    /// Reads back a query value the way the companion apps do (URLComponents.queryItems).
    public static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}
