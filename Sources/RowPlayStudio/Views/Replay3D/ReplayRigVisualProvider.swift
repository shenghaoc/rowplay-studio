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
    /// selects the established procedural builder at that logical pivot.
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
    /// Returning `false` tells callers to construct their existing procedural
    /// visual. A valid bundled provider contains every required name, so a
    /// selected bundled sport set never produces a partial visual mix.
    @discardableResult
    func attachVisual(named name: String, to parent: Entity) -> Bool {
        guard let visual = cloneVisual(named: name) else { return false }
        parent.addChild(visual)
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
