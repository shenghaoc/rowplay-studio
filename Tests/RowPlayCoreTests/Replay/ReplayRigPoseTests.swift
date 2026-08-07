import XCTest
@testable import RowPlayCore

final class ReplayRigPoseTests: XCTestCase {
    private let tau = Double.pi * 2

    // MARK: - RowErg Tests

    func testRowerCatchPose() {
        // At catch: drive = cos(0) = 1, recovery = 0
        let pose = makeStrokePose(warpedPhase: 0, amplitude: 1.0)
        let result = ReplayRigPoseSolver.solve(
            sport: .rower, strokePose: pose, distance: 0, reduceMotion: false
        )
        guard case .rower(let rower) = result else {
            XCTFail("Expected rower pose"); return
        }
        // Seat should be shifted toward stern (negative Z)
        XCTAssertLessThan(rower.seatZ, -0.1, "Seat should move toward stern at catch")
        // Torso should lean forward
        XCTAssertLessThan(rower.joints.torsoLean, 0, "Torso should lean forward at catch")
        // Legs should be compressed
        XCTAssertGreaterThan(rower.joints.kneeFlexL, 0, "Knees should be flexed at catch")
        XCTAssertGreaterThan(rower.joints.hipFlexL, 0, "Hips should be flexed at catch")
    }

    func testRowerFinishPose() {
        // The canonical graph reaches finish after its row drive window.
        let pose = makeStrokePose(phase: 0.38 * tau, amplitude: 1.0)
        let result = ReplayRigPoseSolver.solve(
            sport: .rower, strokePose: pose, distance: 0, reduceMotion: false
        )
        guard case .rower(let rower) = result else {
            XCTFail("Expected rower pose"); return
        }
        // Seat should be shifted toward bow (less negative Z)
        XCTAssertGreaterThan(rower.seatZ, -0.3, "Seat should move toward bow at finish")
        // Legs should be extended
        XCTAssertLessThan(rower.joints.kneeFlexL, 0.1, "Knees should be near straight at finish")
    }

    func testRowerMidDrivePose() {
        let pose = makeStrokePose(phase: 0.15 * tau, amplitude: 1.0)
        let result = ReplayRigPoseSolver.solve(
            sport: .rower, strokePose: pose, distance: 0, reduceMotion: false
        )
        guard case .rower(let rower) = result else {
            XCTFail("Expected rower pose"); return
        }
        // All values should be finite
        XCTAssertTrue(isFinite(rower.seatZ))
        XCTAssertTrue(isFinite(rower.handleY))
        XCTAssertTrue(isFinite(rower.handleZ))
        XCTAssertTrue(isFinite(rower.oarSweep))
    }

    func testRowerRecoveryPose() {
        let pose = makeStrokePose(phase: 0.60 * tau, amplitude: 1.0)
        let result = ReplayRigPoseSolver.solve(
            sport: .rower, strokePose: pose, distance: 0, reduceMotion: false
        )
        guard case .rower(let rower) = result else {
            XCTFail("Expected rower pose"); return
        }
        // Recovery: oar feather should be positive (blades lifted)
        XCTAssertGreaterThan(rower.oarFeather, -0.1, "Oars should be feathered during recovery")
    }

    // MARK: - SkiErg Tests

    func testSkiErgTallRecoveryPose() {
        // Pole-off completes at 29% of the canonical SkiErg cycle.
        let pose = makeStrokePose(phase: 0.30 * tau, amplitude: 1.0)
        let result = ReplayRigPoseSolver.solve(
            sport: .skierg, strokePose: pose, distance: 0, reduceMotion: false
        )
        guard case .skierg(let ski) = result else {
            XCTFail("Expected skierg pose"); return
        }
        // Hip compression should be positive
        XCTAssertGreaterThan(ski.hipCompression, 0, "Should have hip compression during pull")
        // Torso should lean forward
        XCTAssertGreaterThan(ski.joints.torsoLean, 0.2, "Torso should lean forward during pull")
    }

