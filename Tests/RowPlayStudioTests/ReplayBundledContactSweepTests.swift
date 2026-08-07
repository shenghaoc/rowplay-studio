import RealityKit
import RowPlayCore
import XCTest

@testable import RowPlayStudio

/// Acceptance coverage for the bundled V4 athlete contact pipeline.
///
/// The scene builder fails closed to the procedural rig the moment a single
/// frame's contact solve rejects, so the acceptance bar is that every phase
/// of a full cycle solves for every sport — not just a handful of spot
/// phases.  The reach-clamp boundary cases guard the other direction: a
/// bounded shortfall stays best-effort, an unbounded one must still fail.
@MainActor
final class ReplayBundledContactSweepTests: XCTestCase {
    func testBundledScenesSolveContactsAcrossDenseStrokeCycle() async throws {
        let steps = 257
        for sport in ReplayAssetCatalog.supportedSports {
            let loadedSet = await ReplayAssetLibrary.shared.bundledAssetSet(for: sport)
            let assetSet = try XCTUnwrap(loadedSet)
            let scene = Replay3DSceneBuilder.buildScene(
                sport: sport,
                colorScheme: .dark,
                configuration: ReplayRenderQuality.ultra.configuration,
                effectiveQuality: .ultra,
                bundledAssetSet: assetSet
            )
            XCTAssertEqual(scene.visualSource, .bundled)

            let camera = ReplayCameraController()
            var failures: [(phase: Double, result: String)] = []
            var worst: Float = 0
            for step in 0..<steps {
                let phase = 2 * Double.pi * Double(step) / Double(steps)
                let livePose = ReplayStrokePose.fallback(sport: sport, phase: phase, rate: 28)
                let updated = Replay3DSceneBuilder.updateScene(
                    container: scene,
                    livePose: livePose,
                    liveDistance: Double(step),
                    sport: sport,
                    ghostPose: nil,
                    ghostDistance: 0,
                    ghostVisible: false,
                    reduceMotion: false,
                    deltaTime: 1.0 / 60.0,
                    playbackTickGeneration: UInt64(step + 1),
                    isPlaying: true,
                    cameraController: camera,
                    cameraPreset: .chase,
                    cameraResetGeneration: 0,
                    replayDiscontinuityGeneration: 0
                )
                if case .applied(let error, _)? = ReplayAthleteContactSolver.lastResultForTesting {
                    worst = max(worst, error.maximumGripChannelError)
                }
                if !updated {
                    failures.append(
                        (phase, String(describing: ReplayAthleteContactSolver.lastResultForTesting))
                    )
                }
            }
            XCTAssertTrue(
                failures.isEmpty,
                "\(sport.rawValue): \(failures.count)/\(steps) phases failed; worst applied "
                    + "grip error \(worst); first failures: \(failures.prefix(4))"
            )
            XCTAssertLessThanOrEqual(
                worst,
                ReplayAthleteContactSolver.gripChannelContactBudgetMeters,
                "\(sport.rawValue) applied a solve outside the grip budget"
            )
        }
    }

    /// A hand target just past full extension is clamped and accepted, which
    /// is the web renderer's best-effort behaviour at stroke extremes.
    func testHandTargetWithinReachToleranceIsAccepted() async throws {
        let probe = try await makeReachProbe(name: "reach-within-probe")
        let result = ReplayAthleteContactSolver.solve(
            instance: probe.instance,
            targets: probe.targets(handShortfall: 0.015),
            relativeTo: probe.space
        )
        guard case .applied = result else {
            return XCTFail("Expected a bounded shortfall to stay best-effort, got \(result)")
        }
    }

