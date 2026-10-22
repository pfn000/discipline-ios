import XCTest

final class HomeUITests: DisciplineUITestCase {
    /// Simulator has none of the companion apps: every Home control explains or opens the official page.
    func testHomeWithoutCompanionApps() {
        launch()
        XCTAssertTrue(el("home.noTracked").waitForExistence(timeout: 10))
        snap("01-home")
        tap("home.refreshAll")
        expectToast(contains: "Install LocalDevVPN and SideStore first")
        dismissToast()
        tap("home.vpnOn")
        expectToast(contains: "LocalDevVPN isn't installed", value: "localdevvpn://enable?scheme=discipline")
        dismissToast()
        tap("home.vpnOff")
        expectToast(contains: "LocalDevVPN isn't installed", value: "localdevvpn://disable?scheme=discipline")
        dismissToast()
        XCTAssertFalse(el("home.markAllRefreshed").isEnabled, "Mark done is off with nothing tracked")
        XCTAssertEqual(el("home.tunnelState").label, "Off")
        tap("home.checkStatus")
        expectToast(contains: "Status updated")
        dismissToast()
        // "Get" opens each companion's official page in Safari.
        tap("home.open.liveContainer")
        expectOtherApp("com.apple.mobilesafari")
        tap("home.open.sideStore")
        expectOtherApp("com.apple.mobilesafari")
        tap("home.open.localDevVPN")
        expectOtherApp("com.apple.mobilesafari")
    }

    /// With the companions "installed" (test hook), each control hands the exact URL to the right app.
    func testHomeHandsExactLinksToCompanions() {
        launch(["-uiTestingFakeCompanions"])
        tap("home.refreshAll")
        expectToast(contains: "Sent to LocalDevVPN", value: "localdevvpn://enable?scheme=sidestore")
        dismissToast()
        tap("home.vpnOn")
        expectToast(contains: "Sent to LocalDevVPN", value: "localdevvpn://enable?scheme=discipline")
        dismissToast()
        tap("home.vpnOff")
        expectToast(contains: "Sent to LocalDevVPN", value: "localdevvpn://disable?scheme=discipline")
        dismissToast()
        tap("home.open.localDevVPN"); expectToast(contains: "Sent to LocalDevVPN", value: "localdevvpn://"); dismissToast()
        tap("home.open.sideStore"); expectToast(contains: "Sent to SideStore", value: "sidestore://"); dismissToast()
        tap("home.open.liveContainer"); expectToast(contains: "Sent to LiveContainer", value: "livecontainer://"); dismissToast()
        snap("02-home-kit-installed")
    }
}

final class LibraryUITests: DisciplineUITestCase {
    /// "Open in Discipline" from Files: parsed app info, share hand-off, App ID log, tracking, delete.
    func testOpenInIPAFlow() {
        launch(["-uiTestingOpenSampleIPA", "-uiTestingFakeCompanions"])
        XCTAssertTrue(el("ipa.name").waitForExistence(timeout: 15))
        XCTAssertEqual(el("ipa.name").label, "Sample App")
        XCTAssertEqual(el("ipa.bundleID").label, "com.ncom.sampleapp")
        XCTAssertEqual(el("ipa.version").label, "Version 1.2.3 (45)")
        snap("03-ipa-detail")
        tap("ipa.share")
        expectShareSheetAndClose()
        tap("ipa.logSideStore")
        expectToast(contains: "Logged 2 App ID use")
        dismissToast()
        tap("ipa.track")
        expectToast(contains: "Tracking Sample App")
        dismissToast()
        tab("Expiry")
        XCTAssertTrue(el("expiry.row.com.ncom.sampleapp").waitForExistence(timeout: 5))
        XCTAssertTrue(el("expiry.budgetGauge").exists)
        tab("Library")
        tap("ipa.delete")
        tap("ipa.confirmDelete")
        XCTAssertTrue(el("library.empty").waitForExistence(timeout: 5))
    }

    func testImportPickerAndInstallFromLink() {
        launch(["-uiTestingFakeCompanions"])
        tab("Library")
        XCTAssertTrue(el("library.empty").waitForExistence(timeout: 5))
        snap("04-library")
        tap("library.import")
        expectDocumentPickerAndCancel()
        tap("library.fromLink")
        snap("05-from-link")
        tap("link.install")
        XCTAssertTrue(el("link.error").waitForExistence(timeout: 5))
        type("link.field", "not a link")
        tap("link.install")
        XCTAssertEqual(el("link.error").label, "That doesn't look like a web link.")
        type("link.field", "", clear: true)
        type("link.field", "example.com/App.ipa")
        tap("link.install")
        expectToast(contains: "Sent to LiveContainer", value: "livecontainer://install?url=https://example.com/App.ipa")
        dismissToast()
        tap("library.fromLink")
        type("link.field", "https://example.com/apps.json")
        app.segmentedControls["link.target"].buttons["SideStore"].tap()
        tap("link.addSource")
        expectToast(contains: "Sent to SideStore", value: "sidestore://source?url=https://example.com/apps.json")
        dismissToast()
        tap("library.fromLink")
        tap("link.close")
        XCTAssertTrue(el("library.import").waitForExistence(timeout: 5))
    }
}
