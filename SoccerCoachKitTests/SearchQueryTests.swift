import XCTest
@testable import SoccerCoachKit

/// Search was one screen's hand-rolled `lowercased().contains`, and it got two
/// things wrong that a coach hits inside a season. These pin both, and the
/// shared matcher now behind Roster, Games, Training and Drills.
final class SearchQueryTests: XCTestCase {

    func testMatchesASubstringInAnyField() {
        XCTAssertTrue(SearchQuery.matches("rov", in: ["U12 Rovers", "Ash Lane"]))
        XCTAssertTrue(SearchQuery.matches("lane", in: ["U12 Rovers", "Ash Lane"]))
        XCTAssertFalse(SearchQuery.matches("wanderers", in: ["U12 Rovers", "Ash Lane"]))
    }

    func testIsCaseInsensitive() {
        XCTAssertTrue(SearchQuery.matches("ROVERS", in: ["U12 Rovers"]))
        XCTAssertTrue(SearchQuery.matches("rovers", in: ["U12 ROVERS"]))
    }

    /// The name was entered carefully, once. It's searched later, one-handed,
    /// on a touchline, by someone who is not going to hold down the n.
    func testFindsAnAccentedNameFromPlainLetters() {
        XCTAssertTrue(SearchQuery.matches("munoz", in: ["Ana Muñoz"]))
        XCTAssertTrue(SearchQuery.matches("jose", in: ["José Ramírez"]))
        XCTAssertTrue(SearchQuery.matches("ramirez", in: ["José Ramírez"]))
    }

    /// The accent-free spelling has to work in both directions: a coach who
    /// does type the ñ should still find a name entered without one.
    func testFindsAPlainNameFromAnAccentedQuery() {
        XCTAssertTrue(SearchQuery.matches("muñoz", in: ["Ana Munoz"]))
    }

    /// Two words mean both, not a phrase. "u12 rondo" matched nothing before,
    /// because no single field holds it — the words are in the title and tags.
    func testEveryWordMustMatchButNotInTheSameField() {
        let fields = ["Rondo 4v2", "Possession", "u12"]

        XCTAssertTrue(SearchQuery.matches("u12 rondo", in: fields))
        XCTAssertTrue(SearchQuery.matches("rondo possession", in: fields))
        XCTAssertFalse(SearchQuery.matches("u12 shooting", in: fields),
                       "one word matching is not a match")
    }

    func testWordOrderDoesNotMatter() {
        let fields = ["Rondo 4v2", "u12"]

        XCTAssertEqual(SearchQuery.matches("u12 rondo", in: fields),
                       SearchQuery.matches("rondo u12", in: fields))
    }

    // MARK: - Nothing typed

    /// An empty query matches everything, so callers can filter unconditionally
    /// instead of branching on whether a search is running.
    func testAnEmptyQueryMatchesEverything() {
        XCTAssertTrue(SearchQuery.matches("", in: ["anything"]))
        XCTAssertTrue(SearchQuery.matches("   ", in: ["anything"]))
        XCTAssertTrue(SearchQuery.matches("\n\t", in: ["anything"]))
    }

    /// Whitespace isn't a search. The distinction drives which empty state a
    /// list shows, and "no matches" over a list the coach never searched would
    /// be a lie about why it's empty.
    func testWhitespaceDoesNotCountAsSearching() {
        XCTAssertFalse(SearchQuery.isActive(""))
        XCTAssertFalse(SearchQuery.isActive("   "))
        XCTAssertTrue(SearchQuery.isActive("a"))
        XCTAssertTrue(SearchQuery.isActive("  a  "))
    }

    /// Leading and trailing spaces are what a keyboard's autocorrect leaves
    /// behind; they must not stop the search finding anything.
    func testSurroundingWhitespaceIsIgnored() {
        XCTAssertTrue(SearchQuery.matches("  rovers  ", in: ["U12 Rovers"]))
    }

    func testEmptyFieldsNeverMatchATypedQuery() {
        XCTAssertFalse(SearchQuery.matches("rovers", in: []))
        XCTAssertFalse(SearchQuery.matches("rovers", in: ["", ""]))
    }
}
