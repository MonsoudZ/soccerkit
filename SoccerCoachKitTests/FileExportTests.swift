import XCTest
@testable import SoccerCoachKit

/// Exporting used to answer a failed write with `guard let url = … else
/// { return }` on two of the three paths: the coach tapped Export, nothing
/// opened, and nothing was said. These cover the shared writer that replaced
/// them, including the failure that used to be silent.
final class FileExportTests: XCTestCase {

    func testWriteProducesAReadableFile() throws {
        let data = Data("name,number\nAva,9\n".utf8)

        let url = try FileExport.write(data, named: "export-test-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    /// The point of throwing rather than returning nil. A caller can still
    /// ignore this, but it has to do so on purpose.
    func testWriteThrowsWhenItCannotWrite() {
        // A path whose parent directory doesn't exist: the write has nowhere
        // to land, which is what a real failure looks like from here.
        let name = "no-such-directory-\(UUID().uuidString)/roster.csv"

        XCTAssertThrowsError(try FileExport.write(Data("x".utf8), named: name))
    }

    // MARK: - Filenames

    func testSlugKeepsWordsAndDropsPunctuation() {
        XCTAssertEqual(FileExport.slug("U12 Rovers (A)", fallback: "roster"), "U12-Rovers-A")
        XCTAssertEqual(FileExport.slug("Tuesday Session #1", fallback: "session"), "Tuesday-Session-1")
    }

    /// Filtering alone left "!!! ???" as a bare "-", which is not empty, so the
    /// fallback never fired and the file came out named "--roster.csv".
    func testSlugFallsBackWhenNothingMeaningfulSurvives() {
        XCTAssertEqual(FileExport.slug("", fallback: "roster"), "roster")
        XCTAssertEqual(FileExport.slug("!!! ???", fallback: "session"), "session")
        XCTAssertEqual(FileExport.slug("---", fallback: "roster"), "roster")
    }

    func testSlugCollapsesAndTrimsSeparators() {
        XCTAssertEqual(FileExport.slug("U12  Rovers", fallback: "roster"), "U12-Rovers")
        XCTAssertEqual(FileExport.slug("  Rovers  ", fallback: "roster"), "Rovers")
        XCTAssertEqual(FileExport.slug("(Rovers)", fallback: "roster"), "Rovers")
    }

    /// A team name is free text. Left whole it would push the filename past the
    /// filesystem's 255-byte component limit and fail the write — a failure the
    /// coach now hears about but still can't do anything about, so don't make
    /// it in the first place.
    func testSlugTruncatesALongTitle() {
        let long = String(repeating: "a", count: 500)

        let slug = FileExport.slug(long, fallback: "roster")

        XCTAssertLessThanOrEqual(slug.utf8.count, 120)
        XCTAssertTrue(slug.allSatisfy { $0 == "a" }, "truncation must not corrupt the text it keeps")
    }

    /// The budget is bytes, not characters: the filter keeps any Unicode
    /// letter, and those cost more than one byte each.
    func testSlugCountsMultibyteCharactersByTheirBytes() {
        let long = String(repeating: "東", count: 200)   // 3 bytes each

        let slug = FileExport.slug(long, fallback: "roster")

        XCTAssertLessThanOrEqual(slug.utf8.count, 120)
        XCTAssertFalse(slug.isEmpty, "a name that is entirely multibyte is still a usable name")
        XCTAssertTrue(slug.allSatisfy { $0 == "東" }, "the cut must land on a character boundary")
    }

    /// A truncated title still has to leave room for what the exporters append.
    func testTruncatedNamesStayWithinTheFilesystemLimit() {
        let team = Team(id: UUID(), name: String(repeating: "Rovers ", count: 100),
                        ageGroup: .u12, season: "2026", accentName: "Teal")
        let session = TrainingSession(id: UUID(), teamID: team.id,
                                      title: String(repeating: "Session ", count: 100),
                                      date: Date(), objective: "", blocks: [], attendance: [:])

        XCTAssertLessThanOrEqual(RosterExporter.fileName(for: team, extension: "csv").utf8.count, 255)
        XCTAssertLessThanOrEqual(SessionExporter.fileName(for: session).utf8.count, 255)
    }
}
