import XCTest
@testable import RowPlayCore

final class ReplayTwoBoneSolverTests: XCTestCase {
    func testReachableThreeDimensionalSolvePreservesBothSegmentLengths() {
        let root = SIMD3<Double>(0, 0, 0)
        let solution = ReplayTwoBoneSolver.solve3D(
            root: root,
            target: SIMD3(1.2, 0.4, -0.2),
            firstLength: 1,
            secondLength: 0.8,
            bendHint: SIMD3(0, 1, 0)
        )
        XCTAssertEqual(length(solution.joint - root), 1, accuracy: 1e-9)
        XCTAssertEqual(length(solution.end - solution.joint), 0.8, accuracy: 1e-9)
        XCTAssertEqual(length(solution.end - SIMD3(1.2, 0.4, -0.2)), 0, accuracy: 1e-9)
    }

    func testUnreachableAndCoincidentSolvesStayFiniteAndDeterministic() {
        let unreachable = ReplayTwoBoneSolver.solve3D(
            root: .zero,
            target: SIMD3(100, 0, 0),
            firstLength: 0.5,
            secondLength: 0.5,
            bendHint: .zero
        )
        XCTAssertEqual(length(unreachable.end), 1, accuracy: 1e-9)
        let folded = ReplayTwoBoneSolver.solve3D(
            root: SIMD3(2, 3, 4),
            target: SIMD3(2, 3, 4),
            firstLength: 0.5,
            secondLength: 0.5,
            bendHint: .zero
        )
        XCTAssertTrue([folded.joint.x, folded.joint.y, folded.joint.z, folded.end.x, folded.end.y, folded.end.z]
            .allSatisfy(\.isFinite))
        XCTAssertEqual(folded.end, SIMD3(2, 3, 4))
        XCTAssertEqual(length(folded.joint - folded.end), 0.5, accuracy: 1e-9)

        let overflow = ReplayTwoBoneSolver.solve3D(
            root: SIMD3(Double.greatestFiniteMagnitude, 0, 0),
            target: SIMD3(-Double.greatestFiniteMagnitude, 0, 0),
            firstLength: 0.5,
            secondLength: 0.5,
            bendHint: .zero
        )
        XCTAssertTrue(
            [
                overflow.joint.x, overflow.joint.y, overflow.joint.z,
                overflow.end.x, overflow.end.y, overflow.end.z,
            ].allSatisfy(\.isFinite)
        )
    }

    func testTwoDimensionalSolveRetainsLengthsAndBendBranch() {
        let positive = ReplayTwoBoneSolver.solve2D(
            root: .zero,
            target: SIMD2(1, 0),
            firstLength: 0.75,
            secondLength: 0.75,
            bendDirection: 1
        )
        let negative = ReplayTwoBoneSolver.solve2D(
            root: .zero,
            target: SIMD2(1, 0),
            firstLength: 0.75,
            secondLength: 0.75,
            bendDirection: -1
        )
        XCTAssertEqual(length2D(positive.joint), 0.75, accuracy: 1e-9)
        XCTAssertEqual(length2D(positive.end - positive.joint), 0.75, accuracy: 1e-9)
        XCTAssertGreaterThan(positive.joint.y, 0)
        XCTAssertLessThan(negative.joint.y, 0)
    }

    func testRigidContactFallbackRetainsContactRadius() {
        let result = ReplayTwoBoneSolver.solveRigidContact3D(
            root: .zero,
            preferred: SIMD3(4, 0, 0),
            contactCenter: SIMD3(3, 0, 0),
            contactLength: 0.7,
            minimumReach: 0.2,
            maximumReach: 1
        )
        XCTAssertEqual(length(result.point - SIMD3(3, 0, 0)), 0.7, accuracy: 1e-9)
        XCTAssertTrue([result.point.x, result.point.y, result.point.z].allSatisfy(\.isFinite))
    }

    private func length(_ value: SIMD3<Double>) -> Double {
        sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
    }

    private func length2D(_ value: SIMD2<Double>) -> Double {
        sqrt(value.x * value.x + value.y * value.y)
    }
}
