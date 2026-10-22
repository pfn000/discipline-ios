import XCTest
@testable import DisciplineCore

final class GuardTests: XCTestCase {
    func testTrackerScan() throws {
        let findings = try TrackerScanner.scan(ipaBytes: [UInt8](try fixture("Tracked.ipa")))
        let names = Set(findings.map(\.signature.name))
        XCTAssertEqual(names, ["Google Analytics for Firebase", "Google AdMob", "AppsFlyer"])
        XCTAssertEqual(findings.first { $0.signature.name == "Google Analytics for Firebase" }?.evidence, .framework)
        XCTAssertEqual(findings.first { $0.signature.name == "Google AdMob" }?.evidence, .symbol)
        XCTAssertTrue(try TrackerScanner.scan(ipaBytes: [UInt8](try fixture("Sample.ipa"))).isEmpty, "clean sample has none")
    }

    func testDomainLookup() {
        XCTAssertEqual(TrackerSignature.forDomain("app-measurement.com")?.name, "Google Analytics for Firebase")
        XCTAssertEqual(TrackerSignature.forDomain("eu.api2.branch.io")?.name, "Branch")
        XCTAssertNil(TrackerSignature.forDomain("notbranch.io"))
        XCTAssertNil(TrackerSignature.forDomain("example.com"))
    }

    func testPrivacyReport() throws {
        let r = PrivacyReport.parse(try fixture("privacy-report.ndjson"))
        XCTAssertEqual(r.lineCount, 8)
        XCTAssertEqual(r.skippedLines, 1)
        XCTAssertEqual(r.apps.count, 3)
        let chat = try XCTUnwrap(r.apps.first { $0.bundleID == "com.example.chat" })
        XCTAssertEqual(chat.sensorAccess["camera"], 1, "begin/end pair counted once")
        XCTAssertEqual(chat.sensorAccess["location"], 1)
        XCTAssertEqual(chat.domains["api.example.com"], 12)
        XCTAssertEqual(chat.trackerDomains, ["app-measurement.com": "Google Analytics for Firebase"])
        XCTAssertEqual(r.totalTrackerContacts, 2)
        XCTAssertEqual(r.apps.last?.bundleID, "com.example.notes")
    }
}
