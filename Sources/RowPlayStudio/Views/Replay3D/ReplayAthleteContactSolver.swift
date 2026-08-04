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

    subscript(role: ReplayAthleteContactRole) -> SIMD3<Float> {
        switch role {
        case .leftHand: leftHand
        case .rightHand: rightHand
        case .leftFoot: leftFoot
        case .rightFoot: rightFoot
        }
    }
}

/// Measured residual after a contact pass.
struct ReplayAthleteContactError: Equatable, Sendable {
    var leftHand: Float
    var rightHand: Float
    var leftFoot: Float
    var rightFoot: Float
    var pelvis: Float

    var maximumGripChannelError: Float { max(leftHand, rightHand) }
    var maximumSoleError: Float { max(leftFoot, rightFoot) }
}

struct ReplayAthleteMatrixEvaluationMetrics: Equatable, Sendable {
    var topologyBuilds: Int = 0
    var fullWorkspaceBuilds: Int = 0
    var jointMatrixEvaluations: Int = 0
}

enum ReplayAthleteContactSolveFailure: Error, Equatable, Sendable {
    case missingConstraintPose
    case malformedHierarchy(String)
    case missingContact(ReplayAthleteContactRole)
    case missingJoint(role: ReplayAthleteContactRole, bone: String)
    case degenerateLimb(ReplayAthleteContactRole)
    case nonfiniteTarget(ReplayAthleteContactRole)
    case poseWriteRejected
    case residualExceeded(ReplayAthleteContactError)
}

enum ReplayAthleteContactSolveResult: Equatable, Sendable {
    case applied(error: ReplayAthleteContactError, metrics: ReplayAthleteMatrixEvaluationMetrics)
    case failed(failure: ReplayAthleteContactSolveFailure, metrics: ReplayAthleteMatrixEvaluationMetrics)

    var metrics: ReplayAthleteMatrixEvaluationMetrics {
        switch self {
        case .applied(_, let metrics), .failed(_, let metrics): metrics
        }
    }
}

/// Contact policy is centralized here instead of being duplicated by three
/// sport rigs or embedded as role/name switches in the numerical solver.
@MainActor
fileprivate struct ReplayAthleteContactPolicy {
    let role: ReplayAthleteContactRole
    let bone: String
    let offset: SIMD3<Float>
    let bendHint: SIMD3<Float>
    let terminalUp: SIMD3<Float>

    init?(instance: ReplayAthleteInstance, role: ReplayAthleteContactRole) {
        guard let spec = instance.resolvedContactSpec(role: role),
              spec.localOffset.x.isFinite,
              spec.localOffset.y.isFinite,
              spec.localOffset.z.isFinite else {
            return nil
        }
        self.role = role
        self.bone = spec.bone
        self.offset = SIMD3(
            Float(spec.localOffset.x),
            Float(spec.localOffset.y),
            Float(spec.localOffset.z)
        )

        switch role {
        case .leftHand:
            bendHint = SIMD3(-0.65, -0.22, -0.70)
            terminalUp = SIMD3(0, 1, 0)
        case .rightHand:
            bendHint = SIMD3(0.65, -0.22, -0.70)
            terminalUp = SIMD3(0, 1, 0)
        case .leftFoot:
            bendHint = SIMD3(-0.24, 0.18, 0.82)
            terminalUp = SIMD3(0, 0, 1)
        case .rightFoot:
            bendHint = SIMD3(0.24, 0.18, 0.82)
            terminalUp = SIMD3(0, 0, 1)
        }
    }
}

fileprivate struct ReplayAthleteContactBinding {
    let policy: ReplayAthleteContactPolicy
    let upper: Int
    let lower: Int
    let terminal: Int
}

