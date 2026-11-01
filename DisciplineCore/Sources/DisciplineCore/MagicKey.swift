import Foundation

/// NCOM "Magic ID card": a developer-only Ouija sign-in with a rolling one-time token on an NFC card.
///
/// The card holds one NDEF record whose payload is `ncom-card-<20 base32 letters>` (30 bytes, 100 random bits).
/// A tap goes:  read token -> verifier.redeem(token, device) -> verifier burns that token and hands back a new one
/// -> Ouija writes the new token onto the card -> verifier.confirm(rotation) -> developer session granted.
/// Every token works once ("suicide" token). The card is also bound to the phones registered for it
/// (their signing keys): the same card tapped on any other phone is refused, its token burned, and the card
/// locked until a registered phone taps it again. A copy made before a tap is therefore worth at most nothing on
/// another phone, and on a registered phone the stale copy shows up as "out of sync" and locks the card.
///
/// `MagicKeyLedger` is the verifier's rules. The real verifier runs on NCOM's own server (code ready for her
/// Vercel project in docs, NOT on Tab's machines); this Swift copy is the simulator mock and the unit tests'
/// reference, and the server must behave exactly like it.
public enum MagicCardToken {
    public static let prefix = "ncom-card-"
    public static let bodyLength = 20
    static let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")

    public static func isValid(_ s: String) -> Bool {
        guard s.hasPrefix(prefix) else { return false }
        let body = s.dropFirst(prefix.count)
        return body.count == bodyLength && body.allSatisfy { alphabet.contains($0) }
    }

    public static func generate<R: RandomNumberGenerator>(using rng: inout R) -> String {
        prefix + String((0..<bodyLength).map { _ in alphabet[Int(rng.next(upperBound: UInt32(alphabet.count)))] })
    }
    public static func generate() -> String { var g = SystemRandomNumberGenerator(); return generate(using: &g) }

    /// The NDEF record payload bytes for a token (plain UTF-8, as on Saidie's card today).
    public static func payload(_ token: String) -> [UInt8] { Array(token.utf8) }

    /// The token inside a record payload, if it is one. Tolerates a trailing NUL/newline some writer apps add.
    public static func token(fromPayload bytes: [UInt8]) -> String? {
        guard let s = String(bytes: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\0"))),
              isValid(s) else { return nil }
        return s
    }
}

public struct MagicKeyLedger: Sendable {
    public struct Card: Codable, Equatable, Sendable {
        public var cardID: String
        public var ownerName: String
        public var current: String            // digest of the token the card should hold now
        public var pending: Pending?          // a rotation handed out, not yet confirmed
        public var burned: [String]           // digests of every token already used
        public var devices: [String]          // registered phones (their public keys)
        public var lock: Lock?
    }
    public struct Pending: Codable, Equatable, Sendable {
        public var rotationID: String
        public var digest: String
        public var device: String
        public var issuedAt: Date
    }
    public struct Lock: Codable, Equatable, Sendable {
        public enum Reason: String, Codable, Sendable { case otherPhone, outOfSync, revoked }
        public var reason: Reason
        public var at: Date
        public var tokenDigest: String        // the token that triggered it
    }

    public enum Redeem: Equatable, Sendable {
        case rotate(rotationID: String, nextToken: String)
        case unknownCard                       // not an NCOM card this verifier issued
        case otherPhone                        // valid card, unregistered phone: token burned, card locked
        case outOfSync                         // a used token came back from a registered phone (or the app said no): card locked
        case locked(Lock.Reason)               // card already locked; needs a registered phone (otherPhone) or NCOM reset (outOfSync)
        case malformed
    }
    public enum Confirm: Equatable, Sendable {
        case granted(ownerName: String, cardID: String)
        case noSuchRotation, wrongPhone, expired
    }

    public static let rotationLifetime: TimeInterval = 120

    public private(set) var cards: [Card] = []
    public let digest: @Sendable (String) -> String

    /// `digest` turns a token into what is stored (the server uses SHA-256; tests may use any one-way function).
    public init(digest: @escaping @Sendable (String) -> String) { self.digest = digest }

    public mutating func enroll(cardID: String, ownerName: String, token: String, device: String) {
        cards.removeAll { $0.cardID == cardID }
        cards.append(Card(cardID: cardID, ownerName: ownerName, current: digest(token), pending: nil, burned: [], devices: [device], lock: nil))
    }

