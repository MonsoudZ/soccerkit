import XCTest
@testable import SoccerCoachKit

@MainActor
final class SessionExportTests: XCTestCase {

    /// Builds a store whose session references a real drill in the same snapshot.
    private func makeStore(withBlock: Bool, title: String = "Tuesday Session")
        -> (AppStore, TrainingSession) {
        let team = TestData.team()
        let drill = TestData.drill(teamID: team.id, title: "Rondo")
        var blocks: [TrainingBlock] = []
        if withBlock {
            blocks = [TrainingBlock(id: UUID(), drillID: drill.id, minutes: 15,
                                    focus: "Keep possession", topic: "Warm-up")]
        }
        let session = TrainingSession(id: UUID(), teamID: team.id, title: title, date: Date(),
                                      objective: "Possession", blocks: blocks, attendance: [:])
        let snapshot = AppSnapshot(teams: [team], players: [], drills: [drill],
                                   sessions: [session], diagrams: [], games: [], events: [],
                                   selectedTeamID: team.id)
        return (AppStore(snapshot: snapshot, persistence: InMemoryPersistence()), session)
    }

    func testExportsValidPDF() {
        let (store, session) = makeStore(withBlock: true)
        let data = SessionExporter.pdfData(for: session, in: store)
        XCTAssertGreaterThan(data.count, 0)
        XCTAssertEqual(data.prefix(4), Data("%PDF".utf8), "output has PDF magic bytes")
    }

    func testEmptySessionStillProducesPDF() {
        let (store, session) = makeStore(withBlock: false)
        let data = SessionExporter.pdfData(for: session, in: store)
        XCTAssertEqual(data.prefix(4), Data("%PDF".utf8))
    }

    func testFileNameSanitized() {
        let (_, session) = makeStore(withBlock: false, title: "Tuesday: Session #1")
        XCTAssertEqual(SessionExporter.fileName(for: session), "Tuesday-Session-1-plan.pdf")
    }
}