fileprivate struct ReplayAthleteJointTopology {
    let parent: [Int?]
    let children: [[Int]]
    let evaluationOrder: [Int]

    init(jointNames: [String]) throws {
        guard !jointNames.isEmpty, Set(jointNames).count == jointNames.count else {
            throw ReplayAthleteContactSolveFailure.malformedHierarchy("empty or duplicate joint path")
        }
        let indexByPath = Dictionary(uniqueKeysWithValues: jointNames.enumerated().map { ($0.element, $0.offset) })
        var resolvedParents = Array<Int?>(repeating: nil, count: jointNames.count)
        var resolvedChildren = Array(repeating: [Int](), count: jointNames.count)
        for (index, path) in jointNames.enumerated() {
            guard let slash = path.lastIndex(of: "/") else { continue }
            let parentPath = String(path[..<slash])
            guard let parentIndex = indexByPath[parentPath], parentIndex != index else {
                throw ReplayAthleteContactSolveFailure.malformedHierarchy("missing parent for \(path)")
            }
            resolvedParents[index] = parentIndex
            resolvedChildren[parentIndex].append(index)
        }
        var order: [Int] = []
        var queue = resolvedParents.indices.filter { resolvedParents[$0] == nil }
        var cursor = 0
        while cursor < queue.count {
            let index = queue[cursor]
            cursor += 1
            order.append(index)
            queue.append(contentsOf: resolvedChildren[index])
        }
        guard order.count == jointNames.count else {
            throw ReplayAthleteContactSolveFailure.malformedHierarchy("cyclic hierarchy")
        }
        parent = resolvedParents
        children = resolvedChildren
        evaluationOrder = order
    }
}

/// One mutable world-matrix workspace per contact pass. Changing a local joint
/// recomputes only that joint and its descendants; no limb step rebuilds the
/// complete skeletal matrix array.
@MainActor
struct ReplayAthleteContactPlan {
    fileprivate let jointNames: [String]
    fileprivate let topology: ReplayAthleteJointTopology
    fileprivate let bindings: [ReplayAthleteContactRole: ReplayAthleteContactBinding]
    fileprivate let pelvisIndex: Int

    init(instance: ReplayAthleteInstance) throws {
        guard let pose = instance.currentConstraintPose() else {
            throw ReplayAthleteContactSolveFailure.missingConstraintPose
        }
        let topology = try ReplayAthleteJointTopology(jointNames: pose.jointNames)
        self.jointNames = pose.jointNames
        self.topology = topology
        self.bindings = try ReplayAthleteContactSolver.makeBindings(
            instance: instance,
            pose: pose,
            topology: topology
        )
        guard let pelvisBone = instance.contract.semanticBones.first(where: { $0.parent == nil })?.name,
              let pelvisIndex = instance.jointIndex(named: pelvisBone, in: pose) else {
            throw ReplayAthleteContactSolveFailure.malformedHierarchy("missing contract root joint")
        }
        self.pelvisIndex = pelvisIndex
    }
}

private struct ReplayAthleteMatrixWorkspace {
    var pose: SkeletalPose
    let topology: ReplayAthleteJointTopology
    private(set) var matrices: [simd_float4x4]
    private(set) var metrics = ReplayAthleteMatrixEvaluationMetrics()

    init(
        pose: SkeletalPose,
        topology: ReplayAthleteJointTopology,
        topologyWasPrecomputed: Bool
    ) throws {
        guard pose.jointNames.count == pose.jointTransforms.count,
              topology.parent.count == pose.jointNames.count else {
            throw ReplayAthleteContactSolveFailure.malformedHierarchy("joint/transform count mismatch")
        }
        self.pose = pose
        self.topology = topology
        self.matrices = Array(repeating: matrix_identity_float4x4, count: pose.jointNames.count)
        metrics.topologyBuilds = topologyWasPrecomputed ? 0 : 1
        metrics.fullWorkspaceBuilds = 1
        for index in topology.evaluationOrder {
            recompute(index)
        }
    }

    mutating func setRotation(_ rotation: simd_quatf, at joint: Int) {
        var transforms = pose.jointTransforms
        var transform = transforms[joint]
        transform.rotation = rotation
        transforms[joint] = transform
        pose.jointTransforms = transforms
        recomputeSubtree(from: joint)
    }

    private mutating func recomputeSubtree(from root: Int) {
        recompute(root)
        for child in topology.children[root] {
            recomputeSubtree(from: child)
        }
    }

    private mutating func recompute(_ index: Int) {
        let local = pose.jointTransforms[index].matrix
        if let parent = topology.parent[index] {
            matrices[index] = matrices[parent] * local
        } else {
            matrices[index] = local
        }
        metrics.jointMatrixEvaluations += 1
    }
}

/// Corrects the sampled V4 skeleton toward equipment contacts.
@MainActor
enum ReplayAthleteContactSolver {
    static let gripChannelContactBudgetMeters: Float = 0.01
    static let reachContactBudgetMeters: Float = 0.12

