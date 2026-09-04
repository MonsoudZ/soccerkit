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
        // Optional, because a training session need not belong to a team — see
        // TrainingSession.teamID. AppStore.teamName(for:) has always taken an optional
        // and answers with a placeholder; this is the parameter catching up with it.
        teamName: (UUID?) -> String,
        leadMinutes: Int,
        now: Date,
        limit: Int = 30
    ) -> [PlannedReminder] {
        let lead = TimeInterval(leadMinutes * 60)
        // Soonest we can usefully schedule; an event happening within the lead
        // window still gets a reminder now rather than being dropped.
        let earliest = now.addingTimeInterval(60)

        func plan(id: String, date: Date, title: String, body: String) -> PlannedReminder? {
            guard date > now else { return nil } // already started
            return PlannedReminder(
                id: id,
                fireDate: max(date.addingTimeInterval(-lead), earliest),
                title: title,
                body: body
            )
        }

        var planned: [PlannedReminder?] = []
        for game in games {
            planned.append(plan(
                id: "game.\(game.id.uuidString)", date: game.date, title: "Upcoming game",
                body: "\(teamName(game.teamID)) vs \(game.opponent) — \(when(game.date))"))
        }
        for session in sessions {
            planned.append(plan(
                id: "session.\(session.id.uuidString)", date: session.date, title: "Training session",
                body: "\(teamName(session.teamID)): \(session.title) — \(when(session.date))"))
        }
        for event in events {
            planned.append(plan(
                id: "event.\(event.id.uuidString)", date: event.date, title: event.kind.rawValue,
                body: "\(teamName(event.teamID)): \(event.title) — \(when(event.date))"))
        }

        return planned
            .compactMap { $0 }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(limit)
            .map { $0 }
    }

    private static func when(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// The part of `UNUserNotificationCenter` that the app's two notifiers use.
///
/// Behind a protocol so their ordering guarantee can be tested: the real centre
/// can't be driven into an overlap on demand, and the overlap is the whole bug.
/// Deliberately thin — it deals in primitives, and the notification objects are
/// built on the far side of it.
///
/// The two `add`s differ by trigger, because the two callers mean different
/// things by "when". A schedule reminder fires at a wall-clock date that can be
/// days out, so it matches date components and minute granularity is plenty. A
/// sub reminder fires a counted number of seconds from now, measured against a
/// running match clock, and rounding that to the minute would move it.
@MainActor
protocol NotificationCenterScheduling {
    func pendingIdentifiers() async -> [String]
    func removePendingRequests(withIdentifiers identifiers: [String])
    func add(identifier: String, title: String, body: String, fireDate: Date)
    func add(identifier: String, title: String, body: String, secondsFromNow: TimeInterval)
    /// Prompts for permission if it hasn't been asked for yet, and reports
    /// where things stand once the coach has answered. The answer was
    /// previously discarded, which is how a denial became invisible.
    func requestAuthorization() async -> NotificationAuthorization
    func authorizationStatus() async -> NotificationAuthorization
}

@MainActor
final class SystemNotificationCenter: NotificationCenterScheduling {
    private let center = UNUserNotificationCenter.current()

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func add(identifier: String, title: String, body: String, fireDate: Date) {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        add(identifier: identifier, content: content(title: title, body: body), trigger: trigger)
    }

    func add(identifier: String, title: String, body: String, secondsFromNow: TimeInterval) {
        // `UNTimeIntervalNotificationTrigger` traps on a non-positive interval.
        // Callers already drop anything under a second; this is the belt to that
        // pair of braces, because the trap would take the app down mid-match.
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, secondsFromNow), repeats: false)
        add(identifier: identifier, content: content(title: title, body: body), trigger: trigger)
    }

    func requestAuthorization() async -> NotificationAuthorization {
        // The grant flag alone isn't enough: it says the coach tapped Allow,
        // not that banners are switched on. Read the settings back either way.
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        return await authorizationStatus()
    }

    func authorizationStatus() async -> NotificationAuthorization {
        NotificationAuthorization(await center.notificationSettings())
    }

    private func content(title: String, body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        return content
    }

    private func add(identifier: String, content: UNNotificationContent, trigger: UNNotificationTrigger) {
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
}

/// Schedules the planned reminders as local notifications, replacing any it
/// scheduled before (identified by a shared prefix).
///
/// Every operation is read-modify-write — read what's scheduled, drop ours, add
/// the new set — and the read is asynchronous. Previously nothing sequenced
/// them, so two operations could both read the *same* pending set before either
/// wrote, and whichever finished last won with a list it had read before the
/// other changed anything.
///
/// That put deleted reminders back. The app refreshes reminders when it comes
/// to the foreground *and* whenever the schedule changes, and foregrounding
/// also pulls from sync — so an incoming remote change lands a second refresh
/// on top of the first. A coach who deleted Saturday's game could still be
/// notified for it, and turning reminders off while a refresh was in flight got
/// quietly undone a moment later, leaving notifications firing for a setting
/// that reads as off.
///
/// Operations now queue behind each other, so the last one called is the last
/// one applied. They are not coalesced: several queued refreshes all run, in
/// order. Correctness only needs the ordering, and the redundant passes are a
/// handful of local-notification calls.
@MainActor
final class ScheduleNotifier {
    private let center: NotificationCenterScheduling
    private let prefix = "schedule.reminder."
    /// The tail of the queue. Each operation awaits the one before it.
    private var work: Task<Void, Never>?

    /// The real centre is built in the body rather than as a default argument:
    /// a default expression is a nonisolated context in the Swift 5 language
    /// mode, and `SystemNotificationCenter`'s initializer is `@MainActor`.
    init(center: NotificationCenterScheduling? = nil) {
        self.center = center ?? SystemNotificationCenter()
    }

    /// Prompts for permission once, and reports where things stand so the
    /// caller can say something when the answer is no.
    func requestAuthorization() async -> NotificationAuthorization {
        await center.requestAuthorization()
    }

    func authorizationStatus() async -> NotificationAuthorization {
        await center.authorizationStatus()
    }

    /// Replaces the previously-scheduled schedule reminders with `reminders`.
    func apply(_ reminders: [PlannedReminder]) {
        enqueue { [weak self] in
            guard let self else { return }
            await self.removeOurs()
            for reminder in reminders {
                self.center.add(identifier: self.prefix + reminder.id,
                                title: reminder.title,
                                body: reminder.body,
                                fireDate: reminder.fireDate)
            }
        }
    }

    func cancelAll() {
        enqueue { [weak self] in await self?.removeOurs() }
    }

    /// Awaits the queued work. For tests; production never needs to wait.
    func settled() async {
        await work?.value
    }

    private func enqueue(_ operation: @escaping () async -> Void) {
        let previous = work
        work = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }

    private func removeOurs() async {
        let ours = await center.pendingIdentifiers().filter { $0.hasPrefix(prefix) }
        guard !ours.isEmpty else { return }
        center.removePendingRequests(withIdentifiers: ours)
    }
}
