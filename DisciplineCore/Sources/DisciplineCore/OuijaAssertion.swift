import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// "Sign in with Ouija": Discipline opens `ouija://authorize?client=Discipline&nonce=<hex>&callback=discipline://ouija-auth`,
/// the person approves in Ouija (slides their profile picture), and Ouija opens
/// `discipline://ouija-auth?assertion=OUIJA1.<base64url(json)>.<base64url(Ed25519 signature of the json)>`.
/// json = {"v":1,"client":"Discipline","nonce":"<hex>","name":"<account name>","iat":<unix>,"pk":"<base64url public key>"}
///
/// Discipline pins Ouija's public key the first time it pairs (trust on first use) and refuses any other
/// key afterwards until the pairing is reset.
public struct OuijaAssertion: Codable, Equatable, Sendable {
    public let v: Int
    public let client: String
    public let nonce: String
    public let name: String
    public let iat: Int
    public let pk: String

    public init(client: String, nonce: String, name: String, iat: Int, pk: String) {
        self.v = 1; self.client = client; self.nonce = nonce; self.name = name; self.iat = iat; self.pk = pk
    }

    public static let prefix = "OUIJA1."
    public static let maxAge = 300

    public enum Verdict: Equatable, Sendable {
        case accepted(OuijaAssertion, firstPairing: Bool)
        case malformed, badSignature, wrongNonce, wrongClient, expired, differentKey
    }

    public static func b64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func authorizeURL(client: String, nonce: String, callback: String) -> URL {
        var c = URLComponents()
        c.scheme = "ouija"; c.host = "authorize"
        c.queryItems = [URLQueryItem(name: "client", value: client), URLQueryItem(name: "nonce", value: nonce),
                        URLQueryItem(name: "callback", value: callback)]
        return c.url!
    }

    public struct Request: Equatable, Sendable {
        public let client: String, nonce: String, callback: URL
    }

    /// Reads an incoming ouija://authorize link. The callback must be a custom-scheme link back to the
    /// client app (never http), so an approval can't be sent to a web page.
    public static func parseRequest(_ url: URL) -> Request? {
        guard url.scheme == "ouija", url.host == "authorize",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let client = items.first(where: { $0.name == "client" })?.value, !client.isEmpty,
              let nonce = items.first(where: { $0.name == "nonce" })?.value, nonce.count >= 16,
              let cb = items.first(where: { $0.name == "callback" })?.value, let cbURL = URL(string: cb),
              let scheme = cbURL.scheme?.lowercased(), !["http", "https", "ouija"].contains(scheme) else { return nil }
        return Request(client: client, nonce: nonce, callback: cbURL)
    }

    public static func callbackURL(_ callback: URL, assertion: String) -> URL {
        var c = URLComponents(url: callback, resolvingAgainstBaseURL: false)!
        c.queryItems = (c.queryItems ?? []) + [URLQueryItem(name: "assertion", value: assertion)]
        return c.url!
    }

    #if canImport(CryptoKit)
    /// Ouija's side: sign an approval with its device key.
    public static func sign(_ a: OuijaAssertion, with key: Curve25519.Signing.PrivateKey) throws -> String {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try enc.encode(a)
        let sig = try key.signature(for: json)
        return prefix + b64url(json) + "." + b64url(sig)
    }
    #endif

    /// Discipline's side: the whole check.
    public static func verify(_ text: String, client: String, nonce: String, pinnedKey: String?, now: Date = Date()) -> Verdict {
        guard text.hasPrefix(prefix) else { return .malformed }
        let parts = text.dropFirst(prefix.count).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let json = OuijaCode.base64URLDecode(String(parts[0])),
              let sig = OuijaCode.base64URLDecode(String(parts[1])), sig.count == 64,
              let a = try? JSONDecoder().decode(OuijaAssertion.self, from: json), a.v == 1,
              let pk = OuijaCode.base64URLDecode(a.pk), pk.count == 32 else { return .malformed }
        guard RingLogin.isValidSignature([UInt8](sig), for: [UInt8](json), publicKey: [UInt8](pk)) else { return .badSignature }
        guard a.client == client else { return .wrongClient }
        guard a.nonce == nonce else { return .wrongNonce }
        let age = Int(now.timeIntervalSince1970) - a.iat
        guard age <= maxAge, age >= -60 else { return .expired }
        if let pinned = pinnedKey, pinned != a.pk { return .differentKey }
        return .accepted(a, firstPairing: pinnedKey == nil)
    }
}
