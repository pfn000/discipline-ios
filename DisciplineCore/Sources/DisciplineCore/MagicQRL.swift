import Foundation

/// QRL, the "magic QR" (Saidie, Nov 1 2026 10:27 AM): NCOM Dev and GlassVault each sign the same challenge for a
/// card tap, and the magic-ring dance is drawn from BOTH signatures together. The rings only dance when both halves
/// are there and both check out; the dance itself is then a picture of the two systems agreeing.
public enum QRLParty: String, Codable, CaseIterable, Sendable { case ncomDev, glassVault
    public var name: String { self == .ncomDev ? "NCOM Dev" : "GlassVault" }
}

public struct QRLHalf: Codable, Equatable, Sendable {
    public let party: QRLParty
    public let challenge: String
    public let signature: String
    public init(party: QRLParty, challenge: String, signature: String) { self.party = party; self.challenge = challenge; self.signature = signature }
}

/// What the rings draw: four ring speeds and a 16-byte payload for the ring cells.
public struct QRLDance: Equatable, Sendable {
    public let speeds: [Double]
    public let payload: [UInt8]
    /// The two signatures this dance was drawn from (they are public values); the magic sphere hashes both.
    public let ncomDevSignature: String
    public let glassVaultSignature: String
    public var bits: [[Bool]] { RingCode.bits(of: RingCode.frames(for: payload)[0]) }
}

public enum QRLVerdict: Equatable, Sendable {
    case agree(QRLDance)
    case missing([QRLParty])
    case mismatch([QRLParty])
    public var agrees: Bool { if case .agree = self { return true }; return false }
}

public enum MagicQRL {
    public static func challenge(cardID: String, rotationID: String, nextDigest: String) -> String {
        "NCOM-QRL1|\(cardID)|\(rotationID)|\(nextDigest)"
    }

    /// `verify(party, challenge, signature)` checks a half against that party's own public key.
    public static func combine(challenge: String, ncomDev: QRLHalf?, glassVault: QRLHalf?,
                               verify: (QRLParty, String, String) -> Bool) -> QRLVerdict {
        let halves: [(QRLParty, QRLHalf?)] = [(.ncomDev, ncomDev), (.glassVault, glassVault)]
        let missing = halves.filter { $0.1 == nil }.map(\.0)
        if !missing.isEmpty { return .missing(missing) }
        let bad = halves.filter { p, h in
            guard let h else { return true }
            return h.party != p || h.challenge != challenge || !verify(p, challenge, h.signature)
        }.map(\.0)
        if !bad.isEmpty { return .mismatch(bad) }
        return .agree(dance(ncomDev!.signature, glassVault!.signature))
    }

    /// Deterministic: the same two signatures always draw the same dance; change either and it changes.
    public static func dance(_ a: String, _ b: String) -> QRLDance {
        var bytes: [UInt8] = []
        var seed = Array("\(a)|\(b)".utf8)
        while bytes.count < 20 {
            let h = RingCode.fnv1a(seed)
            bytes += [UInt8(h & 0xff), UInt8((h >> 8) & 0xff), UInt8((h >> 16) & 0xff), UInt8(h >> 24)]
            seed = Array(String(h, radix: 16).utf8) + seed
        }
        let speeds = (0..<4).map { i -> Double in
            let mag = 0.05 + Double(bytes[16 + i]) / 255 * 0.08
            return i % 2 == 0 ? mag : -mag
        }
        return QRLDance(speeds: speeds, payload: Array(bytes.prefix(16)), ncomDevSignature: a, glassVaultSignature: b)
    }
}

/// One entry in the security log both sides keep when the handshake says no.
public struct SecurityReport: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(at.timeIntervalSince1970)|\(kind)" }
    public let at: Date
    public let cardID: String?
    public let kind: String        // "qrl-missing", "qrl-mismatch", or the failed step's name
    public let detail: String
    public var reportedToIT = false
    public init(at: Date, cardID: String?, kind: String, detail: String) { self.at = at; self.cardID = cardID; self.kind = kind; self.detail = detail }
}
