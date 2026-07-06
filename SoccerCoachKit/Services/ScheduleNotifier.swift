import Foundation
import UserNotifications

/// A single reminder to fire before a scheduled item.
struct PlannedReminder: Equatable {
    let id: String
    let fireDate: Date
    let title: String
    let body: String
}

/// Pure logic that turns the schedule into a set of reminders, so it can be
/// tested without touching `UNUserNotificationCenter`.
enum ScheduleReminderPlanner {
    /// Reminders for upcoming games, sessions, and events, each firing
    /// `leadMinutes` before its start. Reminders whose fire time has already
    /// passed are dropped; the soonest `limit` are returned (iOS caps pending
    /// notifications, and the near future is what matters).
    static func reminders(
        games: [GameEvent],
        sessions: [TrainingSession],
        events: [TeamEvent],
        teamName: (UUID) -> String,
        leadMinutes: Int,
        now: Date,
        limit: Int = 30
    ) -> [PlannedReminder] {
        let lead = TimeInterval(leadMinutes * 60)
        var planned: [PlannedReminder] = []

        for game in games {
            planned.append(PlannedReminder(
                id: "game.\(game.id.uuidString)",
                fireDate: game.date.addingTimeInterval(-lead),
                title: "Upcoming game",
                body: "\(teamName(game.teamID)) vs \(game.opponent) — \(when(game.date))"
            ))
        }
        for session in sessions {
            planned.append(PlannedReminder(
                id: "session.\(session.id.uuidString)",
                fireDate: session.date.addingTimeInterval(-lead),
                title: "Training session",
                body: "\(teamName(session.teamID)): \(session.title) — \(when(session.date))"
            ))
        }
        for event in events {
            planned.append(PlannedReminder(
                id: "event.\(event.id.uuidString)",
                fireDate: event.date.addingTimeInterval(-lead),
                title: event.kind.rawValue,
                body: "\(teamName(event.teamID)): \(event.title) — \(when(event.date))"
            ))
        }

        return planned
            .filter { $0.fireDate > now }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(limit)
            .map { $0 }
    }

    private static func when(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// Schedules the planned reminders as local notifications, replacing any it
/// scheduled before (identified by a shared prefix).
final class ScheduleNotifier {
    private let center = UNUserNotificationCenter.current()
    private let prefix = "schedule.reminder."

    /// Prompts for permission once; a denial degrades gracefully (nothing fires).
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Replaces the previously-scheduled schedule reminders with `reminders`.
    func apply(_ reminders: [PlannedReminder]) {
        let center = center
        let prefix = prefix
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)

            for reminder in reminders {
                let content = UNMutableNotificationContent()
                content.title = reminder.title
                content.body = reminder.body
                content.sound = .default

                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: reminder.fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                center.add(UNNotificationRequest(
                    identifier: prefix + reminder.id, content: content, trigger: trigger))
            }
        }
    }

    func cancelAll() {
        let center = center
        let prefix = prefix
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }
    }
}
