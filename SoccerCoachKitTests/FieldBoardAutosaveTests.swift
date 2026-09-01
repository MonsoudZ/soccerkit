import XCTest
@testable import SoccerCoachKit

/// The bug these cover: `FieldBoardViewModel` holds the whole diagram — players,
/// zones, lines, equipment — in memory, and the Save toolbar button was the only
/// thing that ever wrote it to the store. Switching team, picking another
/// diagram, or navigating away discarded the work with no prompt. Every other
/// editor in the app writes through `AppStore` as it goes.
///
/// Also here: deleting a diagram was the one destructive action with no undo.
@MainActor
final class FieldBoardAutosaveTests: XCTestCase {

    private func makeBoard() -> (AppStore, FieldBoardViewModel) {
        let store = TestData.store()
        let viewModel = FieldBoardViewModel()
        viewModel.ensureDiagramLoaded(in: store)
        return (store, viewModel)
    }

    /// A marker the coach just dragged onto the pitch, not yet saved.
    private func addUnsavedMarker(_ viewModel: FieldBoardViewModel) {
        viewModel.zones.append(BoardZone(id: UUID(), title: "Press here",
                                         rect: CGRect(x: 0.3, y: 0.4, width: 0.2, height: 0.2)))
    }

    private func storedZones(_ store: AppStore, _ id: UUID?) -> [BoardZone] {
        store.diagrams.first { $0.id == id }?.zones ?? []
    }

    // MARK: - Autosave

    func testAutosaveWritesTheBoardToTheStore() {
        let (store, viewModel) = makeBoard()
        let id = viewModel.selectedDiagramID
        addUnsavedMarker(viewModel)
        XCTAssertFalse(storedZones(store, id).contains { $0.title == "Press here" },
                       "fixture must start unsaved")

        viewModel.autosave(in: store)

        XCTAssertTrue(storedZones(store, id).contains { $0.title == "Press here" })
    }

    /// The write is skipped when nothing changed — `updateDiagram` stamps
    /// `updatedAt`, which reorders the newest-first picker and pushes a sync
    /// record, so an autosave on every appear would churn both for nothing.
    func testAutosaveSkipsAnUnchangedBoard() {
        let (store, viewModel) = makeBoard()
        let id = viewModel.selectedDiagramID
        let before = store.diagrams.first { $0.id == id }?.updatedAt

        viewModel.autosave(in: store)

        XCTAssertEqual(store.diagrams.first { $0.id == id }?.updatedAt, before,
                       "an unchanged board must not be rewritten")
    }

    func testAutosaveIsANoOpWithNoDiagramSelected() {
        let (store, viewModel) = makeBoard()
        viewModel.selectedDiagramID = nil
        let count = store.diagrams.count

        viewModel.autosave(in: store)

        XCTAssertEqual(store.diagrams.count, count, "autosave must never create a diagram")
    }

    // MARK: - The paths that used to lose work

    /// Picking another diagram banks the current one first. This is why the
    /// selection goes through a binding rather than an `onChange`, which fires
    /// after the id has already moved on.
    func testSwitchingDiagramsSavesTheOutgoingBoard() {
        let (store, viewModel) = makeBoard()
        let first = viewModel.selectedDiagramID
        let second = store.addDiagram(title: "Second")
        addUnsavedMarker(viewModel)

        viewModel.diagramSelection(in: store).wrappedValue = second.id

        XCTAssertEqual(viewModel.selectedDiagramID, second.id, "the picker still switches")
        XCTAssertTrue(storedZones(store, first).contains { $0.title == "Press here" },
                      "the outgoing board must be banked before the new one loads")
    }

    /// And the incoming diagram's board is what's on screen afterwards — the
    /// save must not leak the old board into the new selection.
    func testSwitchingDiagramsLoadsTheIncomingBoard() {
        let (store, viewModel) = makeBoard()
        let second = store.addDiagram(title: "Second")
        addUnsavedMarker(viewModel)

        viewModel.diagramSelection(in: store).wrappedValue = second.id

        XCTAssertFalse(viewModel.zones.contains { $0.title == "Press here" },
                       "the board on screen should be the one that was picked")
        XCTAssertEqual(viewModel.title, "Second")
    }

    // MARK: - Delete and undo

    func testDeletingADiagramCanBeUndone() {
        let store = TestData.store()
        let diagram = store.addDiagram(title: "Match Plan")

        store.deleteDiagram(diagram)
        XCTAssertFalse(store.diagrams.contains { $0.id == diagram.id })
        XCTAssertNotNil(store.undoMessage, "a delete with no undo offer is the bug")

        store.undoLastDelete()

        XCTAssertTrue(store.diagrams.contains { $0.id == diagram.id })
    }

    /// Deleting the last diagram used to seed a replacement immediately — a
    /// second mutation, which retires the pending undo. The offer has to survive
    /// long enough to be tapped.
    func testDeletingTheLastDiagramLeavesTheUndoOfferStanding() {
        let (store, viewModel) = makeBoard()
        for extra in store.teamDiagrams.dropFirst() { store.deleteDiagram(extra) }

        viewModel.deleteCurrentDiagram(in: store)

        XCTAssertTrue(store.teamDiagrams.isEmpty, "no replacement is seeded here")
        XCTAssertNil(viewModel.selectedDiagramID)
        XCTAssertNotNil(store.undoMessage, "the undo offer must outlive the delete")

        store.undoLastDelete()
        XCTAssertFalse(store.teamDiagrams.isEmpty)
    }

    /// With more than one diagram, deleting moves to the next rather than
    /// clearing the board.
    func testDeletingSelectsTheNextRemainingDiagram() {
        let (store, viewModel) = makeBoard()
        let second = store.addDiagram(title: "Second")
        viewModel.diagramSelection(in: store).wrappedValue = second.id

        viewModel.deleteCurrentDiagram(in: store)

        XCTAssertNotNil(viewModel.selectedDiagramID)
        XCTAssertNotEqual(viewModel.selectedDiagramID, second.id)
        XCTAssertFalse(store.diagrams.contains { $0.id == second.id })
    }
}