    /// Recovery codes (digests) per card: each works once, to move the card to a new phone after a reinstall or a lost phone.
    public private(set) var recovery: [String: String] = [:]
    public mutating func setRecoveryCode(cardID: String, code: String) { recovery[cardID] = digest("recovery|" + code) }

    /// Moves the card to `newDevice` with a one-time recovery code and gives back the key to write on the card.
    public mutating func recover<R: RandomNumberGenerator>(cardID: String, code: String, newDevice: String, rng: inout R) -> String? {
        guard let i = cards.firstIndex(where: { $0.cardID == cardID }), let want = recovery[cardID], want == digest("recovery|" + code) else { return nil }
        recovery[cardID] = nil                      // single use
        let fresh = MagicCardToken.generate(using: &rng)
        cards[i].burned.append(cards[i].current)
        if let p = cards[i].pending { cards[i].burned.append(p.digest) }
        cards[i].current = digest(fresh); cards[i].pending = nil; cards[i].lock = nil
        cards[i].devices = [newDevice]
        return fresh
    }

    public mutating func registerPhone(cardID: String, device: String) {
        guard let i = cards.firstIndex(where: { $0.cardID == cardID }), !cards[i].devices.contains(device) else { return }
        cards[i].devices.append(device)
    }

    /// NCOM-side reset after an out-of-sync lock (a person decides; the app can't).
    public mutating func reset(cardID: String, token: String) {
        guard let i = cards.firstIndex(where: { $0.cardID == cardID }) else { return }
        cards[i].burned.append(cards[i].current)
        cards[i].current = digest(token); cards[i].pending = nil; cards[i].lock = nil
    }

    public mutating func redeem<R: RandomNumberGenerator>(token: String, device: String, now: Date = Date(), rng: inout R) -> Redeem {
        guard MagicCardToken.isValid(token) else { return .malformed }
        let d = digest(token)
        guard let i = cards.firstIndex(where: { $0.current == d || $0.pending?.digest == d || $0.burned.contains(d) || $0.lock?.tokenDigest == d })
        else { return .unknownCard }
        var card = cards[i]
        defer { cards[i] = card }
        let registered = card.devices.contains(device)

        if !registered {
            // A live NCOM key on a phone that isn't registered: burn it and lock the card. An already-used key
            // (an old copy) is refused without locking, so an old copy can't be used to lock the owner out.
            let live = card.current == d || card.pending?.digest == d
            if live {
                card.burned.append(d)
                if let pd = card.pending?.digest, pd != d { card.burned.append(pd) }
                card.pending = nil      // an owner's rotation in flight at the same moment dies too
                if card.lock == nil { card.lock = Lock(reason: .otherPhone, at: now, tokenDigest: d) }
            }
            return .otherPhone
        }
        if let lock = card.lock {
            // The owner's phone with the card that was on the stranger's phone: let it rotate back in.
            if lock.reason == .otherPhone && lock.tokenDigest == d { return issue(&card, device: device, now: now, rng: &rng) }
            return .locked(lock.reason)
        }
        if card.current == d { return issue(&card, device: device, now: now, rng: &rng) }
        if card.pending?.digest == d {
            // The new token reached the card but the confirm never arrived: it counts as current.
            card.burned.append(card.current); card.current = d; card.pending = nil
            return issue(&card, device: device, now: now, rng: &rng)
        }
        // A used token from a registered phone: the card (or a copy) is behind. Lock it.
        card.lock = Lock(reason: .outOfSync, at: now, tokenDigest: d)
        card.pending = nil
        return .outOfSync
    }

    private func issue<R: RandomNumberGenerator>(_ card: inout Card, device: String, now: Date, rng: inout R) -> Redeem {
        let next = MagicCardToken.generate(using: &rng)
        let rid = MagicCardToken.generate(using: &rng).dropFirst(MagicCardToken.prefix.count)
        card.pending = Pending(rotationID: String(rid), digest: digest(next), device: device, issuedAt: now)
        return .rotate(rotationID: String(rid), nextToken: next)
    }

