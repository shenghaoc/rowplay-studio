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
    private let animationResource: AnimationResource?

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

        // Require at least one authored animation for phase sampling. The
        // provisional USDZ currently bakes the row cycle; contract metadata
        // still describes all three sports for adapter mapping.
        let animations = root.availableAnimations
        guard !animations.isEmpty else {
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
        self.animationResource = animations.first
        rootTemplate.isEnabled = false
    }

    func makeInstance(name: String, opacity: Float) -> ReplayAthleteInstance? {
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
            animationResource: animationResource
        )
        if opacity < 0.999 {
            instance.applyOpacity(opacity)
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

    private let animationResource: AnimationResource?
    private var playbackController: AnimationPlaybackController?
    private var lastSampledFraction: Double?

    let leftHandContact: Entity?
    let rightHandContact: Entity?
    let leftFootContact: Entity?
    let rightFootContact: Entity?

    fileprivate init(
        root: Entity,
        athleteEntity: Entity,
        contract: ReplayAthleteContract,
        jointNames: [String],
        animationResource: AnimationResource?
    ) {
        self.root = root
        self.athleteEntity = athleteEntity
        self.contract = contract
        self.jointNames = jointNames
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

    /// Seek the authored animation to a normalized clip fraction in [0, 1).
    ///
    /// Playback speed is always zero so the native replay clock owns time.
    func seek(toClipFraction fraction: Double) {
        let clamped = ReplayAthleteCatalog.wrapUnit(fraction)
        ensurePlaybackController()
        guard let controller = playbackController,
              let resource = animationResource else {
            return
        }
        let duration = max(resource.definition.duration, 1e-4)
        controller.speed = 0
        controller.time = clamped * duration
        lastSampledFraction = clamped
    }

    func stopAnimation() {
        root.stopAllAnimations(recursive: true)
        playbackController = nil
        lastSampledFraction = nil
    }

    /// Apply rival translucency only to this instance's materials.
    func applyOpacity(_ opacity: Float) {
        ReplaySportRigTranslucency.apply(to: root, opacity: opacity)
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

    private func ensurePlaybackController() {
        guard playbackController == nil, let resource = animationResource else {
            return
        }
        let controller = root.playAnimation(resource.repeat())
        controller.speed = 0
        playbackController = controller
    }
}
