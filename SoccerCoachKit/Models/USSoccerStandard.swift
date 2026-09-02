import Foundation

/// What US Soccer says a match at a given age should look like.
///
/// These come from the Player Development Initiatives — the small-sided
/// standards that have governed youth play since the 2016-17 season — plus the
/// heading restrictions from the concussion initiative. Keeping them as data
/// rather than scattered `switch`es means the app derives the format, the ball,
/// the field, the roster cap and the playing-time goal from one place, and a
/// coach can read the age group's rulebook without leaving the app.
///
/// Two caveats worth knowing, and both are stated in the UI:
///
/// - Format, ball size, field and goal dimensions, the build-out line, offside
///   and heading are the national standard. Leagues apply them as written.
/// - Period lengths and roster maximums are *not* set nationally; they come from
///   the state association or league, and the values here are the common US
///   Youth Soccer ones. They are defaults a coach can override, not rules.
struct USSoccerStandard: Equatable {
    /// Players per side, goalkeeper included where there is one.
    let playersPerSide: Int
    let usesGoalkeeper: Bool
    let ballSize: Int
    let fieldLengthYards: ClosedRange<Int>
    let fieldWidthYards: ClosedRange<Int>
    /// Goal mouth, height × width in feet.
    let goalHeightFeet: Double
    let goalWidthFeet: Double
    /// The 7v7 build-out line: the opposition retreats behind it for goal kicks
    /// and keeper possessions, so young teams can play out from the back.
    let hasBuildOutLine: Bool
    let offsideEnforced: Bool
    let heading: HeadingRule
    let periodCount: Int
    let periodMinutes: Int
    /// League-set, not national. See the type's note.
    let maxRosterSize: Int

    var gameMinutes: Int { periodCount * periodMinutes }

    /// US Soccer's development guidance is that every player gets at least half
    /// the match; many leagues make it a rule. This is the app's default goal.
    var recommendedMinimumMinutes: Int { gameMinutes / 2 }

    var formatLabel: String {
        "\(playersPerSide)v\(playersPerSide)\(usesGoalkeeper ? " with GK" : ", no GK")"
    }

    var gameLengthLabel: String {
        "\(periodCount) × \(periodMinutes) min"
    }

    var fieldLabel: String {
        "\(fieldLengthYards.lowerBound)–\(fieldLengthYards.upperBound) × "
            + "\(fieldWidthYards.lowerBound)–\(fieldWidthYards.upperBound) yd"
    }

    var goalLabel: String {
        "\(Self.feet(goalHeightFeet)) × \(Self.feet(goalWidthFeet)) ft"
    }

