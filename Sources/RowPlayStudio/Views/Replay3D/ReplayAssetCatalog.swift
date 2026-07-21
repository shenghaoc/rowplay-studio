import Foundation
import RowPlayCore

/// The two authored asset files that together provide one sport's replay visuals.
///
/// Keeping this distinction explicit lets the loader reject a partial asset set
/// rather than combining an authored rig with a procedural environment (or vice
/// versa).
enum ReplayAssetKind: String, CaseIterable, Codable, Hashable, Sendable {
    case rig
    case environment
}

/// A bundled Phase 11 replay asset addressed independently of a specific bundle.
///
/// `ReplayAssetLibrary` owns `Bundle.module` lookup. The catalog deliberately
/// exposes names and paths only, so contract validation remains deterministic and
/// testable without RealityKit.
struct ReplayAssetResource: Hashable, Sendable {
    let sport: Sport
    let kind: ReplayAssetKind

    init(sport: Sport, kind: ReplayAssetKind) {
        self.sport = sport
        self.kind = kind
    }

    /// The basename passed to `Bundle.url(forResource:withExtension:subdirectory:)`.
    var resourceName: String {
        "\(sport.rawValue)-\(kind.rawValue)"
    }

    var fileExtension: String { "usda" }

    var fileName: String { "\(resourceName).\(fileExtension)" }

    var subdirectory: String { ReplayAssetCatalog.resourceSubdirectory }

    /// Stable source-control path relative to `Sources/RowPlayStudio/Resources`.
    var relativePath: String { "\(subdirectory)/\(fileName)" }

    static func == (lhs: ReplayAssetResource, rhs: ReplayAssetResource) -> Bool {
        lhs.sport.rawValue == rhs.sport.rawValue && lhs.kind == rhs.kind
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(sport.rawValue)
        hasher.combine(kind)
    }
}

/// The visual source selected for a complete sport asset set.
enum ReplayAssetVisualSource: Equatable, Sendable {
    case procedural
    case bundled
}

/// Exact generated asset envelope in local asset coordinates.
///
/// Bounds are part of the committed golden contract so a visually plausible
/// but incorrectly scaled asset cannot silently replace the replay backdrop.
struct ReplayAssetBounds: Equatable, Sendable {
    let minimum: SIMD3<Double>
    let maximum: SIMD3<Double>

    var hasFiniteNonemptyExtent: Bool {
        minimum.x.isFinite && minimum.y.isFinite && minimum.z.isFinite
            && maximum.x.isFinite && maximum.y.isFinite && maximum.z.isFinite
            && maximum.x > minimum.x && maximum.y > minimum.y && maximum.z > minimum.z
    }
}

/// Static limits for the generated Phase 11 asset package.
struct ReplayAssetBudget: Equatable, Sendable {
    /// A rig may contain at most this many triangles.
    let maximumRigTriangleCount: Int
    /// An environment may contain at most this many triangles.
    let maximumEnvironmentTriangleCount: Int
    /// The six-file bundle must be strictly smaller than this byte count.
    let combinedByteLimitExclusive: Int

    func maximumTriangleCount(for kind: ReplayAssetKind) -> Int {
        switch kind {
        case .rig:
            maximumRigTriangleCount
        case .environment:
            maximumEnvironmentTriangleCount
        }
    }
}

/// Loader-produced facts about one authored file.
///
/// This is intentionally RealityKit-free. A future asset library can populate it
/// from a USDA/RealityKit traversal and then use the catalog for all contract
/// decisions.
struct ReplayAssetInspection: Equatable, Sendable {
    let resource: ReplayAssetResource
    let nodeNames: [String]
    /// Required logical nodes whose authored USDA block contains real mesh
    /// point/index data. Presence alone is insufficient: an empty Xform must
    /// select the complete procedural fallback rather than a missing limb.
    let geometryNodeNames: [String]
    let triangleCount: Int
    let byteCount: Int
    let hasGeometry: Bool
    let hasFiniteTransforms: Bool
    let hasFiniteNormals: Bool
    let hasFiniteBounds: Bool
    let containsCamera: Bool
    let containsLight: Bool
    let materialCategories: Set<String>
    let bounds: ReplayAssetBounds?

