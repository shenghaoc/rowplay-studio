import AppKit
import CoreGraphics
import Metal
import RealityKit
import RowPlayCore

struct ReplayAthleteSurfaceMaterialProfile: Equatable, Sendable {
    let roughness: Float
    let metallic: Float
    let clearcoat: Float
    let clearcoatRoughness: Float
    let specular: Float
    let anisotropy: Float
}

/// Pinned V4 athlete material contract expressed in native PBR parameters.
/// Geometry/contact work is identical at every tier; visible surface response
/// and deterministic normal-map resolution form the athlete quality ladder.
enum ReplayAthleteMaterialProfile {
    static func detailTextureSize(for quality: ReplayRenderQuality) -> Int {
        switch quality {
        case .low: 0
        case .medium: 128
        case .high: 256
        case .ultra: 512
        }
    }

    static func detailStrength(for quality: ReplayRenderQuality) -> Float {
        switch quality {
        case .low: 0
        case .medium: 0.055
        case .high: 0.1
        case .ultra: 0.15
        }
    }

    static func profile(
        for role: ReplayAthleteSurfaceRole,
        quality: ReplayRenderQuality
    ) -> ReplayAthleteSurfaceMaterialProfile {
        let index = qualityIndex(quality)
        switch role {
        case .skin:
            return make(
                index,
                roughness: [0.78, 0.66, 0.50, 0.43],
                metallic: [0, 0, 0, 0],
                clearcoat: [0, 0.015, 0.022, 0.035],
                clearcoatRoughness: [0.70, 0.55, 0.46, 0.38],
                specular: [0.55, 0.70, 0.84, 0.94]
            )
        case .jersey:
            return make(
                index,
                roughness: [0.94, 0.86, 0.78, 0.74],
                metallic: [0, 0, 0, 0],
                clearcoat: [0, 0.005, 0.01, 0.012],
                clearcoatRoughness: [0.80, 0.65, 0.46, 0.36],
                specular: [0.45, 0.56, 0.62, 0.70],
                anisotropy: [0, 0.08, 0.20, 0.34]
            )
        case .lower:
            return make(
                index,
                roughness: [0.92, 0.82, 0.68, 0.60],
                metallic: [0, 0, 0, 0],
                clearcoat: [0, 0.005, 0.008, 0.01],
                clearcoatRoughness: [0.80, 0.62, 0.44, 0.34],
                specular: [0.45, 0.60, 0.80, 0.92],
                anisotropy: [0, 0.08, 0.20, 0.34]
            )
        case .footwear:
            return make(
                index,
                roughness: [0.78, 0.62, 0.36, 0.24],
                metallic: [0, 0.01, 0.03, 0.05],
                clearcoat: [0, 0.045, 0.18, 0.32],
                clearcoatRoughness: [0.70, 0.48, 0.28, 0.20],
                specular: [0.55, 0.72, 0.96, 1.08]
            )
        case .hair:
            return make(
                index,
                roughness: [0.80, 0.78, 0.74, 0.70],
                metallic: [0, 0, 0, 0],
                clearcoat: [0, 0, 0, 0],
                clearcoatRoughness: [0.75, 0.62, 0.55, 0.48],
                specular: [0.36, 0.42, 0.46, 0.50],
                anisotropy: [0.03, 0.10, 0.20, 0.35]
            )
        case .trim:
            return make(
                index,
                roughness: [0.70, 0.54, 0.32, 0.20],
                metallic: [0.02, 0.035, 0.09, 0.14],
                clearcoat: [0.01, 0.07, 0.24, 0.38],
                clearcoatRoughness: [0.60, 0.42, 0.26, 0.18],
                specular: [0.60, 0.74, 1.0, 1.08],
                anisotropy: [0, 0.04, 0.10, 0.18]
            )
        case .eye:
            return make(
                index,
                roughness: [0.34, 0.25, 0.17, 0.10],
                metallic: [0, 0, 0, 0],
                clearcoat: [0.08, 0.16, 0.26, 0.38],
                clearcoatRoughness: [0.34, 0.24, 0.17, 0.11],
                specular: [0.82, 0.94, 1.04, 1.14]
            )
        case .faceDetail:
            return make(
                index,
                roughness: [0.68, 0.62, 0.52, 0.46],
                metallic: [0, 0, 0, 0],
                clearcoat: [0, 0, 0.015, 0.025],
                clearcoatRoughness: [0.70, 0.65, 0.52, 0.44],
                specular: [0.50, 0.58, 0.74, 0.82]
            )
        }
    }