    /// Ouija calls this after writing the new token onto the card.
    public mutating func confirm(rotationID: String, device: String, now: Date = Date()) -> Confirm {
        guard let i = cards.firstIndex(where: { $0.pending?.rotationID == rotationID }), let p = cards[i].pending else { return .noSuchRotation }
        guard p.device == device else { return .wrongPhone }
        guard now.timeIntervalSince(p.issuedAt) <= Self.rotationLifetime else {
            // Too late: the card may hold either token; both stay redeemable once (pending counts as current).
            return .expired
        }
        cards[i].burned.append(cards[i].current)
        cards[i].current = p.digest
        cards[i].pending = nil
        cards[i].lock = nil
        return .granted(ownerName: cards[i].ownerName, cardID: cards[i].cardID)
    }

    public func card(_ id: String) -> Card? { cards.first { $0.cardID == id } }

    /// Which card a handed-out rotation belongs to (the app needs it for its own check, step 4).
    public func cardID(forRotation rid: String) -> String? { cards.first { $0.pending?.rotationID == rid }?.cardID }

    /// Lock a card outright (a party said no without a rotation in hand).
    public mutating func lock(cardID: String, reason: Lock.Reason, tokenDigest: String, now: Date = Date()) {
        guard let i = cards.firstIndex(where: { $0.cardID == cardID }) else { return }
        if cards[i].current == tokenDigest { cards[i].burned.append(tokenDigest) }
        cards[i].pending = nil
        if cards[i].lock == nil || reason != .otherPhone { cards[i].lock = Lock(reason: reason, at: now, tokenDigest: tokenDigest) }
    }

    /// Any party said no after GlassVault handed out a rotation: kill the presented key AND the new one, lock the card.
    public mutating func reject(rotationID: String, reason: Lock.Reason = .outOfSync, now: Date = Date()) {
        guard let i = cards.firstIndex(where: { $0.pending?.rotationID == rotationID }), let p = cards[i].pending else { return }
        cards[i].burned.append(cards[i].current)
        cards[i].burned.append(p.digest)
        cards[i].pending = nil
        cards[i].lock = Lock(reason: reason, at: now, tokenDigest: cards[i].current)
    }
}

/// NCOM Dev's card directory: "do I know this card?" Kept apart from GlassVault on purpose (two parties must agree).
public struct NCOMDevDirectory: Codable, Equatable, Sendable {
    public var owners: [String: String] = [:]   // cardID -> owner name
    public var devices: [String: [String]] = [:] // cardID -> phones NCOM Dev has on file (its own copy)
    public var revoked: [String] = []
    public init() {}
    public mutating func issue(cardID: String, owner: String, device: String) {
        owners[cardID] = owner; devices[cardID] = [device]
    }
    public mutating func revoke(cardID: String) { revoked.append(cardID) }
    public func knows(_ cardID: String) -> Bool { owners[cardID] != nil && !revoked.contains(cardID) }
}

/// OuijaBoard's own memory of the card, on the phone: which card, the digest of the key it last wrote, and its device id.
public struct OuijaKeyRecord: Codable, Equatable, Sendable {
    public var cardID: String
    public var expectedDigest: String
    public var deviceID: String
    public init(cardID: String, expectedDigest: String, deviceID: String) {
        self.cardID = cardID; self.expectedDigest = expectedDigest; self.deviceID = deviceID
    }
}

/// Saidie's 8 steps (Nov 1 2026, 10:24 AM): three parties each give a thumbs up, any single no burns the key and locks the card.
///  1 ID tapped (OuijaBoard reads the key)                 5 GlassVault: yes/no, the key matches the device credentials
///  2 NCOM Dev: do I know this card?                        6 NCOM Dev: yes, kill this key, make a new one
///  3 GlassVault: is this key matched to the stored device? 7 GlassVault: kills the key, generates the new one
///  4 OuijaBoard: does it match the card + device id I hold? 8 OuijaBoard: written, confirmed, authenticated
public enum MagicStep: Int, CaseIterable, Codable, Sendable {
    case tapped = 1, ncomDevKnowsCard, glassVaultDeviceMatch, ouijaLocalMatch, glassVaultVerdict, ncomDevApproves, glassVaultRotates, ouijaAuthenticates

