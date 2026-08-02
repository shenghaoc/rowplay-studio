import AppKit
import Foundation
import RealityKit
import RowPlayCore
import simd

/// Immutable loaded production-athlete template.
///
/// The template entity never enters a live scene.  Callers receive
/// independent clones so live and rival athletes cannot share skeleton,
/// material, grip, or motion state.  The authored base motion comes from the
/// bundled `rowplay-motion.bin` table — never from
/// `Entity.availableAnimations`, whose clip names RealityKit does not
/// guarantee to preserve across USDZ conversion.
@MainActor
final class ReplayAthleteTemplate {
    let contract: ReplayAthleteContract
    let sourceManifest: ReplayAthleteSourceManifest
    let motionTable: ReplayAthleteMotionTable
    let jointNames: [String]

    /// Skeleton joint index for each motion-table bone, in table order.
    let semanticJointIndices: [Int]
    /// Skeleton joint index for each contract helper, in contract order.
    let helperJointIndices: [Int]
    /// Bind pose captured from the loaded asset.
    let restTransforms: [Transform]

    private let rootTemplate: Entity

    init?(
        root: Entity,
        contract: ReplayAthleteContract,
        sourceManifest: ReplayAthleteSourceManifest,
        motionTable: ReplayAthleteMotionTable
    ) {
        guard let athlete = root.findEntity(named: ReplayAthleteCatalog.skinnedMeshName)
                ?? root.replayDescendant(named: ReplayAthleteCatalog.skinnedMeshName) else {
            return nil
        }
        guard athlete.components[ModelComponent.self] != nil else {
            return nil
        }
        guard let poses = athlete.components[SkeletalPosesComponent.self],
              let pose = poses.poses.default ?? poses.poses.first else {
            return nil
        }
        let names = pose.jointNames
        guard names.count == pose.jointTransforms.count else {
            return nil
        }

        // Index every joint by its leaf bone name; the full hierarchy path is
        // an asset-conversion detail the contract does not own.
        var indexByLeafName: [String: Int] = [:]
        for (index, path) in names.enumerated() {
            let leaf = path.split(separator: "/").last.map(String.init) ?? path
            // First occurrence wins; a duplicated leaf name is a contract
            // violation caught below.
            if indexByLeafName[leaf] != nil {
                return nil
            }
            indexByLeafName[leaf] = index
        }

        // The loaded skeleton must expose the exact semantic and helper
        // hierarchy the live contract declares.
        var semanticIndices: [Int] = []
        semanticIndices.reserveCapacity(motionTable.boneNames.count)
        for bone in motionTable.boneNames {
            guard let index = indexByLeafName[bone] else {
                return nil
            }
            semanticIndices.append(index)
        }
        guard motionTable.boneNames == contract.semanticBoneNames else {
            return nil
        }
        var helperIndices: [Int] = []
        helperIndices.reserveCapacity(contract.helpers.count)
        for helper in contract.helpers {
            guard let index = indexByLeafName[helper.name] else {
                return nil
            }
            helperIndices.append(index)
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

        // Disable any authored light so native lighting remains authoritative.
        if let light = root.findEntity(named: "env_light") {
            light.isEnabled = false
        }

        self.contract = contract
        self.sourceManifest = sourceManifest
        self.motionTable = motionTable
        self.jointNames = names
        self.semanticJointIndices = semanticIndices
        self.helperJointIndices = helperIndices
        self.restTransforms = Array(pose.jointTransforms)
        self.rootTemplate = root
        rootTemplate.isEnabled = false
    }

    func makeInstance(
        sport: Sport,
        name: String,
        isRival: Bool
    ) -> ReplayAthleteInstance? {
        guard motionTable.clips[sport] != nil else { return nil }
        guard let gripController = ReplayAthleteGripController(
            contract: contract,
            sport: sport
        ) else {
            return nil
        }
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
            template: self,
            sport: sport,
            gripController: gripController
        )
        instance.applyBodyStyle(isRival: isRival)
        return instance
    }
}

/// Independent live or rival production-athlete instance driven by the
/// sampled motion table.
@MainActor
final class ReplayAthleteInstance {
    let root: Entity
    let athleteEntity: Entity
    let contract: ReplayAthleteContract
    let jointNames: [String]
    let sport: Sport
    let selectedClipName: String
    let gripController: ReplayAthleteGripController

    private let template: ReplayAthleteTemplate
    private var baseRootTransform: Transform?
    private var constraintPose: SkeletalPose?

    /// Reusable per-seek buffers — no allocation on the sample path.
    private var sampleBuffer: [ReplayAthleteBoneTransform]
    private var workingTransforms: [Transform]

    let leftHandContact: Entity?
    let rightHandContact: Entity?
    let leftFootContact: Entity?
    let rightFootContact: Entity?

    fileprivate init(
        root: Entity,
        athleteEntity: Entity,
        template: ReplayAthleteTemplate,
        sport: Sport,
        gripController: ReplayAthleteGripController
    ) {
        self.root = root
        self.athleteEntity = athleteEntity
        self.template = template
        self.contract = template.contract
        self.jointNames = template.jointNames
        self.sport = sport
        self.selectedClipName = template.contract.clip(for: sport)?.name ?? ""
        self.gripController = gripController
        self.sampleBuffer = Array(
            repeating: ReplayAthleteBoneTransform(),
            count: template.motionTable.boneNames.count
        )

        // Working pose starts at bind; helper joints are pre-composed with
        // the install-time grip closure once — per frame only the semantic
        // bones are rewritten from the motion table.
        var transforms = template.restTransforms
        for (offset, helper) in template.contract.helpers.enumerated() {
            let jointIndex = template.helperJointIndices[offset]
            if let solved = gripController.solvedRotation(forHelper: helper.name) {
                var transform = transforms[jointIndex]
                transform.rotation = solved
                transforms[jointIndex] = transform
            }
        }
        self.workingTransforms = transforms

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
    }