    init(
        resource: ReplayAssetResource,
        nodeNames: [String],
        geometryNodeNames: [String]? = nil,
        triangleCount: Int,
        byteCount: Int,
        hasGeometry: Bool,
        hasFiniteTransforms: Bool,
        hasFiniteNormals: Bool,
        hasFiniteBounds: Bool,
        containsCamera: Bool,
        containsLight: Bool,
        materialCategories: Set<String>? = nil,
        bounds: ReplayAssetBounds? = nil
    ) {
        self.resource = resource
        self.nodeNames = nodeNames
        self.geometryNodeNames = geometryNodeNames ?? nodeNames
        self.triangleCount = triangleCount
        self.byteCount = byteCount
        self.hasGeometry = hasGeometry
        self.hasFiniteTransforms = hasFiniteTransforms
        self.hasFiniteNormals = hasFiniteNormals
        self.hasFiniteBounds = hasFiniteBounds
        self.containsCamera = containsCamera
        self.containsLight = containsLight
        self.materialCategories = materialCategories
            ?? Set(ReplayAssetCatalog.requiredMaterialCategories(for: resource))
        self.bounds = bounds ?? ReplayAssetCatalog.expectedBounds(for: resource)
    }
}

/// A precise reason a generated or loaded asset set cannot be used.
enum ReplayAssetValidationFailure: Equatable, Sendable {
    case missingResource(ReplayAssetResource)
    case duplicateResource(ReplayAssetResource)
    case unexpectedResource(ReplayAssetResource)
    case missingRequiredNode(resource: ReplayAssetResource, name: String)
    case duplicateRequiredNode(resource: ReplayAssetResource, name: String)
    case missingGeometry(ReplayAssetResource)
    case missingRequiredNodeGeometry(resource: ReplayAssetResource, name: String)
    case nonFiniteTransforms(ReplayAssetResource)
    case nonFiniteNormals(ReplayAssetResource)
    case nonFiniteBounds(ReplayAssetResource)
    case containsCamera(ReplayAssetResource)
    case containsLight(ReplayAssetResource)
    case missingRequiredMaterial(resource: ReplayAssetResource, name: String)
    case invalidBounds(ReplayAssetResource)
    case unexpectedBounds(
        resource: ReplayAssetResource,
        actual: ReplayAssetBounds,
        expected: ReplayAssetBounds
    )
    case invalidTriangleCount(resource: ReplayAssetResource, actual: Int)
    case invalidByteCount(resource: ReplayAssetResource, actual: Int)
    case triangleBudgetExceeded(resource: ReplayAssetResource, actual: Int, maximum: Int)
    case combinedByteBudgetExceeded(actual: Int, limitExclusive: Int)
}

/// The complete result of validating a sport asset set or the full bundle.
struct ReplayAssetValidationResult: Equatable, Sendable {
    let failures: [ReplayAssetValidationFailure]

    init(failures: [ReplayAssetValidationFailure] = []) {
        self.failures = failures
    }

    var isValid: Bool { failures.isEmpty }
}

/// Single source of truth for Phase 11 replay asset names and contracts.
///
/// The catalog contains no loading code. It is safe to use in tests and in
/// deterministic generator checks, while `ReplayAssetLibrary` can use the same
/// definitions when it resolves bundled resources and constructs RealityKit
/// templates.
enum ReplayAssetCatalog {
    static let resourceSubdirectory = "Replay3D"

    static let supportedSports: [Sport] = [.rower, .skierg, .bike]

    /// Common athlete visual nodes required by every sport rig asset.
    static let commonRigNodeNames: [String] = [
        "visual-pelvis",
        "visual-torso",
        "visual-head",
        "visual-upperArm-L",
        "visual-forearm-L",
        "visual-hand-L",
        "visual-upperArm-R",
        "visual-forearm-R",
        "visual-hand-R",
        "visual-thigh-L",
        "visual-shin-L",
        "visual-foot-L",
        "visual-thigh-R",
        "visual-shin-R",
        "visual-foot-R",
    ]

