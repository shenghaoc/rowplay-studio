import AppKit
import Foundation
import RealityKit

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
    /// Environment detail threshold at which surface maps switch on (High).
    static let texturedDetailThreshold = 2
    /// Environment detail threshold at which normal maps join (Ultra).
    static let normalMappedDetailThreshold = 3

    private let bundle: Bundle
    private var textureCache: [String: TextureResource] = [:]
    private var failedTextureKeys: Set<String> = []

    init(bundle: Bundle = .module) {
        self.bundle = bundle
    }

    // MARK: - Materials

    /// A physically based venue material for the given tier.
    ///
    /// - Parameters:
    ///   - family: CC0 family to bind at High/Ultra, or nil for an always
    ///     solid material.
    ///   - baseColor: Authored tint. At High/Ultra the diffuse map multiplies
    ///     it, matching the web's map-times-color behavior.
    ///   - roughness: Scalar roughness; multiplied by the roughness map when
    ///     one is bound.
    ///   - tier: Environment detail level 0...3.
    ///   - textureRepeat: UV tiling applied through the material's texture
    ///     coordinate transform (the web per-texture `repeat`).
    ///   - metallic: Scalar metallic response.
    func material(
        family: ReplayEnvironmentTextureFamily?,
        baseColor: NSColor,
        roughness: Float,
        tier: Int,
        textureRepeat: SIMD2<Float> = SIMD2(1, 1),
        metallic: Float = 0
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: baseColor)
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: metallic)

        guard let family, tier >= Self.texturedDetailThreshold else {
            return material
        }

        if let diffuse = texture(family: family, slot: .diffuse) {
            material.baseColor = .init(tint: baseColor, texture: .init(diffuse))
        }
        if let roughnessMap = texture(family: family, slot: .roughness) {
            material.roughness = .init(scale: roughness, texture: .init(roughnessMap))
        }
        if tier >= Self.normalMappedDetailThreshold,
            let normalMap = texture(family: family, slot: .normal) {
            // RealityKit has no per-material normal scale; the web's
            // `normalScale` tuning is dropped rather than approximated.
            material.normal = .init(texture: .init(normalMap))
        }
        material.textureCoordinateTransform = .init(
            offset: SIMD2(0, 0),
            scale: textureRepeat,
            rotation: 0
        )
        return material
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
        guard
            let url = bundle.url(
                forResource: "\(family.fileBaseName)-\(slot.fileSuffix)",
                withExtension: "jpg",
                subdirectory: family.subdirectory
            ),
            let resource = try? TextureResource.load(
                contentsOf: url,
                options: .init(semantic: slot.semantic)
            )
        else {
            // Missing or undecodable map: fall back to the solid authored
            // color for this slot, exactly like the web's onError path.
            failedTextureKeys.insert(key)
            return nil
        }
        textureCache[key] = resource
        return resource
    }
}
