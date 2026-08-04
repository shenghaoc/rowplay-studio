import AppKit
import Foundation
import RealityKit
import RowPlayCore

/// The provenance-recorded CC0 surface families bundled with the app under
/// `ReplayReference/environment/textures/<family>/`.
///
/// Files follow the web deploy's naming: `<base>-diffuse-512.jpg`,
/// `<base>-roughness-512.jpg`, and `<base>-normal-gl-512.jpg`, where `<base>`
/// is the family name for every family except `snow-02`, whose files are
/// shipped as `snow-*.jpg`.
enum ReplayEnvironmentTextureFamily: String, CaseIterable, Sendable {
    case aerialGrassRock = "aerial-grass-rock"
    case barkBrown01 = "bark-brown-01"
    case brownPlanks03 = "brown-planks-03"
    case brushedConcrete2 = "brushed-concrete-2"
    case cobblestoneFloor03 = "cobblestone-floor-03"
    case concreteFloorPainted = "concrete-floor-painted"
    case dryRiverPebbles = "dry-river-pebbles"
    case forestLeaves04 = "forest-leaves-04"
    case forrestGround01 = "forrest-ground-01"
    case leafyGrass = "leafy-grass"
    case rock01 = "rock-01"
    case snow02 = "snow-02"
    case woodFloor = "wood-floor"

    /// Directory inside the module bundle holding this family's triplet.
    var subdirectory: String {
        "ReplayReference/environment/textures/\(rawValue)"
    }

    /// File-name stem for the family's maps.
    var fileBaseName: String {
        self == .snow02 ? "snow" : rawValue
    }
}

/// The three PBR slots a CC0 family can fill.
enum ReplayEnvironmentTextureSlot: String, Sendable {
    case diffuse
    case roughness
    case normal

    /// File-name suffix after the family base name.
    var fileSuffix: String {
        switch self {
        case .diffuse: "diffuse-512"
        case .roughness: "roughness-512"
        case .normal: "normal-gl-512"
        }
    }

    /// Only the diffuse map is color data; the others stay linear.
    var semantic: TextureResource.Semantic {
        switch self {
        case .diffuse: .color
        case .roughness: .raw
        case .normal: .normal
        }
    }
}

enum ReplayEnvironmentTextureFailure: String, Equatable, Sendable {
    case missingResource
    case loadFailed
}

/// Loads and caches the bundled CC0 texture triplets and assembles the venue
/// materials the environment builder uses.
///
/// Tier policy mirrors the web `applyEnvironmentSurfaceMaps`: Low and Medium
/// keep solid procedural colors so the venue identity never depends on an
/// image decode; High binds diffuse + roughness; Ultra adds the OpenGL-style
/// normal map. A failed load degrades that slot back to the solid color — a
/// broken map must never replace the authored tint.
@MainActor
final class ReplayEnvironmentMaterialLibrary {
    static let shared = ReplayEnvironmentMaterialLibrary()
    private static let logger = PrivacySafeLogger(category: "replay-environment-texture")

    private let resourceResolver: (ReplayEnvironmentTextureFamily, ReplayEnvironmentTextureSlot) -> URL?
    private let textureLoader: (URL, TextureResource.Semantic) throws -> TextureResource
    private let failureReporter: (String, ReplayEnvironmentTextureFailure) -> Void
    private var textureCache: [String: TextureResource] = [:]
    private var failedTextureKeys: Set<String> = []

    init(
        bundle: Bundle = .module,
        resourceResolver: ((ReplayEnvironmentTextureFamily, ReplayEnvironmentTextureSlot) -> URL?)? = nil,
        textureLoader: ((URL, TextureResource.Semantic) throws -> TextureResource)? = nil,
        failureReporter: ((String, ReplayEnvironmentTextureFailure) -> Void)? = nil
    ) {
        self.resourceResolver = resourceResolver ?? { family, slot in
            bundle.url(
                forResource: "\(family.fileBaseName)-\(slot.fileSuffix)",
                withExtension: "jpg",
                subdirectory: family.subdirectory
            )
        }
        self.textureLoader = textureLoader ?? { url, semantic in
            try TextureResource.load(
                contentsOf: url,
                options: .init(semantic: semantic)
            )
        }
        self.failureReporter = failureReporter ?? { key, failure in
            ReplayEnvironmentMaterialLibrary.logger.warn(
                "Replay environment texture rejected",
                key,
                failure.rawValue
            )
        }
    }

