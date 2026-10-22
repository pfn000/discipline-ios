import Foundation

/// Single place for values that change per build.
enum AppConfig {
    /// TIP_URL: the "Support / Tip" button opens this in Safari (Saidie's Stripe donate link,
    /// pay what you want). A sideloaded app has no App Store in-app purchase.
    static let tipURL = URL(string: "https://donate.stripe.com/fZu28tcfmcuB54F81k8k801")!

    static let appName = "Discipline"
    static let urlScheme = "discipline"
    static let sourceCodeNote = "Private build for Saidie / NCOM."
}

/// Switches that exist only for the UI test run (passed as launch arguments by the tests).
enum TestHooks {
    static let args = ProcessInfo.processInfo.arguments
    /// Fresh, in-memory-backed store on every launch.
    static var isUITesting: Bool { args.contains("-uiTesting") }
    /// Pretend LocalDevVPN/SideStore/LiveContainer are installed and record the URL we would
    /// open instead of opening it (the simulator has none of them installed).
    static var fakeCompanions: Bool { args.contains("-uiTestingFakeCompanions") }
    /// Serve GitHub API calls and .ipa downloads from bundled fixtures.
    static var mockGitHub: Bool { args.contains("-uiTestingMockGitHub") }
    /// Behave as if the bundled Sample.ipa was opened from Files ("Open in Discipline").
    static var openSampleIPA: Bool { args.contains("-uiTestingOpenSampleIPA") }

    /// Import the bundled Sample.ipa and Tracked.ipa into the Library at launch.
    static var seedLibrary: Bool { args.contains("-uiTestingSeedLibrary") }

    static var sampleIPAURL: URL? { Bundle.main.url(forResource: "Sample", withExtension: "ipa") }
}