    /// Nodes required in every sport environment asset.
    static let environmentNodeNames: [String] = [
        "environment-root",
        "environment-ground",
        "environment-props",
    ]

    static let budget = ReplayAssetBudget(
        maximumRigTriangleCount: 18_000,
        maximumEnvironmentTriangleCount: 30_000,
        combinedByteLimitExclusive: 15 * 1_024 * 1_024
    )

    /// The canonical, deterministic order used by generation and bundle checks.
    static let resources: [ReplayAssetResource] = supportedSports.flatMap { sport in
        [rigResource(for: sport), environmentResource(for: sport)]
    }

    static var resourceNames: [String] { resources.map(\.fileName) }

    static func resources(for sport: Sport) -> [ReplayAssetResource] {
        [rigResource(for: sport), environmentResource(for: sport)]
    }

    static func rigResource(for sport: Sport) -> ReplayAssetResource {
        ReplayAssetResource(sport: sport, kind: .rig)
    }

    static func environmentResource(for sport: Sport) -> ReplayAssetResource {
        ReplayAssetResource(sport: sport, kind: .environment)
    }

    static func requiredNodeNames(for resource: ReplayAssetResource) -> [String] {
        switch resource.kind {
        case .rig:
            requiredRigNodeNames(for: resource.sport)
        case .environment:
            environmentNodeNames
        }
    }

    /// A rig must have mesh geometry at every visual attachment point. The
    /// environment root is intentionally an organizational Xform, while its
    /// ground and props must both carry actual geometry.
    static func requiredGeometryNodeNames(for resource: ReplayAssetResource) -> [String] {
        switch resource.kind {
        case .rig:
            requiredRigNodeNames(for: resource.sport)
        case .environment:
            ["environment-ground", "environment-props"]
        }
    }

    /// USD prim identifiers cannot contain hyphens. Generated USDA therefore
    /// stores this reversible identifier and carries the public logical name in
    /// `rowplay:logicalName` metadata. The rest of the replay graph only sees
    /// the stable hyphenated logical names from this catalog.
    static func bundledPrimName(for logicalNodeName: String) -> String {
        logicalNodeName.replacingOccurrences(of: "-", with: "_")
    }

    static func requiredRigNodeNames(for sport: Sport) -> [String] {
        commonRigNodeNames + sportSpecificRigNodeNames(for: sport)
    }

    static func sportSpecificRigNodeNames(for sport: Sport) -> [String] {
        switch sport {
        case .rower:
            [
                "visual-hull",
                "visual-deck-stripe",
                "visual-footplate",
                "visual-rail",
                "visual-seat",
                "visual-handle",
                "visual-oar-port",
                "visual-oar-starboard",
            ]
        case .skierg:
            [
                "visual-post-L",
                "visual-post-R",
                "visual-topBar",
                "visual-platform",
                "visual-handle-L",
                "visual-handle-R",
                "visual-pole-L",
                "visual-pole-R",
                "visual-cable",
            ]
        case .bike:
            [
                "visual-wheel-front",
                "visual-wheel-rear",
                "visual-downTube",
                "visual-seatTube",
                "visual-topTube",
                "visual-cranks",
                "visual-chainRing",
                "visual-pedal-L",
                "visual-pedal-R",
                "visual-handlebar",
                "visual-saddle",
            ]
        }
    }

    /// Named UsdPreviewSurface material categories required for the generated
    /// resource. These are semantic material roles, not hard-coded colours.
    static func requiredMaterialCategories(for resource: ReplayAssetResource) -> [String] {
        switch (resource.sport, resource.kind) {
        case (_, .rig):
            ["skin", "hair", "kit", "shoe", "accent", "metal", "rubber"]
        case (.rower, .environment):
            ["water", "shore", "foliage", "accent", "metal"]
        case (.skierg, .environment):
            ["snow", "ice", "foliage", "accent", "metal"]
        case (.bike, .environment):
            ["asphalt", "concrete", "accent", "metal", "foliage"]
        }
    }