    func testSkiErgCompressedPullPose() {
        // Compressed pull: swing = cos(0) = 1, crunch = max(0, 0) = 0
        let pose = makeStrokePose(warpedPhase: 0, amplitude: 1.0)
        let result = ReplayRigPoseSolver.solve(
            sport: .skierg, strokePose: pose, distance: 0, reduceMotion: false
        )
        guard case .skierg(let ski) = result else {
            XCTFail("Expected skierg pose"); return
        }
        // Should be tall (less compression)
        XCTAssertLessThan(ski.hipCompression, 0.1, "Should be tall at plant")
        // Hands should be high on the reach at the plant
        XCTAssertGreaterThan(ski.preferredHandY, 0.9, "Hands should be high at plant")
    }

    func testSkiErgPlantIsDeterministicAndCourseFixedWithinStroke() {
        let firstCycle = 0.05
        let secondCycle = 0.18
        let firstDistance = firstCycle * 11
        let secondDistance = secondCycle * 11
        let firstPose = makeStrokePose(cycleFrac: firstCycle)
        let secondPose = makeStrokePose(cycleFrac: secondCycle)

        guard case .skierg(let first) = ReplayRigPoseSolver.solve(
            sport: .skierg,
            strokePose: firstPose,
            distance: firstDistance,
            reduceMotion: false
        ), case .skierg(let second) = ReplayRigPoseSolver.solve(
            sport: .skierg,
            strokePose: secondPose,
            distance: secondDistance,
            reduceMotion: false
        ) else {
            return XCTFail("Expected SkiErg poses")
        }

        XCTAssertGreaterThan(first.poleContact, 0)
        XCTAssertGreaterThan(second.poleContact, 0)
        XCTAssertEqual(
            firstDistance + first.plantBasketZ,
            secondDistance + second.plantBasketZ,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            ReplayRigPoseSolver.solve(
                sport: .skierg,
                strokePose: firstPose,
                distance: firstDistance,
                reduceMotion: false
            ),
            .skierg(first),
            "Seeking the same pose must reconstruct the same plant"
        )
    }

    /// The preferred hand path is the web renderer's shoulder arc, so the
    /// authored hand must stay inside the arm's reach envelope at every phase
    /// of the cycle — otherwise the rigid pole solve drags it off the grip.
    func testSkiErgPreferredHandStaysWithinArmReachAcrossCycle() {
        let proportions = ReplaySkiGripContract.athleteProportions
        let maxReach = proportions.upperArmLength + proportions.forearmLength - 0.02
        for step in 0..<128 {
            let cycleFrac = Double(step) / 128
            guard case .skierg(let pose) = ReplayRigPoseSolver.solve(
                sport: .skierg,
                strokePose: makeStrokePose(cycleFrac: cycleFrac),
                distance: cycleFrac * 8,
                reduceMotion: false
            ) else {
                return XCTFail("Expected SkiErg pose at \(cycleFrac)")
            }
            XCTAssertTrue(pose.preferredHandY.isFinite && pose.preferredHandZ.isFinite)
            XCTAssertTrue(pose.shoulderY.isFinite && pose.shoulderZ.isFinite)
            let dy = pose.preferredHandY - pose.shoulderY
            let dz = pose.preferredHandZ - pose.shoulderZ
            // Lateral span between shoulder and preferred hand is the web's
            // fixed 0.05 m margin beyond the shoulder half width.
            let span = (0.05 * 0.05 + dy * dy + dz * dz).squareRoot()
            XCTAssertLessThanOrEqual(
                span,
                maxReach + 1e-6,
                "Preferred hand outside arm reach at cycleFrac \(cycleFrac)"
            )
        }
    }

    /// Reduced motion must keep the calm carry the rig rendered before the
    /// preferred-hand path existed, so the defaults cannot drift.
    func testSkiErgReducedMotionKeepsAuthoredCarryPosition() {
        guard case .skierg(let pose) = ReplayRigPoseSolver.solve(
            sport: .skierg,
            strokePose: makeStrokePose(cycleFrac: 0.4),
            distance: 3,
            reduceMotion: true
        ) else {
            return XCTFail("Expected SkiErg pose")
        }
        // Matches the legacy handleY/handleZ remap the rig applied for the
        // reduced-motion pose (1.2, 0.2) before the web-parity port.
        XCTAssertEqual(pose.preferredHandY, 0.663, accuracy: 0.01)
        XCTAssertEqual(pose.preferredHandZ, 0.094, accuracy: 0.01)
    }

