import Foundation
import RealityKit
import RowPlayCore

/// Resolves a generated asset resource without coupling the library to a
/// filesystem location. Production uses `Bundle.module`; tests can inject a
/// missing or malformed source to prove the atomic fallback contract.
@MainActor
protocol ReplayAssetResourceSource: AnyObject {
    func url(for resource: ReplayAssetResource) -> URL?
}

@MainActor
private final class ReplayModuleAssetResourceSource: ReplayAssetResourceSource {
    func url(for resource: ReplayAssetResource) -> URL? {
        ReplayAssetLibrary.bundledResourceURL(for: resource)
    }
}

/// A complete validated sport-specific asset set.
///
/// Equipment and environment come from the native USDA package. The athlete is
/// the upstream V4 USDZ template. All three must validate together — a missing
/// athlete rejects the whole bundled set so scenes never mix sources.
///
/// The templates never enter a live RealityKit scene. Callers receive fresh
/// clones so live and ghost rigs cannot share mutable entity state.
@MainActor
final class ReplayBundledAssetSet {
    let sport: Sport
    let rigVisualProvider: ReplayBundledRigVisualProvider
    let athleteTemplate: ReplayAthleteTemplate

    private let environmentTemplate: Entity

    init?(
        sport: Sport,
        rigRoot: Entity,
        environmentRoot: Entity,
        athleteTemplate: ReplayAthleteTemplate
    ) {
        guard let provider = ReplayBundledRigVisualProvider(
            root: rigRoot,
            requiredNodeNames: Set(ReplayAssetCatalog.requiredRigNodeNames(for: sport))
        ),
        let environmentRootNode = environmentRoot.replayDescendant(
            named: ReplayAssetCatalog.bundledPrimName(for: "environment-root")
        ),
        let environmentGround = environmentRoot.replayDescendant(
            named: ReplayAssetCatalog.bundledPrimName(for: "environment-ground")
        ),
        let environmentProps = environmentRoot.replayDescendant(
            named: ReplayAssetCatalog.bundledPrimName(for: "environment-props")
        ),
        ReplayAssetGeometry.hasModel(in: environmentRootNode),
        ReplayAssetGeometry.hasModel(in: environmentGround),
        ReplayAssetGeometry.hasModel(in: environmentProps) else {
            return nil
        }

        self.sport = sport
        self.rigVisualProvider = provider
        self.athleteTemplate = athleteTemplate
        self.environmentTemplate = environmentRoot
        rigRoot.isEnabled = false
        environmentTemplate.isEnabled = false
    }

    func cloneEnvironment() -> Entity {
        let clone = environmentTemplate.clone(recursive: true)
        clone.isEnabled = true
        // Keep asset prim names (especially `environment_root`) intact. A
        // separate wrapper provides the stable scene label without overwriting
        // contract node identity required by environment validation/tests.
        let wrapper = Entity()
        wrapper.name = "bundled-environment"
        wrapper.addChild(clone)
        wrapper.isEnabled = true
        return wrapper
    }

    func makeAthleteInstance(name: String, opacity: Float) -> ReplayAthleteInstance? {
        athleteTemplate.makeInstance(name: name, opacity: opacity)
    }
}

/// Small RealityKit-side geometry predicate shared by the template and rig
/// validators. It intentionally runs only while loading a scene graph, never
/// from the per-frame update path.
@MainActor
enum ReplayAssetGeometry {
    static func hasModel(in entity: Entity) -> Bool {
        if entity.components[ModelComponent.self] != nil {
            return true
        }
        return entity.children.contains { hasModel(in: $0) }
    }
}

/// Loads and validates the generated Phase 11 asset package from `Bundle.module`.
///
/// A sport is cached only after both its rig and environment validate and load.
/// Failed loads are cached too: replay rendering must remain deterministic and
/// use the complete procedural fallback instead of repeatedly retrying a broken
/// resource on every SwiftUI update.
@MainActor
final class ReplayAssetLibrary {
    static let shared = ReplayAssetLibrary(source: ReplayModuleAssetResourceSource())

