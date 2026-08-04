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
                .init(logicalName: "visual-hull", sourceName: "equipment:row:boat-assembly:hull"),
                .init(logicalName: "visual-deck-stripe", sourceName: "equipment:row:boat-assembly:accent-strakes"),
                .init(logicalName: "visual-footplate", sourceName: "equipment:row:boat-assembly:foot-stretcher"),
                .init(logicalName: "visual-rail", sourceName: "equipment:row:boat-assembly:slide-rails"),
                .init(logicalName: "visual-seat", sourceName: "equipment:row:seat-carriage"),
                .init(logicalName: "visual-handle", sourceName: "equipment:row:oar-rig:grip"),
                .init(logicalName: "visual-oar-port", sourceName: "equipment:row:oar-rig"),
                .init(logicalName: "visual-oar-starboard", sourceName: "equipment:row:oar-rig"),
            ]
        case .skierg:
            return [
                .init(logicalName: "visual-post-L", sourceName: "equipment:ski:ski-assembly:edge-left"),
                .init(logicalName: "visual-post-R", sourceName: "equipment:ski:ski-assembly:edge-right"),
                .init(logicalName: "visual-topBar", sourceName: "equipment:ski:ski-assembly:tip-ridge"),
                .init(logicalName: "visual-cable", sourceName: "equipment:ski:pole-shaft"),
                .init(logicalName: "visual-handle-L", sourceName: "equipment:ski:pole-grip"),
                .init(logicalName: "visual-handle-R", sourceName: "equipment:ski:pole-grip"),
                .init(logicalName: "visual-platform", sourceName: "equipment:ski:ski-assembly:top-deck"),
                .init(logicalName: "visual-pole-L", sourceName: "equipment:ski:pole-shaft"),
                .init(logicalName: "visual-pole-R", sourceName: "equipment:ski:pole-shaft"),
            ]
        case .bike:
            return [
                .init(logicalName: "visual-wheel-front", sourceName: "equipment:bike:wheel-assembly"),
                .init(logicalName: "visual-wheel-rear", sourceName: "equipment:bike:wheel-assembly"),
                .init(logicalName: "visual-downTube", sourceName: "equipment:bike:frame-assembly:main-triangle"),
                .init(logicalName: "visual-seatTube", sourceName: "equipment:bike:frame-assembly:seat-post"),
                .init(logicalName: "visual-topTube", sourceName: "equipment:bike:frame-assembly:stays-and-fork"),
                .init(logicalName: "visual-saddle", sourceName: "equipment:bike:frame-assembly:saddle"),
                .init(logicalName: "visual-cranks", sourceName: "equipment:bike:drivetrain-assembly:crank-arms"),
                .init(logicalName: "visual-chainRing", sourceName: "equipment:bike:drivetrain-assembly:chainring"),
                .init(logicalName: "visual-pedal-L", sourceName: "equipment:bike:drivetrain-assembly:clipless-pedals"),
                .init(logicalName: "visual-pedal-R", sourceName: "equipment:bike:drivetrain-assembly:clipless-pedals"),
                .init(logicalName: "visual-handlebar", sourceName: "equipment:bike:frame-assembly:cockpit"),
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
