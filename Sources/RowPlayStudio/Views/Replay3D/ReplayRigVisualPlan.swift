import RealityKit
import RowPlayCore

/// One articulated-rig visual slot and the authored equipment node that fills it.
///
/// The rig-facing names are intentionally kept separate from RowPlay's source
/// names. A complete plan is preflighted before any entity is attached, so an
/// unavailable clone selects the whole procedural rig instead of a hybrid.
struct ReplayRigVisualSlot: Equatable, Sendable {
    let logicalName: String
    let sourceName: String
}

enum ReplayRigVisualCatalog {
    static func slots(for sport: Sport) -> [ReplayRigVisualSlot] {
        switch sport {
        case .rower:
            return [
                // Consume the complete composites that the package gate
                // validates. Selecting a few children here made the rest of
                // the authored hull/rigger/cockpit set validation-only.
                .init(logicalName: "visual-boat", sourceName: "equipment:row:boat-assembly"),
                .init(logicalName: "visual-seat", sourceName: "equipment:row:seat-carriage"),
                .init(logicalName: "visual-oar-port", sourceName: "equipment:row:oar-rig"),
                .init(logicalName: "visual-oar-starboard", sourceName: "equipment:row:oar-rig"),
                .init(logicalName: "visual-blade-port", sourceName: "equipment:row:blade"),
                .init(logicalName: "visual-blade-starboard", sourceName: "equipment:row:blade"),
            ]
        case .skierg:
            return [
                .init(logicalName: "visual-ski-L", sourceName: "equipment:ski:ski-assembly"),
                .init(logicalName: "visual-ski-R", sourceName: "equipment:ski:ski-assembly"),
                .init(logicalName: "visual-pole-shaft-L", sourceName: "equipment:ski:pole-shaft"),
                .init(logicalName: "visual-pole-shaft-R", sourceName: "equipment:ski:pole-shaft"),
                .init(logicalName: "visual-pole-grip-L", sourceName: "equipment:ski:pole-grip"),
                .init(logicalName: "visual-pole-grip-R", sourceName: "equipment:ski:pole-grip"),
                .init(logicalName: "visual-pole-basket-L", sourceName: "equipment:ski:pole-basket"),
                .init(logicalName: "visual-pole-basket-R", sourceName: "equipment:ski:pole-basket"),
            ]
        case .bike:
            return [
                .init(logicalName: "visual-wheel-front", sourceName: "equipment:bike:wheel-assembly"),
                .init(logicalName: "visual-wheel-rear", sourceName: "equipment:bike:wheel-assembly"),
                .init(logicalName: "visual-frame", sourceName: "equipment:bike:frame-assembly"),
                .init(logicalName: "visual-drivetrain", sourceName: "equipment:bike:drivetrain-assembly"),
            ]
        }
    }
}

/// A scene-local, all-or-nothing set of cloned visuals for one sport rig.
@MainActor
final class ReplayPreflightRigVisualProvider: ReplayRigVisualProvider {
    let sport: Sport
    let logicalNames: Set<String>
    private let templates: [String: Entity]

    init?(base: any ReplayRigVisualProvider, sport: Sport) {
        guard base.usesBundledAssets else { return nil }
        let slots = ReplayRigVisualCatalog.slots(for: sport)
        let expectedLogicalNames = Set(slots.map(\.logicalName))
        guard expectedLogicalNames.count == slots.count else { return nil }
        var resolved: [String: Entity] = [:]
        for slot in slots {
            guard resolved[slot.logicalName] == nil,
                  let clone = base.cloneVisual(named: slot.sourceName),
                  ReplayAssetGeometry.hasModel(in: clone) else {
                return nil
            }
            resolved[slot.logicalName] = clone
        }
        guard Set(resolved.keys) == expectedLogicalNames else { return nil }
        self.sport = sport
        self.logicalNames = expectedLogicalNames
        templates = resolved
    }

    let usesBundledAssets = true

    func cloneVisual(named name: String) -> Entity? {
        guard logicalNames.contains(name), let template = templates[name] else {
            preconditionFailure(
                "Preflighted \(sport.rawValue) equipment requested unknown logical slot: \(name)"
            )
        }
        return template.clone(recursive: true)
    }

    func isComplete(for requestedSport: Sport) -> Bool {
        requestedSport == sport
            && logicalNames == Set(
                ReplayRigVisualCatalog.slots(for: requestedSport).map(\.logicalName)
            )
    }
}
