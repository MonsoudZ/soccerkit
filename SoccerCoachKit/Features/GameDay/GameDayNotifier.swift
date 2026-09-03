import Foundation
import UserNotifications

/// Schedules local notifications for sub reminders so they still alert the coach
/// when the app is backgrounded or the phone is locked. In-app alerts remain the
/// primary path (and iOS suppresses these banners while the app is foregrounded,
/// so they don't double up); these are the background fallback.
///
/// What is scheduled is read back from the notification centre and filtered by
/// this notifier's prefix, rather than remembered in a property. Pending
/// notifications outlive the process and an in-memory list does not, so after a
/// crash, an eviction, or a force-quit — the three cases `GameDaySession` exists
/// to survive — the list came back empty and `cancelAll` had nothing to cancel.
/// A coach who relaunched at half time and then deleted a sub reminder was still
/// alerted for it, and pausing the clock left every stale alert standing, since
/// that path is a cancel too.
///
/// Like `ScheduleNotifier`, every operation is read-modify-write across an async
/// boundary, so they queue behind each other: the last one called is the last one
/// applied. They are not coalesced — correctness only needs the ordering.
@MainActor
final class GameDayNotifier {
    struct PendingNotification {
        let id: String
        let secondsFromNow: TimeInterval
        let title: String
        let body: String
    }

    private let center: NotificationCenterScheduling
    private let prefix = "gameday.reminder."
    /// The tail of the queue. Each operation awaits the one before it.
    private var work: Task<Void, Never>?

    /// The real centre is built in the body rather than as a default argument:
    /// a default expression is a nonisolated context in the Swift 5 language
    /// mode, and `SystemNotificationCenter`'s initializer is `@MainActor`.
    init(center: NotificationCenterScheduling? = nil) {
        self.center = center ?? SystemNotificationCenter()
    }

    /// Prompts for permission once; the system only shows the dialog the first
    /// time. Reports where things stand, because a denial does *not* degrade
    /// gracefully here: in-app alerts only reach a coach who is looking at this
    /// screen, and the background notification is the whole point of a reminder
    /// set for the 60th minute.
    func requestAuthorization() async -> NotificationAuthorization {
        await center.requestAuthorization()
    }

    func authorizationStatus() async -> NotificationAuthorization {
        await center.authorizationStatus()
    }

    /// Replaces all currently-scheduled sub-reminder notifications with `items`.
    func reschedule(_ items: [PendingNotification]) {
        enqueue { [weak self] in
            guard let self else { return }
            await self.removeOurs()
            // Anything under a second either has already come due or would trap
            // the interval trigger; the in-app alert covers that window.
            for item in items where item.secondsFromNow >= 1 {
                self.center.add(identifier: self.prefix + item.id,
                                title: item.title,
                                body: item.body,
                                secondsFromNow: item.secondsFromNow)
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

    /// Drops every sub reminder currently scheduled, whichever process scheduled
    /// it — and only those: schedule reminders share this centre under their own
    /// prefix.
    private func removeOurs() async {
        let ours = await center.pendingIdentifiers().filter { $0.hasPrefix(prefix) }
        guard !ours.isEmpty else { return }
        center.removePendingRequests(withIdentifiers: ours)
    }
}
