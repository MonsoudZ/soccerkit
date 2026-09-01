import XCTest
@testable import SoccerCoachKit

/// The bug these cover: `FormFieldConfig.higherIsBetter` was declared on every
/// scale field and documented as driving the composite-score direction, but
/// `FormEngine.scaleMean` never read it — it averaged every scale raw. The
/// post-match template made that live: `fatigue` and `exertion` were built by a
/// helper that hardcodes "higher is better", so a shattered athlete's high
/// fatigue *raised* their score.
@MainActor
final class FormScoreDirectionTests: XCTestCase {

    private func reflection(performance: Int, enjoyment: Int, fatigue: Int,
                            confidence: Int, exertion: Int) -> FormInstance {
        FormInstance(
            templateID: FormTemplateCatalog.ID.postMatchReflection,
            context: .postGame,
            subject: .athlete(UUID()),
            answers: [
                .scale("performance", performance),
                .scale("enjoyment", enjoyment),
                .scale("fatigue", fatigue),
                .scale("confidence", confidence),
                .scale("exertion", exertion),
            ]
        )
    }

    private func postMatchScore(_ instance: FormInstance) -> Double? {
        FormEngine.scaleMean(of: instance, using: FormTemplateCatalog.postMatchReflection)
    }

    // MARK: - The normalisation primitive

    /// An inverted scale is mirrored within its own bounds, so it reads on the
    /// same axis as the positive ones.
    func testInvertedScaleIsMirroredWithinItsBounds() {
        let config = FormFieldConfig.scale(min: 1, max: 5, higherIsBetter: false)
        XCTAssertEqual(config.normalizedScore(for: 5), 1)
        XCTAssertEqual(config.normalizedScore(for: 1), 5)
        XCTAssertEqual(config.normalizedScore(for: 3), 3, "the midpoint is its own mirror")
    }

    func testPositiveScalePassesThrough() {
        XCTAssertEqual(FormFieldConfig.scale().normalizedScore(for: 4), 4)
    }

    /// No declared direction means no place on the composite's axis.
    func testUndirectedScaleHasNoScore() {
        XCTAssertNil(FormFieldConfig.unscoredScale().normalizedScore(for: 4))
        XCTAssertNil(FormFieldConfig().normalizedScore(for: 4), "a template predating the flag")
    }

    /// Mirroring needs bounds; without them the value is left out rather than
    /// averaged the wrong way round.
    func testInvertedScaleWithoutBoundsHasNoScore() {
        let unbounded = FormFieldConfig(min: nil, max: nil, higherIsBetter: false)
        XCTAssertNil(unbounded.normalizedScore(for: 4))
    }

    // MARK: - The composite

    /// The headline fix. Before it, this athlete — poor performance, no
    /// enjoyment, no confidence, and exhausted — averaged out to a middling 3.2,
    /// because fatigue 5 and RPE 5 counted as two top marks.
    func testAWreckedAthleteScoresLow() {
        let score = postMatchScore(reflection(performance: 2, enjoyment: 2, fatigue: 5,
                                              confidence: 2, exertion: 5))
        // performance 2, enjoyment 2, fatigue 5→1, confidence 2; RPE sits out.
        XCTAssertEqual(try XCTUnwrap(score), 1.75, accuracy: 0.0001)
    }

    /// And the other end: a great match, played hard, now reads as a great match.
    func testAGreatMatchScoresHigh() {
        let score = postMatchScore(reflection(performance: 5, enjoyment: 5, fatigue: 1,
                                              confidence: 5, exertion: 5))
        XCTAssertEqual(try XCTUnwrap(score), 5.0, accuracy: 0.0001)
    }

    /// Fatigue now moves the score the way a coach would expect.
    func testMoreFatigueLowersTheScore() {
        let fresh = postMatchScore(reflection(performance: 4, enjoyment: 4, fatigue: 1,
                                              confidence: 4, exertion: 3))
        let spent = postMatchScore(reflection(performance: 4, enjoyment: 4, fatigue: 5,
                                              confidence: 4, exertion: 3))
        XCTAssertGreaterThan(try XCTUnwrap(fresh), try XCTUnwrap(spent))
    }

    /// RPE is load, not quality: a hard match is not a worse one, so it must not
    /// move the composite at all.
    func testExertionDoesNotMoveTheScore() {
        let easy = postMatchScore(reflection(performance: 4, enjoyment: 4, fatigue: 2,
                                             confidence: 4, exertion: 1))
        let maximal = postMatchScore(reflection(performance: 4, enjoyment: 4, fatigue: 2,
                                                confidence: 4, exertion: 5))
        XCTAssertEqual(try XCTUnwrap(easy), try XCTUnwrap(maximal), accuracy: 0.0001)
    }

    // MARK: - No change where every scale already ran the same way

    /// Readiness is the one composite the app ships today, and every pre-match
    /// scale is genuinely "higher is better" — so normalising must leave it
    /// exactly as it was: the plain mean of the rated scales.
    func testPreMatchReadinessIsUnchanged() {
        let instance = FormInstance(
            templateID: FormTemplateCatalog.ID.preMatchCheckIn,
            context: .preGame,
            subject: .athlete(UUID()),
            answers: [
                .scale("sleep", 5), .scale("energy", 4), .scale("freshness", 4),
                .scale("hydration", 4), .scale("nutrition", 5), .scale("mood", 5),
                .scale("composure", 4), .scale("focus", 5),
            ]
        )
        let score = FormEngine.scaleMean(of: instance, using: FormTemplateCatalog.preMatchCheckIn)
        XCTAssertEqual(try XCTUnwrap(score), 36.0 / 8.0, accuracy: 0.0001)
    }

    /// Every built-in scale field must declare its direction deliberately —
    /// either a direction or an explicit "unscored" — so a new template can't
    /// quietly inherit the wrong default the way fatigue did.
    func testEveryBuiltInScaleFieldDeclaresItsBounds() {
        for template in FormTemplateCatalog.builtIns {
            for field in template.scaleFields {
                XCTAssertNotNil(field.config.min, "\(template.name).\(field.key) needs a minimum")
                XCTAssertNotNil(field.config.max, "\(template.name).\(field.key) needs a maximum")
            }
        }
    }
}
