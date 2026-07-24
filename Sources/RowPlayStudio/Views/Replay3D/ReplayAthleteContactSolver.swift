import Foundation
import RealityKit
import RowPlayCore
import simd

/// Equipment-contact targets for a V4 athlete instance.
struct ReplayAthleteContactTargets {
    var pelvis: SIMD3<Float>
    var leftHand: SIMD3<Float>
    var rightHand: SIMD3<Float>
    var leftFoot: SIMD3<Float>
    var rightFoot: SIMD3<Float>
}

/// Measured residual after a contact pass.
struct ReplayAthleteContactError: Equatable, Sendable {
    var leftHand: Float
    var rightHand: Float
    var leftFoot: Float
    var rightFoot: Float
    var pelvis: Float

    var maximumPalmError: Float { max(leftHand, rightHand) }
    var maximumSoleError: Float { max(leftFoot, rightFoot) }
}

/// Corrects the sampled V4 skeleton toward equipment contacts.
///
/// This deliberately edits `SkeletalPosesComponent`, never the four contact
/// marker entities.  Markers are updated only from the solved bone positions
/// for diagnostics, which makes a residual visible instead of hiding it by
/// snapping a helper entity to the machine.
@MainActor
enum ReplayAthleteContactSolver {
    /// Soft residual budget for a sampled asset whose limb lengths cannot
    /// reach every procedural equipment configuration exactly.
    static let softContactBudgetMeters: Float = 0.12

    /// A finite but visibly detached skeleton is a failed canonical asset at
    /// runtime too. Let the scene builder take its complete procedural path
    /// rather than retain an implausible hybrid replay.
    static func isUsable(_ error: ReplayAthleteContactError) -> Bool {
        let values = [
            error.leftHand,
            error.rightHand,
            error.leftFoot,
            error.rightFoot,
            error.pelvis,
        ]
        return values.allSatisfy { $0.isFinite && $0 <= softContactBudgetMeters }
    }

    /// Reset the instance to the authored clip sample and its configured root
    /// placement. Must be called before `orientHandsToTargets` and `constrain`.
    @discardableResult
    static func prepare(instance: ReplayAthleteInstance) -> Bool {
        instance.beginConstraintPass()
    }

    /// Pre-orient both arm chains before pelvis/leg closure. RowErg calls this
    /// explicitly so hand-to-handle reach never cuts through the torso as the
    /// seat moves; the final pass repeats the solve after pelvis placement.
    static func orientHandsToTargets(
        instance: ReplayAthleteInstance,
        targets: ReplayAthleteContactTargets,
        relativeTo space: Entity
    ) {
        guard var pose = instance.currentConstraintPose() else { return }
        solveArm(
            instance: instance,
            pose: &pose,
            role: "left-hand",
            target: instance.athleteEntity.convert(position: targets.leftHand, from: space),
            branchHint: SIMD3(-0.65, -0.22, -0.70)
        )
        solveArm(
            instance: instance,
            pose: &pose,
            role: "right-hand",
            target: instance.athleteEntity.convert(position: targets.rightHand, from: space),
            branchHint: SIMD3(0.65, -0.22, -0.70)
        )
        instance.writeConstraintPose(pose)
    }

    /// Close pelvis, arm, and leg constraints using the prepared pose.
    ///
    /// All root and contact positions are calculated in the supplied rig space
    /// so a rival instance, a BikeErg rider subgroup, and a live instance do
    /// not leak transforms or pose state into one another.
    static func constrain(
        instance: ReplayAthleteInstance,
        targets: ReplayAthleteContactTargets,
        relativeTo space: Entity
    ) -> ReplayAthleteContactError {
        guard var pose = instance.currentConstraintPose() else {
            return unavailableError()
        }

        alignPelvis(instance: instance, pose: pose, target: targets.pelvis, relativeTo: space)

        // Root translation changes the equipment targets in athlete space.
        solveArm(
            instance: instance,
            pose: &pose,
            role: "left-hand",
            target: instance.athleteEntity.convert(position: targets.leftHand, from: space),
            branchHint: SIMD3(-0.65, -0.22, -0.70)
        )
        solveArm(
            instance: instance,
            pose: &pose,
            role: "right-hand",
            target: instance.athleteEntity.convert(position: targets.rightHand, from: space),
            branchHint: SIMD3(0.65, -0.22, -0.70)
        )
        solveLeg(
            instance: instance,
            pose: &pose,
            role: "left-foot",
            target: instance.athleteEntity.convert(position: targets.leftFoot, from: space),
            branchHint: SIMD3(-0.24, 0.18, 0.82)
        )
        solveLeg(
            instance: instance,
            pose: &pose,
            role: "right-foot",
            target: instance.athleteEntity.convert(position: targets.rightFoot, from: space),
            branchHint: SIMD3(0.24, 0.18, 0.82)
        )
        instance.writeConstraintPose(pose)
        updateDebugMarkers(instance: instance, relativeTo: space)
        return measure(instance: instance, targets: targets, relativeTo: space)
    }

