import XCTest
@testable import DisciplineCore

final class LabTests: XCTestCase {
    func testEntitlementsFromThinAndFatMachO() throws {
        for name in ["thin.macho", "fat.macho"] {
            let e = try EntitlementReader.entitlements(fromMachO: [UInt8](try fixture(name)))
            XCTAssertEqual(e["application-identifier"] as? String, "TEAMID.com.ncom.sampleapp", name)
            XCTAssertEqual(e["get-task-allow"] as? Bool, true, name)
            XCTAssertEqual(e["com.apple.developer.nfc.readersession.formats"] as? [String], ["TAG"], name)
        }
        XCTAssertThrowsError(try EntitlementReader.entitlements(fromMachO: [UInt8](repeating: 0, count: 64))) {
            XCTAssertEqual($0 as? EntitlementReader.ReadError, .notMachO)
        }
    }

    func testInspectSampleIPA() throws {
        let ins = try IPAReader.inspect(bytes: [UInt8](try fixture("Sample.ipa")))
        XCTAssertNil(ins.entitlementsError)
        XCTAssertTrue(ins.entitlementKeys.contains("get-task-allow"))
        XCTAssertEqual(ins.usageDescriptions.map(\.key), ["NSBluetoothAlwaysUsageDescription", "NSNearbyInteractionUsageDescription"])
        XCTAssertEqual(ins.unsignable(for: .free), ["com.apple.developer.nfc.readersession.formats"])
        XCTAssertEqual(ins.unsignable(for: .paid), [])
        XCTAssertEqual(ins.entitlementSummary.first { $0.key == "com.apple.developer.nfc.readersession.formats" }?.value, "[TAG]")
    }

    func testCatalogAndOuijaPreset() throws {
        XCTAssertEqual(Set(DeviceFeature.catalog.map(\.id)).count, DeviceFeature.catalog.count, "ids unique")
        XCTAssertEqual(DeviceFeature.lookup(entitlement: "com.apple.developer.networking.multicast")?.signability, .appleApprovalOnly)
        let p = SigningPreset.ouijaBoard
        XCTAssertEqual(p.resolved.count, p.features.count)
        XCTAssertEqual(p.blocked(for: .free).map(\.id), ["nfc"])
        XCTAssertEqual(p.blocked(for: .paid).map(\.id), [])
        XCTAssertTrue(p.entitlements(for: .free).isEmpty, "a free account gets no restricted entitlements")
        XCTAssertEqual(p.entitlements(for: .paid)["com.apple.developer.nfc.readersession.formats"] as? [String], ["TAG"])
        let info = p.infoPlistAdditions()
        XCTAssertNotNil(info["NSNearbyInteractionUsageDescription"])
        XCTAssertEqual(info["NSBonjourServices"] as? [String], ["_ncom._tcp", "_ncom-ouija._tcp"])
        XCTAssertEqual(info["UIBackgroundModes"] as? [String], ["bluetooth-central", "external-accessory", "nearby-interaction"])
        let xml = String(decoding: try p.entitlementsPlistXML(for: .paid), as: UTF8.self)
        XCTAssertTrue(xml.contains("com.apple.developer.nfc.readersession.formats"))
        let decoded = try JSONDecoder().decode(SigningPreset.self, from: try p.json())
        XCTAssertEqual(decoded, p)
    }
}
