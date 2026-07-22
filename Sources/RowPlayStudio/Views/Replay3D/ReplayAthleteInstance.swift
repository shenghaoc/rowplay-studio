import AppKit
import Foundation
import RealityKit
import RowPlayCore
import simd

/// Immutable loaded V4 athlete template.
///
/// The template entity never enters a live scene. Callers receive independent
/// clones so live and rival athletes cannot share skeleton, material, or
/// animation controller state.
@MainActor
final class ReplayAthleteTemplate {
    let contract: ReplayAthleteContract
    let sourceManifest: ReplayAthleteSourceManifest
    let jointNames: [String]

    private let rootTemplate: Entity
    private let animationResources: [Sport: AnimationResource]

    init?(
        root: Entity,
        contract: ReplayAthleteContract,
        sourceManifest: ReplayAthleteSourceManifest
    ) {
        guard let athlete = root.findEntity(named: ReplayAthleteCatalog.skinnedMeshName)
                ?? root.replayDescendant(named: ReplayAthleteCatalog.skinnedMeshName) else {
            return nil
        }
        guard athlete.components[ModelComponent.self] != nil else {
            return nil
        }
        guard let poses = athlete.components[SkeletalPosesComponent.self],
              let pose = poses.poses.first else {
            return nil
        }
        let names = pose.jointNames
        guard names.count == ReplayAthleteCatalog.orderedJointPaths.count,
              names == ReplayAthleteCatalog.orderedJointPaths else {
            return nil
        }
        for transform in pose.jointTransforms {
            let t = transform.translation
            let r = transform.rotation.vector
            let s = transform.scale
            let finite =
                t.x.isFinite && t.y.isFinite && t.z.isFinite
                && r.x.isFinite && r.y.isFinite && r.z.isFinite && r.w.isFinite
                && s.x.isFinite && s.y.isFinite && s.z.isFinite
            if !finite {
                return nil
            }
        }

        // A valid package needs exactly one resource for every contract sport.
        // The current merged USDZ fails this gate, which intentionally selects
        // atomic procedural fallback; arbitrarily choosing one authored clip
        // would silently animate Ski/Bike with the row resource.
        var resources: [Sport: AnimationResource] = [:]
        for clip in contract.clips {
            let matches = root.availableAnimations.filter { $0.name == clip.name }
            guard matches.count == 1 else {
                return nil
            }
            resources[clip.sport] = matches[0]
        }
        guard resources.count == 3 else {
            return nil
        }

        // Disable any authored light so native lighting remains authoritative.
        if let light = root.findEntity(named: "env_light") {
            light.isEnabled = false
        }

        self.contract = contract
        self.sourceManifest = sourceManifest
        self.jointNames = names
        self.rootTemplate = root
        self.animationResources = resources
        rootTemplate.isEnabled = false
    }

    func makeInstance(
        sport: Sport,
        name: String,
        isRival: Bool
    ) -> ReplayAthleteInstance? {
        guard let animationResource = animationResources[sport] else { return nil }
        let clone = rootTemplate.clone(recursive: true)
        clone.name = name
        clone.isEnabled = true
        if let light = clone.findEntity(named: "env_light") {
            light.removeFromParent()
        }
        guard let athlete = clone.findEntity(named: ReplayAthleteCatalog.skinnedMeshName)
                ?? clone.replayDescendant(named: ReplayAthleteCatalog.skinnedMeshName) else {
            return nil
        }
        let instance = ReplayAthleteInstance(
            root: clone,
            athleteEntity: athlete,
            contract: contract,
            jointNames: jointNames,
            sport: sport,
            animationResource: animationResource
        )
        if isRival {
            instance.applyRivalBodyStyle()
        }
        return instance
    }
}

/// Independent live or rival V4 athlete instance.
@MainActor
final class ReplayAthleteInstance {
    let root: Entity
    let athleteEntity: Entity
    let contract: ReplayAthleteContract
    let jointNames: [String]
    let sport: Sport
    let selectedClipName: String

    private let animationResource: AnimationResource
    private var playbackController: AnimationPlaybackController?
    private var lastSampledFraction: Double?
    private var baseRootTransform: Transform?
    private var constraintPose: SkeletalPose?

    let leftHandContact: Entity?
    let rightHandContact: Entity?
    let leftFootContact: Entity?
    let rightFootContact: Entity?

