import AppKit
import Foundation
import RealityKit
import RowPlayCore

enum ReplayBundledRigVisualProviderFailure: Error, Equatable, Sendable {
    case invalidContract(ReplayEquipmentContractFailure)
    case missingEntity(sourceName: String, exportedName: String)
    case missingModel(sourceName: String, exportedName: String)

    var diagnosticCode: String {
        switch self {
        case .invalidContract(let failure):
            "contract-\(failure.diagnosticCode)"
        case .missingEntity:
            "missing-entity"
        case .missingModel:
            "missing-model"
        }
    }
}

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

    init(root: Entity, contract: ReplayEquipmentPackageContract) throws {
        let requiredVisuals: [ReplayEquipmentRequiredVisualSpec]
        switch ReplayAssetCatalog.requiredVisuals(in: contract) {
        case .success(let visuals):
            requiredVisuals = visuals
        case .failure(let failure):
            throw ReplayBundledRigVisualProviderFailure.invalidContract(failure)
        }
        self.root = root
        self.contract = contract

        // Every composite root, required part, and required leaf must resolve
        // with real geometry before bundled mode can activate.
        for visual in requiredVisuals {
            guard let entity = root.replayDescendant(named: visual.exportedName) else {
                throw ReplayBundledRigVisualProviderFailure.missingEntity(
                    sourceName: visual.sourceName,
                    exportedName: visual.exportedName
                )
            }
            guard ReplayAssetGeometry.hasModel(in: entity) else {
                throw ReplayBundledRigVisualProviderFailure.missingModel(
                    sourceName: visual.sourceName,
                    exportedName: visual.exportedName
                )
            }
            templateCache[visual.sourceName] = entity
        }
        root.isEnabled = false
    }

    var usesBundledAssets: Bool { true }

    var sport: Sport { contract.sport }

    var validatedSourceNames: Set<String> { Set(templateCache.keys) }

    func cloneVisual(named name: String) -> Entity? {
        guard let template = templateCache[name] else {
            preconditionFailure(
                "Bundled equipment requested an unvalidated visual name: \(name)"
            )
        }
        let clone = template.clone(recursive: true)
        clone.isEnabled = true
        return clone
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

}
