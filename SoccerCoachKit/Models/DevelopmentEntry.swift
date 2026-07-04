import Foundation

/// The skills a coach rates when tracking a player's development.
enum SkillCategory: String, CaseIterable, Identifiable, Codable {
    case technical = "Technical"
    case passing = "Passing"
    case shooting = "Shooting"
    case defending = "Defending"
    case tactical = "Tactical"
    case attitude = "Attitude"

    var id: String { rawValue }
}

/// A dated development record for a player: coach notes plus 1–5 skill ratings,
/// so growth can be tracked over a season.
struct DevelopmentEntry: Identifiable, Hashable, Codable {
    let id: UUID
    var date: Date
    var notes: String
    /// Ratings keyed by `SkillCategory.rawValue` (a String key so it serializes
    /// as a plain JSON object); 1...5, an absent key means unrated.
    var ratings: [String: Int]

    init(id: UUID = UUID(), date: Date = Date(), notes: String = "", ratings: [String: Int] = [:]) {
        self.id = id
        self.date = date
        self.notes = notes
        self.ratings = ratings
    }

    func rating(for skill: SkillCategory) -> Int { ratings[skill.rawValue] ?? 0 }

    /// Skills that carry a rating, in canonical order.
    var ratedSkills: [SkillCategory] { SkillCategory.allCases.filter { rating(for: $0) > 0 } }

    var isEmpty: Bool {
        notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ratings.values.allSatisfy { $0 == 0 }
    }
}