    /// A hand target far past full extension must NOT be silently clamped
    /// into a phantom contact: the frame fails closed and the sampled pose is
    /// restored, so the scene can fall back rather than render a hand
    /// floating off the equipment.
    func testHandTargetBeyondReachToleranceFailsClosed() async throws {
        let probe = try await makeReachProbe(name: "reach-beyond-probe")
        let beforePose = try XCTUnwrap(probe.instance.currentConstraintPose())
        let beforeRoot = probe.instance.root.transform

        let result = ReplayAthleteContactSolver.solve(
            instance: probe.instance,
            targets: probe.targets(handShortfall: 0.25),
            relativeTo: probe.space
        )
        guard case .failed(.residualExceeded(let error), _) = result else {
            return XCTFail("Expected an unreachable hand to fail closed, got \(result)")
        }
        XCTAssertGreaterThan(
            error.maximumGripChannelError,
            ReplayAthleteContactSolver.gripChannelContactBudgetMeters,
            "Residual must be measured against the true target, not the clamped one"
        )

        let afterPose = try XCTUnwrap(probe.instance.currentConstraintPose())
        XCTAssertEqual(
            beforePose.jointTransforms.map(\.rotation.vector),
            afterPose.jointTransforms.map(\.rotation.vector)
        )
        XCTAssertEqual(beforeRoot.translation, probe.instance.root.transform.translation)
    }

    // MARK: - Helpers

    /// Contact targets derived from the athlete's own current skeleton are
    /// reachable by construction, so a hand displaced along its existing
    /// shoulder direction isolates exactly the reach shortfall under test.
    private struct ReachProbe {
        let instance: ReplayAthleteInstance
        let space: Entity
        let pelvis: SIMD3<Float>
        let feet: [ReplayAthleteContactRole: SIMD3<Float>]
        let shoulders: [ReplayAthleteContactRole: SIMD3<Float>]
        let handDirections: [ReplayAthleteContactRole: SIMD3<Float>]
        let armLengths: [ReplayAthleteContactRole: Float]

        func targets(handShortfall: Float) -> ReplayAthleteContactTargets {
            func hand(_ role: ReplayAthleteContactRole) -> SIMD3<Float> {
                shoulders[role]! + handDirections[role]!
                    * (armLengths[role]! * 0.998 + handShortfall)
            }
            return ReplayAthleteContactTargets(
                pelvis: pelvis,
                leftHand: hand(.leftHand),
                rightHand: hand(.rightHand),
                leftFoot: feet[.leftFoot]!,
                rightFoot: feet[.rightFoot]!
            )
        }
    }

    private func makeReachProbe(name: String) async throws -> ReachProbe {
        let loaded = await ReplayAssetLibrary.shared.bundledAssetSet(for: .rower)
        let assetSet = try XCTUnwrap(loaded)
        let instance = try XCTUnwrap(assetSet.makeAthleteInstance(
            sport: .rower,
            name: name,
            isRival: false,
            quality: .ultra
        ))
        let space = Entity()
        instance.attach(to: space)
        instance.captureBaseRootTransform()
        XCTAssertTrue(instance.beginConstraintPass())

        func contact(_ role: ReplayAthleteContactRole) throws -> SIMD3<Float> {
            try XCTUnwrap(instance.skeletalContactPosition(role: role, relativeTo: space))
        }
        func joint(_ bone: String) throws -> SIMD3<Float> {
            try XCTUnwrap(instance.skeletalJointPosition(named: bone, relativeTo: space))
        }

        var shoulders: [ReplayAthleteContactRole: SIMD3<Float>] = [:]
        var directions: [ReplayAthleteContactRole: SIMD3<Float>] = [:]
        var armLengths: [ReplayAthleteContactRole: Float] = [:]
        for (role, side) in [(ReplayAthleteContactRole.leftHand, "Left"),
                             (ReplayAthleteContactRole.rightHand, "Right")] {
            let shoulder = try joint("v4\(side)UpperArm")
            let elbow = try joint("v4\(side)Forearm")
            let hand = try contact(role)
            let span = simd_distance(shoulder, elbow) + simd_distance(elbow, hand)
            XCTAssertGreaterThan(span, 0.1, "Degenerate \(side) arm in probe")
            shoulders[role] = shoulder
            directions[role] = simd_normalize(hand - shoulder)
            armLengths[role] = span
        }

        return ReachProbe(
            instance: instance,
            space: space,
            pelvis: try joint("v4Hips"),
            feet: [
                .leftFoot: try contact(.leftFoot),
                .rightFoot: try contact(.rightFoot)
            ],
            shoulders: shoulders,
            handDirections: directions,
            armLengths: armLengths
        )
    }
}