    static func measure(
        instance: ReplayAthleteInstance,
        targets: ReplayAthleteContactTargets,
        relativeTo space: Entity
    ) -> ReplayAthleteContactError {
        ReplayAthleteContactError(
            leftHand: distance(instance.skeletalContactPosition(role: "left-hand", relativeTo: space), targets.leftHand),
            rightHand: distance(instance.skeletalContactPosition(role: "right-hand", relativeTo: space), targets.rightHand),
            leftFoot: distance(instance.skeletalContactPosition(role: "left-foot", relativeTo: space), targets.leftFoot),
            rightFoot: distance(instance.skeletalContactPosition(role: "right-foot", relativeTo: space), targets.rightFoot),
            pelvis: distance(instance.skeletalJointPosition(named: "v4Hips", relativeTo: space), targets.pelvis)
        )
    }

    private static func alignPelvis(
        instance: ReplayAthleteInstance,
        pose: SkeletalPose,
        target: SIMD3<Float>,
        relativeTo space: Entity
    ) {
        guard instance.jointIndex(named: "v4Hips", in: pose) != nil,
              let current = instance.skeletalJointPosition(named: "v4Hips", relativeTo: space) else {
            instance.root.setPosition(target, relativeTo: space)
            return
        }
        let rootPosition = instance.root.position(relativeTo: space)
        instance.root.setPosition(rootPosition + (target - current), relativeTo: space)
    }

    private static func solveArm(
        instance: ReplayAthleteInstance,
        pose: inout SkeletalPose,
        role: String,
        target: SIMD3<Float>,
        branchHint: SIMD3<Float>
    ) {
        let names: (upper: String, lower: String, terminal: String) = role == "left-hand"
            ? ("v4LeftUpperArm", "v4LeftForearm", "v4LeftHand")
            : ("v4RightUpperArm", "v4RightForearm", "v4RightHand")
        solveLimb(
            instance: instance,
            pose: &pose,
            role: role,
            names: names,
            target: target,
            branchHint: branchHint,
            terminalUp: SIMD3(0, 1, 0)
        )
    }

    private static func solveLeg(
        instance: ReplayAthleteInstance,
        pose: inout SkeletalPose,
        role: String,
        target: SIMD3<Float>,
        branchHint: SIMD3<Float>
    ) {
        let names: (upper: String, lower: String, terminal: String) = role == "left-foot"
            ? ("v4LeftUpperLeg", "v4LeftLowerLeg", "v4LeftFoot")
            : ("v4RightUpperLeg", "v4RightLowerLeg", "v4RightFoot")
        solveLimb(
            instance: instance,
            pose: &pose,
            role: role,
            names: names,
            target: target,
            branchHint: branchHint,
            terminalUp: SIMD3(0, 0, 1)
        )
    }