    fileprivate init(
        root: Entity,
        athleteEntity: Entity,
        contract: ReplayAthleteContract,
        jointNames: [String],
        sport: Sport,
        animationResource: AnimationResource
    ) {
        self.root = root
        self.athleteEntity = athleteEntity
        self.contract = contract
        self.jointNames = jointNames
        self.sport = sport
        self.selectedClipName = animationResource.name ?? ""
        self.animationResource = animationResource
        self.leftHandContact = root.findEntity(named: "v4LeftHandContact")
            ?? root.replayDescendant(named: "v4LeftHandContact")
        self.rightHandContact = root.findEntity(named: "v4RightHandContact")
            ?? root.replayDescendant(named: "v4RightHandContact")
        self.leftFootContact = root.findEntity(named: "v4LeftFootContact")
            ?? root.replayDescendant(named: "v4LeftFootContact")
        self.rightFootContact = root.findEntity(named: "v4RightFootContact")
            ?? root.replayDescendant(named: "v4RightFootContact")

        // Stable names used by contact tests and equipment solvers.
        leftHandContact?.name = "hand-L"
        rightHandContact?.name = "hand-R"
        leftFootContact?.name = "foot-L"
        rightFootContact?.name = "foot-R"
    }

    func attach(to parent: Entity) {
        parent.addChild(root)
        ensurePlaybackController()
    }

    /// Capture the configured rig placement after its parent has been chosen.
    /// A contact pass restores this exact authored placement before applying
    /// the current phase, preventing state from one seek leaking into another.
    func captureBaseRootTransform() {
        baseRootTransform = root.transform
    }

    /// Seek the authored animation to a normalized clip fraction in [0, 1).
    ///
    /// Playback speed is always zero so the native replay clock owns time.
    func seek(toClipFraction fraction: Double) {
        let clamped = ReplayAthleteCatalog.wrapUnit(fraction)
        ensurePlaybackController()
        guard let controller = playbackController else {
            return
        }
        let duration = max(animationResource.definition.duration, 1e-4)
        controller.speed = 0
        controller.time = clamped * duration
        lastSampledFraction = clamped
        constraintPose = nil
    }

    func stopAnimation() {
        root.stopAllAnimations(recursive: true)
        playbackController = nil
        lastSampledFraction = nil
        constraintPose = nil
    }

    /// The V4 body stays in the opaque depth-writing pass. Transparent skin
    /// sorting causes visible torso/limb seams, so rival identity is a cool
    /// tint rather than generic ghost translucency.
    func applyRivalBodyStyle() {
        applyRivalBodyStyle(to: athleteEntity)
    }

    func hasFiniteJointTransforms() -> Bool {
        guard let poses = athleteEntity.components[SkeletalPosesComponent.self],
              let pose = poses.poses.first else {
            return false
        }
        for transform in pose.jointTransforms {
            let t = transform.translation
            let r = transform.rotation.vector
            let s = transform.scale
            if !(t.x.isFinite && t.y.isFinite && t.z.isFinite
                && r.x.isFinite && r.y.isFinite && r.z.isFinite && r.w.isFinite
                && s.x.isFinite && s.y.isFinite && s.z.isFinite) {
                return false
            }
        }
        return true
    }

    func contactEntity(role: String) -> Entity? {
        switch role {
        case "left-hand": leftHandContact
        case "right-hand": rightHandContact
        case "left-foot": leftFootContact
        case "right-foot": rightFootContact
        default: nil
        }
    }

    /// Begin one deterministic skeletal correction pass from the authored clip
    /// sample. The caller must use `prepare → orientHandsToTargets → constrain`
    /// in a single frame.
    func beginConstraintPass() -> Bool {
        if baseRootTransform == nil {
            baseRootTransform = root.transform
        }
        if let baseRootTransform {
            root.transform = baseRootTransform
        }
        guard let component = athleteEntity.components[SkeletalPosesComponent.self],
              let pose = component.poses.default ?? component.poses.first else {
            constraintPose = nil
            return false
        }
        constraintPose = pose
        return true
    }

    func currentConstraintPose() -> SkeletalPose? {
        if let constraintPose {
            return constraintPose
        }
        guard let component = athleteEntity.components[SkeletalPosesComponent.self] else {
            return nil
        }
        return component.poses.default ?? component.poses.first
    }

