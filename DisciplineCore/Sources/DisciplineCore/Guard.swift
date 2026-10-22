import Foundation

/// Ouija Guard: privacy checks Discipline can do itself, without special entitlements.
///  1. Scan an .ipa for bundled tracking/ads/analytics SDKs (framework folders and class names).
///  2. Read the App Privacy Report file iOS exports (Settings → Privacy & Security →
///     App Privacy Report → Save App Activity, an .ndjson file) and summarise it.
/// The SDK list is NCOM's own, built from each vendor's public framework and class names.
public struct TrackerSignature: Hashable, Sendable {
    public enum Category: String, Sendable { case ads = "Ads", analytics = "Analytics", attribution = "Attribution", crash = "Crash reporting", messaging = "Messaging" }
    public let name: String
    public let category: Category
    public let frameworks: [String]       // folder names under <app>/Frameworks/ (without .framework)
    public let symbols: [String]          // distinctive class/symbol name fragments in the binary
    public let domains: [String]          // network domains the SDK reports to

    public static let all: [TrackerSignature] = [
        .init(name: "Google Analytics for Firebase", category: .analytics, frameworks: ["FirebaseAnalytics", "GoogleAppMeasurement"], symbols: ["FIRAnalytics", "APMAnalytics"], domains: ["app-measurement.com", "firebaselogging-pa.googleapis.com"]),
        .init(name: "Google AdMob", category: .ads, frameworks: ["GoogleMobileAds"], symbols: ["GADMobileAds", "GADBannerView"], domains: ["googleads.g.doubleclick.net", "doubleclick.net", "googleadservices.com"]),
        .init(name: "Firebase Crashlytics", category: .crash, frameworks: ["FirebaseCrashlytics"], symbols: ["FIRCrashlytics"], domains: ["crashlytics.com", "firebasecrashlyticssymbols.googleapis.com"]),
        .init(name: "Meta (Facebook) SDK", category: .analytics, frameworks: ["FBSDKCoreKit", "FBAudienceNetwork", "FBSDKLoginKit"], symbols: ["FBSDKAppEvents", "FBAdView"], domains: ["graph.facebook.com", "an.facebook.com"]),
        .init(name: "AppsFlyer", category: .attribution, frameworks: ["AppsFlyerLib"], symbols: ["AppsFlyerLib"], domains: ["appsflyer.com", "appsflyersdk.com"]),
        .init(name: "Adjust", category: .attribution, frameworks: ["AdjustSdk"], symbols: ["ADJConfig", "ADJActivityHandler"], domains: ["adjust.com", "adjust.io"]),
        .init(name: "Branch", category: .attribution, frameworks: ["Branch", "BranchSDK"], symbols: ["BNCServerInterface", "BranchUniversalObject"], domains: ["api2.branch.io", "branch.io"]),
        .init(name: "Amplitude", category: .analytics, frameworks: ["Amplitude", "AmplitudeSwift"], symbols: ["AMPIdentify", "AmplitudeSwift"], domains: ["api2.amplitude.com", "amplitude.com"]),
        .init(name: "Mixpanel", category: .analytics, frameworks: ["Mixpanel"], symbols: ["MixpanelInstance", "MPNetwork"], domains: ["api.mixpanel.com", "mixpanel.com"]),
        .init(name: "Segment", category: .analytics, frameworks: ["Segment", "Analytics"], symbols: ["SEGAnalytics", "SegmentDestination"], domains: ["api.segment.io", "cdn-settings.segment.com"]),
        .init(name: "Flurry", category: .analytics, frameworks: ["Flurry_iOS_SDK", "Flurry"], symbols: ["FlurrySessionBuilder"], domains: ["data.flurry.com"]),
        .init(name: "OneSignal", category: .messaging, frameworks: ["OneSignal", "OneSignalCore"], symbols: ["OSNotificationsManager", "OneSignalCore"], domains: ["onesignal.com"]),
        .init(name: "AppLovin", category: .ads, frameworks: ["AppLovinSDK"], symbols: ["ALSdk", "MAAdView"], domains: ["applovin.com", "applvn.com"]),
        .init(name: "Unity Ads", category: .ads, frameworks: ["UnityAds"], symbols: ["UADSMetaData", "UnityAds"], domains: ["unityads.unity3d.com"]),
        .init(name: "ironSource", category: .ads, frameworks: ["IronSource"], symbols: ["ISNativeAd", "IronSource"], domains: ["supersonicads.com", "ironsrc.mobi"]),
        .init(name: "Pangle / TikTok", category: .ads, frameworks: ["PAGAdSDK", "TikTokBusinessSDK"], symbols: ["PAGBannerAd", "TikTokBusiness"], domains: ["pangle.io", "analytics.tiktok.com"]),
        .init(name: "Braze", category: .messaging, frameworks: ["BrazeKit", "Appboy_iOS_SDK"], symbols: ["Appboy", "BrazeKit"], domains: ["braze.com", "appboy.com"]),
        .init(name: "Sentry", category: .crash, frameworks: ["Sentry"], symbols: ["SentrySDK"], domains: ["sentry.io"]),
        .init(name: "Kochava", category: .attribution, frameworks: ["KochavaTracker", "KochavaCore"], symbols: ["KVATracker"], domains: ["kochava.com"]),
        .init(name: "Singular", category: .attribution, frameworks: ["Singular"], symbols: ["SingularConfig"], domains: ["sdk-api-v1.singular.net"]),
    ]

