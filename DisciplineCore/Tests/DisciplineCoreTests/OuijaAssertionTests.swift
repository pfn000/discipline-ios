import XCTest
@testable import DisciplineCore
#if canImport(CryptoKit)
import CryptoKit
#endif

final class OuijaAssertionTests: XCTestCase {
    func testRequestParsing() {
        let u = OuijaAssertion.authorizeURL(client: "Discipline", nonce: String(repeating: "ab", count: 16), callback: "discipline://ouija-auth")
        let r = OuijaAssertion.parseRequest(u)
        XCTAssertEqual(r?.client, "Discipline")
        XCTAssertEqual(r?.callback.absoluteString, "discipline://ouija-auth")
        XCTAssertNil(OuijaAssertion.parseRequest(URL(string: "ouija://authorize?client=X&nonce=\(String(repeating: "a", count: 32))&callback=https://evil.example")!))
        XCTAssertNil(OuijaAssertion.parseRequest(URL(string: "ouija://authorize?client=X&nonce=short&callback=discipline://x")!))
        XCTAssertEqual(OuijaAssertion.verify("junk", client: "Discipline", nonce: "n", pinnedKey: nil), .malformed)
    }

    #if canImport(CryptoKit)
    func testSignVerifyPinning() throws {
        let key = Curve25519.Signing.PrivateKey()
        let pk = OuijaAssertion.b64url(key.publicKey.rawRepresentation)
        let nonce = String(repeating: "cd", count: 16)
        let now = Date()
        let a = OuijaAssertion(client: "Discipline", nonce: nonce, name: "Saidie", iat: Int(now.timeIntervalSince1970), pk: pk)
        let s = try OuijaAssertion.sign(a, with: key)
        XCTAssertEqual(OuijaAssertion.verify(s, client: "Discipline", nonce: nonce, pinnedKey: nil, now: now), .accepted(a, firstPairing: true))
        XCTAssertEqual(OuijaAssertion.verify(s, client: "Discipline", nonce: nonce, pinnedKey: pk, now: now), .accepted(a, firstPairing: false))
        XCTAssertEqual(OuijaAssertion.verify(s, client: "Discipline", nonce: "other", pinnedKey: nil, now: now), .wrongNonce)
        XCTAssertEqual(OuijaAssertion.verify(s, client: "Discipline", nonce: nonce, pinnedKey: "someoneelse", now: now), .differentKey)
        XCTAssertEqual(OuijaAssertion.verify(s, client: "Discipline", nonce: nonce, pinnedKey: nil, now: now.addingTimeInterval(900)), .expired)
        var tampered = Array(s); tampered[12] = tampered[12] == "A" ? "B" : "A"
        XCTAssertNotEqual(OuijaAssertion.verify(String(tampered), client: "Discipline", nonce: nonce, pinnedKey: nil, now: now), .accepted(a, firstPairing: true))
    }

    func testRingLoginWithRealSignature() {
        let key = Curve25519.Signing.PrivateKey()
        let pub = [UInt8](key.publicKey.rawRepresentation)
        let session = RingLogin.newSession()
        let now = Date()
        var m = RingLogin(session: session, issuedAt: UInt32(now.timeIntervalSince1970), keyID: RingCode.fnv1a(pub), signature: [])
        let sig = try! key.signature(for: Data(RingLogin.domain + m.signedPart))
        m = RingLogin(session: m.session, issuedAt: m.issuedAt, keyID: m.keyID, signature: [UInt8](sig))
        // Through the rings and back.
        var asm = RingCode.Assembler()
        for (i, f) in RingCode.frames(for: m.bytes).enumerated() {
            var img = RingRenderer.render(f, size: 320, angles: RingCode.choreography(forKey: pub).map { $0 * Double(i) * 7 })
            RingRenderer.addNoise(&img, salt: 0.01, amplitude: 30, seed: UInt64(i + 1))
            if let g = RingReader.read(img) { asm.add(g) }
        }
        XCTAssertTrue(asm.isComplete)
        XCTAssertEqual(RingLogin.verify(asm.message!, session: session, enrolled: [pub], now: now), .accepted(keyID: RingCode.fnv1a(pub)))
        XCTAssertEqual(RingLogin.verify(asm.message!, session: RingLogin.newSession(), enrolled: [pub], now: now), .wrongSession)
        XCTAssertEqual(RingLogin.verify(asm.message!, session: session, enrolled: [pub], now: now.addingTimeInterval(600)), .expired)
    }
    #endif
}