    func testSkiErgPreplantTargetsTheNextCatchWithoutHistory() {
        let cycle = 0.97
        let distance = cycle * 11
        let pose = makeStrokePose(cycleFrac: cycle)
        guard case .skierg(let ski) = ReplayRigPoseSolver.solve(
            sport: .skierg,
            strokePose: pose,
            distance: distance,
            reduceMotion: false
        ) else {
            return XCTFail("Expected SkiErg pose")
        }

        XCTAssertGreaterThan(ski.poleContact, 0)
        XCTAssertEqual(
            distance + ski.plantBasketZ,
            11 + ReplaySkiGripContract.athleteProportions.polePlantForwardOffset,
            accuracy: 1e-12
        )
    }

    // MARK: - BikeErg Tests

    func testBikeErgCrankPositions() {
        // Test at 0°, 90°, 180°, 270°
        for angle in stride(from: 0, to: tau, by: .pi / 2) {
            let pose = makeStrokePose(phase: angle, amplitude: 1.0)
            let result = ReplayRigPoseSolver.solve(
                sport: .bike, strokePose: pose, distance: angle * 5, reduceMotion: false
            )
            guard case .bike(let bike) = result else {
                XCTFail("Expected bike pose at angle \(angle)"); return
            }
            // Crank angle should match input phase
            XCTAssertEqual(bike.crankAngle, angle, accuracy: 0.001,
                "Crank angle should match phase at \(angle)")
            // Merged V4 advances wheels from covered distance, not crank phase.
            XCTAssertEqual(
                bike.wheelAngle,
                (angle * 5) / ReplayBikeGripContract.axleY,
                accuracy: 0.001,
                "Wheel angle should follow distance at \(angle)")
            // All values should be finite
            XCTAssertTrue(isFinite(bike.crankAngle))
            XCTAssertTrue(isFinite(bike.wheelAngle))
            XCTAssertTrue(isFinite(bike.pedalPosL.y))
            XCTAssertTrue(isFinite(bike.pedalPosL.z))
            XCTAssertTrue(isFinite(bike.pedalPosR.y))
            XCTAssertTrue(isFinite(bike.pedalPosR.z))
            XCTAssertEqual(
                hypot(bike.pedalPosL.y, bike.pedalPosL.z),
                ReplayBikeGripContract.crankRadius,
                accuracy: 0.001
            )
            XCTAssertEqual(
                hypot(bike.pedalPosR.y, bike.pedalPosR.z),
                ReplayBikeGripContract.crankRadius,
                accuracy: 0.001
            )
        }
    }

    func testBikeErgOppositePedals() {
        let pose = makeStrokePose(phase: 0, amplitude: 1.0)
        let result = ReplayRigPoseSolver.solve(
            sport: .bike, strokePose: pose, distance: 0, reduceMotion: false
        )
        guard case .bike(let bike) = result else {
            XCTFail("Expected bike pose"); return
        }
        // Pedals should be 180° apart at the contract-owned crank radius.
        XCTAssertEqual(bike.pedalPosL.y, ReplayBikeGripContract.crankRadius, accuracy: 0.001)
        XCTAssertEqual(bike.pedalPosR.y, -ReplayBikeGripContract.crankRadius, accuracy: 0.001)
    }

    func testBikeErgThighAnglesDoNotFlipAtBottomOfStroke() {
        let pose = makeStrokePose(phase: .pi, amplitude: 1.0)
        let result = ReplayRigPoseSolver.solve(
            sport: .bike, strokePose: pose, distance: 0, reduceMotion: false
        )
        guard case .bike(let bike) = result else {
            XCTFail("Expected bike pose"); return
        }

        XCTAssertLessThan(abs(bike.joints.hipFlexL), .pi / 2)
        XCTAssertLessThan(abs(bike.joints.hipFlexR), .pi / 2)
    }

