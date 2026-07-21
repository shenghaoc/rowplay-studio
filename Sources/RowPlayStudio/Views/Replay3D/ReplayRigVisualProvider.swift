import AppKit
import Foundation
import RealityKit

/// Supplies visual meshes to an existing logical sport rig.
///
/// The articulated rig remains the owner of pivots, contacts, and pose
/// application. A provider only supplies immutable visual templates, which are
/// recursively cloned during scene construction so live and rival rigs cannot
/// share mutable entities or materials.
@MainActor
protocol ReplayRigVisualProvider: AnyObject {
    /// Whether the provider represents a complete validated bundled asset set.
    var usesBundledAssets: Bool { get }

    /// Returns an independent clone of a named visual node, or `nil` when the
    /// provider cannot supply that node.
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
    /// Returning `false` allows callers to construct their procedural visual
    /// only when a bundled provider was not selected. A valid bundled provider
    /// contains every required name, so partial visual mixes are impossible.
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
