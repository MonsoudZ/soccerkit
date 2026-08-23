import XCTest
@testable import SoccerCoachKit

/// The tactics board stores everything in normalized (0...1) coordinates so a
/// diagram drawn on an iPhone opens correctly on an iPad. These four functions
/// are the entire conversion between that stored form and the pitch actually on
/// screen — shared by the interactive canvas, the markers, and the export view,
/// so a mistake here misplaces a saved diagram everywhere at once.
final class BoardGeometryTests: XCTestCase {
    /// Deliberately not at the origin: an offset pitch is what catches a
    /// conversion that forgets to subtract or add the rect's own position.
    private let pitch = CGRect(x: 40, y: 100, width: 200, height: 400)

    // MARK: - Round trip

    func testNormalizeAndAbsoluteAreInverses() {
        for point in [CGPoint(x: 40, y: 100),    // top-left corner
                      CGPoint(x: 240, y: 500),   // bottom-right corner
                      CGPoint(x: 140, y: 300),   // centre
                      CGPoint(x: 76, y: 460)] {  // somewhere arbitrary
            let roundTripped = absolute(normalize(point, in: pitch), in: pitch)
            XCTAssertEqual(roundTripped.x, point.x, accuracy: 0.0001, "x survives the round trip")
            XCTAssertEqual(roundTripped.y, point.y, accuracy: 0.0001, "y survives the round trip")
        }
    }

    func testCornersAndCentreMapToTheExpectedFractions() {
        XCTAssertEqual(normalize(CGPoint(x: 40, y: 100), in: pitch), CGPoint(x: 0, y: 0))
        XCTAssertEqual(normalize(CGPoint(x: 240, y: 500), in: pitch), CGPoint(x: 1, y: 1))
        XCTAssertEqual(normalize(CGPoint(x: 140, y: 300), in: pitch), CGPoint(x: 0.5, y: 0.5))
    }

    /// A marker dragged past the touchline is pinned to it rather than stored
    /// out of range, where it would render off the pitch on every other device.
    func testNormalizeClampsPointsDraggedOffThePitch() {
        XCTAssertEqual(normalize(CGPoint(x: -500, y: -500), in: pitch), CGPoint(x: 0, y: 0))
        XCTAssertEqual(normalize(CGPoint(x: 5000, y: 5000), in: pitch), CGPoint(x: 1, y: 1))

        // Off on one axis only: the other keeps its real value.
        let overshootX = normalize(CGPoint(x: 1000, y: 300), in: pitch)
        XCTAssertEqual(overshootX.x, 1)
        XCTAssertEqual(overshootX.y, 0.5, accuracy: 0.0001)
    }

    // MARK: - Absolute

    /// `absolute` deliberately does not clamp — it is the render step, and a
    /// stored value is already in range.
    func testAbsoluteScalesIntoTheRectIncludingItsOffset() {
        XCTAssertEqual(absolute(CGPoint(x: 0, y: 0), in: pitch), CGPoint(x: 40, y: 100))
        XCTAssertEqual(absolute(CGPoint(x: 1, y: 1), in: pitch), CGPoint(x: 240, y: 500))
        XCTAssertEqual(absolute(CGPoint(x: 0.25, y: 0.75), in: pitch), CGPoint(x: 90, y: 400))
    }

    func testAbsoluteRectScalesOriginAndSizeTogether() {
        let zone = CGRect(x: 0.5, y: 0, width: 0.5, height: 0.25)
        let drawn = absolute(zone, in: pitch)

        XCTAssertEqual(drawn.minX, 140, accuracy: 0.0001, "Half way across, plus the pitch's own x")
        XCTAssertEqual(drawn.minY, 100, accuracy: 0.0001)
        XCTAssertEqual(drawn.width, 100, accuracy: 0.0001, "Half the width")
        XCTAssertEqual(drawn.height, 100, accuracy: 0.0001, "A quarter of the height")
    }

    /// A zone covering the whole board comes back as the pitch itself.
    func testAFullBoardRectMapsToTheWholePitch() {
        XCTAssertEqual(absolute(CGRect(x: 0, y: 0, width: 1, height: 1), in: pitch), pitch)
    }

    // MARK: - Clamp

    func testClampBoundsToTheUnitRangeByDefault() {
        XCTAssertEqual(clamp(-0.5), 0)
        XCTAssertEqual(clamp(0), 0)
        XCTAssertEqual(clamp(0.5), 0.5)
        XCTAssertEqual(clamp(1), 1)
        XCTAssertEqual(clamp(1.5), 1)
    }

    func testClampHonoursExplicitBounds() {
        XCTAssertEqual(clamp(5, min: 10, max: 20), 10)
        XCTAssertEqual(clamp(15, min: 10, max: 20), 15)
        XCTAssertEqual(clamp(25, min: 10, max: 20), 20)
    }
}
