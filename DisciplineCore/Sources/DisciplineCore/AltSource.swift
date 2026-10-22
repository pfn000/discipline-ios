import Foundation

/// The AltStore/SideStore "source" JSON format (also read by LiveContainer), reduced to the
/// fields Discipline shows. Spec: https://faq.altstore.io/developers/make-a-source
public struct AltSource: Codable, Equatable, Sendable {
    public struct App: Codable, Equatable, Sendable {
        public struct Version: Codable, Equatable, Sendable {
            public let version: String
            public let date: String?
            public let downloadURL: String
            public let size: Int?
            public let minOSVersion: String?
        }
        public let name: String
        public let bundleIdentifier: String
        public let developerName: String?
        public let subtitle: String?
        public let iconURL: String?
        public let versions: [Version]?
        // Legacy single-version fields still used by many sources.
        public let version: String?
        public let downloadURL: String?
        public let minOSVersion: String?

        /// The newest version entry, falling back to the legacy fields.
        public var latest: Version? {
            if let v = versions?.first { return v }
            if let version, let downloadURL {
                return Version(version: version, date: nil, downloadURL: downloadURL, size: nil, minOSVersion: minOSVersion)
            }
            return nil
        }

        /// Whether the newest build claims to run on `os`.
        public func runs(on os: OSVersion) -> Bool {
            guard let min = latest?.minOSVersion, let v = OSVersion(min) else { return true }
            return os >= v
        }
    }

    public let name: String
    public let identifier: String?
    public let apps: [App]

    public static func decode(_ data: Data) throws -> AltSource {
        try JSONDecoder().decode(AltSource.self, from: data)
    }
}