    /// Exact min/max values emitted into the deterministic golden fixture.
    static func expectedBounds(for resource: ReplayAssetResource) -> ReplayAssetBounds {
        switch (resource.sport, resource.kind) {
        case (.rower, .rig):
            ReplayAssetBounds(
                minimum: SIMD3(-2.67, -0.4175, -1.55),
                maximum: SIMD3(2.67, 0.42, 1.55)
            )
        case (.rower, .environment):
            ReplayAssetBounds(
                minimum: SIMD3(-67, -0.105, -60),
                maximum: SIMD3(67, 6.08, 60)
            )
        case (.skierg, .rig):
            ReplayAssetBounds(
                minimum: SIMD3(-0.41, -1.2, -0.31),
                maximum: SIMD3(0.41, 0.9, 0.31)
            )
        case (.skierg, .environment):
            ReplayAssetBounds(
                minimum: SIMD3(-60, -0.12, -60),
                maximum: SIMD3(60, 6.65, 60)
            )
        case (.bike, .rig):
            ReplayAssetBounds(
                minimum: SIMD3(-0.39, -0.475, -0.8),
                maximum: SIMD3(0.39, 0.475, 0.8)
            )
        case (.bike, .environment):
            ReplayAssetBounds(
                minimum: SIMD3(-60, -0.13, -60),
                maximum: SIMD3(60, 5.13, 60)
            )
        }
    }

    /// Low always retains the lightweight procedural path. The other tiers can
    /// choose bundled assets only after their complete sport set validates.
    static func bundledVisualsAreEligible(at effectiveQuality: ReplayRenderQuality) -> Bool {
        switch effectiveQuality {
        case .low:
            false
        case .medium, .high, .ultra:
            true
        }
    }

    /// Selects an atomic visual source for a scene. A failed or partial bundled
    /// set never produces a mixed rig/environment scene.
    static func visualSource(
        for effectiveQuality: ReplayRenderQuality,
        assetSetIsValid: Bool
    ) -> ReplayAssetVisualSource {
        bundledVisualsAreEligible(at: effectiveQuality) && assetSetIsValid
            ? .bundled
            : .procedural
    }

    static func visualSource(
        for effectiveQuality: ReplayRenderQuality,
        validation: ReplayAssetValidationResult
    ) -> ReplayAssetVisualSource {
        visualSource(
            for: effectiveQuality,
            assetSetIsValid: validation.isValid
        )
    }

    /// Validates both files for one sport. This is the decision point used when
    /// constructing a sport scene, so a missing environment rejects its rig too.
    static func validateAssetSet(
        for sport: Sport,
        inspections: [ReplayAssetInspection]
    ) -> ReplayAssetValidationResult {
        let expectedResources = resources(for: sport)
        let inspectionsByResource = Dictionary(grouping: inspections, by: \.resource)
        var failures: [ReplayAssetValidationFailure] = []

        for inspection in inspections where !expectedResources.contains(inspection.resource) {
            failures.append(.unexpectedResource(inspection.resource))
        }

        for resource in expectedResources {
            let matches = inspectionsByResource[resource] ?? []
            switch matches.count {
            case 0:
                failures.append(.missingResource(resource))
            case 1:
                failures.append(contentsOf: validate(matches[0]))
            default:
                failures.append(.duplicateResource(resource))
            }
        }

        return ReplayAssetValidationResult(failures: failures)
    }

