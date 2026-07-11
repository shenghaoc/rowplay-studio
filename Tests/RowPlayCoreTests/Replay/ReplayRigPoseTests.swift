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
        // At finish: drive = cos(π) = -1, recovery = max(0, -sin(π)) = 0
        let pose = makeStrokePose(warpedPhase: .pi, amplitude: 1.0)
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
        // Mid-drive: warpedPhase = π/2
        let pose = makeStrokePose(warpedPhase: .pi / 2, amplitude: 1.0)
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
        // Recovery: warpedPhase = 3π/2 → drive = cos(3π/2) ≈ 0, recovery = max(0, -sin(3π/2)) = 1
        let pose = makeStrokePose(warpedPhase: 3 * .pi / 2, amplitude: 1.0)
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
        // Tall recovery: swing = cos(π) = -1, crunch = max(0, 1) = 1
        let pose = makeStrokePose(warpedPhase: .pi, amplitude: 1.0)
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
        // Handles should be high
        XCTAssertGreaterThan(ski.handleY, 0.4, "Handles should be high at plant")
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
            // Wheel angle should be 2.4× crank
            XCTAssertEqual(bike.wheelAngle, angle * 2.4, accuracy: 0.001,
                "Wheel angle should be 2.4× crank at \(angle)")
            // All values should be finite
            XCTAssertTrue(isFinite(bike.crankAngle))
            XCTAssertTrue(isFinite(bike.wheelAngle))
            XCTAssertTrue(isFinite(bike.pedalPosL.y))
            XCTAssertTrue(isFinite(bike.pedalPosL.z))
            XCTAssertTrue(isFinite(bike.pedalPosR.y))
            XCTAssertTrue(isFinite(bike.pedalPosR.z))
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
        // Pedals should be 180° apart: L at (0.18, 0), R at (-0.18, 0)
        XCTAssertEqual(bike.pedalPosL.y, 0.18, accuracy: 0.001)
        XCTAssertEqual(bike.pedalPosR.y, -0.18, accuracy: 0.001)
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

    // MARK: - Amplitude/Intensity Influence

    func testAmplitudeInfluence() {
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

        // Higher amplitude should produce larger seat travel
        let lowSeatRange = abs(low.seatZ + 0.1)
        let highSeatRange = abs(high.seatZ + 0.1)
        XCTAssertGreaterThan(highSeatRange, lowSeatRange,
            "Higher amplitude should produce larger seat travel")
    }

    // MARK: - Edge Cases

    func testNaNInputsProduceFiniteOutputs() {
        let pose = ReplayStrokePose(
            index: 0, phase: .nan, warpedPhase: .nan, cycleFrac: .nan,
            driveFrac: .nan, drive: false, driveProgress: .nan,
            recoveryProgress: .nan, strokeSeconds: .nan, strokeMeters: .nan,
            rate: .nan, watts: 0, intensity: .nan, amplitude: .nan, fatigue: .nan
        )
        let result = ReplayRigPoseSolver.solve(
            sport: .rower, strokePose: pose, distance: .nan, reduceMotion: false
        )
        assertAllFinite(result)
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
        amplitude: Double = 1.0
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
            intensity: 0.5,
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
            XCTAssertTrue(s.handleY.isFinite, "handleY not finite", file: file, line: line)
            XCTAssertTrue(s.handleZ.isFinite, "handleZ not finite", file: file, line: line)
            XCTAssertTrue(s.poleRotation.isFinite, "poleRotation not finite", file: file, line: line)
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
