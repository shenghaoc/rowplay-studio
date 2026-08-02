import Foundation
import RealityKit
import RowPlayCore
import SwiftUI

/// Seam between the scene builder and the native venue construction.
///
/// Construction failure returns `nil`, keeping the caller's procedural ground
/// enabled — the venue never partially installs.
@MainActor
enum ReplayEnvironmentInstaller {
    static func install(
        sport: Sport,
        quality: ReplayRenderQuality,
        colorScheme: ColorScheme
    ) -> Entity? {
        let plan = ReplayEnvironmentPlan.plan(for: sport)
        let profile = ReplayQualitySceneProfile.profile(for: quality)
        let theme: ReplayEnvironmentTheme = colorScheme == .dark ? .dark : .light
        let materials = ReplayEnvironmentMaterialLibrary()
        let root = Entity()
        root.name = "premium-environment-\(sport.rawValue)-\(quality.rawValue)"

        let groundFamily: ReplayEnvironmentTextureFamily = switch sport {
        case .rower: .aerialGrassRock
        case .skierg: .snow02
        case .bike: .woodFloor
        }
        let ground = ModelEntity(
            mesh: .generatePlane(width: 170, depth: 170),
            materials: [materials.material(
                family: groundFamily,
                baseColor: color(plan.courseStyle.groundColor, theme: theme),
                roughness: Float(plan.courseStyle.roughness),
                tier: profile.environmentDetail,
                textureRepeat: SIMD2(14, 14),
                metallic: Float(plan.courseStyle.metalness)
            )]
        )
        ground.name = "venue-ground"
        ground.position.y = -0.04
        root.addChild(ground)

        let dressing = Entity()
        dressing.name = "venue-dressing-level-\(profile.environmentDetail)"
        root.addChild(dressing)

        switch sport {
        case .rower:
            guard let venue = plan.rower else { return nil }
            buildRower(venue, plan: plan, profile: profile, theme: theme, into: dressing)
        case .skierg:
            guard let venue = plan.skierg else { return nil }
            buildSki(venue, plan: plan, profile: profile, theme: theme, into: dressing)
        case .bike:
            guard let venue = plan.bike else { return nil }
            buildBike(venue, plan: plan, profile: profile, theme: theme, into: dressing)
        }
        return root
    }

    private static func buildRower(
        _ venue: ReplayRowerVenuePlan,
        plan: ReplayEnvironmentPlan,
        profile: ReplayQualitySceneProfile,
        theme: ReplayEnvironmentTheme,
        into root: Entity
    ) {
        let water = simple(plan.courseStyle.surface, theme: theme, roughness: 0.18)
        addDisk(name: "regatta-basin", radius: 38, height: 0.025, y: 0, material: water, to: root)
        let island = simple(plan.lighting.infield, theme: theme, roughness: 0.9)
        addDisk(name: "island-park", radius: Float(venue.islandRadius), height: 0.18, y: 0.08, material: island, to: root)
        let structure = simple(plan.lighting.venueStructure, theme: theme)
        for (index, placement) in venue.landmarks.prefix(venue.landmarkCounts[profile.environmentDetail]).enumerated() {
            addLandmark(placement, name: "rowing-landmark-\(index)-\(placement.name)", material: structure, to: root)
        }
        let foliage = simple(plan.lighting.midSilhouette, theme: theme, roughness: 1)
        let treeCount = venue.islandTreeCounts[profile.environmentDetail]
        addRingMarkers(count: treeCount, radius: Float(venue.islandRadius * 0.72), y: 0.65,
                       size: SIMD3(0.35, 1.25, 0.35), prefix: "island-tree", material: foliage, to: root)
        let buoy = simple(plan.lighting.venueAccent, theme: theme, roughness: 0.45)
        for (ringIndex, radius) in venue.buoyRingRadii.enumerated() {
            addRingMarkers(count: profile.buoysPerRing, radius: Float(radius), y: 0.12,
                           size: SIMD3(0.12, 0.22, 0.12), prefix: "buoy-\(ringIndex)", material: buoy, to: root)
        }
        addQualityLandmarks(profile.environmentDetail, sport: .rower, material: foliage, to: root)
    }

    private static func buildSki(
        _ venue: ReplaySkiVenuePlan,
        plan: ReplayEnvironmentPlan,
        profile: ReplayQualitySceneProfile,
        theme: ReplayEnvironmentTheme,
        into root: Entity
    ) {
        let snow = simple(plan.courseStyle.surface, theme: theme, roughness: 0.92)
        addDisk(name: "nordic-stadium-field", radius: Float(venue.stadiumFieldRadius), height: 0.04, y: 0, material: snow, to: root)
        let structure = simple(plan.lighting.venueStructure, theme: theme)
        for (index, placement) in venue.landmarks.prefix(venue.landmarkCounts[profile.environmentDetail]).enumerated() {
            addLandmark(placement, name: "ski-landmark-\(index)-\(placement.name)", material: structure, to: root)
        }
        let pine = simple(plan.lighting.midSilhouette, theme: theme, roughness: 1)
        let forestCount = venue.forestTreeCounts[profile.environmentDetail]
        addRingMarkers(count: forestCount, radius: Float((venue.forestRadiusMin + venue.forestRadiusMax) * 0.5), y: 1.1,
                       size: SIMD3(0.45, 2.2, 0.45), prefix: "nordic-pine", material: pine, to: root)
        let light = simple(venue.floodlightPoolColor, theme: theme, roughness: 0.3)
        for (index, placement) in venue.floodlights.prefix(venue.floodlightMastCounts[profile.environmentDetail]).enumerated() {
            addLandmark(placement, name: "floodlight-\(index)", material: light, to: root)
        }
        addQualityLandmarks(profile.environmentDetail, sport: .skierg, material: pine, to: root)
    }

