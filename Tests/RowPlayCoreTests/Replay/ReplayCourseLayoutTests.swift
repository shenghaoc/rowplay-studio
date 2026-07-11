import XCTest
@testable import RowPlayCore

final class ReplayCourseLayoutTests: XCTestCase {
    private let layout = ReplayCourseLayout.standard

    // MARK: - Basic Position

    func testPositionAtZeroIsOnCircle() {
        let pos = layout.position(at: 0)
        XCTAssertTrue(pos.x.isFinite)
        XCTAssertTrue(pos.z.isFinite)
        XCTAssertEqual(pos.y, 0, accuracy: 0.001)
        // At distance 0, angle=0, so x=0, z=radius
        XCTAssertEqual(pos.x, 0, accuracy: 0.001)
        XCTAssertEqual(pos.z, layout.loopRadius, accuracy: 0.001)
    }

    func testPositionAtQuarterLap() {
        let pos = layout.position(at: 100) // 100m = 1/4 of 400m
        XCTAssertTrue(pos.x.isFinite)
        XCTAssertTrue(pos.z.isFinite)
        // At 90° (quarter), x=radius, z≈0
        XCTAssertEqual(pos.x, layout.loopRadius, accuracy: 0.01)
        XCTAssertEqual(pos.z, 0, accuracy: 0.01)
    }

    func testPositionAtHalfLap() {
        let pos = layout.position(at: 200)
        XCTAssertEqual(pos.x, 0, accuracy: 0.01)
        XCTAssertEqual(pos.z, -layout.loopRadius, accuracy: 0.01)
    }

    // MARK: - Multiple Laps

    func testMultipleLapsWrapCorrectly() {
        let pos1 = layout.position(at: 0)
        let pos2 = layout.position(at: 400) // one full lap
        XCTAssertEqual(pos1.x, pos2.x, accuracy: 0.001)
        XCTAssertEqual(pos1.z, pos2.z, accuracy: 0.001)
    }

    func testThreeLapsWrap() {
        let pos1 = layout.position(at: 100)
        let pos2 = layout.position(at: 900) // 100 + 2*400
        XCTAssertEqual(pos1.x, pos2.x, accuracy: 0.001)
        XCTAssertEqual(pos1.z, pos2.z, accuracy: 0.001)
    }

    // MARK: - Negative Distance

    func testNegativeDistanceProducesFinitePosition() {
        let pos = layout.position(at: -100)
        XCTAssertTrue(pos.x.isFinite)
        XCTAssertTrue(pos.y.isFinite)
        XCTAssertTrue(pos.z.isFinite)
    }

    func testNegativeDistanceIsOppositeDirection() {
        let posForward = layout.position(at: 100)
        let posBack = layout.position(at: -100)
        // -100m should be at angle = -π/2, which is x=-radius, z≈0
        XCTAssertEqual(posBack.x, -layout.loopRadius, accuracy: 0.01)
        XCTAssertEqual(posForward.x, layout.loopRadius, accuracy: 0.01)
    }

    // MARK: - Lanes

    func testLaneOffsetDisplacesLateral() {
        let posCenter = layout.position(at: 0, laneOffset: 0)
        let posOuter = layout.position(at: 0, laneOffset: 2)
        XCTAssertEqual(posCenter.x, 0, accuracy: 0.001)
        XCTAssertEqual(posOuter.z, layout.loopRadius + 2, accuracy: 0.01)
    }

    func testGhostPositionUsesGhostRadius() {
        let ghostPos = layout.ghostPosition(at: 0)
        XCTAssertEqual(ghostPos.z, layout.ghostRadius, accuracy: 0.001)
        XCTAssertTrue(ghostPos.z < layout.loopRadius, "Ghost should be inside the live lane")
    }

    // MARK: - Tangent

    func testTangentIsUnitLength() {
        for dist in stride(from: 0.0, to: 800.0, by: 50.0) {
            let t = layout.tangent(at: dist)
            let length = sqrt(t.x * t.x + t.y * t.y + t.z * t.z)
            XCTAssertEqual(length, 1.0, accuracy: 0.001, "Tangent at \(dist)m should be unit length")
        }
    }

    func testTangentIsPerpendicularToRadial() {
        let pos = layout.position(at: 100)
        let t = layout.tangent(at: 100)
        // dot product should be ≈ 0
        let dot = pos.x * t.x + pos.y * t.y + pos.z * t.z
        XCTAssertEqual(dot, 0, accuracy: 0.01, "Tangent should be perpendicular to radial")
    }

    // MARK: - Heading Angle

    func testHeadingAngleIsFinite() {
        for dist in stride(from: 0.0, to: 1200.0, by: 100.0) {
            let angle = layout.headingAngle(at: dist)
            XCTAssertTrue(angle.isFinite, "Heading at \(dist)m should be finite")
        }
    }

    // MARK: - Lap Count

    func testLapCount() {
        XCTAssertEqual(layout.lapCount(for: 200), 1)
        XCTAssertEqual(layout.lapCount(for: 400), 1)
        XCTAssertEqual(layout.lapCount(for: 401), 2)
        XCTAssertEqual(layout.lapCount(for: 800), 2)
        XCTAssertEqual(layout.lapCount(for: 1200), 3)
    }

    func testCurrentLap() {
        XCTAssertEqual(layout.currentLap(for: 0), 1)
        XCTAssertEqual(layout.currentLap(for: 200), 1)
        XCTAssertEqual(layout.currentLap(for: 400), 1)
        XCTAssertEqual(layout.currentLap(for: 401), 2)
        XCTAssertEqual(layout.currentLap(for: 800), 2)
    }

    // MARK: - Non-Finite Input

    func testNonFiniteDistanceProducesFinitePosition() {
        let pos = layout.position(at: .nan)
        XCTAssertTrue(pos.x.isFinite)
        XCTAssertTrue(pos.y.isFinite)
        XCTAssertTrue(pos.z.isFinite)
    }

    func testInfiniteDistanceProducesFinitePosition() {
        let pos = layout.position(at: .infinity)
        XCTAssertTrue(pos.x.isFinite)
        XCTAssertTrue(pos.y.isFinite)
        XCTAssertTrue(pos.z.isFinite)
    }

    func testNonFiniteLaneOffsetProducesFinitePosition() {
        let pos = layout.position(at: 100, laneOffset: .nan)
        XCTAssertTrue(pos.x.isFinite)
        XCTAssertTrue(pos.z.isFinite)
    }

    // MARK: - Overflow Safety

    func testLapCountHandlesVeryLargeDistance() {
        // Should not crash — guards Double→Int overflow.
        let count = layout.lapCount(for: .greatestFiniteMagnitude)
        XCTAssertEqual(count, Int.max)
    }

    func testCurrentLapHandlesVeryLargeDistance() {
        // Should not crash — guards Double→Int overflow.
        let lap = layout.currentLap(for: .greatestFiniteMagnitude)
        XCTAssertTrue(lap > 0)
    }

    func testLapCountHandlesNaN() {
        let count = layout.lapCount(for: .nan)
        XCTAssertEqual(count, 1)
    }

    func testCurrentLapHandlesNaN() {
        let lap = layout.currentLap(for: .nan)
        XCTAssertEqual(lap, 1)
    }

    // MARK: - Standard Layout

    func testStandardLayoutHasPositiveRadii() {
        XCTAssertTrue(ReplayCourseLayout.standard.loopRadius > 0)
        XCTAssertTrue(ReplayCourseLayout.standard.ghostRadius > 0)
        XCTAssertTrue(ReplayCourseLayout.standard.ghostRadius < ReplayCourseLayout.standard.loopRadius)
    }
}