    /// Capture the configured rig placement after its parent has been chosen.
    /// A contact pass restores this exact authored placement before applying
    /// the current phase, preventing state from one seek leaking into another.
    func captureBaseRootTransform() {
        baseRootTransform = root.transform
    }

    /// Seek the authored base motion to a normalized clip fraction in [0, 1).
    ///
    /// The pose is rebuilt from the bind pose plus the sampled table every
    /// seek — direct and shuffled seeks are deterministic by construction, and
    /// no state from a previous frame can accumulate.  Digit-closure helper
    /// rotations were composed once at install and ride their corrected hand
    /// parents.
    func seek(toClipFraction fraction: Double) {
        template.motionTable.sample(sport: sport, fraction: fraction, into: &sampleBuffer)
        for (tableIndex, jointIndex) in template.semanticJointIndices.enumerated() {
            let sampled = sampleBuffer[tableIndex]
            let scale = SIMD3<Float>(
                Float(sampled.scale.x),
                Float(sampled.scale.y),
                Float(sampled.scale.z)
            )
            let rotation = simd_quatf(
                ix: Float(sampled.rotation.x),
                iy: Float(sampled.rotation.y),
                iz: Float(sampled.rotation.z),
                r: Float(sampled.rotation.w)
            )
            let translation = SIMD3<Float>(
                Float(sampled.translation.x),
                Float(sampled.translation.y),
                Float(sampled.translation.z)
            )
            workingTransforms[jointIndex] = Transform(
                scale: scale,
                rotation: rotation,
                translation: translation
            )
        }
        writePose(transforms: workingTransforms)
        constraintPose = nil
    }

    func stopAnimation() {
        constraintPose = nil
    }

    /// The production body stays in the opaque depth-writing pass.
    /// Transparent skin sorting causes visible torso/limb seams, so identity
    /// is a restrained cool tint over the authored surface, never alpha: the
    /// rival blends 34% toward the ghost teal, the live athlete 14% toward
    /// the live violet — the merged RowPlay `styleInstance` constants.
    func applyBodyStyle(isRival: Bool) {
        let tint: NSColor
        if isRival {
            tint = Self.blendTowardWhite(red: 0x17, green: 0x6b, blue: 0x8c, amount: 0.34)
        } else {
            tint = Self.blendTowardWhite(red: 0x52, green: 0x40, blue: 0xce, amount: 0.14)
        }
        applyBodyTint(tint, to: athleteEntity)
    }

    private static func blendTowardWhite(red: Int, green: Int, blue: Int, amount: Double) -> NSColor {
        NSColor(
            calibratedRed: 1 - amount + amount * Double(red) / 255,
            green: 1 - amount + amount * Double(green) / 255,
            blue: 1 - amount + amount * Double(blue) / 255,
            alpha: 1
        )
    }

    func hasFiniteJointTransforms() -> Bool {
        guard let poses = athleteEntity.components[SkeletalPosesComponent.self],
              let pose = poses.poses.default ?? poses.poses.first else {
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

    /// Begin one deterministic skeletal correction pass from the sampled base
    /// pose.  The caller must use `prepare → orient → constrain` in a single
    /// frame.
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

    private func writePose(transforms: [Transform]) {
        guard var component = athleteEntity.components[SkeletalPosesComponent.self],
              var pose = component.poses.default ?? component.poses.first,
              pose.jointTransforms.count == transforms.count else {
            return
        }
        for index in transforms.indices {
            pose.jointTransforms[index] = transforms[index]
        }
        component.poses.default = pose
        athleteEntity.components.set(component)
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
        // The authored palm-surface contact is replaced with the sport's
        // grip-channel centre for hands, so the contact solver drives the
        // enclosed channel — not the skin — onto the equipment axis.
        let offset: SIMD3<Float>
        if spec.role == "left-hand" || spec.role == "right-hand" {
            let side: Double = spec.role == "left-hand" ? -1 : 1
            let channel = ReplayAthleteGripController.effectorOffset(for: sport, side: side)
            offset = SIMD3(Float(channel.x), Float(channel.y), Float(channel.z))
        } else {
            offset = SIMD3(
                Float(spec.localOffset.x),
                Float(spec.localOffset.y),
                Float(spec.localOffset.z)
            )
        }
        let local = ReplayAthleteInstance.point(offset, transformedBy: matrices[index])
        return athleteEntity.convert(position: local, to: space)
    }

    func skeletalJointPosition(named bone: String, relativeTo space: Entity) -> SIMD3<Float>? {
        guard let pose = currentConstraintPose(), let index = jointIndex(named: bone, in: pose) else {
            return nil
        }
        let matrices = skeletalJointMatrices(for: pose)
        guard matrices.indices.contains(index) else { return nil }
        return athleteEntity.convert(
            position: ReplayAthleteInstance.point(.zero, transformedBy: matrices[index]),
            to: space
        )
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

    private static func point(_ position: SIMD3<Float>, transformedBy matrix: simd_float4x4) -> SIMD3<Float> {
        let value = matrix * SIMD4(position.x, position.y, position.z, 1)
        guard value.x.isFinite, value.y.isFinite, value.z.isFinite, value.w.isFinite,
              abs(value.w) > 1e-6 else {
            return .zero
        }
        return SIMD3(value.x, value.y, value.z) / value.w
    }

    private func applyBodyTint(_ tint: NSColor, to entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
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
            applyBodyTint(tint, to: child)
        }
    }
}
