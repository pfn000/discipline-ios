import Foundation
import SwiftUI
import CryptoKit
import DisciplineCore
#if canImport(CoreNFC)
import CoreNFC
#endif

// MARK: - This iPhone's developer key (what the verifier registers for the card)

extension OuijaModel {
    static let magicKeyService = "com.ncom.ouija.magickey"

    /// A P-256 signing key that never leaves this iPhone: made inside the Secure Enclave when the phone has one
    /// (a real iPhone), otherwise (the simulator) a software key kept in the Keychain. `magicKeyKind` says which.
    var magicKey: MagicPhoneKey { MagicPhoneKey.loadOrCreate(service: Self.magicKeyService) }
}

struct MagicPhoneKey {
    let publicKeyRaw: Data          // 64 bytes x||y; the verifier stores it as the phone's id
    let kind: String                // "Secure Enclave" or "software key (no Secure Enclave here)"
    private let signer: (Data) throws -> Data

    var id: String { OuijaAssertion.b64url(publicKeyRaw) }
    var fingerprint: String { RingLogin.fingerprint([UInt8](publicKeyRaw)) }

    /// Signs a request message; the signature is raw r||s (64 bytes), base64url.
    func sign(message: String) throws -> String { OuijaAssertion.b64url(try signer(Data(message.utf8))) }

    /// SHA-256 hex, the digest NCOM's servers store instead of the key itself.
    static let digest: @Sendable (String) -> String = { s in SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined() }

    static func loadOrCreate(service: String) -> MagicPhoneKey {
        if SecureEnclave.isAvailable {
            if let blob = Keychain.read(service: service), let k = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob) {
                return MagicPhoneKey(publicKeyRaw: k.publicKey.rawRepresentation, kind: "Secure Enclave") { try k.signature(for: $0).rawRepresentation }
            }
            if let k = try? SecureEnclave.P256.Signing.PrivateKey() {
                Keychain.write(k.dataRepresentation, service: service)
                return MagicPhoneKey(publicKeyRaw: k.publicKey.rawRepresentation, kind: "Secure Enclave") { try k.signature(for: $0).rawRepresentation }
            }
        }
        let k: P256.Signing.PrivateKey
        if let raw = Keychain.read(service: service), let existing = try? P256.Signing.PrivateKey(rawRepresentation: raw) { k = existing }
        else { k = P256.Signing.PrivateKey(); Keychain.write(k.rawRepresentation, service: service) }
        return MagicPhoneKey(publicKeyRaw: k.publicKey.rawRepresentation, kind: "software key (no Secure Enclave here)") { try k.signature(for: $0).rawRepresentation }
    }
}

// MARK: - NCOM Dev + GlassVault (NCOM's servers; an in-memory copy runs only in simulator UI tests)

/// What one tap ended with, for the screen: the 8 steps, the magic QR, and a security report when it's a no.
struct CardTapResult {
    var steps: [MagicStepResult] = []
    var qrl: QRLVerdict?
    var report: SecurityReport?
    var grantedOwner: String?
    var cardID: String?
    var newRecord: OuijaKeyRecord?
}

protocol MagicVerifier {
    /// Steps 2-7 happen on NCOM's side. `write` puts the new key on the card and says whether that worked.
    func run(token: String, local: OuijaKeyRecord?, write: (String) async -> Bool) async -> CardTapResult
}

/// NCOM's verifier over HTTPS: POST <base>/api/ouija/magic-key/redeem, then /confirm (contract in MAGIC-KEY.md).
/// The two QRL halves come back with the confirmation and are checked against NCOM Dev's and GlassVault's own
/// public keys, which the developer pins in Keys (none pinned = the half counts as missing).
struct HTTPMagicVerifier: MagicVerifier {
    let base: URL
    let key: MagicPhoneKey
    let ncomDevKey: String
    let glassVaultKey: String

