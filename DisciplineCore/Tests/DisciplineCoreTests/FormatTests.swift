import XCTest
@testable import DisciplineCore

final class FormatTests: XCTestCase {
    func testDeepLinksMatchUpstreamHandlers() throws {
        XCTAssertEqual(DeepLinks.enableVPN().absoluteString, "localdevvpn://enable?scheme=discipline")
        XCTAssertEqual(DeepLinks.enableVPN(returnTo: "sidestore").absoluteString, "localdevvpn://enable?scheme=sidestore")
        XCTAssertEqual(DeepLinks.disableVPN(returnTo: nil).absoluteString, "localdevvpn://disable")
        let ipa = URL(string: "https://github.com/a/b/releases/download/v1/App.ipa?x=1&y=2")!
        let ss = try DeepLinks.install(ipa: ipa, with: .sideStore)
        XCTAssertEqual(ss.scheme, "sidestore"); XCTAssertEqual(ss.host, "install")
        // The receiving app reads `url` with URLComponents; it must come back byte for byte.
        XCTAssertEqual(DeepLinks.queryValue("url", in: ss), ipa.absoluteString)
        let lc = try DeepLinks.install(ipa: ipa, with: .liveContainer)
        XCTAssertEqual(lc.host, "install"); XCTAssertEqual(DeepLinks.queryValue("url", in: lc), ipa.absoluteString)
        XCTAssertThrowsError(try DeepLinks.install(ipa: ipa, with: .localDevVPN))
        let src = try DeepLinks.addSource(URL(string: "https://example.com/apps.json")!, to: .liveContainer)
        XCTAssertEqual(src.absoluteString, "livecontainer://source?url=https://example.com/apps.json")
        let launch = try DeepLinks.launchInLiveContainer(bundleID: "com.ncom.sampleapp")
        XCTAssertEqual(launch.absoluteString, "livecontainer://livecontainer-launch?bundle-name=com.ncom.sampleapp")
        XCTAssertThrowsError(try DeepLinks.launchInLiveContainer(bundleID: "  "))
        XCTAssertThrowsError(try DeepLinks.launchInLiveContainer(bundleID: "a b"))
    }

    func testNormalizeWebURL() throws {
        XCTAssertEqual(try DeepLinks.normalizeWebURL(" example.com/a.ipa ").absoluteString, "https://example.com/a.ipa")
        XCTAssertEqual(try DeepLinks.normalizeWebURL("http://x.io/b").absoluteString, "http://x.io/b")
        XCTAssertThrowsError(try DeepLinks.normalizeWebURL("")) { XCTAssertEqual($0 as? DeepLinkError, .emptyInput) }
        XCTAssertThrowsError(try DeepLinks.normalizeWebURL("ftp://x.io/b")) { XCTAssertEqual($0 as? DeepLinkError, .notAWebURL) }
        XCTAssertThrowsError(try DeepLinks.normalizeWebURL("not a url"))
    }

    func testCompanionsHaveOfficialSources() {
        XCTAssertEqual(Companion.allCases.count, 3)
        XCTAssertEqual(Companion.localDevVPN.officialURL.host, "apps.apple.com")
        XCTAssertEqual(Companion.liveContainer.openURL.absoluteString, "livecontainer://")
    }

    func testInflateAgainstZlib() throws {
        let corpus = [UInt8](try fixture("corpus.bin"))
        XCTAssertEqual(try Inflate.inflate([UInt8](try fixture("corpus.deflate"))), corpus)
        XCTAssertEqual(try Inflate.inflate([UInt8](try fixture("stored.deflate"))), Array(corpus[0..<5000]))
        XCTAssertEqual(String(decoding: try Inflate.inflate([UInt8](try fixture("short.deflate"))), as: UTF8.self), "hello hello hello")
        XCTAssertThrowsError(try Inflate.inflate([UInt8](try fixture("corpus.deflate")), limit: 100)) {
            XCTAssertEqual($0 as? InflateError, .outputTooLarge)
        }
        XCTAssertThrowsError(try Inflate.inflate([0x07])) // block type 3 is invalid
        XCTAssertThrowsError(try Inflate.inflate([]))
    }

