import XCTest
@testable import SoccerCoachKit

/// Decoding what the server can actually write.
///
/// The backend creates drills and sessions over REST from bodies that collect far less
/// than these models used to require — a drill is a name and a description, a session may
/// have no team and blocks with no drill. Codable throws on one missing key and loses the
/// whole record, so the practical effect was that a drill or session made anywhere but the
/// phone never arrived, and the failure surfaced as "Unexpected server response".
///
/// These are written as the payloads the server sends, not as round-trips of what the app
/// itself encodes, because the app was never the side that got this wrong.
final class RESTCreatedRecordTests: XCTestCase {

    // MARK: - Drill

    /// What POST /drills can produce: a name, a description, and nothing else.
    func testADrillWithOnlyTitleAndSetupDecodes() throws {
        let json = Data("""
        {"id":"11111111-1111-4111-8111-111111111111","title":"Rondo","fieldSetup":"5v2 in a 10m box"}
        """.utf8)

        let drill = try JSONDecoder().decode(Drill.self, from: json)

        XCTAssertEqual(drill.title, "Rondo")
        XCTAssertEqual(drill.fieldSetup, "5v2 in a 10m box")
        XCTAssertEqual(drill.durationMinutes, 0, "a blank the coach can fill in")
        XCTAssertEqual(drill.coachingPoints, [])
        XCTAssertEqual(drill.category, .technical, "the neutral default")
    }

    /// A category this build has no case for must not take the drill down with it — the
    /// same failure `Team.storedAgeGroup` exists to prevent, and reachable the same way:
    /// a newer build writes one and sync hands it here.
    func testAnUnknownCategoryIsKeptRatherThanThrowing() throws {
        let json = Data("""
        {"id":"11111111-1111-4111-8111-111111111111","title":"Rondo",
         "category":"Restarts","fieldSetup":"","coachingPoints":[]}
        """.utf8)

        let drill = try JSONDecoder().decode(Drill.self, from: json)

        XCTAssertEqual(drill.categoryLabel, "Restarts", "the coach is shown what was stored")
        XCTAssertEqual(drill.category, .technical, "and this build still has something to filter on")
    }

    /// And re-encoding gives the unknown value back, so an older build editing a drill
    /// cannot quietly rewrite a newer category.
    func testAnUnknownCategorySurvivesAReEncode() throws {
        let json = Data("""
        {"id":"11111111-1111-4111-8111-111111111111","title":"Rondo","category":"Restarts"}
        """.utf8)
        var drill = try JSONDecoder().decode(Drill.self, from: json)
        drill.title = "Rondo (edited)"

        let round = try JSONDecoder().decode(Drill.self, from: JSONEncoder().encode(drill))

        XCTAssertEqual(round.categoryLabel, "Restarts")
        XCTAssertEqual(round.title, "Rondo (edited)")
    }

    /// A category the coach picks is still stored verbatim.
    func testAKnownCategoryRoundTrips() throws {
        var drill = try JSONDecoder().decode(Drill.self, from: Data("""
        {"id":"11111111-1111-4111-8111-111111111111","title":"Rondo"}
        """.utf8))
        drill.category = .conditioning

        let round = try JSONDecoder().decode(Drill.self, from: JSONEncoder().encode(drill))

        XCTAssertEqual(round.category, .conditioning)
        XCTAssertEqual(round.categoryLabel, "Conditioning")
    }

    // MARK: - Session

    /// A session with no team, and a block with no drill: both things POST /sessions has
    /// always allowed and neither of which the app could decode.
    func testASessionWithNoTeamAndABlockWithNoDrillDecodes() throws {
        let json = Data("""
        {"id":"22222222-2222-4222-8222-222222222222","title":"Tuesday","date":778000000.5,
         "objective":"Pressing",
         "blocks":[{"id":"33333333-3333-4333-8333-333333333333","minutes":10,"focus":"Warm-up"}]}
        """.utf8)

        let session = try JSONDecoder().decode(TrainingSession.self, from: json)

        XCTAssertNil(session.teamID, "a session need not belong to a team")
        XCTAssertEqual(session.blocks.count, 1)
        XCTAssertNil(session.blocks[0].drillID, "a warm-up is not a drill")
        XCTAssertEqual(session.blocks[0].focus, "Warm-up")
        XCTAssertEqual(session.title, "Tuesday")
    }

    /// The date is the one required field the server can always supply, and it is a
    /// Double — seconds since 2001 — which is what Swift writes and what the backend's
    /// own contract test pins.
    func testTheDateIsReadAsSecondsSince2001() throws {
        let json = Data("""
        {"id":"22222222-2222-4222-8222-222222222222","title":"Tuesday","date":778000000.5,
         "objective":"","blocks":[]}
        """.utf8)

        let session = try JSONDecoder().decode(TrainingSession.self, from: json)

        XCTAssertEqual(session.date.timeIntervalSinceReferenceDate, 778000000.5, accuracy: 0.001)
    }

    /// A session that does have a team still keeps it.
    func testATeamIsKeptWhenTheServerSendsOne() throws {
        let json = Data("""
        {"id":"22222222-2222-4222-8222-222222222222",
         "teamID":"44444444-4444-4444-8444-444444444444",
         "title":"Tuesday","date":778000000.5,"objective":"","blocks":[]}
        """.utf8)

        let session = try JSONDecoder().decode(TrainingSession.self, from: json)

        XCTAssertEqual(session.teamID?.uuidString.lowercased(), "44444444-4444-4444-8444-444444444444")
    }
}