    func testBikeErgWheelRotation() {
        let pose = makeStrokePose(phase: .pi, amplitude: 1.0)
        let result = ReplayRigPoseSolver.solve(
            sport: .bike, strokePose: pose, distance: 100, reduceMotion: false
        )
        guard case .bike(let bike) = result else {
            XCTFail("Expected bike pose"); return
        }
        // Wheel should have rotated
        XCTAssertTrue(isFinite(bike.wheelAngle))
        XCTAssertNotEqual(bike.wheelAngle, 0, "Wheel should rotate")
    }

    func testBikeErgWheelRollUsesOuterTyreRadius() {
        let distance = ReplayBikeGripContract.axleY * Double.pi * 2
        let result = ReplayRigPoseSolver.solve(
            sport: .bike,
            strokePose: makeStrokePose(),
            distance: distance,
            reduceMotion: false
        )
        guard case .bike(let bike) = result else {
            return XCTFail("Expected bike pose")
        }
        XCTAssertEqual(bike.wheelAngle, Double.pi * 2, accuracy: 1e-12)
    }

    // MARK: - Reduced Motion Tests

    func testReducedMotionRower() {
        let pose = makeStrokePose(warpedPhase: .pi / 3, amplitude: 1.2)
        let result = ReplayRigPoseSolver.solve(
            sport: .rower, strokePose: pose, distance: 50, reduceMotion: true
        )
        guard case .rower(let rower) = result else {
            XCTFail("Expected rower pose"); return
        }
        // Should be neutral/rest position
        XCTAssertEqual(rower.joints.torsoLean, 0, accuracy: 0.001)
        XCTAssertEqual(rower.joints.kneeFlexL, 0, accuracy: 0.001)
        XCTAssertEqual(rower.oarSweep, 0, accuracy: 0.001)
    }

    func testReducedMotionSkiErg() {
        let pose = makeStrokePose(warpedPhase: .pi / 2, amplitude: 1.0)
        let result = ReplayRigPoseSolver.solve(
            sport: .skierg, strokePose: pose, distance: 30, reduceMotion: true
        )
        guard case .skierg(let ski) = result else {
            XCTFail("Expected skierg pose"); return
        }
        XCTAssertEqual(ski.hipCompression, 0, accuracy: 0.001)
    }

    func testReducedMotionBike() {
        let pose = makeStrokePose(phase: .pi, amplitude: 1.0)
        let result = ReplayRigPoseSolver.solve(
            sport: .bike, strokePose: pose, distance: 100, reduceMotion: true
        )
        guard case .bike(let bike) = result else {
            XCTFail("Expected bike pose"); return
        }
        XCTAssertEqual(bike.crankAngle, 0, accuracy: 0.001)
        XCTAssertEqual(bike.wheelAngle, 0, accuracy: 0.001)
    }

    // MARK: - Canonical Graph Ownership

    func testCanonicalGraphOwnsTechniqueInsteadOfLegacyAmplitude() {
        let lowAmp = makeStrokePose(warpedPhase: 0, amplitude: 0.72)
        let highAmp = makeStrokePose(warpedPhase: 0, amplitude: 1.32)

        let lowResult = ReplayRigPoseSolver.solve(
            sport: .rower, strokePose: lowAmp, distance: 0, reduceMotion: false
        )
        let highResult = ReplayRigPoseSolver.solve(
            sport: .rower, strokePose: highAmp, distance: 0, reduceMotion: false
        )

        guard case .rower(let low) = lowResult,
              case .rower(let high) = highResult else {
            XCTFail("Expected rower poses"); return
        }

        XCTAssertEqual(low.seatZ, high.seatZ, accuracy: 1e-12)
        XCTAssertEqual(low.handleZ, high.handleZ, accuracy: 1e-12)

        let lowEffort = ReplayMotionGraph.sampleRower(pose: makeStrokePose(phase: 0.15 * tau, intensity: 0))
        let highEffort = ReplayMotionGraph.sampleRower(pose: makeStrokePose(phase: 0.15 * tau, intensity: 1))
        XCTAssertNotEqual(lowEffort.accents.surge.value, highEffort.accents.surge.value)
    }

    // MARK: - Edge Cases

