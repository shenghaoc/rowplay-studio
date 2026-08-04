import AppKit
import Foundation
import RealityKit

/// Selects the visual source for an existing logical sport rig.
///
/// The articulated rig remains the owner of pivots, contacts, and pose
/// application. A bundled provider supplies immutable visual templates, which
/// are recursively cloned during scene construction so live and rival rigs
/// cannot share mutable entities or materials. The procedural provider instead
/// selects the rig-owned `ReplayMeshFactory` builders by returning no authored
/// visual node.
@MainActor
protocol ReplayRigVisualProvider: AnyObject {
    /// Whether the provider represents a complete validated bundled asset set.
    var usesBundledAssets: Bool { get }

    /// Returns an independent clone of a named authored visual node. `nil`
    /// selects the established procedural builder for a procedural provider.
    /// A bundled provider accepts only its fully prevalidated source-name set;
    /// requesting any other name is a programmer error, never a hybrid seam.
    func cloneVisual(named name: String) -> Entity?
}

/// Decorates a complete bundled provider with a scene-local sport accent.
///
/// The underlying provider always returns a fresh recursive clone. Recolouring
/// therefore happens only on the live or rival scene instance, never on a
/// cached USDA template or another rig. Procedural visuals retain their
/// existing material construction, which already receives the accent directly.
@MainActor
final class ReplayAccentRigVisualProvider: ReplayRigVisualProvider {
    private let base: any ReplayRigVisualProvider
    private let accent: NSColor

    init(base: any ReplayRigVisualProvider, accent: NSColor) {
        self.base = base
        self.accent = accent
    }

    var usesBundledAssets: Bool { base.usesBundledAssets }

    func cloneVisual(named name: String) -> Entity? {
        guard let clone = base.cloneVisual(named: name) else { return nil }
        if base.usesBundledAssets {
            ReplayBundledRigVisualProvider.applyAccent(accent, to: clone)
        }
        return clone
    }
}

@MainActor
extension ReplayRigVisualProvider {
    /// Attaches a bundled visual node to an existing logical pivot.
    ///
    /// Returning `false` tells callers using the procedural provider to build
    /// their existing procedural visual. A selected bundled provider contains
    /// every accepted source name and traps programmer requests outside that
    /// prevalidated set, so it cannot silently produce a partial visual mix.
    @discardableResult
    func attachVisual(named name: String, to parent: Entity) -> Bool {
        guard let visual = cloneVisual(named: name) else { return false }
        parent.addChild(visual)
        return true
    }

    /// Fits an authored leaf into the renderer-owned logical envelope.
    ///
    /// V3 leaf meshes are normalized authoring forms. Their geometry replaces
    /// a measured procedural slot in RowPlay, whereas composite templates are
    /// already metre-authored assemblies. RealityKit cannot swap a mesh while
    /// retaining the slot transform, so a wrapper applies the same bounds fit
    /// without mutating the cached template or any sibling clone.
    func attachFittedVisual(
        named name: String,
        to parent: Entity,
        targetSize: SIMD3<Float>,
        targetCenter: SIMD3<Float> = .zero
    ) -> Bool {
        guard let visual = cloneVisual(named: name) else { return false }
        let fit = Entity()
        fit.name = "\(name)-fit"
        fit.addChild(visual)
        parent.addChild(fit)

        let bounds = visual.visualBounds(relativeTo: fit)
        let extents = bounds.extents
        guard extents.x.isFinite, extents.y.isFinite, extents.z.isFinite,
              extents.x > 1e-6, extents.y > 1e-6, extents.z > 1e-6 else {
            fit.removeFromParent()
            return false
        }
        let scale = SIMD3(
            targetSize.x / extents.x,
            targetSize.y / extents.y,
            targetSize.z / extents.z
        )
        fit.scale = scale
        fit.position = targetCenter - bounds.center * scale
        return true
    }
}

@MainActor
extension Entity {
    func replayDescendant(named name: String) -> Entity? {
        if self.name == name { return self }
        for child in children {
            if let match = child.replayDescendant(named: name) {
                return match
            }
        }
        return nil
    }
}
