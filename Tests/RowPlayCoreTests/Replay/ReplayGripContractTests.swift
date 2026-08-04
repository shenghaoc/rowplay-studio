import XCTest
@testable import RowPlayCore

final class ReplayGripContractTests: XCTestCase {
    func testSportClosureOptionsMatchPinnedEquipmentChannels() {
        let row = ReplayRowGripContract.gripClosureOptions(side: .left)
        XCTAssertEqual(row.surface.radius, 0.023)
        XCTAssertEqual(row.surface.thumbEndAxial, 0.04)
        XCTAssertEqual(row.thumbOppose, 0.3)
        XCTAssertFalse(row.wrapFingerStages)

        let ski = ReplaySkiGripContract.gripClosureOptions(side: .right)
        XCTAssertEqual(ski.surface.radius, 0.016)
        XCTAssertNil(ski.surface.thumbEndAxial)
        XCTAssertEqual(ski.thumbOppose, 1.75)
        XCTAssertFalse(ski.wrapFingerStages)

        let bike = ReplayBikeGripContract.gripClosureOptions(side: .right)
        XCTAssertEqual(bike.surface.radius, 0.018)
        XCTAssertNil(bike.surface.thumbEndAxial)
        XCTAssertEqual(bike.thumbOppose, 1.56)
        XCTAssertTrue(bike.wrapFingerStages)
    }

    func testGripChannelMirrorsWithoutChangingSeatDepth() {
        let left = ReplayGripGeometry.handChannelCentre(radius: 0.023, side: .left)
        let right = ReplayGripGeometry.handChannelCentre(radius: 0.023, side: .right)
        XCTAssertEqual(left.x, -right.x, accuracy: 1e-12)
        XCTAssertEqual(left.y, right.y, accuracy: 1e-12)
        XCTAssertEqual(left.z, right.z, accuracy: 1e-12)

        let leftLong = ReplayGripGeometry.handLongAxis(side: .left)
        let rightLong = ReplayGripGeometry.handLongAxis(side: .right)
        XCTAssertEqual(leftLong.x, -rightLong.x, accuracy: 1e-12)
        XCTAssertEqual(leftLong.y, rightLong.y, accuracy: 1e-12)
        XCTAssertEqual(leftLong.z, rightLong.z, accuracy: 1e-12)
    }

    func testQuaternionShortestArcAndInterpolationRemainNormalized() {
        let from = SIMD3<Double>(1, 0, 0)
        let to = SIMD3<Double>(0, 1, 0)
        let quarterTurn = ReplayQuaternion(from: from, to: to)
        let rotated = quarterTurn.act(from)
        XCTAssertEqual(rotated.x, 0, accuracy: 1e-12)
        XCTAssertEqual(rotated.y, 1, accuracy: 1e-12)

        let halfway = ReplayQuaternion.identity.interpolated(
            towards: ReplayQuaternion(axis: SIMD3(0, 0, 1), angle: .pi),
            fraction: 0.5
        )
        XCTAssertEqual(halfway.lengthSquared, 1, accuracy: 1e-12)
    }

    func testRowArmSolvePreservesGripAndSegmentLengths() {
        let shoulder = SIMD3<Double>(-0.25, 1.22, 0.08)
        let hand = SIMD3<Double>(-0.42, 0.96, 0.48)
        let upperArm = 0.35
        let forearm = 0.32

        let solution = ReplayRowGripContract.solveArm(
            shoulder: shoulder,
            hand: hand,
            upperArmLength: upperArm,
            forearmLength: forearm,
            side: .left
        )

        assertEqual(solution.hand, hand, accuracy: 1e-12)
        XCTAssertEqual(distance(shoulder, solution.elbow), upperArm, accuracy: 1e-10)
        XCTAssertEqual(distance(solution.elbow, solution.hand), forearm, accuracy: 1e-10)
        let outboard = ReplayRowGripContract.elbowOutboard(
            shoulder: shoulder,
            wrist: solution.hand,
            elbow: solution.elbow,
            side: .left
        )
        XCTAssertLessThanOrEqual(
            outboard,
            ReplayRowGripContract.elbowCorridor.maxOutboard + 1e-10
        )
        XCTAssertGreaterThanOrEqual(
            outboard,
            -ReplayRowGripContract.elbowCorridor.maxInboard - 1e-10
        )
    }