    func testNaNInputsProduceFiniteOutputs() {
        let pose = ReplayStrokePose(
            index: 0, phase: .nan, warpedPhase: .nan, cycleFrac: .nan,
            driveFrac: .nan, drive: false, driveProgress: .nan,
            recoveryProgress: .nan, strokeSeconds: .nan, strokeMeters: .nan,
            rate: .nan, watts: 0, intensity: .nan, amplitude: .nan, fatigue: .nan
        )
        for sport: Sport in [.rower, .skierg, .bike] {
            let result = ReplayRigPoseSolver.solve(
                sport: sport, strokePose: pose, distance: .nan, reduceMotion: false
            )
            assertAllFinite(result)
        }
    }

    func testInfinityInputsProduceFiniteOutputs() {
        let pose = ReplayStrokePose(
            index: 0, phase: .infinity, warpedPhase: -.infinity, cycleFrac: .infinity,
            driveFrac: .infinity, drive: false, driveProgress: .infinity,
            recoveryProgress: .infinity, strokeSeconds: .infinity, strokeMeters: .infinity,
            rate: .infinity, watts: 0, intensity: .infinity, amplitude: .infinity,
            fatigue: .infinity
        )
        for sport: Sport in [.rower, .skierg, .bike] {
            let result = ReplayRigPoseSolver.solve(
                sport: sport, strokePose: pose, distance: .infinity, reduceMotion: false
            )
            assertAllFinite(result)
        }
    }

    func testNegativeDistanceProducesFiniteOutputs() {
        let pose = makeStrokePose(warpedPhase: 0, amplitude: 1.0)
        let result = ReplayRigPoseSolver.solve(
            sport: .bike, strokePose: pose, distance: -100, reduceMotion: false
        )
        assertAllFinite(result)
    }

    func testExtremePhaseInputs() {
        // Very large phase (many cycles)
        let pose = makeStrokePose(warpedPhase: 1000 * tau, phase: 1000 * tau, amplitude: 1.0)
        for sport: Sport in [.rower, .skierg, .bike] {
            let result = ReplayRigPoseSolver.solve(
                sport: sport, strokePose: pose, distance: 5000, reduceMotion: false
            )
            assertAllFinite(result)
        }
    }

    // MARK: - Determinism

    func testDeterminism() {
        let pose = makeStrokePose(warpedPhase: .pi / 4, amplitude: 0.95)
        for sport: Sport in [.rower, .skierg, .bike] {
            let result1 = ReplayRigPoseSolver.solve(
                sport: sport, strokePose: pose, distance: 42, reduceMotion: false
            )
            let result2 = ReplayRigPoseSolver.solve(
                sport: sport, strokePose: pose, distance: 42, reduceMotion: false
            )
            XCTAssertEqual(result1, result2,
                "Identical inputs should produce exactly equal outputs for \(sport)")
        }
    }

    // MARK: - Helpers

    private func makeStrokePose(
        warpedPhase: Double = 0,
        phase: Double = 0,
        amplitude: Double = 1.0,
        intensity: Double = 0.5
    ) -> ReplayStrokePose {
        ReplayStrokePose(
            index: 0,
            phase: phase,
            warpedPhase: warpedPhase,
            cycleFrac: 0,
            driveFrac: 0.38,
            drive: false,
            driveProgress: 0,
            recoveryProgress: 0,
            strokeSeconds: 2,
            strokeMeters: 11,
            rate: 28,
            watts: 200,
            intensity: intensity,
            amplitude: amplitude,
            fatigue: 0
        )
    }

    private func isFinite(_ v: Double) -> Bool {
        v.isFinite
    }