    private static func solveLimb(
        instance: ReplayAthleteInstance,
        pose: inout SkeletalPose,
        role: String,
        names: (upper: String, lower: String, terminal: String),
        target: SIMD3<Float>,
        branchHint: SIMD3<Float>,
        terminalUp: SIMD3<Float>
    ) {
        guard let contact = instance.contactSpec(role: role),
              let upper = instance.jointIndex(named: names.upper, in: pose),
              let lower = instance.jointIndex(named: names.lower, in: pose),
              let terminal = instance.jointIndex(named: names.terminal, in: pose) else {
            return
        }
        let offset = SIMD3<Float>(
            Float(contact.localOffset.x),
            Float(contact.localOffset.y),
            Float(contact.localOffset.z)
        )
        var matrices = instance.skeletalJointMatrices(for: pose)
        guard matrices.indices.contains(upper), matrices.indices.contains(lower), matrices.indices.contains(terminal) else {
            return
        }
        let root = point(.zero, matrix: matrices[upper])
        let elbow = point(.zero, matrix: matrices[lower])
        let contactPoint = point(offset, matrix: matrices[terminal])
        let solution = ReplayTwoBoneSolver.solve3D(
            root: double(root),
            target: double(target),
            firstLength: Double(length(elbow - root)),
            secondLength: Double(length(contactPoint - elbow)),
            bendHint: double(branchHint)
        )
        let targetJoint = float(solution.joint)
        let targetEnd = float(solution.end)

        aimJoint(
            pose: &pose,
            instance: instance,
            joint: upper,
            sourceStart: root,
            sourceEnd: elbow,
            targetEnd: targetJoint
        )
        matrices = instance.skeletalJointMatrices(for: pose)
        guard matrices.indices.contains(lower), matrices.indices.contains(terminal) else { return }
        let newElbow = point(.zero, matrix: matrices[lower])
        let currentContact = point(offset, matrix: matrices[terminal])
        aimJoint(
            pose: &pose,
            instance: instance,
            joint: lower,
            sourceStart: newElbow,
            sourceEnd: currentContact,
            targetEnd: targetEnd
        )
        matrices = instance.skeletalJointMatrices(for: pose)
        guard matrices.indices.contains(terminal) else { return }
        orientTerminal(
            pose: &pose,
            instance: instance,
            joint: terminal,
            contactOffset: offset,
            upHint: terminalUp,
            matrices: matrices
        )
    }

    private static func aimJoint(
        pose: inout SkeletalPose,
        instance: ReplayAthleteInstance,
        joint: Int,
        sourceStart: SIMD3<Float>,
        sourceEnd: SIMD3<Float>,
        targetEnd: SIMD3<Float>
    ) {
        let source = sourceEnd - sourceStart
        let destination = targetEnd - sourceStart
        guard length(source) > 1e-5, length(destination) > 1e-5 else { return }
        let matrices = instance.skeletalJointMatrices(for: pose)
        guard matrices.indices.contains(joint) else { return }
        let currentWorld = Transform(matrix: matrices[joint]).rotation
        let desiredWorld = rotation(from: source, to: destination) * currentWorld
        let parentWorld: simd_quatf
        if let parent = parentIndex(of: joint, in: pose), matrices.indices.contains(parent) {
            parentWorld = Transform(matrix: matrices[parent]).rotation
        } else {
            parentWorld = identityQuaternion()
        }
        let local = normalized(inverse(parentWorld) * desiredWorld)
        var transforms = pose.jointTransforms
        var transform = transforms[joint]
        transform.rotation = local
        transforms[joint] = transform
        pose.jointTransforms = transforms
    }

    /// Apply only a twist around the terminal contact vector. This gives hands
    /// and feet a stable orientation cue while preserving their solved contact
    /// point exactly (a twist cannot move a point on its own rotation axis).
    private static func orientTerminal(
        pose: inout SkeletalPose,
        instance: ReplayAthleteInstance,
        joint: Int,
        contactOffset: SIMD3<Float>,
        upHint: SIMD3<Float>,
        matrices: [simd_float4x4]
    ) {
        guard matrices.indices.contains(joint) else { return }
        let matrix = matrices[joint]
        let terminalPosition = point(.zero, matrix: matrix)
        let contactPosition = point(contactOffset, matrix: matrix)
        let axis = contactPosition - terminalPosition
        guard length(axis) > 1e-5 else { return }
        let normal = normalize(axis)
        let currentWorld = Transform(matrix: matrix).rotation
        let currentUp = project(simd_act(currentWorld, SIMD3(0, 1, 0)), off: normal)
        let desiredUp = project(upHint, off: normal)
        guard length(currentUp) > 1e-5, length(desiredUp) > 1e-5 else { return }
        let from = normalize(currentUp)
        let to = normalize(desiredUp)
        let angle = atan2(simd_dot(normal, simd_cross(from, to)), simd_dot(from, to))
        let desiredWorld = simd_quatf(angle: angle, axis: normal) * currentWorld
        let parentWorld: simd_quatf
        if let parent = parentIndex(of: joint, in: pose), matrices.indices.contains(parent) {
            parentWorld = Transform(matrix: matrices[parent]).rotation
        } else {
            parentWorld = identityQuaternion()
        }
        var transforms = pose.jointTransforms
        var transform = transforms[joint]
        transform.rotation = normalized(inverse(parentWorld) * desiredWorld)
        transforms[joint] = transform
        pose.jointTransforms = transforms
    }

