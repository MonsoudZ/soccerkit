import XCTest
@testable import SoccerCoachKit

@MainActor
final class ScheduleReminderTests: XCTestCase {
    private let teamID = UUID()
    private func name(_: UUID) -> String { "Falcons" }

    private func game(daysFromNow days: Double, opponent: String = "Rivals", now: Date) -> GameEvent {
        GameEvent(id: UUID(), teamID: teamID, opponent: opponent,
                  date: now.addingTimeInterval(days * 86_400))
    }

    func testPlansAReminderPerUpcomingItemAtTheLeadTime() {
        let now = Date()
        let g = game(daysFromNow: 2, now: now)

        let reminders = ScheduleReminderPlanner.reminders(
            games: [g], sessions: [], events: [], teamName: name(_:),
            leadMinutes: 60, now: now)

        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders[0].id, "game.\(g.id.uuidString)")
        // Fires one hour (3600s) before kickoff.
        XCTAssertEqual(reminders[0].fireDate.timeIntervalSince(g.date), -3600, accuracy: 1)
        XCTAssertTrue(reminders[0].body.contains("Falcons vs Rivals"))
    }

    func testDropsPastEventsButClampsImminentOnes() {
        let now = Date()
        let past = game(daysFromNow: -1, now: now)          // already played -> dropped
        let tooSoon = game(daysFromNow: 0.01, now: now)     // ~15 min away, lead 60 -> clamped to now, not dropped
        let upcoming = game(daysFromNow: 3, now: now)

        let reminders = ScheduleReminderPlanner.reminders(
            games: [past, tooSoon, upcoming], sessions: [], events: [], teamName: name(_:),
            leadMinutes: 60, now: now)

        XCTAssertEqual(reminders.map(\.id),
                       ["game.\(tooSoon.id.uuidString)", "game.\(upcoming.id.uuidString)"],
                       "Past dropped; imminent event clamped to fire soon rather than dropped")
        XCTAssertGreaterThan(reminders[0].fireDate, now, "Clamped fire date is still in the future")
    }

    func testSortsByFireDateAndCapsAtLimit() {
        let now = Date()
        let games = (1...40).map { game(daysFromNow: Double(41 - $0), now: now) } // descending dates
        let reminders = ScheduleReminderPlanner.reminders(
            games: games, sessions: [], events: [], teamName: name(_:),
            leadMinutes: 0, now: now, limit: 30)

        XCTAssertEqual(reminders.count, 30, "Capped to the soonest 30")
        XCTAssertTrue(zip(reminders, reminders.dropFirst()).allSatisfy { $0.fireDate <= $1.fireDate },
                      "Sorted soonest-first")
    }

    func testAtStartLeadFiresExactlyAtEventTime() {
        let now = Date()
        let g = game(daysFromNow: 1, now: now)
        let reminders = ScheduleReminderPlanner.reminders(
            games: [g], sessions: [], events: [], teamName: name(_:),
            leadMinutes: 0, now: now)
        XCTAssertEqual(reminders[0].fireDate, g.date)
    }
}