    private func assertAllFinite(_ pose: ReplaySportRigPose, file: StaticString = #filePath, line: UInt = #line) {
        switch pose {
        case .rower(let r):
            XCTAssertTrue(r.seatZ.isFinite, "seatZ not finite", file: file, line: line)
            XCTAssertTrue(r.handleY.isFinite, "handleY not finite", file: file, line: line)
            XCTAssertTrue(r.handleZ.isFinite, "handleZ not finite", file: file, line: line)
            XCTAssertTrue(r.oarSweep.isFinite, "oarSweep not finite", file: file, line: line)
            XCTAssertTrue(r.oarFeather.isFinite, "oarFeather not finite", file: file, line: line)
            assertJointsFinite(r.joints, file: file, line: line)
        case .skierg(let s):
            XCTAssertTrue(s.hipCompression.isFinite, "hipCompression not finite", file: file, line: line)
            XCTAssertTrue(s.preferredHandY.isFinite, "preferredHandY not finite", file: file, line: line)
            XCTAssertTrue(s.preferredHandZ.isFinite, "preferredHandZ not finite", file: file, line: line)
            XCTAssertTrue(s.shoulderY.isFinite, "shoulderY not finite", file: file, line: line)
            XCTAssertTrue(s.shoulderZ.isFinite, "shoulderZ not finite", file: file, line: line)
            XCTAssertTrue(s.poleRotation.isFinite, "poleRotation not finite", file: file, line: line)
            XCTAssertTrue(s.poleContact.isFinite, "poleContact not finite", file: file, line: line)
            XCTAssertTrue(s.plantBasketZ.isFinite, "plantBasketZ not finite", file: file, line: line)
            assertJointsFinite(s.joints, file: file, line: line)
        case .bike(let b):
            XCTAssertTrue(b.crankAngle.isFinite, "crankAngle not finite", file: file, line: line)
            XCTAssertTrue(b.wheelAngle.isFinite, "wheelAngle not finite", file: file, line: line)
            XCTAssertTrue(b.pedalPosL.y.isFinite, "pedalPosL.y not finite", file: file, line: line)
            XCTAssertTrue(b.pedalPosL.z.isFinite, "pedalPosL.z not finite", file: file, line: line)
            XCTAssertTrue(b.pedalPosR.y.isFinite, "pedalPosR.y not finite", file: file, line: line)
            XCTAssertTrue(b.pedalPosR.z.isFinite, "pedalPosR.z not finite", file: file, line: line)
            XCTAssertTrue(b.riderSway.isFinite, "riderSway not finite", file: file, line: line)
            assertJointsFinite(b.joints, file: file, line: line)
        }
    }

    private func makeStrokePose(cycleFrac: Double) -> ReplayStrokePose {
        ReplayStrokePose(
            index: 0,
            phase: cycleFrac * tau,
            warpedPhase: cycleFrac * tau,
            cycleFrac: cycleFrac,
            driveFrac: 0.34,
            drive: cycleFrac < 0.34,
            driveProgress: min(1, cycleFrac / 0.34),
            recoveryProgress: max(0, (cycleFrac - 0.34) / 0.66),
            strokeSeconds: 2,
            strokeMeters: 11,
            rate: 28,
            watts: 200,
            intensity: 0.5,
            amplitude: 1,
            fatigue: 0
        )
    }

    private func assertJointsFinite(_ j: ReplayAthleteJointPose, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(j.torsoLean.isFinite, "torsoLean not finite", file: file, line: line)
        XCTAssertTrue(j.torsoTilt.isFinite, "torsoTilt not finite", file: file, line: line)
        XCTAssertTrue(j.headPitch.isFinite, "headPitch not finite", file: file, line: line)
        XCTAssertTrue(j.shoulderFlexL.isFinite, "shoulderFlexL not finite", file: file, line: line)
        XCTAssertTrue(j.shoulderFlexR.isFinite, "shoulderFlexR not finite", file: file, line: line)
        XCTAssertTrue(j.elbowFlexL.isFinite, "elbowFlexL not finite", file: file, line: line)
        XCTAssertTrue(j.elbowFlexR.isFinite, "elbowFlexR not finite", file: file, line: line)
        XCTAssertTrue(j.hipFlexL.isFinite, "hipFlexL not finite", file: file, line: line)
        XCTAssertTrue(j.hipFlexR.isFinite, "hipFlexR not finite", file: file, line: line)
        XCTAssertTrue(j.kneeFlexL.isFinite, "kneeFlexL not finite", file: file, line: line)
        XCTAssertTrue(j.kneeFlexR.isFinite, "kneeFlexR not finite", file: file, line: line)
        XCTAssertTrue(j.ankleDorsiL.isFinite, "ankleDorsiL not finite", file: file, line: line)
        XCTAssertTrue(j.ankleDorsiR.isFinite, "ankleDorsiR not finite", file: file, line: line)
    }
}