    static func baseColor(for role: ReplayAthleteSurfaceRole) -> NSColor {
        switch role {
        case .skin: color(0.69, 0.405, 0.285)
        case .jersey: color(0.18, 0.28, 0.52)
        case .lower: color(0.075, 0.12, 0.15)
        case .footwear: color(0.24, 0.28, 0.32)
        case .hair: color(0.18, 0.075, 0.028)
        case .trim: color(0.26, 0.38, 0.72)
        case .eye: color(0.86, 0.82, 0.75)
        case .faceDetail: color(0.29, 0.12, 0.09)
        }
    }

    static func detailRepeat(for role: ReplayAthleteSurfaceRole) -> SIMD2<Float> {
        switch role {
        case .skin: SIMD2(4, 4)
        case .jersey: SIMD2(14, 12)
        case .lower: SIMD2(12, 14)
        case .footwear: SIMD2(10, 10)
        case .hair: SIMD2(22, 6)
        case .trim: SIMD2(18, 10)
        case .eye: SIMD2(1, 1)
        case .faceDetail: SIMD2(5, 5)
        }
    }

    static func detailMultiplier(for role: ReplayAthleteSurfaceRole) -> Float {
        switch role {
        case .skin: 0.62
        case .jersey: 1
        case .lower: 0.88
        case .footwear: 0.8
        case .hair: 0.48
        case .trim: 0.62
        case .eye: 0
        case .faceDetail: 0.28
        }
    }

    static func normalTexture(
        resource: TextureResource,
        role: ReplayAthleteSurfaceRole
    ) -> PhysicallyBasedMaterial.Texture {
        var sampler = MaterialParameters.Texture.Sampler()
        sampler.modify { descriptor in
            descriptor.sAddressMode = .repeat
            descriptor.tAddressMode = .repeat
            descriptor.minFilter = .linear
            descriptor.magFilter = .linear
            descriptor.mipFilter = .linear
        }
        return PhysicallyBasedMaterial.Texture(resource, sampler: sampler)
    }

    private static func qualityIndex(_ quality: ReplayRenderQuality) -> Int {
        switch quality {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .ultra: 3
        }
    }

    private static func make(
        _ index: Int,
        roughness: [Float],
        metallic: [Float],
        clearcoat: [Float],
        clearcoatRoughness: [Float],
        specular: [Float],
        anisotropy: [Float] = [0, 0, 0, 0]
    ) -> ReplayAthleteSurfaceMaterialProfile {
        ReplayAthleteSurfaceMaterialProfile(
            roughness: roughness[index],
            metallic: metallic[index],
            clearcoat: clearcoat[index],
            clearcoatRoughness: clearcoatRoughness[index],
            specular: specular[index],
            anisotropy: anisotropy[index]
        )
    }

    private static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }
}

/// Process-shared GPU detail maps. Each selected tier is generated at most
/// once; live/rival clones and later scene rebuilds reuse the same immutable
/// TextureResources. Pixel generation runs off MainActor and no network or
/// user data enters the map.
@MainActor
final class ReplayAthleteMaterialLibrary {
    static let shared = ReplayAthleteMaterialLibrary()

    private var cache: [String: [ReplayAthleteSurfaceRole: TextureResource]] = [:]
    private var failedQualities = Set<String>()
    private var inFlight: [
        String: Task<[ReplayAthleteSurfaceRole: TextureResource]?, Never>
    ] = [:]