    private static func buildBike(
        _ venue: ReplayBikeVenuePlan,
        plan: ReplayEnvironmentPlan,
        profile: ReplayQualitySceneProfile,
        theme: ReplayEnvironmentTheme,
        into root: Entity
    ) {
        let timber = simple(plan.courseStyle.surface, theme: theme, roughness: 0.48)
        addDisk(name: "velodrome-track", radius: Float(plan.course.outerRadius), height: 0.06, y: 0, material: timber, to: root)
        let infield = simple(plan.lighting.infield, theme: theme, roughness: 0.8)
        addDisk(name: "velodrome-infield", radius: Float(venue.infieldFloorRadius), height: 0.08, y: 0.04, material: infield, to: root)
        let wall = simple(plan.lighting.venueStructure, theme: theme, roughness: 0.72)
        addRingMarkers(count: 16 + profile.environmentDetail * 8, radius: Float(venue.arenaWallRadius),
                       y: Float(venue.arenaWallHeight * 0.45), size: SIMD3(5.5, Float(venue.arenaWallHeight), 0.4),
                       prefix: "arena-wall", material: wall, to: root)
        let accent = simple(plan.lighting.venueAccent, theme: theme, roughness: 0.42)
        addLandmark(venue.scoreboard, name: "velodrome-scoreboard", material: accent, to: root)
        addLandmark(venue.serviceBuilding, name: "velodrome-service", material: wall, to: root)
        addQualityLandmarks(profile.environmentDetail, sport: .bike, material: accent, to: root)
    }

    private static func addQualityLandmarks(
        _ detail: Int,
        sport: Sport,
        material: SimpleMaterial,
        to root: Entity
    ) {
        let count = [0, 4, 10, 18][max(0, min(3, detail))]
        addRingMarkers(count: count, radius: 48 + Float(detail * 4), y: 1.3,
                       size: SIMD3(0.55, 2.6, 0.55), prefix: "\(sport.rawValue)-quality-dressing",
                       material: material, to: root)
    }

    private static func addLandmark(
        _ placement: ReplayEnvironmentPlacement,
        name: String,
        material: SimpleMaterial,
        to root: Entity
    ) {
        let angle = Float(placement.angleRadians)
        let entity = ModelEntity(
            mesh: .generateBox(size: SIMD3(Float(placement.scale.x), Float(placement.scale.y), Float(placement.scale.z))),
            materials: [material]
        )
        entity.name = name
        entity.position = SIMD3(Float(placement.radius) * sin(angle), Float(placement.scale.y) * 0.5, Float(placement.radius) * cos(angle))
        entity.orientation = simd_quatf(angle: angle, axis: SIMD3(0, 1, 0))
        root.addChild(entity)
    }

    private static func addRingMarkers(
        count: Int,
        radius: Float,
        y: Float,
        size: SIMD3<Float>,
        prefix: String,
        material: SimpleMaterial,
        to root: Entity
    ) {
        guard count > 0 else { return }
        let mesh = MeshResource.generateBox(size: size)
        for index in 0..<count {
            let angle = Float(index) / Float(count) * .pi * 2
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.name = "\(prefix)-\(index)"
            entity.position = SIMD3(radius * sin(angle), y, radius * cos(angle))
            entity.orientation = simd_quatf(angle: angle, axis: SIMD3(0, 1, 0))
            root.addChild(entity)
        }
    }

    private static func addDisk(
        name: String,
        radius: Float,
        height: Float,
        y: Float,
        material: SimpleMaterial,
        to root: Entity
    ) {
        let disk = ModelEntity(mesh: .generateCylinder(height: height, radius: radius), materials: [material])
        disk.name = name
        disk.position.y = y
        root.addChild(disk)
    }

    private static func simple(
        _ themed: ReplayThemedColor,
        theme: ReplayEnvironmentTheme,
        roughness: Float = 0.75
    ) -> SimpleMaterial {
        SimpleMaterial(
            color: color(themed, theme: theme),
            roughness: .init(floatLiteral: roughness),
            isMetallic: false
        )
    }

    private static func color(_ themed: ReplayThemedColor, theme: ReplayEnvironmentTheme) -> NSColor {
        let hex = themed.hex(for: theme)
        return NSColor(
            calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}