    public static func forDomain(_ domain: String) -> TrackerSignature? {
        let d = domain.lowercased()
        return all.first { sig in sig.domains.contains { d == $0 || d.hasSuffix("." + $0) } }
    }
}

public struct TrackerFinding: Hashable, Sendable {
    public enum Evidence: String, Sendable { case framework = "Bundled framework", symbol = "Class name in the app binary" }
    public let signature: TrackerSignature
    public let evidence: Evidence
    public let detail: String
}

public enum TrackerScanner {
    /// Scans an .ipa. Framework matches are strong evidence; binary-symbol matches are "likely".
    public static func scan(ipaBytes: [UInt8]) throws -> [TrackerFinding] {
        let zip = try ZipArchive(bytes: ipaBytes)
        let info = try IPAReader.read(bytes: ipaBytes)
        let folder = info.appFolder
        var frameworks = Set<String>()
        for e in zip.entries where e.path.hasPrefix(folder + "Frameworks/") {
            let rest = e.path.dropFirst((folder + "Frameworks/").count)
            if let first = rest.split(separator: "/").first, first.hasSuffix(".framework") {
                frameworks.insert(String(first.dropLast(".framework".count)))
            }
        }
        var findings: [TrackerFinding] = []
        var found = Set<String>()
        for sig in TrackerSignature.all {
            if let fw = sig.frameworks.first(where: { frameworks.contains($0) }) {
                findings.append(TrackerFinding(signature: sig, evidence: .framework, detail: fw + ".framework"))
                found.insert(sig.name)
            }
        }
        // Statically linked SDKs only show up as names inside the main executable.
        if let plistEntry = zip.entry(folder + "Info.plist"),
           let obj = try? PropertyListSerialization.propertyList(from: Data(try zip.data(for: plistEntry)), options: [], format: nil),
           let dict = obj as? [String: Any], let exe = dict["CFBundleExecutable"] as? String,
           let exeEntry = zip.entry(folder + exe), let binary = try? zip.data(for: exeEntry, limit: 512 * 1024 * 1024) {
            for sig in TrackerSignature.all where !found.contains(sig.name) {
                if let sym = sig.symbols.first(where: { contains(binary, Array($0.utf8)) }) {
                    findings.append(TrackerFinding(signature: sig, evidence: .symbol, detail: sym))
                    found.insert(sig.name)
                }
            }
        }
        return findings
    }

    /// Byte substring search (first-byte skip; fine for a few MB).
    static func contains(_ hay: [UInt8], _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, hay.count >= needle.count else { return false }
        let first = needle[0], last = hay.count - needle.count
        var i = 0
        while i <= last {
            if hay[i] == first {
                var j = 1
                while j < needle.count && hay[i + j] == needle[j] { j += 1 }
                if j == needle.count { return true }
            }
            i += 1
        }
        return false
    }
}

/// Summary of an App Privacy Report export (.ndjson: one JSON object per line).
public struct PrivacyReport: Sendable {
    public struct AppSummary: Identifiable, Sendable {
        public var id: String { bundleID }
        public let bundleID: String
        public var sensorAccess: [String: Int]       // category → number of access events
        public var domains: [String: Int]            // domain → hits
        public var trackerDomains: [String: String]  // domain → tracker name
    }

    public let apps: [AppSummary]
    public let lineCount: Int
    public let skippedLines: Int

    public var totalTrackerContacts: Int { apps.reduce(0) { $0 + $1.trackerDomains.count } }

    public static func parse(_ data: Data) -> PrivacyReport {
        var byApp: [String: AppSummary] = [:]
        var lines = 0, skipped = 0
        let text = String(decoding: data, as: UTF8.self)
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            lines += 1
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = obj["type"] as? String else { skipped += 1; continue }
            switch type {
            case "access":
                let accessor = obj["accessor"] as? [String: Any]
                guard let bundle = accessor?["identifier"] as? String, let category = obj["category"] as? String else { skipped += 1; continue }
                // Count each access once (iOS writes intervalBegin and intervalEnd pairs).
                if let kind = obj["kind"] as? String, kind == "intervalEnd" { continue }
                var s = byApp[bundle] ?? AppSummary(bundleID: bundle, sensorAccess: [:], domains: [:], trackerDomains: [:])
                s.sensorAccess[category, default: 0] += 1
                byApp[bundle] = s
            case "networkActivity":
                guard let bundle = obj["bundleID"] as? String, let domain = obj["domain"] as? String else { skipped += 1; continue }
                let hits = obj["hits"] as? Int ?? 1
                var s = byApp[bundle] ?? AppSummary(bundleID: bundle, sensorAccess: [:], domains: [:], trackerDomains: [:])
                s.domains[domain, default: 0] += hits
                if let sig = TrackerSignature.forDomain(domain) { s.trackerDomains[domain] = sig.name }
                byApp[bundle] = s
            default:
                continue
            }
        }
        let apps = byApp.values.sorted { ($0.trackerDomains.count, $0.domains.count) > ($1.trackerDomains.count, $1.domains.count) }
        return PrivacyReport(apps: apps, lineCount: lines, skippedLines: skipped)
    }
}
