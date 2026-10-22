import XCTest

/// GitHub to iOS, against the bundled mock API (no network).
final class GitHubUITests: DisciplineUITestCase {
    func testFindDownloadInstallSaveAndUpdate() {
        launch(["-uiTestingMockGitHub", "-uiTestingFakeCompanions"])
        tab("GitHub")
        snap("06-github-empty")
        XCTAssertFalse(el("github.save").isEnabled)
        type("github.field", "https://github.com/ncom/sample-app")
        settle("github.field", "https://github.com/ncom/sample-app")
        tap("github.find")
        XCTAssertTrue(el("github.get.SampleApp.ipa").waitForExistence(timeout: 15))
        XCTAssertTrue(el("github.get.SampleApp-debug.ipa").exists)
        XCTAssertFalse(el("github.get.SampleApp-2.0.0-beta.ipa").exists, "pre-releases hidden by default")
        snap("07-github-releases")
        tap("github.save")
        expectToast(contains: "Saved ncom/sample-app")
        dismissToast()
        tap("github.get.SampleApp.ipa")
        XCTAssertTrue(el("ipa.name").waitForExistence(timeout: 15))
        XCTAssertEqual(el("ipa.name").label, "Sample App")
        snap("08-github-downloaded")
        tap("ipa.installLiveContainer")
        expectToast(contains: "Sent to LiveContainer",
                    value: "livecontainer://install?url=https://github.com/ncom/sample-app/releases/download/v1.2.3/SampleApp.ipa")
        dismissToast()
        tap("ipa.installSideStore")
        expectToast(contains: "Sent to SideStore",
                    value: "sidestore://install?url=https://github.com/ncom/sample-app/releases/download/v1.2.3/SampleApp.ipa")
        dismissToast()
        tab("GitHub")
        tap("github.checkUpdates")
        expectToast(contains: "1 update available")
        dismissToast()
        XCTAssertTrue(el("github.updateBadge.sample-app").waitForExistence(timeout: 5))
        snap("09-github-update-badge")
        tap("github.saved.sample-app")
        XCTAssertTrue(el("github.get.SampleApp.ipa").waitForExistence(timeout: 15))
        XCTAssertFalse(el("github.updateBadge.sample-app").exists, "opening the repo clears the badge")
        tap("github.save")
        expectToast(contains: "Removed ncom/sample-app")
    }

    func testErrorsAreExplained() {
        launch(["-uiTestingMockGitHub"])
        tab("GitHub")
        type("github.field", "nonsense")
        tap("github.find")
        XCTAssertEqual(el("github.error").label, "Paste a GitHub link or owner/repo.")
        type("github.field", "", clear: true)
        type("github.field", "missing/repo")
        settle("github.field", "missing/repo")
        tap("github.find")
        XCTAssertTrue(el("github.error").waitForExistence(timeout: 10))
        XCTAssertTrue(el("github.error").label.contains("404"))
        type("github.field", "", clear: true)
        type("github.field", "ratelimited/repo")
        settle("github.field", "ratelimited/repo")
        tap("github.find")
        let error = el("github.error")
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !(error.exists && error.label.contains("hourly limit")) { usleep(250_000) }
        XCTAssertTrue(error.label.contains("hourly limit"), "rate-limit error shown, got '\(error.exists ? error.label : "none")'")
        snap("10-github-error")
    }
}
