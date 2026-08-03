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
}