    // MARK: - Materials

    /// A physically based primary-receiver material for the given quality.
    ///
    /// - Parameters:
    ///   - family: CC0 family to bind at High/Ultra, or nil for an always
    ///     solid material.
    ///   - baseColor: Authored tint. At High/Ultra the diffuse map multiplies
    ///     it, matching the web's map-times-color behavior.
    ///   - roughness: Scalar roughness; multiplied by the roughness map when
    ///     one is bound.
    ///   - quality: Low/Medium use scalar values, High adds diffuse and
    ///     roughness maps, and Ultra also adds the normal map.
    ///   - textureRepeat: UV tiling applied through the material's texture
    ///     coordinate transform (the web per-texture `repeat`).
    ///   - metallic: Scalar metallic response.
    func material(
        family: ReplayEnvironmentTextureFamily?,
        baseColor: NSColor,
        roughness: Float,
        quality: ReplayRenderQuality,
        textureRepeat: SIMD2<Float> = SIMD2(1, 1),
        metallic: Float = 0
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: baseColor)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: metallic)

        guard let family, Self.usesSurfaceMaps(at: quality) else {
            return material
        }

        var boundMap = false
        if let diffuse = texture(family: family, slot: .diffuse) {
            material.baseColor = .init(tint: baseColor, texture: .init(diffuse))
            boundMap = true
        }
        if let roughnessMap = texture(family: family, slot: .roughness) {
            material.roughness = .init(scale: roughness, texture: .init(roughnessMap))
            boundMap = true
        }
        if Self.usesNormalMap(at: quality),
            let normalMap = texture(family: family, slot: .normal) {
            // RealityKit has no per-material normal scale; the web's
            // `normalScale` tuning is dropped rather than approximated.
            material.normal = .init(texture: .init(normalMap))
            boundMap = true
        }
        if boundMap {
            material.textureCoordinateTransform = .init(
                offset: SIMD2(0, 0),
                scale: textureRepeat,
                rotation: 0
            )
        }
        return material
    }

    static func usesSurfaceMaps(at quality: ReplayRenderQuality) -> Bool {
        quality == .high || quality == .ultra
    }

    static func usesNormalMap(at quality: ReplayRenderQuality) -> Bool {
        quality == .ultra
    }

    // MARK: - Textures

    /// The cached texture for one family slot, or nil when the resource is
    /// missing or fails to decode. Failures are remembered so a broken file
    /// is probed once per library, never per material.
    func texture(
        family: ReplayEnvironmentTextureFamily,
        slot: ReplayEnvironmentTextureSlot
    ) -> TextureResource? {
        let key = "\(family.rawValue)/\(slot.rawValue)"
        if let cached = textureCache[key] {
            return cached
        }
        if failedTextureKeys.contains(key) {
            return nil
        }
        guard let url = resourceResolver(family, slot) else {
            reject(key: key, because: .missingResource)
            return nil
        }
        do {
            let resource = try textureLoader(url, slot.semantic)
            textureCache[key] = resource
            return resource
        } catch {
            // Missing or undecodable maps retain the scalar authored material;
            // diagnostics use stable bundle keys and never raw filesystem paths.
            reject(key: key, because: .loadFailed)
            return nil
        }
    }

    private func reject(
        key: String,
        because failure: ReplayEnvironmentTextureFailure
    ) {
        if failedTextureKeys.insert(key).inserted {
            failureReporter(key, failure)
        }
    }
}
