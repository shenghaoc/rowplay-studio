import XCTest
@testable import RowPlayCore

final class ReplayPlanarKinematicsTests: XCTestCase {
    func testRigidContactPreservesPoleLengthAndReachWhenFeasible() {
        let root = SIMD2<Double>(0, 0)
        let center = SIMD2<Double>(4, 0)
        let solution = ReplayPlanarRigidContactSolver.solve(
            root: root,
            preferred: SIMD2(4, 3),
            contactCenter: center,
            contactLength: 3,
            minimumReach: 2,
            maximumReach: 5
        )

        XCTAssertTrue(solution.isFeasible)
        XCTAssertEqual(length(solution.point - center), 3, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(length(solution.point - root), 2 - 1e-9)
        XCTAssertLessThanOrEqual(length(solution.point - root), 5 + 1e-9)
    }

    func testRigidContactInfeasibleFallbackStaysFiniteAndRigid() {
        let center = SIMD2<Double>(20, 0)
        let solution = ReplayPlanarRigidContactSolver.solve(
            root: .zero,
            preferred: SIMD2(.nan, .infinity),
            contactCenter: center,
            contactLength: 2,
            minimumReach: 0.5,
            maximumReach: 1
        )

        XCTAssertFalse(solution.isFeasible)
        XCTAssertEqual(length(solution.point - center), 2, accuracy: 1e-9)
        XCTAssertTrue([solution.x, solution.y].allSatisfy(\.isFinite))
    }

    func testRowerElbowChoosesRearwardBranchAndPreservesSegments() {
        let shoulder = SIMD2<Double>(0, 0)
        let hand = SIMD2<Double>(4, 2)
        let solution = ReplayPlanarRowSolver.solveRearwardElbow(
            shoulder: shoulder,
            hand: hand,
            upperArmLength: 3,
            forearmLength: 3
        )

        XCTAssertEqual(length(solution.joint - shoulder), 3, accuracy: 1e-9)
        XCTAssertEqual(length(solution.end - solution.joint), 3, accuracy: 1e-9)
        XCTAssertEqual(solution.end, hand)
        let positive = ReplayTwoBoneSolver.solve2D(
            root: shoulder,
            target: hand,
            firstLength: 3,
            secondLength: 3,
            bendDirection: 1
        )
        let negative = ReplayTwoBoneSolver.solve2D(
            root: shoulder,
            target: hand,
            firstLength: 3,
            secondLength: 3,
            bendDirection: -1
        )
        XCTAssertEqual(
            solution.joint.x,
            min(positive.joint.x, negative.joint.x),
            accuracy: 1e-12
        )
        XCTAssertLessThan(solution.joint.x, max(positive.joint.x, negative.joint.x))
    }

    func testRigidOarIsCollinearAndKeepsAuthoredLengths() {
        let lock = SIMD2<Double>(3, 5)
        let oar = ReplayPlanarRowSolver.solveRigidOar(
            lock: lock,
            angle: 0.73,
            inboardLength: 7.1,
            outboardLength: 13.8,
            bladeLength: 4
        )

        XCTAssertEqual(length(oar.handle - lock), 7.1, accuracy: 1e-9)
        XCTAssertEqual(length(oar.bladeRoot - lock), 13.8, accuracy: 1e-9)
        XCTAssertEqual(length(oar.bladeTip - oar.bladeRoot), 4, accuracy: 1e-9)
        let inboard = lock - oar.handle
        let outboard = oar.bladeRoot - lock
        XCTAssertEqual(cross(inboard, outboard), 0, accuracy: 1e-9)
    }

    func testOarAngleDegenerateInputFallsBackWithoutNaN() {
        XCTAssertEqual(
            ReplayPlanarRowSolver.solveOarAngle(
                shoulder: .zero,
                lock: .zero,
                inboardLength: 0,
                requestedReach: .nan,
                preferredAngle: 1.25
            ),
            1.25,
            accuracy: 1e-12
        )
        XCTAssertTrue(
            ReplayPlanarRowSolver.interpolateAngle(
                from: .nan,
                to: .infinity,
                amount: .nan
            ).isFinite
        )
    }

    private func length(_ value: SIMD2<Double>) -> Double {
        sqrt(value.x * value.x + value.y * value.y)
    }

    private func cross(_ first: SIMD2<Double>, _ second: SIMD2<Double>) -> Double {
        first.x * second.y - first.y * second.x
    }
}
