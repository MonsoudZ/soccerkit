import XCTest
@testable import SoccerCoachKit

/// The generic form runner is the engine's write path through the UI. These
/// tests exercise its view model directly (no SwiftUI needed): typed bindings
/// in, a faithful `FormInstance` out.
@MainActor
final class FormRunnerViewModelTests: XCTestCase {

    private var athlete: UUID { UUID() }

    func testDraftBuildsInstanceInFieldOrderDroppingBlanks() {
        let template = FormTemplateCatalog.preMatchCheckIn
        let vm = FormRunnerViewModel(template: template, subject: .athlete(athlete))

        vm.setScale("sleep", 4)
        vm.setScale("energy", 0)          // cleared → no answer
        vm.setBool("hasPain", true)
        vm.setBool("warmedUp", nil)        // unset → no answer
        vm.setText("note", "  ")           // whitespace → no answer

        let instance = vm.instance
        XCTAssertEqual(instance.templateID, template.id)
        XCTAssertEqual(instance.context, .preGame)
        XCTAssertEqual(instance.subject.type, .athlete)
        // Only the two real answers, and in template field order (sleep before hasPain).
        XCTAssertEqual(instance.answers.map(\.fieldKey), ["sleep", "hasPain"])
        XCTAssertEqual(instance.intValue(for: "sleep"), 4)
        XCTAssertEqual(instance.flag(for: "hasPain"), true)
    }

    func testNumberFieldDropsZero() {
        let vm = FormRunnerViewModel(template: FormTemplateCatalog.playerGameReport, subject: .athlete(athlete))
        vm.setNumber("goals", 2)
        vm.setNumber("assists", 0)
        XCTAssertEqual(vm.instance.intValue(for: "goals"), 2)
        XCTAssertNil(vm.instance.answer(for: "assists"))
    }

    func testEditingPreservesIdentityContextRefAndNote() {
        let id = UUID()
        let game = UUID()
        let existing = FormInstance(
            id: id, templateID: FormTemplateCatalog.ID.preMatchCheckIn, context: .preGame,
            subject: .athlete(athlete), contextRef: .game(game),
            answers: [.scale("sleep", 3)], note: "keep me"
        )
        let vm = FormRunnerViewModel(template: FormTemplateCatalog.preMatchCheckIn,
                                     subject: existing.subject, existing: existing)
        XCTAssertTrue(vm.isEditing)
        XCTAssertEqual(vm.scaleValue("sleep"), 3, "existing answers preload")

        vm.setScale("sleep", 5)
        let saved = vm.instance
        XCTAssertEqual(saved.id, id, "same row id — an edit, not a new instance")
        XCTAssertEqual(saved.contextRef, .game(game), "context link preserved")
        XCTAssertEqual(saved.note, "keep me", "freeform note not dropped by the basic runner")
        XCTAssertEqual(saved.intValue(for: "sleep"), 5)
    }

    func testSavePersistsThroughStoreAndEmptyIsDropped() {
        let store = TestData.store()
        let playerID = store.players[0].id
        let vm = FormRunnerViewModel(template: FormTemplateCatalog.developmentReview,
                                     subject: .athlete(playerID))

        // Nothing entered → nothing stored.
        vm.save(into: store)
        XCTAssertTrue(store.formInstances.isEmpty)

        vm.setScale("Passing", 4)
        vm.save(into: store)
        XCTAssertEqual(store.formInstances.count, 1)
        XCTAssertEqual(store.formInstances.first?.intValue(for: "Passing"), 4)

        // Re-saving the same view model replaces rather than duplicates.
        vm.setScale("Passing", 5)
        vm.save(into: store)
        XCTAssertEqual(store.formInstances.count, 1)
        XCTAssertEqual(store.formInstances.first?.intValue(for: "Passing"), 5)
    }
}
