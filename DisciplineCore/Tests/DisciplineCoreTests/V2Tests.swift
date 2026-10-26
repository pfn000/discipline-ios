import XCTest
@testable import DisciplineCore
#if canImport(CryptoKit)
import CryptoKit
#endif

/// v0.3 logic: auto refresh decisions, reading expiry from provisioning profiles,
/// self-update version checks and the signed NCOM Ouija Board QR code.
final class V2Tests: XCTestCase {
    // MARK: Auto refresh

    func testAutoRefreshDecisions() {
        let p = AutoRefreshPlanner()
        XCTAssertEqual(p.decide(apps: [], lastRun: nil, now: t0), .nothingTracked)
        let fresh = TrackedApp(name: "A", bundleID: "a", signedAt: t0, tier: .free)
        if case .nothingDue(let next) = p.decide(apps: [fresh], lastRun: nil, now: t0) {
            XCTAssertEqual(next, fresh.expiresAt.addingTimeInterval(-48 * 3600))
        } else { XCTFail("a fresh 7-day signature is not due") }
        let old = TrackedApp(name: "B", bundleID: "b", signedAt: t0.addingTimeInterval(-6 * 86_400), tier: .free)
        XCTAssertEqual(p.decide(apps: [fresh, old], lastRun: nil, now: t0), .refresh(due: ["b"]))
        // Started 1 h ago: don't loop when the user comes back from SideStore.
        XCTAssertEqual(p.decide(apps: [old], lastRun: t0.addingTimeInterval(-3600), now: t0),
                       .ranRecently(nextAllowed: t0.addingTimeInterval(5 * 3600)))
        XCTAssertEqual(p.decide(apps: [old], lastRun: t0.addingTimeInterval(-7 * 3600), now: t0), .refresh(due: ["b"]))
        let expired = TrackedApp(name: "C", bundleID: "c", signedAt: t0.addingTimeInterval(-9 * 86_400), tier: .free)
        XCTAssertEqual(p.decide(apps: [old, expired], lastRun: nil, now: t0), .refresh(due: ["c", "b"]))
    }

    func testReadExpiryOverridesTypedDate() {
        let exact = t0.addingTimeInterval(3 * 86_400 + 600)
        let app = TrackedApp(name: "D", bundleID: "d", signedAt: t0, tier: .free, profileExpiresAt: exact)
        XCTAssertEqual(app.expiresAt, exact)
        XCTAssertTrue(app.expiryIsRead)
        XCTAssertFalse(TrackedApp(name: "E", bundleID: "e", signedAt: t0, tier: .free).expiryIsRead)
    }

    func testTrackedAppDecodesOldSavedState() throws {
        // v0.2 saved TrackedApp without profileExpiresAt; it must still load.
        let json = #"{"name":"LiveContainer","bundleID":"com.kdt.livecontainer","signedAt":"2026-10-20T10:00:00Z","tier":"free"}"#
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let app = try d.decode(TrackedApp.self, from: Data(json.utf8))
        XCTAssertNil(app.profileExpiresAt)
        XCTAssertEqual(app.name, "LiveContainer")
    }

    // MARK: Provisioning profile

    func testProvisioningProfileFromSignedIPA() throws {
        let data = try fixture("Signed.ipa")
        let profile = try XCTUnwrap(try IPAReader.provisioningProfile(bytes: [UInt8](data)))
        let f = ISO8601DateFormatter()
        XCTAssertEqual(profile.expirationDate, f.date(from: "2026-11-02T12:00:00Z"))
        XCTAssertEqual(profile.creationDate, f.date(from: "2026-10-26T12:00:00Z"))
        XCTAssertEqual(profile.teamName, "Test Team (fixture)")
        XCTAssertEqual(profile.deviceCount, 1)
        XCTAssertEqual(profile.tier(), .free)
        // The app itself is still readable.
        XCTAssertEqual(try IPAReader.read(bytes: [UInt8](data)).bundleID, "com.ncom.signedsample")
    }

    func testUnsignedIPAHasNoProfile() throws {
        XCTAssertNil(try IPAReader.provisioningProfile(bytes: [UInt8](try fixture("Sample.ipa"))))
    }

    func testProfileParserRejectsGarbage() {
        XCTAssertThrowsError(try ProvisioningProfile.parse(Array("not a profile".utf8))) {
            XCTAssertEqual($0 as? ProvisioningProfile.ParseError, .noPropertyList)
        }
        let noDate = Array("<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>Name</key><string>x</string></dict></plist>".utf8)
        XCTAssertThrowsError(try ProvisioningProfile.parse(noDate)) {
            XCTAssertEqual($0 as? ProvisioningProfile.ParseError, .noExpirationDate)
        }
    }

    // MARK: Self-update

    func testVersionCompare() {
        XCTAssertTrue(VersionCompare.isNewer("v0.3.1", than: "0.3.0"))
        XCTAssertTrue(VersionCompare.isNewer("0.10.0", than: "0.9.9"))
        XCTAssertTrue(VersionCompare.isNewer("1.0", than: "0.99.1"))
        XCTAssertFalse(VersionCompare.isNewer("v0.3.0", than: "0.3.0"))
        XCTAssertFalse(VersionCompare.isNewer("v0.2.9", than: "0.3.0"))
        XCTAssertFalse(VersionCompare.isNewer("nightly", than: "0.3.0"))
        XCTAssertTrue(VersionCompare.isNewer("0.3.0", than: "0.3.0-beta"))
        XCTAssertFalse(VersionCompare.isNewer("0.3.0-beta", than: "0.3.0"))
    }

