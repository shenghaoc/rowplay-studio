import AppKit
import Foundation
import RealityKit
import RowPlayCore
import simd

struct ReplayAthleteTemplateBinding {
    let jointNames: [String]
    let semanticJointIndices: [Int]
    let helperJointIndices: [Int]
    let restTransforms: [Transform]
}

enum ReplayAthleteTemplateValidator {
    static func validate(
        contract: ReplayAthleteContract,
        motionBoneNames: [String],
        jointNames: [String],
        jointTransforms: [Transform],
        availableContactRoleCounts: [ReplayAthleteContactRole: Int]
    ) -> Result<ReplayAthleteTemplateBinding, ReplayAthleteValidationFailure> {
        guard jointNames.count == jointTransforms.count else {
            return .failure(
                .jointCountMismatch(actual: jointTransforms.count, expected: jointNames.count)
            )
        }
        guard motionBoneNames == contract.semanticBoneNames else {
            return .failure(.invalidMotionManifest("boneNames"))
        }

        var indexByLeafName: [String: Int] = [:]
        for (index, path) in jointNames.enumerated() {
            let leaf = path.split(separator: "/").last.map(String.init) ?? path
            guard indexByLeafName[leaf] == nil else {
                return .failure(.duplicateBone(leaf))
            }
            indexByLeafName[leaf] = index
            guard isFinite(jointTransforms[index]) else {
                return .failure(.nonFiniteJointTransform(leaf))
            }
        }

        var semanticIndices: [Int] = []
        semanticIndices.reserveCapacity(motionBoneNames.count)
        for bone in motionBoneNames {
            guard let index = indexByLeafName[bone] else {
                return .failure(.missingBone(bone))
            }
            semanticIndices.append(index)
        }
        var helperIndices: [Int] = []
        helperIndices.reserveCapacity(contract.helpers.count)
        for helper in contract.helpers {
            guard let index = indexByLeafName[helper.name] else {
                return .failure(.missingBone(helper.name))
            }
            helperIndices.append(index)
        }

        for role in ReplayAthleteContactRole.allCases {
            let markerCount = availableContactRoleCounts[role, default: 0]
            guard markerCount > 0 else {
                return .failure(.missingContact(role.rawValue))
            }
            guard markerCount == 1 else {
                return .failure(.duplicateContact(role.rawValue))
            }
            guard let contact = contract.contacts.first(where: { $0.role == role }),
                  indexByLeafName[contact.bone] != nil else {
                return .failure(.missingBone(
                    contract.contacts.first(where: { $0.role == role })?.bone ?? role.rawValue
                ))
            }
        }

        return .success(ReplayAthleteTemplateBinding(
            jointNames: jointNames,
            semanticJointIndices: semanticIndices,
            helperJointIndices: helperIndices,
            restTransforms: jointTransforms
        ))
    }

