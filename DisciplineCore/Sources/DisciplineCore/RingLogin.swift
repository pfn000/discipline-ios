import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// What the Ouija host's rings carry for a magic sign-in, and the phone's check of it.
///
/// message (89 bytes) = version 0x01 | session (16 bytes: the string the phone handed the computer over
/// Wi-Fi or Bluetooth) | issued-at (UInt32 big-endian, unix seconds) | key id (UInt32 BE, FNV-1a of the
/// signer's 32-byte Ed25519 public key) | Ed25519 signature (64 bytes) of
/// "NCOM-RING-1" + the first 25 bytes.
///
/// An enrolled "key sign" is the computer's public key, written `NCOMKEY1.<base64url of 32 bytes>`.
public struct RingLogin: Equatable, Sendable {
    public static let version: UInt8 = 1
    public static let length = 89
    public static let domain = Array("NCOM-RING-1".utf8)
    public static let maxAge: TimeInterval = 120

    public let session: [UInt8]
    public let issuedAt: UInt32
    public let keyID: UInt32
    public let signature: [UInt8]

    public init(session: [UInt8], issuedAt: UInt32, keyID: UInt32, signature: [UInt8]) {
        self.session = session; self.issuedAt = issuedAt; self.keyID = keyID; self.signature = signature
    }

    public var signedPart: [UInt8] {
        [RingLogin.version] + session + RingLogin.be(issuedAt) + RingLogin.be(keyID)
    }
    public var bytes: [UInt8] { signedPart + signature }

    public static func parse(_ b: [UInt8]) -> RingLogin? {
        guard b.count >= length, b[0] == version else { return nil }
        let s = Array(b[1..<17])
        let iat = b[17..<21].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        let kid = b[21..<25].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return RingLogin(session: s, issuedAt: iat, keyID: kid, signature: Array(b[25..<89]))
    }

    static func be(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }

    public enum Verdict: Equatable, Sendable {
        case accepted(keyID: UInt32)
        case unknownKey          // signed by a key that isn't enrolled on this phone
        case badSignature        // the signature doesn't match (changed, or forged)
        case wrongSession        // a valid code, but for another sign-in (replayed)
        case expired             // older than two minutes (or from the future)
        case unreadable
    }

    /// The whole check: enrolled key, signature, session, time.
    public static func verify(_ message: [UInt8], session: [UInt8], enrolled: [[UInt8]], now: Date = Date()) -> Verdict {
        guard let m = parse(message) else { return .unreadable }
        guard let key = enrolled.first(where: { RingCode.fnv1a($0) == m.keyID }) else { return .unknownKey }
        guard isValidSignature(m.signature, for: domain + m.signedPart, publicKey: key) else { return .badSignature }
        guard m.session == session else { return .wrongSession }
        let age = now.timeIntervalSince1970 - TimeInterval(m.issuedAt)
        guard age <= maxAge, age >= -30 else { return .expired }
        return .accepted(keyID: m.keyID)
    }

    public static func isValidSignature(_ sig: [UInt8], for data: [UInt8], publicKey: [UInt8]) -> Bool {
        #if canImport(CryptoKit)
        guard let k = try? Curve25519.Signing.PublicKey(rawRepresentation: Data(publicKey)) else { return false }
        return k.isValidSignature(Data(sig), for: Data(data))
        #else
        return false   // no verifier on this platform: fail closed
        #endif
    }

    // MARK: Enrolled keys ("key signs")

    public static let keyPrefix = "NCOMKEY1."

    public static func parseKey(_ text: String) -> [UInt8]? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix(keyPrefix), let d = OuijaCode.base64URLDecode(String(t.dropFirst(keyPrefix.count))), d.count == 32 else { return nil }
        return [UInt8](d)
    }

    public static func keyText(_ key: [UInt8]) -> String {
        keyPrefix + Data(key).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    /// Short fingerprint people can compare by eye, e.g. "7F3A-91C2".
    public static func fingerprint(_ key: [UInt8]) -> String {
        let h = RingCode.fnv1a(key)
        return String(format: "%04X-%04X", h >> 16, h & 0xFFFF)
    }

    /// The session string the phone hands the computer: 16 random bytes as 32 hex characters.
    public static func newSession() -> [UInt8] { (0..<16).map { _ in UInt8.random(in: 0...255) } }
    public static func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }
    public static func unhex(_ s: String) -> [UInt8]? {
        let c = Array(s.utf8)
        guard c.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        var i = 0
        while i < c.count {
            guard let v = UInt8(String(decoding: c[i..<i + 2], as: UTF8.self), radix: 16) else { return nil }
            out.append(v); i += 2
        }
        return out
    }
}
