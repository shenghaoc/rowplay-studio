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
        XCTAssertEqual(pose.fieldOfViewDegrees, 40)
    }

    func testChaseFieldOfViewStaysWithinRequiredBounds() {
        for sport in Sport.allCases {
            let baseFieldOfView = ReplayCameraChaseRig.rig(for: sport).baseFieldOfView
            for speed in [-100.0, 0, 3, 6, 9, 100, .infinity, .nan] {
                let fov = ReplayCameraSolver.targetPose(
                    preset: .chase,
                    sport: sport,
                    participant: participant,
                    tangent: tangent,
                    speed: speed
                ).fieldOfViewDegrees
                XCTAssertGreaterThanOrEqual(fov, baseFieldOfView)
                XCTAssertLessThanOrEqual(
                    fov,
                    baseFieldOfView + ReplayCameraSolver.speedFieldOfViewGain
                )
            }
        }

        XCTAssertEqual(pose(for: .chase, speed: 3).fieldOfViewDegrees, 40)
        XCTAssertEqual(pose(for: .chase, speed: 9).fieldOfViewDegrees, 42)
    }

    func testNonChasePresetsUseStableFieldOfView() {
        for preset in [ReplayCameraPreset.side, .overhead, .orbit] {
            XCTAssertEqual(pose(for: preset, speed: 0).fieldOfViewDegrees, 46)
            XCTAssertEqual(pose(for: preset, speed: 100).fieldOfViewDegrees, 46)
        }
    }

    func testReducedMotionPreservesSportFieldOfViewAndDisablesSmoothing() {
        let expectedFieldOfViews: [Sport: Double] = [.rower: 40, .skierg: 42, .bike: 42]
        for sport in Sport.allCases {
            let target = ReplayCameraSolver.targetPose(
                preset: .chase,
                sport: sport,
                participant: participant,
                tangent: tangent,
                speed: 100,
                reduceMotion: true
            )
            let result = ReplayCameraSolver.smoothedPose(
                current: ReplayCameraPose.fallback,
                target: target,
                dt: 1.0 / 60.0,
                reduceMotion: true
            )

            XCTAssertEqual(result, target)
            XCTAssertEqual(result.fieldOfViewDegrees, expectedFieldOfViews[sport])
        }
    }

    func testChaseRigUsesSportSpecificFraming() {
        let poses = Sport.allCases.map { sport in
            ReplayCameraSolver.targetPose(
                preset: .chase,
                sport: sport,
                participant: participant,
                tangent: tangent,
                speed: 3
            )
        }
        XCTAssertEqual(poses.map(\.fieldOfViewDegrees), [40, 42, 42])
        XCTAssertEqual(Set(poses.map(\.positionY)).count, 3)
        XCTAssertEqual(Set(poses.map(\.positionZ)).count, 3)
    }

    func testRivalFramingTargetsMidpointAndPullsBackMonotonicallyForSeparation() {
        let solo = ReplayCameraSolver.targetPose(
            preset: .chase,
            sport: .rower,
            participant: participant,
            tangent: tangent,
            speed: 6
        )
        let nearRival = ReplayCameraSolver.targetPose(
            preset: .chase,
            sport: .rower,
            participant: participant,
            tangent: tangent,
            speed: 6,
            rival: (x: 12, y: 0, z: 32)
        )
        let farRival = ReplayCameraSolver.targetPose(
            preset: .chase,
            sport: .rower,
            participant: participant,
            tangent: tangent,
            speed: 6,
            rival: (x: 12, y: 0, z: 50)
        )
        let rig = ReplayCameraChaseRig.rig(for: .rower)
        XCTAssertEqual(farRival.targetX, (12 + 12) / 2 + rig.ahead, accuracy: 0.0001)
        XCTAssertEqual(farRival.targetZ, 40, accuracy: 0.0001)
        XCTAssertGreaterThan(cameraDistance(nearRival), cameraDistance(solo))
        XCTAssertGreaterThan(cameraDistance(farRival), cameraDistance(nearRival))
    }

    func testEqualDistanceCourseRivalUsesMidpointAndWidensAgainstSolo() {
        let layout = ReplayCourseLayout.standard
        let distance = 100.0
        let participant = layout.position(at: distance)
        let rival = layout.ghostPosition(at: distance)
        let tangent = layout.tangent(at: distance)
        let rig = ReplayCameraChaseRig.rig(for: .rower)
        let solo = ReplayCameraSolver.targetPose(
            preset: .chase,
            sport: .rower,
            participant: participant,
            tangent: tangent,
            speed: 6
        )
        let paired = ReplayCameraSolver.targetPose(
            preset: .chase,
            sport: .rower,
            participant: participant,
            tangent: tangent,
            speed: 6,
            rival: rival
        )

        XCTAssertTrue(paired.isFinite)
        XCTAssertGreaterThan(cameraDistance(paired), cameraDistance(solo))
        XCTAssertEqual(
            paired.targetX,
            participant.x / 2 + rival.x / 2 + tangent.x * rig.ahead,
            accuracy: 1e-10
        )
        XCTAssertEqual(
            paired.targetZ,
            participant.z / 2 + rival.z / 2 + tangent.z * rig.ahead,
            accuracy: 1e-10
        )
        assertPaddedHorizontalFrustumContains(
            participant,
            rival,
            pose: paired,
            sport: .rower,
            aspect: ReplayCameraSolver.defaultViewportAspect
        )
    }

    func testGappedCourseRivalHasPositiveDepthAndPaddedFrustumInclusion() {
        assertCourseRivalFit(liveDistance: 246.5, rivalDistance: 211)
    }

    func testOppositeCourseRivalHasPositiveDepthAndPaddedFrustumInclusion() {
        assertCourseRivalFit(liveDistance: 37, rivalDistance: 237)
    }

    func testLongitudinalGapWithZeroRightProjectionStillFitsBothParticipants() {
        let longitudinalRival: ReplayPosition = (x: -28, y: 0, z: 30)
        let pose = ReplayCameraSolver.targetPose(
            preset: .chase,
            sport: .rower,
            participant: participant,
            tangent: tangent,
            speed: 6,
            rival: longitudinalRival
        )

        XCTAssertEqual(participant.z - longitudinalRival.z, 0)
        assertPaddedHorizontalFrustumContains(
            participant,
            longitudinalRival,
            pose: pose,
            sport: .rower,
            aspect: ReplayCameraSolver.defaultViewportAspect
        )
    }

    func testPortraitViewportPullsBackMoreThanUltrawideForSameRival() {
        let rival: ReplayPosition = (x: 12, y: 0, z: 50)
        let portrait = ReplayCameraSolver.targetPose(
            preset: .chase,
            sport: .rower,
            participant: participant,
            tangent: tangent,
            speed: 6,
            rival: rival,
            aspect: 0.65
        )
        let ultrawide = ReplayCameraSolver.targetPose(
            preset: .chase,
            sport: .rower,
            participant: participant,
            tangent: tangent,
            speed: 6,
            rival: rival,
            aspect: 2.4
        )

        XCTAssertGreaterThanOrEqual(cameraDistance(portrait), cameraDistance(ultrawide))
        assertPaddedHorizontalFrustumContains(
            participant,
            rival,
            pose: portrait,
            sport: .rower,
            aspect: 0.65
        )
        assertPaddedHorizontalFrustumContains(
            participant,
            rival,
            pose: ultrawide,
            sport: .rower,
            aspect: 2.4
        )
    }

    func testViewportAspectSanitizerHandlesLayoutAndDirectInputEdges() {
        XCTAssertEqual(ReplayCameraSolver.viewportAspect(width: 1600, height: 1000), 1.6)
        XCTAssertEqual(ReplayCameraSolver.viewportAspect(width: 900, height: 1200), 0.75)
        for dimensions in [
            (Double.nan, 600.0),
            (600.0, Double.infinity),
            (0.0, 600.0),
            (600.0, -1.0),
            (0.5, 600.0),
            (600.0, 0.5),
        ] {
            XCTAssertEqual(
                ReplayCameraSolver.viewportAspect(width: dimensions.0, height: dimensions.1),
                ReplayCameraSolver.defaultViewportAspect
            )
        }
        for aspect in [Double.nan, .infinity, 0, -1, 0.2] {
            XCTAssertEqual(
                ReplayCameraSolver.sanitizedViewportAspect(aspect),
                ReplayCameraSolver.defaultViewportAspect
            )
        }
        let defaultPose = ReplayCameraSolver.targetPose(
            preset: .chase,
            participant: participant,
            tangent: tangent,
            speed: 6,
            rival: (x: 12, y: 0, z: 50)
        )
        let invalidAspectPose = ReplayCameraSolver.targetPose(
            preset: .chase,
            participant: participant,
            tangent: tangent,
            speed: 6,
            rival: (x: 12, y: 0, z: 50),
            aspect: .nan
        )
        XCTAssertEqual(invalidAspectPose, defaultPose)
    }

    func testViewportAspectOnlyAffectsChaseWhenRivalIsPresent() {
        let rival: ReplayPosition = (x: 12, y: 0, z: 50)
        let portraitSolo = ReplayCameraSolver.targetPose(
            preset: .chase,
            participant: participant,
            tangent: tangent,
            speed: 6,
            aspect: 0.65
        )
        let wideSolo = ReplayCameraSolver.targetPose(
            preset: .chase,
            participant: participant,
            tangent: tangent,
            speed: 6,
            aspect: 2.4
        )
        XCTAssertEqual(portraitSolo, wideSolo)

        for preset in [ReplayCameraPreset.side, .overhead, .orbit] {
            let portrait = ReplayCameraSolver.targetPose(
                preset: preset,
                participant: participant,
                tangent: tangent,
                speed: 6,
                rival: rival,
                aspect: 0.65
            )
            let wide = ReplayCameraSolver.targetPose(
                preset: preset,
                participant: participant,
                tangent: tangent,
                speed: 6,
                rival: rival,
                aspect: 2.4
            )
            XCTAssertEqual(portrait, wide)
        }
    }

    func testReducedMotionUsesStaticSportFieldOfView() {
        let expectedFieldOfViews: [Sport: Double] = [.rower: 40, .skierg: 42, .bike: 42]
        for sport in Sport.allCases {
            let slow = ReplayCameraSolver.targetPose(
                preset: .chase, sport: sport, participant: participant,
                tangent: tangent, speed: 0, reduceMotion: true
            )
            let fast = ReplayCameraSolver.targetPose(
                preset: .chase, sport: sport, participant: participant,
                tangent: tangent, speed: 100, reduceMotion: true
            )
            XCTAssertEqual(slow.fieldOfViewDegrees, fast.fieldOfViewDegrees)
            XCTAssertEqual(slow.fieldOfViewDegrees, expectedFieldOfViews[sport])
            XCTAssertEqual(slow.positionX, fast.positionX)
            XCTAssertEqual(slow.positionZ, fast.positionZ)
        }
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

    private func cameraDistance(_ pose: ReplayCameraPose) -> Double {
        hypot(pose.positionX - pose.targetX, pose.positionZ - pose.targetZ)
    }

    private func assertCourseRivalFit(
        liveDistance: Double,
        rivalDistance: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let layout = ReplayCourseLayout.standard
        let participant = layout.position(at: liveDistance)
        let rival = layout.ghostPosition(at: rivalDistance)
        let tangent = layout.tangent(at: liveDistance)
        var distances: [Double] = []

        for aspect in [0.65, ReplayCameraSolver.defaultViewportAspect, 2.4] {
            let pose = ReplayCameraSolver.targetPose(
                preset: .chase,
                sport: .rower,
                participant: participant,
                tangent: tangent,
                speed: 6,
                rival: rival,
                aspect: aspect
            )
            XCTAssertTrue(pose.isFinite, file: file, line: line)
            assertPaddedHorizontalFrustumContains(
                participant,
                rival,
                pose: pose,
                sport: .rower,
                aspect: aspect,
                file: file,
                line: line
            )
            distances.append(cameraDistance(pose))
        }

        XCTAssertGreaterThanOrEqual(distances[0], distances[2], file: file, line: line)
    }

    private func assertPaddedHorizontalFrustumContains(
        _ participant: ReplayPosition,
        _ rival: ReplayPosition,
        pose: ReplayCameraPose,
        sport: Sport,
        aspect: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let viewX = pose.targetX - pose.positionX
        let viewZ = pose.targetZ - pose.positionZ
        let viewLength = hypot(viewX, viewZ)
        XCTAssertGreaterThan(viewLength, 0, file: file, line: line)
        let forwardX = viewX / viewLength
        let forwardZ = viewZ / viewLength
        let cameraRightX = -forwardZ
        let cameraRightZ = forwardX
        let horizontalHalfAngle = atan(
            tan(pose.fieldOfViewDegrees * .pi / 360)
                * ReplayCameraSolver.sanitizedViewportAspect(aspect)
        ) * ReplayCameraSolver.rivalFrustumFillFraction

        for point in [participant, rival] {
            let offsetX = point.x - pose.positionX
            let offsetZ = point.z - pose.positionZ
            let depth = offsetX * forwardX + offsetZ * forwardZ
            XCTAssertGreaterThan(
                depth,
                ReplayCameraSolver.minimumRivalFrustumDepth,
                file: file,
                line: line
            )
            let lateral = abs(offsetX * cameraRightX + offsetZ * cameraRightZ)
            let paddedAngle = atan2(
                lateral + ReplayCameraSolver.rivalHorizontalPadding(for: sport),
                depth
            )
            XCTAssertLessThanOrEqual(
                paddedAngle,
                horizontalHalfAngle + 1e-12,
                file: file,
                line: line
            )
        }
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
