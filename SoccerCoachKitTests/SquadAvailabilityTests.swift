import XCTest
@testable import SoccerCoachKit

final class SquadAvailabilityTests: XCTestCase {
    private let teamID = UUID()

    private func player(_ number: Int) -> Player {
        TestData.player(teamID: teamID, number: number)
    }

    private func game(
        daysAgo: Int = 0,
        rsvps: [UUID: RSVPStatus] = [:],
        checkIns: [UUID: PreMatchCheckIn] = [:],
        reflections: [UUID: PostMatchReflection] = [:]
    ) -> GameEvent {
        GameEvent(id: UUID(), teamID: teamID, opponent: "Rivals",
                  date: Date(timeIntervalSince1970: TimeInterval(3_000_000 - daysAgo * 86_400)),
                  rsvps: rsvps, preMatchCheckIns: checkIns, postMatchReflections: reflections)
    }

    func testRSVPMapsToLevels() {
        let (a, b, c, d) = (player(1), player(2), player(3), player(4))
        let g = game(rsvps: [a.id: .going, b.id: .maybe, c.id: .notGoing]) // d: no response
        let board = SquadAvailability.board(players: [a, b, c, d], game: g, history: [g])
        let byID = Dictionary(uniqueKeysWithValues: board.map { ($0.player.id, $0.level) })
        XCTAssertEqual(byID[a.id], .available)
        XCTAssertEqual(byID[b.id], .maybe)
        XCTAssertEqual(byID[c.id], .out)
        XCTAssertEqual(byID[d.id], .noResponse)
    }

    func testLowReadinessFlagsAnOtherwiseAvailablePlayer() {
        let p = player(9)
        let g = game(rsvps: [p.id: .going],
                     checkIns: [p.id: PreMatchCheckIn(sleep: 2, energy: 2, focus: 2)]) // readiness 2.0
        let entry = SquadAvailability.board(players: [p], game: g, history: [g])[0]
        XCTAssertEqual(entry.level, .flagged)
        XCTAssertTrue(entry.flags.contains { $0.contains("Low readiness") })
    }

    func testPainReportedPreMatchFlags() {
        let p = player(9)
        let g = game(rsvps: [p.id: .going], checkIns: [p.id: PreMatchCheckIn(hasPain: true)])
        let entry = SquadAvailability.board(players: [p], game: g, history: [g])[0]
        XCTAssertEqual(entry.level, .flagged)
        XCTAssertTrue(entry.flags.contains("Pain reported pre-match"))
    }

    func testInjuryLastGameCarriesForward() {
        let p = player(9)
        let past = game(daysAgo: 7, reflections: [p.id: PostMatchReflection(hadInjury: true)])
        let upcoming = game(daysAgo: 0, rsvps: [p.id: .going])
        let entry = SquadAvailability.board(players: [p], game: upcoming, history: [past, upcoming])[0]
        XCTAssertEqual(entry.level, .flagged)
        XCTAssertTrue(entry.flags.contains("Injury flagged last game"))
    }

    func testNotGoingStaysOutEvenWithConcerns() {
        let p = player(9)
        let g = game(rsvps: [p.id: .notGoing], checkIns: [p.id: PreMatchCheckIn(hasPain: true)])
        let entry = SquadAvailability.board(players: [p], game: g, history: [g])[0]
        XCTAssertEqual(entry.level, .out, "an out player isn't a fitness concern to action")
    }

    func testBoardIsSortedWorstFirst() {
        let (avail, out, flagged) = (player(1), player(2), player(9))
        let g = game(rsvps: [avail.id: .going, out.id: .notGoing, flagged.id: .going],
                     checkIns: [flagged.id: PreMatchCheckIn(hasPain: true)])
        let board = SquadAvailability.board(players: [avail, out, flagged], game: g, history: [g])
        XCTAssertEqual(board.map(\.level), [.flagged, .out, .available])
    }

    func testSummaryCounts() {
        let (a, b, c) = (player(1), player(2), player(3))
        let g = game(rsvps: [a.id: .going, b.id: .going, c.id: .notGoing])
        let summary = SquadAvailability.summary(SquadAvailability.board(players: [a, b, c], game: g, history: [g]))
        XCTAssertEqual(summary.available, 2)
        XCTAssertEqual(summary.out, 1)
    }
}