    /// Validates the full six-resource package, including its strict combined
    /// size limit. Per-sport callers should use `validateAssetSet` so an invalid
    /// SkiErg asset cannot unnecessarily block a valid RowErg fallback decision.
    static func validateBundle(
        inspections: [ReplayAssetInspection]
    ) -> ReplayAssetValidationResult {
        var failures: [ReplayAssetValidationFailure] = []

        for sport in supportedSports {
            let sportInspections = inspections.filter {
                $0.resource.sport.rawValue == sport.rawValue
            }
            failures.append(contentsOf: validateAssetSet(
                for: sport,
                inspections: sportInspections
            ).failures)
        }

        let totalByteCount = combinedByteCount(of: inspections)
        if totalByteCount >= budget.combinedByteLimitExclusive {
            failures.append(.combinedByteBudgetExceeded(
                actual: totalByteCount,
                limitExclusive: budget.combinedByteLimitExclusive
            ))
        }

        return ReplayAssetValidationResult(failures: failures)
    }

    private static func validate(
        _ inspection: ReplayAssetInspection
    ) -> [ReplayAssetValidationFailure] {
        var failures: [ReplayAssetValidationFailure] = []

        for nodeName in requiredNodeNames(for: inspection.resource) {
            let count = inspection.nodeNames.reduce(into: 0) { partialResult, candidate in
                if candidate == nodeName {
                    partialResult += 1
                }
            }
            switch count {
            case 0:
                failures.append(.missingRequiredNode(
                    resource: inspection.resource,
                    name: nodeName
                ))
            case 1:
                break
            default:
                failures.append(.duplicateRequiredNode(
                    resource: inspection.resource,
                    name: nodeName
                ))
            }
        }

        for nodeName in requiredGeometryNodeNames(for: inspection.resource)
        where !inspection.geometryNodeNames.contains(nodeName) {
            failures.append(.missingRequiredNodeGeometry(
                resource: inspection.resource,
                name: nodeName
            ))
        }

        if !inspection.hasGeometry {
            failures.append(.missingGeometry(inspection.resource))
        }
        if !inspection.hasFiniteTransforms {
            failures.append(.nonFiniteTransforms(inspection.resource))
        }
        if !inspection.hasFiniteNormals {
            failures.append(.nonFiniteNormals(inspection.resource))
        }
        if !inspection.hasFiniteBounds {
            failures.append(.nonFiniteBounds(inspection.resource))
        }
        if inspection.containsCamera {
            failures.append(.containsCamera(inspection.resource))
        }
        if inspection.containsLight {
            failures.append(.containsLight(inspection.resource))
        }
        for material in requiredMaterialCategories(for: inspection.resource)
        where !inspection.materialCategories.contains(material) {
            failures.append(.missingRequiredMaterial(
                resource: inspection.resource,
                name: material
            ))
        }
        guard let bounds = inspection.bounds,
              bounds.hasFiniteNonemptyExtent else {
            failures.append(.invalidBounds(inspection.resource))
            return failures
        }
        if bounds != expectedBounds(for: inspection.resource) {
            failures.append(.unexpectedBounds(
                resource: inspection.resource,
                actual: bounds,
                expected: expectedBounds(for: inspection.resource)
            ))
        }
        if inspection.triangleCount < 0 {
            failures.append(.invalidTriangleCount(
                resource: inspection.resource,
                actual: inspection.triangleCount
            ))
        } else {
            let maximum = budget.maximumTriangleCount(for: inspection.resource.kind)
            if inspection.triangleCount > maximum {
                failures.append(.triangleBudgetExceeded(
                    resource: inspection.resource,
                    actual: inspection.triangleCount,
                    maximum: maximum
                ))
            }
        }
        if inspection.byteCount < 0 {
            failures.append(.invalidByteCount(
                resource: inspection.resource,
                actual: inspection.byteCount
            ))
        }

        return failures
    }

    private static func combinedByteCount(of inspections: [ReplayAssetInspection]) -> Int {
        var total: UInt64 = 0
        for inspection in inspections where inspection.byteCount > 0 {
            let (next, overflowed) = total.addingReportingOverflow(UInt64(inspection.byteCount))
            total = overflowed ? .max : next
        }

        if total > UInt64(Int.max) {
            return Int.max
        }
        return Int(total)
    }
}
