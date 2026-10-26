import Foundation
import DisciplineCore

/// Single place for values that change per build.
enum AppConfig {
    /// TIP_URL: the "Support / Tip" button opens this in Safari (Saidie's Stripe donate link,
    /// pay what you want). A sideloaded app has no App Store in-app purchase.
    static let tipURL = URL(string: "https://donate.stripe.com/fZu28tcfmcuB54F81k8k801")!

    static let appName = "Discipline"
    static let urlScheme = "discipline"
    static let sourceCodeNote = "Built for Saidie / NCOM. Source: github.com/pfn000/discipline-ios."

    /// Discipline checks this repo's GitHub Releases for its own updates.
    static let updateRepo = GitHubRepoRef(owner: "pfn000", repo: "discipline-ios")

    /// Public half of NCOM's Ouija Board signing key (Ed25519, raw 32 bytes, base64url).
    /// The private half never ships in the app or the repo; only codes it signed unlock.
    static let ouijaPublicKeys = ["JFb_lSzDdsvfjjiOfDxJgZgAADqPj7u03UUWn0w1Ir0"]
    /// Accepted only while UI tests run (-uiTesting): signs the fixture code in the tests.
    static let ouijaTestPublicKey = "qNMlfqG-kdjedq5CxZDm10U9n0g9swF1bM1oYsbfQQU"

    static var ouijaKeys: [Data] {
        (ouijaPublicKeys + (TestHooks.isUITesting ? [ouijaTestPublicKey] : [])).compactMap(OuijaCode.base64URLDecode)
    }

    /// Background check identifier (Info.plist BGTaskSchedulerPermittedIdentifiers).
    static let backgroundRefreshID = "com.ncom.discipline.refresh"
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

    /// The value after a launch argument ("-flag value").
    static func value(after flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    /// Keep app state in a named folder so a relaunch sees it.
    static var stateDir: String? { value(after: "-uiTestingStateDir") }
    /// Empty that named folder first.
    static var resetState: Bool { args.contains("-uiTestingResetState") }
    /// Open discipline://ouija?code=<value> at launch, as if the Camera app scanned the QR.
    static var ouijaCode: String? { value(after: "-uiTestingOuijaCode") }
    /// Start with the Ouija Board already unlocked.
    static var ouijaUnlocked: Bool { args.contains("-uiTestingOuijaUnlocked") }
    /// Track one app signed 6 days ago (due for refresh).
    static var dueApp: Bool { args.contains("-uiTestingDueApp") }
    /// Import the bundled Signed.ipa (it carries a provisioning profile) at launch.
    static var seedSigned: Bool { args.contains("-uiTestingSeedSigned") }
    /// Run the launch-time update check even under UI tests (normally off so tests never touch the network).
    static var autoCheck: Bool { args.contains("-uiTestingAutoCheck") }
    /// Save two GitHub repos at launch: missing/repo (answers 404) first, then ncom/sample-app.
    static var seedRepos: Bool { args.contains("-uiTestingSeedRepos") }
    /// Turn auto-download of updates on at launch.
    static var autoDownload: Bool { args.contains("-uiTestingAutoDownload") }
    /// Turn auto refresh off at launch (it is on by default).
    static var autoRefreshOff: Bool { args.contains("-uiTestingAutoRefreshOff") }
}