    private let source: any ReplayAssetResourceSource
    private var loadedSets: [Sport: ReplayBundledAssetSet] = [:]
    private var failedSports = Set<Sport>()
    private var inFlightLoads: [Sport: Task<ReplayBundledAssetSet?, Never>] = [:]

    init(source: any ReplayAssetResourceSource) {
        self.source = source
    }

    func bundledAssetSet(for sport: Sport) async -> ReplayBundledAssetSet? {
        if let cached = loadedSets[sport] {
            return cached
        }
        guard !failedSports.contains(sport) else { return nil }

        if let inFlight = inFlightLoads[sport] {
            return await inFlight.value
        }

        let load: Task<ReplayBundledAssetSet?, Never> = Task { @MainActor [weak self] () -> ReplayBundledAssetSet? in
            guard let self else { return nil }
            return await self.loadAssetSet(for: sport)
        }
        inFlightLoads[sport] = load
        let result = await load.value
        inFlightLoads[sport] = nil
        return result
    }

    private func loadAssetSet(for sport: Sport) async -> ReplayBundledAssetSet? {
        if let cached = loadedSets[sport] {
            return cached
        }
        guard !failedSports.contains(sport) else { return nil }

        // Athlete is shared across sports but required for every bundled set.
        guard let athleteTemplate = await ReplayAthleteLibrary.shared.athleteTemplate() else {
            failedSports.insert(sport)
            return nil
        }

        let resources = ReplayAssetCatalog.resources(for: sport)
        var urls: [ReplayAssetResource: URL] = [:]
        var inspections: [ReplayAssetInspection] = []

        for resource in resources {
            guard let url = source.url(for: resource),
                  let inspection = Self.inspect(resource: resource, at: url) else {
                failedSports.insert(sport)
                return nil
            }
            urls[resource] = url
            inspections.append(inspection)
        }

        guard ReplayAssetCatalog.validateAssetSet(
            for: sport,
            inspections: inspections
        ).isValid,
        let rigURL = urls[ReplayAssetCatalog.rigResource(for: sport)],
        let environmentURL = urls[ReplayAssetCatalog.environmentResource(for: sport)],
        let rigRoot = try? await Entity(contentsOf: rigURL),
        let environmentRoot = try? await Entity(contentsOf: environmentURL),
        let set = ReplayBundledAssetSet(
            sport: sport,
            rigRoot: rigRoot,
            environmentRoot: environmentRoot,
            athleteTemplate: athleteTemplate
        ) else {
            failedSports.insert(sport)
            return nil
        }

        loadedSets[sport] = set
        return set
    }

    /// Test-only cache reset. It is intentionally internal so production code
    /// never treats asset loading as an animation or per-frame operation.
    func resetCacheForTesting() {
        loadedSets.removeAll()
        failedSports.removeAll()
        for load in inFlightLoads.values {
            load.cancel()
        }
        inFlightLoads.removeAll()
    }

    static func bundledResourceURL(for resource: ReplayAssetResource) -> URL? {
        let bundle = Bundle.module
        return bundle.url(
            forResource: resource.resourceName,
            withExtension: resource.fileExtension,
            subdirectory: resource.subdirectory
        ) ?? bundle.url(
            forResource: resource.resourceName,
            withExtension: resource.fileExtension
        )
    }

