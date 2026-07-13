import XCTest
@testable import RowPlayCore

final class ReplayCameraTests: XCTestCase {
    private let participant: ReplayPosition = (x: 12, y: 0, z: 30)
    private let tangent: ReplayPosition = (x: 1, y: 0, z: 0)

    func testEveryPresetProducesFinitePose() {
        for preset in ReplayCameraPreset.allCases {
            let pose = ReplayCameraSolver.targetPose(
                preset: preset,
                participant: participant,
                tangent: tangent,
                speed: 6
            )
            XCTAssertTrue(pose.isFinite, "Expected finite pose for \(preset)")
        }
    }

    func testChaseSideAndOverheadPositionsAreDistinct() {
        let chase = pose(for: .chase)
        let side = pose(for: .side)
        let overhead = pose(for: .overhead)

        XCTAssertNotEqual(chase.positionX, side.positionX)
        XCTAssertNotEqual(chase.positionY, overhead.positionY)
        XCTAssertNotEqual(side.positionZ, overhead.positionZ)
    }

    func testOrbitClampsYawPitchAndDistance() {
        let high = ReplayCameraOrbit(yaw: .infinity, pitch: .infinity, distance: .infinity)
        XCTAssertEqual(high.yaw, 0)
        XCTAssertEqual(high.pitch, ReplayCameraOrbit.defaultPitch)
        XCTAssertEqual(high.distance, ReplayCameraOrbit.defaultDistance)

        let clamped = ReplayCameraOrbit(yaw: Double.pi * 5, pitch: Double.pi, distance: 100)
        XCTAssertGreaterThanOrEqual(clamped.yaw, -Double.pi)
        XCTAssertLessThanOrEqual(clamped.yaw, Double.pi)
        XCTAssertEqual(clamped.pitch, ReplayCameraOrbit.maximumPitch)
        XCTAssertEqual(clamped.distance, ReplayCameraOrbit.maximumDistance)

        let low = ReplayCameraOrbit(pitch: -Double.pi, distance: -10)
        XCTAssertEqual(low.pitch, ReplayCameraOrbit.minimumPitch)
        XCTAssertEqual(low.distance, ReplayCameraOrbit.minimumDistance)
    }

    func testOrbitAdjustmentsRemainClamped() {
        var orbit = ReplayCameraOrbit()
        orbit.rotate(yawDelta: Double.pi * 8, pitchDelta: Double.pi)
        orbit.zoom(magnification: 0.001)

        XCTAssertGreaterThanOrEqual(orbit.yaw, -Double.pi)
        XCTAssertLessThanOrEqual(orbit.yaw, Double.pi)
        XCTAssertEqual(orbit.pitch, ReplayCameraOrbit.maximumPitch)
        XCTAssertEqual(orbit.distance, ReplayCameraOrbit.maximumDistance)

        orbit.reset()
        XCTAssertEqual(orbit, ReplayCameraOrbit())
    }

    func testNonFiniteInputsFallBackToFinitePose() {
        let pose = ReplayCameraSolver.targetPose(
            preset: .chase,
            participant: (x: .nan, y: .infinity, z: -.infinity),
            tangent: (x: .nan, y: 0, z: .infinity),
            speed: .nan,
            orbit: ReplayCameraOrbit(yaw: .nan, pitch: .nan, distance: .nan)
        )

        XCTAssertTrue(pose.isFinite)
        XCTAssertEqual(pose.fieldOfViewDegrees, 46)
    }

    func testChaseFieldOfViewStaysWithinRequiredBounds() {
        for speed in [-100.0, 0, 3, 6, 9, 100, .infinity, .nan] {
            let fov = ReplayCameraSolver.targetPose(
                preset: .chase,
                participant: participant,
                tangent: tangent,
                speed: speed
            ).fieldOfViewDegrees
            XCTAssertGreaterThanOrEqual(fov, 46)
            XCTAssertLessThanOrEqual(fov, 51)
        }

        XCTAssertEqual(pose(for: .chase, speed: 3).fieldOfViewDegrees, 46)
        XCTAssertEqual(pose(for: .chase, speed: 9).fieldOfViewDegrees, 51)
    }

    func testNonChasePresetsUseStableFieldOfView() {
        for preset in [ReplayCameraPreset.side, .overhead, .orbit] {
            XCTAssertEqual(pose(for: preset, speed: 0).fieldOfViewDegrees, 46)
            XCTAssertEqual(pose(for: preset, speed: 100).fieldOfViewDegrees, 46)
        }
    }

    func testReducedMotionFixesFieldOfViewAndDisablesSmoothing() {
        let target = pose(for: .chase, speed: 100)
        let current = ReplayCameraPose.fallback
        let result = ReplayCameraSolver.smoothedPose(
            current: current,
            target: target,
            dt: 1.0 / 60.0,
            reduceMotion: true
        )

        XCTAssertEqual(result.positionX, target.positionX)
        XCTAssertEqual(result.positionY, target.positionY)
        XCTAssertEqual(result.positionZ, target.positionZ)
        XCTAssertEqual(result.targetX, target.targetX)
        XCTAssertEqual(result.fieldOfViewDegrees, 46)
    }