    /// Trims the ".0" from whole-foot goal sizes so 8 × 24 doesn't read 8.0 × 24.0
    /// while 6.5 × 18.5 keeps its halves.
    private static func feet(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// US Soccer's heading restrictions, which are age-banded rather than
/// format-banded — the one standard that doesn't track the small-sided tiers.
enum HeadingRule: String, Equatable {
    /// U11 and younger: not in matches, not in training.
    case notPermitted = "Not permitted"
    /// U12–U13: allowed in matches, capped in training (US Soccer's guidance is
    /// about 30 minutes a week, and no more than 15–20 headers per player).
    case limitedInTraining = "Match only, limited in training"
    case permitted = "Permitted"
}

extension AgeGroup {
    /// The published standard for this age group.
    var standard: USSoccerStandard {
        switch self {
        // 4v4, no goalkeeper. The smallest sided game: no offside, no heading,
        // and quarters rather than halves.
        case .u6, .u7, .u8:
            return USSoccerStandard(
                playersPerSide: 4, usesGoalkeeper: false, ballSize: 3,
                fieldLengthYards: 25...35, fieldWidthYards: 15...25,
                goalHeightFeet: 4, goalWidthFeet: 6,
                hasBuildOutLine: false, offsideEnforced: false, heading: .notPermitted,
                periodCount: 4, periodMinutes: self == .u6 ? 8 : 10,
                maxRosterSize: 8
            )

        // 7v7 with a keeper, and the build-out line that defines this tier.
        case .u9, .u10:
            return USSoccerStandard(
                playersPerSide: 7, usesGoalkeeper: true, ballSize: 4,
                fieldLengthYards: 55...65, fieldWidthYards: 35...45,
                goalHeightFeet: 6.5, goalWidthFeet: 18.5,
                hasBuildOutLine: true, offsideEnforced: true, heading: .notPermitted,
                periodCount: 2, periodMinutes: 25,
                maxRosterSize: 14
            )

        // 9v9. Still no heading at U11; U12 may head in matches.
        case .u11, .u12:
            return USSoccerStandard(
                playersPerSide: 9, usesGoalkeeper: true, ballSize: 4,
                fieldLengthYards: 70...80, fieldWidthYards: 45...55,
                goalHeightFeet: 7, goalWidthFeet: 21,
                hasBuildOutLine: false, offsideEnforced: true,
                heading: self == .u11 ? .notPermitted : .limitedInTraining,
                periodCount: 2, periodMinutes: 30,
                maxRosterSize: 18
            )

        // Full-sided. Period length is the only thing that keeps growing.
        case .u13, .u14, .u15, .u16, .u17, .u18, .u19:
            return USSoccerStandard(
                playersPerSide: 11, usesGoalkeeper: true, ballSize: 5,
                fieldLengthYards: 100...120, fieldWidthYards: 50...80,
                goalHeightFeet: 8, goalWidthFeet: 24,
                hasBuildOutLine: false, offsideEnforced: true,
                heading: self == .u13 ? .limitedInTraining : .permitted,
                periodCount: 2, periodMinutes: Self.fullSidedPeriodMinutes(self),
                maxRosterSize: 22
            )
        }
    }

    /// The band to apply to a stored age group this build does not recognise.
    ///
    /// A newer build can write an age group an older one has never heard of — the odd
    /// years were added that way, and U4, U20 or a league's own label could be next. The
    /// value round-trips untouched (see `Team.ageGroupLabel`); this is only about which
    /// rulebook to show beside it.
    ///
    /// The rule is to round *down* to the nearest band we do know, and to clamp to the
    /// ends of the range. Rounding up would read better for format — U9 belongs with U10
    /// in 7v7, not with U8 in 4v4 — but it gets heading wrong, and heading is the one
    /// standard here that exists to protect a child's head: rounding U11 up to U12 would
    /// display heading as permitted in matches for a team that must not head at all.
    /// Showing a smaller-sided format than the team really plays is a mistake a coach
    /// spots in a second. Showing a permission they do not have is one they might not.
    ///
    /// A value with no `U<number>` in it at all — a birth-year label, say — falls to the
    /// youngest band, by the same reasoning.
    static func nearestKnown(to rawValue: String) -> AgeGroup {
        if let exact = AgeGroup(rawValue: rawValue) { return exact }

        let known = AgeGroup.allCases.sorted { $0.underAge < $1.underAge }
        guard let youngest = known.first, let oldest = known.last else { return .u10 }
        guard let age = Self.underAge(inRawValue: rawValue) else { return youngest }

        if age <= youngest.underAge { return youngest }
        if age >= oldest.underAge { return oldest }
        return known.last { $0.underAge <= age } ?? youngest
    }

    /// The number in a "U10"-shaped label, however it is cased or spaced.
    private static func underAge(inRawValue rawValue: String) -> Int? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("u") else { return nil }
        let digits = trimmed.dropFirst().prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    /// The age this band is "under": 10 for U10. Every case is `U<number>`, so this is
    /// total, and it is what orders the bands rather than the declaration order.
    var underAge: Int {
        Self.underAge(inRawValue: rawValue) ?? 0
    }

    private static func fullSidedPeriodMinutes(_ ageGroup: AgeGroup) -> Int {
        switch ageGroup {
        case .u13, .u14: return 35
        case .u15, .u16: return 40
        default: return 45
        }
    }
}
