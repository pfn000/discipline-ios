import XCTest

final class GuardUITests: DisciplineUITestCase {
    func testTrackerScanPrivacyReportAndSettings() {
        launch(["-uiTestingSeedLibrary", "-uiTestingPrivacyReport"])
        openMore("more.guard")
        tap("guard.scan.com.example.tracked")
        XCTAssertTrue(el("guard.findingsCount").waitForExistence(timeout: 10))
        XCTAssertEqual(el("guard.findingsCount").label, "3 tracker SDKs in Tracked")
        XCTAssertTrue(el("guard.finding.Google AdMob").exists)
        snap("21-guard-scan")
        tap("guard.scan.com.ncom.sampleapp")
        XCTAssertTrue(el("guard.clean").waitForExistence(timeout: 10))
        let summary = el("guard.reportSummary")
        scrollTo(summary)
        XCTAssertEqual(summary.label, "3 apps · 2 tracker domains contacted")
        XCTAssertTrue(el("guard.reportApp.com.example.chat").exists)
        snap("22-guard-report")
        tap("guard.importReport")
        expectDocumentPickerAndCancel()
        tap("guard.openSettings")
        expectOtherApp("com.apple.Preferences")
    }
}

final class LabUITests: DisciplineUITestCase {
    func testHiddenLabUnlockAndEveryControl() {
        launch(["-uiTestingSeedLibrary"])
        tab("More")
        XCTAssertFalse(el("more.lab").exists, "Lab starts hidden")
        let version = el("more.version")
        scrollTo(version)
        for _ in 0..<7 { version.press(forDuration: 0.6) }
        expectToast(contains: "NCOM Lab unlocked")
        dismissToast()
        tap("more.lab")
        XCTAssertTrue(el("lab.tier").waitForExistence(timeout: 5))
        XCTAssertTrue(el("lab.feature.uwb").exists)
        snap("23-lab-capabilities")
        tap("lab.inspectPicker")
        app.buttons["Sample App"].firstMatch.tap()
        tap("lab.inspect")
        let count = el("lab.entitlementCount")
        scrollTo(count)
        XCTAssertEqual(count.label, "4 entitlements")
        XCTAssertTrue(el("lab.unsignable").exists, "NFC entitlement is flagged on a free account")
        snap("24-lab-inspector")
        type("lab.presetName", " Test")
        // Every capability toggle works both ways.
        for id in ["uwb", "ble", "wifiaware", "localnet", "multicast", "wifiinfo", "proximity", "motion", "eaccessory", "multipeer"] {
            let sw = app.switches["lab.toggle.\(id)"].firstMatch
            scrollTo(sw)
            let before = sw.value as? String
            flip("lab.toggle.\(id)")
            XCTAssertNotEqual(sw.value as? String, before, "toggle \(id) changed")
            flip("lab.toggle.\(id)")
            XCTAssertEqual(sw.value as? String, before, "toggle \(id) changed back")
        }
        let status = el("lab.presetStatus")
        flip("lab.toggle.nfc")
        scrollTo(status)
        XCTAssertEqual(status.label, "Everything selected is signable on your account.")
        flip("lab.toggle.nfc")
        XCTAssertEqual(status.label, "Left out for your account: NFC tag reading")
        tap("lab.copy")
        expectToast(contains: "Entitlements copied (0 keys)")
        dismissToast()
        tap("lab.build")
        expectToast(contains: "Built 3 preset files")
        dismissToast()
        snap("25-lab-preset")
        tap("lab.share")
        expectShareSheetAndClose()
        // The list is about 5 screens long and closing the share sheet can leave it scrolled to the top,
        // so walk all the way down to the reset button before tapping it.
        let reset = el("lab.reset")
        var swipes = 0
        while !(reset.exists && reset.isHittable) && swipes < 20 {
            app.swipeUp()
            swipes += 1
        }
        tap("lab.reset")
        XCTAssertFalse(el("lab.share").exists)
        type("lab.presetBundle", "x")
    }
}