    func testDampingIsEquivalentAcrossFrameRates() {
        let start = ReplayCameraPose.fallback
        let target = pose(for: .chase, speed: 9)
        let at30 = integrate(from: start, toward: target, frames: 30, dt: 1.0 / 30.0)
        let at120 = integrate(from: start, toward: target, frames: 120, dt: 1.0 / 120.0)

        XCTAssertEqual(at30.positionX, at120.positionX, accuracy: 1e-10)
        XCTAssertEqual(at30.positionY, at120.positionY, accuracy: 1e-10)
        XCTAssertEqual(at30.positionZ, at120.positionZ, accuracy: 1e-10)
        XCTAssertEqual(at30.targetX, at120.targetX, accuracy: 1e-10)
        XCTAssertEqual(at30.fieldOfViewDegrees, at120.fieldOfViewDegrees, accuracy: 1e-10)
    }

    func testOrbitYawChangesCameraPositionAroundParticipant() {
        let first = ReplayCameraSolver.targetPose(
            preset: .orbit,
            participant: participant,
            tangent: tangent,
            speed: 0,
            orbit: ReplayCameraOrbit(yaw: 0)
        )
        let second = ReplayCameraSolver.targetPose(
            preset: .orbit,
            participant: participant,
            tangent: tangent,
            speed: 0,
            orbit: ReplayCameraOrbit(yaw: Double.pi / 2)
        )

        XCTAssertNotEqual(first.positionX, second.positionX)
        XCTAssertNotEqual(first.positionZ, second.positionZ)
        XCTAssertEqual(first.targetX, second.targetX)
        XCTAssertEqual(first.targetZ, second.targetZ)
    }

    func testNonFiniteDeltaTimeDoesNotProduceNonFinitePose() {
        let result = ReplayCameraSolver.smoothedPose(
            current: ReplayCameraPose.fallback,
            target: pose(for: .side),
            dt: .nan
        )
        XCTAssertTrue(result.isFinite)
        XCTAssertEqual(result, ReplayCameraPose.fallback)
    }

    func testPoseCreatedFromInvalidCurrentInputSnapsFullyToTarget() {
        let invalidCurrent = ReplayCameraPose(
            positionX: .nan,
            positionY: 3,
            positionZ: -4,
            targetX: 1,
            targetY: 2,
            targetZ: 3,
            fieldOfViewDegrees: 48
        )
        let target = pose(for: .side)
        XCTAssertTrue(invalidCurrent.isFinite)
        XCTAssertTrue(invalidCurrent.wasSanitized)
        XCTAssertEqual(invalidCurrent, invalidCurrent)

        let result = ReplayCameraSolver.smoothedPose(
            current: invalidCurrent,
            target: target,
            dt: 1.0 / 120.0
        )

        XCTAssertEqual(result, target)
    }

    func testDampingOppositeFiniteExtremesDoesNotOverflow() {
        let current = ReplayCameraPose(
            positionX: -Double.greatestFiniteMagnitude,
            positionY: 0,
            positionZ: 0,
            targetX: 0,
            targetY: 0,
            targetZ: 0,
            fieldOfViewDegrees: 46
        )
        let target = ReplayCameraPose(
            positionX: Double.greatestFiniteMagnitude,
            positionY: 1,
            positionZ: 1,
            targetX: 1,
            targetY: 1,
            targetZ: 1,
            fieldOfViewDegrees: 51
        )

        let result = ReplayCameraSolver.smoothedPose(current: current, target: target, dt: 0.05)

        XCTAssertTrue(result.isFinite)
    }

    func testInvalidTargetFallsBackBeforeSmoothing() {
        let invalidTarget = ReplayCameraPose(
            positionX: .infinity,
            positionY: 1,
            positionZ: 2,
            targetX: 3,
            targetY: 4,
            targetZ: 5,
            fieldOfViewDegrees: 49
        )

        let result = ReplayCameraSolver.smoothedPose(
            current: ReplayCameraPose.fallback,
            target: invalidTarget,
            dt: 1
        )

        XCTAssertEqual(result, ReplayCameraPose.fallback)

        let invalidCurrent = ReplayCameraPose(
            positionX: 0,
            positionY: .nan,
            positionZ: 0,
            targetX: 0,
            targetY: 0,
            targetZ: 0,
            fieldOfViewDegrees: 46
        )
        XCTAssertEqual(
            ReplayCameraSolver.smoothedPose(
                current: invalidCurrent,
                target: invalidTarget,
                dt: 1
            ),
            ReplayCameraPose.fallback
        )
    }

    private func pose(for preset: ReplayCameraPreset, speed: Double = 6) -> ReplayCameraPose {
        ReplayCameraSolver.targetPose(
            preset: preset,
            participant: participant,
            tangent: tangent,
            speed: speed
        )
    }

    private func integrate(
        from start: ReplayCameraPose,
        toward target: ReplayCameraPose,
        frames: Int,
        dt: Double
    ) -> ReplayCameraPose {
        var pose = start
        for _ in 0..<frames {
            pose = ReplayCameraSolver.smoothedPose(current: pose, target: target, dt: dt)
        }
        return pose
    }
}
