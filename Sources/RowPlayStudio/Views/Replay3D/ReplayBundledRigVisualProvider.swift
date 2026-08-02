import AppKit
import Foundation
import RealityKit
import RowPlayCore

/// Bundled visual source backed by one converted equipment package.
///
/// The provider holds the immutable loaded package root and resolves visuals
/// by their RowPlay source names (`equipment:row:oar-rig`,
/// `equipment:row:oar-rig:grip`, …), translating to the USD-safe exported
/// prim names recorded in the sidecar contract.  Every lookup returns a fresh
/// recursive clone, so live and rival rigs never share entities or materials.
/// The initializer is all-or-nothing: a missing required node fails the whole
/// provider so scene construction selects the complete procedural fallback.
@MainActor
final class ReplayBundledRigVisualProvider: ReplayRigVisualProvider {
    private let root: Entity
    private let contract: ReplayEquipmentPackageContract
    private var templateCache: [String: Entity] = [:]

    init?(root: Entity, contract: ReplayEquipmentPackageContract) {
        guard ReplayAssetCatalog.validatePackageContract(contract) else { return nil }
        self.root = root
        self.contract = contract

        // Every required node must resolve in the loaded package with real
        // geometry beneath it; a partially converted package selects the
        // complete procedural fallback instead.
        let requiredNames = ReplayAssetCatalog.requiredCompositeSourceNames(for: contract.sport)
            + ReplayAssetCatalog.requiredLeafSourceNames(for: contract.sport)
        for sourceName in requiredNames {
            guard let node = contract.node(sourceName: sourceName),
                  let entity = root.replayDescendant(named: node.exportedName),
                  ReplayAssetGeometry.hasModel(in: entity) else {
                return nil
            }
            templateCache[sourceName] = entity
        }
        root.isEnabled = false
    }

    var usesBundledAssets: Bool { true }

    var sport: Sport { contract.sport }

    func cloneVisual(named name: String) -> Entity? {
        let template: Entity?
        if let cached = templateCache[name] {
            template = cached
        } else if let node = contract.node(sourceName: name) {
            template = root.replayDescendant(named: node.exportedName)
        } else if let exported = exportedPartName(for: name) {
            template = root.replayDescendant(named: exported)
        } else {
            template = nil
        }
        guard let template else { return nil }
        templateCache[name] = template
        let clone = template.clone(recursive: true)
        clone.isEnabled = true
        return clone
    }

    /// Resolve a `template:part` source path to its exported prim name.
    private func exportedPartName(for sourceName: String) -> String? {
        for node in contract.nodes {
            if let part = node.parts.first(where: { $0.sourceName == sourceName }) {
                return part.exportedName
            }
        }
        return nil
    }

    /// Recolour a cloned bundled visual with the scene accent.  Bundled
    /// materials load as PBR; tint the base colour while keeping the material
    /// opaque and depth-writing.
    static func applyAccent(_ accent: NSColor, to entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            model.materials = model.materials.map { material in
                if var pbr = material as? PhysicallyBasedMaterial {
                    pbr.baseColor.tint = accent
                    return pbr
                }
                if var simple = material as? SimpleMaterial {
                    simple.color.tint = accent
                    return simple
                }
                return material
            }
            entity.components.set(model)
        }
        for child in entity.children {
            applyAccent(accent, to: child)
        }
    }

    /// Apply controlled rival translucency to a cloned bundled equipment
    /// visual.  Unlike the deforming athlete body — which stays opaque with a
    /// cool tint — equipment may use real alpha, matching the web's
    /// `finalizeAvatar` ghost pass.
    static func applyGhostTranslucency(_ opacity: Double, to entity: Entity) {
        let alpha = Float(min(max(opacity, 0), 1))
        if var model = entity.components[ModelComponent.self] {
            model.materials = model.materials.map { material in
                if var pbr = material as? PhysicallyBasedMaterial {
                    pbr.blending = .transparent(opacity: .init(floatLiteral: alpha))
                    return pbr
                }
                if var simple = material as? SimpleMaterial {
                    let tint = simple.color.tint.usingColorSpace(.deviceRGB) ?? simple.color.tint
                    simple.color.tint = tint.withAlphaComponent(CGFloat(alpha))
                    return simple
                }
                return material
            }
            entity.components.set(model)
        }
        for child in entity.children {
            applyGhostTranslucency(opacity, to: child)
        }
    }
}
