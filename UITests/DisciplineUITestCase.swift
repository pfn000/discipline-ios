import XCTest

/// Shared helpers: launching with test hooks, tabs, toasts, screenshots, system sheets.
class DisciplineUITestCase: XCTestCase {
    var app: XCUIApplication!

    private var dumpedFailure = false

    override func setUp() {
        continueAfterFailure = false
    }

    /// On the first failure of a test, save the screen and the full element tree next to the screenshots,
    /// so a CI failure can be read without the result bundle.
    override func record(_ issue: XCTIssue) {
        if !dumpedFailure, let app, let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            dumpedFailure = true
            let base = URL(fileURLWithPath: dir).appendingPathComponent("FAIL-\(name.filter { $0.isLetter || $0.isNumber })")
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let text = "\(issue.compactDescription)\n\n\(app.debugDescription)"
            try? text.write(to: base.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: base.appendingPathExtension("png"))
        }
        super.record(issue)
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

    /// Closes the keyboard if one is up (it covers the tab bar).
    func hideKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        for key in ["return", "Return", "done", "Done", "Go", "go", "Search", "search"] {
            let k = app.keyboards.buttons[key].firstMatch
            if k.exists && k.isHittable { k.tap(); break }
        }
        if app.keyboards.firstMatch.exists {
            app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
    }

    func tab(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        hideKeyboard()
        let b = app.tabBars.buttons[name]
        if b.waitForExistence(timeout: 5) { b.tap(); return }
        // A minimized tab bar (scrolled down) shows only the current tab: scroll back up to expand it.
        for _ in 0..<3 where !b.exists { app.swipeDown(velocity: .slow) }
        if b.waitForExistence(timeout: 3) { b.tap(); return }
        let any = app.buttons.matching(NSPredicate(format: "label == %@ AND elementType != %ld", name, Int(XCUIElement.ElementType.key.rawValue))).firstMatch
        XCTAssertTrue(any.waitForExistence(timeout: 3), "tab \(name) not found", file: file, line: line)
        any.tap()
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
        hideKeyboard() // the keyboard covers rows at the bottom of the screen
        let s = app.switches[id].firstMatch
        // Lists unload rows that are far off screen, so scroll to it first.
        if !s.waitForExistence(timeout: 3) { scrollTo(s, maxSwipes: 10) }
        XCTAssertTrue(s.waitForExistence(timeout: 5), "missing switch \(id)")
        if !s.isHittable { scrollTo(s) }
        let inner = s.switches.firstMatch
        if inner.exists && inner.isHittable { inner.tap() }
        else { s.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
    }

    func type(_ id: String, _ text: String, clear: Bool = false) {
        let f = tap(id)
        let before = f.value as? String ?? ""
        let wasEmpty = before.isEmpty || before == (f.placeholderValue ?? "")
        if clear, !wasEmpty {
            // Put the cursor at the end of the text before deleting.
            f.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
            f.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: before.count + 4))
        }
        typeChunks(f, text)
        // The simulator keyboard sometimes drops a repeated letter ("https" -> "hps"). Check and retype once.
        if (wasEmpty || clear), !text.isEmpty, (f.value as? String) != text {
            let now = f.value as? String ?? ""
            f.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
            f.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: now.count + 4))
            for c in text { f.typeText(String(c)); usleep(120_000) }
        }
    }

    /// Types in pieces split between doubled letters, so no key is pressed twice in a row within one call.
    func typeChunks(_ f: XCUIElement, _ text: String) {
        var chunk = ""
        for c in text {
            if let last = chunk.last, last == c {
                f.typeText(chunk)
                usleep(150_000)
                chunk = ""
            }
            chunk.append(c)
        }
        if !chunk.isEmpty { f.typeText(chunk) }
    }

    /// Waits until a text field shows the typed text, then gives SwiftUI a moment to commit it to the model.
    func settle(_ id: String, _ text: String) {
        let f = el(id)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, (f.value as? String) != text { usleep(200_000) }
        usleep(700_000)
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
