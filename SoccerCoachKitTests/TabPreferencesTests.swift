import XCTest
@testable import SoccerCoachKit

@MainActor
final class TabPreferencesTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "TabPreferencesTests.\(UUID().uuidString)")!
        return defaults
    }

    func testDefaultsToCalendarRosterGame() {
        let prefs = TabPreferences(defaults: makeDefaults())
        XCTAssertEqual(prefs.favorites, [.calendar, .roster, .game])
        XCTAssertEqual(prefs.quickAccess.first, .dashboard, "Home is always first")
    }

    func testAddRespectsTheCapAndExcludesDuplicates() {
        let prefs = TabPreferences(defaults: makeDefaults())
        // Already full at 3.
        prefs.add(.field)
        XCTAssertFalse(prefs.favorites.contains(.field), "cannot add when full")

        prefs.remove(.calendar)
        prefs.add(.field)
        XCTAssertEqual(prefs.favorites, [.roster, .game, .field])

        prefs.add(.roster) // duplicate
        XCTAssertEqual(prefs.favorites.filter { $0 == .roster }.count, 1)
    }

    func testHomeCannotBeAddedAsAFavorite() {
        let prefs = TabPreferences(defaults: makeDefaults())
        prefs.remove(.calendar)
        prefs.add(.dashboard)
        XCTAssertFalse(prefs.favorites.contains(.dashboard))
    }

    func testAvailableExcludesHomeAndFavorites() {
        let prefs = TabPreferences(defaults: makeDefaults())
        XCTAssertFalse(prefs.available.contains(.dashboard))
        for favorite in prefs.favorites {
            XCTAssertFalse(prefs.available.contains(favorite))
        }
        XCTAssertTrue(prefs.available.contains(.field))
    }

    func testMoveReorders() {
        let prefs = TabPreferences(defaults: makeDefaults())
        prefs.move(fromOffsets: IndexSet(integer: 2), toOffset: 0) // game -> front
        XCTAssertEqual(prefs.favorites, [.game, .calendar, .roster])
    }

    func testChoicesPersistAcrossInstances() {
        let defaults = makeDefaults()
        let first = TabPreferences(defaults: defaults)
        first.remove(.calendar)
        first.add(.field)

        let second = TabPreferences(defaults: defaults)
        XCTAssertEqual(second.favorites, [.roster, .game, .field])
    }

    func testLoadSanitizesDuplicatesPinnedAndOverflow() {
        let defaults = makeDefaults()
        // Home present, a duplicate, and more than the cap.
        defaults.set("Home,Roster,Roster,Field,Drills,Season", forKey: "favoriteSections.v1")
        let prefs = TabPreferences(defaults: defaults)
        XCTAssertEqual(prefs.favorites, [.roster, .field, .drills], "drops Home + dupes, caps at 3")
    }
}
