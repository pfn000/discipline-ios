import Foundation
import UserNotifications
import DisciplineCore

/// Local notifications for signature expiry. Local notifications need no entitlement, so they
/// work on a free Apple ID (remote push does not).
enum ReminderService {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Replaces all Discipline reminders with fresh ones for the given apps.
    @discardableResult
    static func reschedule(_ apps: [TrackedApp], tracker: ExpiryTracker = ExpiryTracker(), now: Date = Date()) async -> Int {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        var count = 0
        for app in apps {
            for date in tracker.reminderDates(for: app, now: now) {
                let content = UNMutableNotificationContent()
                content.title = "Refresh \(app.name)"
                let left = ExpiryTracker.shortText(.refreshSoon(remaining: app.expiresAt.timeIntervalSince(date)))
                content.body = "Its signature runs out in \(left). Turn on LocalDevVPN and tap Refresh All."
                content.sound = .default
                content.userInfo = ["url": "discipline://refresh"]
                let interval = max(1, date.timeIntervalSince(now))
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                let id = "discipline.\(app.bundleID).\(Int(date.timeIntervalSince1970))"
                try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                count += 1
            }
        }
        return count
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    static func pendingCount() async -> Int {
        await UNUserNotificationCenter.current().pendingNotificationRequests().count
    }
}