    private func post(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        var r = URLRequest(url: base.appendingPathComponent(path))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.timeoutInterval = 15
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: r)
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    static func verifyHalf(_ pkText: String, _ challenge: String, _ sig: String) -> Bool {
        guard let pk = Data(base64URL: pkText), let s = Data(base64URL: sig),
              let key = try? P256.Signing.PublicKey(rawRepresentation: pk),
              let es = try? P256.Signing.ECDSASignature(rawRepresentation: s) else { return false }
        return key.isValidSignature(es, for: Data(challenge.utf8))
    }

    func run(token: String, local: OuijaKeyRecord?, write: (String) async -> Bool) async -> CardTapResult {
        var out = CardTapResult()
        func add(_ s: MagicStep, _ ok: Bool, _ w: String) { out.steps.append(MagicStepResult(step: s, ok: ok, words: w)) }
        add(.tapped, true, "Read the card's key.")
        let ts = Int(Date().timeIntervalSince1970)
        let j: [String: Any]
        do {
            j = try await post("api/ouija/magic-key/redeem", ["v": 1, "token": token, "device_pk": key.id, "ts": ts,
                                                              "sig": try key.sign(message: MagicHandshake.message(token: token, ts: ts))])
        } catch {
            add(.ncomDevKnowsCard, false, "Couldn't reach NCOM's verifier. Not signed in; nothing changed.")
            return out
        }
        // The server reports steps 2, 3 and 5-6 as it ran them.
        for s in [MagicStep.ncomDevKnowsCard, .glassVaultDeviceMatch] {
            let flags = j["steps"] as? [Bool] ?? []
            let ok = flags.count >= s.rawValue && flags[s.rawValue - 1]
            if !ok { add(s, false, (j["words"] as? String) ?? "No."); out.report = SecurityReport(at: Date(), cardID: j["card_id"] as? String, kind: "step-\(s.rawValue)", detail: (j["words"] as? String) ?? ""); return out }
            add(s, true, s.title)
        }
        guard j["status"] as? String == "rotate", let rid = j["rotation_id"] as? String, let next = j["next_token"] as? String,
              let cardID = j["card_id"] as? String, MagicCardToken.isValid(next) else {
            add(.glassVaultVerdict, false, (j["words"] as? String) ?? "GlassVault said no.")
            return out
        }
        out.cardID = cardID
        // 4: this iPhone's own record of the card.
        if let local, local.cardID != cardID || local.deviceID != key.id || local.expectedDigest != MagicPhoneKey.digest(token) {
            _ = try? await post("api/ouija/magic-key/reject", ["v": 1, "rotation_id": rid, "card_id": cardID, "device_pk": key.id, "ts": ts,
                                                               "sig": (try? key.sign(message: "NCOM-MAGIC1|reject|\(rid)|\(ts)")) ?? ""])
            add(.ouijaLocalMatch, false, "This card doesn't match what this iPhone wrote on it last. Key burned, card locked.")
            out.report = SecurityReport(at: Date(), cardID: cardID, kind: "step-4", detail: "Card didn't match this iPhone's record.")
            return out
        }
        add(.ouijaLocalMatch, true, local == nil ? "First tap on this iPhone." : "Matches what this iPhone wrote last.")
        add(.glassVaultVerdict, true, MagicStep.glassVaultVerdict.title)
        add(.ncomDevApproves, true, MagicStep.ncomDevApproves.title)
        guard await write(next) else {
            add(.glassVaultRotates, false, "The new key couldn't be written onto the card. Nothing was burned; tap again.")
            return out
        }
        let ts2 = Int(Date().timeIntervalSince1970)
        guard let c = try? await post("api/ouija/magic-key/confirm", ["v": 1, "rotation_id": rid, "card_id": cardID, "device_pk": key.id, "ts": ts2,
                                                                       "sig": (try? key.sign(message: "NCOM-MAGIC1|confirm|\(rid)|\(ts2)")) ?? ""]),
              c["status"] as? String == "granted", let owner = c["owner_name"] as? String else {
            add(.glassVaultRotates, false, "GlassVault didn't confirm. The new key is on the card; tap again.")
            return out
        }
        add(.glassVaultRotates, true, MagicStep.glassVaultRotates.title)
        let challenge = MagicQRL.challenge(cardID: cardID, rotationID: rid, nextDigest: MagicPhoneKey.digest(next))
        let q = c["qrl"] as? [String: String] ?? [:]
        let verdict = MagicQRL.combine(challenge: challenge,
                                       ncomDev: q["ncom_dev"].map { QRLHalf(party: .ncomDev, challenge: challenge, signature: $0) },
                                       glassVault: q["glass_vault"].map { QRLHalf(party: .glassVault, challenge: challenge, signature: $0) },
                                       verify: { party, ch, sig in Self.verifyHalf(party == .ncomDev ? ncomDevKey : glassVaultKey, ch, sig) })
        out.qrl = verdict
        guard verdict.agrees else {
            add(.ouijaAuthenticates, false, "The two halves of the magic QR don't agree. Not signed in.")
            var kind = "qrl-mismatch"
            if case .missing = verdict { kind = "qrl-missing" }
            out.report = SecurityReport(at: Date(), cardID: cardID, kind: kind, detail: "The magic QR halves didn't agree (\(verdict)).")
            return out
        }
        out.grantedOwner = owner
        out.newRecord = OuijaKeyRecord(cardID: cardID, expectedDigest: MagicPhoneKey.digest(next), deviceID: key.id)
        add(.ouijaAuthenticates, true, "Three thumbs up. Signed in as \(owner).")
        return out
    }
}