    func testIPAReader() throws {
        let info = try IPAReader.read(bytes: [UInt8](try fixture("Sample.ipa")))
        XCTAssertEqual(info.displayName, "Sample App")
        XCTAssertEqual(info.bundleID, "com.ncom.sampleapp")
        XCTAssertEqual(info.version, "1.2.3")
        XCTAssertEqual(info.build, "45")
        XCTAssertEqual(info.minimumOS, "17.0")
        XCTAssertEqual(info.appFolder, "Payload/SampleApp.app/")
        XCTAssertTrue(info.hasExtensions)
        XCTAssertEqual(info.extensionCount, 1)
        XCTAssertEqual(info.appIDCost, 2)
        let icon = try XCTUnwrap(info.iconPNG)
        XCTAssertEqual(Array(icon.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "picked the real PNG (largest named icon)")
        XCTAssertGreaterThan(icon.count, 200)
    }

    func testIPAReaderRejectsJunk() {
        XCTAssertThrowsError(try IPAReader.read(bytes: Array("not a zip at all, definitely not".utf8))) {
            XCTAssertEqual($0 as? IPAError, .notAZip)
        }
    }

    func testGitHubRefParsing() {
        XCTAssertEqual(GitHubRepoRef.parse("LiveContainer/LiveContainer")?.fullName, "LiveContainer/LiveContainer")
        XCTAssertEqual(GitHubRepoRef.parse("https://github.com/SideStore/SideStore.git")?.repo, "SideStore")
        XCTAssertEqual(GitHubRepoRef.parse("github.com/a-b/c_d/releases")?.fullName, "a-b/c_d")
        let tagged = GitHubRepoRef.parse("https://www.github.com/ncom/sample-app/releases/tag/v1.2.3?foo=1")
        XCTAssertEqual(tagged?.tag, "v1.2.3")
        XCTAssertEqual(tagged?.releasesAPI.absoluteString, "https://api.github.com/repos/ncom/sample-app/releases?per_page=20")
        XCTAssertNil(GitHubRepoRef.parse("https://gitlab.com/a/b"))
        XCTAssertNil(GitHubRepoRef.parse("justone"))
        XCTAssertNil(GitHubRepoRef.parse(""))
        XCTAssertEqual(GitHubRepoRef.parse("A/B")?.id, "a/b")
    }

    func testReleasesDecodeAndPick() throws {
        let rel = try GitHubRelease.decodeList(try fixture("releases.json"))
        XCTAssertEqual(rel.count, 3)
        XCTAssertEqual(ReleasePicker.newestWithIPA(rel, includePrereleases: false)?.tagName, "v1.2.3")
        XCTAssertEqual(ReleasePicker.newestWithIPA(rel, includePrereleases: true)?.tagName, "v2.0.0-beta")
        let stable = rel[1]
        XCTAssertEqual(stable.ipaAssets.count, 2)
        XCTAssertEqual(ReleasePicker.preferredAsset(stable.assets)?.name, "SampleApp.ipa")
        XCTAssertEqual(rel[2].title, "v1.0.0")
        var saved = SavedRepo(ref: GitHubRepoRef(owner: "ncom", repo: "sample-app"), lastSeenTag: "v1.0.0", latestKnownTag: "v1.2.3")
        XCTAssertTrue(saved.hasUpdate)
        saved.lastSeenTag = "v1.2.3"
        XCTAssertFalse(saved.hasUpdate)
        let rl = RateLimit(headers: ["X-RateLimit-Remaining": "59", "x-ratelimit-limit": "60", "X-RateLimit-Reset": "1790000000"])
        XCTAssertEqual(rl.remaining, 59); XCTAssertEqual(rl.limit, 60); XCTAssertEqual(rl.reset, t0)
    }

    func testAltSource() throws {
        let s = try AltSource.decode(try fixture("source.json"))
        XCTAssertEqual(s.apps.count, 2)
        XCTAssertEqual(s.apps[0].latest?.version, "1.2.3")
        XCTAssertEqual(s.apps[1].latest?.downloadURL, "https://example.com/Legacy.ipa")
        XCTAssertTrue(s.apps[0].runs(on: OSVersion(27, 2)))
        XCTAssertFalse(s.apps[1].runs(on: OSVersion(27, 2)))
    }
}