    func detailMaps(
        for quality: ReplayRenderQuality
    ) async -> [ReplayAthleteSurfaceRole: TextureResource]? {
        let key = quality.rawValue
        if let cached = cache[key] { return cached }
        guard !failedQualities.contains(key) else { return nil }
        if let task = inFlight[key] { return await task.value }
        let task = Task { @MainActor [weak self] () -> [ReplayAthleteSurfaceRole: TextureResource]? in
            guard let self else { return nil }
            return await self.buildDetailMaps(for: quality)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result {
            cache[key] = result
        } else {
            failedQualities.insert(key)
        }
        return result
    }

    func resetCacheForTesting() {
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
        cache.removeAll()
        failedQualities.removeAll()
    }

    private func buildDetailMaps(
        for quality: ReplayRenderQuality
    ) async -> [ReplayAthleteSurfaceRole: TextureResource]? {
        let size = ReplayAthleteMaterialProfile.detailTextureSize(for: quality)
        guard size > 0 else { return [:] }
        let images = await Task.detached(priority: .userInitiated) {
            ReplayAthleteDetailImageFactory.images(for: quality)
        }.value
        let detailedRoles = ReplayAthleteSurfaceRole.allCases.filter {
            ReplayAthleteMaterialProfile.detailMultiplier(for: $0) > 0
        }
        guard images.count == detailedRoles.count else { return nil }

        var resources: [ReplayAthleteSurfaceRole: TextureResource] = [:]
        for role in detailedRoles {
            guard let image = images[role] else { return nil }
            do {
                let texture = try await TextureResource(
                    image: image,
                    withName: "rowplay-v4-\(quality.rawValue)-\(role.runtimeMaterialName)-normal",
                    options: TextureResource.CreateOptions(
                        semantic: .normal,
                        mipmapsMode: .allocateAndGenerateAll
                    )
                )
                guard texture.width == size, texture.height == size else { return nil }
                resources[role] = texture
            } catch {
                return nil
            }
        }
        return resources
    }
}

private enum ReplayAthleteDetailImageFactory {
    nonisolated static func images(
        for quality: ReplayRenderQuality
    ) -> [ReplayAthleteSurfaceRole: CGImage] {
        let size = ReplayAthleteMaterialProfile.detailTextureSize(for: quality)
        guard size > 0 else { return [:] }
        let detailedRoles = ReplayAthleteSurfaceRole.allCases.filter {
            ReplayAthleteMaterialProfile.detailMultiplier(for: $0) > 0
        }
        return Dictionary(uniqueKeysWithValues: detailedRoles.compactMap { role in
            makeImage(role: role, quality: quality, size: size).map { (role, $0) }
        })
    }

    nonisolated private static func makeImage(
        role: ReplayAthleteSurfaceRole,
        quality: ReplayRenderQuality,
        size: Int
    ) -> CGImage? {
        let strength = ReplayAthleteMaterialProfile.detailStrength(for: quality)
            * ReplayAthleteMaterialProfile.detailMultiplier(for: role)
        let normalized = min(max(strength / 0.15, 0), 1)
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let current = detailSample(role: role, x: x, y: y)
                let dx = detailSample(role: role, x: (x + 1) % size, y: y) - current
                let dy = detailSample(role: role, x: x, y: (y + 1) % size) - current
                let scale = Double(normalized) * 1.7
                let offset = (y * size + x) * 4
                pixels[offset] = byte(128 - dx * scale)
                pixels[offset + 1] = byte(128 - dy * scale)
                pixels[offset + 2] = 255
            }
        }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(
            width: size,
            height: size,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    nonisolated private static func detailSample(
        role: ReplayAthleteSurfaceRole,
        x: Int,
        y: Int
    ) -> Double {
        let grain = Double((x * 29 + y * 17 + x * y * 7) % 17 - 8)
        let stripe = sin((Double(x) + Double(y) * 0.24) * .pi * 0.72)
        switch role {
        case .jersey:
            return 126 + (x.isMultiple(of: 4) || y.isMultiple(of: 5) ? 28 : -10) + grain * 0.65
        case .lower:
            return 126 + (x.isMultiple(of: 5) || (x + y).isMultiple(of: 7) ? 22 : -9) + grain * 0.55
        case .footwear:
            return 126 + ((x + y * 2) % 8 < 2 ? 24 : -12) + grain * 0.45
        case .hair:
            return 126 + stripe * 31 + grain * 0.35
        case .trim:
            return 126 + (x.isMultiple(of: 3) ? 24 : -12) + grain * 0.4
        case .skin:
            return 126 + grain * 0.8 + sin((Double(x) * 0.61 + Double(y) * 0.37) * .pi) * 4
        case .eye:
            return 126
        case .faceDetail:
            return 126 + grain * 0.22
        }
    }

    nonisolated private static func byte(_ value: Double) -> UInt8 {
        UInt8(min(max(value.rounded(), 0), 255))
    }
}
