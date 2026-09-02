import XCTest
@testable import SoccerCoachKit

/// Pins the US Soccer Player Development Initiatives standards the app derives
/// its format, roster cap and playing-time goal from. These are published
/// national values, so a change here should be a deliberate correction rather
/// than a side effect of touching something else.
final class USSoccerStandardTests: XCTestCase {

    // MARK: - The small-sided tiers

    func testFourVFourTierIsUnderNine() {
        for ageGroup in [AgeGroup.u6, .u7, .u8] {
            let standard = ageGroup.standard
            XCTAssertEqual(standard.playersPerSide, 4, "\(ageGroup.rawValue) plays 4v4")
            XCTAssertFalse(standard.usesGoalkeeper, "\(ageGroup.rawValue) has no keeper")
            XCTAssertEqual(standard.ballSize, 3)
            XCTAssertFalse(standard.offsideEnforced, "no offside in 4v4")
            XCTAssertEqual(standard.periodCount, 4, "4v4 is played in quarters")
        }
    }

    /// The build-out line is what defines the 7v7 tier, and only that tier.
    func testBuildOutLineIsSevenVSevenOnly() {
        for ageGroup in AgeGroup.allCases {
            XCTAssertEqual(ageGroup.standard.hasBuildOutLine,
                           ageGroup.standard.playersPerSide == 7,
                           "\(ageGroup.rawValue): the build-out line belongs to 7v7")
        }
    }

    func testSevenVSevenTier() {
        for ageGroup in [AgeGroup.u9, .u10] {
            let standard = ageGroup.standard
            XCTAssertEqual(standard.playersPerSide, 7)
            XCTAssertTrue(standard.usesGoalkeeper)
            XCTAssertEqual(standard.ballSize, 4)
            XCTAssertTrue(standard.offsideEnforced)
            XCTAssertEqual(standard.gameMinutes, 50, "two 25-minute halves")
        }
    }

    func testNineVNineTier() {
        for ageGroup in [AgeGroup.u11, .u12] {
            let standard = ageGroup.standard
            XCTAssertEqual(standard.playersPerSide, 9)
            XCTAssertEqual(standard.ballSize, 4)
            XCTAssertFalse(standard.hasBuildOutLine)
            XCTAssertEqual(standard.gameMinutes, 60)
        }
    }

    func testFullSidedFromThirteen() {
        for ageGroup in [AgeGroup.u13, .u14, .u15, .u16, .u17, .u18, .u19] {
            let standard = ageGroup.standard
            XCTAssertEqual(standard.playersPerSide, 11, "\(ageGroup.rawValue) is full-sided")
            XCTAssertEqual(standard.ballSize, 5)
            XCTAssertEqual(standard.goalWidthFeet, 24)
        }
        // Only the period length keeps growing.
        XCTAssertEqual(AgeGroup.u14.standard.gameMinutes, 70)
        XCTAssertEqual(AgeGroup.u16.standard.gameMinutes, 80)
        XCTAssertEqual(AgeGroup.u19.standard.gameMinutes, 90)
    }

    // MARK: - Heading

    /// The heading restriction is age-banded, not format-banded — it's the one
    /// standard that doesn't follow the small-sided tiers, so U11 and U12 differ
    /// while playing the identical game.
    func testHeadingOpensUpAtTwelve() {
        for ageGroup in [AgeGroup.u6, .u7, .u8, .u9, .u10, .u11] {
            XCTAssertEqual(ageGroup.standard.heading, .notPermitted,
                           "\(ageGroup.rawValue) must not head the ball")
        }
        XCTAssertEqual(AgeGroup.u12.standard.heading, .limitedInTraining)
        XCTAssertEqual(AgeGroup.u13.standard.heading, .limitedInTraining)
        for ageGroup in [AgeGroup.u14, .u15, .u16, .u17, .u18, .u19] {
            XCTAssertEqual(ageGroup.standard.heading, .permitted)
        }
    }

    func testHeadingAndFormatDivergeAtEleven() {
        XCTAssertEqual(AgeGroup.u11.standard.playersPerSide, AgeGroup.u12.standard.playersPerSide,
                       "same game")
        XCTAssertNotEqual(AgeGroup.u11.standard.heading, AgeGroup.u12.standard.heading,
                          "different heading rule — which is why single-year groups matter")
    }

    // MARK: - Roster and playing time

    func testRosterLimitFollowsTheFormat() {
        let expected: [Int: Int] = [4: 8, 7: 14, 9: 18, 11: 22]
        for ageGroup in AgeGroup.allCases {
            let standard = ageGroup.standard
            XCTAssertEqual(standard.maxRosterSize, expected[standard.playersPerSide],
                           "\(ageGroup.rawValue) (\(standard.playersPerSide)v\(standard.playersPerSide))")
        }
    }

    /// US Soccer's development guidance is half the match for every player.
    func testEveryAgeGroupRecommendsHalfTheMatch() {
        for ageGroup in AgeGroup.allCases {
            let standard = ageGroup.standard
            XCTAssertEqual(standard.recommendedMinimumMinutes, standard.gameMinutes / 2,
                           "\(ageGroup.rawValue)")
        }
    }