    /// Deterministic instrumentation seam used by focused performance tests.
    private(set) static var lastMetricsForTesting: ReplayAthleteMatrixEvaluationMetrics?
    private(set) static var lastResultForTesting: ReplayAthleteContactSolveResult?

    static func resetMetricsForTesting() {
        lastMetricsForTesting = nil
        lastResultForTesting = nil
    }

    static func hierarchyFailureForTesting(jointNames: [String]) -> ReplayAthleteContactSolveFailure? {
        do {
            _ = try ReplayAthleteJointTopology(jointNames: jointNames)
            return nil
        } catch let failure as ReplayAthleteContactSolveFailure {
            return failure
        } catch {
            return .malformedHierarchy("unknown hierarchy failure")
        }
    }

    static func isUsable(_ error: ReplayAthleteContactError) -> Bool {
        let values = [error.leftHand, error.rightHand, error.leftFoot, error.rightFoot, error.pelvis]
        return values.allSatisfy(\.isFinite)
            && error.maximumGripChannelError <= gripChannelContactBudgetMeters
            && error.maximumSoleError <= reachContactBudgetMeters
            && error.pelvis <= reachContactBudgetMeters
    }

    static func solve(
        instance: ReplayAthleteInstance,
        targets: ReplayAthleteContactTargets,
        relativeTo space: Entity,
        plan: ReplayAthleteContactPlan? = nil
    ) -> ReplayAthleteContactSolveResult {
        guard ReplayAthleteContactRole.allCases.allSatisfy({ isFinite(targets[$0]) }) else {
            let role = ReplayAthleteContactRole.allCases.first { !isFinite(targets[$0]) }!
            return record(.failed(failure: .nonfiniteTarget(role), metrics: .init()))
        }
        guard instance.beginConstraintPass(), let pose = instance.currentConstraintPose() else {
            return record(.failed(failure: .missingConstraintPose, metrics: .init()))
        }

        let originalRootTransform = instance.root.transform
        var failureMetrics = ReplayAthleteMatrixEvaluationMetrics()
        do {
            let resolvedPlan = try plan ?? ReplayAthleteContactPlan(instance: instance)
            guard resolvedPlan.jointNames == pose.jointNames else {
                throw ReplayAthleteContactSolveFailure.malformedHierarchy("joint paths changed after preflight")
            }
            var workspace = try ReplayAthleteMatrixWorkspace(
                pose: pose,
                topology: resolvedPlan.topology,
                topologyWasPrecomputed: plan != nil
            )
            defer { failureMetrics = workspace.metrics }
            let bindings = resolvedPlan.bindings
            let pelvisIndex = resolvedPlan.pelvisIndex

            // Row's long reach benefits from an initial arm clearance solve.
            // The same workspace is retained through root closure and the
            // final all-limb pass.
            if instance.sport == .rower {
                for role in [ReplayAthleteContactRole.leftHand, .rightHand] {
                    try solveLimb(
                        binding: bindings[role]!,
                        target: instance.athleteEntity.convert(position: targets[role], from: space),
                        workspace: &workspace
                    )
                }
            }

            alignPelvis(
                instance: instance,
                workspace: workspace,
                pelvisIndex: pelvisIndex,
                target: targets.pelvis,
                relativeTo: space
            )

            for role in ReplayAthleteContactRole.allCases {
                try solveLimb(
                    binding: bindings[role]!,
                    target: instance.athleteEntity.convert(position: targets[role], from: space),
                    workspace: &workspace
                )
            }

            guard instance.writeConstraintPose(workspace.pose),
                  instance.hasFiniteJointTransforms() else {
                _ = instance.writeConstraintPose(pose)
                instance.root.transform = originalRootTransform
                return record(.failed(
                    failure: .poseWriteRejected,
                    metrics: workspace.metrics
                ))
            }
            let error = measure(
                instance: instance,
                bindings: bindings,
                workspace: workspace,
                pelvisIndex: pelvisIndex,
                targets: targets,
                relativeTo: space
            )
            guard isUsable(error) else {
                _ = instance.writeConstraintPose(pose)
                instance.root.transform = originalRootTransform
                return record(.failed(
                    failure: .residualExceeded(error),
                    metrics: workspace.metrics
                ))
            }
            updateDebugMarkers(
                instance: instance,
                bindings: bindings,
                workspace: workspace,
                relativeTo: space
            )
            return record(.applied(error: error, metrics: workspace.metrics))
        } catch let failure as ReplayAthleteContactSolveFailure {
            instance.root.transform = originalRootTransform
            return record(.failed(failure: failure, metrics: failureMetrics))
        } catch {
            instance.root.transform = originalRootTransform
            return record(.failed(
                failure: .malformedHierarchy("unknown solve failure"),
                metrics: failureMetrics
            ))
        }
    }

