import XCTest
@testable import DisciplineCore

final class PolicyTests: XCTestCase {
    func testTierLimits() {
        XCTAssertEqual(AccountTier.free.signatureLifetimeDays, 7)
        XCTAssertEqual(AccountTier.paid.signatureLifetimeDays, 365)
        XCTAssertEqual(AccountTier.free.activeAppLimit, 3)
        XCTAssertNil(AccountTier.paid.activeAppLimit)
        XCTAssertEqual(AccountTier.free.appIDsPerWeek, 10)
    }

    func testCapabilitiesMatchApplesTable() {
        XCTAssertFalse(Capability.networkExtensions.available(on: .free))
        XCTAssertFalse(Capability.familyControlsDevelopment.available(on: .free))
        XCTAssertFalse(Capability.pushNotifications.available(on: .free))
        XCTAssertTrue(Capability.appGroups.available(on: .free))
        XCTAssertTrue(Capability.backgroundModes.available(on: .free))
        XCTAssertTrue(Capability.networkExtensions.available(on: .paid))
    }

    func testEditions() {
        XCTAssertTrue(DisciplineEdition.standard.canBeSigned(by: .free))
        XCTAssertFalse(DisciplineEdition.pro.canBeSigned(by: .free))
        XCTAssertTrue(DisciplineEdition.pro.canBeSigned(by: .paid))
        XCTAssertEqual(DisciplineEdition.recommended(for: .free), .standard)
        XCTAssertEqual(DisciplineEdition.pro.appIDCost, 2)
    }

    func testExpiryStatusAndReminders() {
        let app = TrackedApp(name: "LiveContainer", bundleID: "com.kdt.livecontainer", signedAt: t0, tier: .free)
        XCTAssertEqual(app.expiresAt, t0.addingTimeInterval(7 * 86_400))
        let tr = ExpiryTracker()
        if case .healthy = tr.status(of: app, now: t0.addingTimeInterval(86_400)) {} else { XCTFail("day 1 healthy") }
        if case .refreshSoon = tr.status(of: app, now: t0.addingTimeInterval(6 * 86_400)) {} else { XCTFail("day 6 refresh soon") }
        if case .expired = tr.status(of: app, now: t0.addingTimeInterval(8 * 86_400)) {} else { XCTFail("day 8 expired") }
        let r = tr.reminderDates(for: app, now: t0)
        XCTAssertEqual(r.count, 3)
        XCTAssertEqual(r.first, app.expiresAt.addingTimeInterval(-48 * 3600))
        XCTAssertEqual(tr.reminderDates(for: app, now: app.expiresAt.addingTimeInterval(-3 * 3600)).count, 1)
        let paid = TrackedApp(name: "X", bundleID: "x", signedAt: t0, tier: .paid)
        XCTAssertEqual(tr.nextToExpire([paid, app])?.bundleID, "com.kdt.livecontainer")
        XCTAssertEqual(ExpiryTracker.shortText(.healthy(remaining: 6 * 86_400 + 3 * 3600 + 59)), "6d 3h")
        XCTAssertEqual(ExpiryTracker.shortText(.refreshSoon(remaining: 5 * 3600 + 12 * 60)), "5h 12m")
        XCTAssertEqual(ExpiryTracker.shortText(.refreshSoon(remaining: 59)), "0m")
        XCTAssertEqual(ExpiryTracker.shortText(.expired(since: 1)), "expired")
    }

    func testAppIDBudgetRollingWindow() {
        var b = AppIDBudget(tier: .free)
        for d in 0..<10 { b.record(t0.addingTimeInterval(Double(d) * 3600)) }
        XCTAssertEqual(b.used(now: t0.addingTimeInterval(10 * 3600)), 10)
        XCTAssertEqual(b.remaining(now: t0.addingTimeInterval(10 * 3600)), 0)
        XCTAssertFalse(b.canRegister(now: t0.addingTimeInterval(10 * 3600)))
        XCTAssertEqual(b.nextAvailable(now: t0.addingTimeInterval(10 * 3600)), t0.addingTimeInterval(7 * 86_400))
        XCTAssertEqual(b.nextAvailable(2, now: t0.addingTimeInterval(10 * 3600)), t0.addingTimeInterval(7 * 86_400 + 3600))
        XCTAssertNil(b.nextAvailable(11, now: t0.addingTimeInterval(10 * 3600)))
        XCTAssertTrue(b.canRegister(now: t0.addingTimeInterval(7 * 86_400 + 1)))
        XCTAssertNil(AppIDBudget(tier: .paid).remaining(now: t0))
        XCTAssertTrue(AppIDBudget(tier: .paid).canRegister(50, now: t0))
    }

    func testCompatibility() {
        XCTAssertEqual(OSVersion("27.2")?.description, "27.2")
        XCTAssertEqual(OSVersion("26.4.1"), OSVersion(26, 4, 1))
        XCTAssertNil(OSVersion("27.x"))
        XCTAssertTrue(OSVersion(27, 0, 1) > OSVersion(27, 0))
        let r = CompatibilityReport.evaluate(OSVersion(27, 2), isBeta: true)
        XCTAssertEqual(r.bootstrap, .onDeviceSupported)
        XCTAssertTrue(r.disciplineRuns); XCTAssertTrue(r.needsInSubnetPeer); XCTAssertTrue(r.isBeta)
        XCTAssertTrue(r.notes.contains { $0.contains("Beta") })
        XCTAssertEqual(CompatibilityReport.evaluate(OSVersion(27, 0)).bootstrap, .needsPairingFileFromComputer)
        XCTAssertEqual(CompatibilityReport.evaluate(OSVersion(18, 6)).bootstrap, .needsPairingFileFromComputer)
        XCTAssertFalse(CompatibilityReport.evaluate(OSVersion(18, 6)).disciplineRuns)
        XCTAssertEqual(CompatibilityReport.evaluate(OSVersion(17, 3)).bootstrap, .unsupported)
    }

    func testSetupPlan() {
        var o = SetupPlan.Observations(installed: [], tunnel: .notConnected, trackedApps: 0, os: OSVersion(27, 2))
        var plan = SetupPlan(o)
        XCTAssertEqual(plan.steps.count, 6)
        XCTAssertEqual(plan.completed, 1)
        XCTAssertEqual(plan.nextStep?.id, .localDevVPN)
        XCTAssertEqual(plan.steps.first { $0.id == .vpnConnected }?.state, .blocked)
        o.installed = [.localDevVPN, .sideStore, .liveContainer]
        o.tunnel = .connected(interface: "utun4", address: IPv4Address("10.7.1.1")!)
        o.trackedApps = 2
        plan = SetupPlan(o)
        XCTAssertEqual(plan.completed, 6)
        XCTAssertNil(plan.nextStep)
    }
}