    /// A roster limit that didn't leave room to rotate would defeat the point.
    func testEveryRosterLimitAllowsSubstitutes() {
        for ageGroup in AgeGroup.allCases {
            let standard = ageGroup.standard
            XCTAssertGreaterThan(standard.maxRosterSize, standard.playersPerSide,
                                 "\(ageGroup.rawValue) must have room for a bench")
        }
    }

    // MARK: - Derived values the rest of the app reads

    func testAgeGroupPassesThroughToTheStandard() {
        for ageGroup in AgeGroup.allCases {
            XCTAssertEqual(ageGroup.playersOnField, ageGroup.standard.playersPerSide)
            XCTAssertEqual(ageGroup.maxRosterSize, ageGroup.standard.maxRosterSize)
            XCTAssertEqual(ageGroup.defaultGameMinutes, ageGroup.standard.gameMinutes)
        }
    }

    func testPeriodFormatDefaultFollowsTheStandard() {
        XCTAssertEqual(PeriodFormat.default(for: .u8), .quarters)
        XCTAssertEqual(PeriodFormat.default(for: .u9), .halves, "7v7 up is played in halves")
        XCTAssertEqual(PeriodFormat.default(for: .u19), .halves)
    }

    /// A new team's playing-time goal is the recommendation.
    func testANewTeamStartsAtTheRecommendedMinimum() {
        let team = Team(id: UUID(), name: "FC", ageGroup: .u10, season: "2026", accentName: "Teal")
        XCTAssertEqual(team.defaultMinimumMinutes, AgeGroup.u10.standard.recommendedMinimumMinutes)
        XCTAssertEqual(team.defaultMinimumMinutes, 25)
    }

    // MARK: - Migration

    /// The single-year groups are additions: every age group a team could
    /// already be saved under still decodes to itself.
    func testTheAgeGroupsTeamsWereAlreadySavedUnderStillDecode() throws {
        for raw in ["U6", "U8", "U10", "U12", "U14", "U16", "U19"] {
            let decoded = try JSONDecoder().decode(AgeGroup.self, from: Data("\"\(raw)\"".utf8))
            XCTAssertEqual(decoded.rawValue, raw)
        }
    }

    func testTheOddYearsAreAvailable() {
        let raws = Set(AgeGroup.allCases.map(\.rawValue))
        for raw in ["U7", "U9", "U11", "U13", "U15", "U17", "U18"] {
            XCTAssertTrue(raws.contains(raw), "\(raw) should be offered")
        }
        XCTAssertEqual(AgeGroup.allCases.count, 14, "U6 through U19, every year")
    }

    /// The groups are listed youngest first, so the picker reads in age order.
    func testAgeGroupsAreOrdered() {
        let ages = AgeGroup.allCases.map { Int($0.rawValue.dropFirst())! }
        XCTAssertEqual(ages, ages.sorted())
    }
}

// MARK: - Age groups this build does not know

extension USSoccerStandardTests {

    func testKnownAgeGroupIsItsOwnBand() {
        for ageGroup in AgeGroup.allCases {
            XCTAssertEqual(AgeGroup.nearestKnown(to: ageGroup.rawValue), ageGroup)
        }
    }

    /// Rounding is downward on purpose. Heading is the standard that exists to protect a
    /// child's head, and it is the one that would be wrong in the other direction: U11
    /// rounded up to U12 would show heading as permitted in matches for a team that must
    /// not head at all.
    func testUnknownBandRoundsDownSoNoPermissionIsInvented() {
        // A hypothetical band between two we know.
        XCTAssertEqual(AgeGroup.nearestKnown(to: "U11.5"), .u11)
        XCTAssertEqual(AgeGroup.nearestKnown(to: "U11").standard.heading, .notPermitted)
        XCTAssertEqual(AgeGroup.nearestKnown(to: "U11.5").standard.heading, .notPermitted,
                       "a band we cannot place must not grant heading")
    }

    func testUnknownBandsClampToTheEndsOfTheRange() {
        XCTAssertEqual(AgeGroup.nearestKnown(to: "U4"), .u6, "younger than anything we know")
        XCTAssertEqual(AgeGroup.nearestKnown(to: "U20"), .u19, "older than anything we know")
        XCTAssertEqual(AgeGroup.nearestKnown(to: "U23"), .u19)
    }

    func testLabelsThatAreNotBandsFallToTheYoungest() {
        for label in ["2015B", "High School", "", "U", "Recreational"] {
            XCTAssertEqual(AgeGroup.nearestKnown(to: label), .u6,
                           "\(label): nothing to place, so nothing is granted")
        }
    }

    func testBandParsingToleratesCaseAndSpacing() {
        XCTAssertEqual(AgeGroup.nearestKnown(to: "u12"), .u12)
        XCTAssertEqual(AgeGroup.nearestKnown(to: " U12 "), .u12)
    }
}
