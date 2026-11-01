import XCTest
import Foundation

/// Ouija v0.3 palette rule (Saidie, Nov 1 2026: "that purple too often"): no purple, violet or indigo anywhere in
/// Ouija's code, no stray hand-made colours, and one style file holding the tokens. Runs against the checked-out sources.
final class OuijaPaletteTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func swiftFiles(_ dir: String) -> [URL] {
        guard let en = FileManager.default.enumerator(at: root.appendingPathComponent(dir), includingPropertiesForKeys: nil) else { return [] }
        return en.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    func testNoPurpleAnywhereInOuija() throws {
        let files = swiftFiles("Ouija") + swiftFiles("OuijaWidgets") + swiftFiles("OuijaUITests")
        try XCTSkipIf(files.isEmpty, "Ouija sources aren't next to the package here")
        let banned = try NSRegularExpression(pattern: "purple|violet|indigo|magenta|lavender", options: .caseInsensitive)
        var hits: [String] = []
        for f in files + swiftFiles("Shared").filter({ $0.lastPathComponent.hasPrefix("Ouija") }) {
            let text = try String(contentsOf: f, encoding: .utf8)
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let l = String(line)
                if l.trimmingCharacters(in: .whitespaces).hasPrefix("//") || l.contains("no purple") { continue }
                if l.contains("\"") && (l.contains("Text(") || l.contains("assertNoPurple")) { continue }
                if banned.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)) != nil { hits.append("\(f.lastPathComponent):\(i + 1): \(l)") }
            }
        }
        XCTAssertTrue(hits.isEmpty, "purple is gone from Ouija:\n" + hits.joined(separator: "\n"))
    }

    func testOnlyTheStyleFileBuildsColours() throws {
        let files = swiftFiles("Ouija") + swiftFiles("OuijaWidgets")
        try XCTSkipIf(files.isEmpty, "Ouija sources aren't next to the package here")
        let raw = try NSRegularExpression(pattern: "Color\\(red:|Color\\(hue|UIColor\\(red|#[0-9A-Fa-f]{6}\\b|\\.(orange|blue|pink|yellow|mint|teal|cyan|brown)\\b")
        var hits: [String] = []
        for f in files {
            let text = try String(contentsOf: f, encoding: .utf8)
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let l = String(line)
                if l.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                if raw.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)) != nil { hits.append("\(f.lastPathComponent):\(i + 1): \(l)") }
            }
        }
        XCTAssertTrue(hits.isEmpty, "colours come from Shared/OuijaStyle.swift only:\n" + hits.joined(separator: "\n"))
    }

    func testStyleFileHasTheLightAndDarkTokens() throws {
        let url = root.appendingPathComponent("Shared/OuijaStyle.swift")
        try XCTSkipIf(!FileManager.default.fileExists(atPath: url.path), "style file isn't next to the package here")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("static let accent = dynamic(light: .black, dark: .white)"), "accent: black in light, white in dark")
        XCTAssertTrue(text.contains("static let ok ") && text.contains("static let bad "), "green yes, red no")
        let code = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n").lowercased()
        XCTAssertFalse(code.contains("purple") || code.contains("violet") || code.contains("indigo"), "no purple token")
    }
}