    private static func isFinite(_ transform: Transform) -> Bool {
        let translation = transform.translation
        let rotation = transform.rotation.vector
        let scale = transform.scale
        return translation.x.isFinite && translation.y.isFinite && translation.z.isFinite
            && rotation.x.isFinite && rotation.y.isFinite
            && rotation.z.isFinite && rotation.w.isFinite
            && scale.x.isFinite && scale.y.isFinite && scale.z.isFinite
    }
}

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
    let nativeManifest: ReplayAthleteNativeManifest
    let motionTable: ReplayAthleteMotionTable
    let jointNames: [String]

    /// Skeleton joint index for each motion-table bone, in table order.
    let semanticJointIndices: [Int]
    /// Skeleton joint index for each contract helper, in contract order.
    let helperJointIndices: [Int]
    /// Bind pose captured from the loaded asset.
    let restTransforms: [Transform]

    private let rootTemplate: Entity

    init(
        root: Entity,
        contract: ReplayAthleteContract,
        sourceManifest: ReplayAthleteSourceManifest,
        nativeManifest: ReplayAthleteNativeManifest,
        motionTable: ReplayAthleteMotionTable
    ) throws {
        guard let athlete = root.findEntity(named: contract.meshName)
                ?? root.replayDescendant(named: contract.meshName) else {
            throw ReplayAthleteValidationFailure.missingSkinnedAthlete
        }
        guard let model = athlete.components[ModelComponent.self] else {
            throw ReplayAthleteValidationFailure.missingModelComponent
        }
        guard model.materials.count == nativeManifest.materialSlotCount else {
            throw ReplayAthleteValidationFailure.surfaceCountMismatch(
                actual: model.materials.count,
                expected: nativeManifest.materialSlotCount
            )
        }
        guard let poses = athlete.components[SkeletalPosesComponent.self],
              let pose = poses.poses.default ?? poses.poses.first else {
            throw ReplayAthleteValidationFailure.missingSkeletalPose
        }

        let availableContactRoleCounts = Dictionary(uniqueKeysWithValues:
            ReplayAthleteCatalog.contactEntityNames.map { role, name in
                (role, Self.entityCount(named: name, in: root))
            }
        )
        let binding: ReplayAthleteTemplateBinding
        switch ReplayAthleteTemplateValidator.validate(
            contract: contract,
            motionBoneNames: motionTable.boneNames,
            jointNames: pose.jointNames,
            jointTransforms: Array(pose.jointTransforms),
            availableContactRoleCounts: availableContactRoleCounts
        ) {
        case .success(let validated):
            binding = validated
        case .failure(let failure):
            throw failure
        }

        // Disable any authored light so native lighting remains authoritative.
        if let light = root.findEntity(named: "env_light") {
            light.isEnabled = false
        }

        self.contract = contract
        self.sourceManifest = sourceManifest
        self.nativeManifest = nativeManifest
        self.motionTable = motionTable
        self.jointNames = binding.jointNames
        self.semanticJointIndices = binding.semanticJointIndices
        self.helperJointIndices = binding.helperJointIndices
        self.restTransforms = binding.restTransforms
        self.rootTemplate = root
        rootTemplate.isEnabled = false
    }

    private static func entityCount(named name: String, in entity: Entity) -> Int {
        let localCount = entity.name == name ? 1 : 0
        return localCount + entity.children.reduce(into: 0) { count, child in
            count += entityCount(named: name, in: child)
        }
    }

    func makeInstance(
        sport: Sport,
        name: String,
        isRival: Bool,
        quality: ReplayRenderQuality,
        detailMaps: [ReplayAthleteSurfaceRole: TextureResource]
    ) -> ReplayAthleteInstance? {
        guard motionTable.clips[sport] != nil,
              let selectedClipName = contract.clip(for: sport)?.name,
              let gripController = ReplayAthleteGripController(
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
        guard let athlete = clone.findEntity(named: contract.meshName)
                ?? clone.replayDescendant(named: contract.meshName) else {
            return nil
        }
        let instance = ReplayAthleteInstance(
            root: clone,
            athleteEntity: athlete,
            template: self,
            sport: sport,
            selectedClipName: selectedClipName,
            quality: quality,
            gripController: gripController
        )
        guard instance.applyBodyStyle(isRival: isRival, detailMaps: detailMaps) else {
            return nil
        }
        return instance
    }

    /// Convenience for callers that are already async and have not resolved the
    /// tier's detail maps. The synchronous scene build uses the prewarmed cache
    /// instead, so this never runs inside RealityView's `make` closure.
    func makeInstance(
        sport: Sport,
        name: String,
        isRival: Bool,
        quality: ReplayRenderQuality
    ) async -> ReplayAthleteInstance? {
        guard let detailMaps = await ReplayAthleteMaterialLibrary.shared.detailMaps(
            for: quality
        ) else { return nil }
        return makeInstance(
            sport: sport,
            name: name,
            isRival: isRival,
            quality: quality,
            detailMaps: detailMaps
        )
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
    let quality: ReplayRenderQuality
    let surfaceRoles: [ReplayAthleteSurfaceRole]
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
        selectedClipName: String,
        quality: ReplayRenderQuality,
        gripController: ReplayAthleteGripController
    ) {
        self.root = root
        self.athleteEntity = athleteEntity
        self.template = template
        self.contract = template.contract
        self.jointNames = template.jointNames
        self.sport = sport
        self.selectedClipName = selectedClipName
        self.quality = quality
        self.surfaceRoles = template.nativeManifest.surfaceRoles
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

        func contactEntity(for role: ReplayAthleteContactRole) -> Entity? {
            guard let name = ReplayAthleteCatalog.contactEntityNames[role] else { return nil }
            return root.findEntity(named: name) ?? root.replayDescendant(named: name)
        }
        self.leftHandContact = contactEntity(for: .leftHand)
        self.rightHandContact = contactEntity(for: .rightHand)
        self.leftFootContact = contactEntity(for: .leftFoot)
        self.rightFootContact = contactEntity(for: .rightFoot)

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
    @discardableResult
    func seek(toClipFraction fraction: Double) -> Bool {
        guard template.motionTable.sample(
            sport: sport,
            fraction: fraction,
            into: &sampleBuffer
        ) else {
            constraintPose = nil
            return false
        }
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
        guard writePose(transforms: workingTransforms) else { return false }
        constraintPose = nil
        return true
    }

    func stopAnimation() {
        constraintPose = nil
    }

    /// The production body stays in the opaque depth-writing pass.
    /// Transparent skin sorting causes visible torso/limb seams, so identity
    /// is a restrained cool tint over the authored surface, never alpha: the
    /// rival blends 34% toward the ghost teal, the live athlete 14% toward
    /// the live violet — the merged RowPlay `styleInstance` constants.
    @discardableResult
    func applyBodyStyle(
        isRival: Bool,
        detailMaps: [ReplayAthleteSurfaceRole: TextureResource]
    ) -> Bool {
        let tint: NSColor
        if isRival {
            tint = Self.blendTowardWhite(red: 0x17, green: 0x6b, blue: 0x8c, amount: 0.34)
        } else {
            tint = Self.blendTowardWhite(red: 0x52, green: 0x40, blue: 0xce, amount: 0.14)
        }
        guard var model = athleteEntity.components[ModelComponent.self],
              model.materials.count == surfaceRoles.count else {
            return false
        }
        var materials: [any Material] = []
        materials.reserveCapacity(surfaceRoles.count)
        for role in surfaceRoles {
            let profile = ReplayAthleteMaterialProfile.profile(for: role, quality: quality)
            var material = PhysicallyBasedMaterial()
            material.baseColor.tint = Self.multipliedColor(
                ReplayAthleteMaterialProfile.baseColor(for: role),
                by: tint
            )
            material.roughness = .init(scale: profile.roughness)
            material.metallic = .init(scale: profile.metallic)
            material.clearcoat = .init(scale: profile.clearcoat)
            material.clearcoatRoughness = .init(scale: profile.clearcoatRoughness)
            material.specular = .init(scale: profile.specular)
            material.anisotropyLevel = .init(scale: profile.anisotropy)
            material.blending = .opaque
            if let texture = detailMaps[role] {
                material.normal = .init(texture: ReplayAthleteMaterialProfile.normalTexture(
                    resource: texture,
                    role: role
                ))
                material.textureCoordinateTransform = .init(
                    scale: ReplayAthleteMaterialProfile.detailRepeat(for: role)
                )
            }
            materials.append(material)
        }
        model.materials = materials
        athleteEntity.components.set(model)
        return true
    }

    private static func blendTowardWhite(red: Int, green: Int, blue: Int, amount: Double) -> NSColor {
        NSColor(
            calibratedRed: 1 - amount + amount * Double(red) / 255,
            green: 1 - amount + amount * Double(green) / 255,
            blue: 1 - amount + amount * Double(blue) / 255,
            alpha: 1
        )
    }

    private static func multipliedColor(_ base: NSColor, by tint: NSColor) -> NSColor {
        guard let base = base.usingColorSpace(.deviceRGB),
              let tint = tint.usingColorSpace(.deviceRGB) else {
            return base
        }
        return NSColor(
            calibratedRed: base.redComponent * tint.redComponent,
            green: base.greenComponent * tint.greenComponent,
            blue: base.blueComponent * tint.blueComponent,
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

    func contactEntity(role: ReplayAthleteContactRole) -> Entity? {
        switch role {
        case .leftHand: leftHandContact
        case .rightHand: rightHandContact
        case .leftFoot: leftFootContact
        case .rightFoot: rightFootContact
        }
    }

    /// Begin one deterministic skeletal correction pass from the sampled base
    /// pose. The per-frame order is `seek → beginConstraintPass →
    /// solve/write`. Constraint transforms are intentionally ephemeral:
    /// `seek` always rebuilds from the sampled table and bind helpers, so a
    /// shuffled seek cannot accumulate an earlier frame's correction.
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

    @discardableResult
    func writeConstraintPose(_ pose: SkeletalPose) -> Bool {
        guard var component = athleteEntity.components[SkeletalPosesComponent.self] else {
            return false
        }
        component.poses.default = pose
        athleteEntity.components.set(component)
        constraintPose = pose
        return true
    }

    @discardableResult
    private func writePose(transforms: [Transform]) -> Bool {
        guard var component = athleteEntity.components[SkeletalPosesComponent.self],
              var pose = component.poses.default ?? component.poses.first,
              pose.jointTransforms.count == transforms.count else {
            return false
        }
        for index in transforms.indices {
            pose.jointTransforms[index] = transforms[index]
        }
        component.poses.default = pose
        athleteEntity.components.set(component)
        return true
    }

    func contactSpec(role: ReplayAthleteContactRole) -> ReplayAthleteContactSpec? {
        contract.contacts.first { $0.role == role }
    }

    /// The exact terminal-local point constrained and measured for a contact.
    /// Hand roles retain the authored palm point and add the fitted sport
    /// channel displacement; feet retain the authored sole offset unchanged.
    func effectiveContactOffset(role: ReplayAthleteContactRole) -> SIMD3<Float>? {
        guard let spec = contactSpec(role: role) else { return nil }
        let value: SIMD3<Double>
        switch role {
        case .leftHand:
            var referencePalm = ReplayGripGeometry.handPalmContact
            referencePalm.x *= -1
            value = spec.localOffset + (
                ReplayAthleteGripController.effectorOffset(for: sport, side: .left)
                    - referencePalm
            )
        case .rightHand:
            value = spec.localOffset + (
                ReplayAthleteGripController.effectorOffset(for: sport, side: .right)
                    - ReplayGripGeometry.handPalmContact
            )
        case .leftFoot, .rightFoot:
            value = spec.localOffset
        }
        return SIMD3(Float(value.x), Float(value.y), Float(value.z))
    }

    func jointIndex(named bone: String, in pose: SkeletalPose) -> Int? {
        if let exact = pose.jointNames.firstIndex(of: bone) {
            return exact
        }
        return pose.jointNames.firstIndex { $0.split(separator: "/").last == Substring(bone) }
    }

    func skeletalContactPosition(
        role: ReplayAthleteContactRole,
        relativeTo space: Entity
    ) -> SIMD3<Float>? {
        guard let pose = currentConstraintPose(),
              let spec = contactSpec(role: role),
              let index = jointIndex(named: spec.bone, in: pose),
              let offset = effectiveContactOffset(role: role) else {
            return nil
        }
        let matrices = skeletalJointMatrices(for: pose)
        guard matrices.indices.contains(index) else { return nil }
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

    func setContactDebugMarker(
        role: ReplayAthleteContactRole,
        position: SIMD3<Float>,
        relativeTo space: Entity
    ) {
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

}
