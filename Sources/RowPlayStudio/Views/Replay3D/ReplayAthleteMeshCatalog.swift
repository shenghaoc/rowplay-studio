import Foundation
import RealityKit

/// Loads the shared athlete character USDZ once and provides named mesh clones
/// for each athlete instance (live, ghost). Each clone owns independent
/// geometry and materials; the template hierarchy is never attached to a scene.
@MainActor
final class ReplayAthleteMeshCatalog {
    /// The loaded template root — never attached directly to a scene.
    private let templateRoot: Entity

    /// Maps segment names ("athlete-head", "athlete-upperArm-L", …) to their
    /// template entities inside `templateRoot`.
    private let segments: [String: Entity]

    /// Mesh names expected in the USDZ. Each key matches the Blender object name;
    /// each value is the corresponding pivot name in `ReplayAthleteRig`.
    static let segmentNames: [String] = [
        "athlete-head",
        "athlete-neck",
        "athlete-torso",
        "athlete-upperArm-L",
        "athlete-upperArm-R",
        "athlete-forearm-L",
        "athlete-forearm-R",
        "athlete-hand-L",
        "athlete-hand-R",
        "athlete-thigh-L",
        "athlete-thigh-R",
        "athlete-shin-L",
        "athlete-shin-R",
        "athlete-foot-L",
        "athlete-foot-R",
        "athlete-shirt",
        "athlete-shorts",
        "athlete-shoe-L",
        "athlete-shoe-R",
    ]

    /// Create a catalog by loading the USDZ from the app bundle.
    /// Returns `nil` when the asset is missing so callers can fall back
    /// to the procedural primitive rig.
    init?() async {
        guard let root = await ReplayAthleteMeshCatalog.loadUSDZ() else {
            return nil
        }
        templateRoot = root
        templateRoot.isEnabled = false

        var map: [String: Entity] = [:]
        for name in Self.segmentNames {
            if let entity = root.findEntity(named: name) {
                map[name] = entity
            }
        }
        segments = map
    }

    /// Number of successfully loaded segments.
    var loadedCount: Int { segments.count }

    /// Create a clone of every named segment for a new athlete instance.
    /// Returns a dictionary mapping segment name → cloned Entity.
    func cloneAll() -> [String: Entity] {
        var clones: [String: Entity] = [:]
        for (name, template) in segments {
            let clone = template.clone(recursive: true)
            clone.name = name
            clones[name] = clone
        }
        return clones
    }

    /// Clone a single named segment.
    func clone(named name: String) -> Entity? {
        guard let template = segments[name] else { return nil }
        let clone = template.clone(recursive: true)
        clone.name = name
        return clone
    }

    // MARK: - Private

    private static func loadUSDZ() async -> Entity? {
        // In the app bundle, resources from SPM .process are in the main bundle.
        if let url = Bundle.main.url(
            forResource: "athlete-character",
            withExtension: "usdz"
        ) {
            return try? await Entity(contentsOf: url)
        }
        #if SWIFT_PACKAGE
        // Fallback: try SPM-generated Bundle.module location
        if let moduleURL = Bundle.module.url(
            forResource: "athlete-character",
            withExtension: "usdz"
        ) {
            return try? await Entity(contentsOf: moduleURL)
        }
        #endif
        return nil
    }
}

private extension Entity {
    /// Recursively search for an entity with the given name.
    func findEntity(named name: String) -> Entity? {
        if self.name == name { return self }
        for child in children {
            if let found = child.findEntity(named: name) { return found }
        }
        return nil
    }
}