    public var title: String {
        switch self {
        case .tapped: return "ID card tapped"
        case .ncomDevKnowsCard: return "NCOM Dev knows this card"
        case .glassVaultDeviceMatch: return "GlassVault: card matches this iPhone's key"
        case .ouijaLocalMatch: return "OuijaBoard: card matches what this iPhone wrote last"
        case .glassVaultVerdict: return "GlassVault says yes"
        case .ncomDevApproves: return "NCOM Dev approves: kill this key"
        case .glassVaultRotates: return "GlassVault burns it and issues a new OuijaKey"
        case .ouijaAuthenticates: return "OuijaBoard writes the new key and signs you in"
        }
    }
}

public struct MagicStepResult: Equatable, Sendable {
    public let step: MagicStep
    public let ok: Bool
    public let words: String
}

/// The whole handshake against in-memory parties. The simulator mock and the unit tests run exactly this;
/// the real NCOM Dev + GlassVault run the same rules on NCOM's server.
///
/// One deliberate order change from her list: OuijaBoard writes the new key onto the card BEFORE GlassVault
/// finalises the burn (step 7). If the write fails, nothing was burned and the card's key still works once,
/// so a shaky NFC tap can't lock her out. Every "no" that means fraud (steps 2-6, 8) burns and locks.
public struct MagicHandshake: Sendable {
    public var directory: NCOMDevDirectory
    public var vault: MagicKeyLedger
    /// When set, every tap must carry this iPhone's signature over `MagicHandshake.message(...)` (the server always sets it).
    public var signatureCheck: (@Sendable (_ devicePK: String, _ message: String, _ signature: String) -> Bool)?
    public static let maxClockSkew: TimeInterval = 120
    /// Either system being unreachable is a "no" (the handshake never falls open).
    public var ncomDevReachable = true
    public var glassVaultReachable = true
    /// Failed taps per phone (unknown card, bad key, bad signature) for the brute-force lockout.
    public private(set) var failures: [String: [Date]] = [:]
    public static let maxFailures = 5
    public static let lockoutTime: TimeInterval = 900

    /// Each party's half of the magic QR. On the server these are real signatures with each party's own key.
    public var ncomDevSign: @Sendable (String) -> String? = { "ncomdev-signed(\($0))" }
    public var glassVaultSign: @Sendable (String) -> String? = { "glassvault-signed(\($0))" }
    public var qrlVerify: @Sendable (QRLParty, String, String) -> Bool = { party, challenge, sig in
        sig == (party == .ncomDev ? "ncomdev-signed(\(challenge))" : "glassvault-signed(\(challenge))")
    }

    public init(directory: NCOMDevDirectory, vault: MagicKeyLedger) { self.directory = directory; self.vault = vault }

    public static func message(token: String, ts: Int) -> String { "NCOM-MAGIC1|redeem|\(token)|\(ts)" }

    /// Locked out when this phone failed `maxFailures` times in the last `lockoutTime` (15 min).
    public func lockedOut(_ device: String, now: Date) -> Bool {
        (failures[device] ?? []).filter { now.timeIntervalSince($0) < Self.lockoutTime }.count >= Self.maxFailures
    }
    mutating func fail(_ device: String, _ now: Date) { failures[device, default: []].append(now) }

    /// A registered phone approves adding another phone (both NCOM Dev and GlassVault record it).
    @discardableResult
    public mutating func approvePhone(cardID: String, approver: String, newDevice: String) -> Bool {
        guard vault.card(cardID)?.devices.contains(approver) == true, directory.devices[cardID]?.contains(approver) == true else { return false }
        vault.registerPhone(cardID: cardID, device: newDevice)
        directory.devices[cardID, default: []].append(newDevice)
        return true
    }

    /// Lost phone / reinstalled app: the one-time recovery code moves the card to the new phone. Returns the key to write.
    public mutating func recover<R: RandomNumberGenerator>(cardID: String, code: String, newDevice: String, rng: inout R) -> String? {
        guard directory.knows(cardID), let fresh = vault.recover(cardID: cardID, code: code, newDevice: newDevice, rng: &rng) else { return nil }
        directory.devices[cardID] = [newDevice]
        return fresh
    }

    public struct Outcome: Equatable, Sendable {
        public var steps: [MagicStepResult] = []
        public var grantedOwner: String?
        public var newCardToken: String?          // what OuijaBoard writes onto the card (nil = nothing written)
        public var newRecord: OuijaKeyRecord?     // what OuijaBoard keeps afterwards
        public var cardLocked = false
        public var qrl: QRLVerdict?               // the magic QR: both halves, or which one was missing / wrong
        public var report: SecurityReport?        // written whenever the answer is a fraud-type no
        /// The developer's choice after a QRL failure: replace the card/key, or report it to IT security.
        public var needsChoice: Bool { if let q = qrl { return !q.agrees }; return false }
        public var failedStep: MagicStep? { steps.first { !$0.ok }?.step }
    }