/// UI-test stand-in for NCOM Dev + GlassVault: the exact rules (MagicHandshake), in memory, on the simulator only.
actor MockMagicVerifier: MagicVerifier {
    private var h: MagicHandshake
    private let device: String
    init(cardToken: String, ownerName: String, registeredDevice: String, thisDevice: String, qrl: String?) {
        var vault = MagicKeyLedger(digest: MagicPhoneKey.digest)
        vault.enroll(cardID: "TEST-0001", ownerName: ownerName, token: cardToken, device: registeredDevice)
        var dir = NCOMDevDirectory()
        dir.issue(cardID: "TEST-0001", owner: ownerName, device: registeredDevice)
        var hs = MagicHandshake(directory: dir, vault: vault)
        if qrl == "missing" { hs.glassVaultSign = { _ in nil } }
        if qrl == "mismatch" { hs.ncomDevSign = { _ in "ncomdev-signed(another tap)" } }
        h = hs; device = thisDevice
    }
    func run(token: String, local: OuijaKeyRecord?, write: (String) async -> Bool) async -> CardTapResult {
        var g = SystemRandomNumberGenerator()
        // Peek at the outcome on a copy first: the card is written only if the parties got that far.
        var trial = h
        let o = trial.tap(cardToken: token, device: device, local: local, writeSucceeds: true, rng: &g)
        var written = false
        if let next = o.newCardToken { written = await write(next) }
        if o.newCardToken != nil && !written {
            var g2 = SystemRandomNumberGenerator()
            let failed = h.tap(cardToken: token, device: device, local: local, writeSucceeds: false, rng: &g2)
            return CardTapResult(steps: failed.steps, qrl: failed.qrl, report: failed.report)
        }
        h = trial
        return CardTapResult(steps: o.steps, qrl: o.qrl, report: o.report, grantedOwner: o.grantedOwner,
                             cardID: o.newRecord?.cardID, newRecord: o.newRecord)
    }
}

extension Data {
    init?(base64URL s: String) {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        self.init(base64Encoded: t)
    }
}

// MARK: - The tap

@MainActor
final class MagicCardFlow: ObservableObject {
    enum Phase: Equatable { case idle, waitingForCard, talking, cardOK, scanning, dancing, granted(String), choice, failed(String) }
    @Published var phase: Phase = .idle
    @Published var result = CardTapResult()
    @Published var reported = false

    private var reader: AnyObject?
    private var mockCardToken: String?
    private var mockVerifier: MockMagicVerifier?

