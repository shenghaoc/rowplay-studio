import Foundation
import RealityKit
import RowPlayCore

enum ReplaySportRigPoseFailure: Equatable, Sendable {
    case unexpectedSport
    case missingMotionSample
    case motionSampleRejected
    case nonfiniteSample
    case contact(ReplayAthleteContactSolveFailure)
}

enum ReplaySportRigPoseResult: Equatable, Sendable {
    case applied
    case failed(ReplaySportRigPoseFailure)

    var failure: ReplaySportRigPoseFailure? {
        guard case .failed(let failure) = self else { return nil }
        return failure
    }
}

/// The athlete implementation is fixed once while constructing a rig. Runtime
/// pose application cannot fall through from a bundled athlete into a hidden
/// procedural body.
@MainActor
enum ReplayRigSource {
    case procedural(ReplayAthleteRig)
    case bundled(ReplayBundledAthleteRuntime)

    var bundledAthlete: ReplayAthleteInstance? {
        guard case .bundled(let runtime) = self else { return nil }
        return runtime.instance
    }
}

/// Shared sample -> contact pipeline used identically by all three sport rigs.
@MainActor
final class ReplayBundledAthleteRuntime {
    let instance: ReplayAthleteInstance
    private let sport: Sport
    private let poseAdapter: ReplayAthletePoseAdapter
    private let contactPlanResult: Result<ReplayAthleteContactPlan, ReplayAthleteContactSolveFailure>

    init(
        instance: ReplayAthleteInstance,
        sport: Sport,
        parent: Entity,
        rootScale: Float,
        rootPosition: SIMD3<Float>
    ) {
        self.instance = instance
        self.sport = sport
        self.poseAdapter = ReplayAthletePoseAdapter(contract: instance.contract)
        instance.attach(to: parent)
        instance.root.scale = SIMD3(repeating: rootScale)
        instance.root.position = rootPosition
        // Blender's USD export presents the athlete facing -Z where the
        // pinned GLB (and every sport rig ported from the web renderer)
        // faces +Z.  Yawing the instance root 180° restores the web-parity
        // facing for all three sports.
        instance.root.orientation = simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))
        instance.captureBaseRootTransform()
        do {
            self.contactPlanResult = .success(try ReplayAthleteContactPlan(instance: instance))
        } catch let failure as ReplayAthleteContactSolveFailure {
            self.contactPlanResult = .failure(failure)
        } catch {
            self.contactPlanResult = .failure(.malformedHierarchy("contact preflight failed"))
        }
    }

    func apply(
        motion: ReplayAthleteMotionSample?,
        targets: ReplayAthleteContactTargets,
        relativeTo space: Entity
    ) -> ReplaySportRigPoseResult {
        guard let motion else { return .failed(.missingMotionSample) }
        guard poseAdapter.apply(sample: motion, sport: sport, to: instance) else {
            return .failed(.motionSampleRejected)
        }
        guard instance.hasFiniteJointTransforms() else {
            return .failed(.nonfiniteSample)
        }
        guard case .success(let contactPlan) = contactPlanResult else {
            if case .failure(let failure) = contactPlanResult {
                return .failed(.contact(failure))
            }
            return .failed(.contact(.missingConstraintPose))
        }
        switch ReplayAthleteContactSolver.solve(
            instance: instance,
            targets: targets,
            relativeTo: space,
            plan: contactPlan
        ) {
        case .applied:
            return instance.hasFiniteJointTransforms() ? .applied : .failed(.nonfiniteSample)
        case .failed(let failure, _):
            return .failed(.contact(failure))
        }
    }
}