    /// `writeSucceeds` is the card write (false = the NFC write failed).
    public mutating func tap<R: RandomNumberGenerator>(cardToken: String?, device: String, local: OuijaKeyRecord?,
                                                       writeSucceeds: Bool = true, now: Date = Date(),
                                                       signature: String? = nil, ts: Int? = nil, rng: inout R) -> Outcome {
        var o = run(cardToken: cardToken, device: device, local: local, writeSucceeds: writeSucceeds, now: now, signature: signature, ts: ts, rng: &rng)
        if o.report == nil, o.cardLocked, let f = o.steps.first(where: { !$0.ok }) {
            o.report = SecurityReport(at: now, cardID: nil, kind: "step-\(f.step.rawValue)", detail: f.words)
        }
        return o
    }

    private mutating func run<R: RandomNumberGenerator>(cardToken: String?, device: String, local: OuijaKeyRecord?,
                                                        writeSucceeds: Bool, now: Date,
                                                        signature: String?, ts: Int?, rng: inout R) -> Outcome {
        var o = Outcome()
        func add(_ s: MagicStep, _ ok: Bool, _ w: String) { o.steps.append(MagicStepResult(step: s, ok: ok, words: w)) }

        if lockedOut(device, now: now) {
            add(.tapped, false, "Too many failed tries from this iPhone. Wait 15 minutes."); return o
        }
        // 1
        guard let token = cardToken, MagicCardToken.isValid(token) else {
            fail(device, now)
            add(.tapped, false, "No NCOM key on this card."); return o
        }
        add(.tapped, true, "Read the card's key.")

        // 2: NCOM Dev: "do I know this card?"
        guard ncomDevReachable else { add(.ncomDevKnowsCard, false, "Couldn't reach NCOM Dev. Not signed in; nothing changed."); return o }
        let d = vault.digest(token)
        let cardID = vault.cards.first { $0.current == d || $0.pending?.digest == d || $0.burned.contains(d) || $0.lock?.tokenDigest == d }?.cardID
        guard let cardID, directory.knows(cardID) else {
            if cardID == nil { fail(device, now) }
            add(.ncomDevKnowsCard, false, cardID == nil ? "NCOM Dev doesn't know this card." : "NCOM Dev has revoked this card.")
            if let cardID { vault.lock(cardID: cardID, reason: .revoked, tokenDigest: d, now: now); o.cardLocked = true }
            return o
        }
        add(.ncomDevKnowsCard, true, "NCOM Dev knows card \(cardID).")

        // 3: GlassVault: "is this key matched to the device key I stored?" (signed by that key, recently)
        guard glassVaultReachable else { add(.glassVaultDeviceMatch, false, "Couldn't reach GlassVault. Not signed in; nothing changed."); return o }
        if let check = signatureCheck {
            guard let signature, let ts, abs(now.timeIntervalSince1970 - Double(ts)) <= Self.maxClockSkew,
                  check(device, Self.message(token: token, ts: ts), signature) else {
                fail(device, now)
                add(.glassVaultDeviceMatch, false, "The request wasn't signed by this iPhone's key just now. Refused; the card wasn't touched.")
                return o
            }
        }
        let r = vault.redeem(token: token, device: device, now: now, rng: &rng)
        if r == .otherPhone {
            add(.glassVaultDeviceMatch, false, MagicKeyWords.text(r)); o.cardLocked = true; return o
        }
        add(.glassVaultDeviceMatch, true, "The card is registered to this iPhone's key.")

        // 4: OuijaBoard: "can I verify this key and the device ID I have?" (nothing stored yet on a first tap)
        let localOK: Bool = {
            guard let local else { return true }
            return local.cardID == cardID && local.deviceID == device && local.expectedDigest == d
        }()
        guard localOK else {
            if case let .rotate(rid, _) = r { vault.reject(rotationID: rid, now: now) }
            else { vault.lock(cardID: cardID, reason: .outOfSync, tokenDigest: d, now: now) }
            add(.ouijaLocalMatch, false, "This card doesn't match what this iPhone wrote on it last. Key burned, card locked.")
            o.cardLocked = true
            return o
        }
        add(.ouijaLocalMatch, true, local == nil ? "First tap on this iPhone." : "Matches what this iPhone wrote last.")

        // 5: GlassVault: yes / no
        guard case let .rotate(rid, next) = r else {
            add(.glassVaultVerdict, false, MagicKeyWords.text(r)); o.cardLocked = true; return o
        }
        add(.glassVaultVerdict, true, "GlassVault: yes, the key matches the device credentials.")

        // 6: NCOM Dev: "my device ID and key string match too; kill this key"
        guard directory.devices[cardID]?.contains(device) == true else {
            vault.reject(rotationID: rid, now: now)
            add(.ncomDevApproves, false, "NCOM Dev doesn't have this iPhone on file for the card. Key burned, card locked.")
            o.cardLocked = true
            return o
        }
        add(.ncomDevApproves, true, "NCOM Dev: yes. Kill this key and make a new one.")

        // 7: GlassVault burns the key and issues the new one (after the card holds it).
        guard writeSucceeds else {
            add(.glassVaultRotates, false, "The new key couldn't be written onto the card. Nothing was burned; tap again.")
            return o
        }
        o.newCardToken = next
        let c = vault.confirm(rotationID: rid, device: device, now: now)
        guard case let .granted(owner, cid) = c else {
            add(.glassVaultRotates, false, c == .expired ? "Took too long. Tap again." : "GlassVault didn't confirm. Tap again.")
            return o
        }
        add(.glassVaultRotates, true, "Old key burned. New OuijaKey issued and on the card.")

        // 8a: the magic QR. Both halves must be there and check out, or the rings don't dance.
        let challenge = MagicQRL.challenge(cardID: cid, rotationID: rid, nextDigest: vault.digest(next))
        let q = MagicQRL.combine(challenge: challenge,
                                 ncomDev: ncomDevSign(challenge).map { QRLHalf(party: .ncomDev, challenge: challenge, signature: $0) },
                                 glassVault: glassVaultSign(challenge).map { QRLHalf(party: .glassVault, challenge: challenge, signature: $0) },
                                 verify: qrlVerify)
        o.qrl = q
        guard q.agrees else {
            vault.lock(cardID: cid, reason: .outOfSync, tokenDigest: vault.digest(next), now: now)
            let (kind, who): (String, [QRLParty]) = {
                switch q { case .missing(let p): return ("qrl-missing", p); case .mismatch(let p): return ("qrl-mismatch", p); default: return ("", []) }
            }()
            let names = who.map(\.name).joined(separator: " and ")
            let detail = kind == "qrl-missing" ? "\(names)'s half of the magic QR never arrived." : "\(names)'s half of the magic QR didn't check out."
            o.report = SecurityReport(at: now, cardID: cid, kind: kind, detail: detail)
            add(.ouijaAuthenticates, false, detail + " Not signed in; card locked.")
            o.cardLocked = true
            return o
        }

        // 8b: OuijaBoard: both systems must agree whose card this is.
        guard cid == cardID, directory.owners[cid] == owner else {
            vault.lock(cardID: cid, reason: .outOfSync, tokenDigest: vault.digest(next), now: now)
            add(.ouijaAuthenticates, false, "NCOM Dev and GlassVault disagree about whose card this is. Not signed in; card locked.")
            o.cardLocked = true
            return o
        }
        o.grantedOwner = owner
        o.newRecord = OuijaKeyRecord(cardID: cid, expectedDigest: vault.digest(next), deviceID: device)
        add(.ouijaAuthenticates, true, "Three thumbs up. Signed in as \(owner).")
        return o
    }
}

/// What a tap shows the person, in plain words.
public enum MagicKeyWords {
    public static func text(_ r: MagicKeyLedger.Redeem) -> String {
        switch r {
        case .rotate: return "Card accepted. Writing its new key…"
        case .unknownCard: return "This isn't an NCOM ID card."
        case .otherPhone: return "This card isn't registered to this iPhone. Its key was burned and the card is locked until its owner's iPhone taps it."
        case .outOfSync: return "This card's key was already used. The card may have been copied, so it is now locked. NCOM has to reset it."
        case .locked(.otherPhone): return "This card is locked after a tap on another phone. Only its owner's iPhone can unlock it."
        case .locked(.outOfSync): return "This card is locked (copied or out of sync). NCOM has to reset it."
        case .locked(.revoked): return "NCOM has revoked this card."
        case .malformed: return "Couldn't read an NCOM key from this card."
        }
    }
}
