import XCTest
@testable import SoccerCoachKit

/// A stand-in notification centre that records what is scheduled and can be made
/// to answer slowly, so two operations can be forced to overlap on demand — the
/// window the real bug lived in, which the system centre can't be driven into.
@MainActor
final class FakeNotificationCenter: NotificationCenterScheduling {
    private(set) var scheduled: Set<String> = []
    /// How long a pending-list read takes. Reads are where the overlap happened:
    /// both operations read the same list before either wrote.
    var readDelay: Duration = .zero
    /// Per-read durations, consumed in order, so a test can make an *earlier*
    /// operation finish *later*. That is the shape of the bug — whichever
    /// operation finished last won, regardless of which was called last — and
    /// equal delays hide it, because then the calls finish in the order made.
    var readDelays: [Duration] = []
    private(set) var authorizationRequests = 0

    func pendingIdentifiers() async -> [String] {
        let delay = readDelays.isEmpty ? readDelay : readDelays.removeFirst()
        if delay > .zero { try? await Task.sleep(for: delay) }
        return Array(scheduled)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        scheduled.subtract(identifiers)
    }

    func add(identifier: String, title: String, body: String, fireDate: Date) {
        scheduled.insert(identifier)
    }

    func requestAuthorization() { authorizationRequests += 1 }
}

/// Reminder scheduling is read-modify-write across an async boundary. Nothing
/// used to sequence those, so two overlapping operations both read the same
/// pending set and whichever finished last won — with a list it had read before
/// the other changed anything.
@MainActor
final class ScheduleNotifierOrderingTests: XCTestCase {
    private var center: FakeNotificationCenter!
    private var notifier: ScheduleNotifier!

    override func setUp() {
        super.setUp()
        center = FakeNotificationCenter()
        notifier = ScheduleNotifier(center: center)
    }

    private func reminder(_ id: String) -> PlannedReminder {
        PlannedReminder(id: id, fireDate: Date().addingTimeInterval(3600),
                        title: "Upcoming game", body: "Kick-off soon")
    }

    private func scheduledIDs() -> Set<String> {
        Set(center.scheduled.map { $0.replacingOccurrences(of: "schedule.reminder.", with: "") })
    }

    /// The reported bug: a coach deletes Saturday's game and is still notified
    /// for it, because a refresh that predates the delete finishes last and
    /// re-adds what it read.
    func testAStaleRefreshCannotResurrectADeletedReminder() async {
        notifier.apply([reminder("saturday"), reminder("tuesday")])
        await notifier.settled()
        XCTAssertEqual(scheduledIDs(), ["saturday", "tuesday"])

        // The stale refresh reads slowly and the current one reads fast, so
        // left to themselves the stale one would land last and win.
        center.readDelays = [.milliseconds(150), .milliseconds(10)]
        notifier.apply([reminder("saturday"), reminder("tuesday")]) // in flight, pre-delete
        notifier.apply([reminder("tuesday")])                       // Saturday is gone
        await notifier.settled()

        XCTAssertEqual(scheduledIDs(), ["tuesday"],
                       "the last refresh called must be the one that sticks")
    }

    /// The other half: turning reminders off while a refresh is in flight used
    /// to be undone a moment later, leaving notifications firing for a setting
    /// that reads as off.
    func testTurningRemindersOffIsNotUndoneByARefreshInFlight() async {
        // The refresh reads slowly, the cancel fast — so the refresh's add would
        // land after the cancel had already cleared everything.
        center.readDelays = [.milliseconds(150), .milliseconds(10)]
        notifier.apply([reminder("saturday"), reminder("tuesday")])
        notifier.cancelAll()
        await notifier.settled()

        XCTAssertTrue(center.scheduled.isEmpty,
                      "reminders the coach switched off must stay off")
    }

    /// And the reverse order still works — cancelling then rescheduling leaves
    /// the reminders on, so the sequencing isn't just "cancel always wins".
    func testSwitchingRemindersBackOnRescheduled() async {
        center.readDelays = [.milliseconds(150), .milliseconds(10)]
        notifier.cancelAll()
        notifier.apply([reminder("saturday")])
        await notifier.settled()

        XCTAssertEqual(scheduledIDs(), ["saturday"])
    }

    /// Many refreshes in a row — the foreground/sync burst — converge on the
    /// last one rather than an arbitrary winner.
    func testABurstOfRefreshesEndsOnTheLastOne() async {
        center.readDelay = .milliseconds(10)
        for index in 1...5 {
            notifier.apply([reminder("fixture-\(index)")])
        }
        await notifier.settled()

        XCTAssertEqual(scheduledIDs(), ["fixture-5"])
    }

    /// It only ever removes its own notifications: Game Day schedules sub
    /// reminders under a different prefix through the same centre.
    func testItLeavesOtherNotificationsAlone() async {
        center.add(identifier: "gameday.reminder.sub-1", title: "", body: "", fireDate: Date())
        notifier.apply([reminder("saturday")])
        await notifier.settled()
        notifier.cancelAll()
        await notifier.settled()

        XCTAssertEqual(center.scheduled, ["gameday.reminder.sub-1"],
                       "Game Day's sub reminders are not ours to cancel")
    }
}
