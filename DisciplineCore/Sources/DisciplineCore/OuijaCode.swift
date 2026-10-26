import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// The NCOM Ouija Board unlock code a QR carries. The QR holds either the bare payload or a link
/// `discipline://ouija?code=<payload>` (so the iPhone Camera app opens Discipline with it).
///
/// payload = "NCOM1." + base64url(message) + "." + base64url(Ed25519 signature of message)
/// message = UTF-8 JSON {"v":1,"iss":"NCOM Systems","sub":"Ouija Board","iat":<unix time>,"n":"<nonce>"}
///
/// Only codes signed with NCOM's private key unlock; the app carries just the public key.
public struct OuijaCode: Equatable, Sendable {
    public let message: Data
    public let signature: Data

    public static let prefix = "NCOM1."

    public struct Claims: Codable, Equatable, Sendable {
        public let v: Int
        public let iss: String
        public let sub: String
        public let iat: Int
        public let n: String
    }

    public enum Verdict: Equatable, Sendable {
        case valid(Claims)
        case notACode          // not an NCOM code at all (any other QR)
        case badSignature      // looks like one, but NCOM didn't sign it (or it was changed)
        case wrongContent      // signed, but not an Ouija Board unlock
    }

    /// Pulls the payload out of whatever the QR said: a discipline:// link, a link with ?code=, or the bare payload.
    public static func extract(from text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix(prefix) { return t }
        if let comps = URLComponents(string: t), let code = comps.queryItems?.first(where: { $0.name == "code" })?.value,
           code.hasPrefix(prefix) {
            return code
        }
        return nil
    }

    public static func parse(_ payload: String) -> OuijaCode? {
        guard payload.hasPrefix(prefix) else { return nil }
        let rest = payload.dropFirst(prefix.count).split(separator: ".", omittingEmptySubsequences: false)
        guard rest.count == 2, let m = base64URLDecode(String(rest[0])), let s = base64URLDecode(String(rest[1])),
              !m.isEmpty, s.count == 64 else { return nil }
        return OuijaCode(message: m, signature: s)
    }

    public var claims: Claims? { try? JSONDecoder().decode(Claims.self, from: message) }

    public func isSigned(byAnyOf publicKeys: [Data]) -> Bool {
        #if canImport(CryptoKit)
        for raw in publicKeys {
            if let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw), key.isValidSignature(signature, for: message) {
                return true
            }
        }
        return false
        #else
        return false   // no verifier on this platform: fail closed
        #endif
    }

    /// The whole check: extract, parse, verify the signature, then the claims.
    public static func check(_ text: String, publicKeys: [Data]) -> Verdict {
        guard let payload = extract(from: text) else { return .notACode }
        guard let code = parse(payload) else { return .badSignature }
        guard code.isSigned(byAnyOf: publicKeys) else { return .badSignature }
        guard let c = code.claims, c.v == 1, c.iss == "NCOM Systems", c.sub == "Ouija Board" else { return .wrongContent }
        return .valid(c)
    }

    public static func base64URLDecode(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b.append("=") }
        return Data(base64Encoded: b)
    }
}
