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

    /// Game Day's interval-triggered variant. The delay is recorded so a test can
    /// check *when* a sub reminder was set for, not just that it exists.
    func add(identifier: String, title: String, body: String, secondsFromNow: TimeInterval) {
        scheduled.insert(identifier)
        delays[identifier] = secondsFromNow
    }

    private(set) var delays: [String: TimeInterval] = [:]

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

/// Sub reminders are scheduled against a match clock that outlives the process:
/// `GameDaySession` exists precisely so a match survives a crash, an eviction, or
/// a force-quit. The notifications it scheduled survive too — so what is pending
/// has to be read back from the centre, not remembered in a property that dies
/// with the process.
@MainActor
final class GameDayNotifierTests: XCTestCase {
    private var center: FakeNotificationCenter!

    override func setUp() {
        super.setUp()
        center = FakeNotificationCenter()
    }

    /// A fresh notifier over the same centre — the same way an in-memory session
    /// store is handed to a second view model to stand in for a relaunch.
    private func relaunchedNotifier() -> GameDayNotifier {
        GameDayNotifier(center: center)
    }

    private func item(_ id: String, dueIn seconds: TimeInterval = 600) -> GameDayNotifier.PendingNotification {
        .init(id: id, secondsFromNow: seconds, title: "Substitution Time",
              body: "Put Maya in for Sam (20').")
    }

    private func ourIDs() -> Set<String> {
        Set(center.scheduled
            .filter { $0.hasPrefix("gameday.reminder.") }
            .map { $0.replacingOccurrences(of: "gameday.reminder.", with: "") })
    }

    /// The reported bug. Pausing the clock routes through `cancelAll`, and after
    /// a relaunch that used to be a no-op — so every alert the previous process
    /// scheduled stayed pending and fired during a stopped match.
    func testCancelReachesRemindersScheduledByAPreviousProcess() async {
        let before = relaunchedNotifier()
        before.reschedule([item("sub-1"), item("sub-2")])
        await before.settled()
        XCTAssertEqual(ourIDs(), ["sub-1", "sub-2"], "precondition: the first process scheduled them")

        let after = relaunchedNotifier() // the app was force-quit and reopened
        after.cancelAll()
        await after.settled()

        XCTAssertTrue(ourIDs().isEmpty, "a relaunched notifier must still cancel what it finds")
    }

    /// The coach relaunches at half time and deletes a sub they no longer want.
    /// They must not be alerted for it at the 40th minute.
    func testARelaunchDropsAReminderTheCoachDeleted() async {
        let before = relaunchedNotifier()
        before.reschedule([item("keep"), item("deleted")])
        await before.settled()

        let after = relaunchedNotifier()
        after.reschedule([item("keep")]) // "deleted" is gone from the match
        await after.settled()

        XCTAssertEqual(ourIDs(), ["keep"], "the deleted reminder must not still be pending")
    }

    /// Schedule reminders share this centre under their own prefix, and a match
    /// running while a fixture reminder is pending is the normal case.
    func testItLeavesScheduleRemindersAlone() async {
        center.add(identifier: "schedule.reminder.game.saturday", title: "", body: "", fireDate: Date())

        let notifier = relaunchedNotifier()
        notifier.reschedule([item("sub-1")])
        await notifier.settled()
        notifier.cancelAll()
        await notifier.settled()

        XCTAssertEqual(center.scheduled, ["schedule.reminder.game.saturday"],
                       "the fixture reminder is not Game Day's to cancel")
    }

    /// Reads are async, so overlapping operations have to queue — the same
    /// guarantee `ScheduleNotifier` needs, for the same reason. A sub recorded
    /// mid-match fires a reschedule on top of one already in flight.
    func testAStaleRescheduleCannotResurrectARemovedReminder() async {
        let notifier = relaunchedNotifier()
        notifier.reschedule([item("sub-1"), item("sub-2")])
        await notifier.settled()

        // The stale pass reads slowly and the current one fast, so left alone the
        // stale one would land last and win.
        center.readDelays = [.milliseconds(150), .milliseconds(10)]
        notifier.reschedule([item("sub-1"), item("sub-2")]) // in flight, pre-delete
        notifier.reschedule([item("sub-1")])                // sub-2 was deleted
        await notifier.settled()

        XCTAssertEqual(ourIDs(), ["sub-1"], "the last reschedule called must be the one that sticks")
    }

    /// Anything already due is the in-app alert's job; scheduling it would also
    /// trap the interval trigger.
    func testItDropsRemindersDueInUnderASecond() async {
        let notifier = relaunchedNotifier()
        notifier.reschedule([item("due-now", dueIn: 0), item("nearly", dueIn: 0.4), item("soon", dueIn: 90)])
        await notifier.settled()

        XCTAssertEqual(ourIDs(), ["soon"])
        XCTAssertEqual(center.delays["gameday.reminder.soon"], 90,
                       "and it is set for when the match clock says, not rounded")
    }
}
