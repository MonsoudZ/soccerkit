import XCTest
@testable import SoccerCoachKit

/// `LineupFormation.slots(for:)` decides how many positions the Game Day pitch
/// draws and where they sit. It's pure branching arithmetic over four squad sizes
/// and three formations — twelve hand-written row breakdowns that have to keep
/// summing correctly — and none of it was covered.
final class LineupFormationTests: XCTestCase {

    // MARK: - The count has to match the squad

    /// The load-bearing invariant: a formation must lay out exactly as many slots
    /// as there are players on the pitch. One short and a starter has nowhere to
    /// stand; one over and the diagram shows a position nobody fills.
    ///
    /// Driven from `AgeGroup` rather than hardcoded sizes, so this fails the day
    /// someone adds an age group whose squad size has no arm in the switch — see
    /// `testAnUnknownSquadSizeFallsBackToEleven` for why that would be silent.
    func testEveryFormationFieldsExactlyTheSquad() {
        for ageGroup in AgeGroup.allCases {
            let squad = ageGroup.playersOnField
            for formation in LineupFormation.allCases {
                XCTAssertEqual(
                    formation.slots(for: squad).count, squad,
                    "\(formation.rawValue) at \(ageGroup.rawValue) (\(squad)-a-side) lays out the wrong number of slots"
                )
            }
        }
    }

    /// Every formation keeps exactly one goalkeeper, at the back.
    func testEveryFormationKeepsOneGoalkeeper() {
        for squad in Self.squadSizes {
            for formation in LineupFormation.allCases {
                let slots = formation.slots(for: squad)
                let keepers = slots.filter { $0.label == "GK" }
                XCTAssertEqual(keepers.count, 1,
                               "\(formation.rawValue) at \(squad)-a-side should have one GK")
                XCTAssertEqual(keepers.first?.position.y, slots.map(\.position.y).max(),
                               "The goalkeeper is the deepest slot")
            }
        }
    }

    /// A squad size the switch has no arm for silently gets an eleven-a-side
    /// shape. Only 4/7/9/11 reach it today, so this documents the fallback rather
    /// than endorsing it — and pins that it is a fallback, not a crash.
    func testAnUnknownSquadSizeFallsBackToEleven() {
        XCTAssertEqual(LineupFormation.balanced.slots(for: 5).count, 11,
                       "5-a-side has no arm of its own; it takes the default")
        XCTAssertEqual(LineupFormation.balanced.slots(for: 0).count, 11)
    }

    // MARK: - Where the slots sit

    /// Positions are normalized board coordinates, so anything outside 0...1 would
    /// be drawn off the pitch.
    func testEverySlotSitsOnThePitch() {
        for squad in Self.squadSizes {
            for formation in LineupFormation.allCases {
                for slot in formation.slots(for: squad) {
                    XCTAssertTrue((0...1).contains(slot.position.x),
                                  "\(formation.rawValue)/\(squad): x \(slot.position.x) is off the pitch")
                    XCTAssertTrue((0...1).contains(slot.position.y),
                                  "\(formation.rawValue)/\(squad): y \(slot.position.y) is off the pitch")
                }
            }
        }
    }

    /// `LineupSlot.id` is derived from label + position specifically so empty
    /// slots keep their identity across renders instead of churning every tick.
    /// That only holds while no two slots share both — and they don't share a
    /// label alone: a five-defender row is three slots all labelled "DEF".
    func testSlotIdentitiesAreUniqueWithinAFormation() {
        for squad in Self.squadSizes {
            for formation in LineupFormation.allCases {
                let slots = formation.slots(for: squad)
                XCTAssertEqual(Set(slots.map(\.id)).count, slots.count,
                               "\(formation.rawValue) at \(squad)-a-side has slots sharing an id")
            }
        }
    }

    /// A lone slot in a row is centred; a row of several spans the pitch with the
    /// outermost pair marked left and right.
    func testRowsAreCentredOrSpannedAndEdgesAreNamed() {
        let backFour = LineupFormation.balanced.slots(for: 11).filter { $0.label.hasSuffix("DEF") }
        XCTAssertEqual(backFour.count, 4)
        XCTAssertEqual(backFour.first?.label, "L DEF")
        XCTAssertEqual(backFour.last?.label, "R DEF")
        XCTAssertLessThan(backFour[0].position.x, backFour[3].position.x,
                          "Left to right, in order")

        let keeper = LineupFormation.balanced.slots(for: 11).first { $0.label == "GK" }
        XCTAssertEqual(keeper?.position.x, 0.5, "A row of one is centred, and unadorned")
    }

    /// Rows are ordered back to front, so the drawn shape reads as a formation
    /// rather than a scatter.
    func testRowsRunFromKeeperToForwards() {
        for squad in Self.squadSizes {
            for formation in LineupFormation.allCases {
                let ys = formation.slots(for: squad).map(\.position.y)
                XCTAssertEqual(ys, ys.sorted(by: >),
                               "\(formation.rawValue) at \(squad)-a-side isn't ordered back to front")
            }
        }
    }

    /// The three formations are meant to be different shapes, not three names for
    /// the same one.
    func testTheFormationsActuallyDiffer() {
        for squad in Self.squadSizes {
            let shapes = LineupFormation.allCases.map { formation in
                formation.slots(for: squad).map(\.id)
            }
            XCTAssertEqual(Set(shapes.map { $0.joined(separator: "|") }).count, shapes.count,
                           "Two formations at \(squad)-a-side lay out identically")
        }
    }

    /// Real squad sizes only — `AgeGroup` is the source of truth for which exist.
    private static var squadSizes: [Int] {
        Array(Set(AgeGroup.allCases.map(\.playersOnField))).sorted()
    }
}