    var nfcAvailable: Bool {
        #if canImport(CoreNFC)
        return NFCNDEFReaderSession.readingAvailable
        #else
        return false
        #endif
    }

    var dance: QRLDance? { if case .agree(let d)? = result.qrl { return d }; return nil }
    var isFailed: Bool { if case .failed = phase { return true }; return false }
    /// The eight checks are shown only once there is an outcome.
    var showsSteps: Bool {
        switch phase { case .failed, .choice, .granted: return true; default: return false }
    }

    func setUpTestCard(model: OuijaModel) {
        guard OuijaTest.has("-uiTestingMagicKeyMock"), mockVerifier == nil else { return }
        let token = "ncom-card-" + String(repeating: "a", count: 20)
        mockCardToken = token
        let me = model.magicKey.id
        let registered = OuijaTest.has("-uiTestingMagicKeyOtherPhone") ? "someone-elses-phone" : me
        mockVerifier = MockMagicVerifier(cardToken: token, ownerName: OuijaTest.value("-uiTestingMagicKeyOwner") ?? "Test Owner",
                                         registeredDevice: registered, thisDevice: me, qrl: OuijaTest.value("-uiTestingMagicKeyQRL"))
    }

    func start(model: OuijaModel) {
        result = CardTapResult(); reported = false
        if let v = mockVerifier, let token = mockCardToken {
            phase = .talking
            Task {
                let r = await v.run(token: token, local: model.settings.cardRecord) { [weak self] next in
                    await MainActor.run { self?.mockCardToken = next }; return true
                }
                await finish(r, model: model)
            }
            return
        }
        let base = model.settings.verifierURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: base), url.scheme == "https" else {
            phase = .failed("NCOM's verifier isn't set up yet, so the card can't be checked. Add its https address in Keys > Developer card.")
            return
        }
        guard nfcAvailable else {
            phase = .failed("This device can't read NFC cards (the simulator never can).")
            return
        }
        let verifier = HTTPMagicVerifier(base: url, key: model.magicKey, ncomDevKey: model.settings.ncomDevKey, glassVaultKey: model.settings.glassVaultKey)
        #if canImport(CoreNFC)
        let r = NFCMagicCardReader()
        reader = r
        phase = .waitingForCard
        let local = model.settings.cardRecord
        r.begin(run: { token, write in
            await MainActor.run { self.phase = .talking }
            let res = await verifier.run(token: token, local: local, write: write)
            await self.finish(res, model: model)
            return (res.grantedOwner != nil, res.grantedOwner.map { "Signed in as \($0)." } ?? (res.steps.last(where: { !$0.ok })?.words ?? "Not signed in."))
        }, ended: { [weak self] error in
            Task { @MainActor in
                guard let self, let error, self.phase == .waitingForCard || self.phase == .talking else { return }
                self.phase = .failed(error)
            }
        })
        #endif
    }

    private func finish(_ r: CardTapResult, model: OuijaModel) async {
        result = r
        if let report = r.report { model.settings.securityReports.insert(report, at: 0) }
        let test = OuijaTest.active
        // v0.4 order (Saidie, Nov 1 3:55 PM): the ID turns green, then the phone scans the sphere the NCOM Dev
        // website shows. The website and the camera decoder are stand-ins in this build (SphereBeacon is the decoder).
        let cardPassed = r.grantedOwner != nil || (r.qrl.map { !$0.agrees } ?? false)
        if cardPassed {
            phase = .cardOK
            try? await Task.sleep(for: .seconds(test ? 1.4 : 1.0))
            phase = .scanning
            try? await Task.sleep(for: .seconds(OuijaTest.has("-uiTestingScanHold") ? 30 : (test ? 2.5 : 2.0)))
        }
        if let owner = r.grantedOwner, let card = r.cardID {
            // The sphere moves to a hash of both halves of the magic QR before the sign-in lands.
            phase = .dancing
            try? await Task.sleep(for: .seconds(OuijaTest.has("-uiTestingSphereLive") ? 30 : (test ? 6 : 1.6)))
            model.settings.cardRecord = r.newRecord    // the card now holds this; keep it whatever happens next
            pendingGrant = (owner, card)
            phase = .granted(owner)
        } else if let q = r.qrl, !q.agrees {
            phase = .choice
        } else {
            phase = .failed(r.steps.last(where: { !$0.ok })?.words ?? "Not signed in.")
        }
    }

    private var pendingGrant: (owner: String, card: String)?

    /// Continue after a granted tap: the account becomes the card owner's (the screen behind the sheet changes now).
    func commit(model: OuijaModel) {
        guard let g = pendingGrant else { return }
        pendingGrant = nil
        model.grantDeveloper(ownerName: g.owner, cardID: g.card)
    }

    /// The developer's choice after a magic-QR failure.
    func reportToIT(model: OuijaModel) {
        if let i = model.settings.securityReports.firstIndex(where: { !$0.reportedToIT }) { model.settings.securityReports[i].reportedToIT = true }
        reported = true
    }
}