    static func inspect(
        resource: ReplayAssetResource,
        at url: URL
    ) -> ReplayAssetInspection? {
        guard let data = try? Data(contentsOf: url),
              let source = String(data: data, encoding: .utf8) else {
            return nil
        }

        let nodeNames = logicalNodeNames(in: source)
        let geometryNodeNames = logicalNodeNamesWithGeometry(in: source)
        let triangleCount = metadataInteger(named: "rowplay-triangles", in: source) ?? -1
        let declaredMaterials = Set(metadataValues(
            named: "rowplay-material-categories",
            in: source
        ))
        let materialCategories = declaredMaterials.filter {
            source.contains("def Material \"\($0)\"")
        }
        let bounds = metadataBounds(named: "rowplay-bounds", in: source)
        let containsNonFinite = containsNonFiniteNumericToken(in: source)

        return ReplayAssetInspection(
            resource: resource,
            nodeNames: nodeNames,
            geometryNodeNames: geometryNodeNames,
            triangleCount: triangleCount,
            byteCount: data.count,
            hasGeometry: source.contains("def Mesh"),
            hasFiniteTransforms: !containsNonFinite,
            hasFiniteNormals: !containsNonFinite,
            hasFiniteBounds: !containsNonFinite && (bounds?.hasFiniteNonemptyExtent ?? false),
            containsCamera: source.contains("def Camera"),
            containsLight: source.contains("def DistantLight")
                || source.contains("def DomeLight")
                || source.contains("def SphereLight"),
            materialCategories: materialCategories,
            bounds: bounds
        )
    }

    private static func logicalNodeNames(in source: String) -> [String] {
        let pattern = "rowplay:logicalName\\s*=\\s*\"([^\"]+)\""
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(source.startIndex..., in: source)
        return expression.matches(in: source, range: range).compactMap { match in
            guard let nameRange = Range(match.range(at: 1), in: source) else {
                return nil
            }
            return String(source[nameRange])
        }
    }

    /// Reads the generated USDA in logical-node order and records only the
    /// nodes whose own block contains a mesh with points and face indices.
    /// This is deliberately narrow: it validates the stable generated subset
    /// of USDA that the repository owns, before RealityKit creates templates.
    private static func logicalNodeNamesWithGeometry(in source: String) -> [String] {
        let pattern = "rowplay:logicalName\\s*=\\s*\"([^\"]+)\""
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(source.startIndex..., in: source)
        let matches = expression.matches(in: source, range: range)
        return matches.enumerated().compactMap { index, match -> String? in
            guard let nameRange = Range(match.range(at: 1), in: source) else {
                return nil
            }
            let blockStart = String.Index(utf16Offset: match.range.location, in: source)
            let nextLocation = index + 1 < matches.count
                ? matches[index + 1].range.location
                : source.utf16.count
            let blockEnd = String.Index(utf16Offset: nextLocation, in: source)
            let block = source[blockStart..<blockEnd]
            guard block.contains("def Mesh"),
                  block.contains("point3f[] points"),
                  block.contains("int[] faceVertexIndices"),
                  block.contains("normal3f[] normals") else {
                return nil
            }
            return String(source[nameRange])
        }
    }

    private static func metadataInteger(named key: String, in source: String) -> Int? {
        guard let value = metadataValue(named: key, in: source) else {
            return nil
        }
        return Int(value)
    }

    private static func metadataValues(named key: String, in source: String) -> [String] {
        guard let value = metadataValue(named: key, in: source) else {
            return []
        }
        return value.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }

    private static func metadataBounds(named key: String, in source: String) -> ReplayAssetBounds? {
        let values = metadataValues(named: key, in: source).compactMap(Double.init)
        guard values.count == 6 else { return nil }
        return ReplayAssetBounds(
            minimum: SIMD3(values[0], values[1], values[2]),
            maximum: SIMD3(values[3], values[4], values[5])
        )
    }

    private static func metadataValue(named key: String, in source: String) -> String? {
        let prefix = "# \(key):"
        for line in source.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(prefix) else { continue }
            return trimmed.dropFirst(prefix.count)
                .trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func containsNonFiniteNumericToken(in source: String) -> Bool {
        let pattern = "(?i)(?:\\bnan\\b|\\binfinity\\b|\\b[+-]?inf\\b)"
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return true
        }
        let range = NSRange(source.startIndex..., in: source)
        return expression.firstMatch(in: source, range: range) != nil
    }
}