    func writeConstraintPose(_ pose: SkeletalPose) {
        guard var component = athleteEntity.components[SkeletalPosesComponent.self] else {
            return
        }
        component.poses.default = pose
        athleteEntity.components.set(component)
        constraintPose = pose
    }

    func contactSpec(role: String) -> ReplayAthleteContactSpec? {
        contract.contacts.first { $0.role == role }
    }

    func jointIndex(named bone: String, in pose: SkeletalPose) -> Int? {
        if let exact = pose.jointNames.firstIndex(of: bone) {
            return exact
        }
        return pose.jointNames.firstIndex { $0.split(separator: "/").last == Substring(bone) }
    }

    func skeletalContactPosition(role: String, relativeTo space: Entity) -> SIMD3<Float>? {
        guard let pose = currentConstraintPose(),
              let spec = contactSpec(role: role),
              let index = jointIndex(named: spec.bone, in: pose) else {
            return nil
        }
        let matrices = skeletalJointMatrices(for: pose)
        guard matrices.indices.contains(index) else { return nil }
        let offset = SIMD3<Float>(
            Float(spec.localOffset.x),
            Float(spec.localOffset.y),
            Float(spec.localOffset.z)
        )
        let local = ReplayAthleteInstance.point(offset, transformedBy: matrices[index])
        return athleteEntity.convert(position: local, to: space)
    }

    func skeletalJointPosition(named bone: String, relativeTo space: Entity) -> SIMD3<Float>? {
        guard let pose = currentConstraintPose(), let index = jointIndex(named: bone, in: pose) else {
            return nil
        }
        let matrices = skeletalJointMatrices(for: pose)
        guard matrices.indices.contains(index) else { return nil }
        return athleteEntity.convert(position: ReplayAthleteInstance.point(.zero, transformedBy: matrices[index]), to: space)
    }

    func skeletalJointMatrices(for pose: SkeletalPose) -> [simd_float4x4] {
        guard pose.jointNames.count == pose.jointTransforms.count else { return [] }
        var indexByPath: [String: Int] = [:]
        for (index, name) in pose.jointNames.enumerated() {
            indexByPath[name] = index
        }
        var matrices = Array(repeating: matrix_identity_float4x4, count: pose.jointNames.count)
        for index in pose.jointNames.indices {
            let path = pose.jointNames[index]
            let local = pose.jointTransforms[index].matrix
            if let slash = path.lastIndex(of: "/"),
               let parent = indexByPath[String(path[..<slash])],
               matrices.indices.contains(parent) {
                matrices[index] = matrices[parent] * local
            } else {
                matrices[index] = local
            }
        }
        return matrices
    }

    func setContactDebugMarker(role: String, position: SIMD3<Float>, relativeTo space: Entity) {
        // Markers mirror the solved skeletal contact for diagnostics/tests;
        // they are never snapped to equipment targets.
        contactEntity(role: role)?.setPosition(position, relativeTo: space)
    }

    private func ensurePlaybackController() {
        guard playbackController == nil else {
            return
        }
        let controller = root.playAnimation(animationResource.repeat())
        controller.speed = 0
        playbackController = controller
    }

    private static func point(_ position: SIMD3<Float>, transformedBy matrix: simd_float4x4) -> SIMD3<Float> {
        let value = matrix * SIMD4(position.x, position.y, position.z, 1)
        guard value.x.isFinite, value.y.isFinite, value.z.isFinite, value.w.isFinite,
              abs(value.w) > 1e-6 else {
            return .zero
        }
        return SIMD3(value.x, value.y, value.z) / value.w
    }

    private func applyRivalBodyStyle(to entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            let tint = NSColor(calibratedRed: 0.52, green: 0.46, blue: 0.86, alpha: 1)
            model.materials = model.materials.map { material in
                if var pbr = material as? PhysicallyBasedMaterial {
                    pbr.baseColor.tint = tint
                    pbr.blending = .opaque
                    return pbr
                }
                if var simple = material as? SimpleMaterial {
                    simple.color.tint = tint
                    return simple
                }
                if var unlit = material as? UnlitMaterial {
                    unlit.color.tint = tint
                    return unlit
                }
                return material
            }
            entity.components.set(model)
        }
        for child in entity.children {
            applyRivalBodyStyle(to: child)
        }
    }
}
