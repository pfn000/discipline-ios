import Foundation

/// The words and icons on the Ouija Board screens. NCOM's own content (from the concept sketches)
/// is private: CI copies `ouija-content.json` into the app from NCOM's private storage at build time,
/// and it is never committed to this repository. Without it the screens use the neutral
/// fallback below, so the code and its layout still build and run.
struct OuijaContent: Codable {
    struct Tile: Codable, Identifiable {
        let id: Int
        let symbols: [String]   // SF Symbols standing in for drawn icons
        let text: String?       // words written on the tile, if any
        let caption: String?    // small line under the icon
        let action: String?     // "import" opens the .ipa picker
    }

    struct PairOption: Codable, Identifiable, Hashable {
        let id: String
        let title: String
        let symbol: String
        let kind: String        // "localNetwork" (real Bonjour search), "uwb", or "hardware"
    }

    var source: String          // "private" for NCOM's file, "fallback" for the built-in one
    var deviceName: String
    var deviceSymbol: String
    var attentionSlide: String
    var agreementText: String
    var agreeButton: String
    var signedInCaption: String
    var shellTitle: String
    var tiles: [Tile]
    var pairTitle: String
    var pairInstructions: String
    var pairOptions: [PairOption]
    var ringSigned: String
    var sessionUser: String
    var sessionAlt: String

    static let shared: OuijaContent = load()

    static func load() -> OuijaContent {
        guard let url = Bundle.main.url(forResource: "ouija-content", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let content = try? JSONDecoder().decode(OuijaContent.self, from: data) else { return fallback }
        return content
    }

    static let fallback = OuijaContent(
        source: "fallback",
        deviceName: "Prototype device",
        deviceSymbol: "cpu",
        attentionSlide: "Slide to confirm",
        agreementText: "Ouija Board features are NCOM developer prototypes.",
        agreeButton: "I agree",
        signedInCaption: "Signed in on this iPhone",
        shellTitle: "Shell (app only)",
        tiles: (1...11).map { Tile(id: $0, symbols: ["square.dashed"], text: nil, caption: "\($0)", action: nil) }
            + [Tile(id: 12, symbols: ["plus"], text: nil, caption: "Add test app", action: "import")],
        pairTitle: "Pair",
        pairInstructions: "Choose how to pair, then start.",
        pairOptions: [PairOption(id: "opt1", title: "Local network", symbol: "network", kind: "localNetwork")],
        ringSigned: "Signed by NCOM Systems",
        sessionUser: "Profile",
        sessionAlt: "Session")
}