    fileprivate static func makeBindings(
        instance: ReplayAthleteInstance,
        pose: SkeletalPose,
        topology: ReplayAthleteJointTopology
    ) throws -> [ReplayAthleteContactRole: ReplayAthleteContactBinding] {
        var bindings: [ReplayAthleteContactRole: ReplayAthleteContactBinding] = [:]
        for role in ReplayAthleteContactRole.allCases {
            guard let policy = ReplayAthleteContactPolicy(instance: instance, role: role) else {
                throw ReplayAthleteContactSolveFailure.missingContact(role)
            }
            guard let terminal = instance.jointIndex(named: policy.bone, in: pose) else {
                throw ReplayAthleteContactSolveFailure.missingJoint(role: role, bone: policy.bone)
            }
            guard let lower = topology.parent[terminal],
                  let upper = topology.parent[lower] else {
                throw ReplayAthleteContactSolveFailure.malformedHierarchy(
                    "contact chain too short for \(role.rawValue)"
                )
            }
            bindings[role] = .init(policy: policy, upper: upper, lower: lower, terminal: terminal)
        }
        return bindings
    }

    private static func alignPelvis(
        instance: ReplayAthleteInstance,
        workspace: ReplayAthleteMatrixWorkspace,
        pelvisIndex: Int,
        target: SIMD3<Float>,
        relativeTo space: Entity
    ) {
        let local = point(.zero, matrix: workspace.matrices[pelvisIndex])
        let current = instance.athleteEntity.convert(position: local, to: space)
        let rootPosition = instance.root.position(relativeTo: space)
        instance.root.setPosition(rootPosition + (target - current), relativeTo: space)
    }

    private static func solveLimb(
        binding: ReplayAthleteContactBinding,
        target: SIMD3<Float>,
        workspace: inout ReplayAthleteMatrixWorkspace
    ) throws {
        let root = point(.zero, matrix: workspace.matrices[binding.upper])
        let joint = point(.zero, matrix: workspace.matrices[binding.lower])
        let contact = point(binding.policy.offset, matrix: workspace.matrices[binding.terminal])
        let firstLength = length(joint - root)
        let secondLength = length(contact - joint)
        guard isFinite(root), isFinite(joint), isFinite(contact), isFinite(target),
              firstLength > 1e-5, secondLength > 1e-5 else {
            throw ReplayAthleteContactSolveFailure.degenerateLimb(binding.policy.role)
        }

        let solution = ReplayTwoBoneSolver.solve3D(
            root: double(root),
            target: double(target),
            firstLength: Double(firstLength),
            secondLength: Double(secondLength),
            bendHint: double(binding.policy.bendHint)
        )
        let desiredJoint = float(solution.joint)
        let desiredEnd = float(solution.end)
        guard isFinite(desiredJoint), isFinite(desiredEnd) else {
            throw ReplayAthleteContactSolveFailure.degenerateLimb(binding.policy.role)
        }

        try aimJoint(
            joint: binding.upper,
            sourceStart: root,
            sourceEnd: joint,
            targetEnd: desiredJoint,
            role: binding.policy.role,
            workspace: &workspace
        )
        let newJoint = point(.zero, matrix: workspace.matrices[binding.lower])
        let currentContact = point(binding.policy.offset, matrix: workspace.matrices[binding.terminal])
        try aimJoint(
            joint: binding.lower,
            sourceStart: newJoint,
            sourceEnd: currentContact,
            targetEnd: desiredEnd,
            role: binding.policy.role,
            workspace: &workspace
        )
        orientTerminal(binding: binding, workspace: &workspace)
    }