    private static func updateDebugMarkers(instance: ReplayAthleteInstance, relativeTo space: Entity) {
        for role in ["left-hand", "right-hand", "left-foot", "right-foot"] {
            if let position = instance.skeletalContactPosition(role: role, relativeTo: space) {
                instance.setContactDebugMarker(role: role, position: position, relativeTo: space)
            }
        }
    }

    private static func parentIndex(of index: Int, in pose: SkeletalPose) -> Int? {
        guard pose.jointNames.indices.contains(index) else { return nil }
        let path = pose.jointNames[index]
        guard let slash = path.lastIndex(of: "/") else { return nil }
        let parent = String(path[..<slash])
        return pose.jointNames.firstIndex(of: parent)
    }

    private static func rotation(from source: SIMD3<Float>, to target: SIMD3<Float>) -> simd_quatf {
        let from = normalize(source)
        let to = normalize(target)
        let scalar = max(-1 as Float, min(1 as Float, simd_dot(from, to)))
        if scalar > 0.999_99 { return identityQuaternion() }
        if scalar < -0.999_99 {
            let basis = abs(from.x) < abs(from.y) && abs(from.x) < abs(from.z)
                ? SIMD3<Float>(1, 0, 0)
                : abs(from.y) < abs(from.z) ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(0, 0, 1)
            return simd_quatf(angle: .pi, axis: normalize(simd_cross(from, basis)))
        }
        let cross = simd_cross(from, to)
        return normalized(simd_quatf(vector: SIMD4(cross.x, cross.y, cross.z, 1 + scalar)))
    }

    private static func inverse(_ quaternion: simd_quatf) -> simd_quatf {
        let value = quaternion.vector
        return simd_quatf(vector: SIMD4(-value.x, -value.y, -value.z, value.w))
    }

    private static func normalized(_ quaternion: simd_quatf) -> simd_quatf {
        let value = quaternion.vector
        let magnitude = sqrt(value.x * value.x + value.y * value.y + value.z * value.z + value.w * value.w)
        guard magnitude.isFinite, magnitude > 1e-6 else { return identityQuaternion() }
        return simd_quatf(vector: value / magnitude)
    }

    private static func identityQuaternion() -> simd_quatf {
        simd_quatf(angle: 0, axis: SIMD3(1, 0, 0))
    }

    private static func project(_ vector: SIMD3<Float>, off normal: SIMD3<Float>) -> SIMD3<Float> {
        vector - normal * simd_dot(vector, normal)
    }

    private static func point(_ point: SIMD3<Float>, matrix: simd_float4x4) -> SIMD3<Float> {
        let value = matrix * SIMD4(point.x, point.y, point.z, 1)
        guard value.x.isFinite, value.y.isFinite, value.z.isFinite, value.w.isFinite,
              abs(value.w) > 1e-6 else { return .zero }
        return SIMD3(value.x, value.y, value.z) / value.w
    }

    private static func distance(_ point: SIMD3<Float>?, _ target: SIMD3<Float>) -> Float {
        guard let point else { return .infinity }
        let result = length(point - target)
        return result.isFinite ? result : .infinity
    }

    private static func unavailableError() -> ReplayAthleteContactError {
        ReplayAthleteContactError(
            leftHand: .infinity,
            rightHand: .infinity,
            leftFoot: .infinity,
            rightFoot: .infinity,
            pelvis: .infinity
        )
    }

    private static func double(_ value: SIMD3<Float>) -> SIMD3<Double> {
        SIMD3(Double(value.x), Double(value.y), Double(value.z))
    }

    private static func float(_ value: SIMD3<Double>) -> SIMD3<Float> {
        SIMD3(Float(value.x), Float(value.y), Float(value.z))
    }

    private static func length(_ value: SIMD3<Float>) -> Float {
        sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
    }
}
