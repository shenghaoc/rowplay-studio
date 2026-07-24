import AppKit
import RealityKit

/// A validated bundled rig template.
///
/// The initializer is all-or-nothing: a missing required node fails the whole
/// provider so scene construction selects the complete procedural fallback
/// rather than mixing authored and generated geometry.
@MainActor
final class ReplayBundledRigVisualProvider: ReplayRigVisualProvider {
    let usesBundledAssets = true

    private let templates: [String: Entity]

    init?(root: Entity, requiredNodeNames: Set<String>) {
        var loaded: [String: Entity] = [:]
        for name in requiredNodeNames {
            guard let entity = root.replayDescendant(
                named: ReplayAssetCatalog.bundledPrimName(for: name)
            ), ReplayAssetGeometry.hasModel(in: entity) else {
                return nil
            }
            loaded[name] = entity
        }
        self.templates = loaded
    }

    func cloneVisual(named name: String) -> Entity? {
        guard let template = templates[name] else { return nil }
        let clone = template.clone(recursive: true)
        clone.name = name
        return clone
    }

    /// Recolours only the authored `accent` material slots. The deterministic
    /// generator names those meshes `material_accent_*`, so selection is
    /// semantic rather than a fragile comparison against a rendered colour.
    /// The caller owns a recursive clone, never a cached template.
    static func applyAccent(_ accent: NSColor, to entity: Entity) {
        if entity.name.hasPrefix("material_accent_"),
           var model = entity.components[ModelComponent.self] {
            model.materials = model.materials.map { material in
                if var simple = material as? SimpleMaterial {
                    simple.color.tint = accent.withAlphaComponent(simple.color.tint.cgColor.alpha)
                    return simple
                }
                if var pbr = material as? PhysicallyBasedMaterial {
                    pbr.baseColor.tint = accent.withAlphaComponent(pbr.baseColor.tint.cgColor.alpha)
                    return pbr
                }
                if var unlit = material as? UnlitMaterial {
                    unlit.color.tint = accent.withAlphaComponent(unlit.color.tint.cgColor.alpha)
                    return unlit
                }
                return material
            }
            entity.components.set(model)
        }
        for child in entity.children {
            applyAccent(accent, to: child)
        }
    }
}