    private static func aimJoint(
        joint: Int,
        sourceStart: SIMD3<Float>,
        sourceEnd: SIMD3<Float>,
        targetEnd: SIMD3<Float>,
        role: ReplayAthleteContactRole,
        workspace: inout ReplayAthleteMatrixWorkspace
    ) throws {
        let source = sourceEnd - sourceStart
        let destination = targetEnd - sourceStart
        guard length(source) > 1e-5, length(destination) > 1e-5 else {
            throw ReplayAthleteContactSolveFailure.degenerateLimb(role)
        }
        let currentWorld = Transform(matrix: workspace.matrices[joint]).rotation
        let desiredWorld = rotation(from: source, to: destination) * currentWorld
        let parentWorld = workspace.topology.parent[joint].map {
            Transform(matrix: workspace.matrices[$0]).rotation
        } ?? identityQuaternion()
        workspace.setRotation(normalized(inverse(parentWorld) * desiredWorld), at: joint)
    }

    private static func orientTerminal(
        binding: ReplayAthleteContactBinding,
        workspace: inout ReplayAthleteMatrixWorkspace
    ) {
        let matrix = workspace.matrices[binding.terminal]
        let terminalPosition = point(.zero, matrix: matrix)
        let contactPosition = point(binding.policy.offset, matrix: matrix)
        let axis = contactPosition - terminalPosition
        guard length(axis) > 1e-5 else { return }
        let normal = normalize(axis)
        let currentWorld = Transform(matrix: matrix).rotation
        let currentUp = project(simd_act(currentWorld, SIMD3(0, 1, 0)), off: normal)
        let desiredUp = project(binding.policy.terminalUp, off: normal)
        guard length(currentUp) > 1e-5, length(desiredUp) > 1e-5 else { return }
        let from = normalize(currentUp)
        let to = normalize(desiredUp)
        let angle = atan2(simd_dot(normal, simd_cross(from, to)), simd_dot(from, to))
        let desiredWorld = simd_quatf(angle: angle, axis: normal) * currentWorld
        let parentWorld = workspace.topology.parent[binding.terminal].map {
            Transform(matrix: workspace.matrices[$0]).rotation
        } ?? identityQuaternion()
        workspace.setRotation(
            normalized(inverse(parentWorld) * desiredWorld),
            at: binding.terminal
        )
    }

    private static func measure(
        instance: ReplayAthleteInstance,
        bindings: [ReplayAthleteContactRole: ReplayAthleteContactBinding],
        workspace: ReplayAthleteMatrixWorkspace,
        pelvisIndex: Int,
        targets: ReplayAthleteContactTargets,
        relativeTo space: Entity
    ) -> ReplayAthleteContactError {
        func residual(_ role: ReplayAthleteContactRole) -> Float {
            let binding = bindings[role]!
            let local = point(binding.policy.offset, matrix: workspace.matrices[binding.terminal])
            let actual = instance.athleteEntity.convert(position: local, to: space)
            return distance(actual, targets[role])
        }
        let pelvisLocal = point(.zero, matrix: workspace.matrices[pelvisIndex])
        let pelvis = instance.athleteEntity.convert(position: pelvisLocal, to: space)
        return ReplayAthleteContactError(
            leftHand: residual(.leftHand),
            rightHand: residual(.rightHand),
            leftFoot: residual(.leftFoot),
            rightFoot: residual(.rightFoot),
            pelvis: distance(pelvis, targets.pelvis)
        )
    }

    private static func updateDebugMarkers(
        instance: ReplayAthleteInstance,
        bindings: [ReplayAthleteContactRole: ReplayAthleteContactBinding],
        workspace: ReplayAthleteMatrixWorkspace,
        relativeTo space: Entity
    ) {
        for role in ReplayAthleteContactRole.allCases {
            let binding = bindings[role]!
            let local = point(binding.policy.offset, matrix: workspace.matrices[binding.terminal])
            let position = instance.athleteEntity.convert(position: local, to: space)
            instance.setContactDebugMarker(
                role: role,
                position: position,
                relativeTo: space
            )
        }
    }

    private static func record(_ result: ReplayAthleteContactSolveResult) -> ReplayAthleteContactSolveResult {
        lastMetricsForTesting = result.metrics
        lastResultForTesting = result
        return result
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

    private static func distance(_ point: SIMD3<Float>, _ target: SIMD3<Float>) -> Float {
        let result = length(point - target)
        return result.isFinite ? result : .infinity
    }

    private static func isFinite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
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