#if canImport(CoreNFC)
/// Reads the NCOM key record off the card, lets NCOM's verifier run its steps, writes the new key back when told to.
/// Core NFC needs the "NFC Tag Reading" capability in the app's signature. Apple lists it for paid developer
/// accounts only, so on a free-account install the session ends with Apple's "missing entitlement" error.
final class NFCMagicCardReader: NSObject, NFCNDEFReaderSessionDelegate {
    typealias Run = (_ token: String, _ write: @escaping (String) async -> Bool) async -> (ok: Bool, words: String)
    private var session: NFCNDEFReaderSession?
    private var run: Run?
    private var ended: ((String?) -> Void)?
    private var finished = false

    func begin(run: @escaping Run, ended: @escaping (String?) -> Void) {
        self.run = run; self.ended = ended
        let s = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        s.alertMessage = "Hold your NCOM ID card to the top of your iPhone."
        session = s
        s.begin()
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        let code = (error as? NFCReaderError)?.code
        let normal = finished || code == .readerSessionInvalidationErrorFirstNDEFTagRead || code == .readerSessionInvalidationErrorUserCanceled
        ended?(normal ? nil : error.localizedDescription)
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {}

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first else { return }
        session.connect(to: tag) { err in
            if err != nil { session.invalidate(errorMessage: "Couldn't connect to the card. Try again."); return }
            tag.queryNDEFStatus { status, _, err in
                guard err == nil else { session.invalidate(errorMessage: "Couldn't read the card."); return }
                guard status == .readWrite else {
                    session.invalidate(errorMessage: status == .readOnly ? "This card is locked read-only, so its key can't roll." : "This isn't an NDEF card.")
                    return
                }
                tag.readNDEF { message, _ in
                    guard let message,
                          let idx = message.records.firstIndex(where: { MagicCardToken.token(fromPayload: [UInt8]($0.payload)) != nil }),
                          let token = MagicCardToken.token(fromPayload: [UInt8](message.records[idx].payload))
                    else { session.invalidate(errorMessage: "No NCOM key on this card."); return }
                    let rec = message.records[idx]
                    let write: (String) async -> Bool = { next in
                        session.alertMessage = "Writing the new key… keep holding."
                        var records = message.records
                        records[idx] = NFCNDEFPayload(format: rec.typeNameFormat, type: rec.type, identifier: rec.identifier,
                                                      payload: Data(MagicCardToken.payload(next)))
                        return await withCheckedContinuation { cont in
                            tag.writeNDEF(NFCNDEFMessage(records: records)) { werr in cont.resume(returning: werr == nil) }
                        }
                    }
                    Task {
                        guard let res = await self.run?(token, write) else { return }
                        let ok = res.ok, words = res.words
                        self.finished = true
                        if ok { session.alertMessage = words; session.invalidate() } else { session.invalidate(errorMessage: words) }
                    }
                }
            }
        }
    }
}
#endif