    func testUpdatePickerUsesReleaseNotes() throws {
        let list = try GitHubRelease.decodeList(try fixture("releases.json"))
        let u = try XCTUnwrap(VersionCompare.update(for: "1.0.0", in: list, includePrereleases: false))
        XCTAssertEqual(u.tagName, "v1.2.3")
        XCTAssertNil(VersionCompare.update(for: "1.2.3", in: list, includePrereleases: false))
        XCTAssertNotNil(u.body, "release notes are decoded")
    }

    // MARK: NCOM Ouija Board QR

    static let testPublicKey = OuijaCode.base64URLDecode("qNMlfqG-kdjedq5CxZDm10U9n0g9swF1bM1oYsbfQQU")!
    static let testCode = "NCOM1.eyJ2IjoxLCJpc3MiOiJOQ09NIFN5c3RlbXMiLCJzdWIiOiJPdWlqYSBCb2FyZCIsImlhdCI6MTc5MjkwMDAwMCwibiI6IjAwMTEyMjMzNDQ1NTY2NzcifQ.OH9zMowlq5wy6fAT2xPHhrzPHN6CrefXrkBHy4_xAxeBit-GHPXi2IL5zbN9AtiyhRUOognhKX4U-QDiH8uZDw"
    static let foreignCode = "NCOM1.eyJ2IjoxLCJpc3MiOiJOQ09NIFN5c3RlbXMiLCJzdWIiOiJPdWlqYSBCb2FyZCIsImlhdCI6MTc5MjkwMDAwMCwibiI6IjAwMTEyMjMzNDQ1NTY2NzcifQ.xW9l6zENePvoOjNpwDLcUMnVtZUUeWh9Fcqe9loeYTRDD8YnQjdA1VrP3Ak4zyOgpoe5g81zuhEnzJVGW-CcDg"
    static let wrongSubject = "NCOM1.eyJ2IjoxLCJpc3MiOiJOQ09NIFN5c3RlbXMiLCJzdWIiOiJTb21ldGhpbmcgZWxzZSIsImlhdCI6MTc5MjkwMDAwMCwibiI6ImFhIn0.rCqWkfOlNjs1pAv_tjXHWv7lIIRJyboYm4L0q3QtcJ7grs5xoy9mAIIyxkm1VojWnBTzD2TEhBrb9tnRwXsNAg"

    func testOuijaCodeExtractAndParse() {
        XCTAssertEqual(OuijaCode.extract(from: "discipline://ouija?code=" + Self.testCode), Self.testCode)
        XCTAssertEqual(OuijaCode.extract(from: "  " + Self.testCode + "\n"), Self.testCode)
        XCTAssertNil(OuijaCode.extract(from: "https://example.com"))
        XCTAssertNotNil(OuijaCode.parse(Self.testCode))
        XCTAssertNil(OuijaCode.parse("NCOM1.abc"))
        XCTAssertEqual(OuijaCode.check("hello", publicKeys: [Self.testPublicKey]), .notACode)
    }

    #if canImport(CryptoKit)
    /// The code was signed by the Python tool that makes Saidie's QR (Ed25519); CryptoKit must accept it.
    func testOuijaCodeSignedOutsideVerifies() {
        if case .valid(let c) = OuijaCode.check(Self.testCode, publicKeys: [Self.testPublicKey]) {
            XCTAssertEqual(c.iss, "NCOM Systems"); XCTAssertEqual(c.sub, "Ouija Board"); XCTAssertEqual(c.iat, 1792900000)
        } else { XCTFail("test code must verify") }
        XCTAssertEqual(OuijaCode.check(Self.foreignCode, publicKeys: [Self.testPublicKey]), .badSignature)
        XCTAssertEqual(OuijaCode.check(Self.wrongSubject, publicKeys: [Self.testPublicKey]), .wrongContent)
        // One changed character in the message breaks the signature.
        var chars = Array(Self.testCode); let i = 12
        chars[i] = chars[i] == "A" ? "B" : "A"
        XCTAssertEqual(OuijaCode.check(String(chars), publicKeys: [Self.testPublicKey]), .badSignature)
    }

    func testOuijaCodeRoundTripWithCryptoKit() throws {
        let key = Curve25519.Signing.PrivateKey()
        let msg = Data(#"{"v":1,"iss":"NCOM Systems","sub":"Ouija Board","iat":1,"n":"x"}"#.utf8)
        let sig = try key.signature(for: msg)
        func b64u(_ d: Data) -> String { d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
        let code = "NCOM1." + b64u(msg) + "." + b64u(sig)
        XCTAssertEqual(OuijaCode.check(code, publicKeys: [key.publicKey.rawRepresentation]), .valid(OuijaCode.Claims(v: 1, iss: "NCOM Systems", sub: "Ouija Board", iat: 1, n: "x")))
        XCTAssertEqual(OuijaCode.check(code, publicKeys: [Self.testPublicKey]), .badSignature)
    }
    #endif
}
