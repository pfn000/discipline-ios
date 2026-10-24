import XCTest
@testable import DisciplineCore

final class TrollStoreSupportTests: XCTestCase {
    func testBoundaryAndRCBuild() {
        let eligible = TrollStoreSupport.Verdict.eligibleOS
        let denied = TrollStoreSupport.Verdict.unsupportedOS
        XCTAssertEqual(TrollStoreSupport.evaluate(version: OSVersion(14, 0)), eligible)
        XCTAssertEqual(TrollStoreSupport.evaluate(version: OSVersion(15, 4, 1)), eligible)
        XCTAssertEqual(TrollStoreSupport.evaluate(version: OSVersion(16, 6, 1)), eligible)
        XCTAssertEqual(TrollStoreSupport.evaluate(version: OSVersion(16, 7), build: "20H18"), eligible)
        XCTAssertEqual(TrollStoreSupport.evaluate(version: OSVersion(16, 7), build: "20H19"), denied)
        XCTAssertEqual(TrollStoreSupport.evaluate(version: OSVersion(17, 0)), eligible)
        XCTAssertEqual(TrollStoreSupport.evaluate(version: OSVersion(17, 0, 1)), denied)
        XCTAssertEqual(TrollStoreSupport.evaluate(version: OSVersion(26, 2)), denied)
        XCTAssertEqual(TrollStoreSupport.evaluate(version: nil), .unknownOS)
        XCTAssertEqual(TrollStoreSupport.evaluate(version: OSVersion(16, 7)), .unknownOS)
    }
}