    func testRowArmContractMirrorsTypedSides() {
        let leftShoulder = SIMD3<Double>(-0.25, 1.22, 0.08)
        let leftHand = SIMD3<Double>(-0.42, 0.96, 0.48)
        let rightShoulder = mirrorX(leftShoulder)
        let rightHand = mirrorX(leftHand)
        let left = ReplayRowGripContract.solveArm(
            shoulder: leftShoulder,
            hand: leftHand,
            upperArmLength: 0.35,
            forearmLength: 0.32,
            side: .left
        )
        let right = ReplayRowGripContract.solveArm(
            shoulder: rightShoulder,
            hand: rightHand,
            upperArmLength: 0.35,
            forearmLength: 0.32,
            side: .right
        )

        assertEqual(right.elbow, mirrorX(left.elbow), accuracy: 1e-10)
        assertEqual(right.hand, mirrorX(left.hand), accuracy: 1e-12)
        assertEqual(right.plane, mirrorX(left.plane), accuracy: 1e-10)
        XCTAssertEqual(right.authority, left.authority, accuracy: 1e-12)
        XCTAssertEqual(
            ReplayRowGripContract.elbowOutboard(
                shoulder: rightShoulder,
                wrist: right.hand,
                elbow: right.elbow,
                side: .right
            ),
            ReplayRowGripContract.elbowOutboard(
                shoulder: leftShoulder,
                wrist: left.hand,
                elbow: left.elbow,
                side: .left
            ),
            accuracy: 1e-10
        )
    }

    func testRowElbowPlaneAuthorityAndDirectionStayBounded() {
        let plane = ReplayRowGripContract.elbowPlane
        XCTAssertEqual(ReplayRowGripContract.elbowPlaneAuthority(.nan), 0)
        XCTAssertEqual(
            ReplayRowGripContract.elbowPlaneAuthority(plane.authorityStart - 0.01),
            0
        )
        XCTAssertEqual(
            ReplayRowGripContract.elbowPlaneAuthority(plane.authorityFull + 0.01),
            1
        )

        for authority in [Double.nan, -1, 0, 0.5, 1, 2] {
            let left = ReplayRowGripContract.elbowPlaneDirection(
                side: .left,
                authority: authority
            )
            let right = ReplayRowGripContract.elbowPlaneDirection(
                side: .right,
                authority: authority
            )
            assertFinite(left)
            assertFinite(right)
            XCTAssertEqual(length(left), 1, accuracy: 1e-12)
            XCTAssertEqual(length(right), 1, accuracy: 1e-12)
            assertEqual(right, mirrorX(left), accuracy: 1e-12)
        }
    }

    func testRowArmSolveHandlesCoincidentAndNonfiniteInputsDeterministically() {
        let coincident = SIMD3<Double>(0.2, 1.0, -0.1)
        let folded = ReplayRowGripContract.solveArm(
            shoulder: coincident,
            hand: coincident,
            upperArmLength: 0.3,
            forearmLength: 0.3,
            side: .right
        )
        assertFinite(folded.elbow)
        assertEqual(folded.hand, coincident, accuracy: 1e-12)
        XCTAssertEqual(distance(coincident, folded.elbow), 0.3, accuracy: 1e-10)
        XCTAssertEqual(distance(folded.elbow, folded.hand), 0.3, accuracy: 1e-10)

        let invalid = ReplayRowGripContract.solveArm(
            shoulder: SIMD3(.nan, 1, 2),
            hand: SIMD3(.infinity, -.infinity, .nan),
            upperArmLength: .nan,
            forearmLength: -.infinity,
            side: .left
        )
        assertFinite(invalid.elbow)
        assertFinite(invalid.hand)
        assertFinite(invalid.plane)
        XCTAssertTrue(invalid.authority.isFinite)
        XCTAssertEqual(invalid.authority, 0)
    }

    private func mirrorX(_ point: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(-point.x, point.y, point.z)
    }

    private func distance(_ first: SIMD3<Double>, _ second: SIMD3<Double>) -> Double {
        length(first - second)
    }

    private func length(_ vector: SIMD3<Double>) -> Double {
        (vector.x * vector.x + vector.y * vector.y + vector.z * vector.z).squareRoot()
    }

    private func assertFinite(
        _ point: SIMD3<Double>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(point.x.isFinite, file: file, line: line)
        XCTAssertTrue(point.y.isFinite, file: file, line: line)
        XCTAssertTrue(point.z.isFinite, file: file, line: line)
    }

    private func assertEqual(
        _ actual: SIMD3<Double>,
        _ expected: SIMD3<Double>,
        accuracy: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.z, expected.z, accuracy: accuracy, file: file, line: line)
    }
}
