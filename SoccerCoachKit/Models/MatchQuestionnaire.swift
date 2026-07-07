import Foundation

/// A player's pre-match readiness check-in. Every scale is 1...5 where **higher
/// is better** (0 = not recorded), so an overall readiness score is simply their
/// mean — which makes "poor sleep → poor game" patterns easy to surface later.
struct PreMatchCheckIn: Hashable, Codable {
    var sleep: Int
    var energy: Int
    /// Physical freshness — the inverse of soreness (5 = fresh, 1 = very sore).
    var freshness: Int
    var hydration: Int
    var nutrition: Int
    var mood: Int
    /// Composure — the inverse of nerves (5 = calm, 1 = very nervous).
    var composure: Int
    var focus: Int
    /// nil = not asked, true/false = the answer.
    var warmedUp: Bool?
    var hasPain: Bool?
    var note: String

    init(sleep: Int = 0, energy: Int = 0, freshness: Int = 0, hydration: Int = 0,
         nutrition: Int = 0, mood: Int = 0, composure: Int = 0, focus: Int = 0,
         warmedUp: Bool? = nil, hasPain: Bool? = nil, note: String = "") {
        self.sleep = sleep
        self.energy = energy
        self.freshness = freshness
        self.hydration = hydration
        self.nutrition = nutrition
        self.mood = mood
        self.composure = composure
        self.focus = focus
        self.warmedUp = warmedUp
        self.hasPain = hasPain
        self.note = note
    }

    /// The labeled 1-5 wellness scales, in display order. Used for the form,
    /// summaries, and correlation.
    var scales: [(key: String, label: String, value: Int)] {
        [
            ("sleep", "Sleep", sleep),
            ("energy", "Energy", energy),
            ("freshness", "Freshness", freshness),
            ("hydration", "Hydration", hydration),
            ("nutrition", "Nutrition", nutrition),
            ("mood", "Mood", mood),
            ("composure", "Composure", composure),
            ("focus", "Focus", focus),
        ]
    }

    /// Mean of the recorded wellness scales; `nil` when none are rated.
    var readiness: Double? {
        let rated = scales.map(\.value).filter { $0 > 0 }
        guard !rated.isEmpty else { return nil }
        return Double(rated.reduce(0, +)) / Double(rated.count)
    }

    var isEmpty: Bool {
        readiness == nil && warmedUp == nil && hasPain == nil
            && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case sleep, energy, freshness, hydration, nutrition, mood, composure, focus, warmedUp, hasPain, note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sleep = try c.decodeIfPresent(Int.self, forKey: .sleep) ?? 0
        energy = try c.decodeIfPresent(Int.self, forKey: .energy) ?? 0
        freshness = try c.decodeIfPresent(Int.self, forKey: .freshness) ?? 0
        hydration = try c.decodeIfPresent(Int.self, forKey: .hydration) ?? 0
        nutrition = try c.decodeIfPresent(Int.self, forKey: .nutrition) ?? 0
        mood = try c.decodeIfPresent(Int.self, forKey: .mood) ?? 0
        composure = try c.decodeIfPresent(Int.self, forKey: .composure) ?? 0
        focus = try c.decodeIfPresent(Int.self, forKey: .focus) ?? 0
        warmedUp = try c.decodeIfPresent(Bool.self, forKey: .warmedUp)
        hasPain = try c.decodeIfPresent(Bool.self, forKey: .hasPain)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

/// A player's post-match reflection — how the game felt and what to build on.
struct PostMatchReflection: Hashable, Codable {
    var exertion: Int     // RPE (1 easy … 5 maximal)
    var performance: Int  // self-rating (1…5)
    var enjoyment: Int
    var fatigue: Int      // (1 fresh … 5 exhausted)
    var confidence: Int
    var hadInjury: Bool?
    var wentWell: String
    var workOn: String

    init(exertion: Int = 0, performance: Int = 0, enjoyment: Int = 0, fatigue: Int = 0,
         confidence: Int = 0, hadInjury: Bool? = nil, wentWell: String = "", workOn: String = "") {
        self.exertion = exertion
        self.performance = performance
        self.enjoyment = enjoyment
        self.fatigue = fatigue
        self.confidence = confidence
        self.hadInjury = hadInjury
        self.wentWell = wentWell
        self.workOn = workOn
    }

    var scales: [(key: String, label: String, value: Int)] {
        [
            ("exertion", "Effort (RPE)", exertion),
            ("performance", "Performance", performance),
            ("enjoyment", "Enjoyment", enjoyment),
            ("fatigue", "Fatigue", fatigue),
            ("confidence", "Confidence", confidence),
        ]
    }

    var isEmpty: Bool {
        scales.allSatisfy { $0.value == 0 } && hadInjury == nil
            && wentWell.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && workOn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case exertion, performance, enjoyment, fatigue, confidence, hadInjury, wentWell, workOn
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exertion = try c.decodeIfPresent(Int.self, forKey: .exertion) ?? 0
        performance = try c.decodeIfPresent(Int.self, forKey: .performance) ?? 0
        enjoyment = try c.decodeIfPresent(Int.self, forKey: .enjoyment) ?? 0
        fatigue = try c.decodeIfPresent(Int.self, forKey: .fatigue) ?? 0
        confidence = try c.decodeIfPresent(Int.self, forKey: .confidence) ?? 0
        hadInjury = try c.decodeIfPresent(Bool.self, forKey: .hadInjury)
        wentWell = try c.decodeIfPresent(String.self, forKey: .wentWell) ?? ""
        workOn = try c.decodeIfPresent(String.self, forKey: .workOn) ?? ""
    }
}

/// The coach's pre-match plan for the whole team.
struct CoachPreMatchPlan: Hashable, Codable {
    var objective: String = ""
    var keyMatchup: String = ""
    var focusPoints: String = ""
    var watchFor: String = ""

    var isEmpty: Bool {
        [objective, keyMatchup, focusPoints, watchFor]
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

/// The coach's post-match review of the whole team.
struct CoachPostMatchReview: Hashable, Codable {
    var teamPerformance: Int = 0 // 1…5
    var whatWorked: String = ""
    var whatToAdjust: String = ""
    var standoutPlayer: String = ""

    var isEmpty: Bool {
        teamPerformance == 0
            && [whatWorked, whatToAdjust, standoutPlayer]
                .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
