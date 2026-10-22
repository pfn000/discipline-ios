import XCTest

/// Shared helpers: launching with test hooks, tabs, toasts, screenshots, system sheets.
class DisciplineUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + extra
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    }

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    @discardableResult
    func tap(_ id: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let e = el(id)
        if !e.waitForExistence(timeout: timeout) {
            scrollTo(e)
        }
        XCTAssertTrue(e.exists, "missing \(id)", file: file, line: line)
        if !e.isHittable { scrollTo(e) }
        e.tap()
        return e
    }

    func scrollTo(_ e: XCUIElement, maxSwipes: Int = 8) {
        var n = 0
        while (!e.exists || !e.isHittable) && n < maxSwipes {
            app.swipeUp(velocity: .slow)
            n += 1
        }
        n = 0
        while (!e.exists || !e.isHittable) && n < maxSwipes {
            app.swipeDown(velocity: .slow)
            n += 1
        }
    }

    func tab(_ name: String) {
        let b = app.tabBars.buttons[name]
        if b.waitForExistence(timeout: 5) { b.tap() } else { app.buttons[name].firstMatch.tap() }
    }

    /// Waits for the toast and checks its text (label) and optional exact detail (value).
    func expectToast(contains text: String, value: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let toast = el("toast")
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if toast.exists, toast.label.contains(text), value == nil || (toast.value as? String) == value { return }
            usleep(200_000)
        }
        XCTFail("toast '\(toast.exists ? toast.label : "none")' value '\(toast.exists ? (toast.value as? String ?? "") : "")' expected '\(text)' \(value ?? "")",
                file: file, line: line)
    }

    func dismissToast() {
        let t = el("toast")
        if t.exists { t.tap() }
        _ = t.waitForNonExistence(timeout: 3)
    }

    func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: shot)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    /// Asserts another app (Safari, Settings) came to the front, optionally showing `text`, then returns.
    func expectOtherApp(_ bundleID: String, showing text: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let other = XCUIApplication(bundleIdentifier: bundleID)
        XCTAssertTrue(other.wait(for: .runningForeground, timeout: 15), "\(bundleID) did not open", file: file, line: line)
        if let text {
            let match = other.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", text, text)).firstMatch
            XCTAssertTrue(match.waitForExistence(timeout: 15), "\(bundleID) is not showing \(text)", file: file, line: line)
        }
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), file: file, line: line)
    }

    /// The system share sheet appeared; close it.
    func expectShareSheetAndClose(file: StaticString = #filePath, line: UInt = #line) {
        let sheet = app.otherElements["ActivityListView"]
        let close = app.buttons["Close"]
        let appeared = sheet.waitForExistence(timeout: 10) || close.waitForExistence(timeout: 2)
        XCTAssertTrue(appeared, "share sheet did not appear", file: file, line: line)
        if close.exists { close.tap() } else { app.swipeDown(velocity: .fast) }
        _ = sheet.waitForNonExistence(timeout: 5)
    }

    /// The Files document picker appeared; cancel it.
    func expectDocumentPickerAndCancel(file: StaticString = #filePath, line: UInt = #line) {
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 15), "document picker did not appear", file: file, line: line)
        cancel.tap()
        _ = cancel.waitForNonExistence(timeout: 5)
    }

    /// Flips a SwiftUI Toggle by tapping its switch (right edge of the row).
    func flip(_ id: String) {
        let s = app.switches[id].firstMatch
        XCTAssertTrue(s.waitForExistence(timeout: 10), "missing switch \(id)")
        if !s.isHittable { scrollTo(s) }
        let inner = s.switches.firstMatch
        if inner.exists && inner.isHittable { inner.tap() }
        else { s.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
    }

    func type(_ id: String, _ text: String, clear: Bool = false) {
        let f = tap(id)
        if clear, let current = f.value as? String, !current.isEmpty {
            f.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        f.typeText(text)
    }

    func back() {
        let b = app.navigationBars.buttons.element(boundBy: 0)
        if b.waitForExistence(timeout: 5) { b.tap() }
    }

    func openMore(_ id: String) {
        tab("More")
        tap(id)
    }
}
