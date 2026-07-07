import XCTest
@testable import SoccerCoachKit

@MainActor
final class DiagramAttachmentTests: XCTestCase {

    private func reload(_ id: UUID, in store: AppStore) -> TacticsDiagram {
        store.diagrams.first { $0.id == id }!
    }

    func testAttachingToOneOwnerClearsTheOthers() {
        let store = TestData.store()
        let diagram = store.addDiagram(title: "Plan")

        // Start attached to a session.
        let sessionID = UUID()
        store.attachDiagram(diagram, sessionID: sessionID, drillID: nil)
        XCTAssertEqual(reload(diagram.id, in: store).sessionID, sessionID)

        // Re-attaching to a game clears the session/drill — a diagram plans one thing.
        let gameID = UUID()
        store.attachDiagram(diagram, sessionID: nil, drillID: nil, gameID: gameID)
        let updated = reload(diagram.id, in: store)
        XCTAssertEqual(updated.gameID, gameID)
        XCTAssertNil(updated.sessionID)
        XCTAssertNil(updated.drillID)
    }

    func testDiagramsForGameIDFiltersByGame() {
        let store = TestData.store()
        let gameID = UUID()
        let attached = store.addDiagram(title: "Game Plan")
        _ = store.addDiagram(title: "Unattached")
        store.attachDiagram(attached, sessionID: nil, drillID: nil, gameID: gameID)

        XCTAssertEqual(store.diagrams(forGameID: gameID).map(\.id), [attached.id])
        XCTAssertTrue(store.diagrams(forGameID: UUID()).isEmpty)
    }

    func testGameIDDecodesToNilForDiagramsSavedBeforeTheField() throws {
        let diagram = TacticsDiagram(
            id: UUID(), teamID: UUID(), title: "T", notes: "",
            sessionID: nil, gameID: UUID(),
            players: [], zones: [], lines: [], updatedAt: Date()
        )
        let data = try JSONEncoder().encode(diagram)
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        dict["gameID"] = nil // simulate an older save
        let legacy = try JSONSerialization.data(withJSONObject: dict)

        let decoded = try JSONDecoder().decode(TacticsDiagram.self, from: legacy)
        XCTAssertNil(decoded.gameID)
        XCTAssertEqual(decoded.title, "T", "other fields still decode")
    }
}
