import Foundation
import UserNotifications

/// Schedules local notifications for sub reminders so they still alert the coach
/// when the app is backgrounded or the phone is locked. In-app alerts remain the
/// primary path (and iOS suppresses these banners while the app is foregrounded,
/// so they don't double up); these are the background fallback.
final class GameDayNotifier {
    struct PendingNotification {
        let id: String
        let secondsFromNow: TimeInterval
        let title: String
        let body: String
    }

    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "gameday.reminder."
    /// Ids we've scheduled, so a reschedule can remove exactly them (reminder
    /// ids are UUIDs, so we can't enumerate them otherwise).
    private var scheduledIDs: [String] = []

    /// Prompts for permission once; the system only shows the dialog the first
    /// time. A denial degrades gracefully — nothing is delivered, in-app alerts
    /// still work.
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Replaces all currently-scheduled sub-reminder notifications with `items`.
    func reschedule(_ items: [PendingNotification]) {
        cancelAll()
        for item in items where item.secondsFromNow >= 1 {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: item.secondsFromNow, repeats: false)
            let identifier = identifierPrefix + item.id
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            scheduledIDs.append(identifier)
        }
    }

    func cancelAll() {
        center.removePendingNotificationRequests(withIdentifiers: scheduledIDs)
        scheduledIDs.removeAll()
    }
}
